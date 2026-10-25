-- DONKEY KONG REMIX  (PhasmaEngine, Lua)
-- A faithful modern remake of Nintendo's Donkey Kong (1981): the intro climb and girder stomp, all four original
-- stages (25m girders, 50m conveyors, 75m elevators, 100m rivets) with their layouts, barrels, blue barrels,
-- fireballs, firefoxes, cement pies, springs, hammers, Pauline's items, bonus timer, US stage order and the ending.
-- Simulation runs in the original 224x256 pixel space at a fixed 60 Hz (capped catch-up), rendered in 3D.
local PI = math.pi
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
math.randomseed(floor((engine.get_metrics and (engine.get_metrics() or {}).frame or 0) + 1981))
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local G = { state = "boot", t = 0 }
_G.DK = G
local function WX(px) return (px - 112) / 8 end
local function WY(py) return 16 - py / 8 end

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
local ss = scene.add_empty_node("DKSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "citynight.hdr")
S("hdr", false); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false); S("dof", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.2)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", true); S("IBL_intensity", 0.5)
S("color_grading", true); S("color_grading_saturation", 1.06); S("color_grading_contrast", 1.06)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "SETTINGS", subtitle = "Donkey Kong Remix", file = "Save/settings.cfg", music = true,
    click = function() sfx("click") end, defaults = { master = 0.5 },
    theme = { accent = { 1, 0.45, 0.3, 1 }, accent2 = { 0.4, 0.85, 0.9, 1 }, text = { 0.85, 0.82, 0.78, 1 }, selected_text = { 1, 0.96, 0.9, 1 } } })
SET:apply()
G.set_open = false

------------------------------------------------------------------ camera
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1600, surf.height or 900
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local CAMZ = 47
local VFOV = 2 * math.atan(17.4 / CAMZ)
local FOVX = 2 * math.atan(math.tan(VFOV / 2) * SW / SH)
pcall(function() cam:set_fov(math.deg(FOVX)) end)
local function to_screen(px, py)   -- original pixel coords -> screen pixels (z = 0 plane)
    local hh = CAMZ * math.tan(VFOV / 2)
    return SW / 2 + WX(px) / hh * SH / 2, SH / 2 - WY(py) / hh * SH / 2
end

------------------------------------------------------------------ templates -> clones
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[DK] missing template " .. name); return nil end
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
local function P_get(kind, tmpl)
    local p = POOL[kind]; if not p then P_begin(kind); p = POOL[kind] end
    p.used = p.used + 1
    local n = p.n[p.used]
    if not n then n = clone(tmpl or kind); p.n[p.used] = n end
    return n
end
local function P_end(kind) local p = POOL[kind]; if not p then return end; for i = p.used + 1, #p.n do p.n[i]:set_position(HIDE) end end

------------------------------------------------------------------ palette
local function paint_templates()
    local P = {
        m_skin = { { 1, .72, .55 }, { .02, .01, 0 }, .55 }, m_hair = { { .2, .1, .05 }, { 0, 0, 0 }, .7 }, m_eye = { { .04, .05, .12 }, { 0, 0, 0 }, .2 },
        m_cap = { { .86, .07, .05 }, { .03, 0, 0 }, .5 }, m_overalls = { { .82, .08, .06 }, { .02, 0, 0 }, .6 }, m_shirt = { { .12, .25, .78 }, { 0, 0, .02 }, .6 },
        m_button = { { 1, .8, .2 }, { .1, .07, 0 }, .3, .6 }, m_sleeve = { { .12, .25, .78 }, { 0, 0, .02 }, .6 }, m_hand = { { 1, .72, .55 }, { .02, .01, 0 }, .55 },
        m_leg = { { .82, .08, .06 }, { .02, 0, 0 }, .6 }, m_shoe = { { .35, .18, .07 }, { 0, 0, 0 }, .5 },
        hm_handle = { { .5, .3, .12 }, { 0, 0, 0 }, .6 }, hm_head = { { .85, .65, .38 }, { .02, .01, 0 }, .55 },
        dk_fur = { { .24, .11, .045 }, { .005, 0, 0 }, .85 }, dk_chest = { { .78, .52, .32 }, { .02, .01, 0 }, .7 }, dk_headfur = { { .24, .11, .045 }, { .005, 0, 0 }, .85 },
        dk_face = { { .8, .56, .36 }, { .02, .01, 0 }, .65 }, dk_eyew = { { .95, .95, .92 }, { .03, .03, .03 }, .3 }, dk_pupil = { { .03, .02, .02 }, { 0, 0, 0 }, .2 },
        dk_mouth = { { .35, .05, .04 }, { 0, 0, 0 }, .5 }, dk_teeth = { { .96, .95, .9 }, { .03, .03, .03 }, .3 },
        dk_arm_l = { { .24, .11, .045 }, { .005, 0, 0 }, .85 }, dk_arm_r = { { .24, .11, .045 }, { .005, 0, 0 }, .85 },
        dk_hand_l = { { .78, .52, .32 }, { .02, .01, 0 }, .7 }, dk_hand_r = { { .78, .52, .32 }, { .02, .01, 0 }, .7 },
        dk_leg_l = { { .24, .11, .045 }, { .005, 0, 0 }, .85 }, dk_leg_r = { { .24, .11, .045 }, { .005, 0, 0 }, .85 },
        dk_foot_l = { { .78, .52, .32 }, { .02, .01, 0 }, .7 }, dk_foot_r = { { .78, .52, .32 }, { .02, .01, 0 }, .7 },
        p_dress = { { .92, .22, .5 }, { .02, .005, .01 }, .55 }, p_skin = { { 1, .76, .62 }, { .02, .01, .01 }, .55 }, p_shoe = { { .95, .92, .9 }, { .01, .01, .01 }, .4 },
        p_face = { { 1, .76, .62 }, { .02, .01, .01 }, .55 }, p_hair = { { .85, .42, .12 }, { .02, .01, 0 }, .6 }, p_eye = { { .05, .08, .2 }, { 0, 0, 0 }, .2 },
        p_lips = { { .85, .12, .15 }, { .02, 0, 0 }, .4 }, p_arm = { { 1, .76, .62 }, { .02, .01, .01 }, .55 },
        b_wood = { { .42, .21, .08 }, { .01, 0, 0 }, .65 }, b_hoop = { { .22, .23, .28 }, { 0, 0, 0 }, .35, .7 },
        bb_wood = { { .14, .34, .85 }, { .0, .02, .06 }, .55 }, bb_hoop = { { .75, .85, .95 }, { .02, .02, .03 }, .3, .7 },
        od_body = { { .12, .32, .78 }, { 0, .01, .03 }, .4, .5 }, od_band = { { .9, .9, .95 }, { .02, .02, .02 }, .35, .6 },
        flame = { { 1, .55, .15 }, { 3.0, 1.2, .25 }, .5 },
        fb_body = { { 1, .62, .15 }, { 2.4, 1.15, .2 }, .5 }, ff_body = { { 1, .38, .1 }, { 2.2, .6, .12 }, .5 },
        fb_eye = { { 1, 1, .95 }, { .6, .6, .55 }, .3 }, fb_pupil = { { .02, .02, .04 }, { 0, 0, 0 }, .3 },
        g_red = { { .85, .16, .24 }, { .02, 0, .005 }, .45, .45 }, g_orange = { { .95, .48, .12 }, { .02, .01, 0 }, .45, .45 }, g_blue = { { .16, .36, .9 }, { 0, .005, .02 }, .45, .45 },
        ladder = { { .3, .82, .85 }, { .005, .02, .02 }, .4, .5 }, rung = { { .3, .82, .85 }, { .005, .02, .02 }, .4, .5 },
        conv_belt = { { .2, .2, .22 }, { 0, 0, 0 }, .6, .3 }, conv_tread = { { .9, .7, .2 }, { .02, .015, 0 }, .5, .3 }, conv_roller = { { .7, .7, .74 }, { 0, 0, 0 }, .3, .9 },
        pie_tray = { { .65, .67, .72 }, { 0, 0, 0 }, .3, .85 }, pie_cement = { { .82, .76, .62 }, { .01, .01, .01 }, .9 },
        el_cable = { { .15, .15, .17 }, { 0, 0, 0 }, .5, .8 }, el_motor = { { .95, .7, .12 }, { .02, .01, 0 }, .45, .5 },
        spring = { { .78, .8, .85 }, { .01, .01, .01 }, .25, .95 }, rivet = { { .9, .7, .15 }, { .03, .02, 0 }, .45, .6 },
        it_hat = { { .75, .25, .55 }, { .02, 0, .01 }, .5 }, it_purse = { { 1, .35, .6 }, { .02, 0, .01 }, .45 }, it_umbrella = { { .7, .3, .85 }, { .02, 0, .02 }, .5 },
        heart = { { 1, .2, .35 }, { .8, .08, .15 }, .35 }, heart_l = { { 1, .2, .35 }, { .8, .08, .15 }, .35 }, heart_r = { { 1, .2, .35 }, { .8, .08, .15 }, .35 },
        bg_block = { { .14, .14, .17 }, { .5, .42, .3 }, .8 }, bg_post = { { .12, .12, .14 }, { 0, 0, 0 }, .6, .6 },
    }
    for name, v in pairs(P) do paint(tnode(name), v[1], v[2], v[3], v[4]) end
    mtex(tnode("bg_block"), "emissive", "Textures/windows.png")
    for _, g in ipairs({ "g_red", "g_orange", "g_blue" }) do mtex(tnode(g), "base_color", "Textures/paint.png") end
    for name in pairs(P) do local n = tnode(name); if n then n:set_position(HIDE) end end
end

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
local LT = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(-0.25, -0.5, -0.8), vec3(0.8, 0.85, 1.0), 1.1)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    LT.key = addp(vec3(-6, 12, 26), vec3(1.0, 0.93, 0.85), 70, 90)
    LT.fill = addp(vec3(10, -6, 24), vec3(0.75, 0.85, 1.0), 40, 80)
    LT.fire = addp(HIDE, vec3(1, 0.5, 0.15), 0, 12)
    LT.fire2 = addp(HIDE, vec3(1, 0.5, 0.15), 0, 12)
    LT.top = addp(vec3(0, 12, 10), vec3(1.0, 0.85, 0.7), 14, 22)
    LT.hh = addp(HIDE, vec3(1.0, 0.92, 0.85), 0, 30)
    LT.flash = {}
    for i = 1, 4 do LT.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1 } end
end
G.flash_next = 1
local function flash(px, py, col, power, life, rad)
    local f = LT.flash[G.flash_next]; G.flash_next = G.flash_next % #LT.flash + 1
    f.t, f.life, f.x, f.y, f.col, f.power, f.rad = 0, life or 0.3, px, py, vec3(col[1], col[2], col[3]), power or 40, rad or 7
end
local function update_flashes(dt)
    for _, f in ipairs(LT.flash) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = 1 - clamp(f.t / f.life, 0, 1)
            set_point(f.idx, vec3(WX(f.x), WY(f.y), 2.5), f.col, f.power * k * k, f.rad)
            if f.t >= f.life then set_point(f.idx, HIDE, f.col, 0, 1) end
        end
    end
end

------------------------------------------------------------------ particles (pixel coords in, world out)
local function PS() return SET:particle_scale() end
local function burst(px, py, o)
    pcall(particles.emit_burst, {
        position = vec3(WX(px), WY(py), o.z or 0.6), velocity = o.vel or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = max(1, floor((o.count or 30) * PS())),
        size_min = o.smin or 0.05, size_max = o.smax or 0.14, life_min = o.lmin or 0.25, life_max = o.lmax or 0.7,
        spawn_radius = o.radius or 0.3, noise_strength = o.spread or 10, drag = o.drag or 2.0,
        gravity = o.grav or vec3(0, 0, 0), cleanup_delay = 3.0,
    })
end
local function sparks(px, py, col, n, spread)
    burst(px, py, { c0 = vec4(col[1] * 2.5 + .5, col[2] * 2.5 + .5, col[3] * 2.5 + .5, 1), c1 = vec4(col[1], col[2], col[3], 0), count = n or 24,
        smin = .04, smax = .09, lmin = .15, lmax = .45, radius = .1, spread = spread or 22, drag = 2.5, grav = vec3(0, -8, 0) })
end
local function dust(px, py, n)
    burst(px, py, { c0 = vec4(.75, .68, .6, .7), c1 = vec4(.5, .45, .4, 0), count = n or 14, smin = .08, smax = .2, lmin = .3, lmax = .8,
        radius = .25, spread = 5, drag = 3, grav = vec3(0, 0.6, 0), z = 0.7 })
end
local function new_emitter(o)
    local ok, e = pcall(particles.add_emitter, {
        position = HIDE, velocity = o.vel or vec3(0, 0, 0), gravity = o.grav or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = o.count or 200, spawn_rate = 0,
        spawn_radius = o.radius or 0.1, size_min = o.smin or 0.06, size_max = o.smax or 0.16,
        life_min = o.lmin or 0.15, life_max = o.lmax or 0.4, noise_strength = o.noise or 1.0, drag = o.drag or 1.5 })
    return ok and e or nil
end
local function emitter_at(e, px, py, z, rate)
    if not e then return end
    pcall(particles.set_emitter, e, "position", vec3(WX(px), WY(py), z or 0.3))
    pcall(particles.set_emitter, e, "spawn_rate", rate * PS())
end

------------------------------------------------------------------ input
local prev = {}
local keyfn = input.is_key_down_raw or input.is_key_pressed
if not G.vkeys then
    G.vkeys = {}
end
local function held(k)
    if G.vkeys[k] then
        return true
    end

    if G.vk and G.vk[k] then
        return true
    end

    local ok, v = pcall(keyfn, k)
    return ok and v
end

local function edge(k) local d = held(k); local p = prev[k]; prev[k] = d; return d and not p end
local function any(...) for _, k in ipairs({ ... }) do if held(k) then return true end end; return false end

------------------------------------------------------------------ score state
G.score, G.lives, G.level, G.hiscore = 0, 3, 1, 0
pcall(function() local s = fs.read("Save/dk_hiscore.txt"); if s then G.hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, "Save/dk_hiscore.txt", tostring(G.hiscore)) end
G.POP = {}
for i = 1, 8 do G.POP[i] = { t = 9, col = { 1, 1, 1 }, x = 0, y = 0 } end
G.pop_next = 1
local function popup(px, py, txt, col)
    local p = G.POP[G.pop_next]; G.pop_next = G.pop_next % #G.POP + 1
    p.t, p.x, p.y, p.txt, p.col = 0, px, py, txt, col or { 1, 1, 1 }
end
local function add_score(n, px, py)
    local before = G.score
    G.score = G.score + n
    if px then popup(px, py, tostring(n), { 1, .9, .55 }) end
    if before < 7000 and G.score >= 7000 then G.lives = G.lives + 1; sfx("extra") end
end
