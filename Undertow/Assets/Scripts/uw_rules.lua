-- Undertow rules: pure Lua (no engine calls), fixed 120 Hz step, so a run depends only on the seed and the input.
-- The glass float (radius FLOAT_R) moves in the play plane (x along the harbour, z up; y = 0). One input, hold:
--   held while flying       the chain hooks the nearest hook ahead within REACH (chain length = that distance,
--                           clamped to CHAIN_MIN..CHAIN_MAX; longer chains reel in at REEL, which pumps the swing)
--   held while hooked       the float swings as a pendulum (gravity; rigid while the chain is taut, free while slack)
--   released                the float flies ballistically with the velocity it had
-- Water (the shared sea_height): free, a shallow, fast touch skips and anything else sinks; hooked, the float floats:
-- it skims, and the water lifts it over crests (the chain only pulls).
-- Hazards: buoy arms and fenders, moored boats, the breakwater head and pier arms, from hit grids cut out of the meshes
-- the game draws (tools/uw_hits.py). The chain tangling in a hazard also breaks the run.
-- Score = distance + LAMP_PTS per lamp lit (each hook) + CLEAN_PTS per clean release (next hook without touching water).
return function(D, Sea, Course)
local R = {}
local RL = D.RULES
local sin, cos, sqrt, abs, min, max, floor, atan2, deg, rad =
    math.sin, math.cos, math.sqrt, math.abs, math.min, math.max, math.floor, math.atan2 or math.atan, math.deg, math.rad
local G, DT, FR = RL.G, RL.DT, D.FLOAT_R
local PI = math.pi
R.DT = DT
R.has_hook = Course.has_hook
-- Swinging fast enough to go over the top of its hook (it then loops; om keeps one sign)?
function R.looping(s)
    return s.hook and not s.slack and G * s.L * (1 - cos(s.th)) + 0.5 * (s.L * s.om) ^ 2 > 2 * G * s.L
end

------------------------------------------------------------------ hit grids
local CELL = RL.HIT_CELL
local HIT = {}
for kind, g in pairs(D.HIT) do
    local cells = {}
    local c = g.cells
    for i = 1, #c, 3 do cells[(c[i] + 4096) * 8192 + (c[i + 1] + 4096)] = c[i + 2] / 1000 end
    HIT[kind] = { cells = cells, box = g.box, probes = g.probes }
end
R.HIT = HIT

-- The grid a course item uses in the play plane, or nil (scenery, far markers, the breakwater line).
function R.grid_of(it)
    local k, p = it.kind, it.p
    if k == "buoy_red" or k == "buoy_white" then
        if p.y == nil and p.scale == nil then return k end
    elseif k == "pier" then
        return "pier"
    elseif k == "boat" and p.inplane then
        return (p.yaw or 0) == 180 and "boat_180" or "boat_0"
    elseif k == "bw_gap" and p.inplane then
        return "bw_gap"
    end
end

-- Point (x, z) in the grid frame of a placed item at sea time t: origin removed, the buoy's tilt undone.
function R.local_point(it, x, z, t)
    local ox, _, oz = Course.origin(it, t)
    local lx, lz = x - ox, z - oz
    if it.kind == "buoy_red" or it.kind == "buoy_white" then
        local pitch = it.p.pitch or D.BUOY_TILT[2]
        local c, s = cos(rad(-pitch)), sin(rad(-pitch))
        lx, lz = lx * c + lz * s, -lx * s + lz * c
    end
    return lx, lz
end

-- Does a ball of radius r at (x, z) touch the item's geometry? (cells keep the smallest |y| of the mesh in them)
local function touches(g, lx, lz, r)
    local b = g.box
    if lx < b[1] - r or lx > b[2] + r or lz < b[3] - r or lz > b[4] + r then return false end
    local cells = g.cells
    local i0, i1 = floor((lx - r) / CELL), floor((lx + r) / CELL)
    local k0, k1 = floor((lz - r) / CELL), floor((lz + r) / CELL)
    local r2 = r * r
    for i = i0, i1 do
        local cx = (i + 0.5) * CELL - lx
        local base = (i + 4096) * 8192 + 4096
        for k = k0, k1 do
            local y = cells[base + k]
            if y then
                local cz = (k + 0.5) * CELL - lz
                if cx * cx + cz * cz < r2 - y * y then return true end
            end
        end
    end
    return false
end
R.touches = touches

-- First hazard item touched by a ball of radius r at (x, z), time t.
function R.hit_at(course, x, z, t, r)
    r = r or FR
    local pl = course.plane
    for i = course:plane_from(x - 14), #pl do
        local it = pl[i]
        if it.x > x + 14 then break end
        local gk = R.grid_of(it)
        if gk then
            local b = HIT[gk].box
            local ox = (it.kind == "buoy_red" or it.kind == "buoy_white") and it.x - D.ARM_FWD or it.x
            if x > ox + b[1] - r - 0.4 and x < ox + b[2] + r + 0.4 then   -- tilt and bob stay within 0.4
                local lx, lz = R.local_point(it, x, z, t)
                if touches(HIT[gk], lx, lz, r) then return it end
            end
        end
    end
end

------------------------------------------------------------------ state
local function level_at(s, x) return Course.level_at(s.course, x) end

function R.new(seed, opts)
    opts = opts or {}
    local course = Course.new_play(seed, opts)
    course:extend(140)
    local s = { course = course, seed = seed, t = 0, clock = 0, steps = 0, acc = 0, mode = "swing",
        lamps = 0, clean = 0, skips = 0, dist = 0, lit = {}, events = {}, touched = false, pending_clean = false }
    local it = course.first_hook
    local hx, _, hz = Course.hook(it, 0)
    s.hook, s.L, s.Lt = it, RL.START.L, RL.START.L
    s.th, s.om, s.slack = rad(RL.START.theta), 0, false
    s.hx, s.hz, s.hvx, s.hvz = hx, hz, 0, 0
    s.x, s.z = hx + s.L * sin(s.th), hz - s.L * cos(s.th)
    s.vx, s.vz = 0, 0
    s.x0 = s.x
    s.last_x = it.x
    s.lit[it.id] = true
    it.lit = true
    s.lamps = 1
    return s
end

local function event(s, kind, extra)
    s.nev = (s.nev or 0) + 1                   -- running event number (the view plays each event's sound once)
    local e = { kind = kind, step = s.steps, x = s.x, z = s.z, n = s.nev }
    if extra then for k, v in pairs(extra) do e[k] = v end end
    s.events[#s.events + 1] = e
    if #s.events > 64 then table.remove(s.events, 1) end
end

local function die(s, cause, what)
    s.mode, s.cause, s.what = "dead", cause, what
    s.hook = nil
    event(s, cause, { what = what })
end

------------------------------------------------------------------ hooking
-- Nearest hook ahead of the float (hook x > float x) and beyond the last hook used, within REACH.
function R.find_hook(s)
    local best, bd
    local pl = s.course.plane
    for i = s.course:plane_from(s.x - 2), #pl do
        local it = pl[i]
        if it.x > s.x + D.REACH + 6 then break end
        if Course.has_hook(it) then
            local hx, _, hz = Course.hook(it, s.t)
            if hx > s.x and it.x > s.last_x then
                local dx, dz = hx - s.x, hz - s.z
                local d = sqrt(dx * dx + dz * dz)
                if d <= D.REACH and (not bd or d < bd) then best, bd = it, d end
            end
        end
    end
    return best, bd
end

-- Float velocity relative to the hook -> pendulum angle / rate; radial motion away from the hook is taken out
-- (the chain snaps taut), motion toward it leaves the chain slack.
local function to_pendulum(s)
    local dx, dz = s.x - s.hx, s.z - s.hz
    local d = sqrt(dx * dx + dz * dz)
    local ux, uz = dx / d, dz / d
    local rvx, rvz = s.vx - s.hvx, s.vz - s.hvz
    local vr = rvx * ux + rvz * uz
    s.th = atan2(dx, -dz)
    s.om = (rvx * -uz + rvz * ux) / s.L      -- tangent (cos th, sin th) = (-uz, ux)
    if vr > 0 then
        s.vx, s.vz = s.vx - vr * ux, s.vz - vr * uz
    end
end

local function attach(s, it, d)
    local hx, _, hz = Course.hook(it, s.t)
    local hx1, _, hz1 = Course.hook(it, s.t + 1e-3)
    s.hook, s.hx, s.hz = it, hx, hz
    s.last_x = it.x
    s.hvx, s.hvz = (hx1 - hx) / 1e-3, (hz1 - hz) / 1e-3
    s.Lt = min(D.CHAIN_MAX, max(D.CHAIN_MIN, d))
    s.L = max(d, D.CHAIN_MIN)
    s.slack = d < s.L
    if not s.slack then
        to_pendulum(s)
        local dx, dz = s.x - hx, s.z - hz
        local rvr = ((s.vx - s.hvx) * dx + (s.vz - s.hvz) * dz) / d
        if rvr < -1e-9 then s.slack = true end
    end
    if not s.lit[it.id] then s.lit[it.id] = true; s.lamps = s.lamps + 1 end
    if not s.ghost then it.lit = true end      -- the bot's planning copies must not light the real lamps
    if s.pending_clean and not s.touched then s.clean = s.clean + 1; event(s, "clean") end
    s.pending_clean = false
    event(s, "hook", { id = it.id, L = s.L })
end

local function release(s)
    s.hook, s.slack = nil, false
    s.pending_clean, s.touched = true, false
    event(s, "release", { vx = s.vx, vz = s.vz })
end

------------------------------------------------------------------ motion
local PUMP_COS = cos(rad(RL.PUMP_THETA))
local function pend_acc(th, om, L, Ld, pump)
    return -(G / L) * sin(th) - 2 * Ld * om / L + pump / L
end

local function swing_step(s, dt)
    local it = s.hook
    local hx, _, hz = Course.hook(it, s.t)
    s.hvx, s.hvz = (hx - s.hx) / dt, (hz - s.hz) / dt
    s.hx, s.hz = hx, hz
    local Ld = s.L > s.Lt and -RL.REEL or 0
    local L0 = s.L
    -- the pump: swing energy (relative to the lowest point) below the PUMP_THETA amplitude's -> a push along the motion
    local e = G * L0 * (1 - cos(s.th)) + 0.5 * (L0 * s.om) ^ 2
    local pump = 0
    if Ld == 0 and e < G * L0 * (1 - PUMP_COS) then pump = (s.om >= 0 and 1 or -1) * RL.PUMP_ACC end
    s.pumping = pump ~= 0
    -- RK4 on (th, om); L changes linearly over the step
    local th, om = s.th, s.om
    local Lm, L1 = L0 + Ld * dt * 0.5, L0 + Ld * dt
    local k1t, k1o = om, pend_acc(th, om, L0, Ld, pump)
    local k2t, k2o = om + 0.5 * dt * k1o, pend_acc(th + 0.5 * dt * k1t, om + 0.5 * dt * k1o, Lm, Ld, pump)
    local k3t, k3o = om + 0.5 * dt * k2o, pend_acc(th + 0.5 * dt * k2t, om + 0.5 * dt * k2o, Lm, Ld, pump)
    local k4t, k4o = om + dt * k3o, pend_acc(th + dt * k3t, om + dt * k3o, L1, Ld, pump)
    s.th = th + dt / 6 * (k1t + 2 * k2t + 2 * k3t + k4t)
    if s.th > PI then s.th = s.th - 2 * PI elseif s.th <= -PI then s.th = s.th + 2 * PI end   -- a fast float loops the hook
    s.om = om + dt / 6 * (k1o + 2 * k2o + 2 * k3o + k4o)
    if Ld ~= 0 and L1 <= s.Lt then L1, Ld = s.Lt, 0 end
    s.L = L1
    local st, ct = sin(s.th), cos(s.th)
    s.x, s.z = hx + s.L * st, hz - s.L * ct
    s.vx = s.hvx + Ld * st + s.L * s.om * ct
    s.vz = s.hvz - Ld * ct + s.L * s.om * st
    -- tension per unit mass; below zero the chain goes slack and the float flies on the slack chain
    if s.L * s.om * s.om + G * ct < 0 then s.slack = true end
end

local function fly_step(s, dt)
    s.x = s.x + s.vx * dt
    s.z = s.z + s.vz * dt - 0.5 * G * dt * dt
    s.vz = s.vz - G * dt
    if s.hook then
        local hx, _, hz = Course.hook(s.hook, s.t)
        s.hvx, s.hvz = (hx - s.hx) / dt, (hz - s.hz) / dt
        s.hx, s.hz = hx, hz
        local dx, dz = s.x - hx, s.z - hz
        local d = sqrt(dx * dx + dz * dz)
        if d >= s.L then            -- the chain snaps taut
            s.x, s.z = hx + dx / d * s.L, hz + dz / d * s.L
            to_pendulum(s)
            s.slack = false
        end
    end
end

------------------------------------------------------------------ water
local function water(s)
    local base = s.z - FR
    if base > RL.AMP + 0.05 then s.skimming = false; return end
    local h = Sea.height(s.x, 0, s.t)
    if base >= h then s.skimming = false; return end
    local e = 0.02
    local sx = (Sea.height(s.x + e, 0, s.t) - Sea.height(s.x - e, 0, s.t)) / (2 * e)
    local ht = (Sea.height(s.x, 0, s.t + e) - Sea.height(s.x, 0, s.t - e)) / (2 * e)
    local nl = sqrt(1 + sx * sx)
    local nx, nz = -sx / nl, 1 / nl            -- surface normal
    local tx, tz = 1 / nl, sx / nl             -- surface tangent (+x)
    local rvx, rvz = s.vx, s.vz - ht           -- velocity relative to the moving surface
    local vn, vt = rvx * nx + rvz * nz, rvx * tx + rvz * tz
    local speed = sqrt(rvx * rvx + rvz * rvz)
    local depth = h - base
    local angle = deg(atan2(-vn, abs(vt)))
    s.touched = true
    if vn >= 0 then                            -- already leaving the surface
        if s.hook then
            if depth > RL.RIDE_DEPTH then s.z, s.slack = h + FR - RL.RIDE_DEPTH, true end
        elseif depth > FR * 2 then
            die(s, "sink")
        end
        return
    end
    local shallow = angle <= RL.SKIP_ANGLE and speed >= RL.SKIP_SPEED
    if s.hook then
        -- hooked: a glass float floats. A taut chain drags it over crests at any angle (a swell's slope made fast swings
        -- "steep" and sank them); the chain only pulls, so deeper than RIDE_DEPTH the water lifts the float, the chain
        -- goes slack and it rides the surface until the chain is taut again. On the chain the water never sinks it
        -- (the old rigid, slow and steep-while-slack sinks killed 4.1-chain holds: scratch/diag/hang2.lua); letting go
        -- is the risk.
        if not s.skimming then event(s, "skim") end
        s.skimming = true
        if not s.slack and depth <= RL.RIDE_DEPTH then
            s.om = s.om * (1 - RL.SKIM_DRAG * DT)
            return
        end
        if depth > RL.RIDE_DEPTH then s.z = h + FR - RL.RIDE_DEPTH end
        local k = 1 - RL.SKIM_DRAG * DT
        rvx, rvz = (rvx - vn * nx) * k, (rvz - vn * nz) * k      -- slide along the surface (vn < 0 here)
        s.vx, s.vz = rvx, rvz + ht
        s.slack = true
        return
    end
    if shallow then
        local nvt, nvn = vt * RL.SKIP_KEEP, -vn * RL.SKIP_BOUNCE
        s.vx = nvt * tx + nvn * nx
        s.vz = nvt * tz + nvn * nz + ht
        s.z = h + FR
        s.skips = s.skips + 1
        event(s, "skip", { angle = angle, speed = speed })
    else
        die(s, "sink", string.format("%.0f deg %.1f u/s", angle, speed))
    end
end

------------------------------------------------------------------ hazards
local CHAIN_R = 0.05
local function hazards(s)
    local it = R.hit_at(s.course, s.x, s.z, s.t, FR)
    if it then return die(s, "hit", it.kind) end
    if s.hook and s.steps % 4 == 0 then          -- the chain tangling in rigging or an arm
        local dx, dz = s.hx - s.x, s.hz - s.z
        local d = sqrt(dx * dx + dz * dz)
        local n = floor((d - FR - 0.3) / 0.1)
        for i = 1, n do
            local u = (FR + i * 0.1) / d
            local c = R.hit_at(s.course, s.x + dx * u, s.z + dz * u, s.t, CHAIN_R)
            if c and c ~= s.hook then return die(s, "tangle", c.kind) end
        end
    end
end

------------------------------------------------------------------ one fixed step
function R.step(s, hold)
    if s.mode == "dead" then return end
    s.steps = s.steps + 1
    local lv = level_at(s, s.x) + 1
    s.t = s.t + DT * RL.LEVEL.sea_rate[lv]
    s.clock = s.clock + DT
    if s.course.gen_x < s.x + 120 then s.course:extend(s.x + 140) end
    if hold and not s.hook then
        local it, d = R.find_hook(s)
        if it then attach(s, it, d) end
    elseif not hold and s.hook then
        release(s)
    end
    if s.hook and not s.slack then swing_step(s, DT) else fly_step(s, DT) end
    s.mode = s.hook and "swing" or "fly"
    water(s)
    if s.mode ~= "dead" then hazards(s) end
    s.dist = max(s.dist, s.x - s.x0)
    s.score = floor(s.dist) + RL.LAMP_PTS * s.lamps + RL.CLEAN_PTS * s.clean
end

-- Advance by a frame of length dt: as many fixed steps as fit; input(s) gives hold for each step.
function R.advance(s, dt, input)
    s.acc = s.acc + dt
    local n = 0
    while s.acc >= DT - 1e-9 and s.mode ~= "dead" do
        s.acc = s.acc - DT
        local hold = input
        if type(input) == "function" then hold = input(s) end
        R.step(s, hold)
        n = n + 1
    end
    if s.mode == "dead" then s.acc = 0 end
    return n
end

------------------------------------------------------------------ clone (the bot plans on copies)
function R.clone(s)
    local c = {}
    for k, v in pairs(s) do c[k] = v end
    c.events = {}
    c.lit = setmetatable({}, { __index = s.lit })
    c.ghost = true
    return c
end

return R
end
