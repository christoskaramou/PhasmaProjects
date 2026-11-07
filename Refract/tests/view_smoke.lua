-- luajit tests/view_smoke.lua  (run from the Refract folder)
-- Boots the real view script and 3D world module against stubbed engine APIs, then clicks, builds,
-- turns, sells and plays waves, so script errors in drawing, picking and input paths show up without
-- launching the player. The camera stub is a simple top-down projection; real picking is checked in
-- the player.
local quads, states, keys = {}, {}, {}
local nodes_alive, emitters = 0, 0
local io_open = io.open
local function read(path)
    local f = io_open("Assets/" .. path, "rb"); if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end
local env = _G
local SW, SH = 1600, 1000

-- Vectors and matrices: tables with fields; the stub view-projection maps world (X, *, Z) to NDC
-- (X / 12, Z / 8) and the inverse encodes depth in Y so ray-plane picking works.
env.vec3 = function(x, y, z) return { x = x, y = y, z = z } end
env.vec4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
local VP = setmetatable({}, { __mul = function(_, v) return { x = v.x / 12, y = v.z / 8, z = 0.5, w = 1 } end })
local INV = setmetatable({}, { __mul = function(_, v) return { x = v.x * 12, y = 10 - 20 * v.z, z = v.y * 8, w = 1 } end })

local Node = {}
Node.__index = function(_, k)
    if k == "remove" then return function() nodes_alive = nodes_alive - 1 end end
    return function() end
end
local function node() nodes_alive = nodes_alive + 1; return setmetatable({}, Node) end
env.primitives = setmetatable({}, { __index = function() return function() return node() end end })
local cam = setmetatable({
    get_view_projection = function() return VP end,
    get_inv_view_projection = function() return INV end,
}, { __index = function() return function() end end })
-- Point lights as the engine keeps them: add_point makes a light plus a scene node of the same name, and every
-- frame the engine copies each node's position into its light. A lamp whose node is not moved stays at the
-- origin, so after each frame every lit lamp must sit where it was last put, and no lamp may be left unset.
local lamps, lamp_node, lamp_checks, lamps_lit = {}, {}, 0, {}
local LampNode = { __index = { set_position = function(self, p) self.p = { p.x, p.y, p.z } end } }
env.lights = setmetatable({
    add_point = function()
        local name = "Point Light " .. #lamps
        lamps[#lamps + 1] = { name = name, p = { 0, 0, 0 }, intensity = 1, radius = 10, fresh = true }
        lamp_node[name] = setmetatable({ p = { 0, 0, 0 } }, LampNode)
    end,
    get_point_lights = function()
        local t = {}
        for i, l in ipairs(lamps) do
            t[i] = { index = i - 1, name = l.name, position = env.vec3(l.p[1], l.p[2], l.p[3]), intensity = l.intensity, radius = l.radius }
        end
        return t
    end,
    set_point_light = function(i, pos, _, intensity, radius)
        local l = lamps[i + 1]
        if l then l.p, l.want, l.intensity, l.radius, l.fresh = { pos.x, pos.y, pos.z }, { pos.x, pos.y, pos.z }, intensity, radius, false end
    end,
}, { __index = function() return function() end end })
local function sync_lamps()
    for i, l in ipairs(lamps) do
        local n = lamp_node[l.name]
        l.p = { n.p[1], n.p[2], n.p[3] }
        assert(not l.fresh, "lamp " .. (i - 1) .. " was never set: it glows at the origin at default brightness")
        if l.intensity > 0 then
            local w = l.want
            assert(math.abs(l.p[1] - w[1]) + math.abs(l.p[2] - w[2]) + math.abs(l.p[3] - w[3]) < 1e-4, string.format(
                "lamp %d was set to (%.2f, %.2f, %.2f) but its scene node is at (%.2f, %.2f, %.2f)", i - 1, w[1], w[2], w[3], l.p[1], l.p[2], l.p[3]))
            lamp_checks, lamps_lit[i] = lamp_checks + 1, true
        end
    end
end
env.scene = setmetatable({ add_empty_node = node, get_active_camera = function() return cam end,
    find_model = function(name) return lamp_node[name] end },
    { __index = function() return function() end end })
env.material = setmetatable({}, { __index = function() return function() end end })
env.particles = setmetatable({
    add_emitter = function() emitters = emitters + 1; return emitters end,
}, { __index = function() return function() return 0 end end })
env.tween = { to = function(_, to, _, setter, opts) setter(to); if opts and opts.on_done then opts.on_done() end; return 1 end }

env.fs = { read = read, write = function() return true end, exists = function() return false end }
env.audio = { play = function() end, set_master_volume = function() end }
env.input = { is_key_down_raw = function(k) return keys[k] == true end, is_key_down = function(k) return keys[k] == true end }
env.engine = setmetatable({ get_metrics = function() return { delta_ms = 33 } end }, { __index = function() return function() end end })
env.runtime_ui = setmetatable({
    set_quad = function(_, id, o)
        assert(type(o.x) == "number" and o.x == o.x, "bad x for " .. id)
        assert(type(o.width) == "number" and o.width == o.width, "bad width for " .. id)
        quads[id] = o
    end,
    get_state = function(_, id) return states[id] end,
    get_surface_size = function() return { width = SW, height = SH } end,
}, { __index = function() return function() end end })
local update
env.settings = { get = function() return nil end, set = function() end }
env.script = { on_update = function(_, f) update = f end }

-- The player's Lua has no os / io libraries: hide them while the game runs so using them fails here too.
local src = assert(read("Scripts/refract.lua"))
env.os, env.io = nil, nil
assert(load(src, "@refract.lua", "t", env))()
assert(update, "no update callback")
local api = env.refract
local W = api.W
local function frame(n) for _ = 1, n or 1 do update(); sync_lamps() end end
sync_lamps()   -- straight after load, before any update: no lamp slot may be left glowing at the origin
local function press(k) keys[k] = true; frame(); keys[k] = false; frame() end

frame(12)
assert(api.S.mode == "intro")
press("Return")
assert(api.S.mode == "play", "intro did not close")
local g = api.game()

-- HUD layout: at any window size the energy / core panels stay right of the wave pips.
for _, size in ipairs({ { 1600, 1000 }, { 1500, 1000 }, { 1280, 1000 }, { 1280, 720 }, { 2560, 1369 }, { 1920, 1080 } }) do
    for _, fps in ipairs({ false, true }) do
        SW, SH = size[1], size[2]
        api.settings.cfg.show_fps = fps
        frame(2)
        local pip, en, co = quads.pip12, quads.en_rim, quads.co_rim
        assert(en.x >= pip.x + pip.width, string.format("energy panel overlaps the wave pips at %dx%d (fps %s)", SW, SH, tostring(fps)))
        assert(co.x + co.width <= SW, "core panel off screen at " .. SW .. "x" .. SH)
    end
end
SW, SH = 1600, 1000
api.settings.cfg.show_fps = false
frame(2)

-- Picking round trip: every cell's projected centre resolves back to that cell.
for y = 1, g.h do
    for x = 1, g.w do
        local X, Z = W.cell_world(x, y)
        local sx, sy = W.project(X, W.BLOCK_H, Z)
        local cx, cy = W.cell_at(sx, sy)
        assert(cx == x and cy == y, string.format("picking round trip failed at %d,%d -> %s,%s", x, y, tostring(cx), tostring(cy)))
    end
end

local function cell_click(x, y, right)
    local X, Z = W.cell_world(x, y)
    local mx, my = W.project(X, W.BLOCK_H, Z)
    states.board = { hovered = true, clicked = not right, right_clicked = right or false, mouse_x = mx, mouse_y = my }
    frame()
    states.board = { hovered = true, clicked = false, right_clicked = false, mouse_x = mx, mouse_y = my }
    frame()
end
local placed = 0
for _, p in ipairs(g.path) do
    for _, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
        local x, y = p[1] + d[1], p[2] + d[2]
        if placed < 2 and g:kind(x, y) == "ground" and not g:piece(x, y) then
            cell_click(x, y); if g:piece(x, y) then placed = placed + 1 end
        end
    end
end
assert(placed == 2, "could not place emitters by clicking")
press("2")
assert(api.S.tool == "mirror")
-- Hover across a row to exercise previews, ghosts and tooltips.
for x = 1, g.w do
    local X, Z = W.cell_world(x, 4)
    local mx, my = W.project(X, W.BLOCK_H, Z)
    states.board = { hovered = true, mouse_x = mx, mouse_y = my }
    frame()
end
-- Turn and sell one emitter; place and flip a mirror and a prism.
for k, p in pairs(g.pieces) do
    local x, y = (k - 1) % g.w + 1, math.floor((k - 1) / g.w) + 1
    local d = p.dir
    press("1"); cell_click(x, y); assert(p.dir ~= d, "click did not turn the emitter")
    cell_click(x, y, true); assert(not g:piece(x, y), "right-click did not sell")
    break
end
press("3")
for y = 1, g.h do
    if g:kind(2, y) == "ground" and not g:piece(2, y) then cell_click(2, y); break end
end
press("Space")
assert(g.state == "fight", "space did not start the wave")
press("F"); press("F")
for _ = 1, 3000 do frame(); if api.S.mode ~= "play" then break end end
print("state after play:", g.state, "wave", g.wave, "core", g.core, "mode", api.S.mode)
local n = 0
for _ in pairs(quads) do n = n + 1 end
print("ui quads used:", n, "  scene nodes alive:", nodes_alive, "  emitters:", emitters)
assert(api.S.mode == "lost", "two emitters should not hold the sector")
local before = nodes_alive
frame(20); press("Return")
assert(api.S.mode == "play" and api.game() ~= g and api.game().wave == 0, "retry did not restart the sector")
frame(5)
local first = nodes_alive
for _ = 1, 3 do api.S.mode = "lost"; api.S.card_t = 1; press("Return"); frame(5) end
assert(nodes_alive <= first + 5, "scene nodes leak across sector restarts: " .. first .. " -> " .. nodes_alive)
print("nodes before retry", before, "after retries", first, nodes_alive)
-- Settings menu opens and closes.
press("Escape")
frame(2)
local lit = 0
for _ in pairs(lamps_lit) do lit = lit + 1 end
print("lamps:", #lamps, "  lit at some point:", lit, "  lit lamp-frames checked:", lamp_checks)
assert(#lamps >= 40 and lit >= 3, "beam, core and gate lamps should light during play")
print("PASS view smoke")
