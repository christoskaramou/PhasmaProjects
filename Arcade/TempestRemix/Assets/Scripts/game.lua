-- TEMPEST REMIX  (PhasmaEngine, Lua)
-- Modern remake of Atari's Tempest (1981). Tube shooter: claw crawls the near rim,
-- flippers / tankers / spikers / fuseballs / pulsars climb out of the web.
-- Visuals first: cooked claw + enemy meshes, glowing rail web, particles, dynamic lights,
-- TAA + soft bloom (see /workspace/games/common/RENDER_SETTINGS.md).
local PI, TAU = math.pi, math.pi * 2
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 =
    math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local function ang_diff(a, b) return (b - a + PI) % TAU - PI end
local function wrap01(x) return x - floor(x) end

local G = { state = "boot", t = 0, score = 0, hiscore = 20000, lives = 3, level = 1, pscale = 1 }
_G.TX = G

------------------------------------------------------------------ deferred materials
local _mset, _mds = material.set, material.set_double_sided
local mat_q = {}
local function qpush(f) mat_q[#mat_q + 1] = { f = f, n = 0 } end
local function mset(n, k, v) pcall(_mset, n, k, v); qpush(function() pcall(_mset, n, k, v) end) end
local function flush_mats()
    for i = #mat_q, 1, -1 do
        local q = mat_q[i]; q.n = q.n + 1
        if q.n == 2 or q.n == 6 then q.f() end
        if q.n >= 6 then table.remove(mat_q, i) end
    end
end
local function paint(n, base, emis, rough, metal)
    if not n then return end
    mset(n, "base_color", vec4(base[1], base[2], base[3], base[4] or 1))
    mset(n, "emissive", vec3(emis[1], emis[2], emis[3]))
    mset(n, "roughness", rough or 0.3)
    mset(n, "metallic", metal or 0.15)
end
local function sfx(name) pcall(audio.play, name .. ".wav") end

------------------------------------------------------------------ render (TAA + soft bloom)
local function S(k, v) pcall(settings.set, k, v) end
local ss = scene.add_empty_node("TempestSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "void.hdr")
S("taa", true); S("cas_sharpening", false)
S("motion_blur", false); S("hdr", true)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.4)
S("tonemapping", true); S("fxaa", false)
S("ssao", false); S("ssr", false); S("dof", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0)
S("IBL", true); S("IBL_intensity", 0.55)
S("color_grading", true); S("color_grading_saturation", 1.18); S("color_grading_contrast", 1.1)

------------------------------------------------------------------ camera / playfield
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1280, surf.height or 720
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local FOVX = 0.95
local Z_NEAR, Z_FAR = 0.0, 28.0
local TUBE_R = 7.2
local CAM = { z = -11.5, y = 0.4 }
-- fit the whole near rim (radius TUBE_R) on screen, like the arcade view
local function cam_fit()
    local aspect = SW / math.max(SH, 1)
    local fovy = 2 * math.atan(math.tan(FOVX * 0.5) / aspect)
    local need = (TUBE_R + 1.6) / math.tan(fovy * 0.5)
    CAM.z = -need
end
cam_fit()
pcall(function() cam:set_fov(math.deg(FOVX)) end)
cam:set_position(vec3(0, CAM.y, CAM.z)); cam:look_at(vec3(0, 0, 10))

------------------------------------------------------------------ templates -> clones
local TPL, seq = {}, 0
local HIDE = vec3(0, -1000, 0)
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[Tempest] missing template " .. name); return nil end
    TPL[name] = { node = n, mesh = n:get_mesh_refs()[1] }
    return TPL[name]
end
local function clone(name, pos, scale, parent)
    local t = tpl(name); seq = seq + 1
    local n = scene.add_empty_node(name .. "_c" .. seq)
    if t and t.mesh then n:add_mesh_ref(t.mesh) end
    if parent then n:set_parent(parent) end
    n:set_position(pos or HIDE)
    if scale then n:set_scale(type(scale) == "number" and vec3(scale, scale, scale) or scale) end
    return n
end
local function tnode(name) local t = tpl(name); return t and t.node end

------------------------------------------------------------------ palette
local COL = {
    claw = {
        body  = { { 0.95, 0.92, 0.85 }, { 0.35, 0.22, 0.05 }, 0.28, 0.45 },
        prong = { { 0.9, 0.55, 0.12 }, { 1.6, 0.55, 0.08 }, 0.25, 0.35 },
        glow  = { { 1.0, 0.75, 0.25 }, { 4.0, 2.2, 0.4 }, 0.2, 0 },
        metal = { { 0.35, 0.4, 0.48 }, { 0.05, 0.08, 0.12 }, 0.22, 0.85 },
    },
    flipper = {
        body = { { 0.95, 0.2, 0.55 }, { 4.5, 0.4, 1.8 }, 0.28, 0.2 },
        edge = { { 1.0, 0.85, 0.3 }, { 6.0, 3.5, 0.5 }, 0.2, 0.1 },
    },
    tanker = {
        body  = { { 0.2, 0.75, 0.95 }, { 0.4, 3.0, 5.0 }, 0.25, 0.35 },
        armor = { { 0.85, 0.9, 1.0 }, { 2.0, 3.0, 5.0 }, 0.2, 0.7 },
    },
    spiker = {
        body = { { 0.95, 0.85, 0.2 }, { 5.0, 3.5, 0.4 }, 0.3, 0.15 },
        ring = { { 1.0, 0.4, 0.1 }, { 5.5, 1.5, 0.3 }, 0.25, 0.2 },
    },
    fuseball = {
        core    = { { 0.7, 0.3, 1.0 }, { 4.5, 1.2, 7.0 }, 0.15, 0.1 },
        tendril = { { 1.0, 0.5, 1.0 }, { 6.0, 2.0, 7.0 }, 0.2, 0 },
    },
    pulsar = {
        body = { { 0.3, 1.0, 0.55 }, { 0.6, 5.0, 2.2 }, 0.25, 0.2 },
        glow = { { 0.7, 1.0, 0.85 }, { 2.5, 7.0, 4.0 }, 0.15, 0 },
    },
}
local function paint_templates()
    for kind, parts in pairs(COL) do
        for part, p in pairs(parts) do
            local names = { "T_" .. kind .. "_" .. part }
            if part == "prong" then names[2] = "T_claw_prongR" end
            for _, nm in ipairs(names) do
                local n = tnode(nm)
                -- emissive scaled down: the old 4-7x values clipped every ship to white under bloom
                local k = (kind == "claw") and 0.75 or 0.32
                if n then paint(n, p[1], { p[2][1] * k, p[2][2] * k, p[2][3] * k }, p[3], p[4]) end
            end
        end
    end
    paint(tnode("T_bolt"), { 1.0, 0.9, 0.4 }, { 3.0, 2.2, 0.5 }, 0.2, 0)
    paint(tnode("T_spike"), { 1.0, 0.55, 0.15 }, { 3.0, 1.2, 0.2 }, 0.25, 0.1)
    paint(tnode("T_hub"), { 0.15, 0.55, 0.85 }, { 0.4, 1.6, 3.2 }, 0.3, 0.4)
    paint(tnode("T_hub2"), { 0.9, 0.45, 0.15 }, { 2.5, 1.0, 0.25 }, 0.25, 0.3)
    for i = 0, 179 do
        paint(tnode("T_rail_" .. i), { 0.12, 0.45, 0.75 }, { 0.25, 1.1, 2.4 }, 0.25, 0.5)
        paint(tnode("T_railg_" .. i), { 0.5, 0.9, 1.0 }, { 1.2, 3.0, 5.0 }, 0.2, 0)
    end
    for i = 0, 95 do
        paint(tnode("T_node_" .. i), { 0.7, 0.95, 1.0 }, { 1.5, 3.2, 5.0 }, 0.2, 0.2)
    end
    for i = 0, 11 do paint(tnode("T_shard_" .. i), { 1, 0.6, 0.2 }, { 4, 2, 0.4 }, 0.3, 0) end
    for i = 0, 9 do paint(tnode("T_ring_" .. i), { 0.6, 0.9, 1 }, { 1.5, 3, 5 }, 0.25, 0) end
    for i = 0, 7 do paint(tnode("T_orb_" .. i), { 1, 0.5, 0.2 }, { 2, 0.8, 0.2 }, 0.2, 0) end
    for i = 0, 7 do paint(tnode("T_bolt_" .. i), { 1.0, 0.85, 0.3 }, { 4.5, 3.0, 0.6 }, 0.2, 0) end
    for i = 0, 15 do paint(tnode("T_spike_" .. i), { 1.0, 0.5, 0.12 }, { 2.8, 1.0, 0.15 }, 0.25, 0.1) end
end

------------------------------------------------------------------ lights
local function add_point() lights.add_point(); return #lights.get_point_lights() - 1 end
local LNODE = {}
local LIGHT_GAIN = 0.14
local function set_point(i, pos, col, inten, rad)
    pcall(lights.set_point_light, i, pos, col, inten * LIGHT_GAIN, rad)
    local n = LNODE[i]
    if n == nil then
        local ok, list = pcall(lights.get_point_lights)
        if ok and list and list[i + 1] then
            n = scene.find_model(list[i + 1].name); LNODE[i] = n or false
        end
    end
    if n then n:set_position(pos) end
end
local L = {
    rim = add_point(), hub = add_point(), claw = add_point(),
    shot = add_point(), zap = add_point(), fx = add_point(),
}

------------------------------------------------------------------ particles
local PSCALE = 1
local function burst(x, y, z, o)
    o = o or {}
    local c = floor((o.count or 18) * PSCALE)
    if c < 1 then return end
    pcall(particles.emit_burst, {
        position = vec3(x, y, z or 0),
        velocity = o.vel or vec3(0, 0, 0),
        color_start = o.c0 or vec4(1, 0.7, 0.2, 1),
        color_end = o.c1 or vec4(0.3, 0.1, 0.05, 0),
        count = c, size_min = o.smin or 0.05, size_max = o.smax or 0.14,
        life_min = o.lmin or 0.2, life_max = o.lmax or 0.55,
        spawn_radius = o.radius or 0.15, velocity_strength = o.spread or 6,
        drag = o.drag or 1.2, gravity = o.grav or vec3(0, 0, 0), cleanup_delay = 2.0,
    })
end
local function new_emitter(o)
    local ok, e = pcall(particles.add_emitter, {
        max_particles = o.count or 300,
        spawn_rate = 0, spawn_radius = o.radius or 0.1,
        size_min = o.smin or 0.05, size_max = o.smax or 0.12,
        life_min = o.lmin or 0.2, life_max = o.lmax or 0.5,
        color_start = o.c0 or vec4(1, 1, 1, 1), color_end = o.c1 or vec4(0, 0, 0, 0),
        velocity = o.vel or vec3(0, 0, 0), drag = o.drag or 1.0,
        noise_strength = o.noise or 0.5, gravity = o.grav or vec3(0, 0, 0),
    })
    return ok and e or nil
end
local function emitter_at(e, x, y, z, rate, vel)
    if not e then return end
    pcall(particles.set_emitter, e, "position", vec3(x, y, z or 0))
    pcall(particles.set_emitter, e, "spawn_rate", rate * PSCALE)
    if vel then pcall(particles.set_emitter, e, "velocity", vel) end
end

------------------------------------------------------------------ tube shapes
-- Each shape: list of 2D rim points (unit circle-ish), closed. Lane count = #pts.
local function poly_reg(n, r, rot)
    local pts = {}
    for i = 0, n - 1 do
        local a = rot + TAU * i / n
        pts[#pts + 1] = { cos(a) * r, sin(a) * r }
    end
    return pts
end
local function poly_plus()
    -- cross / plus silhouette (12 verts)
    local a, b = 1.0, 0.38
    return {
        { a, b }, { b, b }, { b, a }, { -b, a }, { -b, b }, { -a, b },
        { -a, -b }, { -b, -b }, { -b, -a }, { b, -a }, { b, -b }, { a, -b },
    }
end
local function poly_star(n, r0, r1)
    local pts = {}
    for i = 0, n * 2 - 1 do
        local a = -PI / 2 + TAU * i / (n * 2)
        local r = (i % 2 == 0) and r0 or r1
        pts[#pts + 1] = { cos(a) * r, sin(a) * r }
    end
    return pts
end
local function poly_clover()
    local pts = {}
    for i = 0, 23 do
        local a = TAU * i / 24
        local r = 0.72 + 0.28 * abs(sin(a * 2))
        pts[#pts + 1] = { cos(a) * r, sin(a) * r }
    end
    return pts
end
-- Every web gets the same 16 lanes (as in the arcade original) so claw speed, flipper flips and
-- spawn spacing feel identical on every shape.  Polygons keep their corners: each edge gets a
-- share of the 16 lanes proportional to its length; smooth/dense outlines are resampled by arc length.
local LANES = 16
local function relane(pts)
    local n = #pts
    local L, tot = {}, 0
    for i = 1, n do
        local a, b = pts[i], pts[i % n + 1]
        L[i] = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2); tot = tot + L[i]
    end
    local out = {}
    if n >= LANES then
        local step, acc, i, k = tot / LANES, 0, 1, 0
        for s = 0, LANES - 1 do
            local want = s * step
            while acc + L[i] < want - 1e-9 do acc = acc + L[i]; i = i + 1 end
            local f = (want - acc) / L[i]
            local a, b = pts[i], pts[i % n + 1]
            out[#out + 1] = { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f }
        end
        return out
    end
    local seg, used, rem = {}, 0, {}
    for i = 1, n do
        local q = LANES * L[i] / tot
        seg[i] = math.max(1, floor(q)); used = used + seg[i]; rem[i] = q - floor(q)
    end
    while used < LANES do
        local bi, bv = 1, -1
        for i = 1, n do if rem[i] > bv then bi, bv = i, rem[i] end end
        seg[bi] = seg[bi] + 1; rem[bi] = -1; used = used + 1
    end
    for i = 1, n do
        local a, b = pts[i], pts[i % n + 1]
        for k = 0, seg[i] - 1 do
            local f = k / seg[i]
            out[#out + 1] = { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f }
        end
    end
    return out
end
local SHAPES = {
    { name = "CIRCLE",   pts = poly_reg(16, 1, 0) },
    { name = "SQUARE",   pts = poly_reg(4, 1.05, PI / 4) },
    { name = "PLUS",     pts = poly_plus() },
    { name = "TRIANGLE", pts = poly_reg(3, 1.15, -PI / 2) },
    { name = "HEXAGON",  pts = poly_reg(6, 1.05, 0) },
    { name = "STAR",     pts = poly_star(8, 1.15, 0.55) },
    { name = "CLOVER",   pts = poly_clover() },
    { name = "OCTAGON",  pts = poly_reg(8, 1.05, PI / 8) },
}
local LEVEL_TINT = {
    { 0.2, 0.7, 1.0 }, { 1.0, 0.45, 0.15 }, { 0.4, 1.0, 0.55 }, { 0.85, 0.35, 1.0 },
    { 1.0, 0.85, 0.25 }, { 0.3, 0.95, 0.95 }, { 1.0, 0.3, 0.45 }, { 0.55, 0.75, 1.0 },
}

local TUBE = { pts = {}, n = 0, rails = {}, nodes = {}, hub = nil, hub2 = nil, tint = LEVEL_TINT[1] }
local DEPTH_RINGS = 5

local function rim_point(lane, depth)
    -- lane in [0, n) continuous; depth 0=near .. 1=far
    local n = TUBE.n
    local i0 = floor(lane) % n
    local i1 = (i0 + 1) % n
    local f = lane - floor(lane)
    local p0, p1 = TUBE.pts[i0 + 1], TUBE.pts[i1 + 1]
    local x = lerp(p0[1], p1[1], f) * TUBE_R
    local y = lerp(p0[2], p1[2], f) * TUBE_R
    local z = lerp(Z_NEAR, Z_FAR, depth)
    -- slight inward taper at far end for dramatic foreshortening
    local taper = lerp(1.0, 0.42, depth)
    return x * taper, y * taper, z
end

local function lane_tangent(lane)
    local x0, y0 = rim_point(lane, 0)
    local x1, y1 = rim_point(lane + 0.02, 0)
    local dx, dy = x1 - x0, y1 - y0
    local l = sqrt(dx * dx + dy * dy) + 1e-6
    return dx / l, dy / l
end

local function lane_normal(lane)
    local x, y = rim_point(lane, 0)
    local l = sqrt(x * x + y * y) + 1e-6
    return x / l, y / l  -- outward
end

local function place_rail(node, x0, y0, z0, x1, y1, z1, thick)
    local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
    local len = sqrt(dx * dx + dy * dy + dz * dz) + 1e-6
    local mx, my, mz = (x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5
    -- rail mesh is along +X from 0..1; scale X = len, then rotate
    local yaw = atan2(dy, dx)                 -- around Z
    local pitch = -atan2(dz, sqrt(dx * dx + dy * dy) + 1e-6)  -- around Y after yaw... use euler carefully
    -- Simpler: set position at start, scale, rotation from direction
    node:set_position(vec3(x0, y0, z0))
    node:set_scale(vec3(len, thick or 1, thick or 1))
    -- euler: pitch (X), yaw (Y), roll (Z). Our rail along +X.
    -- Rotate so +X aligns with (dx,dy,dz):
    local yaw_y = atan2(dx, dz)  -- hmm
    -- Use look-style: roll around Z for XY, then pitch for Z
    local az = atan2(dy, dx)
    local el = atan2(dz, sqrt(dx * dx + dy * dy))
    node:set_rotation(vec3(0, -el * 180 / PI, az * 180 / PI))
end

local function build_tube_pool()
    TUBE.rails, TUBE.glows, TUBE.nodes = {}, {}, {}
    for i = 0, 179 do
        TUBE.rails[i + 1] = clone("T_rail_" .. i, HIDE, 1)
        TUBE.glows[i + 1] = clone("T_railg_" .. i, HIDE, 1)
    end
    for i = 0, 95 do
        TUBE.nodes[i + 1] = clone("T_node_" .. i, HIDE, 1)
    end
    TUBE.hub = clone("T_hub", HIDE, 1)
    TUBE.hub2 = clone("T_hub2", HIDE, 1)
end

local function hide_tube()
    for _, n in ipairs(TUBE.rails) do n:set_position(HIDE) end
    for _, n in ipairs(TUBE.glows) do n:set_position(HIDE) end
    for _, n in ipairs(TUBE.nodes) do n:set_position(HIDE) end
    if TUBE.hub then TUBE.hub:set_position(HIDE) end
    if TUBE.hub2 then TUBE.hub2:set_position(HIDE) end
end

local function apply_tube_tint(tint)
    TUBE.tint = tint
    for i = 0, 179 do
        local n = tnode("T_rail_" .. i)
        if n then
            pcall(_mset, n, "emissive", vec3(tint[1] * 1.4, tint[2] * 1.4, tint[3] * 1.8))
            pcall(_mset, n, "base_color", vec4(tint[1] * 0.25, tint[2] * 0.35, tint[3] * 0.45, 1))
        end
        local g = tnode("T_railg_" .. i)
        if g then
            pcall(_mset, g, "emissive", vec3(tint[1] * 2.5, tint[2] * 2.8, tint[3] * 3.5))
        end
    end
    for i = 0, 95 do
        local n = tnode("T_node_" .. i)
        if n then pcall(_mset, n, "emissive", vec3(tint[1] * 2.2, tint[2] * 2.5, tint[3] * 3.2)) end
    end
end

local function set_shape(shape_idx)
    local sh = SHAPES[((shape_idx - 1) % #SHAPES) + 1]
    sh.lanes = sh.lanes or relane(sh.pts)
    TUBE.pts = sh.lanes
    TUBE.n = #sh.lanes
    TUBE.name = sh.name
    hide_tube()
    local ri, ni = 1, 1
    -- longitudinal rails (along depth) at each vertex
    for i = 0, TUBE.n - 1 do
        for r = 0, DEPTH_RINGS - 2 do
            if ri > #TUBE.rails then break end
            local d0, d1 = r / (DEPTH_RINGS - 1), (r + 1) / (DEPTH_RINGS - 1)
            local x0, y0, z0 = rim_point(i, d0)
            local x1, y1, z1 = rim_point(i, d1)
            place_rail(TUBE.rails[ri], x0, y0, z0, x1, y1, z1, 1.6)
            place_rail(TUBE.glows[ri], x0, y0, z0, x1, y1, z1, 1.1)
            ri = ri + 1
        end
    end
    -- circumferential rings at each depth
    for r = 0, DEPTH_RINGS - 1 do
        local d = r / (DEPTH_RINGS - 1)
        for i = 0, TUBE.n - 1 do
            if ri > #TUBE.rails then break end
            local x0, y0, z0 = rim_point(i, d)
            local x1, y1, z1 = rim_point((i + 1) % TUBE.n, d)
            place_rail(TUBE.rails[ri], x0, y0, z0, x1, y1, z1, 1.4)
            place_rail(TUBE.glows[ri], x0, y0, z0, x1, y1, z1, 1.0)
            ri = ri + 1
        end
        -- nodes at vertices
        for i = 0, TUBE.n - 1 do
            if ni > #TUBE.nodes then break end
            local x, y, z = rim_point(i, d)
            local sc = lerp(0.55, 0.22, d)
            TUBE.nodes[ni]:set_position(vec3(x, y, z))
            TUBE.nodes[ni]:set_scale(vec3(sc, sc, sc))
            ni = ni + 1
        end
    end
    -- far hub
    local hx, hy, hz = 0, 0, Z_FAR
    local hr = TUBE_R * 0.42
    TUBE.hub:set_position(vec3(hx, hy, hz))
    TUBE.hub:set_scale(vec3(hr, hr, hr))
    TUBE.hub:set_rotation(vec3(90, 0, 0))
    TUBE.hub2:set_position(vec3(hx, hy, hz - 0.15))
    TUBE.hub2:set_scale(vec3(hr * 0.55, hr * 0.55, hr * 0.55))
    TUBE.hub2:set_rotation(vec3(90, G.t * 20, 0))
    apply_tube_tint(LEVEL_TINT[((shape_idx - 1) % #LEVEL_TINT) + 1])
end

------------------------------------------------------------------ entities: player claw
local function make_claw()
    seq = seq + 1
    local root = scene.add_empty_node("claw_" .. seq)
    root:set_position(HIDE)
    local parts = {
        body = clone("T_claw_body", vec3(0, 0, 0), 1, root),
        prong = clone("T_claw_prong", vec3(0, 0, 0), 1, root),
        prongR = clone("T_claw_prongR", vec3(0, 0, 0), 1, root),
        glow = clone("T_claw_glow", vec3(0, 0, 0), 1, root),
        metal = clone("T_claw_metal", vec3(0, 0, 0), 1, root),
    }
    parts.halo = clone("T_orb_0", vec3(0, 0.15, 0), 0.22, root)
    return { root = root, parts = parts, vis = true }
end

local function make_enemy_ship(kind)
    seq = seq + 1
    local root = scene.add_empty_node(kind .. "_" .. seq)
    root:set_position(HIDE)
    local parts = {}
    local list = ({
        flipper = { "body", "edge" },
        tanker = { "body", "armor" },
        spiker = { "body", "ring" },
        fuseball = { "core", "tendril" },
        pulsar = { "body", "glow" },
    })[kind]
    for _, p in ipairs(list) do
        parts[p] = clone("T_" .. kind .. "_" .. p, vec3(0, 0, 0), 1, root)
    end
    -- bright halo so silhouettes read at a distance on lavapipe
    -- (no bright halo orb: it washed every enemy out into a white blob and hid its shape)
    return { root = root, parts = parts, kind = kind, vis = true }
end

local function orient_on_rim(node, lane, depth, face_in, scale, spin)
    lane = lane + 0.5
    local x, y, z = rim_point(lane, depth)
    local nx, ny = lane_normal(lane)
    -- sit slightly inside the web
    local inset = face_in and 0.55 or 0.0
    local taper = lerp(1.0, 0.42, depth)
    x = x - nx * inset * taper
    y = y - ny * inset * taper
    node:set_position(vec3(x, y, z))
    local ang = atan2(ny, nx) * 180 / PI
    local roll = ang + 180
    -- tip toward camera so the silhouette reads against the web (pitch on X)
    local tip = -25
    node:set_rotation(vec3(tip + (spin or 0), 0, roll))
    if scale then node:set_scale(vec3(scale, scale, scale)) end
    return x, y, z
end

------------------------------------------------------------------ pools
local PL = { lane = 0, v = 0, claw = nil, fire_cd = 0, inv = 0, zap_ready = true, zap_t = 0, em = nil }
local enemies, shots, spikes, FX = {}, {}, {}, {}
local POOL_E = { flipper = {}, tanker = {}, spiker = {}, fuseball = {}, pulsar = {} }

local function acquire(kind)
    local pool = POOL_E[kind]
    local s = table.remove(pool)
    if not s then s = make_enemy_ship(kind) end
    s.alive = true
    return s
end
local function release(e)
    if not e or not e.ship then return end
    e.ship.root:set_position(HIDE)
    e.ship.alive = false
    POOL_E[e.kind][#POOL_E[e.kind] + 1] = e.ship
    e.ship = nil
end

------------------------------------------------------------------ shots / spikes
local BOLTS, SPIKE_POOL = {}, {}
local function build_bolts()
    for i = 1, 10 do
        BOLTS[i] = { node = clone("T_bolt_" .. ((i - 1) % 8), HIDE), used = false }
    end
    for i = 1, 24 do
        SPIKE_POOL[i] = { node = clone("T_spike_" .. ((i - 1) % 16), HIDE), used = false }
    end
end

local function fire_shot()
    for _, b in ipairs(BOLTS) do
        if not b.used then
            b.used, b.lane, b.depth, b.spd = true, floor(PL.lane + 0.5) % TUBE.n, 0.02, 1.55
            sfx("shoot")
            local x, y, z = rim_point(b.lane + 0.5, b.depth)
            burst(x, y, z, { c0 = vec4(2, 1.5, 0.4, 1), c1 = vec4(0.5, 0.2, 0.05, 0),
                count = 8, smin = 0.04, smax = 0.1, lmin = 0.08, lmax = 0.2, radius = 0.08, spread = 4,
                vel = vec3(0, 0, 8) })
            return true
        end
    end
    return false
end

local function plant_spike(lane, depth)
    for _, s in ipairs(SPIKE_POOL) do
        if not s.used then
            s.used, s.lane, s.depth = true, lane % TUBE.n, depth
            sfx("spike")
            return s
        end
    end
end

------------------------------------------------------------------ scoring / lives
local HISAVE = "Save/hiscore.txt"
do local ok, s = pcall(fs.read, HISAVE); local v = ok and s and tonumber(s); if v then G.hiscore = v end end
local jev
local function save_hi()
    if jev and jev:assisted() then return end
    if G.score > G.hiscore then G.hiscore = G.score; G.newhi = true end
    pcall(fs.write, HISAVE, tostring(G.hiscore))
end
local function add_score(n)
    local before = G.score
    G.score = G.score + n
    local nxt = G.next_extra or 20000
    if before < nxt and G.score >= nxt then
        G.lives = min(6, G.lives + 1); sfx("extra"); G.next_extra = nxt + 20000
        G.banner = { text = "EXTRA CLAW", sub = "", t = 0, dur = 1.6 }
    end
end

------------------------------------------------------------------ spawn logic
local function clear_enemies()
    for i = #enemies, 1, -1 do release(enemies[i]); enemies[i] = nil end
    for i = #enemies, 1, -1 do table.remove(enemies, i) end
    for _, b in ipairs(BOLTS) do b.used = false; b.node:set_position(HIDE) end
    for _, s in ipairs(SPIKE_POOL) do s.used = false; s.node:set_position(HIDE) end
end

local function spawn_enemy(kind, lane, depth)
    local ship = acquire(kind)
    local e = {
        kind = kind, ship = ship, lane = lane % TUBE.n, depth = depth or 1.0,
        alive = true, t = 0, flip_cd = rr(0.4, 1.2), state = "crawl",
        spd = 0.115 + min(0.07, (G.level - 1) * 0.006),   -- gentle ramp: +60% max, reached at level ~13
        pulse = 0, open = false,
    }
    if kind == "tanker" then e.spd = e.spd * 0.75 end
    if kind == "spiker" then e.spd = e.spd * 0.55; e.planted = false; e.retreat = false end
    if kind == "fuseball" then e.spd = e.spd * 0.9; e.rail = true; e.lane = e.lane + 0.5 end
    if kind == "pulsar" then e.spd = e.spd * 0.5; e.width = 1.0 end
    enemies[#enemies + 1] = e
    sfx("spawn")
    return e
end

local function wave_plan(level)
    -- returns list of {kind, delay, lane}
    local plan = {}
    local n = TUBE.n
    local function add(kind, delay, lane)
        plan[#plan + 1] = { kind = kind, delay = delay, lane = lane % n }
    end
    local base = 4 + min(10, level)
    for i = 1, base do
        add("flipper", 0.35 * i, floor(rr(0, n)))
    end
    local tanks = min(4, 1 + floor(level / 2))
    for i = 1, tanks do add("tanker", 1.0 + 0.5 * i, floor(i * n / (tanks + 1))) end
    if level >= 2 then
        for i = 1, min(3, floor(level / 2)) do
            add("spiker", 2.0 + 0.7 * i, floor(rr(0, n)))
        end
    end
    if level >= 3 then
        for i = 1, min(3, floor(level / 3)) do
            add("fuseball", 2.5 + 0.8 * i, floor(rr(0, n)))
        end
    end
    if level >= 4 then
        for i = 1, min(2, floor(level / 4)) do
            add("pulsar", 3.0 + i, floor(rr(0, n)))
        end
    end
    return plan
end

local SPAWN = { plan = {}, t = 0, done = false }

local function start_level(level)
    G.level = level
    set_shape(level)
    clear_enemies()
    SPAWN.plan = wave_plan(level)
    SPAWN.t = 0
    SPAWN.done = false
    PL.zap_ready = true
    PL.inv = 1.5
    G.banner = { text = "LEVEL " .. level, sub = TUBE.name, t = 0, dur = 1.2 }
    sfx("start")
end

------------------------------------------------------------------ combat helpers
local function kill_enemy(e, scored)
    if not e.alive then return end
    e.alive = false
    local x, y, z = rim_point(e.lane + 0.5, e.depth)
    local rgb = ({
        flipper = {2, 0.4, 1.2}, tanker = {0.4, 1.5, 2.5}, spiker = {2.5, 1.8, 0.3},
        fuseball = {2, 0.6, 3}, pulsar = {0.5, 2.5, 1.2},
    })[e.kind] or {1, 1, 1}
    burst(x, y, z, { c0 = vec4(rgb[1], rgb[2], rgb[3], 1), c1 = vec4(rgb[1]*0.2, rgb[2]*0.15, rgb[3]*0.15, 0),
        count = 28, smin = 0.06, smax = 0.18, lmin = 0.25, lmax = 0.6, radius = 0.25, spread = 9, vel = vec3(0, 0, -2) })
    burst(x, y, z, { c0 = vec4(2, 2, 2, 1), c1 = vec4(0.5, 0.5, 0.5, 0), count = 10,
        smin = 0.03, smax = 0.08, lmin = 0.15, lmax = 0.35, radius = 0.1, spread = 5 })
    set_point(L.fx, vec3(x, y, z), vec3(rgb[1], rgb[2], rgb[3]), 90, 8)
    -- shock ring
    FX[#FX + 1] = { kind = "ring", node = clone("T_ring_" .. (#FX % 10), vec3(x, y, z), 0.3),
        t = 0, life = 0.45, x = x, y = y, z = z }
    if scored then
        local pts = ({ flipper = 150, tanker = 100, spiker = 50, fuseball = 250, pulsar = 200 })[e.kind] or 50
        if e.kind == "fuseball" then pts = floor(250 + 500 * (1 - e.depth)) end
        if e.kind == "spiker" then pts = pts + floor(100 * (1 - e.depth)) end
        add_score(pts)
    end
    sfx(e.kind == "tanker" and "hit" or "boom")
    if e.kind == "tanker" and scored then
        -- split into two flippers on adjacent lanes
        local a = spawn_enemy("flipper", e.lane, e.depth)
        local b = spawn_enemy("flipper", e.lane + 1, e.depth)
        a.depth = clamp(e.depth + 0.02, 0, 1); b.depth = clamp(e.depth - 0.02, 0, 1)
    end
    release(e)
end

local function superzap()
    if not PL.zap_ready then return end
    PL.zap_ready = false
    PL.zap_t = 0.8
    sfx("zap")
    set_point(L.zap, vec3(0, 0, 8), vec3(0.4, 0.9, 1.5), 200, 30)
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        if e.alive then kill_enemy(e, true) end
    end
    -- wipe spikes
    for _, s in ipairs(SPIKE_POOL) do
        if s.used then
            local x, y, z = rim_point(s.lane, s.depth)
            burst(x, y, z, { c0 = vec4(2, 1, 0.3, 1), c1 = vec4(0.3, 0.1, 0, 0), count = 12,
                smin = 0.04, smax = 0.1, radius = 0.1, spread = 5 })
            s.used = false; s.node:set_position(HIDE)
        end
    end
    G.shake = (G.shake or 0) + 0.6
end

------------------------------------------------------------------ update entities
local function update_shots(dt)
    for _, b in ipairs(BOLTS) do
        if b.used then
            b.depth = b.depth + b.spd * dt
            if b.depth >= 1.05 then
                b.used = false; b.node:set_position(HIDE)
            else
                local x, y, z = rim_point(b.lane + 0.5, b.depth)
                b.node:set_position(vec3(x, y, z))
                local sc = lerp(1.5, 0.55, b.depth)
                b.node:set_scale(vec3(sc, sc, sc * 1.4))
                -- hit enemies
                for i = #enemies, 1, -1 do
                    local e = enemies[i]
                    if e.alive then
                        local dl = abs(ang_diff(e.lane / TUBE.n * TAU, b.lane / TUBE.n * TAU)) * TUBE.n / TAU
                        -- lane distance in lane units
                        local lane_dist = abs((e.lane - b.lane + TUBE.n * 0.5) % TUBE.n - TUBE.n * 0.5)
                        local need = (e.kind == "pulsar" and e.open) and 1.2 or (e.kind == "fuseball" and 0.55 or 0.65)
                        local d0 = b.depth - b.spd * dt - 0.03
                        if lane_dist < need and e.depth >= d0 and e.depth <= b.depth + 0.04 then
                            b.used = false; b.node:set_position(HIDE)
                            kill_enemy(e, true)
                            break
                        end
                    end
                end
                -- hit spikes (destroy tip)
                for _, s in ipairs(SPIKE_POOL) do
                    if s.used then
                        local lane_dist = abs((s.lane - b.lane + TUBE.n * 0.5) % TUBE.n - TUBE.n * 0.5)
                        if lane_dist < 0.4 and s.depth >= b.depth - b.spd * dt - 0.03 and s.depth <= b.depth + 0.03 then
                            b.used = false; b.node:set_position(HIDE)
                            s.depth = s.depth + 0.04
                            if s.depth > 0.98 then
                                s.used = false; s.node:set_position(HIDE)
                                add_score(10); sfx("hit")
                            end
                            break
                        end
                    end
                end
            end
        end
    end
end

local function update_spikes(dt)
    for _, s in ipairs(SPIKE_POOL) do
        if s.used then
            local x, y, z = rim_point(s.lane + 0.5, s.depth)
            local nx, ny = lane_normal(s.lane + 0.5)
            -- spike points inward/along depth: orient along -radial-ish, scale by remaining length toward near
            local len = max(0.15, s.depth)  -- visual length cue
            s.node:set_position(vec3(x - nx * 0.15, y - ny * 0.15, z))
            local ang = atan2(ny, nx) * 180 / PI + 180
            s.node:set_rotation(vec3(90, 0, ang))
            local sc = lerp(0.7, 0.3, s.depth)
            s.node:set_scale(vec3(sc, sc * (0.5 + s.depth), sc))
        end
    end
end

local function update_enemies(dt)
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        if not e.alive then table.remove(enemies, i)
        else
            e.t = e.t + dt
            if e.kind == "flipper" then
                e.depth = e.depth - e.spd * dt
                e.flip_cd = e.flip_cd - dt
                if e.flip_cd <= 0 and e.depth > 0.02 then
                    e.lane = (e.lane + (rand() < 0.5 and 1 or -1)) % TUBE.n
                    e.flip_cd = rr(0.5, 1.2)
                    sfx("flip")
                end
            elseif e.kind == "tanker" then
                e.depth = e.depth - e.spd * dt
            elseif e.kind == "spiker" then
                if not e.retreat then
                    e.depth = e.depth - e.spd * dt
                    if e.depth < 0.35 and not e.planted then
                        plant_spike(floor(e.lane + 0.5), e.depth)
                        e.planted = true; e.retreat = true
                    end
                else
                    e.depth = e.depth + e.spd * 1.4 * dt
                    if e.depth >= 1.05 then kill_enemy(e, false) end
                end
            elseif e.kind == "fuseball" then
                e.depth = e.depth - e.spd * dt
                e.lane = e.lane + sin(e.t * 3.0) * 0.4 * dt
            elseif e.kind == "pulsar" then
                e.depth = e.depth - e.spd * dt
                e.pulse = e.pulse + dt
                e.open = (e.pulse % 1.4) < 0.7
            end
            if e.alive and e.depth <= 0.02 then
                -- reached near rim — lethal if near player
                local lane_dist = abs((e.lane - PL.lane + TUBE.n * 0.5) % TUBE.n - TUBE.n * 0.5)
                local lethal = true
                if e.kind == "pulsar" and not e.open then lethal = false end
                if lethal and lane_dist < (e.kind == "pulsar" and 1.2 or 0.75) and PL.inv <= 0 and G.state == "play" then
                    G.state = "dying"; G.die_t = 0; sfx("death")
                    local x, y, z = rim_point(PL.lane, 0)
                    burst(x, y, z, { c0 = vec4(2, 1.2, 0.3, 1), c1 = vec4(0.4, 0.1, 0, 0),
                        count = 40, smin = 0.08, smax = 0.22, lmin = 0.3, lmax = 0.8, radius = 0.4, spread = 12 })
                    G.shake = (G.shake or 0) + 0.9
                end
                if e.kind ~= "spiker" or not e.retreat then
                    -- on the rim: stay at depth 0 and flip one lane toward the player at a steady,
                    -- dt-based cadence (previously this re-flipped every few frames)
                    e.depth = 0
                    e.rim_cd = (e.rim_cd or 0.55) - dt
                    if e.rim_cd <= 0 then
                        local d = (PL.lane - e.lane + TUBE.n * 0.5) % TUBE.n - TUBE.n * 0.5
                        local s = d > 0 and 1 or -1
                        if abs(d) < 0.3 then s = rand() < 0.5 and 1 or -1 end
                        e.lane = (e.lane + s) % TUBE.n
                        e.rim_cd = max(0.4, 0.6 - G.level * 0.01)
                    end
                end
            end
            -- place mesh
            if e.alive and e.ship then
                local sc = lerp(2.3, 0.85, e.depth) * (e.kind == "tanker" and 1.4 or (e.kind == "fuseball" and 1.3 or (e.kind == "pulsar" and 1.2 or 1)))
                if e.kind == "pulsar" then
                    local x, y, z = rim_point(e.lane + 0.5, e.depth)
                    e.ship.root:set_position(vec3(x, y, z))
                    local nx, ny = lane_normal(e.lane + 0.5)
                    local ang = atan2(ny, nx) * 180 / PI + 180
                    local w = e.open and 1.3 or 0.45
                    e.ship.root:set_rotation(vec3(0, 0, ang))
                    e.ship.root:set_scale(vec3(w * sc, sc, sc))
                elseif e.kind == "fuseball" then
                    orient_on_rim(e.ship.root, e.lane, e.depth, true, sc * 0.85, e.t * 180)
                else
                    orient_on_rim(e.ship.root, e.lane, e.depth, true, sc, e.kind == "flipper" and sin(e.t * 8) * 25 or 0)
                end
            end
        end
    end
end

local function update_fx(dt)
    for i = #FX, 1, -1 do
        local f = FX[i]
        f.t = f.t + dt
        if f.t >= f.life then
            f.node:set_position(HIDE); table.remove(FX, i)
        else
            local u = f.t / f.life
            local sc = 0.3 + u * 2.5
            f.node:set_position(vec3(f.x, f.y, f.z))
            f.node:set_scale(vec3(sc, sc, sc * 0.3))
            f.node:set_rotation(vec3(90, u * 90, 0))
        end
    end
end

local function update_player(dt, move, fire, zap)
    PL.inv = max(0, PL.inv - dt)
    PL.fire_cd = max(0, PL.fire_cd - dt)
    PL.zap_t = max(0, PL.zap_t - dt)
    -- smooth lane movement (continuous)
    local accel = 16
    local maxv = 4.6 + min(0.6, (G.level - 1) * 0.05)   -- lanes/s (all webs have 16 lanes)
    if move ~= 0 then PL.v = damp(PL.v, move * maxv, accel, dt)
    else PL.v = damp(PL.v, 0, 14, dt) end
    PL.lane = (PL.lane + PL.v * dt) % TUBE.n
    -- place claw
    local bank = -PL.v * 4
    local x, y, z = orient_on_rim(PL.claw.root, PL.lane, 0.0, true, 1.55, bank)
    -- engine / rim trail
    emitter_at(PL.em, x, y, z + 0.2, 40 + abs(PL.v) * 8, vec3(0, 0, 2))
    set_point(L.claw, vec3(x, y, z), vec3(1.0, 0.55, 0.15), 55 + abs(PL.v) * 5, 6)
    if fire and PL.fire_cd <= 0 then
        if fire_shot() then PL.fire_cd = 0.11 end
    end
    if zap then superzap() end
    -- spike collision
    if PL.inv <= 0 and G.state == "play" then
        for _, s in ipairs(SPIKE_POOL) do
            if s.used and s.depth < 0.08 then
                local lane_dist = abs((s.lane - PL.lane + TUBE.n * 0.5) % TUBE.n - TUBE.n * 0.5)
                if lane_dist < 0.45 then
                    G.state = "dying"; G.die_t = 0; sfx("death")
                    burst(x, y, z, { c0 = vec4(2, 1, 0.2, 1), c1 = vec4(0.3, 0.05, 0, 0),
                        count = 35, radius = 0.35, spread = 10 })
                    G.shake = (G.shake or 0) + 0.8
                end
            end
        end
    end
end

------------------------------------------------------------------ UI
local HUD = "hud"
runtime_ui.show(HUD); runtime_ui.set_screen_overlay(HUD, true)
local NONE = { 0, 0, 0, 0 }
local AMBER = { 1.0, 0.72, 0.25, 1 }
local CYAN = { 0.35, 0.9, 1.0, 1 }
local MAG = { 0.95, 0.4, 0.85, 1 }
local WHITE = { 0.95, 0.96, 1.0, 1 }
local DIM = { 0.55, 0.7, 0.8, 0.85 }
local cache = {}
local function upd(id, key, q)
    if cache[id] == key then return end
    cache[id] = key
    runtime_ui.set_quad(HUD, id, q)
end
local function text(id, label, x, y, w, h, fs, col, align, vis)
    vis = vis ~= false
    local key = tostring(label) .. "|" .. floor(x) .. "|" .. floor(y) .. "|" .. tostring(vis) .. "|" .. string.format("%.2f|%.2f", col[4] or 1, fs) .. (col[1] or 0)
    upd(id, key, { x = x, y = y, w = w, h = h, z = 10, style = "text", label = label, fill = NONE, border = NONE,
        text_color = col, font_scale = fs, align_h = align or "center", align_v = "middle", no_input = true, visible = vis })
end
local function panel(id, x, y, w, h, vis, fill, border, z, input)
    vis = vis ~= false
    fill = fill or { 0.02, 0.04, 0.08, 0.72 }
    border = border or { 0.3, 0.75, 1.0, 0.55 }
    local key = floor(x) .. "|" .. floor(y) .. "|" .. floor(w) .. "|" .. floor(h) .. "|" .. tostring(vis) .. "|" .. table.concat(fill, ",")
    upd(id, key, { x = x, y = y, w = w, h = h, z = z or 5, style = "text", label = "", fill = fill, border = border,
        corner_radius = 14, no_input = not input, visible = vis })
end

local MENU = { items = {}, sel = 1, id = "" }
local function set_menu(id, items) MENU.id, MENU.items, MENU.sel = id, items, 1 end
local function draw_menu(vis, y0)
    local s = SH / 1080
    for i = 1, 4 do
        local it = MENU.items[i]
        local v = vis and it ~= nil
        local sel = v and MENU.sel == i
        local x, w, h = SW / 2 - 230 * s, 460 * s, 66 * s
        local y = y0 + (i - 1) * 80 * s
        panel("mi_bg" .. i, x, y, w, h, v,
            sel and { 0.15, 0.45, 0.7, 0.45 } or { 0.03, 0.06, 0.12, 0.6 },
            sel and { 0.5, 0.9, 1.0, 0.95 } or { 0.25, 0.55, 0.8, 0.45 }, 20, true)
        text("mi_tx" .. i, v and it.label or "", x, y, w, h, (sel and 1.7 or 1.5) * s,
            sel and WHITE or DIM, "center", v)
    end
end
local function ui_state(id) local ok, s = pcall(runtime_ui.get_state, HUD, id); if ok then return s end end
local function menu_input(pressed)
    if #MENU.items == 0 then return nil end
    for i = 1, #MENU.items do
        local st = ui_state("mi_bg" .. i)
        if st and st.hovered and (G.mouse_moved or false) then MENU.sel = i end
        if st and st.clicked then MENU.sel = i; return MENU.items[i].act end
    end
    if pressed("Up") or pressed("W") then MENU.sel = (MENU.sel - 2) % #MENU.items + 1; sfx("click") end
    if pressed("Down") or pressed("S") then MENU.sel = MENU.sel % #MENU.items + 1; sfx("click") end
    if pressed("Return") or pressed("Space") then return MENU.items[MENU.sel].act end
end

local function draw_hud(dt)
    local s = SH / 1080
    local st = G.state
    local play = (st == "play" or st == "paused" or st == "clear" or st == "over" or st == "dying" or st == "levelintro" or st == "warp")
    local title = st == "title"
    text("score", string.format("%06d", G.score), 36 * s, 16 * s, 360 * s, 54 * s, 1.7 * s, AMBER, "left", play or title)
    text("hiscore", "HI " .. string.format("%06d", G.hiscore), SW * 0.5 - 160 * s, 18 * s, 320 * s, 42 * s, 1.15 * s, CYAN, "center", play or title)
    text("lives", "CLAWS  " .. tostring(G.lives), SW - 340 * s, 16 * s, 300 * s, 50 * s, 1.35 * s, CYAN, "right", play)
    text("level", "LEVEL " .. G.level .. "  " .. (TUBE.name or ""), SW - 420 * s, 58 * s, 380 * s, 36 * s, 1.0 * s, DIM, "right", play)
    local zapcol = PL.zap_ready and { 0.4, 1.0, 0.7, 1 } or { 0.4, 0.4, 0.45, 0.6 }
    text("zap", PL.zap_ready and "SUPERZAPPER READY" or "SUPERZAPPER", SW * 0.5 - 200 * s, SH - 48 * s, 400 * s, 36 * s, 0.95 * s, zapcol, "center", play and st == "play")

    panel("tpanel", SW * 0.5 - 520 * s, SH * 0.07, 1040 * s, SH * 0.7, title,
        { 0.02, 0.04, 0.09, 0.68 }, { 0.35, 0.75, 1.0, 0.55 }, 4, false)
    local pulse = 0.55 + 0.1 * sin(G.t * 2.2)
    text("title", "T E M P E S T", 0, SH * 0.14, SW, 110 * s, 4.1 * s, AMBER, "center", title)
    text("title2", "REMIX", 0, SH * 0.24, SW, 80 * s, 2.9 * s, { pulse, 0.85, 1.0, 1 }, "center", title)
    text("tsub", "HIGH SCORE  " .. G.hiscore, 0, SH * 0.35, SW, 50 * s, 1.35 * s, CYAN, "center", title)
    text("thint", "A / D  or  ARROWS move   ·   SPACE / CLICK fire   ·   SHIFT zap", 0, SH * 0.86, SW, 40 * s, 0.95 * s, DIM, "center", title)

    local pause = st == "paused"
    local over = st == "over"
    panel("dim", 0, 0, SW, SH, pause or over, { 0, 0.02, 0.05, 0.55 }, NONE, 2, false)
    text("pause", "PAUSED", 0, SH * 0.25, SW, 120 * s, 4.0 * s, CYAN, "center", pause)
    text("over", "GAME  OVER", 0, SH * 0.22, SW, 140 * s, 4.5 * s, MAG, "center", over)
    text("over2", (G.newhi and "NEW HIGH SCORE  " or "FINAL SCORE  ") .. G.score, 0, SH * 0.36, SW, 70 * s, 1.8 * s, AMBER, "center", over)
    draw_menu(title or pause or over, title and SH * 0.46 or SH * 0.48)

    local ban = G.banner
    if ban then
        ban.t = ban.t + dt
        local bvis = ban.t < (ban.dur or 1.8)
        local ba = bvis and (1 - clamp(ban.t / (ban.dur or 1.8), 0, 1)) or 0
        text("ban1", ban.text or "", 0, SH * 0.40, SW, 90 * s, 3.0 * s, { AMBER[1], AMBER[2], AMBER[3], ba }, "center", bvis)
        text("ban2", ban.sub or "", 0, SH * 0.48, SW, 50 * s, 1.4 * s, { CYAN[1], CYAN[2], CYAN[3], ba * 0.9 }, "center", bvis)
        if not bvis then G.banner = nil end
    else
        text("ban1", "", 0, 0, 1, 1, 1, NONE, "center", false)
        text("ban2", "", 0, 0, 1, 1, 1, NONE, "center", false)
    end
end

------------------------------------------------------------------ settings
local SET = nil
do
    local src = fs.read("Scripts/Lib/settings_menu.lua")
    if src then
        local ok, mod = pcall(function() return load(src, "@settings_menu.lua")() end)
        if ok and mod then
            local ok2, s = pcall(mod.new, {
                title = "SETTINGS", file = "Save/settings.cfg",
                click = function() sfx("click") end, music = false,
                defaults = { master = 0.5 },
                theme = { accent = { 0.35, 0.85, 1.0, 1 }, accent2 = { 1.0, 0.55, 0.2, 1 } },
            })
            if ok2 then SET = s else pe_log("[Tempest] settings menu init failed: " .. tostring(s)) end
        else pe_log("[Tempest] settings menu load failed: " .. tostring(mod)) end
    end
end

------------------------------------------------------------------ input
local prev = {}
G.vkeys = {}
local function kdown(k) if G.vkeys[k] then return true end local ok, r = pcall(input.is_key_down_raw, k); return ok and r end
local function pressed(k)
    local d = kdown(k); local p = prev[k]; prev[k] = d
    return d and not p
end
local WATCH = { "Left", "Right", "A", "D", "Up", "Down", "W", "S", "Space", "Return", "Escape", "P", "M", "O",
    "LShift", "RShift", "X", "Z", "LControl", "RControl" }
local function latch() for _, k in ipairs(WATCH) do prev[k] = kdown(k) end end
local mouse_prev_down = false
local function mouse_clicked()
    local ok, d = pcall(input.is_left_mouse_down); d = ok and d
    local c = d and not mouse_prev_down; mouse_prev_down = d
    return c
end
local function mouse_down() local ok, d = pcall(input.is_left_mouse_down); return ok and d end

------------------------------------------------------------------ jev holds
-- Hardware edges only. Virtual keys must not look like a player taking over.
local HUMAN_KEYS = { "Left", "Right", "A", "D", "Space", "Z", "LShift", "RShift", "X", "LControl" }
local human_prev = {}
local hold = { left = false, right = false, fire = false }
local zap_pulse = false
local zap_armed = false

local function raw_down(k)
    local ok, down = pcall(input.is_key_down_raw, k)
    return ok and down and true or false
end

local function latch_human()
    for _, k in ipairs(HUMAN_KEYS) do
        human_prev[k] = raw_down(k)
    end
end

local function human_edge()
    local edge = false
    for _, k in ipairs(HUMAN_KEYS) do
        local down = raw_down(k)
        if down and not human_prev[k] then
            edge = true
        end
        human_prev[k] = down
    end
    return edge
end

local function clear_virtual()
    G.vkeys.Left = nil
    G.vkeys.Right = nil
    G.vkeys.A = nil
    G.vkeys.D = nil
    G.vkeys.Space = nil
    G.vkeys.Z = nil
    G.vkeys.LShift = nil
    G.vkeys.RShift = nil
    G.vkeys.X = nil
    G.vkeys.LControl = nil
end

local function on_human()
    hold.left = false
    hold.right = false
    hold.fire = false
    zap_pulse = false
    zap_armed = false
    clear_virtual()
end

local function write_hold()
    zap_armed = false
    if not jev or not jev:assisted() then
        return
    end

    if G.state ~= "play" then
        clear_virtual()
        return
    end

    G.vkeys.Left = hold.left or nil
    G.vkeys.Right = hold.right or nil
    G.vkeys.A = nil
    G.vkeys.D = nil
    G.vkeys.Space = hold.fire or nil
    G.vkeys.Z = nil
    G.vkeys.RShift = nil
    G.vkeys.X = nil
    G.vkeys.LControl = nil
    if zap_pulse then
        G.vkeys.LShift = true
        prev.LShift = false
        zap_armed = true
    else
        G.vkeys.LShift = nil
    end
end

local function apply_action(id)
    if id == "left" then
        hold.left = true
        hold.right = false
        hold.fire = true
    elseif id == "right" then
        hold.left = false
        hold.right = true
        hold.fire = true
    elseif id == "stop" then
        hold.left = false
        hold.right = false
        hold.fire = true
    elseif id == "fire" then
        hold.fire = true
    elseif id == "left_fire" then
        hold.left = true
        hold.right = false
        hold.fire = true
    elseif id == "right_fire" then
        hold.left = false
        hold.right = true
        hold.fire = true
    elseif id == "zap" then
        zap_pulse = true
    end
    write_hold()
end

------------------------------------------------------------------ flow
local function to_title()
    G.state = "title"
    set_menu("title", {
        { label = "PLAY", act = "play" },
        { label = "Jev", act = "jev" },
        { label = "SETTINGS", act = "settings" },
        { label = "QUIT", act = "quit" },
    })
    clear_enemies()
    set_shape(1)
    PL.lane = 0
end

local function new_game()
    G.score, G.lives, G.level = 0, 3, 1
    G.next_extra, G.newhi = 20000, false
    PL.zap_ready, PL.v, PL.lane = true, 0, 0
    G.state = "levelintro"; G.intro_t = 0
    start_level(1)
end

local function do_menu_action(act)
    if act == "play" then
        jev:begin_human()
        runtime_ui.show(HUD); new_game()
    elseif act == "jev" then
        latch_human()
        local ok, err = jev:start()
        if not ok then
            jev:begin_human()
            err = err or jev:error() or "Jev failed to start"
            pe_log("[Tempest] " .. tostring(err))
            to_title()
            G.banner = { text = "JEV", sub = tostring(err), t = 0, dur = 6 }
        end
    elseif act == "resume" then
        G.state = G.paused_from or "play"
    elseif act == "settings" then
        if SET then
            local back = G.state
            runtime_ui.hide(HUD)
            SET:open(function()
                runtime_ui.show(HUD)
                -- re-assert TAA+bloom after settings apply
                S("taa", true); S("cas_sharpening", false); S("motion_blur", false)
                S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.4); S("fxaa", false)
                if SET then
                    PSCALE = SET:particle_scale() or 1
                    G.pscale = PSCALE
                end
            end)
        end
    elseif act == "title" then
        save_hi(); to_title()
    elseif act == "quit" then
        save_hi(); pcall(engine.quit)
    end
end

------------------------------------------------------------------ init world
paint_templates()
build_tube_pool()
build_bolts()
PL.claw = make_claw()
PL.em = new_emitter({
    c0 = vec4(1.5, 0.8, 0.2, 1), c1 = vec4(0.4, 0.1, 0.05, 0),
    count = 280, radius = 0.15, smin = 0.04, smax = 0.1,
    lmin = 0.15, lmax = 0.35, noise = 0.6, drag = 1.0, vel = vec3(0, 0, 3),
})
set_shape(1)
if SET then SET:apply() end
-- re-assert look after SET:apply (HIGH baseline)
S("taa", true); S("cas_sharpening", false); S("motion_blur", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.4); S("fxaa", false)
if SET then PSCALE = SET:particle_scale() or 1; G.pscale = PSCALE end

local jev_source = fs.read("Scripts/jev_auto.lua")
local JevAuto = assert(load(jev_source, "@Scripts/jev_auto.lua", "t", _ENV))()
local LIVE = { levelintro = true, play = true, clear = true, warp = true, dying = true }

local function nearest_enemy()
    local n = TUBE.n
    if not n or n < 1 then
        return nil
    end

    local best
    local best_rank
    for i = 1, #enemies do
        local e = enemies[i]
        if e.alive then
            local depth = e.depth or 1
            local lane_dist = abs((e.lane - PL.lane + n * 0.5) % n - n * 0.5)
            local rank = depth + lane_dist * 0.001
            if not best or rank < best_rank then
                best = e
                best_rank = rank
            end
        end
    end
    return best
end

jev = JevAuto.attach({
    port = 9124,
    id = "tempest-remix",
    description = "Tempest Remix. The offered action rides the rim toward the nearest enemy, and the gun keeps firing. Prefer the higher action score.",
    playing = function()
        return LIVE[G.state] == true
    end,
    terminal = function()
        return G.state == "over"
    end,
    score = function()
        return G.score or 0
    end,
    busy = function()
        return false
    end,
    human_edge = human_edge,
    observe = function()
        local enemy = nearest_enemy()
        return {
            player_lane = PL.lane or 0,
            enemy_lane = enemy and enemy.lane or -1,
            enemy_depth = enemy and enemy.depth or -1,
            lives = G.lives or 0,
            score = G.score or 0,
        }
    end,
    actions = function()
        local enemy = nearest_enemy()
        if not enemy or not TUBE.n or TUBE.n < 1 then
            return { { id = "stop", description = "Hold the lane. The gun keeps firing.", score = 1 } }
        end
        local n = TUBE.n
        local signed = (enemy.lane - PL.lane + n * 0.5) % n - n * 0.5
        if signed > 0.35 then
            return { { id = "right", description = "Ride right toward the enemy. The gun keeps firing.", score = signed } }
        end
        if signed < -0.35 then
            return { { id = "left", description = "Ride left toward the enemy. The gun keeps firing.", score = -signed } }
        end
        return { { id = "stop", description = "On the enemy lane. The gun keeps firing.", score = 1 } }
    end,
    apply = apply_action,
    reset = function(seed)
        math.randomseed(seed)
        zap_pulse = false
        zap_armed = false
        G.vkeys.LShift = nil
        G.cam_dz = 0
        G.shake = 0
        new_game()
    end,
    on_human = on_human,
})

to_title()
latch()
pe_log("[Tempest] ready")

------------------------------------------------------------------ attract / ambient
local function ambient(dt)
    set_point(L.rim, vec3(0, 0, 2), vec3(TUBE.tint[1], TUBE.tint[2], TUBE.tint[3]), 40, 18)
    set_point(L.hub, vec3(0, 0, Z_FAR - 1), vec3(TUBE.tint[1] * 1.2, TUBE.tint[2], TUBE.tint[3] * 1.4), 70, 14)
    if TUBE.hub2 then TUBE.hub2:set_rotation(vec3(90, G.t * 25, 0)) end
    if rand() < 0.2 * PSCALE then
        local lane = rr(0, TUBE.n)
        local d = rr(0.2, 0.9)
        local x, y, z = rim_point(lane, d)
        burst(x, y, z, { c0 = vec4(TUBE.tint[1], TUBE.tint[2], TUBE.tint[3], 0.8),
            c1 = vec4(0.1, 0.1, 0.2, 0), count = 1, smin = 0.03, smax = 0.07,
            lmin = 0.8, lmax = 1.6, radius = 0.05, spread = 0.4, vel = vec3(0, 0, -0.5) })
    end
end

local function cam_update(dt)
    local sh = (G.shake or 0) * (SET and SET:shake_scale() or 1)
    G.shake = max(0, (G.shake or 0) - dt * 2.5)
    local ox = (rand() - 0.5) * sh * 0.35
    local oy = (rand() - 0.5) * sh * 0.35
    -- slight follow of claw
    local px, py = rim_point(PL.lane, 0)
    local tx = damp(cam:get_position().x, px * 0.08 + ox, 3, dt)
    local ty = damp(cam:get_position().y, CAM.y + py * 0.06 + oy, 3, dt)
    local dz = G.cam_dz or 0
    cam:set_position(vec3(tx, ty, CAM.z + dz))
    cam:look_at(vec3(px * 0.15, py * 0.1, CAM.z + dz + 30))
end

------------------------------------------------------------------ main loop
local update_step
local function update(dt)
    if G.freeze then return end   -- automation only (screenshots)
    dt = math.min(dt, 0.25)
    if jev then
        jev:tick(dt)
    end
    write_hold()
    local n = math.max(1, math.ceil(dt / (1 / 40)))
    for _ = 1, n do update_step(dt / n) end
end
update_step = function(dt)
    G.t = G.t + dt
    flush_mats()
    -- mouse move tracking for menu hover
    local okm, mx, my = pcall(function()
        local m = input.get_mouse_position and input.get_mouse_position() or nil
        if m then return m.x, m.y end
        return nil
    end)
    if okm and mx then
        if G._mx and (abs(mx - G._mx) + abs(my - (G._my or 0)) > 2) then G.mouse_moved = true end
        G._mx, G._my = mx, my
    end

    if SET and SET:update(dt) then
        latch(); draw_hud(dt); return
    end

    local st = G.state
    ambient(dt)
    cam_update(dt)

    if st == "title" then
        -- slow attract spin
        PL.lane = (PL.lane + dt * 0.7) % TUBE.n
        orient_on_rim(PL.claw.root, PL.lane, 0.0, true, 1.55, sin(G.t * 2) * 8)
        local act = menu_input(pressed)
        if act then do_menu_action(act) end
        if pressed("O") then do_menu_action("settings") end
        if mouse_clicked() and not act then
            -- fall through; menu handles clicks via ui_state
        end
    elseif st == "levelintro" then
        G.intro_t = (G.intro_t or 0) + dt
        orient_on_rim(PL.claw.root, PL.lane, 0.0, true, 1.55, 0)
        if G.intro_t > 1.6 then G.state = "play"; latch() end
    elseif st == "play" then
        local move = 0
        if kdown("Left") or kdown("A") then move = move - 1 end
        if kdown("Right") or kdown("D") then move = move + 1 end
        local fire = kdown("Space") or kdown("Z") or mouse_down()
        local zap = pressed("LShift") or pressed("RShift") or pressed("X") or pressed("LControl")
        if zap_armed then
            zap_armed = false
            zap_pulse = false
            G.vkeys.LShift = nil
        end
        update_player(dt, move, fire, zap)
        -- spawn queue
        SPAWN.t = SPAWN.t + dt
        while SPAWN.plan[1] and SPAWN.t >= SPAWN.plan[1].delay do
            local p = table.remove(SPAWN.plan, 1)
            spawn_enemy(p.kind, p.lane, 1.0)
        end
        if #SPAWN.plan == 0 then SPAWN.done = true end
        update_enemies(dt)
        update_shots(dt)
        update_spikes(dt)
        update_fx(dt)
        -- level clear?
        if SPAWN.done and #enemies == 0 then
            G.state = "clear"; G.clear_t = 0; sfx("clear")
            G.banner = { text = "LEVEL CLEAR", sub = "+" .. (1000 + G.level * 250), t = 0, dur = 1.8 }
            add_score(1000 + G.level * 250)
        end
        if pressed("Escape") or pressed("P") then
            G.paused_from = st; G.state = "paused"; sfx("click")
            set_menu("pause", {
                { label = "RESUME", act = "resume" },
                { label = "SETTINGS", act = "settings" },
                { label = "QUIT TO TITLE", act = "title" },
            })
        end
        if pressed("O") then do_menu_action("settings") end
        if pressed("M") and SET then SET:toggle_mute() end
    elseif st == "paused" then
        local act = menu_input(pressed)
        if act then do_menu_action(act) end
        if pressed("Escape") or pressed("P") then G.state = G.paused_from or "play" end
        if pressed("O") then do_menu_action("settings") end
    elseif st == "clear" then
        G.clear_t = (G.clear_t or 0) + dt
        orient_on_rim(PL.claw.root, PL.lane, 0.0, true, 1.55, 0)
        update_fx(dt)
        if G.clear_t > 0.9 then G.state = "warp"; G.warp_t = 0; G.warp_switched = false; sfx("start") end
    elseif st == "warp" then
        -- arcade-style level transition: the claw dives down its lane, the camera flies through the tube,
        -- and the next tube shape zooms in from the distance
        G.warp_t = (G.warp_t or 0) + dt
        local T1, T2 = 1.5, 1.1
        local t = G.warp_t
        if not G.warp_switched then
            local u = math.min(1, t / T1)
            local e = u * u * (3 - 2 * u)
            local cd = e * 1.08
            G.cam_dz = (Z_FAR + 6 - CAM.z) * u * u * u
            orient_on_rim(PL.claw.root, PL.lane, math.min(cd, 1.0), true, 1.55, t * 220)
            -- leftover spikes kill the claw on the way down (classic)
            for _, s in ipairs(SPIKE_POOL) do
                if s.used then
                    local ld = abs((s.lane - PL.lane + TUBE.n * 0.5) % TUBE.n - TUBE.n * 0.5)
                    if ld < 0.45 and cd >= s.depth then
                        G.cam_dz = 0; G.state = "dying"; G.die_t = 0; sfx("death"); G.shake = (G.shake or 0) + 0.8
                        local x, y, z = rim_point(PL.lane + 0.5, s.depth)
                        burst(x, y, z, { c0 = vec4(2, 1, 0.2, 1), c1 = vec4(0.3, 0.05, 0, 0), count = 35, radius = 0.35, spread = 10 })
                        break
                    end
                end
            end
            if G.state ~= "warp" then return end
            -- speed streaks
            if rand() < 0.9 * PSCALE then
                local lane = rr(0, TUBE.n)
                local x, y, z = rim_point(lane, rr(0.3, 1.0))
                burst(x, y, z, { c0 = vec4(TUBE.tint[1] * 2, TUBE.tint[2] * 2, TUBE.tint[3] * 2, 1), c1 = vec4(0, 0, 0, 0),
                    count = 3, smin = 0.03, smax = 0.08, lmin = 0.2, lmax = 0.4, radius = 0.05, spread = 0.5, vel = vec3(0, 0, -30) })
            end
            if u >= 1 then
                G.warp_switched = true; G.warp_t = 0
                G.level = G.level + 1
                start_level(G.level)
                G.cam_dz = -45
            end
        else
            local u = math.min(1, t / T2)
            local e = 1 - (1 - u) ^ 3
            G.cam_dz = -45 * (1 - e)
            orient_on_rim(PL.claw.root, PL.lane, 0.0, true, 1.55, (1 - e) * 360)
            if u >= 1 then G.cam_dz = 0; G.state = "levelintro"; G.intro_t = 0.6 end
        end
    elseif st == "dying" then
        G.die_t = (G.die_t or 0) + dt
        update_fx(dt)
        if G.die_t > 1.4 then
            G.cam_dz = 0
            G.lives = G.lives - 1
            if G.lives <= 0 then
                G.state = "over"; sfx("gameover"); save_hi()
                set_menu("over", {
                    { label = "PLAY AGAIN", act = "play" },
                    { label = "TITLE", act = "title" },
                })
            else
                PL.inv = 2.0; PL.zap_ready = true; PL.v = 0
                -- remove near threats
                for i = #enemies, 1, -1 do
                    if enemies[i].depth < 0.25 then kill_enemy(enemies[i], false) end
                end
                G.state = "play"; latch()
            end
        end
    elseif st == "over" then
        local act = menu_input(pressed)
        if act then do_menu_action(act) end
        if pressed("O") then do_menu_action("settings") end
    end

    -- always draw claw on title/play etc.
    draw_hud(dt)
    G.mouse_moved = false
end

G.new_game = new_game; G.to_title = to_title; G.start_level = start_level
G.update = update
function G.sim(sec, keys) G.vkeys = keys or {}; for _ = 1, math.floor(sec * 40) do update_step(1 / 40) end; G.vkeys = {}; return G.state .. " lvl=" .. G.level .. " en=" .. #enemies .. " dz=" .. string.format("%.1f", G.cam_dz or 0) end
function G.clear_now() for i = #enemies, 1, -1 do kill_enemy(enemies[i], false) end; SPAWN.plan = {}; SPAWN.done = true end
function G.demo_field()
    new_game(); G.state = "play"; PL.inv = 99; SPAWN.plan = {}
    spawn_enemy("flipper", 1, 0.25); spawn_enemy("flipper", 5, 0.55); spawn_enemy("tanker", 8, 0.7)
    spawn_enemy("spiker", 11, 0.45); spawn_enemy("fuseball", 13, 0.35); spawn_enemy("pulsar", 3, 0.8)
    plant_spike(6, 0.5); PL.lane = 0
    return #enemies
end
G.SET = SET; G.superzap = superzap; G.spawn_enemy = spawn_enemy
G.PL = PL; G.TUBE = TUBE; G.enemies = enemies; G.set_menu = set_menu
hooks { update = update }
