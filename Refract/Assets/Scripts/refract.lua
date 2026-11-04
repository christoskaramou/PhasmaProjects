-- Refract (PhasmaEngine, Lua): a light-bending tower defense.
-- You do not build guns. You build light: emitters fire white beams, mirrors bend them, prisms split
-- white into red / green / blue, lenses focus them. Every enemy a beam crosses burns.
-- refract_rules.lua: rules. refract_world.lua: the 3D board (PBR, bloom, SSR, lights, GPU particles).
-- This file: flow, input and the runtime-UI HUD on top.
local function module(path)
    local source = assert(fs.read(path), "Missing Refract module: " .. path)
    return assert(load(source, "@" .. path, "t", _ENV))()
end
local R = module("Scripts/refract_rules.lua")
local World = module("Scripts/refract_world.lua")(R)
local SettingsMenu = module("Scripts/Lib/settings_menu.lua") -- shared menu, same copy as the Arcade games

local SCREEN = "refract"
local floor, min, max, abs, sin, cos = math.floor, math.min, math.max, math.abs, math.sin, math.cos
local CLEAR = { 0, 0, 0, 0 }
local WHITE = { 1, 1, 1, 1 }
local DIM = { 0.62, 0.68, 0.84, 1 }
local GOLD = { 1, 0.82, 0.32, 1 }
local GOOD = { 0.4, 1.0, 0.65, 1 }
local BAD = { 1.0, 0.33, 0.36, 1 }
local CYAN = { 0.45, 0.92, 1, 1 }
local VIOLET = { 0.62, 0.45, 1, 1 }
local PANEL = { 0.03, 0.04, 0.09, 0.86 }
local LIGHT = World.LIGHT

local function T(n) return "Textures/" .. n .. ".png" end
local TEX = {
    emitter = T("emitter_up"), mirror = T("mirror_slash"), prism = T("prism"), lens = T("lens"),
    glow = T("glow"), star = T("star"), flare = T("flare"),
    beam_h = T("beam_glow_h"), beam_v = T("beam_glow_v"), strip = T("strip"), sheen = T("sheen"), vignette = T("vignette"),
    icon_energy = T("icon_energy"), icon_core = T("icon_core"), icon_upgrade = T("icon_upgrade"),
    icon_speed = T("icon_speed"), icon_surge = T("icon_surge"), icon_menu = T("icon_menu"), icon_play = T("icon_play"),
    en_orb = T("en_orb"), en_dart = T("en_dart_right"), en_hulk = T("en_hulk"), en_splitter = T("en_splitter"),
    en_chrome = T("en_chrome"), en_ring = T("en_ring"), en_dark = T("en_dark"), corona = T("en_corona"),
}
local TOOL_ICON = { emitter = TEX.emitter, mirror = TEX.mirror, prism = TEX.prism, lens = TEX.lens, upgrade = TEX.icon_upgrade }
local TOOL_LABEL = { emitter = "EMITTER", mirror = "MIRROR", prism = "PRISM", lens = "LENS", upgrade = "UPGRADE" }
local TOOL_HELP = {
    emitter = "Fires a white beam. Click it again to turn it.",
    mirror = "Bends a beam 90 degrees. Click it to flip.",
    prism = "Splits white light into red, green and blue.",
    lens = "Focuses any beam through it: x1.5 power.",
    upgrade = "Click an emitter to raise its power.",
}
-- What each tool does, shown in the info panel. Numbers come from the rules so they stay true.
local EP, UC = R.EMITTER_POWER, R.UPGRADE_COST
local TOOL_INFO = {
    emitter = { "Fires a white beam straight out of its barrel.",
        "Every enemy the beam crosses burns. Click a placed emitter to turn it 90 degrees.",
        string.format("Power %d / %d / %d damage per second by tier (tool 5 upgrades it).", EP[1], EP[2], EP[3]) },
    mirror = { "Bends any beam that hits it by 90 degrees.",
        "Click a placed mirror to flip its angle ( / or \\ ).",
        "Chain mirrors to run one beam along the lane again and again." },
    prism = { "Splits white light into three beams: red to the left, green ahead, blue to the right.",
        string.format("Each colour keeps %d%% of the power. Coloured light passes through a prism unchanged.", floor(R.PRISM_SPLIT * 100 + 0.5)),
        string.format("Shades take x%.1f from their own colour. Mirrorbacks ignore white light.", R.ENEMIES.shade_r.mult.r) },
    lens = { string.format("Focuses any beam that passes through it: x%.1f power.", R.LENS_GAIN),
        "Works on white and coloured light, and several lenses on one beam stack.",
        "Place it on a cell a beam already crosses." },
    upgrade = { "Click a placed emitter to raise its tier.",
        string.format("Tier 2 costs %d (%d dps).  Tier 3 costs %d (%d dps).", UC[1], EP[2], UC[2], EP[3]),
        string.format("Right-click any piece to sell it for %d%% of everything spent on it.", floor(R.SELL_BACK * 100 + 0.5)) },
}
local TIPS = {
    "Run beams along the lane, not across it. Long contact beats raw power.",
    "Shades shrug off the wrong colour. A prism in front of the lane pays for itself.",
    "Mirrorbacks ignore white light: keep a coloured beam on the lane.",
    "Calling a wave early pays energy for every second left on the clock.",
    "Save Surge for the Eclipse: x3 light for five seconds.",
}

local saved = tonumber(fs.read("Save/refract_sector.txt") or "1") or 1
local S = {
    sector = max(1, floor(saved)), best = max(1, floor(saved)),
    mode = "intro", t = 0, card_t = 0, speed = 1, paused = false, tool = "emitter",
    flash = 0, flash_c = BAD, banner = nil, banner_t = 0, energy_shown = 0, tip = 1,
}
local game
local L = {}
local hover = nil
local preview = nil
local floaters = {}
local last_segs, last_preview_segs
_G.refract = { S = S, R = R, W = World, game = function() return game end }

local function sound(name) if audio and audio.play then pcall(audio.play, name .. ".wav") end end
local SET = SettingsMenu.new({ title = "SETTINGS", subtitle = "REFRACT", click = function() sound("click") end,
    theme = { accent = { 0.45, 0.92, 1, 1 }, accent2 = { 0.65, 0.4, 1, 1 } },
    -- ULTRA forces shadows on in the shared menu; on this top-lit board they only blacken the blocks.
    -- TAA is never touched by the menu, but keep it pinned on with the rest of the AA setup.
    on_graphics = function()
        settings.set("shadows", false); settings.set("taa", true); settings.set("fxaa", false)
        if World.refresh_particles then World.refresh_particles() end
    end })
_G.refract.settings = SET

------------------------------------------------------------------ widgets
local widgets = {}
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
local function image(id, path, x, y, w, h, tint, z)
    quad(id, { style = "image", path = path, x = x, y = y, width = w, height = h, z = z, image_tint = tint or WHITE })
end
local function text(id, s, x, y, w, h, size, color, z, align)
    quad(id, { style = "text", label = s, x = x, y = y, width = w, height = h, z = z or 40, font_scale = size * L.k,
        text_color = color or WHITE, align_h = align or "center", align_v = "middle" })
end
-- Transparent input catcher over a custom-drawn control.
local function catcher(id, x, y, w, h, z)
    quad(id, { style = "text", label = "", x = x, y = y, width = w, height = h, z = z or 60, no_input = false })
end
local function state(id) return runtime_ui.get_state(SCREEN, id) end
local function clicked(id)
    local s = state(id)
    return s and s.clicked == true
end
local function hovered(id)
    local s = state(id)
    return s and s.hovered == true
end

-- Per-frame pools: dynamic quads take ids prefix..n each frame; leftovers from a busier frame hide.
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
local function lerp(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * t } end
local function ease_out(t) t = max(0, min(1, t)); return 1 - (1 - t) ^ 3 end
local function ease_back(t) t = max(0, min(1, t)); local c = 1.7; return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2 end

-- A panel: soft outer glow rim, body, top sheen.
local function panel(prefix, x, y, w, h, rim, rim_a, z, radius, fill)
    local k = L.k
    radius = radius or 14 * k
    rect(prefix .. "_rim", x - 2 * k, y - 2 * k, w + 4 * k, h + 4 * k, col4(rim or VIOLET, rim_a or 0.35), z, radius + 2 * k)
    rect(prefix .. "_body", x, y, w, h, fill or PANEL, z, radius)
    image(prefix .. "_sheen", TEX.sheen, x + radius * 0.5, y + 2 * k, w - radius, h * 0.5, { 1, 1, 1, 0.05 }, z)
end
local function hide_panel(prefix) hide(prefix .. "_rim"); hide(prefix .. "_body"); hide(prefix .. "_sheen") end

-- Enemy icon from the 2D sprites (shades: dark body inside a coloured ring).
local function enemy_icon(kind, x, y, s, z, a)
    a = a or 1
    local def = R.ENEMIES[kind]
    local function img(path, scale, tint)
        local w = s * scale
        image(pid("ic"), path, x + (s - w) / 2, y + (s - w) / 2, w, w, tint, z)
    end
    if def.shield then
        img(TEX.glow, 1.5, col4(LIGHT[def.shield], 0.35 * a)); img(TEX.en_dark, 0.8, { 1, 1, 1, a }); img(TEX.en_ring, 1.05, col4(LIGHT[def.shield], a))
    elseif kind == "eclipse" then
        local c = LIGHT[R.COLORS[2 + floor(S.t / 1.2) % 3]]
        img(TEX.corona, 1.35, col4(c, a)); img(TEX.en_dark, 0.8, { 1, 1, 1, a })
    elseif kind == "mirrorback" then img(TEX.en_chrome, 0.9, { 1, 1, 1, a })
    elseif kind == "dart" then img(TEX.en_dart, 1.0, col4(World.ENEMY_C.dart, a))
    elseif kind == "hulk" then img(TEX.en_hulk, 0.95, col4(World.ENEMY_C.hulk, a))
    elseif kind == "splitter" then img(TEX.en_splitter, 0.95, col4(World.ENEMY_C.splitter, a))
    else img(TEX.en_orb, 0.85, col4(World.ENEMY_C.mote, a)) end
end

------------------------------------------------------------------ layout
local function layout()
    local surf = runtime_ui.get_surface_size()
    local w, h = surf.width or 1280, surf.height or 800
    if w <= 0 or h <= 0 then return false end
    if L.w == w and L.h == h then return false end
    L.w, L.h = w, h
    L.k = min(w / 1600, h / 1000)
    L.top, L.bot = 104 * L.k, 156 * L.k
    return true
end

------------------------------------------------------------------ light helpers
local function path_light(cov)
    local s = 0
    for _, p in ipairs(game.path) do
        local c = cov[R.idx(p[1], p[2])]
        if c then s = s + c.w + c.r + c.g + c.b end
    end
    return s
end
local function light_mix(c)
    local tot = c.w + c.r + c.g + c.b
    if tot <= 0 then return nil end
    local m = { 0, 0, 0 }
    for _, col in ipairs(R.COLORS) do
        for i = 1, 3 do m[i] = m[i] + LIGHT[col][i] * c[col] / tot end
    end
    return m
end
local function burn_of(e)
    local p = game.path[min(#game.path, max(1, floor(e.d + 0.5)))]
    local c = p and game.cov[R.idx(p[1], p[2])]
    return c and light_mix(c)
end

------------------------------------------------------------------ floaters (world-anchored text)
local function floater(X, Z, s, c, size)
    floaters[#floaters + 1] = { X = X, Z = Z, s = s, c = c, t = 0, size = size or 1 }
end
local function floater_cell(x, y, s, c, size)
    local X, Z = World.cell_world(x, y)
    floater(X, Z, s, c, size)
end
local function draw_floaters(dt)
    local alive = {}
    for _, f in ipairs(floaters) do
        f.t = f.t + dt
        if f.t < 1.1 then
            local sx, sy = World.project(f.X, 0.9 + f.t * 0.9, f.Z)
            if sx then
                local a = 1 - (f.t / 1.1) ^ 2
                local pop = 0.7 + 0.3 * ease_back(f.t * 5)
                text(pid("ft"), f.s, sx - 120 * L.k, sy - 22 * L.k, 240 * L.k, 44 * L.k, f.size * 1.3 * pop, col4(f.c, a), 30)
            end
            alive[#alive + 1] = f
        end
    end
    floaters = alive
end

local function draw_health_bars()
    local k = L.k
    for _, e in ipairs(game.enemies) do
        if e.hp < e.max then
            local X, Z = World.enemy_world(game, e)
            local def = R.ENEMIES[e.kind]
            local sx, sy = World.project(X, World.BEAM_Y + def.size + 0.32, Z)
            if sx then
                local bw, bh = (def.cycle and 110 or 46) * k, 6 * k
                local f = max(0, e.hp / e.max)
                rect(pid("hb"), sx - bw / 2 - 2 * k, sy - 2 * k, bw + 4 * k, bh + 4 * k, { 0, 0, 0, 0.7 }, 28, 4 * k)
                rect(pid("hf"), sx - bw / 2, sy, bw * f, bh, lerp(BAD, GOOD, f), 29, 3 * k)
            end
        end
    end
end

------------------------------------------------------------------ beam glow (overlay)
-- The engine's bloom kernel is short, so a thin emissive line only gets a tight halo. The soft,
-- coloured falloff of a laser is drawn here instead: Gaussian strips projected from the 3D beams.
-- Beams along X project to horizontal lines; beams along Z are drawn cell by cell to follow the slant.
local function ppu(X, Z)
    local ax = World.project(X - 0.5, World.BEAM_Y, Z)
    local bx = World.project(X + 0.5, World.BEAM_Y, Z)
    return (ax and bx) and (bx - ax) or nil
end
local function draw_beam_glow()
    local t = World.time()
    local surge = World.surge_on() and 1.4 or 1
    local ga = World.ghost_beams and 0.5 or 1
    local Y = World.BEAM_Y
    for i, b in ipairs(World.beam_list()) do
        local c = b.c
        local v = World.vis(b.pw)                                 -- saturates: lenses cannot blow out the glow
        local pulse = 0.95 + 0.05 * sin(t * 4.5 + i * 1.7)
        local ww = (0.95 + 0.6 * v) * surge * pulse               -- full texture width, world units
        local a = (0.45 + 0.35 * v) * ga
        if b.hor then
            local xa, xb = min(b.x0, b.x1), max(b.x0, b.x1)
            local sx0, sy0 = World.project(xa, Y, b.z0)
            local sx1 = World.project(xb, Y, b.z0)
            local p = ppu((xa + xb) / 2, b.z0)
            if sx0 and sx1 and p then
                local w = ww * p
                image(pid("bgl"), TEX.beam_h, sx0, sy0 - w / 2, sx1 - sx0, w, col4(c, a), 5)
            end
        else
            -- A beam along Z projects to a slanted line. Slice it so each slice drifts under a pixel
            -- sideways, with exactly shared edges (no overlap bands, no visible steps).
            local za, zb = min(b.z0, b.z1), max(b.z0, b.z1)
            local ax0 = World.project(b.x0, Y, za)
            local bx0 = World.project(b.x0, Y, zb)
            if ax0 and bx0 then
                local n = max(1, min(96, math.ceil(abs(bx0 - ax0) / 0.8)))
                local px_, py_ = World.project(b.x0, Y, za)
                for j = 1, n do
                    local z1 = za + (zb - za) * j / n
                    local qx, qy = World.project(b.x0, Y, z1)
                    local p = ppu(b.x0, za + (zb - za) * (j - 0.5) / n)
                    if qx and p then
                        local w = ww * p
                        local cx = (px_ + qx) / 2
                        image(pid("bgl"), TEX.beam_v, cx - w / 2, min(py_, qy), w, abs(qy - py_), col4(c, a), 5)
                    end
                    px_, py_ = qx, qy
                end
            end
        end
        -- Flares where the light turns, splits or strikes stone, and a softer one at its source.
        for e = 0, 1 do
            local X, Z = e == 0 and b.x0 or b.x1, e == 0 and b.z0 or b.z1
            local sx, sy = World.project(X, Y, Z)
            local p = ppu(X, Z)
            if sx and p then
                local fs = p * (e == 1 and 1.1 or 0.8) * (0.85 + 0.3 * v) * (0.95 + 0.05 * sin(t * 5 + i))
                image(pid("bfl"), TEX.flare, sx - fs / 2, sy - fs / 2, fs, fs, col4(lerp(c, { 1, 1, 1 }, 0.3), (e == 1 and 0.8 or 0.5) * ga), 6)
            end
        end
    end
    -- Photons: bright glints racing along the beams.
    for _, ph in ipairs(World.photons or {}) do
        local sx, sy = World.project(ph[1], Y, ph[2])
        local p = ppu(ph[1], ph[2])
        if sx and p then
            local fs = p * 0.5
            image(pid("bph"), TEX.flare, sx - fs / 2, sy - fs / 2, fs, fs, col4(lerp(ph[3], { 1, 1, 1 }, 0.5), 0.9 * ga), 6)
        end
    end
end

------------------------------------------------------------------ HUD
local function draw_top()
    local k, w = L.k, L.w
    rect("top_bg", 0, 0, w, L.top, { 0.01, 0.012, 0.035, 0.78 }, 20)
    image("top_line", TEX.strip, 0, L.top - 6 * k, w, 12 * k, { 0.5, 0.4, 1, 0.55 }, 21)
    -- Title with a soft glow behind it.
    image("title_glow", TEX.glow, 10 * k, -30 * k, 400 * k, 160 * k, { 0.3, 0.7, 1, 0.22 + 0.05 * sin(S.t * 1.5) }, 21)
    text("title", "REFRACT", 34 * k, 14 * k, 380 * k, 60 * k, 2.6, { 0.78, 0.95, 1, 1 }, 40, "left")
    text("sub", "A  LIGHT-BENDING  DEFENSE", 37 * k, 66 * k, 380 * k, 24 * k, 0.75, { 0.55, 0.6, 0.85, 1 }, 40, "left")
    -- Centre: sector, wave and the wave pips.
    local cx = w / 2
    text("sector", "SECTOR " .. game.sector, cx - 200 * k, 6 * k, 400 * k, 26 * k, 0.85, VIOLET)
    text("wave", "WAVE  " .. game.wave .. " / " .. R.WAVES, cx - 220 * k, 26 * k, 440 * k, 46 * k, 1.75, WHITE)
    local pw, gap = 22 * k, 8 * k
    local total = R.WAVES * pw + (R.WAVES - 1) * gap
    for i = 1, R.WAVES do
        local x = cx - total / 2 + (i - 1) * (pw + gap)
        local c
        local boss = (i % 6 == 0)
        if i < game.wave or (i == game.wave and game.state ~= "fight" and game.state ~= "build") then c = col4(boss and GOLD or CYAN, 0.95)
        elseif i == game.wave then c = col4(WHITE, 0.6 + 0.4 * sin(S.t * 6))
        else c = boss and { 0.5, 0.35, 0.15, 0.7 } or { 0.2, 0.22, 0.35, 0.9 } end
        rect("pip" .. i, x, 76 * k, pw, 8 * k, c, 40, 4 * k)
    end
    -- Right: energy (counts up), core integrity (segmented). Compact panels anchored right; on narrow
    -- windows they shrink further so they never reach the centred wave pips.
    -- The settings menu's FPS counter sits in the top-right corner: make room for it when it is on.
    local fx = SET:get("show_fps") and 170 * k or 0
    local right = w - 24 * k - fx
    local block = (200 + 12 + 240) * k                      -- energy + gap + core at full size
    local room = right - (cx + total / 2 + 24 * k)          -- space between the pips and the edge
    local q = k * max(0.55, min(1, room / block))           -- panel scale
    local ph, py = 56 * q, 22 * k
    local ew, cw = 200 * q, 240 * q
    local cx2 = right - cw
    local ex = cx2 - 12 * q - ew
    panel("en", ex, py, ew, ph, GOLD, 0.3, 30, 12 * q)
    image("en_icon", TEX.icon_energy, ex + 10 * q, py + 8 * q, 40 * q, 40 * q, WHITE, 41)
    local bump = S.energy_bump or 0
    text("en_val", tostring(floor(S.energy_shown + 0.5)), ex + 56 * q, py + 2 * q, ew - 60 * q, 36 * q, (1.45 + bump * 0.3) * q / k, lerp(GOLD, WHITE, bump), 41, "left")
    text("en_lbl", "ENERGY", ex + 58 * q, py + 34 * q, ew - 60 * q, 18 * q, 0.62 * q / k, { 0.85, 0.7, 0.35, 1 }, 41, "left")
    panel("co", cx2, py, cw, ph, CYAN, 0.3, 30, 12 * q)
    image("co_icon", TEX.icon_core, cx2 + 10 * q, py + 8 * q, 40 * q, 40 * q, WHITE, 41)
    local hpf = game.core / R.CORE
    local cc = lerp(BAD, CYAN, hpf)
    text("co_val", "CORE  " .. game.core, cx2 + 56 * q, py + 3 * q, cw - 60 * q, 28 * q, 1.0 * q / k, cc, 41, "left")
    local sx0, sw_ = cx2 + 58 * q, cw - 70 * q
    local segw = (sw_ - 19 * 2 * q) / 20
    for i = 1, R.CORE do
        local on = i <= game.core
        local c = on and col4(cc, 0.95) or { 0.15, 0.16, 0.25, 0.9 }
        if on and S.flash > 0 and i > game.core - 3 then c = lerp(c, WHITE, S.flash) end
        rect("seg" .. i, sx0 + (i - 1) * (segw + 2 * q), py + 36 * q, segw, 10 * q, c, 41, 2 * q)
    end
    -- Next wave chips under the bar.
    local nxt = game:next_wave_list()
    local chip_y = L.top + 10 * k
    if nxt and S.mode == "play" then
        local n = #nxt
        local cw = 108 * k
        local tw = 150 * k + n * cw
        local x0 = cx - tw / 2
        panel("nx", x0, chip_y, tw, 50 * k, VIOLET, 0.25, 30, 25 * k, { 0.02, 0.025, 0.06, 0.7 })
        text("nx_lbl", game.state == "fight" and "AFTER THIS" or "NEXT WAVE", x0 + 10 * k, chip_y, 140 * k, 50 * k, 0.8, VIOLET, 41)
        for i, e in ipairs(nxt) do
            local ix = x0 + 150 * k + (i - 1) * cw
            enemy_icon(e[1], ix, chip_y + 5 * k, 40 * k, 41)
            text(pid("nxc"), "x" .. e[2], ix + 42 * k, chip_y, 64 * k, 50 * k, 1.05, WHITE, 41, "left")
        end
    else
        hide_panel("nx"); hide("nx_lbl")
    end
end

local function tool_card(i, tool, x, y, w, h, open)
    local k = L.k
    local id = "tool" .. i
    if open then
        hide_panel("tc" .. i); for _, s in ipairs({ "_ic", "_nm", "_cost", "_ci", "_key", "_kb", "_glow" }) do hide("tc" .. i .. s) end
        hide(id)
        return
    end
    local sel = S.tool == tool
    local hov = hovered(id)
    local cost = R.PIECES[tool] and R.PIECES[tool].cost
    local poor = cost and game.energy < cost
    local lift = sel and -6 * k or (hov and -3 * k or 0)
    y = y + lift
    if sel then
        image("tc" .. i .. "_glow", TEX.glow, x - w * 0.25, y - h * 0.4, w * 1.5, h * 1.8, { 0.4, 0.9, 1, 0.3 + 0.08 * sin(S.t * 4) }, 44)
    else hide("tc" .. i .. "_glow") end
    panel("tc" .. i, x, y, w, h, sel and CYAN or VIOLET, sel and 0.95 or (hov and 0.6 or 0.22), 45, 12 * k,
        sel and { 0.05, 0.1, 0.17, 0.95 } or PANEL)
    local is = 58 * k
    image("tc" .. i .. "_ic", TOOL_ICON[tool], x + (w - is) / 2, y + 6 * k, is, is, poor and { 0.5, 0.5, 0.6, 0.5 } or WHITE, 46)
    text("tc" .. i .. "_nm", TOOL_LABEL[tool], x, y + h - 46 * k, w, 22 * k, 0.8, sel and WHITE or DIM, 46)
    if cost then
        image("tc" .. i .. "_ci", TEX.icon_energy, x + w / 2 - 30 * k, y + h - 24 * k, 18 * k, 18 * k, WHITE, 46)
        text("tc" .. i .. "_cost", tostring(cost), x + w / 2 - 10 * k, y + h - 26 * k, 60 * k, 22 * k, 0.85, poor and BAD or GOLD, 46, "left")
    else
        hide("tc" .. i .. "_ci")
        text("tc" .. i .. "_cost", "tier up", x, y + h - 26 * k, w, 22 * k, 0.75, GOLD, 46)
    end
    rect("tc" .. i .. "_kb", x + 6 * k, y + 6 * k, 22 * k, 22 * k, sel and col4(CYAN, 0.9) or { 0.15, 0.17, 0.3, 0.9 }, 46, 5 * k)
    text("tc" .. i .. "_key", tostring(i), x + 6 * k, y + 6 * k, 22 * k, 22 * k, 0.75, sel and { 0.02, 0.08, 0.1, 1 } or WHITE, 47)
    catcher(id, x, y - lift, w, h)
end

local function action(id, icon, label, sub, x, y, w, h, primary, ready, fillf, fillc, open)
    local k = L.k
    if open then
        hide_panel(id .. "_p"); for _, s in ipairs({ "_ic", "_lb", "_sb", "_fill", "_glow" }) do hide(id .. s) end
        hide(id)
        return
    end
    local hov = hovered(id)
    local rim = primary and CYAN or VIOLET
    local fill = primary and { 0.04, 0.16, 0.2, 0.95 } or PANEL
    if not ready then fill = { 0.03, 0.035, 0.07, 0.8 }; rim = { 0.3, 0.3, 0.45, 1 } end
    if ready and primary then
        image(id .. "_glow", TEX.glow, x - w * 0.2, y - h * 0.5, w * 1.4, h * 2, col4(rim, 0.22 + 0.1 * sin(S.t * 4)), 44)
    else hide(id .. "_glow") end
    panel(id .. "_p", x, y, w, h, rim, hov and 0.9 or (ready and 0.55 or 0.25), 45, 12 * k, fill)
    if fillf and fillf > 0 then
        rect(id .. "_fill", x + 4 * k, y + h - 10 * k, (w - 8 * k) * min(1, fillf), 6 * k, fillc or GOLD, 46, 3 * k)
    else hide(id .. "_fill") end
    local is = 40 * k
    image(id .. "_ic", icon, x + 16 * k, y + (h - is) / 2, is, is, ready and WHITE or { 0.5, 0.5, 0.6, 0.6 }, 46)
    text(id .. "_lb", label, x + 64 * k, y + 10 * k, w - 72 * k, 34 * k, 1.05, ready and WHITE or DIM, 46, "left")
    text(id .. "_sb", sub, x + 64 * k, y + 44 * k, w - 72 * k, 26 * k, 0.75, ready and (primary and CYAN or GOLD) or { 0.45, 0.48, 0.6, 1 }, 46, "left")
    catcher(id, x, y, w, h)
end

local function draw_bottom()
    local k, w, h = L.k, L.w, L.h
    rect("bot_bg", 0, h - L.bot, w, L.bot, { 0.01, 0.012, 0.035, 0.8 }, 20)
    image("bot_line", TEX.strip, 0, h - L.bot - 6 * k, w, 12 * k, { 0.5, 0.4, 1, 0.55 }, 21)
    local open = SET:is_open() or S.mode ~= "play"
    local y, ch = h - L.bot + 26 * k, 110 * k
    local cw, gap = 132 * k, 12 * k
    local x0 = 36 * k
    for i, tool in ipairs(R.TOOLS) do tool_card(i, tool, x0 + (i - 1) * (cw + gap), y, cw, ch, open) end
    -- Actions on the right.
    local aw, ah = 250 * k, 84 * k
    local ay = y + (ch - ah) / 2
    local ax = w - 36 * k - 4 * aw - 3 * gap
    local can = game:can_call()
    local lbl, sub, fillf
    if game.state == "build" then lbl, sub = "START", "Space"
    elseif game.state == "between" then
        lbl, sub = "CALL WAVE", "+" .. game:call_bonus() .. " early  ·  Space"
        fillf = game.call_t / R.CALL_TIME
    else lbl, sub = "WAVE ACTIVE", (#game.enemies + #game.queue) .. " left" end
    action("btn_send", TEX.icon_play, lbl, sub, ax, ay, aw, ah, true, can, fillf, CYAN, open)
    local ready = game:surge_ready()
    local sf = game.surge_t > 0 and game.surge_t / R.SURGE_TIME or game.surge / 100
    action("btn_surge", TEX.icon_surge, ready and "SURGE!" or "SURGE", game.surge_t > 0 and "x3 light" or (ready and "Q  ·  x3 light" or floor(game.surge) .. "%  ·  kills charge it"),
        ax + aw + gap, ay, aw, ah, ready, ready or game.surge_t > 0, sf, game.surge_t > 0 and WHITE or GOLD, open)
    action("btn_speed", TEX.icon_speed, S.paused and "PAUSED" or ("SPEED  x" .. S.speed), "F  ·  P pause", ax + 2 * (aw + gap), ay, aw, ah, false, true, nil, nil, open)
    action("btn_settings", TEX.icon_menu, "MENU", "Esc", ax + 3 * (aw + gap), ay, aw, ah, false, true, nil, nil, open)

    -- Tool info panel: for the hovered tool card, or briefly for a tool just picked.
    local info_tool
    for i, tool in ipairs(R.TOOLS) do if not open and hovered("tool" .. i) then info_tool = tool end end
    if not info_tool and not open and (S.info_t or 0) > 0 then info_tool = S.tool end
    local ids = { "inf_ic", "inf_t", "inf_c", "inf_ci", "inf_1", "inf_2", "inf_3" }
    if info_tool then
        local a = min(1, (S.info_t or 1) * 3)
        if hovered("tool1") or hovered("tool2") or hovered("tool3") or hovered("tool4") or hovered("tool5") then a = 1 end
        local pw, ph = 760 * k, 150 * k
        local px0, py0 = 36 * k, h - L.bot - 58 * k - ph - 12 * k
        panel("inf", px0, py0, pw, ph, CYAN, 0.55 * a, 47, 16 * k, { 0.02, 0.03, 0.07, 0.93 * a })
        image("inf_ic", TOOL_ICON[info_tool], px0 + 18 * k, py0 + 18 * k, 72 * k, 72 * k, { 1, 1, 1, a }, 48)
        text("inf_t", TOOL_LABEL[info_tool], px0 + 108 * k, py0 + 12 * k, 300 * k, 36 * k, 1.25, col4(CYAN, a), 48, "left")
        local cost = R.PIECES[info_tool] and R.PIECES[info_tool].cost
        if cost then
            image("inf_ci", TEX.icon_energy, px0 + pw - 120 * k, py0 + 20 * k, 22 * k, 22 * k, { 1, 1, 1, a }, 48)
            text("inf_c", tostring(cost), px0 + pw - 94 * k, py0 + 14 * k, 80 * k, 34 * k, 1.1, col4(GOLD, a), 48, "left")
        else hide("inf_ci"); hide("inf_c") end
        for j, line in ipairs(TOOL_INFO[info_tool]) do
            text("inf_" .. j, line, px0 + 108 * k, py0 + (48 + (j - 1) * 30) * k, pw - 124 * k, 28 * k, 0.85,
                col4(j == 1 and WHITE or DIM, a), 48, "left")
        end
    else
        hide_panel("inf"); for _, id in ipairs(ids) do hide(id) end
    end

    -- Tooltip pill above the bar.
    local tip = TOOL_LABEL[S.tool] .. ":  " .. TOOL_HELP[S.tool]
    local tipc = DIM
    if hover and S.mode == "play" then
        local x, y2 = hover[1], hover[2]
        local p = game:piece(x, y2)
        local kind = game:kind(x, y2)
        if p then
            local name = R.PIECES[p.kind].name .. (p.kind == "emitter" and (" (tier " .. p.tier .. ")") or "")
            local act = (p.kind == "emitter" or p.kind == "mirror") and "Click: turn" or ""
            if S.tool == "upgrade" and p.kind == "emitter" then
                local c = game:upgrade_cost(x, y2)
                act = c and ("Click: upgrade for " .. c) or "Max tier"
            end
            tip = name .. "     " .. act .. "     Right-click: sell (+" .. game:sell_value(x, y2) .. ")"
            tipc = WHITE
        elseif kind == "path" then
            local c = game.cov[R.idx(x, y2)]
            tip = c and string.format("Lane     light here:  white %.0f   red %.0f   green %.0f   blue %.0f", c.w, c.r, c.g, c.b) or "Lane     no light here yet"
        elseif kind == "rock" then tip = "Rock: blocks light and building"
        elseif kind == "core" then tip = "The core: " .. game.core .. " integrity left"
        elseif kind == "gate" then tip = "The rift: enemies come through here"
        elseif preview then
            tip = string.format("%s  %d     light on the lane   %.0f  ->  %.0f", TOOL_LABEL[S.tool], R.PIECES[S.tool].cost, preview.before, preview.after)
            tipc = preview.ok and (preview.after > preview.before and GOOD or WHITE) or BAD
            if not preview.ok then tip = tip .. "     (not enough energy)" end
        end
    end
    if open then hide_panel("tip"); hide("tip") else
        local tw = 1000 * k
        panel("tip", 36 * k, h - L.bot - 58 * k, tw, 40 * k, VIOLET, 0.2, 30, 20 * k, { 0.02, 0.025, 0.06, 0.72 })
        text("tip", tip, 56 * k, h - L.bot - 58 * k, tw - 30 * k, 40 * k, 0.95, tipc, 41, "left")
    end
end

local function draw_overlay()
    local k, w, h = L.k, L.w, L.h
    image("vig", TEX.vignette, 0, 0, w, h, { 0, 0, 0, 0.85 }, 15)
    if S.flash > 0 then image("hurt", TEX.vignette, 0, 0, w, h, col4(S.flash_c, S.flash * 0.9), 16) else hide("hurt") end
    -- Banner: slides in on a light strip.
    if S.banner and S.banner_t > 0 then
        local life = 2.2 - S.banner_t
        local a = max(0, min(1, life * 5, S.banner_t * 2.5))
        local sc = 0.85 + 0.15 * ease_back(life * 3)
        local by = L.top + (h - L.top - L.bot) * 0.34
        local c = S.banner_c or WHITE
        image("ban_strip", TEX.strip, w * 0.15, by - 30 * k, w * 0.7, 140 * k, col4(c, 0.28 * a), 34)
        text("banner", S.banner, 0, by, w, 80 * k, 2.9 * sc, col4(lerp(c, WHITE, 0.25), a), 35)
        if S.banner_sub then text("banner_sub", S.banner_sub, 0, by + 70 * k, w, 34 * k, 1.1, col4(DIM, a), 35) else hide("banner_sub") end
    else hide("ban_strip"); hide("banner"); hide("banner_sub") end
end

------------------------------------------------------------------ cards
local CARD_IDS = { "card_dim", "card_title", "card_tglow", "card_sub", "card_line1", "card_line2", "card_line3", "card_ctrl", "btn_card", "card_btn_lb" }
local function hide_card()
    for _, id in ipairs(CARD_IDS) do hide(id) end
    hide_panel("card"); hide_panel("card_btn")
end

local INTRO_PIECES = {
    { "emitter", "EMITTER", "fires white light" }, { "mirror", "MIRROR", "bends it 90" },
    { "prism", "PRISM", "white -> red, green, blue" }, { "lens", "LENS", "focuses x1.5" },
}
local INTRO_ENEMIES = {
    { "mote", "Mote" }, { "dart", "Dart" }, { "hulk", "Hulk" }, { "shade_r", "Shade" },
    { "mirrorback", "Mirrorback" }, { "splitter", "Splitter" }, { "eclipse", "Eclipse" },
}

local function draw_card()
    if S.mode == "play" then hide_card(); return end
    local k, w, h = L.k, L.w, L.h
    local a = ease_out(S.card_t * 3)
    rect("card_dim", 0, 0, w, h, { 0, 0, 0.02, 0.55 * a }, 79)
    local intro = S.mode == "intro"
    local pw, ph = 1060 * k, (intro and 640 or 420) * k
    local px0, py0 = (w - pw) / 2, (h - ph) / 2 + (1 - a) * 40 * k
    panel("card", px0, py0, pw, ph, intro and VIOLET or (S.mode == "won" and GOOD or BAD), 0.6 * a, 80, 26 * k, { 0.025, 0.03, 0.07, 0.94 * a })
    local title, tc, sub
    if intro then title, tc, sub = "REFRACT", { 0.78, 0.95, 1 }, "Light is your only weapon. Every enemy a beam crosses burns."
    elseif S.mode == "won" then title, tc, sub = "SECTOR " .. game.sector .. " SECURED", GOOD, game.kills .. " burned   ·   " .. game.leaks .. " slipped through   ·   core " .. game.core .. " / " .. R.CORE
    else title, tc, sub = "CORE SHATTERED", BAD, "The light failed on wave " .. game.wave .. " of sector " .. game.sector end
    image("card_tglow", TEX.glow, px0 + pw * 0.2, py0 - 40 * k, pw * 0.6, 200 * k, col4(tc, 0.22 * a), 81)
    text("card_title", title, px0, py0 + 24 * k, pw, 84 * k, 3.0, col4(tc, a), 82)
    text("card_sub", sub, px0, py0 + 104 * k, pw, 36 * k, 1.05, col4({ 0.85, 0.9, 1 }, a), 82)
    if intro then
        -- Pieces row.
        local cw = (pw - 80 * k) / 4
        for i, p in ipairs(INTRO_PIECES) do
            local x = px0 + 40 * k + (i - 1) * cw
            local bob = sin(S.t * 2 + i) * 3 * k
            image(pid("cpi"), TEX.glow, x + cw / 2 - 60 * k, py0 + 150 * k + bob, 120 * k, 100 * k, { 0.4, 0.8, 1, 0.12 * a }, 81)
            image(pid("cpi"), TOOL_ICON[p[1]], x + cw / 2 - 36 * k, py0 + 160 * k + bob, 72 * k, 72 * k, { 1, 1, 1, a }, 82)
            text(pid("cpt"), p[2], x, py0 + 238 * k, cw, 28 * k, 1.0, col4(CYAN, a), 82)
            text(pid("cpt"), p[3], x, py0 + 264 * k, cw, 26 * k, 0.8, col4(DIM, a), 82)
        end
        -- Enemies row.
        local ew = (pw - 80 * k) / #INTRO_ENEMIES
        for i, e in ipairs(INTRO_ENEMIES) do
            local x = px0 + 40 * k + (i - 1) * ew
            enemy_icon(e[1], x + ew / 2 - 28 * k, py0 + 318 * k, 56 * k, 82, a)
            text(pid("cpt"), e[2], x, py0 + 378 * k, ew, 24 * k, 0.8, col4(WHITE, a), 82)
        end
        text("card_line1", "Shades take real damage only from their own colour.  Mirrorbacks ignore white.", px0, py0 + 418 * k, pw, 30 * k, 0.9, col4(DIM, a), 82)
        text("card_line2", "The Eclipse cycles red, green and blue: cover the lane in every colour.", px0, py0 + 446 * k, pw, 30 * k, 0.9, col4(DIM, a), 82)
        text("card_ctrl", "Left-click  build / turn     ·     Right-click  sell     ·     1-5  tools     ·     Space  wave     ·     Q  surge", px0, py0 + 488 * k, pw, 30 * k, 0.85, col4(VIOLET, a), 82)
        hide("card_line3")
    elseif S.mode == "won" then
        local stars = game.core == R.CORE and 3 or (game.core >= R.CORE / 2 and 2 or 1)
        for i = 1, 3 do
            local t = S.card_t - 0.3 - i * 0.22
            local sc = (i <= stars) and ease_back(t * 3) or 1
            local s = (i == 2 and 110 or 90) * k * max(0.01, sc)
            local x = w / 2 + (i - 2) * 130 * k - s / 2
            local y = py0 + (i == 2 and 160 or 178) * k + ((i == 2 and 110 or 90) * k - s) / 2
            local on = i <= stars and t > 0
            if on then image(pid("cst"), TEX.glow, x - s * 0.4, y - s * 0.4, s * 1.8, s * 1.8, { 1, 0.8, 0.3, 0.35 * a }, 81) end
            image(pid("cst"), TEX.star, x, y, s, s, on and { 1, 0.82, 0.3, a } or { 0.25, 0.27, 0.38, a }, 82)
        end
        text("card_line1", stars == 3 and "Flawless. Not a single photon wasted." or (stars == 2 and "Solid light. A few slipped through." or "Held, just barely."), px0, py0 + 290 * k, pw, 32 * k, 1.0, col4(GOLD, a), 82)
        hide("card_line2"); hide("card_line3"); hide("card_ctrl")
    else
        text("card_line1", "Tip: " .. TIPS[S.tip], px0, py0 + 170 * k, pw, 32 * k, 1.0, col4(GOLD, a), 82)
        text("card_line2", "Energy left " .. floor(game.energy) .. "   ·   " .. game.kills .. " burned", px0, py0 + 214 * k, pw, 30 * k, 0.9, col4(DIM, a), 82)
        hide("card_line3"); hide("card_ctrl")
    end
    local btn = intro and ("BEGIN  ·  SECTOR " .. S.sector) or (S.mode == "won" and "NEXT SECTOR" or "TRY AGAIN")
    local bw, bh = 420 * k, 72 * k
    local bx, by = (w - bw) / 2, py0 + ph - bh - 30 * k
    if SET:is_open() then hide_panel("card_btn"); hide("card_btn_lb"); hide("btn_card") else
        local hov = hovered("btn_card")
        panel("card_btn", bx, by, bw, bh, CYAN, (hov and 1 or 0.7) * a, 83, 16 * k, { 0.05, 0.2, 0.25, 0.95 * a })
        text("card_btn_lb", btn .. "   (Enter)", bx, by, bw, bh, 1.2, col4(WHITE, a), 84)
        catcher("btn_card", bx, by, bw, bh, 85)
    end
end

------------------------------------------------------------------ flow
local function retrace_world()
    World.set_beams(game.segs, false)
    World.set_lane_light(game.cov)
    last_segs, last_preview_segs = game.segs, nil
end

local function start_sector(n)
    S.sector = max(1, n)
    game = R.new_game(S.sector)
    _G.refract.g = game
    floaters, preview = {}, nil
    S.card_t, S.flash, S.banner_t = 0, 0, 0
    S.paused = false
    S.energy_shown = game.energy
    World.build(game)
    World.sync_pieces(game)
    World.set_ghost(nil)
    retrace_world()
    if S.sector > S.best then
        S.best = S.sector
        pcall(fs.write, "Save/refract_sector.txt", tostring(S.best))
    end
end

local function banner(s, c, sub) S.banner, S.banner_c, S.banner_sub, S.banner_t = s, c, sub, 2.2 end

local function send_wave()
    if not game:can_call() then sound("deny"); return end
    local ok, bonus = game:start_wave()
    if ok then
        sound("wave")
        local list = R.wave_list(game.sector, game.wave)
        local boss = false
        for _, e in ipairs(list) do if e[1] == "eclipse" then boss = true end end
        local g = game.path[1]
        local X, Z = World.cell_world(g[1], g[2])
        World.shock(X, Z, { 1, 0.3, 0.9 }, 3.2)
        if boss then banner("ECLIPSE APPROACHING", { 0.85, 0.5, 1 }, "its shield cycles red, green, blue"); sound("boss"); World.shake(0.4)
        else banner("WAVE " .. game.wave, WHITE) end
        if bonus and bonus > 0 then floater(X, Z, "+" .. bonus .. " early", GOLD, 1.1) end
    end
end

local function handle_events(ev)
    for _, e in ipairs(ev) do
        if e.kind == "kill" then
            local def = R.ENEMIES[e.enemy.kind]
            local sh = R.shield_of(e.enemy)
            local c = sh and LIGHT[sh] or (World.ENEMY_C[e.enemy.kind] or { 1, 1, 1 })
            if e.enemy.kind == "eclipse" then c = LIGHT[sh] end
            local X, Z = World.cell_world(e.x, e.y)
            World.burst(X, Z, c, def.cycle and 260 or 45, def.cycle and 9 or 5)
            World.shock(X, Z, c, def.cycle and 6 or 1.8, World.BEAM_Y)
            World.flash(X, Z, c, def.cycle and 3 or 0.6)
            floater(X, Z, "+" .. e.reward, GOLD)
            sound("pop")
            if def.cycle then World.shake(0.9); S.flash, S.flash_c = 0.5, GOLD; banner("ECLIPSE BROKEN", GOLD) end
        elseif e.kind == "leak" then
            S.flash, S.flash_c = 1, BAD
            local c = game.path[#game.path]
            local X, Z = World.cell_world(c[1], c[2])
            World.shake(0.6 + 0.2 * e.amount)
            World.flash(X, Z, { 1, 0.15, 0.15 }, 3)
            World.shock(X, Z, { 1, 0.2, 0.2 }, 3.5, 0.5)
            World.burst(X, Z, { 1, 0.25, 0.2 }, 60, 6, 0.9)
            World.set_core_health(game.core / R.CORE)
            floater(X, Z, "-" .. e.amount, BAD, 1.4)
            sound("leak")
        elseif e.kind == "wave_done" then
            if game.state ~= "won" then banner("WAVE " .. e.wave .. " CLEAR", GOOD, "+" .. e.bonus .. " energy") end
        elseif e.kind == "auto_wave" then
            sound("wave"); banner("WAVE " .. e.wave, WHITE)
        elseif e.kind == "won" then
            S.mode, S.card_t = "won", 0; sound("win")
        elseif e.kind == "lost" then
            S.mode, S.card_t = "lost", 0; S.tip = S.tip % #TIPS + 1; sound("lose")
        end
    end
end

local function edge_keys()
    local keys = {}
    return function(name)
        local down = input.is_key_down_raw(name)
        local was = keys[name]
        keys[name] = down
        return down and not was
    end
end
local pressed = edge_keys()
local KEYS = { "M", "R", "P", "F", "Q", "Return", "Space", "PageUp", "PageDown", "1", "2", "3", "4", "5" }

local function board_input(st)
    if not hover or not st then return end
    local x, y = hover[1], hover[2]
    local X, Z = World.cell_world(x, y)
    local p = game:piece(x, y)
    if st.right_clicked then
        if p then
            local v = game:sell(x, y)
            floater(X, Z, "+" .. v, GOLD)
            World.burst(X, Z, { 0.6, 0.8, 1 }, 30, 3)
            World.shock(X, Z, { 0.6, 0.8, 1 }, 1.4, World.BLOCK_H + 0.05)
            sound("sell")
        end
        return
    end
    if not st.clicked then return end
    if p then
        if S.tool == "upgrade" and p.kind == "emitter" then
            local ok = game:upgrade(x, y)
            if ok then
                sound("place")
                World.sync_pieces(game); World.pop(x, y)
                World.burst(X, Z, { 1, 0.8, 0.3 }, 50, 4)
                World.shock(X, Z, { 1, 0.8, 0.3 }, 1.8, World.BLOCK_H + 0.05)
                floater(X, Z, "TIER " .. p.tier, GOLD)
            else sound("deny") end
        elseif game:rotate(x, y) then
            sound("rotate")
            World.sync_pieces(game); World.pop(x, y)
        end
        return
    end
    if R.PIECES[S.tool] then
        local ok, why = game:place(S.tool, x, y)
        if ok then
            sound("place")
            World.sync_pieces(game); World.pop(x, y)
            World.burst(X, Z, { 0.5, 0.85, 1 }, 30, 3, World.BLOCK_H + 0.1)
            World.shock(X, Z, { 0.5, 0.85, 1 }, 1.6, World.BLOCK_H + 0.05)
            preview = nil
        else
            sound("deny")
            if why then floater(X, Z, why, BAD, 0.8) end
        end
    end
end

local function controls()
    if pressed("M") then SET:toggle_mute() end
    local enter = pressed("Return")
    local space = pressed("Space")
    if S.mode == "intro" then
        if S.card_t > 0.25 and (enter or space or clicked("btn_card")) then sound("click"); S.mode = "play" end
        return
    elseif S.mode ~= "play" then
        if S.card_t > 0.5 and (enter or space or clicked("btn_card")) then
            sound("click")
            start_sector(S.mode == "won" and game.sector + 1 or game.sector)
            S.mode = "play"
        end
        return
    end
    for i, tool in ipairs(R.TOOLS) do
        if pressed(tostring(i)) or clicked("tool" .. i) then S.tool = tool; S.info_t = 3.5; sound("click"); preview = nil end
    end
    if space or clicked("btn_send") then send_wave() end
    if pressed("F") or clicked("btn_speed") then S.speed = S.speed % 3 + 1; sound("click") end
    if pressed("P") then S.paused = not S.paused; sound("click") end
    if pressed("Q") or clicked("btn_surge") then
        if game:fire_surge() then
            sound("surge"); banner("SURGE", WHITE, "all light x3"); S.flash, S.flash_c = 0.4, WHITE
            World.shake(0.3)
            local c = game.path[#game.path]
            local X, Z = World.cell_world(c[1], c[2])
            World.shock(X, Z, { 1, 1, 1 }, 14, World.BEAM_Y)
        else sound("deny") end
    end
    if pressed("R") and (S.paused or game.state == "build") then start_sector(game.sector); return end
    if game.state == "build" then
        if pressed("PageUp") and game.sector < S.best then start_sector(game.sector + 1); return end
        if pressed("PageDown") and game.sector > 1 then start_sector(game.sector - 1); return end
    end
    local st = state("board")
    hover = nil
    if st and st.hovered then
        local x, y = World.cell_at(st.mouse_x, st.mouse_y)
        if x then hover = { x, y } end
    end
    board_input(st)
end

local function step(dt)
    S.t = S.t + dt
    if S.mode ~= "play" then S.card_t = S.card_t + dt end
    S.flash = max(0, S.flash - dt * 1.5)
    S.banner_t = max(0, S.banner_t - dt)
    S.info_t = max(0, (S.info_t or 0) - dt)
    -- Energy counter eases toward the real value and bumps when it rises.
    local diff = game.energy - S.energy_shown
    if diff > 0.5 then S.energy_bump = 1 end
    S.energy_shown = S.energy_shown + diff * min(1, dt * 10)
    S.energy_bump = max(0, (S.energy_bump or 0) - dt * 4)
    if S.mode == "play" and not S.paused then
        local sim = dt * S.speed
        local n = math.ceil(sim / (1 / 30))
        for _ = 1, n do
            handle_events(game:update(sim / n))
            if S.mode ~= "play" then break end
        end
    end
end

------------------------------------------------------------------ preview
local function update_preview()
    if not hover or S.tool == "upgrade" or not R.PIECES[S.tool] or S.mode ~= "play" then preview = nil; return end
    local x, y = hover[1], hover[2]
    local key = S.tool .. x .. "_" .. y .. "_" .. floor(game.energy) .. "_" .. tostring(game.segs)
    if preview and preview.key == key then return end
    if game:kind(x, y) ~= "ground" or game:piece(x, y) then preview = nil; return end
    local p = { kind = S.tool, tier = 1, flip = "/" }
    if S.tool == "emitter" then p.dir = game:best_dir(x, y) end
    local segs, cov = game:trace({ [R.idx(x, y)] = p })
    preview = { key = key, x = x, y = y, piece = p, segs = segs, before = path_light(game.cov), after = path_light(cov),
        ok = game.energy >= R.PIECES[S.tool].cost }
end

local function present(dt)
    if layout() then for id in pairs(widgets) do widgets[id] = true; hide(id) end end
    update_preview()
    -- World: beams (preview or live), lane light, ghost, cursor, enemies.
    if game.segs ~= last_segs then World.sync_pieces(game); retrace_world() end
    if preview then
        if last_preview_segs ~= preview.segs then World.set_beams(preview.segs, true); last_preview_segs = preview.segs end
        World.set_ghost(preview.piece, preview.x, preview.y, preview.ok)
    else
        if last_preview_segs then World.set_beams(game.segs, false); last_preview_segs = nil end
        World.set_ghost(nil)
    end
    if hover and S.mode == "play" then
        local hx, hy = hover[1], hover[2]
        local c = { 1, 1, 1 }
        if not game:piece(hx, hy) and R.PIECES[S.tool] then
            c = (preview and preview.ok) and { 0.3, 1, 0.55 } or { 1, 0.3, 0.3 }
        end
        local kind = game:kind(hx, hy)
        World.set_cursor(hx, hy, c, true, kind ~= "ground" and kind ~= "rock")
    else
        World.set_cursor(0, 0, nil, false)
    end
    World.set_surge(game.surge_t)
    World.update_enemies(game, dt, burn_of)
    World.update(dt, game)
    -- HUD.
    local open = SET:is_open() or S.mode ~= "play"
    if open then hide("board") else
        catcher("board", 0, L.top, L.w, L.h - L.top - L.bot, 1)
    end
    draw_beam_glow()
    draw_overlay()
    draw_top()
    draw_bottom()
    if S.mode == "play" then draw_health_bars() end
    draw_floaters(dt)
    draw_card()
    flush_pools()
end

------------------------------------------------------------------ boot
runtime_ui.clear(SCREEN)
runtime_ui.set_screen_overlay(SCREEN, true)
runtime_ui.show(SCREEN)
do -- Preload every HUD texture so the first frames do not hitch.
    local all = {}
    for _, v in pairs(TEX) do all[#all + 1] = v end
    pcall(runtime_ui.preload_images, all)
end
World.init({ particle_scale = function() return SET:particle_scale() end, shake_scale = function() return SET:shake_scale() end })
layout()
start_sector(S.sector)
SET:apply()
present(0)

script.on_update("refract", function()
    local dt = max(0, min(0.1, engine.get_metrics().delta_ms / 1000))
    local esc = pressed("Escape")
    if SET:update(dt) then
        for _, key in ipairs(KEYS) do pressed(key) end
        hover = nil
    elseif esc or clicked("btn_settings") then
        sound("click")
        SET:open()
    else
        controls()
        if not SET:is_open() then step(dt) end
    end
    present(dt)
end, "play")

print("[Refract] Ready. Build light: 1-5 tools, left-click build/turn, right-click sell, Space wave, Q surge, F speed, P pause, Esc menu.")
