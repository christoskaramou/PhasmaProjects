-- luajit tests/view_smoke.lua   (run from the ShadowPuppeteer folder)
-- Boots the real game scripts against a stubbed engine with a real perspective camera, then checks:
--  1. each prop's shadow card is the planar projection of its shared silhouette (sp_data.lua) for 5 lantern positions
--     and both reference states: card corners within 0.5 % of the shadow's size;
--  2. nothing on the paper plane is drawn outside the paper rectangle without the front card covering it: whenever a
--     shadow card or paper piece reaches past the paper, the front card is up, full window height, its weights sum to 1,
--     and every bake it uses is one the generator verified opaque outside the paper (sp_data.FRONT_COVERS);
--  3. dragging (mouse -> floor / track plane) moves the lantern and props within their limits;
--  4. no pools leak: nodes, emitters and UI quads stay the same over 50 state changes and drags.
local quads, nodes_made, emitters = {}, 0, 0
local io_open = io.open
local function read(path)
    local f = io_open("Assets/" .. path, "rb"); if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end
local SW, SH = 2560, 1369
local env = _G
env.vec3 = function(x, y, z) return { x = x, y = y, z = z } end
env.vec4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end

------------------------------------------------------------------ a real camera (look-at + perspective) and its inverse
local function mat_mul_vec(m, v)
    return { x = m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13] * v.w, y = m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14] * v.w,
             z = m[3] * v.x + m[7] * v.y + m[11] * v.z + m[15] * v.w, w = m[4] * v.x + m[8] * v.y + m[12] * v.z + m[16] * v.w }
end
local function mat_mul(a, b)
    local r = {}
    for c = 0, 3 do for rr = 1, 4 do
        local s = 0
        for k = 0, 3 do s = s + a[k * 4 + rr] * b[c * 4 + k + 1] end
        r[c * 4 + rr] = s
    end end
    return r
end
local function inverse(m)
    local inv, a = {}, m
    inv[1] = a[6]*a[11]*a[16]-a[6]*a[12]*a[15]-a[10]*a[7]*a[16]+a[10]*a[8]*a[15]+a[14]*a[7]*a[12]-a[14]*a[8]*a[11]
    inv[5] = -a[5]*a[11]*a[16]+a[5]*a[12]*a[15]+a[9]*a[7]*a[16]-a[9]*a[8]*a[15]-a[13]*a[7]*a[12]+a[13]*a[8]*a[11]
    inv[9] = a[5]*a[10]*a[16]-a[5]*a[12]*a[14]-a[9]*a[6]*a[16]+a[9]*a[8]*a[14]+a[13]*a[6]*a[12]-a[13]*a[8]*a[10]
    inv[13] = -a[5]*a[10]*a[15]+a[5]*a[11]*a[14]+a[9]*a[6]*a[15]-a[9]*a[7]*a[14]-a[13]*a[6]*a[11]+a[13]*a[7]*a[10]
    inv[2] = -a[2]*a[11]*a[16]+a[2]*a[12]*a[15]+a[10]*a[3]*a[16]-a[10]*a[4]*a[15]-a[14]*a[3]*a[12]+a[14]*a[4]*a[11]
    inv[6] = a[1]*a[11]*a[16]-a[1]*a[12]*a[15]-a[9]*a[3]*a[16]+a[9]*a[4]*a[15]+a[13]*a[3]*a[12]-a[13]*a[4]*a[11]
    inv[10] = -a[1]*a[10]*a[16]+a[1]*a[12]*a[14]+a[9]*a[2]*a[16]-a[9]*a[4]*a[14]-a[13]*a[2]*a[12]+a[13]*a[4]*a[10]
    inv[14] = a[1]*a[10]*a[15]-a[1]*a[11]*a[14]-a[9]*a[2]*a[15]+a[9]*a[3]*a[14]+a[13]*a[2]*a[11]-a[13]*a[3]*a[10]
    inv[3] = a[2]*a[7]*a[16]-a[2]*a[8]*a[15]-a[6]*a[3]*a[16]+a[6]*a[4]*a[15]+a[14]*a[3]*a[8]-a[14]*a[4]*a[7]
    inv[7] = -a[1]*a[7]*a[16]+a[1]*a[8]*a[15]+a[5]*a[3]*a[16]-a[5]*a[4]*a[15]-a[13]*a[3]*a[8]+a[13]*a[4]*a[7]
    inv[11] = a[1]*a[6]*a[16]-a[1]*a[8]*a[14]-a[5]*a[2]*a[16]+a[5]*a[4]*a[14]+a[13]*a[2]*a[8]-a[13]*a[4]*a[6]
    inv[15] = -a[1]*a[6]*a[15]+a[1]*a[7]*a[14]+a[5]*a[2]*a[15]-a[5]*a[3]*a[14]-a[13]*a[2]*a[7]+a[13]*a[3]*a[6]
    inv[4] = -a[2]*a[7]*a[12]+a[2]*a[8]*a[11]+a[6]*a[3]*a[12]-a[6]*a[4]*a[11]-a[10]*a[3]*a[8]+a[10]*a[4]*a[7]
    inv[8] = a[1]*a[7]*a[12]-a[1]*a[8]*a[11]-a[5]*a[3]*a[12]+a[5]*a[4]*a[11]+a[9]*a[3]*a[8]-a[9]*a[4]*a[7]
    inv[12] = -a[1]*a[6]*a[12]+a[1]*a[8]*a[10]+a[5]*a[2]*a[12]-a[5]*a[4]*a[10]-a[9]*a[2]*a[8]+a[9]*a[4]*a[6]
    inv[16] = a[1]*a[6]*a[11]-a[1]*a[7]*a[10]-a[5]*a[2]*a[11]+a[5]*a[3]*a[10]+a[9]*a[2]*a[7]-a[9]*a[3]*a[6]
    local det = a[1] * inv[1] + a[2] * inv[5] + a[3] * inv[9] + a[4] * inv[13]
    for i = 1, 16 do inv[i] = inv[i] / det end
    return inv
end
local CAM = { pos = { 0, 0, 0 }, look = { 0, 0, -1 }, hfov = 60 }
local function wrap(m) return setmetatable({ m = m }, { __mul = function(s, v) return mat_mul_vec(s.m, v) end }) end
local function view_proj()
    local p, l = CAM.pos, CAM.look
    local fx, fy, fz = l.x - p.x, l.y - p.y, l.z - p.z
    local n = math.sqrt(fx * fx + fy * fy + fz * fz); fx, fy, fz = fx / n, fy / n, fz / n
    local rx, ry, rz = -fz, 0, fx                       -- f x (0,1,0)
    n = math.sqrt(rx * rx + rz * rz); rx, rz = rx / n, rz / n
    local ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
    local V = { rx, ux, -fx, 0, ry, uy, -fy, 0, rz, uz, -fz, 0,
        -(rx * p.x + ry * p.y + rz * p.z), -(ux * p.x + uy * p.y + uz * p.z), (fx * p.x + fy * p.y + fz * p.z), 1 }
    local th = math.tan(math.rad(CAM.hfov) / 2)
    local tv = th * SH / SW
    local nr, fr = 0.05, 200
    local P = { 1 / th, 0, 0, 0, 0, 1 / tv, 0, 0, 0, 0, -(fr + nr) / (fr - nr), -1, 0, 0, -2 * fr * nr / (fr - nr), 0 }
    return mat_mul(P, V)
end
local cam = { set_projection_mode = function() end, set_fov = function(_, d) CAM.hfov = d end,
    set_position = function(_, v) CAM.pos = v end, look_at = function(_, v) CAM.look = v end,
    get_view_projection = function() return wrap(view_proj()) end, get_inv_view_projection = function() return wrap(inverse(view_proj())) end,
    get_jitter = function() return { x = 0, y = 0 } end }

------------------------------------------------------------------ stub engine
local Node = {}
Node.__index = function(_, k)
    if k == "set_position" then return function(n, v) rawset(n, "pos", v) end end
    if k == "set_scale" then return function(n, v) rawset(n, "scl", v) end end
    if k == "set_rotation" then return function(n, v) rawset(n, "rot", v) end end
    if k == "set_enabled" then return function(n, on) rawset(n, "on", on) end end
    return function() end
end
local named = {}
env.scene = setmetatable({ get_active_camera = function() return cam end,
    add_empty_node = function(name) nodes_made = nodes_made + 1; return setmetatable({ name = name }, Node) end,
    find_model = function(name) named[name] = named[name] or setmetatable({ name = name }, Node); return named[name] end },
    { __index = function() return function() end end })
local render_type = {}                                   -- node -> render type the game set
local textures = {}                                      -- node -> slot -> texture path the game set
env.material = setmetatable({ set_render_type = function(n, t) render_type[n] = t end,
    set_texture = function(n, slot, path) textures[n] = textures[n] or {}; textures[n][slot] = path end },
    { __index = function() return function() end end })
env.particles = setmetatable({ add_emitter = function() emitters = emitters + 1; return emitters - 1 end },
    { __index = function() return function() end end })
env.lights = setmetatable({ find = function(name) return { { type = "point", index = 0, name = name } } end },
    { __index = function() return function() end end })
local setv, render_mode = {}, nil
env.settings = { get = function(k) return setv[k] end, set = function(k, v) setv[k] = v end, set_render_mode = function(m) render_mode = m end }
local states = {}
env.runtime_ui = setmetatable({
    set_quad = function(screen, id, o)
        assert(type(o.x) == "number" and o.x == o.x and type(o.width) == "number", "bad quad " .. id)
        quads[screen .. "/" .. id] = o
    end,
    get_state = function(_, id) return states[id] end,
    get_surface_size = function() return { width = SW, height = SH } end,
}, { __index = function() return function() end end })
local quit_called = false
env.engine = setmetatable({ get_metrics = function() return { delta_ms = 1000 / 60 } end, quit = function() quit_called = true end },
    { __index = function() return function() end end })
local files = {}                                         -- Save/ files the game writes (a fresh install: none)
env.fs = { read = function(path) if path:sub(1, 5) == "Save/" then return files[path] end; return read(path) end,
    write = function(path, text) files[path] = text; return true end }
local keys_down = {}
env.input = { is_key_down_raw = function(k) return keys_down[k] == true end, is_left_mouse_down = function() return false end }
local played = {}
env.audio = setmetatable({ play = function(name) played[#played + 1] = name end }, { __index = function() return function() end end })
local update
env.script = { on_update = function(_, f) update = f end }
env.os, env.io = nil, nil
-- 7a. the game boots: the script runs to the end without an error and registers its per-frame update (in the engine an
-- error during on_play stops the script before script.on_update: no camera fit, no rules, no input)
local boot_ok, boot_err = pcall(assert(load(assert(read("Scripts/puppet.lua")), "@puppet.lua", "t", env)))
assert(boot_ok, "7. the game script failed to boot: " .. tostring(boot_err))
assert(update, "7. the game script did not register its per-frame update")
local api, D, W = env.puppet, env.puppet.D, env.puppet.W
local function frame(n) for _ = 1, n or 1 do update() end end
frame(5)

assert(render_mode == "raster", "the world must ask for raster")
assert(setv.taa == true and setv.tonemapping == true and setv.physical_point_falloff == true and setv.linear_color == true, "look settings")
for _, name in ipairs(D.MESHES) do assert(W.N["N_" .. name], "scene node for " .. name) end

-- the props on stage now (the reference states: cup, comb, ladder)
local function on_stage()
    local t = {}
    for name, p in pairs(D.PROPS) do if W.present[name] then t[name] = p end end
    return pairs(t)
end
------------------------------------------------------------------ 1. shadow cards = planar projection of the shared data
local function check_cards(tag)
    local st = W.state
    local lx, ly = st.lantern[1], st.lantern[2]
    for name, p in on_stage() do
        local n = W.N["N_shadow_" .. name]
        local x = st[name]
        local k = (D.SY - ly) / (p.y - ly)                      -- independent of the game's code
        local c = D.CARD[name]
        local size = k * math.max(c[3] - c[1], c[4] - c[2])
        for _, q in ipairs({ { c[1], c[2] }, { c[3], c[2] }, { c[3], c[4] }, { c[1], c[4] } }) do
            local u = lx + k * (x + q[1] - lx)
            local v = D.LZ + k * (q[2] - D.LZ)
            local gu, gv = n.pos.x + n.scl.x * q[1], n.pos.y + n.scl.y * q[2]
            assert(math.abs(gu - u) <= 0.005 * size and math.abs(gv - v) <= 0.005 * size,
                string.format("%s: %s shadow corner (%.4f, %.4f) should be (%.4f, %.4f)", tag, name, gu, gv, u, v))
        end
        assert(math.abs(n.pos.z - (-D.SY + D.LAYER.shadow)) < 1e-9, name .. " shadow card off its layer")
        -- the penumbra copy: same place and scale, just behind the core and in front of the paper
        local pn = W.N["N_shadowpen_" .. name]
        assert(pn and math.abs(pn.pos.x - n.pos.x) < 1e-9 and math.abs(pn.pos.y - n.pos.y) < 1e-9 and pn.scl.x == n.scl.x
            and pn.scl.y == n.scl.y, name .. " penumbra card does not follow its shadow")
        assert(math.abs(pn.pos.z - (-D.SY + D.LAYER.penumbra)) < 1e-9 and D.LAYER.penumbra < D.LAYER.shadow
            and D.LAYER.penumbra > 0, name .. " penumbra card not between the paper and the core")
        -- overlapping shadows must be a union: the core opaque (blended cards keep only the last alpha, Pipeline.cpp:52)
        assert(render_type[n] == "alpha_cut" and render_type[pn] == "alpha_blend",
            name .. " shadow core not opaque (alpha_cut) or penumbra not blended")
    end
end
local LP = { { D.LANTERN_X[1], D.LANTERN_Y[1] }, { D.LANTERN_X[2], D.LANTERN_Y[1] }, { 0, (D.LANTERN_Y[1] + D.LANTERN_Y[2]) / 2 },
    { D.LANTERN_X[1], D.LANTERN_Y[2] }, { D.LANTERN_X[2], D.LANTERN_Y[2] } }
for i, l in ipairs(LP) do
    api.set({ lantern = { l[1], l[2] } })
    check_cards("lantern position " .. i)
end
api.state_a(); check_cards("state A")
api.state_b(); check_cards("state B")
print("1. shadow cards match the planar projection at 5 lantern positions and both states")

------------------------------------------------------------------ 2. outside the paper only under the front card
local covered = {}
for _, f in ipairs(D.FRONT_COVERS or {}) do covered[f] = true end
local function card_extent(name)
    local n, c = W.N["N_shadow_" .. name], D.CARD[name]
    return n.pos.x + n.scl.x * c[1], n.pos.y + n.scl.y * c[2], n.pos.x + n.scl.x * c[3], n.pos.y + n.scl.y * c[4]
end
local paper_reach = 0                                   -- paper pieces reach past the paper too (cliffs to +-2.6)
for _, poly in pairs(D.LEVEL.solids) do for _, p in ipairs(poly) do paper_reach = math.max(paper_reach, math.abs(p[1])) end end
local function check_front(tag)
    local outside = paper_reach > D.SCREEN_U[2]
    for name in on_stage() do
        local u0, v0, u1, v1 = card_extent(name)
        if u0 < D.SCREEN_U[1] or u1 > D.SCREEN_U[2] or v1 > D.SCREEN_V[2] then outside = true end
    end
    if not outside then return end
    local sum, n = 0, 0
    for m = 1, 4 do
        local q = quads["puppet/front" .. m]
        if q and q.visible ~= false then
            n = n + 1
            assert(q.y <= 0 and q.height >= SH and q.x <= 0 and q.x + q.width >= SW, tag .. ": the front card must cover the window")
            local f = q.path:match("(front_%d_%d)")
            assert(f and covered[f], tag .. ": " .. tostring(f) .. " is not a bake verified opaque outside the paper")
            sum = sum * (1 - q.image_tint[4]) + q.image_tint[4]
        end
    end
    assert(n > 0 and math.abs(sum - 1) < 1e-6, tag .. ": something is drawn outside the paper and the front card does not cover it")
end
math.randomseed(7)
for i = 1, 30 do
    api.set({ lantern = { D.LANTERN_X[1] + math.random() * (D.LANTERN_X[2] - D.LANTERN_X[1]),
        D.LANTERN_Y[1] + math.random() * (D.LANTERN_Y[2] - D.LANTERN_Y[1]) },
        cup = D.PROPS.cup.x[1] + math.random() * (D.PROPS.cup.x[2] - D.PROPS.cup.x[1]),
        comb = D.PROPS.comb.x[1] + math.random() * (D.PROPS.comb.x[2] - D.PROPS.comb.x[1]),
        ladder = D.PROPS.ladder.x[1] + math.random() * (D.PROPS.ladder.x[2] - D.PROPS.ladder.x[1]) })
    frame()
    check_front("random state " .. i)
end
print("2. whenever a paper-plane layer passes the paper's edge, the verified front card covers it")

------------------------------------------------------------------ 3. dragging
api.state_a(); frame(2)
local function mouse_at(x, y, z) local sx, sy = W.project(x, y, z); return sx, sy end
local function drag(what, from, to)
    local sx, sy = mouse_at(from[1], from[2], from[3])
    states.stage = { down = true, mouse_x = sx, mouse_y = sy }; frame()
    assert(api.S.drag and api.S.drag.what == what, "pressing on the " .. what .. " grabs it (got " .. tostring(api.S.drag and api.S.drag.what) .. ")")
    local tx, ty = mouse_at(to[1], to[2], to[3])
    states.stage = { down = true, mouse_x = tx, mouse_y = ty }; frame()
    states.stage = { down = false, mouse_x = tx, mouse_y = ty }; frame()
end
local L0 = { W.state.lantern[1], W.state.lantern[2] }
drag("lantern", { L0[1], L0[2], 0.01 }, { L0[1] + 0.8, L0[2] + 0.2, 0.01 })
assert(math.abs(W.state.lantern[1] - (L0[1] + 0.8)) < 0.02 and math.abs(W.state.lantern[2] - (L0[2] + 0.2)) < 0.03, "the lantern follows the mouse on the floor")
drag("lantern", { W.state.lantern[1], W.state.lantern[2], 0.2 }, { 9, 5, 0.2 })
assert(W.state.lantern[1] == D.LANTERN_X[2] and W.state.lantern[2] == D.LANTERN_Y[2], "the lantern stops at its limits")
api.state_a(); frame()
local c0 = W.state.comb
drag("comb", { c0 + 0.25, D.PROPS.comb.y, 0.28 }, { c0 + 0.55, D.PROPS.comb.y, 0.28 })
assert(math.abs(W.state.comb - (c0 + 0.3)) < 0.01, "the comb slides along its track")
drag("comb", { W.state.comb + 0.25, D.PROPS.comb.y, 0.28 }, { 9, D.PROPS.comb.y, 0.28 })
assert(W.state.comb == D.PROPS.comb.x[2], "the comb stops at the end of its track")
check_cards("after drags")
print("3. the lantern and props drag within their limits; shadows follow")

------------------------------------------------------------------ 4. pools
local function count_quads() local n = 0; for _ in pairs(quads) do n = n + 1 end; return n end
local before = { nodes_made, emitters, count_quads() }
for i = 1, 50 do
    if i % 2 == 0 then api.state_a() else api.state_b() end
    api.set({ lantern = { -1.45 + (i % 7) * 0.4, -1.2 + (i % 3) * 0.2 } })
    frame()
end
drag("ladder", { W.state.ladder, D.PROPS.ladder.y, 0.5 }, { W.state.ladder - 0.2, D.PROPS.ladder.y, 0.5 })
local after = { nodes_made, emitters, count_quads() }
assert(before[1] == after[1] and before[2] == after[2] and before[3] == after[3],
    string.format("pools leak: nodes %d->%d, emitters %d->%d, quads %d->%d", before[1], after[1], before[2], after[2], before[3], after[3]))
print("4. no nodes, emitters or UI quads leak over 50 state changes")

------------------------------------------------------------------ 5. play: the rules walk the jointed puppet
api.play(); frame(2)
local root = scene.add_empty_node and nil
local g = api.S.game
local x0 = g.x
frame(60)
assert(api.S.game.x > x0 + 0.15 and api.S.game.mode == "walk", "the puppet walks right in play: " .. api.status())
local r = W.pp_root
assert(r and r.pos and math.abs(r.pos.x - api.S.game.x) < 1e-9 and math.abs(r.pos.y - api.S.game.y) < 1e-9,
    "the jointed puppet stands where the rules put it")
-- dragging while it walks changes its ground on the next step (the rules read the dragged stage)
local before = W.state.lantern[1]
drag("lantern", { W.state.lantern[1], W.state.lantern[2], 0.01 }, { W.state.lantern[1] - 0.4, W.state.lantern[2], 0.01 })
assert(W.state.lantern[1] < before - 0.3 and api.S.game.mode ~= nil, "drag works while the puppet walks")
api.run("win")
for _ = 1, 60 * 40 do frame(); if api.S.game.won or api.S.game.dead then break end end
assert(api.S.game.won and api.S.game.star, "the scripted win plays through the game loop: " .. api.status())
api.run("nothing")
for _ = 1, 60 * 40 do frame(); if api.S.game.won or api.S.game.dead then break end end
assert(api.S.game.dead == "thorns", "doing nothing loses through the game loop: " .. api.status())
local after = { nodes_made, emitters }
api.play(); frame(30)
assert(nodes_made == after[1] and emitters == after[2], "restarting makes no nodes")
print("5. play: the puppet walks, drags work while it walks, scripted win and do-nothing loss through the game loop")

------------------------------------------------------------------ 6. the slide and climb poses agree with the rules
do
    local PS = D.PUPPET.scale
    local back, hip = 0.024 * PS, D.PUPPET.hip * PS
    for _, sl in ipairs({ 56, 62, 75, 85 }) do
        local p = { x = 0.1, y = 0.3, dir = 1, mode = "slide", slope = sl, phase = 0.4 }
        W.pose_puppet(p, 1.0)
        local q = W.pp_pose
        local b = math.rad(q.tilt)
        -- the coat's back edge at the feet and at the hip, rotated by the lean about the root (CCW, toward the camera)
        local function world(lx, ly) return q.x + lx * math.cos(b) - ly * math.sin(b), q.y + lx * math.sin(b) + ly * math.cos(b) end
        local th = math.rad(sl)
        local function off_face(u, v) return (u - p.x) * math.sin(th) + (v - p.y) * math.cos(th) end   -- signed distance
        local u0, v0 = world(-back, 0)
        local u1, v1 = world(-back, hip)
        assert(math.abs(off_face(u0, v0)) < 1e-9 and math.abs(off_face(u1, v1)) < 1e-9,
            string.format("slide pose: back %.5f / %.5f off the %d deg face", off_face(u0, v0), off_face(u1, v1), sl))
    end
    local al = {}
    for _, ph in ipairs({ 0.5, 1.5 }) do
        W.pose_puppet({ x = 0, y = 0.3, dir = 1, mode = "climb", phase = ph }, 1.0)
        al[#al + 1] = { W.N.N_pp_arm_l.rot.z, W.N.N_pp_arm_r.rot.z, W.N.N_pp_leg_l.rot.z, W.N.N_pp_leg_r.rot.z }
    end
    assert(al[1][1] > al[1][2] + 60 and al[2][2] > al[2][1] + 60 and al[1][3] > al[1][4] and al[2][4] > al[2][3],
        "climb: the hands and knees do not alternate")
    W.pose_puppet({ x = 0, y = 0.3, dir = 1, mode = "walk", phase = 0 }, 1.0)
end
print("6. slide pose: the coat's back lies on the face (56-85 deg); climb alternates hands and knees")
------------------------------------------------------------------ 7. every level of every map and both reference states boot
-- each with no Lua error over its first frames; every prop the level has is placed and shown (with its shadow card
-- under the lantern's projection), every prop it lacks is hidden
local function check_props(tag, present)
    for name in pairs(D.PROPS) do
        local n, sh, shl = W.N["N_" .. name], W.N["N_shadow_" .. name], W.N["N_shadow_" .. name .. "_l"]
        local on = present[name] ~= nil
        -- a prop that turns round (the mouse) shows its mirrored card while it runs left: one of the two, never both
        if shl then
            assert(not (sh.on ~= false and shl.on ~= false), tag .. ": both of " .. name .. "'s shadow cards shown")
            if on and shl.on ~= false then sh = shl end
            if not on then assert(shl.on == false, tag .. ": " .. shl.name .. " should be hidden") end
        end
        for _, nd in ipairs({ n, sh }) do
            if nd then
                if on then
                    assert(nd.on ~= false, tag .. ": " .. nd.name .. " should be shown")
                    assert(nd.pos and nd.pos.x == nd.pos.x, tag .. ": " .. nd.name .. " has no position")
                else
                    assert(nd.on == false, tag .. ": " .. nd.name .. " should be hidden (not in this level)")
                end
            end
        end
    end
end
local maps = {}
for _, lv in ipairs(D.LEVELS) do
    local ok, err = pcall(api.play, lv.id)
    assert(ok, "7. level " .. lv.id .. " failed to start: " .. tostring(err))
    ok, err = pcall(frame, 30)
    assert(ok, "7. level " .. lv.id .. " failed in its first frames: " .. tostring(err))
    assert(env.puppet.L.id == lv.id and env.puppet.S.game and env.puppet.S.game.t > 0, "7. level " .. lv.id .. " is not running")
    check_props("7. level " .. lv.id, lv.props)
    maps[lv.map] = (maps[lv.map] or 0) + 1
    -- its own cut paper only (the rules' polygons, gen_meshes paper_*_<id>), its props' tracks only, its set's bakes
    local tag = lv.id:gsub("-", "_")
    for _, o in ipairs(D.LEVELS) do
        local ot = o.id:gsub("-", "_")
        for _, k in ipairs({ "paper_black_", "paper_red_", "paper_gold_" }) do
            local n = W.N["N_" .. k .. ot]
            assert(n, "7. scene node N_" .. k .. ot)
            assert((n.on ~= false) == (ot == tag), "7. level " .. lv.id .. ": N_" .. k .. ot .. (ot == tag and " hidden" or " shown"))
        end
    end
    for _, tn in ipairs({ "cup", "comb", "ladder", "mouse" }) do
        local n = W.N["N_track_slot_" .. tn]
        assert(n and (n.on ~= false) == (lv.props[tn] ~= nil), "7. level " .. lv.id .. ": the " .. tn .. " track's visibility")
    end
    local look = D.MAPLOOK[lv.map]
    assert(textures[W.N.N_paper] and textures[W.N.N_paper].base_color == look.tex .. "albedo.png",
        "7. level " .. lv.id .. ": the paper shows " .. tostring(textures[W.N.N_paper] and textures[W.N.N_paper].base_color))
    assert(textures[W.N.N_floor].emissive == look.tex .. "backdrop_em.png", "7. level " .. lv.id .. ": the floor's baked light")
    for _, q in pairs(W.FRONT) do
        assert(q.path:sub(1, #look.tex) == look.tex and not q.path:sub(#look.tex + 1):find("/"),
            "7. level " .. lv.id .. ": front card " .. q.path .. " is not " .. lv.map .. "'s")
    end
end
for _, m in ipairs(D.MAPS) do assert((maps[m.id] or 0) >= 3, "7. map " .. m.id .. " needs at least 3 levels") end
for _, which in ipairs({ "state_a", "state_b" }) do
    local ok, err = pcall(api[which])
    assert(ok, "7. " .. which .. " failed: " .. tostring(err))
    ok, err = pcall(frame, 3)
    assert(ok, "7. " .. which .. " failed in its first frames: " .. tostring(err))
    check_props("7. " .. which, { cup = 1, comb = 1, ladder = 1 })
end
api.play("1-3")
-- the start cliff's decoration stands clear of the puppet's start (the reference level keeps target.png's tree)
for _, lv in ipairs(D.LEVELS) do
    if lv.id ~= "1-3" then
        local px, hw = lv.start.puppet[1], D.RULES.puppet_w / 2
        assert(lv.decor_x + D.DECOR_HALF < px - hw, "7. level " .. lv.id .. ": its decoration covers the puppet's start")
    end
end
-- every set's front cards (UI images loaded on first use) and its paper/floor bakes are preloaded at boot
local want = 0
for _ in ipairs(D.MAPS) do want = want + #D.FRONT_X * #D.FRONT_Y end
assert(W.preloaded_images and #W.preloaded_images >= want, "7. the front cards of every set are preloaded at boot")
for _, mp in ipairs(D.MAPS) do
    local found = false
    for _, path in ipairs(W.preloaded_images) do if path == D.MAPLOOK[mp.id].tex .. "front_4_1.png" then found = true end end
    assert(found, "7. " .. mp.id .. "'s front cards preloaded")
end
print("7. the game boots; all " .. #D.LEVELS .. " levels of " .. #D.MAPS .. " maps and states A and B start and run")
------------------------------------------------------------------ 8. the game: cards, keyboard and mouse paths, saves, sounds
local Gm = api.G
local function key(k) keys_down[k] = true; frame(); keys_down[k] = nil; frame() end
local function click(id) states[id] = { clicked = true }; frame(); states[id] = nil; frame() end
local function wait(s) frame(math.floor(s * 60)) end
local function overlaps(tag, list)
    -- texts drawn in the same place: centre-aligned estimates, boxes shrunk to the estimated glyph run
    for i = 1, #list do for j = i + 1, #list do
        local a, b = list[i], list[j]
        if a.s ~= "" and b.s ~= "" and a.s ~= b.s then
            local ay0, ay1, by0, by1 = a.y0, a.y1, b.y0, b.y1
            local ax0, ax1 = a.ex0, a.ex1
            local bx0, bx1 = b.ex0, b.ex1
            assert(not (ax0 < bx1 and bx0 < ax1 and ay0 < by1 and by0 < ay1),
                string.format("%s: '%s' overlaps '%s'", tag, a.s, b.s))
        end
    end end
end
-- estimated glyph run of a text at px (the UI font: capitals and digits ~0.66 em, lower case ~0.52, spaces 0.30;
-- 0.52 for everything missed "SKIP TUTORIAL" wrapping onto two lines, live 2026-11-13)
local function run_w(s_, px)
    local w = 0
    for ch in s_:gmatch(".") do
        if ch:match("[A-Z0-9]") then w = w + 0.66 elseif ch == " " then w = w + 0.30 elseif ch:match("[a-z]") then w = w + 0.52 else w = w + 0.45 end
    end
    return w * px
end
local function check_layout(tag)
    for _, size in ipairs({ { 1280, 720 }, { 2560, 1369 } }) do
        SW, SH = size[1], size[2]
        frame(2)
        local seen, list = {}, {}
        for _, t in ipairs(Gm.text_log) do
            local key_ = t.s .. "@" .. math.floor(t.x) .. "," .. math.floor(t.y)
            if not seen[key_] then
                seen[key_] = true
                local w = run_w(t.s, t.px)
                assert(t.px >= 12, string.format("%s at %dx%d: '%s' is %.1f px (under 12)", tag, SW, SH, t.s, t.px))
                assert(w <= t.w + 1, string.format("%s at %dx%d: '%s' (%.0f px) overflows its %.0f px box", tag, SW, SH, t.s, w, t.w))
                assert(t.x >= -1 and t.x + t.w <= SW + 1 and t.y >= -1 and t.y + t.h <= SH + 1,
                    string.format("%s at %dx%d: '%s' leaves the window", tag, SW, SH, t.s))
                list[#list + 1] = { s = t.s, y0 = t.y + t.h * 0.25, y1 = t.y + t.h * 0.75 }
                -- glyph run: where its alignment puts it in its box
                if t.align == "left" then list[#list].ex0, list[#list].ex1 = t.x, t.x + w
                elseif t.align == "right" then list[#list].ex0, list[#list].ex1 = t.x + t.w - w, t.x + t.w
                else local cx = t.x + t.w / 2; list[#list].ex0, list[#list].ex1 = cx - w / 2, cx + w / 2 end
            end
        end
        overlaps(tag .. " at " .. SW .. "x" .. SH, list)
    end
    SW, SH = 2560, 1369
    frame(2)
end
-- a fresh boot lands on the title card; the stage behind it is the reference frame
files = {}
Gm.load_save()
-- (the guided first level and the sets' intros: check 9)
Gm.save.tutorial = true
for _, m in ipairs(D.MAPS) do Gm.save.seen[m.id] = true end
Gm.to_title(); wait(0.5)
assert(Gm.mode == "title" and api.S.mode == "look", "boots to the title card over the theatre")
local function has_text(sub) for _, t in ipairs(Gm.text_log) do if t.s:find(sub, 1, true) then return true end end end
assert(has_text("SHADOW PUPPETEER") and has_text("PLAY") and has_text("SETTINGS") and has_text("QUIT"), "title: name, PLAY, SETTINGS, QUIT")
assert(has_text("DRAG THE LANTERN") and has_text("Esc pause"), "title: the controls are spelled out")
check_layout("title")
-- keyboard path: Enter -> select, Enter -> the first level, Esc -> pause, R -> restart, Esc -> resume
key("Return"); wait(0.4)
assert(Gm.mode == "select" and Gm.sel == "1-1", "Enter opens the level select on 1-1")
assert(has_text("THE RED THEATRE") and has_text("opens at 4 stars") and has_text("BACK"), "select: sets, locks, BACK")
check_layout("select")
key("Right"); assert(Gm.sel == "1-1", "a locked set cannot be chosen")
key("Down"); assert(Gm.sel == "1-1", "a locked level cannot be chosen (1-2 opens when 1-1 is won)")
assert(not Gm.level_open("1-2") and not Gm.level_open("2-1"), "only 1-1 open on a fresh save")
key("Return"); wait(0.3)
assert(Gm.mode == "play" and api.L.id == "1-1" and api.S.game, "Enter plays the chosen level")
check_layout("play HUD")
local t1 = api.S.game.t
key("Escape"); wait(0.3)
assert(Gm.pause and api.S.game.t == api.S.game.t, "Esc pauses")
local tp = api.S.game.t; wait(0.5)
assert(api.S.game.t == tp, "the rules stop while paused")
assert(has_text("PAUSED") and has_text("RESUME") and has_text("RESTART LEVEL") and has_text("BACK TO MENU") and has_text("QUIT GAME"), "pause card rows")
check_layout("pause")
key("Escape"); wait(0.2)
assert(not Gm.pause, "Esc resumes")
wait(0.5); assert(api.S.game.t > tp, "the rules run again after resume")
key("R"); wait(0.1)
assert(api.S.game.t < 0.3, "R restarts the level")
-- mouse path: a scripted win (the game's own input path) on 1-1 -> the win card -> NEXT by click
local sol = Gm.solutions and Gm.solutions["1-1"]
assert(sol, "1-1 has a scripted solution")
Gm.start_level("1-1", "solution")
for _ = 1, 60 * 45 do frame(); if Gm.mode ~= "play" then break end end
assert(Gm.mode == "won", "the scripted solution wins 1-1 through the game: " .. api.status())
wait(0.6)
assert(has_text("THROUGH THE DOOR!") and has_text("NEXT") and has_text("RETRY") and has_text("MENU"), "win card")
check_layout("win card")
assert(Gm.save.stars["1-1"] and Gm.save.stars["1-1"] >= 1, "the win is saved")
assert(files["Save/puppet.txt"] and files["Save/puppet.txt"]:find("stars_1%-1="), "written to Save/puppet.txt")
assert(Gm.level_open("1-2"), "winning 1-1 opens 1-2")
click("e_next"); wait(0.2)
assert(Gm.mode == "play" and api.L.id == "1-2", "NEXT plays 1-2")
-- a death -> the failed card -> RETRY (Enter) -> MENU (click)
Gm.start_level("1-2", "nothing")
for _ = 1, 60 * 45 do frame(); if Gm.mode ~= "play" then break end end
assert(Gm.mode == "lost" and Gm.result.dead == "thorns", "doing nothing loses 1-2 with the failed card")
wait(0.6)
assert(has_text("CAUGHT ON THE THORNS") and has_text("RETRY"), "failed card says why")
check_layout("failed card")
key("Return"); wait(0.2)
assert(Gm.mode == "play" and api.L.id == "1-2" and api.S.game.t < 0.5, "Enter retries")
key("Escape"); wait(0.3); click("pz_menu"); wait(0.3)
assert(Gm.mode == "select", "pause -> BACK TO MENU -> the level select")
click("s_back"); wait(0.3)
assert(Gm.mode == "title", "BACK on the select card -> the title")
-- sets open by stars; a saved file is read back after a restart
for _, l in ipairs(D.LEVELS) do if l.map == "stage" then Gm.save.stars[l.id] = 2 end end
Gm.write_save()
assert(Gm.map_open(D.MAPS[2]) and not Gm.map_open(D.MAPS[3]), "6 stars open the nursery (4), not the fair (9)")
local saved = files["Save/puppet.txt"]
Gm.save.stars = {}
Gm.load_save()
assert(Gm.save.stars["1-3"] == 2 and Gm.level_open("2-1") and not Gm.level_open("2-2"), "the save reads back (a restart)")
assert(files["Save/puppet.txt"] == saved, "reading the save does not change it")
-- the mute key, sounds from the rules' events
local muted0 = Gm.SET:get("mute")
key("M")
assert(Gm.SET:get("mute") ~= muted0, "M toggles mute")
key("M")
local snd = {}
for _, n in ipairs(played) do snd[n] = true end
for _, n in ipairs({ "click.wav", "step.wav", "thorns.wav", "door.wav" }) do assert(snd[n], "sound played: " .. n) end
-- Esc on the title opens the pause card (RESUME, SETTINGS, QUIT; nothing to restart), never quits at once
key("Escape"); wait(0.3)
assert(Gm.pause and not quit_called, "Esc on the title opens the pause card, it does not quit")
assert(has_text("RESUME") and has_text("QUIT GAME") and not has_text("RESTART LEVEL"), "title pause card rows")
check_layout("title pause")
key("Escape"); wait(0.3)
assert(not Gm.pause and Gm.mode == "title", "Esc closes it")
-- QUIT on the title quits
click("t_quit")
assert(quit_called, "QUIT quits")
print("8. title, select (locks, stars), play, pause, restart, win (saved, next opened), loss, retry, menu, BACK; keyboard and mouse; text fits at 1280x720 and 2560x1369; save read back; mute; sounds")
------------------------------------------------------------------ 9. teaching: HOW TO PLAY, the guided first level, set intros, hints
quit_called = false
files = {}
Gm.load_save()                                          -- a fresh install: nothing seen yet
Gm.to_title(); wait(0.5)
key("H"); wait(0.3)
assert(Gm.howto and Gm.howto.from == "title", "H on the title opens HOW TO PLAY")
for _, need in ipairs({ "HOW TO PLAY", "red door", "walks by itself", "track", "nearer the props", "climbs", "slides",
    "Thorns", "candle", "Up to 3", "Stars open", "Arrows", "Esc pause", "BACK" }) do
    assert(has_text(need), "HOW TO PLAY says: " .. need)
end
check_layout("how to play")
click("h_back"); wait(0.3)
assert(not Gm.howto and Gm.mode == "title", "BACK closes it to the title")
click("t_howto"); wait(0.3)
assert(Gm.howto, "the title's HOW TO PLAY button opens it")
key("Escape"); wait(0.3)
assert(not Gm.howto, "Esc closes it")
-- the guided first level: from the player's own select, once
key("Return"); wait(0.4); key("Return"); wait(0.5)
assert(Gm.mode == "play" and api.L.id == "1-1" and Gm.tut and Gm.tut.step == 1, "a fresh save starts 1-1 with the guide")
local t0 = api.S.game.t
wait(1.0)
assert(api.S.game.t == t0, "the rules wait while the guide explains")
assert(has_text("THIS IS YOUR PUPPET") and has_text("SKIP TUTORIAL"), "step 1 points at the puppet, with SKIP")
-- the puppet stands on its start while the rules wait (2026-11-13 live: it stayed at the world origin, mid-stage)
assert(W.pp_root.pos and math.abs(W.pp_root.pos.x - api.S.game.x) < 1e-6 and math.abs(W.pp_root.pos.y - api.S.game.y) < 1e-6,
    "the puppet is drawn on its start under the guide")
check_layout("guide step 1")
key("Return"); wait(0.4)
assert(Gm.tut.step == 2 and has_text("RED DOOR"), "Enter: step 2, the door")
check_layout("guide step 2")
key("Return"); wait(0.4)
assert(Gm.tut.step == 3 and has_text("DRAG THE CUP"), "step 3, the cup")
check_layout("guide step 3")
key("Tab"); keys_down["A"] = true; wait(0.5); keys_down["A"] = nil; wait(0.4)
assert(Gm.tut.step == 4 and has_text("DRAG THE LANTERN"), "moving the cup moves the guide on: step 4, the lantern")
check_layout("guide step 4")
keys_down["Left"] = true; wait(0.4); keys_down["Left"] = nil; wait(0.4)
assert(Gm.tut.step == 5 and has_text("BRIDGE THE THORNS"), "moving the lantern: step 5, the bridge")
check_layout("guide step 5")
assert(api.S.game.t == t0, "the rules still wait")
key("Return"); wait(0.6)
assert(not Gm.tut and api.S.game.t > t0, "Enter (GO): the guide ends, the puppet walks")
assert(files["Save/puppet.txt"]:find("tutorial=1", 1, true), "the guide is saved as seen")
key("R"); wait(0.3)
assert(not Gm.tut, "restarting 1-1 does not show it again")
Gm.save.tutorial = nil; Gm.load_save()
assert(Gm.save.tutorial, "after a restart (save read back) it stays seen")
-- SKIP: on another fresh save, Backspace skips it and saves that
files = {}; Gm.load_save()
Gm.to_select(); wait(0.3); key("Return"); wait(0.5)
assert(Gm.tut, "the guide again on a fresh save")
click("tut_skip"); wait(0.3)
assert(not Gm.tut and Gm.save.tutorial and files["Save/puppet.txt"]:find("tutorial=1", 1, true), "SKIP ends it and saves")
-- a set's new prop, the first time its level is played from the select
for _, l in ipairs(D.LEVELS) do Gm.save.stars[l.id] = 3 end
Gm.write_save()
Gm.start_level("2-1", nil, true); wait(0.4)
assert(Gm.intro and Gm.intro.map.id == "nursery" and has_text("NEW IN THE MOONLIT NURSERY") and has_text("clockwork mouse"),
    "the nursery's mouse is introduced")
local ti = api.S.game.t; wait(0.5)
assert(api.S.game.t == ti, "the rules wait under the intro")
check_layout("nursery intro")
key("Return"); wait(0.4)
assert(not Gm.intro and Gm.save.seen.nursery, "GOT IT: seen and saved")
Gm.start_level("2-2", nil, true); wait(0.3)
assert(not Gm.intro, "not again on the same set")
Gm.start_level("3-1", nil, true); wait(0.3)
assert(Gm.intro and Gm.intro.map.id == "fair" and has_text("balloon"), "the fair's balloon is introduced")
click("in_ok"); wait(0.3)
assert(not Gm.intro and Gm.save.seen.fair, "GOT IT by click")
-- the failed card: the cause in plain words and this level's hint
Gm.start_level("3-1", "nothing")
for _ = 1, 60 * 45 do frame(); if Gm.mode ~= "play" then break end end
wait(0.6)
assert(Gm.mode == "lost" and has_text("CAUGHT ON THE THORNS") and has_text("no shadow was there") and has_text("Hint: "), "failed card: cause and hint")
check_layout("failed card with hint")
-- HOW TO PLAY from pause, and back to the pause card
Gm.start_level("1-1"); wait(0.3)
key("Escape"); wait(0.3); click("pz_howto"); wait(0.3)
assert(Gm.howto and Gm.howto.from == "pause", "pause -> HOW TO PLAY")
check_layout("how to play from pause")
key("Escape"); wait(0.3)
assert(not Gm.howto and Gm.pause, "BACK returns to the pause card")
key("Escape"); wait(0.2)
print("9. HOW TO PLAY (title button and H, pause, BACK), the guided first level (rules wait, 5 steps, saved, skippable), set intros once, failed card cause + hint; layouts at both sizes")
print("view_smoke: OK")
