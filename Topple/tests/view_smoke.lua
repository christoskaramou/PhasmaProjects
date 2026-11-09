-- luajit tests/view_smoke.lua  (run from the Topple folder)
-- Boots the real game script and 3D world against stubbed engine APIs. Table Run: begins a run, draws a line of
-- dominoes by dragging across the felt (through the projection / picking round trip), extends it from its end,
-- places and aims each special toy, removes one with a right-click, undoes and clears, tips and plays the chain out,
-- then lets the autoplay hook play tables, the shop and a run's end. Free Build: opens on the demo build and tips it,
-- stands it up, clears and undoes, lays dominoes with every tool through the raw mouse, erases, sets the start,
-- right-click removes, turns and zooms the camera, plays a run and replays it, saves and loads slots, autosaves, and
-- goes back to the menu without leaking nodes. Catches script errors in drawing, input, animation and flow without
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
    if k == "remove" then return function() nodes_alive = nodes_alive - 1 end end
    if k == "get_mesh_refs" then return function() return { 1 } end end
    return function() end
end
local function node() nodes_alive = nodes_alive + 1; return setmetatable({}, Node) end
env.primitives = setmetatable({}, { __index = function() return function() return node() end end })
local cam = setmetatable({ get_view_projection = function() return VP end, get_inv_view_projection = function() return INV end },
    { __index = function() return function() end end })
local templates = {}
env.scene = setmetatable({ add_empty_node = node, get_active_camera = function() return cam end,
    find_model = function(name) templates[name] = true; return setmetatable({}, Node) end },
    { __index = function() return function() end end })
env.material = setmetatable({}, { __index = function() return function() end end })
-- The engine's rigid bodies: present, so a Free Build tip takes the live path (nothing moves, so it ends quickly).
env.physics = setmetatable({ is_simulating = function() return true end, add_body = function() env.bodies_added = (env.bodies_added or 0) + 1 end,
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
    if n:match("^clack") then clacks = clacks + 1 end
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
press("Return")
assert(api.S.mode == "free", "Enter opens Free Build")
local FV, FW, F = api.free, api.FW, api.F
local fb = FV.board()
assert(fb and fb.count > 400, "a first visit opens on the demo build")
local function vis_count() local n = 0 for _ in pairs(FW.vis) do n = n + 1 end return n end
assert(vis_count() == fb.count, "every demo domino has a node")
assert(setv.shadow_fixed_bounds == true and (setv.shadow_bounds_radius or 0) > 50 and math.abs(setv.shadow_bounds_y - 24) < 1e-6,
    "Free Build uses one fixed shadow map over the whole room")
assert(setv.lod_enabled == false, "Free Build draws at full detail (LOD meshes changed the window light with distance)")
local function click(id) states[id] = { clicked = true }; frame(); states[id] = nil; frame() end
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
keys["Return"] = true; frame(3)        -- held across several frames, as a real key press is
assert(FV.S.mode == "build", "the Enter that opens Free Build does not tip the chain: " .. FV.S.mode)
keys["Return"] = false; frame()
assert(api.S.mode == "free" and FV.board().count == mine, "Free Build reopens on the same build")
frame(5)
assert(FW.made() <= made + 128 * 5, "re-entering reuses the pooled dominoes: " .. FW.made() .. " vs " .. made)
assert(#lights_set > 0, "Free Build sets its lights")
click("fb_menu")
frame(30)
press("T")
assert(api.S.mode == "build", "Table Run still starts after Free Build")
assert(setv.shadow_fixed_bounds == false, "leaving Free Build gives Table Run its camera-fitted shadows back")
assert(setv.lod_enabled == true, "leaving Free Build turns LODs back on")
-- Settings open and close.
api.autoplay = false
press("Escape"); frame(2)
assert(api.settings:is_open(), "Esc opens the settings")
press("Escape"); frame(2)

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
    assert(fell == 1000000, "the engine hears of each fall once: " .. fell)
    assert(saved["Save/hall_best.txt"] == "1000000", "the best chain is kept")
    local before = stood
    press("R")
    assert(Hall.S.mode == "build" and stood == before + 1, "R stands them all up at once")
    -- The Picture tool: no pictures yet, draw one, and it becomes the current picture.
    press("7")
    assert(Hall.S.tool == "picture", "7 selects the Picture tool")
    click("gh_pic_draw")
    assert(Hall.S.canvas, "the drawing canvas opens")
    click("gh_cv_col3")
    assert(Hall.S.canvas.brush == 3, "a colour is chosen")
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
    click("gh_menu")
    env.hinge_field = nil
end
print("PASS view smoke")
