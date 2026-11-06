-- Resonance Break (PhasmaEngine, Lua) - playable prototype.
-- Glass panes slide down four lanes; strike the matching tuning fork (A S D F) as each reaches the brass
-- rail. Chords need two forks at once; shifting panes change colour on the way, strike the colour they
-- show on arrival. Misses crack the shield; the tempo climbs every wave.
-- rb_rules.lua: rules. rb_world.lua: the 3D hall. This file: flow, input, sounds and the HUD.
local function module(path)
    local source = assert(fs.read(path), "Missing Resonance Break module: " .. path)
    return assert(load(source, "@" .. path, "t", _ENV))()
end
local R = module("Scripts/rb_rules.lua")
local World = module("Scripts/rb_world.lua")(R)
local SettingsMenu = module("Scripts/Lib/settings_menu.lua") -- shared menu, same copy as the other games

local SCREEN = "rb"
local floor, min, max, abs, sin = math.floor, math.min, math.max, math.abs, math.sin
local CLEAR = { 0, 0, 0, 0 }
local IVORY = { 0.94, 0.89, 0.8, 1 }
local BRASS = { 0.82, 0.66, 0.42, 1 }
local DIMC = { 0.72, 0.64, 0.52, 1 }
local PANEL = { 0.085, 0.066, 0.047, 0.82 }
local RIM = { 0.75, 0.6, 0.36, 0.65 }
local BAD = { 0.85, 0.35, 0.3, 1 }
local KEYS = { "A", "S", "D", "F" }
local JUDGE_C = { perfect = { 0.98, 0.9, 0.66, 1 }, great = { 0.86, 0.9, 0.78, 1 }, good = { 0.78, 0.74, 0.66, 1 } }

local best = tonumber(fs.read("Save/rb_best.txt") or "0") or 0
local S = { mode = "title", t = 0, card_t = 0, pops = {}, banner = nil, banner_t = 0, flash = 0, seed = 1 }
local game
local L = {}
_G.rb = { S = S, R = R, W = World, game = function() return game end, autoplay = false }

local function sound(name) if audio and audio.play then pcall(audio.play, name .. ".wav") end end
local SET = SettingsMenu.new({ title = "SETTINGS", subtitle = "RESONANCE BREAK", click = function() sound("click") end,
    theme = { accent = { 0.82, 0.66, 0.42, 1 }, accent2 = { 0.9, 0.78, 0.55, 1 }, text = { 0.94, 0.89, 0.8, 1 }, selected_text = { 1, 0.96, 0.88, 1 } } })
_G.rb.settings = SET

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
local function clicked(id) local s = runtime_ui.get_state(SCREEN, id); return s and s.clicked == true end
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
local function col4(c, a) return { c[1], c[2], c[3], a or 1 } end
local function panel(x, y, w, h, z, rim)
    local k = L.k
    rect(pid("pr"), x - 1.5 * k, y - 1.5 * k, w + 3 * k, h + 3 * k, rim or RIM, z, 9 * k)
    rect(pid("pb"), x, y, w, h, PANEL, z, 8 * k)
end
local function ease_back(t) t = max(0, min(1, t)); local c = 1.7; return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2 end
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
    S.mode, S.pops, S.flash, S.over_saved = "play", {}, 0, false
end

_G.rb.start = function() start() end

local function pop(lane, s, c)
    S.pops[#S.pops + 1] = { lane = lane, s = s, c = c, t = 0 }
end

local function handle(ev)
    if ev.kind == "break" then
        local p = ev.pane
        World.shatter(p.lane, R.key_at(p, p.t))
        sound("fork" .. ev.key)
        sound(ev.judge == "perfect" and "shatter1" or (ev.judge == "great" and "shatter2" or "shatter3"))
        pop(p.lane, ev.judge:upper(), JUDGE_C[ev.judge])
    elseif ev.kind == "empty" then
        World.ring(ev.key)
        sound("dull")
    elseif ev.kind == "crack" then
        sound("crack")
        World.shake(0.8)
        S.flash = 1
        pop(ev.pane.lane, "CRACK", BAD)
    elseif ev.kind == "wave" then
        if ev.wave > 1 then S.banner, S.banner_t = "WAVE " .. ev.wave, 2.2; S.banner_sub = ev.bpm .. " BPM"; sound("wave") end
    elseif ev.kind == "repair" then
        sound("repair")
    elseif ev.kind == "over" then
        S.mode, S.card_t = "over", 0
        sound("over")
        if game.score > best then best = game.score; pcall(fs.write, "Save/rb_best.txt", tostring(best)) end
    end
end

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
local ALL_KEYS = { "A", "S", "D", "F", "Return", "Space", "M" }

local function controls()
    if pressed("M") then SET:toggle_mute() end
    local enter = pressed("Return") or pressed("Space")
    if S.mode == "title" or S.mode == "over" then
        for _, k in ipairs(KEYS) do pressed(k) end
        if S.card_t > 0.4 and (enter or clicked("btn_card")) then sound("click"); start() end
        return
    end
    -- Forks: read every key this frame so chords register together.
    for i, k in ipairs(KEYS) do
        if pressed(k) then game:strike(i) end
    end
    -- Test hook (off unless set from the console): strike every pane on time, for captures.
    if _G.rb.autoplay then
        for _, p in ipairs(game.panes) do
            if not p.done and game.t >= p.t - 0.01 then game:strike(R.key_at(p, p.t)) end
        end
    end
end

local function step(dt)
    S.t = S.t + dt
    S.card_t = S.card_t + dt
    S.flash = max(0, S.flash - dt * 2.5)
    S.banner_t = max(0, S.banner_t - dt)
    if S.mode == "play" then game:update(dt) end
    if game then for _, ev in ipairs(game:take_events()) do handle(ev) end end
    for i = #S.pops, 1, -1 do S.pops[i].t = S.pops[i].t + dt; if S.pops[i].t > 0.7 then table.remove(S.pops, i) end end
end

------------------------------------------------------------------ HUD
local function draw_hud()
    local k, w, h = L.k, L.w, L.h
    local playing = S.mode == "play"
    panel(22 * k, 14 * k, 470 * k, 80 * k, 39)
    text(pid("t"), "RESONANCE BREAK", 34 * k, 18 * k, 520 * k, 52 * k, 2.1, IVORY, 40, "left")
    text(pid("t"), "STRIKE THE FORK THAT MATCHES THE PANE", 36 * k, 64 * k, 520 * k, 22 * k, 0.7, DIMC, 40, "left")
    if not game then return end
    -- Score and combo.
    text(pid("t"), "SCORE", w / 2 - 150 * k, 8 * k, 300 * k, 22 * k, 0.7, BRASS, 40)
    text(pid("t"), tostring(game.score), w / 2 - 250 * k, 26 * k, 500 * k, 60 * k, 2.4, IVORY, 40)
    if game.combo >= 2 then
        panel(w / 2 - 110 * k, 92 * k, 220 * k, 38 * k, 39)
        text(pid("t"), "COMBO  x" .. game.combo .. (game:multiplier() > 1 and ("   ·   " .. game:multiplier() .. "x") or ""), w / 2 - 110 * k, 92 * k, 220 * k, 38 * k, 0.9, { 0.95, 0.85, 0.62, 1 }, 41)
    end
    -- Tempo and shield.
    local px = w - 34 * k - 220 * k
    panel(px, 18 * k, 220 * k, 68 * k, 39)
    text(pid("t"), "SHIELD", px + 16 * k, 22 * k, 180 * k, 24 * k, 0.7, BRASS, 41, "left")
    for i = 1, R.SHIELD do
        local on = i <= game.shield
        local c = on and { 0.86, 0.73, 0.48, 1 } or { 0.24, 0.2, 0.16, 1 }
        if on and S.flash > 0 and i == game.shield then c = { 0.95, 0.5, 0.4, 1 } end
        rect(pid("sh"), px + 16 * k + (i - 1) * 40 * k, 52 * k, 32 * k, 18 * k, c, 41, 4 * k)
    end
    local tx = px - 12 * k - 200 * k
    panel(tx, 18 * k, 200 * k, 68 * k, 39)
    text(pid("t"), "TEMPO  ·  WAVE " .. game.wave, tx + 16 * k, 22 * k, 180 * k, 24 * k, 0.7, BRASS, 41, "left")
    text(pid("t"), R.bpm(game.wave) .. " BPM", tx + 16 * k, 46 * k, 180 * k, 34 * k, 1.35, IVORY, 41, "left")
    -- Key caps under the forks, lit while held / just struck.
    for i, x in ipairs(World.LANE_X) do
        local sx, sy = World.project(x, 0.0, World.FORK_Z + 0.35)
        if sx then
            local held = input.is_key_down_raw(KEYS[i])
            local tint = World.TINT[i]
            local cw = 58 * k
            local y = min(h - cw - 14 * k, sy)
            rect(pid("kc"), sx - cw / 2 - 1.5 * k, y - 1.5 * k, cw + 3 * k, cw + 3 * k, col4(tint, held and 1 or 0.75), 42, 10 * k)
            rect(pid("kc"), sx - cw / 2, y, cw, cw, held and { tint[1] * 0.5, tint[2] * 0.5, tint[3] * 0.5, 0.95 } or { 0.08, 0.065, 0.05, 0.9 }, 42, 9 * k)
            text(pid("kc"), KEYS[i], sx - cw / 2, y, cw, cw, 1.4, IVORY, 43)
        end
    end
    -- Judgement pops over the strike line.
    for _, p in ipairs(S.pops) do
        local sx, sy = World.project(World.LANE_X[p.lane], 2.5, World.STRIKE_Z)
        if sx then
            local a = 1 - max(0, p.t - 0.45) / 0.25
            local s = 1.35 * ease_back(p.t * 5)
            text(pid("jp"), p.s, sx - 120 * k, sy - 40 * k - p.t * 40 * k, 240 * k, 50 * k, s, col4(p.c, a), 44)
        end
    end
    -- Wave banner.
    if S.banner and S.banner_t > 0 and playing then
        local a = min(1, (2.2 - S.banner_t) * 4, S.banner_t * 2)
        text(pid("bn"), S.banner, 0, h * 0.24, w, 70 * k, 2.6, col4(IVORY, a), 45)
        text(pid("bn"), S.banner_sub or "", 0, h * 0.24 + 64 * k, w, 30 * k, 1.0, col4(BRASS, a), 45)
    end
    if S.flash > 0 then rect(pid("fl"), 0, 0, w, h, { 0.5, 0.1, 0.05, 0.18 * S.flash }, 30) end
end

local function draw_card()
    if S.mode == "play" or SET:is_open() then hide("btn_card"); return end
    local k, w, h = L.k, L.w, L.h
    local a = min(1, S.card_t * 3)
    rect(pid("cd"), 0, 0, w, h, { 0.02, 0.015, 0.01, 0.55 * a }, 80)
    local cw, ch = 860 * k, 480 * k
    local x, y = (w - cw) / 2, (h - ch) / 2
    rect(pid("cd"), x - 2 * k, y - 2 * k, cw + 4 * k, ch + 4 * k, col4(RIM, 0.9 * a), 81, 14 * k)
    rect(pid("cd"), x, y, cw, ch, { 0.075, 0.058, 0.04, 0.96 * a }, 81, 12 * k)
    if S.mode == "title" then
        text(pid("ct"), "RESONANCE BREAK", x, y + 36 * k, cw, 70 * k, 2.8, col4(IVORY, a), 82)
        text(pid("ct"), "Strike the fork that matches each pane as it reaches the brass rail.", x, y + 120 * k, cw, 30 * k, 1.0, col4(IVORY, a), 82)
        text(pid("ct"), "A  S  D  F  are the four forks, left to right.", x, y + 160 * k, cw, 30 * k, 1.0, col4(BRASS, a), 82)
        text(pid("ct"), "Two panes side by side: strike both forks together.", x, y + 210 * k, cw, 28 * k, 0.85, col4(DIMC, a), 82)
        text(pid("ct"), "From wave 5 some panes change colour: strike the colour they show on arrival.", x, y + 242 * k, cw, 28 * k, 0.85, col4(DIMC, a), 82)
        text(pid("ct"), "A missed pane cracks your shield. Each cleared wave mends one crack.", x, y + 274 * k, cw, 28 * k, 0.85, col4(DIMC, a), 82)
        text(pid("ct"), best > 0 and ("Best score  " .. best) or "", x, y + 318 * k, cw, 28 * k, 0.85, col4(BRASS, a), 82)
    else
        text(pid("ct"), "THE SHIELD SHATTERS", x, y + 36 * k, cw, 70 * k, 2.4, col4(IVORY, a), 82)
        text(pid("ct"), "Score  " .. game.score .. "     ·     wave " .. game.wave .. "     ·     best combo " .. game.best_combo, x, y + 130 * k, cw, 34 * k, 1.1, col4(IVORY, a), 82)
        local c = game.counts
        text(pid("ct"), string.format("perfect %d   ·   great %d   ·   good %d   ·   missed %d", c.perfect, c.great, c.good, c.miss), x, y + 180 * k, cw, 30 * k, 0.9, col4(DIMC, a), 82)
        text(pid("ct"), game.score >= best and game.score > 0 and "A new best score." or ("Best score  " .. best), x, y + 226 * k, cw, 30 * k, 1.0, col4(BRASS, a), 82)
    end
    local bw, bh = 320 * k, 64 * k
    local bx, by = x + (cw - bw) / 2, y + ch - 100 * k
    rect(pid("cb"), bx - 1.5 * k, by - 1.5 * k, bw + 3 * k, bh + 3 * k, col4(BRASS, a), 83, 10 * k)
    rect(pid("cb"), bx, by, bw, bh, { 0.16, 0.12, 0.07, a }, 83, 9 * k)
    text(pid("cb"), (S.mode == "title" and "BEGIN" or "PLAY AGAIN") .. "  ·  Enter", bx, by, bw, bh, 1.1, col4(IVORY, a), 84)
    catcher("btn_card", bx, by, bw, bh, 85)
end

local function present(dt)
    if layout() then for id in pairs(widgets) do widgets[id] = true; hide(id) end end
    World.update(dt, S.mode == "play" and game or (S.mode == "over" and game or nil))
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

script.on_update("rb", function()
    local dt = max(0, min(0.05, engine.get_metrics().delta_ms / 1000))
    local esc = pressed("Escape")
    if SET:update(dt) then
        for _, key in ipairs(ALL_KEYS) do pressed(key) end
    elseif esc then
        sound("click"); SET:open()
    else
        controls()
        step(dt)
    end
    present(dt)
end, "play")

print("[ResonanceBreak] Ready. A S D F strike the forks, Enter starts, Esc settings, M mute.")
