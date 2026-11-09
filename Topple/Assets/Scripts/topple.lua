-- Topple (PhasmaEngine, Lua): set up a chain reaction of wooden toys on a games table, tip the first domino and
-- watch it all fall. Bells raise the multiplier; springs, rockets and marbles carry the chain across the table.
-- Beat each table's score within its tips, spend coins at the toy shop, go on to a harder table.
-- topple_rules.lua: rules and the chain simulation. topple_world.lua: the 3D table. This file: flow, input,
-- sounds and the HUD (the chalk board, the toy tray, pops and cards).
local function module(path)
    local source = assert(fs.read(path), "Missing Topple module: " .. path)
    return assert(load(source, "@" .. path, "t", _ENV))()
end
local R = module("Scripts/topple_rules.lua")
local World = module("Scripts/topple_world.lua")(R)
local SettingsMenu = module("Scripts/Lib/settings_menu.lua") -- shared menu, same copy as the other games
local Free = module("Scripts/topple_free.lua")                -- Free Build: rules, the room, the view
Free.set_room(module("Scripts/free_room.lua"))
local FreeWorld = module("Scripts/topple_free_world.lua")(Free)
local FreeView
local Hall

local SCREEN = "topple"
local floor, min, max, abs, sin, cos, sqrt = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt
local atan2 = math.atan2 or math.atan
local CLEAR = { 0, 0, 0, 0 }
local CREAM = { 0.97, 0.93, 0.82, 1 }
local CHALK = { 0.93, 0.92, 0.86, 0.95 }
local CHALK_DIM = { 0.86, 0.86, 0.8, 0.55 }
local BRASS = { 0.88, 0.68, 0.38, 1 }
local GOLD = { 1.0, 0.8, 0.4, 1 }
local WALNUT = { 0.12, 0.065, 0.035, 0.93 }
local WALNUT_HI = { 0.22, 0.12, 0.06, 0.96 }
local RIM = { 0.8, 0.6, 0.33, 0.85 }
local INK = { 0.04, 0.025, 0.015, 0.6 }
local BAD = { 0.93, 0.45, 0.33, 1 }
local SAGE = { 0.62, 0.8, 0.55, 1 }

local best = tonumber(fs.read("Save/topple_best.txt") or "0") or 0
local runs = tonumber(fs.read("Save/topple_runs.txt") or "0") or 0
local S = { mode = "title", t = 0, card_t = 0, tool = "domino", pops = {}, speed = 1, painted = 0, pending = {} }
local run, board
local L = {}
_G.topple = { S = S, R = R, W = World, run = function() return run end, board = function() return board end, autoplay = false,
    F = Free, FW = FreeWorld }

-- The engine aborts when about 32 sounds overlap; a long chain clacks fast. Cap voices and space the clacks.
local LEN = { clack1 = 0.37, clack2 = 0.36, clack3 = 0.35, place = 0.4, remove = 0.37, tip = 0.52, bell = 2.58, boing = 0.91,
    launch = 1.09, pop = 0.68, roll = 1.33, thunk = 0.49, house = 0.6, wobble = 0.34, cheer = 2.23, over = 2.68, coin = 0.5, click = 0.07 }
local MAX_VOICES, voices, clock, last_clack, last_place = 16, {}, 0, -1, -1
local function sound(name)
    if not (audio and audio.play) then return end
    for i = #voices, 1, -1 do if voices[i] <= clock then table.remove(voices, i) end end
    if #voices >= MAX_VOICES then return end
    voices[#voices + 1] = clock + (LEN[name] or 2)
    pcall(audio.play, name .. ".wav")
end
local function clack()
    if clock - last_clack < 0.035 then return end
    last_clack = clock
    sound("clack" .. math.random(1, 3))
end
local SET = SettingsMenu.new({ title = "SETTINGS", subtitle = "TOPPLE", click = function() sound("click") end,
    theme = { accent = { 0.86, 0.66, 0.36, 1 }, accent2 = { 0.95, 0.8, 0.5, 1 }, text = { 0.97, 0.93, 0.82, 1 }, selected_text = { 1, 0.97, 0.88, 1 } },
    on_graphics = function(c)
        pcall(settings.set, "taa", true); pcall(settings.set, "fxaa", false)
        if S.mode == "free" or S.mode == "hall" then FreeWorld.apply_look(c) end
    end })
_G.topple.settings = SET
World.particle_scale = function() return SET:particle_scale() end
World.shake_scale = function() return SET:shake_scale() end
FreeWorld.particle_scale = World.particle_scale
FreeWorld.shake_scale = World.shake_scale

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
local function image(path, x, y, w, h, tint, z)
    quad(pid("i"), { style = "image", path = path, x = x, y = y, width = w, height = h, z = z or 31, image_tint = tint or { 1, 1, 1, 1 } })
end
-- Text with its em size px (screen pixels) centred on y; a soft dark copy under it for legibility.
local function text(s, x, y, px, color, align, z, w, shadow)
    local h = px * 1.6
    local bw = w or max(60, #s * px * 0.75)
    local bx = align == "left" and x or (align == "right" and x - bw or x - bw / 2)
    if shadow ~= false then
        local a = (color[4] or 1)
        quad(pid("t"), { style = "text", label = s, x = bx + px * 0.05, y = y - h / 2 + px * 0.07, width = bw, height = h, z = (z or 40) - 0.5,
            font_scale = px / 16, text_color = { 0.03, 0.02, 0.01, 0.55 * a }, align_h = align or "center", align_v = "middle" })
    end
    quad(pid("t"), { style = "text", label = s, x = bx, y = y - h / 2, width = bw, height = h, z = z or 40,
        font_scale = px / 16, text_color = color, align_h = align or "center", align_v = "middle" })
end
local function panel(x, y, w, h, z, fill, rim, r)
    r = (r or 14) * u
    quad(pid("p"), { style = "text", label = "", x = x, y = y, width = w, height = h, z = z, fill = fill or WALNUT, border = rim or RIM, corner_radius = r })
    quad(pid("p"), { style = "text", label = "", x = x + 2, y = y + 2, width = w - 4, height = h - 4, z = z, fill = CLEAR, border = col4(rim or RIM, 0.45), corner_radius = max(0, r - 2) })
end
local function commas(n)
    local s = tostring(floor(n))
    while true do
        local t = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if t == s then return s end
        s = t
    end
end
local function ease_back(t) t = max(0, min(1, t)); local c = 1.7; return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2 end

------------------------------------------------------------------ flow
local function update_preview()
    S.pred = board and R.simulate(board, run) or nil
    World.set_starter(board and board:starter())
end
local function start_board()
    board = run:new_board()
    World.clear()
    World.sync(board)
    S.painted, S.press, S.res, S.pops, S.tip_pts, S.mult = 0, nil, nil, {}, 0, 1
    update_preview()
    S.mode = "build"
    if (board.left[S.tool] or 0) <= 0 then S.tool = "domino" end
end
local function new_run()
    runs = runs + 1
    pcall(fs.write, "Save/topple_runs.txt", tostring(runs))
    run = R.new_run(runs * 7 + 3)
    S.tool = "domino"
    start_board()
end
_G.topple.new_run = new_run
-- Console / capture hook: play a board built elsewhere (e.g. a scripted layout).
_G.topple.set_board = function(b)
    board = b
    World.clear()
    World.sync(board)
    S.painted, S.press, S.mode = 0, nil, "build"
    update_preview()
end
local function changed()
    World.sync(board)
    update_preview()
end
local function place_domino(x, y, a)
    local p = board:place("domino", x, y, a, World.PAINTS[floor(S.painted / 6) % 5 + 1])
    if p then
        S.painted = S.painted + 1
        if clock - last_place > 0.05 then sound("place"); last_place = clock end
        S.dirty = true
    end
    return p
end
local function tip()
    if S.mode ~= "build" then return end
    if not board:starter() then S.nudge = 1; sound("click"); return end
    S.res = R.simulate(board, run)
    S.tip_pts, S.mult, S.pops, S.pending = 0, S.res.start_mult, {}, {}
    World.set_starter(nil)
    World.play(S.res)
    S.mode, S.speed = "running", 1
end
_G.topple.tip = tip
local function save_best()
    if run.table_n > best then best = run.table_n; pcall(fs.write, "Save/topple_best.txt", tostring(best)) end
end
local function finish()
    S.outcome = run:finish_tip(S.res)
    S.mode, S.card_t = "tally", 0
    if S.outcome == "cleared" then sound("cheer"); save_best()
    elseif S.outcome == "over" then sound("over"); save_best() end
end
local function after_tally()
    if S.outcome == "again" then start_board()
    elseif S.outcome == "cleared" then S.mode, S.card_t = "cleared", 0
    else S.mode, S.card_t = "over", 0 end
end
local function open_shop()
    run:shop_offers()
    S.mode, S.card_t = "shop", 0
end
local function next_table()
    run:next_table()
    save_best()
    start_board()
end
_G.topple.open_shop, _G.topple.next_table = function() open_shop() end, function() next_table() end

------------------------------------------------------------------ playing a tip: sounds and pops
local function pop(x, y, h, s, kind)
    S.pops[#S.pops + 1] = { x = x, y = y, h = h, s = s, kind = kind or "pt", t = 0 }
end
local function on_event(ev)
    local p = board.pieces[ev.id]
    if ev.points and ev.points > 0 then
        S.tip_pts = S.tip_pts + ev.points
        if p then pop(p.x, p.y, (p.kind == "house") and 2.2 or 1.6, "+" .. commas(ev.points)) end
    end
    if ev.kind == "fall" then
        if ev.starter then sound("tip") elseif p and p.kind == "house" then sound("house") else clack() end
    elseif ev.kind == "ring" then
        S.mult = ev.mult
        sound("bell")
        if p then pop(p.x, p.y, 3.0, "×" .. ev.mult, "mult") end
    elseif ev.kind == "lucky" then
        S.mult = ev.mult
        if p then pop(p.x, p.y, 2.4, "×" .. ev.mult, "mult") end
    elseif ev.kind == "spring" then sound("boing")
    elseif ev.kind == "launch" then
        sound("launch")
        S.pending[#S.pending + 1] = { t = ev.t_land, f = function() sound("pop") end }
    elseif ev.kind == "roll" then sound("roll")
    elseif ev.kind == "wobble" then sound("wobble")
    elseif ev.kind == "thunk" then sound("thunk") end
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
local KEYS = { "M", "Return", "Space", "F", "C", "Backspace", "1", "2", "3", "4", "5", "T", "G" }

-- Free Build gets the screen helpers; it keeps its own key edges (see FreeView.flush_keys).
local TABLE_IDS = { "board", "btn_tip", "btn_speed", "btn_undo", "btn_clear", "btn_menu", "tool1", "tool2", "tool3", "tool4", "tool5",
    "buy1", "buy2", "buy3", "buy4" }
local back_to_menu
FreeView = module("Scripts/topple_free_view.lua")(Free, FreeWorld, {
    quad = quad, hide = hide, catcher = catcher, state = state, clicked = clicked, hovered = hovered, pid = pid, rect = rect,
    image = image, text = text, panel = panel, col4 = col4, commas = commas, ease_back = ease_back, sound = sound, clack = clack,
    edge = edge, SET = SET, L = L, u = function() return u end, back_to_menu = function() back_to_menu() end,
    C = { CREAM = CREAM, BRASS = BRASS, GOLD = GOLD, WALNUT = WALNUT, WALNUT_HI = WALNUT_HI, RIM = RIM, BAD = BAD, SAGE = SAGE, CLEAR = CLEAR },
})
_G.topple.free = FreeView
Hall = module("Scripts/topple_hall.lua")(Free, FreeWorld, module("Scripts/topple_hall_core.lua")(Free), {
    quad = quad, hide = hide, catcher = catcher, state = state, clicked = clicked, hovered = hovered, pid = pid, rect = rect, image = image,
    text = text, panel = panel, col4 = col4, commas = commas, sound = sound, clack = clack, edge = edge, SET = SET, L = L,
    u = function() return u end, back_to_menu = function() back_to_menu() end,
    C = { CREAM = CREAM, BRASS = BRASS, GOLD = GOLD, WALNUT = WALNUT, WALNUT_HI = WALNUT_HI, RIM = RIM, BAD = BAD, SAGE = SAGE, CLEAR = CLEAR },
})
_G.topple.hall = Hall
local function start_free()
    for _, id in ipairs(TABLE_IDS) do hide(id) end
    hide("btn_card"); hide("btn_table"); hide("btn_hall")
    World.show(false)
    S.mode = "free"
    FreeView.enter()
    SET:apply()
end
local function start_hall()
    if not hinge_field then return end     -- an engine build from before the hall can't draw it
    for _, id in ipairs(TABLE_IDS) do hide(id) end
    hide("btn_card"); hide("btn_table"); hide("btn_hall")
    World.show(false)
    S.mode = "hall"
    Hall.enter()
    SET:apply()
end
_G.topple.start_hall = start_hall
back_to_menu = function()
    if S.mode == "hall" then
        Hall.leave()
        Hall.hide_all()
    else
        FreeView.leave()
        FreeView.hide_all()
    end
    World.show(true)
    World.apply_look()
    S.mode, S.card_t = "title", 0
    SET:apply()
    pcall(settings.set, "shadows", true)
end
_G.topple.start_free, _G.topple.back_to_menu = start_free, function() back_to_menu() end
local TOOLS = { "domino", "bell", "spring", "rocket", "marble" }
local TOOL_ICON = { domino = "dominoes", bell = "bell", spring = "spring", rocket = "rocket", marble = "marble" }
local TOOL_NAME = { domino = "DOMINOES", bell = "BELL", spring = "SPRING", rocket = "ROCKET", marble = "MARBLE" }
local TOOL_HINT = {
    domino = "Drag across the felt to draw a line of dominoes. The first one you place is the one the tip knocks over.",
    bell = "Hang a bell beside the line: every bell the chain passes adds x2 to the multiplier.",
    spring = "Press and drag to aim. A spring jumps a gap and strikes the first toy up to 3.6 ahead.",
    rocket = "Press and drag to aim. A rocket flies 5 ahead and knocks over everything it lands among.",
    marble = "Press and drag to aim the chute. The marble rolls on across the felt to the next toy.",
}

local function select_tool(t)
    if t == S.tool then return end
    if t ~= "domino" and (board.left[t] or 0) <= 0 then sound("click"); S.nudge_tool = t; return end
    S.tool = t
    sound("click")
end

local function undo()
    local last
    for _, p in pairs(board.pieces) do if not p.fixed and (not last or p.order > last.order) then last = p end end
    if last then
        board:remove(last.id)
        if last.kind == "domino" then S.painted = max(0, S.painted - 1) end
        sound("remove"); S.dirty = true
    end
end
local function clear_all()
    local any = false
    for id, p in pairs(board.pieces) do if not p.fixed then board:remove(id); any = true end end
    if any then S.painted = 0; sound("remove"); S.dirty = true end
end

-- A bell's gallows stands along the nearest line (its posts beside the dominoes, not across them).
local function bell_angle(x, y)
    local near, bd
    for _, p in pairs(board.pieces) do
        if p.kind == "domino" then
            local d = (p.x - x) ^ 2 + (p.y - y) ^ 2
            if d < 6 and (not bd or d < bd) then near, bd = p, d end
        end
    end
    return near and (near.a + math.pi / 2) or 0
end
_G.topple.bell_angle = function(x, y) return bell_angle(x, y) end

local function nearest_end(x, y)
    local best_p, bd
    for _, p in pairs(board.pieces) do
        if p.kind == "domino" and not p.fixed then
            local d = sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2)
            if d < 0.55 and (not bd or d < bd) then best_p, bd = p, d end
        end
    end
    return best_p
end

local function build_input(enter)
    for i, t in ipairs(TOOLS) do
        if pressed(tostring(i)) or clicked("tool" .. i) then select_tool(t) end
    end
    if pressed("Backspace") or clicked("btn_undo") then undo() end
    if pressed("C") or clicked("btn_clear") then clear_all() end
    if enter or clicked("btn_tip") then tip(); return end
    local st = state("board")
    local mx, my = st and st.mouse_x, st and st.mouse_y
    local tx, ty
    if mx and (st.hovered or st.down) then tx, ty = World.table_point(mx, my) end
    if tx and not R.inside(tx, ty, { x0 = R.TABLE.x0 - 1, x1 = R.TABLE.x1 + 1, y0 = R.TABLE.y0 - 1, y1 = R.TABLE.y1 + 1 }) then tx = nil end
    S.cursor = tx and { mx = mx, my = my, x = tx, y = ty } or nil
    if st and st.right_clicked and tx then
        local p = board:pick(tx, ty, 0.45)
        if p then
            board:remove(p.id)
            if p.kind == "domino" then S.painted = max(0, S.painted - 1) end
            sound("remove"); S.dirty = true
        end
    end
    local down = st and st.down
    if down and not S.was_down and tx then
        S.press = { x = tx, y = ty }
        if S.tool == "domino" then
            local e = nearest_end(tx, ty)
            if e then S.press.lx, S.press.ly, S.press.started = e.x, e.y, true
            else S.press.lx, S.press.ly = tx, ty end
        end
    elseif down and S.press and tx then
        if S.tool == "domino" then
            if not S.press.started then
                if sqrt((tx - S.press.x) ^ 2 + (ty - S.press.y) ^ 2) >= R.SPACING * 0.5 then
                    place_domino(S.press.x, S.press.y, atan2(ty - S.press.y, tx - S.press.x))
                    S.press.started = true
                end
            end
            if S.press.started then
                for _ = 1, 10 do
                    local nx, ny, a = R.stroke_next(S.press.lx, S.press.ly, tx, ty)
                    if not nx then break end
                    place_domino(nx, ny, a)
                    S.press.lx, S.press.ly = nx, ny
                end
            end
        else
            local d = sqrt((tx - S.press.x) ^ 2 + (ty - S.press.y) ^ 2)
            if d >= 0.4 then S.press.a = atan2(ty - S.press.y, tx - S.press.x) end
        end
    elseif not down and S.press then
        if S.tool == "domino" then
            if not S.press.started then place_domino(S.press.x, S.press.y, S.press.a or 0) end
        else
            local a = S.tool == "bell" and bell_angle(S.press.x, S.press.y) or (S.press.a or 0)
            local p, why = board:place(S.tool, S.press.x, S.press.y, a)
            if p then sound("place"); S.dirty = true
            else S.deny, S.deny_why = 1, why; sound("click") end
            if (board.left[S.tool] or 0) <= 0 then S.tool = "domino" end
        end
        S.press = nil
    end
    S.was_down = down
end

-- Test / capture hook (off unless set from the console): draw a line through the middle of the table, hang the
-- first bell beside it, then tip.
local function autoplay()
    if S.mode ~= "build" then return end
    local y, x = -3.0, -11.4
    while (board.left.domino or 0) > 0 and x < 10.5 do
        place_domino(x, y, 0)
        x = x + R.SPACING
    end
    if (board.left.bell or 0) > 0 then board:place("bell", -11.4 + 2 * R.SPACING + 0.3, y + 0.75, bell_angle(-11.4, y)) end
    changed()
    tip()
end

local function controls(dt)
    if pressed("M") then SET:toggle_mute() end
    local enter = pressed("Return") or pressed("Space")
    local tkey = pressed("T")
    local gkey = pressed("G")
    if S.mode == "free" then
        FreeView.controls(dt)
        return
    end
    if S.mode == "hall" then
        Hall.controls(dt)
        return
    end
    if run and S.mode ~= "title" and clicked("btn_menu") then
        sound("click"); for _, id in ipairs(TABLE_IDS) do hide(id) end
        World.clear(); S.mode, S.card_t = "title", 0
        return
    end
    if S.mode == "title" then
        if S.card_t > 0.3 and (enter or clicked("btn_card")) then sound("click"); start_free()
        elseif S.card_t > 0.3 and (gkey or clicked("btn_hall")) then sound("click"); start_hall()
        elseif S.card_t > 0.3 and (tkey or clicked("btn_table")) then sound("click"); new_run() end
    elseif S.mode == "build" then
        if _G.topple.autoplay then autoplay() else build_input(enter) end
        if S.dirty then S.dirty = false; changed() end
    elseif S.mode == "running" then
        if pressed("F") or clicked("btn_speed") then S.speed = S.speed == 1 and 2.5 or 1; sound("click") end
    elseif S.mode == "tally" then
        if S.card_t > 1.7 or (S.card_t > 0.4 and enter) then after_tally() end
    elseif S.mode == "cleared" then
        if S.card_t > 0.4 and (enter or clicked("btn_card")) then sound("click"); open_shop() end
    elseif S.mode == "shop" then
        for i = 1, 4 do
            if clicked("buy" .. i) then
                if run:buy(i) then sound("coin") else sound("click"); S.deny = 1 end
            end
        end
        if S.card_t > 0.3 and (enter or clicked("btn_card")) then sound("click"); next_table() end
        if _G.topple.autoplay and S.card_t > 1 then next_table() end
    elseif S.mode == "over" then
        if S.card_t > 0.6 and (enter or clicked("btn_card")) then sound("click"); new_run() end
    end
    if (S.mode == "cleared" or S.mode == "over") and _G.topple.autoplay and S.card_t > 1.2 then
        if S.mode == "cleared" then open_shop() else new_run() end
    end
end

local function step(dt)
    S.t = S.t + dt
    S.card_t = S.card_t + dt
    for i = #S.pops, 1, -1 do
        local q = S.pops[i]
        q.t = q.t + dt
        if q.t > (q.kind == "mult" and 1.6 or 0.9) then table.remove(S.pops, i) end
    end
    S.nudge = max(0, (S.nudge or 0) - dt * 1.5)
    S.deny = max(0, (S.deny or 0) - dt * 2)
end

------------------------------------------------------------------ HUD
local function chalk_board()
    local cx, cy, bw, bh = World.board_rect()
    if not cx or bw < 40 then return end
    local tb = run.tb
    local live = (S.mode == "running" or S.mode == "tally") and S.tip_pts or 0
    local shown = tb.score + ((S.mode == "running") and live or 0)
    local top = cy - bh / 2
    text((tb.grand and "Grand Table " or "Table ") .. tb.n, cx, top + bh * 0.2, bh * 0.14, CHALK, "center", 20, bw, false)
    text(commas(shown) .. " / " .. commas(tb.target), cx, top + bh * 0.41, bh * 0.16, CHALK, "center", 20, bw, false)
    -- Progress bar: chalk outline, filled to the score (the running tip shown brighter).
    local bx, by, bww, bhh = cx - bw * 0.42, top + bh * 0.58, bw * 0.84, bh * 0.12
    local lw = max(2, bh * 0.012)
    rect(bx, by, bww, lw, CHALK, 20); rect(bx, by + bhh - lw, bww, lw, CHALK, 20)
    rect(bx, by, lw, bhh, CHALK, 20); rect(bx + bww - lw, by, lw, bhh, CHALK, 20)
    local f0 = min(1, tb.score / tb.target)
    local f1 = min(1, shown / tb.target)
    if f0 > 0 then rect(bx + lw * 2, by + lw * 2, (bww - lw * 4) * f0, bhh - lw * 4, CHALK_DIM, 20) end
    if f1 > f0 then rect(bx + lw * 2 + (bww - lw * 4) * f0, by + lw * 2, (bww - lw * 4) * (f1 - f0), bhh - lw * 4, col4(GOLD, 0.8), 20) end
    -- Tips left: chalk rings, filled while still to come.
    local n = tb.tips_left + tb.tips_used
    local r = bh * 0.045
    local gap = r * 3.2
    local x0 = cx - (n - 1) * gap / 2
    for i = 1, n do
        local left = i > tb.tips_used
        quad(pid("tip"), { style = "text", label = "", x = x0 + (i - 1) * gap - r, y = top + bh * 0.83 - r, width = 2 * r, height = 2 * r, z = 20,
            fill = left and CHALK_DIM or CLEAR, border = CHALK, corner_radius = r })
    end
    text("tips", x0 - r * 3.6, top + bh * 0.83, bh * 0.09, CHALK, "center", 20, bw * 0.3, false)
    if S.mode == "running" and live > 0 then
        text("+" .. commas(live) .. (S.mult > 1 and ("  ×" .. S.mult) or ""), x0 + (n - 1) * gap + r * 5.5, top + bh * 0.83, bh * 0.1, GOLD, "center", 20, bw * 0.4, false)
    end
end

local function tray()
    local w, h = L.w, L.h
    local tw, th = 1120 * u, 150 * u
    local tx, ty = (w - tw) / 2, h - th - 18 * u
    panel(tx, ty, tw, th, 50, WALNUT, RIM, 18)
    local building = S.mode == "build"
    -- Tool cards.
    local cw, ch = 150 * u, 126 * u
    for i, t in ipairs(TOOLS) do
        local x = tx + 14 * u + (i - 1) * (cw + 10 * u)
        local y = ty + 12 * u
        local n = board and (board.left[t] or 0) or 0
        local sel = building and S.tool == t
        local empty = n <= 0
        local hov = hovered("tool" .. i)
        local fill = sel and { 0.34, 0.2, 0.09, 0.97 } or (hov and WALNUT_HI or { 0.17, 0.095, 0.05, 0.95 })
        panel(x, y, cw, ch, 51, fill, sel and GOLD or col4(RIM, 0.6), 12)
        local a = empty and 0.35 or 1
        image("Textures/icon_" .. TOOL_ICON[t] .. ".png", x + (cw - 86 * u) / 2, y + 4 * u, 86 * u, 86 * u, { 1, 1, 1, a }, 52)
        text(TOOL_NAME[t], x + cw / 2, y + 96 * u, 17 * u, col4(sel and GOLD or CREAM, a), "center", 53, cw)
        text("×" .. n, x + cw - 10 * u, y + 16 * u, 19 * u, col4(empty and BAD or CREAM, 1), "right", 53, 60 * u)
        text(tostring(i), x + 14 * u, y + 16 * u, 15 * u, col4(BRASS, 0.8), "center", 53, 30 * u)
        if S.nudge_tool == t and empty then S.nudge_tool = nil end
        if building then catcher("tool" .. i, x, y, cw, ch, 62) else hide("tool" .. i) end
    end
    -- Undo / clear.
    local sx = tx + 14 * u + 5 * (cw + 10 * u)
    for k, b in ipairs({ { "btn_undo", "UNDO", "Backspace" }, { "btn_clear", "CLEAR", "C" } }) do
        local y = ty + 12 * u + (k - 1) * 66 * u
        local hov = hovered(b[1])
        panel(sx, y, 120 * u, 60 * u, 51, hov and WALNUT_HI or { 0.17, 0.095, 0.05, 0.95 }, col4(RIM, 0.6), 10)
        text(b[2], sx + 60 * u, y + 22 * u, 18 * u, CREAM, "center", 53, 120 * u)
        text(b[3], sx + 60 * u, y + 44 * u, 12 * u, col4(BRASS, 0.85), "center", 53, 120 * u)
        if building then catcher(b[1], sx, y, 120 * u, 60 * u, 62) else hide(b[1]) end
    end
    -- TIP / speed.
    local bx = sx + 132 * u
    local bw2 = tx + tw - 14 * u - bx
    local by, bh2 = ty + 12 * u, 126 * u
    if building then
        local ready = board and board:starter() ~= nil
        local hov = hovered("btn_tip")
        local pulse = ready and (0.5 + 0.5 * sin(S.t * 4)) or 0
        panel(bx, by, bw2, bh2, 51, ready and (hov and { 0.5, 0.3, 0.1, 0.98 } or { 0.42, 0.25, 0.09, 0.97 }) or { 0.17, 0.095, 0.05, 0.95 },
            ready and col4(GOLD, 0.7 + 0.3 * pulse) or col4(RIM, 0.5), 14)
        text("TIP", bx + bw2 / 2, by + 50 * u, 44 * u, ready and GOLD or col4(CREAM, 0.4), "center", 53, bw2)
        text("Space", bx + bw2 / 2, by + 96 * u, 15 * u, col4(BRASS, ready and 0.9 or 0.4), "center", 53, bw2)
        catcher("btn_tip", bx, by, bw2, bh2, 62)
        hide("btn_speed")
    else
        hide("btn_tip")
        local running = S.mode == "running"
        panel(bx, by, bw2, bh2, 51, { 0.17, 0.095, 0.05, 0.95 }, col4(RIM, 0.5), 14)
        if running then text(S.speed > 1 and "FAST ×2.5" or "WATCH", bx + bw2 / 2, by + 50 * u, 28 * u, CREAM, "center", 53, bw2) end
        text(running and "F  speed" or "", bx + bw2 / 2, by + 92 * u, 15 * u, col4(BRASS, 0.9), "center", 53, bw2)
        if running then catcher("btn_speed", bx, by, bw2, bh2, 62) else hide("btn_speed") end
    end
    -- Above the tray: the prediction and the tool's hint.
    if building and board then
        local msg
        local nd = board:count("domino")
        if nd == 0 then
            msg = "Draw a line of dominoes, then tip it."
        elseif S.pred then
            msg = string.format("The chain reaches %d of %d dominoes", S.pred.toppled, nd)
        end
        local col = (S.nudge or 0) > 0 and col4(BAD, 0.6 + 0.4 * S.nudge) or CREAM
        if msg then text(msg, w / 2, ty - 50 * u, 22 * u, col, "center", 45, 900 * u) end
        text(TOOL_HINT[S.tool], w / 2, ty - 20 * u, 15 * u, col4(CREAM, 0.85), "center", 45, 1200 * u)
        if (S.deny or 0) > 0 then
            local why = ({ crowded = "Too close to another toy.", edge = "That's off the table.", none = "None left in the box." })[S.deny_why] or "Can't go there."
            text(why, w / 2, ty - 80 * u, 18 * u, col4(BAD, S.deny), "center", 45, 800 * u)
        end
    end
end

local function top_left()
    panel(24 * u, 18 * u, 330 * u, 92 * u, 39, WALNUT, RIM, 14)
    text("TOPPLE", 44 * u, 50 * u, 40 * u, CREAM, "left", 41, 300 * u)
    text("table run", 46 * u, 88 * u, 15 * u, col4(BRASS, 0.95), "left", 41, 200 * u)
    if S.mode ~= "title" then
        local hov = hovered("btn_menu")
        panel(270 * u, 34 * u, 70 * u, 60 * u, 41, hov and WALNUT_HI or { 0.17, 0.095, 0.05, 0.95 }, col4(RIM, 0.6), 10)
        text("MENU", 305 * u, 64 * u, 17 * u, CREAM, "center", 42, 70 * u)
        catcher("btn_menu", 270 * u, 34 * u, 70 * u, 60 * u, 62)
    else
        hide("btn_menu")
    end
    -- Coins and charms.
    local y = 122 * u
    panel(24 * u, y, 200 * u, 50 * u, 39, WALNUT, RIM, 12)
    quad(pid("coin"), { style = "text", label = "", x = 40 * u, y = y + 13 * u, width = 24 * u, height = 24 * u, z = 41,
        fill = { 0.95, 0.72, 0.3, 1 }, border = { 1, 0.88, 0.55, 1 }, corner_radius = 12 * u })
    text(run and tostring(run.coins) or "0", 76 * u, y + 26 * u, 24 * u, CREAM, "left", 41, 100 * u)
    text("coins", 132 * u, y + 28 * u, 15 * u, col4(BRASS, 0.9), "left", 41, 80 * u)
    if run then
        local k = 0
        local tb = run.tb
        if tb and (tb.twist or tb.grand) then
            local tw = tb.twist and R.TWISTS[tb.twist]
            local title = (tb.grand and "GRAND TABLE" or "") .. ((tb.grand and tw) and "  ·  " or "") .. (tw and tw.name:upper() or "")
            local sub = tw and tw.text or ""
            if tb.grand then sub = (tw and (sub .. "  ") or "") .. "Target x1.5, coins x2." end
            local yy = y + 60 * u
            panel(24 * u, yy, 330 * u, 58 * u, 39, { 0.17, 0.095, 0.05, 0.92 }, col4(CREAM, 0.5), 10)
            text(title, 189 * u, yy + 18 * u, 15 * u, CREAM, "center", 41, 320 * u)
            text(sub, 189 * u, yy + 40 * u, 12 * u, col4(BRASS, 0.95), "center", 41, 320 * u)
            y = y + 66 * u
        end
        -- Owned charms, six at most listed (there are 14).
        local ids = {}
        for id in pairs(R.CHARMS) do if run.charms[id] then ids[#ids + 1] = id end end
        table.sort(ids)
        local extra = max(0, #ids - 6)
        for i = #ids, 7, -1 do ids[i] = nil end
        if extra > 0 then
            text("+" .. extra .. " more charms", 134 * u, y + 60 * u + 6 * 34 * u + 15 * u, 14 * u, col4(GOLD, 0.8), "center", 41, 220 * u)
        end
        for _, id in ipairs(ids) do
            local yy = y + 60 * u + k * 34 * u
            panel(24 * u, yy, 220 * u, 30 * u, 39, { 0.17, 0.095, 0.05, 0.9 }, col4(GOLD, 0.6), 10)
            text(R.CHARMS[id].name, 134 * u, yy + 15 * u, 15 * u, GOLD, "center", 41, 220 * u)
            k = k + 1
        end
    end
end

local function draw_pops()
    for _, q in ipairs(S.pops) do
        local sx, sy = World.project(q.x, q.y, q.h)
        if sx then
            if q.kind == "mult" then
                local s = max(0.15, ease_back(q.t * 4))
                local a = 1 - max(0, q.t - 1.1) / 0.5
                text(q.s, sx, sy - 18 * u - q.t * 26 * u, 64 * u * s, col4(GOLD, a), "center", 46, 300 * u)
            else
                local a = 1 - max(0, q.t - 0.55) / 0.35
                text(q.s, sx, sy - q.t * 42 * u, 26 * u * (0.7 + 0.3 * ease_back(q.t * 6)), col4(CREAM, a), "center", 45, 120 * u)
            end
        end
    end
end

-- Where the cursor would put a toy: a ring on the felt, and for aimed toys the way they will act.
local function cursor_marks()
    if S.mode ~= "build" or SET:is_open() then return end
    local c = S.cursor
    if not c then return end
    local x, y = c.x, c.y
    local a = 0
    if S.press and S.tool ~= "domino" then x, y, a = S.press.x, S.press.y, S.press.a or 0 end
    local ok = board:can_place(S.tool, x, y)
    local px, py = World.project(x, y, 0)
    if not px then return end
    local r = (S.tool == "domino" and 26 or 44) * u
    image("Textures/ring.png", px - r, py - r * 0.55, 2 * r, 1.1 * r, ok and { 1, 0.92, 0.7, 0.9 } or { 1, 0.45, 0.35, 0.8 }, 44)
    if S.tool ~= "domino" and S.tool ~= "bell" then
        local from, to, step_ = 0.6, 3.0, 0.4
        if S.tool == "rocket" then from, to = 0.8, R.ROCKET_RANGE end
        if S.tool == "spring" then from, to = R.SPRING_FROM, R.SPRING_TO end
        for d = from, to, step_ do
            local qx, qy = World.project(x + cos(a) * d, y + sin(a) * d, 0)
            if qx then
                local rr = 4 * u
                quad(pid("dot"), { style = "text", label = "", x = qx - rr, y = qy - rr, width = 2 * rr, height = 2 * rr, z = 44,
                    fill = { 1, 0.9, 0.65, 0.75 }, corner_radius = rr })
            end
        end
        if S.tool == "rocket" then
            local qx, qy = World.project(x + cos(a) * R.ROCKET_RANGE, y + sin(a) * R.ROCKET_RANGE, 0)
            if qx then
                local rr = 60 * u
                image("Textures/ring.png", qx - rr, qy - rr * 0.55, 2 * rr, 1.1 * rr, { 1, 0.6, 0.3, 0.7 }, 44)
            end
        end
    end
end

local function draw_cards()
    local w, h = L.w, L.h
    local show = S.mode == "title" or S.mode == "cleared" or S.mode == "over" or S.mode == "shop"
    if not show or SET:is_open() then
        hide("btn_card"); hide("btn_table"); hide("btn_hall"); for i = 1, 4 do hide("buy" .. i) end
        if S.mode == "tally" then
            local a = min(1, S.card_t * 4) * (1 - max(0, S.card_t - 1.3) / 0.4)
            local tw = 520 * u
            panel((w - tw) / 2, h * 0.3, tw, 110 * u, 70, col4(WALNUT, a), col4(RIM, a), 16)
            text("TIP " .. run.tb.tips_used .. "   +" .. commas(S.res.score), w / 2, h * 0.3 + 42 * u, 40 * u, col4(GOLD, a), "center", 71, tw)
            local tb = run.tb
            local msg = S.outcome == "cleared" and "Table cleared!" or (S.outcome == "over" and "Out of tips." or
                (commas(tb.target - tb.score) .. " to go  ·  " .. tb.tips_left .. (tb.tips_left == 1 and " tip left" or " tips left")))
            text(msg, w / 2, h * 0.3 + 84 * u, 20 * u, col4(CREAM, a), "center", 71, tw)
        end
        return
    end
    local a = min(1, S.card_t * 3)
    rect(0, 0, w, h, { 0.02, 0.015, 0.01, 0.55 * a }, 80)
    local cw, ch = 900 * u, 500 * u
    if S.mode == "shop" then cw, ch = 1240 * u, 620 * u end
    local x, y = (w - cw) / 2, (h - ch) / 2 + (1 - ease_back(S.card_t * 2.5)) * 30 * u
    panel(x, y, cw, ch, 81, col4({ 0.1, 0.055, 0.03, 0.97 }, a), col4(RIM, a), 20)
    local cx = x + cw / 2
    local btn
    if S.mode == "title" then
        text("TOPPLE", cx, y + 80 * u, 86 * u, col4(CREAM, a), "center", 82, cw)
        text("Set up chain reactions of dominoes, then tip the first one.", cx, y + 160 * u, 22 * u, col4(CREAM, a), "center", 82, cw)
        text("FREE BUILD: thousands of dominoes anywhere in a living room. Lines, spirals,", cx, y + 210 * u, 18 * u, col4(BRASS, a), "center", 82, cw)
        text("fields, up the books and onto the coffee table. Save your builds, tip, replay.", cx, y + 238 * u, 18 * u, col4(BRASS, a), "center", 82, cw)
        text("THE GREAT HALL: a floor for five million. Tip a million dominoes and watch them go.", cx, y + 272 * u, 18 * u, col4(BRASS, a), "center", 82, cw)
        text("TABLE RUN: a toy chain on a games table, a score to beat, a toy shop between tables.", cx, y + 306 * u, 18 * u, col4(BRASS, a), "center", 82, cw)
        text(best > 0 and ("Best table run: table " .. best) or "", cx, y + 346 * u, 18 * u, col4(GOLD, a), "center", 82, cw)
        btn = "FREE BUILD"
    elseif S.mode == "cleared" then
        local tb = run.tb
        text("TABLE " .. tb.n .. " CLEARED", cx, y + 80 * u, 60 * u, col4(GOLD, a), "center", 82, cw)
        text(commas(tb.score) .. " / " .. commas(tb.target) .. "   in " .. tb.tips_used .. (tb.tips_used == 1 and " tip" or " tips"), cx, y + 160 * u, 28 * u, col4(CREAM, a), "center", 82, cw)
        text("+" .. (tb.reward or 0) .. " coins", cx, y + 220 * u, 34 * u, col4(GOLD, a), "center", 82, cw)
        text("Next: table " .. (tb.n + 1) .. "  ·  target " .. commas(R.table_target(tb.n + 1)), cx, y + 280 * u, 20 * u, col4(BRASS, a), "center", 82, cw)
        btn = "TOY SHOP"
    elseif S.mode == "over" then
        local tb = run.tb
        text("OUT OF TIPS", cx, y + 80 * u, 60 * u, col4(CREAM, a), "center", 82, cw)
        text("Table " .. tb.n .. ":  " .. commas(tb.score) .. " / " .. commas(tb.target), cx, y + 160 * u, 28 * u, col4(CREAM, a), "center", 82, cw)
        text(tb.n >= best and "Your furthest table yet." or ("Best: table " .. best), cx, y + 220 * u, 24 * u, col4(GOLD, a), "center", 82, cw)
        btn = "NEW RUN"
    else
        text("TOY SHOP", cx, y + 60 * u, 56 * u, col4(CREAM, a), "center", 82, cw)
        text(run.coins .. " coins to spend", cx, y + 112 * u, 22 * u, col4(GOLD, a), "center", 82, cw)
        local ow, oh = 270 * u, 330 * u
        local gap = 20 * u
        local ox0 = cx - (4 * ow + 3 * gap) / 2
        local ICON = { bell = "bell", spring = "spring", rocket = "rocket", marble = "marble", dominoes = "dominoes",
            brass = "bell", pips = "dominoes", touch = "dominoes", fair = "house", encore = "block", crate = "rocket",
            chime = "bell", fuse = "rocket", coil = "spring", glass = "marble", thrift = "block", piggy = "house",
            lucky = "dominoes", mason = "block", kit = "spring" }
        for i, o in ipairs(run.offers or {}) do
            local ox, oy = ox0 + (i - 1) * (ow + gap), y + 150 * u
            local afford = run.coins >= o.price
            local dim = o.sold and 0.35 or 1
            local hov = hovered("buy" .. i) and not o.sold
            panel(ox, oy, ow, oh, 82, col4(hov and WALNUT_HI or { 0.16, 0.09, 0.045, 0.97 }, a), col4(o.charm and GOLD or RIM, a * dim), 14)
            image("Textures/icon_" .. ICON[o.id] .. ".png", ox + (ow - 120 * u) / 2, oy + 12 * u, 120 * u, 120 * u, { 1, 1, 1, a * dim }, 83)
            if o.charm then text("CHARM", ox + ow - 14 * u, oy + 20 * u, 13 * u, col4(GOLD, a * dim), "right", 84, 100 * u) end
            text(o.name, ox + ow / 2, oy + 150 * u, 24 * u, col4(CREAM, a * dim), "center", 84, ow)
            -- Wrap the description over two lines at the nearest space to the middle.
            local s = o.text
            local mid, cut = #s / 2, nil
            for i2 = 1, #s do if s:sub(i2, i2) == " " and (not cut or abs(i2 - mid) < abs(cut - mid)) then cut = i2 end end
            local l1, l2 = s, ""
            if #s > 26 and cut then l1, l2 = s:sub(1, cut - 1), s:sub(cut + 1) end
            text(l1, ox + ow / 2, oy + 190 * u, 15 * u, col4(BRASS, a * dim), "center", 84, ow)
            text(l2, ox + ow / 2, oy + 212 * u, 15 * u, col4(BRASS, a * dim), "center", 84, ow)
            local bw_, bh_ = 170 * u, 52 * u
            local bx_, by_ = ox + (ow - bw_) / 2, oy + oh - bh_ - 18 * u
            panel(bx_, by_, bw_, bh_, 83, col4(o.sold and { 0.12, 0.07, 0.04, 1 } or (afford and { 0.42, 0.25, 0.09, 1 } or { 0.17, 0.095, 0.05, 1 }), a),
                col4(afford and not o.sold and GOLD or RIM, a * dim), 10)
            text(o.sold and "BOUGHT" or ("BUY  " .. o.price), bx_ + bw_ / 2, by_ + bh_ / 2, 22 * u, col4(afford and not o.sold and GOLD or CREAM, a * dim), "center", 84, bw_)
            if not o.sold then catcher("buy" .. i, ox, oy, ow, oh, 86) else hide("buy" .. i) end
        end
        btn = "NEXT TABLE"
    end
    if S.mode ~= "shop" then for i = 1, 4 do hide("buy" .. i) end end
    local bw, bh = S.mode == "title" and 270 * u or 340 * u, 70 * u
    local bx, by = cx - bw / 2, y + ch - 104 * u
    if S.mode == "title" then bx = cx - bw * 1.5 - 12 * u end
    local hov = hovered("btn_card")
    panel(bx, by, bw, bh, 83, col4(hov and { 0.5, 0.3, 0.1, 1 } or { 0.42, 0.25, 0.09, 1 }, a), col4(GOLD, a), 14)
    text(btn .. "  ·  Enter", bx + bw / 2, by + bh / 2, S.mode == "title" and 22 * u or 26 * u, col4(GOLD, a), "center", 84, bw)
    catcher("btn_card", bx, by, bw, bh, 85)
    if S.mode == "title" then
        local hx = cx - bw / 2
        local hov3 = hovered("btn_hall")
        panel(hx, by, bw, bh, 83, col4(hov3 and { 0.5, 0.3, 0.1, 1 } or { 0.34, 0.2, 0.08, 1 }, a), col4(GOLD, a), 14)
        text("GREAT HALL  ·  G", hx + bw / 2, by + bh / 2, 22 * u, col4(GOLD, a), "center", 84, bw)
        catcher("btn_hall", hx, by, bw, bh, 85)
        local tx2 = cx + bw / 2 + 12 * u
        local hov2 = hovered("btn_table")
        panel(tx2, by, bw, bh, 83, col4(hov2 and { 0.3, 0.17, 0.08, 1 } or { 0.2, 0.11, 0.05, 1 }, a), col4(RIM, a), 14)
        text("TABLE RUN  ·  T", tx2 + bw / 2, by + bh / 2, 22 * u, col4(CREAM, a), "center", 84, bw)
        catcher("btn_table", tx2, by, bw, bh, 85)
    else
        hide("btn_table")
        hide("btn_hall")
    end
end

-- dt: the smoothed frame step (camera, cards, effects); real: the time that actually passed, which drives a chain's
-- clock so it runs at the same speed at any frame rate (a 30 FPS unfocused window, a busy GPU).
local function present(dt, real)
    if layout() then for id in pairs(widgets) do widgets[id] = true; hide(id) end end
    local w, h = L.w, L.h
    u = min(w / 1920, h / 1080)
    if S.mode == "free" then
        FreeView.update(dt, real)
        FreeView.draw()
        draw_cards()
        flush_pools()
        return
    end
    if S.mode == "hall" then
        Hall.update(dt, real)
        Hall.draw()
        draw_cards()
        flush_pools()
        return
    end
    local due = World.update(S.mode == "running" and (real or dt) * S.speed or dt)
    if S.mode == "running" then
        for _, ev in ipairs(due) do on_event(ev) end
        local at = World.anim_time()
        for i = #S.pending, 1, -1 do if S.pending[i].t <= at then S.pending[i].f(); table.remove(S.pending, i) end end
        if not World.playing() then finish() end
    end
    if S.mode == "build" and not SET:is_open() then catcher("board", 0, 0, w, h - 175 * u, 1) else hide("board") end
    if run then
        chalk_board()
        tray()
        top_left()
        draw_pops()
        cursor_marks()
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
present(0)

local smooth_dt
script.on_update("topple", function()
    local real = max(0, engine.get_metrics().delta_ms / 1000)
    local raw = min(0.05, real)
    smooth_dt = smooth_dt and smooth_dt + (raw - smooth_dt) * 0.1 or raw
    local dt = smooth_dt
    real = min(real, 0.5)      -- only a stall (a dragged window, a breakpoint) is cut short
    clock = clock + dt
    local esc = pressed("Escape")
    if SET:update(dt) then
        for _, key in ipairs(KEYS) do pressed(key) end
        FreeView.flush_keys()
        Hall.flush_keys()
    elseif esc then
        sound("click"); SET:open()
    else
        controls(dt)
        step(dt)
    end
    present(dt, real)
end, "play")

print("[Topple] Ready. Enter: Free Build, T: Table Run. Esc settings, M mute.")
