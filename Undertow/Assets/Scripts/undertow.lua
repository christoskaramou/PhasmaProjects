-- Undertow (PhasmaEngine, Lua): hold to hook the glass float's chain onto the lamp ahead, swing, let go to fly, skim the
-- storm water; boats, rocks and the pier shatter the glass. undertow_game.lua runs the game (cards, HUD, input, saves,
-- sounds); this file wires the modules, the rules run (play / play_frame) and the look/debug console modes.
--   uw_data.lua       numbers generated from tools/uw_common.py (camera, units, swells, course, reference states)
--   uw_sea.lua        the sea's height (same formula as the sea meshes)
--   uw_course.lua     the endless seeded course, bobbing and hook points
--   undertow_world.lua  drawing
--   uw_rules.lua / uw_bot.lua  the rules and the look-ahead bot; undertow_game.lua the game flow
-- Console (execute_lua): undertow.state("A") / undertow.state("B") pose the two target frames exactly;
-- undertow.run(speed) starts the scripted pendulum, undertow.stop() freezes, undertow.info() reports. These take the
-- frame from the game (undertow.game_mode() gives it back). undertow.G is the game (G.start_run, G.force_hold, G.info).
local function module(path)
    local source = assert(fs.read(path), "Missing Undertow module: " .. path)
    return assert(load(source, "@" .. path, "t", _ENV))()
end
local D = module("Scripts/uw_data.lua")
local Sea = module("Scripts/uw_sea.lua")(D)
local Course = module("Scripts/uw_course.lua")(D, Sea)
local World = module("Scripts/undertow_world.lua")(D, Sea, Course)
local Rules = module("Scripts/uw_rules.lua")(D, Sea, Course)
local Bot = module("Scripts/uw_bot.lua")(D, Rules)

local floor, min, max, abs, sin, cos, sqrt = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt
local rad, atan2 = math.rad, math.atan2 or math.atan
local G = 9.81

local S = { mode = "state", t = 0, frozen = true, cx = 0, speed = 8.0, fps = {}, frames = 0 }
local course = Course.new(7)
_G.undertow = { S = S, D = D, W = World, Sea = Sea, Course = Course, Rules = Rules, Bot = Bot, course = function() return course end }

------------------------------------------------------------------ the reference states
local function view_of_state()
    return { t = S.t, dt = S.raw, real_dt = S.real_dt, cx = S.cx, cz = S.cz, float = S.F, hook = S.H, theta = S.theta, L = S.L, skim = S.skim, trail = S.H ~= nil,
        shattered = S.shattered, sunk = S.mode == "play" and S.rs and S.rs.cause == "sink" }
end

local Game
local function manual() if Game then Game.manual = true end end
function _G.undertow.state(name)
    manual()
    local st = assert(D.STATES[name], "no state " .. tostring(name))
    S.mode, S.frozen, S.t = "state", true, st.t
    -- a fresh course: exact lamps (nothing lit by an earlier run) and the start still there after a long scroll
    course = Course.new(7)
    World.reset()
    local it, F, H = Course.state(course, name)
    if st.lit_pier then
        for _, o in ipairs(course.items) do if o.kind == "pier" and abs(o.x - it.x) < 20 then o.lit = true end end
    end
    it.lit = it.lit or it.kind == "pier" and st.lit_pier or it.lit
    S.F, S.H, S.theta, S.L, S.skim = F, H, rad(st.theta), st.L, st.spray
    S.cx = F.x + D.CAM.dx
    S.cz = D.CAM.z
    S.hook_item, S.state_name = it, name
    return string.format("state %s t=%.2f float=(%.3f, %.3f, %.3f) hook=(%.3f, %.3f, %.3f)", name, S.t, F.x, F.y, F.z, H.x, H.y, H.z)
end

------------------------------------------------------------------ the scripted pendulum (look only, no rules)
local P = {}
local function next_hook(after_x)
    local best, bx
    for _, it in ipairs(course.items) do
        if Course.has_hook(it) then
            local hx = Course.hook(it, S.t)
            if hx > after_x + 3 and (not bx or hx < bx) then best, bx = it, hx end
        end
    end
    return best
end
local ATTACH, RELEASE = rad(-42), rad(38)
local function launch()
    -- aim the flight at the next hook's attach point; horizontal speed = S.speed
    local nh = next_hook(P.hx)
    P.next = nh
    local hx, _, hz = Course.hook(nh, S.t)
    local L2 = min(D.CHAIN_MAX, max(D.CHAIN_MIN, 4.0))
    local tx, tz = hx + L2 * sin(ATTACH), hz - L2 * cos(ATTACH)
    local T = max(0.35, (tx - S.F.x) / S.speed)
    P.vx = (tx - S.F.x) / T
    P.vz = (tz - S.F.z + 0.5 * G * T * T) / T
    P.T, P.ft, P.L2 = T, 0, L2
    P.mode = "fly"
end
local function attach(it)
    local hx, hy, hz = Course.hook(it, S.t)
    local dx, dz = S.F.x - hx, S.F.z - hz
    P.hook, P.hx = it, hx
    P.L = min(D.CHAIN_MAX, max(D.CHAIN_MIN, sqrt(dx * dx + dz * dz)))
    P.th = atan2(dx, -dz)
    -- tangential speed from the flight velocity
    local tx, tz = cos(P.th), sin(P.th)
    local vt = (P.vx or S.speed) * tx + (P.vz or 0) * tz
    P.om = max(vt, 4.0) / P.L
    P.mode = "swing"
    it.lit = true                     -- each buoy lamp lights when you hook it
end

function _G.undertow.run(speed)
    manual()
    S.speed = speed or S.speed
    S.mode, S.frozen = "run", false
    if not S.F then _G.undertow.state("A") end
    S.mode, S.frozen = "run", false
    local it = S.hook_item or next_hook(S.F.x - 6)
    P.vx, P.vz = S.speed, 0
    attach(it)
    return "running at " .. S.speed
end
function _G.undertow.stop() S.frozen = true; S.mode = "stopped"; return "stopped" end

local function step_pendulum(dt)
    if P.mode == "swing" then
        local hx, hy, hz = Course.hook(P.hook, S.t)
        P.hx = hx
        local n = 4
        for _ = 1, n do
            local h = dt / n
            P.om = P.om - G / P.L * sin(P.th) * h
            P.th = P.th + P.om * h
        end
        S.F = { x = hx + P.L * sin(P.th), y = hy, z = hz - P.L * cos(P.th) }
        S.H = { x = hx, y = hy, z = hz }
        S.theta, S.L = P.th, P.L
        if P.th >= RELEASE or P.om <= 0 then
            P.vx, P.vz = P.L * P.om * cos(P.th), P.L * P.om * sin(P.th)
            launch()
            S.H = nil
        end
        local under = Sea.height(S.F.x, 0, S.t)
        S.skim = S.F.z - D.FLOAT_R < under + 0.12
    elseif P.mode == "fly" then
        P.ft = P.ft + dt
        P.vz = P.vz - G * dt
        local F = S.F
        S.F = { x = F.x + P.vx * dt, y = 0, z = F.z + P.vz * dt }
        local under = Sea.height(S.F.x, 0, S.t)
        S.skim = S.F.z - D.FLOAT_R < under + 0.12
        if S.F.z - D.FLOAT_R < under then           -- a skip off the water
            S.F.z = under + D.FLOAT_R
            P.vz = abs(P.vz) * 0.55
        end
        if P.ft >= P.T then attach(P.next) end
    end
end

------------------------------------------------------------------ play: the rules drive the float (phase 2: the bot or a console hold)
-- undertow.play(seed) starts a run on a fresh seeded course; undertow.hold = true/false is the input when the bot is
-- off; undertow.pause_on = { skip = true, hook = true, ... } freezes the run on the next such event (screenshots);
-- undertow.resume() carries on.
function _G.undertow.play(seed, use_bot, level, extra)
    local opts = { level = level }                           -- level: a debug start level held for the whole run
    for k, v in pairs(extra or {}) do opts[k] = v end        -- extra.gentle: the guided first run's easy stretch
    local rs = Rules.new(seed or 1, opts)
    S.rs, S.mode, S.frozen, S.paused, S.ended = rs, "play", false, false, nil
    S.bot = (use_bot ~= false) and Bot.new() or nil
    S.ev_seen = 0
    course = rs.course
    World.reset()
    S.t, S.F, S.H = rs.t, { x = rs.x, y = 0, z = rs.z }, { x = rs.hx, y = 0, z = rs.hz }
    S.cx = rs.x + D.CAM.dx
    S.cz = D.CAM.z
    S.end_t = 0
    return string.format("play seed %s bot %s", tostring(seed or 1), tostring(S.bot ~= nil))
end
function _G.undertow.resume() S.paused = false; return "resumed" end
function _G.undertow.bot(on) if on then S.bot = S.bot or Bot.new() else S.bot = nil end; return tostring(S.bot ~= nil) end
function _G.undertow.run_info()
    local rs = S.rs
    if not rs then return "no run" end
    local e = rs.events[#rs.events]
    return string.format("mode %s cause %s what %s x %.2f z %.2f v %.2f %.2f dist %.0f score %s lamps %d clean %d skips %d steps %d paused %s last %s",
        rs.mode, tostring(rs.cause), tostring(rs.what), rs.x, rs.z, rs.vx, rs.vz, rs.dist, tostring(rs.score), rs.lamps, rs.clean, rs.skips,
        rs.steps, tostring(S.paused), e and (e.kind .. "@" .. e.step) or "-")
end

local CAM_RISE_Z = 6.0      -- the float's height above which the play camera rises with it (top edge ~7.6 at CAM.z)
local function play_frame(raw)
    local rs = S.rs
    if rs.mode ~= "dead" and not S.paused then
        local n0 = #rs.events
        local last0 = rs.events[n0]
        Rules.advance(rs, raw, function(st)
            if S.paused then return st.hook ~= nil end     -- (paused mid-frame: hold steady, no new input)
            if S.bot then return Bot.input(S.bot, st) end
            if S.input then return S.input(st) end
            return _G.undertow.hold and true or false
        end)
        -- pause on the first new event of a wanted kind (events keep the last 64)
        if _G.undertow.pause_on then
            local seen = false
            for i = #rs.events, 1, -1 do
                local e = rs.events[i]
                if e == last0 then break end
                if _G.undertow.pause_on[e.kind] then seen = e end
            end
            if seen then S.paused, S.pause_event = true, seen.kind .. "@" .. seen.step end
        end
    end
    S.t = rs.t
    local F = { x = rs.x, y = 0, z = rs.z }
    if rs.mode == "dead" then
        S.end_t = (S.end_t or 0) + raw
        if rs.cause == "sink" then F.z = rs.z - math.min(1.6, S.end_t * 0.9) end    -- the glass goes under
        if not S.ended then
            S.ended = rs.cause
            print(string.format("[Undertow] run over: %s %s at x %.1f, score %s", rs.cause, tostring(rs.what), rs.x, tostring(rs.score)))
        end
    end
    S.F = F
    S.shattered = rs.mode == "dead" and rs.cause ~= "sink"
    if rs.hook then
        S.H = { x = rs.hx, y = 0, z = rs.hz }
        S.theta = atan2(F.x - rs.hx, -(F.z - rs.hz))
        S.L = math.sqrt((F.x - rs.hx) ^ 2 + (F.z - rs.hz) ^ 2)
    else
        S.H = nil
    end
    local recent = false
    for i = #rs.events, math.max(1, #rs.events - 3), -1 do
        local e = rs.events[i]
        if (e.kind == "skip" or e.kind == "skim") and rs.steps - e.step < 36 then recent = true end
    end
    S.skim = rs.mode ~= "dead" and (rs.skimming or recent)
    local want = F.x + D.CAM.dx
    S.cx = S.cx + (want - S.cx) * min(1, raw * D.CAM.follow)
    -- Rise with a high float (live level-5 frames: long releases carried it off the top of the frame; the camera
    -- height was fixed). Below CAM_RISE_Z the camera sits at CAM.z exactly (the target frames' framing).
    local wz = D.CAM.z + max(0, F.z - CAM_RISE_Z)
    local cz0 = S.cz or D.CAM.z
    S.cz = cz0 + (wz - cz0) * min(1, raw * (wz > cz0 and 16 or 4))      -- quick up (keeps a fast climb in frame), slow down
end

_G.undertow.play_frame = play_frame

------------------------------------------------------------------ the loop
World.init()
_G.undertow.state("A")
Game = module("Scripts/undertow_game.lua")(_G.undertow, module("Scripts/Lib/settings_menu.lua"))
_G.undertow.G = Game
function _G.undertow.game_mode() Game.manual = false; Game.to_title(); return "game" end

-- Frame-time window measured inside the game (polling over MCP stalls the frames it lands on).
function _G.undertow.timing_reset() S.timing = { n = 0, sum = 0, max = 0, over = 0 }; return "timing reset" end
function _G.undertow.timing()
    local T = S.timing
    if not T or T.n == 0 then return "no samples" end
    return string.format("frames=%d mean_ms=%.2f max_ms=%.2f over_16.7ms=%d", T.n, T.sum / T.n, T.max, T.over)
end

-- Time series of the live run (recorded in-game every `every` s; read in chunks): t,x,z,hook,score,level,game,rules,
-- dist,lamps,frame_ms; rows joined by "|", the first field is the row count)
function _G.undertow.series_start(every) _G.undertow.series_on = { acc = 0, t = 0, every = every or 0.25, rows = {} }; return "series on" end
function _G.undertow.series_read(from)
    local SR = _G.undertow.series_on
    if not SR then return "" end
    local out = {}
    for i = (from or 1), #SR.rows do out[#out + 1] = SR.rows[i] end
    return #SR.rows .. "|" .. table.concat(out, "|")
end

function _G.undertow.info()
    local pc = World.pool_counts()
    local parts = {}
    for k, v in pairs(pc) do parts[#parts + 1] = k .. "=" .. v.used .. "/" .. v.size end
    table.sort(parts)
    local m = engine.get_metrics and engine.get_metrics() or {}
    return string.format("mode=%s t=%.2f cx=%.1f items=%d nodes_created=%d starved=%d links=%d lights=%d halos=%d dt=%.2fms | %s",
        S.mode, S.t, S.cx, #course.items, World.created, World.starved or 0, World.links_used or 0, World.lights_used or 0,
        World.halo_used or 0, m.delta_ms or -1, table.concat(parts, " "))
end

script.on_update("undertow", function()
    local dms = engine.get_metrics().delta_ms
    local raw = max(0, min(0.05, dms / 1000))
    S.raw = raw
    S.real_dt = max(1e-4, dms / 1000)       -- the engine's own frame time (particles move by it; the game clamps to 50 ms)
    S.frames = S.frames + 1
    local T = S.timing
    if T then T.n = T.n + 1; T.sum = T.sum + dms; T.max = max(T.max, dms); if dms > 16.7 then T.over = T.over + 1 end end
    local SR = _G.undertow.series_on
    if SR and S.rs then
        SR.acc = SR.acc + raw
        if SR.acc >= SR.every then
            SR.acc = 0
            local rs = S.rs
            local lv = Course.level_at(rs.course, rs.x)
            SR.rows[#SR.rows + 1] = string.format("%.2f,%.2f,%.2f,%s,%s,%d,%s,%s,%.0f,%d,%.2f", SR.t, rs.x, rs.z,
                rs.hook and tostring(rs.hook.id) or "-", tostring(rs.score), lv, Game.mode, rs.mode, rs.dist, rs.lamps, dms)
        end
        SR.t = SR.t + raw
    end
    if not Game.manual then
        Game.update(raw)
    elseif S.mode == "play" and S.rs then
        play_frame(raw)
    elseif not S.frozen then
        S.t = S.t + raw
        if S.mode == "run" then
            step_pendulum(raw)
            local want = S.F.x + D.CAM.dx
            S.cx = S.cx + (want - S.cx) * min(1, raw * D.CAM.follow)
        end
    end
    if Game.manual then Game.update(raw) end      -- (hides the cards)
    if Game.manual and S.mode == "state" and S.hook_item then
        -- a held state hangs from its hook as the buoy bobs (at the state's own time this is the exact target pose)
        local st = D.STATES[S.state_name]
        local hx, hy, hz = Course.hook(S.hook_item, S.t)
        S.H = { x = hx, y = hy, z = hz }
        S.F = { x = hx + st.L * sin(S.theta), y = hy, z = hz - st.L * cos(S.theta) }
    end
    course:extend(S.cx + 220)
    course:prune(S.cx - 140)
    if not _G.undertow.no_draw then World.frame(course, view_of_state()) end     -- no_draw: timing A/B only
end, "play")

print("[Undertow] Ready. Hold Space or the left mouse button to hook and swing, let go to fly. Esc pause, M mute.")
