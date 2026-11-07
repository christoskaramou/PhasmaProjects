-- Ricochet Parlour (PhasmaEngine, Lua): balls ricochet on an upright bagatelle board; click a falling ball
-- to kick it back up. A click nearer its underside kicks harder. Keep every ball out of the slot.
-- rp_rules.lua: rules and physics. rp_world.lua: the 3D board. This file: flow, input, sounds and HUD.
local function module(path)
    local source = assert(fs.read(path), "Missing Ricochet Parlour module: " .. path)
    return assert(load(source, "@" .. path, "t", _ENV))()
end
local R = module("Scripts/rp_rules.lua")
local World = module("Scripts/rp_world.lua")(R)
local SettingsMenu = module("Scripts/Lib/settings_menu.lua") -- shared menu, same copy as the other games

local SCREEN = "rp"
local floor, min, max, abs, sin = math.floor, math.min, math.max, math.abs, math.sin
local CLEAR = { 0, 0, 0, 0 }
local IVORY = { 0.94, 0.89, 0.8, 1 }
local BRASS = { 0.82, 0.66, 0.42, 1 }

local best = tonumber(fs.read("Save/rp_best.txt") or "0") or 0
local S = { mode = "title", t = 0, card_t = 0, pops = {}, seed = 1 }
local game
local L = {}
_G.rp = { S = S, R = R, W = World, game = function() return game end, autoplay = false }

-- The engine aborts the process when about 32 sounds overlap (it doesn't drop extras), and a busy board
-- reaches that. ponytail: cap voices here; real fix is voice stealing in the engine's audio mixer.
local LEN = { bumper = 0.68, clack = 0.38, click = 0.07, cup = 1.4, drop = 1.02, glass = 0.98, kick = 0.56,
    kick_close = 0.58, over = 2.78, pin = 0.44, spawn = 0.65, whiff = 0.7 }   -- seconds (tools/make_sounds.py)
local MAX_VOICES, voices, clock = 16, {}, 0
local function sound(name)
    if not (audio and audio.play) then return end
    for i = #voices, 1, -1 do if voices[i] <= clock then table.remove(voices, i) end end
    if #voices >= MAX_VOICES then return end
    voices[#voices + 1] = clock + (LEN[name] or 3)
    pcall(audio.play, name .. ".wav")
end
local SET = SettingsMenu.new({ title = "SETTINGS", subtitle = "RICOCHET PARLOUR", click = function() sound("click") end,
    theme = { accent = { 0.82, 0.66, 0.42, 1 }, accent2 = { 0.9, 0.78, 0.55, 1 }, text = { 0.94, 0.89, 0.8, 1 }, selected_text = { 1, 0.96, 0.88, 1 } },
    on_graphics = function() pcall(settings.set, "taa", true); pcall(settings.set, "fxaa", false) end })
_G.rp.settings = SET

------------------------------------------------------------------ widgets
local widgets = {}
local function quad(id, o)
    o.fill = o.fill or CLEAR; o.border = o.border or CLEAR; o.accent = CLEAR
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
        text_color = color or IVORY, align_h = align or "center", align_v = "middle" })
end
local function catcher(id, x, y, w, h, z) quad(id, { style = "text", label = "", x = x, y = y, width = w, height = h, z = z or 60, no_input = false }) end
local function state(id) return runtime_ui.get_state(SCREEN, id) end
local function clicked(id) local s = state(id); return s and s.clicked == true end
local pools = {}
local function pid(prefix)
    local p = pools[prefix]
    if not p then p = { n = 0, m = 0 }; pools[prefix] = p end
    p.n = p.n + 1
    return prefix .. p.n
end
local function flush_pools()
    for prefix, p in pairs(pools) do
        for i = p.n + 1, p.m do hide(prefix .. i) end
        p.m, p.n = max(p.m, p.n), 0
    end
end
local function layout()
    local surf = runtime_ui.get_surface_size()
    local w, h = surf.width or 1280, surf.height or 800
    if w <= 0 or h <= 0 or (L.w == w and L.h == h) then return false end
    L.w, L.h, L.k = w, h, min(w / 1600, h / 1000)
    return true
end

------------------------------------------------------------------ flow
local function start()
    S.seed = S.seed + 1
    game = R.new(S.seed)
    S.mode, S.pops = "play", {}
end
_G.rp.start = function() start() end

local function handle(ev)
    if ev.kind == "kick" then
        World.kick(ev.ball.x, ev.ball.y, ev.quality)
        sound(ev.close and "kick_close" or "kick")
        -- Stack above any pop still showing nearby so two quick kicks never overlap.
        local dy = 0
        for _, q in ipairs(S.pops) do
            if math.abs(q.x - ev.ball.x) < 1.9 and math.abs((q.y + (q.dy or 0)) - (ev.ball.y + dy)) < 0.75 then dy = (q.y + (q.dy or 0)) - ev.ball.y + 0.8 end
        end
        S.pops[#S.pops + 1] = { x = ev.ball.x, y = ev.ball.y, dy = dy, close = ev.close, points = ev.points, t = 0, id = ev.ball.id }
        S.streak_bump = 1
    elseif ev.kind == "cup" then
        for i, c in ipairs(R.CUPS) do if c == ev.cup then World.cup(i, c.x, c.y) end end
        sound("cup")
        S.pops[#S.pops + 1] = { x = ev.ball.x, y = ev.ball.y, dy = 0.5, cup = ev.cup.points, points = ev.points, t = 0, id = ev.ball.id }
    elseif ev.kind == "whiff" then
        World.whiff(ev.x, ev.y); sound("whiff")
    elseif ev.kind == "pin" then
        if ev.pin.rubber then World.pin_hit(ev.pin, ev.speed); sound("bumper") elseif ev.speed > 1.2 then sound("pin") end
    elseif ev.kind == "clack" then
        sound("clack")
    elseif ev.kind == "shatter" then
        World.shatter(ev.ball.x, ev.ball.y); sound("glass")
    elseif ev.kind == "lost" then
        if ev.why == "drop" then World.drop(ev.ball.x); sound("drop") end
        S.token_flash = 1
    elseif ev.kind == "spawn" then
        sound("spawn")
    elseif ev.kind == "over" then
        S.mode, S.card_t = "over", 0
        sound("over")
        if game.score > best then best = floor(game.score); pcall(fs.write, "Save/rp_best.txt", tostring(best)) end
    end
end

_G.rp.handle = handle      -- console / test hook

local function edge()
    local keys = {}
    return function(name)
        local down = input.is_key_down_raw(name)
        local was = keys[name]
        keys[name] = down
        return down and not was
    end
end
local pressed = edge()

local function controls()
    if pressed("M") then SET:toggle_mute() end
    local enter = pressed("Return") or pressed("Space")
    if S.mode ~= "play" then
        if S.card_t > 0.4 and (enter or clicked("btn_card")) then sound("click"); start() end
        return
    end
    -- Kick: a click anywhere on the board kicks the ball under the cursor.
    local st = state("board")
    if st and st.clicked and st.mouse_x then
        local x, y = World.board_point(st.mouse_x, st.mouse_y)
        if x then game:kick(x, y) end
    end
    S.mouse = st and st.hovered and st.mouse_x and st.mouse_y and { st.mouse_x, st.mouse_y } or _G.rp.fake_mouse   -- console hook for captures
    -- Test hook (off unless set from the console): kick the lowest falling ball, for captures.
    if _G.rp.autoplay then
        local low
        for _, b in ipairs(game.balls) do
            if b.vy < 0 and b.y < 2.0 and b.cooldown <= 0 and (b.kind ~= "glass" or b.touched) and (not low or b.y < low.y) then low = b end
        end
        if low then game:kick(low.x, low.y - R.BALL_R) end
    end
end

local function step(dt)
    S.t = S.t + dt
    S.card_t = S.card_t + dt
    if S.mode == "play" then game:update(dt) end
    if game then for _, ev in ipairs(game:take_events()) do handle(ev) end end
    for i = #S.pops, 1, -1 do S.pops[i].t = S.pops[i].t + dt; if S.pops[i].t > 0.8 then table.remove(S.pops, i) end end
    S.token_flash = max(0, (S.token_flash or 0) - dt * 1.6)
    S.streak_bump = max(0, (S.streak_bump or 0) - dt * 5)
end

------------------------------------------------------------------ HUD
-- Laid out in the concept render's 1920x1080 pixel coordinates, scaled to the window (u). The text font
-- is Literata (Assets/Fonts/RuntimeUi.ttf, SIL OFL), the runtime UI's project font.
local BRASS_T = { 0.784, 0.647, 0.412, 1 }      -- (200,165,105) label brass
local IVORY_T = { 0.941, 0.894, 0.804, 1 }      -- (240,228,205)
local SCORE_T = { 0.961, 0.922, 0.843, 1 }      -- (245,235,215)
local NOTE_T = { 0.882, 0.824, 0.725, 1 }       -- (225,210,185)
local SUB_T = { 0.784, 0.706, 0.569, 1 }        -- (200,180,145)
local RIM = { 0.745, 0.588, 0.353, 0.67 }       -- (190,150,90,170)
local FILL = { 0.086, 0.067, 0.047, 0.8 }       -- (22,17,12,200)
local BAD = { 0.86, 0.38, 0.3, 1 }
local TAG = { iron = "IRON  ·  2 kicks", gold = "GOLD  ·  x3 points", glass = "GLASS  ·  let it bounce" }
local function col4(c, a) return { c[1], c[2], c[3], (c[4] or 1) * (a or 1) } end
local function ease_back(t) t = max(0, min(1, t)); local c = 1.7; return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2 end
local function image(id, path, x, y, w, h, tint, z)
    quad(id, { style = "image", path = path, x = x, y = y, width = w, height = h, z = z, image_tint = tint or { 1, 1, 1, 1 } })
end
local function commas(n)
    local s = tostring(floor(n))
    while true do
        local t = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if t == s then return s end
        s = t
    end
end
local u = 1
-- Literata renders smaller than the concept's Georgia at the same nominal size: match the cap heights.
local FONT_K = 1.42
-- A concept panel: dark fill with a brass outline (two 1.5 px borders for the heavier rim).
local function panel(x, y, w, h, z, rim, fill, r)
    r = (r or 10) * u
    quad(pid("pn"), { style = "text", label = "", x = x, y = y, width = w, height = h, z = z, fill = fill or FILL, border = rim or RIM, corner_radius = r })
    quad(pid("pn"), { style = "text", label = "", x = x + 1, y = y + 1, width = w - 2, height = h - 2, z = z, fill = CLEAR, border = col4(rim or RIM, 0.7), corner_radius = r - 1 })
end
-- Text at a concept position: px is the concept font size; the box is vertically centred on (y + px*0.62).
local function ctext(s, x, y, px, color, align, z, w)
    local h = px * 1.5 * u * FONT_K
    local cy = y + px * 0.62 * u
    local bw = w or 900 * u
    local bx = align == "center" and x - bw / 2 or (align == "right" and x - bw or x)
    text(pid("tx"), s, bx, cy - h / 2, bw, h, px / 16 * u * FONT_K / L.k, color, z or 41, align or "left")
end

local function draw_hud()
    local w, h = L.w, L.h
    u = min(w / 1920, h / 1080)
    -- The concept's grade: a soft dark vignette over the scene, under the HUD.
    image(pid("vg"), "Textures/vignette.png", 0, 0, w, h, { 0, 0, 0, 0.82 }, 5)
    -- Title.
    panel(24 * u, 16 * u, 470 * u, 84 * u, 39)
    ctext("RICOCHET PARLOUR", 42 * u, 22 * u, 34, IVORY_T)
    ctext("CLICK A FALLING BALL TO KICK IT BACK UP", 44 * u, 68 * u, 14, SUB_T)
    if not game then return end
    local cx = w / 2
    -- Score.
    panel(cx - 130 * u, 8 * u, 260 * u, 78 * u, 39)
    ctext("SCORE", cx, 10 * u, 14, BRASS_T, "center")
    ctext(commas(game.score), cx, 30 * u, 46, SCORE_T, "center")
    -- Streak pill.
    if game.streak >= 2 then
        local bump = S.streak_bump or 0
        panel(cx - 120 * u, 92 * u, 240 * u, 40 * u, 39, { 0.784, 0.627, 0.373, 0.67 }, { 0.118, 0.086, 0.047, 0.82 }, 20)
        ctext("STREAK  x" .. game.streak, cx, 101 * u, 17 + 3 * bump, { 0.941, 0.843, 0.627, 1 }, "center")
    end
    -- In play and tokens (they move left to make room for the FPS counter).
    local fx = SET:get("show_fps") and 170 * u or 0
    local ip = w - fx - 530 * u
    panel(ip, 18 * u, 260 * u, 70 * u, 39)
    ctext("IN PLAY", ip + 20 * u, 24 * u, 14, BRASS_T)
    ctext(#game.balls .. (#game.balls == 1 and " ball" or " balls"), ip + 20 * u, 44 * u, 26, IVORY_T)
    local tk = w - fx - 254 * u
    panel(tk, 18 * u, 220 * u, 70 * u, 39)
    ctext("TOKENS", tk + 20 * u, 24 * u, 14, BRASS_T)
    for i = 1, R.TOKENS do
        local on = i <= game.tokens
        local r = 15 * u
        local x0, y0 = tk + 38 * u + (i - 1) * 46 * u, 62 * u
        local fill = on and { 0.843, 0.686, 0.392, 0.94 } or { 0.235, 0.196, 0.157, 0.8 }
        if (S.token_flash or 0) > 0 and i == game.tokens + 1 then fill = col4(BAD, 0.6 + 0.4 * S.token_flash) end
        quad(pid("tk"), { style = "text", label = "", x = x0 - r, y = y0 - r, width = 2 * r, height = 2 * r, z = 40, fill = fill,
            border = on and { 0.941, 0.824, 0.588, 1 } or { 0.353, 0.294, 0.235, 1 }, corner_radius = r })
    end
    -- Points pops beside the kicked ball ("CLOSE KICK +150" or "+points"), laid out first in screen space:
    -- each moves up past any pop already placed, so none overlap.
    local function hit(r1, r2) return r1.x < r2.x + r2.w and r2.x < r1.x + r1.w and r1.y < r2.y + r2.h and r2.y < r1.y + r1.h end
    local rects = {}
    for _, p in ipairs(S.pops) do
        local sx, sy = World.project(p.x, p.y + (p.dy or 0), World.BALL_Z)
        if sx then
            local big = p.close or p.cup
            local r = { p = p, x = sx + (big and 50 or 40) * u, y = sy - (big and 66 or 42) * u - p.t * 30 * u, w = (big and 190 or 110) * u, h = (big and 64 or 36) * u }
            local moved = true
            while moved do
                moved = false
                for _, o in ipairs(rects) do
                    if hit(r, o) then r.y = o.y - r.h - 6 * u; moved = true end
                end
            end
            rects[#rects + 1] = r
        end
    end
    -- Tags beside the special balls; a tag that would touch a pop (or is its ball's own pop) is skipped.
    local popped = {}
    for _, p in ipairs(S.pops) do popped[p.id or 0] = true end
    for _, b in ipairs(game.balls) do
        local tag = TAG[b.kind]
        if tag and not popped[b.id] then
            local sx, sy = World.project(b.x, b.y, World.BALL_Z)
            if sx then
                local tw = (#tag * 7.6 + 30) * u
                local tr = { x = sx + 26 * u, y = sy - 16 * u, w = tw, h = 32 * u }
                local clear = true
                for _, o in ipairs(rects) do if hit(tr, o) then clear = false end end
                if clear then
                    panel(tr.x, tr.y, tw, tr.h, 34, { 0.627, 0.51, 0.333, 0.67 }, { 0.086, 0.067, 0.047, 0.78 }, 8)
                    ctext(tag, tr.x + tw / 2, sy - 11 * u, 14, NOTE_T, "center", 35, tw)
                end
            end
        end
    end
    for _, r in ipairs(rects) do
        local p = r.p
        local a = 1 - max(0, p.t - 0.5) / 0.3
        local s = ease_back(p.t * 5)
        if p.close or p.cup then
            panel(r.x, r.y, r.w, r.h, 44, col4({ 0.784, 0.627, 0.373, 0.67 }, a), col4({ 0.094, 0.071, 0.047, 0.84 }, a))
            ctext(p.cup and ("CUP  " .. p.cup) or "CLOSE KICK", r.x + r.w / 2, r.y + 8 * u, 18 * s, col4({ 0.961, 0.882, 0.667 }, a), "center", 45, r.w)
            ctext("+" .. commas(p.points), r.x + r.w / 2, r.y + 34 * u, 18, col4(NOTE_T, a), "center", 45, r.w)
        else
            panel(r.x, r.y, r.w, r.h, 44, col4({ 0.784, 0.627, 0.373, 0.6 }, a), col4({ 0.094, 0.071, 0.047, 0.8 }, a))
            ctext("+" .. commas(p.points), r.x + r.w / 2, r.y + 7 * u, 17 * s, col4(NOTE_T, a), "center", 45, r.w)
        end
    end    -- Kick cursor: a ring with two side ticks; it tightens and warms over a ball you can kick.
    if S.mouse and S.mode == "play" and not SET:is_open() then
        local mx, my = S.mouse[1], S.mouse[2]
        local bx, by = World.board_point(mx, my)
        local over = false
        if bx then
            for _, b in ipairs(game.balls) do
                if (bx - b.x) ^ 2 + (by - b.y) ^ 2 <= (R.BALL_R + R.KICK_REACH) ^ 2 then over = true end
            end
        end
        local r = (over and 30 or 34) * u
        local c = over and { 1, 0.9, 0.66, 0.95 } or { 0.96, 0.92, 0.82, 0.9 }
        image(pid("cu"), "Textures/ring.png", mx - r, my - r, 2 * r, 2 * r, c, 70)
        for _, sgn in ipairs({ -1, 1 }) do
            quad(pid("cu"), { style = "text", label = "", x = mx + sgn * (r + 8 * u) - 4 * u, y = my - 1.5 * u, width = 8 * u, height = 3 * u, z = 70, fill = c })
        end
    end
    -- Bottom note: the rule people forget, and when the next ball arrives.
    local nxt = #game.balls < R.MAX_BALLS and max(0, R.spawn_every(game.t) - game.spawn_t) or nil
    panel(36 * u, h - 74 * u, 520 * u, 44 * u, 39, nil, { 0.086, 0.067, 0.047, 0.75 }, 12)
    ctext("Glass balls crack if kicked twice in a row  ·  " .. (nxt and string.format("next ball in %d s", math.ceil(nxt)) or "the board is full"),
        56 * u, h - 61 * u, 15, NOTE_T, "left", 41, 500 * u)
    if (S.token_flash or 0) > 0 then rect(pid("fl"), 0, 0, w, h, { 0.45, 0.1, 0.05, 0.16 * S.token_flash }, 30) end
end

local function draw_card()
    if S.mode == "play" or SET:is_open() then hide("btn_card"); return end
    local w, h = L.w, L.h
    u = min(w / 1920, h / 1080)
    local a = min(1, S.card_t * 3)
    rect(pid("cd"), 0, 0, w, h, { 0.02, 0.015, 0.01, 0.55 * a }, 80)
    local cw, ch = 860 * u, 470 * u
    local x, y = (w - cw) / 2, (h - ch) / 2 + (1 - ease_back(S.card_t * 2.5)) * 30 * u
    panel(x, y, cw, ch, 81, col4(RIM, a), col4({ 0.075, 0.058, 0.04, 0.96 }, a), 14)
    local cx = x + cw / 2
    if S.mode == "title" then
        ctext("RICOCHET PARLOUR", cx, y + 40 * u, 44, col4(IVORY_T, a), "center", 82)
        ctext("Click a falling ball to kick it back up. Keep them all out of the slot.", cx, y + 128 * u, 18, col4(IVORY_T, a), "center", 82)
        ctext("Click near a ball's underside for a stronger CLOSE KICK and more points.", cx, y + 166 * u, 17, col4(BRASS_T, a), "center", 82)
        ctext("Iron needs two kicks.  Gold falls fast, pays triple.  Glass: let it bounce before kicking again.", cx, y + 214 * u, 15, col4(NOTE_T, a), "center", 82)
        ctext("Roll a ball through a brass cup for 50 or 100.  A ball through the slot costs a token.", cx, y + 246 * u, 15, col4(NOTE_T, a), "center", 82)
        ctext(best > 0 and ("Best score  " .. commas(best)) or "", cx, y + 292 * u, 16, col4(BRASS_T, a), "center", 82)
    else
        ctext("OUT OF TOKENS", cx, y + 40 * u, 44, col4(IVORY_T, a), "center", 82)
        ctext("Score  " .. commas(game.score) .. "     ·     " .. string.format("%d:%02d", floor(game.t / 60), floor(game.t % 60)) .. " on the board",
            cx, y + 136 * u, 20, col4(IVORY_T, a), "center", 82)
        ctext("kicks " .. game.kicks .. "   ·   best streak " .. game.best_streak .. "   ·   balls lost " .. game.lost, cx, y + 184 * u, 16, col4(NOTE_T, a), "center", 82)
        ctext(floor(game.score) >= best and game.score > 0 and "A new best score." or ("Best score  " .. commas(best)), cx, y + 228 * u, 18, col4(BRASS_T, a), "center", 82)
    end
    local bw, bh = 320 * u, 64 * u
    local bx, by = cx - bw / 2, y + ch - 100 * u
    panel(bx, by, bw, bh, 83, col4({ 0.82, 0.66, 0.42, 1 }, a), col4({ 0.16, 0.12, 0.07, 1 }, a), 10)
    ctext((S.mode == "title" and "BEGIN" or "PLAY AGAIN") .. "  ·  Enter", cx, by + 18 * u, 20, col4(IVORY_T, a), "center", 84, bw)
    catcher("btn_card", bx, by, bw, bh, 85)
end

local function present(dt)
    if layout() then for id in pairs(widgets) do widgets[id] = true; hide(id) end end
    World.update(dt, game)
    if S.mode == "play" and not SET:is_open() then catcher("board", 0, 0, L.w, L.h, 1) else hide("board") end
    draw_hud()
    draw_card()
    flush_pools()
end

------------------------------------------------------------------ boot
runtime_ui.clear(SCREEN)
runtime_ui.set_screen_overlay(SCREEN, true)
runtime_ui.show(SCREEN)
World.init()
layout()
SET:apply()
pcall(settings.set, "shadows", true)
present(0)

-- Measured frame times wobble by ~2 ms around a steady vsync interval; stepping the balls by them makes the
-- motion judder. A light low-pass keeps the long-run average (no drift) but steps every frame evenly.
local smooth_dt
script.on_update("rp", function()
    local raw = max(0, min(0.05, engine.get_metrics().delta_ms / 1000))
    smooth_dt = smooth_dt and smooth_dt + (raw - smooth_dt) * 0.1 or raw
    local dt = smooth_dt
    clock = clock + dt
    local esc = pressed("Escape")
    if SET:update(dt) then
        for _, key in ipairs({ "M", "Return", "Space" }) do pressed(key) end
    elseif esc then
        sound("click"); SET:open()
    else
        controls()
        step(dt)
    end
    present(dt)
end, "play")

print("[RicochetParlour] Ready. Click a falling ball to kick it; Enter starts; Esc settings; M mute.")
