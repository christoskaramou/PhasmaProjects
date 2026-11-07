-- luajit tests/view_smoke.lua  (run from the RicochetParlour folder)
-- Boots the real game script and 3D world against stubbed engine APIs. Kicks balls by clicking the
-- screen at their projected undersides (so projection and board picking round-trip), then stops
-- clicking until the run ends, and restarts. Catches script errors in drawing, picking, effects and flow.
local quads, keys, states = {}, {}, {}
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
-- Stub camera: NDC = ((X) / 5, (Y - 4) / 5); the inverse puts depth on Z so ray-plane picking works.
local VP = setmetatable({}, { __mul = function(_, v) return { x = v.x / 5, y = (v.y - 4) / 5, z = 0.5, w = 1 } end })
local INV = setmetatable({}, { __mul = function(_, v) return { x = v.x * 5, y = v.y * 5 + 4, z = 10 - 20 * v.z, w = 1 } end })
local Node = {}
Node.__index = function(_, k)
    if k == "remove" then return function() nodes_alive = nodes_alive - 1 end end
    return function() end
end
local function node() nodes_alive = nodes_alive + 1; return setmetatable({}, Node) end
env.primitives = setmetatable({}, { __index = function() return function() return node() end end })
local cam = setmetatable({ get_view_projection = function() return VP end, get_inv_view_projection = function() return INV end },
    { __index = function() return function() end end })
env.scene = setmetatable({ add_empty_node = node, get_active_camera = function() return cam end }, { __index = function() return function() end end })
env.material = setmetatable({}, { __index = function() return function() end end })
env.lights = setmetatable({ get_point_lights = function() return {} end }, { __index = function() return function() end end })
env.particles = setmetatable({}, { __index = function() return function() return 0 end end })
local saved, played = {}, {}
env.fs = { read = read, write = function(p, s) saved[p] = s; return true end, exists = function() return false end }
env.audio = { play = function(n) played[#played + 1] = n end, set_master_volume = function() end }
env.input = { is_key_down_raw = function(k) return keys[k] == true end, is_key_down = function(k) return keys[k] == true end }
env.engine = setmetatable({ get_metrics = function() return { delta_ms = 1000 / 60 } end }, { __index = function() return function() end end })
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
local render_mode
env.settings = { get = function() return nil end, set = function() end, set_render_mode = function(m) render_mode = m end }
env.script = { on_update = function(_, f) update = f end }
local src = assert(read("Scripts/rp.lua"))
env.os, env.io = nil, nil
assert(load(src, "@rp.lua", "t", env))()
local api = env.rp
local R, W = api.R, api.W
local function frame(n) for _ = 1, n or 1 do update() end end
local function press(k) keys[k] = true; frame(); keys[k] = false; frame() end

frame(30)
assert(api.S.mode == "title", "starts on the title card")
-- The engine's hybrid default refits a TLAS every frame, which faulted the GPU as effect nodes came and went.
assert(render_mode == "raster", "the game must select raster rendering")
press("Return")
assert(api.S.mode == "play", "Enter starts a run")
local g = api.game()

-- Picking round trip: a board point projects to the screen and picks back to itself.
for _, p in ipairs({ { 0, 1 }, { -2.5, 6 }, { 2.7, 3.3 } }) do
    local sx, sy = W.project(p[1], p[2], W.BALL_Z)
    local x, y = W.board_point(sx, sy)
    assert(math.abs(x - p[1]) < 1e-6 and math.abs(y - p[2]) < 1e-6, "picking round trip at " .. p[1] .. "," .. p[2])
end

-- Play 60 s by clicking under the lowest falling ball.
for _ = 1, 60 * 60 do
    states.board = { hovered = true, clicked = false }
    local low
    for _, b in ipairs(g.balls) do
        if b.vy < 0 and b.y < 2.2 and b.cooldown <= 0 and (b.kind ~= "glass" or b.touched) and (not low or b.y < low.y) then low = b end
    end
    if low then
        local sx, sy = W.project(low.x, low.y - R.BALL_R, W.BALL_Z)
        states.board = { hovered = true, clicked = true, mouse_x = sx, mouse_y = sy }
    end
    frame()
    if api.S.mode ~= "play" then break end
end
states.board = nil
print(string.format("after 60 s of clicking: kicks %d, lost %d, score %d, balls %d, tokens %d", g.kicks, g.lost, g.score, #g.balls, g.tokens))
assert(g.kicks > 50 and g.lost == 0, "clicks on screen kick the balls (kicks " .. g.kicks .. ", lost " .. g.lost .. ")")
local kick_snd = 0
for _, n in ipairs(played) do if n:match("^kick") then kick_snd = kick_snd + 1 end end
assert(kick_snd > 50, "kick sounds play")
-- Stop clicking: balls drop until the tokens run out.
for _ = 1, 60 * 240 do frame(); if api.S.mode ~= "play" then break end end
assert(api.S.mode == "over", "unattended balls end the run")
assert(saved["Save/rp_best.txt"], "best score saved")
frame(40)
local before = nodes_alive
press("Return")
assert(api.S.mode == "play" and api.game() ~= g, "Enter starts a new run")
frame(120)
assert(nodes_alive <= before + 30, "ball and effect nodes are released: " .. before .. " -> " .. nodes_alive)
press("Escape"); frame(2)
print("nodes alive", nodes_alive)
print("PASS view smoke")
