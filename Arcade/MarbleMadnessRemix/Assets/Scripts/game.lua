-- MARBLE MADNESS REMIX  (PhasmaEngine, Lua)
-- A faithful modern remake of Atari's Marble Madness (1984): guide a marble down six isometric races (Practice,
-- Beginner, Intermediate, Aerial, Silly, Ultimate) to the goal before the clock runs out. Unused time carries over.
-- Steelies push you, Marble Munchers and acid pools eat you, hammers flatten you, long drops shatter you.
-- World: x/z course grid (1 unit cells), y up. Courses run from far (high z) to near (low z).
local PI = math.pi
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
math.randomseed(os and os.time and os.time() or 1942)
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local G = { state = "boot", t = 0 }
_G.MM = G

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
local ss = scene.add_empty_node("MarbleSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "night.hdr")
S("hdr", false); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false); S("dof", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.2)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", false)
S("color_grading", true); S("color_grading_saturation", 1.05); S("color_grading_contrast", 1.04)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "SETTINGS", subtitle = "Marble Madness Remix", file = "Save/settings.cfg", music = true,
    click = function() sfx("click") end, defaults = { master = 0.5 },
    theme = { accent = { 0.35, 0.75, 1, 1 }, accent2 = { 1, 0.55, 0.3, 1 }, text = { 0.86, 0.84, 0.8, 1 }, selected_text = { 1, 0.97, 0.9, 1 } } })
SET:apply()
G.set_open = false

------------------------------------------------------------------ camera
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1600, surf.height or 900
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local VFOV = math.rad(30)
local FOVX = 2 * math.atan(math.tan(VFOV / 2) * SW / SH)
pcall(function() cam:set_fov(math.deg(FOVX)) end)
pcall(function() cam:set_far_plane(600) end)
G.cam = { pos = vec3(0, 30, -30), look = vec3(0, 0, 0) }
G.CAM_YAW = math.rad(35)          -- camera looks along +Z rotated by this yaw (isometric diagonal)
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
    if not n then pe_log("[MM] missing template " .. name); return nil end
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
    marble = { { 1, 1, 1 }, { .02, .02, .03 }, .08, .1 }, steelie = { { .1, .1, .12 }, { 0, 0, 0 }, .15, .9 },
    shadow = { { .02, .02, .03 }, { 0, 0, 0 }, 1 },
    mun_coil = { { .3, .62, .25 }, { .01, .03, .01 }, .45, .3 }, mun_head = { { .35, .68, .28 }, { .01, .03, .01 }, .4, .2 },
    mun_eye = { { .95, .9, .6 }, { .3, .25, .05 }, .3 },
    acid = { { .45, .8, .25 }, { .08, .22, .04 }, .15, 0 },
    ham_post = { { .5, .5, .55 }, { 0, 0, 0 }, .4, .7 }, ham_head = { { .55, .25, .15 }, { .01, 0, 0 }, .55, .1 },
    flag_pole = { { .85, .85, .9 }, { 0, 0, 0 }, .3, .8 }, flag_cloth = { { 1, 1, 1 }, { .15, .15, .15 }, .6 },
    chute = { { .55, .58, .65 }, { 0, 0, 0 }, .3, .8 }, shard = { { .3, .5, .95 }, { .05, .08, .15 }, .1 },
    floor = { { .05, .05, .09 }, { 0, 0, 0 }, 1 },
}
-- slope shade classes: "" flat (bright, warm), 1 falls toward the camera, 2 sideways, 3 falls away (darkest, cooler)
local SHADE = { [""] = { 1.0, 0.98, 0.94 }, ["1"] = { 0.80, 0.80, 0.86 }, ["2"] = { 0.60, 0.60, 0.70 }, ["3"] = { 0.42, 0.42, 0.54 } }
local function paint_templates()
    for k, c in ipairs(G.COURSES) do
        for _, m in ipairs(c.meshes) do
            local col, sc = m:match("_top(%a)(%d?)$")
            if col then
                local t = SHADE[sc] or SHADE[""]
                PAL[m] = { t, col == "G" and { .04, .04, .04 } or { 0, 0, 0 }, sc == "" and .65 or .8 }
            else PAL[m] = { { .9, .9, .95 }, { 0, 0, 0 }, .85 } end
        end
    end
    for name, v in pairs(PAL) do paint(tnode(name), v[1], v[2], v[3], v[4]) end
    mtex(tnode("marble"), "base_color", "Textures/marble.png")
    mtex(tnode("flag_cloth"), "base_color", "Textures/flag.png")
    for k, c in ipairs(G.COURSES) do
        for _, m in ipairs(c.meshes) do
            local col = m:match("_top(%a)%d?$")
            mtex(tnode(m), "base_color", col and ("Textures/c" .. k .. "_" .. col .. ".png") or ("Textures/c" .. k .. "_wall.png"))
        end
    end
    for name in pairs(PAL) do local n = tnode(name); if n then n:set_position(HIDE) end end
end

------------------------------------------------------------------ lights
local LT = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(0.45, -0.8, 0.35), vec3(1.0, 0.97, 0.92), 2.7)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    LT.key = addp(vec3(0, 12, 0), vec3(1.0, 0.95, 0.88), 30, 30)
    LT.fill = addp(vec3(0, 8, 0), vec3(0.7, 0.8, 1.0), 22, 34)
    LT.flash = {}
    for i = 1, 3 do LT.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1 } end
end
G.flash_next = 1
local function flash(p, col, power, life, rad)
    local f = LT.flash[G.flash_next]; G.flash_next = G.flash_next % #LT.flash + 1
    f.t, f.life, f.p, f.col, f.power, f.rad = 0, life or 0.3, p, vec3(col[1], col[2], col[3]), power or 40, rad or 7
end
local function update_lights(dt, p)
    set_point(LT.key, vec3(p.x - 5, p.y + 9, p.z - 4), vec3(1.0, 0.95, 0.88), 30, 30)
    set_point(LT.fill, vec3(p.x + 6, p.y + 5, p.z + 6), vec3(0.7, 0.8, 1.0), 22, 34)
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
-- same signatures as before (p = world vec3); drawn with Scripts/Lib/particles.lua via 02c_fx (G.FX)
local function shatter(p, col)          -- the marble breaks: glass chips, glints, a puff of dust
    col = col or { .4, .6, 1 }
    G.FX.emit("debris", p.x, p.y, p.z, { n = 22, c0 = { col[1] * 1.4, col[2] * 1.4, col[3] * 1.4 }, c1 = { col[1] * .3, col[2] * .3, col[3] * .3 },
        s0 = .12, s1 = .3, l0 = .5, l1 = 1.1, r = .3, sp = 9, drag = 1.2, grav = { 0, -12, 0 }, anim = 0.01 })
    G.FX.sparks(p.x, p.y, p.z, 16, nil, 12)
    G.FX.dust(p.x, p.y, p.z, { .45, .45, .5 }, 1, { 0, .5, 0 }, 1)
    flash(vec3(p.x, p.y + 1, p.z), { .6, .75, 1 }, 40, 0.3, 6)
end
local function sparks(p, n)
    G.FX.sparks(p.x, p.y, p.z, n or 10, nil, 8)
end
local function goo(p)                    -- acid puddle / slinky melt: green vapour
    G.FX.emit("smoke", p.x, p.y, p.z, { n = 6, c0 = { .3, .6, .15 }, c1 = { 0, 0, 0 }, s0 = .8, s1 = 1.5, l0 = .5, l1 = 1.0, r = .4, sp = 2, drag = 2, grav = { 0, 1.5, 0 } })
    G.FX.emit("ember", p.x, p.y, p.z, { n = 10, c0 = { .6, 1.1, .3 }, c1 = { 0, 0, 0 }, s0 = .1, s1 = .2, l0 = .3, l1 = .7, r = .4, sp = 4, drag = 2, grav = { 0, 1.5, 0 } })
end
local function dust(p, n)
    G.FX.dust(p.x, p.y, p.z, { .28, .28, .32 }, clamp((n or 6) / 6, 0.3, 2), { 0, .2, 0 }, 0.8)   -- dim: pale tiles + screen blend
end

------------------------------------------------------------------ score state
G.score, G.hiscore = 0, 0
pcall(function() local s = fs.read("Save/marble_hiscore.txt"); if s then G.hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, "Save/marble_hiscore.txt", tostring(G.hiscore)) end
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
FX.scale = 0.5    -- Marble Madness: the marble is half a unit across
G.fx_light = function(pos, col, power, life, radius) flash(pos, col, power * 0.5, life, radius) end
------------------------------------------------------------------ courses (generated by tools/courses.py, do not edit)
local COURSES = {
    { name = "Practice Race", nx = 24, nz = 64, time = 60, gravity = 1, start = { 17, 59 }, goal = { 15, 3, 19, 7 },
      checks = { { 17, 59 }, { 17, 41 }, { 5, 41 }, { 5, 23 }, { 17, 23 }, { 17, 12 } },
      enemies = {  },
      meshes = { "c1_topA", "c1_topB1", "c1_topW", "c1_topB2", "c1_topG", "c1_wall" },
      rows = {
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;3,3,3,3;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;3,3,3.3,3.3;3,3,3.3,3.3;3,3,3.3,3.3;3,3,3.3,3.3;3,3,3.3,3.3;3,3,3.3,3.3;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;3.3,3.3,3.6,3.6;3.3,3.3,3.6,3.6;3.3,3.3,3.6,3.6;3.3,3.3,3.6,3.6;3.3,3.3,3.6,3.6;3.3,3.3,3.6,3.6;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;3.6,3.6,3.9,3.9;3.6,3.6,3.9,3.9;3.6,3.6,3.9,3.9;3.6,3.6,3.9,3.9;3.6,3.6,3.9,3.9;3.6,3.6,3.9,3.9;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;3.9,3.9,4.2,4.2;3.9,3.9,4.2,4.2;3.9,3.9,4.2,4.2;3.9,3.9,4.2,4.2;3.9,3.9,4.2,4.2;3.9,3.9,4.2,4.2;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;4.2,4.2,4.5,4.5;4.2,4.2,4.5,4.5;4.2,4.2,4.5,4.5;4.2,4.2,4.5,4.5;4.2,4.2,4.5,4.5;4.2,4.2,4.5,4.5;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;4.5,4.5,4.8,4.8;4.5,4.5,4.8,4.8;4.5,4.5,4.8,4.8;4.5,4.5,4.8,4.8;4.5,4.5,4.8,4.8;4.5,4.5,4.8,4.8;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;4.8,4.8,5.1,5.1;4.8,4.8,5.1,5.1;4.8,4.8,5.1,5.1;4.8,4.8,5.1,5.1;4.8,4.8,5.1,5.1;4.8,4.8,5.1,5.1;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;5.1,5.1,5.4,5.4;5.1,5.1,5.4,5.4;5.1,5.1,5.4,5.4;5.1,5.1,5.4,5.4;5.1,5.1,5.4,5.4;5.1,5.1,5.4,5.4;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;5.4,5.4,5.7,5.7;5.4,5.4,5.7,5.7;5.4,5.4,5.7,5.7;5.4,5.4,5.7,5.7;5.4,5.4,5.7,5.7;5.4,5.4,5.7,5.7;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;5.7,5.7,6,6;5.7,5.7,6,6;5.7,5.7,6,6;5.7,5.7,6,6;5.7,5.7,6,6;5.7,5.7,6,6;x;x;x;x",
        "x;x;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,7.667,8,7.667;7.667,7.333,7.667,7.333;7.333,7,7.333,7;7,6.667,7,6.667;6.667,6.333,6.667,6.333;6.333,6,6.333,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;x;x;x;x",
        "x;x;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,7.667,8,7.667;7.667,7.333,7.667,7.333;7.333,7,7.333,7;7,6.667,7,6.667;6.667,6.333,6.667,6.333;6.333,6,6.333,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;x;x;x;x",
        "x;x;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,7.667,8,7.667;7.667,7.333,7.667,7.333;7.333,7,7.333,7;7,6.667,7,6.667;6.667,6.333,6.667,6.333;6.333,6,6.333,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;x;x;x;x",
        "x;x;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,7.667,8,7.667;7.667,7.333,7.667,7.333;7.333,7,7.333,7;7,6.667,7,6.667;6.667,6.333,6.667,6.333;6.333,6,6.333,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;x;x;x;x",
        "x;x;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,7.667,8,7.667;7.667,7.333,7.667,7.333;7.333,7,7.333,7;7,6.667,7,6.667;6.667,6.333,6.667,6.333;6.333,6,6.333,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;x;x;x;x",
        "x;x;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,7.667,8,7.667;7.667,7.333,7.667,7.333;7.333,7,7.333,7;7,6.667,7,6.667;6.667,6.333,6.667,6.333;6.333,6,6.333,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;x;x;x;x",
        "x;x;8,8,8.075,8.075;8,8,8.075,8.075;8,8,8.075,8.075;8,8,8.075,8.075;8,8,8.075,8.075;8,8,8.075,8.075;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;8.075,8.075,8.75,8.75;8.075,8.075,8.75,8.75;8.075,8.075,8.75,8.75;8.075,8.075,8.75,8.75;8.075,8.075,8.75,8.75;8.075,8.075,8.75,8.75;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;8.75,8.75,9.425,9.425;8.75,8.75,9.425,9.425;8.75,8.75,9.425,9.425;8.75,8.75,9.425,9.425;8.75,8.75,9.425,9.425;8.75,8.75,9.425,9.425;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;9.425,9.425,9.5,9.5;9.425,9.425,9.5,9.5;9.425,9.425,9.5,9.5;9.425,9.425,9.5,9.5;9.425,9.425,9.5,9.5;9.425,9.425,9.5,9.5;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;9.5,9.5,9.575,9.575;9.5,9.5,9.575,9.575;9.5,9.5,9.575,9.575;9.5,9.5,9.575,9.575;9.5,9.5,9.575,9.575;9.5,9.5,9.575,9.575;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;9.575,9.575,10.25,10.25;9.575,9.575,10.25,10.25;9.575,9.575,10.25,10.25;9.575,9.575,10.25,10.25;9.575,9.575,10.25,10.25;9.575,9.575,10.25,10.25;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;10.25,10.25,10.925,10.925;10.25,10.25,10.925,10.925;10.25,10.25,10.925,10.925;10.25,10.25,10.925,10.925;10.25,10.25,10.925,10.925;10.25,10.25,10.925,10.925;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;10.925,10.925,11,11;10.925,10.925,11,11;10.925,10.925,11,11;10.925,10.925,11,11;10.925,10.925,11,11;10.925,10.925,11,11;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;11,11,11.075,11.075;11,11,11.075,11.075;11,11,11.075,11.075;11,11,11.075,11.075;11,11,11.075,11.075;11,11,11.075,11.075;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;11.075,11.075,11.75,11.75;11.075,11.075,11.75,11.75;11.075,11.075,11.75,11.75;11.075,11.075,11.75,11.75;11.075,11.075,11.75,11.75;11.075,11.075,11.75,11.75;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;11.75,11.75,12.425,12.425;11.75,11.75,12.425,12.425;11.75,11.75,12.425,12.425;11.75,11.75,12.425,12.425;11.75,11.75,12.425,12.425;11.75,11.75,12.425,12.425;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;12.425,12.425,12.5,12.5;12.425,12.425,12.5,12.5;12.425,12.425,12.5,12.5;12.425,12.425,12.5,12.5;12.425,12.425,12.5,12.5;12.425,12.425,12.5,12.5;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.917,12.5,12.917;12.917,13.333,12.917,13.333;13.333,13.75,13.333,13.75;13.75,14.167,13.75,14.167;14.167,14.583,14.167,14.583;14.583,15,14.583,15;15.8,15.8,15.8,15.8;15.8,15.8,15.8,15.8;15.8,15.8,15.8,15.8;15.8,15.8,15.8,15.8;15.8,15.8,15.8,15.8;15.8,15.8,15.8,15.8;x;x;x;x",
        "x;x;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.917,12.5,12.917;12.917,13.333,12.917,13.333;13.333,13.75,13.333,13.75;13.75,14.167,13.75,14.167;14.167,14.583,14.167,14.583;14.583,15,14.583,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15.8,15.8,15.8,15.8;x;x;x;x",
        "x;x;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.917,12.5,12.917;12.917,13.333,12.917,13.333;13.333,13.75,13.333,13.75;13.75,14.167,13.75,14.167;14.167,14.583,14.167,14.583;14.583,15,14.583,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15.8,15.8,15.8,15.8;x;x;x;x",
        "x;x;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.917,12.5,12.917;12.917,13.333,12.917,13.333;13.333,13.75,13.333,13.75;13.75,14.167,13.75,14.167;14.167,14.583,14.167,14.583;14.583,15,14.583,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15.8,15.8,15.8,15.8;x;x;x;x",
        "x;x;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.917,12.5,12.917;12.917,13.333,12.917,13.333;13.333,13.75,13.333,13.75;13.75,14.167,13.75,14.167;14.167,14.583,14.167,14.583;14.583,15,14.583,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15.8,15.8,15.8,15.8;x;x;x;x",
        "x;x;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.5,12.5,12.5;12.5,12.917,12.5,12.917;12.917,13.333,12.917,13.333;13.333,13.75,13.333,13.75;13.75,14.167,13.75,14.167;14.167,14.583,14.167,14.583;14.583,15,14.583,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15.8,15.8,15.8,15.8;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;15,15,15.5,15.5;15,15,15.5,15.5;15,15,15.5,15.5;15,15,15.5,15.5;15,15,15.5,15.5;15,15,15.5,15.5;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;15.5,15.5,16,16;15.5,15.5,16,16;15.5,15.5,16,16;15.5,15.5,16,16;15.5,15.5,16,16;15.5,15.5,16,16;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;16,16,16.5,16.5;16,16,16.5,16.5;16,16,16.5,16.5;16,16,16.5,16.5;16,16,16.5,16.5;16,16,16.5,16.5;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;16.5,16.5,17,17;16.5,16.5,17,17;16.5,16.5,17,17;16.5,16.5,17,17;16.5,16.5,17,17;16.5,16.5,17,17;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;17,17,17.5,17.5;17,17,17.5,17.5;17,17,17.5,17.5;17,17,17.5,17.5;17,17,17.5,17.5;17,17,17.5,17.5;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;17.5,17.5,18,18;17.5,17.5,18,18;17.5,17.5,18,18;17.5,17.5,18,18;17.5,17.5,18,18;17.5,17.5,18,18;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;18,18,18.5,18.5;18,18,18.5,18.5;18,18,18.5,18.5;18,18,18.5,18.5;18,18,18.5,18.5;18,18,18.5,18.5;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;18.5,18.5,19,19;18.5,18.5,19,19;18.5,18.5,19,19;18.5,18.5,19,19;18.5,18.5,19,19;18.5,18.5,19,19;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;19,19,19.5,19.5;19,19,19.5,19.5;19,19,19.5,19.5;19,19,19.5,19.5;19,19,19.5,19.5;19,19,19.5,19.5;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;19.5,19.5,20,20;19.5,19.5,20,20;19.5,19.5,20,20;19.5,19.5,20,20;19.5,19.5,20,20;19.5,19.5,20,20;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;20,20,20,20;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x" } },
    { name = "Beginner Race", nx = 28, nz = 72, time = 60, gravity = 1, start = { 14, 67 }, goal = { 11, 0, 17, 3 },
      checks = { { 14, 67 }, { 14, 41 }, { 14, 31 }, { 14, 23 }, { 14, 13 }, { 14, 5 } },
      enemies = { { k = "steelie", x = 18.5, z = 32 }, { k = "steelie", x = 8.5, z = 15 } },
      meshes = { "c2_topA", "c2_topB2", "c2_topB3", "c2_topB1", "c2_topB", "c2_topA1", "c2_topW", "c2_topA2", "c2_topG", "c2_wall" },
      rows = {
        "x;x;x;x;x;x;x;x;x;x;x;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;10,9.7,10,9.667;9.7,9.374,9.667,9.333;9.374,9.054,9.333,9;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;8,8,8,8;9.054,9.374,9,9.333;9.374,9.7,9.333,9.667;9.7,10,9.667,10;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;10,9.667,10,9.7;9.667,9.333,9.7,9.374;9.333,9,9.374,9.054;9,8.667,9.054,8.745;8.667,8.333,8.745,8.471;8.333,8,8.471,8.333;8,8.333,8.333,8.471;8.333,8.667,8.471,8.745;8.667,9,8.745,9.054;9,9.333,9.054,9.374;9.333,9.667,9.374,9.7;9.667,10,9.7,10;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;10,9.7,10,9.795;9.7,9.374,9.795,9.491;9.374,9.054,9.491,9.202;9.054,8.745,9.202,8.943;8.745,8.471,8.943,8.745;8.471,8.333,8.745,8.667;8.333,8.471,8.667,8.745;8.471,8.745,8.745,8.943;8.745,9.054,8.943,9.202;9.054,9.374,9.202,9.491;9.374,9.7,9.491,9.795;9.7,10,9.795,10;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;10,9.795,10,9.944;9.795,9.491,9.944,9.667;9.491,9.202,9.667,9.414;9.202,8.943,9.414,9.202;8.943,8.745,9.202,9.054;8.745,8.667,9.054,9;8.667,8.745,9,9.054;8.745,8.943,9.054,9.202;8.943,9.202,9.202,9.414;9.202,9.491,9.414,9.667;9.491,9.795,9.667,9.944;9.795,10,9.944,10;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;10,9.944,10,10;9.944,9.667,10,9.886;9.667,9.414,9.886,9.667;9.414,9.202,9.667,9.491;9.202,9.054,9.491,9.374;9.054,9,9.374,9.333;9,9.054,9.333,9.374;9.054,9.202,9.374,9.491;9.202,9.414,9.491,9.667;9.414,9.667,9.667,9.886;9.667,9.944,9.886,10;9.944,10,10,10;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;10,10,10,10;10,9.886,10,10;9.886,9.667,10,9.944;9.667,9.491,9.944,9.795;9.491,9.374,9.795,9.7;9.374,9.333,9.7,9.667;9.333,9.374,9.667,9.7;9.374,9.491,9.7,9.795;9.491,9.667,9.795,9.944;9.667,9.886,9.944,10;9.886,10,10,10;10,10,10,10;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;10,10,10,10;10,10,10,10;10,9.944,10,10;9.944,9.795,10,10;9.795,9.7,10,10;9.7,9.667,10,10;9.667,9.7,10,10;9.7,9.795,10,10;9.795,9.944,10,10;9.944,10,10,10;10,10,10,10;10,10,10,10;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;10,10,10,10;10,10,10,10;10,10,10,10;10,10,10,10;10,10,10,10;10,10,10,10;10,10,10,10;10,10,10,10;10,10,10,10;10,10,10,10;10,10,10,10;10,10,10,10;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;10,10,10.833,10.833;10,10,10.833,10.833;10,10,10.833,10.833;10,10,10.833,10.833;10,10,10.833,10.833;10,10,10.833,10.833;10,10,10.833,10.833;10,10,10.833,10.833;10,10,10.833,10.833;10,10,10.833,10.833;10,10,10.833,10.833;10,10,10.833,10.833;10,10,10.833,10.833;10,10,10.833,10.833;10,10,10.833,10.833;10,10,10.833,10.833;10,10,10.833,10.833;10,10,10.833,10.833;x;x;x;x;x",
        "x;x;x;x;x;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;10.833,10.833,11.206,11.206;x;x;x;x;x",
        "x;x;x;x;x;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;11.206,11.206,11.294,11.294;x;x;x;x;x",
        "x;x;x;x;x;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;11.294,11.294,11.667,11.667;x;x;x;x;x",
        "x;x;x;x;x;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;11.667,11.667,12.5,12.5;x;x;x;x;x",
        "x;x;x;x;x;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;12.5,12.5,13.333,13.333;x;x;x;x;x",
        "x;x;x;x;x;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;13.333,13.333,13.706,13.706;x;x;x;x;x",
        "x;x;x;x;x;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;13.706,13.706,13.794,13.794;x;x;x;x;x",
        "x;x;x;x;x;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;13.794,13.794,14.167,14.167;x;x;x;x;x",
        "x;x;x;x;x;14.167,14.167,15,15;14.167,14.167,15,15;14.167,14.167,15,15;14.167,14.167,15,15;14.167,14.167,15,15;14.167,14.167,15,15;14.167,14.167,15,15;14.167,14.167,15,15;14.167,14.167,15,15;14.167,14.167,15,15;14.167,14.167,15,15;14.167,14.167,15,15;14.167,14.167,15,15;14.167,14.167,15,15;14.167,14.167,15,15;14.167,14.167,15,15;14.167,14.167,15,15;14.167,14.167,15,15;x;x;x;x;x",
        "x;x;x;x;x;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x;x;x;x",
        "x;x;x;x;x;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x;x;x;x",
        "x;x;x;x;x;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x;x;x;x",
        "x;x;x;x;x;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x;x;x;x",
        "x;x;x;x;x;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x;x;x;x",
        "x;x;x;x;x;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x;x;x;x",
        "x;x;x;x;x;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;x;x;x;x;x",
        "x;x;x;x;x;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;x;x;x;x;x",
        "x;x;x;x;x;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;x;x;x;x;x",
        "x;x;x;x;x;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;18.2,18.2,18.2,18.2;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;x;x;x;x;x",
        "x;x;x;x;x;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;18.2,18.2,18.2,18.2;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;18.2,18.2,18.2,18.2;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;x;x;x;x;x",
        "x;x;x;x;x;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;18.2,18.2,18.2,18.2;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;x;x;x;x;x",
        "x;x;x;x;x;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;x;x;x;x;x",
        "x;x;x;x;x;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;x;x;x;x;x",
        "x;x;x;x;x;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;x;x;x;x;x",
        "x;x;x;x;x;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;17,17,17,17;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;17,17,17.25,17.25;17,17,17.25,17.25;17,17,17.25,17.25;17,17,17.25,17.25;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;17.25,17.25,17.5,17.5;17.25,17.25,17.5,17.5;17.25,17.25,17.5,17.5;17.25,17.25,17.5,17.5;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;17.5,17.5,17.75,17.75;17.5,17.5,17.75,17.75;17.5,17.5,17.75,17.75;17.5,17.5,17.75,17.75;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;17.75,17.75,18,18;17.75,17.75,18,18;17.75,17.75,18,18;17.75,17.75,18,18;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;18,18,18.25,18.25;18,18,18.25,18.25;18,18,18.25,18.25;18,18,18.25,18.25;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;18.25,18.25,18.5,18.5;18.25,18.25,18.5,18.5;18.25,18.25,18.5,18.5;18.25,18.25,18.5,18.5;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;18.5,18.5,18.75,18.75;18.5,18.5,18.75,18.75;18.5,18.5,18.75,18.75;18.5,18.5,18.75,18.75;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;18.75,18.75,19,19;18.75,18.75,19,19;18.75,18.75,19,19;18.75,18.75,19,19;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;19,19,19.25,19.25;19,19,19.25,19.25;19,19,19.25,19.25;19,19,19.25,19.25;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;19.25,19.25,19.5,19.5;19.25,19.25,19.5,19.5;19.25,19.25,19.5,19.5;19.25,19.25,19.5,19.5;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;24,23.575,24,23.55;23.575,23.128,23.55,23.1;23.128,22.682,23.1,22.65;22.682,22.237,22.65,22.2;22.237,21.795,22.2,21.75;21.795,21.355,21.75,21.3;21.355,20.923,21.3,20.85;20.923,20.506,20.85,20.4;20.506,20.136,20.4,19.95;20.136,19.95,19.95,19.5;19.95,20.136,19.5,19.95;20.136,20.506,19.95,20.4;20.506,20.923,20.4,20.85;20.923,21.355,20.85,21.3;21.355,21.795,21.3,21.75;21.795,22.237,21.75,22.2;22.237,22.682,22.2,22.65;22.682,23.128,22.65,23.1;23.128,23.575,23.1,23.55;23.575,24,23.55,24;x;x;x;x",
        "x;x;x;x;24,23.55,24,23.575;23.55,23.1,23.575,23.128;23.1,22.65,23.128,22.682;22.65,22.2,22.682,22.237;22.2,21.75,22.237,21.795;21.75,21.3,21.795,21.355;21.3,20.85,21.355,20.923;20.85,20.4,20.923,20.506;20.4,19.95,20.506,20.136;19.95,19.5,20.136,19.95;19.5,19.95,19.95,20.136;19.95,20.4,20.136,20.506;20.4,20.85,20.506,20.923;20.85,21.3,20.923,21.355;21.3,21.75,21.355,21.795;21.75,22.2,21.795,22.237;22.2,22.65,22.237,22.682;22.65,23.1,22.682,23.128;23.1,23.55,23.128,23.575;23.55,24,23.575,24;x;x;x;x",
        "x;x;x;x;24,23.575,24,23.649;23.575,23.128,23.649,23.211;23.128,22.682,23.211,22.776;22.682,22.237,22.776,22.346;22.237,21.795,22.346,21.923;21.795,21.355,21.923,21.512;21.355,20.923,21.512,21.122;20.923,20.506,21.122,20.773;20.506,20.136,20.773,20.506;20.136,19.95,20.506,20.4;19.95,20.136,20.4,20.506;20.136,20.506,20.506,20.773;20.506,20.923,20.773,21.122;20.923,21.355,21.122,21.512;21.355,21.795,21.512,21.923;21.795,22.237,21.923,22.346;22.237,22.682,22.346,22.776;22.682,23.128,22.776,23.211;23.128,23.575,23.211,23.649;23.575,24,23.649,24;x;x;x;x",
        "x;x;x;x;24,23.649,24,23.769;23.649,23.211,23.769,23.345;23.211,22.776,23.345,22.927;22.776,22.346,22.927,22.519;22.346,21.923,22.519,22.124;21.923,21.512,22.124,21.75;21.512,21.122,21.75,21.409;21.122,20.773,21.409,21.122;20.773,20.506,21.122,20.923;20.506,20.4,20.923,20.85;20.4,20.506,20.85,20.923;20.506,20.773,20.923,21.122;20.773,21.122,21.122,21.409;21.122,21.512,21.409,21.75;21.512,21.923,21.75,22.124;21.923,22.346,22.124,22.519;22.346,22.776,22.519,22.927;22.776,23.211,22.927,23.345;23.211,23.649,23.345,23.769;23.649,24,23.769,24;x;x;x;x",
        "x;x;x;x;24,23.769,24,23.932;23.769,23.345,23.932,23.525;23.345,22.927,23.525,23.128;22.927,22.519,23.128,22.745;22.519,22.124,22.745,22.381;22.124,21.75,22.381,22.046;21.75,21.409,22.046,21.75;21.409,21.122,21.75,21.512;21.122,20.923,21.512,21.355;20.923,20.85,21.355,21.3;20.85,20.923,21.3,21.355;20.923,21.122,21.355,21.512;21.122,21.409,21.512,21.75;21.409,21.75,21.75,22.046;21.75,22.124,22.046,22.381;22.124,22.519,22.381,22.745;22.519,22.927,22.745,23.128;22.927,23.345,23.128,23.525;23.345,23.769,23.525,23.932;23.769,24,23.932,24;x;x;x;x",
        "x;x;x;x;24,23.932,24,24;23.932,23.525,24,23.745;23.525,23.128,23.745,23.371;23.128,22.745,23.371,23.015;22.745,22.381,23.015,22.682;22.381,22.046,22.682,22.381;22.046,21.75,22.381,22.124;21.75,21.512,22.124,21.923;21.512,21.355,21.923,21.795;21.355,21.3,21.795,21.75;21.3,21.355,21.75,21.795;21.355,21.512,21.795,21.923;21.512,21.75,21.923,22.124;21.75,22.046,22.124,22.381;22.046,22.381,22.381,22.682;22.381,22.745,22.682,23.015;22.745,23.128,23.015,23.371;23.128,23.525,23.371,23.745;23.525,23.932,23.745,24;23.932,24,24,24;x;x;x;x",
        "x;x;x;x;24,24,24,24;24,23.745,24,24;23.745,23.371,24,23.649;23.371,23.015,23.649,23.318;23.015,22.682,23.318,23.015;22.682,22.381,23.015,22.745;22.381,22.124,22.745,22.519;22.124,21.923,22.519,22.346;21.923,21.795,22.346,22.237;21.795,21.75,22.237,22.2;21.75,21.795,22.2,22.237;21.795,21.923,22.237,22.346;21.923,22.124,22.346,22.519;22.124,22.381,22.519,22.745;22.381,22.682,22.745,23.015;22.682,23.015,23.015,23.318;23.015,23.371,23.318,23.649;23.371,23.745,23.649,24;23.745,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;x;x;24,24,24,24;24,24,24,24;24,23.649,24,23.955;23.649,23.318,23.955,23.649;23.318,23.015,23.649,23.371;23.015,22.745,23.371,23.128;22.745,22.519,23.128,22.927;22.519,22.346,22.927,22.776;22.346,22.237,22.776,22.682;22.237,22.2,22.682,22.65;22.2,22.237,22.65,22.682;22.237,22.346,22.682,22.776;22.346,22.519,22.776,22.927;22.519,22.745,22.927,23.128;22.745,23.015,23.128,23.371;23.015,23.318,23.371,23.649;23.318,23.649,23.649,23.955;23.649,24,23.955,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;x;x;24,24,24,24;24,24,24,24;24,23.955,24,24;23.955,23.649,24,24;23.649,23.371,24,23.745;23.371,23.128,23.745,23.525;23.128,22.927,23.525,23.345;22.927,22.776,23.345,23.211;22.776,22.682,23.211,23.128;22.682,22.65,23.128,23.1;22.65,22.682,23.1,23.128;22.682,22.776,23.128,23.211;22.776,22.927,23.211,23.345;22.927,23.128,23.345,23.525;23.128,23.371,23.525,23.745;23.371,23.649,23.745,24;23.649,23.955,24,24;23.955,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,23.745,24,24;23.745,23.525,24,23.932;23.525,23.345,23.932,23.769;23.345,23.211,23.769,23.649;23.211,23.128,23.649,23.575;23.128,23.1,23.575,23.55;23.1,23.128,23.55,23.575;23.128,23.211,23.575,23.649;23.211,23.345,23.649,23.769;23.345,23.525,23.769,23.932;23.525,23.745,23.932,24;23.745,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,23.932,24,24;23.932,23.769,24,24;23.769,23.649,24,24;23.649,23.575,24,24;23.575,23.55,24,24;23.55,23.575,24,24;23.575,23.649,24,24;23.649,23.769,24,24;23.769,23.932,24,24;23.932,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x" } },
    { name = "Intermediate Race", nx = 28, nz = 74, time = 40, gravity = 1, start = { 6.5, 69 }, goal = { 19, 0, 25, 4 },
      checks = { { 6.5, 69 }, { 6.5, 52 }, { 21, 40 }, { 19, 31 }, { 5, 22 }, { 22, 18 }, { 22, 6 } },
      enemies = { { k = "acid", path = { { 4, 50 }, { 20, 50 } }, v = 2.2 }, { k = "acid", path = { { 22, 46 }, { 6, 54 } }, v = 1.8 }, { k = "muncher", x = 5, z = 21 }, { k = "muncher", x = 21, z = 13 } },
      meshes = { "c3_topA", "c3_topB1", "c3_topB2", "c3_topG", "c3_wall" },
      rows = {
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;13,13,13.333,13.333;13,13,13.333,13.333;13,13,13.333,13.333;13,13,13.333,13.333;13,13,13.333,13.333;13,13,13.333,13.333;13,13,13.333,13.333;13,13,13.333,13.333;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;13.333,13.333,13.667,13.667;13.333,13.333,13.667,13.667;13.333,13.333,13.667,13.667;13.333,13.333,13.667,13.667;13.333,13.333,13.667,13.667;13.333,13.333,13.667,13.667;13.333,13.333,13.667,13.667;13.333,13.333,13.667,13.667;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;13.667,13.667,14,14;13.667,13.667,14,14;13.667,13.667,14,14;13.667,13.667,14,14;13.667,13.667,14,14;13.667,13.667,14,14;13.667,13.667,14,14;13.667,13.667,14,14;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;14,14,14.333,14.333;14,14,14.333,14.333;14,14,14.333,14.333;14,14,14.333,14.333;14,14,14.333,14.333;14,14,14.333,14.333;14,14,14.333,14.333;14,14,14.333,14.333;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;14.333,14.333,14.667,14.667;14.333,14.333,14.667,14.667;14.333,14.333,14.667,14.667;14.333,14.333,14.667,14.667;14.333,14.333,14.667,14.667;14.333,14.333,14.667,14.667;14.333,14.333,14.667,14.667;14.333,14.333,14.667,14.667;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;14.667,14.667,15,15;14.667,14.667,15,15;14.667,14.667,15,15;14.667,14.667,15,15;14.667,14.667,15,15;14.667,14.667,15,15;14.667,14.667,15,15;14.667,14.667,15,15;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x",
        "x;x;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.25,18.5,18.25;18.25,18,18.25,18;18,17.75,18,17.75;17.75,17.5,17.75,17.5;17.5,17.25,17.5,17.25;17.25,17,17.25,17;17,16.75,17,16.75;16.75,16.5,16.75,16.5;16.5,16.25,16.5,16.25;16.25,16,16.25,16;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x",
        "x;x;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.25,18.5,18.25;18.25,18,18.25,18;18,17.75,18,17.75;17.75,17.5,17.75,17.5;17.5,17.25,17.5,17.25;17.25,17,17.25,17;17,16.75,17,16.75;16.75,16.5,16.75,16.5;16.5,16.25,16.5,16.25;16.25,16,16.25,16;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x",
        "x;x;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.25,18.5,18.25;18.25,18,18.25,18;18,17.75,18,17.75;17.75,17.5,17.75,17.5;17.5,17.25,17.5,17.25;17.25,17,17.25,17;17,16.75,17,16.75;16.75,16.5,16.75,16.5;16.5,16.25,16.5,16.25;16.25,16,16.25,16;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x",
        "x;x;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.25,18.5,18.25;18.25,18,18.25,18;18,17.75,18,17.75;17.75,17.5,17.75,17.5;17.5,17.25,17.5,17.25;17.25,17,17.25,17;17,16.75,17,16.75;16.75,16.5,16.75,16.5;16.5,16.25,16.5,16.25;16.25,16,16.25,16;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x",
        "x;x;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.25,18.5,18.25;18.25,18,18.25,18;18,17.75,18,17.75;17.75,17.5,17.75,17.5;17.5,17.25,17.5,17.25;17.25,17,17.25,17;17,16.75,17,16.75;16.75,16.5,16.75,16.5;16.5,16.25,16.5,16.25;16.25,16,16.25,16;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x",
        "x;x;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.25,18.5,18.25;18.25,18,18.25,18;18,17.75,18,17.75;17.75,17.5,17.75,17.5;17.5,17.25,17.5,17.25;17.25,17,17.25,17;17,16.75,17,16.75;16.75,16.5,16.75,16.5;16.5,16.25,16.5,16.25;16.25,16,16.25,16;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;15,15,15,15;x;x",
        "x;x;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;18.5,18.5,18.5,18.5;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;18.24,18.75,18.24,18.75;18.75,19.26,18.75,19.26;19.26,18.99,19.26,18.99;18.99,19.5,18.99,19.5;19.5,20.01,19.5,20.01;20.01,19.74,20.01,19.74;19.74,20.25,19.74,20.25;20.25,20.76,20.25,20.76;20.76,20.49,20.76,20.49;20.49,21,20.49,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;x;18.24,18.75,18.24,18.75;18.75,19.26,18.75,19.26;19.26,18.99,19.26,18.99;18.99,19.5,18.99,19.5;19.5,20.01,19.5,20.01;20.01,19.74,20.01,19.74;19.74,20.25,19.74,20.25;20.25,20.76,20.25,20.76;20.76,20.49,20.76,20.49;20.49,21,20.49,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;x;18.24,18.75,18.24,18.75;18.75,19.26,18.75,19.26;19.26,18.99,19.26,18.99;18.99,19.5,18.99,19.5;19.5,20.01,19.5,20.01;20.01,19.74,20.01,19.74;19.74,20.25,19.74,20.25;20.25,20.76,20.25,20.76;20.76,20.49,20.76,20.49;20.49,21,20.49,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;x;18.24,18.75,18.24,18.75;18.75,19.26,18.75,19.26;19.26,18.99,19.26,18.99;18.99,19.5,18.99,19.5;19.5,20.01,19.5,20.01;20.01,19.74,20.01,19.74;19.74,20.25,19.74,20.25;20.25,20.76,20.25,20.76;20.76,20.49,20.76,20.49;20.49,21,20.49,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;x;18.24,18.75,18.24,18.75;18.75,19.26,18.75,19.26;19.26,18.99,19.26,18.99;18.99,19.5,18.99,19.5;19.5,20.01,19.5,20.01;20.01,19.74,20.01,19.74;19.74,20.25,19.74,20.25;20.25,20.76,20.25,20.76;20.76,20.49,20.76,20.49;20.49,21,20.49,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;x;18.24,18.75,18.24,18.75;18.75,19.26,18.75,19.26;19.26,18.99,19.26,18.99;18.99,19.5,18.99,19.5;19.5,20.01,19.5,20.01;20.01,19.74,20.01,19.74;19.74,20.25,19.74,20.25;20.25,20.76,20.25,20.76;20.76,20.49,20.76,20.49;20.49,21,20.49,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;21,21,21.3,21.3;21,21,21.3,21.3;21,21,21.3,21.3;21,21,21.3,21.3;21,21,21.3,21.3;21,21,21.3,21.3;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;21.3,21.3,21.6,21.6;21.3,21.3,21.6,21.6;21.3,21.3,21.6,21.6;21.3,21.3,21.6,21.6;21.3,21.3,21.6,21.6;21.3,21.3,21.6,21.6;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;21.6,21.6,21.9,21.9;21.6,21.6,21.9,21.9;21.6,21.6,21.9,21.9;21.6,21.6,21.9,21.9;21.6,21.6,21.9,21.9;21.6,21.6,21.9,21.9;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;21.9,21.9,22.2,22.2;21.9,21.9,22.2,22.2;21.9,21.9,22.2,22.2;21.9,21.9,22.2,22.2;21.9,21.9,22.2,22.2;21.9,21.9,22.2,22.2;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;22.2,22.2,22.5,22.5;22.2,22.2,22.5,22.5;22.2,22.2,22.5,22.5;22.2,22.2,22.5,22.5;22.2,22.2,22.5,22.5;22.2,22.2,22.5,22.5;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;22.5,22.5,22.8,22.8;22.5,22.5,22.8,22.8;22.5,22.5,22.8,22.8;22.5,22.5,22.8,22.8;22.5,22.5,22.8,22.8;22.5,22.5,22.8,22.8;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;22.8,22.8,23.1,23.1;22.8,22.8,23.1,23.1;22.8,22.8,23.1,23.1;22.8,22.8,23.1,23.1;22.8,22.8,23.1,23.1;22.8,22.8,23.1,23.1;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;23.1,23.1,23.4,23.4;23.1,23.1,23.4,23.4;23.1,23.1,23.4,23.4;23.1,23.1,23.4,23.4;23.1,23.1,23.4,23.4;23.1,23.1,23.4,23.4;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;23.4,23.4,23.7,23.7;23.4,23.4,23.7,23.7;23.4,23.4,23.7,23.7;23.4,23.4,23.7,23.7;23.4,23.4,23.7,23.7;23.4,23.4,23.7,23.7;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;23.7,23.7,24,24;23.7,23.7,24,24;23.7,23.7,24,24;23.7,23.7,24,24;23.7,23.7,24,24;23.7,23.7,24,24;x;x;x;x",
        "x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;24,24,24,24;x;x;x;x",
        "x;x;x;x;24,24,24.4,24.4;24,24,24.4,24.4;24,24,24.4,24.4;24,24,24.4,24.4;24,24,24.4,24.4;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;24.4,24.4,24.8,24.8;24.4,24.4,24.8,24.8;24.4,24.4,24.8,24.8;24.4,24.4,24.8,24.8;24.4,24.4,24.8,24.8;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;24.8,24.8,25.2,25.2;24.8,24.8,25.2,25.2;24.8,24.8,25.2,25.2;24.8,24.8,25.2,25.2;24.8,24.8,25.2,25.2;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;25.2,25.2,25.6,25.6;25.2,25.2,25.6,25.6;25.2,25.2,25.6,25.6;25.2,25.2,25.6,25.6;25.2,25.2,25.6,25.6;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;25.6,25.6,26,26;25.6,25.6,26,26;25.6,25.6,26,26;25.6,25.6,26,26;25.6,25.6,26,26;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;26,26,26.4,26.4;26,26,26.4,26.4;26,26,26.4,26.4;26,26,26.4,26.4;26,26,26.4,26.4;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;26.4,26.4,26.8,26.8;26.4,26.4,26.8,26.8;26.4,26.4,26.8,26.8;26.4,26.4,26.8,26.8;26.4,26.4,26.8,26.8;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;26.8,26.8,27.2,27.2;26.8,26.8,27.2,27.2;26.8,26.8,27.2,27.2;26.8,26.8,27.2,27.2;26.8,26.8,27.2,27.2;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;27.2,27.2,27.6,27.6;27.2,27.2,27.6,27.6;27.2,27.2,27.6,27.6;27.2,27.2,27.6,27.6;27.2,27.2,27.6,27.6;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;27.6,27.6,28,28;27.6,27.6,28,28;27.6,27.6,28,28;27.6,27.6,28,28;27.6,27.6,28,28;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;28,28,28,28;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x" } },
    { name = "Aerial Race", nx = 28, nz = 76, time = 40, gravity = 1, start = { 14.5, 71 }, goal = { 5, 0, 10, 4 },
      checks = { { 14.5, 71 }, { 14.5, 56 }, { 5.5, 53 }, { 5.5, 38 }, { 22, 36 }, { 22, 20 }, { 7.5, 16 }, { 7.5, 2 } },
      enemies = { { k = "steelie", x = 22, z = 36 }, { k = "muncher", x = 7, z = 15 } },
      meshes = { "c4_topA", "c4_topB1", "c4_topB2", "c4_topG", "c4_wall" },
      rows = {
        "x;x;x;x;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;11,11,11.25,11.25;11,11,11.25,11.25;11,11,11.25,11.25;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;11.25,11.25,11.5,11.5;11.25,11.25,11.5,11.5;11.25,11.25,11.5,11.5;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;11.5,11.5,11.75,11.75;11.5,11.5,11.75,11.75;11.5,11.5,11.75,11.75;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;11.75,11.75,12,12;11.75,11.75,12,12;11.75,11.75,12,12;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;12,12,12.25,12.25;12,12,12.25,12.25;12,12,12.25,12.25;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;12.25,12.25,12.5,12.5;12.25,12.25,12.5,12.5;12.25,12.25,12.5,12.5;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;12.5,12.5,12.75,12.75;12.5,12.5,12.75,12.75;12.5,12.5,12.75,12.75;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;12.75,12.75,13,13;12.75,12.75,13,13;12.75,12.75,13,13;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;14.2,14.4,14.2,14.4;14.4,14.6,14.4,14.6;14.6,14.8,14.6,14.8;14.8,15,14.8,15;15,15.2,15,15.2;15.2,15.4,15.2,15.4;15.4,15.6,15.4,15.6;15.6,15.8,15.6,15.8;15.8,16,15.8,16;16,16,16,16;16,16,16,16;16,16,16,16;16,16,16,16;16,16,16,16;16,16,16,16;x;x;x",
        "x;x;x;x;x;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;13,13,13,13;14.2,14.4,14.2,14.4;14.4,14.6,14.4,14.6;14.6,14.8,14.6,14.8;14.8,15,14.8,15;15,15.2,15,15.2;15.2,15.4,15.2,15.4;15.4,15.6,15.4,15.6;15.6,15.8,15.6,15.8;15.8,16,15.8,16;16,16,16,16;16,16,16,16;16,16,16,16;16,16,16,16;16,16,16,16;16,16,16,16;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;16,16,16,16;16,16,16,16;16,16,16,16;16,16,16,16;16,16,16,16;16,16,16,16;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;16,16,16,16;16,16,16,16;16,16,16,16;16,16,16,16;16,16,16,16;16,16,16,16;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;17,17,17.2,17.2;17,17,17.2,17.2;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;17.2,17.2,17.4,17.4;17.2,17.2,17.4,17.4;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;17.4,17.4,17.6,17.6;17.4,17.4,17.6,17.6;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;17.6,17.6,17.8,17.8;17.6,17.6,17.8,17.8;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;17.8,17.8,18,18;17.8,17.8,18,18;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;18,18,18.2,18.2;18,18,18.2,18.2;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;18.2,18.2,18.4,18.4;18.2,18.2,18.4,18.4;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;18.4,18.4,18.6,18.6;18.4,18.4,18.6,18.6;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;18.6,18.6,18.8,18.8;18.6,18.6,18.8,18.8;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;18.8,18.8,19,19;18.8,18.8,19,19;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;19,19,19,19;19,19,19,19;19,19,19,19;19,19,19,19;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;19,19,19,19;19,19,19,19;19,19,19,19;19,19,19,19;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;19,19,19,19;19,19,19,19;19,19,19,19;19,19,19,19;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;19,19,19,19;19,19,19,19;19,19,19,19;19,19,19,19;x;x;x;x",
        "x;x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,20.846,21,20.846;20.846,20.692,20.846,20.692;20.692,20.538,20.692,20.538;20.538,20.385,20.538,20.385;20.385,20.231,20.385,20.231;20.231,20.077,20.231,20.077;20.077,19.923,20.077,19.923;19.923,19.769,19.923,19.769;19.769,19.615,19.769,19.615;19.615,19.462,19.615,19.462;19.462,19.308,19.462,19.308;19.308,19.154,19.308,19.154;19.154,19,19.154,19;19,19,19,19;19,19,19,19;19,19,19,19;19,19,19,19;x;x;x;x",
        "x;x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,20.846,21,20.846;20.846,20.692,20.846,20.692;20.692,20.538,20.692,20.538;20.538,20.385,20.538,20.385;20.385,20.231,20.385,20.231;20.231,20.077,20.231,20.077;20.077,19.923,20.077,19.923;19.923,19.769,19.923,19.769;19.769,19.615,19.769,19.615;19.615,19.462,19.615,19.462;19.462,19.308,19.462,19.308;19.308,19.154,19.308,19.154;19.154,19,19.154,19;19,19,19,19;19,19,19,19;19,19,19,19;19,19,19,19;x;x;x;x",
        "x;x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,20.846,21,20.846;20.846,20.692,20.846,20.692;20.692,20.538,20.692,20.538;20.538,20.385,20.538,20.385;20.385,20.231,20.385,20.231;20.231,20.077,20.231,20.077;20.077,19.923,20.077,19.923;19.923,19.769,19.923,19.769;19.769,19.615,19.769,19.615;19.615,19.462,19.615,19.462;19.462,19.308,19.462,19.308;19.308,19.154,19.308,19.154;19.154,19,19.154,19;19,19,19,19;19,19,19,19;19,19,19,19;19,19,19,19;x;x;x;x",
        "x;x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;x;x;x;x;x;x;x;x;x;x;x;x;x;19,19,19,19;19,19,19,19;19,19,19,19;19,19,19,19;x;x;x;x",
        "x;x;x;x;23,23,23.2,23.2;23,23,23.2,23.2;23,23,23.2,23.2;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;23.2,23.2,23.4,23.4;23.2,23.2,23.4,23.4;23.2,23.2,23.4,23.4;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;23.4,23.4,23.6,23.6;23.4,23.4,23.6,23.6;23.4,23.4,23.6,23.6;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;23.6,23.6,23.8,23.8;23.6,23.6,23.8,23.8;23.6,23.6,23.8,23.8;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;23.8,23.8,24,24;23.8,23.8,24,24;23.8,23.8,24,24;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;24,24,24.2,24.2;24,24,24.2,24.2;24,24,24.2,24.2;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;24.2,24.2,24.4,24.4;24.2,24.2,24.4,24.4;24.2,24.2,24.4,24.4;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;24.4,24.4,24.6,24.6;24.4,24.4,24.6,24.6;24.4,24.4,24.6,24.6;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;24.6,24.6,24.8,24.8;24.6,24.6,24.8,24.8;24.6,24.6,24.8,24.8;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;24.8,24.8,25,25;24.8,24.8,25,25;24.8,24.8,25,25;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25.75,26,25.75,26;26,26.25,26,26.25;26.25,26.5,26.25,26.5;26.5,26.75,26.5,26.75;26.75,27,26.75,27;27,27,27,27;27,27,27,27;27,27,27,27;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25.75,26,25.75,26;26,26.25,26,26.25;26.25,26.5,26.25,26.5;26.5,26.75,26.5,26.75;26.75,27,26.75,27;27,27,27,27;27,27,27,27;27,27,27,27;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25,25,25,25;25.75,26,25.75,26;26,26.25,26,26.25;26.25,26.5,26.25,26.5;26.5,26.75,26.5,26.75;26.75,27,26.75,27;27,27,27,27;27,27,27,27;27,27,27,27;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;27,27,27,27;27,27,27,27;27,27,27,27;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;27,27,27.3,27.3;27,27,27.3,27.3;27,27,27.3,27.3;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;27.3,27.3,27.6,27.6;27.3,27.3,27.6,27.6;27.3,27.3,27.6,27.6;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;27.6,27.6,27.9,27.9;27.6,27.6,27.9,27.9;27.6,27.6,27.9,27.9;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;27.9,27.9,28.2,28.2;27.9,27.9,28.2,28.2;27.9,27.9,28.2,28.2;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;28.2,28.2,28.5,28.5;28.2,28.2,28.5,28.5;28.2,28.2,28.5,28.5;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;28.5,28.5,28.8,28.8;28.5,28.5,28.8,28.8;28.5,28.5,28.8,28.8;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;28.8,28.8,29.1,29.1;28.8,28.8,29.1,29.1;28.8,28.8,29.1,29.1;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;29.1,29.1,29.4,29.4;29.1,29.1,29.4,29.4;29.1,29.1,29.4,29.4;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;29.4,29.4,29.7,29.7;29.4,29.4,29.7,29.7;29.4,29.4,29.7,29.7;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;29.7,29.7,30,30;29.7,29.7,30,30;29.7,29.7,30,30;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x" } },
    { name = "Silly Race", nx = 26, nz = 66, time = 35, gravity = -1, start = { 12.5, 61 }, goal = { 18, 0, 23, 4 },
      checks = { { 12.5, 61 }, { 12.5, 43 }, { 4, 43 }, { 4, 27 }, { 8, 19 }, { 20, 18 }, { 20, 6 } },
      enemies = { { k = "steelie", x = 4, z = 36 }, { k = "steelie", x = 20, z = 14 } },
      meshes = { "c5_topA", "c5_topB3", "c5_topW", "c5_topB2", "c5_topG", "c5_wall" },
      rows = {
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;23,23,22.667,22.667;23,23,22.667,22.667;23,23,22.667,22.667;23,23,22.667,22.667;23,23,22.667,22.667;23,23,22.667,22.667;23,23,22.667,22.667;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;22.667,22.667,22.333,22.333;22.667,22.667,22.333,22.333;22.667,22.667,22.333,22.333;22.667,22.667,22.333,22.333;22.667,22.667,22.333,22.333;22.667,22.667,22.333,22.333;22.667,22.667,22.333,22.333;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;22.333,22.333,22,22;22.333,22.333,22,22;22.333,22.333,22,22;22.333,22.333,22,22;22.333,22.333,22,22;22.333,22.333,22,22;22.333,22.333,22,22;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;22,22,21.667,21.667;22,22,21.667,21.667;22,22,21.667,21.667;22,22,21.667,21.667;22,22,21.667,21.667;22,22,21.667,21.667;22,22,21.667,21.667;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;21.667,21.667,21.333,21.333;21.667,21.667,21.333,21.333;21.667,21.667,21.333,21.333;21.667,21.667,21.333,21.333;21.667,21.667,21.333,21.333;21.667,21.667,21.333,21.333;21.667,21.667,21.333,21.333;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;21.333,21.333,21,21;21.333,21.333,21,21;21.333,21.333,21,21;21.333,21.333,21,21;21.333,21.333,21,21;21.333,21.333,21,21;21.333,21.333,21,21;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18.5,18,18.5;18.5,19,18.5,19;19,19.5,19,19.5;19.5,20,19.5,20;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18.5,18,18.5;18.5,19,18.5,19;19,19.5,19,19.5;19.5,20,19.5,20;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18.5,18,18.5;18.5,19,18.5,19;19,19.5,19,19.5;19.5,20,19.5,20;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18.5,18,18.5;18.5,19,18.5,19;19,19.5,19,19.5;19.5,20,19.5,20;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18.5,18,18.5;18.5,19,18.5,19;19,19.5,19,19.5;19.5,20,19.5,20;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18.5,18,18.5;18.5,19,18.5,19;19,19.5,19,19.5;19.5,20,19.5,20;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x",
        "x;18,18,17.3,17.3;18,18,17.3,17.3;18,18,17.3,17.3;18,18,17.3,17.3;18,18,17.3,17.3;18,18,17.3,17.3;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;17.3,17.3,17.2,17.2;17.3,17.3,17.2,17.2;17.3,17.3,17.2,17.2;17.3,17.3,17.2,17.2;17.3,17.3,17.2,17.2;17.3,17.3,17.2,17.2;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;17.2,17.2,17.1,17.1;17.2,17.2,17.1,17.1;17.2,17.2,17.1,17.1;17.2,17.2,17.1,17.1;17.2,17.2,17.1,17.1;17.2,17.2,17.1,17.1;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;17.1,17.1,16.4,16.4;17.1,17.1,16.4,16.4;17.1,17.1,16.4,16.4;17.1,17.1,16.4,16.4;17.1,17.1,16.4,16.4;17.1,17.1,16.4,16.4;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;16.4,16.4,15.7,15.7;16.4,16.4,15.7,15.7;16.4,16.4,15.7,15.7;16.4,16.4,15.7,15.7;16.4,16.4,15.7,15.7;16.4,16.4,15.7,15.7;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;15.7,15.7,15.6,15.6;15.7,15.7,15.6,15.6;15.7,15.7,15.6,15.6;15.7,15.7,15.6,15.6;15.7,15.7,15.6,15.6;15.7,15.7,15.6,15.6;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;15.6,15.6,15.5,15.5;15.6,15.6,15.5,15.5;15.6,15.6,15.5,15.5;15.6,15.6,15.5,15.5;15.6,15.6,15.5,15.5;15.6,15.6,15.5,15.5;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;15.5,15.5,14.8,14.8;15.5,15.5,14.8,14.8;15.5,15.5,14.8,14.8;15.5,15.5,14.8,14.8;15.5,15.5,14.8,14.8;15.5,15.5,14.8,14.8;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;14.8,14.8,14.1,14.1;14.8,14.8,14.1,14.1;14.8,14.8,14.1,14.1;14.8,14.8,14.1,14.1;14.8,14.8,14.1,14.1;14.8,14.8,14.1,14.1;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;14.1,14.1,14,14;14.1,14.1,14,14;14.1,14.1,14,14;14.1,14.1,14,14;14.1,14.1,14,14;14.1,14.1,14,14;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;12,11.5,12,11.5;11.5,11,11.5,11;11.8,11.8,11.8,11.8;11.8,11.8,11.8,11.8;11.8,11.8,11.8,11.8;11.8,11.8,11.8,11.8;11.8,11.8,11.8,11.8;11.8,11.8,11.8,11.8;11.8,11.8,11.8,11.8;x;x;x;x;x;x;x;x;x;x",
        "x;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;12,11.5,12,11.5;11.5,11,11.5,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11.8,11.8,11.8,11.8;x;x;x;x;x;x;x;x;x;x",
        "x;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;12,11.5,12,11.5;11.5,11,11.5,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11.8,11.8,11.8,11.8;x;x;x;x;x;x;x;x;x;x",
        "x;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;12,11.5,12,11.5;11.5,11,11.5,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11.8,11.8,11.8,11.8;x;x;x;x;x;x;x;x;x;x",
        "x;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;12,11.5,12,11.5;11.5,11,11.5,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11.8,11.8,11.8,11.8;x;x;x;x;x;x;x;x;x;x",
        "x;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;14,14,14,14;12,11.5,12,11.5;11.5,11,11.5,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11,11,11,11;11.8,11.8,11.8,11.8;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;11,11,10.583,10.583;11,11,10.583,10.583;11,11,10.583,10.583;11,11,10.583,10.583;11,11,10.583,10.583;11,11,10.583,10.583;11,11,10.583,10.583;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;10.583,10.583,10.167,10.167;10.583,10.583,10.167,10.167;10.583,10.583,10.167,10.167;10.583,10.583,10.167,10.167;10.583,10.583,10.167,10.167;10.583,10.583,10.167,10.167;10.583,10.583,10.167,10.167;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;10.167,10.167,9.75,9.75;10.167,10.167,9.75,9.75;10.167,10.167,9.75,9.75;10.167,10.167,9.75,9.75;10.167,10.167,9.75,9.75;10.167,10.167,9.75,9.75;10.167,10.167,9.75,9.75;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;9.75,9.75,9.333,9.333;9.75,9.75,9.333,9.333;9.75,9.75,9.333,9.333;9.75,9.75,9.333,9.333;9.75,9.75,9.333,9.333;9.75,9.75,9.333,9.333;9.75,9.75,9.333,9.333;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;9.333,9.333,8.917,8.917;9.333,9.333,8.917,8.917;9.333,9.333,8.917,8.917;9.333,9.333,8.917,8.917;9.333,9.333,8.917,8.917;9.333,9.333,8.917,8.917;9.333,9.333,8.917,8.917;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;8.917,8.917,8.5,8.5;8.917,8.917,8.5,8.5;8.917,8.917,8.5,8.5;8.917,8.917,8.5,8.5;8.917,8.917,8.5,8.5;8.917,8.917,8.5,8.5;8.917,8.917,8.5,8.5;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;8.5,8.5,8.083,8.083;8.5,8.5,8.083,8.083;8.5,8.5,8.083,8.083;8.5,8.5,8.083,8.083;8.5,8.5,8.083,8.083;8.5,8.5,8.083,8.083;8.5,8.5,8.083,8.083;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;8.083,8.083,7.667,7.667;8.083,8.083,7.667,7.667;8.083,8.083,7.667,7.667;8.083,8.083,7.667,7.667;8.083,8.083,7.667,7.667;8.083,8.083,7.667,7.667;8.083,8.083,7.667,7.667;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;7.667,7.667,7.25,7.25;7.667,7.667,7.25,7.25;7.667,7.667,7.25,7.25;7.667,7.667,7.25,7.25;7.667,7.667,7.25,7.25;7.667,7.667,7.25,7.25;7.667,7.667,7.25,7.25;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;7.25,7.25,6.833,6.833;7.25,7.25,6.833,6.833;7.25,7.25,6.833,6.833;7.25,7.25,6.833,6.833;7.25,7.25,6.833,6.833;7.25,7.25,6.833,6.833;7.25,7.25,6.833,6.833;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;6.833,6.833,6.417,6.417;6.833,6.833,6.417,6.417;6.833,6.833,6.417,6.417;6.833,6.833,6.417,6.417;6.833,6.833,6.417,6.417;6.833,6.833,6.417,6.417;6.833,6.833,6.417,6.417;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;6.417,6.417,6,6;6.417,6.417,6,6;6.417,6.417,6,6;6.417,6.417,6,6;6.417,6.417,6,6;6.417,6.417,6,6;6.417,6.417,6,6;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;6,6,6,6;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x" } },
    { name = "Ultimate Race", nx = 28, nz = 80, time = 35, gravity = 1, start = { 14, 75 }, goal = { 3, 0, 8, 4 },
      checks = { { 14, 75 }, { 14, 59 }, { 13.5, 41 }, { 19.5, 23 }, { 5.5, 19 }, { 5.5, 3 } },
      enemies = { { k = "hammer", x = 13.5, z = 51, per = 2.4, ph = 0 }, { k = "hammer", x = 19.5, z = 31, per = 2.2, ph = 1.1 }, { k = "acid", path = { { 6, 41 }, { 22, 41 } }, v = 2.6 }, { k = "muncher", x = 19, z = 23 }, { k = "muncher", x = 5.5, z = 18 }, { k = "steelie", x = 14, z = 59 }, { k = "hammer", x = 5.5, z = 10, per = 2, ph = 0.5 } },
      meshes = { "c6_topA", "c6_topB1", "c6_topA3", "c6_topA1", "c6_topA2", "c6_topB2", "c6_topG", "c6_wall" },
      rows = {
        "x;x;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;18,18,18,18;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;18,18,18.375,18.375;18,18,18.375,18.375;18,18,18.375,18.375;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;18.375,18.375,18.75,18.75;18.375,18.375,18.75,18.75;18.375,18.375,18.75,18.75;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;18.75,18.75,19.125,19.125;18.75,18.75,19.125,19.125;18.75,18.75,19.125,19.125;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;19.125,19.125,19.5,19.5;19.125,19.125,19.5,19.5;19.125,19.125,19.5,19.5;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;19.5,19.5,19.875,19.875;19.5,19.5,19.875,19.875;19.5,19.5,19.875,19.875;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;19.875,19.875,20.25,20.25;19.875,19.875,20.25,20.25;19.875,19.875,20.25,20.25;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;20.25,20.25,20.625,20.625;20.25,20.25,20.625,20.625;20.25,20.25,20.625,20.625;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;20.625,20.625,21,21;20.625,20.625,21,21;20.625,20.625,21,21;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;x;x;x;x;x;x;x;x;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;x;x;x;x;x",
        "x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21.4,21.6,21.4,21.6;21.6,21.8,21.6,21.8;21.8,22,21.8,22;22,22.2,22,22.2;22.2,22.4,22.2,22.4;22.4,22.6,22.4,22.6;22.6,22.8,22.6,22.8;22.8,23,22.8,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;x;x;x;x;x",
        "x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21.4,21.6,21.4,21.6;21.6,21.8,21.6,21.8;21.8,22,21.8,22;22,22.2,22,22.2;22.2,22.4,22.2,22.4;22.4,22.6,22.4,22.6;22.6,22.8,22.6,22.8;22.8,23,22.8,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;x;x;x;x;x",
        "x;x;x;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21,21,21,21;21.4,21.6,21.4,21.6;21.6,21.8,21.6,21.8;21.8,22,21.8,22;22,22.2,22,22.2;22.2,22.4,22.2,22.4;22.4,22.6,22.4,22.6;22.6,22.8,22.6,22.8;22.8,23,22.8,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;23,23,23,23;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;23,23,23.3,23.3;23,23,23.3,23.3;23,23,23.3,23.3;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;23.3,23.3,23.6,23.6;23.3,23.3,23.6,23.6;23.3,23.3,23.6,23.6;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;23.6,23.6,23.9,23.9;23.6,23.6,23.9,23.9;23.6,23.6,23.9,23.9;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;23.9,23.9,24.2,24.2;23.9,23.9,24.2,24.2;23.9,23.9,24.2,24.2;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;24.2,24.2,24.5,24.5;24.2,24.2,24.5,24.5;24.2,24.2,24.5,24.5;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;24.5,24.5,24.8,24.8;24.5,24.5,24.8,24.8;24.5,24.5,24.8,24.8;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;24.8,24.8,25.1,25.1;24.8,24.8,25.1,25.1;24.8,24.8,25.1,25.1;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;25.1,25.1,25.4,25.4;25.1,25.1,25.4,25.4;25.1,25.1,25.4,25.4;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;25.4,25.4,25.7,25.7;25.4,25.4,25.7,25.7;25.4,25.4,25.7,25.7;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;25.7,25.7,26,26;25.7,25.7,26,26;25.7,25.7,26,26;x;x;x;x;x;x;x",
        "x;x;x;x;26,26,25.55,25.55;26,26,25.55,26;26,26,26,26.45;26,26,26.45,26.45;26,26,26.45,26;26,26,26,25.55;26,26,25.55,25.55;26,26,25.55,26;26,26,26,26.45;26,26,26.45,26.45;26,26,26.45,26;26,26,26,25.55;26,26,25.55,25.55;26,26,25.55,26;26,26,26,26.45;26,26,26.45,26.45;26,26,26.45,26;26,26,26,25.55;26,26,25.55,25.55;26,26,25.55,26;x;x;x;x",
        "x;x;x;x;25.55,25.55,25.55,25.55;25.55,26,25.55,26;26,26.45,26,26.45;26.45,26.45,26.45,26.45;26.45,26,26.45,26;26,25.55,26,25.55;25.55,25.55,25.55,25.55;25.55,26,25.55,26;26,26.45,26,26.45;26.45,26.45,26.45,26.45;26.45,26,26.45,26;26,25.55,26,25.55;25.55,25.55,25.55,25.55;25.55,26,25.55,26;26,26.45,26,26.45;26.45,26.45,26.45,26.45;26.45,26,26.45,26;26,25.55,26,25.55;25.55,25.55,25.55,25.55;25.55,26,25.55,26;x;x;x;x",
        "x;x;x;x;25.55,25.55,26,26;25.55,26,26,26;26,26.45,26,26;26.45,26.45,26,26;26.45,26,26,26;26,25.55,26,26;25.55,25.55,26,26;25.55,26,26,26;26,26.45,26,26;26.45,26.45,26,26;26.45,26,26,26;26,25.55,26,26;25.55,25.55,26,26;25.55,26,26,26;26,26.45,26,26;26.45,26.45,26,26;26.45,26,26,26;26,25.55,26,26;25.55,25.55,26,26;25.55,26,26,26;x;x;x;x",
        "x;x;x;x;26,26,26.45,26.45;26,26,26.45,26;26,26,26,25.55;26,26,25.55,25.55;26,26,25.55,26;26,26,26,26.45;26,26,26.45,26.45;26,26,26.45,26;26,26,26,25.55;26,26,25.55,25.55;26,26,25.55,26;26,26,26,26.45;26,26,26.45,26.45;26,26,26.45,26;26,26,26,25.55;26,26,25.55,25.55;26,26,25.55,26;26,26,26,26.45;26,26,26.45,26.45;26,26,26.45,26;x;x;x;x",
        "x;x;x;x;26.45,26.45,26.45,26.45;26.45,26,26.45,26;26,25.55,26,25.55;25.55,25.55,25.55,25.55;25.55,26,25.55,26;26,26.45,26,26.45;26.45,26.45,26.45,26.45;26.45,26,26.45,26;26,25.55,26,25.55;25.55,25.55,25.55,25.55;25.55,26,25.55,26;26,26.45,26,26.45;26.45,26.45,26.45,26.45;26.45,26,26.45,26;26,25.55,26,25.55;25.55,25.55,25.55,25.55;25.55,26,25.55,26;26,26.45,26,26.45;26.45,26.45,26.45,26.45;26.45,26,26.45,26;x;x;x;x",
        "x;x;x;x;26.45,26.45,26,26;26.45,26,26,26;26,25.55,26,26;25.55,25.55,26,26;25.55,26,26,26;26,26.45,26,26;26.45,26.45,26,26;26.45,26,26,26;26,25.55,26,26;25.55,25.55,26,26;25.55,26,26,26;26,26.45,26,26;26.45,26.45,26,26;26.45,26,26,26;26,25.55,26,26;25.55,25.55,26,26;25.55,26,26,26;26,26.45,26,26;26.45,26.45,26,26;26.45,26,26,26;x;x;x;x",
        "x;x;x;x;26,26,25.55,25.55;26,26,25.55,26;26,26,26,26.45;26,26,26.45,26.45;26,26,26.45,26;26,26,26,25.55;26,26,25.55,25.55;26,26,25.55,26;26,26,26,26.45;26,26,26.45,26.45;26,26,26.45,26;26,26,26,25.55;26,26,25.55,25.55;26,26,25.55,26;26,26,26,26.45;26,26,26.45,26.45;26,26,26.45,26;26,26,26,25.55;26,26,25.55,25.55;26,26,25.55,26;x;x;x;x",
        "x;x;x;x;25.55,25.55,25.55,25.55;25.55,26,25.55,26;26,26.45,26,26.45;26.45,26.45,26.45,26.45;26.45,26,26.45,26;26,25.55,26,25.55;25.55,25.55,25.55,25.55;25.55,26,25.55,26;26,26.45,26,26.45;26.45,26.45,26.45,26.45;26.45,26,26.45,26;26,25.55,26,25.55;25.55,25.55,25.55,25.55;25.55,26,25.55,26;26,26.45,26,26.45;26.45,26.45,26.45,26.45;26.45,26,26.45,26;26,25.55,26,25.55;25.55,25.55,25.55,25.55;25.55,26,25.55,26;x;x;x;x",
        "x;x;x;x;25.55,25.55,26,26;25.55,26,26,26;26,26.45,26,26;26.45,26.45,26,26;26.45,26,26,26;26,25.55,26,26;25.55,25.55,26,26;25.55,26,26,26;26,26.45,26,26;26.45,26.45,26,26;26.45,26,26,26;26,25.55,26,26;25.55,25.55,26,26;25.55,26,26,26;26,26.45,26,26;26.45,26.45,26,26;26.45,26,26,26;26,25.55,26,26;25.55,25.55,26,26;25.55,26,26,26;x;x;x;x",
        "x;x;x;x;26,26,26.45,26.45;26,26,26.45,26;26,26,26,25.55;26,26,25.55,25.55;26,26,25.55,26;26,26,26,26.45;26,26,26.45,26.45;26,26,26.45,26;26,26,26,25.55;26,26,25.55,25.55;26,26,25.55,26;26,26,26,26.45;26,26,26.45,26.45;26,26,26.45,26;26,26,26,25.55;26,26,25.55,25.55;26,26,25.55,26;26,26,26,26.45;26,26,26.45,26.45;26,26,26.45,26;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;27,27,27.3,27.3;27,27,27.3,27.3;27,27,27.3,27.3;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;27.3,27.3,27.6,27.6;27.3,27.3,27.6,27.6;27.3,27.3,27.6,27.6;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;27.6,27.6,27.9,27.9;27.6,27.6,27.9,27.9;27.6,27.6,27.9,27.9;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;27.9,27.9,28.2,28.2;27.9,27.9,28.2,28.2;27.9,27.9,28.2,28.2;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;28.2,28.2,28.5,28.5;28.2,28.2,28.5,28.5;28.2,28.2,28.5,28.5;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;28.5,28.5,28.8,28.8;28.5,28.5,28.8,28.8;28.5,28.5,28.8,28.8;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;28.8,28.8,29.1,29.1;28.8,28.8,29.1,29.1;28.8,28.8,29.1,29.1;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;29.1,29.1,29.4,29.4;29.1,29.1,29.4,29.4;29.1,29.1,29.4,29.4;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;29.4,29.4,29.7,29.7;29.4,29.4,29.7,29.7;29.4,29.4,29.7,29.7;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;29.7,29.7,30,30;29.7,29.7,30,30;29.7,29.7,30,30;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;30,30,30,30;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;30,30,30.4,30.4;30,30,30.4,30.4;30,30,30.4,30.4;30,30,30.4,30.4;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;30.4,30.4,30.8,30.8;30.4,30.4,30.8,30.8;30.4,30.4,30.8,30.8;30.4,30.4,30.8,30.8;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;30.8,30.8,31.2,31.2;30.8,30.8,31.2,31.2;30.8,30.8,31.2,31.2;30.8,30.8,31.2,31.2;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;31.2,31.2,31.6,31.6;31.2,31.2,31.6,31.6;31.2,31.2,31.6,31.6;31.2,31.2,31.6,31.6;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;31.6,31.6,32,32;31.6,31.6,32,32;31.6,31.6,32,32;31.6,31.6,32,32;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;32,32,32.4,32.4;32,32,32.4,32.4;32,32,32.4,32.4;32,32,32.4,32.4;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;32.4,32.4,32.8,32.8;32.4,32.4,32.8,32.8;32.4,32.4,32.8,32.8;32.4,32.4,32.8,32.8;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;32.8,32.8,33.2,33.2;32.8,32.8,33.2,33.2;32.8,32.8,33.2,33.2;32.8,32.8,33.2,33.2;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;33.2,33.2,33.6,33.6;33.2,33.2,33.6,33.6;33.2,33.2,33.6,33.6;33.2,33.2,33.6,33.6;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;33.6,33.6,34,34;33.6,33.6,34,34;33.6,33.6,34,34;33.6,33.6,34,34;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;34,34,34,34;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x",
        "x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x;x" } },
}
G.COURSES = COURSES
------------------------------------------------------------------ course height field
-- cells[j*nx+i+1] = { h00, h10, h01, h11 } (corners (i,j) (i+1,j) (i,j+1) (i+1,j+1)) or false (void)
local R = 0.45
G.R = R
local function parse(c)
    local cells, lo = {}, 1e9
    for j, row in ipairs(c.rows) do
        local i = 0
        for cell in (row .. ";"):gmatch("([^;]*);") do
            if cell == "x" then cells[(j - 1) * c.nx + i + 1] = false
            else
                local a, b, d, e = cell:match("([^,]+),([^,]+),([^,]+),([^,]+)")
                local h = { tonumber(a), tonumber(b), tonumber(d), tonumber(e) }
                cells[(j - 1) * c.nx + i + 1] = h
                for q = 1, 4 do lo = min(lo, h[q]) end
            end
            i = i + 1
        end
    end
    c.cells, c.lo = cells, lo
end
for _, c in ipairs(COURSES) do parse(c) end
G.COURSES = COURSES
local CUR
-- height + gradient at (x, z); nil over void
local function hgt(x, z)
    local i, j = floor(x), floor(z)
    if i < 0 or j < 0 or i >= CUR.nx or j >= CUR.nz then return nil end
    local h = CUR.cells[j * CUR.nx + i + 1]
    if not h then return nil end
    local u, v = x - i, z - j
    local a = h[1] + (h[2] - h[1]) * u
    local b = h[3] + (h[4] - h[3]) * u
    local y = a + (b - a) * v
    local gx = (h[2] - h[1]) * (1 - v) + (h[4] - h[3]) * v
    local gz = b - a
    return y, gx, gz
end
G.hgt = hgt
------------------------------------------------------------------ state
local M = { x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0, air = false, alive = true, roll = 0, head = 0, squash = 1 }
G.M = M
G.EN = {}
local G0 = 24          -- gravity
local ROLLK = 5 / 7    -- rolling solid sphere
local STEP = 0.32      -- a rise taller than this above the ball's base is a wall
local BREAK_DROP = 4.6 -- falls longer than this shatter the marble
local MAXV = 15
-- marble orientation as a 3x3 rotation matrix (rows), integrated from the rolling motion every step:
-- rolling without slipping spins the ball about (up x velocity) by |v| dt / R. Rendering slerps the last step.
M.rot = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }; M.prot = M.rot; M.wax, M.waz, M.wang = 1, 0, 0
local function mrot_axis(ax, ay, az, a)
    local c, s, t = cos(a), sin(a), 1 - cos(a)
    return { t * ax * ax + c, t * ax * ay - s * az, t * ax * az + s * ay,
             t * ax * ay + s * az, t * ay * ay + c, t * ay * az - s * ax,
             t * ax * az - s * ay, t * ay * az + s * ax, t * az * az + c }
end
local function mmul(A, B)
    local C = {}
    for r = 0, 2 do for c = 0, 2 do C[r * 3 + c + 1] = A[r * 3 + 1] * B[c + 1] + A[r * 3 + 2] * B[c + 4] + A[r * 3 + 3] * B[c + 7] end end
    return C
end
G.mrot_axis, G.mmul = mrot_axis, mmul
local function orient_step(dt)
    M.prot = M.rot
    local sp = sqrt(M.vx * M.vx + M.vz * M.vz)
    if sp > 1e-4 then
        local ax, az = M.vz / sp, -M.vx / sp          -- up x v
        local a = sp * dt / R
        if M.air then a = a * 0.98 end                 -- keeps spinning in the air
        M.wax, M.waz, M.wang = ax, az, a
        local Rm = mmul(mrot_axis(ax, 0, az, a), M.rot)
        -- re-orthonormalise occasionally against drift
        M.nrm = (M.nrm or 0) + 1
        if M.nrm > 120 then
            M.nrm = 0
            local function nz(a1, a2, a3) local l = sqrt(a1 * a1 + a2 * a2 + a3 * a3); return a1 / l, a2 / l, a3 / l end
            local x1, x2, x3 = nz(Rm[1], Rm[4], Rm[7]); local y1, y2, y3 = Rm[2], Rm[5], Rm[8]
            local d = x1 * y1 + x2 * y2 + x3 * y3; y1, y2, y3 = nz(y1 - d * x1, y2 - d * x2, y3 - d * x3)
            local z1, z2, z3 = x2 * y3 - x3 * y2, x3 * y1 - x1 * y3, x1 * y2 - x2 * y1
            Rm = { x1, y1, z1, x2, y2, z2, x3, y3, z3 }
        end
        M.rot = Rm
    else M.wang = 0 end
end
local function place(x, z)
    local y = hgt(x, z) or 0
    M.x, M.z, M.y = x, z, y + R
    M.ox, M.oy, M.oz = nil, nil, nil
    M.prot, M.wang = M.rot, 0          -- no leftover spin from the last step (it would be re-applied every frame)
    M.vx, M.vy, M.vz = 0, 0, 0
    M.air, M.alive, M.squash, M.dissolve = false, true, 1, 0
    M.fall_y = M.y
end
G.place = function(x, z) place(x, z) end
local function load_course(k)
    G.ci = k; CUR = COURSES[k]; G.CUR = CUR
    G.time = (G.carry or 0) + CUR.time
    G.check = 1; G.minz = CUR.start[2]
    place(CUR.start[1], CUR.start[2])
    G.EN = {}
    for _, e in ipairs(CUR.enemies) do
        local n = { k = e.k, t = 0 }
        if e.k == "steelie" then n.x, n.z, n.hx, n.hz, n.vx, n.vz = e.x, e.z, e.x, e.z, 0, 0; n.y = (hgt(e.x, e.z) or 0) + R
        elseif e.k == "muncher" then n.x, n.z, n.hx, n.hz, n.hop = e.x, e.z, e.x, e.z, 0
        elseif e.k == "acid" then n.path, n.v, n.s, n.dir = e.path, e.v, 0, 1; n.x, n.z = e.path[1][1], e.path[1][2]
        elseif e.k == "hammer" then n.x, n.z, n.per, n.ph = e.x, e.z, e.per, e.ph; n.drop = 0 end
        G.EN[#G.EN + 1] = n
    end
    G.phase = "ready"; G.pt = 0; G.dead = nil
    M.inv = 0; G.safe_log = {}; G.race_t = 0; G.safe_tick = 0
    G.banner_set(CUR.name, 2.2)
end
G.load_course = load_course
function G.new_game_sim()
    G.score = 0; G.carry = 0; G.won = false; G.time_up = false
    load_course(1)
end

------------------------------------------------------------------ deaths
local PROBE = false   -- true while safe_point test-rolls an idle marble (no deaths, sounds or particles)
local PROBE_DEAD = false
local function kill(kind)
    if PROBE then PROBE_DEAD = true; return end
    if not M.alive then return end
    -- respawn grace: enemies and hazards can't kill a freshly respawned marble (falls still count)
    if (M.inv or 0) > 0 and (kind == "munch" or kind == "acid" or kind == "slam") then return end
    M.alive = false; G.dead = { t = 0, kind = kind }; G.deaths = (G.deaths or 0) + 1
    local p = vec3(M.x, M.y, M.z)
    if kind == "break" then sfx("break"); G.shatter(p); G.shake = 0.5
    elseif kind == "fall" then sfx("fall")
    elseif kind == "acid" then sfx("splat"); G.goo(p)
    elseif kind == "munch" then sfx("munch"); G.goo(p)
    elseif kind == "slam" then sfx("slam"); G.dust(p, 14); G.shake = 0.6 end
end
------------------------------------------------------------------ safe respawn
-- The marble used to respawn exactly on the last checkpoint. Some checkpoints sit inside an enemy's reach (Aerial
-- Race: the Marble Muncher coils 1.1 m from checkpoint 7; Ultimate Race: two munchers 0.5-1 m from theirs, and an
-- acid slime patrols straight across another), so the marble reappeared in the jaws and died again, forever.
-- Now a respawn point must be solid, level-ish ground with no drop nearby, connected to the checkpoint, and clear of
-- every hazard's reach; enemies near it are sent home; and the marble gets 2.5 s of invulnerability.
local INV_T = 2.5
local ground_move, air_move   -- defined below (marble physics); safe_point test-rolls with them
local function seg_dist(px, pz, a, b)
    local dx, dz = b[1] - a[1], b[2] - a[2]
    local t = clamp(((px - a[1]) * dx + (pz - a[2]) * dz) / max(dx * dx + dz * dz, 1e-6), 0, 1)
    return sqrt((px - a[1] - t * dx) ^ 2 + (pz - a[2] - t * dz) ^ 2)
end
-- clearance from every hazard: strict = outside a muncher's whole hunting range (it chases up to 3 m from home and
-- bites within 0.75 m), relaxed = only clear of where things are now (used if no strict point exists nearby)
local function hazard_clear(x, z, strict)
    for _, e in ipairs(G.EN) do
        if e.k == "muncher" then
            if sqrt((x - e.hx) ^ 2 + (z - e.hz) ^ 2) < (strict and 4.3 or 2.6) then return false end
            if sqrt((x - e.x) ^ 2 + (z - e.z) ^ 2) < 2.6 then return false end
        elseif e.k == "acid" then
            if seg_dist(x, z, e.path[1], e.path[2]) < (strict and 2.0 or 1.4) then return false end
        elseif e.k == "hammer" then
            if max(abs(x - e.x), abs(z - e.z)) < (strict and 1.9 or 1.5) then return false end
        elseif e.k == "steelie" then
            if sqrt((x - e.hx) ^ 2 + (z - e.hz) ^ 2) < (strict and 3.0 or 1.2) then return false end
        end
    end
    return true
end
-- solid ground: floor all round the ball (no edge within 0.9 m (a 2-wide bridge still counts)), no wall step, gentle slope
local function ground_ok(x, z, maxg)
    local y, gx, gz = hgt(x, z)
    if not y then return false end
    maxg = maxg or 0.45
    if abs(gx) > maxg or abs(gz) > maxg then return false end
    for k = 0, 7 do
        local a = k * PI / 4
        for _, r in ipairs({ 0.5, 0.9 }) do
            local h = hgt(x + cos(a) * r, z + sin(a) * r)
            if not h or abs(h - y) > STEP then return false end
        end
    end
    return true
end
-- the checkpoint can be rolled to from here: walk the straight line from the candidate (x0, z0) to the checkpoint and
-- require floor all the way, no wall-sized rise, and no drop that would shatter the marble (Aerial Race drops 1.2 m
-- from its ramp onto the snake's platform, so the upstream ramp counts as connected)
local function connected(x0, z0, x1, z1)
    -- flood fill over cells (4-neighbours, centre to centre) from the candidate's cell to the checkpoint's cell
    local i0, j0, i1, j1 = floor(x0), floor(z0), floor(x1), floor(z1)
    if not hgt(i0 + 0.5, j0 + 0.5) then return false end
    local seen, q, h = { [j0 * 1000 + i0] = true }, { { i0, j0 } }, 1
    while h <= #q and #q < 600 do
        local i, j = q[h][1], q[h][2]; h = h + 1
        if i == i1 and j == j1 then return true end
        local y = hgt(i + 0.5, j + 0.5)
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local ni, nj = i + d[1], j + d[2]
            if not seen[nj * 1000 + ni] and abs(ni - i0) + abs(nj - j0) <= 14 then
                local ny = hgt(ni + 0.5, nj + 0.5)
                if ny and ny - y <= STEP + 0.05 and y - ny <= 3 then seen[nj * 1000 + ni] = true; q[#q + 1] = { ni, nj } end
            end
        end
    end
    return false
end
-- would a marble left alone here stay safe? Roll it with the real physics for 3.5 s, no input: it must not fall,
-- shatter or roll into a hazard's reach, and must end on solid ground (Aerial Race: the spot behind the snake is a
-- ramp that drops the marble onto the snake's platform and then off its far side)
local function idle_safe(x, z)
    local keep = {}
    for _, k in ipairs({ "x", "y", "z", "vx", "vy", "vz", "air", "fall_y" }) do keep[k] = M[k] end
    PROBE, PROBE_DEAD = true, false
    M.x, M.z = x, z; M.y = (hgt(x, z) or 0) + R; M.vx, M.vy, M.vz, M.air, M.fall_y = 0, 0, 0, false, M.y
    local ok = true
    for _ = 1, 420 do
        if M.air then air_move(1 / 120, 0, 0) else ground_move(1 / 120, 0, 0) end
        if PROBE_DEAD or (not M.air and not hazard_clear(M.x, M.z, false)) then ok = false; break end
    end
    if ok then ok = not M.air and ground_ok(M.x, M.z) and hazard_clear(M.x, M.z, true) end
    PROBE = false
    for k, v in pairs(keep) do M[k] = v end
    return ok
end
G.idle_safe = idle_safe
-- good = strict hazard clearance, an idle marble stays safe there, and not ahead of the checkpoint (a respawn
-- shouldn't skip the marble past the hazard that killed it); otherwise the best fallback is returned with good = false
local function safe_point(ci, good_only)
    local c = CUR.checks[ci]
    local cands = {}
    for _, strict in ipairs({ true, false }) do
        for r = 0, 7, 0.5 do
            local nrm = max(1, floor(r * 2 * PI / 0.6))
            for k = 0, nrm - 1 do
                local a = k * 2 * PI / nrm
                local x, z = c[1] + cos(a) * r, c[2] + sin(a) * r
                if ground_ok(x, z) and hazard_clear(x, z, strict) and connected(x, z, c[1], c[2]) then
                    local _, gx, gz = hgt(x, z)
                    local ahead = z < c[2] - 0.5
                    cands[#cands + 1] = { x, z, strict = strict, ahead = ahead, sc = r + (ahead and 6 or 0) + (abs(gx) + abs(gz)) * 3 + (strict and 0 or 20) }
                end
            end
        end
    end
    table.sort(cands, function(p, q) return p.sc < q.sc end)
    local fb
    for i, p in ipairs(cands) do
        if i > 80 then break end
        local idle = idle_safe(p[1], p[2])
        if p.strict and not p.ahead and idle then return p[1], p[2], true end
        if not fb and idle then fb = p end
    end
    if good_only then return nil end
    fb = fb or cands[1]
    if fb then return fb[1], fb[2], false end
    return nil
end
G.safe_point = safe_point
local function respawn()
    -- newest recorded safe spot (logged while rolling, at least 1 s before the death), else the checkpoint search;
    -- fall back to earlier checkpoints if a checkpoint has no safe ground at all
    local x, z, how
    local log = G.safe_log or {}
    for i = #log, 1, -1 do
        local p = log[i]
        if G.race_t - p.t > 1.0 and ground_ok(p.x, p.z) and hazard_clear(p.x, p.z, true) and idle_safe(p.x, p.z) then x, z, how = p.x, p.z, "last safe spot"; break end
    end
    -- else the latest checkpoint with a good spot near it (flat, clear, not past the hazard); else the best fallback
    if not x then
        for ci = G.check, 1, -1 do
            local sx, sz = safe_point(ci, true)
            if sx then x, z, how = sx, sz, "checkpoint " .. ci; break end
        end
    end
    if not x then
        local sx, sz = safe_point(G.check)
        if sx then x, z, how = sx, sz, "checkpoint " .. G.check .. " (fallback)" end
    end
    if not x then local c = CUR.checks[G.check]; x, z, how = c[1], c[2], "checkpoint (raw)" end
    place(x, z); G.dead = nil; sfx("hop")
    M.inv = INV_T; G.respawn_info = how
    -- enemies near the respawn or its checkpoint go back home (steelies stop dead), so nothing is waiting there
    local c = CUR.checks[G.check]
    for _, e in ipairs(G.EN) do
        local d = min(sqrt((e.x - x) ^ 2 + (e.z - z) ^ 2), sqrt((e.x - c[1]) ^ 2 + (e.z - c[2]) ^ 2))
        if (e.k == "muncher" or e.k == "steelie") and d < 8 then
            e.x, e.z = e.hx, e.hz; e.ox, e.oz = e.x, e.z
            if e.k == "steelie" then e.vx, e.vz = 0, 0; e.y = (hgt(e.x, e.z) or e.y - R) + R; e.oy = e.y end
        end
    end
    G.safe_log = {}
end
G.respawn = function() respawn() end
G.kill = function(k) kill(k) end

------------------------------------------------------------------ marble physics
function ground_move(dt, ax, az)
    local y, gx, gz = hgt(M.x, M.z)
    if not y then M.air = true; return end
    local gs = CUR.gravity
    -- slope acceleration of a rolling ball (Silly Race: gravity pulls you UP the slopes)
    local den = 1 + gx * gx + gz * gz
    ax = ax - G0 * ROLLK * gs * gx / den
    az = az - G0 * ROLLK * gs * gz / den
    M.vx = M.vx + ax * dt; M.vz = M.vz + az * dt
    local fr = 1 - min(1, 0.35 * dt)
    M.vx, M.vz = M.vx * fr, M.vz * fr
    local sp = sqrt(M.vx * M.vx + M.vz * M.vz)
    if sp > MAXV then M.vx, M.vz = M.vx / sp * MAXV, M.vz / sp * MAXV end
    -- per-axis wall test against the next surface
    local base = M.y - R
    local nx, nz = M.x + M.vx * dt, M.z + M.vz * dt
    local function blocked(px, pz)
        local hy = hgt(px + (px > M.x and R * 0.6 or (px < M.x and -R * 0.6 or 0)), pz + (pz > M.z and R * 0.6 or (pz < M.z and -R * 0.6 or 0)))
        return hy and hy > base + STEP
    end
    local hit = false
    if blocked(nx, M.z) then nx = M.x; if abs(M.vx) > 2 then hit = true end; M.vx = -M.vx * 0.4 end
    if blocked(nx, nz) then nz = M.z; if abs(M.vz) > 2 then hit = true end; M.vz = -M.vz * 0.4 end
    if hit and not PROBE then sfx("bump"); G.sparks(vec3(M.x, M.y, M.z), 6) end
    M.x, M.z = nx, nz
    local y2, gx2, gz2 = hgt(M.x, M.z)
    if not y2 or y2 < base - 0.5 then
        -- launched off an edge: keep the slope's vertical velocity
        M.air = true; M.vy = M.vx * gx + M.vz * gz; M.fall_y = M.y
    else
        M.vy = M.vx * gx2 + M.vz * gz2
        M.y = y2 + R
    end
end
function air_move(dt, ax, az)
    M.vx = M.vx + ax * 0.25 * dt; M.vz = M.vz + az * 0.25 * dt
    M.vy = M.vy - G0 * dt
    local base = M.y - R
    local nx, nz = M.x + M.vx * dt, M.z + M.vz * dt
    local hx = hgt(nx, M.z); if hx and hx > base + STEP then nx = M.x; M.vx = -M.vx * 0.3 end
    local hz = hgt(nx, nz); if hz and hz > base + STEP then nz = M.z; M.vz = -M.vz * 0.3 end
    M.x, M.z = nx, nz
    M.y = M.y + M.vy * dt
    M.fall_y = max(M.fall_y, M.y)
    local y = hgt(M.x, M.z)
    if y and M.y - R <= y then
        local drop = M.fall_y - M.y
        M.y = y + R
        if drop > BREAK_DROP then kill("break"); return end
        if drop > 0.8 and not PROBE then sfx("clack"); G.dust(vec3(M.x, y + 0.05, M.z), 5) end
        M.air = false; M.vy = 0
    elseif M.y < CUR.lo - 8 then kill("fall") end
end

------------------------------------------------------------------ enemies
local function enemies_step(dt)
    for _, e in ipairs(G.EN) do
        e.ox, e.oy, e.oz = e.x, e.y, e.z
        e.t = e.t + dt
        if e.k == "steelie" then
            -- chases the marble when close, otherwise drifts home
            local tx, tz = M.x, M.z
            local dx, dz = tx - e.x, tz - e.z
            local d = sqrt(dx * dx + dz * dz)
            if d > 9 or not M.alive or (M.inv or 0) > 0 then tx, tz = e.hx, e.hz; dx, dz = tx - e.x, tz - e.z; d = sqrt(dx * dx + dz * dz) end
            if d > 0.05 then e.vx = e.vx + dx / d * 7 * dt; e.vz = e.vz + dz / d * 7 * dt end
            local fr = 1 - min(1, 1.2 * dt); e.vx, e.vz = e.vx * fr, e.vz * fr
            local nx, nz = e.x + e.vx * dt, e.z + e.vz * dt
            local hy = hgt(nx, nz); local cy = hgt(e.x, e.z) or hy
            if hy and cy and abs(hy - cy) < STEP then e.x, e.z = nx, nz else e.vx, e.vz = -e.vx * 0.5, -e.vz * 0.5 end
            e.y = (hgt(e.x, e.z) or e.y - R) + R
            e.roll = (e.roll or 0) + sqrt(e.vx * e.vx + e.vz * e.vz) * dt / R
            -- collide with the marble: heavier steelie, elastic push
            if M.alive and not M.air and (M.inv or 0) <= 0 then   -- a respawning marble is a ghost to steelies
                local cx, cz = M.x - e.x, M.z - e.z
                local cd = sqrt(cx * cx + cz * cz)
                if cd < 2 * R and cd > 1e-4 then
                    local nxx, nzz = cx / cd, cz / cd
                    local rel = (M.vx - e.vx) * nxx + (M.vz - e.vz) * nzz
                    if rel < 0 then
                        M.vx = M.vx - 1.6 * rel * nxx; M.vz = M.vz - 1.6 * rel * nzz
                        e.vx = e.vx + 0.4 * rel * nxx; e.vz = e.vz + 0.4 * rel * nzz
                        sfx("clack"); G.sparks(vec3(e.x + nxx * R, e.y, e.z + nzz * R), 8)
                    end
                    local push = 2 * R - cd
                    M.x, M.z = M.x + nxx * push * 0.8, M.z + nzz * push * 0.8
                    e.x, e.z = e.x - nxx * push * 0.2, e.z - nzz * push * 0.2
                end
            end
        elseif e.k == "muncher" then
            -- Marble Muncher: hops toward the marble when it comes close
            e.hop = (e.hop + dt * 2.4) % 1
            local dx, dz = M.x - e.x, M.z - e.z
            local d = sqrt(dx * dx + dz * dz)
            local hd = sqrt((e.x - e.hx) ^ 2 + (e.z - e.hz) ^ 2)
            if M.alive and (M.inv or 0) <= 0 and d < 4.5 and d > 0.1 and hd < 3 then e.x, e.z = e.x + dx / d * 1.6 * dt, e.z + dz / d * 1.6 * dt
            elseif hd > 0.1 then e.x, e.z = e.x + (e.hx - e.x) * dt, e.z + (e.hz - e.z) * dt end
            if e.hop < dt * 2.4 then sfx("hop") end
            if M.alive and d < 0.75 and M.y - R < (hgt(e.x, e.z) or 0) + 0.9 then kill("munch") end
        elseif e.k == "acid" then
            local a, b = e.path[1], e.path[2]
            local L = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
            e.s = e.s + e.dir * e.v * dt / L
            if e.s > 1 then e.s, e.dir = 1, -1 elseif e.s < 0 then e.s, e.dir = 0, 1 end
            e.x, e.z = lerp(a[1], b[1], e.s), lerp(a[2], b[2], e.s)
            local d = sqrt((M.x - e.x) ^ 2 + (M.z - e.z) ^ 2)
            if M.alive and not M.air and d < 0.85 then kill("acid") end
        elseif e.k == "hammer" then
            -- raised, then a quick slam (12% of the cycle), then a slow lift
            local c = ((e.t + e.ph) / e.per) % 1
            local was = e.drop
            if c < 0.7 then e.drop = 0 elseif c < 0.78 then e.drop = (c - 0.7) / 0.08 elseif c < 0.9 then e.drop = 1 else e.drop = 1 - (c - 0.9) / 0.1 end
            if was < 1 and e.drop >= 1 then sfx("slam"); G.dust(vec3(e.x, (hgt(e.x, e.z) or 0) + 0.1, e.z), 8) end
            local d = max(abs(M.x - e.x), abs(M.z - e.z))
            if M.alive and e.drop > 0.85 and d < 0.75 + R * 0.5 then kill("slam") end
        end
    end
end

------------------------------------------------------------------ course step
-- The renderer draws every moving thing between its previous and current step (AL = leftover fraction of a step).
-- Any step that does NOT integrate something must collapse that interpolation to the current state, otherwise the
-- stale "previous" values keep being blended in with a different AL every frame and the object trembles in place.
local function hold_marble()
    M.ox, M.oy, M.oz = M.x, M.y, M.z
    M.prot, M.wang = M.rot, 0
end
local function hold_enemies() for _, e in ipairs(G.EN) do e.ox, e.oy, e.oz = e.x, e.y, e.z end end
G.hold_marble = hold_marble
-- after the goal line the marble coasts to a stop on the goal pad instead of freezing mid-roll
local function goal_coast(dt)
    M.ox, M.oy, M.oz = M.x, M.y, M.z
    if M.air or not M.alive then hold_marble(); return end
    local k = math.exp(-4.5 * dt)
    M.vx, M.vz = M.vx * k, M.vz * k
    local g = CUR.goal
    local nx, nz = M.x + M.vx * dt, M.z + M.vz * dt
    if (nx < g[1] + R and M.vx < 0) or (nx > g[3] - R and M.vx > 0) then M.vx = 0 end   -- stay on the pad
    if (nz < g[2] + R and M.vz < 0) or (nz > g[4] - R and M.vz > 0) then M.vz = 0 end
    if M.vx * M.vx + M.vz * M.vz < 1e-4 then M.vx, M.vz = 0, 0 end
    ground_move(dt, 0, 0)
    M.vx, M.vz = M.vx * k, M.vz * k
    if M.air then M.air = false; M.y = (hgt(M.x, M.z) or M.y - R) + R; M.vy = 0 end
    orient_step(dt)
    if M.vx == 0 and M.vz == 0 then M.prot, M.wang = M.rot, 0 end
end
function G.course_step(inp, dt)
    G.pt = G.pt + dt
    if G.phase == "ready" then
        hold_marble()
        if G.pt > 1.6 then G.phase = "race"; G.pt = 0; sfx("go"); G.music_race() end
        enemies_step(dt); return
    end
    if G.phase == "goal" then
        goal_coast(dt); hold_enemies()
        if G.pt > 3.2 then
            if G.ci >= #COURSES then G.won = true; G.finished = true
            else G.carry = G.carry_next; load_course(G.ci + 1) end
        end
        return
    end
    if G.phase == "timeup" then hold_marble(); hold_enemies(); if G.pt > 2.4 then G.finished = true end; return end
    -- clock (keeps running while the marble is broken)
    local before = math.ceil(G.time)
    G.time = G.time - dt
    if math.ceil(G.time) ~= before and G.time < 10 and G.time > 0 then sfx("tick") end
    if G.time <= 0 then G.time = 0; G.phase = "timeup"; G.pt = 0; sfx("timeup"); G.banner_set("Time Out", 2.4); return end
    enemies_step(dt)
    if not M.alive then
        hold_marble()
        G.dead.t = G.dead.t + dt
        if G.dead.t > 2 then respawn() end
        return
    end
    M.ox, M.oy, M.oz = M.x, M.y, M.z
    G.race_t = (G.race_t or 0) + dt
    M.inv = max(0, (M.inv or 0) - dt)
    -- remember where the marble was recently safe (on the ground, away from edges and every hazard's reach)
    G.safe_tick = (G.safe_tick or 0) - dt
    if G.safe_tick <= 0 and not M.air then
        G.safe_tick = 0.25
        if ground_ok(M.x, M.z) and hazard_clear(M.x, M.z, true) then
            local log = G.safe_log; log[#log + 1] = { x = M.x, z = M.z, t = G.race_t }
            if #log > 24 then table.remove(log, 1) end
        end
    end
    local ax, az = inp.ax * 16, inp.az * 16
    local n = 2
    for _ = 1, n do
        if not M.alive then break end
        if M.air then air_move(dt / n, ax, az) else ground_move(dt / n, ax, az) end
    end
    local sp = sqrt(M.vx * M.vx + M.vz * M.vz)
    if M.alive then orient_step(dt) end
    M.roll = (M.roll + sp * dt / R * 57.2958) % 360
    if sp > 0.3 then M.head = math.deg(atan2(M.vx, M.vz)) end
    G.speed = sp
    -- progress points and checkpoints
    if M.z < G.minz - 1 then local d = floor(G.minz - M.z); G.minz = G.minz - d; add_score(10 * d * G.ci) end
    local nc = CUR.checks[G.check + 1]
    if nc and (M.x - nc[1]) ^ 2 + (M.z - nc[2]) ^ 2 < 9 then G.check = G.check + 1 end
    -- goal
    local g = CUR.goal
    if M.x >= g[1] and M.x <= g[3] and M.z >= g[2] and M.z <= g[4] and not M.air then
        G.phase = "goal"; G.pt = 0
        local left = floor(G.time)
        G.bonus = left * 100 * G.ci; add_score(G.bonus); G.carry_next = left
        sfx("goal"); G.banner_set("Goal!", 3)
        G.flash(vec3(M.x, M.y + 2, M.z), { 1, .9, .6 }, 60, 0.6, 9)
    end
end
G.shatter, G.sparks, G.goo, G.dust, G.flash = shatter, sparks, goo, dust, flash
------------------------------------------------------------------ world nodes
local function V(x, y, z) return vec3(x, y, z) end
G.shake = 0
local W = { course = {}, cur = nil }
local NM = {}
local function build_world()
    for k, c in ipairs(COURSES) do
        local list = {}
        for _, m in ipairs(c.meshes) do
            if tnode(m) then list[#list + 1] = clone(m, HIDE) end
        end
        W.course[k] = list
    end
    W.floor = clone("floor", HIDE)
    NM.marble = clone("marble", HIDE); NM.shadow = clone("shadow", HIDE)
    NM.shards = {}
    for i = 1, 10 do NM.shards[i] = { n = clone("shard", HIDE) } end
    NM.pole = clone("flag_pole", HIDE); NM.cloth = clone("flag_cloth", HIDE); NM.chute = clone("chute", HIDE)
end
local ENR = {}
local function enemy_nodes()
    for _, r in ipairs(ENR) do for _, n in pairs(r) do n:set_position(HIDE) end end
    ENR = {}
    for i, e in ipairs(G.EN) do
        local r = {}
        if e.k == "steelie" then r.ball = clone("steelie", HIDE); r.sh = clone("shadow", HIDE)
        elseif e.k == "muncher" then r.coil = clone("mun_coil", HIDE); r.head = clone("mun_head", HIDE); r.eye = clone("mun_eye", HIDE)
        elseif e.k == "acid" then r.blob = clone("acid", HIDE)
        elseif e.k == "hammer" then r.post = clone("ham_post", HIDE); r.head = clone("ham_head", HIDE) end
        ENR[i] = r
    end
end
-- node reuse: course switch hides the old course and shows the new (meshes are authored in world space)
-- Every other course is hidden explicitly. (Bug fix: reset_world() used to clear W.cur without hiding the course that
-- was showing, so after a game over on race 2+ and a new game, that course's geometry stayed visible on top of the
-- Practice Race: its higher funnel buried the start platform, which looked low, and the marble seemed trapped.)
local function show_course(k)
    if W.cur == k then return end
    for kk, list in ipairs(W.course) do if kk ~= k then for _, n in ipairs(list) do n:set_position(HIDE) end end end
    for _, n in ipairs(W.course[k]) do n:set_position(V(0, 0, 0)) end
    W.cur = k
    local c = COURSES[k]
    W.floor:set_position(V(c.nx / 2, c.lo - 7, c.nz / 2)); W.floor:set_scale(V(c.nx * 3, 1, c.nz * 3))
    local g = c.goal
    local gx, gz = g[3] + 0.1, (g[2] + g[4]) / 2
    local gy = G.hgt((g[1] + g[3]) / 2, gz) or 0
    NM.pole:set_position(V(gx, gy, gz)); NM.cloth:set_position(V(gx, gy, gz))
    local s = c.start
    NM.chute:set_position(V(s[1], (G.hgt(s[1], s[2]) or 0) + 3.2, s[2]))
    G.ens_ver = nil
end
G.show_course = show_course
function G.reset_world() W.cur = nil end

-- render interpolation: the simulation runs at a fixed 60 Hz, the display at any rate; draw the state between the
-- last two steps (AL = leftover fraction of a step) so the marble moves the same distance every displayed frame.
local function ip(e, k) local o = e["o" .. k]; local v = e[k]; if not o or abs(v - o) > 3 then return v end; return o + (v - o) * AL end
function G.marble_pos() local M = G.M; return ip(M, "x"), ip(M, "y"), ip(M, "z") end
function G.rendered_pos() local x, y, z = G.marble_pos(); return { x, y, z } end
-- rotation matrix (rows) -> engine euler degrees (engine builds R = Rz * Ry * Rx from set_rotation)
local function mat_euler(m)
    local sy = -m[7]; sy = sy > 1 and 1 or (sy < -1 and -1 or sy)
    local y = math.asin(sy)
    local x, z
    if abs(sy) < 0.9999 then x = atan2(m[8], m[9]); z = atan2(m[4], m[1]) else x = atan2(-m[6], m[5]); z = 0 end
    return V(math.deg(x), math.deg(y), math.deg(z))
end
local function render_world(dt)
    local k = G.ci or 1
    show_course(k)
    if G.ens_ver ~= G.EN then G.ens_ver = G.EN; enemy_nodes() end
    local M = G.M
    NM.cloth:set_rotation(V(0, 8 * sin(G.t * 2.1), 0))
    -- marble
    local vis = M.alive
    local shvis = vis   -- the contact shadow stays on while the marble blinks, so you never lose track of it
    -- respawn grace: the marble blinks while it can't be killed (steady for the last moment so it's clear it ended)
    if vis and (M.inv or 0) > 0.15 and floor(M.inv * 12) % 2 == 1 then vis = false end
    local sq = 1
    local mx, my, mz = G.marble_pos()
    NM.marble:set_position(vis and V(mx, my, mz) or HIDE)
    -- orientation: last step's rotation advanced by the same interpolation fraction (no Euler flips when the heading reverses)
    local Rm = M.rot
    if M.prot and M.wang and M.wang > 0 and AL < 1 then Rm = G.mmul(G.mrot_axis(M.wax, 0, M.waz, M.wang * AL), M.prot) end
    NM.marble:set_rotation(mat_euler(Rm))
    G.rend_R = Rm      -- (tests: per-frame rendered orientation)
    -- contact shadow on the surface under the marble
    local gy = G.hgt(mx, mz)
    if shvis and gy then
        local h = my - R - gy
        local s = clamp(1 - h * 0.12, 0.35, 1) * 0.52
        NM.shadow:set_position(V(mx + 0.06, gy + 0.02, mz + 0.04)); NM.shadow:set_scale(V(s, 1, s))
    else NM.shadow:set_position(HIDE) end
    -- broken-marble shards (break, slam) / dissolved (acid, munch) show no shards
    local d = G.dead
    for i, s in ipairs(NM.shards) do
        if d and (d.kind == "break" or d.kind == "slam") and d.t < 1.6 then
            if d.t == 0 or not s.vx or s.gen ~= d then
                local a = i / #NM.shards * 6.2832
                s.gen = d; s.x, s.y, s.z = M.x, M.y, M.z
                s.vx, s.vy, s.vz = cos(a) * rr(1.5, 3.5), d.kind == "slam" and 0.5 or rr(2, 5), sin(a) * rr(1.5, 3.5)
                s.rx, s.ry = rr(0, 360), rr(0, 360)
            end
            s.vy = s.vy - 18 * dt
            s.x, s.y, s.z = s.x + s.vx * dt, s.y + s.vy * dt, s.z + s.vz * dt
            local fy = G.hgt(s.x, s.z)
            if fy and s.y < fy + 0.05 and s.vy < 0 then s.y = fy + 0.05; s.vy = -s.vy * 0.3; s.vx, s.vz = s.vx * 0.6, s.vz * 0.6 end
            s.rx = s.rx + dt * 400
            s.n:set_position(V(s.x, s.y, s.z)); s.n:set_rotation(V(s.rx, s.ry, s.rx * 0.5))
        else s.n:set_position(HIDE) end
    end
    -- enemies
    for i, e in ipairs(G.EN) do
        local r = ENR[i]
        if r then
            local y = G.hgt(e.x, e.z) or 0
            if e.k == "steelie" then
                local ex, ey, ez = ip(e, "x"), ip(e, "y"), ip(e, "z")
                r.ball:set_position(V(ex, ey, ez)); r.ball:set_rotation(V((e.roll or 0) * 57.3 % 360, math.deg(atan2(e.vx, e.vz)), 0))
                r.sh:set_position(V(ex + 0.06, (G.hgt(ex, ez) or y) + 0.02, ez + 0.04)); r.sh:set_scale(V(0.52, 1, 0.52))
            elseif e.k == "muncher" then
                local hp = sin(e.hop * PI)
                local st = 0.55 + 0.6 * hp
                r.coil:set_position(V(e.x, y, e.z)); r.coil:set_scale(V(1, st, 1))
                r.head:set_position(V(e.x, y + st * 0.9, e.z)); r.head:set_rotation(V(0, math.deg(atan2(M.x - e.x, M.z - e.z)), 0))
                r.eye:set_position(V(e.x, y + st * 0.9, e.z)); r.eye:set_rotation(V(0, math.deg(atan2(M.x - e.x, M.z - e.z)), 0))
            elseif e.k == "acid" then
                local ex, ez = ip(e, "x"), ip(e, "z"); y = G.hgt(ex, ez) or y
                local w = 1 + 0.12 * sin(G.t * 5 + i)
                r.blob:set_position(V(ex, y + 0.03, ez)); r.blob:set_scale(V(w, 1 + 0.2 * sin(G.t * 7 + i), 2 - w))
            elseif e.k == "hammer" then
                r.post:set_position(V(e.x, y, e.z))
                r.head:set_position(V(e.x, y + 0.3 + 2.4 * (1 - e.drop), e.z))
            end
        end
    end
end

------------------------------------------------------------------ camera: fixed isometric-style view that follows the marble
local function update_camera(dt)
    local M = G.M
    local yaw = G.CAM_YAW
    local fx, fz = sin(yaw), cos(yaw)
    local tx, ty, tz = G.marble_pos()
    if G.state == "title" then
        local c = COURSES[G.ci or 1]
        tx, tz = c.nx / 2 + 6 * sin(G.t * 0.1), c.nz * 0.55 + c.nz * 0.3 * sin(G.t * 0.05)
        ty = G.hgt(tx, tz) or (c.lo + 10)
    end
    local L = G.cam.look
    local k = G.cam_snap and 1 or (1 - math.exp(-4 * dt))
    G.cam_snap = false
    L.x, L.y, L.z = L.x + (tx - L.x) * k, L.y + (ty - L.y) * k * 0.7, L.z + (tz - L.z) * k
    local D, H = 21, 25
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.3 * SET:shake_scale()
    cam:set_position(V(L.x - fx * D + a * sin(G.t * 53), L.y + H, L.z - fz * D + a * cos(G.t * 61)))
    cam:look_at(V(L.x, L.y, L.z))
end
-- camera-relative input axes: forward (screen up) and right
function G.cam_axes() local yaw = G.CAM_YAW; local fx, fz = sin(yaw), cos(yaw); return fx, fz, -fz, fx end

------------------------------------------------------------------ collider debug overlay (F3)
G.DBG = { on = false, pool = {}, used = 0, w = 0.05 }
local DC = { me = { .2, 1, .3 }, enemy = { 1, .25, .2 }, wall = { .4, .7, 1 }, goal = { 1, .9, .3 }, check = { .3, .8, 1 } }
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
local function dcircle(x, y, z, r, col, n)
    n = n or 12
    for i = 0, n - 1 do
        local a0, a1 = i / n * 6.2832, (i + 1) / n * 6.2832
        G.dbg_bar(V(x + cos(a0) * r, y, z + sin(a0) * r), V(x + cos(a1) * r, y, z + sin(a1) * r), col)
    end
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and G.state ~= "title" then
        local M, C = G.M, G.CUR
        if M.alive then dcircle(M.x, M.y, M.z, R, DC.me); dcircle(M.x, M.y - R + 0.03, M.z, R * 0.6, DC.me, 8) end
        for _, e in ipairs(G.EN) do
            local y = (G.hgt(e.x, e.z) or 0) + 0.06
            if e.k == "steelie" then dcircle(e.x, e.y, e.z, R, DC.enemy)
            elseif e.k == "muncher" then dcircle(e.x, y, e.z, 0.75, DC.enemy)
            elseif e.k == "acid" then dcircle(e.x, y, e.z, 0.85, DC.enemy)
            elseif e.k == "hammer" then
                local r = 0.75 + R * 0.5
                G.dbg_bar(V(e.x - r, y, e.z - r), V(e.x + r, y, e.z - r), DC.enemy); G.dbg_bar(V(e.x + r, y, e.z - r), V(e.x + r, y, e.z + r), DC.enemy)
                G.dbg_bar(V(e.x + r, y, e.z + r), V(e.x - r, y, e.z + r), DC.enemy); G.dbg_bar(V(e.x - r, y, e.z + r), V(e.x - r, y, e.z - r), DC.enemy)
            end
        end
        -- wall edges (rises taller than a step) near the marble
        local ci, cj = floor(M.x), floor(M.z)
        for j = cj - 6, cj + 6 do for i = ci - 6, ci + 6 do
            local a = G.hgt(i + 0.5, j + 0.5)
            if a then
                local function edge(ni, nj, x0, z0, x1, z1)
                    local b = G.hgt(ni + 0.5, nj + 0.5)
                    if not b or abs(b - a) > STEP + 0.2 then G.dbg_bar(V(x0, (G.hgt(x0 * 0.98 + (i + .5) * .02, z0 * 0.98 + (j + .5) * .02) or a) + 0.04, z0), V(x1, (G.hgt(x1 * 0.98 + (i + .5) * .02, z1 * 0.98 + (j + .5) * .02) or a) + 0.04, z1), DC.wall) end
                end
                edge(i - 1, j, i, j, i, j + 1); edge(i + 1, j, i + 1, j, i + 1, j + 1); edge(i, j - 1, i, j, i + 1, j); edge(i, j + 1, i, j + 1, i + 1, j + 1)
            end
        end end
        local g = C.goal; local gy = (G.hgt((g[1] + g[3]) / 2, (g[2] + g[4]) / 2) or 0) + 0.08
        G.dbg_bar(V(g[1], gy, g[2]), V(g[3], gy, g[2]), DC.goal); G.dbg_bar(V(g[3], gy, g[2]), V(g[3], gy, g[4]), DC.goal)
        G.dbg_bar(V(g[3], gy, g[4]), V(g[1], gy, g[4]), DC.goal); G.dbg_bar(V(g[1], gy, g[4]), V(g[1], gy, g[2]), DC.goal)
        for q, c in ipairs(C.checks) do local y = (G.hgt(c[1], c[2]) or 0) + 0.08; dcircle(c[1], y, c[2], 3, q <= G.check and DC.me or DC.check, 16) end
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
    panel("lp", 20 * US, 20 * US, LW, 200 * US, play, 0.5)
    text("l1", "Score", 40 * US, 30 * US, LW - 40 * US, 34 * US, 1.0, RED, "left", play)
    text("l2", pad6(G.score), 40 * US, 62 * US, LW - 40 * US, 52 * US, 1.8, WHITE, "left", play)
    text("l3", "High Score", 40 * US, 120 * US, LW - 40 * US, 34 * US, 1.0, RED, "left", play)
    text("l4", pad6(max(G.hiscore, G.score)), 40 * US, 152 * US, LW - 40 * US, 52 * US, 1.5, WHITE, "left", play)
    panel("rp", SW - LW - 20 * US, 20 * US, LW, 200 * US, play, 0.5)
    local tl = G.time or 0
    text("r1", "Time", SW - LW, 30 * US, LW - 40 * US, 34 * US, 1.0, RED, "right", play)
    text("r2", tostring(math.ceil(tl)), SW - LW, 62 * US, LW - 40 * US, 70 * US, 2.6, tl < 10 and RED or GOLD, "right", play)
    text("r3", G.CUR and G.CUR.name or "", SW - LW, 150 * US, LW - 40 * US, 40 * US, 1.1, WHITE, "right", play)
    G.banner.t = (G.banner.t or 0) - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    text("ban", G.banner.text or "", 0, SH * 0.16, SW, 80 * US, 2.4, { 1, .88, .45, ba }, "center", play and G.banner.t > 0)
    local gl = play and G.phase == "goal" and G.pt > 0.6
    text("gb", "Time Bonus  " .. tostring(G.bonus or 0), 0, SH * 0.16 + 90 * US, SW, 50 * US, 1.5, WHITE, "center", gl)
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 470 * US, SH * 0.06, 940 * US, SH * 0.62, title, 0.62)
    text("t_title", "Marble Madness Remix", 0, SH * 0.08, SW, 130 * US, 3.8, { .55, .7, 1, 1 }, "center", title)
    text("t_sub", "Roll your marble to the goal of six races before time runs out", 0, SH * 0.08 + 120 * US, SW, 40 * US, 1.0, DIM, "center", title)
    local CL = { "WASD / Arrows: push the marble (diagonals roll diagonally)   ·   Mouse: trackball",
        "Unused seconds carry over to the next race   ·   long drops shatter the marble",
        "Steelies push you · Marble Munchers and acid eat you · hammers flatten you",
        "P / Esc: pause   ·   O: settings   ·   M: mute   ·   F3: colliders" }
    for i, l in ipairs(CL) do text("t_c" .. i, l, SW / 2 - 460 * US, SH * 0.47 + (i - 1) * 34 * US, 920 * US, 34 * US, 0.92, DIM, "center", title) end
    text("t_hi", "High Score " .. tostring(G.hiscore), 0, SH * 0.47 + 150 * US, SW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, GOLD, "center", pause)
    local over = st == "over" and not G.set_open
    panel("o_bg", SW / 2 - 400 * US, SH * 0.22, 800 * US, SH * 0.56, over, 0.78)
    text("o_t", G.won and "Congratulations!" or "Game Over", 0, SH * 0.24, SW, 90 * US, 3.0, G.won and GOLD or RED, "center", over)
    text("o_m", G.won and "You finished all six races" or ("Time ran out on the " .. (G.CUR and G.CUR.name or "")), 0, SH * 0.24 + 92 * US, SW, 40 * US, 1.2, DIM, "center", over)
    text("o_s", "Score " .. tostring(G.score), 0, SH * 0.24 + 140 * US, SW, 44 * US, 1.4, WHITE, "center", over)
    local c = {}
    local yb = SH * 0.3
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
function G.music_race() music("race" .. tostring(((G.ci or 1) - 1) % 3 + 1)) end
local function to_title()
    G.state = "title"; G.won = false
    G.new_game_sim(); G.reset_world()
    music("title")
end
G.to_title = to_title
local function new_game()
    G.reset_world(); G.new_game_sim(); G.finished = false
    G.state = "play"; G.cam_snap = true
    music(nil)
end
G.new_game = new_game
local function game_over()
    G.state = "over"; G.over_t = 0
    music(G.won and "ending" or nil); sfx(G.won and "goal" or "timeup")
    if G.score > G.hiscore then G.hiscore = G.score; save_hi() end
end
local acc = 0
local mprev = { x = 0, y = 0 }
local macc = { x = 0, y = 0 }
local function update(dt)
    flush_mats()
    dt = clamp(dt, 0, 0.1)   -- a negative frame time (timer hitch) would make every damp() explode
    G.t = G.t + dt; G.dt = dt
    local k = { ret = edge("Return"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), qk = edge("Q"), f3 = edge("F3"), space = edge("Space") }
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        if k.ret or k.space or c.start then sfx("click"); new_game()
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click") end
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
    -- mouse trackball (relative mode in play)
    local mdx, mdy = 0, 0
    pcall(function() local d = input.get_mouse_delta(); if d then mdx, mdy = d.x or d[1] or 0, d.y or d[2] or 0 end end)
    if st == "play" and not G.set_open then
        local mx = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0)
        local my = (any("Up", "W") and 1 or 0) - (any("Down", "S") and 1 or 0)
        if (mx ~= 0 or my ~= 0) and (mx ~= mprev.x or my ~= mprev.y) and G.M.alive and G.phase == "race" then sfx("roll" .. tostring(floor(rand() * 6))) end
        mprev.x, mprev.y = mx, my
        if mx ~= 0 and my ~= 0 then mx, my = mx * 0.7071, my * 0.7071 end
        -- mouse flicks add a short impulse spread over the next frames
        macc.x = clamp(macc.x + mdx * 0.02, -3, 3); macc.y = clamp(macc.y - mdy * 0.02, -3, 3)
        mx, my = mx + macc.x, my + macc.y
        macc.x, macc.y = macc.x * math.exp(-10 * dt), macc.y * math.exp(-10 * dt)
        if G.autoplay then mx, my = G.autoplay_fn() end
        local fx, fz, rx, rz = G.cam_axes()
        local inp = { ax = clamp(fx * my + rx * mx, -2, 2), az = clamp(fz * my + rz * mx, -2, 2) }
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 4 do
            G.course_step(inp, FR)
            acc = acc - FR; n = n + 1
        end
        if acc > FR * 4 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if G.finished and G.state == "play" then G.finished = false; game_over() end
        -- rolling sound loop scaled by speed
        G.roll_t = (G.roll_t or 0) - dt
        if G.roll_t <= 0 and G.M.alive and not G.M.air and (G.speed or 0) > 2 then G.roll_t = 0.45; sfx("roll" .. tostring(min(5, floor(G.speed / 2.5)))) end
    else AL = 1 end
    render_world(dt)
    update_camera(dt)
    do local x, y, z = G.marble_pos(); update_lights(dt, vec3(x, y, z)) end
    -- test hook: per-frame rendered marble positions (see README "Testing")
    if G.trace and #G.trace < 900 then local p = G.rendered_pos(); local R = G.rend_R or {}
        G.trace[#G.trace + 1] = { dt, p[1], p[3], G.speed or 0, p[2], R[1] or 0, R[2] or 0, R[3] or 0, R[5] or 0, G.phase, AL } end
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end
-- debug autopilot for tests/screenshots only: steer toward the next checkpoint, then the goal
function G.autoplay_fn()
    local M, C = G.M, G.CUR
    local t = C.checks[G.check + 1]
    local tx, tz
    if t then tx, tz = t[1], t[2] else local g = C.goal; tx, tz = (g[1] + g[3]) / 2, (g[2] + g[4]) / 2 end
    local dx, dz = tx - M.x - M.vx * 0.35, tz - M.z - M.vz * 0.35
    local fx, fz, rx, rz = G.cam_axes()
    local my = clamp((dx * fx + dz * fz) * 0.5, -1, 1)
    local mx = clamp((dx * rx + dz * rz) * 0.5, -1, 1)
    return mx, my
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_world()
to_title()
G.update = update; G.SET = SET
hooks { update = update }
pe_log("[MM] ready")
