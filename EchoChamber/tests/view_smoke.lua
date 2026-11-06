-- luajit tests/view_smoke.lua  (run from the EchoChamber folder)
-- Boots the real game script and 3D world against stubbed engine APIs, then clicks a chamber's solution
-- into place, flips, takes back, sends, wins, fails, uses a hint and clears, so script errors in
-- drawing, picking, playback and input show up without launching the player. The camera stub is a
-- simple top-down projection; real picking is checked in the player.
local quads, states, keys = {}, {}, {}
local nodes_alive = 0
local io_open = io.open
local function read(path)
    if path:match("^Save/") then return nil end -- fresh profile: ignore local progress / settings
    local f = io_open("Assets/" .. path, "rb"); if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end
local env = _G
local SW, SH = 1600, 1000

env.vec3 = function(x, y, z) return { x = x, y = y, z = z } end
env.vec4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
local VP = setmetatable({}, { __mul = function(_, v) return { x = v.x / 12, y = v.z / 8, z = 0.5, w = 1 } end })
local INV = setmetatable({}, { __mul = function(_, v) return { x = v.x * 12, y = 10 - 20 * v.z, z = v.y * 8, w = 1 } end })

local Node = {}
Node.__index = function(_, k)
    if k == "remove" then return function() nodes_alive = nodes_alive - 1 end end
    if k == "get_mesh_refs" then return function() return { 1 } end end
    return function() end
end
local function node() nodes_alive = nodes_alive + 1; return setmetatable({}, Node) end
env.primitives = setmetatable({}, { __index = function() return function() return node() end end })
local cam = setmetatable({
    get_view_projection = function() return VP end,
    get_inv_view_projection = function() return INV end,
}, { __index = function() return function() end end })
env.scene = setmetatable({ add_empty_node = node, get_active_camera = function() return cam end,
    find_model = function() return setmetatable({}, Node) end },
    { __index = function() return function() end end })
env.material = setmetatable({}, { __index = function() return function() end end })
env.lights = setmetatable({ get_point_lights = function() return {} end }, { __index = function() return function() end end })
env.particles = setmetatable({ add_emitter = function() return 1 end }, { __index = function() return function() return 0 end end })
env.tween = { to = function(_, to, _, setter, opts) setter(to); if opts and opts.on_done then opts.on_done() end; return 1 end }
local saved = {}
env.fs = { read = read, write = function(p, s) saved[p] = s; return true end, exists = function() return false end }
local played = {}
env.audio = { play = function(n) played[#played + 1] = n end, set_master_volume = function() end }
env.input = { is_key_down_raw = function(k) return keys[k] == true end, is_key_down = function(k) return keys[k] == true end }
env.engine = setmetatable({ get_metrics = function() return { delta_ms = 33 } end }, { __index = function() return function() end end })
env.runtime_ui = setmetatable({
    set_quad = function(_, id, o)
        assert(type(o.x) == "number" and o.x == o.x, "bad x for " .. id)
        assert(type(o.width) == "number" and o.width == o.width, "bad width for " .. id)
        if o.label ~= nil then assert(type(o.label) == "string", "label not a string for " .. id) end
        quads[id] = o
    end,
    get_state = function(_, id) return states[id] end,
    get_surface_size = function() return { width = SW, height = SH } end,
}, { __index = function() return function() end end })
local update
env.settings = { get = function() return nil end, set = function() end }
env.script = { on_update = function(_, f) update = f end }

-- The player's Lua has no os / io libraries: hide them while the game runs so using them fails here too.
local src = assert(read("Scripts/echo.lua"))
local clock = os.clock
env.os, env.io = nil, nil
assert(load(src, "@echo.lua", "t", env))()
assert(update, "no update callback")
local api = env.echo
local W = api.W
local function frame(n) for _ = 1, n or 1 do update() end end
local function press(k) keys[k] = true; frame(); keys[k] = false; frame() end

frame(10)
assert(api.S.mode == "menu", "starts on the main menu")
press("Return")
assert(api.S.mode == "plan", "Enter on the menu did not start play")
local g = api.game()

-- HUD at several window sizes: the pulse / pieces panels stay right of the bell pips and on screen.
for _, size in ipairs({ { 1600, 1000 }, { 1280, 720 }, { 2560, 1369 }, { 1920, 1080 }, { 1366, 768 } }) do
    SW, SH = size[1], size[2]
    frame(2)
    local pm, pc = quads.pm_rim, quads.pc_rim
    assert(pc.x + pc.width <= SW + 1, "pieces panel off screen at " .. SW .. "x" .. SH)
    assert(pm.x > SW / 2 + 40, "pulse panel reaches the centre at " .. SW .. "x" .. SH)
end
SW, SH = 1600, 1000
frame(2)

-- Picking round trip: every cell's projected centre resolves back to that cell.
for y = 1, g.h do
    for x = 1, g.w do
        local X, Z = W.cell_world(x, y)
        local sx, sy = W.project(X, 0, Z)
        local cx, cy = W.cell_at(sx, sy)
        assert(cx == x and cy == y, string.format("picking round trip failed at %d,%d -> %s,%s", x, y, tostring(cx), tostring(cy)))
    end
end

local function cell_click(x, y, right)
    local X, Z = W.cell_world(x, y)
    local mx, my = W.project(X, 0, Z)
    states.board = { hovered = true, clicked = not right, right_clicked = right or false, mouse_x = mx, mouse_y = my }
    frame()
    states.board = { hovered = true, clicked = false, right_clicked = false, mouse_x = mx, mouse_y = my }
    frame()
end
local function select_tool(kind)
    for i, k in ipairs(api.R.PIECES) do if k == kind then press(tostring(i)) end end
    assert(api.S.tool == kind, "could not select " .. kind)
end

-- Fail first: send with nothing placed.
press("Space")
assert(api.S.mode == "playing", "space did not send")
for _ = 1, 600 do frame(); if api.S.mode ~= "playing" then break end end
assert(api.S.mode == "plan" and api.S.fail, "empty send should fail and return to planning")
assert(g.sends == 1)

-- Place the solution by clicking (and set reflector flips by clicking again).
for _, s in ipairs(g.solution) do
    select_tool(s.kind)
    cell_click(s.x, s.y)
    local p = g:piece(s.x, s.y)
    assert(p and p.kind == s.kind, "click did not place a " .. s.kind)
    if s.flip and p.flip ~= s.flip then cell_click(s.x, s.y) end
    assert(not s.flip or g:piece(s.x, s.y).flip == s.flip, "click did not flip the reflector")
end
-- Take one back with right-click and put it again.
local s1 = g.solution[1]
cell_click(s1.x, s1.y, true)
assert(not g:piece(s1.x, s1.y), "right-click did not take the piece back")
select_tool(s1.kind)
cell_click(s1.x, s1.y)
if s1.flip and g:piece(s1.x, s1.y).flip ~= s1.flip then cell_click(s1.x, s1.y) end
-- Hover across a row for ghosts and tips.
for x = 1, g.w do
    local X, Z = W.cell_world(x, 2)
    local mx, my = W.project(X, 0, Z)
    states.board = { hovered = true, mouse_x = mx, mouse_y = my }
    frame()
end
states.board = nil
press("Space")
local rings = 0
for _ = 1, 900 do frame(); if api.S.mode ~= "playing" then break end end
for _, n in ipairs(played) do if n:match("^bell%d") then rings = rings + 1 end end
assert(api.S.mode == "won", "the solution should win (mode " .. api.S.mode .. ")")
assert(g.stars == 2, "second send wins two stars")
assert(rings >= #g.bells, "every bell played its sound")
assert(saved["Save/echo_chamber.txt"] == "2", "progress saved")
assert(saved["Save/echo_stars.txt"] == "1 2", "stars saved per chamber: " .. tostring(saved["Save/echo_stars.txt"]))
frame(30)
assert(not quads.card_title or quads.card_title.visible == false, "win card waits while the chamber resonates")
frame(60)
press("Return")
assert(api.S.mode == "plan" and api.game().level == 2, "Enter goes to the next chamber")

-- Hint and clear.
local g2 = api.game()
press("H")
assert(api.S.hint and g2.hints == 1, "H gives a hint")
local h = api.S.hint
cell_click(h.x, h.y)
assert(g2:piece(h.x, h.y), "the hinted piece places")
press("R")
assert(g2:placed_count() == 0, "R clears the board")

-- Chamber switching does not leak scene nodes.
press("PageDown")
assert(api.game().level == 1, "PageDown goes back a chamber")
frame(5)
local first = nodes_alive
for _ = 1, 3 do press("PageUp"); frame(3); press("PageDown"); frame(3) end
assert(nodes_alive <= first + 8, "scene nodes leak across chambers: " .. first .. " -> " .. nodes_alive)
-- Play a send twice to check the trail pool does not grow.
press("Space"); for _ = 1, 600 do frame(); if api.S.mode ~= "playing" then break end end
local after1 = nodes_alive
press("Space"); for _ = 1, 600 do frame(); if api.S.mode ~= "playing" then break end end
assert(nodes_alive <= after1 + 2, "pulse playback leaks nodes: " .. after1 .. " -> " .. nodes_alive)
-- Menu: Esc opens it, CHAMBERS lists the unlocked chambers, picking one starts it, Esc resumes,
-- HOW TO PLAY and SETTINGS open from it.
local function click(id) states[id] = { clicked = true }; frame(); states[id] = nil; frame() end
press("Escape")
assert(api.S.mode == "menu", "Esc opens the menu")
frame(10)
click("m_select")
assert(api.S.mode == "select", "CHAMBERS opens chamber select")
frame(20)
assert(quads.selc1 and quads.selc1.visible ~= false, "chamber tiles are drawn")
click("selc5")
assert(api.S.mode == "select", "a locked chamber is refused")
click("selc2")
assert(api.S.mode == "plan" and api.game().level == 2, "picking chamber 2 starts it")
press("Escape"); frame(10); press("Escape")
assert(api.S.mode == "plan", "Esc in the menu resumes the chamber")
press("Escape"); frame(10)
click("m_help")
assert(api.S.mode == "help", "HOW TO PLAY opens the rules card")
press("Escape")
assert(api.S.mode == "menu", "Esc from the rules returns to the menu")
frame(10)
click("m_settings")
assert(api.settings:is_open(), "SETTINGS opens the settings menu")
frame(2)
local n = 0
for _ in pairs(quads) do n = n + 1 end
print("ui quads used:", n, "  scene nodes alive:", nodes_alive)
print("PASS view smoke")
