-- GALAGA REMIX  (PhasmaEngine, Lua)
-- A modernized remake of Namco's Galaga (1981). Faithful core: 40-ship formation that swoops in on looping
-- entry paths, diving attacks (bees loop, butterflies weave, bosses dive with escorts), the Boss Galaga
-- tractor beam that captures your fighter, rescue for a DUAL FIGHTER, challenging stages every 4th stage
-- (3, 7, 11 ...), stage badges (1/5/10/20/30/50 pennants), 2 shots on screen per fighter, extra ships.
-- Modern visuals: cooked 3D insect ships with flapping wings, deep-space nebula + 3-layer parallax stars,
-- a ringed gas giant, neon engine trails, layered explosion particles + debris + shockwaves, dynamic lights,
-- a glowing animated tractor beam, HDR bloom with TAA.
local PI, TAU = math.pi, math.pi * 2
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local G = { state = "boot", t = 0 }
local KK = {}   -- constant tables (keeps the main chunk under LuaJIT's 200-local limit)
_G.GA = G

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
local ss = scene.add_empty_node("GalagaSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "space.hdr")
S("hdr", true); S("taa", true); S("cas_sharpening", true); S("motion_blur", false); S("fxaa", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.8)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("dof", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", true); S("IBL_intensity", 0.6)
S("color_grading", true); S("color_grading_saturation", 1.15); S("color_grading_contrast", 1.08)

------------------------------------------------------------------ playfield + camera
local FX, FY = 15.0, 21.0            -- half extents of the playfield
local PLAYER_Y = -17.5
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1280, surf.height or 720
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local FOVX = 0.9
local CAM = { z = 85, tilt = 7.0 }
local function fit_camera()
    local aspect = SW / max(1, SH)
    local half_h = FY + 1.2
    CAM.z = half_h * aspect / math.tan(FOVX * 0.5)
end
pcall(function() cam:set_fov(math.deg(FOVX)) end)
fit_camera()
cam:set_position(vec3(0, -CAM.tilt, CAM.z)); cam:look_at(vec3(0, 0, 0))

------------------------------------------------------------------ templates -> clones
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[Galaga] missing template " .. name); return nil end
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

------------------------------------------------------------------ palette (per template materials)
-- {base, emissive, roughness, metallic}
local PAL = {
    fighter = { body = { { .92, .93, .97 }, { .05, .05, .07 }, .22, .35 }, metal = { { .32, .35, .42 }, { 0, 0, 0 }, .25, .9 },
        accent = { { 1, .08, .1 }, { .9, .05, .06 }, .3, .2 }, glass = { { .2, .7, 1 }, { .6, 2.2, 4.0 }, .05, 0 },
        glow = { { .4, .8, 1 }, { 2.0, 4.5, 8.0 }, .3, 0 } },
    cap = { body = { { 1, .3, .3 }, { .6, .06, .06 }, .25, .3 }, metal = { { .4, .18, .2 }, { .1, 0, 0 }, .3, .8 },
        accent = { { 1, .9, .9 }, { .8, .7, .7 }, .3, .1 }, glass = { { 1, .2, .2 }, { 4.0, .5, .4 }, .05, 0 },
        glow = { { 1, .3, .3 }, { 6.0, 1.0, .8 }, .3, 0 } },
    bee = { body = { { 1, .75, .05 }, { .7, .45, 0 }, .3, .1 }, accent = { { .12, .3, 1 }, { .1, .3, 1.2 }, .25, .3 },
        eye = { { 1, .2, .1 }, { 5.0, .6, .3 }, .1, 0 }, wing = { { .3, .5, .9 }, { .03, .09, .3 }, .2, .2 } },
    bfly = { body = { { 1, .1, .15 }, { .9, .04, .07 }, .3, .1 }, accent = { { .95, .95, 1 }, { .5, .5, .6 }, .3, .1 },
        eye = { { 1, .9, .3 }, { 4.0, 3.4, .6 }, .1, 0 }, wing = { { .12, .25, 1, .8 }, { .05, .14, .8 }, .15, .1 },
        wingtrim = { { 1, 1, 1 }, { .8, .8, 1.1 }, .2, 0 } },
    boss = { body = { { .1, .8, .32 }, { .04, .75, .2 }, .28, .3 }, accent = { { 1, .72, .18 }, { .9, .45, .05 }, .2, .8 },
        eye = { { 1, .2, 1 }, { 4.5, .6, 4.5 }, .1, 0 }, wing = { { .6, .2, 1, .8 }, { .3, .08, .8 }, .15, .1 } },
    boss2 = { body = { { .35, .3, 1 }, { .25, .15, 1.0 }, .25, .35 }, accent = { { 1, .45, .8 }, { 1.2, .3, .7 }, .2, .6 },
        eye = { { 1, .2, .1 }, { 5.0, .7, .3 }, .1, 0 }, wing = { { .2, .5, 1, .8 }, { .1, .3, .9 }, .15, .1 } },
    cbee = { body = { { .1, .95, .9 }, { .05, .6, .55 }, .25, .2 }, accent = { { 1, .2, .8 }, { 1.4, .2, 1.0 }, .25, .3 },
        eye = { { 1, 1, 1 }, { 4, 4, 4 }, .1, 0 }, wing = { { 1, .4, .9, .6 }, { .6, .15, .5 }, .1, 0 } },
    cbfly = { body = { { 1, .5, .05 }, { .8, .3, 0 }, .25, .2 }, accent = { { .2, 1, .3 }, { .2, 1.2, .3 }, .3, .1 },
        eye = { { .3, 1, 1 }, { .6, 4, 4 }, .1, 0 }, wing = { { .3, 1, .4, .8 }, { .12, .7, .15 }, .15, .1 },
        wingtrim = { { 1, .9, .3 }, { 3, 2.5, .6 }, .2, 0 } },
    cboss = { body = { { .95, .95, 1 }, { .4, .4, .5 }, .2, .5 }, accent = { { 1, .2, .2 }, { 1.6, .15, .1 }, .2, .6 },
        eye = { { .3, .7, 1 }, { .6, 2.4, 5 }, .1, 0 }, wing = { { 1, .3, .2, .8 }, { .8, .15, .1 }, .15, .1 } },
}
KK.PARTS = {
    fighter = { "body", "metal", "accent", "glass", "glow" },
    bee = { "body", "accent", "eye" }, bfly = { "body", "accent", "eye" }, boss = { "body", "accent", "eye" },
}
KK.BASEKIND = { fighter = "fighter", cap = "fighter", bee = "bee", cbee = "bee", bfly = "bfly", cbfly = "bfly", boss = "boss", boss2 = "boss", cboss = "boss" }
local function paint_templates()
    for kind, parts in pairs(PAL) do
        if kind:sub(1, 1) == "c" and kind ~= "cap" then parts = {} end   -- challenge skins are applied live by skin()
        for part, p in pairs(parts) do
            local names = { "T_" .. kind .. "_" .. part }
            if part == "wing" or part == "wingtrim" then names[2] = names[1] .. "R" end
            for _, nm in ipairs(names) do
                local n = tnode(nm)
                if n then
                    paint(n, p[1], p[2], p[3], p[4])
                    if part == "wing" or part == "wingtrim" then pcall(_mds, n, true); qpush(function() pcall(_mds, n, true) end) end
                end
            end
        end
    end
end

------------------------------------------------------------------ ships (root node + parented cooked parts, flapping wings)
local function make_ship(kind)
    seq = seq + 1
    local root = scene.add_empty_node("ship_" .. kind .. seq)
    root:set_position(HIDE)
    local s = { root = root, kind = kind, nodes = {} }
    local base = KK.BASEKIND[kind]
    local function add(name, parent)
        local n = clone(name, vec3(0, 0, 0), nil, parent or root); s.nodes[#s.nodes + 1] = n; return n
    end
    local function build(k)
        local list = {}
        for _, p in ipairs(KK.PARTS[base]) do list[#list + 1] = add("T_" .. k .. "_" .. p) end
        local wl, wr
        if base ~= "fighter" then
            wl = add("T_" .. k .. "_wing"); wr = add("T_" .. k .. "_wingR")
            list[#list + 1] = wl; list[#list + 1] = wr
            if base == "bfly" then list[#list + 1] = add("T_" .. k .. "_wingtrim", wl); list[#list + 1] = add("T_" .. k .. "_wingtrimR", wr) end
        end
        return list, wl, wr
    end
    s.main, s.wl, s.wr = build(kind)
    if kind == "boss" then s.alt, s.awl, s.awr = build("boss2"); for _, n in ipairs(s.alt) do n:set_enabled(false) end end
    s.vis = true
    return s
end
local function ship_visible(s, v)
    if s.vis == v then return end
    s.vis = v
    if not v then s.root:set_position(HIDE) end
end
local function ship_damaged(s, dmg)
    if not s.alt or s.dmg == dmg then return end
    s.dmg = dmg
    for _, n in ipairs(s.main) do n:set_enabled(not dmg) end
    for _, n in ipairs(s.alt) do n:set_enabled(dmg) end
end
-- heading: degrees, 0 = nose up (+Y). flap: wing angle in degrees.
local function place_ship(s, x, y, z, heading, bank, scale, flap)
    s.root:set_position(vec3(x, y, z or 0))
    s.root:set_rotation(vec3(0, bank or 0, heading or 0))
    if scale then s.root:set_scale(vec3(scale, scale, scale)) end
    if flap then
        local wl, wr = s.wl, s.wr
        if s.dmg then wl, wr = s.awl, s.awr end
        if wl then wl:set_rotation(vec3(0, flap, 0)); wr:set_rotation(vec3(0, -flap, 0)) end
    end
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
    lights.set_directional_light(0, vec3(0.55, 0.35, 0.75), vec3(0.85, 0.85, 1.0), 2.2)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    L.fill_l = addp(vec3(-FX - 8, 6, 14), vec3(0.3, 0.6, 1.0), 120, 60)
    L.fill_r = addp(vec3(FX + 8, 10, 14), vec3(1.0, 0.35, 0.8), 120, 60)
    L.player = addp(HIDE, vec3(0.4, 0.8, 1.0), 0, 1)
    L.beam = addp(HIDE, vec3(0.3, 0.6, 1.0), 0, 1)
    L.flash = {}
    for i = 1, 6 do L.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1, power = 0, rad = 6 } end
end
local flash_next = 1
local function flash(x, y, col, power, life, rad)
    local f = L.flash[flash_next]; flash_next = flash_next % #L.flash + 1
    f.t, f.life, f.pos, f.col, f.power, f.rad = 0, life or 0.35, vec3(x, y, 2.5), vec3(col[1], col[2], col[3]), power or 40, rad or 9
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
        position = vec3(x, y, o.z or 0.5), velocity = o.vel or vec3(0, 0, 0),
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
        s.x, s.y, s.z = x, y, rr(-0.3, 0.6)
        s.vx, s.vy, s.vz = cos(a) * sp, sin(a) * sp, rr(-3, 6)
        s.rx, s.ry, s.rz = rr(0, 360), rr(0, 360), rr(0, 360)
        s.wx, s.wy, s.wz = rr(-700, 700), rr(-700, 700), rr(-700, 700)
        s.sz = rr(0.35, 0.75); s.life = rr(0.5, 1.0)
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
            s.vx, s.vy, s.vz = s.vx * d, s.vy * d, s.vz * d
            s.x, s.y, s.z = s.x + s.vx * dt, s.y + s.vy * dt, s.z + s.vz * dt
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
            r.node:set_position(vec3(r.x, r.y, 0.3)); r.node:set_scale(vec3(s, s, 1 + 2 * (1 - k)))
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
        lmin = 0.7, lmax = 1.4, radius = 0.6, spread = 9, drag = 1.0, vel = vec3(0, -1.5, 0) })
    shatter(slot or 4, x, y, big and 12 or 7, big and 1.3 or 1)
    shockwave(x, y, col, big and 5.5 or 3.2, big and 0.6 or 0.4)
    flash(x, y, col, big and 120 or 60, big and 0.5 or 0.3, big and 16 or 10)
    add_shake(big and 0.45 or 0.12)
end

------------------------------------------------------------------ deep space backdrop: nebula tiles, gas giant, 3 parallax star layers
local SPACE = { speed = 1.0, warp = 0, nebula = {}, stars = {} }
KK.NEB_Z, KK.NEB_S = -230, 340
local function view_half(z)   -- half extents of the view at depth z
    local d = CAM.z - z
    local hh = d * math.tan(FOVX * 0.5) * SH / SW
    return hh * SW / SH, hh
end
KK.STAR_LAYERS = { { z = -70, n = 110, v = 2.2, s = 0.22 }, { z = -32, n = 70, v = 5.5, s = 0.2 }, { z = -6, n = 34, v = 12, s = 0.16 } }
local function build_space()
    for i = 1, 2 do
        local q = prim("quad", vec3(0, (i - 1) * KK.NEB_S, KK.NEB_Z), vec3(KK.NEB_S, KK.NEB_S, 1))
        paint(q, { 0, 0, 0 }, { 1.25, 1.25, 1.4 }, 1.0, 0.0)
        pcall(_mds, q, true); qpush(function() pcall(_mds, q, true) end)
        mtex(q, "emissive", "Textures/nebula.png")
        SPACE.nebula[i] = q
    end
    SPACE.neb_y = 0
    SPACE.planet = clone("T_planet", vec3(52, 34, -170), vec3(20, 20, 20))
    SPACE.pring = clone("T_planetring", HIDE, vec3(20, 20, 20))   -- ring disabled: reads as a dark disc on lavapipe
    paint(tnode("T_planet"), { 1, 1, 1 }, { 0.55, 0.5, 0.6 }, 0.7, 0.0)
    mtex(tnode("T_planet"), "base_color", "Textures/planet.png"); mtex(tnode("T_planet"), "emissive", "Textures/planet.png")
    paint(tnode("T_planetring"), { 0.2, 0.15, 0.25 }, { 0.55, 0.42, 0.7 }, 0.6, 0.1)
    pcall(_mds, tnode("T_planetring"), true)
    SPACE.py = 34
    local SC = { { 0.6, 0.7, 1.0, 1.4 }, { 0.9, 0.9, 1.0, 2.6 }, { 1.0, 0.95, 0.9, 5.0 } }
    for li, Lr in ipairs(KK.STAR_LAYERS) do
        local c = SC[li]
        paint(tnode("T_star_" .. (li - 1)), { c[1], c[2], c[3] }, { c[1] * c[4], c[2] * c[4], c[3] * c[4] }, 0.5, 0)
        local hw, hh = view_half(Lr.z)
        for k = 1, Lr.n do
            local st = { x = rr(-hw, hw), y = rr(-hh, hh), z = Lr.z + rr(-3, 3), ph = rr(0, TAU), tw = rr(1.5, 5), sz = Lr.s * rr(0.6, 1.4), L = li }
            st.node = clone("T_star_" .. (li - 1), vec3(st.x, st.y, st.z), vec3(st.sz, st.sz, st.sz))
            SPACE.stars[#SPACE.stars + 1] = st
        end
    end
    SPACE.streak = new_emitter({ c0 = vec4(0.8, 0.9, 1.6, 1), c1 = vec4(0.3, 0.4, 1.0, 0), count = 400, radius = 0, smin = 0.04, smax = 0.08,
        lmin = 0.4, lmax = 0.8, noise = 0.0, drag = 0.0, vel = vec3(0, -60, 0) })
end
local function update_space(dt)
    local sp = SPACE.speed + SPACE.warp * 9
    SPACE.neb_y = (SPACE.neb_y - dt * 0.9 * sp) % KK.NEB_S
    for i, q in ipairs(SPACE.nebula) do q:set_position(vec3(0, SPACE.neb_y + (i - 2) * KK.NEB_S + KK.NEB_S * 0.25, KK.NEB_Z)) end
    SPACE.py = SPACE.py - dt * 0.25 * (1 + SPACE.warp * 3)
    if SPACE.py < -110 then SPACE.py = 110 end
    SPACE.planet:set_position(vec3(52, SPACE.py, -170))
    SPACE.planet:set_rotation(vec3(0, G.t * 2.5, -15)); SPACE.pring:set_rotation(vec3(-72, 0, -15))
    for _, st in ipairs(SPACE.stars) do
        local Lr = KK.STAR_LAYERS[st.L]
        local hw, hh = view_half(Lr.z)
        st.y = st.y - Lr.v * sp * dt
        if st.y < -hh - 2 then st.y = hh + 2; st.x = rr(-hw, hw) end
        local tw = 0.65 + 0.35 * sin(G.t * st.tw + st.ph)
        local s = st.sz * tw
        local stretch = 1 + SPACE.warp * (3 + st.L * 6)
        st.node:set_position(vec3(st.x, st.y, st.z)); st.node:set_scale(vec3(s, s * stretch, s))
    end
    if SPACE.streak then
        local hw, hh = view_half(-10)
        emitter_at(SPACE.streak, rr(-hw, hw), hh, -10, SPACE.warp * 260, vec3(0, -40 - 80 * SPACE.warp, 0))
        pcall(particles.set_emitter, SPACE.streak, "spawn_radius", 0.0)
    end
end

------------------------------------------------------------------ paths (polylines sampled from lines + arcs; followed at constant speed)
local Path = {}
Path.__index = Path
local function newpath(x, y) return setmetatable({ pts = { { x, y } } }, Path) end
function Path:to(x, y) self.pts[#self.pts + 1] = { x, y }; return self end
function Path:last() return self.pts[#self.pts][1], self.pts[#self.pts][2] end
-- arc around centre (cx,cy) from the current point, sweeping `sweep` radians (+ = counter-clockwise)
function Path:arc(cx, cy, sweep)
    local x, y = self:last()
    local r = sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
    local a0 = atan2(y - cy, x - cx)
    local n = max(4, floor(abs(sweep) * r / 0.6))
    for i = 1, n do local a = a0 + sweep * i / n; self:to(cx + cos(a) * r, cy + sin(a) * r) end
    return self
end
-- smooth quadratic bezier to (x,y) with control (qx,qy)
function Path:curve(qx, qy, x, y)
    local x0, y0 = self:last()
    for i = 1, 10 do
        local t = i / 10; local u = 1 - t
        self:to(u * u * x0 + 2 * u * t * qx + t * t * x, u * u * y0 + 2 * u * t * qy + t * t * y)
    end
    return self
end
function Path:mirror() for _, p in ipairs(self.pts) do p[1] = -p[1] end; return self end
function Path:finish()
    self.len = { 0 }
    for i = 2, #self.pts do
        local a, b = self.pts[i - 1], self.pts[i]
        self.len[i] = self.len[i - 1] + sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
    end
    self.total = self.len[#self.pts]
    return self
end
-- position + tangent at distance d along the path
function Path:at(d)
    local P, Ln = self.pts, self.len
    if d <= 0 then local a, b = P[1], P[2] or P[1]; return a[1], a[2], b[1] - a[1], b[2] - a[2] end
    if d >= self.total then local a, b = P[#P - 1] or P[#P], P[#P]; return b[1], b[2], b[1] - a[1], b[2] - a[2] end
    local lo, hi = 1, #P
    while hi - lo > 1 do local m = floor((lo + hi) / 2); if Ln[m] <= d then lo = m else hi = m end end
    local a, b = P[lo], P[hi]; local seg = Ln[hi] - Ln[lo]
    local t = seg > 0 and (d - Ln[lo]) / seg or 0
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, b[1] - a[1], b[2] - a[2]
end

------------------------------------------------------------------ formation
local SPX, SPY, FTOP = 2.85, 2.6, 15.2
local FORM = { sway = 0, breath = 0, mode = "sway", t = 0 }
local function slot_pos(col, row)
    local dx = (col - 5.5) * SPX
    local b = FORM.breath
    local x = dx * (1 + 0.16 * b) + FORM.sway
    local y = FTOP - (row - 1) * SPY * (1 + 0.1 * b) + 0.6 * b
    return x, y
end
local function update_formation(dt, complete)
    FORM.t = FORM.t + dt
    if complete then
        FORM.sway = damp(FORM.sway, 0, 2, dt)
        FORM.bt = (FORM.bt or 0) + dt
        FORM.breath = 0.5 - 0.5 * cos(FORM.bt * 1.6)
    else
        FORM.bt = 0
        FORM.breath = damp(FORM.breath, 0, 3, dt)
        FORM.sway = 2.6 * sin(FORM.t * 0.9)
    end
end

------------------------------------------------------------------ enemy pools
local POOLS = { bee = {}, bfly = {}, boss = {}, cap = {} }
KK.POOL_N = { bee = 20, bfly = 16, boss = 4, cap = 4 }
local function build_pools()
    for kind, n in pairs(KK.POOL_N) do
        for i = 1, n do POOLS[kind][i] = { ship = make_ship(kind == "cap" and "cap" or kind), used = false } end
    end
end
local function acquire(kind)
    local base = (kind == "cap") and "cap" or kind
    for _, p in ipairs(POOLS[base]) do if not p.used then p.used = true; ship_visible(p.ship, true); return p end end
end
local function release(p) if p then p.used = false; ship_damaged(p.ship, false); ship_visible(p.ship, false) end end

------------------------------------------------------------------ trails (neon engine trails: pooled emitters bound to moving ships)
local TRAILS = {}
local function build_trails()
    for i = 1, 12 do
        TRAILS[i] = { em = new_emitter({ c0 = vec4(1.0, 0.6, 2.4, 1), c1 = vec4(0.2, 0.1, 0.8, 0), count = 240, radius = 0.15,
            smin = 0.07, smax = 0.18, lmin = 0.2, lmax = 0.45, noise = 1.2, drag = 2.0 }), owner = nil }
    end
end
KK.TRAIL_COL = { bee = { vec4(2.4, 1.8, 0.3, 1), vec4(0.9, 0.2, 0.0, 0) }, bfly = { vec4(2.6, 0.4, 0.6, 1), vec4(0.4, 0.1, 1.0, 0) },
    boss = { vec4(0.6, 2.6, 1.2, 1), vec4(0.4, 0.1, 1.2, 0) }, cap = { vec4(2.8, 0.6, 0.5, 1), vec4(0.8, 0.0, 0.2, 0) } }
local function grab_trail(e)
    if e.trail then return end
    for _, t in ipairs(TRAILS) do
        if not t.owner then
            t.owner = e; e.trail = t
            local c = KK.TRAIL_COL[e.kind] or KK.TRAIL_COL.bee
            pcall(particles.set_emitter, t.em, "color_start", c[1]); pcall(particles.set_emitter, t.em, "color_end", c[2])
            return
        end
    end
end
local function drop_trail(e)
    if e.trail then emitter_at(e.trail.em, 0, -1000, 0, 0); e.trail.owner = nil; e.trail = nil end
end

------------------------------------------------------------------ enemies
local enemies = {}
G.enemies = enemies
KK.POINTS = { bee = { 50, 100 }, bfly = { 80, 160 }, boss = { 150, 400 }, cap = { 500, 1000 } }
KK.SCALE = { bee = 0.9, bfly = 0.92, boss = 0.95, cap = 0.9 }
KK.RADIUS = { bee = 1.15, bfly = 1.2, boss = 1.4, cap = 1.1 }
local function new_enemy(kind, col, row)
    local p = acquire(kind)
    if not p then return nil end
    local e = { kind = kind, p = p, ship = p.ship, col = col, row = row, x = 0, y = 40, hd = 180, bank = 0,
        hp = kind == "boss" and 2 or 1, state = "wait", delay = 0, d = 0, ph = rr(0, TAU), alive = true, fire_t = 9 }
    enemies[#enemies + 1] = e
    return e
end
local function remove_enemy(e)
    e.alive = false; drop_trail(e); release(e.p)
    for i = #enemies, 1, -1 do if enemies[i] == e then table.remove(enemies, i) end end
end
local function enemy_slot(e)
    if e.cap_of then local x, y = slot_pos(e.cap_of.col, e.cap_of.row); return x, y + 2.4 end
    return slot_pos(e.col, e.row)
end
local function angle_to(dx, dy) return math.deg(atan2(-dx, dy)) end
local function turn_toward(a, b, k, dt)
    local d = (b - a + 540) % 360 - 180
    return a + d * (1 - math.exp(-k * dt))
end
local function set_path(e, path, speed, after)
    e.path = path:finish(); e.d = 0; e.speed = speed; e.after = after; e.state = "path"
end

------------------------------------------------------------------ player
local P = { x = 0, vx = 0, bank = 0, state = "none", dual = false, inv = 0, fire_cd = 0, t = 0 }
G.P = P
local DUAL_OFF = 0.95
local function build_player()
    P.ships = { make_ship("fighter"), make_ship("fighter") }
    P.em = {}
    for i = 1, 2 do
        P.em[i] = new_emitter({ c0 = vec4(1.2, 2.6, 5.0, 1), c1 = vec4(0.6, 0.1, 2.0, 0), count = 400, radius = 0.12,
            smin = 0.06, smax = 0.16, lmin = 0.15, lmax = 0.35, noise = 0.8, drag = 1.0, vel = vec3(0, -9, 0) })
    end
    P.icons = {}
    for i = 1, 6 do P.icons[i] = make_ship("fighter") end
end
local function player_points()
    if P.dual then return { P.x - DUAL_OFF, P.x + DUAL_OFF } end
    return { P.x }
end
local BOLTS, EBOLTS = {}, {}
local function build_bolts()
    paint(tnode("T_bolt"), { 0.6, 0.9, 1 }, { 2.5, 5.0, 9.0 }, 0.2, 0)
    paint(tnode("T_ebolt"), { 1, 0.3, 0.6 }, { 9.0, 1.2, 3.5 }, 0.2, 0)
    for i = 1, 8 do BOLTS[i] = { node = clone("T_bolt", HIDE), used = false } end
    for i = 1, 18 do EBOLTS[i] = { node = clone("T_ebolt", HIDE), used = false } end
end
local function live_bolts() local n = 0; for _, b in ipairs(BOLTS) do if b.used then n = n + 1 end end; return n end
local function fire_player()
    local pts = player_points()
    local cap = P.dual and 4 or 2
    if live_bolts() + #pts > cap then return false end
    for _, x in ipairs(pts) do
        for _, b in ipairs(BOLTS) do
            if not b.used then
                b.used, b.x, b.y = true, x, PLAYER_Y + 1.6
                break
            end
        end
        burst(x, PLAYER_Y + 1.7, { c0 = vec4(2, 4, 7, 1), c1 = vec4(0.2, 0.5, 1.5, 0), count = 10, smin = 0.05, smax = 0.12,
            lmin = 0.06, lmax = 0.16, radius = 0.05, spread = 8, vel = vec3(0, 6, 0) })
    end
    sfx("shoot")
    return true
end
local function fire_enemy(x, y, tx)
    for _, b in ipairs(EBOLTS) do
        if not b.used then
            local dx, dy = tx - x, PLAYER_Y - y
            local l = sqrt(dx * dx + dy * dy)
            local sp = 15 + min(8, (G.stage or 1) * 0.5)
            local vx = clamp(dx / l * sp, -6, 6)
            b.used, b.x, b.y, b.vx, b.vy = true, x, y, vx, -sqrt(max(1, sp * sp - vx * vx))
            sfx("eshot")
            return
        end
    end
end

------------------------------------------------------------------ stage layouts + entry paths
local function is_challenge(st) return st % 4 == 3 end
KK.ENTRY = {}
function KK.ENTRY.top(v) return newpath(1.4, 26):to(1.4, 16):curve(1.4, 5, 6 + v, 1):arc(6 + v, 5 - v * 0.3, 1.5 * PI) end
function KK.ENTRY.bottom(v) return newpath(-19, -14):curve(-8, -14, -3, -6 + v):arc(0, -6 + v, -2 * PI + 0.4) end
function KK.ENTRY.side(v) return newpath(14.5, 26):curve(13, 8, 5 - v, 3):arc(5 - v, 6, -1.5 * PI) end
KK.CHAL = {}
function KK.CHAL.top(v) return newpath(1.4, 26):to(1.4, 9):curve(1.4, -1, 8, -3):arc(8, 2 + v, 1.7 * PI):curve(3, 16, -22, 18) end
function KK.CHAL.bottom(v) return newpath(-19, -12):curve(-5, -12, 0, -1):arc(4 + v, -1, -2 * PI):curve(8, 8, 22, 14) end
function KK.CHAL.side(v) return newpath(16, 24):curve(-6, 15, -5, 2):arc(-1, 2 - v, 2 * PI):curve(2, -12, 22, -16) end
function KK.CHAL.weave(v) return newpath(-14, 26):curve(-14, 8, -4, 6):curve(6, 4, 4, -4):curve(2, -12, -8, -8):arc(-8, -4 - v, -1.5 * PI):curve(0, 8, 24, 6) end
local function M(kind, c, r) return { kind = kind, col = c, row = r } end
KK.NORMAL_GROUPS = {
    { { path = "top", mir = false, list = { M("bfly", 5, 2), M("bfly", 6, 2), M("bfly", 5, 3), M("bfly", 6, 3) } },
      { path = "top", mir = true, list = { M("bee", 5, 4), M("bee", 6, 4), M("bee", 5, 5), M("bee", 6, 5) } } },
    { { path = "bottom", mir = false, list = { M("boss", 4, 1), M("bfly", 4, 2), M("boss", 5, 1), M("bfly", 7, 2), M("boss", 6, 1), M("bfly", 4, 3), M("boss", 7, 1), M("bfly", 7, 3) } } },
    { { path = "bottom", mir = true, list = { M("bfly", 2, 2), M("bfly", 3, 2), M("bfly", 8, 2), M("bfly", 9, 2), M("bfly", 2, 3), M("bfly", 3, 3), M("bfly", 8, 3), M("bfly", 9, 3) } } },
    { { path = "side", mir = false, list = { M("bee", 7, 4), M("bee", 8, 4), M("bee", 7, 5), M("bee", 8, 5), M("bee", 9, 4), M("bee", 10, 4), M("bee", 9, 5), M("bee", 10, 5) } } },
    { { path = "side", mir = true, list = { M("bee", 4, 4), M("bee", 3, 4), M("bee", 4, 5), M("bee", 3, 5), M("bee", 2, 4), M("bee", 1, 4), M("bee", 2, 5), M("bee", 1, 5) } } },
}
local function L8(kind, n) local t = {}; for i = 1, n do t[i] = M(kind, 0, 0) end; return t end
KK.CHAL_GROUPS = {
    { { path = "top", mir = false, list = L8("bee", 4) }, { path = "top", mir = true, list = L8("bee", 4) } },
    { { path = "bottom", mir = false, list = L8("bfly", 8) } },
    { { path = "bottom", mir = true, list = L8("bfly", 8) } },
    { { path = "weave", mir = false, list = { M("boss", 0, 0), M("bee", 0, 0), M("boss", 0, 0), M("bee", 0, 0) } },
      { path = "weave", mir = true, list = { M("boss", 0, 0), M("bee", 0, 0), M("boss", 0, 0), M("bee", 0, 0) } } },
    { { path = "side", mir = false, list = L8("bee", 4) }, { path = "side", mir = true, list = L8("bee", 4) } },
}
-- challenge stages re-skin the insect templates (materials are per template)
KK.CHAL_SKIN = { bee = "cbee", bfly = "cbfly", boss = "cboss" }
local function skin(challenge)
    for kind, alt in pairs(KK.CHAL_SKIN) do
        local src = PAL[challenge and alt or kind]
        for part, p in pairs(src) do
            for _, nm in ipairs((part == "wing" or part == "wingtrim") and { "T_" .. kind .. "_" .. part, "T_" .. kind .. "_" .. part .. "R" } or { "T_" .. kind .. "_" .. part }) do
                local n = tnode(nm)
                if n then
                    mlive(n, "base_color", vec4(p[1][1], p[1][2], p[1][3], 1)); mlive(n, "emissive", vec3(p[2][1], p[2][2], p[2][3]))
                end
            end
        end
    end
end
local function spawn_stage(st)
    for i = #enemies, 1, -1 do remove_enemy(enemies[i]) end
    local chal = is_challenge(st)
    skin(chal)
    local groups = chal and KK.CHAL_GROUPS or KK.NORMAL_GROUPS
    local book = chal and KK.CHAL or KK.ENTRY
    local v = ((st - 1) % 3) * 0.8
    local fire_p = chal and 0 or clamp(0.08 + (st - 1) * 0.05, 0, 0.6)
    local gap = chal and 2.9 or 3.3
    for gi, g in ipairs(groups) do
        for _, train in ipairs(g) do
            for i, m in ipairs(train.list) do
                local e = new_enemy(m.kind, m.col, m.row)
                if e then
                    local pth = book[train.path](v)
                    if train.mir then pth:mirror() end
                    e.entry = { path = pth, after = chal and "exit" or "home" }
                    e.delay = 0.6 + (gi - 1) * gap + (i - 1) * 0.16
                    e.group = gi
                    e.chal = chal
                    e.entry_fire = rand() < fire_p
                end
            end
        end
    end
    G.chal = chal
    G.chal_hits, G.chal_total = 0, #enemies
    G.group_hits = {}
end

------------------------------------------------------------------ tractor beam
local BEAM = { on = false, len = 0, t = 0, boss = nil, rings = {} }
KK.BEAM_LEN = 14.0
local function build_beam()
    BEAM.outer = clone("T_beam", HIDE); BEAM.inner = clone("T_beam2", HIDE)
    paint(tnode("T_beam"), { 0.3, 0.6, 1.0 }, { 0.5, 1.4, 4.0 }, 0.4, 0)
    paint(tnode("T_beam2"), { 0.7, 0.9, 1.0 }, { 1.2, 2.4, 5.0 }, 0.4, 0)
    for _, nm in ipairs({ "T_beam", "T_beam2" }) do
        local n = tnode(nm)
        pcall(_mds, n, true); qpush(function() pcall(_mds, n, true) end)
    end
    for i = 0, 5 do
        BEAM.rings[i + 1] = clone("T_beamring_" .. i, HIDE)
        paint(tnode("T_beamring_" .. i), { 0.5, 0.8, 1 }, { 1, 2.5, 6 }, 0.3, 0)
    end
    BEAM.em = new_emitter({ c0 = vec4(1.0, 2.0, 4.0, 1), c1 = vec4(0.2, 0.4, 1.5, 0), count = 600, radius = 1.8,
        smin = 0.05, smax = 0.14, lmin = 0.4, lmax = 0.9, noise = 2.0, drag = 0.5, vel = vec3(0, 6, 0) })
end
local function beam_width(yfrac) return 0.45 + 2.6 * yfrac end
local function draw_beam(dt)
    local b = BEAM.boss
    if not BEAM.on or not b or not b.alive then
        if BEAM.vis then
            BEAM.vis = false
            BEAM.outer:set_position(HIDE); BEAM.inner:set_position(HIDE)
            for _, r in ipairs(BEAM.rings) do r:set_position(HIDE) end
            emitter_at(BEAM.em, 0, -1000, 0, 0); set_point(L.beam, HIDE, vec3(0, 0, 0), 0, 1)
        end
        return
    end
    BEAM.vis = true
    local x, y0 = b.x, b.y - 1.0
    local len = max(0.05, BEAM.len)
    local w = beam_width(1) * (len / KK.BEAM_LEN) ^ 0.7 + 0.3
    local wob = 1 + 0.04 * sin(G.t * 23)
    BEAM.outer:set_position(vec3(x, y0, 0)); BEAM.outer:set_scale(vec3(w * wob, len, w * wob))
    BEAM.inner:set_position(vec3(x, y0, 0)); BEAM.inner:set_scale(vec3(w * 0.55, len, w * 0.55))
    BEAM.outer:set_rotation(vec3(0, G.t * 90, 0)); BEAM.inner:set_rotation(vec3(0, -G.t * 140, 0))
    for i, r in ipairs(BEAM.rings) do
        local f = ((G.t * 0.9 + i / #BEAM.rings) % 1)
        local d = f * len
        local rw = 0.18 + (w - 0.18) * (d / len)
        r:set_position(vec3(x, y0 - d, 0)); r:set_scale(vec3(rw, 1, rw))
    end
    emitter_at(BEAM.em, x, y0 - len * 0.6, 0, 260 * min(1, len / KK.BEAM_LEN), vec3(0, 7, 0))
    set_point(L.beam, vec3(x, y0 - len * 0.5, 3), vec3(0.3, 0.6, 1.0), 110 * min(1, len / 4), 14)
end

------------------------------------------------------------------ score popups (world -> screen)
local function project(x, y, z)
    local C = cam:get_position()
    -- camera looks at origin from C; build basis
    local fx, fy, fz = -C.x, -C.y, -C.z
    local fl = sqrt(fx * fx + fy * fy + fz * fz); fx, fy, fz = fx / fl, fy / fl, fz / fl
    local rx, ry, rz = -fz, 0, fx                         -- right = f x up(0,1,0)
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

------------------------------------------------------------------ scoring
G.score, G.hiscore = 0, 20000
KK.HISAVE = "Save/hiscore.txt"
do local s = fs.read and fs.read(KK.HISAVE); local v = s and tonumber(s); if v then G.hiscore = v end end
local score_pop = 0
local function add_score(n)
    local before = G.score
    G.score = G.score + n
    score_pop = 1
    if G.score > G.hiscore and not (G.jev and G.jev:assisted()) then G.hiscore = G.score end
    -- extra fighters at 20000, 70000, then every 70000
    local nxt = G.next_extra or 20000
    if before < nxt and G.score >= nxt then
        G.lives = min(6, G.lives + 1); sfx("extra"); G.next_extra = nxt == 20000 and 70000 or nxt + 70000
        G.banner = { text = "EXTRA FIGHTER", sub = "", t = 0, dur = 1.6 }
    end
end

------------------------------------------------------------------ dives
local DIVE_SPEED = function() return 15 + min(9, (G.stage or 1) * 0.55) end
local function dive_path(e, kind, px)
    local dir = e.x < 0 and -1 or 1
    local p = newpath(e.x, e.y):arc(e.x + dir * 1.8, e.y, -dir * PI)
    local x1, y1 = p:last()
    if kind == "beam" then
        return p:curve(x1, y1 - 8, px, -3.5)
    elseif kind == "bfly" then
        local a = rr(3, 5)
        return p:curve(x1 + dir * 2, y1 - 6, px + a * dir, 0):curve(px + a * dir, -6, px - a * dir, -9):curve(px - 2 * a * dir, -16, px + rr(-2, 2), -27)
    elseif kind == "boss" or kind == "cap" then
        return p:curve(x1, y1 - 10, px + dir * 3, -6):curve(px - dir * 3, -14, px - dir * 6, -27)
    else -- bee: swoop at the player, then a late hook
        return p:curve(x1 + dir * 3, y1 - 9, px + rr(-2, 2), -8):curve(px - dir * 2, -16, px - dir * rr(4, 9), -27)
    end
end
local function start_dive(e, kind, px, lead_path)
    e.state_kind = kind
    local pth = dive_path(e, kind, px)
    set_path(e, pth, DIVE_SPEED() * (kind == "beam" and 0.85 or 1), kind == "beam" and "beam" or "wrap")
    e.diving = true; e.fire_t = rr(0.4, 1.4); e.shots = (G.stage or 1) >= 2 and (rand() < 0.5 and 2 or 1) or (rand() < 0.6 and 1 or 0)
    if kind == "beam" then e.shots = 0 end
    grab_trail(e)
    if e.captive then e.captive.diving = true; grab_trail(e.captive) end
end
local function formation_complete()
    for _, e in ipairs(enemies) do if e.state == "wait" or (e.state == "path" and not e.diving) or (e.state == "home" and not e.diving) then return false end end
    return true
end
local function count_diving() local n = 0; for _, e in ipairs(enemies) do if e.diving then n = n + 1 end end; return n end
local function launch_dive()
    local inform = {}
    for _, e in ipairs(enemies) do if e.state == "form" and not e.cap_of then inform[#inform + 1] = e end end
    if #inform == 0 then return end
    local px = P.x
    local e = inform[floor(rr(1, #inform + 0.999))]
    -- bias toward bosses once in a while, and toward the edge columns (classic)
    if rand() < 0.3 then for _, c in ipairs(inform) do if c.kind == "boss" then e = c; break end end end
    if e.kind == "boss" then
        local beam_ok = not P.dual and P.state == "alive" and not e.captive and not BEAM.boss and not G.captive_exists and G.stage >= 1 and rand() < 0.45
        if beam_ok then
            start_dive(e, "beam", clamp(px + rr(-3, 3), -FX + 3, FX - 3)); sfx("dive"); return
        end
        start_dive(e, "boss", px)
        -- escorts: up to two butterflies from the row below
        local esc = 0
        for _, c in ipairs(inform) do
            if esc < 2 and c.kind == "bfly" and c.row == 2 and abs(c.col - e.col) <= 1 and c ~= e then
                esc = esc + 1; c.escort_of = e
                local ox = c.x - e.x
                start_dive(c, "boss", px + ox)
            end
        end
        e.escorts = esc
    else
        start_dive(e, e.kind, px)
        -- bees sometimes go in pairs
        if e.kind == "bee" and rand() < 0.35 then
            for _, c in ipairs(inform) do
                if c ~= e and c.kind == "bee" and c.row == e.row and abs(c.col - e.col) == 1 then start_dive(c, "bee", px + (c.x - e.x)); break end
            end
        end
    end
    sfx("dive")
end

------------------------------------------------------------------ banner
G.banner = { text = "", sub = "", t = 9, dur = 1 }
local function show_banner(t, s, d) G.banner = { text = t, sub = s or "", t = 0, dur = d or 2 } end

------------------------------------------------------------------ enemy death / capture logic
KK.KCOL = { bee = { { 1, .8, .2 }, 0 }, bfly = { { 1, .2, .25 }, 1 }, boss = { { .3, 1, .5 }, 3 }, cap = { { 1, .3, .3 }, 1 } }
local function player_lost_ship(captured)
    P.state = captured and "lost" or "dead"
    P.dual = false
    G.respawn_t = 0
end
local function hit_enemy(e)
    if not e.alive then return end
    if e.kind == "boss" and e.hp > 1 then
        e.hp = e.hp - 1; ship_damaged(e.ship, true); sfx("bosshit")
        sparks(e.x, e.y, { .5, .6, 1 }, 40, 22); flash(e.x, e.y, { .5, .5, 1 }, 40, 0.2, 8); e.hitflash = 1
        return
    end
    local c = KK.KCOL[e.kind]
    local col, slot = c[1], c[2]
    if e.kind == "boss" and e.dmg then col, slot = { .5, .4, 1 }, 5 end
    local big = e.kind == "boss" or e.kind == "cap"
    explode(e.x, e.y, col, slot, big)
    sfx(big and "boom" or "hit")
    local pts
    if e.chal then
        pts = 100
        G.chal_hits = G.chal_hits + 1
        G.group_hits[e.group] = (G.group_hits[e.group] or 0) + 1
        if G.group_hits[e.group] == 8 then
            local bonus = ({ 1000, 1000, 1500, 1500, 2000, 2000, 3000 })[min(7, floor((G.stage + 1) / 4))] or 3000
            pts = pts + bonus; popup(e.x, e.y + 1.5, tostring(bonus), { 1, .9, .3 })
        end
    elseif e.kind == "boss" and e.diving then
        local esc = 0
        for _, o in ipairs(enemies) do if o.escort_of == e and o.alive and o.diving then esc = esc + 1 end end
        pts = esc == 2 and 1600 or (esc == 1 and 800 or 400)
        popup(e.x, e.y + 1.5, tostring(pts), esc > 0 and { 1, .5, 1 } or { 1, 1, 1 })
    else
        pts = KK.POINTS[e.kind][e.diving and 2 or 1]
        if e.kind == "cap" then popup(e.x, e.y + 1.5, tostring(pts), { 1, .4, .4 }) end
    end
    add_score(pts)
    if e.kind == "cap" then G.captive_exists = false end
    -- the boss carried a captured fighter
    local cpt = e.captive
    if cpt and cpt.alive then
        cpt.cap_of = nil
        if e.state ~= "form" and e.state ~= "home" then
            cpt.state = "rescue"; cpt.t = 0; cpt.diving = false; sfx("release")
            show_banner("FIGHTER RESCUED", "", 1.6)
        else
            cpt.state = "form"; cpt.hostile = true; cpt.col, cpt.row = e.col, e.row; cpt.diving = false; drop_trail(cpt)
        end
    end
    if BEAM.boss == e then
        BEAM.on = false; BEAM.boss = nil
        if P.state == "captured" then P.state = "alive"; P.cap_t = nil end
    end
    remove_enemy(e)
end

local function enemy_fire_logic(e, dt)
    if (e.shots or 0) <= 0 or P.state ~= "alive" then return end
    e.fire_t = e.fire_t - dt
    if e.fire_t <= 0 and e.y > PLAYER_Y + 8 and e.y < 13 and abs(e.x) < FX then
        fire_enemy(e.x, e.y - 0.8, P.x + rr(-1.5, 1.5)); e.shots = e.shots - 1; e.fire_t = rr(0.25, 0.7)
    end
end
local function cap_slot(e)
    local x, y = slot_pos(e.col, e.row); return x, y + 2.4
end
local function update_enemy(e, dt)
    e.t = (e.t or 0) + dt
    local thd = e.hd
    local st = e.state
    if st == "wait" then
        e.delay = e.delay - dt
        if e.delay <= 0 then
            set_path(e, e.entry.path, e.chal and 21 or 20, e.entry.after); grab_trail(e)
            if e.entry_fire then e.shots = 1; e.fire_t = rr(0.6, 1.6) end
            st = "path"
        else
            ship_visible(e.ship, false); return
        end
    end
    ship_visible(e.ship, true)
    if st == "path" then
        e.d = e.d + e.speed * dt
        local x, y, dx, dy = e.path:at(e.d)
        e.x, e.y = x, y
        if dx * dx + dy * dy > 1e-6 then thd = angle_to(dx, dy) end
        enemy_fire_logic(e, dt)
        if e.d >= e.path.total then
            local a = e.after
            if a == "home" then e.state = "home"
            elseif a == "exit" then remove_enemy(e); return
            elseif a == "wrap" then
                local sx = (e.kind == "cap" and e.hostile) and cap_slot(e) or enemy_slot(e)
                e.x, e.y = sx, FY + 5; e.state = "home"
                if e.captive then e.captive.x, e.captive.y = sx, FY + 7.5 end
            elseif a == "beam" then
                e.state = "beam"; BEAM.boss = e; BEAM.on = true; BEAM.t = 0; BEAM.len = 0; BEAM.captured = false; sfx("beam")
            end
        end
    elseif st == "home" then
        local sx, sy
        if e.kind == "cap" and e.hostile then sx, sy = cap_slot(e) else sx, sy = enemy_slot(e) end
        local dx, dy = sx - e.x, sy - e.y
        local dist = sqrt(dx * dx + dy * dy)
        local sp = 17
        if dist < 0.25 then
            e.state = "form"; e.diving = false; e.escort_of = nil; drop_trail(e); e.x, e.y = sx, sy
            if e.captive then e.captive.diving = false; drop_trail(e.captive) end
        else
            local step = min(dist, sp * dt * clamp(dist / 1.5, 0.35, 1))
            e.x, e.y = e.x + dx / dist * step, e.y + dy / dist * step
            thd = dist > 1.2 and angle_to(dx, dy) or 180
        end
    elseif st == "form" then
        if e.kind == "cap" and e.hostile then e.x, e.y = cap_slot(e) else e.x, e.y = enemy_slot(e) end
        thd = 180
    elseif st == "beam" then
        thd = 180
    elseif st == "attached" then
        local b = e.cap_of
        if not b or not b.alive then e.state = "rescue"; e.t = 0 else
            local h = math.rad(b.hd)
            e.x, e.y = b.x - (-sin(h)) * 2.4, b.y - cos(h) * 2.4
            thd = b.hd
        end
    elseif st == "rescue" then
        -- released fighter: spin, then glide down to dock beside the player (or become the player's ship)
        e.t = e.t + 0
        thd = e.hd + 720 * dt
        if e.t > 1.0 then
            local tx = (P.state == "alive") and (P.x + 2 * DUAL_OFF) or 0
            tx = clamp(tx, -FX + 1.3, FX - 1.3)
            local dx, dy = tx - e.x, PLAYER_Y - e.y
            local dist = sqrt(dx * dx + dy * dy)
            P.frozen = true
            if dist < 0.3 then
                if P.state == "alive" then
                    P.dual = true; P.x = clamp(P.x + DUAL_OFF, -FX + 2.2, FX - 2.2)
                else
                    P.state = "alive"; P.x = 0; P.inv = 1.5
                end
                P.frozen = false; G.captive_exists = false
                sfx("rescue"); show_banner("DUAL FIGHTER", "", 1.6)
                flash(e.x, e.y, { .5, .8, 1 }, 80, 0.5, 12); sparks(e.x, e.y, { .5, .8, 1 }, 60, 20)
                remove_enemy(e); return
            end
            local step = min(dist, 13 * dt)
            e.x, e.y = e.x + dx / dist * step, e.y + dy / dist * step
            if dist < 3 then thd = 0 end
        end
    end
    -- heading / bank smoothing
    local prev = e.hd
    e.hd = turn_toward(e.hd, thd, st == "rescue" and 30 or 12, dt)
    local dh = ((e.hd - prev + 540) % 360 - 180) / max(dt, 1e-4)
    e.bank = damp(e.bank, clamp(-dh * 0.12, -40, 40), 8, dt)
    -- flap + render
    local k = e.kind
    local fl = (k == "boss" and 18 or 26) * sin(e.t * ((e.diving or st == "path") and 22 or 11) + e.ph)
    local sc = KK.SCALE[k] * (1 + 0.25 * (e.hitflash or 0))
    e.hitflash = max(0, (e.hitflash or 0) - dt * 5)
    local z = (st == "form") and 0 or 0.8
    local hd = e.hd
    if k == "cap" then hd = (st == "attached" or st == "form" or st == "home") and (e.hd) or e.hd end
    place_ship(e.ship, e.x, e.y, z, hd, e.bank, sc, fl)
    if e.trail then
        local h = math.rad(e.hd)
        emitter_at(e.trail.em, e.x + sin(h) * 1.0, e.y - cos(h) * 1.0, z, 80, vec3(sin(h) * 4, -cos(h) * 4, 0))
    end
end

local function update_beam(dt)
    local b = BEAM.boss
    if not BEAM.on or not b then return end
    if not b.alive then BEAM.on = false; BEAM.boss = nil; return end
    BEAM.t = BEAM.t + dt
    local t = BEAM.t
    local hold_end = BEAM.captured and (BEAM.cap_end or 99) or 3.8
    if t < 0.9 then BEAM.len = KK.BEAM_LEN * (t / 0.9) ^ 0.8
    elseif t < hold_end then BEAM.len = KK.BEAM_LEN
    else BEAM.len = max(0, BEAM.len - dt * KK.BEAM_LEN * 1.6) end
    -- capture test
    if not BEAM.captured and P.state == "alive" and not P.dual and BEAM.len > KK.BEAM_LEN * 0.85 and abs(P.x - b.x) < beam_width(1) * 0.7 and P.inv <= 0 then
        BEAM.captured = true; BEAM.cap_end = t + 2.0
        P.state = "captured"; P.cap_t = 0; P.cx, P.cy = P.x, PLAYER_Y; P.dual = false
        sfx("captured")
    end
    if P.state == "captured" then
        P.cap_t = P.cap_t + dt
        local k = clamp(P.cap_t / 1.9, 0, 1)
        local e = k * k * (3 - 2 * k)
        P.cx = lerp(P.x, b.x, e); P.cy = lerp(PLAYER_Y, b.y - 2.4, e)
        if k >= 1 then
            local c = new_enemy("cap", b.col, b.row)
            if c then
                c.state = "attached"; c.cap_of = b; c.x, c.y, c.hd = b.x, b.y - 2.4, 180; b.captive = c; G.captive_exists = true
            end
            player_lost_ship(true)
            show_banner("FIGHTER CAPTURED", "", 2.0)
        end
    end
    if t >= hold_end and BEAM.len <= 0 then
        BEAM.on = false; BEAM.boss = nil
        b.state = "home"; b.diving = true
    end
end

------------------------------------------------------------------ player update
local function player_hit(xhit)
    -- dual fighter loses only the half that was hit
    if P.dual then
        P.dual = false
        local other = (xhit < P.x) and (P.x + DUAL_OFF) or (P.x - DUAL_OFF)
        explode(xhit, PLAYER_Y, { .6, .8, 1 }, 4, true); sfx("death")
        P.x = other; P.inv = 1.0
        return
    end
    explode(P.x, PLAYER_Y, { .6, .8, 1 }, 4, true)
    burst(P.x, PLAYER_Y, { c0 = vec4(5, 5, 6, 1), c1 = vec4(0.2, 0.4, 1.5, 0), count = 120, smin = 0.08, smax = 0.25, lmin = 0.4, lmax = 1.2,
        radius = 0.4, spread = 30, drag = 1.2 })
    sfx("death"); add_shake(0.9)
    player_lost_ship(false)
end
local function draw_player(dt)
    local alive = P.state == "alive"
    local s1, s2 = P.ships[1], P.ships[2]
    local blink = P.inv > 0 and (floor(G.t * 16) % 2 == 0)
    if P.state == "captured" then
        ship_visible(s1, true); ship_visible(s2, false)
        place_ship(s1, P.cx, P.cy, 0.5, (P.cap_t or 0) * 900, 0, 0.9)
        emitter_at(P.em[1], 0, -1000, 0, 0); emitter_at(P.em[2], 0, -1000, 0, 0)
        set_point(L.player, vec3(P.cx, P.cy, 2), vec3(1, 0.3, 0.3), 30, 6)
        return
    end
    if not alive or blink then
        ship_visible(s1, false); ship_visible(s2, false)
        emitter_at(P.em[1], 0, -1000, 0, 0); emitter_at(P.em[2], 0, -1000, 0, 0)
        if not alive then set_point(L.player, HIDE, vec3(0, 0, 0), 0, 1) end
        return
    end
    local pts = player_points()
    for i = 1, 2 do
        local s = P.ships[i]
        local x = pts[i]
        if x then
            ship_visible(s, true)
            local bob = sin(G.t * 3 + i) * 0.08
            place_ship(s, x, PLAYER_Y + bob, 0.4, 0, P.bank, 0.9)
            emitter_at(P.em[i], x, PLAYER_Y - 1.25, 0.4, 140, vec3(-P.vx * 0.1, -10, 0))
        else
            ship_visible(s, false); emitter_at(P.em[i], 0, -1000, 0, 0)
        end
    end
    set_point(L.player, vec3(P.x, PLAYER_Y + 0.5, 3), vec3(0.4, 0.75, 1.0), 40, 9)
end

------------------------------------------------------------------ bolts + collisions
local function update_bolts(dt)
    for _, b in ipairs(BOLTS) do
        if b.used then
            b.y = b.y + 52 * dt
            local hit = false
            for _, e in ipairs(enemies) do
                if e.alive and e.state ~= "wait" and e.state ~= "rescue" then
                    local r = KK.RADIUS[e.kind]
                    if abs(e.x - b.x) < r and abs(e.y - b.y) < r + 0.5 then hit_enemy(e); hit = true; G.hits = (G.hits or 0) + 1; break end
                end
            end
            if hit or b.y > FY + 2 then b.used = false; b.node:set_position(HIDE)
            else b.node:set_position(vec3(b.x, b.y, 0.4)); b.node:set_scale(vec3(1.1, 1.1, 1.1)) end
        end
    end
    local pts = (P.state == "alive" and P.inv <= 0) and player_points() or {}
    for _, b in ipairs(EBOLTS) do
        if b.used then
            b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
            local hit = false
            for _, x in ipairs(pts) do
                if abs(b.x - x) < 0.75 and abs(b.y - PLAYER_Y) < 0.9 then hit = true; player_hit(x); break end
            end
            if hit or b.y < -FY - 2 then b.used = false; b.node:set_position(HIDE)
            else
                b.node:set_position(vec3(b.x, b.y, 0.4))
                b.node:set_rotation(vec3(0, G.t * 400, math.deg(atan2(-b.vx, b.vy))))
            end
        end
    end
    -- ramming
    if P.state == "alive" and P.inv <= 0 then
        for _, e in ipairs(enemies) do
            if e.alive and (e.state == "path" or e.state == "home") and e.y < PLAYER_Y + 3 then
                for _, x in ipairs(player_points()) do
                    if abs(e.x - x) < KK.RADIUS[e.kind] * 0.75 + 0.6 and abs(e.y - PLAYER_Y) < 1.3 then
                        hit_enemy(e); if e.alive then hit_enemy(e) end
                        player_hit(x); break
                    end
                end
                if P.state ~= "alive" then break end
            end
        end
    end
end
local function clear_bolts()
    for _, b in ipairs(BOLTS) do b.used = false; b.node:set_position(HIDE) end
    for _, b in ipairs(EBOLTS) do b.used = false; b.node:set_position(HIDE) end
end

------------------------------------------------------------------ stage badges (1 / 5 / 10 / 20 / 30 / 50 pennants) + reserve ships
KK.BADGE = { { v = 50, flag = { 1, .85, .2 }, stripe = { 1, .2, .2 }, s = 1.25, n = 6 }, { v = 30, flag = { .2, 1, .5 }, stripe = { 1, 1, 1 }, s = 1.15, n = 1 },
    { v = 20, flag = { 1, .3, .9 }, stripe = { 1, .9, .3 }, s = 1.1, n = 1 }, { v = 10, flag = { .25, .5, 1 }, stripe = { 1, .85, .2 }, s = 1.05, n = 1 },
    { v = 5, flag = { 1, 1, 1 }, stripe = { 1, .15, .15 }, s = 0.95, n = 1 }, { v = 1, flag = { 1, .15, .2 }, stripe = { 1, .9, .3 }, s = 0.75, n = 4 } }
local BADGES = {}
local function build_badges()
    paint(tnode("T_badge_pole"), { .8, .8, .85 }, { .3, .3, .35 }, .2, .9)
    for i, b in ipairs(KK.BADGE) do
        local f, s = tnode("T_flag_" .. (i - 1)), tnode("T_stripe_" .. (i - 1))
        paint(f, b.flag, { b.flag[1] * 1.6, b.flag[2] * 1.6, b.flag[3] * 1.6 }, .3, .1)
        paint(s, b.stripe, { b.stripe[1] * 2.5, b.stripe[2] * 2.5, b.stripe[3] * 2.5 }, .3, .1)
        b.pool = {}
        for k = 1, b.n do
            local root = scene.add_empty_node("badge" .. i .. "_" .. k); root:set_position(HIDE)
            clone("T_badge_pole", vec3(0, 0, 0), nil, root); clone("T_flag_" .. (i - 1), vec3(0, 0, 0), nil, root); clone("T_stripe_" .. (i - 1), vec3(0, 0, 0), nil, root)
            b.pool[k] = root
        end
    end
end
-- shown: number of badge units revealed so far (count-up at stage start)
local function badge_list(stage)
    local out, r = {}, stage
    for i, b in ipairs(KK.BADGE) do
        while r >= b.v and #out < 14 do
            local used = 0; for _, o in ipairs(out) do if o.i == i then used = used + 1 end end
            if used >= b.n then break end
            out[#out + 1] = { i = i }; r = r - b.v
        end
    end
    return out
end
local function draw_badges(stage, shown)
    for _, b in ipairs(KK.BADGE) do for _, n in ipairs(b.pool) do n:set_position(HIDE) end end
    if not stage or stage < 1 then return end
    local list = badge_list(stage)
    local used = {}
    local x = FX - 0.6
    for k = #list, 1, -1 do
        local o = list[k]
        if k <= shown then
            local b = KK.BADGE[o.i]
            used[o.i] = (used[o.i] or 0) + 1
            local n = b.pool[used[o.i]]
            local pop = (k == shown) and (G.badge_pop or 0) or 0
            local bs = b.s * 1.5
            n:set_position(vec3(x - 0.5, -FY + 1.0 * bs, 0.5)); n:set_scale(vec3(bs * (1 + pop), bs * (1 + pop), bs))
            n:set_rotation(vec3(0, 20 * sin(G.t * 2 + k), 0))
        end
        x = x - 1.35 * KK.BADGE[o.i].s
    end
end
local function draw_icons(n)
    for i, s in ipairs(P.icons) do
        if i <= n and G.state ~= "title" then
            ship_visible(s, true); place_ship(s, -FX + 0.9 + (i - 1) * 1.55, -FY + 0.9, 0.3, 0, 15 * sin(G.t * 2 + i), 0.55)
        else ship_visible(s, false) end
    end
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
        panel("mi_bg" .. i, x, y, w, h, v, sel and { 0.9, 0.15, 0.3, 0.38 } or { 0.02, 0.02, 0.08, 0.6 },
            sel and { 1, 0.5, 0.6, 0.95 } or { 0.3, 0.5, 1.0, 0.45 }, 20, true)
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
    -- field edge in screen space -> side panels hug the playfield
    local fxl = project(-FX, 0, 0)
    local pw = max(160 * s, fxl - 40 * s)
    local blink = floor(G.t * 2.5) % 2 == 0
    text("up", "1UP", 30 * s, 60 * s, pw, 50 * s, 1.5 * s, (st == "play" and blink) and { 1, .3, .3, 0.35 } or KK.RED, "left", play)
    text("score", tostring(G.score), 30 * s, 105 * s, pw, 80 * s, (2.6 + 0.4 * score_pop) * s, KK.WHITE, "left", play)
    text("hi_t", "HIGH SCORE", 30 * s, 210 * s, pw, 50 * s, 1.2 * s, KK.RED, "left", play or title)
    text("hi", tostring(G.hiscore), 30 * s, 250 * s, pw, 70 * s, 2.0 * s, KK.GOLD, "left", play or title)
    local rx = SW - 30 * s - pw
    text("stage_t", "STAGE", rx, 60 * s, pw, 50 * s, 1.3 * s, KK.CYAN, "right", play)
    text("stage", tostring(G.stage or 1), rx, 105 * s, pw, 80 * s, 2.6 * s, KK.WHITE, "right", play)
    text("ratio_t", "HIT RATIO", rx, 210 * s, pw, 50 * s, 1.1 * s, KK.CYAN, "right", play)
    local ratio = (G.shots or 0) > 0 and string.format("%.1f %%", 100 * (G.hits or 0) / G.shots) or "-"
    text("ratio", ratio, rx, 250 * s, pw, 60 * s, 1.6 * s, { .8, .9, 1, 1 }, "right", play)
    text("dual", P.dual and "DUAL FIGHTER" or (G.captive_exists and "FIGHTER CAPTURED" or ""), rx, 330 * s, pw, 50 * s, 1.1 * s,
        P.dual and KK.GOLD or { 1, .4, .4, 0.6 + 0.4 * sin(G.t * 6) }, "right", play)
    text("ctl_hint", "ARROWS / A D / MOUSE  MOVE\nSPACE / CLICK  FIRE\nESC  PAUSE   M  MUTE", rx, SH - 190 * s, pw, 140 * s, 0.85 * s, { .6, .7, .9, .7 }, "right", play)
    -- banner
    local b = G.banner
    b.t = b.t + dt
    local bvis = b.t < b.dur and play
    local ba = bvis and min(1, b.t * 6, (b.dur - b.t) * 3) or 0
    local bs = 1 + 0.2 * max(0, 1 - b.t * 5)
    text("banner", b.text, 0, SH * 0.44, SW, 100 * s, 2.8 * s * bs, { 1, .3, .35, ba }, "center", bvis)
    text("banner2", b.sub, 0, SH * 0.44 + 90 * s, SW, 60 * s, 1.6 * s, { .5, .9, 1, ba }, "center", bvis and b.sub ~= "")
    -- popups
    for i = 1, 6 do
        local p = POPS[i]
        if p then
            p.t = p.t + dt
            local sx, sy = project(p.x, p.y + p.t * 1.5, 0)
            local a = clamp(1.6 - p.t, 0, 1)
            text("pop" .. i, p.txt, sx - 100 * s, sy - 25 * s, 200 * s, 50 * s, 1.4 * s, { p.col[1], p.col[2], p.col[3], a }, "center", a > 0)
        else text("pop" .. i, "", 0, 0, 10, 10, 1, KK.NONE, "center", false) end
    end
    for i = #POPS, 1, -1 do if POPS[i].t > 1.6 then table.remove(POPS, i) end end
    -- title
    text("title", "Galaga", 0, SH * 0.06, SW, 200 * s, 6.5 * s, { 0.4 + 0.2 * sin(G.t * 2), 0.85, 1, 1 }, "center", title)
    text("title2", "Remix", 0, SH * 0.22, SW, 80 * s, 2.4 * s, { 1, .3, .45, 1 }, "center", title)
    local tx = SW * 0.5 + 10 * s
    text("tt0", "-- SCORE --", 0, SH * 0.31, SW, 50 * s, 1.3 * s, KK.CYAN, "center", title)
    text("tt1", "50 / 100", tx, SH * 0.36, 400 * s, 60 * s, 1.5 * s, KK.GOLD, "left", title)
    text("tt2", "80 / 160", tx, SH * 0.44, 400 * s, 60 * s, 1.5 * s, KK.GOLD, "left", title)
    text("tt3", "150 / 400 - 1600", tx, SH * 0.52, 400 * s, 60 * s, 1.5 * s, KK.GOLD, "left", title)
    text("ttn", "IN FORMATION / DIVING", 0, SH * 0.585, SW, 40 * s, 0.9 * s, { .7, .8, 1, .8 }, "center", title)
    text("ctl", "ARROWS / A D or MOUSE  MOVE      SPACE / CLICK  FIRE (HOLD = AUTO)      ESC  PAUSE      M  MUTE",
        0, SH * 0.93, SW, 50 * s, 1.0 * s, { .7, .85, 1, .85 }, "center", title)
    text("hint", "LET A BOSS GALAGA CAPTURE YOUR FIGHTER, THEN SHOOT THE BOSS TO RESCUE IT FOR A DUAL FIGHTER",
        0, SH * 0.96, SW, 40 * s, 0.85 * s, { 1, .6, .7, .8 }, "center", title)
    -- pause / game over
    local pause = st == "paused"
    local over = st == "over"
    panel("dim", 0, 0, SW, SH, pause or over, { 0, 0, 0.02, 0.55 }, KK.NONE, 2)
    text("pause", "PAUSED", 0, SH * 0.24, SW, 140 * s, 4.0 * s, KK.CYAN, "center", pause)
    text("over", "GAME  OVER", 0, SH * 0.14, SW, 150 * s, 4.6 * s, KK.RED, "center", over)
    local res = string.format("SHOTS FIRED  %d\nNUMBER OF HITS  %d\nHIT-MISS RATIO  %.1f %%", G.shots or 0, G.hits or 0,
        (G.shots or 0) > 0 and 100 * (G.hits or 0) / G.shots or 0)
    text("over2", (G.newhi and "NEW HIGH SCORE  " or "SCORE  ") .. G.score, 0, SH * 0.29, SW, 70 * s, 2.0 * s, KK.GOLD, "center", over)
    text("over3", res, 0, SH * 0.36, SW, 170 * s, 1.3 * s, { .7, .9, 1, 1 }, "center", over)
    draw_menu(title or pause or over, title and SH * 0.64 or SH * 0.56)
end

------------------------------------------------------------------ settings menu (shared module)
local SET = nil
do
    local src = fs.read("Scripts/Lib/settings_menu.lua")
    if src then
        local ok, mod = pcall(function() return load(src, "@settings_menu.lua")() end)
        if ok and mod then
            local ok2, s = pcall(mod.new, { title = "SETTINGS", file = "Save/settings.cfg", click = function() sfx("click") end,
                music = false, defaults = { master = 0.5 }, theme = { accent = { 0.4, 0.85, 1, 1 }, accent2 = { 1, 0.3, 0.45, 1 } } })
            if ok2 then SET = s else pe_log("[Galaga] settings menu init failed: " .. tostring(s)) end
        else pe_log("[Galaga] settings menu load failed: " .. tostring(mod)) end
    end
end

------------------------------------------------------------------ input
local prev = {}
G.vkeys = {}
local function kdown(k) if G.vkeys[k] then return true end local ok, r = pcall(input.is_key_down_raw, k); return ok and r end
local function pressed(k) local d = kdown(k); local p = prev[k]; prev[k] = d; return d and not p end
local WATCH = { "Left", "Right", "A", "D", "Up", "Down", "W", "S", "Space", "Return", "Escape", "P", "M" }
local function latch() for _, k in ipairs(WATCH) do prev[k] = kdown(k) end end
local mouse_prev_down, mouse_last = false, nil
local function mouse_down() local ok, d = pcall(input.is_left_mouse_down); return (ok and d) or G.vkeys.Click end
local function mouse_clicked() local d = mouse_down(); local c = d and not mouse_prev_down; mouse_prev_down = d; return c end
local function mouse_world_x(mx)
    -- invert the projection on the player line
    local x0 = project(-FX, PLAYER_Y, 0.4); local x1 = project(FX, PLAYER_Y, 0.4)
    return -FX + (mx - x0) / max(1, x1 - x0) * 2 * FX
end

------------------------------------------------------------------ title showcase ships
local SHOW = {}
local function build_showcase() SHOW = { make_ship("bee"), make_ship("bfly"), make_ship("boss"), make_ship("fighter") } end
local function screen_to_world(sx, sy)
    local x0, y0 = project(-FX, -FY, 0); local x1, y1 = project(FX, FY, 0)
    return -FX + (sx - x0) / (x1 - x0) * 2 * FX, -FY + (sy - y0) / (y1 - y0) * 2 * FY
end
local function draw_showcase(vis)
    local s = SH / 1080
    for i, sh in ipairs(SHOW) do
        if vis then
            ship_visible(sh, true)
            if i <= 3 then
                local wx, wy = screen_to_world(SW * 0.5 - 70 * s, SH * (0.36 + 0.08 * (i - 1)) + 30 * s)
                place_ship(sh, wx, wy, 4, 180 + 25 * sin(G.t * 1.3 + i), 20 * sin(G.t * 1.7 + i), 1.25, 24 * sin(G.t * 10 + i))
            else
                local wx, wy = screen_to_world(SW * 0.5, SH * 0.88)
                place_ship(sh, wx + 6 * sin(G.t * 0.6), wy, 2, 0, -25 * cos(G.t * 0.6), 1.3)
            end
        else ship_visible(sh, false) end
    end
end

------------------------------------------------------------------ autopilot (attract / automation)
local function auto_target()
    local tx, best = P.x, 1e9
    for _, e in ipairs(enemies) do
        if e.alive and e.state ~= "wait" and e.state ~= "rescue" and e.state ~= "attached" then
            local sc = (e.diving and 0 or 12) + abs(e.x - P.x) * 0.4 + (e.y > 16 and 20 or 0)
            if (e.kind == "cap") then sc = sc + 30 end
            if sc < best then best, tx = sc, e.x + (e.diving and (e.x - (e.px or e.x)) * 6 or 0) end
            e.px = e.x
        end
    end
    -- rescue: park under a boss that carries our fighter? keep it simple: avoid beams unless asked
    if BEAM.on and BEAM.boss and not G.auto_capture then
        local bx = BEAM.boss.x
        if abs(tx - bx) < 4.5 then tx = bx + (P.x > bx and 5 or -5) end
    elseif BEAM.on and BEAM.boss and G.auto_capture then tx = BEAM.boss.x end
    for _, b in ipairs(EBOLTS) do
        if b.used and b.y > PLAYER_Y - 1 and b.y < PLAYER_Y + 10 then
            local bx = b.x + b.vx * (b.y - PLAYER_Y) / -b.vy
            if abs(bx - tx) < 1.8 then tx = bx + (bx > P.x and -2.6 or 2.6) end
        end
    end
    for _, e in ipairs(enemies) do
        if e.alive and e.diving and e.y < PLAYER_Y + 5 and abs(e.x - tx) < 2.2 then tx = e.x + (e.x > P.x and -3 or 3) end
    end
    return tx
end

------------------------------------------------------------------ player control
local function update_player(dt, control)
    P.inv = max(0, P.inv - dt)
    if P.state ~= "alive" then return end
    local lim = FX - (P.dual and 2.2 or 1.3)
    local target = nil
    if P.frozen then target = P.x
    elseif control == "auto" then target = auto_target()
    elseif control == "player" then
        local ok, mp = pcall(input.get_mouse_position)
        if ok and mp and mp.x then
            if mouse_last and (abs(mp.x - mouse_last.x) + abs(mp.y - mouse_last.y)) > 0.5 then G.use_mouse = true end
            mouse_last = { x = mp.x, y = mp.y }
        end
        local kx = ((kdown("Right") or kdown("D")) and 1 or 0) - ((kdown("Left") or kdown("A")) and 1 or 0)
        if kx ~= 0 then
            G.use_mouse = false
            P.vx = damp(P.vx, kx * 24, 16, dt)
        elseif G.use_mouse and mp and mp.x then
            target = mouse_world_x(mp.x)
        else
            P.vx = damp(P.vx, 0, 18, dt)
        end
    end
    if target then
        target = clamp(target, -lim, lim)
        local want = clamp((target - P.x) * 9, -24, 24)
        P.vx = damp(P.vx, want, 20, dt)
    end
    P.x = clamp(P.x + P.vx * dt, -lim, lim)
    if abs(P.x) >= lim then P.vx = 0 end
    P.bank = damp(P.bank, clamp(P.vx * 1.6, -35, 35), 10, dt)
    -- fire
    P.fire_cd = max(0, P.fire_cd - dt)
    local want_fire
    if control == "auto" then want_fire = true
    elseif control == "player" then want_fire = G.click or pressed("Space") or ((kdown("Space") or mouse_down()) and P.fire_cd <= 0) end
    if want_fire and not P.frozen and P.fire_cd <= 0 then
        if fire_player() then P.fire_cd = 0.2; G.shots = (G.shots or 0) + (P.dual and 2 or 1) end
    end
end

------------------------------------------------------------------ game flow
local function reset_actors()
    for i = #enemies, 1, -1 do remove_enemy(enemies[i]) end
    clear_bolts(); BEAM.on = false; BEAM.boss = nil; G.captive_exists = false; P.frozen = false
end
local function start_stage(st)
    G.stage = st
    clear_bolts(); BEAM.on = false; BEAM.boss = nil
    spawn_stage(st)
    G.state = "intro"; G.intro_t = 0; G.badge_shown = 0; G.badge_t = 0
    G.intro_len = (st == 1) and 3.4 or 2.3
    if is_challenge(st) then show_banner("CHALLENGING STAGE", "", G.intro_len); sfx("challenge")
    else show_banner("STAGE " .. st, st == 1 and "PLAYER 1" or "", G.intro_len); if st == 1 then sfx("start") end end
    G.dive_t = 3.0
    FORM.t, FORM.bt = 0, 0
end
local function new_game()
    reset_actors()
    G.score, G.lives, G.next_extra, G.shots, G.hits, G.newhi = 0, 2, 20000, 0, 0, false
    P.state, P.x, P.vx, P.dual, P.inv = "alive", 0, 0, false, 1.0
    runtime_ui.show(HUD)
    start_stage(1)
end
local function to_title()
    reset_actors()
    G.state = "title"; P.state = "none"; G.stage = 0
    set_menu({ { label = "PLAY", act = "play" }, { label = "Jev", act = "jev" }, { label = "SETTINGS", act = "settings" }, { label = "QUIT", act = "quit" } })
end
local function game_over()
    G.state = "over"; sfx("gameover")
    local assisted = G.jev and G.jev:assisted()
    G.newhi = not assisted and G.score > 0 and G.score >= G.hiscore
    if not assisted then pcall(fs.write, KK.HISAVE, tostring(G.hiscore)) end
    set_menu({ { label = "PLAY AGAIN", act = "play" }, { label = "TITLE", act = "title" } })
end
local function do_menu_action(act)
    sfx("click")
    if act == "play" then
        G.jev:begin_human()
        new_game()
    elseif act == "jev" then
        if not G.jev:start() then
            local err = G.jev:error() or "Jev failed to start"
            pe_log("[Galaga] " .. err)
            show_banner("JEV", err, 4)
        end
    elseif act == "resume" then G.state = G.paused_from or "play"
    elseif act == "settings" then if SET then G.in_settings = true; SET:open(function() G.in_settings = false end) end
    elseif act == "title" then to_title()
    elseif act == "quit" then
        if not (G.jev and G.jev:assisted()) then pcall(fs.write, KK.HISAVE, tostring(G.hiscore)) end
        pcall(engine.quit)
    end
end

local function update_enemies(dt)
    local complete = formation_complete()
    update_formation(dt, complete and not G.chal)
    for i = #enemies, 1, -1 do local e = enemies[i]; if e and e.alive then update_enemy(e, dt) end end
    return complete
end
local function any_rescue() for _, e in ipairs(enemies) do if e.state == "rescue" then return true end end; return false end
local function play_tick(dt, control)
    update_player(dt, control)
    local complete = update_enemies(dt)
    update_beam(dt)
    update_bolts(dt)
    -- dive scheduler
    if not G.chal and complete and P.state == "alive" and not P.frozen then
        G.dive_t = G.dive_t - dt
        local left = #enemies
        if G.dive_t <= 0 then
            local maxd = min(2 + floor(G.stage / 3), 6) + (left <= 8 and 2 or 0)
            if count_diving() < maxd then launch_dive() end
            G.dive_t = max(0.55, 2.4 - G.stage * 0.12) * rr(0.7, 1.3) * (left <= 8 and 0.55 or 1)
        end
    end
    -- respawn after losing a fighter
    if P.state == "dead" or P.state == "lost" then
        G.respawn_t = G.respawn_t + dt
        if (G.respawn_t > 2.2 and count_diving() == 0 and not BEAM.on and not any_rescue()) or G.respawn_t > 9 then
            if P.state ~= "alive" then
                if G.lives > 0 then
                    G.lives = G.lives - 1
                    P.state, P.x, P.vx, P.inv = "alive", 0, 0, 2.0
                    show_banner("READY", "", 1.4)
                else
                    game_over(); return
                end
            end
        end
    end
    -- stage end
    if #enemies == 0 and G.state == "play" and P.state ~= "captured" then
        if G.chal then
            G.state = "chal_result"; G.res_t = 0
            local n = G.chal_hits
            if n >= G.chal_total then sfx("perfect"); add_score(10000); show_banner("PERFECT !", "SPECIAL BONUS 10000 PTS", 4.0)
            else add_score(n * 100); show_banner("NUMBER OF HITS  " .. n, "BONUS  " .. (n * 100), 4.0) end
        else
            G.state = "clear"; G.clear_t = 0
        end
    end
end

------------------------------------------------------------------ visuals tick
local function update_visuals(dt)
    update_flashes(dt); update_shards(dt); update_rings(dt); update_space(dt); draw_beam(dt)
    draw_player(dt)
    draw_icons(G.lives or 0)
    G.badge_pop = max(0, (G.badge_pop or 0) - dt * 4)
    draw_badges(G.state ~= "title" and G.stage or 0, G.badge_shown or 99)
    draw_showcase(G.state == "title")
    set_point(L.fill_l, vec3(-FX - 8 + sin(G.t * 0.4) * 3, 6 + cos(G.t * 0.3) * 5, 14), vec3(0.3, 0.6, 1.0), 120, 60)
    set_point(L.fill_r, vec3(FX + 8 + cos(G.t * 0.35) * 3, 10 + sin(G.t * 0.45) * 5, 14), vec3(1.0, 0.35, 0.8), 120, 60)
    -- camera: subtle parallax drift with the player + trauma shake
    shake = max(0, shake - dt * 2.2)
    local sk = shake * shake * SHAKE_SCALE
    local ox = (sin(G.t * 47) + sin(G.t * 31.7) * 0.5) * 0.6 * sk
    local oy = (cos(G.t * 41) + sin(G.t * 23.3) * 0.5) * 0.6 * sk
    G.cam_px = damp(G.cam_px or 0, (P.state == "alive" and P.x or 0) * 0.08, 2.5, dt)
    cam:set_position(vec3(G.cam_px + ox, -CAM.tilt + oy, CAM.z))
    cam:look_at(vec3(G.cam_px * 0.6 + ox * 0.3, oy * 0.3, 0))
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
            pe_log("[Galaga] ready")
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
    SPACE.warp = damp(SPACE.warp, G.warp_target or 0, 2.5, dt)
    G.warp_target = 0
    if st == "title" then
        local act = menu_input(pressed)
        if act then do_menu_action(act) end
        SPACE.speed = 1.0
    elseif st == "intro" then
        G.intro_t = G.intro_t + dt
        update_player(dt, control)
        update_bolts(dt)
        G.badge_t = G.badge_t + dt
        local nb = #badge_list(G.stage)
        if G.intro_t > 0.4 and G.badge_shown < nb and G.badge_t > 0.13 then
            G.badge_t = 0; G.badge_shown = G.badge_shown + 1; G.badge_pop = 0.6; sfx("badge")
        end
        if G.intro_t >= G.intro_len then G.state = "play"; G.badge_shown = 99 end
    elseif st == "play" then
        if pressed("Escape") or pressed("P") then
            G.paused_from = "play"; G.state = "paused"; sfx("click")
            set_menu({ { label = "RESUME", act = "resume" }, { label = "SETTINGS", act = "settings" }, { label = "QUIT TO TITLE", act = "title" } })
        else
            play_tick(dt, control)
        end
    elseif st == "paused" then
        if pressed("Escape") or pressed("P") then G.state = G.paused_from or "play"
        else local act = menu_input(pressed); if act then do_menu_action(act) end end
    elseif st == "clear" or st == "chal_result" then
        G.clear_t = (G.clear_t or 0) + dt; G.res_t = (G.res_t or 0) + dt
        update_player(dt, control); update_bolts(dt)
        local wait = st == "clear" and 1.0 or 3.6
        local tt = st == "clear" and G.clear_t or G.res_t
        if tt > wait then G.warp_target = 1 end
        if tt > wait + 1.6 then G.clear_t, G.res_t = 0, 0; start_stage(G.stage + 1) end
    elseif st == "over" then
        local act = menu_input(pressed)
        if act then do_menu_action(act) end
        update_enemies(dt); update_bolts(dt)
    end
    update_visuals(dt)
    draw_hud(dt)
    latch()
end

------------------------------------------------------------------ Jev (holds Left / Right / Space in G.vkeys; attract stays on control == "auto")
(function()
    local source = assert(fs.read("Scripts/jev_auto.lua"), "Missing Jev module: Scripts/jev_auto.lua")
    local JevAuto = assert(load(source, "@Scripts/jev_auto.lua", "t", _ENV))()
    local reseed = false
    local prev = {}
    local keys = { "Left", "Right", "A", "D", "Space" }

    local function set_hold(left, right, fire)
        if type(G.vkeys) ~= "table" then
            G.vkeys = {}
        end
        G.vkeys.Left = left and true or nil
        G.vkeys.Right = right and true or nil
        G.vkeys.Space = fire and true or nil
    end

    local function nearest_diver()
        local best_x, best_y, best_d
        for _, e in ipairs(enemies) do
            if e.alive and e.diving and e.state ~= "attached" then
                local ox = e.x - P.x
                local oy = e.y - PLAYER_Y
                local d = ox * ox + oy * oy
                if not best_d or d < best_d then
                    best_d = d
                    best_x = e.x
                    best_y = e.y
                end
            end
        end
        return best_x, best_y, best_d ~= nil
    end

    local function human_edge()
        local skip = reseed
        reseed = false
        local edge = false
        for i = 1, #keys do
            local key = keys[i]
            local ok, down = pcall(input.is_key_down_raw, key)
            down = ok and down and true or false
            if down and not skip and not prev[key] then
                edge = true
            end
            prev[key] = down
        end
        return edge
    end

    local holds = {
        left = { left = true, fire = true },
        right = { right = true, fire = true },
        stop = { fire = true },
    }

    local function aim_dx()
        local px = P.x or 0
        local ax = px
        local best = 1e18
        for _, e in ipairs(enemies) do
            if e.alive and e.x then
                local y = e.y or 0
                if e.diving then
                    y = y - 100
                end
                if y < best then
                    best = y
                    ax = e.x
                end
            end
        end
        return ax - px
    end

    local function jev_actions()
        local dx = aim_dx()
        if dx > 0.35 then
            return { { id = "right", description = "Fly right. The guns keep firing.", score = dx } }
        end
        if dx < -0.35 then
            return { { id = "left", description = "Fly left. The guns keep firing.", score = -dx } }
        end
        return { { id = "stop", description = "Lined up. The guns keep firing.", score = 1 } }
    end

    G.jev = JevAuto.attach({
        port = 9143,
        id = "galaga-remix",
        description = "Galaga Remix. The offered action is the steer, and the guns keep firing. Prefer the higher action score.",
        playing = function()
            local s = G.state
            return s == "intro" or s == "play" or s == "clear" or s == "chal_result"
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
        on_human = function()
            set_hold(false, false, false)
        end,
        observe = function()
            local diver_x, diver_y, found = nearest_diver()
            local captured = P.state == "captured" or P.state == "lost" or G.captive_exists == true
            local observation = {
                player_x = P.x or 0,
                captured = captured,
                lives = G.lives or 0,
                score = G.score or 0,
            }
            if found then
                observation.nearest_diver_x = diver_x
                observation.nearest_diver_y = diver_y
            end
            return observation
        end,
        actions = jev_actions,
        apply = function(id)
            local h = holds[id]
            if not h then
                return
            end
            set_hold(h.left, h.right, h.fire)
        end,
        reset = function(seed)
            reseed = true
            math.randomseed(seed)
            set_hold(false, false, false)
            G.use_mouse = false
            new_game()
        end,
    })
end)()

local function init()
    build_lights(); build_space(); build_debris(); build_rings(); build_pools(); build_trails(); build_player(); build_bolts()
    build_beam(); build_badges(); build_showcase()
    paint_templates()
    pcall(audio.set_master_volume, 0.5)
    G.state = "boot"
end
init()
hooks { update = function(dt)
    G.jev:tick(dt)
    update(dt)
end }

-- automation helpers (MCP): GA.sim(seconds, keys) steps the game deterministically at 60 Hz
function G.sim(sec, keys)
    G.vkeys = keys or {}
    for _ = 1, floor(sec * 60) do update(1 / 60) end
    G.vkeys = {}
end
G.new_game = new_game
G.start_stage = start_stage
G.to_title = to_title
G.launch_dive = launch_dive
G.start_dive = start_dive
G.hit_enemy = hit_enemy
G.BEAM = BEAM
