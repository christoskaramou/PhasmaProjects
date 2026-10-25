-- JOUST REMIX  (PhasmaEngine, Lua)
local PI, TAU = math.pi, math.pi * 2
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
math.randomseed(floor((engine.get_metrics and (engine.get_metrics() or {}).frame or 0) + 4321))
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local G = { state = "boot", t = 0 }
_G.JR = G

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

-- A modernized remake of Williams' Joust (1982). Faithful core: flap to fly, wrap-around arena, rock ledges over a
-- lava lake, the higher lance wins every clash, unseated riders drop eggs that hatch into tougher knights, a lava troll
-- that grabs anyone flying too low, waves of Bounders, Hunters and Shadow Lords.
-- Modern visuals: cooked 3D ostrich/buzzard riders with flapping wings and running legs, rocky floating ledges with
-- glowing rims, a living lava lake with crust, embers and heat light, layered clash/unseat VFX, TAA with soft bloom.

------------------------------------------------------------------ render setup (see /workspace/games/common/RENDER_SETTINGS.md)
local function S(k, v) pcall(settings.set, k, v) end
local ss = scene.add_empty_node("JoustSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "cavern.hdr")
S("hdr", false); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false); S("dof", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.1)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", true); S("IBL_intensity", 0.6)
S("color_grading", true); S("color_grading_saturation", 1.08); S("color_grading_contrast", 1.05)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "SETTINGS", subtitle = "Joust Remix", file = "Save/settings.cfg",
    click = function() sfx("click") end, defaults = { master = 0.5 },
    theme = { accent = { 0.95, 0.72, 0.35, 1 }, accent2 = { 0.45, 0.75, 0.95, 1 }, text = { 0.8, 0.78, 0.74, 1 }, selected_text = { 1, 0.95, 0.88, 1 } } })
SET:apply()
local set_open = false

------------------------------------------------------------------ arena + camera
local WW = 55.2                   -- arena width (wraps)
local HW = WW / 2
local LAVA_Y = -13.2
local CEIL = 15.2
local PLATS = { { -17.0, 17.0, -11.0 }, { -28.5, -19.0, -1.5 }, { 19.0, 28.5, -1.5 }, { -5.0, 9.0, -4.0 }, { -19.5, -8.0, 4.5 }, { 9.0, 20.5, 4.0 }, { -3.5, 6.0, 10.0 } }
local PADS = { { 0.0, -11.0 }, { -13.7, 4.5 }, { 14.7, 4.0 }, { 2.0, -4.0 } }
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1600, surf.height or 900
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local FOVX = 0.9
local CAMZ = (HW + 0.2) / math.tan(FOVX * 0.5)
pcall(function() cam:set_fov(math.deg(FOVX)) end)
local VIEW_HH = HW * SH / SW
local CAMY = 1.2
local function wrapx(x) return (x + HW) % WW - HW end
local function wrapd(d) return (d + HW) % WW - HW end

------------------------------------------------------------------ templates -> clones
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[Joust] missing template " .. name); return nil end
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
local KINDS = { "player", "bounder", "hunter", "shadow" }
local PAL = {
    player = { body = { { .72, .42, .1 }, { .06, .04, .01 }, .55, 0 }, beak = { { 1, .5, .15 }, { .25, .08, 0 }, .35, 0 },
        leg = { { .9, .55, .2 }, { .03, .01, 0 }, .5, 0 }, wingl = { { .95, .75, .4 }, { .04, .03, .01 }, .6, 0 }, wingr = { { .95, .75, .4 }, { .04, .03, .01 }, .6, 0 },
        armor = { { .85, .87, .92 }, { .05, .05, .06 }, .3, .55 }, trim = { { .25, .45, 1 }, { .1, .25, .7 }, .3, .4 },
        plume = { { .4, .8, 1 }, { .6, 1.4, 2.2 }, .4, 0 }, lance = { { .6, .45, .3 }, { 0, 0, 0 }, .45, .2 }, tip = { { .8, .95, 1 }, { 1.2, 2.2, 3.0 }, .2, .5 } },
    bounder = { body = { { .1, .08, .085 }, { .03, .012, .01 }, .6, 0 }, beak = { { .9, .75, .2 }, { .4, .25, 0 }, .35, 0 },
        leg = { { .18, .15, .12 }, { 0, 0, 0 }, .6, 0 }, wingl = { { .06, .045, .05 }, { .01, 0, 0 }, .7, 0 }, wingr = { { .06, .045, .05 }, { .01, 0, 0 }, .7, 0 },
        armor = { { .75, .12, .1 }, { .12, .01, .01 }, .3, .6 }, trim = { { .95, .7, .25 }, { .2, .12, .02 }, .3, .8 },
        plume = { { 1, .3, .15 }, { 2.2, .5, .15 }, .4, 0 }, lance = { { .45, .32, .22 }, { 0, 0, 0 }, .5, .1 }, tip = { { 1, .5, .3 }, { 2.4, .8, .3 }, .2, .5 } },
    hunter = { body = { { .1, .1, .11 }, { .02, .02, .025 }, .6, 0 }, beak = { { .9, .75, .2 }, { .4, .25, 0 }, .35, 0 },
        leg = { { .18, .15, .12 }, { 0, 0, 0 }, .6, 0 }, wingl = { { .05, .05, .06 }, { 0, 0, 0 }, .7, 0 }, wingr = { { .05, .05, .06 }, { 0, 0, 0 }, .7, 0 },
        armor = { { .8, .82, .85 }, { .05, .05, .05 }, .3, .6 }, trim = { { .25, .25, .28 }, { 0, 0, 0 }, .3, .9 },
        plume = { { .95, .95, 1 }, { 1.8, 1.8, 2.0 }, .4, 0 }, lance = { { .45, .32, .22 }, { 0, 0, 0 }, .5, .1 }, tip = { { 1, 1, 1 }, { 2.2, 2.2, 2.4 }, .2, .5 } },
    shadow = { body = { { .035, .035, .06 }, { .01, .01, .03 }, .55, 0 }, beak = { { .7, .7, .85 }, { .15, .15, .3 }, .35, 0 },
        leg = { { .35, .35, .45 }, { 0, 0, 0 }, .6, 0 }, wingl = { { .03, .03, .06 }, { .01, .01, .04 }, .7, 0 }, wingr = { { .03, .03, .06 }, { .01, .01, .04 }, .7, 0 },
        armor = { { .15, .25, .75 }, { .03, .06, .25 }, .25, .7 }, trim = { { .5, .3, 1 }, { .5, .2, 1.4 }, .3, .5 },
        plume = { { .5, .4, 1 }, { 1.0, .7, 2.8 }, .4, 0 }, lance = { { .3, .3, .38 }, { 0, 0, 0 }, .4, .5 }, tip = { { .7, .6, 1 }, { 1.6, 1.2, 3.2 }, .2, .5 } },
}
local KCOL = { player = { .5, .8, 1 }, bounder = { 1, .35, .15 }, hunter = { .9, .92, 1 }, shadow = { .55, .4, 1 } }
local KSLOT = { player = 3, bounder = 0, hunter = 1, shadow = 2 }
local function paint_templates()
    for kind, parts in pairs(PAL) do
        for part, p in pairs(parts) do paint(tnode("T_" .. kind .. "_" .. part), p[1], p[2], p[3], p[4]) end
    end
end
local function sx(x) return x end
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
    lights.set_directional_light(0, vec3(-0.3, -0.55, -0.75), vec3(0.75, 0.8, 1.0), 1.5)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    L.key = addp(vec3(-8, 16, 22), vec3(0.6, 0.7, 1.0), 75, 80)
    L.fill = addp(vec3(10, 2, 34), vec3(1.0, 0.9, 0.85), 60, 80)
    L.lava = { addp(vec3(-22, LAVA_Y + 2, 6), vec3(1, 0.4, 0.1), 120, 30), addp(vec3(22, LAVA_Y + 2, 6), vec3(1, 0.4, 0.1), 120, 30),
        addp(vec3(0, LAVA_Y + 1, 9), vec3(1, 0.35, 0.08), 90, 26) }
    L.player = addp(HIDE, vec3(0.5, 0.8, 1.0), 0, 1)
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
------------------------------------------------------------------ debris shards, feathers + shockwave rings
local SHARD_COL = { [0] = { 1, .35, .15 }, { .9, .92, 1 }, { .55, .4, 1 }, { .5, .8, 1 }, { 1, .8, .4 }, { 1, .5, .1 } }
local SHARDS, live_shards = {}, {}
local function build_debris()
    for c = 0, 5 do
        local col = SHARD_COL[c]
        paint(tnode("T_shard_" .. c), col, { col[1] * 1.2, col[2] * 1.2, col[3] * 1.2 }, 0.3, 0.3)
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
            s.vx, s.vy, s.vz = s.vx * d, s.vy * d - (s.g or 9) * dt, s.vz * d
            s.x, s.y, s.z = s.x + s.vx * dt, s.y + s.vy * dt, s.z + s.vz * dt
            if s.y < LAVA_Y + 0.3 then s.y = LAVA_Y + 0.3; s.vy = abs(s.vy) * 0.4 end
            s.rx, s.ry, s.rz = s.rx + s.wx * dt, s.ry + s.wy * dt, s.rz + s.wz * dt
            local k = clamp(s.life / 0.35, 0, 1) * s.sz
            s.node:set_position(vec3(sx(s.x), s.y, s.z)); s.node:set_rotation(vec3(s.rx, s.ry, s.rz)); s.node:set_scale(vec3(k, k, k))
        end
    end
end
-- feathers: tumbling cooked feather meshes that drift down
local FEATH, live_feath, feath_next = {}, {}, 1
local function build_feathers()
    paint(tnode("T_feather"), { .16, .14, .15 }, { .02, .015, .015 }, 0.7, 0)
    for i = 1, 40 do FEATH[i] = { node = clone("T_feather", HIDE), live = false } end
end
local function feathers(x, y, n)
    for _ = 1, floor(n * (0.4 + 0.6 * PS()) + 0.5) do
        local f = FEATH[feath_next]; feath_next = feath_next % #FEATH + 1
        local a, sp = rr(0, TAU), rr(2, 7)
        f.x, f.y, f.z, f.vx, f.vy = x + rr(-1, 1), y + rr(-.8, 1), rr(-0.5, 1.5), cos(a) * sp, sin(a) * sp + 2
        f.ph, f.r, f.life, f.s = rr(0, TAU), rr(0, 360), rr(1.4, 2.4), rr(0.6, 1.1)
        if not f.live then f.live = true; live_feath[#live_feath + 1] = f end
    end
end
local function update_feathers(dt)
    for i = #live_feath, 1, -1 do
        local f = live_feath[i]; f.life = f.life - dt
        if f.life <= 0 then f.live = false; f.node:set_position(HIDE); table.remove(live_feath, i)
        else
            local d = math.exp(-2.5 * dt)
            f.vx = f.vx * d; f.vy = max(-2.2, f.vy * d - 6 * dt); f.ph = f.ph + dt * 4
            f.x = f.x + (f.vx + sin(f.ph) * 1.5) * dt; f.y = f.y + f.vy * dt
            local k = clamp(f.life / 0.5, 0, 1) * f.s
            f.node:set_position(vec3(f.x, f.y, f.z)); f.node:set_rotation(vec3(sin(f.ph) * 50, f.r + f.ph * 40, cos(f.ph) * 60)); f.node:set_scale(vec3(k, k, k))
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
            local f = (1 - k) ^ 2 * 2.2
            mlive(r.mat, "emissive", vec3(r.col[1] * f, r.col[2] * f, r.col[3] * f))
            if r.t >= r.life or k > 0.8 then r.t = r.life; r.node:set_position(HIDE) end
        end
    end
end
local shake = 0
local function add_shake(a) shake = min(1.2, shake + a) end
-- layered explosion: white core, coloured fireball, fast sparks, slow embers, debris, ring, light
local function explode(wx, y, col, slot, big)
    local x = sx(wx)
    local k = big and 1.6 or 1.0
    burst(x, y, { c0 = vec4(2.0, 1.8, 1.5, 1), c1 = vec4(col[1] * 1.5, col[2] * 1.5, col[3] * 1.5, 0), count = 14 * k, smin = 0.15, smax = 0.4 * k,
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
    feathers(wx, y, big and 10 or 7)
end

------------------------------------------------------------------ world: sky, cavern ridges, pillars, ledges, lava lake
local BG = {}
local SKY_Z = -300
local function view_half(z) local hw = (CAMZ - z) * math.tan(FOVX * 0.5); return hw, hw * SH / SW end
local PLAT_GLOW = { 1.0, 0.5, 0.15 }
local function build_world()
    local hw, hh = view_half(SKY_Z)
    BG.sky = prim("quad", vec3(0, CAMY + hh * 0.1, SKY_Z), vec3(hw * 2.4, hh * 2.6, 1))
    paint(BG.sky, { 0, 0, 0 }, { 0.9, 0.9, 0.95 }, 1, 0); mds(BG.sky); mtex(BG.sky, "emissive", "Textures/sky.png")
    paint(tnode("T_ridge_far"), { .12, .1, .13 }, { .02, .01, .02 }, 0.95, 0); mtex(tnode("T_ridge_far"), "base_color", "Textures/rock.png")
    BG.far = clone("T_ridge_far", vec3(0, -26, -150), vec3(1.4, 1.0, 1.3))
    paint(tnode("T_ridge_near"), { .2, .15, .16 }, { .03, .012, .01 }, 0.9, 0); mtex(tnode("T_ridge_near"), "base_color", "Textures/rock.png")
    BG.near = clone("T_ridge_near", vec3(0, -16, -60))
    paint(tnode("T_pillars"), { .42, .33, .3 }, { .05, .02, .012 }, 0.9, 0); mtex(tnode("T_pillars"), "base_color", "Textures/rock.png")
    BG.pil = clone("T_pillars", vec3(0, 0, -32), vec3(1.0, 1.0, 1.0))
    for i, p in ipairs(PLATS) do
        local cx = (p[1] + p[2]) / 2
        paint(tnode("T_plat" .. (i - 1)), { .5, .42, .4 }, { .015, .01, .008 }, 0.85, 0.02); mtex(tnode("T_plat" .. (i - 1)), "base_color", "Textures/rock.png")
        paint(tnode("T_platglow" .. (i - 1)), PLAT_GLOW, { PLAT_GLOW[1] * 0.45, PLAT_GLOW[2] * 0.45, PLAT_GLOW[3] * 0.45 }, 0.4, 0)
        clone("T_plat" .. (i - 1), vec3(cx, p[3], 0)); clone("T_platglow" .. (i - 1), vec3(cx, p[3], 0))
    end
    paint(tnode("T_lava"), { 1, .45, .1 }, { 1.6, .55, .12 }, 0.35, 0); mtex(tnode("T_lava"), "emissive", "Textures/lava.png"); mtex(tnode("T_lava"), "base_color", "Textures/lava.png")
    BG.lava = clone("T_lava", vec3(0, LAVA_Y, 0))
    paint(tnode("T_crust"), { .12, .07, .06 }, { .06, .015, .0 }, 0.95, 0); mtex(tnode("T_crust"), "base_color", "Textures/rock.png")
    BG.crust = clone("T_crust", vec3(0, LAVA_Y, 0))
    BG.crust2 = clone("T_crust", vec3(80, LAVA_Y, 0))
    paint(tnode("T_pad"), { .8, .55, .3 }, { .55, .35, .15 }, 0.3, 0)
    BG.pads = {}
    for i, p in ipairs(PADS) do BG.pads[i] = clone("T_pad", vec3(p[1], p[2] + 0.05, 0.6), vec3(0.8, 1, 0.8)) end
    paint(tnode("T_beam"), { .1, .15, .2, 1 }, { .3, .5, .8 }, 0.3, 0); mds(tnode("T_beam"))
    BG.beam = clone("T_beam", HIDE)
    -- embers rising from the lava + heat haze sparks
    BG.embers = {}
    for i = 1, 9 do
        BG.embers[i] = new_emitter({ c0 = vec4(2.4, 0.9, 0.25, 1), c1 = vec4(0.8, 0.1, 0.02, 0), count = 300, radius = 1.6, smin = 0.04, smax = 0.11,
            lmin = 1.2, lmax = 2.6, noise = 2.0, drag = 0.6, vel = vec3(0, 2.2, 0), grav = vec3(0, 0.6, 0) })
    end
    BG.dust = new_emitter({ c0 = vec4(0.5, 0.45, 0.5, 0.35), c1 = vec4(0.3, 0.25, 0.3, 0), count = 300, radius = 26, smin = 0.03, smax = 0.07,
        lmin = 4, lmax = 7, noise = 0.6, drag = 0.2, vel = vec3(0.4, 0.15, 0) })
end
local EMBER_X = { -26.5, -23.5, -20.5, -18, 18, 20.5, 23.5, 26.5, 0 }
local function update_world(dt)
    local t = G.t
    local pulse = 0.85 + 0.15 * sin(t * 1.3) + 0.06 * sin(t * 4.1)
    mlive(tnode("T_lava"), "emissive", vec3(1.6 * pulse, 0.55 * pulse, 0.12 * pulse))
    local off = (t * 0.6) % 80
    BG.crust:set_position(vec3(off - 0, LAVA_Y + 0.05 * sin(t), 0)); BG.crust2:set_position(vec3(off - 80, LAVA_Y + 0.05 * sin(t + 1), 0))
    BG.lava:set_position(vec3(0, LAVA_Y + 0.06 * sin(t * 0.8), 0))
    for i, e in ipairs(BG.embers) do emitter_at(e, EMBER_X[i] + sin(t * 0.7 + i) * 0.8, LAVA_Y + 0.3, i == 9 and -4 or (i % 2) * 2 - 0.5, i == 9 and 8 or 11) end
    emitter_at(BG.dust, 0, 2, -4, 6)
    for i, li in ipairs(L.lava) do
        local f = 0.8 + 0.2 * sin(t * (3 + i) + i) + 0.1 * sin(t * 11.3 + i * 2)
        local p = ({ vec3(-22, LAVA_Y + 2.5, 6), vec3(22, LAVA_Y + 2.5, 6), vec3(0, LAVA_Y + 1.2, 9) })[i]
        set_point(li, p, vec3(1, 0.42, 0.12), (i == 3 and 70 or 130) * f, i == 3 and 24 or 32)
    end
    for i, n in ipairs(BG.pads) do n:set_rotation(vec3(0, t * 40 + i * 30, 0)) end
    mlive(tnode("T_pad"), "emissive", vec3(0.55 + 0.15 * sin(t * 2), 0.35, 0.15))
end

------------------------------------------------------------------ input
local prev = {}
G.vk = {}
G.human_prev = {}
G.human_hit = false
G.human_keys = { "Left", "A", "Right", "D", "Space", "W", "Up", "J" }
local keyfn = input.is_key_down_raw or input.is_key_pressed
local function held(k) if G.vk and G.vk[k] then return true end local ok, v = pcall(keyfn, k); return ok and v end
local function edge(k) local d = held(k); local p = prev[k]; prev[k] = d; return d and not p end
local function any(...) for _, k in ipairs({ ... }) do if held(k) then return true end end; return false end
G.poll_human = function()
    G.human_hit = false
    for i = 1, #G.human_keys do
        local name = G.human_keys[i]
        local ok, pressed = pcall(input.is_key_down_raw, name)
        local down = ok and pressed and true or false
        if down and not G.human_prev[name] then
            G.human_hit = true
        end
        G.human_prev[name] = down
    end
end

------------------------------------------------------------------ state
local score, hiscore, lives, wave = 0, 0, 4, 0
local next_extra = 20000
pcall(function() local s = fs.read("Save/joust_hiscore.txt"); if s then hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, "Save/joust_hiscore.txt", tostring(hiscore)) end
local banner = { text = "", sub = "", t = 0 }
local function show_banner(s, sub, d) banner.text, banner.sub, banner.t = s, sub or "", d or 2.4 end
local POP = {}
for i = 1, 8 do POP[i] = { t = 9 } end
local pop_next = 1
local function popup(x, y, txt, col)
    local p = POP[pop_next]; pop_next = pop_next % #POP + 1
    p.x, p.y, p.txt, p.col, p.t = x, y, txt, col or { 1, .9, .6 }, 0
end
local function add_score(p, x, y)
    score = score + p
    if x then popup(x, y, tostring(p)) end
    if score >= next_extra then next_extra = next_extra + 20000; lives = lives + 1; sfx("extra"); show_banner("Extra Life", "+1 rider", 1.8) end
end

------------------------------------------------------------------ riders (player + enemies share model, physics, animation)
local RS = 1.2                        -- rider model scale
local FEET, HEAD = 1.25 * RS, 2.4 * RS -- origin -> feet / -> helmet top
------------------------------------------------------------------ colliders (match the cooked meshes)
-- All shapes are tapered capsules {ax, ay, bx, by, ra, rb} in the model's local space (facing +x, unscaled),
-- taken from tools/gen_meshes.py (the source the .pemesh files are cooked from).  World transform follows
-- the rider node exactly: tilt about z, the yaw turn (cos(yaw) squashes/flips x) and the spawn scale.
-- Wings (animated feathers) are deliberately left out so a flap never decides a joust.
G.COL = {
    ostrich = {
        { -0.37, 0.55, 0.37, 0.55, 0.58, 0.58, "mount" },      -- body ellipsoid (0.95 x 0.58)
        { -0.62, 0.78, -1.45, 1.10, 0.13, 0.07, "mount" },      -- plume tail
        { 0.70, 0.85, 0.95, 1.35, 0.20, 0.17, "mount" },        -- S-neck
        { 0.95, 1.35, 0.95, 1.85, 0.18, 0.17, "mount" },
        { 0.95, 1.85, 1.10, 2.20, 0.17, 0.17, "mount" },
        { 1.10, 2.25, 1.26, 2.25, 0.22, 0.22, "mount" },        -- head
        { 1.30, 2.20, 1.80, 2.20, 0.08, 0.06, "mount" },        -- beak
        { 0.05, 0.30, 0.10, -0.95, 0.11, 0.07, "legs" },         -- legs (hip -> toes)
    },
    buzzard = {
        { -0.50, 0.55, 0.50, 0.55, 0.50, 0.50, "mount" },      -- body ellipsoid (1.0 x 0.5)
        { -0.80, 0.75, -1.70, 0.52, 0.10, 0.06, "mount" },      -- ragged tail
        { 0.75, 0.75, 1.10, 1.15, 0.19, 0.16, "mount" },        -- low neck + ruff
        { 1.10, 1.15, 1.35, 1.40, 0.16, 0.14, "mount" },
        { 1.40, 1.45, 1.60, 1.45, 0.20, 0.20, "mount" },        -- head
        { 1.65, 1.42, 2.10, 1.30, 0.09, 0.04, "mount" },        -- hooked beak
        { 0.05, 0.30, 0.00, -0.95, 0.11, 0.07, "legs" },
    },
    knight = {
        { -0.10, 1.35, -0.10, 1.55, 0.32, 0.32, "rider" },      -- torso (0.32 x 0.42)
        { -0.08, 2.05, -0.08, 2.05, 0.25, 0.25, "rider" },      -- helmet
        { -0.10, 2.27, -0.41, 2.62, 0.07, 0.03, "rider" },      -- plume
        { 0.15, 1.37, 3.00, 1.62, 0.07, 0.05, "lance" },        -- lance shaft (mesh 0.15..3.0)
        { 3.00, 1.62, 3.45, 1.66, 0.07, 0.01, "tip" },          -- lance tip
    },
    egg = { { 0, 0.36, 0, 0.57, 0.36, 0.36, "egg" } },          -- egg mesh: 0.72 wide, 0.96 tall
}
G.COL_GROW = 0.04   -- tiny skin so grazing contacts at high speed still register
-- world-space shapes of a rider: list of {ax,ay,bx,by,ra,rb,tag}
function G.col_world(r, list, out)
    out = out or {}
    local sc = (r.spawn and r.spawn > 0) and math.max(0.05, 1 - r.spawn) or 1
    sc = sc * RS
    local cy = math.cos(math.rad(r.yaw or 0))
    local tr = math.rad(r.tilt or 0)
    local ct, st = math.cos(tr), math.sin(tr)
    for _, s in ipairs(list) do
        local ax, ay = s[1] * ct - s[2] * st, s[1] * st + s[2] * ct
        local bx, by = s[3] * ct - s[4] * st, s[3] * st + s[4] * ct
        out[#out + 1] = { r.x + ax * cy * sc, r.y + ay * sc, r.x + bx * cy * sc, r.y + by * sc, s[5] * sc, s[6] * sc, s[7] }
    end
    return out
end
function G.rider_shapes(r)
    local o = G.col_world(r, r.kind == "player" and G.COL.ostrich or G.COL.buzzard)
    return G.col_world(r, G.COL.knight, o)
end
function G.egg_shapes(g)
    local a = math.rad(-(g.rot or 0))
    local ca, sa = math.cos(a), math.sin(a)
    local s = G.COL.egg[1]
    return { { g.x - s[2] * sa, g.y + s[2] * ca, g.x - s[4] * sa, g.y + s[4] * ca, s[5], s[6], "egg" } }
end
-- closest points between segments p(s)=A+s(B-A), q(t)=C+t(D-C)
function G.seg_seg(ax, ay, bx, by, cx, cy, dx, dy)
    local ux, uy, vx, vy, wx, wy = bx - ax, by - ay, dx - cx, dy - cy, ax - cx, ay - cy
    local a, b, c, d, e = ux * ux + uy * uy, ux * vx + uy * vy, vx * vx + vy * vy, ux * wx + uy * wy, vx * wx + vy * wy
    local D = a * c - b * b
    local s, t
    if a < 1e-9 and c < 1e-9 then return 0, 0, sqrt(wx * wx + wy * wy)
    elseif a < 1e-9 then s = 0; t = clamp(e / c, 0, 1)
    elseif c < 1e-9 then t = 0; s = clamp(-d / a, 0, 1)
    else
        s = D > 1e-9 and clamp((b * e - c * d) / D, 0, 1) or 0
        t = (b * s + e) / c
        if t < 0 then t = 0; s = clamp(-d / a, 0, 1) elseif t > 1 then t = 1; s = clamp((b - d) / a, 0, 1) end
    end
    local px, py, qx, qy = ax + ux * s, ay + uy * s, cx + vx * t, cy + vy * t
    return s, t, sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
end
-- tapered-capsule overlap; shapes of b are shifted by sx (wrap-around)
function G.cap_hit(p, q, sx)
    local s, t, d = G.seg_seg(p[1], p[2], p[3], p[4], q[1] + sx, q[2], q[3] + sx, q[4])
    return d < (p[5] + (p[6] - p[5]) * s) + (q[5] + (q[6] - q[5]) * t) + G.COL_GROW
end
-- does any shape of A tagged in ta touch any shape of B tagged in tb?
function G.group_hit(A, B, ta, tb, sx)
    for _, p in ipairs(A) do if ta[p[7]] then
        for _, q in ipairs(B) do if tb[q[7]] and G.cap_hit(p, q, sx) then return true end end
    end end
    return false
end
G.BODY = { mount = true, rider = true, legs = true }
G.LANCE = { lance = true, tip = true }
G.ALL = { mount = true, rider = true, legs = true, lance = true, tip = true }
G.TIP = { tip = true }
-- contact between two riders: lance tip on body, lance on lance, or bodies bumping
function G.riders_touch(a, b)
    local dx = wrapd(b.x - a.x)
    if math.abs(dx) > 9 or math.abs(b.y - a.y) > 6 then return false end
    local sx = dx - (b.x - a.x)       -- shift that brings b next to a across the wrap seam
    local A, B = G.rider_shapes(a), G.rider_shapes(b)
    return G.group_hit(A, B, G.ALL, G.ALL, sx), A, B, sx
end
-- ledge underside (relative to ledge top) at world x, using the generated slab profile
function G.ledge_under(i, lx)
    local pc = G.PLAT_COL[i]
    if pc.flat == nil then local t = 0; for _, v in ipairs(pc.y) do t = t + v end; pc.flat = t / #pc.y end
    do return pc.flat end   -- simple flat underside at the slab's mean bottom (no spikes)
    local f = (lx - pc.xs0) / pc.dx
    local k = math.floor(f)
    local ys = pc.y
    if k < 0 then return ys[1] elseif k >= #ys - 1 then return ys[#ys] end
    local u = f - k
    return ys[k + 1] * (1 - u) + ys[k + 2] * u
end
-- push a rider out of ledge slabs and stalactites (head bumps / side bumps), circle samples along its shapes
function G.col_ledges(r, dt)
    if r.ground then return end
    local sh = G.col_world(r, r.kind == "player" and G.COL.ostrich or G.COL.buzzard)
    G.col_world(r, G.COL.knight, sh)
    for i, pl in ipairs(PLATS) do
        local cxp = (pl[1] + pl[2]) * 0.5
        local hw = (pl[2] - pl[1]) * 0.5
        local dxp = wrapd(r.x - cxp)
        if math.abs(dxp) < hw + 5 and r.y - FEET < pl[3] + 0.5 and r.y + 4 > pl[3] - 6 then
            local ox = r.x - (cxp + dxp)   -- world -> ledge-local x offset (handles wrap)
            for _, s in ipairs(sh) do
                if s[7] ~= "legs" then   -- feet are handled by the landing code
                    for k = 0, 2 do
                        local u = k / 2
                        local px = s[1] + (s[3] - s[1]) * u - ox - cxp
                        local py = s[2] + (s[4] - s[2]) * u - pl[3]
                        local rr_ = s[5] + (s[6] - s[5]) * u
                        -- slab: x in [-hw, hw], y in [under(x), 0]
                        if px + rr_ > -hw and px - rr_ < hw and py - rr_ < -0.05 then
                            local ux = clamp(px, -hw, hw)
                            local under = G.ledge_under(i, ux)
                            if py + rr_ > under then
                                -- smallest way out: down (head bump), or out of the left / right end
                                local pen_d = py + rr_ - under
                                local pen_l = px + rr_ + hw
                                local pen_r = hw - px + rr_
                                if pen_d <= pen_l and pen_d <= pen_r then
                                    r.y = r.y - pen_d; if r.vy > 0 then r.vy = -abs(r.vy) * 0.35 end
                                elseif pen_l < pen_r then r.x = wrapx(r.x - pen_l); r.vx = -abs(r.vx) * 0.5
                                else r.x = wrapx(r.x + pen_r); r.vx = abs(r.vx) * 0.5 end
                                return
                            end
                        end
                    end
                end
            end
        end
    end
end
G.PLAT_COL = {
  { xs0=-17.000, dx=0.5000, y={-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.61,-2.60,-2.60,-2.60,-2.76,-2.60,-2.60,-2.60,-2.60,-2.62,-2.81,-2.60,-2.62,-2.60,-2.60,-2.60,-2.60,-2.60,-2.61,-2.65,-2.65,-2.60,-2.60,-2.60,-2.60,-2.60,-2.63,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60,-2.60}, st={{13.30,-2.30,0.58,0.82},{15.04,-2.30,0.53,1.88},{15.25,-2.30,0.46,1.08},{8.17,-2.30,0.66,1.39},{-14.51,-2.30,0.57,1.91},{15.75,-2.30,0.47,1.00},{15.30,-2.30,0.37,1.61},{0.39,-2.30,0.64,1.15},{-2.76,-2.30,0.65,1.34},{14.89,-2.30,0.70,1.63},{11.97,-2.30,0.38,2.07},{15.14,-2.30,0.60,1.79},{-3.88,-2.30,0.45,1.22}} },
  { xs0=-4.750, dx=0.5000, y={-0.77,-0.82,-0.94,-1.23,-1.28,-1.36,-1.27,-1.37,-1.30,-1.62,-1.21,-1.40,-1.29,-1.35,-1.34,-1.18,-1.07,-1.12,-1.00,-0.69}, st={{-3.86,-0.52,0.56,1.54},{2.26,-1.04,0.36,0.84},{-3.42,-0.64,0.39,1.32}} },
  { xs0=-4.750, dx=0.5000, y={-0.77,-0.86,-1.00,-1.09,-1.05,-1.44,-1.41,-1.53,-1.40,-1.28,-1.40,-1.33,-1.60,-1.32,-1.40,-1.03,-1.07,-0.98,-0.99,-0.70}, st={{-3.70,-0.70,0.51,1.73},{3.42,-0.77,0.36,1.38},{3.78,-0.68,0.46,2.06}} },
  { xs0=-7.000, dx=0.5000, y={-0.55,-1.31,-0.91,-1.09,-0.99,-1.16,-1.03,-1.28,-1.38,-1.27,-1.31,-1.42,-1.42,-1.31,-1.32,-1.46,-1.43,-1.60,-1.16,-1.37,-1.15,-1.23,-1.01,-1.02,-1.11,-0.92,-1.14,-0.79,-0.95}, st={{1.38,-1.13,0.55,1.53},{2.70,-1.07,0.55,1.61},{0.96,-1.16,0.53,1.20},{-4.96,-0.69,0.57,2.00},{-2.24,-0.97,0.45,1.02}} },
  { xs0=-5.750, dx=0.5000, y={-0.69,-1.08,-1.25,-1.48,-1.24,-1.10,-1.29,-1.27,-1.23,-1.48,-1.07,-1.50,-1.35,-1.06,-1.39,-1.34,-1.39,-1.25,-1.50,-1.27,-0.93,-1.03,-0.99,-0.73}, st={{0.15,-1.20,0.55,0.82},{-4.92,-0.78,0.42,1.44},{0.32,-1.05,0.52,1.86},{-1.16,-1.18,0.61,1.38}} },
  { xs0=-5.750, dx=0.5000, y={-0.94,-1.07,-1.01,-1.20,-1.13,-1.15,-1.47,-1.21,-1.43,-1.13,-1.30,-1.46,-1.37,-1.37,-1.34,-1.19,-1.26,-1.09,-1.17,-1.22,-1.32,-1.24,-0.94,-0.69}, st={{1.10,-1.07,0.56,1.59},{2.16,-0.89,0.61,2.14},{-0.95,-0.83,0.68,1.52},{2.78,-0.79,0.51,0.87}} },
  { xs0=-4.750, dx=0.5000, y={-0.84,-0.91,-0.97,-1.05,-1.02,-1.34,-1.27,-1.41,-1.56,-1.48,-1.38,-1.50,-1.39,-1.20,-1.23,-1.17,-1.13,-1.11,-1.21,-0.65}, st={{-3.04,-0.75,0.62,1.91},{-2.97,-0.75,0.58,1.76},{-3.76,-0.61,0.69,1.57}} }
}  -- generated by tools/colgen.py from the ledge mesh generator: slab underside profile + stalactite cones (x, y, radius, length), local to ledge centre/top
local GRAV, FLAP_V, VY_MAX, VY_MIN = 24.0, 8.6, 11.5, -16.0
local SPEC = {
    player = { vmax = 12.5, run = 22, air = 9, flap_dx = 2.6, pts = 0 },
    bounder = { vmax = 7.0, run = 14, air = 5, flap_dx = 1.6, pts = 500, cd = 0.27 },
    hunter = { vmax = 9.5, run = 16, air = 7, flap_dx = 2.0, pts = 750, cd = 0.21 },
    shadow = { vmax = 12.0, run = 18, air = 9, flap_dx = 2.5, pts = 1500, cd = 0.17 },
}
local function make_rider(kind)
    seq = seq + 1
    local root = scene.add_empty_node("r_" .. kind .. seq); root:set_position(HIDE)
    local m = { root = root }
    local function part(p, pos) return clone("T_" .. kind .. "_" .. p, pos or vec3(0, 0, 0), nil, root) end
    m.body = part("body"); m.beak = part("beak")
    m.wl = part("wingl", vec3(-0.1, 0.95, 0.35)); m.wr = part("wingr", vec3(-0.1, 0.95, -0.35))
    m.l1 = part("leg", vec3(0.05, 0.3, 0.22)); m.l2 = part("leg", vec3(0.05, 0.3, -0.22))
    m.armor = part("armor"); m.trim = part("trim"); m.plume = part("plume"); m.lance = part("lance"); m.tip = part("tip")
    return m
end
local function new_rider(kind, m)
    return { kind = kind, m = m, x = 0, y = 0, vx = 0, vy = 0, face = 1, yaw = 0, ground = false, wing = 0, wingv = 0, flap_t = 0,
        legph = 0, alive = true, spawn = 0, grab = nil, ai_t = 0, ai_dir = 1, ai_y = 0, hold_t = 0, step_t = 0, tilt = 0 }
end
local function plat_under(x, f_old, f_new)
    for _, p in ipairs(PLATS) do
        for _, xx in ipairs({ x, x - WW, x + WW }) do
            if xx > p[1] - 0.25 and xx < p[2] + 0.25 and f_old >= p[3] - 0.3 and f_new <= p[3] then return p end
        end
    end
end
local function on_plat(x, f)
    for _, p in ipairs(PLATS) do
        for _, xx in ipairs({ x, x - WW, x + WW }) do
            if xx > p[1] - 0.25 and xx < p[2] + 0.25 and abs(f - p[3]) < 0.08 then return p end
        end
    end
end
local function dust(x, y, n, col)
    col = col or { .6, .5, .45 }
    burst(x, y, { c0 = vec4(col[1], col[2], col[3], 0.6), c1 = vec4(col[1] * .5, col[2] * .5, col[3] * .5, 0), count = n or 10, smin = 0.08, smax = 0.22,
        lmin = 0.3, lmax = 0.7, radius = 0.4, spread = 4, drag = 3, grav = vec3(0, 1.0, 0), z = 0.8 })
end
local function flap(r)
    r.vy = clamp(max(r.vy, -2) + FLAP_V, VY_MIN, VY_MAX); r.wingv = 1; r.flap_t = 0
    r.ground = false
    if r.kind == "player" then sfx("flap") end
    if rand() < 0.5 then burst(r.x - r.face * 0.3, r.y + 0.7, { c0 = vec4(1.4, 1.3, 1.2, 0.8), c1 = vec4(.5, .5, .5, 0), count = 5, smin = .04, smax = .1, lmin = .25, lmax = .5, radius = .5, spread = 3, drag = 3, z = 0.4 }) end
end
-- step physics for a rider given control {h=-1..1, flap=bool}
local function rider_physics(r, c, dt)
    local s = SPEC[r.kind]
    if c.flap then flap(r); if c.h ~= 0 then r.vx = r.vx + c.h * s.flap_dx; r.face = c.h end end
    if r.ground then
        if c.h ~= 0 then
            if c.h * r.vx < -1.5 then -- skid when reversing at speed
                r.vx = r.vx + c.h * s.run * 1.4 * dt
                r.skid = (r.skid or 0) + dt
                if rand() < 0.5 then burst(r.x + r.face * 0.4, r.y - FEET + 0.1, { c0 = vec4(2.5, 1.6, .7, 1), c1 = vec4(1, .3, .1, 0), count = 3, smin = .03, smax = .07, lmin = .15, lmax = .35, radius = .2, spread = 9, drag = 2, z = 0.6 }) end
                if r.kind == "player" and r.skid > 0 and (r.skid_s or 0) <= 0 then sfx("skid"); r.skid_s = 0.4 end
            else r.vx = r.vx + c.h * s.run * dt; r.face = c.h end
        else
            r.vx = r.vx * math.exp(-6 * dt)
        end
    else
        if c.h ~= 0 then r.vx = r.vx + c.h * s.air * dt end
        r.vx = r.vx * math.exp(-0.25 * dt)
        r.vy = max(VY_MIN, r.vy - GRAV * dt)
    end
    r.skid_s = (r.skid_s or 0) - dt
    r.vx = clamp(r.vx, -s.vmax, s.vmax)
    local f_old = r.y - FEET
    r.x = wrapx(r.x + r.vx * dt)
    if not r.ground then r.y = r.y + r.vy * dt end
    local f_new = r.y - FEET
    if r.ground then
        if not on_plat(r.x, f_new) then r.ground = false; r.vy = 0 end
    elseif r.vy <= 0 then
        local p = plat_under(r.x, f_old, f_new)
        if p then
            r.y = p[3] + FEET; r.vy = 0; r.ground = true
            dust(r.x, p[3] + 0.1, 8); if r.kind == "player" then sfx("step") end
        end
    end
    -- head / side bumps against the ledges' real shape (slab underside profile + stalactites)
    G.col_ledges(r, dt)
    if r.y + HEAD > CEIL then r.y = CEIL - HEAD; r.vy = -abs(r.vy) * 0.3 end
end
local function rider_anim(r, dt)
    local m = r.m
    if not r.alive then return end
    r.yaw = damp(r.yaw, r.face > 0 and -12 or 192, 12, dt)
    local tilt_t = r.ground and 0 or clamp(-r.vx * r.face * -0.6 + r.vy * 0.6, -12, 14)
    r.tilt = damp(r.tilt, tilt_t, 8, dt)
    local sc = r.spawn > 0 and (1 - r.spawn) or 1
    sc = clamp(sc, 0.05, 1) * RS
    m.root:set_position(vec3(r.x, r.y, 0)); m.root:set_rotation(vec3(0, r.yaw, r.tilt)); m.root:set_scale(vec3(sc, sc, sc))
    -- wings: flap stroke after each flap, glide spread in air, folded on the ground
    r.flap_t = r.flap_t + dt
    local wa
    if r.ground then wa = 62 + 4 * sin(G.t * 3)
    elseif r.flap_t < 0.32 then local k = r.flap_t / 0.32; wa = -55 + 115 * sin(k * PI) ^ 0.8 * (k < 0.5 and 1 or 1) - (k > 0.5 and 0 or 0)
    else wa = -12 + 6 * sin(G.t * 5) end
    m.wl:set_rotation(vec3(-wa, 0, 0)); m.wr:set_rotation(vec3(wa, 0, 0))
    -- legs: run cycle on the ground, tucked in the air
    local sp = abs(r.vx)
    local l1, l2
    if r.ground then
        r.legph = r.legph + dt * (2 + sp * 1.4)
        local a = min(1, sp / 4) * 38
        l1, l2 = sin(r.legph) * a, -sin(r.legph) * a
        if sp > 1 then
            r.step_t = r.step_t - dt
            if r.step_t <= 0 then r.step_t = PI / (2 + sp * 1.4); if r.kind == "player" then sfx("step") end; dust(r.x - r.face * 0.2, r.y - FEET + 0.1, 2) end
        end
        m.body:set_position(vec3(0, abs(sin(r.legph)) * 0.06 * min(1, sp / 3), 0))
    else
        l1, l2 = -55, -40
        m.body:set_position(vec3(0, 0, 0))
    end
    m.l1:set_rotation(vec3(0, 0, l1)); m.l2:set_rotation(vec3(0, 0, l2))
end
local function hide_rider(r) r.m.root:set_position(HIDE) end

------------------------------------------------------------------ pools
local P = new_rider("player", nil)
P.dead_t = 0; P.inv = 0; P.lives_shown = 0
local POOL = { bounder = {}, hunter = {}, shadow = {} }
local enemies = {}
G.enemies = enemies
local function build_riders()
    P.m = make_rider("player")
    P.trail = new_emitter({ c0 = vec4(.8, 1.4, 2.0, 0.8), c1 = vec4(.3, .5, 1, 0), count = 200, radius = 0.1, smin = 0.03, smax = 0.07, lmin = 0.15, lmax = 0.3, noise = 0.6, drag = 2 })
    for k, n in pairs({ bounder = 8, hunter = 8, shadow = 6 }) do
        for i = 1, n do POOL[k][i] = { m = make_rider(k), used = false } end
    end
end
local spawn_fx
local function spawn_enemy(kind, x, y, from_egg)
    for _, slot in ipairs(POOL[kind]) do
        if not slot.used then
            slot.used = true
            local e = new_rider(kind, slot.m)
            e.slot = slot; e.x, e.y = x, y + FEET; e.ground = true; e.spawn = 1; e.face = rand() < 0.5 and -1 or 1
            e.ai_y = rr(-6, 10); e.ai_dir = e.face; e.ai_t = rr(0.5, 2)
            enemies[#enemies + 1] = e
            if not from_egg then spawn_fx(x, y, KCOL[kind]) end
            return e
        end
    end
end
local function despawn(e)
    e.alive = false; e.slot.used = false; hide_rider(e)
    for i = #enemies, 1, -1 do if enemies[i] == e then table.remove(enemies, i) end end
end
local beam_t, beam_x, beam_y, beam_col = 9, 0, 0, { 1, 1, 1 }
function spawn_fx(x, y, col)
    beam_t, beam_x, beam_y, beam_col = 0, x, y, col
    burst(x, y + 1, { c0 = vec4(col[1] * 2 + .5, col[2] * 2 + .5, col[3] * 2 + .5, 1), c1 = vec4(col[1], col[2], col[3], 0), count = 40, smin = .04, smax = .1,
        lmin = .4, lmax = .9, radius = 1.0, spread = 3, drag = 1, grav = vec3(0, 5, 0) })
    flash(x, y + 1.5, col, 50, 0.6, 9); shockwave(x, y + 0.2, col, 2.6, 0.5)
    burst(x, y + 2.5, { c0 = vec4(col[1] + .6, col[2] + .6, col[3] + .6, 1), c1 = vec4(col[1], col[2], col[3], 0), count = 60, smin = .03, smax = .07, lmin = .5, lmax = 1.0, radius = .35, spread = 1.5, drag = 0.5, grav = vec3(0, 7, 0) })
    sfx("spawn")
end
local function update_beam(dt)
    beam_t = beam_t + dt
    if false then
        local k = beam_t / 0.8
        BG.beam:set_position(vec3(beam_x, beam_y, 0)); BG.beam:set_scale(vec3(0.45 * (1 - k * 0.7), 9 * (1 - k * k) + 0.1, 0.45 * (1 - k * 0.7)))
        local f = (1 - k) * 0.7
        mlive(tnode("T_beam"), "emissive", vec3(beam_col[1] * f, beam_col[2] * f, beam_col[3] * f))
    else BG.beam:set_position(HIDE) end
end

------------------------------------------------------------------ eggs
local EGGS = {}
local egg_chain = 0
local NEXT_KIND = { bounder = "hunter", hunter = "shadow", shadow = "shadow" }
local function build_eggs()
    paint(tnode("T_egg"), { .92, .9, .82 }, { .06, .06, .05 }, 0.35, 0)
    paint(tnode("T_eggband"), { .5, .8, 1 }, { .6, 1.1, 1.6 }, 0.3, 0)
    for i = 1, 12 do
        local root = scene.add_empty_node("egg" .. i); root:set_position(HIDE)
        clone("T_egg", vec3(0, 0, 0), nil, root); clone("T_eggband", vec3(0, 0, 0), nil, root)
        EGGS[i] = { root = root, live = false }
    end
end
local function drop_egg(e)
    for _, g in ipairs(EGGS) do
        if not g.live then
            g.live = true; g.x, g.y, g.vx, g.vy = e.x, e.y, e.vx * 0.6, max(e.vy, 2); g.ground = false; g.t = 0; g.kind = NEXT_KIND[e.kind]; g.rot = 0
            return g
        end
    end
end
local function eggs_live() local n = 0; for _, g in ipairs(EGGS) do if g.live then n = n + 1 end end; return n end
local function kill_egg(g) g.live = false; g.root:set_position(HIDE) end
local function update_eggs(dt)
    for _, g in ipairs(EGGS) do
        if g.live then
            g.t = g.t + dt
            local fo = g.y
            if not g.ground then
                g.vy = max(VY_MIN, g.vy - GRAV * 0.8 * dt); g.x = wrapx(g.x + g.vx * dt); g.y = g.y + g.vy * dt
                local p = (g.vy <= 0) and plat_under(g.x, fo, g.y)
                if p then
                    g.y = p[3]
                    if g.vy < -4 then g.vy = -g.vy * 0.35; dust(g.x, g.y, 4) else g.vy = 0; g.ground = true; g.t = 0 end
                end
                g.rot = g.rot + g.vx * dt * 120
                if g.y < LAVA_Y then
                    burst(g.x, LAVA_Y + 0.3, { c0 = vec4(2.5, 1, .2, 1), c1 = vec4(1, .2, 0, 0), count = 25, smin = .05, smax = .14, lmin = .3, lmax = .8, radius = .3, spread = 8, drag = 2, grav = vec3(0, -6, 0) })
                    kill_egg(g)
                end
            else
                g.vx = g.vx * math.exp(-4 * dt); g.x = wrapx(g.x + g.vx * dt); g.rot = g.rot + g.vx * dt * 120
                if not on_plat(g.x, g.y) then g.ground = false end
                if g.t > 8.5 then -- hatch
                    local e = spawn_enemy(g.kind, g.x, g.y, true)
                    burst(g.x, g.y + 0.5, { c0 = vec4(2, 2, 1.8, 1), c1 = vec4(.9, .85, .7, 0), count = 30, smin = .05, smax = .15, lmin = .3, lmax = .7, radius = .3, spread = 10, drag = 3, grav = vec3(0, -8, 0) })
                    shockwave(g.x, g.y + 0.5, KCOL[g.kind], 2.5, 0.4); sfx("hatch")
                    kill_egg(g)
                end
            end
            if g.live then
                local wob = (g.ground and g.t > 6) and sin(g.t * (20 + (g.t - 6) * 10)) * (g.t - 6) * 6 or 0
                g.root:set_position(vec3(g.x, g.y, 0.3)); g.root:set_rotation(vec3(0, 0, -g.rot + wob))
                local f = 0.6 + 0.4 * sin(g.t * 5)
                if P.alive and abs(wrapd(g.x - P.x)) < 5 and G.group_hit(G.rider_shapes(P), G.egg_shapes(g), G.ALL, { egg = true }, wrapd(g.x - P.x) - (g.x - P.x)) then
                    egg_chain = egg_chain + 1
                    local pts = min(1000, 250 * egg_chain) + (g.ground and 0 or 500)
                    add_score(pts, g.x, g.y + 1); sfx("egg")
                    if not g.ground then popup(g.x, g.y + 2, "Mid-air catch", { .6, .9, 1 }) end
                    shockwave(g.x, g.y + 0.4, { .6, .9, 1 }, 2, 0.35)
                    burst(g.x, g.y + 0.4, { c0 = vec4(1.5, 2.2, 2.8, 1), c1 = vec4(.3, .6, 1, 0), count = 30, smin = .04, smax = .1, lmin = .3, lmax = .6, radius = .3, spread = 10, drag = 3 })
                    flash(g.x, g.y + 0.5, { .5, .8, 1 }, 35, 0.3, 7)
                    kill_egg(g)
                end
            end
        end
    end
    mlive(tnode("T_eggband"), "emissive", vec3(.5 + .3 * sin(G.t * 4), .9 + .4 * sin(G.t * 4), 1.4 + .5 * sin(G.t * 4)))
end

------------------------------------------------------------------ lava troll
local TROLL = { state = "idle", t = 0, x = 0, y = LAVA_Y - 5, target = nil, grip = 0, cool = 3 }
local function build_troll()
    paint(tnode("T_hand"), { .3, .12, .07 }, { .45, .1, .02 }, 0.8, 0); mtex(tnode("T_hand"), "base_color", "Textures/rock.png")
    paint(tnode("T_handglow"), { 1, .4, .1 }, { 3.0, 1.0, .2 }, 0.5, 0)
    TROLL.root = scene.add_empty_node("troll"); TROLL.root:set_position(HIDE)
    clone("T_hand", vec3(0, 0, 0), nil, TROLL.root); clone("T_handglow", vec3(0, 0, 0), nil, TROLL.root)
end
local function over_lava(x) return x < PLATS[1][1] - 0.3 or x > PLATS[1][2] + 0.3 end
local function update_troll(dt, active)
    local T = TROLL
    T.cool = T.cool - dt
    if T.state == "idle" then
        T.y = LAVA_Y - 6
        if active and T.cool <= 0 then
            local cands = { P }
            for _, e in ipairs(enemies) do cands[#cands + 1] = e end
            for _, r in ipairs(cands) do
                if r.alive and r.spawn <= 0 and r.y - FEET < -8.6 and over_lava(r.x) and not r.ground and (r ~= P or P.inv <= 0) then
                    T.state = "rise"; T.target = r; T.x = r.x; T.t = 0; sfx("lava")
                    burst(r.x, LAVA_Y + 0.3, { c0 = vec4(3, 1.3, .3, 1), c1 = vec4(1, .2, 0, 0), count = 50, smin = .06, smax = .18, lmin = .4, lmax = 1.0, radius = .8, spread = 10, drag = 1.5, grav = vec3(0, -9, 0) })
                    break
                end
            end
        end
    elseif T.state == "rise" then
        T.t = T.t + dt
        local r = T.target
        T.x = damp(T.x, r.x, 6, dt)
        T.y = min(T.y + 22 * dt, LAVA_Y + 1.5)
        if r.alive and abs(wrapd(r.x - T.x)) < 1.4 and r.y - FEET < T.y + 3.0 then
            T.state = "grab"; T.grip = r == P and 1.0 or 0.6; r.grab = T; sfx("grab")
        elseif T.t > 1.2 or not r.alive then T.state = "sink"; T.t = 0 end
    elseif T.state == "grab" then
        local r = T.target
        T.y = T.y - 2.2 * dt
        if not r.alive then T.state = "sink"
        else
            r.x = T.x; r.y = T.y + 2.9 + FEET; r.vx = 0; r.vy = 0; r.ground = false
            if T.grip <= 0 then r.grab = nil; r.vy = 6; T.state = "sink"; T.cool = 2.5; T.t = 0; shockwave(T.x, T.y + 1.5, { 1, .5, .2 }, 2.2, 0.35) end
        end
    elseif T.state == "sink" then
        T.y = T.y - 10 * dt
        if T.y < LAVA_Y - 6 then T.state = "idle"; T.cool = max(T.cool, 1.5) end
    end
    if T.state == "idle" then T.root:set_position(HIDE)
    else
        T.root:set_position(vec3(T.x, T.y, 0.8)); T.root:set_rotation(vec3(0, 0, sin(G.t * 6) * 6)); T.root:set_scale(vec3(1.7, 1.7, 1.7))
        if rand() < 0.5 then burst(T.x, LAVA_Y + 0.2, { c0 = vec4(2.5, 1, .2, 1), c1 = vec4(1, .2, 0, 0), count = 3, smin = .05, smax = .12, lmin = .3, lmax = .6, radius = .6, spread = 4, drag = 1, grav = vec3(0, -4, 0) }) end
    end
end

------------------------------------------------------------------ collider debug overlay (F3)
-- Thin emissive bars drawn in front of the scene; every point is pulled along its camera ray to z = DBG_Z,
-- so the outline lands exactly on top of the z = 0 gameplay plane in the image.
G.DBG = { on = false, pool = {}, used = 0, z = 2.4, w = 0.11 }
G.DBG_COL = { mount = { .2, 1, .3 }, legs = { .2, 1, .3 }, rider = { .3, .8, 1 }, lance = { 1, .9, .2 }, tip = { 1, .2, .15 }, egg = { 1, .55, .1 }, ledge = { .1, 1, 1 }, st = { .1, 1, 1 } }
function G.dbg_bar(x0, y0, x1, y1, col, zsrc)
    local D = G.DBG
    D.used = D.used + 1
    local b = D.pool[D.used]
    if not b then
        if #D.pool >= 3000 then return end
        b = { n = prim("cube", HIDE, vec3(1, 1, 1)), col = nil }
        D.pool[D.used] = b
    end
    if b.col ~= col then
        b.col = col
        paint(b.n, { col[1] * .3, col[2] * .3, col[3] * .3 }, { col[1] * 1.4, col[2] * 1.4, col[3] * 1.4 }, 0.5, 0)
    end
    local c = cam:get_position()
    zsrc = zsrc or 0
    local k = (c.z - D.z) / (c.z - zsrc)
    local ax, ay = c.x + (x0 - c.x) * k, c.y + (y0 - c.y) * k
    local bx, by = c.x + (x1 - c.x) * k, c.y + (y1 - c.y) * k
    local dx, dy = bx - ax, by - ay
    local L = sqrt(dx * dx + dy * dy)
    b.n:set_position(vec3((ax + bx) * .5, (ay + by) * .5, D.z))
    b.n:set_rotation(vec3(0, 0, math.deg(atan2(dy, dx))))
    b.n:set_scale(vec3(L + G.DBG.w, G.DBG.w, G.DBG.w))
end
function G.dbg_cap(s, col)
    local ax, ay, bx, by, ra, rb = s[1], s[2], s[3], s[4], s[5], s[6]
    local dx, dy = bx - ax, by - ay
    local L = sqrt(dx * dx + dy * dy)
    local base = L > 1e-4 and atan2(dy, dx) or 0
    local nx, ny = -sin(base), cos(base)
    if L > 1e-4 then
        G.dbg_bar(ax + nx * ra, ay + ny * ra, bx + nx * rb, by + ny * rb, col)
        G.dbg_bar(ax - nx * ra, ay - ny * ra, bx - nx * rb, by - ny * rb, col)
    end
    local N = 7
    for side = 0, 1 do
        local cx, cy, r = side == 0 and ax or bx, side == 0 and ay or by, side == 0 and ra or rb
        local a0 = base + (side == 0 and PI * 0.5 or -PI * 0.5)
        local span = (L > 1e-4) and PI or TAU
        if L <= 1e-4 and side == 1 then break end
        local n = (L > 1e-4) and N or N * 2
        for i = 0, n - 1 do
            local u0, u1 = a0 + span * i / n, a0 + span * (i + 1) / n
            G.dbg_bar(cx + cos(u0) * r, cy + sin(u0) * r, cx + cos(u1) * r, cy + sin(u1) * r, col)
        end
    end
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on then
        local function rider(r) if r.alive then for _, s in ipairs(G.rider_shapes(r)) do G.dbg_cap(s, G.DBG_COL[s[7]]) end end end
        rider(P)
        for _, e in ipairs(enemies) do rider(e) end
        for _, g in ipairs(EGGS) do if g.live then G.dbg_cap(G.egg_shapes(g)[1], G.DBG_COL.egg) end end
        for i, pl in ipairs(PLATS) do
            local cx, pc = (pl[1] + pl[2]) * .5, G.PLAT_COL[i]
            local col = G.DBG_COL.ledge
            G.dbg_bar(pl[1], pl[3], pl[2], pl[3], col)
            local fy = pl[3] + G.ledge_under(i, 0)
            G.dbg_bar(pl[1], fy, pl[2], fy, col)
            G.dbg_bar(pl[1], pl[3], pl[1], fy, col); G.dbg_bar(pl[2], pl[3], pl[2], fy, col)
        end
    end
    for i = D.used + 1, #D.pool do local b = D.pool[i]; if not b.hidden then b.n:set_position(HIDE); b.hidden = true end end
    for i = 1, D.used do D.pool[i].hidden = false end
end
------------------------------------------------------------------ combat
local survived = true
local function unseat(e)
    if not e.alive then return end
    explode(e.x, e.y + 0.8, KCOL[e.kind], KSLOT[e.kind], e.kind == "shadow")
    sfx("boom"); add_score(SPEC[e.kind].pts, e.x, e.y + 2.5)
    drop_egg(e)
    despawn(e)
end
local function burn(r)
    burst(r.x, LAVA_Y + 0.4, { c0 = vec4(3, 1.4, .3, 1), c1 = vec4(1, .2, 0, 0), count = 60, smin = .06, smax = .2, lmin = .4, lmax = 1.1, radius = .6, spread = 12, drag = 1.5, grav = vec3(0, -9, 0) })
    flash(r.x, LAVA_Y + 1, { 1, .5, .15 }, 80, 0.5, 10); sfx("lava")
    if r == P then P.burned = true end
end
local function player_die()
    if not P.alive or P.inv > 0 then return end
    P.alive = false; P.dead_t = 0; survived = false
    explode(P.x, P.y + 0.8, KCOL.player, 3, true)
    hide_rider(P); sfx("death"); add_shake(0.9)
    if TROLL.target == P then TROLL.state = "sink" end
    P.grab = nil
end
local function clash_fx(x, y)
    burst(x, y, { c0 = vec4(3.5, 3.2, 2.6, 1), c1 = vec4(1.5, .8, .3, 0), count = 40, smin = .03, smax = .08, lmin = .15, lmax = .4, radius = .1, spread = 30, drag = 3 })
    shockwave(x, y, { 1, .9, .7 }, 1.8, 0.25); flash(x, y, { 1, .9, .7 }, 45, 0.2, 7); add_shake(0.1); sfx("clash")
end
local function joust(a, b)   -- returns winner or nil (bounce)
    local dx = wrapd(b.x - a.x)
    -- contact uses the mesh-matched compound colliders: lance/tip, rider, mount, legs (see G.COL)
    if not G.riders_touch(a, b) then return false end
    local d = a.y - b.y   -- the higher lance (riders share the same lance height offset) wins
    if d > 0.35 then return a, b elseif d < -0.35 then return b, a end
    -- even: lances clash, both bounce apart
    local s = dx > 0 and -1 or 1
    a.vx = s * max(5, abs(a.vx)); b.vx = -s * max(5, abs(b.vx)); a.vy = max(a.vy, 3); b.vy = max(b.vy, 3)
    a.x = wrapx(a.x + s * 0.3); b.x = wrapx(b.x - s * 0.3)
    a.ground, b.ground = false, false
    clash_fx(a.x + dx / 2, (a.y + b.y) / 2 + 1.5)
    return nil
end
local function update_combat()
    if P.alive and P.spawn <= 0 then
        for i = #enemies, 1, -1 do
            local e = enemies[i]
            if e and e.alive and e.spawn <= 0 then
                local w, l = joust(P, e)
                if w == P then clash_fx(l.x, l.y + 1.5); unseat(l)
                elseif w == e then if P.inv <= 0 then clash_fx(P.x, P.y + 1.5); player_die() end end
            end
        end
    end
    for i = 1, #enemies do for j = i + 1, #enemies do
        local a, b = enemies[i], enemies[j]
        local dx = wrapd(b.x - a.x)
        if abs(dx) < 6 and abs(b.y - a.y) < 4 and G.group_hit(G.rider_shapes(a), G.rider_shapes(b), G.BODY, G.BODY, dx - (b.x - a.x)) then
            local s = dx > 0 and -1 or 1
            a.vx = s * abs(a.vx) + s; b.vx = -s * abs(b.vx) - s; a.ai_dir = s; b.ai_dir = -s; a.face = s; b.face = -s
        end
    end end
end

------------------------------------------------------------------ AI (enemies; also drives the attract-mode player)
local function ai_control(r, dt, target)
    local s = SPEC[r.kind]
    local c = { h = 0, flap = false }
    r.ai_t = r.ai_t - dt
    if r.ai_t <= 0 then
        r.ai_t = rr(1.0, 2.6)
        if r.kind == "bounder" then r.ai_y = rr(-7, 11); if rand() < 0.35 then r.ai_dir = -r.ai_dir end
        else r.ai_y = target and (target.y + (r.kind == "shadow" and 2.2 or 1.2) + rr(-1.5, 1.5)) or rr(-6, 10) end
    end
    local ty = r.ai_y
    if target and target.alive and r.kind ~= "bounder" then
        local dx = wrapd(target.x - r.x)
        r.ai_dir = dx > 0 and 1 or -1
        if abs(dx) < 6 then ty = target.y + (r.kind == "shadow" and 1.6 or 0.9) end
    end
    -- never skim the lava; climb out from under ledges
    if r.y - FEET < -8 and over_lava(r.x) then ty = max(ty, -3) end
    c.h = r.ai_dir
    r.hold_t = r.hold_t - dt
    local low = r.y - FEET < -6.5 and over_lava(r.x)
    if (r.y < ty or (low and r.vy < 2)) and r.hold_t <= 0 then c.flap = true; r.hold_t = (s.cd or 0.25) * (low and 0.7 or rr(0.8, 1.25)) end
    if r.ground and r.hold_t <= 0 and rand() < dt * 1.5 then c.flap = true; r.hold_t = 0.3 end
    return c
end

------------------------------------------------------------------ waves
local W = { queue = {}, t = 0, intro = 0 }
local function start_wave()
    wave = wave + 1; survived = true; egg_chain = 0
    local n = min(8, 2 + wave)
    W.queue = {}
    for i = 1, n do
        local k = "bounder"
        local r = rand()
        if wave >= 3 and r < min(0.6, 0.12 * (wave - 1)) then k = "hunter" end
        if wave >= 5 and r < min(0.35, 0.06 * (wave - 3)) then k = "shadow" end
        W.queue[i] = k
    end
    W.t = 1.2
    local sub = wave % 5 == 0 and "Egg wave: grab every egg" or (wave >= 2 and "Watch the lava troll" or "Strike from above")
    show_banner("Wave " .. wave, sub, 2.4); sfx("wave")
end
local pad_i = 1
local function update_waves(dt, st)
    if #W.queue > 0 then
        W.t = W.t - dt
        if W.t <= 0 then
            pad_i = pad_i % #PADS + 1
            local pd = PADS[pad_i]
            if pad_i == 1 and P.alive and abs(P.x) < 4 then pad_i = 2; pd = PADS[2] end
            spawn_enemy(table.remove(W.queue, 1), pd[1], pd[2])
            W.t = 0.9
        end
    elseif #enemies == 0 and eggs_live() == 0 then
        if survived and st == "play" then add_score(3000); popup(0, 4, "Survival bonus 3000", { .6, .9, 1 }) end
        start_wave()
    end
end

------------------------------------------------------------------ per-frame rider updates
local AUTO = { on = false }
local function nearest_enemy(r)
    local best, bd = nil, 1e9
    for _, e in ipairs(enemies) do if e.alive and e.spawn <= 0 then local d = abs(wrapd(e.x - r.x)) + abs(e.y - r.y); if d < bd then bd, best = d, e end end end
    return best
end
local function update_player(dt, ctl)
    if not P.alive then P.dead_t = P.dead_t + dt; emitter_at(P.trail, 0, -1000, 0, 0); set_point(L.player, HIDE, vec3(1, 1, 1), 0, 1); return end
    P.inv = max(0, P.inv - dt)
    P.spawn = max(0, P.spawn - dt * 2.5)
    if P.grab then
        if ctl.flap then P.grab.grip = P.grab.grip - 0.2; P.wingv = 1; P.flap_t = 0; sfx("flap"); burst(P.x, P.y + 1, { c0 = vec4(1.4, 1.3, 1.2, .8), c1 = vec4(.5, .5, .5, 0), count = 6, smin = .04, smax = .1, lmin = .2, lmax = .4, radius = .5, spread = 4, drag = 3 }) end
    else rider_physics(P, ctl, dt) end
    if P.y - FEET < LAVA_Y + 0.2 then burn(P); P.inv = 0; player_die(); return end
    rider_anim(P, dt)
    local spd = sqrt(P.vx * P.vx + P.vy * P.vy)
    emitter_at(P.trail, P.x + 3.2 * (P.face > 0 and 1 or -1), P.y + 1.6, -0.3, P.ground and 0 or min(60, spd * 5))
    set_point(L.player, vec3(P.x, P.y + 1.5, 3), vec3(0.55, 0.8, 1.0), 7, 7)
    local f = P.inv > 0 and (0.5 + 0.5 * sin(G.t * 18)) or 0
    mlive(tnode("T_player_trim"), "emissive", vec3(0.1 + f * 1.2, 0.25 + f * 1.6, 0.7 + f * 2.0))
end
local function update_enemies(dt)
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        if e and e.alive then
            e.spawn = max(0, e.spawn - dt * 2.0)
            if e.grab then
                e.grab.grip = e.grab.grip - dt * 0.15
            elseif e.spawn <= 0 then
                rider_physics(e, ai_control(e, dt, P.alive and P or nil), dt)
            end
            if e.y - FEET < LAVA_Y + 0.2 then burn(e); if TROLL.target == e then TROLL.state = "sink" end; despawn(e)
            else rider_anim(e, dt) end
        end
    end
end

------------------------------------------------------------------ camera
local shake_t = 0
local function update_camera(dt)
    shake = max(0, shake - dt * 2.0); shake_t = shake_t + dt
    local a = shake * shake * 0.9 * SET:shake_scale()
    local ox, oy = a * (sin(shake_t * 53) + 0.5 * sin(shake_t * 97)), a * (cos(shake_t * 61) + 0.5 * sin(shake_t * 83))
    local sway = sin(G.t * 0.17) * 0.6
    if G.cam_ov then local o = G.cam_ov; cam:set_position(vec3(o[1], o[2], o[3])); cam:look_at(vec3(o[4], o[5], 0)); return end
    cam:set_position(vec3(ox + sway, CAMY + 2.0 + oy, CAMZ)); cam:look_at(vec3(ox * 0.5 + sway * 0.5, CAMY + oy * 0.5, 0))
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
    quad(id, { x = x, y = y, w = w, h = h, z = 4, style = "text", label = "", fill = { 0.04, 0.03, 0.03, a or 0.55 },
        border = border or { 0.95, 0.7, 0.4, 0.5 }, corner_radius = 12 * US, no_input = true, visible = vis ~= false })
end
local function button(id, label, cx, cy, vis)
    local w, h = 330 * US, 60 * US
    local st = vis and select(2, pcall(runtime_ui.get_state, UI, id))
    local hov = type(st) == "table" and st.hovered
    quad(id, { x = cx - w / 2, y = cy - h / 2, w = w, h = h, z = 12, style = "text", label = label,
        fill = hov and { 0.3, 0.2, 0.1, 0.92 } or { 0.08, 0.06, 0.05, 0.85 }, border = hov and { 1, 0.8, 0.45, 1 } or { 0.8, 0.6, 0.35, 0.9 },
        text_color = hov and { 1, 0.95, 0.85, 1 } or { 0.95, 0.9, 0.82, 1 }, font_scale = 1.25 * US, align_h = "center", align_v = "middle",
        corner_radius = 12 * US, visible = vis })
    return vis and type(st) == "table" and st.clicked
end
local function fmt(n) local s = tostring(floor(n)); return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end
local AC, AC2, DIM = { 1, 0.85, 0.55, 1 }, { 0.6, 0.85, 1, 1 }, { 0.78, 0.74, 0.7, 1 }
local function to_screen(x, y) return SW / 2 + x / HW * SW / 2, SH / 2 - (y - CAMY) / VIEW_HH * SH / 2 end
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause" or st == "over") and not set_open
    panel("hud_l", 20 * US, 14 * US, 360 * US, 96 * US, play, 0.4)
    text("score", fmt(score), 40 * US, 18 * US, 330 * US, 50 * US, 2.0, AC, "left", play)
    text("hi", "Best " .. fmt(max(hiscore, score)), 40 * US, 64 * US, 330 * US, 34 * US, 1.0, DIM, "left", play)
    panel("hud_r", SW - 380 * US, 14 * US, 360 * US, 96 * US, play, 0.4)
    text("wave", "Wave " .. wave, SW - 370 * US, 18 * US, 330 * US, 46 * US, 1.6, AC2, "right", play)
    for i = 1, 8 do
        local vis = play and i <= lives
        quad("life" .. i, { x = SW - 70 * US - (i - 1) * 30 * US, y = 70 * US, w = 20 * US, h = 20 * US, z = 6, style = "text", label = "",
            fill = { 1, 0.82, 0.4, 0.95 }, border = { 1, 0.95, 0.8, 1 }, corner_radius = 10 * US, no_input = true, visible = vis })
    end
    -- score popups
    for i, p in ipairs(POP) do
        p.t = p.t + dt
        local vis = st == "play" and not set_open and p.t < 1.1
        local px, py = 0, 0
        if vis then px, py = to_screen(p.x, p.y + p.t * 1.5) end
        local a = floor(clamp((1.1 - p.t) / 0.4, 0, 1) * 10) / 10
        text("pop" .. i, p.txt or "", px - 200 * US, py - 20 * US, 400 * US, 40 * US, 1.15, { p.col and p.col[1] or 1, p.col and p.col[2] or 1, p.col and p.col[3] or 1, a }, "center", vis)
    end
    banner.t = banner.t - dt
    local ba = clamp(banner.t / 0.4, 0, 1)
    text("ban", banner.text, 0, SH * 0.33, SW, 80 * US, 2.6, { 1, .88, .6, floor(ba * 20) / 20 }, "center", st == "play" and not set_open and banner.t > 0)
    text("bans", banner.sub, 0, SH * 0.33 + 70 * US, SW, 40 * US, 1.2, { .8, .9, 1, floor(ba * 20) / 20 }, "center", st == "play" and not set_open and banner.t > 0)
    -- title
    local title = st == "title" and not set_open
    panel("t_bg", SW / 2 - 470 * US, SH * 0.1, 940 * US, SH * 0.74, title, 0.5)
    text("t_title", "Joust Remix", 0, SH * 0.13, SW, 130 * US, 4.6, { 1, 0.86, 0.55, 1 }, "center", title)
    text("t_sub", "Fly high, strike from above, and claim every egg", 0, SH * 0.13 + 118 * US, SW, 40 * US, 1.15, DIM, "center", title)
    text("t_ctl1", "A / D or arrows: move   ·   Space / W / Up: flap (hold to keep flapping)", 0, SH * 0.66, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_ctl2", "P / Esc: pause   ·   O: settings   ·   M: mute   ·   F3: colliders   ·   Mouse: click any button", 0, SH * 0.66 + 34 * US, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_hi", "Best score " .. fmt(hiscore), 0, SH * 0.66 + 78 * US, SW, 36 * US, 1.1, AC2, "center", title)
    local pause = st == "pause" and not set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.3, 600 * US, SH * 0.42, pause, 0.7)
    text("p_t", "Paused", 0, SH * 0.32, SW, 80 * US, 2.6, AC, "center", pause)
    local over = st == "over" and not set_open
    panel("o_bg", SW / 2 - 360 * US, SH * 0.26, 720 * US, SH * 0.5, over, 0.7, { 1, 0.5, 0.3, 0.6 })
    text("o_t", "Game Over", 0, SH * 0.28, SW, 90 * US, 3.0, { 1, .6, .4, 1 }, "center", over)
    text("o_s", "Score " .. fmt(score) .. "  ·  Wave " .. wave, 0, SH * 0.28 + 90 * US, SW, 40 * US, 1.3, DIM, "center", over)
    local c = {}
    local span = 346 * US
    c.start = button("b_start", "Start (Enter)", SW / 2 - span / 2, SH * 0.43, title)
    c.jev = button("b_jev", "Jev", SW / 2 + span / 2, SH * 0.43, title)
    c.set_t = button("b_set_t", "Settings (O)", SW / 2, SH * 0.43 + 76 * US, title)
    c.quit_app = button("b_quit_app", "Quit Game", SW / 2, SH * 0.43 + 152 * US, title)
    c.resume = button("b_resume", "Resume (P)", SW / 2, SH * 0.44, pause)
    c.set_p = button("b_set_p", "Settings (O)", SW / 2, SH * 0.44 + 76 * US, pause)
    c.quit = button("b_quit", "Quit to Title (Q)", SW / 2, SH * 0.44 + 152 * US, pause)
    local ov = over and (G.over_t or 0) > 1.2
    c.again = button("b_again", "Play Again (Enter)", SW / 2, SH * 0.5, ov)
    c.title = button("b_title", "Title (Esc)", SW / 2, SH * 0.5 + 76 * US, ov)
    return c
end

------------------------------------------------------------------ game flow
local function clear_world()
    for i = #enemies, 1, -1 do despawn(enemies[i]) end
    for _, g in ipairs(EGGS) do kill_egg(g) end
    TROLL.state = "idle"; TROLL.target = nil; TROLL.cool = 4
end
local function reset_player()
    local pd = PADS[1]
    P.alive = true; P.x, P.y = pd[1], pd[2] + FEET; P.vx, P.vy = 0, 0; P.ground = true; P.grab = nil
    P.inv = 2.5; P.spawn = 1; P.face = 1; P.yaw = -12; P.burned = false
    spawn_fx(pd[1], pd[2], KCOL.player)
end
local function new_game(attract)
    clear_world()
    score, lives, wave, next_extra = 0, 4, 0, 20000
    reset_player()
    AUTO.on = attract or false
    G.state = attract and "title" or "play"
    W.queue = {}
    start_wave()
    if not attract then sfx("start") end
end
local function to_title()
    G.jev:begin_human()
    new_game(true)
    G.state = "title"
end
local function autopilot()
    local c = { h = 0, flap = false }
    local e = nearest_enemy(P)
    local ty = 4
    if e then
        local dx = wrapd(e.x - P.x); c.h = dx > 0 and 1 or -1; ty = e.y + 1.4
    else c.h = P.face end
    if P.y - FEET < -8 and over_lava(P.x) then ty = 0 end
    P.hold_t = P.hold_t - G.dt
    if P.y < ty and P.hold_t <= 0 then c.flap = true; P.hold_t = rr(0.2, 0.3) end
    return c
end
local flap_hold = 0
local function update(dt)
    flush_mats()
    dt = min(dt, 1 / 20)
    G.t = G.t + dt; G.dt = dt
    G.poll_human()
    G.jev:tick(dt)
    local k = { ret = edge("Return"), space = edge("Space"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), q = edge("Q"),
        up = edge("Up"), w = edge("W"), f3 = edge("F3") }
    if k.f3 then G.DBG.on = not G.DBG.on end
    set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if set_open then for kk in pairs(k) do k[kk] = false end end
    local function open_settings() sfx("click"); SET:open(); set_open = true end
    if k.m then SET:toggle_mute() end
    local consumed = false
    if st == "title" then
        if (k.ret or k.space or c.start) then
            sfx("click")
            G.jev:begin_human()
            new_game(false)
            consumed = true
        elseif c.jev then
            local started = G.jev:start()
            if not started then
                local err = G.jev:error() or "Jev could not start"
                G.jev:begin_human()
                show_banner("Jev", err, 4)
                pe_log("[Joust] " .. err)
            end
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click") end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.q or c.quit then to_title() end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then
                sfx("click")
                G.jev:begin_human()
                new_game(false)
                consumed = true
            elseif k.esc or c.title then
                to_title()
            end
        end
    end
    st = G.state
    local running = (st == "play" or st == "title" or st == "over") and not (set_open and st ~= "title") and not G.freeze
    if running then
        local ctl
        if AUTO.on or st ~= "play" then ctl = autopilot()
        else
            local fl = any("Space", "W", "Up", "J")
            local press = (k.space or k.w or k.up) and not consumed
            flap_hold = fl and (flap_hold + dt) or 0
            local auto_flap = fl and flap_hold > 0.2 and ((flap_hold - 0.2) % 0.19) < dt
            ctl = { h = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0), flap = press or auto_flap }
        end
        if st == "over" then ctl = { h = 0, flap = false } end
        update_player(dt, ctl)
        update_enemies(dt)
        update_combat()
        update_eggs(dt)
        update_troll(dt, wave >= 2 or st == "title")
        if st ~= "over" then update_waves(dt, st) end
        if not P.alive and st ~= "over" and P.dead_t > 2.0 then
            if st == "title" then reset_player()
            else
                lives = lives - 1
                if lives <= 0 then
                    G.state = "over"; G.over_t = 0; sfx("gameover")
                    if score > hiscore and not G.jev:assisted() then
                        hiscore = score
                        save_hi()
                    end
                else reset_player() end
            end
        end
    end
    if G.freeze then rider_anim(P, 0); for _, e in ipairs(enemies) do if e.alive then rider_anim(e, 0) end end end   -- automation: hold the pose
    update_camera(dt)
    update_world(dt)
    update_beam(dt)
    update_shards(dt); update_feathers(dt); update_rings(dt); update_flashes(dt)
    G.dbg_draw()
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_world()
build_debris(); build_rings(); build_feathers()
build_riders(); build_eggs(); build_troll()

G.clear_vk = function()
    G.vk.Left = nil
    G.vk.Right = nil
    G.vk.Space = nil
end

G.jev_actions = {
    { id = "left", description = "Hold left" },
    { id = "right", description = "Hold right" },
    { id = "stop", description = "Release move and flap" },
    { id = "flap", description = "Hold flap" },
    { id = "left_flap", description = "Hold left and flap" },
    { id = "right_flap", description = "Hold right and flap" },
}

G.jev = assert(load(assert(fs.read("Scripts/jev_auto.lua")), "@Scripts/jev_auto.lua", "t", _ENV))().attach({
    port = 9127,
    id = "joust-remix",
    description = "Joust Remix. Hold left or right to move, and hold flap to fly. Strike enemies from above.",
    playing = function()
        return G.state == "play" and not set_open
    end,
    terminal = function()
        return G.state == "over"
    end,
    score = function()
        return score
    end,
    busy = function()
        return false
    end,
    human_edge = function()
        return G.human_hit
    end,
    observe = function()
        local enemy = nearest_enemy(P)
        local enemy_x = 0
        local enemy_y = 0
        if enemy then
            enemy_x = enemy.x
            enemy_y = enemy.y
        end

        return {
            player_x = P.x,
            player_y = P.y,
            vertical_speed = P.vy,
            nearest_enemy_x = enemy_x,
            nearest_enemy_y = enemy_y,
            has_enemy = enemy ~= nil,
            lives = lives,
            score = score,
        }
    end,
    actions = function()
        local enemy = nearest_enemy(P)
        local dx = 0
        local above = true
        if enemy then
            dx = enemy.x - P.x
            above = enemy.y > P.y + 0.4
        end
        if dx > 0.5 then
            return { { id = "right_flap", description = "Fly right and flap.", score = dx } }
        end
        if dx < -0.5 then
            return { { id = "left_flap", description = "Fly left and flap.", score = -dx } }
        end
        if above then
            return { { id = "flap", description = "Flap to climb toward the enemy.", score = 1 } }
        end
        return { { id = "stop", description = "Level with the enemy.", score = 1 } }
    end,
    apply = function(id)
        local left = id == "left" or id == "left_flap"
        local right = id == "right" or id == "right_flap"
        local flap = id == "flap" or id == "left_flap" or id == "right_flap"
        G.vk.Left = left or nil
        G.vk.Right = right or nil
        G.vk.Space = flap or nil
    end,
    reset = function(seed)
        math.randomseed(seed)
        G.clear_vk()
        new_game(false)
    end,
    on_human = function()
        G.clear_vk()
    end,
})
to_title()
G.spawn = spawn_enemy; G.P = P; G.new_game = new_game; G.to_title = to_title; G.AUTO = AUTO; G.unseat = unseat; G.EGGS = EGGS; G.drop_egg = drop_egg
G.SET = SET; G.state_set = function(s) G.state = s; G.over_t = 5 end
G.info = function() return score, lives, wave end
G.TROLL = TROLL; G.explode = explode; G.clash = clash_fx; G.joust = joust
G.update = update; G.PLATS = PLATS; G.FEET = FEET
hooks { update = update }
pe_log("[Joust] ready  camz " .. floor(CAMZ))
