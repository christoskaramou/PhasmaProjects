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
    quad(id, { x = x, y = y, w = w, h = h, z = 4, style = "text", label = "", fill = { 0.03, 0.03, 0.05, a or 0.55 },
        border = border or { 0.95, 0.35, 0.3, 0.55 }, corner_radius = 12 * US, no_input = true, visible = vis ~= false })
end
local function button(id, label, cx, cy, vis)
    local w, h = 340 * US, 60 * US
    local st = vis and select(2, pcall(runtime_ui.get_state, UI, id))
    local hov = type(st) == "table" and st.hovered
    quad(id, { x = cx - w / 2, y = cy - h / 2, w = w, h = h, z = 12, style = "text", label = label,
        fill = hov and { 0.45, 0.1, 0.08, 0.92 } or { 0.08, 0.05, 0.06, 0.88 }, border = hov and { 1, 0.6, 0.45, 1 } or { 0.85, 0.35, 0.3, 0.9 },
        text_color = hov and { 1, 0.95, 0.85, 1 } or { 0.95, 0.9, 0.85, 1 }, font_scale = 1.25 * US, align_h = "center", align_v = "middle",
        corner_radius = 12 * US, visible = vis })
    return vis and type(st) == "table" and st.clicked
end
local function pad6(n) local s = tostring(floor(n)); return string.rep("0", max(0, 6 - #s)) .. s end
local RED, WHITE, CYAN, DIM, GOLD = { 1, .3, .25, 1 }, { 1, 1, 1, 1 }, { .45, .9, 1, 1 }, { .78, .76, .74, 1 }, { 1, .85, .45, 1 }
G.banner = { text = "", t = 0 }
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause" or st == "over" or st == "clear" or st == "howhigh" or st == "intro") and not G.set_open
    local lx = to_screen(0, 0)
    local rx = to_screen(224, 0)
    local lw = lx - 60 * US
    -- left: scores
    panel("hl", 30 * US, 40 * US, lw, 230 * US, play, 0.45)
    text("h1", "1UP", 50 * US, 50 * US, lw - 40 * US, 44 * US, 1.4, RED, "left", play)
    text("h1s", pad6(G.score), 50 * US, 92 * US, lw - 40 * US, 56 * US, 2.0, WHITE, "left", play)
    text("hh", "HIGH SCORE", 50 * US, 156 * US, lw - 40 * US, 40 * US, 1.1, RED, "left", play)
    text("hhs", pad6(max(G.hiscore, G.score)), 50 * US, 196 * US, lw - 40 * US, 52 * US, 1.7, WHITE, "left", play)
    -- right: level, bonus, lives, height
    local rw = SW - rx - 60 * US
    local rx0 = rx + 30 * US
    panel("hr", rx0, 40 * US, rw, 330 * US, play, 0.45)
    text("lv", string.format("L=%02d", G.level), rx0 + 20 * US, 50 * US, rw - 40 * US, 46 * US, 1.5, CYAN, "left", play)
    text("ht", ST and ST.height or "", rx0 + 20 * US, 50 * US, rw - 40 * US, 46 * US, 1.5, GOLD, "right", play)
    quad("bbox", { x = rx0 + 20 * US, y = 110 * US, w = rw - 40 * US, h = 110 * US, z = 6, style = "text", label = "", fill = { 0.02, 0.03, 0.1, 0.7 },
        border = { 0.3, 0.55, 1, 0.9 }, corner_radius = 8 * US, no_input = true, visible = play })
    text("bt", "BONUS", rx0 + 20 * US, 116 * US, rw - 40 * US, 36 * US, 1.0, CYAN, "center", play)
    local bcol = (G.bonus or 0) <= 1000 and (floor(G.t * 4) % 2 == 0 and RED or WHITE) or WHITE
    text("bv", tostring(G.bonus or 0), rx0 + 20 * US, 152 * US, rw - 40 * US, 60 * US, 2.2, bcol, "center", play)
    text("lvs", "Lives", rx0 + 20 * US, 236 * US, rw - 40 * US, 36 * US, 1.0, DIM, "left", play)
    for i = 1, 8 do
        quad("life" .. i, { x = rx0 + 24 * US + (i - 1) * 34 * US, y = 280 * US, w = 24 * US, h = 24 * US, z = 7, style = "text", label = "",
            fill = { 0.9, 0.12, 0.08, 0.95 }, border = { 1, 0.85, 0.7, 1 }, corner_radius = 12 * US, no_input = true, visible = play and i <= G.lives - ((st == "play" and M.st ~= "dead") and 1 or 0) })
    end
    local ham = play and st == "play" and M.ham > 0
    quad("hambar", { x = rx0 + 20 * US, y = 326 * US, w = (rw - 40 * US) * clamp(M.ham / 600, 0, 1), h = 12 * US, z = 7, style = "text", label = "",
        fill = { 1, 0.6, 0.2, 0.9 }, border = NONE, corner_radius = 6 * US, no_input = true, visible = ham })
    -- Pauline's "HELP!"
    local help = (st == "play" or st == "title" or st == "intro") and not G.set_open and PAUL.help > 0 and not G.paul_hidden and not PAUL.carried
    local hx, hy = to_screen(PAUL.x + 22, PAUL.y - 20)
    text("help", "HELP!", hx - 80 * US, hy - 20 * US, 160 * US, 40 * US, 1.2, { 1, .55, .75, 1 }, "center", help)
    -- score popups
    for i, p in ipairs(G.POP) do
        p.t = p.t + dt
        local vis = (st == "play" or st == "clear") and not G.set_open and p.t < 1.0
        local px, py = 0, 0
        if vis then px, py = to_screen(p.x, p.y - p.t * 10) end
        local a = floor(clamp((1.0 - p.t) / 0.3, 0, 1) * 10) / 10
        text("pop" .. i, p.txt or "", px - 100 * US, py - 18 * US, 200 * US, 36 * US, 1.1, { p.col[1] or 1, p.col[2] or 1, p.col[3] or 1, a }, "center", vis)
    end
    G.banner.t = G.banner.t - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    text("ban", G.banner.text, 0, SH * 0.42, SW, 80 * US, 2.4, { 1, .9, .6, ba }, "center", (st == "play" or st == "clear") and not G.set_open and G.banner.t > 0)
    -- how high
    local hh = st == "howhigh" and not G.set_open
    text("hh_t", "How High Can You Get?", 0, SH * 0.84, SW, 80 * US, 2.4, WHITE, "center", hh)
    for i = 1, 4 do
        local vis = hh and i <= (G.hh_n or 0)
        local sx, sy = SW / 2 + 300 * US, 0
        if vis then
            local hh_half = 30 * math.tan(VFOV / 2)
            sy = SH / 2 - ((-9 + (i - 1) * 5.6 + 1.8) - (-9 + ((G.hh_n or 1) - 1) * 2.8 + 1.5)) / hh_half * SH / 2
        end
        text("hh_m" .. i, (i * 25) .. " m", sx - 100 * US, sy - 25 * US, 200 * US, 50 * US, 1.8, i == (G.hh_n or 0) and GOLD or DIM, "left", vis)
    end
    text("skip", "Enter / Space / Click: skip", 0, SH - 60 * US, SW, 36 * US, 0.9, DIM, "center", (st == "intro") and not G.set_open)
    -- title
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 480 * US, SH * 0.08, 960 * US, SH * 0.8, title, 0.62)
    text("t_title", "Donkey Kong Remix", 0, SH * 0.1, SW, 130 * US, 4.4, { 1, .4, .3, 1 }, "center", title)
    text("t_sub", "Climb the girders, dodge the barrels and rescue Pauline", 0, SH * 0.1 + 118 * US, SW, 40 * US, 1.15, DIM, "center", title)
    text("t_ctl1", "A / D or Left / Right: walk   ·   W / S or Up / Down: climb ladders", 0, SH * 0.66, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_ctl2", "Space / Z / J: jump   ·   Grab a hammer to smash barrels and fireballs", 0, SH * 0.66 + 34 * US, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_ctl3", "P / Esc: pause   ·   O: settings   ·   M: mute   ·   F3: colliders   ·   Mouse: click any button", 0, SH * 0.66 + 68 * US, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_hi", "High score " .. pad6(G.hiscore), 0, SH * 0.66 + 112 * US, SW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.28, 600 * US, SH * 0.44, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.3, SW, 80 * US, 2.6, { 1, .45, .35, 1 }, "center", pause)
    local over = st == "over" and not G.set_open
    panel("o_bg", SW / 2 - 360 * US, SH * 0.26, 720 * US, SH * 0.5, over, 0.78)
    text("o_t", "Game Over", 0, SH * 0.28, SW, 90 * US, 3.0, { 1, .4, .3, 1 }, "center", over)
    text("o_s", "Score " .. pad6(G.score) .. "  ·  L=" .. string.format("%02d", G.level), 0, SH * 0.28 + 90 * US, SW, 40 * US, 1.3, DIM, "center", over)
    local c = {}
    c.start = button("b_start", "Start (Enter)", SW / 2, SH * 0.4, title)
    c.set_t = button("b_set_t", "Settings (O)", SW / 2, SH * 0.4 + 76 * US, title)
    c.quit_app = button("b_quit_app", "Quit Game", SW / 2, SH * 0.4 + 152 * US, title)
    c.resume = button("b_resume", "Resume (P)", SW / 2, SH * 0.44, pause)
    c.set_p = button("b_set_p", "Settings (O)", SW / 2, SH * 0.44 + 76 * US, pause)
    c.quit = button("b_quit", "Quit to Title (Q)", SW / 2, SH * 0.44 + 152 * US, pause)
    local ov = over and (G.over_t or 0) > 1.2
    c.again = button("b_again", "Play Again (Enter)", SW / 2, SH * 0.5, ov)
    c.title = button("b_title", "Title (Esc)", SW / 2, SH * 0.5 + 76 * US, ov)
    return c
end

------------------------------------------------------------------ main loop
local function to_title()
    clear_ents()
    build_stage("25")
    G.state = "title"; G.attract = true; G.cut = nil; G.cam_ov = nil
    G.kong_hidden, G.paul_hidden, G.stack_hidden = false, false, false
    for _, h in ipairs(RIGS.hh) do h.root:set_position(HIDE) end
    KONG.x, KONG.y = 44, 84; KONG.st = "idle"; KONG.t = 60; KONG.throws = 0
    PAUL.x, PAUL.y = 112, 56; PAUL.carried = nil; PAUL.yaw = nil
    G.first_done = true
    M.st = "hidden"; M.ham = 0; M.x = -100; M.y = 400
    music(nil)
end
G.to_title = to_title
local function new_game()
    G.score, G.lives, G.level, G.seq_i = 0, 3, 1, 1; G.bonus = 5000
    intro_start()
end
G.new_game = new_game
local acc = 0
G.jump_q = false
local function update(dt)
    flush_mats()
    dt = min(dt, 0.1)
    G.t = G.t + dt; G.dt = dt
    local k = { ret = edge("Return"), space = edge("Space"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), q = edge("Q"),
        z = edge("Z"), j = edge("J"), f3 = edge("F3") }
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    local md = false
    pcall(function() md = input.is_left_mouse_down() and true or false end)
    local mouse_click = md and not G.mouse_prev; G.mouse_prev = md
    if st == "title" then
        if k.ret or k.space or c.start then sfx("click"); new_game()
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "intro" then
        if (k.ret or k.space or k.z or (mouse_click and not G.set_open)) and G.cut and G.cut.t > 0.3 then
            G.cut = nil; G.bend_all(1); for _, l in ipairs(ST.ladders) do l.hidden = false end; for _, d in ipairs(ST.deco_ladders) do d.hidden = false end
            G.refresh_ladders(); for _, n in ipairs(G.intro_lad) do n:set_position(HIDE) end; P_begin("rung_i"); P_end("rung_i")
            G.seq_i = 1; how_high(seq()[1])
        end
        if k.esc then to_title() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click") end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.q or c.quit then to_title() end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then sfx("click"); new_game()
            elseif k.esc or c.title then to_title() end
        end
    elseif st == "howhigh" then
        G.hh_t = G.hh_t + dt
        G.cam_ov = { HHX, -9 + (G.hh_n - 1) * 2.8 + 1.5, 30, HHX, -9 + (G.hh_n - 1) * 2.8 + 1.5, 0 }
        if G.hh_t > 2.8 or ((k.ret or k.space) and G.hh_t > 0.4) then start_stage(G.hh_kind) end
    end
    st = G.state
    -- Pauline calls for help now and then
    PAUL.t = PAUL.t + dt
    if PAUL.help > 0 then PAUL.help = PAUL.help - dt elseif PAUL.t > 4.2 and (st == "play" or st == "title") then PAUL.t = 0; PAUL.help = 1.6 end
    if st == "intro" and G.cut then intro_update(dt) end
    if st == "clear" and G.cut then clear_update(dt) end
    local running = (st == "play" or st == "title") and not (G.set_open and st ~= "title") and not G.freeze
    if running then
        if (k.space or k.z or k.j) and st == "play" then G.jump_q = true end
        local inp = { h = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0), v = (any("Down", "S") and 1 or 0) - (any("Up", "W") and 1 or 0), jump = false }
        if st ~= "play" then inp.h, inp.v = 0, 0 end
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 6 do
            inp.jump = G.jump_q; G.jump_q = false
            stage_step(inp)
            acc = acc - FR; n = n + 1
            if G.state ~= st then break end
            if st == "play" and M.st ~= "dead" and ST.goal(M) and M.st == "walk" then clear_start(); break end
            if st == "play" and ST.kind == "100" and ST.rivets_left <= 0 and M.st ~= "dead" then clear_start(); break end
        end
        if acc > FR * 6 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if st == "play" and M.st == "dead" and M.dead_f >= 160 then
            G.lives = G.lives - 1
            if G.lives <= 0 then
                G.state = "over"; G.over_t = 0
                if G.score > G.hiscore then G.hiscore = G.score; save_hi() end
            else start_stage(ST.kind) end
        end
    else AL = 1 end
    if G.score > G.hiscore and st == "over" then G.hiscore = G.score; save_hi() end
    if st ~= "howhigh" then G.cam_ov = G.cam_ov_fixed end
    update_camera(dt)
    render_stage(dt)
    render_ents(dt)
    render_mario(dt)
    render_kong(dt)
    render_pauline(dt)
    update_flashes(dt)
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_backdrop()
build_rigs()
build_fx()
G.hh_g = {}
for i = 1, 12 do G.hh_g[i] = clone("g_red") end
to_title()
G.update = update; G.SET = SET; G.WX, G.WY = WX, WY; G.surf = surf; G.build_stage = build_stage; G.how_high = how_high
G.state_set = function(s) G.state = s; G.over_t = 5 end
hooks { update = update }
pe_log("[DK] ready")
