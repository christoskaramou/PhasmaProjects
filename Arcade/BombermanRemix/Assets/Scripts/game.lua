-- BOMBERMAN REMIX  (PhasmaEngine, Lua)
-- A faithful modern remake of Hudson Soft's Bomberman (NES/arcade, 1983-85): a 31 x 13 maze of concrete pillars and
-- brick walls, bombs with cross-shaped blasts and chain reactions, the eight classic enemies, eight power-ups,
-- a hidden exit door per stage, a 200 second timer and 50 stages. Fixed 60 Hz simulation with capped catch-up.
-- World: ground = XZ plane, one cell = 2 units, cell (c, r) centre = (c * 2, 0, r * 2); c 0..32, r 0..14 incl. border.
local PI = math.pi
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
math.randomseed(os and os.time and os.time() or 1985)
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local G = { state = "boot", t = 0 }
_G.BM = G
local CS, NC, NR = 2, 31, 13

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
local function paint(n, base, emis, rough, metal)
    if not n then return end
    mset(n, "base_color", vec4(base[1], base[2], base[3], 1))
    mset(n, "emissive", vec3(emis[1], emis[2], emis[3]))
    mset(n, "roughness", rough or 0.4)
    mset(n, "metallic", metal or 0.0)
end
local function sfx(name) pcall(audio.play, name .. ".wav") end
G.music_cur = nil
local function music(name)
    if G.music_cur == name then return end
    G.music_cur = name
    pcall(audio.stop_music)
    if name then pcall(audio.play_music, name .. ".wav") end
end

------------------------------------------------------------------ render setup (see /workspace/games/common/RENDER_SETTINGS.md)
local function S(k, v) pcall(settings.set, k, v) end
local ss = scene.add_empty_node("BomberSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "day.hdr")
S("hdr", false); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false); S("dof", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.2)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", true); S("IBL_intensity", 0.55)
S("color_grading", true); S("color_grading_saturation", 1.05); S("color_grading_contrast", 1.04)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "SETTINGS", subtitle = "Bomberman Remix", file = "Save/settings.cfg", music = true,
    click = function() sfx("click") end, defaults = { master = 0.5 },
    theme = { accent = { 0.35, 0.75, 1, 1 }, accent2 = { 1, 0.55, 0.3, 1 }, text = { 0.86, 0.84, 0.8, 1 }, selected_text = { 1, 0.97, 0.9, 1 } } })
SET:apply()
G.set_open = false

------------------------------------------------------------------ camera (tilted top-down, follows the player along X)
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1600, surf.height or 900
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local VFOV = math.rad(40)
local FOVX = 2 * math.atan(math.tan(VFOV / 2) * SW / SH)
pcall(function() cam:set_fov(math.deg(FOVX)) end)
G.cam = { x = 16, y = 30, z = 32, tx = 16, tz = 15.5 }
local function project(p)          -- world -> screen pixels using the live camera
    local c = cam:get_position(); local C = G.cam
    local fx, fy, fz = C.tx - c.x, 0 - c.y, C.tz - c.z
    local fl = sqrt(fx * fx + fy * fy + fz * fz); fx, fy, fz = fx / fl, fy / fl, fz / fl
    local rx, ry, rz = -fz, 0, fx; local rl = sqrt(rx * rx + rz * rz); rx, rz = rx / rl, rz / rl
    local ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
    local dx, dy, dz = p.x - c.x, p.y - c.y, p.z - c.z
    local zc = dx * fx + dy * fy + dz * fz
    if zc < 0.1 then return -9999, -9999 end
    local th = math.tan(VFOV / 2)
    return SW / 2 + (dx * rx + dy * ry + dz * rz) / (zc * th) * SH / 2, SH / 2 - (dx * ux + dy * uy + dz * uz) / (zc * th) * SH / 2
end
------------------------------------------------------------------ templates -> clones
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[BM] missing template " .. name); return nil end
    TPL[name] = { node = n, mesh = n:get_mesh_refs()[1] }
    return TPL[name]
end
local seq = 0
local HIDE = vec3(0, -1000, 0)
local function clone(name, pos, scale, parent)
    local t = tpl("T_" .. name); seq = seq + 1
    local n = scene.add_empty_node(name .. "_c" .. seq)
    if t and t.mesh then n:add_mesh_ref(t.mesh) end
    if parent then n:set_parent(parent) end
    n:set_position(pos or HIDE)
    if scale then n:set_scale(scale) end
    return n
end
local function empty(name, parent, pos)
    seq = seq + 1
    local n = scene.add_empty_node(name .. "_e" .. seq)
    if parent then n:set_parent(parent) end
    n:set_position(pos or vec3(0, 0, 0))
    return n
end
local function prim(kind, pos, scale)
    seq = seq + 1
    local n = scene.add_empty_node(kind .. "_p" .. seq)
    scene.attach_primitive(n, kind)
    n:set_position(pos); n:set_scale(scale)
    return n
end
local function tnode(name) local t = tpl("T_" .. name); return t and t.node end
-- pools for stage geometry and props: P_get(kind) hands out clones, P_end(kind) hides the rest
local POOL = {}
local function P_begin(kind) local p = POOL[kind]; if not p then p = { n = {}, used = 0 }; POOL[kind] = p end; p.used = 0 end
local function P_get(kind)
    local p = POOL[kind]; if not p then P_begin(kind); p = POOL[kind] end
    p.used = p.used + 1
    local n = p.n[p.used]
    if not n then n = clone(kind); p.n[p.used] = n end
    return n
end
local function P_end(kind) local p = POOL[kind]; if not p then return end; for i = p.used + 1, #p.n do p.n[i]:set_position(HIDE) end end

------------------------------------------------------------------ lights
local LIGHT_GAIN = 0.12
local LNODE = {}
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
------------------------------------------------------------------ input
local prev = {}
local keyfn = input.is_key_down_raw or input.is_key_pressed
local function held(k) if G.vk and G.vk[k] then return true end local ok, v = pcall(keyfn, k); return ok and v end
local function edge(k) local d = held(k); local p = prev[k]; prev[k] = d; return d and not p end
local function any(...) for _, k in ipairs({ ... }) do if held(k) then return true end end; return false end

------------------------------------------------------------------ palette {base, emissive, rough, metal}
local function paint_templates()
    local P = {
        bm_helmet = { { .93, .93, .95 }, { .02, .02, .02 }, .35 }, bm_face = { { 1, .72, .62 }, { .02, .01, .01 }, .5 },
        bm_eye = { { .03, .03, .06 }, { 0, 0, 0 }, .2 }, bm_antenna = { { .85, .85, .9 }, { 0, 0, 0 }, .4, .3 },
        bm_knob = { { 1, .3, .55 }, { .12, .02, .05 }, .3 }, bm_body = { { .15, .35, .9 }, { .01, .02, .05 }, .45 },
        bm_belt = { { .1, .1, .12 }, { 0, 0, 0 }, .4 }, bm_arm = { { .15, .35, .9 }, { .01, .02, .05 }, .45 },
        bm_glove = { { .95, .95, .97 }, { .02, .02, .02 }, .45 }, bm_leg = { { .15, .35, .9 }, { .01, .02, .05 }, .45 },
        bm_boot = { { 1, .35, .55 }, { .03, .01, .015 }, .45 },
        bomb = { { .07, .07, .1 }, { 0, 0, 0 }, .22, .2 }, bomb_cap = { { .5, .5, .55 }, { 0, 0, 0 }, .3, .8 },
        bomb_fuse = { { .85, .75, .55 }, { .05, .03, 0 }, .7 }, bomb_shine = { { 1, 1, 1 }, { 1.2, 1.2, 1.2 }, .1 },
        floor = { { .9, .9, .9 }, { 0, 0, 0 }, .85 }, pillar = { { .55, .56, .6 }, { .005, .005, .005 }, .75 },
        pillar_top = { { .62, .63, .67 }, { .005, .005, .005 }, .65 }, brick = { { .85, .8, .78 }, { .005, .003, .003 }, .8 }, brick_chunk = { { .78, .7, .66 }, { .004, .002, .002 }, .85 },
        border = { { .7, .7, .74 }, { 0, 0, 0 }, .8 },
        door_frame = { { .55, .55, .6 }, { 0, 0, 0 }, .5, .6 }, door = { { .3, .3, .36 }, { .02, .02, .03 }, .4, .5 },
        door_light = { { .9, .95, 1 }, { .6, .8, 1.1 }, .3 },
        fl_core = { { 1, .75, .3 }, { 1.7, .95, .25 }, .5 }, fl_arm = { { 1, .35, .05 }, { 1.35, .36, .03 }, .5 },
        fl_end = { { 1, .35, .05 }, { 1.35, .36, .03 }, .5 }, fl_inner = { { 1, .8, .5 }, { 1.5, .95, .4 }, .5 },
        debris = { { .7, .38, .25 }, { 0, 0, 0 }, .8 },
        en_eye = { { .97, .97, .97 }, { .05, .05, .05 }, .3 }, en_pupil = { { .02, .02, .04 }, { 0, 0, 0 }, .2 },
        en_ballom = { { .95, .42, .12 }, { .02, .01, 0 }, .35 }, en_onil = { { .3, .55, 1 }, { .02, .04, .08 }, .3 },
        en_dahl = { { .95, .45, .2 }, { .04, .02, 0 }, .5 }, en_minvo = { { 1, .45, .65 }, { .06, .02, .04 }, .4 },
        en_doria = { { .35, .45, .95 }, { .02, .03, .07 }, .25 }, en_ovape = { { .7, .45, .95 }, { .05, .03, .08 }, .35 },
        en_pass = { { 1, .65, .1 }, { .05, .03, 0 }, .5 }, en_pontan = { { 1, .82, .2 }, { .1, .07, .01 }, .25, .8 },
        en_stripe = { { .15, .1, .05 }, { 0, 0, 0 }, .5 },
        shadow = { { .02, .03, .02 }, { 0, 0, 0 }, 1 }, ring = { { 1, .8, .4 }, { 1.4, 1.0, .4 }, .4 },
    }
    for _, k in ipairs({ "bombs", "fire", "speed", "wallpass", "detonator", "bombpass", "flamepass", "mystery" }) do P["pu_" .. k] = { { 1, 1, 1 }, { .18, .18, .18 }, .4 } end
    for name, v in pairs(P) do paint(tnode(name), v[1], v[2], v[3], v[4]) end
    mtex(tnode("floor"), "base_color", "Textures/field.png")
    mtex(tnode("brick"), "base_color", "Textures/brick.png"); mtex(tnode("brick_chunk"), "base_color", "Textures/brick.png")
    mtex(tnode("pillar"), "base_color", "Textures/concrete.png"); mtex(tnode("pillar_top"), "base_color", "Textures/concrete.png")
    mtex(tnode("border"), "base_color", "Textures/stone.png")
    for _, k in ipairs({ "bombs", "fire", "speed", "wallpass", "detonator", "bombpass", "flamepass", "mystery" }) do mtex(tnode("pu_" .. k), "base_color", "Textures/pu_" .. k .. ".png") end
    for name in pairs(P) do local n = tnode(name); if n then n:set_position(HIDE) end end
end

------------------------------------------------------------------ lights
local LT = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(-0.35, -0.85, -0.4), vec3(1.0, 0.97, 0.92), 1.3)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    LT.key = addp(vec3(10, 30, 30), vec3(1.0, 0.96, 0.9), 60, 90)
    LT.fill = addp(vec3(50, 20, 34), vec3(0.85, 0.9, 1.0), 35, 90)
    LT.flash = {}
    for i = 1, 8 do LT.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1 } end
end
G.LT = LT
G.flash_next = 1
local function flash(x, z, col, power, life, rad)
    local f = LT.flash[G.flash_next]; G.flash_next = G.flash_next % #LT.flash + 1
    f.t, f.life, f.x, f.z, f.col, f.power, f.rad = 0, life or 0.3, x, z, vec3(col[1], col[2], col[3]), power or 40, rad or 7
end
local function update_flashes(dt)
    -- key/fill follow the camera so the lit area stays even while scrolling
    local cx = G.cam.tx
    set_point(LT.key, vec3(cx - 6, 30, 30), vec3(1.0, 0.96, 0.9), 60, 90)
    set_point(LT.fill, vec3(cx + 14, 18, 34), vec3(0.85, 0.9, 1.0), 35, 90)
    for _, f in ipairs(LT.flash) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = 1 - clamp(f.t / f.life, 0, 1)
            set_point(f.idx, vec3(f.x, 2.5, f.z), f.col, f.power * k * k, f.rad)
            if f.t >= f.life then set_point(f.idx, HIDE, f.col, 0, 1) end
        end
    end
end

------------------------------------------------------------------ particles (x, y, z world)
local function PS() return SET:particle_scale() end
local function burst(x, y, z, o)
    pcall(particles.emit_burst, {
        position = vec3(x, y, z), velocity = o.vel or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = max(1, floor((o.count or 30) * PS())),
        size_min = o.smin or 0.05, size_max = o.smax or 0.14, life_min = o.lmin or 0.25, life_max = o.lmax or 0.7,
        spawn_radius = o.radius or 0.3, noise_strength = o.spread or 10, drag = o.drag or 2.0,
        gravity = o.grav or vec3(0, 0, 0), cleanup_delay = 3.0,
    })
end
local function sparks(x, y, z, col, n, spread, radius)
    burst(x, y, z, { c0 = vec4(col[1] * 1.6 + .4, col[2] * 1.6 + .4, col[3] * 1.6 + .4, 1), c1 = vec4(col[1], col[2], col[3], 0), count = n or 24,
        smin = .07, smax = .18, lmin = .25, lmax = .6, radius = radius or .3, spread = spread or 14, drag = 2.2, grav = vec3(0, -10, 0) })
end
local function smoke(x, y, z, n, r)
    burst(x, y, z, { c0 = vec4(.35, .33, .3, .7), c1 = vec4(.2, .2, .2, 0), count = n or 10, smin = .25, smax = .5, lmin = .5, lmax = 1.1,
        radius = r or .5, spread = 3, drag = 2.5, grav = vec3(0, 2.2, 0) })
end
local function fire_puff(x, z, n)
    burst(x, 0.8, z, { c0 = vec4(1.8, 1.0, .3, 1), c1 = vec4(.9, .2, .05, 0), count = n or 8, smin = .18, smax = .4, lmin = .2, lmax = .45,
        radius = .6, spread = 5, drag = 3, grav = vec3(0, 4, 0) })
end

------------------------------------------------------------------ explosion FX (common/particles.lua)
-- Particles here blend additively, so colours are kept low (gain) and overlap builds the hot centre.
-- Flipbook fire, stretched sparks, embers, smoke and brick debris.
-- The flame cross is staggered outward from the bomb (FX only; the sim's flame cells all exist at once).
local FX = load(fs.read("Scripts/Lib/particles.lua"), "@particles.lua")().new({ scale = PS, gain = 0.5 })
G.FX = FX
local FXQ = {}
local function later(d, fn) FXQ[#FXQ + 1] = { t = d, fn = fn } end
function G.fx_update(dt)
    for i = #FXQ, 1, -1 do local q = FXQ[i]; q.t = q.t - dt; if q.t <= 0 then table.remove(FXQ, i); pcall(q.fn) end end
end
function G.fx_clear() for i = #FXQ, 1, -1 do FXQ[i] = nil end end
local function heat(x, z, s, a, life)
    FX:burst("soft", { pos = vec3(x, 0.35, z), count = 1 / FX:k(), c0 = { 1, .42, .12, a or .3 }, c1 = { .6, .12, .02, 0 }, smin = s, smax = s * 1.05,
        lmin = life or .5, lmax = (life or .5) * 1.1, radius = 0, spread = 0, drag = 0 })
end
local function fx_core(x, z)
    local p = vec3(x, 0.9, z)
    FX:flash(vec3(x, 1.8, z), 1.7, { 1, .7, .4 })
    FX:fireball(p, 1.45, { 1, .38, .1 })
    FX:burst("fire", { pos = vec3(x, 1.4, z), count = 6, vel = { 0, 3.2, 0 }, c0 = { 1.6, .75, .3, 1 }, c1 = { .6, .15, .04, 0 }, smin = .7, smax = 1.1,
        lmin = .35, lmax = .55, radius = .3, spread = 1.2, drag = 3, grav = { 0, 1.5, 0 }, anim = 1.5 })        -- rising column
    FX:sparks(p, 34, 1.5, nil, { 2, 1.5, .9 }, -9)
    FX:embers(vec3(x, 1.2, z), 16, 1.4)
    later(0.28, function() FX:smoke(vec3(x, 1.6, z), 5, 1.7, .14, 1.5) end)
    later(0.55, function() FX:smoke(vec3(x, 1.0, z), 3, 1.3, .1, 1.1) end)
end
local function fx_arm(x, z, dx, dz, i, last)
    later(0.035 * i, function()
        local p = vec3(x, 0.8, z)
        FX:burst("fire", { pos = p, count = 5, vel = { dx * 4.0, 0.7, dz * 4.0 }, c0 = { 2.0, .6, .16, 1 }, c1 = { .8, .1, .02, 0 }, smin = .75, smax = 1.15,
            lmin = .3, lmax = .5, radius = .35, spread = 1.3, drag = 3.2, grav = { 0, 1.2, 0 }, anim = 1.7 })
        FX:burst("fire", { pos = vec3(x, 0.6, z), count = 3, c0 = { 1.2, .6, .25, .8 }, c1 = { .4, .1, .03, 0 }, smin = .9, smax = 1.3,
            lmin = .4, lmax = .6, radius = .5, spread = .8, drag = 2.5, grav = { 0, 1.6, 0 }, anim = 1.1 })
        if last then flash(x, z, { 1, .55, .22 }, 30, 0.55, 6) end
        FX:embers(vec3(x, 1.0, z), 3, 1.0)
        if last then FX:sparks(p, 10, 1.1, { dx * 6, 1.5, dz * 6 }, { 2, 1.4, .8 }, -9) end
    end)
    later(0.3 + 0.035 * i, function() FX:smoke(vec3(x, 1.3, z), 1, 1.3, .1, 1.3) end)
end
local function fx_brick_hit(x, z)
    FX:fireball(vec3(x, 1.0, z), 0.9, { 1, .55, .25 })
    FX:sparks(vec3(x, 1.0, z), 12, 1.1, nil, { 2, 1.4, .8 }, -9)
    FX:debris(vec3(x, 1.2, z), 8, 1.3, { .75, .5, .38 }, -14)
end
G.CHUNKS = {}
local function fx_brick_break(x, z)
    -- solid lit chunks that tumble and bounce, plus particle grit
    for i = 1, 9 do
        local a = rand() * 2 * PI
        local sp = 2.5 + rand() * 4
        G.CHUNKS[#G.CHUNKS + 1] = { x = x + (rand() - .5) * 1.2, y = 0.4 + rand() * 0.8, z = z + (rand() - .5) * 1.2, vx = math.cos(a) * sp, vz = math.sin(a) * sp,
            vy = 5 + rand() * 5, rx = rand() * 360, ry = rand() * 360, wr = (rand() - .5) * 900, s = 0.6 + rand() * 0.7, t = 0, life = 0.9 + rand() * 0.5 }
    end
    FX:debris(vec3(x, 1.0, z), 22, 1.6, { .72, .46, .33 }, -16)
    FX:debris(vec3(x, 0.8, z), 10, 1.0, { .3, .22, .18 }, -16)                                   -- charred bits
    FX:smoke(vec3(x, 0.9, z), 5, 1.5, .3, .9)                                                    -- brick dust
    FX:embers(vec3(x, 1.0, z), 8, 1.2)
end
-- sustained flame body on a live flame cell (re-emitted every few frames while the cell burns; k = 1 fresh .. 0 dying)
function G.fx_flame(x, z, core, k)
    local s = 0.55 + 0.45 * k
    FX:burst("fire", { pos = vec3(x, 0.75, z), count = core and 3 or 2, vel = { 0, 1.4, 0 }, c0 = { 1.9, .5, .12, 1 }, c1 = { .8, .1, .02, 0 },
        smin = 0.75 * s, smax = 1.1 * s, lmin = .18, lmax = .3, radius = .6, spread = .9, drag = 2.5, grav = { 0, 1.0, 0 }, anim = 2.2 })
end
G.fx_core, G.fx_arm, G.fx_brick_hit, G.fx_brick_break = fx_core, fx_arm, fx_brick_hit, fx_brick_break

------------------------------------------------------------------ score state
G.score, G.lives, G.hiscore = 0, 3, 0
pcall(function() local s = fs.read("Save/bomberman_hiscore.txt"); if s then G.hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, "Save/bomberman_hiscore.txt", tostring(G.hiscore)) end
G.POP = {}
for i = 1, 12 do G.POP[i] = { t = 9, col = { 1, 1, 1 }, x = 0, z = 0 } end
G.pop_next = 1
local function popup(x, z, txt, col)
    local p = G.POP[G.pop_next]; G.pop_next = G.pop_next % #G.POP + 1
    p.t, p.x, p.z, p.txt, p.col = 0, x, z, txt, col or { 1, 1, 1 }
end
local function add_score(n, x, z)
    G.score = G.score + n
    if x then popup(x, z, tostring(n), { 1, .95, .7 }) end
end
------------------------------------------------------------------ enemies (NES order of difficulty)
--          mesh         speed(cells/s) smart wallpass points
local EN = {
    ballom = { "en_ballom", 1.6, 0, false, 100, "Ballom" },
    onil   = { "en_onil", 2.5, 1, false, 200, "Onil" },
    dahl   = { "en_dahl", 2.5, 0, false, 400, "Dahl" },
    minvo  = { "en_minvo", 3.4, 1, false, 800, "Minvo" },
    doria  = { "en_doria", 1.0, 2, true, 1000, "Doria" },
    ovape  = { "en_ovape", 1.6, 1, true, 2000, "Ovape" },
    pass   = { "en_pass", 3.4, 2, false, 4000, "Pass" },
    pontan = { "en_pontan", 3.4, 3, true, 8000, "Pontan" },
}
local TIER = { "ballom", "onil", "dahl", "minvo", "doria", "ovape", "pass", "pontan" }
G.EN, G.TIER = EN, TIER
-- stage table: enemy counts by tier {ballom, onil, dahl, minvo, doria, ovape, pass} and the hidden power-up
local ST_EN = {
    { 6 }, { 3, 3 }, { 2, 2, 2 }, { 1, 1, 2, 2 }, { 0, 4, 3 }, { 0, 2, 3, 2 }, { 0, 2, 3, 0, 2 }, { 0, 1, 2, 4 }, { 0, 1, 1, 4, 1 },
    { 0, 1, 1, 1, 3, 1 }, { 0, 1, 2, 3, 1, 1 }, { 0, 1, 1, 1, 1, 4 }, { 0, 0, 3, 3, 0, 2 }, { 0, 0, 0, 0, 0, 7, 1 }, { 0, 0, 1, 3, 0, 3, 1 },
    { 0, 0, 0, 3, 0, 4, 1 }, { 0, 0, 5, 0, 0, 2, 1 }, { 0, 0, 3, 3, 0, 0, 2 }, { 0, 1, 1, 0, 3, 1, 2 }, { 0, 0, 1, 1, 1, 2, 2 },
}
local ST_PU = { "fire", "bombs", "detonator", "speed", "bombs", "bombs", "fire", "detonator", "bombpass", "wallpass",
    "bombs", "bombs", "fire", "bombpass", "fire", "wallpass", "bombs", "bombpass", "bombs", "detonator",
    "bombpass", "bombs", "bombs", "detonator", "bombpass", "mystery", "fire", "bombs", "bombpass", "flamepass",
    "wallpass", "bombs", "detonator", "mystery", "bombpass", "flamepass", "detonator", "fire", "wallpass", "mystery",
    "detonator", "wallpass", "bombpass", "detonator", "mystery", "wallpass", "bombpass", "detonator", "flamepass", "mystery" }
G.PU_NAME = { bombs = "Bomb Up", fire = "Fire Up", speed = "Speed Up", wallpass = "Wall Pass", detonator = "Detonator",
    bombpass = "Bomb Pass", flamepass = "Flame Pass", mystery = "Mystery" }
local function stage_enemies(n)
    if ST_EN[n] then return ST_EN[n] end
    -- 21..50: the later NES stages lean on Doria, Ovape and Pass; counts grow to 10
    local total = min(10, 7 + floor((n - 20) / 10))
    local t = {}
    local hi = (n >= 40) and 7 or 6
    for i = 1, total do
        local k = hi - ((i * 3 + n) % 4)
        if n % 5 == 0 and i <= 2 then k = 7 end
        t[k] = (t[k] or 0) + 1
    end
    for i = 1, 7 do t[i] = t[i] or 0 end
    return t
end
G.stage_enemies = stage_enemies
local function stage_def(n)
    local en = stage_enemies(n)
    local maxt = 1
    for i = 1, 7 do if (en[i] or 0) > 0 then maxt = i end end
    return { n = n, en = en, pu = ST_PU[n] or "bombs", time = 200, spawn_tier = min(7, maxt + 1) }
end
G.stage_def = stage_def

------------------------------------------------------------------ grid
-- cells c 0..32, r 0..14; 0 empty, 1 hard, 2 brick. World centre of a cell = (c * CS, r * CS)
local GRID = {}
local ST = nil
local function wx(c) return c * CS end
local function cell_of(x) return floor(x / CS + 0.5) end
local function solid_raw(c, r) local col = GRID[c]; if not col then return 1 end; return col[r] or 1 end
G.solid_raw = solid_raw
local function build_layout(n)
    local seed = n * 7919 + 13
    local function lr() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
    for c = 0, NC + 1 do
        GRID[c] = {}
        for r = 0, NR + 1 do
            local hard = c == 0 or r == 0 or c == NC + 1 or r == NR + 1 or (c % 2 == 0 and r % 2 == 0)
            GRID[c][r] = hard and 1 or 0
        end
    end
    local free = {}
    for c = 1, NC do for r = 1, NR do
        if GRID[c][r] == 0 and not (c + r <= 3) then
            if lr() < 0.26 then GRID[c][r] = 2 end
            free[#free + 1] = { c, r }
        end
    end end
    local bricks = {}
    for c = 1, NC do for r = 1, NR do if GRID[c][r] == 2 then bricks[#bricks + 1] = { c, r } end end end
    local e = table.remove(bricks, 1 + floor(lr() * #bricks))
    local p = table.remove(bricks, 1 + floor(lr() * #bricks))
    local empties = {}
    for _, f in ipairs(free) do if GRID[f[1]][f[2]] == 0 and f[1] + f[2] >= 9 then empties[#empties + 1] = f end end
    return e, p, empties, lr
end
------------------------------------------------------------------ live stage state (cell units; world = cell * CS)
local FR = 1 / 60
local FUSE, FLAME_T, BURN_T = 2.6, 0.55, 0.5
local PSPEED, PSPEED_UP = 3.2, 1.0
local HW = 0.42             -- player half width (cells) against walls
local HIT_EN = 0.62         -- player <-> enemy contact distance (cells)
G.CONST = { FUSE = FUSE, FLAME_T = FLAME_T, PSPEED = PSPEED, HW = HW, HIT_EN = HIT_EN }
local BOMBS, FLS, ENEMIES, BRICKS = {}, {}, {}, {}
local FLAME = {}            -- FLAME[c * 100 + r] = time left
local BOMBAT = {}           -- BOMBAT[c * 100 + r] = bomb
local FLAMEG = {}           -- explosion group per flame cell (kill chain scoring)
G.BOMBS, G.FLS, G.ENEMIES, G.BRICKS, G.FLAME, G.BOMBAT = BOMBS, FLS, ENEMIES, BRICKS, FLAME, BOMBAT
local function key(c, r) return c * 100 + r end
local P = { x = 1, z = 1, ox = 1, oz = 1, st = "walk", dir = "down", ph = 0, bombs = 1, fire = 1, speed = 0, inv = 0, dead_t = 0 }
G.P = P
local EXIT, PU = { c = 0, r = 0 }, { c = 0, r = 0 }
G.EXIT, G.PU = EXIT, PU

local function flame_at(c, r) return (FLAME[key(c, r)] or 0) > 0 end
G.flame_at = flame_at
local function blocked_p(c, r)
    local s = solid_raw(c, r)
    if s == 1 then return true end
    if s == 2 and not P.wallpass then return true end
    local b = BOMBAT[key(c, r)]
    if b and not P.bombpass and not b.pass_p then return true end
    return false
end
local function blocked_e(e, c, r)
    local s = solid_raw(c, r)
    if s == 1 then return true end
    if s == 2 and not EN[e.k][4] then return true end
    if BOMBAT[key(c, r)] then return true end
    return false
end
local function box_hits(x, z)
    for c = floor(x - HW + 0.5), floor(x + HW + 0.5 - 1e-6) do
        for r = floor(z - HW + 0.5), floor(z + HW + 0.5 - 1e-6) do
            if blocked_p(c, r) then return true end
        end
    end
    return false
end
G.box_hits = box_hits

------------------------------------------------------------------ stage build (geometry nodes come from 05_render)
local function build_stage(n)
    for _, t in ipairs({ BOMBS, FLS, ENEMIES }) do for i = #t, 1, -1 do t[i] = nil end end
    for k in pairs(FLAME) do FLAME[k] = nil; FLAMEG[k] = nil end
    for k in pairs(BOMBAT) do BOMBAT[k] = nil end
    for k in pairs(BRICKS) do BRICKS[k] = nil end
    local d = stage_def(n)
    local e, p, empties, lr = build_layout(n)
    EXIT.c, EXIT.r, EXIT.exposed, EXIT.open = e[1], e[2], false, false
    PU.c, PU.r, PU.kind, PU.exposed, PU.taken = p[1], p[2], d.pu, false, false
    for c = 1, NC do for r = 1, NR do if GRID[c][r] == 2 then BRICKS[key(c, r)] = { c = c, r = r, burn = 0 } end end end
    ST = { n = n, def = d, empties = empties }
    -- enemies on free cells away from the start corner
    local slots = {}
    for i, f in ipairs(empties) do slots[i] = f end
    for tier = 1, 7 do
        for _ = 1, d.en[tier] or 0 do
            if #slots == 0 then break end
            local f = table.remove(slots, 1 + floor(lr() * #slots))
            G.enemy_new(TIER[tier], f[1], f[2], 0)
        end
    end
    G.build_bricks()
    return ST
end
G.ST = function() return ST end

------------------------------------------------------------------ enemies
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
function G.enemy_new(k, c, r, inv)
    local e = { k = k, c = c, r = r, tc = c, tr = r, t = 1, x = c, z = r, ox = c, oz = r, alive = true, inv = inv or 0, die_t = 0, ph = rand() * 6, wait = 0 }
    ENEMIES[#ENEMIES + 1] = e
    return e
end
local function enemy_choose(e)
    local def = EN[e.k]
    local opts = {}
    for _, d in ipairs(DIRS) do if not blocked_e(e, e.c + d[1], e.r + d[2]) then opts[#opts + 1] = d end end
    if #opts == 0 then e.dx, e.dz = 0, 0; e.wait = 0.4; return end
    local smart = def[3]
    local px, pz = floor(P.x + 0.5), floor(P.z + 0.5)
    local dist = abs(px - e.c) + abs(pz - e.r)
    if smart > 0 and P.st ~= "dead" and dist <= 3 + smart * 2 and rand() < 0.35 + smart * 0.2 then
        local best, bd = nil, 1e9
        for _, d in ipairs(opts) do
            local dd = abs(px - (e.c + d[1])) + abs(pz - (e.r + d[2])) + rand() * 0.3
            if dd < bd then bd, best = dd, d end
        end
        e.dx, e.dz = best[1], best[2]; return
    end
    local turn = (e.k == "dahl" or e.k == "pontan") and 0.5 or 0.12
    if e.dx then
        for _, d in ipairs(opts) do
            if d[1] == e.dx and d[2] == e.dz and rand() > turn then return end
        end
    end
    -- prefer not to reverse unless it is the only way
    local fw = {}
    for _, d in ipairs(opts) do if not (e.dx and d[1] == -e.dx and d[2] == -e.dz) then fw[#fw + 1] = d end end
    local pick = (#fw > 0 and rand() > 0.08) and fw[1 + floor(rand() * #fw)] or opts[1 + floor(rand() * #opts)]
    e.dx, e.dz = pick[1], pick[2]
end
local function enemy_step(e, dt)
    e.ox, e.oz = e.x, e.z
    e.ph = e.ph + dt
    if not e.alive then e.die_t = e.die_t + dt; return end
    e.inv = max(0, e.inv - dt)
    local sp = EN[e.k][2]
    if e.t >= 1 then
        if e.wait > 0 then e.wait = e.wait - dt; return end
        enemy_choose(e)
        if e.dx == 0 and e.dz == 0 then return end
        e.tc, e.tr = e.c + e.dx, e.r + e.dz; e.t = 0
    end
    -- a bomb dropped in front: turn back
    if BOMBAT[key(e.tc, e.tr)] and e.t < 0.6 then
        e.c, e.tc = e.tc, e.c; e.r, e.tr = e.tr, e.r; e.t = 1 - e.t; e.dx, e.dz = -e.dx, -e.dz
    end
    e.t = e.t + sp * dt
    if e.t >= 1 then e.t = 1; e.c, e.r = e.tc, e.tr end
    e.x = e.c + (e.tc - e.c) * e.t; e.z = e.r + (e.tr - e.r) * e.t
    if e.t >= 1 then e.x, e.z = e.c, e.r end
end
local function spawn_wave(c, r, tier, n)
    for _ = 1, n do
        local e = G.enemy_new(TIER[tier], c, r, 1.0)
        e.wait = rand() * 0.5
    end
    sfx("spawn")
end
G.spawn_wave = spawn_wave

------------------------------------------------------------------ bombs + flames
local function place_bomb()
    local c, r = floor(P.x + 0.5), floor(P.z + 0.5)
    if BOMBAT[key(c, r)] or solid_raw(c, r) ~= 0 then return end
    local live = 0
    for _, b in ipairs(BOMBS) do live = live + 1 end
    if live >= P.bombs then return end
    local b = { c = c, r = r, t = FUSE, range = P.fire, pass_p = true, remote = P.detonator, age = 0, born = G.t }
    BOMBS[#BOMBS + 1] = b; BOMBAT[key(c, r)] = b
    -- enemies standing in that cell keep going; enemies about to enter it turn back (enemy_step)
    sfx("place")
end
local explode
local function kill_enemy(e, grp)
    if not e.alive or e.inv > 0 then return end
    e.alive = false; e.die_t = 0
    grp.kills = grp.kills + 1
    local pts = EN[e.k][5] * 2 ^ (grp.kills - 1)
    add_score(pts, e.x, e.z)
    sfx("kill")
    sparks(e.x * CS, 1.0, e.z * CS, { 1, .8, .5 }, 26, 10, 0.6)
end
local function flame_cell(c, r, kind, ax, grp)
    FLAME[key(c, r)] = FLAME_T; FLAMEG[key(c, r)] = grp
    FLS[#FLS + 1] = { c = c, r = r, t = FLAME_T, kind = kind, ax = ax }
    if PU.exposed and not PU.taken and PU.c == c and PU.r == r and not grp.pu_hit then
        grp.pu_hit = true; PU.taken = true; sparks(c * CS, 0.5, r * CS, { .6, .8, 1 }, 20)
        spawn_wave(c, r, ST.def.spawn_tier, 8)
    end
    if EXIT.exposed and EXIT.c == c and EXIT.r == r and not grp.exit_hit and (G.exit_cool or 0) <= 0 then
        grp.exit_hit = true; G.exit_cool = 1.0
        spawn_wave(c, r, ST.def.spawn_tier, 8)
    end
end
explode = function(b, grp)
    if b.gone then return end
    b.gone = true
    BOMBAT[key(b.c, b.r)] = nil
    for i = #BOMBS, 1, -1 do if BOMBS[i] == b then table.remove(BOMBS, i) end end
    grp = grp or { kills = 0 }
    sfx("boom"); G.shake = max(G.shake, 0.32)
    flash(b.c * CS, b.r * CS, { 1, .6, .25 }, 70, 0.4, 10)
    fx_core(b.c * CS, b.r * CS)
    flame_cell(b.c, b.r, "core", 0, grp)
    for _, d in ipairs(DIRS) do
        for i = 1, b.range do
            local c, r = b.c + d[1] * i, b.r + d[2] * i
            local s = solid_raw(c, r)
            if s == 1 then break end
            if s == 2 then
                local br = BRICKS[key(c, r)]
                if br and br.burn <= 0 then br.burn = BURN_T; fx_brick_hit(c * CS, r * CS) end
                break
            end
            local ob = BOMBAT[key(c, r)]
            flame_cell(c, r, i == b.range and "end" or "arm", (d[1] ~= 0) and (d[1] > 0 and 90 or -90) or (d[2] > 0 and 0 or 180), grp)
            fx_arm(c * CS, r * CS, d[1], d[2], i, i == b.range)
            FLS[#FLS].fxd = 0.035 * i
            if ob then explode(ob, grp); break end
        end
    end
end
G.explode = explode
local function detonate()
    local oldest = nil
    for _, b in ipairs(BOMBS) do if b.remote and (not oldest or b.born < oldest.born) then oldest = b end end
    if oldest then sfx("detonate"); explode(oldest) end
end

------------------------------------------------------------------ player
local function try_move(dx, dz, dist)
    local x0, z0 = P.x, P.z
    if dx ~= 0 then
        local nx = P.x + dx * dist
        if not box_hits(nx, P.z) then P.x = nx
        else
            -- corner assist: slide toward the lane centre if the lane ahead is open
            local lane = floor(P.z + 0.5)
            local off = lane - P.z
            if abs(off) > 0.02 and not blocked_p(floor(P.x + 0.5) + dx, lane) then
                local s = min(abs(off), dist); P.z = P.z + (off > 0 and s or -s)
                if box_hits(P.x, P.z) then P.z = z0 end
            else
                -- snug up against the wall
                local c = floor(P.x + 0.5); local lim = c + dx * (0.5 - HW)
                if (dx > 0 and P.x < lim) or (dx < 0 and P.x > lim) then P.x = lim end
            end
        end
    else
        local nz = P.z + dz * dist
        if not box_hits(P.x, nz) then P.z = nz
        else
            local lane = floor(P.x + 0.5)
            local off = lane - P.x
            if abs(off) > 0.02 and not blocked_p(lane, floor(P.z + 0.5) + dz) then
                local s = min(abs(off), dist); P.x = P.x + (off > 0 and s or -s)
                if box_hits(P.x, P.z) then P.x = x0 end
            else
                local r = floor(P.z + 0.5); local lim = r + dz * (0.5 - HW)
                if (dz > 0 and P.z < lim) or (dz < 0 and P.z > lim) then P.z = lim end
            end
        end
    end
    return abs(P.x - x0) + abs(P.z - z0) > 1e-5
end
local DIRV = { left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 }, down = { 0, 1 } }
local function player_die(cause)
    if P.st == "dead" or G.god then return end
    P.st = "dead"; P.dead_t = 0; P.cause = cause
    music(nil); sfx("death"); G.shake = 0.5
    smoke(P.x * CS, 1.0, P.z * CS, 16, 0.6)
end
G.player_die = player_die
local function apply_pu(k)
    if k == "bombs" then P.bombs = min(10, P.bombs + 1)
    elseif k == "fire" then P.fire = min(10, P.fire + 1)
    elseif k == "speed" then P.speed = 1
    elseif k == "mystery" then P.inv = 10
    else P[k] = true end
    sfx("item"); popup(P.x, P.z, G.PU_NAME[k], { .7, .9, 1 })
end
local function player_step(inp, dt)
    P.ox, P.oz = P.x, P.z
    if P.st == "dead" then P.dead_t = P.dead_t + dt; return end
    if P.st ~= "walk" then return end
    P.inv = max(0, P.inv - dt)
    if inp.bomb then place_bomb() end
    if inp.det and P.detonator then detonate() end
    local dist = (PSPEED + P.speed * PSPEED_UP) * dt
    local moved = false
    -- most recently pressed direction first; if it is blocked, take whichever other held direction is open
    for _, nm in ipairs(inp.order) do
        local v = DIRV[nm]
        if try_move(v[1], v[2], dist) then moved = true; P.dir = nm; break end
    end
    if not moved and inp.order[1] then P.dir = inp.order[1] end
    P.moving = moved
    if moved then
        P.ph = P.ph + dt * 12
        P.step_t = (P.step_t or 0) - dt
        if P.step_t <= 0 then P.step_alt = not P.step_alt; sfx(P.step_alt and "walk" or "walk2"); P.step_t = 0.22 end
    else P.step_t = 0 end
    -- leave a freshly placed bomb behind
    for _, b in ipairs(BOMBS) do
        if b.pass_p and (abs(P.x - b.c) >= 0.5 + HW - 1e-3 or abs(P.z - b.r) >= 0.5 + HW - 1e-3) then b.pass_p = false end
    end
    local c, r = floor(P.x + 0.5), floor(P.z + 0.5)
    if PU.exposed and not PU.taken and PU.c == c and PU.r == r then PU.taken = true; apply_pu(PU.kind) end
end

------------------------------------------------------------------ step
local function stage_step(inp, dt)
    G.exit_cool = max(0, (G.exit_cool or 0) - dt)
    if P.st == "walk" then
        G.time = G.time - dt
        if G.time <= 10 and floor(G.time + dt) ~= floor(G.time) and G.time > 0 then sfx("warn") end
        if G.time <= 0 and not G.pontans then
            G.time = 0; G.pontans = true
            for i = 1, 8 do
                local f = ST.empties[1 + floor(rand() * #ST.empties)]
                if solid_raw(f[1], f[2]) == 0 then G.enemy_new("pontan", f[1], f[2], 1.0) end
            end
            sfx("spawn"); G.banner = { text = "Time Up", t = 2 }
        end
    end
    player_step(inp, dt)
    -- bombs
    for i = #BOMBS, 1, -1 do
        local b = BOMBS[i]
        if b then
            b.age = b.age + dt
            if not b.remote or P.st == "dead" then b.t = b.t - dt end
            if b.t <= 0 then explode(b) end
        end
    end
    -- flames
    for i = #FLS, 1, -1 do local f = FLS[i]; f.t = f.t - dt; if f.t <= 0 then table.remove(FLS, i) end end
    for k, t in pairs(FLAME) do t = t - dt; if t <= 0 then FLAME[k] = nil; FLAMEG[k] = nil else FLAME[k] = t end end
    -- burning bricks
    for k, br in pairs(BRICKS) do
        if br.burn > 0 then
            br.burn = br.burn - dt
            if br.burn <= 0 then
                GRID[br.c][br.r] = 0; BRICKS[k] = nil; sfx("brick")
                fx_brick_break(br.c * CS, br.r * CS)
                if EXIT.c == br.c and EXIT.r == br.r then EXIT.exposed = true end
                if PU.c == br.c and PU.r == br.r then PU.exposed = true end
            end
        end
    end
    for _, e in ipairs(ENEMIES) do enemy_step(e, dt) end
    for i = #ENEMIES, 1, -1 do if not ENEMIES[i].alive and ENEMIES[i].die_t > 1.0 then table.remove(ENEMIES, i) end end
    -- flame kills (cell of the centre point)
    for _, e in ipairs(ENEMIES) do
        local k = key(floor(e.x + 0.5), floor(e.z + 0.5))
        if e.alive and (FLAME[k] or 0) > 0 then kill_enemy(e, FLAMEG[k] or { kills = 0 }) end
    end
    if P.st == "walk" then
        local c, r = floor(P.x + 0.5), floor(P.z + 0.5)
        if flame_at(c, r) and not P.flamepass and P.inv <= 0 then player_die("fire") end
        if P.inv <= 0 then
            for _, e in ipairs(ENEMIES) do
                if e.alive and abs(e.x - P.x) < HIT_EN and abs(e.z - P.z) < HIT_EN then player_die("enemy"); break end
            end
        end
    end
    -- exit door
    local alive = 0
    for _, e in ipairs(ENEMIES) do if e.alive then alive = alive + 1 end end
    G.alive = alive
    if alive == 0 and not EXIT.open then EXIT.open = true; if EXIT.exposed then sfx("door") end end
    if alive > 0 then EXIT.open = false end
end
G.stage_step = stage_step
local function stage_reset(n, keep)
    build_stage(n)
    P.x, P.z, P.ox, P.oz = 1, 1, 1, 1; P.st = "walk"; P.dir = "down"; P.inv = 0; P.dead_t = 0
    if not keep then P.bombs, P.fire, P.speed = 1, 1, 0 end
    P.wallpass, P.bombpass, P.flamepass, P.detonator = false, false, false, false
    G.time = ST.def.time; G.pontans = false; G.exit_cool = 0
end
G.stage_reset = stage_reset
function G.at_exit() local c, r = floor(P.x + 0.5), floor(P.z + 0.5); return EXIT.exposed and EXIT.open and c == EXIT.c and r == EXIT.r end
------------------------------------------------------------------ static arena
local function V(x, y, z) return vec3(x, y, z) end
local function build_world()
    clone("floor", V((NC + 1) / 2 * CS, 0, (NR + 1) / 2 * CS), V(NC * CS, 1, NR * CS))
    for c = 0, NC + 1 do for r = 0, NR + 1 do
        local border = c == 0 or r == 0 or c == NC + 1 or r == NR + 1
        if border then clone("border", V(c * CS, 0, r * CS))
        elseif c % 2 == 0 and r % 2 == 0 then clone("pillar", V(c * CS, 0, r * CS)); clone("pillar_top", V(c * CS, 0.001, r * CS)) end
    end end
    -- ground beyond the arena
    local g = prim("cube", V(32, -0.6, 14), V(160, 1, 100)); paint(g, { .2, .32, .16 }, { 0, 0, 0 }, .95, 0)
end
function G.build_bricks()
    P_begin("brick")
    for _, br in pairs(BRICKS) do br.node = P_get("brick"); br.node:set_position(V(br.c * CS, 0, br.r * CS)); br.node:set_scale(V(1, 1, 1)); br.node:set_rotation(V(0, 0, 0)) end
    P_end("brick")
end

------------------------------------------------------------------ Bomberman rig
local function grp(parent, pos, meshes)
    local g = empty("grp", parent, pos)
    for _, m in ipairs(meshes) do clone(m, V(0, 0, 0), nil, g) end
    return g
end
local R = {}
local function build_player()
    local root = empty("Bomber", nil, HIDE)
    R.root = root
    R.body = grp(root, V(0, 0.42, 0), { "bm_body", "bm_belt" })
    R.head = grp(root, V(0, 1.0, 0), { "bm_helmet", "bm_face", "bm_eye", "bm_antenna", "bm_knob" })
    R.arm_l = grp(root, V(0.42, 0.95, 0), { "bm_arm", "bm_glove" })
    R.arm_r = grp(root, V(-0.42, 0.95, 0), { "bm_arm", "bm_glove" })
    R.leg_l = grp(root, V(0.16, 0.42, 0), { "bm_leg", "bm_boot" })
    R.leg_r = grp(root, V(-0.16, 0.42, 0), { "bm_leg", "bm_boot" })
    R.shadow = clone("shadow")
end
G.R = R
local AL = 1
local YAW = { down = 0, right = 90, left = -90, up = 180 }
G.vis = { yaw = 0 }
local function render_player(dt)
    if G.hide_player then R.root:set_position(HIDE); R.shadow:set_position(HIDE); return end
    local x, z = lerp(P.ox, P.x, AL) * CS, lerp(P.oz, P.z, AL) * CS
    local VIS = G.vis
    local yt = YAW[P.dir] or 0
    if yt - VIS.yaw > 180 then VIS.yaw = VIS.yaw + 360 elseif VIS.yaw - yt > 180 then VIS.yaw = VIS.yaw - 360 end
    VIS.yaw = damp(VIS.yaw, yt, 20, dt)
    local s = sin(P.ph)
    local ll, lr, al, ar, bob = 0, 0, 0, 0, 0
    if P.moving and P.st == "walk" then ll, lr, al, ar = 35 * s, -35 * s, -30 * s, 30 * s; bob = abs(cos(P.ph)) * 0.06 end
    local sc, rz, ry = 1, 0, VIS.yaw
    if P.st == "dead" then
        local k = clamp(P.dead_t / 1.4, 0, 1)
        ry = VIS.yaw + P.dead_t * 720 * (1 - k); al, ar = 150, 150
        sc = 1 - 0.85 * clamp((P.dead_t - 0.9) / 0.8, 0, 1)
    end
    if P.st == "win" then al, ar = 160 + 15 * sin(G.t * 10), 160 - 15 * sin(G.t * 10); bob = abs(sin(G.t * 8)) * 0.3 end
    local blink = P.inv > 0 and P.inv < 10 and floor(G.t * 12) % 2 == 0 and P.st == "walk"
    R.root:set_position(blink and HIDE or V(x, bob, z))
    R.root:set_rotation(V(0, ry, rz)); R.root:set_scale(V(sc, sc, sc))
    R.leg_l:set_rotation(V(ll, 0, 0)); R.leg_r:set_rotation(V(lr, 0, 0))
    R.arm_l:set_rotation(V(al, 0, -8)); R.arm_r:set_rotation(V(ar, 0, 8))
    R.head:set_rotation(V(0, 0, P.st == "walk" and 0 or 0))
    R.shadow:set_position(V(x, 0.03, z)); R.shadow:set_scale(V(0.45 * sc, 1, 0.45 * sc))
end

------------------------------------------------------------------ dynamic objects (pooled per frame)
local EYE_Y = { ballom = 0.95, onil = 0.72, dahl = 0.9, minvo = 0.85, doria = 0.62, ovape = 1.0, pass = 0.85, pontan = 0.85 }
local EYE_Z = { ballom = 0.66, onil = 0.6, dahl = 0.6, minvo = 0.58, doria = 0.66, ovape = 0.56, pass = 0.6, pontan = 0.2 }
local DYN = { "brick", "brick_chunk", "bomb", "bomb_cap", "bomb_fuse", "bomb_shine", "fl_core", "fl_arm", "fl_end", "fl_inner", "door_frame", "door", "door_light",
    "en_eye", "en_pupil", "en_ballom", "en_onil", "en_dahl", "en_minvo", "en_doria", "en_ovape", "en_pass", "en_pontan", "en_stripe", "shadow", "ring",
    "pu_bombs", "pu_fire", "pu_speed", "pu_wallpass", "pu_detonator", "pu_bombpass", "pu_flamepass", "pu_mystery" }
local function render_dyn(dt)
    for _, k in ipairs(DYN) do if k ~= "brick" then P_begin(k) end end
    local t = G.t
    -- bricks: burning ones shake, char and crumble
    for _, br in pairs(BRICKS) do
        if br.node then
            if br.burn > 0 then
                local k = clamp(1 - br.burn / 0.5, 0, 1)
                local sh = 0.06 * sin(t * 70)
                br.node:set_position(V(br.c * CS + sh, -k * 0.6, br.r * CS)); br.node:set_scale(V(1 - k * 0.3, 1 - k * 0.6, 1 - k * 0.3))
            end
        end
    end
    -- brick chunks: ballistic, bounce once or twice on the floor, shrink away at the end of their life
    for i = #G.CHUNKS, 1, -1 do
        local c = G.CHUNKS[i]
        c.t = c.t + dt
        if c.t >= c.life then table.remove(G.CHUNKS, i) else
            c.vy = c.vy - 26 * dt; c.x = c.x + c.vx * dt; c.y = c.y + c.vy * dt; c.z = c.z + c.vz * dt
            c.rx = c.rx + c.wr * dt; c.ry = c.ry + c.wr * 0.6 * dt
            local h = 0.15 * c.s
            if c.y < h then c.y = h; c.vy = abs(c.vy) * 0.35; c.vx = c.vx * 0.6; c.vz = c.vz * 0.6; c.wr = c.wr * 0.6 end
            local k = clamp((c.life - c.t) / 0.25, 0, 1) * c.s
            local n = P_get("brick_chunk"); n:set_position(V(c.x, c.y, c.z)); n:set_rotation(V(c.rx, c.ry, 0)); n:set_scale(V(k, k, k))
        end
    end
    -- hidden items revealed
    if EXIT.exposed then
        local x, z = EXIT.c * CS, EXIT.r * CS
        P_get("door_frame"):set_position(V(x, 0, z)); P_get("door"):set_position(V(x, 0, z))
        local dl = P_get("door_light")
        dl:set_position(EXIT.open and V(x, 0, z + 0.002) or HIDE)
    end
    if PU.exposed and not PU.taken then
        local n = P_get("pu_" .. PU.kind)
        n:set_position(V(PU.c * CS, 0.05 + 0.08 * sin(t * 4), PU.r * CS))
    end
    -- bombs: breathe while the fuse burns, fuse sparks
    for _, b in ipairs(BOMBS) do
        local x, z = b.c * CS, b.r * CS
        local p = 1 + 0.08 * sin(b.age * (b.remote and 6 or (8 + (G.CONST.FUSE - b.t) * 6)))
        for _, m in ipairs({ "bomb", "bomb_cap", "bomb_fuse", "bomb_shine" }) do
            local n = P_get(m); n:set_position(V(x, 0, z)); n:set_scale(V(p, 2 - p, p))
        end
        local sd = P_get("shadow"); sd:set_position(V(x, 0.03, z)); sd:set_scale(V(0.75, 1, 0.75))
        b.spark = (b.spark or 0) - dt
        if b.spark <= 0 then b.spark = 0.09; G.FX:sparks(V(x + 0.2 * p, 1.6, z), 3, 0.6, V(0, 1.2, 0), { 2.2, 1.6, .7 }, -5)
            G.FX:burst("ember", { pos = V(x + 0.2 * p, 1.65, z), count = 1, c0 = { 2, 1.3, .5, 1 }, c1 = { 1, .3, .05, 0 }, smin = .12, smax = .16, lmin = .08, lmax = .12, radius = 0, spread = 0 }) end
    end
    -- flames: a slim white-hot core keeps the burning cells readable; the body of the flame is particles
    for _, f in ipairs(FLS) do
        local k = f.t / G.CONST.FLAME_T
        local w = 0.55 + 0.55 * sin(PI * clamp(1 - k, 0, 1) ^ 0.6) + 0.05 * sin(t * 40 + f.c)
        local x, z = f.c * CS, f.r * CS
        local live = (G.CONST.FLAME_T - f.t) >= (f.fxd or 0)
        local inner = P_get("fl_inner"); inner:set_position(live and V(x, 0.02, z) or HIDE); inner:set_rotation(V(0, f.ax or 0, 0))
        inner:set_scale(f.kind == "core" and V(w * 0.6, w * 0.6, 0.35 * w) or V(w * 0.36, w * 0.36, f.kind == "end" and 0.6 or 1))
        f.fx = (f.fx or (f.fxd or 0)) - dt
        if f.fx <= 0 then f.fx = 0.06; G.fx_flame(x, z, f.kind == "core", k) end
    end
    -- enemies
    for _, e in ipairs(ENEMIES) do
        local x, z = lerp(e.ox, e.x, AL) * CS, lerp(e.oz, e.z, AL) * CS
        local def = EN[e.k]
        local hop = abs(sin(e.ph * 6)) * 0.15
        local sc, ry, rx = 1, 0, 0
        if e.k == "pontan" then ry = e.ph * 260 end
        if e.k == "ovape" or e.k == "doria" then hop = 0.1 + 0.1 * sin(e.ph * 3) end
        if not e.alive then
            local k = clamp(e.die_t / 1.0, 0, 1)
            ry = e.die_t * 900; sc = 1 - k; hop = k * 1.2
        end
        local vis = not (e.inv > 0 and floor(t * 16) % 2 == 0)
        local pos = vis and V(x, hop, z) or HIDE
        local n = P_get(def[1]); n:set_position(pos); n:set_rotation(V(rx, ry, 0)); n:set_scale(V(sc, sc * (1 + 0.06 * sin(e.ph * 12)), sc))
        if e.k == "pass" then local s2 = P_get("en_stripe"); s2:set_position(pos); s2:set_scale(V(sc * 1.05, sc, sc * 1.05)) end
        if e.k ~= "pontan" then
            local ey, ez = EYE_Y[e.k] * sc + hop, EYE_Z[e.k] * sc
            local ep = vis and V(x, ey, z + ez) or HIDE
            local ee = P_get("en_eye"); ee:set_position(ep); ee:set_scale(V(sc, sc, sc))
            local pp = P_get("en_pupil")
            pp:set_position(vis and V(x + (e.dx or 0) * 0.07 * sc, ey - 0.02 + ((e.dz or 0) < 0 and 0.05 or 0), z + ez + 0.02) or HIDE); pp:set_scale(V(sc, sc, sc))
        end
        local sd = P_get("shadow"); sd:set_position(V(x, 0.03, z)); sd:set_scale(V(0.55 * sc, 1, 0.55 * sc))
    end
    for _, k in ipairs(DYN) do if k ~= "brick" then P_end(k) end end
end

------------------------------------------------------------------ camera: tilted top-down, scrolls along X with the player
G.shake = 0
local CAM_D, CAM_P = 46, math.rad(62)
local function update_camera(dt)
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.5 * SET:shake_scale()
    local ox, oz = a * sin(G.t * 53), a * cos(G.t * 61)
    local C = G.cam
    if G.cam_ov then
        local o = G.cam_ov; cam:set_position(V(o[1], o[2], o[3])); cam:look_at(V(o[4], o[5], o[6])); C.tx, C.tz = o[4], o[6]; return
    end
    local half = CAM_D * math.tan(VFOV / 2) * SW / SH * 0.92
    local lo, hi = half - 1.5, (NC + 1) * CS + 1.5 - half
    local want = G.hide_player and (G.title_x or 32) or lerp(P.ox, P.x, AL) * CS
    local tx = lo < hi and clamp(want, lo, hi) or (NC + 1) / 2 * CS
    C.tx = damp(C.tx, tx, 6, dt)
    C.tz = (NR + 1) / 2 * CS + 0.4
    cam:set_position(V(C.tx + ox, CAM_D * sin(CAM_P), C.tz + CAM_D * cos(CAM_P) + oz))
    cam:look_at(V(C.tx + ox * 0.5, 0, C.tz + oz * 0.5))
end

------------------------------------------------------------------ collider debug overlay (F3): boxes on the ground plane
G.DBG = { on = false, pool = {}, used = 0, y = 2.3, w = 0.09 }
local DC = { wall = { .2, .9, 1 }, brick = { 1, .8, .2 }, player = { .2, 1, .3 }, enemy = { 1, .25, .2 }, flame = { 1, .55, .1 }, bomb = { .8, .4, 1 }, item = { 1, .4, .9 } }
function G.dbg_bar(x0, z0, x1, z1, col)
    local D = G.DBG
    D.used = D.used + 1
    local b = D.pool[D.used]
    if not b then
        if #D.pool >= 2500 then return end
        b = { n = prim("cube", HIDE, V(1, 1, 1)), col = nil }
        D.pool[D.used] = b
    end
    if b.col ~= col then b.col = col; paint(b.n, { col[1] * .3, col[2] * .3, col[3] * .3 }, { col[1] * 1.4, col[2] * 1.4, col[3] * 1.4 }, 0.5, 0) end
    local dx, dz = x1 - x0, z1 - z0
    b.n:set_position(V((x0 + x1) * .5, D.y, (z0 + z1) * .5))
    b.n:set_rotation(V(0, -math.deg(atan2(dz, dx)), 0))
    b.n:set_scale(V(sqrt(dx * dx + dz * dz) + D.w, D.w, D.w))
end
local function dbox(cx, cz, hx, hz, c)   -- centre + half extents in cells
    local x0, x1, z0, z1 = (cx - hx) * CS, (cx + hx) * CS, (cz - hz) * CS, (cz + hz) * CS
    G.dbg_bar(x0, z0, x1, z0, c); G.dbg_bar(x1, z0, x1, z1, c); G.dbg_bar(x1, z1, x0, z1, c); G.dbg_bar(x0, z1, x0, z0, c)
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and G.ST() then
        local cx = floor(G.cam.tx / CS + 0.5)
        for c = max(0, cx - 14), min(NC + 1, cx + 14) do for r = 0, NR + 1 do
            local s = solid_raw(c, r)
            if s == 1 then dbox(c, r, 0.5, 0.5, DC.wall) elseif s == 2 then dbox(c, r, 0.47, 0.47, DC.brick) end
        end end
        for _, b in ipairs(BOMBS) do dbox(b.c, b.r, 0.44, 0.44, DC.bomb) end
        for _, f in ipairs(FLS) do dbox(f.c, f.r, 0.4, 0.4, DC.flame) end
        if P.st ~= "dead" then dbox(P.x, P.z, G.CONST.HW, G.CONST.HW, DC.player); dbox(P.x, P.z, G.CONST.HIT_EN / 2, G.CONST.HIT_EN / 2, DC.player) end
        for _, e in ipairs(ENEMIES) do if e.alive then dbox(e.x, e.z, G.CONST.HIT_EN / 2, G.CONST.HIT_EN / 2, DC.enemy) end end
        if PU.exposed and not PU.taken then dbox(PU.c, PU.r, 0.3, 0.3, DC.item) end
        if EXIT.exposed then dbox(EXIT.c, EXIT.r, 0.3, 0.3, DC.item) end
    end
    for i = D.used + 1, #D.pool do D.pool[i].n:set_position(HIDE) end
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
    quad(id, { x = x, y = y, w = w, h = h, z = 4, style = "text", label = "", fill = { 0.04, 0.04, 0.06, a or 0.55 },
        border = border or { 0.35, 0.7, 1, 0.55 }, corner_radius = 12 * US, no_input = true, visible = vis ~= false })
end
local function button(id, label, cx, cy, vis)
    local w, h = 340 * US, 60 * US
    local st = vis and select(2, pcall(runtime_ui.get_state, UI, id))
    local hov = type(st) == "table" and st.hovered
    quad(id, { x = cx - w / 2, y = cy - h / 2, w = w, h = h, z = 12, style = "text", label = label,
        fill = hov and { 0.12, 0.3, 0.5, 0.92 } or { 0.05, 0.07, 0.1, 0.88 }, border = hov and { 0.6, 0.85, 1, 1 } or { 0.35, 0.65, 0.95, 0.9 },
        text_color = { 0.95, 0.95, 0.92, 1 }, font_scale = 1.25 * US, align_h = "center", align_v = "middle",
        corner_radius = 12 * US, visible = vis })
    return vis and type(st) == "table" and st.clicked
end
local function pad6(n) local s = tostring(floor(n)); return string.rep("0", max(0, 6 - #s)) .. s end
local RED, WHITE, CYAN, DIM, GOLD = { 1, .35, .3, 1 }, { 1, 1, 1, 1 }, { .5, .85, 1, 1 }, { .82, .8, .78, 1 }, { 1, .85, .45, 1 }
G.banner = { text = "", t = 0 }
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause" or st == "over" or st == "clear" or st == "intro") and not G.set_open
    local bh = 92 * US
    panel("hb", 20 * US, 12 * US, SW - 40 * US, bh, play, 0.62)
    local tcol = (G.time or 99) <= 10 and (floor(G.t * 4) % 2 == 0 and RED or WHITE) or WHITE
    text("htl", "TIME", 50 * US, 16 * US, 200 * US, 36 * US, 1.0, RED, "left", play)
    text("htv", tostring(math.ceil(G.time or 0)), 50 * US, 48 * US, 200 * US, 52 * US, 1.8, tcol, "left", play)
    text("hsl", "SCORE", 250 * US, 16 * US, 300 * US, 36 * US, 1.0, RED, "left", play)
    text("hsv", tostring(G.score), 250 * US, 48 * US, 300 * US, 52 * US, 1.8, WHITE, "left", play)
    local st_ = G.ST()
    text("hstg", st_ and string.format("Stage %d", st_.n) or "", SW / 2 - 200 * US, 16 * US, 400 * US, 40 * US, 1.3, CYAN, "center", play)
    local flags = {}
    if P.detonator then flags[#flags + 1] = "Detonator" end
    if P.wallpass then flags[#flags + 1] = "Wall Pass" end
    if P.bombpass then flags[#flags + 1] = "Bomb Pass" end
    if P.flamepass then flags[#flags + 1] = "Flame Pass" end
    if P.inv > 0 then flags[#flags + 1] = "Mystery " .. math.ceil(P.inv) end
    if P.speed > 0 then flags[#flags + 1] = "Speed" end
    text("hpu", string.format("Bombs %d  ·  Fire %d", P.bombs, P.fire) .. (#flags > 0 and ("  ·  " .. table.concat(flags, "  ·  ")) or ""),
        SW / 2 - 420 * US, 56 * US, 840 * US, 40 * US, 0.95, GOLD, "center", play)
    text("hel", "ENEMIES", SW - 560 * US, 16 * US, 200 * US, 36 * US, 1.0, RED, "left", play)
    text("hev", tostring(G.alive or 0), SW - 560 * US, 48 * US, 200 * US, 52 * US, 1.8, WHITE, "left", play)
    text("hll", "LEFT", SW - 360 * US, 16 * US, 140 * US, 36 * US, 1.0, RED, "left", play)
    local nl = G.lives - ((st == "play" and P.st ~= "dead") and 1 or 0)
    text("hlv", tostring(max(0, nl)), SW - 360 * US, 48 * US, 140 * US, 52 * US, 1.8, WHITE, "left", play)
    text("hh", "HIGH", SW - 220 * US, 16 * US, 170 * US, 36 * US, 1.0, RED, "right", play)
    text("hhs", tostring(max(G.hiscore, G.score)), SW - 300 * US, 48 * US, 250 * US, 52 * US, 1.6, WHITE, "right", play)
    -- popups
    for i, p in ipairs(G.POP) do
        p.t = p.t + dt
        local vis = (st == "play" or st == "clear") and not G.set_open and p.t < 1.1
        local px, py = 0, 0
        if vis then px, py = project(vec3(p.x * CS, 2.4 + p.t * 1.5, p.z * CS)) end
        local a = floor(clamp((1.1 - p.t) / 0.3, 0, 1) * 10) / 10
        text("pop" .. i, p.txt or "", px - 140 * US, py - 18 * US, 280 * US, 36 * US, 1.1, { p.col[1] or 1, p.col[2] or 1, p.col[3] or 1, a }, "center", vis)
    end
    G.banner.t = (G.banner.t or 0) - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    local ban_on = (G.banner.t or 0) > 0 and not G.set_open and (st == "play" or st == "title" or st == "intro")
    text("ban", G.banner.text or "", 0, SH * 0.42, SW, 80 * US, 2.4, { 1, .85, .5, ba }, "center", ban_on)
    -- stage card / clear
    local card = st == "intro" and not G.set_open
    -- light veil so the arena shows through, with a soft band behind the stage title
    panel("c_bg", 0, 0, SW, SH, card, 0.3, NONE)
    panel("c_band", 0, SH * 0.42 - 10 * US, SW, 160 * US, card, 0.42, NONE)
    text("c_stg", st_ and string.format("Stage %d", st_.n) or "", 0, SH * 0.42, SW, 100 * US, 3.2, WHITE, "center", card)
    text("c_pu", "", 0, SH * 0.42 + 100 * US, SW, 40 * US, 1.1, DIM, "center", card)
    local clr = st == "clear" and not G.set_open
    panel("k_bg", SW / 2 - 380 * US, SH * 0.32, 760 * US, 160 * US, clr, 0.6)
    text("k_t", "Stage Clear", 0, SH * 0.32 + 40 * US, SW, 80 * US, 2.6, GOLD, "center", clr)
    local dead = st == "play" and P.st == "dead" and (P.dead_t or 0) > 1.0 and not G.set_open and P.cause == "time"
    text("d_t", "Time Up", 0, SH * 0.4, SW, 80 * US, 2.6, RED, "center", dead)
    -- title
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 480 * US, SH * 0.06, 960 * US, SH * 0.84, title, 0.62)
    text("t_title", "Bomberman Remix", 0, SH * 0.08, SW, 130 * US, 4.4, { 1, .5, .3, 1 }, "center", title)
    text("t_sub", "Blast through 50 stages of bricks, find the exit and wipe out every enemy", 0, SH * 0.08 + 118 * US, SW, 40 * US, 1.05, DIM, "center", title)
    text("t_ctl1", "WASD or Arrow keys: walk   ·   Space / Z / J / Left Click: drop a bomb", 0, SH * 0.68, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_ctl2", "X / K / Right Click: Detonator (once you have it)   ·   find the exit under a brick", 0, SH * 0.68 + 34 * US, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_ctl3", "P / Esc: pause   ·   O: settings   ·   M: mute   ·   F3: colliders", 0, SH * 0.68 + 68 * US, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_hi", "High score " .. tostring(G.hiscore), 0, SH * 0.68 + 112 * US, SW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, CYAN, "center", pause)
    local over = st == "over" and not G.set_open
    local win = G.won
    panel("o_bg", SW / 2 - 380 * US, SH * 0.24, 760 * US, SH * 0.52, over, 0.78)
    text("o_t", win and "Congratulations" or "Game Over", 0, SH * 0.26, SW, 90 * US, 3.0, win and GOLD or RED, "center", over)
    text("o_s", "Score " .. tostring(G.score) .. "  ·  Stage " .. tostring(G.ST() and G.ST().n or 1), 0, SH * 0.26 + 90 * US, SW, 40 * US, 1.3, DIM, "center", over)
    local c = {}
    local hasc = title and (G.cont_stage or 1) > 1
    local yb = SH * 0.36
    c.start = button("b_start", "Start (Enter)", SW / 2 - 190 * US, yb, title)
    c.jev = button("b_jev", "Jev", SW / 2 + 190 * US, yb, title)
    yb = yb + 76 * US
    c.cont = button("b_cont", "Continue Stage " .. tostring(G.cont_stage or 1), SW / 2, yb, hasc); if hasc then yb = yb + 76 * US end
    c.set_t = button("b_set_t", "Settings (O)", SW / 2, yb, title); yb = yb + 76 * US
    c.quit_app = button("b_quit_app", "Quit Game", SW / 2, yb, title)
    c.resume = button("b_resume", "Resume (P)", SW / 2, SH * 0.42, pause)
    c.set_p = button("b_set_p", "Settings (O)", SW / 2, SH * 0.42 + 76 * US, pause)
    c.quit = button("b_quit", "Quit to Title (Q)", SW / 2, SH * 0.42 + 152 * US, pause)
    local ov = over and (G.over_t or 0) > 1.2
    c.again = button("b_again", "Play Again (Enter)", SW / 2, SH * 0.5, ov)
    c.title = button("b_title", "Title (Esc)", SW / 2, SH * 0.5 + 76 * US, ov)
    return c
end

------------------------------------------------------------------ flow
local function to_title()
    G.state = "title"; G.won = false; G.cam_ov = nil
    G.stage_reset(1 + floor(rand() * 12))
    G.hide_player = true
    music("title")
end
G.to_title = to_title
local function start_stage(n, keep)
    G.stage_reset(n, keep); G.fx_clear(); G.CHUNKS = {}
    G.hide_player = false
    G.state = "intro"; G.intro_t = 0
    music(nil); sfx("ready")
end
G.start_stage = start_stage
local function new_game(n)
    G.score, G.lives = 0, 3
    start_stage(n or 1)
end
G.new_game = new_game

local JevAuto = assert(load(fs.read("Scripts/jev_auto.lua"), "@Scripts/jev_auto.lua", "t", _ENV))()
local WALK_KEYS = {
    left = { "Left", "A" },
    right = { "Right", "D" },
    up = { "Up", "W" },
    down = { "Down", "S" },
}
local PULSE_KEYS = { "Z", "J", "X", "K" }
local HUMAN_KEYS = {
    "Left", "Right", "Up", "Down", "A", "D", "W", "S", "Space", "Z", "J", "X", "K",
}
local human_prev = {}

local function clear_virtual()
    G.vk = {}
end

local function clear_walk()
    if not G.vk then
        return
    end

    for _, keys in pairs(WALK_KEYS) do
        for i = 1, #keys do
            G.vk[keys[i]] = nil
        end
    end
end

local function apply_jev(id)
    G.vk = G.vk or {}
    local walk = WALK_KEYS[id]
    if walk then
        clear_walk()
        for i = 1, #walk do
            G.vk[walk[i]] = true
        end
        G.vk.Z = true
        G.vk.J = true
        return
    end

    if id == "stop" then
        clear_walk()
        return
    end

    if id == "bomb" then
        G.vk.Z = true
        G.vk.J = true
        return
    end

    if id == "detonate" then
        G.vk.X = true
        G.vk.K = true
    end
end

local function consume_pulses()
    if not G.vk then
        return
    end

    for i = 1, #PULSE_KEYS do
        local key = PULSE_KEYS[i]
        if G.vk[key] then
            G.vk[key] = nil
            local raw = false
            if input.is_key_down_raw then
                local ok, down = pcall(input.is_key_down_raw, key)
                raw = ok and down and true or false
            end
            if not raw then
                prev[key] = false
            end
        end
    end
end

local function human_edge()
    local hit = false
    if input.is_key_down_raw then
        for i = 1, #HUMAN_KEYS do
            local key = HUMAN_KEYS[i]
            local ok, down = pcall(input.is_key_down_raw, key)
            down = ok and down and true or false
            if down and not human_prev[key] then
                hit = true
            end
            human_prev[key] = down
        end
    end

    return G.state == "play" and hit
end

local function jev_observe()
    local pc = floor(P.x + 0.5)
    local pr = floor(P.z + 0.5)
    local best = nil
    local best_d = nil
    for i = 1, #ENEMIES do
        local enemy = ENEMIES[i]
        if enemy.alive then
            local ec = floor(enemy.x + 0.5)
            local er = floor(enemy.z + 0.5)
            local dist = abs(ec - pc) + abs(er - pr)
            if not best_d or dist < best_d then
                best_d = dist
                best = { c = ec, r = er }
            end
        end
    end

    return {
        cell = { c = pc, r = pr },
        nearest_enemy = best,
        bombs = P.bombs,
        lives = G.lives,
        score = G.score,
    }
end

local function jev_actions()
    local view = jev_observe()
    local foe = view.nearest_enemy
    if not foe then
        return { { id = "right", description = "Walk and drop a bomb.", score = 1 } }
    end
    local dc = foe.c - view.cell.c
    local dr = foe.r - view.cell.r
    if math.abs(dc) >= math.abs(dr) and dc ~= 0 then
        if dc > 0 then
            return { { id = "right", description = "Walk right toward the enemy and drop a bomb.", score = dc } }
        end
        return { { id = "left", description = "Walk left toward the enemy and drop a bomb.", score = -dc } }
    end
    if dr > 0 then
        return { { id = "down", description = "Walk down toward the enemy and drop a bomb.", score = dr } }
    end
    if dr < 0 then
        return { { id = "up", description = "Walk up toward the enemy and drop a bomb.", score = -dr } }
    end
    return { { id = "right", description = "On the enemy. Walk and drop a bomb.", score = 1 } }
end

local jev = JevAuto.attach({
    port = 9134,
    id = "bomberman_remix",
    description = "Bomberman Remix. The offered action walks toward the nearest enemy and drops a bomb. Prefer the higher action score.",
    playing = function()
        return G.state == "play"
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
    observe = jev_observe,
    actions = jev_actions,
    apply = apply_jev,
    reset = function(seed)
        math.randomseed(seed)
        clear_virtual()
        new_game(1)
    end,
    on_human = clear_virtual,
})

local function game_over(won)
    G.state = "over"; G.over_t = 0; G.won = won
    music(nil); sfx(won and "clear" or "gameover")
    if not jev:assisted() and G.score > G.hiscore then
        G.hiscore = G.score
        save_hi()
    end
end
G.cont_stage = 1
local acc = 0
G.bomb_q, G.det_q = false, false
local mouse_prev, rmouse_prev = true, true
local DIRK = { up = { "Up", "W" }, down = { "Down", "S" }, left = { "Left", "A" }, right = { "Right", "D" } }
local order = {}
local function update(dt)
    jev:tick(dt)
    if G.on_frame then G.on_frame(dt) end
    G.fx_update(dt)
    flush_mats()
    dt = min(dt, 0.1)
    G.t = G.t + dt; G.dt = dt
    local k = { ret = edge("Return"), space = edge("Space"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), q = edge("Q"),
        z = edge("Z"), j = edge("J"), x = edge("X"), kk = edge("K"), f3 = edge("F3") }
    local md, rd = false, false
    pcall(function() md = input.is_left_mouse_down() and true or false end)
    pcall(function() rd = input.is_right_mouse_down and input.is_right_mouse_down() and true or false end)
    local mclick = md and not mouse_prev; mouse_prev = md
    local rclick = rd and not rmouse_prev; rmouse_prev = rd
    consume_pulses()
    -- direction press order (newest first) for the "take whichever way is open" rule
    for nm, ks in pairs(DIRK) do
        local h = any(ks[1], ks[2])
        local idx = nil
        for i, o in ipairs(order) do if o == nm then idx = i end end
        if h and not idx then table.insert(order, 1, nm) elseif not h and idx then table.remove(order, idx) end
    end
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end; mclick = false; rclick = false end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        G.title_x = 32 + 18 * sin(G.t * 0.12)
        if c.jev then
            sfx("click")
            local ok = jev:start()
            if not ok then
                local err = jev:error() or "Jev could not start"
                G.banner.text = err
                G.banner.t = 6
                pe_log("[BM] " .. err)
            end
        elseif k.ret or k.space or c.start then
            sfx("click")
            jev:begin_human()
            new_game(1)
        elseif c.cont then
            sfx("click")
            jev:begin_human()
            new_game(G.cont_stage)
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "intro" then
        G.intro_t = G.intro_t + dt
        if G.intro_t > 2.4 or ((k.ret or k.space or mclick) and G.intro_t > 0.4) then
            G.state = "play"; music("bgm" .. ((G.ST().n - 1) % 2 + 1)); G.bomb_q = false; G.det_q = false
        end
        if k.esc then to_title() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click") end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.q or c.quit then to_title() end
    elseif st == "clear" then
        G.clear_t = G.clear_t + dt
        if G.clear_t > 3.2 or ((k.ret or k.space) and G.clear_t > 0.8) then
            if G.ST().n >= 50 then game_over(true) else start_stage(G.ST().n + 1, true) end
        end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then
                sfx("click")
                jev:begin_human()
                new_game(1)
            elseif k.esc or c.title then to_title() end
        end
    end
    st = G.state
    local running = (st == "play" or st == "title") and not (G.set_open and st ~= "title")
    if running then
        if (k.space or k.z or k.j or mclick) and st == "play" then G.bomb_q = true end
        if (k.x or k.kk or rclick) and st == "play" then G.det_q = true end
        local inp = { order = {}, bomb = false, det = false }
        if st == "play" then for i, o in ipairs(order) do inp.order[i] = o end end
        if G.autoplay and st == "play" then G.autoplay_fn(inp) end
        local god = G.god
        if st == "title" then G.god = true; G.time = 200 end
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 6 do
            inp.bomb = G.bomb_q; G.bomb_q = false
            inp.det = G.det_q; G.det_q = false
            G.stage_step(inp, FR)
            acc = acc - FR; n = n + 1
            if st == "play" and P.st == "walk" and G.at_exit() then
                G.state = "clear"; G.clear_t = 0; P.st = "win"
                G.cont_stage = max(G.cont_stage, min(50, G.ST().n + 1))
                music(nil); sfx("clear")
                break
            end
        end
        if st == "title" then G.god = god; if (G.alive or 1) == 0 then G.stage_reset(1 + floor(rand() * 12)) end end
        if acc > FR * 6 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if st == "play" and P.st == "dead" and P.dead_t >= 2.6 then
            G.lives = G.lives - 1
            if G.lives <= 0 then game_over(false) else start_stage(G.ST().n, true) end
        end
    else AL = 1 end
    if st == "clear" then
        -- keep flames/bricks animating and let him celebrate
        P.ox, P.oz = P.x, P.z
    end
    G.cam_ov = G.cam_ov_fixed
    update_camera(dt)
    render_dyn(dt)
    render_player(dt)
    update_flashes(dt)
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_world()
build_player()
G.autoplay_fn = function(inp)        -- debug bot for tests and screenshots only (G.autoplay = true)
    G.bot_t = (G.bot_t or 0) - G.dt
    if G.bot_t <= 0 then G.bot_t = 0.5 + rand(); G.bot_dir = ({ "up", "down", "left", "right" })[1 + floor(rand() * 4)] end
    inp.order[1] = G.bot_dir
    if rand() < 0.01 then G.bomb_q = true end
end
to_title()
G.update = update; G.SET = SET; G.surf = surf
hooks { update = update }
pe_log("[BM] ready")
