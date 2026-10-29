------------------------------------------------------------------ 08_main: states, fixed step, camera, music, save, test hooks
do
local U, D, SIM, R, HUD, SCR, BOT = G.UI, G.D, G.SIM, G.R, G.HUD, G.SCR, G.BOT
local US = U.US
paint_templates()
build_lights()
------------------------------------------------------------------ save
local SV
local function load_save()
    local ok, s = pcall(fs.read, D.SAVE)
    SV = D.deserialize(ok and s or "")
end
local function save() pcall(fs.write, D.SAVE, D.serialize(SV)) end
load_save()
G.SV = function() return SV end
G.save = save

------------------------------------------------------------------ level flow
local S
local STEP = 1 / 60
local acc, end_t, res = 0, 0, nil
local demo_lvl = 1
local function demo_save()
    local s = D.new_save()
    for k in pairs(s.up) do s.up[k] = 3 end
    s.up.squad = 6; s.up.fire = 6
    s.hero = SV.hero
    s.weapon = ({ "rifle", "minigun", "rifle", "shotgun", "laser" })[(demo_lvl - 1) % 5 + 1]
    return s
end
local function start(n, demo)
    n = clamp(n, 1, #D.LEVELS)
    S = SIM.start(n, demo and demo_save() or SV)
    G.S = S
    G.set_world(D.LEVELS[n].world)
    G.weapon_tint(D.WEAPONS[S.weapon].col)
    R.reset(); HUD.reset()
    acc, end_t, res = 0, 0, nil; G.strike_q = false
    G.tx = 0
    G.demo = demo
    G.cam_reset = true
    if not demo then G.state = "play"; music("music_battle") end
end
G.start_level = start
local function go(st)
    G.state = st
    if st == "title" or st == "levels" or st == "shop" then music("music_title") end
end
local function to_menu(st)
    demo_lvl = ({ 1, 3, 5, 7, 9 })[rand(1, 5)]
    start(demo_lvl, true)
    go(st or "title")
end

local HINTS = { "Tip: Shoot A Gate Before Walking Through - Every Hit Raises It", "Tip: Merge 5 Soldiers Into A Veteran - Elites Survive Longer",
    "Tip: Upgrade Starting Squad And Firepower In The Shop", "Tip: Save Airstrikes For Brutes And Bosses",
    "Tip: Crack Containers To Free Turrets, Gunships And Mechs", "Tip: Do Not Over-Shoot Orange Trap Gates" }
local function finish()
    local won = S.over == "win"
    local n = S.lvl
    local coins = floor(S.coins + 0.5)
    if not won then coins = floor(coins * 0.5) end
    SV.coins = SV.coins + coins
    local newbest = S.score > (SV.best[n] or 0)
    if won then
        if newbest then SV.best[n] = S.score end
        SV.stars[n] = max(SV.stars[n] or 0, S.stars or 1)
        local medal = false
        if D.LEVELS[n].boss and n >= SV.unlocked then SV.medals = SV.medals + 1; medal = true end
        SV.unlocked = max(SV.unlocked, min(#D.LEVELS, n + 1))
        res = { won = true, stars = S.stars or 1, coins = coins, score = S.score, kills = S.kills, surv = S.surv or SIM.worth(), lvl = n, newbest = newbest, medal = medal, t = 0 }
    else
        res = { won = false, stars = 0, coins = coins, score = S.score, kills = S.kills, surv = 0, lvl = n, prog = clamp(S.travel / (S.L.len + 30), 0, 1), hint = HINTS[rand(1, #HINTS)], t = 0 }
    end
    save()
    sfx(won and "win" or "lose")
    music(nil)
    G.state = won and "win" or "lose"
    G.res = res
end

------------------------------------------------------------------ input -> sim
local mx_last
local function steer_input(dt)
    local MS = U.MS
    local hud_zone = U.inside(SW - 420 * US, SH - 240 * US, 420 * US, 240 * US) or U.inside(SW - 130 * US, 0, 130 * US, 120 * US)
    if MS.down and not hud_zone then
        if mx_last then G.tx = G.tx + (MS.x - mx_last) / SW * 15 end
        mx_last = MS.x
    else mx_last = nil end
    local k = 0
    if anyheld("A", "Left") then k = k - 1 end
    if anyheld("D", "Right") then k = k + 1 end
    if k ~= 0 then G.tx = G.tx + k * 20 * dt end   -- was 11 m/s: keys now sweep the 10 m lane in 0.5 s
    G.tx = clamp(G.tx, -D.LANE, D.LANE)
end

------------------------------------------------------------------ camera
local CAM = { p = vec3(0, 10.5, -12.2), l = vec3(0, 0, 12) }
local function camera(dt)
    local st = G.state
    local x = WX(S.x)
    local n = min(SIM.units(), 60)
    local up = n * 0.03
    local p, l
    if G.demo then
        local a = G.t * 0.09
        p = vec3(x * 0.3 + math.sin(a) * 2.5, 9.6 + up, -11.6 - up * 0.5)
        l = vec3(x * 0.4 + math.sin(a) * 1.5, 0.2, 13)
    else
        local boss = S.boss and S.boss.arrived
        p = vec3(x * 0.38, 10.5 + up + (boss and 1.4 or 0), -12.2 - up * 0.6 - (boss and 1.5 or 0))
        l = vec3(x * 0.5, 0.0 + (boss and 0.8 or 0), 11.8 + (boss and 3 or 0))
        if st == "win" then local a = math.sin((res and res.t or 0) * 0.35) * 1.2; p = vec3(x * 0.6 + a, 4.5, -5.5); l = vec3(x * 0.8, 1.5, 12) end
    end
    if G.cam_reset then G.cam_reset = false; CAM.p, CAM.l = p, l end
    local k = 3.5
    CAM.p = vec3(damp(CAM.p.x, p.x, k, dt), damp(CAM.p.y, p.y, k, dt), damp(CAM.p.z, p.z, k, dt))
    CAM.l = vec3(damp(CAM.l.x, l.x, k, dt), damp(CAM.l.y, l.y, k, dt), damp(CAM.l.z, l.z, k, dt))
    local s = (S.shake or 0) * (G.demo and 0.3 or 1)
    s = s * s
    local sx, sy = (rand() - 0.5) * s * 0.9, (rand() - 0.5) * s * 0.6
    G.cam.pos = vec3(CAM.p.x + sx, CAM.p.y + sy, CAM.p.z)
    G.cam.look = vec3(CAM.l.x + sx * 0.4, CAM.l.y + sy * 0.4, CAM.l.z)
    cam:set_position(G.cam.pos); cam:look_at(G.cam.look)
end

------------------------------------------------------------------ frame
to_menu("title")
local function sim_steps(dt, input_fn)
    -- equal substeps (Crowd Master fix): split this frame's time into n identical steps of <= STEP instead of a fixed-STEP
    -- accumulator that alternates 0/1/2 steps per frame (that beat against the display rate and made the squad judder)
    local sp = G.test.speed or 1
    acc = min(acc + dt * sp, 0.2 * sp)
    if acc > 0 then
        local n = math.ceil(acc / STEP - 1e-6)
        local h = acc / n
        for _ = 1, n do
            SIM.step(h, input_fn())
            R.events(S)
        end
        acc = 0
    end
end
local function update(dt)
    dt = min(dt or 0.016, 0.1)
    G.t = G.t + dt
    flush_mats()
    U.begin_frame()
    local st = G.state
    if st == "options" then
        if not SET:update(dt) then G.state = G.opt_back or "title" end
        U.end_frame()
        R.draw(S, 0); camera(dt); update_lights(dt)
        return
    end
    U.poll(st)
    if st == "play" then
        steer_input(dt)
        local strike = G.strike_q or U.K.ok
        G.strike_q = false
        if G.test.auto then G.tx = BOT.target(S) end
        sim_steps(dt, function() local s = strike; strike = false; return { tx = G.tx, strike = s or (G.test.auto and S.air >= 1) } end)
        R.draw(S, dt)
        camera(dt)   -- camera BEFORE the HUD: world-anchored labels/bars project with this frame's camera (no 1-frame lag wobble)
        local act = HUD.play(S, dt, false)
        if act == "air" then G.strike_q = true end   -- consumed by the next sim step (one frame later)
        if act == "merge" or anyedge("M") then if S.sol >= 5 then SIM.merge_all() end end
        if S.over then
            end_t = end_t + dt
            if end_t > (S.over == "win" and 0.6 or 1.4) then finish() end
        end
        if act == "pause" or U.K.back or anyedge("P") then G.state = "pause"; sfx("click") end
    elseif st == "pause" then
        R.draw(S, 0)
        camera(dt)
        HUD.play(S, 0, false)
        local act = SCR.pause(dt)
        if act == "resume" then G.state = "play"
        elseif act == "retry" then start(S.lvl)
        elseif act == "options" then G.opt_back = "pause"; G.state = "options"; SET:open()
        elseif act == "menu" then to_menu("title") end
    elseif st == "win" or st == "lose" then
        -- the world keeps living behind the card (the squad cheers / the horde keeps coming)
        if st == "win" then R.draw(S, dt) else R.draw(S, dt * 0.3) end
        camera(dt)
        local act = SCR.result(dt, res)
        if act == "next" then start(min(#D.LEVELS, res.lvl + 1))
        elseif act == "retry" then start(res.lvl)
        elseif act == "shop" then to_menu("shop")
        elseif act == "menu" then to_menu("title") end
    else
        -- menus: attract run of the bot behind them
        sim_steps(dt, function() return { tx = BOT.target(S), strike = S.air >= 1 } end)
        if S.over then end_t = end_t + dt; if end_t > 2 then demo_lvl = demo_lvl % #D.LEVELS + 1; start(demo_lvl, true) end end
        R.draw(S, dt)
        camera(dt)
        HUD.play(S, dt, true)
        local act
        if st == "title" then
            act = SCR.title(dt, SV)
            if act == "play" then start(SV.unlocked)
            elseif act == "levels" then go("levels")
            elseif act == "shop" then go("shop")
            elseif act == "options" then G.opt_back = "title"; G.state = "options"; SET:open()
            elseif act == "quit" then save(); pcall(function() app.quit() end); pcall(function() engine.quit() end) end
        elseif st == "levels" then
            act = SCR.levels(dt, SV)
            if act == "back" then go("title") elseif type(act) == "number" then start(act) end
        elseif st == "shop" then
            act = SCR.shop(dt, SV)
            if act == "buy" then save() elseif act == "back" then go("title") end
        end
    end
    HUD.overlays(dt)
    U.end_frame()
    update_lights(dt)
end
G.update = update
G.test.menu = to_menu
hooks { update = update }
pe_log("[GB] ready")
end
