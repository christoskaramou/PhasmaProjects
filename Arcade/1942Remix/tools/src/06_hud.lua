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
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause") and not G.set_open
    -- side panels (the arcade field is the centre strip)
    panel("lp", 20 * US, 20 * US, LW, 330 * US, play, 0.5)
    text("l1", "1UP", 40 * US, 30 * US, LW - 40 * US, 34 * US, 1.0, RED, "left", play)
    text("l2", pad6(G.score), 40 * US, 62 * US, LW - 40 * US, 52 * US, 1.8, WHITE, "left", play)
    text("l3", "High Score", 40 * US, 120 * US, LW - 40 * US, 34 * US, 1.0, RED, "left", play)
    text("l4", pad6(max(G.hiscore, G.score)), 40 * US, 152 * US, LW - 40 * US, 52 * US, 1.5, WHITE, "left", play)
    text("l5", "Planes in Reserve  " .. tostring(max(0, G.lives or 0)), 40 * US, 220 * US, LW - 40 * US, 40 * US, 1.1, DIM, "left", play)
    text("l6", "Loops  " .. string.rep("R ", P.rolls), 40 * US, 262 * US, LW - 40 * US, 40 * US, 1.1, GOLD, "left", play)
    text("l7", (P.quad and "Quad Guns" or "Twin Guns") .. ((P.esc[1] or P.esc[2]) and "  ·  Escorts" or ""), 40 * US, 300 * US, LW - 40 * US, 36 * US, 0.9, CYAN, "left", play)
    panel("rp", SW - LW - 20 * US, 20 * US, LW, 220 * US, play, 0.5)
    text("r1", "Stage " .. tostring(G.num or 32), SW - LW, 30 * US, LW - 40 * US, 56 * US, 1.8, GOLD, "right", play)
    text("r2", G.stage_name(G.num or 32), SW - LW, 88 * US, LW - 40 * US, 40 * US, 1.2, WHITE, "right", play)
    local rate = (G.spawned or 0) > 0 and floor(G.killed / G.spawned * 100) or 0
    text("r3", "Shot Down " .. rate .. "%", SW - LW, 136 * US, LW - 40 * US, 36 * US, 1.0, DIM, "right", play)
    text("r4", G.ceasefire and G.ceasefire > 0 and string.format("Enemy Fire Stopped %d", math.ceil(G.ceasefire)) or "", SW - LW, 180 * US, LW - 40 * US, 36 * US, 0.9, GOLD, "right", play)
    G.banner.t = (G.banner.t or 0) - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    text("ban", G.banner.text or "", 0, SH * 0.36, SW, 80 * US, 2.4, { 1, .88, .45, ba }, "center", play and G.banner.t > 0 and G.phase ~= "result")
    -- stage result card
    local rs = play and G.phase == "result"
    panel("rs_bg", SW / 2 - 380 * US, SH * 0.28, 760 * US, SH * 0.36, rs, 0.75)
    text("rs_t", "Stage " .. tostring(G.num or 0) .. " Clear", 0, SH * 0.3, SW, 80 * US, 2.6, GOLD, "center", rs)
    text("rs_r", "Shooting Down  " .. floor((G.rate or 0) * 100) .. "%", 0, SH * 0.3 + 100 * US, SW, 50 * US, 1.5, WHITE, "center", rs)
    text("rs_b", ((G.rate or 0) >= 0.999 and "Perfect!  " or "") .. "Bonus  " .. tostring(G.bonus or 0), 0, SH * 0.3 + 160 * US, SW, 50 * US, 1.5, WHITE, "center", rs)
    -- title
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 470 * US, SH * 0.06, 940 * US, SH * 0.86, title, 0.62)
    text("t_title", "1942 Remix", 0, SH * 0.08, SW, 130 * US, 4.4, { 1, .5, .3, 1 }, "center", title)
    text("t_sub", "Fly the P-38 from Midway to Tokyo: 32 stages over the Pacific", 0, SH * 0.08 + 120 * US, SW, 40 * US, 1.0, DIM, "center", title)
    local CL = { "WASD / Arrows: fly   ·   Space / Z / J / Left Click: fire (one volley per press)",
        "X / K / Shift / Right Click: loop (evade, 3 per stage)",
        "Shoot a whole red formation for a POW: Red Quad Guns · Green Side Fighters · White Destroy All",
        "Gray Extra Loop · Yellow Stop Enemy Fire · Orange 1000 Points",
        "P / Esc: pause   ·   O: settings   ·   M: mute   ·   F3: colliders" }
    for i, l in ipairs(CL) do text("t_c" .. i, l, SW / 2 - 460 * US, SH * 0.62 + (i - 1) * 34 * US, 920 * US, 34 * US, 0.92, DIM, "center", title) end
    text("t_hi", "High Score " .. tostring(G.hiscore), 0, SH * 0.62 + 180 * US, SW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, GOLD, "center", pause)
    local over = st == "over" and not G.set_open
    panel("o_bg", SW / 2 - 400 * US, SH * 0.22, 800 * US, SH * 0.56, over, 0.78)
    text("o_t", G.won and "Victory!" or "Game Over", 0, SH * 0.24, SW, 90 * US, 3.0, G.won and GOLD or RED, "center", over)
    text("o_m", G.won and "You flew all 32 stages and reached Tokyo" or ("Stage " .. tostring(G.num or 32) .. "  ·  " .. G.stage_name(G.num or 32)), 0, SH * 0.24 + 92 * US, SW, 40 * US, 1.2, DIM, "center", over)
    text("o_s", "Score " .. tostring(G.score), 0, SH * 0.24 + 140 * US, SW, 44 * US, 1.4, WHITE, "center", over)
    local c = {}
    local yb = SH * 0.3
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

local function to_title()
    G.state = "title"; G.won = false
    G.new_game_sim(); G.phase = "title"; G.carrier.on = false
    G.reset_world()
    music("title")
end
G.to_title = to_title
local function new_game()
    G.reset_world()
    G.new_game_sim()
    G.state = "play"
    music(nil)
end
G.new_game = new_game
local function game_over()
    G.state = "over"; G.over_t = 0
    music(nil); sfx(G.won and "clear" or "gameover")
    if G.score > G.hiscore and not (jev and jev:assisted()) then
        G.hiscore = G.score
        save_hi()
    end
end

local DIR_KEYS = { "Up", "Down", "Left", "Right" }
local DIRS = {
    up = { Up = true },
    up_right = { Up = true, Right = true },
    right = { Right = true },
    down_right = { Down = true, Right = true },
    down = { Down = true },
    down_left = { Down = true, Left = true },
    left = { Left = true },
    up_left = { Up = true, Left = true },
    stop = {},
}
local DIR_STEP = {
    up = { 0, 1 },
    up_right = { 0.7071, 0.7071 },
    right = { 1, 0 },
    down_right = { 0.7071, -0.7071 },
    down = { 0, -1 },
    down_left = { -0.7071, -0.7071 },
    left = { -1, 0 },
    up_left = { -0.7071, 0.7071 },
}
local DIR_ORDER = {
    "up", "up_right", "right", "down_right",
    "down", "down_left", "left", "up_left",
    "stop",
}
local DIR_TEXT = {
    up = "Fly up. Guns keep firing while this is held.",
    up_right = "Fly up-right. Guns keep firing while this is held.",
    right = "Fly right. Guns keep firing while this is held.",
    down_right = "Fly down-right. Guns keep firing while this is held.",
    down = "Fly down. Guns keep firing while this is held.",
    down_left = "Fly down-left. Guns keep firing while this is held.",
    left = "Fly left. Guns keep firing while this is held.",
    up_left = "Fly up-left. Guns keep firing while this is held.",
    stop = "Stop. Guns stop until the next direction.",
}
local PULSES = { loop = "X" }
local pulse = {}
local driving = false
local HUMAN_KEYS = {
    "W", "A", "S", "D",
    "Up", "Down", "Left", "Right",
    "Space", "Z", "J",
    "X", "K", "LeftShift", "RightShift",
}
local human_down = {}
local human_ready = false
local human_hit = false

local function clear_hold()
    for _, key in ipairs(DIR_KEYS) do
        G.vk[key] = nil
    end
    for _, key in pairs(PULSES) do
        G.vk[key] = nil
        pulse[key] = nil
    end
end

local function apply_action(id)
    local dir = DIRS[id]
    if dir then
        for _, key in ipairs(DIR_KEYS) do
            G.vk[key] = dir[key]
        end
        return
    end

    local key = PULSES[id]
    if not key then
        return
    end

    G.vk[key] = true
    arm_edge(key)
    pulse[key] = "down"
end

local function release_pulses()
    for key, state in pairs(pulse) do
        if state == "up_next" then
            G.vk[key] = nil
            pulse[key] = nil
        end
    end
end

local function latch_pulses()
    for key, state in pairs(pulse) do
        if state == "down" then
            pulse[key] = "up_next"
        end
    end
end

local function poll_human()
    local raw = input.is_key_down_raw
    if not raw then
        return false
    end

    local hit = false
    for _, key in ipairs(HUMAN_KEYS) do
        local down = false
        local ok, value = pcall(raw, key)
        if ok and value then
            down = true
        end
        if human_ready and down and not human_down[key] then
            hit = true
        end
        human_down[key] = down
    end
    human_ready = true
    return hit
end

local function human_edge()
    return human_hit
end

local function nearest_enemy()
    local best = nil
    local best_d = nil
    for _, e in ipairs(G.EN or {}) do
        if not e.dead then
            local dx = e.x - P.x
            local dy = e.y - P.y
            local d = dx * dx + dy * dy
            if not best_d or d < best_d then
                best = e
                best_d = d
            end
        end
    end
    return best
end

-- Positive aim_dx means the target is to the right. A close bullet pushes the aim off itself.
local function aim_offset()
    local ax, ay = 0, 5
    local enemy = nearest_enemy()
    if enemy and enemy.y > P.y - 1 then
        ax, ay = enemy.x, enemy.y
    end

    local dx = ax - P.x
    local dy = ay - P.y
    for _, b in ipairs(G.BUL or {}) do
        local bx = b.x - P.x
        local by = b.y - P.y
        if by > -0.5 and by < 5 and abs(bx) < 2.2 then
            local side = bx > 0 and 1 or -1
            dx = dx - side * (2.2 - abs(bx))
        end
    end
    return dx, dy
end

local function jev_actions()
    local dx, dy = aim_offset()
    if P.rolls > 0 and P.roll <= 0 then
        for _, b in ipairs(G.BUL or {}) do
            local bx = b.x - P.x
            local by = b.y - P.y
            if by > -0.5 and by < 4 and abs(bx) < 1.6 then
                return { { id = "loop", description = "Loop once to dodge a close shot.", score = 12 } }
            end
        end
    end

    local best_id = "up"
    local best = -1e9
    for _, id in ipairs(DIR_ORDER) do
        local step = DIR_STEP[id]
        if step then
            local score = step[1] * dx + step[2] * dy
            if score > best then
                best = score
                best_id = id
            end
        end
    end
    return { { id = best_id, description = DIR_TEXT[best_id], score = best } }
end

local acc = 0
local rmouse_prev, lmouse_prev = true, true
local q = { fire = false, roll = false }
local mprev = { x = 0, y = 0 }
local function update(dt)
    flush_mats()
    dt = min(dt, 0.1)
    G.t = G.t + dt; G.dt = dt
    human_hit = poll_human()
    jev:tick(dt)
    release_pulses()
    local k = { ret = edge("Return"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), qk = edge("Q"), f3 = edge("F3"),
        space = edge("Space"), z = edge("Z"), j = edge("J"), x = edge("X"), kk = edge("K"), sh = edge("LeftShift"), sh2 = edge("RightShift") }
    latch_pulses()
    local rd, ld = false, false
    pcall(function() rd = input.is_right_mouse_down and input.is_right_mouse_down() and true or false end)
    pcall(function() ld = input.is_left_mouse_down and input.is_left_mouse_down() and true or false end)
    local rclick, lclick = rd and not rmouse_prev, ld and not lmouse_prev
    rmouse_prev, lmouse_prev = rd, ld
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end; rclick, lclick = false, false end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        if k.ret or k.space or c.start then
            sfx("click")
            jev:begin_human()
            new_game()
        elseif c.jev then
            sfx("click")
            local started = jev:start()
            if not started then
                jev:begin_human()
                local err = jev:error()
                if not err or err == "" then
                    err = "Jev failed to start"
                end
                pe_log("[AF] " .. err)
                G.banner_set(err, 4)
            end
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click")
        else
            if k.space or k.z or k.j or lclick then q.fire = true end
            if k.x or k.kk or k.sh or k.sh2 or rclick then q.roll = true end
            if driving and (any("Left", "A") or any("Right", "D") or any("Up", "W") or any("Down", "S")) then
                q.fire = true
            end
        end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.qk or c.quit then
            jev:begin_human()
            to_title()
        end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then
                sfx("click")
                jev:begin_human()
                new_game()
            elseif k.esc or c.title then to_title() end
        end
    end
    st = G.state
    if st == "play" and not G.set_open then
        local mx = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0)
        local my = (any("Up", "W") and 1 or 0) - (any("Down", "S") and 1 or 0)
        if (mx ~= 0 or my ~= 0) and (mx ~= mprev.x or my ~= mprev.y) and P.alive and G.phase == "fly" then sfx("bank") end
        mprev.x, mprev.y = mx, my
        if G.autoplay then mx, my, q.fire = G.autoplay_fn() end
        local inp = { mx = mx, my = my, fire = false, roll = false }
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 6 do
            inp.fire, inp.roll = q.fire, q.roll; q.fire, q.roll = false, false
            if G.phase ~= "fly" then inp.fire, inp.roll = false, false end
            G.stage_step(inp, FR)
            acc = acc - FR; n = n + 1
        end
        if acc > FR * 6 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if G.music_after then G.music_after = G.music_after - dt; if G.music_after <= 0 then G.music_after = nil end end
        if G.out_of_lives and G.state == "play" then game_over() end
        if G.phase == "won" and G.pt > 0 then G.phase = "done"; game_over() end
        G.drone_t = (G.drone_t or 0) - dt
        if G.drone_t <= 0 and P.alive then G.drone_t = 0.95; sfx("drone") end
    elseif st == "title" then
        G.scroll = (G.scroll or 0) + 3 * dt
        AL = 1
    else AL = 1 end
    render_world(dt)
    render_planes(dt)
    update_camera(dt)
    update_lights(dt)
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end
-- debug autopilot for tests/screenshots only (G.autoplay = true): weave, dodge the nearest bullet, keep firing
function G.autoplay_fn()
    local tx = 0
    local best
    for _, e in ipairs(G.EN) do if e.entered and (not best or e.y < best.y) and e.y > P.y then best = e end end
    if best then tx = best.x end
    local mx = clamp((tx - P.x) * 0.6, -1, 1)
    local my = clamp((5 - P.y) * 0.4, -1, 1)
    for _, b in ipairs(G.BUL) do
        local dx, dy = b.x - P.x, b.y - P.y
        if dy > -0.5 and dy < 4 and abs(dx) < 1.4 then mx = dx > 0 and -1 or 1 end
    end
    G.ap_t = (G.ap_t or 0) + 1
    return mx, my, (G.ap_t % 9 == 0)
end

------------------------------------------------------------------ boot
local JevAuto = assert(load(assert(fs.read("Scripts/jev_auto.lua")), "@Scripts/jev_auto.lua", "t", _ENV))()
jev = JevAuto.attach({
    port = 9136,
    id = "1942remix",
    description = "1942 Remix. Fly the P-38 and shoot the formation. A direction is a hold: the plane keeps "
        .. "flying that way and the guns keep firing until the next direction. aim_dx positive means the target is "
        .. "to the right. aim_dy positive means it is up the screen. Prefer the higher action score.",
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
        return P.alive and P.roll > 0
    end,
    human_edge = human_edge,
    observe = function()
        local dx, dy = aim_offset()
        return {
            player_x = P.x,
            player_y = P.y,
            aim_dx = dx,
            aim_dy = dy,
            lives = G.lives or 0,
            loops = P.rolls or 0,
            score = G.score or 0,
        }
    end,
    actions = jev_actions,
    apply = apply_action,
    reset = function(seed)
        math.randomseed(seed)
        clear_hold()
        driving = true
        new_game()
    end,
    on_human = function()
        driving = false
        clear_hold()
    end,
})

build_lights()
paint_templates()
build_world()
to_title()
G.update = update; G.SET = SET
hooks { update = update }
pe_log("[AF] ready")
