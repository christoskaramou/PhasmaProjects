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
local RED, WHITE, CYAN, DIM, GOLD = { 1, .35, .3, 1 }, { 1, 1, 1, 1 }, { .5, .85, 1, 1 }, { .8, .78, .75, 1 }, { 1, .85, .45, 1 }
local WNAME = { wire = "Wire", double = "Double Wire", power = "Power Wire", vulcan = "Vulcan Missile" }
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause" or st == "over" or st == "clear" or st == "intro") and not G.set_open
    -- bottom strip under the play field
    local _, fy = to_screen(0, -3.1)
    local by = min(fy, SH - 120 * US)
    local bh = SH - by - 10 * US
    panel("hb", 20 * US, by, SW - 40 * US, bh, play, 0.6)
    local cy = by + 8 * US
    text("h1", "1UP", 50 * US, cy, 200 * US, 40 * US, 1.3, RED, "left", play)
    text("h1s", pad6(G.score), 50 * US, cy + 38 * US, 300 * US, 52 * US, 1.9, WHITE, "left", play)
    local nl = G.lives - ((st == "play" and P.st ~= "dead") and 1 or 0)
    for i = 1, 6 do
        quad("life" .. i, { x = 360 * US + (i - 1) * 34 * US, y = cy + 52 * US, w = 26 * US, h = 22 * US, z = 7, style = "text", label = "",
            fill = { 0.93, 0.88, 0.74, 0.95 }, border = { 0.5, 0.35, 0.2, 1 }, corner_radius = 11 * US, no_input = true, visible = play and i <= nl })
    end
    local d = ST and ST.def
    local loc = d and LOCS[d.loc][2] or ""
    text("hloc", loc, SW / 2 - 300 * US, cy, 600 * US, 44 * US, 1.4, CYAN, "center", play)
    text("hstg", d and string.format("Stage %d", d.n) or "", SW / 2 - 300 * US, cy + 44 * US, 600 * US, 40 * US, 1.1, DIM, "center", play)
    local tcol = (G.time or 99) <= 15 and (floor(G.t * 4) % 2 == 0 and RED or WHITE) or WHITE
    text("htl", "TIME", SW / 2 + 330 * US, cy, 200 * US, 40 * US, 1.1, RED, "left", play)
    text("htv", tostring(math.ceil(G.time or 0)), SW / 2 + 330 * US, cy + 38 * US, 200 * US, 52 * US, 1.9, tcol, "left", play)
    local wtxt = WNAME[P.weapon] .. (P.shield and "  +  Shield" or "")
    if (G.freeze_t or 0) > 0 then wtxt = wtxt .. "  ·  Time Stop" elseif (G.slow_t or 0) > 0 then wtxt = wtxt .. "  ·  Slow" end
    text("hw", wtxt, SW / 2 + 500 * US, cy + 50 * US, 420 * US, 36 * US, 0.95, GOLD, "left", play and SW > 1500 * US)
    text("hh", "HIGH", SW - 380 * US, cy, 330 * US, 40 * US, 1.1, RED, "right", play)
    text("hhs", pad6(max(G.hiscore, G.score)), SW - 380 * US, cy + 38 * US, 330 * US, 52 * US, 1.6, WHITE, "right", play)
    -- popups
    for i, p in ipairs(G.POP) do
        p.t = p.t + dt
        local vis = (st == "play" or st == "clear") and not G.set_open and p.t < 1.0
        local px, py = 0, 0
        if vis then px, py = to_screen(p.x, p.y + p.t * 2) end
        local a = floor(clamp((1.0 - p.t) / 0.3, 0, 1) * 10) / 10
        text("pop" .. i, p.txt or "", px - 140 * US, py - 18 * US, 280 * US, 36 * US, 1.1, { p.col[1] or 1, p.col[2] or 1, p.col[3] or 1, a }, "center", vis)
    end
    -- stage card / ready / clear
    local card = st == "intro" and not G.set_open
    panel("c_bg", SW / 2 - 380 * US, SH * 0.3, 760 * US, 220 * US, card, 0.6)
    text("c_loc", loc, 0, SH * 0.3 + 20 * US, SW, 80 * US, 2.6, WHITE, "center", card)
    text("c_stg", d and string.format("Stage %d", d.n) or "", 0, SH * 0.3 + 100 * US, SW, 50 * US, 1.5, CYAN, "center", card)
    text("c_rdy", "Ready", 0, SH * 0.3 + 150 * US, SW, 50 * US, 1.5, GOLD, "center", card and (G.intro_t or 0) > 1.0)
    local clr = st == "clear" and not G.set_open
    panel("k_bg", SW / 2 - 380 * US, SH * 0.3, 760 * US, 220 * US, clr, 0.6)
    text("k_t", "Stage Clear", 0, SH * 0.3 + 20 * US, SW, 80 * US, 2.6, GOLD, "center", clr)
    text("k_b", "Time Bonus  " .. tostring(G.tbonus or 0), 0, SH * 0.3 + 110 * US, SW, 50 * US, 1.5, WHITE, "center", clr)
    local dead = st == "play" and P.st == "dead" and (P.dead_t or 0) > 0.8 and not G.set_open
    text("d_t", P.cause == "time" and "Time Over" or "", 0, SH * 0.4, SW, 80 * US, 2.6, RED, "center", dead)
    -- death hit flash: a brief white screen flash that fades over the hit-stop
    G.hit_flash = max(0, (G.hit_flash or 0) - dt * 4.5)
    local hf = G.hit_flash
    quad("hitfl", { x = 0, y = 0, w = SW, h = SH, z = 3, style = "text", label = "", fill = { 1, .97, .9, 0.55 * hf * hf }, border = NONE,
        no_input = true, visible = hf > 0.01 })
    -- title
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 480 * US, SH * 0.06, 960 * US, SH * 0.84, title, 0.62)
    text("t_title", "Pang Remix", 0, SH * 0.08, SW, 130 * US, 4.4, { 1, .45, .35, 1 }, "center", title)
    text("t_sub", "Fire your wire straight up and split every balloon, around the world in 50 stages", 0, SH * 0.08 + 118 * US, SW, 40 * US, 1.05, DIM, "center", title)
    text("t_ctl1", "A / D or Left / Right: walk   ·   W / S or Up / Down: climb ladders", 0, SH * 0.68, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_ctl2", "Space / Z / J / Left Click: fire   ·   hold for the Vulcan Missile", 0, SH * 0.68 + 34 * US, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_ctl3", "P / Esc: pause   ·   O: settings   ·   M: mute   ·   F3: colliders", 0, SH * 0.68 + 68 * US, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_hi", "High score " .. pad6(G.hiscore), 0, SH * 0.68 + 112 * US, SW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, CYAN, "center", pause)
    local over = st == "over" and not G.set_open
    local win = G.won
    panel("o_bg", SW / 2 - 380 * US, SH * 0.24, 760 * US, SH * 0.52, over, 0.78)
    text("o_t", win and "Congratulations" or "Game Over", 0, SH * 0.26, SW, 90 * US, 3.0, win and GOLD or RED, "center", over)
    text("o_s", "Score " .. pad6(G.score) .. "  ·  Stage " .. tostring(ST and ST.n or 1), 0, SH * 0.26 + 90 * US, SW, 40 * US, 1.3, DIM, "center", over)
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
    G.stage_reset(1 + floor(rand() * 9))
    G.hide_player = true
    music("title")
end
G.to_title = to_title
local function start_stage(n)
    G.stage_reset(n)
    G.hide_player = false
    G.state = "intro"; G.intro_t = 0
    music(nil); sfx("ready")
end
G.start_stage = start_stage
local function new_game(n)
    G.score, G.lives = 0, 3; G.extra_at = 20000
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
G.fire_q = false
local mouse_prev = true
local function update(dt)
    if G.on_frame then G.on_frame(dt) end
    flush_mats()
    dt = min(dt, 0.1)
    G.t = G.t + dt; G.dt = dt
    local k = { ret = edge("Return"), space = edge("Space"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), q = edge("Q"),
        z = edge("Z"), j = edge("J"), f3 = edge("F3") }
    local md = false
    pcall(function() md = input.is_left_mouse_down() and true or false end)
    local mclick = md and not mouse_prev; mouse_prev = md
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end; mclick = false end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        if k.ret or k.space or c.start then sfx("click"); new_game(1)
        elseif c.cont then sfx("click"); new_game(G.cont_stage)
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "intro" then
        G.intro_t = G.intro_t + dt
        if G.intro_t > 2.2 or ((k.ret or k.space or mclick) and G.intro_t > 0.4) then
            G.state = "play"; music("bgm" .. ((ST.def.loc - 1) % 4 + 1)); G.fire_q = false
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
        if G.clear_t > 3.0 or ((k.ret or k.space) and G.clear_t > 0.8) then
            if ST.n >= 50 then game_over(true) else start_stage(ST.n + 1) end
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
        if (k.space or k.z or k.j or mclick) and st == "play" then G.fire_q = true end
        local inp = { h = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0), v = (any("Up", "W") and 1 or 0) - (any("Down", "S") and 1 or 0),
            fire = false, fire_held = any("Space", "Z", "J") or md }
        if st ~= "play" then inp.h, inp.v, inp.fire_held = 0, 0, false end
        if G.autoplay and st == "play" then   -- debug bot (tests / screenshots only)
            local tb, bd = nil, 1e9
            for _, b in ipairs(BALLS) do local d = abs(b.x - P.x) + b.y * 0.2; if d < bd then bd, tb = d, b end end
            if tb then local dx = tb.x - (P.x + tb.vx * 0.25); inp.h = abs(dx) > 0.4 and (dx > 0 and 1 or -1) or 0 end
            G.fire_q = true; inp.fire_held = true
        end
        local god = G.god
        if st == "title" then G.god = true; G.time = 99; P.x = -100 end
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 6 do
            inp.fire = G.fire_q; G.fire_q = false
            G.stage_step(inp, FR)
            acc = acc - FR; n = n + 1
            if st == "play" and #BALLS == 0 and P.st ~= "dead" then
                G.state = "clear"; G.clear_t = 0
                G.tbonus = floor(G.time) * 100; add_score(G.tbonus)
                G.cont_stage = max(G.cont_stage, min(50, ST.n + 1))
                music(nil); sfx("clear"); G.clear_all()
                break
            end
        end
        if st == "title" then G.god = god; if #BALLS == 0 then G.stage_reset(1 + floor(rand() * 9)) end end
        if acc > FR * 6 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if st == "play" and P.st == "dead" and P.dead_t >= 2.6 then
            G.lives = G.lives - 1
            if G.lives <= 0 then game_over(false) else start_stage(ST.n) end
        end
    else AL = 1 end
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
to_title()
G.update = update; G.SET = SET; G.surf = surf
hooks { update = update }
pe_log("[PG] ready")
