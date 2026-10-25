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
    c.start = button("b_start", "Start (Enter)", SW / 2 - 200 * US, yb, title)
    c.jev = button("b_jev", "Jev", SW / 2 + 200 * US, yb, title)
    yb = yb + 76 * US
    c.cont = button("b_cont", "Continue Stage " .. tostring(G.cont_stage or 1), SW / 2, yb, hasc); if hasc then yb = yb + 76 * US end
    c.set_t = button("b_set_t", "Settings (O)", SW / 2, yb, title); yb = yb + 76 * US
    c.quit_app = button("b_quit_app", "Quit Game", SW / 2, yb, title)
    c.resume = button("b_resume", "Resume (P)", SW / 2, SH * 0.42, pause)
    c.set_p = button("b_set_p", "Settings (O)", SW / 2, SH * 0.42 + 76 * US, pause)
    c.quit = button("b_quit", "Quit to Title (Q)", SW / 2, SH * 0.42 + 152 * US, pause)
    local ov = over and (G.over_t or 0) > 1.2
    c.again = button("b_again", "Play Again (Enter)", SW / 2, SH * 0.5, ov)
    c.title = button("b_title", "Title (Esc)", SW / 2, SH * 0.5 + 76 * US, ov)
    text("t_jerr", G.jev_err or "", 40 * US, SH * 0.82, SW - 80 * US, 32 * US, 0.8, RED, "center", (title or st == "pause") and G.jev_err ~= nil)
    return c
end

------------------------------------------------------------------ flow
local jev
local function to_title()
    jev:begin_human()
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
    if jev and jev:assisted() then return end
    if G.score > G.hiscore then G.hiscore = G.score; save_hi() end
end
G.cont_stage = 1

-- Hardware edges only. Virtual keys live in G.vk and must not count as a human.
local RAW_PLAY = { "Left", "Right", "A", "D", "Up", "Down", "W", "S", "Space", "Z", "J" }
local raw_prev = {}
local human_edged = false
local function sample_human()
    local raw = input.is_key_down_raw
    human_edged = false
    if not raw then
        return
    end

    for i = 1, #RAW_PLAY do
        local key = RAW_PLAY[i]
        local ok, v = pcall(raw, key)
        local down = ok and v and true or false
        -- Settings uses these keys to turn Jev on. That is not the player taking the match.
        if down and not raw_prev[key] and not G.set_open then
            human_edged = true
        end
        raw_prev[key] = down
    end
end

local function clear_hold()
    G.vk = {}
    G.fire_pulse = false
    G.jev_x = nil
    G._jev_cache = nil
end

local function round2(v)
    if v >= 0 then
        return floor(v * 100 + 0.5) / 100
    end
    return floor(v * 100 - 0.5) / 100
end

local function nearest_balloon()
    local best, best_d = nil, 1e18
    for _, b in ipairs(BALLS) do
        local dx = b.x - P.x
        local dy = b.y - P.y
        local d = dx * dx + dy * dy
        if d < best_d then
            best, best_d = b, d
        end
    end
    return best
end

local function shot_free()
    if P.st == "dead" or (P.stun or 0) > 0 then return false end
    if P.weapon == "vulcan" then
        return (P.vcool or 0) <= 0 and #SHOTS < 8
    end
    local cap = (P.weapon == "double") and 2 or 1
    return #ROPES < cap
end

local jev_target, wire_outcome
jev_target, wire_outcome = (function()
-- Beside the body. Stepping against the balloon's vx so it does not chase us into the wall.
local function escape_x(b)
    local safe = b.r * HB.ball_k + HB.pw + 0.45
    local dir = 1
    if b.vx > 0.4 then dir = -1 elseif b.vx < -0.4 then dir = 1
    else dir = ((X1 - b.x) >= (b.x - X0)) and 1 or -1 end
    if P.x > b.x + 0.35 then dir = 1 elseif P.x < b.x - 0.35 then dir = -1 end
    local side = b.x + dir * safe
    if side < X0 + PHW or side > X1 - PHW then dir = -dir end
    return clamp(b.x + dir * safe, X0 + PHW, X1 - PHW)
end

local function copy_balls()
    local out = {}
    for i, b in ipairs(BALLS) do
        out[i] = { x = b.x, y = b.y, vx = b.vx, vy = b.vy, r = b.r, size = b.size }
    end
    return out
end

local function step_copy(b, dt)
    b.vy = b.vy - GRAV * dt
    b.x = b.x + b.vx * dt
    b.y = b.y + b.vy * dt
    local r = b.r
    if b.x - r < X0 then b.x = X0 + r; b.vx = abs(b.vx) end
    if b.x + r > X1 then b.x = X1 - r; b.vx = -abs(b.vx) end
    if b.y + r > CEIL then b.y = CEIL - r; b.vy = -abs(b.vy) end
    if b.y - r < 0 then b.y = r; b.vy = BV[b.size] end
    for _, k in ipairs(ST.blocks) do
        if k.live then
            local px, py = clamp(b.x, k.x0, k.x1), clamp(b.y, k.y0, k.y1)
            local dx, dy = b.x - px, b.y - py
            if dx * dx + dy * dy < r * r then
                if abs(dy) >= abs(dx) then
                    if dy > 0 or (dy == 0 and b.y > (k.y0 + k.y1) / 2) then b.y = k.y1 + r; b.vy = BV[b.size]
                    else b.y = k.y0 - r; b.vy = -abs(b.vy) end
                else
                    if dx > 0 then b.x = k.x1 + r; b.vx = abs(b.vx) else b.x = k.x0 - r; b.vx = -abs(b.vx) end
                end
            end
        end
    end
end

local function body_hit(px, b)
    return circ_box(b.x, b.y, b.r * HB.ball_k, px - HB.pw, P.y + HB.py0, px + HB.pw, P.y + HB.py1)
end

local function rope_touch(x, y0, tip, b)
    local cy = clamp(b.y, y0, tip)
    local dx, dy = b.x - x, b.y - cy
    local rad = b.r + HB.rope
    return dx * dx + dy * dy < rad * rad
end

local function wire_blocked(x, y0, tip)
    for _, k in ipairs(ST.blocks) do
        if k.live and x > k.x0 - 0.05 and x < k.x1 + 0.05 and y0 < k.y0 and tip >= k.y0 then return true end
    end
    return false
end

local function walk_x(x, dir, dt)
    local nx = clamp(x + dir * PW * dt, X0 + PHW, X1 - PHW)
    if dir == 0 then return x end
    for _, k in ipairs(ST.blocks) do
        if k.live and k.y0 < P.y + PH - 0.2 and k.y1 > P.y + 0.15 then
            if dir > 0 and x + PHW <= k.x0 + 0.01 and nx + PHW > k.x0 then return k.x0 - PHW end
            if dir < 0 and x - PHW >= k.x1 - 0.01 and nx - PHW < k.x1 then return k.x1 + PHW end
        end
    end
    return nx
end

-- Walk to stand, then fire. A miss keeps the wire out until the ceiling, so a plan that
-- does not hit is not a shot. Also reject a walk the balloon would land on.
local function wire_outcome(stand, t_fire)
    local balls = copy_balls()
    local t, px = 0, P.x
    local dir = stand > P.x + 0.01 and 1 or (stand < P.x - 0.01 and -1 or 0)
    while t < t_fire do
        local step = min(FR, t_fire - t)
        px = walk_x(px, dir, step)
        for _, b in ipairs(balls) do
            step_copy(b, step)
            if body_hit(px, b) then return false, t + step end
        end
        t = t + step
    end
    if abs(px - stand) > 0.45 then return false, t end
    local y0, tip0 = P.y, P.y + 1.8
    local flight = (CEIL - tip0) / WIRE_V
    if flight < 0.02 then return false, t end
    local fired = 0
    while fired < flight do
        local step = min(FR, flight - fired)
        fired = fired + step
        local tip = min(CEIL, tip0 + WIRE_V * fired)
        local blocked = wire_blocked(stand, y0, tip)
        for _, b in ipairs(balls) do
            step_copy(b, step)
            if body_hit(stand, b) then return false, t + fired end
            if not blocked and rope_touch(stand, y0, tip, b) then return true, t + fired end
        end
        if blocked then return false, t + fired end
    end
    return false, t + flight
end

-- Remaining time of a wire already in the air, and whether it still hits a balloon.
local function rope_time(r)
    if r.st ~= "rise" then return r.t or 0, true end
    local balls = copy_balls()
    local tip, t = r.tip, 0
    while tip < CEIL - 0.05 and t < 2 do
        local step = min(FR, (CEIL - tip) / WIRE_V)
        if step < 1e-4 then break end
        t = t + step
        tip = min(CEIL, tip + WIRE_V * step)
        local blocked = wire_blocked(r.x, r.y0, tip)
        for _, b in ipairs(balls) do
            step_copy(b, step)
            if not blocked and rope_touch(r.x, r.y0, tip, b) then return t, true end
        end
        if blocked then return t, false end
    end
    return t, false
end

local function miss_flight()
    local flight = (CEIL - (P.y + 1.8)) / WIRE_V
    if flight < 0.2 then flight = 0.2 end
    return flight
end

-- Safe x for the whole lock. A miss lasts until the ceiling, so look that far ahead.
local function avoid_x(duration, why)
    local balls = copy_balls()
    local threat, gap, t = nil, 1e18, 0
    while t < duration do
        local step = min(FR, duration - t)
        for _, b in ipairs(balls) do
            step_copy(b, step)
            if b.y - b.r * HB.ball_k < P.y + HB.py1 + 0.4 and b.y + b.r * HB.ball_k > P.y + HB.py0 then
                local g = abs(b.x - P.x)
                if g < gap then
                    gap = g
                    threat = { x = b.x, vx = b.vx, r = b.r }
                end
            end
        end
        t = t + step
    end
    if threat then return escape_x(threat), false, why end
    local near = nearest_balloon()
    if not near then return P.x, false, "none" end
    return escape_x(near), false, why
end

local function best_stand()
    local hit = wire_outcome(P.x, 0)
    if hit then return P.x end
    local balls = copy_balls()
    local tip0 = P.y + 1.8
    local flight_max = (CEIL - tip0) / WIRE_V
    local tries, best_x, best_t, t = {}, nil, 1e18, 0
    while t < 1.4 do
        for _, b in ipairs(balls) do step_copy(b, FR) end
        t = t + FR
        for i, b in ipairs(balls) do
            if (tries[i] or 0) < 2 then
                local flight = (b.y - tip0) / WIRE_V
                if flight > 0.05 and flight < flight_max - 0.03 then
                    local t_fire = t - flight
                    if t_fire < 0 then t_fire = 0 end
                    local stand = clamp(b.x, X0 + PHW, X1 - PHW)
                    if abs(stand - P.x) / PW <= t_fire + 0.03 then
                        tries[i] = (tries[i] or 0) + 1
                        local ok, tw = wire_outcome(stand, t_fire)
                        if ok and tw < best_t then best_x, best_t = stand, tw end
                    end
                end
            end
        end
    end
    return best_x
end

local function span(l)
    if l.y1 >= l.y0 then return l.y0, l.y1 end
    return l.y1, l.y0
end

local function wall_between(x0, x1, y)
    local a, b = min(x0, x1), max(x0, x1)
    for _, k in ipairs(ST.blocks) do
        if k.live and k.y0 < y + PH - 0.2 and k.y1 > y + 0.15 then
            if k.x0 < b - 0.15 and k.x1 > a + 0.15 then return true end
        end
    end
    return false
end

local function crab_x_at(a, t)
    local x, vx = a.x, a.vx
    local left, right = X0 + 1, X1 - 1
    local remain, guard = t, 0
    while remain > 1e-4 and guard < 8 do
        guard = guard + 1
        if vx > 0.01 then
            local dt = (right - x) / vx
            if dt >= remain then return x + vx * remain end
            x, vx, remain = right, -abs(vx), remain - dt
        elseif vx < -0.01 then
            local dt = (x - left) / -vx
            if dt >= remain then return x + vx * remain end
            x, vx, remain = left, abs(vx), remain - dt
        else
            return x
        end
    end
    return x
end

-- A crab stuns on the ground. Step to the open side, or climb if one is underfoot.
local function creep_plan()
    if P.st == "climb" and P.ladder and P.ladder.y1 >= 1.2 and P.y < 1.05 then return P.ladder.x, 1 end
    if (P.inv or 0) > 0.15 or P.y >= 1.05 or P.st == "dead" then return nil end
    local best, bt
    for _, a in ipairs(ANIMALS) do
        if a.kind == "crab" and a.st ~= "hit" then
            local t = 0
            while t <= 0.85 do
                if abs(crab_x_at(a, t) - P.x) < 1.25 then
                    if not best or t < bt then best, bt = a, t end
                    break
                end
                t = t + 0.05
            end
        end
    end
    if not best then return nil end
    local away = best.x >= P.x and -1 or 1
    local dest = clamp(P.x + away * 4.5, X0 + PHW, X1 - PHW)
    if abs(dest - P.x) < 0.4 then
        away = -away
        dest = clamp(P.x + away * 4.5, X0 + PHW, X1 - PHW)
    end
    if bt < 0.5 then
        for _, l in ipairs(ST.ladders) do
            local foot, top = span(l)
            if abs(l.x - P.x) < 0.8 and abs(P.y - foot) < 0.45 and top >= 1.2 and not wall_between(P.x, l.x, P.y) then
                return l.x, 1
            end
        end
    end
    return dest, 0
end

local function balloon_clear(x, y)
    for _, b in ipairs(BALLS) do
        if b.y - b.r < y + HB.py1 and b.y + b.r > y + HB.py0 and abs(b.x - x) < b.r * HB.ball_k + HB.pw + 0.3 then
            return false
        end
    end
    return true
end

local function crab_hits(x, y, within)
    if y >= 1 then return false end
    for _, a in ipairs(ANIMALS) do
        if a.kind == "crab" and a.st ~= "hit" then
            local t = 0
            while t <= within do
                if abs(crab_x_at(a, t) - x) < 1.2 then return true end
                t = t + 0.1
            end
        end
    end
    return false
end

local function ladder_between(item_y)
    local best, bd
    for _, l in ipairs(ST.ladders) do
        local foot, top = span(l)
        if P.y >= foot - 0.45 and P.y <= top + 0.45 and item_y >= foot - 0.5 and item_y <= top + 0.5 then
            local d = abs(l.x - P.x)
            if not best or d < bd then best, bd = l, d end
        end
    end
    return best
end

local function pickup_plan()
    local aim, why, v, score = nil, nil, 0, -1e18
    for _, it in ipairs(ITEMS) do
        local life = 7 - (it.t or 0)
        if life > 0.4 then
            local fruit = it.kind == "fruit"
            local worth = fruit and 2 or 5
            if it.kind == "life" then worth = 8 end
            local iy = it.y
            if not it.landed then iy = support_at(it.x, it.y, 0.3, 0.4, 40) or 0 end
            local same = abs(iy - P.y) < 0.8
            local safe = balloon_clear(it.x, iy) and balloon_clear((P.x + it.x) / 2, P.y)
            if same and not wall_between(P.x, it.x, P.y) and not crab_hits(it.x, iy, 0.7) and safe then
                local s = worth * 12 - abs(it.x - P.x) + life
                if s > score then aim, why, v, score = it.x, fruit and "fruit" or "item", 0, s end
            else
                local lad = ladder_between(iy)
                if lad and not wall_between(P.x, lad.x, P.y) and not crab_hits(lad.x, P.y, 0.6) and balloon_clear(lad.x, P.y) then
                    local s = worth * 8 - abs(lad.x - P.x) - abs(iy - P.y) + life
                    if s > score then
                        local on = abs(P.x - lad.x) < 0.55 or P.st == "climb"
                        local dir = 0
                        if on then
                            if iy > P.y + 0.3 then dir = 1 elseif iy < P.y - 0.3 then dir = -1 end
                        end
                        local x = (abs(iy - P.y) < 0.8) and it.x or lad.x
                        aim, why, v, score = x, fruit and "fruit" or "item", dir, s
                    end
                end
            end
        end
    end
    if aim then return aim, why, v end
end

local function route_around(x, can, why, v)
    if (v or 0) ~= 0 then return x, can, why, v end
    if not wall_between(P.x, x, P.y) then return x, can, why, v end
    local lad, best
    for _, l in ipairs(ST.ladders) do
        local foot, top = span(l)
        if abs(P.y - foot) < 0.5 and top > P.y + 1.2 and not wall_between(P.x, l.x, P.y) then
            local d = abs(l.x - x)
            if not lad or d < best then lad, best = l, d end
        end
    end
    if not lad then return x, can, why, v end
    local dir = 0
    if abs(P.x - lad.x) < 0.55 or P.st == "climb" then dir = 1 end
    return lad.x, false, "route", dir
end

local function field_plan(x, can, why)
    local cx, cv = creep_plan()
    if cx then return route_around(cx, false, "creep", cv) end
    local shooting = can and abs(x - P.x) <= 0.5
    local px, pwhy, pv = pickup_plan()
    if px and not shooting and (not can or abs(px - P.x) + 0.4 < abs(x - P.x)) then
        return route_around(px, false, pwhy, pv)
    end
    return route_around(x, can, why, 0)
end

local function jev_target()
    local cache = G._jev_cache
    if cache and cache.t == G.t then return cache.b, cache.x, cache.can, cache.why, cache.v end
    local balloon = nearest_balloon()
    local x, can, why
    if not balloon then
        x, can, why = P.x, false, "none"
    elseif balloon.y <= balloon.r + HB.py1 then
        x, can, why = escape_x(balloon), false, "low"
    elseif not shot_free() then
        local remain, will_hit = 0, true
        for _, r in ipairs(ROPES) do
            local rt, rh = rope_time(r)
            if rt > remain then remain, will_hit = rt, rh end
        end
        if remain < 0.15 then remain = 0.15 end
        why = will_hit and "busy" or "miss"
        x, can = avoid_x(remain, why)
        can = false
    else
        local stand = best_stand()
        if stand then
            x, can, why = stand, true, "shoot"
        else
            x, can, why = avoid_x(miss_flight(), "miss")
            can = false
        end
    end
    local v
    x, can, why, v = field_plan(x, can, why)
    v = v or 0
    G._jev_cache = { t = G.t, b = balloon, x = x, can = can, why = why, v = v }
    return balloon, x, can, why, v
end
return jev_target, wire_outcome
end)()

local jev_source = assert(fs.read("Scripts/jev_auto.lua"), "Missing Jev module: Scripts/jev_auto.lua")
local JevAuto = assert(load(jev_source, "@Scripts/jev_auto.lua", "t", _ENV))()
jev = JevAuto.attach({
    port = 9133,
    id = "pang-remix",
    description = "Pang Remix. One wire flies at a time, straight up. Fire only when the shot hits a balloon before the ceiling. A miss stays out until the ceiling, so stay clear of the balloon for that whole trip. A crab stuns you on the ground: step away, or climb a ladder off the floor. Climb ladders to fruit and power-ups. If a block walls the floor, climb around it. Prefer the higher action score.",
    playing = function()
        local state = G.state
        return state == "intro" or state == "play" or state == "clear"
    end,
    terminal = function()
        return G.state == "over"
    end,
    score = function()
        return G.score or 0
    end,
    -- No hop. Death and stun are not started by apply.
    busy = function()
        return false
    end,
    human_edge = function()
        return human_edged
    end,
    observe = function()
        local balloon = nearest_balloon()
        return {
            player_x = round2(P.x),
            player_y = round2(P.y),
            balloon_x = balloon and round2(balloon.x) or 0,
            balloon_y = balloon and round2(balloon.y) or 0,
            shot = shot_free(),
            wire = select(4, jev_target()),
            lives = G.lives or 0,
            score = G.score or 0,
        }
    end,
    actions = function()
        local balloon, aim, can, why = jev_target()
        local dx = aim - P.x
        local text
        if why == "creep" then
            text = "Step away from the crab. It stuns you on the ground."
        elseif why == "fruit" then
            text = "Pick up the fruit before it disappears. Climb the ladder when the fruit is above you."
        elseif why == "item" then
            text = "Climb the ladder or walk to the power-up."
        elseif why == "route" then
            text = "The floor is blocked. Climb the ladder and go around."
        elseif not balloon then
            text = "No balloon. Hold."
        elseif can then
            text = "Step onto the shot line. This wire hits the balloon before the ceiling."
        elseif why == "miss" then
            text = "Stay clear. This shot misses, so the wire stays out until the ceiling."
        elseif why == "busy" then
            text = "Stay beside the balloon. The wire is already out."
        elseif why == "low" then
            text = "Stay beside the balloon. It is too low for the wire to hit above you."
        else
            text = "Stay beside the balloon. You cannot reach a shot that hits."
        end
        if dx > 0.3 then
            return { { id = "right", description = text, score = dx } }
        end
        if dx < -0.3 then
            return { { id = "left", description = text, score = -dx } }
        end
        return { { id = "stop", description = text, score = 1 } }
    end,
    apply = function(id)
        if id ~= "left" and id ~= "right" and id ~= "up" and id ~= "down" and id ~= "stop" then
            return
        end

        clear_hold()
        -- Hold the aim point. A held Left key keeps walking after the balloon has
        -- been passed and pins Jev in the left wall until the next reply.
        if id == "left" or id == "right" or id == "stop" then
            local _, aim = jev_target()
            G.jev_x = aim
        elseif id == "up" then
            G.vk.Up = true
        elseif id == "down" then
            G.vk.Down = true
        end
    end,
    reset = function(seed)
        math.randomseed(seed)
        clear_hold()
        new_game(1)
    end,
    on_human = function()
        clear_hold()
    end,
})

SET.opts.on_change = function(id, value)
    if id ~= "jev" then return end
    local on = value and true or false
    if on then
        local live = G.state == "intro" or G.state == "play" or G.state == "pause" or G.state == "clear"
        local ok, err
        if live then ok, err = jev:engage() else ok, err = jev:start() end
        if not ok then
            SET.cfg.jev = false
            G.jev_err = err or jev:error() or "Jev could not start"
            pe_log("[PG] " .. G.jev_err)
            if not live then to_title() end
        else
            G.jev_err = nil
            SET.cfg.jev = true
            if live then G.jev_x = P.x end
        end
    else
        jev:begin_human()
        SET.cfg.jev = false
        G.jev_err = nil
    end
end

local acc = 0
G.fire_q = false
local mouse_prev = true
local function update(dt)
    if G.on_frame then G.on_frame(dt) end
    sample_human()
    jev:tick(dt)
    if P.weapon ~= "vulcan" and G.vk then
        G.vk.Space = nil
    end
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
    local function open_settings()
        sfx("click")
        SET.cfg.jev = jev:assisted() and true or false
        SET:open()
        G.set_open = true
    end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        if k.ret or k.space or c.start then
            sfx("click")
            G.jev_err = nil
            jev:begin_human()
            new_game(1)
        elseif c.jev then
            sfx("click")
            G.jev_err = nil
            if not jev:start() then
                G.jev_err = jev:error() or "Jev could not start"
                pe_log("[PG] " .. G.jev_err)
                to_title()
            end
        elseif c.cont then
            sfx("click")
            G.jev_err = nil
            jev:begin_human()
            new_game(G.cont_stage)
        elseif k.o or c.set_t then
            open_settings()
        elseif c.quit_app then
            engine.quit()
        end
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
            if k.ret or k.space or c.again then
                sfx("click")
                G.jev_err = nil
                jev:begin_human()
                new_game(1)
            elseif k.esc or c.title then
                to_title()
            end
        end
    end
    if G.set_open then
        local want = SET:get("jev") and true or false
        if want ~= (jev:assisted() and true or false) then SET.opts.on_change("jev", want) end
    end
    st = G.state
    local running = (st == "play" or st == "title") and not (G.set_open and st ~= "title")
    if running then
        if st == "play" and (k.space or k.z or k.j or mclick or G.fire_pulse) then
            G.fire_q = true
            G.fire_pulse = false
        end
        local h = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0)
        local climb = 0
        if st == "play" and G.jev_x and jev:assisted() then
            local _, aim, can, _, v = jev_target()
            climb = v or 0
            if climb == 0 and P.st == "climb" and P.ladder then
                local l = P.ladder
                climb = (P.y - l.y0) <= (l.y1 - P.y) and -1 or 1
            end
            G.jev_x = aim
            local hit_now = can and wire_outcome(P.x, 0)
            if hit_now then
                if P.weapon == "vulcan" then G.vk.Space = true else G.fire_q = true end
            elseif G.vk then
                G.vk.Space = nil
            end
            local dx = G.jev_x - P.x
            if dx > 0.3 then h = 1 elseif dx < -0.3 then h = -1 else h = 0 end
        end
        local vkey = (any("Up", "W") and 1 or 0) - (any("Down", "S") and 1 or 0)
        if st == "play" and G.jev_x and jev:assisted() then vkey = climb end
        local inp = { h = h, v = vkey,
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
