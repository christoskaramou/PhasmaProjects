-- Undertow game flow: the title card (PLAY, HOW TO PLAY, GLASS, SETTINGS, QUIT), the HOW TO PLAY card, a guided first run, over a bot playing the harbour behind it, a run
-- (hold Space or the left mouse button to hook the lamp ahead and swing, let go to fly), the HUD, the Esc pause card,
-- the game-over card (RETRY, BACK TO MENU), the shared settings menu, the mute key, the save file and the sounds.
-- U is _G.undertow (undertow.lua): U.play(seed, use_bot) starts a rules run, U.play_frame(raw) advances and poses it.
return function(U, SettingsMenu)
local G = {}
local D, W, Rules, Bot = U.D, U.W, U.Rules, U.Bot
local S = U.S
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local SCREEN = "undertow"

------------------------------------------------------------------ palette (dusk harbour: tarred wood, brass, green glass)
local CLEAR = { 0, 0, 0, 0 }
local CREAM = { 0.96, 0.92, 0.82, 1 }
local DIM = { 0.80, 0.78, 0.70, 0.85 }
local BRASS = { 0.90, 0.68, 0.38, 1 }
local GOLD = { 1.0, 0.80, 0.45, 1 }
local GLASS = { 0.58, 1.0, 0.68, 1 }
local BAD = { 0.95, 0.48, 0.36, 1 }
local PANEL = { 0.035, 0.05, 0.055, 0.92 }
local BTN = { 0.07, 0.10, 0.10, 1 }
local BTN_HI = { 0.12, 0.17, 0.15, 1 }
local RIM = { 0.78, 0.58, 0.32, 0.85 }

------------------------------------------------------------------ save (Save/undertow.txt: best, runs, glass)
local SAVE = "Save/undertow.txt"
local save = { best = 0, runs = 0, glass = "green", tut = 0 }      -- tut 1: the guided first run was finished or skipped
do
    local ok, txt = pcall(fs.read, SAVE)
    if ok and txt then
        for k, v in tostring(txt):gmatch("([%w_]+)%s*=%s*([%w_.]+)") do
            if k == "glass" then save.glass = v elseif save[k] ~= nil then save[k] = tonumber(v) or save[k] end
        end
    end
end
local function write_save()
    pcall(fs.write, SAVE, string.format("best=%d\nruns=%d\nglass=%s\ntut=%d\n", save.best, save.runs, save.glass, save.tut))
end
G.save = save
G.write_save = write_save

-- Glass colours unlock by best score (one run's score: distance + lamps + clean releases).
G.UNLOCKS = { { "green", 0 }, { "amber", 400 }, { "cobalt", 900 }, { "rose", 1600 } }
local function unlocked(name)
    for _, u in ipairs(G.UNLOCKS) do if u[1] == name then return save.best >= u[2] end end
    return false
end
local function next_unlock()
    for _, u in ipairs(G.UNLOCKS) do if save.best < u[2] then return u end end
end
if not unlocked(save.glass) then save.glass = "green" end
W.set_glass(save.glass)

------------------------------------------------------------------ sounds (Assets/Audio, CC0 recordings: see CREDITS.txt)
local LEN = { catch = 0.6, release = 0.45, skim = 0.7, crash = 1.6, sink = 1.2, click = 0.12, unlock = 1.0 }
local MAX_VOICES, voices, clock, last = 14, {}, 0, {}
local function sound(name, gap)
    if not (audio and audio.play) then return end
    if last[name] and clock - last[name] < (gap or 0.08) then return end
    for i = #voices, 1, -1 do if voices[i] <= clock then table.remove(voices, i) end end
    if #voices >= MAX_VOICES then return end
    voices[#voices + 1] = clock + (LEN[name] or 1)
    last[name] = clock
    G.sounds_played = (G.sounds_played or 0) + 1
    pcall(audio.play, name .. ".wav")
end
G.sound = sound
local ambience_on = false
local function ambience(on)
    if on == ambience_on or not audio then return end
    ambience_on = on
    if on then pcall(audio.play_music, "ambience.wav") else pcall(audio.stop_music) end
end

local SET = SettingsMenu.new({ title = "SETTINGS", subtitle = "UNDERTOW", click = function() sound("click") end,
    theme = { accent = { 0.86, 0.64, 0.36, 1 }, accent2 = { 0.62, 1.0, 0.70, 1 }, text = CREAM, selected_text = { 1, 0.97, 0.88, 1 } },
    on_graphics = function() pcall(settings.set, "taa", true); pcall(settings.set, "fxaa", false) end })
G.settings = SET

------------------------------------------------------------------ widgets (Topple's pattern: pooled runtime_ui quads)
local widgets, pools, L, u = {}, {}, {}, 1
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
-- Text of em size px centred on y; a soft dark copy under it for legibility over the sea.
local MIN_PX = 12          -- no text smaller than this many pixels (at 1280x720 u = 0.67, so 15 * u alone is 10 px)
local function text(s, x, y, px, color, align, z, w)
    px = max(px, MIN_PX)
    local h = px * 1.6
    local bw = w or max(60, #s * px * 0.75)
    local bx = align == "left" and x or (align == "right" and x - bw or x - bw / 2)
    local a = color[4] or 1
    quad(pid("t"), { style = "text", label = s, x = bx + px * 0.05, y = y - h / 2 + px * 0.07, width = bw, height = h, z = (z or 40) - 0.5,
        font_scale = px / 16, text_color = { 0.0, 0.01, 0.01, 0.6 * a }, align_h = align or "center", align_v = "middle" })
    quad(pid("t"), { style = "text", label = s, x = bx, y = y - h / 2, width = bw, height = h, z = z or 40,
        font_scale = px / 16, text_color = color, align_h = align or "center", align_v = "middle" })
end
local function panel(x, y, w, h, z, fill, rim, r)
    r = (r or 14) * u
    quad(pid("p"), { style = "text", label = "", x = x, y = y, width = w, height = h, z = z, fill = fill or PANEL, border = rim or RIM, corner_radius = r })
    quad(pid("p"), { style = "text", label = "", x = x + 2, y = y + 2, width = w - 4, height = h - 4, z = z, fill = CLEAR, border = col4(rim or RIM, 0.4), corner_radius = max(0, r - 2) })
end
local HV = {}
local function hv(id)
    local v = HV[id] or 0
    v = v + ((hovered(id) and 1 or 0) - v) * min(1, (G.fdt or 1 / 60) * 14)
    HV[id] = v
    return v
end
local function ease_back(t) t = max(0, min(1, t)); local c = 1.7; return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2 end
-- A button: id, label, key hint, x, y, w, h, z; returns nothing (clicked(id) reads it next frame).
local function button(id, label, key, x, y, w, h, z, a, colour)
    local hvv = hv(id)
    y = y - hvv * 3 * u
    if hvv > 0.02 then rect(x - 5 * u, y - 5 * u, w + 10 * u, h + 10 * u, CLEAR, z, 14 * u, col4(GOLD, 0.35 * hvv * a)) end
    panel(x, y, w, h, z + 1, col4(hvv > 0.5 and BTN_HI or BTN, a), col4(hvv > 0.5 and GOLD or RIM, a), 10)
    local px = min(26 * u, h * 0.42)
    text(label, x + w / 2, y + h / 2, px, col4(colour or CREAM, a), "center", z + 2, w - 130 * u)
    if key then text(key, x + w - 16 * u, y + h / 2, px * 0.6, col4(BRASS, 0.9 * a), "right", z + 2, 110 * u) end
    catcher(id, x, y, w, h, z + 4)
end
local function layout()
    local ok, surf = pcall(runtime_ui.get_surface_size)
    local w, h = ok and surf and surf.width or 1280, ok and surf and surf.height or 720
    if w <= 0 or h <= 0 then w, h = 1280, 720 end
    local changed = L.w ~= w or L.h ~= h
    L.w, L.h = w, h
    u = min(w / 1920, h / 1080)
    return changed
end

------------------------------------------------------------------ input (key edges; hold = Space or the left mouse button)
local keys = {}
local function keydown(k)
    local f = input and (input.is_key_down_raw or input.is_key_down)
    if not f then return false end
    local ok, r = pcall(f, k); return ok and r or false
end
local function pressed(name)
    local down = keydown(name)
    local was = keys[name]
    keys[name] = down
    return down and not was
end
local KEYS = { "Escape", "Return", "Space", "M", "Q", "R", "G", "S", "Backspace", "H", "Tab" }
local function flush_keys() for _, k in ipairs(KEYS) do pressed(k) end end
-- The hold input. G.force_hold (console/testing: true or false) replaces the keys and mouse when set.
local function mouse_down()
    if not input or not input.is_left_mouse_down then return false end
    local ok, r = pcall(input.is_left_mouse_down); return ok and r or false
end
function G.hold_input()
    if G.force_hold ~= nil then return G.force_hold end
    return keydown("Space") or mouse_down()
end

------------------------------------------------------------------ flow
-- G.mode: "title" (the bot plays behind the card) | "run" (the player) | "over" (the card after a run ended)
G.mode, G.card_t, G.t = "title", 0, 0
local attract_seed = 11
local function start_attract()
    U.play(attract_seed, true)
    attract_seed = attract_seed % 97 + 7
    S.input = nil
    G.attract_dead_t = nil
end
local function new_seed()
    G.seed_n = (G.seed_n or 0) + 1
    return (save.runs * 7919 + floor(G.t * 1000) + G.seed_n * 104729) % 99991 + 1
end
-- G.start_level (console/testing): the next runs start at, and hold, that difficulty step. G.auto (console/testing):
-- the bot decides the hold each rules step through the game's own input function (instead of the keys and mouse).
function G.start_run(seed)
    seed = seed or new_seed()
    -- the guided first run (until it is finished or skipped once: save.tut): a gentle first stretch of close buoys
    G.tut = (save.tut == 0 and not G.auto) and { step = 1, t = 0, seen = {} } or nil
    U.play(seed, false, G.start_level, G.tut and { gentle = G.GENTLE } or nil)
    G.mode, G.card_t, G.seed = "run", 0, seed
    -- The run waits on its first swing until a fresh press (a click on PLAY must not count as the first hold).
    G.waiting, G.armed = true, not G.hold_input()
    G.ev_n = S.rs.nev or 0
    G.pops, G.new_best, G.unlocked_now = {}, false, nil
    G.best0 = save.best
    if G.auto then G.auto = Bot.new() end
    G.held_after_release = true
    S.input = function(st)
        if G.waiting then return true end
        local h
        if G.auto then h = Bot.input(G.auto, st) else h = G.hold_input() end
        if h and not st.hook then G.held_after_release = true end
        return h
    end
    G.end_shown = false
    flush_keys()
    return "run seed " .. seed
end
local function to_title()
    G.mode, G.card_t = "title", 0
    G.pause = nil
    start_attract()
    flush_keys()
end
G.to_title = to_title
local function quit_game() sound("click"); pcall(engine.quit) end
local function cycle_glass()
    local names = {}
    for _, g in ipairs(G.UNLOCKS) do if unlocked(g[1]) then names[#names + 1] = g[1] end end
    local k = 1
    for i, n in ipairs(names) do if n == save.glass then k = i end end
    save.glass = names[k % #names + 1]
    W.set_glass(save.glass)
    write_save()
    sound("click")
end
G.cycle_glass = cycle_glass

-- The run ended: count it, keep the best, unlock what it reached.
local function finish_run(rs)
    save.runs = save.runs + 1
    local sc = rs.score or 0
    if sc > save.best then
        local before = save.best
        save.best = sc
        G.new_best = true
        for _, g in ipairs(G.UNLOCKS) do
            if before < g[2] and sc >= g[2] then G.unlocked_now = g[1] end
        end
    end
    write_save()
end

local POP_TEXT = { hook = "+%d LAMP", clean = "+%d CLEAN RELEASE", skip = "SKIP!" }
local function on_events(rs, live)
    local n0 = G.ev_n or 0
    for _, e in ipairs(rs.events) do
        if e.n and e.n > n0 then
            if live then
                if e.kind == "hook" then sound("catch")
                elseif e.kind == "release" then sound("release"); G.held_after_release = false
                elseif e.kind == "skip" or e.kind == "skim" then sound("skim", 0.15)
                elseif e.kind == "hit" or e.kind == "tangle" then sound("crash")
                elseif e.kind == "sink" then sound("sink") end
                local fmt = POP_TEXT[e.kind]
                if fmt and G.mode == "run" then
                    local pts = e.kind == "hook" and D.RULES.LAMP_PTS or D.RULES.CLEAN_PTS
                    G.pops[#G.pops + 1] = { s = string.format(fmt, pts), t = 0, col = e.kind == "skip" and GLASS or GOLD }
                end
            end
            n0 = e.n
        end
    end
    G.ev_n = n0
end

------------------------------------------------------------------ pause
local PAUSE_IDS = { "pz_block", "pz_resume", "pz_howto", "pz_settings", "pz_menu", "pz_quit" }
local function open_pause() G.pause = { t = 0 }; flush_keys() end
local function close_pause() G.pause = nil; for _, id in ipairs(PAUSE_IDS) do hide(id) end; flush_keys() end
G.open_pause, G.close_pause = open_pause, close_pause
local function pause_controls(dt, esc)
    local P = G.pause
    P.t = P.t + dt
    if P.t < 0.12 then return end
    if esc or clicked("pz_resume") then sound("click"); close_pause()
    elseif pressed("Q") or clicked("pz_quit") then close_pause(); quit_game()
    elseif clicked("pz_settings") then sound("click"); close_pause(); SET:open(function() open_pause() end)
    elseif pressed("H") or clicked("pz_howto") then sound("click"); close_pause(); G.open_howto("pause")
    elseif G.mode ~= "title" and clicked("pz_menu") then sound("click"); close_pause(); to_title() end
end
local function draw_pause()
    local P = G.pause
    if not P or SET:is_open() then for _, id in ipairs(PAUSE_IDS) do hide(id) end; return end
    local w, h = L.w, L.h
    local a = min(1, P.t * 6)
    rect(0, 0, w, h, { 0.0, 0.01, 0.015, 0.5 * a }, 150)
    catcher("pz_block", 0, 0, w, h, 151)
    local rows = { { "pz_resume", "RESUME", "Esc" }, { "pz_howto", "HOW TO PLAY", "H" }, { "pz_settings", "SETTINGS" } }
    if G.mode ~= "title" then rows[#rows + 1] = { "pz_menu", "BACK TO MENU" } else hide("pz_menu") end
    rows[#rows + 1] = { "pz_quit", "QUIT GAME", "Q" }
    local bw, bh, gap = 400 * u, 64 * u, 14 * u
    local cw = bw + 80 * u
    local ch = 150 * u + #rows * (bh + gap) + 16 * u
    local x, y = (w - cw) / 2, (h - ch) / 2 + (1 - ease_back(P.t * 3)) * 30 * u
    panel(x, y, cw, ch, 152, col4(PANEL, a), col4(RIM, a), 18)
    text("PAUSED", x + cw / 2, y + 56 * u, 48 * u, col4(CREAM, a), "center", 153, cw)
    text(G.mode == "title" and "UNDERTOW" or ("Score " .. tostring(S.rs and S.rs.score or 0) .. "   ·   the harbour waits"), x + cw / 2, y + 104 * u,
        18 * u, col4(GOLD, a), "center", 153, cw - 40 * u)
    for i, r in ipairs(rows) do
        local by = y + 150 * u + (i - 1) * (bh + gap)
        button(r[1], r[2], r[3], x + 40 * u, by, bw, bh, 154, a, r[1] == "pz_quit" and BAD or CREAM)
    end
end

------------------------------------------------------------------ title
local TITLE_IDS = { "t_play", "t_howto", "t_glass", "t_settings", "t_quit" }
local function draw_title(a)
    local w, h = L.w, L.h
    local cw, ch = 1060 * u, 900 * u      -- (760 hid the best-score line under QUIT; 900 for the fifth button)
    local x, y = (w - cw) / 2, (h - ch) / 2 + (1 - ease_back(G.card_t * 2.5)) * 30 * u
    panel(x, y, cw, ch, 81, col4(PANEL, a * 0.95), col4(RIM, a), 20)
    local cx = x + cw / 2
    text("UNDERTOW", cx, y + 78 * u, 84 * u, col4(CREAM, a), "center", 82, cw)
    text("A glass float on a chain, across a stormy harbour at dusk.", cx, y + 142 * u, 22 * u, col4(DIM, a), "center", 82, cw - 60 * u)
    -- the controls, spelled out
    local bx, by, bw, bh = x + 50 * u, y + 180 * u, cw - 100 * u, 214 * u
    rect(bx, by, bw, bh, col4({ 0.0, 0.02, 0.02, 0.55 }, a), 82, 12 * u, col4(RIM, 0.35 * a))
    local rows = {
        { "HOLD  Space or left mouse", "grab the nearest lamp hook ahead and swing" },
        { "LET GO", "fly off with the swing's speed" },
        { "SKIM", "meet the water flat and fast to skip; steep or slow sinks" },
        { "AVOID", "boats, rocks, the pier and buoy arms break the glass" },
    }
    for i, r in ipairs(rows) do
        local ry = by + 34 * u + (i - 1) * 49 * u
        text(r[1], bx + 30 * u, ry, 21 * u, col4(i == 1 and GLASS or GOLD, a), "left", 83, 330 * u)
        text(r[2], bx + 360 * u, ry, 18 * u, col4(CREAM, a), "left", 83, bw - 380 * u)
    end
    -- buttons
    local nb = 5
    local bw2, bh2, gap = 380 * u, 60 * u, 10 * u
    local x0 = cx - bw2 / 2
    local y0 = by + bh + 26 * u
    button("t_play", "PLAY", "Enter", x0, y0, bw2, bh2, 84, a, GLASS)
    button("t_howto", "HOW TO PLAY", "H", x0, y0 + (bh2 + gap), bw2, bh2, 84, a, GOLD)
    local g = save.glass
    button("t_glass", "GLASS: " .. g:upper(), "G", x0, y0 + 2 * (bh2 + gap), bw2, bh2, 84, a)
    button("t_settings", "SETTINGS", "S", x0, y0 + 3 * (bh2 + gap), bw2, bh2, 84, a)
    button("t_quit", "QUIT", "Q", x0, y0 + 4 * (bh2 + gap), bw2, bh2, 84, a, BAD)
    local nu = next_unlock()
    local line = "Best " .. save.best .. (nu and ("   ·   " .. nu[1]:upper() .. " glass at best " .. nu[2]) or "   ·   every glass unlocked")
    text(line, cx, y + ch - 70 * u, 20 * u, col4(GOLD, a), "center", 82, cw - 40 * u)
    text("H how to play   ·   Esc pause   ·   M mute", cx, y + ch - 32 * u, 17 * u, col4(DIM, 0.9 * a), "center", 82, cw - 40 * u)
    return nb
end
local function title_controls()
    if G.card_t < 0.25 then return end
    if pressed("Return") or clicked("t_play") then sound("click"); G.start_run()
    elseif pressed("H") or clicked("t_howto") then sound("click"); G.open_howto("title")
    elseif pressed("G") or clicked("t_glass") then cycle_glass()
    elseif pressed("S") or clicked("t_settings") then sound("click"); SET:open(function() flush_keys() end)
    elseif pressed("Q") or clicked("t_quit") then quit_game() end
end

------------------------------------------------------------------ game over
local OVER_IDS = { "o_retry", "o_menu" }
local HIT_WORDS = { buoy_red = "on a buoy's arm", buoy_white = "on a buoy's arm", boat = "on a moored boat's hull", pier = "on the pier",
    bw_gap = "on the breakwater rocks", bw = "on the breakwater rocks" }
local function end_words(rs)
    if rs.cause == "sink" then
        return "LOST TO THE UNDERTOW", "The float hit the water too steep or too slow, and went under."
    elseif rs.cause == "tangle" then
        return "THE CHAIN SNAGGED", "It caught " .. (HIT_WORDS[rs.what] or "on the harbour") .. " and pulled the glass in."
    end
    return "THE GLASS SHATTERED", "It broke " .. (HIT_WORDS[rs.what] or "on the harbour") .. "."
end
G.end_words = end_words
local function draw_over(a)
    local rs = S.rs
    local w, h = L.w, L.h
    local cw, ch = 940 * u, 630 * u
    local x, y = (w - cw) / 2, (h - ch) / 2 + (1 - ease_back(G.card_t * 2.5)) * 30 * u
    panel(x, y, cw, ch, 81, col4(PANEL, a * 0.95), col4(RIM, a), 20)
    local cx = x + cw / 2
    local head, why = end_words(rs)
    text(head, cx, y + 66 * u, 50 * u, col4(rs.cause == "sink" and CREAM or BAD, a), "center", 82, cw - 40 * u)
    text(why, cx, y + 116 * u, 19 * u, col4(DIM, a), "center", 82, cw - 60 * u)
    G.last_hint = G.hint(rs, G.held_after_release)
    text("TIP   " .. G.last_hint, cx, y + 156 * u, 19 * u, col4(GLASS, a), "center", 82, cw - 60 * u)
    text(tostring(rs.score or 0), cx, y + 250 * u, 76 * u, col4(GOLD, a), "center", 82, cw)
    text(G.new_best and "NEW BEST!" or ("best " .. save.best), cx, y + 308 * u, 20 * u, col4(G.new_best and GLASS or BRASS, a), "center", 82, cw)
    local stats = string.format("%d m   ·   %d lamps lit   ·   %d clean releases   ·   %d skips", floor(rs.dist), rs.lamps, rs.clean, rs.skips)
    text(stats, cx, y + 350 * u, 19 * u, col4(CREAM, a), "center", 82, cw - 40 * u)
    if G.unlocked_now then
        text(G.unlocked_now:upper() .. " GLASS UNLOCKED   ·   choose it on the title card", cx, y + 390 * u, 19 * u, col4(GLASS, a), "center", 82, cw - 40 * u)
    end
    local bw, bh, gap = 370 * u, 66 * u, 24 * u      -- (330 wrapped BACK TO MENU onto two lines at 1280x720)
    local by = y + ch - bh - 44 * u
    button("o_retry", "RETRY", "Enter", cx - bw - gap / 2, by, bw, bh, 84, a, GLASS)
    button("o_menu", "BACK TO MENU", "Esc", cx + gap / 2, by, bw, bh, 84, a)
end
local function over_controls(esc)
    if G.card_t < 0.35 then return end
    if pressed("Return") or pressed("R") or clicked("o_retry") then sound("click"); G.start_run()
    elseif esc or pressed("Backspace") or clicked("o_menu") then sound("click"); to_title() end
end

------------------------------------------------------------------ HUD
local function draw_hud()
    local rs = S.rs
    local w, h = L.w, L.h
    local m = 28 * u
    -- score (top left)
    panel(m, m, 330 * u, 118 * u, 20, { 0.02, 0.035, 0.04, 0.62 }, { 0.78, 0.58, 0.32, 0.5 }, 12)
    text("SCORE", m + 22 * u, m + 26 * u, 15 * u, col4(BRASS, 0.9), "left", 21, 120 * u)
    text(tostring(rs.score or 0), m + 22 * u, m + 64 * u, 46 * u, CREAM, "left", 21, 290 * u)
    text(string.format("%d m   ·   %d lamps", floor(rs.dist), rs.lamps), m + 22 * u, m + 100 * u, 15 * u, DIM, "left", 21, 290 * u)
    -- best and level (top right)
    local lv = 1
    if U.Course.level_at then lv = U.Course.level_at(rs.course, rs.x) + 1 end
    panel(w - m - 250 * u, m, 250 * u, 92 * u, 20, { 0.02, 0.035, 0.04, 0.62 }, { 0.78, 0.58, 0.32, 0.5 }, 12)
    text("BEST " .. max(save.best, rs.score or 0), w - m - 22 * u, m + 32 * u, 24 * u, GOLD, "right", 21, 210 * u)
    text("HARBOUR " .. lv .. " of " .. D.RULES.LEVELS, w - m - 22 * u, m + 66 * u, 15 * u, DIM, "right", 21, 210 * u)
    if SET:get("mute") then text("MUTED  ·  M", w - m - 22 * u, m + 112 * u, 14 * u, BRASS, "right", 21, 210 * u) end
    -- pops under the score
    for i = #G.pops, 1, -1 do
        local p = G.pops[i]
        p.t = p.t + (G.fdt or 0)
        if p.t > 1.2 then table.remove(G.pops, i) end
    end
    for i, p in ipairs(G.pops) do
        local a = min(1, (1.2 - p.t) * 3)
        text(p.s, m + 22 * u, m + 150 * u + (i - 1) * 30 * u - p.t * 12 * u, 20 * u, col4(p.col, a), "left", 22, 320 * u)
    end
    -- the control cue (bottom centre): what the input does right now
    if rs.mode ~= "dead" then
        local cue, col
        if G.waiting then cue, col = "HOLD Space or left mouse to take the swing   ·   then LET GO to fly", GLASS
        elseif rs.hook then cue, col = "LET GO to fly", CREAM
        else
            local it = Rules.find_hook(rs)
            if it then cue, col = "HOLD to hook the lamp in reach", GLASS else cue, col = "flying   ·   hold early to catch the next hook", DIM end
        end
        local cw = 760 * u
        rect((w - cw) / 2, h - 86 * u, cw, 50 * u, { 0.02, 0.035, 0.04, 0.5 }, 20, 12 * u)
        text(cue, w / 2, h - 61 * u, 21 * u, col, "center", 21, cw - 30 * u)
    end
end


------------------------------------------------------------------ screen projection (for markers on the 3D scene)
-- World (Blender axes) -> window pixels, from the camera the world places (x = S.cx, y = CAM.y, z = S.cz, yaw, pitch,
-- horizontal fov). nil behind the camera. (TAA jitter is sub-pixel; markers are big rings.)
function G.project(x, y, z)
    local C = D.CAM
    local cy, sy = math.cos(math.rad(C.yaw)), math.sin(math.rad(C.yaw))
    local cp, sp = math.cos(math.rad(C.pitch)), math.sin(math.rad(C.pitch))
    local dx, dy, dz = x - (S.cx or 0), y - C.y, z - (S.cz or C.z)
    local depth = dx * sy * cp + dy * cy * cp + dz * sp
    if depth < 0.1 then return nil end
    local right = dx * cy - dy * sy
    local up = -dx * sy * sp - dy * cy * sp + dz * cp
    local f = (L.w / 2) / math.tan(math.rad(C.fovx / 2))
    return L.w / 2 + right / depth * f, L.h / 2 - up / depth * f
end

------------------------------------------------------------------ HOW TO PLAY card (title: H / button; pause: H / button)
G.GENTLE = 80          -- the guided first run: close buoys and no hazards for its first 80 units
local HOWTO_IDS = { "h_block", "h_back" }
local HOWTO_ROWS = {
    { "GOAL", "Fly the glowing glass float from lamp hook to lamp hook along the harbour, as far as you can." },
    { "HOLD", "Hold Space or the left mouse button: the chain grabs the nearest hook ahead and you swing." },
    { "LET GO", "Let go near the top of the forward swing to fly. Hold again early to catch the next hook." },
    { "SKIM", "Touch the water flat and fast and you skip off it. Hit it steep or slow and the glass sinks." },
    { "DANGER", "Boats, breakwater rocks, the pier and buoy arms break the glass. Falling with no hook sinks it." },
    { "SCORE", "Metres flown, +10 for every lamp you light, +25 for a clean release (next hook, no water)." },
    { "HARBOUR", "Every 300 m the harbour gets harder: wider gaps, more boats and rocks, faster swell." },
    { "GLASS", "Your best score unlocks glass colours: amber 400, cobalt 900, rose 1600. Pick it on the title." },
    { "KEYS", "Esc pause   ·   M mute   ·   H this card   ·   Tab skips the first-run guide" },
}
G.HOWTO_ROWS = HOWTO_ROWS
function G.open_howto(from)
    G.howto = { t = 0, from = from }
    flush_keys()
end
local function close_howto()
    local from = G.howto and G.howto.from
    G.howto = nil
    for _, id in ipairs(HOWTO_IDS) do hide(id) end
    flush_keys()
    if from == "pause" then G.open_pause() end
end
local function howto_controls(esc)
    G.howto.t = G.howto.t + (G.fdt or 0)
    if G.howto.t < 0.15 then return end
    if esc or pressed("Backspace") or pressed("H") or clicked("h_back") then sound("click"); close_howto() end
end
local function dot(x, y, r, col, z) rect(x - r, y - r, 2 * r, 2 * r, col, z, r) end
-- one small picture: a hook on its arm, the chain, the float and a dotted path
local function diagram(x, y, w, h, kind, a, z)
    rect(x, y, w, h, col4({ 0.0, 0.02, 0.03, 0.6 }, a), z, 10 * u, col4(RIM, 0.35 * a))
    local sea = y + h - 26 * u
    rect(x + 6 * u, sea, w - 12 * u, 3 * u, col4({ 0.35, 0.55, 0.5, 0.8 }, a), z + 1)
    local function hook(hx, hy)
        rect(hx - 50 * u, hy - 8 * u, 50 * u, 5 * u, col4(BRASS, 0.8 * a), z + 1, 2 * u)       -- the lamp arm
        dot(hx, hy, 6 * u, col4(GOLD, a), z + 2)
    end
    local function chain(ax, ay, bx, by)
        for i = 1, 6 do local t = i / 7; dot(ax + (bx - ax) * t, ay + (by - ay) * t, 2.5 * u, col4(CREAM, 0.8 * a), z + 2) end
    end
    local function float(fx, fy) dot(fx, fy, 14 * u, col4(GLASS, a), z + 3); dot(fx, fy, 6 * u, col4({ 1, 1, 1, 1 }, a), z + 4) end
    if kind == 1 then          -- hold: swinging under the hook
        local hx, hy = x + w * 0.45, y + 34 * u
        hook(hx, hy)
        for i = -3, 3 do local an = i * 0.22; dot(hx + math.sin(an) * 82 * u, hy + math.cos(an) * 82 * u, 2 * u, col4(DIM, 0.6 * a), z + 1) end
        chain(hx, hy, hx + math.sin(0.55) * 82 * u, hy + math.cos(0.55) * 82 * u)
        float(hx + math.sin(0.55) * 82 * u, hy + math.cos(0.55) * 82 * u)
    elseif kind == 2 then      -- let go: flying off the top of the swing
        local hx, hy = x + w * 0.22, y + 34 * u
        hook(hx, hy)
        for i = 0, 7 do local t = i / 7; dot(hx + 60 * u + t * (w * 0.62), hy + 50 * u - math.sin(t * math.pi) * 36 * u + t * 10 * u, 2.5 * u, col4(GLASS, 0.7 * a), z + 1) end
        float(hx + 60 * u, hy + 50 * u)
    else                       -- hold again: caught by the next hook
        local hx, hy = x + w * 0.62, y + 34 * u
        hook(hx, hy)
        for i = 0, 5 do local t = i / 5; dot(x + 24 * u + t * (hx - x - 70 * u), y + 70 * u - math.sin(t * math.pi) * 22 * u + t * 20 * u, 2.5 * u, col4(GLASS, 0.5 * a), z + 1) end
        chain(hx, hy, hx - 40 * u, hy + 70 * u)
        float(hx - 40 * u, hy + 70 * u)
    end
end
local function draw_howto(a)
    local w, h = L.w, L.h
    local cw, ch = 1500 * u, 980 * u
    local x, y = (w - cw) / 2, (h - ch) / 2
    rect(0, 0, w, h, { 0.0, 0.01, 0.015, 0.55 * a }, 199)
    catcher("h_block", 0, 0, w, h, 200)
    panel(x, y, cw, ch, 201, col4(PANEL, a), col4(RIM, a), 20)
    local cx = x + cw / 2
    text("HOW TO PLAY", cx, y + 52 * u, 46 * u, col4(CREAM, a), "center", 202, cw)
    -- three pictures: hold, let go, hold again
    local pw, ph, pg = 440 * u, 170 * u, 30 * u
    local px0 = cx - (3 * pw + 2 * pg) / 2
    local caps = { "1  HOLD: swing on the hook", "2  LET GO near the top: fly", "3  HOLD again: catch the next" }
    for i = 1, 3 do
        local px = px0 + (i - 1) * (pw + pg)
        diagram(px, y + 96 * u, pw, ph, i, a, 202)
        text(caps[i], px + pw / 2, y + 96 * u + ph + 22 * u, 18 * u, col4(i == 2 and GLASS or GOLD, a), "center", 203, pw)
    end
    local ry0 = y + 330 * u
    for i, r in ipairs(HOWTO_ROWS) do
        local ry = ry0 + (i - 1) * 54 * u
        text(r[1], x + 60 * u, ry, 21 * u, col4(i <= 3 and GLASS or GOLD, a), "left", 203, 190 * u)
        text(r[2], x + 260 * u, ry, 19 * u, col4(CREAM, a), "left", 203, cw - 300 * u)
    end
    button("h_back", "BACK", "Esc", cx - 180 * u, y + ch - 100 * u, 360 * u, 62 * u, 204, a)
end

------------------------------------------------------------------ the guided first run (shown until finished or skipped)
local TUT_IDS = { "tut_skip" }
local TUT = {
    { "HOLD Space (or the left mouse button) to start swinging", "Keep holding: the float swings on its chain under the lamp hook." },
    { "Now LET GO near the top of the forward swing", "You fly off with the swing's speed. Let go when it says NOW." },
    { "HOLD again to catch the marked hook", "Hold early: the chain grabs the nearest hook ahead within reach." },
    { "That's the game: swing, let go, catch", "Light lamps, skip flat and fast off the water, keep clear of boats and rocks." },
}
G.TUT = TUT
local function finish_tut()
    save.tut = 1
    write_save()
    G.tut = nil
    for _, id in ipairs(TUT_IDS) do hide(id) end
end
G.finish_tut = finish_tut
-- the next hook the player should catch: the one in reach, else the first ahead
local function next_hook(rs)
    local it = Rules.find_hook(rs)
    if it then return it, true end
    for _, c in ipairs(rs.course.plane) do
        if Rules.has_hook(c) and c.x > rs.x and c.x > (rs.last_x or -1e9) then return c, false end
    end
end
local function tut_update(rs, dt)
    local T = G.tut
    T.t = T.t + dt
    T.seen[T.step] = true
    if pressed("Tab") or clicked("tut_skip") then sound("click"); finish_tut(); return end
    if rs.mode == "dead" then return end
    if T.step == 1 and not G.waiting then T.step = 2
    elseif T.step == 2 and not rs.hook then T.step = 3
    elseif T.step == 3 and rs.hook then T.step, T.t = 4, 0
    elseif T.step == 4 and T.t > 3.5 then finish_tut() end
end
local function draw_tut(rs)
    local T = G.tut
    local w = L.w
    local cw, chh = 1240 * u, 118 * u
    local x, y = (w - cw) / 2, 150 * u
    panel(x, y, cw, chh, 30, { 0.02, 0.04, 0.045, 0.82 }, RIM, 14)
    local line = TUT[T.step]
    local now = T.step == 2 and rs.hook and not rs.slack and rs.om > 0 and rs.th > math.rad(25)
    text(now and "NOW!  Let go" or line[1], x + 30 * u, y + 40 * u, 27 * u, now and GOLD or GLASS, "left", 31, cw - 410 * u)
    text(line[2], x + 30 * u, y + 84 * u, 18 * u, DIM, "left", 31, cw - 410 * u)
    button("tut_skip", "SKIP GUIDE", "Tab", x + cw - 360 * u, y + 28 * u, 330 * u, 60 * u, 32, 1)
    -- mark the hook to catch (steps 2 and 3)
    if T.step == 2 or T.step == 3 then
        local it, inreach = next_hook(rs)
        if it then
            local hx, hy, hz = U.Course.hook(it, S.t)
            local sx, sy = G.project(hx, hy, hz)
            if sx then
                local r = (38 + 6 * math.sin(G.t * 6)) * u
                rect(sx - r, sy - r, 2 * r, 2 * r, CLEAR, 33, r, col4(inreach and GLASS or GOLD, 0.95))
                text(inreach and "CATCH THIS HOOK" or "NEXT HOOK", sx, sy - r - 20 * u, 18 * u, inreach and GLASS or GOLD, "center", 33, 260 * u)
            end
        end
    end
end

------------------------------------------------------------------ the game-over hint: what went wrong, what to do
function G.hint(rs, held_after_release)
    if rs.cause == "sink" then
        local ang, spd = tostring(rs.what or ""):match("^(%d+) deg ([%d.]+) u/s")
        ang, spd = tonumber(ang), tonumber(spd)
        local vz
        for i = #rs.events, 1, -1 do if rs.events[i].kind == "release" then vz = rs.events[i].vz; break end end
        if held_after_release == false then return "No hook caught: hold again as soon as you let go." end
        if vz and vz < 0 then return "You let go too late: release on the up-swing, near the top." end
        if spd and spd < D.RULES.SKIP_SPEED then return "Too slow to skip: swing higher before you let go." end
        if ang and ang > D.RULES.SKIP_ANGLE then return "Too steep to skip: let go a little earlier, for a flatter flight." end
        return "Hold again early: the chain only grabs hooks within reach."
    elseif rs.cause == "tangle" then
        return "Let go before the chain sweeps across a hull or a lamp arm."
    end
    local w = rs.what
    if w == "boat" then return "Catch the buoy before a boat, then fly over it from high on the swing." end
    if w == "bw_gap" or w == "bw" then return "Fly over the rocks at the harbour mouth from high on the swing." end
    if w == "pier" then return "Keep above the pier rail: let go earlier on the swing." end
    return "You flew into a lamp arm: hold earlier, so the chain catches the hook first."
end

------------------------------------------------------------------ the frame
SET:apply()
pcall(runtime_ui.clear, SCREEN)
pcall(runtime_ui.set_screen_overlay, SCREEN, true)
pcall(runtime_ui.show, SCREEN)
layout()
start_attract()
-- G.manual: the look/debug console modes (undertow.state / run) own the frame; the game draws nothing.
G.manual = false

function G.update(raw)
    if layout() then for id in pairs(widgets) do widgets[id] = true; hide(id) end end
    G.fdt, G.t = raw, G.t + raw
    clock = clock + raw
    G.card_t = G.card_t + raw
    if G.manual then for id in pairs(widgets) do hide(id) end; return end
    ambience(true)
    local esc = pressed("Escape")
    if pressed("M") then SET:toggle_mute() end
    local rs = S.rs
    local menu = SET:update(raw)
    if menu then
        flush_keys()
    elseif G.howto then
        howto_controls(esc)
    elseif G.pause then
        pause_controls(raw, esc)
    elseif esc then
        sound("click")
        if G.mode == "over" then to_title() else open_pause() end
    elseif G.mode == "title" then
        title_controls()
    elseif G.mode == "over" then
        over_controls(false)
    end
    local paused = G.pause ~= nil or G.howto ~= nil or SET:is_open() and G.mode == "run"
    if G.mode == "run" and G.waiting then
        local hold = G.hold_input() or (G.auto ~= nil)
        if not hold then G.armed = true elseif G.armed then G.waiting = false end
    end
    if not paused and rs then U.play_frame(raw) end
    rs = S.rs
    if G.mode == "run" and G.tut and not paused and rs then tut_update(rs, raw) end
    if rs then on_events(rs, G.mode ~= "title") end
    if G.mode == "title" and rs and rs.mode == "dead" then
        G.attract_dead_t = (G.attract_dead_t or 0) + raw
        if G.attract_dead_t > 1.5 then start_attract() end
    end
    -- the death delay waits while paused (Esc in the 1.1 s after a death left the pause card over the game-over card)
    if G.mode == "run" and rs.mode == "dead" and not paused then
        if not G.end_shown then G.end_shown = true; finish_run(rs); G.end_t = 0 end
        G.end_t = G.end_t + raw
        if G.end_t > 1.1 then G.mode, G.card_t = "over", 0 end
    end
    -- draw
    local a = min(1, G.card_t * 4)
    if G.howto and not SET:is_open() then
        draw_howto(min(1, G.howto.t * 6))
        for _, id in ipairs(TITLE_IDS) do hide(id) end
        for _, id in ipairs(OVER_IDS) do hide(id) end
        for _, id in ipairs(TUT_IDS) do hide(id) end
    elseif not SET:is_open() then
        for _, id in ipairs(HOWTO_IDS) do hide(id) end
        if G.mode == "title" then draw_title(a) else for _, id in ipairs(TITLE_IDS) do hide(id) end end
        if G.mode == "run" or G.mode == "over" then draw_hud() end
        if G.mode == "run" and G.tut and not paused and rs and rs.mode ~= "dead" then draw_tut(rs) else for _, id in ipairs(TUT_IDS) do hide(id) end end
        if G.mode == "over" then draw_over(a) else for _, id in ipairs(OVER_IDS) do hide(id) end end
    else
        for _, id in ipairs(TITLE_IDS) do hide(id) end
        for _, id in ipairs(OVER_IDS) do hide(id) end
        for _, id in ipairs(HOWTO_IDS) do hide(id) end
        for _, id in ipairs(TUT_IDS) do hide(id) end
    end
    draw_pause()
    flush_pools()
end

-- Console / testing helpers
function G.info()
    local rs = S.rs
    return string.format("mode=%s waiting=%s pause=%s settings=%s seed=%s best=%d runs=%d glass=%s sounds=%d score=%s state=%s",
        G.mode, tostring(G.waiting), tostring(G.pause ~= nil), tostring(SET:is_open()), tostring(G.seed), save.best, save.runs, save.glass,
        G.sounds_played or 0, tostring(rs and rs.score), tostring(rs and rs.mode))
end
return G
end
