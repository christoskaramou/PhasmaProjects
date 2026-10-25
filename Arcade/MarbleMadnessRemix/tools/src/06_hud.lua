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
    panel("lp", 20 * US, 20 * US, LW, 200 * US, play, 0.5)
    text("l1", "Score", 40 * US, 30 * US, LW - 40 * US, 34 * US, 1.0, RED, "left", play)
    text("l2", pad6(G.score), 40 * US, 62 * US, LW - 40 * US, 52 * US, 1.8, WHITE, "left", play)
    text("l3", "High Score", 40 * US, 120 * US, LW - 40 * US, 34 * US, 1.0, RED, "left", play)
    text("l4", pad6(max(G.hiscore, G.score)), 40 * US, 152 * US, LW - 40 * US, 52 * US, 1.5, WHITE, "left", play)
    panel("rp", SW - LW - 20 * US, 20 * US, LW, 200 * US, play, 0.5)
    local tl = G.time or 0
    text("r1", "Time", SW - LW, 30 * US, LW - 40 * US, 34 * US, 1.0, RED, "right", play)
    text("r2", tostring(math.ceil(tl)), SW - LW, 62 * US, LW - 40 * US, 70 * US, 2.6, tl < 10 and RED or GOLD, "right", play)
    text("r3", G.CUR and G.CUR.name or "", SW - LW, 150 * US, LW - 40 * US, 40 * US, 1.1, WHITE, "right", play)
    G.banner.t = (G.banner.t or 0) - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    text("ban", G.banner.text or "", 0, SH * 0.16, SW, 80 * US, 2.4, { 1, .88, .45, ba }, "center", play and G.banner.t > 0)
    local gl = play and G.phase == "goal" and G.pt > 0.6
    text("gb", "Time Bonus  " .. tostring(G.bonus or 0), 0, SH * 0.16 + 90 * US, SW, 50 * US, 1.5, WHITE, "center", gl)
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 470 * US, SH * 0.06, 940 * US, SH * 0.62, title, 0.62)
    text("t_title", "Marble Madness Remix", 0, SH * 0.08, SW, 130 * US, 3.8, { .55, .7, 1, 1 }, "center", title)
    text("t_sub", "Roll your marble to the goal of six races before time runs out", 0, SH * 0.08 + 120 * US, SW, 40 * US, 1.0, DIM, "center", title)
    local CL = { "WASD / Arrows: push the marble (diagonals roll diagonally)   ·   Mouse: trackball",
        "Unused seconds carry over to the next race   ·   long drops shatter the marble",
        "Steelies push you · Marble Munchers and acid eat you · hammers flatten you",
        "P / Esc: pause   ·   O: settings   ·   M: mute   ·   F3: colliders" }
    for i, l in ipairs(CL) do text("t_c" .. i, l, SW / 2 - 460 * US, SH * 0.47 + (i - 1) * 34 * US, 920 * US, 34 * US, 0.92, DIM, "center", title) end
    text("t_hi", "High Score " .. tostring(G.hiscore), 0, SH * 0.47 + 150 * US, SW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, GOLD, "center", pause)
    local over = st == "over" and not G.set_open
    panel("o_bg", SW / 2 - 400 * US, SH * 0.22, 800 * US, SH * 0.56, over, 0.78)
    text("o_t", G.won and "Congratulations!" or "Game Over", 0, SH * 0.24, SW, 90 * US, 3.0, G.won and GOLD or RED, "center", over)
    text("o_m", G.won and "You finished all six races" or ("Time ran out on the " .. (G.CUR and G.CUR.name or "")), 0, SH * 0.24 + 92 * US, SW, 40 * US, 1.2, DIM, "center", over)
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

------------------------------------------------------------------ Jev
-- Compass holds land in G.vk. held() already treats that table like a key that is down.
local jev
local RAW_MOVE = { "W", "A", "S", "D", "Up", "Down", "Left", "Right" }
local raw_prev = {}
local PUSH = {
    n = { "W", "Up" },
    s = { "S", "Down" },
    e = { "D", "Right" },
    w = { "A", "Left" },
    ne = { "W", "Up", "D", "Right" },
    nw = { "W", "Up", "A", "Left" },
    se = { "S", "Down", "D", "Right" },
    sw = { "S", "Down", "A", "Left" },
    stop = {},
}
local ACTION_TEXT = {
    n = "Hold up the screen (W). World push about x+0.57 z+0.82.",
    s = "Hold down the screen (S), toward the goal. World push about x-0.57 z-0.82.",
    e = "Hold right (D). World push about x-0.82 z+0.57.",
    w = "Hold left (A). World push about x+0.82 z-0.57.",
    ne = "Hold up and right. World push about x-0.17 z+0.98, nearly +Z.",
    nw = "Hold up and left. World push about x+0.98 z+0.17, nearly +X.",
    se = "Hold down and right. World push about x-0.98 z-0.17, nearly -X.",
    sw = "Hold down and left. World push about x+0.17 z-0.98, nearly -Z, down the course.",
    stop = "Release the push.",
}
local ACTION_IDS = { "n", "s", "e", "w", "ne", "nw", "se", "sw", "stop" }
local ACTIONS = {}
for i = 1, #ACTION_IDS do
    local id = ACTION_IDS[i]
    ACTIONS[i] = { id = id, description = ACTION_TEXT[id] }
end

local source = assert(fs.read("Scripts/jev_auto.lua"), "Missing Jev module: Scripts/jev_auto.lua")
local JevAuto = assert(load(source, "@Scripts/jev_auto.lua", "t", _ENV))()

local function mcp_port()
    local text = fs.read("Agent/agent_config.json") or ""
    return tonumber(text:match('"mcp_port"%s*:%s*(%d+)')) or 9137
end

local function rnd(v)
    local sign = 1
    if v < 0 then
        sign = -1
        v = -v
    end
    return sign * floor(v * 100 + 0.5) / 100
end

local function raw_down(key)
    if not input.is_key_down_raw then
        return false
    end

    local ok, down = pcall(input.is_key_down_raw, key)
    if ok and down then
        return true
    end
    return false
end

local function snapshot_raw()
    for i = 1, #RAW_MOVE do
        local key = RAW_MOVE[i]
        raw_prev[key] = raw_down(key)
    end
end

local function human_edge()
    local hit = false
    for i = 1, #RAW_MOVE do
        local key = RAW_MOVE[i]
        local down = raw_down(key)
        if down and not raw_prev[key] then
            hit = true
        end
        raw_prev[key] = down
    end
    return hit
end

local function set_hold(id)
    local keys = PUSH[id]
    if not keys then
        return
    end

    if #keys == 0 then
        G.vk = nil
        return
    end

    local vk = {}
    for i = 1, #keys do
        vk[keys[i]] = true
    end
    G.vk = vk
end

local function clear_hold()
    G.vk = nil
    G.jev_drive = false
end

local function nearest_hazard()
    local M = G.M
    local best_d = 1e9
    local best = nil
    for _, e in ipairs(G.EN or {}) do
        local ex = e.x or 0
        local ez = e.z or 0
        local dx = ex - M.x
        local dz = ez - M.z
        local d = sqrt(dx * dx + dz * dz)
        if d < best_d then
            best_d = d
            best = { kind = e.k, x = ex, z = ez, dist = d }
        end
    end

    if G.CUR and G.hgt then
        for dz = -8, 8 do
            for dx = -8, 8 do
                if dx ~= 0 or dz ~= 0 then
                    local d = sqrt(dx * dx + dz * dz)
                    local closer = d < best_d
                    local void = closer and not G.hgt(M.x + dx, M.z + dz)
                    if void then
                        best_d = d
                        best = {
                            kind = "edge",
                            x = M.x + dx,
                            z = M.z + dz,
                            dist = d,
                        }
                    end
                end
            end
        end
    end

    if not best then
        return nil
    end

    return {
        kind = best.kind,
        x = rnd(best.x),
        z = rnd(best.z),
        dist = rnd(best.dist),
    }
end

local function observe()
    local M = G.M
    return {
        x = rnd(M.x),
        z = rnd(M.z),
        vx = rnd(M.vx),
        vz = rnd(M.vz),
        phase = G.phase or "",
        hazard = nearest_hazard(),
        score = G.score or 0,
    }
end

------------------------------------------------------------------ flow
function G.music_race() music("race" .. tostring(((G.ci or 1) - 1) % 3 + 1)) end
local function to_title()
    if jev then
        jev:begin_human()
    end
    G.state = "title"
    G.won = false
    G.new_game_sim()
    G.reset_world()
    music("title")
end
G.to_title = to_title
local function new_game()
    G.reset_world(); G.new_game_sim(); G.finished = false
    G.state = "play"; G.cam_snap = true
    music(nil)
end
G.new_game = new_game

local ABOUT = "Roll the marble down six races from high z to low z before time runs out. "
    .. "Actions n, s, e, w, ne, nw, se, sw hold a screen-relative push; stop releases it. "
    .. "Observation x, z, vx, vz are the marble. phase is ready, race, goal, or timeup. "
    .. "hazard is the nearest steelie, muncher, acid, hammer, or edge."
jev = JevAuto.attach({
    port = mcp_port(),
    id = "marble_madness_remix",
    description = ABOUT,
    playing = function()
        if G.set_open then
            return false
        end
        return G.state == "play" or G.state == "pause"
    end,
    terminal = function()
        return G.state == "over"
    end,
    score = function()
        return G.score or 0
    end,
    human_edge = human_edge,
    observe = observe,
    actions = function()
        local world = {
            n = { 0.57, 0.82 },
            s = { -0.57, -0.82 },
            e = { -0.82, 0.57 },
            w = { 0.82, -0.57 },
            ne = { -0.17, 0.98 },
            nw = { 0.98, 0.17 },
            se = { -0.98, -0.17 },
            sw = { 0.17, -0.98 },
        }
        local ax = -0.57
        local az = -0.82
        local hazard = nearest_hazard()
        if hazard and hazard.dist and hazard.dist < 5 and G.M then
            local scale = (5 - hazard.dist) / 5
            ax = ax + (G.M.x - hazard.x) * scale
            az = az + (G.M.z - hazard.z) * scale
        end
        local best_id = "s"
        local best = -1e9
        for id, push in pairs(world) do
            local score = push[1] * ax + push[2] * az
            if score > best then
                best = score
                best_id = id
            end
        end
        return { { id = best_id, description = "Push down the course, away from a close edge.", score = best } }
    end,
    apply = function(id)
        set_hold(id)
    end,
    reset = function(seed)
        seed = tonumber(seed)
        if seed then
            math.randomseed(seed)
        end
        G.jev_drive = true
        G.vk = nil
        new_game()
        snapshot_raw()
    end,
    on_human = function()
        clear_hold()
    end,
})

local function game_over()
    G.state = "over"
    G.over_t = 0
    music(G.won and "ending" or nil)
    sfx(G.won and "goal" or "timeup")
    if jev:assisted() then
        return
    end
    if G.score > G.hiscore then
        G.hiscore = G.score
        save_hi()
    end
end

local acc = 0
local mprev = { x = 0, y = 0 }
local macc = { x = 0, y = 0 }
local function update(dt)
    flush_mats()
    dt = clamp(dt, 0, 0.1)   -- a negative frame time (timer hitch) would make every damp() explode
    jev:tick(dt)
    G.t = G.t + dt; G.dt = dt
    local k = { ret = edge("Return"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), qk = edge("Q"), f3 = edge("F3"), space = edge("Space") }
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        if k.ret or k.space or c.start then
            sfx("click")
            jev:begin_human()
            new_game()
        elseif c.jev then
            sfx("click")
            if not jev:start() then
                G.jev_drive = false
                G.vk = nil
                local err = jev:error() or "Jev could not start"
                G.banner_set(err, 5)
                pe_log("[MM] " .. err)
            end
        elseif k.o or c.set_t then
            open_settings()
        elseif c.quit_app then
            engine.quit()
        end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click") end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.qk or c.quit then to_title() end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then
                sfx("click")
                jev:begin_human()
                new_game()
            elseif k.esc or c.title then
                to_title()
            end
        end
    end
    st = G.state
    -- mouse trackball (relative mode in play)
    local mdx, mdy = 0, 0
    pcall(function() local d = input.get_mouse_delta(); if d then mdx, mdy = d.x or d[1] or 0, d.y or d[2] or 0 end end)
    if st == "play" and not G.set_open then
        local mx = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0)
        local my = (any("Up", "W") and 1 or 0) - (any("Down", "S") and 1 or 0)
        if (mx ~= 0 or my ~= 0) and (mx ~= mprev.x or my ~= mprev.y) and G.M.alive and G.phase == "race" then sfx("roll" .. tostring(floor(rand() * 6))) end
        mprev.x, mprev.y = mx, my
        if mx ~= 0 and my ~= 0 then mx, my = mx * 0.7071, my * 0.7071 end
        -- mouse flicks add a short impulse spread over the next frames
        if G.jev_drive then
            macc.x = 0
            macc.y = 0
        else
            macc.x = clamp(macc.x + mdx * 0.02, -3, 3)
            macc.y = clamp(macc.y - mdy * 0.02, -3, 3)
        end
        mx, my = mx + macc.x, my + macc.y
        macc.x, macc.y = macc.x * math.exp(-10 * dt), macc.y * math.exp(-10 * dt)
        if G.autoplay then mx, my = G.autoplay_fn() end
        local fx, fz, rx, rz = G.cam_axes()
        local inp = { ax = clamp(fx * my + rx * mx, -2, 2), az = clamp(fz * my + rz * mx, -2, 2) }
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 4 do
            G.course_step(inp, FR)
            acc = acc - FR; n = n + 1
        end
        if acc > FR * 4 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if G.finished and G.state == "play" then G.finished = false; game_over() end
        -- rolling sound loop scaled by speed
        G.roll_t = (G.roll_t or 0) - dt
        if G.roll_t <= 0 and G.M.alive and not G.M.air and (G.speed or 0) > 2 then G.roll_t = 0.45; sfx("roll" .. tostring(min(5, floor(G.speed / 2.5)))) end
    else AL = 1 end
    render_world(dt)
    update_camera(dt)
    do local x, y, z = G.marble_pos(); update_lights(dt, vec3(x, y, z)) end
    -- test hook: per-frame rendered marble positions (see README "Testing")
    if G.trace and #G.trace < 900 then local p = G.rendered_pos(); local R = G.rend_R or {}
        G.trace[#G.trace + 1] = { dt, p[1], p[3], G.speed or 0, p[2], R[1] or 0, R[2] or 0, R[3] or 0, R[5] or 0, G.phase, AL } end
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end
-- debug autopilot for tests/screenshots only: steer toward the next checkpoint, then the goal
function G.autoplay_fn()
    local M, C = G.M, G.CUR
    local t = C.checks[G.check + 1]
    local tx, tz
    if t then tx, tz = t[1], t[2] else local g = C.goal; tx, tz = (g[1] + g[3]) / 2, (g[2] + g[4]) / 2 end
    local dx, dz = tx - M.x - M.vx * 0.35, tz - M.z - M.vz * 0.35
    local fx, fz, rx, rz = G.cam_axes()
    local my = clamp((dx * fx + dz * fz) * 0.5, -1, 1)
    local mx = clamp((dx * rx + dz * rz) * 0.5, -1, 1)
    return mx, my
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_world()
to_title()
G.update = update; G.SET = SET
hooks { update = update }
pe_log("[MM] ready")
