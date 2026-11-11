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
local House = module("Scripts/topple_house.lua")              -- the eight rooms: progress, what is open and unlocked
-- A room's data (surfaces, solids, furniture, lights, camera): the living room's is free_room.lua, the others'
-- Scripts/rooms/<id>.lua. nil while a room isn't made yet (the House map shows it as coming soon). fresh: read it again.
local ROOMS = {}
local function load_room(id, fresh)
    if fresh then ROOMS[id] = nil end
    if ROOMS[id] then return ROOMS[id] end
    local path = id == "living" and "Scripts/free_room.lua" or ("Scripts/rooms/" .. id .. ".lua")
    local okr, src = pcall(fs.read, path)
    if not okr or not src then return nil end
    local ok, room = pcall(function() return assert(load(src, "@" .. path, "t", _ENV))() end)
    if not ok or type(room) ~= "table" or not (room.surfaces and room.solids and room.bounds) then
        print("[Topple] The room " .. id .. " did not load: " .. tostring(room))
        return nil
    end
    room.id = room.id or id
    room.name = room.name or (House.BY_ID[id] and House.BY_ID[id].name) or id
    room.pieces = room.pieces or {}
    ROOMS[id] = room
    return room
end
Free.set_room(load_room("living"))
local FreeWorld = module("Scripts/topple_free_world.lua")(Free)
World.F = Free                                                -- both modes' dominoes lean by the same rule
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
local CLACK_VARIANTS = 12
local LEN = { place = 0.4, remove = 0.37, tip = 0.52, bell = 2.58, boing = 0.91,
    launch = 1.09, pop = 0.68, roll = 1.33, thunk = 0.49, house = 0.6, wobble = 0.34, cheer = 2.23, over = 2.68, coin = 0.5, click = 0.07 }
for i = 1, CLACK_VARIANTS do LEN["clack" .. i] = 0.06 end
-- The House: traps, a new tool, and each room's goal.
for name, d in pairs({ string_snap1 = 0.72, string_snap2 = 0.73, weight_drop = 0.5, plank_fall = 0.75, gate_open = 0.97, collapse_cards = 1.35,
    collapse_blocks = 1.28, collapse_glass = 1.81, unlock = 1.65, goal_doorbell = 2.38, goal_tv = 2.0, goal_toaster = 0.69, goal_record = 3.28,
    goal_train = 1.68, goal_musicbox = 3.5, goal_dictionary = 0.69, goal_lights = 2.45 }) do LEN[name] = d end
local MAX_VOICES, voices, clock, last_clack, clack_gap, last_place = 16, {}, 0, -1, 0, -1
local function sound(name)
    if not (audio and audio.play) then return end
    for i = #voices, 1, -1 do if voices[i] <= clock then table.remove(voices, i) end end
    if #voices >= MAX_VOICES then return end
    voices[#voices + 1] = clock + (LEN[name] or 2)
    pcall(audio.play, name .. ".wav")
end
local function clack()
    if clock - last_clack < clack_gap then return end
    last_clack, clack_gap = clock, 0.015 + math.random() * 0.02    -- hits in recorded chains land about 17-24 ms apart, never evenly
    sound("clack" .. math.random(1, CLACK_VARIANTS))
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
local function wrap(s, n)
    local lines, cur = {}, ""
    for word in s:gmatch("%S+") do
        if #cur + #word + 1 > n and cur ~= "" then lines[#lines + 1] = cur; cur = word
        else cur = cur == "" and word or (cur .. " " .. word) end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return lines
end
-- A brass padlock centred on (cx, cy); s: the width of its body.
local function lock(cx, cy, s, a, z)
    local c = col4(BRASS, a)
    quad(pid("lk"), { style = "text", label = "", x = cx - s * 0.36, y = cy - s * 0.86, width = s * 0.72, height = s * 0.9, z = z, fill = c, corner_radius = s * 0.36 })
    quad(pid("lk"), { style = "text", label = "", x = cx - s * 0.2, y = cy - s * 0.66, width = s * 0.4, height = s * 0.7, z = z + 0.1, fill = { 0.09, 0.05, 0.028, a }, corner_radius = s * 0.2 })
    quad(pid("lk"), { style = "text", label = "", x = cx - s / 2, y = cy - s * 0.24, width = s, height = s * 0.78, z = z + 0.2, fill = c, border = { 1, 0.86, 0.55, 0.5 * a }, corner_radius = s * 0.14 })
    quad(pid("lk"), { style = "text", label = "", x = cx - s * 0.08, y = cy + s * 0.02, width = s * 0.16, height = s * 0.3, z = z + 0.3, fill = { 0.09, 0.05, 0.028, a }, corner_radius = s * 0.08 })
end
-- How hovered a widget is, eased (0..1), for lifts and glows.
local HV = {}
local function hv(id)
    local v = HV[id] or 0
    v = v + ((hovered(id) and 1 or 0) - v) * min(1, (S.fdt or 1 / 60) * 14)
    HV[id] = v
    return v
end

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
local KEYS = { "M", "Return", "Space", "F", "C", "Backspace", "1", "2", "3", "4", "5", "T", "G", "Q" }

-- Free Build gets the screen helpers; it keeps its own key edges (see FreeView.flush_keys).
local TABLE_IDS = { "btn_card_back", "board", "btn_tip", "btn_speed", "btn_undo", "btn_clear", "btn_menu", "tool1", "tool2", "tool3", "tool4", "tool5",
    "buy1", "buy2", "buy3", "buy4" }
local back_to_menu
local Challenges = module("Scripts/topple_challenges.lua")(Free)
local GLOBAL_SAVE = "Save/global_challenges.txt"
Challenges.load_global(fs.read(GLOBAL_SAVE))
-- The House's progress: the best stars of every room challenge (Save/house.txt; before the House, the living room's
-- stars were kept in Save/challenges.txt, which seeds it).
local house = House.new(Challenges.MAPS)
house:load(fs.read("Save/house.txt") or fs.read("Save/challenges.txt"))
_G.topple.house, _G.topple.House, _G.topple.load_room, _G.topple.Challenges = house, House, load_room, Challenges
-- (testing) Open every room and unlock every tool and size for this session; nothing is saved.
_G.topple.unlock_all = function(on) house.all = on ~= false; return house.all and "Every room and tool unlocked." or "Back to what you've earned." end
local open_house
-- Every mode reports its finished runs here. Returns what to announce, or nil.
local function report_run(stats)
    local new = Challenges.award(stats)
    if #new == 0 then return nil end
    if not (pcall(fs.write, GLOBAL_SAVE, Challenges.dump_global())) then return "Couldn't save your challenges." end
    sound("coin")
    return "Challenge complete: " .. new[1].name .. (#new > 1 and ("  (+" .. (#new - 1) .. " more)") or "")
end
-- The shared global challenges, as a 4-wide grid for any map's list. Four rows fill h.
local function challenge_grid(map, x, y, w, h, z)
    local gap = 10 * u
    local cw, ch = (w - 3 * gap) / 4, (h - 3 * gap) / 4
    for i, e in ipairs(Challenges.for_map(map).shared) do
        local cx, cy = x + (i - 1) % 4 * (cw + gap), y + floor((i - 1) / 4) * (ch + gap)
        panel(cx, cy, cw, ch, z, e.done and { 0.3, 0.18, 0.07, 0.98 } or { 0.17, 0.095, 0.05, 0.97 }, e.done and col4(GOLD, 0.8) or col4(RIM, e.here and 0.6 or 0.3), 10)
        local a = (e.here or e.done) and 1 or 0.5
        local sz = 40 * u
        image("Textures/star.png", cx + 12 * u, cy + (ch - sz) / 2, sz, sz, e.done and { 1, 0.78, 0.3, 1 } or { 0.27, 0.18, 0.1, 1 }, z + 1)
        local tx = cx + 62 * u
        local tw = cw - 70 * u
        text(e.g.name, tx, cy + ch * 0.26, 17 * u, col4(e.done and GOLD or CREAM, a), "left", z + 2, tw)
        if e.here or e.done then
            local line, n = "", 0
            for word in e.g.brief:gmatch("%S+") do
                if #line + #word + 1 > 34 then
                    n = n + 1
                    text(line, tx, cy + ch * 0.36 + n * 19 * u, 13 * u, col4(CREAM, 0.85), "left", z + 2, tw)
                    line = word
                else line = line == "" and word or (line .. " " .. word) end
            end
            text(line, tx, cy + ch * 0.36 + (n + 1) * 19 * u, 13 * u, col4(CREAM, 0.85), "left", z + 2, tw)
        else
            text("Needs " .. Challenges.MAPS[e.g.needs].name, tx, cy + ch * 0.62, 13 * u, col4(BRASS, 0.75), "left", z + 2, tw)
        end
    end
end
FreeView = module("Scripts/topple_free_view.lua")(Free, FreeWorld, {
    Challenges = Challenges, report_run = report_run, challenge_grid = challenge_grid,
    quad = quad, hide = hide, catcher = catcher, state = state, clicked = clicked, hovered = hovered, pid = pid, rect = rect,
    image = image, text = text, panel = panel, col4 = col4, commas = commas, ease_back = ease_back, sound = sound, clack = clack,
    edge = edge, SET = SET, L = L, u = function() return u end, back_to_menu = function() back_to_menu() end,
    house = house, House = House, load_room = load_room, lock = lock, open_house = function(tab, room) open_house(tab, room) end,
    C = { CREAM = CREAM, BRASS = BRASS, GOLD = GOLD, WALNUT = WALNUT, WALNUT_HI = WALNUT_HI, RIM = RIM, BAD = BAD, SAGE = SAGE, CLEAR = CLEAR },
})
_G.topple.free = FreeView
Hall = module("Scripts/topple_hall.lua")(Free, FreeWorld, module("Scripts/topple_hall_core.lua")(Free), {
    report_run = report_run, Challenges = Challenges, challenge_grid = challenge_grid,
    quad = quad, hide = hide, catcher = catcher, state = state, clicked = clicked, hovered = hovered, pid = pid, rect = rect, image = image,
    text = text, panel = panel, col4 = col4, commas = commas, sound = sound, clack = clack, edge = edge, SET = SET, L = L,
    u = function() return u end, back_to_menu = function() back_to_menu() end,
    C = { CREAM = CREAM, BRASS = BRASS, GOLD = GOLD, WALNUT = WALNUT, WALNUT_HI = WALNUT_HI, RIM = RIM, BAD = BAD, SAGE = SAGE, CLEAR = CLEAR },
})
_G.topple.hall = Hall
local TITLE_IDS = { "btn_card", "btn_challenge", "btn_free", "btn_table", "btn_hall", "btn_quit" }
local HOUSE_IDS = { "hm_back", "hm_block", "hm_build", "hm_card_block", "hm_tab1", "hm_tab2", "hm_tab3" }
for i = 1, #House.ROOMS do HOUSE_IDS[#HOUSE_IDS + 1] = "hm_room" .. i end
for k = 1, 3 do HOUSE_IDS[#HOUSE_IDS + 1] = "hm_tier" .. k end
local function hide_title() for _, id in ipairs(TITLE_IDS) do hide(id) end end
local function hide_house() for _, id in ipairs(HOUSE_IDS) do hide(id) end end
local function house_say(s) if S.hz then S.hz.msg, S.hz.msg_t = s, 3 end end
-- Free Build in a room (default: the last one built in), or one of its challenges. False if the room isn't made yet.
local function start_free(room_id, def)
    for _, id in ipairs(TABLE_IDS) do hide(id) end
    hide_title(); hide_house()
    World.show(false)
    local was = S.mode
    S.mode = "free"
    if not FreeView.enter(room_id, def) then
        S.mode = was
        World.show(true)
        house_say("That room isn't built yet: coming soon.")
        return false
    end
    SET:apply()
    return true
end
local function start_hall()
    if not hinge_field then return end     -- an engine build from before the hall can't draw it
    for _, id in ipairs(TABLE_IDS) do hide(id) end
    hide_title(); hide_house()
    World.show(false)
    S.mode = "hall"
    Hall.enter()
    SET:apply()
end
_G.topple.start_hall = start_hall
-- Out of Free Build or the hall, back to the table's world (the title and the House map show over it).
local function leave_play(next_mode)
    if S.mode == "hall" then
        Hall.leave()
        Hall.hide_all()
    elseif S.mode == "free" then
        FreeView.leave()
        FreeView.hide_all()
    end
    World.show(true)
    World.apply_look()
    S.mode, S.card_t = next_mode, 0
    SET:apply()
    pcall(settings.set, "shadows", true)
end
back_to_menu = function() hide_house(); leave_play("title") end
-- What the map shows for each room: whether it is made, and how many dominoes its build holds.
local function house_scan()
    local hz = S.hz
    hz.ready, hz.count = {}, {}
    for _, r in ipairs(House.ROOMS) do
        hz.ready[r.id] = load_room(r.id) ~= nil
        local b = FreeView.boards[r.id]
        local n = b and b.count
        if not n then
            local s = fs.read(FreeView.room_file("auto", nil, r.id))
            if s then n = 0; for _ in s:gmatch("\nd ") do n = n + 1 end end
        end
        hz.count[r.id] = n
    end
end
-- The House map. tab: "challenge" (the rooms' challenges), "free" (the rooms to build in) or "global"; room: open
-- that room's three levels.
open_house = function(tab, room)
    if S.mode == "free" or S.mode == "hall" then leave_play("house") else S.mode = "house" end
    hide_title()
    S.hz = { tab = tab or "challenge", room = room, t = 0, rt = 0, tt = 1, shake = {}, msg_t = 0 }
    house_scan()
end
_G.topple.open_house = function(tab, room) open_house(tab, room) end
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

-- The House map's clicks: tabs, a room (its tiers, or Free Build there), a tier (its challenge), back.
local function house_controls(enter)
    local hz = S.hz
    if hz.t < 0.2 then return end
    local back = pressed("Backspace") or clicked("hm_back")
    if hz.room then
        if back then sound("click"); hz.room = nil; return end
        for k = 1, 3 do
            if clicked("hm_tier" .. k) then
                local def = house:tiers(hz.room)[k]
                if def then sound("place"); start_free(hz.room, def) else sound("click") end
                return
            end
        end
        if clicked("hm_build") and house:free_open(hz.room) then sound("click"); start_free(hz.room) end
        return
    end
    if back then sound("click"); hide_house(); S.mode, S.card_t = "title", 0; return end
    for i, tab in ipairs({ "challenge", "free", "global" }) do
        if clicked("hm_tab" .. i) and hz.tab ~= tab then sound("click"); hz.tab, hz.tt = tab, 0 end
    end
    if hz.tab == "global" then return end
    for i, r in ipairs(House.ROOMS) do
        if clicked("hm_room" .. i) then
            sound("click")
            local prev = House.ROOMS[i - 1]
            if not hz.ready[r.id] then
                hz.shake[i] = 1; house_say("The " .. r.name .. " is coming soon.")
            elseif hz.tab == "challenge" then
                if house:is_open(r.id) then hz.room, hz.rt = r.id, 0
                else hz.shake[i] = 1; house_say("The " .. r.name .. " opens when you clear level 1 in the " .. prev.name .. ".") end
            elseif house:free_open(r.id) then
                start_free(r.id)
            else
                hz.shake[i] = 1; house_say("Clear level 1 in the " .. r.name .. " to build there.")
            end
            return
        end
    end
    if enter and hz.tab == "free" then
        local id = FreeView.S.room
        if house:free_open(id) then sound("click"); start_free(id) end
    end
end

------------------------------------------------------------------ quit, pause and back
-- Quit (engine.quit, as Echo Chamber's menu): what the mode autosaves is written first (a room's or the hall's build,
-- through their own leave; House progress is written as each level is recorded), and no chain is tipped nor a run counted.
local function quit_game()
    sound("click")
    if S.mode == "free" then FreeView.leave() elseif S.mode == "hall" then Hall.leave() end
    pcall(engine.quit)
end
_G.topple.quit = function() quit_game() end
-- Nothing held carries into the screen the player lands on.
local function flush_all()
    for _, key in ipairs(KEYS) do pressed(key) end
    FreeView.flush_keys()
    Hall.flush_keys()
end
-- To the title from anywhere: Free Build and the hall leave through their autosave; a table run is dropped as its MENU
-- button drops it, never tipped or counted.
local function to_menu()
    if S.mode == "free" or S.mode == "hall" then back_to_menu(); return end
    for _, id in ipairs(TABLE_IDS) do hide(id) end
    if S.mode ~= "house" and S.mode ~= "title" then World.clear() end
    hide_house()
    S.mode, S.card_t = "title", 0
end
-- The pause card (Esc wherever Esc has nothing nearer to close): RESUME, SETTINGS, BACK TO MENU (not on the title),
-- QUIT GAME. While it is up nothing moves: a running chain waits, and nothing under it takes a click.
local PAUSE_IDS = { "pz_block", "pz_resume", "pz_settings", "pz_menu", "pz_quit" }
local function open_pause() S.pause = { t = 0 }; flush_all() end
local function close_pause() S.pause = nil; for _, id in ipairs(PAUSE_IDS) do hide(id) end; flush_all() end
_G.topple.pause = function() open_pause() end
local function pause_controls(dt, esc)
    local P = S.pause
    P.t = P.t + dt
    if P.t < 0.12 then return end
    if esc or clicked("pz_resume") then sound("click"); close_pause()
    elseif pressed("Q") or clicked("pz_quit") then close_pause(); quit_game()
    elseif clicked("pz_settings") then sound("click"); close_pause(); SET:open(function() open_pause() end)
    elseif S.mode ~= "title" and clicked("pz_menu") then sound("click"); close_pause(); to_menu() end
end
-- Esc: up exactly one level. An open panel, card or canvas closes; the House map's level card goes to the map and the
-- map to the title; anywhere else (the title, a room, a level, the hall, a table run) the pause card opens.
-- A Table Run card: the tally closes (as if it had run out), the cleared, shop and game-over cards go back to the title
-- (as MENU does: the run is left, nothing more counted).
local function table_back()
    if S.mode == "tally" then after_tally() else to_menu() end
end
local TABLE_CARDS = { tally = true, cleared = true, shop = true, over = true }
local function go_back()
    sound("click")
    if TABLE_CARDS[S.mode] and run then table_back()
    elseif S.mode == "free" then if not FreeView.back() then open_pause() end
    elseif S.mode == "hall" then if not Hall.back() then open_pause() end
    elseif S.mode == "house" and S.hz then
        if S.hz.room then S.hz.room = nil else hide_house(); S.mode, S.card_t = "title", 0 end
    else open_pause() end
    flush_all()
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
    if S.mode == "house" then
        house_controls(enter)
        return
    end
    if TABLE_CARDS[S.mode] and clicked("btn_card_back") then sound("click"); table_back(); return end
    if S.mode == "title" then
        local ckey = pressed("C")
        if S.card_t > 0.3 and (ckey or clicked("btn_challenge")) then sound("click"); open_house("challenge")
        elseif S.card_t > 0.3 and (enter or clicked("btn_free")) then sound("click"); open_house("free")
        elseif S.card_t > 0.3 and (gkey or clicked("btn_hall")) then sound("click"); start_hall()
        elseif S.card_t > 0.3 and (tkey or clicked("btn_table")) then sound("click"); new_run()
        elseif S.card_t > 0.3 and (pressed("Q") or clicked("btn_quit")) then quit_game() end
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
    local hz = S.hz
    if S.mode == "house" and hz then
        hz.t, hz.rt, hz.tt = hz.t + dt, hz.rt + dt, hz.tt + dt
        hz.msg_t = max(0, hz.msg_t - dt)
        for i, v in pairs(hz.shake) do hz.shake[i] = max(0, v - dt * 2.5) end
    end
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
    if S.mode ~= "title" and S.mode ~= "house" then
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

-- The title card: CHALLENGE and FREE BUILD the two ways in, the Great Hall and Table Run below them.
local function draw_title(a)
    local w, h = L.w, L.h
    local cw, ch = 1000 * u, (best > 0 and 572 or 534) * u
    local x, y = (w - cw) / 2, (h - ch) / 2 + (1 - ease_back(S.card_t * 2.5)) * 30 * u
    panel(x, y, cw, ch, 81, col4({ 0.1, 0.055, 0.03, 0.97 }, a), col4(RIM, a), 20)
    local cx = x + cw / 2
    text("TOPPLE", cx, y + 80 * u, 86 * u, col4(CREAM, a), "center", 82, cw)
    text("Set up chain reactions of dominoes, then tip the first one.", cx, y + 150 * u, 22 * u, col4(CREAM, a), "center", 82, cw)
    local open_n = 0
    for _, r in ipairs(House.ROOMS) do if house:is_open(r.id) then open_n = open_n + 1 end end
    local nfree = #house:free_rooms()
    local BIG = {
        { "btn_challenge", "CHALLENGE", "C", "Textures/star.png", { 1, 0.78, 0.3, 1 }, { "Eight rooms of a house, three levels in each.", "Clear a room to unlock its tool." },
            house:total_stars() .. " of 72 stars  ·  " .. open_n .. (open_n == 1 and " room open" or " rooms open"), { 0.42, 0.25, 0.09 }, { 0.52, 0.31, 0.11 } },
        { "btn_free", "FREE BUILD", "Enter", "Textures/icon_tool_draw.png", { 1, 1, 1, 1 }, { "Thousands of dominoes in the rooms you've", "cleared, with the tools you've unlocked." },
            nfree .. (nfree == 1 and " room to build in" or " rooms to build in"), { 0.3, 0.17, 0.07 }, { 0.4, 0.23, 0.09 } },
    }
    local bw, bh, gap = 452 * u, 214 * u, 24 * u
    local by = y + 192 * u
    for k, b in ipairs(BIG) do
        local hvv = hv(b[1])
        local bx = cx - bw - gap / 2 + (k - 1) * (bw + gap)
        local e = ease_back(S.card_t * 3 - 0.25 - 0.12 * k)
        local yy = by + (1 - e) * 24 * u - hvv * 6 * u
        local f0, f1 = b[8], b[9]
        local fill = { f0[1] + (f1[1] - f0[1]) * hvv, f0[2] + (f1[2] - f0[2]) * hvv, f0[3] + (f1[3] - f0[3]) * hvv, 1 }
        if hvv > 0.02 then rect(bx - 6 * u, yy - 6 * u, bw + 12 * u, bh + 12 * u, CLEAR, 83, 20 * u, col4(GOLD, 0.35 * hvv * a)) end
        panel(bx, yy, bw, bh, 83, col4(fill, a), col4(GOLD, a * (0.7 + 0.3 * hvv)), 16)
        image(b[4], bx + 22 * u, yy + 20 * u, 58 * u, 58 * u, col4(b[5], a), 84)
        text(b[2], bx + bw / 2, yy + 52 * u, 42 * u, col4(GOLD, a), "center", 85, bw - 150 * u)
        text(b[3], bx + bw - 26 * u, yy + 30 * u, 15 * u, col4(BRASS, 0.9 * a), "right", 85, 100 * u)
        text(b[6][1], bx + bw / 2, yy + 112 * u, 16 * u, col4(CREAM, 0.92 * a), "center", 85, bw - 30 * u)
        text(b[6][2], bx + bw / 2, yy + 136 * u, 16 * u, col4(CREAM, 0.92 * a), "center", 85, bw - 30 * u)
        rect(bx + 40 * u, yy + 160 * u, bw - 80 * u, 1.5 * u, col4(RIM, 0.45 * a), 84)
        text(b[7], bx + bw / 2, yy + 186 * u, 16 * u, col4(GOLD, 0.95 * a), "center", 85, bw - 30 * u)
        catcher(b[1], bx, yy, bw, bh, 86)
    end
    hide("btn_card")
    local SMALL = { { "btn_hall", "GREAT HALL  ·  G", "five million dominoes on one floor" }, { "btn_table", "TABLE RUN  ·  T", "a toy chain, a score to beat" },
        { "btn_quit", "QUIT  ·  Q", "close the game" } }
    local sw2, sh2, sg = 296 * u, 62 * u, 16 * u
    local sy = by + bh + 26 * u
    for k, b in ipairs(SMALL) do
        local hvv = hv(b[1])
        local sx = cx - (#SMALL * sw2 + (#SMALL - 1) * sg) / 2 + (k - 1) * (sw2 + sg)
        local yy = sy - hvv * 3 * u
        panel(sx, yy, sw2, sh2, 83, col4(hvv > 0.5 and { 0.3, 0.17, 0.08, 1 } or { 0.2, 0.11, 0.05, 1 }, a), col4(hvv > 0.5 and GOLD or RIM, a), 12)
        text(b[2], sx + sw2 / 2, yy + 23 * u, 19 * u, col4(CREAM, a), "center", 84, sw2)
        text(b[3], sx + sw2 / 2, yy + 45 * u, 12 * u, col4(BRASS, 0.9 * a), "center", 84, sw2)
        catcher(b[1], sx, yy, sw2, sh2, 85)
    end
    text(best > 0 and ("Best table run: table " .. best) or "", cx, y + ch - 36 * u, 17 * u, col4(GOLD, a), "center", 82, cw)
end

-- The pause card, over everything (but the settings menu it can open).
local function draw_pause()
    local P = S.pause
    if not P or SET:is_open() then for _, id in ipairs(PAUSE_IDS) do hide(id) end; return end
    local w, h = L.w, L.h
    local a = min(1, P.t * 6)
    rect(0, 0, w, h, { 0.02, 0.012, 0.006, 0.55 * a }, 150)
    catcher("pz_block", 0, 0, w, h, 151)
    local rows = { { "pz_resume", "RESUME", "Esc" }, { "pz_settings", "SETTINGS" } }
    if S.mode ~= "title" then rows[#rows + 1] = { "pz_menu", "BACK TO MENU" } else hide("pz_menu") end
    rows[#rows + 1] = { "pz_quit", "QUIT GAME", "Q" }
    local where = ({ title = "TOPPLE", house = "the House", hall = "the Great Hall" })[S.mode]
    if S.mode == "free" then where = FreeView.S.ch and ("Challenge  ·  " .. (FreeView.S.ch.name or "")) or "Free Build" end
    where = where or "Table Run"
    local saves = (S.mode == "free" and not FreeView.S.ch) or S.mode == "hall"
    local bw, bh, gap = 380 * u, 62 * u, 14 * u
    local cw = bw + 80 * u
    local ch = 150 * u + #rows * (bh + gap) + 14 * u
    local x, y = (w - cw) / 2, (h - ch) / 2 + (1 - ease_back(P.t * 3)) * 30 * u
    panel(x, y, cw, ch, 152, col4({ 0.1, 0.055, 0.03, 0.97 }, a), col4(RIM, a), 20)
    text("PAUSED", x + cw / 2, y + 54 * u, 46 * u, col4(CREAM, a), "center", 153, cw)
    text(where, x + cw / 2, y + 98 * u, 17 * u, col4(GOLD, a), "center", 153, cw - 40 * u)
    text(saves and "Your build is saved when you leave." or "Nothing is tipped or counted when you leave.", x + cw / 2, y + 124 * u, 14 * u,
        col4(BRASS, 0.9 * a), "center", 153, cw - 40 * u)
    for i, r in ipairs(rows) do
        local hvv = hv(r[1])
        local bx, by = x + 40 * u, y + 150 * u + (i - 1) * (bh + gap) - hvv * 3 * u
        local quit = r[1] == "pz_quit"
        if hvv > 0.02 then rect(bx - 5 * u, by - 5 * u, bw + 10 * u, bh + 10 * u, CLEAR, 153, 16 * u, col4(GOLD, 0.35 * hvv * a)) end
        panel(bx, by, bw, bh, 154, col4(hvv > 0.5 and { 0.3, 0.17, 0.08, 1 } or { 0.2, 0.11, 0.05, 1 }, a), col4(hvv > 0.5 and GOLD or RIM, a), 12)
        text(r[2], bx + bw / 2, by + bh / 2, 22 * u, col4(quit and BAD or CREAM, a), "center", 155, bw - 120 * u)
        if r[3] then text(r[3], bx + bw - 20 * u, by + bh / 2, 14 * u, col4(BRASS, 0.9 * a), "right", 155, 70 * u) end
        catcher(r[1], bx, by, bw, bh, 157)
    end
end

-- The House map: a floor plan of the eight rooms (16 x 9 cells; the attic the strip upstairs), each with its name,
-- its stars out of 9 and what it unlocks, a lock on the rooms not open yet; a chosen room's three levels on a card.
local TIER_COL = { { 0.62, 0.8, 0.55, 1 }, { 0.88, 0.68, 0.38, 1 }, { 0.93, 0.45, 0.33, 1 } }
local function unlock_words(r)
    local t = {}
    for _, id in ipairs(r.unlocks.tools or {}) do t[#t + 1] = id:upper() end
    for _, s in ipairs(r.unlocks.sizes or {}) do t[#t + 1] = Free.SIZE_NAMES[s]:upper() end
    return table.concat(t, ", ")
end
local function tier_card(hz)
    local w, h = L.w, L.h
    local r = House.BY_ID[hz.room]
    local rt = hz.rt
    local ka = min(1, rt * 5)
    rect(0, 0, w, h, { 0.02, 0.012, 0.008, 0.55 * ka }, 92)
    catcher("hm_card_block", 0, 0, w, h, 93)
    local cw, ch = 1320 * u, 640 * u
    local x, y = (w - cw) / 2, (h - ch) / 2 + (1 - ease_back(rt * 3)) * 40 * u
    panel(x, y, cw, ch, 94, col4({ 0.1, 0.055, 0.03, 0.98 }, ka), col4(GOLD, 0.8 * ka), 20)
    local cx = x + cw / 2
    text(r.n .. "  ·  " .. r.name:upper(), cx, y + 54 * u, 44 * u, col4(GOLD, ka), "center", 95, cw - 300 * u)
    local nxt = House.ROOMS[r.n + 1]
    local why = house:cleared(r.id) and ("Cleared: " .. unlock_words(r) .. " unlocked, and you can build here.")
        or ("Clear level 1 to unlock " .. unlock_words(r) .. (nxt and (" and open the " .. nxt.name) or "") .. ".")
    text(why, cx, y + 102 * u, 17 * u, col4(CREAM, 0.95 * ka), "center", 95, cw - 80 * u)
    image("Textures/star.png", x + cw - 170 * u, y + 34 * u, 40 * u, 40 * u, col4({ 1, 0.78, 0.3, 1 }, ka), 95)
    text(house:stars(r.id) .. " / 9", x + cw - 122 * u, y + 54 * u, 26 * u, col4(CREAM, ka), "left", 95, 110 * u)
    local tiers = house:tiers(r.id)
    local tw, th, gap = 400 * u, 404 * u, 24 * u
    local ty = y + 138 * u
    if not house:has_challenges(r.id) then
        for k = 1, 3 do hide("hm_tier" .. k) end
        panel(x + 60 * u, ty, cw - 120 * u, th, 95, col4({ 0.14, 0.08, 0.04, 0.97 }, ka), col4(RIM, 0.5 * ka), 16)
        lock(cx, ty + 150 * u, 46 * u, 0.6 * ka, 96)
        text("No challenges in this room yet.", cx, ty + 230 * u, 30 * u, col4(CREAM, ka), "center", 96, cw - 160 * u)
        text("The " .. r.name .. "'s three levels are still being built. Come back soon.", cx, ty + 274 * u, 17 * u, col4(BRASS, ka), "center", 96, cw - 160 * u)
    else
        for k = 1, 3 do
            local def = tiers[k]
            local id = "hm_tier" .. k
            local e = ease_back(rt * 4 - 0.25 - 0.14 * k)
            local hvv = def and hv(id) or 0
            local tx = cx - (3 * tw + 2 * gap) / 2 + (k - 1) * (tw + gap)
            local yy = ty + (1 - e) * 36 * u - hvv * 7 * u
            local ca = ka * max(0, min(1, rt * 4 - 0.2 - 0.14 * k))
            if hvv > 0.02 then rect(tx - 6 * u, yy - 6 * u, tw + 12 * u, th + 12 * u, CLEAR, 95, 20 * u, col4(GOLD, 0.35 * hvv * ca)) end
            panel(tx, yy, tw, th, 95, col4(def and (hvv > 0.5 and WALNUT_HI or { 0.17, 0.095, 0.05, 0.98 }) or { 0.11, 0.06, 0.035, 0.97 }, ca),
                col4(hvv > 0.5 and GOLD or TIER_COL[k], (def and 0.8 or 0.35) * ca), 16)
            -- (the tier's ribbon)
            local rw = 150 * u
            panel(tx + (tw - rw) / 2, yy - 16 * u, rw, 34 * u, 96, col4({ 0.12, 0.065, 0.035, 1 }, ca), col4(TIER_COL[k], ca), 10)
            text("LEVEL " .. k, tx + tw / 2, yy + 1 * u, 16 * u, col4(TIER_COL[k], ca), "center", 97, rw)
            if def and k == 1 then
                text("clear it to unlock " .. (def.unlock and tostring(def.unlock):upper() or unlock_words(r)), tx + tw / 2, yy + 30 * u, 12 * u, col4(GOLD, 0.9 * ca), "center", 96, tw - 20 * u)
            end
            if def then
                text(def.name, tx + tw / 2, yy + 60 * u, 27 * u, col4(CREAM, ca), "center", 96, tw - 20 * u)
                for i, line in ipairs(wrap(def.brief or "", 40)) do
                    if i <= 3 then text(line, tx + tw / 2, yy + 84 * u + i * 22 * u, 15 * u, col4(CREAM, 0.88 * ca), "center", 96, tw - 20 * u) end
                end
                local B, extra = def.budget or {}, ""
                for _, g in ipairs({ "ball", "swing", "switch", "ramp" }) do
                    if (B[g] or 0) > 0 then extra = extra .. "  +  " .. B[g] .. " " .. g end
                end
                text((B.domino or 0) .. " dominoes" .. extra, tx + tw / 2, yy + 204 * u, 16 * u, col4(GOLD, ca), "center", 96, tw - 20 * u)
                if def.tools then
                    local names = {}
                    for _, t in ipairs(def.tools) do names[#names + 1] = t:upper() end
                    text("tools: " .. table.concat(names, "  ·  "), tx + tw / 2, yy + 230 * u, 13 * u, col4(BRASS, 0.9 * ca), "center", 96, tw - 20 * u)
                end
                -- (its challenges, 2, 3 or 4, a star each: gold for those held; then cleared or not, and the stars)
                local got, list = house.best[def.id], def.challenges or {}
                for i, c in ipairs(list) do
                    local ry = yy + 262 * u + (i - 1) * 21 * u
                    local held = house:done(def.id, c.id)
                    image("Textures/star.png", tx + 34 * u, ry - 8 * u, 16 * u, 16 * u, col4(held and { 1, 0.78, 0.3, 1 } or { 0.3, 0.2, 0.12, 1 }, ca), 96)
                    text(c.name, tx + 58 * u, ry, 14 * u, col4(held and GOLD or CREAM, (held and 1 or 0.75) * ca), "left", 96, tw - 80 * u)
                end
                local n = house:stars_for(def.id)
                text(not got and "not cleared yet" or (n == 0 and #list > 0) and ("cleared  ·  0 of " .. #list .. " stars")
                    or (#list > 0 and (n .. " of " .. #list .. " stars  ·  best " .. got.used .. " dominoes") or ("best: " .. got.used .. " dominoes")),
                    tx + tw / 2, yy + 352 * u, 14 * u, col4(got and GOLD or BRASS, 0.9 * ca), "center", 96, tw)
                text("PLAY", tx + tw / 2, yy + 380 * u, 20 * u, col4(GOLD, (0.45 + 0.55 * hvv) * ca), "center", 96, tw)
                catcher(id, tx, yy, tw, th, 98)
            else
                hide(id)
                lock(tx + tw / 2, yy + 170 * u, 34 * u, 0.45 * ca, 96)
                text("Not built yet", tx + tw / 2, yy + 230 * u, 22 * u, col4(CREAM, 0.5 * ca), "center", 96, tw)
                text("This puzzle is still being made.", tx + tw / 2, yy + 262 * u, 14 * u, col4(BRASS, 0.6 * ca), "center", 96, tw)
            end
        end
    end
    local bw2, bh2 = 220 * u, 54 * u
    local by2 = y + ch - bh2 - 22 * u
    local hb = hv("hm_back")
    panel(x + 40 * u, by2, bw2, bh2, 96, col4(hb > 0.5 and WALNUT_HI or { 0.17, 0.095, 0.05, 1 }, ka), col4(hb > 0.5 and GOLD or RIM, ka), 12)
    text("BACK  ·  Esc", x + 40 * u + bw2 / 2, by2 + bh2 / 2, 17 * u, col4(CREAM, ka), "center", 97, bw2)
    catcher("hm_back", x + 40 * u, by2, bw2, bh2, 98)
    if house:free_open(r.id) and hz.ready[r.id] then
        local hb2 = hv("hm_build")
        local bx3 = x + cw - 40 * u - bw2
        panel(bx3, by2, bw2, bh2, 96, col4(hb2 > 0.5 and { 0.5, 0.3, 0.1, 1 } or { 0.34, 0.2, 0.08, 1 }, ka), col4(GOLD, ka), 12)
        text("BUILD HERE", bx3 + bw2 / 2, by2 + bh2 / 2, 18 * u, col4(GOLD, ka), "center", 97, bw2)
        catcher("hm_build", bx3, by2, bw2, bh2, 98)
    else
        hide("hm_build")
    end
end

local function draw_house()
    local w, h, hz = L.w, L.h, S.hz
    local t = hz.t
    local a = min(1, t * 4)
    rect(0, 0, w, h, { 0.02, 0.015, 0.01, 0.62 * a }, 80)
    catcher("hm_block", 0, 0, w, h, 81)
    local pw, ph = 1600 * u, 950 * u
    local px, py = (w - pw) / 2, (h - ph) / 2 + (1 - ease_back(t * 2.5)) * 30 * u
    panel(px, py, pw, ph, 82, col4({ 0.1, 0.055, 0.03, 0.97 }, a), col4(RIM, a), 20)
    text("THE HOUSE", px + 44 * u, py + 54 * u, 48 * u, col4(CREAM, a), "left", 84, 460 * u)
    local open_n = 0
    for _, r in ipairs(House.ROOMS) do if house:is_open(r.id) then open_n = open_n + 1 end end
    image("Textures/star.png", px + 46 * u, py + 88 * u, 24 * u, 24 * u, col4({ 1, 0.78, 0.3, 1 }, a), 84)
    text(house:total_stars() .. " of 72 stars  ·  " .. open_n .. " of 8 rooms open  ·  " .. #house:free_rooms() .. " to build in",
        px + 78 * u, py + 100 * u, 16 * u, col4(BRASS, a), "left", 84, 600 * u)
    -- The tabs.
    local TABS = { { "challenge", "CHALLENGES" }, { "free", "FREE BUILD" }, { "global", "GLOBAL  " .. Challenges.global_count() .. " / " .. #Challenges.GLOBAL } }
    local tw, th = 230 * u, 54 * u
    for i, tb in ipairs(TABS) do
        local id = "hm_tab" .. i
        local on = hz.tab == tb[1]
        local hvv = hz.room and 0 or hv(id)
        local tx = px + pw - 44 * u - (4 - i) * (tw + 12 * u) + 12 * u
        panel(tx, py + 34 * u - hvv * 3 * u, tw, th, 84, col4(on and { 0.42, 0.25, 0.09, 1 } or (hvv > 0.5 and WALNUT_HI or { 0.17, 0.095, 0.05, 1 }), a),
            col4(on and GOLD or RIM, a), 12)
        text(tb[2], tx + tw / 2, py + 34 * u + th / 2 - hvv * 3 * u, 18 * u, col4(on and GOLD or CREAM, a), "center", 85, tw)
        catcher(id, tx, py + 34 * u, tw, th, 86)
    end
    -- The plan.
    local ax, ay, aw, ah = px + 44 * u, py + 140 * u, pw - 88 * u, ph - 140 * u - 100 * u
    local cs = min(aw / 16, ah / 9)
    local gx, gy = ax + (aw - 16 * cs) / 2, ay + (ah - 9 * cs) / 2
    local ta = a * min(1, hz.tt * 5)
    if hz.tab == "global" then
        for i = 1, #House.ROOMS do hide("hm_room" .. i) end
        challenge_grid("room", gx, gy, 16 * cs, 9 * cs, 84)
    else
        -- (the walls of the house: upstairs, and the ground floor)
        for _, b in ipairs({ { 0, 0, 16, 2.2 }, { 0, 2.6, 16, 6.4 } }) do
            rect(gx + b[1] * cs - 7 * u, gy + b[2] * cs - 7 * u, b[3] * cs + 14 * u, b[4] * cs + 14 * u, col4({ 0.05, 0.028, 0.015, 1 }, ta), 83, 10 * u, col4(RIM, 0.8 * ta))
        end
        text("UPSTAIRS", gx - 4 * u, gy + 2.4 * cs, 11 * u, col4(BRASS, 0.7 * ta), "left", 84, 200 * u)
        for i, r in ipairs(House.ROOMS) do
            local id = "hm_room" .. i
            local P = r.plan
            local ready = hz.ready[r.id]
            local open = hz.tab == "challenge" and house:is_open(r.id) or (hz.tab == "free" and house:free_open(r.id))
            local usable = ready and open
            local k = max(0, min(1, (hz.tt - 0.06 - 0.05 * i) * 4))
            local e = ease_back(k)
            local hvv = (hz.room or not usable) and 0 or hv(id)
            local sh = hz.shake[i] or 0
            local x0 = gx + P[1] * cs + 4 * u + sin(S.t * 46) * 7 * u * sh
            local y0 = gy + P[2] * cs + 4 * u + (1 - e) * 28 * u - hvv * 5 * u
            local cw, ch = P[3] * cs - 8 * u, P[4] * cs - 8 * u
            local ra = ta * k
            local cleared = house:cleared(r.id)
            local fill = usable and (hvv > 0.5 and { 0.34, 0.2, 0.09, 1 } or { 0.24, 0.135, 0.065, 1 }) or { 0.12, 0.068, 0.038, 1 }
            panel(x0, y0, cw, ch, 84, col4(fill, ra), col4(hvv > 0.5 and GOLD or (cleared and GOLD or RIM), ra * (usable and (0.65 + 0.35 * hvv) or 0.35)), 8)
            if usable then image("Textures/room_floor.png", x0 + 3 * u, y0 + 3 * u, cw - 6 * u, ch - 6 * u, { 0.62, 0.42, 0.26, 0.16 * ra }, 84.5) end
            -- (its number, in the corner)
            local br = 15 * u
            quad(pid("hmb"), { style = "text", label = "", x = x0 + 10 * u, y = y0 + 10 * u, width = 2 * br, height = 2 * br, z = 85,
                fill = col4(usable and { 0.42, 0.25, 0.09, 1 } or { 0.16, 0.09, 0.05, 1 }, ra), border = col4(usable and GOLD or RIM, ra * 0.8), corner_radius = br })
            text(tostring(i), x0 + 10 * u + br, y0 + 10 * u + br, 15 * u, col4(usable and GOLD or BRASS, ra), "center", 86, 2 * br, false)
            if cleared then text("CLEARED", x0 + cw - 12 * u, y0 + 22 * u, 12 * u, col4(GOLD, ra), "right", 86, 120 * u) end
            local ccx = x0 + cw / 2
            local top = y0 + (ch - 96 * u) / 2
            text(r.name, ccx, top + 14 * u, 25 * u, col4(CREAM, ra * (usable and 1 or 0.6)), "center", 86, cw - 70 * u)
            local unl = unlock_words(r)
            if not ready then
                text("coming soon", ccx, top + 50 * u, 17 * u, col4(BRASS, 0.75 * ra), "center", 86, cw - 20 * u)
                text("unlocks " .. unl, ccx, top + 82 * u, 13 * u, col4(BRASS, 0.5 * ra), "center", 86, cw - 20 * u)
            elseif not open then
                lock(ccx, top + 52 * u, 22 * u, 0.85 * ra, 86)
                local prev = House.ROOMS[i - 1]
                local need = hz.tab == "free" and "Clear its level 1 to build here" or ("Clear level 1 in the " .. (prev and prev.name or ""))
                text(need, ccx, top + 84 * u, 13 * u, col4(BRASS, 0.8 * ra), "center", 86, cw - 20 * u)
            elseif hz.tab == "challenge" then
                local sx = ccx - 34 * u
                image("Textures/star.png", sx - 12 * u, top + 36 * u, 26 * u, 26 * u, col4({ 1, 0.78, 0.3, 1 }, ra), 86)
                text(house:stars(r.id) .. " / 9", sx + 20 * u, top + 49 * u, 21 * u, col4(CREAM, ra), "left", 86, 100 * u)
                text((cleared and "unlocked " or "unlocks ") .. unl, ccx, top + 82 * u, 13 * u, col4(cleared and GOLD or BRASS, 0.9 * ra), "center", 86, cw - 20 * u)
            else
                local n = hz.count[r.id]
                text(n and n > 0 and (commas(n) .. (n == 1 and " domino" or " dominoes")) or ((r.id == "living" and not n) and "a sample chain to tip" or "an empty room"), ccx, top + 50 * u, 18 * u, col4(GOLD, ra), "center", 86, cw - 20 * u)
                text(r.id == FreeView.S.room and "where you last built  ·  Enter" or "build here", ccx, top + 82 * u, 13 * u, col4(BRASS, (0.6 + 0.4 * hvv) * ra), "center", 86, cw - 20 * u)
            end
            if hz.room then hide(id) else catcher(id, x0, y0, cw, ch, 87) end
        end
    end
    -- Along the bottom: back, and what to do (or what a click said).
    local bw2, bh2 = 220 * u, 54 * u
    local by2 = py + ph - bh2 - 28 * u
    if not hz.room then
        local hb = hv("hm_back")
        panel(px + 44 * u, by2, bw2, bh2, 84, col4(hb > 0.5 and WALNUT_HI or { 0.17, 0.095, 0.05, 1 }, a), col4(hb > 0.5 and GOLD or RIM, a), 12)
        text("BACK  ·  Esc", px + 44 * u + bw2 / 2, by2 + bh2 / 2, 17 * u, col4(CREAM, a), "center", 85, bw2)
        catcher("hm_back", px + 44 * u, by2, bw2, bh2, 86)
    end
    local hint = ({ challenge = "Choose a room and a level. Each room opens when you clear level 1 in the room before it.",
        free = "Build in the living room and every room you've cleared, with the tools you've unlocked.",
        global = "Challenges for any run you build yourself, in any room or the Great Hall." })[hz.tab]
    local msg = hz.msg_t > 0 and hz.msg
    text(msg or hint, px + pw / 2 + 120 * u, by2 + bh2 / 2, 16 * u, col4(msg and BAD or CREAM, a * (msg and min(1, hz.msg_t * 2) or 0.85)), "center", 85, pw - 400 * u)
    if hz.room then tier_card(hz) else hide("hm_card_block"); for k = 1, 3 do hide("hm_tier" .. k) end; hide("hm_build") end
end

-- A Table Run card's way back, at its bottom-left like every other card's: CLOSE (the tally) or BACK (to the title).
local function card_back(x, y, label, a, z)
    local bw, bh = 220 * u, 54 * u
    local hb = hv("btn_card_back")
    panel(x, y, bw, bh, z, col4(hb > 0.5 and WALNUT_HI or { 0.17, 0.095, 0.05, 1 }, a), col4(hb > 0.5 and GOLD or RIM, a), 12)
    text(label .. "  ·  Esc", x + bw / 2, y + bh / 2, 17 * u, col4(CREAM, a), "center", z + 1, bw)
    catcher("btn_card_back", x, y, bw, bh, z + 2)
end
local function draw_cards()
    local w, h = L.w, L.h
    local show = S.mode == "title" or S.mode == "cleared" or S.mode == "over" or S.mode == "shop"
    if not show or SET:is_open() then
        hide_title(); for i = 1, 4 do hide("buy" .. i) end
        if S.mode == "tally" and not SET:is_open() then
            local a = min(1, S.card_t * 4) * (1 - max(0, S.card_t - 1.3) / 0.4)
            local tw = 520 * u
            panel((w - tw) / 2, h * 0.3, tw, 172 * u, 70, col4(WALNUT, a), col4(RIM, a), 16)
            card_back((w - tw) / 2 + 20 * u, h * 0.3 + 104 * u, "CLOSE", a, 72)
            text("TIP " .. run.tb.tips_used .. "   +" .. commas(S.res.score), w / 2, h * 0.3 + 42 * u, 40 * u, col4(GOLD, a), "center", 71, tw)
            local tb = run.tb
            local msg = S.outcome == "cleared" and "Table cleared!" or (S.outcome == "over" and "Out of tips." or
                (commas(tb.target - tb.score) .. " to go  ·  " .. tb.tips_left .. (tb.tips_left == 1 and " tip left" or " tips left")))
            text(msg, w / 2, h * 0.3 + 84 * u, 20 * u, col4(CREAM, a), "center", 71, tw)
        else
            hide("btn_card_back")
        end
        return
    end
    local a = min(1, S.card_t * 3)
    rect(0, 0, w, h, { 0.02, 0.015, 0.01, 0.55 * a }, 80)
    if S.mode == "title" then hide("btn_card_back"); draw_title(a); return end
    hide("btn_challenge"); hide("btn_free")
    local cw, ch = 900 * u, 500 * u
    if S.mode == "shop" then cw, ch = 1240 * u, 620 * u end
    local x, y = (w - cw) / 2, (h - ch) / 2 + (1 - ease_back(S.card_t * 2.5)) * 30 * u
    panel(x, y, cw, ch, 81, col4({ 0.1, 0.055, 0.03, 0.97 }, a), col4(RIM, a), 20)
    local cx = x + cw / 2
    local btn
    if S.mode == "cleared" then
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
    local bw, bh = 340 * u, 70 * u
    local bx, by = cx - bw / 2, y + ch - 104 * u
    card_back(x + 40 * u, by + (bh - 54 * u) / 2, "BACK", a, 83)
    local hov = hovered("btn_card")
    panel(bx, by, bw, bh, 83, col4(hov and { 0.5, 0.3, 0.1, 1 } or { 0.42, 0.25, 0.09, 1 }, a), col4(GOLD, a), 14)
    text(btn .. "  ·  Enter", bx + bw / 2, by + bh / 2, 26 * u, col4(GOLD, a), "center", 84, bw)
    catcher("btn_card", bx, by, bw, bh, 85)
    hide("btn_table")
    hide("btn_hall")
end

-- dt: the smoothed frame step (camera, cards, effects); real: the time that actually passed, which drives a chain's
-- clock so it runs at the same speed at any frame rate (a 30 FPS unfocused window, a busy GPU).
local function present(dt, real)
    if layout() then for id in pairs(widgets) do widgets[id] = true; hide(id) end end
    local w, h = L.w, L.h
    u = min(w / 1920, h / 1080)
    S.fdt = dt
    if S.pause then dt, real = 0, 0 end          -- (paused: nothing moves, a running chain waits)
    if S.mode == "free" then
        FreeView.update(dt, real)
        FreeView.draw()
        draw_cards()
        draw_pause()
        flush_pools()
        return
    end
    if S.mode == "hall" then
        Hall.update(dt, real)
        Hall.draw()
        draw_cards()
        draw_pause()
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
    if S.mode == "house" then
        if SET:is_open() then hide_house() else draw_house() end
    end
    draw_pause()
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
        flush_all()
    elseif S.pause then
        pause_controls(dt, esc)
    elseif esc then
        go_back()
    else
        controls(dt)
        step(dt)
    end
    present(dt, real)
end, "play")

print("[Topple] Ready. C: Challenges, Enter: Free Build, G: the Great Hall, T: Table Run. Esc pause or back, Q quit, M mute.")
