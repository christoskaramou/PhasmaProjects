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
local function held(k) if G.vk and G.vk[k] then return true end local ok, v = pcall(keyfn, k); return ok and v end
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
------------------------------------------------------------------ stage data (original pixel space: x 0..223 right, y 0..255 down)
-- girder = { x0, sw (segment width px), ys = top surface y per segment, dir = barrel roll direction, conv = conveyor dir }
local function seq_ys(n, a, step) local t = {}; for i = 1, n do t[i] = a + (i - 1) * step end; return t end
local function flat(n, y) return seq_ys(n, y, 0) end
local function cat(a, b) local t = {}; for _, v in ipairs(a) do t[#t + 1] = v end; for _, v in ipairs(b) do t[#t + 1] = v end; return t end
local STAGE_DEF = {}
STAGE_DEF["25"] = function()
    return {
        kind = "25", mesh = "g_red", height = "25 m", music = "bgm25",
        girders = {
            { x0 = 0, sw = 16, ys = cat(flat(7, 248), seq_ys(7, 247, -1)), dir = -1 },   -- G1 bottom, oil drum on the left
            { x0 = 0, sw = 16, ys = seq_ys(13, 205, 1), dir = 1 },                        -- G2
            { x0 = 16, sw = 16, ys = seq_ys(13, 184, -1), dir = -1 },                     -- G3
            { x0 = 0, sw = 16, ys = seq_ys(13, 139, 1), dir = 1 },                        -- G4
            { x0 = 16, sw = 16, ys = seq_ys(13, 118, -1), dir = -1 },                     -- G5
            { x0 = 0, sw = 16, ys = cat(flat(9, 84), seq_ys(4, 85, 1)), dir = 1 },        -- G6 Kong's girder
            { x0 = 88, sw = 16, ys = flat(3, 56), dir = 1, top = true },                   -- Pauline
        },
        ladders = {
            { x = 80, lo = 1, hi = 2, broken = true }, { x = 184, lo = 1, hi = 2 },
            { x = 32, lo = 2, hi = 3 }, { x = 96, lo = 2, hi = 3 }, { x = 168, lo = 2, hi = 3, broken = true },
            { x = 64, lo = 3, hi = 4, broken = true }, { x = 112, lo = 3, hi = 4 }, { x = 184, lo = 3, hi = 4 },
            { x = 32, lo = 4, hi = 5 }, { x = 72, lo = 4, hi = 5, broken = true }, { x = 168, lo = 4, hi = 5 },
            { x = 72, lo = 5, hi = 6, broken = true }, { x = 184, lo = 5, hi = 6 },
            { x = 128, lo = 6, hi = 7 },
        },
        deco_ladders = { { x = 64, y0 = 84, y1 = 16 }, { x = 80, y0 = 84, y1 = 16 } },
        hammers = { { x = 168, g = 2 }, { x = 24, g = 5 } },
        items = {},
        drum = { x = 24, y = 248 },
        mario = { x = 60, g = 1 }, dk = { x = 44, y = 84 }, pauline = { x = 112, y = 56 },
        goal = function(m) return m.g == 7 end,
    }
end
STAGE_DEF["50"] = function()
    return {
        kind = "50", mesh = "g_orange", height = "50 m", music = "bgm50",
        girders = {
            { x0 = 0, sw = 16, ys = flat(14, 248), dir = 1 },                        -- 1 floor
            { x0 = 16, sw = 16, ys = flat(12, 208), conv = 1, swap = true },        -- 2 long belt (reverses)
            { x0 = 0, sw = 16, ys = flat(6, 168), conv = 1 },                       -- 3 left belt into the fire
            { x0 = 96, sw = 16, ys = flat(2, 168) },                                 -- 4 oil fire stand
            { x0 = 128, sw = 16, ys = flat(6, 168), conv = -1 },                    -- 5 right belt into the fire
            { x0 = 0, sw = 16, ys = flat(5, 128) },                                  -- 6
            { x0 = 88, sw = 16, ys = flat(3, 128), conv = -1, swap = true },        -- 7 short belt
            { x0 = 144, sw = 16, ys = flat(5, 128) },                                -- 8
            { x0 = 0, sw = 16, ys = flat(14, 88), conv = 1, swap = true, top = true }, -- 9 Kong's belt (goal)
            { x0 = 88, sw = 16, ys = flat(3, 48) },                                  -- 10 Pauline
        },
        ladders = {
            { x = 24, lo = 1, hi = 2 }, { x = 112, lo = 1, hi = 2 }, { x = 200, lo = 1, hi = 2 },
            { x = 48, lo = 2, hi = 3 }, { x = 176, lo = 2, hi = 5 },
            { x = 40, lo = 3, hi = 6, retract = true }, { x = 72, lo = 3, hi = 6 }, { x = 152, lo = 5, hi = 8 }, { x = 184, lo = 5, hi = 8, retract = true },
            { x = 16, lo = 6, hi = 9 }, { x = 64, lo = 6, hi = 9, retract = true }, { x = 160, lo = 8, hi = 9, retract = true }, { x = 208, lo = 8, hi = 9 },
        },
        hammers = { { x = 24, g = 6 }, { x = 104, g = 2 } },
        items = { { kind = "it_umbrella", x = 40, g = 2 }, { kind = "it_hat", x = 168, g = 1 }, { kind = "it_purse", x = 200, g = 8 } },
        fire = { x = 112, y = 168 },
        mario = { x = 60, g = 1 }, dk = { x = 112, y = 88, patrol = { 72, 152 } }, pauline = { x = 112, y = 48 },
        goal = function(m) return m.g == 9 end,
    }
end
STAGE_DEF["75"] = function()
    return {
        kind = "75", mesh = "g_red", height = "75 m", music = "bgm75", pit = true,
        girders = {
            { x0 = 0, sw = 8, ys = flat(4, 240) },        -- 1 start ledge
            { x0 = 72, sw = 8, ys = flat(3, 184) },       -- 2 island A
            { x0 = 72, sw = 8, ys = flat(3, 128) },       -- 3 island B
            { x0 = 128, sw = 8, ys = flat(4, 232) },      -- 4 low right
            { x0 = 136, sw = 8, ys = flat(11, 184) },     -- 5
            { x0 = 160, sw = 8, ys = flat(8, 144) },      -- 6
            { x0 = 136, sw = 8, ys = flat(7, 112) },      -- 7
            { x0 = 0, sw = 8, ys = flat(24, 84) },        -- 8 Kong's girder (springs)
            { x0 = 88, sw = 8, ys = flat(6, 56), top = true }, -- 9 Pauline
        },
        ladders = {
            { x = 88, lo = 2, hi = 3 }, { x = 76, lo = 3, hi = 8 },
            { x = 148, lo = 4, hi = 5 }, { x = 212, lo = 5, hi = 6 }, { x = 172, lo = 6, hi = 7 }, { x = 144, lo = 7, hi = 8 },
            { x = 128, lo = 8, hi = 9 },
        },
        elevators = { { x = 56, dir = -1 }, { x = 112, dir = 1 } },
        hammers = {},
        items = { { kind = "it_umbrella", x = 80, g = 3 }, { kind = "it_purse", x = 216, g = 6 }, { kind = "it_hat", x = 100, g = 8 } },
        mario = { x = 14, g = 1 }, dk = { x = 28, y = 84 }, pauline = { x = 112, y = 56 },
        goal = function(m) return m.g == 9 end,
    }
end
STAGE_DEF["100"] = function()
    local R = { 56, 168 }
    local function fl(x0, x1, y) return { x0 = x0, sw = 8, ys = flat((x1 - x0) / 8, y), rivets = (y < 248 and y > 48) and { R[1], R[2] } or nil } end
    return {
        kind = "100", mesh = "g_blue", height = "100 m", music = "bgm100",
        girders = { fl(0, 224, 248), fl(8, 216, 208), fl(16, 208, 168), fl(24, 200, 128), fl(32, 192, 88), { x0 = 88, sw = 8, ys = flat(6, 48), top = true } },
        ladders = {
            { x = 16, lo = 1, hi = 2 }, { x = 112, lo = 1, hi = 2 }, { x = 208, lo = 1, hi = 2 },
            { x = 24, lo = 2, hi = 3 }, { x = 84, lo = 2, hi = 3 }, { x = 140, lo = 2, hi = 3 }, { x = 200, lo = 2, hi = 3 },
            { x = 32, lo = 3, hi = 4 }, { x = 112, lo = 3, hi = 4 }, { x = 192, lo = 3, hi = 4 },
            { x = 40, lo = 4, hi = 5 }, { x = 88, lo = 4, hi = 5 }, { x = 136, lo = 4, hi = 5 }, { x = 184, lo = 4, hi = 5 },
        },
        hammers = { { x = 24, g = 3 }, { x = 200, g = 2 } },
        items = { { kind = "it_umbrella", x = 188, g = 2 }, { kind = "it_purse", x = 44, g = 3 }, { kind = "it_hat", x = 176, g = 4 } },
        mario = { x = 60, g = 1 }, dk = { x = 112, y = 88, patrol = { 80, 144 } }, pauline = { x = 112, y = 48 },
        goal = function() return false end,
    }
end

------------------------------------------------------------------ live stage + surface queries
local ST = nil
G.ST = function() return ST end
local function gx1(g) return g.x0 + g.sw * #g.ys end
local function in_hole(g, x, who)
    if not g.holes then return false end
    for _, h in ipairs(g.holes) do
        if h.open and x >= h.a and x < h.b and not (who == "mario" and h.grace) then return true end
    end
    return false
end
local function covers(g, x, who) return x >= g.x0 and x < gx1(g) and not in_hole(g, x, who) end
local function surf(g, x)
    local i = clamp(floor((x - g.x0) / g.sw) + 1, 1, #g.ys)
    return g.ys[i]
end
-- floors near y (inclusive band): returns girder index, surface y (elevator platforms are returned as "E"..)
local function floor_near(x, y, up, down, who)
    local best, by, bd = nil, nil, 1e9
    for i, g in ipairs(ST.girders) do
        if covers(g, x, who) then
            local s = surf(g, x)
            if s >= y - up and s <= y + down then
                local d = abs(s - y); if d < bd then best, by, bd = i, s, d end
            end
        end
    end
    if ST.plats then
        for _, p in ipairs(ST.plats) do
            if p.live and x >= p.x - 8 and x < p.x + 8 and p.y >= y - up and p.y <= y + down then
                local d = abs(p.y - y); if d < bd then best, by, bd = p, p.y, d end
            end
        end
    end
    return best, by
end
local function ladder_at(x, y, tol)
    for _, l in ipairs(ST.ladders) do
        if abs(x - l.x) <= (tol or 3) and y <= l.ylo + 0.5 and y >= l.yhi - 0.5 then return l end
    end
end
local function ladder_bottom(x, y, tol)
    for _, l in ipairs(ST.ladders) do if abs(x - l.x) <= (tol or 3) and abs(y - l.ylo) <= 2.5 then return l end end
end
local function ladder_top(x, y, tol)
    for _, l in ipairs(ST.ladders) do if abs(x - l.x) <= (tol or 3) and abs(y - l.yhi) <= 2.5 then return l end end
end
-- highest point Mario can climb to on a ladder (broken / retracted ladders stop short)
local function ladder_limit(l)
    if l.broken then return l.ylo - (l.ylo - l.yhi) * 0.42 end
    if l.retract then return lerp(l.yhi, l.ylo - (l.ylo - l.yhi) * 0.42, l.rk or 0) end
    return l.yhi
end

------------------------------------------------------------------ backdrop (built once): night city + scaffold
local function build_backdrop()
    local function block(x, y, z, w, h, d) clone("bg_block", vec3(x, y, z), vec3(w, h, d)) end
    math.randomseed(77)
    for i = -16, 16 do
        local x = i * 4.6 + rr(-1, 1)
        local h = rr(14, 34) + (abs(i) > 6 and 6 or 0)
        block(x, -26, -60 - rr(0, 20), rr(3.5, 5.5), h, rr(3, 6))
    end
    for i = -9, 9 do
        local x = i * 6 + rr(-1.5, 1.5)
        if abs(x) > 17 then block(x, -24, -28 - rr(0, 6), rr(3, 5), rr(10, 22), rr(3, 5)) end
    end
    -- steel scaffold behind the playfield (posts + cross beams)
    for i = 0, 6 do
        local x = -13.6 + i * 4.53
        clone("bg_post", vec3(x, -17, -3.2), vec3(1.3, 34, 1.3))
    end
    for j = 0, 7 do clone("bg_post", vec3(0, -15.5 + j * 4.4, -3.25), vec3(0.8, 27.6, 0.8)):set_rotation(vec3(0, 0, 90)) end
    math.randomseed(floor(G.t * 1000 + 4242))
    G.ground = prim("cube", vec3(0, -17.6, -6), vec3(120, 1.2, 40))
    paint(G.ground, { .06, .06, .07 }, { 0, 0, 0 }, .9, 0)
end

------------------------------------------------------------------ stage build (pooled clones)
local POOLED = { "g_red", "g_orange", "g_blue", "ladder", "conv_belt", "conv_tread", "conv_roller", "rivet", "el_cable", "el_motor", "od_body", "od_band", "flame",
    "hm_handle", "hm_head", "it_hat", "it_purse", "it_umbrella" }
local function place_girders(g, gi)
    local mesh = g.conv and "conv_belt" or ST.mesh
    g.nodes = g.nodes or {}
    for i, y in ipairs(g.ys) do
        local n = g.nodes[i]
        if not n then n = P_get(mesh); g.nodes[i] = n end
        local cx = g.x0 + g.sw * (i - 0.5)
        local hidden = false
        if g.holes then for _, h in ipairs(g.holes) do if h.open and cx >= h.a and cx < h.b then hidden = true end end end
        n:set_position(hidden and HIDE or vec3(WX(cx), WY(y), ((i + gi) % 2) * 0.004))
        n:set_scale(vec3(g.sw / 16, g.conv and 1.35 or 1, 1))
    end
end
local function build_stage(kind)
    for _, k in ipairs(POOLED) do P_begin(k) end
    ST = STAGE_DEF[kind]()
    for gi, g in ipairs(ST.girders) do
        g.final = {}; for i, y in ipairs(g.ys) do g.final[i] = y end
        if g.rivets then
            g.holes = {}
            for _, rx in ipairs(g.rivets) do g.holes[#g.holes + 1] = { a = rx - 4, b = rx + 4, open = false, x = rx } end
        end
        place_girders(g, gi)
        if g.conv then
            g.treads, g.rollers = {}, {}
            local len = gx1(g) - g.x0
            for i = 1, floor(len / 8) do g.treads[i] = P_get("conv_tread") end
            g.rollers[1] = P_get("conv_roller"); g.rollers[2] = P_get("conv_roller")
            g.phase = 0
        end
    end
    for _, l in ipairs(ST.ladders) do
        l.ylo = surf(ST.girders[l.lo], l.x); l.yhi = surf(ST.girders[l.hi], l.x)
        l.nodes = { P_get("ladder") }
        if l.broken or l.retract then l.nodes[2] = P_get("ladder") end
        l.rk = 0
    end
    if ST.deco_ladders then for _, d in ipairs(ST.deco_ladders) do d.node = P_get("ladder") end end
    -- rivets (100m)
    ST.rivets = {}
    for gi, g in ipairs(ST.girders) do
        if g.holes then for _, h in ipairs(g.holes) do
            local n = P_get("rivet")
            n:set_position(vec3(WX(h.x), WY(surf(g, h.x)), 0.02)); n:set_scale(vec3(1.05, 1, 1))
            ST.rivets[#ST.rivets + 1] = { g = gi, h = h, node = n, x = h.x, y = surf(g, h.x) }
        end end
    end
    -- elevators (75m): three platforms per shaft, cables and motors
    if ST.elevators then
        ST.plats = {}
        for _, e in ipairs(ST.elevators) do
            for k = 0, 2 do
                local p = { x = e.x, dir = e.dir, ph = k / 3, live = true, node = P_get(ST.mesh), y = 200 }
                ST.plats[#ST.plats + 1] = p
            end
            local c1, c2 = P_get("el_cable"), P_get("el_cable")
            c1:set_position(vec3(WX(e.x - 7), WY(250), -0.4)); c1:set_scale(vec3(1, (250 - 92) / 8, 1))
            c2:set_position(vec3(WX(e.x + 7), WY(250), -0.4)); c2:set_scale(vec3(1, (250 - 92) / 8, 1))
            local m1, m2 = P_get("el_motor"), P_get("el_motor")
            m1:set_position(vec3(WX(e.x), WY(93), -0.1)); m2:set_position(vec3(WX(e.x), WY(251), -0.1))
        end
    end
    -- oil drum
    if ST.drum or ST.fire then
        local d = ST.drum or ST.fire
        local b, band, fl = P_get("od_body"), P_get("od_band"), P_get("flame")
        b:set_position(vec3(WX(d.x), WY(d.y), 0)); band:set_position(vec3(WX(d.x), WY(d.y), 0))
        ST.flame = fl; ST.drum_xy = d
        ST.lit = ST.fire ~= nil
    end
    -- hammers + items
    ST.hammer_props = {}
    for _, h in ipairs(ST.hammers) do
        local g = ST.girders[h.g]
        local hp = { x = h.x, y = surf(g, h.x) - 22, live = true, n1 = P_get("hm_handle"), n2 = P_get("hm_head") }
        ST.hammer_props[#ST.hammer_props + 1] = hp
    end
    for _, it in ipairs(ST.items) do
        it.y = surf(ST.girders[it.g], it.x); it.live = true; it.node = P_get(it.kind)
    end
    for _, k in ipairs(POOLED) do P_end(k) end
    G.bend_all(1)
end
-- girder bend factor for the intro (0 = flat, 1 = original slants); also refreshes ladders
function G.bend_all(b) for gi = 1, #ST.girders do G.bend(gi, b) end; G.refresh_ladders() end
function G.bend(gi, b)
    local g = ST.girders[gi]
    local avg = 0; for _, y in ipairs(g.final) do avg = avg + y end; avg = avg / #g.final
    if gi == 1 then avg = g.final[1] end
    if gi == 6 and ST.kind == "25" then avg = 84 end
    for i, y in ipairs(g.final) do g.ys[i] = lerp(avg, y, b) end
    g.bent = b
    place_girders(g, gi)
end
-- one ladder piece: rails from ybot up to ytop (pixels, y grows downwards) plus rungs at a fixed 4 px pitch.
-- Fixed pieces put their rungs on the world 4 px grid, so every ladder has the same spacing at the same heights;
-- a moving piece (retractable top) carries its rungs with it, measured from its own top.
local RUNG_PITCH = 4
local function lad_seg(node, x, ybot, ytop, z, pool, moving)
    node:set_position(vec3(WX(x), WY(ybot), z)); node:set_scale(vec3(1, max(0.01, (ybot - ytop) / 8), 1))
    local y = moving and (ytop + RUNG_PITCH / 2) or (floor(ytop / RUNG_PITCH) + 1) * RUNG_PITCH
    while y < ybot - 1 do
        if y > ytop + 1 then local r = P_get(pool, "rung"); r:set_position(vec3(WX(x), WY(y), z)) end
        y = y + RUNG_PITCH
    end
end
G.lad_seg = lad_seg
function G.refresh_ladders()
    P_begin("rung")
    for _, l in ipairs(ST.ladders) do
        l.ylo = surf(ST.girders[l.lo], l.x); l.yhi = surf(ST.girders[l.hi], l.x)
        local len = l.ylo - l.yhi
        local a, b = l.nodes[1], l.nodes[2]
        if l.hidden then a:set_position(HIDE); if b then b:set_position(HIDE) end
        elseif l.broken then
            lad_seg(a, l.x, l.ylo, l.ylo - len * 0.3, -0.3, "rung")
            lad_seg(b, l.x, l.yhi + len * 0.3, l.yhi, -0.3, "rung")
        elseif l.retract then
            local k = l.rk or 0
            lad_seg(a, l.x, l.ylo, l.ylo - len * 0.36, -0.3, "rung")
            local top = lerp(l.yhi, l.ylo - len * 0.36, k)
            lad_seg(b, l.x, top + len * 0.5, top, -0.32, "rung", true)
        else
            lad_seg(a, l.x, l.ylo, l.yhi, -0.3, "rung")
        end
    end
    if ST.deco_ladders then for _, d in ipairs(ST.deco_ladders) do
        if d.hidden then d.node:set_position(HIDE) else lad_seg(d.node, d.x, d.y0, d.y1, -0.3, "rung") end
    end end
    P_end("rung")
end
------------------------------------------------------------------ character rigs (part pivots match tools/gen_meshes.py)
local function grp(parent, pos, meshes)
    local g = empty("grp", parent, pos)
    for _, m in ipairs(meshes) do clone(m, vec3(0, 0, 0), nil, g) end
    return g
end
local function build_mario()
    local root = empty("Mario", nil, HIDE)
    local r = { root = root }
    r.torso = grp(root, vec3(0, 0.78, 0), { "m_overalls", "m_shirt", "m_button" })
    r.head = grp(root, vec3(0, 1.42, 0), { "m_skin", "m_hair", "m_eye", "m_cap" })
    r.arm_l = grp(root, vec3(0, 1.32, 0.3), { "m_sleeve", "m_hand" })
    r.arm_r = grp(root, vec3(0, 1.32, -0.3), { "m_sleeve", "m_hand" })
    r.leg_l = grp(root, vec3(0, 0.62, 0.14), { "m_leg", "m_shoe" })
    r.leg_r = grp(root, vec3(0, 0.62, -0.14), { "m_leg", "m_shoe" })
    r.hammer = grp(root, vec3(0.12, 1.25, 0.36), { "hm_handle", "hm_head" })
    r.hammer:set_position(HIDE)
    return r
end
local function build_dk(name)
    local root = empty(name or "Kong", nil, HIDE)
    local r = { root = root }
    r.torso = empty("dk_torso", root, vec3(0, 1.0, 0))
    clone("dk_fur", vec3(0, -1.0, 0), nil, r.torso); clone("dk_chest", vec3(0, -1.0, 0), nil, r.torso)
    r.head = grp(r.torso, vec3(0, 1.7, 0.25), { "dk_headfur", "dk_face", "dk_eyew", "dk_pupil", "dk_mouth", "dk_teeth" })
    r.arm_l = grp(r.torso, vec3(-1.05, 1.35, 0), { "dk_arm_l", "dk_hand_l" })
    r.arm_r = grp(r.torso, vec3(1.05, 1.35, 0), { "dk_arm_r", "dk_hand_r" })
    r.leg_l = grp(root, vec3(-0.55, 1.0, 0), { "dk_leg_l", "dk_foot_l" })
    r.leg_r = grp(root, vec3(0.55, 1.0, 0), { "dk_leg_r", "dk_foot_r" })
    return r
end
local function build_pauline()
    local root = empty("Pauline", nil, HIDE)
    local r = { root = root }
    clone("p_dress", vec3(0, 0, 0), nil, root); clone("p_skin", vec3(0, 0, 0), nil, root); clone("p_shoe", vec3(0, 0, 0), nil, root)
    r.head = grp(root, vec3(0, 1.78, 0), { "p_face", "p_hair", "p_eye", "p_lips" })
    r.arm_l = grp(root, vec3(-0.28, 1.6, 0), { "p_arm" })
    r.arm_r = grp(root, vec3(0.28, 1.6, 0), { "p_arm" })
    return r
end
local function rig_pool(n, meshes)
    local p = {}
    for i = 1, n do
        local root = empty("ent", nil, HIDE)
        for _, m in ipairs(meshes) do clone(m, vec3(0, 0, 0), nil, root) end
        p[i] = { root = root, used = false }
    end
    return p
end
local function rig_take(pool)
    for _, r in ipairs(pool) do if not r.used then r.used = true; return r end end
end
local function rig_free(r) if r then r.used = false; r.root:set_position(HIDE) end end
local RIGS = {}
local function build_rigs()
    RIGS.mario = build_mario()
    RIGS.dk = build_dk("Kong")
    RIGS.pauline = build_pauline()
    RIGS.barrel = rig_pool(14, { "b_wood", "b_hoop" })
    RIGS.bbarrel = rig_pool(8, { "bb_wood", "bb_hoop" })
    RIGS.stack = rig_pool(4, { "b_wood", "b_hoop" })
    RIGS.fire = rig_pool(6, { "fb_body", "fb_eye", "fb_pupil" })
    RIGS.fox = rig_pool(6, { "ff_body", "fb_eye", "fb_pupil" })
    RIGS.pie = rig_pool(8, { "pie_tray", "pie_cement" })
    RIGS.spring = rig_pool(6, { "spring" })
    RIGS.heart = clone("heart"); RIGS.heart_l = clone("heart_l"); RIGS.heart_r = clone("heart_r")
    RIGS.hh = {}
    for i = 1, 4 do RIGS.hh[i] = build_dk("KongHH" .. i) end
end
local function V(x, y, z) return vec3(x, y, z) end
-- pose helpers (angles in degrees)
local function pose_mario(r, o)
    r.root:set_position(o.pos); r.root:set_rotation(V(o.rx or 0, o.yaw or 0, o.rz or 0)); r.root:set_scale(V(o.s or 1, o.s or 1, o.s or 1))
    r.leg_l:set_rotation(V(o.lx or 0, 0, o.ll or 0)); r.leg_r:set_rotation(V(-(o.lx or 0), 0, o.lr or 0))
    r.arm_l:set_rotation(V(o.ax or 0, 0, o.al or 0)); r.arm_r:set_rotation(V(-(o.ax or 0), 0, o.ar or 0))
    r.head:set_rotation(V(0, o.hy or 0, o.hz or 0))
    r.torso:set_rotation(V(0, 0, o.tz or 0))
    if o.ham then r.hammer:set_position(V(0.12, 1.25, 0.36)); r.hammer:set_rotation(V(0, 0, o.ham)) else r.hammer:set_position(HIDE) end
end
local function pose_dk(r, o)
    r.root:set_position(o.pos); r.root:set_rotation(V(o.rx or 0, o.yaw or 0, o.rz or 0)); r.root:set_scale(V(o.s or 1, (o.s or 1) * (o.sy or 1), o.s or 1))
    r.torso:set_position(V(0, 1.0 + (o.bob or 0), 0)); r.torso:set_rotation(V(o.lean or 0, o.ty or 0, 0))
    r.arm_l:set_rotation(V(o.alx or 0, 0, o.alz or 0)); r.arm_r:set_rotation(V(o.arx or 0, 0, o.arz or 0))
    r.leg_l:set_rotation(V(o.llx or 0, 0, o.llz or 0)); r.leg_r:set_rotation(V(o.lrx or 0, 0, o.lrz or 0))
    r.head:set_rotation(V(o.hx or 0, o.hy or 0, o.hz or 0))
end
local function pose_pauline(r, o)
    local s = 1.12
    r.root:set_position(o.pos); r.root:set_rotation(V(o.rx or 0, o.yaw or 0, o.rz or 0)); r.root:set_scale(V(s, s, s))
    r.arm_l:set_rotation(V(o.alx or 0, 0, o.alz or 0)); r.arm_r:set_rotation(V(o.arx or 0, 0, o.arz or 0))
    r.head:set_rotation(V(0, o.hy or 0, o.hz or 0))
end
------------------------------------------------------------------ gameplay simulation (60 Hz, original pixel units)
local FR = 1 / 60
local WALK, CLIMB, JUMP_V, GRAV = 0.75, 0.62, 1.65, 0.097
G.SPEEDS = { walk = WALK, climb = CLIMB, jump_v = JUMP_V, grav = GRAV }
local M = { st = "hidden", x = 0, y = 0, ox = 0, oy = 0, face = 1, ph = 0, ham = 0, hph = 0 }
G.M = M
local B, F, PIES, SPR = {}, {}, {}, {}
G.B, G.F, G.PIES, G.SPR = B, F, PIES, SPR
local KONG = { x = 44, y = 84, ox = 44, oy = 84, st = "idle", t = 0, dir = 1, throws = 0 }
G.KONG = KONG
local PAUL = { x = 112, y = 56, t = 0, help = 0 }
G.PAUL = PAUL
local HB = { mario = { 4, 13, 1 }, barrel = 5, fire = { 5, 11 }, pie = { 6, 7 }, spring = { 6, 12 }, kong = { 13, 30 } }
G.HB = HB
local function overlap(ax0, ay0, ax1, ay1, bx0, by0, bx1, by1) return ax0 < bx1 and bx0 < ax1 and ay0 < by1 and by0 < ay1 end
local function mario_box() return M.x - HB.mario[1], M.y - HB.mario[2], M.x + HB.mario[1], M.y - HB.mario[3] end
local function ent_box(e)
    if e.kind == "barrel" then return e.x - HB.barrel, e.y - HB.barrel * 2, e.x + HB.barrel, e.y end
    if e.kind == "pie" then return e.x - HB.pie[1], e.y - HB.pie[2], e.x + HB.pie[1], e.y end
    if e.kind == "spring" then return e.x - HB.spring[1], e.y - HB.spring[2], e.x + HB.spring[1], e.y end
    return e.x - HB.fire[1], e.y - HB.fire[2], e.x + HB.fire[1], e.y - 1
end
G.mario_box, G.ent_box = mario_box, ent_box
local function diff() return min(5, G.level + floor((G.stage_f or 0) / (60 * 45))) end
local function on_conv(g) local gg = type(g) == "number" and ST.girders[g]; return gg and gg.conv and (gg.cs or 0) or 0 end

------------------------------------------------------------------ Mario
local function mario_die(cause)
    if M.st == "dead" or G.god then return end
    M.st = "dead"; M.dead_f = 0; M.cause = cause
    music(nil); sfx("death")
    flash(M.x, M.y - 8, { 1, .4, .3 }, 30, 0.5, 6)
end
G.mario_die = mario_die
local function land_on(x, y0, y1, who)
    local best, by = nil, 1e9
    for i, g in ipairs(ST.girders) do
        if covers(g, x, who) then
            local s = surf(g, x)
            if s >= y0 - 0.5 and s <= y1 + 0.5 and s < by then best, by = i, s end
        end
    end
    if ST.plats and who == "mario" then
        for _, p in ipairs(ST.plats) do
            if p.live and x >= p.x - 8.5 and x < p.x + 8.5 and p.y >= y0 - 2.5 and p.y <= y1 + 0.5 and p.y < by then best, by = p, p.y end
        end
    end
    return best, by
end
local function award_jump()
    local n = 0; for _ in pairs(M.jumped or {}) do n = n + 1 end
    if n > 0 then add_score(n == 1 and 100 or (n == 2 and 300 or 800), M.x, M.y - 18); sfx("item") end
    M.jumped = {}
end
local function mario_reset(def)
    M.st = "walk"; M.x = def.x; M.g = def.g; M.y = surf(ST.girders[def.g], def.x); M.ox, M.oy = M.x, M.y
    M.face = 1; M.ph = 0; M.ham = 0; M.vx, M.vy = 0, 0; M.jumped = {}; M.ladder = nil; M.walk_snd = 0
end
G.mario_reset = mario_reset
local function rivet_check(px)
    if ST.kind ~= "100" then return end
    for _, r in ipairs(ST.rivets) do
        local h = r.h
        if not h.open then
            local crossed = (px - h.x) * (M.x - h.x) <= 0 and abs(px - M.x) < 3
            local above = M.y <= r.y + 0.5 and r.y - M.y < 26
            if crossed and above and M.st ~= "climb" then
                h.open = true; h.grace = true; r.fly = 0
                add_score(100, h.x, r.y - 14); sfx("rivet"); sparks(h.x, r.y, { 1, .8, .25 }, 20)
                ST.rivets_left = ST.rivets_left - 1
            end
        end
        if h.grace and (abs(M.x - h.x) > 5 or M.st == "jump") then h.grace = (M.st == "jump") and abs(M.x - h.x) <= 5 or false end
    end
end
local function mario_step(inp)
    M.ox, M.oy = M.x, M.y
    local px = M.x
    if M.st == "walk" then
        local ham = M.ham > 0
        local l_up = (inp.v < 0 and not ham) and ladder_bottom(M.x, M.y, 3)
        if l_up and ladder_limit(l_up) >= M.y - 1 then l_up = nil end
        local l_dn = (inp.v > 0 and not ham) and ladder_top(M.x, M.y, 3)
        if l_dn and (l_dn.broken or (l_dn.retract and (l_dn.rk or 0) > 0.02) or ST.girders[l_dn.lo] == nil) then l_dn = nil end
        if l_up then M.st = "climb"; M.ladder = l_up; M.x = l_up.x
        elseif l_dn then M.st = "climb"; M.ladder = l_dn; M.x = l_dn.x; M.y = M.y + 0.05
        elseif inp.jump and not ham then
            M.st = "jump"; M.vy = -JUMP_V; M.vx = inp.h * WALK; M.ty = M.y; M.jumped = {}; sfx("jump")
            if inp.h ~= 0 then M.face = inp.h end
        else
            local dx = inp.h * WALK + on_conv(M.g)
            if inp.h ~= 0 then M.face = inp.h end
            M.x = clamp(M.x + dx, 5, 219)
            if ST.drum and M.x < ST.drum.x + 13 and M.y > 230 then M.x = ST.drum.x + 13 end
            if type(M.g) == "table" then M.y = M.g.y end
            local g, s = floor_near(M.x, M.y, 3, 3, "mario")
            if g then M.g = g; M.y = s
            else M.st = "fall"; M.vy = 0; M.vx = 0; M.ty = M.y end
            if inp.h ~= 0 then
                M.ph = M.ph + 0.2
                M.walk_snd = (M.walk_snd or 0) - 1
                if M.walk_snd <= 0 then sfx("walk"); M.walk_snd = 9 end
            else M.walk_snd = 0 end
        end
    elseif M.st == "climb" then
        local l = M.ladder
        local lim = ladder_limit(l)
        if inp.v < 0 then M.y = max(lim, M.y - CLIMB); M.ph = M.ph + 0.15
        elseif inp.v > 0 then M.y = M.y + CLIMB; M.ph = M.ph + 0.15 end
        if M.y < lim then M.y = lim end
        if M.y <= l.yhi + 0.001 and lim <= l.yhi + 0.001 then M.st = "walk"; M.g = l.hi; M.y = l.yhi
        elseif M.y >= l.ylo then M.st = "walk"; M.g = l.lo; M.y = l.ylo end
        if M.st == "climb" and (inp.v ~= 0) then
            M.walk_snd = (M.walk_snd or 0) - 1
            if M.walk_snd <= 0 then sfx("walk"); M.walk_snd = 14 end
        end
    elseif M.st == "jump" or M.st == "fall" then
        M.vy = min(M.vy + GRAV, 3.2)
        M.x = M.x + M.vx
        if M.x < 5 or M.x > 219 then M.vx = -M.vx; M.x = clamp(M.x, 5, 219) end
        local y0 = M.y
        M.y = M.y + M.vy
        if M.st == "jump" then
            for _, list in ipairs({ B, F, PIES, SPR }) do
                for _, e in ipairs(list) do
                    if abs(e.x - M.x) < 8 and e.y > M.y + 1 and e.y - M.y < 28 and not M.jumped[e] then M.jumped[e] = true end
                end
            end
        end
        if M.vy > 0 then
            local g, s = land_on(M.x, y0, M.y, "mario")
            if g then
                M.y = s; M.g = g
                if s - M.ty > 12 then mario_die("fall"); M.y = s
                else M.st = "walk"; if next(M.jumped or {}) then award_jump() end end
            end
        end
        if M.y > 262 then mario_die("pit") end
    end
    -- carried by elevator / crushed by the motor
    if M.st == "walk" and type(M.g) == "table" then
        M.y = M.g.y
        if M.g.dir < 0 and M.g.y < 104 then mario_die("crush") end
        if not M.g.live then M.st = "fall"; M.vy = 0; M.vx = 0; M.ty = M.y end
    end
    if M.st ~= "dead" then rivet_check(px) end
    -- hammer pickup + timer
    if M.st ~= "dead" then
        if M.ham <= 0 then
            local x0, y0, x1, y1 = mario_box()
            for _, h in ipairs(ST.hammer_props) do
                if h.live and overlap(x0, y0 - 3, x1, y1, h.x - 5, h.y - 6, h.x + 5, h.y + 6) then
                    h.live = false; M.ham = 60 * 10; M.hph = 0; music("hammer"); sfx("item")
                    if M.st == "climb" then M.st = "walk" end
                end
            end
        else
            M.ham = M.ham - 1; M.hph = M.hph + 1
            if M.ham <= 0 then music(ST.music) end
        end
    end
end
local function hammer_box()
    if M.ham <= 0 or M.st == "dead" then return nil end
    if floor(M.hph / 9) % 2 == 0 then return M.x - 7, M.y - 32, M.x + 7, M.y - 14 end
    local a = M.x + M.face * 3; local b = M.x + M.face * 17
    return min(a, b), M.y - 13, max(a, b), M.y + 1
end
G.hammer_box = hammer_box

------------------------------------------------------------------ barrels
local function free_ent(list, i) local e = list[i]; rig_free(e.rig); table.remove(list, i) end
local function spawn_fire(x, y, kind)
    local cap = ST.kind == "75" and 2 or 5
    if #F >= cap then return end
    local pool = kind == "fox" and RIGS.fox or RIGS.fire
    local r = rig_take(pool); if not r then return end
    F[#F + 1] = { kind = kind or "fire", x = x, y = y, ox = x, oy = y, st = "spawn", vx = 0.55, vy = -1.5, dir = 1, g = nil, t = 30, rig = r, ph = rand() * 6 }
end
G.spawn_fire = spawn_fire
local function ignite(x, y)
    if not ST.lit then ST.lit = true end
    sfx("ignite"); flash(x, y - 18, { 1, .55, .2 }, 70, 0.6, 9)
    sparks(x, y - 16, { 1, .5, .15 }, 30, 18)
end
local function barrel_spawn(mode, blue)
    local r = rig_take(blue and RIGS.bbarrel or RIGS.barrel); if not r then return end
    local b = { kind = "barrel", x = KONG.x + 14, y = 84, st = "roll", dir = 1, g = 6, vx = 0, vy = 0, blue = blue, rig = r, spin = 0, bnc = 0 }
    if mode == "drop" then b.st = "drop"; b.x = 28; b.y = 70; b.vy = 0; b.skip = {}
    elseif mode == "wild" then b.st = "wild"; b.x = KONG.x + 10; b.y = 74; b.vx = (M.x > b.x) and 0.7 or 0.35; b.vy = 0; b.skip = {} end
    b.ox, b.oy = b.x, b.y
    B[#B + 1] = b
    return b
end
G.barrel_spawn = barrel_spawn
local function barrel_ladder_choice(b, l)
    if l.hi == 7 then return false end
    local p = 0.18 + 0.06 * diff()
    if M.y > b.y + 8 then p = p + 0.15; if abs(M.x - l.x) < 40 then p = p + 0.25 end end
    if M.ham > 0 then p = p * 0.5 end
    return rand() < p
end
local function enter_drum(b)
    if b.blue or b.first then ignite(ST.drum.x, ST.drum.y); spawn_fire(ST.drum.x, ST.drum.y - 16, "fire") end
    sparks(ST.drum.x, ST.drum.y - 15, { 1, .6, .2 }, 10, 10)
end
local function barrel_step(b, i)
    b.ox, b.oy = b.x, b.y
    local sp = 1.0 + 0.04 * diff()
    if b.st == "roll" then
        local g = ST.girders[b.g]
        local nx = b.x + b.dir * sp
        for _, l in ipairs(ST.ladders) do
            if l.hi == b.g and (b.x - l.x) * (nx - l.x) <= 0 and b.lastl ~= l then
                b.lastl = l
                if barrel_ladder_choice(b, l) then b.st = "ladder"; b.ladder = l; b.x = l.x; return end
            end
        end
        b.x = nx; b.spin = b.spin - b.dir * sp / 5 * 57.3
        if covers(g, b.x) then b.y = surf(g, b.x)
        else b.st = "fall"; b.vx = b.dir * 0.55; b.vy = 0.3; b.bnc = 0; b.from = b.g end
        if ST.drum and b.g == 1 and b.x <= ST.drum.x + 9 then enter_drum(b); free_ent(B, i); return end
    elseif b.st == "ladder" then
        b.y = b.y + sp * 0.9
        if b.y >= b.ladder.ylo then b.st = "roll"; b.g = b.ladder.lo; b.y = b.ladder.ylo; b.dir = ST.girders[b.g].dir; b.lastl = b.ladder end
    elseif b.st == "fall" then
        b.vy = min(b.vy + 0.12, 3); b.x = b.x + b.vx
        local y0 = b.y; b.y = b.y + b.vy
        if b.vy > 0 then
            local g, s = land_on(b.x, y0, b.y, "barrel")
            if g and g ~= b.from then
                b.y = s
                if b.bnc == 0 then b.bnc = 1; b.vy = -0.9; b.vx = b.vx * 0.4; b.g2 = g; sfx("land")
                else b.st = "roll"; b.g = g; b.dir = ST.girders[g].dir end
            elseif g and b.bnc == 1 and g == b.from then b.st = "roll"; b.g = g; b.dir = ST.girders[g].dir end
        end
        if b.x < -10 or b.x > 234 or b.y > 262 then free_ent(B, i); return end
    elseif b.st == "wild" or b.st == "drop" then
        b.vy = min(b.vy + 0.1, 2.6); b.x = b.x + b.vx
        local y0 = b.y; b.y = b.y + b.vy
        b.spin = b.spin + 6
        if b.vy > 0 then
            for gi, g in ipairs(ST.girders) do
                if not b.skip[gi] and covers(g, b.x) then
                    local s = surf(g, b.x)
                    if s >= y0 and s <= b.y then
                        b.skip[gi] = true
                        if gi == 1 then
                            if b.st == "drop" then b.y = s; enter_drum(b); free_ent(B, i); return end
                            b.st = "roll"; b.g = 1; b.y = s; b.dir = (b.x < 112) and -1 or 1; return
                        end
                        b.y = s; b.vy = -1.1; sfx("land"); dust(b.x, s, 6)
                        if b.st == "wild" then b.vx = clamp((M.x - b.x) / 60, -0.9, 0.9) end
                        break
                    end
                end
            end
        end
        if b.st == "drop" and b.y >= ST.drum.y - 15 and abs(b.x - ST.drum.x) < 10 then enter_drum(b); free_ent(B, i); return end
        if b.x < -10 or b.x > 234 or b.y > 262 then free_ent(B, i); return end
    end
end

------------------------------------------------------------------ fireballs / firefoxes
local function fire_step(f, i)
    f.ox, f.oy = f.x, f.y
    f.ph = f.ph + 0.15
    local sp = (f.kind == "fox" and 0.5 or 0.42) + 0.03 * diff()
    if f.st == "spawn" then
        f.vy = f.vy + 0.08; f.x = f.x + f.vx; local y0 = f.y; f.y = f.y + f.vy
        if f.vy > 0 then
            local g, s = land_on(f.x, y0, f.y, "fire")
            if g then f.st = "walk"; f.g = g; f.y = s; f.dir = 1 end
        end
        if f.y > 262 then free_ent(F, i) end
        return
    end
    if f.st == "walk" then
        f.t = f.t - 1
        local flee = M.ham > 0
        if f.t <= 0 then
            f.t = floor(rr(40, 120))
            local tow = (M.x > f.x) and 1 or -1
            if flee then f.dir = -tow elseif rand() < 0.55 then f.dir = tow elseif rand() < 0.5 then f.dir = -f.dir end
        end
        local g = ST.girders[f.g]
        local nx = f.x + f.dir * sp * (flee and 0.7 or 1)
        -- ladders: climb toward Mario now and then
        for _, l in ipairs(ST.ladders) do
            if not l.broken and not (l.retract and (l.rk or 0) > 0.02) and l.hi ~= #ST.girders and not ST.girders[l.hi].top and (f.x - l.x) * (nx - l.x) <= 0 then
                local want_up = M.y < f.y - 10
                if l.lo == f.g and rand() < (want_up and 0.45 or 0.12) then f.st = "climb"; f.ladder = l; f.x = l.x; f.cdir = -1; return end
                if l.hi == f.g and rand() < ((not want_up and M.y > f.y + 10) and 0.45 or 0.1) then f.st = "climb"; f.ladder = l; f.x = l.x; f.cdir = 1; return end
            end
        end
        if ST.drum and f.g == 1 and nx < ST.drum.x + 12 then f.dir = 1 end
        if not covers(g, nx + f.dir * 4) or nx < 6 or nx > 218 or (ST.fire and f.g ~= 4 and abs(nx - ST.fire.x) < 14 and abs(surf(g, nx) - ST.fire.y) < 2) then f.dir = -f.dir; nx = f.x end
        f.x = nx; f.y = surf(g, f.x)
    elseif f.st == "climb" then
        local l = f.ladder
        f.y = f.y + f.cdir * sp * 0.8
        if f.cdir < 0 and f.y <= l.yhi then f.st = "walk"; f.g = l.hi; f.y = l.yhi; f.t = 20 end
        if f.cdir > 0 and f.y >= l.ylo then f.st = "walk"; f.g = l.lo; f.y = l.ylo; f.t = 20 end
    end
end

------------------------------------------------------------------ cement pies (50m), springs (75m)
local function pie_spawn(gi)
    local g = ST.girders[gi]
    local d = g.conv * (g.flip or 1)
    local x = d > 0 and g.x0 + 4 or gx1(g) - 4
    for _, p in ipairs(PIES) do if p.g == gi and abs(p.x - x) < 26 then return end end
    local r = rig_take(RIGS.pie); if not r then return end
    PIES[#PIES + 1] = { kind = "pie", x = x, y = surf(g, x), ox = x, oy = surf(g, x), g = gi, st = "ride", rig = r, vy = 0 }
end
local function pie_step(p, i)
    p.ox, p.oy = p.x, p.y
    if p.st == "ride" then
        local g = ST.girders[p.g]
        p.x = p.x + (g.cs or 0)
        if not covers(g, p.x) then
            local fg, s = floor_near(p.x, p.y, 1, 1, "pie")
            if fg and ST.girders[fg] and ST.girders[fg].conv then p.g = fg
            else p.st = "fall"; p.vy = 0 end
        end
        if ST.fire and abs(p.x - ST.fire.x) < 9 and abs(p.y - ST.fire.y) < 2 then
            sparks(p.x, p.y - 8, { 1, .5, .2 }, 16); free_ent(PIES, i); return
        end
    else
        p.vy = p.vy + 0.15; p.y = p.y + p.vy
        if p.y > 262 then free_ent(PIES, i); return end
    end
end
local function spring_step(s, i)
    s.ox, s.oy = s.x, s.y
    s.sq = max(0, (s.sq or 0) - 0.08)
    s.vy = s.vy + 0.11
    local y0 = s.y
    s.x = s.x + s.vx; s.y = s.y + s.vy
    if s.st == "hop" then
        if s.x >= 184 then s.st = "drop"; s.vx = 0; sfx("spring") end
        if s.vy > 0 and s.y >= 84 and y0 <= 84 then s.y = 84; s.vy = -1.75; s.sq = 1; sfx("spring") end
    end
    if s.y > 266 then free_ent(SPR, i) end
end

------------------------------------------------------------------ Kong + world behaviour per stage
local function kong_step()
    KONG.ox, KONG.oy = KONG.x, KONG.y
    KONG.t = KONG.t - 1
    local k = ST.kind
    if k == "25" then
        if KONG.st == "idle" and KONG.t <= 0 then
            if KONG.throws > 0 and KONG.throws % 5 == 4 and rand() < 0.6 then KONG.st = "beat"; KONG.t = 70; sfx("beat")
            else KONG.st = "grab"; KONG.t = 28 end
        elseif KONG.st == "beat" and KONG.t <= 0 then KONG.st = "idle"; KONG.t = 20; KONG.throws = KONG.throws + 1
        elseif KONG.st == "grab" and KONG.t <= 0 then KONG.st = "hold"; KONG.t = 16
        elseif KONG.st == "hold" and KONG.t <= 0 then
            KONG.st = "throw"; KONG.t = 18; KONG.throws = KONG.throws + 1
            local first = not G.first_done
            if first then
                G.first_done = true
                local b = barrel_spawn("drop", true); if b then b.first = true end
            else
                local d = diff()
                local wild = d >= 2 and rand() < 0.08 + 0.04 * d
                barrel_spawn(wild and "wild" or "roll", rand() < 0.1 + 0.03 * d)
            end
            sfx("throw")
        elseif KONG.st == "throw" and KONG.t <= 0 then
            KONG.st = "idle"; KONG.t = floor(rr(50, 150) * (1.15 - 0.12 * diff()))
        end
    elseif k == "75" then
        if KONG.st == "idle" and KONG.t <= 0 then KONG.st = "grab"; KONG.t = 24
        elseif KONG.st == "grab" and KONG.t <= 0 then
            KONG.st = "throw"; KONG.t = 16
            local r = rig_take(RIGS.spring)
            if r then SPR[#SPR + 1] = { kind = "spring", x = 52, y = 84, ox = 52, oy = 84, vx = 1.05 + rr(0, 0.25), vy = -1.5, st = "hop", rig = r } end
            sfx("throw")
        elseif KONG.st == "throw" and KONG.t <= 0 then
            KONG.st = (rand() < 0.2) and "beat" or "idle"; KONG.t = KONG.st == "beat" and 70 or floor(rr(70, 160) * (1.1 - 0.1 * diff()))
            if KONG.st == "beat" then sfx("beat") end
        elseif KONG.st == "beat" and KONG.t <= 0 then KONG.st = "idle"; KONG.t = 30 end
    else
        local p = ST.dk.patrol
        if KONG.st == "beat" then
            if KONG.t <= 0 then KONG.st = "walk"; KONG.t = floor(rr(150, 320)) end
        else
            KONG.st = "walk"
            KONG.x = KONG.x + KONG.dir * 0.35
            if KONG.x < p[1] then KONG.x = p[1]; KONG.dir = 1 end
            if KONG.x > p[2] then KONG.x = p[2]; KONG.dir = -1 end
            if rand() < 0.004 then KONG.dir = -KONG.dir end
            if KONG.t <= 0 then KONG.st = "beat"; KONG.t = 80; sfx("beat") end
        end
    end
end
local function world_step()
    local d = diff()
    -- conveyors
    for gi, g in ipairs(ST.girders) do
        if g.conv then
            if g.swap then
                g.sw_t = (g.sw_t or floor(rr(300, 540))) - 1
                if g.sw_t <= 0 then g.flip = -(g.flip or 1); g.sw_t = floor(rr(300, 540)) end
            end
            g.cs = g.conv * (g.flip or 1) * 0.5
            g.phase = (g.phase or 0) + g.cs
        end
    end
    -- retractable ladders (50m)
    for _, l in ipairs(ST.ladders) do
        if l.retract then
            l.rt = (l.rt or floor(rr(60, 240))) - 1
            if l.rt <= 0 then l.up = not l.up; l.rt = floor(l.up and rr(120, 200) or rr(150, 260)) end
            local tgt = l.up and 1 or 0
            l.rk = clamp((l.rk or 0) + (tgt > (l.rk or 0) and 0.02 or -0.02), 0, 1)
            if abs(l.rk - tgt) < 0.02 then l.rk = tgt end
        end
    end
    if ST.kind == "50" then
        G.pie_t = (G.pie_t or 60) - 1
        if G.pie_t <= 0 then
            G.pie_t = floor(rr(80, 170) * (1.15 - 0.1 * d))
            local opts = { 2, 3, 5 }
            if #PIES < 7 then pie_spawn(opts[floor(rr(1, 3.999))]) end
        end
        G.fox_t = (G.fox_t or 240) - 1
        if G.fox_t <= 0 then G.fox_t = floor(rr(360, 600) * (1.1 - 0.1 * d)); spawn_fire(ST.fire.x, ST.fire.y - 16, "fox") end
    elseif ST.kind == "100" then
        G.fox_t = (G.fox_t or 120) - 1
        if G.fox_t <= 0 then
            G.fox_t = floor(rr(420, 700) * (1.1 - 0.1 * d))
            local side = rand() < 0.5 and 20 or 204
            local gi = floor(rr(1, 3.999))
            local r = #F < 5 and rig_take(RIGS.fox)
            if r then local g = ST.girders[gi]; F[#F + 1] = { kind = "fox", x = side, y = surf(g, side), ox = side, oy = surf(g, side), st = "walk", g = gi, dir = side < 112 and 1 or -1, t = 40, rig = r, ph = 0, pop = 1 } end
        end
    elseif ST.kind == "75" then
        for _, p in ipairs(ST.plats) do
            p.oy = p.y
            p.ph = (p.ph + 0.5 / 152) % 1
            p.y = (p.dir < 0) and (248 - p.ph * 152) or (96 + p.ph * 152)
            p.live = p.y < 247 and p.y > 97
        end
        if #F < 2 and (G.stage_f or 0) % 240 == 120 then
            local spots = { { 5, 200 }, { 6, 180 } }
            local s = spots[#F + 1]
            local r = rig_take(RIGS.fire)
            if r then local g = ST.girders[s[1]]; F[#F + 1] = { kind = "fire", x = s[2], y = surf(g, s[2]), ox = s[2], oy = surf(g, s[2]), st = "walk", g = s[1], dir = -1, t = 40, rig = r, ph = 0, pop = 1 } end
        end
    end
end

------------------------------------------------------------------ collisions + scoring
local function smash(e, list, i, pts)
    add_score(pts, e.x, e.y - 14); sfx("smash")
    sparks(e.x, e.y - 6, { 1, .85, .5 }, 30, 26); flash(e.x, e.y - 6, { 1, .9, .7 }, 50, 0.3, 6)
    G.smash_fx = { x = e.x, y = e.y - 6, t = 0 }
    free_ent(list, i)
end
local function collide()
    if M.st == "dead" or M.st == "hidden" then return end
    local x0, y0, x1, y1 = mario_box()
    local hx0, hy0, hx1, hy1 = hammer_box()
    local function test(list, pts_fn)
        for i = #list, 1, -1 do
            local e = list[i]
            if e and e.st ~= "spawn" then
                local a, b, c, d = ent_box(e)
                if hx0 and pts_fn and overlap(hx0, hy0, hx1, hy1, a, b, c, d) then smash(e, list, i, pts_fn(e))
                elseif overlap(x0, y0, x1, y1, a, b, c, d) then mario_die(e.kind); return end
            end
        end
    end
    local function rnd_pts() local r = rand(); return r < 0.6 and 300 or (r < 0.9 and 500 or 800) end
    test(B, rnd_pts)
    test(F, function() return 500 end)
    test(PIES, function() return 500 end)
    test(SPR, nil)
    -- Kong
    local kh = HB.kong
    if overlap(x0, y0, x1, y1, KONG.x - kh[1], KONG.y - kh[2], KONG.x + kh[1], KONG.y) then mario_die("kong") end
    -- oil fire on the 50m stand
    if ST.fire and overlap(x0, y0, x1, y1, ST.fire.x - 8, ST.fire.y - 22, ST.fire.x + 8, ST.fire.y) then mario_die("fire") end
    -- items
    for _, it in ipairs(ST.items) do
        if it.live and overlap(x0, y0, x1, y1, it.x - 6, it.y - 10, it.x + 6, it.y) then
            it.live = false; add_score(G.level == 1 and 300 or (G.level == 2 and 500 or 800), it.x, it.y - 14); sfx("item")
            sparks(it.x, it.y - 6, { 1, .6, .8 }, 20)
        end
    end
end
local function stage_step(inp)
    G.stage_f = (G.stage_f or 0) + 1
    world_step()
    if M.st ~= "dead" then
        mario_step(inp)
        kong_step()
        for i = #B, 1, -1 do if B[i] then barrel_step(B[i], i) end end
        for i = #F, 1, -1 do if F[i] then fire_step(F[i], i) end end
        for i = #PIES, 1, -1 do if PIES[i] then pie_step(PIES[i], i) end end
        for i = #SPR, 1, -1 do if SPR[i] then spring_step(SPR[i], i) end end
        collide()
        -- bonus timer
        if G.attract then return end
        G.bonus_f = (G.bonus_f or 0) + 1
        if G.bonus_f >= 120 then
            G.bonus_f = 0; G.bonus = max(0, G.bonus - 100)
            if G.bonus <= 1000 and G.bonus > 0 then sfx("timeout") end
            if G.bonus <= 0 then mario_die("time") end
        end
    else
        M.dead_f = M.dead_f + 1
        M.ox, M.oy = M.x, M.y
    end
end
G.stage_step = stage_step
local function clear_ents()
    for _, list in ipairs({ B, F, PIES, SPR }) do for i = #list, 1, -1 do free_ent(list, i) end end
end
G.clear_ents = clear_ents
------------------------------------------------------------------ rendering (interpolated between sim steps)
local AL = 1
local function ip(e) return lerp(e.ox or e.x, e.x, AL), lerp(e.oy or e.y, e.y, AL) end
G.vis = { mz = 0, myaw = -20, ham = 10, kyaw = 0 }
local VIS = G.vis
local EMIT = {}
local function build_fx()
    EMIT.drum = new_emitter({ c0 = vec4(2.4, 1.0, .25, 1), c1 = vec4(.8, .2, .05, 0), vel = vec3(0, 2.2, 0), radius = 0.45, smin = .1, smax = .26, lmin = .25, lmax = .6, noise = 2.5, drag = 1.2, count = 300 })
    EMIT.smoke = new_emitter({ c0 = vec4(.25, .22, .2, .35), c1 = vec4(.15, .14, .13, 0), vel = vec3(0, 1.6, 0), radius = 0.4, smin = .25, smax = .5, lmin = .8, lmax = 1.6, noise = 1.5, drag = .6, count = 200 })
    for _, r in ipairs(RIGS.fire) do r.em = new_emitter({ c0 = vec4(2.2, 1.1, .25, 1), c1 = vec4(.8, .25, .05, 0), vel = vec3(0, 1.6, 0), radius = 0.3, smin = .06, smax = .15, lmin = .15, lmax = .35, noise = 2, count = 120 }) end
    for _, r in ipairs(RIGS.fox) do r.em = new_emitter({ c0 = vec4(2.2, .6, .15, 1), c1 = vec4(.7, .1, .03, 0), vel = vec3(0, 1.6, 0), radius = 0.3, smin = .06, smax = .15, lmin = .15, lmax = .35, noise = 2, count = 120 }) end
    G.held = rig_pool(1, { "b_wood", "b_hoop" })[1]
    G.held_spring = rig_pool(1, { "spring" })[1]
    G.intro_lad = { clone("ladder"), clone("ladder") }
end
local function render_mario(dt)
    local r = RIGS.mario
    if M.st == "hidden" then r.root:set_position(HIDE); return end
    local x, y = ip(M)
    local climbing = M.st == "climb"
    VIS.mz = damp(VIS.mz, climbing and 0.8 or 0, 14, dt)
    local yaw_t = climbing and 90 or (M.face > 0 and -20 or 200)
    VIS.myaw = damp(VIS.myaw, yaw_t, 18, dt)
    local o = { pos = V(WX(x), WY(y), VIS.mz), yaw = VIS.myaw }
    local s = sin(M.ph * 1.4)
    if M.st == "walk" then
        local moving = abs(M.x - M.ox) > 0.05
        local a = moving and 32 or 0
        o.ll, o.lr, o.al, o.ar = a * s, -a * s, -a * 0.8 * s, a * 0.8 * s
        o.pos = V(WX(x), WY(y) + (moving and abs(s) * 0.05 or 0), VIS.mz)
    elseif climbing then
        o.al, o.ar = 150 + 25 * s, 150 - 25 * s
        o.ll, o.lr = 30 * max(0, s), 30 * max(0, -s)
    elseif M.st == "jump" or M.st == "fall" then
        o.ll, o.lr, o.al, o.ar = 28, -18, 160, -25
    elseif M.st == "dead" then
        local f = M.dead_f or 0
        if f < 70 then o.yaw = VIS.myaw + f * 21; o.al, o.ar = 60, 60
        else o.yaw = -20; o.rz = 90; o.pos = V(WX(x) - 0.9, WY(y) + 0.32, 0.2); o.al, o.ar = 160, 20 end
    elseif M.st == "win" then
        o.yaw = 15; o.al, o.ar = 0, 0
    end
    if M.ham > 0 and M.st ~= "dead" then
        local up = floor(M.hph / 9) % 2 == 0
        VIS.ham = damp(VIS.ham, up and 8 or -100, 30, dt)
        o.ham = VIS.ham
        o.al = up and 165 or 75; o.ar = o.al
        if M.ham < 120 and floor(M.ham / 6) % 2 == 0 then o.ham = nil end
    end
    pose_mario(r, o)
end
local function render_kong(dt)
    local r = RIGS.dk
    if G.kong_hidden then r.root:set_position(HIDE); return end
    local x, y = ip(KONG)
    local t = G.t
    local o = { pos = V(WX(x), WY(y), -0.25), s = 1 }
    local st = KONG.st
    local yaw_t = 0
    o.alx, o.arx = -8 + 4 * sin(t * 2), -8 + 4 * sin(t * 2 + 1)
    o.alz, o.arz = -10, 10
    o.bob = 0.04 * sin(t * 3)
    if st == "beat" then
        local b = sin(t * 18)
        o.alx = -75 + 25 * b; o.arx = -75 - 25 * b; o.alz, o.arz = 30, -30; o.hx = -10
    elseif st == "grab" then yaw_t = -70; o.alx, o.arx = -60, -60; o.lean = 18
    elseif st == "hold" then yaw_t = 0; o.alx, o.arx = -175, -175; o.alz, o.arz = 12, -12
    elseif st == "throw" then yaw_t = 70; o.alx, o.arx = -85, -85; o.lean = 15
    elseif st == "walk" then
        local s = sin(t * 7)
        yaw_t = KONG.dir * 35; o.llx, o.lrx = 22 * s, -22 * s; o.alx, o.arx = -22 * s, 22 * s; o.bob = abs(s) * 0.12
    elseif st == "climb" then
        local s = sin(t * 7)
        yaw_t = 180; o.alx, o.arx = -165 + 20 * s, -165 - 20 * s; o.llx, o.lrx = -30 * max(0, s), -30 * max(0, -s)
    elseif st == "hop" then o.alx, o.arx = -150, -150; o.alz, o.arz = 30, -30; o.llx, o.lrx = -25, -25
    elseif st == "grin" then o.alz, o.arz = -40 + 10 * sin(t * 6), 40 - 10 * sin(t * 6); o.hz = 8 * sin(t * 5)
    elseif st == "fall" then o.rx = 180; o.pos = V(WX(x), WY(y) + 4.2, -0.25); o.alz, o.arz = -120 + 30 * sin(t * 14), 120 - 30 * sin(t * 14); o.llx, o.lrx = 40 * sin(t * 12), -40 * sin(t * 12)
    elseif st == "dazed" then o.rx = 180; o.pos = V(WX(x), WY(y) + 4.1, -0.25); o.alz, o.arz = -95, 95; o.hy = 25 * sin(t * 4) end
    VIS.kyaw = damp(VIS.kyaw, KONG.yaw_ov or yaw_t, 10, dt)
    o.yaw = VIS.kyaw
    pose_dk(r, o)
    -- barrel / spring in his hands
    local hb = G.held
    if ST and ST.kind == "25" and (st == "grab" or st == "hold") and not G.cut then
        local hx, hy = WX(x), WY(y) + (st == "hold" and 5.1 or 1.8)
        local hz = st == "grab" and 0.9 or 0.2
        if st == "grab" then hx = hx - 1.6 end
        hb.root:set_position(V(hx, hy, hz)); hb.root:set_rotation(V(0, 0, 0))
    else hb.root:set_position(HIDE) end
    if ST and ST.kind == "75" and st == "grab" then G.held_spring.root:set_position(V(WX(x) + 1.4, WY(y) + 2.6, 0.6)) else G.held_spring.root:set_position(HIDE) end
end
local function render_pauline(dt)
    local r = RIGS.pauline
    if G.paul_hidden then r.root:set_position(HIDE); return end
    local x, y = PAUL.x, PAUL.y
    local t = G.t
    local o = { pos = V(WX(x), WY(y), PAUL.z or 0.1), yaw = PAUL.yaw or (sin(t * 0.7) * 12) }
    if PAUL.carried then
        o.pos = PAUL.carried; o.rx = 0; o.rz = 80; o.yaw = 0
        o.alz, o.arz = -150 + 30 * sin(t * 10), 150 - 30 * sin(t * 10)
    elseif PAUL.help > 0 then
        o.arz = 150 + 22 * sin(t * 11); o.alz = -20; o.hz = 6 * sin(t * 3)
    else
        o.alz, o.arz = -12 + 4 * sin(t * 2), 12 - 4 * sin(t * 2.3)
    end
    pose_pauline(r, o)
end
local function render_ents(dt)
    local t = G.t
    for _, b in ipairs(B) do
        local x, y = ip(b)
        b.rig.root:set_position(V(WX(x), WY(y) + 0.63, 0.05))
        b.rig.root:set_rotation(V(0, b.st == "ladder" and 70 or 0, b.spin or 0))
    end
    for _, pool in ipairs({ RIGS.fire, RIGS.fox }) do for _, r in ipairs(pool) do if not r.used then emitter_at(r.em, 0, 2000, 0, 0) end end end
    for _, f in ipairs(F) do
        local x, y = ip(f)
        local sc = 1 + 0.08 * sin(f.ph * 3)
        if f.pop then f.pop = max(0, f.pop - dt * 2); sc = sc * (1 - f.pop) end
        f.rig.root:set_position(V(WX(x), WY(y) + 0.02 + 0.06 * abs(sin(f.ph)), 0.1))
        f.rig.root:set_rotation(V(0, (f.st == "climb") and 0 or f.dir * 35, 4 * sin(f.ph * 2)))
        f.rig.root:set_scale(V(sc, sc * (1 + 0.05 * sin(f.ph * 5)), sc))
        emitter_at(f.rig.em, x, y - 7, 0.1, 40)
    end
    for _, p in ipairs(PIES) do
        local x, y = ip(p)
        p.rig.root:set_position(V(WX(x), WY(y), 0.05))
    end
    for _, s in ipairs(SPR) do
        local x, y = ip(s)
        s.rig.root:set_position(V(WX(x), WY(y), 0.1))
        s.rig.root:set_scale(V(1 + 0.2 * (s.sq or 0), 1 - 0.35 * (s.sq or 0), 1 + 0.2 * (s.sq or 0)))
    end
end
local function render_stage(dt)
    if not ST then return end
    local t = G.t
    -- conveyors: moving slats + spinning end rollers
    for gi, g in ipairs(ST.girders) do
        if g.conv and g.treads then
            local x0, len = g.x0, gx1(g) - g.x0
            local y = WY(g.ys[1])
            for i, n in ipairs(g.treads) do
                local px = x0 + ((i - 1) * 8 + (g.phase or 0)) % len
                n:set_position(V(WX(px), y + 0.03, 0)); n:set_scale(V(0.22, 1, 1))
            end
            g.rollers[1]:set_position(V(WX(x0), y - 0.3, 0)); g.rollers[2]:set_position(V(WX(x0 + len), y - 0.3, 0))
            local a = -(g.phase or 0) * 20
            g.rollers[1]:set_rotation(V(0, 0, a)); g.rollers[2]:set_rotation(V(0, 0, a))
        end
    end
    -- retractable ladders follow their state
    local any_r = false
    for _, l in ipairs(ST.ladders) do if l.retract then any_r = true end end
    if any_r then G.refresh_ladders() end
    -- rivets: pop out and tumble away
    for _, r in ipairs(ST.rivets) do
        if r.h.open then
            if not r.placed then r.placed = true; place_girders(ST.girders[r.g], r.g) end
            if r.fly then
                r.fly = r.fly + dt
                local k = r.fly
                r.node:set_position(V(WX(r.x) + k * 2.5, WY(r.y) + 2.2 * k - 9 * k * k, 0.6 + k)); r.node:set_rotation(V(k * 400, 0, k * 300))
                if k > 1.2 then r.fly = nil; r.node:set_position(HIDE) end
            end
        end
    end
    -- elevator platforms
    if ST.plats then for _, p in ipairs(ST.plats) do
        local y = lerp(p.oy or p.y, p.y, AL)
        if p.live then p.node:set_position(V(WX(p.x), WY(y), 0)); p.node:set_scale(V(1, 0.6, 1)) else p.node:set_position(HIDE) end
    end end
    -- oil drum fire
    if ST.drum_xy then
        local d = ST.drum_xy
        if ST.lit then
            local fl = 1 + 0.12 * sin(t * 17) + 0.08 * sin(t * 29)
            ST.flame:set_position(V(WX(d.x), WY(d.y) + 1.9, 0)); ST.flame:set_scale(V(1.0, fl * 1.1, 1.0))
            emitter_at(EMIT.drum, d.x, d.y - 17, 0, 60); emitter_at(EMIT.smoke, d.x, d.y - 24, -0.2, 8)
            set_point(LT.fire, V(WX(d.x), WY(d.y) + 3.2, 2.2), V(1, .5, .15), 55 * fl, 12)
        else
            ST.flame:set_position(HIDE); emitter_at(EMIT.drum, 0, 2000, 0, 0); emitter_at(EMIT.smoke, 0, 2000, 0, 0)
            set_point(LT.fire, HIDE, V(1, .5, .15), 0, 1)
        end
    else
        emitter_at(EMIT.drum, 0, 2000, 0, 0); emitter_at(EMIT.smoke, 0, 2000, 0, 0)
        set_point(LT.fire, HIDE, V(1, .5, .15), 0, 1)
    end
    for _, h in ipairs(ST.hammer_props) do
        if h.live then
            local yaw = t * 60
            h.n1:set_position(V(WX(h.x), WY(h.y + 6) + 0.05 * sin(t * 3), 0.1)); h.n1:set_rotation(V(0, yaw, 0))
            h.n2:set_position(V(WX(h.x), WY(h.y + 6) + 0.05 * sin(t * 3), 0.1)); h.n2:set_rotation(V(0, yaw, 0))
        else h.n1:set_position(HIDE); h.n2:set_position(HIDE) end
    end
    for _, it in ipairs(ST.items) do
        if it.live then it.node:set_position(V(WX(it.x), WY(it.y) + 0.05, 0.1)); it.node:set_rotation(V(0, 25 * sin(t * 1.5), 0))
        else it.node:set_position(HIDE) end
    end
    -- Kong's barrel stack (25m)
    for i, r in ipairs(RIGS.stack) do
        if ST.kind == "25" and not G.stack_hidden then
            local cx = ({ 8, 19, 8, 19 })[i]; local lay = i > 2 and 1 or 0
            r.root:set_position(V(WX(cx), WY(84) + lay * 0.96, -0.1)); r.root:set_rotation(V(90, 0, 0))
        else r.root:set_position(HIDE) end
    end
end

------------------------------------------------------------------ camera
G.shake = 0
local function update_camera(dt)
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.5 * SET:shake_scale()
    local ox, oy = a * sin(G.t * 53), a * cos(G.t * 61)
    if G.cam_ov then local o = G.cam_ov; cam:set_position(V(o[1], o[2], o[3])); cam:look_at(V(o[4], o[5], o[6] or 0)); return end
    local fx = (M.st ~= "hidden" and WX(M.x) or 0) * 0.04
    local sway = sin(G.t * 0.21) * 0.25
    cam:set_position(V(fx + sway + ox, 0.3 + oy, CAMZ)); cam:look_at(V(fx * 0.6 + sway * 0.5 + ox * 0.5, -0.1 + oy * 0.5, 0))
end

------------------------------------------------------------------ collider debug overlay (F3)
-- thin emissive bars; every point is pulled along its camera ray to z = DBG.z so outlines sit on the z = 0 gameplay plane
G.DBG = { on = false, pool = {}, used = 0, z = 3.0, w = 0.07 }
G.DBG_COL = { floor = { .1, 1, 1 }, ladder = { 1, .9, .2 }, mario = { .2, 1, .3 }, enemy = { 1, .25, .2 }, hammer = { 1, .6, .1 }, item = { 1, .4, .9 }, plat = { .3, .6, 1 } }
function G.dbg_bar(x0, y0, x1, y1, col)
    local D = G.DBG
    D.used = D.used + 1
    local b = D.pool[D.used]
    if not b then
        if #D.pool >= 1500 then return end
        b = { n = prim("cube", HIDE, V(1, 1, 1)), col = nil }
        D.pool[D.used] = b
    end
    if b.col ~= col then b.col = col; paint(b.n, { col[1] * .3, col[2] * .3, col[3] * .3 }, { col[1] * 1.4, col[2] * 1.4, col[3] * 1.4 }, 0.5, 0) end
    local c = cam:get_position()
    local k = (c.z - D.z) / c.z
    local ax, ay = c.x + (WX(x0) - c.x) * k, c.y + (WY(y0) - c.y) * k
    local bx, by = c.x + (WX(x1) - c.x) * k, c.y + (WY(y1) - c.y) * k
    local dx, dy = bx - ax, by - ay
    local L = sqrt(dx * dx + dy * dy)
    b.n:set_position(V((ax + bx) * .5, (ay + by) * .5, D.z))
    b.n:set_rotation(V(0, 0, math.deg(atan2(dy, dx))))
    b.n:set_scale(V(L + D.w, D.w, D.w))
end
function G.dbg_box(x0, y0, x1, y1, col)
    G.dbg_bar(x0, y0, x1, y0, col); G.dbg_bar(x1, y0, x1, y1, col); G.dbg_bar(x1, y1, x0, y1, col); G.dbg_bar(x0, y1, x0, y0, col)
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and ST and (G.state == "play" or G.state == "pause" or G.state == "title") then
        local C = G.DBG_COL
        for _, g in ipairs(ST.girders) do
            for i, y in ipairs(g.ys) do
                local a, b = g.x0 + (i - 1) * g.sw, g.x0 + i * g.sw
                local x = a
                if g.holes then for _, h in ipairs(g.holes) do if h.open and h.a >= a and h.b <= b + 0.1 then G.dbg_bar(a, y, h.a, y, C.floor); x = h.b end end end
                if x < b then G.dbg_bar(x, y, b, y, C.floor) end
            end
        end
        for _, l in ipairs(ST.ladders) do G.dbg_box(l.x - 3, ladder_limit(l), l.x + 3, l.ylo, C.ladder) end
        if ST.plats then for _, p in ipairs(ST.plats) do if p.live then G.dbg_bar(p.x - 8, p.y, p.x + 8, p.y, C.plat) end end end
        if M.st ~= "hidden" then local a, b, c, d = mario_box(); G.dbg_box(a, b, c, d, C.mario) end
        local hx0, hy0, hx1, hy1 = hammer_box(); if hx0 then G.dbg_box(hx0, hy0, hx1, hy1, C.hammer) end
        for _, list in ipairs({ B, F, PIES, SPR }) do for _, e in ipairs(list) do local a, b, c, d = ent_box(e); G.dbg_box(a, b, c, d, C.enemy) end end
        local kh = HB.kong
        G.dbg_box(KONG.x - kh[1], KONG.y - kh[2], KONG.x + kh[1], KONG.y, C.enemy)
        if ST.fire then G.dbg_box(ST.fire.x - 8, ST.fire.y - 22, ST.fire.x + 8, ST.fire.y, C.enemy) end
        for _, h in ipairs(ST.hammer_props) do if h.live then G.dbg_box(h.x - 5, h.y - 6, h.x + 5, h.y + 6, C.hammer) end end
        for _, it in ipairs(ST.items) do if it.live then G.dbg_box(it.x - 6, it.y - 10, it.x + 6, it.y, C.item) end end
    end
    for i = D.used + 1, #D.pool do local b = D.pool[i]; if not b.hidden_ then b.n:set_position(HIDE) end end
end
------------------------------------------------------------------ stage order (US arcade) + flow
local SEQS = { { "25", "100" }, { "25", "75", "100" }, { "25", "50", "75", "100" }, { "25", "50", "25", "75", "100" }, { "25", "50", "25", "75", "25", "100" } }
local function seq() return SEQS[min(G.level, 5)] end
G.seq_i = 1
local function start_stage(kind)
    clear_ents()
    build_stage(kind)
    G.cut = nil; G.cam_ov = nil; G.kong_hidden = false; G.paul_hidden = false; G.stack_hidden = false; G.attract = false
    for _, h in ipairs(RIGS.hh) do h.root:set_position(HIDE) end
    for _, n in ipairs(G.hh_g) do n:set_position(HIDE) end
    set_point(LT.hh, HIDE, V(1, 1, 1), 0, 1)
    KONG.x, KONG.y = ST.dk.x, ST.dk.y; KONG.ox, KONG.oy = KONG.x, KONG.y; KONG.st = ST.dk.patrol and "walk" or "idle"; KONG.t = 90; KONG.dir = 1; KONG.throws = 0; KONG.yaw_ov = nil
    PAUL.x, PAUL.y = ST.pauline.x, ST.pauline.y; PAUL.carried = nil; PAUL.yaw = nil; PAUL.help = 0; PAUL.t = 0; PAUL.z = nil
    mario_reset(ST.mario)
    G.bonus = min(8000, 4000 + 1000 * G.level); G.bonus_f = 0; G.stage_f = 0; G.first_done = false
    G.pie_t, G.fox_t = 60, (kind == "100") and 60 or 240
    ST.rivets_left = #ST.rivets
    RIGS.heart:set_position(HIDE); RIGS.heart_l:set_position(HIDE); RIGS.heart_r:set_position(HIDE)
    music(ST.music)
    G.state = "play"
end
G.start_stage = start_stage

-- "How high can you get?" : Kong statues stacked for every 25 m reached
local HHX = 140
local function how_high(kind)
    G.state = "howhigh"; G.hh_t = 0; G.hh_kind = kind; G.hh_n = tonumber(kind) / 25
    music(nil); sfx("howhigh")
    set_point(LT.hh, V(HHX + 4, -9 + (G.hh_n - 1) * 2.8 + 4, 14), V(1, .92, .85), 120, 40)
    for i, r in ipairs(RIGS.hh) do
        if i <= G.hh_n then pose_dk(r, { pos = V(HHX, -9 + (i - 1) * 5.6, 0), s = 1, alz = -25, arz = 25, alx = -10, arx = -10 }) else r.root:set_position(HIDE) end
    end
    for i, n in ipairs(G.hh_g) do
        local lv = floor((i - 1) / 3) + 1
        if lv <= G.hh_n then n:set_position(V(HHX - 2 + ((i - 1) % 3) * 2, -9 + (lv - 1) * 5.6, 0)) else n:set_position(HIDE) end
    end
end
local function next_stage()
    G.seq_i = G.seq_i + 1
    if G.seq_i > #seq() then G.level = G.level + 1; G.seq_i = 1 end
    how_high(seq()[G.seq_i])
end

------------------------------------------------------------------ cutscenes
local function cut_bend(dt)
    local c = G.cut
    if not c or not c.bends then return end
    for gi, t0 in pairs(c.bends) do
        local k = clamp((c.t - t0) / 0.32, 0, 1)
        local b = k + sin(k * PI) * 0.35 * (1 - k * 0.5)
        if k >= 1 then b = 1; c.bends[gi] = nil end
        G.bend(gi, b)
    end
    G.refresh_ladders()
end
local function intro_start()
    clear_ents()
    build_stage("25")
    G.state = "intro"; G.attract = false
    G.cut = { kind = "intro", t = 0, hop = 0, bends = {} }
    M.st = "hidden"
    G.kong_hidden = false; G.paul_hidden = false; G.stack_hidden = true
    for _, l in ipairs(ST.ladders) do l.hidden = true end
    for _, d in ipairs(ST.deco_ladders) do d.hidden = true end
    G.bend_all(0)
    KONG.x, KONG.y = 112, 248; KONG.ox, KONG.oy = 112, 248; KONG.st = "climb"; KONG.yaw_ov = nil
    PAUL.x, PAUL.y = 112, 56; PAUL.help = 0
    P_begin("rung_i"); for i, n in ipairs(G.intro_lad) do G.lad_seg(n, 104 + (i - 1) * 16, 248, 56, -0.3, "rung_i") end; P_end("rung_i")
    music(nil); sfx("intro")
end
G.intro_start = intro_start
local HOPS = { 112, 100, 88, 76, 64, 54, 44 }
local function intro_update(dt)
    local c = G.cut
    c.t = c.t + dt
    local t = c.t
    if t < 5.5 then
        KONG.st = "climb"; KONG.y = lerp(248, 84, t / 5.5); KONG.x = 112
        PAUL.carried = V(WX(112) + 1.0, WY(KONG.y) + 3.9, 0.7)
    elseif t < 6.4 then
        KONG.y = 84; KONG.st = "idle"; KONG.yaw_ov = 180
        if t > 5.75 then PAUL.carried = nil; PAUL.help = 1 end
    elseif t < 7.0 then
        KONG.yaw_ov = nil
        local k = (t - 6.4) / 0.6
        P_begin("rung_i")
        for i, n in ipairs(G.intro_lad) do G.lad_seg(n, 104 + (i - 1) * 16, lerp(248, 56, k), 56, -0.3, "rung_i") end
        P_end("rung_i")
    else
        for _, n in ipairs(G.intro_lad) do n:set_position(HIDE) end; P_begin("rung_i"); P_end("rung_i")
        PAUL.help = 0
        local ht = 0.62
        local i = floor((t - 7.0) / ht) + 1
        if i <= 6 then
            local u = ((t - 7.0) % ht) / ht
            KONG.st = "hop"; KONG.x = lerp(HOPS[i], HOPS[i + 1], u); KONG.y = 84 - 16 * sin(PI * u)
            if c.hop < i - 1 or (c.hop < i and u > 0.97) then end
            if c.hop < i and u > 0.92 then
                c.hop = i
                local gi = ({ 6, 5, 4, 3, 2, 1 })[i]
                c.bends[gi] = t
                sfx("stomp"); G.shake = 0.7
                local g = ST.girders[gi]
                for x = g.x0 + 8, gx1(g) - 8, 40 do dust(x, surf(g, x), 5) end
            end
        else
            KONG.x, KONG.y = 44, 84
            KONG.st = "grin"
            if not c.lad then
                c.lad = true
                for _, l in ipairs(ST.ladders) do l.hidden = false end
                for _, d in ipairs(ST.deco_ladders) do d.hidden = false end
                G.refresh_ladders()
            end
            if t > 7.0 + 6 * ht + 1.6 then
                G.cut = nil; G.stack_hidden = false; KONG.st = "idle"
                G.seq_i = 1
                how_high(seq()[1])
                return
            end
        end
    end
    KONG.ox, KONG.oy = KONG.x, KONG.y
    cut_bend(dt)
end
local function clear_start()
    clear_ents()
    music(nil); sfx("clear")
    G.state = "clear"
    G.cut = { kind = ST.kind == "100" and "end100" or "clear", t = 0, bonus_done = false }
    M.ham = 0; M.st = "win"
    if ST.kind == "100" then
        G.cut.segs = {}
        for gi = 2, 5 do
            local g = ST.girders[gi]
            for i, n in ipairs(g.nodes) do
                local cx = g.x0 + g.sw * (i - 0.5)
                if cx > 56 and cx < 168 then G.cut.segs[#G.cut.segs + 1] = { n = n, x = WX(cx), y = WY(g.ys[i]), vy = 0, r = rr(-60, 60), d = rr(0, 0.25) } end
            end
        end
        for _, l in ipairs(ST.ladders) do l.hidden = true end
        G.refresh_ladders()
    end
end
G.clear_start = clear_start
local function heart_at(px, py, s)
    RIGS.heart:set_position(V(WX(px), WY(py), 0.4)); RIGS.heart:set_scale(V(s, s, s)); RIGS.heart:set_rotation(V(0, 15 * sin(G.t * 3), 0))
end
local function clear_update(dt)
    local c = G.cut
    c.t = c.t + dt
    local t = c.t
    local hx = (M.x + PAUL.x) / 2
    if not c.bonus_done and t > 0.8 then
        c.bonus_done = true; add_score(G.bonus); G.banner = { text = "Bonus " .. G.bonus, t = 2.4 }; sfx("bonus")
    end
    if c.kind == "clear" then
        PAUL.yaw = (M.x < PAUL.x) and -45 or 45
        if t < 1.5 then
            heart_at(hx, PAUL.y - 26, min(1, t * 3) * (1 + 0.08 * sin(t * 10)))
        elseif t < 2.0 then
            -- Kong snatches Pauline; the heart breaks
            RIGS.heart:set_position(HIDE)
            local k = (t - 1.5) / 0.5
            RIGS.heart_l:set_position(V(WX(hx) - k * 1.2, WY(PAUL.y - 26) - k * k * 3, 0.4)); RIGS.heart_l:set_rotation(V(0, 0, 25 * k))
            RIGS.heart_r:set_position(V(WX(hx) + k * 1.2, WY(PAUL.y - 26) - k * k * 3, 0.4)); RIGS.heart_r:set_rotation(V(0, 0, -25 * k))
            if not c.snatch then c.snatch = true; sfx("beat") end
        else
            RIGS.heart_l:set_position(HIDE); RIGS.heart_r:set_position(HIDE)
            local kx = ST.kind == "25" and 72 or KONG.x
            if not c.kx0 then c.kx0 = KONG.x; c.ky0 = KONG.y end
            local k = clamp((t - 2.0) / 0.6, 0, 1)
            KONG.x = lerp(c.kx0, kx, k)
            if k >= 1 then KONG.st = "climb"; KONG.y = c.ky0 - (t - 2.6) * 34 else KONG.st = "walk"; KONG.dir = kx > c.kx0 and 1 or -1 end
            PAUL.carried = V(WX(KONG.x) + 1.0, WY(KONG.y) + 3.9, 0.7)
        end
        if t > 5.2 then next_stage() end
    else
        -- 100m: Kong roars, the middle of the tower collapses, he falls head first; Mario and Pauline meet on top
        PAUL.yaw = -45
        if t < 1.0 then KONG.st = "beat"; G.shake = 0.4
        else
            if not c.fall then c.fall = true; c.ky = KONG.y; c.kvy = 0; KONG.st = "fall"; sfx("fall") end
            for _, s in ipairs(c.segs) do
                if t > 1.0 + s.d then
                    s.vy = s.vy + dt * 30; s.y = s.y - s.vy * dt
                    s.n:set_position(V(s.x, s.y, 0)); s.n:set_rotation(V(0, 0, s.r * (t - 1.0)))
                    if s.y < -30 then s.n:set_position(HIDE) end
                end
            end
            if KONG.st == "fall" then
                c.kvy = c.kvy + dt * 150; KONG.y = KONG.y + c.kvy * dt
                if KONG.y >= 248 then KONG.y = 248; KONG.st = "dazed"; sfx("stomp"); G.shake = 1; dust(KONG.x - 12, 248, 12); dust(KONG.x + 12, 248, 12) end
            end
            if t > 1.4 and not c.top then c.top = true; M.x, M.y, M.g = 100, 48, 6; M.ox, M.oy = M.x, M.y; M.face = 1; PAUL.x = 124 end
            if t > 3.0 then heart_at(112, 22, min(1, (t - 3.0) * 3) * (1 + 0.08 * sin(t * 10))) end
        end
        if t > 7.5 then next_stage() end
    end
    KONG.ox, KONG.oy = KONG.x, KONG.y
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
    quad(id, { x = x, y = y, w = w, h = h, z = 4, style = "text", label = "", fill = { 0.03, 0.03, 0.05, a or 0.55 },
        border = border or { 0.95, 0.35, 0.3, 0.55 }, corner_radius = 12 * US, no_input = true, visible = vis ~= false })
end
local function button(id, label, cx, cy, vis)
    local w, h = 340 * US, 60 * US
    local st = vis and select(2, pcall(runtime_ui.get_state, UI, id))
    local hov = type(st) == "table" and st.hovered
    quad(id, { x = cx - w / 2, y = cy - h / 2, w = w, h = h, z = 12, style = "text", label = label,
        fill = hov and { 0.45, 0.1, 0.08, 0.92 } or { 0.08, 0.05, 0.06, 0.88 }, border = hov and { 1, 0.6, 0.45, 1 } or { 0.85, 0.35, 0.3, 0.9 },
        text_color = hov and { 1, 0.95, 0.85, 1 } or { 0.95, 0.9, 0.85, 1 }, font_scale = 1.25 * US, align_h = "center", align_v = "middle",
        corner_radius = 12 * US, visible = vis })
    return vis and type(st) == "table" and st.clicked
end
local function pad6(n) local s = tostring(floor(n)); return string.rep("0", max(0, 6 - #s)) .. s end
local RED, WHITE, CYAN, DIM, GOLD = { 1, .3, .25, 1 }, { 1, 1, 1, 1 }, { .45, .9, 1, 1 }, { .78, .76, .74, 1 }, { 1, .85, .45, 1 }
G.banner = { text = "", t = 0 }
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause" or st == "over" or st == "clear" or st == "howhigh" or st == "intro") and not G.set_open
    local lx = to_screen(0, 0)
    local rx = to_screen(224, 0)
    local lw = lx - 60 * US
    -- left: scores
    panel("hl", 30 * US, 40 * US, lw, 230 * US, play, 0.45)
    text("h1", "1UP", 50 * US, 50 * US, lw - 40 * US, 44 * US, 1.4, RED, "left", play)
    text("h1s", pad6(G.score), 50 * US, 92 * US, lw - 40 * US, 56 * US, 2.0, WHITE, "left", play)
    text("hh", "HIGH SCORE", 50 * US, 156 * US, lw - 40 * US, 40 * US, 1.1, RED, "left", play)
    text("hhs", pad6(max(G.hiscore, G.score)), 50 * US, 196 * US, lw - 40 * US, 52 * US, 1.7, WHITE, "left", play)
    -- right: level, bonus, lives, height
    local rw = SW - rx - 60 * US
    local rx0 = rx + 30 * US
    panel("hr", rx0, 40 * US, rw, 330 * US, play, 0.45)
    text("lv", string.format("L=%02d", G.level), rx0 + 20 * US, 50 * US, rw - 40 * US, 46 * US, 1.5, CYAN, "left", play)
    text("ht", ST and ST.height or "", rx0 + 20 * US, 50 * US, rw - 40 * US, 46 * US, 1.5, GOLD, "right", play)
    quad("bbox", { x = rx0 + 20 * US, y = 110 * US, w = rw - 40 * US, h = 110 * US, z = 6, style = "text", label = "", fill = { 0.02, 0.03, 0.1, 0.7 },
        border = { 0.3, 0.55, 1, 0.9 }, corner_radius = 8 * US, no_input = true, visible = play })
    text("bt", "BONUS", rx0 + 20 * US, 116 * US, rw - 40 * US, 36 * US, 1.0, CYAN, "center", play)
    local bcol = (G.bonus or 0) <= 1000 and (floor(G.t * 4) % 2 == 0 and RED or WHITE) or WHITE
    text("bv", tostring(G.bonus or 0), rx0 + 20 * US, 152 * US, rw - 40 * US, 60 * US, 2.2, bcol, "center", play)
    text("lvs", "Lives", rx0 + 20 * US, 236 * US, rw - 40 * US, 36 * US, 1.0, DIM, "left", play)
    for i = 1, 8 do
        quad("life" .. i, { x = rx0 + 24 * US + (i - 1) * 34 * US, y = 280 * US, w = 24 * US, h = 24 * US, z = 7, style = "text", label = "",
            fill = { 0.9, 0.12, 0.08, 0.95 }, border = { 1, 0.85, 0.7, 1 }, corner_radius = 12 * US, no_input = true, visible = play and i <= G.lives - ((st == "play" and M.st ~= "dead") and 1 or 0) })
    end
    local ham = play and st == "play" and M.ham > 0
    quad("hambar", { x = rx0 + 20 * US, y = 326 * US, w = (rw - 40 * US) * clamp(M.ham / 600, 0, 1), h = 12 * US, z = 7, style = "text", label = "",
        fill = { 1, 0.6, 0.2, 0.9 }, border = NONE, corner_radius = 6 * US, no_input = true, visible = ham })
    -- Pauline's "HELP!"
    local help = (st == "play" or st == "title" or st == "intro") and not G.set_open and PAUL.help > 0 and not G.paul_hidden and not PAUL.carried
    local hx, hy = to_screen(PAUL.x + 22, PAUL.y - 20)
    text("help", "HELP!", hx - 80 * US, hy - 20 * US, 160 * US, 40 * US, 1.2, { 1, .55, .75, 1 }, "center", help)
    -- score popups
    for i, p in ipairs(G.POP) do
        p.t = p.t + dt
        local vis = (st == "play" or st == "clear") and not G.set_open and p.t < 1.0
        local px, py = 0, 0
        if vis then px, py = to_screen(p.x, p.y - p.t * 10) end
        local a = floor(clamp((1.0 - p.t) / 0.3, 0, 1) * 10) / 10
        text("pop" .. i, p.txt or "", px - 100 * US, py - 18 * US, 200 * US, 36 * US, 1.1, { p.col[1] or 1, p.col[2] or 1, p.col[3] or 1, a }, "center", vis)
    end
    G.banner.t = G.banner.t - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    text("ban", G.banner.text, 0, SH * 0.42, SW, 80 * US, 2.4, { 1, .9, .6, ba }, "center", (st == "play" or st == "clear") and not G.set_open and G.banner.t > 0)
    -- how high
    local hh = st == "howhigh" and not G.set_open
    text("hh_t", "How High Can You Get?", 0, SH * 0.84, SW, 80 * US, 2.4, WHITE, "center", hh)
    for i = 1, 4 do
        local vis = hh and i <= (G.hh_n or 0)
        local sx, sy = SW / 2 + 300 * US, 0
        if vis then
            local hh_half = 30 * math.tan(VFOV / 2)
            sy = SH / 2 - ((-9 + (i - 1) * 5.6 + 1.8) - (-9 + ((G.hh_n or 1) - 1) * 2.8 + 1.5)) / hh_half * SH / 2
        end
        text("hh_m" .. i, (i * 25) .. " m", sx - 100 * US, sy - 25 * US, 200 * US, 50 * US, 1.8, i == (G.hh_n or 0) and GOLD or DIM, "left", vis)
    end
    text("skip", "Enter / Space / Click: skip", 0, SH - 60 * US, SW, 36 * US, 0.9, DIM, "center", (st == "intro") and not G.set_open)
    -- title
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 480 * US, SH * 0.08, 960 * US, SH * 0.8, title, 0.62)
    text("t_title", "Donkey Kong Remix", 0, SH * 0.1, SW, 130 * US, 4.4, { 1, .4, .3, 1 }, "center", title)
    text("t_sub", "Climb the girders, dodge the barrels and rescue Pauline", 0, SH * 0.1 + 118 * US, SW, 40 * US, 1.15, DIM, "center", title)
    text("t_ctl1", "A / D or Left / Right: walk   ·   W / S or Up / Down: climb ladders", 0, SH * 0.66, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_ctl2", "Space / Z / J: jump   ·   Grab a hammer to smash barrels and fireballs", 0, SH * 0.66 + 34 * US, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_ctl3", "P / Esc: pause   ·   O: settings   ·   M: mute   ·   F3: colliders   ·   Mouse: click any button", 0, SH * 0.66 + 68 * US, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_hi", "High score " .. pad6(G.hiscore), 0, SH * 0.66 + 112 * US, SW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.28, 600 * US, SH * 0.44, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.3, SW, 80 * US, 2.6, { 1, .45, .35, 1 }, "center", pause)
    local over = st == "over" and not G.set_open
    panel("o_bg", SW / 2 - 360 * US, SH * 0.26, 720 * US, SH * 0.5, over, 0.78)
    text("o_t", "Game Over", 0, SH * 0.28, SW, 90 * US, 3.0, { 1, .4, .3, 1 }, "center", over)
    text("o_s", "Score " .. pad6(G.score) .. "  ·  L=" .. string.format("%02d", G.level), 0, SH * 0.28 + 90 * US, SW, 40 * US, 1.3, DIM, "center", over)
    local c = {}
    c.start = button("b_start", "Start (Enter)", SW / 2, SH * 0.4, title)
    c.set_t = button("b_set_t", "Settings (O)", SW / 2, SH * 0.4 + 76 * US, title)
    c.quit_app = button("b_quit_app", "Quit Game", SW / 2, SH * 0.4 + 152 * US, title)
    c.resume = button("b_resume", "Resume (P)", SW / 2, SH * 0.44, pause)
    c.set_p = button("b_set_p", "Settings (O)", SW / 2, SH * 0.44 + 76 * US, pause)
    c.quit = button("b_quit", "Quit to Title (Q)", SW / 2, SH * 0.44 + 152 * US, pause)
    local ov = over and (G.over_t or 0) > 1.2
    c.again = button("b_again", "Play Again (Enter)", SW / 2, SH * 0.5, ov)
    c.title = button("b_title", "Title (Esc)", SW / 2, SH * 0.5 + 76 * US, ov)
    return c
end

------------------------------------------------------------------ main loop
local function to_title()
    clear_ents()
    build_stage("25")
    G.state = "title"; G.attract = true; G.cut = nil; G.cam_ov = nil
    G.kong_hidden, G.paul_hidden, G.stack_hidden = false, false, false
    for _, h in ipairs(RIGS.hh) do h.root:set_position(HIDE) end
    KONG.x, KONG.y = 44, 84; KONG.st = "idle"; KONG.t = 60; KONG.throws = 0
    PAUL.x, PAUL.y = 112, 56; PAUL.carried = nil; PAUL.yaw = nil
    G.first_done = true
    M.st = "hidden"; M.ham = 0; M.x = -100; M.y = 400
    music(nil)
end
G.to_title = to_title
local function new_game()
    G.score, G.lives, G.level, G.seq_i = 0, 3, 1, 1; G.bonus = 5000
    intro_start()
end
G.new_game = new_game
local acc = 0
G.jump_q = false
local function update(dt)
    flush_mats()
    dt = min(dt, 0.1)
    G.t = G.t + dt; G.dt = dt
    local k = { ret = edge("Return"), space = edge("Space"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), q = edge("Q"),
        z = edge("Z"), j = edge("J"), f3 = edge("F3") }
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    local md = false
    pcall(function() md = input.is_left_mouse_down() and true or false end)
    local mouse_click = md and not G.mouse_prev; G.mouse_prev = md
    if st == "title" then
        if k.ret or k.space or c.start then sfx("click"); new_game()
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "intro" then
        if (k.ret or k.space or k.z or (mouse_click and not G.set_open)) and G.cut and G.cut.t > 0.3 then
            G.cut = nil; G.bend_all(1); for _, l in ipairs(ST.ladders) do l.hidden = false end; for _, d in ipairs(ST.deco_ladders) do d.hidden = false end
            G.refresh_ladders(); for _, n in ipairs(G.intro_lad) do n:set_position(HIDE) end; P_begin("rung_i"); P_end("rung_i")
            G.seq_i = 1; how_high(seq()[1])
        end
        if k.esc then to_title() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click") end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.q or c.quit then to_title() end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then sfx("click"); new_game()
            elseif k.esc or c.title then to_title() end
        end
    elseif st == "howhigh" then
        G.hh_t = G.hh_t + dt
        G.cam_ov = { HHX, -9 + (G.hh_n - 1) * 2.8 + 1.5, 30, HHX, -9 + (G.hh_n - 1) * 2.8 + 1.5, 0 }
        if G.hh_t > 2.8 or ((k.ret or k.space) and G.hh_t > 0.4) then start_stage(G.hh_kind) end
    end
    st = G.state
    -- Pauline calls for help now and then
    PAUL.t = PAUL.t + dt
    if PAUL.help > 0 then PAUL.help = PAUL.help - dt elseif PAUL.t > 4.2 and (st == "play" or st == "title") then PAUL.t = 0; PAUL.help = 1.6 end
    if st == "intro" and G.cut then intro_update(dt) end
    if st == "clear" and G.cut then clear_update(dt) end
    local running = (st == "play" or st == "title") and not (G.set_open and st ~= "title") and not G.freeze
    if running then
        if (k.space or k.z or k.j) and st == "play" then G.jump_q = true end
        local inp = { h = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0), v = (any("Down", "S") and 1 or 0) - (any("Up", "W") and 1 or 0), jump = false }
        if st ~= "play" then inp.h, inp.v = 0, 0 end
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 6 do
            inp.jump = G.jump_q; G.jump_q = false
            stage_step(inp)
            acc = acc - FR; n = n + 1
            if G.state ~= st then break end
            if st == "play" and M.st ~= "dead" and ST.goal(M) and M.st == "walk" then clear_start(); break end
            if st == "play" and ST.kind == "100" and ST.rivets_left <= 0 and M.st ~= "dead" then clear_start(); break end
        end
        if acc > FR * 6 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if st == "play" and M.st == "dead" and M.dead_f >= 160 then
            G.lives = G.lives - 1
            if G.lives <= 0 then
                G.state = "over"; G.over_t = 0
                if G.score > G.hiscore then G.hiscore = G.score; save_hi() end
            else start_stage(ST.kind) end
        end
    else AL = 1 end
    if G.score > G.hiscore and st == "over" then G.hiscore = G.score; save_hi() end
    if st ~= "howhigh" then G.cam_ov = G.cam_ov_fixed end
    update_camera(dt)
    render_stage(dt)
    render_ents(dt)
    render_mario(dt)
    render_kong(dt)
    render_pauline(dt)
    update_flashes(dt)
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_backdrop()
build_rigs()
build_fx()
G.hh_g = {}
for i = 1, 12 do G.hh_g[i] = clone("g_red") end
to_title()
G.update = update; G.SET = SET; G.WX, G.WY = WX, WY; G.surf = surf; G.build_stage = build_stage; G.how_high = how_high
G.state_set = function(s) G.state = s; G.over_t = 5 end
hooks { update = update }
pe_log("[DK] ready")
