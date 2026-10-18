------------------------------------------------------------------ car + traffic simulation (fixed 60 Hz)
local FR = 1 / 60
local SEGL, HALF, RUMB = G.TC.SEG, G.TC.HALF, G.TC.RUMB
local VMAX_L, VMAX_H = 190 / 3.6, 293 / 3.6
local CAR_HW, CAR_HL = 0.98, 2.25          -- Testarossa half width / half length (m)
G.CONST = { VMAX_L = VMAX_L, VMAX_H = VMAX_H, CAR_HW = CAR_HW, CAR_HL = CAR_HL }
local P = { s = 20, x = 0, v = 0, gear = "L", steer = 0, st = "drive", t = 0, yawv = 0, row = 1, col = 1 }
G.P = P
local CARS = {}
G.CARS = CARS
local OBJ_HW = { palm = 0.7, bush = 1.2, rock = 2.0, cliff = 7.5, pine = 1.0, pine_s = 1.0, cactus = 0.7, bld = 6.5, windmill = 2.2,
    column = 0.9, vine = 0.5, lamp = 0.3, fence = 0.2, sign_l = 1.5, sign_r = 1.5 }
G.OBJ_HW = OBJ_HW
local function seg_at(s) return SG[floor(s / SEGL) + 1] end
G.seg_at = seg_at
local function fork_raw(s) local a = seg_at(s); return (a and a.fork) or 0 end
-- branch offset interpolated inside the segment, exactly as frame() interpolates the shifted centre line
local function fork_at(s)
    local gf = s / SEGL; local g = floor(gf) + 1; local a, b = SG[g], SG[g + 1]
    if not a or not a.fork then return 0 end
    local fb = (b and b.st == a.st and b.fork) or a.fork
    return a.fork + (fb - a.fork) * (gf - floor(gf))
end
G.fork_at = fork_at
-- where the drivable surface is, in frame coordinates (x relative to the current frame)
local function surface(s, x)
    local a = seg_at(s)
    if not a then return "road" end
    local lanes = { 0 }
    if a.fork then
        local d = a.fork
        if a.st.side then lanes = { 0, -2 * a.st.side * d } else lanes = { -d, d } end
    end
    local best = 1e9
    for _, c in ipairs(lanes) do best = min(best, abs(x - c)) end
    if best <= HALF then return "road" elseif best <= HALF + RUMB then return "rumble" end
    return "off"
end
G.surface = surface
local function car_x(c)                     -- traffic lateral position in frame coordinates
    if c.side then return c.side * fork_raw(c.s) + c.lane end
    return c.lane
end
G.car_x = car_x
local LANES = { -6.75, -2.25, 2.25, 6.75 }
local KINDS = { "beetle", "vette", "truck", "beetle", "vette" }
local function spawn_car(s)
    local a = seg_at(s)
    if not a then return end
    local st = a.st
    if st.g1 and not st.side and floor(s / SEGL) + 1 >= st.gend - 1 then return end
    local c = { s = s, lane = LANES[1 + floor(rand() * 4)], v = rr(16, 31), k = KINDS[1 + floor(rand() * #KINDS)] }
    if c.k == "truck" then c.v = rr(15, 22) end
    if a.fork and not st.side and floor(s / SEGL) + 1 >= st.g1 then c.side = rand() < 0.5 and -1 or 1 end
    for _, o in ipairs(CARS) do if abs(o.s - c.s) < 14 and abs(car_x(o) - car_x(c)) < 3 then return end end
    CARS[#CARS + 1] = c
end
local function traffic_step(dt)
    local st = seg_at(P.s).st
    local want = floor(9 * st.th.traffic)
    if #CARS < want then spawn_car(P.s + 330 + rand() * 260) end
    for i = #CARS, 1, -1 do
        local c = CARS[i]
        c.s = c.s + c.v * dt
        local a = seg_at(c.s)
        if c.s < P.s - 60 or c.s > P.s + 900 or not a or (a.fork and a.st.side and c.side and c.side ~= a.st.side) then table.remove(CARS, i) end
    end
end

------------------------------------------------------------------ stage progress: forks, checkpoints, goal
-- Fork choice. It used to be decided silently by the sign of P.x at one segment, and the commit moved P.x into the
-- chosen branch's frame without moving P.ox (the previous step's x the renderer interpolates from), so for the rest
-- of that step the car and camera were drawn up to ~21 m sideways and snapped back: the view swapped back and forth.
-- Now: a tentative pick with hysteresis (the car must cross 2.5 m past the centre line to change it), shown on the
-- HUD; the pick locks as soon as the roads have separated and the car is fully on one of them (or at the latest at
-- segment COMMIT of the fork), and the frame change moves P.x and P.ox together by the exact interpolated offset.
local PICK_BAND = 2.5
local function commit_fork(st)
    local side = st.pick or ((P.x >= 0) and 1 or -1)
    st.side = side
    local d = side * fork_at(P.s)
    P.x = P.x - d
    if P.ox then P.ox = P.ox - d end
    G.fork_lock = { name = G.ROUTE[st.row + 1][st.col + (side > 0 and 1 or 0)][1], side = side, t = 2.2 }
    sfx("check")
    for i = #CARS, 1, -1 do
        local c = CARS[i]
        local a = seg_at(c.s)
        if c.side then
            if c.side ~= side then table.remove(CARS, i) else c.side = nil end
        end
    end
    local tail = SG[st.gend]
    local rx, rz = right_of(tail.yaw)
    local base = { tail.x + rx * side * G.TC.FORK_D, tail.y, tail.z + rz * side * G.TC.FORK_D, tail.yaw }
    local ncol = st.col + (side > 0 and 1 or 0)
    append_stage(st.row + 1, ncol, base, st.gend)
    if G.invalidate_slots then G.invalidate_slots() end
end
local function progress()
    local g = floor(P.s / SEGL) + 1
    local a = SG[g]
    if not a then return end
    local st = a.st
    if st ~= G.cur_stage then
        G.cur_stage = st
        set_theme(st.th)
        if st.row > 1 then
            G.time = G.time + G.EXTEND[st.row]
            G.laps[#G.laps + 1] = G.lap_t; G.lap_t = 0
            G.banner = { text = "Extended Play!", t = 2.6 }
            sfx("check")
        end
        P.row, P.col = st.row, st.col
    end
    if st.g1 and not st.side and g >= st.g1 - 30 then
        if P.x > PICK_BAND then st.pick = 1 elseif P.x < -PICK_BAND then st.pick = -1 end
        if g >= st.g1 then
            local f = fork_at(P.s)
            local on = st.pick and abs(P.x - st.pick * f) <= HALF - CAR_HW
            if (f >= HALF + RUMB + 1 and on) or g >= st.g1 + G.TC.COMMIT then commit_fork(st) end
        end
    end
    if st.last and g >= st.g0 + G.TC.STAGE_LEN and P.st ~= "goal" then
        P.st = "goal"; P.t = 0
        G.laps[#G.laps + 1] = G.lap_t
        G.goal = G.GOALS[st.col]
        G.bonus = floor(max(0, G.time)) * 250000
        music(nil); sfx("goal")
    end
end

------------------------------------------------------------------ collisions
local function crash(kind)
    if G.god then P.v = P.v * 0.5; return end
    if P.st == "timeup" then P.v = 0; G.shake = max(G.shake, 0.4); sfx("bump"); return end   -- out of time: just stop dead
    P.st = "crash"; P.t = 0; P.crash_v = P.v
    sfx("crash"); G.shake = 0.9
    local p, yaw = world_at(P.s, P.x, 0.6)
    G.crash_fx(p, yaw, P.crash_v)
end
local function hit_objects()
    local g = floor(P.s / SEGL) + 1
    local a = SG[g]
    if not a then return end
    local rawx = P.x + ((a.fork and a.st.side) and a.st.side * fork_at(P.s) or 0)
    local list = { a.st }
    if STAGES[#STAGES] ~= a.st then list[2] = STAGES[#STAGES] end
    for _, st in ipairs(list) do
        for _, o in ipairs(st.objs) do
            if o.g > g + 2 then break end
            if abs(o.g - g) <= 1 and abs((o.g - 1) * SEGL - P.s) < CAR_HL + 1.0 then
                if o.arch then
                    for _, px in ipairs({ -12.5, 12.5 }) do
                        if abs(rawx - px) < 0.7 + CAR_HW then
                            if P.v > 70 / 3.6 then crash("arch"); return else P.v = 0; P.x = P.x - (px > rawx and 0.6 or -0.6) end
                        end
                    end
                else
                    local hw = OBJ_HW[o.k] or 1
                    if abs(rawx - o.x) < hw + CAR_HW then
                        if P.v > 70 / 3.6 then crash(o.k); return
                        else P.v = 0; P.x = P.x + ((rawx > o.x) and 0.6 or -0.6); sfx("bump") end
                    end
                end
            end
        end
    end
end
local function hit_traffic()
    for _, c in ipairs(CARS) do
        local ds = c.s - P.s
        local hl = (c.k == "truck") and 3.4 or 2.1
        if abs(ds) < hl + CAR_HL then
            local dx = car_x(c) - P.x
            local hw = (c.k == "truck") and 1.2 or 0.9
            if abs(dx) < hw + CAR_HW then
                local dv = P.v - c.v
                if dv > 22 and not G.god and P.st ~= "timeup" then
                    P.st = "spin"; P.t = 0; sfx("skid"); sfx("bump"); G.shake = 0.6
                else sfx("bump"); G.shake = max(G.shake, 0.3) end
                P.v = min(P.v, c.v * 0.8)
                P.s = c.s - (hl + CAR_HL) * (ds > 0 and 1 or -1)
                P.x = P.x - (dx > 0 and 0.5 or -0.5)
                c.v = c.v + 3
                return
            end
        end
    end
end

------------------------------------------------------------------ step
local function accel(v, gear)
    if gear == "L" then return 9.5 * max(0, 1 - v / VMAX_L) ^ 0.6 end
    local bog = clamp((v - 8) / 22, 0.22, 1)
    return 8.0 * max(0, 1 - (v / VMAX_H) ^ 2) * bog
end
G.accel = accel
local function car_step(inp, dt)
    P.t = P.t + dt
    if inp.shift and (P.st == "drive" or P.st == "spin") then P.gear = (P.gear == "L") and "H" or "L"; sfx("shift"); P.pop = true end
    local a = seg_at(P.s)
    if P.st == "drive" or P.st == "timeup" then
        local vmax = (P.gear == "L") and VMAX_L or VMAX_H
        local acc = 0
        if inp.gas and P.st == "drive" then acc = accel(P.v, P.gear) else acc = -(1.2 + P.v * 0.025) end
        if inp.brake then acc = -16 end
        -- time up: the driver stands on the brakes and the car pulls up where it is (it used to coast for a minute,
        -- drifting off the road with collisions switched off, so it slid through the scenery)
        if P.st == "timeup" then acc = -(13 + P.v * 0.12) end
        if P.v > vmax then acc = min(acc, -6) end
        local surf = surface(P.s, P.x)
        if surf == "off" then
            if P.v > 120 / 3.6 then acc = min(acc, -14) end
            G.shake = max(G.shake, 0.18 * clamp(P.v / 40, 0, 1))
            if P.v > 3 then G.off_t = (G.off_t or 0) - dt; if G.off_t <= 0 then G.off_t = 0.18; sfx("offroad") end end   -- dust: render_car
        end
        P.v = clamp(P.v + acc * dt, 0, VMAX_H + 2)
        -- steering + centrifugal drift on curves
        local ts = (P.st == "drive") and inp.h or 0
        P.steer = damp(P.steer, ts, 9, dt)
        local vlat = P.steer * min(P.v, 55) * 0.3
        local k = a and math.rad(a.curve) / SEGL or 0
        local drift = k * P.v * P.v * 0.33
        if P.st == "timeup" then drift = drift * 0.5 end
        P.x = P.x + (vlat + drift) * dt
        P.drift, P.brk, P.gas, P.surf = drift, (inp.brake or P.st == "timeup") and P.v > 8, inp.gas and P.st == "drive", surf   -- read by the car FX / body slip
        if abs(drift) > 9 and abs(P.steer) > 0.6 and P.v > 45 then
            G.skid_t = (G.skid_t or 0) - dt
            if G.skid_t <= 0 then G.skid_t = 0.3; sfx("skid") end
            P.skid = true
        else P.skid = false end
        P.s = P.s + P.v * dt
        if P.st == "drive" and P.v > 1 then add_score(floor(P.v * 3.6 * dt * 250 * ((surf == "off") and 0.3 or 1))) end
    else P.drift, P.brk, P.gas = 0, false, false end
    if P.st == "spin" then
        P.v = max(0, P.v - 18 * dt); P.s = P.s + P.v * dt
        if P.t > 1.4 then P.st = "drive" end
    elseif P.st == "crash" then
        local v = P.crash_v * max(0, 1 - P.t / 0.9)
        P.s = P.s + v * dt; P.v = 0
        if P.t > 3.2 then
            P.st = "drive"; P.t = 0; P.v = 0; P.gear = "L"
            local aa = seg_at(P.s)
            P.x = (aa and aa.fork and not aa.st.side) and ((aa.st.pick or ((P.x >= 0) and 1 or -1)) * aa.fork) or 0
        end
    elseif P.st == "goal" then
        P.v = max(0, P.v - 9 * dt); P.s = P.s + P.v * dt; P.steer = damp(P.steer, 0, 4, dt)
        P.x = damp(P.x, 0, 1.5, dt)
    end
    P.x = clamp(P.x, -140, 140)
end
local function stage_step(inp, dt)
    if P.st == "drive" or P.st == "spin" or P.st == "crash" then
        G.time = G.time - dt; G.lap_t = G.lap_t + dt
        if G.time <= 10 and floor(G.time + dt) ~= floor(G.time) and G.time > 0 then sfx("warn") end
        if G.time <= 0 then G.time = 0; P.st = "timeup"; P.t = 0; music(nil); sfx("timeup") end
    end
    car_step(inp, dt)
    traffic_step(dt)
    if P.st == "drive" or (P.st == "timeup" and P.v > 0) then hit_traffic(); hit_objects() end
    progress()
end
G.stage_step = stage_step
local function race_reset()
    if G.clear_scenery then G.clear_scenery() end
    reset_route()
    if G.invalidate_slots then G.invalidate_slots() end
    for i = #CARS, 1, -1 do CARS[i] = nil end
    P.s, P.x, P.v, P.gear, P.steer, P.st, P.t = 12, 0, 0, "L", 0, "drive", 0
    P.slip, P.drift, P.brk, P.gas, P.pop, P.os, P.ox = 0, 0, false, false, false, nil, nil
    if G.hide_debris then G.hide_debris() end
    G.cur_stage = nil; G.fork_lock = nil; G.time = G.EXTEND[1]; G.lap_t = 0; G.laps = {}; G.goal = nil; G.bonus = 0
    progress()
end
G.race_reset = race_reset
