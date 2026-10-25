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
    panel("lp", 20 * US, 20 * US, LW, 250 * US, play, 0.5)
    text("l1", "Score", 40 * US, 30 * US, LW - 40 * US, 30 * US, 0.9, RED, "left", play)
    text("l2", pad6(G.score), 40 * US, 58 * US, LW - 40 * US, 52 * US, 1.8, G.freeze > 0 and DIM or WHITE, "left", play)
    text("l3", "High Score  " .. pad6(max(G.hiscore, G.score)), 40 * US, 116 * US, LW - 40 * US, 34 * US, 0.9, CYAN, "left", play)
    text("l4", G.free > 0 and ("Free Cars  " .. math.ceil(G.free)) or ("Spare Cars  " .. tostring(G.cars)), 40 * US, 160 * US, LW - 40 * US, 38 * US, 1.15, GOLD, "left", play)
    text("l5", string.format("Speed  %d", floor(P.v * 8)), 40 * US, 206 * US, LW - 40 * US, 36 * US, 1.0, DIM, "left", play)
    panel("rp", SW - LW - 20 * US, 20 * US, LW, 130 * US, play, 0.5)
    text("r1", "Weapon", SW - LW, 30 * US, LW - 40 * US, 30 * US, 0.9, RED, "right", play)
    text("r2", P.weapon and (G.WNAME[P.weapon] .. "  x" .. P.ammo) or "Machine Guns", SW - LW, 64 * US, LW - 40 * US, 40 * US, 1.15, WHITE, "right", play)
    text("r3", P.mode == "boat" and "Boat" or "Car", SW - LW, 104 * US, LW - 40 * US, 34 * US, 0.9, DIM, "right", play)
    G.banner.t = (G.banner.t or 0) - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    text("ban", G.banner.text or "", 0, SH * 0.16, SW, 80 * US, 2.2, { 1, .88, .45, ba }, "center", play and G.banner.t > 0)
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 470 * US, SH * 0.06, 940 * US, SH * 0.66, title, 0.62)
    text("t_title", "Spy Hunter Remix", 0, SH * 0.08, SW, 130 * US, 4.2, { 1, .55, .3, 1 }, "center", title)
    text("t_sub", "Drive the Interceptor, destroy the enemy agents, spare the civilians", 0, SH * 0.08 + 120 * US, SW, 40 * US, 1.0, DIM, "center", title)
    local CL = { "A / D / Left / Right: steer  ·  W / Up: accelerate  ·  S / Down: brake",
        "Space / J / Left Click: machine guns (one burst per press)  ·  Shift / X / Right Click: special weapon",
        "Drive into the back of the red weapons van for smoke, oil or missiles  ·  only missiles stop the helicopter",
        "Leaving the road wrecks your car  ·  P / Esc: pause  ·  O: settings  ·  M: mute  ·  F3: colliders" }
    for i, l in ipairs(CL) do text("t_c" .. i, l, SW / 2 - 460 * US, SH * 0.5 + (i - 1) * 34 * US, 920 * US, 34 * US, 0.88, DIM, "center", title) end
    text("t_hi", "High Score " .. tostring(G.hiscore), 0, SH * 0.5 + 150 * US, SW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, GOLD, "center", pause)
    local over = st == "over" and not G.set_open
    panel("o_bg", SW / 2 - 400 * US, SH * 0.22, 800 * US, SH * 0.56, over, 0.78)
    text("o_t", "Game Over", 0, SH * 0.24, SW, 90 * US, 3.0, RED, "center", over)
    text("o_m", string.format("Distance %d", floor(P.y)), 0, SH * 0.24 + 92 * US, SW, 40 * US, 1.2, DIM, "center", over)
    text("o_s", "Score " .. tostring(G.score), 0, SH * 0.24 + 140 * US, SW, 44 * US, 1.4, WHITE, "center", over)
    local c = {}
    local yb = SH * 0.28
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

------------------------------------------------------------------ Jev autoplay (holds ride the existing virtual-key read)
local jev_source = fs.read("Scripts/jev_auto.lua")
local JevAuto = assert(load(jev_source, "@Scripts/jev_auto.lua", "t", _ENV))()
local pulse_guns = false
local pulse_special = false
local human_prev = {}
local HUMAN_KEYS = {
    "Left", "Right", "A", "D",
    "Up", "Down", "W", "S",
    "Space", "J", "X", "LeftShift", "RightShift",
}
local HOSTILE = { sw = true, rl = true, enf = true, heli = true, eboat = true, dumper = true }
local ACTIONS = {
    { id = "left", description = "Steer left. Holds until another steer action." },
    { id = "right", description = "Steer right. Holds until another steer action." },
    { id = "straight", description = "Hold the wheel straight." },
    { id = "gas", description = "Accelerate. Holds until brake." },
    { id = "brake", description = "Brake. Holds until gas." },
    { id = "guns", description = "Fire the machine guns once." },
    { id = "special", description = "Fire the special weapon once." },
}

local function clear_virtual()
    G.vk = {}
    pulse_guns = false
    pulse_special = false
end

local function read_human()
    local raw = input.is_key_down_raw
    local now = {}
    if type(raw) ~= "function" then
        return now
    end

    for i = 1, #HUMAN_KEYS do
        local key = HUMAN_KEYS[i]
        local ok, down = pcall(raw, key)
        now[key] = ok and down and true or false
    end
    return now
end

local function prime_human()
    human_prev = read_human()
end

local function human_edge()
    local now = read_human()
    local hit = false
    for i = 1, #HUMAN_KEYS do
        local key = HUMAN_KEYS[i]
        if now[key] and not human_prev[key] then
            hit = true
        end
    end
    human_prev = now
    return hit
end

local function lane_offset()
    local P = G.P
    local cx, hw, isl = G.course(P.y)
    local center = cx
    if isl > 0.05 then
        local side = -1
        if P.x >= cx then
            side = 1
        end
        center = cx + side * (isl + hw) * 0.5
    end
    return P.x - center
end

local function nearest_enemy()
    local P = G.P
    local best = nil
    local best_dist = math.huge
    for i = 1, #G.EN do
        local e = G.EN[i]
        if e.alive and HOSTILE[e.k] and e.y > P.y then
            local dist = e.y - P.y
            if dist < best_dist then
                best = e
                best_dist = dist
            end
        end
    end
    if not best then
        return { distance = -1, side = 0, kind = "" }
    end
    return { distance = best.y - P.y, side = best.x - P.x, kind = best.k }
end

local function apply_action(id)
    if not G.vk then
        G.vk = {}
    end
    if id == "left" or id == "right" or id == "straight" then
        G.vk.Left = nil
        G.vk.Right = nil
        G.vk.A = nil
        G.vk.D = nil
        G.vk.Down = nil
        G.vk.S = nil
    end
    if id == "gas" or id == "brake" then
        G.vk.Up = nil
        G.vk.Down = nil
        G.vk.W = nil
        G.vk.S = nil
    end
    if id == "left" then
        G.vk.Left = true
        G.vk.Up = true
        pulse_guns = true
    elseif id == "right" then
        G.vk.Right = true
        G.vk.Up = true
        pulse_guns = true
    elseif id == "straight" then
        G.vk.Up = true
        pulse_guns = true
    elseif id == "gas" then
        G.vk.Up = true
    elseif id == "brake" then
        G.vk.Down = true
    elseif id == "guns" then
        pulse_guns = true
    elseif id == "special" then
        pulse_special = true
    end
end

local function start_match()
    clear_virtual()
    G.reset_world()
    G.new_game_sim()
    G.sh_fx_reset()
    G.state = "play"
    G.cam_snap = true
    music("drive")
    sfx("start")
end

local jev = JevAuto.attach({
    port = 9140,
    id = "spyhunter-remix",
    description = "Spy Hunter Remix. The offered action steers the Interceptor. Gas and the guns stay on with that steer. Prefer the higher action score.",
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
    on_human = clear_virtual,
    observe = function()
        return {
            lane_offset = lane_offset(),
            speed = G.P.v,
            nearest_enemy_ahead = nearest_enemy(),
            score = G.score or 0,
        }
    end,
    actions = function()
        local off = lane_offset()
        if off > 1.1 then
            return { { id = "left", description = "Steer left back into the lane. Gas and guns stay on.", score = off } }
        end
        if off < -1.1 then
            return { { id = "right", description = "Steer right back into the lane. Gas and guns stay on.", score = -off } }
        end
        local foe = nearest_enemy()
        if foe and foe.distance and foe.distance >= 0 and foe.distance < 28 then
            if foe.side > 0.35 then
                return { { id = "right", description = "Steer toward the enemy ahead. Gas and guns stay on.", score = foe.side } }
            end
            if foe.side < -0.35 then
                return { { id = "left", description = "Steer toward the enemy ahead. Gas and guns stay on.", score = -foe.side } }
            end
        end
        return { { id = "straight", description = "Hold the lane. Gas and guns stay on.", score = 1 } }
    end,
    apply = apply_action,
    reset = function(seed)
        math.randomseed(seed)
        start_match()
        prime_human()
    end,
})

------------------------------------------------------------------ flow
local function to_title()
    jev:begin_human()
    G.state = "title"
    G.new_game_sim(); G.reset_world()
    music("title")
end
G.to_title = to_title
local function new_game()
    jev:begin_human()
    start_match()
end
G.new_game = new_game
local function game_over()
    G.state = "over"; G.over_t = 0
    music(nil); sfx("gameover")
    if G.score > G.hiscore and not jev:assisted() then
        G.hiscore = G.score
        save_hi()
    end
end
local acc = 0
local mprev = 0
local q = { fire = false, special = false }
local lmouse_prev, rmouse_prev = true, true
local function update(dt)
    flush_mats()
    dt = clamp(dt, 0, 0.1)   -- a negative frame time (timer hitch) would make every damp() explode
    G.t = G.t + dt
    G.dt = dt
    jev:tick(dt)
    local k = { ret = edge("Return"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), qk = edge("Q"), f3 = edge("F3"),
        space = edge("Space"), j = edge("J"), x = edge("X"), sh = edge("LeftShift"), sh2 = edge("RightShift") }
    local ld, rd = false, false
    pcall(function() ld = input.is_left_mouse_down and input.is_left_mouse_down() and true or false end)
    pcall(function() rd = input.is_right_mouse_down and input.is_right_mouse_down() and true or false end)
    local lclick, rclick = ld and not lmouse_prev, rd and not rmouse_prev; lmouse_prev, rmouse_prev = ld, rd
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end; lclick, rclick = false, false end
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
                local err = jev:error() or "Jev failed to start"
                G.banner_set(err, 4)
                pe_log("[SH] " .. err)
            end
        elseif k.o or c.set_t then
            open_settings()
        elseif c.quit_app then
            engine.quit()
        end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click")
        else
            if k.space or k.j or lclick then q.fire = true end
            if k.x or k.sh or k.sh2 or rclick then q.special = true end
        end
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
    if st == "play" and not G.set_open then
        local mx = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0)
        local my = (any("Up", "W") and 1 or 0) - (any("Down", "S") and 1 or 0)
        if mx ~= 0 and mx ~= mprev and G.P.alive then sfx("steer") end
        mprev = mx
        if pulse_guns then
            q.fire = true
            pulse_guns = false
        end
        if pulse_special then
            q.special = true
            pulse_special = false
        end
        if G.autoplay then mx, my, q.fire = G.autoplay_fn() end
        local inp = { mx = mx, my = my }
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 4 do
            inp.fire, inp.special = q.fire, q.special; q.fire, q.special = false, false
            G.drive_step(inp, FR)
            acc = acc - FR; n = n + 1
        end
        if acc > FR * 4 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if G.out and G.state == "play" then G.out = false; game_over() end
        G.eng_t = (G.eng_t or 0) - dt
        if G.eng_t <= 0 and G.P.alive then G.eng_t = 0.19; sfx("eng" .. tostring(min(4, floor(G.P.v / 6)))) end
    elseif st == "title" then
        -- attract mode: the car cruises down the road
        local P = G.P
        P.y = P.y + 12 * dt; P.v = 12
        P.mode = G.mode_at(P.y)
        local tx = G.safe_x(P.y, P.x, P.mode, 8); P.x = P.x + (tx - P.x) * min(1, dt * 2)   -- a lane, never the median
        AL = 1
    else AL = 1 end
    render_world(dt)
    update_camera(dt)
    update_lights(dt, G.P.x, G.P.y)
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end
-- debug autopilot for tests/screenshots only: hold the lane centre, dodge cars ahead, fire at hunters
function G.autoplay_fn()
    local P = G.P
    local cx, hw, isl = G.course(P.y + 3)
    local c2, h2, i2 = G.course(P.y + 9)
    local tx = cx
    if isl > 0.05 then tx = cx + (P.x < cx and -1 or 1) * (isl + hw) / 2
    elseif i2 > 0.05 then tx = c2 + (P.x < c2 and -1 or 1) * (i2 + h2) / 2 end
    local van
    for _, e in ipairs(G.EN) do if e.alive and e.k == "van" and not e.done and e.y > P.y then van = e end end
    for _, e in ipairs(G.EN) do if e.alive and e ~= van and e.y > P.y and e.y - P.y < 6 and abs(e.x - tx) < 1.0 then tx = tx + (e.x > tx and -1.1 or 1.1) end end
    if van then tx = van.x end
    G.ap_t = (G.ap_t or 0) + 1
    local mx = clamp((tx - P.x) * 1.5, -1, 1)
    local my = P.v < (van and van.y - P.y < 8 and van.v + 2.5 or 17) and 1 or 0
    if van and van.y - P.y < 8 and P.v > van.v + 4 then my = -1 end
    return mx, my, (G.ap_t % 15 == 0)
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_world()
to_title()
G.update = update; G.SET = SET
hooks { update = update }
pe_log("[SH] ready")
