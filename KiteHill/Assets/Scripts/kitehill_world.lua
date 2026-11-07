-- Kite Hill world. The hills, village, windmill tower, sky and clouds are a pre-rendered Cycles backdrop
-- (tools/make_backdrop.py) shown unlit on a quad that exactly fills the fixed camera's view. On top, in 3D: the
-- four kites (cloth panels painted per design, a swinging tail of ribbon bows, the flying line), the ribbon gates on
-- their poles, the kite flyer who turns to follow the kite, and the windmill's sails (faster in a gust), lit by the
-- scene's sun and a sky HDR, with soft shadows cast on the pictured grass from the sun's direction.
-- Field point (x, y) at height h is engine (x, h, -y). The kites fly in the plane y = R.PLANE_Y.
-- The camera, sun and windmill numbers match tools/kh_common.py (the bake).
return function(R)
local W = {}
local floor, min, max, abs, sin, cos, sqrt = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt
local deg, rad, pi = math.deg, math.rad, math.pi
local atan2 = math.atan2 or math.atan
local function v3(x, y, z) return vec3(x, y, z) end

W.CAM = { pos = { 0.0, 4.0, 14.0 }, look = { 0.0, 6.5, -20.0 }, vfov = 42.0 }
do  -- toward the sun, field axes (engine (-0.55, 0.62, 0.5) normalized, as tools/kh_common.py)
    local x, y, z = -0.55, 0.62, 0.50
    local L = sqrt(x * x + y * y + z * z)
    W.SUN = { x = x / L, y = -z / L, h = y / L }
end
do
    local mx, my, mh, face = 18.0, 50.0, 7.2, rad(-90 - 28)
    local base = R.ground(mx, my)
    W.MILL = { x = mx + cos(face) * 1.75, y = my + sin(face) * 1.75, h = base + mh + 0.55, face = face }
end
local PY = R.PLANE_Y
local cam
local S = { t = 0, shake = 0, mill = 0, mill_speed = 0.6 }

------------------------------------------------------------------ materials (template clones replay writes: engine quirk)
local mat_q = {}
local function mset(n, k, v)
    pcall(material.set, n, k, v)
    mat_q[#mat_q + 1] = { n = n, k = k, v = v, c = 0 }
end
local function flush_mats()
    for i = #mat_q, 1, -1 do
        local q = mat_q[i]
        q.c = q.c + 1
        if q.c == 2 or q.c == 6 or q.c == 20 then
            if q.f then q.f() else pcall(material.set, q.n, q.k, q.v) end
        end
        if q.c >= 20 then table.remove(mat_q, i) end
    end
end
local function mat(n, base, metal, rough, emis)
    mset(n, "base_color", vec4(base[1], base[2], base[3], base[4] or 1))
    mset(n, "emissive", v3(emis and emis[1] or 0, emis and emis[2] or 0, emis and emis[3] or 0))
    mset(n, "metallic", metal or 0)
    mset(n, "roughness", rough or 0.5)
end
-- Paints (linear), pulled toward grey: the backdrop went through Cycles' AgX view, which rolls saturated colours
-- off; the engine draws the 3D actors without that tone curve (as in Topple).
local function agx(c, k)
    local l = 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
    return { l + (c[1] - l) * k, l + (c[2] - l) * k, l + (c[3] - l) * k }
end
W.PAINT = {
    cream = agx({ 0.86, 0.80, 0.64 }, 0.8), terracotta = agx({ 0.66, 0.24, 0.10 }, 0.75), mustard = agx({ 0.82, 0.58, 0.12 }, 0.75),
    plum = agx({ 0.36, 0.14, 0.30 }, 0.8), rose = agx({ 0.84, 0.48, 0.48 }, 0.75), sky = agx({ 0.36, 0.56, 0.78 }, 0.75),
    white = agx({ 0.90, 0.89, 0.85 }, 1), ochre = agx({ 0.70, 0.46, 0.14 }, 0.75), sage = agx({ 0.40, 0.52, 0.32 }, 0.7),
    red = agx({ 0.70, 0.12, 0.08 }, 0.75), navy = agx({ 0.12, 0.18, 0.36 }, 0.85), olive = agx({ 0.38, 0.40, 0.14 }, 0.75),
}
local LOOK = {
    wood = function(n) mat(n, { 0.62, 0.45, 0.27 }, 0, 0.6) end,
    darkwood = function(n) mat(n, { 0.20, 0.12, 0.07 }, 0, 0.6) end,
    string = function(n) mat(n, { 0.88, 0.85, 0.76 }, 0, 0.7) end,
    skin = function(n) mat(n, { 0.80, 0.56, 0.42 }, 0, 0.6) end,
    shirt = function(n) mat(n, { 0.86, 0.83, 0.74 }, 0, 0.8) end,
    trousers = function(n) mat(n, agx({ 0.20, 0.27, 0.40 }, 0.8), 0, 0.85) end,
    straw = function(n) mat(n, { 0.80, 0.66, 0.38 }, 0, 0.8) end,
    canvas = function(n) mat(n, { 0.86, 0.82, 0.72 }, 0, 0.85) end,
    todo = function(n) mat(n, W.PAINT.cream, 0, 0.6) end,
    next = function(n) mat(n, W.PAINT.mustard, 0, 0.5, { 0.25, 0.16, 0.03 }) end,
    done = function(n) mat(n, W.PAINT.sage, 0, 0.6) end,
}
for k, c in pairs(W.PAINT) do LOOK[k] = function(n) mat(n, c, 0, 0.55) end end

------------------------------------------------------------------ nodes
local TPL = {}
local seq = 0
-- Every node a gate makes goes on its list, so clearing the course removes them all (children first).
local LIST
local function track(n) if LIST then LIST[#LIST + 1] = n end; return n end
local function clone(name, parent, look)
    local t = TPL[name]
    if not t then
        local n = scene.find_model and scene.find_model("T_" .. name)
        t = { mesh = n and n:get_mesh_refs()[1] or nil }
        TPL[name] = t
    end
    seq = seq + 1
    local n = track(scene.add_empty_node(name .. "_" .. seq))
    if t.mesh then n:add_mesh_ref(t.mesh) end
    if parent then n:set_parent(parent) end
    if look and LOOK[look] then LOOK[look](n) end
    return n
end
local function empty(parent, x, y, z)
    seq = seq + 1
    local n = track(scene.add_empty_node("kh_e" .. seq))
    if parent then n:set_parent(parent) end
    n:set_position(v3(x or 0, y or 0, z or 0))
    return n
end
local function kill(n) if n then pcall(function() n:remove() end) end end
local function show(n, on) if n then pcall(function() n:set_enabled(on and true or false) end) end end

local function shadow_node(tex, alpha)
    local n = track(primitives.cube(1))
    pcall(material.set_render_type, n, "alpha_blend")
    mat(n, { 0.05, 0.08, 0.03, alpha or 0.4 }, 0, 1)
    pcall(material.set_texture, n, "base_color", tex or "Textures/shadow.png")
    return n
end
-- Where the sun throws field point (x, y, h) on the ground (two refinements for the slope).
local function cast(x, y, h)
    local sx, sy = x, y
    for _ = 1, 3 do
        local g = R.ground(sx, sy)
        local k = (h - g) / W.SUN.h
        sx, sy = x - W.SUN.x * k, y - W.SUN.y * k
    end
    return sx, sy, R.ground(sx, sy)
end
W.cast = cast

-- A cord between two engine points: root (position) -> yaw -> pitch -> the unit line scaled to length.
local function cord(look, radius)
    local c = { root = empty(nil), r = radius }
    c.yaw = empty(c.root)
    c.pitch = empty(c.yaw)
    c.line = clone(look == "tail" and "tail_string" or "line", c.pitch, "string")
    return c
end
local function set_cord(c, ax, ay, az, bx, by, bz)
    local dx, dy, dz = bx - ax, by - ay, bz - az
    local hz = sqrt(dx * dx + dz * dz)
    local L = sqrt(dx * dx + dy * dy + dz * dz)
    c.root:set_position(v3(ax, ay, az))
    c.yaw:set_rotation(v3(0, deg(atan2(-dz, dx)), 0))
    c.pitch:set_rotation(v3(0, 0, deg(atan2(dy, hz))))
    c.line:set_scale(v3(max(1e-3, L), c.r, c.r))
end

------------------------------------------------------------------ init
function W.init()
    cam = scene.get_active_camera()
    pcall(function() cam:set_projection_mode("perspective") end)
    if not W.settings_node then
        W.settings_node = scene.add_empty_node("Scene Settings")
        pcall(function() W.settings_node:set_scene_settings(true) end)
    end
    -- Raster, like the other games here (the hybrid default refits a ray-tracing TLAS every frame).
    pcall(settings.set_render_mode, "raster")
    if skybox and skybox.load then pcall(skybox.load, "sky.hdr") end
    -- The backdrop is already graded (AgX): no tonemapping or bloom on top of it.
    for k, v in pairs({ tonemapping = false, bloom = false, render_scale = 1.0, taa = true, fxaa = false, cas_sharpening = false,
        motion_blur = false, ssao = false, ssr = false, IBL = true, IBL_intensity = 1.0, shadows = true, color_grading = false,
        dof = false }) do pcall(settings.set, k, v) end
    local t = scene.find_model and scene.find_model("T_backdrop")
    if t then
        W.backdrop = t
        mat(t, { 0, 0, 0, 1 }, 0, 1, { 1, 1, 1 })
        pcall(material.set_texture, t, "emissive", "Textures/backdrop.png")
        mat_q[#mat_q + 1] = { c = 0, f = function() pcall(material.set_texture, t, "emissive", "Textures/backdrop.png") end }
    end
    W.kites, W.gates, W.fx = {}, {}, {}
    W.build_flyer()
    W.build_mill()
end

------------------------------------------------------------------ the flyer and the windmill
function W.build_flyer()
    local F = { x = R.FLYER.x, y = R.FLYER.y }
    F.g = R.ground(F.x, F.y)
    F.root = empty(nil, F.x, F.g, -F.y)
    clone("flyer_legs", F.root, "trousers")
    clone("flyer_body", F.root, "shirt")
    clone("flyer_head", F.root, "skin")
    clone("flyer_hat", F.root, "straw")
    clone("flyer_band", F.root, "terracotta")
    F.arms = {}
    for i, sx in ipairs({ -0.21, 0.21 }) do
        local a = empty(F.root, sx, 1.42, 0)
        clone("flyer_arm", a, "shirt")
        F.arms[i] = a
    end
    F.spool = clone("flyer_spool", F.arms[2], "wood")
    F.spool:set_position(v3(-0.1, -0.62, 0))
    F.shadow = shadow_node("Textures/shadow.png", 0.35)
    W.flyer = F
end
-- Turn the flyer to face the kite and raise the arms along the line; returns the spool's engine position.
local function pose_flyer(kx, kh, dt)
    local F = W.flyer
    if not F then return 0, 0, 0 end
    local ex, ey, ez = kx - F.x, kh - (F.g + 1.42), -PY + F.y
    local want = atan2(-ex, -ez)
    F.yaw = F.yaw and F.yaw + R.wrap(want - F.yaw) * min(1, dt * 6) or want
    F.root:set_rotation(v3(0, deg(F.yaw), 0))
    local hz = sqrt(ex * ex + ez * ez)
    local phi = atan2(hz, -ey)
    local pitch = deg(phi) * 0.85
    for i, a in ipairs(F.arms) do
        a:set_rotation(v3(pitch + (i == 1 and 4 or 0), 0, 0))
    end
    -- The spool: shoulder + 0.62 along the arm.
    local th = rad(pitch)
    local lx, ly, lz = 0.11, 1.42 - 0.62 * cos(th), -0.62 * sin(th)
    local c, s = cos(F.yaw), sin(F.yaw)
    local wx, wz = lx * c + lz * s, -lx * s + lz * c
    local sxs, sys = cast(F.x, F.y, F.g + 1.8)
    F.shadow:set_position(v3((F.x + sxs) / 2, R.ground(F.x, F.y) + 0.02, -(F.y + sys) / 2))
    F.shadow:set_rotation(v3(0, deg(atan2(sys - F.y, sxs - F.x)), 0))
    F.shadow:set_scale(v3(sqrt((sxs - F.x) ^ 2 + (sys - F.y) ^ 2) + 0.5, 0.001, 0.55))
    return F.x + wx, F.g + ly, -F.y + wz
end

function W.build_mill()
    local M = W.MILL
    M.root = empty(nil, M.x, M.h, -M.y)
    M.root:set_rotation(v3(0, deg(atan2(cos(M.face), -sin(M.face))), 0))
    M.spin = empty(M.root)
    clone("mill_frame", M.spin, "wood")
    clone("mill_cloth", M.spin, "canvas")
end

------------------------------------------------------------------ kites
local PANELS = { "tl", "tr", "bl", "br" }
local TAIL_N, TAIL_SEG = 12, 0.3
-- Anchors of the rivals' lines: below the bottom of the picture, as if their flyers stood behind the camera.
local function anchor(i)
    if i == 1 then return nil end
    return R.LAUNCH[i] * 1.2, -2.6, -(-0.5)
end

function W.paint(i, design_id)
    local k = W.kites[i]
    if not k then return end
    local d = R.design(design_id)
    for j, p in ipairs(PANELS) do
        local c = W.PAINT[d.panels[j]] or W.PAINT.cream
        mat(k.panels[j], c, 0, 0.75)
    end
    local bow = k.bows[2]                -- every bow of a kite shares one material entry
    if bow then mat(bow, W.PAINT[d.tail] or W.PAINT.cream, 0, 0.6) end
    k.design = design_id
end

local function build_kite(i, design_id)
    local k = { i = i }
    k.root = empty(nil)
    k.spin = empty(k.root)
    k.body = empty(k.spin)
    k.panels = {}
    for j, p in ipairs(PANELS) do k.panels[j] = clone("sail_" .. p .. "_" .. i, k.body) end
    clone("kite_spars", k.body, "darkwood")
    k.tail = {}
    k.bows, k.strings = {}, {}
    for j = 1, TAIL_N do
        k.tail[j] = { x = 0, y = 0, px = 0, py = 0 }
        if j > 1 then
            k.strings[j - 1] = clone("tail_string", nil, "string")
            -- A bow on every other knot, so the string shows between them.
            if j % 2 == 1 then k.bows[j - 1] = clone("tail_bow_" .. i, nil) end
        end
    end
    k.line = cord("line", i == 1 and 0.012 or 0.01)
    k.shadow = shadow_node("Textures/shadow_kite.png", 0.38)
    W.kites[i] = k
    W.paint(i, design_id)
    k.fresh = true
    return k
end

-- Kite pose: position (field x, h in the plane), heading a, the time since it crashed (nil while flying).
local function pose_kite(k, kx, kh, a, crashed, dt, wind)
    local z = -PY
    local spin = deg(a) - 90
    local flutter = 6 * sin(S.t * 9 + k.i * 1.7) + 3 * sin(S.t * 23 + k.i)
    local tilt = 0
    if crashed then
        -- Down on the grass: tipped over and lying back.
        local u = min(1, crashed / 0.35)
        tilt = -70 * u
        spin = spin + 160 * u
        flutter = 0
    end
    k.root:set_position(v3(kx, kh, z))
    k.spin:set_rotation(v3(0, 0, spin))
    k.body:set_rotation(v3(tilt, flutter, 0))
    -- The tail: a short rope hanging from the kite's tail tip, swung by its motion and the wind.
    local ar = rad(spin)
    local tx, ty = kx + sin(ar) * 1.0, kh - cos(ar) * 1.0
    local T = k.tail
    if k.fresh then
        for j = 1, TAIL_N do T[j].x, T[j].y, T[j].px, T[j].py = tx, ty - (j - 1) * TAIL_SEG, tx, ty - (j - 1) * TAIL_SEG end
        k.fresh = false
    end
    T[1].x, T[1].y = tx, ty
    local g = -7.0 * dt * dt
    local wx = (wind or 0) * 0.6 * dt * dt
    for j = 2, TAIL_N do
        local p = T[j]
        local vx, vy = (p.x - p.px) * 0.94, (p.y - p.py) * 0.94
        p.px, p.py = p.x, p.y
        p.x, p.y = p.x + vx + wx + sin(S.t * 5 + j * 0.9 + k.i) * 0.0009, p.y + vy + g
    end
    for _ = 1, 3 do
        for j = 2, TAIL_N do
            local a_, b_ = T[j - 1], T[j]
            local dx, dy = b_.x - a_.x, b_.y - a_.y
            local L = sqrt(dx * dx + dy * dy)
            if L > 1e-6 then
                local f = (L - TAIL_SEG) / L
                if j == 2 then
                    b_.x, b_.y = b_.x - dx * f, b_.y - dy * f
                else
                    a_.x, a_.y = a_.x + dx * f * 0.5, a_.y + dy * f * 0.5
                    b_.x, b_.y = b_.x - dx * f * 0.5, b_.y - dy * f * 0.5
                end
            end
        end
        T[1].x, T[1].y = tx, ty
    end
    -- Keep the tail off the grass.
    for j = 2, TAIL_N do
        local fl = R.floor(T[j].x) + 0.1
        if T[j].y < fl then T[j].y = fl end
    end
    for j = 2, TAIL_N do
        local a_, b_ = T[j - 1], T[j]
        local s = k.strings[j - 1]
        local dx, dy = b_.x - a_.x, b_.y - a_.y
        s:set_position(v3(a_.x, a_.y, z - 0.02))
        s:set_rotation(v3(0, 0, deg(atan2(dy, dx))))
        s:set_scale(v3(sqrt(dx * dx + dy * dy), 0.008, 0.008))
        local bw = k.bows[j - 1]
        if bw then bw:set_position(v3(b_.x, b_.y, z - 0.02))
        bw:set_rotation(v3(0, 0, deg(atan2(dy, dx)) + 90)) end
    end
    -- Shadow on the grass.
    local sx, sy, sg = cast(kx, PY, kh)
    k.shadow:set_position(v3(sx, sg + 0.03 + k.i * 0.002, -sy))
    k.shadow:set_rotation(v3(0, -spin * 0.3, 0))
    local sc = 1.9 * (1 - min(0.35, (kh - sg) * 0.015))
    k.shadow:set_scale(v3(sc * 0.85, 0.001, sc))
    -- The tow point (where the line ties on), in front of the kite.
    local fx, fy = -sin(ar) * 0.15, cos(ar) * 0.15
    return kx + fx, kh + fy, z + 0.4
end

------------------------------------------------------------------ gates
local function gate_parts(g)
    local v = { g = g, scale = 0, want = false, all = {} }
    LIST = v.all
    local fl = R.floor(g.x)
    local pole_h = g.h - g.r - fl
    v.root = empty(nil, g.x, fl, -PY)
    v.pole = clone("pole", v.root, "wood")
    v.pole:set_scale(v3(1, pole_h, 1))
    v.knot = clone("pole_knot", v.root, "terracotta")
    v.knot:set_position(v3(0, pole_h, 0))
    v.ring = empty(v.root, 0, pole_h + g.r, 0)
    v.ring_scale = empty(v.ring)
    v.ring_scale:set_scale(v3(g.r, g.r, g.r))
    clone("ring", v.ring_scale, "wood")
    v.wraps, v.streams = {}, {}
    for _, st in ipairs({ "todo", "next", "done" }) do
        v.wraps[st] = clone("ring_wrap_" .. st, v.ring_scale, st)
        v.streams[st] = {}
        for j, ang in ipairs({ -150, -30 }) do
            local s = empty(v.ring, cos(rad(ang)) * g.r, sin(rad(ang)) * g.r, 0.02)
            clone("streamer_" .. st, s, st)
            v.streams[st][j] = s
        end
    end
    v.state = nil
    v.shadow = shadow_node("Textures/shadow_pole.png", 0.32)
    v.rshadow = shadow_node("Textures/shadow_ring.png", 0.32)
    LIST = nil
    show(v.root, false)
    return v
end
local function set_state(v, st)
    if v.state == st then return end
    v.state = st
    for name, n in pairs(v.wraps) do show(n, name == st) end
    for name, list in pairs(v.streams) do for _, s in ipairs(list) do show(s, name == st) end end
end

function W.clear()
    for _, v in pairs(W.gates or {}) do
        for i = #v.all, 1, -1 do kill(v.all[i]) end
        v.all = {}
    end
    W.gates = {}
end

-- A new course: build its gates (hidden until a kite needs them) and put the kites at their launch spots.
function W.setup(race, designs)
    W.clear()
    for i, g in ipairs(race.gates) do W.gates[i] = gate_parts(g) end
    for i = 1, #race.kites do
        local d = designs and designs[i] or race.kites[i].design
        if not W.kites[i] then build_kite(i, d)
        elseif W.kites[i].design ~= d then W.paint(i, d) end
        W.kites[i].fresh = true
        W.kites[i].crash_t = nil
    end
    W.race = race
end

------------------------------------------------------------------ effects
local function burst(x, h, c, n, sp, life, grav, vel, size)
    local k = W.particle_scale and W.particle_scale() or 1
    if k <= 0 then return end
    pcall(particles.emit_burst, { position = v3(x, h, -PY), velocity = vel or v3(0, 0.6, 0),
        color_start = vec4(c[1], c[2], c[3], 0.95), color_end = vec4(c[1], c[2], c[3], 0), gravity = v3(0, grav or -2.0, 0),
        count = max(1, floor(n * k)), size_min = (size or 0.06) * 0.5, size_max = size or 0.06, life_min = 0.3, life_max = life or 0.9,
        spawn_radius = 0.3, noise_strength = sp or 2.0, drag = 1.5 })
end
W.CONFETTI = { { 0.95, 0.75, 0.30 }, { 0.90, 0.45, 0.32 }, { 0.96, 0.93, 0.84 }, { 0.55, 0.70, 0.45 } }
function W.confetti(x, h, big)
    for _, c in ipairs(W.CONFETTI) do burst(x, h, c, big and 14 or 7, big and 3.2 or 2.2, 1.1, -1.6, nil, 0.08) end
end
function W.puff(x, h)
    burst(x, h, { 0.56, 0.62, 0.36 }, 16, 2.0, 0.8, -1.0, v3(0, 1.2, 0), 0.1)
    burst(x, h, { 0.85, 0.82, 0.70 }, 8, 1.6, 0.7, -1.0, v3(0, 0.8, 0), 0.08)
    W.shake(0.2)
end
function W.boost_fx(x, h, a)
    burst(x - cos(a), h - sin(a), { 0.98, 0.95, 0.88 }, 10, 1.0, 0.6, 0, v3(-cos(a) * 3, -sin(a) * 3, 0), 0.07)
end
-- Gust streaks: pale motes blown across the field.
function W.gust_fx(vx, vh)
    local k = W.particle_scale and W.particle_scale() or 1
    if k <= 0 then return end
    local from = vx > 0 and R.FIELD.x0 - 1 or R.FIELD.x1 + 1
    for _ = 1, 3 do
        local h = R.floor(0) + 1.5 + math.random() * (R.FIELD.h1 - 2)
        pcall(particles.emit_burst, { position = v3(from, h, -PY + 0.5), velocity = v3(vx * 4.5, vh * 2, 0),
            color_start = vec4(0.98, 0.96, 0.9, 0.7), color_end = vec4(0.98, 0.96, 0.9, 0), gravity = v3(0, 0, 0),
            count = max(1, floor(6 * k)), size_min = 0.03, size_max = 0.06, life_min = 1.2, life_max = 2.4, spawn_radius = 1.2,
            noise_strength = 0.6, drag = 0 })
    end
end

------------------------------------------------------------------ per frame
-- Which gates stand: each racing kite's next R.SHOWN rings.
local function wanted(race)
    local want = {}
    for _, k in ipairs(race.kites) do
        if not k.finished then
            for j = k.gate, min(#race.gates, k.gate + R.SHOWN - 1) do want[j] = true end
        end
    end
    return want
end
local function ease_back(t) t = max(0, min(1, t)); local c = 1.7; return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2 end

local function update_gates(race, dt)
    local want = wanted(race)
    local me = race.kites[1]
    for i, v in ipairs(W.gates) do
        local g = v.g
        local on = want[i] == true
        if on ~= v.want then v.want, v.t = on, 0 end
        v.t = (v.t or 0) + dt
        local s = on and ease_back(v.t * 2.2) or max(0, 1 - v.t * 3)
        if on or s > 0 then
            show(v.root, true)
            v.root:set_scale(v3(max(0.001, s), max(0.001, s), max(0.001, s)))
            set_state(v, i < me.gate and "done" or (i == me.gate and "next" or "todo"))
            -- Streamers flutter downwind.
            local wx = W.wind_x or 0
            for _, list in pairs(v.streams) do
                for j, n in ipairs(list) do
                    n:set_rotation(v3(8 * sin(S.t * 3 + i + j), 0, 14 * sin(S.t * 4.3 + i * 2 + j) - wx * 6))
                end
            end
            -- The pole's and the ring's shadows.
            local fl = R.floor(g.x)
            local tx, ty, tg = cast(g.x, PY, (g.h - g.r) * s + fl * (1 - s))
            local dx, dy = tx - g.x, ty - PY
            local L = sqrt(dx * dx + dy * dy)
            show(v.shadow, s > 0.05)
            v.shadow:set_position(v3((g.x + tx) / 2, (fl + tg) / 2 + 0.03, -(PY + ty) / 2))
            v.shadow:set_rotation(v3(0, deg(atan2(dy, dx)), 0))
            v.shadow:set_scale(v3(L + 0.3, 0.001, 0.32))
            local rx, ry, rg = cast(g.x, PY, g.h * s + fl * (1 - s))
            show(v.rshadow, s > 0.05)
            v.rshadow:set_position(v3(rx, rg + 0.035, -ry))
            v.rshadow:set_rotation(v3(0, deg(atan2(dy, dx)), 0))
            v.rshadow:set_scale(v3(2 * g.r * s * abs(W.SUN.y / W.SUN.h) + 0.4, 0.001, 2 * g.r * s + 0.2))
        else
            show(v.root, false); show(v.shadow, false); show(v.rshadow, false)
        end
        if v.state == "next" then
            local e = 0.18 + 0.14 * sin(S.t * 4)
            pcall(material.set, v.wraps.next, "emissive", v3(e, e * 0.65, e * 0.12))
        end
    end
end

function W.update(dt, race)
    S.t = S.t + dt
    flush_mats()
    local wx = race and R.wind(race) or 0
    W.wind_x = wx
    -- Windmill: turns in the breeze, faster in a gust.
    S.mill_speed = S.mill_speed + ((0.55 + abs(wx) * 0.35) - S.mill_speed) * min(1, dt * 1.5)
    S.mill = S.mill + S.mill_speed * dt
    if W.MILL.spin then W.MILL.spin:set_rotation(v3(0, 0, -deg(S.mill))) end
    if race then
        update_gates(race, dt)
        for i, k in ipairs(race.kites) do
            local v = W.kites[i]
            if v then
                if k.crashed > 0 then v.crash_t = (v.crash_t or 0) + dt else v.crash_t = nil end
                local tx, th, tz = pose_kite(v, k.x, k.h, k.a, v.crash_t, dt, wx)
                local ax, ay, az
                if i == 1 then
                    ax, ay, az = pose_flyer(k.x, k.h, dt)
                else
                    local x, y, z = anchor(i)
                    ax, ay, az = x, y, z
                end
                set_cord(v.line, ax, ay, az, tx, th, tz)
            end
        end
    end
    -- Camera: fixed on the bake's view. Shake turns the view a touch (a pure rotation keeps things on the picture).
    S.shake = max(0, S.shake - dt * 2.5)
    local sk = S.shake
    local sx, sy = sk * 0.1 * sin(S.t * 43), sk * 0.1 * sin(S.t * 37 + 1)
    local sw, sh = W.screen_size()
    pcall(function() cam:set_fov(deg(2 * math.atan(math.tan(rad(W.CAM.vfov / 2)) * sw / max(1, sh)))) end)
    local p, l = W.CAM.pos, W.CAM.look
    cam:set_position(v3(p[1], p[2], p[3]))
    cam:look_at(v3(l[1] + sx, l[2] + sy, l[3]))
    W.vp, W.inv = cam:get_view_projection(), cam:get_inv_view_projection()
    local ok, j = pcall(function() return cam:get_jitter() end)
    W.jx, W.jy = ok and j and j.x or 0, ok and j and j.y or 0
end

------------------------------------------------------------------ picking
function W.screen_size()
    local s = runtime_ui.get_surface_size()
    return s.width or 1280, s.height or 800
end
local function flip()
    if W.flip == nil then
        local vp = W.vp or cam:get_view_projection()
        local a, b = vp * vec4(0, 9, -PY, 1), vp * vec4(0, 2, -PY, 1)
        W.flip = (a.y / a.w) > (b.y / b.w)    -- y-up NDC: screen y must be inverted
    end
    return W.flip
end
-- Field point (x, y) at height h -> UI pixels (jitter-free, so labels hold still).
function W.project(x, y, h)
    local vp = W.vp or cam:get_view_projection()
    local c = vp * vec4(x, h or 0, -y, 1)
    if c.w <= 1e-5 then return nil end
    local sw, sh = W.screen_size()
    local nx, ny = c.x / c.w - (W.jx or 0), c.y / c.w - (W.jy or 0)
    return (nx * 0.5 + 0.5) * sw, (flip() and (0.5 - ny * 0.5) or (0.5 + ny * 0.5)) * sh
end
function W.plane_project(x, h) return W.project(x, PY, h) end
-- UI pixels -> the kite plane (x, h), by meeting the mouse ray with it.
function W.plane_point(mx, my)
    local inv = W.inv or cam:get_inv_view_projection()
    local sw, sh = W.screen_size()
    local nx = mx / sw * 2 - 1 + (W.jx or 0)
    local ny = (flip() and (1 - my / sh * 2) or (my / sh * 2 - 1)) + (W.jy or 0)
    local a, b = inv * vec4(nx, ny, 0.25, 1), inv * vec4(nx, ny, 0.75, 1)
    local ax, ay, az = a.x / a.w, a.y / a.w, a.z / a.w
    local bx, by, bz = b.x / b.w, b.y / b.w, b.z / b.w
    if abs(bz - az) < 1e-6 then return nil end
    local t = (-PY - az) / (bz - az)
    return ax + (bx - ax) * t, ay + (by - ay) * t
end
function W.shake(a) S.shake = max(S.shake, a * (W.shake_scale and W.shake_scale() or 1)) end
return W
end
