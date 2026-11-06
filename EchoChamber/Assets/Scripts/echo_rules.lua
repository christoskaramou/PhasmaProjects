-- Echo Chamber rules: a grid, a horn that fires a sound pulse, bells to ring in numbered order, and the
-- pieces the player places to steer the pulse. Pure Lua (no engine calls) so tests run under luajit.
--
-- Board: cells (x, y), x = 1..w left to right, y = 1..h top (far) to bottom (near).
-- A pulse moves one cell per tick. Each move costs 1 strength; a bounce or split costs 1 more.
--   reflector  "/" or "\": turns the pulse 90 degrees (click to flip)
--   fork       splits the pulse into two, out to the left and right of its heading
--   resonator  recharges a pulse to full strength, once per send
--   damper     stops a pulse dead
-- A bell rings when a pulse reaches it. Bells must ring 1, 2, 3, ...: reaching an unrung bell out of
-- order fails the send. Walls, the board edge and the horn absorb pulses.
local R = {}
local floor, min, max, abs = math.floor, math.min, math.max, math.abs

R.PIECES = { "reflector", "fork", "resonator", "damper" }
R.BOUNCE_COST = 1
R.MAX_PULSES = 48

------------------------------------------------------------------ rng (own LCG: same levels on every Lua)
local function rng(seed)
    local s = (seed * 1103515245 + 12345) % 2147483648
    local r = {}
    function r.next()
        s = (s * 1103515245 + 12345) % 2147483648
        return s / 2147483648
    end
    function r.int(a, b) return a + floor(r.next() * (b - a + 1)) end
    function r.pick(t) return t[r.int(1, #t)] end
    return r
end
R.rng = rng

------------------------------------------------------------------ directions
-- "/" in a y-down grid: moving right (1,0) turns up (0,-1). "\": moving right turns down.
local function reflect(flip, dx, dy)
    if flip == "/" then return -dy, -dx end
    return dy, dx
end
R.reflect = reflect
local function flip_for(dx, dy, ndx, ndy)
    local ax, ay = reflect("/", dx, dy)
    if ax == ndx and ay == ndy then return "/" end
    return "\\"
end

------------------------------------------------------------------ game object
local Game = {}
Game.__index = Game

function R.idx(g, x, y) return (y - 1) * g.w + x end
function Game:idx(x, y) return (y - 1) * self.w + x end
function Game:inside(x, y) return x >= 1 and y >= 1 and x <= self.w and y <= self.h end

function Game:kind(x, y)
    if not self:inside(x, y) then return "out" end
    local i = self:idx(x, y)
    if self.walls[i] then return "wall" end
    if self.emitter.x == x and self.emitter.y == y then return "emitter" end
    if self.bell_at[i] then return "bell" end
    return "floor"
end

function Game:piece(x, y) return self:inside(x, y) and self.pieces[self:idx(x, y)] or nil end

function Game:left(kind)
    local used = 0
    for _, p in pairs(self.pieces) do if p.kind == kind then used = used + 1 end end
    return (self.inventory[kind] or 0) - used
end

function Game:total_pieces()
    local n = 0
    for _, k in ipairs(R.PIECES) do n = n + (self.inventory[k] or 0) end
    return n
end
function Game:placed_count()
    local n = 0
    for _ in pairs(self.pieces) do n = n + 1 end
    return n
end

function Game:place(kind, x, y, flip)
    if self.state == "won" then return false, "solved" end
    if self:kind(x, y) ~= "floor" then return false, "blocked" end
    if self:piece(x, y) then return false, "taken" end
    if (self.inventory[kind] or 0) == 0 then return false, "none in this chamber" end
    if self:left(kind) <= 0 then return false, "none left" end
    self.pieces[self:idx(x, y)] = { kind = kind, flip = kind == "reflector" and (flip or "/") or nil }
    self.version = self.version + 1
    return true
end

function Game:rotate(x, y)
    local p = self:piece(x, y)
    if not p or p.kind ~= "reflector" or self.state == "won" then return false end
    p.flip = p.flip == "/" and "\\" or "/"
    self.version = self.version + 1
    return true
end

function Game:remove(x, y)
    local p = self:piece(x, y)
    if not p or self.state == "won" then return nil end
    self.pieces[self:idx(x, y)] = nil
    self.version = self.version + 1
    return p
end

function Game:clear_pieces()
    self.pieces = {}
    self.version = self.version + 1
end

------------------------------------------------------------------ simulation
-- Runs a send with the given pieces (default: the placed ones) and strength.
-- Returns { ok, fail = nil | { why = "order"|"faded"|"lost", bell, expected, x, y }, ticks, rings, events,
--           frames = { [t] = { { x0, y0, x1, y1, s, id }, ... } } }.
function Game:simulate(pieces, strength)
    pieces = pieces or self.pieces
    local S = strength or self.strength
    local e = self.emitter
    local pulses = { { x = e.x, y = e.y, dx = e.dx, dy = e.dy, s = S, id = 1 } }
    local next_id = 1
    local rung, nxt = {}, 1
    local used_res = {}
    local out = { ok = false, frames = {}, events = {}, rings = {}, ticks = 0, peak = S }
    local nb = #self.bells
    local t = 0
    while #pulses > 0 do
        t = t + 1
        if t > 4000 then break end
        local frame, alive, hits = {}, {}, {}
        for _, p in ipairs(pulses) do
            local x0, y0 = p.x, p.y
            local x, y = x0 + p.dx, y0 + p.dy
            p.s = p.s - 1
            local k = self:kind(x, y)
            if k == "out" or k == "wall" or k == "emitter" then
                -- Absorbed at the boundary: draw half a step into the obstacle.
                frame[#frame + 1] = { x0, y0, x0 + p.dx * 0.5, y0 + p.dy * 0.5, max(p.s, 0), p.id, stop = true }
                out.events[#out.events + 1] = { t = t, kind = "absorb", x = x0 + p.dx * 0.5, y = y0 + p.dy * 0.5, wall = k == "wall", bx = x, by = y }
            else
                frame[#frame + 1] = { x0, y0, x, y, max(p.s, 0), p.id }
                p.x, p.y = x, y
                local i = self:idx(x, y)
                local b = self.bell_at[i]
                if b and not rung[b] then hits[#hits + 1] = { b = b, x = x, y = y } end
                local pc = pieces[i]
                local dead = false
                if pc then
                    if pc.kind == "reflector" then
                        p.dx, p.dy = reflect(pc.flip, p.dx, p.dy)
                        p.s = p.s - R.BOUNCE_COST
                        out.events[#out.events + 1] = { t = t, kind = "bounce", x = x, y = y }
                    elseif pc.kind == "fork" then
                        p.s = p.s - R.BOUNCE_COST
                        local ldx, ldy = p.dy, -p.dx
                        if #pulses + #alive < R.MAX_PULSES then
                            next_id = next_id + 1
                            alive[#alive + 1] = { x = x, y = y, dx = -ldx, dy = -ldy, s = p.s, id = next_id, parent = p.id }
                        end
                        p.dx, p.dy = ldx, ldy
                        out.events[#out.events + 1] = { t = t, kind = "split", x = x, y = y }
                    elseif pc.kind == "resonator" then
                        if not used_res[i] then
                            used_res[i] = true
                            p.s = S
                            out.events[#out.events + 1] = { t = t, kind = "charge", x = x, y = y }
                        end
                    elseif pc.kind == "damper" then
                        dead = true
                        out.events[#out.events + 1] = { t = t, kind = "damp", x = x, y = y }
                    end
                end
                if not dead then
                    if p.s <= 0 then
                        out.events[#out.events + 1] = { t = t, kind = "fade", x = x, y = y }
                    else
                        alive[#alive + 1] = p
                    end
                end
            end
        end
        out.frames[t] = frame
        -- Bells reached on the same tick ring lowest number first.
        table.sort(hits, function(a, b) return a.b < b.b end)
        for _, h in ipairs(hits) do
            if not rung[h.b] then
                if h.b == nxt then
                    rung[h.b] = true
                    nxt = nxt + 1
                    out.rings[#out.rings + 1] = { t = t, bell = h.b, x = h.x, y = h.y }
                    out.events[#out.events + 1] = { t = t, kind = "ring", bell = h.b, x = h.x, y = h.y }
                else
                    out.fail = { why = "order", bell = h.b, expected = nxt, x = h.x, y = h.y, t = t }
                    out.events[#out.events + 1] = { t = t, kind = "wrong", bell = h.b, x = h.x, y = h.y }
                    out.ticks = t
                    return out
                end
            end
        end
        if nb > 0 and nxt > nb then
            out.ok = true
            out.ticks = t
            return out
        end
        -- Keep forks from multiplying pulses that sit on the same cell heading the same way.
        local seen, uniq = {}, {}
        for _, p in ipairs(alive) do
            local key = p.x .. "," .. p.y .. "," .. p.dx .. "," .. p.dy
            if not seen[key] then seen[key] = true; uniq[#uniq + 1] = p end
        end
        pulses = uniq
    end
    out.ticks = t
    local faded = false
    for _, ev in ipairs(out.events) do if ev.kind == "fade" then faded = true end end
    out.fail = { why = faded and "faded" or "lost", expected = nxt }
    return out
end

-- Fire the pulse with the placed pieces. Updates sends / state / stars.
function Game:send()
    local res = self:simulate()
    self.sends = self.sends + 1
    self.last = res
    if res.ok then
        self.state = "won"
        local stars = self.sends == 1 and 3 or (self.sends <= 3 and 2 or 1)
        stars = max(1, stars - self.hints)
        self.stars = stars
    end
    return res
end

-- Reveal one solution piece that is not already placed correctly. Clears whatever sits on that cell.
function Game:hint()
    for _, s in ipairs(self.solution) do
        local p = self:piece(s.x, s.y)
        if not p or p.kind ~= s.kind or (s.flip and p.flip ~= s.flip) then
            self.hints = self.hints + 1
            return s
        end
    end
    return nil
end

------------------------------------------------------------------ level generation
-- Grow a solution (the pieces a player would place), simulate it to find where the pulse really goes,
-- hang bells along that route numbered by when the pulse reaches them, add walls off the route, then
-- drop every piece the route does not need. The player gets exactly the needed pieces.
local function params(level)
    local L = level
    return {
        w = min(14, 7 + floor(L / 3)),
        h = min(9, 5 + floor(L / 4)),
        bells = min(7, 2 + floor(L / 3)),
        turns = min(9, 1 + floor((L + 1) / 2)),
        fork = L >= 5,
        resonator = L >= 4,
        damper = L >= 8,
        walls = 0.07 + min(0.06, L * 0.004),
        slack = L <= 3 and 3 or (L <= 8 and 2 or 1),
    }
end
R.params = params

local function shuffle(r, t)
    for i = #t, 2, -1 do
        local j = r.int(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function try_build(level, r, P, want)
    local g = setmetatable({ w = P.w, h = P.h, walls = {}, bell_at = {}, bells = {}, pieces = {}, version = 0 }, Game)
    -- Horn on a random edge, facing inward, not in a corner.
    local side = r.int(1, 4)
    local e
    if side == 1 then e = { x = 1, y = r.int(2, P.h - 1), dx = 1, dy = 0 }
    elseif side == 2 then e = { x = P.w, y = r.int(2, P.h - 1), dx = -1, dy = 0 }
    elseif side == 3 then e = { x = r.int(2, P.w - 1), y = 1, dx = 0, dy = 1 }
    else e = { x = r.int(2, P.w - 1), y = P.h, dx = 0, dy = -1 } end
    g.emitter = e
    local sol = {}           -- idx -> piece
    local trail = {}         -- idx -> true (cells the planned route crosses)
    trail[g:idx(e.x, e.y)] = true
    local forks, res = 0, 0
    local gadget             -- damper set-up: { x = bell cell, mid = cells for the bell before it, clear = cells }
    local function free(x, y)
        if not g:inside(x, y) then return false end
        local i = g:idx(x, y)
        return not trail[i] and not sol[i]
    end
    local function run_ok(x, y, dx, dy, n)
        for k = 1, n do if not free(x + dx * k, y + dy * k) then return false end end
        return true
    end

    -- Damper set-up at a fork F (pulse arriving along d). Branch A loops round and comes back down
    -- across branch B's straight line at X. A bell hangs at X and another on A's loop before it, so
    -- B would reach X out of order unless a damper stops it first:
    --   A: F -a1-> R1 -a2 (along d)-> R2 -(a1+k) back across-> R3 -a2 (against d)-> X = F + b*k
    --   B: F -> F + b*1 .. F + b*(k-1) (damper somewhere here) -> X
    local function try_gadget(fx, fy, dx, dy)
        for _, sgn in ipairs(r.next() < 0.5 and { 1, -1 } or { -1, 1 }) do
            local ax, ay = dy * sgn, -dx * sgn
            local bx, by = -ax, -ay
            local a1, a2, k = r.int(2, 3), r.int(2, 3), r.int(2, 3)
            local cells, seen, ok = {}, {}, true
            local function add(x, y)
                if not ok then return end
                if not free(x, y) then ok = false; return end
                local i = g:idx(x, y)
                if seen[i] then ok = false; return end
                seen[i] = true
                cells[#cells + 1] = i
            end
            for s = 1, a1 do add(fx + ax * s, fy + ay * s) end
            local r1x, r1y = fx + ax * a1, fy + ay * a1
            for s = 1, a2 do add(r1x + dx * s, r1y + dy * s) end
            local r2x, r2y = r1x + dx * a2, r1y + dy * a2
            for s = 1, a1 + k do add(r2x + bx * s, r2y + by * s) end
            local r3x, r3y = r2x + bx * (a1 + k), r2y + by * (a1 + k)
            for s = 1, a2 do add(r3x - dx * s, r3y - dy * s) end
            for s = 1, k - 1 do add(fx + bx * s, fy + by * s) end
            if ok then
                for _, i in ipairs(cells) do trail[i] = true end
                sol[g:idx(fx, fy)] = { kind = "fork" }
                sol[g:idx(r1x, r1y)] = { kind = "reflector", flip = flip_for(ax, ay, dx, dy) }
                sol[g:idx(r2x, r2y)] = { kind = "reflector", flip = flip_for(dx, dy, bx, by) }
                sol[g:idx(r3x, r3y)] = { kind = "reflector", flip = flip_for(bx, by, -dx, -dy) }
                local j = r.int(1, k - 1)
                sol[g:idx(fx + bx * j, fy + by * j)] = { kind = "damper" }
                local mid, clear = {}, {}
                for s = 2, a1 + k - 1 do mid[#mid + 1] = g:idx(r2x + bx * s, r2y + by * s) end
                for s = j + 1, k - 1 do clear[#clear + 1] = g:idx(fx + bx * s, fy + by * s) end
                gadget = { x = g:idx(fx + bx * k, fy + by * k), mid = mid, clear = clear }
                return fx + bx * k, fy + by * k, -dx, -dy
            end
        end
    end

    -- Walk a branch: runs of 2..4 cells, each ended by a piece. Looks one turn ahead so routes do not
    -- stall against the edge or their own trail.
    local function walk(x, y, dx, dy, turns, depth)
        for step = 1, turns do
            local opts, good = {}, {}
            for n = 2, 4 do
                if run_ok(x, y, dx, dy, n) then
                    opts[#opts + 1] = n
                    local cx, cy = x + dx * n, y + dy * n
                    if run_ok(cx, cy, dy, -dx, 2) or run_ok(cx, cy, -dy, dx, 2) then good[#good + 1] = n end
                end
            end
            if #opts == 0 then return end
            local run = #good > 0 and r.pick(good) or r.pick(opts)
            for k = 1, run - 1 do trail[g:idx(x + dx * k, y + dy * k)] = true end
            if want.resonator and res == 0 and run >= 3 and r.next() < 0.5 then
                local k = r.int(1, run - 1)
                sol[g:idx(x + dx * k, y + dy * k)] = { kind = "resonator" }
                res = res + 1
            end
            x, y = x + dx * run, y + dy * run
            local i = g:idx(x, y)
            trail[i] = true
            if depth == 0 and forks == 0 and turns - step >= 2 then
                if want.damper then
                    local nx, ny, ndx, ndy = try_gadget(x, y, dx, dy)
                    if nx then
                        forks = forks + 1
                        walk(nx, ny, ndx, ndy, max(1, turns - step - 3), 1)
                        return
                    end
                elseif want.fork and r.next() < 0.5 then
                    sol[i] = { kind = "fork" }
                    forks = forks + 1
                    local ldx, ldy = dy, -dx
                    local rest = turns - step
                    walk(x, y, ldx, ldy, rest - floor(rest / 2), depth + 1)
                    walk(x, y, -ldx, -ldy, floor(rest / 2), depth + 1)
                    return
                end
            end
            local dirs = {}
            for _, d in ipairs({ { dy, -dx }, { -dy, dx } }) do
                if run_ok(x, y, d[1], d[2], step == turns and 1 or 2) then dirs[#dirs + 1] = d end
            end
            if #dirs == 0 then dirs = { { dy, -dx }, { -dy, dx } } end
            local d = r.pick(dirs)
            sol[i] = { kind = "reflector", flip = flip_for(dx, dy, d[1], d[2]) }
            dx, dy = d[1], d[2]
        end
    end
    walk(e.x, e.y, e.dx, e.dy, P.turns, 0)
    local nsol = 0
    for _ in pairs(sol) do nsol = nsol + 1 end
    if nsol < max(1, floor(P.turns * 0.6)) then return nil end
    if want.damper and not gadget then return nil end

    -- Where does the pulse really go? Big strength, no bells, no walls yet.
    g.strength = 999
    local first, count = {}, {}
    local probe = g:simulate(sol, 999)
    for t, frame in ipairs(probe.frames) do
        for _, s in ipairs(frame) do
            if not s.stop then
                local i = g:idx(s[3], s[4])
                count[i] = (count[i] or 0) + 1
                if not first[i] then first[i] = t end
            end
        end
    end
    local function cell(i) return (i - 1) % g.w + 1, floor((i - 1) / g.w) + 1 end
    local keep_clear = {}
    local chosen, used_t, taken = {}, {}, {}
    local function choose(i)
        local x, y = cell(i)
        chosen[#chosen + 1] = { i = i, t = first[i], x = x, y = y }
        used_t[first[i]] = true
        taken[i] = true
    end
    if gadget then
        if not (first[gadget.x] and count[gadget.x] == 1) then return nil end
        local mids = {}
        for _, i in ipairs(gadget.mid) do
            if first[i] and count[i] == 1 and first[i] < first[gadget.x] then mids[#mids + 1] = i end
        end
        if #mids == 0 then return nil end
        choose(gadget.x)
        choose(r.pick(mids))
        for _, i in ipairs(gadget.clear) do keep_clear[i] = true end
    end
    -- Bell candidates: cells crossed exactly once, not a piece, not next to the horn's mouth.
    local cand = {}
    for i, t in pairs(first) do
        local x, y = cell(i)
        if count[i] == 1 and not sol[i] and t >= 2 and not taken[i] and not used_t[t] then
            cand[#cand + 1] = { i = i, t = t, x = x, y = y }
        end
    end
    table.sort(cand, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.i < b.i end)
    local need = P.bells - #chosen
    if #cand < need then return nil end
    -- Spread bells over the route; distinct times so the order is never a tie.
    local span = #cand / max(1, need)
    for k = 1, need do
        local lo = floor((k - 1) * span) + 1
        local hi = max(lo, floor(k * span))
        local pickc
        for _ = 1, 8 do
            local c = cand[r.int(lo, hi)]
            if c and not used_t[c.t] then pickc = c; break end
        end
        if not pickc then return nil end
        choose(pickc.i)
    end
    table.sort(chosen, function(a, b) return a.t < b.t end)
    for n, c in ipairs(chosen) do
        g.bells[n] = { x = c.x, y = c.y, n = n }
        g.bell_at[c.i] = n
    end

    -- Walls: off the route, mostly hugging it so they read as part of the chamber.
    local area = g.w * g.h
    local want = floor(area * P.walls)
    local spots = {}
    for y = 1, g.h do
        for x = 1, g.w do
            local i = g:idx(x, y)
            if not first[i] and not sol[i] and not keep_clear[i] and not (x == e.x and y == e.y) and not (x == e.x + e.dx and y == e.y + e.dy) then
                local near = 0
                for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                    if first[g:idx(min(g.w, max(1, x + d[1])), min(g.h, max(1, y + d[2])))] then near = near + 1 end
                end
                spots[#spots + 1] = { i = i, w = near > 0 and 3 or 1 }
            end
        end
    end
    shuffle(r, spots)
    table.sort(spots, function(a, b) return a.w > b.w end)
    local placed = 0
    for k = 1, #spots do
        if placed >= want then break end
        if r.next() < (spots[k].w == 3 and 0.75 or 0.35) then g.walls[spots[k].i] = true; placed = placed + 1 end
    end

    -- Strength: the least that still works with every piece, plus slack.
    local function works(pcs, S) return g:simulate(pcs, S).ok end
    if not works(sol, 999) then return nil end
    local lo, hi = 1, 999
    while lo < hi do
        local mid = floor((lo + hi) / 2)
        if works(sol, mid) then hi = mid else lo = mid + 1 end
    end
    g.strength = lo + P.slack
    -- Drop pieces the route does not need at that strength (resonators included).
    local order = {}
    for i in pairs(sol) do order[#order + 1] = i end
    table.sort(order)
    for _, i in ipairs(order) do
        local p = sol[i]
        sol[i] = nil
        if not works(sol, g.strength) then sol[i] = p end
    end
    local list = {}
    for _, i in ipairs(order) do
        if sol[i] then
            local p = sol[i]
            list[#list + 1] = { x = (i - 1) % g.w + 1, y = floor((i - 1) / g.w) + 1, kind = p.kind, flip = p.flip }
        end
    end
    if #list == 0 then return nil end
    -- Not trivial: the bare horn must not ring every bell.
    if works({}, g.strength) then return nil end
    g.solution = list
    g.inventory = {}
    for _, s in ipairs(list) do g.inventory[s.kind] = (g.inventory[s.kind] or 0) + 1 end
    return g
end

-- Which piece kinds a chamber should feature. Every few chambers asks for a damper or a fork, so each
-- piece keeps turning up instead of depending on luck.
local function wants(level, P)
    return {
        damper = P.damper and level % 3 == 2,
        fork = P.fork and level % 2 == 1,
        resonator = P.resonator and level % 3 ~= 1,
    }
end

function R.new(level)
    level = max(1, floor(level or 1))
    local P = params(level)
    local r = rng(level * 7919 + 17)
    local want = wants(level, P)
    local g
    for attempt = 1, 1500 do
        if attempt == 900 then want = { resonator = want.resonator, fork = want.fork } end   -- stop insisting
        g = try_build(level, r, P, want)
        if g and want.damper and not g.inventory.damper then g = nil end
        if g then break end
    end
    if not g then
        -- Fallback (not expected): relax to fewer bells.
        P.bells = 2
        for _ = 1, 600 do g = try_build(level, r, P, {}); if g then break end end
    end
    assert(g, "could not generate chamber " .. level)
    g.level = level
    g.state = "plan"
    g.sends, g.hints, g.stars = 0, 0, 0
    g.pieces = {}
    g.version = 0
    return g
end

return R
