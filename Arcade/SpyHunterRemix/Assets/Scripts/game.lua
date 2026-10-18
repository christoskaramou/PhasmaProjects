-- SPY HUNTER REMIX  (PhasmaEngine, Lua)
-- A faithful modern remake of Bally Midway's Spy Hunter (1983): drive the G-6155 Interceptor down an endless road,
-- shoot or ram enemy agents off the road (but spare the civilians), dock with the weapons van for oil slicks, smoke
-- screens and missiles, and switch to the boat at the boathouse for the river sections.
-- Logic coords: x across the road, y = distance travelled (forward). WP maps to world (camera looks forward, +Z).
local PI = math.pi
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
math.randomseed(os and os.time and os.time() or 1942)
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local G = { state = "boot", t = 0 }
_G.SH = G

------------------------------------------------------------------ deferred materials (engine quirk: replay writes)
local _mset, _mtex, _mds = material.set, material.set_texture, material.set_double_sided
local mat_q = {}
local function qpush(f) mat_q[#mat_q + 1] = { f = f, n = 0 } end
local function mset(n, k, v) pcall(_mset, n, k, v); qpush(function() pcall(_mset, n, k, v) end) end
local function mtex(n, k, v) qpush(function() pcall(_mtex, n, k, v) end) end
local function flush_mats()
    -- oldest first, so a later request for the same material wins
    local i = 1
    while i <= #mat_q do
        local q = mat_q[i]; q.n = q.n + 1
        if q.n == 2 or q.n == 6 then q.f() end
        if q.n >= 6 then table.remove(mat_q, i) else i = i + 1 end
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
local ss = scene.add_empty_node("SpyHunterSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "day.hdr")
S("hdr", false); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false); S("dof", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.2)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", false)
S("color_grading", true); S("color_grading_saturation", 1.05); S("color_grading_contrast", 1.04)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "SETTINGS", subtitle = "Spy Hunter Remix", file = "Save/settings.cfg", music = true,
    click = function() sfx("click") end, defaults = { master = 0.5 },
    theme = { accent = { 0.35, 0.75, 1, 1 }, accent2 = { 1, 0.55, 0.3, 1 }, text = { 0.86, 0.84, 0.8, 1 }, selected_text = { 1, 0.97, 0.9, 1 } } })
SET:apply()
G.set_open = false

------------------------------------------------------------------ camera
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1600, surf.height or 900
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local VFOV = math.rad(38)
local FOVX = 2 * math.atan(math.tan(VFOV / 2) * SW / SH)
pcall(function() cam:set_fov(math.deg(FOVX)) end)
pcall(function() cam:set_far_plane(300) end)
local function WP(x, y, h) return vec3(-x, h or 0, y) end
G.cam = { x = 0, y = 0 }
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
    if not n then pe_log("[SH] missing template " .. name); return nil end
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

local FR = 1 / 60
local AL = 1
------------------------------------------------------------------ palette {base, emissive, rough, metal}
local PAL = {
    int_body = { { .92, .92, .95 }, { .02, .02, .02 }, .25, .35 }, int_glass = { { .05, .07, .1 }, { 0, 0, 0 }, .08, .2 },
    int_wheel = { { .06, .06, .07 }, { 0, 0, 0 }, .7 }, int_gun = { { .35, .35, .4 }, { 0, 0, 0 }, .3, .7 },
    civ_body = { { .2, .45, .85 }, { 0, 0, .02 }, .35, .3 }, civ_glass = { { .08, .1, .14 }, { 0, 0, 0 }, .1 }, civ_wheel = { { .06, .06, .07 }, { 0, 0, 0 }, .7 },
    truck_cab = { { .9, .55, .15 }, { .02, .01, 0 }, .45, .2 }, truck_box = { { .85, .85, .8 }, { 0, 0, 0 }, .6 }, truck_wheel = { { .06, .06, .07 }, { 0, 0, 0 }, .7 },
    van_box = { { .8, .15, .12 }, { .03, 0, 0 }, .45, .2 }, van_ramp = { { .5, .5, .55 }, { 0, 0, 0 }, .4, .7 },
    sw_body = { { .25, .55, .75 }, { 0, .01, .02 }, .35, .4 }, sw_glass = { { .06, .08, .1 }, { 0, 0, 0 }, .1 }, sw_blade = { { .8, .8, .85 }, { .05, .05, .05 }, .2, .8 },
    rl_body = { { .3, .3, .32 }, { 0, 0, 0 }, .5, .6 }, rl_glass = { { .06, .08, .1 }, { 0, 0, 0 }, .1 }, rl_plate = { { .5, .5, .52 }, { 0, 0, 0 }, .35, .8 },
    enf_body = { { .07, .07, .08 }, { 0, 0, 0 }, .2, .5 }, enf_glass = { { .1, .1, .12 }, { 0, 0, 0 }, .08 }, enf_wheel = { { .06, .06, .07 }, { 0, 0, 0 }, .7 },
    heli_body = { { .25, .3, .22 }, { 0, 0, 0 }, .5, .3 }, heli_glass = { { .1, .15, .2 }, { .02, .03, .04 }, .1 }, heli_rotor = { { .15, .15, .16 }, { 0, 0, 0 }, .5 },
    boat_hull = { { .92, .92, .95 }, { .02, .02, .02 }, .3, .2 }, boat_deck = { { .3, .32, .38 }, { 0, 0, 0 }, .4, .4 },
    eboat_hull = { { .7, .15, .12 }, { .02, 0, 0 }, .4, .2 }, eboat_deck = { { .3, .3, .3 }, { 0, 0, 0 }, .5 },
    torpedo = { { .4, .4, .45 }, { 0, 0, 0 }, .3, .7 }, barrel = { { .6, .3, .1 }, { 0, 0, 0 }, .6 },
    bullet = { { 1, .85, .4 }, { 1.4, 1.0, .4 }, .4 }, missile = { { .85, .85, .9 }, { .1, .05, .02 }, .3, .5 }, bomb = { { .1, .1, .12 }, { 0, 0, 0 }, .4, .5 },
    oil = { { .02, .02, .03 }, { 0, 0, 0 }, .05, .3 }, crater = { { .12, .1, .08 }, { 0, 0, 0 }, .9 }, shadow = { { .05, .05, .05 }, { 0, 0, 0 }, 1 },
    road = { { .9, .9, .9 }, { 0, 0, 0 }, .85 }, curb = { { 1, 1, 1 }, { 0, 0, 0 }, .6 }, water = { { 1, 1, 1 }, { .02, .03, .04 }, .15 },
    bank = { { 1, 1, 1 }, { 0, 0, 0 }, .9 }, ground = { { 1, 1, 1 }, { 0, 0, 0 }, .95 }, rail = { { .75, .75, .78 }, { 0, 0, 0 }, .35, .7 },
    tree_trunk = { { .4, .27, .15 }, { 0, 0, 0 }, .9 }, tree_top = { { .25, .5, .2 }, { 0, 0, 0 }, .85 }, pine = { { .25, .52, .28 }, { 0, 0, 0 }, .85 },
    bush = { { .3, .5, .22 }, { 0, 0, 0 }, .85 }, house_wall = { { .85, .8, .7 }, { 0, 0, 0 }, .8 }, house_roof = { { .6, .25, .2 }, { 0, 0, 0 }, .8 },
    boathouse = { { .5, .35, .22 }, { 0, 0, 0 }, .85 },
}
-- seasons: the verge and trees change colour every loop of the course (summer, autumn, winter, spring)
local SEASON = { { { .3, .6, .25 }, { 1.35, 1.35, 1.3 } }, { { .8, .45, .15 }, { 1.4, 1.15, .85 } }, { { .82, .86, .9 }, { 1, 1, 1 } }, { { .4, .7, .32 }, { 1.4, 1.5, 1.25 } } }
G.SEASON = SEASON
local function paint_templates()
    for name, v in pairs(PAL) do paint(tnode(name), v[1], v[2], v[3], v[4]) end
    mtex(tnode("road"), "base_color", "Textures/road.png"); mtex(tnode("curb"), "base_color", "Textures/curb.png")
    mtex(tnode("water"), "base_color", "Textures/water.png"); mtex(tnode("bank"), "base_color", "Textures/sand.png")
    mtex(tnode("ground"), "base_color", "Textures/grass.png")
    for name in pairs(PAL) do local n = tnode(name); if n then n:set_position(HIDE) end end
end
function G.set_season(k)
    local s = SEASON[(k - 1) % 4 + 1]
    paint(tnode("tree_top"), s[1], { 0, 0, 0 }, .85); paint(tnode("bush"), { s[1][1] * 1.1, s[1][2] * 1.05, s[1][3] }, { 0, 0, 0 }, .85)
    paint(tnode("ground"), s[2], { 0, 0, 0 }, .95)
    mtex(tnode("ground"), "base_color", (k - 1) % 4 == 2 and "Textures/snow.png" or "Textures/grass.png")
end

------------------------------------------------------------------ lights
local LT = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(-0.35, -0.85, 0.3), vec3(1.0, 0.97, 0.9), 3.4)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    LT.fill = addp(HIDE, vec3(0.7, 0.8, 1.0), 14, 30)
    LT.flash = {}
    for i = 1, 5 do LT.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1 } end
end
G.flash_next = 1
local function flash(p, col, power, life, rad)
    local f = LT.flash[G.flash_next]; G.flash_next = G.flash_next % #LT.flash + 1
    f.t, f.life, f.p, f.col, f.power, f.rad = 0, life or 0.3, p, vec3(col[1], col[2], col[3]), power or 30, rad or 4
end
local function update_lights(dt, x, y)
    set_point(LT.fill, WP(x, y + 6, 8), vec3(0.7, 0.8, 1.0), 14, 30)
    for _, f in ipairs(LT.flash) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = 1 - clamp(f.t / f.life, 0, 1)
            set_point(f.idx, f.p, f.col, f.power * k * k, f.rad)
            if f.t >= f.life then set_point(f.idx, HIDE, f.col, 0, 1) end
        end
    end
end

------------------------------------------------------------------ particles
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
-- these keep their old signatures (p = world vec3) but draw with the textured FX helpers (02c_fx / 02d_shfx)
local function puff(p, col, n)
    col = col or { .7, .7, .75 }
    G.FX.emit("smoke", p.x, p.y, p.z, { n = max(1, (n or 14) / 5), c0 = { col[1] * .45, col[2] * .45, col[3] * .45 }, c1 = { 0, 0, 0 },
        s0 = .5, s1 = 1.0, l0 = .4, l1 = .8, r = .3, sp = 1.5, drag = 2, grav = { 0, 1.5, 0 } })
end
local function sparks(p, n, col)
    G.FX.sparks(p.x, p.y, p.z, max(3, (n or 8) * 1.5), nil, 9)
end
local function smoke(p, n)
    G.FX.smoke(p.x, p.y, p.z, max(0.5, (n or 10) / 8), { 0, 0.3, 0 }, 0.34, 1.6)
end
local function spray(p, n)
    G.FX.spray(p.x, p.y, p.z, max(0.4, (n or 6) / 6), { 0, 1.2, 0 }, 0.9)
end
local function boom(p, big)
    G.sh_explode(p, big)
    flash(p, { 1, .7, .4 }, big and 120 or 30, big and 0.8 or 0.3, big and 14 or 5)
end

------------------------------------------------------------------ score state
G.score, G.hiscore = 0, 0
pcall(function() local s = fs.read("Save/spyhunter_hiscore.txt"); if s then G.hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, "Save/spyhunter_hiscore.txt", tostring(G.hiscore)) end
local function add_score(n) G.score = G.score + n end
G.banner = { text = "", t = 0 }
function G.banner_set(t, d) G.banner.text = t; G.banner.t = d or 1.5 end
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
------------------------------------------------------------------ Spy Hunter effects (built on 02c_fx; game units: the car is ~1.5 long)
FX.scale = 0.38
G.fx_light = function(pos, col, power, life, radius) flash(pos, col, power * 0.5, life, radius) end
local SFX = { fires = {}, t = {} }
G.SFX = SFX
local function W3(x, y, h) local p = WP(x, y, h or 0); return p.x, p.y, p.z end
-- explosion: flash, fireball, sparks, rolling smoke, plus a short-lived burning wreck left on the ground.
-- Over water it throws a spray column and a foam ring instead of leaving fire.
function G.sh_explode(p, big)
    local s = big and 3.5 or 1.8
    local gy = p.z   -- world z = course distance
    local gx = -p.x
    local _, _, _, kind = G.course(gy)
    local wet = kind == "river"
    local v = G.P and G.P.v or 0
    FX.explosion(p.x, p.y, p.z, s, { 0, 0.5, v * 0.35 })
    FX.emit("soft", p.x, p.y, p.z, { n = 8 * s, vel = { 0, 2, v * 0.3 }, c0 = { 1.6, 1.0, 0.45 }, c1 = { 0.4, 0.08, 0 }, s0 = .08, s1 = .16,
        l0 = .5, l1 = 1.1, r = .3, sp = 9, drag = .8, grav = { 0, -10, 0 } })                                  -- burning bits
    if wet then
        FX.spray(p.x, p.y, p.z, 2.5 * s, { 0, 4, v * 0.3 }, 1.6 * s)
        FX.emit("foam", p.x, 0.12, p.z, { n = 3, c0 = { .55, .6, .65 }, c1 = { 0, 0, 0 }, s0 = 3 * s, s1 = 4 * s, l0 = 1.0, l1 = 1.6, r = .3, sp = .5, flat = true })
    else
        FX.ring(p.x, 0.13, p.z, 4 * s, { .45, .42, .38 }, true)
        SFX.fires[#SFX.fires + 1] = { x = gx, y = gy, t = 0, life = big and 0 or 1.8 }
    end
end
-- muzzle flash at each gun barrel; dir = travel speed of the shooter
function G.muzzle(x, y, v, side_dir)
    local px, py, pz = W3(x, y, 0.32)
    if side_dir then
        FX.emit("fire", px, py, pz, { n = 2, vel = { -side_dir * 6, 0, v }, c0 = { 2, 1.4, .6 }, c1 = { .3, .05, 0 }, s0 = .5, s1 = .8, l0 = .04, l1 = .07, r = .02, sp = .5, drag = 6 })
    else
        FX.emit("fire", px, py, pz, { n = 2, vel = { 0, 0, v + 6 }, c0 = { 2, 1.5, .7 }, c1 = { .3, .05, 0 }, s0 = .45, s1 = .7, l0 = .04, l1 = .07, r = .02, sp = .5, drag = 6 })
        FX.emit("soft", px, py + 0.05, pz - 0.3, { n = 1, vel = { (rand() < 0.5 and -1 or 1) * 2.5, 1.5, v }, c0 = { 1.2, .9, .35 }, c1 = { .3, .2, .05 },
            s0 = .1, s1 = .14, l0 = .25, l1 = .4, r = .02, sp = 1, drag = 1, grav = { 0, -14, 0 } })                    -- brass
    end
    flash(WP(x, y, 0.6), { 1, .75, .4 }, 5, 0.06, 2.2)
end
-- dock swap: splash-down into the river / water streaming off the car on the ramp
function G.on_swap(mode)
    local P = G.P
    local px, py, pz = W3(P.x, P.y, 0)
    if mode == "boat" then
        FX.spray(px, py, pz + 0.4, 3, { 0, 3.5, P.v * 0.5 }, 1.8)
        FX.emit("foam", px, 0.12, pz, { n = 3, vel = { 0, 0, P.v * 0.3 }, c0 = { .6, .65, .7 }, c1 = { 0, 0, 0 }, s0 = 2.5, s1 = 3.5, l0 = .8, l1 = 1.3, r = .4, sp = .5, flat = true })
        FX.ring(px, 0.13, pz, 3.2, { .5, .55, .6 }, true)
    else
        FX.spray(px, py + 0.2, pz, 1.5, { 0, 1.0, P.v * 0.6 }, 1.0)
    end
    SFX.drip = (mode == "car") and 1.2 or 0
end
function G.on_respawn()
    local P = G.P
    local px, py, pz = W3(P.x, P.y, 0.05)
    if P.mode == "boat" then FX.spray(px, py, pz, 1.5, { 0, 2, P.v }, 1.2)
    else FX.dust(px, py, pz, { .35, .34, .32 }, 1, { 0, 0.5, P.v * 0.6 }, 1.4) end
end
-- per-frame effects that follow the vehicles (called from render_world)
local function every(key, period, dt)
    local t = (SFX.t[key] or 0) - dt
    if t <= 0 then SFX.t[key] = t + period; if SFX.t[key] < 0 then SFX.t[key] = period end; return true end
    SFX.t[key] = t; return false
end
local function wake(key, x, y, v, half, len, k, dt)
    if v < 2 or not every(key, 0.035, dt) then return end
    local f = clamp(v / 22, 0.3, 1.1) * (k or 1)
    for _, s in ipairs({ -1, 1 }) do
        local px, py, pz = W3(x + s * half, y - len, 0.12)   -- 12 cm up: the particle pass fades anything within 10 cm of a surface
        FX.emit("foam", px, py, pz, { n = 1, vel = { -s * (0.6 + v * 0.05), 0, v * 0.25 }, c0 = { .75 * f, .8 * f, .85 * f }, c1 = { 0, 0, 0 },
            s0 = 1.3, s1 = 2.1, l0 = 1.3, l1 = 2.0, r = .05, sp = .3, drag = .8, flat = true })
        local bx, by, bz = W3(x + s * half * 0.8, y + len * 0.7, 0.0)
        if rand() < 0.6 then FX.emit("foam", bx, by, bz, { n = 1, vel = { -s * (1 + v * 0.08), 1.2 + v * 0.05, v * 0.9 }, c0 = { .5 * f, .55 * f, .6 * f }, c1 = { 0, 0, 0 },
            s0 = .5, s1 = .9, l0 = .25, l1 = .45, r = .05, sp = 1, drag = 1.5, grav = { 0, -9, 0 } }) end      -- bow spray
    end
    local cx, cy, cz = W3(x, y - len - 0.1, 0.12)
    FX.emit("foam", cx, cy, cz, { n = 1, vel = { 0, 0.4, v * 0.3 }, c0 = { .6 * f, .65 * f, .7 * f }, c1 = { 0, 0, 0 }, s0 = 1.4, s1 = 2.0, l0 = .8, l1 = 1.3, r = .1, sp = .5, drag = 1.2, flat = true })  -- prop wash
end
local function tyres(key, x, y, v, k, dt)
    if not every(key, 0.05, dt) then return end
    for _, s in ipairs({ -1, 1 }) do
        local px, py, pz = W3(x + s * 0.34, y - 0.5, 0.08)
        FX.smoke(px, py, pz, 0.45 * k, { 0, 0.3, v * 0.7 }, 0.3, 0.9)
    end
end
function G.sh_frame_fx(dt)
    local P = G.P
    if G.state ~= "play" and G.state ~= "title" then return end
    if P.alive and G.phase == "drive" then
        if P.mode == "boat" then wake("pw", P.x, P.y, P.v, 0.38, 0.8, 1, dt)
        else
            local k = 0
            if P.brk then k = 1 elseif abs(P.vx or 0) > 4.2 then k = 0.6 end
            if k > 0 then tyres("pt", P.x, P.y, P.v, k, dt) end
            if (SFX.drip or 0) > 0 then
                SFX.drip = SFX.drip - dt
                if every("drip", 0.05, dt) then local px, py, pz = W3(P.x, P.y - 0.5, 0.2); FX.spray(px, py, pz, 0.4, { 0, 0.5, P.v * 0.8 }, 0.6) end
            end
            if every("exh", 0.09, dt) then
                local px, py, pz = W3(P.x, P.y - 0.8, 0.18)
                FX.emit("smoke", px, py, pz, { n = 1, vel = { 0, 0.3, P.v * 0.6 }, c0 = { .12, .12, .13 }, c1 = { 0, 0, 0 }, s0 = .35, s1 = .6, l0 = .3, l1 = .6, r = .03, sp = .5, drag = 3 })
            end
        end
    end
    for i, e in ipairs(G.EN) do
        if e.alive then
            if e.k == "eboat" or e.k == "dumper" then wake("ew" .. i, e.x, e.y, e.v, 0.45, 0.9, 0.8, dt)
            elseif e.spin > 0 then tyres("es" .. i, e.x, e.y, e.v, 1, dt) end
        end
    end
    for _, s in ipairs(G.SHOTS) do
        if s.k == "missile" then
            local px, py, pz = W3(s.x, s.y - 0.35, 0.3)
            FX.emit("fire", px, py, pz, { n = 1, vel = { 0, 0, P.v * 0.5 }, c0 = { 1.8, 1.1, .45 }, c1 = { .2, .03, 0 }, s0 = .35, s1 = .5, l0 = .05, l1 = .1, r = .02, sp = .4, drag = 4 })
            if every("ms", 0.03, dt) then FX.emit("smoke", px, py, pz, { n = 1, vel = { 0, 0.4, P.v * 0.4 }, c0 = { .3, .3, .31 }, c1 = { 0, 0, 0 }, s0 = .5, s1 = .8, l0 = .5, l1 = .9, r = .05, sp = .6, drag = 2.5 }) end
        end
    end
    for i, s in ipairs(G.ESHOT) do
        if s.k == "torpedo" and every("tp" .. i, 0.04, dt) then
            local px, py, pz = W3(s.x, s.y - 0.3, 0.12)
            FX.emit("foam", px, py, pz, { n = 1, c0 = { .4, .45, .5 }, c1 = { 0, 0, 0 }, s0 = .5, s1 = .8, l0 = .7, l1 = 1.1, r = .05, sp = .3, flat = true })
        end
    end
    for i, o in ipairs(G.DROPS) do
        if o.k == "smoke" and o.t < 3.0 and every("sm" .. i, 0.09, dt) then
            -- the smoke screen: a rolling wall across its whole catch width. Puffs are dim on purpose: the particle
            -- pass screen-blends, so twenty overlapping puffs already read as a thick white wall.
            local k = 1 - o.t / 3.0
            for j = -1, 1 do
                local px, py, pz = W3(o.x + j * 0.9 + rr(-0.25, 0.25), o.y + rr(-0.5, 0.5), 0.3 + rand() * 0.3)
                FX.emit("smoke", px, py, pz, { n = 1, vel = { j * 0.4, 0.5, 0 }, c0 = { .045 * k + .02, .045 * k + .02, .05 * k + .02 }, c1 = { 0, 0, 0 },
                    s0 = 2.4, s1 = 3.8, l0 = 1.2, l1 = 2.0, r = .5, sp = 1.0, drag = 1.5, grav = { 0, .4, 0 } })
            end
        elseif o.k == "oil" and o.t < 6 and every("oil" .. i, 0.35, dt) then
            -- rainbow sheen drifting over the slick (screen blending adds the thin-film colours)
            local hue = rand()
            local c = { .5 + .5 * sin(hue * 6.28), .5 + .5 * sin(hue * 6.28 + 2.1), .5 + .5 * sin(hue * 6.28 + 4.2) }
            local px, py, pz = W3(o.x + rr(-0.35, 0.35), o.y + rr(-0.5, 0.5), 0.12)
            FX.emit("ring", px, py, pz, { n = 1, c0 = { c[1] * .12, c[2] * .12, c[3] * .12 }, c1 = { 0, 0, 0 }, s0 = 1.2, s1 = 2.2, l0 = .8, l1 = 1.4, r = .05, sp = .1, flat = true })
        elseif o.k == "crater" and o.t < 3 and every("cr" .. i, 0.15, dt) then
            local px, py, pz = W3(o.x + rr(-0.2, 0.2), o.y, 0.1)
            FX.emit("smoke", px, py, pz, { n = 1, vel = { 0, 0.8, 0 }, c0 = { .14, .14, .14 }, c1 = { 0, 0, 0 }, s0 = .8, s1 = 1.3, l0 = 1, l1 = 1.6, r = .2, sp = .5, grav = { 0, .8, 0 } })
        end
    end
    -- burning wrecks left by explosions
    for i = #SFX.fires, 1, -1 do
        local f = SFX.fires[i]
        f.t = f.t + dt
        if f.t > f.life or f.y < P.y - 14 then table.remove(SFX.fires, i)
        elseif every("bf" .. i, 0.07, dt) then
            local k = 1 - f.t / f.life
            local px, py, pz = W3(f.x + rr(-0.15, 0.15), f.y + rr(-0.2, 0.2), 0.15)
            FX.fire(px, py, pz, 0.6 * k, 0.8)
            FX.smoke(px, py + 0.3, pz, 0.35 * k + 0.1, { 0, 1.0, 0 }, 0.25, 1.2)
        end
    end
end
function G.sh_fx_reset() SFX.fires = {}; SFX.t = {}; SFX.drip = 0 end
------------------------------------------------------------------ course
-- The road is a list of segments: { length, centre x, half width, island half width, kind }. kind: "road", "bridge"
-- (water both sides, guard rails), "river" (boat), "dock" (the boathouse ramp between road and river).
-- Centre, width and island ease between segments. The course loops; each loop is a new season.
local SEG = {
    { 60, 0, 3.0, 0, "road" }, { 40, 0, 3.0, 0, "road" }, { 50, 1.5, 2.6, 0, "road" }, { 40, -1.0, 3.4, 0, "road" },
    { 30, 0, 4.6, 1.2, "road" }, { 60, 0, 5.2, 1.8, "road" }, { 30, 0, 3.2, 0, "road" },          -- the fork
    { 50, -1.5, 2.6, 0, "road" }, { 40, 0, 2.2, 0, "bridge" }, { 30, 0, 2.6, 0, "road" },
    { 60, 2.0, 3.0, 0, "road" }, { 40, 0, 2.6, 0, "road" }, { 14, 0, 2.6, 0, "dock" },               -- into the boathouse
    { 80, 0, 3.6, 0, "river" }, { 60, 2.5, 3.2, 0, "river" }, { 60, -2.0, 4.0, 1.4, "river" }, { 60, 0, 3.4, 0, "river" },
    { 14, 0, 2.6, 0, "dock" },                                                                      -- back on land
    { 50, 0, 3.0, 0, "road" }, { 40, -2.0, 2.4, 0, "road" }, { 50, 0, 4.8, 1.4, "road" }, { 40, 0, 3.0, 0, "road" },
    { 40, 1.8, 2.4, 0, "bridge" }, { 50, 0, 3.0, 0, "road" },
}
local START, TOTAL = {}, 0
for i, s in ipairs(SEG) do START[i] = TOTAL; TOTAL = TOTAL + s[1] end
G.TOTAL = TOTAL
local function smooth(t) return t * t * (3 - 2 * t) end
-- course at distance y: centre, half width, island half width, kind
local function course(y)
    local yy = y % TOTAL
    local i = 1
    while i < #SEG and START[i + 1] <= yy do i = i + 1 end
    local s, p = SEG[i], SEG[i == 1 and #SEG or i - 1]
    local t = smooth(clamp((yy - START[i]) / min(14, s[1]), 0, 1))
    return lerp(p[2], s[2], t), lerp(p[3], s[3], t), lerp(p[4], s[4], t), s[5], i
end
G.course = course
-- is (x, y) on drivable surface for this vehicle mode? returns false when off the road / out of the river
local function on_surface(x, y, mode)
    local cx, hw, isl, kind = course(y)
    local d = abs(x - cx)
    if d > hw or d < isl then return false end
    if mode == "car" then return kind ~= "river" end
    return kind == "river" or kind == "dock"
end
G.on_surface = on_surface
------------------------------------------------------------------ vehicles
-- half sizes (x, y) for the collision boxes; they match the meshes
local DIM = { int = { .4, .76 }, boat = { .42, .88 }, civ = { .4, .75 }, truck = { .48, 1.25 }, van = { .5, 1.4 }, sw = { .44, .8 },
    rl = { .48, .86 }, enf = { .42, 1.06 }, eboat = { .5, .95 }, dumper = { .5, .95 }, heli = { .5, .7 } }
G.DIM = DIM
local PTS = { sw = 500, rl = 500, enf = 500, heli = 1500, eboat = 700, dumper = 700 }
local P = { x = 0, y = 0, v = 0, vx = 0, mode = "car", alive = true, inv = 0, weapon = nil, ammo = 0 }
G.P = P
G.EN, G.SHOTS, G.ESHOT, G.DROPS, G.BOMBS = {}, {}, {}, {}, {}
local VMAX, VMIN = 26, 0
local function pdim() return P.mode == "car" and DIM.int or DIM.boat end
G.pdim = pdim
local function overlap(ax, ay, ad, bx, by, bd) return abs(ax - bx) < ad[1] + bd[1] and abs(ay - by) < ad[2] + bd[2] end
-- a vehicle box is on the surface when all four corners are
local function box_on(x, y, d, mode)
    local on = G.on_surface
    return on(x - d[1] * 0.8, y - d[2] * 0.7, mode) and on(x + d[1] * 0.8, y - d[2] * 0.7, mode) and on(x - d[1] * 0.8, y + d[2] * 0.7, mode) and on(x + d[1] * 0.8, y + d[2] * 0.7, mode)
end
G.box_on = box_on
-- a lane position that stays on the surface from y to y + ahead (the car keeps rolling while it is protected).
-- The old respawn used the course centre line, which is the grass median wherever the road splits round an island.
local function safe_x(y, x, mode, ahead)
    local cx, hw, isl = G.course(y)
    local d = (mode == "car") and DIM.int or DIM.boat
    local pref = (x or cx) < cx and -1 or 1
    -- candidate = { side, a }: x = centre + side * (island + (half width - island) * a); side 0 = centre line
    local function at(c, h, i, cand) if cand[1] == 0 then return c end; return c + cand[1] * (i + (h - i) * cand[2]) end
    local cands = { { 0, 0 }, { pref, 0.5 }, { -pref, 0.5 }, { pref, 0.3 }, { -pref, 0.3 }, { pref, 0.7 }, { -pref, 0.7 } }
    for _, cand in ipairs(cands) do
        local ok = true
        for dy = 0, ahead or 0, 0.5 do
            local c2, h2, i2 = G.course(y + dy)
            if not box_on(at(c2, h2, i2, cand), y + dy, d, mode) then ok = false; break end
        end
        if ok then return at(cx, hw, isl, cand), cand end
    end
    return at(cx, hw, isl, { pref, 0.5 }), { pref, 0.5 }
end
G.safe_x = safe_x
-- which vehicle fits at y: the boat whenever any part of its length would be over the river (it may sit on the dock)
function G.mode_at(y)
    for _, dy in ipairs({ -DIM.boat[2], 0, DIM.boat[2] }) do
        local _, _, _, k = G.course(y + dy); if k == "river" then return "boat" end
    end
    return "car"
end
function G.new_game_sim()
    G.score = 0; G.free = 60; G.cars = 0; G.next_car = 10000; G.freeze = 0; G.out = false
    P.x, P.y, P.v, P.vx, P.mode, P.alive, P.inv, P.weapon, P.ammo = 0, 4, 10, 0, "car", true, 2, nil, 0
    G.EN, G.SHOTS, G.ESHOT, G.DROPS, G.BOMBS = {}, {}, {}, {}, {}
    G.spawn_t = 2; G.van_at = 260; G.heli_at = 520; G.lap = 1; G.dist_acc = 0
    G.phase = "drive"; G.pt = 0; G.weapon_i = 0
    P.x = G.safe_x(P.y, 0, "car", 12); P.swap_t = 9
    G.banner_set("Free Cars For 60 Seconds", 2.5)
end
local function add_pts(n)
    if G.freeze > 0 then return end
    add_score(n)
    if G.score >= G.next_car then G.next_car = G.next_car + 10000; G.cars = G.cars + 1; sfx("extra"); G.banner_set("Extra Car", 1.4) end
end
G.add_pts = add_pts
------------------------------------------------------------------ crashes
local function wreck(e, by_player)
    e.alive = false
    G.boom(WP(e.x, e.y, 0.4), false); sfx("boom")
    if e.k == "civ" or e.k == "truck" then
        if by_player then G.freeze = 6; sfx("penalty"); G.banner_set("Don't Destroy Civilians", 2.0) end
    elseif by_player then add_pts(PTS[e.k] or 300) end
end
local function crash()
    if not P.alive or P.inv > 0 then return end
    P.alive = false; G.phase = "crash"; G.pt = 0
    sfx(P.mode == "car" and "crash" or "splash"); G.boom(WP(P.x, P.y, 0.4), false); G.shake = 0.8
    if P.mode == "boat" then G.spray(WP(P.x, P.y, 0.2), 20) end
end
G.crash = crash
------------------------------------------------------------------ spawning
local function lane_x(y, f) local cx, hw, isl = G.course(y); local side = f < 0 and -1 or 1; return cx + side * (isl + (hw - isl) * abs(f)) end
local function spawn(k, y, f, v)
    local x = lane_x(y, f)
    local e = { k = k, x = x, y = y, v = v, vx = 0, f = f, hp = ({ sw = 2, enf = 3, eboat = 2, dumper = 2, civ = 1, truck = 2, rl = 99, van = 99, heli = 99 })[k] or 1,
        alive = true, t = 0, fire = rr(1.5, 3), slash = 0, spin = 0 }
    if G.box_on(x, y, DIM[k] or DIM.civ, (k == "eboat" or k == "dumper") and "boat" or "car") or k == "heli" then G.EN[#G.EN + 1] = e; return e end
end
local function spawn_traffic()
    local _, _, _, kind = G.course(P.y + 30)
    local boat = kind == "river"
    if (P.mode == "boat") ~= boat then return end
    local r = rand()
    local ahead = rand() < 0.65
    local y = ahead and P.y + rr(26, 32) or P.y - 9
    local f = (rand() < 0.5 and -1 or 1) * rr(0.25, 0.75)
    if boat then
        if r < 0.5 then spawn("eboat", P.y - 9, f, P.v + 4)
        else spawn("dumper", P.y + 28, f, max(4, P.v - 4)) end
        return
    end
    local prog = P.y / 300
    if r < 0.38 then spawn("civ", y, f, ahead and rr(9, 14) or P.v + rr(3, 6))
    elseif r < 0.5 then spawn("truck", y, f, ahead and rr(8, 11) or P.v + 3)
    elseif r < 0.68 then spawn("sw", P.y - 9, f, P.v + rr(4, 6))
    elseif r < 0.84 or prog < 1 then spawn("rl", y, f, ahead and rr(10, 13) or P.v + 4)
    else spawn("enf", P.y - 10, f, P.v + 5) end
end
------------------------------------------------------------------ weapons
local WEAPS = { "smoke", "oil", "missile" }
local WNAME = { smoke = "Smoke Screen", oil = "Oil Slick", missile = "Missiles" }
G.WNAME = WNAME
local function fire_guns()
    if not P.alive or #G.SHOTS >= 8 then return end
    for _, s in ipairs({ -1, 1 }) do G.SHOTS[#G.SHOTS + 1] = { x = P.x + s * 0.18, y = P.y + 0.9, py = P.y + 0.9, d = 0, k = "bullet" }; G.muzzle(P.x + s * 0.18, P.y + 0.9, P.v) end
    sfx("gun")
end
local function fire_special()
    if not P.alive or not P.weapon or P.ammo <= 0 then return end
    P.ammo = P.ammo - 1
    if P.weapon == "missile" then G.SHOTS[#G.SHOTS + 1] = { x = P.x, y = P.y + 0.9, py = P.y + 0.9, d = 0, k = "missile" }; sfx("missile")
    elseif P.weapon == "oil" then G.DROPS[#G.DROPS + 1] = { k = "oil", x = P.x, y = P.y - 1.2, t = 0, rot = rr(0, 360) }; sfx("oil")
    else G.DROPS[#G.DROPS + 1] = { k = "smoke", x = P.x, y = P.y - 1.2, t = 0 }; sfx("smoke"); G.smoke(WP(P.x, P.y - 1.2, 0.5), 18) end
    if P.ammo <= 0 then P.weapon = nil end
end
------------------------------------------------------------------ enemy AI
local function enemy_step(e, dt)
    e.t = e.t + dt
    local cx, hw, isl = G.course(e.y)
    local d = DIM[e.k] or DIM.civ
    if e.spin > 0 then
        -- spinning out on oil / blinded by smoke: drift off and crash
        e.spin = e.spin - dt; e.x = e.x + e.vx * dt; e.v = max(0, e.v - 10 * dt)
        e.y = e.y + e.v * dt
        if not G.box_on(e.x, e.y, d, "car") then wreck(e, true) end
        return
    end
    local tx = lane_x(e.y, e.f)
    if e.k == "sw" or e.k == "rl" or e.k == "enf" then
        -- hunters pull alongside the Interceptor
        local side = (e.x < P.x) and -1 or 1
        if abs(e.y - P.y) < 6 and P.alive then
            tx = P.x + side * (e.k == "rl" and 0.7 or 0.95)
            e.v = e.v + clamp((P.v + (P.y - e.y) * 1.5) - e.v, -8, 8) * dt * 2
        end
        if e.k == "sw" and P.alive and abs(e.y - P.y) < 0.6 and abs(abs(e.x - P.x) - 0.9) < 0.2 then
            -- the Switch Blade's tyre slashers
            e.slash = e.slash + dt
            if e.slash > 0.5 then crash() end
        else e.slash = 0 end
        if e.k == "enf" then
            e.fire = e.fire - dt
            if e.fire <= 0 and P.alive and abs(e.y - P.y) < 0.8 then
                e.fire = rr(1.6, 2.4); sfx("gun"); G.muzzle(e.x + ((P.x > e.x) and 0.45 or -0.45), e.y, e.v, (P.x > e.x) and 1 or -1)
                G.ESHOT[#G.ESHOT + 1] = { x = e.x, y = e.y, vx = (P.x > e.x) and 9 or -9, vy = 0, life = 0.4, k = "bullet" }
            end
        end
    elseif e.k == "heli" then
        -- the Mad Bomber hovers ahead and drops bombs on the road in front of you
        e.y = P.y + 9 + 1.5 * sin(e.t * 0.8); e.x = e.x + (P.x - e.x) * min(1, dt * 1.2)
        e.fire = e.fire - dt
        if e.fire <= 0 and P.alive then e.fire = rr(1.3, 2.0); G.BOMBS[#G.BOMBS + 1] = { x = e.x, y = e.y - 1, t = 0, T = 0.9 }; sfx("bombfall") end
        if e.t > 26 then e.alive = false end
        return
    elseif e.k == "eboat" then
        -- Doctor Torpedo: comes up from behind and fires straight ahead
        e.v = e.v + clamp((P.v + (P.y - 3 - e.y) * 1.2) - e.v, -6, 6) * dt
        tx = P.x
        e.fire = e.fire - dt
        if e.fire <= 0 and P.alive and e.y < P.y and abs(e.x - P.x) < 0.6 then e.fire = rr(2, 3); G.ESHOT[#G.ESHOT + 1] = { x = e.x, y = e.y + 1, vx = 0, vy = P.v + 9, life = 3, k = "torpedo" } end
    elseif e.k == "dumper" then
        e.fire = e.fire - dt
        if e.fire <= 0 and abs(e.y - P.y) < 22 then e.fire = rr(1.2, 2); G.DROPS[#G.DROPS + 1] = { k = "barrel", x = e.x, y = e.y - 1.1, t = 0, v = e.v * 0.3 } end
    end
    e.x = e.x + clamp(tx - e.x, -1, 1) * 2.4 * dt + e.vx * dt
    e.vx = e.vx * (1 - min(1, dt * 3))
    e.y = e.y + e.v * dt
    if e.k ~= "heli" and not G.box_on(e.x, e.y, d, (e.k == "eboat" or e.k == "dumper") and "boat" or "car") then wreck(e, e.pushed and e.pushed > 0) end
    e.pushed = max(0, (e.pushed or 0) - dt)
end
------------------------------------------------------------------ main step
function G.drive_step(inp, dt)
    G.pt = G.pt + dt
    G.freeze = max(0, G.freeze - dt)
    if G.free > 0 then G.free = max(0, G.free - dt); if G.free == 0 then G.banner_set("Free Cars Over", 1.5) end end
    local d = pdim()
    if G.phase == "crash" then
        P.v = max(0, P.v - 30 * dt); P.y = P.y + P.v * dt
        if G.pt > 2.0 then
            if G.free <= 0 then
                if G.cars <= 0 then G.out = true; return end
                G.cars = G.cars - 1
            end
            -- a fresh car is set down in a lane: never on the median island (the old code used the centre line, which
            -- is grass wherever the road splits) and on a lane that stays clear for the protected roll-out ahead
            P.mode = G.mode_at(P.y)
            P.x, G.respawn_lane = safe_x(P.y, P.x, P.mode, 2.5 * 8 + 4)
            P.vx, P.v, P.alive, P.inv = 0, 8, true, 2.5
            G.phase = "drive"; G.pt = 0; G.cam_snap = true
            if G.on_respawn then G.on_respawn() end
        end
        return
    end
    if G.phase == "dock" then
        -- inside the weapons van
        local van = G.dock_van
        P.y = van.y; P.x = van.x; P.v = van.v
        van.y = van.y + van.v * dt
        if G.pt > 1.3 then
            G.weapon_i = G.weapon_i % 3 + 1
            P.weapon = WEAPS[G.weapon_i]; P.ammo = P.weapon == "missile" and 4 or 8
            P.y = van.y + 2.3; P.v = van.v + 6; P.inv = 1
            G.phase = "drive"; G.pt = 0; sfx("van"); G.banner_set(WNAME[P.weapon], 1.4)
            van.done = true
        end
        return
    end
    P.inv = max(0, P.inv - dt)
    -- throttle and steering
    if inp.my > 0 then P.v = min(VMAX, P.v + 13 * dt) elseif inp.my < 0 then P.v = max(VMIN, P.v - 22 * dt) end
    P.brk = inp.my < 0 and P.v > 6
    local steer = (3 + P.v * 0.18) * inp.mx
    P.vx = P.vx + (steer - P.vx) * min(1, dt * 10)
    P.x = P.x + P.vx * dt
    P.y = P.y + P.v * dt
    G.dist_acc = G.dist_acc + P.v * dt
    while G.dist_acc >= 1 do G.dist_acc = G.dist_acc - 1; add_pts(5) end
    -- car <-> boat at the boathouse. The swap is keyed to the vehicle's LEADING edge, not its centre: the surface test
    -- checks the box corners, so with a centre-keyed swap the car's nose reached the river (or the boat's bow reached
    -- the road) while still in the old mode, and you crashed / "drowned" on a perfectly clean run through the dock.
    -- The dock itself is valid for both, so after the swap the trailing corners are still on legal ground.
    local _, _, _, kfront = G.course(P.y + d[2] * 0.75)
    if kfront == "river" and P.mode == "car" then
        P.mode = "boat"; d = pdim(); P.swap_t = 0; sfx("splash")
        if G.on_swap then G.on_swap("boat") end
    elseif kfront ~= "river" and kfront ~= "dock" and P.mode == "boat" then
        P.mode = "car"; d = pdim(); P.swap_t = 0; sfx("dock")
        if G.on_swap then G.on_swap("car") end
    end
    local lap = 1 + floor(P.y / G.TOTAL)
    if lap ~= G.lap then G.lap = lap; G.set_season(lap); G.banner_set(({ "Summer", "Autumn", "Winter", "Spring" })[(lap - 1) % 4 + 1], 1.6) end
    -- leaving the road (or the river) wrecks the Interceptor
    if not box_on(P.x, P.y, d, P.mode) then
        if P.inv > 0 then local tx = safe_x(P.y, P.x, P.mode, 3); P.x = P.x + (tx - P.x) * min(1, dt * 4) else crash(); return end
    end
    -- weapons
    if inp.fire then fire_guns() end
    if inp.special then fire_special() end
    -- spawns
    G.spawn_t = G.spawn_t - dt
    local live = 0; for _, e in ipairs(G.EN) do if e.alive then live = live + 1 end end
    if G.spawn_t <= 0 and live < 7 then G.spawn_t = rr(1.0, 2.2) - min(0.6, P.y / 4000); spawn_traffic() end
    if P.y > G.van_at and P.mode == "car" then
        local _, _, _, k2 = G.course(P.y + 28)
        if k2 == "road" then G.van_at = P.y + rr(700, 900); local v = spawn("van", P.y + 28, 0.2, 9); if v then sfx("warn"); G.banner_set("Weapons Van", 1.2) end
        else G.van_at = P.y + 60 end
    end
    if P.y > G.heli_at and P.mode == "car" then G.heli_at = P.y + rr(500, 700); local h = spawn("heli", P.y + 14, 0, P.v); if h then h.x = P.x; sfx("heli"); G.banner_set("Mad Bomber", 1.2) end end
    -- enemies
    for _, e in ipairs(G.EN) do if e.alive then enemy_step(e, dt) end end
    -- vehicle contact: bumping trades sideways shoves; a car shoved off the road is wrecked (you get the points)
    for _, e in ipairs(G.EN) do
        if e.alive and e.k ~= "heli" and P.alive and P.inv <= 0 and overlap(P.x, P.y, d, e.x, e.y, DIM[e.k]) then
            if e.k == "van" then
                if P.y < e.y - 1.0 and abs(P.x - e.x) < 0.35 and not e.done then G.phase = "dock"; G.pt = 0; G.dock_van = e; sfx("dock"); return end
            end
            local side = (e.x > P.x) and 1 or -1
            local heavy = (e.k == "rl" or e.k == "truck" or e.k == "van") and 1.6 or 1
            e.vx = e.vx + side * 5 / heavy; P.vx = P.vx - side * 3 * heavy
            e.x = e.x + side * 0.06; P.x = P.x - side * 0.06
            if abs(P.y - e.y) > (d[2] + DIM[e.k][2]) * 0.8 then
                -- rear-ended: speeds swap a little
                if P.y < e.y then e.v = e.v + 2; P.v = P.v * 0.7 else P.v = P.v + 2; e.v = e.v * 0.7 end
            end
            e.pushed = 1.0
            if G.SHAKE_OK ~= false then G.shake = max(G.shake, 0.2) end
            sfx("hit")
        end
    end
    -- player shots (swept) and missiles
    for i = #G.SHOTS, 1, -1 do
        local s = G.SHOTS[i]
        s.py = s.y
        local sp = (s.k == "missile" and 30 or 44) + P.v
        if s.k == "missile" then
            -- missiles lock on to the Mad Bomber
            for _, e in ipairs(G.EN) do if e.alive and e.k == "heli" then s.x = s.x + clamp(e.x - s.x, -1, 1) * 6 * dt end end
            -- exhaust flame + smoke trail: G.sh_frame_fx
        end
        s.y = s.y + sp * dt; s.d = s.d + sp * dt
        local hit = false
        for _, e in ipairs(G.EN) do
            if e.alive and not hit then
                local ed = DIM[e.k] or DIM.civ
                if abs(s.x - e.x) < ed[1] + 0.05 and s.y > e.y - ed[2] and s.py < e.y + ed[2] then
                    if e.k == "heli" then if s.k == "missile" then e.alive = false; add_pts(PTS.heli); sfx("boom"); G.boom(WP(e.x, e.y, 3), true); hit = true end
                    elseif e.k == "van" then hit = true
                    else
                        hit = true
                        if s.k == "missile" then wreck(e, true)
                        elseif e.k == "rl" then G.sparks(WP(s.x, e.y - ed[2], 0.4), 4); sfx("hit")      -- Road Lord is bulletproof
                        else e.hp = e.hp - 1; G.sparks(WP(s.x, s.y, 0.4), 4); if e.hp <= 0 then wreck(e, true) else sfx("hit") end end
                    end
                end
            end
        end
        if hit or s.d > (s.k == "missile" and 30 or 16) then table.remove(G.SHOTS, i) end
    end
    -- enemy shots / torpedoes
    for i = #G.ESHOT, 1, -1 do
        local s = G.ESHOT[i]
        s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt; s.life = s.life - dt
        if P.alive and P.inv <= 0 and abs(s.x - P.x) < d[1] and abs(s.y - P.y) < d[2] then crash(); table.remove(G.ESHOT, i)
        elseif s.life <= 0 then table.remove(G.ESHOT, i) end
    end
    -- bombs from the helicopter
    for i = #G.BOMBS, 1, -1 do
        local b = G.BOMBS[i]
        b.t = b.t + dt; b.y = b.y + P.v * 0.2 * dt
        if b.t >= b.T then
            table.remove(G.BOMBS, i); sfx("boom"); G.boom(WP(b.x, b.y, 0.2), false)
            G.DROPS[#G.DROPS + 1] = { k = "crater", x = b.x, y = b.y, t = 0 }
            if P.alive and P.inv <= 0 and abs(b.x - P.x) < 0.7 and abs(b.y - P.y) < 0.9 then crash() end
        end
    end
    -- drops: oil and smoke catch enemies behind you, barrels and craters catch you
    for i = #G.DROPS, 1, -1 do
        local o = G.DROPS[i]
        o.t = o.t + dt
        if o.k == "barrel" then o.y = o.y + (o.v or 0) * dt end
        if o.k == "oil" or o.k == "smoke" then
            for _, e in ipairs(G.EN) do
                if e.alive and e.spin <= 0 and e.k ~= "heli" and e.k ~= "van" and abs(e.x - o.x) < (o.k == "smoke" and 1.2 or 0.8) and abs(e.y - o.y) < 1.2 then
                    e.spin = 2; e.vx = (rand() < 0.5 and -1 or 1) * rr(2.5, 4); e.pushed = 2
                end
            end
        elseif P.alive and P.inv <= 0 and abs(o.x - P.x) < d[1] + 0.25 and abs(o.y - P.y) < d[2] + 0.25 then
            if o.k == "barrel" then crash()
            elseif o.k == "crater" and P.mode == "car" then crash() end
        end
        if o.y < P.y - 14 or o.t > 20 then table.remove(G.DROPS, i) end
    end
    -- cull
    for i = #G.EN, 1, -1 do local e = G.EN[i]; if not e.alive or e.y < P.y - 16 or e.y > P.y + 45 then table.remove(G.EN, i) end end
end
G.boom_fx, G.spray, G.smoke, G.puff, G.sparks, G.boom, G.flash = boom, spray, smoke, puff, sparks, boom, flash
------------------------------------------------------------------ world nodes
local function V(x, y, z) return vec3(x, y, z) end
G.shake = 0
local RIG = {
    int = { "int_body", "int_glass", "int_wheel", "int_gun" }, boat = { "boat_hull", "boat_deck" },
    civ = { "civ_body", "civ_glass", "civ_wheel" }, truck = { "truck_cab", "truck_box", "truck_wheel" }, van = { "van_box", "van_ramp", "truck_wheel" },
    sw = { "sw_body", "sw_glass", "civ_wheel", "sw_blade" }, rl = { "rl_body", "rl_glass", "rl_plate", "civ_wheel" },
    enf = { "enf_body", "enf_glass", "enf_wheel" }, eboat = { "eboat_hull", "eboat_deck" }, dumper = { "eboat_hull", "eboat_deck", "barrel" },
    heli = { "heli_body", "heli_glass", "heli_rotor" },
}
local ALLM = {}
for _, list in pairs(RIG) do for _, n in ipairs(list) do ALLM[n] = true end end
for _, n in ipairs({ "road", "curb", "water", "bank", "rail", "tree_trunk", "tree_top", "pine", "bush", "house_wall", "house_roof", "boathouse",
    "bullet", "missile", "bomb", "oil", "crater", "barrel", "torpedo", "shadow" }) do ALLM[n] = true end
local W = {}
local function build_world()
    W.ground = clone("ground", HIDE, V(90, 1, 90))
end
function G.reset_world() G.set_season(1) end
local function pose(list, x, y, h, yaw, roll)
    for _, mname in ipairs(list) do
        local n = P_get(mname); n:set_position(WP(x, y, h or 0)); n:set_rotation(V(0, yaw or 0, roll or 0))
    end
end
local function hash(i) local h = (i * 2654435761) % 4294967296; return (h % 10007) / 10007 end
local function slab(name, x0, x1, y, len, ang, h, sx)
    len = len * 1.1
    local n = P_get(name); n:set_position(WP((x0 + x1) / 2, y, (h or 0) + (floor(y / 2) % 2) * 0.0015)); n:set_scale(V((x1 - x0) * (sx or 1), 1, len)); n:set_rotation(V(0, ang, 0))
end
local function render_world(dt)
    for mname in pairs(ALLM) do P_begin(mname) end
    local P = G.P
    local cy = P.y
    W.ground:set_position(WP(P.x, cy + 10, 0))
    -- road / river slices (2 units each)
    local y0 = floor((cy - 12) / 2) * 2
    for y = y0, cy + 48, 2 do
        local cx, hw, isl, kind, si = G.course(y + 1)
        local ca, ha, ia = G.course(y)
        local cb, hb, ib = G.course(y + 2)
        local yc = y + 1
        -- each strip runs between its own edge positions at both ends of the slice, so curves and island
        -- splits stay continuous instead of stepping
        local function strip(name, fa0, fa1, h, sx)
            local x0a, x1a = fa0(ca, ha, ia), fa1(ca, ha, ia)
            local x0b, x1b = fa0(cb, hb, ib), fa1(cb, hb, ib)
            if x1a - x0a < 0.01 and x1b - x0b < 0.01 then return end
            local ang = -math.deg(math.atan(((x0b + x1b) - (x0a + x1a)) / 4))
            local w = ((x1a - x0a) + (x1b - x0b)) / 2
            local m = (x0a + x1a + x0b + x1b) / 4
            slab(name, m - w / 2, m + w / 2, yc, 2.04, ang, h, sx)
        end
        local L0 = function(c, h) return c - h end
        local R0 = function(c, h) return c + h end
        local IL = function(c, h, i) return c - i end
        local IR = function(c, h, i) return c + i end
        local off = function(f, d) return function(c, h, i) return f(c, h, i) + d end end
        local ang = -math.deg(math.atan((cb - ca) / 2))
        if kind == "river" then
            strip("water", L0, R0, 0)
            strip("bank", off(L0, -0.6), L0, 0.004); strip("bank", R0, off(R0, 0.6), 0.004)
            if isl > 0 then strip("bank", IL, IR, 0.004) end
        else
            if kind == "bridge" then
                slab("water", cx - 14, cx + 14, yc, 2.04, 0, -0.03)
                strip("rail", off(L0, -0.05), off(L0, 0.03), 0, 12); strip("rail", off(R0, -0.03), off(R0, 0.05), 0, 12)
            elseif kind == "dock" then
                strip("water", L0, R0, -0.05)
            end
            if isl > 0.05 or (ia or 0) > 0.05 or (ib or 0) > 0.05 then
                strip("road", L0, IL, 0.002); strip("road", IR, R0, 0.002)
                strip("curb", IL, off(IL, 0.15), 0.004); strip("curb", off(IR, -0.15), IR, 0.004)
            else strip("road", L0, R0, kind == "dock" and 0.02 or 0.002) end
            if kind ~= "bridge" then strip("curb", off(L0, -0.15), L0, 0.004); strip("curb", R0, off(R0, 0.15), 0.004) end
        end
        -- scenery beside the road (deterministic per slice)
        local idx = floor(y / 2)
        if kind ~= "bridge" then
            for s = -1, 1, 2 do
                local h = hash(idx * 2 + (s > 0 and 1 or 0))
                local x = cx + s * (hw + 1.6 + h * 7)
                if h < 0.55 then
                    local tp = h < 0.18 and "pine" or "tree"
                    if tp == "pine" then pose({ "pine" }, x, yc, 0, 0) else pose({ "tree_trunk", "tree_top" }, x, yc, 0, h * 900) end
                elseif h < 0.75 then pose({ "bush" }, x, yc, 0, h * 900)
                elseif h > 0.97 and kind == "road" then pose({ "house_wall", "house_roof" }, cx + s * (hw + 5.5), yc, 0, 0) end
            end
        end
        if kind == "dock" and G.course(y - 1) ~= nil then
            local _, _, _, kp = G.course(y - 1)
            if kp ~= "dock" then pose({ "boathouse" }, cx, y + 1, 0, 0) end
        end
    end
    -- drops
    for _, o in ipairs(G.DROPS) do
        if o.k == "oil" then
            -- the slick spreads out as it hits the road, then lies as a glossy puddle
            local n = P_get("oil"); local sp = 0.3 + 0.7 * (1 - (1 - clamp(o.t / 0.45, 0, 1)) ^ 3)
            n:set_position(WP(o.x, o.y, 0.01)); n:set_scale(V(sp, 1, sp)); n:set_rotation(V(0, o.rot or 0, 0))
        elseif o.k == "crater" then local n = P_get("crater"); n:set_position(WP(o.x, o.y, 0.012)); n:set_scale(V(1, 1, 1)); n:set_rotation(V(0, 0, 0))
        elseif o.k == "barrel" then local n = P_get("barrel"); n:set_position(WP(o.x, o.y, -0.12 + 0.04 * sin(o.t * 4))); n:set_rotation(V(o.t * 120, 0, 0))
        elseif o.k == "smoke" and o.t < 2.5 and rand() < 0.3 then G.smoke(WP(o.x + rr(-0.6, 0.6), o.y, 0.4), 2) end
    end
    -- vehicles
    for _, e in ipairs(G.EN) do
        local yaw = -math.deg(math.atan(e.vx * 0.06)) + (e.spin > 0 and e.t * 400 or 0)
        if e.k == "heli" then
            pose({ "heli_body", "heli_glass" }, e.x, e.y, 3.0, 180 + 8 * sin(e.t))
            local r = P_get("heli_rotor"); r:set_position(WP(e.x, e.y, 3.0)); r:set_rotation(V(0, G.t * 1400 % 360, 0))
            local sh = P_get("shadow"); sh:set_position(WP(e.x + 0.8, e.y - 0.6, 0.01)); sh:set_scale(V(0.95, 1, 1.25))
        else
            local h = (e.k == "eboat" or e.k == "dumper") and (-0.12 + 0.03 * sin(e.t * 5)) or 0
            pose(RIG[e.k], e.x, e.y, h, yaw)
            if e.k == "sw" and e.slash > 0 then for _, n in ipairs({ P_get("sw_blade"), P_get("sw_blade") }) do end end
            local sh = P_get("shadow"); local d = G.DIM[e.k] or G.DIM.civ
            sh:set_position(WP(e.x + 0.08, e.y - 0.08, 0.008)); sh:set_scale(V(d[1] * 2.2, 1, d[2] * 2.1))
        end
    end
    -- the Interceptor (flickers while protected)
    if (P.alive or G.phase == "dock") and G.phase ~= "dock" and (P.inv <= 0 or (G.t * 12) % 2 < 1.4) then
        local yaw = -math.deg(math.atan(P.vx * 0.05))
        -- dock swap: the boat settles into the water with a dip, the car rises out onto the ramp
        P.swap_t = (P.swap_t or 9) + dt
        local sw = clamp(P.swap_t / 0.45, 0, 1)
        if P.mode == "car" then pose(RIG.int, P.x, P.y, -0.12 * (1 - sw), yaw, P.vx * 1.2)
        else pose(RIG.boat, P.x, P.y, -0.12 + 0.03 * sin(G.t * 6) - 0.1 * sin(PI * sw) * (1 - sw * 0.5), yaw, P.vx * 2 + 6 * sin(PI * sw) * (1 - sw)) end
        local sh = P_get("shadow"); local d = G.pdim(); sh:set_position(WP(P.x + 0.08, P.y - 0.08, 0.008)); sh:set_scale(V(d[1] * 2.2, 1, d[2] * 2.1))
    end
    -- shots
    for _, s in ipairs(G.SHOTS) do local n = P_get(s.k); n:set_position(WP(s.x, s.y, 0)) end
    for _, s in ipairs(G.ESHOT) do local n = P_get(s.k); n:set_position(WP(s.x, s.y, s.k == "torpedo" and -0.15 or 0)); n:set_rotation(V(0, s.vx ~= 0 and 90 or 0, 0)) end
    for _, b in ipairs(G.BOMBS) do local n = P_get("bomb"); n:set_position(WP(b.x, b.y, 3.0 * (1 - b.t / b.T) + 0.1)) end
    for mname in pairs(ALLM) do P_end(mname) end
    G.sh_frame_fx(dt)
end

------------------------------------------------------------------ camera: high chase view up the road
local function update_camera(dt)
    local P = G.P
    local c = G.cam
    local cx = G.course(P.y + 6)
    local tx = lerp(cx, P.x, 0.55)
    local k = G.cam_snap and 1 or (1 - math.exp(-3 * dt)); G.cam_snap = false
    c.x = c.x + (tx - c.x) * k
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.3 * SET:shake_scale()
    cam:set_position(WP(c.x + a * sin(G.t * 53), P.y - 7.5 + a * cos(G.t * 61), 10.0))
    cam:look_at(WP(c.x, P.y + 4.2, 0))
end

------------------------------------------------------------------ collider debug overlay (F3)
G.DBG = { on = false, pool = {}, used = 0, w = 0.04 }
local DC = { me = { .2, 1, .3 }, enemy = { 1, .25, .2 }, civ = { .3, .8, 1 }, edge = { .4, .7, 1 }, shot = { 1, .9, .3 }, drop = { 1, .5, .1 } }
function G.dbg_bar(p0, p1, col)
    local D = G.DBG
    D.used = D.used + 1
    local b = D.pool[D.used]
    if not b then
        if #D.pool >= 2500 then return end
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
local function dbox(x, y, hx, hy, col, h)
    h = h or 0.5
    local a, b, c, d = WP(x - hx, y - hy, h), WP(x + hx, y - hy, h), WP(x + hx, y + hy, h), WP(x - hx, y + hy, h)
    G.dbg_bar(a, b, col); G.dbg_bar(b, c, col); G.dbg_bar(c, d, col); G.dbg_bar(d, a, col)
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and G.state ~= "title" then
        local P = G.P
        -- drivable edges
        for y = floor(P.y - 6), P.y + 30, 1 do
            local cx, hw, isl = G.course(y); local cx2, hw2, isl2 = G.course(y + 1)
            G.dbg_bar(WP(cx - hw, y, 0.1), WP(cx2 - hw2, y + 1, 0.1), DC.edge); G.dbg_bar(WP(cx + hw, y, 0.1), WP(cx2 + hw2, y + 1, 0.1), DC.edge)
            if isl > 0.05 then G.dbg_bar(WP(cx - isl, y, 0.1), WP(cx2 - isl2, y + 1, 0.1), DC.edge); G.dbg_bar(WP(cx + isl, y, 0.1), WP(cx2 + isl2, y + 1, 0.1), DC.edge) end
        end
        if P.alive then local d = G.pdim(); dbox(P.x, P.y, d[1], d[2], DC.me) end
        for _, e in ipairs(G.EN) do local d = G.DIM[e.k] or G.DIM.civ; dbox(e.x, e.y, d[1], d[2], (e.k == "civ" or e.k == "truck" or e.k == "van") and DC.civ or DC.enemy, e.k == "heli" and 3 or 0.5) end
        for _, s in ipairs(G.SHOTS) do G.dbg_bar(WP(s.x, s.py, 0.4), WP(s.x, s.y, 0.4), DC.shot) end
        for _, s in ipairs(G.ESHOT) do dbox(s.x, s.y, 0.1, 0.1, DC.enemy, 0.4) end
        for _, o in ipairs(G.DROPS) do if o.k ~= "smoke" then dbox(o.x, o.y, o.k == "oil" and 0.8 or 0.25, o.k == "oil" and 1.2 or 0.25, DC.drop, 0.1) end end
        for _, b in ipairs(G.BOMBS) do dbox(b.x, b.y, 0.7, 0.9, DC.enemy, 0.1) end
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
local function button(id, label, cx, cy, vis, bw)
    local w, h = (bw or 340) * US, 60 * US
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
    local P = G.P
    panel("lp", 20 * US, 20 * US, LW, 250 * US, play, 0.5)
    text("l1", "Score", 40 * US, 30 * US, LW - 40 * US, 30 * US, 0.9, RED, "left", play)
    text("l2", pad6(G.score), 40 * US, 58 * US, LW - 40 * US, 52 * US, 1.8, G.freeze > 0 and DIM or WHITE, "left", play)
    text("l3", "High Score  " .. pad6(max(G.hiscore, G.score)), 40 * US, 116 * US, LW - 40 * US, 34 * US, 0.9, CYAN, "left", play)
    text("l4", G.free > 0 and ("Free Cars  " .. math.ceil(G.free)) or ("Spare Cars  " .. tostring(G.cars)), 40 * US, 160 * US, LW - 40 * US, 38 * US, 1.15, GOLD, "left", play)
    text("l5", string.format("Speed  %d", floor(P.v * 8)), 40 * US, 206 * US, LW - 40 * US, 36 * US, 1.0, DIM, "left", play)
    panel("rp", SW - LW - 20 * US, 20 * US, LW, 130 * US, play, 0.5)
    text("r1", "Weapon", SW - LW, 30 * US, LW - 40 * US, 30 * US, 0.9, RED, "right", play)
    text("r2", P.weapon and (G.WNAME[P.weapon] .. "  x" .. P.ammo) or "Machine Guns", SW - LW, 64 * US, LW - 40 * US, 40 * US, 1.15, WHITE, "right", play)
    text("r3", P.mode == "boat" and "Boat" or "Car", SW - LW, 104 * US, LW - 40 * US, 34 * US, 0.9, DIM, "right", play)
    G.banner.t = (G.banner.t or 0) - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    text("ban", G.banner.text or "", 0, SH * 0.16, SW, 80 * US, 2.2, { 1, .88, .45, ba }, "center", play and G.banner.t > 0)
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 470 * US, SH * 0.06, 940 * US, SH * 0.66, title, 0.62)
    text("t_title", "Spy Hunter Remix", 0, SH * 0.08, SW, 130 * US, 4.2, { 1, .55, .3, 1 }, "center", title)
    text("t_sub", "Drive the Interceptor, destroy the enemy agents, spare the civilians", 0, SH * 0.08 + 120 * US, SW, 40 * US, 1.0, DIM, "center", title)
    local CL = { "A / D / Left / Right: steer  ·  W / Up: accelerate  ·  S / Down: brake",
        "Space / J / Left Click: machine guns (one burst per press)  ·  Shift / X / Right Click: special weapon",
        "Drive into the back of the red weapons van for smoke, oil or missiles  ·  only missiles stop the helicopter",
        "Leaving the road wrecks your car  ·  P / Esc: pause  ·  O: settings  ·  M: mute  ·  F3: colliders" }
    for i, l in ipairs(CL) do text("t_c" .. i, l, SW / 2 - 460 * US, SH * 0.5 + (i - 1) * 34 * US, 920 * US, 34 * US, 0.88, DIM, "center", title) end
    text("t_hi", "High Score " .. tostring(G.hiscore), 0, SH * 0.5 + 150 * US, SW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, GOLD, "center", pause)
    local over = st == "over" and not G.set_open
    panel("o_bg", SW / 2 - 400 * US, SH * 0.22, 800 * US, SH * 0.56, over, 0.78)
    text("o_t", "Game Over", 0, SH * 0.24, SW, 90 * US, 3.0, RED, "center", over)
    text("o_m", string.format("Distance %d", floor(P.y)), 0, SH * 0.24 + 92 * US, SW, 40 * US, 1.2, DIM, "center", over)
    text("o_s", "Score " .. tostring(G.score), 0, SH * 0.24 + 140 * US, SW, 44 * US, 1.4, WHITE, "center", over)
    local c = {}
    local yb = SH * 0.28
    c.start = button("b_start", "Start (Enter)", SW / 2, yb, title)
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
local function to_title()
    G.state = "title"
    G.new_game_sim(); G.reset_world()
    music("title")
end
G.to_title = to_title
local function new_game()
    G.reset_world(); G.new_game_sim(); G.sh_fx_reset()
    G.state = "play"; G.cam_snap = true
    music("drive"); sfx("start")
end
G.new_game = new_game
local function game_over()
    G.state = "over"; G.over_t = 0
    music(nil); sfx("gameover")
    if G.score > G.hiscore then G.hiscore = G.score; save_hi() end
end
local acc = 0
local mprev = 0
local q = { fire = false, special = false }
local lmouse_prev, rmouse_prev = true, true
local function update(dt)
    flush_mats()
    dt = clamp(dt, 0, 0.1)   -- a negative frame time (timer hitch) would make every damp() explode
    G.t = G.t + dt; G.dt = dt
    local k = { ret = edge("Return"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), qk = edge("Q"), f3 = edge("F3"),
        space = edge("Space"), j = edge("J"), x = edge("X"), sh = edge("LeftShift"), sh2 = edge("RightShift") }
    local ld, rd = false, false
    pcall(function() ld = input.is_left_mouse_down and input.is_left_mouse_down() and true or false end)
    pcall(function() rd = input.is_right_mouse_down and input.is_right_mouse_down() and true or false end)
    local lclick, rclick = ld and not lmouse_prev, rd and not rmouse_prev; lmouse_prev, rmouse_prev = ld, rd
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end; lclick, rclick = false, false end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        if k.ret or k.space or c.start then sfx("click"); new_game()
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click")
        else
            if k.space or k.j or lclick then q.fire = true end
            if k.x or k.sh or k.sh2 or rclick then q.special = true end
        end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.qk or c.quit then to_title() end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then sfx("click"); new_game()
            elseif k.esc or c.title then to_title() end
        end
    end
    st = G.state
    if st == "play" and not G.set_open then
        local mx = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0)
        local my = (any("Up", "W") and 1 or 0) - (any("Down", "S") and 1 or 0)
        if mx ~= 0 and mx ~= mprev and G.P.alive then sfx("steer") end
        mprev = mx
        if G.autoplay then mx, my, q.fire = G.autoplay_fn() end
        local inp = { mx = mx, my = my }
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 4 do
            inp.fire, inp.special = q.fire, q.special; q.fire, q.special = false, false
            G.drive_step(inp, FR)
            acc = acc - FR; n = n + 1
        end
        if acc > FR * 4 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if G.out and G.state == "play" then G.out = false; game_over() end
        G.eng_t = (G.eng_t or 0) - dt
        if G.eng_t <= 0 and G.P.alive then G.eng_t = 0.19; sfx("eng" .. tostring(min(4, floor(G.P.v / 6)))) end
    elseif st == "title" then
        -- attract mode: the car cruises down the road
        local P = G.P
        P.y = P.y + 12 * dt; P.v = 12
        P.mode = G.mode_at(P.y)
        local tx = G.safe_x(P.y, P.x, P.mode, 8); P.x = P.x + (tx - P.x) * min(1, dt * 2)   -- a lane, never the median
        AL = 1
    else AL = 1 end
    render_world(dt)
    update_camera(dt)
    update_lights(dt, G.P.x, G.P.y)
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end
-- debug autopilot for tests/screenshots only: hold the lane centre, dodge cars ahead, fire at hunters
function G.autoplay_fn()
    local P = G.P
    local cx, hw, isl = G.course(P.y + 3)
    local c2, h2, i2 = G.course(P.y + 9)
    local tx = cx
    if isl > 0.05 then tx = cx + (P.x < cx and -1 or 1) * (isl + hw) / 2
    elseif i2 > 0.05 then tx = c2 + (P.x < c2 and -1 or 1) * (i2 + h2) / 2 end
    local van
    for _, e in ipairs(G.EN) do if e.alive and e.k == "van" and not e.done and e.y > P.y then van = e end end
    for _, e in ipairs(G.EN) do if e.alive and e ~= van and e.y > P.y and e.y - P.y < 6 and abs(e.x - tx) < 1.0 then tx = tx + (e.x > tx and -1.1 or 1.1) end end
    if van then tx = van.x end
    G.ap_t = (G.ap_t or 0) + 1
    local mx = clamp((tx - P.x) * 1.5, -1, 1)
    local my = P.v < (van and van.y - P.y < 8 and van.v + 2.5 or 17) and 1 or 0
    if van and van.y - P.y < 8 and P.v > van.v + 4 then my = -1 end
    return mx, my, (G.ap_t % 15 == 0)
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_world()
to_title()
G.update = update; G.SET = SET
hooks { update = update }
pe_log("[SH] ready")
