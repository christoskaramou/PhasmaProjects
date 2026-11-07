-- luajit tests/view_smoke.lua  (run from the ResonanceBreak folder)
-- Boots the real game script and 3D world against stubbed engine APIs, starts a run, presses A S D F
-- on each pane's hit time for three waves, then stops pressing until the shield breaks, and restarts.
-- Catches script errors in drawing, pane pooling, shards, key handling and the cards.
local quads, keys = {}, {}
local nodes_alive = 0
local io_open = io.open
local function read(path)
    if path:match("^Save/") then return nil end
    local f = io_open("Assets/" .. path, "rb"); if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end
local env = _G
local SW, SH = 1600, 1000
env.vec3 = function(x, y, z) return { x = x, y = y, z = z } end
env.vec4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
local VP = setmetatable({}, { __mul = function(_, v) return { x = v.x / 8, y = v.y / 6 - v.z / 40, z = 0.5, w = 1 } end })
local Node = {}
Node.__index = function(_, k)
    if k == "remove" then return function() nodes_alive = nodes_alive - 1 end end
    return function() end
end
local function node() nodes_alive = nodes_alive + 1; return setmetatable({}, Node) end
env.primitives = setmetatable({}, { __index = function() return function() return node() end end })
local cam = setmetatable({ get_view_projection = function() return VP end }, { __index = function() return function() end end })
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
    find_model = function(name) return lamp_node[name] end }, { __index = function() return function() end end })
env.material = setmetatable({}, { __index = function() return function() end end })
env.particles = setmetatable({}, { __index = function() return function() return 0 end end })
local saved, played = {}, {}
env.fs = { read = read, write = function(p, s) saved[p] = s; return true end, exists = function() return false end }
env.audio = { play = function(n) played[#played + 1] = n end, set_master_volume = function() end }
env.input = { is_key_down_raw = function(k) return keys[k] == true end, is_key_down = function(k) return keys[k] == true end }
local DT = 1 / 60
env.engine = setmetatable({ get_metrics = function() return { delta_ms = DT * 1000 } end }, { __index = function() return function() end end })
env.runtime_ui = setmetatable({
    set_quad = function(_, id, o)
        assert(type(o.x) == "number" and o.x == o.x, "bad x for " .. id)
        assert(type(o.width) == "number" and o.width == o.width, "bad width for " .. id)
        if o.label ~= nil then assert(type(o.label) == "string", "label not a string for " .. id) end
        quads[id] = o
    end,
    get_state = function() return nil end,
    get_surface_size = function() return { width = SW, height = SH } end,
}, { __index = function() return function() end end })
local update
env.settings = { get = function() return nil end, set = function() end }
env.script = { on_update = function(_, f) update = f end }
local src = assert(read("Scripts/rb.lua"))
env.os, env.io = nil, nil
assert(load(src, "@rb.lua", "t", env))()
local api = env.rb
local R = api.R
local function frame(n) for _ = 1, n or 1 do update(); sync_lamps() end end
sync_lamps()   -- straight after load, before any update: no lamp slot may be left glowing at the origin
local function press(k) keys[k] = true; frame(); keys[k] = false; frame() end

frame(30)
assert(api.S.mode == "title", "starts on the title card")
press("Return")
assert(api.S.mode == "play", "Enter starts a run")
local g = api.game()
-- Autoplay three waves: press each pane's fork on the frame its hit time arrives (chords together).
local KEYS = { "A", "S", "D", "F" }
local struck = {}
local frames = 0
while g.wave <= 3 and api.S.mode == "play" and frames < 60 * 120 do
    local down = {}
    for _, p in ipairs(g.panes) do
        if not p.done and not struck[p] and g.t + DT * 0.5 >= p.t then struck[p] = true; down[KEYS[R.key_at(p, p.t)]] = true end
    end
    for k in pairs(down) do keys[k] = true end
    frame()
    for k in pairs(down) do keys[k] = false end
    frames = frames + 1
end
print(string.format("after 3 waves: wave %d score %d combo %d perfect %d great %d good %d miss %d empty %d",
    g.wave, g.score, g.combo, g.counts.perfect, g.counts.great, g.counts.good, g.counts.miss, g.counts.empty))
assert(g.wave == 4 and g.counts.miss == 0 and g.counts.empty == 0, "frame-timed play clears three waves cleanly")
local forks, shatters = 0, 0
for _, n in ipairs(played) do
    if n:match("^fork%d") then forks = forks + 1 end
    if n:match("^shatter%d") then shatters = shatters + 1 end
end
assert(forks > 50 and shatters > 50, "fork and shatter sounds play")
-- Wrong key: an empty strike breaks the combo.
press("A"); press("A")
-- Stop playing: panes crack the shield until the run ends.
for _ = 1, 60 * 60 do frame(); if api.S.mode ~= "play" then break end end
assert(api.S.mode == "over", "missing every pane ends the run")
assert(saved["Save/rb_best.txt"] == tostring(g.score), "best score saved")
frame(40)
local before = nodes_alive
press("Return")
assert(api.S.mode == "play" and api.game() ~= g, "Enter starts a new run")
frame(200)
assert(nodes_alive <= before + 40, "nodes stay pooled across runs: " .. before .. " -> " .. nodes_alive)
press("Escape"); frame(2)
print("nodes alive", nodes_alive)
local lit = 0
for _ in pairs(lamps_lit) do lit = lit + 1 end
print("lamps:", #lamps, "  lit at some point:", lit, "  lit lamp-frames checked:", lamp_checks)
assert(#lamps >= 16 and lit >= 12, "the window, fork and lantern lamps should all light")
print("PASS view smoke")
