-- ROBOTRON REMIX  (PhasmaEngine, Lua)
-- A modernized remake of Williams' Robotron: 2084 (1982), a twin-stick arena shooter.
-- Faithful core: one hero in a walled arena, waves of Grunts that home in and speed up, indestructible Hulks that
-- wander and crush humans (shots only push them back), deadly Electrodes, Spheroids that spawn shooting Enforcers,
-- Brains (from wave 5) that hunt the family. Rescue the last human family (Mommy, Daddy, Mikey) for 1000, 2000 ...
-- up to 5000 points per wave. Extra life every 25,000.
-- Modern visuals: cooked 3D robots and humans, an emissive circuit-panel floor, glowing arena rails, warp-in
-- materialisation, layered explosion particles with bouncing debris and shockwaves, dynamic lights, HDR bloom + TAA.
local PI, TAU = math.pi, math.pi * 2
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local G = { state = "boot", t = 0 }
local KK = {}   -- constant tables (keeps the main chunk under LuaJIT's 200-local limit)
_G.RR = G

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
    mset(n, "base_color", vec4(base[1], base[2], base[3], base[4] or 1))
    mset(n, "emissive", vec3(emis[1], emis[2], emis[3]))
    mset(n, "roughness", rough or 0.3)
    mset(n, "metallic", metal or 0.0)
end
local function sfx(name) pcall(audio.play, name .. ".wav") end


------------------------------------------------------------------ render setup (see /workspace/games/common/RENDER_SETTINGS.md)
local function S(k, v) pcall(settings.set, k, v) end
local ss = scene.add_empty_node("RobotronSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "space.hdr")
S("hdr", true); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.25)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("dof", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", true); S("IBL_intensity", 0.5)
S("color_grading", true); S("color_grading_saturation", 1.12); S("color_grading_contrast", 1.06)

------------------------------------------------------------------ arena + camera
local AX, AY = 22.0, 12.5            -- half extents of the arena floor (inside the rails)
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1280, surf.height or 720
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local FOVX = 0.85
local CAM = { z = 40, tilt = 0.2, tx = 0, ty = 0 }   -- tilt: camera sits behind (-Y) by z*tilt
local function fit_camera()
    local aspect = SW / max(1, SH)
    local tv = math.tan(FOVX * 0.5) / aspect
    local need_h = (AY + 3.2) / tv
    local need_w = (AX + 1.5) / math.tan(FOVX * 0.5)
    CAM.z = max(need_h, need_w) * 0.98
end
pcall(function() cam:set_fov(math.deg(FOVX)) end)
fit_camera()
local function cam_pos() return CAM.tx, CAM.ty - CAM.z * CAM.tilt, CAM.z end
cam:set_position(vec3(cam_pos())); cam:look_at(vec3(0, 0, 0))

------------------------------------------------------------------ templates -> clones
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[Robotron] missing template " .. name); return nil end
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

------------------------------------------------------------------ palette (per template materials): {base, emissive, roughness, metallic}
local PAL = {
    hero = { body = { { .9, .92, .96 }, { .04, .05, .07 }, .25, .35 }, metal = { { .3, .34, .42 }, { 0, 0, 0 }, .25, .9 },
        glow = { { .3, .9, 1 }, { 1.2, 4.0, 6.0 }, .1, 0 } },
    grunt = { body = { { .85, .1, .1 }, { .35, .02, .02 }, .35, .5 }, accent = { { 1, .78, .1 }, { .7, .45, 0 }, .3, .7 },
        eye = { { 1, .9, .3 }, { 6.0, 4.2, .6 }, .1, 0 } },
    hulk = { body = { { .12, .55, .16 }, { .02, .12, .03 }, .45, .3 }, accent = { { .5, .55, .5 }, { .03, .05, .03 }, .3, .9 },
        eye = { { 1, .2, .1 }, { 7.0, .8, .3 }, .1, 0 } },
    spheroid = { core = { { .9, .25, .2 }, { 2.4, .5, .3 }, .2, .4 }, ring = { { 1, .8, .4 }, { 3.0, 2.0, .6 }, .2, .8 } },
    enforcer = { body = { { .4, .4, .5 }, { .05, .05, .08 }, .25, .9 }, fins = { { .2, .7, 1 }, { .5, 1.8, 3.0 }, .2, .5 },
        eye = { { 1, .3, 1 }, { 4.0, .8, 4.0 }, .1, 0 } },
    electrode = { star = { { .8, .2, 1 }, { 1.8, .4, 2.6 }, .25, .5 }, core = { { 1, 1, 1 }, { 4, 3.5, 5 }, .1, 0 } },
    brain = { body = { { .3, .2, .5 }, { .05, .03, .1 }, .3, .5 }, lobes = { { 1, .45, .6 }, { 1.1, .3, .45 }, .45, .1 },
        eye = { { .3, 1, .4 }, { .8, 5, 1.2 }, .1, 0 } },
    mom = { body = { { .95, .3, .55 }, { .9, .15, .45 }, .5, .1 }, skin = { { 1, .78, .62 }, { .45, .3, .22 }, .55, 0 }, hair = { { 1, .8, .3 }, { .25, .18, .04 }, .5, 0 } },
    dad = { body = { { .2, .4, .9 }, { .15, .3, 1.0 }, .5, .1 }, skin = { { .95, .72, .55 }, { .45, .3, .22 }, .55, 0 }, hair = { { .35, .2, .1 }, { .03, .02, .01 }, .5, 0 } },
    kid = { body = { { .3, .85, .3 }, { .2, .9, .2 }, .5, .1 }, skin = { { 1, .8, .64 }, { .45, .3, .22 }, .55, 0 }, hair = { { .9, .4, .1 }, { .2, .07, .01 }, .5, 0 } },
}
KK.PARTS = { hero = { "body", "metal", "glow" }, grunt = { "body", "accent", "eye" }, hulk = { "body", "accent", "eye" },
    spheroid = { "core", "ring" }, enforcer = { "body", "fins", "eye" }, electrode = { "star", "core" }, brain = { "body", "lobes", "eye" },
    mom = { "body", "skin", "hair" }, dad = { "body", "skin", "hair" }, kid = { "body", "skin", "hair" } }
local function paint_templates()
    for kind, parts in pairs(PAL) do
        for part, p in pairs(parts) do
            local n = tnode("T_" .. kind .. "_" .. part)
            if n then paint(n, p[1], p[2], p[3], p[4]) end
        end
    end
end

------------------------------------------------------------------ actors (root node + parented cooked parts)
local function make_actor(kind)
    seq = seq + 1
    local root = scene.add_empty_node("act_" .. kind .. seq)
    root:set_position(HIDE)
    local a = { root = root, kind = kind, nodes = {}, vis = false }
    for _, p in ipairs(KK.PARTS[kind]) do
        local n = clone("T_" .. kind .. "_" .. p, vec3(0, 0, 0), nil, root); a.nodes[p] = n
    end
    return a
end
local function actor_hide(a) if a.vis then a.vis = false; a.root:set_position(HIDE) end end
-- heading: degrees around Z, 0 = facing +Y. roll/pitch add walk sway. s: uniform scale, sz: vertical squash
local function place(a, x, y, z, heading, roll, s, sz)
    a.vis = true
    s = s or 1
    a.root:set_position(vec3(x, y, z or 0))
    a.root:set_rotation(vec3(0, roll or 0, heading or 0))
    a.root:set_scale(vec3(s, s, s * (sz or 1)))
end
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
    lights.set_directional_light(0, vec3(0.3, 0.45, -0.85), vec3(0.9, 0.92, 1.0), 4.5)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    L.fill_l = addp(vec3(-AX, 0, 12), vec3(0.3, 0.6, 1.0), 120, 40)
    L.fill_r = addp(vec3(AX, 0, 12), vec3(1.0, 0.35, 0.8), 120, 40)
    L.player = addp(HIDE, vec3(0.4, 0.8, 1.0), 0, 1)
    L.muzzle = addp(HIDE, vec3(0.6, 0.9, 1.0), 0, 1)
    L.flash = {}
    for i = 1, 8 do L.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1, power = 0, rad = 6 } end
end
local flash_next = 1
local function flash(x, y, col, power, life, rad)
    local f = L.flash[flash_next]; flash_next = flash_next % #L.flash + 1
    f.t, f.life, f.pos, f.col, f.power, f.rad = 0, life or 0.35, vec3(x, y, 3.0), vec3(col[1], col[2], col[3]), power or 40, rad or 9
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
local PSCALE = 1.0
local SHAKE_SCALE = 1.0
local function burst(x, y, o)
    pcall(particles.emit_burst, {
        position = vec3(x, y, o.z or 1.0), velocity = o.vel or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = max(1, floor((o.count or 40) * PSCALE)),
        size_min = o.smin or 0.05, size_max = o.smax or 0.16, life_min = o.lmin or 0.25, life_max = o.lmax or 0.7,
        spawn_radius = o.radius or 0.3, noise_strength = o.spread or 14, drag = o.drag or 2.0,
        gravity = o.grav or vec3(0, 0, 0), cleanup_delay = 3.0,
    })
end
local function hot(c, k) return vec4(c[1] * k + 0.8, c[2] * k + 0.8, c[3] * k + 0.8, 1) end
local function sparks(x, y, col, n, spread)
    burst(x, y, { c0 = hot(col, 3), c1 = vec4(col[1], col[2], col[3], 0), count = n or 30, smin = 0.04, smax = 0.1,
        lmin = 0.15, lmax = 0.45, radius = 0.1, spread = spread or 26, drag = 2.5 })
end
local function new_emitter(o)
    local ok, e = pcall(particles.add_emitter, {
        position = HIDE, velocity = o.vel or vec3(0, 0, 0), gravity = vec3(0, 0, 0),
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

------------------------------------------------------------------ debris shards + shockwave rings
KK.SHARD_COL = { [0] = { 1, .8, .1 }, { 1, .15, .2 }, { .2, .45, 1 }, { .2, 1, .4 }, { 1, 1, 1 }, { .7, .3, 1 } }
local SHARDS = {}
local live_shards = {}
local function build_debris()
    for c = 0, 5 do
        local col = KK.SHARD_COL[c]
        paint(tnode("T_shard_" .. c), col, { col[1] * 2.5, col[2] * 2.5, col[3] * 2.5 }, 0.3, 0.3)
        SHARDS[c] = { next = 1 }
        for k = 1, 14 do SHARDS[c][k] = { node = clone("T_shard_" .. c, HIDE, vec3(0.4, 0.4, 0.4)), life = 0 } end
    end
end
local function shatter(slot, x, y, n, power)
    local pool = SHARDS[slot] or SHARDS[4]
    for _ = 1, floor((n or 8) * (0.4 + 0.6 * PSCALE) + 0.5) do
        local s = pool[pool.next]; pool.next = pool.next % #pool + 1
        local a, sp = rr(0, TAU), rr(4, 13) * (power or 1)
        s.x, s.y, s.z = x, y, rr(0.6, 1.6)
        s.vx, s.vy, s.vz = cos(a) * sp, sin(a) * sp, rr(4, 12)
        s.rx, s.ry, s.rz = rr(0, 360), rr(0, 360), rr(0, 360)
        s.wx, s.wy, s.wz = rr(-700, 700), rr(-700, 700), rr(-700, 700)
        s.sz = rr(0.35, 0.75); s.life = rr(0.8, 1.5)
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
            s.vx, s.vy, s.vz = s.vx * d, s.vy * d, s.vz * d - 30 * dt
            s.x, s.y, s.z = s.x + s.vx * dt, s.y + s.vy * dt, s.z + s.vz * dt
            if s.z < 0.08 then s.z = 0.08; s.vz = abs(s.vz) * 0.45; s.vx, s.vy = s.vx * 0.7, s.vy * 0.7; s.wx, s.wy = s.wx * 0.6, s.wy * 0.6 end
            if abs(s.x) > AX then s.vx = -s.vx; s.x = clamp(s.x, -AX, AX) end
            if abs(s.y) > AY then s.vy = -s.vy; s.y = clamp(s.y, -AY, AY) end
            s.rx, s.ry, s.rz = s.rx + s.wx * dt, s.ry + s.wy * dt, s.rz + s.wz * dt
            local k = clamp(s.life / 0.35, 0, 1) * s.sz
            s.node:set_position(vec3(s.x, s.y, s.z)); s.node:set_rotation(vec3(s.rx, s.ry, s.rz)); s.node:set_scale(vec3(k, k, k))
        end
    end
end
local RINGS = {}
local ring_next = 1
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
            local e = 1 - (1 - k) ^ 3
            local s = 0.3 + r.size * e
            r.node:set_position(vec3(r.x, r.y, 0.15)); r.node:set_scale(vec3(s, s, 1 + 3 * (1 - k)))
            local f = (1 - k) ^ 2 * 5
            mlive(r.mat, "emissive", vec3(r.col[1] * f, r.col[2] * f, r.col[3] * f))
            if r.t >= r.life then r.node:set_position(HIDE) end
        end
    end
end

-- full layered explosion: white core flash, coloured fireball, fast sparks, slow embers, debris, ring, light
local shake = 0
local function add_shake(a) shake = min(1.2, shake + a) end
local function explode(x, y, col, slot, big)
    local k = big and 1.6 or 1.0
    burst(x, y, { c0 = vec4(4, 4, 4, 1), c1 = vec4(col[1] * 2, col[2] * 2, col[3] * 2, 0), count = 26 * k, smin = 0.25, smax = 0.55 * k,
        lmin = 0.08, lmax = 0.22, radius = 0.25, spread = 6, drag = 4 })
    burst(x, y, { c0 = hot(col, 2.5), c1 = vec4(col[1] * 0.6, col[2] * 0.3, col[3] * 0.3, 0), count = 60 * k, smin = 0.1, smax = 0.3,
        lmin = 0.25, lmax = 0.6, radius = 0.5, spread = 18 * k, drag = 3.5 })
    burst(x, y, { c0 = vec4(3.5, 3.0, 2.2, 1), c1 = vec4(col[1] * 2, col[2] * 2, col[3] * 2, 0), count = 70 * k, smin = 0.03, smax = 0.08,
        lmin = 0.3, lmax = 0.8, radius = 0.15, spread = 40 * k, drag = 1.6 })
    burst(x, y, { c0 = vec4(1.8, 0.7, 0.25, 1), c1 = vec4(0.4, 0.05, 0.1, 0), count = 34 * k, smin = 0.05, smax = 0.12,
        lmin = 0.7, lmax = 1.4, radius = 0.6, spread = 9, drag = 1.0, vel = vec3(0, 0, 2.0) })
    shatter(slot or 4, x, y, big and 12 or 7, big and 1.3 or 1)
    shockwave(x, y, col, big and 5.5 or 3.2, big and 0.6 or 0.4)
    flash(x, y, col, big and 120 or 60, big and 0.5 or 0.3, big and 16 or 10)
    add_shake(big and 0.45 or 0.12)
end


------------------------------------------------------------------ arena: circuit-panel floor, glowing rails that colour-cycle
local ARENA = { tiles = {}, rails = {} }
KK.TW, KK.TNX, KK.TNY = 4.0, 11, 6
local function build_arena()
    local tw, th = 2 * AX / KK.TNX, 2 * AY / KK.TNY
    for i = 0, KK.TNX - 1 do
        for j = 0, KK.TNY - 1 do
            local nm = ((i + j) % 2 == 0) and "T_floor" or "T_floor2"
            local n = clone(nm, vec3(-AX + (i + 0.5) * tw, -AY + (j + 0.5) * th, 0), vec3(tw, th, 1))
            ARENA.tiles[#ARENA.tiles + 1] = n
        end
    end
    for _, nm in ipairs({ "T_floor", "T_floor2" }) do
        local t = tnode(nm)
        paint(t, { 1, 1, 1 }, { 0.6, 0.6, 0.6 }, 0.35, 0.6)
        mtex(t, "base_color", "Textures/floor.png"); mtex(t, "emissive", "Textures/floor_glow.png")
    end
    local W = 0.5
    local R = { { 0, AY + W / 2, 2 * AX + 2 * W, W }, { 0, -AY - W / 2, 2 * AX + 2 * W, W }, { AX + W / 2, 0, W, 2 * AY }, { -AX - W / 2, 0, W, 2 * AY } }
    for _, r in ipairs(R) do
        ARENA.rails[#ARENA.rails + 1] = clone("T_rail", vec3(r[1], r[2], 0.35), vec3(r[3], r[4], 0.7))
        ARENA.rails[#ARENA.rails + 1] = clone("T_rail2", vec3(r[1], r[2], -0.25), vec3(r[3] + 0.8, r[4] + 0.8, 0.5))
    end
    paint(tnode("T_rail"), { 1, 0.3, 0.3 }, { 3, 0.6, 0.6 }, 0.2, 0.3)
    paint(tnode("T_rail2"), { 0.12, 0.13, 0.17 }, { 0.0, 0.0, 0.0 }, 0.3, 0.9)
end
KK.RAILCOL = { { 1, .25, .2 }, { 1, .7, .1 }, { .3, 1, .3 }, { .2, .7, 1 }, { .7, .3, 1 }, { 1, .3, .7 } }
local function update_arena(dt)
    local k = (G.t * 0.25) % #KK.RAILCOL
    local i = floor(k); local f = k - i
    local a, b = KK.RAILCOL[i + 1], KK.RAILCOL[(i + 1) % #KK.RAILCOL + 1]
    local c = { lerp(a[1], b[1], f), lerp(a[2], b[2], f), lerp(a[3], b[3], f) }
    local p = 2.6 + 0.6 * sin(G.t * 3) + (G.rail_flash or 0) * 6
    G.rail_flash = max(0, (G.rail_flash or 0) - dt * 2)
    mlive(tnode("T_rail"), "emissive", vec3(c[1] * p, c[2] * p, c[3] * p))
    mlive(tnode("T_rail"), "base_color", vec4(c[1], c[2], c[3], 1))
    local g = 1.3 + 0.3 * sin(G.t * 1.3) + (G.floor_flash or 0)
    G.floor_flash = max(0, (G.floor_flash or 0) - dt * 1.5)
    mlive(tnode("T_floor"), "emissive", vec3(g * 0.9, g, g * 1.1))
    local g2 = 1.1 + 0.3 * sin(G.t * 1.3 + 2) + (G.floor_flash or 0)
    mlive(tnode("T_floor2"), "emissive", vec3(g2 * c[1] * 1.2 + 0.1, g2 * c[2] * 0.6 + 0.1, g2 * c[3] * 1.2 + 0.1))
end

------------------------------------------------------------------ camera math: world <-> screen
local function cam_basis()
    local cx, cy, cz = cam_pos()
    local fx, fy, fz = CAM.tx - cx, CAM.ty - cy, -cz
    local fl = sqrt(fx * fx + fy * fy + fz * fz); fx, fy, fz = fx / fl, fy / fl, fz / fl
    -- right = f x up(0,0,1)... the engine camera uses world up = +Y; looking mostly down, use up hint +Y projected
    local rx, ry, rz = fy * 1 - fz * 0, fz * 0 - fx * 1, 0     -- f x (0,0,1)
    local rl = sqrt(rx * rx + ry * ry); rx, ry = rx / rl, ry / rl
    local ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
    return cx, cy, cz, fx, fy, fz, rx, ry, rz, ux, uy, uz
end
local function project(x, y, z)
    local cx, cy, cz, fx, fy, fz, rx, ry, rz, ux, uy, uz = cam_basis()
    local px, py, pz = x - cx, y - cy, (z or 0) - cz
    local d = px * fx + py * fy + pz * fz
    local t = math.tan(FOVX * 0.5)
    local sx = (px * rx + py * ry + pz * rz) / (d * t)
    local sy = (px * ux + py * uy + pz * uz) / (d * t * SH / SW)
    return SW * 0.5 * (1 + sx), SH * 0.5 * (1 - sy)
end
local function screen_to_floor(mx, my, zplane)
    local cx, cy, cz, fx, fy, fz, rx, ry, rz, ux, uy, uz = cam_basis()
    local t = math.tan(FOVX * 0.5)
    local sx = (mx / SW) * 2 - 1; local sy = 1 - (my / SH) * 2
    local a, b = sx * t, sy * t * SH / SW
    local dx, dy, dz = fx + rx * a + ux * b, fy + ry * a + uy * b, fz + rz * a + uz * b
    local k = ((zplane or 1.0) - cz) / dz
    return cx + dx * k, cy + dy * k
end

------------------------------------------------------------------ pools
KK.POOL_N = { grunt = 50, hulk = 10, electrode = 20, spheroid = 4, enforcer = 14, brain = 6, mom = 4, dad = 4, kid = 4 }
local POOLS = {}
local function build_pools()
    for kind, n in pairs(KK.POOL_N) do
        POOLS[kind] = {}
        for i = 1, n do POOLS[kind][i] = { a = make_actor(kind), used = false } end
    end
end
local function acquire(kind)
    for _, p in ipairs(POOLS[kind] or {}) do if not p.used then p.used = true; return p end end
end
local function release(p) if p then p.used = false; actor_hide(p.a) end end

------------------------------------------------------------------ entities
local ENTS = {}
G.ents = ENTS
KK.INFO = {   -- r: collision radius, pts: score, col: explosion colour, shard: debris colour slot, kill: counts for wave clear
    grunt = { r = 0.6, pts = 100, col = { 1, .3, .15 }, shard = 1, kill = true, s = 1.2 },
    hulk = { r = 0.95, pts = 0, col = { .3, 1, .3 }, shard = 3, s = 1.2 },
    electrode = { r = 0.6, pts = 25, col = { .8, .3, 1 }, shard = 5, s = 1.2 },
    spheroid = { r = 0.8, pts = 1000, col = { 1, .5, .2 }, shard = 0, kill = true, s = 1.2 },
    enforcer = { r = 0.6, pts = 150, col = { .3, .7, 1 }, shard = 2, kill = true, s = 1.2 },
    brain = { r = 0.65, pts = 500, col = { 1, .45, .7 }, shard = 4, kill = true, s = 1.2 },
    mom = { r = 0.55, human = true, col = { 1, .5, .7 }, s = 1.2 }, dad = { r = 0.55, human = true, col = { .4, .6, 1 }, s = 1.2 },
    kid = { r = 0.5, human = true, col = { .4, 1, .4 }, s = 0.95 },
}
local P = { x = 0, y = 0, vx = 0, vy = 0, h = 0, ax = 0, ay = 1, state = "none", inv = 0, fire_cd = 0, walk = 0 }
G.P = P
local function spawn_ent(kind, x, y, delay)
    local p = acquire(kind); if not p then return end
    local e = { kind = kind, pool = p, a = p.a, x = x, y = y, vx = 0, vy = 0, h = rr(0, 360), t = rr(0, 10), alive = true,
        spawn = delay or 0, sp_t = 0, info = KK.INFO[kind], timer = rr(0.5, 2.5), walk = rr(0, 6) }
    ENTS[#ENTS + 1] = e
    return e
end
local function remove_ent(e)
    e.alive = false; release(e.pool)
    for i = #ENTS, 1, -1 do if ENTS[i] == e then table.remove(ENTS, i) break end end
end
local function clear_ents() for i = #ENTS, 1, -1 do release(ENTS[i].pool); ENTS[i] = nil end end
local function count_kill() local n = 0; for _, e in ipairs(ENTS) do if e.alive and e.info.kill then n = n + 1 end end; return n end

------------------------------------------------------------------ hero + bolts + enemy shots
local HERO
local JET
local BOLTS, ORBS = {}, {}
local function build_hero()
    HERO = make_actor("hero")
    JET = new_emitter({ c0 = vec4(0.6, 1.6, 3.0, 1), c1 = vec4(0.2, 0.3, 1.0, 0), count = 300, radius = 0.15, smin = 0.05, smax = 0.14,
        lmin = 0.15, lmax = 0.4, noise = 1.5, drag = 3 })
    for i = 1, 14 do BOLTS[i] = { node = clone("T_bolt", HIDE, vec3(0.7, 1.5, 0.7)), used = false } end
    paint(tnode("T_bolt"), { .7, .95, 1 }, { 3.0, 7.0, 10.0 }, .2, 0)
    for i = 1, 20 do ORBS[i] = { node = clone("T_orb", HIDE), used = false } end
    paint(tnode("T_orb"), { 1, .4, 1 }, { 6.0, 1.5, 6.0 }, .2, 0)
end
local POPS = {}
local function popup(x, y, txt, col)
    POPS[#POPS + 1] = { x = x, y = y, txt = txt, col = col or { 1, 1, 1 }, t = 0 }
    if #POPS > 8 then table.remove(POPS, 1) end
end
G.score, G.hiscore = 0, 10000
KK.HISAVE = "Save/hiscore.txt"
do local s = fs.read and fs.read(KK.HISAVE); local v = s and tonumber(s); if v then G.hiscore = v end end
local score_pop = 0
local function show_banner(t, s, d) G.banner = { text = t, sub = s or "", t = 0, dur = d or 2 } end
G.banner = { text = "", sub = "", t = 9, dur = 0 }
local function add_score(n)
    local before = G.score
    G.score = G.score + n; score_pop = 1
    if not (G.jev and G.jev:assisted()) and G.score > G.hiscore then
        G.hiscore = G.score
    end
    if floor(before / 25000) < floor(G.score / 25000) then
        G.lives = min(9, G.lives + 1); sfx("extra"); show_banner("Extra Life", "", 1.6)
    end
end
local function fire_bolt(dx, dy)
    for _, b in ipairs(BOLTS) do
        if not b.used then
            local l = sqrt(dx * dx + dy * dy); dx, dy = dx / l, dy / l
            b.used = true; b.x, b.y = P.x + dx * 0.9 + dy * 0.3, P.y + dy * 0.9 - dx * 0.3; b.vx, b.vy = dx * 44, dy * 44; b.t = 0
            b.h = math.deg(atan2(-dx, dy))
            b.node:set_rotation(vec3(0, 0, b.h))
            burst(b.x, b.y, { c0 = vec4(2, 4, 5, 1), c1 = vec4(.2, .5, 1, 0), count = 6, smin = .04, smax = .09, lmin = .06, lmax = .14,
                radius = .05, spread = 10, drag = 4, vel = vec3(dx * 8, dy * 8, 0) })
            G.muzzle = 1
            sfx("shoot")
            return true
        end
    end
end
local function fire_orb(x, y, tx, ty, speed)
    for _, o in ipairs(ORBS) do
        if not o.used then
            local dx, dy = tx - x, ty - y; local l = max(0.01, sqrt(dx * dx + dy * dy))
            o.used = true; o.x, o.y = x, y; o.vx, o.vy = dx / l * speed, dy / l * speed; o.t = 0
            sfx("eshot"); return true
        end
    end
end
local function clear_shots()
    for _, b in ipairs(BOLTS) do b.used = false; b.node:set_position(HIDE) end
    for _, o in ipairs(ORBS) do o.used = false; o.node:set_position(HIDE) end
end

------------------------------------------------------------------ combat
local function kill_ent(e, dx, dy)
    local inf = e.info
    explode(e.x, e.y, inf.col, inf.shard, e.kind == "spheroid" or e.kind == "brain")
    if inf.pts and inf.pts > 0 then add_score(inf.pts); if inf.pts >= 150 then popup(e.x, e.y, tostring(inf.pts), inf.col) end end
    sfx(e.kind == "spheroid" and "boom" or "hit")
    G.kills = (G.kills or 0) + 1
    remove_ent(e)
end
local function kill_human(e, by)
    burst(e.x, e.y, { c0 = vec4(3, 0.6, 0.6, 1), c1 = vec4(0.5, 0, 0, 0), count = 40, smin = .06, smax = .16, lmin = .3, lmax = .8, spread = 12, drag = 3 })
    shockwave(e.x, e.y, { 1, .2, .2 }, 2.2, 0.4)
    popup(e.x, e.y, "Lost", { 1, .35, .35 })
    sfx("lost")
    G.lost = (G.lost or 0) + 1
    remove_ent(e)
end
local function rescue(e)
    G.rescue_n = min(5, (G.rescue_n or 0) + 1)
    local pts = 1000 * G.rescue_n
    add_score(pts); popup(e.x, e.y, tostring(pts), { 1, .9, .4 })
    burst(e.x, e.y, { c0 = vec4(3, 3, 1.2, 1), c1 = vec4(1, .5, 1, 0), count = 70, smin = .05, smax = .14, lmin = .4, lmax = 1.0,
        radius = .4, spread = 8, drag = 2, vel = vec3(0, 0, 4) })
    shockwave(e.x, e.y, { 1, .9, .4 }, 3.0, 0.5)
    flash(e.x, e.y, { 1, .9, .5 }, 60, 0.4, 8)
    sfx("rescue")
    G.saved = (G.saved or 0) + 1
    remove_ent(e)
end
local function hero_die()
    if P.state ~= "alive" then return end
    P.state = "dead"; P.dead_t = 0
    explode(P.x, P.y, { .4, .8, 1 }, 2, true)
    burst(P.x, P.y, { c0 = vec4(4, 4, 5, 1), c1 = vec4(.2, .4, 1, 0), count = 160, smin = .05, smax = .2, lmin = .5, lmax = 1.6, spread = 30, drag = 1.5 })
    shockwave(P.x, P.y, { .5, .8, 1 }, 9, 0.9)
    flash(P.x, P.y, { .5, .8, 1 }, 200, 0.9, 22)
    add_shake(1.0); G.rail_flash = 1
    sfx("death")
    actor_hide(HERO)
end

------------------------------------------------------------------ enemy behaviour
local function dist2(ax, ay, bx, by) local dx, dy = ax - bx, ay - by; return dx * dx + dy * dy end
local function wall(e, r)
    r = r or 0.6
    if e.x < -AX + r then e.x = -AX + r; e.vx = abs(e.vx) end
    if e.x > AX - r then e.x = AX - r; e.vx = -abs(e.vx) end
    if e.y < -AY + r then e.y = -AY + r; e.vy = abs(e.vy) end
    if e.y > AY - r then e.y = AY - r; e.vy = -abs(e.vy) end
end
local function face(e, vx, vy, dt, k)
    if vx * vx + vy * vy < 1e-4 then return end
    local want = math.deg(atan2(-vx, vy))
    local d = (want - e.h + 540) % 360 - 180
    e.h = e.h + d * min(1, (k or 10) * dt)
end
local function nearest_human(x, y)
    local best, bd = nil, 1e9
    for _, h in ipairs(ENTS) do if h.alive and h.info.human then local d = dist2(x, y, h.x, h.y); if d < bd then best, bd = h, d end end end
    return best, bd
end
KK.UPD = {}
function KK.UPD.grunt(e, dt)
    local spd = (2.0 + G.wave * 0.22 + G.wave_t * 0.06) * (P.state == "alive" and 1 or 0.3)
    spd = min(spd, 9)
    local tx, ty = P.x, P.y
    local dx, dy = tx - e.x, ty - e.y; local l = max(0.01, sqrt(dx * dx + dy * dy))
    local j = sin(e.t * 3 + e.walk) * 0.5
    e.vx = damp(e.vx, (dx / l + j * dy / l * 0.3) * spd, 6, dt); e.vy = damp(e.vy, (dy / l - j * dx / l * 0.3) * spd, 6, dt)
    face(e, dx, dy, dt, 8)
end
function KK.UPD.hulk(e, dt)
    e.timer = e.timer - dt
    if e.timer <= 0 then
        e.timer = rr(1.0, 2.6)
        local h, d = nearest_human(e.x, e.y)
        local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
        local pick = dirs[rand(4)]
        if h and d < 120 and rand() < 0.75 then
            local dx, dy = h.x - e.x, h.y - e.y
            pick = abs(dx) > abs(dy) and { dx > 0 and 1 or -1, 0 } or { 0, dy > 0 and 1 or -1 }
        elseif rand() < 0.35 then
            local dx, dy = P.x - e.x, P.y - e.y
            pick = abs(dx) > abs(dy) and { dx > 0 and 1 or -1, 0 } or { 0, dy > 0 and 1 or -1 }
        end
        e.dir = pick
    end
    local d = e.dir or { 1, 0 }
    local spd = 2.2 + min(2, G.wave * 0.1)
    e.vx = damp(e.vx, d[1] * spd, 4, dt) + (e.push_x or 0); e.vy = damp(e.vy, d[2] * spd, 4, dt) + (e.push_y or 0)
    e.push_x, e.push_y = 0, 0
    face(e, d[1], d[2], dt, 5)
    for _, h in ipairs(ENTS) do
        if h.alive and h.info.human and dist2(e.x, e.y, h.x, h.y) < 1.4 then kill_human(h, e); add_shake(0.1); sfx("thud") end
    end
end
function KK.UPD.electrode(e, dt) e.vx, e.vy = 0, 0; e.h = e.h + dt * 40 end
function KK.UPD.spheroid(e, dt)
    if not e.tx or dist2(e.x, e.y, e.tx, e.ty) < 4 then e.tx, e.ty = rr(-AX + 2, AX - 2), rr(-AY + 2, AY - 2) end
    local dx, dy = e.tx - e.x, e.ty - e.y; local l = max(0.01, sqrt(dx * dx + dy * dy))
    e.vx = damp(e.vx, dx / l * 9, 1.5, dt); e.vy = damp(e.vy, dy / l * 9, 1.5, dt)
    e.h = e.h + dt * 200
    e.timer = e.timer - dt
    if e.timer <= 0 and (e.spawned or 0) < 4 and G.state == "play" then
        e.timer = rr(2.0, 3.5); e.spawned = (e.spawned or 0) + 1
        local n = spawn_ent("enforcer", e.x, e.y, 0)
        if n then n.spawn = 0.35; shockwave(e.x, e.y, { 1, .6, .3 }, 2, 0.35); sfx("spawn") end
    end
end
function KK.UPD.enforcer(e, dt)
    local tx, ty = P.x + rr(-4, 4) * 0, P.y
    local dx, dy = tx - e.x, ty - e.y; local l = max(0.01, sqrt(dx * dx + dy * dy))
    local spd = 6.5
    e.vx = damp(e.vx, dx / l * spd + sin(e.t * 2 + e.walk) * 3, 1.2, dt); e.vy = damp(e.vy, dy / l * spd + cos(e.t * 1.7 + e.walk) * 3, 1.2, dt)
    e.h = e.h + dt * 120
    e.timer = e.timer - dt
    if e.timer <= 0 and P.state == "alive" then
        e.timer = rr(1.4, 2.8) * max(0.5, 1 - G.wave * 0.03)
        local lead = l / 14
        fire_orb(e.x, e.y, P.x + P.vx * lead * 0.6, P.y + P.vy * lead * 0.6, 13 + min(6, G.wave * 0.4))
    end
end
function KK.UPD.brain(e, dt)
    local h = nearest_human(e.x, e.y)
    local tx, ty = P.x, P.y
    if h then tx, ty = h.x, h.y end
    local dx, dy = tx - e.x, ty - e.y; local l = max(0.01, sqrt(dx * dx + dy * dy))
    e.vx = damp(e.vx, dx / l * 3.2, 3, dt); e.vy = damp(e.vy, dy / l * 3.2, 3, dt)
    face(e, dx, dy, dt, 6)
    if h and l < 1.0 then kill_human(h, e) end
    e.timer = e.timer - dt
    if e.timer <= 0 and P.state == "alive" then e.timer = rr(2.5, 4.5); fire_orb(e.x, e.y, P.x, P.y, 10) end
end
local function human_upd(e, dt)
    e.timer = e.timer - dt
    if e.timer <= 0 then e.timer = rr(1.2, 3.0); local a = rr(0, TAU); e.dx, e.dy = cos(a), sin(a) end
    local spd = 1.6
    e.vx = damp(e.vx, (e.dx or 0) * spd, 3, dt); e.vy = damp(e.vy, (e.dy or 0) * spd, 3, dt)
    face(e, e.vx, e.vy, dt, 6)
end
KK.UPD.mom, KK.UPD.dad, KK.UPD.kid = human_upd, human_upd, human_upd

------------------------------------------------------------------ entity tick + draw
KK.SPAWN_LEN = 0.55
local function draw_ent(e)
    local k, s = e.kind, e.info.s
    local spd = sqrt(e.vx * e.vx + e.vy * e.vy)
    local z, roll, sq = 0, 0, 1
    if k == "grunt" then roll = sin(e.walk) * 9; z = abs(sin(e.walk)) * 0.12
    elseif k == "hulk" then roll = sin(e.walk * 0.6) * 6; sq = 1 - abs(sin(e.walk * 0.6)) * 0.06
    elseif k == "electrode" then local p = 1 + 0.12 * sin(e.t * 6 + e.walk); s = s * p
    elseif k == "spheroid" then z = 0.4 + sin(e.t * 3) * 0.3; roll = 25
    elseif k == "enforcer" then z = 0.5 + sin(e.t * 4 + e.walk) * 0.25; roll = clamp(e.vx * 3, -30, 30)
    elseif k == "brain" then roll = sin(e.walk) * 6; sq = 1 + 0.05 * sin(e.t * 8)
    else roll = sin(e.walk) * 10; z = abs(sin(e.walk)) * 0.1 * min(1, spd) end
    if e.spawn > 0 or e.sp_t < KK.SPAWN_LEN then
        local f = clamp(e.sp_t / KK.SPAWN_LEN, 0, 1)
        if e.spawn > 0 then f = 0 end
        local ef = 1 - (1 - f) ^ 3
        place(e.a, e.x, e.y, z + (1 - ef) * 4, e.h + (1 - ef) * 360, 0, s * max(0.02, ef), 1 + (1 - ef) * 3)
        return
    end
    place(e.a, e.x, e.y, z, e.h, roll, s, sq)
end
local function update_ents(dt, active)
    for i = #ENTS, 1, -1 do
        local e = ENTS[i]
        if e and e.alive then
            e.t = e.t + dt
            if e.spawn > 0 then
                e.spawn = e.spawn - dt
                if e.spawn <= 0 then
                    shockwave(e.x, e.y, e.info.col, 1.6, 0.35)
                    burst(e.x, e.y, { c0 = vec4(e.info.col[1] * 3, e.info.col[2] * 3, e.info.col[3] * 3, 1), c1 = vec4(1, 1, 1, 0), count = 14,
                        smin = .04, smax = .1, lmin = .2, lmax = .45, radius = .5, spread = 6, drag = 3, vel = vec3(0, 0, -3), z = 3 })
                end
            elseif e.sp_t < KK.SPAWN_LEN then
                e.sp_t = e.sp_t + dt
            elseif active then
                local f = KK.UPD[e.kind]; if f then f(e, dt) end
                e.x, e.y = e.x + e.vx * dt, e.y + e.vy * dt
                wall(e, e.info.r)
                e.walk = e.walk + dt * (2 + sqrt(e.vx * e.vx + e.vy * e.vy) * 2.2)
                if P.state == "alive" and e.alive then
                    local rr2 = (e.info.r + 0.45) ^ 2
                    if dist2(e.x, e.y, P.x, P.y) < rr2 then
                        if e.info.human then rescue(e) elseif P.inv <= 0 then hero_die() end
                    end
                end
            end
            if e.alive then draw_ent(e) end
        end
    end
end
local function update_bolts(dt)
    for _, b in ipairs(BOLTS) do
        if b.used then
            b.t = b.t + dt
            b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
            local hit = false
            if abs(b.x) > AX or abs(b.y) > AY then
                hit = true
                local x, y = clamp(b.x, -AX, AX), clamp(b.y, -AY, AY)
                burst(x, y, { c0 = vec4(2, 3.5, 5, 1), c1 = vec4(.2, .4, 1, 0), count = 10, smin = .03, smax = .08, lmin = .1, lmax = .3, spread = 14, drag = 3, z = .6 })
            else
                for _, e in ipairs(ENTS) do
                    if e.alive and not e.info.human and e.spawn <= 0 and e.sp_t >= KK.SPAWN_LEN then
                        local r = e.info.r + 0.25
                        if dist2(b.x, b.y, e.x, e.y) < r * r then
                            hit = true
                            if e.kind == "hulk" then
                                local l = sqrt(b.vx * b.vx + b.vy * b.vy)
                                e.x, e.y = e.x + b.vx / l * 0.45, e.y + b.vy / l * 0.45
                                sparks(b.x, b.y, { .4, 1, .4 }, 14, 18); sfx("thud")
                            else
                                kill_ent(e, b.vx, b.vy)
                            end
                            break
                        end
                    end
                end
                if not hit then
                    for _, o in ipairs(ORBS) do
                        if o.used and dist2(b.x, b.y, o.x, o.y) < 0.5 then
                            hit = true; o.used = false; o.node:set_position(HIDE); add_score(25)
                            sparks(o.x, o.y, { 1, .4, 1 }, 18, 16); break
                        end
                    end
                end
            end
            if hit then b.used = false; b.node:set_position(HIDE)
            else b.node:set_position(vec3(b.x, b.y, 1.0)) end
        end
    end
    for _, o in ipairs(ORBS) do
        if o.used then
            o.t = o.t + dt
            o.x, o.y = o.x + o.vx * dt, o.y + o.vy * dt
            local gone = abs(o.x) > AX or abs(o.y) > AY or o.t > 4
            if not gone and P.state == "alive" and P.inv <= 0 and dist2(o.x, o.y, P.x, P.y) < 0.55 then gone = true; hero_die() end
            if gone then o.used = false; o.node:set_position(HIDE); sparks(clamp(o.x, -AX, AX), clamp(o.y, -AY, AY), { 1, .4, 1 }, 8, 10)
            else
                local s = 0.55 + 0.12 * sin(o.t * 30)
                o.node:set_position(vec3(o.x, o.y, 1.0)); o.node:set_scale(vec3(s, s, s))
            end
        end
    end
end

------------------------------------------------------------------ input
local prev = {}
G.vkeys = {}
local function kdown(k) if G.vkeys[k] then return true end local ok, r = pcall(input.is_key_down_raw, k); return ok and r end
local function pressed(k) local d = kdown(k); local p = prev[k]; prev[k] = d; return d and not p end
local WATCH = { "Left", "Right", "A", "D", "Up", "Down", "W", "S", "Space", "Return", "Escape", "P", "M" }
local function latch() for _, k in ipairs(WATCH) do prev[k] = kdown(k) end end
local mouse_prev_down = false
local function mouse_down() local ok, d = pcall(input.is_left_mouse_down); return (ok and d) or G.vkeys.Click end
local function mouse_clicked() local d = mouse_down(); local c = d and not mouse_prev_down; mouse_prev_down = d; return c end

------------------------------------------------------------------ autopilot (attract mode / automation)
local function auto_control()
    local mx, my = 0, 0
    local tgt, td = nil, 1e9
    for _, e in ipairs(ENTS) do
        if e.alive and e.spawn <= 0 then
            local dx, dy = P.x - e.x, P.y - e.y; local d2 = dx * dx + dy * dy
            if e.info.human then
                local d = sqrt(d2); mx, my = mx - dx / d * 1.2, my - dy / d * 1.2
            else
                local danger = (e.kind == "hulk" or e.kind == "electrode") and 5 or 9
                if d2 < danger * danger then local d = max(0.3, sqrt(d2)); mx, my = mx + dx / d * (danger / d), my + dy / d * (danger / d) end
                if e.kind ~= "hulk" then
                    local w = d2 * (e.kind == "electrode" and 3 or 1)
                    if w < td then td, tgt = w, e end
                end
            end
        end
    end
    for _, o in ipairs(ORBS) do
        if o.used then local dx, dy = P.x - o.x, P.y - o.y; local d = max(0.3, sqrt(dx * dx + dy * dy)); if d < 6 then mx, my = mx + dx / d * 4 / d, my + dy / d * 4 / d end end
    end
    mx, my = mx - P.x * 0.03, my - P.y * 0.05
    local l = sqrt(mx * mx + my * my)
    if l > 0.25 then mx, my = mx / l, my / l else mx, my = 0, 0 end
    local fx, fy
    if tgt then fx, fy = tgt.x + tgt.vx * 0.1 - P.x, tgt.y + tgt.vy * 0.1 - P.y end
    return mx, my, fx, fy
end

------------------------------------------------------------------ hero control: WASD move, arrows / mouse aim + fire (twin-stick)
local function update_hero(dt, control)
    P.inv = max(0, P.inv - dt)
    if control ~= "player" then P.face_x = nil end
    if P.state ~= "alive" then return end
    local mx, my, fx, fy = 0, 0, nil, nil
    if control == "auto" then
        mx, my, fx, fy = auto_control()
    elseif control == "player" then
        -- twin-stick with the mouse: WASD / arrows move, the hero always faces the cursor
        -- (mouse ray projected onto the play plane), left click fires (hold = auto-fire)
        mx = ((kdown("D") or kdown("Right")) and 1 or 0) - ((kdown("A") or kdown("Left")) and 1 or 0)
        my = ((kdown("W") or kdown("Up")) and 1 or 0) - ((kdown("S") or kdown("Down")) and 1 or 0)
        if G.mx and not G.aim_lock then
            local wx, wy = screen_to_floor(G.mx, G.my, 1.0)
            local ax, ay = wx - P.x, wy - P.y
            if ax * ax + ay * ay > 0.04 then G.aim_x, G.aim_y = ax, ay end
            G.use_mouse = true
        end
        if G.aim_x then
            P.face_x, P.face_y = G.aim_x, G.aim_y
            if mouse_down() or kdown("Space") then fx, fy = G.aim_x, G.aim_y end
        elseif kdown("Space") then fx, fy = P.ax, P.ay end
        local l = sqrt(mx * mx + my * my); if l > 0 then mx, my = mx / l, my / l end
    end
    local spd = 10.5
    P.vx = damp(P.vx, mx * spd, 14, dt); P.vy = damp(P.vy, my * spd, 14, dt)
    P.x = clamp(P.x + P.vx * dt, -AX + 0.5, AX - 0.5); P.y = clamp(P.y + P.vy * dt, -AY + 0.5, AY - 0.5)
    local moving = mx ~= 0 or my ~= 0
    P.walk = P.walk + dt * (moving and 13 or 0)
    -- facing: aim direction while firing, else movement direction
    local hx, hy = nil, nil
    if fx and (fx * fx + fy * fy) > 0.01 then hx, hy = fx, fy
    elseif control == "player" and P.face_x then hx, hy = P.face_x, P.face_y
    elseif moving then hx, hy = mx, my end
    if hx then
        local want = math.deg(atan2(-hx, hy)); local d = (want - P.h + 540) % 360 - 180
        P.h = P.h + d * min(1, 22 * dt)
        local l = sqrt(hx * hx + hy * hy); P.ax, P.ay = hx / l, hy / l
    end
    P.fire_cd = max(0, P.fire_cd - dt)
    if fx and (fx * fx + fy * fy) > 0.01 and P.fire_cd <= 0 then
        if fire_bolt(fx, fy) then P.fire_cd = 0.085; G.shots = (G.shots or 0) + 1 end
    end
    P.moving = moving
end
local function draw_hero(dt)
    if P.state == "alive" then
        local blink = P.inv > 0 and floor(G.t * 14) % 2 == 0
        if blink then actor_hide(HERO)
        else place(HERO, P.x, P.y, abs(sin(P.walk)) * 0.08, P.h, sin(P.walk) * 7, 1.2, 1.0) end
        set_point(L.player, vec3(P.x, P.y, 3.5), vec3(0.4, 0.8, 1.0), 45, 9)
        local m = G.muzzle or 0; G.muzzle = max(0, m - dt * 12)
        set_point(L.muzzle, vec3(P.x + P.ax * 1.2, P.y + P.ay * 1.2, 1.5), vec3(0.6, 0.9, 1.0), 60 * m, 6)
        emitter_at(JET, P.x - P.ax * 0.4, P.y - P.ay * 0.4, 0.5, P.moving and 90 or 12, vec3(-P.vx * 0.3, -P.vy * 0.3, 1.5))
    else
        actor_hide(HERO)
        set_point(L.player, HIDE, vec3(0, 0, 0), 0, 1); set_point(L.muzzle, HIDE, vec3(0, 0, 0), 0, 1)
        emitter_at(JET, 0, -1000, 0, 0)
    end
end

------------------------------------------------------------------ waves
local function wave_counts(w)
    return { grunt = min(46, 10 + w * 4), electrode = min(18, 4 + w * 2), hulk = w >= 2 and min(9, 1 + w) or 0,
        spheroid = w >= 2 and min(4, floor(w / 2)) or 0, brain = (w % 5 == 0) and 6 or (w > 5 and 2 or 0),
        mom = min(4, 1 + floor(w / 3)), dad = min(4, 1 + floor(w / 3)), kid = min(4, 1 + floor(w / 4)) }
end
local function free_spot(minr)
    for _ = 1, 40 do
        local x, y = rr(-AX + 1.2, AX - 1.2), rr(-AY + 1.2, AY - 1.2)
        if dist2(x, y, P.x, P.y) > minr * minr then return x, y end
    end
    return rr(-AX + 1, AX - 1), AY - 1.5
end
local function start_wave(w)
    clear_ents(); clear_shots()
    G.wave, G.wave_t, G.rescue_n = w, 0, 0
    P.x, P.y, P.vx, P.vy, P.h, P.inv = 0, 0, 0, 0, 0, 1.2
    local c = wave_counts(w)
    local order = { "electrode", "mom", "dad", "kid", "hulk", "spheroid", "brain", "grunt" }
    local d = 0.1
    for _, k in ipairs(order) do
        for _ = 1, c[k] or 0 do
            local x, y = free_spot(k == "grunt" and 8 or (k == "electrode" and 4 or 6))
            spawn_ent(k, x, y, d); d = d + 0.025
        end
    end
    G.state = "intro"; G.intro_t = 0
    show_banner("Wave " .. w, w == 1 and "Save the last human family" or "", 2.0)
    sfx(w == 1 and "start" or "wave")
    G.floor_flash = 0.8
end
local function respawn_hero()
    clear_shots()
    P.x, P.y, P.vx, P.vy, P.inv, P.state = 0, 0, 0, 0, 2.2, "alive"
    for _, e in ipairs(ENTS) do
        if not e.info.human and dist2(e.x, e.y, 0, 0) < 64 then
            local a = atan2(e.y, e.x); e.x, e.y = cos(a) * rr(9, 14), sin(a) * rr(8, 11)
            wall(e, e.info.r); e.sp_t = 0
        end
    end
    show_banner("Ready", "", 1.2)
end

------------------------------------------------------------------ HUD / menus
local HUD = "hud"
runtime_ui.show(HUD); runtime_ui.set_screen_overlay(HUD, true)
KK.NONE = { 0, 0, 0, 0 }
KK.RED, KK.CYAN, KK.WHITE, KK.GOLD, KK.MAG = { 1, .25, .3, 1 }, { .45, .9, 1, 1 }, { 1, 1, 1, 1 }, { 1, .85, .35, 1 }, { 1, .45, .9, 1 }
local cache = {}
local function upd(id, key, q) if cache[id] == key then return end; cache[id] = key; runtime_ui.set_quad(HUD, id, q) end
local function text(id, label, x, y, w, h, fs, col, align, vis)
    vis = vis ~= false
    local key = label .. "|" .. floor(x) .. "|" .. floor(y) .. "|" .. tostring(vis) .. "|" .. string.format("%.2f|%.2f|%.2f%.2f%.2f", col[4], fs, col[1], col[2], col[3])
    upd(id, key, { x = x, y = y, w = w, h = h, z = 10, style = "text", label = label, fill = KK.NONE, border = KK.NONE,
        text_color = col, font_scale = fs, align_h = align or "center", align_v = "middle", no_input = true, visible = vis })
end
local function panel(id, x, y, w, h, vis, fill, border, z, input)
    vis = vis ~= false
    local key = floor(x) .. "|" .. floor(y) .. "|" .. floor(w) .. "|" .. floor(h) .. "|" .. tostring(vis) .. "|" .. table.concat(fill, ",") .. table.concat(border or KK.NONE, ",")
    upd(id, key, { x = x, y = y, w = w, h = h, z = z or 5, style = "text", label = "", fill = fill, border = border or KK.NONE,
        corner_radius = 14, no_input = not input, visible = vis })
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
        local x, w, h = SW / 2 - 210 * s, 420 * s, 62 * s
        local y = y0 + (i - 1) * 76 * s
        panel("mi_bg" .. i, x, y, w, h, v, sel and { 0.15, 0.55, 0.9, 0.42 } or { 0.02, 0.02, 0.08, 0.6 },
            sel and { 0.6, 0.9, 1, 0.95 } or { 0.3, 0.5, 1.0, 0.45 }, 20, true)
        text("mi_tx" .. i, v and it.label or "", x, y, w, h, (sel and 1.6 or 1.4) * s, sel and KK.WHITE or { 0.75, 0.85, 1, 1 }, "center", v)
    end
end
local function menu_input(pressed)
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
    text("score_t", "Score", 40 * s, 18 * s, 400 * s, 40 * s, 1.0 * s, { .6, .8, 1, .9 }, "left", play)
    text("score", tostring(G.score), 40 * s, 50 * s, 500 * s, 60 * s, (2.0 + 0.3 * score_pop) * s, KK.WHITE, "left", play)
    text("hi_t", "High Score", SW / 2 - 200 * s, 18 * s, 400 * s, 40 * s, 1.0 * s, { 1, .8, .4, .9 }, "center", play or title)
    text("hi", tostring(G.hiscore), SW / 2 - 200 * s, 50 * s, 400 * s, 60 * s, 1.7 * s, KK.GOLD, "center", play or title)
    text("wave_t", "Wave", SW - 440 * s, 18 * s, 400 * s, 40 * s, 1.0 * s, { .6, .8, 1, .9 }, "right", play)
    text("wave", tostring(G.wave or 1), SW - 440 * s, 50 * s, 400 * s, 60 * s, 2.0 * s, KK.WHITE, "right", play)
    local lives = G.lives or 0
    text("lives", "Lives  " .. string.rep("| ", min(lives, 9)), 40 * s, SH - 62 * s, 600 * s, 50 * s, 1.2 * s, { .5, .9, 1, 1 }, "left", play)
    local fam = 0; for _, e in ipairs(ENTS) do if e.alive and e.info.human then fam = fam + 1 end end
    text("fam", "Family left  " .. fam .. "     Next rescue  " .. (1000 * min(5, (G.rescue_n or 0) + 1)), SW - 760 * s, SH - 62 * s, 720 * s, 50 * s, 1.1 * s,
        { 1, .85, .5, 1 }, "right", play)
    -- banner
    local b = G.banner
    b.t = b.t + dt
    local bvis = b.t < b.dur and play
    local ba = bvis and min(1, b.t * 6, (b.dur - b.t) * 3) or 0
    local bs = 1 + 0.2 * max(0, 1 - b.t * 5)
    text("banner", b.text, 0, SH * 0.40, SW, 110 * s, 3.0 * s * bs, { 1, 1, 1, ba }, "center", bvis)
    text("banner2", b.sub, 0, SH * 0.40 + 100 * s, SW, 60 * s, 1.5 * s, { .6, .9, 1, ba }, "center", bvis and b.sub ~= "")
    for i = 1, 8 do
        local p = POPS[i]
        if p then
            p.t = p.t + dt
            local sx, sy = project(p.x, p.y, 2.2 + p.t * 1.5)
            local a = clamp(1.4 - p.t, 0, 1)
            text("pop" .. i, p.txt, sx - 100 * s, sy - 25 * s, 200 * s, 50 * s, 1.3 * s, { p.col[1], p.col[2], p.col[3], a }, "center", a > 0)
        else text("pop" .. i, "", 0, 0, 10, 10, 1, KK.NONE, "center", false) end
    end
    for i = #POPS, 1, -1 do if POPS[i].t > 1.4 then table.remove(POPS, i) end end
    -- title
    panel("tback", SW * 0.5 - 520 * s, SH * 0.07, 1040 * s, 330 * s, title, { 0.01, 0.02, 0.06, 0.55 }, { 0.3, 0.6, 1, 0.35 }, 3)
    text("title", "Robotron Remix", 0, SH * 0.09, SW, 160 * s, 5.2 * s, { 0.85, 0.93, 1, 1 }, "center", title)
    text("title2", "A twin-stick arena shooter after Robotron: 2084", 0, SH * 0.22, SW, 60 * s, 1.4 * s, { .6, .8, 1, .95 }, "center", title)
    text("title3", "Save the last human family. Destroy the robots.", 0, SH * 0.28, SW, 50 * s, 1.15 * s, { 1, .85, .55, .95 }, "center", title)
    text("ctl", "W A S D / Arrows  move   ·   Mouse  aim   ·   Left click (hold)  fire   ·   Esc  pause   ·   M  mute",
        0, SH * 0.93, SW, 50 * s, 1.0 * s, { .75, .85, 1, .9 }, "center", title)
    for i, row in ipairs(KK.LEGEND) do
        local sx, sy = project(row.x, row.y - 1.6, 0)
        text("lg" .. i, row.label, sx - 110 * s, sy, 220 * s, 60 * s, 0.9 * s, { .85, .9, 1, .95 }, "center", title)
    end
    -- pause / game over
    local pause = st == "paused"
    local over = st == "over"
    panel("dim", 0, 0, SW, SH, pause or over, { 0, 0, 0.02, 0.55 }, KK.NONE, 2)
    text("pause", "Paused", 0, SH * 0.24, SW, 140 * s, 4.0 * s, KK.CYAN, "center", pause)
    text("over", "Game Over", 0, SH * 0.14, SW, 150 * s, 4.4 * s, KK.RED, "center", over)
    text("over2", (G.newhi and "New high score  " or "Score  ") .. G.score, 0, SH * 0.29, SW, 70 * s, 2.0 * s, KK.GOLD, "center", over)
    text("over3", string.format("Reached wave %d     Humans saved %d     Robots destroyed %d", G.wave or 1, G.saved or 0, G.kills or 0),
        0, SH * 0.38, SW, 60 * s, 1.2 * s, { .7, .9, 1, 1 }, "center", over)
    draw_menu(title or pause or over, title and SH * 0.66 or SH * 0.5)
end

------------------------------------------------------------------ settings menu (shared module)
local SET = nil
do
    local src = fs.read("Scripts/Lib/settings_menu.lua")
    if src then
        local ok, mod = pcall(function() return load(src, "@settings_menu.lua")() end)
        if ok and mod then
            local ok2, s = pcall(mod.new, { title = "Settings", subtitle = "WASD / Arrows  move  ·  Mouse  aim  ·  Left click (hold)  fire", file = "Save/settings.cfg", click = function() sfx("click") end,
                music = false, defaults = { master = 0.5 }, theme = { accent = { 0.4, 0.8, 1, 1 }, accent2 = { 1, 0.75, 0.3, 1 } } })
            if ok2 then SET = s else pe_log("[Robotron] settings menu init failed: " .. tostring(s)) end
        else pe_log("[Robotron] settings menu load failed: " .. tostring(mod)) end
    end
end

------------------------------------------------------------------ title showcase
KK.LEGEND = {
    { kind = "grunt", label = "Grunt  100" }, { kind = "hulk", label = "Hulk  (indestructible)" }, { kind = "electrode", label = "Electrode  25" },
    { kind = "spheroid", label = "Spheroid  1000" }, { kind = "enforcer", label = "Enforcer  150" }, { kind = "brain", label = "Brain  500" },
    { kind = "mom", label = "Mommy" }, { kind = "dad", label = "Daddy" }, { kind = "kid", label = "Mikey" },
}
local SHOW = {}
local function build_showcase()
    for i, row in ipairs(KK.LEGEND) do
        row.x = -16 + (i - 1) * 4; row.y = 1.0
        SHOW[i] = make_actor(row.kind)
    end
end
local function draw_showcase(vis)
    for i, row in ipairs(KK.LEGEND) do
        local a = SHOW[i]
        if vis then
            local s = (KK.INFO[row.kind].s or 1) * 1.9
            local z = (row.kind == "spheroid" or row.kind == "enforcer") and 0.5 + 0.2 * sin(G.t * 3 + i) or 0
            place(a, row.x, row.y, z, 200 + 30 * sin(G.t * 0.9 + i), 6 * sin(G.t * 5 + i), s, 1)
        else actor_hide(a) end
    end
end

------------------------------------------------------------------ game flow
local function new_game()
    G.score, G.lives, G.shots, G.kills, G.saved, G.lost, G.newhi = 0, 3, 0, 0, 0, 0, false
    P.state = "alive"
    runtime_ui.show(HUD)
    start_wave(1)
end
local function to_title()
    clear_ents(); clear_shots()
    G.state = "title"; P.state = "none"; G.wave = 0
    set_menu({
        { label = "Play", act = "play" },
        { label = "Jev", act = "jev" },
        { label = "Settings", act = "settings" },
        { label = "Quit", act = "quit" },
    })
end
local function game_over()
    G.state = "over"; sfx("gameover")
    local assisted = G.jev and G.jev:assisted()
    G.newhi = not assisted and G.score > 0 and G.score >= G.hiscore
    if not assisted then
        pcall(fs.write, KK.HISAVE, tostring(G.hiscore))
    end
    set_menu({ { label = "Play Again", act = "play" }, { label = "Title", act = "title" } })
end
local function do_menu_action(act)
    sfx("click")
    if act == "play" then
        if G.jev then
            G.jev:begin_human()
        end
        new_game()
    elseif act == "resume" then
        G.state = G.paused_from or "play"
    elseif act == "settings" then
        if SET then
            G.in_settings = true
            SET:open(function() G.in_settings = false end)
        end
    elseif act == "title" then
        to_title()
    elseif act == "jev" then
        local ok = G.jev and G.jev:start()
        if not ok then
            local message = (G.jev and G.jev:error()) or "Jev could not start"
            show_banner(message, "", 4)
            pe_log("[Robotron] " .. message)
        end
    elseif act == "quit" then
        if not (G.jev and G.jev:assisted()) then
            pcall(fs.write, KK.HISAVE, tostring(G.hiscore))
        end
        pcall(engine.quit)
    end
end
local function play_tick(dt, control)
    G.wave_t = G.wave_t + dt
    update_hero(dt, control)
    update_ents(dt, true)
    update_bolts(dt)
    if P.state == "dead" then
        P.dead_t = P.dead_t + dt
        if P.dead_t > 2.0 then
            if G.lives > 0 then G.lives = G.lives - 1; respawn_hero() else game_over(); return end
        end
    elseif count_kill() == 0 then
        G.state = "clear"; G.clear_t = 0
        local bonus = 0
        show_banner("Wave " .. G.wave .. " Clear", "Humans saved " .. (G.rescue_n or 0), 1.8)
        G.floor_flash = 1; G.rail_flash = 1; sfx("wave")
    end
end

------------------------------------------------------------------ visuals tick
local function update_visuals(dt)
    update_flashes(dt); update_shards(dt); update_rings(dt); update_arena(dt)
    draw_hero(dt)
    draw_showcase(G.state == "title")
    set_point(L.fill_l, vec3(-AX * 0.7 + sin(G.t * 0.4) * 4, cos(G.t * 0.3) * 6, 10), vec3(0.3, 0.6, 1.0), 55, 30)
    set_point(L.fill_r, vec3(AX * 0.7 + cos(G.t * 0.35) * 4, sin(G.t * 0.45) * 6, 10), vec3(1.0, 0.4, 0.75), 55, 30)
    shake = max(0, shake - dt * 2.2)
    local sk = shake * shake * SHAKE_SCALE
    local ox = (sin(G.t * 47) + sin(G.t * 31.7) * 0.5) * 0.5 * sk
    local oy = (cos(G.t * 41) + sin(G.t * 23.3) * 0.5) * 0.5 * sk
    local follow = (P.state == "alive" and G.state ~= "title")
    CAM.tx = damp(CAM.tx, follow and P.x * 0.06 or 0, 2.5, dt) + ox * 0
    CAM.ty = damp(CAM.ty, follow and P.y * 0.06 or 0, 2.5, dt)
    local cx, cy, cz = cam_pos()
    cam:set_position(vec3(cx + ox, cy + oy, cz))
    cam:look_at(vec3(CAM.tx + ox * 0.3, CAM.ty + oy * 0.3, 0))
    score_pop = max(0, score_pop - dt * 4)
end

------------------------------------------------------------------ main update
local function update(dt)
    dt = min(dt, 1 / 20)
    if G.jev and not G.simming then
        G.jev:tick(dt)
    end
    G.t = G.t + dt
    local okS, sz = pcall(runtime_ui.get_surface_size)
    if okS and sz and (sz.width or 0) > 0 and (sz.width ~= SW or sz.height ~= SH) then SW, SH = sz.width, sz.height; cache = {}; fit_camera() end
    flush_mats()
    if G.state == "boot" then
        G.boot = (G.boot or 0) + 1
        if G.boot == 3 then
            if SET then pcall(SET.apply, SET) end
            to_title()
            pe_log("[Robotron] ready")
        end
        return
    end
    if SET then
        PSCALE = SET:particle_scale() or 1; SHAKE_SCALE = SET:shake_scale() or 1
        if SET:update(dt) then latch(); mouse_clicked(); update_visuals(dt); draw_hud(dt); return end
    end
    local ok, mp = pcall(input.get_mouse_position)
    G.mouse_moved = ok and mp and G.mx and (abs(mp.x - G.mx) + abs(mp.y - G.my) > 1) or false
    if ok and mp and mp.x then G.mx, G.my = mp.x, mp.y end
    G.click = mouse_clicked()
    if pressed("M") then if SET then SET:toggle_mute() end end
    local control = G.autoplay and "auto" or "player"
    local st = G.state
    if st == "title" then
        local act = menu_input(pressed)
        if act then do_menu_action(act) end
    elseif st == "intro" then
        G.intro_t = G.intro_t + dt
        update_ents(dt, false)
        if G.intro_t >= 1.6 then G.state = "play"; P.state = "alive" end
    elseif st == "play" then
        if pressed("Escape") or pressed("P") then
            G.paused_from = "play"; G.state = "paused"; sfx("click")
            set_menu({ { label = "Resume", act = "resume" }, { label = "Settings", act = "settings" }, { label = "Quit to Title", act = "title" } })
        else
            play_tick(dt, control)
        end
    elseif st == "paused" then
        if pressed("Escape") or pressed("P") then G.state = G.paused_from or "play"
        else local act = menu_input(pressed); if act then do_menu_action(act) end end
        update_ents(dt, false)
    elseif st == "clear" then
        G.clear_t = G.clear_t + dt
        update_hero(dt, control); update_ents(dt, true); update_bolts(dt)
        if G.clear_t > 2.0 then start_wave(G.wave + 1) end
    elseif st == "over" then
        local act = menu_input(pressed)
        if act then do_menu_action(act) end
        update_ents(dt, true); update_bolts(dt)
    end
    update_visuals(dt)
    draw_hud(dt)
    latch()
end

local function attach_jev()
    local source = assert(fs.read("Scripts/jev_auto.lua"), "Missing Jev module: Scripts/jev_auto.lua")
    local JevAuto = assert(load(source, "@Scripts/jev_auto.lua", "t", _ENV))()
    local diag = 0.7071067811865476
    local dirs = {
        n = { x = 0, y = 1, keys = { "W" } },
        ne = { x = diag, y = diag, keys = { "W", "D" } },
        e = { x = 1, y = 0, keys = { "D" } },
        se = { x = diag, y = -diag, keys = { "S", "D" } },
        s = { x = 0, y = -1, keys = { "S" } },
        sw = { x = -diag, y = -diag, keys = { "S", "A" } },
        w = { x = -1, y = 0, keys = { "A" } },
        nw = { x = -diag, y = diag, keys = { "W", "A" } },
    }
    local dir_order = { "n", "ne", "e", "se", "s", "sw", "w", "nw" }
    local dir_text = {
        n = "Hold W. Move and aim +Y",
        ne = "Hold W and D. Move and aim +X +Y",
        e = "Hold D. Move and aim +X",
        se = "Hold S and D. Move and aim +X -Y",
        s = "Hold S. Move and aim -Y",
        sw = "Hold S and A. Move and aim -X -Y",
        w = "Hold A. Move and aim -X",
        nw = "Hold W and A. Move and aim -X +Y",
    }
    local raw_keys = { "W", "A", "S", "D", "Up", "Down", "Left", "Right", "Space" }
    local raw_prev = {}

    local function raw_down(key)
        local ok, down = pcall(input.is_key_down_raw, key)
        return ok and down == true
    end

    local function prime_raw()
        for i = 1, #raw_keys do
            local key = raw_keys[i]
            raw_prev[key] = raw_down(key)
        end
    end

    local function human_edge()
        local edge = false
        for i = 1, #raw_keys do
            local key = raw_keys[i]
            local down = raw_down(key)
            if down and not raw_prev[key] then
                edge = true
            end
            raw_prev[key] = down
        end
        return edge
    end

    local function clear_hold()
        G.vkeys = {}
        G.aim_lock = false
    end

    local function nearest_hostile()
        local best = nil
        local best_d = 1e9
        for i = 1, #ENTS do
            local ent = ENTS[i]
            if ent.alive and not ent.info.human then
                local d = dist2(P.x, P.y, ent.x, ent.y)
                if d < best_d then
                    best = ent
                    best_d = d
                end
            end
        end
        return best
    end

    local function apply_action(id)
        if id == "stop" then
            G.vkeys = {}
            return
        end

        if id == "fire_nearest" then
            local ent = nearest_hostile()
            if not ent then
                G.vkeys = {}
                return
            end

            local dx = ent.x - P.x
            local dy = ent.y - P.y
            local len = sqrt(dx * dx + dy * dy)
            if len <= 1e-6 then
                G.vkeys = {}
                return
            end

            G.aim_x = dx / len
            G.aim_y = dy / len
            G.aim_lock = true
            G.vkeys = { Space = true }
            return
        end

        local dir = dirs[id]
        if not dir then
            G.vkeys = {}
            return
        end

        local hold = {}
        for i = 1, #dir.keys do
            hold[dir.keys[i]] = true
        end
        hold.Space = true
        G.vkeys = hold
        local ent = nearest_hostile()
        if ent then
            local ax = ent.x - P.x
            local ay = ent.y - P.y
            local alen = sqrt(ax * ax + ay * ay)
            if alen > 1e-6 then
                G.aim_x = ax / alen
                G.aim_y = ay / alen
            else
                G.aim_x = dir.x
                G.aim_y = dir.y
            end
        else
            G.aim_x = dir.x
            G.aim_y = dir.y
        end
        G.aim_lock = true
    end

    local function best_dir()
        local ent = nearest_hostile()
        local dx, dy = 0, 1
        if ent then
            dx = ent.x - P.x
            dy = ent.y - P.y
            local dist = sqrt(dx * dx + dy * dy)
            if dist < 1.6 then
                dx = -dx
                dy = -dy
            end
        end
        local best_id = "n"
        local best = -1e18
        for i = 1, #dir_order do
            local id = dir_order[i]
            local dir = dirs[id]
            local dot = dir.x * dx + dir.y * dy
            if dot > best then
                best = dot
                best_id = id
            end
        end
        return best_id, best
    end

    local function actions()
        local id, score = best_dir()
        return { { id = id, description = "Move and shoot. Back away when a hostile is on top of you.", score = score + 1 } }
    end

    prime_raw()
    G.jev = JevAuto.attach({
        port = 9128,
        id = "robotron-remix",
        description = "Twin-stick arena shooter. The offered action moves and shoots. It steps away when a hostile is close. Prefer the higher action score.",
        playing = function()
            local st = G.state
            return st == "intro" or st == "play" or st == "clear"
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
            local ent = nearest_hostile()
            return {
                hero_x = P.x,
                hero_y = P.y,
                nearest_x = ent and ent.x or 0,
                nearest_y = ent and ent.y or 0,
                lives = G.lives or 0,
                score = G.score or 0,
            }
        end,
        actions = actions,
        apply = apply_action,
        reset = function(seed)
            math.randomseed(seed)
            clear_hold()
            prime_raw()
            new_game()
        end,
        on_human = clear_hold,
    })
end

attach_jev()

local function init()
    build_lights(); build_arena(); build_debris(); build_rings(); build_pools(); build_hero(); build_showcase()
    paint_templates()
    pcall(audio.set_master_volume, 0.5)
    G.state = "boot"
end
init()
hooks { update = update }

-- automation helpers (MCP): RR.sim(seconds, keys) steps the game deterministically at 60 Hz
function G.sim(sec, keys)
    G.vkeys = keys or {}
    G.simming = true
    for _ = 1, floor(sec * 60) do update(1 / 60) end
    G.simming = false
    G.vkeys = {}
end
G.new_game = new_game
G.start_wave = start_wave
G.to_title = to_title
G.game_over = game_over
G.do_menu_action = do_menu_action
