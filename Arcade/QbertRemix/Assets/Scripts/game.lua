-- Q*BERT REMIX  (PhasmaEngine, Lua)
-- A modernized remake of Gottlieb's Q*bert (1982). Faithful core: a 28-cube pyramid, diagonal hops that change
-- each cube's top colour, round rules that get stricter per level (one hop / two hops / colours toggle back),
-- red balls, the purple ball that hatches into Coily, green ball freezes time, Slick & Sam undo your work,
-- spinning escape discs that lure Coily off the edge, the @!#?@! curse balloon.
-- Modern visuals: cooked bevelled cubes with glowing tiles, glossy 3D characters with squash & stretch,
-- layered particle VFX, dynamic lights, drifting backdrop cubes, TAA + soft bloom.
local PI, TAU = math.pi, math.pi * 2
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local G = { state = "boot", t = 0, score = 0, hiscore = 0, lives = 3, level = 1, round = 1 }
local KK = {}
_G.QB = G

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
local function mlive(n, k, v) if n then pcall(_mset, n, k, v) end end
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
local ss = scene.add_empty_node("QbertSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "dusk.hdr")
S("hdr", true); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false); S("dof", false)
S("bloom", true); S("bloom_strength", 0.5); S("bloom_range", 1.2)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", true); S("IBL_intensity", 0.3)
S("color_grading", true); S("color_grading_saturation", 1.1); S("color_grading_contrast", 1.05)

------------------------------------------------------------------ pyramid geometry
-- cube (r, c): row r = 0..6 from the apex, c = 0..r. Centre = (c, -r, r - c). Camera looks along -(1, 1.2, 1).
local NR = 7
local function valid(r, c) return r >= 0 and r < NR and c >= 0 and c <= r end
local function cpos(r, c) return c, -r + 0.5, r - c end          -- top-surface stand point
KK.DIRS = { UR = { -1, 0, 180 }, UL = { -1, -1, -90 }, DR = { 1, 1, 90 }, DL = { 1, 0, 0 } }   -- dr, dc, yaw

------------------------------------------------------------------ camera
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1280, surf.height or 720
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local FOVX = 0.62
local CAM = { tx = 2.6, ty = -3.15, tz = 2.6, dir = { 1, 1.15, 1 }, dist = 40 }
do local d = CAM.dir; local l = sqrt(d[1] ^ 2 + d[2] ^ 2 + d[3] ^ 2); CAM.dir = { d[1] / l, d[2] / l, d[3] / l } end
local function fit_camera()
    local aspect = SW / max(1, SH)
    local tfy = math.tan(FOVX * 0.5) / aspect
    CAM.dist = max(7.3 / tfy, 7.6 / math.tan(FOVX * 0.5))
end
pcall(function() cam:set_fov(math.deg(FOVX)) end)
fit_camera()
local CP = { x = 0, y = 0, z = 0, lx = 0, ly = 0, lz = 0 }
local function set_cam(ox, oy)
    local d = CAM.dir
    local tx, ty, tz = CAM.tx + (ox or 0), CAM.ty + (oy or 0), CAM.tz - (ox or 0)
    CP.x, CP.y, CP.z = tx + d[1] * CAM.dist, ty + d[2] * CAM.dist, tz + d[3] * CAM.dist
    CP.lx, CP.ly, CP.lz = tx, ty, tz
    cam:set_position(vec3(CP.x, CP.y, CP.z)); cam:look_at(vec3(tx, ty, tz))
end
set_cam()
local function project(x, y, z)
    local fx, fy, fz = CP.lx - CP.x, CP.ly - CP.y, CP.lz - CP.z
    local fl = sqrt(fx * fx + fy * fy + fz * fz); fx, fy, fz = fx / fl, fy / fl, fz / fl
    local rx, ry, rz = -fz, 0, fx
    local rl = sqrt(rx * rx + rz * rz); rx, rz = rx / rl, rz / rl
    local ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
    local px, py, pz = x - CP.x, y - CP.y, z - CP.z
    local d = px * fx + py * fy + pz * fz
    local tf = math.tan(FOVX * 0.5)
    local sx = (px * rx + py * ry + pz * rz) / (d * tf)
    local sy = (px * ux + py * uy + pz * uz) / (d * tf * SH / SW)
    return SW * 0.5 * (1 + sx), SH * 0.5 * (1 - sy)
end

------------------------------------------------------------------ templates -> clones
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[Qbert] missing template " .. name); return nil end
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
local function tnode(name) local t = tpl(name); return t and t.node end
local function root(name) seq = seq + 1; local n = scene.add_empty_node(name .. seq); n:set_position(HIDE); return n end

------------------------------------------------------------------ round themes {start, mid, target, side, rim}
KK.THEMES = {
    { { .22, .34, .78 }, { .95, .45, .2 }, { 1, .82, .18 }, { .1, .14, .3 }, { .3, .5, 1 } },
    { { .62, .2, .55 }, { .2, .75, .9 }, { .35, 1, .55 }, { .2, .08, .22 }, { 1, .35, .8 } },
    { { .18, .55, .5 }, { 1, .55, .75 }, { 1, .95, .9 }, { .06, .2, .2 }, { .3, 1, .85 } },
    { { .78, .5, .15 }, { .35, .45, 1 }, { .2, .9, 1 }, { .26, .14, .05 }, { 1, .7, .3 } },
    { { .45, .45, .52 }, { .9, .3, .35 }, { 1, .45, .1 }, { .14, .14, .18 }, { .8, .8, 1 } },
    { { .28, .2, .7 }, { .9, .85, .3 }, { 1, .35, .7 }, { .1, .07, .25 }, { .6, .4, 1 } },
}
local function theme() return KK.THEMES[((G.level - 1) * 4 + G.round - 1) % #KK.THEMES + 1] end
local function tile_emis(c, k) return { c[1] * k, c[2] * k, c[3] * k } end
local function apply_theme(th)
    th = th or theme()
    paint(tnode("T_cube_body"), th[4], tile_emis(th[4], 0.12), 0.32, 0.15)
    paint(tnode("T_cube_rim"), th[5], tile_emis(th[5], 1.1), 0.3, 0.0)
    paint(tnode("T_top_0"), th[1], tile_emis(th[1], 0.2), 0.55, 0.0)
    paint(tnode("T_top_1"), th[2], tile_emis(th[2], 0.32), 0.5, 0.0)
    paint(tnode("T_top_2"), th[3], tile_emis(th[3], 0.42), 0.5, 0.0)
    G.theme = th
end

------------------------------------------------------------------ lights
KK.LNODE = {}
KK.LIGHT_GAIN = 0.12
local function add_point() lights.add_point(); return #lights.get_point_lights() - 1 end
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
    lights.set_directional_light(0, vec3(-0.45, -0.85, -0.3), vec3(1.0, 0.94, 0.88), 1.25)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    L.fill_l = addp(vec3(-3, 2, 9), vec3(0.3, 0.6, 1.0), 90, 22)
    L.fill_r = addp(vec3(9, 2, -3), vec3(1.0, 0.35, 0.75), 90, 22)
    L.qbert = addp(HIDE, vec3(1.0, 0.6, 0.25), 0, 1)
    L.coily = addp(HIDE, vec3(0.7, 0.3, 1.0), 0, 1)
    L.disc = { addp(HIDE, vec3(1, 1, 1), 0, 1), addp(HIDE, vec3(1, 1, 1), 0, 1) }
    L.flash = {}
    for i = 1, 5 do L.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1, power = 0, rad = 4 } end
end
local flash_next = 1
local function flash(x, y, z, col, power, life, rad)
    local f = L.flash[flash_next]; flash_next = flash_next % #L.flash + 1
    f.t, f.life, f.pos, f.col, f.power, f.rad = 0, life or 0.35, vec3(x, y, z), vec3(col[1], col[2], col[3]), power or 30, rad or 4
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
local function burst(x, y, z, o)
    pcall(particles.emit_burst, {
        position = vec3(x, y, z), velocity = o.vel or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = max(1, floor((o.count or 40) * PSCALE)),
        size_min = o.smin or 0.03, size_max = o.smax or 0.08, life_min = o.lmin or 0.25, life_max = o.lmax or 0.7,
        spawn_radius = o.radius or 0.15, noise_strength = o.spread or 6, drag = o.drag or 2.0,
        gravity = o.grav or vec3(0, 0, 0), cleanup_delay = 3.0,
    })
end
local function hot(c, k, w) w = w or 0.5; return vec4(c[1] * k + w, c[2] * k + w, c[3] * k + w, 1) end
local function fade(c, k) return vec4(c[1] * (k or 1), c[2] * (k or 1), c[3] * (k or 1), 0) end
local function new_emitter(o)
    local ok, e = pcall(particles.add_emitter, {
        position = HIDE, velocity = o.vel or vec3(0, 0, 0), gravity = o.grav or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = o.count or 200, spawn_rate = 0,
        spawn_radius = o.radius or 0.1, size_min = o.smin or 0.03, size_max = o.smax or 0.07,
        life_min = o.lmin or 0.2, life_max = o.lmax or 0.5, noise_strength = o.noise or 0.6, drag = o.drag or 1.5 })
    return ok and e or nil
end
local function emitter_at(e, x, y, z, rate)
    if not e then return end
    pcall(particles.set_emitter, e, "position", vec3(x, y, z))
    pcall(particles.set_emitter, e, "spawn_rate", rate * PSCALE)
end
-- landing puff: soft dust ring + tile-coloured sparkles
local function land_fx(x, y, z, col, strong)
    burst(x, y + 0.03, z, { c0 = vec4(0.9, 0.85, 1.0, 0.7), c1 = vec4(0.4, 0.4, 0.6, 0), count = 16, smin = 0.04, smax = 0.09,
        lmin = 0.25, lmax = 0.5, radius = 0.25, spread = 4, drag = 4, vel = vec3(0, 0.6, 0) })
    if col then
        burst(x, y + 0.08, z, { c0 = hot(col, 2.4), c1 = fade(col, 1.2), count = strong and 40 or 22, smin = 0.025, smax = 0.06,
            lmin = 0.35, lmax = 0.8, radius = 0.35, spread = 7, drag = 2.2, vel = vec3(0, 2.2, 0), grav = vec3(0, -4, 0) })
    end
end

------------------------------------------------------------------ shockwave rings (flat, on cube tops) + debris shards
local RINGS, ring_next = {}, 1
local function build_rings()
    for i = 0, 7 do
        local m = tnode("T_shock_" .. i)
        paint(m, { 0, 0, 0 }, { 0, 0, 0 }, 0.5, 0)
        RINGS[#RINGS + 1] = { node = clone("T_shock_" .. i, HIDE), mat = m, t = 9, life = 1 }
    end
end
local function shockwave(x, y, z, col, size, life)
    local r = RINGS[ring_next]; ring_next = ring_next % #RINGS + 1
    r.x, r.y, r.z, r.col, r.size, r.t, r.life = x, y, z, col, size or 0.6, 0, life or 0.4
end
local function update_rings(dt)
    for _, r in ipairs(RINGS) do
        if r.t < r.life then
            r.t = r.t + dt
            local k = clamp(r.t / r.life, 0, 1)
            local s = 0.15 + r.size * (1 - (1 - k) ^ 3)
            r.node:set_position(vec3(r.x, r.y, r.z)); r.node:set_scale(vec3(s, (1 - k) * 2, s))
            local f = (1 - k) ^ 2 * 3.5
            mlive(r.mat, "emissive", vec3(r.col[1] * f, r.col[2] * f, r.col[3] * f))
            mlive(r.mat, "base_color", vec4(r.col[1] * f * 0.25, r.col[2] * f * 0.25, r.col[3] * f * 0.25, 1))
            if r.t >= r.life then r.node:set_position(HIDE) end
        end
    end
end
KK.SHARD_COL = { [0] = { 1, .25, .2 }, { .7, .3, 1 }, { .3, 1, .45 }, { 1, .6, .2 }, { 1, 1, 1 } }
local SHARDS, live_shards = {}, {}
local function build_debris()
    for c = 0, 4 do
        local col = KK.SHARD_COL[c]
        paint(tnode("T_shard_" .. c), col, { col[1] * 2, col[2] * 2, col[3] * 2 }, 0.3, 0.2)
        SHARDS[c] = { next = 1 }
        for k = 1, 12 do SHARDS[c][k] = { node = clone("T_shard_" .. c, HIDE), life = 0 } end
    end
end
local function shatter(slot, x, y, z, n, power)
    local pool = SHARDS[slot] or SHARDS[4]
    for _ = 1, floor((n or 8) * (0.4 + 0.6 * PSCALE) + 0.5) do
        local s = pool[pool.next]; pool.next = pool.next % #pool + 1
        local a, sp = rr(0, TAU), rr(1.5, 4) * (power or 1)
        s.x, s.y, s.z = x, y + 0.3, z
        s.vx, s.vy, s.vz = cos(a) * sp, rr(2, 5) * (power or 1), sin(a) * sp
        s.rx, s.ry, s.rz = rr(0, 360), rr(0, 360), rr(0, 360)
        s.wx, s.wy, s.wz = rr(-600, 600), rr(-600, 600), rr(-600, 600)
        s.sz = rr(0.7, 1.3); s.life = rr(0.6, 1.1)
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
            s.vy = s.vy - 12 * dt
            s.x, s.y, s.z = s.x + s.vx * dt, s.y + s.vy * dt, s.z + s.vz * dt
            s.rx, s.ry, s.rz = s.rx + s.wx * dt, s.ry + s.wy * dt, s.rz + s.wz * dt
            local k = clamp(s.life / 0.3, 0, 1) * s.sz
            s.node:set_position(vec3(s.x, s.y, s.z)); s.node:set_rotation(vec3(s.rx, s.ry, s.rz)); s.node:set_scale(vec3(k, k, k))
        end
    end
end
local shake = 0
local function add_shake(a) shake = min(1.0, shake + a) end
local function poof(x, y, z, col, slot, big)
    local k = big and 1.6 or 1
    burst(x, y + 0.3, z, { c0 = vec4(3, 3, 3, 1), c1 = fade(col, 1.5), count = 20 * k, smin = 0.08, smax = 0.18 * k, lmin = 0.08, lmax = 0.2, radius = 0.15, spread = 3, drag = 4 })
    burst(x, y + 0.3, z, { c0 = hot(col, 2), c1 = fade(col, 0.5), count = 50 * k, smin = 0.04, smax = 0.1, lmin = 0.3, lmax = 0.7, radius = 0.3, spread = 9 * k, drag = 3 })
    burst(x, y + 0.3, z, { c0 = vec4(2.5, 2.2, 1.8, 1), c1 = fade(col, 1), count = 40 * k, smin = 0.015, smax = 0.04, lmin = 0.4, lmax = 0.9, radius = 0.1, spread = 16 * k, drag = 1.6 })
    shatter(slot or 4, x, y, z, big and 12 or 7, big and 1.3 or 1)
    shockwave(x, y + 0.05, z, col, big and 1.6 or 1.0, 0.45)
    flash(x, y + 0.8, z, col, big and 70 or 40, 0.4, big and 6 or 4)
    add_shake(big and 0.35 or 0.1)
end

------------------------------------------------------------------ pyramid
local CUBES = {}
local function build_pyramid()
    for r = 0, NR - 1 do
        CUBES[r] = {}
        for c = 0, r do
            local x, y, z = c, -r, r - c
            local cb = { r = r, c = c, s = 0, pop = 0, x = x, y = y, z = z }
            cb.root = root("cube")
            cb.root:set_position(vec3(x, y, z))
            cb.body = clone("T_cube_body", vec3(0, 0, 0), nil, cb.root)
            cb.rim = clone("T_cube_rim", vec3(0, 0, 0), nil, cb.root)
            cb.tops = {}
            for k = 0, 2 do cb.tops[k] = clone("T_top_" .. k, vec3(0, 0, 0), nil, cb.root); cb.tops[k]:set_enabled(k == 0) end
            cb.shown = 0
            CUBES[r][c] = cb
        end
    end
end
local function top_index(s)            -- target-in-one-hop rounds jump straight to the target colour
    if G.target == 1 then return s >= 1 and 2 or 0 end
    return s
end
local function show_top(cb, k)
    if cb.shown == k then return end
    cb.tops[cb.shown]:set_enabled(false); cb.tops[k]:set_enabled(true); cb.shown = k
end
local function each_cube(f) for r = 0, NR - 1 do for c = 0, r do f(CUBES[r][c]) end end end
local function cubes_done()
    local n = 0
    each_cube(function(cb) if cb.s == G.target then n = n + 1 end end)
    return n
end
-- pyramid intro: cubes rise in from below in a wave
G.rise = 1
local function update_pyramid(dt)
    each_cube(function(cb)
        cb.pop = max(0, cb.pop - dt * 3.2)
        local p = cb.pop
        local wob = sin((1 - p) * 9) * p
        local rise = 0
        if G.rise < 1 then
            local k = clamp(G.rise * 2.2 - (cb.r + cb.c * 0.3) * 0.12, 0, 1)
            rise = (1 - (1 - (1 - k) ^ 3)) * -9
        end
        local wave = G.wave and (0.12 * sin(G.t * 10 - (cb.r + cb.c) * 0.9)) or 0
        cb.root:set_position(vec3(cb.x, cb.y + rise + wave + 0.06 * wob, cb.z))
        local sxz = 1 + 0.08 * wob
        cb.tops[cb.shown]:set_scale(vec3(sxz, 1 + 1.5 * p, sxz))
        show_top(cb, G.flashing and (floor(G.t * 10 + cb.r + cb.c) % 3) or top_index(cb.s))
    end)
end

------------------------------------------------------------------ backdrop: drifting cubes + twinkling stars
local DECO, STARS = {}, {}
local function build_backdrop()
    local d = CAM.dir
    -- basis perpendicular to the view direction
    local rx, rz = -d[3], d[1]; local rl = sqrt(rx * rx + rz * rz); rx, rz = rx / rl, rz / rl
    local ux, uy, uz = d[2] * rz, d[3] * rx - d[1] * rz, -d[2] * rx
    KK.BB = { rx = rx, rz = rz, ux = ux, uy = uy, uz = uz }
    paint(tnode("T_deco_body"), { .08, .07, .16 }, { .02, .015, .05 }, 0.4, 0.2)
    paint(tnode("T_deco_top"), { .3, .25, .7 }, { .18, .12, .4 }, 0.3, 0.0)
    for i = 1, 26 do
        local back = rr(14, 48)
        local o = { a = rr(-1, 1) * (8 + back * 0.55), b = rr(-1, 1) * (5 + back * 0.33), back = back, s = rr(0.6, 2.2),
            rx = rr(0, 360), ry = rr(0, 360), rz = rr(0, 360), wx = rr(-12, 12), wy = rr(-12, 12), vb = rr(0.15, 0.5), ph = rr(0, TAU) }
        o.root = root("deco")
        clone("T_deco_body", vec3(0, 0, 0), nil, o.root); clone("T_deco_top", vec3(0, 0, 0), nil, o.root)
        o.root:set_scale(vec3(o.s, o.s, o.s))
        DECO[#DECO + 1] = o
    end
    local SC = { { .6, .7, 1, 2 }, { 1, .7, .9, 3 }, { 1, .95, .8, 4.5 } }
    for k = 0, 2 do local c = SC[k + 1]; paint(tnode("T_star_" .. k), { c[1], c[2], c[3] }, { c[1] * c[4], c[2] * c[4], c[3] * c[4] }, 0.5, 0) end
    for i = 1, 140 do
        local back = rr(40, 80)
        local st = { a = rr(-1, 1) * (12 + back * 0.6), b = rr(-1, 1) * (7 + back * 0.36), back = back, k = i % 3, ph = rr(0, TAU), tw = rr(1, 4), sz = rr(0.06, 0.18) }
        st.node = clone("T_star_" .. st.k, HIDE)
        STARS[#STARS + 1] = st
    end
end
local function bb_pos(a, b, back)
    local B, d = KK.BB, CAM.dir
    return CAM.tx + B.rx * a + B.ux * b - d[1] * back, CAM.ty + B.uy * b - d[2] * back, CAM.tz + B.rz * a + B.uz * b - d[3] * back
end
local function update_backdrop(dt)
    for _, o in ipairs(DECO) do
        o.b = o.b + o.vb * dt
        local lim = 5 + o.back * 0.36
        if o.b > lim then o.b = -lim end
        o.rx, o.ry = o.rx + o.wx * dt, o.ry + o.wy * dt
        local x, y, z = bb_pos(o.a + sin(G.t * 0.2 + o.ph) * 0.6, o.b, o.back)
        o.root:set_position(vec3(x, y, z)); o.root:set_rotation(vec3(o.rx, o.ry, o.rz))
    end
    for _, st in ipairs(STARS) do
        local x, y, z = bb_pos(st.a, st.b, st.back)
        local s = st.sz * (0.55 + 0.45 * sin(G.t * st.tw + st.ph)) * (st.back / 40)
        st.node:set_position(vec3(x, y, z)); st.node:set_scale(vec3(s, s, s))
    end
end

------------------------------------------------------------------ actors (root -> pivot -> cooked parts)
KK.PARTS = {
    qbert = { "T_qb_body", "T_qb_eye", "T_qb_dark", "T_qb_feet" },
    red = { "T_ball_red" }, green = { "T_ball_green" }, egg = { "T_egg" },
    coily = { "T_coily_spring", "T_coily_head", "T_coily_eye", "T_coily_dark" },
    slick = { "T_slick_body", "T_shades" }, sam = { "T_sam_body", "T_shades" },
    disc = { "T_disc_ring", "T_disc_core" },
}
local function make_actor(kind)
    local a = { kind = kind, root = root(kind) }
    a.piv = scene.add_empty_node(kind .. "_piv" .. seq); a.piv:set_parent(a.root); a.piv:set_position(vec3(0, 0, 0))
    a.parts = {}
    for _, p in ipairs(KK.PARTS[kind]) do a.parts[#a.parts + 1] = clone(p, vec3(0, 0, 0), nil, a.piv) end
    return a
end
local function paint_actors()
    paint(tnode("T_qb_body"), { 1, .42, .06 }, { .32, .09, 0 }, 0.32, 0.05)
    paint(tnode("T_qb_feet"), { .9, .32, .04 }, { .2, .05, 0 }, 0.4, 0.05)
    paint(tnode("T_qb_eye"), { 1, 1, 1 }, { .5, .5, .5 }, 0.15, 0)
    paint(tnode("T_qb_dark"), { .02, .02, .03 }, { 0, 0, 0 }, 0.1, 0)
    paint(tnode("T_ball_red"), { 1, .08, .1 }, { .7, .03, .05 }, 0.12, 0.1)
    paint(tnode("T_ball_green"), { .2, 1, .35 }, { .2, 1.1, .3 }, 0.12, 0.05)
    paint(tnode("T_egg"), { .62, .22, 1 }, { .32, .08, .6 }, 0.15, 0.1)
    paint(tnode("T_coily_spring"), { .45, .12, .8 }, { .2, .04, .4 }, 0.25, 0.5)
    paint(tnode("T_coily_head"), { .65, .22, 1 }, { .3, .07, .55 }, 0.25, 0.05)
    paint(tnode("T_coily_eye"), { 1, 1, 1 }, { 1.4, 1.2, 1.4 }, 0.15, 0)
    paint(tnode("T_coily_dark"), { .02, .0, .03 }, { 0, 0, 0 }, 0.1, 0)
    paint(tnode("T_slick_body"), { .25, .9, .3 }, { .1, .4, .12 }, 0.3, 0)
    paint(tnode("T_sam_body"), { .2, .8, .75 }, { .08, .35, .33 }, 0.3, 0)
    paint(tnode("T_shades"), { .02, .02, .04 }, { 0, 0, 0 }, 0.05, 0.8)
    paint(tnode("T_disc_ring"), { 1, 1, 1 }, { 2, 2, 2 }, 0.2, 0)
    paint(tnode("T_disc_core"), { .5, .5, .7 }, { .12, .12, .25 }, 0.1, 0.6)
end

------------------------------------------------------------------ hop kinematics
local function hop_begin(o, fx, fy, fz, tx, ty, tz, dur, h)
    o.fx, o.fy, o.fz, o.tx, o.ty, o.tz, o.t, o.dur, o.h = fx, fy, fz, tx, ty, tz, 0, dur, h or 0.55
end
local function hop_pos(o)
    local k = clamp(o.t / o.dur, 0, 1)
    local e = k * k * (3 - 2 * k) * 0.35 + k * 0.65           -- slight ease, keeps the arc snappy
    local arc = o.h * 4 * k * (1 - k)
    return lerp(o.fx, o.tx, e), lerp(o.fy, o.ty, k) + arc, lerp(o.fz, o.tz, e)
end
local function dist3(ax, ay, az, bx, by, bz) local dx, dy, dz = ax - bx, ay - by, az - bz; return sqrt(dx * dx + dy * dy + dz * dz) end
local function ri() return (G.level - 1) * 4 + G.round end                -- 1-based round index

------------------------------------------------------------------ escape discs
local DISCS = {}
local DISC_POOL = {}
local function disc_world(d) local x, y, z = cpos(d.r, d.c); return x, y - 0.35, z end
local function find_disc(r, c) for _, d in ipairs(DISCS) do if not d.used and d.r == r and d.c == c then return d end end end
local function setup_discs()
    for _, a in ipairs(DISC_POOL) do a.root:set_position(HIDE) end
    DISCS = {}
    local n = min(2 + floor((ri() - 1) / 4), 4)
    local rows = { 3, 5, 2, 4 }
    for i = 1, n do
        local left = (i % 2 == 1)
        local r = rows[i] - ((ri() % 2 == 0 and i <= 2) and 1 or 0)
        local d = { r = r, c = left and -1 or r + 1, used = false, a = DISC_POOL[i], ph = rand() * TAU }
        DISCS[#DISCS + 1] = d
    end
end
local function update_discs(dt)
    for i, d in ipairs(DISCS) do
        if not d.used or d.riding then
            local x, y, z
            if d.riding then x, y, z = d.x, d.y, d.z
            else x, y, z = disc_world(d); y = y + 0.08 * sin(G.t * 2.4 + d.ph) end
            d.wx, d.wy, d.wz = x, y, z
            d.a.root:set_position(vec3(x, y, z)); d.a.root:set_rotation(vec3(8 * sin(G.t * 1.7 + d.ph), G.t * 160, 0))
            if rand() < dt * 18 * PSCALE then
                local hue = (G.t * 0.4 + i * 0.3) % 1
                local col = { 0.5 + 0.5 * cos(TAU * hue), 0.5 + 0.5 * cos(TAU * (hue - 0.33)), 0.5 + 0.5 * cos(TAU * (hue - 0.66)) }
                burst(x, y, z, { c0 = hot(col, 2.2, 0.3), c1 = fade(col, 0.8), count = 3, smin = 0.02, smax = 0.05, lmin = 0.4, lmax = 0.9,
                    radius = 0.35, spread = 1.5, drag = 1, vel = vec3(0, d.riding and -2 or -0.4, 0) })
            end
            if L.disc[i] then set_point(L.disc[i], vec3(x, y + 0.4, z), vec3(0.6 + 0.4 * sin(G.t * 3), 0.6 + 0.4 * sin(G.t * 3 + 2), 0.6 + 0.4 * sin(G.t * 3 + 4)), 22, 3.5) end
        else
            d.a.root:set_position(HIDE)
            if L.disc[i] then set_point(L.disc[i], HIDE, vec3(1, 1, 1), 0, 1) end
        end
    end
    for i = #DISCS + 1, #L.disc do set_point(L.disc[i], HIDE, vec3(1, 1, 1), 0, 1) end
    local h = (G.t * 0.25) % 1
    mlive(tnode("T_disc_ring"), "emissive", vec3(0.7 + 0.6 * cos(TAU * h), 0.7 + 0.6 * cos(TAU * (h - 0.33)), 0.7 + 0.6 * cos(TAU * (h - 0.66))))
end

------------------------------------------------------------------ Q*bert
local Q = { r = 0, c = 0, state = "none", yaw = 0, tyaw = 0, squash = 0 }
local function q_world()
    if Q.state == "hop" or Q.state == "fall" then return Q.x, Q.y, Q.z end
    if Q.state == "disc" and Q.ride then return Q.ride.x, Q.ride.y + 0.08, Q.ride.z end
    return cpos(Q.r, Q.c)
end
local POPS = {}
local function popup(x, y, z, txt, col)
    POPS[#POPS + 1] = { x = x, y = y, z = z, txt = txt, col = col or { 1, 1, 1 }, t = 0 }
    if #POPS > 6 then table.remove(POPS, 1) end
end
local score_pop = 0
local function add_score(n)
    if G.state == "title" then return end
    local before = G.score
    G.score = G.score + n; score_pop = 1
    if G.score > G.hiscore then G.hiscore = G.score end
    if before < G.next_extra and G.score >= G.next_extra then
        G.lives = G.lives + 1; G.next_extra = G.next_extra + 14000; sfx("extra")
        local x, y, z = q_world(); popup(x, y + 1.2, z, "1UP", { .4, 1, .5 })
    end
end
local ENT = {}
local function rule()
    local L_ = G.level
    if L_ == 1 then return 1, nil elseif L_ == 2 then return 2, nil elseif L_ == 3 then return 1, 0 else return 2, 1 end
end
local start_clear
local function step_cube(r, c)
    local cb = CUBES[r][c]
    local T, back = rule()
    if cb.s < T then
        cb.s = cb.s + 1; cb.pop = 1; add_score(25)
        local x, y, z = cpos(r, c)
        local col = (cb.s == T) and G.theme[3] or G.theme[2]
        land_fx(x, y, z, col, cb.s == T)
        shockwave(x, y + 0.03, z, col, 0.75, 0.35)
        flash(x, y + 0.7, z, col, 26, 0.3, 3)
        if cubes_done() == NR * (NR + 1) / 2 then start_clear() end
    elseif back then
        cb.s = back; cb.pop = 0.7
        local x, y, z = cpos(r, c); land_fx(x, y, z, G.theme[1], false)
    else
        local x, y, z = cpos(r, c); land_fx(x, y, z, nil, false)
    end
end
local Q_HOP = 0.32
local function q_hop(dir)
    local D = KK.DIRS[dir]
    local nr, nc = Q.r + D[1], Q.c + D[2]
    local fx, fy, fz = cpos(Q.r, Q.c)
    Q.tyaw = D[3]
    Q.state = "hop"; Q.to_r, Q.to_c = nr, nc
    Q.disc = find_disc(nr, nc)
    local tx, ty, tz = cpos(nr, nc)
    if Q.disc then tx, ty, tz = disc_world(Q.disc); ty = ty + 0.08 end
    local up = D[1] < 0
    hop_begin(Q, fx, fy, fz, tx, ty, tz, Q_HOP, up and 0.75 or 0.5)
    Q.x, Q.y, Q.z = fx, fy, fz
    Q.squash = -0.6
    sfx("hop")
end

------------------------------------------------------------------ enemies
local POOL = {}
local function get_actor(kind)
    local p = POOL[kind]
    for _, a in ipairs(p) do if not a.busy then a.busy = true; return a end end
end
local function free_actor(a) a.busy = false; a.root:set_position(HIDE) end
KK.COL = { red = { 1, .15, .15 }, green = { .3, 1, .4 }, egg = { .65, .3, 1 }, coily = { .7, .3, 1 }, slick = { .3, 1, .4 }, sam = { .3, 1, .9 } }
KK.SLOT = { red = 0, egg = 1, coily = 1, green = 2, slick = 2, sam = 2 }
local function count(kind) local n = 0; for _, e in ipairs(ENT) do if e.kind == kind and e.state ~= "dead" then n = n + 1 end end; return n end
local function spawn(kind, r, c)
    local a = get_actor(kind); if not a then return end
    r = r or 1; c = c or (rand() < 0.5 and 0 or 1)
    local e = { kind = kind, a = a, r = r, c = c, state = "drop", yaw = 0, squash = 0 }
    local x, y, z = cpos(r, c)
    hop_begin(e, x, y + 7, z, x, y, z, 0.55, 0)
    e.x, e.y, e.z = x, y + 7, z
    ENT[#ENT + 1] = e
    return e
end
local function kill_ent(e, fx)
    if e.state == "dead" then return end
    e.state = "dead"
    if fx then local x, y, z = e.x, e.y, e.z; poof(x, y, z, KK.COL[e.kind], KK.SLOT[e.kind], e.kind == "coily") ; sfx("pop") end
    free_actor(e.a)
end
local function clear_enemies(fx) for _, e in ipairs(ENT) do kill_ent(e, fx) end; for i = #ENT, 1, -1 do ENT[i] = nil end end
local function rest_time() return max(0.22, 0.62 - ri() * 0.03) end
local function hop_time(kind) return (kind == "coily" and 0.36 or 0.4) * max(0.75, 1 - ri() * 0.015) end
local function choose_dir(e)
    local k = e.kind
    if k == "coily" then
        local gr, gc = Q.r, Q.c
        if e.lure then gr, gc = e.lure.r, e.lure.c end
        local gx, gy, gz = cpos(gr, gc)
        local best, bd = nil, 1e9
        for name, D in pairs(KK.DIRS) do
            local nr, nc = e.r + D[1], e.c + D[2]
            local ok = valid(nr, nc) or (e.lure and nr == e.lure.r and nc == e.lure.c)
            if ok then
                local x, y, z = cpos(nr, nc)
                local d = dist3(x, y, z, gx, gy, gz) + rand() * 0.05
                if d < bd then bd, best = d, name end
            end
        end
        return best
    end
    return rand() < 0.5 and "DL" or "DR"
end
local function ent_hop(e)
    local dir = choose_dir(e); if not dir then e.rest = rest_time(); return end
    local D = KK.DIRS[dir]
    local fx, fy, fz = cpos(e.r, e.c)
    e.r, e.c = e.r + D[1], e.c + D[2]
    local tx, ty, tz = cpos(e.r, e.c)
    e.tyaw = D[3]
    hop_begin(e, fx, fy, fz, tx, ty, tz, hop_time(e.kind), e.kind == "coily" and 0.7 or 0.45)
    e.state = "hop"; e.squash = -0.5
    sfx(e.kind == "coily" and "coily" or "ehop")
end
local function ent_land(e)
    if not valid(e.r, e.c) then
        e.state = "fall"; e.vy = -2; e.vx = (e.tx - e.fx) * 1.2; e.vz = (e.tz - e.fz) * 1.2
        if e.kind == "coily" and e.lure then
            add_score(500); popup(e.x, e.y + 1, e.z, "500", { .8, .5, 1 }); sfx("bonus"); e.bonus = true
        end
        return
    end
    e.state = "rest"; e.rest = rest_time(); e.squash = 0.7
    local x, y, z = cpos(e.r, e.c)
    land_fx(x, y, z, nil, false)
    if e.kind == "slick" or e.kind == "sam" then
        local cb = CUBES[e.r][e.c]
        if cb.s > 0 then cb.s = cb.s - 1; cb.pop = 0.8; burst(x, y + 0.1, z, { c0 = hot(G.theme[1], 2), c1 = fade(G.theme[1]), count = 18, vel = vec3(0, 1.5, 0), spread = 4 }) end
    end
    if e.kind == "egg" and e.r == NR - 1 then e.state = "hatch"; e.rest = 0.9 end
end
local function update_ent(e, dt)
    local frozen = G.freeze > 0 and e.state ~= "fall"
    if frozen then return end
    if e.state == "drop" then
        e.t = e.t + dt
        local k = clamp(e.t / e.dur, 0, 1)
        e.x, e.y, e.z = e.tx, lerp(e.fy, e.ty, k * k), e.tz
        if k >= 1 then ent_land(e) end
    elseif e.state == "rest" then
        e.rest = e.rest - dt
        e.x, e.y, e.z = cpos(e.r, e.c)
        if e.rest <= 0 then ent_hop(e) end
    elseif e.state == "hop" then
        e.t = e.t + dt
        e.x, e.y, e.z = hop_pos(e)
        if e.t >= e.dur then ent_land(e) end
    elseif e.state == "hatch" then
        e.rest = e.rest - dt
        if e.rest <= 0 then
            local r, c = e.r, e.c
            local x, y, z = cpos(r, c)
            kill_ent(e, false); sfx("hatch")
            burst(x, y + 0.3, z, { c0 = hot(KK.COL.coily, 2), c1 = fade(KK.COL.coily), count = 40, spread = 8 })
            shockwave(x, y + 0.05, z, KK.COL.coily, 1.2, 0.4)
            local co = spawn("coily", r, c)
            if co then co.state = "rest"; co.rest = 0.5; co.x, co.y, co.z = x, y, z; co.yaw = 180; co.tyaw = 180 end
        end
    elseif e.state == "fall" then
        e.vy = e.vy - 22 * dt
        e.x, e.y, e.z = e.x + e.vx * dt, e.y + e.vy * dt, e.z + e.vz * dt
        if e.y < -16 then kill_ent(e, false) end
    end
    if e.yaw and e.tyaw then
        local d = ((e.tyaw - e.yaw + 540) % 360) - 180
        e.yaw = e.yaw + d * min(1, dt * 14)
    end
    e.squash = damp(e.squash, 0, 9, dt)
end
local function draw_ent(e)
    if e.state == "dead" then return end
    local a = e.a
    a.root:set_position(vec3(e.x, e.y, e.z))
    a.root:set_rotation(vec3(0, e.yaw or 0, 0))
    local sq = e.squash or 0
    local sy = 1 - 0.35 * sq
    if e.state == "hop" then sy = 1 + 0.18 * sin(clamp(e.t / e.dur, 0, 1) * PI) end
    if e.state == "hatch" then sy = 1 + 0.1 * sin(G.t * 40); a.root:set_rotation(vec3(10 * sin(G.t * 35), 0, 10 * cos(G.t * 31))) end
    local sxz = 1 / sqrt(max(0.4, sy))
    if e.kind == "coily" then
        a.parts[1]:set_scale(vec3(1, sy * (e.state == "hop" and 1.25 or 1), 1)); a.piv:set_scale(vec3(sxz, 1, sxz))
        local hy = (sy * (e.state == "hop" and 1.25 or 1) - 1) * 0.55
        for i = 2, 4 do a.parts[i]:set_position(vec3(0, hy, 0)) end
    else
        a.piv:set_scale(vec3(sxz, sy, sxz))
    end
    if G.freeze > 0 and e.state ~= "fall" then a.piv:set_rotation(vec3(0, 0, 3 * sin(G.t * 30))) else a.piv:set_rotation(vec3(0, 0, 0)) end
end

------------------------------------------------------------------ spawn director
local function director(dt)
    if G.freeze > 0 then return end
    G.spawn_t = G.spawn_t - dt
    G.egg_t = G.egg_t - dt
    if G.egg_t <= 0 and count("egg") + count("coily") == 0 then
        spawn("egg"); G.egg_t = 9; G.spawn_t = max(G.spawn_t, 1.2); return
    end
    if G.spawn_t > 0 then return end
    local n = ri()
    G.spawn_t = max(1.5, 4.0 - n * 0.18) * rr(0.8, 1.25)
    local roll = rand()
    if n >= 3 and roll < 0.16 and count("slick") + count("sam") == 0 then spawn(rand() < 0.5 and "slick" or "sam")
    elseif n >= 2 and roll < 0.28 and count("green") == 0 then spawn("green")
    elseif count("red") < min(1 + floor(n / 3), 3) then spawn("red") end
end

------------------------------------------------------------------ death, disc ride, round flow
local function lose_life(kind)
    if G.state ~= "play" then return end
    G.state = "dying"; G.dead_kind = kind; G.dead_t = 0
    sfx(kind == "fall" and "fall" or "curse")
    if kind == "hit" then
        local x, y, z = q_world()
        poof(x, y, z, { 1, .5, .15 }, 3, false); add_shake(0.5)
        G.balloon = 1.9
    end
end
local function q_drop_in(r, c)
    Q.r, Q.c = r or 0, c or 0
    local x, y, z = cpos(Q.r, Q.c)
    hop_begin(Q, x, y + 6, z, x, y, z, 0.5, 0)
    Q.x, Q.y, Q.z = x, y + 6, z
    Q.state = "drop"; Q.yaw, Q.tyaw = 0, 0
end
local function q_land()
    if Q.disc then
        local d = Q.disc
        d.used = true; d.riding = true
        Q.state = "disc"; Q.ride = { d = d, t = 0, x0 = d.wx or Q.tx, y0 = d.wy or Q.ty, z0 = d.wz or Q.tz, x = Q.tx, y = Q.ty - 0.08, z = Q.tz }
        d.x, d.y, d.z = Q.ride.x, Q.ride.y, Q.ride.z
        sfx("disc")
        -- lure Coily if it is close, everything else vanishes
        for _, e in ipairs(ENT) do
            if e.kind == "coily" and e.state ~= "fall" and e.state ~= "dead" and dist3(e.x, e.y, e.z, Q.tx, Q.ty, Q.tz) < 3.2 then
                e.lure = { r = Q.to_r, c = Q.to_c }
            elseif e.state ~= "fall" then kill_ent(e, true) end
        end
        return
    end
    if not valid(Q.to_r, Q.to_c) then
        Q.state = "fall"; Q.vy = -1; Q.vx = (Q.tx - Q.fx) * 1.1; Q.vz = (Q.tz - Q.fz) * 1.1
        lose_life("fall")
        return
    end
    Q.r, Q.c = Q.to_r, Q.to_c
    Q.state = "idle"; Q.squash = 1
    sfx("land")
    step_cube(Q.r, Q.c)
end
local function update_ride(dt)
    local R = Q.ride; R.t = R.t + dt
    local T = 1.6
    local k = clamp(R.t / T, 0, 1)
    local e = k * k * (3 - 2 * k)
    local tx, ty, tz = 0, 2.6, 0
    R.x = lerp(R.x0, tx, e); R.z = lerp(R.z0, tz, e); R.y = lerp(R.y0, ty, e) + sin(k * PI) * 1.2
    R.d.x, R.d.y, R.d.z = R.x, R.y, R.z
    Q.yaw = Q.yaw + dt * 220
    if R.t >= T then
        R.d.riding = false
        poof(R.x, R.y - 0.3, R.z, { .7, .8, 1 }, 4, false)
        local x, y, z = cpos(0, 0)
        hop_begin(Q, R.x, R.y + 0.08, R.z, x, y, z, 0.45, 0.4)
        Q.x, Q.y, Q.z = R.x, R.y, R.z
        Q.state = "hop"; Q.to_r, Q.to_c = 0, 0; Q.disc = nil; Q.ride = nil; Q.tyaw = 0
        G.spawn_t = max(G.spawn_t, 1.5)
    end
end
local function begin_round()
    clear_enemies(false)
    G.target = rule()
    each_cube(function(cb) cb.s = 0; cb.pop = 0 end)
    apply_theme()
    setup_discs()
    G.rise = 0; G.flashing = false; G.wave = false
    G.state = "intro"; G.intro_t = 0
    G.freeze, G.spawn_t, G.egg_t = 0, 2.5, 3.0 + rand() * 1.5
    Q.state = "none"
    G.banner = { text = "Level " .. G.level .. "   Round " .. G.round, sub = (G.round == 1) and ({ "Change every cube to the target colour", "Two hops per cube this time",
        "Careful: hopping again flips it back", "Two hops - and they flip back" })[min(G.level, 4)] or "", t = 0, dur = 2.6 }
end
start_clear = function()
    G.state = "clear"; G.clear_t = 0; G.flashing = true; G.wave = true
    sfx("clear")
    local bonus = 1000 + 250 * (ri() - 1)
    add_score(bonus)
    local x, y, z = q_world()
    popup(x, y + 1.3, z, "BONUS " .. bonus, { 1, .9, .4 })
    clear_enemies(true)
end
local function finish_clear()
    local unused = 0
    for _, d in ipairs(DISCS) do if not d.used then unused = unused + 1 end end
    if unused > 0 then add_score(unused * 50) end
    G.round = G.round + 1
    if G.round > 4 then G.round = 1; G.level = G.level + 1 end
    begin_round()
end

------------------------------------------------------------------ Q*bert tick + draw
local QA                                  -- Q*bert actor
local function q_update(dt, want)
    if Q.state == "idle" then
        if want then q_hop(want); return true end
    elseif Q.state == "hop" then
        Q.t = Q.t + dt
        Q.x, Q.y, Q.z = hop_pos(Q)
        if Q.t >= Q.dur then q_land() end
    elseif Q.state == "drop" then
        Q.t = Q.t + dt
        local k = clamp(Q.t / Q.dur, 0, 1)
        Q.x, Q.y, Q.z = Q.tx, lerp(Q.fy, Q.ty, k * k), Q.tz
        if k >= 1 then Q.state = "idle"; Q.squash = 1.2; sfx("land"); local x, y, z = cpos(Q.r, Q.c); land_fx(x, y, z, G.theme[1], false); shockwave(x, y + 0.03, z, { 1, .6, .3 }, 0.9, 0.35) end
    elseif Q.state == "fall" then
        Q.vy = Q.vy - 22 * dt
        Q.x, Q.y, Q.z = Q.x + Q.vx * dt, Q.y + Q.vy * dt, Q.z + Q.vz * dt
    elseif Q.state == "disc" then
        update_ride(dt)
    end
    local d = ((Q.tyaw - Q.yaw + 540) % 360) - 180
    if Q.state ~= "disc" then Q.yaw = Q.yaw + d * min(1, dt * 16) end
    Q.squash = damp(Q.squash, 0, 10, dt)
    return false
end
local function q_draw(dt)
    if Q.state == "none" or (Q.state == "fall" and Q.y < -18) then QA.root:set_position(HIDE); set_point(L.qbert, HIDE, vec3(1, 1, 1), 0, 1); return end
    local x, y, z = q_world()
    QA.root:set_position(vec3(x, y, z))
    QA.root:set_rotation(vec3(0, Q.yaw, 0))
    local sy
    if Q.state == "hop" then
        local k = clamp(Q.t / Q.dur, 0, 1); sy = 1 + 0.2 * sin(k * PI) - 0.25 * max(0, Q.squash)
    elseif Q.state == "idle" then sy = 1 - 0.3 * Q.squash + 0.025 * sin(G.t * 4)
    elseif Q.state == "fall" then sy = 1.15; QA.root:set_rotation(vec3(G.t * 300, Q.yaw, 0))
    else sy = 1 - 0.3 * Q.squash end
    local sxz = 1 / sqrt(max(0.4, sy))
    QA.piv:set_scale(vec3(sxz, sy, sxz))
    if G.state == "dying" and G.dead_kind == "hit" then QA.piv:set_rotation(vec3(0, 0, 6 * sin(G.t * 40))) else QA.piv:set_rotation(vec3(0, 0, 0)) end
    set_point(L.qbert, vec3(x, y + 1.4, z), vec3(1.0, 0.62, 0.3), 30, 4.5)
    -- trail sparkle while hopping
    if Q.state == "hop" and QA.trail then emitter_at(QA.trail, x, y + 0.4, z, 60) elseif QA.trail then emitter_at(QA.trail, x, y + 0.4, z, 0) end
end
local function collide()
    if Q.state ~= "idle" and Q.state ~= "hop" then return end
    local qx, qy, qz = q_world()
    for _, e in ipairs(ENT) do
        if e.state ~= "dead" and e.state ~= "fall" and (e.state ~= "drop" or e.t > e.dur * 0.6) then
            if dist3(qx, qy + 0.35, qz, e.x, e.y + 0.3, e.z) < 0.6 then
                if e.kind == "slick" or e.kind == "sam" then
                    add_score(300); popup(e.x, e.y + 1, e.z, "300", { .4, 1, .6 }); sfx("catch"); kill_ent(e, true)
                elseif e.kind == "green" then
                    add_score(100); popup(e.x, e.y + 1, e.z, "FREEZE", { .5, 1, .7 }); sfx("freeze"); kill_ent(e, true)
                    G.freeze = 4.5
                else
                    lose_life("hit"); return
                end
            end
        end
    end
end

------------------------------------------------------------------ autoplay (title attract + automation)
local function auto_dir()
    local best, bs = nil, -1e9
    for name, D in pairs(KK.DIRS) do
        local nr, nc = Q.r + D[1], Q.c + D[2]
        local s
        if valid(nr, nc) then
            s = (CUBES[nr][nc].s < G.target) and 3 or 0
            local x, y, z = cpos(nr, nc)
            for _, e in ipairs(ENT) do
                if e.state ~= "dead" and e.state ~= "fall" then
                    local d = dist3(x, y, z, e.x, e.y, e.z)
                    if d < 1.6 then s = s - 12 + d * 3 end
                end
            end
            s = s + rand() * 2.5
        elseif find_disc(nr, nc) then
            s = -4
            for _, e in ipairs(ENT) do if e.kind == "coily" and e.state ~= "dead" and dist3(e.x, e.y, e.z, cpos(Q.r, Q.c)) < 1.8 then s = 20 end end
        else s = -1e6 end
        if s > bs then bs, best = s, name end
    end
    return best
end

------------------------------------------------------------------ HUD / menus
local HUD = "hud"
runtime_ui.show(HUD); runtime_ui.set_screen_overlay(HUD, true)
KK.NONE = { 0, 0, 0, 0 }
KK.ORANGE, KK.CYAN, KK.WHITE, KK.GOLD, KK.MAG = { 1, .6, .2, 1 }, { .5, .85, 1, 1 }, { 1, 1, 1, 1 }, { 1, .85, .35, 1 }, { 1, .5, .85, 1 }
local cache = {}
local function upd(id, key, q) if cache[id] == key then return end; cache[id] = key; runtime_ui.set_quad(HUD, id, q) end
local function text(id, label, x, y, w, h, fs, col, align, vis)
    vis = vis ~= false
    local key = label .. "|" .. floor(x) .. "|" .. floor(y) .. "|" .. tostring(vis) .. "|" .. string.format("%.2f|%.2f|%.2f%.2f%.2f", col[4], fs, col[1], col[2], col[3])
    upd(id, key, { x = x, y = y, w = w, h = h, z = 10, style = "text", label = label, fill = KK.NONE, border = KK.NONE,
        text_color = col, font_scale = fs, align_h = align or "center", align_v = "middle", no_input = true, visible = vis })
end
local function panel(id, x, y, w, h, vis, fill, border, z, input, radius)
    vis = vis ~= false
    local key = floor(x) .. "|" .. floor(y) .. "|" .. floor(w) .. "|" .. floor(h) .. "|" .. tostring(vis) .. "|" .. table.concat(fill, ",") .. table.concat(border or KK.NONE, ",")
    upd(id, key, { x = x, y = y, w = w, h = h, z = z or 5, style = "text", label = "", fill = fill, border = border or KK.NONE,
        corner_radius = radius or 14, no_input = not input, visible = vis })
end
local function ui_state(id) local ok, s = pcall(runtime_ui.get_state, HUD, id); if ok then return s end end
local MENU = { items = {}, sel = 1 }
local function set_menu(items) MENU.items, MENU.sel = items, 1 end
local function draw_menu(vis, y0, cx)
    local s = SH / 1080
    cx = cx or SW / 2
    for i = 1, 4 do
        local it = MENU.items[i]
        local v = vis and it ~= nil
        local sel = v and MENU.sel == i
        local x, w, h = cx - 200 * s, 400 * s, 62 * s
        local y = y0 + (i - 1) * 76 * s
        panel("mi_bg" .. i, x, y, w, h, v, sel and { 1, 0.5, 0.15, 0.42 } or { 0.03, 0.02, 0.09, 0.62 },
            sel and { 1, 0.75, 0.4, 0.95 } or { 0.55, 0.45, 1.0, 0.45 }, 20, true)
        text("mi_tx" .. i, v and it.label or "", x, y, w, h, (sel and 1.55 or 1.4) * s, sel and KK.WHITE or { 0.8, 0.82, 1, 1 }, "center", v)
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
local function c4(c, a) return { c[1], c[2], c[3], a or 1 } end
local function draw_hud(dt)
    local s = SH / 1080
    local st = G.state
    local title = st == "title"
    local play = not title and st ~= "boot"
    local th = G.theme or KK.THEMES[1]
    text("p1", "PLAYER 1", 40 * s, 40 * s, 400 * s, 44 * s, 1.2 * s, KK.MAG, "left", play)
    text("score", tostring(G.score), 40 * s, 82 * s, 400 * s, 80 * s, (2.5 + 0.4 * score_pop) * s, KK.ORANGE, "left", play)
    text("hi", "HIGH  " .. G.hiscore, title and (SW * 0.25 - 200 * s) or 40 * s, title and SH * 0.36 or 160 * s, 400 * s, 40 * s, 1.0 * s, { .75, .75, 1, .9 }, title and "center" or "left", play or title)
    for i = 1, 6 do
        panel("life" .. i, (44 + (i - 1) * 40) * s, 212 * s, 28 * s, 28 * s, play and i <= G.lives, { 1, .45, .1, 1 }, { 1, .8, .5, 1 }, 6, false, 14 * s)
    end
    -- change-to indicator
    text("chg", "CHANGE TO", 40 * s, 268 * s, 300 * s, 40 * s, 1.0 * s, { .8, .8, 1, .9 }, "left", play)
    panel("sw0", 44 * s, 314 * s, 54 * s, 54 * s, play, c4(th[1]), { 1, 1, 1, .5 }, 6, false, 10 * s)
    text("swa", ">", 100 * s, 314 * s, 40 * s, 54 * s, 1.4 * s, KK.WHITE, "center", play)
    local two = (G.target or 1) == 2
    panel("sw1", 142 * s, 314 * s, 54 * s, 54 * s, play and two, c4(th[2]), { 1, 1, 1, .5 }, 6, false, 10 * s)
    text("swb", ">", 198 * s, 314 * s, 40 * s, 54 * s, 1.4 * s, KK.WHITE, "center", play and two)
    local tx = two and 240 or 142
    local pulse = 0.75 + 0.25 * sin(G.t * 5)
    panel("sw2", tx * s, 314 * s, 54 * s, 54 * s, play, c4(th[3]), { 1, 1, 1, pulse }, 6, false, 10 * s)
    local rx = SW - 440 * s
    text("lvl", "Level " .. G.level, rx, 40 * s, 400 * s, 60 * s, 1.9 * s, KK.CYAN, "right", play)
    text("rnd", "Round " .. G.round, rx, 100 * s, 400 * s, 50 * s, 1.4 * s, { .85, .85, 1, 1 }, "right", play)
    text("frz", G.freeze > 0 and string.format("TIME FROZEN  %.1f", G.freeze) or "", rx, 160 * s, 400 * s, 44 * s, 1.1 * s, { .5, 1, .7, 1 }, "right", play and G.freeze > 0)
    text("ctl_hint", "ARROWS / WASD  diagonal hops\nQ E Z C  or  MOUSE  hop toward cursor\nESC  pause    M  mute", rx, SH - 170 * s, 400 * s, 130 * s, 0.85 * s, { .7, .7, .95, .7 }, "right", play)
    -- banner
    local b = G.banner or { t = 9, dur = 0, text = "", sub = "" }
    b.t = b.t + dt
    local bvis = b.t < b.dur and play
    local ba = bvis and min(1, b.t * 5, (b.dur - b.t) * 3) or 0
    local bs = 1 + 0.15 * max(0, 1 - b.t * 5)
    text("banner", b.text, 0, SH * 0.1, SW, 100 * s, 2.6 * s * bs, { 1, .7, .3, ba }, "center", bvis)
    text("banner2", b.sub, 0, SH * 0.1 + 80 * s, SW, 60 * s, 1.3 * s, { .8, .85, 1, ba }, "center", bvis and b.sub ~= "")
    -- popups (world anchored)
    for i = 1, 6 do
        local p = POPS[i]
        if p then
            p.t = p.t + dt
            local sx, sy = project(p.x, p.y + p.t * 0.8, p.z)
            local a = clamp(1.6 - p.t, 0, 1)
            text("pop" .. i, p.txt, sx - 150 * s, sy - 25 * s, 300 * s, 50 * s, 1.4 * s, { p.col[1], p.col[2], p.col[3], a }, "center", a > 0)
        else text("pop" .. i, "", 0, 0, 10, 10, 1, KK.NONE, "center", false) end
    end
    for i = #POPS, 1, -1 do if POPS[i].t > 1.6 then table.remove(POPS, i) end end
    -- curse balloon
    local bal = (G.balloon or 0) > 0
    if bal then
        local x, y, z = q_world()
        local bx, by = project(x, y + 1.25, z)
        panel("bal", bx - 10 * s, by - 120 * s, 230 * s, 86 * s, true, { 1, 1, 1, 0.95 }, { .1, .1, .1, 1 }, 8, false, 40 * s)
        text("balt", "@!#?@!", bx - 10 * s, by - 120 * s, 230 * s, 86 * s, 1.7 * s, { .1, .05, .15, 1 }, "center", true)
    else panel("bal", 0, 0, 10, 10, false, KK.NONE); text("balt", "", 0, 0, 10, 10, 1, KK.NONE, "center", false) end
    -- title
    local tcx = SW * 0.25
    text("title", "Q*bert", tcx - 400 * s, SH * 0.12, 800 * s, 200 * s, 6.0 * s, { 1, .55 + 0.08 * sin(G.t * 2), .15, 1 }, "center", title)
    text("title2", "Remix", tcx - 400 * s, SH * 0.27, 800 * s, 80 * s, 2.4 * s, { .75, .6, 1, 1 }, "center", title)
    text("ctl", "ARROWS / WASD  hop diagonally (Up = up-right)      Q E Z C  direct diagonals      MOUSE  hold to hop toward the cursor      ESC  pause      M  mute",
        0, SH * 0.91, SW, 50 * s, 1.05 * s, { .75, .78, 1, .85 }, "center", title)
    text("hint", "Ride a spinning disc to lure Coily off the edge.  Green ball freezes time.  Catch Slick and Sam before they undo your work.",
        0, SH * 0.95, SW, 40 * s, 0.95 * s, { 1, .75, .5, .8 }, "center", title)
    -- pause / game over
    local pause = st == "paused"
    local over = st == "over"
    panel("dim", 0, 0, SW, SH, pause or over, { 0, 0, 0.03, 0.55 }, KK.NONE, 2)
    text("pause", "Paused", 0, SH * 0.22, SW, 140 * s, 4.0 * s, KK.CYAN, "center", pause)
    text("over", "Game Over", 0, SH * 0.16, SW, 150 * s, 4.4 * s, { 1, .45, .3, 1 }, "center", over)
    text("over2", (G.newhi and "NEW HIGH SCORE  " or "SCORE  ") .. G.score, 0, SH * 0.31, SW, 70 * s, 2.0 * s, KK.GOLD, "center", over)
    text("over3", "Reached Level " .. G.level .. "  Round " .. G.round, 0, SH * 0.38, SW, 60 * s, 1.3 * s, { .8, .85, 1, 1 }, "center", over)
    draw_menu(title or pause or over, title and SH * 0.45 or SH * 0.5, title and tcx or SW / 2)
end

------------------------------------------------------------------ settings menu (shared module)
local SET = nil
do
    local src = fs.read("Scripts/Lib/settings_menu.lua")
    if src then
        local ok, mod = pcall(function() return load(src, "@settings_menu.lua")() end)
        if ok and mod then
            local ok2, s = pcall(mod.new, { title = "SETTINGS", file = "Save/settings.cfg", click = function() sfx("click") end,
                music = false, defaults = { master = 0.5 }, theme = { accent = { 1, 0.6, 0.2, 1 }, accent2 = { 0.7, 0.5, 1, 1 } } })
            if ok2 then SET = s else pe_log("[Qbert] settings menu init failed: " .. tostring(s)) end
        else pe_log("[Qbert] settings menu load failed: " .. tostring(mod)) end
    end
end

------------------------------------------------------------------ input
local prev = {}
G.vkeys = {}
local function kdown(k) if G.vkeys[k] then return true end local ok, r = pcall(input.is_key_down_raw, k); return ok and r end
local function pressed(k) local d = kdown(k); local p = prev[k]; prev[k] = d; return d and not p end
local WATCH = { "Left", "Right", "Up", "Down", "W", "A", "S", "D", "Q", "E", "Z", "C", "Space", "Return", "Escape", "P", "M" }
local function latch() for _, k in ipairs(WATCH) do prev[k] = kdown(k) end end
KK.KEYMAP = { Up = "UR", W = "UR", E = "UR", Right = "DR", D = "DR", C = "DR", Down = "DL", S = "DL", Z = "DL", Left = "UL", A = "UL", Q = "UL" }
KK.KEYORDER = { "Up", "Right", "Down", "Left", "W", "D", "S", "A", "Q", "E", "Z", "C" }
local mouse_prev_down = false
local function mouse_down() local ok, d = pcall(input.is_left_mouse_down); return (ok and d) or G.vkeys.Click end
local function mouse_clicked() local d = mouse_down(); local c = d and not mouse_prev_down; mouse_prev_down = d; return c end
local function mouse_dir()
    local ok, mp = pcall(input.get_mouse_position); if not ok or not mp or not mp.x then return nil end
    local x, y, z = q_world()
    local qx, qy = project(x, y + 0.4, z)
    local dx, dy = mp.x - qx, mp.y - qy
    if abs(dx) + abs(dy) < 20 then return nil end
    if dy < 0 then return dx >= 0 and "UR" or "UL" else return dx >= 0 and "DR" or "DL" end
end
-- edge presses are buffered so a tap during a hop is never lost; held keys auto-repeat
local BUF = { dir = nil, t = 0 }
local function read_dir(dt)
    for _, k in ipairs(KK.KEYORDER) do if pressed(k) then BUF.dir, BUF.t = KK.KEYMAP[k], 0.3 end end
    if G.click then local d = mouse_dir(); if d then BUF.dir, BUF.t = d, 0.3 end end
    BUF.t = BUF.t - dt
    if BUF.t > 0 and BUF.dir then return BUF.dir, true end
    for _, k in ipairs(KK.KEYORDER) do if kdown(k) then return KK.KEYMAP[k], false end end
    if mouse_down() then return mouse_dir(), false end
end

------------------------------------------------------------------ game flow
KK.HISAVE = "Save/hiscore.txt"
local function new_game()
    G.score, G.lives, G.level, G.round, G.next_extra, G.newhi = 0, 3, 1, 1, 8000, false
    sfx("start")
    begin_round()
end
local function to_title()
    clear_enemies(false)
    G.level, G.round = 1, 1
    G.target = 1; apply_theme(KK.THEMES[1]); setup_discs()
    each_cube(function(cb) cb.s = 0 end)
    G.flashing, G.wave, G.freeze = false, false, 0
    G.state = "title"; G.title_t = 0
    q_drop_in(0, 0)
    G.spawn_t, G.egg_t = 3, 4
    set_menu({ { label = "PLAY", act = "play" }, { label = "SETTINGS", act = "settings" }, { label = "QUIT", act = "quit" } })
end
local function game_over()
    G.state = "over"; sfx("gameover")
    G.newhi = G.score > 0 and G.score >= G.hiscore
    pcall(fs.write, KK.HISAVE, tostring(G.hiscore))
    set_menu({ { label = "PLAY AGAIN", act = "play" }, { label = "TITLE", act = "title" } })
end
local function do_menu_action(act)
    sfx("click")
    if act == "play" then new_game()
    elseif act == "resume" then G.state = "play"
    elseif act == "settings" then if SET then runtime_ui.show(HUD); SET:open(function() end) end
    elseif act == "title" then to_title()
    elseif act == "quit" then pcall(fs.write, KK.HISAVE, tostring(G.hiscore)); pcall(engine.quit) end
end
local function update_dying(dt)
    G.dead_t = G.dead_t + dt
    if G.dead_kind == "fall" then q_update(dt, nil) end
    if G.dead_t > (G.dead_kind == "fall" and 1.5 or 1.9) then
        clear_enemies(G.dead_kind == "hit")
        G.balloon = 0
        G.lives = G.lives - 1
        if G.lives < 0 then G.lives = 0; game_over(); return end
        G.state = "play"; G.spawn_t, G.egg_t = 2.0, 3.5; G.freeze = 0
        if G.dead_kind == "fall" then q_drop_in(0, 0) else Q.state = "idle"; Q.squash = 0.8 end
    end
end
-- one simulation tick of an active board (play + title attract)
local function board_tick(dt, want)
    G.freeze = max(0, G.freeze - dt)
    if q_update(dt, want) then BUF.dir, BUF.t = nil, 0 end
    director(dt)
    for i = #ENT, 1, -1 do local e = ENT[i]; update_ent(e, dt); if e.state == "dead" then table.remove(ENT, i) end end
    if G.state == "play" then collide() end
end

------------------------------------------------------------------ visuals tick
local function update_visuals(dt)
    update_flashes(dt); update_shards(dt); update_rings(dt); update_backdrop(dt); update_pyramid(dt); update_discs(dt)
    q_draw(dt)
    local cx, cy, cz, cl = 0, 0, 0, false
    for _, e in ipairs(ENT) do
        draw_ent(e)
        if e.kind == "coily" and e.state ~= "dead" then cx, cy, cz, cl = e.x, e.y, e.z, true end
        if (e.kind == "red" or e.kind == "green") and e.state ~= "dead" and rand() < dt * 25 * PSCALE then
            local col = KK.COL[e.kind]
            burst(e.x, e.y + 0.2, e.z, { c0 = hot(col, 1.6, 0.2), c1 = fade(col, 0.5), count = 2, smin = 0.02, smax = 0.05, lmin = 0.2, lmax = 0.45, radius = 0.12, spread = 0.6, drag = 2 })
        end
    end
    if cl then set_point(L.coily, vec3(cx, cy + 1.3, cz), vec3(0.7, 0.3, 1.0), 26, 3.5) else set_point(L.coily, HIDE, vec3(1, 1, 1), 0, 1) end
    if G.freeze > 0 and rand() < dt * 30 * PSCALE then
        local r = floor(rand() * NR); local c = floor(rand() * (r + 1)); local x, y, z = cpos(r, c)
        burst(x, y + 0.2, z, { c0 = vec4(1.2, 2, 2.4, 1), c1 = vec4(.3, .6, 1, 0), count = 6, smin = 0.02, smax = 0.05, lmin = 0.5, lmax = 1, radius = 0.4, spread = 1, vel = vec3(0, 0.6, 0) })
    end
    if G.flashing and rand() < dt * 14 * PSCALE then
        local th = G.theme; local col = ({ th[1], th[2], th[3], { 1, 1, 1 } })[floor(rand() * 4) + 1]
        local r = floor(rand() * NR); local c = floor(rand() * (r + 1)); local x, y, z = cpos(r, c)
        burst(x, y + 0.3, z, { c0 = hot(col, 2.5, 0.4), c1 = fade(col), count = 30, smin = 0.03, smax = 0.07, lmin = 0.6, lmax = 1.2, radius = 0.2, spread = 6, vel = vec3(0, 4, 0), grav = vec3(0, -5, 0), drag = 1.2 })
    end
    G.rise = min(1, G.rise + dt / 1.3)
    set_point(L.fill_l, vec3(-3 + sin(G.t * 0.4) * 1.5, 2 + cos(G.t * 0.3), 9), vec3(0.3, 0.6, 1.0), 90, 22)
    set_point(L.fill_r, vec3(9, 2 + sin(G.t * 0.35), -3 + cos(G.t * 0.45) * 1.5), vec3(1.0, 0.35, 0.75), 90, 22)
    -- camera: title framing offset + trauma shake
    G.cam_ox = damp(G.cam_ox or 0, (G.state == "title") and -3.4 or 0, 3, dt)
    shake = max(0, shake - dt * 2.0)
    local sk = shake * shake * SHAKE_SCALE
    set_cam(G.cam_ox + (sin(G.t * 47) + sin(G.t * 31.7) * 0.5) * 0.25 * sk, (cos(G.t * 41) + sin(G.t * 23.3) * 0.5) * 0.25 * sk)
    score_pop = max(0, score_pop - dt * 4)
    G.balloon = max(0, (G.balloon or 0) - dt)
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
            pe_log("[Qbert] ready")
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
    local st = G.state
    if st == "title" then
        local act = menu_input(pressed)
        if act then do_menu_action(act)
        else
            G.title_t = G.title_t + dt
            local want = (Q.state == "idle" and G.title_t > 0.6) and auto_dir() or nil
            if want then G.title_t = 0.25 end
            board_tick(dt, want)
            if cubes_done() == NR * (NR + 1) / 2 then each_cube(function(cb) cb.s = 0; cb.pop = 1 end) end
            if Q.state == "fall" and Q.y < -16 then q_drop_in(0, 0) end
        end
    elseif st == "intro" then
        G.intro_t = G.intro_t + dt
        if G.intro_t > 1.0 and Q.state == "none" then q_drop_in(0, 0); sfx("hatch") end
        q_update(dt, nil)
        if G.intro_t > 1.6 and Q.state == "idle" then G.state = "play" end
    elseif st == "play" then
        if pressed("Escape") or pressed("P") then
            G.state = "paused"; sfx("click")
            set_menu({ { label = "RESUME", act = "resume" }, { label = "SETTINGS", act = "settings" }, { label = "QUIT TO TITLE", act = "title" } })
        else
            local want = read_dir(dt)
            if G.autoplay then want = (Q.state == "idle") and auto_dir() or nil end
            board_tick(dt, want)
        end
    elseif st == "dying" then
        update_dying(dt)
    elseif st == "clear" then
        G.clear_t = G.clear_t + dt
        q_update(dt, nil)
        if G.clear_t > 2.6 then finish_clear() end
    elseif st == "paused" then
        if pressed("Escape") or pressed("P") then G.state = "play"
        else local act = menu_input(pressed); if act then do_menu_action(act) end end
    elseif st == "over" then
        local act = menu_input(pressed)
        if act then do_menu_action(act) end
    end
    update_visuals(dt)
    draw_hud(dt)
    latch()
end

local function init()
    build_lights(); build_pyramid(); build_backdrop(); build_rings(); build_debris()
    QA = make_actor("qbert"); QA.root:set_scale(vec3(1.2, 1.2, 1.2))
    QA.trail = new_emitter({ c0 = vec4(2, 1.1, 0.4, 1), c1 = vec4(1, 0.3, 0.05, 0), count = 200, radius = 0.15, smin = 0.02, smax = 0.05, lmin = 0.2, lmax = 0.45, noise = 0.5, drag = 2 })
    for kind, n in pairs({ red = 4, green = 2, egg = 1, coily = 1, slick = 1, sam = 1 }) do
        POOL[kind] = {}
        for i = 1, n do POOL[kind][i] = make_actor(kind) end
    end
    for i = 1, 4 do DISC_POOL[i] = make_actor("disc") end
    paint_actors()
    G.target = 1; apply_theme(KK.THEMES[1])
    local hs = fs.read(KK.HISAVE); G.hiscore = tonumber(hs or "") or 0
    G.freeze, G.spawn_t, G.egg_t, G.next_extra = 0, 3, 4, 8000
    pcall(audio.set_master_volume, 0.5)
    G.state = "boot"
end
init()
hooks { update = update }

-- automation helpers (MCP): QB.sim(seconds, keys) steps the game deterministically at 60 Hz
function G.sim(sec, keys)
    G.vkeys = keys or {}
    for _ = 1, floor(sec * 60) do update(1 / 60) end
    G.vkeys = {}
end
G.new_game = new_game
G.to_title = to_title
G.begin_round = begin_round
G.spawn = spawn
G.CUBES = CUBES
G.Q = Q
G.ENT = ENT
G.start_clear = function() start_clear() end
G.SET = SET
G.clear_enemies = clear_enemies
