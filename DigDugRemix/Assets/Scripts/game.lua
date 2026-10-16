-- DIG DUG REMIX  (PhasmaEngine, Lua)
-- A modernized remake of Namco's Dig Dug (1982). Faithful core: dig tunnels through four strata, inflate
-- Pookas and Fygars with the air pump (4 pumps pop them, depth-based scores, horizontal Fygar x2), drop rocks
-- to crush enemies (multi-crush bonuses), enemies turn into ghosts and drift through dirt, Fygars breathe fire
-- through dirt, the last enemy flees to the surface, a bonus vegetable appears after two rocks fall.
-- Modern visuals: cooked 3D voxel earth with rounded blocks + pebbles, cooked characters, warm headlamp
-- point light, dig crumbs, pop confetti + shockwaves + debris, fire VFX, ghost wisps, rock dust, TAA + soft bloom.
local PI, TAU = math.pi, math.pi * 2
local sin, cos, sqrt, rand, floor, abs, min, max = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local function sgn(v) return v > 0 and 1 or (v < 0 and -1 or 0) end
local G = { state = "boot", t = 0, round = 1 }
local KK = {}
_G.DD = G

------------------------------------------------------------------ deferred materials (engine quirk: replay writes)
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
local function mlive(n, k, v) pcall(_mset, n, k, v) end
local function paint(n, base, emis, rough, metal)
    if not n then return end
    mset(n, "base_color", vec4(base[1], base[2], base[3], base[4] or 1))
    mset(n, "emissive", vec3(emis[1], emis[2], emis[3]))
    mset(n, "roughness", rough or 0.5)
    mset(n, "metallic", metal or 0.0)
end
local function sfx(name) pcall(audio.play, name .. ".wav") end

------------------------------------------------------------------ render setup (see /workspace/games/common/RENDER_SETTINGS.md)
local function S(k, v) pcall(settings.set, k, v) end
local ss = scene.add_empty_node("DigDugSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "space.hdr")
S("hdr", false); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false)
S("bloom", true); S("bloom_strength", 0.5); S("bloom_range", 1.2)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("dof", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", true); S("IBL_intensity", 0.35)
S("color_grading", true); S("color_grading_saturation", 1.1); S("color_grading_contrast", 1.05)

------------------------------------------------------------------ playfield geometry
-- 13 columns x 13 rows of 2-unit tiles; row 0 is the surface lane, rows 1..12 are earth (4 strata x 3 rows).
-- Earth is resolved in 1-unit sub-cells (2x2 per tile) so digging is smooth.
local COLS, ROWS = 13, 13
local TOPY = 13                                  -- top edge of row 0
local function tx(c) return (c - (COLS - 1) / 2) * 2 end
local function ty(r) return TOPY - 1 - r * 2 end
local function col_of(x) return floor((x + COLS) / 2) end
local function row_of(y) return floor((TOPY - y) / 2) end
local SCOLS, SROWS = COLS * 2, ROWS * 2
local function scx(i) return -COLS + i + 0.5 end
local function scy(j) return TOPY - j - 0.5 end
local function stratum(r) return clamp(floor((r - 1) / 3), 0, 3) end
local XMIN, XMAX, YMIN, YMAX = tx(0), tx(COLS - 1), ty(ROWS - 1), ty(0)
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1280, surf.height or 720
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local FOVX = 0.75
local CAM = { z = 60, cy = -0.6 }
local function fit_camera()
    local aspect = SW / max(1, SH)
    local half_h = 17.4
    CAM.z = half_h * aspect / math.tan(FOVX * 0.5)
end
pcall(function() cam:set_fov(math.deg(FOVX)) end)
fit_camera()
cam:set_position(vec3(0, CAM.cy - 2, CAM.z)); cam:look_at(vec3(0, CAM.cy, 0))

------------------------------------------------------------------ templates -> clones
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[DigDug] missing template " .. name); return nil end
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

------------------------------------------------------------------ palette {base, emissive, roughness, metallic}
KK.STRATA = { { .95, .72, .25 }, { .9, .45, .14 }, { .68, .2, .1 }, { .38, .13, .14 } }
KK.PEBBLE = { { .55, .5, .42 }, { .5, .42, .36 }, { .4, .33, .3 }, { .3, .27, .3 } }
local PAL = {
    dig_suit = { { .95, .96, 1 }, { .05, .05, .06 }, .35, 0 }, dig_trim = { { .1, .35, 1 }, { .02, .08, .3 }, .25, .3 },
    dig_visor = { { .3, .8, 1 }, { .5, 1.6, 2.4 }, .05, 0 }, dig_gun = { { .7, .72, .78 }, { 0, 0, 0 }, .25, .9 },
    pooka_body = { { 1, .12, .08 }, { .35, .02, .01 }, .3, 0 }, pooka_lens = { { 1, .95, .4 }, { 2.2, 2.0, .6 }, .05, 0 },
    pooka_rim = { { .95, .95, .95 }, { .1, .1, .1 }, .3, .2 }, pooka_feet = { { 1, .85, .7 }, { .05, .03, .02 }, .5, 0 },
    fygar_body = { { .15, .8, .2 }, { .02, .2, .03 }, .35, 0 }, fygar_belly = { { .85, .95, .5 }, { .1, .12, .03 }, .4, 0 },
    fygar_wing = { { .95, .95, .9 }, { .2, .2, .2 }, .4, 0 }, fygar_eye = { { 1, 1, 1 }, { .8, .8, .7 }, .1, 0 },
    fygar_pupil = { { .05, .05, .05 }, { 1.8, .1, .05 }, .1, 0 }, fygar_feet = { { .9, .7, .2 }, { .1, .05, 0 }, .4, 0 },
    rock = { { .52, .48, .46 }, { 0.01, 0.01, 0.01 }, .75, 0 }, rock_crack = { { .1, .08, .07 }, { 0, 0, 0 }, .9, 0 },
    hose = { { .9, .9, .95 }, { .3, .45, .6 }, .3, .4 }, harpoon = { { .8, .85, .95 }, { .6, 1.0, 1.6 }, .2, .8 },
    flame = { { 1, .45, .1, 1 }, { 6, 1.8, .25 }, .5, 0 }, flame_core = { { 1, .9, .5 }, { 7, 5.5, 2.2 }, .5, 0 },
    fl_stem = { { .2, .7, .2 }, { .02, .1, .02 }, .5, 0 }, fl_petal = { { 1, .95, .95 }, { .3, .3, .35 }, .4, 0 },
    fl_center = { { 1, .8, .1 }, { 1.2, .8, .05 }, .4, 0 }, grass = { { .25, .8, .2 }, { .03, .15, .02 }, .6, 0 },
    carrot = { { 1, .45, .05 }, { .5, .15, 0 }, .4, 0 }, carrot_top = { { .2, .9, .2 }, { .05, .3, .05 }, .5, 0 },
    mush_cap = { { 1, .2, .25 }, { .4, .05, .05 }, .3, 0 }, mush_stem = { { 1, .95, .85 }, { .15, .12, .1 }, .5, 0 },
    orb = { { .6, .8, 1, 1 }, { .8, 1.2, 2.0 }, .2, 0 },
}
local function paint_templates()
    for k, p in pairs(PAL) do paint(tnode("T_" .. k), p[1], p[2], p[3], p[4]) end
    for s = 0, 3 do
        local c = KK.STRATA[s + 1]
        for v = 0, 2 do
            local k = 0.9 + 0.08 * v
            paint(tnode("T_dirt_" .. s .. "_" .. v), { c[1] * k, c[2] * k, c[3] * k }, { c[1] * 0.04, c[2] * 0.03, c[3] * 0.02 }, 0.85, 0)
        end
        local pc = KK.PEBBLE[s + 1]
        paint(tnode("T_pebble_" .. s), pc, { 0, 0, 0 }, 0.55, 0.05)
    end
    pcall(_mds, tnode("T_fygar_wing"), true)
end

------------------------------------------------------------------ lights
local function add_point() lights.add_point(); return #lights.get_point_lights() - 1 end
KK.LNODE = {}
KK.LIGHT_GAIN = 0.12
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
    lights.set_directional_light(0, vec3(-0.45, -0.55, -0.7), vec3(1.0, 0.9, 0.8), 2.4)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    L.sun = addp(vec3(-14, 22, 16), vec3(1.0, 0.8, 0.6), 160, 45)
    L.fill = addp(vec3(16, -6, 18), vec3(0.45, 0.55, 1.0), 90, 45)
    L.lamp = addp(HIDE, vec3(1.0, 0.85, 0.6), 0, 1)
    L.fire = {}
    for i = 1, 3 do L.fire[i] = addp(HIDE, vec3(1, 0.5, 0.1), 0, 1) end
    L.flash = {}
    for i = 1, 5 do L.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1, power = 0, rad = 6 } end
end
local flash_next = 1
local function flash(x, y, col, power, life, rad)
    local f = L.flash[flash_next]; flash_next = flash_next % #L.flash + 1
    f.t, f.life, f.pos, f.col, f.power, f.rad = 0, life or 0.35, vec3(x, y, 2.5), vec3(col[1], col[2], col[3]), power or 40, rad or 8
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

------------------------------------------------------------------ particles
local PSCALE, SHAKE_SCALE = 1.0, 1.0
local function burst(x, y, o)
    pcall(particles.emit_burst, {
        position = vec3(x, y, o.z or 0.6), velocity = o.vel or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = max(1, floor((o.count or 40) * PSCALE)),
        size_min = o.smin or 0.05, size_max = o.smax or 0.16, life_min = o.lmin or 0.25, life_max = o.lmax or 0.7,
        spawn_radius = o.radius or 0.3, noise_strength = o.spread or 14, drag = o.drag or 2.0,
        gravity = o.grav or vec3(0, 0, 0), cleanup_delay = 3.0,
    })
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
    pcall(particles.set_emitter, e, "spawn_rate", rate * PSCALE)
    if vel then pcall(particles.set_emitter, e, "velocity", vel) end
end
local function crumbs(x, y, s, n)
    local c = KK.STRATA[s + 1]
    burst(x, y, { c0 = vec4(c[1] * 1.1, c[2] * 1.1, c[3] * 1.1, 1), c1 = vec4(c[1] * 0.5, c[2] * 0.4, c[3] * 0.3, 0), count = n or 10,
        smin = 0.06, smax = 0.16, lmin = 0.3, lmax = 0.7, radius = 0.4, spread = 5, drag = 1.2, grav = vec3(0, -14, 0), z = 0.7 })
end

------------------------------------------------------------------ debris shards + shockwave rings
KK.SHARD_COL = { [0] = KK.STRATA[1], KK.STRATA[2], KK.STRATA[3], KK.STRATA[4], { .55, .5, .48 }, { 1, .15, .1 }, { .2, .85, .25 } }
local SHARDS, live_shards = {}, {}
local function build_debris()
    for c = 0, 6 do
        local col = KK.SHARD_COL[c]
        local e = c >= 5 and 0.6 or 0.03
        paint(tnode("T_shard_" .. c), col, { col[1] * e, col[2] * e, col[3] * e }, 0.6, 0.0)
        SHARDS[c] = { next = 1 }
        for k = 1, 12 do SHARDS[c][k] = { node = clone("T_shard_" .. c, HIDE, vec3(0.4, 0.4, 0.4)), life = 0 } end
    end
end
local function shatter(slot, x, y, n, power, grav)
    local pool = SHARDS[slot] or SHARDS[4]
    for _ = 1, floor((n or 8) * (0.4 + 0.6 * PSCALE) + 0.5) do
        local s = pool[pool.next]; pool.next = pool.next % #pool + 1
        local a, sp = rr(0, TAU), rr(3, 10) * (power or 1)
        s.x, s.y, s.z = x, y, rr(0.2, 1.0)
        s.vx, s.vy, s.vz = cos(a) * sp, sin(a) * sp + 4, rr(0, 6)
        s.rx, s.ry, s.rz = rr(0, 360), rr(0, 360), rr(0, 360)
        s.wx, s.wy, s.wz = rr(-600, 600), rr(-600, 600), rr(-600, 600)
        s.sz = rr(0.35, 0.7); s.life = rr(0.6, 1.1); s.g = grav or 22
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
            local d = math.exp(-1.2 * dt)
            s.vx, s.vy, s.vz = s.vx * d, (s.vy - s.g * dt) * d, s.vz * d
            s.x, s.y, s.z = s.x + s.vx * dt, s.y + s.vy * dt, s.z + s.vz * dt
            s.rx, s.ry, s.rz = s.rx + s.wx * dt, s.ry + s.wy * dt, s.rz + s.wz * dt
            local k = clamp(s.life / 0.35, 0, 1) * s.sz
            s.node:set_position(vec3(s.x, s.y, s.z)); s.node:set_rotation(vec3(s.rx, s.ry, s.rz)); s.node:set_scale(vec3(k, k, k))
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
            r.node:set_position(vec3(r.x, r.y, 1.2)); r.node:set_scale(vec3(s, s, 1 + 2 * (1 - k)))
            local f = (1 - k) ^ 2 * 3
            mlive(r.mat, "emissive", vec3(r.col[1] * f, r.col[2] * f, r.col[3] * f))
            if r.t >= r.life then r.node:set_position(HIDE) end
        end
    end
end
local shake = 0
local function add_shake(a) shake = min(1.0, shake + a) end
-- balloon pop: white core, coloured confetti, sparkles, debris, ring, light
local function pop_fx(x, y, col, slot)
    burst(x, y, { c0 = vec4(3, 3, 3, 1), c1 = vec4(col[1] * 2, col[2] * 2, col[3] * 2, 0), count = 24, smin = 0.25, smax = 0.5,
        lmin = 0.08, lmax = 0.2, radius = 0.4, spread = 6, drag = 4, z = 1.2 })
    burst(x, y, { c0 = vec4(col[1] * 2.2 + .4, col[2] * 2.2 + .4, col[3] * 2.2 + .4, 1), c1 = vec4(col[1], col[2], col[3], 0), count = 70,
        smin = 0.08, smax = 0.2, lmin = 0.4, lmax = 0.9, radius = 0.6, spread = 22, drag = 2.5, grav = vec3(0, -6, 0), z = 1.0 })
    burst(x, y, { c0 = vec4(2.5, 2.3, 1.6, 1), c1 = vec4(1, .6, .2, 0), count = 40, smin = 0.03, smax = 0.07,
        lmin = 0.3, lmax = 0.7, radius = 0.2, spread = 30, drag = 1.6, z = 1.0 })
    shatter(slot, x, y, 8, 1)
    shockwave(x, y, col, 3.6, 0.45)
    flash(x, y, col, 70, 0.35, 9)
    add_shake(0.18)
end

------------------------------------------------------------------ backdrop: sky, tunnel back wall, grass, flowers
local WORLD = { flowers = {} }
local function build_backdrop()
    local sky = prim("quad", vec3(0, TOPY + 10, -14), vec3(90, 22, 1))
    paint(sky, { 0, 0, 0 }, { 1.0, 1.0, 1.0 }, 1.0, 0.0); mtex(sky, "emissive", "Textures/sky.png")
    pcall(_mds, sky, true); qpush(function() pcall(_mds, sky, true) end)
    local back = prim("quad", vec3(0, (TOPY - 2 + ty(ROWS - 1) - 1) / 2, -0.62), vec3(COLS * 2 + 0.2, (ROWS - 1) * 2, 1))
    paint(back, { 0.3, 0.2, 0.14 }, { 0.55, 0.45, 0.4 }, 0.95, 0.0); mtex(back, "emissive", "Textures/tunnel.png"); mtex(back, "base_color", "Textures/tunnel.png")
    pcall(_mds, back, true); qpush(function() pcall(_mds, back, true) end)
    WORLD.back = back
    local deep = prim("quad", vec3(0, -20, -1.5), vec3(140, 62, 1))
    paint(deep, { 0.05, 0.035, 0.03 }, { 0.22, 0.17, 0.15 }, 0.95, 0.0); mtex(deep, "emissive", "Textures/tunnel.png")
    pcall(_mds, deep, true); qpush(function() pcall(_mds, deep, true) end)
    -- frame: dark bedrock below and walls on the sides (outside the playfield)
    local function slab(x, y, w, h)
        local n = prim("cube", vec3(x, y, -0.2), vec3(w, h, 1.4))
        paint(n, { 0.07, 0.05, 0.05 }, { 0.0, 0.0, 0.0 }, 0.9, 0.0)
    end
    -- grass crown along the top of the earth
    for i = 0, COLS * 3 do
        local x = -COLS - 0.5 + i * (2 * COLS + 1) / (COLS * 3)
        local g = clone("T_grass", vec3(x + rr(-0.2, 0.2), TOPY - 2.05, rr(-0.2, 0.5)), vec3(rr(0.9, 1.3), rr(0.8, 1.4), 1))
        g:set_rotation(vec3(0, rr(0, 180), 0))
    end
end
local function make_flower(i)
    local f = {}
    f.stem = clone("T_fl_stem", HIDE); f.petal = clone("T_fl_petal", HIDE); f.center = clone("T_fl_center", HIDE)
    return f
end
local function build_flowers() for i = 1, 10 do WORLD.flowers[i] = make_flower(i) end end
local function draw_flowers(n)
    for i, f in ipairs(WORLD.flowers) do
        local show = i <= min(n, 10)
        local x = COLS - 1 - (i - 1) * 1.1
        local sc = (i == 1 and n >= 10) and 1.6 or 1.0
        local p = show and vec3(x, TOPY - 2.05, 0.3) or HIDE
        local sway = 6 * sin(G.t * 1.7 + i)
        for _, nd in ipairs({ f.stem, f.petal, f.center }) do nd:set_position(p); nd:set_scale(vec3(sc, sc, sc)); nd:set_rotation(vec3(0, 0, sway)) end
    end
end

------------------------------------------------------------------ earth: sub-cell blocks
local EARTH = { cells = {}, dug = {}, peb = {} }
local function sidx(i, j) return j * SCOLS + i end
local function build_earth()
    for j = 2, SROWS - 1 do
        local s = stratum(floor(j / 2))
        for i = 0, SCOLS - 1 do
            local v = (i * 7 + j * 13 + floor(i / 3) * 5) % 3
            local n = clone("T_dirt_" .. s .. "_" .. v, HIDE)
            EARTH.cells[sidx(i, j)] = { node = n, i = i, j = j, s = s, rz = rr(-6, 6), zz = rr(-0.06, 0.06), k = rr(0.97, 1.04) }
            if rand() < 0.11 then
                local p = clone("T_pebble_" .. s, HIDE)
                EARTH.peb[sidx(i, j)] = { node = p, ox = rr(-0.25, 0.25), oy = rr(-0.25, 0.25), r = rr(0, 360), k = rr(0.35, 0.6) }
            end
        end
    end
end
KK.GEMC = { { .3, 1, .9 }, { 1, .3, .9 }, { .5, .6, 1 } }
local GEMS = {}
local function build_gems()
    for g = 0, 2 do local c = KK.GEMC[g + 1]; paint(tnode("T_gem_" .. g), { c[1], c[2], c[3] }, { c[1] * 2.2, c[2] * 2.2, c[3] * 2.2 }, 0.05, 0.3) end
    for k = 1, 14 do GEMS[k] = { node = clone("T_gem_" .. (k % 3), HIDE), ph = rr(0, 6) } end
end
local function place_gems()
    for _, g in ipairs(GEMS) do
        local i, j = rand(0, SCOLS - 1), rand(8, SROWS - 1)
        g.id = sidx(i, j); g.x, g.y = scx(i) + rr(-0.2, 0.2), scy(j) + rr(-0.2, 0.2); g.r = rr(-40, 40); g.live = true
    end
end
local function show_cell(id, on)
    local c = EARTH.cells[id]; if not c then return end
    if on then
        c.node:set_position(vec3(scx(c.i), scy(c.j), c.zz)); c.node:set_rotation(vec3(0, 0, c.rz)); c.node:set_scale(vec3(c.k, c.k, 1))
    else c.node:set_position(HIDE) end
    local p = EARTH.peb[id]
    if p then
        if on then p.node:set_position(vec3(scx(c.i) + p.ox, scy(c.j) + p.oy, 0.5)); p.node:set_rotation(vec3(p.r, p.r * 0.7, p.r)); p.node:set_scale(vec3(p.k, p.k, p.k))
        else p.node:set_position(HIDE) end
    end
end
local function is_dug(i, j)
    if j < 2 then return true end
    if i < 0 or i >= SCOLS or j >= SROWS then return false end
    return EARTH.dug[sidx(i, j)] == true
end
local function dig_cell(i, j, fx)
    if j < 2 or i < 0 or i >= SCOLS or j >= SROWS then return false end
    local id = sidx(i, j)
    if EARTH.dug[id] then return false end
    EARTH.dug[id] = true; show_cell(id, false)
    if fx then crumbs(scx(i), scy(j), EARTH.cells[id].s, 6) end
    for _, g in ipairs(GEMS) do
        if g.live and g.id == id then
            g.live = false; g.node:set_position(HIDE)
            if fx then
                local c = KK.GEMC[1]
                burst(g.x, g.y, { c0 = vec4(2.5, 2.5, 2.5, 1), c1 = vec4(.3, .8, 1, 0), count = 30, smin = .03, smax = .09, lmin = .3, lmax = .7, spread = 16, z = 1 })
                G.gem_bonus = (G.gem_bonus or 0) + 1
            end
        end
    end
    return true
end
local function tile_open(c, r)
    if c < 0 or c >= COLS or r < 0 or r >= ROWS then return false end
    if r == 0 then return true end
    local i, j = c * 2, r * 2
    return is_dug(i, j) and is_dug(i + 1, j) and is_dug(i, j + 1) and is_dug(i + 1, j + 1)
end
local function dig_tile(c, r) for a = 0, 1 do for b = 0, 1 do dig_cell(c * 2 + a, r * 2 + b, false) end end end
local function reset_earth()
    EARTH.dug = {}
    for id, _ in pairs(EARTH.cells) do show_cell(id, true) end
end
-- dig the sub-cells overlapped by a 2x2 body centred at (x,y); returns number dug
local function dig_at(x, y)
    local n = 0
    local i0, i1 = floor(x - 1 + COLS + 0.02), floor(x + 1 + COLS - 0.02)
    local j0, j1 = floor(TOPY - (y + 1) + 0.02), floor(TOPY - (y - 1) - 0.02)
    for i = i0, i1 do for j = j0, j1 do if dig_cell(i, j, true) then n = n + 1 end end end
    return n
end
-- is the point inside solid earth?
local function solid_at(x, y)
    local i, j = floor(x + COLS), floor(TOPY - y)
    if j < 2 then return false end
    if i < 0 or i >= SCOLS or j >= SROWS then return true end
    return not EARTH.dug[sidx(i, j)]
end

------------------------------------------------------------------ rocks
local ROCKS = {}
local function rock_at_tile(c, r)
    for _, k in ipairs(ROCKS) do if k.alive and k.state == "idle" and k.c == c and k.r == r then return k end end
end
local function build_rocks()
    for i = 1, 6 do
        local root = scene.add_empty_node("rock" .. i); root:set_position(HIDE)
        local body = clone("T_rock", vec3(0, 0, 0), nil, root)
        local crack = clone("T_rock_crack", vec3(0, 0, 0), nil, root)
        ROCKS[i] = { root = root, crack = crack, alive = false }
    end
end
local function place_rock(k, c, r)
    k.alive, k.state, k.c, k.r, k.x, k.y, k.vy, k.t, k.carry = true, "idle", c, r, tx(c), ty(r), 0, 0, {}
    k.root:set_position(vec3(k.x, k.y, 0.1)); k.root:set_rotation(vec3(rr(-10, 10), rr(0, 360), rr(-8, 8))); k.root:set_scale(vec3(1, 1, 1))
    k.crack:set_enabled(false)
    for a = 0, 1 do for b = 0, 1 do local id = sidx(c * 2 + a, r * 2 + b); local cc = EARTH.cells[id]; if cc then cc.node:set_position(HIDE) end; local pb = EARTH.peb[id]; if pb then pb.node:set_position(HIDE) end end end
end
local function kill_rock(k) k.alive = false; k.root:set_position(HIDE) end

------------------------------------------------------------------ characters
local function make_digger()
    seq = seq + 1
    local root = scene.add_empty_node("digger" .. seq); root:set_position(HIDE)
    local pivot = scene.add_empty_node("diggerpivot" .. seq); pivot:set_parent(root)
    local d = { root = root, pivot = pivot }
    for _, p in ipairs({ "suit", "trim", "visor", "gun" }) do d[p] = clone("T_dig_" .. p, vec3(0, 0, 0), nil, pivot) end
    return d
end
local function make_enemy_model(kind)
    seq = seq + 1
    local root = scene.add_empty_node(kind .. seq); root:set_position(HIDE)
    local pivot = scene.add_empty_node(kind .. "pv" .. seq); pivot:set_parent(root)
    local m = { root = root, pivot = pivot, kind = kind, bodies = {}, ghostpart = {} }
    local parts = kind == "pooka" and { "body", "lens", "rim", "feet" } or { "body", "belly", "wing", "eye", "pupil", "feet" }
    for _, p in ipairs(parts) do
        local n = clone("T_" .. kind .. "_" .. p, vec3(0, 0, 0), nil, pivot)
        m[p] = n
        if p == "lens" or p == "eye" or p == "pupil" then m.ghostpart[#m.ghostpart + 1] = n else m.bodies[#m.bodies + 1] = n end
    end
    if kind == "fygar" then
        m.flame = clone("T_flame", HIDE); m.flame_core = clone("T_flame_core", HIDE)
    end
    m.ghost_orb = clone("T_orb", HIDE)
    return m
end
local function model_ghost(m, on)
    if m.is_ghost == on then return end
    m.is_ghost = on
    for _, n in ipairs(m.bodies) do n:set_enabled(not on) end
end

------------------------------------------------------------------ player + harpoon
local P = { x = 0, y = 0, dir = 1, fx = 1, fy = 0, state = "none", vx = 0, vy = 0, ang = 0, walk = 0 }
local HARP = { on = false, len = 0, target = nil }
local function build_player()
    P.m = make_digger()
    HARP.hose = clone("T_hose", HIDE); HARP.tip = clone("T_harpoon", HIDE)
    P.dust = new_emitter({ c0 = vec4(0.9, 0.7, 0.4, 0.9), c1 = vec4(0.4, 0.25, 0.15, 0), count = 200, radius = 0.5, smin = 0.05, smax = 0.12,
        lmin = 0.25, lmax = 0.6, noise = 3.0, drag = 1.5, grav = vec3(0, -6, 0) })
end

------------------------------------------------------------------ enemies
local POOL = { pooka = {}, fygar = {} }
local enemies = {}
local function build_enemy_pools()
    for i = 1, 6 do POOL.pooka[i] = { m = make_enemy_model("pooka"), used = false } end
    for i = 1, 4 do POOL.fygar[i] = { m = make_enemy_model("fygar"), used = false } end
end
local function release_model(e)
    for _, p in ipairs(POOL[e.kind]) do
        if p.m == e.m then
            p.used = false; e.m.root:set_position(HIDE); e.m.ghost_orb:set_position(HIDE)
            if e.m.flame then e.m.flame:set_position(HIDE); e.m.flame_core:set_position(HIDE) end
            model_ghost(e.m, false)
        end
    end
end
local function new_enemy(kind, c, r)
    local slot
    for _, p in ipairs(POOL[kind]) do if not p.used then slot = p; break end end
    if not slot then return nil end
    slot.used = true
    local e = { kind = kind, m = slot.m, c0 = c, r0 = r, alive = true }
    enemies[#enemies + 1] = e
    return e
end
local function reset_enemy(e)
    e.x, e.y, e.dx, e.dy = tx(e.c0), ty(e.r0), (rand() < 0.5 and 1 or -1), 0
    e.face = e.dx; e.state = "move"; e.inf, e.infv, e.pump_t = 0, 0, 0
    e.ghost_t, e.ghost_wait, e.tc, e.exiting = 0, rr(7, 13), nil, false; e.fire_t, e.fire_cd = 0, rr(2, 5); e.flee = false
    e.spd = 3.6 + min(G.round, 10) * 0.18; e.vis_face = e.face; e.anim = rr(0, 6)
    model_ghost(e.m, false)
end
local function remove_enemy(e)
    e.alive = false; release_model(e)
    for i, x in ipairs(enemies) do if x == e then table.remove(enemies, i); break end end
end

-- BFS distance field over open tiles from (c,r)
local function bfs(c0, r0)
    local D = {}
    if c0 < 0 or c0 >= COLS or r0 < 0 or r0 >= ROWS then return D end
    local q, h = { { c0, r0 } }, 1
    D[r0 * COLS + c0] = 0
    while h <= #q do
        local c, r = q[h][1], q[h][2]; h = h + 1
        local d = D[r * COLS + c]
        for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local nc, nr = c + o[1], r + o[2]
            local k = nr * COLS + nc
            if not D[k] and tile_open(nc, nr) then D[k] = d + 1; q[#q + 1] = { nc, nr } end
        end
    end
    return D
end
local FIELD = { t = 0 }
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }     -- dx, dy in WORLD (dy=1 up); rows grow downward
local function choose_dir(e, c, r, field)
    local best, bestd, opts = nil, 1e9, {}
    for _, d in ipairs(DIRS) do
        local nc, nr = c + d[1], r - d[2]
        if tile_open(nc, nr) and not (nr == 0 and not e.flee and r ~= 0 and rand() < 0.85) then
            local reverse = d[1] == -e.dx and d[2] == -e.dy
            opts[#opts + 1] = { d = d, rev = reverse }
            local fd = field and field[nr * COLS + nc]
            if fd and (not reverse or fd == 0) and fd < bestd then best, bestd = d, fd end
        end
    end
    if #opts == 0 then return nil end
    if best and (e.flee or rand() < 0.7) then return best end
    local nonrev = {}
    for _, o in ipairs(opts) do if not o.rev then nonrev[#nonrev + 1] = o.d end end
    if #nonrev > 0 then return nonrev[rand(#nonrev)] end
    return opts[1].d
end

------------------------------------------------------------------ projection, popups, scoring
CAM.look = { 0, CAM.cy, 0 }
local function project(x, y, z)
    local C = cam:get_position()
    local fx, fy, fz = CAM.look[1] - C.x, CAM.look[2] - C.y, CAM.look[3] - C.z
    local fl = sqrt(fx * fx + fy * fy + fz * fz); fx, fy, fz = fx / fl, fy / fl, fz / fl
    local rx, ry, rz = -fz, 0, fx
    local rl = sqrt(rx * rx + rz * rz); rx, rz = rx / rl, rz / rl
    local ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
    local px, py, pz = x - C.x, y - C.y, (z or 0) - C.z
    local d = px * fx + py * fy + pz * fz
    local sx = (px * rx + py * ry + pz * rz) / (d * math.tan(FOVX * 0.5))
    local sy = (px * ux + py * uy + pz * uz) / (d * math.tan(FOVX * 0.5) * SH / SW)
    return SW * 0.5 * (1 + sx), SH * 0.5 * (1 - sy)
end
local POPS = {}
local function popup(x, y, txt, col)
    POPS[#POPS + 1] = { x = x, y = y, txt = txt, col = col or { 1, 1, 1 }, t = 0 }
    if #POPS > 6 then table.remove(POPS, 1) end
end
G.score, G.hiscore = 0, 10000
KK.HISAVE = "Save/hiscore.txt"
do local s = fs.read and fs.read(KK.HISAVE); local v = s and tonumber(s); if v then G.hiscore = v end end
local score_pop = 0
local function add_score(n)
    local before = G.score
    G.score = G.score + n; score_pop = 1
    if G.score > G.hiscore then G.hiscore = G.score end
    for _, th in ipairs({ 10000, 40000, 80000, 120000 }) do
        if before < th and G.score >= th then G.lives = G.lives + 1; sfx("extra"); popup(P.x, P.y + 2, "1UP", { .4, 1, .5 }) end
    end
end
local function show_banner(t, s, d) G.banner = { text = t, sub = s or "", t = 0, dur = d or 2 } end
G.banner = { text = "", sub = "", t = 9, dur = 0 }
KK.POP_SCORE = { 200, 300, 400, 500 }
KK.CRUSH = { 1000, 2500, 4000, 6000, 8000, 10000, 12000, 15000 }
KK.VEG = { { "carrot", 400 }, { "mush", 600 }, { "carrot", 800 }, { "mush", 1000 }, { "carrot", 2000 }, { "mush", 3000 } }

------------------------------------------------------------------ bonus vegetable
local VEG = { on = false }
local function build_veg()
    VEG.carrot = { clone("T_carrot", HIDE), clone("T_carrot_top", HIDE) }
    VEG.mush = { clone("T_mush_cap", HIDE), clone("T_mush_stem", HIDE) }
    VEG.spark = new_emitter({ c0 = vec4(2.5, 2.2, 1.0, 1), c1 = vec4(1, .6, .2, 0), count = 200, radius = 1.0, smin = 0.04, smax = 0.1,
        lmin = 0.4, lmax = 0.9, noise = 2.0, drag = 1.0, vel = vec3(0, 1.2, 0) })
end
local function spawn_veg()
    local v = KK.VEG[min(G.round, #KK.VEG)]
    VEG.on, VEG.kind, VEG.pts, VEG.t, VEG.x, VEG.y = true, v[1], v[2], 0, tx(6), ty(6)
    sfx("bonus")
end
local function draw_veg(dt)
    for _, k in ipairs({ "carrot", "mush" }) do
        for _, n in ipairs(VEG[k]) do
            if VEG.on and VEG.kind == k then
                local b = 1 + 0.08 * sin(G.t * 6)
                n:set_position(vec3(VEG.x, VEG.y + 0.15 * sin(G.t * 3), 0.3)); n:set_rotation(vec3(0, G.t * 70, k == "carrot" and 25 or 0)); n:set_scale(vec3(b, b, b))
            else n:set_position(HIDE) end
        end
    end
    emitter_at(VEG.spark, VEG.on and VEG.x or 0, VEG.on and VEG.y or -1000, 0.6, VEG.on and 30 or 0)
end

------------------------------------------------------------------ input
local prev = {}
G.vkeys = {}
local function kdown(k) if G.vkeys[k] then return true end local ok, r = pcall(input.is_key_down_raw, k); return ok and r end
local function pressed(k) local d = kdown(k); local p = prev[k]; prev[k] = d; return d and not p end
local WATCH = { "Left", "Right", "A", "D", "Up", "Down", "W", "S", "Space", "Return", "Escape", "P", "M", "LCtrl" }
local function latch() for _, k in ipairs(WATCH) do prev[k] = kdown(k) end end
local mouse_prev_down = false
local function mouse_down() local ok, d = pcall(input.is_left_mouse_down); return (ok and d) or G.vkeys.Click end
local function mouse_clicked() local d = mouse_down(); local c = d and not mouse_prev_down; mouse_prev_down = d; return c end

------------------------------------------------------------------ player logic
local function blocked(nx, ny)
    for _, k in ipairs(ROCKS) do
        if k.alive and (k.state == "idle" or k.state == "wobble") and abs(nx - k.x) < 1.85 and abs(ny - k.y) < 1.85 then return true end
    end
    for _, e in ipairs(enemies) do
        if e.state == "inflate" and e ~= HARP.target and abs(nx - e.x) < 1.6 and abs(ny - e.y) < 1.6 then return true end
    end
    return false
end
local function harp_off() HARP.on = false; HARP.target = nil; HARP.len = 0 end
local function player_die(cause)
    if P.state ~= "alive" then return end
    P.state = "dying"; P.dt = 0; harp_off(); sfx("death")
    if cause == "fire" then burst(P.x, P.y, { c0 = vec4(4, 2, .4, 1), c1 = vec4(1, .2, 0, 0), count = 60, smin = .1, smax = .3, lmin = .3, lmax = .8, spread = 10 }) end
    flash(P.x, P.y, { 1, .6, .4 }, 50, 0.6, 8); add_shake(0.35)
end
local function want_dir(control)
    if control == "auto" then return G.auto_dx or 0, G.auto_dy or 0 end
    local kx = ((kdown("Right") or kdown("D")) and 1 or 0) - ((kdown("Left") or kdown("A")) and 1 or 0)
    local ky = ((kdown("Up") or kdown("W")) and 1 or 0) - ((kdown("Down") or kdown("S")) and 1 or 0)
    -- the most recently pressed axis wins when both are held
    if kx ~= 0 and ky ~= 0 then
        if P.last_axis == "x" then ky = 0 else kx = 0 end
    elseif kx ~= 0 then P.last_axis = "y" elseif ky ~= 0 then P.last_axis = "x" end
    return kx, ky
end
local function step_axis(cur, target, d) if abs(target - cur) <= d then return target, true end; return cur + sgn(target - cur) * d, false end
local function move_player(dt, control)
    local wx, wy = want_dir(control)
    if HARP.on then
        if HARP.target and (wx ~= 0 or wy ~= 0) and (wx ~= P.fx or wy ~= P.fy) then harp_off() end
        if HARP.on then P.moving = false; return end
    end
    if wx == 0 and wy == 0 then P.moving = false; return end
    local spd = (P.digging and 4.6 or 6.2) * dt
    local nx, ny = P.x, P.y
    local cc, rc = tx(clamp(col_of(P.x + 0.0001), 0, COLS - 1)), ty(clamp(row_of(P.y), 0, ROWS - 1))
    -- nearest lane centres
    local lc = tx(clamp(floor((P.x + COLS) / 2 + 0.5 - 0.5 + 0.5), 0, COLS - 1))
    local nearc = tx(clamp(math.floor((P.x - tx(0)) / 2 + 0.5), 0, COLS - 1))
    local nearr = ty(clamp(math.floor((ty(0) - P.y) / 2 + 0.5), 0, ROWS - 1))
    if wx ~= 0 then
        if abs(P.y - nearr) < 0.02 then nx = P.x + wx * spd; ny = nearr; P.fx, P.fy = wx, 0
        else ny = step_axis(P.y, nearr, spd); P.fx, P.fy = 0, sgn(nearr - P.y) end
    else
        if abs(P.x - nearc) < 0.02 then ny = P.y + wy * spd; nx = nearc; P.fx, P.fy = 0, wy
        else nx = step_axis(P.x, nearc, spd); P.fx, P.fy = sgn(nearc - P.x), 0 end
    end
    if P.fx ~= 0 then P.face = P.fx end
    nx, ny = clamp(nx, XMIN, XMAX), clamp(ny, YMIN, YMAX)
    if blocked(nx, ny) then P.moving = false; return end
    P.x, P.y = nx, ny; P.moving = true
    P.walk = P.walk + dt * 10
    local n = dig_at(P.x, P.y)
    P.digging = n > 0 or (P.dig_hold or 0) > 0
    P.dig_hold = n > 0 and 0.15 or max(0, (P.dig_hold or 0) - dt)
    if (G.gem_bonus or 0) > 0 then add_score(250 * G.gem_bonus); popup(P.x, P.y + 1.2, "GEM " .. (250 * G.gem_bonus), { .5, 1, .95 }); sfx("bonus"); G.gem_bonus = 0 end
    if n > 0 then G.dig_snd = (G.dig_snd or 0) - 1; if G.dig_snd <= 0 then sfx("dig"); G.dig_snd = 3 end end
end
local function fire_harpoon()
    if HARP.on or (P.harp_cd or 0) > 0 then return end
    HARP.on, HARP.len, HARP.target, HARP.dx, HARP.dy, HARP.retract = true, 0, nil, P.fx, P.fy, false
    if HARP.dx == 0 and HARP.dy == 0 then HARP.dx = P.face or 1 end
    sfx("shoot")
end
local function enemy_hit_by_tip(x, y)
    for _, e in ipairs(enemies) do
        if e.alive and e.state ~= "ghost" and e.state ~= "crushed" and e.state ~= "dead" and abs(e.x - x) < 1.1 and abs(e.y - y) < 1.1 then return e end
    end
end
local pump_enemy
local function update_harpoon(dt, fire_pressed, fire_held)
    P.harp_cd = max(0, (P.harp_cd or 0) - dt)
    if not HARP.on then
        if fire_pressed then fire_harpoon() end
        return
    end
    if HARP.target then
        local e = HARP.target
        if not e.alive or e.state ~= "inflate" then harp_off(); return end
        HARP.len = max(0, abs(e.x - P.x) + abs(e.y - P.y) - 1.4)
        HARP.pump_t = (HARP.pump_t or 0) - dt
        if fire_pressed or (fire_held and HARP.pump_t <= 0) then pump_enemy(e); HARP.pump_t = 0.32 end
        return
    end
    if HARP.retract then
        HARP.len = HARP.len - dt * 30
        if HARP.len <= 0 then harp_off(); P.harp_cd = 0.12 end
        return
    end
    HARP.len = HARP.len + dt * 26
    local tipx, tipy = P.x + HARP.dx * (0.9 + HARP.len), P.y + HARP.dy * (0.9 + HARP.len)
    local e = enemy_hit_by_tip(tipx, tipy)
    if e then HARP.target = e; HARP.pump_t = 0.32; pump_enemy(e); return end
    if solid_at(tipx, tipy) or HARP.len >= 5.0 then HARP.retract = true end
end
local function draw_harpoon()
    if not HARP.on or HARP.len <= 0.01 then HARP.hose:set_position(HIDE); HARP.tip:set_position(HIDE); return end
    local ang = HARP.dx ~= 0 and (HARP.dx > 0 and 0 or 180) or (HARP.dy > 0 and 90 or -90)
    local ox, oy = P.x + HARP.dx * 0.9, P.y + HARP.dy * 0.9 + (HARP.dx ~= 0 and 0.1 or 0)
    local wig = HARP.target and 0.06 * sin(G.t * 30) or 0
    HARP.hose:set_position(vec3(ox, oy, 0.3)); HARP.hose:set_rotation(vec3(0, 0, ang)); HARP.hose:set_scale(vec3(HARP.len, 1 + wig * 4, 1 + wig * 4))
    HARP.tip:set_position(vec3(ox + HARP.dx * HARP.len, oy + HARP.dy * HARP.len, 0.3)); HARP.tip:set_rotation(vec3(0, 0, ang))
end

------------------------------------------------------------------ enemy logic
local function enemy_color(e) return e.kind == "pooka" and { 1, .2, .12 } or { .25, 1, .3 } end
local function pop_enemy(e)
    local r = clamp(row_of(e.y), 0, ROWS - 1)
    local pts = KK.POP_SCORE[stratum(max(1, r)) + 1]
    if e.kind == "fygar" and HARP.dy == 0 then pts = pts * 2 end
    add_score(pts); popup(e.x, e.y + 1, tostring(pts), { 1, .95, .5 })
    pop_fx(e.x, e.y, enemy_color(e), e.kind == "pooka" and 5 or 6)
    sfx("pop"); harp_off()
    remove_enemy(e)
end
pump_enemy = function(e)
    if e.state ~= "inflate" then
        e.state = "inflate"; e.inf = 0; e.fire_t = 0
        if e.m.flame then e.m.flame:set_position(HIDE); e.m.flame_core:set_position(HIDE) end
    end
    e.inf = e.inf + 1; e.pump_t = 0; sfx("pump")
    burst(e.x, e.y, { c0 = vec4(1.5, 2, 2.5, 1), c1 = vec4(.3, .6, 1, 0), count = 12, smin = .04, smax = .1, lmin = .15, lmax = .35, spread = 12, z = 1 })
    if e.inf >= 4 then pop_enemy(e) end
end
local function snap_tile(e)
    local c, r = clamp(math.floor((e.x - tx(0)) / 2 + 0.5), 0, COLS - 1), clamp(math.floor((ty(0) - e.y) / 2 + 0.5), 0, ROWS - 1)
    return c, r
end
local function walk_enemy(e, dt, spd)
    if e.exiting then e.x = e.x - spd * dt; e.face = -1; return end
    local dist = spd * dt
    for _ = 1, 3 do
        if not e.tc then e.tc, e.tr = snap_tile(e) end
        local gx, gy = tx(e.tc), ty(e.tr)
        local ddx, ddy = gx - e.x, gy - e.y
        local len = abs(ddx) + abs(ddy)
        if len <= dist then
            e.x, e.y = gx, gy; dist = dist - len
            if e.flee and e.tr == 0 and e.tc == 0 then e.exiting = true; return end
            local d = choose_dir(e, e.tc, e.tr, e.flee and FIELD.flee or FIELD.chase)
            if not d then e.stuck = (e.stuck or 0) + dt; return end
            e.stuck = 0; e.dx, e.dy = d[1], d[2]; if d[1] ~= 0 then e.face = d[1] end
            e.tc, e.tr = e.tc + d[1], e.tr - d[2]
            if dist <= 0 then return end
        else
            if abs(ddx) > 1e-5 then local m = min(dist, abs(ddx)); e.x = e.x + sgn(ddx) * m; dist = dist - m end
            if dist > 0 and abs(ddy) > 1e-5 then local m = min(dist, abs(ddy)); e.y = e.y + sgn(ddy) * m end
            return
        end
    end
end
local function to_ghost(e)
    e.state = "ghost"; e.ghost_t = 0; model_ghost(e.m, true); sfx("ghost")
end
local function update_enemy(e, dt)
    e.anim = e.anim + dt
    if e.state == "move" then
        e.ghost_wait = e.ghost_wait - dt * ((e.stuck or 0) > 0.5 and 3 or 1)
        walk_enemy(e, dt, e.spd * (e.flee and 1.35 or 1))
        if e.flee and e.x < XMIN - 2.5 then
            popup(XMIN, YMAX + 1, "ESCAPED", { 1, .5, .5 }); remove_enemy(e); return
        end
        if e.flee and not e.exiting and FIELD.flee and e.tc and abs(e.x - tx(e.tc)) + abs(e.y - ty(e.tr)) < 1e-3 and not FIELD.flee[e.tr * COLS + e.tc] then to_ghost(e) end
        if e.ghost_wait <= 0 and not e.flee and e.tc and abs(e.x - tx(e.tc)) + abs(e.y - ty(e.tr)) < 1e-3 then to_ghost(e) end
        -- Fygar fire
        if e.kind == "fygar" and not e.flee and P.state == "alive" then
            e.fire_cd = e.fire_cd - dt
            if e.fire_cd <= 0 and e.dy == 0 and abs(e.y - P.y) < 1.0 and sgn(P.x - e.x) == e.face and abs(P.x - e.x) < 9 then
                e.state = "charge"; e.fire_t = 0; e.fire_cd = rr(3, 6) - min(G.round, 8) * 0.2
            elseif e.fire_cd <= 0 then e.fire_cd = rr(0.6, 1.5) end
        end
    elseif e.state == "charge" then
        e.fire_t = e.fire_t + dt
        if e.fire_t > 0.75 then e.state = "fire"; e.fire_t = 0; sfx("fire") end
    elseif e.state == "fire" then
        e.fire_t = e.fire_t + dt
        if e.fire_t > 1.0 then e.state = "move"; e.fire_t = 0; e.m.flame:set_position(HIDE); e.m.flame_core:set_position(HIDE) end
    elseif e.state == "ghost" then
        e.ghost_t = e.ghost_t + dt
        local gx, gy = P.x, P.y
        if e.flee then gx, gy = tx(0), ty(0) end
        local dx, dy = gx - e.x, gy - e.y
        local d = sqrt(dx * dx + dy * dy) + 1e-6
        local sp = 2.6 + min(G.round, 10) * 0.1
        e.x, e.y = e.x + dx / d * sp * dt, e.y + dy / d * sp * dt
        if dx ~= 0 then e.face = sgn(dx) end
        local c, r = snap_tile(e)
        if e.ghost_t > 1.6 and tile_open(c, r) and (not e.flee or (FIELD.flee and FIELD.flee[r * COLS + c])) and abs(e.x - tx(c)) < 0.35 and abs(e.y - ty(r)) < 0.35 then
            e.x, e.y = tx(c), ty(r); e.state = "move"; e.tc = nil; e.dx, e.dy = 0, 0; e.ghost_wait = rr(8, 14); model_ghost(e.m, false)
        end
    elseif e.state == "inflate" then
        e.pump_t = e.pump_t + dt
        if e.pump_t > 0.85 then
            e.pump_t = 0; e.inf = e.inf - 1
            if e.inf <= 0 then
                e.inf = 0; e.state = "move"; local c, r = snap_tile(e); e.x, e.y = tx(c), ty(r); e.tc = nil; e.dx, e.dy = 0, 0
                if HARP.target == e then harp_off() end
            end
        end
    end
    -- collisions with the player
    if P.state == "alive" and (e.state == "move" or e.state == "charge" or e.state == "fire") and abs(e.x - P.x) < 1.3 and abs(e.y - P.y) < 1.3 and (P.inv or 0) <= 0 then
        player_die("touch")
    end
    if e.state == "fire" and P.state == "alive" and (P.inv or 0) <= 0 then
        local len = min(1, e.fire_t * 4) * 5.0
        local x0 = e.x + e.face * 0.9
        if abs(P.y - e.y) < 0.9 and (P.x - x0) * e.face > -0.6 and (P.x - x0) * e.face < len + 0.4 then player_die("fire") end
    end
end

------------------------------------------------------------------ rock logic
local function rock_dust(x, y, n)
    burst(x, y, { c0 = vec4(.8, .7, .6, .8), c1 = vec4(.35, .3, .28, 0), count = n or 40, smin = .12, smax = .35, lmin = .5, lmax = 1.2,
        radius = 0.9, spread = 6, drag = 2.2, grav = vec3(0, 1.0, 0), z = 0.9 })
end
local function update_rock(k, dt)
    if k.state == "idle" then
        local below_open = is_dug(k.c * 2, k.r * 2 + 2) and is_dug(k.c * 2 + 1, k.r * 2 + 2)
        local under = P.state == "alive" and abs(P.x - k.x) < 1.9 and P.y < k.y and P.y > k.y - 3.9
        if below_open and not under then k.state = "wobble"; k.t = 0; sfx("wobble") end
    elseif k.state == "wobble" then
        k.t = k.t + dt
        k.root:set_rotation(vec3(0, 0, 7 * sin(k.t * 40)))
        k.root:set_position(vec3(k.x + 0.08 * sin(k.t * 53), k.y, 0.1))
        if k.t > 0.6 then
            k.state = "fall"; k.vy = 0; k.carry = {}
            dig_tile(k.c, k.r)
            G.rocks_dropped = (G.rocks_dropped or 0) + 1
        end
    elseif k.state == "fall" then
        k.vy = min(16, k.vy + 40 * dt)
        local ny = k.y - k.vy * dt
        local bottom = ny - 1.0
        local stop = bottom < YMIN - 1 or solid_at(k.x - 0.5, bottom) or solid_at(k.x + 0.5, bottom)
        if stop then
            ny = max(ny, ty(row_of(k.y)))
            k.y = ny; k.state = "land"; k.t = 0; sfx("crush"); rock_dust(k.x, k.y - 0.8, 50); add_shake(0.3)
            k.crack:set_enabled(true)
        else k.y = ny end
        if math.floor(G.t * 20) % 2 == 0 then rock_dust(k.x, k.y + 0.9, 6) end
        -- crush
        for _, e in ipairs(enemies) do
            if e.alive and e.state ~= "ghost" and e.state ~= "crushed" and abs(e.x - k.x) < 1.6 and e.y < k.y + 0.3 and k.y - e.y < 1.9 then
                e.state = "crushed"; k.carry[#k.carry + 1] = e
                if HARP.target == e then harp_off() end
            end
        end
        for _, e in ipairs(k.carry) do e.y = k.y - 1.2; e.x = damp(e.x, k.x, 12, dt) end
        if P.state == "alive" and abs(P.x - k.x) < 1.5 and P.y < k.y + 0.2 and k.y - P.y < 1.8 then
            P.state = "crushed_fall"; harp_off(); sfx("death"); P.carry_rock = k
        end
        if P.carry_rock == k then P.y = k.y - 1.2 end
        k.root:set_position(vec3(k.x, k.y, 0.1)); k.root:set_rotation(vec3(0, 0, 0))
    elseif k.state == "land" then
        k.t = k.t + dt
        local sq = 1 + 0.08 * max(0, 1 - k.t * 5)
        k.root:set_scale(vec3(sq, 2 - sq, 1))
        if k.t > 0.55 then
            -- crush score
            local n = 0
            for _, e in ipairs(k.carry) do if e.alive then n = n + 1; pop_fx(e.x, e.y, enemy_color(e), e.kind == "pooka" and 5 or 6); remove_enemy(e) end end
            if n > 0 then local pts = KK.CRUSH[min(n, #KK.CRUSH)]; add_score(pts); popup(k.x, k.y + 1.5, tostring(pts), { 1, .8, .3 }) end
            if P.carry_rock == k then P.carry_rock = nil; P.state = "alive"; player_die("rock") end
            shatter(4, k.x, k.y, 14, 1.2); rock_dust(k.x, k.y, 60); sfx("break"); flash(k.x, k.y, { 1, .85, .6 }, 30, 0.3, 7)
            kill_rock(k)
            if G.rocks_dropped == 2 and not G.veg_given then G.veg_given = true; spawn_veg() end
        end
    end
end

------------------------------------------------------------------ drawing actors
local function draw_player(dt)
    local m = P.m
    if P.state == "none" then m.root:set_position(HIDE); return end
    local tgt
    if P.fy > 0 then tgt = 90 elseif P.fy < 0 then tgt = -90 else tgt = 0 end
    if P.fx ~= 0 then tgt = 0 end
    P.ang = damp(P.ang, tgt, 18, dt)
    local face = P.face or 1
    P.yaw = damp(P.yaw or 0, face > 0 and 0 or 180, 16, dt)
    local bob = P.moving and abs(sin(P.walk)) * 0.12 or 0.03 * sin(G.t * 2.5)
    local sc = 1.2
    local roll = (face > 0 and 1 or -1) * P.ang
    if P.state == "dying" then
        local k = clamp(P.dt / 1.6, 0, 1)
        sc = 1.2 * (1 - k * 0.85); roll = P.dt * 720
    end
    local blink = (P.inv or 0) > 0 and floor(G.t * 12) % 2 == 0
    m.root:set_position(blink and HIDE or vec3(P.x, P.y + bob - 0.05, 0))
    m.root:set_rotation(vec3(0, P.yaw, roll))
    m.root:set_scale(vec3(sc, sc * (P.state == "crushed_fall" and 0.5 or 1), sc))
    m.pivot:set_rotation(vec3(0, 0, P.moving and 6 * sin(P.walk * 0.5) or 0))
    -- headlamp
    set_point(L.lamp, vec3(P.x + face * 1.2, P.y + 0.8, 2.6), vec3(1.0, 0.85, 0.6), 75, 10)
    local dig = P.state == "alive" and P.digging and P.moving
    emitter_at(P.dust, P.x + (P.fx or 0) * 1.0, P.y + (P.fy or 0) * 1.0, 0.6, dig and 70 or 0)
end
local function draw_enemy(e, dt)
    local m = e.m
    e.vis_face = damp(e.vis_face or 1, e.face or 1, 12, dt)
    local yaw = (1 - e.vis_face) * 90
    local s = 1.15
    local sx, sy = 1, 1
    local wob = 0
    if e.state == "inflate" then
        e.infv = damp(e.infv or 0, e.inf, 14, dt)
        local k = 1 + 0.32 * e.infv
        sx, sy = k + 0.04 * sin(G.t * 25), k - 0.04 * sin(G.t * 25)
    else e.infv = damp(e.infv or 0, 0, 10, dt) end
    if e.state == "move" then wob = 6 * sin(e.anim * 9) end
    if e.state == "charge" then local p = 1 + 0.08 * sin(e.fire_t * 50); sx, sy = p, 2 - p end
    if e.state == "crushed" then sx, sy = 1.3, 0.35 end
    local bob = e.state == "move" and abs(sin(e.anim * 9)) * 0.1 or 0
    m.root:set_position(vec3(e.x, e.y + bob - (e.kind == "fygar" and 0.05 or 0), e.state == "ghost" and 0.9 or 0))
    m.root:set_rotation(vec3(0, yaw, wob))
    m.root:set_scale(vec3(sx * s, sy * s, (sx + sy) * 0.5 * s))
    if e.state == "ghost" then
        local p = 0.75 + 0.15 * sin(G.t * 8 + e.anim)
        m.ghost_orb:set_position(vec3(e.x, e.y, 0.6)); m.ghost_orb:set_scale(vec3(p * 1.4, p * 1.4, p * 0.6))
        if math.floor(G.t * 30) % 3 == 0 then
            burst(e.x, e.y, { c0 = vec4(.6, .8, 1.6, .7), c1 = vec4(.2, .3, .8, 0), count = 3, smin = .1, smax = .25, lmin = .3, lmax = .7, spread = 2, drag = 2, z = 0.8, radius = 0.6 })
        end
    else m.ghost_orb:set_position(HIDE) end
    if e.kind == "fygar" then
        m.wing:set_rotation(vec3(25 * sin(e.anim * 14), 0, 0))
        if e.state == "fire" then
            local len = min(1, e.fire_t * 4) * 5.0
            local fl = 0.85 + 0.15 * sin(G.t * 40)
            local x0 = e.x + e.face * 0.9
            m.flame:set_position(vec3(x0, e.y + 0.1, 0.5)); m.flame:set_rotation(vec3(0, 0, e.face > 0 and 0 or 180)); m.flame:set_scale(vec3(len, 2.5 * fl, 2.0 * fl))
            m.flame_core:set_position(vec3(x0, e.y + 0.1, 0.6)); m.flame_core:set_rotation(vec3(0, 0, e.face > 0 and 0 or 180)); m.flame_core:set_scale(vec3(len * 0.95, 2.4, 2.0))
            burst(x0 + e.face * len * rr(0.2, 1), e.y + 0.1, { c0 = vec4(4, 1.6, .3, 1), c1 = vec4(.8, .1, 0, 0), count = 14, smin = .1, smax = .3, lmin = .2, lmax = .5, spread = 4, drag = 1.5, grav = vec3(0, 3, 0), z = 0.8, radius = 0.4 })
        else m.flame:set_position(HIDE); m.flame_core:set_position(HIDE) end
    end
end

------------------------------------------------------------------ lives icons (mini diggers on the bedrock)
local ICONS = {}
local function build_icons() for i = 1, 5 do ICONS[i] = make_digger() end end
local function draw_icons(n)
    for i, d in ipairs(ICONS) do
        if i <= n and G.state ~= "title" then
            d.root:set_position(vec3(XMIN - 0.6 + (i - 1) * 1.6, YMIN - 2.6, 1.0)); d.root:set_scale(vec3(0.6, 0.6, 0.6))
            d.root:set_rotation(vec3(0, 20 * sin(G.t + i), 0))
        else d.root:set_position(HIDE) end
    end
end

------------------------------------------------------------------ round generation
local function overlaps(list, c, r, pad)
    for _, t in ipairs(list) do if abs(t[1] - c) <= pad and abs(t[2] - r) <= pad then return true end end
    return false
end
local function build_round()
    for i = #enemies, 1, -1 do remove_enemy(enemies[i]) end
    for _, k in ipairs(ROCKS) do kill_rock(k) end
    reset_earth(); place_gems(); harp_off(); VEG.on = false
    G.rocks_dropped, G.veg_given = 0, false
    local used = {}
    for r = 0, 7 do used[#used + 1] = { 6, r } end                -- the start shaft
    local ne = min(4 + floor((G.round - 1) / 2), 8)
    local nf = min(1 + floor(G.round / 2), 3, ne - 2)
    local tries = 0
    local made = 0
    while made < ne and tries < 400 do
        tries = tries + 1
        local horiz = rand() < 0.6
        local c, r = rand(0, horiz and COLS - 3 or COLS - 1), rand(2, horiz and 11 or 9)
        local tiles = {}
        for k = 0, 2 do tiles[#tiles + 1] = horiz and { c + k, r } or { c, r + k } end
        local ok = true
        for _, t in ipairs(tiles) do if overlaps(used, t[1], t[2], 1) then ok = false end end
        if ok then
            for _, t in ipairs(tiles) do dig_tile(t[1], t[2]); used[#used + 1] = t end
            local kind = made < nf and "fygar" or "pooka"
            local m = tiles[2]
            local e = new_enemy(kind, m[1], m[2])
            if e then reset_enemy(e) end
            made = made + 1
        end
    end
    -- rocks
    local nr = 3 + min(floor(G.round / 3), 2)
    local placed = 0; tries = 0
    while placed < nr and tries < 300 do
        tries = tries + 1
        local c, r = rand(0, COLS - 1), rand(2, 9)
        if not overlaps(used, c, r, 1) and not tile_open(c, r + 1) then
            for _, k in ipairs(ROCKS) do if not k.alive then place_rock(k, c, r); break end end
            used[#used + 1] = { c, r }; placed = placed + 1
        end
    end
    -- tilt enemy order so fygars are not all first
    for _, e in ipairs(enemies) do e.face = rand() < 0.5 and 1 or -1 end
end

------------------------------------------------------------------ HUD / menus
local HUD = "hud"
runtime_ui.show(HUD); runtime_ui.set_screen_overlay(HUD, true)
KK.NONE = { 0, 0, 0, 0 }
KK.WHITE, KK.GOLD, KK.SKY, KK.RED, KK.SOFT = { 1, 1, 1, 1 }, { 1, .82, .35, 1 }, { .55, .8, 1, 1 }, { 1, .35, .3, 1 }, { .85, .78, .7, 1 }
local cache = {}
local function upd(id, key, q) if cache[id] == key then return end; cache[id] = key; runtime_ui.set_quad(HUD, id, q) end
local function text(id, label, x, y, w, h, fs, col, align, vis)
    vis = vis ~= false
    local key = label .. "|" .. floor(x) .. "|" .. floor(y) .. "|" .. tostring(vis) .. "|" .. string.format("%.2f|%.2f|%.2f%.2f%.2f", col[4], fs, col[1], col[2], col[3])
    upd(id, key, { x = x, y = y, w = w, h = h, z = 10, style = "text", label = label, fill = KK.NONE, border = KK.NONE,
        text_color = col, font_scale = fs, align_h = align or "center", align_v = "middle", no_input = true, visible = vis })
end
local function panel(id, x, y, w, h, vis, fill, border, z, input, rad)
    vis = vis ~= false
    local key = floor(x) .. "|" .. floor(y) .. "|" .. floor(w) .. "|" .. floor(h) .. "|" .. tostring(vis) .. "|" .. table.concat(fill, ",") .. table.concat(border or KK.NONE, ",")
    upd(id, key, { x = x, y = y, w = w, h = h, z = z or 5, style = "text", label = "", fill = fill, border = border or KK.NONE,
        corner_radius = rad or 14, no_input = not input, visible = vis })
end
local function ui_state(id) local ok, s = pcall(runtime_ui.get_state, HUD, id); if ok then return s end end
local MENU = { items = {}, sel = 1 }
local function set_menu(items) MENU.items, MENU.sel = items, 1 end
local function draw_menu(vis, y0)
    local s = SH / 1080
    for i = 1, 4 do
        local it = MENU.items[i]
        local v = vis and it ~= nil
        local sel = v and MENU.sel == i
        local x, w, h = SW / 2 - 200 * s, 400 * s, 64 * s
        local y = y0 + (i - 1) * 80 * s
        local fill = sel and { 0.95, 0.55, 0.15, 0.6 } or { 0.1, 0.06, 0.04, 0.88 }
        local border = sel and { 1, 0.85, 0.5, 0.95 } or { 0.85, 0.6, 0.35, 0.55 }
        local label = v and it.label or ""
        local tc = sel and KK.WHITE or { 1, .9, .78, 1 }
        local fs = (sel and 1.55 or 1.4) * s
        upd("mi_bg" .. i, label .. floor(x) .. "|" .. floor(y) .. tostring(v) .. tostring(sel) .. fs, { x = x, y = y, w = w, h = h, z = 20, style = "text", label = label,
            fill = fill, border = border, text_color = tc, font_scale = fs, align_h = "center", align_v = "middle", corner_radius = 14, no_input = false, visible = v })
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
local function draw_hud(dt)
    local s = SH / 1080
    local st = G.state
    local title = st == "title"
    local play = not title and st ~= "boot"
    local fxl = project(XMIN - 1, 0, 0)
    local pw = max(150 * s, fxl - 50 * s)
    text("up", "1UP", 30 * s, 60 * s, pw, 50 * s, 1.4 * s, KK.RED, "left", play)
    text("score", tostring(G.score), 30 * s, 105 * s, pw, 80 * s, (2.4 + 0.4 * score_pop) * s, KK.WHITE, "left", play)
    text("hi_t", "HIGH SCORE", 30 * s, 210 * s, pw, 50 * s, 1.15 * s, KK.RED, "left", play or title)
    text("hi", tostring(G.hiscore), 30 * s, 250 * s, pw, 70 * s, 1.9 * s, KK.GOLD, "left", play or title)
    local rx = SW - 30 * s - pw
    text("round_t", "ROUND", rx, 60 * s, pw, 50 * s, 1.3 * s, KK.SKY, "right", play)
    text("round", tostring(G.round or 1), rx, 105 * s, pw, 80 * s, 2.4 * s, KK.WHITE, "right", play)
    text("left_t", "ENEMIES", rx, 210 * s, pw, 50 * s, 1.1 * s, KK.SKY, "right", play)
    text("left", tostring(#enemies), rx, 250 * s, pw, 60 * s, 1.7 * s, { .9, .95, 1, 1 }, "right", play)
    text("ctl_hint", "ARROWS / WASD  DIG\nSPACE / CLICK  PUMP\nESC  PAUSE   M  MUTE", rx, SH - 190 * s, pw, 140 * s, 0.85 * s, { .9, .8, .7, .75 }, "right", play)
    local b = G.banner
    b.t = b.t + dt
    local bvis = b.t < b.dur and play
    local ba = bvis and min(1, b.t * 6, (b.dur - b.t) * 3) or 0
    local bs = 1 + 0.2 * max(0, 1 - b.t * 5)
    panel("banner_bg", SW * 0.5 - 330 * s, SH * 0.43, 660 * s, 150 * s, bvis, { 0.05, 0.03, 0.02, 0.55 * ba }, { 1, .75, .4, 0.6 * ba }, 8)
    text("banner", b.text, 0, SH * 0.43 + 10 * s, SW, 90 * s, 2.6 * s * bs, { 1, .85, .45, ba }, "center", bvis)
    text("banner2", b.sub, 0, SH * 0.43 + 90 * s, SW, 50 * s, 1.3 * s, { .9, .95, 1, ba }, "center", bvis and b.sub ~= "")
    for i = 1, 6 do
        local p = POPS[i]
        if p then
            p.t = p.t + dt
            local sx, sy = project(p.x, p.y + p.t * 1.5, 1)
            local a = clamp(1.6 - p.t, 0, 1)
            text("pop" .. i, p.txt, sx - 110 * s, sy - 25 * s, 220 * s, 50 * s, 1.35 * s, { p.col[1], p.col[2], p.col[3], a }, "center", a > 0)
        else text("pop" .. i, "", 0, 0, 10, 10, 1, KK.NONE, "center", false) end
    end
    for i = #POPS, 1, -1 do if POPS[i].t > 1.6 then table.remove(POPS, i) end end
    -- title
    panel("title_bg", SW * 0.5 - 520 * s, SH * 0.07, 1040 * s, 330 * s, title, { 0.04, 0.025, 0.02, 0.62 }, { 1, .7, .35, 0.45 }, 3, false, 26)
    text("title", "Dig Dug Remix", 0, SH * 0.09, SW, 170 * s, 5.4 * s, { 1, .86 + 0.05 * sin(G.t * 2), .5, 1 }, "center", title)
    text("title2", "Dig, pump and drop rocks. Clear every round.", 0, SH * 0.235, SW, 60 * s, 1.35 * s, { .95, .9, .85, 1 }, "center", title)
    text("tt1", "POOKA  200 - 500        FYGAR  400 - 1000        ROCK CRUSH  1000 +", 0, SH * 0.29, SW, 50 * s, 1.0 * s, KK.GOLD, "center", title)
    text("ctl", "ARROWS / WASD  MOVE + DIG      SPACE / CLICK  PUMP (HOLD TO KEEP PUMPING)      ESC  PAUSE      M  MUTE",
        0, SH * 0.94, SW, 50 * s, 0.95 * s, { .95, .9, .85, .9 }, "center", title)
    local pause, over = st == "paused", st == "over"
    panel("dim", 0, 0, SW, SH, pause or over or title, { 0, 0, 0, title and 0.38 or 0.55 }, KK.NONE, 2, false, 0)
    text("pause", "Paused", 0, SH * 0.24, SW, 140 * s, 4.0 * s, KK.SKY, "center", pause)
    text("over", "Game Over", 0, SH * 0.16, SW, 150 * s, 4.4 * s, KK.RED, "center", over)
    text("over2", (G.newhi and "NEW HIGH SCORE  " or "SCORE  ") .. G.score, 0, SH * 0.31, SW, 70 * s, 2.0 * s, KK.GOLD, "center", over)
    text("over3", "ROUND  " .. (G.round or 1), 0, SH * 0.38, SW, 60 * s, 1.4 * s, { .9, .95, 1, 1 }, "center", over)
    draw_menu(title or pause or over, title and SH * 0.62 or SH * 0.5)
end

------------------------------------------------------------------ settings menu (shared module)
local SET = nil
do
    local src = fs.read("Scripts/Lib/settings_menu.lua")
    if src then
        local ok, mod = pcall(function() return load(src, "@settings_menu.lua")() end)
        if ok and mod then
            local ok2, s = pcall(mod.new, { title = "SETTINGS", file = "Save/settings.cfg", click = function() sfx("click") end,
                music = false, defaults = { master = 0.5 }, theme = { accent = { 1, 0.75, 0.35, 1 }, accent2 = { 0.45, 0.8, 1, 1 } } })
            if ok2 then SET = s else pe_log("[DigDug] settings menu init failed: " .. tostring(s)) end
        else pe_log("[DigDug] settings menu load failed: " .. tostring(mod)) end
    end
end

------------------------------------------------------------------ title showcase
local SHOW = {}
local function build_showcase()
    SHOW.dig = make_digger(); SHOW.pooka = make_enemy_model("pooka"); SHOW.fygar = make_enemy_model("fygar")
end
local function draw_showcase(vis)
    local function put(m, x, y, sc, yaw, roll)
        if vis then m.root:set_position(vec3(x, y, 7)); m.root:set_scale(vec3(sc, sc, sc)); m.root:set_rotation(vec3(0, yaw, roll or 0))
        else m.root:set_position(HIDE) end
    end
    local b = abs(sin(G.t * 3)) * 0.3
    put(SHOW.pooka, -7.5, 0.6 + b, 2.6 + 0.15 * sin(G.t * 2), -25 + 20 * sin(G.t), 5 * sin(G.t * 3))
    put(SHOW.dig, 0, 0.4 + abs(sin(G.t * 3 + 1)) * 0.3, 2.7, 0 + 25 * sin(G.t * 0.8), 0)
    put(SHOW.fygar, 7.5, 0.6 + abs(sin(G.t * 3 + 2)) * 0.3, 2.4, 200 + 20 * sin(G.t * 1.1), 0)
    if vis then SHOW.fygar.wing:set_rotation(vec3(25 * sin(G.t * 14), 0, 0)) end
end

------------------------------------------------------------------ autopilot (attract / automation)
local function autopilot()
    G.auto_lock = (G.auto_lock or 0) - 1 / 60
    local best, bd = G.auto_tgt, 1e9
    if best and (not best.alive or best.state == "ghost" or G.auto_lock <= 0) then best = nil end
    if not best then for _, e in ipairs(enemies) do
        if e.alive and e.state ~= "ghost" and e.state ~= "crushed" then
            local d = abs(e.x - P.x) + abs(e.y - P.y)
            if d < bd then best, bd = e, d end
        end
    end; G.auto_tgt = best; G.auto_lock = 6 end
    G.auto_fire = false
    if not best then G.auto_dx, G.auto_dy = 0, 0; return end
    if HARP.target then G.auto_fire = true; G.auto_dx, G.auto_dy = 0, 0; return end
    local dx, dy = best.x - P.x, best.y - P.y
    if abs(dy) < 0.5 and abs(dx) < 5.6 then
        if P.fy == 0 and sgn(dx) == P.fx then G.auto_fire = true; G.auto_dx, G.auto_dy = 0, 0 else G.auto_dx, G.auto_dy = sgn(dx), 0 end
        return
    end
    if abs(dx) < 0.5 and abs(dy) < 5.6 then
        if P.fx == 0 and sgn(dy) == P.fy then G.auto_fire = true; G.auto_dx, G.auto_dy = 0, 0 else G.auto_dx, G.auto_dy = 0, sgn(dy) end
        return
    end
    local onx = abs(P.x - tx(clamp(math.floor((P.x - tx(0)) / 2 + 0.5), 0, COLS - 1))) < 0.02
    local ony = abs(P.y - ty(clamp(math.floor((ty(0) - P.y) / 2 + 0.5), 0, ROWS - 1))) < 0.02
    if not (onx and ony) and ((G.auto_dx or 0) ~= 0 or (G.auto_dy or 0) ~= 0) then return end
    G.auto_dx, G.auto_dy = 0, 0
    if abs(dy) > 0.6 then G.auto_dy = sgn(dy) else G.auto_dx = sgn(dx) end
end

------------------------------------------------------------------ game flow
local function start_round(n)
    G.round = n
    build_round()
    P.x, P.y, P.fx, P.fy, P.face, P.state, P.inv = tx(6), ty(0), 0, -1, 1, "alive", 0
    P.ang, P.yaw = -90, 0
    dig_at(P.x, P.y)
    G.state = "intro"; G.intro_t = 0
    show_banner("Round " .. n, n == 1 and "Player 1" or "", 2.6)
    sfx("start")
end
local function new_game()
    G.score, G.lives, G.newhi = 0, 2, false
    runtime_ui.show(HUD)
    start_round(1)
end
local function to_title()
    G.state = "title"; P.state = "none"
    G.round = 1; build_round(); harp_off()
    set_menu({ { label = "Play", act = "play" }, { label = "Settings", act = "settings" }, { label = "Quit", act = "quit" } })
end
local function game_over()
    G.state = "over"; sfx("gameover")
    G.newhi = G.score > 0 and G.score >= G.hiscore
    pcall(fs.write, KK.HISAVE, tostring(G.hiscore))
    set_menu({ { label = "Play Again", act = "play" }, { label = "Settings", act = "settings" }, { label = "Title", act = "title" } })
end
local function do_menu_action(act)
    sfx("click")
    if act == "play" then new_game()
    elseif act == "resume" then G.state = "play"
    elseif act == "settings" then if SET then G.in_settings = true; SET:open(function() G.in_settings = false end) end
    elseif act == "title" then to_title()
    elseif act == "quit" then pcall(fs.write, KK.HISAVE, tostring(G.hiscore)); pcall(engine.quit) end
end
local function respawn()
    for _, e in ipairs(enemies) do reset_enemy(e) end
    harp_off()
    P.x, P.y, P.fx, P.fy, P.state, P.inv, P.face = tx(6), ty(6), 1, 0, "alive", 2.0, 1
    show_banner("Ready", "", 1.3)
end
local function play_tick(dt, control)
    G.play_t = (G.play_t or 0) + dt
    P.inv = max(0, (P.inv or 0) - dt)
    if control == "auto" then autopilot() end
    local fire_p = control == "auto" and G.auto_fire or (pressed("Space") or pressed("LCtrl") or G.click)
    local fire_h = control == "auto" and G.auto_fire or (kdown("Space") or mouse_down())
    if P.state == "alive" then
        move_player(dt, control)
        update_harpoon(dt, fire_p, fire_h)
    elseif P.state == "dying" then
        P.dt = P.dt + dt
        if P.dt > 1.9 then
            if G.lives > 0 then G.lives = G.lives - 1; respawn() else game_over(); return end
        end
    end
    FIELD.t = FIELD.t - dt
    if FIELD.t <= 0 then
        FIELD.t = 0.2
        FIELD.chase = bfs(clamp(math.floor((P.x - tx(0)) / 2 + 0.5), 0, COLS - 1), clamp(math.floor((ty(0) - P.y) / 2 + 0.5), 0, ROWS - 1))
        FIELD.flee = bfs(0, 0)
    end
    if P.state ~= "dying" then
        for i = #enemies, 1, -1 do local e = enemies[i]; if e and e.alive then update_enemy(e, dt) end end
    end
    for _, k in ipairs(ROCKS) do if k.alive then update_rock(k, dt) end end
    if #enemies == 1 and not enemies[1].flee and P.state == "alive" then
        local e = enemies[1]
        if e.state == "move" then e.flee = true; e.tc = nil; sfx("flee"); popup(e.x, e.y + 1.4, "RUNNING!", { 1, .6, .5 }) end
    end
    if VEG.on then
        VEG.t = VEG.t + dt
        if P.state == "alive" and abs(P.x - VEG.x) < 1.4 and abs(P.y - VEG.y) < 1.4 then
            add_score(VEG.pts); popup(VEG.x, VEG.y + 1.2, tostring(VEG.pts), { .5, 1, .5 }); sfx("bonus")
            burst(VEG.x, VEG.y, { c0 = vec4(3, 3, 1.5, 1), c1 = vec4(.5, 1, .3, 0), count = 60, spread = 18, smin = .05, smax = .15, lmin = .4, lmax = .9, z = 1 })
            flash(VEG.x, VEG.y, { .6, 1, .5 }, 45, 0.4, 8)
            VEG.on = false
        elseif VEG.t > 10 then VEG.on = false end
    end
    if #enemies == 0 and P.state == "alive" then
        G.state = "clear"; G.clear_t = 0; harp_off(); sfx("clear"); show_banner("Round Clear", "", 2.2)
    end
end

------------------------------------------------------------------ visuals tick
local function update_visuals(dt)
    update_flashes(dt); update_shards(dt); update_rings(dt)
    draw_player(dt); draw_harpoon()
    local fi = 1
    for _, e in ipairs(enemies) do
        if e.alive then
            draw_enemy(e, dt)
            if e.kind == "fygar" and (e.state == "fire" or e.state == "charge") and L.fire[fi] then
                local k = e.state == "fire" and 1 or 0.3 * abs(sin(G.t * 30))
                set_point(L.fire[fi], vec3(e.x + e.face * 3, e.y + 0.3, 2.2), vec3(1, 0.45, 0.1), 60 * k, 8); fi = fi + 1
            end
        end
    end
    for i = fi, #L.fire do set_point(L.fire[i], HIDE, vec3(1, .5, .1), 0, 1) end
    draw_veg(dt)
    for _, g in ipairs(GEMS) do
        if g.live and EARTH.dug[g.id] then g.live = false; g.node:set_position(HIDE) end
        if g.live then
            local tw = 0.42 + 0.08 * sin(G.t * 3 + g.ph)
            g.node:set_position(vec3(g.x, g.y, 0.62)); g.node:set_rotation(vec3(0, G.t * 60 + g.ph * 50, g.r)); g.node:set_scale(vec3(tw, tw, tw))
        end
    end
    if WORLD.motes then emitter_at(WORLD.motes, 0, 0, 1.2, 10) end
    draw_icons(G.lives or 0)
    draw_flowers(G.state == "title" and 1 or (G.round or 1))
    draw_showcase(G.state == "title")
    if P.state == "none" then set_point(L.lamp, HIDE, vec3(1, 1, 1), 0, 1); emitter_at(P.dust, 0, -1000, 0, 0) end
    set_point(L.sun, vec3(-14 + sin(G.t * 0.2) * 2, 22, 16), vec3(1.0, 0.8, 0.6), 160, 45)
    shake = max(0, shake - dt * 2.2)
    local sk = shake * shake * SHAKE_SCALE
    local ox = (sin(G.t * 47) + sin(G.t * 31.7) * 0.5) * 0.5 * sk
    local oy = (cos(G.t * 41) + sin(G.t * 23.3) * 0.5) * 0.5 * sk
    local follow = (P.state ~= "none") and 1 or 0
    G.cam_px = damp(G.cam_px or 0, P.x * 0.06 * follow, 2.5, dt)
    G.cam_py = damp(G.cam_py or 0, (P.y - 0) * 0.04 * follow, 2.5, dt)
    cam:set_position(vec3(G.cam_px + ox, CAM.cy - 2.5 + G.cam_py + oy, CAM.z))
    CAM.look = { G.cam_px * 0.6 + ox * 0.3, CAM.cy + G.cam_py + oy * 0.3, 0 }
    cam:look_at(vec3(CAM.look[1], CAM.look[2], CAM.look[3]))
    score_pop = max(0, score_pop - dt * 4)
end

------------------------------------------------------------------ main update
local function update(dt)
    dt = min(dt, 1 / 20)
    G.t = G.t + dt
    local okS, sz = pcall(runtime_ui.get_surface_size)
    if okS and sz and (sz.width or 0) > 0 and (sz.width ~= SW or sz.height ~= SH) then SW, SH = sz.width, sz.height; cache = {}; fit_camera() end
    flush_mats()
    if G.state == "boot" then
        G.boot = (G.boot or 0) + 1
        if G.boot == 3 then
            if SET then pcall(SET.apply, SET) end
            to_title()
            pe_log("[DigDug] ready")
        end
        return
    end
    if SET then
        PSCALE = SET:particle_scale() or 1; SHAKE_SCALE = SET:shake_scale() or 1
        if SET:update(dt) then latch(); mouse_clicked(); update_visuals(dt); draw_hud(dt); return end
    end
    local ok, mp = pcall(input.get_mouse_position)
    G.mouse_moved = ok and mp and G._mx and (abs(mp.x - G._mx) + abs(mp.y - G._my) > 1) or false
    if ok and mp then G._mx, G._my = mp.x, mp.y end
    G.click = mouse_clicked()
    if pressed("M") then if SET then SET:toggle_mute() end end
    local control = G.autoplay and "auto" or "player"
    local st = G.state
    if st == "title" then
        local act = menu_input(); if act then do_menu_action(act) end
    elseif st == "intro" then
        G.intro_t = G.intro_t + dt
        local target = ty(6)
        if P.y > target then
            P.y = max(target, P.y - 5.5 * dt); P.moving = true; P.walk = P.walk + dt * 10; P.digging = dig_at(P.x, P.y) > 0
        else P.moving = false; P.fx, P.fy, P.face = 1, 0, 1 end
        if G.intro_t > 2.6 and P.y <= target then G.state = "play"; G.play_t = 0 end
    elseif st == "play" then
        if pressed("Escape") or pressed("P") then
            G.state = "paused"; sfx("click")
            set_menu({ { label = "Resume", act = "resume" }, { label = "Settings", act = "settings" }, { label = "Quit to Title", act = "title" } })
        else play_tick(dt, control) end
    elseif st == "paused" then
        if pressed("Escape") or pressed("P") then G.state = "play"
        else local act = menu_input(); if act then do_menu_action(act) end end
    elseif st == "clear" then
        G.clear_t = G.clear_t + dt
        for _, k in ipairs(ROCKS) do if k.alive and k.state ~= "idle" then update_rock(k, dt) end end
        if G.clear_t > 2.6 then start_round(G.round + 1) end
    elseif st == "over" then
        local act = menu_input(); if act then do_menu_action(act) end
    end
    update_visuals(dt)
    draw_hud(dt)
    latch()
end

local function init()
    build_lights(); build_backdrop(); build_earth(); build_rocks(); build_debris(); build_rings()
    build_gems(); build_enemy_pools(); build_player();
    WORLD.motes = new_emitter({ c0 = vec4(1.4, 1.1, .7, .6), c1 = vec4(.6, .4, .2, 0), count = 300, radius = 13, smin = .03, smax = .07,
        lmin = 2.5, lmax = 5, noise = 0.6, drag = 0.5, vel = vec3(0, 0.25, 0) }) build_veg(); build_flowers(); build_icons(); build_showcase()
    paint_templates()
    pcall(audio.set_master_volume, 0.5)
    G.state = "boot"
end
init()
hooks { update = update }

-- automation helpers (MCP): DD.sim(seconds, keys) steps the game at 60 Hz
function G.sim(sec, keys)
    G.vkeys = keys or {}
    for _ = 1, floor(sec * 60) do update(1 / 60) end
    G.vkeys = {}
end
G.new_game, G.start_round, G.to_title, G.P, G.enemies, G.ROCKS, G.HARP = new_game, start_round, to_title, P, enemies, ROCKS, HARP
G.spawn_veg, G.pump_enemy, G.dig_tile = spawn_veg, function(e) pump_enemy(e) end, dig_tile
