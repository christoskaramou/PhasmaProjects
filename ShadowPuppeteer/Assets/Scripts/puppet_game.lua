-- Shadow Puppeteer game flow: the title card over the theatre, the map and level select (locks and stars), a level
-- (drag the lantern and props; or the keyboard), the HUD, the Esc pause card, the level-complete and failed cards, the
-- shared settings menu, the mute key, the save file and the sounds. Undertow's card pattern (pooled runtime_ui quads).
-- P is _G.puppet (puppet.lua): P.begin(id, script) starts a level under the rules, P.S.game is its state.
return function(P, SettingsMenu)
local G = {}
local D, W, R = P.D, P.W, P.R
local S = P.S
G.solutions = P.Scripts and P.Scripts.solutions or {}
local floor, min, max = math.floor, math.min, math.max
local SCREEN = "puppet"

------------------------------------------------------------------ palette (a toy theatre: velvet, brass, cream paper)
local CLEAR = { 0, 0, 0, 0 }
local CREAM = { 0.97, 0.91, 0.78, 1 }
local DIM = { 0.80, 0.72, 0.60, 0.9 }
local BRASS = { 0.92, 0.70, 0.40, 1 }
local GOLD = { 1.0, 0.80, 0.38, 1 }
local GOOD = { 0.80, 0.95, 0.62, 1 }
local BAD = { 0.98, 0.50, 0.40, 1 }
local PANEL = { 0.07, 0.015, 0.02, 0.93 }
local BTN = { 0.16, 0.03, 0.04, 1 }
local BTN_HI = { 0.26, 0.06, 0.06, 1 }
local LOCKED = { 0.10, 0.08, 0.08, 1 }
local RIM = { 0.82, 0.60, 0.32, 0.9 }

------------------------------------------------------------------ save (Save/puppet.txt: stars per level, last level)
local SAVE = "Save/puppet.txt"
local save = { stars = {}, last = "1-1", seen = {} }
local function load_save()
    save.stars, save.last, save.tutorial, save.seen = {}, "1-1", nil, {}
    local ok, txt = pcall(fs.read, SAVE)
    if ok and txt then
        for k, v in tostring(txt):gmatch("([%w_%-]+)%s*=%s*([%w_%-.]+)") do
            local id = k:match("^stars_(.+)$")
            local seen = k:match("^seen_(.+)$")
            if id then save.stars[id] = max(0, min(3, tonumber(v) or 0))
            elseif seen then save.seen[seen] = v == "1"
            elseif k == "tutorial" then save.tutorial = v == "1"
            elseif k == "last" then save.last = v end
        end
    end
end
load_save()
local function write_save()
    local t = { "# Shadow Puppeteer v1" }
    for _, l in ipairs(D.LEVELS) do
        if save.stars[l.id] then t[#t + 1] = string.format("stars_%s=%d", l.id, save.stars[l.id]) end
    end
    t[#t + 1] = "last=" .. save.last
    if save.tutorial then t[#t + 1] = "tutorial=1" end
    for _, m in ipairs(D.MAPS) do if save.seen[m.id] then t[#t + 1] = "seen_" .. m.id .. "=1" end end
    pcall(fs.write, SAVE, table.concat(t, "\n") .. "\n")
end
G.save, G.load_save, G.write_save = save, load_save, write_save

local function total_stars()
    local n = 0
    for _, v in pairs(save.stars) do n = n + v end
    return n
end
local function map_of(id) for _, l in ipairs(D.LEVELS) do if l.id == id then return l.map end end end
local function level(id) for i, l in ipairs(D.LEVELS) do if l.id == id then return l, i end end end
local function map_open(m) return total_stars() >= (m.unlock or 0) end
-- A level is open when its stage set is and it is the set's first, or the one before it in the set was won.
local function level_open(id)
    local lv, i = level(id)
    if not lv then return false end
    for _, m in ipairs(D.MAPS) do if m.id == lv.map and not map_open(m) then return false end end
    local prev = D.LEVELS[i - 1]
    if not prev or prev.map ~= lv.map then return true end
    return save.stars[prev.id] ~= nil
end
local function next_level(id)
    local _, i = level(id)
    local nx = i and D.LEVELS[i + 1]
    return nx and nx.id or nil
end
G.total_stars, G.level_open, G.map_open = total_stars, level_open, map_open

------------------------------------------------------------------ sounds (Assets/Audio, CC0 recordings: see CREDITS.txt)
local LEN = { click = 0.15, step = 0.25, climb = 0.3, fall = 0.6, land = 0.4, slide = 0.6, thorns = 1.2, candle = 1.5,
    star = 1.2, door = 2.0, drag = 0.5, unlock = 1.5 }
local MAX_VOICES, voices, clock, last = 12, {}, 0, {}
local function sound(name, gap)
    if not (audio and audio.play) then return end
    if last[name] and clock - last[name] < (gap or 0.08) then return end
    for i = #voices, 1, -1 do if voices[i] <= clock then table.remove(voices, i) end end
    if #voices >= MAX_VOICES then return end
    voices[#voices + 1] = clock + (LEN[name] or 1)
    last[name] = clock
    G.sounds_played = (G.sounds_played or 0) + 1
    G.last_sound = name
    pcall(audio.play, name .. ".wav")
end
G.sound = sound
local ambience_on = false
local function ambience(on)
    if on == ambience_on or not audio then return end
    ambience_on = on
    if on then pcall(audio.play_music, "ambience.wav") else pcall(audio.stop_music) end
end

local SET = SettingsMenu.new({ title = "SETTINGS", subtitle = "SHADOW PUPPETEER", click = function() sound("click") end,
    theme = { accent = { 0.92, 0.68, 0.36, 1 }, accent2 = { 1.0, 0.80, 0.40, 1 }, panel = { 0.07, 0.015, 0.02, 0.95 },
        row = { 0.16, 0.035, 0.04, 0.8 }, text = CREAM, dim = DIM, selected_text = { 1, 0.97, 0.88, 1 } },
    -- the look needs TAA + FXAA (cut-paper edges, review 2026-11-13) whatever the quality preset does
    on_graphics = function() pcall(settings.set, "taa", true); pcall(settings.set, "fxaa", true); W.apply_look() end })
G.settings = SET

------------------------------------------------------------------ widgets (pooled runtime_ui quads)
local widgets, pools, LY, u = {}, {}, {}, 1
-- A quad is sent to the engine only when it changed (the cards are rebuilt every frame: sending them all every frame
-- cost the title card a dropped frame in 20, live profile 2026-11-13)
local sent = {}
local function col_sig(c) return c and string.format("%.3f,%.3f,%.3f,%.3f", c[1], c[2], c[3], c[4] or 1) or "-" end
local function sig(o)
    return table.concat({ o.style or "", o.label or "", o.path or "", string.format("%.1f %.1f %.1f %.1f %.2f %.3f %.1f",
        o.x, o.y, o.width, o.height, o.z or 0, o.font_scale or 0, o.corner_radius or 0), col_sig(o.fill), col_sig(o.border),
        col_sig(o.text_color), col_sig(o.image_tint), tostring(o.no_input), tostring(o.visible), o.align_h or "" }, "|")
end
local function quad(id, o)
    o.fill = o.fill or CLEAR; o.border = o.border or CLEAR; o.accent = CLEAR
    if o.no_input == nil then o.no_input = true end
    if o.visible == nil then o.visible = true end
    widgets[id] = o.visible
    local k = sig(o)
    if sent[id] ~= k then sent[id] = k; runtime_ui.set_quad(SCREEN, id, o) end
end
local function hide(id)
    if widgets[id] then
        widgets[id] = false; sent[id] = nil
        runtime_ui.set_quad(SCREEN, id, { visible = false, x = 0, y = 0, width = 1, height = 1, no_input = true })
    end
end
G.quads = widgets
local function catcher(id, x, y, w, h, z) quad(id, { style = "text", label = "", x = x, y = y, width = w, height = h, z = z or 60, no_input = false }) end
local function ui_state(id) return runtime_ui.get_state(SCREEN, id) end
local function clicked(id) local s = ui_state(id); return s and s.clicked == true end
local function hovered(id) local s = ui_state(id); return s and s.hovered == true end
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
local function col4(c, a) return { c[1], c[2], c[3], (c[4] or 1) * (a or 1) } end
local function rect(x, y, w, h, fill, z, r, border)
    quad(pid("r"), { style = "text", label = "", x = x, y = y, width = w, height = h, z = z or 30, fill = fill, border = border, corner_radius = r or 0 })
end
local function image(path, x, y, w, h, z, a)
    quad(pid("i"), { style = "image", path = path, x = x, y = y, width = w, height = h, z = z or 40, image_tint = { 1, 1, 1, a or 1 } })
end
-- Text of em size px centred on y; a soft dark copy under it for legibility over the stage.
local MIN_PX = 12
G.text_log = {}
local function text(s, x, y, px, color, align, z, w)
    px = max(px, MIN_PX)
    local h = px * 1.6
    local bw = w or max(60, #s * px * 0.75)
    local bx = align == "left" and x or (align == "right" and x - bw or x - bw / 2)
    local a = color[4] or 1
    quad(pid("t"), { style = "text", label = s, x = bx + px * 0.05, y = y - h / 2 + px * 0.07, width = bw, height = h, z = (z or 40) - 0.5,
        font_scale = px / 16, text_color = { 0.02, 0.0, 0.0, 0.65 * a }, align_h = align or "center", align_v = "middle" })
    quad(pid("t"), { style = "text", label = s, x = bx, y = y - h / 2, width = bw, height = h, z = z or 40,
        font_scale = px / 16, text_color = color, align_h = align or "center", align_v = "middle" })
    G.text_log[#G.text_log + 1] = { s = s, x = bx, y = y - h / 2, w = bw, h = h, px = px, align = align or "center" }
end
local function panel(x, y, w, h, z, fill, rim, r)
    r = (r or 14) * u
    quad(pid("p"), { style = "text", label = "", x = x, y = y, width = w, height = h, z = z, fill = fill or PANEL, border = rim or RIM, corner_radius = r })
    quad(pid("p"), { style = "text", label = "", x = x + 3, y = y + 3, width = w - 6, height = h - 6, z = z, fill = CLEAR, border = col4(rim or RIM, 0.35), corner_radius = max(0, r - 3) })
end
local HV = {}
local function hv(id, sel)
    local v = HV[id] or 0
    v = v + (((hovered(id) or sel) and 1 or 0) - v) * min(1, (G.fdt or 1 / 60) * 14)
    HV[id] = v
    return v
end
local function ease_back(t) t = max(0, min(1, t)); local c = 1.7; return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2 end
-- A button: id, label, key hint, x, y, w, h, z, alpha, label colour, selected by the keyboard, locked.
local function button(id, label, key, x, y, w, h, z, a, colour, sel, locked)
    local hvv = locked and 0 or hv(id, sel)
    y = y - hvv * 3 * u
    if hvv > 0.02 then rect(x - 5 * u, y - 5 * u, w + 10 * u, h + 10 * u, CLEAR, z, 14 * u, col4(GOLD, 0.4 * hvv * a)) end
    panel(x, y, w, h, z + 1, col4(locked and LOCKED or (hvv > 0.5 and BTN_HI or BTN), a), col4(locked and DIM or (hvv > 0.5 and GOLD or RIM), a), 10)
    local px = min(26 * u, h * 0.42)
    text(label, x + w / 2, y + h / 2, px, col4(locked and DIM or (colour or CREAM), a), "center", z + 2, w - (key and 130 or 30) * u)
    if key then text(key, x + w - 16 * u, y + h / 2, px * 0.6, col4(BRASS, 0.9 * a), "right", z + 2, 110 * u) end
    catcher(id, x, y, w, h, z + 4)
    G.rects[id] = { x, y, w, h }
end
G.rects = {}
-- console / live runs: a button's window rectangle "x y w h" (centre clicks land on it)
function G.rect_of(id) local r = G.rects[id]; return r and string.format("%.0f %.0f %.0f %.0f", r[1], r[2], r[3], r[4]) or "none" end
-- n gold paper stars (of 3) in a row centred on x
local function stars_row(n, x, y, size, z, a)
    local gap = size * 0.18
    local x0 = x - (3 * size + 2 * gap) / 2
    for i = 1, 3 do
        image(i <= n and "Textures/ui_star_on.png" or "Textures/ui_star_off.png", x0 + (i - 1) * (size + gap), y - size / 2, size, size, z, a)
    end
end
local function layout()
    local ok, surf = pcall(runtime_ui.get_surface_size)
    local w, h = ok and surf and surf.width or 1280, ok and surf and surf.height or 720
    if w <= 0 or h <= 0 then w, h = 1280, 720 end
    local changed = LY.w ~= w or LY.h ~= h
    LY.w, LY.h = w, h
    u = min(w / 1920, h / 1080)
    return changed
end

------------------------------------------------------------------ input (key edges)
local keys = {}
local function keydown(k)
    local f = input and (input.is_key_down_raw or input.is_key_down)
    if not f then return false end
    local ok, r = pcall(f, k); return ok and r or false
end
G.keydown = keydown
local function pressed(name)
    local down = keydown(name)
    local was = keys[name]
    keys[name] = down
    return down and not was
end
local KEYS = { "Escape", "Return", "Space", "M", "Q", "R", "S", "N", "H", "Backspace", "Tab", "Left", "Right", "Up", "Down", "1", "2", "3" }
local function flush_keys() for _, k in ipairs(KEYS) do pressed(k) end end

------------------------------------------------------------------ flow
-- G.mode: "title" | "select" | "play" | "won" | "lost"; G.manual: console look/debug frames own the screen
G.mode, G.card_t, G.t, G.manual = "title", 0, 0, false
local function to_title()
    G.mode, G.card_t, G.pause = "title", 0, nil
    P.look("a")
    flush_keys()
end
G.to_title = to_title
local function to_select()
    G.mode, G.card_t, G.pause = "select", 0, nil
    G.sel = save.last
    if not level_open(G.sel) then G.sel = "1-1" end
    P.look("a")
    flush_keys()
end
G.to_select = to_select
function G.start_level(id, script, from_ui)
    id = id or save.last
    G.mode, G.card_t, G.pause, G.manual = "play", 0, nil, false
    G.level, G.result = id, nil
    G.ev_n, G.steps_n = 0, 0
    G.sel_prop = nil
    G.tut, G.intro, G.howto = nil, nil, nil
    save.last = id
    write_save()
    P.begin(id, script)
    if from_ui and not script then
        local lv = level(id)
        if id == D.LEVELS[1].id and not save.tutorial then
            G.tut = { step = 1, t = 0 }
            G.tut_reset()
        elseif lv and not save.seen[lv.map] then
            for _, m in ipairs(D.MAPS) do
                if m.id == lv.map and (m.intro or "") ~= "" then G.intro = { map = m, t = 0 } end
            end
            if not G.intro then save.seen[lv.map] = true; write_save() end
        end
    end
    flush_keys()
    return "playing " .. id
end
local function quit_game() sound("click"); pcall(engine.quit) end

-- The level ended: keep the best stars, note what it opened.
local function finish(g)
    local L = P.L
    local n, c = R.stars(L, g)
    G.result = { won = g.won, dead = g.dead, stars = n, c = c, t = g.t }
    if g.won then
        local before = total_stars()
        local open_before = {}
        for _, m in ipairs(D.MAPS) do open_before[m.id] = map_open(m) end
        if n > (save.stars[G.level] or -1) then save.stars[G.level] = n end
        write_save()
        G.result.new_best = n > 0 and total_stars() > before
        for _, m in ipairs(D.MAPS) do
            if not open_before[m.id] and map_open(m) then G.result.opened = m.name end
        end
        G.mode = "won"
        sound("door")
        if G.result.opened then sound("unlock") end
    else
        G.mode = "lost"
    end
    G.card_t = 0
    flush_keys()
end

-- The rules' events -> sounds, footsteps from the stride.
local function on_events(g)
    local n0 = G.ev_n or 0
    for i = n0 + 1, #g.events do
        local e = g.events[i].e
        if e == "fall" then sound("fall", 0.3)
        elseif e == "land" then sound("land", 0.15)
        elseif e == "climb" then sound("climb", 0.2)
        elseif e == "slide" then sound("slide", 0.3)
        elseif e == "star" then sound("star")
        elseif e == "dead:thorns" then sound("thorns")
        elseif e == "dead:candle" then sound("candle")
        elseif e == "dead:fell" or e == "dead:crushed" then sound("land") end
    end
    G.ev_n = #g.events
    -- a footstep each half stride on the ground; a rung creak each rung climbed
    local steps = floor((g.phase or 0))
    if steps ~= G.steps_n then
        G.steps_n = steps
        if g.mode == "walk" then sound("step", 0.12) elseif g.mode == "climb" then sound("climb", 0.2) end
    end
end

------------------------------------------------------------------ pause
local PAUSE_IDS = { "pz_block", "pz_resume", "pz_restart", "pz_howto", "pz_settings", "pz_menu", "pz_quit" }
local function open_pause() G.pause = { t = 0 }; flush_keys() end
local function close_pause() G.pause = nil; for _, id in ipairs(PAUSE_IDS) do hide(id) end; flush_keys() end
G.open_pause, G.close_pause = open_pause, close_pause
local function pause_controls(dt, esc)
    local Pz = G.pause
    Pz.t = Pz.t + dt
    if Pz.t < 0.12 then return end
    if esc or clicked("pz_resume") then sound("click"); close_pause()
    elseif G.mode == "play" and (pressed("R") or clicked("pz_restart")) then sound("click"); close_pause(); G.start_level(G.level, nil, true)
    elseif clicked("pz_settings") or pressed("S") then sound("click"); close_pause(); SET:open(function() open_pause() end)
    elseif clicked("pz_howto") or pressed("H") then sound("click"); close_pause(); G.open_howto("pause")
    elseif G.mode == "play" and (clicked("pz_menu") or pressed("Backspace")) then sound("click"); close_pause(); to_select()
    elseif pressed("Q") or clicked("pz_quit") then close_pause(); quit_game() end
end
local function draw_pause()
    local Pz = G.pause
    if not Pz or SET:is_open() then for _, id in ipairs(PAUSE_IDS) do hide(id) end; return end
    local w, h = LY.w, LY.h
    local a = min(1, Pz.t * 6)
    rect(0, 0, w, h, { 0.02, 0.0, 0.0, 0.55 * a }, 150)
    catcher("pz_block", 0, 0, w, h, 151)
    -- (on the title: no level to restart or leave)
    local rows = G.mode == "play" and { { "pz_resume", "RESUME", "Esc" }, { "pz_restart", "RESTART LEVEL", "R" },
        { "pz_howto", "HOW TO PLAY", "H" }, { "pz_settings", "SETTINGS", "S" }, { "pz_menu", "BACK TO MENU", "Bksp" },
        { "pz_quit", "QUIT GAME", "Q" } }
        or { { "pz_resume", "RESUME", "Esc" }, { "pz_howto", "HOW TO PLAY", "H" }, { "pz_settings", "SETTINGS", "S" },
        { "pz_quit", "QUIT GAME", "Q" } }
    if G.mode ~= "play" then hide("pz_restart"); hide("pz_menu") end
    local bw, bh, gap = 440 * u, 64 * u, 14 * u
    local cw = bw + 80 * u
    local ch = 160 * u + #rows * (bh + gap) + 16 * u
    local x, y = (w - cw) / 2, (h - ch) / 2 + (1 - ease_back(Pz.t * 3)) * 30 * u
    panel(x, y, cw, ch, 152, col4(PANEL, a), col4(RIM, a), 18)
    text("PAUSED", x + cw / 2, y + 58 * u, 50 * u, col4(CREAM, a), "center", 153, cw)
    local lv = G.mode == "play" and level(G.level)
    text(lv and (lv.id .. "   ·   " .. lv.name) or "SHADOW PUPPETEER", x + cw / 2, y + 110 * u, 20 * u, col4(GOLD, a), "center", 153, cw - 40 * u)
    for i, r in ipairs(rows) do
        local by = y + 160 * u + (i - 1) * (bh + gap)
        button(r[1], r[2], r[3], x + 40 * u, by, bw, bh, 154, a, r[1] == "pz_quit" and BAD or CREAM)
    end
end

------------------------------------------------------------------ title
local function draw_title(a)
    local w, h = LY.w, LY.h
    local cw, ch = 1100 * u, 880 * u
    local x, y = (w - cw) / 2, (h - ch) / 2 + (1 - ease_back(G.card_t * 2.5)) * 30 * u
    panel(x, y, cw, ch, 81, col4(PANEL, a * 0.93), col4(RIM, a), 20)
    local cx = x + cw / 2
    text("SHADOW PUPPETEER", cx, y + 80 * u, 76 * u, col4(CREAM, a), "center", 82, cw)
    text("A paper puppet walks on whatever shadows you cast. Light its way to the door.", cx, y + 140 * u, 22 * u, col4(DIM, a), "center", 82, cw - 60 * u)
    local bx, by, bw, bh = x + 50 * u, y + 180 * u, cw - 100 * u, 214 * u
    rect(bx, by, bw, bh, col4({ 0.0, 0.0, 0.0, 0.45 }, a), 82, 12 * u, col4(RIM, 0.35 * a))
    local rows = {
        { "DRAG THE LANTERN", "sideways moves the shadows; nearer the props, they grow" },
        { "DRAG A PROP", "slide the cup, comb or ladder along its track" },
        { "KEYBOARD", "arrows: lantern  ·  Tab: pick a prop  ·  A D / W S: move it" },
        { "THE PUPPET", "walks by itself; thorns, falls and the candle end the show" },
    }
    for i, r in ipairs(rows) do
        local ry = by + 34 * u + (i - 1) * 49 * u
        text(r[1], bx + 30 * u, ry, 20 * u, col4(i == 1 and GOOD or GOLD, a), "left", 83, 300 * u)
        text(r[2], bx + 310 * u, ry, 18 * u, col4(CREAM, a), "left", 83, bw - 330 * u)
    end
    local bw2, bh2, gap = 380 * u, 66 * u, 14 * u
    local x0 = cx - bw2 / 2
    local y0 = by + bh + 30 * u
    button("t_play", "PLAY", "Enter", x0, y0, bw2, bh2, 84, a, GOOD)
    button("t_howto", "HOW TO PLAY", "H", x0, y0 + (bh2 + gap), bw2, bh2, 84, a)
    button("t_settings", "SETTINGS", "S", x0, y0 + 2 * (bh2 + gap), bw2, bh2, 84, a)
    button("t_quit", "QUIT", "Q", x0, y0 + 3 * (bh2 + gap), bw2, bh2, 84, a, BAD)
    text(string.format("%d of %d stars", total_stars(), 3 * #D.LEVELS), cx, y + ch - 66 * u, 20 * u, col4(GOLD, a), "center", 82, cw - 40 * u)
    text("Esc pause   ·   M mute   ·   R restart a level", cx, y + ch - 30 * u, 17 * u, col4(DIM, 0.9 * a), "center", 82, cw - 40 * u)
end
local function title_controls()
    if G.card_t < 0.25 then return end
    if pressed("Return") or pressed("Space") or clicked("t_play") then sound("click"); to_select()
    elseif pressed("H") or clicked("t_howto") then sound("click"); G.open_howto("title")
    elseif pressed("S") or clicked("t_settings") then sound("click"); SET:open(function() flush_keys() end)
    elseif pressed("Q") or clicked("t_quit") then quit_game() end
end

------------------------------------------------------------------ map and level select
local function draw_select(a)
    local w, h = LY.w, LY.h
    local cw, ch = 1560 * u, 820 * u
    local x, y = (w - cw) / 2, (h - ch) / 2 + (1 - ease_back(G.card_t * 2.5)) * 30 * u
    panel(x, y, cw, ch, 81, col4(PANEL, a * 0.94), col4(RIM, a), 20)
    local cx = x + cw / 2
    text("CHOOSE A STAGE", cx, y + 64 * u, 54 * u, col4(CREAM, a), "center", 82, cw)
    text(string.format("%d of %d stars   ·   each level: reach the door, take its star, arrive before the quick mark",
        total_stars(), 3 * #D.LEVELS), cx, y + 114 * u, 20 * u, col4(GOLD, a), "center", 82, cw - 60 * u)
    local mw, gap = 460 * u, 40 * u
    local mx0 = cx - (3 * mw + 2 * gap) / 2
    for mi, m in ipairs(D.MAPS) do
        local mx, my, mh = mx0 + (mi - 1) * (mw + gap), y + 160 * u, 540 * u
        local open = map_open(m)
        panel(mx, my, mw, mh, 82, col4({ 0.03, 0.0, 0.0, 0.55 }, a), col4(open and RIM or DIM, a), 14)
        text(m.name:upper(), mx + mw / 2, my + 40 * u, 26 * u, col4(open and CREAM or DIM, a), "center", 83, mw - 20 * u)
        local sub = open and ({ stage = "cup, comb and ladder", nursery = "a clockwork mouse runs by itself",
            fair = "a balloon on a string goes up and down" })[m.id] or string.format("opens at %d stars", m.unlock)
        text(sub, mx + mw / 2, my + 78 * u, 17 * u, col4(open and DIM or BAD, a), "center", 83, mw - 30 * u)
        local k = 0
        for _, l in ipairs(D.LEVELS) do
            if l.map == m.id then
                k = k + 1
                local id = "s_" .. l.id
                local lo = level_open(l.id)
                local by = my + 120 * u + (k - 1) * 138 * u
                button(id, l.id .. "  " .. l.name, nil, mx + 30 * u, by, mw - 60 * u, 76 * u, 84, a, CREAM, G.sel == l.id, not lo)
                if lo then stars_row(save.stars[l.id] or 0, mx + mw / 2, by + 102 * u, 34 * u, 86, a)
                else text("locked", mx + mw / 2, by + 102 * u, 16 * u, col4(DIM, a), "center", 86, 200 * u) end
            end
        end
    end
    button("s_back", "BACK", "Esc", cx - 190 * u, y + ch - 96 * u, 380 * u, 64 * u, 84, a)
    text("arrows choose   ·   Enter plays", cx, y + ch - 18 * u, 16 * u, col4(DIM, 0.9 * a), "center", 82, cw - 40 * u)
end
local function select_move(dx, dy)
    local _, i = level(G.sel)
    local n = #D.LEVELS
    local j = i
    if dx ~= 0 then j = i + 3 * dx end                     -- next / previous stage set (3 levels each)
    if dy ~= 0 then j = i + dy end
    j = max(1, min(n, j))
    if level_open(D.LEVELS[j].id) then G.sel = D.LEVELS[j].id; sound("click", 0.05) end
end
local function select_controls(esc)
    if G.card_t < 0.25 then return end
    if esc or pressed("Backspace") or clicked("s_back") then sound("click"); to_title(); return end
    if pressed("Left") then select_move(-1, 0) elseif pressed("Right") then select_move(1, 0)
    elseif pressed("Up") then select_move(0, -1) elseif pressed("Down") then select_move(0, 1) end
    if pressed("Return") or pressed("Space") then
        if level_open(G.sel) then sound("click"); G.start_level(G.sel, nil, true) end
        return
    end
    for _, l in ipairs(D.LEVELS) do
        if clicked("s_" .. l.id) and level_open(l.id) then sound("click"); G.start_level(l.id, nil, true); return end
    end
end

------------------------------------------------------------------ HOW TO PLAY (title and pause, BACK)
local HOWTO_IDS = { "h_block", "h_back" }
local HOWTO = {
    { "THE GOAL", "Get the paper puppet to the red door. The gold star on the way is a bonus." },
    { "THE PUPPET", "It walks by itself and turns at walls. It stands on black paper and on every shadow." },
    { "PROPS", "Drag the cup, comb or ladder along its floor track: its shadow moves with it." },
    { "THE LANTERN", "Drag it: sideways slides every shadow; nearer the props makes the shadows bigger." },
    { "CLIMB, FALL, SLIDE", "It climbs a ladder's shadow, falls off edges, slides down slopes too steep to walk." },
    { "DANGER", "Thorns in the pits end the show, and so does the candle when it burns down." },
    { "STARS", "Up to 3 a level: reach the door, take the star, arrive before the quick mark." },
    { "NEW STAGES", "Stars open the Moonlit Nursery (4) and the Harvest Fair (9), each with a new prop." },
    { "MOUSE", "Drag the lantern or a prop. Click a button on any card." },
    { "KEYS", "Arrows: lantern  ·  Tab: pick a prop  ·  A D / W S: move it  ·  R restart  ·  Esc pause  ·  M mute" },
}
G.HOWTO = HOWTO
function G.open_howto(from) G.howto = { from = from, t = 0 }; flush_keys() end
local function close_howto()
    local from = G.howto and G.howto.from
    G.howto = nil
    for _, id in ipairs(HOWTO_IDS) do hide(id) end
    if from == "pause" then open_pause() end
    flush_keys()
end
local function draw_howto()
    local Hc = G.howto
    local w, h = LY.w, LY.h
    local a = min(1, Hc.t * 6)
    rect(0, 0, w, h, { 0.02, 0.0, 0.0, 0.6 * a }, 150)
    catcher("h_block", 0, 0, w, h, 151)
    local cw, ch = 1500 * u, 960 * u
    local x, y = (w - cw) / 2, (h - ch) / 2
    panel(x, y, cw, ch, 152, col4(PANEL, a), col4(RIM, a), 18)
    text("HOW TO PLAY", x + cw / 2, y + 62 * u, 52 * u, col4(CREAM, a), "center", 153, cw)
    for i, r in ipairs(HOWTO) do
        local ry = y + 140 * u + (i - 1) * 64 * u
        text(r[1], x + 60 * u, ry, 21 * u, col4(GOLD, a), "left", 153, 300 * u)
        text(r[2], x + 380 * u, ry, 21 * u, col4(CREAM, a), "left", 153, cw - 430 * u)
    end
    button("h_back", "BACK", "Esc", x + cw / 2 - 190 * u, y + ch - 100 * u, 380 * u, 64 * u, 154, a)
end
local function howto_controls(dt, esc)
    G.howto.t = G.howto.t + dt
    if G.howto.t < 0.15 then return end
    if esc or pressed("Backspace") or pressed("H") or clicked("h_back") then sound("click"); close_howto() end
end

------------------------------------------------------------------ the guided first level (once, saved; skippable)
-- The rules wait while it explains; the player's drags still work. Steps: the puppet, the door and the star, the cup
-- (moved: next), the lantern (moved: next), then Enter lets the puppet walk.
local TUT = {
    { "THIS IS YOUR PUPPET", "It walks by itself, on black paper and on shadows.", "puppet", "Enter: next" },
    { "THE RED DOOR IS THE GOAL", "Get the puppet there. The gold star on the way is a bonus.", "door", "Enter: next" },
    { "DRAG THE CUP", "Slide it along its track (or Tab, then A / D): its shadow moves with it.", "cup", "move the cup" },
    { "DRAG THE LANTERN", "Sideways slides the shadows; nearer the props makes them bigger (or arrows).", "lantern", "move the lantern" },
    { "BRIDGE THE THORNS", "Make the cup's shadow span the pit, then press Enter: the puppet starts walking.", "pit", "Enter: go" },
}
G.TUT = TUT
local TUT_IDS = { "tut_next", "tut_skip" }
function G.tut_reset()
    local st = W.state
    G.tut.cup0, G.tut.lan0 = st.cup, { st.lantern[1], st.lantern[2] }
end
local function end_tut()
    G.tut = nil
    save.tutorial = true
    write_save()
    for _, id in ipairs(TUT_IDS) do hide(id) end
    flush_keys()
end
G.end_tut = end_tut
local function tut_target(kind)
    local g, L = S.game, P.L
    local st = W.state
    local x, y, z, r
    if kind == "puppet" and g then x, y, z, r = g.x, D.SY, g.y + 0.15, 70
    elseif kind == "door" then x, y, z, r = L.door[1], D.SY, L.door[2] + 0.16, 80
    elseif kind == "cup" then x, y, z, r = st.cup, D.PROPS.cup.y, 0.13, 110
    elseif kind == "lantern" then x, y, z, r = st.lantern[1], st.lantern[2], 0.14, 90
    elseif kind == "pit" then
        local p = D.LEVELS[1].pits[1]
        x, y, z, r = (p[1] + p[2]) / 2, D.SY, 0.2, 140
    else return nil end
    local px, py = W.project(x, y, z)
    return px, py, r * u
end
local function tut_controls(dt)
    local T_ = G.tut
    T_.t = T_.t + dt
    if pressed("Backspace") or clicked("tut_skip") then sound("click"); end_tut(); return end
    if T_.t < 0.3 then return end
    local st = W.state
    local step = TUT[T_.step]
    local moved = (step[3] == "cup" and math.abs(st.cup - T_.cup0) > 0.12)
        or (step[3] == "lantern" and (math.abs(st.lantern[1] - T_.lan0[1]) + math.abs(st.lantern[2] - T_.lan0[2])) > 0.12)
    if moved or pressed("Return") or clicked("tut_next") then
        sound("click")
        if T_.step >= #TUT then end_tut() else T_.step, T_.t = T_.step + 1, 0; G.tut_reset() end
    end
end
local function draw_tut()
    local T_ = G.tut
    local w, h = LY.w, LY.h
    local step = TUT[T_.step]
    local a = min(1, T_.t * 5)
    local sx, sy, r
    local px, py
    px, py, r = tut_target(step[3])
    if px then
        -- a pulsing gold ring round what the step is about
        local pr = r * (1 + 0.08 * math.sin(G.t * 5))
        rect(px - pr, py - pr, 2 * pr, 2 * pr, CLEAR, 90, pr, col4(GOLD, 0.9 * a))
        rect(px - pr - 4 * u, py - pr - 4 * u, 2 * pr + 8 * u, 2 * pr + 8 * u, CLEAR, 90, pr + 4 * u, col4(GOLD, 0.35 * a))
    end
    -- the callout: above the ring when there is room, else below; kept inside the window
    local cw, ch = 900 * u, 210 * u
    local cx = max(20 * u, min(w - cw - 20 * u, (px or w / 2) - cw / 2))
    local cy = (py or h / 2) - (r or 0) - ch - 24 * u
    if cy < 130 * u then cy = (py or h / 2) + (r or 0) + 24 * u end
    cy = min(cy, h - ch - 100 * u)
    panel(cx, cy, cw, ch, 91, col4(PANEL, 0.95 * a), col4(GOLD, a), 14)
    text(string.format("%d / %d   %s", T_.step, #TUT, step[1]), cx + 30 * u, cy + 40 * u, 26 * u, col4(GOLD, a), "left", 92, cw - 60 * u)
    text(step[2], cx + 30 * u, cy + 88 * u, 19 * u, col4(CREAM, a), "left", 92, cw - 60 * u)
    local nxt = step[4]
    if nxt:sub(1, 5) == "Enter" then
        button("tut_next", nxt == "Enter: go" and "GO" or "NEXT", "Enter", cx + 30 * u, cy + ch - 76 * u, 300 * u, 56 * u, 93, a, GOOD)
    else
        hide("tut_next")
        text(nxt:upper() .. " to go on", cx + 30 * u, cy + ch - 48 * u, 18 * u, col4(GOOD, a), "left", 92, 330 * u)
    end
    button("tut_skip", "SKIP TUTORIAL", "Bksp", cx + cw - 440 * u, cy + ch - 76 * u, 410 * u, 56 * u, 93, a)
end

------------------------------------------------------------------ a new stage set's prop, the first time it is played
local INTRO_IDS = { "in_ok" }
local function draw_intro()
    local I = G.intro
    local w, h = LY.w, LY.h
    local a = min(1, I.t * 5)
    local cw, ch = 1000 * u, 330 * u
    local x, y = (w - cw) / 2, 150 * u
    panel(x, y, cw, ch, 91, col4(PANEL, 0.95 * a), col4(GOLD, a), 16)
    text("NEW IN " .. I.map.name:upper(), x + cw / 2, y + 50 * u, 30 * u, col4(GOLD, a), "center", 92, cw - 40 * u)
    -- the line, wrapped at a word break near the middle
    local s_ = I.map.intro
    local cut = s_:find(" ", math.floor(#s_ / 2)) or #s_
    text(s_:sub(1, cut - 1), x + cw / 2, y + 114 * u, 21 * u, col4(CREAM, a), "center", 92, cw - 60 * u)
    text(s_:sub(cut + 1), x + cw / 2, y + 150 * u, 21 * u, col4(CREAM, a), "center", 92, cw - 60 * u)
    button("in_ok", "GOT IT", "Enter", x + cw / 2 - 160 * u, y + ch - 96 * u, 320 * u, 62 * u, 93, a, GOOD)
end
local function intro_controls(dt)
    local I = G.intro
    I.t = I.t + dt
    if I.t < 0.3 then return end
    if pressed("Return") or pressed("Space") or clicked("in_ok") then
        sound("click")
        save.seen[I.map.id] = true
        write_save()
        G.intro = nil
        hide("in_ok")
        flush_keys()
    end
end

------------------------------------------------------------------ level complete / failed
local DEATH = { thorns = { "CAUGHT ON THE THORNS", "It walked into the pit: no shadow was there to carry it over." },
    candle = { "THE CANDLE BURNT OUT", "Time ran out before it reached the door: build its path sooner." },
    fell = { "LOST OFF THE PAPER", "It fell out of the light at the paper's edge." },
    crushed = { "CRUSHED", "A shadow was moved onto the puppet: move shadows beside it, not over it." } }
local function draw_end(a)
    local w, h = LY.w, LY.h
    local r = G.result
    local cw, ch = 900 * u, (r.won and 600 or 440) * u      -- (the failed card at 600 left a blank band)
    local x, y = (w - cw) / 2, (h - ch) / 2 + (1 - ease_back(G.card_t * 2.5)) * 30 * u
    panel(x, y, cw, ch, 81, col4(PANEL, a * 0.94), col4(RIM, a), 20)
    local cx = x + cw / 2
    local lv = level(G.level)
    text(lv.id .. "   ·   " .. lv.name, cx, y + 44 * u, 20 * u, col4(GOLD, a), "center", 82, cw)
    if r.won then
        text("THROUGH THE DOOR!", cx, y + 104 * u, 56 * u, col4(CREAM, a), "center", 82, cw)
        stars_row(r.stars, cx, y + 200 * u, 76 * u, 83, a)
        local L = P.L
        local lines = { { "reached the door", r.c[1] }, { "took the bonus star", r.c[2] },
            { string.format("arrived before %d s  (%.1f s)", floor(L.quick_s or 0), r.t), r.c[3] } }
        for i, l in ipairs(lines) do
            text((l[2] and "+  " or "-  ") .. l[1], cx, y + 270 * u + (i - 1) * 34 * u, 20 * u, col4(l[2] and GOOD or DIM, a), "center", 82, cw - 60 * u)
        end
        if r.opened then text(r.opened:upper() .. " IS OPEN", cx, y + 384 * u, 24 * u, col4(GOLD, a), "center", 82, cw - 40 * u) end
        local nx = next_level(G.level)
        local has_next = nx and level_open(nx)
        local bw, bh, gap = 250 * u, 66 * u, 20 * u
        local by = y + ch - bh - 44 * u
        if has_next then
            button("e_next", "NEXT", "Enter", cx - 1.5 * bw - gap, by, bw, bh, 84, a, GOOD)
        else hide("e_next") end
        button("e_retry", "RETRY", "R", has_next and (cx - bw / 2) or (cx - bw - gap / 2), by, bw, bh, 84, a)
        button("e_menu", "MENU", "Esc", has_next and (cx + bw / 2 + gap) or (cx + gap / 2), by, bw, bh, 84, a)
    else
        local d = DEATH[r.dead] or { "THE SHOW STOPPED", "" }
        text(d[1], cx, y + 110 * u, 50 * u, col4(BAD, a), "center", 82, cw - 40 * u)
        text(d[2], cx, y + 166 * u, 21 * u, col4(DIM, a), "center", 82, cw - 60 * u)
        -- the level's own hint, wrapped onto two lines at a word break near the middle
        local hint = "Hint: " .. (lv.hint or "")
        local l1, l2 = hint, nil
        if #hint > 60 then
            local cut = hint:find(" ", math.floor(#hint / 2)) or #hint
            l1, l2 = hint:sub(1, cut - 1), hint:sub(cut + 1)
        end
        text(l1, cx, y + 222 * u, 20 * u, col4(GOLD, a), "center", 82, cw - 60 * u)
        if l2 then text(l2, cx, y + 254 * u, 20 * u, col4(GOLD, a), "center", 82, cw - 60 * u) end
        hide("e_next")
        local bw, bh, gap = 300 * u, 66 * u, 24 * u
        local by = y + ch - bh - 54 * u
        button("e_retry", "RETRY", "Enter", cx - bw - gap / 2, by, bw, bh, 84, a, GOOD)
        button("e_menu", "MENU", "Esc", cx + gap / 2, by, bw, bh, 84, a)
    end
end
local function end_controls(esc)
    if G.card_t < 0.4 then return end
    local r = G.result
    local nx = next_level(G.level)
    if r.won and nx and level_open(nx) and (pressed("Return") or pressed("N") or clicked("e_next")) then
        sound("click"); G.start_level(nx, nil, true)
    elseif pressed("R") or clicked("e_retry") or (not r.won and pressed("Return")) then sound("click"); G.start_level(G.level, nil, true)
    elseif esc or pressed("Backspace") or clicked("e_menu") then sound("click"); to_select() end
end

------------------------------------------------------------------ HUD (while playing)
local function draw_hud()
    local g, L = S.game, P.L
    if not g then return end
    local w, h = LY.w, LY.h
    local m = 26 * u
    local lv = level(G.level)
    panel(m, m, 470 * u, 96 * u, 20, { 0.05, 0.01, 0.015, 0.62 }, col4(RIM, 0.55), 12)
    text(lv.id .. "  " .. lv.name, m + 22 * u, m + 32 * u, 26 * u, CREAM, "left", 21, 430 * u)
    local mp
    for _, mm in ipairs(D.MAPS) do if mm.id == lv.map then mp = mm end end
    text(mp and mp.name or "", m + 22 * u, m + 68 * u, 16 * u, DIM, "left", 21, 430 * u)
    -- the candle (time) and the three challenges, top right
    local left = max(0, (L.candle_s or D.RULES.candle_s) - g.t)
    local pw = 390 * u
    panel(w - m - pw, m, pw, 96 * u, 20, { 0.05, 0.01, 0.015, 0.62 }, col4(RIM, 0.55), 12)
    text(string.format("CANDLE  %d s", math.ceil(left)), w - m - pw + 22 * u, m + 32 * u, 24 * u, left < 8 and BAD or GOLD, "left", 21, 220 * u)
    local quick = L.quick_s and g.t <= L.quick_s
    text(L.quick_s and (quick and string.format("quick mark in %d s", math.ceil(L.quick_s - g.t)) or "quick mark passed") or "",
        w - m - pw + 22 * u, m + 68 * u, 16 * u, quick and DIM or col4(DIM, 0.6), "left", 21, 240 * u)
    image(g.star and "Textures/ui_star_on.png" or "Textures/ui_star_off.png", w - m - 82 * u, m + 18 * u, 60 * u, 60 * u, 21, 1)
    if SET:get("mute") then text("MUTED  ·  M", w - m - 22 * u, m + 116 * u, 14 * u, BRASS, "right", 21, 210 * u) end
    -- the cue, bottom centre
    local cue = "Drag the lantern or a prop   ·   arrows: lantern   ·   Tab: pick a prop   ·   Esc pause"
    if G.sel_prop then
        local mv = D.PROP_MOVE[G.sel_prop]
        cue = G.sel_prop:upper() .. " picked   ·   " .. (mv == "z" and "W S: up and down" or "A D: along its track") .. "   ·   Tab: next   ·   Esc pause"
    end
    local cw = 1100 * u
    rect((w - cw) / 2, h - 80 * u, cw, 48 * u, { 0.05, 0.01, 0.015, 0.5 }, 20, 12 * u)
    text(cue, w / 2, h - 56 * u, 19 * u, CREAM, "center", 21, cw - 30 * u)
end

-- Keyboard play: arrows move the lantern, Tab picks the next movable prop, A/D slide it, W/S lift the balloon.
local function keyboard_play(dt)
    if pressed("Tab") then
        local names = {}
        for name, p in pairs(P.L.props) do if p.move ~= "auto" then names[#names + 1] = name end end
        table.sort(names)
        local k = 0
        for i, n in ipairs(names) do if n == G.sel_prop then k = i end end
        G.sel_prop = names[k % max(1, #names) + 1]
        sound("click", 0.05)
    end
    local st = W.state
    local lx, ly = 0, 0
    if keydown("Left") then lx = lx - 1 end
    if keydown("Right") then lx = lx + 1 end
    if keydown("Up") then ly = ly + 1 end
    if keydown("Down") then ly = ly - 1 end
    local moved = false
    if lx ~= 0 or ly ~= 0 then
        st.lantern[1] = max(D.LANTERN_X[1], min(D.LANTERN_X[2], st.lantern[1] + lx * 0.9 * dt))
        st.lantern[2] = max(D.LANTERN_Y[1], min(D.LANTERN_Y[2], st.lantern[2] + ly * 0.35 * dt))
        moved = true
    end
    local name = G.sel_prop
    if name and P.L.props[name] then
        local mv = D.PROP_MOVE[name]
        local d = 0
        if mv == "z" then
            if keydown("W") then d = d + 1 end
            if keydown("S") then d = d - 1 end
            if d ~= 0 then
                local r = D.PROPS[name].z
                st[name] = max(r[1], min(r[2], (st[name] or 0) + d * 0.5 * dt)); moved = true
            end
        else
            if keydown("A") then d = d - 1 end
            if keydown("D") then d = d + 1 end
            if d ~= 0 then
                local r = D.PROPS[name].x
                st[name] = max(r[1], min(r[2], st[name] + d * 0.6 * dt)); moved = true
            end
        end
    end
    if moved then W.apply(); sound("drag", 0.45) end
end

------------------------------------------------------------------ the frame
SET:apply()
layout()
-- G.update(dt) -> true while a level is being played (no card, no pause, no menu): the caller runs drags and rules
function G.update(raw)
    if layout() then for id in pairs(widgets) do widgets[id] = true; hide(id) end end
    G.fdt, G.t = raw, G.t + raw
    clock = clock + raw
    G.card_t = G.card_t + raw
    G.text_log = {}
    if G.manual then for id in pairs(widgets) do hide(id) end; return S.mode == "play" end
    ambience(true)
    local esc = pressed("Escape")
    if pressed("M") then SET:toggle_mute() end
    local live = false
    local menu = SET:update(raw)
    G.hold = false
    if menu then
        flush_keys()
    elseif G.howto then
        howto_controls(raw, esc)
    elseif G.pause then
        pause_controls(raw, esc)
    elseif G.mode == "title" then
        if esc then sound("click"); open_pause() else title_controls() end
    elseif G.mode == "select" then
        select_controls(esc)
    elseif G.mode == "play" and G.intro then
        if esc then sound("click"); open_pause() else intro_controls(raw) end
        G.hold = true
    elseif G.mode == "play" then
        if esc then sound("click"); open_pause()
        elseif pressed("R") and not G.tut then sound("click"); G.start_level(G.level, nil, true)
        else
            live = true
            keyboard_play(raw)
            if G.tut then tut_controls(raw); G.hold = G.tut ~= nil end
        end
    elseif G.mode == "won" or G.mode == "lost" then
        end_controls(esc)
    end
    -- draw
    if not menu then
        local a = min(1, G.card_t * 4)
        if G.mode == "title" then if not G.pause and not G.howto then draw_title(a) end
        elseif G.mode == "select" then draw_select(a)
        elseif G.mode == "play" then
            if not G.howto then draw_hud() end
            if G.intro and not G.pause then draw_intro() else hide("in_ok") end
            if G.tut and not G.pause then draw_tut() else for _, id in ipairs(TUT_IDS) do hide(id) end end
        elseif G.mode == "won" or G.mode == "lost" then draw_hud(); draw_end(a) end
        draw_pause()
        if G.howto then draw_howto() else for _, id in ipairs(HOWTO_IDS) do hide(id) end end
    end
    flush_pools()
    return live
end
-- After the rules stepped: sounds from its events, and the end of the level.
function G.after_step()
    local g = S.game
    if not g or G.mode ~= "play" then return end
    on_events(g)
    if (g.won or g.dead) and not G.result and g.t_end and S.clock - g.t_end > (g.won and 1.2 or 1.0) then finish(g) end
end
G.SET = SET
return G
end
