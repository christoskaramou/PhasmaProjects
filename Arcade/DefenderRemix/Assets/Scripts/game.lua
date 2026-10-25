-- DEFENDER REMIX  (PhasmaEngine, Lua)
-- A modernized remake of Williams' Defender (1981). Faithful core: a wrap-around planet you patrol left and right with
-- inertia, a long-range scanner, Landers that abduct Humanoids (shoot the Lander, catch the falling Humanoid and set
-- them down), Mutants born from captured Humanoids, Bombers laying mines, Pods that burst into Swarmers, Baiters that
-- hunt slow players, smart bombs, hyperspace, and a planet that explodes when every Humanoid is lost.
-- Modern visuals: cooked 3D ships and creatures, parallax mountain ranges with a glowing crest, a lit city, aurora sky,
-- engine exhaust, layered explosion particles + debris + shockwaves, dynamic point lights, TAA with soft bloom.
local PI, TAU = math.pi, math.pi * 2
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
math.randomseed(floor((engine.get_metrics and (engine.get_metrics() or {}).frame or 0) + 4321))
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local G = { state = "boot", t = 0 }
_G.DF = G

------------------------------------------------------------------ deferred materials (engine quirk: replay writes)
local _mset, _mtex, _mds = material.set, material.set_texture, material.set_double_sided
local mat_q = {}
local function qpush(f) mat_q[#mat_q + 1] = { f = f, n = 0 } end
local function mset(n, k, v) pcall(_mset, n, k, v); qpush(function() pcall(_mset, n, k, v) end) end
local function mtex(n, k, v) qpush(function() pcall(_mtex, n, k, v) end) end
local function mds(n) pcall(_mds, n, true); qpush(function() pcall(_mds, n, true) end) end
local function flush_mats()
    for i = #mat_q, 1, -1 do
        local q = mat_q[i]; q.n = q.n + 1
        if q.n == 2 or q.n == 6 then q.f() end
        if q.n >= 6 then table.remove(mat_q, i) end
    end
end
local function mlive(n, k, v) pcall(_mset, n, k, v) end
local function paint(n, base, emis, rough, metal)
    if not n then return end
    mset(n, "base_color", vec4(base[1], base[2], base[3], base[4] or 1))
    mset(n, "emissive", vec3(emis[1], emis[2], emis[3]))
    mset(n, "roughness", rough or 0.3)
    mset(n, "metallic", metal or 0.0)
end
local function sfx(name) pcall(audio.play, name .. ".wav") end

------------------------------------------------------------------ render setup (see /workspace/games/common/RENDER_SETTINGS.md)
local function S(k, v) pcall(settings.set, k, v) end
local ss = scene.add_empty_node("DefenderSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "dusk.hdr")
S("hdr", true); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false); S("dof", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.4)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", true); S("IBL_intensity", 0.7)
S("color_grading", true); S("color_grading_saturation", 1.12); S("color_grading_contrast", 1.06)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "SETTINGS", subtitle = "D E F E N D E R   R E M I X", file = "Save/settings.cfg",
    click = function() sfx("click") end, defaults = { master = 0.5 },
    theme = { accent = { 0.2, 0.75, 0.7, 1 }, accent2 = { 0.85, 0.4, 0.25, 1 }, text = { 0.72, 0.78, 0.86, 1 }, selected_text = { 0.85, 0.9, 0.95, 1 } } })
SET:apply()
local set_open = false

------------------------------------------------------------------ world + camera
local WW = 480.0                  -- world circumference (wraps)
local GROUND, TOP = -13.0, 10.5   -- playfield floor (terrain) and ceiling
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1600, surf.height or 900
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local FOVX = 1.0
local CAMZ = 0
do local half_h = 15.0; CAMZ = half_h * (SW / max(1, SH)) / math.tan(FOVX * 0.5) end
pcall(function() cam:set_fov(math.deg(FOVX)) end)
local VIEW_HW = CAMZ * math.tan(FOVX * 0.5)      -- half view width at z=0
local function wrapd(d) d = d % WW; if d > WW / 2 then d = d - WW end; return d end
local function wrapx(x) return x % WW end
local CAMX = 0                    -- unbounded camera x
local function sx(x) return CAMX + wrapd(x - CAMX) end   -- world x -> render x near the camera

------------------------------------------------------------------ templates -> clones
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[Defender] missing template " .. name); return nil end
    TPL[name] = { node = n, mesh = n:get_mesh_refs()[1] }
    return TPL[name]
end
local seq = 0
local HIDE = vec3(0, -1000, 0)
local function clone(name, pos, scale, parent)
    local t = tpl(name); seq = seq + 1
    local n = scene.add_empty_node(name .. "_c" .. seq)
    if t and t.mesh then n:add_mesh_ref(t.mesh) end
    if parent then n:set_parent(parent) end
    n:set_position(pos or HIDE)
    if scale then n:set_scale(scale) end
    return n
end
local function prim(kind, pos, scale)
    seq = seq + 1
    local n = scene.add_empty_node(kind .. "_p" .. seq)
    scene.attach_primitive(n, kind)
    n:set_position(pos); n:set_scale(scale)
    return n
end
local function tnode(name) local t = tpl(name); return t and t.node end

------------------------------------------------------------------ palette {base, emissive, rough, metal}
local PAL = {
    ship = { body = { { .72, .75, .8 }, { .04, .04, .06 }, .2, .45 }, metal = { { .3, .33, .4 }, { 0, 0, 0 }, .22, .9 },
        accent = { { 1, .35, .08 }, { 1.1, .3, .05 }, .3, .2 }, glass = { { .2, .7, 1 }, { .15, .6, 1.1 }, .05, 0.2 },
        glow = { { .4, .8, 1 }, { 1.2, 2.5, 4.5 }, .3, 0 } },
    lander = { body = { { .15, .85, .3 }, { .04, .35, .1 }, .3, .4 }, accent = { { .7, .75, .8 }, { .05, .06, .08 }, .25, .9 },
        eye = { { 1, .85, .2 }, { .9, .6, .08 }, .1, 0.3 }, glow = { { 1, .4, .1 }, { 2.5, .7, .15 }, .2, 0 } },
    mutant = { body = { { .8, .1, .9 }, { .35, .04, .4 }, .25, .3 }, accent = { { .3, 1, .4 }, { .4, 2.2, .5 }, .2, .3 },
        eye = { { 1, 1, 1 }, { 2.5, 2.5, 2 }, .1, 0 } },
    bomber = { body = { { .55, .2, .85 }, { .25, .05, .45 }, .3, .5 }, accent = { { 1, .8, .3 }, { 1.4, .9, .2 }, .2, .8 },
        glow = { { 1, .3, .6 }, { 2, .4, 1.2 }, .2, 0 } },
    baiter = { body = { { .2, .9, .25 }, { .1, .6, .15 }, .2, .6 }, accent = { { .9, .95, 1 }, { .3, .35, .4 }, .15, .8 },
        glow = { { 1, 1, .4 }, { 2.5, 2.5, .6 }, .2, 0 } },
    pod = { body = { { .45, .1, .6 }, { .5, .08, .7 }, .35, .2 }, accent = { { 1, .3, .3 }, { 1.5, .3, .25 }, .2, .1 } },
    swarmer = { body = { { 1, .3, .1 }, { 1.2, .35, .05 }, .3, .3 }, glow = { { 1, .9, .3 }, { 2.5, 2, .5 }, .2, 0 } },
    human = { body = { { .95, .95, 1 }, { .15, .15, .18 }, .4, .1 }, visor = { { 1, .6, .15 }, { .6, .3, .05 }, .1, .6 },
        glow = { { .4, .9, 1 }, { 1.5, 3.5, 4.5 }, .1, 0 } },
}
local PARTS = {}
for k, ps in pairs(PAL) do PARTS[k] = {}; for p in pairs(ps) do PARTS[k][#PARTS[k] + 1] = p end end
local function paint_templates()
    for kind, parts in pairs(PAL) do
        for part, p in pairs(parts) do paint(tnode("T_" .. kind .. "_" .. part), p[1], p[2], p[3], p[4]) end
    end
end
-- a model = root node + parented cooked parts
local function make_model(kind, scale)
    seq = seq + 1
    local root = scene.add_empty_node("m_" .. kind .. seq)
    root:set_position(HIDE)
    for _, p in ipairs(PARTS[kind]) do clone("T_" .. kind .. "_" .. p, vec3(0, 0, 0), nil, root) end
    if scale then root:set_scale(vec3(scale, scale, scale)) end
    return root
end

------------------------------------------------------------------ lights
local LNODE = {}
local LIGHT_GAIN = 0.12
local function add_point() lights.add_point(); return #lights.get_point_lights() - 1 end
local function set_point(i, pos, col, inten, rad)
    pcall(lights.set_point_light, i, pos, col, inten * LIGHT_GAIN, rad)
    local n = LNODE[i]
    if n == nil then
        local l = lights.get_point_lights()[i + 1]
        n = (l and scene.find_model(l.name)) or false
        LNODE[i] = n
    end
    if n then n:set_position(pos) end
end
local L = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(-0.35, -0.5, -0.8), vec3(1.0, 0.85, 0.8), 4.0)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    L.key = addp(vec3(0, 14, 16), vec3(0.45, 0.65, 1.0), 110, 70)
    L.fill = addp(vec3(0, 4, 30), vec3(0.9, 0.9, 1.0), 160, 90)
    L.city = addp(vec3(0, -10, 8), vec3(1.0, 0.55, 0.25), 70, 40)
    L.player = addp(HIDE, vec3(0.4, 0.8, 1.0), 0, 1)
    L.laser = addp(HIDE, vec3(1, 0.5, 0.3), 0, 1)
    L.flash = {}
    for i = 1, 6 do L.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1, power = 0, rad = 6 } end
end
local flash_next = 1
local function flash(x, y, col, power, life, rad)
    local f = L.flash[flash_next]; flash_next = flash_next % #L.flash + 1
    f.t, f.life, f.x, f.y, f.col, f.power, f.rad = 0, life or 0.35, x, y, vec3(col[1], col[2], col[3]), power or 40, rad or 9
end
local function update_flashes(dt)
    for _, f in ipairs(L.flash) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = 1 - clamp(f.t / f.life, 0, 1)
            set_point(f.idx, vec3(sx(f.x), f.y, 3), f.col, f.power * k * k, f.rad)
            if f.t >= f.life then set_point(f.idx, HIDE, f.col, 0, 1) end
        end
    end
end

------------------------------------------------------------------ particles (positions are given in render space)
local function PS() return SET:particle_scale() end
local function burst(x, y, o)
    pcall(particles.emit_burst, {
        position = vec3(x, y, o.z or 0.5), velocity = o.vel or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = max(1, floor((o.count or 40) * PS())),
        size_min = o.smin or 0.05, size_max = o.smax or 0.16, life_min = o.lmin or 0.25, life_max = o.lmax or 0.7,
        spawn_radius = o.radius or 0.3, noise_strength = o.spread or 14, drag = o.drag or 2.0,
        gravity = o.grav or vec3(0, 0, 0), cleanup_delay = 3.0,
    })
end
local function hot(c, k) return vec4(c[1] * k + 0.8, c[2] * k + 0.8, c[3] * k + 0.8, 1) end
local function sparks(x, y, col, n, spread)
    burst(sx(x), y, { c0 = hot(col, 3), c1 = vec4(col[1], col[2], col[3], 0), count = n or 30, smin = 0.04, smax = 0.1,
        lmin = 0.15, lmax = 0.45, radius = 0.1, spread = spread or 26, drag = 2.5 })
end
local function new_emitter(o)
    local ok, e = pcall(particles.add_emitter, {
        position = HIDE, velocity = o.vel or vec3(0, 0, 0), gravity = o.grav or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = o.count or 300, spawn_rate = 0,
        spawn_radius = o.radius or 0.1, size_min = o.smin or 0.06, size_max = o.smax or 0.16,
        life_min = o.lmin or 0.15, life_max = o.lmax or 0.4, noise_strength = o.noise or 1.0, drag = o.drag or 1.5 })
    return ok and e or nil
end
local function emitter_at(e, x, y, z, rate, vel)
    if not e then return end
    pcall(particles.set_emitter, e, "position", vec3(x, y, z or 0))
    pcall(particles.set_emitter, e, "spawn_rate", rate * PS())
    if vel then pcall(particles.set_emitter, e, "velocity", vel) end
end

------------------------------------------------------------------ debris shards + shockwave rings (world x, wrapped at draw)
local SHARD_COL = { [0] = { .2, 1, .35 }, { 1, .2, .9 }, { .7, .3, 1 }, { 1, .45, .1 }, { 1, 1, 1 }, { .3, .8, 1 } }
local SHARDS, live_shards = {}, {}
local function build_debris()
    for c = 0, 5 do
        local col = SHARD_COL[c]
        paint(tnode("T_shard_" .. c), col, { col[1] * 2.5, col[2] * 2.5, col[3] * 2.5 }, 0.3, 0.3)
        SHARDS[c] = { next = 1 }
        for k = 1, 16 do SHARDS[c][k] = { node = clone("T_shard_" .. c, HIDE, vec3(0.4, 0.4, 0.4)), life = 0 } end
    end
end
local function shatter(slot, x, y, n, power)
    local pool = SHARDS[slot] or SHARDS[4]
    for _ = 1, floor((n or 8) * (0.4 + 0.6 * PS()) + 0.5) do
        local s = pool[pool.next]; pool.next = pool.next % #pool + 1
        local a, sp = rr(0, TAU), rr(4, 14) * (power or 1)
        s.x, s.y, s.z = x, y, rr(-0.3, 0.6)
        s.vx, s.vy, s.vz = cos(a) * sp, sin(a) * sp, rr(-3, 6)
        s.rx, s.ry, s.rz = rr(0, 360), rr(0, 360), rr(0, 360)
        s.wx, s.wy, s.wz = rr(-700, 700), rr(-700, 700), rr(-700, 700)
        s.sz = rr(0.35, 0.8); s.life = rr(0.5, 1.1)
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
            local d = math.exp(-1.6 * dt)
            s.vx, s.vy, s.vz = s.vx * d, s.vy * d - 9 * dt, s.vz * d
            s.x, s.y, s.z = s.x + s.vx * dt, s.y + s.vy * dt, s.z + s.vz * dt
            if s.y < GROUND + 0.3 then s.y = GROUND + 0.3; s.vy = abs(s.vy) * 0.4 end
            s.rx, s.ry, s.rz = s.rx + s.wx * dt, s.ry + s.wy * dt, s.rz + s.wz * dt
            local k = clamp(s.life / 0.35, 0, 1) * s.sz
            s.node:set_position(vec3(sx(s.x), s.y, s.z)); s.node:set_rotation(vec3(s.rx, s.ry, s.rz)); s.node:set_scale(vec3(k, k, k))
        end
    end
end
local RINGS, ring_next = {}, 1
local function build_rings()
    for i = 0, 7 do
        local n = clone("T_ring_" .. i, HIDE)
        paint(tnode("T_ring_" .. i), { 0, 0, 0 }, { 0, 0, 0 }, 0.5, 0)
        RINGS[#RINGS + 1] = { node = n, mat = tnode("T_ring_" .. i), t = 9, life = 1 }
    end
end
local function shockwave(x, y, col, size, life)
    local r = RINGS[ring_next]; ring_next = ring_next % #RINGS + 1
    r.x, r.y, r.col, r.size, r.t, r.life = x, y, col, size or 3, 0, life or 0.45
end
local function update_rings(dt)
    for _, r in ipairs(RINGS) do
        if r.t < r.life then
            r.t = r.t + dt
            local k = clamp(r.t / r.life, 0, 1)
            local s = 0.3 + r.size * (1 - (1 - k) ^ 3)
            r.node:set_position(vec3(sx(r.x), r.y, 0.3)); r.node:set_scale(vec3(s, s, 1 + 2 * (1 - k)))
            local f = (1 - k) ^ 2 * 4
            mlive(r.mat, "emissive", vec3(r.col[1] * f, r.col[2] * f, r.col[3] * f))
            if r.t >= r.life then r.node:set_position(HIDE) end
        end
    end
end
local shake = 0
local function add_shake(a) shake = min(1.2, shake + a) end
-- layered explosion: white core, coloured fireball, fast sparks, slow embers, debris, ring, light
local function explode(wx, y, col, slot, big)
    local x = sx(wx)
    local k = big and 1.6 or 1.0
    burst(x, y, { c0 = vec4(3.5, 3.5, 3.5, 1), c1 = vec4(col[1] * 2, col[2] * 2, col[3] * 2, 0), count = 26 * k, smin = 0.25, smax = 0.55 * k,
        lmin = 0.08, lmax = 0.22, radius = 0.25, spread = 6, drag = 4 })
    burst(x, y, { c0 = hot(col, 2.5), c1 = vec4(col[1] * 0.6, col[2] * 0.3, col[3] * 0.3, 0), count = 60 * k, smin = 0.1, smax = 0.3,
        lmin = 0.25, lmax = 0.6, radius = 0.5, spread = 18 * k, drag = 3.5 })
    burst(x, y, { c0 = vec4(3.2, 2.8, 2.0, 1), c1 = vec4(col[1] * 2, col[2] * 2, col[3] * 2, 0), count = 70 * k, smin = 0.03, smax = 0.08,
        lmin = 0.3, lmax = 0.8, radius = 0.15, spread = 40 * k, drag = 1.6 })
    burst(x, y, { c0 = vec4(1.8, 0.7, 0.25, 1), c1 = vec4(0.4, 0.05, 0.1, 0), count = 34 * k, smin = 0.05, smax = 0.12,
        lmin = 0.7, lmax = 1.4, radius = 0.6, spread = 9, drag = 1.0, grav = vec3(0, -4, 0) })
    shatter(slot or 4, wx, y, big and 12 or 7, big and 1.3 or 1)
    shockwave(wx, y, col, big and 5.5 or 3.2, big and 0.6 or 0.4)
    flash(wx, y, col, big and 120 or 60, big and 0.5 or 0.3, big and 16 or 10)
    add_shake(big and 0.45 or 0.12)
end

------------------------------------------------------------------ backdrop: aurora sky, planet, star layer, far + near mountains, city, glowing crest
local BG = { near = {}, far = {}, crest = {}, ground = {}, stars = {}, cities = {} }
local TILE = 40.0
local FAR_S, FAR_Z, NEAR_Z = 1.9, -45, -4.5
local CITY_TILES = { 1, 4, 7, 10 }     -- world tiles (0..11) that hold a city
local SKY_Z = -320
local function view_half(z) local d = CAMZ - z; local hw = d * math.tan(FOVX * 0.5); return hw, hw * SH / SW end
local function build_backdrop()
    local hw, hh = view_half(SKY_Z)
    BG.sky = prim("quad", vec3(0, hh * 0.25, SKY_Z), vec3(hw * 2.3, hh * 2.6, 1))
    paint(BG.sky, { 0, 0, 0 }, { 1.0, 1.0, 1.05 }, 1, 0); mds(BG.sky); mtex(BG.sky, "emissive", "Textures/sky.png")
    BG.planet = clone("T_planet", HIDE, vec3(34, 34, 34))
    paint(tnode("T_planet"), { 1, 1, 1 }, { 0.04, 0.02, 0.05 }, 0.75, 0); mtex(tnode("T_planet"), "base_color", "Textures/planet.png")
    paint(tnode("T_star_0"), { 1, 1, 1 }, { 2.4, 2.4, 2.8 }, 0.5, 0)
    local shw, shh = view_half(-90)
    for i = 1, 70 do
        local st = { x = rr(-shw, shw) * 1.2, y = rr(-2, shh), ph = rr(0, TAU), tw = rr(1.5, 4), s = rr(0.25, 0.55) }
        st.node = clone("T_star_0", HIDE, vec3(st.s, st.s, st.s)); BG.stars[i] = st
    end
    paint(tnode("T_mountain_far"), { .16, .1, .2 }, { .05, .02, .07 }, 0.9, 0); mtex(tnode("T_mountain_far"), "base_color", "Textures/rock.png")
    for i = 1, 4 do BG.far[i] = clone("T_mountain_far", HIDE, vec3(FAR_S, FAR_S * 1.1, FAR_S)) end
    paint(tnode("T_mountain"), { .36, .24, .25 }, { .03, .015, .02 }, 0.85, 0.05); mtex(tnode("T_mountain"), "base_color", "Textures/rock.png")
    paint(tnode("T_crest"), { .2, 1, .8 }, { .3, 1.6, 1.2 }, 0.4, 0)
    paint(tnode("T_ground"), { .16, .1, .1 }, { .01, .005, .01 }, 0.9, 0); mtex(tnode("T_ground"), "base_color", "Textures/rock.png")
    for i = 1, 5 do
        BG.near[i] = clone("T_mountain", HIDE); BG.crest[i] = clone("T_crest", HIDE); BG.ground[i] = clone("T_ground", HIDE)
    end
    paint(tnode("T_city"), { .16, .18, .24 }, { .01, .015, .03 }, 0.35, 0.6)
    paint(tnode("T_citywin"), { 1, .8, .5 }, { 2.6, 1.7, .7 }, 0.3, 0)
    for i = 1, 3 do BG.cities[i] = { clone("T_city", HIDE), clone("T_citywin", HIDE) } end
end
local planet_alive = true
local function place_tiles(list, offset_factor, scale, y, z)
    local Lt = TILE * scale
    local base = CAMX - ((CAMX * offset_factor) % Lt) - Lt * floor(#list / 2)
    for i, n in ipairs(list) do
        if type(n) == "table" then for _, m in ipairs(n) do m:set_position(vec3(base + (i - 1) * Lt, y, z)) end
        else n:set_position(vec3(base + (i - 1) * Lt, y, z)) end
    end
end
local function update_backdrop(dt)
    local hw, hh = view_half(SKY_Z)
    BG.sky:set_position(vec3(CAMX, hh * 0.25, SKY_Z))
    BG.planet:set_position(vec3(CAMX - hw * 0.45 - (CAMX * 0.02) % 60 + 30, hh * 0.32, SKY_Z + 60)); BG.planet:set_rotation(vec3(10, G.t * 3, 22))
    local shw = view_half(-90)
    for _, st in ipairs(BG.stars) do
        local x = CAMX + ((st.x - CAMX * 0.15 + shw * 1.2) % (shw * 2.4)) - shw * 1.2
        local s = st.s * (0.6 + 0.4 * sin(G.t * st.tw + st.ph))
        st.node:set_position(vec3(x, st.y, -90)); st.node:set_scale(vec3(s, s, s))
    end
    place_tiles(BG.far, 0.55, FAR_S, GROUND + 3.2, FAR_Z)
    if planet_alive then
        place_tiles(BG.near, 1.0, 1, GROUND + 3, NEAR_Z); place_tiles(BG.crest, 1.0, 1, GROUND + 3, NEAR_Z)
        place_tiles(BG.ground, 1.0, 1, GROUND + 3, 0)
        -- cities live on fixed world tiles
        local k = 1
        for _, ti in ipairs(CITY_TILES) do
            local wx = ti * TILE + TILE / 2
            if abs(wrapd(wx - CAMX)) < VIEW_HW + TILE and k <= #BG.cities then
                for _, m in ipairs(BG.cities[k]) do m:set_position(vec3(sx(wx), GROUND + 3, -1.8)) end
                k = k + 1
            end
        end
        for j = k, #BG.cities do for _, m in ipairs(BG.cities[j]) do m:set_position(HIDE) end end
    else
        for _, l in ipairs({ BG.near, BG.crest, BG.ground }) do for _, n in ipairs(l) do n:set_position(HIDE) end end
        for _, c in ipairs(BG.cities) do for _, m in ipairs(c) do m:set_position(HIDE) end end
    end
    set_point(L.key, vec3(CAMX - 12, 14, 18), vec3(0.45, 0.65, 1.0), 110, 80)
    set_point(L.fill, vec3(CAMX + 6, 8, 34), vec3(0.8, 0.85, 1.0), 90, 75)
    set_point(L.city, vec3(CAMX + 8, GROUND + 4, 10), vec3(1.0, 0.55, 0.3), planet_alive and 70 or 0, 50)
end

------------------------------------------------------------------ input
local prev = {}
local pulse = { bomb = false, hyper = false }
local keyfn = input.is_key_down_raw or input.is_key_pressed
local PLAY_VK = { Left = true, Right = true, Up = true, Down = true, Space = true }
G.vk = {}

local function raw_down(k)
    local ok, v = pcall(keyfn, k)
    return ok and v
end

local function held(k)
    if PLAY_VK[k] and G.vk[k] then
        return true
    end
    return raw_down(k)
end

local function edge(k)
    local d = raw_down(k)
    local p = prev[k]
    prev[k] = d
    return d and not p
end

local function any(...)
    for _, k in ipairs({ ... }) do
        if held(k) then
            return true
        end
    end
    return false
end

local HUMAN_KEYS = {
    "Left", "Right", "Up", "Down", "A", "D", "W", "S",
    "Space", "J", "Z", "Left Ctrl", "B", "X", "H", "C",
}
local raw_prev = {}

local function sample_human_keys()
    local raw = input.is_key_down_raw
    if not raw then
        return
    end
    for i = 1, #HUMAN_KEYS do
        local key = HUMAN_KEYS[i]
        local ok, v = pcall(raw, key)
        raw_prev[key] = ok and v and true or false
    end
end

local function human_edge()
    local raw = input.is_key_down_raw
    if not raw then
        return false
    end
    local hit = false
    for i = 1, #HUMAN_KEYS do
        local key = HUMAN_KEYS[i]
        local ok, v = pcall(raw, key)
        local down = ok and v and true or false
        if down and not raw_prev[key] then
            hit = true
        end
        raw_prev[key] = down
    end
    return hit
end

------------------------------------------------------------------ state
local score, hiscore, lives, bombs, wave = 0, 0, 3, 3, 0
local next_extra = 10000
pcall(function() local s = fs.read("Save/defender_hiscore.txt"); if s then hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, "Save/defender_hiscore.txt", tostring(hiscore)) end
local banner = { text = "", sub = "", t = 0 }
local function show_banner(s, sub, d) banner.text, banner.sub, banner.t = s, sub or "", d or 2.4 end
local function add_score(p)
    score = score + p
    if score >= next_extra then next_extra = next_extra + 10000; lives = lives + 1; bombs = bombs + 1; sfx("extra"); show_banner("BONUS SHIP", "+1 ship · +1 smart bomb", 1.8) end
end

------------------------------------------------------------------ player
local P = { ux = 0, x = 0, y = 0, vx = 0, vy = 0, face = 1, yaw = 0, bank = 0, alive = true, dead_t = 0, inv = 0, fire_t = 0, hyper_t = 0, carry = nil }
local function build_player()
    P.root = make_model("ship", 1.3)
    P.exhaust = new_emitter({ c0 = vec4(1.2, 2.2, 4.0, 1), c1 = vec4(0.6, 0.15, 1.2, 0), count = 600, radius = 0.22, smin = 0.04, smax = 0.12,
        lmin = 0.1, lmax = 0.3, noise = 1.5, drag = 2.5 })
    P.smoke = new_emitter({ c0 = vec4(0.25, 0.3, 0.6, 0.35), c1 = vec4(0.2, 0.05, 0.3, 0), count = 300, radius = 0.15, smin = 0.06, smax = 0.16,
        lmin = 0.4, lmax = 0.8, noise = 2.5, drag = 3 })
end
local LASERS = {}
local function build_lasers()
    for i = 0, 3 do
        local c = ({ { 1, .35, .15 }, { 1, .9, .3 }, { .3, 1, .9 }, { 1, .3, .8 } })[i + 1]
        paint(tnode("T_laser_" .. i), c, { c[1] * 3, c[2] * 3, c[3] * 3 }, 0.3, 0)
    end
    for i = 1, 8 do LASERS[i] = { node = clone("T_laser_" .. ((i - 1) % 4), HIDE), live = false } end
end
local laser_n = 0
local function fire_laser()
    for _, l in ipairs(LASERS) do
        if not l.live then
            l.live = true; l.dir = P.face; l.y = P.y - 0.05 + rr(-0.05, 0.05)
            l.x0 = P.x + P.face * 2.0; l.head = 0; l.tail = 0; l.t = 0
            sfx("laser")
            sparks(l.x0, l.y, { 1, .6, .3 }, 8, 10)
            return
        end
    end
end

------------------------------------------------------------------ pools: enemies, humans, bullets, mines
local KIND = {
    lander = { n = 20, scale = 1.3, r = 1.7, pts = 150, slot = 0, col = { .3, 1, .4 } },
    mutant = { n = 20, scale = 1.25, r = 1.6, pts = 150, slot = 1, col = { 1, .3, 1 } },
    bomber = { n = 6, scale = 1.2, r = 1.5, pts = 250, slot = 2, col = { .8, .4, 1 } },
    baiter = { n = 5, scale = 1.25, r = 1.8, pts = 200, slot = 0, col = { .5, 1, .4 } },
    pod = { n = 5, scale = 1.25, r = 1.6, pts = 1000, slot = 2, col = { .8, .3, 1 } },
    swarmer = { n = 24, scale = 1.1, r = 1.05, pts = 150, slot = 3, col = { 1, .5, .1 } },
}
local POOL = {}
local enemies = {}
G.enemies = enemies
local function build_pools()
    for k, d in pairs(KIND) do POOL[k] = {}; for i = 1, d.n do POOL[k][i] = { root = make_model(k, d.scale), used = false } end end
end
local function spawn(kind, x, y)
    for _, m in ipairs(POOL[kind]) do
        if not m.used then
            m.used = true
            local e = { kind = kind, m = m, x = wrapx(x), y = y, vx = 0, vy = 0, t = 0, ph = rr(0, TAU), fire = rr(1.5, 3.5), alive = true, spawn = 0 }
            enemies[#enemies + 1] = e
            sparks(x, y, KIND[kind].col, 18, 12)
            return e
        end
    end
end
local function despawn(e)
    e.alive = false; e.m.used = false; e.m.root:set_position(HIDE)
    for i = #enemies, 1, -1 do if enemies[i] == e then table.remove(enemies, i) end end
end

local HUMANS = {}
local function build_humans()
    for i = 1, 10 do
        local h = { root = make_model("human", 1.25), alive = false }
        HUMANS[i] = h
    end
end
local function reset_humans()
    for i, h in ipairs(HUMANS) do
        h.alive = true; h.x = (i - 0.5) * WW / 10 + rr(-10, 10); h.y = GROUND + 1.35; h.vy = 0; h.state = "walk"
        h.dir = rand() < 0.5 and -1 or 1; h.t = rr(0, 5); h.by = nil; h.fall_from = 0
    end
end
local function humans_alive() local n = 0; for _, h in ipairs(HUMANS) do if h.alive then n = n + 1 end end; return n end

local BULLETS, MINES = {}, {}
local function build_shots()
    paint(tnode("T_bullet"), { 1, .5, .3 }, { 6, 2.2, 1.2 }, 0.3, 0)
    paint(tnode("T_mine"), { 1, .2, .7 }, { 4, .6, 2.6 }, 0.3, 0)
    for i = 1, 30 do BULLETS[i] = { node = clone("T_bullet", HIDE), live = false } end
    for i = 1, 30 do MINES[i] = { node = clone("T_mine", HIDE), live = false } end
end
local function enemy_shot(x, y, speed)
    if not P.alive then return end
    local dx, dy = wrapd(P.x - x), P.y - y
    if abs(dx) > VIEW_HW + 2 then return end
    local tlead = sqrt(dx * dx + dy * dy) / speed
    dx = dx + P.vx * tlead * 0.6; dy = dy + P.vy * tlead * 0.4
    local d = max(0.01, sqrt(dx * dx + dy * dy))
    for _, b in ipairs(BULLETS) do
        if not b.live then
            b.live = true; b.x, b.y, b.vx, b.vy, b.t = x, y, dx / d * speed, dy / d * speed, 0
            sfx("eshot"); return
        end
    end
end
local function drop_mine(x, y)
    for _, m in ipairs(MINES) do if not m.live then m.live = true; m.x, m.y, m.t = x, y, 0; return end end
end
local BEAMS = {}
local function build_beams()
    paint(tnode("T_beam"), { .05, .25, .15, 1 }, { .12, .9, .5 }, 0.3, 0); mds(tnode("T_beam"))
    for i = 1, 6 do BEAMS[i] = clone("T_beam", HIDE) end
end

------------------------------------------------------------------ combat
local planet_boom
local function kill_enemy(e, by_bomb)
    if not e.alive then return end
    local d = KIND[e.kind]
    explode(e.x, e.y, d.col, d.slot, e.kind == "pod" or e.kind == "bomber")
    sfx(by_bomb and "hit" or "boom")
    add_score(d.pts)
    if e.human then local h = e.human; h.state = "fall"; h.by = nil; h.vy = 0; h.fall_from = h.y; e.human = nil end
    if e.kind == "pod" then for i = 1, 4 do local s = spawn("swarmer", e.x + rr(-1, 1), e.y + rr(-1, 1)); if s then s.vx = rr(-12, 12); s.vy = rr(-8, 8) end end end
    despawn(e)
end
local function kill_human(h)
    if not h.alive then return end
    h.alive = false; h.root:set_position(HIDE)
    explode(h.x, h.y, { .4, .9, 1 }, 5, false)
    if humans_alive() == 0 and planet_alive then planet_boom() end
end
local function player_die()
    if not P.alive or P.inv > 0 then return end
    P.alive = false; P.dead_t = 0
    explode(P.x, P.y, { .4, .8, 1 }, 5, true); explode(P.x + 1, P.y + 0.5, { 1, .5, .2 }, 3, true)
    sfx("death"); add_shake(1.0)
    P.root:set_position(HIDE)
    if P.carry then P.carry.state = "fall"; P.carry.fall_from = P.carry.y; P.carry = nil end
    for _, b in ipairs(BULLETS) do b.live = false; b.node:set_position(HIDE) end
end
local function smart_bomb()
    if bombs <= 0 or not P.alive then return end
    bombs = bombs - 1
    sfx("smartbomb"); add_shake(0.8); G.white = 1.0
    shockwave(P.x, P.y, { .9, .9, 1 }, 34, 0.8); shockwave(P.x, P.y, { 1, .5, .2 }, 22, 0.6)
    for i = #enemies, 1, -1 do local e = enemies[i]; if e and abs(wrapd(e.x - CAMX)) < VIEW_HW + 4 then kill_enemy(e, true) end end
    for _, m in ipairs(MINES) do if m.live and abs(wrapd(m.x - CAMX)) < VIEW_HW + 4 then m.live = false; m.node:set_position(HIDE) end end
end
local function hyperspace()
    if not P.alive or P.hyper_t > 0 then return end
    P.hyper_t = 2.5
    sfx("hyper"); shockwave(P.x, P.y, { .4, .8, 1 }, 6, 0.5)
    burst(sx(P.x), P.y, { c0 = vec4(1, 2, 4, 1), c1 = vec4(.3, .1, 1, 0), count = 120, smin = 0.05, smax = 0.15, lmin = 0.3, lmax = 0.7, spread = 30, drag = 2 })
    local nx = wrapx(P.x + rr(80, WW - 80))
    P.ux = P.ux + wrapd(nx - P.x); P.x = nx; P.y = rr(GROUND + 4, TOP - 3); P.vx = 0; P.inv = 1.0
    CAMX = P.ux + P.face * VIEW_HW * 0.4
    shockwave(P.x, P.y, { .4, .8, 1 }, 6, 0.5)
end
planet_boom = function()
    planet_alive = false
    sfx("planetboom"); add_shake(1.2); G.white = 1.2
    show_banner("PLANET LOST", "every Lander is now a Mutant", 3)
    for i = 1, 8 do explode(CAMX + rr(-VIEW_HW, VIEW_HW), GROUND + rr(0, 4), { 1, .5, .2 }, 3, true) end
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        if e.kind == "lander" then local x, y = e.x, e.y; despawn(e); spawn("mutant", x, y) end
    end
end

------------------------------------------------------------------ waves
local W = { queue = {}, t = 0, spawn_t = 0, time = 0, bait_t = 0, done = false, intermission = 0 }
local function start_wave()
    wave = wave + 1
    W.queue = {}; W.time = 0; W.bait_t = 0; W.spawn_t = 1.0; W.done = false
    local nl = min(20, 8 + wave * 2)
    for i = 1, nl do W.queue[#W.queue + 1] = "lander" end
    for i = 1, min(1 + floor(wave / 2), 4) do table.insert(W.queue, 3 + i * 3, "bomber") end
    if wave >= 2 then for i = 1, min(wave - 1, 3) do table.insert(W.queue, #W.queue, "pod") end end
    if wave % 5 == 1 and wave > 1 then planet_alive = true; reset_humans() end
    show_banner("ATTACK WAVE " .. wave, humans_alive() .. " humanoids to defend", 2.4)
    sfx("wave")
end
local function update_waves(dt)
    W.time = W.time + dt
    W.spawn_t = W.spawn_t - dt
    if #W.queue > 0 and W.spawn_t <= 0 then
        W.spawn_t = 3.0
        for i = 1, 4 do
            local k = table.remove(W.queue, 1); if not k then break end
            local x = wrapx(P.x + (rand() < 0.5 and -1 or 1) * rr(VIEW_HW * 0.45, VIEW_HW * 2.2))
            local e = spawn(k, x, rr(TOP - 4, TOP - 0.5))
            if e then e.vx = rr(3.5, 6.5) * (rand() < 0.5 and -1 or 1); e.spawn = 0.6 end
        end
    end
    if W.time > 45 then
        W.bait_t = W.bait_t - dt
        if W.bait_t <= 0 then W.bait_t = max(5, 12 - wave); spawn("baiter", P.x + (rand() < 0.5 and -1 or 1) * VIEW_HW * 1.2, rr(GROUND + 5, TOP - 2)) end
    end
    local hostile = 0
    for _, e in ipairs(enemies) do if e.kind ~= "baiter" then hostile = hostile + 1 end end
    if #W.queue == 0 and hostile == 0 and not W.done then
        W.done = true; W.intermission = 3.2
        local bonus = humans_alive() * 100 * min(wave, 5)
        add_score(bonus)
        show_banner("WAVE " .. wave .. " COMPLETE", "humanoid bonus " .. bonus, 3.0)
        for i = #enemies, 1, -1 do kill_enemy(enemies[i], true) end
    end
    if W.done then W.intermission = W.intermission - dt; if W.intermission <= 0 then start_wave() end end
end

------------------------------------------------------------------ updates
local AUTO = { on = false, fire = false }
local function nearest_enemy()
    local best, bd = nil, 1e9
    for _, e in ipairs(enemies) do local d = abs(wrapd(e.x - P.x)) + abs(e.y - P.y) * 2; if d < bd then best, bd = e, d end end
    return best
end
local function update_player(dt, ctl)
    if not P.alive then
        P.dead_t = P.dead_t + dt
        emitter_at(P.exhaust, 0, -1000, 0, 0); emitter_at(P.smoke, 0, -1000, 0, 0)
        return
    end
    P.inv = max(0, P.inv - dt); P.hyper_t = max(0, P.hyper_t - dt)
    local h, v = ctl.h, ctl.v
    if h ~= 0 then P.face = h > 0 and 1 or -1 end
    local ACC, MAXV = 40, 30
    if h ~= 0 then P.vx = P.vx + P.face * ACC * dt; P.vx = P.vx * math.exp(-0.35 * dt)
    else P.vx = P.vx * math.exp(-1.6 * dt) end
    P.vx = clamp(P.vx, -MAXV, MAXV)
    P.vy = damp(P.vy, v * 15, 12, dt)
    P.ux = P.ux + P.vx * dt; P.x = wrapx(P.ux)
    P.y = clamp(P.y + P.vy * dt, GROUND + 1.4, TOP)
    -- smooth turn (yaw 0 = facing +X) and banking with vertical speed
    P.yaw = damp(P.yaw, P.face > 0 and 0 or 180, 10, dt)
    P.bank = damp(P.bank, clamp(P.vy * 0.9, -18, 18), 8, dt)
    local blink = P.inv > 0 and (floor(G.t * 20) % 2 == 0)
    P.root:set_position(blink and HIDE or vec3(sx(P.x), P.y, 0))
    P.root:set_rotation(vec3(-P.bank * (P.face), P.yaw, P.bank * 0.5))
    local thrust = (h ~= 0) and 1 or 0.25
    local tx = sx(P.x) - P.face * 3.0
    emitter_at(P.exhaust, tx, P.y, 0, 420 * thrust, vec3(-P.face * (5 + 6 * thrust) + P.vx * 0.85, 0, 0))
    emitter_at(P.smoke, tx - P.face * 0.5, P.y, 0, 25 * thrust, vec3(-P.face * 3 + P.vx * 0.8, 0, 0))
    set_point(L.player, vec3(tx - P.face * 1.2, P.y, 2.5), vec3(0.45, 0.75, 1.0), 14 + 22 * thrust, 12)
    P.fire_t = P.fire_t - dt
    if ctl.fire and P.fire_t <= 0 then P.fire_t = 0.11; fire_laser() end
    if ctl.bomb then smart_bomb() end
    if ctl.hyper then hyperspace() end
    -- set down a carried humanoid
    if P.carry then
        local hm = P.carry
        hm.x, hm.y = wrapx(P.x - P.face * 0.3), P.y - 2.0
        if P.y < GROUND + 3.0 then hm.state = "walk"; hm.y = GROUND + 1.35; P.carry = nil; add_score(500); sfx("rescue"); show_banner("+500", "humanoid returned", 1.0) end
    end
end
local function update_lasers(dt)
    local lit = false
    for i, l in ipairs(LASERS) do
        if l.live then
            l.t = l.t + dt
            l.head = l.head + 190 * dt
            if l.t > 0.12 then l.tail = l.tail + 150 * dt end
            local len = l.head - l.tail
            if len <= 0.2 or l.t > 0.6 then l.live = false; l.node:set_position(HIDE)
            else
                local mid = l.x0 + l.dir * (l.head + l.tail) * 0.5
                l.node:set_position(vec3(sx(mid), l.y, 0)); l.node:set_scale(vec3(len / 6, 1 + 0.4 * sin(l.t * 60), 1))
                lit = true
                -- hit test
                for j = #enemies, 1, -1 do
                    local e = enemies[j]
                    if e and abs(e.y - l.y) < KIND[e.kind].r + 0.9 then
                        local dx = wrapd(e.x - l.x0) * l.dir
                        if dx > l.tail - 2.5 and dx < l.head + 2.0 then kill_enemy(e); l.live = false; l.node:set_position(HIDE); break end
                    end
                end
                for _, hm in ipairs(HUMANS) do
                    if l.live and hm.alive and hm.state ~= "walk" and hm.state ~= "carried_p" and abs(hm.y - l.y) < 0.7 then
                        local dx = wrapd(hm.x - l.x0) * l.dir
                        if dx > l.tail and dx < l.head then kill_human(hm); l.live = false; l.node:set_position(HIDE) end
                    end
                end
            end
        end
    end
    set_point(L.laser, lit and vec3(sx(P.x) + P.face * 8, P.y, 2) or HIDE, vec3(1, 0.5, 0.3), lit and 30 or 0, 14)
end
local function steer(e, tx, ty, sp, k, dt)
    local dx, dy = wrapd(tx - e.x), ty - e.y
    local d = max(0.01, sqrt(dx * dx + dy * dy))
    e.vx = damp(e.vx, dx / d * sp, k, dt); e.vy = damp(e.vy, dy / d * sp, k, dt)
end
local function update_enemies(dt)
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        if e then
            e.t = e.t + dt
            local k = e.kind
            local near = abs(wrapd(e.x - P.x)) < VIEW_HW + 2
            if k == "lander" then
                if e.human then
                    e.vx = damp(e.vx, 0, 3, dt); e.vy = 3.2 + wave * 0.15
                    e.human.x, e.human.y = e.x, e.y - 3.0
                    if e.y >= TOP + 0.5 then
                        local hm = e.human; e.human = nil; hm.alive = false; hm.root:set_position(HIDE)
                        local x, y = e.x, e.y; despawn(e); local m = spawn("mutant", x, y); sfx("mutate")
                        explode(x, y, { 1, .3, 1 }, 1, false)
                        if humans_alive() == 0 and planet_alive then planet_boom() end
                    end
                elseif e.target then
                    -- hunt: fly over the humanoid while descending to just above its head, then drop and grab it
                    local hm = e.target
                    if not hm.alive or hm.state ~= "walk" then e.target = nil; if hm.targeted == e then hm.targeted = nil end
                    else
                        local dx = wrapd(hm.x - e.x)
                        if abs(dx) > 1.2 then
                            e.vx = damp(e.vx, clamp(dx * 1.5, -7.5, 7.5), 2.5, dt)
                            e.vy = damp(e.vy, clamp((hm.y + 5.0 - e.y) * 0.9, -4.5, 3), 2, dt)
                        else
                            e.vx = damp(e.vx, dx * 3, 5, dt); e.vy = damp(e.vy, -3.5, 4, dt)
                            if e.y <= hm.y + 3.0 then e.human = hm; hm.state = "carried"; hm.by = e; e.target = nil; sfx("abduct") end
                        end
                    end
                else
                    -- drift: cruise sideways, periodically picking a new altitude (biased toward the surface)
                    e.alt_t = (e.alt_t or 0) - dt
                    if e.alt_t <= 0 or not e.alt then
                        e.alt_t = rr(2.0, 4.5)
                        e.alt = rr(GROUND + 5.5, TOP - 2.5)
                        if rand() < 0.5 then e.alt = rr(GROUND + 4.5, GROUND + 8) end
                    end
                    local wob = 0.8 * sin(e.t * 1.7 + e.ph)
                    e.vy = damp(e.vy, clamp((e.alt + wob - e.y) * 0.9, -4, 4), 2, dt)
                    local cruise = 4.5 + min(3, wave * 0.3)
                    e.vx = damp(e.vx, (e.vx >= 0 and 1 or -1) * cruise, 1.5, dt)
                    if rand() < dt * 0.08 then e.vx = -e.vx end
                    if planet_alive and rand() < dt * 0.35 then
                        local best, bd = nil, 90
                        for _, hm in ipairs(HUMANS) do
                            if hm.alive and hm.state == "walk" and not hm.targeted then local d = abs(wrapd(hm.x - e.x)); if d < bd then best, bd = hm, d end end
                        end
                        if best then e.target = best; best.targeted = e end
                    end
                end
                e.m.root:set_rotation(vec3(0, e.t * 60, sin(e.t * 2 + e.ph) * 8))
            elseif k == "mutant" then
                steer(e, P.x + sin(e.t * 3 + e.ph) * 6, P.y + sin(e.t * 5 + e.ph) * 3, 11 + wave * 0.6, 3, dt)
                e.vx = e.vx + rr(-12, 12) * dt; e.vy = e.vy + rr(-12, 12) * dt
                e.m.root:set_rotation(vec3(e.t * 90, e.t * 140, e.t * 50))
            elseif k == "bomber" then
                e.vx = (e.vx >= 0 and 1 or -1) * 5; e.vy = cos(e.t * 0.9 + e.ph) * 3
                e.drop = (e.drop or 1) - dt
                if e.drop <= 0 then e.drop = rr(0.9, 1.6); drop_mine(e.x, e.y) end
                e.m.root:set_rotation(vec3(e.t * 70, e.t * 50, e.t * 30))
            elseif k == "pod" then
                e.vx = (e.vx >= 0 and 1 or -1) * 3.5; e.vy = sin(e.t * 0.6 + e.ph) * 2
                e.m.root:set_rotation(vec3(e.t * 30, e.t * 45, 0))
            elseif k == "swarmer" then
                steer(e, P.x, P.y + sin(e.t * 4 + e.ph) * 4, 14 + wave * 0.6, 2.2, dt)
                e.m.root:set_rotation(vec3(0, e.vx < 0 and 180 or 0, clamp(e.vy * 3, -40, 40)))
            elseif k == "baiter" then
                steer(e, P.x - P.face * 8, P.y + 2 * sin(e.t * 2), 31, 1.6, dt)
                e.m.root:set_rotation(vec3(0, e.t * 200, 0))
            end
            e.x = wrapx(e.x + e.vx * dt); e.y = clamp(e.y + e.vy * dt, GROUND + 1.6, TOP + 1)
            if k ~= "lander" or not e.human then
                if e.y >= TOP and e.vy > 0 then e.vy = -abs(e.vy) end
                if e.y <= GROUND + 1.7 and e.vy < 0 then e.vy = abs(e.vy) end
            end
            local sc = KIND[k].scale * clamp(1 - e.spawn, 0, 1) ^ 0.5
            e.spawn = max(0, e.spawn - dt * 1.5)
            e.m.root:set_position(vec3(sx(e.x), e.y, 0)); e.m.root:set_scale(vec3(sc, sc, sc))
            -- fire
            e.fire = e.fire - dt
            if e.fire <= 0 then
                local rate = ({ lander = 2.8, mutant = 1.6, baiter = 1.2, swarmer = 3.0, bomber = 99, pod = 99 })[k]
                e.fire = rr(0.6, 1.4) * rate * max(0.45, 1 - wave * 0.06)
                if near and rate < 50 and P.alive then enemy_shot(e.x, e.y, 10 + wave * 0.6) end
            end
            -- collide with player
            if P.alive and P.inv <= 0 then
                local dx, dy = wrapd(e.x - P.x), e.y - P.y
                if abs(dx) < KIND[k].r + 1.4 and abs(dy) < KIND[k].r * 0.8 + 0.4 then kill_enemy(e); player_die() end
            end
        end
    end
end

local function update_humans(dt)
    local bi = 1
    for _, hm in ipairs(HUMANS) do
        if hm.alive then
            hm.t = hm.t + dt
            if hm.targeted and (not hm.targeted.alive or hm.targeted.target ~= hm) then hm.targeted = nil end
            local rot = vec3(0, hm.dir > 0 and 90 or -90, 0)
            if hm.state == "walk" then
                hm.x = wrapx(hm.x + hm.dir * 0.9 * dt); hm.y = GROUND + 1.35
                if rand() < dt * 0.15 then hm.dir = -hm.dir end
                rot = vec3(sin(hm.t * 8) * 6, hm.dir > 0 and 90 or -90, 0)
            elseif hm.state == "carried" then
                rot = vec3(0, hm.t * 120, sin(hm.t * 6) * 20)
                if bi <= #BEAMS and hm.by then
                    local b = BEAMS[bi]; bi = bi + 1
                    b:set_position(vec3(sx(hm.x), hm.y - 0.6, 0)); b:set_scale(vec3(0.3 + 0.08 * sin(hm.t * 31), 3.0 + 0.2 * sin(hm.t * 20), 1))
                    if rand() < 0.5 then burst(sx(hm.x), hm.y + 1, { c0 = vec4(.5, 2.4, 1.2, 1), c1 = vec4(.1, .6, .4, 0), count = 3, smin = 0.04, smax = 0.1, lmin = 0.3, lmax = 0.6, radius = 0.4, spread = 2, vel = vec3(0, 3, 0) }) end
                end
            elseif hm.state == "fall" then
                hm.vy = max(hm.vy - 9 * dt, -9); hm.y = hm.y + hm.vy * dt
                rot = vec3(hm.t * 200, 0, hm.t * 150)
                if P.alive and not P.carry and abs(wrapd(hm.x - P.x)) < 2.2 and abs(hm.y - P.y) < 2.0 then
                    hm.state = "carried_p"; P.carry = hm; add_score(500); sfx("catch"); show_banner("+500", "humanoid caught", 1.0)
                elseif hm.y <= GROUND + 1.35 then
                    hm.y = GROUND + 1.35
                    if hm.fall_from - hm.y > 9 then kill_human(hm) else hm.state = "walk"; add_score(250); sfx("catch") end
                end
            elseif hm.state == "carried_p" then
                rot = vec3(0, P.face > 0 and 90 or -90, 0)
            end
            if hm.alive then
                hm.root:set_position(vec3(sx(hm.x), hm.y, 1.4)); hm.root:set_rotation(rot)
                if hm.state == "fall" and rand() < 0.4 then burst(sx(hm.x), hm.y, { c0 = vec4(.6, 1.6, 2.4, 1), c1 = vec4(.2, .4, 1, 0), count = 2, smin = .04, smax = .08, lmin = .3, lmax = .5, radius = .2, spread = 2 }) end
            end
        end
    end
    for j = bi, #BEAMS do BEAMS[j]:set_position(HIDE) end
end
local function update_shots(dt)
    for _, b in ipairs(BULLETS) do
        if b.live then
            b.t = b.t + dt; b.x = wrapx(b.x + b.vx * dt); b.y = b.y + b.vy * dt
            if b.t > 3 or b.y < GROUND or b.y > TOP + 3 then b.live = false; b.node:set_position(HIDE)
            else
                local s = 0.8 + 0.25 * sin(b.t * 30)
                b.node:set_position(vec3(sx(b.x), b.y, 0.2)); b.node:set_scale(vec3(s, s, s))
                if P.alive and P.inv <= 0 and abs(wrapd(b.x - P.x)) < 1.6 and abs(b.y - P.y) < 0.6 then b.live = false; b.node:set_position(HIDE); player_die() end
            end
        end
    end
    for _, m in ipairs(MINES) do
        if m.live then
            m.t = m.t + dt
            if m.t > 7 then m.live = false; m.node:set_position(HIDE)
            else
                local s = 1 + 0.3 * sin(m.t * 9)
                m.node:set_position(vec3(sx(m.x), m.y, 0.2)); m.node:set_scale(vec3(s, s, s)); m.node:set_rotation(vec3(0, 0, m.t * 120))
                if P.alive and P.inv <= 0 and abs(wrapd(m.x - P.x)) < 1.4 and abs(m.y - P.y) < 0.7 then m.live = false; m.node:set_position(HIDE); player_die() end
            end
        end
    end
end
local shake_t = 0
local function update_camera(dt, snap)
    local target = P.ux + P.face * VIEW_HW * 0.42 + P.vx * 0.18
    CAMX = snap and target or damp(CAMX, target, 3.0, dt)
    shake = max(0, shake - dt * 2.0); shake_t = shake_t + dt
    local a = shake * shake * 0.9 * SET:shake_scale()
    local ox, oy = a * (sin(shake_t * 53) + 0.5 * sin(shake_t * 97)), a * (cos(shake_t * 61) + 0.5 * sin(shake_t * 83))
    cam:set_position(vec3(CAMX + ox, 1.5 + oy, CAMZ)); cam:look_at(vec3(CAMX + ox * 0.5, 0.5 + oy * 0.5, 0))
end

------------------------------------------------------------------ HUD + menus (runtime_ui, pixel coords)
local UI = "hud"
runtime_ui.show(UI); pcall(runtime_ui.set_screen_overlay, UI, true)
local NONE = { 0, 0, 0, 0 }
local hc = {}
local US = SH / 1080
local function quad(id, o)
    local key = ""
    for _, k in ipairs({ "x", "y", "w", "h", "label", "visible", "font_scale" }) do key = key .. tostring(o[k]) .. "|" end
    if o.fill then key = key .. o.fill[1] .. o.fill[2] .. o.fill[3] .. o.fill[4] end
    if o.text_color then key = key .. o.text_color[4] end
    if hc[id] == key then return end
    hc[id] = key
    pcall(runtime_ui.set_quad, UI, id, o)
end
local function text(id, label, x, y, w, h, fs, col, align, vis)
    quad(id, { x = x, y = y, w = w, h = h, z = 10, style = "text", label = label, fill = NONE, border = NONE, text_color = col,
        font_scale = fs * US, align_h = align or "center", align_v = "middle", no_input = true, visible = vis ~= false })
end
local function panel(id, x, y, w, h, vis, a, border)
    quad(id, { x = x, y = y, w = w, h = h, z = 4, style = "text", label = "", fill = { 0.02, 0.03, 0.07, a or 0.55 },
        border = border or { 0.35, 0.8, 0.75, 0.55 }, corner_radius = 12 * US, no_input = true, visible = vis ~= false })
end
local function button(id, label, cx, cy, vis)
    local w, h = 330 * US, 60 * US
    local st = vis and select(2, pcall(runtime_ui.get_state, UI, id))
    local hov = type(st) == "table" and st.hovered
    quad(id, { x = cx - w / 2, y = cy - h / 2, w = w, h = h, z = 12, style = "text", label = label,
        fill = hov and { 0.12, 0.28, 0.3, 0.92 } or { 0.03, 0.07, 0.12, 0.85 }, border = hov and { 1, 0.65, 0.3, 1 } or { 0.35, 0.85, 0.8, 0.9 },
        text_color = hov and { 1, 0.95, 0.85, 1 } or { 0.8, 0.95, 0.95, 1 }, font_scale = 1.25 * US, align_h = "center", align_v = "middle",
        corner_radius = 12 * US, visible = vis })
    return vis and type(st) == "table" and st.clicked
end
local SCAN = { n = 90 }
local SCOL = { lander = { .3, 1, .4, 1 }, mutant = { 1, .3, 1, 1 }, bomber = { .75, .45, 1, 1 }, baiter = { .6, 1, .3, 1 }, pod = { .8, .3, 1, 1 }, swarmer = { 1, .55, .1, 1 } }
local function draw_scanner(vis)
    local w, h = SW * 0.42, 92 * US
    local x0, y0 = SW / 2 - w / 2, 14 * US
    panel("scan_bg", x0, y0, w, h, vis, 0.6)
    local vw = (VIEW_HW * 2) / WW * w
    quad("scan_view", { x = SW / 2 - vw / 2 + wrapd(CAMX - P.ux) / WW * w, y = y0 + 4, w = vw, h = h - 8, z = 5, style = "text", label = "",
        fill = { 0.3, 0.8, 0.8, 0.08 }, border = { 0.4, 0.9, 0.85, 0.5 }, corner_radius = 4, no_input = true, visible = vis })
    local i = 0
    local function dot(x, y, col, s)
        i = i + 1; if i > SCAN.n then return end
        local px = SW / 2 + wrapd(x - P.x) / WW * w
        local py = y0 + h - 8 * US - (y - GROUND) / (TOP + 2 - GROUND) * (h - 16 * US)
        s = (s or 7) * US
        pcall(runtime_ui.set_quad, UI, "sd" .. i, { x = px - s / 2, y = py - s / 2, w = s, h = s, z = 6, style = "text", label = "", fill = col, border = NONE,
            corner_radius = s / 2, no_input = true, visible = true })
    end
    if vis then
        for _, e in ipairs(enemies) do dot(e.x, e.y, SCOL[e.kind]) end
        for _, hm in ipairs(HUMANS) do if hm.alive then dot(hm.x, hm.y, { .5, .85, 1, 1 }, 5) end end
        if P.alive then dot(P.x, P.y, { 1, 1, 1, 1 }, 9) end
    end
    for j = i + 1, SCAN.n do
        if SCAN[j] ~= false then SCAN[j] = false; pcall(runtime_ui.set_quad, UI, "sd" .. j, { x = 0, y = 0, w = 1, h = 1, visible = false, no_input = true }) end
    end
    for j = 1, i do SCAN[j] = true end
end
local function fmt(n) local s = tostring(floor(n)); return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end
local AC, AC2, DIM = { 0.55, 1, 0.9, 1 }, { 1, 0.7, 0.4, 1 }, { 0.7, 0.78, 0.85, 1 }
local function draw_hud(dt, st, menu)
    local play = (st == "play" or st == "pause" or st == "over") and not set_open
    draw_scanner(play)
    text("score", fmt(score), 30 * US, 18 * US, 380 * US, 50 * US, 2.0, AC, "left", play)
    text("hi", "HI " .. fmt(max(hiscore, score)), 30 * US, 64 * US, 380 * US, 34 * US, 1.0, DIM, "left", play)
    text("wave", "WAVE " .. wave, SW - 410 * US, 18 * US, 380 * US, 40 * US, 1.5, AC2, "right", play)
    text("ships", "SHIPS " .. lives .. "  ·  BOMBS " .. bombs, SW - 410 * US, 58 * US, 380 * US, 34 * US, 1.05, DIM, "right", play)
    text("humans", "HUMANOIDS " .. humans_alive(), SW / 2 - 200 * US, 112 * US, 400 * US, 30 * US, 0.95, { .5, .85, 1, 0.9 }, "center", play)
    -- banner
    banner.t = banner.t - dt
    local ba = clamp(banner.t / 0.4, 0, 1)
    text("ban", banner.text, 0, SH * 0.36, SW, 80 * US, 2.6, { 1, .85, .6, floor(ba * 20) / 20 }, "center", play and banner.t > 0)
    text("bans", banner.sub, 0, SH * 0.36 + 70 * US, SW, 40 * US, 1.2, { .7, .9, 1, floor(ba * 20) / 20 }, "center", play and banner.t > 0)
    -- white flash (smart bomb / planet)
    G.white = max(0, (G.white or 0) - dt * 2.2)
    quad("white", { x = 0, y = 0, w = SW, h = SH, z = 2, style = "text", label = "", fill = { 1, 0.95, 0.9, floor(min(0.7, G.white) * 20) / 20 },
        border = NONE, no_input = true, visible = G.white > 0.02 })
    -- title
    local title = st == "title" and not set_open
    panel("t_bg", SW / 2 - 480 * US, SH * 0.12, 960 * US, SH * 0.68, title, 0.42)
    text("t_title", "Defender Remix", 0, SH * 0.15, SW, 130 * US, 4.6, { 0.6, 1, 0.92, 1 }, "center", title)
    text("t_sub", "Protect the humanoids · Patrol the planet · Leave nothing in the sky", 0, SH * 0.15 + 118 * US, SW, 40 * US, 1.15, DIM, "center", title)
    text("t_ctl1", "Arrows / WASD: fly   ·   Space / J: fire   ·   B / X: smart bomb   ·   H / C: hyperspace", 0, SH * 0.645, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_ctl2", "P / Esc: pause   ·   O: settings   ·   M: mute   ·   mouse: click any button", 0, SH * 0.645 + 34 * US, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_hi", "HIGH SCORE " .. fmt(hiscore), 0, SH * 0.645 + 76 * US, SW, 36 * US, 1.1, AC2, "center", title)
    local pause = st == "pause" and not set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.3, 600 * US, SH * 0.42, pause, 0.7)
    text("p_t", "PAUSED", 0, SH * 0.32, SW, 80 * US, 2.6, AC, "center", pause)
    local over = st == "over" and not set_open
    panel("o_bg", SW / 2 - 360 * US, SH * 0.26, 720 * US, SH * 0.5, over, 0.7, { 1, 0.5, 0.3, 0.6 })
    text("o_t", "GAME OVER", 0, SH * 0.28, SW, 90 * US, 3.0, { 1, .55, .35, 1 }, "center", over)
    text("o_s", "SCORE " .. fmt(score) .. "  ·  WAVE " .. wave, 0, SH * 0.28 + 90 * US, SW, 40 * US, 1.3, DIM, "center", over)
    local c = {}
    c.start = button("b_start", "START (ENTER)", SW / 2 - 190 * US, SH * 0.45, title)
    c.jev = button("b_jev", "Jev", SW / 2 + 190 * US, SH * 0.45, title)
    c.set_t = button("b_set_t", "SETTINGS (O)", SW / 2, SH * 0.45 + 76 * US, title)
    c.quit_app = button("b_quit_app", "QUIT GAME", SW / 2, SH * 0.45 + 152 * US, title)
    c.resume = button("b_resume", "RESUME (P)", SW / 2, SH * 0.44, pause)
    c.set_p = button("b_set_p", "SETTINGS (O)", SW / 2, SH * 0.44 + 76 * US, pause)
    c.quit = button("b_quit", "QUIT TO TITLE (Q)", SW / 2, SH * 0.44 + 152 * US, pause)
    local ov = over and (G.over_t or 0) > 1.2
    c.again = button("b_again", "PLAY AGAIN (ENTER)", SW / 2, SH * 0.5, ov)
    c.title = button("b_title", "TITLE (ESC)", SW / 2, SH * 0.5 + 76 * US, ov)
    return c
end

------------------------------------------------------------------ game flow
local function clear_world()
    for i = #enemies, 1, -1 do despawn(enemies[i]) end
    for _, b in ipairs(BULLETS) do b.live = false; b.node:set_position(HIDE) end
    for _, m in ipairs(MINES) do m.live = false; m.node:set_position(HIDE) end
    for _, l in ipairs(LASERS) do l.live = false; l.node:set_position(HIDE) end
    for _, hm in ipairs(HUMANS) do hm.targeted = nil end
    P.carry = nil
end
local function reset_player()
    P.alive = true; P.vx = 0; P.vy = 0; P.y = 0; P.inv = 2.0; P.hyper_t = 0
end
local function new_game(attract)
    clear_world()
    score, lives, bombs, wave, next_extra = 0, 3, 3, 0, 10000
    planet_alive = true; reset_humans(); reset_player()
    P.ux = 0; P.x = 0; P.face = 1; P.yaw = 0
    update_camera(0, true)
    AUTO.on = attract or false
    G.state = attract and "title" or "play"
    W.queue = {}; W.done = false
    start_wave()
    if not attract then sfx("start") end
end
local function to_title() new_game(true); G.state = "title" end
local function autopilot()
    local c = { h = 0, v = 0, fire = false, bomb = false, hyper = false }
    local e = nearest_enemy()
    if e then
        local dx = wrapd(e.x - P.x)
        c.h = dx > 0 and 1 or -1
        if abs(dx) < 14 and (dx > 0) == (P.face > 0) then c.h = 0 end
        if abs(dx) < 6 then c.h = dx > 0 and -1 or 1 end
        c.v = clamp((e.y - P.y) * 0.6, -1, 1)
        c.fire = abs(e.y - P.y) < 2 and abs(dx) < VIEW_HW
    else c.h = P.face end
    for _, b in ipairs(BULLETS) do if b.live and abs(wrapd(b.x - P.x)) < 6 and abs(b.y - P.y) < 2 then c.v = b.y > P.y and -1 or 1 end end
    return c
end

local jev

local function update(dt)
    dt = min(dt, 0.25)
    jev:tick(dt)
    if G.freeze then return end   -- automation only (screenshots)
    flush_mats()
    G.t = G.t + dt
    -- edges every frame (even while settings is open) so the ESC that closes settings is not re-seen
    local k = { ret = edge("Return"), space = edge("Space"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), q = edge("Q"),
        b = edge("B") or edge("X"), hy = edge("H") or edge("C") }
    set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if set_open then for kk in pairs(k) do k[kk] = false end end
    local function open_settings()
        sfx("click"); SET:open(); set_open = true
    end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        if (k.ret or k.space or c.start) then
            sfx("click")
            jev:begin_human()
            new_game(false)
        elseif c.jev then
            local ok = jev:start()
            if not ok then
                jev:begin_human()
                local message = jev:error() or "Jev failed to start"
                pe_log("[Defender] " .. message)
                show_banner("JEV", message, 4)
            end
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click")
        end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.q or c.quit then jev:begin_human(); to_title() end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then
                sfx("click")
                jev:begin_human()
                new_game(false)
            elseif k.esc or c.title then jev:begin_human(); to_title() end
        end
    end
    st = G.state
    local running = (st == "play" or st == "title" or st == "over") and not (set_open and st ~= "title")
    if st == "pause" or (set_open and st == "play") then running = false end
    if running then
        local ctl
        if AUTO.on or st ~= "play" then ctl = autopilot()
        else
            ctl = {
                h = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0),
                v = (any("Up", "W") and 1 or 0) - (any("Down", "S") and 1 or 0),
                fire = any("Space", "J", "Z", "Left Ctrl"),
                bomb = k.b or pulse.bomb,
                hyper = k.hy or pulse.hyper,
            }
            pulse.bomb = false
            pulse.hyper = false
        end
        if st == "over" then ctl = { h = 0, v = 0 } end
        local n = max(1, math.ceil(dt / (1 / 60)))
        local h = dt / n
        for i = 1, n do
            if i > 1 then ctl.bomb = false; ctl.hyper = false end
            update_player(h, ctl)
            update_lasers(h)
            update_enemies(h)
            update_humans(h)
            update_shots(h)
            update_waves(h)
        end
        if not P.alive and st ~= "over" and P.dead_t > 2.4 then
            if st == "title" then reset_player()
            else
                lives = lives - 1
                if lives <= 0 then
                    G.state = "over"; G.over_t = 0; sfx("gameover")
                    if score > hiscore and not jev:assisted() then hiscore = score; save_hi() end
                else reset_player(); show_banner("SHIP READY", lives .. " remaining", 1.4) end
            end
        end
    end
    update_camera(dt)
    update_backdrop(dt)
    update_shards(dt); update_rings(dt); update_flashes(dt)
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_backdrop()
build_debris(); build_rings()
build_player(); build_lasers(); build_pools(); build_humans(); build_shots(); build_beams()
to_title()
G.spawn = spawn; G.HUMANS = HUMANS; G.explode = explode; G.wrapd = wrapd; G.cam = function() return CAMX end; G.VHW = VIEW_HW
G.new_game = new_game; G.to_title = to_title; G.P = P; G.smart_bomb = smart_bomb; G.AUTO = AUTO
G.update = update

local function clear_hold()
    G.vk.Left = false
    G.vk.Right = false
    G.vk.Up = false
    G.vk.Down = false
    G.vk.Space = false
    pulse.bomb = false
    pulse.hyper = false
end

local function hold_facing(opposite)
    local left = P.face < 0
    if opposite then
        left = not left
    end
    if left then
        G.vk.Left = true
    else
        G.vk.Right = true
    end
end

local function apply_action(id)
    clear_hold()

    if id == "thrust" or id == "thrust_fire" then
        hold_facing(false)
    elseif id == "reverse" then
        hold_facing(true)
    elseif id == "climb" then
        G.vk.Up = true
    elseif id == "dive" then
        G.vk.Down = true
    elseif id == "bomb" then
        pulse.bomb = true
    elseif id == "hyperspace" then
        pulse.hyper = true
    end

    if id == "fire" or id == "thrust_fire" or id == "thrust" or id == "reverse" or id == "climb" or id == "dive" then
        G.vk.Space = true
    end
end

local function humanoid_in_trouble()
    local best = nil
    local best_d = 1e9
    for _, hm in ipairs(HUMANS) do
        local troubled = hm.alive and (hm.state == "fall" or hm.state == "carried" or hm.targeted)
        if troubled then
            local d = abs(wrapd(hm.x - P.x)) + abs(hm.y - P.y)
            if d < best_d then
                best = hm
                best_d = d
            end
        end
    end
    if not best then
        return false
    end

    local state = best.state
    if state == "walk" then
        state = "hunted"
    end
    return {
        x = best.x,
        y = best.y,
        state = state,
        dx = wrapd(best.x - P.x),
        dy = best.y - P.y,
    }
end

local function defender_action()
    local hm = humanoid_in_trouble()
    local enemy = nearest_enemy()
    local dx, dy = 0, 0
    if type(hm) == "table" then
        dx, dy = hm.dx, hm.dy
    elseif enemy then
        dx = wrapd(enemy.x - P.x)
        dy = enemy.y - P.y
    else
        return { { id = "thrust_fire", description = "Patrol. Thrust and fire.", score = 1 } }
    end

    if abs(dy) > abs(dx) and abs(dy) > 1.2 then
        if dy > 0 then
            return { { id = "climb", description = "Climb toward the target. The gun keeps firing.", score = dy } }
        end
        return { { id = "dive", description = "Dive toward the target. The gun keeps firing.", score = -dy } }
    end

    local face = P.face or 1
    local facing = (dx >= 0 and face > 0) or (dx < 0 and face < 0)
    if not facing and abs(dx) > 0.8 then
        return { { id = "reverse", description = "Turn around toward the target. The gun keeps firing.", score = abs(dx) } }
    end
    return { { id = "thrust_fire", description = "Thrust toward the target and fire.", score = abs(dx) + 1 } }
end

local function observe_match()
    local enemy = nearest_enemy()
    local nearest = false
    if enemy then
        nearest = {
            kind = enemy.kind,
            x = enemy.x,
            y = enemy.y,
            dx = wrapd(enemy.x - P.x),
            dy = enemy.y - P.y,
        }
    end
    return {
        ship = { x = P.x, y = P.y, facing = P.face },
        enemy = nearest,
        humanoid = humanoid_in_trouble(),
        lives = lives,
        score = score,
    }
end

local function reset_match(seed)
    if type(seed) == "number" then
        math.randomseed(floor(seed))
    end
    clear_hold()
    new_game(false)
    sample_human_keys()
end

local jev_source = assert(fs.read("Scripts/jev_auto.lua"), "Missing Scripts/jev_auto.lua")
local JevAuto = assert(load(jev_source, "@Scripts/jev_auto.lua", "t", _ENV))()
jev = JevAuto.attach({
    port = 9123,
    id = "defender-remix",
    description = "Patrol a wrapping planet. The offered action flies toward a humanoid in trouble, or the nearest enemy, and the gun keeps firing. Prefer the higher action score.",
    playing = function()
        return G.state == "play"
    end,
    terminal = function()
        return G.state == "over"
    end,
    score = function()
        return score
    end,
    human_edge = human_edge,
    observe = observe_match,
    actions = defender_action,
    apply = apply_action,
    reset = reset_match,
    on_human = clear_hold,
})

hooks { update = update }
pe_log("[Defender] ready  view half-width " .. floor(VIEW_HW) .. "  camz " .. floor(CAMZ))
