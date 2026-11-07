-- Kite Hill (PhasmaEngine, Lua): fly a cloth kite through numbered ribbon gates above the hills and race three
-- rival kites. Steer toward the pointer (or turn with A / D, the arrow keys), ride the gusts, Space for an updraft.
-- Finish high enough to go on to a harder heat; coins buy kite upgrades and new kites at the workshop (kept
-- between runs). kitehill_rules.lua: rules and flight. kitehill_world.lua: the 3D scene. This file: flow,
-- input, sounds and the HUD.
local function module(path)
    local source = assert(fs.read(path), "Missing Kite Hill module: " .. path)
    return assert(load(source, "@" .. path, "t", _ENV))()
end
local R = module("Scripts/kitehill_rules.lua")
local World = module("Scripts/kitehill_world.lua")(R)
local SettingsMenu = module("Scripts/Lib/settings_menu.lua") -- shared menu, same copy as the other games

local SCREEN = "kitehill"
local floor, min, max, abs, sin, cos, sqrt = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt
local CLEAR = { 0, 0, 0, 0 }
local PAPER = { 0.98, 0.95, 0.87, 0.94 }
local PAPER_HI = { 1.0, 0.98, 0.92, 0.98 }
local RIM = { 0.70, 0.36, 0.20, 1 }
local INK = { 0.26, 0.16, 0.09, 1 }
local INK_SOFT = { 0.42, 0.30, 0.20, 1 }
local TERRA = { 0.74, 0.34, 0.18, 1 }
local GOLD = { 0.88, 0.62, 0.16, 1 }
local SAGE = { 0.36, 0.52, 0.28, 1 }
local CREAM = { 0.99, 0.96, 0.88, 1 }
local BAD = { 0.78, 0.26, 0.16, 1 }
local DIM = { 0.55, 0.47, 0.38, 1 }

local SAVE_PATH = "Save/kitehill_save.txt"
local save = R.load_save(fs.read(SAVE_PATH))
local S = { mode = "title", t = 0, card_t = 0, pops = {}, after_shop = "title" }
local run, race
local L = {}
_G.kitehill = { S = S, R = R, W = World, save = function() return save end, run = function() return run end,
    race = function() return race end, autoplay = false }

local function write_save() pcall(fs.write, SAVE_PATH, R.save_text(save)) end

-- Cap overlapping voices (the engine aborts when about 32 sounds overlap).
local LEN = { chime1 = 0.9, chime2 = 0.9, chime3 = 0.9, chime4 = 0.9, chime5 = 0.9, bull = 1.2, crash = 0.8, relaunch = 0.6,
    gust = 2.4, warn = 0.8, boost = 0.9, count = 0.4, go = 1.2, finish = 1.6, win = 2.4, over = 2.4, coin = 0.5, click = 0.07,
    rival = 0.7 }
local MAX_VOICES, voices, clock = 14, {}, 0
local function sound(name)
    if not (audio and audio.play) then return end
    for i = #voices, 1, -1 do if voices[i] <= clock then table.remove(voices, i) end end
    if #voices >= MAX_VOICES then return end
    voices[#voices + 1] = clock + (LEN[name] or 2)
    pcall(audio.play, name .. ".wav")
end
local SET = SettingsMenu.new({ title = "SETTINGS", subtitle = "KITE HILL", click = function() sound("click") end,
    theme = { accent = { 0.80, 0.42, 0.22, 1 }, accent2 = { 0.92, 0.66, 0.26, 1 }, text = { 0.99, 0.96, 0.88, 1 }, selected_text = { 1, 0.98, 0.92, 1 } },
    on_graphics = function() pcall(settings.set, "taa", true); pcall(settings.set, "fxaa", false) end })
_G.kitehill.settings = SET
World.particle_scale = function() return SET:particle_scale() end
World.shake_scale = function() return SET:shake_scale() end

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
local function catcher(id, x, y, w, h, z) quad(id, { style = "text", label = "", x = x, y = y, width = w, height = h, z = z or 60, no_input = false }) end
local function state(id) return runtime_ui.get_state(SCREEN, id) end
local function clicked(id) local s = state(id); return s and s.clicked == true end
local function hovered(id) local s = state(id); return s and s.hovered == true end
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
    L.w, L.h = w, h
    return true
end
local u = 1
local function col4(c, a) return { c[1], c[2], c[3], (c[4] or 1) * (a or 1) } end
local function rect(x, y, w, h, fill, z, r, border)
    quad(pid("r"), { style = "text", label = "", x = x, y = y, width = w, height = h, z = z or 30, fill = fill, border = border, corner_radius = r or 0 })
end
-- Text with its em size px centred on y. shadow: a soft dark copy under it (for text over the scene).
local function text(s, x, y, px, color, align, z, w, shadow)
    local h = px * 1.6
    local bw = w or max(60, #s * px * 0.75)
    local bx = align == "left" and x or (align == "right" and x - bw or x - bw / 2)
    if shadow then
        local a = (color[4] or 1)
        quad(pid("t"), { style = "text", label = s, x = bx + px * 0.05, y = y - h / 2 + px * 0.07, width = bw, height = h, z = (z or 40) - 0.5,
            font_scale = px / 16, text_color = { 0.12, 0.08, 0.04, 0.6 * a }, align_h = align or "center", align_v = "middle" })
    end
    quad(pid("t"), { style = "text", label = s, x = bx, y = y - h / 2, width = bw, height = h, z = z or 40,
        font_scale = px / 16, text_color = color, align_h = align or "center", align_v = "middle" })
end
local function panel(x, y, w, h, z, fill, rim, r)
    r = (r or 14) * u
    quad(pid("p"), { style = "text", label = "", x = x, y = y, width = w, height = h, z = z, fill = fill or PAPER, border = rim or RIM, corner_radius = r })
end
local function ordinal(n) return n .. (({ "st", "nd", "rd" })[n] or "th") end
local function ease_back(t) t = max(0, min(1, t)); local c = 1.7; return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2 end
local function kite_color(i)
    local d = R.design(race and race.kites[i] and race.kites[i].design or save.design)
    local c = World.PAINT[d.panels[2] == "white" and d.panels[1] or d.panels[2]] or World.PAINT.cream
    if d.panels[1] == "cream" and d.panels[2] ~= "cream" then c = World.PAINT[d.panels[2]] end
    return { c[1] ^ 0.45, c[2] ^ 0.45, c[3] ^ 0.45, 1 }      -- linear paint -> display-ish
end

------------------------------------------------------------------ flow
local function designs_for_race()
    local t = { save.design }
    for i, rv in ipairs(R.RIVALS) do t[i + 1] = rv.design end
    return t
end
local function start_race()
    race = run:new_race()
    World.setup(race, designs_for_race())
    S.mode, S.card_t, S.pops, S.end_t = "race", 0, {}, nil
    S.pointer_active = false
end
local function new_run()
    run = R.new_run(save)
    write_save()
    start_race()
end
_G.kitehill.new_run = new_run
_G.kitehill.start_race = start_race
local function open_shop(after)
    S.after_shop = after
    S.mode, S.card_t = "shop", 0
end
local function close_shop()
    write_save()
    if S.after_shop == "next" then start_race()
    else S.mode, S.card_t = S.after_shop == "over" and "over" or "title", 0 end
end
local function race_over()
    S.outcome = run:finish_race()
    write_save()
    S.mode, S.card_t = S.outcome == "advance" and "results" or "over", 0
    sound(S.outcome == "advance" and "win" or "over")
end

------------------------------------------------------------------ race events: sounds, pops, effects
local function pop(x, h, s, kind, color)
    S.pops[#S.pops + 1] = { x = x, h = h, s = s, kind = kind or "pt", t = 0, color = color }
end
local function on_event(ev)
    local k = ev.k and race.kites[ev.k]
    if ev.kind == "count" then sound("count")
    elseif ev.kind == "go" then sound("go")
    elseif ev.kind == "pass" then
        local g = race.gates[ev.gate]
        if ev.k == 1 then
            World.confetti(g.x, g.h, ev.bull)
            sound("chime" .. min(5, (ev.gate - 1) % 5 + 1))
            if ev.bull then sound("bull"); pop(g.x, g.h + g.r + 0.6, "BULLSEYE +2", "big", GOLD)
            else pop(g.x, g.h + g.r + 0.6, "+1", "pt") end
        else
            sound("rival")
        end
    elseif ev.kind == "crash" then
        World.puff(ev.x, ev.h)
        sound("crash")
        if ev.k == 1 then pop(ev.x, ev.h + 1.6, "CRASHED", "big", BAD) end
    elseif ev.kind == "relaunch" then
        if ev.k == 1 then sound("relaunch") end
    elseif ev.kind == "boost" then
        sound("boost")
        World.boost_fx(k.x, k.h, k.a)
    elseif ev.kind == "gust_warn" then sound("warn")
    elseif ev.kind == "gust" then
        sound("gust")
        local g = race.gusts[ev.gust]
        S.gust_fx = { vx = g.vx, vh = g.vh, until_t = race.t + g.dur }
    elseif ev.kind == "finish" then
        if ev.k == 1 then sound("finish") end
        pop(k.x, k.h + 1.8, ordinal(ev.place), "big", ev.k == 1 and GOLD or CREAM)
    elseif ev.kind == "decided" then
        S.end_t = 0
    end
end

------------------------------------------------------------------ input
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
local KEYS = { "M", "Return", "Space", "W", "Escape" }
local function key(k) return input.is_key_down_raw(k) == true end

-- The autoplay hook (tests, captures): fly at the next ring's centre, climbing away from the grass.
local function bot_input()
    local k = race.kites[1]
    local g = race.gates[k.gate]
    if not g then return { tx = k.launch, th = R.FIELD.h1 - 3 } end
    if k.h - R.floor(k.x) < 1.8 and sin(k.a) < 0.3 then return { tx = k.x, th = k.h + 5 } end
    return { tx = g.x, th = g.h, boost = race.t > 4 and race.t < 4.1 }
end

local function race_input()
    if _G.kitehill.autoplay then return bot_input() end
    local inp = {}
    local turn = 0
    if key("A") or key("Left") then turn = turn + 1 end
    if key("D") or key("Right") then turn = turn - 1 end
    local st = state("field")
    if st and st.mouse_x then
        if S.last_mx and (abs(st.mouse_x - S.last_mx) > 2 or abs(st.mouse_y - S.last_my) > 2) then S.pointer_active = true end
        S.last_mx, S.last_my = st.mouse_x, st.mouse_y
    end
    if turn ~= 0 then
        S.pointer_active = false
        inp.turn = turn
    elseif S.pointer_active and S.last_mx then
        local x, h = World.plane_point(S.last_mx, S.last_my)
        if x then inp.tx, inp.th = x, h; S.aim = { x = x, h = h } end
    else
        inp.turn = 0
    end
    if not S.pointer_active then S.aim = nil end
    inp.boost = pressed("Space") or (st and st.right_clicked == true)
    return inp
end

local function controls(dt)
    if pressed("M") then SET:toggle_mute() end
    local enter = pressed("Return")
    local wkey = pressed("W")
    if S.mode == "title" then
        if S.card_t > 0.3 and (enter or clicked("btn_card")) then sound("click"); new_run()
        elseif wkey or clicked("btn_alt") then sound("click"); open_shop("title") end
    elseif S.mode == "race" then
        local inp = race_input()
        local evs = R.step(race, dt, inp)
        for _, ev in ipairs(evs) do on_event(ev) end
        if S.end_t and S.mode == "race" then
            S.end_t = S.end_t + dt
            if S.end_t > 1.8 then race_over() end
        end
    elseif S.mode == "results" then
        R.step(race, dt, { turn = 0 })
        if S.card_t > 0.4 and (enter or clicked("btn_card")) then sound("click"); start_race()
        elseif wkey or clicked("btn_alt") then sound("click"); open_shop("next") end
        if _G.kitehill.autoplay and S.card_t > 1 then start_race() end
    elseif S.mode == "over" then
        R.step(race, dt, { turn = 0 })
        if S.card_t > 0.6 and (enter or clicked("btn_card")) then sound("click"); new_run()
        elseif wkey or clicked("btn_alt") then sound("click"); open_shop("over") end
        if _G.kitehill.autoplay and S.card_t > 1.2 then new_run() end
    elseif S.mode == "shop" then
        for i, up in ipairs(R.UPGRADES) do
            if clicked("up" .. i) then
                if R.buy(save, up.id) then sound("coin"); write_save() else sound("click"); S.deny = 1 end
            end
        end
        for i, d in ipairs(R.DESIGNS) do
            if not d.rival and clicked("ds" .. i) then
                local was = save.design
                if R.buy(save, "design:" .. d.id) then
                    sound(save.owned[d.id] and was ~= d.id and "click" or "coin"); write_save()
                else sound("click"); S.deny = 1 end
            end
        end
        if S.card_t > 0.3 and (enter or wkey or clicked("btn_card")) then sound("click"); close_shop() end
    end
end

local function step(dt)
    S.t = S.t + dt
    S.card_t = S.card_t + dt
    for i = #S.pops, 1, -1 do
        local q = S.pops[i]
        q.t = q.t + dt
        if q.t > (q.kind == "big" and 1.5 or 0.9) then table.remove(S.pops, i) end
    end
    S.deny = max(0, (S.deny or 0) - dt * 2)
    if S.gust_fx and race and race.t < S.gust_fx.until_t then
        S.gust_acc = (S.gust_acc or 0) + dt
        if S.gust_acc > 0.12 then S.gust_acc = 0; World.gust_fx(S.gust_fx.vx, S.gust_fx.vh) end
    end
end

------------------------------------------------------------------ HUD
local function hud()
    local w, h = L.w, L.h
    local me = race.kites[1]
    local H = race.H
    -- Top left: the heat and what it takes.
    panel(22 * u, 18 * u, 330 * u, 96 * u, 39, PAPER, RIM, 16)
    text("KITE HILL", 42 * u, 48 * u, 34 * u, TERRA, "left", 41, 300 * u)
    text("Heat " .. race.n .. "  ·  finish " .. R.need_text(H.need), 44 * u, 88 * u, 19 * u, INK, "left", 41, 300 * u)
    -- Top centre: live place, rings, time.
    local place = R.place(race, 1)
    local cw = 380 * u
    local cx = w / 2
    panel(cx - cw / 2, 18 * u, cw, 96 * u, 39, PAPER, RIM, 16)
    local ok = place <= H.need
    text(me.finished and ordinal(race.place or place) or ordinal(place), cx - 110 * u, 64 * u, 52 * u, ok and SAGE or BAD, "center", 41, 160 * u)
    text("RING", cx + 40 * u, 44 * u, 15 * u, INK_SOFT, "center", 41, 100 * u)
    text(min(#race.gates, me.gate - (me.finished and 1 or 0)) .. "/" .. #race.gates, cx + 40 * u, 76 * u, 32 * u, INK, "center", 41, 120 * u)
    text("TIME", cx + 130 * u, 44 * u, 15 * u, INK_SOFT, "center", 41, 100 * u)
    text(string.format("%.1f", max(0, me.finished or race.t)), cx + 130 * u, 76 * u, 28 * u, INK, "center", 41, 120 * u)
    -- Top right: coins and updrafts.
    local rx = w - 22 * u - 300 * u
    panel(rx, 18 * u, 300 * u, 96 * u, 39, PAPER, RIM, 16)
    quad(pid("coin"), { style = "text", label = "", x = rx + 20 * u, y = 36 * u, width = 26 * u, height = 26 * u, z = 41,
        fill = { 0.92, 0.68, 0.24, 1 }, border = { 0.70, 0.46, 0.12, 1 }, corner_radius = 13 * u })
    text(tostring(save.coins), rx + 56 * u, 50 * u, 26 * u, INK, "left", 41, 100 * u)
    text("coins", rx + 120 * u, 52 * u, 16 * u, INK_SOFT, "left", 41, 80 * u)
    text("UPDRAFT", rx + 20 * u, 90 * u, 15 * u, INK_SOFT, "left", 41, 100 * u)
    local nb = 1 + save.updraft
    for i = 1, nb do
        local full = i <= me.boosts
        quad(pid("bst"), { style = "text", label = "", x = rx + 112 * u + (i - 1) * 30 * u, y = 80 * u, width = 22 * u, height = 22 * u, z = 41,
            fill = full and col4(GOLD, 1) or CLEAR, border = full and { 0.6, 0.4, 0.1, 1 } or DIM, corner_radius = 11 * u })
    end
    text("Space", rx + 280 * u, 90 * u, 14 * u, DIM, "right", 41, 80 * u)
    -- Standings, right side.
    local list = R.standings(race)
    local sy = 130 * u
    panel(w - 22 * u - 210 * u, sy, 210 * u, 30 * u + #list * 34 * u, 39, PAPER, RIM, 14)
    for p, k in ipairs(list) do
        local y = sy + 30 * u + (p - 1) * 34 * u
        local c = kite_color(k.i)
        text(ordinal(p), w - 214 * u, y, 18 * u, p <= H.need and SAGE or DIM, "left", 41, 50 * u)
        quad(pid("sw"), { style = "text", label = "", x = w - 160 * u, y = y - 9 * u, width = 18 * u, height = 18 * u, z = 41, fill = c,
            border = INK_SOFT, corner_radius = 4 * u })
        text(k.i == 1 and "You" or k.name, w - 132 * u, y, 18 * u, k.i == 1 and TERRA or INK, "left", 41, 100 * u)
        text(k.finished and "in" or tostring(k.gate - 1), w - 44 * u, y, 18 * u, INK_SOFT, "right", 41, 40 * u)
    end
    text("place", w - 127 * u, sy + 4 * u + 9 * u, 13 * u, DIM, "center", 41, 200 * u)
    -- Gust banner.
    local g, lead = R.gust_now(race)
    if g and S.mode == "race" then
        local right = g.vx > 0
        local msg = lead > 0 and string.format(right and "GUST >  in %.1f" or "GUST <  in %.1f", lead) or (right and "GUST  >>>" or "<<<  GUST")
        local a = lead > 0 and (0.6 + 0.4 * sin(S.t * 10)) or 1
        local bw = 300 * u
        panel(cx - bw / 2, 126 * u, bw, 46 * u, 39, col4(PAPER, a), col4(GOLD, a), 14)
        text(msg, cx, 149 * u, 24 * u, col4(lead > 0 and INK or TERRA, a), "center", 41, bw)
    end
end

local function scene_labels()
    local me = race.kites[1]
    -- Ring numbers: the player's next ring (big, gold) and the two after it.
    for j = me.gate, min(#race.gates, me.gate + R.SHOWN - 1) do
        local g = race.gates[j]
        local sx, sy = World.plane_project(g.x, g.h + g.r + 0.25)
        -- Under the top bar? Put the number under the ring instead.
        if sy and sy < 150 * u then sx, sy = World.plane_project(g.x, g.h - g.r - 0.25); sy = sy and sy + 46 * u end
        if sx then
            local nxt = j == me.gate
            local px = (nxt and 34 or 22) * u
            local r = px * 0.8
            quad(pid("gb"), { style = "text", label = "", x = sx - r, y = sy - r * 1.4, width = 2 * r, height = 2 * r, z = 33,
                fill = nxt and col4(GOLD, 0.95) or col4(PAPER, 0.85), border = nxt and { 0.55, 0.35, 0.08, 1 } or col4(RIM, 0.8), corner_radius = r })
            text(tostring(j), sx, sy - r * 0.4, px * 0.95, nxt and CREAM or INK, "center", 34, 2 * r)
        end
    end
    -- Name tags over the kites.
    for i, k in ipairs(race.kites) do
        local sx, sy = World.plane_project(k.x, k.h + 1.5)
        if sx then
            if i > 1 then
                text(k.name, sx, sy, 15 * u, col4(CREAM, 0.9), "center", 32, 120 * u, true)
            elseif race.t < 2 then
                text("YOU", sx, sy - 6 * u, 20 * u, GOLD, "center", 32, 120 * u, true)
            end
        end
    end
    -- Where the pointer is steering.
    if S.aim and S.mode == "race" and not me.finished then
        local ax, ay = World.plane_project(S.aim.x, S.aim.h)
        if ax then
            local r = 9 * u
            quad(pid("aim"), { style = "text", label = "", x = ax - r, y = ay - r, width = 2 * r, height = 2 * r, z = 33,
                fill = CLEAR, border = { 1, 0.96, 0.86, 0.8 }, corner_radius = r })
        end
    end
    for _, q in ipairs(S.pops) do
        local sx, sy = World.plane_project(q.x, q.h)
        if sx then
            local a = 1 - max(0, q.t - (q.kind == "big" and 1.1 or 0.55)) / 0.4
            local s = q.kind == "big" and (0.6 + 0.4 * ease_back(q.t * 4)) or (0.7 + 0.3 * ease_back(q.t * 6))
            text(q.s, sx, sy - q.t * 40 * u, (q.kind == "big" and 36 or 28) * u * s, col4(q.color or CREAM, a), "center", 45, 400 * u, true)
        end
    end
    -- Countdown.
    if race.t < 0.8 then
        local n = race.t < 0 and math.ceil(-race.t) or 0
        local frac = race.t < 0 and (-race.t - floor(-race.t)) or (1 - race.t / 0.8)
        local s = ease_back((1 - frac) * 3)
        text(n > 0 and tostring(n) or "GO!", L.w / 2, L.h * 0.42, 120 * u * max(0.2, s), col4(n > 0 and CREAM or GOLD, n > 0 and 1 or frac), "center", 70, 600 * u, true)
        if race.t < 0 then
            text("Fly through the rings in order. Steer toward the pointer, or A / D.", L.w / 2, L.h * 0.42 + 100 * u, 24 * u, CREAM, "center", 70, 1200 * u, true)
        end
    end
    if S.end_t and S.mode == "race" then
        local msg = race.outcome == "advance" and ("You finished " .. ordinal(race.place) .. "!") or "Not this time..."
        local a = min(1, S.end_t * 4)
        text(msg, L.w / 2, L.h * 0.4, 64 * u, col4(race.outcome == "advance" and GOLD or CREAM, a), "center", 70, 1200 * u, true)
    end
end

local function button(id, label, x, y, w, h, primary, a)
    local hov = hovered(id)
    panel(x, y, w, h, 83, col4(primary and (hov and { 0.82, 0.42, 0.22, 1 } or TERRA) or (hov and PAPER_HI or { 0.94, 0.89, 0.78, 1 }), a),
        col4(primary and { 0.55, 0.24, 0.1, 1 } or RIM, a), 14)
    text(label, x + w / 2, y + h / 2, 24 * u, col4(primary and CREAM or INK, a), "center", 84, w)
    catcher(id, x, y, w, h, 85)
end

local function draw_cards()
    local w, h = L.w, L.h
    local show = S.mode == "title" or S.mode == "results" or S.mode == "over" or S.mode == "shop"
    for i = 1, #R.UPGRADES do if S.mode ~= "shop" then hide("up" .. i) end end
    for i = 1, #R.DESIGNS do if S.mode ~= "shop" then hide("ds" .. i) end end
    if not show or SET:is_open() then hide("btn_card"); hide("btn_alt"); return end
    local a = min(1, S.card_t * 3)
    rect(0, 0, w, h, { 0.12, 0.10, 0.06, 0.35 * a }, 80)
    local cw, ch = 900 * u, 520 * u
    if S.mode == "shop" then cw, ch = 1380 * u, 820 * u end
    local x, y = (w - cw) / 2, (h - ch) / 2 + (1 - ease_back(S.card_t * 2.5)) * 30 * u
    panel(x, y, cw, ch, 81, col4(PAPER, a), col4(RIM, a), 22)
    local cx = x + cw / 2
    local btn, alt = nil, nil
    if S.mode == "title" then
        text("KITE HILL", cx, y + 86 * u, 92 * u, col4(TERRA, a), "center", 82, cw)
        text("Fly your kite through the ribbon gates in order and race three rivals over the hills.", cx, y + 170 * u, 22 * u, col4(INK, a), "center", 82, cw)
        text("The kite flies toward the pointer (or turn with A / D). Turning hard costs speed.", cx, y + 210 * u, 19 * u, col4(INK_SOFT, a), "center", 82, cw)
        text("Gusts blow everyone off line: ride them. Space for an updraft. Don't touch the grass.", cx, y + 240 * u, 19 * u, col4(INK_SOFT, a), "center", 82, cw)
        text("Finish high enough for the next heat. Coins buy upgrades and kites at the workshop.", cx, y + 270 * u, 19 * u, col4(INK_SOFT, a), "center", 82, cw)
        text((save.best > 0 and ("Best: heat " .. save.best .. "   ·   ") or "") .. save.coins .. " coins", cx, y + 326 * u, 22 * u, col4(GOLD, a), "center", 82, cw)
        btn, alt = "FLY  ·  Enter", "WORKSHOP  ·  W"
    elseif S.mode == "results" then
        text("HEAT " .. race.n .. ": " .. ordinal(race.place):upper(), cx, y + 80 * u, 64 * u, col4(SAGE, a), "center", 82, cw)
        local me = race.kites[1]
        text(string.format("%.1f s   ·   %d rings, %d bullseyes, %d crashes", me.finished or race.t, me.passes, me.bulls, me.crashes), cx, y + 150 * u, 22 * u, col4(INK, a), "center", 82, cw)
        text("+" .. (race.coins or 0) .. " coins", cx, y + 208 * u, 40 * u, col4(GOLD, a), "center", 82, cw)
        local H2 = R.heat(run.heat)
        text(string.format("Next: heat %d  ·  %d rings  ·  finish %s", run.heat, H2.gates, R.need_text(H2.need)), cx, y + 270 * u, 20 * u, col4(INK_SOFT, a), "center", 82, cw)
        text("Rivals get quicker, the rings smaller and the gusts stronger.", cx, y + 302 * u, 18 * u, col4(INK_SOFT, a), "center", 82, cw)
        btn, alt = "NEXT HEAT  ·  Enter", "WORKSHOP  ·  W"
    elseif S.mode == "over" then
        text("OUT IN HEAT " .. race.n, cx, y + 80 * u, 62 * u, col4(TERRA, a), "center", 82, cw)
        text("You came " .. ordinal(race.place or 4) .. ": the heat needed " .. R.need_text(race.H.need) .. ".", cx, y + 150 * u, 24 * u, col4(INK, a), "center", 82, cw)
        text("This run: " .. (run.heat - 1) .. (run.heat - 1 == 1 and " heat" or " heats") .. " cleared, +" .. run.earned .. " coins", cx, y + 200 * u, 24 * u, col4(INK, a), "center", 82, cw)
        text("Best: heat " .. save.best .. "   ·   " .. save.coins .. " coins to spend", cx, y + 250 * u, 22 * u, col4(GOLD, a), "center", 82, cw)
        text("Coins and upgrades stay with you for the next run.", cx, y + 290 * u, 18 * u, col4(INK_SOFT, a), "center", 82, cw)
        btn, alt = "NEW RUN  ·  Enter", "WORKSHOP  ·  W"
    else
        text("KITE WORKSHOP", cx, y + 56 * u, 54 * u, col4(TERRA, a), "center", 82, cw)
        text(save.coins .. " coins", cx, y + 104 * u, 26 * u, col4(GOLD, a), "center", 82, cw)
        local ow, oh, gap = 250 * u, 250 * u, 18 * u
        local ox0 = cx - (#R.UPGRADES * ow + (#R.UPGRADES - 1) * gap) / 2
        for i, up in ipairs(R.UPGRADES) do
            local ox, oy = ox0 + (i - 1) * (ow + gap), y + 140 * u
            local lvl, maxl = save[up.id], #up.price
            local price = R.price(save, up.id)
            local afford = price and save.coins >= price
            local hov = hovered("up" .. i) and price
            panel(ox, oy, ow, oh, 82, col4(hov and PAPER_HI or { 0.95, 0.90, 0.80, 1 }, a), col4(afford and GOLD or RIM, a), 14)
            text(up.name, ox + ow / 2, oy + 36 * u, 26 * u, col4(INK, a), "center", 84, ow)
            text(up.text, ox + ow / 2, oy + 76 * u, 16 * u, col4(INK_SOFT, a), "center", 84, ow)
            for l = 1, maxl do
                local rr = 9 * u
                local px = ox + ow / 2 + (l - (maxl + 1) / 2) * 26 * u
                quad(pid("lv"), { style = "text", label = "", x = px - rr, y = oy + 118 * u - rr, width = 2 * rr, height = 2 * rr, z = 84,
                    fill = l <= lvl and col4(TERRA, a) or CLEAR, border = col4(RIM, a), corner_radius = rr })
            end
            local bw_, bh_ = 170 * u, 50 * u
            local bx_, by_ = ox + (ow - bw_) / 2, oy + oh - bh_ - 20 * u
            panel(bx_, by_, bw_, bh_, 83, col4(price and (afford and TERRA or { 0.86, 0.80, 0.70, 1 }) or SAGE, a), col4(RIM, a), 10)
            text(price and ("BUY  " .. price) or "MAXED", bx_ + bw_ / 2, by_ + bh_ / 2, 22 * u, col4(price and (afford and CREAM or INK_SOFT) or CREAM, a), "center", 85, bw_)
            if price then catcher("up" .. i, ox, oy, ow, oh, 86) else hide("up" .. i) end
        end
        -- Kites.
        text("KITES", cx, y + 430 * u, 26 * u, col4(INK, a), "center", 82, cw)
        local list = {}
        for i, d in ipairs(R.DESIGNS) do if not d.rival then list[#list + 1] = { i = i, d = d } end end
        local dw, dh = 230 * u, 200 * u
        local dx0 = cx - (#list * dw + (#list - 1) * gap) / 2
        for n, e in ipairs(list) do
            local d = e.d
            local ox, oy = dx0 + (n - 1) * (dw + gap), y + 460 * u
            local owned, chosen = save.owned[d.id], save.design == d.id
            local afford = owned or save.coins >= d.price
            local hov = hovered("ds" .. e.i)
            panel(ox, oy, dw, dh, 82, col4(hov and PAPER_HI or { 0.95, 0.90, 0.80, 1 }, a), col4(chosen and GOLD or RIM, a), 14)
            -- The four panels as a swatch, in kite order.
            local s = 34 * u
            for j = 1, 4 do
                local c = World.PAINT[d.panels[j]] or World.PAINT.cream
                local qx = ox + dw / 2 + ((j == 1 or j == 3) and -s or 0)
                local qy = oy + 22 * u + ((j <= 2) and 0 or s)
                quad(pid("sw"), { style = "text", label = "", x = qx, y = qy, width = s, height = s, z = 84,
                    fill = { c[1] ^ 0.45, c[2] ^ 0.45, c[3] ^ 0.45, a }, border = col4(INK_SOFT, a), corner_radius = 3 * u })
            end
            text(d.name, ox + dw / 2, oy + 118 * u, 22 * u, col4(INK, a), "center", 84, dw)
            text(chosen and "FLYING" or (owned and "CHOOSE" or ("BUY  " .. d.price)), ox + dw / 2, oy + 160 * u, 20 * u,
                col4(chosen and SAGE or (afford and TERRA or DIM), a), "center", 84, dw)
            if not chosen then catcher("ds" .. e.i, ox, oy, dw, dh, 86) else hide("ds" .. e.i) end
        end
        if (S.deny or 0) > 0 then text("Not enough coins.", cx, y + ch - 132 * u, 20 * u, col4(BAD, S.deny), "center", 84, 600 * u) end
        btn = S.after_shop == "next" and "NEXT HEAT  ·  Enter" or "DONE  ·  Enter"
    end
    local bw, bh = 340 * u, 66 * u
    local by = y + ch - 96 * u
    if alt then
        button("btn_card", btn, cx - bw - 12 * u, by, bw, bh, true, a)
        button("btn_alt", alt, cx + 12 * u, by, bw, bh, false, a)
    else
        button("btn_card", btn, cx - bw / 2, by, bw, bh, true, a)
        hide("btn_alt")
    end
end

local function present(dt)
    if layout() then for id in pairs(widgets) do widgets[id] = true; hide(id) end end
    local w, h = L.w, L.h
    u = min(w / 1920, h / 1080)
    World.update(dt, race)
    if S.mode == "race" and not SET:is_open() then catcher("field", 0, 0, w, h, 1) else hide("field") end
    local demo = S.mode == "title" or (S.mode == "shop" and S.after_shop == "title")
    if race and not demo then
        hud()
        scene_labels()
    end
    draw_cards()
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
-- A quiet course behind the title card: the rivals fly it while you read.
run = R.new_run(R.new_save(), 1)
race = run:new_race()
race.t = 0
World.setup(race, designs_for_race())
if audio and audio.play_music then pcall(audio.play_music, "breeze.wav") end
present(0)

local smooth_dt
script.on_update("kitehill", function()
    local raw = max(0, min(0.05, engine.get_metrics().delta_ms / 1000))
    smooth_dt = smooth_dt and smooth_dt + (raw - smooth_dt) * 0.1 or raw
    local dt = smooth_dt
    clock = clock + dt
    local esc = pressed("Escape")
    if SET:update(dt) then
        for _, k in ipairs(KEYS) do pressed(k) end
    elseif esc then
        sound("click"); SET:open()
    else
        if S.mode == "title" or (S.mode == "shop" and S.after_shop == "title") then
            -- The demo course behind the title card: everyone flies it (the player's kite on autopilot), then again.
            R.step(race, dt, bot_input())
            local all = true
            for _, k in ipairs(race.kites) do if not k.finished then all = false end end
            if all or race.t > 60 then
                race = run:new_race(); race.t = 0
                World.setup(race, designs_for_race())
            end
        end
        controls(dt)
        step(dt)
    end
    present(dt)
end, "play")

print("[KiteHill] Ready. Steer toward the pointer or A/D, Space updraft, Esc settings, M mute.")
