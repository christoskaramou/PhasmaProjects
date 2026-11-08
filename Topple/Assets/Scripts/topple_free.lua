-- Topple Free Build rules: lay thousands of dominoes around a living room (floor, rug, coffee table, a staircase of
-- books...), tip the first one and watch the chain run. Pure Lua (no engine calls) so tests run under luajit.
--
-- Table coordinates as in Table Run: x right, y away from the default camera, h up; 1 unit = a domino's height.
-- The room (Scripts/free_room.lua, written by tools/gen_room.py) gives the surfaces you can build on and the solid
-- furniture that blocks placing and stops a falling domino.
--
-- A domino falls along whichever way of its facing the push favours (pushed edge-on it only wobbles), pivoting on
-- its front edge. As it tips it meets, at the smallest angle, either dominoes ahead (several if side by side: it
-- knocks them on and comes to lean on them), a piece of furniture (it stops there), a low ledge such as a book's
-- edge (it slides over that, and only rests on it if nothing else is in reach) or nothing (it lies flat). The
-- dominoes it struck fall next, so the chain runs as a time-ordered event queue (a binary heap) over a spatial
-- grid: a run of thousands takes milliseconds to simulate. The whole run is worked out up front (the view animates
-- it and can replay it), and the same simulation gives the build preview.
local F = {}
local floor, min, max, abs, sqrt, sin, cos = math.floor, math.min, math.max, math.abs, math.sqrt, math.sin, math.cos
local asin, pi, rad, deg = math.asin, math.pi, math.rad, math.deg
local atan2 = math.atan2 or math.atan

F.DOM = { w = 0.5, t = 0.15, h = 1.0 }
local W, T, H = F.DOM.w, F.DOM.t, F.DOM.h
F.SPACING = 0.62           -- along a drawn line
F.MIN_GAP = 0.45           -- closest two dominoes may stand (centre to centre, same level)
F.CLIMB = 0.6              -- a line steps up or down onto a surface at most this much higher or lower
F.CAP = 5000               -- dominoes in the box
F.FIELD_LAT = 0.6          -- side by side in a field row (staggered rows: each one strikes two ahead)
F.SPIRAL_GAP = 0.95        -- between the turns of a spiral
F.SPIRAL_MIN = 1.6         -- the spiral's innermost radius
F.TIME_K = 0.5             -- Free Build's chains run at about twice Table Run's pace
F.REST = 89.3              -- a domino with nothing in reach lies flat
F.LEDGE = 0.6              -- solids no taller than this above a faller's base are ledges it slides over
F.PAINTS = { "brick", "mustard", "sage", "navy", "cream" }
F.FIELD_WIDTH = { min = 1.2, max = 24, default = 6 }
-- A ball: pushed by a falling domino it rolls, drops off edges, bounces and knocks over what it meets.
-- step: the highest lip it rolls up onto (the rug); max_t: a run never waits on a ball longer than this.
-- Real values at this scale (1 unit = 5 cm): g 9.81 m/s2 = 196.2. The ball weighs what a table-tennis ball does, so a
-- domino can really push it. drag: rolling resistance (0.01 * 5/7 * g); air: 0.5 rho Cd A / m for this ball, per
-- unit of speed squared; e: its bounce on wood. rebound: what is left of its speed, reversed, after striking a
-- standing domino (the domino is the heavier). min_hit: the speed that gives a standing domino enough to tip it.
-- domino: its mass in kg, for the kick a falling one gives.
F.BALL = { r = 0.42, mass = 0.0027, domino = 0.008, drag = 1.4, air = 0.00769, g = 196.2, dt = 1 / 240, e = 0.8, bounce = 0.8, min_bounce = 6, keep = 0.9,
    rebound = 0.525, stop = 0.2, min_hit = 3.9,
    step = 0.2, max_t = 12, cap = 64, clear = 0.12 }
-- A ball on a string: a heavy bob held pulled back by a latch on the surface behind it. A hit on the latch lets it go
-- and gravity swings it through the lowest point and out the other side. It hangs a little above the surface from a
-- stand of two posts (post: either side of the axis), or from the bookshelf's top when it is set down within
-- shelf_reach of the shelf's front. amp: how far it is pulled back. damp: the little that air and the string take.
F.SWING = { r = 0.55, lift = 0.07, len = 8, amp = rad(35), amp_shelf = rad(20), mass = 0.2, damp = 0.15, dt = 1 / 120, keep = 0.97, min_hit = 0.8, post = 1.3, post_r = 0.15,
    shelf_reach = 2.4, cap = 32, max_t = 8, clear = 0.12 }
-- A switch: struck by a domino, ball or swing, it starts the domino it is linked to (anywhere in the room) after
-- delay, and can turn the lamp off or on. It is a solid block 2r wide and 2r tall.
F.SWITCH = { r = 0.4, delay = 0.12, cap = 32, clear = 0.12 }
-- A ramp: a straight flight of narrow steps along one room axis, from a surface up to the edge of a higher one.
-- Dominoes stand on the steps, like the book staircase; balls roll it as a slope. rise and run: the most a step
-- climbs and the least it is long (so the steepest slope is rise / run). grav: 5/7, a solid ball rolling without slipping.
F.RAMP = { rise = 0.2, run = 0.45, width = 2.6, grav = 5 / 7, cap = 8 }

local ROOM
local GRID = 2.0
local function key(cx, cy) return (cx + 4096) * 8192 + (cy + 4096) end

function F.set_room(room)
    ROOM = room
    F.ROOM = room
    -- Highest surfaces first, so "the surface under this point" picks the top one.
    table.sort(room.surfaces, function(a, b) return a.h > b.h end)
    return room
end

------------------------------------------------------------------ surfaces and solids
-- Half extents (x, y) of a domino's footprint facing a (thin along its facing, wide across it), with a hair of
-- clearance; facing unknown: the widest.
local function extents(a)
    if not a then return W / 2 + 0.02, W / 2 + 0.02 end
    local c, s = abs(cos(a)), abs(sin(a))
    return c * T / 2 + s * W / 2 + 0.02, s * T / 2 + c * W / 2 + 0.02
end
F.extents = extents

local function in_rect(x, y, r, ex, ey)
    ex, ey = ex or 0, ey or ex or 0
    return x >= r.x0 + ex and x <= r.x1 - ex and y >= r.y0 + ey and y <= r.y1 - ey
end

-- Surfaces under (x, y) that a domino facing a could stand on (whole footprint inside a raised one), highest first.
function F.surfaces_at(x, y, a, list)
    local ex, ey = extents(a)
    local out = {}
    for _, s in ipairs(list or ROOM.surfaces) do
        if (s.edge and in_rect(x, y, s, ex, ey)) or (not s.edge and in_rect(x, y, s)) then out[#out + 1] = s end
    end
    return out
end

-- The solid (furniture, walls) a domino facing a, standing at (x, y) on height h, would intersect, if any.
local function solid_at(x, y, h, a, list)
    local ex, ey = extents(a)
    for _, s in ipairs(list or ROOM.solids) do
        if s.z0 < h + H - 0.01 and s.z1 > h + 0.01 and x + ex > s.x0 and x - ex < s.x1 and y + ey > s.y0 and y - ey < s.y1 then
            return s
        end
    end
    return nil
end
F.solid_at = solid_at

------------------------------------------------------------------ the board
local Board = {}
Board.__index = Board

function F.new_board()
    return setmetatable({ pieces = {}, balls = {}, ball_count = 0, swings = {}, swing_count = 0, switches = {}, switch_count = 0, ramps = {}, ramp_count = 0, grid = {}, count = 0, next_id = 0, order = 0, start = nil,
        undo_stack = {}, redo_stack = {}, act = nil, rev = 0 }, Board)
end

local function cell_of(x, y) return floor(x / GRID), floor(y / GRID) end

-- Work out a ramp's steps from its two ends (x0, y0, z0 the low end, x1, y1, z1 the high end).
local function ramp_build(p)
    local R = F.RAMP
    local dx, dy = p.x1 - p.x0, p.y1 - p.y0
    local on_x = abs(dx) >= abs(dy)
    local L = on_x and abs(dx) or abs(dy)
    local rise = p.z1 - p.z0
    local n = max(1, math.ceil(rise / R.rise - 1e-9))
    local sgn = (on_x and dx or dy) >= 0 and 1 or -1
    local hw = R.width / 2
    p.on_x, p.sgn, p.L, p.n, p.d, p.rise, p.slope = on_x, sgn, L, n, L / n, rise / n, rise / L
    p.ux, p.uy = on_x and sgn or 0, on_x and 0 or sgn
    p.steps, p.solids = {}, {}
    for k = 1, n do
        local a, b = (on_x and p.x0 or p.y0) + sgn * (k - 1) * p.d, (on_x and p.x0 or p.y0) + sgn * k * p.d
        if a > b then a, b = b, a end
        local x0, x1, y0, y1
        if on_x then x0, x1, y0, y1 = a, b, p.y0 - hw, p.y0 + hw else x0, x1, y0, y1 = p.x0 - hw, p.x0 + hw, a, b end
        local h = p.z0 + p.rise * k
        p.steps[k] = { name = "ramp", x0 = x0, x1 = x1, y0 = y0, y1 = y1, h = h, edge = true }
        p.solids[k] = { name = "ramp", x0 = x0, x1 = x1, y0 = y0, y1 = y1, z0 = p.z0, z1 = h, ramp = p }
    end
    p.fx0, p.fx1 = min(p.steps[1].x0, p.steps[n].x0), max(p.steps[1].x1, p.steps[n].x1)
    p.fy0, p.fy1 = min(p.steps[1].y0, p.steps[n].y0), max(p.steps[1].y1, p.steps[n].y1)
end

-- The room's surfaces and furniture plus this board's ramps (the room's own lists when there are none).
function Board:all_surfaces()
    if self.ramp_count == 0 then return ROOM.surfaces end
    if not self._surf then
        local list = {}
        for _, s in ipairs(ROOM.surfaces) do list[#list + 1] = s end
        for _, r in pairs(self.ramps) do
            for _, s in ipairs(r.steps) do list[#list + 1] = s end
        end
        table.sort(list, function(a, b) return a.h > b.h end)
        self._surf = list
    end
    return self._surf
end

function Board:all_solids()
    if self.ramp_count == 0 then return ROOM.solids end
    if not self._sol then
        local list = {}
        for _, s in ipairs(ROOM.solids) do list[#list + 1] = s end
        local ids = {}
        for id in pairs(self.ramps) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            for _, s in ipairs(self.ramps[id].solids) do list[#list + 1] = s end
        end
        self._sol = list
    end
    return self._sol
end

function Board:_insert(p)
    if p.kind == "ramp" then
        if not p.steps then ramp_build(p) end
        self.ramps[p.id] = p
        self.ramp_count = self.ramp_count + 1
        self._surf, self._sol = nil, nil
        self.rev = self.rev + 1
        return
    end
    if p.kind == "switch" then
        self.switches[p.id] = p
        self.switch_count = self.switch_count + 1
        self.rev = self.rev + 1
        return
    end
    if p.kind == "swing" then
        self.swings[p.id] = p
        self.swing_count = self.swing_count + 1
        p.ax, p.ay = cos(p.a), sin(p.a)
        p.lx, p.ly, p.amp = F.swing_latch(p.x, p.y, p.a, p.L, p.hang)
        self.rev = self.rev + 1
        return
    end
    if p.kind == "ball" then
        self.balls[p.id] = p
        self.ball_count = self.ball_count + 1
        self.rev = self.rev + 1
        return
    end
    self.pieces[p.id] = p
    local cx, cy = cell_of(p.x, p.y)
    local k = key(cx, cy)
    local c = self.grid[k]
    if not c then c = {}; self.grid[k] = c end
    c[#c + 1] = p
    p.gk, p.gi = k, #c
    p.ax, p.ay = cos(p.a), sin(p.a)
    self.count = self.count + 1
    self.rev = self.rev + 1
end

function Board:_extract(p)
    if p.kind == "ramp" then
        if self.ramps[p.id] == p then
            self.ramps[p.id] = nil
            self.ramp_count = self.ramp_count - 1
            self._surf, self._sol = nil, nil
            self.rev = self.rev + 1
        end
        return
    end
    if p.kind == "switch" then
        if self.switches[p.id] == p then
            self.switches[p.id] = nil
            self.switch_count = self.switch_count - 1
            self.rev = self.rev + 1
        end
        return
    end
    if p.kind == "swing" then
        if self.swings[p.id] == p then
            self.swings[p.id] = nil
            self.swing_count = self.swing_count - 1
            self.rev = self.rev + 1
        end
        return
    end
    if p.kind == "ball" then
        if self.balls[p.id] == p then
            self.balls[p.id] = nil
            self.ball_count = self.ball_count - 1
            self.rev = self.rev + 1
        end
        return
    end
    if self.pieces[p.id] ~= p then return end
    self.pieces[p.id] = nil
    local c = self.grid[p.gk]
    local last = c[#c]
    c[p.gi] = last
    last.gi = p.gi
    c[#c] = nil
    if #c == 0 then self.grid[p.gk] = nil end
    self.count = self.count - 1
    self.rev = self.rev + 1
end

-- Every domino within r of (x, y) (any height): calls fn(p).
function Board:near(x, y, r, fn)
    local cx0, cy0 = cell_of(x - r, y - r)
    local cx1, cy1 = cell_of(x + r, y + r)
    for cx = cx0, cx1 do
        for cy = cy0, cy1 do
            local c = self.grid[key(cx, cy)]
            if c then for i = 1, #c do fn(c[i]) end end
        end
    end
end

-- Where a swing's two posts stand (x1, y1, x2, y2).
function F.swing_posts(x, y, a)
    local nx, ny = -sin(a) * F.SWING.post, cos(a) * F.SWING.post
    return x + nx, y + ny, x - nx, y - ny
end

-- Where a swing's latch stands (x, y) and how far it is pulled back: behind the lowest point, under the held bob.
function F.swing_latch(x, y, a, L, hang)
    local amp = hang == "shelf" and F.SWING.amp_shelf or F.SWING.amp
    local o = L * sin(amp)
    return x - cos(a) * o, y - sin(a) * o, amp
end

-- True if something of radius r at (x, y), height h, would be inside a swing's ball, posts or latch.
function Board:near_swing(x, y, h, r)
    local S = F.SWING
    for _, s in pairs(self.swings) do
        if abs(s.z - h) < 0.9 and (s.x - x) ^ 2 + (s.y - y) ^ 2 < (S.r + r) ^ 2 then return true end
        if abs(s.z - h) < 0.9 and (s.lx - x) ^ 2 + (s.ly - y) ^ 2 < (F.SWITCH.r + r) ^ 2 then return true end
        if s.hang == "stand" and h > s.z - 0.9 and h < s.z + s.L then
            local x1, y1, x2, y2 = F.swing_posts(s.x, s.y, s.a)
            local d = (S.post_r + r) ^ 2
            if (x1 - x) ^ 2 + (y1 - y) ^ 2 < d or (x2 - x) ^ 2 + (y2 - y) ^ 2 < d then return true end
        end
    end
    return false
end

-- True if something of radius r at (x, y), height h, would be inside a switch.
function Board:near_switch(x, y, h, r)
    local d = (F.SWITCH.r + r) ^ 2
    for _, s in pairs(self.switches) do
        if abs(s.z - h) < 0.9 and (s.x - x) ^ 2 + (s.y - y) ^ 2 < d then return true end
    end
    return false
end

-- Why a domino cannot stand at (x, y) on a surface of height h (nil if it can).
function Board:blocked(x, y, h, a)
    if self.count >= F.CAP then return "full" end
    local ok = false
    local ex, ey = extents(a)
    for _, s in ipairs(self:all_surfaces()) do
        if abs(s.h - h) < 1e-4 and ((s.edge and in_rect(x, y, s, ex, ey)) or (not s.edge and in_rect(x, y, s))) then ok = true; break end
    end
    if not ok then return "air" end
    if solid_at(x, y, h, a, self:all_solids()) then return "furniture" end
    local crowded = false
    self:near(x, y, F.MIN_GAP, function(q)
        if not crowded and abs(q.z - h) < 0.9 and (q.x - x) ^ 2 + (q.y - y) ^ 2 < F.MIN_GAP * F.MIN_GAP then crowded = true end
    end)
    if crowded then return "crowded" end
    local gap = F.BALL.r + F.BALL.clear
    for _, b in pairs(self.balls) do
        if abs(b.z - h) < 0.9 and (b.x - x) ^ 2 + (b.y - y) ^ 2 < gap * gap then return "crowded" end
    end
    if self:near_swing(x, y, h, F.SWING.clear) or self:near_switch(x, y, h, F.SWITCH.clear) then return "crowded" end
    return nil
end

function Board:can_place(x, y, h, a) return self:blocked(x, y, h, a) == nil end

function Board:_record(kind, p)
    local a = self.act
    if a then a[kind][#a[kind] + 1] = p end
end

function Board:place(x, y, a, h, paint)
    local why = self:blocked(x, y, h, a)
    if why then return nil, why end
    self.next_id = self.next_id + 1
    self.order = self.order + 1
    local p = { id = self.next_id, x = x, y = y, z = h, a = a or 0, paint = paint or "cream", order = self.order }
    self:_insert(p)
    self:_record("added", p)
    return p
end

-- Place on whichever surface under (x, y) suits: the one nearest near_h within a climb (a line stepping onto the
-- rug or up a book), or the highest when near_h is nil.
function Board:place_auto(x, y, a, paint, near_h)
    local cands = F.surfaces_at(x, y, a, self:all_surfaces())
    if near_h then
        table.sort(cands, function(p, q) return abs(p.h - near_h) < abs(q.h - near_h) end)
    end
    local why = "air"
    for _, s in ipairs(cands) do
        if near_h and abs(s.h - near_h) > F.CLIMB then break end
        local p, w = self:place(x, y, a, s.h, paint)
        if p then return p end
        if why == "air" or w == "full" then why = w end
    end
    return nil, why
end

-- Why a ball cannot rest at (x, y) on a surface of height h (nil if it can).
function Board:ball_blocked(x, y, h)
    local B = F.BALL
    if self.ball_count >= B.cap then return "full" end
    local ok = false
    for _, s in ipairs(ROOM.surfaces) do
        if abs(s.h - h) < 1e-4 and in_rect(x, y, s, s.edge and 0.2 or 0) then ok = true; break end
    end
    if not ok then return "air" end
    for _, s in ipairs(self:all_solids()) do
        if s.z0 < h + 2 * B.r - 0.01 and s.z1 > h + 0.01 and x + B.r > s.x0 and x - B.r < s.x1 and y + B.r > s.y0 and y - B.r < s.y1 then
            return "furniture"
        end
    end
    local gap, crowded = B.r + B.clear, false
    self:near(x, y, gap, function(q)
        if abs(q.z - h) < 0.9 and (q.x - x) ^ 2 + (q.y - y) ^ 2 < gap * gap then crowded = true end
    end)
    if crowded then return "crowded" end
    for _, b in pairs(self.balls) do
        if abs(b.z - h) < 0.9 and (b.x - x) ^ 2 + (b.y - y) ^ 2 < (2 * B.r) ^ 2 then return "crowded" end
    end
    if self:near_swing(x, y, h, B.r) or self:near_switch(x, y, h, B.r) then return "crowded" end
    return nil
end

function Board:can_place_ball(x, y, h) return self:ball_blocked(x, y, h) == nil end

function Board:place_ball(x, y, h)
    local why = self:ball_blocked(x, y, h)
    if why then return nil, why end
    self.next_id = self.next_id + 1
    self.order = self.order + 1
    local p = { kind = "ball", id = self.next_id, x = x, y = y, z = h, order = self.order }
    self:_insert(p)
    self:_record("added", p)
    return p
end

-- What a swing set down at (x, y) on height h hangs from: its string length, and "shelf" or "stand".
function F.swing_mount(x, y, h)
    local S = F.SWING
    for _, s in ipairs(ROOM.surfaces) do
        if s.name == "bookshelf" and x >= s.x0 + 0.5 and x <= s.x1 - 0.5 and y < s.y0 and y >= s.y0 - S.shelf_reach and h < s.h - 2 then
            return s.h - (h + S.lift + S.r), "shelf", s
        end
    end
    return S.len, "stand"
end

-- Why a swing cannot hang at (x, y) over a surface of height h, swinging along a (nil if it can).
function Board:swing_blocked(x, y, h, a)
    local S, B = F.SWING, F.BALL
    if self.swing_count >= S.cap then return "full" end
    local function on_surface(px, py, tol, margin)
        for _, s in ipairs(ROOM.surfaces) do
            if abs(s.h - h) <= tol and in_rect(px, py, s, s.edge and margin or 0) then return true end
        end
        return false
    end
    if not on_surface(x, y, 1e-4, 0.2) then return "air" end
    local z0, z1 = h + S.lift, h + S.lift + 2 * S.r
    local L, hang = F.swing_mount(x, y, h)
    for _, s in ipairs(self:all_solids()) do
        if s.z0 < z1 - 0.01 and s.z1 > z0 + 0.01 and x + S.r > s.x0 and x - S.r < s.x1 and y + S.r > s.y0 and y - S.r < s.y1 then
            return "furniture"
        end
    end
    local x1, y1, x2, y2 = F.swing_posts(x, y, a)
    local posts = hang == "stand" and { { x1, y1 }, { x2, y2 } } or {}
    for _, c in ipairs(posts) do
        if not on_surface(c[1], c[2], 0.2, S.post_r) then return "air" end
        for _, s in ipairs(self:all_solids()) do
            if s.z0 < h + L + S.lift + S.r and s.z1 > h + 0.01 and c[1] + S.post_r > s.x0 and c[1] - S.post_r < s.x1 and c[2] + S.post_r > s.y0 and c[2] - S.post_r < s.y1 then
                return "furniture"
            end
        end
    end
    -- The latch stands on the surface under the held bob.
    local lx, ly = F.swing_latch(x, y, a, L, hang)
    local SW = F.SWITCH
    if not on_surface(lx, ly, 0.2, SW.r) then return "air" end
    for _, s in ipairs(self:all_solids()) do
        if s.z0 < h + 2 * SW.r - 0.01 and s.z1 > h + 0.01 and lx + SW.r > s.x0 and lx - SW.r < s.x1 and ly + SW.r > s.y0 and ly - SW.r < s.y1 then
            return "furniture"
        end
    end
    local crowded = false
    if self:near_swing(lx, ly, h, SW.r) or self:near_switch(lx, ly, h, SW.r) then crowded = true end
    local lg = SW.r + SW.clear + W / 2
    self:near(lx, ly, lg, function(q)
        if abs(q.z - h) < 0.9 and (q.x - lx) ^ 2 + (q.y - ly) ^ 2 < lg * lg then crowded = true end
    end)
    local gap = S.r + S.clear
    self:near(x, y, gap, function(q)
        if abs(q.z - h) < 0.9 and (q.x - x) ^ 2 + (q.y - y) ^ 2 < gap * gap then crowded = true end
    end)
    for _, c in ipairs(posts) do
        local g = S.post_r + S.clear
        self:near(c[1], c[2], g + W / 2, function(q)
            if abs(q.z - h) < 0.9 and (q.x - c[1]) ^ 2 + (q.y - c[2]) ^ 2 < (g + W / 2) ^ 2 then crowded = true end
        end)
        if self:near_swing(c[1], c[2], h, S.post_r) or self:near_switch(c[1], c[2], h, S.post_r) then crowded = true end
    end
    for _, b in pairs(self.balls) do
        if abs(b.z - h) < 0.9 and (b.x - x) ^ 2 + (b.y - y) ^ 2 < (S.r + B.r) ^ 2 then crowded = true end
        for _, c in ipairs(posts) do
            if abs(b.z - h) < 0.9 and (b.x - c[1]) ^ 2 + (b.y - c[2]) ^ 2 < (S.post_r + B.r) ^ 2 then crowded = true end
        end
    end
    if self:near_swing(x, y, h, S.r) or self:near_switch(x, y, h, S.r) then crowded = true end
    return crowded and "crowded" or nil
end

function Board:can_place_swing(x, y, h, a) return self:swing_blocked(x, y, h, a) == nil end

function Board:place_swing(x, y, h, a)
    local why = self:swing_blocked(x, y, h, a)
    if why then return nil, why end
    local L, hang = F.swing_mount(x, y, h)
    self.next_id = self.next_id + 1
    self.order = self.order + 1
    local p = { kind = "swing", id = self.next_id, x = x, y = y, z = h, a = a, L = L, hang = hang, order = self.order }
    self:_insert(p)
    self:_record("added", p)
    return p
end

-- The swing whose ball is nearest (x, y) at about height h, within reach.
function Board:pick_swing(x, y, h, reach)
    reach = reach or F.SWING.r + 0.15
    local best, bd
    for _, s in pairs(self.swings) do
        local d = (s.x - x) ^ 2 + (s.y - y) ^ 2
        if (not h or abs(s.z - h) < 0.8) and d <= reach * reach and (not bd or d < bd or (d == bd and s.id < best.id)) then best, bd = s, d end
    end
    return best
end

-- The centre of a swing's ball (x, y, height) at angle th.
function F.swing_bob(p, th)
    local S = F.SWING
    local o = p.L * sin(th)
    return p.x + p.ax * o, p.y + p.ay * o, p.z + S.lift + S.r + p.L * (1 - cos(th))
end

-- Where the string is tied, above the ball at rest.
function F.swing_top(p) return p.z + F.SWING.lift + F.SWING.r + p.L end

-- Marks along the axis for the placing preview: as far each way as the ball is still low enough to strike a domino
-- standing on the same surface.
function F.swing_spots(x0, y0, x1, y1, h)
    local S = F.SWING
    local L, hang = F.swing_mount(x0, y0, h)
    local amp = hang == "shelf" and S.amp_shelf or S.amp
    local dx, dy = x1 - x0, y1 - y0
    local d = sqrt(dx * dx + dy * dy)
    if d < 0.5 then return {} end
    dx, dy = dx / d, dy / d
    local th = math.min(amp, math.acos(max(-1, min(1, 1 - (H - S.lift) / L))))
    local reach = L * sin(th)
    local out = {}
    local k = floor(reach / F.SPACING)
    for i = -k, k do out[#out + 1] = { x = x0 + dx * i * F.SPACING, y = y0 + dy * i * F.SPACING } end
    return out
end

-- Why a switch cannot stand at (x, y) on a surface of height h (nil if it can).
function Board:switch_blocked(x, y, h)
    local W_ = F.SWITCH
    if self.switch_count >= W_.cap then return "full" end
    local ok = false
    for _, s in ipairs(ROOM.surfaces) do
        if abs(s.h - h) < 1e-4 and in_rect(x, y, s, s.edge and W_.r or 0) then ok = true; break end
    end
    if not ok then return "air" end
    for _, s in ipairs(self:all_solids()) do
        if s.z0 < h + 2 * W_.r - 0.01 and s.z1 > h + 0.01 and x + W_.r > s.x0 and x - W_.r < s.x1 and y + W_.r > s.y0 and y - W_.r < s.y1 then
            return "furniture"
        end
    end
    local gap, crowded = W_.r + W_.clear, false
    self:near(x, y, gap, function(q)
        if abs(q.z - h) < 0.9 and (q.x - x) ^ 2 + (q.y - y) ^ 2 < gap * gap then crowded = true end
    end)
    for _, b in pairs(self.balls) do
        if abs(b.z - h) < 0.9 and (b.x - x) ^ 2 + (b.y - y) ^ 2 < (W_.r + F.BALL.r) ^ 2 then crowded = true end
    end
    if crowded or self:near_swing(x, y, h, W_.r) or self:near_switch(x, y, h, W_.r) then return "crowded" end
    return nil
end

function Board:can_place_switch(x, y, h) return self:switch_blocked(x, y, h) == nil end

function Board:place_switch(x, y, h)
    local why = self:switch_blocked(x, y, h)
    if why then return nil, why end
    self.next_id = self.next_id + 1
    self.order = self.order + 1
    local p = { kind = "switch", id = self.next_id, x = x, y = y, z = h, dir = 1, lamp = false, order = self.order }
    self:_insert(p)
    self:_record("added", p)
    return p
end

function Board:pick_switch(x, y, h, reach)
    reach = reach or F.SWITCH.r + 0.15
    local best, bd
    for _, s in pairs(self.switches) do
        local d = (s.x - x) ^ 2 + (s.y - y) ^ 2
        if (not h or abs(s.z - h) < 0.8) and d <= reach * reach and (not bd or d < bd or (d == bd and s.id < best.id)) then best, bd = s, d end
    end
    return best
end

-- Change a switch's settings as part of the current action, so undo and redo can put them back.
function Board:_change_switch(p, target, dir, lamp)
    local a = self.act
    if a then
        a.changes[#a.changes + 1] = { p = p, before = { p.target, p.dir, p.lamp }, after = { target, dir, lamp } }
    end
    p.target, p.dir, p.lamp = target, dir, lamp
    self.rev = self.rev + 1
end

-- Link a switch to the domino it starts; linking the same domino again turns the push round.
function Board:link_switch(p, id)
    if p.target == id then self:_change_switch(p, id, -p.dir, p.lamp)
    else self:_change_switch(p, id, 1, p.lamp) end
end

function Board:set_switch_lamp(p, on) self:_change_switch(p, p.target, p.dir, on) end

-- Fit a ramp to a drag between two surfaces: its low end stays where it was dragged from or to, it runs along the
-- nearer room axis, and its top stops at the edge of the higher surface. Returns the ramp's ends, or nil and why.
function Board:fit_ramp(x0, y0, h0, x1, y1, h1)
    local R = F.RAMP
    if abs(h1 - h0) < 0.01 then return nil, "flat" end
    if h1 < h0 then x0, y0, h0, x1, y1, h1 = x1, y1, h1, x0, y0, h0 end
    if self.ramp_count >= R.cap then return nil, "full" end
    local dx, dy = x1 - x0, y1 - y0
    local on_x = abs(dx) >= abs(dy)
    local sgn = (on_x and dx or dy) >= 0 and 1 or -1
    local top
    for _, s in ipairs(ROOM.surfaces) do
        if abs(s.h - h1) < 1e-4 and in_rect(x1, y1, s) then top = s; break end
    end
    if not top then return nil, "air" end
    local hw = R.width / 2
    local cross, c0, c1 = on_x and y0 or x0, on_x and top.y0 or top.x0, on_x and top.y1 or top.x1
    if cross - hw < c0 or cross + hw > c1 then return nil, "air" end
    local rim = sgn > 0 and (on_x and top.x0 or top.y0) or (on_x and top.x1 or top.y1)
    local from = on_x and x0 or y0
    if (rim - from) * sgn <= 0 then return nil, "air" end
    local L = abs(rim - from)
    local n = max(1, math.ceil((h1 - h0) / R.rise - 1e-9))
    if L < n * R.run then return nil, "steep" end
    local fit = { kind = "ramp", x0 = x0, y0 = y0, z0 = h0, x1 = on_x and rim or x0, y1 = on_x and y0 or rim, z1 = h1 }
    ramp_build(fit)
    -- Clear of furniture, other ramps and everything standing there.
    local e = 1e-3
    local solids = self:all_solids()
    for _, st in ipairs(fit.solids) do
        for _, s in ipairs(solids) do
            if s.z0 < st.z1 - 0.01 and s.z1 > st.z0 + 0.01 and st.x1 - e > s.x0 and st.x0 + e < s.x1 and st.y1 - e > s.y0 and st.y0 + e < s.y1 then
                return nil, "furniture"
            end
        end
    end
    local cx, cy = (fit.fx0 + fit.fx1) / 2, (fit.fy0 + fit.fy1) / 2
    local radius = sqrt((fit.fx1 - cx) ^ 2 + (fit.fy1 - cy) ^ 2)
    local function inside(px, py, pad, pz)
        return pz >= h0 - 0.9 and pz <= h1 and px > fit.fx0 - pad and px < fit.fx1 + pad and py > fit.fy0 - pad and py < fit.fy1 + pad
    end
    local crowded = false
    self:near(cx, cy, radius + 1, function(q) if inside(q.x, q.y, 0.1, q.z) then crowded = true end end)
    for _, list in ipairs({ { self.balls, F.BALL.r }, { self.swings, F.SWING.r }, { self.switches, F.SWITCH.r } }) do
        for _, q in pairs(list[1]) do if inside(q.x, q.y, list[2], q.z) then crowded = true end end
    end
    for _, sw in pairs(self.swings) do
        if sw.hang == "stand" then
            local px1, py1, px2, py2 = F.swing_posts(sw.x, sw.y, sw.a)
            if inside(px1, py1, F.SWING.post_r, sw.z) or inside(px2, py2, F.SWING.post_r, sw.z) then crowded = true end
        end
    end
    if crowded then return nil, "crowded" end
    return fit
end

function Board:place_ramp(x0, y0, h0, x1, y1, h1)
    local p, why = self:fit_ramp(x0, y0, h0, x1, y1, h1)
    if not p then return nil, why end
    self.next_id = self.next_id + 1
    self.order = self.order + 1
    p.id, p.order = self.next_id, self.order
    self:_insert(p)
    self:_record("added", p)
    return p
end

-- The ramp under (x, y) at about height h.
function Board:pick_ramp(x, y, h)
    local ids, best = {}, nil
    for id in pairs(self.ramps) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local r = self.ramps[id]
        if x >= r.fx0 and x <= r.fx1 and y >= r.fy0 and y <= r.fy1 and (not h or (h >= r.z0 - 0.3 and h <= r.z1 + 0.3)) then best = r end
    end
    return best
end

-- Marks for the placing preview: up the middle of a fitted ramp.
function F.ramp_spots(r)
    local out = {}
    for k = 0, 12 do
        local u = k / 12
        out[#out + 1] = { x = r.x0 + (r.x1 - r.x0) * u, y = r.y0 + (r.y1 - r.y0) * u, h = r.z0 + (r.z1 - r.z0) * u }
    end
    return out
end

-- The ball nearest (x, y) at about height h, within reach.
function Board:pick_ball(x, y, h, reach)
    reach = reach or F.BALL.r + 0.15
    local best, bd
    for _, b in pairs(self.balls) do
        local d = (b.x - x) ^ 2 + (b.y - y) ^ 2
        if (not h or abs(b.z - h) < 0.8) and d <= reach * reach and (not bd or d < bd or (d == bd and b.id < best.id)) then best, bd = b, d end
    end
    return best
end

function Board:remove(id)
    local p = self.pieces[id] or self.balls[id] or self.swings[id] or self.switches[id] or self.ramps[id]
    if not p then return nil end
    self:_extract(p)
    self:_record("removed", p)
    if p.kind == "ramp" then
        -- Dominoes standing on it go with it (one action, so undo brings them back).
        local riders = {}
        local cx, cy = (p.fx0 + p.fx1) / 2, (p.fy0 + p.fy1) / 2
        self:near(cx, cy, sqrt((p.fx1 - cx) ^ 2 + (p.fy1 - cy) ^ 2) + 1, function(q)
            if q.z > p.z0 + 0.01 and q.z < p.z1 - 1e-4 and q.x >= p.fx0 and q.x <= p.fx1 and q.y >= p.fy0 and q.y <= p.fy1 then riders[#riders + 1] = q.id end
        end)
        table.sort(riders)
        for _, rid in ipairs(riders) do self:remove(rid) end
    end
    if self.start and self.start.id == id then
        if self.act then
            self.act.start_before = self.act.start_before or { v = self.start }
            self.act.start_after = { v = nil }
        end
        self.start = nil
    end
    return p
end

-- The domino nearest (x, y) at about height h, within reach.
function Board:pick(x, y, h, reach)
    reach = reach or 0.45
    local best, bd
    self:near(x, y, reach, function(q)
        if not h or abs(q.z - h) < 0.8 then
            local d = (q.x - x) ^ 2 + (q.y - y) ^ 2
            if d <= reach * reach and (not bd or d < bd) then best, bd = q, d end
        end
    end)
    return best
end

function Board:erase_at(x, y, h, r)
    local gone = {}
    self:near(x, y, r, function(q)
        if (not h or abs(q.z - h) < 0.8) and (q.x - x) ^ 2 + (q.y - y) ^ 2 <= r * r then gone[#gone + 1] = q.id end
    end)
    for _, b in pairs(self.balls) do
        if (not h or abs(b.z - h) < 0.8) and (b.x - x) ^ 2 + (b.y - y) ^ 2 <= r * r then gone[#gone + 1] = b.id end
    end
    for _, s in pairs(self.swings) do
        if (not h or abs(s.z - h) < 0.8) and (s.x - x) ^ 2 + (s.y - y) ^ 2 <= r * r then gone[#gone + 1] = s.id end
    end
    for _, s in pairs(self.switches) do
        if (not h or abs(s.z - h) < 0.8) and (s.x - x) ^ 2 + (s.y - y) ^ 2 <= r * r then gone[#gone + 1] = s.id end
    end
    -- A ramp goes only when the brush finds nothing standing: a stroke over its dominoes must not take the ramp too.
    if #gone == 0 then
        local p = self:pick_ramp(x, y, h)
        if p then gone[1] = p.id end
    end
    for _, id in ipairs(gone) do self:remove(id) end
    return #gone
end

-- The domino the tip knocks over, and which way (+1 along its facing, -1 against): the one you chose, else the
-- first placed.
function Board:starter()
    local s = self.start
    if s and self.pieces[s.id] then return self.pieces[s.id], s.dir end
    local first
    for _, p in pairs(self.pieces) do if not first or p.order < first.order then first = p end end
    return first, 1
end

-- Choose the starting domino; choosing it again turns the push around.
function Board:set_start(id)
    local before = self.start and { id = self.start.id, dir = self.start.dir } or nil
    local p, dir = self:starter()
    if p and p.id == id then
        self.start = { id = id, dir = -dir }
    else
        self.start = { id = id, dir = 1 }
    end
    if self.act then self.act.start_before = self.act.start_before or { v = before }; self.act.start_after = { v = self.start } end
    self.rev = self.rev + 1
end

------------------------------------------------------------------ undo / redo (one action per stroke or shape)
function Board:begin_action()
    self.act = { added = {}, removed = {}, changes = {} }
end

function Board:end_action()
    local a = self.act
    self.act = nil
    if not a or (#a.added == 0 and #a.removed == 0 and #a.changes == 0 and not a.start_after) then return false end
    self.undo_stack[#self.undo_stack + 1] = a
    if #self.undo_stack > 200 then table.remove(self.undo_stack, 1) end
    self.redo_stack = {}
    return true
end

function Board:undo()
    local a = table.remove(self.undo_stack)
    if not a then return false end
    for i = #a.added, 1, -1 do self:_extract(a.added[i]) end
    for _, p in ipairs(a.removed) do self:_insert(p) end
    for i = #a.changes, 1, -1 do
        local c = a.changes[i]
        c.p.target, c.p.dir, c.p.lamp = c.before[1], c.before[2], c.before[3]
        self.rev = self.rev + 1
    end
    if a.start_before then self.start = a.start_before.v end
    self.redo_stack[#self.redo_stack + 1] = a
    return true
end

function Board:redo()
    local a = table.remove(self.redo_stack)
    if not a then return false end
    for _, p in ipairs(a.added) do self:_insert(p) end
    for _, p in ipairs(a.removed) do self:_extract(p) end
    for _, c in ipairs(a.changes) do
        c.p.target, c.p.dir, c.p.lamp = c.after[1], c.after[2], c.after[3]
        self.rev = self.rev + 1
    end
    if a.start_after then self.start = a.start_after.v end
    self.undo_stack[#self.undo_stack + 1] = a
    return true
end

function Board:clear()
    self:begin_action()
    local ids = {}
    for id in pairs(self.pieces) do ids[#ids + 1] = id end
    for id in pairs(self.balls) do ids[#ids + 1] = id end
    for id in pairs(self.swings) do ids[#ids + 1] = id end
    for id in pairs(self.switches) do ids[#ids + 1] = id end
    for id in pairs(self.ramps) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do self:remove(id) end
    return self:end_action()
end

------------------------------------------------------------------ shapes
-- The next spot along a stroke from the last domino (lx, ly at height lz) toward the cursor: a full spacing on,
-- nudged up to 0.3 farther when that spot is taken or blocked (a line climbing a book finds its footing).
function Board:stroke_step(lx, ly, lz, cx, cy, paint)
    local dx, dy = cx - lx, cy - ly
    local d = sqrt(dx * dx + dy * dy)
    if d < F.SPACING then return nil, "wait" end
    dx, dy = dx / d, dy / d
    local a = atan2(dy, dx)
    local why
    for k = 0, 3 do
        local s = F.SPACING + 0.1 * k
        if s > d then return nil, "wait" end
        local p, w = self:place_auto(lx + dx * s, ly + dy * s, a, paint, lz)
        if p then return p end
        why = w
    end
    return nil, why, lx + dx * F.SPACING, ly + dy * F.SPACING
end

function F.line_spots(x0, y0, x1, y1)
    local dx, dy = x1 - x0, y1 - y0
    local L = sqrt(dx * dx + dy * dy)
    local a = L > 1e-6 and atan2(dy, dx) or 0
    local out = {}
    local n = floor(L / F.SPACING + 1e-6)
    for i = 0, n do
        local s = i * F.SPACING
        out[#out + 1] = { x = x0 + cos(a) * s, y = y0 + sin(a) * s, a = a }
    end
    return out
end

-- An Archimedean spiral from radius R (starting on the side of (sx, sy)) winding in to SPIRAL_MIN, outer end
-- first, each domino facing along the way the chain runs. cw winds clockwise.
function F.spiral_spots(cx, cy, sx, sy, cw)
    local R = sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2)
    local out = {}
    if R < F.SPIRAL_MIN + 0.5 then return out end
    local b = F.SPIRAL_GAP / (2 * pi)
    local ang = atan2(sy - cy, sx - cx)
    local sgn = cw and -1 or 1
    local r = R
    while r > F.SPIRAL_MIN and #out < 4000 do
        local ca, sa = cos(ang), sin(ang)
        local tx, ty = -b * ca - r * sa * sgn, -b * sa + r * ca * sgn
        out[#out + 1] = { x = cx + r * ca, y = cy + r * sa, a = atan2(ty, tx) }
        local dphi = F.SPACING / sqrt(r * r + b * b)
        ang = ang + dphi * sgn
        r = r - b * dphi
    end
    return out
end

-- A field: from its point at (ax, ay) it fans out row by row toward (bx, by) until it is `width` wide, then runs
-- on at that width. Rows are staggered, so each domino strikes the two in the row ahead and the wave fills it all.
function F.field_spots(ax, ay, bx, by, width)
    local dx, dy = bx - ax, by - ay
    local L = sqrt(dx * dx + dy * dy)
    local out = {}
    if L < 1e-6 then return { { x = ax, y = ay, a = 0, row = 0 } } end
    local ux, uy = dx / L, dy / L
    local px, py = -uy, ux
    local a = atan2(uy, ux)
    local nmax = max(1, floor(width / F.FIELD_LAT + 1e-6) + 1)
    local rows = floor(L / F.SPACING + 1e-6) + 1
    for k = 0, rows - 1 do
        local n
        if k + 1 <= nmax then n = k + 1 else n = ((k - nmax) % 2 == 0) and (nmax - 1) or nmax end
        if n < 1 then n = 1 end
        for i = 0, n - 1 do
            local l = (-(n - 1) / 2 + i) * F.FIELD_LAT
            local s = k * F.SPACING
            out[#out + 1] = { x = ax + ux * s + px * l, y = ay + uy * s + py * l, a = a, row = k, col = i }
        end
    end
    return out
end

-- A field's colours: the paints in diagonal bands, so no two neighbouring dominoes match and the wave shows them.
function F.field_paint(i, s)
    if s and s.row then return F.PAINTS[(s.row + (s.col or 0)) % #F.PAINTS + 1] end
    return F.PAINTS[floor((i - 1) / 6) % #F.PAINTS + 1]
end

-- Place a list of spots in order, each on the surface nearest the one before (a whole shape keeps to one level,
-- stepping on and off the rug). paint(i) picks each colour. Returns how many stood.
function Board:place_spots(spots, paint, h0)
    local n, last = 0, h0
    for i, s in ipairs(spots) do
        local p = self:place_auto(s.x, s.y, s.a, paint and paint(i, s) or "cream", s.row and h0 or last)
        if p then n = n + 1; last = p.z end
    end
    return n
end

-- A straight line from (x0, y0) to (x1, y1), walked like a stroke: each domino a spacing on from the last, nudged
-- forward when its spot is taken (so it finds its footing on a book's step), skipping past anything solid.
function Board:place_line(x0, y0, x1, y1, paint, h0)
    local n = 0
    local first, why = self:place_auto(x0, y0, atan2(y1 - y0, x1 - x0), paint and paint(1) or "cream", h0)
    local lx, ly, lz = x0, y0, h0
    if first then n, lz = 1, first.z end
    for _ = 1, 10000 do
        local p, w, gx, gy = self:stroke_step(lx, ly, lz, x1, y1, paint and paint(n + 1) or "cream")
        if p then
            n = n + 1
            lx, ly, lz = p.x, p.y, p.z
        elseif gx then
            lx, ly = gx, gy                 -- blocked here: leave a gap and carry on beyond it
            why = w
        else
            break
        end
    end
    return n, why
end

-- Lay dominoes along a smooth path through waypoints (Catmull-Rom), walked like a stroke. Returns the last domino.
function Board:place_path(pts, paint, h0)
    local first = self:place_auto(pts[1][1], pts[1][2], atan2(pts[2][2] - pts[1][2], pts[2][1] - pts[1][1]), paint and paint(1) or "cream", h0)
    local lx, ly, lz = pts[1][1], pts[1][2], first and first.z or h0
    local last, n = first, first and 1 or 0
    for i = 1, #pts - 1 do
        local p0, p1, p2, p3 = pts[max(1, i - 1)], pts[i], pts[i + 1], pts[min(#pts, i + 2)]
        for k = 1, 40 do
            local t = k / 40
            local t2, t3 = t * t, t * t * t
            local cx = 0.5 * (2 * p1[1] + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            local cy = 0.5 * (2 * p1[2] + (-p0[2] + p2[2]) * t + (2 * p0[2] - 5 * p1[2] + 4 * p2[2] - p3[2]) * t2 + (-p0[2] + 3 * p1[2] - 3 * p2[2] + p3[2]) * t3)
            for _ = 1, 4 do
                local p, _, gx, gy = self:stroke_step(lx, ly, lz, cx, cy, paint and paint(n + 1) or "cream")
                if p then lx, ly, lz, last, n = p.x, p.y, p.z, p, n + 1
                elseif gx then lx, ly = gx, gy
                else break end
            end
        end
    end
    return last, n
end

-- The build a first visit opens on: a line from the front of the room that winds across the floor, climbs the
-- staircase of books and comes down the other side, then swings round and fans out into a field across the open
-- floor.
function F.demo(board)
    board:begin_action()
    local k = 0
    local function rainbow() k = k + 1; return F.PAINTS[floor((k - 1) / 6) % 5 + 1] end
    local last = board:place_path({ { -26, -29 }, { -14, -29.5 }, { -2, -28.5 }, { 5, -25 }, { 8.5, -19.5 }, { 12, -19 },
        { 24, -19 }, { 36.5, -19 }, { 37.6, -15 }, { 36, -10 }, { 31, -6 }, { 27, -3.5 } }, rainbow, 0)
    if last then
        local ax, ay = cos(last.a), sin(last.a)
        local sx, sy = last.x + ax * F.SPACING, last.y + ay * F.SPACING
        board:place_spots(F.field_spots(sx, sy, sx + ax * 26, sy + ay * 26, 9.6), F.field_paint, last.z)
    end
    board.start = nil
    board:end_action()
    board.undo_stack, board.redo_stack = {}, {}
    return board
end

------------------------------------------------------------------ simulation
-- Seconds for a faller of height h to tip through theta (radians): slow start, quick finish.
function F.fall_time(theta, h)
    return F.TIME_K * (0.03 + 0.14 * (max(0, theta) / (pi / 2)) ^ 0.7) * sqrt(h or H)
end

-- The angle (radians) at which a faller of height h, pivoting on its front edge, first touches something whose near
-- face is c ahead and which spans heights zb..zt relative to the faller's base. nil if it never does.
function F.contact_angle(c, zb, zt, h)
    h = h or H
    if c >= h or zt <= 0 then return nil end
    c = max(c, 0.02)
    local top = sqrt(h * h - c * c)
    if top < zb then return nil end           -- it passes under: the thing stands too high
    if top <= zt then return asin(c / h) end  -- its top edge meets the face
    return atan2(c, zt)                       -- it comes down on the top edge of something lower
end

-- Distance along (fx, fy) from (px, py) at which a ray first meets the box (2D slab test), or nil.
local function ray_box1(px, py, fx, fy, s, reach)
    local x0, x1, y0, y1 = s.x0, s.x1, s.y0, s.y1
    local t0, t1 = -1e9, 1e9
    if abs(fx) < 1e-9 then
        if px < x0 or px > x1 then return nil end
    else
        local a, b = (x0 - px) / fx, (x1 - px) / fx
        if a > b then a, b = b, a end
        t0, t1 = max(t0, a), min(t1, b)
    end
    if abs(fy) < 1e-9 then
        if py < y0 or py > y1 then return nil end
    else
        local a, b = (y0 - py) / fy, (y1 - py) / fy
        if a > b then a, b = b, a end
        t0, t1 = max(t0, a), min(t1, b)
    end
    if t1 < max(t0, 0) or t0 > reach then return nil end
    return max(0, t0)
end
-- The same for a band hw either side of the ray (the faller's width): the nearest of its middle and its edges, which
-- for a box is where the band first meets it.
local function ray_box(px, py, fx, fy, hw, s, reach)
    local best = ray_box1(px, py, fx, fy, s, reach)
    for _, o in ipairs({ -hw, hw }) do
        local c = ray_box1(px - fy * o, py + fx * o, fx, fy, s, reach)
        if c and (not best or c < best) then best = c end
    end
    return best
end

local function heap_push(hp, job)
    local n = hp.n + 1
    hp.n = n
    hp[n] = job
    while n > 1 do
        local pa = floor(n / 2)
        local a, b = hp[pa], hp[n]
        if a.t < b.t or (a.t == b.t and a.seq < b.seq) then break end
        hp[pa], hp[n] = b, a
        n = pa
    end
end
local function heap_pop(hp)
    local top = hp[1]
    local n = hp.n
    hp[1] = hp[n]; hp[n] = nil
    n = n - 1
    hp.n = n
    local i = 1
    while true do
        local l, r = 2 * i, 2 * i + 1
        local m = i
        if l <= n and (hp[l].t < hp[m].t or (hp[l].t == hp[m].t and hp[l].seq < hp[m].seq)) then m = l end
        if r <= n and (hp[r].t < hp[m].t or (hp[r].t == hp[m].t and hp[r].seq < hp[m].seq)) then m = r end
        if m == i then break end
        hp[i], hp[m] = hp[m], hp[i]
        i = m
    end
    return top
end

-- The height a ball whose base is at z comes to rest on at (x, y): the highest surface or furniture top it can reach.
local function ball_ground(x, y, z)
    local g, lim = 0, z + F.BALL.step
    for _, s in ipairs(ROOM.surfaces) do
        if s.h > g and s.h <= lim and x >= s.x0 and x <= s.x1 and y >= s.y0 and y <= s.y1 then g = s.h end
    end
    for _, s in ipairs(ROOM.solids) do
        if s.z1 > g and s.z1 <= lim and x >= s.x0 and x <= s.x1 and y >= s.y0 and y <= s.y1 then g = s.z1 end
    end
    return g
end

-- The kick a domino falling through th gives a ball it meets at arm from its pivot: the domino's tip speed from the
-- energy it has lost falling, the ball's share of a collision with the domino's effective mass there, and 5/7 of
-- that left once the ball has stopped sliding and is rolling.
function F.ball_kick(th, arm)
    local B = F.BALL
    arm = min(H, max(0.1, arm))
    local omega = sqrt(3 * B.g / H * (1 - cos(th)))
    local eff = B.domino * H * H / (3 * arm * arm)
    return (1 + B.e) * eff / (eff + B.mass) * omega * arm * 5 / 7
end

-- A run, advanced in time: advance(t) works through everything due by t. With ext (ext.ball(p, t, dx, dy, speed) and
-- ext.swing(p, t)) the engine's rigid bodies move the balls and swings, and strike_ball / strike_bob feed what they
-- meet back into the chain; without it they are stepped here, which is what the tests and the build preview use.
function F.begin_run(board, ext)
    local res = { falls = {}, order = {}, events = {}, toppled = 0, total = board.count, duration = 0, gaps = {}, balls = {}, swings = {}, switches = {} }
    local st, sdir = board:starter()
    if not st then
        return { res = res, advance = function() end, finish = function() end, pending = function() return false end,
            strike_ball = function() end, strike_bob = function() end }
    end
    local hp, seq = { n = 0 }, 0
    local function push(t, p, dx, dy, speed)
        seq = seq + 1
        heap_push(hp, { t = t, p = p, dx = dx, dy = dy, speed = speed, seq = seq })
    end
    push(0, st, st.ax * sdir, st.ay * sdir)
    local done, wobbled = {}, {}
    local solids = board:all_solids()
    local reach = H + W
    local hit_q, hit_th, hit_kick = {}, {}, {}
    local B = F.BALL
    local RP = F.RAMP
    local ramp_list = {}
    for _, r in pairs(board.ramps) do ramp_list[#ramp_list + 1] = r end
    table.sort(ramp_list, function(a, b) return a.id < b.id end)
    -- The height of a slope under (x, y) that a ball whose base is at z can get onto, and the ramp. It runs along the
    -- steps' near corners, so the ball clears them.
    local function ramp_ground(x, y, z)
        local g, on
        for i = 1, #ramp_list do
            local r = ramp_list[i]
            if x >= r.fx0 and x <= r.fx1 and y >= r.fy0 and y <= r.fy1 then
                local s = abs(r.on_x and x - r.x0 or y - r.y0)
                local h = min(r.z1, r.z0 + r.rise + r.slope * s)
                -- (in the first step, a ball at the foot gets on however far in this time step carried it)
                local at_foot = s <= r.d and z >= r.z0 - 1e-3 and z <= h
                if (h <= z + B.step + 1e-6 or at_foot) and (not g or h > g) then g, on = h, r end
            end
        end
        return g, on
    end
    local ball_list = {}
    for _, b in pairs(board.balls) do ball_list[#ball_list + 1] = b end
    table.sort(ball_list, function(a, b) return a.id < b.id end)
    local S = F.SWING
    local swing_list = {}
    for _, s in pairs(board.swings) do swing_list[#swing_list + 1] = s end
    table.sort(swing_list, function(a, b) return a.id < b.id end)
    -- What a falling domino can strike besides dominoes (a swing: its latch).
    local target_list = {}
    for _, b in ipairs(ball_list) do target_list[#target_list + 1] = b end
    for _, s in ipairs(swing_list) do target_list[#target_list + 1] = s end
    local SW = F.SWITCH
    local switch_list = {}
    for _, s in pairs(board.switches) do switch_list[#switch_list + 1] = s end
    table.sort(switch_list, function(a, b) return a.id < b.id end)
    for _, s in ipairs(switch_list) do target_list[#target_list + 1] = s end
    local lamp_on = true
    -- A switch: goes once, starts its domino and works the lamp.
    local function press_switch(p, t)
        done[p.id] = true
        local e = { id = p.id, t = t }
        if p.lamp then lamp_on = not lamp_on; e.lamp_on = lamp_on end
        res.switches[#res.switches + 1] = e
        if t > res.duration then res.duration = t end
        local q = p.target and board.pieces[p.target]
        if q then
            e.target = q.id
            push(t + SW.delay, q, q.ax * p.dir, q.ay * p.dir)
        end
    end
    -- A stand's posts and the switches are solid like furniture.
    if #swing_list + #switch_list > 0 then
        local all = {}
        for i = 1, #solids do all[i] = solids[i] end
        for _, s in ipairs(swing_list) do
            all[#all + 1] = { name = "latch", x0 = s.lx - SW.r, x1 = s.lx + SW.r, y0 = s.ly - SW.r, y1 = s.ly + SW.r, z0 = s.z, z1 = s.z + 2 * SW.r, switch = s }
            if s.hang == "stand" then
                local x1, y1, x2, y2 = F.swing_posts(s.x, s.y, s.a)
                for _, c in ipairs({ { x1, y1 }, { x2, y2 } }) do
                    all[#all + 1] = { name = "swing post", x0 = c[1] - S.post_r, x1 = c[1] + S.post_r, y0 = c[2] - S.post_r, y1 = c[2] + S.post_r,
                        z0 = s.z, z1 = F.swing_top(s) }
                end
            end
        end
        for _, s in ipairs(switch_list) do
            all[#all + 1] = { name = "switch", x0 = s.x - SW.r, x1 = s.x + SW.r, y0 = s.y - SW.r, y1 = s.y + SW.r, z0 = s.z, z1 = s.z + 2 * SW.r, switch = s }
        end
        solids = all
    end
    local function push_ball(t, b)
        seq = seq + 1
        heap_push(hp, { t = t, ball = b, seq = seq })
    end
    local function launch(p, t, dx, dy, speed)
        done[p.id] = true
        if ext then ext.ball(p, t, dx, dy, speed); return end
        local b = { id = p.id, p = p, x = p.x, y = p.y, z = p.z, vx = dx * speed, vy = dy * speed, vz = 0, air = false, t0 = t, n = 0,
            pts = { t, p.x, p.y, p.z }, bumps = {} }
        res.balls[#res.balls + 1] = b
        push_ball(t + B.dt, b)
    end
    local function ball_stops(b, t)
        local P = b.pts
        P[#P + 1], P[#P + 2], P[#P + 3], P[#P + 4] = t, b.x, b.y, b.z
        b.t_end = t
        if t > res.duration then res.duration = t end
    end
    -- One time step of a ball in flight. It runs in the same queue as the dominoes, so what it finds standing is what
    -- is really standing at that moment; dominoes already falling are rolled over.
    local function step_ball(b, t)
        local dt, r, z0 = B.dt, B.r, b.z
        if b.air then b.vz = b.vz - B.g * dt end
        local air = max(0, 1 - B.air * sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz) * dt)
        b.vx, b.vy, b.vz = b.vx * air, b.vy * air, b.vz * air
        b.x, b.y, b.z = b.x + b.vx * dt, b.y + b.vy * dt, b.z + b.vz * dt
        local g = ball_ground(b.x, b.y, max(z0, b.z))
        local rg, ramp = ramp_ground(b.x, b.y, max(z0, b.z))
        if rg and rg >= g then g = rg else ramp = nil end
        b.ramp = ramp
        if b.air then
            if b.z <= g and b.vz <= 0 then
                b.z = g
                local drop = -b.vz
                if drop > 1 then b.bumps[#b.bumps + 1] = t end
                if drop > B.min_bounce then
                    b.vz, b.vx, b.vy = drop * B.bounce, b.vx * 0.85, b.vy * 0.85
                else
                    b.air, b.vz = false, 0
                end
            end
        elseif g < b.z - (ramp and 0.5 or 1e-3) then
            b.air, b.vz = true, 0
        else
            b.z = g
            if ramp then
                local a = B.g * RP.grav * ramp.slope / (1 + ramp.slope * ramp.slope) * dt     -- along the slope, horizontal part
                b.vx, b.vy = b.vx - ramp.ux * a, b.vy - ramp.uy * a
            end
            local s = sqrt(b.vx * b.vx + b.vy * b.vy)
            if s > 1e-6 then
                local k = max(0, s - B.drag * dt) / s
                b.vx, b.vy = b.vx * k, b.vy * k
            end
        end
        for i = 1, #solids do
            local s = solids[i]
            -- A ball rolls a ramp as a slope, so its steps only stop it from the sides.
            local on_slope = s.ramp and (s.ramp.on_x and abs(b.y - s.ramp.y0) <= RP.width / 2 or (not s.ramp.on_x) and abs(b.x - s.ramp.x0) <= RP.width / 2)
            if not on_slope and b.z < s.z1 - 0.01 and b.z + 2 * r > s.z0 then
                local nx, ny = b.x - max(s.x0, min(s.x1, b.x)), b.y - max(s.y0, min(s.y1, b.y))
                local d2 = nx * nx + ny * ny
                if d2 < r * r then
                    -- From any side or from above, a switch feels the whole speed of the ball.
                    if s.switch and not done[s.switch.id] and sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz) >= B.min_hit then
                        push(t, s.switch, 1, 0)
                        b.bumps[#b.bumps + 1] = t
                    end
                    local d = sqrt(d2)
                    if d < 1e-6 then
                        local sp = sqrt(b.vx * b.vx + b.vy * b.vy)
                        if sp > 1e-6 then nx, ny = -b.vx / sp, -b.vy / sp else nx, ny = 1, 0 end
                        d = 1
                        b.x, b.y = b.x + nx * r, b.y + ny * r
                    else
                        b.x, b.y = b.x + nx / d * (r - d), b.y + ny / d * (r - d)
                    end
                    nx, ny = nx / d, ny / d
                    local vn = b.vx * nx + b.vy * ny
                    if vn < 0 then
                        b.vx, b.vy = b.vx - 1.5 * vn * nx, b.vy - 1.5 * vn * ny
                        if vn < -1 then b.bumps[#b.bumps + 1] = t end
                    end
                end
            end
        end
        -- Standing dominoes: boxes, tested against the ball.
        local cz = b.z + r
        board:near(b.x, b.y, r + W, function(q)
            if not done[q.id] and cz + r > q.z and cz - r < q.z + H then
                local rx, ry = b.x - q.x, b.y - q.y
                local u, v = rx * q.ax + ry * q.ay, ry * q.ax - rx * q.ay
                local cu, cv = max(-T / 2, min(T / 2, u)), max(-W / 2, min(W / 2, v))
                local ch = max(q.z, min(q.z + H, cz))
                local du, dv, dh = u - cu, v - cv, cz - ch
                if du * du + dv * dv + dh * dh < r * r then
                    local s = sqrt(b.vx * b.vx + b.vy * b.vy)
                    local dx, dy = s > 1e-6 and b.vx / s or 0, s > 1e-6 and b.vy / s or 0
                    if s * s + b.vz * b.vz >= B.min_hit * B.min_hit then      -- (falling on it counts as well)
                        push(t, q, dx, dy)
                        b.bumps[#b.bumps + 1] = t
                    end
                    -- The domino is the heavier: the ball comes back off it, whether or not it tips.
                    local nx, ny = du * q.ax - dv * q.ay, du * q.ay + dv * q.ax
                    local n = sqrt(nx * nx + ny * ny)
                    if n < 1e-6 then nx, ny, n = -dx, -dy, 1 end
                    nx, ny = nx / n, ny / n
                    local vn = b.vx * nx + b.vy * ny
                    if vn < 0 then b.vx, b.vy = b.vx - (1 + B.rebound) * vn * nx, b.vy - (1 + B.rebound) * vn * ny end
                end
            end
        end)
        -- Balls at rest: it hands on most of its speed.
        for i = 1, #ball_list do
            local q = ball_list[i]
            if q ~= b.p and not done[q.id] then
                local dx, dy, dz = q.x - b.x, q.y - b.y, q.z - b.z
                if dx * dx + dy * dy + dz * dz < 4 * r * r then
                    local s = sqrt(b.vx * b.vx + b.vy * b.vy)
                    if s >= B.min_hit then
                        local d = max(1e-6, sqrt(dx * dx + dy * dy))
                        launch(q, t, dx / d, dy / d, s * (1 + B.e) / 2)
                        b.vx, b.vy = b.vx * (1 - B.keep), b.vy * (1 - B.keep)
                        b.bumps[#b.bumps + 1] = t
                    end
                end
            end
        end
        b.n = b.n + 1
        if b.n % 4 == 0 then
            local P = b.pts
            P[#P + 1], P[#P + 2], P[#P + 3], P[#P + 4] = t, b.x, b.y, b.z
        end
        local s = sqrt(b.vx * b.vx + b.vy * b.vy)
        if (not b.air and not b.ramp and s < B.stop) or t - b.t0 >= B.max_t then ball_stops(b, t) else push_ball(t + dt, b) end
    end
    local function push_swing(t, s)
        seq = seq + 1
        heap_push(hp, { t = t, swing = s, seq = seq })
    end
    -- A hit on its latch lets the bob go: gravity does the rest.
    local function start_swing(p, t)
        done[p.id] = true
        if ext then ext.swing(p, t); return end
        local s = { id = p.id, p = p, th = -p.amp, w = 0, t0 = t, n = 0, pts = { t, -p.amp }, bumps = {}, period = 2 * pi * sqrt(p.L / B.g) }
        res.swings[#res.swings + 1] = s
        push_swing(t + S.dt, s)
    end
    -- One time step of a swing, in the same queue as everything else.
    local function step_swing(s, t)
        local p, L, dt, r = s.p, s.p.L, S.dt, S.r
        s.w = s.w + (-(B.g / L) * sin(s.th) - S.damp * s.w) * dt
        s.th = s.th + s.w * dt
        local x, y, cz = F.swing_bob(p, s.th)
        local dir = s.w >= 0 and 1 or -1
        local dx, dy = p.ax * dir, p.ay * dir
        local speed = abs(s.w) * L * cos(s.th)
        -- Furniture turns it back.
        for i = 1, #solids do
            local q = solids[i]
            if cz - r < q.z1 - 0.01 and cz + r > q.z0 then
                local cx, cy = max(q.x0, min(q.x1, x)), max(q.y0, min(q.y1, y))
                local ox, oy = cx - x, cy - y
                if ox * ox + oy * oy < r * r and ox * dx + oy * dy > 0 then
                    if q.switch and not done[q.switch.id] and speed >= S.min_hit then push(t, q.switch, dx, dy) end
                    s.w = -s.w * 0.5
                    if speed > 1 then s.bumps[#s.bumps + 1] = t end
                    dir, dx, dy = -dir, -dx, -dy
                    break
                end
            end
        end
        -- Standing dominoes: the heavy bob hardly notices them.
        board:near(x, y, r + W, function(q)
            if not done[q.id] and cz + r > q.z and cz - r < q.z + H and (q.x - x) * dx + (q.y - y) * dy > 0 then
                local rx, ry = x - q.x, y - q.y
                local u, v = rx * q.ax + ry * q.ay, ry * q.ax - rx * q.ay
                local du, dv = u - max(-T / 2, min(T / 2, u)), v - max(-W / 2, min(W / 2, v))
                local dh = cz - max(q.z, min(q.z + H, cz))
                if du * du + dv * dv + dh * dh < r * r then
                    if speed >= S.min_hit then
                        push(t, q, dx, dy)
                        s.bumps[#s.bumps + 1] = t
                    end
                    if speed >= S.min_hit and abs(dx * q.ax + dy * q.ay) >= 0.3 then
                        s.w = s.w * S.keep
                    else
                        s.w = -s.w * 0.5
                    end
                end
            end
        end)
        -- Balls at rest: a heavy thing hitting a light one sends it off at up to (1 + e) times its own speed.
        for i = 1, #ball_list do
            local q = ball_list[i]
            if not done[q.id] then
                local ox, oy, oz = q.x - x, q.y - y, q.z + B.r - cz
                if ox * ox + oy * oy + oz * oz < (r + B.r) ^ 2 and ox * dx + oy * dy > 0 and speed >= S.min_hit then
                    launch(q, t, dx, dy, speed * (1 + B.e))
                    s.w = s.w * S.keep
                    s.bumps[#s.bumps + 1] = t
                end
            end
        end
        s.n = s.n + 1
        if s.n % 2 == 0 then
            s.pts[#s.pts + 1], s.pts[#s.pts + 2] = t, s.th
        end
        -- A run waits for one swing out and back; after that the bob only sways.
        if t - s.t0 >= s.period * 1.25 then
            s.pts[#s.pts + 1], s.pts[#s.pts + 2] = t, s.th
            s.t_end = t
            if t > res.duration then res.duration = t end
        else
            push_swing(t + dt, s)
        end
    end
    local function advance(limit)
    while hp.n > 0 and hp[1].t <= limit do
        local job = heap_pop(hp)
        local p, t = job.p, job.t
        if job.ball then
            step_ball(job.ball, t)
        elseif job.swing then
            step_swing(job.swing, t)
        elseif p.kind == "switch" then
            if not done[p.id] then press_switch(p, t) end
        elseif p.kind == "swing" then
            if not done[p.id] then start_swing(p, t) end
        elseif p.kind == "ball" then
            if not done[p.id] then launch(p, t, job.dx, job.dy, job.speed or 0) end
        elseif not done[p.id] then
            local d = job.dx * p.ax + job.dy * p.ay
            if abs(d) < 0.3 then
                if not wobbled[p.id] then
                    wobbled[p.id] = true
                    res.events[#res.events + 1] = { t = t, kind = "wobble", id = p.id }
                end
            else
                local sgn = d > 0 and 1 or -1
                local fx, fy = p.ax * sgn, p.ay * sgn
                done[p.id] = true
                res.toppled = res.toppled + 1
                -- Dominoes ahead.
                local nh, best = 0, nil
                board:near(p.x, p.y, reach, function(q)
                    if q ~= p and not done[q.id] then
                        local rx, ry = q.x - p.x, q.y - p.y
                        local along = rx * fx + ry * fy
                        if along > 0.02 and along < reach then
                            local cq, sq = abs(q.ax * fx + q.ay * fy), abs(q.ax * fy - q.ay * fx)
                            local lat = abs(rx * fy - ry * fx)
                            if lat < W / 2 + sq * T / 2 + cq * W / 2 - 0.02 then
                                local c = along - T / 2 - (cq * T / 2 + sq * W / 2)
                                local dz = q.z - p.z
                                local th = F.contact_angle(c, dz, dz + H, H)
                                if th then
                                    nh = nh + 1
                                    hit_q[nh], hit_th[nh] = q, th
                                    if not best or th < best then best = th end
                                end
                            end
                        end
                    end
                end)
                -- Furniture and ledges.
                local wall, ledge
                local pvx, pvy = p.x + fx * T / 2, p.y + fy * T / 2
                for i = 1, #solids do
                    local s = solids[i]
                    if s.z1 > p.z + 0.01 and s.z0 < p.z + H then
                        local c = ray_box(pvx, pvy, fx, fy, W / 2 - 0.02, s, H)
                        if c then
                            local zt = s.z1 - p.z
                            local th = F.contact_angle(c, s.z0 - p.z, zt, H)
                            if th then
                                if zt <= F.LEDGE then
                                    if not ledge or th < ledge then ledge = th end
                                elseif not wall or th < wall then wall = th end
                            end
                        end
                    end
                end
                -- Balls and swings ahead: they fly off, so the domino carries on past them.
                local n_dom = nh
                for i = 1, #target_list do
                    local q = target_list[i]
                    local is_swing = q.kind == "swing"
                    if not done[q.id] then
                        local qr, lift = (is_swing or q.kind == "switch") and SW.r or B.r, 0
                        local rx, ry = (is_swing and q.lx or q.x) - p.x, (is_swing and q.ly or q.y) - p.y
                        local along = rx * fx + ry * fy
                        if along > 0.02 and along < H + qr and abs(rx * fy - ry * fx) < W / 2 + qr * 0.85 then
                            local dz = q.z + lift - p.z
                            local th = F.contact_angle(along - T / 2 - qr, dz, dz + 2 * qr, H)
                            if th then
                                nh = nh + 1
                                local cc, zt = max(0.02, along - T / 2 - qr), dz + 2 * qr
                                hit_q[nh], hit_th[nh], hit_kick[nh] = q, th, q.kind == "ball" and F.ball_kick(th, sqrt(cc * cc + zt * zt)) or nil
                            end
                        end
                    end
                end
                local fall = { id = p.id, t = t, yaw = atan2(fy, fx), flip = sgn < 0, dx = fx, dy = fy }
                local contact
                if best and (not wall or best <= wall) then
                    contact = best
                    fall.hits = 0
                    local tc = t + F.fall_time(contact)
                    for i = 1, n_dom do
                        if hit_th[i] <= best + rad(3) then
                            push(tc, hit_q[i], fx, fy)
                            fall.hits = fall.hits + 1
                        end
                    end
                    fall.final = min(rad(80), contact + rad(26))
                elseif wall then
                    contact, fall.blocked, fall.final = wall, true, wall
                else
                    contact = ledge or rad(F.REST)
                    fall.final = contact
                end
                for i = n_dom + 1, nh do
                    if hit_th[i] <= contact + rad(3) then
                        push(t + F.fall_time(hit_th[i]), hit_q[i], fx, fy, hit_kick[i])
                        fall.hits = (fall.hits or 0) + 1
                    end
                end
                for i = 1, nh do hit_q[i], hit_kick[i] = nil, nil end
                fall.contact = contact
                fall.tc = t + F.fall_time(contact)
                fall.t_end = fall.tc + 0.15
                res.falls[p.id] = fall
                res.order[#res.order + 1] = fall
                if fall.t_end > res.duration then res.duration = fall.t_end end
            end
        end
    end
    end
    -- Where a branch of the chain stopped short of dominoes still standing (a gap too wide, a bad turn): the view
    -- marks these after a run.
    local function finish()
    for _, f in ipairs(res.order) do
        if not f.hits then
            local p = board.pieces[f.id]
            local found
            board:near(p.x, p.y, 3.0, function(q)
                if not found and not done[q.id] then
                    local rx, ry = q.x - p.x, q.y - p.y
                    local along = rx * f.dx + ry * f.dy
                    if along > 0 and along < 3.0 and abs(rx * f.dy - ry * f.dx) < 0.7 and abs(q.z - p.z) < 1 then found = q end
                end
            end)
            if found then res.gaps[#res.gaps + 1] = { x = (p.x + found.x) / 2, y = (p.y + found.y) / 2, z = p.z, id = p.id } end
        end
    end
    res.done = done
    end
    -- A sphere moving from (x0, y0, c0) to (x1, y1, c1) (centres): start what it touches and report the normal of the
    -- first standing domino it struck, so the engine body can come off it. speed: its speed there.
    local function strike(r, x0, y0, c0, x1, y1, c1, vx, vy, vz, t, min_hit)
        local speed = sqrt(vx * vx + vy * vy + vz * vz)
        local hv = max(1e-6, sqrt(vx * vx + vy * vy))
        local dx, dy = vx / hv, vy / hv
        local len = sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2 + (c1 - c0) ^ 2)
        local n = min(40, max(1, floor(len / (r * 0.5)) + 1))
        local nrx, nry, struck
        for k = 1, n do
            local u = k / n
            local x, y, c = x0 + (x1 - x0) * u, y0 + (y1 - y0) * u, c0 + (c1 - c0) * u
            board:near(x, y, r + W, function(q)
                if not done[q.id] and c + r > q.z and c - r < q.z + H then
                    local rx, ry = x - q.x, y - q.y
                    local qu, qv = rx * q.ax + ry * q.ay, ry * q.ax - rx * q.ay
                    local du, dv = qu - max(-T / 2, min(T / 2, qu)), qv - max(-W / 2, min(W / 2, qv))
                    local dh = c - max(q.z, min(q.z + H, c))
                    if du * du + dv * dv + dh * dh < r * r then
                        if speed >= min_hit then push(t, q, dx, dy) end
                        if not struck then
                            struck = true
                            nrx, nry = du * q.ax - dv * q.ay, du * q.ay + dv * q.ax
                            local m = sqrt(nrx * nrx + nry * nry)
                            if m < 1e-6 then nrx, nry, m = -dx, -dy, 1 end
                            nrx, nry = nrx / m, nry / m
                        end
                    end
                end
            end)
            for i = 1, #solids do
                local s = solids[i]
                if s.switch and not done[s.switch.id] and c + r > s.z0 and c - r < s.z1 and speed >= min_hit then
                    local ox, oy = x - max(s.x0, min(s.x1, x)), y - max(s.y0, min(s.y1, y))
                    if ox * ox + oy * oy < (r + 0.04) ^ 2 then push(t, s.switch, dx, dy) end
                end
            end
        end
        return nrx, nry
    end
    return { res = res, advance = advance, finish = finish, pending = function() return hp.n > 0 end,
        strike_ball = function(...) return strike(B.r, ...) end, strike_bob = function(...) return strike(S.r, ...) end }
end

function F.simulate(board)
    local run = F.begin_run(board)
    run.advance(1e18)
    run.finish()
    return run.res
end

------------------------------------------------------------------ posing (for the world; pure maths)
-- A domino at (p.x, p.y, p.z) tipped theta radians along table yaw `yaw` (flip: it falls against its facing),
-- pivoting on its front edge: engine position and Euler degrees (x, y, z) for node:set_rotation, whose convention is
-- R = Rz * Ry * Rx. The domino mesh faces +X: R = Ry(yaw) * Rz(-theta) [* Ry(pi) when flipped].
function F.pose(p, yaw, flip, theta)
    local ca, sa = cos(yaw), sin(yaw)
    local ct, st = cos(theta), sin(theta)
    local e = T / 2
    local k = e * (1 - ct)
    local x, y, h = p.x + ca * k, p.y + sa * k, p.z + e * st
    local cb, sb = ct, -st
    local rx, ry, rz
    if not flip then
        ry = asin(max(-1, min(1, sa * cb))); rx = atan2(sa * sb, ca); rz = atan2(sb, ca * cb)
    else
        ry = asin(max(-1, min(1, -sa * cb))); rx = atan2(sa * sb, -ca); rz = atan2(-sb, -ca * cb)
    end
    return x, h, -y, deg(rx), deg(ry), deg(rz)
end

------------------------------------------------------------------ saving
function F.serialize(board)
    local list = {}
    for _, p in pairs(board.pieces) do list[#list + 1] = p end
    table.sort(list, function(a, b) return a.order < b.order end)
    local out = { "TOPPLE-FREE 1" }
    local s = board.start
    if s and board.pieces[s.id] then
        for i, p in ipairs(list) do if p.id == s.id then out[#out + 1] = string.format("start %d %d", i, s.dir) end end
    end
    local balls = {}
    for _, b in pairs(board.balls) do balls[#balls + 1] = b end
    table.sort(balls, function(a, b) return a.order < b.order end)
    for _, b in ipairs(balls) do out[#out + 1] = string.format("b %.3f %.3f %.3f", b.x, b.y, b.z) end
    local swings = {}
    for _, p in pairs(board.swings) do swings[#swings + 1] = p end
    table.sort(swings, function(a, b) return a.order < b.order end)
    for _, p in ipairs(swings) do out[#out + 1] = string.format("s %.3f %.3f %.3f %.4f %.3f %s", p.x, p.y, p.z, p.a, p.L, p.hang) end
    local ramps = {}
    for _, p in pairs(board.ramps) do ramps[#ramps + 1] = p end
    table.sort(ramps, function(a, b) return a.order < b.order end)
    for _, p in ipairs(ramps) do out[#out + 1] = string.format("r %.3f %.3f %.3f %.3f %.3f %.3f", p.x0, p.y0, p.z0, p.x1, p.y1, p.z1) end
    -- Switches name their domino by its place in the list below (ids are not saved).
    local index = {}
    for i, p in ipairs(list) do index[p.id] = i end
    local switches = {}
    for _, p in pairs(board.switches) do switches[#switches + 1] = p end
    table.sort(switches, function(a, b) return a.order < b.order end)
    for _, p in ipairs(switches) do
        out[#out + 1] = string.format("w %.3f %.3f %.3f %d %d %d", p.x, p.y, p.z, p.dir, p.lamp and 1 or 0, p.target and index[p.target] or 0)
    end
    for _, p in ipairs(list) do
        out[#out + 1] = string.format("d %.3f %.3f %.3f %.4f %s", p.x, p.y, p.z, p.a, p.paint or "cream")
    end
    return table.concat(out, "\n") .. "\n"
end

function F.deserialize(text)
    local b = F.new_board()
    if not text or not text:match("^TOPPLE%-FREE 1") then return b, false end
    local start_i, start_dir
    local i = 0
    local dom_ids, wait_target = {}, {}
    -- A damaged line loses only its own piece: a field that is not a finite number stops that line, not the load.
    local function tonumber(s)
        local v = _G.tonumber(s)
        if not v or v - v ~= 0 then error("bad number in a saved build") end
        return v
    end
    local function parse_line(line)
        local si, sd = line:match("^start (%d+) (%-?%d+)")
        if si then start_i, start_dir = tonumber(si), tonumber(sd) end
        local rx0, ry0, rz0, rx1, ry1, rz1 = line:match("^r (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)")
        if rx0 then
            b.next_id = b.next_id + 1
            b.order = b.order + 1
            b:_insert({ kind = "ramp", id = b.next_id, x0 = tonumber(rx0), y0 = tonumber(ry0), z0 = tonumber(rz0), x1 = tonumber(rx1), y1 = tonumber(ry1), z1 = tonumber(rz1), order = b.order })
        end
        local wx, wy, wz, wd, wl, wt = line:match("^w (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)")
        if wx then
            b.next_id = b.next_id + 1
            b.order = b.order + 1
            local w = { kind = "switch", id = b.next_id, x = tonumber(wx), y = tonumber(wy), z = tonumber(wz), dir = tonumber(wd), lamp = wl == "1", order = b.order }
            b:_insert(w)
            if tonumber(wt) > 0 then wait_target[w] = tonumber(wt) end
        end
        local sx, sy, sz, sa, sl, hang = line:match("^s (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)")
        if sx then
            b.next_id = b.next_id + 1
            b.order = b.order + 1
            b:_insert({ kind = "swing", id = b.next_id, x = tonumber(sx), y = tonumber(sy), z = tonumber(sz), a = tonumber(sa), L = tonumber(sl), hang = hang, order = b.order })
        end
        local bx, by, bz = line:match("^b (%S+) (%S+) (%S+)")
        if bx then
            b.next_id = b.next_id + 1
            b.order = b.order + 1
            b:_insert({ kind = "ball", id = b.next_id, x = tonumber(bx), y = tonumber(by), z = tonumber(bz), order = b.order })
        end
        local x, y, z, a, paint = line:match("^d (%S+) (%S+) (%S+) (%S+) (%S+)")
        if x then
            i = i + 1
            b.next_id = b.next_id + 1
            b.order = b.order + 1
            local p = { id = b.next_id, x = tonumber(x), y = tonumber(y), z = tonumber(z), a = tonumber(a), paint = paint, order = b.order }
            if i == start_i then b.start = { id = p.id, dir = start_dir >= 0 and 1 or -1 } end
            b:_insert(p)
            dom_ids[i] = p.id
        end
    end
    for line in text:gmatch("[^\n]+") do pcall(parse_line, line) end
    for w, n in pairs(wait_target) do w.target = dom_ids[n] end
    return b, true
end

return F
