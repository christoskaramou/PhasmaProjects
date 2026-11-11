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
local asin, acos, pi, rad, deg = math.asin, math.acos, math.pi, math.rad, math.deg
local atan2 = math.atan2 or math.atan

F.DOM = { w = 0.5, t = 0.15, h = 1.0 }
local W, T, H = F.DOM.w, F.DOM.t, F.DOM.h
F.SPACING = 0.62           -- along a drawn line
F.MIN_GAP = 0.45           -- closest two dominoes may stand (centre to centre, same level)
F.CLIMB = 0.6              -- a line steps up or down onto a surface at most this much higher or lower
F.CAP = 6000               -- dominoes in the box (60 FPS measured at 6,389 falling across the floor)
F.FIELD_LAT = 0.6          -- side by side in a field row (staggered rows: each one strikes two ahead)
F.SPIRAL_GAP = 0.95        -- between the turns of a spiral
F.SPIRAL_MIN = 1.6         -- the spiral's innermost radius
F.TIME_K = 0.5             -- Free Build's chains run at about twice Table Run's pace
F.REST = 89.3              -- a domino with nothing in reach lies flat
F.LEDGE = 0.6              -- solids no taller than this above a faller's base are ledges it slides over
F.PAINTS = { "brick", "mustard", "sage", "navy", "cream" }
F.FIELD_WIDTH = { min = 1.2, max = 24, default = 6 }
-- Sizes: every measure of a domino times s. A falling domino tips one up to KNOCK times its own size; against anything
-- bigger it only comes to lean. So a chain steps up a size at a time, and a big one coming down flattens the small ones
-- under it. A stroke that grows makes each domino GROW times the one before.
F.SIZES = { 2 / 3, 1, 1.5, 2.25, 3.375 }
F.SIZE_NAMES = { "Mini", "Standard", "Large", "Giant", "Titan" }
F.KNOCK = 1.5
F.GROW = 1.25
-- Off an edge: a domino that lies down with its middle past the edge of what it stands on tips off and tumbles to
-- whatever is below, at least min_drop lower, and knocks over what it lands on. speed: how fast it leaves, per sqrt(size).
F.DIVE = { min_drop = 0.8, speed = 3.2, margin = 0.12 }
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
local function extents(a, k)
    k = k or 1
    if not a then return k * W / 2 + 0.02, k * W / 2 + 0.02 end
    local c, s = abs(cos(a)), abs(sin(a))
    return k * (c * T / 2 + s * W / 2) + 0.02, k * (s * T / 2 + c * W / 2) + 0.02
end
F.extents = extents

local function in_rect(x, y, r, ex, ey)
    ex, ey = ex or 0, ey or ex or 0
    return x >= r.x0 + ex and x <= r.x1 - ex and y >= r.y0 + ey and y <= r.y1 - ey
end

-- Surfaces under (x, y) that a domino facing a could stand on (whole footprint inside a raised one), highest first.
function F.surfaces_at(x, y, a, list, k)
    local ex, ey = extents(a, k)
    local out = {}
    for _, s in ipairs(list or ROOM.surfaces) do
        if (s.edge and in_rect(x, y, s, ex, ey)) or (not s.edge and in_rect(x, y, s)) then out[#out + 1] = s end
    end
    return out
end

-- The solid (furniture, walls) a domino facing a, standing at (x, y) on height h, would intersect, if any.
local function solid_at(x, y, h, a, list, k)
    local ex, ey = extents(a, k)
    local H = H * (k or 1)
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
        undo_stack = {}, redo_stack = {}, act = nil, rev = 0, traps = {}, trap_order = {}, preset_count = 0 }, Board)
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
    if self.ramp_count == 0 and not self.support_count then return ROOM.surfaces end
    if not self._surf then
        local list = {}
        for _, s in ipairs(ROOM.surfaces) do list[#list + 1] = s end
        for _, r in pairs(self.ramps) do
            for _, s in ipairs(r.steps) do list[#list + 1] = s end
        end
        -- (a support's top: only presets stand on it)
        for _, tr in ipairs(self.trap_order) do
            if tr.kind == "support" then list[#list + 1] = { name = "support", x0 = tr.x0, x1 = tr.x1, y0 = tr.y0, y1 = tr.y1, h = tr.z1, edge = true, trap = tr } end
        end
        table.sort(list, function(a, b) return a.h > b.h end)
        self._surf = list
    end
    return self._surf
end

-- How many of a kind the box holds: a challenge's budget where it has one, else the default.
function Board:limit(kind, default)
    if self.limits then return self.limits[kind] or 0 end
    return default
end

function Board:all_solids()
    if self.ramp_count == 0 and not self.props and #self.trap_order == 0 then return ROOM.solids end
    if not self._sol then
        local list = {}
        for _, s in ipairs(ROOM.solids) do list[#list + 1] = s end
        for _, s in ipairs(self.props or {}) do list[#list + 1] = s end
        -- (a trap's body is solid while it is in place: the run skips it once it is gone)
        for _, tr in ipairs(self.trap_order) do
            for _, b in ipairs(tr.boxes) do
                list[#list + 1] = { name = tr.kind, x0 = b.x0, x1 = b.x1, y0 = b.y0, y1 = b.y1, z0 = b.z0, z1 = b.z1, trap = tr }
            end
        end
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
    p.s = p.s or 1
    if p.s > (self.smax or 1) then self.smax = p.s end
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
-- True if two dominoes' footprints (centre, facing, size) come within a hair of each other.
local function feet_touch(x1, y1, a1, k1, x2, y2, a2, k2)
    local c1, s1, c2, s2 = cos(a1), sin(a1), cos(a2), sin(a2)
    local t1, w1, t2, w2 = k1 * T / 2 + 0.03, k1 * W / 2 + 0.03, k2 * T / 2, k2 * W / 2
    local dx, dy = x2 - x1, y2 - y1
    local cc, ss = abs(c1 * c2 + s1 * s2), abs(c1 * s2 - s1 * c2)
    if abs(dx * c1 + dy * s1) > t1 + cc * t2 + ss * w2 then return false end
    if abs(-dx * s1 + dy * c1) > w1 + ss * t2 + cc * w2 then return false end
    if abs(dx * c2 + dy * s2) > t2 + cc * t1 + ss * w1 then return false end
    if abs(-dx * s2 + dy * c2) > w2 + ss * t1 + cc * w1 then return false end
    return true
end

-- The height a piece set down at h on (x, y) really stands at: a thin surface lying over that spot (a rug, a play
-- mat: its top less than clear above h and nothing solid under it) is stood on, not under. Tables, bridges, ramps
-- and gaps under furniture have a solid top or room enough, so they are left as they are.
function Board:rest(x, y, h, clear)
    for _ = 1, 4 do
        local up
        for _, s in ipairs(self:all_surfaces()) do
            if s.h > h + 1e-4 and s.h - h < clear and not s.trap and in_rect(x, y, s) and (not up or s.h > up.h) then up = s end
        end
        if not up then return h end
        for _, q in ipairs(self:all_solids()) do
            if q.z1 > h + 0.01 and q.z0 < up.h - 0.01 and in_rect(x, y, q) then return h end
        end
        h = up.h
    end
    return h
end

function Board:blocked(x, y, h, a, k)
    k = k or 1
    h = self:rest(x, y, h, H * k)
    if self.count - self.preset_count >= self:limit("domino", F.CAP) then return "full" end
    local ok = false
    local ex, ey = extents(a, k)
    if #self.trap_order > 0 then
        local why = self:trap_block(x - ex, x + ex, y - ey, y + ey, h, h + H * k)
        if why then return why end
    end
    for _, s in ipairs(self:all_surfaces()) do
        if abs(s.h - h) < 1e-4 and ((s.edge and in_rect(x, y, s, ex, ey)) or (not s.edge and in_rect(x, y, s))) then
            -- (only a challenge's own pieces stand on a fragile support)
            if s.trap and not self._installing then return "support" end
            ok = true; break
        end
    end
    if not ok then return "air" end
    if solid_at(x, y, h, a, self:all_solids(), k) then return "furniture" end
    local crowded = false
    local smax = self.smax or 1
    self:near(x, y, max(F.MIN_GAP * k, (k + smax) * W / 2 + 0.1), function(q)
        if crowded then return end
        local d2 = (q.x - x) ^ 2 + (q.y - y) ^ 2
        -- (same size: the old rule, which lets a field stand shoulder to shoulder; mixed sizes: their footprints)
        if q.s == k then
            if abs(q.z - h) < 0.9 * k and d2 < (F.MIN_GAP * k) ^ 2 then crowded = true end
        elseif q.z < h + k * H and q.z + q.s * H > h and (d2 < (F.MIN_GAP * min(k, q.s)) ^ 2 or feet_touch(x, y, a or 0, k, q.x, q.y, q.a, q.s)) then
            crowded = true
        end
    end)
    if crowded then return "crowded" end
    local gap = F.BALL.r + F.BALL.clear + (k - 1) * W / 2
    for _, b in pairs(self.balls) do
        if abs(b.z - h) < 0.9 and (b.x - x) ^ 2 + (b.y - y) ^ 2 < gap * gap then return "crowded" end
    end
    if self:near_swing(x, y, h, F.SWING.clear) or self:near_switch(x, y, h, F.SWITCH.clear) then return "crowded" end
    return nil
end

function Board:can_place(x, y, h, a, k) return self:blocked(x, y, h, a, k) == nil end

function Board:_record(kind, p)
    local a = self.act
    if a then a[kind][#a[kind] + 1] = p end
end

function Board:place(x, y, a, h, paint, k)
    h = self:rest(x, y, h, H * (k or 1))
    local why = self:blocked(x, y, h, a, k)
    if why then return nil, why end
    self.next_id = self.next_id + 1
    self.order = self.order + 1
    local p = { id = self.next_id, x = x, y = y, z = h, a = a or 0, paint = paint or "cream", order = self.order, s = k or 1 }
    self:_insert(p)
    self:_record("added", p)
    return p
end

-- Place on whichever surface under (x, y) suits: the one nearest near_h within a climb (a line stepping onto the
-- rug or up a book), or the highest when near_h is nil.
function Board:place_auto(x, y, a, paint, near_h, k)
    local cands = F.surfaces_at(x, y, a, self:all_surfaces(), k)
    if near_h then
        table.sort(cands, function(p, q) return abs(p.h - near_h) < abs(q.h - near_h) end)
    end
    local why = "air"
    for _, s in ipairs(cands) do
        if near_h and abs(s.h - near_h) > F.CLIMB then break end
        local p, w = self:place(x, y, a, s.h, paint, k)
        if p then return p end
        if why == "air" or w == "full" then why = w end
    end
    return nil, why
end

-- Why a ball cannot rest at (x, y) on a surface of height h (nil if it can).
function Board:ball_blocked(x, y, h)
    local B = F.BALL
    h = self:rest(x, y, h, 2 * B.r)
    if self.ball_count >= self:limit("ball", B.cap) then return "full" end
    local tw = self:trap_block(x - B.r, x + B.r, y - B.r, y + B.r, h, h + 2 * B.r)
    if tw then return tw end
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
    h = self:rest(x, y, h, 2 * F.BALL.r)
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
    h = self:rest(x, y, h, S.post)
    if self.swing_count >= self:limit("swing", S.cap) then return "full" end
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
    local tw = self:trap_block(x - S.r, x + S.r, y - S.r, y + S.r, z0, z1)
    if tw then return tw end
    for _, c in ipairs(posts) do
        tw = self:trap_block(c[1] - S.post_r, c[1] + S.post_r, c[2] - S.post_r, c[2] + S.post_r, h, h + L + S.lift + S.r)
        if tw then return tw end
    end
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
    tw = self:trap_block(lx - SW.r, lx + SW.r, ly - SW.r, ly + SW.r, h, h + 2 * SW.r)
    if tw then return tw end
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
    h = self:rest(x, y, h, F.SWING.post)
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
    h = self:rest(x, y, h, 2 * W_.r)
    if self.switch_count >= self:limit("switch", W_.cap) then return "full" end
    local tw = self:trap_block(x - W_.r, x + W_.r, y - W_.r, y + W_.r, h, h + 2 * W_.r)
    if tw then return tw end
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
    h = self:rest(x, y, h, 2 * F.SWITCH.r)
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
        if not s.fixed and (not h or abs(s.z - h) < 0.8) and d <= reach * reach and (not bd or d < bd or (d == bd and s.id < best.id)) then best, bd = s, d end
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
    h0 = self:rest(x0, y0, h0, H)                -- (the foot)
    if h1 - h0 < 0.01 then return nil, "flat" end
    if self.ramp_count >= self:limit("ramp", R.cap) then return nil, "full" end
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
    -- Clear of traps, furniture, other ramps and everything standing there.
    local e = 1e-3
    for _, st in ipairs(fit.solids) do
        local tw = self:trap_block(st.x0, st.x1, st.y0, st.y1, st.z0, st.z1 + 0.01)
        if tw then return nil, tw end
    end
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
    if not p or p.fixed then return nil end     -- a challenge's first domino and goal stay put
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
    self:near(x, y, reach * (self.smax or 1), function(q)
        if not h or abs(q.z - h) < 0.8 then
            local d = ((q.x - x) ^ 2 + (q.y - y) ^ 2) / (q.s * q.s)       -- (a big one is as easy to point at)
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
-- size: the new domino's; from: the size of the one before it (they stand half of each one's spacing apart).
function Board:stroke_step(lx, ly, lz, cx, cy, paint, size, from)
    size = size or 1
    local sp = F.SPACING * (size + (from or size)) / 2
    local dx, dy = cx - lx, cy - ly
    local d = sqrt(dx * dx + dy * dy)
    if d < sp then return nil, "wait" end
    dx, dy = dx / d, dy / d
    local a = atan2(dy, dx)
    local why
    for k = 0, 3 do
        local s = sp + 0.1 * k * size
        if s > d then return nil, "wait" end
        local p, w = self:place_auto(lx + dx * s, ly + dy * s, a, paint, lz, size)
        if p then return p end
        why = w
    end
    return nil, why, lx + dx * sp, ly + dy * sp
end

-- The size of the next domino in a stroke that grows from one of size `from` toward `to` (GROW at a time).
function F.grow_size(from, to)
    if to >= from then return min(to, from * F.GROW) end
    return max(to, from / F.GROW)
end

-- (the shapes take a size k: the same shape, every measure times k)
function F.line_spots(x0, y0, x1, y1, k)
    k = k or 1
    local dx, dy = x1 - x0, y1 - y0
    local L = sqrt(dx * dx + dy * dy)
    local a = L > 1e-6 and atan2(dy, dx) or 0
    local out = {}
    local n = floor(L / (F.SPACING * k) + 1e-6)
    for i = 0, n do
        local s = i * F.SPACING * k
        out[#out + 1] = { x = x0 + cos(a) * s, y = y0 + sin(a) * s, a = a, s = k }
    end
    return out
end

-- An Archimedean spiral from radius R (starting on the side of (sx, sy)) winding in to SPIRAL_MIN, outer end
-- first, each domino facing along the way the chain runs. cw winds clockwise.
function F.spiral_spots(cx, cy, sx, sy, cw, k)
    k = k or 1
    local R = sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2)
    local out = {}
    if R < (F.SPIRAL_MIN + 0.5) * k then return out end
    local b = F.SPIRAL_GAP * k / (2 * pi)
    local ang = atan2(sy - cy, sx - cx)
    local sgn = cw and -1 or 1
    local r = R
    while r > F.SPIRAL_MIN * k and #out < 4000 do
        local ca, sa = cos(ang), sin(ang)
        local tx, ty = -b * ca - r * sa * sgn, -b * sa + r * ca * sgn
        out[#out + 1] = { x = cx + r * ca, y = cy + r * sa, a = atan2(ty, tx), s = k }
        local dphi = F.SPACING * k / sqrt(r * r + b * b)
        ang = ang + dphi * sgn
        r = r - b * dphi
    end
    return out
end

-- A field: from its point at (ax, ay) it fans out row by row toward (bx, by) until it is `width` wide, then runs
-- on at that width. Rows are staggered, so each domino strikes the two in the row ahead and the wave fills it all.
function F.field_spots(ax, ay, bx, by, width, k)
    k = k or 1
    local dx, dy = bx - ax, by - ay
    local L = sqrt(dx * dx + dy * dy)
    local out = {}
    if L < 1e-6 then return { { x = ax, y = ay, a = 0, row = 0, s = k } } end
    local ux, uy = dx / L, dy / L
    local px, py = -uy, ux
    local a = atan2(uy, ux)
    local nmax = max(1, floor(width / (F.FIELD_LAT * k) + 1e-6) + 1)
    local rows = floor(L / (F.SPACING * k) + 1e-6) + 1
    for row = 0, rows - 1 do
        local n
        if row + 1 <= nmax then n = row + 1 else n = ((row - nmax) % 2 == 0) and (nmax - 1) or nmax end
        if n < 1 then n = 1 end
        for i = 0, n - 1 do
            local l = (-(n - 1) / 2 + i) * F.FIELD_LAT * k
            local s = row * F.SPACING * k
            out[#out + 1] = { x = ax + ux * s + px * l, y = ay + uy * s + py * l, a = a, row = row, col = i, s = k }
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
        local p = self:place_auto(s.x, s.y, s.a, paint and paint(i, s) or "cream", s.row and h0 or last, s.s)
        if p then n = n + 1; last = p.z end
    end
    return n
end

-- A straight line from (x0, y0) to (x1, y1), walked like a stroke: each domino a spacing on from the last, nudged
-- forward when its spot is taken (so it finds its footing on a book's step), skipping past anything solid.
-- size: every domino's; grow: the size the line grows (or shrinks) to from there, a step at a time.
function Board:place_line(x0, y0, x1, y1, paint, h0, size, grow)
    local n = 0
    size = size or 1
    local first, why = self:place_auto(x0, y0, atan2(y1 - y0, x1 - x0), paint and paint(1) or "cream", h0, size)
    local lx, ly, lz = x0, y0, h0
    if first then n, lz = 1, first.z end
    for _ = 1, 10000 do
        local nxt = grow and F.grow_size(size, grow) or size
        local p, w, gx, gy = self:stroke_step(lx, ly, lz, x1, y1, paint and paint(n + 1) or "cream", nxt, size)
        if p then
            n = n + 1
            size = nxt
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
function Board:place_path(pts, paint, h0, size, grow)
    size = size or 1
    local first = self:place_auto(pts[1][1], pts[1][2], atan2(pts[2][2] - pts[1][2], pts[2][1] - pts[1][1]), paint and paint(1) or "cream", h0, size)
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
                local nxt = grow and F.grow_size(size, grow) or size
                local p, _, gx, gy = self:stroke_step(lx, ly, lz, cx, cy, paint and paint(n + 1) or "cream", nxt, size)
                if p then lx, ly, lz, last, n, size = p.x, p.y, p.z, p, n + 1, nxt
                elseif gx then lx, ly = gx, gy
                else break end
            end
        end
    end
    return last, n
end

-- How far ahead of where it stood a domino of size k comes down after tipping off an edge `drop` high, and how long
-- it is in the air.
function F.dive_throw(drop, k)
    k = k or 1
    local td = sqrt(2 * drop / F.BALL.g) * 1.15
    return (T + H) * k / 2 + F.DIVE.speed * sqrt(k) * td, td
end

-- The build a first visit opens on, a tour of the ways dominoes fall: a line from the front of the room winds across
-- the floor, climbs the staircase of books and a ramp onto the coffee table, fans out across the table and pours off
-- its front edge; one of the fallers starts a line that grows a size at a time into Titans, and the last Titan comes
-- down on a fan of Minis.
function F.demo(board)
    board:begin_action()
    local k = 0
    local function rainbow() k = k + 1; return F.PAINTS[floor((k - 1) / 6) % 5 + 1] end
    local tbl
    for _, s in ipairs(ROOM.surfaces) do if s.name == "coffee table" then tbl = s end end
    local ym = (tbl.y0 + tbl.y1) / 2
    board:place_ramp(25, ym, 0, tbl.x1, ym, tbl.h)
    -- Along the front, over the books, up the right side, up the ramp and round the back of the table.
    local last = board:place_path({ { -26, -29 }, { -14, -29.5 }, { -2, -28.5 }, { 5, -25 }, { 8.5, -19.5 }, { 12, -19 },
        { 24, -19 }, { 36.5, -19 }, { 37.6, -15 }, { 36, -10 }, { 32.5, -5 }, { 29.6, -0.6 }, { 27.6, ym - 0.1 }, { 26.4, ym },
        { 20, ym }, { 10, ym }, { 2, ym }, { tbl.x1 - 1.2, ym }, { tbl.x1 - 3.6, ym + 0.6 }, { tbl.x1 - 6, ym + 2.8 }, { tbl.x1 - 8.6, ym + 4.5 },
        { tbl.x1 - 11.2, ym + 4.7 }, { tbl.x1 - 12.9, ym + 4.1 }, { tbl.x1 - 13.5, ym + 3 } }, rainbow, 0)
    if not last or last.z < tbl.h - 0.01 then last = { x = tbl.x1 - 13.5, y = ym + 3, z = tbl.h } end
    -- A fan across the table to its front edge: the last row has nothing ahead of it but the drop.
    local fx = last.x
    local edge = tbl.y0 + 0.15
    local rows = floor((last.y - edge - 0.47) / F.SPACING)
    board:place_spots(F.field_spots(fx, edge + rows * F.SPACING, fx, edge, 9), F.field_paint, tbl.h)
    -- Where the middle of that row lands a short row stands waiting, and behind it the line that grows...
    local rug = 0
    for _, s in ipairs(ROOM.surfaces) do if s.name == "rug" then rug = s.h end end
    local ly = edge - F.dive_throw(tbl.h - rug) - 0.6      -- (just past where a faller's far end comes down, so it lands behind them)
    for i = -2, 2 do board:place(fx + i * 0.62, ly, -pi / 2, rug, "cream") end
    local turn = board:place_path({ { fx, ly - F.SPACING }, { fx, ly - 2.4 }, { fx + 0.9, ly - 4.2 }, { fx + 3, ly - 5 } }, rainbow, rug)
    local ay = turn and turn.y or ly - 5
    local ax = (turn and turn.x or fx + 3) + F.SPACING * (1 + F.GROW) / 2
    board:place_line(ax, ay, ax + 16.2, ay, function() return "brick" end, rug, F.GROW, F.SIZES[5])
    -- ...and the last Titan has a fan of Minis under it.
    local titan
    for _, p in pairs(board.pieces) do
        if p.s > 3 and (not titan or p.x > titan.x) then titan = p end
    end
    if titan then
        local sx = titan.x + T * titan.s / 2 + 0.55
        board:place_spots(F.field_spots(sx, ay, sx + 7.6, ay, 8.2, F.SIZES[1]), F.field_paint, rug)
    end
    board.start = nil
    board:end_action()
    board.undo_stack, board.redo_stack = {}, {}
    board.sample_rev = board.rev      -- tipped untouched, it is not your own build
    return board
end

------------------------------------------------------------------ traps
-- TRAP API (for the world, the view and challenge authors). Units are table units (x, y, h up); angles in radians.
--
-- Installing (a challenge does this through C.new_board(def), from def.traps):
--   board:add_trap(spec) -> trap      Copies spec; asserts on a bad one. Never recorded for undo, never saved, cannot be
--                                     removed, erased or cleared. Install traps before presets and the player's pieces.
--   board:check_traps()               Asserts that every string's holds names an installed weight, plank, gate or support.
--   board:place_preset(x, y, a, h, paint, size) -> p | nil, why
--                                     A challenge's fixed domino (size: a scale, default 1): p.fixed = p.preset = true,
--                                     may stand on a support, not in the budget (board.preset_count), not saved.
--   board.traps[id] -> trap           board.trap_order: every trap in install order (iterate this, it is deterministic).
--   board:trap_block(x0, x1, y0, y1, z0, z1) -> "zone" | "trap" | nil   What refuses a box there.
-- Specs (every trap but a zone needs a unique string id; a zone's defaults to "zone <n>"):
--   { kind = "zone", x0, x1, y0, y1 [, z0, z1] }  Nothing may be placed overlapping it (at any height, or only within
--       z0..z1 if given). It has no body and no events.
--   { kind = "string", id, a = { x, y, h }, b = { x, y, h } [, holds = "<trap id>"] }  A taut string between a and b
--       (points as { x, y, h } or { x = , y = , h = }). Cut once, by: a falling domino whose body sweeps through it, a
--       domino diving off an edge through it, a ball or swing bob (preview or engine) crossing it, a dropped weight or
--       a falling plank passing through it. Cutting it releases what it holds.
--   { kind = "weight", id, x, y, h, r }  Hangs with its base at h; its body is the box x +- r, y +- r, h .. h + 2r.
--       Released, it falls freely (F.BALL.g) to the highest surface or solid top under (x, y) and, as it lands, within r
--       of (x, y) at that height: knocks over standing dominoes of any size (away from its middle, along their facing),
--       presses switches, launches balls (F.TRAP.weight_kick, away from its middle) and collapses a support it lands on.
--   { kind = "plank", id, x, y, h, a, len [, width = F.TRAP.plank_w] }  Stands upright, hinged on the line through
--       (x, y, h) across a; its body is F.TRAP.plank_t thick behind that line, width wide, len tall. Released, it tips
--       along a about the hinge like one tall domino (it may go past flat, down an edge) until its far end comes down
--       on a surface or solid top, or meets furniture or a closed gate from the side (it stops there; a support it meets
--       collapses). Standing dominoes its body reaches on the way go over as it reaches them; where its far end comes
--       down (within max(F.TRAP.knock, width / 2)) it knocks over dominoes along a, presses switches, launches balls and
--       collapses a support. It does not become a surface: it carries a chain across a gap by striking.
--   { kind = "gate", id, x0, x1, y0, y1, z0, z1 }  Solid (to dominoes, balls, bobs, planks) until released, then gone.
--       A domino that starts to fall while it is closed and meets it is blocked there for good, even if it opens later.
--   { kind = "support", id, x0, x1, y0, y1, z0, z1 }  A fragile stack: solid, and its top (h = z1) is a surface only
--       presets (and a challenge's locked pieces) may stand on. It collapses when a falling domino comes to rest against
--       it (or slides over it as a ledge), a domino dives onto its top, a ball (>= F.TRAP.support_hit) or a bob
--       (>= F.SWING.min_hit) strikes it, a weight or plank comes down on it, or a string holding it is cut. Then its body
--       and top are gone, and every domino, ball and switch still standing on its top is lost: it never falls or acts.
-- Placing (dominoes, balls, switches, swings, ramps) is refused with:
--   "zone"     overlapping a zone;    "trap"  inside a trap's body or through a string;
--   "support"  a domino on a support's top (place_preset and C.new_board's locked pieces are allowed).
-- A run (F.simulate / F.begin_run, preview and live alike) steps the traps in its own event queue, never as engine bodies:
--   res.traps  time-ordered events; every one has { t, id, kind, event }, and per event:
--     string  "cut"       by = "domino" | "dive" | "ball" | "swing" | "weight" | "plank";  x, y, h: where it was cut;
--                         holds: the id it held (released at the same t, its event follows)
--     weight  "drop"      x, y; h: its base before, z: its base at rest; t1: when it lands. F.weight_height(e, t)
--             "land"      x, y; h: its base at rest (= drop's z)
--     plank   "fall"      angle: its final tilt from upright about the hinge, toward a (pi / 2 = flat; more = down an
--                         edge); t1: when it gets there; x, y, h: its far end then. F.plank_angle(e, t)
--             "land"      x, y, h: where its far end came down (only when it came down on something; not when it
--                         stopped against furniture or a gate)
--     gate    "open"      (nothing more: it is gone from t)
--     support "collapse"  by = "domino" | "dive" | "ball" | "swing" | "weight" | "plank" | "string";
--                         lost = { piece ids } (the same as res.lost entries at this t)
--   res.lost   { { id, t }, ... } in time order: pieces lost with a support (dominoes, balls, switches).
--   res.duration covers the trap events. In a live run (begin_run with ext) events arrive as advance() reaches them, and
--   run.strike_ball / run.strike_bob also cut strings and collapse supports; the engine bodies themselves are the world's
--   (a gate, plank, weight or support that should stop an engine ball needs a body the world removes on its event).
F.TRAP = { string_r = 0.04, plank_t = 0.3, plank_w = 1.5, knock = 0.6, support_hit = 3.9, weight_kick = 10 }
local TRAP_KINDS = { zone = true, string = true, weight = true, plank = true, gate = true, support = true }

local function num(v, what)
    assert(type(v) == "number" and v - v == 0, what .. " must be a finite number")
    return v
end

-- A string's end: { x, y, h } or { x = , y = , h = }.
local function trap_point(t, what)
    assert(type(t) == "table", what .. " must be a point { x, y, h }")
    return num(t.x or t[1], what .. ".x"), num(t.y or t[2], what .. ".y"), num(t.h or t[3], what .. ".h")
end

-- The boxes a trap fills while it is in place (what blocks placing and what a faller, a ball or a bob meets).
local function trap_boxes(tr)
    local k = tr.kind
    if k == "gate" or k == "support" then
        return { { x0 = tr.x0, x1 = tr.x1, y0 = tr.y0, y1 = tr.y1, z0 = tr.z0, z1 = tr.z1 } }
    elseif k == "weight" then
        return { { x0 = tr.x - tr.r, x1 = tr.x + tr.r, y0 = tr.y - tr.r, y1 = tr.y + tr.r, z0 = tr.h, z1 = tr.h + 2 * tr.r } }
    elseif k == "plank" then
        -- Upright on its hinge, its thickness behind the hinge line (like a domino on its front edge). (Its bounding box.)
        local c, s, t, hw = cos(tr.a), sin(tr.a), F.TRAP.plank_t, tr.width / 2
        local x0, x1, y0, y1 = 1e9, -1e9, 1e9, -1e9
        for _, u in ipairs({ -t, 0 }) do
            for _, v in ipairs({ -hw, hw }) do
                local x, y = tr.x + c * u - s * v, tr.y + s * u + c * v
                x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
            end
        end
        return { { x0 = x0, x1 = x1, y0 = y0, y1 = y1, z0 = tr.h, z1 = tr.h + tr.len } }
    end
    return {}
end

-- Install a trap from its spec (copied; the spec is not changed). Returns the trap. Traps sit outside the pieces, the
-- undo history and the save: nothing the player does removes them.
function Board:add_trap(spec)
    local k = spec.kind
    assert(TRAP_KINDS[k], "unknown trap kind " .. tostring(k))
    local tr = {}
    for key, v in pairs(spec) do tr[key] = v end
    if k == "zone" then
        tr.id = tr.id or ("zone " .. (#self.trap_order + 1))
    else
        assert(type(tr.id) == "string" and tr.id ~= "", k .. ": a trap needs a string id")
    end
    assert(not self.traps[tr.id], "two traps are called " .. tr.id)
    if k == "zone" or k == "gate" or k == "support" then
        for _, f in ipairs({ "x0", "x1", "y0", "y1" }) do num(tr[f], tr.id .. "." .. f) end
        assert(tr.x0 < tr.x1 and tr.y0 < tr.y1, tr.id .. ": x0 < x1 and y0 < y1")
        if k ~= "zone" or tr.z0 or tr.z1 then
            num(tr.z0, tr.id .. ".z0"); num(tr.z1, tr.id .. ".z1")
            assert(tr.z0 < tr.z1, tr.id .. ": z0 < z1")
        end
    elseif k == "string" then
        tr.sx0, tr.sy0, tr.sz0 = trap_point(tr.a, tr.id .. ".a")
        tr.sx1, tr.sy1, tr.sz1 = trap_point(tr.b, tr.id .. ".b")
        local R = F.TRAP.string_r
        tr.bx0, tr.bx1 = min(tr.sx0, tr.sx1) - R, max(tr.sx0, tr.sx1) + R
        tr.by0, tr.by1 = min(tr.sy0, tr.sy1) - R, max(tr.sy0, tr.sy1) + R
        tr.bz0, tr.bz1 = min(tr.sz0, tr.sz1) - R, max(tr.sz0, tr.sz1) + R
        tr.len = sqrt((tr.sx1 - tr.sx0) ^ 2 + (tr.sy1 - tr.sy0) ^ 2 + (tr.sz1 - tr.sz0) ^ 2)
        assert(tr.len > 0.05, tr.id .. ": a string needs two different ends")
        assert(tr.holds == nil or type(tr.holds) == "string", tr.id .. ": holds names a trap id")
    elseif k == "weight" then
        for _, f in ipairs({ "x", "y", "h", "r" }) do num(tr[f], tr.id .. "." .. f) end
        assert(tr.r > 0, tr.id .. ": r > 0")
    elseif k == "plank" then
        for _, f in ipairs({ "x", "y", "h", "a", "len" }) do num(tr[f], tr.id .. "." .. f) end
        tr.width = num(tr.width or F.TRAP.plank_w, tr.id .. ".width")
        assert(tr.len > 0 and tr.width > 0, tr.id .. ": len and width > 0")
    end
    tr.boxes = trap_boxes(tr)
    self.traps[tr.id] = tr
    self.trap_order[#self.trap_order + 1] = tr
    if k == "support" then self.support_count = (self.support_count or 0) + 1 end
    self._surf, self._sol = nil, nil
    self.rev = self.rev + 1
    return tr
end

-- Every string's holds names an installed weight, plank, gate or support (call once all traps are in).
function Board:check_traps()
    for _, tr in ipairs(self.trap_order) do
        if tr.holds then
            local h = self.traps[tr.holds]
            assert(h and h.kind ~= "zone" and h.kind ~= "string", tr.id .. ": holds " .. tostring(tr.holds) .. ", not a weight, plank, gate or support")
        end
    end
end

-- A fixed piece of a challenge: like place, but it may stand on a support, cannot be removed and does not count
-- against the budget. size: a scale (F.SIZES[i]), default 1.
function Board:place_preset(x, y, a, h, paint, size)
    self._installing = true
    local p, why = self:place(x, y, a, h, paint, size)
    self._installing = nil
    if not p then return nil, why end
    p.fixed, p.preset = true, true
    self.preset_count = self.preset_count + 1
    return p
end

-- Segment (x0, y0, z0)-(x1, y1, z1) through the box (open: touching a face is not through).
local function seg_box(x0, y0, z0, x1, y1, z1, bx0, bx1, by0, by1, bz0, bz1)
    local t0, t1 = 0, 1
    local p, d, lo, hi = { x0, y0, z0 }, { x1 - x0, y1 - y0, z1 - z0 }, { bx0, by0, bz0 }, { bx1, by1, bz1 }
    for i = 1, 3 do
        if abs(d[i]) < 1e-12 then
            if p[i] <= lo[i] or p[i] >= hi[i] then return false end
        else
            local a, b = (lo[i] - p[i]) / d[i], (hi[i] - p[i]) / d[i]
            if a > b then a, b = b, a end
            t0, t1 = max(t0, a), min(t1, b)
            if t0 >= t1 then return false end
        end
    end
    return true
end

-- Why nothing may fill the box x0..x1, y0..y1, z0..z1 (heights): "zone" or "trap" (a trap's body or string), or nil.
function Board:trap_block(x0, x1, y0, y1, z0, z1)
    local list = self.trap_order
    if #list == 0 then return nil end
    local e = 0.01
    for i = 1, #list do
        local tr = list[i]
        if tr.kind == "zone" and x1 > tr.x0 and x0 < tr.x1 and y1 > tr.y0 and y0 < tr.y1 and (not tr.z0 or (z1 > tr.z0 and z0 < tr.z1)) then return "zone" end
    end
    local R = F.TRAP.string_r
    for i = 1, #list do
        local tr = list[i]
        if tr.kind == "string" then
            if seg_box(tr.sx0, tr.sy0, tr.sz0, tr.sx1, tr.sy1, tr.sz1, x0 - R, x1 + R, y0 - R, y1 + R, z0 + e - R, z1 - e + R) then return "trap" end
        else
            for _, b in ipairs(tr.boxes) do
                if x1 > b.x0 + e and x0 < b.x1 - e and y1 > b.y0 + e and y0 < b.y1 - e and z1 > b.z0 + e and z0 < b.z1 - e then return "trap" end
            end
        end
    end
    return nil
end

-- Closest approach of segments P-Q and R-S: squared distance, and where on each (0..1).
local function seg_seg(px, py, pz, qx, qy, qz, rx, ry, rz, sx, sy, sz)
    local d1x, d1y, d1z = qx - px, qy - py, qz - pz
    local d2x, d2y, d2z = sx - rx, sy - ry, sz - rz
    local wx, wy, wz = px - rx, py - ry, pz - rz
    local a = d1x * d1x + d1y * d1y + d1z * d1z
    local e = d2x * d2x + d2y * d2y + d2z * d2z
    local f = d2x * wx + d2y * wy + d2z * wz
    local u, v
    local function cl(x) return x < 0 and 0 or (x > 1 and 1 or x) end
    if a <= 1e-12 and e <= 1e-12 then u, v = 0, 0
    elseif a <= 1e-12 then u, v = 0, cl(f / e)
    else
        local c = d1x * wx + d1y * wy + d1z * wz
        if e <= 1e-12 then u, v = cl(-c / a), 0
        else
            local b = d1x * d2x + d1y * d2y + d1z * d2z
            local den = a * e - b * b
            u = den > 1e-12 and cl((b * f - c * e) / den) or 0
            v = (b * u + f) / e
            if v < 0 then v, u = 0, cl(-c / a)
            elseif v > 1 then v, u = 1, cl((b - c) / a) end
        end
    end
    local dx = px + d1x * u - rx - d2x * v
    local dy = py + d1y * u - ry - d2y * v
    local dz = pz + d1z * u - rz - d2z * v
    return dx * dx + dy * dy + dz * dz, u, v
end
F.seg_seg = seg_seg

-- A plank's tilt (radians from upright) at time t, from its "fall" event: it tips like a domino.
function F.plank_angle(e, t)
    if t <= e.t then return 0 end
    if t >= e.t1 then return e.angle end
    return e.angle * ((t - e.t) / (e.t1 - e.t)) ^ 1.6
end

-- A dropped weight's base height at time t, from its "drop" event: free fall from h to z.
function F.weight_height(e, t)
    if t <= e.t then return e.h end
    if t >= e.t1 then return e.z end
    return max(e.z, e.h - 0.5 * F.BALL.g * (t - e.t) ^ 2)
end

------------------------------------------------------------------ simulation
-- Seconds for a faller of height h to tip through theta (radians): slow start, quick finish.
function F.fall_time(theta, h)
    return F.TIME_K * (0.03 + 0.14 * (max(0, theta) / (pi / 2)) ^ 0.7) * sqrt(h or H)
end

-- Solid contact. A domino pivots on its front edge and leans on the back of the next, so how far it can lean follows
-- from how far the next has gone. S: pivot to pivot along the fall; dz: how much higher the next one stands.
local FLAT = rad(F.REST)
F.LEAN_GAP = rad(0.5)       -- a hair between faces at rest: dominoes in a row end up lying face on face
-- hi: the leaner's height; tj, hj: the thickness and height of the one it leans on (a standard domino's if not given).
function F.lean(next_a, S, dz, hi, tj, hj)
    dz, hi, tj, hj = dz or 0, hi or H, tj or T, hj or H
    local c, s = cos(next_a), sin(next_a)
    local best = FLAT
    -- Its top edge coming down on the next one's back...
    local a = next_a + asin(max(-1, min(1, (S * c - dz * s - tj) / hi)))
    local along = hi * cos(a - next_a) - S * s - dz * c
    if along >= 0 and along <= hj then best = min(best, a) end
    -- ...or its front face on the next one's two back corners, whichever comes first.
    for k = 0, hj, hj do
        local bx, bz = S - tj * c + k * s, dz + tj * s + k * c
        if bx * bx + bz * bz <= hi * hi and bz > 1e-9 then best = min(best, atan2(bx, bz)) end
    end
    return best
end

-- Where a domino comes to rest in a row of evenly spaced ones, having struck the next at this angle: leaning on it
-- with both at the same tilt, cos(tilt) = thickness / spacing. Past the widest spacing that can hold it, it lies flat.
function F.rest_angle(contact, hi, tj)
    hi, tj = hi or H, tj or T
    local S = hi * sin(contact) + tj
    if S * S >= hi * hi + tj * tj then return FLAT end
    return max(contact, acos(tj / S) - F.LEAN_GAP)
end

-- Connecting dominoes as the chain reaches them. f.on_id: what f leans on; falls: records by id; waiting: leaners
-- whose target has not fallen yet. Each new fact runs back up the chain, shrinking fast, so this stays local.
local function refit(i)
    local j = i.on
    -- (what it leaned on went off an edge: it is left lying flat)
    local new = j.dive and FLAT or min(FLAT, F.lean(j.final, i.S, i.dz, i.hh, j.tt, j.hh) - F.LEAN_GAP)
    if abs(new - i.final) < 1e-4 then return end
    i.final = new
    for _, k in ipairs(i.leaners or {}) do refit(k) end
end
local function connect(i, j)
    i.on = j
    j.leaners = j.leaners or {}
    j.leaners[#j.leaners + 1] = i
    refit(i)
end
function F.attach_fall(f, falls, waiting)
    local w = waiting[f.id]
    if w then
        waiting[f.id] = nil
        for _, i in ipairs(w) do connect(i, f) end
    end
    if f.on_id then
        local j = falls[f.on_id]
        if j then connect(f, j)
        else
            waiting[f.on_id] = waiting[f.on_id] or {}
            table.insert(waiting[f.on_id], f)
        end
    end
end
-- What they were leaning on stayed standing (struck edge-on): they stop against it.
function F.fall_missed(id, waiting)
    for _, i in ipairs(waiting[id] or {}) do
        i.on_id, i.final = nil, i.contact
        for _, k in ipairs(i.leaners or {}) do refit(k) end
    end
    waiting[id] = nil
end

-- A domino's tilt at time t. Struck dominoes follow the one they lean on, so they never pass through it or hang in
-- the air; one with nothing to lean on tips on over and, if it lands flat, bounces a little.
local SETTLE = 0.24
function F.fall_angle(f, t)
    if t <= f.t then return 0 end
    local span = max(1e-3, f.tc - f.t)
    if t < f.tc then return f.contact * ((t - f.t) / span) ^ 1.6 end
    local j = f.on
    if j then
        if t >= f.t_end then return f.final end
        if f.ang_t == t then return f.ang end
        f.ang_t, f.ang = t, f.final
        local a
        if j.dive and t >= j.dive.t0 then
            -- It lay on one that has just gone over an edge: it settles flat.
            local a0 = min(FLAT, F.lean(FLAT, f.S, f.dz, f.hh, j.tt, j.hh))
            local s = max(0, min(1, (t - j.dive.t0) / SETTLE))
            a = a0 + (FLAT - a0) * s * s * (3 - 2 * s)
        else
            -- (no faster than it was already going, if what it leans on started before it arrived)
            a = min(f.final, F.lean(F.fall_angle(j, t), f.S, f.dz, f.hh, j.tt, j.hh), f.contact + (t - f.tc) * 1.6 * max(f.contact, 0.2) / span)
        end
        f.ang = a
        return a
    end
    local u = (t - f.tc) / (SETTLE * sqrt(f.s or 1))
    local s = max(0, min(1, u))
    local a = f.contact + (f.final - f.contact) * s * s * (3 - 2 * s)
    if f.final >= rad(85) and u > 0 and u < 1.6 then
        local k = min(1, u / 1.6)
        a = a - rad(5) * sin(k * pi) * (1 - k)
    end
    return a
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
function F.ball_kick(th, arm, k)
    local B = F.BALL
    k = k or 1
    local H = H * k
    arm = min(H, max(0.1, arm))
    local omega = sqrt(3 * B.g / H * (1 - cos(th)))
    local eff = B.domino * k * k * k * H * H / (3 * arm * arm)
    return (1 + B.e) * eff / (eff + B.mass) * omega * arm * 5 / 7
end

-- A run, advanced in time: advance(t) works through everything due by t. With ext (ext.ball(p, t, dx, dy, speed) and
-- ext.swing(p, t)) the engine's rigid bodies move the balls and swings, and strike_ball / strike_bob feed what they
-- meet back into the chain; without it they are stepped here, which is what the tests and the build preview use.
function F.begin_run(board, ext)
    local res = { falls = {}, order = {}, events = {}, toppled = 0, total = board.count, duration = 0, gaps = {}, balls = {}, swings = {}, switches = {}, balls_launched = 0, swings_released = 0,
        traps = {}, lost = {} }
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
    local smax = board.smax or 1
    local hit_q, hit_th, hit_kick = {}, {}, {}
    res.lands = {}
    local gone = {}         -- traps no longer in place (cut, dropped, fallen, open, collapsed), by id
    -- The highest thing under (x, y) that is no higher than z: where something dropped from there comes down.
    local surfaces = board:all_surfaces()
    local function ground_below(x, y, z)
        local g = 0
        for i = 1, #surfaces do
            local s = surfaces[i]
            if s.h > g and s.h <= z + 0.05 and x >= s.x0 and x <= s.x1 and y >= s.y0 and y <= s.y1 and not (s.trap and gone[s.trap.id]) then g = s.h end
        end
        for i = 1, #solids do
            local s = solids[i]
            if s.z1 > g and s.z1 <= z + 0.05 and x >= s.x0 and x <= s.x1 and y >= s.y0 and y <= s.y1 and not (s.trap and gone[s.trap.id]) then g = s.z1 end
        end
        return g
    end
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
    local waiting = {}
    ------------------------------------------------ traps, stepped in the same queue
    local TR = F.TRAP
    local strings = {}
    for _, tr in ipairs(board.trap_order) do if tr.kind == "string" then strings[#strings + 1] = tr end end
    local function trap_event(e)
        res.traps[#res.traps + 1] = e
        if e.t > res.duration then res.duration = e.t end
    end
    local function push_trap(t, tr, ev, info)
        seq = seq + 1
        heap_push(hp, { t = t, trap = tr, ev = ev, info = info, seq = seq })
    end
    local function cut(s, t, by, x, y, z)
        if not gone[s.id] then push_trap(t, s, "cut", { by = by, x = x, y = y, z = z }) end
    end
    -- A sphere of radius r moving from (ax, ay, az) to (bx, by, bz) (centres) at time t cuts the strings it touches.
    local function cut_sphere(ax, ay, az, bx, by, bz, r, t, by_what)
        local R = r + TR.string_r
        for i = 1, #strings do
            local s = strings[i]
            if not gone[s.id] and min(ax, bx) - r < s.bx1 and max(ax, bx) + r > s.bx0 and min(ay, by) - r < s.by1 and max(ay, by) + r > s.by0
                and min(az, bz) - r < s.bz1 and max(az, bz) + r > s.bz0 then
                local d2, _, v = seg_seg(ax, ay, az, bx, by, bz, s.sx0, s.sy0, s.sz0, s.sx1, s.sy1, s.sz1)
                if d2 < R * R then
                    cut(s, t, by_what, s.sx0 + (s.sx1 - s.sx0) * v, s.sy0 + (s.sy1 - s.sy0) * v, s.sz0 + (s.sz1 - s.sz0) * v)
                end
            end
        end
    end
    -- Something tipping over like a domino (pivot on the front edge of the one standing at (px, py, pz), facing fx, fy,
    -- thickness PT, width PW, height PH) as far as thmax, from time t, reaching `contact` at tc: the strings it sweeps.
    local function sweep_strings(px, py, pz, fx, fy, PT, PW, PH, thmax, t, tc, contact, by_what)
        local ox, oy = px + fx * PT / 2, py + fy * PT / 2
        local reach = PH + PT
        for i = 1, #strings do
            local s = strings[i]
            if not gone[s.id] and s.bx0 < px + reach and s.bx1 > px - reach and s.by0 < py + reach and s.by1 > py - reach and s.bz1 > pz and s.bz0 < pz + PH then
                local n = max(2, math.ceil(s.len / 0.05))
                local best, cx, cy, cz
                for k = 0, n do
                    local u = k / n
                    local x, y, z = s.sx0 + (s.sx1 - s.sx0) * u, s.sy0 + (s.sy1 - s.sy0) * u, s.sz0 + (s.sz1 - s.sz0) * u
                    local up = z - pz
                    local rx, ry = x - ox, y - oy
                    local along = rx * fx + ry * fy
                    if up >= -TR.string_r and along >= -PT and abs(rx * fy - ry * fx) <= PW / 2 + TR.string_r and along * along + up * up <= (PH + TR.string_r) ^ 2 then
                        local phi = max(0, atan2(along, max(up, 1e-6)))
                        if phi <= thmax + 1e-6 and (not best or phi < best) then best, cx, cy, cz = phi, x, y, z end
                    end
                end
                if best then
                    local tcut = best <= contact and t + (tc - t) * (best / max(contact, 1e-6)) ^ (1 / 1.6) or tc
                    cut(s, tcut, by_what, cx, cy, cz)
                end
            end
        end
    end
    -- What a dropped weight or a plank's far end comes down on at (x, y), height g, within R: dominoes go over (along
    -- fx, fy if given, else away from the middle), switches are pressed, balls launched, a support under it collapses.
    local collapse
    local function smash(x, y, g, R, t, fx, fy, by_what)
        board:near(x, y, R + W * smax, function(q)
            if not done[q.id] and abs(q.z - g) < 0.6 then
                local rx, ry = q.x - x, q.y - y
                if rx * rx + ry * ry < (R + q.s * W / 2) ^ 2 then
                    local d = fx and fx * q.ax + fy * q.ay or 0
                    if abs(d) < 0.3 then d = rx * q.ax + ry * q.ay end
                    local sg = d >= 0 and 1 or -1
                    push(t, q, q.ax * sg, q.ay * sg)
                end
            end
        end)
        for i = 1, #switch_list do
            local q = switch_list[i]
            if not done[q.id] and abs(q.z - g) < 1 then
                local ox, oy = x - max(q.x - SW.r, min(q.x + SW.r, x)), y - max(q.y - SW.r, min(q.y + SW.r, y))
                if ox * ox + oy * oy < R * R then push(t, q, fx or 1, fy or 0) end
            end
        end
        for i = 1, #ball_list do
            local q = ball_list[i]
            local rx, ry = q.x - x, q.y - y
            local d = sqrt(rx * rx + ry * ry)
            if not done[q.id] and abs(q.z - g) < 1 and d < R + B.r then
                local dx, dy = fx, fy
                if not dx then
                    if d > 1e-6 then dx, dy = rx / d, ry / d else dx, dy = 1, 0 end
                end
                push(t, q, dx, dy, TR.weight_kick)
            end
        end
        for _, tr in ipairs(board.trap_order) do
            if tr.kind == "support" and not gone[tr.id] and abs(tr.z1 - g) < 0.05 and x > tr.x0 - R and x < tr.x1 + R and y > tr.y0 - R and y < tr.y1 + R then
                collapse(tr, t, by_what)
            end
        end
    end
    -- A support gives way: its top is gone and whatever still stands on it is lost.
    function collapse(tr, t, by_what)
        if gone[tr.id] then return end
        gone[tr.id] = true
        local lost = {}
        local function on_top(q) return not done[q.id] and abs(q.z - tr.z1) < 0.05 and q.x >= tr.x0 and q.x <= tr.x1 and q.y >= tr.y0 and q.y <= tr.y1 end
        local cx, cy = (tr.x0 + tr.x1) / 2, (tr.y0 + tr.y1) / 2
        board:near(cx, cy, sqrt((tr.x1 - cx) ^ 2 + (tr.y1 - cy) ^ 2) + 0.1, function(q) if on_top(q) then lost[#lost + 1] = q.id end end)
        for _, q in ipairs(ball_list) do if on_top(q) then lost[#lost + 1] = q.id end end
        for _, q in ipairs(switch_list) do if on_top(q) then lost[#lost + 1] = q.id end end
        table.sort(lost)
        for _, id in ipairs(lost) do
            done[id] = true
            res.lost[#res.lost + 1] = { id = id, t = t }
            F.fall_missed(id, waiting)
        end
        trap_event({ t = t, id = tr.id, kind = "support", event = "collapse", by = by_what, lost = lost })
    end
    -- A plank let go: it tips along a from its hinge until its far end comes down on something or meets furniture.
    local function plank_fall(tr, t)
        local fx, fy, L = cos(tr.a), sin(tr.a), tr.len
        local th, lastz, step = 0, tr.h + L, rad(0.5)
        local tx, ty, tz, landed, blocked_by = tr.x, tr.y, tr.h + L, nil, nil
        while th < pi do
            local nth = th + step
            local x, y, z = tr.x + fx * L * sin(nth), tr.y + fy * L * sin(nth), tr.h + L * cos(nth)
            for i = 1, #solids do
                local s = solids[i]
                if x > s.x0 and x < s.x1 and y > s.y0 and y < s.y1 and z > s.z0 + 0.01 and z < s.z1 - 0.01 and s.z1 > lastz + 0.05 and not (s.trap and (s.trap == tr or gone[s.trap.id])) then
                    blocked_by = s; break
                end
            end
            if blocked_by then break end
            local g = ground_below(x, y, lastz)
            if z <= g + 1e-6 then
                th = abs(g - tr.h) <= L and acos(max(-1, min(1, (g - tr.h) / L))) or nth
                tx, ty, tz, landed = tr.x + fx * L * sin(th), tr.y + fy * L * sin(th), g, true
                break
            end
            th, lastz, tx, ty, tz = nth, z, x, y, z
        end
        local t1 = t + F.fall_time(th, L)
        trap_event({ t = t, id = tr.id, kind = "plank", event = "fall", angle = th, t1 = t1, x = tx, y = ty, h = tz })
        -- Standing dominoes in its way go over as it reaches them.
        local hw = tr.width / 2
        board:near(tr.x, tr.y, L + W * smax, function(q)
            if not done[q.id] then
                local rx, ry = q.x - tr.x, q.y - tr.y
                local along = rx * fx + ry * fy
                local qs = q.s
                local cq, sq = abs(q.ax * fx + q.ay * fy), abs(q.ax * fy - q.ay * fx)
                if along > 0 and abs(rx * fy - ry * fx) < hw + (sq * T / 2 + cq * W / 2) * qs then
                    local dz = q.z - tr.h
                    local c = along - (cq * T / 2 + sq * W / 2) * qs
                    local cth = F.contact_angle(c, dz, dz + H * qs, L)
                    if cth and cth < th - rad(1) then
                        local d = fx * q.ax + fy * q.ay
                        local sg = d >= 0 and 1 or -1
                        if abs(d) < 0.3 then sg = (rx * q.ax + ry * q.ay) >= 0 and 1 or -1 end
                        push(t + F.fall_time(cth, L), q, q.ax * sg, q.ay * sg)
                    end
                end
            end
        end)
        sweep_strings(tr.x - fx * TR.plank_t / 2, tr.y - fy * TR.plank_t / 2, tr.h, fx, fy, TR.plank_t, tr.width, L, th, t, t1, th, "plank")
        if blocked_by and blocked_by.trap and blocked_by.trap.kind == "support" then push_trap(t1, blocked_by.trap, "collapse", { by = "plank" }) end
        if landed then push_trap(t1, tr, "land", { x = tx, y = ty, g = tz, fx = fx, fy = fy }) end
    end
    -- A string lets go of what it holds.
    local function release(id, t)
        local tr = board.traps[id]
        if not tr or gone[tr.id] then return end
        if tr.kind == "support" then collapse(tr, t, "string"); return end
        gone[tr.id] = true
        if tr.kind == "gate" then
            trap_event({ t = t, id = tr.id, kind = "gate", event = "open" })
        elseif tr.kind == "plank" then
            plank_fall(tr, t)
        elseif tr.kind == "weight" then
            local g = ground_below(tr.x, tr.y, tr.h)
            local t1 = t + sqrt(2 * max(0, tr.h - g) / B.g)
            trap_event({ t = t, id = tr.id, kind = "weight", event = "drop", x = tr.x, y = tr.y, h = tr.h, z = g, t1 = t1 })
            -- Strings under it: cut as it falls through them.
            local r = tr.r
            for i = 1, #strings do
                local s = strings[i]
                if not gone[s.id] then
                    local d2, u, v = seg_seg(tr.x, tr.y, tr.h + r, tr.x, tr.y, g + r, s.sx0, s.sy0, s.sz0, s.sx1, s.sy1, s.sz1)
                    if d2 < (r + TR.string_r) ^ 2 then
                        local fallen = max(0, (tr.h - g) * u - r)
                        cut(s, t + sqrt(2 * fallen / B.g), "weight", s.sx0 + (s.sx1 - s.sx0) * v, s.sy0 + (s.sy1 - s.sy0) * v, s.sz0 + (s.sz1 - s.sz0) * v)
                    end
                end
            end
            push_trap(t1, tr, "land", { x = tr.x, y = tr.y, g = g })
        end
    end
    local function trap_job(job, t)
        local tr, i = job.trap, job.info
        if job.ev == "cut" then
            if gone[tr.id] then return end
            gone[tr.id] = true
            trap_event({ t = t, id = tr.id, kind = "string", event = "cut", by = i.by, x = i.x, y = i.y, h = i.z, holds = tr.holds })
            if tr.holds then release(tr.holds, t) end
        elseif job.ev == "collapse" then
            collapse(tr, t, i.by)
        elseif job.ev == "land" then
            trap_event({ t = t, id = tr.id, kind = tr.kind, event = "land", x = i.x, y = i.y, h = i.g })
            if tr.kind == "weight" then smash(i.x, i.y, i.g, tr.r, t, nil, nil, "weight")
            else smash(i.x, i.y, i.g, max(TR.knock, tr.width / 2), t, i.fx, i.fy, "plank") end
        end
    end
    local function push_ball(t, b)
        seq = seq + 1
        heap_push(hp, { t = t, ball = b, seq = seq })
    end
    local function launch(p, t, dx, dy, speed)
        done[p.id] = true
        res.balls_launched = res.balls_launched + 1      -- counted here: a live run's real bodies are not in res.balls
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
        local x0, y0 = b.x, b.y
        if b.air then b.vz = b.vz - B.g * dt end
        local air = max(0, 1 - B.air * sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz) * dt)
        b.vx, b.vy, b.vz = b.vx * air, b.vy * air, b.vz * air
        b.x, b.y, b.z = b.x + b.vx * dt, b.y + b.vy * dt, b.z + b.vz * dt
        if #strings > 0 then cut_sphere(x0, y0, z0 + r, b.x, b.y, b.z + r, r, t, "ball") end
        local g = ball_ground(b.x, b.y, max(z0, b.z))
        local rg, ramp = ramp_ground(b.x, b.y, max(z0, b.z))
        if rg and rg >= g then g = rg else ramp = nil end
        -- Up a step (not a ramp): the climb costs 2 * grav * g * rise of v^2, as for a real rolling ball. Without that
        -- much speed it rolls back off the lip (with what a hit on a domino leaves it). Stepping down gains nothing.
        local rise = g - max(z0, b.z)
        if rise > 1e-6 and not ramp and not b.ramp then
            local cost, v2 = 2 * RP.grav * B.g * rise, b.vx * b.vx + b.vy * b.vy
            if v2 > cost then
                local k = sqrt((v2 - cost) / v2)
                b.vx, b.vy = b.vx * k, b.vy * k
            else
                local bx, by = b.x, b.y
                b.x, b.y, b.z = x0, y0, z0
                local up_x = ball_ground(bx, y0, z0) > z0 + 1e-6
                local up_y = ball_ground(x0, by, z0) > z0 + 1e-6
                if not up_x and not up_y then up_x, up_y = true, true end
                b.vx = (up_x and -B.rebound or 1) * b.vx
                b.vy = (up_y and -B.rebound or 1) * b.vy
                g = ball_ground(x0, y0, z0)
            end
        end
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
            if not on_slope and b.z < s.z1 - 0.01 and b.z + 2 * r > s.z0 and not (s.trap and gone[s.trap.id]) then
                local nx, ny = b.x - max(s.x0, min(s.x1, b.x)), b.y - max(s.y0, min(s.y1, b.y))
                local d2 = nx * nx + ny * ny
                if d2 < r * r then
                    if s.trap and s.trap.kind == "support" and sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz) >= TR.support_hit then
                        collapse(s.trap, t, "ball")
                    end
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
        board:near(b.x, b.y, r + W * smax, function(q)
            local T, W, H = T * q.s, W * q.s, H * q.s
            if not done[q.id] and cz + r > q.z and cz - r < q.z + H then
                local rx, ry = b.x - q.x, b.y - q.y
                local u, v = rx * q.ax + ry * q.ay, ry * q.ax - rx * q.ay
                local cu, cv = max(-T / 2, min(T / 2, u)), max(-W / 2, min(W / 2, v))
                local ch = max(q.z, min(q.z + H, cz))
                local du, dv, dh = u - cu, v - cv, cz - ch
                if du * du + dv * dv + dh * dh < r * r then
                    local s = sqrt(b.vx * b.vx + b.vy * b.vy)
                    local dx, dy = s > 1e-6 and b.vx / s or 0, s > 1e-6 and b.vy / s or 0
                    -- (falling on it counts as well; the bigger the domino, the harder it is to tip)
                    if s * s + b.vz * b.vz >= (B.min_hit * q.s * q.s) ^ 2 then
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
        res.swings_released = res.swings_released + 1
        if ext then ext.swing(p, t); return end
        local s = { id = p.id, p = p, th = -p.amp, w = 0, t0 = t, n = 0, pts = { t, -p.amp }, bumps = {}, period = 2 * pi * sqrt(p.L / B.g) }
        res.swings[#res.swings + 1] = s
        push_swing(t + S.dt, s)
    end
    -- One time step of a swing, in the same queue as everything else.
    local function step_swing(s, t)
        local p, L, dt, r = s.p, s.p.L, S.dt, S.r
        local ox, oy, oz = F.swing_bob(p, s.th)
        s.w = s.w + (-(B.g / L) * sin(s.th) - S.damp * s.w) * dt
        s.th = s.th + s.w * dt
        local x, y, cz = F.swing_bob(p, s.th)
        if #strings > 0 then cut_sphere(ox, oy, oz, x, y, cz, r, t, "swing") end
        local dir = s.w >= 0 and 1 or -1
        local dx, dy = p.ax * dir, p.ay * dir
        local speed = abs(s.w) * L * cos(s.th)
        -- Furniture turns it back.
        for i = 1, #solids do
            local q = solids[i]
            if cz - r < q.z1 - 0.01 and cz + r > q.z0 and not (q.trap and gone[q.trap.id]) then
                local cx, cy = max(q.x0, min(q.x1, x)), max(q.y0, min(q.y1, y))
                local ox, oy = cx - x, cy - y
                if ox * ox + oy * oy < r * r and ox * dx + oy * dy > 0 then
                    if q.switch and not done[q.switch.id] and speed >= S.min_hit then push(t, q.switch, dx, dy) end
                    if q.trap and q.trap.kind == "support" and speed >= S.min_hit then collapse(q.trap, t, "swing") end
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
        if job.trap then
            trap_job(job, t)
        elseif job.ball then
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
                F.fall_missed(p.id, waiting)
                if not wobbled[p.id] then
                    wobbled[p.id] = true
                    res.events[#res.events + 1] = { t = t, kind = "wobble", id = p.id }
                end
            else
                local sgn = d > 0 and 1 or -1
                local fx, fy = p.ax * sgn, p.ay * sgn
                done[p.id] = true
                res.toppled = res.toppled + 1
                local ps = p.s
                local PT, PW, PH = T * ps, W * ps, H * ps
                local reach = PH + W * smax
                -- Dominoes ahead.
                local nh, best = 0, nil
                local best_on, best_c, best_dz, best_s          -- the one it comes to lean on
                local lean_th, lean_on, lean_c, lean_dz, lean_s -- or, with none left standing ahead, one already down
                local wall, ledge, wall_s, ledge_s
                board:near(p.x, p.y, reach, function(q)
                    local down = done[q.id] and res.falls[q.id]
                    if q ~= p and (not done[q.id] or (down and not down.dive and down.dx * fx + down.dy * fy > 0)) then
                        local rx, ry = q.x - p.x, q.y - p.y
                        local along = rx * fx + ry * fy
                        if along > 0.02 and along < reach then
                            local qs = q.s
                            local cq, sq = abs(q.ax * fx + q.ay * fy), abs(q.ax * fy - q.ay * fx)
                            local lat = abs(rx * fy - ry * fx)
                            if lat < PW / 2 + (sq * T / 2 + cq * W / 2) * qs - 0.02 then
                                local c = along - PT / 2 - (cq * T / 2 + sq * W / 2) * qs
                                local dz = q.z - p.z
                                local th = F.contact_angle(c, dz, dz + H * qs, PH)
                                if th and down then
                                    if not lean_th or th < lean_th then lean_th, lean_on, lean_c, lean_dz, lean_s = th, q.id, c, dz, qs end
                                elseif th and qs > ps * F.KNOCK * 1.01 then
                                    -- Too big for it to tip: it stops against it, as against furniture.
                                    if not wall or th < wall then wall, wall_s = th, nil end
                                elseif th then
                                    nh = nh + 1
                                    hit_q[nh], hit_th[nh] = q, th
                                    if not best or th < best then best, best_on, best_c, best_dz, best_s = th, q.id, c, dz, qs end
                                end
                            end
                        end
                    end
                end)
                -- Furniture and ledges.
                local pvx, pvy = p.x + fx * PT / 2, p.y + fy * PT / 2
                for i = 1, #solids do
                    local s = solids[i]
                    if s.z1 > p.z + 0.01 and s.z0 < p.z + PH and not (s.trap and gone[s.trap.id]) then
                        local c = ray_box(pvx, pvy, fx, fy, PW / 2 - 0.02, s, PH)
                        if c then
                            local zt = s.z1 - p.z
                            local th = F.contact_angle(c, s.z0 - p.z, zt, PH)
                            if th then
                                if zt <= F.LEDGE * ps then
                                    if not ledge or th < ledge then ledge, ledge_s = th, s end
                                elseif not wall or th < wall then wall, wall_s = th, s end
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
                        if along > 0.02 and along < PH + qr and abs(rx * fy - ry * fx) < PW / 2 + qr * 0.85 then
                            local dz = q.z + lift - p.z
                            local th = F.contact_angle(along - PT / 2 - qr, dz, dz + 2 * qr, PH)
                            if th then
                                nh = nh + 1
                                local cc, zt = max(0.02, along - PT / 2 - qr), dz + 2 * qr
                                hit_q[nh], hit_th[nh], hit_kick[nh] = q, th, q.kind == "ball" and F.ball_kick(th, sqrt(cc * cc + zt * zt), ps) or nil
                            end
                        end
                    end
                end
                local fall = { id = p.id, t = t, yaw = atan2(fy, fx), flip = sgn < 0, dx = fx, dy = fy, s = ps, hh = PH, tt = PT }
                local contact
                if best and (not wall or best <= wall) then
                    contact = best
                    fall.hits = 0
                    local tc = t + F.fall_time(contact, PH)
                    -- (as far as it can come down if the one it leans on ends up flat: what is under it by then is flattened)
                    local sweep = F.lean(FLAT, max(best_c, 0.02) + T * best_s, best_dz, PH, T * best_s, H * best_s)
                    for i = 1, n_dom do
                        if hit_th[i] <= best + rad(3) then
                            push(tc, hit_q[i], fx, fy)
                            fall.hits = fall.hits + 1
                        elseif hit_q[i].s * 1.2 < ps and hit_th[i] <= sweep then
                            push(t + F.fall_time(hit_th[i], PH), hit_q[i], fx, fy)
                            fall.hits = fall.hits + 1
                        end
                    end
                    fall.final = F.rest_angle(contact, PH, T * best_s)
                    fall.on_id, fall.S, fall.dz = best_on, max(best_c, 0.02) + T * best_s, best_dz
                elseif lean_th and (not wall or lean_th <= wall) then
                    contact, fall.final = lean_th, F.rest_angle(lean_th, PH, T * lean_s)
                    fall.on_id, fall.S, fall.dz = lean_on, max(lean_c, 0.02) + T * lean_s, lean_dz
                elseif wall then
                    contact, fall.blocked, fall.final = wall, true, wall
                else
                    contact = ledge or rad(F.REST)
                    fall.final = contact
                end
                for i = n_dom + 1, nh do
                    if hit_th[i] <= contact + rad(3) then
                        push(t + F.fall_time(hit_th[i], PH), hit_q[i], fx, fy, hit_kick[i])
                        fall.hits = (fall.hits or 0) + 1
                    end
                end
                for i = 1, nh do hit_q[i], hit_kick[i] = nil, nil end
                fall.contact = contact
                fall.tc = t + F.fall_time(contact, PH)
                -- Nothing ahead and its middle past the edge of what it stands on: it tips off and tumbles down.
                if not fall.on_id and not fall.blocked and not ledge then
                    local D = F.DIVE
                    local a0 = PT / 2 + PH / 2
                    local g = ground_below(p.x + fx * a0, p.y + fy * a0, p.z)
                    local drop = p.z - g
                    if drop >= max(D.min_drop, 0.5 * PH) then
                        local td = sqrt(2 * drop / B.g) * 1.15
                        local a1 = a0 + D.speed * sqrt(ps) * td
                        local lx, ly = p.x + fx * a1, p.y + fy * a1
                        g = ground_below(lx, ly, p.z)
                        drop = p.z - g
                        td = sqrt(2 * drop / B.g) * 1.15
                        local t1 = fall.tc + td
                        -- (a long drop turns it right over onto its back; a short one only lets it flop down)
                        fall.dive = { t0 = fall.tc, t1 = t1, a0 = a0, a1 = a1, z0 = p.z + PT / 2, z1 = g + PT / 2, flip = td >= 0.2, x = lx, y = ly, g = g }
                        fall.t_end = t1 + 0.2
                        res.lands[#res.lands + 1] = { t = t1, id = p.id, x = lx, y = ly, z = g, s = ps }
                        -- (coming down on a fragile support breaks it)
                        for _, tr in ipairs(board.trap_order) do
                            if tr.kind == "support" and not gone[tr.id] and abs(tr.z1 - g) < 0.05 and lx >= tr.x0 and lx <= tr.x1 and ly >= tr.y0 and ly <= tr.y1 then
                                push_trap(t1, tr, "collapse", { by = "dive" })
                            end
                        end
                        -- What it lands on goes over.
                        board:near(lx, ly, PH / 2 + W * smax + 0.2, function(q)
                            if q ~= p and abs(q.z - g) < 0.6 and q.s <= ps * F.KNOCK * 1.01 then
                                local rx, ry = q.x - lx, q.y - ly
                                if abs(rx * fx + ry * fy) < PH / 2 + T * q.s / 2 + D.margin and abs(rx * fy - ry * fx) < PW / 2 + W * q.s / 2 - 0.02 then
                                    local along = fx * q.ax + fy * q.ay
                                    if abs(along) >= 0.3 then push(t1, q, fx, fy)
                                    else
                                        -- (side on: it goes over away from where the faller came down)
                                        local away = (rx * q.ax + ry * q.ay) >= 0 and 1 or -1
                                        push(t1, q, q.ax * away, q.ay * away)
                                    end
                                    fall.hits = (fall.hits or 0) + 1
                                end
                            end
                        end)
                        for i = 1, #target_list do
                            local q = target_list[i]
                            local qx, qy = q.kind == "swing" and q.lx or q.x, q.kind == "swing" and q.ly or q.y
                            local rx, ry = qx - lx, qy - ly
                            -- (a switch or a latch is solid: it comes down on top of it)
                            if g - q.z < 1 and q.z - g < 0.6 and abs(rx * fx + ry * fy) < PH / 2 + 0.4 and abs(rx * fy - ry * fx) < PW / 2 + 0.3 then
                                push(t1, q, fx, fy, q.kind == "ball" and D.speed * 2 * sqrt(ps) or nil)
                                fall.hits = (fall.hits or 0) + 1
                            end
                        end
                    end
                end
                -- Traps: a fragile support it strikes gives way; strings it sweeps through (or dives through) are cut.
                local hit_s = (fall.blocked and wall_s) or (not fall.on_id and ledge and contact == ledge and ledge_s) or nil
                if hit_s and hit_s.trap and hit_s.trap.kind == "support" then push_trap(fall.tc, hit_s.trap, "collapse", { by = "domino" }) end
                if #strings > 0 then
                    sweep_strings(p.x, p.y, p.z, fx, fy, PT, PW, PH, max(contact, fall.final), t, fall.tc, contact, "domino")
                    local d = fall.dive
                    if d then
                        for k = 1, 24 do
                            local u = k / 24
                            local along, z = d.a0 + (d.a1 - d.a0) * u, d.z0 + (d.z1 - d.z0) * u * u
                            local u0 = (k - 1) / 24
                            local along0, z0 = d.a0 + (d.a1 - d.a0) * u0, d.z0 + (d.z1 - d.z0) * u0 * u0
                            cut_sphere(p.x + fx * along0, p.y + fy * along0, z0, p.x + fx * along, p.y + fy * along, z, PH / 2, d.t0 + (d.t1 - d.t0) * u, "dive")
                        end
                    end
                end
                -- (one leaning on the next only stops when the ones ahead have: the gap to its rest shrinks with each)
                fall.t_end = fall.dive and fall.t_end or fall.tc + (fall.on_id and max(0.15, 10 * (fall.tc - t)) or 0.15 * sqrt(ps))
                res.falls[p.id] = fall
                F.attach_fall(fall, res.falls, waiting)
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
    local function strike(r, by_what, x0, y0, c0, x1, y1, c1, vx, vy, vz, t, min_hit)
        local speed = sqrt(vx * vx + vy * vy + vz * vz)
        -- Traps: strings it passes through are cut; a support it strikes hard enough collapses (its body is the world's).
        if #strings > 0 then cut_sphere(x0, y0, c0, x1, y1, c1, r, t, by_what) end
        if speed >= (by_what == "ball" and TR.support_hit or min_hit) then
            for _, tr in ipairs(board.trap_order) do
                if tr.kind == "support" and not gone[tr.id] and min(c0, c1) - r < tr.z1 and max(c0, c1) + r > tr.z0
                    and seg_box(x0, y0, c0, x1, y1, c1, tr.x0 - r, tr.x1 + r, tr.y0 - r, tr.y1 + r, tr.z0 - r, tr.z1 + r) then
                    push_trap(t, tr, "collapse", { by = by_what })
                end
            end
        end
        local hv = max(1e-6, sqrt(vx * vx + vy * vy))
        local dx, dy = vx / hv, vy / hv
        local len = sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2 + (c1 - c0) ^ 2)
        local n = min(40, max(1, floor(len / (r * 0.5)) + 1))
        local nrx, nry, struck
        for k = 1, n do
            local u = k / n
            local x, y, c = x0 + (x1 - x0) * u, y0 + (y1 - y0) * u, c0 + (c1 - c0) * u
            board:near(x, y, r + W * smax, function(q)
                local T, W, H = T * q.s, W * q.s, H * q.s
                if not done[q.id] and c + r > q.z and c - r < q.z + H then
                    local rx, ry = x - q.x, y - q.y
                    local qu, qv = rx * q.ax + ry * q.ay, ry * q.ax - rx * q.ay
                    local du, dv = qu - max(-T / 2, min(T / 2, qu)), qv - max(-W / 2, min(W / 2, qv))
                    local dh = c - max(q.z, min(q.z + H, c))
                    if du * du + dv * dv + dh * dh < r * r then
                        if speed >= min_hit * q.s * q.s then push(t, q, dx, dy) end
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
        strike_ball = function(...) return strike(B.r, "ball", ...) end, strike_bob = function(...) return strike(S.r, "swing", ...) end }
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
function F.pose(p, yaw, flip, theta, along, height)
    local ca, sa = cos(yaw), sin(yaw)
    local ct, st = cos(theta), sin(theta)
    local e = T * (p.s or 1) / 2
    local k = e * (1 - ct)
    local x, y, h = p.x + ca * k, p.y + sa * k, p.z + e * st
    if along then
        -- In the air: its middle is `along` ahead of where it stood, at `height`.
        local half = H * (p.s or 1) / 2
        x, y, h = p.x + ca * (along - half * st), p.y + sa * (along - half * st), height - half * ct
    end
    local cb, sb = ct, -st
    local rx, ry, rz
    if not flip then
        ry = asin(max(-1, min(1, sa * cb))); rx = atan2(sa * sb, ca); rz = atan2(sb, ca * cb)
    else
        ry = asin(max(-1, min(1, -sa * cb))); rx = atan2(sa * sb, -ca); rz = atan2(-sb, -ca * cb)
    end
    return x, h, -y, deg(rx), deg(ry), deg(rz)
end

-- A falling domino at time t: tipping on its edge, then (off an edge) tumbling down to where it lands.
function F.fall_pose(p, f, t)
    local d = f.dive
    if not d or t <= d.t0 then return F.pose(p, f.yaw, f.flip, F.fall_angle(f, t)) end
    local u = min(1, (t - d.t0) / (d.t1 - d.t0))
    local th = d.flip and FLAT + (1.5 * pi - FLAT) * u or FLAT + rad(30) * sin(pi * u)
    local z = d.z0 + (d.z1 - d.z0) * u * u
    if t > d.t1 then
        local v = (t - d.t1) / 0.2
        if v < 1 then z = z + min(0.35, 0.05 * (d.z0 - d.z1)) * sin(pi * v) * (1 - v) end
    end
    return F.pose(p, f.yaw, f.flip, th, d.a0 + (d.a1 - d.a0) * u, z)
end

------------------------------------------------------------------ saving
function F.serialize(board)
    local list = {}
    -- (a challenge's presets and traps belong to the challenge, never to a save)
    for _, p in pairs(board.pieces) do if not p.preset then list[#list + 1] = p end end
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
        out[#out + 1] = string.format(p.s == 1 and "d %.3f %.3f %.3f %.4f %s" or "d %.3f %.3f %.3f %.4f %s %.4f", p.x, p.y, p.z, p.a, p.paint or "cream", p.s)
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
            local w = { kind = "switch", id = b.next_id, x = tonumber(wx), y = tonumber(wy), z = b:rest(tonumber(wx), tonumber(wy), tonumber(wz), 2 * F.SWITCH.r), dir = tonumber(wd), lamp = wl == "1", order = b.order }
            b:_insert(w)
            if tonumber(wt) > 0 then wait_target[w] = tonumber(wt) end
        end
        local sx, sy, sz, sa, sl, hang = line:match("^s (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)")
        if sx then
            b.next_id = b.next_id + 1
            b.order = b.order + 1
            b:_insert({ kind = "swing", id = b.next_id, x = tonumber(sx), y = tonumber(sy), z = b:rest(tonumber(sx), tonumber(sy), tonumber(sz), F.SWING.post), a = tonumber(sa), L = tonumber(sl), hang = hang, order = b.order })
        end
        local bx, by, bz = line:match("^b (%S+) (%S+) (%S+)")
        if bx then
            b.next_id = b.next_id + 1
            b.order = b.order + 1
            b:_insert({ kind = "ball", id = b.next_id, x = tonumber(bx), y = tonumber(by), z = b:rest(tonumber(bx), tonumber(by), tonumber(bz), 2 * F.BALL.r), order = b.order })
        end
        local x, y, z, a, paint, size = line:match("^d (%S+) (%S+) (%S+) (%S+) (%S+) ?(%S*)")
        if x then
            i = i + 1
            b.next_id = b.next_id + 1
            b.order = b.order + 1
            local p = { id = b.next_id, x = tonumber(x), y = tonumber(y), z = tonumber(z), a = tonumber(a), paint = paint, order = b.order }
            if size ~= "" then p.s = max(0.25, min(8, tonumber(size))) end
            p.z = b:rest(p.x, p.y, p.z, H * (p.s or 1))       -- (an old save's piece under a mat stands on it)
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
