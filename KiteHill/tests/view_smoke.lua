-- luajit tests/view_smoke.lua  (run from the KiteHill folder)
-- Boots the real game script and 3D world against stubbed engine APIs: the title card's demo race, a run begun
-- with Enter, the countdown, steering with the keys and with the pointer (through the projection / picking round
-- trip), an updraft, then the autoplay hook flying heats through results, the workshop (buying an upgrade and a
-- kite) and a run's end. Catches script errors in drawing, input, animation and flow without launching the player.
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
local PY = 12
env.vec3 = function(x, y, z) return { x = x, y = y, z = z } end
env.vec4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
-- Stub camera facing the kite plane: NDC = (X / 16, (Y - 7) / 9); the inverse puts depth on Z so the mouse ray
-- meets the plane z = -PY and plane points round-trip.
local VP = setmetatable({}, { __mul = function(_, v) return { x = v.x / 16, y = (v.y - 7) / 9, z = 0.5, w = 1 } end })
local INV = setmetatable({}, { __mul = function(_, v) return { x = v.x * 16, y = v.y * 9 + 7, z = -PY + 20 * (0.5 - v.z), w = 1 } end })
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
env.particles = setmetatable({}, { __index = function() return function() return 0 end end })
env.skybox = { load = function() end }
local saved, played, music = {}, {}, nil
env.fs = { read = read, write = function(p, s) saved[p] = s; return true end, exists = function() return false end }
env.audio = { play = function(n) played[#played + 1] = n end, play_music = function(n) music = n end, set_master_volume = function() end }
env.input = { is_key_down_raw = function(k) return keys[k] == true end, is_key_down = function(k) return keys[k] == true end }
env.engine = setmetatable({ get_metrics = function() return { delta_ms = 1000 / 60 } end }, { __index = function() return function() end end })
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
env.settings = { get = function() return nil end, set = function() end, set_render_mode = function(m) render_mode = m end }
env.script = { on_update = function(_, f) update = f end }
local src = assert(read("Scripts/kitehill.lua"))
env.os, env.io = nil, nil
assert(load(src, "@kitehill.lua", "t", env))()
local api = env.kitehill
local R, W = api.R, api.W
local function frame(n) for _ = 1, n or 1 do update() end end
local function press(k) keys[k] = true; frame(); keys[k] = false; frame() end
local function count(name) local n = 0 for _, p in ipairs(played) do if p == name then n = n + 1 end end return n end
local function labels()
    local t = {}
    for _, q in pairs(quads) do if q.visible ~= false and q.label and q.label ~= "" then t[#t + 1] = q.label end end
    return table.concat(t, "|")
end

frame(30)
assert(render_mode == "raster", "the world must ask for raster")
assert(api.S.mode == "title", "starts on the title card")
assert(music == "breeze.wav", "the breeze plays under everything")
assert(templates.T_backdrop and templates.T_sail_tl_1 and templates.T_flyer_body and templates.T_mill_frame, "templates looked up")
local demo = api.race()
assert(demo and demo.t > 0.3 and demo.kites[2].h ~= R.floor(R.LAUNCH[2]) + 3.0, "the demo race flies behind the title")
assert(labels():find("KITE HILL"), "title card drawn")

-- Picking round trip on the kite plane.
for _, pt in ipairs({ { -8, 3 }, { 0, 7 }, { 10, 12 } }) do
    local sx, sy = W.plane_project(pt[1], pt[2])
    local x, h = W.plane_point(sx, sy)
    assert(math.abs(x - pt[1]) < 1e-6 and math.abs(h - pt[2]) < 1e-6, "picking round trip failed")
end

press("Return")
local race = api.race()
assert(api.S.mode == "race" and api.run() and race ~= demo and race.t < 0, "Enter begins a run at the countdown")
assert(#W.gates == #race.gates, "a gate built for every ring")
frame(60 * 3 + 5)
assert(race.t > 0, "the countdown ran out")
assert(count("count.wav") == 3 and count("go.wav") == 1, "three ticks and a go")

-- Keys turn the kite.
local me = race.kites[1]
local a0 = me.a
keys.A = true; frame(6); keys.A = false
assert(R.wrap(me.a - a0) > 0.2, "A turns the kite left")
a0 = me.a
keys.Right = true; frame(6); keys.Right = false
assert(R.wrap(me.a - a0) < -0.2, "Right turns the kite right")
-- The pointer steers: put it straight above the kite.
local function point_at(x, h)
    local sx, sy = W.plane_project(x, h)
    states.field = { hovered = true, mouse_x = sx, mouse_y = sy }
end
point_at(me.x + 0.5, me.h + 6); frame()
point_at(me.x, me.h + 6); frame(25)
assert(math.abs(R.wrap(me.a - math.pi / 2)) < 0.5, "the kite turns toward the pointer, heading " .. me.a)
assert(api.S.aim, "the pointer's aim mark is shown")
-- Updraft.
local b0 = me.boosts
press("Space")
assert(me.boosts == b0 - 1 and count("boost.wav") == 1, "Space spends an updraft")
states.field = nil

-- Hand over to the autoplay hook: fly heats until a run ends.
api.autoplay = true
local seen, frames = {}, 0
local went_shop = false
while frames < 60 * 900 and not seen.over do
    frame(); frames = frames + 1
    seen[api.S.mode] = true
    if api.S.mode == "results" and not went_shop and api.S.card_t > 0.5 then
        -- Visit the workshop from the results card: buy an upgrade and a kite, then on to the next heat.
        api.autoplay = false
        press("W")
        assert(api.S.mode == "shop", "W opens the workshop")
        local sv = api.save()
        sv.coins = sv.coins + 40
        local c0, lvl = sv.coins, sv.sail
        states.up1 = { clicked = true }; frame(); states.up1 = nil; frame()
        assert(sv.sail == lvl + 1 and sv.coins < c0, "clicking an upgrade buys it")
        local idx
        for i, d in ipairs(R.DESIGNS) do if d.id == "sunflower" then idx = i end end
        states["ds" .. idx] = { clicked = true }; frame(); states["ds" .. idx] = nil; frame()
        assert(sv.design == "sunflower" and sv.owned.sunflower, "clicking a kite buys and flies it")
        assert(labels():find("KITE WORKSHOP"), "workshop drawn")
        frame(20)
        press("Return")
        assert(api.S.mode == "race" and api.race().kites[1].design == "sunflower", "the next heat flies the new kite")
        went_shop = true
        api.autoplay = true
    end
end
local modes = {}
for k in pairs(seen) do modes[#modes + 1] = k end
table.sort(modes)
print("modes seen:", table.concat(modes, " "), " heats reached:", api.run().heat)
assert(seen.results and seen.over and went_shop, "autoplay should win heats, visit the workshop and end a run")
assert(count("finish.wav") >= 1 and count("chime1.wav") >= 1 and count("gust.wav") >= 1, "rings chime, gusts blow, finishes cheer")
assert(saved["Save/kitehill_save.txt"] and R.load_save(saved["Save/kitehill_save.txt"]).best >= 1, "the save keeps the best heat")
-- A few more runs, to see nothing leaks.
local runs0 = api.save().runs
frames = 0
while api.save().runs < runs0 + 3 and frames < 60 * 900 do frame(); frames = frames + 1 end
local n = 0
for _ in pairs(quads) do n = n + 1 end
print("ui quads used:", n, "  scene nodes alive:", nodes_alive)
assert(nodes_alive < 1200, "scene nodes leak across races: " .. nodes_alive .. " alive")
-- Settings open and close.
api.autoplay = false
press("Escape"); frame(2)
assert(api.settings:is_open(), "Esc opens the settings")
press("Escape"); frame(2)
print("PASS view smoke")
