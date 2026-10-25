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
local LW = 300 * US
local CAPN = { S = "Slow", C = "Catch", L = "Laser", E = "Enlarge" }
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause") and not G.set_open
    panel("lp", 20 * US, 20 * US, LW, 300 * US, play, 0.5)
    text("l1", "1UP", 40 * US, 30 * US, LW - 40 * US, 34 * US, 1.0, RED, "left", play)
    text("l2", pad6(G.score), 40 * US, 62 * US, LW - 40 * US, 52 * US, 1.8, WHITE, "left", play)
    text("l3", "High Score", 40 * US, 120 * US, LW - 40 * US, 34 * US, 1.0, RED, "left", play)
    text("l4", pad6(max(G.hiscore, G.score)), 40 * US, 152 * US, LW - 40 * US, 52 * US, 1.5, WHITE, "left", play)
    text("l5", "Vaus  " .. tostring(max(0, G.lives - 1)), 40 * US, 220 * US, LW - 40 * US, 40 * US, 1.1, DIM, "left", play)
    text("l6", G.P.mode and CAPN[G.P.mode] or "", 40 * US, 262 * US, LW - 40 * US, 40 * US, 1.1, CYAN, "left", play)
    panel("rp", SW - LW - 20 * US, 20 * US, LW, 150 * US, play, 0.5)
    text("r1", "Round", SW - LW, 30 * US, LW - 40 * US, 34 * US, 1.0, RED, "right", play)
    text("r2", tostring(G.round or 1), SW - LW, 62 * US, LW - 40 * US, 70 * US, 2.6, GOLD, "right", play)
    G.banner.t = (G.banner.t or 0) - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    text("ban", G.banner.text or "", 0, SH * 0.5, SW, 80 * US, 2.4, { 1, .88, .45, ba }, "center", play and G.banner.t > 0)
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 470 * US, SH * 0.06, 940 * US, SH * 0.62, title, 0.62)
    text("t_title", "Arkanoid Remix", 0, SH * 0.08, SW, 130 * US, 4.2, { 1, .55, .3, 1 }, "center", title)
    text("t_sub", "Pilot the Vaus through 32 rounds of bricks, then destroy DOH", 0, SH * 0.08 + 120 * US, SW, 40 * US, 1.0, DIM, "center", title)
    local CL = { "A / D / Arrows / Mouse: move the Vaus   ·   Space / Z / Left Click: launch / fire laser (one per press)",
        "Capsules: S Slow · C Catch · L Laser · E Enlarge · D Disruption · B Break (warp out) · P Extra Vaus",
        "Silver bricks need several hits · gold bricks can't be broken",
        "P / Esc: pause   ·   O: settings   ·   M: mute   ·   F3: colliders" }
    for i, l in ipairs(CL) do text("t_c" .. i, l, SW / 2 - 460 * US, SH * 0.47 + (i - 1) * 34 * US, 920 * US, 34 * US, 0.92, DIM, "center", title) end
    text("t_hi", "High Score " .. tostring(G.hiscore), 0, SH * 0.47 + 150 * US, SW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, GOLD, "center", pause)
    local over = st == "over" and not G.set_open
    panel("o_bg", SW / 2 - 400 * US, SH * 0.22, 800 * US, SH * 0.56, over, 0.78)
    text("o_t", G.won and "Congratulations!" or "Game Over", 0, SH * 0.24, SW, 90 * US, 3.0, G.won and GOLD or RED, "center", over)
    text("o_m", G.won and "DOH is destroyed and the Arkanoid's dimension is restored" or ("Round " .. tostring(G.round or 1)), 0, SH * 0.24 + 92 * US, SW, 40 * US, 1.2, DIM, "center", over)
    text("o_s", "Score " .. tostring(G.score), 0, SH * 0.24 + 140 * US, SW, 44 * US, 1.4, WHITE, "center", over)
    local c = {}
    local yb = SH * 0.3
    local span = (340 + 24) * US
    c.start = button("b_start", "Start (Enter)", SW / 2 - span / 2, yb, title)
    c.jev = button("b_jev", "Jev", SW / 2 + span / 2, yb, title)
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
local hold_left = false
local hold_right = false
local pulse_launch = false
local vk_live = false
local raw_prev = {}
local RAW_PLAY = { "Left", "Right", "A", "D", "Space", "Z", "J", "Up", "W" }

local function clear_virtual()
    hold_left = false
    hold_right = false
    pulse_launch = false
    vk_live = false
    if not G.vk then
        return
    end

    G.vk["Left"] = nil
    G.vk["A"] = nil
    G.vk["Right"] = nil
    G.vk["D"] = nil
    G.vk["Space"] = nil
end

-- Holds stay until the next act. The launch pulse is published for one play frame
-- so edge() sees it the same way it sees Space.
local function sync_vk()
    local playing = G.state == "play" and not G.set_open
    local fire = false
    if playing then
        fire = pulse_launch
    end
    pulse_launch = false

    if not hold_left and not hold_right and not fire and not vk_live then
        return
    end

    if not G.vk then
        G.vk = {}
    end

    G.vk["Left"] = hold_left or nil
    G.vk["A"] = hold_left or nil
    G.vk["Right"] = hold_right or nil
    G.vk["D"] = hold_right or nil
    G.vk["Space"] = fire or nil
    vk_live = hold_left or hold_right or fire
end

local function human_edge()
    local raw = input.is_key_down_raw
    if type(raw) ~= "function" then
        return false
    end

    local hit = false
    for i = 1, #RAW_PLAY do
        local key = RAW_PLAY[i]
        local ok, down = pcall(raw, key)
        down = ok and down and true or false
        if down and not raw_prev[key] then
            hit = true
        end
        raw_prev[key] = down
    end
    return hit
end

local function apply_action(id)
    if id == "left" then
        hold_left = true
        hold_right = false
    elseif id == "right" then
        hold_right = true
        hold_left = false
    elseif id == "stop" then
        hold_left = false
        hold_right = false
    elseif id == "launch" then
        pulse_launch = true
    end
end

local function observe_match()
    local ball = nil
    local balls = G.BALLS or {}
    for i = 1, #balls do
        local candidate = balls[i]
        if not ball or candidate.y < ball.y then
            ball = candidate
        end
    end

    return {
        paddle_x = G.P and G.P.x or 0,
        ball_x = ball and ball.x or 0,
        ball_y = ball and ball.y or 0,
        ball_vx = ball and ball.vx or 0,
        ball_vy = ball and ball.vy or 0,
        lives = G.lives or 0,
        score = G.score or 0,
    }
end

local function to_title()
    if jev then
        jev:begin_human()
    end
    G.state = "title"; G.won = false
    G.new_game_sim(); G.reset_world()
    music("title")
end
G.to_title = to_title

local function start_match(seed)
    if type(seed) == "number" then
        math.randomseed(seed)
    end

    G.reset_world()
    G.new_game_sim()
    G.state = "play"
    music(nil)
    sfx("start")
end

local function new_game()
    if jev then
        jev:begin_human()
    end
    start_match()
end
G.new_game = new_game

local function game_over()
    G.state = "over"; G.over_t = 0
    music(G.won and "ending" or nil); sfx(G.won and "extra" or "gameover")
    if jev and jev:assisted() then
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
    if jev then
        jev:tick(dt)
    end
    sync_vk()
    dt = min(dt, 0.1)
    G.t = G.t + dt; G.dt = dt
    local k = { ret = edge("Return"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), qk = edge("Q"), f3 = edge("F3"),
        space = edge("Space"), z = edge("Z"), j = edge("J"), up = edge("Up"), w = edge("W") }
    local ld = false
    pcall(function() ld = input.is_left_mouse_down and input.is_left_mouse_down() and true or false end)
    local lclick = ld and not lmouse_prev; lmouse_prev = ld
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end; lclick = false end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        if k.ret or k.space or c.start then
            sfx("click")
            new_game()
        elseif c.jev then
            sfx("click")
            local ok = jev:start()
            if not ok then
                local err = jev:error() or "Jev failed"
                pe_log("[AK] " .. err)
                G.banner_set(err, 4)
            end
        elseif k.o or c.set_t then
            open_settings()
        elseif c.quit_app then
            engine.quit()
        end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click")
        elseif k.space or k.z or k.j or k.up or k.w or lclick then q.fire = true end
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
    local mdx = 0
    pcall(function() local d = input.get_mouse_delta(); if d then mdx = d.x or d[1] or 0 end end)
    if st == "play" and not G.set_open then
        local mx = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0)
        if mx ~= 0 and mx ~= mprev and G.P.alive then sfx("move") end
        mprev = mx
        local mouse = clamp(mdx * 0.012, -1.5, 1.5)
        if G.autoplay then mx, mouse, q.fire = G.autoplay_fn() end
        local inp = { mx = mx, mdx = 0, fire = false }
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 7 do   -- 7 steps cover the 0.1 s dt clamp, so the game never runs slow above 10 fps
            inp.fire = q.fire; q.fire = false
            inp.mdx = n == 0 and mouse or 0
            G.snap_prev()
            G.round_step(inp, FR)
            acc = acc - FR; n = n + 1
        end
        if acc > FR * 7 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if G.out_of_lives and G.state == "play" then G.out_of_lives = false; game_over() end
        if G.doh and G.phase ~= "dead" and not G.doh_music then G.doh_music = true; music("doh") end
        if not G.doh then G.doh_music = false end
    else AL = 1 end
    render_world(dt)
    if G.on_frame then G.on_frame(dt) end   -- test/capture hook (nil in play)
    update_camera(dt)
    local b = G.BALLS[1]
    update_lights(dt, b and WP(G.ix(b, "x"), G.ix(b, "y"), 0.9) or nil)   -- the ball light follows the interpolated ball too
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end
-- debug autopilot for tests/screenshots only: track the lowest descending ball (and capsules when safe)
function G.autoplay_fn()
    local P = G.P
    local tx = 0
    local best
    for _, b in ipairs(G.BALLS) do if not best or (b.vy < 0 and b.y < best.y) then best = b end end
    if best then tx = best.x + (G.ap_off or 0) end
    G.ap_t = (G.ap_t or 0) + 1
    if G.ap_t % 90 == 0 then G.ap_off = rr(-0.6, 0.6) end
    local mx = clamp((tx - P.x) * 3, -1, 1)
    return mx, 0, (G.ap_t % 20 == 0)
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_world()
to_title()

local jev_source = assert(fs.read("Scripts/jev_auto.lua"), "Missing Scripts/jev_auto.lua")
local JevAuto = assert(load(jev_source, "@Scripts/jev_auto.lua", "t", _ENV))()
jev = JevAuto.attach({
    port = 9138,
    id = "arkanoid_remix",
    description = "Steer the Vaus. The offered action launches a held ball, or moves the Vaus under the ball. Prefer the higher action score.",
    playing = function()
        return G.state == "play" and not G.set_open
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
    observe = observe_match,
    actions = function()
        local view = observe_match()
        local moving = view.ball_vx ~= 0 or view.ball_vy ~= 0
        if not moving then
            return { { id = "launch", description = "Launch the ball.", score = 1 } }
        end
        local dx = view.ball_x - view.paddle_x
        if dx > 0.2 then
            return { { id = "right", description = "Move the Vaus right under the ball.", score = dx } }
        end
        if dx < -0.2 then
            return { { id = "left", description = "Move the Vaus left under the ball.", score = -dx } }
        end
        return { { id = "stop", description = "The Vaus is under the ball.", score = 1 } }
    end,
    apply = apply_action,
    reset = start_match,
    on_human = clear_virtual,
})

G.update = update
G.SET = SET
hooks { update = update }
pe_log("[AK] ready")
