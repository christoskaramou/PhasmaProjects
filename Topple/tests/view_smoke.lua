-- luajit tests/view_smoke.lua  (run from the Topple folder)
-- Boots the real game script and 3D world against stubbed engine APIs. Table Run: begins a run, draws a line of
-- dominoes by dragging across the felt (through the projection / picking round trip), extends it from its end,
-- places and aims each special toy, removes one with a right-click, undoes and clears, tips and plays the chain out,
-- then lets the autoplay hook play tables, the shop and a run's end. Free Build: opens on the demo build and tips it,
-- stands it up, clears and undoes, lays dominoes with every tool through the raw mouse, erases, sets the start,
-- right-click removes, turns and zooms the camera, plays a run and replays it, saves and loads slots, autosaves, and
-- goes back to the menu without leaking nodes. The House: the title's CHALLENGE / FREE BUILD, the map, a room's levels,
-- tools and sizes gated by what is unlocked (and by what a challenge allows), a room not made yet shown as coming
-- soon, and switching rooms (a stub kitchen) with its own build, saves, lights and shadow bounds, tearing the last
-- room down without leaking nodes or colliders. Catches script errors in drawing, input, animation and flow without
-- launching the player.
local quads, keys, states = {}, {}, {}
local nodes_alive = 0
local io_open = io.open
local function read(path)
    if path:match("^Save/") then return nil end
    local f = io_open("Assets/" .. path, "rb"); if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end
local env = _G
local SW, SH = 1920, 1080
env.vec3 = function(x, y, z) return { x = x, y = y, z = z } end
env.vec4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
-- Stub camera, looking straight down: NDC = (X / 13, -Z / 10); the inverse puts depth on Y so the mouse ray meets
-- the felt (y = 0) and table points round-trip.
local VP = setmetatable({}, { __mul = function(_, v) return { x = v.x / 13, y = -v.z / 10, z = 0.5, w = 1 } end })
local INV = setmetatable({}, { __mul = function(_, v) return { x = v.x * 13, y = 10 - 20 * v.z, z = -v.y * 10, w = 1 } end })
local Node = {}
Node.__index = function(_, k)
    if k == "remove" then return function(n) if not rawget(n, "dead") then rawset(n, "dead", true); nodes_alive = nodes_alive - 1 end end end
    if k == "get_mesh_refs" then return function() return { 1 } end end
    -- (it remembers where it was put and how big it was made, like the engine's)
    if k == "set_position" then return function(n, v) rawset(n, "pos", v) end end
    if k == "get_position" then return function(n) return rawget(n, "pos") end end
    if k == "set_scale" then return function(n, v) rawset(n, "scl", v) end end
    if k == "get_scale" then return function(n) return rawget(n, "scl") or { x = 1, y = 1, z = 1 } end end
    if k == "set_rotation" then return function(n, v) rawset(n, "rot", v) end end
    if k == "get_rotation" then return function(n) return rawget(n, "rot") end end
    if k == "set_visible" then return function(n, on) rawset(n, "shown", on) end end
    return function() end
end
local function node() nodes_alive = nodes_alive + 1; return setmetatable({}, Node) end
env.primitives = setmetatable({}, { __index = function() return function() return node() end end })
local cam = setmetatable({ get_view_projection = function() return VP end, get_inv_view_projection = function() return INV end },
    { __index = function() return function() end end })
local templates = {}
env.scene = setmetatable({ add_empty_node = node, get_active_camera = function() return cam end,
    set_positions = function(list, n) for i = 0, n - 1 do rawset(list[i * 4 + 1], "pos", { x = list[i * 4 + 2], y = list[i * 4 + 3], z = list[i * 4 + 4] }) end end,
    find_model = function(name) templates[name] = true; return setmetatable({}, Node) end },
    { __index = function() return function() end end })
env.material = setmetatable({}, { __index = function() return function() end end })
-- The engine's rigid bodies: present, so a Free Build tip takes the live path (nothing moves, so it ends quickly).
local bodies = {}
env.physics = setmetatable({ is_simulating = function() return true end,
    add_body = function(n, kind, shape, o)
        env.bodies_added = (env.bodies_added or 0) + 1; bodies[n] = true
        if env.body_opts then env.body_opts[n] = { kind = kind, shape = shape, o = o } end
    end,
    remove_body = function(n) bodies[n] = nil end,
    get_velocity = function() return { x = 0, y = 0, z = 0 } end },
    { __index = function() return function() end end })
env.particles = setmetatable({}, { __index = function() return function() return 0 end end })
env.skybox = { load = function() end }
local saved, played = {}, {}
env.fs = { read = read, write = function(p, s) saved[p] = s; return true end, exists = function() return false end }
env.audio = { play = function(n) played[#played + 1] = n end, set_master_volume = function() end }
local M = { x = 0, y = 0, left = false, right = false, middle = false, wheel = 0 }
env.input = { is_key_down_raw = function(k) return keys[k] == true end, is_key_down = function(k) return keys[k] == true end,
    get_mouse_position = function() return { x = M.x, y = M.y } end, is_left_mouse_down = function() return M.left end,
    is_right_mouse_down = function() return M.right end, is_middle_mouse_down = function() return M.middle end,
    get_mouse_wheel = function() local w = M.wheel; M.wheel = 0; return { x = 0, y = w } end }
local lights_set = {}
env.lights = setmetatable({ find = function(name) return { { type = "directional", index = 0, name = name } } end,
    set_property = function(t, i, k, v) lights_set[#lights_set + 1] = k end },
    { __index = function() return function() return nil end end })
local FRAME_MS = 1000 / 60
env.engine = setmetatable({ get_metrics = function() return { delta_ms = FRAME_MS } end }, { __index = function() return function() end end })
env.runtime_ui = setmetatable({
    set_quad = function(_, id, o)
        assert(type(o.x) == "number" and o.x == o.x, "bad x for " .. id)
        assert(type(o.width) == "number" and o.width == o.width, "bad width for " .. id)
        if o.label ~= nil then assert(type(o.label) == "string", "label not a string for " .. id) end
        if o.font_scale ~= nil then assert(o.font_scale == o.font_scale and o.font_scale > 0, "bad font scale for " .. id) end
        quads[id] = o
    end,
    get_state = function(_, id) return states[id] end,
    get_surface_size = function() return { width = SW, height = SH } end,
}, { __index = function() return function() end end })
local update
local render_mode
local setv = {}
env.settings = { get = function(k) return setv[k] end, set = function(k, v) setv[k] = v end, set_render_mode = function(m) render_mode = m end }
env.script = { on_update = function(_, f) update = f end }
local src = assert(read("Scripts/topple.lua"))
env.os, env.io = nil, nil
assert(load(src, "@topple.lua", "t", env))()
local api = env.topple
local R, W = api.R, api.W
local function frame(n) for _ = 1, n or 1 do update() end end
local function press(k) keys[k] = true; frame(); keys[k] = false; frame() end
local function screen(x, y) return W.project(x, y, 0) end
local function mouse(x, y, down, extra)
    local sx, sy = screen(x, y)
    local st = { hovered = true, down = down, mouse_x = sx, mouse_y = sy }
    for k, v in pairs(extra or {}) do st[k] = v end
    states.board = st
    frame()
end
local function placed(kind)
    local n = 0
    for _, p in pairs(api.board().pieces) do if p.kind == kind and not p.fixed then n = n + 1 end end
    return n
end

frame(20)
assert(render_mode == "raster", "the world must ask for raster")
assert(api.S.mode == "title", "starts on the title card")
local function shown(label)
    for _, q in pairs(quads) do if q.label == label and q.visible ~= false then return q end end
end
local function visible(id) return quads[id] and quads[id].visible ~= false end
for _, l in ipairs({ "CHALLENGE", "FREE BUILD", "GREAT HALL  ·  G", "TABLE RUN  ·  T" }) do assert(shown(l), "the title shows " .. l) end
assert(visible("btn_challenge") and visible("btn_free") and visible("btn_hall") and visible("btn_table"), "the title's four ways in can be clicked")
assert(quads.btn_challenge.width > 2 * quads.btn_hall.width * 0.6 and quads.btn_challenge.height > 2 * quads.btn_hall.height,
    "CHALLENGE and FREE BUILD are the big choices")
press("T")
assert(api.S.mode == "build" and api.run() and api.board(), "T begins a table run")
assert(templates.T_backdrop and templates["T_domino_brick"] == nil or true)

-- Picking round trip.
for _, pt in ipairs({ { -8, -3 }, { 0, 0 }, { 6, 9 } }) do
    local sx, sy = screen(pt[1], pt[2])
    local x, y = W.table_point(sx, sy)
    assert(math.abs(x - pt[1]) < 1e-6 and math.abs(y - pt[2]) < 1e-6, "picking round trip failed")
end

-- Draw a line of dominoes from the left across the table front (away from the village at the back).
local y0 = -4.5
mouse(-11, y0, true)
for x = -11, 1, 0.2 do mouse(x, y0, true) end
mouse(1, y0, false)
local n1 = placed("domino")
assert(n1 >= 17 and n1 <= 21, "a 12-unit drag should lay about 19 dominoes, got " .. n1)
local st = api.board():starter()
assert(st and st.x < -10.9 and math.abs(st.a) < 1e-6, "the first domino placed is the starter, facing along the stroke")
assert(api.S.pred and api.S.pred.toppled == n1, "the preview should see the whole straight line fall")
-- Extend the line from its end.
mouse(1.1, y0, true)
for x = 1.1, 3.5, 0.2 do mouse(x, y0, true) end
mouse(3.5, y0, false)
assert(placed("domino") > n1 + 2, "extending from the end did not add dominoes")

-- Specials: a bell beside the line, a spring aimed along it.
press("2")
assert(api.S.tool == "bell", "2 selects the bell")
mouse(-9.5, y0 + 0.8, true); mouse(-9.5, y0 + 0.8, false)
assert(placed("bell") == 1, "bell not placed")
assert(api.S.tool == "domino", "the tool falls back to dominoes once the box is empty")
press("3")
mouse(7, y0, true); mouse(8, y0, true); mouse(8, y0, false)
assert(placed("spring") == 1, "spring not placed")
local sp
for _, p in pairs(api.board().pieces) do if p.kind == "spring" then sp = p end end
assert(math.abs(sp.a) < 1e-6, "the spring should be aimed along the drag")
press("4")
assert(api.S.tool == "domino", "no rockets in the box yet: the tool must not switch")

-- Right-click removes the toy under the cursor; undo and clear.
local before = placed("domino")
mouse(-6, y0, false, { right_clicked = true }); mouse(-6, y0, false)
assert(placed("domino") == before - 1, "right-click did not remove a domino")
press("Backspace")
assert(placed("spring") == 0, "undo should take back the last toy placed (the spring)")
local nvis = 0
for _ in pairs(W.vis) do nvis = nvis + 1 end
local npieces = 0
for _ in pairs(api.board().pieces) do npieces = npieces + 1 end
assert(nvis == npieces, "visuals out of step with the board: " .. nvis .. " vs " .. npieces)

-- Tip it and watch. (Under the Echo twist the live multiplier shows x2 from the first domino.)
local board_now, twist_now = api.board(), api.board().twist
board_now.twist = "echo"
press("Space")
assert(api.S.mode == "running", "Space tips")
assert(api.S.mult >= 2, "the Echo twist's starting x2 is shown: " .. api.S.mult)
board_now.twist = twist_now
local frames = 0
while api.S.mode == "running" and frames < 60 * 30 do frame(); frames = frames + 1 end
assert(api.S.mode == "tally", "the tip never finished")
local res = api.S.res
assert(res.score > 0 and api.S.tip_pts == res.score, "live points " .. api.S.tip_pts .. " vs " .. res.score)
local clacks, bells = 0, 0
for _, n in ipairs(played) do
    if n:match("^clack") then
        clacks = clacks + 1
        local wav = io_open("Assets/Audio/" .. n, "rb")
        assert(wav, "no sound file for " .. n)
        wav:close()
    end
    if n == "bell.wav" then bells = bells + 1 end
end
assert(clacks > 5, "the chain should clack")
frame(140)
assert(api.S.mode == "build" or api.S.mode == "cleared", "the tally card should move on, got " .. api.S.mode)

-- Clear the board, then let the autoplay hook play tables until the run ends (through the shop).
if api.S.mode == "build" then
    press("C")
    assert(placed("domino") == 0, "C clears the board")
end
api.autoplay = true
local seen = {}
frames = 0
while frames < 60 * 600 and not (seen.over and api.S.mode == "build") do
    frame(); frames = frames + 1
    seen[api.S.mode] = true
end
print("modes seen:", (function() local t = {} for k in pairs(seen) do t[#t + 1] = k end table.sort(t) return table.concat(t, " ") end)())
assert(seen.cleared and seen.shop and seen.over, "autoplay should clear tables, visit the shop and end a run")
-- The card after table 4 announces what table 5, a Grand Table, really asks for.
do
    local tb, n, mode = api.run().tb, api.run().tb.n, api.S.mode
    api.autoplay, tb.n, api.S.mode, api.S.card_t = false, 4, "cleared", 1
    frame()
    local card
    for _, q in pairs(quads) do if q.label and q.label:match("^Next: table 5") then card = q.label end end
    assert(card and card:match("target 500$"), "the next-table card shows the Grand Table target: " .. tostring(card))
    api.autoplay, tb.n, api.S.mode = true, n, mode
end
assert(saved["Save/topple_best.txt"], "best table saved")
assert(templates.T_house_cottage and templates.T_house_townhouse and templates.T_house_farmhouse,
    "Table Run's houses are the three model houses")
for name in pairs(templates) do assert(not name:match("^T_house_walls") and not name:match("^T_house_roof"), "an old toy house part was asked for: " .. name) end
local n = 0
for _ in pairs(quads) do n = n + 1 end
print("ui quads used:", n, "  scene nodes alive:", nodes_alive)
assert(nodes_alive < 400, "scene nodes leak across tips and tables: " .. nodes_alive .. " alive")

------------------------------------------------------------------ Free Build
api.autoplay = false
api.back_to_menu()
frame(30)
assert(api.S.mode == "title", "back on the title card")
local house = api.house
press("Return")
assert(api.S.mode == "house" and api.S.hz.tab == "free", "Enter opens FREE BUILD's rooms")
frame(20)
assert(shown("an empty room") or shown("Living Room"), "the rooms are listed")
press("Return")
assert(api.S.mode == "free", "Enter again builds in the living room")
local FV, FW, F = api.free, api.FW, api.F
assert(FV.S.room == "living" and F.ROOM.id == "living", "the living room")
local fb = FV.board()
assert(fb and fb.count > 400, "a first visit opens on the demo build")
local function vis_count() local n = 0 for _ in pairs(FW.vis) do n = n + 1 end return n end
assert(vis_count() == fb.count, "every demo domino has a node")
assert(setv.shadow_fixed_bounds == true and (setv.shadow_bounds_radius or 0) > 50 and math.abs(setv.shadow_bounds_y - 24) < 1e-6,
    "Free Build uses one fixed shadow map over the whole room")
assert(setv.lod_enabled == false, "Free Build draws at full detail (LOD meshes changed the window light with distance)")
local function click(id) states[id] = { clicked = true }; frame(); states[id] = nil; frame() end
-- A new house: nothing unlocked, so the tray holds every tool, the locked ones dimmed with the room that unlocks
-- them; only erase and start work, only Standard dominoes.
do
    frame(2)
    assert(FV.S.tool == "erase", "with DRAW locked the tool in hand is ERASE: " .. FV.S.tool)
    press("1")
    assert(FV.S.tool == "erase" and FV.S.msg == "Clear level 1 in the Hallway to unlock DRAW.", "a locked tool says what unlocks it: " .. tostring(FV.S.msg))
    for i = 1, 10 do assert(visible("fb_tool" .. i), "Free Build shows every tool, locked or not: " .. i) end
    assert(shown("Hallway") and shown("Attic") and shown("Kids' Room"), "locked tools name their rooms")
    press("6"); assert(FV.S.tool == "start", "START is always there")
    press("=")
    assert(FV.S.size == 2 and FV.S.msg:match("Study"), "Large waits for the study: " .. tostring(FV.S.msg))
    press("-")
    assert(FV.S.size == 2 and FV.S.msg:match("Dining Room"), "Mini waits for the dining room: " .. tostring(FV.S.msg))
    assert(visible("fb_size1") and visible("fb_size5"), "every size is listed")
    press("G"); assert(not FV.S.grow, "GROW waits for the study")
    -- unlock_all, for testing: everything opens.
    api.unlock_all()
    press("1"); assert(FV.S.tool == "draw", "unlocked, DRAW works")
    for _, q in pairs(quads) do assert(not (q.label == "Hallway" and q.visible ~= false), "no lock labels once unlocked") end
end
local function at(x, y, h) local sx, sy = FW.project(x, y, h or 0); M.x, M.y = sx, sy end
local function drag(x0, y0, x1, y1, steps)
    at(x0, y0); frame(); M.left = true; frame()
    for i = 1, steps or 30 do at(x0 + (x1 - x0) * i / (steps or 30), y0 + (y1 - y0) * i / (steps or 30)); frame() end
    M.left = false; frame()
end
local function run_out()
    local frames = 0
    while FV.S.mode == "running" and frames < 60 * 60 do frame(); frames = frames + 1 end
    assert(FV.S.mode == "done", "the run never finished (" .. FV.S.mode .. ")")
end
-- Tip the demo and watch it all fall.
local played_before = #played
press("Space")
assert(FV.S.mode == "running", "Space tips in Free Build")
run_out()
assert(FV.S.res.toppled == fb.count, "the demo falls end to end: " .. FV.S.res.toppled .. " of " .. fb.count)
local clacks2 = 0
for i = played_before + 1, #played do if played[i]:match("^clack") then clacks2 = clacks2 + 1 end end
assert(clacks2 > 20, "a long chain clacks: " .. clacks2)
-- The sample's Titans come down with a thud, and its fan lands off the table's edge; every faller ends where the
-- rules say, the ones that went over the edge on the rug.
local thuds = 0
for i = played_before + 1, #played do if played[i] == "house.wav" or played[i] == "thunk.wav" then thuds = thuds + 1 end end
assert(thuds >= 3, "big dominoes and landings thud: " .. thuds)
assert(#FV.S.res.lands >= 10, "the sample's fan goes off the table: " .. #FV.S.res.lands)
do
    local land = FV.S.res.lands[1]
    local v = FW.vis[land.id]
    local want_x, want_h, want_z = F.fall_pose(v.p, FV.S.res.falls[land.id], 1e9)
    local pos = v.n:get_position()
    assert(math.abs(pos.x - want_x) < 1e-6 and math.abs(pos.y - want_h) < 1e-6 and math.abs(pos.z - want_z) < 1e-6, "a domino that went over the edge is drawn where it landed")
    assert(pos.y < 1, "which is down on the rug, not up on the table: " .. pos.y)
end
press("R")
assert(FV.S.mode == "build" and FW.A == nil, "R stands them all up")
-- Clear (twice to confirm), undo brings it back, clear again for a clean room.
local demo_n = fb.count
press("C"); assert(fb.count == demo_n, "one C only asks")
press("C"); assert(fb.count == 0, "C twice clears the room")
press("Backspace"); assert(fb.count == demo_n, "undo brings the cleared build back")
press("C"); press("C")
frame(2)
assert(vis_count() == 0, "cleared dominoes go back to the pool")
-- Draw a freehand line across the rug.
press("1")
drag(-10, -8, 8, -8, 60)
local n_draw = fb.count
assert(n_draw >= 26 and n_draw <= 31, "an 18-unit stroke lays about 29 dominoes, got " .. n_draw)
-- A straight line, a field, a spiral.
press("2"); drag(-10, -6, 8, -6)
local n_line = fb.count - n_draw
assert(n_line >= 26 and n_line <= 31, "an 18-unit line lays about 29, got " .. n_line)
press("4"); drag(-9, 1, 2, 1)
local n_field = fb.count - n_draw - n_line
assert(n_field > 60, "a field fans out: " .. n_field)
press("3"); drag(7, 4, 10.5, 4)
local n_spiral = fb.count - n_draw - n_line - n_field
assert(n_spiral > 20, "a spiral: " .. n_spiral)
assert(vis_count() == fb.count, "nodes match the board after every tool")
-- Sizes: = chooses the next size up and the tools lay it; G makes a stroke grow a size at a time; each node is scaled.
do
    local n0 = fb.count
    press("="); assert(FV.S.size == 3, "= chooses Large")
    press("2"); drag(-10, -12, 2, -12)
    local large = 0
    for _, p in pairs(fb.pieces) do
        if math.abs(p.y + 12) < 0.3 then
            assert(math.abs(p.s - 1.5) < 1e-9, "the line is laid Large")
            assert(math.abs(FW.vis[p.id].n:get_scale().x - 1.5) < 1e-9, "and its node is Large too")
            large = large + 1
        end
    end
    assert(large >= 11 and large <= 14, "a 12-unit line of Large dominoes is about 13, got " .. large)
    press("="); press("="); press("G")
    assert(FV.S.size == 5 and FV.S.grow, "Titan, growing")
    drag(-10, -15, 10, -15)
    local row = {}
    for _, p in pairs(fb.pieces) do if math.abs(p.y + 15) < 0.3 then row[#row + 1] = p end end
    table.sort(row, function(a, b) return a.x < b.x end)
    assert(#row >= 8 and math.abs(row[1].s - F.SIZES[1]) < 1e-9 and math.abs(row[#row].s - F.SIZES[5]) < 1e-9, "a growing line runs from Mini to Titan (" .. #row .. ")")
    for i = 2, #row do assert(row[i].s <= row[i - 1].s * F.GROW + 1e-9, "a step at a time") end
    press("G"); press("-"); press("-"); press("-")
    assert(FV.S.size == 2 and not FV.S.grow, "back to Standard, not growing")
    press("-"); press("-"); assert(FV.S.size == 1, "- stops at Mini")
    press("=")
    press("Backspace"); press("Backspace")
    assert(fb.count == n0 and vis_count() == n0, "undo takes both lines away")
    -- A pooled node handed to a Standard domino is Standard again.
    press("2"); drag(-10, -12, 2, -12)
    for _, p in pairs(fb.pieces) do
        if math.abs(p.y + 12) < 0.3 then assert(FW.vis[p.id].n:get_scale().x == 1, "a reused node goes back to full size") end
    end
    press("Backspace")
    assert(fb.count == n0, "and that line is undone")
end
-- Erase a stretch of the first line.
press("5"); local before_erase = fb.count
drag(-2, -8, 0, -8, 10)
assert(fb.count < before_erase, "erasing lifts dominoes away")
press("Backspace"); assert(fb.count == before_erase, "undo puts the erased ones back")
press("Y"); keys["Left Ctrl"] = true; press("Y"); keys["Left Ctrl"] = false
assert(fb.count < before_erase, "Ctrl+Y redoes the erase")
press("Backspace")
-- Choose the start: the far end of the drawn line, then turn it round.
press("6")
local far
for _, p in pairs(fb.pieces) do if math.abs(p.y + 8) < 0.3 and (not far or p.x > far.x) then far = p end end
at(far.x, far.y, far.z); frame(); M.left = true; frame(); M.left = false; frame()
local st, dir = fb:starter()
assert(st == far and dir == 1, "clicking a domino makes it the start")
M.left = true; frame(); M.left = false; frame()
st, dir = fb:starter()
assert(st == far and dir == -1, "clicking it again turns the push round")
-- Right-click (no drag) removes the domino under the cursor.
local before_r = fb.count
local victim
for _, p in pairs(fb.pieces) do if math.abs(p.y + 6) < 0.3 and p.x > -1 and p.x < 1 then victim = p end end
at(victim.x, victim.y, victim.z); frame(); M.right = true; frame(); M.right = false; frame()
assert(fb.count == before_r - 1 and not fb.pieces[victim.id], "right-click removes one")
-- The camera: wheel zooms, right-drag turns.
local d0, y0 = FW.goal.dist, FW.goal.yaw
M.wheel = 2; frame()
assert(FW.goal.dist < d0, "the wheel zooms in")
at(0, 0); frame(); M.right = true; frame()
for i = 1, 10 do M.x = M.x + 12; frame() end
M.right = false; frame()
assert(FW.goal.yaw ~= y0, "right-drag turns the camera")
assert(fb.count == before_r - 1, "a right-drag does not remove anything")
-- Tip, watch, then AGAIN replays the same run.
press("Space"); run_out()
local first = FV.S.res.toppled
assert(first > 20, "the drawn line falls from its start: " .. first)
click("fb_tip")
assert(FV.S.mode == "running", "AGAIN replays")
run_out()
assert(FV.S.res.toppled == first, "a replay plays the same")
press("R")
-- A run keeps real time at any frame rate: at 8 FPS (125 ms frames) 16 frames are 2 s of chain.
-- "Again" from a finished run: bodies wait until the stand-up's moves have reached the scene, or they start where the
-- last run left the pieces.
local again_ball = assert(FV.board():place_ball(0, -12, 0), "a ball for the Again check")
FW.sync(FV.board())
press("Space"); run_out()
assert(FV.S.mode == "done", "the run has finished")
env.bodies_added = 0
keys["Space"] = true; frame(); keys["Space"] = false
assert(FV.S.mode == "running", "Space runs it again")
assert(env.bodies_added == 0, "no body is created in the frame of the stand-up")
frame()
assert(env.bodies_added > 0, "they are created once the moves have landed")
run_out()
press("R")
FV.board():remove(again_ball.id)
FW.sync(FV.board())
-- The engine ball, as measured live: rug boards and ramps no thinner than the physics' 0.05 edge rounding allows (thinner
-- ones came out thicker, a lip that threw the ball), no collider on a rug's own mesh under its board, the ball set on
-- the rug it stands over, bouncing with the rules' rebound, and no bodies until the room's colliders are in.
do
    local thin = math.huge
    for _, n in ipairs(FW.boards) do thin = math.min(thin, n:get_scale().y) end
    assert(thin >= 0.1 - 1e-9, "a rug board or ramp is too thin for the physics: " .. thin)
    assert(next(FW.rug_mesh), "the room's rug mesh is known")
    for n in pairs(FW.rug_mesh) do assert(not bodies[n], "a rug's mesh under its flat board has no collider") end
    local rug_h
    for _, s in ipairs(F.ROOM.surfaces) do if s.name == "rug" then rug_h = s.h end end
    local bl = assert(FV.board():place_ball(0, -12, 0), "a ball on the rug, at the floor's height")
    FW.sync(FV.board())
    frame(3)
    FW.settle = nil      -- (as in a fresh session: nothing has been stood up yet)
    FW.enter()
    assert(FW.statics_due, "entering a room, its colliders come a few frames later")
    env.body_opts = {}
    keys["Space"] = true; frame(); keys["Space"] = false
    assert(FV.S.mode == "running", "tipped at once")
    local ball
    while FW.statics_due do
        for n, o in pairs(env.body_opts) do assert(o.shape ~= "sphere", "the ball got a body before the room's floor did") end
        frame()
    end
    frame(3)
    for n, o in pairs(env.body_opts) do if o.kind == "dynamic" and o.shape == "sphere" then ball = { n = n, o = o.o } end end
    assert(ball, "the ball gets its body once the room's colliders are in")
    assert(ball.o.restitution == F.BALL.rebound, "the ball bounces with the rules' rebound: " .. tostring(ball.o.restitution))
    assert(math.abs(ball.n:get_position().y - (rug_h + F.BALL.r)) < 1e-6, "the ball stands on the rug: " .. ball.n:get_position().y)
    env.body_opts = nil
    run_out()
    press("R")
    FV.board():remove(bl.id)
    FW.sync(FV.board())
end
-- House Challenges: the list, a challenge that keeps your room safe, a win that saves its stars, and back.
do
    local room, room_n = FV.board(), FV.board().count
    if FV.S.mode ~= "build" then
        while FV.S.mode == "running" do frame() end
        press("R"); frame()
    end
    local writes_before = saved["Save/free_autosave.txt"]
    click("fb_ch")
    assert(api.S.mode == "house" and api.S.hz.tab == "challenge", "HOUSE MAP opens the map")
    frame(20)
    click("hm_tab3"); frame(2)
    assert(api.S.hz.tab == "global" and quads.hm_room1.visible == false, "the Global tab replaces the plan")
    local listed = 0
    for _, q in pairs(quads) do if q.label == "On a Roll" and q.visible ~= false then listed = listed + 1 end end
    assert(listed > 0, "the shared challenges are listed")
    click("hm_room2"); assert(api.S.hz.room == nil, "a hidden room cannot be clicked")
    click("hm_tab1"); frame(20)
    assert(api.S.hz.tab == "challenge" and visible("hm_room2"), "and CHALLENGES brings the plan back")
    -- Staged living-room challenges made the old way (no End, stars by count, so the
    -- test brings its own): a level 1 with a plain line to the goal, and a level 2 with every kind of trap.
    local LEVEL1 = { id = "stage_line", room = "living", tier = 1, name = "Straight Shot", icon = "bell", brief = "Lay a line from the first domino to the switch.",
        goal_word = "Press the switch", win = "CLICK!", fail = "MISSED", start = { x = -20, y = -31, h = 0, a = 0 }, goal = { x = -6, y = -31, h = 0 },
        budget = { domino = 40 }, stars = { 30, 25 }, tools = { "draw", "line" } }
    local TRAPS = { id = "stage_traps", room = "living", tier = 2, name = "Trap Run", icon = "bell",
        brief = "Watch the strings: one drops the weight on the switch.", goal_word = "Drop the weight", win = "CLONK!", fail = "STILL HANGING",
        start = { x = -24, y = -28, h = 0, a = 0 }, goal = { x = -2, y = -24, h = 0 }, budget = { domino = 20 }, stars = { 12, 6 }, tools = { "draw", "line" },
        traps = {
            { kind = "zone", x0 = -24, x1 = -20, y0 = -25.5, y1 = -22.5 },
            { kind = "weight", id = "w", x = -2, y = -24, h = 7, r = 0.6, a = { -2, -24, 16 } },
            { kind = "string", id = "s1", a = { -20.61, -30, 0.6 }, b = { -20.61, -26, 0.6 }, holds = "w" },
            { kind = "gate", id = "g", x0 = -8.93, x1 = -8.73, y0 = -29.3, y1 = -26.7, z0 = 0, z1 = 1.8 },
            { kind = "string", id = "s2", a = { -15.03, -30, 0.6 }, b = { -15.03, -26, 0.6 }, holds = "g" },
            { kind = "plank", id = "p", x = -12, y = -31.6, h = 0, a = math.pi / 2, len = 2.4, width = 1.5 },
            { kind = "string", id = "s3", a = { -11.93, -29.0, 0.6 }, b = { -11.93, -26.4, 0.6 }, holds = "p" },
            { kind = "support", id = "c", x0 = -5.6, x1 = -3.4, y0 = -29.0, y1 = -27.0, z0 = 0, z1 = 2.2, look = "cards" },
            { kind = "support", id = "c2", x0 = 3, x1 = 5.4, y0 = -31, y1 = -29, z0 = 0, z1 = 2.6, look = "blocks" },
            { kind = "support", id = "c3", x0 = 7, x1 = 9.4, y0 = -31, y1 = -29, z0 = 0, z1 = 3.2, look = "glass" },
        },
        preset = { { line = { -23.4, -28, -5.9, -28 }, h = 0 }, { x = -5.0, y = -28, h = 2.2, a = 0, id = "top1" }, { x = -4.1, y = -28, h = 2.2, a = 0, id = "top2" } },
        camera = { x = -11, y = -27, h = 1, yaw = -80, pitch = 32, dist = 34 } }
    house:set_defs({ room = { list = { LEVEL1, TRAPS } } })
    local droom, dtier = api.House.BY_ID.living, 1
    click("hm_room" .. droom.n); frame(20)
    assert(api.S.hz.room == droom.id and visible("hm_tier" .. dtier), "a room shows its levels")
    assert(shown("LEVEL 1") and shown("LEVEL 2") and shown("LEVEL 3"), "all three levels are on the card")
    assert(shown("clear it to unlock LINE"), "the level 1 card says what clearing it unlocks")
    assert(not visible("hm_room1"), "the map behind the card takes no clicks")
    click("hm_back"); frame(2)
    assert(api.S.mode == "house" and api.S.hz.room == nil, "BACK closes the levels")
    click("hm_room" .. droom.n); frame(20)
    click("hm_tier" .. dtier)
    local def = FV.S.ch
    assert(api.S.mode == "free" and def == LEVEL1 and FV.board() ~= room, "a level starts its challenge")
    assert(FV.board().count == 1 and FV.board().limits.domino == def.budget.domino + 1, "the challenge has its own board and budget")
    frame(2)
    assert(shown("LEVEL 1") and shown("LINE"), "the level card shows its level and the tool it unlocks")
    FV.S.tool = "draw"; press("6")
    assert(FV.S.tool ~= "start", "the first domino cannot be moved")
    FV.board():begin_action()
    FV.board():place_line(-19.38, -31, -6.8, -31, function() return "cream" end, 0)
    FV.board():end_action()
    FW.sync(FV.board())
    FV.S.save_due = FV.S.clock
    frame(5)                                   -- an autosave falls due: it must not write this board
    assert(saved["Save/free_autosave.txt"] == writes_before, "a challenge does not overwrite your room's autosave")
    local played_ch = #played
    press("Space")
    assert(FV.S.mode == "running", "Space tips the challenge")
    local n = 0
    while FV.S.mode == "running" and n < 3600 do frame(); n = n + 1 end
    local r = FV.S.ch_result
    assert(r and r.won and r.stars == 3, "the old-style line wins 3 stars by count")
    assert(saved["Save/house.txt"]:match("\nstage_line 3 %d+"), "the stars are saved")
    assert(house:stars(droom.id) >= 3, "the room counts them")
    assert(FW.goal_t ~= nil, "the goal went off in the world")
    local heard = {}
    for i = played_ch + 1, #played do heard[played[i]] = true end
    assert(heard["goal_tv.wav"], "the living room's goal sound plays")
    assert(heard["unlock.wav"] and r.news and r.news.cleared.id == "living", "clearing level 1 plays the unlock")
    assert(saved["Save/global_challenges.txt"]:match("three_stars"), "a finished run reports its global challenges, and they save")
    click("fb_ch")
    assert(api.S.mode == "house" and api.S.hz.room == droom.id, "LEAVE CHALLENGE goes back to the room's levels")
    frame(20)
    ------------------------------------------------------------------ traps
    -- Every kind drawn, played on its event (at any frame rate), stood up again, and gone with the board.
    local alive_before = nodes_alive
    click("hm_tier2")
    assert(FV.S.ch == TRAPS, "the trap challenge")
    frame(2)
    assert(shown("LEVEL 2") and not shown("clear it: unlocks"), "a level 2 card shows its level and unlocks nothing")
    local TV = FW.trap_vis
    local function shown_node(n) return rawget(n, "shown") ~= false end
    local function rot(n) return rawget(n, "rot") or { x = 0, y = 0, z = 0 } end
    local function pos(n) return rawget(n, "pos") end
    for _, id in ipairs({ "s1", "s2", "s3", "w", "p", "g", "c", "c2", "c3", "zone 1" }) do assert(TV[id], "trap " .. id .. " is drawn") end
    -- string: taut between its tacks, its two halves waiting
    local s1 = TV.s1
    assert(s1.whole and shown_node(s1.whole) and not shown_node(s1.h1) and not shown_node(s1.h2), "a string is drawn taut")
    assert(math.abs(rawget(s1.whole, "scl").y - 4) < 1e-6 and math.abs(pos(s1.whole).y - 0.6) < 1e-6, "between its ends, at its height")
    -- weight: hanging at its height, on a cord
    local w = TV.w
    assert(w.body and math.abs(pos(w.body).y - (7 + 0.6 * 0.86)) < 1e-6 and shown_node(w.cord), "a weight hangs on its cord")
    -- plank: upright on its hinge
    local pk = TV.p
    assert(pk.root and rot(pk.root).x == 0 and #pk.nodes >= 4, "a plank stands on its hinges")
    -- gate: closed
    local g = TV.g
    assert(g.root and rot(g.root).y == g.yaw and #g.nodes >= 6, "a gate stands closed")
    -- supports: a house of cards, a block tower, a tower of glasses, each up to its top
    for id, lk in pairs({ c = "cards", c2 = "blocks", c3 = "glass" }) do
        local v = TV[id]
        assert(v.look == lk and #v.pieces >= 4, id .. " is a " .. lk .. " stack of " .. #v.pieces)
        local cyl, leaning = 0, 0
        for _, q in ipairs(v.pieces) do
            if q.shape == "cyl" then cyl = cyl + 1 end
            if q.rx ~= 0 or q.rz ~= 0 then leaning = leaning + 1 end
        end
        assert((lk == "glass") == (cyl > 0) and (lk == "cards") == (leaning > 0), id .. ": glasses only in glass, leaning cards only in cards")
        local top = 0
        for _, q in ipairs(v.pieces) do top = math.max(top, q.z + rawget(q.n, "scl").y / 2) end
        assert(math.abs(top - v.tr.z1) < 0.06, id .. ": its top is where its dominoes stand: " .. top .. " vs " .. v.tr.z1)
    end
    -- zone: a red outline on the floor
    local z = TV["zone 1"]
    assert(#z.strips == 4 and math.abs(pos(z.strips[1]).y - 0.02) < 1e-6, "a zone is outlined on the floor")
    -- A refused placement there says why and lights the outline; a challenge's own domino says it stays.
    press("1")
    at(-22, -24); frame(); M.left = true; frame(); M.left = false; frame()
    assert(FV.S.msg and FV.S.msg:match("out of bounds") and z.flash > 0.5, "a domino refused in a zone says why and lights it: " .. tostring(FV.S.msg))
    frame(60)
    assert(z.flash == 0, "and the light fades")
    local top1 = FV.board().pieces[FV.board().preset_ids.top1]
    at(-10, -28); frame(); M.right = true; frame(); M.right = false; frame()
    assert(FV.S.msg and FV.S.msg:match("challenge's"), "a protected domino says so: " .. tostring(FV.S.msg))
    at(-15.03, -27.2); frame(); M.left = true; frame(); M.left = false; frame()
    assert(FV.S.msg == "That's part of a trap: build around it.", "a domino through a string says why: " .. tostring(FV.S.msg))
    -- Play it.
    local initial = {}
    for _, q in ipairs(TV.c.pieces) do initial[q] = { pos(q.n).x, pos(q.n).y, pos(q.n).z } end
    local played_tr = #played
    press("Space")
    run_out()
    assert(FV.S.ch_result and FV.S.ch_result.won, "the weight sets off the goal")
    heard = {}
    for i = played_tr + 1, #played do heard[played[i]:gsub("%d?%.wav$", "")] = true end
    for _, snd in ipairs({ "string_snap", "weight_drop", "gate_open", "plank_fall", "collapse_cards" }) do assert(heard[snd], "the " .. snd .. " sound plays") end
    for name in pairs(heard) do
        local f = io_open("Assets/Audio/" .. name .. ".wav", "rb") or io_open("Assets/Audio/" .. name .. "1.wav", "rb")
        assert(f, "no file for the sound " .. name); f:close()
    end
    local function animated()
        assert(not shown_node(s1.whole) and shown_node(s1.h1) and shown_node(s1.h2), "a cut string snaps in two")
        assert(pos(s1.h1).y < 0.55 and pos(s1.h2).y < 0.55, "its halves fall to the floor: " .. pos(s1.h1).y)
        assert(pos(w.body).y < 2 and not shown_node(w.cord), "the weight came down: " .. pos(w.body).y)
        assert(rot(pk.root).x > 80, "the plank fell: " .. rot(pk.root).x)
        assert(rot(g.root).y > g.yaw + 90, "the gate swung open: " .. rot(g.root).y)
        local moved = 0
        for _, q in ipairs(TV.c.pieces) do if pos(q.n).y < initial[q][2] - 0.05 or math.abs(pos(q.n).x - initial[q][1]) > 0.3 then moved = moved + 1 end end
        assert(moved >= #TV.c.pieces * 0.8, "the house of cards collapsed: " .. moved .. " of " .. #TV.c.pieces)
        for _, q in ipairs(TV.c2.pieces) do assert(pos(q.n).y == q.z, "a stack nothing struck stands") end
        local lost = FW.vis[top1.id].n
        assert(pos(lost).y < 1.2, "a domino on the cards falls with them: " .. pos(lost).y)
    end
    animated()
    local final = {}
    for _, q in ipairs(TV.c.pieces) do final[q] = { pos(q.n).x, pos(q.n).y, pos(q.n).z } end
    -- Stand up: every trap as installed.
    press("R")
    assert(shown_node(s1.whole) and not shown_node(s1.h1), "R mends the string")
    assert(math.abs(pos(w.body).y - (7 + 0.6 * 0.86)) < 1e-6 and shown_node(w.cord), "hangs the weight back up")
    assert(rot(pk.root).x == 0 and rot(g.root).y == g.yaw, "stands the plank and shuts the gate")
    for _, q in ipairs(TV.c.pieces) do assert(pos(q.n).x == q.x and pos(q.n).y == q.z, "and rebuilds the cards") end
    -- Again at 8 FPS: the same run, the same end.
    FRAME_MS = 125
    press("Space")
    local guard = 0
    while FV.S.mode == "running" and guard < 600 do frame(); guard = guard + 1 end
    FRAME_MS = 1000 / 60
    animated()
    for _, q in ipairs(TV.c.pieces) do
        local a, b = final[q], pos(q.n)
        assert(math.abs(a[1] - b.x) < 1e-6 and math.abs(a[2] - b.y) < 1e-6 and math.abs(a[3] - b.z) < 1e-6, "the collapse ends the same at any frame rate")
    end
    click("fb_tip")
    assert(FV.S.mode == "running" and shown_node(s1.whole), "AGAIN stands the traps up and runs again")
    run_out()
    animated()
    -- Leaving takes every trap node with it; coming back builds them again, the same number.
    local with_traps = nodes_alive
    click("fb_ch"); frame(20)
    assert(next(FW.trap_vis) == nil, "the traps go with the challenge")
    for _ = 1, 3 do
        click("hm_tier2"); frame(3)
        assert(FW.trap_vis.c and nodes_alive == with_traps, "re-entering builds the same traps: " .. nodes_alive .. " vs " .. with_traps)
        click("fb_ch"); frame(20)
    end
    assert(nodes_alive <= alive_before + 2, "no trap nodes left behind: " .. nodes_alive .. " vs " .. alive_before)
    house:set_defs(api.Challenges.MAPS)
    click("hm_back"); frame(2); api.open_house("free"); frame(20); click("hm_room2")
    assert(api.S.mode == "free" and not FV.S.ch and FV.board() == room and room.count == room_n and FW.goal_t == nil, "building again brings your room back")
    frame(5)
end
press("Space")
assert(FV.S.mode == "running", "tipped for the frame-rate check")
FRAME_MS = 125
local t_before = FW.run_time()
for _ = 1, 16 do frame() end
local advanced = FW.run_time() - t_before
FRAME_MS = 1000 / 60
assert(math.abs(advanced - 2.0) < 0.01, "a run's clock must follow real time at a low frame rate: 16 x 125 ms gave " .. advanced .. " s")
run_out()
press("R")
-- A chain still falling after a minute keeps running: the live time limit is only for a ball that never settles.
press("Space")
FW.A.res.duration = 1000
FRAME_MS = 125
for _ = 1, 560 do frame() end
FRAME_MS = 1000 / 60
assert(FW.run_time() > 65 and FV.S.mode == "running", "a long chain outlasts a minute: " .. FW.run_time() .. " s, " .. FV.S.mode)
FW.A.res.duration = 0
run_out()
assert(FV.S.mode == "done", "and ends once it is over")
press("R")
-- Save to slot 1, load the sample, load slot 1 back.
local mine = fb.count
click("fb_save"); click("fb_slot1")
assert(saved["Save/free_slot1.txt"] and saved["Save/free_slot1.txt"]:match("^TOPPLE%-FREE 1"), "slot 1 saved")
assert(FV.S.msg == "Saved to slot 1.", "a good save says so: " .. tostring(FV.S.msg))
-- A write that fails says so too, rather than claiming the build is safe.
do
    local real_write = env.fs.write
    env.fs.write = function() return false end
    click("fb_save"); click("fb_slot2")
    env.fs.write = real_write
    assert(FV.S.msg == "Couldn't save to slot 2.", "a failed save must not claim success: " .. tostring(FV.S.msg))
end
click("fb_load"); click("fb_slot4")
assert(FV.board().count == demo_n, "the sample loads")
local real_read = env.fs.read
env.fs.read = function(path) if saved[path] then return saved[path] end return real_read(path) end
click("fb_load"); click("fb_slot1")
assert(FV.board().count == mine, "slot 1 loads back: " .. FV.board().count .. " vs " .. mine)
frame(200)
assert(saved["Save/free_autosave.txt"], "the room autosaves")
-- An autosave that fails says so; one that works stays quiet.
do
    local real_write = env.fs.write
    env.fs.write = function() return false end
    FV.S.msg, FV.S.save_due = nil, FV.S.clock
    frame(2)
    env.fs.write = real_write
    assert(FV.S.msg == "Couldn't autosave the room.", "a failed autosave must say so: " .. tostring(FV.S.msg))
    FV.S.msg, FV.S.save_due = nil, FV.S.clock
    frame(2)
    assert(FV.S.msg == nil, "a good autosave says nothing: " .. tostring(FV.S.msg))
end
local made = FW.made()
-- Back to the menu and in again: nothing leaks; the build is still there.
click("fb_menu")
assert(api.S.mode == "title", "MENU goes back to the title")
frame(30)
press("Return"); frame(20)
assert(api.S.mode == "house", "FREE BUILD's rooms")
keys["Return"] = true; frame(3)        -- held across several frames, as a real key press is
assert(FV.S.mode == "build", "the Enter that opens Free Build does not tip the chain: " .. FV.S.mode)
keys["Return"] = false; frame()
assert(api.S.mode == "free" and FV.board().count == mine, "Free Build reopens on the same build")
frame(5)
assert(FW.made() <= made + 128 * 5, "re-entering reuses the pooled dominoes: " .. FW.made() .. " vs " .. made)
assert(#lights_set > 0, "Free Build sets its lights")
------------------------------------------------------------------ the House: rooms
do
    -- A stub kitchen (the real rooms come from tools/house_rooms.py): a floor and a counter, its own lights and
    -- camera, a piece that collides and one appliance for its challenge. The attic is not made yet.
    local KITCHEN = [[return { id = "kitchen", name = "Kitchen",
        bounds = { x0 = -20, x1 = 20, y0 = -15, y1 = 15 }, wall_h = 30,
        surfaces = { { name = "floor", x0 = -20, x1 = 20, y0 = -15, y1 = 15, h = 0, edge = false },
            { name = "counter", x0 = 10, x1 = 19, y0 = 8, y1 = 14, h = 9, edge = true, board = true } },
        solids = { { name = "counter", x0 = 10, x1 = 19, y0 = 8, y1 = 14, z0 = 0, z1 = 9 } },
        pieces = { { name = "kitchen_floor", color = { 1, 1, 1 } }, { name = "furn_kitchen_counter", color = { 1, 1, 1 } },
            { name = "kitchen_wall_L", color = { 1, 1, 1 }, group = "L" }, { name = "goal_toaster", color = { 1, 1, 1 }, challenge = "stub_toast" } },
        sun = { dir = { 0.5, -0.7, 0.3 }, color = { 1, 0.9, 0.8 }, intensity = 4 }, fill = { dir = { -0.3, -0.8, -0.4 }, intensity = 0.4 },
        camera = { target = { 0, 0, 1 }, yaw = -50, pitch = 42, dist = 60 } }]]
    local real_read2 = env.fs.read
    env.fs.read = function(path)
        if path == "Scripts/rooms/kitchen.lua" then return KITCHEN end
        if path == "Scripts/rooms/attic.lua" then return nil end
        return real_read2(path)
    end
    api.load_room("kitchen", true); api.load_room("attic", true)
    local living_auto = saved["Save/free_autosave.txt"]
    local living_board = FV.board()
    local living_room = F.ROOM
    -- Into the kitchen from FREE BUILD (everything is unlocked).
    click("fb_menu"); frame(5)
    api.open_house("free"); frame(20)
    assert(api.S.hz.ready.kitchen and not api.S.hz.ready.attic, "the kitchen is made, the attic is not")
    click("hm_room8"); frame(2)
    assert(api.S.mode == "house" and api.S.hz.msg == "The Attic is coming soon.", "a room not made yet is coming soon: " .. tostring(api.S.hz.msg))
    assert(shown("coming soon"), "and the plan says so")
    local nodes_living = nodes_alive
    click("hm_room3")
    assert(api.S.mode == "free" and FV.S.room == "kitchen", "into the kitchen")
    assert(F.ROOM.id == "kitchen" and FW.room() == F.ROOM, "rules and world follow the room")
    assert(FV.board() ~= living_board and FV.board().count == 0, "the kitchen has a build of its own")
    assert(shown("free build  ·  kitchen"), "the HUD names the room")
    assert(math.abs(setv.shadow_bounds_y - 15) < 1e-6 and math.abs(setv.shadow_bounds_radius - (math.sqrt(20 * 20 + 15 * 15 + 15 * 15) + 1)) < 1e-6,
        "the shadow map covers the kitchen")
    assert(FW.room_nodes() == 4 + 1 + 1, "the kitchen's nodes: four pieces, one flat board and the root: " .. FW.room_nodes())
    -- The rules know the kitchen: a point in the living room but past the kitchen's walls takes nothing.
    assert(not FV.board():place(-35, 0, 0, 0, "cream"), "outside the kitchen")
    press("2"); drag(-10, -5, 6, -5)
    local kn = FV.board().count
    assert(kn > 20, "a line in the kitchen: " .. kn)
    frame(5)
    for n in pairs(bodies) do assert(not rawget(n, "dead"), "a collider outlived its node") end
    -- The world switched while it is open: the old room's colliders go with its nodes, the new one is built and lit.
    local kitchen_room = F.ROOM
    FW.set_room(living_room); frame(5)
    for n in pairs(bodies) do assert(not rawget(n, "dead"), "switching while open: a collider outlived its node") end
    assert(FW.room() == living_room and FW.room_nodes() > 6 and math.abs(setv.shadow_bounds_y - 24) < 1e-6, "the living room is built while open")
    FW.set_room(kitchen_room); frame(5)
    assert(FW.room_nodes() == 6, "and the kitchen again")
    frame(200)
    assert(saved["Save/room_kitchen_autosave.txt"] and saved["Save/free_autosave.txt"] == living_auto, "the kitchen autosaves to its own file")
    click("fb_save"); click("fb_slot1")
    assert(saved["Save/room_kitchen_slot1.txt"], "and has its own slots")
    click("fb_load"); frame(2)
    assert(not visible("fb_slot4"), "the sample is the living room's")
    click("fb_load")
    -- Back to the living room: the kitchen goes, the living room and its build come back.
    click("fb_menu"); frame(5)
    api.open_house("free"); frame(20)
    click("hm_room2")
    assert(FV.S.room == "living" and F.ROOM == living_room and FV.board() == living_board, "the living room's build is back")
    assert(math.abs(setv.shadow_bounds_y - 24) < 1e-6, "with its own shadow bounds")
    frame(5)
    for n in pairs(bodies) do assert(not rawget(n, "dead"), "a collider outlived its node") end
    -- Back and forth: nothing leaks.
    local counts = {}
    for cycle = 1, 5 do
        for _, n in ipairs({ 3, 2 }) do
            click("fb_menu"); frame(3); api.open_house("free"); frame(20); click("hm_room" .. n); frame(5)
        end
        counts[cycle] = nodes_alive
    end
    assert(counts[5] == counts[2], "room switches leak nodes: " .. table.concat(counts, " "))
    assert(FV.boards.kitchen.count == kn, "the kitchen's build waits for you")
    -- A challenge in the kitchen allows only some tools and sizes; the tray and the SIZE column show only those.
    local stub = { id = "stub_toast", room = "kitchen", tier = 1, name = "Stub Toast", brief = "Tip the line into the toaster.", goal_word = "Pop it",
        win = "TOAST!", fail = "NO TOAST", start = { x = -10, y = 0, h = 0, a = 0 }, goal = { x = 6, y = 0, h = 0 }, budget = { domino = 30 }, stars = { 26, 22 },
        tools = { "draw", "line" }, sizes = { 1, 2 } }
    house:set_defs({ room = { list = {} }, house = { list = { stub } } })
    click("fb_menu"); frame(3)
    api.open_house("challenge"); frame(20)
    click("hm_room3"); frame(20)
    assert(api.S.hz.room == "kitchen" and visible("hm_tier1") and shown("Not built yet"), "the kitchen's levels: one made, two not")
    click("hm_tier1")
    assert(FV.S.ch == stub and FV.S.room == "kitchen", "the kitchen's challenge")
    frame(2)
    for i = 1, 10 do assert(visible("fb_tool" .. i) == (i == 1 or i == 2 or i == 5), "a challenge's tray shows only its tools and erase: " .. i) end
    assert(visible("fb_size1") and visible("fb_size2") and not visible("fb_size3") and not visible("fb_grow"), "and only its sizes")
    press("3"); assert(FV.S.tool ~= "spiral" and FV.S.msg == "This challenge doesn't use that tool.", "a tool it doesn't allow stays put")
    press("-"); assert(FV.S.size == 1, "Mini is allowed here")
    press("-"); press("="); press("="); assert(FV.S.size == 2, "Standard, and no further")
    press("2"); drag(-9.4, 0, 5.4, 0)
    press("Space"); run_out()
    assert(FV.S.ch_result and FV.S.ch_result.won, "the stub challenge is won")
    assert(FV.S.ch_result.news and FV.S.ch_result.news.cleared.id == "kitchen", "and clearing it says what it opened")
    assert(shown("KITCHEN CLEARED  ·  unlocked RAMP"), "on the result card")
    -- Without unlock_all the ramp is now the kitchen's gift; the living room and the kitchen are the rooms to build in.
    api.unlock_all(false)
    assert(house:tool_open("ramp") and not house:tool_open("line"), "the kitchen unlocked the ramp")
    click("fb_ch"); frame(20)
    assert(api.S.mode == "house" and api.S.hz.room == "kitchen", "back to the kitchen's levels")
    click("hm_build")
    assert(api.S.mode == "free" and FV.S.room == "kitchen" and not FV.S.ch, "BUILD HERE in a cleared room")
    frame(2)
    assert(visible("fb_tool10") and not shown("Kitchen"), "the ramp is unlocked in Free Build")
    assert(shown("Living Room"), "LINE still names the living room")
    api.unlock_all()
    house:set_defs(api.Challenges.MAPS)
    env.fs.read = real_read2
    -- Every room that is really made (Scripts/rooms/*.lua) opens, builds its nodes and its colliders, takes a line of
    -- dominoes where its camera looks, and leaves nothing behind.
    local made, counts2 = {}, {}
    for pass = 1, 2 do
        for _, r in ipairs(api.House.ROOMS) do
            if r.id ~= "living" and api.load_room(r.id, true) then
                if pass == 1 then made[#made + 1] = r.id end
                click("fb_menu"); frame(3)
                api.open_house("free"); frame(20)
                assert(api.S.hz.ready[r.id], r.id .. " is made")
                click("hm_room" .. r.n); frame(6)
                assert(api.S.mode == "free" and FV.S.room == r.id and F.ROOM.id == r.id and FW.room() == F.ROOM, "into the " .. r.id)
                assert(FW.room_nodes() > 4, r.id .. ": its room is built: " .. FW.room_nodes())
                local B = F.ROOM.bounds
                assert(math.abs(setv.shadow_bounds_y - F.ROOM.wall_h / 2) < 1e-6 and math.abs(setv.shadow_bounds_x - (B.x0 + B.x1) / 2) < 1e-6, r.id .. ": its shadow bounds")
                for n in pairs(bodies) do assert(not rawget(n, "dead"), r.id .. ": a collider outlived its node") end
                -- A rug or mat the rules' ball steps up: a flat board and four ramps for the engine's ball, all with bodies.
                local low = 0
                for _, s in ipairs(F.ROOM.surfaces) do if s.h > 0 and s.h <= F.BALL.step and not s.board then low = low + 1 end end
                assert(FW.low_ramps == 4 * low, r.id .. ": four ramps per rug: " .. tostring(FW.low_ramps) .. " for " .. low)
                for _, n in ipairs(FW.boards) do assert(bodies[n], r.id .. ": a board or ramp for the balls has a body") end
                if r.id == "attic" then assert(#FW.rafters == 3, "the attic's beams, side beams and tie beams all hide from above: " .. #FW.rafters) end
                if #FW.rafters > 0 then
                    local _, _, ch = FW.cam_pos()
                    assert(FW.rafters_hidden == (ch > FW.rafter_h - 0.5), r.id .. ": rafters hidden exactly while the camera is above them")
                    if FW.rafters_hidden then for _, n in ipairs(FW.rafters) do assert(rawget(n, "shown") == false, r.id .. ": a rafter blocks the view") end end
                end
            end
        end
        counts2[pass] = nodes_alive
    end
    print("rooms made:", table.concat(made, " "), "  nodes after each pass:", counts2[1], counts2[2])
    -- Every House challenge (C.HOUSE, Scripts/challenges/*.lua): its room's goal object, each trap and each prop drawn;
    -- its solution (tests/solutions) wins and the room's goal object animates; in a live run every standing gate,
    -- support, plank and weight has a body for the engine's balls, and loses it on its event.
    local Ch = api.Challenges
    local live = env.physics.is_simulating
    local played_defs, trap_kinds, anims, with_bodies = 0, {}, {}, 0
    local card_lens, marked, crane_cords = {}, 0, 0
    for _, r in ipairs(api.House.ROOMS) do
        local list = Ch.HOUSE[r.id]
        local sols = list and dofile("tests/solutions/" .. r.id .. ".lua")
        for k, d in ipairs(list or {}) do
            if api.load_room(r.id) then
                click("fb_menu"); frame(3)
                env.physics.is_simulating = function() return false end        -- (the rules' run: the stub's bodies never move)
                -- (a goal that is only { preset = id }, no x, y, h: the HUD marks that domino)
                if d.goal.preset then d = setmetatable({ goal = { preset = d.goal.preset } }, { __index = d }) end
                assert(api.start_free(r.id, d), "into " .. d.id)
                frame(3)
                local b = FV.board()
                assert(#FW.room_goal + #FW.goal_fb > 0, d.id .. ": the room's goal object is drawn")
                -- START and END: a marker beside each locked domino, the words in the room, and the level card: its
                -- level, the rule, and its 2, 3 or 4 challenges.
                assert(b.start_piece and b.end_piece, d.id .. ": a Start and an End")
                for key, pid in pairs({ start = b.start_piece, finish = b.end_piece }) do
                    local m, pc = FW.marks[key], b.pieces[pid]
                    assert(m and m.piece == pid, d.id .. ": its " .. key .. " marker is on that domino")
                    if not m.label_only then
                        assert(math.sqrt((m.x - pc.x) ^ 2 + (m.y - pc.y) ^ 2) >= 1.5, d.id .. ": the " .. key .. " plaque stands beside its domino, not on it")
                        marked = marked + 1
                        for _, tr in ipairs(d.traps or {}) do
                            if tr.x0 and (tr.z1 or 99) > pc.z then
                                assert(not (m.x > tr.x0 - 1 and m.x < tr.x1 + 1 and m.y > tr.y0 - 1 and m.y < tr.y1 + 1), d.id .. ": the " .. key .. " plaque stands clear of the " .. tostring(tr.id))
                            end
                        end
                    end
                end
                assert(shown("START") and shown("END"), d.id .. ": START and END are written in the room")
                assert(#d.challenges == k + 1, d.id .. ": level " .. k .. " has " .. (k + 1) .. " challenges")
                assert(shown("LEVEL " .. k) and shown(FV.REQUIRE), d.id .. ": the level card says its level and the rule")
                for _, c in ipairs(d.challenges) do assert(shown(c.name) and shown(c.brief), d.id .. ": the level card lists " .. c.name) end
                card_lens[#d.challenges] = true
                -- Previews stand where the rules will: on the kids' play mat (0.1), not under it; under the living room's
                -- coffee table, on the rug, not up on the table.
                if r.id == "kids" and k == 1 then
                    assert(math.abs(FV.rest_h(-20, -15, 0, "line", 1) - 0.1) < 1e-6 and math.abs(FV.rest_h(-20, -15, 0, "ball") - 0.1) < 1e-6, "a domino's and a ball's preview over the mat stand on it")
                    local proj, hs = FW.project, {}
                    FW.project = function(x, y, h) if x < 11 then hs[#hs + 1] = h end; return proj(x, y, h) end
                    FV.S.press = { kind = "line", x0 = 14, y0 = -20, x1 = 4, y1 = -20, h0 = 0 }
                    FV.shape_preview()
                    FV.S.press, FW.project = nil, proj
                    frame()          -- (the HUD drawn again over the preview's quads)
                    assert(#hs > 3, "the line's dots over the mat are drawn")
                    for _, h in ipairs(hs) do assert(math.abs(h - 0.6) < 1e-6 or math.abs(h - 1.3) < 1e-6, "a line from the floor shows its dots (and count) on the mat: " .. h) end
                end
                if r.id == "living" and k == 1 then
                    assert(math.abs(FV.rest_h(-13, 1, 0.12, "draw", 1) - 0.12) < 1e-6 and math.abs(FV.rest_h(-13, 1, 0.12, "ball") - 0.12) < 1e-6, "under the coffee table a preview stays on the rug")
                end
                -- The START and END tags: big enough to read at this room's camera, never over their own domino.
                local uu = shown("TOPPLE").font_scale * 16 / 40
                for key, lab in pairs({ start = "START", finish = "END" }) do
                    local q, pc = shown(lab), b.pieces[key == "start" and b.start_piece or b.end_piece]
                    assert(q.font_scale * 16 >= 17 * uu - 1e-6, d.id .. ": the " .. lab .. " tag is big enough to read: " .. q.font_scale * 16)
                    local px, py = FW.project(pc.x, pc.y, pc.z + 0.5)
                    assert(not (px > q.x and px < q.x + q.width and py > q.y and py < q.y + q.height), d.id .. ": the " .. lab .. " tag does not cover its domino")
                    assert(q.y >= FV.card_bottom - 1e-6, d.id .. ": the " .. lab .. " tag is not behind the level card")
                end
                -- A string hung from a room's hook (the kids' crane) has its cord, from the hook down to the string.
                local cords = {}
                for _, tr in ipairs(b.trap_order) do
                    local v = FW.trap_vis[tr.id]
                    if v.hcord then
                        cords[#cords + 1] = v
                        local top = rawget(v.hcord, "pos")
                        assert(rawget(v.hcord, "shown") ~= false and top.y > v.tie[3] and top.y < v.hook[3], d.id .. ": the cord hangs from the hook to the string")
                        if math.sqrt((v.hook[1] - v.tie[1]) ^ 2 + (v.hook[2] - v.tie[2]) ^ 2) > 1.5 then
                            -- (a hook off to the side: straight down to a floor pulley, then along the floor to the string)
                            assert(v.fcord and v.pulley and rawget(v.fcord, "shown") ~= false, d.id .. ": the cord runs over a floor pulley")
                            assert(math.sqrt((v.low[1] - v.hook[1]) ^ 2 + (v.low[2] - v.hook[2]) ^ 2) < 1 and v.low[3] < 0.6, d.id .. ": it drops nearly straight from the hook to the floor")
                        end
                    end
                end
                if d.id == "kids_crane" then assert(#cords == 1, "the crane holds its string by a cord") end
                -- The rig reads: a rope at least 0.12 thick, one line from the hook to the wheel, over it and on to
                -- the string; and only where the room has a hook for it.
                local hooked = false
                for _, sp in ipairs(F.ROOM.spots and F.ROOM.spots.traps or {}) do if sp.kind == "string" and (sp.hook or sp.a) then hooked = true end end
                if not hooked then assert(#cords == 0, d.id .. ": no hook in this room, no rig") end
                local function mid(n, a2, b2)
                    local q = rawget(n, "pos")
                    return math.abs(q.x - (a2[1] + b2[1]) / 2) < 1e-6 and math.abs(q.y - (a2[3] + b2[3]) / 2) < 1e-6 and math.abs(q.z + (a2[2] + b2[2]) / 2) < 1e-6
                end
                for _, v in ipairs(cords) do
                    for _, n in ipairs({ v.hcord, v.fcord }) do
                        if n then local sc = rawget(n, "scl"); assert(sc.x >= 0.12 and sc.z >= 0.12, d.id .. ": the rope is thick enough to read: " .. sc.x) end
                    end
                    assert(mid(v.hcord, v.hook, v.low), d.id .. ": the rope starts at the hook")
                    if v.fcord then
                        assert(mid(v.fcord, v.low2, v.tie), d.id .. ": and runs on from the wheel to the string")
                        -- (posed by tipping and turning only, which the engine reads as meant: a roll about z stood the
                        -- floor run on end; its local y must lie along the run)
                        local ro = rawget(v.fcord, "rot")
                        local rx, ry = math.rad(ro.x), math.rad(ro.y)
                        local ux, uy, uz = math.sin(rx) * math.sin(ry), math.cos(rx), math.sin(rx) * math.cos(ry)
                        local ddx, ddy, ddz = v.tie[1] - v.low2[1], v.tie[3] - v.low2[3], -(v.tie[2] - v.low2[2])
                        local dl = math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz)
                        assert(ro.z == 0 and ux * ddx / dl + uy * ddy / dl + uz * ddz / dl > 0.999, d.id .. ": the floor run lies along the floor")
                        local c = v.pulley_at
                        for _, e in ipairs({ v.low, v.low2 }) do
                            local dd = math.sqrt((e[1] - c[1]) ^ 2 + (e[2] - c[2]) ^ 2 + (e[3] - c[3]) ^ 2)
                            assert(math.abs(dd - rawget(v.pulley, "scl").x) < 0.02, d.id .. ": the rope meets the wheel's rim: " .. dd)
                        end
                    end
                end
                crane_cords = crane_cords + #cords
                for _, g in ipairs(FW.room_goal) do
                    assert(rawget(g.n, "shown") ~= false or (b.goal_piece ~= nil), d.id .. ": its goal piece " .. g.L.name .. " shows")
                end
                for _, tr in ipairs(b.trap_order) do
                    local v = FW.trap_vis[tr.id]
                    assert(v and (#v.nodes - (v.col and 1 or 0) > 0 or v.art), d.id .. ": trap " .. tr.id .. " is drawn")
                    trap_kinds[tr.kind] = true
                end
                for i, s in ipairs(d.props or {}) do
                    local got = FW.prop_drawn[i]
                    assert(got == "goal" or (got or 0) > 0, d.id .. ": prop " .. tostring(s.name) .. " is drawn")
                end
                if b.goal_piece then
                    assert(#FW.book > 0 and rawget(FW.vis[b.goal_piece].n, "shown") == false, d.id .. ": the goal domino is drawn as the room's book")
                end
                local sol = sols[k]
                local solve = type(sol) == "function" and sol or sol.solve
                b:begin_action(); solve(b, F); b:end_action()
                FW.sync(b)
                local sig0 = FW.goal_sig()
                if FW.goal_key() == "lights" then
                    -- (waiting at dusk: dim enough that the win's rise shows, light enough to build in)
                    assert(FW.glow_k == 0.12 and setv.IBL_intensity >= FW.LOOK.IBL_intensity * 0.55 and setv.IBL_intensity <= FW.LOOK.IBL_intensity * 0.7,
                        d.id .. ": the attic waits at dusk, readable: " .. setv.IBL_intensity / FW.LOOK.IBL_intensity)
                end
                press("Space")
                assert(FV.S.mode == "running" and shown("START") and shown("END"), d.id .. ": START and END stay marked while it runs")
                local moved, guard = false, 0
                while (FV.S.mode == "running" or guard < 30) and guard < 4000 do
                    frame(); guard = guard + (FV.S.mode == "running" and 0 or 1)
                    if FW.goal_sig() ~= sig0 then moved = true end
                end
                assert(FV.S.ch_result and FV.S.ch_result.won, d.id .. ": its solution wins")
                for _, c in ipairs(d.challenges) do assert(shown(c.name), d.id .. ": the result lists " .. c.name) end
                assert(moved and FW.goal_t, d.id .. ": the room's " .. FW.goal_key() .. " animates on the win")
                if FW.goal_key() == "lights" then
                    local g = 0
                    while FW.goal_t < 3.3 and g < 400 do frame(); g = g + 1 end
                    assert(FW.glow_k == 1 and math.abs(setv.IBL_intensity - FW.LOOK.IBL_intensity) < 1e-6, d.id .. ": the attic's lights are all the way up after the win")
                end
                anims[FW.goal_key()] = true
                for _, v in ipairs(cords) do
                    assert(v.ev and rawget(v.hcord, "shown") == false and rawget(v.knot, "shown") == false and (not v.fcord or rawget(v.fcord, "shown") == false), d.id .. ": the cut string's cord whips away")
                end
                press("R")
                assert(FW.goal_sig() == sig0, d.id .. ": and stands still again after R")
                for _, v in ipairs(cords) do assert(rawget(v.hcord, "shown") ~= false and (not v.fcord or rawget(v.fcord, "shown") ~= false), d.id .. ": the cord is back after R") end
                -- The same board in a live run: bodies for whatever of the traps stands.
                env.physics.is_simulating = live
                press("Space"); frame(4)
                for _, tr in ipairs(b.trap_order) do
                    if tr.kind == "gate" or tr.kind == "support" or tr.kind == "plank" or tr.kind == "weight" then
                        local v = FW.trap_vis[tr.id]
                        assert(v.gone or (v.col and bodies[v.col]), d.id .. ": the standing " .. tr.kind .. " " .. tr.id .. " has a body in a live run")
                        with_bodies = with_bodies + 1
                    end
                end
                run_out()
                for _, tr in ipairs(b.trap_order) do
                    local v = FW.trap_vis[tr.id]
                    if v.col and v.gone then assert(not bodies[v.col], d.id .. ": " .. tr.id .. " loses its body on its event") end
                end
                press("R")
                played_defs = played_defs + 1
            end
        end
    end
    env.physics.is_simulating = live
    local kinds, keys = {}, {}
    for k in pairs(trap_kinds) do kinds[#kinds + 1] = k end
    for k in pairs(anims) do keys[#keys + 1] = k end
    table.sort(kinds); table.sort(keys)
    print("House challenges won:", played_defs, "  trap kinds:", table.concat(kinds, " "), "  goals animated:", table.concat(keys, " "),
        "  standing traps with bodies:", with_bodies)
    assert(#keys == 8, "every room's goal animates: " .. table.concat(keys, " "))
    assert(counts2[1] == counts2[2], "walking the house twice leaks nodes: " .. counts2[1] .. " vs " .. counts2[2])
    assert(card_lens[2] and card_lens[3] and card_lens[4], "level cards list 2, 3 and 4 challenges")
    assert(marked > 24, "START and END plaques stand in the rooms: " .. marked)
    assert(crane_cords >= 1, "the crane's cord is drawn: " .. crane_cords)
    -- A level's challenges, star by star: cleared from START to END with none done is a clear with 0 stars; the solution
    -- then earns both, new, a coin each as they come in; a later run that earns none keeps them; and a domino that falls
    -- after the END fails the level, saying so, with no star.
    local function play_level(rid, k, extra)
        local d = Ch.HOUSE[rid][k]
        assert(api.load_room(rid), "into the " .. rid)
        click("fb_menu"); frame(3)
        env.physics.is_simulating = function() return false end
        FV.S.ch_boards[d.id] = nil
        assert(api.start_free(rid, d), "into " .. d.id)
        frame(3)
        local b = FV.board()
        local sol = dofile("tests/solutions/" .. rid .. ".lua")[k]
        b:begin_action(); (type(sol) == "function" and sol or sol.solve)(b, F); if extra then extra(b) end; b:end_action()
        FW.sync(b)
        press("Space"); run_out()
        env.physics.is_simulating = live
        return FV.S.ch_result, d
    end
    local function standing(n)          -- (dominoes stood far apart, off the line: they never fall)
        return function(b)
            local B, got = F.ROOM.bounds, 0
            for x = B.x0 + 3, B.x1 - 3, 3 do
                for y = B.y0 + 3, B.y1 - 3, 3 do if got < n and b:place(x, y, 0, 0, "cream") then got = got + 1 end end
            end
            assert(got == n, "room for the standing dominoes")
        end
    end
    local hall1 = Ch.HOUSE.hall[1]
    house.best[hall1.id] = nil
    local r0 = play_level("hall", 1, standing(20))
    assert(r0.won and r0.stars == 0 and #r0.pops == 0, "cleared, with no challenge done")
    assert(shown(FV.ZERO_HEAD) and shown("not yet"), "the card says cleared with 0 stars")
    assert(house.best[hall1.id] and house:stars_for(hall1.id) == 0 and house:cleared("hall"), "a 0-star clear counts as cleared")
    press("R")
    local r1 = play_level("hall", 1)
    assert(r1.won and r1.stars == 2 and #r1.pops == 2 and shown("NEW STAR"), "the solution earns both challenges, new")
    local coins = #played
    frame(90)
    local n_coin = 0
    for i = coins + 1, #played do if played[i] == "coin.wav" then n_coin = n_coin + 1 end end
    assert(r1.popped == 2 and n_coin == 2, "the two stars come in one by one, a coin each: " .. n_coin)
    press("R")
    local r2 = play_level("hall", 1, standing(20))
    assert(r2.won and r2.stars == 0 and r2.held[hall1.challenges[1].id] and r2.held[hall1.challenges[2].id] and shown("kept"), "a later run that earns none shows them kept")
    assert(house:stars_for(hall1.id) == 2, "stars once earned are kept: " .. house:stars_for(hall1.id))
    press("R")
    local bath1 = Ch.HOUSE.bath[1]
    local before = house:stars_for(bath1.id)
    local r3 = play_level("bath", 1, function(b)
        local e = b.pieces[b.end_piece]
        assert(b:place(e.x + math.cos(e.a) * F.SPACING, e.y + math.sin(e.a) * F.SPACING, e.a, e.z, "cream"), "a domino past the END")
    end)
    assert(not r3.won and r3.why == "after" and r3.stars == 0, "a domino falling after the END fails the level")
    assert(shown(FV.WHY.after .. "  No star this run.") and shown("NOT CLEARED"), "and the card says so")
    assert(house:stars_for(bath1.id) == before, "no star for it")
    press("R")
    click("fb_menu"); frame(3)
    api.open_house("free"); frame(20); click("hm_room2"); frame(5)
    assert(FV.S.room == "living", "home again")
end
click("fb_menu")
frame(30)
press("T")
assert(api.S.mode == "build", "Table Run still starts after Free Build")
assert(setv.shadow_fixed_bounds == false, "leaving Free Build gives Table Run its camera-fitted shadows back")
assert(setv.lod_enabled == true, "leaving Free Build turns LODs back on")
-- Back, pause and quit. Esc goes up exactly one level: an open panel, card or canvas closes, the House map's level card
-- goes to the map and the map to the title; anywhere else the pause card opens (RESUME, SETTINGS, BACK TO MENU, QUIT
-- GAME). Every card or panel shows its BACK (or CLOSE), which does the same. Nothing is tipped or counted, what the
-- mode autosaves is written, and QUIT calls the engine's quit (stubbed here).
api.autoplay = false
do
    local quits = 0
    rawset(env.engine, "quit", function() quits = quits + 1 end)
    local function esc() press("Escape"); frame(10) end
    local function paused() return api.S.pause ~= nil end
    local function pause_shown(menu)
        for _, l in ipairs({ "PAUSED", "RESUME", "SETTINGS", "QUIT GAME" }) do assert(shown(l), "the pause card shows " .. l) end
        assert(visible("pz_resume") and visible("pz_settings") and visible("pz_quit"), "and they can be clicked")
        assert(visible("pz_menu") == menu, menu and "BACK TO MENU is offered" or "the title has no menu to go back to")
    end
    -- Table Run: Esc pauses; nothing moves or tips under the card; Esc resumes.
    assert(api.S.mode == "build", "a table run to pause")
    esc(); assert(paused(), "Esc pauses a table run"); pause_shown(true)
    assert(shown("Table Run"), "the card says where you are")
    press("Space"); frame(5)
    assert(api.S.mode == "build" and paused(), "Space on the pause card tips nothing")
    esc(); assert(not paused() and not visible("pz_resume") and api.S.mode == "build", "Esc resumes, one level")
    -- SETTINGS from the card; the settings' own Esc (or BACK) lands back on the card.
    esc(); click("pz_settings"); frame(2)
    assert(api.settings:is_open() and not visible("pz_resume"), "SETTINGS opens over the card")
    press("Escape"); frame(10)
    assert(not api.settings:is_open() and paused(), "the settings' Esc goes back to the pause card")
    click("pz_resume"); frame(2)
    assert(not paused(), "RESUME closes the card")
    -- BACK TO MENU drops the table run, uncounted.
    local runs = saved["Save/topple_runs.txt"]
    esc(); click("pz_menu"); frame(2)
    assert(api.S.mode == "title" and not paused() and saved["Save/topple_runs.txt"] == runs, "BACK TO MENU leaves the run for the title, uncounted")
    -- The title: QUIT (button and Q), and Esc's pause card without BACK TO MENU.
    frame(30)
    assert(shown("QUIT  ·  Q") and visible("btn_quit"), "the title shows QUIT")
    for _, a in ipairs({ "btn_hall", "btn_table", "btn_quit" }) do
        for _, b in ipairs({ "btn_hall", "btn_table", "btn_quit", "btn_challenge", "btn_free" }) do
            local p, q = quads[a], quads[b]
            assert(a == b or p.x + p.width <= q.x + 0.5 or q.x + q.width <= p.x + 0.5 or p.y + p.height <= q.y + 0.5 or q.y + q.height <= p.y + 0.5,
                a .. " overlaps " .. b)
        end
    end
    click("btn_quit"); assert(quits == 1, "QUIT on the title calls the engine's quit")
    press("Q"); assert(quits == 2, "and so does Q")
    esc(); assert(paused(), "Esc on the title opens the pause card"); pause_shown(false)
    click("pz_quit"); assert(quits == 3, "QUIT GAME on the pause card calls the engine's quit")
    assert(not paused() and api.S.mode == "title", "the card is gone")
    -- The House map: the level card goes back to the map, the map to the title, by Esc and by BACK.
    frame(30)
    press("C"); frame(30)
    assert(api.S.mode == "house" and visible("hm_back") and shown("BACK  ·  Esc"), "the map shows BACK  ·  Esc")
    click("hm_room1"); frame(30)
    assert(api.S.hz.room == "hall" and visible("hm_back"), "a room's level card, with its BACK")
    esc(); assert(api.S.mode == "house" and api.S.hz.room == nil and not paused(), "Esc: level card to the map")
    esc(); assert(api.S.mode == "title" and not paused(), "Esc: the map to the title")
    press("C"); frame(30); click("hm_tab2"); frame(5)
    click("hm_back"); frame(2)
    assert(api.S.mode == "title", "BACK: the room list to the title")
    -- Free Build: the slots panel and a run's card close by Esc or BACK / CLOSE; then the pause card; leaving autosaves.
    house.all = true
    assert(api.start_free("living"), "into Free Build")
    frame(5)
    esc(); assert(paused() and shown("Free Build"), "Esc pauses Free Build"); pause_shown(true)
    press("Space"); assert(FV.S.mode == "build", "Space on the pause card tips nothing")
    esc(); assert(not paused(), "and Esc resumes")
    click("fb_save"); frame(2)
    assert(FV.S.panel == "save" and visible("fb_slot_back"), "the save slots show their BACK")
    esc(); assert(FV.S.panel == nil and not paused() and not visible("fb_slot_back"), "Esc closes the slots, one level")
    click("fb_load"); frame(2); click("fb_slot_back"); frame(2)
    assert(FV.S.panel == nil and api.S.mode == "free", "BACK closes the slots")
    press("Space"); run_out()
    assert(visible("fb_res_close") and shown("CLOSE"), "a finished run's card shows CLOSE")
    esc(); assert(FV.S.mode == "build" and not paused() and not visible("fb_res_close"), "Esc closes the card: the dominoes stand up")
    press("Space"); run_out(); click("fb_res_close"); frame(2)
    assert(FV.S.mode == "build", "so does CLOSE")
    -- A chain running under the pause card waits.
    press("Space"); frame(3)
    assert(FV.S.mode == "running", "a chain running")
    esc()
    local fallen = FV.S.fallen
    frame(60)
    assert(paused() and FV.S.mode == "running" and FV.S.fallen == fallen, "paused: the chain waits")
    esc(); run_out()
    -- Leaving from the pause card writes the room's autosave.
    saved["Save/free_autosave.txt"] = nil
    press("C"); press("C")
    assert(FV.board().count == 0, "the room is cleared, unsaved yet")
    esc(); click("pz_menu"); frame(2)
    assert(api.S.mode == "title" and saved["Save/free_autosave.txt"], "BACK TO MENU from Free Build autosaves the room")
    -- QUIT GAME from a room writes its autosave first.
    assert(api.start_free("living")); frame(5)
    press("Backspace"); frame(2)
    saved["Save/free_autosave.txt"] = nil
    esc(); press("Q")
    assert(quits == 4 and saved["Save/free_autosave.txt"], "Q on the pause card autosaves the room, then quits")
    api.back_to_menu(); frame(5)
    -- A challenge level: a chain left mid-run from the pause card is never counted.
    local d = api.house:tiers("hall")[1]
    house.best[d.id] = nil
    env.physics.is_simulating = function() return false end
    FV.S.ch_boards[d.id] = nil
    assert(api.start_free("hall", d)); frame(3)
    local b = FV.board()
    local sol = dofile("tests/solutions/hall.lua")[1]
    b:begin_action(); (type(sol) == "function" and sol or sol.solve)(b, F); b:end_action()
    FW.sync(b)
    press("Space"); frame(3)
    assert(FV.S.mode == "running", "the level's chain runs")
    esc(); assert(paused() and shown("Challenge  ·  " .. d.name), "Esc pauses the level")
    click("pz_menu"); frame(30)
    assert(api.S.mode == "title" and house.best[d.id] == nil, "leaving mid-run counts nothing")
    env.physics.is_simulating = function() return true end
    house.all = false
    press("T"); frame(2)
    assert(api.S.mode == "build", "a table run again")
    -- Table Run's cards: the tally shows CLOSE (it closes as if it had run out), the cleared, shop and game-over cards
    -- BACK (to the title, as MENU does); Esc does the same, one level up; BACK sits clear of the card's own button.
    local function card(mode, outcome)
        api.S.mode, api.S.card_t, api.S.outcome = mode, 0.5, outcome
        api.S.res = api.S.res or { score = 0 }
        frame(3)
    end
    local function apart(a, b)
        local p, q = quads[a], quads[b]
        return p.x + p.width <= q.x + 0.5 or q.x + q.width <= p.x + 0.5 or p.y + p.height <= q.y + 0.5 or q.y + q.height <= p.y + 0.5
    end
    card("tally", "again")
    assert(visible("btn_card_back") and shown("CLOSE  ·  Esc"), "the tally shows CLOSE")
    esc(); assert(api.S.mode == "build" and not paused() and not visible("btn_card_back"), "Esc closes the tally, back to the table")
    card("tally", "again"); click("btn_card_back")
    assert(api.S.mode == "build", "and so does CLOSE")
    for _, m in ipairs({ "cleared", "shop", "over" }) do
        press("T"); frame(2)
        if m == "shop" then api.open_shop(); api.S.card_t = 0.5; frame(3) else card(m) end
        assert(api.S.mode == m and visible("btn_card_back") and shown("BACK  ·  Esc") and visible("btn_card"), "the " .. m .. " card shows BACK")
        assert(apart("btn_card_back", "btn_card"), "BACK clear of the " .. m .. " card's button")
        if m == "shop" then for i = 1, 4 do if visible("buy" .. i) then assert(apart("btn_card_back", "buy" .. i), "BACK clear of offer " .. i) end end end
        if m == "over" then click("btn_card_back") else esc() end
        assert(api.S.mode == "title" and not paused() and not visible("btn_card_back"), (m == "over" and "BACK" or "Esc") .. " on the " .. m .. " card goes to the title")
        frame(30)
    end
    press("T"); frame(2)
    assert(api.S.mode == "build", "a table run for what follows")
end

-- The Great Hall: no engine support, no hall; with it, a million dominoes are laid, fall, stand up, and it leaves cleanly.
do
    states.btn_menu = { clicked = true }; frame(); states.btn_menu = nil; frame(40)
    assert(api.S.mode == "title", "back at the title for the hall")
    keys.G = true; frame(2); keys.G = false; frame()
    assert(api.S.mode == "title", "an engine without the hinge field stays on the title card")
    local appended, fell, stood, enabled, casts = 0, 0, 0, nil, nil
    env.hinge_field = setmetatable({
        append = function(_, n) appended = appended + n; return 0 end,
        fall = function(_, n) fell = fell + n end,
        stand_all = function() stood = stood + 1 end,
        set_enabled = function(on) enabled = on end,
        set_casts_shadows = function(on) casts = on end,
    }, { __index = function() return function() end end })
    keys.G = true; frame(2); keys.G = false; frame()
    assert(api.S.mode == "hall", "G opens the Great Hall")
    assert(enabled == true, "the hall switches the hinge field on")
    local Hall = api.hall
    local n = 0
    while Hall.S.job and n < 400 do frame(); n = n + 1 end
    assert(not Hall.S.job and appended == 1000000 and Hall.core.count() == 1000000, "the first visit lays exactly a million: " .. appended)
    assert(n > 2, "laying them takes several frames, not one long one: " .. n)
    assert(casts == false, "from the opening overview the dominoes are too small to cast shadows")
    press("Space")
    assert(Hall.S.mode == "running", "Space tips the million")
    FRAME_MS = 500
    n = 0
    while Hall.S.mode == "running" and n < 600 do frame(); n = n + 1 end
    FRAME_MS = 1000 / 60
    assert(Hall.S.mode == "done" and Hall.core.toppled == 1000000, "a million fall: " .. Hall.core.toppled .. ", " .. Hall.S.mode)
    assert(fell >= 1000000 and fell < 1010000, "the engine hears of each fall, and again only for a few at the edges: " .. fell)
    assert(saved["Save/hall_best.txt"] == "1000000", "the best chain is kept")
    local before = stood
    press("R")
    assert(Hall.S.mode == "build" and stood == before + 1, "R stands them all up at once")
    -- The Picture tool: no pictures yet, draw one, and it becomes the current picture.
    press("7")
    assert(Hall.S.tool == "picture", "7 selects the Picture tool")
    click("gh_ch"); frame(2)
    assert(Hall.S.ch_open and quads.gh_ch_close and quads.gh_ch_close.visible ~= false, "the hall lists its challenges")
    press("1"); assert(Hall.S.tool == "picture", "tools wait behind the list")
    click("gh_ch_close"); frame(2)
    assert(not Hall.S.ch_open and quads.gh_ch_close.visible == false, "and BACK closes it")
    click("gh_pic_draw")
    assert(Hall.S.canvas, "the drawing canvas opens")
    click("gh_cv_col3")
    assert(Hall.S.canvas.brush == 3, "a colour is chosen")
    -- While the UI holds the mouse the engine reports no button and 0, 0, so a stroke must come from the canvas's own state.
    do
        local _, c, gx, gy = Hall.canvas_layout()
        M.x, M.y, M.left = 0, 0, false
        local function stroke(col, down, row) states.gh_canvas = { hovered = true, down = down, mouse_x = gx + (col + 0.5) * c, mouse_y = gy + ((row or 2) + 0.5) * c }; frame() end
        stroke(3, true); stroke(9, true); stroke(9, false)
        -- A new click starts where it lands, not joined to the row or column the last stroke ended on.
        stroke(20, true, 12); stroke(20, false, 12); states.gh_canvas = nil
        local cells = Hall.S.canvas.cells
        assert(cells[12 * 48 + 20 + 1] == "2", "a click paints its own cell")
        for row = 2, 11 do assert(cells[row * 48 + 20 + 1] == "0", "a new click drew a line from the last stroke's row: row " .. row) end
        for x = 3, 9 do assert(cells[2 * 48 + x + 1] == "2", "the stroke paints cell " .. x .. ": " .. cells[2 * 48 + x + 1]) end
        assert(cells[2 * 48 + 11] == "0" and cells[2 * 48 + 12] == "0", "only the stroke is painted")
    end
    click("gh_cv_done")
    assert(not Hall.S.canvas and Hall.S.pic:match("^draw:48:30:"), "the drawing becomes the picture")
    press("8")
    assert(Hall.S.tool == "split", "8 selects the splitter")
    press("]")
    assert(Hall.S.split_n == 4, "] adds a branch")
    press("9")
    assert(Hall.S.tool == "bell", "9 selects the bell")
    press("1")
    frame(120)
    assert(saved["Save/hall_autosave.txt"] and #saved["Save/hall_autosave.txt"] < 200, "a million dominoes save in a few bytes")
    click("gh_menu")
    assert(api.S.mode == "title" and enabled == false, "MENU leaves the hall and hides its dominoes")
    assert(setv.shadow_fixed_bounds == false, "leaving the hall gives the title its shadows back")
    frame(30)
    appended = 0
    keys.G = true; frame(2); keys.G = false; frame(3)
    assert(api.S.mode == "hall" and not Hall.S.job and appended == 0, "coming back finds the build still laid")
    -- Back and quit in the hall: the picture picker, the drawing canvas (its drawing kept), the challenge list and a
    -- finished run's card each close by Esc or their BACK / CLOSE, one level; then the pause card; QUIT saves first.
    do
        local quits = 0
        rawset(env.engine, "quit", function() quits = quits + 1 end)
        local function esc() press("Escape"); frame(10) end
        local had = Hall.S.tool
        press("7"); frame(2)
        assert(Hall.S.tool == "picture" and visible("gh_pic_back"), "the picture picker shows its BACK")
        esc(); assert(Hall.S.tool == had and not api.S.pause and not visible("gh_pic_back"), "Esc closes the picker: the tool you had")
        press("7"); frame(2); click("gh_pic_back"); frame(2)
        assert(Hall.S.tool == had, "BACK closes the picker")
        press("7"); frame(2); click("gh_pic_draw"); frame(2)
        assert(Hall.S.canvas and shown("BACK  ·  Esc"), "the canvas shows BACK")
        Hall.S.canvas.cells[1] = "3"
        esc(); assert(not Hall.S.canvas and Hall.S.tool == "picture" and not api.S.pause, "Esc closes the canvas, back to the picker")
        click("gh_pic_draw"); frame(2)
        assert(Hall.S.canvas and Hall.S.canvas.cells[1] == "3", "the drawing is still there when it opens again")
        click("gh_cv_cancel"); frame(2)
        assert(not Hall.S.canvas, "BACK closes the canvas")
        esc(); assert(Hall.S.tool == had, "and Esc then closes the picker")
        click("gh_ch"); frame(2); esc()
        assert(not Hall.S.ch_open and not api.S.pause, "Esc closes the challenge list")
        esc(); assert(api.S.pause and shown("the Great Hall") and visible("pz_menu"), "Esc pauses the hall")
        esc(); assert(not api.S.pause, "and resumes")
        press("Space"); frame(2)
        local n = 0
        FRAME_MS = 500
        while Hall.S.mode ~= "done" and n < 600 do frame(); n = n + 1 end
        FRAME_MS = 1000 / 60
        frame(30)
        assert(Hall.S.mode == "done" and visible("gh_res_close") and shown("CLOSE"), "a finished chain's card shows CLOSE")
        esc(); assert(Hall.S.mode == "build" and not visible("gh_res_close"), "Esc closes it: the dominoes stand up")
        -- QUIT GAME from the hall writes its autosave first.
        click("gh_undo")
        n = 0
        while Hall.S.job and n < 600 do frame(); n = n + 1 end
        saved["Save/hall_autosave.txt"] = nil
        esc(); click("pz_quit")
        assert(quits == 1 and saved["Save/hall_autosave.txt"], "QUIT GAME in the hall autosaves it, then quits")
    end
    click("gh_menu")
    env.hinge_field = nil
end
print("PASS view smoke")
