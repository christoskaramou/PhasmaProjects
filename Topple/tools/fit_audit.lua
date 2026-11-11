-- Does every domino stand on something? For each room, the cooked meshes the game draws are read (Assets/Objects/
-- <piece>.pemesh) and every buildable surface in rooms/<id>.lua (free_room.lua for the living room) is sampled on a
-- grid: the mesh's top under each point against the surface's height. Then every challenge def's Start, End, presets,
-- props, goal and traps, and every scripted solution's dominoes, are checked the same way at their own spots.
--
--   luajit tools/fit_audit.lua [room ...]        (from the Topple folder; prints one line per surface, FLAG on the bad)
--
-- gap: the surface is above the mesh (a domino would float); sink: the mesh is above the surface (a domino would stand
-- inside it); bare: the share of the surface with no mesh under it near its height. Flagged over TOL or over BARE.
-- The rooms' surfaces and solids are the contract (the boards are laid on them): a flagged piece is fixed by fitting
-- its model (tools/house_rooms.py `fit`), never by moving the surface.
local ffi = require("ffi")
local A = {}
A.TOL, A.BARE, A.STEP, A.INSET = 0.15, 0.05, 0.5, 0.3
A.ROOMS = { "hall", "living", "kitchen", "dining", "kids", "bath", "study", "attic" }

------------------------------------------------------------------ the cooked meshes
local function u32(p, o) return ffi.cast("uint32_t*", p + o)[0] end
-- Triangles of a .pemesh in table axes (x, y, h): the engine's (x, h, -y). nil when the file is missing.
function A.read_pemesh(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    local p = ffi.cast("const uint8_t*", s)
    assert(s:sub(1, 4) == "PEMS", path .. ": not a cooked mesh")
    local vsz, pusz, absz = u32(p, 12), u32(p, 16), u32(p, 20)
    local streams, meshes = u32(p, 24), u32(p, 28)
    local off, blob = 48 + streams * 16, {}
    for i = 0, streams - 1 do
        local d = 48 + i * 16
        blob[u32(p, d)] = { off = off, stride = u32(p, d + 4), count = u32(p, d + 8) }
        off = off + u32(p, d + 12)
    end
    local V, I = blob[0], blob[3]
    assert(V and I and V.stride == vsz, path .. ": unexpected streams")
    local tris = {}
    local rec = off
    for m = 0, meshes - 1 do
        local r = rec + m * 65
        local vo, io_, ic = u32(p, r), u32(p, r + 8), u32(p, r + 12)
        local fp = ffi.cast("const float*", p + V.off)
        local ip = ffi.cast("const uint32_t*", p + I.off)
        for t = 0, ic / 3 - 1 do
            local tri = {}
            for k = 0, 2 do
                local vi = vo + ip[io_ + t * 3 + k]
                local b = vi * (vsz / 4)
                tri[#tri + 1] = fp[b]; tri[#tri + 1] = -fp[b + 2]; tri[#tri + 1] = fp[b + 1]
            end
            tris[#tris + 1] = tri
        end
    end
    return tris
end

-- A room's drawn furniture and props as one grid of triangles, for "what is the top under (x, y), at or below zmax".
function A.scene(room, objects)
    local G, cell = {}, 1.0
    local function key(i, j) return i * 100003 + j end
    local n = 0
    for _, L in ipairs(room.pieces) do
        if not L.challenge and not L.trap and not L.goal then     -- (a goal object stands on the furniture; it is no ground)
            local tris = A.read_pemesh(objects .. "/" .. L.name .. ".pemesh")
            for _, t in ipairs(tris or {}) do
                local x0, x1 = math.min(t[1], t[4], t[7]), math.max(t[1], t[4], t[7])
                local y0, y1 = math.min(t[2], t[5], t[8]), math.max(t[2], t[5], t[8])
                local d = (t[4] - t[1]) * (t[8] - t[2]) - (t[7] - t[1]) * (t[5] - t[2])
                if math.abs(d) > 1e-9 then
                    t.d = d
                    for i = math.floor(x0 / cell), math.floor(x1 / cell) do
                        for j = math.floor(y0 / cell), math.floor(y1 / cell) do
                            local k = key(i, j)
                            local c = G[k]
                            if not c then c = {}; G[k] = c end
                            c[#c + 1] = t
                        end
                    end
                    n = n + 1
                end
            end
        end
    end
    local S = { tris = n }
    function S.top(x, y, zmax)
        local c = G[key(math.floor(x / cell), math.floor(y / cell))]
        local best
        for _, t in ipairs(c or {}) do
            local a = ((t[4] - x) * (t[8] - y) - (t[7] - x) * (t[5] - y)) / t.d
            local b = ((t[7] - x) * (t[2] - y) - (t[1] - x) * (t[8] - y)) / t.d
            local g = 1 - a - b
            if a >= -1e-6 and b >= -1e-6 and g >= -1e-6 then
                local z = a * t[3] + b * t[6] + g * t[9]
                if z <= zmax and (not best or z > best) then best = z end
            end
        end
        return best
    end
    return S
end

------------------------------------------------------------------ the checks
-- One surface: max gap and sink over a grid inset from its edges, and the bare share. The mesh is looked for from
-- h + 1 down to h - 2 (a top much lower than that is no top for this surface).
function A.surface(S, s, solids)
    local gap, sink, bare, n = 0, 0, 0, 0
    local diffs = {}
    local w, d = s.x1 - s.x0 - 2 * A.INSET, s.y1 - s.y0 - 2 * A.INSET
    local nx, ny = math.max(1, math.floor(w / A.STEP + 0.5)), math.max(1, math.floor(d / A.STEP + 0.5))
    for i = 0, nx do
        for j = 0, ny do
            local x = s.x0 + A.INSET + (nx > 0 and w * i / nx or w / 2)
            local y = s.y0 + A.INSET + (ny > 0 and d * j / ny or d / 2)
            -- (a point under something standing on the surface - a book on a book, a lamp's foot - is no place for a
            -- domino: the rules' solids block it, so it is not sampled)
            local blocked = false
            for _, q in ipairs(solids or {}) do
                if q.z1 > s.h + 0.01 and q.z0 < s.h + 1 and x > q.x0 and x < q.x1 and y > q.y0 and y < q.y1 then blocked = true; break end
            end
            if not blocked then
                n = n + 1
                local z = S.top(x, y, s.h + 1)
                if not z or z < s.h - 2 then bare = bare + 1
                else
                    diffs[#diffs + 1] = s.h - z
                    if s.h - z > gap then gap = s.h - z end
                    if z - s.h > sink then sink = z - s.h end
                end
            end
        end
    end
    table.sort(diffs)
    return gap, sink, n > 0 and bare / n or 0, diffs[math.max(1, math.floor(#diffs / 2))] or 0
end

-- What a thing standing at (x, y) on height h stands on: nothing to check on the floor or a rug (h <= 0.2); else the
-- mesh's top there, from h + 0.5 down.
function A.spot(S, x, y, h)
    if h <= 0.2 then return 0, 0, false end
    local z = S.top(x, y, h + 0.5)
    if not z or z < h - 2 then return 0, 0, true end
    return math.max(0, h - z), math.max(0, z - h), false
end

-- Everything, for the rooms given (default all). Returns the lines and the count of flagged ones.
function A.run(ids, opts)
    opts = opts or {}
    local objects = opts.objects or "Assets/Objects"
    local F = dofile("Assets/Scripts/topple_free.lua")
    local lines, flagged = {}, 0
    local function put(bad, s) lines[#lines + 1] = (bad and "FLAG " or "     ") .. s; if bad then flagged = flagged + 1 end end
    local C
    for _, id in ipairs(ids or A.ROOMS) do
        local room = dofile(id == "living" and "Assets/Scripts/free_room.lua" or ("Assets/Scripts/rooms/" .. id .. ".lua"))
        local S = A.scene(room, objects)
        for _, s in ipairs(room.surfaces) do
            if s.h > 0.2 then
                local g, k, b, med = A.surface(S, s, room.solids)
                put(g > A.TOL or k > A.TOL or b > A.BARE, string.format("%-8s surface %-18s h %6.2f  gap %5.2f  sink %5.2f  median %+5.2f  bare %3.0f%%", id, s.name, s.h, g, k, med, b * 100))
            end
        end
        if not opts.surfaces_only then
            F.set_room(room)
            C = C or dofile("Assets/Scripts/topple_challenges.lua")(F)
            local defs = C.HOUSE[id] or {}
            local ok, sols = pcall(dofile, "tests/solutions/" .. id .. ".lua")
            for k, def in ipairs(defs) do
                local worst, what = 0, nil
                local bad_spots = {}
                -- (what the rules add under things that the room's meshes do not draw: props, a fragile stack's top,
                -- a ramp's steps; something standing on one of those stands on it, not in the air)
                local own = {}
                for _, s in ipairs(room.surfaces) do own[s] = true end
                local extra = {}
                local function supports(board)
                    extra = {}
                    for _, s in ipairs(board:all_surfaces()) do if not own[s] then extra[#extra + 1] = s end end
                    for _, pr in ipairs(def.props or {}) do extra[#extra + 1] = { x0 = pr.x0, x1 = pr.x1, y0 = pr.y0, y1 = pr.y1, h = pr.z1 } end
                end
                local function held(x, y, h)
                    for _, s in ipairs(extra) do
                        if math.abs(s.h - h) < 0.05 and x >= s.x0 - 0.05 and x <= s.x1 + 0.05 and y >= s.y0 - 0.05 and y <= s.y1 + 0.05 then return true end
                    end
                end
                local function at(label, x, y, h)
                    if held(x, y, h) then return end
                    local g, s_, bare = A.spot(S, x, y, h)
                    local e = math.max(g, s_)
                    if bare or e > A.TOL then bad_spots[#bad_spots + 1] = string.format("%s (%.1f, %.1f, %.2f) %s", label, x, y, h, bare and "on nothing" or string.format("gap %.2f sink %.2f", g, s_)) end
                    if e > worst then worst, what = e, label end
                end
                local b = C.new_board(def)
                supports(b)
                for _, p in pairs(b.pieces) do at(p.id == b.start_piece and "start" or p.id == b.end_piece and "end" or "preset", p.x, p.y, p.z) end
                for _, pr in ipairs(def.props or {}) do
                    -- (a prop stands on whatever is under any part of it: a board on two jars, a ruler or bridge laid level
                    -- with the tops it spans between; a bath caddy is drawn hanging by a lip at each end down to what is
                    -- under that end (topple_free_world draw_prop), so each end must have something under it, at most 1 down)
                    local best
                    local z0 = pr.z0 or 0
                    if (pr.name or ""):lower():find("caddy", 1, true) then
                        local along_y = (pr.y1 - pr.y0) >= (pr.x1 - pr.x0)
                        best = 0
                        for _, e in ipairs({ -1, 1 }) do
                            local ex = along_y and (pr.x0 + pr.x1) / 2 or (e < 0 and pr.x0 + 0.14 or pr.x1 - 0.14)
                            local ey = along_y and (e < 0 and pr.y0 + 0.14 or pr.y1 - 0.14) or (pr.y0 + pr.y1) / 2
                            local z = S.top(ex, ey, z0)
                            local e_ = (not z or z < z0 - 1) and 99 or 0
                            if e_ > best then best = e_ end
                        end
                    else
                        for x = pr.x0 + 0.02, pr.x1 - 0.02 + 1e-9, math.max(0.1, (pr.x1 - pr.x0 - 0.04) / 8) do
                            for y = pr.y0 + 0.02, pr.y1 - 0.02 + 1e-9, math.max(0.1, (pr.y1 - pr.y0 - 0.04) / 8) do
                                local e
                                if held(x, y, z0) then e = 0
                                else
                                    local g, s_, bare = A.spot(S, x, y, z0)
                                    e = bare and 99 or math.max(g, s_)
                                end
                                if not best or e < best then best = e end
                            end
                        end
                    end
                    if best > A.TOL then bad_spots[#bad_spots + 1] = string.format("prop %s (z0 %.2f) %s", tostring(pr.name), pr.z0 or 0, best >= 99 and "on nothing" or string.format("off by %.2f", best)) end
                    if best < 99 and best > worst then worst, what = best, "prop " .. tostring(pr.name) end
                end
                if def.goal and def.goal.x then at("goal", def.goal.x, def.goal.y, def.goal.h or 0) end
                for _, tr in ipairs(def.traps or {}) do
                    if tr.x0 and tr.z0 then at("trap " .. tr.id, (tr.x0 + tr.x1) / 2, (tr.y0 + tr.y1) / 2, tr.z0)
                    elseif tr.kind == "plank" then at("trap " .. tr.id, tr.x, tr.y, tr.h)
                    end                       -- (a string's pegs are drawn down to whatever is under them)
                end
                local sol = ok and sols[k]
                local solve = type(sol) == "function" and sol or (type(sol) == "table" and sol.solve)
                local nd = 0
                if solve then
                    local sb = C.new_board(def)
                    solve(sb, F)
                    supports(sb)
                    for _, p in pairs(sb.pieces) do nd = nd + 1; at("domino", p.x, p.y, p.z) end
                    for _, p in pairs(sb.balls) do at("ball", p.x, p.y, p.z) end
                end
                put(#bad_spots > 0, string.format("%-8s level %d %-16s worst %.2f (%s), %d solution dominoes%s", id, k, def.id, worst, what or "-", nd,
                    #bad_spots > 0 and (": " .. table.concat(bad_spots, "; ", 1, math.min(4, #bad_spots)) .. (#bad_spots > 4 and (" +" .. (#bad_spots - 4)) or "")) or ""))
            end
        end
    end
    return lines, flagged
end

if arg and arg[0] and arg[0]:match("fit_audit%.lua$") then
    local ids = #arg > 0 and { unpack(arg) } or nil
    local lines, flagged = A.run(ids)
    for _, l in ipairs(lines) do print(l) end
    print(string.format("%d flagged of %d", flagged, #lines))
    os.exit(flagged == 0 and 0 or 1)
end
return A
