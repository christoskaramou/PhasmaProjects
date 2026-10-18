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
        border = border or { 0.35, 0.7, 1, 0.55 }, corner_radius = 12 * US, no_input = true, visible = vis ~= false })
end
local function button(id, label, cx, cy, vis)
    local w, h = 340 * US, 60 * US
    local st = vis and select(2, pcall(runtime_ui.get_state, UI, id))
    local hov = type(st) == "table" and st.hovered
    quad(id, { x = cx - w / 2, y = cy - h / 2, w = w, h = h, z = 12, style = "text", label = label,
        fill = hov and { 0.12, 0.3, 0.5, 0.92 } or { 0.05, 0.07, 0.1, 0.88 }, border = hov and { 0.6, 0.85, 1, 1 } or { 0.35, 0.65, 0.95, 0.9 },
        text_color = { 0.95, 0.95, 0.92, 1 }, font_scale = 1.25 * US, align_h = "center", align_v = "middle",
        corner_radius = 12 * US, visible = vis })
    return vis and type(st) == "table" and st.clicked
end
local function pad6(n) local s = tostring(floor(n)); return string.rep("0", max(0, 6 - #s)) .. s end
local RED, WHITE, CYAN, DIM, GOLD = { 1, .35, .3, 1 }, { 1, 1, 1, 1 }, { .5, .85, 1, 1 }, { .82, .8, .78, 1 }, { 1, .85, .45, 1 }
G.banner = { text = "", t = 0 }
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause" or st == "over" or st == "clear" or st == "intro") and not G.set_open
    local bh = 92 * US
    panel("hb", 20 * US, 12 * US, SW - 40 * US, bh, play, 0.62)
    local tcol = (G.time or 99) <= 10 and (floor(G.t * 4) % 2 == 0 and RED or WHITE) or WHITE
    text("htl", "TIME", 50 * US, 16 * US, 200 * US, 36 * US, 1.0, RED, "left", play)
    text("htv", tostring(math.ceil(G.time or 0)), 50 * US, 48 * US, 200 * US, 52 * US, 1.8, tcol, "left", play)
    text("hsl", "SCORE", 250 * US, 16 * US, 300 * US, 36 * US, 1.0, RED, "left", play)
    text("hsv", tostring(G.score), 250 * US, 48 * US, 300 * US, 52 * US, 1.8, WHITE, "left", play)
    local st_ = G.ST()
    text("hstg", st_ and string.format("Stage %d", st_.n) or "", SW / 2 - 200 * US, 16 * US, 400 * US, 40 * US, 1.3, CYAN, "center", play)
    local flags = {}
    if P.detonator then flags[#flags + 1] = "Detonator" end
    if P.wallpass then flags[#flags + 1] = "Wall Pass" end
    if P.bombpass then flags[#flags + 1] = "Bomb Pass" end
    if P.flamepass then flags[#flags + 1] = "Flame Pass" end
    if P.inv > 0 then flags[#flags + 1] = "Mystery " .. math.ceil(P.inv) end
    if P.speed > 0 then flags[#flags + 1] = "Speed" end
    text("hpu", string.format("Bombs %d  ·  Fire %d", P.bombs, P.fire) .. (#flags > 0 and ("  ·  " .. table.concat(flags, "  ·  ")) or ""),
        SW / 2 - 420 * US, 56 * US, 840 * US, 40 * US, 0.95, GOLD, "center", play)
    text("hel", "ENEMIES", SW - 560 * US, 16 * US, 200 * US, 36 * US, 1.0, RED, "left", play)
    text("hev", tostring(G.alive or 0), SW - 560 * US, 48 * US, 200 * US, 52 * US, 1.8, WHITE, "left", play)
    text("hll", "LEFT", SW - 360 * US, 16 * US, 140 * US, 36 * US, 1.0, RED, "left", play)
    local nl = G.lives - ((st == "play" and P.st ~= "dead") and 1 or 0)
    text("hlv", tostring(max(0, nl)), SW - 360 * US, 48 * US, 140 * US, 52 * US, 1.8, WHITE, "left", play)
    text("hh", "HIGH", SW - 220 * US, 16 * US, 170 * US, 36 * US, 1.0, RED, "right", play)
    text("hhs", tostring(max(G.hiscore, G.score)), SW - 300 * US, 48 * US, 250 * US, 52 * US, 1.6, WHITE, "right", play)
    -- popups
    for i, p in ipairs(G.POP) do
        p.t = p.t + dt
        local vis = (st == "play" or st == "clear") and not G.set_open and p.t < 1.1
        local px, py = 0, 0
        if vis then px, py = project(vec3(p.x * CS, 2.4 + p.t * 1.5, p.z * CS)) end
        local a = floor(clamp((1.1 - p.t) / 0.3, 0, 1) * 10) / 10
        text("pop" .. i, p.txt or "", px - 140 * US, py - 18 * US, 280 * US, 36 * US, 1.1, { p.col[1] or 1, p.col[2] or 1, p.col[3] or 1, a }, "center", vis)
    end
    G.banner.t = (G.banner.t or 0) - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    text("ban", G.banner.text or "", 0, SH * 0.42, SW, 80 * US, 2.4, { 1, .85, .5, ba }, "center", st == "play" and not G.set_open and G.banner.t > 0)
    -- stage card / clear
    local card = st == "intro" and not G.set_open
    -- light veil so the arena shows through, with a soft band behind the stage title
    panel("c_bg", 0, 0, SW, SH, card, 0.3, NONE)
    panel("c_band", 0, SH * 0.42 - 10 * US, SW, 160 * US, card, 0.42, NONE)
    text("c_stg", st_ and string.format("Stage %d", st_.n) or "", 0, SH * 0.42, SW, 100 * US, 3.2, WHITE, "center", card)
    text("c_pu", "", 0, SH * 0.42 + 100 * US, SW, 40 * US, 1.1, DIM, "center", card)
    local clr = st == "clear" and not G.set_open
    panel("k_bg", SW / 2 - 380 * US, SH * 0.32, 760 * US, 160 * US, clr, 0.6)
    text("k_t", "Stage Clear", 0, SH * 0.32 + 40 * US, SW, 80 * US, 2.6, GOLD, "center", clr)
    local dead = st == "play" and P.st == "dead" and (P.dead_t or 0) > 1.0 and not G.set_open and P.cause == "time"
    text("d_t", "Time Up", 0, SH * 0.4, SW, 80 * US, 2.6, RED, "center", dead)
    -- title
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 480 * US, SH * 0.06, 960 * US, SH * 0.84, title, 0.62)
    text("t_title", "Bomberman Remix", 0, SH * 0.08, SW, 130 * US, 4.4, { 1, .5, .3, 1 }, "center", title)
    text("t_sub", "Blast through 50 stages of bricks, find the exit and wipe out every enemy", 0, SH * 0.08 + 118 * US, SW, 40 * US, 1.05, DIM, "center", title)
    text("t_ctl1", "WASD or Arrow keys: walk   ·   Space / Z / J / Left Click: drop a bomb", 0, SH * 0.68, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_ctl2", "X / K / Right Click: Detonator (once you have it)   ·   find the exit under a brick", 0, SH * 0.68 + 34 * US, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_ctl3", "P / Esc: pause   ·   O: settings   ·   M: mute   ·   F3: colliders", 0, SH * 0.68 + 68 * US, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_hi", "High score " .. tostring(G.hiscore), 0, SH * 0.68 + 112 * US, SW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, CYAN, "center", pause)
    local over = st == "over" and not G.set_open
    local win = G.won
    panel("o_bg", SW / 2 - 380 * US, SH * 0.24, 760 * US, SH * 0.52, over, 0.78)
    text("o_t", win and "Congratulations" or "Game Over", 0, SH * 0.26, SW, 90 * US, 3.0, win and GOLD or RED, "center", over)
    text("o_s", "Score " .. tostring(G.score) .. "  ·  Stage " .. tostring(G.ST() and G.ST().n or 1), 0, SH * 0.26 + 90 * US, SW, 40 * US, 1.3, DIM, "center", over)
    local c = {}
    local hasc = title and (G.cont_stage or 1) > 1
    local yb = SH * 0.36
    c.start = button("b_start", "Start (Enter)", SW / 2, yb, title); yb = yb + 76 * US
    c.cont = button("b_cont", "Continue Stage " .. tostring(G.cont_stage or 1), SW / 2, yb, hasc); if hasc then yb = yb + 76 * US end
    c.set_t = button("b_set_t", "Settings (O)", SW / 2, yb, title); yb = yb + 76 * US
    c.quit_app = button("b_quit_app", "Quit Game", SW / 2, yb, title)
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
    G.stage_reset(1 + floor(rand() * 12))
    G.hide_player = true
    music("title")
end
G.to_title = to_title
local function start_stage(n, keep)
    G.stage_reset(n, keep); G.fx_clear(); G.CHUNKS = {}
    G.hide_player = false
    G.state = "intro"; G.intro_t = 0
    music(nil); sfx("ready")
end
G.start_stage = start_stage
local function new_game(n)
    G.score, G.lives = 0, 3
    start_stage(n or 1)
end
G.new_game = new_game
local function game_over(won)
    G.state = "over"; G.over_t = 0; G.won = won
    music(nil); sfx(won and "clear" or "gameover")
    if G.score > G.hiscore then G.hiscore = G.score; save_hi() end
end
G.cont_stage = 1
local acc = 0
G.bomb_q, G.det_q = false, false
local mouse_prev, rmouse_prev = true, true
local DIRK = { up = { "Up", "W" }, down = { "Down", "S" }, left = { "Left", "A" }, right = { "Right", "D" } }
local order = {}
local function update(dt)
    if G.on_frame then G.on_frame(dt) end
    G.fx_update(dt)
    flush_mats()
    dt = min(dt, 0.1)
    G.t = G.t + dt; G.dt = dt
    local k = { ret = edge("Return"), space = edge("Space"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), q = edge("Q"),
        z = edge("Z"), j = edge("J"), x = edge("X"), kk = edge("K"), f3 = edge("F3") }
    local md, rd = false, false
    pcall(function() md = input.is_left_mouse_down() and true or false end)
    pcall(function() rd = input.is_right_mouse_down and input.is_right_mouse_down() and true or false end)
    local mclick = md and not mouse_prev; mouse_prev = md
    local rclick = rd and not rmouse_prev; rmouse_prev = rd
    -- direction press order (newest first) for the "take whichever way is open" rule
    for nm, ks in pairs(DIRK) do
        local h = any(ks[1], ks[2])
        local idx = nil
        for i, o in ipairs(order) do if o == nm then idx = i end end
        if h and not idx then table.insert(order, 1, nm) elseif not h and idx then table.remove(order, idx) end
    end
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end; mclick = false; rclick = false end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        G.title_x = 32 + 18 * sin(G.t * 0.12)
        if k.ret or k.space or c.start then sfx("click"); new_game(1)
        elseif c.cont then sfx("click"); new_game(G.cont_stage)
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "intro" then
        G.intro_t = G.intro_t + dt
        if G.intro_t > 2.4 or ((k.ret or k.space or mclick) and G.intro_t > 0.4) then
            G.state = "play"; music("bgm" .. ((G.ST().n - 1) % 2 + 1)); G.bomb_q = false; G.det_q = false
        end
        if k.esc then to_title() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click") end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.q or c.quit then to_title() end
    elseif st == "clear" then
        G.clear_t = G.clear_t + dt
        if G.clear_t > 3.2 or ((k.ret or k.space) and G.clear_t > 0.8) then
            if G.ST().n >= 50 then game_over(true) else start_stage(G.ST().n + 1, true) end
        end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then sfx("click"); new_game(1)
            elseif k.esc or c.title then to_title() end
        end
    end
    st = G.state
    local running = (st == "play" or st == "title") and not (G.set_open and st ~= "title")
    if running then
        if (k.space or k.z or k.j or mclick) and st == "play" then G.bomb_q = true end
        if (k.x or k.kk or rclick) and st == "play" then G.det_q = true end
        local inp = { order = {}, bomb = false, det = false }
        if st == "play" then for i, o in ipairs(order) do inp.order[i] = o end end
        if G.autoplay and st == "play" then G.autoplay_fn(inp) end
        local god = G.god
        if st == "title" then G.god = true; G.time = 200 end
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 6 do
            inp.bomb = G.bomb_q; G.bomb_q = false
            inp.det = G.det_q; G.det_q = false
            G.stage_step(inp, FR)
            acc = acc - FR; n = n + 1
            if st == "play" and P.st == "walk" and G.at_exit() then
                G.state = "clear"; G.clear_t = 0; P.st = "win"
                G.cont_stage = max(G.cont_stage, min(50, G.ST().n + 1))
                music(nil); sfx("clear")
                break
            end
        end
        if st == "title" then G.god = god; if (G.alive or 1) == 0 then G.stage_reset(1 + floor(rand() * 12)) end end
        if acc > FR * 6 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if st == "play" and P.st == "dead" and P.dead_t >= 2.6 then
            G.lives = G.lives - 1
            if G.lives <= 0 then game_over(false) else start_stage(G.ST().n, true) end
        end
    else AL = 1 end
    if st == "clear" then
        -- keep flames/bricks animating and let him celebrate
        P.ox, P.oz = P.x, P.z
    end
    G.cam_ov = G.cam_ov_fixed
    update_camera(dt)
    render_dyn(dt)
    render_player(dt)
    update_flashes(dt)
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_world()
build_player()
G.autoplay_fn = function(inp)        -- debug bot for tests and screenshots only (G.autoplay = true)
    G.bot_t = (G.bot_t or 0) - G.dt
    if G.bot_t <= 0 then G.bot_t = 0.5 + rand(); G.bot_dir = ({ "up", "down", "left", "right" })[1 + floor(rand() * 4)] end
    inp.order[1] = G.bot_dir
    if rand() < 0.01 then G.bomb_q = true end
end
to_title()
G.update = update; G.SET = SET; G.surf = surf
hooks { update = update }
pe_log("[BM] ready")
