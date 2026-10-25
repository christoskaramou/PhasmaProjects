-- PANG REMIX  (PhasmaEngine, Lua)
-- A faithful modern remake of Mitchell's Pang / Buster Bros. (1989): fire the harpoon wire straight up, split the
-- bouncing balloons (4 sizes, fixed bounce heights) until they vanish, across 50 stages in 17 world locations in the
-- original order. Breakable glass blocks, steel blocks, ladders, power-ups (double wire, power wire, vulcan, clock,
-- hourglass, dynamite, shield), fruit, crabs and birds, a stage timer.
-- Simulation runs at a fixed 60 Hz (capped catch-up). World units: field x -24..24, floor y = 0, ceiling y = 26.
local PI = math.pi
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
math.randomseed(floor((engine.get_metrics and (engine.get_metrics() or {}).frame or 0) + 1989))
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local G = { state = "boot", t = 0 }
_G.PG = G
local X0, X1, CEIL = -24, 24, 26

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
local ss = scene.add_empty_node("PangSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "day.hdr")
S("hdr", false); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false); S("dof", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.2)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", true); S("IBL_intensity", 0.55)
S("color_grading", true); S("color_grading_saturation", 1.05); S("color_grading_contrast", 1.04)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "SETTINGS", subtitle = "Pang Remix", file = "Save/settings.cfg", music = true,
    click = function() sfx("click") end, defaults = { master = 0.5, jev = false },
    extra = { { id = "jev", label = "JEV", kind = "toggle" } },
    theme = { accent = { 0.35, 0.75, 1, 1 }, accent2 = { 1, 0.55, 0.3, 1 }, text = { 0.86, 0.84, 0.8, 1 }, selected_text = { 1, 0.97, 0.9, 1 } } })
SET:apply()
G.set_open = false

------------------------------------------------------------------ camera
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1600, surf.height or 900
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local VFOV = math.rad(36)
local CAMZ = 16.9 / math.tan(VFOV / 2)
local CAMY = 11.4
local FOVX = 2 * math.atan(math.tan(VFOV / 2) * SW / SH)
pcall(function() cam:set_fov(math.deg(FOVX)) end)
local function to_screen(x, y)
    local hh = CAMZ * math.tan(VFOV / 2)
    return SW / 2 + x / hh * SH / 2, SH / 2 - (y - CAMY) / hh * SH / 2
end

------------------------------------------------------------------ templates -> clones
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[PG] missing template " .. name); return nil end
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
local BALLC = { red = { .92, .1, .1 }, blue = { .12, .32, .95 }, green = { .1, .75, .2 }, yellow = { 1, .78, .08 }, purple = { .62, .2, .9 } }
G.BALLC = BALLC
local function paint_templates()
    local P = {
        pl_skin = { { 1, .74, .58 }, { .02, .01, .01 }, .55 }, pl_eye = { { .04, .04, .08 }, { 0, 0, 0 }, .15 }, pl_eyew = { { .95, .95, .93 }, { .03, .03, .03 }, .3 },
        pl_mouth = { { .4, .12, .1 }, { 0, 0, 0 }, .5 }, pl_hair = { { .35, .2, .1 }, { 0, 0, 0 }, .7 },
        pl_helmet = { { .93, .87, .7 }, { .02, .02, .015 }, .55 }, pl_hband = { { .45, .28, .12 }, { 0, 0, 0 }, .6 },
        pl_shirt = { { .72, .6, .37 }, { .01, .01, .005 }, .75 }, pl_trim = { { .56, .44, .25 }, { 0, 0, 0 }, .75 },
        pl_button = { { .3, .2, .1 }, { 0, 0, 0 }, .4 }, pl_buckle = { { .85, .66, .28 }, { .02, .015, 0 }, .3, .9 },
        pl_belt = { { .3, .18, .08 }, { 0, 0, 0 }, .5 }, pl_shorts = { { .56, .43, .24 }, { 0, 0, 0 }, .75 }, pl_shortleg = { { .56, .43, .24 }, { 0, 0, 0 }, .75 },
        pl_pack = { { .36, .4, .22 }, { 0, 0, 0 }, .75 }, pl_packflap = { { .29, .33, .17 }, { 0, 0, 0 }, .75 }, pl_strap = { { .32, .21, .1 }, { 0, 0, 0 }, .6 },
        pl_sleeve = { { .72, .6, .37 }, { .01, .01, .005 }, .75 }, pl_hand = { { 1, .74, .58 }, { .02, .01, .01 }, .55 },
        pl_leg = { { 1, .74, .58 }, { .02, .01, .01 }, .55 }, pl_sock = { { .93, .92, .88 }, { .02, .02, .02 }, .8 },
        pl_boot = { { .36, .21, .1 }, { 0, 0, 0 }, .45 }, pl_sole = { { .12, .08, .05 }, { 0, 0, 0 }, .7 }, pl_lace = { { .82, .74, .58 }, { 0, 0, 0 }, .7 },
        pl_gun = { { .45, .48, .55 }, { 0, 0, 0 }, .3, .85 }, pl_gunwood = { { .42, .25, .12 }, { 0, 0, 0 }, .45, 0 },
        rung = { { .62, .4, .2 }, { .01, .005, 0 }, .7, 0 },
        ball_shine = { { 1, 1, 1 }, { 1.6, 1.6, 1.6 }, .1 }, shadow = { { .03, .03, .035 }, { 0, 0, 0 }, 1 },
        wire = { { .85, .85, .9 }, { .35, .35, .4 }, .25, .8 }, wire_tip = { { .9, .9, .95 }, { .4, .4, .45 }, .2, .9 },
        hook = { { 1, .75, .3 }, { .5, .3, .05 }, .25, .8 }, bullet = { { 1, .85, .4 }, { 1.4, 1.0, .3 }, .3, .3 },
        blk_steel = { { .62, .65, .7 }, { .03, .03, .035 }, .38, .45 },
        blk_glass_red = { { .9, .25, .3 }, { .25, .04, .05 }, .1, .1 }, blk_glass_blue = { { .3, .5, 1 }, { .05, .1, .28 }, .1, .1 },
        blk_glass_yellow = { { 1, .8, .25 }, { .25, .18, .03 }, .1, .1 }, blk_glass_green = { { .3, .9, .45 }, { .05, .22, .08 }, .1, .1 },
        frame = { { .62, .56, .48 }, { .01, .01, .01 }, .8, .05 }, floor = { { .5, .45, .4 }, { .01, .01, .01 }, .85, 0 },
        ladder = { { .62, .4, .2 }, { .01, .005, 0 }, .7, 0 }, bg_plane = { { 0, 0, 0 }, { .92, .92, .92 }, 1, 0 },
        it_double = { { .9, .9, .95 }, { .3, .3, .35 }, .3, .8 }, it_power = { { 1, .75, .3 }, { .35, .22, .05 }, .3, .8 },
        it_vulcan = { { .35, .38, .45 }, { .02, .02, .03 }, .3, .9 }, it_clock = { { 1, .82, .2 }, { .2, .15, .02 }, .3, .7 },
        it_hands = { { .1, .1, .1 }, { 0, 0, 0 }, .4 }, it_hourglass = { { .95, .85, .55 }, { .25, .2, .08 }, .2, .1 },
        it_hg_frame = { { .55, .35, .15 }, { 0, 0, 0 }, .5 }, it_dynamite = { { .9, .15, .12 }, { .1, .01, .01 }, .5 },
        it_fuse = { { .95, .9, .8 }, { .6, .4, .1 }, .5 }, it_shield = { { .4, .8, 1 }, { .25, .5, .7 }, .2, .4 },
        it_life = { { .93, .88, .74 }, { .1, .09, .06 }, .5 },
        fr_cherry = { { .85, .05, .1 }, { .1, 0, .01 }, .2 }, fr_stem = { { .3, .55, .15 }, { 0, .02, 0 }, .6 },
        fr_apple = { { .9, .2, .1 }, { .05, .01, 0 }, .3 }, fr_grape = { { .45, .15, .6 }, { .04, .01, .06 }, .25 },
        shield_ring = { { .5, .85, 1 }, { .5, 1.1, 1.6 }, .2, .3 }, pop_ring = { { 1, 1, 1 }, { 1.4, 1.4, 1.4 }, .3 },
        cr_body = { { .9, .3, .15 }, { .03, .01, 0 }, .5 }, cr_claw = { { .95, .35, .18 }, { .03, .01, 0 }, .5 },
        cr_legs = { { .85, .3, .15 }, { .02, .01, 0 }, .5 }, cr_eye = { { .05, .05, .05 }, { 0, 0, 0 }, .2 },
        bd_body = { { .25, .45, .85 }, { .01, .02, .04 }, .6 }, bd_beak = { { 1, .7, .1 }, { .1, .06, 0 }, .5 }, bd_wing = { { .2, .38, .78 }, { .01, .02, .04 }, .6 },
    }
    for c, v in pairs(BALLC) do P["ball_" .. c] = { v, { v[1] * .08, v[2] * .08, v[3] * .08 }, .12, 0 } end
    for name, v in pairs(P) do paint(tnode(name), v[1], v[2], v[3], v[4]) end
    mtex(tnode("frame"), "base_color", "Textures/stone.png"); mtex(tnode("floor"), "base_color", "Textures/stone.png")
    for name in pairs(P) do local n = tnode(name); if n then n:set_position(HIDE) end end
end

------------------------------------------------------------------ lights
local LT = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(-0.3, -0.6, -0.75), vec3(1.0, 0.97, 0.92), 1.4)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    LT.key = addp(vec3(-10, 22, 30), vec3(1.0, 0.96, 0.9), 70, 90)
    LT.fill = addp(vec3(14, 4, 26), vec3(0.85, 0.9, 1.0), 40, 80)
    LT.flash = {}
    for i = 1, 6 do LT.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1 } end
end
G.flash_next = 1
local function flash(x, y, col, power, life, rad)
    local f = LT.flash[G.flash_next]; G.flash_next = G.flash_next % #LT.flash + 1
    f.t, f.life, f.x, f.y, f.col, f.power, f.rad = 0, life or 0.3, x, y, vec3(col[1], col[2], col[3]), power or 40, rad or 7
end
local function update_flashes(dt)
    for _, f in ipairs(LT.flash) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = 1 - clamp(f.t / f.life, 0, 1)
            set_point(f.idx, vec3(f.x, f.y, 2.5), f.col, f.power * k * k, f.rad)
            if f.t >= f.life then set_point(f.idx, HIDE, f.col, 0, 1) end
        end
    end
end

------------------------------------------------------------------ particles
local function PS() return SET:particle_scale() end
local function burst(x, y, o)
    pcall(particles.emit_burst, {
        position = vec3(x, y, o.z or 0.6), velocity = o.vel or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = max(1, floor((o.count or 30) * PS())),
        size_min = o.smin or 0.05, size_max = o.smax or 0.14, life_min = o.lmin or 0.25, life_max = o.lmax or 0.7,
        spawn_radius = o.radius or 0.3, noise_strength = o.spread or 10, drag = o.drag or 2.0,
        gravity = o.grav or vec3(0, 0, 0), cleanup_delay = 3.0,
    })
end
local function sparks(x, y, col, n, spread, radius)
    burst(x, y, { c0 = vec4(col[1] * 1.6 + .4, col[2] * 1.6 + .4, col[3] * 1.6 + .4, 1), c1 = vec4(col[1], col[2], col[3], 0), count = n or 24,
        smin = .06, smax = .16, lmin = .25, lmax = .6, radius = radius or .3, spread = spread or 18, drag = 2.2, grav = vec3(0, -10, 0) })
end
local function dust(x, y, n)
    burst(x, y, { c0 = vec4(.8, .75, .68, .6), c1 = vec4(.6, .55, .5, 0), count = n or 10, smin = .1, smax = .25, lmin = .3, lmax = .7,
        radius = .3, spread = 4, drag = 3, grav = vec3(0, 0.8, 0), z = 0.8 })
end

------------------------------------------------------------------ score state
G.score, G.lives, G.stage, G.hiscore = 0, 3, 1, 0
pcall(function() local s = fs.read("Save/pang_hiscore.txt"); if s then G.hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, "Save/pang_hiscore.txt", tostring(G.hiscore)) end
G.POP = {}
for i = 1, 10 do G.POP[i] = { t = 9, col = { 1, 1, 1 }, x = 0, y = 0 } end
G.pop_next = 1
local function popup(x, y, txt, col)
    local p = G.POP[G.pop_next]; G.pop_next = G.pop_next % #G.POP + 1
    p.t, p.x, p.y, p.txt, p.col = 0, x, y, txt, col or { 1, 1, 1 }
end
G.extra_at = 20000
local function add_score(n, x, y)
    G.score = G.score + n
    if x then popup(x, y, tostring(n), { 1, .95, .7 }) end
    if G.score >= G.extra_at then G.lives = G.lives + 1; G.extra_at = G.extra_at + (G.extra_at < 50000 and 30000 or 50000); sfx("life") end
end
------------------------------------------------------------------ world locations (original order: 17 locations, 50 stages)
local LOCS = {
    { "fuji", "Mt. Fuji", "Japan" }, { "guilin", "Mt. Keirin", "China" }, { "emerald", "Emerald Temple", "Thailand" },
    { "angkor", "Angkor Wat", "Cambodia" }, { "ayers", "Ayers Rock", "Australia" }, { "taj", "Taj Mahal", "India" },
    { "leningrad", "Leningrad", "U.S.S.R." }, { "paris", "Paris", "France" }, { "london", "London", "England" },
    { "barcelona", "Barcelona", "Spain" }, { "athens", "Athens", "Greece" }, { "egypt", "Egypt", "Egypt" },
    { "kenya", "Kenya", "Africa" }, { "newyork", "New York", "U.S.A." }, { "maya", "Maya", "Mexico" },
    { "antarctica", "Antarctica", "" }, { "easter", "Easter Island", "Chile" },
}
G.LOCS = LOCS
local NSTAGES = 50
local function loc_of(n) return min(17, floor((n - 1) / 3) + 1) end
G.loc_of = loc_of

------------------------------------------------------------------ layouts: blocks {x0, y0, w, h, kind}  kind: s = steel, r/b/y/g = breakable glass
-- ladders {x, y0, y1}; y1 is ALWAYS the TOP of the block the ladder leads onto (y0 + h), so the player can step off.
-- A wall that stands on the floor always gets a ladder on both sides up to a cap, so no wall can split the floor.
-- tools/audit_stages.py checks every stage (reachability, walls, trapped balloons).
local LAYOUTS = {
    { b = {}, l = {} },                                                                                                    -- 1 open field
    { b = { { -19, 9, 8, 1, "s" }, { 11, 9, 8, 1, "s" } }, l = {} },                                                       -- 2 two shelves
    { b = { { -10, 13, 4, 1, "r" }, { -6, 13, 4, 1, "y" }, { -2, 13, 4, 1, "r" }, { 2, 13, 4, 1, "y" }, { 6, 13, 4, 1, "r" } }, l = {} }, -- 3 glass row
    { b = { { -20, 8, 9, 1, "s" }, { 11, 8, 9, 1, "s" } }, l = { { -12.5, 0, 9 }, { 12.5, 0, 9 } } },                   -- 4 platforms + ladders
    { b = { { -24, 17, 22, 1, "b" }, { 2, 17, 22, 1, "b" } }, l = {} },                                                   -- 5 glass ceiling with a gap
    { b = { { -20, 4, 4, 1, "g" }, { -16, 7, 4, 1, "g" }, { -12, 10, 4, 1, "g" }, { 8, 10, 4, 1, "g" }, { 12, 7, 4, 1, "g" }, { 16, 4, 4, 1, "g" } }, l = {} }, -- 6 stairs
    { b = { { -8, 10, 16, 1, "s" } }, l = { { -6, 0, 11 }, { 6, 0, 11 } } },                                              -- 7 bridge
    { b = { { -17, 6, 2, 2, "r" }, { -7, 12, 2, 2, "y" }, { 5, 6, 2, 2, "r" }, { 15, 12, 2, 2, "y" }, { -1, 17, 2, 2, "b" } }, l = {} }, -- 8 boxes
    { b = { { -9, 0, 2, 7, "b" }, { 7, 0, 2, 7, "b" }, { -10.5, 7, 5, 1, "s" }, { 5.5, 7, 5, 1, "s" } },
      l = { { -9.9, 0, 8 }, { -6.1, 0, 8 }, { 6.1, 0, 8 }, { 9.9, 0, 8 } } },                                          -- 9 glass walls, capped, ladders both sides
    { b = { { -14, 15, 28, 1, "s" } }, l = {} },                                                                           -- 10 high bar
    { b = { { -20, 9, 3, 1, "y" }, { -11, 9, 3, 1, "y" }, { -2, 9, 3, 1, "y" }, { 7, 9, 3, 1, "y" }, { 16, 9, 3, 1, "y" },
            { -15, 15, 3, 1, "r" }, { -6, 15, 3, 1, "r" }, { 3, 15, 3, 1, "r" }, { 12, 15, 3, 1, "r" } }, l = {} },     -- 11 checker
    { b = { { -24, 12, 6, 1, "s" }, { 18, 12, 6, 1, "s" } }, l = { { -21, 0, 13 }, { 21, 0, 13 } } },                   -- 12 side ledges
    { b = { { -24, 9, 20, 1, "s" }, { 4, 9, 20, 1, "s" } }, l = { { -7, 0, 10 }, { 7, 0, 10 } } },                        -- 13 double deck
    { b = { { -1, 0, 2, 9, "s" }, { -2.5, 9, 5, 1, "s" } }, l = { { -1.9, 0, 10 }, { 1.9, 0, 10 } } },                 -- 14 centre pillar: capped, a ladder up each side
    { b = { { -6, 14, 12, 1, "g" }, { -6, 15, 1, 4, "g" }, { 5, 15, 1, 4, "g" } }, l = {} },                             -- 15 glass cup
    { b = { { -18, 6, 6, 1, "s" }, { 12, 6, 6, 1, "s" }, { -3, 12, 6, 1, "s" } }, l = { { -15, 0, 7 }, { 15, 0, 7 } } }, -- 16 three shelves
}
G.LAYOUTS = LAYOUTS
local COLORS = { "red", "blue", "green", "yellow", "purple" }
local BX = { -14, 14, -4, 6, -20, 20 }
local function stage_def(n)
    local lay = (n == 1) and LAYOUTS[1] or LAYOUTS[((n * 7) % (#LAYOUTS - 1)) + 2]
    if n == 2 then lay = LAYOUTS[2] end
    if n == 3 then lay = LAYOUTS[3] end
    local k = (n - 1) % 3 + 1
    local balls = {}
    local big = min(4, 1 + floor((n - 1) / 7))
    if n % 7 == 0 then
        for i = 1, 4 do balls[#balls + 1] = { 3, BX[i], 1 - 2 * (i % 2) } end
    else
        for i = 1, big do balls[#balls + 1] = { 4, BX[i], 1 - 2 * (i % 2) } end
        if k == 2 or n > 20 then balls[#balls + 1] = { 3, BX[#balls + 1] or 0, -1 } end
        if k == 3 then balls[#balls + 1] = { 2, BX[#balls + 1] or 0, 1 }; balls[#balls + 1] = { 2, BX[#balls + 1] or 2, -1 } end
    end
    local tm = min(150, 70 + 18 * #balls)
    return { n = n, loc = loc_of(n), lay = lay, balls = balls, color = COLORS[(n - 1) % #COLORS + 1], time = tm,
        crab = (n % 4 == 2 and n > 4), bird = (n % 4 == 0) }
end
G.stage_def = stage_def

------------------------------------------------------------------ live stage
local ST = nil
G.ST = function() return ST end
local BLK_MESH = { s = "blk_steel", r = "blk_glass_red", b = "blk_glass_blue", y = "blk_glass_yellow", g = "blk_glass_green" }
local BLK_COL = { s = { .7, .72, .78 }, r = { 1, .35, .35 }, b = { .4, .6, 1 }, y = { 1, .85, .3 }, g = { .4, 1, .5 } }
G.BLK_COL = BLK_COL
local BLKP = { "blk_steel", "blk_glass_red", "blk_glass_blue", "blk_glass_yellow", "blk_glass_green", "ladder", "rung" }
-- every ladder uses the same rung pitch, with rungs on a world-height grid so neighbouring ladders line up
local RUNG_PITCH = 0.65
local function build_stage(n)
    local d = stage_def(n)
    for _, k in ipairs(BLKP) do P_begin(k) end
    ST = { n = n, def = d, blocks = {}, ladders = {} }
    for _, b in ipairs(d.lay.b) do
        local blk = { x0 = b[1], y0 = b[2], w = b[3], h = b[4], x1 = b[1] + b[3], y1 = b[2] + b[4], kind = b[5], live = true }
        blk.node = P_get(BLK_MESH[blk.kind])
        blk.node:set_position(vec3(blk.x0 + blk.w / 2, blk.y0 + blk.h / 2, 0)); blk.node:set_scale(vec3(blk.w - 0.02, blk.h - 0.02, 2.0))
        ST.blocks[#ST.blocks + 1] = blk
    end
    for _, l in ipairs(d.lay.l) do
        local lad = { x = l[1], y0 = l[2], y1 = l[3] }
        lad.node = P_get("ladder"); lad.node:set_position(vec3(lad.x, lad.y0, 0.25)); lad.node:set_scale(vec3(1.25, lad.y1 - lad.y0, 1))
        local y = (floor(lad.y0 / RUNG_PITCH) + 1) * RUNG_PITCH - RUNG_PITCH / 2
        while y < lad.y1 - 0.15 do
            if y > lad.y0 + 0.2 then P_get("rung"):set_position(vec3(lad.x, y, 0.25)) end
            y = y + RUNG_PITCH
        end
        ST.ladders[#ST.ladders + 1] = lad
    end
    for _, k in ipairs(BLKP) do P_end(k) end
    G.set_backdrop(LOCS[d.loc][1])
    return ST
end
G.build_stage = build_stage
-- standing surfaces for the player / items: floor, block tops
local function support_at(x, y, hw, up, down)
    local best = nil
    if y <= up and y >= -down then best = 0 end
    for _, b in ipairs(ST.blocks) do
        if b.live and x + hw > b.x0 and x - hw < b.x1 and b.y1 >= y - down and b.y1 <= y + up then
            if not best or abs(b.y1 - y) < abs(best - y) then best = b.y1 end
        end
    end
    return best
end
G.support_at = support_at

------------------------------------------------------------------ frame, floor and the painted backdrop
local BG = {}
function G.set_backdrop(key)
    if BG.key == key then return end
    BG.key = key
    mtex(BG.plane, "emissive", "Textures/bg_" .. key .. ".png")
end
local function build_world()
    BG.plane = clone("bg_plane", vec3(0, 13, -2.7), vec3(48, 26, 1))
    local function fr(x, y, w, h, z, d) clone("frame", vec3(x, y, z or -0.2), vec3(w, h, d or 5.4)) end
    -- Posts sit 0.15 behind the lintel and floor and stop inside them, so the four
    -- corners are one surface. The old posts occupied the same volume and flickered.
    fr(-25, 13.05, 1.92, 26.5, -0.2, 5.1); fr(25, 13.05, 1.92, 26.5, -0.2, 5.1); fr(0, 27, 52, 2)
    clone("floor", vec3(0, -1.5, -0.2), vec3(52, 3, 5.4))
    -- surroundings so the frame doesn't float: a deep wall behind
    local back = prim("cube", vec3(0, 12, -6), vec3(140, 70, 1)); paint(back, { .08, .09, .11 }, { 0, 0, 0 }, .9, 0)
end
------------------------------------------------------------------ gameplay simulation (fixed 60 Hz, world units)
local FR = 1 / 60
local GRAV, BVX, POPV = 34, 4.8, 9.5
local RAD = { 0.38, 0.72, 1.35, 2.1 }            -- balloon radius by size 1..4
local APEX = { 6.5, 10, 14.5, 18.5 }             -- fixed bounce apex (centre height above the floor) by size
local PTS = { 200, 150, 100, 50 }
local BV = {}
for s = 1, 4 do BV[s] = sqrt(2 * GRAV * (APEX[s] - RAD[s])) end
local PW, PCLIMB, PHW, PH = 9.2, 6.2, 0.5, 2.6
local WIRE_V, BULLET_V = 30, 42
G.CONST = { GRAV = GRAV, BVX = BVX, RAD = RAD, APEX = APEX, PW = PW, PCLIMB = PCLIMB, WIRE_V = WIRE_V }
local BALLS, ROPES, SHOTS, ITEMS, ANIMALS = {}, {}, {}, {}, {}
G.BALLS, G.ROPES, G.SHOTS, G.ITEMS, G.ANIMALS = BALLS, ROPES, SHOTS, ITEMS, ANIMALS
local P = { x = 0, y = 0, ox = 0, oy = 0, st = "walk", face = 1, ph = 0, shoot_t = 0, weapon = "wire", shield = false, inv = 0, stun = 0, vx = 0, vy = 0 }
G.P = P
local HB = { pw = 0.45, py0 = 0.15, py1 = 2.15, ball_k = 0.9, rope = 0.12 }
G.HB = HB
local function circ_box(cx, cy, r, x0, y0, x1, y1)
    local px, py = clamp(cx, x0, x1), clamp(cy, y0, y1)
    local dx, dy = cx - px, cy - py
    return dx * dx + dy * dy < r * r
end
G.circ_box = circ_box

------------------------------------------------------------------ balloons
local function ball_new(size, x, y, vx, vy, col)
    BALLS[#BALLS + 1] = { size = size, x = x, y = y, ox = x, oy = y, vx = vx, vy = vy, col = col or ST.def.color, r = RAD[size], spin = rand() * 360 }
    return BALLS[#BALLS]
end
G.ball_new = ball_new
local function ball_step(b, dt)
    b.ox, b.oy = b.x, b.y
    b.vy = b.vy - GRAV * dt
    b.x = b.x + b.vx * dt; b.y = b.y + b.vy * dt
    local r = b.r
    if b.x - r < X0 then b.x = X0 + r; b.vx = abs(b.vx) end
    if b.x + r > X1 then b.x = X1 - r; b.vx = -abs(b.vx) end
    if b.y + r > CEIL then b.y = CEIL - r; b.vy = -abs(b.vy) end
    if b.y - r < 0 then b.y = r; b.vy = BV[b.size]; b.bounced = true end
    for _, k in ipairs(ST.blocks) do
        if k.live then
            local px, py = clamp(b.x, k.x0, k.x1), clamp(b.y, k.y0, k.y1)
            local dx, dy = b.x - px, b.y - py
            if dx * dx + dy * dy < r * r then
                if abs(dy) >= abs(dx) then
                    if dy > 0 or (dy == 0 and b.y > (k.y0 + k.y1) / 2) then b.y = k.y1 + r; b.vy = BV[b.size]
                    else b.y = k.y0 - r; b.vy = -abs(b.vy) end
                else
                    if dx > 0 then b.x = k.x1 + r; b.vx = abs(b.vx) else b.x = k.x0 - r; b.vx = -abs(b.vx) end
                end
            end
        end
    end
end
local ITEM_KINDS = { { "double", .17 }, { "power", .14 }, { "vulcan", .12 }, { "clock", .1 }, { "hourglass", .1 }, { "dynamite", .08 },
    { "shield", .1 }, { "life", .02 }, { "fruit", .17 } }
local function item_drop(x, y, forced)
    if not forced and rand() > 0.13 then return end
    local r, acc, kind = rand(), 0, "fruit"
    for _, k in ipairs(ITEM_KINDS) do acc = acc + k[2]; if r <= acc then kind = k[1]; break end end
    if kind == "life" and G.lives >= 6 then kind = "fruit" end
    ITEMS[#ITEMS + 1] = { kind = kind, x = clamp(x, X0 + 0.6, X1 - 0.6), y = y, oy = y, vy = 0, t = 0, fruit = floor(rr(1, 3.999)) }
end
G.item_drop = item_drop
local function ball_pop(i, silent_score)
    local b = BALLS[i]; if not b then return end
    table.remove(BALLS, i)
    if not silent_score then add_score(PTS[b.size], b.x, b.y + b.r + 0.6) end
    sfx("pop" .. b.size)
    local c = BALLC[b.col]
    sparks(b.x, b.y, c, 10 + b.size * 10, 10 + b.size * 4, b.r * 0.7)
    flash(b.x, b.y, c, 25 + b.size * 12, 0.3, 4 + b.size * 2)
    G.ring_fx(b.x, b.y, b.r, b.col)
    if b.size >= 4 then G.shake = max(G.shake, 0.35) end
    if b.size > 1 then
        local s = b.size - 1
        local y = max(b.y, RAD[s] + 0.05)
        ball_new(s, b.x - RAD[s] * 0.5, y, -BVX, POPV, b.col)
        ball_new(s, b.x + RAD[s] * 0.5, y, BVX, POPV, b.col)
        item_drop(b.x, b.y)
    end
end
G.ball_pop = ball_pop
local function dynamite()
    local again = true
    while again do
        again = false
        for i = #BALLS, 1, -1 do if BALLS[i].size > 1 then ball_pop(i, true); again = true end end
    end
    for i = #ITEMS, 1, -1 do if ITEMS[i].dyn then table.remove(ITEMS, i) end end
    sfx("boom"); G.shake = 0.8
end

------------------------------------------------------------------ blocks
local function block_break(k)
    k.live = false; k.node:set_position(HIDE)
    sfx("break"); add_score(100, (k.x0 + k.x1) / 2, k.y1 + 0.5)
    local c = G.BLK_COL[k.kind]
    for x = k.x0 + 0.5, k.x1 - 0.4, 1 do sparks(x, (k.y0 + k.y1) / 2, c, 10, 10, 0.4) end
    if rand() < 0.35 then item_drop((k.x0 + k.x1) / 2, k.y0, true) end
end

------------------------------------------------------------------ player
-- death: the classic Pang knock-back. A short hit-stop with a flash, then a keyframed arc away from the balloon
-- with a spin that eases out into lying on the back, one small bounce, and a still pose. Keys are {t, value, ease}
-- where ease shapes the segment towards the next key.
local EASE = { lin = function(u) return u end, out = function(u) return 1 - (1 - u) * (1 - u) end,
    ["in"] = function(u) return u * u end, inout = function(u) return u * u * (3 - 2 * u) end }
local function kf(keys, t)
    if t <= keys[1][1] then return keys[1][2] end
    for i = 1, #keys - 1 do
        local a, b = keys[i], keys[i + 1]
        if t < b[1] then return a[2] + (b[2] - a[2]) * EASE[a[3] or "lin"]((t - a[1]) / (b[1] - a[1])) end
    end
    return keys[#keys][2]
end
G.kf = kf
local DIE = {
    hold = 0.14,
    x = { { 0, 0 }, { 0.14, 0, "out" }, { 0.95, 4.6, "out" }, { 1.25, 5.3 } },
    up = { { 0, 0 }, { 0.14, 0, "out" }, { 0.52, 3.3, "in" }, { 0.95, 0 } },        -- lift above the start height, then down
    land = { { 0, 0 }, { 0.52, 0 }, { 0.95, 1, "out" } },                            -- 0..1 blend from start height to the floor
    bounce = { { 0, 0 }, { 0.95, 0, "out" }, { 1.1, 0.55, "in" }, { 1.25, 0 } },
    spin = { { 0, 0, "out" }, { 0.14, -18, "out" }, { 0.95, 450, "inout" }, { 1.1, 468, "inout" }, { 1.25, 450 } },
}
G.DIE = DIE
local function fold(x)       -- walls reflect the arc, like the arcade
    local lo, hi = X0 + 0.9, X1 - 0.9
    for _ = 1, 3 do if x < lo then x = 2 * lo - x elseif x > hi then x = 2 * hi - x end end
    return clamp(x, lo, hi)
end
local function death_step(dt)
    local t0 = P.dead_t; P.dead_t = P.dead_t + dt
    local t, D = P.dead_t, P.die
    P.x = fold(D.x0 + D.d * kf(DIE.x, t))
    P.y = lerp(D.y0, 0, kf(DIE.land, t)) + kf(DIE.up, t) + kf(DIE.bounce, t)
    if t0 < 0.95 and t >= 0.95 then dust(P.x, 0, 8); G.shake = max(G.shake, 0.25); sfx("thud") end
    if t0 < 1.25 and t >= 1.25 then dust(P.x, 0, 4) end
end
local function player_die(cause, bx)
    if P.st == "dead" or G.god then return end
    local d = bx and ((P.x >= bx) and 1 or -1) or ((P.x < 0) and 1 or -1)
    P.st = "dead"; P.dead_t = 0; P.vx, P.vy = 0, 0; P.cause = cause
    P.die = { x0 = P.x, y0 = P.y, d = d }
    music(nil); sfx("death"); G.shake = 0.6
    flash(P.x, P.y + 1.2, { 1, .95, .85 }, 32, 0.3, 7)
    G.ring_fx(P.x, P.y + 1.3, 1, { 1, 1, 1 })
    sparks(P.x, P.y + 1.3, { 1, .9, .6 }, 26, 14, 1)
    G.hit_flash = 1
end
G.player_die = player_die
local function ladder_near(x, y, top)
    for _, l in ipairs(ST.ladders) do
        if abs(x - l.x) < 0.75 then
            if top and abs(y - l.y1) < 0.35 then return l end
            if not top and abs(y - l.y0) < 0.35 then return l end
        end
    end
end
local function fire(inp)
    local w = P.weapon
    if w == "vulcan" then
        if inp.fire_held and (P.vcool or 0) <= 0 and #SHOTS < 8 then
            P.vcool = 0.09
            SHOTS[#SHOTS + 1] = { x = P.x + (#SHOTS % 2 == 0 and -0.2 or 0.2), y = P.y + 2.4, oy = P.y + 2.4 }
            sfx("vulcan"); P.shoot_t = 0.1
        end
        return
    end
    if not inp.fire then return end
    local cap = (w == "double") and 2 or 1
    if #ROPES >= cap then return end
    ROPES[#ROPES + 1] = { x = P.x, y0 = P.y, tip = P.y + 1.8, otip = P.y + 1.8, st = "rise", t = 0, power = (w == "power") }
    P.shoot_t = 0.14; sfx("shoot")
end
local function player_step(inp, dt)
    P.ox, P.oy = P.x, P.y
    P.vcool = (P.vcool or 0) - dt
    P.inv = max(0, P.inv - dt)
    if P.st == "dead" then death_step(dt); return end
    if P.stun > 0 then P.stun = P.stun - dt; return end
    fire(inp)
    if P.shoot_t > 0 then P.shoot_t = P.shoot_t - dt end
    local moving = P.shoot_t <= 0 or P.weapon == "vulcan" or G.jev_x
    if P.st == "walk" then
        local lu = inp.v > 0 and ladder_near(P.x, P.y, false)
        local ld = inp.v < 0 and ladder_near(P.x, P.y, true)
        if lu or ld then
            P.st = "climb"; P.ladder = lu or ld; P.x = P.ladder.x
        elseif moving and inp.h ~= 0 then
            P.face = inp.h
            local nx = P.x + inp.h * PW * dt
            for _, k in ipairs(ST.blocks) do
                if k.live and k.y0 < P.y + PH - 0.2 and k.y1 > P.y + 0.15 then
                    if inp.h > 0 and P.x + PHW <= k.x0 + 0.01 and nx + PHW > k.x0 then nx = k.x0 - PHW end
                    if inp.h < 0 and P.x - PHW >= k.x1 - 0.01 and nx - PHW < k.x1 then nx = k.x1 + PHW end
                end
            end
            P.x = clamp(nx, X0 + PHW, X1 - PHW)
            P.ph = P.ph + dt * 11
            P.step_t = (P.step_t or 0) - dt
            if P.step_t <= 0 then sfx("walk"); P.step_t = 0.24 end
        else P.step_t = 0 end
        local s = G.support_at(P.x, P.y, PHW * 0.5, 0.3, 0.3)
        if s then P.y = s else P.st = "fall"; P.vy = 0 end
    elseif P.st == "climb" then
        local l = P.ladder
        if inp.v ~= 0 then
            P.y = P.y + inp.v * PCLIMB * dt; P.ph = P.ph + dt * 9
            P.step_t = (P.step_t or 0) - dt
            if P.step_t <= 0 then sfx("climb"); P.step_t = 0.2 end
        end
        if P.y >= l.y1 then P.y = l.y1; P.st = "walk"
        elseif P.y <= l.y0 then P.y = l.y0; P.st = "walk" end
    elseif P.st == "fall" then
        local y0 = P.y
        P.vy = P.vy - 40 * dt; P.y = P.y + P.vy * dt
        local s = G.support_at(P.x, (y0 + P.y) / 2, PHW * 0.5, (y0 - P.y) / 2 + 0.05, (y0 - P.y) / 2 + 0.05)
        if s and s <= y0 + 0.01 and s >= P.y - 0.01 then P.y = s; P.st = "walk"; dust(P.x, s, 5) end
        if P.y < 0 then P.y = 0; P.st = "walk" end
    end
end

------------------------------------------------------------------ wires + vulcan shots
local function rope_hits_ball(r)
    for i = #BALLS, 1, -1 do
        local b = BALLS[i]
        local cy = clamp(b.y, r.y0, r.tip)
        local dx, dy = b.x - r.x, b.y - cy
        local rad = b.r + HB.rope
        if dx * dx + dy * dy < rad * rad then ball_pop(i); return true end
    end
    for i = #ANIMALS, 1, -1 do
        local a = ANIMALS[i]
        if a.st ~= "hit" and abs(a.x - r.x) < 0.9 and a.y < r.tip and a.y + 1.0 > r.y0 then
            a.st = "hit"; a.vy = 10; add_score(500, a.x, a.y + 1.5); sfx("animal"); sparks(a.x, a.y + 0.5, { 1, .8, .4 }, 20); return true
        end
    end
    return false
end
local function rope_step(r, i, dt)
    r.otip = r.tip
    if r.st == "rise" then
        local nt = r.tip + WIRE_V * dt
        local stop = nil
        if nt >= CEIL then stop = CEIL; r.hit = "ceil" end
        for _, k in ipairs(ST.blocks) do
            if k.live and r.x > k.x0 - 0.05 and r.x < k.x1 + 0.05 and r.y0 < k.y0 and nt >= k.y0 and (not stop or k.y0 < stop) then stop = k.y0; r.hit = k end
        end
        r.tip = stop or nt
        if rope_hits_ball(r) then table.remove(ROPES, i); return end
        if stop then
            local k = r.hit
            if type(k) == "table" and k.kind ~= "s" then block_break(k); table.remove(ROPES, i); return end
            if r.power then r.st = "stick"; r.t = 3.0; sfx("climb") else table.remove(ROPES, i) end
            if type(k) ~= "table" then sparks(r.x, r.tip, { .9, .9, 1 }, 6, 6, 0.1) end
            return
        end
    else
        r.t = r.t - dt
        if rope_hits_ball(r) or r.t <= 0 then table.remove(ROPES, i) end
    end
end
local function shot_step(s, i, dt)
    s.oy = s.y; s.y = s.y + BULLET_V * dt
    if s.y >= CEIL then table.remove(SHOTS, i); return end
    for _, k in ipairs(ST.blocks) do
        if k.live and s.x > k.x0 and s.x < k.x1 and s.y >= k.y0 and s.oy <= k.y1 then
            if k.kind ~= "s" then block_break(k) end
            table.remove(SHOTS, i); return
        end
    end
    for j = #BALLS, 1, -1 do
        local b = BALLS[j]
        local cy = clamp(b.y, s.oy - 0.3, s.y)
        local dx, dy = b.x - s.x, b.y - cy
        if dx * dx + dy * dy < (b.r + 0.15) ^ 2 then ball_pop(j); table.remove(SHOTS, i); return end
    end
end

------------------------------------------------------------------ items + animals
local function apply_item(it)
    local k = it.kind
    if k == "double" or k == "power" or k == "vulcan" then P.weapon = k; sfx("weapon"); popup(it.x, it.y + 1.5, ({ double = "Double Wire", power = "Power Wire", vulcan = "Vulcan Missile" })[k], { .7, .9, 1 })
    elseif k == "clock" then G.freeze_t = 6; sfx("freeze"); popup(it.x, it.y + 1.5, "Time Stop", { .7, .9, 1 })
    elseif k == "hourglass" then G.slow_t = 8; sfx("freeze"); popup(it.x, it.y + 1.5, "Slow", { .7, .9, 1 })
    elseif k == "dynamite" then dynamite()
    elseif k == "shield" then P.shield = true; sfx("shield")
    elseif k == "life" then G.lives = G.lives + 1; sfx("life"); popup(it.x, it.y + 1.5, "1UP", { 1, .9, .5 })
    else add_score(({ 500, 1000, 2000 })[it.fruit], it.x, it.y + 1.2); sfx("item") end
end
local function item_step(it, i, dt)
    it.t = it.t + dt
    it.oy = it.y
    if not it.landed then
        local y0 = it.y
        it.vy = it.vy - 20 * dt; it.y = it.y + it.vy * dt
        local s = G.support_at(it.x, (y0 + it.y) / 2, 0.3, (y0 - it.y) / 2 + 0.05, (y0 - it.y) / 2 + 0.05)
        if s and s <= y0 + 0.01 then it.y = s; it.landed = true end
        if it.y <= 0 then it.y = 0; it.landed = true end
    else
        local s = G.support_at(it.x, it.y, 0.3, 0.05, 0.05)
        if not s then it.landed = false; it.vy = 0 end
    end
    if it.t > 7 then table.remove(ITEMS, i); return end
    if P.st ~= "dead" and abs(it.x - P.x) < 1.0 and it.y < P.y + 2.2 and it.y + 1.0 > P.y then apply_item(it); table.remove(ITEMS, i) end
end
local function animal_spawn(kind)
    local side = rand() < 0.5 and -1 or 1
    if kind == "crab" then ANIMALS[#ANIMALS + 1] = { kind = "crab", x = side * 23, y = 0, vx = -side * 3.2, st = "walk", t = 0, ox = side * 23, oy = 0 }
    else local y = rr(15, 20); ANIMALS[#ANIMALS + 1] = { kind = "bird", x = side * 23.5, y = y, y0 = y, vx = -side * 5, st = "fly", t = 0, ox = side * 23.5, oy = y } end
end
G.animal_spawn = animal_spawn
local function animal_step(a, i, dt)
    a.ox, a.oy = a.x, a.y
    a.t = a.t + dt
    if a.st == "hit" then
        a.vy = a.vy - 30 * dt; a.y = a.y + a.vy * dt; a.x = a.x + a.vx * 0.3 * dt
        if a.y < -4 then table.remove(ANIMALS, i) end
        return
    end
    a.x = a.x + a.vx * dt
    if a.kind == "crab" then
        if a.x < X0 + 1 or a.x > X1 - 1 then a.vx = -a.vx; a.x = clamp(a.x, X0 + 1, X1 - 1); a.turns = (a.turns or 0) + 1 end
        if (a.turns or 0) >= 3 and (a.x < X0 + 1.2 or a.x > X1 - 1.2) then table.remove(ANIMALS, i); return end
        if P.st ~= "dead" and P.inv <= 0 and P.stun <= 0 and abs(a.x - P.x) < 1.1 and P.y < 1.0 then P.stun = 1.4; P.inv = 2.6; sfx("animal") end
    else
        a.y = a.y0 + sin(a.t * 3) * 1.2
        if a.x < X0 - 1 or a.x > X1 + 1 then table.remove(ANIMALS, i); return end
    end
end

------------------------------------------------------------------ collisions + step
local function player_hit()
    if P.st == "dead" or P.inv > 0 then return end
    local x0, y0, x1, y1 = P.x - HB.pw, P.y + HB.py0, P.x + HB.pw, P.y + HB.py1
    for i, b in ipairs(BALLS) do
        if circ_box(b.x, b.y, b.r * HB.ball_k, x0, y0, x1, y1) then
            if P.shield then
                P.shield = false; P.inv = 1.6; sfx("shield"); sparks(P.x, P.y + 1.3, { .5, .85, 1 }, 30, 16, 1)
                b.vy = BV[b.size]; b.vx = (b.x > P.x) and abs(b.vx) or -abs(b.vx)
            else player_die("ball", b.x) end
            return
        end
    end
end
local function stage_step(inp, dt)
    if P.st ~= "dead" then
        G.time = G.time - dt
        if G.time <= 15 and floor(G.time + dt) ~= floor(G.time) and G.time > 0 then sfx("warn") end
        if G.time <= 0 then G.time = 0; player_die("time") end
    end
    player_step(inp, dt)
    if P.st == "dead" then return end
    local bdt = dt
    if (G.freeze_t or 0) > 0 then G.freeze_t = G.freeze_t - dt; bdt = 0 end
    if (G.slow_t or 0) > 0 then G.slow_t = G.slow_t - dt; bdt = bdt * 0.4 end
    if bdt > 0 then for _, b in ipairs(BALLS) do ball_step(b, bdt) end else for _, b in ipairs(BALLS) do b.ox, b.oy = b.x, b.y end end
    for i = #ROPES, 1, -1 do rope_step(ROPES[i], i, dt) end
    for i = #SHOTS, 1, -1 do shot_step(SHOTS[i], i, dt) end
    for i = #ITEMS, 1, -1 do item_step(ITEMS[i], i, dt) end
    for i = #ANIMALS, 1, -1 do animal_step(ANIMALS[i], i, dt) end
    player_hit()
    -- animals now and then
    local d = ST.def
    G.animal_t = (G.animal_t or 12) - dt
    if G.animal_t <= 0 and #ANIMALS == 0 and (d.crab or d.bird) then G.animal_t = rr(14, 22); animal_spawn(d.crab and "crab" or "bird") end
end
G.stage_step = stage_step
local function clear_all()
    for _, t in ipairs({ BALLS, ROPES, SHOTS, ITEMS, ANIMALS }) do for i = #t, 1, -1 do t[i] = nil end end
end
G.clear_all = clear_all
local function stage_reset(n)
    clear_all()
    build_stage(n)
    for i, b in ipairs(ST.def.balls) do
        local s = b[1]; local y = (s == 4) and 18 or 16
        for _, k in ipairs(ST.blocks) do if circ_box(b[2], y, RAD[s] + 0.3, k.x0, k.y0, k.x1, k.y1) then y = 22.5 end end
        ball_new(s, b[2], y, b[3] * BVX, 0, ST.def.color)
    end
    -- spawn at the centre, unless a wall stands there (centre pillar): then just right of it
    local sx = 0
    for _, k in ipairs(ST.blocks) do if k.y0 < PH - 0.2 and sx + PHW > k.x0 and sx - PHW < k.x1 then sx = k.x1 + PHW + 0.6 end end
    P.x, P.y, P.ox, P.oy = sx, 0, sx, 0; P.st = "walk"; P.face = 1; P.shoot_t = 0; P.inv = 0; P.stun = 0
    P.weapon = "wire"; P.shield = false
    G.time = ST.def.time; G.freeze_t = 0; G.slow_t = 0; G.animal_t = 12
end
G.stage_reset = stage_reset
------------------------------------------------------------------ player rig (pivots match tools/gen_meshes.py)
local function V(x, y, z) return vec3(x, y, z) end
local function grp(parent, pos, meshes)
    local g = empty("grp", parent, pos)
    for _, m in ipairs(meshes) do clone(m, V(0, 0, 0), nil, g) end
    return g
end
local R = {}
local function build_player()
    local root = empty("Hero", nil, HIDE)
    R.root = root
    R.body = empty("body", root, V(0, 0, 0))           -- death pose pivot (keyframed in render_player)
    local B = R.body
    R.torso = grp(B, V(0, 1.0, 0), { "pl_shirt", "pl_trim", "pl_button", "pl_belt", "pl_buckle", "pl_shorts", "pl_pack", "pl_packflap", "pl_strap" })
    R.head = grp(B, V(0, 1.95, 0), { "pl_skin", "pl_eyew", "pl_eye", "pl_mouth", "pl_hair", "pl_helmet", "pl_hband" })
    R.arm_l = grp(B, V(0, 1.78, 0.38), { "pl_sleeve", "pl_hand" })
    R.arm_r = grp(B, V(0, 1.78, -0.38), { "pl_sleeve", "pl_hand" })
    R.leg_l = grp(B, V(0, 0.98, 0.16), { "pl_shortleg", "pl_leg", "pl_sock", "pl_boot", "pl_sole", "pl_lace" })
    R.leg_r = grp(B, V(0, 0.98, -0.16), { "pl_shortleg", "pl_leg", "pl_sock", "pl_boot", "pl_sole", "pl_lace" })
    R.gun = grp(B, V(0.3, 1.0, 0), { "pl_gun", "pl_gunwood" })
    R.shield = clone("shield_ring")
end
G.R = R
local AL = 1
local function ip(e) return lerp(e.ox or e.x, e.x, AL), lerp(e.oy or e.y, e.y, AL) end
G.vis = { yaw = -25, z = 0 }
local VIS = G.vis
local function render_player(dt)
    if G.hide_player then R.root:set_position(HIDE); R.shield:set_position(HIDE); return end
    local x, y = ip(P)
    x = clamp(x, X0 + 0.9, X1 - 0.9)
    local st = P.st
    local shooting = P.shoot_t > 0 and st ~= "dead"
    local yaw_t = (st == "climb") and 90 or (shooting and -90 or (P.face > 0 and -25 or 205))
    if yaw_t - VIS.yaw > 180 then VIS.yaw = VIS.yaw + 360 elseif VIS.yaw - yaw_t > 180 then VIS.yaw = VIS.yaw - 360 end
    VIS.yaw = damp(VIS.yaw, yaw_t, 22, dt)
    VIS.z = damp(VIS.z, st == "climb" and 0.9 or 0, 14, dt)
    local s = sin(P.ph)
    local ll, lr, al, ar, rz, rx, hz = 0, 0, 0, 0, 0, 0, 0
    local gpos, grot = V(0.32, 1.05, 0.05), -80
    if st == "walk" and abs(P.x - P.ox) > 0.001 then ll, lr, al, ar = 32 * s, -32 * s, -26 * s, 26 * s end
    if st == "climb" then al, ar = 150 + 25 * s, 150 - 25 * s; ll, lr = 30 * max(0, s), 30 * max(0, -s); gpos = V(-0.3, 1.2, 0) end
    if st == "fall" then ll, lr, al, ar = 20, -20, 60, 60 end
    if shooting or (P.weapon == "vulcan" and P.shoot_t > 0) then al, ar = 172, 172; gpos, grot = V(0.12, 2.35, 0), 0 end
    local piv = 0
    if st == "dead" then
        -- keyframed knock-back pose (timing shared with the arc in 04_sim): shock, flail through the spin, limp on the floor
        local t, kf, D = P.dead_t or 0, G.kf, G.DIE
        local d = P.die and P.die.d or 1
        rz = -d * kf(D.spin, t)
        local shock = 1 - kf({ { 0, 0 }, { 0.1, 0, "inout" }, { 0.3, 1 } }, t)               -- 1 during the hit-stop
        local limp = kf({ { 0, 0 }, { 0.9, 0, "inout" }, { 1.3, 1 } }, t)
        local fl = sin(t * 26) * (1 - limp) * (1 - shock)
        al = lerp(lerp(150 + 40 * fl, 165, shock), 100, limp); ar = lerp(lerp(140 - 40 * fl, 165, shock), 75, limp)
        ll = lerp(lerp(35 + 25 * fl, 40, shock), 12, limp); lr = lerp(lerp(-30 - 25 * fl, -40, shock), -6, limp)
        hz = 25 * fl
        piv = 1.25                                                                           -- spin about the body centre
        VIS.yaw = -90
    end
    if P.stun > 0 then hz = 18 * sin(G.t * 16) end
    local blink = (P.inv > 0 and st ~= "dead" and floor(G.t * 14) % 2 == 0)
    -- dead: root sits at the body centre so the spin turns about it; lift keeps the body above the floor at any angle
    local lift = piv > 0 and (piv * abs(cos(math.rad(rz))) + 0.42 * abs(sin(math.rad(rz)))) or 0
    R.root:set_position(blink and HIDE or V(x, y + lift, VIS.z))
    R.body:set_position(V(0, -piv, 0))
    R.root:set_rotation(V(rx, VIS.yaw, rz))
    R.leg_l:set_rotation(V(0, 0, ll)); R.leg_r:set_rotation(V(0, 0, lr))
    R.arm_l:set_rotation(V(0, 0, al)); R.arm_r:set_rotation(V(0, 0, ar))
    R.head:set_rotation(V(hz, 0, 0))
    R.gun:set_position(gpos); R.gun:set_rotation(V(0, 0, grot))
    if P.shield and st ~= "dead" then
        R.shield:set_position(V(x, y + 1.3, 0.2)); R.shield:set_scale(V(1.55, 1.75, 1.55)); R.shield:set_rotation(V(0, G.t * 120, 0))
    else R.shield:set_position(HIDE) end
end

------------------------------------------------------------------ balloons, wires, shots, items, animals (pooled each frame)
G.RINGS = {}
function G.ring_fx(x, y, r, col) G.RINGS[#G.RINGS + 1] = { x = x, y = y, r = r, t = 0 } end
local ITEM_MESH = { double = { "it_double" }, power = { "it_power" }, vulcan = { "it_vulcan" }, clock = { "it_clock", "it_hands" },
    hourglass = { "it_hourglass", "it_hg_frame" }, dynamite = { "it_dynamite", "it_fuse" }, shield = { "it_shield" }, life = { "it_life" } }
local FRUIT_MESH = { { "fr_cherry", "fr_stem" }, { "fr_apple", "fr_stem" }, { "fr_grape", "fr_stem" } }
local DYN = { "ball_red", "ball_blue", "ball_green", "ball_yellow", "ball_purple", "ball_shine", "shadow", "pop_ring", "wire", "wire_tip", "hook", "bullet",
    "it_double", "it_power", "it_vulcan", "it_clock", "it_hands", "it_hourglass", "it_hg_frame", "it_dynamite", "it_fuse", "it_shield", "it_life",
    "fr_cherry", "fr_stem", "fr_apple", "fr_grape", "cr_body", "cr_claw", "cr_legs", "cr_eye", "bd_body", "bd_beak", "bd_wing" }
local function shadow_y(x, y)
    local best = 0
    if ST then for _, k in ipairs(ST.blocks) do if k.live and x > k.x0 and x < k.x1 and k.y1 <= y + 0.01 and k.y1 > best then best = k.y1 end end end
    return best
end
local function render_dyn(dt)
    for _, k in ipairs(DYN) do P_begin(k) end
    local t = G.t
    for _, b in ipairs(BALLS) do
        local x, y = ip(b)
        local r = b.r
        local sq = 0
        if b.bounced then b.sq = 1; b.bounced = false end
        if b.sq then b.sq = max(0, b.sq - dt * 7); sq = b.sq * 0.12 end
        local n = P_get("ball_" .. b.col)
        n:set_position(V(x, y - r * sq, 0)); n:set_scale(V(r * (1 + sq), r * (1 - sq), r * (1 + sq)))
        local sh = P_get("ball_shine"); sh:set_position(V(x, y - r * sq, 0)); sh:set_scale(V(r, r * (1 - sq), r))
        local gy = shadow_y(x, y - r)
        local h = y - r - gy
        local ss = r * clamp(1.1 - h * 0.04, 0.35, 1.1)
        local d = P_get("shadow"); d:set_position(V(x, gy + 0.02, 0.2)); d:set_rotation(V(90, 0, 0)); d:set_scale(V(ss, ss * 0.6, 1))
    end
    for i = #G.RINGS, 1, -1 do
        local g = G.RINGS[i]; g.t = g.t + dt
        if g.t > 0.3 then table.remove(G.RINGS, i) else
            local k = g.t / 0.3; local s = g.r * (1 + 1.4 * k)
            local n = P_get("pop_ring"); n:set_position(V(g.x, g.y, 0.3)); n:set_scale(V(s, s, s * (1 - k) + 0.05))
        end
    end
    for _, r in ipairs(ROPES) do
        local tip = lerp(r.otip or r.tip, r.tip, AL)
        local y = r.y0
        while y < tip - 0.001 do
            local len = min(1, tip - y)
            local n = P_get("wire"); n:set_position(V(r.x, y, 0.3)); n:set_scale(V(2.2, len, 2.2))
            y = y + 1
        end
        local tipn = P_get(r.power and "hook" or "wire_tip"); tipn:set_position(V(r.x, tip, 0.3))
        if r.st == "stick" and r.t < 0.8 and floor(t * 12) % 2 == 0 then tipn:set_position(HIDE) end
    end
    for _, s in ipairs(SHOTS) do local n = P_get("bullet"); n:set_position(V(s.x, lerp(s.oy, s.y, AL), 0.3)) end
    for _, it in ipairs(ITEMS) do
        local vis = not (it.t > 5 and floor(t * 10) % 2 == 0)
        local ms = it.kind == "fruit" and FRUIT_MESH[it.fruit] or ITEM_MESH[it.kind]
        for _, m in ipairs(ms) do
            local n = P_get(m)
            n:set_position(vis and V(it.x, lerp(it.oy, it.y, AL) + 0.05, 0.3) or HIDE); n:set_rotation(V(0, 30 * sin(t * 2 + it.x), 0)); n:set_scale(V(1.15, 1.15, 1.15))
        end
    end
    for _, a in ipairs(ANIMALS) do
        local x, y = ip(a)
        local rz = a.st == "hit" and t * 600 or 0
        if a.kind == "crab" then
            local yaw = 15 * sin(t * 2)
            for _, m in ipairs({ "cr_body", "cr_claw", "cr_legs", "cr_eye" }) do
                local n = P_get(m); n:set_position(V(x, y + (m == "cr_legs" and 0 or 0.05 * abs(sin(t * 14))), 0.4)); n:set_rotation(V(0, yaw, rz)); n:set_scale(V(1.1, 1.1, 1.1))
            end
        else
            local yaw = a.vx > 0 and 0 or 180
            local b = P_get("bd_body"); b:set_position(V(x, y, 0.4)); b:set_rotation(V(0, yaw, rz))
            local bk = P_get("bd_beak"); bk:set_position(V(x, y, 0.4)); bk:set_rotation(V(0, yaw, rz))
            local f = 50 * sin(t * 16)
            local w1 = P_get("bd_wing"); w1:set_position(V(x, y + 0.1, 0.55)); w1:set_rotation(V(f, yaw, 0))
            local w2 = P_get("bd_wing"); w2:set_position(V(x, y + 0.1, 0.25)); w2:set_rotation(V(180 - f, yaw, 0))
        end
    end
    for _, k in ipairs(DYN) do P_end(k) end
end

------------------------------------------------------------------ camera
G.shake = 0
local function update_camera(dt)
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.45 * SET:shake_scale()
    local ox, oy = a * sin(G.t * 53), a * cos(G.t * 61)
    if G.cam_ov then local o = G.cam_ov; cam:set_position(V(o[1], o[2], o[3])); cam:look_at(V(o[4], o[5], o[6] or 0)); return end
    local sway = sin(G.t * 0.23) * 0.2
    cam:set_position(V(sway + ox, CAMY + 0.6 + oy, CAMZ)); cam:look_at(V(sway * 0.4 + ox * 0.5, CAMY + oy * 0.5, 0))
end

------------------------------------------------------------------ collider debug overlay (F3)
G.DBG = { on = false, pool = {}, used = 0, z = 3.0, w = 0.16 }
local DC = { floor = { .1, 1, 1 }, block = { 1, .9, .2 }, ladder = { .9, .6, .2 }, player = { .2, 1, .3 }, ball = { 1, .25, .2 }, rope = { 1, .6, .1 }, item = { 1, .4, .9 } }
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
    local ax, ay = c.x + (x0 - c.x) * k, c.y + (y0 - c.y) * k
    local bx, by = c.x + (x1 - c.x) * k, c.y + (y1 - c.y) * k
    local dx, dy = bx - ax, by - ay
    b.n:set_position(V((ax + bx) * .5, (ay + by) * .5, D.z))
    b.n:set_rotation(V(0, 0, math.deg(atan2(dy, dx))))
    b.n:set_scale(V(sqrt(dx * dx + dy * dy) + D.w, D.w, D.w))
end
local function dbox(x0, y0, x1, y1, c) G.dbg_bar(x0, y0, x1, y0, c); G.dbg_bar(x1, y0, x1, y1, c); G.dbg_bar(x1, y1, x0, y1, c); G.dbg_bar(x0, y1, x0, y0, c) end
local function dcirc(x, y, r, c)
    local n = 16
    for i = 0, n - 1 do
        local a0, a1 = i / n * 2 * PI, (i + 1) / n * 2 * PI
        G.dbg_bar(x + r * cos(a0), y + r * sin(a0), x + r * cos(a1), y + r * sin(a1), c)
    end
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and ST then
        G.dbg_bar(X0, 0, X1, 0, DC.floor); G.dbg_bar(X0, 0, X0, CEIL, DC.floor); G.dbg_bar(X1, 0, X1, CEIL, DC.floor); G.dbg_bar(X0, CEIL, X1, CEIL, DC.floor)
        for _, k in ipairs(ST.blocks) do if k.live then dbox(k.x0, k.y0, k.x1, k.y1, DC.block) end end
        for _, l in ipairs(ST.ladders) do dbox(l.x - 0.75, l.y0, l.x + 0.75, l.y1, DC.ladder) end
        if P.st ~= "dead" then dbox(P.x - HB.pw, P.y + HB.py0, P.x + HB.pw, P.y + HB.py1, DC.player) end
        for _, b in ipairs(BALLS) do dcirc(b.x, b.y, b.r * HB.ball_k, DC.ball) end
        for _, r in ipairs(ROPES) do dbox(r.x - HB.rope, r.y0, r.x + HB.rope, r.tip, DC.rope) end
        for _, it in ipairs(ITEMS) do dbox(it.x - 0.6, it.y, it.x + 0.6, it.y + 1, DC.item) end
        for _, a in ipairs(ANIMALS) do dbox(a.x - 0.9, a.y, a.x + 0.9, a.y + 1, DC.ball) end
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
local RED, WHITE, CYAN, DIM, GOLD = { 1, .35, .3, 1 }, { 1, 1, 1, 1 }, { .5, .85, 1, 1 }, { .8, .78, .75, 1 }, { 1, .85, .45, 1 }
local WNAME = { wire = "Wire", double = "Double Wire", power = "Power Wire", vulcan = "Vulcan Missile" }
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause" or st == "over" or st == "clear" or st == "intro") and not G.set_open
    -- bottom strip under the play field
    local _, fy = to_screen(0, -3.1)
    local by = min(fy, SH - 120 * US)
    local bh = SH - by - 10 * US
    panel("hb", 20 * US, by, SW - 40 * US, bh, play, 0.6)
    local cy = by + 8 * US
    text("h1", "1UP", 50 * US, cy, 200 * US, 40 * US, 1.3, RED, "left", play)
    text("h1s", pad6(G.score), 50 * US, cy + 38 * US, 300 * US, 52 * US, 1.9, WHITE, "left", play)
    local nl = G.lives - ((st == "play" and P.st ~= "dead") and 1 or 0)
    for i = 1, 6 do
        quad("life" .. i, { x = 360 * US + (i - 1) * 34 * US, y = cy + 52 * US, w = 26 * US, h = 22 * US, z = 7, style = "text", label = "",
            fill = { 0.93, 0.88, 0.74, 0.95 }, border = { 0.5, 0.35, 0.2, 1 }, corner_radius = 11 * US, no_input = true, visible = play and i <= nl })
    end
    local d = ST and ST.def
    local loc = d and LOCS[d.loc][2] or ""
    text("hloc", loc, SW / 2 - 300 * US, cy, 600 * US, 44 * US, 1.4, CYAN, "center", play)
    text("hstg", d and string.format("Stage %d", d.n) or "", SW / 2 - 300 * US, cy + 44 * US, 600 * US, 40 * US, 1.1, DIM, "center", play)
    local tcol = (G.time or 99) <= 15 and (floor(G.t * 4) % 2 == 0 and RED or WHITE) or WHITE
    text("htl", "TIME", SW / 2 + 330 * US, cy, 200 * US, 40 * US, 1.1, RED, "left", play)
    text("htv", tostring(math.ceil(G.time or 0)), SW / 2 + 330 * US, cy + 38 * US, 200 * US, 52 * US, 1.9, tcol, "left", play)
    local wtxt = WNAME[P.weapon] .. (P.shield and "  +  Shield" or "")
    if (G.freeze_t or 0) > 0 then wtxt = wtxt .. "  ·  Time Stop" elseif (G.slow_t or 0) > 0 then wtxt = wtxt .. "  ·  Slow" end
    text("hw", wtxt, SW / 2 + 500 * US, cy + 50 * US, 420 * US, 36 * US, 0.95, GOLD, "left", play and SW > 1500 * US)
    text("hh", "HIGH", SW - 380 * US, cy, 330 * US, 40 * US, 1.1, RED, "right", play)
    text("hhs", pad6(max(G.hiscore, G.score)), SW - 380 * US, cy + 38 * US, 330 * US, 52 * US, 1.6, WHITE, "right", play)
    -- popups
    for i, p in ipairs(G.POP) do
        p.t = p.t + dt
        local vis = (st == "play" or st == "clear") and not G.set_open and p.t < 1.0
        local px, py = 0, 0
        if vis then px, py = to_screen(p.x, p.y + p.t * 2) end
        local a = floor(clamp((1.0 - p.t) / 0.3, 0, 1) * 10) / 10
        text("pop" .. i, p.txt or "", px - 140 * US, py - 18 * US, 280 * US, 36 * US, 1.1, { p.col[1] or 1, p.col[2] or 1, p.col[3] or 1, a }, "center", vis)
    end
    -- stage card / ready / clear
    local card = st == "intro" and not G.set_open
    panel("c_bg", SW / 2 - 380 * US, SH * 0.3, 760 * US, 220 * US, card, 0.6)
    text("c_loc", loc, 0, SH * 0.3 + 20 * US, SW, 80 * US, 2.6, WHITE, "center", card)
    text("c_stg", d and string.format("Stage %d", d.n) or "", 0, SH * 0.3 + 100 * US, SW, 50 * US, 1.5, CYAN, "center", card)
    text("c_rdy", "Ready", 0, SH * 0.3 + 150 * US, SW, 50 * US, 1.5, GOLD, "center", card and (G.intro_t or 0) > 1.0)
    local clr = st == "clear" and not G.set_open
    panel("k_bg", SW / 2 - 380 * US, SH * 0.3, 760 * US, 220 * US, clr, 0.6)
    text("k_t", "Stage Clear", 0, SH * 0.3 + 20 * US, SW, 80 * US, 2.6, GOLD, "center", clr)
    text("k_b", "Time Bonus  " .. tostring(G.tbonus or 0), 0, SH * 0.3 + 110 * US, SW, 50 * US, 1.5, WHITE, "center", clr)
    local dead = st == "play" and P.st == "dead" and (P.dead_t or 0) > 0.8 and not G.set_open
    text("d_t", P.cause == "time" and "Time Over" or "", 0, SH * 0.4, SW, 80 * US, 2.6, RED, "center", dead)
    -- death hit flash: a brief white screen flash that fades over the hit-stop
    G.hit_flash = max(0, (G.hit_flash or 0) - dt * 4.5)
    local hf = G.hit_flash
    quad("hitfl", { x = 0, y = 0, w = SW, h = SH, z = 3, style = "text", label = "", fill = { 1, .97, .9, 0.55 * hf * hf }, border = NONE,
        no_input = true, visible = hf > 0.01 })
    -- title
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 480 * US, SH * 0.06, 960 * US, SH * 0.84, title, 0.62)
    text("t_title", "Pang Remix", 0, SH * 0.08, SW, 130 * US, 4.4, { 1, .45, .35, 1 }, "center", title)
    text("t_sub", "Fire your wire straight up and split every balloon, around the world in 50 stages", 0, SH * 0.08 + 118 * US, SW, 40 * US, 1.05, DIM, "center", title)
    text("t_ctl1", "A / D or Left / Right: walk   ·   W / S or Up / Down: climb ladders", 0, SH * 0.68, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_ctl2", "Space / Z / J / Left Click: fire   ·   hold for the Vulcan Missile", 0, SH * 0.68 + 34 * US, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_ctl3", "P / Esc: pause   ·   O: settings   ·   M: mute   ·   F3: colliders", 0, SH * 0.68 + 68 * US, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_hi", "High score " .. pad6(G.hiscore), 0, SH * 0.68 + 112 * US, SW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, CYAN, "center", pause)
    local over = st == "over" and not G.set_open
    local win = G.won
    panel("o_bg", SW / 2 - 380 * US, SH * 0.24, 760 * US, SH * 0.52, over, 0.78)
    text("o_t", win and "Congratulations" or "Game Over", 0, SH * 0.26, SW, 90 * US, 3.0, win and GOLD or RED, "center", over)
    text("o_s", "Score " .. pad6(G.score) .. "  ·  Stage " .. tostring(ST and ST.n or 1), 0, SH * 0.26 + 90 * US, SW, 40 * US, 1.3, DIM, "center", over)
    local c = {}
    local hasc = title and (G.cont_stage or 1) > 1
    local yb = SH * 0.36
    c.start = button("b_start", "Start (Enter)", SW / 2 - 200 * US, yb, title)
    c.jev = button("b_jev", "Jev", SW / 2 + 200 * US, yb, title)
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
    text("t_jerr", G.jev_err or "", 40 * US, SH * 0.82, SW - 80 * US, 32 * US, 0.8, RED, "center", (title or st == "pause") and G.jev_err ~= nil)
    return c
end

------------------------------------------------------------------ flow
local jev
local function to_title()
    jev:begin_human()
    G.state = "title"; G.won = false; G.cam_ov = nil
    G.stage_reset(1 + floor(rand() * 9))
    G.hide_player = true
    music("title")
end
G.to_title = to_title
local function start_stage(n)
    G.stage_reset(n)
    G.hide_player = false
    G.state = "intro"; G.intro_t = 0
    music(nil); sfx("ready")
end
G.start_stage = start_stage
local function new_game(n)
    G.score, G.lives = 0, 3; G.extra_at = 20000
    start_stage(n or 1)
end
G.new_game = new_game
local function game_over(won)
    G.state = "over"; G.over_t = 0; G.won = won
    music(nil); sfx(won and "clear" or "gameover")
    if jev and jev:assisted() then return end
    if G.score > G.hiscore then G.hiscore = G.score; save_hi() end
end
G.cont_stage = 1

-- Hardware edges only. Virtual keys live in G.vk and must not count as a human.
local RAW_PLAY = { "Left", "Right", "A", "D", "Up", "Down", "W", "S", "Space", "Z", "J" }
local raw_prev = {}
local human_edged = false
local function sample_human()
    local raw = input.is_key_down_raw
    human_edged = false
    if not raw then
        return
    end

    for i = 1, #RAW_PLAY do
        local key = RAW_PLAY[i]
        local ok, v = pcall(raw, key)
        local down = ok and v and true or false
        -- Settings uses these keys to turn Jev on. That is not the player taking the match.
        if down and not raw_prev[key] and not G.set_open then
            human_edged = true
        end
        raw_prev[key] = down
    end
end

local function clear_hold()
    G.vk = {}
    G.fire_pulse = false
    G.jev_x = nil
    G._jev_cache = nil
end

local function round2(v)
    if v >= 0 then
        return floor(v * 100 + 0.5) / 100
    end
    return floor(v * 100 - 0.5) / 100
end

local function nearest_balloon()
    local best, best_d = nil, 1e18
    for _, b in ipairs(BALLS) do
        local dx = b.x - P.x
        local dy = b.y - P.y
        local d = dx * dx + dy * dy
        if d < best_d then
            best, best_d = b, d
        end
    end
    return best
end

local function shot_free()
    if P.st == "dead" or (P.stun or 0) > 0 then return false end
    if P.weapon == "vulcan" then
        return (P.vcool or 0) <= 0 and #SHOTS < 8
    end
    local cap = (P.weapon == "double") and 2 or 1
    return #ROPES < cap
end

local jev_target, wire_outcome
jev_target, wire_outcome = (function()
-- Beside the body. Stepping against the balloon's vx so it does not chase us into the wall.
local function escape_x(b)
    local safe = b.r * HB.ball_k + HB.pw + 0.45
    local dir = 1
    if b.vx > 0.4 then dir = -1 elseif b.vx < -0.4 then dir = 1
    else dir = ((X1 - b.x) >= (b.x - X0)) and 1 or -1 end
    if P.x > b.x + 0.35 then dir = 1 elseif P.x < b.x - 0.35 then dir = -1 end
    local side = b.x + dir * safe
    if side < X0 + PHW or side > X1 - PHW then dir = -dir end
    return clamp(b.x + dir * safe, X0 + PHW, X1 - PHW)
end

local function copy_balls()
    local out = {}
    for i, b in ipairs(BALLS) do
        out[i] = { x = b.x, y = b.y, vx = b.vx, vy = b.vy, r = b.r, size = b.size }
    end
    return out
end

local function step_copy(b, dt)
    b.vy = b.vy - GRAV * dt
    b.x = b.x + b.vx * dt
    b.y = b.y + b.vy * dt
    local r = b.r
    if b.x - r < X0 then b.x = X0 + r; b.vx = abs(b.vx) end
    if b.x + r > X1 then b.x = X1 - r; b.vx = -abs(b.vx) end
    if b.y + r > CEIL then b.y = CEIL - r; b.vy = -abs(b.vy) end
    if b.y - r < 0 then b.y = r; b.vy = BV[b.size] end
    for _, k in ipairs(ST.blocks) do
        if k.live then
            local px, py = clamp(b.x, k.x0, k.x1), clamp(b.y, k.y0, k.y1)
            local dx, dy = b.x - px, b.y - py
            if dx * dx + dy * dy < r * r then
                if abs(dy) >= abs(dx) then
                    if dy > 0 or (dy == 0 and b.y > (k.y0 + k.y1) / 2) then b.y = k.y1 + r; b.vy = BV[b.size]
                    else b.y = k.y0 - r; b.vy = -abs(b.vy) end
                else
                    if dx > 0 then b.x = k.x1 + r; b.vx = abs(b.vx) else b.x = k.x0 - r; b.vx = -abs(b.vx) end
                end
            end
        end
    end
end

local function body_hit(px, b)
    return circ_box(b.x, b.y, b.r * HB.ball_k, px - HB.pw, P.y + HB.py0, px + HB.pw, P.y + HB.py1)
end

local function rope_touch(x, y0, tip, b)
    local cy = clamp(b.y, y0, tip)
    local dx, dy = b.x - x, b.y - cy
    local rad = b.r + HB.rope
    return dx * dx + dy * dy < rad * rad
end

local function wire_blocked(x, y0, tip)
    for _, k in ipairs(ST.blocks) do
        if k.live and x > k.x0 - 0.05 and x < k.x1 + 0.05 and y0 < k.y0 and tip >= k.y0 then return true end
    end
    return false
end

local function walk_x(x, dir, dt)
    local nx = clamp(x + dir * PW * dt, X0 + PHW, X1 - PHW)
    if dir == 0 then return x end
    for _, k in ipairs(ST.blocks) do
        if k.live and k.y0 < P.y + PH - 0.2 and k.y1 > P.y + 0.15 then
            if dir > 0 and x + PHW <= k.x0 + 0.01 and nx + PHW > k.x0 then return k.x0 - PHW end
            if dir < 0 and x - PHW >= k.x1 - 0.01 and nx - PHW < k.x1 then return k.x1 + PHW end
        end
    end
    return nx
end

-- Walk to stand, then fire. A miss keeps the wire out until the ceiling, so a plan that
-- does not hit is not a shot. Also reject a walk the balloon would land on.
local function wire_outcome(stand, t_fire)
    local balls = copy_balls()
    local t, px = 0, P.x
    local dir = stand > P.x + 0.01 and 1 or (stand < P.x - 0.01 and -1 or 0)
    while t < t_fire do
        local step = min(FR, t_fire - t)
        px = walk_x(px, dir, step)
        for _, b in ipairs(balls) do
            step_copy(b, step)
            if body_hit(px, b) then return false, t + step end
        end
        t = t + step
    end
    if abs(px - stand) > 0.45 then return false, t end
    local y0, tip0 = P.y, P.y + 1.8
    local flight = (CEIL - tip0) / WIRE_V
    if flight < 0.02 then return false, t end
    local fired = 0
    while fired < flight do
        local step = min(FR, flight - fired)
        fired = fired + step
        local tip = min(CEIL, tip0 + WIRE_V * fired)
        local blocked = wire_blocked(stand, y0, tip)
        for _, b in ipairs(balls) do
            step_copy(b, step)
            if body_hit(stand, b) then return false, t + fired end
            if not blocked and rope_touch(stand, y0, tip, b) then return true, t + fired end
        end
        if blocked then return false, t + fired end
    end
    return false, t + flight
end

-- Remaining time of a wire already in the air, and whether it still hits a balloon.
local function rope_time(r)
    if r.st ~= "rise" then return r.t or 0, true end
    local balls = copy_balls()
    local tip, t = r.tip, 0
    while tip < CEIL - 0.05 and t < 2 do
        local step = min(FR, (CEIL - tip) / WIRE_V)
        if step < 1e-4 then break end
        t = t + step
        tip = min(CEIL, tip + WIRE_V * step)
        local blocked = wire_blocked(r.x, r.y0, tip)
        for _, b in ipairs(balls) do
            step_copy(b, step)
            if not blocked and rope_touch(r.x, r.y0, tip, b) then return t, true end
        end
        if blocked then return t, false end
    end
    return t, false
end

local function miss_flight()
    local flight = (CEIL - (P.y + 1.8)) / WIRE_V
    if flight < 0.2 then flight = 0.2 end
    return flight
end

-- Safe x for the whole lock. A miss lasts until the ceiling, so look that far ahead.
local function avoid_x(duration, why)
    local balls = copy_balls()
    local threat, gap, t = nil, 1e18, 0
    while t < duration do
        local step = min(FR, duration - t)
        for _, b in ipairs(balls) do
            step_copy(b, step)
            if b.y - b.r * HB.ball_k < P.y + HB.py1 + 0.4 and b.y + b.r * HB.ball_k > P.y + HB.py0 then
                local g = abs(b.x - P.x)
                if g < gap then
                    gap = g
                    threat = { x = b.x, vx = b.vx, r = b.r }
                end
            end
        end
        t = t + step
    end
    if threat then return escape_x(threat), false, why end
    local near = nearest_balloon()
    if not near then return P.x, false, "none" end
    return escape_x(near), false, why
end

local function best_stand()
    local hit = wire_outcome(P.x, 0)
    if hit then return P.x end
    local balls = copy_balls()
    local tip0 = P.y + 1.8
    local flight_max = (CEIL - tip0) / WIRE_V
    local tries, best_x, best_t, t = {}, nil, 1e18, 0
    while t < 1.4 do
        for _, b in ipairs(balls) do step_copy(b, FR) end
        t = t + FR
        for i, b in ipairs(balls) do
            if (tries[i] or 0) < 2 then
                local flight = (b.y - tip0) / WIRE_V
                if flight > 0.05 and flight < flight_max - 0.03 then
                    local t_fire = t - flight
                    if t_fire < 0 then t_fire = 0 end
                    local stand = clamp(b.x, X0 + PHW, X1 - PHW)
                    if abs(stand - P.x) / PW <= t_fire + 0.03 then
                        tries[i] = (tries[i] or 0) + 1
                        local ok, tw = wire_outcome(stand, t_fire)
                        if ok and tw < best_t then best_x, best_t = stand, tw end
                    end
                end
            end
        end
    end
    return best_x
end

local function span(l)
    if l.y1 >= l.y0 then return l.y0, l.y1 end
    return l.y1, l.y0
end

local function wall_between(x0, x1, y)
    local a, b = min(x0, x1), max(x0, x1)
    for _, k in ipairs(ST.blocks) do
        if k.live and k.y0 < y + PH - 0.2 and k.y1 > y + 0.15 then
            if k.x0 < b - 0.15 and k.x1 > a + 0.15 then return true end
        end
    end
    return false
end

local function crab_x_at(a, t)
    local x, vx = a.x, a.vx
    local left, right = X0 + 1, X1 - 1
    local remain, guard = t, 0
    while remain > 1e-4 and guard < 8 do
        guard = guard + 1
        if vx > 0.01 then
            local dt = (right - x) / vx
            if dt >= remain then return x + vx * remain end
            x, vx, remain = right, -abs(vx), remain - dt
        elseif vx < -0.01 then
            local dt = (x - left) / -vx
            if dt >= remain then return x + vx * remain end
            x, vx, remain = left, abs(vx), remain - dt
        else
            return x
        end
    end
    return x
end

-- A crab stuns on the ground. Step to the open side, or climb if one is underfoot.
local function creep_plan()
    if P.st == "climb" and P.ladder and P.ladder.y1 >= 1.2 and P.y < 1.05 then return P.ladder.x, 1 end
    if (P.inv or 0) > 0.15 or P.y >= 1.05 or P.st == "dead" then return nil end
    local best, bt
    for _, a in ipairs(ANIMALS) do
        if a.kind == "crab" and a.st ~= "hit" then
            local t = 0
            while t <= 0.85 do
                if abs(crab_x_at(a, t) - P.x) < 1.25 then
                    if not best or t < bt then best, bt = a, t end
                    break
                end
                t = t + 0.05
            end
        end
    end
    if not best then return nil end
    local away = best.x >= P.x and -1 or 1
    local dest = clamp(P.x + away * 4.5, X0 + PHW, X1 - PHW)
    if abs(dest - P.x) < 0.4 then
        away = -away
        dest = clamp(P.x + away * 4.5, X0 + PHW, X1 - PHW)
    end
    if bt < 0.5 then
        for _, l in ipairs(ST.ladders) do
            local foot, top = span(l)
            if abs(l.x - P.x) < 0.8 and abs(P.y - foot) < 0.45 and top >= 1.2 and not wall_between(P.x, l.x, P.y) then
                return l.x, 1
            end
        end
    end
    return dest, 0
end

local function balloon_clear(x, y)
    for _, b in ipairs(BALLS) do
        if b.y - b.r < y + HB.py1 and b.y + b.r > y + HB.py0 and abs(b.x - x) < b.r * HB.ball_k + HB.pw + 0.3 then
            return false
        end
    end
    return true
end

local function crab_hits(x, y, within)
    if y >= 1 then return false end
    for _, a in ipairs(ANIMALS) do
        if a.kind == "crab" and a.st ~= "hit" then
            local t = 0
            while t <= within do
                if abs(crab_x_at(a, t) - x) < 1.2 then return true end
                t = t + 0.1
            end
        end
    end
    return false
end

local function ladder_between(item_y)
    local best, bd
    for _, l in ipairs(ST.ladders) do
        local foot, top = span(l)
        if P.y >= foot - 0.45 and P.y <= top + 0.45 and item_y >= foot - 0.5 and item_y <= top + 0.5 then
            local d = abs(l.x - P.x)
            if not best or d < bd then best, bd = l, d end
        end
    end
    return best
end

local function pickup_plan()
    local aim, why, v, score = nil, nil, 0, -1e18
    for _, it in ipairs(ITEMS) do
        local life = 7 - (it.t or 0)
        if life > 0.4 then
            local fruit = it.kind == "fruit"
            local worth = fruit and 2 or 5
            if it.kind == "life" then worth = 8 end
            local iy = it.y
            if not it.landed then iy = support_at(it.x, it.y, 0.3, 0.4, 40) or 0 end
            local same = abs(iy - P.y) < 0.8
            local safe = balloon_clear(it.x, iy) and balloon_clear((P.x + it.x) / 2, P.y)
            if same and not wall_between(P.x, it.x, P.y) and not crab_hits(it.x, iy, 0.7) and safe then
                local s = worth * 12 - abs(it.x - P.x) + life
                if s > score then aim, why, v, score = it.x, fruit and "fruit" or "item", 0, s end
            else
                local lad = ladder_between(iy)
                if lad and not wall_between(P.x, lad.x, P.y) and not crab_hits(lad.x, P.y, 0.6) and balloon_clear(lad.x, P.y) then
                    local s = worth * 8 - abs(lad.x - P.x) - abs(iy - P.y) + life
                    if s > score then
                        local on = abs(P.x - lad.x) < 0.55 or P.st == "climb"
                        local dir = 0
                        if on then
                            if iy > P.y + 0.3 then dir = 1 elseif iy < P.y - 0.3 then dir = -1 end
                        end
                        local x = (abs(iy - P.y) < 0.8) and it.x or lad.x
                        aim, why, v, score = x, fruit and "fruit" or "item", dir, s
                    end
                end
            end
        end
    end
    if aim then return aim, why, v end
end

local function route_around(x, can, why, v)
    if (v or 0) ~= 0 then return x, can, why, v end
    if not wall_between(P.x, x, P.y) then return x, can, why, v end
    local lad, best
    for _, l in ipairs(ST.ladders) do
        local foot, top = span(l)
        if abs(P.y - foot) < 0.5 and top > P.y + 1.2 and not wall_between(P.x, l.x, P.y) then
            local d = abs(l.x - x)
            if not lad or d < best then lad, best = l, d end
        end
    end
    if not lad then return x, can, why, v end
    local dir = 0
    if abs(P.x - lad.x) < 0.55 or P.st == "climb" then dir = 1 end
    return lad.x, false, "route", dir
end

local function field_plan(x, can, why)
    local cx, cv = creep_plan()
    if cx then return route_around(cx, false, "creep", cv) end
    local shooting = can and abs(x - P.x) <= 0.5
    local px, pwhy, pv = pickup_plan()
    if px and not shooting and (not can or abs(px - P.x) + 0.4 < abs(x - P.x)) then
        return route_around(px, false, pwhy, pv)
    end
    return route_around(x, can, why, 0)
end

local function jev_target()
    local cache = G._jev_cache
    if cache and cache.t == G.t then return cache.b, cache.x, cache.can, cache.why, cache.v end
    local balloon = nearest_balloon()
    local x, can, why
    if not balloon then
        x, can, why = P.x, false, "none"
    elseif balloon.y <= balloon.r + HB.py1 then
        x, can, why = escape_x(balloon), false, "low"
    elseif not shot_free() then
        local remain, will_hit = 0, true
        for _, r in ipairs(ROPES) do
            local rt, rh = rope_time(r)
            if rt > remain then remain, will_hit = rt, rh end
        end
        if remain < 0.15 then remain = 0.15 end
        why = will_hit and "busy" or "miss"
        x, can = avoid_x(remain, why)
        can = false
    else
        local stand = best_stand()
        if stand then
            x, can, why = stand, true, "shoot"
        else
            x, can, why = avoid_x(miss_flight(), "miss")
            can = false
        end
    end
    local v
    x, can, why, v = field_plan(x, can, why)
    v = v or 0
    G._jev_cache = { t = G.t, b = balloon, x = x, can = can, why = why, v = v }
    return balloon, x, can, why, v
end
return jev_target, wire_outcome
end)()

local jev_source = assert(fs.read("Scripts/jev_auto.lua"), "Missing Jev module: Scripts/jev_auto.lua")
local JevAuto = assert(load(jev_source, "@Scripts/jev_auto.lua", "t", _ENV))()
jev = JevAuto.attach({
    port = 9133,
    id = "pang-remix",
    description = "Pang Remix. One wire flies at a time, straight up. Fire only when the shot hits a balloon before the ceiling. A miss stays out until the ceiling, so stay clear of the balloon for that whole trip. A crab stuns you on the ground: step away, or climb a ladder off the floor. Climb ladders to fruit and power-ups. If a block walls the floor, climb around it. Prefer the higher action score.",
    playing = function()
        local state = G.state
        return state == "intro" or state == "play" or state == "clear"
    end,
    terminal = function()
        return G.state == "over"
    end,
    score = function()
        return G.score or 0
    end,
    -- No hop. Death and stun are not started by apply.
    busy = function()
        return false
    end,
    human_edge = function()
        return human_edged
    end,
    observe = function()
        local balloon = nearest_balloon()
        return {
            player_x = round2(P.x),
            player_y = round2(P.y),
            balloon_x = balloon and round2(balloon.x) or 0,
            balloon_y = balloon and round2(balloon.y) or 0,
            shot = shot_free(),
            wire = select(4, jev_target()),
            lives = G.lives or 0,
            score = G.score or 0,
        }
    end,
    actions = function()
        local balloon, aim, can, why = jev_target()
        local dx = aim - P.x
        local text
        if why == "creep" then
            text = "Step away from the crab. It stuns you on the ground."
        elseif why == "fruit" then
            text = "Pick up the fruit before it disappears. Climb the ladder when the fruit is above you."
        elseif why == "item" then
            text = "Climb the ladder or walk to the power-up."
        elseif why == "route" then
            text = "The floor is blocked. Climb the ladder and go around."
        elseif not balloon then
            text = "No balloon. Hold."
        elseif can then
            text = "Step onto the shot line. This wire hits the balloon before the ceiling."
        elseif why == "miss" then
            text = "Stay clear. This shot misses, so the wire stays out until the ceiling."
        elseif why == "busy" then
            text = "Stay beside the balloon. The wire is already out."
        elseif why == "low" then
            text = "Stay beside the balloon. It is too low for the wire to hit above you."
        else
            text = "Stay beside the balloon. You cannot reach a shot that hits."
        end
        if dx > 0.3 then
            return { { id = "right", description = text, score = dx } }
        end
        if dx < -0.3 then
            return { { id = "left", description = text, score = -dx } }
        end
        return { { id = "stop", description = text, score = 1 } }
    end,
    apply = function(id)
        if id ~= "left" and id ~= "right" and id ~= "up" and id ~= "down" and id ~= "stop" then
            return
        end

        clear_hold()
        -- Hold the aim point. A held Left key keeps walking after the balloon has
        -- been passed and pins Jev in the left wall until the next reply.
        if id == "left" or id == "right" or id == "stop" then
            local _, aim = jev_target()
            G.jev_x = aim
        elseif id == "up" then
            G.vk.Up = true
        elseif id == "down" then
            G.vk.Down = true
        end
    end,
    reset = function(seed)
        math.randomseed(seed)
        clear_hold()
        new_game(1)
    end,
    on_human = function()
        clear_hold()
    end,
})

SET.opts.on_change = function(id, value)
    if id ~= "jev" then return end
    local on = value and true or false
    if on then
        local live = G.state == "intro" or G.state == "play" or G.state == "pause" or G.state == "clear"
        local ok, err
        if live then ok, err = jev:engage() else ok, err = jev:start() end
        if not ok then
            SET.cfg.jev = false
            G.jev_err = err or jev:error() or "Jev could not start"
            pe_log("[PG] " .. G.jev_err)
            if not live then to_title() end
        else
            G.jev_err = nil
            SET.cfg.jev = true
            if live then G.jev_x = P.x end
        end
    else
        jev:begin_human()
        SET.cfg.jev = false
        G.jev_err = nil
    end
end

local acc = 0
G.fire_q = false
local mouse_prev = true
local function update(dt)
    if G.on_frame then G.on_frame(dt) end
    sample_human()
    jev:tick(dt)
    if P.weapon ~= "vulcan" and G.vk then
        G.vk.Space = nil
    end
    flush_mats()
    dt = min(dt, 0.1)
    G.t = G.t + dt; G.dt = dt
    local k = { ret = edge("Return"), space = edge("Space"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), q = edge("Q"),
        z = edge("Z"), j = edge("J"), f3 = edge("F3") }
    local md = false
    pcall(function() md = input.is_left_mouse_down() and true or false end)
    local mclick = md and not mouse_prev; mouse_prev = md
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end; mclick = false end
    local function open_settings()
        sfx("click")
        SET.cfg.jev = jev:assisted() and true or false
        SET:open()
        G.set_open = true
    end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        if k.ret or k.space or c.start then
            sfx("click")
            G.jev_err = nil
            jev:begin_human()
            new_game(1)
        elseif c.jev then
            sfx("click")
            G.jev_err = nil
            if not jev:start() then
                G.jev_err = jev:error() or "Jev could not start"
                pe_log("[PG] " .. G.jev_err)
                to_title()
            end
        elseif c.cont then
            sfx("click")
            G.jev_err = nil
            jev:begin_human()
            new_game(G.cont_stage)
        elseif k.o or c.set_t then
            open_settings()
        elseif c.quit_app then
            engine.quit()
        end
    elseif st == "intro" then
        G.intro_t = G.intro_t + dt
        if G.intro_t > 2.2 or ((k.ret or k.space or mclick) and G.intro_t > 0.4) then
            G.state = "play"; music("bgm" .. ((ST.def.loc - 1) % 4 + 1)); G.fire_q = false
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
        if G.clear_t > 3.0 or ((k.ret or k.space) and G.clear_t > 0.8) then
            if ST.n >= 50 then game_over(true) else start_stage(ST.n + 1) end
        end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then
                sfx("click")
                G.jev_err = nil
                jev:begin_human()
                new_game(1)
            elseif k.esc or c.title then
                to_title()
            end
        end
    end
    if G.set_open then
        local want = SET:get("jev") and true or false
        if want ~= (jev:assisted() and true or false) then SET.opts.on_change("jev", want) end
    end
    st = G.state
    local running = (st == "play" or st == "title") and not (G.set_open and st ~= "title")
    if running then
        if st == "play" and (k.space or k.z or k.j or mclick or G.fire_pulse) then
            G.fire_q = true
            G.fire_pulse = false
        end
        local h = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0)
        local climb = 0
        if st == "play" and G.jev_x and jev:assisted() then
            local _, aim, can, _, v = jev_target()
            climb = v or 0
            if climb == 0 and P.st == "climb" and P.ladder then
                local l = P.ladder
                climb = (P.y - l.y0) <= (l.y1 - P.y) and -1 or 1
            end
            G.jev_x = aim
            local hit_now = can and wire_outcome(P.x, 0)
            if hit_now then
                if P.weapon == "vulcan" then G.vk.Space = true else G.fire_q = true end
            elseif G.vk then
                G.vk.Space = nil
            end
            local dx = G.jev_x - P.x
            if dx > 0.3 then h = 1 elseif dx < -0.3 then h = -1 else h = 0 end
        end
        local vkey = (any("Up", "W") and 1 or 0) - (any("Down", "S") and 1 or 0)
        if st == "play" and G.jev_x and jev:assisted() then vkey = climb end
        local inp = { h = h, v = vkey,
            fire = false, fire_held = any("Space", "Z", "J") or md }
        if st ~= "play" then inp.h, inp.v, inp.fire_held = 0, 0, false end
        if G.autoplay and st == "play" then   -- debug bot (tests / screenshots only)
            local tb, bd = nil, 1e9
            for _, b in ipairs(BALLS) do local d = abs(b.x - P.x) + b.y * 0.2; if d < bd then bd, tb = d, b end end
            if tb then local dx = tb.x - (P.x + tb.vx * 0.25); inp.h = abs(dx) > 0.4 and (dx > 0 and 1 or -1) or 0 end
            G.fire_q = true; inp.fire_held = true
        end
        local god = G.god
        if st == "title" then G.god = true; G.time = 99; P.x = -100 end
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 6 do
            inp.fire = G.fire_q; G.fire_q = false
            G.stage_step(inp, FR)
            acc = acc - FR; n = n + 1
            if st == "play" and #BALLS == 0 and P.st ~= "dead" then
                G.state = "clear"; G.clear_t = 0
                G.tbonus = floor(G.time) * 100; add_score(G.tbonus)
                G.cont_stage = max(G.cont_stage, min(50, ST.n + 1))
                music(nil); sfx("clear"); G.clear_all()
                break
            end
        end
        if st == "title" then G.god = god; if #BALLS == 0 then G.stage_reset(1 + floor(rand() * 9)) end end
        if acc > FR * 6 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if st == "play" and P.st == "dead" and P.dead_t >= 2.6 then
            G.lives = G.lives - 1
            if G.lives <= 0 then game_over(false) else start_stage(ST.n) end
        end
    else AL = 1 end
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
to_title()
G.update = update; G.SET = SET; G.surf = surf
hooks { update = update }
pe_log("[PG] ready")
