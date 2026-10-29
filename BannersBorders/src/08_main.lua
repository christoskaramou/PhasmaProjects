------------------------------------------------------------------ 08_main: states, input, camera, fixed-step sim, save, tutorial, test hooks
do
local U, D, SIM, AI, RN, HUD, SCR = G.UI, G.D, G.SIM, G.AI, G.RN, G.HUD, G.SCR
local US = U.US
G.paint_templates()
G.build_lights()
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

------------------------------------------------------------------ match state
local S
local STEP = 1 / 30
local acc, end_t, res = 0, 0, nil
local sel, pick, ratio, drag = {}, nil, 1, nil
local hov, tgt = nil, nil
local pan = { x = 0, z = 0 }
local ev = { x = 0, z = 0 }   -- edge-scroll velocity (see edge_scroll)
local zoom, zt = 1, 1          -- zoom eases toward the target zt (wheel, Z/X)
local zanchor = nil              -- screen point zoom keeps fixed ({x, y}); nil = screen centre
local demo_i = 0
local DEMO_LV = { 3, 12, 7, 16, 19, 9, 13 }
local CAM = {}
local function demo_save() local s = D.new_save(); for k in pairs(s.up) do s.up[k] = 2 end; return s end

local function fit(S)
    local x0, x1, z0, z1 = 1e9, -1e9, 1e9, -1e9
    for _, r in ipairs(S.R) do if r.active then x0 = min(x0, r.x); x1 = max(x1, r.x); z0 = min(z0, r.z); z1 = max(z1, r.z) end end
    CAM.cx, CAM.cz = (x0 + x1) / 2, (z0 + z1) / 2
    CAM.ex, CAM.ez = (x1 - x0) / 2 + 3, (z1 - z0) / 2 + 3
end

local function start(li, demo)
    li = clamp(li, 1, #D.LEVELS)
    SV.fails = SV.fails or {}
    S = SIM.new(li, demo and demo_save() or SV, { demo = demo, mode = G.SET:get("difficulty") or 2, boost = (not demo) and (SV.fails[li] or 0) or 0 })
    G.st = S
    G.build_board(S.L.map, S.R)
    RN.reset(S); RN.clear(); HUD.reset()
    acc, end_t, res = 0, 0, nil
    sel, pick, drag, hov, tgt = {}, nil, nil, nil, nil
    pan.x, pan.z, zoom, zt, zanchor = 0, 0, 1, 1, nil
    ev.x, ev.z = 0, 0
    S.tut_i = S.tut and 1 or nil
    S.tut_t = 0
    fit(S)
    G.cam_reset = true
    G.demo = demo
    if not demo then
        G.state = "play"
        G.shop_back = nil
        music(S.L.boss and "music_boss" or "music_battle")
        HUD.banner(S.L.name, SCR.MNAME[S.L.map] .. "  ·  Battle " .. li, S.L.boss and { .3, .12, .4 } or nil)
        sfx("march_horn")
        if S.boost > 0 then
            HUD.toast(string.format("Retry Boost x%d: +%d%% starting troops, enemy recruits -%d%%", S.boost,
                floor(100 * D.RETRY.troops * S.boost + 0.5), floor(100 * D.RETRY.aiprod * S.boost + 0.5)), "gold", nil, "retry")
        end
    end
end
G.start_level = start
local function go(st)
    G.state = st
    if st == "title" or st == "levels" or st == "shop" then music("music_title") end
end
local function to_menu(st)
    demo_i = demo_i % #DEMO_LV + 1
    start(DEMO_LV[demo_i], true)
    go(st or "title")
end

local HINTS = { "Tip: Hit neutral regions early - every region recruits for you.", "Tip: Don't empty your borders; a counter-attack is always coming.",
    "Tip: Forts double as walls. Go around them, or bring a crowd.", "Tip: Streams that meet mid-way annihilate one-for-one.",
    "Tip: Ports sail at full speed; everyone else wades slowly across the sea.", "Tip: Mines speed up your abilities. Grab them.",
    "Tip: Use 50% sends (Space) to keep a garrison home.", "Tip: Upgrades in the War Chest carry over to every battle." }
local function finish()
    local won = S.win
    local li = S.li
    local stars, coins = 0, 0
    local unlock
    local newbest = false
    if won then
        stars = D.stars_for(S.t, S.L.par)
        coins = D.coins_for(li, stars)
        if not SV.best[li] or S.t < SV.best[li] then SV.best[li] = floor(S.t); newbest = true end
        SV.stars[li] = max(SV.stars[li] or 0, stars)
        if li >= SV.unlocked and li < #D.LEVELS then
            for _, a in ipairs(D.ABIL) do if a.unlock == li + 1 then unlock = a.name end end
        end
        SV.unlocked = max(SV.unlocked, min(#D.LEVELS, li + 1))
        SV.wins = (SV.wins or 0) + 1
        if S.L.tut then SV.tut = true end
        SV.fails[li] = nil                                        -- retry boost resets on a win
    else
        coins = 15 + 3 * S.F[1].captured
        SV.fails[li] = math.min(D.RETRY.max, (SV.fails[li] or 0) + 1)
    end
    SV.coins = SV.coins + coins
    save()
    res = { won = won, stars = stars, coins = coins, lvl = li, t = 0, time = S.t, cap = S.F[1].captured, sent = S.stat.sent or S.F[1].sent,
        peak = S.stat.peak, newbest = newbest, unlock = unlock, hint = (not won) and HINTS[math.random(1, #HINTS)] or nil }
    sfx(won and "win" or "lose")
    music(nil)
    G.state = won and "win" or "lose"
    G.res = res
    sel, pick, drag = {}, nil, nil
end

------------------------------------------------------------------ picking
local function pick_region(sx, sy)
    -- badges first (they float above the board), then the tile under the cursor
    local best, bd = nil, (34 * US) ^ 2
    for i, r in ipairs(S.R) do
        if r.active then
            local px, py, zc = project(r.x, r.h + 0.55, r.z)
            if zc > 0.3 then
                local d = (px - sx) ^ 2 + (py - sy) ^ 2
                if d < bd then best, bd = i, d end
            end
        end
    end
    if best then return best end
    for _, y in ipairs({ 0.9, 0.55, 0.3 }) do
        local x, z = unproject(sx, sy, y)
        if x then
            local c = SIM.region_at(S, x, z)
            if c and abs(S.R[c].h - y) < 0.3 then return c end
        end
    end
    local x, z = unproject(sx, sy, 0.5)
    if x then return SIM.region_at(S, x, z) end
    return nil
end
G.pick_region = function(sx, sy) return pick_region(sx, sy) end

local function nsel() local n = 0; for _ in pairs(sel) do n = n + 1 end; return n end
local function do_send(dst)
    local srcs = {}
    for i in pairs(sel) do if i ~= dst and S.R[i].owner == 1 then srcs[#srcs + 1] = i end end
    if #srcs == 0 then return false end
    table.sort(srcs)
    local n = SIM.send(S, 1, srcs, dst, ratio)
    if n > 0 then
        S.multi_sent = S.multi_sent or (#srcs >= 2)
        sel = {}
        return true
    end
    sfx("warn")
    return false
end
local function try_ability(k)
    local a = D.ABIL[k]
    if not SIM.abil_unlocked(S, k) then HUD.toast(a.name .. " unlocks at battle " .. a.unlock, "grey", nil, "lk"); sfx("warn"); return end
    if not SIM.abil_ready(S, 1, k) then HUD.toast(a.name .. " is recharging", "grey", nil, "cd"); sfx("warn"); return end
    if a.target then pick = (pick == k) and nil or k; sfx("select")
    else if SIM.use(S, 1, k) then HUD.toast(a.name .. "!", "gold") end end
end

local rprev = false
local function right_click()
    local ok, d = pcall(input.is_right_mouse_down)
    d = (ok and d) or (G.vmouse and G.vmouse.right) or false
    local e = d and not rprev
    rprev = d
    return e
end

-- RTS edge scrolling: the cursor within EDGE px of a screen edge pans that way (corners pan diagonally).
-- Speed eases in with depth into the margin (smoothstep, 30%..100%), the velocity itself is damped so starts and
-- stops are soft, and everything is dt-scaled. Only called from play_input, so pause / menus / results never scroll.
local EDGE = clamp(floor(18 * US + 0.5), 12, 28)   -- 15 px at 900p, 18 at 1080p, 24 at 1440p
local EDGE_SPEED = 18                              -- world units / s at full depth, zoom 1, before map-size scaling
local function edge_scroll(dt, MS)
    local tx, tz = 0, 0
    local inside = MS.x >= 0 and MS.y >= 0 and MS.x < SW and MS.y < SH
    if inside and not (G.test and G.test.no_edge) then
        local function depth(d) local t = clamp((EDGE - d) / EDGE, 0, 1); if t <= 0 then return 0 end; t = t * t * (3 - 2 * t); return 0.3 + 0.7 * t end
        tx = depth(MS.x) - depth(SW - 1 - MS.x)          -- left edge = +x (world x = -east)
        tz = depth(MS.y) - depth(SH - 1 - MS.y)          -- top edge = +z (north)
        local l = sqrt(tx * tx + tz * tz); if l > 1 then tx, tz = tx / l, tz / l end
    end
    local sp = EDGE_SPEED * max(1, CAM.ez / 12) / zoom
    ev.x, ev.z = damp(ev.x, tx * sp, 10, dt), damp(ev.z, tz * sp, 10, dt)
    if abs(ev.x) < 1e-3 then ev.x = 0 end
    if abs(ev.z) < 1e-3 then ev.z = 0 end
    pan.x, pan.z = pan.x + ev.x * dt, pan.z + ev.z * dt
    -- stop pushing against the map bounds so the camera does not keep "leaning" after it clamps
    if (pan.x >= CAM.ex and ev.x > 0) or (pan.x <= -CAM.ex and ev.x < 0) then ev.x = 0 end
    if (pan.z >= CAM.ez and ev.z > 0) or (pan.z <= -CAM.ez and ev.z < 0) then ev.z = 0 end
end

------------------------------------------------------------------ camera target, wheel zoom, mouse lock
local PITCH = math.rad(56)
local ZMIN, ZMAX = 0.6, 2.6          -- was 0.7..2.2 with Z/X only
local ZSTEP = 1.15                   -- zoom factor per wheel notch
-- where the camera settles for a pan/zoom (before the damping in camera()): look point and distance
local function cam_target(px, pz, zm)
    local hf = math.tan(math.rad(27)) * SW / SH
    local d = max(CAM.ex / hf, CAM.ez * 1.25 / math.tan(math.rad(27))) * 0.92 / zm
    return CAM.cx + px, CAM.cz + pz - CAM.ez * 0.06, d
end
local function cam_pl(px, pz, zm)
    local lx, lz, d = cam_target(px, pz, zm)
    return { x = lx, y = math.sin(PITCH) * d, z = lz - math.cos(PITCH) * d }, { x = lx, y = 0, z = lz }
end
-- this frame's wheel notches (+ = away from you = zoom in). The runtime UI backdrop holds the mouse, so the raw
-- input wheel is usually 0 and ImGui's wheel (runtime_ui.get_wheel) carries it; use one source, never both.
local function read_wheel()
    local w = 0
    local ok, v = pcall(runtime_ui.get_wheel)
    if ok and type(v) == "number" then w = v end
    if w == 0 then
        local ok2, t = pcall(input.get_mouse_wheel)
        if ok2 and type(t) == "table" then w = tonumber(t.y) or 0 end
    end
    if G.vwheel then w = w + G.vwheel; G.vwheel = nil end      -- test hook
    return clamp(w, -5, 5)
end
-- eased zoom toward zt that keeps the map point under zanchor (cursor) fixed; dt-scaled
local function zoom_step(dt)
    local nz = damp(zoom, zt, 12, dt)
    if abs(nz - zt) < 1e-4 then nz = zt end
    if nz == zoom then return end
    local ax, ay = SW / 2, SH / 2
    if zanchor then ax, ay = zanchor.x, zanchor.y end
    local c0, l0 = cam_pl(pan.x, pan.z, zoom)
    local c1, l1 = cam_pl(pan.x, pan.z, nz)
    local x0, z0 = unproject_cam(c0, l0, ax, ay, 0.5)
    local x1, z1 = unproject_cam(c1, l1, ax, ay, 0.5)
    if x0 and x1 then pan.x, pan.z = pan.x + (x0 - x1), pan.z + (z0 - z1) end
    zoom = nz
end

-- Lock Mouse to Window: confine the (visible) cursor to the window during a live battle only. Needs an engine
-- grab binding; the current Phasma Lua API has none, so this feature-detects one and logs every transition.
local LOCK = { on = nil, api = nil }
local function grab_api()
    if LOCK.api == nil then
        LOCK.api = (input and (input.set_mouse_grab or input.set_window_grab or input.set_mouse_confined))
            or (engine and (engine.set_mouse_grab or engine.set_window_grab)) or false
        if not LOCK.api then pe_log("[BB] mouse lock: engine Lua API has no window grab (input.set_mouse_grab missing); setting is kept, cursor not confined") end
    end
    return LOCK.api
end
local function window_focused()
    local f = input and input.is_window_focused
    if f then local ok, v = pcall(f); if ok then return v ~= false end end
    return true   -- no focus query in the API; SDL drops a grab by itself while the window is unfocused
end
local function mouse_lock(st, force_off)
    local want = (not force_off) and st == "play" and G.SET:get("lock_mouse") ~= false and window_focused() and not (S and S.over)
    if want == LOCK.on then return end
    LOCK.on = want
    local f = grab_api()
    if f then pcall(f, want) end
    pe_log(string.format("[BB] mouse lock %s (state=%s, setting=%s, grab api=%s)", want and "ON" or "OFF", tostring(st),
        tostring(G.SET:get("lock_mouse")), f and "yes" or "missing"))
end

local function play_input(dt, tray_act, top_act)
    local MS = U.MS
    local over = HUD.over()
    local under = (MS.x >= 0) and pick_region(MS.x, MS.y) or nil
    hov = under
    tgt = G.test and G.test.ftgt or nil   -- test hook: forced target for screenshots
    -- keys
    for k = 1, #D.ABIL do if anyedge(tostring(k), "Num" .. k) then try_ability(k) end end
    if type(tray_act) == "number" then try_ability(tray_act) elseif tray_act == "ratio" or U.K.ok then ratio = ratio >= 1 and 0.5 or 1; sfx("select") end
    if anyedge("Q") then sel = {}; for i, r in ipairs(S.R) do if r.owner == 1 and r.active then sel[i] = true end end; sfx("select") end
    local pv = 14 * dt / zoom
    local kx, kz = 0, 0
    if anyheld("A", "Left") then kx = kx + 1 end
    if anyheld("D", "Right") then kx = kx - 1 end
    if anyheld("W", "Up") then kz = kz + 1 end
    if anyheld("S", "Down") then kz = kz - 1 end
    pan.x, pan.z = pan.x + kx * pv, pan.z + kz * pv
    edge_scroll(dt, MS)
    local wh = read_wheel()
    if wh ~= 0 then
        zt = clamp(zt * ZSTEP ^ wh, ZMIN, ZMAX)
        local inside = MS.x >= 0 and MS.y >= 0 and MS.x < SW and MS.y < SH
        zanchor = inside and { x = MS.x, y = MS.y } or nil
    end
    if anyheld("Z", "Equal") then zt = min(ZMAX, zt * (1 + dt * 1.2)); zanchor = nil end
    if anyheld("X", "Minus") then zt = max(ZMIN, zt / (1 + dt * 1.2)); zanchor = nil end
    zoom_step(dt)
    if right_click() then sel, pick, drag = {}, nil, nil end
    -- mouse
    if MS.click and not over then
        if pick then
            if under and SIM.use(S, 1, pick, under) then pick = nil else sfx("warn") end
        elseif under and S.R[under].owner == 1 then
            drag = { x0 = MS.x, y0 = MS.y, start = under, moved = false, was = sel[under] }
            if not sel[under] then sel[under] = true; sfx("select") end
        elseif under and nsel() > 0 then
            do_send(under)
        else
            sel = {}   -- a click on empty board only clears the selection; clicks never move the camera
        end
    end
    if drag then
        do
            if abs(MS.x - drag.x0) + abs(MS.y - drag.y0) > 10 then drag.moved = true end
            local wx, wz = unproject(MS.x, MS.y, 0.5)
            drag.x, drag.z = wx or 0, wz or 0
            if MS.down then
                -- sweeping over more of your regions adds them to the group
                if drag.moved and under and S.R[under].owner == 1 and not sel[under] then sel[under] = true; sfx("hover") end
                if drag.moved and under and (not sel[under] or under ~= drag.start) then tgt = under end
            else
                if drag.moved and under then
                    do_send(under)
                elseif not drag.moved and drag.was then
                    sel[drag.start] = nil   -- click on an already selected region deselects it
                end
                drag = nil
            end
        end
    elseif pick then tgt = under
    elseif nsel() > 0 and under and not sel[under] then tgt = under end
    pan.x = clamp(pan.x, -CAM.ex, CAM.ex)
    pan.z = clamp(pan.z, -CAM.ez, CAM.ez)
    -- drop selections that are no longer ours
    for i in pairs(sel) do if S.R[i].owner ~= 1 then sel[i] = nil end end
    if U.K.back then if pick or nsel() > 0 then sel, pick, drag = {}, nil, nil else return "pause" end end
    if top_act == "pause" or anyedge("P") then return "pause" end
end

------------------------------------------------------------------ tutorial
local function tutorial(dt)
    if not S.tut_i then return end
    local step = D.TUT[S.tut_i]
    if not step then return end
    S.tut_t = S.tut_t + dt
    local adv = false
    if step.key == "select" then
        for _, e in ipairs(S.ev) do if e.k == "send" and e.f == 1 then adv = true end end
    elseif step.key == "capture" then adv = S.F[1].nreg >= (step.need or 3)
    elseif step.key == "multi" then adv = S.multi_sent or S.tut_t > (step.wait or 6) * 2.5
    elseif step.wait and step.wait > 0 then adv = S.tut_t > step.wait end
    if adv and S.tut_i < #D.TUT then S.tut_i = S.tut_i + 1; S.tut_t = 0; sfx("coin") end
end
local function tut_focus()
    if not S.tut_i then return nil end
    local step = D.TUT[S.tut_i]
    if step.key == "select" and nsel() == 0 then return S.L.p[1] end
    if step.key == "abil" then return 5 end
    return nil
end

------------------------------------------------------------------ camera
local function camera(dt)
    local lx, lz, d = cam_target(pan.x, pan.z, zoom)
    if G.demo then local a = G.t * 0.07; lx = lx + math.sin(a) * CAM.ex * 0.15; lz = lz + math.cos(a * 0.7) * CAM.ez * 0.08; d = d * 0.9 end
    if G.state == "win" then d = d * (1 - min(0.15, (res and res.t or 0) * 0.02)) end
    local px, py, pz = lx, math.sin(PITCH) * d, lz - math.cos(PITCH) * d
    if G.cam_reset then G.cam_reset = false; CAM.p = { px, py, pz }; CAM.l = { lx, 0, lz } end
    local k = 4
    CAM.p = { damp(CAM.p[1], px, k, dt), damp(CAM.p[2], py, k, dt), damp(CAM.p[3], pz, k, dt) }
    CAM.l = { damp(CAM.l[1], lx, k, dt), 0, damp(CAM.l[3], lz, k, dt) }
    G.cam.pos = vec3(CAM.p[1], CAM.p[2], CAM.p[3])
    G.cam.look = vec3(CAM.l[1], CAM.l[2], CAM.l[3])
    cam:set_position(G.cam.pos); cam:look_at(G.cam.look)
end

------------------------------------------------------------------ frame
to_menu("title")
local function sim_steps(dt)
    local sp = G.test.speed or 1
    acc = min(acc + dt * sp, 0.25 * sp)
    while acc >= STEP do
        SIM.step(S, STEP)
        acc = acc - STEP
    end
end
local function world(dt, live)
    RN.update(S, dt, live and sel or {}, live and hov or nil, live and (tgt or tut_focus()) or nil, live and drag and drag.moved and drag or nil)
    G.update_clouds(dt)
end
local function update(dt)
    dt = min(dt or 0.016, 0.1)
    G.t = G.t + dt
    flush_mats()
    U.begin_frame()
    HUD.begin()
    local st = G.state
    if st == "options" then
        if not G.SET:update(dt) then G.state = G.opt_back or "title" end
        U.end_frame()
        world(0, false); camera(dt); G.update_lights(dt)
        mouse_lock(G.state)
        return
    end
    U.poll(st)
    if st == "play" then
        camera(dt)
        local top = HUD.top(S, false)
        local tray = HUD.tray(S, pick, ratio)
        if S.tut_i then HUD.tut(D.TUT[S.tut_i], S.tut_i, #D.TUT) end
        local act = play_input(dt, tray, top)
        sim_steps(dt)
        tutorial(dt)
        world(dt, true)
        HUD.badges(S, sel, hov, tgt, tut_focus())
        if hov and not drag then HUD.tip(S, hov) end
        if pick then HUD.pick_hint(pick) end
        if S.over then
            sel, drag, pick = {}, nil, nil
            end_t = end_t + dt
            if end_t > 1.6 then finish() end
        end
        if act == "pause" then G.state = "pause"; sfx("click") end
    elseif st == "pause" then
        camera(dt); world(0, false)
        HUD.badges(S, {}, nil, nil)
        local act = SCR.pause(dt)
        if act == "resume" then G.state = "play"
        elseif act == "retry" then start(S.li)
        elseif act == "options" then G.opt_back = "pause"; G.state = "options"; G.SET:open()
        elseif act == "menu" then to_menu("title") end
    elseif st == "win" or st == "lose" then
        camera(dt)
        world(dt, false)
        local act = SCR.result(dt, res, SV)
        if act == "next" then start(min(#D.LEVELS, res.lvl + 1))
        elseif act == "retry" then start(res.lvl)
        elseif act == "shop" then G.shop_back = st; go("shop")    -- War Chest over the frozen battle; Back returns here
        elseif act == "menu" then to_menu("title") end
    else
        -- menus: an AI-vs-AI attract battle plays on the board behind them
        -- (the War Chest opened from a result screen keeps the finished battle frozen behind it instead)
        local frozen = st == "shop" and (G.shop_back == "win" or G.shop_back == "lose")
        if not frozen then
            sim_steps(dt)
            if S.over then end_t = end_t + dt; if end_t > 2.5 then to_menu(st) end end
        end
        camera(dt)
        world(dt, false)
        if st == "title" then HUD.badges(S, {}, nil, nil) end
        local act
        if st == "title" then
            act = SCR.title(dt, SV)
            if act == "play" then start(min(SV.unlocked, #D.LEVELS))
            elseif act == "levels" then go("levels")
            elseif act == "shop" then G.shop_back = nil; go("shop")
            elseif act == "options" then G.opt_back = "title"; G.state = "options"; G.SET:open()
            elseif act == "quit" then save(); mouse_lock(nil, true); pcall(function() app.quit() end); pcall(function() engine.quit() end) end
        elseif st == "levels" then
            act = SCR.levels(dt, SV)
            if act == "back" then go("title") elseif act == "shop" then G.shop_back = "levels"; go("shop") elseif type(act) == "number" then start(act) end
        elseif st == "shop" then
            act = SCR.shop(dt, SV)
            if act == "buy" then save() elseif act == "back" then local b = G.shop_back; G.shop_back = nil; go(b or "title") end
        end
    end
    HUD.overlays(dt)
    U.end_frame()
    G.update_lights(dt)
    mouse_lock(G.state)
end
G.update = update
-- test hooks (driven from tools/lua.sh)
G.test.menu = to_menu
G.test.go = go
G.test.send = function(srcs, dst, r) return SIM.send(S, 1, srcs, dst, r or 1) end
G.test.sel = function(t) sel = {}; for _, i in ipairs(t or {}) do sel[i] = true end end
G.test.tgt = function(i) tgt = i; G.test.ftgt = i end
G.test.pan = function(x, z, zm) pan.x, pan.z = x or 0, z or 0; zoom = zm or zoom; zt = zoom end
G.test.LOCK = LOCK
G.test.unproject = function(x, y) return unproject(x, y, 0.5) end
G.test.cam = function() return { px = pan.x, pz = pan.z, zoom = zoom, zt = zt, ex = CAM.ex, ez = CAM.ez, lock = LOCK.on, api = LOCK.api and true or false } end
G.test.S = function() return S end
G.test.finish = function(win) S.over = true; S.win = win; S.forced = true; pe_log("[BB] test hook: forced " .. (win and "win" or "loss")); finish() end
hooks { update = update }
pe_log("[BB] ready")
end
