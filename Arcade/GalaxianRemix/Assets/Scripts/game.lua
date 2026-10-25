-- GALAXIAN REMIX  (PhasmaEngine, Lua)
-- A faithful modern remake of Namco's Galaxian (1979): a swaying convoy of 46 alien insects (2 flagships, 6 red
-- escorts, 8 purple emissaries, 30 blue drones) peels off to dive at the Galaxip. One missile on screen at a time.
-- Logic coords: x across the field, y up the screen (player near y = 1). WP maps to world (camera looks up the field, +Z).
local PI = math.pi
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
math.randomseed(os and os.time and os.time() or 1979)
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local G = { state = "boot", t = 0 }
_G.GX = G

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
local ss = scene.add_empty_node("GalaxianSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "space.hdr")
S("hdr", false); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false); S("dof", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.2)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", false)
S("color_grading", true); S("color_grading_saturation", 1.05); S("color_grading_contrast", 1.04)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "SETTINGS", subtitle = "Galaxian Remix", file = "Save/settings.cfg", music = true,
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
    if not n then pe_log("[GX] missing template " .. name); return nil end
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
G.vk = {}
local function held(k) if G.vk and G.vk[k] then return true end local ok, v = pcall(keyfn, k); return ok and v end
local function edge(k) local d = held(k); local p = prev[k]; prev[k] = d; return d and not p end
local function any(...) for _, k in ipairs({ ... }) do if held(k) then return true end end; return false end

local FR = 1 / 60
local AL = 1
------------------------------------------------------------------ palette {base, emissive, rough, metal}
-- IBL is off, so metals are kept low and colours carry a little emissive to stay readable against space.
local PAL = {
    gx_body = { { .9, .9, .93 }, { .05, .05, .06 }, .3, .3 }, gx_accent = { { .85, .14, .1 }, { .1, .01, 0 }, .35, .2 },
    gx_glass = { { .15, .35, .7 }, { .04, .1, .22 }, .08, .2 }, gx_engine = { { .4, .4, .45 }, { .5, .3, .12 }, .4, .5 },
    pshot = { { 1, .9, .6 }, { 1.6, 1.2, .5 }, .3 },
    drone_body = { { .16, .3, .82 }, { .02, .05, .16 }, .35, .15 }, drone_wing = { { .3, .62, .9 }, { .03, .08, .14 }, .3 }, drone_eye = { { 1, .9, .5 }, { .8, .6, .2 }, .3 },
    purple_body = { { .5, .2, .72 }, { .09, .03, .14 }, .35, .15 }, purple_wing = { { .72, .45, .9 }, { .1, .05, .14 }, .3 }, purple_eye = { { 1, .9, .5 }, { .8, .6, .2 }, .3 },
    red_body = { { .82, .14, .1 }, { .16, .02, .01 }, .35, .15 }, red_wing = { { .95, .55, .2 }, { .14, .06, .01 }, .3 }, red_eye = { { 1, .95, .7 }, { .8, .7, .3 }, .3 },
    flag_body = { { .95, .78, .2 }, { .2, .14, .02 }, .3, .3 }, flag_wing = { { .82, .14, .1 }, { .14, .02, .01 }, .3 }, flag_eye = { { .3, .7, 1 }, { .2, .45, .8 }, .3 },
    bomb = { { 1, .75, .5 }, { 1.4, .8, .35 }, .4 },
    wflag_pole = { { .8, .8, .8 }, { .1, .1, .1 }, .4 }, wflag_cloth = { { .85, .15, .1 }, { .3, .04, .02 }, .5 },
    planet = { { 1, 1, 1 }, { .06, .05, .04 }, .9 }, planet_ring = { { 1, 1, 1 }, { .06, .05, .04 }, .9 },
    star_w = { { 1, 1, 1 }, { 1.3, 1.3, 1.3 }, .5 }, star_b = { { .6, .75, 1 }, { .7, .9, 1.4 }, .5 },
    star_y = { { 1, .9, .6 }, { 1.3, 1.1, .6 }, .5 }, star_r = { { 1, .6, .5 }, { 1.3, .6, .45 }, .5 },
    field_line = { { .3, .3, .35 }, { .05, .05, .07 }, .8 },
}
local function paint_templates()
    for name, v in pairs(PAL) do paint(tnode(name), v[1], v[2], v[3], v[4]) end
    mtex(tnode("planet"), "base_color", "Textures/planet.png"); mtex(tnode("planet_ring"), "base_color", "Textures/ring.png")
    for name in pairs(PAL) do local n = tnode(name); if n then n:set_position(HIDE) end end
end

------------------------------------------------------------------ lights
local LT = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    -- a cool key light from above-left, like a distant star
    lights.set_directional_light(0, vec3(0.35, -0.85, 0.25), vec3(0.95, 0.95, 1.0), 3.2)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    LT.fill = addp(HIDE, vec3(0.7, 0.75, 1.0), 16, 30)
    LT.ship = addp(HIDE, vec3(1.0, 0.85, 0.65), 6, 4)
    LT.flash = {}
    for i = 1, 6 do LT.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1 } end
end
G.flash_next = 1
local function flash(p, col, power, life, rad)
    local f = LT.flash[G.flash_next]; G.flash_next = G.flash_next % #LT.flash + 1
    f.t, f.life, f.p, f.col, f.power, f.rad = 0, life or 0.3, p, vec3(col[1], col[2], col[3]), power or 30, rad or 4
end
local function update_lights(dt)
    set_point(LT.fill, WP(0, 12, 9), vec3(0.7, 0.75, 1.0), 16, 30)
    local P = G.P
    set_point(LT.ship, P.alive and WP(P.x, P.y - 0.6, 0.8) or HIDE, vec3(1.0, 0.85, 0.65), 6, 4)
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
local function sparks(p, n, col)
    col = col or { 1.6, 1.4, 1.0 }
    burst(p, { c0 = vec4(col[1], col[2], col[3], 1), c1 = vec4(1, .5, .2, 0), count = n or 8, smin = .025, smax = .06, lmin = .12, lmax = .3, radius = .05, spread = 9, drag = 2.5 })
end
-- textured particle FX (common/particles.lua): flipbook fireballs, stretched sparks, embers, tumbling debris.
-- Space has no gravity, so debris and embers drift instead of falling.
local FX = load(fs.read("Scripts/Lib/particles.lua"), "@particles.lua")().new({
    scale = PS, light = function(p, col, power, life, rad) flash(p, col, power, life, rad) end })
G.FX = FX
-- alien burst: flash, a small fireball, sparks, embers and wing debris in the alien's colours
local function pop(p, col, big)
    local s = big and 1.0 or 0.55
    FX:flash(p, s * 0.9, { 1, .8, .55 })
    FX:fireball(p, s * 0.8, { 1, .6, .3 })
    FX:sparks(p, big and 34 or 16, s, nil, { 1.8, 1.5, 1.0 }, 0)
    FX:embers(p, big and 18 or 8, s)
    FX:debris(p, big and 18 or 10, s * 0.8, { col[1] * 1.3 + .1, col[2] * 1.3 + .1, col[3] * 1.3 + .1 }, 0)
    burst(p, { c0 = vec4(col[1] * 1.6, col[2] * 1.6, col[3] * 1.6, 1), c1 = vec4(col[1] * .3, col[2] * .3, col[3] * .3, 0), count = big and 24 or 10, smin = .04, smax = .1, lmin = .3, lmax = .7, radius = .2, spread = 9, drag = 1.6 })
    if big then
        -- flagship: a second, delayed ring of fire and a dust cloud
        FX:fireball(p, 1.3, { 1, .5, .25 }); FX:smoke(p, 5, 0.8, .16, 0)
    end
end
-- Galaxip: big fireball, a shower of hull debris and sparks, a lingering dust cloud
local function ship_boom(p)
    FX:explosion(p, { size = 1.3, tint = { 1, .55, .25 }, debris = { .85, .85, .9 }, debris_grav = 0, spark_grav = 0, grey = .16 })
    FX:debris(p, 14, 1.4, { .9, .2, .15 }, 0)
    FX:sparks(p, 40, 1.6, nil, { 1.6, 1.6, 1.8 }, 0)
    burst(p, { c0 = vec4(1.6, 1.6, 1.7, 1), c1 = vec4(.4, .5, .8, 0), count = 30, smin = .03, smax = .08, lmin = .5, lmax = 1.2, radius = .2, spread = 12, drag = 1.2 })
end
-- engine and missile trails: persistent emitters moved every frame
local TR = {}
local function build_trails()
    TR.engine = FX:trail("fire", { vel = vec3(0, 0, -4), c0 = { 1.6, 1.1, .6, .8 }, c1 = { .5, .15, .05, 0 }, smin = .12, smax = .2, lmin = .12, lmax = .22, radius = .04, spread = .4, anim = 2 })
    -- missile: velocity-aligned spark streaks from four emitters spread over the distance the missile moved since the
    -- last frame, so the trail reads as one continuous streak at 30 units/s at any frame rate instead of per-frame dots.
    -- (The old smoke trail is gone: in space it only showed as bright puffs.)
    local mt = { vel = vec3(0, 0, -9), c0 = { .95, .62, .26, .9 }, c1 = { .6, .14, .03, 0 }, smin = .24, smax = .3, lmin = .1, lmax = .18, radius = .01, spread = .15, stretch = true }
    TR.missile = {}; for i = 1, 4 do TR.missile[i] = FX:trail("spark", mt) end
end
G.TR = TR
local function exhaust(p) end
G.pop, G.ship_boom = pop, ship_boom

------------------------------------------------------------------ score state
G.score, G.hiscore = 0, 0
pcall(function() local s = fs.read("Save/galaxian_hiscore.txt"); if s then G.hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, "Save/galaxian_hiscore.txt", tostring(G.hiscore)) end
G.banner = { text = "", t = 0 }
function G.banner_set(t, d) G.banner.text = t; G.banner.t = d or 1.5 end
-- floating score popups (for diving kills), drawn by the HUD
G.POPS = {}
local function popup(x, y, n) G.POPS[#G.POPS + 1] = { x = x, y = y, n = n, t = 0 } end
------------------------------------------------------------------ the convoy (arcade layout)
-- 10 columns x 6 rows: 2 flagships (columns 4 and 7), 6 red escorts, 8 purple emissaries and 30 blue drones (46 in all).
local XMAX = 7.2          -- the Galaxip's travel either side of centre
local PY = 1.2            -- the Galaxip's height on the field
local TOPY = 21.5         -- divers that fall off the bottom reappear here
local COLW, ROW0, ROWH = 1.38, 18.3, 1.2
local AS, SS = 1.2, 1.2      -- model scale for aliens and the Galaxip (hit boxes below already include it)
local ROWS = {
    { k = "flag", cols = { 3, 6 } },
    { k = "red", cols = { 2, 3, 4, 5, 6, 7 } },
    { k = "purple", cols = { 1, 2, 3, 4, 5, 6, 7, 8 } },
    { k = "drone", cols = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 } },
    { k = "drone", cols = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 } },
    { k = "drone", cols = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 } },
}
-- points: in formation / diving (flagship diving points depend on its escorts, see 04_sim)
local PTS_FORM = { drone = 30, purple = 40, red = 50, flag = 60 }
local PTS_DIVE = { drone = 60, purple = 80, red = 100, flag = 150 }
-- hit boxes (half sizes) match the models: wingspan x body length
local HB = { drone = { .54, .41 }, purple = { .6, .42 }, red = { .6, .46 }, flag = { .72, .54 } }
local SHIP_HB = { .6, .48 }
local COLS = { drone = { .16, .3, .82 }, purple = { .5, .2, .72 }, red = { .82, .14, .1 }, flag = { .95, .78, .2 } }
G.XMAX, G.PY, G.HB, G.SHIP_HB = XMAX, PY, HB, SHIP_HB
local function slot_x(col) return (col - 4.5) * COLW end
local function slot_y(row) return ROW0 - (row - 1) * ROWH end
------------------------------------------------------------------ simulation (fixed 60 Hz steps)
local P = { x = 0, y = PY, vx = 0, alive = true, shot = nil }
G.P = P
G.A, G.BOMBS = {}, {}
G.form = { x = 0, vx = 0.8 }
G.wave, G.ships, G.phase, G.pt = 1, 2, "start", 0
local DIVE_STATES = { peel = true, dive = true, escort = true }
local function wave_k() return min(G.wave - 1, 8) end
local function dive_speed() return 6.0 + 0.35 * wave_k() end
local function add_score(n)
    local before = G.score
    G.score = G.score + n
    if before < 7000 and G.score >= 7000 then G.ships = G.ships + 1; sfx("extra"); G.banner_set("Extra Galaxip", 1.6) end
end
local function start_wave()
    G.A = {}
    for r, row in ipairs(ROWS) do
        for _, c in ipairs(row.cols) do
            G.A[#G.A + 1] = { k = row.k, row = r, col = c, x = slot_x(c) + G.form.x, y = slot_y(r), st = "form", t = 0, vx = 0, vy = 0, ang = 180,
                alive = true, grow = -(6 - r) * 0.07 - c * 0.012 }
        end
    end
    G.BOMBS = {}; P.shot = nil
    G.dive_t = 3.0; G.side = 1
end
function G.new_game_sim()
    G.score = 0; G.ships = 2; G.wave = 1; G.form.x = 0; G.form.vx = 0.8
    P.x = 0; P.vx = 0; P.alive = true; P.shot = nil
    start_wave()
    G.phase = "start"; G.pt = 0; G.out = false; G.POPS = {}
end
local function alive_count() local n = 0; for _, a in ipairs(G.A) do if a.alive then n = n + 1 end end; return n end
G.alive_count = alive_count
local function divers() local n = 0; for _, a in ipairs(G.A) do if a.alive and a.st ~= "form" then n = n + 1 end end; return n end
------------------------------------------------------------------ dives
local function launch(a, side)
    a.st = "peel"; a.t = 0; a.x0, a.y0 = a.x, a.y
    a.side = side or ((a.x < G.form.x) and -1 or 1)
    a.bombs = min(4, 2 + floor(G.wave / 3)); a.bomb_t = rr(0.25, 0.7); a.vx = 0
    a.weave = rr(0, 6)
    sfx("dive")
end
local function launch_convoy(f)
    launch(f)
    f.esc = {}
    local reds = {}
    for _, a in ipairs(G.A) do if a.alive and a.st == "form" and a.k == "red" and abs(a.col - f.col) <= 1 then reds[#reds + 1] = a end end
    table.sort(reds, function(p, q) return abs(p.col - f.col) < abs(q.col - f.col) end)
    for i = 1, min(2, #reds) do
        local r = reds[i]
        r.st = "escort"; r.leader = f; r.t = 0
        local s = (r.col < f.col) and -1 or ((r.col > f.col) and 1 or (#f.esc == 0 and -1 or 1))
        if #f.esc == 1 and f.esc[1].ox == s * 0.85 then s = -s end
        r.ox, r.oy = s * 0.85, 0.7
        r.bombs = f.bombs; r.bomb_t = rr(0.4, 0.9)
        f.esc[#f.esc + 1] = r
    end
    f.esc_n = #f.esc
end
G.launch_convoy = launch_convoy
-- the arcade launches divers from the edges of the convoy, alternating sides
local function schedule(dt)
    if not ((G.phase == "play" and P.alive) or G.phase == "attract") then return end
    G.dive_t = G.dive_t - dt
    if G.dive_t > 0 then return end
    local cap = min(7, 2 + G.wave)
    G.dive_t = max(0.7, 2.6 - 0.18 * wave_k()) * rr(0.7, 1.3)
    if divers() >= cap then return end
    -- flagship convoy now and then
    if rand() < 0.22 then
        local fl = {}
        for _, a in ipairs(G.A) do if a.alive and a.st == "form" and a.k == "flag" then fl[#fl + 1] = a end end
        if #fl > 0 then launch_convoy(fl[floor(rand() * #fl) + 1]); return end
    end
    G.side = -G.side
    local best, cand = nil, {}
    for _, a in ipairs(G.A) do
        if a.alive and a.st == "form" and a.k ~= "flag" then
            local e = (a.col - 4.5) * G.side
            if not best or e > best + 0.5 then best = e; cand = { a } elseif abs(e - best) <= 0.5 then cand[#cand + 1] = a end
        end
    end
    if #cand == 0 then
        -- only flagships remain in formation: they dive alone
        for _, a in ipairs(G.A) do if a.alive and a.st == "form" then launch(a); a.esc_n = 0; a.esc = {}; return end end
        return
    end
    local a = cand[floor(rand() * #cand) + 1]
    launch(a, G.side)
    -- from wave 3, drones sometimes peel off in pairs
    if G.wave >= 3 and a.k == "drone" and rand() < 0.3 then
        for _, b in ipairs(cand) do if b ~= a and b.st == "form" then launch(b, G.side); break end end
    end
end
local function drop_bomb(a)
    if a.bombs <= 0 or not P.alive then return end
    a.bomb_t = a.bomb_t - FR
    if a.bomb_t > 0 or a.y > 15 or a.y < PY + 4 or abs(a.x - P.x) > 5 then return end
    a.bombs = a.bombs - 1; a.bomb_t = rr(0.3, 0.75) - 0.02 * wave_k()
    G.BOMBS[#G.BOMBS + 1] = { x = a.x, y = a.y - 0.4, py = a.y - 0.4, vx = a.vx * 0.25, vy = -(10 + 0.4 * wave_k()) }
    sfx("bomb")
end
local function heading(vx, vy) return math.deg(atan2(-vx, vy)) end
local function wrap(a)
    a.y = TOPY; a.x = clamp(a.x, -XMAX, XMAX); a.vx = 0
    if alive_count() <= 4 and P.alive and G.phase == "play" then
        -- the last few aliens keep attacking without going home
        a.st = "dive"; a.vy = -dive_speed(); a.bombs = min(4, 2 + floor(G.wave / 3)); a.bomb_t = rr(0.3, 0.8)
    else a.st = "return" end
end
local function step_alien(a, dt)
    a.t = a.t + dt
    if a.grow < 1 then a.grow = min(1, a.grow + dt * 2.2) end
    local sx, sy = slot_x(a.col) + G.form.x, slot_y(a.row)
    if a.st == "form" then
        a.x, a.y, a.ang = sx, sy, 180
    elseif a.st == "peel" then
        -- loop up and outward off the end of the convoy, then turn down toward the Galaxip
        local u = min(1, a.t / 0.6); local th = PI * u; local R = 0.9
        a.x = a.x0 + a.side * R * (1 - cos(th)); a.y = a.y0 + R * sin(th)
        a.ang = heading(a.side * sin(th), cos(th))
        if u >= 1 then a.st = "dive"; a.vx = a.side * 1.5; a.vy = -dive_speed() end
    elseif a.st == "dive" then
        if a.y > PY + 3 then
            local tx = P.alive and P.x or a.x
            if a.k == "drone" or a.k == "purple" then tx = tx + sin(a.t * 2.6 + a.weave) * 1.4 end
            a.vx = clamp(a.vx + clamp((tx - a.x) * 2.4, -9, 9) * dt, -4.5, 4.5)
        end
        a.x = a.x + a.vx * dt; a.y = a.y + a.vy * dt
        if abs(a.x) > XMAX + 0.6 then a.x = clamp(a.x, -XMAX - 0.6, XMAX + 0.6); a.vx = -a.vx * 0.5 end
        a.ang = heading(a.vx, a.vy)
        drop_bomb(a)
        if a.y < -1.5 then wrap(a) end
    elseif a.st == "escort" then
        local L = a.leader
        if not L or not L.alive then a.st = "dive"; a.vx = L and L.vx or 0; a.vy = -dive_speed(); a.leader = nil
        elseif L.st == "return" or L.st == "form" then a.st = "return"; a.leader = nil
        else
            a.x = L.x + a.ox; a.y = L.y + a.oy
            a.vx, a.vy, a.ang = L.vx or 0, L.vy or 0, L.ang
            drop_bomb(a)
        end
    elseif a.st == "return" then
        local dx, dy = sx - a.x, sy - a.y
        local d = sqrt(dx * dx + dy * dy)
        local sp = 7 * dt
        if d <= sp + 0.02 then a.st = "form"; a.x, a.y, a.ang = sx, sy, 180; a.esc = nil
        else a.x = a.x + dx / d * sp; a.y = a.y + dy / d * sp; a.ang = heading(dx / d, dy / d) end
    end
end
------------------------------------------------------------------ hits
local function kill(a, by_ship)
    a.alive = false
    local pts
    if a.st == "form" then pts = PTS_FORM[a.k]
    elseif a.k == "flag" then
        local total, killed = a.esc_n or 0, 0
        for _, e in ipairs(a.esc or {}) do if not e.alive then killed = killed + 1 end end
        pts = (total == 2 and killed == 2) and 800 or (total == 2 and 300) or (total == 1 and 200) or 150
        popup(a.x, a.y, pts)
    else pts = PTS_DIVE[a.k] end
    add_score(pts)
    G.pop(WP(a.x, a.y, 0.3), COLS[a.k], a.k == "flag")
    sfx(a.k == "flag" and "hit_flag" or "hit")
    if a.k == "flag" or a.st ~= "form" then G.shake = max(G.shake, a.k == "flag" and 0.35 or 0.15) end
end
local function ship_die()
    if not P.alive then return end
    P.alive = false; P.shot = nil
    G.ship_boom(WP(P.x, P.y, 0.3)); sfx("pdie"); G.shake = 0.8
    G.phase = "dead"; G.pt = 0
end
local function overlap(ax, ay, ah, bx, by, bh) return abs(ax - bx) < ah[1] + bh[1] and abs(ay - by) < ah[2] + bh[2] end
------------------------------------------------------------------ one step
function G.step(inp, dt)
    G.pt = G.pt + dt
    -- convoy sway between the walls (bounded by the outermost living columns)
    local lo, hi = 9, 0
    for _, a in ipairs(G.A) do if a.alive then lo = min(lo, a.col); hi = max(hi, a.col) end end
    if lo <= hi then
        local f = G.form
        f.x = f.x + f.vx * dt
        if slot_x(lo) + f.x < -XMAX + 0.2 and f.vx < 0 then f.vx = -f.vx end
        if slot_x(hi) + f.x > XMAX - 0.2 and f.vx > 0 then f.vx = -f.vx end
    end
    -- the Galaxip
    if P.alive then
        local v = clamp(inp.mx or 0, -1, 1) * 7.5
        local nx = clamp(P.x + v * dt + (inp.mdx or 0), -XMAX, XMAX)
        P.vx = damp(P.vx, (nx - P.x) / dt, 12, dt); P.x = nx
        if inp.fire and not P.shot and (G.phase == "play" or G.phase == "clear" or G.phase == "start") then
            P.shot = { x = P.x, y = PY + 0.62 * SS, py = PY + 0.62 * SS }; sfx("shot")
        end
    end
    -- the missile: swept from last to new position, hits the lowest alien whose box it crosses
    local s = P.shot
    if s then
        s.py = s.y; s.y = s.y + 30 * dt
        local hit, hy = nil, 1e9
        for _, a in ipairs(G.A) do
            if a.alive and a.grow >= 1 then
                local hb = HB[a.k]
                if abs(s.x - a.x) < hb[1] + 0.04 and s.y + 0.14 >= a.y - hb[2] and s.py - 0.18 <= a.y + hb[2] and a.y < hy then hit, hy = a, a.y end
            end
        end
        if hit then kill(hit, false); P.shot = nil elseif s.y > TOPY then P.shot = nil end
    end
    schedule(dt)
    for _, a in ipairs(G.A) do if a.alive then step_alien(a, dt) end end
    -- divers colliding with the Galaxip destroy both (you still get the points)
    if P.alive then
        for _, a in ipairs(G.A) do
            if a.alive and a.st ~= "form" and overlap(P.x, P.y, SHIP_HB, a.x, a.y, HB[a.k]) then kill(a, true); ship_die(); break end
        end
    end
    -- bombs (swept against the Galaxip)
    for i = #G.BOMBS, 1, -1 do
        local b = G.BOMBS[i]
        b.py = b.y; b.x = b.x + b.vx * dt; b.y = b.y + b.vy * dt
        if P.alive and abs(b.x - P.x) < SHIP_HB[1] + 0.05 and b.y - 0.16 <= P.y + SHIP_HB[2] and b.py + 0.12 >= P.y - SHIP_HB[2] then
            table.remove(G.BOMBS, i); ship_die()
        elseif b.y < -1 then table.remove(G.BOMBS, i) end
    end
    -- phases
    if G.phase == "start" then
        if G.pt > 2.0 then G.phase = "play"; G.pt = 0 end
    elseif G.phase == "play" then
        if alive_count() == 0 then G.phase = "clear"; G.pt = 0; sfx("wave"); G.banner_set("Convoy Destroyed", 1.8) end
    elseif G.phase == "clear" then
        if G.pt > 2.2 then
            G.wave = G.wave + 1; start_wave(); G.phase = "play"; G.pt = 0
            G.banner_set("Wave " .. G.wave, 1.4)
        end
    elseif G.phase == "dead" then
        -- wait until every attacker has gone home and the bombs have cleared, as in the arcade
        if G.pt > 2.5 and divers() == 0 and #G.BOMBS == 0 then
            if alive_count() == 0 then G.wave = G.wave + 1; start_wave() end
            if G.ships > 0 then
                G.ships = G.ships - 1; P.alive = true; P.x = 0; P.vx = 0
                G.phase = "start"; G.pt = 0.8; G.dive_t = 2.0
            else G.out = true end
        end
    end
    for i = #G.POPS, 1, -1 do local p = G.POPS[i]; p.t = p.t + dt; if p.t > 1.4 then table.remove(G.POPS, i) end end
end
------------------------------------------------------------------ world nodes
local function V(x, y, z) return vec3(x, y, z) end
G.shake = 0
local RIG = {
    drone = { "drone_body", "drone_wing", "drone_eye" }, purple = { "purple_body", "purple_wing", "purple_eye" },
    red = { "red_body", "red_wing", "red_eye" }, flag = { "flag_body", "flag_wing", "flag_eye" },
    ship = { "gx_body", "gx_accent", "gx_glass", "gx_engine" },
}
local ALLM = {}
for _, n in ipairs(RIG.ship) do ALLM[n] = true end
-- alien rigs (pooled per kind): root = position + heading (yaw), child 'att' = bank (roll about the alien's OWN nose).
-- The engine applies an euler Z after Y, i.e. about the world axis, so rolling a yawed node directly banks the
-- wrong way (or pitches) depending on the heading; the child keeps the bank local in every direction.
local ARFREE, AR = {}, {}
local function alien_rig(k)
    local f = ARFREE[k]
    if f and #f > 0 then return table.remove(f) end
    local r = { k = k, root = empty("alien_" .. k, nil, HIDE) }
    r.att = empty("alien_att_" .. k, r.root)
    local m = RIG[k]
    r.body = clone(m[1], V(0, 0, 0), nil, r.att); r.wing = clone(m[2], V(0, 0.002, 0), nil, r.att); r.eye = clone(m[3], V(0, 0, 0), nil, r.att)
    return r
end
local function alien_rig_free(r) r.root:set_position(HIDE); ARFREE[r.k] = ARFREE[r.k] or {}; table.insert(ARFREE[r.k], r) end
for _, n in ipairs({ "pshot", "bomb", "wflag_pole", "wflag_cloth", "star_w", "star_b", "star_y", "star_r" }) do ALLM[n] = true end
local W = { stars = {} }
local STARC = { "star_w", "star_w", "star_b", "star_y", "star_r" }
local function build_world()
    -- a gas giant far below the field, and a slowly scrolling, twinkling starfield (Galaxian's stars scroll down)
    W.planet = clone("planet", WP(-46, 44, -55), V(8, 8, 8))
    W.ring = clone("planet_ring", WP(-46, 44, -55), V(8, 0.25, 8))
    W.ring:set_rotation(V(20, 0, -24))
    for i = 1, 170 do
        W.stars[i] = { x = rr(-24, 24), y = rr(-10, 40), h = rr(-14, -7), c = STARC[(i % #STARC) + 1], ph = rr(0, 6.28), rate = rr(1.5, 4) }
    end
end
function G.reset_world() end
local function pose(list, x, y, h, yaw, roll, sc)
    for _, mname in ipairs(list) do
        local n = P_get(mname); n:set_position(WP(x, y, h or 0)); n:set_rotation(V(0, yaw or 0, roll or 0))
        n:set_scale(sc and V(sc, sc, sc) or V(1, 1, 1))
    end
end
local function render_world(dt)
    for mname in pairs(ALLM) do P_begin(mname) end
    local P = G.P
    W.planet:set_rotation(V(0, G.t * 2 % 360, 12))
    -- stars
    for _, s in ipairs(W.stars) do
        s.y = s.y - dt * 2.4
        if s.y < -10 then s.y = s.y + 50; s.x = rr(-24, 24) end
        if sin(G.t * s.rate + s.ph) > -0.55 then
            local n = P_get(s.c); n:set_position(WP(s.x, s.y, s.h))
            local k = 0.8 + 0.4 * sin(G.t * s.rate * 0.7 + s.ph); n:set_scale(V(k, k, k))
        end
    end
    -- aliens: bank into the turn (turn rate from the heading change; + roll = right wing down = turning right)
    local seen = {}
    local fdt = max(G.dt or dt, 0.001)
    for _, a in ipairs(G.A) do
        if a.alive and a.grow > 0 then
            seen[a] = true
            local r = AR[a]
            if not r then r = alien_rig(a.k); AR[a] = r end
            local g = a.grow; local sc = g * g * (3 - 2 * g) * AS
            local fast = a.st ~= "form"
            local flap = 0.5 + 0.5 * sin(G.t * (fast and 14 or 6) + a.col * 0.7 + a.row)
            local ang = a.ang or 180
            local turn = 0                                  -- deg/s to the alien's right (heading decreases when turning right)
            if a.pang and fast then turn = -(((ang - a.pang) + 180) % 360 - 180) / fdt end
            a.pang = ang
            a.bank = damp(a.bank or 0, fast and clamp(turn * 0.3, -40, 40) or 0, 8, fdt)
            if G.bank_test then a.bank = G.bank_test end   -- test hook (nil in play)
            local h = 0.3 + (fast and 0.25 or 0)
            r.root:set_position(WP(a.x, a.y, h)); r.root:set_rotation(V(0, ang, 0)); r.root:set_scale(V(sc, sc, sc))
            r.att:set_rotation(V(0, 0, a.bank))
            r.wing:set_scale(V(1 - 0.3 * flap, 1 + 0.4 * flap, 1))
        end
    end
    for a, r in pairs(AR) do if not seen[a] then alien_rig_free(r); AR[a] = nil end end
    -- the Galaxip, its loaded missile and engine glow
    if P.alive then
        local roll = clamp(P.vx * 3.5, -25, 25)   -- + = right wing down when moving right (roll into the move)
        pose(RIG.ship, P.x, P.y, 0.3, 0, roll, SS)
        if not P.shot then local n = P_get("pshot"); n:set_position(WP(P.x, P.y + 0.62 * SS, 0.32)); n:set_rotation(V(0, 0, 0)); n:set_scale(V(SS, SS, SS)) end
    end
    -- engine glow trail behind the Galaxip, fire trail behind the missile in flight
    FX:trail_at(TR.engine, P.alive and WP(P.x, P.y - 0.52 * SS, 0.32) or nil, P.alive and 70 or 0)
    local sh = P.shot
    local my = sh and sh.y - 0.25
    local prev = (sh and TR.my_prev and TR.my_prev < my and my - TR.my_prev < 6) and TR.my_prev or my
    -- streak length follows the per-frame spacing so low frame rates don't break the trail into dots
    local ss = sh and clamp((my - prev) / 3 * 1.3, 0.22, 0.42) or 0.26
    for i, id in ipairs(TR.missile) do
        FX:trail_at(id, sh and WP(sh.x, my + (prev - (my or 0)) * (i - 1) / 3, 0.32) or nil, sh and 160 or 0)
        if sh then pcall(particles.set_emitter, id, { size_min = ss, size_max = ss * 1.2 }) end
    end
    TR.my_prev = my
    if P.shot then local n = P_get("pshot"); n:set_position(WP(P.shot.x, P.shot.y, 0.32)); n:set_rotation(V(0, 0, 0)); n:set_scale(V(SS, SS, SS)) end
    for _, b in ipairs(G.BOMBS) do local n = P_get("bomb"); n:set_position(WP(b.x, b.y, 0.35)); n:set_scale(V(1.2, 1.2, 1.2)); n:set_rotation(V(0, 180 + math.deg(math.atan(b.vx / -b.vy)), 0)) end
    -- reserve ships (bottom left) and wave flags (bottom right), as on the arcade screen
    for i = 1, (G.state == "title") and 0 or min(G.ships, 6) do pose({ "gx_body", "gx_accent", "gx_glass" }, -XMAX - 1.6 - (i - 1) * 0.85, 0.6, 0.2, 0, 0, 0.7) end
    local nf = (G.state == "title") and 0 or min(G.wave, 10)
    for i = 1, nf do
        local x = XMAX + 1.5 + (i - 1) * 0.5
        pose({ "wflag_pole" }, x, 0.6, 0.2, 0, 0)
        local c = P_get("wflag_cloth"); c:set_position(WP(x, 0.6, 0.2)); c:set_rotation(V(0, 0, 4 * sin(G.t * 3 + i))); c:set_scale(V(1, 1, 1))
    end
    for mname in pairs(ALLM) do P_end(mname) end
end
G.exhaust = exhaust

------------------------------------------------------------------ camera: high view down the field, slightly tilted
local function update_camera(dt)
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.3 * SET:shake_scale()
    local pos, look = WP(a * sin(G.t * 53), -5.0 + a * cos(G.t * 61), 25.5), WP(0, 9.4, 0)
    if G.cam_test then pos, look = G.cam_test[1], G.cam_test[2] end     -- screenshot/test override (unset in play)
    cam:set_position(pos); cam:look_at(look)
    G.cam.pos, G.cam.look = pos, look
end

------------------------------------------------------------------ collider debug overlay (F3)
G.DBG = { on = false, pool = {}, used = 0, w = 0.04 }
local DC = { me = { .2, 1, .3 }, enemy = { 1, .25, .2 }, form = { 1, .7, .2 }, edge = { .4, .7, 1 }, shot = { 1, .95, .4 } }
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
local function dbox(x, y, hx, hy, col, h)
    h = h or 0.6
    local a, b, c, d = WP(x - hx, y - hy, h), WP(x + hx, y - hy, h), WP(x + hx, y + hy, h), WP(x - hx, y + hy, h)
    G.dbg_bar(a, b, col); G.dbg_bar(b, c, col); G.dbg_bar(c, d, col); G.dbg_bar(d, a, col)
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and G.state ~= "title" then
        local P = G.P
        G.dbg_bar(WP(-XMAX - SHIP_HB[1], -0.2, 0.6), WP(-XMAX - SHIP_HB[1], 20, 0.6), DC.edge)
        G.dbg_bar(WP(XMAX + SHIP_HB[1], -0.2, 0.6), WP(XMAX + SHIP_HB[1], 20, 0.6), DC.edge)
        if P.alive then dbox(P.x, P.y, SHIP_HB[1], SHIP_HB[2], DC.me) end
        for _, a in ipairs(G.A) do if a.alive then local hb = HB[a.k]; dbox(a.x, a.y, hb[1], hb[2], a.st == "form" and DC.form or DC.enemy, 0.62) end end
        if P.shot then G.dbg_bar(WP(P.shot.x, P.shot.py - 0.18, 0.6), WP(P.shot.x, P.shot.y + 0.14, 0.6), DC.shot) end
        for _, b in ipairs(G.BOMBS) do dbox(b.x, b.y - 0.02, 0.05, 0.14, DC.enemy, 0.6) end
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
    panel("lp", 20 * US, 20 * US, LW, 170 * US, play, 0.5)
    text("l1", "1UP", 40 * US, 30 * US, LW - 40 * US, 30 * US, 0.95, RED, "left", play)
    text("l2", pad6(G.score), 40 * US, 58 * US, LW - 40 * US, 52 * US, 1.8, WHITE, "left", play)
    text("l3", "High Score  " .. pad6(max(G.hiscore, G.score)), 40 * US, 120 * US, LW - 40 * US, 34 * US, 0.95, CYAN, "left", play)
    panel("rp", SW - LW - 20 * US, 20 * US, LW, 130 * US, play, 0.5)
    text("r1", "Wave " .. tostring(G.wave), SW - LW, 30 * US, LW - 40 * US, 40 * US, 1.2, GOLD, "right", play)
    text("r2", "Ships  " .. tostring(G.ships), SW - LW, 76 * US, LW - 40 * US, 40 * US, 1.1, WHITE, "right", play)
    G.banner.t = (G.banner.t or 0) - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    local btxt = G.banner.text or ""
    local bon = G.banner.t > 0
    if G.phase == "start" and G.pt < 2.0 then btxt, ba, bon = "Player One", 1, true end
    text("ban", btxt, 0, SH * 0.42, SW, 80 * US, 2.2, { 1, .88, .45, ba }, "center", play and bon)
    G.jev_err_t = (G.jev_err_t or 0) - dt
    local show_err = play and G.jev_err ~= nil and G.jev_err_t > 0
    text(
        "jev_err",
        G.jev_err or "",
        SW * 0.08,
        SH * 0.5,
        SW * 0.84,
        48 * US,
        0.85,
        { 1, .4, .32, 1 },
        "center",
        show_err)
    -- diving-flagship score popups
    for i = 1, 4 do
        local p = G.POPS[i]
        local vis = play and p ~= nil
        if vis then
            local sx, sy = project(WP(p.x, p.y + p.t * 0.6, 0.6))
            text("pop" .. i, tostring(p.n), sx - 80 * US, sy - 20 * US, 160 * US, 40 * US, 1.3, { 1, .9, .5, 1 }, "center", true)
        else text("pop" .. i, "", 0, 0, 10, 10, 1, WHITE, "center", false) end
    end
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 480 * US, SH * 0.05, 960 * US, SH * 0.8, title, 0.66)
    text("t_title", "Galaxian Remix", 0, SH * 0.07, SW, 130 * US, 4.2, { 1, .8, .35, 1 }, "center", title)
    text("t_sub", "We Are The Galaxians  ·  Mission: Destroy Aliens", 0, SH * 0.07 + 116 * US, SW, 40 * US, 1.05, DIM, "center", title)
    local TB = { "Score Advance Table  (in convoy / diving)",
        "Drone 30 / 60   ·   Emissary 40 / 80   ·   Escort 50 / 100",
        "Flagship 60 in convoy  ·  diving: 150 alone, 200 with one escort, 300 with two, 800 if you shoot both escorts first" }
    for i, l in ipairs(TB) do text("t_s" .. i, l, SW / 2 - 470 * US, SH * 0.5 + (i - 1) * 34 * US, 940 * US, 34 * US, i == 1 and 0.95 or 0.86, i == 1 and GOLD or DIM, "center", title) end
    local CL = { "A / D / Left / Right or mouse: move  ·  Space / J / Left Click: fire (one missile on screen at a time)",
        "P / Esc: pause  ·  O: settings  ·  M: mute  ·  F3: colliders" }
    for i, l in ipairs(CL) do text("t_c" .. i, l, SW / 2 - 470 * US, SH * 0.5 + 118 * US + (i - 1) * 34 * US, 940 * US, 34 * US, 0.86, DIM, "center", title) end
    text("t_hi", "High Score " .. tostring(G.hiscore), 0, SH * 0.5 + 200 * US, SW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, GOLD, "center", pause)
    local over = st == "over" and not G.set_open
    panel("o_bg", SW / 2 - 400 * US, SH * 0.22, 800 * US, SH * 0.56, over, 0.78)
    text("o_t", "Game Over", 0, SH * 0.24, SW, 90 * US, 3.0, RED, "center", over)
    text("o_m", "Wave " .. tostring(G.wave), 0, SH * 0.24 + 92 * US, SW, 40 * US, 1.2, DIM, "center", over)
    text("o_s", "Score " .. tostring(G.score), 0, SH * 0.24 + 140 * US, SW, 44 * US, 1.4, WHITE, "center", over)
    local c = {}
    local yb = SH * 0.25
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
local RAW_HELD = { "Left", "Right", "A", "D", "Space", "J" }
local raw_prev = {}
local raw_ready = false

local function clear_move()
    G.vk.Left = nil
    G.vk.A = nil
    G.vk.Right = nil
    G.vk.D = nil
end

local function clear_hold()
    clear_move()
    G.vk.Space = nil
    G.vk.J = nil
end

local function hold_dir(dir)
    clear_move()
    if dir < 0 then
        G.vk.Left = true
        G.vk.A = true
    elseif dir > 0 then
        G.vk.Right = true
        G.vk.D = true
    end
end

local function pulse_fire()
    G.vk.Space = true
end

local driving = false

local function aim_dx()
    local px = G.P.x
    local ax = px
    local best = 1e18
    for _, a in ipairs(G.A) do
        if a.alive then
            local y = a.y
            if DIVE_STATES[a.st] then
                y = y - 100
            end
            if y < best then
                best = y
                ax = a.x
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

local function apply_action(id)
    if id == "left" or id == "left_fire" then
        hold_dir(-1)
    elseif id == "right" or id == "right_fire" then
        hold_dir(1)
    elseif id == "stop" then
        hold_dir(0)
    end
end

local function prime_raw()
    raw_ready = true
    if not input.is_key_down_raw then
        return
    end

    for i = 1, #RAW_HELD do
        local key = RAW_HELD[i]
        local ok, down = pcall(input.is_key_down_raw, key)
        raw_prev[key] = ok and down and true or false
    end
end

local function human_edge()
    if not input.is_key_down_raw then
        return false
    end

    local hit = false
    for i = 1, #RAW_HELD do
        local key = RAW_HELD[i]
        local ok, down = pcall(input.is_key_down_raw, key)
        local pressed = ok and down and true or false
        if raw_ready and pressed and not raw_prev[key] then
            hit = true
        end
        raw_prev[key] = pressed
    end
    raw_ready = true
    return hit
end

local function nearest_diver()
    local px = G.P.x
    local py = G.P.y
    local best = 1e18
    local bx = 0
    local by = 0
    local found = false
    for _, a in ipairs(G.A) do
        if a.alive and DIVE_STATES[a.st] then
            local dx = a.x - px
            local dy = a.y - py
            local d2 = dx * dx + dy * dy
            if d2 < best then
                best = d2
                bx = a.x
                by = a.y
                found = true
            end
        end
    end
    return bx, by, found
end

local function observe()
    local dx, dy, diving = nearest_diver()
    local lives = G.ships
    if G.P.alive then
        lives = lives + 1
    end
    return {
        player_x = G.P.x,
        diver_x = dx,
        diver_y = dy,
        diving = diving,
        lives = lives,
        score = G.score,
    }
end

local function reset_match(seed)
    if seed ~= nil then
        math.randomseed(seed)
    end
    clear_hold()
    G.jev_err = nil
    G.jev_err_t = 0
    SET:close()
    G.set_open = false
    G.reset_world()
    G.new_game_sim()
    G.state = "play"
    music("swarm")
    sfx("start")
    prime_raw()
end

local function to_title()
    jev:begin_human()
    G.jev_err = nil
    G.jev_err_t = 0
    G.state = "title"
    G.new_game_sim(); G.reset_world()
    G.P.alive = false; G.phase = "attract"; G.dive_t = 2
    music("title")
end
G.to_title = to_title

local function new_game()
    jev:begin_human()
    reset_match(nil)
end
G.new_game = new_game

local function game_over()
    G.state = "over"
    G.over_t = 0
    music(nil)
    sfx("gameover")
    if jev:assisted() then
        return
    end
    if G.score > G.hiscore then
        G.hiscore = G.score
        save_hi()
    end
end

local acc = 0
local mprev = 0
local q = { fire = false }
local lmouse_prev = true
local function update(dt)
    flush_mats()
    if G.on_frame then G.on_frame(dt) end
    jev:tick(dt)
    dt = min(dt, 0.1)
    G.t = G.t + dt; G.dt = dt
    local k = { ret = edge("Return"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), qk = edge("Q"), f3 = edge("F3"),
        space = edge("Space"), j = edge("J") }
    G.vk.Space = nil
    G.vk.J = nil
    local ld = false
    pcall(function() ld = input.is_left_mouse_down and input.is_left_mouse_down() and true or false end)
    local lclick = ld and not lmouse_prev; lmouse_prev = ld
    local mdx = 0
    pcall(function() local d = input.get_mouse_delta(); if d then mdx = d.x or d[1] or 0 end end)
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end; lclick = false end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        if c.jev then
            sfx("click")
            local ok = jev:start()
            if not ok then
                local err = jev:error() or "Jev failed to start"
                jev:begin_human()
                G.jev_err = tostring(err)
                G.jev_err_t = 8
                pe_log("[GX] " .. G.jev_err)
            end
        elseif k.ret or k.space or c.start then sfx("click"); new_game()
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click")
        elseif k.space or k.j or lclick then q.fire = true end
        if driving then q.fire = true end
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
    if (st == "play" or st == "title") and not G.set_open then
        local mx = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0)
        if st == "play" and mx ~= 0 and mx ~= mprev and G.P.alive then sfx("move") end
        mprev = mx
        local mouse = st == "play" and clamp(mdx * 0.012, -1.5, 1.5) or 0
        if st == "play" and G.autoplay then mx, mouse, q.fire = G.autoplay_fn() end
        if st == "title" then mx = 0; q.fire = false end
        local inp = { mx = mx }
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 4 do
            inp.fire = q.fire; q.fire = false
            inp.mdx = n == 0 and mouse or 0
            G.step(inp, FR)
            acc = acc - FR; n = n + 1
        end
        if acc > FR * 4 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if G.out and G.state == "play" then G.out = false; game_over() end
    else AL = 1 end
    render_world(dt)
    update_camera(dt)
    update_lights(dt)
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end
-- debug autopilot for tests/screenshots only: dodge bombs, line up under the lowest attacker, fire when lined up
function G.autoplay_fn()
    local P = G.P
    local tx, best = P.x, -1e9
    for _, a in ipairs(G.A) do
        if a.alive and a.grow >= 1 then
            local sc = (a.st ~= "form" and a.y > 3) and (40 - a.y) or (10 - a.y - abs(a.x - P.x) * 0.5)
            if sc > best then best = sc; tx = a.x + (a.vx or 0) * 0.3 end
        end
    end
    for _, b in ipairs(G.BOMBS) do
        if b.y > P.y and b.y < P.y + 6 and abs(b.x - P.x) < 1.0 then tx = P.x + ((b.x > P.x) and -2 or 2) end
    end
    G.ap_t = (G.ap_t or 0) + 1
    local fire = false
    if not P.shot then
        for _, a in ipairs(G.A) do if a.alive and abs(a.x - P.x) < 0.35 and a.y > P.y + 2 then fire = true end end
    end
    return clamp((tx - P.x) * 2, -1, 1), 0, fire
end

------------------------------------------------------------------ boot
build_lights()
build_trails()
paint_templates()
build_world()
local JevAuto = assert(load(assert(fs.read("Scripts/jev_auto.lua")), "@Scripts/jev_auto.lua", "t", _ENV))()
jev = JevAuto.attach({
    port = 9141,
    id = "galaxian_remix",
    description = "Galaxian Remix. The offered action is the steer, and the guns fire while Jev is playing. "
        .. "Prefer the higher action score.",
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
    observe = observe,
    actions = jev_actions,
    apply = apply_action,
    reset = function(seed)
        driving = true
        reset_match(seed)
    end,
    on_human = function()
        driving = false
        clear_hold()
    end,
})
to_title()
G.update = update; G.SET = SET
hooks { update = update }
pe_log("[GX] ready")
