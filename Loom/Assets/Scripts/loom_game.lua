-- Loom game flow: the title card (PLAY, SETTINGS, QUIT) over a weaver working the loom behind it, a run, the HUD,
-- the Esc pause card, the game-over card (RETRY, BACK TO MENU), the shared settings menu, the mute key, the save
-- file and the sounds. L is _G.loom (loom.lua): L.play(seed, opts) starts a rules run, L.play_frame(dt) runs it.
return function(L, SettingsMenu)
local G = {}
local D, W, R = L.D, L.W, L.R
local S = L.S
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local SCREEN = "loom"

------------------------------------------------------------------ palette (walnut, undyed cream, natural dyes)
local CLEAR = { 0, 0, 0, 0 }
local CREAM = { 0.97, 0.93, 0.84, 1 }
local DIM = { 0.84, 0.79, 0.68, 0.9 }
local OCHRE = { 0.93, 0.72, 0.36, 1 }
local SAGE = { 0.70, 0.82, 0.55, 1 }
local BAD = { 0.95, 0.52, 0.40, 1 }
local PANEL = { 0.10, 0.065, 0.04, 0.90 }
local BTN = { 0.17, 0.11, 0.07, 1 }
local BTN_HI = { 0.26, 0.17, 0.10, 1 }
local RIM = { 0.80, 0.62, 0.38, 0.85 }
local WOOL_UI = { sage = { 0.62, 0.70, 0.48 }, indigo = { 0.45, 0.56, 0.85 }, tan = { 0.84, 0.68, 0.48 }, brown = { 0.66, 0.46, 0.32 },
    ochre = { 0.90, 0.68, 0.30 }, grey = { 0.70, 0.68, 0.64 }, cream = { 0.95, 0.91, 0.82 } }

------------------------------------------------------------------ save (Save/loom.txt: best score, best rows, runs)
local SAVE = "Save/loom.txt"
local save = { best = 0, best_rows = 0, runs = 0, guided = 0 }
do
    local ok, txt = pcall(fs.read, SAVE)
    if ok and txt then
        for k, v in tostring(txt):gmatch("([%w_]+)%s*=%s*([%w_.]+)") do if save[k] ~= nil then save[k] = tonumber(v) or save[k] end end
    end
end
local function write_save()
    pcall(fs.write, SAVE, string.format("best=%d\nbest_rows=%d\nruns=%d\nguided=%d\n", save.best, save.best_rows, save.runs, save.guided))
end
G.save = save
local function village() return save.best_rows >= R.VILLAGE_AT end
G.village = village

------------------------------------------------------------------ sounds (Assets/Audio, CC0 recordings: see CREDITS.txt)
local LEN = { beat = 0.7, shuttle = 0.5, wool = 0.6, step = 0.3, click = 0.12, over = 1.6, unlock = 1.2 }
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

local SET = SettingsMenu.new({ title = "SETTINGS", subtitle = "LOOM", click = function() sound("click") end,
    theme = { accent = { 0.86, 0.66, 0.40, 1 }, accent2 = { 0.70, 0.82, 0.55, 1 }, text = CREAM, selected_text = { 1, 0.97, 0.88, 1 } },
    on_graphics = function() pcall(settings.set, "taa", true); pcall(settings.set, "fxaa", false) end })
G.settings = SET

------------------------------------------------------------------ widgets (Topple's / Undertow's pattern: pooled runtime_ui quads)
local widgets, pools, LY, u = {}, {}, {}, 1
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
G.rects = {}                -- every click target's last rectangle (window pixels): the live input driver clicks their centres
local function catcher(id, x, y, w, h, z)
    G.rects[id] = { x = x, y = y, w = w, h = h }
    quad(id, { style = "text", label = "", x = x, y = y, width = w, height = h, z = z or 60, no_input = false })
end
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
-- Text of em size px centred on y; a soft dark copy under it for legibility over the cloth.
local function text(s, x, y, px, color, align, z, w)
    local h = px * 1.6
    local bw = w or max(60, #s * px * 0.75)
    local bx = align == "left" and x or (align == "right" and x - bw or x - bw / 2)
    local a = color[4] or 1
    quad(pid("t"), { style = "text", label = s, x = bx + px * 0.05, y = y - h / 2 + px * 0.07, width = bw, height = h, z = (z or 40) - 0.5,
        font_scale = px / 16, text_color = { 0.06, 0.03, 0.01, 0.6 * a }, align_h = align or "center", align_v = "middle" })
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
-- Split s into lines of at most n characters (at spaces): the UI quads do not wrap text themselves.
local function wrap(s, n)
    local out, line = {}, ""
    for word in s:gmatch("%S+") do
        if #line == 0 then line = word
        elseif #line + 1 + #word <= n then line = line .. " " .. word
        else out[#out + 1] = line; line = word end
    end
    if #line > 0 then out[#out + 1] = line end
    return out
end
G.wrap = wrap
local function button(id, label, key, x, y, w, h, z, a, colour)
    local hvv = hv(id)
    y = y - hvv * 3 * u
    if hvv > 0.02 then rect(x - 5 * u, y - 5 * u, w + 10 * u, h + 10 * u, CLEAR, z, 14 * u, col4(OCHRE, 0.35 * hvv * a)) end
    panel(x, y, w, h, z + 1, col4(hvv > 0.5 and BTN_HI or BTN, a), col4(hvv > 0.5 and OCHRE or RIM, a), 10)
    local px = min(26 * u, h * 0.42)
    text(label, x + w / 2, y + h / 2, px, col4(colour or CREAM, a), "center", z + 2, w - 110 * u)
    if key then text(key, x + w - 16 * u, y + h / 2, px * 0.6, col4(OCHRE, 0.9 * a), "right", z + 2, 110 * u) end
    catcher(id, x, y, w, h, z + 4)
end
local function layout()
    local ok, surf = pcall(runtime_ui.get_surface_size)
    local w, h = ok and surf and surf.width or 1280, ok and surf and surf.height or 720
    if w <= 0 or h <= 0 then w, h = 1280, 720 end
    local changed = LY.w ~= w or LY.h ~= h
    LY.w, LY.h = w, h
    u = min(w / 1600, h / 900)          -- 1280x720 -> 0.8: the smallest text stays readable
    return changed
end

------------------------------------------------------------------ input (key edges)
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
local KEYS = { "Escape", "Return", "Space", "M", "Q", "R", "S", "H", "Tab", "Backspace", "Left", "Right", "A", "D", "1", "2", "3", "4", "5", "6", "7", "8", "9" }
local function flush_keys() for _, k in ipairs(KEYS) do pressed(k) end end
G.pressed_override = nil      -- tests / console: a table of key names to treat as freshly pressed this frame
local function press(name)
    if G.pressed_override and G.pressed_override[name] then return true end
    return pressed(name)
end

------------------------------------------------------------------ flow
-- G.mode: "title" (the weaver works behind the card) | "run" | "over" (the card after a run ended)
G.mode, G.card_t, G.t = "title", 0, 0
G.sel = 2               -- the chosen kind (path)
local attract_seed = 3
local function start_attract()
    L.play(attract_seed, { village = true })
    attract_seed = attract_seed % 97 + 7
    G.attract_t = 0
end
local function new_seed()
    G.seed_n = (G.seed_n or 0) + 1
    return (save.runs * 7919 + floor(G.t * 1000) + G.seed_n * 104729) % 99991 + 1
end
G.msg, G.msg_t = nil, 0
local function say(s, col) G.msg, G.msg_t, G.msg_col = s, 0, col or CREAM end
function G.start_run(seed)
    seed = seed or new_seed()
    L.play(seed, { village = village() })
    G.mode, G.card_t, G.seed = "run", 0, seed
    G.ev_n = S.st.nev
    G.new_best, G.unlocked_now = false, false
    G.end_shown = false
    G.sel = 2
    G.confirm = nil
    say("Weave the next row: 1-9 lay wool, SPACE beats it in", OCHRE)
    -- the guided first run: shown once (Save/loom.txt guided=1 once it ends or is skipped)
    G.guide = (save.guided or 0) == 0 and { step = 1, t = 0, beats = 0 } or nil
    flush_keys()
    return "run seed " .. seed
end
local function end_guide()
    if G.guide then G.guide = nil; save.guided = 1; write_save() end
end
G.end_guide = end_guide
local function to_title()
    G.mode, G.card_t = "title", 0
    G.pause = nil
    start_attract()
    flush_keys()
end
G.to_title = to_title
local function quit_game() sound("click"); pcall(engine.quit) end

local function finish_run(st)
    save.runs = save.runs + 1
    local before_rows = save.best_rows
    if st.score > save.best then save.best = st.score; G.new_best = true end
    if st.walked > save.best_rows then save.best_rows = st.walked end
    if before_rows < R.VILLAGE_AT and save.best_rows >= R.VILLAGE_AT then G.unlocked_now = true end
    write_save()
end

local KIND_WORD = { f = "field", w = "woods", H = "house", r = "rock", h = "hill", ["~"] = "river", b = "bridge", B = "bridge" }
-- The cells of the row being woven that would carry the path on (R.path_marks) and whether beating now would end the
-- run (R.would_break), cached per row content.
local mark_cache = {}
function G.marks(st)
    local sig = st.K .. "|" .. R.row_string(st) .. "|" .. st.trav.c .. "," .. st.trav.k .. "|" .. tostring(st.over)
    if mark_cache.sig ~= sig then
        mark_cache.sig = sig
        mark_cache.marks = R.path_marks(st)
        mark_cache.breaks = R.would_break(st)
    end
    return mark_cache.marks, mark_cache.breaks
end
local function on_events(st, live)
    local n0 = G.ev_n or 0
    for _, e in ipairs(st.events) do
        if e.n > n0 then
            if live then
                if e.kind == "lay" then sound("shuttle", 0.05)
                elseif e.kind == "undo" then sound("click")
                elseif e.kind == "beat" then
                    sound("beat")
                    if G.guide then
                        G.guide.beats = G.guide.beats + 1
                        if G.guide.step <= 2 then G.guide.step, G.guide.t = 3, 0 end
                    end
                elseif e.kind == "wool" then
                    sound("wool", 0.15)
                    if G.mode == "run" then say(string.format("+%d wool from the %s", e.amount, KIND_WORD[e.what] or "land"), SAGE) end
                    if G.guide and G.guide.step == 3 then
                        G.guide.step, G.guide.t = 4, 0
                        G.guide.wool = string.format("+%d %s wool earned back from the %s", e.amount, next(R.HARVEST[e.what]) or "", KIND_WORD[e.what] or "land")
                    end
                elseif e.kind == "step" then sound("step", 0.2)
                elseif e.kind == "over" then sound("over") end
            end
            n0 = e.n
        end
    end
    G.ev_n = n0
end

------------------------------------------------------------------ the weaving controls (run)
local function try(ok, why)
    if not ok and why then say(why, BAD); sound("click") end
    return ok
end
local function run_controls()
    local st = S.st
    if not st or st.over then return end
    if press("Left") or press("A") then st.cursor = max(0, st.cursor - 1) end
    if press("Right") or press("D") then st.cursor = min(R.COLS - 1, st.cursor + 1) end
    for i = 1, 9 do
        if press(tostring(i)) then
            G.sel = i
            G.hint_i, G.hint_t = i, G.t
            if try(R.lay(st, st.cursor, i)) then say(R.KINDS[i].name:upper() .. " laid", CREAM) end
        end
    end
    if press("Backspace") then try(R.undo(st)) end
    if press("Tab") and G.guide then end_guide(); say("Guide skipped: HOW TO PLAY is on the pause card (Esc)", OCHRE) end
    if press("Space") and not L.busy() then G.beat_now(st) end
    -- mouse: a chip chooses the kind; a cell of the row lays it there
    for i = 1, 9 do if clicked("chip" .. i) then G.sel = i; G.hint_i, G.hint_t = i, G.t; sound("click") end end
    for c = 0, R.COLS - 1 do
        if clicked("cell" .. c) then
            st.cursor = c
            try(R.lay(st, c, G.sel))
        end
    end
    if clicked("beat_btn") and not L.busy() then G.beat_now(st) end
    if clicked("g_skip") and G.guide then end_guide() end
end
-- SPACE: beat the row in. A row that would end the run needs a second press within 5 s (the clock's own beat stays).
function G.beat_now(st)
    local _, breaks = G.marks(st)
    if breaks and not (G.confirm and G.t - G.confirm < 5) then
        G.confirm = G.t
        say("This row does not carry the path on: it ENDS THE RUN. SPACE again to beat it anyway.", BAD)
        sound("click")
        return false
    end
    G.confirm = nil
    if try(R.beat(st)) then say("Beaten in", CREAM); return true end
    return false
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
    elseif press("Q") or clicked("pz_quit") then close_pause(); quit_game()
    elseif press("H") or clicked("pz_howto") then sound("click"); close_pause(); G.open_howto(function() open_pause() end)
    elseif clicked("pz_settings") then sound("click"); close_pause(); SET:open(function() open_pause() end)
    elseif G.mode ~= "title" and clicked("pz_menu") then sound("click"); close_pause(); to_title() end
end
local function draw_pause()
    local P = G.pause
    if not P or SET:is_open() then for _, id in ipairs(PAUSE_IDS) do hide(id) end; return end
    local w, h = LY.w, LY.h
    local a = min(1, P.t * 6)
    rect(0, 0, w, h, { 0.03, 0.02, 0.01, 0.5 * a }, 150)
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
    local st = S.st
    text(G.mode == "title" and "LOOM" or ("Score " .. tostring(st and st.score or 0) .. "   ·   the loom waits"), x + cw / 2, y + 104 * u,
        18 * u, col4(OCHRE, a), "center", 153, cw - 40 * u)
    for i, r in ipairs(rows) do
        local by = y + 150 * u + (i - 1) * (bh + gap)
        button(r[1], r[2], r[3], x + 40 * u, by, bw, bh, 154, a, r[1] == "pz_quit" and BAD or CREAM)
    end
end

------------------------------------------------------------------ title
local TITLE_IDS = { "t_play", "t_howto", "t_settings", "t_quit" }
local function draw_title(a)
    local w, h = LY.w, LY.h
    local cw, ch = 1100 * u, 790 * u
    local x, y = (w - cw) / 2, (h - ch) / 2 + (1 - ease_back(G.card_t * 2.5)) * 30 * u
    panel(x, y, cw, ch, 81, col4(PANEL, a * 0.93), col4(RIM, a), 20)
    local cx = x + cw / 2
    text("LOOM", cx, y + 80 * u, 88 * u, col4(CREAM, a), "center", 82, cw)
    text("Weave the land row by row, and keep the traveller's path going.", cx, y + 146 * u, 22 * u, col4(DIM, a), "center", 82, cw - 60 * u)
    local bx, by, bw, bh = x + 50 * u, y + 184 * u, cw - 100 * u, 150 * u
    rect(bx, by, bw, bh, col4({ 0.04, 0.02, 0.01, 0.55 }, a), 82, 12 * u, col4(RIM, 0.35 * a))
    text("Every row you weave must carry the traveller's PATH on, or the run ends.", cx, by + 36 * u, 20 * u, col4(CREAM, a), "center", 83, bw - 40 * u)
    text("1-9 lay wool   ·   LEFT / RIGHT move the shuttle   ·   SPACE beat the row in", cx, by + 76 * u, 19 * u, col4(OCHRE, a), "center", 83, bw - 40 * u)
    text("New to the loom?  Read HOW TO PLAY (H) first.", cx, by + 116 * u, 19 * u, col4(SAGE, a), "center", 83, bw - 40 * u)
    local bw2, bh2, gap = 380 * u, 66 * u, 14 * u
    local x0 = cx - bw2 / 2
    local y0 = by + bh + 28 * u
    button("t_play", "PLAY", "Enter", x0, y0, bw2, bh2, 84, a, SAGE)
    button("t_howto", "HOW TO PLAY", "H", x0, y0 + (bh2 + gap), bw2, bh2, 84, a, OCHRE)
    button("t_settings", "SETTINGS", "S", x0, y0 + 2 * (bh2 + gap), bw2, bh2, 84, a)
    button("t_quit", "QUIT", "Q", x0, y0 + 3 * (bh2 + gap), bw2, bh2, 84, a, BAD)
    local line = string.format("Best %d   ·   %d rows walked", save.best, save.best_rows) ..
        (village() and "   ·   village houses unlocked" or string.format("   ·   village houses unlock at %d rows walked", R.VILLAGE_AT))
    text(line, cx, y + ch - 40 * u, 18 * u, col4(OCHRE, a), "center", 82, cw - 40 * u)
    text("Esc pause   ·   M mute", cx, y + ch - 14 * u, 15 * u, col4(DIM, 0.85 * a), "center", 82, cw - 40 * u)
end
local function title_controls()
    if G.card_t < 0.25 then return end
    if press("Return") or clicked("t_play") then sound("click"); G.start_run()
    elseif press("H") or clicked("t_howto") then sound("click"); G.open_howto(function() flush_keys() end)
    elseif press("S") or clicked("t_settings") then sound("click"); SET:open(function() flush_keys() end)
    elseif press("Q") or clicked("t_quit") then quit_game() end
end

------------------------------------------------------------------ game over
local OVER_IDS = { "o_retry", "o_menu" }
-- The cause of a broken path and its fix, in plain words (rules: st.over_info).
function G.over_words(st)
    local i = st.over_info or {}
    local col = i.heads and i.heads[1] and (" (column " .. (i.heads[1] + 1) .. ")") or ""
    if i.cause == "clock" then
        return "THE LOOM BEAT AN EMPTY ROW",
            "The clock ran out before the row carried the path on, so the loom beat it in by itself and the path stopped" .. col .. ".",
            "before the clock runs out, lay PATH (2) on the outlined cell above the path's end, then press SPACE."
    elseif i.cause == "river" then
        return "THE RIVER CUT THE PATH",
            "A river crossed the end of the path" .. col .. " and no bridge carried the traveller over it.",
            "where the river meets the path, lay a BRIDGE (4) on the outlined cell. Bridges cost brown wool."
    elseif i.cause == "detached" then
        return "THE PATH IS BROKEN",
            "The row had path wool, but not where the traveller's path ended" .. col .. ", so the two never joined.",
            "lay PATH (2) on the outlined cell straight above the path's end, or join it sideways in the same row."
    end
    return "THE PATH IS BROKEN",
        "That row had no path joined to where the traveller's path ended" .. col .. ", so he had nowhere to walk.",
        "every row needs PATH (2) on the outlined cell above the path's end. SPACE warns you before a breaking beat."
end
local function draw_over(a)
    local st = S.st
    local w, h = LY.w, LY.h
    local cw, ch = 980 * u, 600 * u
    local x, y = (w - cw) / 2, (h - ch) / 2 + (1 - ease_back(G.card_t * 2.5)) * 30 * u
    panel(x, y, cw, ch, 81, col4(PANEL, a * 0.95), col4(RIM, a), 20)
    G.over_box = { x = x, y = y, w = cw, h = ch }
    local cx = x + cw / 2
    local head, why, fix = G.over_words(st)
    text(head, cx, y + 62 * u, 46 * u, col4(BAD, a), "center", 82, cw - 40 * u)
    local ly = y + 112 * u
    for _, l in ipairs(wrap(why, 78)) do text(l, cx, ly, 19 * u, col4(CREAM, a), "center", 82, cw - 50 * u); ly = ly + 28 * u end
    ly = ly + 6 * u
    for _, l in ipairs(wrap("FIX: " .. fix, 78)) do text(l, cx, ly, 19 * u, col4(SAGE, a), "center", 82, cw - 50 * u); ly = ly + 28 * u end
    text(tostring(st.score or 0), cx, y + 300 * u, 64 * u, col4(OCHRE, a), "center", 82, cw)
    text(G.new_best and "NEW BEST!" or ("best " .. save.best), cx, y + 350 * u, 20 * u, col4(G.new_best and SAGE or OCHRE, a), "center", 82, cw)
    local stats = string.format("%d rows walked   ·   %d wool earned back   ·   %d rows woven   ·   level %d", st.walked, st.harvest, st.beats, st.level)
    text(stats, cx, y + 388 * u, 19 * u, col4(CREAM, a), "center", 82, cw - 40 * u)
    if G.unlocked_now then
        text("VILLAGE HOUSES UNLOCKED   ·   key 9 lays a felt house", cx, y + 424 * u, 19 * u, col4(SAGE, a), "center", 82, cw - 40 * u)
    end
    local bw, bh, gap = 370 * u, 66 * u, 24 * u
    local by = y + ch - bh - 44 * u
    button("o_retry", "RETRY", "Enter", cx - bw - gap / 2, by, bw, bh, 84, a, SAGE)
    button("o_menu", "BACK TO MENU", "Esc", cx + gap / 2, by, bw, bh, 84, a)
end
local function over_controls(esc)
    if G.card_t < 0.35 then return end
    if press("Return") or press("R") or clicked("o_retry") then sound("click"); G.start_run()
    elseif esc or press("Backspace") or clicked("o_menu") then sound("click"); to_title() end
end

------------------------------------------------------------------ HOW TO PLAY (round 5: teaching in the game)
-- A two-page card opened from the title (H) and from the pause card, with BACK (Esc / Backspace), NEXT / PREV
-- (Right / Left). Every line is wrapped to its box; the boxes are checked in tests/view_smoke.lua.
local HOWTO_IDS = { "h_block", "h_back", "h_next", "h_prev" }
G.HOWTO = {
    {   title = "HOW TO PLAY   1 / 2   ·   THE PATH",
        items = {
            { "THE GOAL", "Keep the little traveller walking. He follows the woven PATH up the cloth, toward the loom." },
            { "EVERY ROW", "Each row you weave must carry the path on from where it ends: lay PATH on the outlined cell. If a row does not, the run ends." },
            { "WEAVE", "LEFT / RIGHT (or A / D) move the shuttle along the row. Keys 1-9 lay wool in its cell. BACKSPACE takes the last pick back." },
            { "BEAT", "SPACE beats the row in: the cloth moves on and the traveller walks. A row that would break the path asks for SPACE twice." },
            { "THE CLOCK", "Wait too long and the loom beats the row in by itself (top right). Cells you left empty become plain meadow." },
        } },
    {   title = "HOW TO PLAY   2 / 2   ·   WOOL AND LAND",
        items = {
            { "WOOL", "Each kind costs one wool of its colour (meadow is free). The chips at the bottom show the wool left: hover one (or press its key) to see what it does and pays." },
            { "EARN IT BACK", "Land beside the path pays wool when the traveller walks past: fields tan, woods brown and ochre, hills tan and sage, water indigo, bridges brown and tan, rocks cream, houses tan, ochre and brown." },
            { "RIVERS", "A river must start at the cloth's edge or join water. Where a river crosses the path, lay a BRIDGE (4) on it." },
            { "COMING UP", "The panel at the top right shows the next 3 rows. Rivers and rocks stand in the way: turn the path sideways early. Every 10 rows the loom beats faster." },
            { "HOUSES", "Village houses (9) unlock once you have walked 12 rows in one run. They pay three wools." },
        } },
}
function G.open_howto(on_close)
    G.howto = { page = 1, t = 0, on_close = on_close }
    flush_keys()
end
local function close_howto()
    local f = G.howto and G.howto.on_close
    G.howto = nil
    for _, id in ipairs(HOWTO_IDS) do hide(id) end
    flush_keys()
    if f then f() end
end
G.close_howto = close_howto
local function howto_controls(dt, esc)
    local H = G.howto
    H.t = H.t + dt
    if H.t < 0.12 then return end
    if esc or press("Backspace") or clicked("h_back") then sound("click"); close_howto()
    elseif (press("Right") or press("D") or clicked("h_next")) and H.page < #G.HOWTO then sound("click"); H.page = H.page + 1
    elseif (press("Left") or press("A") or clicked("h_prev")) and H.page > 1 then sound("click"); H.page = H.page - 1 end
end
-- page 1's picture: a few rows of cloth, the traveller on the path, the outlined cell above its end in the loose row
local function howto_picture(x, y, cs, a)
    local GREEN, TAN, LOOSE = { 0.40, 0.55, 0.28 }, { 0.80, 0.66, 0.46 }, { 0.30, 0.24, 0.18 }
    local path = { [1] = 2, [2] = 2, [3] = 2, [4] = 3 }       -- row (from the bottom) -> path column
    for r = 1, 4 do
        for c = 1, 5 do
            local yy = y + (5 - r) * (cs + 3 * u)
            local col = (path[r] == c or (r == 4 and c == 2)) and TAN or GREEN
            rect(x + (c - 1) * (cs + 3 * u), yy, cs, cs, col4(col, a), 163, 4 * u)
        end
    end
    for c = 1, 5 do      -- the row being woven: loose warp, the outlined cell above the path's end (column 3)
        local xx = x + (c - 1) * (cs + 3 * u)
        rect(xx, y, cs, cs, col4(LOOSE, a), 163, 4 * u)
        if c == 3 then rect(xx - 2 * u, y - 2 * u, cs + 4 * u, cs + 4 * u, col4({ 0.70, 0.86, 0.52, 0.30 }, a), 164, 6 * u, col4(SAGE, a)) end
    end
    local tx, ty = x + 1 * (cs + 3 * u) + cs / 2, y + 3 * (cs + 3 * u) + cs / 2       -- traveller on row 2
    rect(tx - 8 * u, ty - 14 * u, 16 * u, 28 * u, col4({ 0.62, 0.16, 0.12 }, a), 165, 8 * u)
    text("lay PATH here", x + 2 * (cs + 3 * u) + cs / 2, y - 22 * u, 18 * u, col4(SAGE, a), "center", 165, 220 * u)
    text("the traveller", tx, ty + cs * 0.9, 18 * u, col4(CREAM, a), "center", 165, 160 * u)
end
local function draw_howto()
    local H = G.howto
    local P = G.HOWTO[H.page]
    local w, h = LY.w, LY.h
    local a = min(1, H.t * 6)
    rect(0, 0, w, h, { 0.03, 0.02, 0.01, 0.55 * a }, 160)
    catcher("h_block", 0, 0, w, h, 161)
    local cw, ch = 1360 * u, 830 * u
    local x, y = (w - cw) / 2, (h - ch) / 2
    panel(x, y, cw, ch, 162, col4(PANEL, a), col4(RIM, a), 18)
    G.howto_box = { x = x, y = y, w = cw, h = ch }
    text(P.title, x + cw / 2, y + 48 * u, 34 * u, col4(CREAM, a), "center", 163, cw - 60 * u)
    local pic = H.page == 1
    local bodyw = pic and 640 * u or 950 * u
    local nchar = floor(bodyw / (20 * u * 0.56))
    local ly = y + 110 * u
    for _, it in ipairs(P.items) do
        text(it[1], x + 40 * u, ly, 21 * u, col4(OCHRE, a), "left", 163, 250 * u)
        for _, l in ipairs(wrap(it[2], nchar)) do
            text(l, x + 300 * u, ly, 20 * u, col4(CREAM, a), "left", 163, bodyw)
            ly = ly + 30 * u
        end
        ly = ly + 16 * u
    end
    if pic then howto_picture(x + cw - 380 * u, y + 170 * u, 58 * u, a) end
    local bw, bh = 260 * u, 62 * u
    local by = y + ch - bh - 28 * u
    button("h_back", "BACK", "Esc", x + 40 * u, by, bw, bh, 166, a)
    if H.page > 1 then button("h_prev", "< PREV", "Left", x + cw / 2 - bw / 2, by, bw, bh, 166, a) else hide("h_prev") end
    if H.page < #G.HOWTO then button("h_next", "NEXT >", "Right", x + cw - 40 * u - bw, by, bw, bh, 166, a, SAGE) else hide("h_next") end
end

------------------------------------------------------------------ the path marks and the guided first run
-- Where the cells that would carry the path on (R.path_marks) sit on screen: the guide points there. Not drawn on the
-- cloth (a static box looked wrong there); COMING UP outlines them in its bottom row.
function G.draw_marks(st, marks)
    if not (W.project and LY.w) then return end
    G.mark_rects = {}
    for c = 0, R.COLS - 1 do
        if marks[c] then
            local x1, y1 = W.project(W.col_x(c) - D.CELL / 2 + 0.003, D.CELL - 0.003, D.Z0, LY.w, LY.h)
            local x2, y2 = W.project(W.col_x(c) + D.CELL / 2 - 0.003, 0.003, D.Z0, LY.w, LY.h)
            G.mark_rects[c] = { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
        end
    end
end
local GUIDE_TEXT = {
    "YOUR FIRST ROW.  The traveller's path ends below the cell OUTLINED in COMING UP (top right).  Move the shuttle there with LEFT / RIGHT and press 2 to lay PATH.",
    "GOOD: the path goes on.  Lay other land if you like (it costs wool), then press SPACE to beat the row in.",
    "The cloth moved on and the traveller walked.  Land beside his path pays wool back when he passes: watch the chips at the bottom.",
}
function G.guide_text()
    local g = G.guide
    if not g then return nil end
    if g.step == 4 then return (g.wool or "Wool earned back") .. "!  Fields, woods and hills beside the path keep your bobbins full." end
    return GUIDE_TEXT[g.step]
end
local function draw_guide()
    local g = G.guide
    local w = LY.w
    local s = G.guide_text()
    local lines = wrap(s, 72)
    local bw = 1100 * u
    local bh = (34 + 32 * #lines + 40) * u
    local x, y = (w - bw) / 2, 150 * u
    panel(x, y, bw, bh, 70, { 0.10, 0.07, 0.04, 0.94 }, col4(SAGE, 0.9), 14)
    G.guide_box = { x = x, y = y, w = bw, h = bh }
    text("FIRST RUN GUIDE   ·   step " .. min(g.step, 3) .. " of 3", x + 24 * u, y + 24 * u, 17 * u, SAGE, "left", 71, 600 * u)
    for i, l in ipairs(lines) do text(l, x + 24 * u, y + (24 + 32 * i) * u, 21 * u, CREAM, "left", 71, bw - 48 * u) end
    text("TAB skip the guide", x + bw - 24 * u, y + 24 * u, 16 * u, DIM, "right", 71, 280 * u)
    catcher("g_skip", x + bw - 300 * u, y + 6 * u, 290 * u, 36 * u, 72)
    if g.step <= 2 and G.mark_rects then
        -- point at the outlined cell nearest the cursor
        local best, bd
        for c, r in pairs(G.mark_rects) do
            local d = math.abs(c - (S.st.cursor or 4))
            if not bd or d < bd then best, bd = r, d end
        end
        if best then
            text(g.step == 1 and "press 2:  PATH here" or "SPACE: beat it in", best.x + best.w / 2, best.y - 26 * u, 22 * u, { 0.80, 0.96, 0.60, 1 }, "center", 71, 360 * u)
        end
    end
end

------------------------------------------------------------------ HUD
-- What each kind does (the hint over a chip: hover it, or press its key)
local KIND_HINT = {
    ["."] = "Plain grass. The traveller cannot walk on it. Cells you leave empty become meadow.",
    p = "The traveller walks on it. Every row needs path joined to the path below it.",
    ["~"] = "A river. It must start at the cloth's edge or join water. Only a bridge crosses it.",
    b = "Lay it on a river where your path meets it: the traveller crosses there.",
    w = "Trees. Lay them beside the path to earn brown wool back (bridges need it).",
    f = "Crops. Lay them beside the path: the best way to earn path wool (tan) back.",
    h = "A hill. Lay it beside the path to earn a little tan and sage back.",
    r = "Stone. The traveller cannot cross it. Beside the path it pays cream wool for houses.",
    H = "The traveller walks on it like path, and it pays three wools when he passes.",
}
G.KIND_HINT = KIND_HINT
function G.pays_text(k)
    local hk = R.HARVEST[k]
    if not hk then return "Pays nothing back." end
    local t = {}
    for _, w in ipairs(R.WOOLS) do if hk[w] then t[#t + 1] = hk[w] .. " " .. w end end
    return "Pays back " .. table.concat(t, " + ") .. " when the traveller walks past it."
end
local function draw_kind_hint(st, i, cx, ybot)
    local d = R.KINDS[i]
    local bw = 460 * u
    local lines = {}
    local function add(str, col) for _, l in ipairs(wrap(str, 38)) do lines[#lines + 1] = { l, col } end end
    if d.cost == 0 then add("Free.", DIM)
    else add(string.format("Costs 1 %s wool  ·  you have %d", d.wool, st.wool[d.wool]), st.wool[d.wool] < d.cost and BAD or DIM) end
    add(KIND_HINT[d.k], CREAM)
    add(G.pays_text(d.k), SAGE)
    if d.k == "H" and not st.village then add("Unlocks once you walk " .. R.VILLAGE_AT .. " rows in one run.", OCHRE) end
    local bh = (58 + #lines * 28 + 14) * u
    local x = max(12 * u, min(LY.w - bw - 12 * u, cx - bw / 2))
    local y = ybot - bh
    panel(x, y, bw, bh, 50, { 0.09, 0.06, 0.035, 0.96 }, col4(OCHRE, 0.9), 12)
    text(i .. "   " .. d.name:upper(), x + 20 * u, y + 30 * u, 24 * u, OCHRE, "left", 51, bw - 40 * u)
    for n, l in ipairs(lines) do text(l[1], x + 20 * u, y + (58 + (n - 1) * 28 + 14) * u, 19 * u, l[2], "left", 51, bw - 40 * u) end
    G.hint_box = { x = x, y = y, w = bw, h = bh, i = i, lines = lines }
end
-- COMING UP: the pattern of the next R.PREVIEW rows (top = farthest) over the row being woven
local PREVIEW_COL = { ["~"] = { 0.30, 0.46, 0.80 }, r = { 0.60, 0.58, 0.55 }, h = { 0.46, 0.58, 0.30 }, p = { 0.84, 0.68, 0.48 },
    H = { 0.95, 0.91, 0.82 }, b = { 0.66, 0.46, 0.32 }, B = { 0.66, 0.46, 0.32 }, f = { 0.90, 0.68, 0.30 }, w = { 0.26, 0.42, 0.20 } }
local PREVIEW_EMPTY = { 0.20, 0.27, 0.14 }
local function draw_preview(st, marks, x, y, pw)
    local gap = 3 * u
    local cs = (pw - 44 * u - 8 * gap) / 9
    local nrow = #st.ahead + 1
    local ph = (44 + 36) * u + nrow * (cs + gap) + 8 * u
    panel(x, y, pw, ph, 20, { 0.08, 0.05, 0.03, 0.72 }, { 0.80, 0.62, 0.38, 0.5 }, 12)
    text("COMING UP", x + 22 * u, y + 24 * u, 16 * u, col4(OCHRE, 0.95), "left", 21, 160 * u)
    text("bottom row = this row", x + pw - 22 * u, y + 24 * u, 14 * u, DIM, "right", 21, 170 * u)
    local gx, gy = x + 22 * u, y + 44 * u
    for r = 1, nrow do
        local f = r < nrow and st.ahead[nrow - r] or nil          -- top: the farthest row; bottom: the row being woven
        local yy = gy + (r - 1) * (cs + gap) + (r == nrow and 6 * u or 0)
        for c = 0, R.COLS - 1 do
            local k
            if f then k = f[c] else k = st.cur[c] end
            local col = PREVIEW_COL[k] or PREVIEW_EMPTY
            local a = f and (0.55 + 0.45 * (r / nrow)) or 1
            rect(gx + c * (cs + gap), yy, cs, cs, { col[1], col[2], col[3], a }, 21, 4 * u)
            if not f and marks and marks[c] then
                rect(gx + c * (cs + gap) - 2 * u, yy - 2 * u, cs + 4 * u, cs + 4 * u, CLEAR, 22, 5 * u, { 0.78, 0.94, 0.56, 0.95 })
            end
        end
    end
    local ly = y + ph - 22 * u
    local lx = x + 22 * u
    for _, it in ipairs({ { "~", "river" }, { "r", "rock" }, { "h", "hill" }, { "p", "path" } }) do
        rect(lx, ly - 7 * u, 14 * u, 14 * u, col4(PREVIEW_COL[it[1]], 1), 21, 3 * u)
        text(it[2], lx + 20 * u, ly, 14 * u, DIM, "left", 21, 60 * u)
        lx = lx + 72 * u
    end
    G.preview_box = { x = x, y = y, w = pw, h = ph, cs = cs }
end
-- The warning line above the chips: what needs doing now, most urgent first.
function G.warning(st, marks)
    for c = 0, R.COLS - 1 do
        if marks[c] and st.forced[c] == "~" then return "A river crosses the path here: lay a BRIDGE (4) on the outlined cell", OCHRE end
    end
    local any, open_above = false, false
    for c = 0, R.COLS - 1 do
        if marks[c] then any = true; if st.ahead[1] and R.passable(st.ahead[1], c) then open_above = true end end
    end
    if any and not open_above then return "The next row is blocked above the path: run the path sideways in this row (see COMING UP)", BAD end
    if st.wool.tan <= 2 then
        if st.wool.ochre < 1 then return string.format("Path wool low (%d tan) and no ochre: lay WOODS (5) beside the path for ochre, then FIELDS (6)", st.wool.tan), BAD end
        return string.format("Path wool low (%d tan): lay FIELDS (6) beside the path - each pays 2 tan when the traveller passes", st.wool.tan), BAD
    end
    for i, f in ipairs(st.ahead) do
        local n = 0
        for c = 0, R.COLS - 1 do if f[c] == "~" then n = n + 1 end end
        if n >= 2 then
            local when = i == 1 and "the next row" or ("in " .. i .. " rows")
            if st.wool.brown < 1 then return "A river crosses " .. when .. " and you have no brown wool for a bridge!", BAD end
            return "A river crosses " .. when .. ": keep brown wool for a BRIDGE (4)", OCHRE
        end
    end
    return nil
end
local CHIP_IDS = {}
for i = 1, 9 do CHIP_IDS[#CHIP_IDS + 1] = "chip" .. i end
for c = 0, 8 do CHIP_IDS[#CHIP_IDS + 1] = "cell" .. c end
CHIP_IDS[#CHIP_IDS + 1] = "beat_btn"
local function draw_hud()
    local st = S.st
    local w, h = LY.w, LY.h
    local m = 26 * u
    -- score and rows (top left)
    panel(m, m, 340 * u, 122 * u, 20, { 0.08, 0.05, 0.03, 0.66 }, { 0.80, 0.62, 0.38, 0.5 }, 12)
    text("SCORE", m + 22 * u, m + 26 * u, 15 * u, col4(OCHRE, 0.9), "left", 21, 120 * u)
    text(tostring(st.score), m + 22 * u, m + 64 * u, 44 * u, CREAM, "left", 21, 300 * u)
    text(string.format("%d rows walked   ·   level %d", st.walked, st.level), m + 22 * u, m + 102 * u, 16 * u, DIM, "left", 21, 300 * u)
    -- the loom's clock (top right)
    local bt = R.beat_time(st.level)
    local f = max(0, min(1, st.timer / bt))
    local pw = 330 * u
    panel(w - m - pw, m, pw, 104 * u, 20, { 0.08, 0.05, 0.03, 0.66 }, { 0.80, 0.62, 0.38, 0.5 }, 12)
    text("BEST " .. max(save.best, st.score), w - m - 22 * u, m + 28 * u, 22 * u, OCHRE, "right", 21, pw - 40 * u)
    text(string.format("the loom beats in %d s", math.ceil(st.timer)), w - m - 22 * u, m + 60 * u, 16 * u, f < 0.25 and BAD or DIM, "right", 21, pw - 40 * u)
    rect(w - m - pw + 22 * u, m + 80 * u, (pw - 44 * u), 8 * u, { 0.2, 0.13, 0.08, 0.8 }, 21, 4 * u)
    rect(w - m - pw + 22 * u, m + 80 * u, (pw - 44 * u) * f, 8 * u, col4(f < 0.25 and BAD or SAGE, 0.95), 22, 4 * u)
    local marks, breaks = G.marks(st)
    local py = m + 116 * u
    if SET:get("mute") then text("MUTED  ·  M", w - m - 22 * u, m + 124 * u, 14 * u, OCHRE, "right", 21, 210 * u); py = py + 26 * u end
    draw_preview(st, marks, w - m - pw, py, pw)
    local warn, warn_col = G.warning(st, marks)
    G.warn = warn
    G.draw_marks(st, marks)
    -- the kind chips (bottom): key, name, the wool it spends and what is left
    -- round 3: larger chips (readable at 1280x720: 17 / 15 px), and the wool left as a big number (the wool balls are
    -- out of the close camera's view)
    local cw, chh, gap = 168 * u, 94 * u, 6 * u
    local total = 9 * cw + 8 * gap
    local x0, y0 = (w - total) / 2, h - chh - 18 * u
    for i, d in ipairs(R.KINDS) do
        local x = x0 + (i - 1) * (cw + gap)
        local sel = G.sel == i
        local locked = d.k == "H" and not st.village
        local wc = WOOL_UI[d.wool]
        panel(x, y0, cw, chh, 20, sel and { 0.24, 0.15, 0.08, 0.92 } or { 0.08, 0.05, 0.03, 0.80 }, sel and col4(OCHRE, 1) or { 0.80, 0.62, 0.38, 0.45 }, 10)
        rect(x + 9 * u, y0 + 12 * u, 12 * u, chh - 24 * u, { wc[1], wc[2], wc[3], locked and 0.3 or 1 }, 21, 5 * u)
        text(tostring(i), x + 30 * u, y0 + 26 * u, 22 * u, col4(OCHRE, locked and 0.4 or 1), "left", 22, 26 * u)
        text(d.name:upper(), x + 54 * u, y0 + 26 * u, 21 * u, col4(CREAM, locked and 0.4 or 1), "left", 22, cw - 58 * u)
        local sub
        if locked then sub = R.VILLAGE_AT .. " rows"
        elseif d.cost == 0 then sub = "free"
        else sub = string.format("%s %d", d.wool, st.wool[d.wool]) end
        local low = d.cost > 0 and st.wool[d.wool] < d.cost and not locked
        text(sub, x + 30 * u, y0 + 66 * u, 19 * u, low and BAD or col4(DIM, locked and 0.5 or 1), "left", 22, cw - 34 * u)
        catcher("chip" .. i, x, y0, cw, chh, 26)
        if hovered("chip" .. i) then G.hover_i = i end
    end
    -- the hint of the hovered chip, or of the kind just chosen by key / click (2.5 s)
    local hi = G.hover_i
    G.hover_i = nil
    if not hi and G.hint_i and G.t - (G.hint_t or -9) < 2.5 then hi = G.hint_i end
    G.hint_box = nil
    if hi and not st.over and not G.guide then draw_kind_hint(st, hi, x0 + (hi - 1) * (cw + gap) + cw / 2, y0 - 128 * u) end   -- above the warning lines
    -- message line and the controls cue (above the chips)
    local my = y0 - 30 * u
    if G.msg and G.mode ~= "over" then
        G.msg_t = G.msg_t + (G.fdt or 0)
        local a = min(1, (4.0 - G.msg_t) * 2)
        if a <= 0 then G.msg = nil else text(G.msg, w / 2, my - 30 * u, 21 * u, col4(G.msg_col or CREAM, a), "center", 23, 1100 * u) end
    end
    if warn then text(warn, w / 2, my - 64 * u, 20 * u, warn_col or OCHRE, "center", 23, 1300 * u) end
    G.break_warning = nil
    if breaks and not st.over and not G.guide then
        G.break_warning = string.format("This row does not carry the path on: lay PATH (2) on an outlined cell (COMING UP)   ·   the loom beats in %d s", math.ceil(st.timer))
        local bw = 1180 * u
        rect((w - bw) / 2, my - 116 * u, bw, 40 * u, { 0.18, 0.05, 0.03, 0.72 }, 22, 10 * u, col4(BAD, 0.8))
        text(G.break_warning, w / 2, my - 96 * u, 20 * u, BAD, "center", 23, bw - 30 * u)
    end
    text("LEFT/RIGHT move   ·   1-9 lay   ·   BACKSPACE take back   ·   SPACE beat the row in   ·   Esc pause", w / 2, my, 15 * u, DIM, "center", 23, 1400 * u)
    -- click targets over the cells of the row being woven (projected from the camera)
    for c = 0, R.COLS - 1 do
        local x1, y1 = W.project(W.col_x(c) - D.CELL / 2, D.CELL, D.Z0, w, h)
        local x2, y2 = W.project(W.col_x(c) + D.CELL / 2, 0, D.Z0, w, h)
        catcher("cell" .. c, x1, y1, x2 - x1, y2 - y1, 26)
    end
end
local function hide_hud() for _, id in ipairs(CHIP_IDS) do hide(id) end end

------------------------------------------------------------------ the frame
SET:apply()
pcall(runtime_ui.clear, SCREEN)
pcall(runtime_ui.set_screen_overlay, SCREEN, true)
pcall(runtime_ui.show, SCREEN)
layout()
start_attract()
G.manual = false            -- the look console (loom.state) owns the frame: the game draws nothing
function G.cursor_visible() return G.mode == "run" and not G.manual and S.st and not S.st.over end

function G.update(raw)
    if layout() then for id in pairs(widgets) do widgets[id] = true; hide(id) end end
    G.fdt, G.t = raw, G.t + raw
    clock = clock + raw
    G.card_t = G.card_t + raw
    if G.manual then for id in pairs(widgets) do hide(id) end; flush_pools(); return end
    ambience(true)
    local esc = press("Escape")
    if press("M") then SET:toggle_mute() end
    local menu = SET:update(raw)
    if menu then
        flush_keys()
    elseif G.howto then
        howto_controls(raw, esc)
    elseif G.pause then
        pause_controls(raw, esc)
    elseif esc then
        sound("click")
        if G.mode == "over" then to_title() else open_pause() end
    elseif G.mode == "title" then
        title_controls()
    elseif G.mode == "over" then
        over_controls(false)
    elseif G.mode == "run" then
        run_controls()
    end
    G.pressed_override = nil
    local paused = G.pause ~= nil or G.howto ~= nil or (SET:is_open() and G.mode == "run")
    -- the guided first run: the loom waits (no clock) until the first row is beaten in
    if G.guide and G.mode == "run" and S.st then
        G.guide.t = G.guide.t + raw
        if G.guide.step <= 2 then S.st.timer = R.beat_time(S.st.level) end
        if G.guide.step == 1 then local _, br = G.marks(S.st); if not br then G.guide.step, G.guide.t = 2, 0 end end
        if G.guide.step == 2 then local _, br = G.marks(S.st); if br then G.guide.step = 1 end end
        if (G.guide.step == 3 and G.guide.beats >= 4) or (G.guide.step == 4 and G.guide.t > 6) or S.st.over then end_guide() end
    end
    local st = S.st
    -- the title's weaver: a row every 2.4 s; a new cloth when its run ends
    if G.mode == "title" and st and not paused then
        G.attract_t = (G.attract_t or 0) + raw
        if st.over then
            if G.attract_t > 3 then start_attract() end
        elseif G.attract_t > 2.4 and not L.busy() and S.phase == "weave" then
            G.attract_t = 0
            R.bot_weave(st)
        end
        st.timer = R.beat_time(st.level)          -- the clock never beats a title row
    end
    if not paused then L.play_frame(raw) end
    st = S.st
    if st then on_events(st, G.mode ~= "title") end
    if G.mode == "run" and st.over then
        if not G.end_shown then G.end_shown = true; finish_run(st); G.end_t = 0 end
        G.end_t = G.end_t + raw
        if G.end_t > 1.6 and S.phase == "weave" then G.mode, G.card_t = "over", 0 end
    end
    S.pirn = R.KINDS[G.sel].wool
    -- draw
    local a = min(1, G.card_t * 4)
    if not SET:is_open() then
        if G.mode == "title" and not G.pause and not G.howto then draw_title(a) else for _, id in ipairs(TITLE_IDS) do hide(id) end end
        if G.mode == "run" or G.mode == "over" then draw_hud() else hide_hud() end
        if G.mode == "over" then draw_over(a) else for _, id in ipairs(OVER_IDS) do hide(id) end end
    else
        for _, id in ipairs(TITLE_IDS) do hide(id) end
        for _, id in ipairs(OVER_IDS) do hide(id) end
        hide_hud()
    end
    draw_pause()
    if G.howto and not SET:is_open() then draw_howto() else for _, id in ipairs(HOWTO_IDS) do hide(id) end end
    if G.guide and G.mode == "run" and not G.pause and not G.howto and not SET:is_open() then draw_guide() else hide("g_skip") end
    flush_pools()
end

-- Console / testing helpers
function G.info()
    local st = S.st
    return string.format("howto=%s guide=%s " .. "mode=%s pause=%s settings=%s seed=%s best=%d best_rows=%d runs=%d sounds=%d last_sound=%s score=%s over=%s K=%s msg=%s",
        tostring(G.howto and G.howto.page), tostring(G.guide and G.guide.step), G.mode, tostring(G.pause ~= nil), tostring(SET:is_open()), tostring(G.seed), save.best, save.best_rows, save.runs,
        G.sounds_played or 0, tostring(G.last_sound), tostring(st and st.score), tostring(st and st.over), tostring(st and st.K), tostring(G.msg))
end
function G.keys(list) G.pressed_override = {}; for _, k in ipairs(list) do G.pressed_override[k] = true end end
return G
end
