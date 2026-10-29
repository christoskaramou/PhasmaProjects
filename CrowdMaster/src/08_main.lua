------------------------------------------------------------------ main: states, fixed step, camera, music, test hooks
do
local U, HUD, SCR, FIN, M = G.UI, G.HUD, G.SCR, G.FIN, G.M
local US = U.US
build_lights()
paint_templates()
M.load()
G.state = "title"
local STEP = 1 / 60   -- largest simulation sub-step (each frame's dt is split into equal sub-steps of at most this)
local acc = 0
local sim_dt = STEP  -- the sub-step being simulated (the test bot steers with it)
local CAM = { p = vec3(0, 8, -12), l = vec3(0, 1, 8), fov = 52 }
local menu_level = min(M.D.last or 1, #G.LEVELS)
local end_t = 0

------------------------------------------------------------------ level flow
local function load_level(i, showcase)
    i = clamp(i, 1, #G.LEVELS)
    local L = G.LEVELS[i]
    FIN.cleanup()
    RUN.start(L)
    if L.boss then FIN.boss_build(L) end
    C.cy = 0
    for _, u in ipairs(C.units) do u.y = 0 end   -- staircase feet heights (FIN.stairs_step) never leak into a new run
    G.HUD.pops, G.HUD.wpops, G.HUD.tip = {}, {}, nil
    R.labels = {}
    G.showcase = showcase
    if not showcase then M.D.last = i; M.save()
        if G.boost and G.boost.tries > 0 then G.popup("Retry Boost: +" .. G.boost.pawns .. " Runners, Weaker Foes", { .7, 1, .75, 1 }, 2.6)
        elseif G.boost and G.boost.deficit >= 2 then G.popup("Underdog Boost: +" .. G.boost.pawns .. " Runners, Weaker Foes", { .7, 1, .75, 1 }, 2.6) end
    end
    end_t = 0
    G.hb_reset()
    return L
end
G.goto_level = function(i) load_level(i, false); G.state = "play"; music("run") end
local function go(state)
    G.state = state
    if state == "title" or state == "levels" or state == "camp" then music("title") end
end
local function finish(won)
    local L = G.L
    local res = FIN.result or {}
    local T = M.tally(L, L.idx, won, res, RUN.stats)
    local fin = L.len + (L.boss and 51 or 0)
    local hint = nil
    if not won then
        local hints = { "Upgrade Starting Crowd In The Shop", "Merge Pawns Into Brutes On The Army Board", "Pick Gates By Their Result, Not Their Number",
            "Big Units Survive Traps Better", "Shield Bubble Blocks Every Trap For 3s" }
        hint = "Tip: " .. hints[rand(1, #hints)]
        -- a stuck player sitting on coins: point at the shop first
        local cheap = nil
        for _, u in ipairs(M.UP) do if u.id ~= "bank" and (not u.max or M.lvl(u.id) < u.max) then local c = M.cost(u); if not cheap or c < cheap then cheap = c end end end
        if cheap and M.D.coins >= cheap then hint = "Tip: You Have " .. M.D.coins .. " Coins - Upgrade At The Camp" end
    end
    SCR.res = { won = won, tally = T, t = 0, L = L, res = res, prog = C.cz / fin, hint = hint }
    sfx(won and "win" or "lose")
    G.state = won and "win" or "lose"
    music(nil)
end

------------------------------------------------------------------ autoplay bot (tests): greedy gates, dodges hazards
-- "human" test mode: a steady but imperfect player (reaction delay, keyboard-speed steering, some wrong gate reads,
-- some trap hits, skipped pickups). G.hp overrides the odds; tools/headless.lua runs it in bulk.
local HB = {}
G.hb_reset = function() HB = { t = 0, tx = 0, dec = {}, skip = {}, take = {} } end
local function hazard_at(x, z0, z1, noter)
    for _, e in ipairs(R.list) do
        if not e.done and e.z > z0 and e.z < z1 and not (HB.skip and HB.skip[e]) then
            local t = e.t
            if t == "saw" and x > e.x0 - 0.9 and x < e.x1 + 0.9 then return true end
            if (t == "crush" or t == "roll") and abs(x - e.x) < e.w / 2 + 0.9 then return true end
            if t == "ham" and abs(x - e.x) < 1.6 then return true end
            if t == "spin" then return true end
        end
    end
    local hw = min(C.hw or 1, 1.3) * 0.9   -- the crowd squeezes itself for narrow floor
    for _, zz in ipairs({ z0 - (C.hd or 1) - 0.5, z0, z0 + 3, z0 + 6, z0 + 9, z1 }) do
        local iv = G.floor_at(G.L, zz)
        if not (G.solid(iv, x - hw) and G.solid(iv, x + hw)) then return true end
    end
    if not noter and G.terrain_at(G.L, x, z0 + 6) == "thorn" or G.terrain_at(G.L, x, z0 + 6) == "gravel" then return true end
    return false
end
local function bot(mode)
    if RUN.phase ~= "run" then return end
    local tx = C.cxt
    local front = C.cz + (C.hd or 1)
    local gate
    for _, e in ipairs(R.list) do if e.t == "gate" and not e.done and e.z > front - 0.5 then gate = e; break end end
    if gate and gate.z - front < 28 then
        local best, bv = gate.panels[1], -1e9
        -- timed gates: judge the panels by what they will show on arrival (the lamps let a player read the beat)
        local on_arr
        if gate.kind == "timed" then
            local ta = G.t + max(0, gate.z - (C.hd or 1) * 0.5 - C.cz) / max(3, C.speed)
            on_arr = floor((ta + gate.z * 0.13) / 1.5) % 2 == 0
        end
        for i, p in ipairs(gate.panels) do
            local pv = p.v
            if on_arr ~= nil then pv = on_arr and ((i == 1) and gate.a or gate.b) or ((i == 1) and gate.b or gate.a) end
            local v = RUN.outcome(pv); if mode == "bad" then v = -v end
            if v > bv then bv, best = v, p end
        end
        tx = best.x
    end
    local pick
    -- otherwise grab the next pickup (cage / air drop / ally) like a player would
    if not (gate and gate.z - front < 28) then
        for _, e in ipairs(R.list) do
            if (e.t == "cage" or e.t == "drop" or e.t == "ally") and not e.done and e.z > C.cz - 1 and e.z - front < 24 then
                if mode ~= "bad" then tx = e.x; pick = true end; break
            end
        end
    end
    -- dodge anything in the next ~12 m
    -- with a gate coming up, only dodge what stands before it (a player commits to the panel, then dodges)
    local hz1 = (gate and gate.z - front < 28) and min(C.cz + 12, gate.z - 0.5) or C.cz + 12
    if hazard_at(tx, C.cz, hz1, pick) then
        local cands = { 0, -1, 1, -2, 2, -2.8, 2.8, -3.4, 3.4, -1.5, 1.5 }
        local t0 = tx
        table.sort(cands, function(a, b) return abs(a - t0) < abs(b - t0) end)
        local lim = (gate and gate.z - front < 28) and 1.8 or 99   -- never dodge off the chosen gate panel
        for _, x in ipairs(cands) do if abs(x - t0) <= lim and not hazard_at(x, C.cz, hz1, pick) then tx = x; break end end
    end
    if RUN.safe then local a, b = RUN.safe[1], RUN.safe[2]; tx = (a <= b) and clamp(tx, a, b) or RUN.safe[3] end
    C.cxt = damp(C.cxt, tx, 6, sim_dt)
end
local function human()
    if RUN.phase ~= "run" then return end
    local hp = G.hp or {}
    local dt = sim_dt
    HB.t = HB.t - dt
    if HB.t <= 0 then
        HB.t = (hp.react or 0.32) * rr(0.7, 1.3)
        local front = C.cz + (C.hd or 1)
        local tx = HB.tx
        HB.pick = false
        local gate
        for _, e in ipairs(R.list) do if e.t == "gate" and not e.done and e.z > front - 0.5 then gate = e; break end end
        local see = hp.see or 20
        local near = gate and gate.z - front < see
        if near then
            local d = HB.dec[gate]
            local function vals(arrival)
                local out = {}
                local on
                if gate.kind == "timed" then
                    local ta = G.t + (arrival and max(0, gate.z - (C.hd or 1) * 0.5 - C.cz) / max(3, C.speed) or 0)
                    on = floor((ta + gate.z * 0.13) / 1.5) % 2 == 0
                end
                for i, p in ipairs(gate.panels) do
                    local pv = p.v
                    if on ~= nil then pv = on and ((i == 1) and gate.a or gate.b) or ((i == 1) and gate.b or gate.a) end
                    out[i] = RUN.outcome(pv)
                end
                return out
            end
            local function pick(v, wrong)
                local bi, bv = 1, -1e9
                for i = 1, #v do local x = wrong and -v[i] or v[i]; if x > bv then bi, bv = i, x end end
                return bi
            end
            if not d then
                -- one look at the gate: timed gates are often read by what they show now, not on arrival
                local arrival = not (gate.kind == "timed" and rand() < (hp.p_timed or 0.4))
                local vv = vals(arrival); local wr = rand() < (hp.p_gate or 0.12)
                d = { i = pick(vv, wr) }
                if G.hdebug then print("GATE", gate.z, gate.panels[1].v, gate.panels[1].x, vv[1], gate.panels[2].v, gate.panels[2].x, vv[2], wr, d.i) end
                HB.dec[gate] = d
            end
            if gate.kind == "trick" and gate.flipped and not gate.scramble and not d.re then
                d.re = true
                if rand() < (hp.p_trick or 0.5) then d.i = pick(vals(true), false) end   -- noticed the swap in time
            end
            if gate.kind == "timed" and not d.re2 and gate.z - front < 8 then
                d.re2 = true
                if rand() < (hp.p_late or 0.3) then d.i = pick(vals(true), false) end      -- last-second correction
            end
            tx = gate.panels[d.i].x
        else
            for _, e in ipairs(R.list) do
                if (e.t == "cage" or e.t == "drop" or e.t == "ally") and not e.done and e.z > C.cz - 1 and e.z - front < 22 then
                    if HB.take[e] == nil then HB.take[e] = rand() < (hp.p_pick or 0.75) end
                    if HB.take[e] then tx = e.x; HB.pick = true end
                    break
                end
            end
            if not near and not (gate and gate.z - front < see) then
                -- drift back toward the middle when nothing is going on
                local any = false
                for _, e in ipairs(R.list) do if not e.done and e.z > C.cz and e.z - front < 22 and e.t ~= "enemy" then any = true; break end end
                if not any then tx = tx * 0.7 end
            end
        end
        -- traps: each one is either seen and dodged or (p_miss) run into
        local look = hp.look or 10
        for _, e in ipairs(R.list) do
            if not e.done and HB.skip[e] == nil and e.z > C.cz and e.z - C.cz < look
                and (e.t == "saw" or e.t == "crush" or e.t == "roll" or e.t == "ham" or e.t == "spin") then
                HB.skip[e] = rand() < (hp.p_miss or 0.2)
            end
        end
        local hz1 = near and min(C.cz + look, gate.z - 0.5) or C.cz + look
        if hazard_at(tx, C.cz, hz1, HB.pick) then
            local cands = { 0, -1, 1, -2, 2, -2.8, 2.8, -3.4, 3.4, -1.5, 1.5 }
            local t0 = tx
            table.sort(cands, function(a, b) return abs(a - t0) < abs(b - t0) end)
            local lim = near and 1.8 or 99
            for _, x in ipairs(cands) do if abs(x - t0) <= lim and not hazard_at(x, C.cz, hz1) then tx = x; break end end
        end
        if G.hdebug then print(string.format("    plan z%.1f tx%.2f from %.2f near=%s pick=%s", C.cz, tx, HB.tx, tostring(near), tostring(HB.pick))) end
        -- never cut across a hole to reach the line: hold the current strip until the way over is clear
        local hw = min(C.hw or 1, 1.3) * 0.9
        local function hole(x)
            for _, zz in ipairs({ C.cz - (C.hd or 1), C.cz, C.cz + 2, C.cz + 4, C.cz + 6 }) do
                local iv = G.floor_at(G.L, zz)
                if not (G.solid(iv, x - hw) and G.solid(iv, x + hw)) then return true end
            end
            return false
        end
        local a0, a1 = min(C.cx, tx), max(C.cx, tx)
        local blocked = false
        local x = a0
        while x <= a1 do if hole(x) then blocked = true; break end; x = x + 0.4 end
        if blocked and not hole(C.cx) then tx = C.cx end
        HB.tx = tx
    end
    -- keyboard-speed steering toward the planned line (10 m/s like A/D)
    local d = HB.tx - C.cxt
    C.cxt = C.cxt + clamp(d, -10 * dt, 10 * dt)
end
G.bot = nil   -- "greedy" / "bad" from tests

------------------------------------------------------------------ fixed simulation step
local function follow(dt, hwmax)
    C.layout(hwmax)
    for _, u in ipairs(C.units) do
        u.ox = damp(u.ox, u.tx, 7, dt); u.oz = damp(u.oz, u.tz, 7, dt)
    end
end
local function sim(dt)
    sim_dt = dt
    local L = G.L
    if G.shield_t and G.shield_t > 0 then G.shield_t = max(0, G.shield_t - dt) end
    local ph = RUN.phase
    if ph == "run" then
        if G.bot == "human" then human() elseif G.bot then bot(G.bot) end
        RUN.step(dt)
        if RUN.phase == "run" and C.cz >= L.len + 2 then
            if L.boss then RUN.phase = "boss"; music("boss") else FIN.stairs_start(L) end
        end
    elseif ph == "stairs" then
        follow(dt, 1.6); C.sync(); FIN.stairs_step(dt)
    elseif ph == "boss" then
        follow(dt, 3.6); C.sync(); FIN.boss_step(dt)
    elseif ph == "dead" or ph == "finished" then
        end_t = end_t + dt
        C.speed = damp(C.speed, 0, 4, dt)
        -- several fixed steps can run in one frame: only pay out once (G.state leaves "play" in finish)
        if end_t > (ph == "dead" and 1.4 or 0.9) and G.state == "play" then finish(ph == "finished") end
    end
end

------------------------------------------------------------------ camera
local function camera(dt)
    local st = G.state
    local p, l
    local blob = min(C.rmax or 1, 6)
    local cy = C.cy or 0
    if st == "title" or st == "levels" or st == "camp" then
        local a = G.t * 0.12
        -- low hero orbit: horizon and sky in frame, crowd large on one side
        p = vec3(LX(C.cx) + sin(a) * 11, 2.7 + blob * 0.2, C.cz + cos(a) * 11 - 2)
        l = vec3(LX(C.cx) - sin(a) * 2.5, 2.1, C.cz + 3)
        if st == "camp" then p = vec3(LX(C.cx) + 5, 3.2, C.cz + 8); l = vec3(LX(C.cx), 1.0, C.cz) end
    elseif RUN.phase == "stairs" then
        -- follow the column's front up the staircase on the smooth ramp (not C.cz/C.cy, which no longer jump)
        local fz, fy = C.cz, cy
        if FIN.s then fz, fy = FIN.focus() end
        p = vec3(LX(5.5), fy + 7.5, fz - 11); l = vec3(0, fy + 2.5, fz + 7)
    elseif RUN.phase == "boss" and FIN.b then
        local B = FIN.b
        if B.state == "fall" then p = vec3(LX(9), 7, B.z - 16); l = vec3(0, 3, B.z)
        else p = vec3(LX(C.cx * 0.3 + 3), 7.5 + blob * 0.15, C.cz - 12 - blob * 0.2); l = vec3(0, 3.2, B.z - 2) end
    else
        p = vec3(LX(C.cx * 0.35), 8 + blob * 0.12 + cy, C.cz - 11 - blob * 0.18)
        l = vec3(LX(C.cx * 0.5), 0.8 + cy, C.cz + 8)
        if st == "win" or st == "lose" then p = vec3(p.x + 3, p.y - 1.5, p.z + 4) end
    end
    if G.cam_dbg then p, l = G.cam_dbg[1], G.cam_dbg[2]; G.cam_reset = true end   -- dev inspection camera (MCP: CM.cam_dbg = {vec3, vec3})
    if G.cam_reset then G.cam_reset = false; CAM.p, CAM.l = p, l end
    local k = (st == "play") and 6 or 2.2
    CAM.p = vec3(damp(CAM.p.x, p.x, k, dt), damp(CAM.p.y, p.y, k, dt), damp(CAM.p.z, p.z, k * 1.6, dt))
    CAM.l = vec3(damp(CAM.l.x, l.x, k, dt), damp(CAM.l.y, l.y, k, dt), damp(CAM.l.z, l.z, k * 1.6, dt))
    -- shake + fov punch
    G.shk = max(0, G.shk - dt * 1.8)
    local s = G.shk * G.shk
    local sx, sy = (rand() - 0.5) * s * 1.2, (rand() - 0.5) * s * 0.8
    G.fovp_t = G.fovp_t + dt
    local pk = G.fovp_t < G.fovp_d and G.fovp * sin(PI * min(1, G.fovp_t / G.fovp_d * 1.0)) or 0
    local speedfov = (st == "play" and RUN.phase == "run") and clamp((C.speed - 8.5) * 0.6, -2, 3) or 0
    CAM.fov = damp(CAM.fov, 52 + speedfov, 3, dt)
    set_vfov(math.rad(CAM.fov + pk))
    G.cam.pos = vec3(CAM.p.x + sx, CAM.p.y + sy, CAM.p.z)
    G.cam.look = vec3(CAM.l.x + sx * 0.5, CAM.l.y + sy * 0.5, CAM.l.z)
    cam:set_position(G.cam.pos); cam:look_at(G.cam.look)
end

------------------------------------------------------------------ shield visuals
local sh_t = 0
local function shield_fx(dt)
    if (G.shield_t or 0) > 0 then
        sh_t = sh_t - dt
        if sh_t <= 0 then
            sh_t = 0.12
            local r = (C.hw or 1) + 0.6
            G.FX.ring(LX(C.cx), 0.15 + (C.cy or 0), C.cz, r * 2, { .3, .6, 1.2 }, true)
            G.FX.sparks(LX(C.cx + rr(-r, r)), 1 + rand(), C.cz + rr(-1, 1), 2, { 0, 1, 0 }, 2, { .5, .9, 1.6 })
        end
    end
end

------------------------------------------------------------------ frame
load_level(menu_level, true)
music("title")
local mx_last = nil
local frames = 0
local cam_done = false
local function update(dt)
    dt = min(dt or 0.016, 0.25)
    cam_done = false
    frames = frames + 1
    G.t = G.t + dt
    flush_mats()
    M.tick(dt)
    U.begin_frame()
    local st = G.state
    -- options overlay (settings_menu owns its own screen while open)
    if st == "options" then
        if not SET:update(dt) then G.state = G.opt_back or "title" end
        U.end_frame()
        C.animate(dt, "idle"); camera(dt); update_lights(dt)
        return
    end
    U.poll(st)
    if st == "play" then
        -- drag steering
        local MS = U.MS
        if MS.down and not U.inside(SW - 130 * US, 0, 130 * US, 130 * US) and not U.inside(SW - 180 * US, SH - 200 * US, 180 * US, 200 * US) then
            if mx_last then G.drag_dx = (G.drag_dx or 0) + (MS.x - mx_last) / SW * 14 end
            mx_last = MS.x
        else mx_last = nil end
        if U.K.ok or anyedge("Space") then G.use_shield() end
        -- semi-fixed step: split this frame's dt into n equal sub-steps of at most 1/60 s. The old loop ran whole 1/60 s
        -- steps and carried the remainder, with no interpolation, so at 75/120/144 Hz or with uneven frame times the crowd,
        -- traps and the camera target advanced 0, 1 or 2 steps per rendered frame (visible judder that TAA then smears).
        -- Now every rendered frame shows the world exactly dt further on. G.freeze (tests) holds the simulation.
        acc = G.freeze and 0 or min(acc + dt, 0.2)
        if acc > 0 then
            local n = math.ceil(acc / STEP - 1e-6)
            local h = acc / n
            for _ = 1, n do if G.state ~= "play" then break end; sim(h) end
            acc = 0
        end
        -- move the camera before the HUD projects its world labels (badge, gate numbers, step multipliers): projecting
        -- with last frame's camera made every label trail the 3D scene by one frame
        camera(dt); cam_done = true
        if G.state == "play" then
            local act = HUD.play(dt, G.L)
            if act == "pause" or U.K.back or U.K.pause then G.state = "pause"; sfx("click") end
        end
        local mode = (RUN.phase == "stairs" and FIN.s and FIN.s.done) and "cheer" or ((RUN.phase == "finished" or (FIN.b and FIN.b.state == "fall")) and "cheer" or "run")
        if RUN.phase == "boss" and FIN.b and FIN.b.state == "fight" then mode = "idle" end
        if RUN.phase == "dead" then mode = "idle" end
        C.animate(dt, mode)
        shield_fx(dt)
    elseif st == "pause" then
        local act = SCR.pause(dt)
        C.animate(0, "idle")
        if act == "resume" then G.state = "play"
        elseif act == "retry" then G.goto_level(G.L.idx)
        elseif act == "options" then G.opt_back = "pause"; G.state = "options"; SET:open()
        elseif act == "menu" then load_level(G.L.idx, true); go("title") end
    elseif st == "win" or st == "lose" then
        HUD.overlays(dt)
        local act = SCR.result(dt)
        C.animate(dt, st == "win" and "cheer" or "idle")
        if act == "next" then G.goto_level(G.L.idx >= #G.LEVELS and G.L.idx or G.L.idx + 1)
        elseif act == "retry" then G.goto_level(G.L.idx)
        elseif act == "camp" then load_level(min(M.D.unlocked, G.L.idx + (st == "win" and 1 or 0)), true); go("camp")
        elseif act == "menu" then load_level(G.L.idx, true); go("title") end
    else
        -- menus run the showcase crowd idling in the level
        C.animate(dt, "idle")
        local act
        if st == "title" then
            act = SCR.title(dt)
            if act == "play" then G.goto_level(M.D.unlocked)
            elseif act == "levels" then go("levels")
            elseif act == "camp" then go("camp")
            elseif act == "options" then G.opt_back = "title"; G.state = "options"; SET:open()
            elseif act == "quit" then M.save(); pcall(function() app.quit() end); pcall(function() engine.quit() end) end
        elseif st == "levels" then
            act = SCR.levels(dt)
            if act == "back" then go("title") elseif type(act) == "number" then G.goto_level(act) end
        elseif st == "camp" then
            act = SCR.camp(dt)
            if act == "back" then go("title") elseif act == "next" then G.goto_level(min(M.D.unlocked, (M.D.last or 1) + ((M.D.best[M.D.last or 1] and 1) or 0))) end
        end
        HUD.overlays(dt)
    end
    U.end_frame()
    if not cam_done then camera(dt) end
    update_lights(dt)
end
G.update = update; G.RUN, G.C, G.R = RUN, C, R
hooks { update = update }
pe_log("[CM] ready")
end
