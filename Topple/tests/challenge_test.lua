-- House Challenges: run from the Topple folder with luajit. For every room with a Scripts/challenges/<room>.lua, its
-- three levels are checked and the scripted runs in tests/solutions/<room>.lua replayed: Start and End stand and the End
-- sets off the goal; an empty build meets nothing; the solution meets the Start-to-End requirement within budget and
-- does not with its trap-avoiding step left out; every challenge is earned by a run that meets the requirement and
-- missed by another that also meets it; a run started anywhere but Start earns nothing; only unlocked tools and sizes.
--
-- tests/solutions/<room>.lua returns a list of 3 entries in the same order as the levels. Each is either
--   function(board, F)                      the solution (enough for level 1), or
--   { solve = function(board, F), without = function(board, F),
--     objectives = { [challenge id] = function(board, F) }, misses = { [challenge id] = function(board, F) } }
-- where without is the solution with its trap-avoiding step left out (required for levels 2 and 3: it must not meet
-- the requirement), objectives are runs that earn a challenge the solution does not, and misses are runs that meet the
-- requirement but miss a challenge. The harness adds its own misses: the solution plus dominoes left standing far from
-- the route (for thrift and all_fall), plus an unused gadget (without), plus a standing domino in the box (avoid).
local F = dofile("Assets/Scripts/topple_free.lua")
local LIVING = dofile("Assets/Scripts/free_room.lua")
F.set_room(LIVING)
local C = dofile("Assets/Scripts/topple_challenges.lua")(F)
local H = dofile("Assets/Scripts/topple_house.lua")
local checks = 0
-- TOPPLE_SOFT=1 prints every failed check and carries on (for authoring); normally the first one stops the run.
local SOFT, failed = os.getenv("TOPPLE_SOFT"), 0
local function check(v, msg)
    if not v and SOFT then print("FAIL " .. tostring(msg)); failed = failed + 1; return end
    assert(v, msg); checks = checks + 1
end
local function exists(path) local f = io.open(path, "rb"); if f then f:close(); return true end return false end
local ROOMS = { living = LIVING }
local function room_data(id)
    ROOMS[id] = ROOMS[id] or dofile("Assets/Scripts/rooms/" .. id .. ".lua")
    return ROOMS[id]
end

-- What each room may use: the tools and sizes it and the rooms before it unlock (erase and start always).
local open_tools, open_sizes, unlocks = {}, {}, {}
do
    local tools, sizes = { erase = true, start = true }, { [2] = true }
    for _, r in ipairs(H.ROOMS) do
        for _, t in ipairs(r.unlocks.tools or {}) do tools[t] = true end
        for _, z in ipairs(r.unlocks.sizes or {}) do sizes[z] = true end
        local t2, z2 = {}, {}
        for k in pairs(tools) do t2[k] = true end
        for k in pairs(sizes) do z2[k] = true end
        open_tools[r.id], open_sizes[r.id], unlocks[r.id] = t2, z2, r.unlocks
    end
end
local GADGET_TOOL = { ball = "ball", swing = "swing", switch = "switch", ramp = "ramp" }
local function overlap(a, b)
    return a.x1 > b.x0 + 0.01 and a.x0 < b.x1 - 0.01 and a.y1 > b.y0 + 0.01 and a.y0 < b.y1 - 0.01 and a.z1 > b.z0 + 0.01 and a.z0 < b.z1 - 0.01
end

-- One run: a fresh board for the level, built by fn (then extra(board), which returns false if it found no room),
-- simulated and judged.
local function play(def, fn, extra)
    local b = C.new_board(def)
    fn(b, F)
    if extra and not extra(b) then return nil end
    local res = F.simulate(b)
    local done, met, run = C.evaluate(b, res)
    local set = {}
    for _, id in ipairs(done) do set[id] = true end
    return { b = b, res = res, done = done, set = set, met = met, why = run.why, used = run.used, t = run.t_end }
end
-- Nothing of the run within r of (x, y): no piece, gadget, ramp or trap.
local function clear(b, x, y, r)
    local hit = false
    b:near(x, y, r, function() hit = true end)
    for _, list in ipairs({ b.balls, b.switches, b.swings }) do
        for _, q in pairs(list) do if (q.x - x) ^ 2 + (q.y - y) ^ 2 < r * r then hit = true end end
    end
    for _, rp in pairs(b.ramps) do
        local ax, ay, bx, by = rp.x0 or rp.x, rp.y0 or rp.y, rp.x1 or rp.x, rp.y1 or rp.y
        if ax and math.min((ax - x) ^ 2 + (ay - y) ^ 2, (bx - x) ^ 2 + (by - y) ^ 2) < (r + 6) ^ 2 then hit = true end
    end
    for _, tr in ipairs(b.trap_order) do
        local x0, x1, y0, y1 = tr.x0 or tr.x, tr.x1 or tr.x, tr.y0 or tr.y, tr.y1 or tr.y
        if tr.a and tr.b then x0, x1, y0, y1 = math.min(tr.a[1], tr.b[1]), math.max(tr.a[1], tr.b[1]), math.min(tr.a[2], tr.b[2]), math.max(tr.a[2], tr.b[2]) end
        if x0 and x > x0 - r and x < x1 + r and y > y0 - r and y < y1 + r then hit = true end
    end
    return not hit
end
-- n spots on the floor far from everything, each handed to put(x, y) until n are taken.
local function far(b, n, put)
    local B, got = F.ROOM.bounds, 0
    for y = B.y0 + 2, B.y1 - 2, 1.9 do
        for x = B.x0 + 2, B.x1 - 2, 1.9 do
            if got >= n then return true end
            if clear(b, x, y, 4) and put(x, y) then got = got + 1 end
        end
    end
    return got >= n
end
-- The harness's own misses for a level (see the top): each { name, extra } adds something to the solution.
local function auto_misses(def, used)
    local out = {}
    local thrift
    for _, c in ipairs(def.challenges) do if c.kind == "thrift" then thrift = c.n end end
    local pad = math.max(1, (thrift or used) - used + 1)
    if used + pad <= def.budget.domino then
        out[#out + 1] = { "+" .. pad .. " standing", function(b)
            return far(b, pad, function(x, y) return b:place(x, y, 0, 0, "cream") end)
        end }
    end
    for _, c in ipairs(def.challenges) do
        if c.kind == "without" then
            out[#out + 1] = { "+ an unused " .. c.gadget, function(b)
                return far(b, 1, function(x, y)
                    if c.gadget == "switch" then return b:place_switch(x, y, 0) end
                    if c.gadget == "ball" then return b:place_ball(x, y, 0) end
                    if c.gadget == "mini" then return b:place(x, y, 0, 0, "cream", F.SIZES[1]) end
                end)
            end }
        elseif c.kind == "avoid" then
            out[#out + 1] = { "+ one in the " .. c.what, function(b)
                local B = c.box
                for y = B[3] + 0.6, B[4] - 0.6, 0.7 do
                    for x = B[1] + 0.6, B[2] - 0.6, 0.7 do
                        if clear(b, x, y, 2.5) then
                            for _, sf in ipairs(F.surfaces_at(x, y, 0, b:all_surfaces(), 1)) do
                                if (not B[5] or (sf.h >= B[5] and sf.h <= B[6])) and b:place(x, y, 0, sf.h, "cream") then return true end
                            end
                        end
                    end
                end
                return false
            end }
        end
    end
    return out
end

local table_rows, ids_seen, skipped = {}, {}, {}
local two_runs           -- a level and two of its runs that each earn a challenge the other does not (for the House)
for _, rid in ipairs(C.ROOM_IDS) do
    local list = C.HOUSE[rid]
    local spath = "tests/solutions/" .. rid .. ".lua"
    if not list then
        skipped[#skipped + 1] = rid
    else
        check(#list == 3, rid .. ": three levels, has " .. #list)
        check(C.MAPS[C.map_of(rid)].list == list, rid .. ": filed under map " .. C.map_of(rid))
        check(exists(spath), rid .. ": has its solutions file " .. spath)
        local sols = dofile(spath)
        check(type(sols) == "table" and #sols == 3, rid .. ": three solutions")
        F.set_room(room_data(rid))
        local room_goal
        for tier, def in ipairs(list) do
            local id = tostring(def.id)
            local sol = sols[tier]
            local solve = type(sol) == "function" and sol or (type(sol) == "table" and sol.solve)
            local without = type(sol) == "table" and sol.without or nil
            check(not ids_seen[id], id .. ": ids are unique across the House")
            ids_seen[id] = true
            check(def.room == rid and def.tier == tier, id .. ": room " .. tostring(def.room) .. " tier " .. tostring(def.tier))
            check(C.find(id) == def and C.find(C.map_of(rid), id) == def, id .. ": found by id")
            for _, f in ipairs({ "name", "brief", "goal_word", "win", "fail" }) do check(type(def[f]) == "string", id .. ": has " .. f) end
            check(def.budget and def.budget.domino, id .. ": has a budget")
            -- The room's End and goal: every level of a room sets off the same goal.
            check(def.finish and def.goal, id .. ": has an End and a goal")
            local gkey = def.goal.preset or (def.goal.x .. "," .. def.goal.y .. "," .. def.goal.h)
            room_goal = room_goal or gkey
            check(room_goal == gkey, id .. ": the room's levels share one goal")
            -- Challenges: tier + 1 of them (2, 3, 4), whole, each id and kind once.
            local cs = def.challenges
            check(type(cs) == "table" and #cs == tier + 1, id .. ": level " .. tier .. " has " .. (tier + 1) .. " challenges")
            local cids, kinds = {}, {}
            for _, c in ipairs(cs) do
                check(type(c.id) == "string" and type(c.name) == "string" and type(c.brief) == "string" and type(c.test) == "function", id .. ": a whole challenge")
                check(not cids[c.id], id .. ": challenge ids are unique, " .. c.id)
                check(not kinds[c.kind], id .. ": no two challenges of one kind (the same test with other numbers), " .. tostring(c.kind))
                cids[c.id], kinds[c.kind] = true, true
                if c.kind == "without" and GADGET_TOOL[c.gadget] then
                    check((def.budget[c.gadget] or 0) > 0, id .. ": doing without a " .. c.gadget .. " means the budget has one")
                end
                if c.kind == "thrift" then check(c.n < def.budget.domino, id .. ": the thrift challenge is under the budget") end
            end
            -- The camera (as the view reads it: an orbit of dist at yaw and pitch about x, y, h; 40 degrees high,
            -- here 16:9). An eye within the walls is under the ceiling, or an attic's roof, by 3. One outside them
            -- looks in through the one-sided walls, but not in the attic: its roof beams stay. Start and End in view.
            do
                local c, R = def.camera, room_data(rid)
                check(c and c.x and c.y and c.h and c.yaw and c.pitch and c.dist, id .. ": has a camera")
                local rd, cp = math.pi / 180, math.cos(c.pitch * math.pi / 180)
                local ex, ey, eh = c.x + c.dist * cp * math.cos(c.yaw * rd), c.y + c.dist * cp * math.sin(c.yaw * rd), c.h + c.dist * math.sin(c.pitch * rd)
                local B = R.bounds
                local inside = ex > B.x0 and ex < B.x1 and ey > B.y0 and ey < B.y1
                local top = R.knee_h and R.knee_h + (B.y1 - math.abs(ey)) * (R.wall_h - R.knee_h) / B.y1 or R.wall_h or 48
                check(inside and eh <= top - 3 or (not inside and not R.knee_h), string.format("%s: the camera's eye (%.1f, %.1f, %.1f) is under the roof (%.1f) or outside the walls", id, ex, ey, eh, top))
                local cb = C.new_board(def)
                local fx, fy, fh = c.x - ex, c.y - ey, c.h - eh
                local n = math.sqrt(fx * fx + fy * fy + fh * fh)
                fx, fy, fh = fx / n, fy / n, fh / n
                local rx, ry = -math.sin(c.yaw * rd), math.cos(c.yaw * rd)
                local ux, uy, uh = ry * fh, -rx * fh, rx * fy - ry * fx
                local tv = math.tan(20 * rd)
                for _, pid in ipairs({ cb.start_piece, cb.end_piece }) do
                    local p = cb.pieces[pid]
                    local dx, dy, dh = p.x - ex, p.y - ey, p.z - eh
                    local w = dx * fx + dy * fy + dh * fh
                    check(w > 0 and math.abs(dx * rx + dy * ry) / w <= tv * 16 / 9 * 0.9 and math.abs(dx * ux + dy * uy + dh * uh) / w <= tv * 0.9,
                        string.format("%s: the camera sees piece %d at (%.1f, %.1f)", id, pid, p.x, p.y))
                end
            end
            -- Tools, sizes and gadgets: only what this room and the ones before it unlock.
            check(type(def.tools) == "table", id .. ": lists its tools")
            for _, t in ipairs(def.tools) do check(open_tools[rid][t], id .. ": tool " .. t .. " is not unlocked by " .. rid .. " or before") end
            for _, z in ipairs(def.sizes or C.DEFAULT_SIZES) do check(open_sizes[rid][z], id .. ": size " .. z .. " is not unlocked yet") end
            for k, v in pairs(def.budget) do
                if GADGET_TOOL[k] and v > 0 then check(open_tools[rid][GADGET_TOOL[k]] and C.allows(def, GADGET_TOOL[k]), id .. ": a " .. k .. " it cannot place") end
            end
            if tier == 1 then
                local u = unlocks[rid]
                local mine = false
                for _, t in ipairs(u.tools or {}) do if t == def.unlock and C.allows(def, t) then mine = true end end
                if def.unlock == "mini" then mine = C.allows_size(def, 1) and (u.sizes or {})[1] == 1 end
                check(mine, id .. ": level 1 unlocks (and uses) the room's tool, unlock = " .. tostring(def.unlock))
                check(not def.traps or #def.traps == 0, id .. ": level 1 has no trap")
            else
                check(def.unlock == nil, id .. ": only level 1 unlocks")
                check(def.traps and #def.traps > 0, id .. ": levels 2 and 3 have the room's trap")
            end
            -- Props clear of furniture, walls and each other.
            for i, pr in ipairs(def.props or {}) do
                for _, s in ipairs(F.ROOM.solids) do check(not overlap(pr, s), id .. ": prop " .. tostring(pr.name) .. " is inside " .. s.name) end
                for j = i + 1, #def.props do check(not overlap(pr, def.props[j]), id .. ": props overlap") end
            end

            -- Start and End stand (C.new_board asserts they fit), locked; the End's fall alone sets off the goal.
            local empty = C.new_board(def)
            local sp, ep = empty.pieces[empty.start_piece], empty.pieces[empty.end_piece]
            check(sp and sp.fixed and ep and (ep.fixed or ep.preset), id .. ": Start and End are locked dominoes")
            check(empty.limits.domino == def.budget.domino + empty.locked_count and C.used(empty) == 0, id .. ": Start and End are outside the budget")
            local alone = C.new_board(def)
            alone.start = { id = alone.end_piece, dir = 1 }
            local ar = F.simulate(alone)
            local fired = alone.goal_piece and ar.falls[alone.goal_piece] ~= nil
            for _, e in ipairs(ar.switches) do if e.id == alone.goal_id then fired = true end end
            check(fired, id .. ": the End's fall sets off the goal")
            -- An empty build: Start falls, the End does not: nothing met, nothing earned.
            local er = F.simulate(empty)
            local edone, emet = C.evaluate(empty, er)
            check(not emet and #edone == 0 and not C.won(empty, er) and C.stars(def, 0, false) == 0, id .. ": an empty build meets nothing and earns nothing")

            -- The solution: meets the requirement within budget; without its trap-avoiding step it does not.
            check(type(solve) == "function", id .. ": has a solution")
            local main = play(def, solve)
            check(main.met, id .. ": the solution gets from Start to End, why not: " .. tostring(main.why))
            check(main.used <= def.budget.domino, id .. ": the solution fits the budget, used " .. main.used)
            local wtxt = "-"
            if tier > 1 then
                check(type(without) == "function", id .. ": names its trap-avoiding step (solutions entry { solve, without })")
                local wr = play(def, without)
                check(not wr.met, id .. ": without its trap-avoiding step it does not reach the End last")
                wtxt = string.format("%s, %d of %d fell", wr.why or "?", wr.res.toppled, wr.b.count)
            end
            -- Every run: the solution, the scripted ones, the harness's own misses.
            local runs = { { name = "solution", r = main } }
            for cid, fn in pairs(type(sol) == "table" and sol.objectives or {}) do
                check(cids[cid], id .. ": objectives names a challenge it has, " .. cid)
                local r = play(def, fn)
                check(r.met and r.set[cid], id .. ": the run for " .. cid .. " meets the requirement and earns it, met " .. tostring(r.met) .. " " .. tostring(r.why))
                runs[#runs + 1] = { name = "for " .. cid, r = r }
            end
            for cid, fn in pairs(type(sol) == "table" and sol.misses or {}) do
                check(cids[cid], id .. ": misses names a challenge it has, " .. cid)
                local r = play(def, fn)
                check(r.met and not r.set[cid], id .. ": the run built to miss " .. cid .. " meets the requirement and misses it, met " .. tostring(r.met) .. " " .. tostring(r.why))
                runs[#runs + 1] = { name = "missing " .. cid, r = r }
            end
            for _, m in ipairs(auto_misses(def, main.used)) do
                local r = play(def, solve, m[2])
                check(r, id .. ": room for the harness's run, the solution " .. m[1])
                check(r.met, id .. ": the solution " .. m[1] .. " still meets the requirement, " .. tostring(r.why))
                runs[#runs + 1] = { name = "solution " .. m[1], r = r }
            end
            local earned_by, missed_by = {}, {}
            for _, c in ipairs(cs) do
                for _, run in ipairs(runs) do
                    if run.r.met and run.r.set[c.id] then earned_by[c.id] = earned_by[c.id] or run.name end
                    if run.r.met and not run.r.set[c.id] then missed_by[c.id] = missed_by[c.id] or run.name end
                end
                check(earned_by[c.id], id .. ": challenge " .. c.id .. " is earned by a run that meets the requirement")
                check(missed_by[c.id], id .. ": challenge " .. c.id .. " is missed by a run that meets the requirement")
            end
            for _, r1 in ipairs(runs) do
                for _, r2 in ipairs(runs) do
                    for c1 in pairs(r1.r.set) do
                        for c2 in pairs(r2.r.set) do
                            if not two_runs and not r2.r.set[c1] and not r1.r.set[c2] then two_runs = { def = def, a = r1.r, b = r2.r, ca = c1, cb = c2 } end
                        end
                    end
                end
            end
            -- Started anywhere but Start, the same build earns nothing, though its chain still reaches the End.
            local moved = play(def, solve, function(b)
                local first
                for _, p in pairs(b.pieces) do
                    local f = main.res.falls[p.id]
                    if not p.fixed and not p.preset and f and (not first or f.t < main.res.falls[first.id].t) then first = p end
                end
                if not first then return false end
                b.start = { id = first.id, dir = 1 }
                return true
            end)
            check(moved and moved.res.falls[moved.b.end_piece] and not moved.met and #moved.done == 0, id .. ": a run from a domino that is not Start earns nothing")
            -- C.won hands the run to C.stars: the stars of this run are the challenges it earned.
            local hb = C.new_board(def)
            solve(hb, F)
            local hres = F.simulate(hb)
            check(C.won(hb, hres) and C.stars(def, C.used(hb), true) == #main.done, id .. ": C.won and C.stars agree with C.evaluate")

            -- Locked pieces survive erasing, clearing and removing; the switch tool cannot pick the goal.
            local locked = C.new_board(def)
            local presets, kept = locked.preset_count, locked.count
            for _, pid in ipairs({ locked.start_piece, locked.end_piece }) do
                local p = locked.pieces[pid]
                check(locked:remove(pid) == nil, id .. ": Start and End are locked")
                locked:erase_at(p.x, p.y, p.z, 2)
            end
            if locked.goal_id then
                local goal = locked.switches[locked.goal_id]
                check(goal.fixed and goal.goal == id and locked:remove(goal.id) == nil, id .. ": the goal is locked")
                locked:erase_at(goal.x, goal.y, goal.z, 2)
                check(locked:pick_switch(goal.x, goal.y, goal.z) == nil, id .. ": the goal cannot be rewired")
            else
                local gp = locked.pieces[locked.goal_piece]
                locked:erase_at(gp.x, gp.y, gp.z, 3)
            end
            locked:clear()
            check(locked.count == kept and locked.preset_count == presets and locked.switch_count == (locked.goal_id and 1 or 0)
                and #locked.trap_order == #(def.traps or {}), id .. ": erase and clear leave the locked pieces, presets and traps")

            -- The budget: dominoes stop at it, and gadgets it has none of cannot be placed.
            local full, n = C.new_board(def), 0
            local B = F.ROOM.bounds
            for y = B.y0 + 1, B.y1 - 1, 1.2 do
                for x = B.x0 + 1, B.x1 - 1, 1.2 do
                    if n < def.budget.domino + 5 and full:place(x, y, 0, 0, "cream") then n = n + 1 end
                end
            end
            check(n == def.budget.domino and C.used(full) == def.budget.domino, id .. ": dominoes stop at the budget, placed " .. n)
            local _, why = full:place(0, 0, 0, 0, "cream")
            check(why == "full", id .. ": over budget says full, got " .. tostring(why))
            if (def.budget.ball or 0) == 0 then
                local _, w = C.new_board(def):place_ball(0, 0, 0)
                check(w == "full", id .. ": no balls in this budget")
            end
            if (def.budget.ramp or 0) == 0 then
                local _, w = C.new_board(def):place_ramp(0, 0, 0, 0, 5, 1)
                check(w == "full", id .. ": no ramps in this budget")
            end
            local ctxt = {}
            for _, c in ipairs(cs) do
                local num = c.n and (" " .. c.n) or c.t and (" " .. c.t .. "s") or c.trap and (" " .. c.trap) or c.gadget and (" " .. c.gadget) or c.what and (" " .. c.what) or ""
                ctxt[#ctxt + 1] = c.kind .. num .. (earned_by[c.id] == "solution" and "" or "*")
            end
            table_rows[#table_rows + 1] = { rid, tier, id, main.used, def.budget.domino, main.t or 0, table.concat(ctxt, "; "), wtxt }
        end
    end
end
F.set_room(LIVING)
check(C.MAPS.hall and C.MAPS.hall.name == "The Great Hall" and #C.MAPS.hall.list == 0, "the Great Hall keeps its map")
check(C.MAPS.room and C.MAPS.room.name == "The Living Room", "the living room keeps the map id room")
local by = H.sort_defs(C.MAPS)
for _, rid in ipairs(C.ROOM_IDS) do
    for k = 1, 3 do check((by[rid][k] ~= nil) == (C.HOUSE[rid] ~= nil), rid .. ": the House sorts its tier " .. k) end
end
print(string.format("  %-8s %-2s %-16s %4s %4s %5s  %s", "room", "lv", "id", "used", "bdgt", "End s", "challenges (* earned by another run than the solution)"))
for _, r in ipairs(table_rows) do print(string.format("  %-8s %-2d %-16s %4d %4d %5.2f  %s", r[1], r[2], r[3], r[4], r[5], r[6], r[7])) end
print("  skipped (no challenges file yet): " .. (#skipped > 0 and table.concat(skipped, ", ") or "none"))
-- The first room that has challenges, its easy def and that def's solution (for the checks below).
local function any_def()
    for _, rid in ipairs(C.ROOM_IDS) do
        if C.HOUSE[rid] then
            local s = dofile("tests/solutions/" .. rid .. ".lua")[1]
            return C.HOUSE[rid][1], rid, type(s) == "function" and s or s.solve
        end
    end
end

-- Free Build keeps its own limits.
local free = F.new_board()
check(free:limit("domino", F.CAP) == F.CAP and free:limit("ball", 64) == 64, "no budget outside a challenge")

local function paint() return "cream" end
-- Stars and progress. An old def (no challenges) still earns 1-3 stars by domino count.
local def = { id = "old_style", budget = { domino = 10 }, stars = { 4, 3 } }
check(C.stars(def, 3, true) == 3 and C.stars(def, 4, true) == 2 and C.stars(def, 5, true) == 1 and C.stars(def, 3, false) == 0, "an old def's stars by count")
-- A level's stars: one per challenge it holds; a room's: the sum; an old save's n stars: cleared and n - 1 done.
local lv3 = C.HOUSE.hall[3]
local all = {}
for _, c in ipairs(lv3.challenges) do all[c.id] = true end
check(C.level_stars(lv3, all) == 4 and C.level_stars(lv3, {}) == 0 and C.level_stars(lv3, nil) == 0, "a level's stars count its challenges done")
check(C.level_stars(lv3, { [lv3.challenges[1].id] = true, nope = true }) == 1, "and only its own")
local by_level = { [lv3.id] = all, [C.HOUSE.hall[1].id] = { [C.HOUSE.hall[1].challenges[2].id] = true } }
check(C.room_stars("hall", by_level) == 5 and C.room_stars("attic", {}) == 0, "a room's stars are its levels' sum")
local m3, m1 = C.migrate(lv3, 3), C.migrate(C.HOUSE.hall[1], 3)
check(m3[lv3.challenges[1].id] and m3[lv3.challenges[2].id] and not m3[lv3.challenges[3].id], "an old 3 stars: the first two challenges")
check(C.level_stars(C.HOUSE.hall[1], m1) == 2 and next(C.migrate(lv3, 1)) == nil, "capped at the level's, and 1 star is a clear alone")
-- Stars persist: two runs that each earn a challenge the other does not; the House keeps both.
check(two_runs, "some level has two runs that earn different challenges")
local house = H.new(C.MAPS)
local tr = two_runs
local _, news = house:record(tr.def.id, { met = true, done = tr.a.done }, tr.a.used)
local after1 = house:stars_for(tr.def.id)
check(after1 == #tr.a.done and house:done(tr.def.id, tr.ca) and not house:done(tr.def.id, tr.cb), "the first run's stars, " .. after1)
house:record(tr.def.id, { met = true, done = tr.b.done }, tr.b.used)
check(house:done(tr.def.id, tr.ca) and house:done(tr.def.id, tr.cb) and house:stars_for(tr.def.id) > after1, "the second run adds its own and keeps the first's")
house:record(tr.def.id, { met = false, done = {} }, 1)
check(house:done(tr.def.id, tr.ca) and house:done(tr.def.id, tr.cb), "a failed run takes nothing away")

-- The requirement on a scene of its own (the living room): Start, a line to the End, and a side branch: the line cuts a
-- string, the weight it held drops on the head of a second line (one domino tips only the next, so a branch needs
-- something like this). A long branch is still falling after the End: not met; shortened, it is.
do
    local SB = C.normalize({ id = "test_branch", room = "living", tier = 2, name = "Branch", budget = { domino = 80 },
        start = { x = -20, y = -28, h = 0, a = 0 }, finish = { x = 0, y = -28, h = 0, a = 0 }, goal = { x = 0.9, y = -28, h = 0 },
        traps = { { kind = "weight", id = "w", x = -15, y = -22, h = 1.5, r = 0.6 },
            { kind = "string", id = "s", a = { -17, -29.5, 0.6 }, b = { -17, -26.5, 0.6 }, holds = "w" } },
        challenges = { { kind = "thrift", n = 60 }, { kind = "all_fall" } } })
    local function build(to_y)
        return function(b)
            b:place_line(-19.38, -28, -0.62, -28, paint, 0)
            if to_y then
                assert(b:place(-15, -22, math.pi / 2, 0, "cream"), "the branch's head, under the weight")
                b:place_line(-15, -21.38, -15, to_y, paint, 0)
            end
        end
    end
    local line, long, short = play(SB, build(nil)), play(SB, build(-4)), play(SB, build(-18))
    check(line.met and line.set.thrift and line.set.all_fall, "the line alone meets it, " .. tostring(line.why))
    check(not long.met and long.why == "after" and long.res.falls[long.b.end_piece] and #long.done == 0, "a branch that finishes after the End fails it, " .. tostring(long.why))
    check(short.met and short.set.all_fall, "the same branch shortened meets it, " .. tostring(short.why))
    -- A domino left standing does not matter.
    local stand = play(SB, build(nil), function(b) return b:place(-10, -20, 0, 0, "cream") ~= nil end)
    check(stand.met and not stand.set.all_fall, "a domino left standing does not fail it (it misses all_fall)")
end
local p = {}
check(C.record(p, "tv", 1, 80), "a first win is recorded")
check(not C.record(p, "tv", 0, 10), "a loss is not")
check(not C.record(p, "tv", 1, 85), "a worse win is not")
check(C.record(p, "tv", 1, 70) and C.record(p, "tv", 3, 75), "fewer dominoes, or more stars, are")
local back = C.load(C.dump(p))
check(back.tv.stars == 3 and back.tv.used == 75, "progress saves and loads")
check(next(C.load(nil)) == nil and next(C.load("garbage")) == nil, "a missing or bad file is no progress")

-- Global challenges, on real simulated builds wherever the room allows it.
check(#C.GLOBAL >= 10 and #C.GLOBAL <= 20, "10 to 20 global challenges")
local seen = {}
for _, g in ipairs(C.GLOBAL) do
    check(not seen[g.id] and g.name and g.brief and g.test, g.id .. ": unique and complete")
    seen[g.id] = true
end
local function stats(b, stars)
    local res, sw = F.simulate(b), 0
    for _, e in ipairs(res.switches) do if e.id ~= b.goal_id then sw = sw + 1 end end
    return { own = b.sample_rev ~= b.rev, fallen = res.toppled, total = res.total, duration = res.duration, balls = res.balls_launched,
        swings = res.swings_released, switches = sw, ramp = b.ramp_count > 0, stars = stars or 0 }, res
end
local function ids(list) local o = {}; for _, g in ipairs(list) do o[g.id] = true end; return o end
local base = { own = true, fallen = 0, total = 0, duration = 0, balls = 0, swings = 0, switches = 0, ramp = false, stars = 0 }
local function fresh() C.load_global("") end
local function paint() return "cream" end

fresh()
local sample = F.demo(F.new_board())
local st = stats(sample)
check(st.fallen >= 500 and not st.own and #C.award(st) == 0, "tipping the untouched sample earns nothing")
assert(sample:place(20, 12, 0, 0, "cream"), "room for one more")
check(stats(sample).own, "an edited sample is your own build")

fresh()
local short = F.new_board()
short:place_line(-30, -28, 30, -28, paint, 0)
st = stats(short)
local got = ids(C.award(st))
check(st.fallen == short.count and st.fallen > 90 and got.fell_25 and got.clean_50, "a line earns the first ones, fell " .. st.fallen)
check(not got.fell_500 and not got.ball and not got.long_30, "and only those")
check(C.award(st)[1] == nil, "a challenge is only earned once")
local count_after = C.global_count()
local again = C.dump_global()
C.load_global(again)
check(C.global_count() == count_after and C.global_done.fell_25, "global challenges save and load")
fresh(); check(C.global_count() == 0, "and start empty")

-- A hundred in under three seconds: a wide field fans out.
local fan = F.new_board()
fan:place_spots(F.field_spots(-30, -28, -14, -28, 8), F.field_paint, 0)
st = stats(fan)
check(ids(C.award(st)).fast_100, "a field is fast: " .. st.fallen .. " in " .. st.duration)
-- A big field.
fresh()
local big = F.new_board()
big:place_spots(F.field_spots(-26, -29, 26, -29, 9), F.field_paint, 0)
st = stats(big)
got = ids(C.award(st))
check(st.fallen >= 500 and got.fell_500, "a big field: " .. st.fallen .. " of " .. st.total)
-- Thirty seconds of single file.
local long = F.new_board()
long:place_spots(F.spiral_spots(22, 2.5, 38.5, 2.5), paint, 0)
st = stats(long)
check(ids(C.award(st)).long_30, "a long spiral runs " .. st.duration .. " s")

-- One run with all the gadgets (the same route is checked with real physics in the Player).
fresh()
local m = F.new_board()
local function ends(fn) local e; for _, p in pairs(m.pieces) do if fn(p) and (not e or p.order > e.order) then e = p end end; return e end
m:place_line(16.2, 12, 21.9, 12, paint, 0)
local sw = assert(m:place_swing(27.5, 12, 0, 0), "swing")
m:place_line(30, 12, 36, 12, paint, 0)
local tail = ends(function(p) return p.y == 12 and p.x > sw.x end)
local w1 = assert(m:place_switch(tail.x + 0.8, 12, 0), "switch")
assert(m:place_ramp(22, 3.2, 0, -4, 3.2, 8.8), "ramp")
local tb = assert(m:place(-5.5, 3.2, 0, 8.8, "sage"))
assert(m:place_ball(-4.55, 3.2, 8.8), "ball")
m:link_switch(w1, tb.id)
st = stats(m)
got = ids(C.award(st))
check(st.balls == 1 and st.swings == 1 and st.switches == 1, "the gadgets are counted: " .. st.balls .. " " .. st.swings .. " " .. st.switches)
check(got.ball and got.swing and got.switch and got.contraption, "they earn theirs")

local unused = F.new_board()
unused:place_line(-30, -28, -20, -28, paint, 0)
unused:place_ball(30, -30, 0)
st = stats(unused)
check(st.balls == 0, "a ball that is never hit does not count")

-- A goal is not "a switch of your own"; three stars is global; gadgets need a map that has them.
local def1, rid1, solve1 = any_def()
F.set_room(room_data(rid1))
local won = C.new_board(def1)
solve1(won, F)
st = stats(won, 3)
F.set_room(LIVING)
check(st.switches == 0 and ids(C.award(st)).three_stars, "three stars counts, the goal is not your switch")
fresh()
local at = {}
for k, v in pairs(base) do at[k] = v end
at.fallen, at.total = 5000, 6000
check(ids(C.award(at)).fell_5000, "5,000")
at.fallen, at.total = 100000, 100000
check(ids(C.award(at)).fell_100k, "100,000")
at.own = false; fresh()
check(#C.award(at) == 0, "a sample never earns anything")

-- Each map's list: its own challenges and every shared one, saying which it can't do here.
fresh()
C.award({ own = true, fallen = 30, total = 30, duration = 1, balls = 1, swings = 0, switches = 0, ramp = false, stars = 0 })
local room, hall = C.for_map("room"), C.for_map("hall")
check(#room.own == 3 and #hall.own == 0, "each map has its own list")
check(#room.shared == #C.GLOBAL and #hall.shared == #C.GLOBAL, "every map lists the whole shared set")
local function entry(list, id) for _, e in ipairs(list.shared) do if e.g.id == id then return e end end end
check(entry(room, "ball").here and not entry(hall, "ball").here, "gadget goals belong to the room")
check(entry(hall, "fell_100k").here and not entry(room, "fell_100k").here, "100,000 needs the hall")
check(entry(room, "fell_100").here and entry(hall, "fell_100").here, "chain goals work on both")
check(entry(room, "ball").done and entry(hall, "ball").done and entry(hall, "fell_25").done, "progress is shared between maps")
check(not entry(hall, "fell_500").done, "and only what was earned")
for _, g in ipairs(C.GLOBAL) do check(g.needs == nil or C.MAPS[g.needs], g.id .. ": its map exists") end

-- House fields: room, tier, tools, sizes, presets, traps and a goal that is a preset to tip (here in the living room).
local function dict_def()
    return {
        id = "test_dict", name = "Test Dictionary", room = "living", tier = 2,
        tools = { "line", "grow" }, sizes = { 2, 4 },
        start = { x = -20, y = -28, h = 0, a = 0 },
        goal = { preset = "dict" },
        preset = {
            { id = "dict", x = -5, y = -28, h = 0, a = 0, size = 5, paint = "navy" },
            { line = { x0 = 5, y0 = -31, x1 = 9, y1 = -31 }, h = 0 },
            { x = 21, y = -29, h = 1.5, a = 0 },
        },
        traps = {
            { kind = "support", id = "cards", x0 = 20, x1 = 22, y0 = -30, y1 = -28, z0 = 0, z1 = 1.5 },
            { kind = "zone", x0 = -15, x1 = -14, y0 = -25, y1 = -24 },
        },
        budget = { domino = 60 }, stars = { 40, 30 },
    }
end
do
    local d = dict_def()
    local b = C.new_board(d)
    check(b.room == "living" and b.tier == 2 and b.def == d, "a board knows its room and tier")
    check(#b.trap_order == 2 and b.traps.cards and b.preset_count == 9 and C.used(b) == 0, "traps and presets are installed and cost nothing, presets " .. b.preset_count)
    check(b.goal_piece and b.pieces[b.goal_piece].s == F.SIZES[5] and b.goal_id == nil, "the goal is the Titan preset")
    check(C.allows(b, "line") and C.allows(b, "grow") and C.allows(b, "erase") and not C.allows(b, "ball") and not C.allows(b, "draw"), "tools: its list and erase")
    check(C.allows_size(b, 2) and C.allows_size(b, 4) and not C.allows_size(b, 1) and not C.allows_size(b, 5), "sizes: its list")
    local old = { id = "old", start = { x = -20, y = -28, h = 0, a = 0 }, goal = { x = -10, y = -28, h = 0 }, budget = { domino = 5 }, stars = { 4, 3 } }
    local door = C.new_board(old)
    check(C.allows(door, "ball") and C.allows(old, "ramp") and C.allows_size(door, 2) and not C.allows_size(door, 1), "a def without tools or sizes: every tool, Standard only")
    check(C.allows(F.new_board(), "ball") and C.allows_size(F.new_board(), 5), "Free Build allows everything")
    local _, why = b:place(21, -28.5, 0, 1.5, "cream")
    check(why == "support", "the player cannot build on the support, got " .. tostring(why))
    _, why = b:place(-14.5, -24.5, 0, 0, "cream")
    check(why == "zone", "nor in the zone, got " .. tostring(why))
    -- A Standard line cannot tip the Titan; one that grows to Giant can.
    local s1 = C.new_board(dict_def())
    s1:place_line(-19.38, -28, -5.55, -28, paint, 0)
    local r1 = F.simulate(s1)
    local near
    for _, p in pairs(s1.pieces) do if not p.preset and (not near or p.x > near.x) then near = p end end
    check(r1.falls[near.id] and r1.falls[near.id].blocked, "a Standard falls against the dictionary")
    check(not C.won(s1, r1) and r1.falls[s1.goal_piece] == nil, "and cannot tip it")
    local s2 = C.new_board(dict_def())
    s2:place_line(-19.38, -28, -6.2, -28, paint, 0, F.SIZES[2], F.SIZES[4])
    local r2 = F.simulate(s2)
    check(C.won(s2, r2), "a line grown to Giant tips it and wins")
    check(C.used(s2) == s2.count - 1 - 9 and C.used(s2) <= 60, "only the player's dominoes count, " .. C.used(s2))
    -- Presets survive erase and clear, stay out of the save; the budget counts around them.
    s2:erase_at(-5, -28, 0, 3)
    s2:clear()
    check(s2.preset_count == 9 and s2.pieces[s2.goal_piece] and C.used(s2) == 0, "erase and clear keep the presets")
    check(not F.serialize(s2):find("navy"), "a save does not hold them")
    local full, n = C.new_board(dict_def()), 0
    for y = -20, -12, 1.2 do for x = -38, 38, 1.2 do if full:place(x, y, 0, 0, "cream") then n = n + 1 end end end
    check(n == 60 and C.used(full) == 60, "the budget is the player's own, placed " .. n)
    -- A bad def is caught when the board is made.
    local bad = dict_def()
    bad.goal = { preset = "nope" }
    check(not pcall(C.new_board, bad), "a goal naming no preset is refused")
end

if failed > 0 then error(failed .. " checks failed") end
print(checks .. " checks passed")
print("PASS challenges")
