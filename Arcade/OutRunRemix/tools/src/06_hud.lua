------------------------------------------------------------------ HUD + menus (runtime_ui, pixel coords)
local UI = "hud"
runtime_ui.show(UI); pcall(runtime_ui.set_screen_overlay, UI, true)
local NONE = { 0, 0, 0, 0 }
local hc = {}
local US = SH / 1080
local function quad(id, o)
    local key = ""
    for _, k in ipairs({ "x", "y", "w", "h", "label", "visible", "font_scale" }) do key = key .. tostring(o[k]) .. "|" end
    if o.fill then key = key .. o.fill[1] .. o.fill[2] .. o.fill[3] .. o.fill[4] end
    if o.text_color then key = key .. o.text_color[4] end
    if hc[id] == key then return end
    hc[id] = key
    pcall(runtime_ui.set_quad, UI, id, o)
end
local function text(id, label, x, y, w, h, fs, col, align, vis)
    quad(id, { x = x, y = y, w = w, h = h, z = 10, style = "text", label = label, fill = NONE, border = NONE, text_color = col,
        font_scale = fs * US, align_h = align or "center", align_v = "middle", no_input = true, visible = vis ~= false })
end
local function panel(id, x, y, w, h, vis, a, border)
    quad(id, { x = x, y = y, w = w, h = h, z = 4, style = "text", label = "", fill = { 0.04, 0.04, 0.06, a or 0.55 },
        border = border or { 1, 0.55, 0.3, 0.55 }, corner_radius = 12 * US, no_input = true, visible = vis ~= false })
end
local function button(id, label, cx, cy, vis)
    local w, h = 340 * US, 60 * US
    local st = vis and select(2, pcall(runtime_ui.get_state, UI, id))
    local hov = type(st) == "table" and st.hovered
    quad(id, { x = cx - w / 2, y = cy - h / 2, w = w, h = h, z = 12, style = "text", label = label,
        fill = hov and { 0.55, 0.12, 0.08, 0.92 } or { 0.08, 0.05, 0.05, 0.85 }, border = hov and { 1, 0.75, 0.5, 1 } or { 1, 0.5, 0.3, 0.9 },
        text_color = { 0.95, 0.95, 0.92, 1 }, font_scale = 1.25 * US, align_h = "center", align_v = "middle",
        corner_radius = 12 * US, visible = vis })
    return vis and type(st) == "table" and st.clicked
end
local function pad6(n) local s = tostring(floor(n)); return string.rep("0", max(0, 6 - #s)) .. s end
local RED, WHITE, CYAN, DIM, GOLD = { 1, .35, .3, 1 }, { 1, 1, 1, 1 }, { .5, .85, 1, 1 }, { .85, .82, .78, 1 }, { 1, .85, .35, 1 }
local RADIO = { { "radio1", "Sunset Drive" }, { "radio2", "Coastal Breeze" }, { "radio3", "Summer Wave" } }
G.radio = 1
G.banner = { text = "", t = 0 }
local function fmt_t(t) local m = floor(t / 60); return string.format("%d'%05.2f\"", m, t - m * 60) end
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause" or st == "count" or st == "goal") and not G.set_open
    local cur = G.cur_stage
    -- top: score, time, lap
    text("hsl", "SCORE", 40 * US, 18 * US, 300 * US, 34 * US, 1.0, GOLD, "left", play)
    text("hsv", tostring(G.score), 40 * US, 50 * US, 420 * US, 56 * US, 1.9, WHITE, "left", play)
    local tl = math.ceil(G.time or 0)
    local tcol = (G.time or 99) <= 10 and (floor(G.t * 4) % 2 == 0 and RED or WHITE) or GOLD
    text("htl", "TIME", SW / 2 - 150 * US, 12 * US, 300 * US, 34 * US, 1.0, RED, "center", play)
    text("htv", tostring(max(0, tl)), SW / 2 - 150 * US, 40 * US, 300 * US, 90 * US, 3.4, tcol, "center", play)
    text("hll", "LAP", SW - 460 * US, 18 * US, 420 * US, 34 * US, 1.0, GOLD, "right", play)
    text("hlv", fmt_t(G.lap_t or 0), SW - 460 * US, 50 * US, 420 * US, 56 * US, 1.6, WHITE, "right", play)
    text("hstg", cur and string.format("Stage %d  ·  %s", cur.row, cur.name) or "", SW / 2 - 400 * US, 128 * US, 800 * US, 40 * US, 1.15, CYAN, "center", play)
    -- speed + gear
    local kmh = floor(P.v * 3.6 + 0.5)
    panel("hsp", SW - 380 * US, SH - 170 * US, 350 * US, 140 * US, play, 0.5)
    text("hkv", tostring(kmh), SW - 370 * US, SH - 165 * US, 220 * US, 90 * US, 3.0, WHITE, "right", play)
    text("hku", "km/h", SW - 145 * US, SH - 140 * US, 100 * US, 40 * US, 1.0, DIM, "left", play)
    text("hgr", P.gear == "L" and "LOW" or "HIGH", SW - 370 * US, SH - 82 * US, 330 * US, 44 * US, 1.3, P.gear == "L" and CYAN or GOLD, "center", play)
    local rpm = clamp(P.v / ((P.gear == "L") and G.CONST.VMAX_L or G.CONST.VMAX_H), 0, 1)
    for i = 1, 12 do
        quad("tach" .. i, { x = SW - 370 * US + (i - 1) * 27 * US, y = SH - 36 * US, w = 22 * US, h = 14 * US, z = 7, style = "text", label = "",
            fill = (i / 12 <= rpm) and (i > 9 and { 1, .3, .2, 1 } or { 1, .8, .3, 1 }) or { .2, .2, .2, .6 }, border = NONE, corner_radius = 3 * US, no_input = true, visible = play })
    end
    -- course map: 5 rows, the path so far highlighted
    local mx, my = 40 * US, SH - 200 * US
    panel("map", mx - 10 * US, my - 10 * US, 300 * US, 190 * US, play, 0.45)
    local path = {}
    for _, s2 in ipairs(G.STAGES) do path[s2.row] = s2.col end
    for r = 1, 5 do
        for c = 1, r do
            local on = path[r] == c
            local here = cur and cur.row == r and cur.col == c
            local px = mx + 140 * US + (c - (r + 1) / 2) * 54 * US
            quad("mp" .. r .. c, { x = px - 11 * US, y = my + (r - 1) * 34 * US, w = 22 * US, h = 22 * US, z = 7, style = "text", label = "",
                fill = here and (floor(G.t * 4) % 2 == 0 and { 1, .9, .3, 1 } or { 1, .4, .2, 1 }) or (on and { 1, .55, .25, 1 } or { .35, .35, .4, .8 }),
                border = { 1, 1, 1, .6 }, corner_radius = 11 * US, no_input = true, visible = play })
        end
    end
    text("mpg", "Goal " .. table.concat(G.GOALS, " "), mx, my + 166 * US, 280 * US, 30 * US, 0.8, DIM, "center", false)
    -- fork hint
    local a = G.seg_at(P.s)
    local fk = st == "play" and a and a.st.g1 and not a.st.side and a.st.row < 5 and floor(P.s / G.TC.SEG) + 1 >= a.st.g1 - 30 and not G.set_open
    local L = fk and G.ROUTE[a.st.row + 1][a.st.col][1] or ""
    local Rn = fk and G.ROUTE[a.st.row + 1][a.st.col + 1][1] or ""
    -- the tentative pick is gold and larger, the other branch dims; once locked, the chosen road is announced
    local pk = fk and a.st.pick
    local DIMW = { .75, .75, .78, .55 }
    text("fkl", "<  " .. L, SW / 2 - 620 * US, SH * 0.3, 560 * US, 50 * US, pk == -1 and 1.8 or 1.5, pk == -1 and GOLD or (pk and DIMW or WHITE), "right", fk)
    text("fkr", Rn .. "  >", SW / 2 + 60 * US, SH * 0.3, 560 * US, 50 * US, pk == 1 and 1.8 or 1.5, pk == 1 and GOLD or (pk and DIMW or WHITE), "left", fk)
    local lk = G.fork_lock
    if lk then lk.t = lk.t - dt; if lk.t <= 0 then G.fork_lock = nil; lk = nil end end
    local lka = lk and floor(clamp(lk.t / 0.4, 0, 1) * 20) / 20 or 0
    text("fklk", lk and ((lk.side < 0) and ("<  " .. lk.name) or (lk.name .. "  >")) or "", 0, SH * 0.3, SW, 50 * US, 1.8, { GOLD[1], GOLD[2], GOLD[3], lka }, "center", st == "play" and lk ~= nil and not G.set_open)
    G.banner.t = (G.banner.t or 0) - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    text("ban", G.banner.text or "", 0, SH * 0.22, SW, 90 * US, 3.0, { 1, .85, .35, ba }, "center", st == "play" and not G.set_open and G.banner.t > 0)
    -- countdown
    local cd = st == "count" and not G.set_open
    local n = 3 - floor(G.count_t or 0)
    text("cd", n > 0 and tostring(n) or "GO!", 0, SH * 0.34, SW, 160 * US, 6.0, n > 0 and WHITE or GOLD, "center", cd)
    text("cdr", "Radio: " .. RADIO[G.radio][2], 0, SH * 0.34 + 160 * US, SW, 40 * US, 1.2, DIM, "center", cd)
    -- goal / time up
    local gl = st == "goal" and not G.set_open
    panel("g_bg", SW / 2 - 420 * US, SH * 0.22, 840 * US, SH * 0.5, gl, 0.72)
    text("g_t", "Goal " .. tostring(G.goal or ""), 0, SH * 0.24, SW, 100 * US, 3.2, GOLD, "center", gl)
    local lt = {}
    for i, t in ipairs(G.laps or {}) do lt[#lt + 1] = string.format("Stage %d  %s", i, fmt_t(t)) end
    text("g_l", table.concat(lt, "   "), SW / 2 - 400 * US, SH * 0.24 + 110 * US, 800 * US, 40 * US, 0.9, DIM, "center", gl)
    text("g_b", "Time Bonus  " .. tostring(G.bonus or 0), 0, SH * 0.24 + 160 * US, SW, 50 * US, 1.5, WHITE, "center", gl)
    text("g_s", "Score  " .. tostring(G.score), 0, SH * 0.24 + 215 * US, SW, 50 * US, 1.5, WHITE, "center", gl)
    -- title
    local title = st == "title" and not G.set_open
    local TX, TW = SW * 0.53, SW * 0.44
    panel("t_bg", TX, SH * 0.05, TW, SH * 0.9, title, 0.6)
    text("t_title", "Out Run Remix", TX, SH * 0.07, TW, 120 * US, 3.8, { 1, .45, .25, 1 }, "center", title)
    text("t_sub", "Pick a road at every fork and reach a goal", TX, SH * 0.07 + 108 * US, TW, 36 * US, 1.0, DIM, "center", title)
    text("t_sub2", "before the time runs out", TX, SH * 0.07 + 140 * US, TW, 36 * US, 1.0, DIM, "center", title)
    local CL = { "W / Up: accelerate   ·   S / Down: brake", "A / D or Left / Right: steer", "Space / Shift / Right Click: gear (Low / High)",
        "Left / Right on this screen: radio", "P / Esc: pause  ·  O: settings  ·  M: mute  ·  F3: colliders" }
    for i, l in ipairs(CL) do text("t_ctl" .. i, l, TX, SH * 0.64 + (i - 1) * 32 * US, TW, 32 * US, 0.9, DIM, "center", title) end
    text("t_hi", "High score " .. tostring(G.hiscore), TX, SH * 0.64 + 172 * US, TW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, GOLD, "center", pause)
    local over = st == "over" and not G.set_open
    panel("o_bg", SW / 2 - 380 * US, SH * 0.24, 760 * US, SH * 0.52, over, 0.78)
    text("o_t", G.won and ("Goal " .. tostring(G.goal)) or "Game Over", 0, SH * 0.26, SW, 90 * US, 3.0, G.won and GOLD or RED, "center", over)
    text("o_s", "Score " .. tostring(G.score) .. (cur and ("  ·  " .. cur.name) or ""), 0, SH * 0.26 + 90 * US, SW, 40 * US, 1.3, DIM, "center", over)
    local c = {}
    local yb = SH * 0.36
    c.start = button("b_start", "Start (Enter)", SW * 0.75, yb, title); yb = yb + 76 * US
    c.radio = button("b_radio", "Radio: " .. RADIO[G.radio][2], SW * 0.75, yb, title); yb = yb + 76 * US
    c.set_t = button("b_set_t", "Settings (O)", SW * 0.75, yb, title); yb = yb + 76 * US
    c.quit_app = button("b_quit_app", "Quit Game", SW * 0.75, yb, title)
    c.resume = button("b_resume", "Resume (P)", SW / 2, SH * 0.42, pause)
    c.set_p = button("b_set_p", "Settings (O)", SW / 2, SH * 0.42 + 76 * US, pause)
    c.quit = button("b_quit", "Quit to Title (Q)", SW / 2, SH * 0.42 + 152 * US, pause)
    local ov = over and (G.over_t or 0) > 1.2
    c.again = button("b_again", "Play Again (Enter)", SW / 2, SH * 0.5, ov)
    c.title = button("b_title", "Title (Esc)", SW / 2, SH * 0.5 + 76 * US, ov)
    return c
end

------------------------------------------------------------------ flow
local function to_title()
    G.state = "title"; G.won = false; G.cam_ov = nil
    G.race_reset()
    music("title")
end
G.to_title = to_title
local function new_game()
    G.score = 0
    G.race_reset()
    G.state = "count"; G.count_t = 0; G.beeped = -1
    music(RADIO[G.radio][1])
end
G.new_game = new_game
local function game_over(won)
    G.state = "over"; G.over_t = 0; G.won = won
    if not won then music(nil) end
    if G.score > G.hiscore then G.hiscore = G.score; save_hi() end
end
local acc = 0
G.shift_q = false
local rmouse_prev = true
local function update(dt)
    flush_mats()
    dt = clamp(dt, 0, 0.1)   -- a negative frame time (timer hitch) would make every damp() explode
    G.t = G.t + dt; G.dt = dt
    local k = { ret = edge("Return"), space = edge("Space"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), q = edge("Q"),
        sh = edge("LeftShift"), sh2 = edge("RightShift"), left = edge("Left"), right = edge("Right"), f3 = edge("F3") }
    local rd = false
    pcall(function() rd = input.is_right_mouse_down and input.is_right_mouse_down() and true or false end)
    local rclick = rd and not rmouse_prev; rmouse_prev = rd
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end; rclick = false end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        if k.ret or k.space or c.start then sfx("click"); new_game()
        elseif c.radio or k.right then sfx("click"); G.radio = G.radio % #RADIO + 1; music(RADIO[G.radio][1])
        elseif k.left then sfx("click"); G.radio = (G.radio - 2) % #RADIO + 1; music(RADIO[G.radio][1])
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "count" then
        G.count_t = G.count_t + dt
        local n = floor(G.count_t)
        if n ~= G.beeped then G.beeped = n; if n < 3 then sfx("beep") elseif n == 3 then sfx("go") end end
        if G.count_t >= 3 then G.state = "play"; G.shift_q = false end
        if k.esc then to_title() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click") end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.q or c.quit then to_title() end
    elseif st == "goal" then
        G.goal_t = G.goal_t + dt
        if G.goal_t > 1.5 and not G.bonus_given then G.bonus_given = true; add_score(G.bonus) end
        if G.goal_t > 6 or ((k.ret or k.space) and G.goal_t > 2) then game_over(true) end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then sfx("click"); new_game()
            elseif k.esc or c.title then to_title() end
        end
    end
    st = G.state
    local running = (st == "play" or st == "goal" or st == "count" or st == "title") and not (G.set_open and st ~= "title")
    if running then
        if (k.space or k.sh or k.sh2 or rclick) and st == "play" then G.shift_q = true end
        local inp = { h = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0), gas = any("Up", "W"), brake = any("Down", "S"), shift = false }
        if st ~= "play" then inp.h, inp.gas, inp.brake = 0, false, false end
        if G.autoplay and st == "play" then
            inp.gas = true; local a = G.seg_at(P.s); local tx = (a and a.fork and not a.st.side) and (G.auto_side or 1) * a.fork or 0
            inp.h = clamp((tx - P.x) * 0.3 - (a and a.curve or 0) * 0.5, -1, 1)
            if P.gear == "L" and P.v > 45 then G.shift_q = true end
        end
        if G.test_inp and st == "play" then for kk, vv in pairs(G.test_inp) do inp[kk] = vv end end   -- MCP test hook
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 6 do
            inp.shift = G.shift_q; G.shift_q = false
            P.os, P.ox = P.s, P.x
            if st == "play" or st == "goal" then G.stage_step(inp, FR) end
            acc = acc - FR; n = n + 1
        end
        if acc > FR * 6 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if st == "play" and P.st == "goal" then G.state = "goal"; G.goal_t = 0; G.bonus_given = false end
        if st == "play" and P.st == "timeup" and P.v < 0.5 and P.t > 2 then game_over(false) end
    else AL = 1 end
    -- engine note: short grains whose pitch follows the revs
    if (st == "play" or st == "count" or st == "goal") and not G.set_open then
        G.eng_t = (G.eng_t or 0) - dt
        if G.eng_t <= 0 then
            G.eng_t = 0.1
            local rpm = clamp(P.v / ((P.gear == "L") and G.CONST.VMAX_L or G.CONST.VMAX_H), 0, 1)
            if st == "count" then rpm = 0.25 + 0.15 * sin(G.t * 9) end
            local bin = clamp(floor(rpm * 7 + ((P.gear == "H") and 2.5 or 0) * rpm), 0, 9)
            sfx("eng" .. bin)
        end
    end
    if st == "title" then
        local p = world_at(P.s, 0, 0)
        local _, yaw = world_at(P.s, 0, 0)
        local ang = math.rad(yaw + 145 + 25 * sin(G.t * 0.2))
        local cx, cz = p.x + 8.5 * sin(ang), p.z + 8.5 * cos(ang)
        local dx, dz = p.x - cx, p.z - cz; local dl = math.sqrt(dx * dx + dz * dz)
        local rx, rz = -dz / dl, dx / dl
        G.cam_ov = { cx, p.y + 2.6, cz, p.x + rx * 3.6, p.y + 0.9, p.z + rz * 3.6 }
    else G.cam_ov = G.cam_ov_fixed end
    local gcur = floor(P.s / G.TC.SEG) + 1
    render_road(gcur)
    render_scenery(gcur)
    local carp, yaw = render_car(dt)
    render_traffic(dt)
    update_camera(dt, carp, yaw)
    update_lights(dt, carp)
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_world()
build_car()
to_title()
G.update = update; G.SET = SET; G.surf = surf
hooks { update = update }
pe_log("[OR] ready")
