-- OUT RUN REMIX  (PhasmaEngine, Lua)
-- A faithful modern remake of Sega's Out Run (1986): drive the Ferrari Testarossa Spider down a branching route of
-- 15 roads (5 stages, pick left or right at every fork) to one of 5 goals before the timer runs out. Low/high gear,
-- traffic, checkpoints with extended time, crashes, radio selection. Fixed 60 Hz simulation with capped catch-up.
-- Track space: s = distance along the road (m), x = lateral offset (m, + = right). World: Y up, metres.
local PI = math.pi
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
math.randomseed(os and os.time and os.time() or 1985)
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local G = { state = "boot", t = 0 }
_G.OR = G

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
local ss = scene.add_empty_node("OutRunSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "day.hdr")
S("hdr", false); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false); S("dof", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.2)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", true); S("IBL_intensity", 0.55)
S("color_grading", true); S("color_grading_saturation", 1.05); S("color_grading_contrast", 1.04)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "SETTINGS", subtitle = "Out Run Remix", file = "Save/settings.cfg", music = true,
    click = function() sfx("click") end, defaults = { master = 0.5 },
    theme = { accent = { 0.35, 0.75, 1, 1 }, accent2 = { 1, 0.55, 0.3, 1 }, text = { 0.86, 0.84, 0.8, 1 }, selected_text = { 1, 0.97, 0.9, 1 } } })
SET:apply()
G.set_open = false

------------------------------------------------------------------ camera
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1600, surf.height or 900
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local VFOV = math.rad(46)
local FOVX = 2 * math.atan(math.tan(VFOV / 2) * SW / SH)
pcall(function() cam:set_fov(math.deg(FOVX)) end)
pcall(function() cam:set_far_plane(3000) end)
G.cam = { pos = vec3(0, 3, -8), look = vec3(0, 1, 10) }
local function project(p)
    local c, l = G.cam.pos, G.cam.look
    local fx, fy, fz = l.x - c.x, l.y - c.y, l.z - c.z
    local fl = sqrt(fx * fx + fy * fy + fz * fz); fx, fy, fz = fx / fl, fy / fl, fz / fl
    local rx, rz = -fz, fx; local rl = sqrt(rx * rx + rz * rz); rx, rz = rx / rl, rz / rl
    local ux, uy, uz = -rz * fy, rz * fx - rx * fz, rx * fy
    local dx, dy, dz = p.x - c.x, p.y - c.y, p.z - c.z
    local zc = dx * fx + dy * fy + dz * fz
    if zc < 0.1 then return -9999, -9999 end
    local th = math.tan(VFOV / 2)
    return SW / 2 + (dx * rx + dz * rz) / (zc * th) * SH / 2, SH / 2 - (dx * ux + dy * uy + dz * uz) / (zc * th) * SH / 2
end
------------------------------------------------------------------ templates -> clones
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[OR] missing template " .. name); return nil end
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
local PAL = {
    car_body = { { .78, .03, .03 }, { .02, 0, 0 }, .22, .35 }, car_under = { { .05, .05, .05 }, { 0, 0, 0 }, .8 },
    car_strake = { { .04, .04, .04 }, { 0, 0, 0 }, .4 }, car_grille = { { .06, .06, .06 }, { 0, 0, 0 }, .4, .3 },
    car_tail = { { .9, .1, .08 }, { .9, .06, .03 }, .3 }, car_head = { { .95, .95, .9 }, { .4, .4, .35 }, .2 },
    car_glass = { { .25, .3, .35 }, { 0, 0, 0 }, .05, .6 }, car_frame = { { .08, .08, .08 }, { 0, 0, 0 }, .3, .5 },
    car_seat = { { .62, .42, .25 }, { 0, 0, 0 }, .6 }, car_cabin = { { .08, .07, .06 }, { 0, 0, 0 }, .8 },
    car_wheelin = { { .1, .1, .1 }, { 0, 0, 0 }, .5 }, car_mirror = { { .78, .03, .03 }, { .02, 0, 0 }, .22, .35 },
    car_tire = { { .05, .05, .05 }, { 0, 0, 0 }, .85 }, car_rim = { { .75, .76, .8 }, { 0, 0, 0 }, .25, .9 },
    car_shadow = { { .09, .09, .08 }, { 0, 0, 0 }, 1 },
    drv_skin = { { .95, .7, .55 }, { .01, .005, .005 }, .55 }, drv_hair = { { .08, .05, .03 }, { 0, 0, 0 }, .6 },
    pas_hair = { { .98, .85, .45 }, { .03, .02, 0 }, .5 }, drv_shirt = { { .92, .92, .9 }, { .01, .01, .01 }, .7 },
    tr_beetle = { { .95, .78, .1 }, { .02, .015, 0 }, .3, .2 }, tr_vette = { { .15, .3, .8 }, { 0, .005, .02 }, .25, .35 },
    tr_cab = { { .85, .85, .88 }, { .01, .01, .01 }, .4, .2 }, tr_box = { { .92, .9, .85 }, { .01, .01, .01 }, .6 },
    tr_glass = { { .15, .18, .22 }, { 0, 0, 0 }, .05, .6 }, tr_wind = { { .15, .18, .22 }, { 0, 0, 0 }, .05, .6 }, tr_lamp = { { .9, .1, .08 }, { .8, .05, .02 }, .3 },
    road = { { .9, .9, .9 }, { 0, 0, 0 }, .85 }, rumble_r = { { .8, .08, .06 }, { .02, 0, 0 }, .6 }, rumble_w = { { .92, .92, .92 }, { .02, .02, .02 }, .6 },
    ground = { { 1, 1, 1 }, { 0, 0, 0 }, .95 }, divider = { { .85, .85, .85 }, { 0, 0, 0 }, .5 }, horizon = { { 0, 0, 0 }, { 1, 1, 1 }, 1 },
    palm_trunk = { { .48, .36, .24 }, { 0, 0, 0 }, .85 }, palm_leaves = { { .2, .55, .18 }, { .005, .02, .005 }, .6 },
    bush = { { .22, .45, .16 }, { 0, .01, 0 }, .8 }, rock = { { .55, .5, .45 }, { 0, 0, 0 }, .9 }, cliff = { { .62, .36, .24 }, { 0, 0, 0 }, .95 },
    pine_trunk = { { .35, .23, .15 }, { 0, 0, 0 }, .9 }, pine_leaves = { { .1, .32, .15 }, { 0, .01, 0 }, .8 }, pine_snow = { { .8, .85, .88 }, { .03, .03, .04 }, .7 },
    cactus = { { .28, .5, .22 }, { 0, .01, 0 }, .7 }, bld_0 = { { 1, 1, 1 }, { 0, 0, 0 }, .7 }, bld_1 = { { 1, 1, 1 }, { 0, 0, 0 }, .7 },
    bld_2 = { { 1, 1, 1 }, { 0, 0, 0 }, .7 }, roof = { { .6, .22, .14 }, { 0, 0, 0 }, .7 },
    windmill = { { .88, .85, .78 }, { 0, 0, 0 }, .7 }, blades = { { .45, .3, .2 }, { 0, 0, 0 }, .7 },
    column = { { .9, .88, .82 }, { .01, .01, .01 }, .6 }, vine = { { .25, .42, .15 }, { 0, .01, 0 }, .8 },
    lamp = { { .3, .32, .35 }, { 0, 0, 0 }, .4, .7 }, fence = { { .85, .85, .85 }, { 0, 0, 0 }, .5, .3 },
    sign_post = { { .5, .5, .5 }, { 0, 0, 0 }, .4, .6 }, sign_board = { { 1, 1, 1 }, { .25, .25, .25 }, .5 }, sign_board_r = { { 1, 1, 1 }, { .25, .25, .25 }, .5 },
    arch = { { .85, .85, .88 }, { .01, .01, .01 }, .5, .3 }, ban_start = { { 1, 1, 1 }, { .35, .35, .35 }, .5 },
    ban_check = { { 1, 1, 1 }, { .35, .35, .35 }, .5 }, ban_goal = { { 1, 1, 1 }, { .35, .35, .35 }, .5 },
    deb_red = { { .78, .03, .03 }, { .02, 0, 0 }, .3, .3 }, deb_dark = { { .06, .06, .06 }, { 0, 0, 0 }, .6 },
    flagman = { { .2, .2, .25 }, { 0, 0, 0 }, .7 }, flag = { { 1, 1, 1 }, { .2, .2, .2 }, .6 },
}
local function paint_templates()
    for name, v in pairs(PAL) do paint(tnode(name), v[1], v[2], v[3], v[4]) end
    mtex(tnode("road"), "base_color", "Textures/road.png")
    for _, k in ipairs({ "bld_0", "bld_1", "bld_2" }) do mtex(tnode(k), "base_color", "Textures/facade.png") end
    mtex(tnode("sign_board"), "base_color", "Textures/sign_curve.png"); mtex(tnode("sign_board_r"), "base_color", "Textures/sign_curve_r.png")
    for _, k in ipairs({ "ban_start", "ban_check", "ban_goal" }) do mtex(tnode(k), "base_color", "Textures/" .. k .. ".png") end
    mtex(tnode("flag"), "base_color", "Textures/flag.png")
    pcall(_mds, tnode("horizon"), true); pcall(_mds, tnode("flag"), true)
    for name in pairs(PAL) do local n = tnode(name); if n then n:set_position(HIDE) end end
end
G.theme_key = nil
local function set_theme(th)
    if G.theme_key == th.key then return end
    G.theme_key = th.key
    mtex(tnode("ground"), "base_color", "Textures/gr_" .. th.ground .. ".png")
    mtex(tnode("horizon"), "emissive", "Textures/hz_" .. th.sky .. ".png")
    if G.farplane then paint(G.farplane, th.far, { 0, 0, 0 }, 1, 0) end
end

------------------------------------------------------------------ lights (sun + fill that ride with the car)
local LT = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(-0.35, -0.8, 0.45), vec3(1.0, 0.96, 0.9), 1.5)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    LT.key = addp(vec3(0, 20, 0), vec3(1.0, 0.96, 0.9), 50, 60)
    LT.fill = addp(vec3(0, 6, 0), vec3(0.85, 0.9, 1.0), 25, 30)
    LT.flash = {}
    for i = 1, 3 do LT.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1 } end
end
G.LT = LT
G.flash_next = 1
local function flash(p, col, power, life, rad)
    local f = LT.flash[G.flash_next]; G.flash_next = G.flash_next % #LT.flash + 1
    f.t, f.life, f.p, f.col, f.power, f.rad = 0, life or 0.3, p, vec3(col[1], col[2], col[3]), power or 40, rad or 7
end
local function update_lights(dt, carp)
    set_point(LT.key, vec3(carp.x - 8, carp.y + 18, carp.z - 6), vec3(1.0, 0.96, 0.9), 50, 60)
    set_point(LT.fill, vec3(carp.x + 4, carp.y + 5, carp.z - 9), vec3(0.85, 0.9, 1.0), 25, 30)
    for _, f in ipairs(LT.flash) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = 1 - clamp(f.t / f.life, 0, 1)
            set_point(f.idx, f.p, f.col, f.power * k * k, f.rad)
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

------------------------------------------------------------------ score state
G.score, G.hiscore = 0, 0
pcall(function() local s = fs.read("Save/outrun_hiscore.txt"); if s then G.hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, "Save/outrun_hiscore.txt", tostring(G.hiscore)) end
local function add_score(n) G.score = G.score + n end
------------------------------------------------------------------ FX: particle effects on top of Scripts/Lib/particles.lua
-- Scripts/Lib/particles.lua is a verbatim copy of the shared helper (common/particles.lua). It loads the textures in
-- Textures/fx/ and provides the explosion / fireball / embers / debris presets used here.
-- Engine facts this layer works around (see tools/gen_fx_pm.py):
--   * the particle pass SCREEN-blends and multiplies colour by texture RGB; alpha only kills/discards, so the
--     textures in Textures/fx/ are premultiplied, particles can only brighten (smoke is a light veil) and every
--     fade happens in RGB (color_end rgb -> 0);
--   * orientation strings: "billboard", "horizontal" (flat on the ground), "velocity" (stretched streaks);
--   * flipbook settings only apply through particles.set_emitter after emit_burst.
local FX = { tex = {}, scale = 1 }   -- scale: world size of the effects (1 = metre-sized cars)
G.FX = FX
FX.lib = load(fs.read("Scripts/Lib/particles.lua"), "@particles.lua")().new({
    scale = PS, gain = 1, light = function(pos, col, power, life, radius) if G.fx_light then G.fx_light(pos, col, power, life, radius) end end })
FX.tex = FX.lib.tex
for _, k in ipairs({ "dust", "foam" }) do
    local ok, idx = pcall(particles.load_texture, "Textures/fx/" .. k .. ".png")
    FX.tex[k] = (ok and type(idx) == "number") and idx or 0
end
local BOOK = { fire = { 4, 4 }, smoke = { 4, 4 }, debris = { 2, 2 } }
local function fxv(t) return vec3(t[1], t[2], t[3]) end
-- one burst; o: n, vel{}, c0{}, c1{}, s0, s1, l0, l1, r, sp(read), drag, grav{}, stretch, flat, anim
function FX.emit(tex, x, y, z, o)
    local n = max(1, floor((o.n or 8) * PS() + 0.5))
    local k = FX.scale
    local c0, c1 = o.c0 or { 1, 1, 1 }, o.c1 or { 0, 0, 0 }
    local ok, id = pcall(particles.emit_burst, {
        position = vec3(x, y, z), velocity = o.vel and fxv(o.vel) or vec3(0, 0, 0),
        color_start = vec4(c0[1], c0[2], c0[3], 1), color_end = vec4(c1[1], c1[2], c1[3], 0.02), count = n,
        size_min = (o.s0 or 0.2) * k, size_max = (o.s1 or 0.4) * k, life_min = o.l0 or 0.4, life_max = o.l1 or 0.8,
        spawn_radius = (o.r or 0.2) * k, noise_strength = (o.sp or 2) * k, drag = o.drag or 1.5,
        gravity = o.grav and vec3(o.grav[1] * k, o.grav[2] * k, o.grav[3] * k) or vec3(0, 0, 0),
        texture_index = FX.tex[tex] or 0, orientation = o.flat and "horizontal" or (o.stretch and "velocity" or "billboard"),
        cleanup_delay = (o.l1 or 0.8) + 1.0,
    })
    local b = BOOK[tex]
    if ok and b and id then pcall(particles.set_emitter, id, { anim_cols = b[1], anim_rows = b[2], anim_speed = o.anim or (1 / (o.l1 or 0.8)), interpolate = true }) end
end
local function sc(c, k) return { c[1] * k, c[2] * k, c[3] * k } end
-- presets (k = intensity 0..1+, vel = carried velocity table)
function FX.smoke(x, y, z, k, vel, grey, size)   -- light grey billow (flipbook)
    k = k or 1; local g = (grey or 0.42) * 1.7; size = size or 1   -- the premultiplied flipbook peaks near half density
    FX.emit("smoke", x, y, z, { n = 2 + 2 * k, vel = vel, c0 = { g * k, g * k, g * 1.02 * k }, c1 = { 0, 0, 0 }, s0 = 0.8 * size, s1 = 1.7 * size,
        l0 = 0.9, l1 = 1.8, r = 0.3 * size, sp = 1.4, drag = 2.2, grav = { 0, 0.9, 0 } })
end
function FX.dust(x, y, z, col, k, vel, size)      -- grainy cloud tinted by the ground
    k = k or 1; size = size or 1
    FX.emit("dust", x, y, z, { n = 2 + 3 * k, vel = vel, c0 = sc(col, k), c1 = { 0, 0, 0 }, s0 = 0.5 * size, s1 = 1.2 * size,
        l0 = 0.5, l1 = 1.1, r = 0.35 * size, sp = 2.4, drag = 2.6, grav = { 0, 0.5, 0 } })
end
function FX.grit(x, y, z, col, n, vel)            -- thrown clods / clippings / snow chunks
    FX.emit("debris", x, y, z, { n = n or 6, vel = vel, c0 = col, c1 = sc(col, 0.3), s0 = 0.06, s1 = 0.14, l0 = 0.35, l1 = 0.7,
        r = 0.2, sp = 5, drag = 0.8, grav = { 0, -14, 0 }, anim = 0.01 })
end
function FX.sparks(x, y, z, n, vel, spread)       -- streaks stretched along their velocity
    FX.emit("spark", x, y, z, { n = n or 16, vel = vel, c0 = { 2.2, 1.6, 0.8 }, c1 = { 0.6, 0.15, 0.02 }, s0 = 0.08, s1 = 0.16,
        l0 = 0.2, l1 = 0.5, r = 0.1, sp = spread or 10, drag = 1.8, grav = { 0, -9, 0 }, stretch = true })
end
function FX.flash(x, y, z, size, col)
    col = col or { 1.6, 1.1, 0.6 }
    FX.emit("soft", x, y, z, { n = 1 / max(PS(), 0.01), c0 = col, c1 = { 0, 0, 0 }, s0 = size, s1 = size * 1.1, l0 = 0.08, l1 = 0.12, r = 0, sp = 0, drag = 0 })
end
function FX.fire(x, y, z, k, size, vel)           -- licking flames, rising (flipbook)
    k = k or 1; size = size or 1
    FX.emit("fire", x, y, z, { n = 2 + 3 * k, vel = vel, c0 = { 1.5 * k, 1.0 * k, 0.55 * k }, c1 = { 0.25, 0.04, 0 }, s0 = 0.4 * size, s1 = 0.9 * size,
        l0 = 0.25, l1 = 0.55, r = 0.3 * size, sp = 1.5, drag = 2.5, grav = { 0, 3.5, 0 } })
end
function FX.ring(x, y, z, size, col, flat)
    FX.emit("ring", x, y, z, { n = 1 / max(PS(), 0.01), c0 = col or { 0.6, 0.55, 0.5 }, c1 = { 0, 0, 0 }, s0 = size, s1 = size, l0 = 0.25, l1 = 0.3, r = 0, sp = 0, flat = flat })
end
-- full explosion: the shared preset (flash, fireball, sparks, embers, smoke, debris) at this game's scale,
-- plus a carried smoke column so a wreck moving with the traffic leaves a trail
function FX.explosion(x, y, z, size, vel, debris_col)
    size = size or 1
    FX.lib:explosion(vec3(x, y, z), { size = size * FX.scale, smoke = true, debris = debris_col or { .35, .3, .26 }, spark_grav = -9 * FX.scale })
    FX.emit("smoke", x, y + 0.5 * FX.scale, z, { n = 4 * size, vel = vel, c0 = { 0.3, 0.29, 0.28 }, c1 = { 0, 0, 0 }, s0 = 1.4 * size, s1 = 2.8 * size,
        l0 = 1.2, l1 = 2.4, r = 1.0 * size, sp = 2.5 * size, drag = 1.6, grav = { 0, 1.6, 0 } })
end
function FX.spray(x, y, z, k, vel, size)          -- water spray / foam
    k = k or 1; size = size or 1
    FX.emit("foam", x, y, z, { n = 2 + 3 * k, vel = vel, c0 = { 0.75 * k, 0.82 * k, 0.88 * k }, c1 = { 0, 0, 0 }, s0 = 0.4 * size, s1 = 1.0 * size,
        l0 = 0.35, l1 = 0.8, r = 0.3 * size, sp = 3, drag = 1.8, grav = { 0, -6, 0 } })
end
------------------------------------------------------------------ the route: 15 roads in 5 stages (left/right fork after each)
local SEG = 5.0                      -- metres per segment
local HALF = 9.0                     -- road half width (4 lanes of 4.5 m)
local RUMB = 1.3                     -- rumble strip width
local FORK = 110                     -- fork length in segments
local FORK_D = 46                    -- branch offset at the end of a fork (m)
local COMMIT = 70                    -- segment in the fork where the choice is locked
local STAGE_LEN = 820                -- segments per road before the fork
G.TC = { SEG = SEG, HALF = HALF, RUMB = RUMB, FORK = FORK, FORK_D = FORK_D, COMMIT = COMMIT, STAGE_LEN = STAGE_LEN }
-- themes: ground texture, horizon panorama, far-plane colour, scenery mix {kind, weight}, curviness, hilliness, traffic
local TH = {
    beach   = { key = "beach", ground = "beach", sky = "beach", far = { .82, .74, .55 }, mix = { { "palm", 6 }, { "bush", 1 } }, curve = 0.8, hill = 0.4, traffic = 1.0, right = { { "palm", 1 } } },
    gateway = { key = "gateway", ground = "grass", sky = "green", far = { .3, .5, .22 }, mix = { { "column", 3 }, { "bush", 3 }, { "palm", 1 } }, curve = 1.0, hill = 0.6, traffic = 1.0 },
    canyon  = { key = "canyon", ground = "canyon", sky = "canyon", far = { .6, .33, .22 }, mix = { { "cliff", 3 }, { "rock", 4 } }, curve = 1.3, hill = 0.8, traffic = 0.9 },
    deso    = { key = "deso", ground = "dry", sky = "pale", far = { .6, .55, .38 }, mix = { { "rock", 3 }, { "bush", 2 }, { "sign", 1 } }, curve = 1.0, hill = 1.2, traffic = 1.0 },
    alps    = { key = "alps", ground = "alps", sky = "alps", far = { .45, .6, .42 }, mix = { { "pine_s", 5 }, { "rock", 1 } }, curve = 1.2, hill = 1.0, traffic = 1.0 },
    cloudy  = { key = "cloudy", ground = "dark", sky = "cloudy", far = { .24, .4, .24 }, mix = { { "pine", 5 }, { "rock", 1 } }, curve = 1.4, hill = 1.1, traffic = 1.1 },
    wheat   = { key = "wheat", ground = "wheat", sky = "wheat", far = { .8, .68, .35 }, mix = { { "windmill", 1 }, { "bush", 2 }, { "fence", 3 } }, curve = 0.8, hill = 0.7, traffic = 1.2 },
    town    = { key = "town", ground = "town", sky = "town", far = { .42, .42, .4 }, mix = { { "bld", 4 }, { "lamp", 3 }, { "palm", 1 } }, curve = 1.0, hill = 0.5, traffic = 1.4 },
    capital = { key = "capital", ground = "grass", sky = "dusk", far = { .3, .45, .22 }, mix = { { "column", 4 }, { "bld", 2 }, { "bush", 2 } }, curve = 1.1, hill = 0.7, traffic = 1.2 },
    wild    = { key = "wild", ground = "dry", sky = "desert", far = { .62, .52, .34 }, mix = { { "cactus", 3 }, { "rock", 3 } }, curve = 1.3, hill = 1.0, traffic = 1.0 },
    vine    = { key = "vine", ground = "vine", sky = "green", far = { .4, .45, .22 }, mix = { { "vine", 5 }, { "bush", 1 } }, curve = 1.1, hill = 0.8, traffic = 1.2 },
    death   = { key = "death", ground = "desert", sky = "canyon", far = { .8, .65, .45 }, mix = { { "rock", 3 }, { "cliff", 2 }, { "cactus", 1 } }, curve = 1.5, hill = 1.1, traffic = 1.0 },
    desert  = { key = "desert", ground = "desert", sky = "desert", far = { .85, .72, .5 }, mix = { { "cactus", 4 }, { "rock", 2 } }, curve = 1.2, hill = 0.9, traffic = 1.0 },
    autobahn = { key = "autobahn", ground = "grass", sky = "green", far = { .3, .5, .22 }, mix = { { "pine", 3 }, { "lamp", 2 }, { "fence", 2 } }, curve = 0.7, hill = 0.4, traffic = 1.6 },
    lake    = { key = "lake", ground = "lake", sky = "lake", far = { .3, .5, .22 }, mix = { { "pine", 4 }, { "bush", 1 } }, curve = 1.2, hill = 0.8, traffic = 1.1 },
}
-- the original map (row = stage 1..5, left to right); branch i of row k leads to i (left) or i+1 (right) of row k+1
local ROUTE = {
    { { "Coconut Beach", "beach" } },
    { { "Gateway", "gateway" }, { "Devil's Canyon", "canyon" } },
    { { "Desolation Hill", "deso" }, { "Alps", "alps" }, { "Cloudy Mountain", "cloudy" } },
    { { "Wheat Field", "wheat" }, { "Seaside Town", "town" }, { "Old Capital", "capital" }, { "Wilderness", "wild" } },
    { { "Vineyard", "vine" }, { "Death Valley", "death" }, { "Desert", "desert" }, { "Autobahn", "autobahn" }, { "Lakeside", "lake" } },
}
local GOALS = { "A", "B", "C", "D", "E" }
local EXTEND = { 75, 64, 62, 60, 58 }          -- start time, then time added at each checkpoint
G.ROUTE, G.TH, G.GOALS, G.EXTEND = ROUTE, TH, GOALS, EXTEND

------------------------------------------------------------------ segment storage (global index g, appended stage by stage)
local SG = {}          -- SG[g] = { x, y, z (start point), yaw (deg), curve (deg/seg), dy, fork (offset or nil), st (stage rec) }
local STAGES = {}      -- { row, col, name, th, g0, g1 (first seg of fork), gend, side, objs }
G.SG, G.STAGES = SG, STAGES
local function road_rng(row, col)
    local seed = row * 977 + col * 131 + 7
    return function() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
end
local function append_stage(row, col, base, gstart)
    local def = ROUTE[row][col]
    local th = TH[def[2]]
    local lr = road_rng(row, col)
    local st = { row = row, col = col, name = def[1], th = th, objs = {}, last = (row == 5) }
    local g = gstart or (#SG + 1)
    st.g0 = g
    local x, y, z, yaw = base[1], base[2], base[3], base[4]
    -- sections: {length, curve, hill amplitude}
    local secs = { { 40, 0, 0 } }
    local total = 40
    while total < STAGE_LEN - 40 do
        local len = 40 + floor(lr() * 70)
        local r = lr()
        local cv = 0
        if r < 0.62 * th.curve then
            local mag = (lr() < 0.35) and 1.9 or (lr() < 0.6 and 1.15 or 0.6)
            cv = mag * (lr() < 0.5 and -1 or 1)
        end
        local hl = (lr() < 0.55 * th.hill) and (lr() * 2 - 1) * 0.55 * th.hill or 0
        secs[#secs + 1] = { len, cv, hl }
        total = total + len
    end
    secs[#secs + 1] = { STAGE_LEN + (st.last and 60 or FORK) - total, 0, 0 }
    local i0 = 0
    for _, sc in ipairs(secs) do
        for k = 0, sc[1] - 1 do
            local t = k / sc[1]
            local ease = math.sin(PI * t)                 -- curves and hills ease in and out
            local cv = sc[2] * min(1, ease * 1.6)
            local dy = sc[3] * math.sin(2 * PI * t)
            SG[g] = { x = x, y = y, z = z, yaw = yaw, curve = cv, dy = dy, st = st, i = i0 }
            local yr = math.rad(yaw)
            x = x + SEG * math.sin(yr); z = z + SEG * math.cos(yr); y = y + dy
            yaw = yaw + cv
            g = g + 1; i0 = i0 + 1
        end
    end
    SG[g] = { x = x, y = y, z = z, yaw = yaw, curve = 0, dy = 0, st = st, i = i0, tail = true }
    st.gend = g
    -- keep the unshifted end point: once the next road is appended, SG[gend] becomes that road's first segment, which
    -- starts 46 m to one side (on the chosen branch). Geometry for the last fork segment must still end here.
    st.tail = SG[g]
    if not st.last then
        st.g1 = st.g0 + STAGE_LEN
        for gg = st.g1, st.gend do
            local j = (gg - st.g1) / FORK
            SG[gg].fork = FORK_D * clamp(j, 0, 1) ^ 1.7
        end
    end
    -- scenery (both sides, plus the median of the fork); s is the segment index inside the road
    local mix = th.mix
    local wsum = 0
    for _, m in ipairs(mix) do wsum = wsum + m[2] end
    local function pick()
        local r = lr() * wsum
        for _, m in ipairs(mix) do r = r - m[2]; if r <= 0 then return m[1] end end
        return mix[1][1]
    end
    local gi = st.g0 + 8
    while gi < st.gend - 2 do
        for _, sd in ipairs({ -1, 1 }) do
            if lr() < 0.75 then
                local k = pick()
                if th.right and sd > 0 and th.key == "beach" then k = (lr() < 0.4) and "palm" or nil end
                if k then
                    local off = HALF + RUMB + 3 + lr() * 9
                    if k == "cliff" then off = off + 9 end
                    if k == "bld" then off = off + 8 end
                    if k == "fence" or k == "lamp" then off = HALF + RUMB + 2.5 end
                    st.objs[#st.objs + 1] = { g = gi, x = sd * off, k = k, v = floor(lr() * 3), ry = lr() * 360 }
                end
            end
        end
        gi = gi + 3 + floor(lr() * 4)
    end
    -- warning signs before every sharp curve
    for gg = st.g0 + 20, st.gend - 1 do
        local s2 = SG[gg + 12]
        if s2 and abs(s2.curve) > 1.0 and abs(SG[gg].curve) < 0.4 and SG[gg].i % 7 == 0 then
            local left = s2.curve > 0
            st.objs[#st.objs + 1] = { g = gg, x = (left and 1 or -1) * (HALF + RUMB + 2.2), k = left and "sign_l" or "sign_r", v = 0, ry = 0 }
        end
    end
    -- roadside offsets were measured from the unsplit centre line, but inside the fork the two roads slide out to
    -- +-46 m, straight over that scenery (palms on the road ~1 min in, at the first fork). Inside the fork every
    -- roadside object now rides out with its branch: x is measured from the outer kerb of its own road.
    for _, o in ipairs(st.objs) do
        local f = SG[o.g] and SG[o.g].fork
        if f and o.x ~= 0 then o.x = o.x + (o.x > 0 and f or -f) end
    end
    -- the fork median: bushes and rocks only once the inner kerbs are far enough apart to hold them
    if st.g1 then
        for gg = st.g1, st.gend - 1, 5 do
            local k = (gg % 15 == 0) and "rock" or "bush"
            local need = HALF + RUMB + ((k == "rock") and 2.0 or 1.2) + 1.0
            if SG[gg].fork >= need then st.objs[#st.objs + 1] = { g = gg, x = 0, k = k, v = 0, ry = gg * 37, median = true } end
        end
    end
    -- gantries: START on the first road, CHECKPOINT on the others, GOAL at the end of stage 5
    st.objs[#st.objs + 1] = { g = st.g0 + 2, x = 0, k = (row == 1) and "start" or "check", v = 0, ry = 0, arch = true }
    if st.last then st.objs[#st.objs + 1] = { g = st.g0 + STAGE_LEN, x = 0, k = "goal", v = 0, ry = 0, arch = true } end
    table.sort(st.objs, function(a, b) return a.g < b.g end)
    STAGES[#STAGES + 1] = st
    return st
end
G.append_stage = append_stage
local function reset_route()
    for k in pairs(SG) do SG[k] = nil end
    for k in pairs(STAGES) do STAGES[k] = nil end
    append_stage(1, 1, { 0, 0, 0, 0 })
end
G.reset_route = reset_route
-- right vector of a heading (deg)
local function right_of(yaw) local r = math.rad(yaw); return -math.cos(r), math.sin(r) end
G.right_of = right_of
-- end point of segment g for geometry (road/ground pieces): the next segment, except across a road change where it
-- is this road's own unshifted tail (see append_stage)
local function seg_end(g)
    local a, b = SG[g], SG[g + 1]
    if a and b and b.st ~= a.st and a.st.tail then return a.st.tail end
    return b
end
G.seg_end = seg_end
-- lateral shift of the drivable centre line: after the fork choice the frame follows the chosen branch
local function shift_of(sg) if sg and sg.fork and sg.st.side then return sg.st.side * sg.fork end return 0 end
G.shift_of = shift_of
-- interpolated frame at distance s (m along the driven route); raw = the unshifted centre line
local function frame(s, raw)
    local gf = s / SEG
    local g = floor(gf); local t = gf - g
    g = g + 1
    local a, b = SG[g], SG[g + 1]
    if not a then a = SG[#SG]; t = 0 end
    if not b then b = a end
    local ax, az, bx, bz = a.x, a.z, b.x, b.z
    if not raw then
        local sa, sb = shift_of(a), shift_of(b)
        if sa ~= 0 then local rx, rz = right_of(a.yaw); ax, az = ax + rx * sa, az + rz * sa end
        if sb ~= 0 then local rx, rz = right_of(b.yaw); bx, bz = bx + rx * sb, bz + rz * sb end
    end
    local x, y, z = lerp(ax, bx, t), lerp(a.y, b.y, t), lerp(az, bz, t)
    local yaw = lerp(a.yaw, b.yaw, t)
    return x, y, z, yaw, a, t
end
G.frame = frame
local function world_at(s, x, h, raw)
    local cx, cy, cz, yaw = frame(s, raw)
    local rx, rz = right_of(yaw)
    return vec3(cx + rx * x, cy + (h or 0), cz + rz * x), yaw
end
G.world_at = world_at
------------------------------------------------------------------ car + traffic simulation (fixed 60 Hz)
local FR = 1 / 60
local SEGL, HALF, RUMB = G.TC.SEG, G.TC.HALF, G.TC.RUMB
local VMAX_L, VMAX_H = 190 / 3.6, 293 / 3.6
local CAR_HW, CAR_HL = 0.98, 2.25          -- Testarossa half width / half length (m)
G.CONST = { VMAX_L = VMAX_L, VMAX_H = VMAX_H, CAR_HW = CAR_HW, CAR_HL = CAR_HL }
local P = { s = 20, x = 0, v = 0, gear = "L", steer = 0, st = "drive", t = 0, yawv = 0, row = 1, col = 1 }
G.P = P
local CARS = {}
G.CARS = CARS
local OBJ_HW = { palm = 0.7, bush = 1.2, rock = 2.0, cliff = 7.5, pine = 1.0, pine_s = 1.0, cactus = 0.7, bld = 6.5, windmill = 2.2,
    column = 0.9, vine = 0.5, lamp = 0.3, fence = 0.2, sign_l = 1.5, sign_r = 1.5 }
G.OBJ_HW = OBJ_HW
local function seg_at(s) return SG[floor(s / SEGL) + 1] end
G.seg_at = seg_at
local function fork_raw(s) local a = seg_at(s); return (a and a.fork) or 0 end
-- branch offset interpolated inside the segment, exactly as frame() interpolates the shifted centre line
local function fork_at(s)
    local gf = s / SEGL; local g = floor(gf) + 1; local a, b = SG[g], SG[g + 1]
    if not a or not a.fork then return 0 end
    local fb = (b and b.st == a.st and b.fork) or a.fork
    return a.fork + (fb - a.fork) * (gf - floor(gf))
end
G.fork_at = fork_at
-- where the drivable surface is, in frame coordinates (x relative to the current frame)
local function surface(s, x)
    local a = seg_at(s)
    if not a then return "road" end
    local lanes = { 0 }
    if a.fork then
        local d = a.fork
        if a.st.side then lanes = { 0, -2 * a.st.side * d } else lanes = { -d, d } end
    end
    local best = 1e9
    for _, c in ipairs(lanes) do best = min(best, abs(x - c)) end
    if best <= HALF then return "road" elseif best <= HALF + RUMB then return "rumble" end
    return "off"
end
G.surface = surface
local function car_x(c)                     -- traffic lateral position in frame coordinates
    if c.side then return c.side * fork_raw(c.s) + c.lane end
    return c.lane
end
G.car_x = car_x
local LANES = { -6.75, -2.25, 2.25, 6.75 }
local KINDS = { "beetle", "vette", "truck", "beetle", "vette" }
local function spawn_car(s)
    local a = seg_at(s)
    if not a then return end
    local st = a.st
    if st.g1 and not st.side and floor(s / SEGL) + 1 >= st.gend - 1 then return end
    local c = { s = s, lane = LANES[1 + floor(rand() * 4)], v = rr(16, 31), k = KINDS[1 + floor(rand() * #KINDS)] }
    if c.k == "truck" then c.v = rr(15, 22) end
    if a.fork and not st.side and floor(s / SEGL) + 1 >= st.g1 then c.side = rand() < 0.5 and -1 or 1 end
    for _, o in ipairs(CARS) do if abs(o.s - c.s) < 14 and abs(car_x(o) - car_x(c)) < 3 then return end end
    CARS[#CARS + 1] = c
end
local function traffic_step(dt)
    local st = seg_at(P.s).st
    local want = floor(9 * st.th.traffic)
    if #CARS < want then spawn_car(P.s + 330 + rand() * 260) end
    for i = #CARS, 1, -1 do
        local c = CARS[i]
        c.s = c.s + c.v * dt
        local a = seg_at(c.s)
        if c.s < P.s - 60 or c.s > P.s + 900 or not a or (a.fork and a.st.side and c.side and c.side ~= a.st.side) then table.remove(CARS, i) end
    end
end

------------------------------------------------------------------ stage progress: forks, checkpoints, goal
-- Fork choice. It used to be decided silently by the sign of P.x at one segment, and the commit moved P.x into the
-- chosen branch's frame without moving P.ox (the previous step's x the renderer interpolates from), so for the rest
-- of that step the car and camera were drawn up to ~21 m sideways and snapped back: the view swapped back and forth.
-- Now: a tentative pick with hysteresis (the car must cross 2.5 m past the centre line to change it), shown on the
-- HUD; the pick locks as soon as the roads have separated and the car is fully on one of them (or at the latest at
-- segment COMMIT of the fork), and the frame change moves P.x and P.ox together by the exact interpolated offset.
local PICK_BAND = 2.5
local function commit_fork(st)
    local side = st.pick or ((P.x >= 0) and 1 or -1)
    st.side = side
    local d = side * fork_at(P.s)
    P.x = P.x - d
    if P.ox then P.ox = P.ox - d end
    G.fork_lock = { name = G.ROUTE[st.row + 1][st.col + (side > 0 and 1 or 0)][1], side = side, t = 2.2 }
    sfx("check")
    for i = #CARS, 1, -1 do
        local c = CARS[i]
        local a = seg_at(c.s)
        if c.side then
            if c.side ~= side then table.remove(CARS, i) else c.side = nil end
        end
    end
    local tail = SG[st.gend]
    local rx, rz = right_of(tail.yaw)
    local base = { tail.x + rx * side * G.TC.FORK_D, tail.y, tail.z + rz * side * G.TC.FORK_D, tail.yaw }
    local ncol = st.col + (side > 0 and 1 or 0)
    append_stage(st.row + 1, ncol, base, st.gend)
    if G.invalidate_slots then G.invalidate_slots() end
end
local function progress()
    local g = floor(P.s / SEGL) + 1
    local a = SG[g]
    if not a then return end
    local st = a.st
    if st ~= G.cur_stage then
        G.cur_stage = st
        set_theme(st.th)
        if st.row > 1 then
            G.time = G.time + G.EXTEND[st.row]
            G.laps[#G.laps + 1] = G.lap_t; G.lap_t = 0
            G.banner = { text = "Extended Play!", t = 2.6 }
            sfx("check")
        end
        P.row, P.col = st.row, st.col
    end
    if st.g1 and not st.side and g >= st.g1 - 30 then
        if P.x > PICK_BAND then st.pick = 1 elseif P.x < -PICK_BAND then st.pick = -1 end
        if g >= st.g1 then
            local f = fork_at(P.s)
            local on = st.pick and abs(P.x - st.pick * f) <= HALF - CAR_HW
            if (f >= HALF + RUMB + 1 and on) or g >= st.g1 + G.TC.COMMIT then commit_fork(st) end
        end
    end
    if st.last and g >= st.g0 + G.TC.STAGE_LEN and P.st ~= "goal" then
        P.st = "goal"; P.t = 0
        G.laps[#G.laps + 1] = G.lap_t
        G.goal = G.GOALS[st.col]
        G.bonus = floor(max(0, G.time)) * 250000
        music(nil); sfx("goal")
    end
end

------------------------------------------------------------------ collisions
local function crash(kind)
    if G.god then P.v = P.v * 0.5; return end
    if P.st == "timeup" then P.v = 0; G.shake = max(G.shake, 0.4); sfx("bump"); return end   -- out of time: just stop dead
    P.st = "crash"; P.t = 0; P.crash_v = P.v
    sfx("crash"); G.shake = 0.9
    local p, yaw = world_at(P.s, P.x, 0.6)
    G.crash_fx(p, yaw, P.crash_v)
end
local function hit_objects()
    local g = floor(P.s / SEGL) + 1
    local a = SG[g]
    if not a then return end
    local rawx = P.x + ((a.fork and a.st.side) and a.st.side * fork_at(P.s) or 0)
    local list = { a.st }
    if STAGES[#STAGES] ~= a.st then list[2] = STAGES[#STAGES] end
    for _, st in ipairs(list) do
        for _, o in ipairs(st.objs) do
            if o.g > g + 2 then break end
            if abs(o.g - g) <= 1 and abs((o.g - 1) * SEGL - P.s) < CAR_HL + 1.0 then
                if o.arch then
                    for _, px in ipairs({ -12.5, 12.5 }) do
                        if abs(rawx - px) < 0.7 + CAR_HW then
                            if P.v > 70 / 3.6 then crash("arch"); return else P.v = 0; P.x = P.x - (px > rawx and 0.6 or -0.6) end
                        end
                    end
                else
                    local hw = OBJ_HW[o.k] or 1
                    if abs(rawx - o.x) < hw + CAR_HW then
                        if P.v > 70 / 3.6 then crash(o.k); return
                        else P.v = 0; P.x = P.x + ((rawx > o.x) and 0.6 or -0.6); sfx("bump") end
                    end
                end
            end
        end
    end
end
local function hit_traffic()
    for _, c in ipairs(CARS) do
        local ds = c.s - P.s
        local hl = (c.k == "truck") and 3.4 or 2.1
        if abs(ds) < hl + CAR_HL then
            local dx = car_x(c) - P.x
            local hw = (c.k == "truck") and 1.2 or 0.9
            if abs(dx) < hw + CAR_HW then
                local dv = P.v - c.v
                if dv > 22 and not G.god and P.st ~= "timeup" then
                    P.st = "spin"; P.t = 0; sfx("skid"); sfx("bump"); G.shake = 0.6
                else sfx("bump"); G.shake = max(G.shake, 0.3) end
                P.v = min(P.v, c.v * 0.8)
                P.s = c.s - (hl + CAR_HL) * (ds > 0 and 1 or -1)
                P.x = P.x - (dx > 0 and 0.5 or -0.5)
                c.v = c.v + 3
                return
            end
        end
    end
end

------------------------------------------------------------------ step
local function accel(v, gear)
    if gear == "L" then return 9.5 * max(0, 1 - v / VMAX_L) ^ 0.6 end
    local bog = clamp((v - 8) / 22, 0.22, 1)
    return 8.0 * max(0, 1 - (v / VMAX_H) ^ 2) * bog
end
G.accel = accel
local function car_step(inp, dt)
    P.t = P.t + dt
    if inp.shift and (P.st == "drive" or P.st == "spin") then P.gear = (P.gear == "L") and "H" or "L"; sfx("shift"); P.pop = true end
    local a = seg_at(P.s)
    if P.st == "drive" or P.st == "timeup" then
        local vmax = (P.gear == "L") and VMAX_L or VMAX_H
        local acc = 0
        if inp.gas and P.st == "drive" then acc = accel(P.v, P.gear) else acc = -(1.2 + P.v * 0.025) end
        if inp.brake then acc = -16 end
        -- time up: the driver stands on the brakes and the car pulls up where it is (it used to coast for a minute,
        -- drifting off the road with collisions switched off, so it slid through the scenery)
        if P.st == "timeup" then acc = -(13 + P.v * 0.12) end
        if P.v > vmax then acc = min(acc, -6) end
        local surf = surface(P.s, P.x)
        if surf == "off" then
            if P.v > 120 / 3.6 then acc = min(acc, -14) end
            G.shake = max(G.shake, 0.18 * clamp(P.v / 40, 0, 1))
            if P.v > 3 then G.off_t = (G.off_t or 0) - dt; if G.off_t <= 0 then G.off_t = 0.18; sfx("offroad") end end   -- dust: render_car
        end
        P.v = clamp(P.v + acc * dt, 0, VMAX_H + 2)
        -- steering + centrifugal drift on curves
        local ts = (P.st == "drive") and inp.h or 0
        P.steer = damp(P.steer, ts, 9, dt)
        local vlat = P.steer * min(P.v, 55) * 0.3
        local k = a and math.rad(a.curve) / SEGL or 0
        local drift = k * P.v * P.v * 0.33
        if P.st == "timeup" then drift = drift * 0.5 end
        P.x = P.x + (vlat + drift) * dt
        P.drift, P.brk, P.gas, P.surf = drift, (inp.brake or P.st == "timeup") and P.v > 8, inp.gas and P.st == "drive", surf   -- read by the car FX / body slip
        if abs(drift) > 9 and abs(P.steer) > 0.6 and P.v > 45 then
            G.skid_t = (G.skid_t or 0) - dt
            if G.skid_t <= 0 then G.skid_t = 0.3; sfx("skid") end
            P.skid = true
        else P.skid = false end
        P.s = P.s + P.v * dt
        if P.st == "drive" and P.v > 1 then add_score(floor(P.v * 3.6 * dt * 250 * ((surf == "off") and 0.3 or 1))) end
    else P.drift, P.brk, P.gas = 0, false, false end
    if P.st == "spin" then
        P.v = max(0, P.v - 18 * dt); P.s = P.s + P.v * dt
        if P.t > 1.4 then P.st = "drive" end
    elseif P.st == "crash" then
        local v = P.crash_v * max(0, 1 - P.t / 0.9)
        P.s = P.s + v * dt; P.v = 0
        if P.t > 3.2 then
            P.st = "drive"; P.t = 0; P.v = 0; P.gear = "L"
            local aa = seg_at(P.s)
            P.x = (aa and aa.fork and not aa.st.side) and ((aa.st.pick or ((P.x >= 0) and 1 or -1)) * aa.fork) or 0
        end
    elseif P.st == "goal" then
        P.v = max(0, P.v - 9 * dt); P.s = P.s + P.v * dt; P.steer = damp(P.steer, 0, 4, dt)
        P.x = damp(P.x, 0, 1.5, dt)
    end
    P.x = clamp(P.x, -140, 140)
end
local function stage_step(inp, dt)
    if P.st == "drive" or P.st == "spin" or P.st == "crash" then
        G.time = G.time - dt; G.lap_t = G.lap_t + dt
        if G.time <= 10 and floor(G.time + dt) ~= floor(G.time) and G.time > 0 then sfx("warn") end
        if G.time <= 0 then G.time = 0; P.st = "timeup"; P.t = 0; music(nil); sfx("timeup") end
    end
    car_step(inp, dt)
    traffic_step(dt)
    if P.st == "drive" or (P.st == "timeup" and P.v > 0) then hit_traffic(); hit_objects() end
    progress()
end
G.stage_step = stage_step
local function race_reset()
    if G.clear_scenery then G.clear_scenery() end
    reset_route()
    if G.invalidate_slots then G.invalidate_slots() end
    for i = #CARS, 1, -1 do CARS[i] = nil end
    P.s, P.x, P.v, P.gear, P.steer, P.st, P.t = 12, 0, 0, "L", 0, "drive", 0
    P.slip, P.drift, P.brk, P.gas, P.pop, P.os, P.ox = 0, 0, false, false, false, nil, nil
    if G.hide_debris then G.hide_debris() end
    G.cur_stage = nil; G.fork_lock = nil; G.time = G.EXTEND[1]; G.lap_t = 0; G.laps = {}; G.goal = nil; G.bonus = 0
    progress()
end
G.race_reset = race_reset
------------------------------------------------------------------ road + ground: ring of slots, one per segment in view
local function V(x, y, z) return vec3(x, y, z) end
local NSLOT, AHEAD, BEHIND = 170, 160, 4
local SEGL, HALF, RUMB = G.TC.SEG, G.TC.HALF, G.TC.RUMB
local SLOTS = {}
local SLOT_KINDS = { "ground", "roadA", "roadB", "rumAl", "rumAr", "rumBl", "rumBr" }
local function build_slots()
    for _, k in ipairs(SLOT_KINDS) do
        SLOTS[k] = {}
        for i = 0, NSLOT - 1 do
            local mesh = (k == "ground") and "ground" or ((k == "roadA" or k == "roadB") and "road" or nil)
            if mesh then SLOTS[k][i] = { n = clone(mesh), g = nil }
            else SLOTS[k][i] = { r = clone("rumble_r"), w = clone("rumble_w"), g = nil } end
        end
    end
end
function G.invalidate_slots() for _, k in ipairs(SLOT_KINDS) do for i = 0, NSLOT - 1 do SLOTS[k][i].g = nil end end end
local function place(n, g, off, width, dy)
    local a, b = SG[g], G.seg_end(g)
    local rax, raz = right_of(a.yaw); local rbx, rbz = right_of(b.yaw)
    local x0, z0 = a.x + rax * off, a.z + raz * off
    local x1, z1 = b.x + rbx * off, b.z + rbz * off
    local dx, dy_, dz = x1 - x0, b.y - a.y, z1 - z0
    local len = sqrt(dx * dx + dz * dz)
    n:set_position(V(x0, a.y + (dy or 0), z0))
    n:set_rotation(V(-math.deg(math.atan(dy_ / max(len, 0.01))), math.deg(atan2(dx, dz)), 0))
    n:set_scale(V(width, 1, len + 0.12))
end
local function render_road(gcur)
    for g = max(1, gcur - BEHIND), gcur + AHEAD do
        local a, b = SG[g], SG[g + 1]
        if not a or not b then break end
        local i = g % NSLOT
        local gs = SLOTS.ground[i]
        if gs.g ~= g then
            gs.g = g
            -- z-fighting: every slot is stretched 12 cm past its segment end (closes wedge gaps on curves), so
            -- neighbouring slots overlap; on curves the 420 m ground slabs fan over each other far from the road.
            -- Equal heights there are coplanar and flicker. Give each slot its own millimetre layer instead:
            -- ground cycles 16 levels (pairs that share a level are 80 m apart), road/kerbs alternate per segment,
            -- and fork road B sits a layer above road A where the two overlap.
            place(gs.n, g, 0, 420, -0.06 - (g % 16) * 0.004)
            local offs = { 0 }
            if a.fork and a.fork > 0.01 then offs = { -a.fork, a.fork } end
            local red = (floor(g / 2) % 2 == 0)
            local lay = (g % 2) * 0.004
            local merged = a.fork and a.fork > 0.01 and a.fork < HALF + RUMB   -- roads still overlap: hide the inner kerbs
            for k, nm in ipairs({ "A", "B" }) do
                local rs = SLOTS["road" .. nm][i]
                local rl, rr_ = SLOTS["rum" .. nm .. "l"][i], SLOTS["rum" .. nm .. "r"][i]
                rs.g, rl.g, rr_.g = g, g, g
                local off = offs[k]
                if off then
                    local dy = lay + (k - 1) * 0.009
                    place(rs.n, g, off, HALF * 2, dy)
                    local on, offn = red and "r" or "w", red and "w" or "r"
                    rl[offn]:set_position(HIDE); rr_[offn]:set_position(HIDE)
                    if merged and k == 2 then rl[on]:set_position(HIDE) else place(rl[on], g, off - HALF - RUMB / 2, RUMB, dy) end
                    if merged and k == 1 then rr_[on]:set_position(HIDE) else place(rr_[on], g, off + HALF + RUMB / 2, RUMB, dy) end
                else
                    rs.n:set_position(HIDE); rl.r:set_position(HIDE); rl.w:set_position(HIDE); rr_.r:set_position(HIDE); rr_.w:set_position(HIDE)
                end
            end
        end
    end
end

------------------------------------------------------------------ scenery (assigned from per-mesh free lists while in view)
local OBJ_MESH = { palm = { "palm_trunk", "palm_leaves" }, pine = { "pine_trunk", "pine_leaves" }, pine_s = { "pine_trunk", "pine_snow" },
    bush = { "bush" }, rock = { "rock" }, cliff = { "cliff" }, cactus = { "cactus" }, column = { "column" }, vine = { "vine" }, lamp = { "lamp" },
    fence = { "fence" }, windmill = { "windmill", "blades" }, sign_l = { "sign_post", "sign_board" }, sign_r = { "sign_post", "sign_board_r" },
    start = { "arch", "ban_start", "flagman", "flag" }, check = { "arch", "ban_check" }, goal = { "arch", "ban_goal" } }
local FREE = {}
local function take(m)
    local f = FREE[m]; if f and #f > 0 then return table.remove(f) end
    return clone(m)
end
local function give(m, n) n:set_position(HIDE); FREE[m] = FREE[m] or {}; table.insert(FREE[m], n) end
local ACTIVE = {}
local function obj_meshes(o)
    if o.k == "bld" then return { "bld_" .. o.v, "roof" } end
    return OBJ_MESH[o.k] or { "rock" }
end
local function show_obj(o)
    local ms = obj_meshes(o)
    local a = SG[o.g]
    if not a then return end
    local rx, rz = right_of(a.yaw)
    local x, z = a.x + rx * o.x, a.z + rz * o.x
    o.nodes = {}
    local natural = not (o.arch or o.k == "sign_l" or o.k == "sign_r" or o.k == "lamp" or o.k == "fence" or o.k == "bld" or o.k == "vine")
    local yaw = a.yaw + (natural and o.ry or 0) + ((o.arch or o.k == "sign_l" or o.k == "sign_r") and 180 or 0)
    if o.k == "lamp" and o.x < 0 then yaw = yaw + 180 end
    for i, m in ipairs(ms) do
        local n = take(m); o.nodes[i] = { m = m, n = n }
        local px, pz = x, z
        if m == "flagman" or m == "flag" then local fx, fz = right_of(a.yaw); px, pz = x + fx * -11, z + fz * -11 end
        local s = 1
        if natural then s = 0.85 + 0.3 * ((o.v or 0) / 2) end
        if m == "roof" then s = ({ 0.85, 1.2, 0.7 })[(o.v or 0) + 1] end
        local py = a.y - 0.05
        if m == "roof" then py = py + ({ 14, 22, 9 })[(o.v or 0) + 1] - 9 end
        if m == "blades" then py = py + 8.6; o.blade = n end
        n:set_position(V(px, py, pz)); n:set_rotation(V(0, yaw, 0)); n:set_scale(V(s, s, s))
    end
    o.yaw = yaw
end
local function hide_obj(o) for _, e in ipairs(o.nodes or {}) do give(e.m, e.n) end; o.nodes = nil; o.blade = nil end
local function render_scenery(gcur)
    local seen = {}
    local lo, hi = gcur - BEHIND, gcur + AHEAD
    for si = max(1, #STAGES - 1), #STAGES do
        local st = STAGES[si]
        for _, o in ipairs(st.objs) do
            if o.g > hi then break end
            if o.g >= lo then
                seen[o] = true
                if not ACTIVE[o] then ACTIVE[o] = true; show_obj(o) end
                if o.blade then o.blade:set_rotation(V(0, o.yaw, G.t * 60)) end
            end
        end
    end
    for o in pairs(ACTIVE) do if not seen[o] then hide_obj(o); ACTIVE[o] = nil end end
end
function G.clear_scenery() for o in pairs(ACTIVE) do hide_obj(o); ACTIVE[o] = nil end end

------------------------------------------------------------------ the Testarossa rig
local function grp(parent, pos, meshes)
    local g = empty("grp", parent, pos)
    for _, m in ipairs(meshes) do clone(m, V(0, 0, 0), nil, g) end
    return g
end
local R = {}
local function build_car()
    R.root = empty("Car", nil, HIDE)
    R.body = grp(R.root, V(0, 0, 0), { "car_body", "car_under", "car_strake", "car_grille", "car_tail", "car_head", "car_glass", "car_frame",
        "car_seat", "car_cabin", "car_wheelin", "car_mirror", "drv_skin", "drv_hair", "pas_hair", "drv_shirt" })
    R.wheels = {}
    for _, w in ipairs({ { 0.86, 1.42, true }, { -0.86, 1.42, true }, { 0.88, -1.38 }, { -0.88, -1.38 } }) do
        local hub = empty("hub", R.root, V(w[1], 0.34, w[2]))
        local spin = grp(hub, V(0, 0, 0), { "car_tire", "car_rim" })
        R.wheels[#R.wheels + 1] = { hub = hub, spin = spin, front = w[3] }
    end
    R.shadow = clone("car_shadow")
    R.wrot = 0
end
local AL = 1
local function car_pose(dt)
    local s = lerp(P.os or P.s, P.s, AL)
    local x = lerp(P.ox or P.x, P.x, AL)
    local p, yaw = world_at(s, x, 0)
    local a = seg_at(s)
    local pitch = 0
    if a then pitch = -math.deg(math.atan(a.dy / SEGL)) end
    return p, yaw, pitch, s, x
end
G.car_pose = car_pose
-- ground FX colours per theme ground texture: { dust cloud, thrown grit }
local GROUND_FX = {
    grass = { { .34, .36, .22 }, { .3, .55, .16 } }, vine = { { .36, .34, .22 }, { .32, .5, .16 } }, lake = { { .32, .36, .24 }, { .3, .52, .2 } },
    dark = { { .3, .32, .24 }, { .24, .42, .16 } }, wheat = { { .62, .54, .32 }, { .8, .68, .3 } }, beach = { { .7, .64, .5 }, { .9, .82, .62 } },
    desert = { { .7, .58, .4 }, { .85, .7, .45 } }, dry = { { .6, .52, .38 }, { .7, .6, .42 } }, canyon = { { .62, .42, .3 }, { .72, .45, .3 } },
    alps = { { .75, .78, .82 }, { .95, .97, 1 } }, town = { { .45, .44, .42 }, { .55, .54, .5 } },
}
-- car-local point -> world (engine yaw: +Z forward rotates toward +X for positive degrees)
local function car_pt(p, ry, lx, ly, lz)
    local r = math.rad(ry); local c, s = cos(r), sin(r)
    return p.x + lx * c + lz * s, p.y + ly, p.z - lx * s + lz * c
end
local FXS = { tire = 0, dirt = 0, exh = 0, wreck = 0 }
local DEB = {}
function G.crash_fx(p, yaw, v)
    local r = math.rad(yaw); local fx, fz = sin(r), cos(r)
    local cv = { fx * v * 0.35, 1.5, fz * v * 0.35 }
    FX.flash(p.x, p.y, p.z, 3, { 0.8, 0.65, 0.5 })
    FX.sparks(p.x, p.y - 0.3, p.z, 40, cv, 16)
    FX.ring(p.x, p.y - 0.55, p.z, 6, { 0.5, 0.48, 0.45 }, true)
    FX.smoke(p.x, p.y, p.z, 1.5, cv, 0.24, 1.8)
    FX.dust(p.x, p.y - 0.4, p.z, { .3, .29, .27 }, 1.5, cv, 2)
    FX.emit("soft", p.x, p.y, p.z, { n = 14, vel = cv, c0 = { 1.2, 1.15, 1.0 }, c1 = { 0.2, 0.2, 0.25 }, s0 = 0.04, s1 = 0.1, l0 = 0.5, l1 = 1.0, r = 0.6, sp = 8, drag = 0.6, grav = { 0, -12, 0 } })  -- glass
    -- body-panel and trim shards: real meshes so they can be dark, tumbling with gravity and a bounce
    for i = 1, 12 do
        local d = DEB[i]
        if not d then d = { n = clone((i % 3 == 0) and "deb_dark" or "deb_red") }; DEB[i] = d end
        local a = rand() * 2 * PI
        d.x, d.y, d.z, d.floor = p.x, p.y, p.z, p.y - 0.6
        d.vx, d.vy, d.vz = fx * v * (0.25 + rand() * 0.35) + cos(a) * (3 + rand() * 6), 4 + rand() * 7, fz * v * (0.25 + rand() * 0.35) + sin(a) * (3 + rand() * 6)
        d.rx, d.ry, d.rz = rand() * 360, rand() * 360, rand() * 360
        d.wx, d.wy, d.wz = (rand() - 0.5) * 1400, (rand() - 0.5) * 1400, (rand() - 0.5) * 1400
        d.t = 0; d.life = 2.4 + rand() * 0.8
        local s = 0.7 + rand() * 0.8; d.n:set_scale(V(s, s, s))
    end
    FXS.wreck = 2.8
end
local function update_debris(dt)
    for _, d in ipairs(DEB) do
        if d.t and d.t < d.life then
            d.t = d.t + dt
            d.vy = d.vy - 18 * dt
            local k = math.exp(-0.6 * dt); d.vx, d.vz = d.vx * k, d.vz * k
            d.x, d.y, d.z = d.x + d.vx * dt, d.y + d.vy * dt, d.z + d.vz * dt
            if d.y < d.floor then
                d.y = d.floor; d.vy = -d.vy * 0.35; d.vx, d.vz = d.vx * 0.6, d.vz * 0.6; d.wx, d.wy, d.wz = d.wx * 0.5, d.wy * 0.5, d.wz * 0.5
                if abs(d.vy) > 2 then FX.emit("dust", d.x, d.y, d.z, { n = 1, c0 = { .3, .3, .28 }, s0 = .3, s1 = .5, l0 = .3, l1 = .6, r = .1, sp = 1 }) end
            end
            d.rx, d.ry, d.rz = d.rx + d.wx * dt, d.ry + d.wy * dt, d.rz + d.wz * dt
            d.n:set_position(V(d.x, d.y, d.z)); d.n:set_rotation(V(d.rx, d.ry, d.rz))
            if d.t >= d.life then d.n:set_position(HIDE) end
        end
    end
end
function G.hide_debris() for _, d in ipairs(DEB) do d.t = nil; d.n:set_position(HIDE) end; FXS.wreck = 0 end
local function car_fx(dt, p, ry)
    local v = P.v
    local r = math.rad(ry); local fx, fz = sin(r), cos(r)
    local drive = P.st == "drive" or P.st == "timeup" or P.st == "spin"
    local onroad = P.surf ~= "off"
    -- tyre smoke from both rear contact patches: power slides, hard cornering, heavy braking, spins
    local tk = 0
    if drive and v > 12 and onroad then
        if P.skid or P.st == "spin" then tk = 1
        elseif abs(P.slip or 0) > 8 then tk = 0.75
        elseif P.brk and v > 25 then tk = 0.6
        elseif abs(P.steer) > 0.85 and v > 55 then tk = 0.35 end
    end
    FXS.tire = FXS.tire - dt
    if tk > 0 and FXS.tire <= 0 then
        FXS.tire = 0.045
        local cv = { fx * v * 0.78, 0.8, fz * v * 0.78 }   -- dragged along behind the car, then left hanging
        for _, side in ipairs({ 0.95, -0.95 }) do
            local x, y, z = car_pt(p, ry, side, 0.25, -1.6)
            FX.smoke(x, y, z, tk * 1.15, cv, 0.42, 1.35)
        end
    end
    -- off-road: theme-coloured dust cloud + thrown clods/clippings/snow from the rear wheels
    FXS.dirt = FXS.dirt - dt
    if drive and not onroad and v > 4 and FXS.dirt <= 0 then
        FXS.dirt = 0.05
        local a = seg_at(P.s); local gk = a and a.st and a.st.th and a.st.th.ground or "grass"
        local gc = GROUND_FX[gk] or GROUND_FX.grass
        local k = clamp(v / 50, 0.3, 1.2)
        local cv = { fx * v * 0.4, 1.2, fz * v * 0.4 }
        for _, side in ipairs({ 0.9, -0.9 }) do
            local x, y, z = car_pt(p, ry, side, 0.2, -1.5)
            FX.dust(x, y, z, gc[1], k, cv, 1.0 + 0.5 * k)
            FX.grit(x, y, z, gc[2], 3, { fx * v * 0.3, 3.5, fz * v * 0.3 })
        end
    end
    -- exhaust: twin tailpipes, visible puffs under throttle at low speed, a pop + flame on every gear change
    FXS.exh = FXS.exh - dt
    if drive and FXS.exh <= 0 then
        FXS.exh = (P.gas and v < 30) and 0.06 or 0.12
        local k = (P.gas and 1 or 0.35) * clamp(1.2 - v / 80, 0.25, 1)
        for _, side in ipairs({ 0.55, -0.55 }) do
            local x, y, z = car_pt(p, ry, side, 0.36, -2.35)
            FX.emit("smoke", x, y, z, { n = 1, vel = { fx * v * 0.8 - fx * 2, 0.4, fz * v * 0.8 - fz * 2 }, c0 = { .2 * k, .2 * k, .21 * k }, c1 = { 0, 0, 0 },
                s0 = .18, s1 = .35, l0 = .35, l1 = .7, r = .03, sp = .6, drag = 3, grav = { 0, .6, 0 } })
        end
    end
    if P.pop then
        P.pop = false
        for _, side in ipairs({ 0.55, -0.55 }) do
            local x, y, z = car_pt(p, ry, side, 0.36, -2.4)
            local cv = { fx * v * 0.9 - fx * 6, 0.2, fz * v * 0.9 - fz * 6 }
            FX.emit("fire", x, y, z, { n = 3, vel = cv, c0 = { 1.8, 1.0, .4 }, c1 = { .2, .03, 0 }, s0 = .25, s1 = .45, l0 = .08, l1 = .16, r = .02, sp = 1, drag = 4 })
            FX.emit("smoke", x, y, z, { n = 2, vel = cv, c0 = { .3, .3, .3 }, c1 = { 0, 0, 0 }, s0 = .3, s1 = .5, l0 = .4, l1 = .8, r = .05, sp = 1, drag = 3, grav = { 0, .7, 0 } })
        end
    end
    -- wreck: smoke pouring off the tumbling car, plus a few licks of flame early on
    if FXS.wreck > 0 then
        FXS.wreck = FXS.wreck - dt
        FXS.wk = (FXS.wk or 0) - dt
        if FXS.wk <= 0 then
            FXS.wk = 0.09
            local k = clamp(FXS.wreck / 2.8, 0.2, 1)   -- screen-blended puffs add up: keep each one dim
            FX.smoke(p.x, p.y + 0.8, p.z, 0.6 * k, { 0, 1.4, 0 }, 0.2, 1.6)
            if FXS.wreck > 2.0 and rand() < 0.35 then FX.fire(p.x, p.y + 0.6, p.z, 0.4, 0.5) end
        end
    end
    update_debris(dt)
end
local function render_car(dt)
    local p, yaw, pitch = car_pose(dt)
    -- body slip: in a power slide the nose points INTO the bend and the tail swings OUT (centrifugal side).
    -- Engine yaw is positive toward +X = screen left, while steer > 0 moves the car right (right_of = -X), so
    -- the steering yaw must be subtracted (it used to be added, which pointed the nose out and the tail in).
    local tgt = 0
    if (P.st == "drive" or P.st == "timeup") and P.v > 30 and abs(P.drift or 0) > 5 and P.steer * (P.drift or 0) < 0 then
        tgt = (P.drift > 0 and 1 or -1) * clamp((abs(P.drift) - 5) * 1.4, 0, 20) * clamp(abs(P.steer) * 1.3, 0, 1)
    end
    P.slip = clamp(damp(P.slip or 0, tgt, (tgt ~= 0) and 3.5 or 6, dt), -25, 25)
    if abs(P.slip) < 1e-3 then P.slip = 0 end   -- never decay into denormals
    local roll = -P.steer * 2.5 * clamp(P.v / 60, 0, 1) - (P.slip or 0) * 0.12
    local ry, rx, rz, lift = yaw - P.steer * 6 + P.slip, pitch, roll, 0
    if P.st == "spin" then ry = ry + P.t / 1.4 * 720 end
    if P.st == "crash" then
        local t = clamp(P.t / 1.6, 0, 1)
        lift = math.sin(PI * t) * 3.2
        rz = rz + t * 540; rx = rx + t * 180
        if P.t > 1.6 then rz, rx, lift = 0, pitch, 0 end
    end
    R.root:set_position(V(p.x, p.y + lift, p.z)); R.root:set_rotation(V(rx, ry, rz))
    R.wrot = R.wrot + P.v * dt / 0.34 * 57.3
    for _, w in ipairs(R.wheels) do
        -- front wheels follow the steering (same sign fix) and counter-steer against the slide
        w.hub:set_rotation(V(0, w.front and (-P.steer * 22 - P.slip * 0.7) or 0, 0))
        w.spin:set_rotation(V(R.wrot, 0, 0))
    end
    R.shadow:set_position(V(p.x, p.y + 0.03, p.z)); R.shadow:set_rotation(V(pitch, yaw, 0))
    car_fx(dt, V(p.x, p.y + lift, p.z), (P.st == "crash") and yaw or ry)
    return p, yaw
end

------------------------------------------------------------------ traffic
local TMESH = { beetle = { "tr_beetle", "tr_glass", "tr_lamp" }, vette = { "tr_vette", "tr_glass", "tr_lamp" }, truck = { "tr_cab", "tr_box", "tr_wind", "tr_lamp" } }
local DYN = { "tr_beetle", "tr_vette", "tr_cab", "tr_box", "tr_glass", "tr_wind", "tr_lamp", "car_tire" }
local function render_traffic(dt)
    for _, k in ipairs(DYN) do P_begin(k) end
    for _, c in ipairs(CARS) do
        local s = lerp(c.os or c.s, c.s, AL)
        local p, yaw = world_at(s, car_x(c), 0)
        for _, m in ipairs(TMESH[c.k]) do local n = P_get(m); n:set_position(p); n:set_rotation(V(0, yaw, 0)); n:set_scale(V(1, 1, 1)) end
        c.wr = (c.wr or 0) + c.v * dt / 0.34 * 57.3
        local rx, rz = right_of(yaw); local fx, fz = math.sin(math.rad(yaw)), math.cos(math.rad(yaw))
        local L = (c.k == "truck") and 2.6 or 1.3
        for _, w in ipairs({ { 0.8, L }, { -0.8, L }, { 0.8, -L }, { -0.8, -L } }) do
            local n = P_get("car_tire")
            n:set_position(V(p.x + rx * w[1] + fx * w[2], p.y + 0.34, p.z + rz * w[1] + fz * w[2])); n:set_rotation(V(c.wr, yaw, 0)); n:set_scale(V(1, 1, 1))
        end
    end
    for _, k in ipairs(DYN) do P_end(k) end
    for _, c in ipairs(CARS) do c.os = c.s end
end

------------------------------------------------------------------ camera, horizon and the far plane
G.shake = 0
local CAMV = { y = 3 }
local function update_camera(dt, carp, yaw)
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.35 * SET:shake_scale()
    if G.cam_ov then
        local o = G.cam_ov; G.cam.pos = V(o[1], o[2], o[3]); G.cam.look = V(o[4], o[5], o[6])
    else
        local fx, fz = math.sin(math.rad(yaw)), math.cos(math.rad(yaw))
        local s = lerp(P.os or P.s, P.s, AL)
        local _, ry = frame(max(0, s - 7.5))
        CAMV.y = damp(CAMV.y, ry + 2.75, 8, dt)
        local cx, cz = carp.x - fx * 7.6, carp.z - fz * 7.6
        G.cam.pos = V(cx + a * sin(G.t * 53), CAMV.y + a * cos(G.t * 61), cz)
        local _, ly = frame(s + 14)
        G.cam.look = V(carp.x + fx * 12, max(ly, carp.y) + 1.1, carp.z + fz * 12)
    end
    cam:set_position(G.cam.pos); cam:look_at(G.cam.look)
    if G.trace and #G.trace < 4000 then local cp = G.cam.pos; G.trace[#G.trace + 1] = { G.t, cp.x, cp.z, P.s, P.x, AL } end   -- MCP test hook
    local c = G.cam.pos
    G.hz:set_position(V(c.x, c.y - 70, c.z))
    -- far plane (fills the view beyond the ground slabs): it used to sit 1.2 m under the road at the CAR, so any road
    -- ahead that dropped more than ~0.7 m below the car (every downhill, a crest with a dip behind it) went under its
    -- top face and was painted over by a flat green band. Keep it under the lowest road in view instead.
    if G.farplane then
        local g0 = floor(lerp(P.os or P.s, P.s, AL) / SEGL) + 1
        local lo = math.huge
        for g = max(1, g0 - BEHIND), g0 + AHEAD do local sg = SG[g]; if not sg then break end; if sg.y < lo then lo = sg.y end end
        if lo == math.huge then lo = c.y - 3 end
        G.far_y = (G.far_y and G.far_y < lo - 1.6) and damp(G.far_y, lo - 2.0, 1.5, dt) or (lo - 2.0)   -- drop at once, rise slowly
        G.farplane:set_position(V(c.x, G.far_y, c.z))
    end
end
local function build_world()
    build_slots()
    G.hz = clone("horizon", V(0, 0, 0), V(2600, 1400, 2600))
    G.farplane = prim("cube", V(0, -2, 0), V(9000, 1, 9000)); paint(G.farplane, { .3, .5, .22 }, { 0, 0, 0 }, 1, 0)
end

------------------------------------------------------------------ collider debug overlay (F3)
G.DBG = { on = false, pool = {}, used = 0, w = 0.14 }
local DC = { edge = { .2, .9, 1 }, car = { .2, 1, .3 }, traffic = { 1, .25, .2 }, obj = { 1, .8, .2 } }
function G.dbg_bar(p0, p1, col)
    local D = G.DBG
    D.used = D.used + 1
    local b = D.pool[D.used]
    if not b then
        if #D.pool >= 1500 then return end
        b = { n = prim("cube", HIDE, V(1, 1, 1)), col = nil }
        D.pool[D.used] = b
    end
    if b.col ~= col then b.col = col; paint(b.n, { col[1] * .3, col[2] * .3, col[3] * .3 }, { col[1] * 1.4, col[2] * 1.4, col[3] * 1.4 }, 0.5, 0) end
    local dx, dy, dz = p1.x - p0.x, p1.y - p0.y, p1.z - p0.z
    local len = sqrt(dx * dx + dy * dy + dz * dz)
    b.n:set_position(V((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, (p0.z + p1.z) / 2))
    b.n:set_rotation(V(-math.deg(math.atan(dy / max(sqrt(dx * dx + dz * dz), 0.001))), math.deg(atan2(dx, dz)), 0))
    b.n:set_scale(V(D.w, D.w, len + D.w))
end
local function dbox(s, x, hw, hl, col, raw)
    local h = 0.4
    local a, b, c, d = world_at(s - hl, x - hw, h, raw), world_at(s - hl, x + hw, h, raw), world_at(s + hl, x + hw, h, raw), world_at(s + hl, x - hw, h, raw)
    G.dbg_bar(a, b, col); G.dbg_bar(b, c, col); G.dbg_bar(c, d, col); G.dbg_bar(d, a, col)
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and SG[1] then
        local s0 = P.s
        for k = -2, 30 do
            local s = s0 + k * 4
            local a = seg_at(s)
            local offs = { 0 }
            if a and a.fork then offs = a.st.side and { 0, -2 * a.st.side * a.fork } or { -a.fork, a.fork } end
            for _, o in ipairs(offs) do
                for _, e in ipairs({ -HALF - RUMB, HALF + RUMB }) do G.dbg_bar(world_at(s, o + e, 0.3), world_at(s + 4, o + e, 0.3), DC.edge) end
            end
        end
        dbox(P.s, P.x, G.CONST.CAR_HW, G.CONST.CAR_HL, DC.car)
        for _, c in ipairs(CARS) do
            if abs(c.s - P.s) < 160 then dbox(c.s, car_x(c), (c.k == "truck") and 1.2 or 0.9, (c.k == "truck") and 3.4 or 2.1, DC.traffic) end
        end
        local g = floor(P.s / SEGL) + 1
        for si = max(1, #STAGES - 1), #STAGES do
            for _, o in ipairs(STAGES[si].objs) do
                if o.g > g + 30 then break end
                if o.g >= g - 2 then
                    local s = (o.g - 1) * SEGL
                    if o.arch then for _, px in ipairs({ -12.5, 12.5 }) do dbox(s, px, 0.7, 1.0, DC.obj, true) end
                    else dbox(s, o.x, OBJ_HW[o.k] or 1, 1.0, DC.obj, true) end
                end
            end
        end
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
        border = border or { 1, 0.55, 0.3, 0.55 }, corner_radius = 12 * US, no_input = true, visible = vis ~= false })
end
local function button(id, label, cx, cy, vis)
    local w, h = 340 * US, 60 * US
    local st = vis and select(2, pcall(runtime_ui.get_state, UI, id))
    local hov = type(st) == "table" and st.hovered
    quad(id, { x = cx - w / 2, y = cy - h / 2, w = w, h = h, z = 12, style = "text", label = label,
        fill = hov and { 0.55, 0.12, 0.08, 0.92 } or { 0.08, 0.05, 0.05, 0.85 }, border = hov and { 1, 0.75, 0.5, 1 } or { 1, 0.5, 0.3, 0.9 },
        text_color = { 0.95, 0.95, 0.92, 1 }, font_scale = 1.25 * US, align_h = "center", align_v = "middle",
        corner_radius = 12 * US, visible = vis })
    return vis and type(st) == "table" and st.clicked
end
local function pad6(n) local s = tostring(floor(n)); return string.rep("0", max(0, 6 - #s)) .. s end
local RED, WHITE, CYAN, DIM, GOLD = { 1, .35, .3, 1 }, { 1, 1, 1, 1 }, { .5, .85, 1, 1 }, { .85, .82, .78, 1 }, { 1, .85, .35, 1 }
local RADIO = { { "radio1", "Sunset Drive" }, { "radio2", "Coastal Breeze" }, { "radio3", "Summer Wave" } }
G.radio = 1
G.banner = { text = "", t = 0 }
local function fmt_t(t) local m = floor(t / 60); return string.format("%d'%05.2f\"", m, t - m * 60) end
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause" or st == "count" or st == "goal") and not G.set_open
    local cur = G.cur_stage
    -- top: score, time, lap
    text("hsl", "SCORE", 40 * US, 18 * US, 300 * US, 34 * US, 1.0, GOLD, "left", play)
    text("hsv", tostring(G.score), 40 * US, 50 * US, 420 * US, 56 * US, 1.9, WHITE, "left", play)
    local tl = math.ceil(G.time or 0)
    local tcol = (G.time or 99) <= 10 and (floor(G.t * 4) % 2 == 0 and RED or WHITE) or GOLD
    text("htl", "TIME", SW / 2 - 150 * US, 12 * US, 300 * US, 34 * US, 1.0, RED, "center", play)
    text("htv", tostring(max(0, tl)), SW / 2 - 150 * US, 40 * US, 300 * US, 90 * US, 3.4, tcol, "center", play)
    text("hll", "LAP", SW - 460 * US, 18 * US, 420 * US, 34 * US, 1.0, GOLD, "right", play)
    text("hlv", fmt_t(G.lap_t or 0), SW - 460 * US, 50 * US, 420 * US, 56 * US, 1.6, WHITE, "right", play)
    text("hstg", cur and string.format("Stage %d  ·  %s", cur.row, cur.name) or "", SW / 2 - 400 * US, 128 * US, 800 * US, 40 * US, 1.15, CYAN, "center", play)
    -- speed + gear
    local kmh = floor(P.v * 3.6 + 0.5)
    panel("hsp", SW - 380 * US, SH - 170 * US, 350 * US, 140 * US, play, 0.5)
    text("hkv", tostring(kmh), SW - 370 * US, SH - 165 * US, 220 * US, 90 * US, 3.0, WHITE, "right", play)
    text("hku", "km/h", SW - 145 * US, SH - 140 * US, 100 * US, 40 * US, 1.0, DIM, "left", play)
    text("hgr", P.gear == "L" and "LOW" or "HIGH", SW - 370 * US, SH - 82 * US, 330 * US, 44 * US, 1.3, P.gear == "L" and CYAN or GOLD, "center", play)
    local rpm = clamp(P.v / ((P.gear == "L") and G.CONST.VMAX_L or G.CONST.VMAX_H), 0, 1)
    for i = 1, 12 do
        quad("tach" .. i, { x = SW - 370 * US + (i - 1) * 27 * US, y = SH - 36 * US, w = 22 * US, h = 14 * US, z = 7, style = "text", label = "",
            fill = (i / 12 <= rpm) and (i > 9 and { 1, .3, .2, 1 } or { 1, .8, .3, 1 }) or { .2, .2, .2, .6 }, border = NONE, corner_radius = 3 * US, no_input = true, visible = play })
    end
    -- course map: 5 rows, the path so far highlighted
    local mx, my = 40 * US, SH - 200 * US
    panel("map", mx - 10 * US, my - 10 * US, 300 * US, 190 * US, play, 0.45)
    local path = {}
    for _, s2 in ipairs(G.STAGES) do path[s2.row] = s2.col end
    for r = 1, 5 do
        for c = 1, r do
            local on = path[r] == c
            local here = cur and cur.row == r and cur.col == c
            local px = mx + 140 * US + (c - (r + 1) / 2) * 54 * US
            quad("mp" .. r .. c, { x = px - 11 * US, y = my + (r - 1) * 34 * US, w = 22 * US, h = 22 * US, z = 7, style = "text", label = "",
                fill = here and (floor(G.t * 4) % 2 == 0 and { 1, .9, .3, 1 } or { 1, .4, .2, 1 }) or (on and { 1, .55, .25, 1 } or { .35, .35, .4, .8 }),
                border = { 1, 1, 1, .6 }, corner_radius = 11 * US, no_input = true, visible = play })
        end
    end
    text("mpg", "Goal " .. table.concat(G.GOALS, " "), mx, my + 166 * US, 280 * US, 30 * US, 0.8, DIM, "center", false)
    -- fork hint
    local a = G.seg_at(P.s)
    local fk = st == "play" and a and a.st.g1 and not a.st.side and a.st.row < 5 and floor(P.s / G.TC.SEG) + 1 >= a.st.g1 - 30 and not G.set_open
    local L = fk and G.ROUTE[a.st.row + 1][a.st.col][1] or ""
    local Rn = fk and G.ROUTE[a.st.row + 1][a.st.col + 1][1] or ""
    -- the tentative pick is gold and larger, the other branch dims; once locked, the chosen road is announced
    local pk = fk and a.st.pick
    local DIMW = { .75, .75, .78, .55 }
    text("fkl", "<  " .. L, SW / 2 - 620 * US, SH * 0.3, 560 * US, 50 * US, pk == -1 and 1.8 or 1.5, pk == -1 and GOLD or (pk and DIMW or WHITE), "right", fk)
    text("fkr", Rn .. "  >", SW / 2 + 60 * US, SH * 0.3, 560 * US, 50 * US, pk == 1 and 1.8 or 1.5, pk == 1 and GOLD or (pk and DIMW or WHITE), "left", fk)
    local lk = G.fork_lock
    if lk then lk.t = lk.t - dt; if lk.t <= 0 then G.fork_lock = nil; lk = nil end end
    local lka = lk and floor(clamp(lk.t / 0.4, 0, 1) * 20) / 20 or 0
    text("fklk", lk and ((lk.side < 0) and ("<  " .. lk.name) or (lk.name .. "  >")) or "", 0, SH * 0.3, SW, 50 * US, 1.8, { GOLD[1], GOLD[2], GOLD[3], lka }, "center", st == "play" and lk ~= nil and not G.set_open)
    G.banner.t = (G.banner.t or 0) - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    text("ban", G.banner.text or "", 0, SH * 0.22, SW, 90 * US, 3.0, { 1, .85, .35, ba }, "center", st == "play" and not G.set_open and G.banner.t > 0)
    -- countdown
    local cd = st == "count" and not G.set_open
    local n = 3 - floor(G.count_t or 0)
    text("cd", n > 0 and tostring(n) or "GO!", 0, SH * 0.34, SW, 160 * US, 6.0, n > 0 and WHITE or GOLD, "center", cd)
    text("cdr", "Radio: " .. RADIO[G.radio][2], 0, SH * 0.34 + 160 * US, SW, 40 * US, 1.2, DIM, "center", cd)
    -- goal / time up
    local gl = st == "goal" and not G.set_open
    panel("g_bg", SW / 2 - 420 * US, SH * 0.22, 840 * US, SH * 0.5, gl, 0.72)
    text("g_t", "Goal " .. tostring(G.goal or ""), 0, SH * 0.24, SW, 100 * US, 3.2, GOLD, "center", gl)
    local lt = {}
    for i, t in ipairs(G.laps or {}) do lt[#lt + 1] = string.format("Stage %d  %s", i, fmt_t(t)) end
    text("g_l", table.concat(lt, "   "), SW / 2 - 400 * US, SH * 0.24 + 110 * US, 800 * US, 40 * US, 0.9, DIM, "center", gl)
    text("g_b", "Time Bonus  " .. tostring(G.bonus or 0), 0, SH * 0.24 + 160 * US, SW, 50 * US, 1.5, WHITE, "center", gl)
    text("g_s", "Score  " .. tostring(G.score), 0, SH * 0.24 + 215 * US, SW, 50 * US, 1.5, WHITE, "center", gl)
    -- title
    local title = st == "title" and not G.set_open
    local TX, TW = SW * 0.53, SW * 0.44
    panel("t_bg", TX, SH * 0.05, TW, SH * 0.9, title, 0.6)
    text("t_title", "Out Run Remix", TX, SH * 0.07, TW, 120 * US, 3.8, { 1, .45, .25, 1 }, "center", title)
    text("t_sub", "Pick a road at every fork and reach a goal", TX, SH * 0.07 + 108 * US, TW, 36 * US, 1.0, DIM, "center", title)
    text("t_sub2", "before the time runs out", TX, SH * 0.07 + 140 * US, TW, 36 * US, 1.0, DIM, "center", title)
    local CL = { "W / Up: accelerate   ·   S / Down: brake", "A / D or Left / Right: steer", "Space / Shift / Right Click: gear (Low / High)",
        "Left / Right on this screen: radio", "P / Esc: pause  ·  O: settings  ·  M: mute  ·  F3: colliders" }
    for i, l in ipairs(CL) do text("t_ctl" .. i, l, TX, SH * 0.64 + (i - 1) * 32 * US, TW, 32 * US, 0.9, DIM, "center", title) end
    text("t_hi", "High score " .. tostring(G.hiscore), TX, SH * 0.64 + 172 * US, TW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, GOLD, "center", pause)
    local over = st == "over" and not G.set_open
    panel("o_bg", SW / 2 - 380 * US, SH * 0.24, 760 * US, SH * 0.52, over, 0.78)
    text("o_t", G.won and ("Goal " .. tostring(G.goal)) or "Game Over", 0, SH * 0.26, SW, 90 * US, 3.0, G.won and GOLD or RED, "center", over)
    text("o_s", "Score " .. tostring(G.score) .. (cur and ("  ·  " .. cur.name) or ""), 0, SH * 0.26 + 90 * US, SW, 40 * US, 1.3, DIM, "center", over)
    local c = {}
    local yb = SH * 0.36
    c.start = button("b_start", "Start (Enter)", SW * 0.75, yb, title); yb = yb + 76 * US
    c.radio = button("b_radio", "Radio: " .. RADIO[G.radio][2], SW * 0.75, yb, title); yb = yb + 76 * US
    c.set_t = button("b_set_t", "Settings (O)", SW * 0.75, yb, title); yb = yb + 76 * US
    c.quit_app = button("b_quit_app", "Quit Game", SW * 0.75, yb, title)
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
    G.race_reset()
    music("title")
end
G.to_title = to_title
local function new_game()
    G.score = 0
    G.race_reset()
    G.state = "count"; G.count_t = 0; G.beeped = -1
    music(RADIO[G.radio][1])
end
G.new_game = new_game
local function game_over(won)
    G.state = "over"; G.over_t = 0; G.won = won
    if not won then music(nil) end
    if G.score > G.hiscore then G.hiscore = G.score; save_hi() end
end
local acc = 0
G.shift_q = false
local rmouse_prev = true
local function update(dt)
    flush_mats()
    dt = clamp(dt, 0, 0.1)   -- a negative frame time (timer hitch) would make every damp() explode
    G.t = G.t + dt; G.dt = dt
    local k = { ret = edge("Return"), space = edge("Space"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), q = edge("Q"),
        sh = edge("LeftShift"), sh2 = edge("RightShift"), left = edge("Left"), right = edge("Right"), f3 = edge("F3") }
    local rd = false
    pcall(function() rd = input.is_right_mouse_down and input.is_right_mouse_down() and true or false end)
    local rclick = rd and not rmouse_prev; rmouse_prev = rd
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end; rclick = false end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        if k.ret or k.space or c.start then sfx("click"); new_game()
        elseif c.radio or k.right then sfx("click"); G.radio = G.radio % #RADIO + 1; music(RADIO[G.radio][1])
        elseif k.left then sfx("click"); G.radio = (G.radio - 2) % #RADIO + 1; music(RADIO[G.radio][1])
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "count" then
        G.count_t = G.count_t + dt
        local n = floor(G.count_t)
        if n ~= G.beeped then G.beeped = n; if n < 3 then sfx("beep") elseif n == 3 then sfx("go") end end
        if G.count_t >= 3 then G.state = "play"; G.shift_q = false end
        if k.esc then to_title() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click") end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.q or c.quit then to_title() end
    elseif st == "goal" then
        G.goal_t = G.goal_t + dt
        if G.goal_t > 1.5 and not G.bonus_given then G.bonus_given = true; add_score(G.bonus) end
        if G.goal_t > 6 or ((k.ret or k.space) and G.goal_t > 2) then game_over(true) end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then sfx("click"); new_game()
            elseif k.esc or c.title then to_title() end
        end
    end
    st = G.state
    local running = (st == "play" or st == "goal" or st == "count" or st == "title") and not (G.set_open and st ~= "title")
    if running then
        if (k.space or k.sh or k.sh2 or rclick) and st == "play" then G.shift_q = true end
        local inp = { h = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0), gas = any("Up", "W"), brake = any("Down", "S"), shift = false }
        if st ~= "play" then inp.h, inp.gas, inp.brake = 0, false, false end
        if G.autoplay and st == "play" then
            inp.gas = true; local a = G.seg_at(P.s); local tx = (a and a.fork and not a.st.side) and (G.auto_side or 1) * a.fork or 0
            inp.h = clamp((tx - P.x) * 0.3 - (a and a.curve or 0) * 0.5, -1, 1)
            if P.gear == "L" and P.v > 45 then G.shift_q = true end
        end
        if G.test_inp and st == "play" then for kk, vv in pairs(G.test_inp) do inp[kk] = vv end end   -- MCP test hook
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 6 do
            inp.shift = G.shift_q; G.shift_q = false
            P.os, P.ox = P.s, P.x
            if st == "play" or st == "goal" then G.stage_step(inp, FR) end
            acc = acc - FR; n = n + 1
        end
        if acc > FR * 6 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if st == "play" and P.st == "goal" then G.state = "goal"; G.goal_t = 0; G.bonus_given = false end
        if st == "play" and P.st == "timeup" and P.v < 0.5 and P.t > 2 then game_over(false) end
    else AL = 1 end
    -- engine note: short grains whose pitch follows the revs
    if (st == "play" or st == "count" or st == "goal") and not G.set_open then
        G.eng_t = (G.eng_t or 0) - dt
        if G.eng_t <= 0 then
            G.eng_t = 0.1
            local rpm = clamp(P.v / ((P.gear == "L") and G.CONST.VMAX_L or G.CONST.VMAX_H), 0, 1)
            if st == "count" then rpm = 0.25 + 0.15 * sin(G.t * 9) end
            local bin = clamp(floor(rpm * 7 + ((P.gear == "H") and 2.5 or 0) * rpm), 0, 9)
            sfx("eng" .. bin)
        end
    end
    if st == "title" then
        local p = world_at(P.s, 0, 0)
        local _, yaw = world_at(P.s, 0, 0)
        local ang = math.rad(yaw + 145 + 25 * sin(G.t * 0.2))
        local cx, cz = p.x + 8.5 * sin(ang), p.z + 8.5 * cos(ang)
        local dx, dz = p.x - cx, p.z - cz; local dl = math.sqrt(dx * dx + dz * dz)
        local rx, rz = -dz / dl, dx / dl
        G.cam_ov = { cx, p.y + 2.6, cz, p.x + rx * 3.6, p.y + 0.9, p.z + rz * 3.6 }
    else G.cam_ov = G.cam_ov_fixed end
    local gcur = floor(P.s / G.TC.SEG) + 1
    render_road(gcur)
    render_scenery(gcur)
    local carp, yaw = render_car(dt)
    render_traffic(dt)
    update_camera(dt, carp, yaw)
    update_lights(dt, carp)
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_world()
build_car()
to_title()
G.update = update; G.SET = SET; G.surf = surf
hooks { update = update }
pe_log("[OR] ready")
