-- Arrow Out (PhasmaEngine, Lua): tap bent arrows to slide them off the board.
-- An arrow leaves only if nothing stands on its head's path; a blocked arrow bumps and costs a heart.
-- Pure rules live in arrow_rules.lua; this file is the runtime-UI view and input.
local function module(path)
    local source = assert(fs.read(path), "Missing Arrow Out module: " .. path)
    return assert(load(source, "@" .. path, "t", _ENV))()
end
local R = module("Scripts/arrow_rules.lua")
local SettingsMenu = module("Scripts/Lib/settings_menu.lua") -- shared menu, same copy as the Arcade games

local SCREEN = "arrowout"
local floor, min, max, abs, sin = math.floor, math.min, math.max, math.abs, math.sin
local CLEAR = { 0, 0, 0, 0 }
local BG = { 0.045, 0.05, 0.085, 1 }
local BOARD = { 0.075, 0.085, 0.135, 1 }
local DOT = { 0.2, 0.23, 0.33, 1 }
local INK = { 0.86, 0.89, 0.96 }
local HOVER = { 0.35, 0.9, 1.0 }
local HINT = { 1.0, 0.8, 0.3 }
local BAD = { 1.0, 0.33, 0.36 }
local GOOD = { 0.4, 1.0, 0.65 }
local WHITE = { 1, 1, 1, 1 }
local DIM = { 0.62, 0.68, 0.8, 1 }
local HEAD_IMG = { "Textures/head_up.png", "Textures/head_right.png", "Textures/head_down.png", "Textures/head_left.png" }

local saved = tonumber(fs.read("Save/arrowout_level.txt") or "1") or 1
local S = {
    level = max(1, floor(saved)), best = max(1, floor(saved)),
    mode = "play", t = 0, shake = 0, hints = 0, card_t = 0,
}
local game
local anims, flashes, dirty, widgets = {}, {}, {}, {}
local hover_id, hint_id, hint_t = 0, 0, 0
local L = {} -- layout: surface size, ui scale, board rect, cell size
_G.arrowout = { S = S, R = R, game = function() return game end }

local function sound(name) if audio and audio.play then pcall(audio.play, name .. ".wav") end end -- volume and mute: settings menu
local SET = SettingsMenu.new({ title = "SETTINGS", click = function() sound("click") end })
_G.arrowout.settings = SET
do -- Flat 2D game: bloom, ambient occlusion and particles change nothing, so drop those rows (shared lib untouched).
    local keep, hidden = {}, { bloom = true, ssao = true, particles = true }
    for _, row in ipairs(SET.rows) do if not hidden[row.id] then keep[#keep + 1] = row end end
    SET.rows = keep
end

------------------------------------------------------------------ widgets
local function quad(id, o)
    o.fill = o.fill or CLEAR
    o.border = o.border or CLEAR
    o.accent = CLEAR
    if o.no_input == nil then o.no_input = true end
    if o.visible == nil then o.visible = true end
    widgets[id] = o.visible
    runtime_ui.set_quad(SCREEN, id, o)
end
local function hide(id)
    if widgets[id] then widgets[id] = false; runtime_ui.set_quad(SCREEN, id, { visible = false, x = 0, y = 0, width = 1, height = 1, no_input = true }) end
end
local function rect(id, x, y, w, h, fill, z, radius)
    quad(id, { style = "text", label = "", x = x, y = y, width = w, height = h, z = z, fill = fill, corner_radius = radius or 0 })
end
local function text(id, s, x, y, w, h, size, color, z, align)
    quad(id, { style = "text", label = s, x = x, y = y, width = w, height = h, z = z or 40, font_scale = size * L.k,
        text_color = color or WHITE, align_h = align or "center", align_v = "middle" })
end
local function button(id, caption, x, y, w, h, primary, z)
    quad(id, { style = "button", title = caption, x = x, y = y, width = w, height = h, z = z or 50, no_input = false,
        corner_radius = 10 * L.k, font_scale = 1.1 * L.k,
        fill = primary and { 0.36, 0.87, 0.75, 1 } or { 0.1, 0.13, 0.21, 1 },
        border = primary and CLEAR or { 0.3, 0.36, 0.51, 0.7 },
        text_color = primary and { 0.025, 0.09, 0.11, 1 } or WHITE })
end
local function clicked(id)
    local s = runtime_ui.get_state(SCREEN, id)
    return s and s.clicked == true
end

------------------------------------------------------------------ layout
local function cell_center(x, y)
    return L.bx + (x - 0.5) * L.cs, L.by + (y - 0.5) * L.cs
end

local function layout()
    local surf = runtime_ui.get_surface_size()
    local w, h = surf.width or 1280, surf.height or 800
    if w <= 0 or h <= 0 then return false end
    if L.w == w and L.h == h and L.gw == game.w and L.gh == game.h then return false end
    L.w, L.h, L.gw, L.gh = w, h, game.w, game.h
    L.k = min(w / 1600, h / 1000)
    local top, bottom, side = 110 * L.k, 110 * L.k, 40 * L.k
    L.cs = floor(min((w - 2 * side) / game.w, (h - top - bottom) / game.h))
    L.bw, L.bh = L.cs * game.w, L.cs * game.h
    L.bx0 = floor((w - L.bw) / 2)
    L.by0 = floor(top + (h - top - bottom - L.bh) / 2)
    L.bx, L.by = L.bx0, L.by0
    L.th = max(2, floor(L.cs * 0.13 + 0.5))
    return true
end

------------------------------------------------------------------ arrows
local function arrow_point(a, t)
    -- Arc position t along the arrow's path: cells tail->head, then onward past the head.
    local n = #a.cells
    local i = floor(t)
    local f = t - i
    local function P(j) -- j is 0-based along the path
        if j < n then return a.cells[j + 1][1], a.cells[j + 1][2] end
        local hd, d = a.cells[n], R.DIRS[a.dir]
        return hd[1] + d[1] * (j - n + 1), hd[2] + d[2] * (j - n + 1)
    end
    local x0, y0 = P(i)
    if f == 0 then return x0, y0 end
    local x1, y1 = P(i + 1)
    return x0 + (x1 - x0) * f, y0 + (y1 - y0) * f
end

local function lerp_col(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end

local function arrow_style(id)
    local a, an = game.arrows[id], anims[id]
    local s, alpha, col = 0, 1, INK
    if an then
        local p = min(1, an.t / an.dur)
        if an.kind == "slide" then
            s = an.dist * p * p
            col = lerp_col(HOVER, INK, p)
            alpha = 1 - max(0, (p - 0.55) / 0.45)
        else
            local reach = an.steps + 0.35
            if p < 0.4 then local q = p / 0.4; s = reach * (1 - (1 - q) * (1 - q))
            else s = reach * (1 - (p - 0.4) / 0.6) end
            col = BAD
        end
    elseif flashes[id] then
        col = lerp_col(INK, BAD, min(1, flashes[id] / 0.25))
    elseif id == hint_id then
        col = lerp_col(INK, HINT, 0.55 + 0.45 * sin(S.t * 7))
    elseif id == hover_id and S.mode == "play" then
        col = HOVER
    end
    return s, alpha, col, a
end

local function draw_arrow(id)
    local s, alpha, col, a = arrow_style(id)
    local n = #a.cells
    local c4 = { col[1], col[2], col[3], alpha }
    local th, cs = L.th, L.cs
    local x_lo, x_hi, y_lo, y_hi = L.bx, L.bx + L.bw, L.by, L.by + L.bh
    local visible = (a.alive or anims[id]) and true or false
    -- Head: a straight lead-in leaves the head cell's centre in the head direction and the arrowhead
    -- sits at its end, so a body that turns in the head cell bends well clear of the arrowhead.
    local t_end = s + n - 1
    local hx, hy = arrow_point(a, t_end)
    local px, py = cell_center(hx, hy)
    local d = R.DIRS[a.dir]
    local hs = cs * 0.34
    local base = cs * 0.22                     -- arrowhead base distance from the head cell's centre
    local k = 0
    if visible then
        -- Polyline in pixels: tail, every cell centre passed, head, end of the lead-in.
        local pts = {}
        local function push(x, y)
            local m = #pts
            -- Drop the previous point when it sits in the middle of a straight run: one bar per run
            -- means no seams where cells join.
            if m >= 2 and ((pts[m - 1][1] == pts[m][1] and pts[m][1] == x) or (pts[m - 1][2] == pts[m][2] and pts[m][2] == y)) then
                pts[m] = { x, y }
            elseif m == 0 or pts[m][1] ~= x or pts[m][2] ~= y then
                pts[m + 1] = { x, y }
            end
        end
        push(cell_center(arrow_point(a, s)))
        for j = floor(s) + 1, math.ceil(t_end) - 1 do push(cell_center(arrow_point(a, j))) end
        push(px, py)
        push(px + d[1] * (base + 1), py + d[2] * (base + 1))
        -- Each bar has round ends (radius = half the thickness), so bends get a smooth rounded join.
        for i = 2, #pts do
            local p, q = pts[i - 1], pts[i]
            local x0, x1 = max(min(p[1], q[1]) - th / 2, x_lo), min(max(p[1], q[1]) + th / 2, x_hi)
            local y0, y1 = max(min(p[2], q[2]) - th / 2, y_lo), min(max(p[2], q[2]) + th / 2, y_hi)
            if x1 - x0 > 0.5 and y1 - y0 > 0.5 then
                k = k + 1
                rect("a" .. id .. "_" .. k, x0, y0, x1 - x0, y1 - y0, c4, 5, th / 2)
            end
        end
    end
    for j = k + 1, n + 2 do hide("a" .. id .. "_" .. j) end
    local cx, cy = px + d[1] * (base + hs / 2), py + d[2] * (base + hs / 2)
    if visible and cx > x_lo and cx < x_hi and cy > y_lo and cy < y_hi then
        quad("h" .. id, { style = "image", path = HEAD_IMG[a.dir], x = cx - hs / 2, y = cy - hs / 2, width = hs, height = hs,
            z = 6, image_tint = c4 })
    else
        hide("h" .. id)
    end
end

------------------------------------------------------------------ hud
local function draw_static()
    local k = L.k
    rect("bg", 0, 0, L.w, L.h, BG, 0)
    rect("board_bg", L.bx - 14 * k, L.by - 14 * k, L.bw + 28 * k, L.bh + 28 * k, BOARD, 1, 16 * k)
    -- Picture dots: show the level's shape faintly under the arrows.
    local ds = max(2, L.cs * 0.12)
    local used = 0
    for y = 1, game.h do
        for x = 1, game.w do
            if game.mask[(y - 1) * game.w + x] then
                used = used + 1
                local cx, cy = cell_center(x, y)
                rect("dot" .. used, cx - ds / 2, cy - ds / 2, ds, ds, DOT, 2, ds / 2)
            end
        end
    end
    for i = used + 1, (S.dots or 0) do hide("dot" .. i) end
    S.dots = max(S.dots or 0, used)
end

local function draw_hud()
    local k, w, h = L.k, L.w, L.h
    text("title", "ARROW OUT", 40 * k, 22 * k, 500 * k, 66 * k, 2.4, { 0.75, 0.93, 1, 1 }, 40, "left")
    text("level", "LEVEL " .. game.level .. "  ·  " .. string.upper(game.spec.shape.name), w / 2 - 300 * k, 22 * k, 600 * k, 66 * k, 1.7, WHITE)
    text("left", game.left .. " ARROWS", w - 540 * k, 22 * k, 300 * k, 66 * k, 1.4, DIM, 40, "right")
    for i = 1, R.LIVES do
        local alive = i <= game.lives
        local r = 30 * k
        rect("life" .. i, w - 40 * k - (R.LIVES - i + 1) * (r + 12 * k), 40 * k, r, r,
            alive and { 1, 0.34, 0.42, 1 } or { 0.22, 0.24, 0.32, 1 }, 40, r / 2)
    end
    -- Input quads draw in their own layer above plain quads whatever their z, so the board's click
    -- catcher is transparent, and every input quad hides while the settings menu is open.
    if SET:is_open() then
        for _, id in ipairs({ "board", "btn_hint", "btn_restart", "btn_settings", "btn_card" }) do hide(id) end
    else
        quad("board", { style = "text", label = "", x = L.bx0, y = L.by0, width = L.bw, height = L.bh, z = 1, no_input = false })
        local bw, bh, y, gap = 210 * k, 62 * k, h - 88 * k, 24 * k
        button("btn_hint", "HINT  (H)", w / 2 - bw * 1.5 - gap, y, bw, bh, false)
        button("btn_restart", "RESTART  (R)", w / 2 - bw / 2, y, bw, bh, false)
        button("btn_settings", "SETTINGS  (Esc)", w / 2 + bw / 2 + gap, y, bw, bh, false)
    end
    text("help", "Tap an arrow to slide it out. Blocked arrows bump and cost a heart.", 0, 72 * k, w, 30 * k, 1.0, DIM)
end

local CARD = { "card_dim", "card_panel", "card_title", "card_sub", "btn_card", "btn_card2" }
local function draw_card()
    if S.mode == "play" then
        for _, id in ipairs(CARD) do hide(id) end
        return
    end
    local k, w, h = L.k, L.w, L.h
    local a = min(1, S.card_t * 4)
    local menu = SET:is_open()
    rect("card_dim", 0, 0, w, h, { 0, 0, 0, 0.55 * a }, 80)
    local pw, ph = 620 * k, 330 * k
    local px, py = (w - pw) / 2, (h - ph) / 2
    rect("card_panel", px, py, pw, ph, { 0.09, 0.11, 0.18, 0.97 * a }, 81, 22 * k)
    local won = S.mode == "won"
    text("card_title", won and ("LEVEL " .. game.level .. " CLEAR") or "OUT OF HEARTS", px, py + 30 * k, pw, 80 * k, 2.6,
        won and { GOOD[1], GOOD[2], GOOD[3], a } or { BAD[1], BAD[2], BAD[3], a }, 82)
    local sub
    if won then
        sub = game.mistakes == 0 and "Flawless!  " .. game.moves .. " taps" or (game.mistakes .. (game.mistakes == 1 and " bump" or " bumps") .. "  ·  " .. game.moves .. " taps")
    else
        sub = game.left .. " arrows were still on the board"
    end
    text("card_sub", sub, px, py + 120 * k, pw, 50 * k, 1.3, { 0.85, 0.9, 1, a }, 82)
    if not menu then
        button("btn_card", won and "NEXT LEVEL  (Enter)" or "TRY AGAIN  (Enter)", px + 60 * k, py + ph - 110 * k, pw - 120 * k, 70 * k, true, 83)
    end
    hide("btn_card2")
end

------------------------------------------------------------------ flow
local function clear_arrow_widgets(list)
    for id, a in ipairs(list or {}) do
        for j = 1, #a.cells + 2 do hide("a" .. id .. "_" .. j) end
        hide("h" .. id)
    end
end

local function start_level(n)
    local old = game and game.arrows
    clear_arrow_widgets(old)
    S.level = max(1, n)
    game = R.new_game(S.level)
    anims, flashes, dirty = {}, {}, {}
    hover_id, hint_id, hint_t = 0, 0, 0
    S.mode, S.card_t, S.shake = "play", 0, 0
    L.w = nil
    if S.level > S.best then
        S.best = S.level
        pcall(fs.write, "Save/arrowout_level.txt", tostring(S.best))
    end
end

local function relayout_all()
    draw_static()
    for id in ipairs(game.arrows) do dirty[id] = true end
end

local function tap(id)
    if S.mode ~= "play" or id == 0 then return end
    local r = game:tap_arrow(id)
    if not r then return end
    if hint_id == id then hint_id = 0 end
    if r.ok then
        local n = #game.arrows[id].cells
        local dist = r.steps + n + 1
        anims[id] = { kind = "slide", t = 0, dur = min(0.75, 0.3 + 0.025 * dist), dist = dist }
        sound("slide")
    else
        anims[id] = { kind = "bump", t = 0, dur = 0.38, steps = r.steps }
        flashes[r.blocker] = 0.45
        dirty[r.blocker] = true
        if not r.free then S.shake = 0.25 * SET:shake_scale() end -- a repeat into the same blocker costs nothing
        sound("bump")
    end
end

local function edge_keys()
    S.keys = S.keys or {}
    local function pressed(name)
        local down = input.is_key_down_raw(name)
        local was = S.keys[name]
        S.keys[name] = down
        return down and not was
    end
    return pressed
end
local pressed = edge_keys()
_G.arrowout.tap = function(id) tap(id) end
_G.arrowout.start = function(n) start_level(n) end

local function update_hover()
    local st = runtime_ui.get_state(SCREEN, "board")
    local id = 0
    if st and st.hovered and S.mode == "play" then
        local cx = floor((st.mouse_x - L.bx) / L.cs) + 1
        local cy = floor((st.mouse_y - L.by) / L.cs) + 1
        id = game:at(cx, cy)
    end
    if id ~= hover_id then
        if hover_id ~= 0 then dirty[hover_id] = true end
        if id ~= 0 then dirty[id] = true end
        hover_id = id
    end
    if st and st.clicked and id ~= 0 then tap(id) end
end

local function controls()
    if pressed("M") then SET:toggle_mute() end
    local enter = pressed("Return") or pressed("Space")
    if pressed("R") or clicked("btn_restart") then sound("click"); start_level(S.level); return end
    if S.mode == "play" then
        if (pressed("H") or clicked("btn_hint")) and game:hint() then
            if hint_id ~= 0 then dirty[hint_id] = true end
            hint_id, hint_t = game:hint(), 2.5
            S.hints = S.hints + 1
            sound("click")
        end
        if pressed("PageUp") then start_level(S.level + 1); return end
        if pressed("PageDown") then start_level(S.level - 1); return end
        update_hover()
    elseif S.card_t > 0.3 and (enter or clicked("btn_card")) then
        sound("click")
        start_level(S.mode == "won" and S.level + 1 or S.level)
    end
end

local function step(dt)
    S.t = S.t + dt
    for id, an in pairs(anims) do
        an.t = an.t + dt
        dirty[id] = true
        if an.t >= an.dur then anims[id] = nil end
    end
    for id, f in pairs(flashes) do
        f = f - dt
        dirty[id] = true
        flashes[id] = f > 0 and f or nil
    end
    if hint_id ~= 0 then
        hint_t = hint_t - dt
        dirty[hint_id] = true
        if hint_t <= 0 or not game.arrows[hint_id].alive then hint_id = 0 end
    end
    if S.mode == "play" and next(anims) == nil then
        if game:won() then S.mode = "won"; sound("win")
        elseif game:lost() then S.mode = "lost"; sound("lose") end
    end
    if S.mode ~= "play" then S.card_t = S.card_t + dt end
    -- Board shake on a bump: offset the board origin and redraw everything while it settles.
    if S.shake > 0 then
        S.shake = max(0, S.shake - dt)
        local amp = S.shake * 26 * L.k
        L.bx = L.bx0 + floor(sin(S.t * 90) * amp)
        L.by = L.by0
        for id in ipairs(game.arrows) do dirty[id] = true end
    elseif L.bx ~= L.bx0 then
        L.bx = L.bx0
        for id in ipairs(game.arrows) do dirty[id] = true end
    end
end

local function present()
    if layout() then relayout_all() end
    for id in pairs(dirty) do draw_arrow(id) end
    dirty = {}
    draw_hud()
    draw_card()
end

------------------------------------------------------------------ boot
runtime_ui.clear(SCREEN)
runtime_ui.set_screen_overlay(SCREEN, true)
runtime_ui.show(SCREEN)
pcall(runtime_ui.preload_images, HEAD_IMG)
start_level(S.level)
SET:apply()
present()

script.on_update("arrowout", function()
    local dt = max(0, min(0.1, engine.get_metrics().delta_ms / 1000))
    -- Poll Escape every frame so the press that closes the menu does not reopen it.
    local esc = pressed("Escape")
    if SET:update(dt) then
        -- Keep the game's key edges current so keys used in the menu do not fire when it closes.
        for _, key in ipairs({ "M", "R", "H", "Return", "Space", "PageUp", "PageDown" }) do pressed(key) end
    elseif esc or clicked("btn_settings") then
        sound("click")
        SET:open()
    else
        controls()
    end
    step(dt)
    present()
end, "play")

print("[ArrowOut] Ready. Click arrows to slide them out; H hint, R restart, Esc settings, M mute, PgUp/PgDn change level.")
