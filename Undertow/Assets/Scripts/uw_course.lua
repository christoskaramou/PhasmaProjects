-- The course: the fixed stretch the two target frames show (uw_data.COURSE, from tools/uw_common.py) continued
-- endlessly by a seeded generator, plus where each piece floats at sea time t and where its hook is.
-- Pure Lua (no engine calls), so tests/view_smoke.lua can drive it. Blender axes: x along the harbour, y depth, z up.
return function(D, Sea)
local C = {}
local sin, cos, rad, floor, max, min, abs = math.sin, math.cos, math.rad, math.floor, math.max, math.min, math.abs

local function lcg(seed)
    local s = seed % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function(a, b)
        s = (s * 48271) % 2147483647
        local u = (s - 1) / 2147483646
        if a then return a + (b - a) * u end
        return u
    end
end

-- A piece floats on the water: buoys and boats bob (BOB_K of the water's rise); piers and the breakwater stand.
local function origin(it, t)
    local p = it.p
    local sc = p.scale or 1
    if it.kind == "buoy_red" or it.kind == "buoy_white" then
        local y = p.y or D.BUOY_BACK
        local ox = it.x - D.ARM_FWD * sc
        return ox, y, D.BOB_K.buoy * Sea.height(ox, y, t) - D.SINK
    elseif it.kind == "boat" then
        return it.x, p.y, D.BOB_K.boat * Sea.height(it.x, p.y, t) - D.SINK
    elseif it.kind == "pier" then
        return it.x, D.PIER_Y, 0
    end
    return it.x, p.y or D.BW_Y, 0
end
-- Memo per item for the last sea time asked (the rules ask many times per step; a pure function of (item, t)).
function C.origin(it, t)
    if it._ot ~= t then
        it._ot = t
        it._ox, it._oy, it._oz = origin(it, t)
    end
    return it._ox, it._oy, it._oz
end

-- Buoy tilt (pitch about y, degrees) and its effect on a local point: as uw_common.tilt_point with roll 0.
local function tilt(px, py, pz, pitch)
    local c, s = cos(rad(pitch)), sin(rad(pitch))
    return px * c + pz * s, py, -px * s + pz * c
end
C.tilt = tilt

-- The hook a float can hang from on this piece (buoys on the play plane and pier segments), world point at t.
function C.hook(it, t)
    if it.kind == "pier" then return it.x + D.PIER_SEG / 2, 0, D.HOOK_Z_PIER end
    local hx, hy, hz = tilt(D.ARM_FWD, -D.BUOY_BACK, D.HOOK_Z_BUOY, it.p.pitch or D.BUOY_TILT[2])
    local ox, oy, oz = C.origin(it, t)
    return ox + hx, oy + hy, oz + hz
end
function C.has_hook(it)
    if it.kind == "pier" then return true end
    return (it.kind == "buoy_red" or it.kind == "buoy_white") and (it.p.y == nil) and (it.p.scale == nil)
end

------------------------------------------------------------------ the course object
local Course = {}
Course.__index = Course

function C.new(seed)
    local c = setmetatable({ items = {}, n = 0, rnd = lcg(seed or 7) }, Course)
    for _, e in ipairs(D.COURSE) do
        local kind, x, p = e[1], e[2], e[3]
        if kind == "pier" then
            for s = 0, (p.segs or 1) - 1 do c:add("pier", x + s * D.PIER_SEG, {}, p.lit) end
        else
            c:add(kind, x, p, p.lit)
        end
    end
    c.last_no = { buoy_red = 8, buoy_white = 7 }         -- generated buoys carry on after the stretch's numbers
    -- where the generator carries on after the target stretch
    c.next_buoy, c.last_kind = 70, "buoy_red"           -- first generated buoy beyond state B's view (x <= 78)
    c.next_pier = 120
    c.next_boat, c.next_far = 70, 80
    local last_bw = -1e9
    for _, it in ipairs(c.items) do
        if it.kind == "bw" then last_bw = max(last_bw, it.x + D.BW_SEG) end
        if it.kind == "bw_gap" then last_bw = max(last_bw, it.x + D.BW_GAP) end
    end
    c.next_bw, c.bw_count = last_bw, 0
    c.gen_x = 60
    return c
end

-- Buoy numbers: red (port) buoys even, white ones odd, counted along the course per colour and wrapping after
-- PLATE_N, so two buoys of a colour with one number are PLATE_N buoys of that colour apart (never both in view).
function C.next_no(last, kind)
    local first = kind == "buoy_red" and 2 or 1
    if not last then return first end
    local i = ((last - first) / 2 + 1) % D.PLATE_N
    return first + 2 * i
end

function Course:add(kind, x, p, lit)
    self.n = self.n + 1
    local it = { id = self.n, kind = kind, x = x, p = p or {}, lit = lit and true or false }
    if self.plane and (C.has_hook(it) or it.p.inplane) then      -- hooks and hazards, kept sorted by x
        local pl = self.plane
        local i = #pl
        while i > 0 and pl[i].x > x do i = i - 1 end
        table.insert(pl, i + 1, it)
    end
    if kind == "buoy_red" or kind == "buoy_white" then
        self.last_no = self.last_no or {}
        it.no = it.p.no or C.next_no(self.last_no[kind], kind)
        self.last_no[kind] = it.no
    end
    self.items[#self.items + 1] = it
    return it
end

------------------------------------------------------------------ the playable course
-- Seeded sections ahead of the float: open water (a channel buoy), a pier (2-3 lamp hooks 8 apart), moored boats (a
-- trawler lying with its hull side in the play plane) and the harbour mouth (a breakwater head beside the plane, a
-- buoy in the gap). Difficulty steps every LEVEL_LEN: wider hook spacing, more hazard sections, fewer (higher) pier
-- hooks. Pieces never overlap along x near the plane (FOOT: how far each reaches either side of its origin).
local RL = D.RULES
local FOOT = { buoy = { -2.2, 0.4 }, boat = { -4.4, 4.4 }, bw_gap = { -0.3, 8.5 }, pier = { 0, D.PIER_SEG + 0.15 } }
C.FOOT = FOOT
function C.level_at(c, x)
    if c.opts.level then return c.opts.level end
    return min(RL.LEVELS - 1, max(0, floor(x / RL.LEVEL_LEN)))
end

function C.new_play(seed, opts)
    local c = setmetatable({ items = {}, plane = {}, n = 0, rnd = lcg(seed or 7), play = true, opts = opts or {} }, Course)
    c.last_no = {}
    local first = c:add("buoy_red", 0, {}, false)
    c.first_hook = first
    c.last_hook, c.foot = 0, FOOT.buoy[2]
    c.next_boat, c.next_far = -30, -20
    c.next_bw, c.bw_count = -60, 0
    c.gen_x = -40
    return c
end

-- One section after the last hook. Returns nothing; advances last_hook / foot.
function Course:section()
    local r = self.rnd
    local lv = C.level_at(self, self.last_hook) + 1
    local sp = RL.LEVEL.spacing[lv]
    local roll = r()
    -- a calm start, and never two hazards in a row (the float needs a hook between them to gather speed)
    if self.last_hook < 40 or self.prev_hazard then roll = 1 end
    -- the guided first run (opts.gentle units): close buoys only, no hazards and no piers
    if self.opts.gentle and self.last_hook < self.opts.gentle then
        self.prev_hazard = false
        local hx = max(self.last_hook + r(6.5, 7.0), self.foot + 0.2 - FOOT.buoy[1])
        self:add(r() < 0.5 and "buoy_red" or "buoy_white", hx, {}, false)
        self.last_hook, self.foot = hx, hx + FOOT.buoy[2]
        return
    end
    self.prev_hazard = roll < RL.LEVEL.hazard[lv]
    local function buoy_at(hx)
        hx = max(hx, self.foot + 0.2 - FOOT.buoy[1])
        self:add(r() < 0.5 and "buoy_red" or "buoy_white", hx, {}, false)
        self.last_hook, self.foot = hx, hx + FOOT.buoy[2]
    end
    if roll < RL.LEVEL.hazard[lv] then
        -- a hook's swing arc (longest chain, hook bobbed up) passes below the hazard's top within CL along x
        local function clear(b)
            local dz = D.HOOK_Z_BUOY + 0.55 - (b[4] + 0.45) - D.FLOAT_R
            return math.sqrt(max(0, D.CHAIN_MAX * D.CHAIN_MAX - dz * dz)) + RL.HOOK_CLEAR
        end
        local CL
        if r() < 0.5 then      -- moored boat: hull side in the plane, bow either way; hooks clear of the hull
            local yaw = r() < 0.5 and 0 or 180
            -- the run-up: hook to hook over the hull is 12.7-14.3, more than a dead hang can fly; a buoy BOAT_RUNUP
            -- after the last hook, hooked from far, reels the chain in and gives the swing enough to clear it
            buoy_at(self.last_hook + RL.BOAT_RUNUP)
            local b = D.HIT[yaw == 180 and "boat_180" or "boat_0"].box
            CL = clear(b)
            local bx = max(self.foot + 0.2 - FOOT.boat[1], self.last_hook + CL - b[1])
            self:add("boat", bx, { y = RL.BOAT_IN_Y, yaw = yaw, roll = 0, inplane = true }, false)
            self.foot = max(bx + FOOT.boat[2], bx + b[2] + CL - 0.2 + FOOT.buoy[1])
            buoy_at(self.foot + 0.2 - FOOT.buoy[1])
        else                   -- harbour mouth: breakwater head beside the plane, a buoy in the gap beyond its rocks
            local b = D.HIT.bw_gap.box
            CL = clear(b)
            local gx = max(self.foot + 0.2 - FOOT.bw_gap[1], self.last_hook + CL - b[1])
            self:add("bw_gap", gx, { y = RL.GAP_IN_Y, inplane = true }, false)
            self.foot = gx + 1.4                                   -- the gap's water: gx + 1.6 .. gx + 7.0
            buoy_at(max(gx + b[2] + CL, gx + 4.6))
            self.foot = gx + FOOT.bw_gap[2]
        end
    elseif r() < RL.LEVEL.pier[lv] then
        local segs = r() < 0.5 and 2 or 3
        local hx = max(self.last_hook + r(sp[1], sp[2]), self.foot + 0.2 + D.PIER_SEG / 2)
        for k = 0, segs - 1 do self:add("pier", hx - D.PIER_SEG / 2 + k * D.PIER_SEG, {}, false) end
        self.last_hook = hx + (segs - 1) * D.PIER_SEG
        self.foot = hx - D.PIER_SEG / 2 + (segs - 1) * D.PIER_SEG + FOOT.pier[2]
    else
        buoy_at(self.last_hook + r(sp[1], sp[2]))
    end
end

-- Generate items up to x = xmax.
function Course:extend(xmax)
    if self.play then return self:extend_play(xmax) end
    local r = self.rnd
    while self.gen_x < xmax do
        local x1 = self.gen_x + 10
        while self.next_buoy + D.SPACING[2] < x1 do
            local x = self.next_buoy + r(D.SPACING[1], D.SPACING[2])
            if x >= self.next_pier then
                local segs = r() < 0.5 and 2 or 3
                for s = 0, segs - 1 do self:add("pier", x + s * D.PIER_SEG, {}, false) end
                x = x + segs * D.PIER_SEG - D.PIER_SEG / 2
                self.next_pier = x + r(110, 170)
            else
                local kind = r() < 0.5 and "buoy_red" or "buoy_white"
                self:add(kind, x, {}, false)
            end
            self.next_buoy = x
        end
        while self.next_boat < x1 do
            self:add("boat", self.next_boat, { y = r(8.5, 13), yaw = r() < 0.5 and r(-14, 14) or r(160, 190), roll = r(-3, 3) }, false)
            self.next_boat = self.next_boat + r(24, 42)
        end
        while self.next_far < x1 do
            local kind = r() < 0.5 and "buoy_red" or "buoy_white"
            self:add(kind, self.next_far, { y = r(13, 16), scale = 0.9 }, true)
            self.next_far = self.next_far + r(26, 46)
        end
        while self.next_bw < x1 + 40 do
            self.bw_count = self.bw_count + 1
            if self.bw_count % 13 == 0 then
                self:add("bw_gap", self.next_bw, {}, false)
                self.next_bw = self.next_bw + D.BW_GAP
            else
                self:add("bw", self.next_bw, {}, false)
                self.next_bw = self.next_bw + D.BW_SEG
            end
        end
        self.gen_x = x1
    end
end

function Course:extend_play(xmax)
    local r = self.rnd
    while self.gen_x < xmax do
        local x1 = self.gen_x + 10
        while self.last_hook < x1 + 20 do self:section() end
        while self.next_boat < x1 do          -- scenery: boats moored out in the harbour
            self:add("boat", self.next_boat, { y = r(8.5, 13), yaw = r() < 0.5 and r(-14, 14) or r(160, 190), roll = r(-3, 3) }, false)
            self.next_boat = self.next_boat + r(24, 42)
        end
        while self.next_far < x1 do
            local kind = r() < 0.5 and "buoy_red" or "buoy_white"
            self:add(kind, self.next_far, { y = r(13, 16), scale = 0.9 }, true)
            self.next_far = self.next_far + r(26, 46)
        end
        while self.next_bw < x1 + 40 do
            self.bw_count = self.bw_count + 1
            if self.bw_count % 13 == 0 then
                self:add("bw_gap", self.next_bw, {}, false)
                self.next_bw = self.next_bw + D.BW_GAP
            else
                self:add("bw", self.next_bw, {}, false)
                self.next_bw = self.next_bw + D.BW_SEG
            end
        end
        self.gen_x = x1
    end
end

-- Forget items that ended long before x (the camera never goes back).
function Course:prune(xmin)
    local keep = {}
    for _, it in ipairs(self.items) do
        if it.x > xmin then keep[#keep + 1] = it end
    end
    self.items = keep
    if self.plane then
        local pk = {}
        for _, it in ipairs(self.plane) do if it.x > xmin then pk[#pk + 1] = it end end
        self.plane = pk
    end
end

-- First index in the x-sorted plane list with x >= x0.
function Course:plane_from(x0)
    local pl = self.plane
    local lo, hi = 1, #pl + 1
    while lo < hi do
        local mid = floor((lo + hi) / 2)
        if pl[mid].x < x0 then lo = mid + 1 else hi = mid end
    end
    return lo
end

-- Hook-bearing items sorted by hook x.
function Course:hooks()
    local out = {}
    for _, it in ipairs(self.items) do
        if C.has_hook(it) then out[#out + 1] = it end
    end
    table.sort(out, function(a, b) return C.hook(a, 0) < C.hook(b, 0) end)
    return out
end

-- The hook item of a reference state, and the float there.
function C.state(course, name)
    local st = D.STATES[name]
    local kind, x = st.hook[1], st.hook[2]
    local best
    for _, it in ipairs(course.items) do
        if it.kind == kind and C.has_hook(it) and abs(it.x - x) < 1e-6 then best = it end
    end
    assert(best, "state hook not on the course: " .. name)
    local hx, hy, hz = C.hook(best, st.t)
    local th = rad(st.theta)
    return best, { x = hx + st.L * sin(th), y = hy, z = hz - st.L * cos(th) }, { x = hx, y = hy, z = hz }
end

return C
end
