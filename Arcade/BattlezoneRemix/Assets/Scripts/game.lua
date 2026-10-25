-- BATTLEZONE REMIX  (PhasmaEngine, Lua)
-- Modernized remake of Atari's Battlezone (1980). First-person tank combat on a
-- wasteland plain: enemy tanks, super tanks, guided missiles and flying saucers,
-- radar, score. Visuals: cooked tank meshes, mountain silhouettes, dust/fire VFX,
-- dynamic lights, HDR + TAA + smooth bloom.
local PI, TAU = math.pi, math.pi * 2
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 =
    math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local function len2(x, z) return sqrt(x * x + z * z) end
local function norm2(x, z)
    local l = len2(x, z); if l < 1e-6 then return 0, 0, 0 end
    return x / l, z / l, l
end
local G = { state = "boot", t = 0, score = 0, hiscore = 0, lives = 3, wave = 0 }
local jev
local hw_mdx = 0
local KK = {}
_G.BZ = G

------------------------------------------------------------------ deferred materials
local _mset, _mtex, _mds = material.set, material.set_texture, material.set_double_sided
local mat_q = {}
local function qpush(f) mat_q[#mat_q + 1] = { f = f, n = 0 } end
local function mset(n, k, v) pcall(_mset, n, k, v); qpush(function() pcall(_mset, n, k, v) end) end
local function mtex(n, k, v) qpush(function() pcall(_mtex, n, k, v) end) end
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
    mset(n, "roughness", rough or 0.45)
    mset(n, "metallic", metal or 0.35)
end
local function sfx(name) pcall(audio.play, name .. ".wav") end

------------------------------------------------------------------ render (HDR + TAA, CAS off, soft bloom)
local function S(k, v) pcall(settings.set, k, v) end
local ss = scene.add_empty_node("BattlezoneSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "wasteland.hdr")
S("hdr", true); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.5)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("dof", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", true); S("IBL_intensity", 0.85)
S("color_grading", true); S("color_grading_saturation", 1.05); S("color_grading_contrast", 1.06)
S("color_grading_temperature", 0.15)

------------------------------------------------------------------ camera / world
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1600, surf.height or 900
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local FOVX = 1.05
pcall(function() cam:set_fov(math.deg(FOVX)) end)
local WORLD = 220          -- playable half-extent
local HIDE = vec3(0, -1000, 0)

------------------------------------------------------------------ templates
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[Battlezone] missing template " .. name); return nil end
    TPL[name] = { node = n, mesh = n:get_mesh_refs()[1] }
    return TPL[name]
end
local seq = 0
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
local function paint_templates()
    -- player: olive drab armor, warm muzzle glow
    paint(tnode("T_player_hull"), { 0.28, 0.32, 0.22 }, { 0.02, 0.03, 0.01 }, 0.55, 0.55)
    paint(tnode("T_player_tread"), { 0.12, 0.12, 0.1 }, { 0, 0, 0 }, 0.7, 0.8)
    paint(tnode("T_player_treadR"), { 0.12, 0.12, 0.1 }, { 0, 0, 0 }, 0.7, 0.8)
    paint(tnode("T_player_turret"), { 0.32, 0.36, 0.26 }, { 0.03, 0.04, 0.02 }, 0.5, 0.6)
    paint(tnode("T_player_barrel"), { 0.18, 0.18, 0.16 }, { 0.01, 0.01, 0.01 }, 0.35, 0.85)
    paint(tnode("T_player_hatch"), { 0.4, 0.38, 0.28 }, { 0.05, 0.04, 0.02 }, 0.4, 0.5)
    paint(tnode("T_player_glow"), { 1.0, 0.55, 0.15 }, { 4.0, 1.8, 0.3 }, 0.2, 0.0)
    -- enemy: rusted red-brown
    paint(tnode("T_enemy_hull"), { 0.45, 0.22, 0.12 }, { 0.08, 0.02, 0.01 }, 0.55, 0.5)
    paint(tnode("T_enemy_tread"), { 0.1, 0.08, 0.07 }, { 0, 0, 0 }, 0.75, 0.8)
    paint(tnode("T_enemy_treadR"), { 0.1, 0.08, 0.07 }, { 0, 0, 0 }, 0.75, 0.8)
    paint(tnode("T_enemy_turret"), { 0.5, 0.25, 0.12 }, { 0.1, 0.03, 0.01 }, 0.5, 0.55)
    paint(tnode("T_enemy_barrel"), { 0.2, 0.15, 0.12 }, { 0.02, 0.01, 0 }, 0.4, 0.8)
    paint(tnode("T_enemy_glow"), { 1.0, 0.3, 0.1 }, { 5.0, 1.2, 0.2 }, 0.2, 0)
    -- super tank: dark slate + cyan accents
    paint(tnode("T_super_hull"), { 0.18, 0.22, 0.28 }, { 0.02, 0.05, 0.08 }, 0.4, 0.7)
    paint(tnode("T_super_tread"), { 0.08, 0.09, 0.1 }, { 0, 0, 0 }, 0.7, 0.85)
    paint(tnode("T_super_treadR"), { 0.08, 0.09, 0.1 }, { 0, 0, 0 }, 0.7, 0.85)
    paint(tnode("T_super_turret"), { 0.22, 0.28, 0.35 }, { 0.04, 0.1, 0.15 }, 0.35, 0.75)
    paint(tnode("T_super_barrel"), { 0.15, 0.18, 0.22 }, { 0.02, 0.04, 0.06 }, 0.3, 0.9)
    paint(tnode("T_super_glow"), { 0.3, 0.85, 1.0 }, { 1.0, 4.0, 6.0 }, 0.2, 0)
    -- saucer
    paint(tnode("T_saucer_body"), { 0.55, 0.58, 0.62 }, { 0.15, 0.2, 0.3 }, 0.25, 0.85)
    paint(tnode("T_saucer_rim"), { 0.7, 0.45, 0.15 }, { 1.5, 0.7, 0.15 }, 0.3, 0.6)
    paint(tnode("T_saucer_glow"), { 0.4, 1.0, 0.6 }, { 1.5, 5.0, 2.5 }, 0.15, 0)
    -- missile / shell
    paint(tnode("T_missile_body"), { 0.35, 0.35, 0.32 }, { 0.05, 0.04, 0.02 }, 0.4, 0.7)
    paint(tnode("T_missile_glow"), { 1.0, 0.45, 0.1 }, { 6.0, 2.0, 0.3 }, 0.2, 0)
    paint(tnode("T_shell_body"), { 0.7, 0.55, 0.25 }, { 0.8, 0.4, 0.05 }, 0.35, 0.6)
    paint(tnode("T_shell_glow"), { 1.0, 0.7, 0.2 }, { 5.0, 2.5, 0.4 }, 0.2, 0)
    -- environment
    for i = 0, 3 do
        paint(tnode("T_mountain_" .. i), { 0.22, 0.18, 0.14 }, { 0.04, 0.02, 0.01 }, 0.85, 0.05)
        mtex(tnode("T_mountain_" .. i), "base_color", "rock.png")
    end
    paint(tnode("T_pyramid_5"), { 0.22, 0.18, 0.14 }, { 0.04, 0.02, 0.01 }, 0.85, 0.05)   -- mountain foothills
    mtex(tnode("T_pyramid_5"), "base_color", "rock.png")
    for i = 0, 7 do
        paint(tnode("T_ground_" .. i), { 0.4, 0.3, 0.18 }, { 0.02, 0.015, 0.008 }, 0.9, 0.0)
        mtex(tnode("T_ground_" .. i), "base_color", "ground.png")
    end
    for i = 0, 9 do paint(tnode("T_crater_" .. i), { 0.25, 0.2, 0.14 }, { 0.01, 0.008, 0.004 }, 0.95, 0) end
    for i = 0, 11 do paint(tnode("T_rock_" .. i), { 0.3, 0.26, 0.2 }, { 0.02, 0.015, 0.01 }, 0.8, 0.1) end
    for i = 0, 5 do
        if i ~= 5 then paint(tnode("T_pyramid_" .. i), { 0.35, 0.32, 0.25 }, { 0.03, 0.025, 0.015 }, 0.7, 0.15) end
        paint(tnode("T_block_" .. i), { 0.28, 0.3, 0.32 }, { 0.02, 0.025, 0.03 }, 0.55, 0.4)
    end
    local scols = { {1,.6,.1}, {1,.25,.15}, {.3,.7,1}, {.9,.9,.95}, {1,.45,.2}, {.5,1,.4} }
    for i = 0, 5 do
        local c = scols[i + 1]
        paint(tnode("T_shard_" .. i), c, { c[1]*3, c[2]*3, c[3]*3 }, 0.3, 0.4)
    end
    for i = 0, 3 do
        paint(tnode("T_ring_" .. i), { 1, .7, .3 }, { 4, 2, 0.5 }, 0.2, 0)
        paint(tnode("T_orb_" .. i), { 1, .5, .15 }, { 5, 2, 0.4 }, 0.2, 0)
    end
    paint(tnode("T_radar"), { 0.3, 0.55, 0.35 }, { 0.1, 0.4, 0.2 }, 0.4, 0.5)
end

------------------------------------------------------------------ entity builders (root + parts)
local function make_tank(kind)
    seq = seq + 1
    local root = scene.add_empty_node(kind .. "_tank" .. seq)
    root:set_position(HIDE)
    local prefix = "T_" .. kind .. "_"
    local hull = clone(prefix .. "hull", vec3(0, 0, 0), nil, root)
    local tl = clone(prefix .. "tread", vec3(-1.15, 0, 0), nil, root)
    local tr = clone(prefix .. "treadR", vec3(1.15, 0, 0), vec3(-1, 1, 1), root)
    local turret = clone(prefix .. "turret", vec3(0, 1.05, -0.1), nil, root)
    local barrel = clone(prefix .. "barrel", vec3(0, 0.25, 0.55), nil, turret)
    local glow = clone(prefix .. "glow", vec3(0, 0, 2.3), nil, barrel)
    local hatch
    if kind == "player" then hatch = clone("T_player_hatch", vec3(0, 0.55, -0.15), nil, turret) end
    return {
        root = root, hull = hull, tl = tl, tr = tr, turret = turret, barrel = barrel, glow = glow, hatch = hatch,
        kind = kind, alive = false, x = 0, z = 0, yaw = 0, hp = 1, cd = 0, ai = {},
    }
end
local function make_saucer()
    seq = seq + 1
    local root = scene.add_empty_node("saucer" .. seq); root:set_position(HIDE)
    local body = clone("T_saucer_body", vec3(0, 0, 0), nil, root)
    local rim = clone("T_saucer_rim", vec3(0, 0, 0), nil, root)
    local glow = clone("T_saucer_glow", vec3(0, -0.2, 0), nil, root)
    return { root = root, body = body, rim = rim, glow = glow, alive = false, x = 0, y = 8, z = 0, yaw = 0, hp = 1, cd = 0, ai = {} }
end
local function make_missile()
    seq = seq + 1
    local root = scene.add_empty_node("missile" .. seq); root:set_position(HIDE)
    local body = clone("T_missile_body", vec3(0, 0, 0), nil, root)
    local glow = clone("T_missile_glow", vec3(0, 0, -0.1), nil, root)
    return { root = root, body = body, glow = glow, alive = false, x = 0, y = 2, z = 0, yaw = 0, pitch = 0, hp = 1, ai = {} }
end
local function place_tank(t, x, z, yaw, scale)
    t.x, t.z, t.yaw = x, z, yaw or t.yaw
    t.root:set_position(vec3(x, 0, z))
    t.root:set_rotation(vec3(0, math.deg(t.yaw), 0))
    if scale then t.root:set_scale(vec3(scale, scale, scale)) end
end
local function hide_ent(e)
    e.alive = false
    e.root:set_position(HIDE)
end

------------------------------------------------------------------ world props
local GROUNDS, MOUNTAINS, ROCKS, PYRAMIDS, BLOCKS, CRATERS = {}, {}, {}, {}, {}, {}
local GROUND_ROOT, MOUNTAIN_ROOT
local GROUND_TILE, R_MTN = 80, 600          -- ground tile size (ground.pemesh is 80 x 80 m); mountain ring radius
local EYE = { x = 0, z = 0 }
local function update_backdrop()
    -- keep the horizon around the eye: ground snaps to whole tiles (texture stays put), mountains follow exactly
    if GROUND_ROOT then
        GROUND_ROOT:set_position(vec3(math.floor(EYE.x / GROUND_TILE + 0.5) * GROUND_TILE, 0,
                                      math.floor(EYE.z / GROUND_TILE + 0.5) * GROUND_TILE))
    end
    if MOUNTAIN_ROOT then MOUNTAIN_ROOT:set_position(vec3(EYE.x, 0, EYE.z)) end
end
local function build_world()
    -- Ground and mountains are a backdrop that follows the eye (see update_backdrop): the playfield is
    -- +-WORLD but the camera sees ~600 m to the horizon, so a fixed 3x3 ground patch (+-118 m) ran out
    -- (hard ground edge with sky under the mountains) and ten loose mountain slabs at 150-190 m left gaps
    -- and showed their square-cut ends. Now: a 9x9 grid of 80 m tiles snapped to the 80 m grid around the
    -- eye (+-360 m, world-locked texture) plus a coarse outer apron (+-1080 m), and a closed ring of
    -- overlapping mountains at R_MTN with tapered foothills over every joint, always R_MTN away like the
    -- arcade's mountains at infinity. Everything stays inside the 800 m far plane.
    GROUND_ROOT = scene.add_empty_node("GroundRoot")
    local gi = 0
    for gx = -4, 4 do
        for gz = -4, 4 do
            GROUNDS[#GROUNDS + 1] = clone("T_ground_" .. (gi % 8), vec3(gx * GROUND_TILE, 0, gz * GROUND_TILE), 1.0, GROUND_ROOT)
            gi = gi + 1
        end
    end
    local far = GROUND_TILE * 9
    for gx = -1, 1 do
        for gz = -1, 1 do
            if gx ~= 0 or gz ~= 0 then
                GROUNDS[#GROUNDS + 1] = clone("T_ground_" .. (gi % 8), vec3(gx * far, 0, gz * far), 9.0, GROUND_ROOT)
                gi = gi + 1
            end
        end
    end
    -- mountain ring: per-variant silhouette size (from tools/gen_meshes.py) so every piece spans its arc
    -- and the foothill at each joint is taller than the two piece ends it covers
    MOUNTAIN_ROOT = scene.add_empty_node("MountainRoot")
    local MV = {   -- width, peak, left end, right end (mesh units)
        [0] = { 50, 13.8, 5.1, 8.0 }, { 58, 16.6, 4.9, 10.1 }, { 66, 21.1, 8.5, 5.9 }, { 74, 28.6, 14.8, 6.4 },
    }
    local N = 12
    local step = TAU / N
    local span = 2 * R_MTN * math.tan(step / 2) * 1.16          -- chord per piece + overlap
    local peaks = { 70, 96, 62, 88, 104, 66, 92, 78, 100, 64, 84, 94 }
    local ends = {}
    for i = 1, N do
        local v = (i * 3) % 4
        local mv = MV[v]
        local a = (i - 1) * step
        local flip = (i % 2 == 0)                                  -- 180 deg turn shows the mirrored back face
        local sx, sy = span / mv[1], peaks[i] / mv[2]
        local n = clone("T_mountain_" .. v, vec3(sin(a) * R_MTN, 0, cos(a) * R_MTN), vec3(sx, sy, 3.0), MOUNTAIN_ROOT)
        n:set_rotation(vec3(0, math.deg(a) + (flip and 180 or 0), 0))
        MOUNTAINS[#MOUNTAINS + 1] = n
        local l, r = mv[3] * sy, mv[4] * sy
        if flip then l, r = r, l end
        -- seen from the centre, +angle runs right-to-left for the -z face; record end heights per joint
        ends[i] = { lo = r, hi = l }
    end
    for i = 1, N do
        local j = i % N + 1
        local h = max(ends[i].hi, ends[j].lo, ends[i].lo, ends[j].hi) * 1.35
        local a = (i - 0.5) * step
        local r = R_MTN - 14
        local n = clone("T_pyramid_5", vec3(sin(a) * r, 0, cos(a) * r), vec3(60 / 1.5, h / 3.0, 12), MOUNTAIN_ROOT)
        n:set_rotation(vec3(0, math.deg(a), 0))
        MOUNTAINS[#MOUNTAINS + 1] = n
    end
    -- scattered rocks / pyramids / blocks / craters
    local rng_pos = {
        {28, 40}, {-35, 55}, {60, -20}, {-50, -45}, {15, -70}, {-80, 10},
        {90, 30}, {-25, 95}, {45, 75}, {-70, -80}, {110, -50}, {-95, 60},
        {5, 120}, {-120, -30}, {75, -95}, {-55, 130},
    }
    for i, p in ipairs(rng_pos) do
        if i % 4 == 1 then
            local n = clone("T_pyramid_" .. ((i - 1) % 6), vec3(p[1], 0, p[2]), 0.8 + (i % 3) * 0.2)
            n:set_rotation(vec3(0, i * 25, 0)); PYRAMIDS[#PYRAMIDS + 1] = { n = n, x = p[1], z = p[2], r = 2.2 }
        elseif i % 4 == 2 then
            local n = clone("T_block_" .. ((i - 1) % 6), vec3(p[1], 0, p[2]), 0.9 + (i % 2) * 0.3)
            n:set_rotation(vec3(0, i * 40, 0)); BLOCKS[#BLOCKS + 1] = { n = n, x = p[1], z = p[2], r = 1.8 }
        else
            local n = clone("T_rock_" .. ((i - 1) % 12), vec3(p[1], 0, p[2]), 1.0 + (i % 4) * 0.25)
            n:set_rotation(vec3(0, i * 33, 0)); ROCKS[#ROCKS + 1] = { n = n, x = p[1], z = p[2], r = 1.4 }
        end
    end
    for i = 1, 8 do
        local a = i * TAU / 8 + 0.4; local d = 40 + (i % 3) * 25
        local x, z = cos(a) * d, sin(a) * d
        local n = clone("T_crater_" .. ((i - 1) % 10), vec3(x, 0.02, z), 1.2 + (i % 3) * 0.4)
        CRATERS[#CRATERS + 1] = n
    end
end
local function obstacle_hit(x, z, rad)
    for _, o in ipairs(PYRAMIDS) do if len2(x - o.x, z - o.z) < rad + o.r then return true end end
    for _, o in ipairs(BLOCKS) do if len2(x - o.x, z - o.z) < rad + o.r then return true end end
    for _, o in ipairs(ROCKS) do if len2(x - o.x, z - o.z) < rad + o.r * 0.7 then return true end end
    return false
end

------------------------------------------------------------------ lights
local function add_point() lights.add_point(); return #lights.get_point_lights() - 1 end
KK.LNODE = {}
KK.LIGHT_GAIN = 0.14
local function set_point(i, pos, col, inten, rad)
    pcall(lights.set_point_light, i, pos, col, inten * KK.LIGHT_GAIN, rad)
    local n = KK.LNODE[i]
    if n == nil then
        local l = lights.get_point_lights()[i + 1]
        n = (l and scene.find_model(l.name)) or false
        KK.LNODE[i] = n
    end
    if n then n:set_position(pos) end
end
local L = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    -- low sun from desert sky
    lights.set_directional_light(0, vec3(0.55, 0.55, 0.35), vec3(1.0, 0.75, 0.45), 2.4)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    L.sunfill = addp(vec3(40, 30, 60), vec3(1.0, 0.7, 0.35), 80, 120)
    L.cool = addp(vec3(-50, 25, -40), vec3(0.25, 0.4, 0.7), 50, 100)
    L.muzzle = addp(HIDE, vec3(1.0, 0.6, 0.2), 0, 1)
    L.player = addp(HIDE, vec3(0.5, 0.7, 0.4), 0, 1)
    L.flash = {}
    for i = 1, 8 do L.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1, power = 0, rad = 8 } end
end
local flash_next = 1
local function flash_at(x, y, z, col, power, life, rad)
    local f = L.flash[flash_next]; flash_next = flash_next % #L.flash + 1
    f.t, f.life = 0, life or 0.4
    f.pos, f.col = vec3(x, y, z), vec3(col[1], col[2], col[3])
    f.power, f.rad = power or 50, rad or 12
end
local function update_flashes(dt)
    for _, f in ipairs(L.flash) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = 1 - clamp(f.t / f.life, 0, 1)
            set_point(f.idx, f.pos, f.col, f.power * k * k, f.rad)
            if f.t >= f.life then set_point(f.idx, HIDE, f.col, 0, 1) end
        end
    end
end

------------------------------------------------------------------ particles / debris / rings
local PSCALE, SHAKE_SCALE = 1.0, 1.0
local function burst(x, y, z, o)
    pcall(particles.emit_burst, {
        position = vec3(x, y, z), velocity = o.vel or vec3(0, 2, 0),
        color_start = o.c0, color_end = o.c1,
        count = max(1, floor((o.count or 40) * PSCALE)),
        size_min = o.smin or 0.08, size_max = o.smax or 0.28,
        life_min = o.lmin or 0.3, life_max = o.lmax or 0.9,
        spawn_radius = o.radius or 0.4, noise_strength = o.spread or 12, drag = o.drag or 1.8,
        gravity = o.grav or vec3(0, -6, 0), cleanup_delay = 3.0,
    })
end
local function explode(x, z, big)
    local y = 1.2
    burst(x, y, z, { c0 = vec4(1, 0.85, 0.4, 1), c1 = vec4(0.4, 0.1, 0.02, 0),
        count = big and 90 or 50, smin = 0.1, smax = big and 0.55 or 0.35, lmin = 0.3, lmax = 1.0,
        radius = 0.6, spread = 18, grav = vec3(0, -4, 0) })
    burst(x, y + 0.5, z, { c0 = vec4(1, 0.4, 0.1, 1), c1 = vec4(0.1, 0.05, 0.02, 0),
        count = big and 40 or 22, smin = 0.05, smax = 0.15, lmin = 0.2, lmax = 0.55,
        radius = 0.2, spread = 28, grav = vec3(0, -2, 0), vel = vec3(0, 6, 0) })
    -- dust
    burst(x, 0.3, z, { c0 = vec4(0.45, 0.35, 0.2, 0.9), c1 = vec4(0.25, 0.2, 0.12, 0),
        count = big and 50 or 28, smin = 0.2, smax = 0.7, lmin = 0.6, lmax = 1.6,
        radius = 1.0, spread = 8, grav = vec3(0, -1, 0), vel = vec3(0, 3, 0) })
    flash_at(x, y + 1, z, { 1.0, 0.55, 0.2 }, big and 90 or 55, 0.45, big and 18 or 12)
    shatter_at(x, z, big and 14 or 8)
    ring_at(x, z, big and 1.4 or 1.0)
end

local SHARDS, live_shards = {}, {}
local function build_debris()
    for c = 0, 5 do
        SHARDS[c] = { next = 1 }
        for k = 1, 12 do SHARDS[c][k] = { node = clone("T_shard_" .. c, HIDE, 0.5), life = 0 } end
    end
end
function shatter_at(x, z, n)
    for _ = 1, floor((n or 8) * (0.4 + 0.6 * PSCALE) + 0.5) do
        local pool = SHARDS[rand(0, 5)]
        local s = pool[pool.next]; pool.next = pool.next % #pool + 1
        local a, sp = rr(0, TAU), rr(5, 14)
        s.x, s.y, s.z = x, rr(0.5, 2.0), z
        s.vx, s.vy, s.vz = cos(a) * sp, rr(4, 12), sin(a) * sp
        s.rx, s.ry, s.rz = rr(0, 360), rr(0, 360), rr(0, 360)
        s.wx, s.wy, s.wz = rr(-600, 600), rr(-600, 600), rr(-600, 600)
        s.sz = rr(0.4, 0.9); s.life = rr(0.6, 1.2)
        if not s.live then s.live = true; live_shards[#live_shards + 1] = s end
    end
end
local function update_shards(dt)
    for i = #live_shards, 1, -1 do
        local s = live_shards[i]
        s.life = s.life - dt
        if s.life <= 0 then
            s.live = false; s.node:set_position(HIDE); table.remove(live_shards, i)
        else
            s.vy = s.vy - 14 * dt
            local d = math.exp(-1.2 * dt)
            s.vx, s.vz = s.vx * d, s.vz * d
            s.x, s.y, s.z = s.x + s.vx * dt, s.y + s.vy * dt, s.z + s.vz * dt
            if s.y < 0.1 then s.y = 0.1; s.vy = -s.vy * 0.3 end
            s.rx, s.ry, s.rz = s.rx + s.wx * dt, s.ry + s.wy * dt, s.rz + s.wz * dt
            local k = clamp(s.life / 0.4, 0, 1) * s.sz
            s.node:set_position(vec3(s.x, s.y, s.z)); s.node:set_rotation(vec3(s.rx, s.ry, s.rz)); s.node:set_scale(vec3(k, k, k))
        end
    end
end
local RINGS, ring_next = {}, 1
local function build_rings()
    for i = 0, 3 do
        RINGS[#RINGS + 1] = { node = clone("T_ring_" .. i, HIDE), life = 0 }
        RINGS[#RINGS + 1] = { node = clone("T_ring_" .. i, HIDE), life = 0 }
    end
end
function ring_at(x, z, sc)
    local r = RINGS[ring_next]; ring_next = ring_next % #RINGS + 1
    r.x, r.z, r.life, r.sc0 = x, z, 0.55, sc or 1
    r.node:set_position(vec3(x, 0.4, z)); r.node:set_rotation(vec3(90, 0, 0))
end
local function update_rings(dt)
    for _, r in ipairs(RINGS) do
        if r.life > 0 then
            r.life = r.life - dt
            local u = 1 - clamp(r.life / 0.55, 0, 1)
            local sc = r.sc0 * (1 + u * 6)
            r.node:set_scale(vec3(sc, sc, sc * 0.2))
            if r.life <= 0 then r.node:set_position(HIDE) end
        end
    end
end
local ORBS, orb_next = {}, 1
local function build_orbs()
    for i = 0, 3 do
        ORBS[#ORBS + 1] = { node = clone("T_orb_" .. i, HIDE), life = 0 }
        ORBS[#ORBS + 1] = { node = clone("T_orb_" .. i, HIDE), life = 0 }
    end
end
local function orb_flash(x, y, z)
    local o = ORBS[orb_next]; orb_next = orb_next % #ORBS + 1
    o.life = 0.25; o.node:set_position(vec3(x, y, z)); o.node:set_scale(vec3(0.8, 0.8, 0.8))
end
local function update_orbs(dt)
    for _, o in ipairs(ORBS) do
        if o.life > 0 then
            o.life = o.life - dt
            local k = clamp(o.life / 0.25, 0, 1)
            o.node:set_scale(vec3(k * 1.4, k * 1.4, k * 1.4))
            if o.life <= 0 then o.node:set_position(HIDE) end
        end
    end
end

------------------------------------------------------------------ player + shells
local P = { tank = nil, x = 0, z = 0, yaw = 0, speed = 0, turn = 0, fire_cd = 0, invuln = 0, shake = 0 }
local SHELLS = {}
local ENEMY_SHELLS = {}
local function build_player()
    P.tank = make_tank("player")
    P.tank.alive = true
    place_tank(P.tank, 0, 0, 0, 1.0)
    P.x, P.z, P.yaw, P.turn = 0, 0, 0, 0
end
local function spawn_shell(list, x, y, z, yaw, speed, friendly)
    local s = nil
    for _, sh in ipairs(list) do if not sh.alive then s = sh; break end end
    if not s then
        seq = seq + 1
        local root = scene.add_empty_node((friendly and "pshell" or "eshell") .. seq)
        local body = clone("T_shell_body", vec3(0, 0, 0), nil, root)
        local glow = clone("T_shell_glow", vec3(0, 0, 0.2), 0.7, root)
        s = { root = root, body = body, glow = glow, alive = false }
        list[#list + 1] = s
    end
    s.alive = true; s.x, s.y, s.z = x, y, z; s.yaw = yaw; s.speed = speed; s.life = 2.8; s.friendly = friendly
    s.root:set_position(vec3(x, y, z)); s.root:set_rotation(vec3(0, math.deg(yaw), 0))
    return s
end
local function update_shells(list, dt, on_hit)
    for _, s in ipairs(list) do
        if s.alive then
            s.life = s.life - dt
            local dx, dz = sin(s.yaw) * s.speed * dt, cos(s.yaw) * s.speed * dt
            s.x, s.z = s.x + dx, s.z + dz
            s.root:set_position(vec3(s.x, s.y, s.z))
            if s.life <= 0 or abs(s.x) > WORLD or abs(s.z) > WORLD or obstacle_hit(s.x, s.z, 0.5) then
                if obstacle_hit(s.x, s.z, 0.5) then
                    burst(s.x, s.y, s.z, { c0 = vec4(1, 0.7, 0.3, 1), c1 = vec4(0.3, 0.15, 0.05, 0),
                        count = 18, smin = 0.05, smax = 0.18, radius = 0.2, spread = 14 })
                    flash_at(s.x, s.y, s.z, { 1, 0.5, 0.2 }, 30, 0.25, 8)
                end
                s.alive = false; s.root:set_position(HIDE)
            elseif on_hit and on_hit(s) then
                s.alive = false; s.root:set_position(HIDE)
            end
        end
    end
end

------------------------------------------------------------------ enemy pools
local TANKS, SUPERS, SAUCERS, MISSILES = {}, {}, {}, {}
local function build_pools()
    for i = 1, 6 do TANKS[i] = make_tank("enemy") end
    for i = 1, 3 do SUPERS[i] = make_tank("super") end
    for i = 1, 2 do SAUCERS[i] = make_saucer() end
    for i = 1, 3 do MISSILES[i] = make_missile() end
end
local function free_slot(pool)
    for _, e in ipairs(pool) do if not e.alive then return e end end
end
local function spawn_away(min_d)
    for _ = 1, 30 do
        local a = rr(0, TAU); local d = rr(min_d or 55, 100)
        local x, z = P.x + cos(a) * d, P.z + sin(a) * d
        if abs(x) < WORLD - 10 and abs(z) < WORLD - 10 and not obstacle_hit(x, z, 2.5) then
            return x, z
        end
    end
    return P.x + 60, P.z + 60
end
local function spawn_tank(pool, kind, hp)
    local e = free_slot(pool); if not e then return end
    local x, z = spawn_away(50)
    e.alive = true; e.hp = hp or 1; e.cd = rr(0.5, 1.5); e.ai = { state = "hunt", t = 0 }
    e.kind = kind
    place_tank(e, x, z, atan2(P.x - x, P.z - z), kind == "super" and 1.25 or 1.0)
    return e
end
local function spawn_saucer()
    local e = free_slot(SAUCERS); if not e then return end
    local x, z = spawn_away(70)
    e.alive = true; e.hp = 1; e.x, e.y, e.z = x, 10 + rr(0, 4), z
    e.yaw = rr(0, TAU); e.cd = 1.5; e.ai = { t = 0, vx = 0, vz = 0 }
    e.root:set_position(vec3(e.x, e.y, e.z))
    sfx("saucer")
    return e
end
local function spawn_missile()
    local e = free_slot(MISSILES); if not e then return end
    local x, z = spawn_away(80)
    e.alive = true; e.hp = 1; e.x, e.y, e.z = x, 1.5, z
    e.yaw = atan2(P.x - x, P.z - z); e.speed = 22; e.life = 12; e.ai = {}
    e.root:set_position(vec3(e.x, e.y, e.z)); e.root:set_rotation(vec3(0, math.deg(e.yaw), 0))
    sfx("missile")
    return e
end

local SCORE_VAL = { enemy = 1000, super = 3000, saucer = 5000, missile = 2000 }
local function kill_enemy(e, kind)
    if not e.alive then return end
    explode(e.x, e.z, kind == "super" or kind == "saucer")
    sfx("death")
    G.score = G.score + (SCORE_VAL[kind] or 1000)
    if (not jev or not jev:assisted()) and G.score > G.hiscore then
        G.hiscore = G.score
        G.newhi = true
    end
    sfx("score")
    hide_ent(e)
    G.kills = (G.kills or 0) + 1
    G.wave_kills = (G.wave_kills or 0) + 1
end

local function aim_yaw(from_x, from_z, to_x, to_z)
    return atan2(to_x - from_x, to_z - from_z)
end
local function ang_diff(a, b)
    local d = (b - a + PI) % TAU - PI
    return d
end

local function update_enemy_tank(e, dt, is_super)
    if not e.alive then return end
    e.ai.t = (e.ai.t or 0) + dt
    local tx, tz = P.x - e.x, P.z - e.z
    local dist = len2(tx, tz)
    local want = aim_yaw(e.x, e.z, P.x, P.z)
    local turn = ang_diff(e.yaw, want)
    local turn_spd = is_super and 1.6 or 2.2
    e.yaw = e.yaw + clamp(turn, -turn_spd * dt, turn_spd * dt)
    local speed = is_super and 9 or 12
    if dist > 35 then
        local nx, nz = sin(e.yaw), cos(e.yaw)
        local nx2, nz2 = e.x + nx * speed * dt, e.z + nz * speed * dt
        if not obstacle_hit(nx2, nz2, 2.0) and abs(nx2) < WORLD and abs(nz2) < WORLD then
            e.x, e.z = nx2, nz2
        else
            e.yaw = e.yaw + rr(-1, 1)
        end
    elseif dist < 18 then
        local nx, nz = -sin(e.yaw), -cos(e.yaw)
        local nx2, nz2 = e.x + nx * speed * 0.5 * dt, e.z + nz * speed * 0.5 * dt
        if not obstacle_hit(nx2, nz2, 2.0) then e.x, e.z = nx2, nz2 end
    end
    place_tank(e, e.x, e.z, e.yaw)
    -- turret lead slightly
    if e.turret then e.turret:set_rotation(vec3(0, math.deg(ang_diff(e.yaw, want)) * 0.3, 0)) end
    e.cd = e.cd - dt
    if e.cd <= 0 and dist < 90 and abs(ang_diff(e.yaw, want)) < 0.35 then
        e.cd = is_super and rr(1.2, 2.0) or rr(1.6, 2.8)
        local bx = e.x + sin(e.yaw) * 2.5
        local bz = e.z + cos(e.yaw) * 2.5
        spawn_shell(ENEMY_SHELLS, bx, 1.4, bz, e.yaw, is_super and 48 or 40, false)
        flash_at(bx, 1.5, bz, is_super and {0.3,0.8,1} or {1,0.4,0.15}, 35, 0.2, 7)
        orb_flash(bx, 1.5, bz)
    end
end
local function update_saucer(e, dt)
    if not e.alive then return end
    e.ai.t = e.ai.t + dt
    local want = aim_yaw(e.x, e.z, P.x, P.z)
    e.yaw = e.yaw + ang_diff(e.yaw, want) * 1.5 * dt
    -- strafe circle
    local side = e.ai.t * 0.7
    local spd = 14
    e.x = e.x + (sin(e.yaw) * 0.4 + cos(e.yaw) * sin(side)) * spd * dt
    e.z = e.z + (cos(e.yaw) * 0.4 - sin(e.yaw) * sin(side)) * spd * dt
    e.y = 9 + 2 * sin(e.ai.t * 1.3)
    e.root:set_position(vec3(e.x, e.y, e.z))
    e.root:set_rotation(vec3(8 * sin(e.ai.t), math.deg(e.yaw), 10 * cos(e.ai.t * 0.7)))
    if e.rim then e.rim:set_rotation(vec3(0, math.deg(e.ai.t * 120), 0)) end
    e.cd = e.cd - dt
    if e.cd <= 0 then
        e.cd = rr(1.8, 3.0)
        local yaw = aim_yaw(e.x, e.z, P.x, P.z)
        spawn_shell(ENEMY_SHELLS, e.x, e.y - 0.5, e.z, yaw, 35, false)
    end
end
local function update_missile_ent(e, dt)
    if not e.alive then return end
    if e.ai and e.ai.frozen then
        e.root:set_position(vec3(e.x, e.y, e.z)); e.root:set_rotation(vec3(-8, math.deg(e.yaw), 0)); return
    end
    e.life = (e.life or 10) - dt
    local want = aim_yaw(e.x, e.z, P.x, P.z)
    e.yaw = e.yaw + clamp(ang_diff(e.yaw, want), -2.5 * dt, 2.5 * dt)
    e.speed = min(36, e.speed + 8 * dt)
    e.x = e.x + sin(e.yaw) * e.speed * dt
    e.z = e.z + cos(e.yaw) * e.speed * dt
    e.y = 1.2 + 0.3 * sin(G.t * 8)
    e.root:set_position(vec3(e.x, e.y, e.z))
    e.root:set_rotation(vec3(-8, math.deg(e.yaw), 0))
    -- trail
    if floor(G.t * 20) % 2 == 0 then
        burst(e.x - sin(e.yaw) * 0.5, e.y, e.z - cos(e.yaw) * 0.5, {
            c0 = vec4(1, 0.5, 0.1, 1), c1 = vec4(0.2, 0.05, 0, 0), count = 4,
            smin = 0.06, smax = 0.14, lmin = 0.15, lmax = 0.35, radius = 0.05, spread = 3,
            grav = vec3(0, 0, 0), vel = vec3(-sin(e.yaw)*2, 0, -cos(e.yaw)*2)
        })
    end
    if e.life <= 0 or abs(e.x) > WORLD or abs(e.z) > WORLD then
        explode(e.x, e.z, false); hide_ent(e)
    elseif len2(e.x - P.x, e.z - P.z) < 2.8 then
        -- hit player
        damage_player(1)
        explode(e.x, e.z, false); hide_ent(e)
    end
end

------------------------------------------------------------------ waves / spawning
local function count_alive()
    local n = 0
    for _, e in ipairs(TANKS) do if e.alive then n = n + 1 end end
    for _, e in ipairs(SUPERS) do if e.alive then n = n + 1 end end
    for _, e in ipairs(SAUCERS) do if e.alive then n = n + 1 end end
    for _, e in ipairs(MISSILES) do if e.alive then n = n + 1 end end
    return n
end
local function start_wave()
    G.wave = G.wave + 1
    G.wave_kills = 0
    G.spawn_cd = 1.0
    G.banner = { text = "WAVE " .. G.wave, sub = "ENEMY FORCES APPROACHING", t = 0, dur = 2.5 }
    sfx("start")
end
local function wave_spawner(dt)
    if G.state ~= "play" then return end
    G.spawn_cd = (G.spawn_cd or 0) - dt
    local alive = count_alive()
    local target = min(2 + G.wave, 7)
    if G.spawn_cd <= 0 and alive < target then
        G.spawn_cd = max(1.5, 4.0 - G.wave * 0.25)
        local r = rand()
        if G.wave >= 3 and r < 0.15 then spawn_saucer()
        elseif G.wave >= 2 and r < 0.35 then spawn_missile()
        elseif G.wave >= 2 and r < 0.55 then spawn_tank(SUPERS, "super", 3)
        else spawn_tank(TANKS, "enemy", 1) end
    end
    if G.wave_kills >= 5 + G.wave * 2 and alive == 0 then
        start_wave()
    end
end

------------------------------------------------------------------ player damage / camera
function damage_player(n)
    if P.invuln > 0 or G.state ~= "play" then return end
    P.invuln = 2.0
    P.shake = 0.7
    G.lives = G.lives - (n or 1)
    explode(P.x, P.z, true)
    sfx("playerdie")
    flash_at(P.x, 2, P.z, { 1, 0.3, 0.1 }, 100, 0.6, 20)
    if G.lives <= 0 then
        G.state = "over"
        G.banner = { text = "", sub = "", t = 99, dur = 0 }
        sfx("gameover")
        set_menu({ { label = "PLAY AGAIN", act = "play" }, { label = "TITLE", act = "title" } })
    else
        -- respawn near origin offset
        local a = rr(0, TAU)
        P.x, P.z = cos(a) * 15, sin(a) * 15
        P.yaw = aim_yaw(P.x, P.z, 0, 0)
        place_tank(P.tank, P.x, P.z, P.yaw)
        G.banner = { text = "TANK DESTROYED", sub = G.lives .. " REMAINING", t = 0, dur = 2.0 }
    end
end

local CAM_SHAKE = { x = 0, y = 0 }
local function update_camera(dt)
    local eye_h = 2.15
    local look_d = 40
    local sx = CAM_SHAKE.x * SHAKE_SCALE
    local sy = CAM_SHAKE.y * SHAKE_SCALE
    if P.shake > 0 then
        P.shake = P.shake - dt
        CAM_SHAKE.x = rr(-0.25, 0.25) * P.shake
        CAM_SHAKE.y = rr(-0.2, 0.2) * P.shake
    else
        CAM_SHAKE.x = damp(CAM_SHAKE.x, 0, 8, dt)
        CAM_SHAKE.y = damp(CAM_SHAKE.y, 0, 8, dt)
    end
    local ex = P.x + sx
    local ey = eye_h + sy
    local ez = P.z
    -- slight rearward offset so barrel tip is visible-ish; classic BZ is pure FP
    local bx = ex - sin(P.yaw) * 0.15
    local bz = ez - cos(P.yaw) * 0.15
    cam:set_position(vec3(bx, ey, bz))
    cam:look_at(vec3(ex + sin(P.yaw) * look_d, ey - 0.5, ez + cos(P.yaw) * look_d))
    EYE.x, EYE.z = bx, bz; update_backdrop()
    set_point(L.player, vec3(P.x, 1.5, P.z), vec3(0.45, 0.7, 0.4), G.state == "play" and 18 or 8, 14)
end

local MOUSE_BASE, MOUSE_SMOOTH, TURN_CAP = 0.0022, 16, 6.0   -- rad per pixel at 100%, easing rate (1/s), max rad/s
local function update_player(dt, control)
    if not P.tank or not P.tank.alive then return end
    local thrust, mdx = 0, 0
    if control then
        if kdown("Up") or kdown("W") then thrust = thrust + 1 end
        if kdown("Down") or kdown("S") then thrust = thrust - 1 end
        -- turning is mouse-only (cursor is locked in relative mode during play)
        local ok, md = pcall(input.get_mouse_delta)
        if ok and md and md.x then mdx = md.x end
        hw_mdx = mdx
        if G.vmdx then mdx = G.vmdx end          -- automation
    end
    -- smooth mouse turning: the per-frame delta becomes a target turn RATE (rad/s), and the actual
    -- rate eases toward it exponentially (~60 ms), so uneven mouse reports / frame times never step.
    local sens = MOUSE_BASE * (0.25 + 1.5 * ((SET and SET:get("mouse_sens")) or 0.5))
    local want_w = clamp(-mdx * sens / max(dt, 1e-3), -TURN_CAP, TURN_CAP)
    P.turn = damp(P.turn, want_w, MOUSE_SMOOTH, dt)
    if abs(P.turn) < 1e-4 and mdx == 0 then P.turn = 0 end
    local max_spd = 18
    local want = thrust * max_spd
    P.speed = damp(P.speed, want, 4.5, dt)
    P.yaw = P.yaw + P.turn * dt
    local nx = P.x + sin(P.yaw) * P.speed * dt
    local nz = P.z + cos(P.yaw) * P.speed * dt
    if abs(nx) < WORLD and abs(nz) < WORLD and not obstacle_hit(nx, nz, 2.2) then
        P.x, P.z = nx, nz
    else
        P.speed = P.speed * 0.3
    end
    place_tank(P.tank, P.x, P.z, P.yaw)
    -- tread scroll fake via slight bob on glow
    if P.tank.glow then
        P.tank.glow:set_position(vec3(0, 0, 2.25 + 0.02 * sin(G.t * 30)))
    end
    P.fire_cd = P.fire_cd - dt
    P.invuln = max(0, P.invuln - dt)
    if control and P.fire_cd <= 0 and (pressed("Space") or G.click or (kdown("Space") and P.fire_cd <= -0.05)) then
        P.fire_cd = 0.55
        local bx = P.x + sin(P.yaw) * 3.0
        local bz = P.z + cos(P.yaw) * 3.0
        spawn_shell(SHELLS, bx, 1.6, bz, P.yaw, 55, true)
        sfx("shoot")
        flash_at(bx, 1.7, bz, { 1.0, 0.65, 0.25 }, 60, 0.18, 9)
        orb_flash(bx, 1.7, bz)
        set_point(L.muzzle, vec3(bx, 1.7, bz), vec3(1, 0.6, 0.2), 70, 10)
        P.shake = max(P.shake, 0.18)
        -- dust kick
        burst(P.x, 0.2, P.z, { c0 = vec4(0.4, 0.32, 0.18, 0.7), c1 = vec4(0.2, 0.15, 0.08, 0),
            count = 10, smin = 0.1, smax = 0.3, lmin = 0.3, lmax = 0.7, radius = 0.8, spread = 4,
            vel = vec3(-sin(P.yaw)*2, 1, -cos(P.yaw)*2) })
    end
    if L.muzzle then
        -- decay muzzle light
        local ok, lights_list = pcall(lights.get_point_lights)
    end
end

------------------------------------------------------------------ collisions player shells -> enemies
local function shell_hits_enemies(s)
    local function check(pool, kind, rad)
        for _, e in ipairs(pool) do
            if e.alive and len2(s.x - e.x, s.z - e.z) < rad then
                e.hp = e.hp - 1
                sfx("hit")
                flash_at(e.x, 1.5, e.z, { 1, 0.5, 0.2 }, 40, 0.25, 8)
                burst(e.x, 1.5, e.z, { c0 = vec4(1, 0.8, 0.3, 1), c1 = vec4(0.5, 0.1, 0, 0),
                    count = 20, smin = 0.05, smax = 0.15, radius = 0.3, spread = 16 })
                if e.hp <= 0 then kill_enemy(e, kind) end
                return true
            end
        end
    end
    if check(TANKS, "enemy", 2.4) then return true end
    if check(SUPERS, "super", 2.8) then return true end
    if check(SAUCERS, "saucer", 2.6) then return true end
    if check(MISSILES, "missile", 1.8) then return true end
    return false
end
local function enemy_shell_hits_player(s)
    if P.invuln > 0 then return false end
    if len2(s.x - P.x, s.z - P.z) < 2.2 then
        damage_player(1)
        return true
    end
    return false
end

------------------------------------------------------------------ HUD / menus
local HUD = "hud"
runtime_ui.show(HUD); runtime_ui.set_screen_overlay(HUD, true)
KK.NONE = { 0, 0, 0, 0 }
KK.AMBER = { 1.0, 0.75, 0.25, 1 }
KK.GREEN = { 0.35, 0.95, 0.45, 1 }
KK.WHITE = { 0.95, 0.95, 0.9, 1 }
KK.RED = { 1.0, 0.3, 0.22, 1 }
KK.DIM = { 0.55, 0.65, 0.55, 1 }
local cache = {}
local function upd(id, key, q) if cache[id] == key then return end; cache[id] = key; runtime_ui.set_quad(HUD, id, q) end
local function text(id, label, x, y, w, h, fs, col, align, vis)
    vis = vis ~= false
    local key = label .. "|" .. floor(x) .. "|" .. floor(y) .. "|" .. tostring(vis) .. "|" ..
        string.format("%.2f|%.2f|%.2f%.2f%.2f", col[4] or 1, fs, col[1], col[2], col[3])
    upd(id, key, { x = x, y = y, w = w, h = h, z = 10, style = "text", label = label, fill = KK.NONE, border = KK.NONE,
        text_color = col, font_scale = fs, align_h = align or "center", align_v = "middle", no_input = true, visible = vis })
end
local function panel(id, x, y, w, h, vis, fill, border, z, input)
    vis = vis ~= false
    local key = floor(x) .. "|" .. floor(y) .. "|" .. floor(w) .. "|" .. floor(h) .. "|" .. tostring(vis) .. "|" ..
        table.concat(fill, ",") .. table.concat(border or KK.NONE, ",")
    upd(id, key, { x = x, y = y, w = w, h = h, z = z or 5, style = "text", label = "", fill = fill, border = border or KK.NONE,
        corner_radius = 10, no_input = not input, visible = vis })
end
local function ui_state(id) local ok, s = pcall(runtime_ui.get_state, HUD, id); if ok then return s end end

local MENU = { items = {}, sel = 1 }
function set_menu(items) MENU.items, MENU.sel = items, 1 end
local function draw_menu(vis, y0)
    local s = SH / 1080
    for i = 1, 4 do
        local it = MENU.items[i]
        local v = vis and it ~= nil
        local sel = v and MENU.sel == i
        local x, w, h = SW / 2 - 220 * s, 440 * s, 64 * s
        local y = y0 + (i - 1) * 78 * s
        panel("mi_bg" .. i, x, y, w, h, v, sel and { 0.55, 0.35, 0.08, 0.45 } or { 0.04, 0.05, 0.04, 0.65 },
            sel and { 1.0, 0.75, 0.3, 0.95 } or { 0.4, 0.55, 0.35, 0.5 }, 20, true)
        text("mi_tx" .. i, v and it.label or "", x, y, w, h, (sel and 1.65 or 1.4) * s,
            sel and KK.WHITE or { 0.75, 0.85, 0.7, 1 }, "center", v)
    end
end
local function menu_input()
    if #MENU.items == 0 then return nil end
    for i = 1, #MENU.items do
        local st = ui_state("mi_bg" .. i)
        if st and st.hovered and G.mouse_moved then MENU.sel = i end
        if st and st.clicked then MENU.sel = i; return MENU.items[i].act end
    end
    if pressed("Up") or pressed("W") then MENU.sel = (MENU.sel - 2) % #MENU.items + 1; sfx("click") end
    if pressed("Down") or pressed("S") then MENU.sel = MENU.sel % #MENU.items + 1; sfx("click") end
    if pressed("Return") or pressed("Space") then return MENU.items[MENU.sel].act end
end

-- radar blips as UI quads
local function draw_radar(vis)
    local s = SH / 1080
    local rw, rh = 200 * s, 200 * s
    local rx, ry = SW - rw - 36 * s, SH - rh - 36 * s
    panel("radar_bg", rx, ry, rw, rh, vis, { 0.02, 0.06, 0.03, 0.72 }, { 0.3, 0.7, 0.35, 0.7 }, 8)
    panel("radar_cross_h", rx + 10 * s, ry + rh * 0.5 - 1, rw - 20 * s, 2, vis, { 0.2, 0.5, 0.25, 0.35 }, KK.NONE, 9)
    panel("radar_cross_v", rx + rw * 0.5 - 1, ry + 10 * s, 2, rh - 20 * s, vis, { 0.2, 0.5, 0.25, 0.35 }, KK.NONE, 9)
    text("radar_t", "RADAR", rx, ry - 28 * s, rw, 28 * s, 0.9 * s, KK.GREEN, "center", vis)
    local scale = (rw * 0.45) / 90
    local cx, cy = rx + rw * 0.5, ry + rh * 0.5
    -- player heading tick
    local hx = cx + sin(0) * 0  -- player always center; world relative
    panel("radar_me", cx - 4 * s, cy - 4 * s, 8 * s, 8 * s, vis, { 0.4, 1.0, 0.5, 1 }, KK.NONE, 11)
    local function blip(id, ex, ez, col, show)
        local dx, dz = ex - P.x, ez - P.z
        -- rotate into player frame
        local lx = dx * cos(P.yaw) - dz * sin(P.yaw)
        local lz = dx * sin(P.yaw) + dz * cos(P.yaw)
        local px = cx + lx * scale
        local py = cy - lz * scale
        local on = show and abs(lx) < 90 and abs(lz) < 90
        panel(id, px - 3 * s, py - 3 * s, 6 * s, 6 * s, on and vis, col, KK.NONE, 12)
    end
    local bi = 0
    local function add_blips(pool, col)
        for _, e in ipairs(pool) do
            bi = bi + 1
            blip("rb" .. bi, e.x, e.z, col, e.alive)
        end
    end
    add_blips(TANKS, { 1.0, 0.35, 0.2, 1 })
    add_blips(SUPERS, { 0.3, 0.7, 1.0, 1 })
    add_blips(SAUCERS, { 0.5, 1.0, 0.6, 1 })
    add_blips(MISSILES, { 1.0, 0.85, 0.2, 1 })
    for i = bi + 1, 20 do panel("rb" .. i, 0, 0, 4, 4, false, KK.NONE, KK.NONE, 12) end
end

local function draw_reticle(vis)
    local s = SH / 1080
    local cx, cy = SW * 0.5, SH * 0.48
    panel("ret_h", cx - 28 * s, cy - 1, 56 * s, 2, vis, { 0.9, 0.85, 0.4, 0.85 }, KK.NONE, 15)
    panel("ret_v", cx - 1, cy - 28 * s, 2, 56 * s, vis, { 0.9, 0.85, 0.4, 0.85 }, KK.NONE, 15)
    panel("ret_box", cx - 10 * s, cy - 10 * s, 20 * s, 20 * s, vis, KK.NONE, { 1.0, 0.8, 0.3, 0.7 }, 15)
end

local function draw_hud(dt)
    local s = SH / 1080
    local st = G.state
    local title = st == "title"
    local play = st == "play" or st == "paused"
    local over = st == "over"
    local pause = st == "paused"
    -- score / lives
    text("score_t", "SCORE", 36 * s, 28 * s, 280 * s, 36 * s, 1.1 * s, KK.AMBER, "left", play or over)
    text("score", tostring(G.score), 36 * s, 64 * s, 320 * s, 60 * s, 2.4 * s, KK.WHITE, "left", play or over)
    text("hi_t", "HIGH", 36 * s, 140 * s, 280 * s, 32 * s, 1.0 * s, KK.DIM, "left", play or title or over)
    text("hi", tostring(G.hiscore), 36 * s, 172 * s, 280 * s, 44 * s, 1.6 * s, KK.AMBER, "left", play or title or over)
    text("wave_t", "WAVE", SW - 220 * s, 28 * s, 180 * s, 36 * s, 1.1 * s, KK.GREEN, "right", play)
    text("wave", tostring(G.wave), SW - 220 * s, 64 * s, 180 * s, 56 * s, 2.2 * s, KK.WHITE, "right", play)
    local lives_str = string.rep("T ", max(0, G.lives))
    text("lives_t", "TANKS", 36 * s, 240 * s, 280 * s, 32 * s, 1.0 * s, KK.DIM, "left", play)
    text("lives", lives_str, 36 * s, 272 * s, 280 * s, 40 * s, 1.4 * s, KK.GREEN, "left", play)
    text("ctl", "W/S DRIVE   MOUSE TURN   SPACE / CLICK FIRE   ESC PAUSE   M MUTE",
        0, SH - 40 * s, SW, 36 * s, 0.95 * s, { 0.6, 0.7, 0.55, 0.75 }, "center", play and not pause)
    draw_radar(play and not pause)
    draw_reticle(play and not pause)
    -- banner
    local b = G.banner or { text = "", sub = "", t = 99, dur = 0 }
    b.t = (b.t or 0) + dt
    local bvis = b.t < b.dur and (play or over)
    local ba = bvis and min(1, b.t * 5, (b.dur - b.t) * 3) or 0
    text("banner", b.text or "", 0, SH * 0.38, SW, 90 * s, 3.2 * s, { 1, 0.75, 0.3, ba }, "center", bvis)
    text("banner2", b.sub or "", 0, SH * 0.38 + 85 * s, SW, 50 * s, 1.5 * s, { 0.6, 0.9, 0.55, ba }, "center", bvis and (b.sub or "") ~= "")

    -- title screen
    text("title", "Battlezone", 0, SH * 0.12, SW, 140 * s, 5.2 * s, { 0.95, 0.78, 0.35, 1 }, "center", title)
    text("title2", "Remix", 0, SH * 0.26, SW, 70 * s, 2.6 * s, { 0.45, 0.85, 0.5, 1 }, "center", title)
    text("tt0", "FIRST-PERSON TANK COMBAT", 0, SH * 0.36, SW, 40 * s, 1.2 * s, KK.DIM, "center", title)
    text("tt1", "1000  ENEMY TANK", SW * 0.35, SH * 0.42, 500 * s, 40 * s, 1.3 * s, KK.AMBER, "left", title)
    text("tt2", "2000  MISSILE", SW * 0.35, SH * 0.47, 500 * s, 40 * s, 1.3 * s, KK.AMBER, "left", title)
    text("tt3", "3000  SUPER TANK", SW * 0.35, SH * 0.52, 500 * s, 40 * s, 1.3 * s, KK.AMBER, "left", title)
    text("tt4", "5000  SAUCER", SW * 0.35, SH * 0.57, 500 * s, 40 * s, 1.3 * s, KK.AMBER, "left", title)
    text("tctl", "W / S  DRIVE      MOUSE  TURN      SPACE / CLICK  FIRE      ESC  PAUSE      M  MUTE",
        0, SH * 0.92, SW, 40 * s, 0.95 * s, { 0.7, 0.8, 0.65, 0.85 }, "center", title)

    panel("dim", 0, 0, SW, SH, pause or over, { 0.02, 0.03, 0.02, 0.55 }, KK.NONE, 2)
    text("pause", "PAUSED", 0, SH * 0.22, SW, 120 * s, 4.0 * s, KK.AMBER, "center", pause)
    text("over", "GAME OVER", 0, SH * 0.16, SW, 130 * s, 4.4 * s, KK.RED, "center", over)
    text("over2", (G.newhi and "NEW HIGH SCORE  " or "SCORE  ") .. tostring(G.score), 0, SH * 0.32, SW, 60 * s, 2.0 * s, KK.AMBER, "center", over)
    text("over3", "WAVE " .. tostring(G.wave) .. "   KILLS " .. tostring(G.kills or 0), 0, SH * 0.40, SW, 50 * s, 1.4 * s, KK.GREEN, "center", over)
    draw_menu(title or pause or over, title and SH * 0.64 or SH * 0.52)
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
                defaults = { master = 0.5, mouse_sens = 0.5 },
                extra_rows = { { id = "mouse_sens", label = "MOUSE SENSITIVITY", kind = "slider", section = "CONTROLS" } },
                theme = { accent = { 0.95, 0.75, 0.3, 1 }, accent2 = { 0.35, 0.85, 0.45, 1 } },
            })
            if ok2 then SET = s else pe_log("[Battlezone] settings init failed: " .. tostring(s)) end
        else pe_log("[Battlezone] settings load failed: " .. tostring(mod)) end
    end
end

------------------------------------------------------------------ input
local prev = {}
G.vkeys = {}
function kdown(k) if G.vkeys[k] then return true end local ok, r = pcall(input.is_key_down_raw, k); return ok and r end
function pressed(k) local d = kdown(k); local p = prev[k]; prev[k] = d; return d and not p end
local WATCH = { "Left", "Right", "A", "D", "Up", "Down", "W", "S", "Space", "Return", "Escape", "P", "M" }
local function latch() for _, k in ipairs(WATCH) do prev[k] = kdown(k) end end
local mouse_prev_down = false
local function mouse_down() local ok, d = pcall(input.is_left_mouse_down); return (ok and d) or G.vkeys.Click end
local function mouse_clicked() local d = mouse_down(); local c = d and not mouse_prev_down; mouse_prev_down = d; return c end
local mouse_last_x, mouse_last_y = nil, nil

------------------------------------------------------------------ title attract camera
local ATTRACT = { yaw = 0, elev = 0 }
local function update_attract(dt)
    ATTRACT.yaw = ATTRACT.yaw + dt * 0.25
    ATTRACT.elev = 12 + 3 * sin(G.t * 0.4)
    local r = 55
    local cx, cz = cos(ATTRACT.yaw) * r, sin(ATTRACT.yaw) * r
    cam:set_position(vec3(cx, ATTRACT.elev, cz))
    cam:look_at(vec3(0, 2, 0))
    EYE.x, EYE.z = cx, cz; update_backdrop()
    -- showcase player tank at origin
    if P.tank then
        P.tank.alive = true
        place_tank(P.tank, 0, 0, G.t * 0.4, 1.15)
        if P.tank.turret then P.tank.turret:set_rotation(vec3(0, 20 * sin(G.t), 0)) end
    end
    -- showcase enemies orbiting
    for i, e in ipairs(TANKS) do
        if i <= 3 then
            e.alive = true
            local a = G.t * 0.3 + i * TAU / 3
            place_tank(e, cos(a) * 18, sin(a) * 18, a + PI, 1.0)
        else hide_ent(e) end
    end
    if SUPERS[1] then
        SUPERS[1].alive = true
        place_tank(SUPERS[1], cos(-G.t * 0.2) * 28, sin(-G.t * 0.2) * 28, -G.t * 0.2 + PI, 1.25)
    end
    if SAUCERS[1] then
        local e = SAUCERS[1]; e.alive = true
        e.x, e.y, e.z = cos(G.t * 0.5) * 22, 8 + sin(G.t) * 2, sin(G.t * 0.5) * 22
        e.root:set_position(vec3(e.x, e.y, e.z))
        e.root:set_rotation(vec3(10, math.deg(G.t * 40), 5))
        if e.rim then e.rim:set_rotation(vec3(0, math.deg(G.t * 90), 0)) end
    end
end

------------------------------------------------------------------ game flow
local function clear_enemies()
    for _, e in ipairs(TANKS) do hide_ent(e) end
    for _, e in ipairs(SUPERS) do hide_ent(e) end
    for _, e in ipairs(SAUCERS) do hide_ent(e) end
    for _, e in ipairs(MISSILES) do hide_ent(e) end
    for _, s in ipairs(SHELLS) do s.alive = false; s.root:set_position(HIDE) end
    for _, s in ipairs(ENEMY_SHELLS) do s.alive = false; s.root:set_position(HIDE) end
end

G.P = P
local function new_game()
    clear_enemies()
    G.score = 0; G.lives = 3; G.wave = 0; G.kills = 0; G.newhi = false; G.wave_kills = 0
    P.x, P.z, P.yaw, P.speed, P.turn = 0, 0, 0, 0, 0
    P.fire_cd, P.invuln, P.shake = 0, 1.5, 0
    P.tank.alive = true
    place_tank(P.tank, 0, 0, 0, 1.0)
    G.state = "play"
    start_wave()
    -- seed a couple enemies
    spawn_tank(TANKS, "enemy", 1)
    spawn_tank(TANKS, "enemy", 1)
end

local function to_title()
    if jev then
        jev:begin_human()
    end
    clear_enemies()
    G.state = "title"
    G.banner = { text = "", sub = "", t = 99, dur = 0 }
    set_menu({
        { label = "PLAY", act = "play" },
        { label = "Jev", act = "jev" },
        { label = "SETTINGS", act = "settings" },
        { label = "QUIT", act = "quit" },
    })
end

local function do_menu_action(act)
    if act == "play" then
        jev:begin_human()
        new_game()
    elseif act == "jev" then
        if not jev:start() then
            local err = jev:error()
            if not err or err == "" then
                err = "Jev could not start"
            end
            G.banner = { text = "JEV", sub = err, t = 0, dur = 8 }
            pe_log("[Battlezone] " .. err)
        end
    elseif act == "resume" then G.state = G.paused_from or "play"
    elseif act == "settings" then
        if SET then G.in_settings = true; SET:open(function() G.in_settings = false end) end
    elseif act == "title" then to_title()
    elseif act == "quit" then pcall(engine.quit) end
end

local function update_visuals(dt)
    flush_mats()
    update_flashes(dt)
    update_shards(dt)
    update_rings(dt)
    update_orbs(dt)
    -- fade muzzle light
    if L.muzzle then set_point(L.muzzle, vec3(P.x + sin(P.yaw)*3, 1.7, P.z + cos(P.yaw)*3), vec3(1,0.6,0.2), 0, 1) end
end

-- Hardware edges only. G.vmdx / G.vkeys are the Jev hold and must not count.
local HUMAN_KEYS = { "Up", "Down", "W", "S", "Space" }
local hw_prev = {}
local human_edge_now = false
local swallow_mouse = 0

local function sample_human()
    local edge = false
    for i = 1, #HUMAN_KEYS do
        local key = HUMAN_KEYS[i]
        local ok, down = pcall(input.is_key_down_raw, key)
        down = ok and down == true
        if down and not hw_prev[key] then
            edge = true
        end
        hw_prev[key] = down
    end

    local ok_click, click = pcall(input.is_left_mouse_down)
    click = ok_click and click == true
    if click and not hw_prev.Click then
        edge = true
    end
    hw_prev.Click = click

    if swallow_mouse > 0 then
        swallow_mouse = swallow_mouse - 1
    elseif hw_mdx ~= 0 then
        edge = true
    end

    local live = G.state == "play" and not (SET and SET:is_open())
    human_edge_now = live and edge
end

local function clear_hold()
    G.vmdx = nil
    G.vkeys.Up = nil
    G.vkeys.Down = nil
    G.vkeys.W = nil
    G.vkeys.S = nil
    G.vkeys.Space = nil
    G.space_pulse = nil
    G.space_live = nil
end

local function arm_space()
    if not G.space_pulse then
        return
    end

    G.vkeys.Space = true
    G.space_pulse = nil
    G.space_live = true
    prev.Space = false
end

local function release_space()
    if not G.space_live then
        return
    end

    G.vkeys.Space = nil
    G.space_live = nil
end

local function update(dt)
    dt = min(dt, 0.05)
    sample_human()
    jev:tick(dt)
    hw_mdx = 0
    G.t = G.t + dt
    local okS, sz = pcall(runtime_ui.get_surface_size)
    if okS and sz then SW, SH = sz.width or SW, sz.height or SH end

    if G.state == "boot" then
        if G.t > 0.4 then to_title(); pe_log("[Battlezone] ready") end
        update_visuals(dt); draw_hud(dt); latch(); return
    end

    if SET then
        PSCALE = SET:particle_scale() or 1
        SHAKE_SCALE = SET:shake_scale() or 1
        if SET:update(dt) then latch(); mouse_clicked(); update_visuals(dt); draw_hud(dt); return end
    end

    -- mouse move tracking for menu hover
    local okm, mp = pcall(input.get_mouse_position)
    if okm and mp and mp.x then
        if mouse_last_x and (abs(mp.x - mouse_last_x) + abs(mp.y - (mouse_last_y or 0)) > 2) then G.mouse_moved = true end
        mouse_last_x, mouse_last_y = mp.x, mp.y
    end
    G.click = mouse_clicked()
    if pressed("M") then if SET then SET:toggle_mute() end end

    local st = G.state
    if st == "title" then
        update_attract(dt)
        local act = menu_input()
        if act then do_menu_action(act) end
    elseif st == "play" then
        if pressed("Escape") or pressed("P") then
            G.paused_from = "play"; G.state = "paused"
            set_menu({ { label = "RESUME", act = "resume" }, { label = "SETTINGS", act = "settings" }, { label = "QUIT TO TITLE", act = "title" } })
        else
            arm_space()
            update_player(dt, true)
            for _, e in ipairs(TANKS) do update_enemy_tank(e, dt, false) end
            for _, e in ipairs(SUPERS) do update_enemy_tank(e, dt, true) end
            for _, e in ipairs(SAUCERS) do update_saucer(e, dt) end
            for _, e in ipairs(MISSILES) do update_missile_ent(e, dt) end
            update_shells(SHELLS, dt, shell_hits_enemies)
            update_shells(ENEMY_SHELLS, dt, enemy_shell_hits_player)
            wave_spawner(dt)
            update_camera(dt)
        end
    elseif st == "paused" then
        if pressed("Escape") or pressed("P") then G.state = G.paused_from or "play"
        else
            local act = menu_input()
            if act then do_menu_action(act) end
        end
        update_camera(dt)
    elseif st == "over" then
        update_camera(dt)
        local act = menu_input()
        if act then do_menu_action(act) end
    end
    update_visuals(dt)
    draw_hud(dt)
    release_space()
    latch()
    G.mouse_moved = false
    -- hide + lock the cursor only while actually playing; menus (title/pause/settings/over) get it back
    local want_lock = G.state == "play" and not (SET and SET:is_open())
    if want_lock ~= G.mouse_locked then
        G.mouse_locked = want_lock
        pcall(input.set_relative_mouse, want_lock)
        pcall(input.get_mouse_delta)   -- drop the jump accumulated while switching
        hw_mdx = 0
        swallow_mouse = 2
        P.turn = 0
    end
end

-- Positive is the same sign as a rightward mouse delta. update_player turns that
-- held delta into a rad/s rate (delta * sens / dt), capped at TURN_CAP.
local JEV_TURN = 32

local function set_thrust(dir)
    G.vkeys.Up = (dir > 0) or nil
    G.vkeys.Down = (dir < 0) or nil
    G.vkeys.W = nil
    G.vkeys.S = nil
end

local function pulse_space()
    G.space_pulse = true
end

local function apply_jev(id)
    if id == "left" then
        G.vmdx = -JEV_TURN
    elseif id == "right" then
        G.vmdx = JEV_TURN
    elseif id == "straight" then
        G.vmdx = 0
    elseif id == "forward" then
        set_thrust(1)
    elseif id == "back" then
        set_thrust(-1)
    elseif id == "stop" then
        set_thrust(0)
    elseif id == "fire" then
        pulse_space()
    elseif id == "forward_fire" then
        set_thrust(1)
        pulse_space()
    end
end

local function nearest_enemy()
    local best, kind, best_d
    local function consider(pool, pool_kind)
        for _, e in ipairs(pool) do
            if e.alive then
                local dx = e.x - P.x
                local dz = e.z - P.z
                local d = dx * dx + dz * dz
                if not best or d < best_d then
                    best = e
                    kind = pool_kind
                    best_d = d
                end
            end
        end
    end

    consider(TANKS, "enemy")
    consider(SUPERS, "super")
    consider(SAUCERS, "saucer")
    consider(MISSILES, "missile")
    return best, kind
end

local jev_source = fs.read("Scripts/jev_auto.lua")
assert(jev_source, "Missing Scripts/jev_auto.lua")
local JevAuto = assert(load(jev_source, "@Scripts/jev_auto.lua", "t", _ENV))()

jev = JevAuto.attach({
    port = 9130,
    id = "battlezone",
    description = "First-person tank combat. The offered action turns toward the nearest enemy, or drives and fires once lined up. Prefer the higher action score.",
    playing = function()
        if G.state ~= "play" then
            return false
        end
        if SET and SET:is_open() then
            return false
        end
        return true
    end,
    terminal = function()
        return G.state == "over"
    end,
    score = function()
        return G.score or 0
    end,
    human_edge = function()
        return human_edge_now
    end,
    observe = function()
        local enemy, kind = nearest_enemy()
        local obs = {
            x = P.x,
            z = P.z,
            yaw = P.yaw,
            score = G.score or 0,
            enemy_x = 0,
            enemy_z = 0,
            enemy_kind = "none",
        }
        if enemy then
            obs.enemy_x = enemy.x
            obs.enemy_z = enemy.z
            obs.enemy_kind = kind
        end
        return obs
    end,
    actions = function()
        local enemy = nearest_enemy()
        if not enemy then
            return { { id = "forward", description = "No enemy. Drive forward.", score = 1 } }
        end
        local dx = enemy.x - P.x
        local dz = enemy.z - P.z
        local want = math.atan2(dx, dz)
        local err = math.atan2(math.sin(want - P.yaw), math.cos(want - P.yaw))
        if err > 0.18 then
            return { { id = "left", description = "Turn left toward the enemy.", score = err } }
        end
        if err < -0.18 then
            return { { id = "right", description = "Turn right toward the enemy.", score = -err } }
        end
        return { { id = "forward_fire", description = "Facing the enemy. Drive and fire.", score = 1 } }
    end,
    apply = function(id)
        apply_jev(id)
    end,
    reset = function(seed)
        math.randomseed(seed)
        clear_hold()
        new_game()
    end,
    on_human = function()
        clear_hold()
    end,
})

local function init()
    build_lights(); build_world(); build_debris(); build_rings(); build_orbs()
    build_player(); build_pools()
    paint_templates()
    pcall(audio.set_master_volume, 0.5)
    if SET then SET:apply() end
    G.state = "boot"
    pe_log("[Battlezone] init")
end
init()
hooks { update = update }

-- MCP helpers
function G.sim(sec, keys)
    G.vkeys = keys or {}
    for _ = 1, floor(sec * 60) do update(1 / 60) end
    G.vkeys = {}
end
G.new_game = new_game; G.update = update; G.SET = SET
G.to_title = to_title
G.damage_player = damage_player
function G.clear_invuln() P.invuln = 0 end
function G.close_settings()
    if SET then SET:close() end
    G.in_settings = false
end

function G.force_over()
    P.invuln = 0; G.lives = 1; damage_player(1)
end
function G.force_pause()
    G.paused_from = "play"; G.state = "paused"
    set_menu({ { label = "RESUME", act = "resume" }, { label = "SETTINGS", act = "settings" }, { label = "QUIT TO TITLE", act = "title" } })
end
function G.cinematic()
    -- Put player at origin looking +Z, enemies and a saucer in view
    clear_enemies()
    G.state = "play"; G.score = G.score or 0; G.lives = 3; G.wave = max(1, G.wave); G.kills = G.kills or 0
    P.x, P.z, P.yaw, P.speed, P.invuln, P.shake, P.fire_cd = 0, 0, 0, 0, 0, 0, 0
    P.tank.alive = true; place_tank(P.tank, 0, 0, 0, 1.0)
    local function put(pool, kind, x, z, hp, sc)
        local e = free_slot(pool); if not e then return end
        e.alive = true; e.hp = hp or 1; e.cd = 99; e.ai = { t = 0 }; e.kind = kind
        place_tank(e, x, z, aim_yaw(x, z, 0, 0), sc or 1)
    end
    put(TANKS, "enemy", -8, 28, 1, 1.0)
    put(TANKS, "enemy", 10, 36, 1, 1.0)
    put(SUPERS, "super", 0, 48, 3, 1.25)
    local s = free_slot(SAUCERS)
    if s then
        s.alive = true; s.hp = 1; s.x, s.y, s.z = -14, 9, 40; s.yaw = 0; s.cd = 99; s.ai = { t = 0 }
        s.root:set_position(vec3(s.x, s.y, s.z))
    end
    local m = free_slot(MISSILES)
    if m then
        m.alive = true; m.hp = 1; m.x, m.y, m.z = 16, 1.5, 32; m.yaw = PI; m.speed = 0; m.life = 99; m.ai = { frozen = true }
        m.root:set_position(vec3(m.x, m.y, m.z)); m.root:set_rotation(vec3(0, 180, 0))
    end
    -- fire a shell for muzzle flash / projectile in frame
    spawn_shell(SHELLS, 0, 1.6, 3.2, 0, 55, true)
    flash_at(0, 1.7, 3.2, { 1.0, 0.65, 0.25 }, 70, 0.35, 10)
    orb_flash(0, 1.7, 3.2)
    update_camera(0)
end
