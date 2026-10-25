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
local function button(id, label, cx, cy, vis, bw)
    local w, h = (bw or 340) * US, 60 * US
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
local LW = 300 * US
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause") and not G.set_open
    local P = G.P
    panel("lp", 20 * US, 20 * US, LW, 170 * US, play, 0.5)
    text("l1", "1UP", 40 * US, 30 * US, LW - 40 * US, 30 * US, 0.95, RED, "left", play)
    text("l2", pad6(G.score), 40 * US, 58 * US, LW - 40 * US, 52 * US, 1.8, WHITE, "left", play)
    text("l3", "High Score  " .. pad6(max(G.hiscore, G.score)), 40 * US, 120 * US, LW - 40 * US, 34 * US, 0.95, CYAN, "left", play)
    panel("rp", SW - LW - 20 * US, 20 * US, LW, 130 * US, play, 0.5)
    text("r1", "Wave " .. tostring(G.wave), SW - LW, 30 * US, LW - 40 * US, 40 * US, 1.2, GOLD, "right", play)
    text("r2", "Ships  " .. tostring(G.ships), SW - LW, 76 * US, LW - 40 * US, 40 * US, 1.1, WHITE, "right", play)
    G.banner.t = (G.banner.t or 0) - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    local btxt = G.banner.text or ""
    local bon = G.banner.t > 0
    if G.phase == "start" and G.pt < 2.0 then btxt, ba, bon = "Player One", 1, true end
    text("ban", btxt, 0, SH * 0.42, SW, 80 * US, 2.2, { 1, .88, .45, ba }, "center", play and bon)
    G.jev_err_t = (G.jev_err_t or 0) - dt
    local show_err = play and G.jev_err ~= nil and G.jev_err_t > 0
    text(
        "jev_err",
        G.jev_err or "",
        SW * 0.08,
        SH * 0.5,
        SW * 0.84,
        48 * US,
        0.85,
        { 1, .4, .32, 1 },
        "center",
        show_err)
    -- diving-flagship score popups
    for i = 1, 4 do
        local p = G.POPS[i]
        local vis = play and p ~= nil
        if vis then
            local sx, sy = project(WP(p.x, p.y + p.t * 0.6, 0.6))
            text("pop" .. i, tostring(p.n), sx - 80 * US, sy - 20 * US, 160 * US, 40 * US, 1.3, { 1, .9, .5, 1 }, "center", true)
        else text("pop" .. i, "", 0, 0, 10, 10, 1, WHITE, "center", false) end
    end
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 480 * US, SH * 0.05, 960 * US, SH * 0.8, title, 0.66)
    text("t_title", "Galaxian Remix", 0, SH * 0.07, SW, 130 * US, 4.2, { 1, .8, .35, 1 }, "center", title)
    text("t_sub", "We Are The Galaxians  ·  Mission: Destroy Aliens", 0, SH * 0.07 + 116 * US, SW, 40 * US, 1.05, DIM, "center", title)
    local TB = { "Score Advance Table  (in convoy / diving)",
        "Drone 30 / 60   ·   Emissary 40 / 80   ·   Escort 50 / 100",
        "Flagship 60 in convoy  ·  diving: 150 alone, 200 with one escort, 300 with two, 800 if you shoot both escorts first" }
    for i, l in ipairs(TB) do text("t_s" .. i, l, SW / 2 - 470 * US, SH * 0.5 + (i - 1) * 34 * US, 940 * US, 34 * US, i == 1 and 0.95 or 0.86, i == 1 and GOLD or DIM, "center", title) end
    local CL = { "A / D / Left / Right or mouse: move  ·  Space / J / Left Click: fire (one missile on screen at a time)",
        "P / Esc: pause  ·  O: settings  ·  M: mute  ·  F3: colliders" }
    for i, l in ipairs(CL) do text("t_c" .. i, l, SW / 2 - 470 * US, SH * 0.5 + 118 * US + (i - 1) * 34 * US, 940 * US, 34 * US, 0.86, DIM, "center", title) end
    text("t_hi", "High Score " .. tostring(G.hiscore), 0, SH * 0.5 + 200 * US, SW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, GOLD, "center", pause)
    local over = st == "over" and not G.set_open
    panel("o_bg", SW / 2 - 400 * US, SH * 0.22, 800 * US, SH * 0.56, over, 0.78)
    text("o_t", "Game Over", 0, SH * 0.24, SW, 90 * US, 3.0, RED, "center", over)
    text("o_m", "Wave " .. tostring(G.wave), 0, SH * 0.24 + 92 * US, SW, 40 * US, 1.2, DIM, "center", over)
    text("o_s", "Score " .. tostring(G.score), 0, SH * 0.24 + 140 * US, SW, 44 * US, 1.4, WHITE, "center", over)
    local c = {}
    local yb = SH * 0.25
    c.start = button("b_start", "Start (Enter)", SW / 2 - 190 * US, yb, title)
    c.jev = button("b_jev", "Jev", SW / 2 + 190 * US, yb, title)
    c.set_t = button("b_set_t", "Settings (O)", SW / 2, yb + 76 * US, title)
    c.quit_app = button("b_quit_app", "Quit Game", SW / 2, yb + 152 * US, title)
    c.resume = button("b_resume", "Resume (P)", SW / 2, SH * 0.42, pause)
    c.set_p = button("b_set_p", "Settings (O)", SW / 2, SH * 0.42 + 76 * US, pause)
    c.quit = button("b_quit", "Quit to Title (Q)", SW / 2, SH * 0.42 + 152 * US, pause)
    local ov = over and (G.over_t or 0) > 1.2
    c.again = button("b_again", "Play Again (Enter)", SW / 2, SH * 0.52, ov)
    c.title = button("b_title", "Title (Esc)", SW / 2, SH * 0.52 + 76 * US, ov)
    return c
end

------------------------------------------------------------------ flow
local jev
local RAW_HELD = { "Left", "Right", "A", "D", "Space", "J" }
local raw_prev = {}
local raw_ready = false

local function clear_move()
    G.vk.Left = nil
    G.vk.A = nil
    G.vk.Right = nil
    G.vk.D = nil
end

local function clear_hold()
    clear_move()
    G.vk.Space = nil
    G.vk.J = nil
end

local function hold_dir(dir)
    clear_move()
    if dir < 0 then
        G.vk.Left = true
        G.vk.A = true
    elseif dir > 0 then
        G.vk.Right = true
        G.vk.D = true
    end
end

local function pulse_fire()
    G.vk.Space = true
end

local driving = false

local function aim_dx()
    local px = G.P.x
    local ax = px
    local best = 1e18
    for _, a in ipairs(G.A) do
        if a.alive then
            local y = a.y
            if DIVE_STATES[a.st] then
                y = y - 100
            end
            if y < best then
                best = y
                ax = a.x
            end
        end
    end
    return ax - px
end

local function jev_actions()
    local dx = aim_dx()
    if dx > 0.35 then
        return { { id = "right", description = "Fly right. The guns keep firing.", score = dx } }
    end
    if dx < -0.35 then
        return { { id = "left", description = "Fly left. The guns keep firing.", score = -dx } }
    end
    return { { id = "stop", description = "Lined up. The guns keep firing.", score = 1 } }
end

local function apply_action(id)
    if id == "left" or id == "left_fire" then
        hold_dir(-1)
    elseif id == "right" or id == "right_fire" then
        hold_dir(1)
    elseif id == "stop" then
        hold_dir(0)
    end
end

local function prime_raw()
    raw_ready = true
    if not input.is_key_down_raw then
        return
    end

    for i = 1, #RAW_HELD do
        local key = RAW_HELD[i]
        local ok, down = pcall(input.is_key_down_raw, key)
        raw_prev[key] = ok and down and true or false
    end
end

local function human_edge()
    if not input.is_key_down_raw then
        return false
    end

    local hit = false
    for i = 1, #RAW_HELD do
        local key = RAW_HELD[i]
        local ok, down = pcall(input.is_key_down_raw, key)
        local pressed = ok and down and true or false
        if raw_ready and pressed and not raw_prev[key] then
            hit = true
        end
        raw_prev[key] = pressed
    end
    raw_ready = true
    return hit
end

local function nearest_diver()
    local px = G.P.x
    local py = G.P.y
    local best = 1e18
    local bx = 0
    local by = 0
    local found = false
    for _, a in ipairs(G.A) do
        if a.alive and DIVE_STATES[a.st] then
            local dx = a.x - px
            local dy = a.y - py
            local d2 = dx * dx + dy * dy
            if d2 < best then
                best = d2
                bx = a.x
                by = a.y
                found = true
            end
        end
    end
    return bx, by, found
end

local function observe()
    local dx, dy, diving = nearest_diver()
    local lives = G.ships
    if G.P.alive then
        lives = lives + 1
    end
    return {
        player_x = G.P.x,
        diver_x = dx,
        diver_y = dy,
        diving = diving,
        lives = lives,
        score = G.score,
    }
end

local function reset_match(seed)
    if seed ~= nil then
        math.randomseed(seed)
    end
    clear_hold()
    G.jev_err = nil
    G.jev_err_t = 0
    SET:close()
    G.set_open = false
    G.reset_world()
    G.new_game_sim()
    G.state = "play"
    music("swarm")
    sfx("start")
    prime_raw()
end

local function to_title()
    jev:begin_human()
    G.jev_err = nil
    G.jev_err_t = 0
    G.state = "title"
    G.new_game_sim(); G.reset_world()
    G.P.alive = false; G.phase = "attract"; G.dive_t = 2
    music("title")
end
G.to_title = to_title

local function new_game()
    jev:begin_human()
    reset_match(nil)
end
G.new_game = new_game

local function game_over()
    G.state = "over"
    G.over_t = 0
    music(nil)
    sfx("gameover")
    if jev:assisted() then
        return
    end
    if G.score > G.hiscore then
        G.hiscore = G.score
        save_hi()
    end
end

local acc = 0
local mprev = 0
local q = { fire = false }
local lmouse_prev = true
local function update(dt)
    flush_mats()
    if G.on_frame then G.on_frame(dt) end
    jev:tick(dt)
    dt = min(dt, 0.1)
    G.t = G.t + dt; G.dt = dt
    local k = { ret = edge("Return"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), qk = edge("Q"), f3 = edge("F3"),
        space = edge("Space"), j = edge("J") }
    G.vk.Space = nil
    G.vk.J = nil
    local ld = false
    pcall(function() ld = input.is_left_mouse_down and input.is_left_mouse_down() and true or false end)
    local lclick = ld and not lmouse_prev; lmouse_prev = ld
    local mdx = 0
    pcall(function() local d = input.get_mouse_delta(); if d then mdx = d.x or d[1] or 0 end end)
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end; lclick = false end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        if c.jev then
            sfx("click")
            local ok = jev:start()
            if not ok then
                local err = jev:error() or "Jev failed to start"
                jev:begin_human()
                G.jev_err = tostring(err)
                G.jev_err_t = 8
                pe_log("[GX] " .. G.jev_err)
            end
        elseif k.ret or k.space or c.start then sfx("click"); new_game()
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click")
        elseif k.space or k.j or lclick then q.fire = true end
        if driving then q.fire = true end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.qk or c.quit then to_title() end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then sfx("click"); new_game()
            elseif k.esc or c.title then to_title() end
        end
    end
    st = G.state
    if (st == "play" or st == "title") and not G.set_open then
        local mx = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0)
        if st == "play" and mx ~= 0 and mx ~= mprev and G.P.alive then sfx("move") end
        mprev = mx
        local mouse = st == "play" and clamp(mdx * 0.012, -1.5, 1.5) or 0
        if st == "play" and G.autoplay then mx, mouse, q.fire = G.autoplay_fn() end
        if st == "title" then mx = 0; q.fire = false end
        local inp = { mx = mx }
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 4 do
            inp.fire = q.fire; q.fire = false
            inp.mdx = n == 0 and mouse or 0
            G.step(inp, FR)
            acc = acc - FR; n = n + 1
        end
        if acc > FR * 4 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if G.out and G.state == "play" then G.out = false; game_over() end
    else AL = 1 end
    render_world(dt)
    update_camera(dt)
    update_lights(dt)
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end
-- debug autopilot for tests/screenshots only: dodge bombs, line up under the lowest attacker, fire when lined up
function G.autoplay_fn()
    local P = G.P
    local tx, best = P.x, -1e9
    for _, a in ipairs(G.A) do
        if a.alive and a.grow >= 1 then
            local sc = (a.st ~= "form" and a.y > 3) and (40 - a.y) or (10 - a.y - abs(a.x - P.x) * 0.5)
            if sc > best then best = sc; tx = a.x + (a.vx or 0) * 0.3 end
        end
    end
    for _, b in ipairs(G.BOMBS) do
        if b.y > P.y and b.y < P.y + 6 and abs(b.x - P.x) < 1.0 then tx = P.x + ((b.x > P.x) and -2 or 2) end
    end
    G.ap_t = (G.ap_t or 0) + 1
    local fire = false
    if not P.shot then
        for _, a in ipairs(G.A) do if a.alive and abs(a.x - P.x) < 0.35 and a.y > P.y + 2 then fire = true end end
    end
    return clamp((tx - P.x) * 2, -1, 1), 0, fire
end

------------------------------------------------------------------ boot
build_lights()
build_trails()
paint_templates()
build_world()
local JevAuto = assert(load(assert(fs.read("Scripts/jev_auto.lua")), "@Scripts/jev_auto.lua", "t", _ENV))()
jev = JevAuto.attach({
    port = 9141,
    id = "galaxian_remix",
    description = "Galaxian Remix. The offered action is the steer, and the guns fire while Jev is playing. "
        .. "Prefer the higher action score.",
    playing = function()
        return G.state == "play"
    end,
    terminal = function()
        return G.state == "over"
    end,
    score = function()
        return G.score or 0
    end,
    busy = function()
        return false
    end,
    human_edge = human_edge,
    observe = observe,
    actions = jev_actions,
    apply = apply_action,
    reset = function(seed)
        driving = true
        reset_match(seed)
    end,
    on_human = function()
        driving = false
        clear_hold()
    end,
})
to_title()
G.update = update; G.SET = SET
hooks { update = update }
pe_log("[GX] ready")
