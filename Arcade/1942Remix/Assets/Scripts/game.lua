-- 1942 REMIX  (PhasmaEngine, Lua)
-- A faithful modern remake of Capcom's 1942 (1984): fly the P-38 "Super Ace" from Midway (stage 32) to Tokyo (stage 1).
-- Twin guns (one volley per press), three evasive loops per stage, red formations that drop POW power-ups, medium and
-- heavy bombers, take-off and landing on the carrier, and a shoot-down bonus after every stage.
-- Field space: x right (-12..12), y up the screen (0..30); planes fly at altitude ALT. World: X = -x, Y = altitude, Z = y.
local PI = math.pi
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
math.randomseed(os and os.time and os.time() or 1942)
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local G = { state = "boot", t = 0 }
_G.AF = G

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
local ss = scene.add_empty_node("A1942SceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "day.hdr")
S("hdr", false); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false); S("dof", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.2)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", false)
S("color_grading", true); S("color_grading_saturation", 1.05); S("color_grading_contrast", 1.04)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "SETTINGS", subtitle = "1942 Remix", file = "Save/settings.cfg", music = true,
    click = function() sfx("click") end, defaults = { master = 0.5 },
    theme = { accent = { 0.35, 0.75, 1, 1 }, accent2 = { 1, 0.55, 0.3, 1 }, text = { 0.86, 0.84, 0.8, 1 }, selected_text = { 1, 0.97, 0.9, 1 } } })
SET:apply()
G.set_open = false

------------------------------------------------------------------ camera
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1600, surf.height or 900
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local VFOV = math.rad(44)
local FOVX = 2 * math.atan(math.tan(VFOV / 2) * SW / SH)
pcall(function() cam:set_fov(math.deg(FOVX)) end)
pcall(function() cam:set_far_plane(400) end)
local FW, FH, ALT = 24, 30, 5.0
G.FW, G.FH, G.ALT = FW, FH, ALT
G.cam = { pos = vec3(0, 37, FH / 2 - 7.5), look = vec3(0, 0, FH / 2 + 0.2) }
local function WP(x, y, h) return vec3(-x, h or ALT, y) end
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
    if not n then pe_log("[AF] missing template " .. name); return nil end
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
G.vk = {}
local prev = {}
local keyfn = input.is_key_down_raw or input.is_key_pressed
local function held(k) if G.vk and G.vk[k] then return true end local ok, v = pcall(keyfn, k); return ok and v end
local function edge(k) local d = held(k); local p = prev[k]; prev[k] = d; return d and not p end
local function any(...) for _, k in ipairs({ ... }) do if held(k) then return true end end; return false end
local function arm_edge(k)
    prev[k] = false
end

local FR = 1 / 60
local AL = 1
------------------------------------------------------------------ palette {base, emissive, rough, metal}
local PAL = {
    p38_body = { { .78, .8, .82 }, { .03, .03, .03 }, .35, .3 }, p38_fin = { { .78, .8, .82 }, { .03, .03, .03 }, .35, .3 },
    p38_glass = { { .2, .28, .35 }, { 0, 0, 0 }, .05, .6 }, p38_mark = { { .1, .2, .5 }, { 0, 0, 0 }, .5 }, p38_prop = { { .12, .12, .12 }, { 0, 0, 0 }, .5, .3 },
    zero_body = { { .62, .66, .55 }, { .005, .005, .005 }, .45, .2 }, red_body = { { .78, .12, .1 }, { .02, 0, 0 }, .4, .2 },
    zero_cowl = { { .12, .12, .13 }, { 0, 0, 0 }, .4, .5 }, zero_glass = { { .2, .28, .35 }, { 0, 0, 0 }, .05, .6 },
    zero_mark = { { .85, .1, .08 }, { .03, 0, 0 }, .5 }, zero_prop = { { .15, .13, .1 }, { 0, 0, 0 }, .5 },
    mid_body = { { .26, .34, .22 }, { 0, 0, 0 }, .55, .2 }, mid_glass = { { .2, .28, .35 }, { 0, 0, 0 }, .05, .6 }, mid_prop = { { .15, .13, .1 }, { 0, 0, 0 }, .5 },
    big_body = { { .3, .36, .26 }, { 0, 0, 0 }, .55, .25 }, big_glass = { { .2, .28, .35 }, { 0, 0, 0 }, .05, .6 }, big_prop = { { .15, .13, .1 }, { 0, 0, 0 }, .5 },
    shot = { { 1, .86, .35 }, { 1.5, 1.05, .22 }, .3 }, ebul = { { 1, .45, .2 }, { .8, .25, .06 }, .3 },
    ebul_core = { { 1, .3, .62 }, { 2.6, .22, 1.15 }, .2 }, ebul_star = { { .9, .06, .5 }, { 1.9, .04, .95 }, .3 },
    pow_red = { { 1, 1, 1 }, { .12, .12, .12 }, .4 }, pow_green = { { 1, 1, 1 }, { .12, .12, .12 }, .4 }, pow_white = { { 1, 1, 1 }, { .12, .12, .12 }, .4 },
    pow_gray = { { 1, 1, 1 }, { .12, .12, .12 }, .4 }, pow_yellow = { { 1, 1, 1 }, { .12, .12, .12 }, .4 }, pow_orange = { { 1, 1, 1 }, { .12, .12, .12 }, .4 },
    shadow = { { .02, .06, .1 }, { 0, 0, 0 }, 1 }, sh_p38 = { { .04, .13, .24 }, { 0, 0, 0 }, 1 }, sh_zero = { { .04, .13, .24 }, { 0, 0, 0 }, 1 }, sh_mid = { { .04, .13, .24 }, { 0, 0, 0 }, 1 }, sh_big = { { .04, .13, .24 }, { 0, 0, 0 }, 1 },
    carrier_hull = { { .4, .42, .44 }, { 0, 0, 0 }, .6, .4 }, carrier_deck = { { 1, 1, 1 }, { 0, 0, 0 }, .8 }, carrier_island = { { .5, .52, .54 }, { 0, 0, 0 }, .6, .4 },
    ocean = { { 1, 1, 1 }, { 0, 0, 0 }, .85, 0 },
    isl_reef0 = { { 1, 1, 1 }, { 0, 0, 0 }, .3 }, isl_reef1 = { { 1, 1, 1 }, { 0, 0, 0 }, .3 }, isl_reef2 = { { 1, 1, 1 }, { 0, 0, 0 }, .3 },
    isl_sand0 = { { 1, 1, 1 }, { 0, 0, 0 }, .9 }, isl_sand1 = { { 1, 1, 1 }, { 0, 0, 0 }, .9 }, isl_sand2 = { { 1, 1, 1 }, { 0, 0, 0 }, .9 },
    isl_jungle0 = { { 1, 1, 1 }, { 0, 0, 0 }, .85 }, isl_jungle1 = { { 1, 1, 1 }, { 0, 0, 0 }, .85 }, isl_jungle2 = { { 1, 1, 1 }, { 0, 0, 0 }, .85 },
    palm_trunk = { { .45, .34, .22 }, { 0, 0, 0 }, .85 }, palm_leaves = { { .2, .5, .18 }, { .004, .015, .004 }, .6 },
    cloud0 = { { .86, .88, .92 }, { .55, .56, .6 }, 1 }, cloud1 = { { .86, .88, .92 }, { .55, .56, .6 }, 1 }, cloud2 = { { .86, .88, .92 }, { .55, .56, .6 }, 1 },
    wreck = { { .2, .2, .2 }, { 0, 0, 0 }, .7 },
}
local function paint_templates()
    for name, v in pairs(PAL) do paint(tnode(name), v[1], v[2], v[3], v[4]) end
    mtex(tnode("ocean"), "base_color", "Textures/ocean.png")
    mtex(tnode("carrier_deck"), "base_color", "Textures/deck.png")
    for _, c in ipairs({ "red", "green", "white", "gray", "yellow", "orange" }) do mtex(tnode("pow_" .. c), "base_color", "Textures/pow_" .. c .. ".png") end
    for v = 0, 2 do
        mtex(tnode("isl_reef" .. v), "base_color", "Textures/reef.png"); mtex(tnode("isl_sand" .. v), "base_color", "Textures/sand.png")
        mtex(tnode("isl_jungle" .. v), "base_color", "Textures/jungle.png")
    end
    for name in pairs(PAL) do local n = tnode(name); if n then n:set_position(HIDE) end end
end

------------------------------------------------------------------ lights (sun from the upper left, soft fill)
local LT = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(-0.4, -0.85, -0.35), vec3(1.0, 0.97, 0.92), 2.0)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    LT.key = addp(vec3(6, 30, 10), vec3(1.0, 0.96, 0.9), 25, 70)
    LT.fill = addp(vec3(-8, 20, 24), vec3(0.8, 0.9, 1.0), 12, 60)
    LT.flash = {}
    for i = 1, 4 do LT.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1 } end
end
G.flash_next = 1
local function flash(p, col, power, life, rad)
    local f = LT.flash[G.flash_next]; G.flash_next = G.flash_next % #LT.flash + 1
    f.t, f.life, f.p, f.col, f.power, f.rad = 0, life or 0.3, p, vec3(col[1], col[2], col[3]), power or 40, rad or 7
end
local function update_lights(dt)
    for _, f in ipairs(LT.flash) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = 1 - clamp(f.t / f.life, 0, 1)
            set_point(f.idx, f.p, f.col, f.power * k * k, f.rad)
            if f.t >= f.life then set_point(f.idx, HIDE, f.col, 0, 1) end
        end
    end
end

------------------------------------------------------------------ particles (world coords)
local function PS() return SET:particle_scale() end
local function burst(p, o)
    pcall(particles.emit_burst, {
        position = p, velocity = o.vel or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = max(1, floor((o.count or 30) * PS())),
        size_min = o.smin or 0.05, size_max = o.smax or 0.14, life_min = o.lmin or 0.25, life_max = o.lmax or 0.7,
        spawn_radius = o.radius or 0.3, noise_strength = o.spread or 10, drag = o.drag or 2.0,
        gravity = o.grav or vec3(0, 0, 0), cleanup_delay = 3.0,
    })
end
local function explode(x, y, size, h)
    local p = WP(x, y, h)
    local s = size or 1
    burst(p, { c0 = vec4(1.9, 1.15, .4, 1), c1 = vec4(.9, .25, .05, 0), count = floor(18 * s), smin = .25 * s, smax = .6 * s, lmin = .2, lmax = .5,
        radius = .4 * s, spread = 6 * s, drag = 3, grav = vec3(0, 1, 0) })
    burst(p, { c0 = vec4(.3, .28, .26, .8), c1 = vec4(.15, .15, .15, 0), count = floor(10 * s), smin = .4 * s, smax = .9 * s, lmin = .6, lmax = 1.3,
        radius = .6 * s, spread = 2.5 * s, drag = 2, grav = vec3(0, 0.6, 0) })
    burst(p, { c0 = vec4(1.6, 1.3, .7, 1), c1 = vec4(.8, .3, .1, 0), count = floor(14 * s), smin = .06, smax = .14, lmin = .3, lmax = .8,
        radius = .2, spread = 16 * s, drag = 1.2, grav = vec3(0, -9, 0) })
    flash(vec3(p.x, p.y + 1.5, p.z), { 1, .7, .35 }, 60 * s, 0.35 + 0.1 * s, 6 + 3 * s)
end
local function puff(x, y, col, n, h)
    burst(WP(x, y, h), { c0 = vec4(col[1], col[2], col[3], 1), c1 = vec4(col[1] * .5, col[2] * .5, col[3] * .5, 0), count = n or 8,
        smin = .06, smax = .14, lmin = .15, lmax = .35, radius = .15, spread = 8, drag = 2 })
end
local function trail(x, y, h)
    burst(WP(x, y, h), { c0 = vec4(.25, .24, .22, .7), c1 = vec4(.15, .15, .15, 0), count = 2, smin = .3, smax = .55, lmin = .5, lmax = .9,
        radius = .2, spread = 1, drag = 1, grav = vec3(0, 0.5, 0) })
end

------------------------------------------------------------------ score state
G.score, G.hiscore = 0, 40000
pcall(function() local s = fs.read("Save/s1942_hiscore.txt"); if s then G.hiscore = max(40000, tonumber(s) or 0) end end)
local function save_hi() pcall(fs.write, "Save/s1942_hiscore.txt", tostring(G.hiscore)) end
G.next_extra = 20000
local function add_score(n)
    G.score = G.score + n
    if G.score >= G.next_extra then
        G.next_extra = (G.next_extra == 20000) and 80000 or (G.next_extra + 80000)
        G.lives = (G.lives or 0) + 1; sfx("extra"); G.banner_set("Extra Plane!", 1.6)
    end
end
G.banner = { text = "", t = 0 }
function G.banner_set(t, d) G.banner.text = t; G.banner.t = d or 1.5 end
------------------------------------------------------------------ stages: 32 (Midway) counting down to 1 (Tokyo)
local function stage_name(n)
    if n >= 29 then return "Midway" elseif n >= 25 then return "Marshall" elseif n >= 21 then return "Attu"
    elseif n >= 17 then return "Rabaul" elseif n >= 13 then return "Leyte" elseif n >= 9 then return "Saipan"
    elseif n >= 5 then return "Iwo Jima" elseif n >= 2 then return "Okinawa" end
    return "Tokyo"
end
local function is_boss(n) return n % 4 == 1 end            -- 29, 25, ... 5, 1: the Ayako heavy bomber
G.stage_name, G.is_boss = stage_name, is_boss
-- enemy kinds: radius list = collider circles {dx, dy, r} in field units (dy = along the nose)
local EK = {
    zero = { hp = 1, score = 50, circles = { { 0, 0.05, 0.55 }, { 0.62, 0.02, 0.3 }, { -0.62, 0.02, 0.3 } }, meshes = { "zero_body", "zero_cowl", "zero_glass", "zero_mark", "zero_prop" } },
    red  = { hp = 1, score = 100, circles = { { 0, 0.05, 0.55 }, { 0.62, 0.02, 0.3 }, { -0.62, 0.02, 0.3 } }, meshes = { "red_body", "zero_cowl", "zero_glass", "zero_mark", "zero_prop" } },
    mid  = { hp = 14, score = 1500, circles = { { 0, 0.1, 0.45 }, { 0, 1.0, 0.35 }, { 0, -1.0, 0.35 }, { 0.95, 0.3, 0.45 }, { -0.95, 0.3, 0.45 }, { 1.8, 0.1, 0.35 }, { -1.8, 0.1, 0.35 } },
             meshes = { "mid_body", "mid_glass", "mid_prop" } },
    big  = { hp = 150, score = 10000, circles = { { 0, 0.3, 0.75 }, { 0, 1.9, 0.6 }, { 0, -1.5, 0.6 }, { 1.6, 0.75, 0.55 }, { -1.6, 0.75, 0.55 }, { 3.0, 0.65, 0.5 }, { -3.0, 0.65, 0.5 },
             { 4.2, 0.25, 0.4 }, { -4.2, 0.25, 0.4 }, { 0, -2.75, 0.45 } }, meshes = { "big_body", "big_glass", "big_prop" } },
}
G.EK = EK
-- deterministic per-stage randomness (same waves every play, like the arcade)
local function lcg(seed) local s = seed % 2147483647; if s <= 0 then s = s + 2147483646 end
    return function(a, b) s = (s * 16807) % 2147483647; local u = (s - 1) / 2147483646; if a then return a + (b - a) * u end; return u end end
-- a wave spawns one or more planes: {t, kind, ai, x, y, h, v, extra...}
local function build_waves(k)                 -- k = 1 (stage 32) .. 32 (stage 1)
    local R = lcg(k * 7919 + 13)
    local W = {}
    local T = 56 + min(k, 16) * 1.25
    local t = 3.0
    local sp = 1 + min(k, 24) * 0.015
    local red_next, mid_next = 6 + R(0, 3), 14 + R(0, 4)
    local function add(o) W[#W + 1] = o end
    while t < T do
        if t >= red_next then
            local side = R() < 0.5 and -1 or 1
            local y0, A, f = R(17, 25), R(1.6, 2.4) * (R() < 0.5 and -1 or 1), R(1.2, 1.7)
            for i = 0, 4 do add({ t = t + i * 0.26, kind = "red", ai = "snake", x = side * 15, y = y0, h = -side * math.pi / 2, v = 9.5 * sp, A = A, f = f, grp = "r" .. k .. "_" .. floor(t) }) end
            red_next = t + R(9, 13); t = t + 2.4
        elseif k >= 2 and t >= mid_next then
            if R() < 0.6 then add({ t = t, kind = "mid", ai = "rise", x = R(-6, 6), y = -4, h = 0, v = 6.5 * sp })
            else add({ t = t, kind = "mid", ai = "sink", x = R(-7, 7), y = FH + 4, h = math.pi, v = 3.2 * sp }) end
            mid_next = t + R(15, 21) - min(k, 20) * 0.2; t = t + 2.2
        else
            local r = R()
            local nb = floor(2 + R(0, 1 + min(k, 20) * 0.08))
            if r < 0.28 then                                   -- dive at the player
                local x0 = R(-9, 9)
                for i = 0, nb - 1 do add({ t = t + i * 0.32, kind = "zero", ai = "dive", x = clamp(x0 + (i - nb / 2) * 2.1, -11, 11), y = FH + 2, h = math.pi, v = 10 * sp }) end
            elseif r < 0.5 then                                -- dive and loop
                local x0, dir = R(-7, 7), R() < 0.5 and -1 or 1
                for i = 0, nb - 1 do add({ t = t + i * 0.4, kind = "zero", ai = "loop", x = x0, y = FH + 2, h = math.pi, v = 9.5 * sp, ly = R(11, 16), dir = dir }) end
            elseif r < 0.68 then                               -- cross from a side, gently weaving
                local side, y0 = R() < 0.5 and -1 or 1, R(14, 26)
                for i = 0, nb do add({ t = t + i * 0.35, kind = "zero", ai = "cross", x = side * 15, y = y0, h = -side * math.pi / 2, v = 9 * sp }) end
            elseif r < 0.84 and k >= 2 then                    -- up from behind the player
                local x0 = R(-8, 8)
                for i = 0, nb - 1 do add({ t = t + i * 0.3, kind = "zero", ai = "behind", x = clamp(x0 + i * 1.8, -11, 11), y = -3, h = 0, v = 15 * sp }) end
            else                                               -- swoop across from a top corner
                local side = R() < 0.5 and -1 or 1
                for i = 0, nb - 1 do add({ t = t + i * 0.3, kind = "zero", ai = "swoop", x = side * 13, y = FH + 1, h = math.pi + side * 0.6, v = 10 * sp, w = -side * R(0.55, 0.8) }) end
            end
            t = t + R(1.5, 2.4) - min(k, 20) * 0.025
        end
    end
    return W, T
end
G.build_waves = build_waves
local POWSEQ = { "red", "green", "gray", "white", "yellow", "red", "orange", "green", "white", "gray", "yellow", "orange" }
G.POWSEQ = POWSEQ
------------------------------------------------------------------ simulation (fixed 60 Hz)
local PI2 = math.pi * 2
local SCROLL = 3.0
local P = { x = 0, y = 5, px = 0, py = 5, alive = true, inv = 0, roll = 0, rolls = 3, quad = false, esc = { false, false }, h = ALT, bank = 0 }
G.P = P
local SHOTS, BUL, EN, POWS = {}, {}, {}, {}
G.SHOTS, G.BUL, G.EN, G.POWS = SHOTS, BUL, EN, POWS
local ROLL_T = 1.6
G.ROLL_T = ROLL_T
local function inside(x, y, m) m = m or 0; return x > -FW / 2 - 6 - m and x < FW / 2 + 6 + m and y > -1 - m and y < FH + 1 + m end
local function esc_pos(i) return P.x + (i == 1 and -2.0 or 2.0), P.y - 0.4 end
G.esc_pos = esc_pos
local function circles(e)
    local hs, hc = sin(e.h), cos(e.h)
    local out = {}
    for i, c in ipairs(EK[e.kind].circles) do
        out[i] = { e.x + hc * c[1] + hs * c[2], e.y - hs * c[1] + hc * c[2], c[3] }
    end
    return out
end
G.circles = circles
------------------------------------------------------------------ spawning
local function spawn(w)
    local d = EK[w.kind]
    local e = { kind = w.kind, ai = w.ai, x = w.x, y = w.y, h = w.h, h0 = w.h, v = w.v, t = 0, hp = d.hp + (w.kind == "big" and G.k * 4 or 0),
        A = w.A, f = w.f, ly = w.ly, dir = w.dir, w = w.w, grp = w.grp, turn = 0, fired = 0, fire_t = rr(0.5, 1.8), entered = false, hit_t = 0 }
    EN[#EN + 1] = e
    if w.kind ~= "big" then G.spawned = G.spawned + 1 end
    if w.grp then G.groups[w.grp] = G.groups[w.grp] or { n = 0, k = 0 }; G.groups[w.grp].n = G.groups[w.grp].n + 1 end
    return e
end
local function fire_bullet(x, y, ang, v)
    if #BUL >= 70 or G.ceasefire > 0 then return end
    BUL[#BUL + 1] = { x = x, y = y, vx = sin(ang) * v, vy = cos(ang) * v }
end
local function aim(x, y) return math.atan2(P.x - x, P.y - y) end
------------------------------------------------------------------ enemy behaviour
local function enemy_ai(e, dt)
    local k = G.k
    e.t = e.t + dt
    local ai = e.ai
    if ai == "dive" then
        if e.y > P.y + 6 and P.alive then
            local want = clamp(aim(e.x, e.y), math.pi - 0.75, math.pi + 0.75)
            local dh = (want - e.h + math.pi) % PI2 - math.pi
            e.h = e.h + clamp(dh, -1.3 * dt, 1.3 * dt)
        end
    elseif ai == "loop" then
        if e.turn == 0 and e.y <= e.ly then e.turn = PI2 end
        if e.turn > 0 then local dh = e.v / 2.4 * dt; e.turn = max(0, e.turn - dh); e.h = e.h + e.dir * dh; if e.turn == 0 then e.turn = -1; e.h = math.pi end end
    elseif ai == "cross" then
        e.h = e.h0 + 0.35 * sin(e.t * 2.2)
    elseif ai == "swoop" then
        e.h = e.h + e.w * dt
    elseif ai == "snake" then
        e.h = e.h0 + e.A * 0.5 * sin(e.t * e.f)
    elseif ai == "rise" then
        if e.t < 11 then e.v = clamp((21 - e.y) * 0.9, 0.4, 6.5) else e.v = min(7, e.v + 3 * dt) end
        e.h = 0.15 * sin(e.t * 0.6)
    elseif ai == "sink" then
        e.h = math.pi + 0.12 * sin(e.t * 0.7)
    elseif ai == "boss" then
        if e.t < 40 then
            e.v = 0
            e.y = e.y + clamp((22 - e.y) * 0.7, -1, 3.5) * dt
            e.x = e.x + (6 * sin(e.t * 0.35) - e.x) * min(1, dt * 0.8)
            e.h = 0
        else e.v = min(9, e.v + 3 * dt) end
    end
    e.x = e.x + sin(e.h) * e.v * dt
    e.y = e.y + cos(e.h) * e.v * dt
    if ai == "boss" and e.t < 40 then e.h = 0 end
    if not e.entered and e.x > -FW / 2 - 1 and e.x < FW / 2 + 1 and e.y > 0 and e.y < FH then e.entered = true end
    -- fire
    e.fire_t = e.fire_t - dt
    if e.fire_t <= 0 and P.alive and e.y < FH - 0.5 and e.y > 1 and e.x > -FW / 2 and e.x < FW / 2 then
        local vb = 8.5 + k * 0.09
        if e.kind == "zero" or e.kind == "red" then
            local maxf = (k >= 12) and 2 or 1
            if e.fired < maxf and e.y > P.y + 3 and rand() < 0.35 + k * 0.02 then fire_bullet(e.x, e.y, aim(e.x, e.y), vb); e.fired = e.fired + 1 end
            e.fire_t = rr(0.9, 1.8)
        elseif e.kind == "mid" then
            local a = aim(e.x, e.y)
            for d = -1, 1 do fire_bullet(e.x, e.y - 0.6, a + d * 0.24, vb) end
            e.fire_t = max(0.9, 1.7 - k * 0.02)
        elseif e.kind == "big" then
            e.salvo = (e.salvo or 0) + 1
            local a = aim(e.x, e.y)
            if e.salvo % 2 == 1 then for d = -2, 2 do fire_bullet(e.x, e.y - 1.5, a + d * 0.2, vb) end
            else for _, sx in ipairs({ -3.0, 3.0 }) do local a2 = aim(e.x + sx, e.y + 0.6); for d = -1, 1 do fire_bullet(e.x + sx, e.y + 0.4, a2 + d * 0.25, vb * 0.9) end end end
            e.fire_t = max(0.7, 1.15 - k * 0.012)
        end
    end
end
------------------------------------------------------------------ hits
local function kill_enemy(e, by_player)
    e.dead = true
    local d = EK[e.kind]
    if by_player then
        add_score(d.score)
        if e.kind ~= "big" then G.killed = G.killed + 1 end
        if e.grp then
            local g = G.groups[e.grp]; g.k = g.k + 1
            if g.k >= 5 then
                G.pow_i = G.pow_i % #POWSEQ + 1
                POWS[#POWS + 1] = { x = clamp(e.x, -FW / 2 + 1, FW / 2 - 1), y = clamp(e.y, 4, FH - 2), c = POWSEQ[G.pow_i], t = 0 }
                G.banner_set("Formation Destroyed", 1.0)
            end
        end
    end
    if e.kind == "big" then
        sfx("boom_l"); G.shake = 1.4
        for i = 1, 6 do G.later(i * 0.18, function() explode(e.x + rr(-4, 4), e.y + rr(-2, 2), 2.2) end) end
        explode(e.x, e.y, 3)
        G.boss_done = true
    elseif e.kind == "mid" then sfx("boom_l"); explode(e.x, e.y, 2.0); G.shake = max(G.shake, 0.7)
    else sfx("boom_s"); explode(e.x, e.y, 1.0) end
end
G.kill_enemy = kill_enemy
local function damage(e, n)
    e.hp = e.hp - n; e.hit_t = 0.08
    if e.hp <= 0 then kill_enemy(e, true) else sfx("hit") end
end
local function player_die()
    if not P.alive then return end
    P.alive = false; P.dead_t = 2.4; P.quad = false; P.esc = { false, false }
    explode(P.x, P.y, 1.8); sfx("death"); G.shake = 1.0
    G.lives = G.lives - 1
end
G.player_die = player_die
local function lose_escort(i)
    P.esc[i] = false
    local x, y = esc_pos(i); explode(x, y, 1.0); sfx("boom_s")
end
local function seg_circle(x, y0, y1, c)
    local dx = x - c[1]
    if abs(dx) > c[3] then return false end
    local hh = sqrt(c[3] * c[3] - dx * dx)
    return max(y0, y1) >= c[2] - hh and min(y0, y1) <= c[2] + hh
end
------------------------------------------------------------------ player
local function fire_volley()
    local n = 0
    for _, s in ipairs(SHOTS) do if s.lead then n = n + 1 end end
    if n >= 3 then return end
    local xs = P.quad and { -0.62, -0.22, 0.22, 0.62 } or { -0.24, 0.24 }
    for i, dx in ipairs(xs) do SHOTS[#SHOTS + 1] = { x = P.x + dx, y = P.y + 0.7, py = P.y + 0.7, lead = (i == 1) } end
    for i = 1, 2 do if P.esc[i] then local ex, ey = esc_pos(i); SHOTS[#SHOTS + 1] = { x = ex, y = ey + 0.5, py = ey + 0.5 } end end
    sfx("shot")
end
local function player_step(inp, dt)
    P.px, P.py = P.x, P.y
    if not P.alive then
        P.dead_t = P.dead_t - dt
        if P.dead_t <= 0 then
            if G.lives < 0 then G.out_of_lives = true; return end
            P.alive = true; P.x, P.y = 0, 5; P.px, P.py = P.x, P.y; P.inv = 2.5; P.roll = 0
            for i = #BUL, 1, -1 do BUL[i] = nil end
        end
        return
    end
    P.inv = max(0, P.inv - dt)
    local mx, my = inp.mx, inp.my
    local l = sqrt(mx * mx + my * my); if l > 1 then mx, my = mx / l, my / l end
    local spd = 12.5
    P.x = clamp(P.x + mx * spd * dt, -FW / 2 + 1.1, FW / 2 - 1.1)
    P.y = clamp(P.y + my * spd * dt, 1.6, FH - 3)
    P.bank = damp(P.bank, mx * 28, 10, dt)
    if P.roll > 0 then
        P.roll = max(0, P.roll - dt)
    else
        if inp.roll and P.rolls > 0 then P.roll = ROLL_T; P.rolls = P.rolls - 1; sfx("roll")
        elseif inp.fire then fire_volley() end
    end
end
------------------------------------------------------------------ stage flow
G.later_q = {}
function G.later(d, f) G.later_q[#G.later_q + 1] = { t = d, f = f } end
local function clear_field()
    for _, t in ipairs({ SHOTS, BUL, EN, POWS }) do for i = #t, 1, -1 do t[i] = nil end end
end
local function start_stage(k)
    G.k = k; G.num = 33 - k
    clear_field()
    G.waves, G.T = G.build_waves(k); G.wi = 1; G.st = 0
    G.spawned, G.killed, G.groups = 0, 0, {}
    G.boss_done = not G.is_boss(G.num); G.boss_spawned = false
    G.ceasefire = 0
    P.rolls = 3; P.roll = 0; P.inv = 0; P.alive = true
    P.x, P.y, P.px, P.py = 0, 3.2, 0, 3.2
    G.phase = "takeoff"; G.pt = 0
    G.carrier = { y = 12.5, on = true }
    G.banner_set(string.format("Stage %d  ·  %s", G.num, G.stage_name(G.num)), 2.6)
    sfx("start")
    G.music_after = 3.0
end
G.start_stage = start_stage
local function new_game()
    G.score = 0; G.lives = 2; G.next_extra = 20000; G.out_of_lives = false; G.won = false
    P.quad = false; P.esc = { false, false }; G.pow_i = 0
    start_stage(1)
end
G.new_game_sim = new_game
local function apply_pow(c)
    sfx("pow")
    if c == "red" then P.quad = true; G.banner_set("Quad Guns", 1.4)
    elseif c == "green" then P.esc = { true, true }; G.banner_set("Side Fighters", 1.4)
    elseif c == "gray" then P.rolls = P.rolls + 1; G.banner_set("Extra Loop", 1.4)
    elseif c == "yellow" then G.ceasefire = 10; for i = #BUL, 1, -1 do BUL[i] = nil end; G.banner_set("Enemy Fire Stopped", 1.4)
    elseif c == "orange" then add_score(1000); G.banner_set("1000 Points", 1.4)
    elseif c == "white" then
        sfx("kill_all"); G.shake = 1.0; G.banner_set("Enemies Destroyed", 1.4)
        for _, e in ipairs(EN) do
            if not e.dead and e.entered then
                if e.kind == "big" then damage(e, 40) else kill_enemy(e, true) end
            end
        end
        for i = #BUL, 1, -1 do BUL[i] = nil end
    end
end
local function stage_step(inp, dt)
    G.pt = G.pt + dt
    G.scroll = (G.scroll or 0) + SCROLL * dt
    G.ceasefire = max(0, G.ceasefire - dt)
    for i = #G.later_q, 1, -1 do local q = G.later_q[i]; q.t = q.t - dt; if q.t <= 0 then table.remove(G.later_q, i); q.f() end end
    if G.carrier.on then G.carrier.y = G.carrier.y - SCROLL * dt * ((G.phase == "landing") and 0 or 1) end
    local ph = G.phase
    if ph == "takeoff" then
        local u = clamp(G.pt / 3.0, 0, 1)
        P.px, P.py = P.x, P.y
        P.y = 3.2 + u * u * 3.0
        P.h = 1.55 + (ALT - 1.55) * clamp((G.pt - 0.8) / 2.2, 0, 1) ^ 1.5
        if G.pt >= 3.0 then G.phase = "fly"; G.pt = 0; P.h = ALT; music("bgm") end
        return
    end
    if ph == "landing" then
        local c = G.carrier
        if c.y > 12 then c.y = max(12, c.y - 7 * dt) end
        P.px, P.py = P.x, P.y
        local ty = c.y - 6
        P.x = P.x + (0 - P.x) * min(1, dt * 1.6)
        P.y = P.y + (ty - P.y) * min(1, dt * 1.4)
        if c.y <= 12.01 then P.h = max(1.55, P.h - dt * 1.6) end
        P.bank = damp(P.bank, 0, 6, dt)
        if P.h <= 1.56 and G.pt > 3.5 then
            G.phase = "result"; G.pt = 0
            local rate = (G.spawned > 0) and (G.killed / G.spawned) or 0
            G.rate = rate
            G.bonus = (rate >= 0.999) and 20000 or floor(rate * 100) * 100
            add_score(G.bonus); sfx("clear"); music(nil)
        end
        for _, s in ipairs(SHOTS) do s.py = s.y; s.y = s.y + 46 * dt end
        for i = #SHOTS, 1, -1 do if SHOTS[i].y > FH + 2 then table.remove(SHOTS, i) end end
        return
    end
    if ph == "result" then
        if G.pt > 4.0 then
            if G.k >= 32 then G.won = true; G.phase = "won"; G.pt = 0; music("ending")
            else start_stage(G.k + 1) end
        end
        return
    end
    -- fly
    G.st = G.st + dt
    while G.waves[G.wi] and G.waves[G.wi].t <= G.st do spawn(G.waves[G.wi]); G.wi = G.wi + 1 end
    if not G.boss_spawned and not G.boss_done and G.st > G.T + 2 then
        G.boss_spawned = true
        spawn({ kind = "big", ai = "boss", x = 0, y = -7, h = 0, v = 0 })
        sfx("warn"); music("boss"); G.banner_set("Warning: Heavy Bomber Ayako", 2.4)
    end
    player_step(inp, dt)
    if G.out_of_lives then return end
    -- shots (swept along their path this step)
    for i = #SHOTS, 1, -1 do
        local s = SHOTS[i]
        s.py = s.y; s.y = s.y + 46 * dt
        local hit = false
        for _, e in ipairs(EN) do
            if not e.dead and e.entered then
                for _, c in ipairs(circles(e)) do
                    if seg_circle(s.x, s.py, s.y, c) then hit = true; break end
                end
                if hit then damage(e, 1); puff(s.x, s.y, { 1.6, 1.2, .6 }, 5); break end
            end
        end
        if hit or s.y > FH + 1 then table.remove(SHOTS, i) end
    end
    -- enemies
    for _, e in ipairs(EN) do
        if not e.dead then
            enemy_ai(e, dt)
            e.hit_t = max(0, e.hit_t - dt)
            if e.entered and (e.y < -6 or e.y > FH + 9 or abs(e.x) > FW / 2 + 9) then e.dead = true; e.gone = true end
            if e.kind == "big" and e.y > FH + 8 then G.boss_done = true end
            -- body contact
            if P.alive and P.roll <= 0 and P.inv <= 0 and not e.dead and e.entered then
                for _, c in ipairs(circles(e)) do
                    local dx, dy = c[1] - P.x, c[2] - P.y
                    if dx * dx + dy * dy < (c[3] + 0.36) ^ 2 then
                        player_die(); if e.kind == "zero" or e.kind == "red" then kill_enemy(e, true) end; break
                    end
                end
                for ei = 1, 2 do
                    if P.esc[ei] and not e.dead then
                        local ex, ey = esc_pos(ei)
                        for _, c in ipairs(circles(e)) do
                            local dx, dy = c[1] - ex, c[2] - ey
                            if dx * dx + dy * dy < (c[3] + 0.3) ^ 2 then lose_escort(ei); if e.kind == "zero" or e.kind == "red" then kill_enemy(e, true) end; break end
                        end
                    end
                end
            end
        end
    end
    for i = #EN, 1, -1 do if EN[i].dead then table.remove(EN, i) end end
    -- enemy bullets
    for i = #BUL, 1, -1 do
        local b = BUL[i]
        b.x = b.x + b.vx * dt; b.y = b.y + b.vy * dt
        local gone = not inside(b.x, b.y, 1)
        if not gone and P.alive and P.roll <= 0 and P.inv <= 0 then
            local dx, dy = b.x - P.x, b.y - P.y
            if dx * dx + dy * dy < 0.53 * 0.53 then player_die(); gone = true end
            for ei = 1, 2 do
                if not gone and P.esc[ei] then
                    local ex, ey = esc_pos(ei); dx, dy = b.x - ex, b.y - ey
                    if dx * dx + dy * dy < 0.47 * 0.47 then lose_escort(ei); gone = true end
                end
            end
        end
        if gone then table.remove(BUL, i) end
    end
    -- POWs drift down
    for i = #POWS, 1, -1 do
        local w = POWS[i]
        w.t = w.t + dt; w.y = w.y - 1.4 * dt; w.x = w.x + 0.8 * cos(w.t * 1.6) * dt
        local dx, dy = w.x - P.x, w.y - P.y
        if P.alive and dx * dx + dy * dy < 1.25 * 1.25 then apply_pow(w.c); table.remove(POWS, i)
        elseif w.y < -2 then table.remove(POWS, i) end
    end
    -- end of stage: all waves out, boss gone, field quiet -> carrier
    if G.wi > #G.waves and G.boss_done and P.alive then
        local busy = false
        for _, e in ipairs(EN) do if e.entered and e.kind ~= "zero" and e.kind ~= "red" then busy = true end end
        if not busy and #EN <= 2 then
            G.quiet = (G.quiet or 0) + dt
            if G.quiet > 2.5 then
                G.quiet = 0
                G.phase = "landing"; G.pt = 0
                G.carrier = { y = FH + 16, on = true }
                for j = #EN, 1, -1 do EN[j] = nil end
                for j = #BUL, 1, -1 do BUL[j] = nil end
                P.roll = 0
                G.banner_set("Landing", 1.5)
            end
        else G.quiet = 0 end
    end
end
G.stage_step = stage_step
------------------------------------------------------------------ rendering
local function V(x, y, z) return vec3(x, y, z) end
G.shake = 0
------------------------------------------------------------------ plane rigs (pooled per kind)
local RIG_MESH = {
    p38 = { "p38_body", "p38_fin", "p38_glass", "p38_mark" },
    zero = EK.zero.meshes, red = EK.red.meshes, mid = EK.mid.meshes, big = EK.big.meshes,
}
local SHMESH = { p38 = "sh_p38", esc = "sh_p38", zero = "sh_zero", red = "sh_zero", mid = "sh_mid", big = "sh_big" }
local RFREE = {}
local function new_rig(kind)
    -- root carries position + heading (yaw); the child 'att' carries pitch + bank, so the bank is a roll about the
    -- plane's OWN nose axis. (The engine's euler applies Z after Y, i.e. about the world axis: rolling the root made a
    -- plane heading down-screen bank the opposite way and a crossing plane pitch instead of bank.)
    local r = { kind = kind, root = empty("rig_" .. kind, nil, HIDE), props = {} }
    r.att = empty("att_" .. kind, r.root)
    for _, m in ipairs(RIG_MESH[kind == "esc" and "p38" or kind]) do clone(m, V(0, 0, 0), nil, r.att) end
    if kind == "p38" or kind == "esc" then
        for _, sx in ipairs({ 0.42, -0.42 }) do r.props[#r.props + 1] = clone("p38_prop", V(sx, 0.01, 0.71), nil, r.att) end
    end
    r.shadow = clone(SHMESH[kind])
    if kind == "esc" then r.root:set_scale(V(0.72, 0.72, 0.72)) end
    return r
end
local function take_rig(kind)
    local f = RFREE[kind]
    if f and #f > 0 then return table.remove(f) end
    return new_rig(kind)
end
local function give_rig(r)
    r.root:set_position(HIDE); r.shadow:set_position(HIDE)
    RFREE[r.kind] = RFREE[r.kind] or {}; table.insert(RFREE[r.kind], r)
end
local function pose_rig(r, x, y, h, yaw, pitch, roll, vis)
    if not vis then r.root:set_position(HIDE); r.shadow:set_position(HIDE); return end
    r.root:set_position(WP(x, y, h)); r.root:set_rotation(V(0, yaw, 0)); r.att:set_rotation(V(pitch or 0, 0, roll or 0))
    local k = clamp(1.2 - h * 0.04, 0.6, 1.2) * ((r.kind == "esc") and 0.72 or 1)
    r.shadow:set_position(WP(x + 0.12 * h, y - 0.18 * h, 0.05)); r.shadow:set_rotation(V(0, yaw, 0)); r.shadow:set_scale(V(k, 1, k))
end
local function yaw_of(h) return -math.deg(h) end
------------------------------------------------------------------ world: ocean tiles, islands, clouds, carrier
local OCEAN = {}
local TILE = 24
local ISL, CLD = {}, {}
local function build_world()
    for i = -2, 2 do for j = 0, 3 do OCEAN[#OCEAN + 1] = { n = clone("ocean", V(0, 0, 0), V(TILE + 0.02, 1, TILE + 0.02)), i = i, j = j } end end
    G.cv = { hull = clone("carrier_hull"), deck = clone("carrier_deck"), isl = clone("carrier_island") }
    G.next_isl, G.next_cld = 0, 0
end
local IFREE = {}
local function itake(m) local f = IFREE[m]; if f and #f > 0 then return table.remove(f) end; return clone(m) end
local function igive(m, n) n:set_position(HIDE); IFREE[m] = IFREE[m] or {}; table.insert(IFREE[m], n) end
local function spawn_island(y0)
    local v = floor(rand() * 3)
    local side = rand() < 0.5 and -1 or 1
    local o = { v = v, x = side * rr(5, 21), y = y0, yaw = rr(0, 360), parts = {} }
    for _, m in ipairs({ "isl_reef" .. v, "isl_sand" .. v, "isl_jungle" .. v }) do o.parts[#o.parts + 1] = { m = m, n = itake(m), dx = 0, dz = 0, h = 0 } end
    for k = 1, 3 + floor(rand() * 4) do
        local a, r = rr(0, 6.28), rr(2.4, 4.6)
        local dx, dz = cos(a) * r, sin(a) * r * 0.65
        o.parts[#o.parts + 1] = { m = "palm_trunk", n = itake("palm_trunk"), dx = dx, dz = dz, h = 0.12, s = rr(0.9, 1.3), ry = rr(0, 360) }
        o.parts[#o.parts + 1] = { m = "palm_leaves", n = itake("palm_leaves"), dx = dx, dz = dz, h = 0.12, s = o.parts[#o.parts].s, ry = o.parts[#o.parts].ry }
    end
    ISL[#ISL + 1] = o
end
local function spawn_cloud(y0)
    local v = floor(rand() * 3)
    CLD[#CLD + 1] = { m = "cloud" .. v, n = itake("cloud" .. v), x = rr(-20, 20), y = y0, h = rr(2.2, 3.0), s = rr(0.8, 1.4), yaw = rr(0, 360) }
end
function G.reset_world()
    for _, o in ipairs(ISL) do for _, p in ipairs(o.parts) do igive(p.m, p.n) end end
    for _, c in ipairs(CLD) do igive(c.m, c.n) end
    ISL, CLD = {}, {}
    G.scroll = 0; G.next_isl = 0; G.next_cld = 0; G.isl_scroll = nil
    for k = 0, 2 do spawn_island(10 + k * 26 + rr(-4, 4)) end
    for k = 0, 3 do spawn_cloud(6 + k * 14) end
end
local function render_world(dt)
    local sc = G.scroll or 0
    local off = sc % TILE
    for _, t in ipairs(OCEAN) do t.n:set_position(V(t.i * TILE, 0, -TILE / 2 + t.j * TILE - off + TILE / 2)) end
    -- islands drift with the scroll
    G.isl_scroll = G.isl_scroll or sc
    local d = sc - G.isl_scroll; G.isl_scroll = sc
    for i = #ISL, 1, -1 do
        local o = ISL[i]
        o.y = o.y - d
        local cy, sy = cos(math.rad(o.yaw)), sin(math.rad(o.yaw))
        for _, p in ipairs(o.parts) do
            local wx, wz = p.dx * cy + p.dz * sy, -p.dx * sy + p.dz * cy
            p.n:set_position(V(-o.x + wx, p.h, o.y + wz)); p.n:set_rotation(V(0, p.ry or o.yaw, 0))
            if p.s then p.n:set_scale(V(p.s, p.s, p.s)) end
        end
        if o.y < -16 then for _, p in ipairs(o.parts) do igive(p.m, p.n) end; table.remove(ISL, i) end
    end
    local top = -99; for _, o in ipairs(ISL) do top = max(top, o.y) end
    if top < FH + 12 then spawn_island(top + rr(22, 34)) end
    for i = #CLD, 1, -1 do
        local c = CLD[i]
        c.y = c.y - d * 1.6
        c.n:set_position(V(-c.x, c.h, c.y)); c.n:set_rotation(V(0, c.yaw, 0)); c.n:set_scale(V(c.s, c.s, c.s))
        if c.y < -14 then igive(c.m, c.n); table.remove(CLD, i) end
    end
    local ctop = -99; for _, c in ipairs(CLD) do ctop = max(ctop, c.y) end
    if ctop < FH + 10 then spawn_cloud(ctop + rr(10, 20)) end
    -- carrier
    local cv = G.cv
    if G.carrier and G.carrier.on and G.carrier.y > -20 then
        local p = V(0, 0, G.carrier.y)
        cv.hull:set_position(p); cv.deck:set_position(p); cv.isl:set_position(p)
    else cv.hull:set_position(HIDE); cv.deck:set_position(HIDE); cv.isl:set_position(HIDE) end
end
------------------------------------------------------------------ planes, shots, POWs
local PR = {}
local ER = {}
local function render_planes(dt)
    -- player
    if not PR.me then PR.me = new_rig("p38"); PR.esc = { new_rig("esc"), new_rig("esc") } end
    local x, y = lerp(P.px, P.x, AL), lerp(P.py, P.y, AL)
    local vis = P.alive and not (P.inv > 0 and floor(G.t * 10) % 2 == 0) and G.state ~= "title"
    local pitch, hh, yo = 0, P.h, 0
    if P.roll > 0 then
        local u = 1 - P.roll / G.ROLL_T
        pitch = -360 * u; hh = P.h + 2.6 * sin(math.pi * u); yo = 1.8 * sin(2 * math.pi * u)
    end
    pose_rig(PR.me, x, y + yo, hh, 0, pitch, P.bank, vis)   -- +bank = roll into the turn (right wing down when moving right)
    for _, pr in ipairs(PR.me.props) do pr:set_rotation(V(0, 0, G.t * 2200 % 360)) end
    for i = 1, 2 do
        local ex, ey = G.esc_pos(i)
        ex, ey = ex - P.x + x, ey - P.y + y
        pose_rig(PR.esc[i], ex, ey + yo, hh, 0, pitch, P.bank, vis and P.esc[i])
        for _, pr in ipairs(PR.esc[i].props) do pr:set_rotation(V(0, 0, G.t * 2200 % 360)) end
    end
    -- enemies
    local seen = {}
    for _, e in ipairs(G.EN) do
        seen[e] = true
        local r = ER[e]
        if not r then r = take_rig(e.kind); ER[e] = r end
        local turn = 0
        if e.ph then turn = ((e.h - e.ph + math.pi) % (2 * math.pi) - math.pi) / max(G.dt, 0.001) end
        e.ph = e.h
        e.bank = damp(e.bank or 0, clamp(turn * 18, -50, 50), 6, G.dt)
        if G.bank_test then e.bank = G.bank_test end   -- test hook (nil in play)
        local hgt = ALT + ((e.kind == "big") and 0.6 or 0) + ((e.kind == "mid") and 0.3 or 0)
        pose_rig(r, e.x, e.y, hgt, yaw_of(e.h), 0, e.bank, not (e.hit_t > 0 and floor(G.t * 30) % 2 == 0))
        if (e.kind == "mid" or e.kind == "big") and e.hp < EK[e.kind].hp * 0.5 and rand() < 0.3 then trail(e.x + rr(-1, 1), e.y - 0.5, hgt) end
    end
    for e, r in pairs(ER) do if not seen[e] then give_rig(r); ER[e] = nil end end
    P_begin("shot"); P_begin("ebul_core"); P_begin("ebul_star")
    for _, s in ipairs(G.SHOTS) do local n = P_get("shot"); n:set_position(WP(s.x, s.y, ALT + 0.05)) end
    -- enemy fire: a white-hot pulsing core inside a spinning magenta star (bloom gives the glow); round and spiky,
    -- so it never reads as the player's elongated yellow tracers or as anything on the sea/islands below
    for i, b in ipairs(G.BUL) do
        local ph = G.t * 16 + i * 1.7
        local p = WP(b.x, b.y, ALT + 0.12)
        local c = P_get("ebul_core"); c:set_position(p); local k = 1.8 + 0.45 * sin(ph); c:set_scale(V(k, k, k))
        local st = P_get("ebul_star"); st:set_position(p); st:set_rotation(V(0, (G.t * 420 + i * 37) % 360, 0))
        local q = 1.3 + 0.16 * sin(ph + 1.6); st:set_scale(V(q, 1, q))
    end
    P_end("shot"); P_end("ebul_core"); P_end("ebul_star")
    for _, c in ipairs({ "red", "green", "white", "gray", "yellow", "orange" }) do P_begin("pow_" .. c) end
    for _, w in ipairs(G.POWS) do
        local n = P_get("pow_" .. w.c)
        n:set_position(WP(w.x, w.y, ALT - 0.6 + 0.15 * sin(w.t * 4))); n:set_rotation(V(18 * sin(w.t * 2.3), 0, 18 * cos(w.t * 1.9))); n:set_scale(V(1.45, 1.45, 1.45))
    end
    for _, c in ipairs({ "red", "green", "white", "gray", "yellow", "orange" }) do P_end("pow_" .. c) end
end
------------------------------------------------------------------ camera
local function update_camera(dt)
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.35 * SET:shake_scale()
    local c, l = G.cam.pos, G.cam.look
    cam:set_position(V(c.x + a * sin(G.t * 53), c.y, c.z + a * cos(G.t * 61)))
    cam:look_at(l)
end
------------------------------------------------------------------ collider debug overlay (F3)
G.DBG = { on = false, pool = {}, used = 0, w = 0.09 }
local DC = { me = { .2, 1, .3 }, enemy = { 1, .25, .2 }, shot = { 1, .9, .3 }, bul = { 1, .5, .1 }, pow = { .3, .8, 1 }, wall = { .4, .7, 1 } }
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
local function dcircle(x, y, r, col, h, n)
    n = n or 10
    h = (h or ALT) + 0.6
    for i = 0, n - 1 do
        local a0, a1 = i / n * 6.2832, (i + 1) / n * 6.2832
        G.dbg_bar(WP(x + cos(a0) * r, y + sin(a0) * r, h), WP(x + cos(a1) * r, y + sin(a1) * r, h), col)
    end
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and G.state ~= "title" then
        local hw = FW / 2
        G.dbg_bar(WP(-hw, 0, ALT), WP(-hw, FH, ALT), DC.wall); G.dbg_bar(WP(hw, 0, ALT), WP(hw, FH, ALT), DC.wall)
        if P.alive then
            dcircle(P.x, P.y, 0.36, DC.me)
            for i = 1, 2 do if P.esc[i] then local ex, ey = G.esc_pos(i); dcircle(ex, ey, 0.3, DC.me, nil, 8) end end
        end
        for _, e in ipairs(G.EN) do for _, c in ipairs(G.circles(e)) do dcircle(c[1], c[2], c[3], DC.enemy, nil, 8) end end
        for _, s in ipairs(G.SHOTS) do G.dbg_bar(WP(s.x, s.py, ALT + 0.6), WP(s.x, s.y, ALT + 0.6), DC.shot) end
        for _, b in ipairs(G.BUL) do dcircle(b.x, b.y, 0.17, DC.bul, nil, 6) end
        for _, w in ipairs(G.POWS) do dcircle(w.x, w.y, 1.25 - 0.5, DC.pow, nil, 10) end
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
local LW = 300 * US
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause") and not G.set_open
    -- side panels (the arcade field is the centre strip)
    panel("lp", 20 * US, 20 * US, LW, 330 * US, play, 0.5)
    text("l1", "1UP", 40 * US, 30 * US, LW - 40 * US, 34 * US, 1.0, RED, "left", play)
    text("l2", pad6(G.score), 40 * US, 62 * US, LW - 40 * US, 52 * US, 1.8, WHITE, "left", play)
    text("l3", "High Score", 40 * US, 120 * US, LW - 40 * US, 34 * US, 1.0, RED, "left", play)
    text("l4", pad6(max(G.hiscore, G.score)), 40 * US, 152 * US, LW - 40 * US, 52 * US, 1.5, WHITE, "left", play)
    text("l5", "Planes in Reserve  " .. tostring(max(0, G.lives or 0)), 40 * US, 220 * US, LW - 40 * US, 40 * US, 1.1, DIM, "left", play)
    text("l6", "Loops  " .. string.rep("R ", P.rolls), 40 * US, 262 * US, LW - 40 * US, 40 * US, 1.1, GOLD, "left", play)
    text("l7", (P.quad and "Quad Guns" or "Twin Guns") .. ((P.esc[1] or P.esc[2]) and "  ·  Escorts" or ""), 40 * US, 300 * US, LW - 40 * US, 36 * US, 0.9, CYAN, "left", play)
    panel("rp", SW - LW - 20 * US, 20 * US, LW, 220 * US, play, 0.5)
    text("r1", "Stage " .. tostring(G.num or 32), SW - LW, 30 * US, LW - 40 * US, 56 * US, 1.8, GOLD, "right", play)
    text("r2", G.stage_name(G.num or 32), SW - LW, 88 * US, LW - 40 * US, 40 * US, 1.2, WHITE, "right", play)
    local rate = (G.spawned or 0) > 0 and floor(G.killed / G.spawned * 100) or 0
    text("r3", "Shot Down " .. rate .. "%", SW - LW, 136 * US, LW - 40 * US, 36 * US, 1.0, DIM, "right", play)
    text("r4", G.ceasefire and G.ceasefire > 0 and string.format("Enemy Fire Stopped %d", math.ceil(G.ceasefire)) or "", SW - LW, 180 * US, LW - 40 * US, 36 * US, 0.9, GOLD, "right", play)
    G.banner.t = (G.banner.t or 0) - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    text("ban", G.banner.text or "", 0, SH * 0.36, SW, 80 * US, 2.4, { 1, .88, .45, ba }, "center", play and G.banner.t > 0 and G.phase ~= "result")
    -- stage result card
    local rs = play and G.phase == "result"
    panel("rs_bg", SW / 2 - 380 * US, SH * 0.28, 760 * US, SH * 0.36, rs, 0.75)
    text("rs_t", "Stage " .. tostring(G.num or 0) .. " Clear", 0, SH * 0.3, SW, 80 * US, 2.6, GOLD, "center", rs)
    text("rs_r", "Shooting Down  " .. floor((G.rate or 0) * 100) .. "%", 0, SH * 0.3 + 100 * US, SW, 50 * US, 1.5, WHITE, "center", rs)
    text("rs_b", ((G.rate or 0) >= 0.999 and "Perfect!  " or "") .. "Bonus  " .. tostring(G.bonus or 0), 0, SH * 0.3 + 160 * US, SW, 50 * US, 1.5, WHITE, "center", rs)
    -- title
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 470 * US, SH * 0.06, 940 * US, SH * 0.86, title, 0.62)
    text("t_title", "1942 Remix", 0, SH * 0.08, SW, 130 * US, 4.4, { 1, .5, .3, 1 }, "center", title)
    text("t_sub", "Fly the P-38 from Midway to Tokyo: 32 stages over the Pacific", 0, SH * 0.08 + 120 * US, SW, 40 * US, 1.0, DIM, "center", title)
    local CL = { "WASD / Arrows: fly   ·   Space / Z / J / Left Click: fire (one volley per press)",
        "X / K / Shift / Right Click: loop (evade, 3 per stage)",
        "Shoot a whole red formation for a POW: Red Quad Guns · Green Side Fighters · White Destroy All",
        "Gray Extra Loop · Yellow Stop Enemy Fire · Orange 1000 Points",
        "P / Esc: pause   ·   O: settings   ·   M: mute   ·   F3: colliders" }
    for i, l in ipairs(CL) do text("t_c" .. i, l, SW / 2 - 460 * US, SH * 0.62 + (i - 1) * 34 * US, 920 * US, 34 * US, 0.92, DIM, "center", title) end
    text("t_hi", "High Score " .. tostring(G.hiscore), 0, SH * 0.62 + 180 * US, SW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, GOLD, "center", pause)
    local over = st == "over" and not G.set_open
    panel("o_bg", SW / 2 - 400 * US, SH * 0.22, 800 * US, SH * 0.56, over, 0.78)
    text("o_t", G.won and "Victory!" or "Game Over", 0, SH * 0.24, SW, 90 * US, 3.0, G.won and GOLD or RED, "center", over)
    text("o_m", G.won and "You flew all 32 stages and reached Tokyo" or ("Stage " .. tostring(G.num or 32) .. "  ·  " .. G.stage_name(G.num or 32)), 0, SH * 0.24 + 92 * US, SW, 40 * US, 1.2, DIM, "center", over)
    text("o_s", "Score " .. tostring(G.score), 0, SH * 0.24 + 140 * US, SW, 44 * US, 1.4, WHITE, "center", over)
    local c = {}
    local yb = SH * 0.3
    c.start = button("b_start", "Start (Enter)", SW / 2 - 190 * US, yb, title)
    c.jev = button("b_jev", "Jev", SW / 2 + 190 * US, yb, title)
    c.set_t = button("b_set_t", "Settings (O)", SW / 2, yb + 76 * US, title)
    c.quit_app = button("b_quit_app", "Quit Game", SW / 2, yb + 152 * US, title)
    c.resume = button("b_resume", "Resume (P)", SW / 2, SH * 0.42, pause)
    c.set_p = button("b_set_p", "Settings (O)", SW / 2, SH * 0.42 + 76 * US, pause)
    c.quit = button("b_quit", "Quit to Title (Q)", SW / 2, SH * 0.42 + 152 * US, pause)
    local ov = over and (G.over_t or 0) > 1.2
    c.again = button("b_again", "Play Again (Enter)", SW / 2, SH * 0.52, ov)
    c.title = button("b_title", "Title (Esc)", SW / 2, SH * 0.52 + 76 * US, ov)
    return c
end

------------------------------------------------------------------ flow
local jev

local function to_title()
    G.state = "title"; G.won = false
    G.new_game_sim(); G.phase = "title"; G.carrier.on = false
    G.reset_world()
    music("title")
end
G.to_title = to_title
local function new_game()
    G.reset_world()
    G.new_game_sim()
    G.state = "play"
    music(nil)
end
G.new_game = new_game
local function game_over()
    G.state = "over"; G.over_t = 0
    music(nil); sfx(G.won and "clear" or "gameover")
    if G.score > G.hiscore and not (jev and jev:assisted()) then
        G.hiscore = G.score
        save_hi()
    end
end

local DIR_KEYS = { "Up", "Down", "Left", "Right" }
local DIRS = {
    up = { Up = true },
    up_right = { Up = true, Right = true },
    right = { Right = true },
    down_right = { Down = true, Right = true },
    down = { Down = true },
    down_left = { Down = true, Left = true },
    left = { Left = true },
    up_left = { Up = true, Left = true },
    stop = {},
}
local DIR_STEP = {
    up = { 0, 1 },
    up_right = { 0.7071, 0.7071 },
    right = { 1, 0 },
    down_right = { 0.7071, -0.7071 },
    down = { 0, -1 },
    down_left = { -0.7071, -0.7071 },
    left = { -1, 0 },
    up_left = { -0.7071, 0.7071 },
}
local DIR_ORDER = {
    "up", "up_right", "right", "down_right",
    "down", "down_left", "left", "up_left",
    "stop",
}
local DIR_TEXT = {
    up = "Fly up. Guns keep firing while this is held.",
    up_right = "Fly up-right. Guns keep firing while this is held.",
    right = "Fly right. Guns keep firing while this is held.",
    down_right = "Fly down-right. Guns keep firing while this is held.",
    down = "Fly down. Guns keep firing while this is held.",
    down_left = "Fly down-left. Guns keep firing while this is held.",
    left = "Fly left. Guns keep firing while this is held.",
    up_left = "Fly up-left. Guns keep firing while this is held.",
    stop = "Stop. Guns stop until the next direction.",
}
local PULSES = { loop = "X" }
local pulse = {}
local driving = false
local HUMAN_KEYS = {
    "W", "A", "S", "D",
    "Up", "Down", "Left", "Right",
    "Space", "Z", "J",
    "X", "K", "LeftShift", "RightShift",
}
local human_down = {}
local human_ready = false
local human_hit = false

local function clear_hold()
    for _, key in ipairs(DIR_KEYS) do
        G.vk[key] = nil
    end
    for _, key in pairs(PULSES) do
        G.vk[key] = nil
        pulse[key] = nil
    end
end

local function apply_action(id)
    local dir = DIRS[id]
    if dir then
        for _, key in ipairs(DIR_KEYS) do
            G.vk[key] = dir[key]
        end
        return
    end

    local key = PULSES[id]
    if not key then
        return
    end

    G.vk[key] = true
    arm_edge(key)
    pulse[key] = "down"
end

local function release_pulses()
    for key, state in pairs(pulse) do
        if state == "up_next" then
            G.vk[key] = nil
            pulse[key] = nil
        end
    end
end

local function latch_pulses()
    for key, state in pairs(pulse) do
        if state == "down" then
            pulse[key] = "up_next"
        end
    end
end

local function poll_human()
    local raw = input.is_key_down_raw
    if not raw then
        return false
    end

    local hit = false
    for _, key in ipairs(HUMAN_KEYS) do
        local down = false
        local ok, value = pcall(raw, key)
        if ok and value then
            down = true
        end
        if human_ready and down and not human_down[key] then
            hit = true
        end
        human_down[key] = down
    end
    human_ready = true
    return hit
end

local function human_edge()
    return human_hit
end

local function nearest_enemy()
    local best = nil
    local best_d = nil
    for _, e in ipairs(G.EN or {}) do
        if not e.dead then
            local dx = e.x - P.x
            local dy = e.y - P.y
            local d = dx * dx + dy * dy
            if not best_d or d < best_d then
                best = e
                best_d = d
            end
        end
    end
    return best
end

-- Positive aim_dx means the target is to the right. A close bullet pushes the aim off itself.
local function aim_offset()
    local ax, ay = 0, 5
    local enemy = nearest_enemy()
    if enemy and enemy.y > P.y - 1 then
        ax, ay = enemy.x, enemy.y
    end

    local dx = ax - P.x
    local dy = ay - P.y
    for _, b in ipairs(G.BUL or {}) do
        local bx = b.x - P.x
        local by = b.y - P.y
        if by > -0.5 and by < 5 and abs(bx) < 2.2 then
            local side = bx > 0 and 1 or -1
            dx = dx - side * (2.2 - abs(bx))
        end
    end
    return dx, dy
end

local function jev_actions()
    local dx, dy = aim_offset()
    if P.rolls > 0 and P.roll <= 0 then
        for _, b in ipairs(G.BUL or {}) do
            local bx = b.x - P.x
            local by = b.y - P.y
            if by > -0.5 and by < 4 and abs(bx) < 1.6 then
                return { { id = "loop", description = "Loop once to dodge a close shot.", score = 12 } }
            end
        end
    end

    local best_id = "up"
    local best = -1e9
    for _, id in ipairs(DIR_ORDER) do
        local step = DIR_STEP[id]
        if step then
            local score = step[1] * dx + step[2] * dy
            if score > best then
                best = score
                best_id = id
            end
        end
    end
    return { { id = best_id, description = DIR_TEXT[best_id], score = best } }
end

local acc = 0
local rmouse_prev, lmouse_prev = true, true
local q = { fire = false, roll = false }
local mprev = { x = 0, y = 0 }
local function update(dt)
    flush_mats()
    dt = min(dt, 0.1)
    G.t = G.t + dt; G.dt = dt
    human_hit = poll_human()
    jev:tick(dt)
    release_pulses()
    local k = { ret = edge("Return"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), qk = edge("Q"), f3 = edge("F3"),
        space = edge("Space"), z = edge("Z"), j = edge("J"), x = edge("X"), kk = edge("K"), sh = edge("LeftShift"), sh2 = edge("RightShift") }
    latch_pulses()
    local rd, ld = false, false
    pcall(function() rd = input.is_right_mouse_down and input.is_right_mouse_down() and true or false end)
    pcall(function() ld = input.is_left_mouse_down and input.is_left_mouse_down() and true or false end)
    local rclick, lclick = rd and not rmouse_prev, ld and not lmouse_prev
    rmouse_prev, lmouse_prev = rd, ld
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end; rclick, lclick = false, false end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        if k.ret or k.space or c.start then
            sfx("click")
            jev:begin_human()
            new_game()
        elseif c.jev then
            sfx("click")
            local started = jev:start()
            if not started then
                jev:begin_human()
                local err = jev:error()
                if not err or err == "" then
                    err = "Jev failed to start"
                end
                pe_log("[AF] " .. err)
                G.banner_set(err, 4)
            end
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click")
        else
            if k.space or k.z or k.j or lclick then q.fire = true end
            if k.x or k.kk or k.sh or k.sh2 or rclick then q.roll = true end
            if driving and (any("Left", "A") or any("Right", "D") or any("Up", "W") or any("Down", "S")) then
                q.fire = true
            end
        end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.qk or c.quit then
            jev:begin_human()
            to_title()
        end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then
                sfx("click")
                jev:begin_human()
                new_game()
            elseif k.esc or c.title then to_title() end
        end
    end
    st = G.state
    if st == "play" and not G.set_open then
        local mx = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0)
        local my = (any("Up", "W") and 1 or 0) - (any("Down", "S") and 1 or 0)
        if (mx ~= 0 or my ~= 0) and (mx ~= mprev.x or my ~= mprev.y) and P.alive and G.phase == "fly" then sfx("bank") end
        mprev.x, mprev.y = mx, my
        if G.autoplay then mx, my, q.fire = G.autoplay_fn() end
        local inp = { mx = mx, my = my, fire = false, roll = false }
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 6 do
            inp.fire, inp.roll = q.fire, q.roll; q.fire, q.roll = false, false
            if G.phase ~= "fly" then inp.fire, inp.roll = false, false end
            G.stage_step(inp, FR)
            acc = acc - FR; n = n + 1
        end
        if acc > FR * 6 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if G.music_after then G.music_after = G.music_after - dt; if G.music_after <= 0 then G.music_after = nil end end
        if G.out_of_lives and G.state == "play" then game_over() end
        if G.phase == "won" and G.pt > 0 then G.phase = "done"; game_over() end
        G.drone_t = (G.drone_t or 0) - dt
        if G.drone_t <= 0 and P.alive then G.drone_t = 0.95; sfx("drone") end
    elseif st == "title" then
        G.scroll = (G.scroll or 0) + 3 * dt
        AL = 1
    else AL = 1 end
    render_world(dt)
    render_planes(dt)
    update_camera(dt)
    update_lights(dt)
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end
-- debug autopilot for tests/screenshots only (G.autoplay = true): weave, dodge the nearest bullet, keep firing
function G.autoplay_fn()
    local tx = 0
    local best
    for _, e in ipairs(G.EN) do if e.entered and (not best or e.y < best.y) and e.y > P.y then best = e end end
    if best then tx = best.x end
    local mx = clamp((tx - P.x) * 0.6, -1, 1)
    local my = clamp((5 - P.y) * 0.4, -1, 1)
    for _, b in ipairs(G.BUL) do
        local dx, dy = b.x - P.x, b.y - P.y
        if dy > -0.5 and dy < 4 and abs(dx) < 1.4 then mx = dx > 0 and -1 or 1 end
    end
    G.ap_t = (G.ap_t or 0) + 1
    return mx, my, (G.ap_t % 9 == 0)
end

------------------------------------------------------------------ boot
local JevAuto = assert(load(assert(fs.read("Scripts/jev_auto.lua")), "@Scripts/jev_auto.lua", "t", _ENV))()
jev = JevAuto.attach({
    port = 9136,
    id = "1942remix",
    description = "1942 Remix. Fly the P-38 and shoot the formation. A direction is a hold: the plane keeps "
        .. "flying that way and the guns keep firing until the next direction. aim_dx positive means the target is "
        .. "to the right. aim_dy positive means it is up the screen. Prefer the higher action score.",
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
        return P.alive and P.roll > 0
    end,
    human_edge = human_edge,
    observe = function()
        local dx, dy = aim_offset()
        return {
            player_x = P.x,
            player_y = P.y,
            aim_dx = dx,
            aim_dy = dy,
            lives = G.lives or 0,
            loops = P.rolls or 0,
            score = G.score or 0,
        }
    end,
    actions = jev_actions,
    apply = apply_action,
    reset = function(seed)
        math.randomseed(seed)
        clear_hold()
        driving = true
        new_game()
    end,
    on_human = function()
        driving = false
        clear_hold()
    end,
})

build_lights()
paint_templates()
build_world()
to_title()
G.update = update; G.SET = SET
hooks { update = update }
pe_log("[AF] ready")
