-- Echo Chamber (PhasmaEngine, Lua): place reflectors, forks, resonators and dampers, then send one
-- sound pulse from the horn so it rings every bell in numbered order.
-- echo_rules.lua: rules and chamber generator. echo_world.lua: the 3D chamber. This file: flow, input
-- and the runtime-UI HUD on top.
local function module(path)
    local source = assert(fs.read(path), "Missing Echo Chamber module: " .. path)
    return assert(load(source, "@" .. path, "t", _ENV))()
end
local R = module("Scripts/echo_rules.lua")
local World = module("Scripts/echo_world.lua")(R)
local SettingsMenu = module("Scripts/Lib/settings_menu.lua") -- shared menu, same copy as the other games

local SCREEN = "echo"
local floor, min, max, abs, sin, cos = math.floor, math.min, math.max, math.abs, math.sin, math.cos
local CLEAR = { 0, 0, 0, 0 }
local WHITE = { 1, 1, 1, 1 }
local DIM = { 0.62, 0.66, 0.84, 1 }
local GOLD = { 1, 0.8, 0.32, 1 }
local GOOD = { 0.45, 1.0, 0.7, 1 }
local BAD = { 1.0, 0.35, 0.36, 1 }
local CYAN = { 0.45, 0.9, 1, 1 }
local VIOLET = { 0.62, 0.47, 1, 1 }
local PANEL = { 0.025, 0.03, 0.075, 0.88 }

local function T(n) return "Textures/" .. n .. ".png" end
local TEX = {
    reflector = T("ic_reflector"), fork = T("ic_fork"), resonator = T("ic_resonator"), damper = T("ic_damper"),
    bell = T("ic_bell"), play = T("ic_play"), reset = T("ic_reset"), hint = T("ic_hint"), menu = T("ic_menu"),
    star = T("ic_star"), check = T("ic_check"), glow = T("glow"), ring = T("ring"), sheen = T("sheen"),
    vignette = T("vignette"), strip = T("strip"), grid = T("ic_grid"), power = T("ic_power"), back = T("ic_back"),
}
local TOOLS = R.PIECES
local LABEL = { reflector = "REFLECTOR", fork = "FORK", resonator = "RESONATOR", damper = "DAMPER" }
local DESC = {
    reflector = "bounces the pulse 90°",
    fork = "splits it in two",
    resonator = "recharges a fading pulse",
    damper = "stops a pulse dead",
}
local TIP = {
    reflector = "Reflector: click it again to flip  /  \\.  F flips the next one.",
    fork = "Fork: the pulse splits left and right of the way it came in.",
    resonator = "Resonator: tops the pulse back up to full strength, once per send.",
    damper = "Damper: a pulse that reaches it stops. Use it to cut a branch short.",
}
local TUTOR = {
    "Place the reflector so the pulse turns toward bell 1, then press SEND PULSE.",
    "Bells must ring in order. A bell reached too early spoils the whole send.",
    "Every step costs strength and every bounce costs one more. Watch the PULSE meter.",
    "A resonator refills a fading pulse. Put it where the pulse is running low.",
    "A fork splits the pulse. Both halves travel at once, so timing decides the order.",
}

local saved = tonumber(fs.read("Save/echo_chamber.txt") or "1") or 1
local S = {
    level = max(1, floor(saved)), best = max(1, floor(saved)),
    mode = "menu", t = 0, card_t = 0, menu_t = 0, tool = "reflector", flip = "/", page = 1, started = false,
    flash = 0, flash_c = BAD, banner = nil, banner_t = 0, rung = 0, fail = nil, hint = nil,
}
-- Best stars per chamber, one `chamber stars` pair per line.
S.stars_by = {}
for a, b in (fs.read("Save/echo_stars.txt") or ""):gmatch("(%d+)%s+(%d+)") do S.stars_by[tonumber(a)] = tonumber(b) end
local function save_stars()
    local out = {}
    for n, st in pairs(S.stars_by) do out[#out + 1] = n .. " " .. st end
    table.sort(out, function(a, b) return tonumber(a:match("%d+")) < tonumber(b:match("%d+")) end)
    pcall(fs.write, "Save/echo_stars.txt", table.concat(out, "\n"))
end
local function progress()
    local solved, stars = 0, 0
    for _, st in pairs(S.stars_by) do solved = solved + 1; stars = stars + st end
    return solved, stars
end

local game
local L = {}
local hover = nil
_G.echo = { S = S, R = R, W = World, game = function() return game end }

local function sound(name) if audio and audio.play then pcall(audio.play, name .. ".wav") end end
-- Frequent sounds have several baked takes; pick one so repeats never sound mechanical.
local VARIANTS = { send = 3, bounce = 5, split = 2, absorb = 3, place = 3 }
local last_take = {}
local function sfx(name)
    local n = VARIANTS[name]
    if not n then return sound(name) end
    local k = math.random(n)
    if k == last_take[name] then k = k % n + 1 end
    last_take[name] = k
    sound(name .. k)
end
local SET = SettingsMenu.new({ title = "SETTINGS", subtitle = "ECHO CHAMBER", click = function() sound("click") end,
    music = true, defaults = { music = 0.6 },   -- the music bus carries the chamber's room tone
    theme = { accent = { 0.45, 0.9, 1, 1 }, accent2 = { 1, 0.75, 0.3, 1 } },
    -- ULTRA forces shadows on in the shared menu; on this top-lit board they only blacken the tiles.
    on_graphics = function()
        settings.set("shadows", false); settings.set("taa", true); settings.set("fxaa", false)
        if World.refresh_particles then World.refresh_particles() end
    end })
_G.echo.settings = SET

------------------------------------------------------------------ widgets
local widgets = {}
local Y_OFF, X_OFF = 0, 0      -- slide offsets for the HUD group being drawn
local function quad(id, o)
    if o.y then o.y = o.y + Y_OFF end
    if o.x then o.x = o.x + X_OFF end
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
local function catcher(id, x, y, w, h, z)
    quad(id, { style = "text", label = "", x = x, y = y, width = w, height = h, z = z or 60, no_input = false })
end
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

local function col4(c, a) return { c[1], c[2], c[3], a or 1 } end
local function lerp(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * t } end
local function ease_back(t) t = max(0, min(1, t)); local c = 1.7; return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2 end

local function panel(prefix, x, y, w, h, rim, rim_a, z, radius, fill)
    local k = L.k
    radius = radius or 14 * k
    rect(prefix .. "_rim", x - 2 * k, y - 2 * k, w + 4 * k, h + 4 * k, col4(rim or VIOLET, rim_a or 0.35), z, radius + 2 * k)
    rect(prefix .. "_body", x, y, w, h, fill or PANEL, z, radius)
    image(prefix .. "_sheen", TEX.sheen, x + radius * 0.5, y + 2 * k, w - radius, h * 0.45, { 1, 1, 1, 0.05 }, z)
end
local function hide_panel(prefix) hide(prefix .. "_rim"); hide(prefix .. "_body"); hide(prefix .. "_sheen") end

local function layout()
    local surf = runtime_ui.get_surface_size()
    local w, h = surf.width or 1280, surf.height or 800
    if w <= 0 or h <= 0 then return false end
    if L.w == w and L.h == h then return false end
    L.w, L.h = w, h
    L.k = min(w / 1600, h / 1000)
    L.top, L.bot = 100 * L.k, 150 * L.k
    return true
end

------------------------------------------------------------------ flow
local function banner(s, c, sub) S.banner, S.banner_c, S.banner_sub, S.banner_t = s, c, sub, 2.6 end

local function first_tool()
    for _, k in ipairs(TOOLS) do if game:left(k) > 0 then return k end end
    for _, k in ipairs(TOOLS) do if (game.inventory[k] or 0) > 0 then return k end end
    return "reflector"
end

local function start_chamber(n)
    game = R.new(n)
    S.level = n
    if n > S.best then S.best = n; pcall(fs.write, "Save/echo_chamber.txt", tostring(S.best)) end
    S.rung, S.fail, S.hint, S.banner_t = 0, nil, nil, 0
    S.tool, S.flip = first_tool(), "/"
    World.build(game)
    World.reset_bells(1)
    S.enter_t, S.ring_at, S.bump = 0, {}, 0
    sound("assemble")
    World.set_hint(nil)
    World.set_ghost(nil)
end

-- After an edit, a finished send's bell states no longer apply.
local function edited()
    if S.rung > 0 or S.fail then World.reset_bells(1); S.rung = 0 end
    if S.fail then S.fail = nil end
end

local BOUNCE_SFX_T = 0
local function on_event(ev)
    World.event_fx(ev)
    if ev.kind == "ring" then
        S.rung = ev.bell
        S.ring_at[ev.bell] = S.t
        sound("bell" .. min(7, ev.bell))
    elseif ev.kind == "wrong" then
        sound("wrong")
        S.flash, S.flash_c = 0.8, BAD
    elseif ev.kind == "bounce" then
        if S.t - BOUNCE_SFX_T > 0.05 then sfx("bounce"); BOUNCE_SFX_T = S.t end
    elseif ev.kind == "split" then sfx("split")
    elseif ev.kind == "charge" then sound("charge")
    elseif ev.kind == "damp" then sound("damp")
    elseif ev.kind == "fade" then sound("fade")
    elseif ev.kind == "absorb" then if S.t - BOUNCE_SFX_T > 0.08 then sfx("absorb"); BOUNCE_SFX_T = S.t end
    end
end

local function fail_text(f)
    if not f then return nil end
    if f.why == "order" then return string.format("Bell %d rang before bell %d.", f.bell, f.expected) end
    if f.why == "faded" then return string.format("The pulse faded before bell %d. Shorter route, or a resonator.", f.expected) end
    return string.format("The pulse died against a wall or the edge before bell %d.", f.expected)
end

local function send()
    if World.playing() then World.skip(); return end
    if game.state == "won" then return end
    World.set_hint(nil); S.hint = nil
    World.reset_bells(1)
    S.rung, S.fail = 0, nil
    local res = game:send()
    sfx("send")
    World.fire()
    S.mode = "playing"
    World.play(res, game.strength, on_event, function()
        if res.ok then
            S.mode, S.card_t = "won", -1.5     -- the card waits while the chamber resonates
            if game.stars > (S.stars_by[game.level] or 0) then S.stars_by[game.level] = game.stars; save_stars() end
            S.star_snd = 0
            World.celebrate()
            sound("win")
            if game.level + 1 > S.best then S.best = game.level + 1; pcall(fs.write, "Save/echo_chamber.txt", tostring(S.best)) end
        else
            S.mode = "plan"
            S.fail = res.fail
            local ft = fail_text(res.fail)
            banner(res.fail.why == "order" and "OUT OF ORDER" or (res.fail.why == "faded" and "THE PULSE FADED" or "LOST IN THE WALLS"), BAD, ft)
            if res.fail.why ~= "order" then sound("lose") end
        end
    end)
end

local function clear_board()
    if World.playing() or game.state == "won" then return end
    if game:placed_count() == 0 and not World.echo then sound("deny"); return end
    game:clear_pieces()
    World.sync_pieces(game)
    World.clear_trail()
    edited()
    sound("remove")
end

local function use_hint()
    if World.playing() or game.state == "won" then return end
    local h = game:hint()
    if not h then sound("deny"); return end
    -- Free the hinted cell so the piece can go straight there.
    local p = game:piece(h.x, h.y)
    if p then game:remove(h.x, h.y); World.sync_pieces(game) end
    S.hint = h
    S.tool = h.kind
    if h.flip then S.flip = h.flip end
    World.set_hint(h)
    sound("hint")
    banner("HINT", GOLD, LABEL[h.kind] .. " on the glowing cell" .. (h.flip and ("  ( " .. h.flip .. " )") or "") .. ".  Hints cost a star.")
end

-- Into play: optionally load chamber n (a fresh build animates in), slide the HUD in, name the chamber.
local function enter_play(n)
    if n then start_chamber(n) end
    S.mode, S.enter_t, S.started = "plan", 0, true
    banner("CHAMBER " .. game.level, VIOLET, #game.bells .. " bells  ·  " .. game:total_pieces() .. " pieces")
end
-- Continue from the menu: the next chamber if this one is solved, else back to it as it was.
local function resume()
    sound("click")
    if game.state == "won" then enter_play(game.level + 1) else enter_play(not S.started and game.level or nil) end
end
local function open_menu()
    if World.playing() then World.skip(); return end
    sound("click")
    S.mode, S.menu_t = "menu", 0
    hover = nil
end
local PAGE = 30
local function open_select()
    sound("click")
    S.mode, S.menu_t = "select", 0
    S.page = floor((game.level - 1) / PAGE) + 1
end
_G.echo.send, _G.echo.start, _G.echo.hint, _G.echo.clear = send, enter_play, use_hint, clear_board
_G.echo.menu, _G.echo.select = open_menu, open_select

------------------------------------------------------------------ input
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
local KEYS = { "M", "R", "H", "F", "C", "Return", "Space", "PageUp", "PageDown", "1", "2", "3", "4" }

local function board_input(st)
    if not hover or not st or World.playing() or game.state == "won" then return end
    local x, y = hover[1], hover[2]
    local X, Z = World.cell_world(x, y)
    local p = game:piece(x, y)
    if st.right_clicked then
        if p then
            game:remove(x, y)
            World.sync_pieces(game)
            sound("remove")
            S.bump = 1
            edited()
        end
        return
    end
    if not st.clicked then return end
    if p then
        if game:rotate(x, y) then
            S.flip = p.flip
            sound("rotate")
            World.sync_pieces(game)
            edited()
        else
            sound("deny")
        end
        return
    end
    local ok, why = game:place(S.tool, x, y, S.flip)
    if ok then
        sfx("place")
        World.sync_pieces(game)
        S.bump = 1
        if S.hint and S.hint.x == x and S.hint.y == y then S.hint = nil; World.set_hint(nil) end
        edited()
        if game:left(S.tool) <= 0 then S.tool = first_tool() end
    else
        sound("deny")
        S.deny_t, S.deny_msg = 1.4, why
    end
end

local function controls()
    if pressed("M") then SET:toggle_mute() end
    local enter, space = pressed("Return"), pressed("Space")
    if S.mode == "menu" then
        if S.menu_t > 0.2 then
            if enter or space or clicked("m_play") then resume()
            elseif pressed("C") or clicked("m_select") then open_select()
            elseif clicked("m_help") then sound("click"); S.mode, S.card_t = "help", 0
            elseif clicked("m_settings") then sound("click"); SET:open()
            elseif clicked("m_quit") then sound("click"); pcall(engine.quit) end
        end
        return
    elseif S.mode == "select" then
        local pages = max(1, math.ceil((S.best + 1) / PAGE))
        if (pressed("PageDown") or clicked("sel_prev")) and S.page > 1 then S.page = S.page - 1; sound("click") end
        if (pressed("PageUp") or clicked("sel_next")) and S.page < pages then S.page = S.page + 1; sound("click") end
        if clicked("sel_back") then sound("click"); S.mode, S.menu_t = "menu", 0; return end
        for i = 1, PAGE do
            if clicked("selc" .. i) then
                local n = (S.page - 1) * PAGE + i
                if n <= S.best then sound("click"); enter_play(n) else sound("deny") end
                return
            end
        end
        return
    elseif S.mode == "help" then
        if S.card_t > 0.25 and (enter or space or clicked("btn_card")) then resume() end
        return
    elseif S.mode == "won" then
        if S.card_t > 0.6 and (enter or space or clicked("btn_card")) then
            sound("click"); enter_play(game.level + 1)
        elseif S.card_t > 0.6 and (pressed("R") or clicked("btn_card2")) then
            sound("click"); enter_play(game.level)
        end
        return
    end
    for i, tool in ipairs(TOOLS) do
        if (pressed(tostring(i)) or clicked("tool" .. i)) and (game.inventory[tool] or 0) > 0 then S.tool = tool; sound("click") end
    end
    if pressed("F") then S.flip = S.flip == "/" and "\\" or "/"; sound("rotate") end
    if space or clicked("btn_send") then send() end
    if pressed("R") or clicked("btn_clear") then clear_board() end
    if pressed("H") or clicked("btn_hint") then use_hint() end
    if not World.playing() then
        if pressed("PageUp") and game.level < S.best then enter_play(game.level + 1); return end
        if pressed("PageDown") and game.level > 1 then enter_play(game.level - 1); return end
    end
    local st = state("board")
    hover = nil
    if st and st.hovered then
        local x, y = World.cell_at(st.mouse_x, st.mouse_y)
        if x then hover = { x, y } end
    end
    board_input(st)
end

------------------------------------------------------------------ HUD
local function draw_top()
    local k, w = L.k, L.w
    rect("top_bg", 0, 0, w, L.top, { 0.01, 0.012, 0.035, 0.8 }, 20)
    image("top_line", TEX.strip, 0, L.top - 6 * k, w, 12 * k, { 0.55, 0.42, 1, 0.55 }, 21)
    image("title_glow", TEX.glow, 0, -40 * k, 440 * k, 170 * k, { 0.3, 0.7, 1, 0.2 + 0.05 * sin(S.t * 1.5) }, 21)
    text("title", "ECHO CHAMBER", 34 * k, 12 * k, 420 * k, 58 * k, 2.4, { 0.8, 0.94, 1, 1 }, 40, "left")
    text("sub", "RING  THE  BELLS  IN  ORDER", 37 * k, 62 * k, 420 * k, 24 * k, 0.72, { 0.56, 0.58, 0.86, 1 }, 40, "left")
    -- Centre: chamber, bells rung, order pips.
    local cx = w / 2
    local nb = #game.bells
    text("chamber", "CHAMBER " .. game.level, cx - 200 * k, 4 * k, 400 * k, 26 * k, 0.85, VIOLET)
    text("bells", "BELLS  " .. S.rung .. " / " .. nb, cx - 220 * k, 24 * k, 440 * k, 46 * k, 1.7, WHITE)
    local pw, gap = 20 * k, 10 * k
    local total = nb * pw + (nb - 1) * gap
    for i = 1, 8 do
        if i <= nb then
            local x = cx - total / 2 + (i - 1) * (pw + gap)
            local c
            if i <= S.rung then c = col4(GOLD, 1)
            elseif S.fail and S.fail.bell == i then c = col4(BAD, 0.7 + 0.3 * sin(S.t * 8))
            elseif i == S.rung + 1 then c = col4(WHITE, 0.6 + 0.4 * sin(S.t * 5))
            else c = { 0.22, 0.24, 0.4, 0.95 } end
            local el = S.ring_at and S.ring_at[i] and (S.t - S.ring_at[i]) or 9
            local pp = el < 0.5 and 0.6 * math.sin(el / 0.5 * math.pi) or 0
            rect("pip" .. i, x - pw * pp / 2, 74 * k - pw * 0.8 * pp / 2, pw * (1 + pp), pw * 0.8 * (1 + pp), c, 40, pw * 0.4 * (1 + pp))
        else hide("pip" .. i) end
    end
    -- Right: pulse strength and pieces.
    local fx = SET:get("show_fps") and 170 * k or 0
    local right = w - 24 * k - fx
    local room = right - (cx + 240 * k)
    local q = k * max(0.55, min(1, room / ((260 + 12 + 170) * k)))
    local py, ph = 18 * k, 62 * q
    local pcw, pmw = 170 * q, 260 * q
    local px2 = right - pcw
    local px1 = px2 - 12 * q - pmw
    panel("pm", px1, py, pmw, ph, CYAN, 0.35, 30, 14 * q)
    local live = World.live_strength()
    local frac = max(0, min(1, S.meter or 1))
    text("pm_lbl", "PULSE", px1 + 16 * q, py + 4 * q, 120 * q, 24 * q, 0.78 * q / k, CYAN, 41, "left")
    text("pm_val", live and (floor(frac * 100 + 0.5) .. "%") or ("RANGE " .. game.strength), px1 + pmw - 156 * q, py + 4 * q, 140 * q, 24 * q, 0.78 * q / k, { 0.8, 0.92, 1, 1 }, 41, "right")
    rect("pm_track", px1 + 16 * q, py + 36 * q, pmw - 32 * q, 14 * q, { 0.08, 0.1, 0.2, 1 }, 41, 7 * q)
    local fc = frac > 0.3 and CYAN or lerp(BAD, CYAN, frac / 0.3)
    rect("pm_fill", px1 + 16 * q, py + 36 * q, max(14 * q, (pmw - 32 * q) * frac), 14 * q, col4(fc, 1), 42, 7 * q)
    panel("pc", px2, py, pcw, ph, GOLD, 0.35, 30, 14 * q)
    text("pc_lbl", "PIECES", px2, py + 4 * q, pcw, 22 * q, 0.72 * q / k, GOLD, 41)
    text("pc_val", game:placed_count() .. " / " .. game:total_pieces(), px2, py + 24 * q, pcw, 34 * q, (1.35 + 0.35 * (S.bump or 0)) * q / k, lerp({ 1, 0.92, 0.7, 1 }, WHITE, S.bump or 0), 41)
end

local function tool_card(i, tool, x, y, w, h, open)
    local k = L.k
    local id = "tool" .. i
    local have = (game.inventory[tool] or 0) > 0
    if open or not have then
        hide_panel("tc" .. i); for _, s in ipairs({ "_ic", "_nm", "_ds", "_left", "_key", "_kb", "_glow" }) do hide("tc" .. i .. s) end
        hide(id)
        return false
    end
    local left = game:left(tool)
    local sel = S.tool == tool
    local hov = hovered(id)
    local lift = sel and -6 * k or (hov and -3 * k or 0)
    y = y + lift
    if sel then
        image("tc" .. i .. "_glow", TEX.glow, x - w * 0.15, y - h * 0.45, w * 1.3, h * 1.9, { 0.4, 0.9, 1, 0.24 + 0.06 * sin(S.t * 4) }, 44)
    else hide("tc" .. i .. "_glow") end
    panel("tc" .. i, x, y, w, h, sel and CYAN or VIOLET, sel and 0.95 or (hov and 0.6 or 0.25), 45, 14 * k,
        sel and { 0.04, 0.1, 0.16, 0.96 } or PANEL)
    local is = 52 * k
    local ic = tool == "resonator" and GOLD or (tool == "damper" and { 1, 0.45, 0.45, 1 } or { 0.75, 0.93, 1, 1 })
    image("tc" .. i .. "_ic", TEX[tool], x + 16 * k, y + (h - is) / 2 - 4 * k, is, is, left > 0 and ic or { 0.5, 0.5, 0.6, 0.5 }, 46)
    text("tc" .. i .. "_nm", LABEL[tool], x + 80 * k, y + 14 * k, w - 88 * k, 26 * k, 0.95, sel and WHITE or { 0.85, 0.86, 0.98, 1 }, 46, "left")
    text("tc" .. i .. "_ds", DESC[tool], x + 80 * k, y + 40 * k, w - 88 * k, 22 * k, 0.66, DIM, 46, "left")
    text("tc" .. i .. "_left", left .. " left", x + 80 * k, y + 64 * k, w - 88 * k, 24 * k, 0.8, left > 0 and GOLD or { 0.6, 0.4, 0.42, 1 }, 46, "left")
    rect("tc" .. i .. "_kb", x + w - 30 * k, y + 8 * k, 22 * k, 22 * k, sel and col4(CYAN, 0.9) or { 0.15, 0.17, 0.3, 0.9 }, 46, 5 * k)
    text("tc" .. i .. "_key", tostring(i), x + w - 30 * k, y + 8 * k, 22 * k, 22 * k, 0.72, sel and { 0.02, 0.08, 0.1, 1 } or WHITE, 47)
    catcher(id, x, y - lift, w, h)
    return true
end

local function action(id, icon, label, sub, x, y, w, h, primary, ready, open, icon_c)
    local k = L.k
    if open then
        hide_panel(id .. "_p"); for _, s in ipairs({ "_ic", "_lb", "_sb", "_glow" }) do hide(id .. s) end
        hide(id)
        return
    end
    local hov = hovered(id)
    local rim = primary and CYAN or VIOLET
    local fill = primary and { 0.04, 0.15, 0.2, 0.96 } or PANEL
    if not ready then fill = { 0.03, 0.035, 0.07, 0.8 }; rim = { 0.3, 0.3, 0.45, 1 } end
    if ready and primary then
        image(id .. "_glow", TEX.glow, x - w * 0.2, y - h * 0.5, w * 1.4, h * 2, col4(rim, 0.2 + 0.1 * sin(S.t * 4)), 44)
    else hide(id .. "_glow") end
    panel(id .. "_p", x, y, w, h, rim, hov and 0.95 or (ready and 0.55 or 0.25), 45, 14 * k, fill)
    local is = 34 * k
    image(id .. "_ic", icon, x + 18 * k, y + (h - is) / 2, is, is, ready and (icon_c or WHITE) or { 0.5, 0.5, 0.6, 0.6 }, 46)
    text(id .. "_lb", label, x + 66 * k, y + 10 * k, w - 72 * k, 32 * k, 1.05, ready and WHITE or DIM, 46, "left")
    text(id .. "_sb", sub, x + 66 * k, y + 42 * k, w - 72 * k, 24 * k, 0.7, ready and (primary and CYAN or { 0.75, 0.7, 1, 1 }) or { 0.45, 0.48, 0.6, 1 }, 46, "left")
    catcher(id, x, y, w, h)
end

local function draw_bottom()
    local k, w, h = L.k, L.w, L.h
    rect("bot_bg", 0, h - L.bot, w, L.bot, { 0.01, 0.012, 0.035, 0.82 }, 20)
    image("bot_line", TEX.strip, 0, h - L.bot - 6 * k, w, 12 * k, { 0.55, 0.42, 1, 0.55 }, 21)
    local open = SET:is_open() or S.mode ~= "plan" and S.mode ~= "playing"
    local y, ch = h - L.bot + 22 * k, 104 * k
    local cw, gap = 236 * k, 14 * k
    local x = 30 * k
    local shown = 0
    for i, tool in ipairs(TOOLS) do
        local f = max(0, min(1, ((S.enter_t or 9) - 0.35 - shown * 0.09) / 0.45))
        local cy = y + 160 * k * (1 - ease_back(f))
        if tool_card(i, tool, x, cy, cw, ch, open) then x = x + cw + gap; shown = shown + 1 end
    end
    local aw, ah = 210 * k, 78 * k
    local ay = y + (ch - ah) / 2
    local ax = w - 30 * k - 4 * aw - 3 * gap
    local playing = World.playing()
    action("btn_send", TEX.play, playing and "SKIP" or "SEND PULSE", playing and "Space  ·  finish the send" or "Space", ax, ay, aw, ah, true, game.state ~= "won", open)
    action("btn_clear", TEX.reset, "CLEAR", "R  ·  take every piece back", ax + aw + gap, ay, aw, ah, false, not playing and game:placed_count() > 0, open)
    action("btn_hint", TEX.hint, "HINT", "H  ·  costs a star", ax + 2 * (aw + gap), ay, aw, ah, false, not playing, open, GOLD)
    action("btn_menu", TEX.menu, "MENU", "Esc  ·  chambers, settings", ax + 3 * (aw + gap), ay, aw, ah, false, true, open)

    -- Tip pill: what the hovered cell is, the last failure, or a tutorial line.
    local tip, tipc = nil, DIM
    if S.deny_t and S.deny_t > 0 then
        tip, tipc = "Can't place there: " .. tostring(S.deny_msg), BAD
    elseif hover and S.mode == "plan" then
        local hx, hy = hover[1], hover[2]
        local p = game:piece(hx, hy)
        local kind = game:kind(hx, hy)
        if p then
            tip = LABEL[p.kind] .. (p.flip and ("  " .. p.flip) or "") .. "     " .. (p.kind == "reflector" and "Click: flip     " or "") .. "Right-click: take it back"
            tipc = WHITE
        elseif kind == "bell" then tip = "Bell " .. game.bell_at[game:idx(hx, hy)] .. ": the pulse rings it as it passes. Lower numbers first."
        elseif kind == "wall" then tip = "Acoustic pillar: absorbs the pulse."
        elseif kind == "emitter" then tip = "The horn: fires the pulse with strength " .. game.strength .. " (one per step, one more per bounce)."
        elseif game:left(S.tool) > 0 then tip, tipc = TIP[S.tool], WHITE
        end
    end
    if not tip and S.fail then tip, tipc = fail_text(S.fail), { 1, 0.6, 0.6, 1 } end
    if not tip and game.level <= #TUTOR then tip, tipc = TUTOR[game.level], { 0.8, 0.86, 1, 1 } end
    if not tip then tip = TIP[S.tool] end
    if open then hide_panel("tip"); hide("tip") else
        local tw = min(w - 60 * k, 980 * k)
        local dz = (S.deny_t or 0) - 1.0
        X_OFF = dz > 0 and math.sin(S.t * 55) * 9 * k * dz / 0.4 or 0
        panel("tip", 30 * k, h - L.bot - 56 * k, tw, 40 * k, VIOLET, 0.2, 30, 20 * k, { 0.02, 0.025, 0.06, 0.74 })
        text("tip", tip, 50 * k, h - L.bot - 56 * k, tw - 30 * k, 40 * k, 0.9, tipc, 41, "left")
        X_OFF = 0
    end
end

-- Number badges above the bells, projected from the 3D bell positions.
local function draw_badges()
    local k = L.k
    local show = S.mode == "plan" or S.mode == "playing" or S.mode == "won"
    for _, b in ipairs(game.bells) do
        local n = b.n
        local X, Y, Z, st = World.bell_anchor(n)
        local sx, sy = nil, nil
        local ap = (S.enter_t or 9) - (0.95 + n * 0.11)
        if X and show and ap > 0 then sx, sy = World.project(X, Y, Z) end
        if sx then
            local el = S.ring_at and S.ring_at[n] and (S.t - S.ring_at[n]) or 9
            local pop = el < 0.6 and 0.55 * math.sin(el / 0.6 * math.pi) or 0
            local r = 19 * k * ease_back(min(1, ap / 0.35)) * (1 + pop)
            local rung = n <= S.rung
            local wrong = S.fail and S.fail.bell == n
            local nxt = n == S.rung + 1 and not wrong
            if nxt then sy = sy + math.sin(S.t * 3) * 4 * k end
            local fill = rung and { 1, 0.76, 0.3, 0.96 } or (wrong and { 0.8, 0.15, 0.15, 0.95 } or { 0.07, 0.07, 0.15, 0.9 })
            local rim = rung and { 1, 0.93, 0.7, 1 } or (wrong and { 1, 0.6, 0.6, 1 } or (nxt and col4(WHITE, 0.6 + 0.4 * sin(S.t * 5)) or { 0.62, 0.56, 0.9, 1 }))
            if rung or nxt then
                image("bg_glow" .. n, TEX.glow, sx - r * 2.4, sy - r * 2.4, r * 4.8, r * 4.8, rung and { 1, 0.7, 0.25, 0.45 } or { 0.5, 0.85, 1, 0.3 }, 23)
            else hide("bg_glow" .. n) end
            rect("bg_rim" .. n, sx - r - 2 * k, sy - r - 2 * k, 2 * r + 4 * k, 2 * r + 4 * k, rim, 24, r + 2 * k)
            rect("bg_body" .. n, sx - r, sy - r, 2 * r, 2 * r, fill, 24, r)
            text("bg_num" .. n, tostring(n), sx - r, sy - r, 2 * r, 2 * r, 1.0, rung and { 0.2, 0.12, 0.02, 1 } or WHITE, 25)
            if rung then image("bg_chk" .. n, TEX.check, sx + r + 2 * k, sy - 12 * k, 24 * k, 24 * k, { 1, 0.85, 0.45, 1 }, 25)
            else hide("bg_chk" .. n) end
        else
            for _, p in ipairs({ "bg_glow", "bg_rim", "bg_body", "bg_num", "bg_chk" }) do hide(p .. n) end
        end
    end
    for n = #game.bells + 1, 8 do for _, p in ipairs({ "bg_glow", "bg_rim", "bg_body", "bg_num", "bg_chk" }) do hide(p .. n) end end
end

local function draw_overlay()
    local k, w, h = L.k, L.w, L.h
    image("vig", TEX.vignette, 0, 0, w, h, { 0, 0, 0, 0.8 }, 15)
    if S.flash > 0 then image("hurt", TEX.vignette, 0, 0, w, h, col4(S.flash_c, S.flash * 0.8), 16) else hide("hurt") end
    if S.banner and S.banner_t > 0 and S.mode ~= "won" then
        local life = 2.6 - S.banner_t
        local a = max(0, min(1, life * 5, S.banner_t * 2))
        local sc = 0.85 + 0.15 * ease_back(life * 3)
        local by = L.top + 40 * k
        local c = S.banner_c or WHITE
        image("ban_strip", TEX.strip, w * 0.2, by - 24 * k, w * 0.6, 130 * k, col4(c, 0.25 * a), 34)
        text("banner", S.banner, 0, by, w, 64 * k, 2.2 * sc, col4(lerp(c, WHITE, 0.3), a), 35)
        if S.banner_sub then text("banner_sub", S.banner_sub, 0, by + 58 * k, w, 30 * k, 0.95, col4({ 0.85, 0.88, 1 }, a), 35) else hide("banner_sub") end
    else hide("ban_strip"); hide("banner"); hide("banner_sub") end
end

------------------------------------------------------------------ cards
local CARD_IDS = { "card_dim", "card_glow", "card_title", "card_sub", "card_l1", "card_l2", "card_l3", "card_l4", "card_l5", "card_ctrl",
    "btn_card", "card_btn_lb", "btn_card2", "card_btn2_lb", "card_star1", "card_star2", "card_star3", "card_bell" }
local function hide_card()
    for _, id in ipairs(CARD_IDS) do hide(id) end
    hide_panel("card"); hide_panel("card_btn"); hide_panel("card_btn2")
    for i = 1, 4 do hide("card_pi" .. i); hide("card_pt" .. i) end
end

local function card_button(id, label, x, y, w, h, primary)
    local k = L.k
    local hov = hovered(id)
    panel(id == "btn_card" and "card_btn" or "card_btn2", x, y, w, h, primary and CYAN or VIOLET, hov and 1 or 0.6, 92, 16 * k,
        primary and { 0.05, 0.17, 0.22, 0.98 } or PANEL)
    text(id == "btn_card" and "card_btn_lb" or "card_btn2_lb", label, x, y, w, h, 1.0, WHITE, 93)
    catcher(id, x, y, w, h, 94)
end

local function draw_card()
    if SET:is_open() or (S.mode ~= "help" and S.mode ~= "won") or S.card_t < 0 then hide_card(); return end
    local k, w, h = L.k, L.w, L.h
    local a = min(1, S.card_t * 3)
    rect("card_dim", 0, 0, w, h, { 0, 0, 0.02, 0.55 * a }, 88)
    local cw, chh = 900 * k, (S.mode == "help" and 600 or 470) * k
    local x, y = (w - cw) / 2, (h - chh) / 2 + (1 - ease_back(S.card_t * 2.5)) * 40 * k
    image("card_glow", TEX.glow, x - cw * 0.2, y - chh * 0.3, cw * 1.4, chh * 1.6, { 0.35, 0.6, 1, 0.22 * a }, 89)
    panel("card", x, y, cw, chh, S.mode == "won" and GOLD or CYAN, 0.75, 90, 22 * k, { 0.02, 0.025, 0.06, 0.96 })
    if S.mode == "help" then
        image("card_bell", TEX.bell, x + cw / 2 - 40 * k, y + 22 * k, 80 * k, 80 * k, { 1, 0.78, 0.35, 1 }, 91)
        text("card_title", "ECHO CHAMBER", x, y + 104 * k, cw, 64 * k, 2.6, { 0.82, 0.95, 1, 1 }, 91)
        text("card_sub", "One pulse. Every bell. In order.", x, y + 166 * k, cw, 32 * k, 1.0, GOLD, 91)
        text("card_l1", "Place your pieces, then send the pulse from the horn. Each bell it reaches rings.", x + 40 * k, y + 214 * k, cw - 80 * k, 28 * k, 0.86, WHITE, 91)
        text("card_l2", "Bells must ring 1, 2, 3... A bell reached too early spoils the send.", x + 40 * k, y + 244 * k, cw - 80 * k, 28 * k, 0.86, WHITE, 91)
        text("card_l3", "The pulse weakens with every step and every bounce. Pillars and the edge absorb it.", x + 40 * k, y + 274 * k, cw - 80 * k, 28 * k, 0.86, DIM, 91)
        local px, pw = x + 50 * k, (cw - 100 * k) / 4
        for i, tool in ipairs(TOOLS) do
            local ic = tool == "resonator" and GOLD or (tool == "damper" and { 1, 0.45, 0.45, 1 } or { 0.75, 0.93, 1, 1 })
            image("card_pi" .. i, TEX[tool], px + (i - 1) * pw + pw / 2 - 30 * k, y + 318 * k, 60 * k, 60 * k, ic, 91)
            text("card_pt" .. i, LABEL[tool] .. "\n" .. DESC[tool], px + (i - 1) * pw, y + 382 * k, pw, 54 * k, 0.72, DIM, 91)
        end
        text("card_ctrl", "Click: place / flip  ·  Right-click: take back  ·  1-4: piece  ·  F: flip  ·  Space: send  ·  H: hint  ·  R: clear",
            x + 20 * k, y + 446 * k, cw - 40 * k, 30 * k, 0.7, { 0.6, 0.62, 0.8, 1 }, 91)
        for _, id in ipairs({ "card_l4", "card_l5", "card_star1", "card_star2", "card_star3" }) do hide(id) end
        hide_panel("card_btn2"); hide("card_btn2_lb"); hide("btn_card2")
        card_button("btn_card", (S.started and "BACK TO CHAMBER " or "PLAY  ·  CHAMBER ") .. game.level, x + cw / 2 - 170 * k, y + chh - 96 * k, 340 * k, 64 * k, true)
    else
        hide("card_bell"); for i = 1, 4 do hide("card_pi" .. i); hide("card_pt" .. i) end
        text("card_title", "CHAMBER " .. game.level .. " RESONATES", x, y + 34 * k, cw, 64 * k, 2.2, { 1, 0.9, 0.62, 1 }, 91)
        -- Stars pop in one by one.
        for i = 1, 3 do
            local on = i <= game.stars
            local t = S.card_t * 3 - i * 0.5
            if on and t > 0 and (S.star_snd or 0) < i then S.star_snd = i; sound("star") end
            local s = on and (110 * k * max(0, min(1, ease_back(t)))) or 90 * k
            local cx = x + cw / 2 + (i - 2) * 130 * k
            image("card_star" .. i, TEX.star, cx - s / 2, y + 160 * k - s / 2, s, s, on and { 1, 0.8, 0.3, 1 } or { 0.2, 0.2, 0.32, 1 }, 92)
        end
        local sends = game.sends == 1 and "Solved on the first send." or ("Solved in " .. game.sends .. " sends.")
        text("card_sub", sends .. (game.hints > 0 and ("  " .. game.hints .. " hint" .. (game.hints > 1 and "s" or "") .. " used.") or ""), x, y + 230 * k, cw, 32 * k, 1.0, WHITE, 91)
        text("card_l1", "3 stars: first send, no hints.   2 stars: within three sends.", x, y + 268 * k, cw, 28 * k, 0.78, DIM, 91)
        for _, id in ipairs({ "card_l2", "card_l3", "card_l4", "card_l5", "card_ctrl" }) do hide(id) end
        card_button("btn_card", "NEXT CHAMBER  ·  Enter", x + cw / 2 + 10 * k, y + chh - 100 * k, 340 * k, 64 * k, true)
        card_button("btn_card2", "REPLAY  ·  R", x + cw / 2 - 290 * k, y + chh - 100 * k, 280 * k, 64 * k, false)
    end
end

------------------------------------------------------------------ menu and chamber select
-- Pooled panel (ids from pid, so it hides itself on frames it is not drawn).
local function ppanel(x, y, w, h, rim, rim_a, z, radius, fill)
    local k = L.k
    radius = radius or 14 * k
    rect(pid("pp"), x - 2 * k, y - 2 * k, w + 4 * k, h + 4 * k, col4(rim or VIOLET, rim_a or 0.35), z, radius + 2 * k)
    rect(pid("pp"), x, y, w, h, fill or PANEL, z, radius)
    image(pid("pp"), TEX.sheen, x + radius * 0.5, y + 2 * k, w - radius, h * 0.45, { 1, 1, 1, 0.05 }, z)
end
local MENU_IDS = { "m_play", "m_select", "m_help", "m_settings", "m_quit" }
local SEL_IDS = { "sel_prev", "sel_next", "sel_back" }

local function menu_button(id, icon, label, sub, x, y, w, h, primary, icon_c, a)
    local k = L.k
    local hov = hovered(id)
    local lift = hov and 10 * k or 0
    if primary then image(pid("mg"), TEX.glow, x - w * 0.15, y - h * 0.6, w * 1.3, h * 2.2, { 0.4, 0.85, 1, (0.18 + 0.08 * sin(S.t * 3)) * a }, 70) end
    ppanel(x + lift, y, w, h, primary and CYAN or VIOLET, (hov and 0.95 or 0.45) * a, 71, 16 * k, primary and { 0.04, 0.15, 0.2, 0.95 * a } or { 0.025, 0.03, 0.075, 0.9 * a })
    image(pid("mi"), icon, x + lift + 22 * k, y + (h - 38 * k) / 2, 38 * k, 38 * k, col4(icon_c or WHITE, a), 72)
    text(pid("mt"), label, x + lift + 78 * k, y + 8 * k, w - 90 * k, 36 * k, 1.2, col4(WHITE, a), 72, "left")
    text(pid("mt"), sub, x + lift + 78 * k, y + 42 * k, w - 90 * k, 24 * k, 0.72, col4(primary and CYAN or { 0.72, 0.7, 0.95 }, a), 72, "left")
    catcher(id, x, y, w + 12 * k, h, 73)
end

local function draw_menu()
    if S.mode ~= "menu" or SET:is_open() then for _, id in ipairs(MENU_IDS) do hide(id) end return end
    local k, w, h = L.k, L.w, L.h
    local t = S.menu_t
    local a = min(1, t * 4)
    -- A dark wash on the left for the title and buttons; the chamber turns slowly behind it.
    local pw = min(w * 0.5, 720 * k)
    rect(pid("mb"), 0, 0, pw, h, { 0.008, 0.01, 0.03, 0.82 * a }, 60)
    image(pid("mb"), TEX.strip, pw - 60 * k, 0, 120 * k, h, { 0.5, 0.4, 1, 0 }, 61)
    rect(pid("mb"), pw - 2 * k, 0, 3 * k, h, { 0.5, 0.42, 1, 0.45 * a }, 61)
    local x0 = 70 * k
    local ty = h * 0.14
    image(pid("mb"), TEX.glow, x0 - 120 * k, ty - 110 * k, 640 * k, 340 * k, { 0.3, 0.6, 1, 0.22 * a }, 61)
    local bs = 74 * k * ease_back(min(1, t * 2.5))
    image(pid("mb"), TEX.bell, x0, ty - bs * 0.1 + sin(S.t * 1.6) * 3 * k, bs, bs, { 1, 0.78, 0.35, a }, 62)
    text(pid("mb"), "ECHO", x0 + 92 * k, ty - 8 * k, 560 * k, 60 * k, 2.9, col4({ 0.82, 0.95, 1 }, a), 62, "left")
    text(pid("mb"), "CHAMBER", x0 + 92 * k, ty + 46 * k, 560 * k, 60 * k, 2.9, col4({ 0.82, 0.95, 1 }, a), 62, "left")
    text(pid("mb"), "One pulse. Every bell. In order.", x0 + 4 * k, ty + 124 * k, 560 * k, 30 * k, 1.0, col4(GOLD, a), 62, "left")
    -- Buttons slide in from the left, one after another.
    local solved, stars = progress()
    local next_n = game.state == "won" and game.level + 1 or game.level
    local items = {
        { "m_play", TEX.play, S.started and "CONTINUE" or "PLAY", "Chamber " .. next_n .. "  ·  Enter", true, WHITE },
        { "m_select", TEX.grid, "CHAMBERS", solved .. " solved  ·  " .. stars .. " stars  ·  C", false, { 0.75, 0.93, 1, 1 } },
        { "m_help", TEX.hint, "HOW TO PLAY", "pieces, rules and keys", false, GOLD },
        { "m_settings", TEX.menu, "SETTINGS", "sound, graphics, screen", false, WHITE },
        { "m_quit", TEX.power, "QUIT", "close the game", false, { 1, 0.5, 0.5, 1 } },
    }
    local bw, bh, gap = min(pw - 2 * x0, 420 * k), 76 * k, 16 * k
    local by = ty + 190 * k
    for i, it in ipairs(items) do
        local f = max(0, min(1, (t - 0.08 * i) / 0.4))
        local bx = x0 - (1 - ease_back(f)) * (bw + 120 * k)
        menu_button(it[1], it[2], it[3], it[4], bx, by + (i - 1) * (bh + gap), bw, bh, it[5], it[6], a * f)
    end
    text(pid("mb"), S.started and "Esc  ·  back to the chamber" or "Best chamber reached: " .. S.best, x0, h - 60 * k, pw - x0, 28 * k, 0.75, col4(DIM, a), 62, "left")
end

local function draw_select()
    if S.mode ~= "select" or SET:is_open() then for _, id in ipairs(SEL_IDS) do hide(id) end; for i = 1, PAGE do hide("selc" .. i) end return end
    local k, w, h = L.k, L.w, L.h
    local t = S.menu_t
    local a = min(1, t * 4)
    rect(pid("sb"), 0, 0, w, h, { 0.006, 0.008, 0.025, 0.78 * a }, 60)
    local solved, stars = progress()
    text(pid("sb"), "CHAMBERS", 0, 40 * k, w, 64 * k, 2.4, col4({ 0.82, 0.95, 1 }, a), 62)
    text(pid("sb"), solved .. " solved  ·  " .. stars .. " / " .. (3 * max(1, solved)) .. " stars  ·  unlocked up to " .. S.best, 0, 104 * k, w, 30 * k, 0.9, col4(GOLD, a), 62)
    local cols, rows = 6, 5
    local tw, th, gx, gy = 168 * k, 112 * k, 18 * k, 18 * k
    local gw = cols * tw + (cols - 1) * gx
    local x0, y0 = (w - gw) / 2, 160 * k
    for i = 1, PAGE do
        local n = (S.page - 1) * PAGE + i
        local c, r = (i - 1) % cols, floor((i - 1) / cols)
        local f = max(0, min(1, (t - 0.015 * i) / 0.35))
        local x = x0 + c * (tw + gx)
        local y = y0 + r * (th + gy) + (1 - ease_back(f)) * 50 * k
        local open = n <= S.best
        local st = S.stars_by[n] or 0
        local cur = n == game.level
        local hov = open and hovered("selc" .. i)
        local rim = st > 0 and GOLD or (open and CYAN or { 0.3, 0.3, 0.45, 1 })
        if cur then image(pid("sg"), TEX.glow, x - tw * 0.25, y - th * 0.4, tw * 1.5, th * 1.8, { 0.4, 0.85, 1, (0.25 + 0.1 * sin(S.t * 4)) * a * f }, 63) end
        local lift = hov and -5 * k or 0
        ppanel(x, y + lift, tw, th, rim, (hov and 1 or (open and 0.55 or 0.25)) * a * f, 64, 14 * k,
            open and { 0.03, 0.045, 0.1, 0.94 * a * f } or { 0.02, 0.02, 0.04, 0.8 * a * f })
        text(pid("st"), tostring(n), x, y + lift + 10 * k, tw, 52 * k, 1.9, col4(open and WHITE or { 0.4, 0.4, 0.52 }, a * f), 65)
        if open then
            for s = 1, 3 do
                local ss = 24 * k
                image(pid("ss"), TEX.star, x + tw / 2 + (s - 2) * 30 * k - ss / 2, y + lift + 70 * k, ss, ss, s <= st and col4({ 1, 0.8, 0.3 }, a * f) or { 0.2, 0.2, 0.32, a * f }, 65)
            end
        else
            text(pid("st"), "locked", x, y + lift + 68 * k, tw, 26 * k, 0.72, col4({ 0.4, 0.4, 0.52 }, a * f), 65)
        end
        catcher("selc" .. i, x, y, tw, th, 66)
    end
    -- Paging and back.
    local pages = max(1, math.ceil((S.best + 1) / PAGE))
    local by = y0 + rows * (th + gy) + 20 * k
    local bw, bh = 220 * k, 64 * k
    local function small(id, icon, label, x, ready)
        local hov = hovered(id)
        ppanel(x, by, bw, bh, ready and VIOLET or { 0.3, 0.3, 0.45, 1 }, (hov and ready and 1 or 0.45) * a, 64, 14 * k)
        image(pid("si"), icon, x + 18 * k, by + (bh - 30 * k) / 2, 30 * k, 30 * k, ready and col4(WHITE, a) or { 0.5, 0.5, 0.6, 0.5 * a }, 65)
        text(pid("st"), label, x + 58 * k, by, bw - 64 * k, bh, 0.95, ready and col4(WHITE, a) or col4(DIM, 0.6 * a), 65, "left")
        catcher(id, x, by, bw, bh, 66)
    end
    small("sel_back", TEX.back, "BACK  ·  Esc", x0, true)
    small("sel_prev", TEX.back, "PREVIOUS", x0 + gw - 2 * bw - 16 * k, S.page > 1)
    small("sel_next", TEX.play, "NEXT", x0 + gw - bw, S.page < pages)
    text(pid("st"), "PAGE " .. S.page .. " / " .. pages .. "  ·  PgUp / PgDn", x0 + bw, by, gw - 4 * bw, bh, 0.8, col4(DIM, a), 65)
end

------------------------------------------------------------------ frame
local function step(dt)
    S.t = S.t + dt
    if S.mode == "help" or S.mode == "won" then S.card_t = S.card_t + dt end
    if S.mode == "menu" or S.mode == "select" then S.menu_t = S.menu_t + dt end
    S.flash = max(0, S.flash - dt * 1.4)
    S.banner_t = max(0, S.banner_t - dt)
    S.deny_t = max(0, (S.deny_t or 0) - dt)
    S.enter_t = (S.enter_t or 9) + dt
    S.bump = max(0, (S.bump or 0) - dt * 4)
    local live = World.live_strength() or 1
    S.meter = (S.meter or 1) + (live - (S.meter or 1)) * min(1, dt * 10)
end

local function present(dt)
    if layout() then for id in pairs(widgets) do widgets[id] = true; hide(id) end end
    local planning = S.mode == "plan" and not SET:is_open()
    -- Ghost of the piece about to be placed, and the hover cursor.
    if planning and hover then
        local hx, hy = hover[1], hover[2]
        local free = game:kind(hx, hy) == "floor" and not game:piece(hx, hy)
        local ok = free and game:left(S.tool) > 0
        if free then World.set_ghost({ kind = S.tool, flip = S.flip }, hx, hy, ok) else World.set_ghost(nil) end
        local c = game:piece(hx, hy) and { 1, 1, 1 } or (ok and { 0.35, 1, 0.65 } or { 1, 0.35, 0.35 })
        World.set_cursor(hx, hy, c, true)
    else
        World.set_ghost(nil)
        World.set_cursor(0, 0, nil, false)
    end
    World.set_orbit(S.mode == "menu" or S.mode == "select" or S.mode == "help")
    World.update(dt, game)
    local open = SET:is_open() or S.mode ~= "plan" and S.mode ~= "playing"
    if open then hide("board") else catcher("board", 0, L.top, L.w, L.h - L.top - L.bot, 1) end
    draw_overlay()
    -- HUD entrance: the bars slide in when a chamber starts.
    local in_menu = S.mode == "menu" or S.mode == "select" or S.mode == "help"
    local et = in_menu and -1 or (S.enter_t or 9)
    Y_OFF = -L.top * 1.3 * (1 - ease_back(max(0, min(1, et / 0.55))))
    draw_top()
    Y_OFF = L.bot * 1.3 * (1 - ease_back(max(0, min(1, (et - 0.1) / 0.55))))
    draw_bottom()
    Y_OFF = 0
    draw_badges()
    if et >= 0 and et < 0.6 then rect("fade", 0, 0, L.w, L.h, { 0.004, 0.005, 0.02, 1 - et / 0.6 }, 86) else hide("fade") end
    draw_card()
    draw_menu()
    draw_select()
    flush_pools()
end

------------------------------------------------------------------ boot
runtime_ui.clear(SCREEN)
runtime_ui.set_screen_overlay(SCREEN, true)
runtime_ui.show(SCREEN)
do
    local all = {}
    for _, v in pairs(TEX) do all[#all + 1] = v end
    pcall(runtime_ui.preload_images, all)
end
World.init({ particle_scale = function() return SET:particle_scale() end, shake_scale = function() return SET:shake_scale() end })
layout()
start_chamber(S.level)
SET:apply()
if audio and audio.play_music then pcall(audio.play_music, "ambience.wav") end   -- the chamber's room tone, on the music bus
present(0)

script.on_update("echo", function()
    local dt = max(0, min(0.1, engine.get_metrics().delta_ms / 1000))
    local esc = pressed("Escape")
    if SET:update(dt) then
        for _, key in ipairs(KEYS) do pressed(key) end
        hover = nil
    elseif esc and S.mode == "menu" then
        if S.started then resume() end
    elseif esc and (S.mode == "select" or S.mode == "help") then
        sound("click"); S.mode, S.menu_t = "menu", 0
    elseif esc or clicked("btn_menu") then
        open_menu()
    else
        controls()
        step(dt)
    end
    present(dt)
end, "play")

print("[EchoChamber] Ready. Click to place, right-click to take back, 1-4 pieces, F flip, Space send, H hint, R clear, Esc menu.")
