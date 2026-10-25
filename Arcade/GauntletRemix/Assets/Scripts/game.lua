-- GAUNTLET REMIX  (PhasmaEngine, Lua)
-- A faithful modern remake of Atari's Gauntlet (1985): pick Thor the Warrior, Thyra the Valkyrie, Merlin the Wizard or
-- Questor the Elf and fight down through the dungeon. Health drains over time; food restores it; keys open doors;
-- potions destroy everything on screen; generators keep spawning ghosts, grunts, demons, lobbers and sorcerers.
-- Logic coords: x east, y north, 1 unit = 1 cell. WP maps to world (camera looks north, so world X is mirrored).
local PI = math.pi
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
math.randomseed(os and os.time and os.time() or 1942)
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local G = { state = "boot", t = 0 }
_G.GT = G

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
local ss = scene.add_empty_node("GauntletSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "night.hdr")
S("hdr", false); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false); S("dof", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.2)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", false)
S("color_grading", true); S("color_grading_saturation", 1.05); S("color_grading_contrast", 1.04)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "SETTINGS", subtitle = "Gauntlet Remix", file = "Save/settings.cfg", music = true,
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
    if not n then pe_log("[GT] missing template " .. name); return nil end
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
    wall = { { .6, .6, .6 }, { 0, 0, 0 }, .9 }, floor = { { .5, .5, .5 }, { 0, 0, 0 }, .9 }, shadow = { { .01, .01, .01 }, { 0, 0, 0 }, 1 },
    door = { { .55, .5, .45 }, { 0, 0, 0 }, .4, .8 }, exit = { { .03, .03, .04 }, { 0, 0, 0 }, 1 }, exit_steps = { { .45, .42, .4 }, { .06, .05, .03 }, .8 },
    key = { { 1, .8, .3 }, { .25, .18, .04 }, .3, .6 }, food_plate = { { .85, .85, .8 }, { 0, 0, 0 }, .4 }, food_ham = { { .7, .35, .25 }, { .04, .01, 0 }, .5 },
    potion = { { .3, .45, 1 }, { .1, .15, .4 }, .15 }, potion_cork = { { .55, .4, .25 }, { 0, 0, 0 }, .8 },
    chest = { { .5, .3, .15 }, { 0, 0, 0 }, .7 }, chest_lid = { { .55, .33, .17 }, { 0, 0, 0 }, .7 }, chest_band = { { 1, .78, .3 }, { .15, .1, .02 }, .3, .6 },
    gen = { { .42, .4, .38 }, { 0, 0, 0 }, .85 }, gen_bones = { { .9, .88, .8 }, { .04, .04, .03 }, .6 },
    -- heroes and monsters: per-material palettes come from 02b_rigs.lua (gen_chars.py)
    p_axe = { { .75, .75, .8 }, { .05, .05, .05 }, .3, .6 }, p_sword = { { .8, .8, .85 }, { .08, .08, .1 }, .3, .6 },
    p_fire = { { 1, .7, .3 }, { 1.4, .7, .2 }, .5 }, p_arrow = { { .7, .55, .3 }, { .05, .04, .02 }, .5 }, p_rock = { { .5, .48, .45 }, { 0, 0, 0 }, .9 },
    p_dfire = { { 1, .4, .2 }, { 1.4, .35, .1 }, .5 },
}
local function paint_templates()
    -- every floor has its own wall/floor texture and tint (see tools/levels.py), so the dungeon changes as you descend
    for i, L in ipairs(G.LEVELS) do
        PAL["lv" .. i .. "_wall"] = { L.wc or { 1, 1, 1 }, { 0, 0, 0 }, .85 }; PAL["lv" .. i .. "_floor"] = { L.fc or { .85, .85, .85 }, { 0, 0, 0 }, .9 }
        if L.trapw then PAL["lv" .. i .. "_trapw"] = PAL["lv" .. i .. "_wall"] end
    end
    PAL.trap_tile = { { 1, 1, 1 }, { 0, 0, 0 }, .45, .5 }; PAL.stun_tile = { { 1, 1, 1 }, { .05, .05, .02 }, .5, .3 }
    PAL.exit_rim = { { 1, .78, .35 }, { .12, .08, .02 }, .35, .7 }
    for name, v in pairs(PAL) do paint(tnode(name), v[1], v[2], v[3], v[4]) end
    for i, L in ipairs(G.LEVELS) do
        local wt, ft = L.wt or ((i - 1) % 4), L.ft or ((i - 1) % 4)
        mtex(tnode("lv" .. i .. "_wall"), "base_color", "Textures/wall" .. wt .. ".png")
        if L.trapw then mtex(tnode("lv" .. i .. "_trapw"), "base_color", "Textures/wall" .. wt .. ".png") end
        mtex(tnode("lv" .. i .. "_floor"), "base_color", "Textures/floor" .. ft .. ".png")
    end
    mtex(tnode("trap_tile"), "base_color", "Textures/trap_tile.png"); mtex(tnode("stun_tile"), "base_color", "Textures/stun_tile.png")
    for name in pairs(PAL) do local n = tnode(name); if n then n:set_position(HIDE) end end
end

------------------------------------------------------------------ lights: dim hall light plus the hero's torch
local LT = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(-0.3, -0.85, 0.45), vec3(0.85, 0.85, 1.0), 2.0)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    LT.torch = addp(HIDE, vec3(1.0, 0.75, 0.45), 55, 14)
    LT.fill = addp(HIDE, vec3(0.6, 0.7, 1.0), 14, 16)
    LT.flash = {}
    for i = 1, 4 do LT.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1 } end
end
G.flash_next = 1
local function flash(p, col, power, life, rad)
    local f = LT.flash[G.flash_next]; G.flash_next = G.flash_next % #LT.flash + 1
    f.t, f.life, f.p, f.col, f.power, f.rad = 0, life or 0.3, p, vec3(col[1], col[2], col[3]), power or 30, rad or 4
end
local function update_lights(dt, x, y)
    local fl = 1 + 0.06 * sin(G.t * 13) + 0.04 * sin(G.t * 29)
    set_point(LT.torch, WP(x, y, 2.4), vec3(1.0, 0.75, 0.45), 55 * fl, 14)
    set_point(LT.fill, WP(x + 3, y + 5, 5), vec3(0.6, 0.7, 1.0), 14, 16)
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
local function puff(p, col, n)          -- kills, spawns, impacts: a coloured smoke puff with a few motes
    col = col or { .7, .7, .75 }
    local k = clamp((n or 14) / 14, 0.5, 2)
    G.FX.emit("smoke", p.x, p.y, p.z, { n = 2 * k, c0 = { col[1] * .55, col[2] * .55, col[3] * .55 }, c1 = { 0, 0, 0 }, s0 = .9, s1 = 1.6,
        l0 = .45, l1 = .9, r = .4, sp = 1.5, drag = 2, grav = { 0, 1.5, 0 } })
    G.FX.emit("ember", p.x, p.y, p.z, { n = 4 * k, c0 = { col[1] * 1.3, col[2] * 1.3, col[3] * 1.3 }, c1 = { 0, 0, 0 }, s0 = .12, s1 = .25,
        l0 = .25, l1 = .6, r = .5, sp = 6, drag = 2, grav = { 0, 2, 0 } })
end
local function sparks(p, n, col)
    G.FX.sparks(p.x, p.y, p.z, max(4, (n or 8) * 1.4), nil, 8)
end
local function boom(p, big)             -- generator destroyed / smart bomb: the shared explosion preset
    G.FX.explosion(p.x, p.y, p.z, big and 3.5 or 1.6, nil, { .45, .4, .35 })
    flash(p, { 1, .7, .4 }, big and 120 or 25, big and 0.8 or 0.25, big and 14 or 4)
end
local function dust(p, n)
    G.FX.dust(p.x, p.y, p.z, { .5, .45, .37 }, clamp((n or 8) / 8, 0.3, 1.6), { 0, .3, 0 }, 0.8)
end
local MUZ = { war = { 1.5, 1.3, 1.0 }, val = { 1.2, 1.35, 1.7 }, wiz = { 1.7, .9, 2.1 }, elf = { 1.1, 1.6, .8 } }
local function muzzle(p, id)
    local c = MUZ[id] or MUZ.war
    G.FX.emit("ember", p.x, p.y, p.z, { n = id == "wiz" and 10 or 5, c0 = c, c1 = { 0, 0, 0 }, s0 = .15, s1 = .3, l0 = .1, l1 = .25, r = .12, sp = 5, drag = 3 })
    G.FX.emit("soft", p.x, p.y, p.z, { n = 1, c0 = { c[1] * .5, c[2] * .5, c[3] * .5 }, c1 = { 0, 0, 0 }, s0 = 1.0, s1 = 1.2, l0 = .07, l1 = .1, r = 0, sp = 0, drag = 0 })
    if id == "wiz" then flash(p, { .8, .5, 1 }, 18, .18, 3) end
end
-- small per-frame trail puffs behind fireballs and magic (throttled by the particle setting)
local function trail(p, col, n)
    G.FX.emit("ember", p.x, p.y, p.z, { n = n or 2, c0 = col, c1 = { col[1] * .2, col[2] * .1, col[3] * .1 }, s0 = .1, s1 = .2,
        l0 = .15, l1 = .35, r = .06, sp = 1.5, drag = 2, grav = { 0, .6, 0 } })
end
G.dust, G.muzzle, G.trail = dust, muzzle, trail
------------------------------------------------------------------ score state
G.score, G.hiscore = 0, 0
pcall(function() local s = fs.read("Save/gauntlet_hiscore.txt"); if s then G.hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, "Save/gauntlet_hiscore.txt", tostring(G.hiscore)) end
local function add_score(n) G.score = G.score + n end
G.banner = { text = "", t = 0 }
function G.banner_set(t, d) G.banner.text = t; G.banner.t = d or 1.5 end
------------------------------------------------------------------ rigs (generated by tools/gen_chars.py, do not edit)
-- RIG[kind] = list of segments {name, pivot, meshes}; each mesh has its own material in PAL
local RIG = {
    war = {
        { name = "body", piv = { 0.0000, 0.0000, 0.0000 }, meshes = { "ch_war_body_skin", "ch_war_body_void", "ch_war_body_leather", "ch_war_body_gold", "ch_war_body_war_red", "ch_war_body_fur", "ch_war_body_steel", "ch_war_body_ivory", "ch_war_body_war_hair" } },
        { name = "leg_l", piv = { 0.0850, 0.3000, 0.0000 }, meshes = { "ch_war_leg_l_leather_dk", "ch_war_leg_l_leather", "ch_war_leg_l_fur" } },
        { name = "leg_r", piv = { -0.0850, 0.3000, 0.0000 }, meshes = { "ch_war_leg_r_leather_dk", "ch_war_leg_r_leather", "ch_war_leg_r_fur" } },
        { name = "arm_l", piv = { 0.2050, 0.5550, 0.0000 }, meshes = { "ch_war_arm_l_skin", "ch_war_arm_l_leather", "ch_war_arm_l_war_red", "ch_war_arm_l_steel", "ch_war_arm_l_gold" } },
        { name = "arm_r", piv = { -0.2050, 0.5550, 0.0000 }, meshes = { "ch_war_arm_r_skin", "ch_war_arm_r_leather", "ch_war_arm_r_war_red", "ch_war_arm_r_wood", "ch_war_arm_r_steel", "ch_war_arm_r_gold" } },
    },
    val = {
        { name = "body", piv = { 0.0000, 0.0000, 0.0000 }, meshes = { "ch_val_body_val_blue", "ch_val_body_val_armor", "ch_val_body_gold", "ch_val_body_skin", "ch_val_body_void", "ch_val_body_val_hair", "ch_val_body_steel", "ch_val_body_white" } },
        { name = "leg_l", piv = { 0.0850, 0.3000, 0.0000 }, meshes = { "ch_val_leg_l_skin", "ch_val_leg_l_leather", "ch_val_leg_l_steel" } },
        { name = "leg_r", piv = { -0.0850, 0.3000, 0.0000 }, meshes = { "ch_val_leg_r_skin", "ch_val_leg_r_leather", "ch_val_leg_r_steel" } },
        { name = "arm_l", piv = { 0.2050, 0.5550, 0.0000 }, meshes = { "ch_val_arm_l_skin", "ch_val_arm_l_val_armor", "ch_val_arm_l_val_blue", "ch_val_arm_l_gold" } },
        { name = "arm_r", piv = { -0.2050, 0.5550, 0.0000 }, meshes = { "ch_val_arm_r_skin", "ch_val_arm_r_val_armor", "ch_val_arm_r_steel", "ch_val_arm_r_gold", "ch_val_arm_r_leather" } },
    },
    wiz = {
        { name = "body", piv = { 0.0000, 0.0000, 0.0000 }, meshes = { "ch_wiz_body_wiz_robe", "ch_wiz_body_wiz_trim", "ch_wiz_body_gold", "ch_wiz_body_skin", "ch_wiz_body_void", "ch_wiz_body_beard" } },
        { name = "leg_l", piv = { 0.0850, 0.3000, 0.0000 }, meshes = { "ch_wiz_leg_l_wiz_trim" } },
        { name = "leg_r", piv = { -0.0850, 0.3000, 0.0000 }, meshes = { "ch_wiz_leg_r_wiz_trim" } },
        { name = "arm_l", piv = { 0.2050, 0.5550, 0.0000 }, meshes = { "ch_wiz_arm_l_wiz_robe", "ch_wiz_arm_l_wiz_trim", "ch_wiz_arm_l_skin" } },
        { name = "arm_r", piv = { -0.2050, 0.5550, 0.0000 }, meshes = { "ch_wiz_arm_r_wiz_robe", "ch_wiz_arm_r_wiz_trim", "ch_wiz_arm_r_skin", "ch_wiz_arm_r_wood", "ch_wiz_arm_r_orb", "ch_wiz_arm_r_gold" } },
    },
    elf = {
        { name = "body", piv = { 0.0000, 0.0000, 0.0000 }, meshes = { "ch_elf_body_elf_green", "ch_elf_body_leather", "ch_elf_body_gold", "ch_elf_body_feather", "ch_elf_body_wood", "ch_elf_body_skin", "ch_elf_body_void", "ch_elf_body_elf_hair", "ch_elf_body_elf_dkgreen" } },
        { name = "leg_l", piv = { 0.0850, 0.3000, 0.0000 }, meshes = { "ch_elf_leg_l_leather", "ch_elf_leg_l_leather_dk" } },
        { name = "leg_r", piv = { -0.0850, 0.3000, 0.0000 }, meshes = { "ch_elf_leg_r_leather", "ch_elf_leg_r_leather_dk" } },
        { name = "arm_l", piv = { 0.2050, 0.5550, 0.0000 }, meshes = { "ch_elf_arm_l_elf_green", "ch_elf_arm_l_skin", "ch_elf_arm_l_leather", "ch_elf_arm_l_wood", "ch_elf_arm_l_white" } },
        { name = "arm_r", piv = { -0.2050, 0.5550, 0.0000 }, meshes = { "ch_elf_arm_r_elf_green", "ch_elf_arm_r_skin", "ch_elf_arm_r_leather" } },
    },
    ghost = {
        { name = "body", piv = { 0.0000, 0.0000, 0.0000 }, meshes = { "ch_ghost_body_ghost", "ch_ghost_body_void", "ch_ghost_body_eye_green" } },
        { name = "arm_l", piv = { 0.1600, 0.5000, 0.0200 }, meshes = { "ch_ghost_arm_l_ghost" } },
        { name = "arm_r", piv = { -0.1600, 0.5000, 0.0200 }, meshes = { "ch_ghost_arm_r_ghost" } },
    },
    grunt = {
        { name = "body", piv = { 0.0000, 0.0000, 0.0000 }, meshes = { "ch_grunt_body_grunt_skin", "ch_grunt_body_grunt_cloth", "ch_grunt_body_bronze", "ch_grunt_body_ivory", "ch_grunt_body_horn", "ch_grunt_body_eye_red" } },
        { name = "leg_l", piv = { 0.1000, 0.2400, 0.0000 }, meshes = { "ch_grunt_leg_l_grunt_skin", "ch_grunt_leg_l_claw" } },
        { name = "leg_r", piv = { -0.1000, 0.2400, 0.0000 }, meshes = { "ch_grunt_leg_r_grunt_skin", "ch_grunt_leg_r_claw" } },
        { name = "arm_l", piv = { 0.2200, 0.4800, 0.0200 }, meshes = { "ch_grunt_arm_l_grunt_skin", "ch_grunt_arm_l_leather" } },
        { name = "arm_r", piv = { -0.2200, 0.4800, 0.0200 }, meshes = { "ch_grunt_arm_r_grunt_skin", "ch_grunt_arm_r_leather", "ch_grunt_arm_r_wood", "ch_grunt_arm_r_steel_dk" } },
    },
    demon = {
        { name = "body", piv = { 0.0000, 0.0000, 0.0000 }, meshes = { "ch_demon_body_demon_skin", "ch_demon_body_horn", "ch_demon_body_eye_yel", "ch_demon_body_void" } },
        { name = "leg_l", piv = { 0.0900, 0.2700, 0.0000 }, meshes = { "ch_demon_leg_l_demon_skin", "ch_demon_leg_l_claw" } },
        { name = "leg_r", piv = { -0.0900, 0.2700, 0.0000 }, meshes = { "ch_demon_leg_r_demon_skin", "ch_demon_leg_r_claw" } },
        { name = "arm_l", piv = { 0.1900, 0.5300, 0.0000 }, meshes = { "ch_demon_arm_l_demon_skin", "ch_demon_arm_l_claw" } },
        { name = "arm_r", piv = { -0.1900, 0.5300, 0.0000 }, meshes = { "ch_demon_arm_r_demon_skin", "ch_demon_arm_r_claw" } },
        { name = "wing_l", piv = { 0.0700, 0.5200, -0.0900 }, meshes = { "ch_demon_wing_l_horn", "ch_demon_wing_l_demon_wing" } },
        { name = "wing_r", piv = { -0.0700, 0.5200, -0.0900 }, meshes = { "ch_demon_wing_r_horn", "ch_demon_wing_r_demon_wing" } },
    },
    lobber = {
        { name = "body", piv = { 0.0000, 0.0000, 0.0000 }, meshes = { "ch_lobber_body_lob_skin", "ch_lobber_body_grunt_cloth", "ch_lobber_body_sack", "ch_lobber_body_leather", "ch_lobber_body_eye_yel" } },
        { name = "leg_l", piv = { 0.0700, 0.1700, 0.0000 }, meshes = { "ch_lobber_leg_l_lob_skin" } },
        { name = "leg_r", piv = { -0.0700, 0.1700, 0.0000 }, meshes = { "ch_lobber_leg_r_lob_skin" } },
        { name = "arm_l", piv = { 0.1500, 0.3600, 0.0500 }, meshes = { "ch_lobber_arm_l_lob_skin" } },
        { name = "arm_r", piv = { -0.1500, 0.3600, 0.0500 }, meshes = { "ch_lobber_arm_r_lob_skin", "ch_lobber_arm_r_rock" } },
    },
    sorc = {
        { name = "body", piv = { 0.0000, 0.0000, 0.0000 }, meshes = { "ch_sorc_body_sorc_robe", "ch_sorc_body_sorc_dk", "ch_sorc_body_gold", "ch_sorc_body_eye_red" } },
        { name = "arm_l", piv = { 0.1800, 0.5500, 0.0000 }, meshes = { "ch_sorc_arm_l_sorc_robe", "ch_sorc_arm_l_gold", "ch_sorc_arm_l_skin_dk", "ch_sorc_arm_l_magic" } },
        { name = "arm_r", piv = { -0.1800, 0.5500, 0.0000 }, meshes = { "ch_sorc_arm_r_sorc_robe", "ch_sorc_arm_r_gold", "ch_sorc_arm_r_skin_dk", "ch_sorc_arm_r_magic" } },
    },
    death = {
        { name = "body", piv = { 0.0000, 0.0000, 0.0000 }, meshes = { "ch_death_body_death_robe", "ch_death_body_void", "ch_death_body_bone", "ch_death_body_eye_red" } },
        { name = "arm_l", piv = { 0.2000, 0.6000, 0.0000 }, meshes = { "ch_death_arm_l_death_robe", "ch_death_arm_l_bone" } },
        { name = "arm_r", piv = { -0.2000, 0.6000, 0.0000 }, meshes = { "ch_death_arm_r_death_robe", "ch_death_arm_r_bone", "ch_death_arm_r_wood", "ch_death_arm_r_steel" } },
    },
}
local RMAT = {
    skin = { { 0.860, 0.620, 0.480 }, { 0.020, 0.010, 0.000 }, 0.55, 0.00 },
    skin_dk = { { 0.660, 0.440, 0.320 }, { 0.000, 0.000, 0.000 }, 0.60, 0.00 },
    steel = { { 0.780, 0.790, 0.840 }, { 0.050, 0.050, 0.060 }, 0.30, 0.30 },
    steel_dk = { { 0.420, 0.430, 0.470 }, { 0.010, 0.010, 0.010 }, 0.38, 0.30 },
    gold = { { 1.000, 0.780, 0.340 }, { 0.120, 0.080, 0.020 }, 0.30, 0.45 },
    bronze = { { 0.780, 0.520, 0.300 }, { 0.040, 0.020, 0.000 }, 0.35, 0.35 },
    leather = { { 0.420, 0.260, 0.140 }, { 0.000, 0.000, 0.000 }, 0.70, 0.00 },
    leather_dk = { { 0.240, 0.150, 0.090 }, { 0.000, 0.000, 0.000 }, 0.75, 0.00 },
    fur = { { 0.550, 0.400, 0.260 }, { 0.000, 0.000, 0.000 }, 0.95, 0.00 },
    wood = { { 0.500, 0.330, 0.180 }, { 0.000, 0.000, 0.000 }, 0.75, 0.00 },
    ivory = { { 0.930, 0.900, 0.800 }, { 0.030, 0.030, 0.020 }, 0.50, 0.00 },
    war_red = { { 0.720, 0.120, 0.080 }, { 0.030, 0.000, 0.000 }, 0.65, 0.00 },
    war_hair = { { 0.550, 0.220, 0.080 }, { 0.000, 0.000, 0.000 }, 0.80, 0.00 },
    val_blue = { { 0.160, 0.300, 0.820 }, { 0.000, 0.010, 0.040 }, 0.55, 0.00 },
    val_armor = { { 0.680, 0.760, 0.950 }, { 0.030, 0.040, 0.070 }, 0.30, 0.30 },
    val_hair = { { 1.000, 0.820, 0.380 }, { 0.050, 0.040, 0.010 }, 0.60, 0.00 },
    white = { { 0.920, 0.920, 0.900 }, { 0.030, 0.030, 0.030 }, 0.60, 0.00 },
    wiz_robe = { { 0.900, 0.720, 0.160 }, { 0.040, 0.030, 0.000 }, 0.70, 0.00 },
    wiz_trim = { { 0.600, 0.200, 0.100 }, { 0.000, 0.000, 0.000 }, 0.60, 0.00 },
    beard = { { 0.930, 0.930, 0.930 }, { 0.050, 0.050, 0.050 }, 0.80, 0.00 },
    orb = { { 0.600, 0.800, 1.000 }, { 1.200, 1.600, 2.400 }, 0.20, 0.00 },
    elf_green = { { 0.200, 0.580, 0.220 }, { 0.000, 0.015, 0.000 }, 0.65, 0.00 },
    elf_dkgreen = { { 0.100, 0.320, 0.140 }, { 0.000, 0.000, 0.000 }, 0.70, 0.00 },
    elf_hair = { { 0.850, 0.600, 0.250 }, { 0.020, 0.010, 0.000 }, 0.70, 0.00 },
    feather = { { 0.850, 0.150, 0.100 }, { 0.040, 0.000, 0.000 }, 0.60, 0.00 },
    ghost = { { 0.780, 0.800, 0.880 }, { 0.100, 0.110, 0.140 }, 0.60, 0.00 },
    void = { { 0.020, 0.020, 0.030 }, { 0.000, 0.000, 0.000 }, 0.90, 0.00 },
    grunt_skin = { { 0.450, 0.520, 0.300 }, { 0.000, 0.000, 0.000 }, 0.70, 0.00 },
    grunt_cloth = { { 0.450, 0.300, 0.180 }, { 0.000, 0.000, 0.000 }, 0.85, 0.00 },
    demon_skin = { { 0.620, 0.180, 0.120 }, { 0.030, 0.000, 0.000 }, 0.55, 0.00 },
    demon_wing = { { 0.300, 0.100, 0.090 }, { 0.010, 0.000, 0.000 }, 0.70, 0.00 },
    horn = { { 0.300, 0.260, 0.220 }, { 0.000, 0.000, 0.000 }, 0.45, 0.10 },
    claw = { { 0.900, 0.860, 0.740 }, { 0.000, 0.000, 0.000 }, 0.40, 0.00 },
    lob_skin = { { 0.660, 0.560, 0.360 }, { 0.000, 0.000, 0.000 }, 0.70, 0.00 },
    sack = { { 0.580, 0.480, 0.320 }, { 0.000, 0.000, 0.000 }, 0.95, 0.00 },
    rock = { { 0.500, 0.480, 0.450 }, { 0.000, 0.000, 0.000 }, 0.90, 0.00 },
    sorc_robe = { { 0.420, 0.140, 0.500 }, { 0.020, 0.000, 0.030 }, 0.65, 0.00 },
    sorc_dk = { { 0.160, 0.050, 0.200 }, { 0.000, 0.000, 0.000 }, 0.80, 0.00 },
    death_robe = { { 0.070, 0.070, 0.090 }, { 0.000, 0.000, 0.000 }, 0.85, 0.00 },
    bone = { { 0.860, 0.840, 0.740 }, { 0.040, 0.040, 0.030 }, 0.55, 0.00 },
    eye_red = { { 1.000, 0.300, 0.200 }, { 2.200, 0.500, 0.250 }, 0.50, 0.00 },
    eye_yel = { { 1.000, 0.900, 0.300 }, { 2.000, 1.600, 0.300 }, 0.50, 0.00 },
    eye_green = { { 0.500, 1.000, 0.400 }, { 0.800, 2.000, 0.500 }, 0.50, 0.00 },
    magic = { { 0.900, 0.500, 1.000 }, { 1.600, 0.700, 2.200 }, 0.30, 0.00 },
}
for _, kv in ipairs({{ "ch_death_arm_l_bone", "bone" }, { "ch_death_arm_l_death_robe", "death_robe" }, { "ch_death_arm_r_bone", "bone" }, { "ch_death_arm_r_death_robe", "death_robe" }, { "ch_death_arm_r_steel", "steel" }, { "ch_death_arm_r_wood", "wood" }, { "ch_death_body_bone", "bone" }, { "ch_death_body_death_robe", "death_robe" }, { "ch_death_body_eye_red", "eye_red" }, { "ch_death_body_void", "void" }, { "ch_demon_arm_l_claw", "claw" }, { "ch_demon_arm_l_demon_skin", "demon_skin" }, { "ch_demon_arm_r_claw", "claw" }, { "ch_demon_arm_r_demon_skin", "demon_skin" }, { "ch_demon_body_demon_skin", "demon_skin" }, { "ch_demon_body_eye_yel", "eye_yel" }, { "ch_demon_body_horn", "horn" }, { "ch_demon_body_void", "void" }, { "ch_demon_leg_l_claw", "claw" }, { "ch_demon_leg_l_demon_skin", "demon_skin" }, { "ch_demon_leg_r_claw", "claw" }, { "ch_demon_leg_r_demon_skin", "demon_skin" }, { "ch_demon_wing_l_demon_wing", "demon_wing" }, { "ch_demon_wing_l_horn", "horn" }, { "ch_demon_wing_r_demon_wing", "demon_wing" }, { "ch_demon_wing_r_horn", "horn" }, { "ch_elf_arm_l_elf_green", "elf_green" }, { "ch_elf_arm_l_leather", "leather" }, { "ch_elf_arm_l_skin", "skin" }, { "ch_elf_arm_l_white", "white" }, { "ch_elf_arm_l_wood", "wood" }, { "ch_elf_arm_r_elf_green", "elf_green" }, { "ch_elf_arm_r_leather", "leather" }, { "ch_elf_arm_r_skin", "skin" }, { "ch_elf_body_elf_dkgreen", "elf_dkgreen" }, { "ch_elf_body_elf_green", "elf_green" }, { "ch_elf_body_elf_hair", "elf_hair" }, { "ch_elf_body_feather", "feather" }, { "ch_elf_body_gold", "gold" }, { "ch_elf_body_leather", "leather" }, { "ch_elf_body_skin", "skin" }, { "ch_elf_body_void", "void" }, { "ch_elf_body_wood", "wood" }, { "ch_elf_leg_l_leather", "leather" }, { "ch_elf_leg_l_leather_dk", "leather_dk" }, { "ch_elf_leg_r_leather", "leather" }, { "ch_elf_leg_r_leather_dk", "leather_dk" }, { "ch_ghost_arm_l_ghost", "ghost" }, { "ch_ghost_arm_r_ghost", "ghost" }, { "ch_ghost_body_eye_green", "eye_green" }, { "ch_ghost_body_ghost", "ghost" }, { "ch_ghost_body_void", "void" }, { "ch_grunt_arm_l_grunt_skin", "grunt_skin" }, { "ch_grunt_arm_l_leather", "leather" }, { "ch_grunt_arm_r_grunt_skin", "grunt_skin" }, { "ch_grunt_arm_r_leather", "leather" }, { "ch_grunt_arm_r_steel_dk", "steel_dk" }, { "ch_grunt_arm_r_wood", "wood" }, { "ch_grunt_body_bronze", "bronze" }, { "ch_grunt_body_eye_red", "eye_red" }, { "ch_grunt_body_grunt_cloth", "grunt_cloth" }, { "ch_grunt_body_grunt_skin", "grunt_skin" }, { "ch_grunt_body_horn", "horn" }, { "ch_grunt_body_ivory", "ivory" }, { "ch_grunt_leg_l_claw", "claw" }, { "ch_grunt_leg_l_grunt_skin", "grunt_skin" }, { "ch_grunt_leg_r_claw", "claw" }, { "ch_grunt_leg_r_grunt_skin", "grunt_skin" }, { "ch_lobber_arm_l_lob_skin", "lob_skin" }, { "ch_lobber_arm_r_lob_skin", "lob_skin" }, { "ch_lobber_arm_r_rock", "rock" }, { "ch_lobber_body_eye_yel", "eye_yel" }, { "ch_lobber_body_grunt_cloth", "grunt_cloth" }, { "ch_lobber_body_leather", "leather" }, { "ch_lobber_body_lob_skin", "lob_skin" }, { "ch_lobber_body_sack", "sack" }, { "ch_lobber_leg_l_lob_skin", "lob_skin" }, { "ch_lobber_leg_r_lob_skin", "lob_skin" }, { "ch_sorc_arm_l_gold", "gold" }, { "ch_sorc_arm_l_magic", "magic" }, { "ch_sorc_arm_l_skin_dk", "skin_dk" }, { "ch_sorc_arm_l_sorc_robe", "sorc_robe" }, { "ch_sorc_arm_r_gold", "gold" }, { "ch_sorc_arm_r_magic", "magic" }, { "ch_sorc_arm_r_skin_dk", "skin_dk" }, { "ch_sorc_arm_r_sorc_robe", "sorc_robe" }, { "ch_sorc_body_eye_red", "eye_red" }, { "ch_sorc_body_gold", "gold" }, { "ch_sorc_body_sorc_dk", "sorc_dk" }, { "ch_sorc_body_sorc_robe", "sorc_robe" }, { "ch_val_arm_l_gold", "gold" }, { "ch_val_arm_l_skin", "skin" }, { "ch_val_arm_l_val_armor", "val_armor" }, { "ch_val_arm_l_val_blue", "val_blue" }, { "ch_val_arm_r_gold", "gold" }, { "ch_val_arm_r_leather", "leather" }, { "ch_val_arm_r_skin", "skin" }, { "ch_val_arm_r_steel", "steel" }, { "ch_val_arm_r_val_armor", "val_armor" }, { "ch_val_body_gold", "gold" }, { "ch_val_body_skin", "skin" }, { "ch_val_body_steel", "steel" }, { "ch_val_body_val_armor", "val_armor" }, { "ch_val_body_val_blue", "val_blue" }, { "ch_val_body_val_hair", "val_hair" }, { "ch_val_body_void", "void" }, { "ch_val_body_white", "white" }, { "ch_val_leg_l_leather", "leather" }, { "ch_val_leg_l_skin", "skin" }, { "ch_val_leg_l_steel", "steel" }, { "ch_val_leg_r_leather", "leather" }, { "ch_val_leg_r_skin", "skin" }, { "ch_val_leg_r_steel", "steel" }, { "ch_war_arm_l_gold", "gold" }, { "ch_war_arm_l_leather", "leather" }, { "ch_war_arm_l_skin", "skin" }, { "ch_war_arm_l_steel", "steel" }, { "ch_war_arm_l_war_red", "war_red" }, { "ch_war_arm_r_gold", "gold" }, { "ch_war_arm_r_leather", "leather" }, { "ch_war_arm_r_skin", "skin" }, { "ch_war_arm_r_steel", "steel" }, { "ch_war_arm_r_war_red", "war_red" }, { "ch_war_arm_r_wood", "wood" }, { "ch_war_body_fur", "fur" }, { "ch_war_body_gold", "gold" }, { "ch_war_body_ivory", "ivory" }, { "ch_war_body_leather", "leather" }, { "ch_war_body_skin", "skin" }, { "ch_war_body_steel", "steel" }, { "ch_war_body_void", "void" }, { "ch_war_body_war_hair", "war_hair" }, { "ch_war_body_war_red", "war_red" }, { "ch_war_leg_l_fur", "fur" }, { "ch_war_leg_l_leather", "leather" }, { "ch_war_leg_l_leather_dk", "leather_dk" }, { "ch_war_leg_r_fur", "fur" }, { "ch_war_leg_r_leather", "leather" }, { "ch_war_leg_r_leather_dk", "leather_dk" }, { "ch_wiz_arm_l_skin", "skin" }, { "ch_wiz_arm_l_wiz_robe", "wiz_robe" }, { "ch_wiz_arm_l_wiz_trim", "wiz_trim" }, { "ch_wiz_arm_r_gold", "gold" }, { "ch_wiz_arm_r_orb", "orb" }, { "ch_wiz_arm_r_skin", "skin" }, { "ch_wiz_arm_r_wiz_robe", "wiz_robe" }, { "ch_wiz_arm_r_wiz_trim", "wiz_trim" }, { "ch_wiz_arm_r_wood", "wood" }, { "ch_wiz_body_beard", "beard" }, { "ch_wiz_body_gold", "gold" }, { "ch_wiz_body_skin", "skin" }, { "ch_wiz_body_void", "void" }, { "ch_wiz_body_wiz_robe", "wiz_robe" }, { "ch_wiz_body_wiz_trim", "wiz_trim" }, { "ch_wiz_leg_l_wiz_trim", "wiz_trim" }, { "ch_wiz_leg_r_wiz_trim", "wiz_trim" }}) do PAL[kv[1]] = RMAT[kv[2]] end
G.RIG = RIG
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
FX.scale = 0.45   -- Gauntlet: one-unit maze tiles
G.fx_light = function(pos, col, power, life, radius) flash(pos, col, power * 0.5, life, radius) end
------------------------------------------------------------------ levels (generated by tools/levels.py, do not edit)
-- rows: top row = north (highest y). See tools/levels.py for the legend.
local LEVELS = {
    { name = "Level 1", style = "maze", w = 29, h = 21, jump = 0, wt = 0, ft = 0, wc = { 1.00, 1.00, 1.00 }, fc = { 0.90, 0.90, 0.90 }, trapw = false, rows = {
        "#############################",
        "#S..........................#",
        "#...#.###.###.#.#.###...#.#.#",
        "#...#.f.......#.#...g.......#",
        "#.#.#.#.#.#.#t#.#.#.#.#.###.#",
        "#.......f...#...#.......#tD.#",
        "###f#...#.#.#.#.#.......###.#",
        "#......k#...#.............#p#",
        "#.###...###.#.#f#....t..#.#.#",
        "#.........................#.#",
        "#.#.#.#.#.#.#.###k###.#g#.#.#",
        "#...#...........#...p.....#.#",
        "###.#####.#####.#.#.#####.#.#",
        "#.#......g.......g..........#",
        "#.#######.#.#.#####.#.#.#f#D#",
        "#...........#...#.t.......#t#",
        "#.#.#.###.#.#.#.#.#.#####.###",
        "#.#...........#.............#",
        "#.#.#.#.###.#.#.#####.#.###g#",
        "#....g..............E.#.....#",
        "#############################",
    } },
    { name = "Level 2", style = "halls", w = 33, h = 25, jump = 0, wt = 1, ft = 1, wc = { 1.00, 1.00, 1.00 }, fc = { 0.90, 0.90, 0.90 }, trapw = false, rows = {
        "#################################",
        "#################################",
        "#######################.......###",
        "#######################......E###",
        "######......###########....f.k###",
        "#####.......##############..#####",
        "#####....p..##############..#####",
        "#####g.#######.......##......####",
        "#####..#######.......##....r.####",
        "#........#####...f....f......p.##",
        "#..........k.........g...t.....##",
        "#....t............f..#####.##..##",
        "####..########.......#####.##..##",
        "####..###########..#######.....##",
        "##.....##########..#######.r...##",
        "##...f.#######.......#####.....##",
        "##.....#######....t..#####.....##",
        "##.....#######r.........g...#.###",
        "#......#######.......######.#g###",
        "#.S....#################......###",
        "#...####################......###",
        "########################......###",
        "########################......###",
        "#################################",
        "#################################",
    } },
    { name = "Level 3", style = "pillars", w = 31, h = 23, jump = 0, wt = 4, ft = 4, wc = { 1.00, 0.97, 0.92 }, fc = { 0.90, 0.90, 0.90 }, trapw = true, rows = {
        "###############################",
        "#..............S..............#",
        "#.#.#.#.#.#.#.....#.#.#.#.#.#.#",
        "#.............................#",
        "#...#.#.#.#.#.#.#.#.#.#.#.#.#.#",
        "#.......tf.k...##.###.........#",
        "#.#.#.#...#.#.g...#.#...#...#.#",
        "#...................f.........#",
        "#.#g#.#.....#...#.#.#.#f#.#.#.#",
        "#........r....................#",
        "#...#.#.#.......#.#.#.#.#.#.#.#",
        "#..............D..#..##......f#",
        "#.#.#.#.#.#...#t#.#.#.w.#.#.#.#",
        "#.r..........####w#w#.##.f....#",
        "#.#.#.#.#.#.#...#...#.#.##k.#.#",
        "#........................#..t.#",
        "#.#..#w#..#...#.#.#.#.#..#..#.#",
        "#....T........g##.######.#....#",
        "#.#t....#.#.#.#.#...###p#tD##.#",
        "#........................#....#",
        "#.#.#...#.#.#...#.#.#.#r#...#.#",
        "#...p........g..........E.....#",
        "###############################",
    } },
    { name = "Level 4", style = "rings", w = 33, h = 25, jump = 4, wt = 2, ft = 2, wc = { 1.00, 1.00, 1.00 }, fc = { 0.90, 0.90, 0.90 }, trapw = true, rows = {
        "#################################",
        "#................r.....t...r....#",
        "#.#######.#####################.#",
        "#f#......r.........t.d........#.#",
        "#.#.#####.###################.#.#",
        "#.#.#tD.....................#.#.#",
        "#.#r#####.###########w#####.#.#f#",
        "#X#.#.#.........#.........#.#f#.#",
        "#.#.#..k#.#######..#..###.#.#.#.#",
        "#.#.#...w..d...........z#.#.#.#.#",
        "#.#.#.###...............#.#.#.#.#",
        "#.#.#.#t#...............#.#.#.#.#",
        "#.#.#.#D#.......S.......#.#.#.#.#",
        "#.#.#.#.#...............#.#.#t#.#",
        "#.#.#.#.#...............#k#.#.#.#",
        "#.#.#.#.#...............#.#.#.#.#",
        "#.#.#.#.####w############.#.w.#.#",
        "#.#.#.#...t...........z...#.#.#.#",
        "#.#.#.#####################f#.#.#",
        "#.#.#...........p.d........z#.#.#",
        "#.#.############w########..##.#.#",
        "#.#..d...f....................#.#",
        "#.########################..###E#",
        "#......T.p......................#",
        "#################################",
    } },
    { name = "Treasure Room", style = "treasure", w = 27, h = 19, jump = 0, wt = 5, ft = 5, wc = { 0.95, 0.90, 0.80 }, fc = { 0.90, 0.85, 0.80 }, trapw = false, treasure = 30, rows = {
        "###########################",
        "#.......t...........tf....#",
        "#......t............t.....#",
        "#t..####################.t#",
        "#...#..................#..#",
        "#...#..................#..#",
        "#...#...############...#..#",
        "#...#..............#..t#..#",
        "#.......#.......t..#f#.#..#",
        "#S..#t..#....t.........#..#",
        "#...#..t#......p...##..#..#",
        "#...#..t#...t.....t#...#..#",
        "#...#.t....t.......#.t.#..#",
        "#.t.##.t############t.##E.#",
        "#...#.t........t.......#..#",
        "#...#........t.#.......#.t#",
        "#...#########.##########..#",
        "#............tt.....t...t.#",
        "###########################",
    } },
    { name = "Level 6", style = "mirror", w = 35, h = 25, jump = 0, wt = 3, ft = 3, wc = { 1.00, 1.00, 1.00 }, fc = { 0.90, 0.90, 0.90 }, trapw = true, rows = {
        "###################################",
        "#tD.......#.............#.......Dt#",
        "###.#t#.#.#.#.#.#.#.#.#.#.#.#.#.###",
        "#...#E.g....#.........#.......#...#",
        "#.#.#.###.#.#.#.#l#.#.#.#.###.w.#.#",
        "#..lw.....#..t..#.#.....w.....#...#",
        "#.###f#.#.#####.#.#.#####.#.#.###.#",
        "#.#...#.#.......#.#.......#.#...#.#",
        "#.#.###T#.#f#.#.#.#.#.#.#.#l###.#.#",
        "#.#...#.w.....#.....#.....#.#...#.#",
        "#.#.#.#.#.#.#.........#t#.#.#.#.#.#",
        "#.#...#...#f............#...#.g.w.#",
        "#.#.#####.#.##.......##g#.#####.#.#",
        "#..t.k..#.................#.......#",
        "#####.#.#####.........#####.#z#####",
        "#.....#.....................#.....#",
        "#.#.#.#.#.#.#.###.###.#.#.#.#.#.#.#",
        "#...#.z...f...................#...#",
        "#.#.#.#.#.#.#####.#####.#.#.#.#.#.#",
        "#.#.....#......k..........#.....#.#",
        "#.###.#.#.#.#.#.#.#.#.#.#z#f#.###.#",
        "#.#...#p..#g..#.....#...#...#...#.#",
        "#.#.#.###.#.#.##...##.#.#.###.#.#.#",
        "#g..#...p........S............#..l#",
        "###################################",
    } },
    { name = "Level 7", style = "diag", w = 33, h = 25, jump = 0, wt = 0, ft = 4, wc = { 0.85, 0.80, 0.75 }, fc = { 0.85, 0.85, 0.85 }, trapw = true, rows = {
        "#################################",
        "#......E......wt##.......z.s....#",
        "#.......##.k.####....######.....#",
        "#......f.##...##.....#..........#",
        "#.........##.####....#....#..p..#",
        "#..........###.f..d..##w###.....#",
        "#..........##........#.t..#....##",
        "#............##......#........###",
        "#.............##....tw....#..##.#",
        "#..#####.......##z.#w#w####....g#",
        "#..#...#...d....##.....##.......#",
        "#......#.......f.##..###........#",
        "#..#...#.............###........#",
        "#..#w###............##..........#",
        "#........s....f....##...........#",
        "#.................##...........g#",
        "#........##......##....##..T....#",
        "#.......##..t..........g.......D#",
        "#......##........##......##..##t#",
        "#.p...##........##........##..###",
        "#....##..f....z##..........##..##",
        "###.........s.##............##..#",
        "#..##...d.......................#",
        "#......k....##t................S#",
        "#################################",
    } },
    { name = "Level 8", style = "maze", w = 37, h = 27, jump = 0, wt = 1, ft = 0, wc = { 0.80, 0.80, 0.90 }, fc = { 0.85, 0.85, 0.90 }, trapw = true, rows = {
        "#####################################",
        "#t#f...z..#..........g.............S#",
        "#D#.#####.#.#.#####.###.###.#k#.#...#",
        "#.....................#.......#.....#",
        "#.....#.........#.#.#.###.#.#.#.#.###",
        "#............t....#.#.........#.#...#",
        "#.....#.#######.#.#.#.#.#.#.#.#.###.#",
        "#....g....#.......#.#......t........#",
        "#.#.###.#.#.#.#.###.#.#####T#.#.###.#",
        "#...........................#.....#.#",
        "#.#.......#.#.#.###.###.#.#d#.#.#.#.#",
        "#.............#.........#...#.......#",
        "#.#.#w#.#.....#.#.###.#.#w#k#.#####.#",
        "#...........t.w.#.t...........d.#...#",
        "#.#z###.#.#.#.#.#####w#####.#.#.#.###",
        "#.......#.....#.#.....#.g.#.........#",
        "#.###r#.#...#.#.#.#.#.#.#.#.#.#.###.#",
        "#..............p..........#.f.......#",
        "#.#.#.###.#.#w#.#.#.#w#.#.#####r#.#.#",
        "#.........#.....#.#.p.#.......f.....#",
        "#.#.#####.#.#####.###.#####.#.#####.#",
        "#.......................#...z.....#.#",
        "#.#.#f#.#######z###.###.#d#.#####.#.#",
        "#...#...f..r..f.........#....t..g...#",
        "#.#.###.#####.#.#.#.#.###.#.#.#.#.#.#",
        "#...........E................r#.....#",
        "#####################################",
    } },
    { name = "Level 9", style = "halls", w = 39, h = 27, jump = 3, wt = 4, ft = 2, wc = { 0.85, 0.85, 0.85 }, fc = { 0.85, 0.85, 0.85 }, trapw = true, rows = {
        "#######################################",
        "#####.d...#############################",
        "####......#############################",
        "####......#############################",
        "####f##.###############################",
        "####.##.#############........##########",
        "####.##.#############..#..#.l##.....z##",
        "####.##.#############................##",
        "####.##T######.....##..#f.#..##s.....##",
        "#.......######.....##t.......##########",
        "#..#....######....p###ww#.#############",
        "#....t..###.......l.......#############",
        "#......k###.##.....######.#############",
        "#S.#....###.##.X...######f#############",
        "#.......###.#############d..z##########",
        "####..#.###.#############..t.##########",
        "####..w.###.#############.......#######",
        "##l...#...s....##########....t..#######",
        "##...........f.z.z...........#pf#######",
        "##....#........####w##########..#######",
        "##..s.w.###########....#######.t#######",
        "##....w.###########...l####.......#####",
        "#######.###########....####.......#####",
        "#######.....................kf..Ed#####",
        "###########################d......#####",
        "#######################################",
        "#######################################",
    } },
    { name = "Treasure Room", style = "treasure", w = 29, h = 21, jump = 0, wt = 5, ft = 1, wc = { 0.90, 0.95, 1.00 }, fc = { 0.85, 0.88, 0.90 }, trapw = false, treasure = 30, rows = {
        "#############################",
        "#..t...........E............#",
        "#.....................t.t...#",
        "#...##############.#######t.#",
        "#...#..................t.#.t#",
        "#...#t.........t.........#t.#",
        "#...#t.t##############t..#..#",
        "#...#...#............#.t.#..#",
        "#...#...#........t...#p..#f.#",
        "#...#...#............#..f#t.#",
        "#...#...#................#t.#",
        "#...#t..#...........t#.t.#..#",
        "#..t#..t#............#...#tt#",
        "#...#...#.......t....#...#..#",
        "#...#...#.......t....#.t.#..#",
        "#...#...###.##########...#t.#",
        "#...#....................#..#",
        "#...#.........#......t..t#..#",
        "#...#########...##########..#",
        "#.............S........t...t#",
        "#############################",
    } },
    { name = "Level 11", style = "pillars", w = 37, h = 27, jump = 0, wt = 2, ft = 5, wc = { 0.90, 0.85, 0.80 }, fc = { 0.85, 0.85, 0.85 }, trapw = true, rows = {
        "#####################################",
        "#.........................l.........#",
        "#.#.#.#.#.#...#.#z#.#.#...#.....#.#.#",
        "#........t...D........k........k....#",
        "#...#...#.#.#t#.#.#.#.#.##w##.#.....#",
        "#.......#.#######.wl...........E....#",
        "#...#.#t#.#.#.#.#.#.#.#.#.#.#.#.#.#.#",
        "#t........#s..........w.............#",
        "#.#.#.#.....#.#....f###w###.#.#.#.#.#",
        "#.##tD##..#...........#..s..........#",
        "#...#.#s#.#...#.#.#.#...#...#.#.#.#.#",
        "#.....p...#....l......#..f..........#",
        "#.f.#.#.#.#.#.#z#.#...w.#.###...#.#.#",
        "#.........#..........T#.............#",
        "#.#.#.#.#.#...#.#.#z#.#...#...#.#.#.#",
        "#...........................t.....T.#",
        "#.#.#w##f.#.#.....#.#.#.#.#.#.......#",
        "#..g..........................g.....#",
        "#...#.#.#.#.#.#...#.#.#.#.#.#.#...#.#",
        "#...................................#",
        "#.#.#g..#.#.#.#.#.#...#.#.#.#.#.#.#.#",
        "#....f..............................#",
        "#.#.#.#.#.#.#.#.#.#.#z#.#.#s....#.#l#",
        "#...................................#",
        "#...#.#...#.#.#.#.#.#fp.#...#.#.#.#.#",
        "#S....................g.t...........#",
        "#####################################",
    } },
    { name = "Level 12", style = "rings", w = 37, h = 29, jump = 2, wt = 3, ft = 0, wc = { 0.85, 0.95, 0.85 }, fc = { 0.85, 0.85, 0.85 }, trapw = true, rows = {
        "#####################################",
        "#S.............................f....#",
        "#..################################.#",
        "#....f....#....z.....t........r...#.#",
        "#..##############################.#.#",
        "#.#.#...........................#.#.#",
        "#.#.#.........r...f....d....d...#...#",
        "#.w.#..##w############..######..#...#",
        "#.#.#..........k..r..........#..#.#z#",
        "#.#.#..#.....................#..#.#t#",
        "#.#.#..#..#################..#..#.#.#",
        "#.#.#..#..#...z.p...wt#tw.#..w..#.#.#",
        "#.#.#..#..#.#######..####.#..#....#.#",
        "#.#.#..#..#.#..t........#.#..#....#.#",
        "#.#.#..#..#.#.E.........#g#..#..#.#.#",
        "#.#.#.g#..#.#.g.........#.#..#..#.#.#",
        "#.#.#..#..#.#############.#..#..#t#.#",
        "#.#.#..#..#....T..........#..w..#.#.#",
        "#.#g#..#..##########..#####..#..#.#.#",
        "#.#.#..#.....g.......t.......#..#.#.#",
        "#.#.#..#.....................#..#.#.#",
        "#.#.#..######..#####w#########..#.#.#",
        "#.#.#r..........................#.#.#",
        "#.#.#.....T...........d.........#.#.#",
        "#.#.#####################.t######.#.#",
        "#.#..............f................#.#",
        "#.######################w####w#####.#",
        "#dkf..................f.......Xz..zp#",
        "#####################################",
    } },
    { name = "Level 13", style = "mirror", w = 39, h = 27, jump = 0, wt = 0, ft = 1, wc = { 0.75, 0.72, 0.70 }, fc = { 0.80, 0.80, 0.80 }, trapw = true, rows = {
        "#######################################",
        "#.#................S................#t#",
        "#l#.#.#.#f#t#.#.#.....#.#.#.#.#.#.#.#D#",
        "#...#.......#.............#.......#...#",
        "#.###.#.#.#.#.###.#.#.###.#.#.#.#.###.#",
        "#..t..#.#.......w.....#.......#.#.....#",
        "#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#",
        "#...........#....d#.#...f.#...........#",
        "#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#",
        "#.#...........#.#.....#.#.d.........#.#",
        "#.#.#.#.#.#T#.#.#.#.#.#.#.#.#.#.#.#.#.#",
        "#.......#...#..........r..#...#..k...l#",
        "#.#####.###.#.#.........#.#.###.#####.#",
        "#.....#..z......................#.....#",
        "#.#.#.#w#####t#.........#.####w##.#.#.#",
        "#...........#.............#......r....#",
        "#.#.###.###t#.###.###.###l#.#w#.###.#.#",
        "#....z#.f...#....d...p....#.....#.....#",
        "#.#.#.#.#.###.#.#.#.#.#k#.#w#r#t#.#.#.#",
        "#.t.#.......#.....w.#.....#f......#...#",
        "###.#.#.#.#.#.#.#.#z#.#.#.#.#.#p#.#.###",
        "#.....#...#...r.#.#.#f#.....w...#.....#",
        "#.###d#.###.#.#.#.#.#.#.#.#.###.#.###.#",
        "#...#...#.........#.#...z.....#...#...#",
        "#D#.###.#.###.#T#.#.#.#.#.###.#.###.#.#",
        "#t#rfE....z.......................l.#.#",
        "#######################################",
    } },
    { name = "Level 14", style = "diag", w = 37, h = 27, jump = 0, wt = 4, ft = 3, wc = { 0.95, 0.85, 0.80 }, fc = { 0.85, 0.85, 0.85 }, trapw = true, rows = {
        "#####################################",
        "#.........##........................#",
        "#.....s..##z...........T.##.........#",
        "#..................g...........z##..#",
        "#......##......................##...#",
        "#t......................l.....##....#",
        "#...##..g........l........t.........#",
        "#..##....t................f.##......#",
        "#.##........s..........f...##.......#",
        "#.............##....................#",
        "#...##...##....##............p......#",
        "#.........##....................s...#",
        "#S.#.......##..f.##.....g..k........#",
        "#...........##....####..............#",
        "##...........##....##..............D#",
        "#.............##k.####f........f.##t#",
        "#..............#w######.......sE..###",
        "#.##................###w#...........#",
        "#..##..l...t........###.z...........#",
        "#...##....p.........Dt###...........#",
        "#...z##.....t.......#####...........#",
        "#..........###w#t...######..##.....l#",
        "#......##..#........w.......z##.....#",
        "#.......####...#....w..#......##....#",
        "#....T...#####w#.s..##w#.......##...#",
        "#.g..f.....g##......................#",
        "#####################################",
    } },
    { name = "Treasure Room", style = "treasure", w = 31, h = 21, jump = 0, wt = 5, ft = 2, wc = { 0.90, 0.80, 0.70 }, fc = { 0.85, 0.80, 0.75 }, trapw = true, treasure = 30, rows = {
        "###############################",
        "#..........................t..#",
        "#.........t...t.............t.#",
        "#...########################..#",
        "#...#.........T......t.....#..#",
        "#.t..t................#t...#..#",
        "#...#..t#############.##..t#..#",
        "#..p#...#.t..t.........#...#..#",
        "#..t#..t#..........f...#...#..#",
        "#.t.#...#t.............#..t#..#",
        "#...#...#..t.....tt....#...#.S#",
        "#...#...#f.............#...#..#",
        "#...#...##.............#...#..#",
        "#...#..t..t#..............t...#",
        "#.Et#...#..........t...#...#..#",
        "#.t.#...################...#..#",
        "#...#w.....T.....#.......t.#..#",
        "#tt.#t#.t.#...........t....#..#",
        "#...########################..#",
        "#.........t.t.................#",
        "###############################",
    } },
    { name = "Level 16", style = "maze", w = 41, h = 29, jump = 3, wt = 2, ft = 4, wc = { 0.75, 0.70, 0.70 }, fc = { 0.80, 0.80, 0.80 }, trapw = true, rows = {
        "#########################################",
        "#t#.z.........#.....gk#.................#",
        "#D#.#.#.#.###.#.#t###.#.#.#.#.###.#.###.#",
        "#....d..........#...t.#.#.....#.s.......#",
        "#.......###.#.#.#t#T###.#.#.#.#.#.#.#.#.#",
        "#.......#.s...#...#.............#.......#",
        "#.......#.#.#.#t#.###.#.###.#.#.#.#.#.#.#",
        "#.E.....#.#.....#..p...l......#...#...#.#",
        "#.#.###.#.#.#.#z#.#####.###w#g#.#.###.#.#",
        "#.#.....#........f..............#.....#.#",
        "#.#.#.#.#.#d#w#.....#.#.#.#.#.#.#.###.#.#",
        "#.....#d......#...............#.....#...#",
        "###.#.#.###.#.#.###...#.#.#.#.#.#.#.#.#.#",
        "#.....#.........#...S.............#.....#",
        "#.#.#z#.###.##w##.#...#.#.#.#.#z#.###.#.#",
        "#.#..s#tt.........#...#.........#..f#...#",
        "#.#t###.#.#w#.######w##.#.#.#.#.###.#.#.#",
        "#...z.#...#...................#....X....#",
        "#.###.#.###.#.......#.###.#####.#.#####.#",
        "#.l.w...#......f.......p........f.......#",
        "#.#.#.#.#.#.###.#.#.#.#......g#.#.#f###.#",
        "#.#.#.............#.#.#.................#",
        "#.#.#.#.###.#.....#.#.#.#####.#.###.#w#.#",
        "#.....#.............#...l.....w....f....#",
        "###.#.#...k.......#.#.#.#.###.#####.#.#l#",
        "#...#.................#.......#...#...T.#",
        "#.###.#.###.#.###.#.#.###z#.###.#.#.###.#",
        "#.......d.............g...........#.....#",
        "#########################################",
    } },
    { name = "Level 17", style = "halls", w = 41, h = 29, jump = 0, wt = 1, ft = 5, wc = { 0.70, 0.70, 0.78 }, fc = { 0.80, 0.80, 0.85 }, trapw = true, rows = {
        "#########################################",
        "#####################......###z.....#####",
        "#####################......###........###",
        "##############.......dp..ft.........S.###",
        "##############.....T..........t.......###",
        "##############..d..##.....t###rp.....####",
        "#...g...######.....###########.......####",
        "#.......######.....##############.##.####",
        "#.......######.#.################.##.####",
        "######..######.#.################.....z##",
        "######..####zr...............z.....k..g##",
        "######..####.....#################.....##",
        "######..####k....###################..###",
        "######..####t....##########.....####..###",
        "######.r####.#..###########.....####..###",
        "######t.####.w..###########.......d...###",
        "####....####.#..###########...r.t....####",
        "####..f.##.....g################..#######",
        "####.f..##......################..#######",
        "######...z......################..#######",
        "##########.....#####.f.s.#######..#######",
        "############..s..........####......######",
        "##.....t####.#w#####.....####......######",
        "##.....g##....T##############..d...######",
        "##.f.E.........##############......######",
        "##......##.s.f.##############......######",
        "#############################.....z######",
        "#########################################",
        "#########################################",
    } },
    { name = "Level 18", style = "pillars", w = 39, h = 29, jump = 0, wt = 3, ft = 2, wc = { 0.80, 0.90, 0.80 }, fc = { 0.80, 0.80, 0.80 }, trapw = true, rows = {
        "#######################################",
        "#.......f.Ed.....s.................l..#",
        "#.#.#.#.#.#.#.#.#.#...#.#.#.#.#...#.#.#",
        "####.##............t.d...t............#",
        "#.#...#.#.#...#.#.#...#.#.#.#.#.l.#.#.#",
        "#.............#w##.#w#.##.............#",
        "#.#.#.#.#.#.#.#.#.........#.#.#.#.#f#.#",
        "#.............d.......................#",
        "#g#...#.#l#.##w##w#.#z#.#.#.#z#.#.#.#.#",
        "#....#......z.........................#",
        "#.#..##.#.#.#.#.f.#.#.#....T#.#......g#",
        "#....wt...............................#",
        "#.#.p##.#.#.#.#...#.#.#.#.#.#.#.#g#.#.#",
        "#....w.s....z.z.......................#",
        "#.#.###...#.#.#.#.#.#.#.#.f.....#.#.#.#",
        "#...#........................tt.......#",
        "#.#...#.#.#...#.#.#.#...#.#.#...#...#.#",
        "#...#...........z.....................#",
        "#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.....#",
        "#.......f.......t..............s......#",
        "#.#.#.#.#t#.#.#.#.#.#.#.#.#...#...#.#.#",
        "#.....................................#",
        "#.#...#.#.#.#p#####w#..#w##.#.###...#.#",
        "#.........................d....#......#",
        "#...#.#.#....l#.#.#.#.#.#.#.#.###.#.#.#",
        "#...............###.......f....#......#",
        "#.#.#.#.#.#.#...#.#.#..T#.#...#tD.#...#",
        "#.....k............k...g....sDt#.....S#",
        "#######################################",
    } },
    { name = "Level 19", style = "rings", w = 41, h = 29, jump = 0, wt = 4, ft = 0, wc = { 0.70, 0.70, 0.70 }, fc = { 0.75, 0.75, 0.75 }, trapw = true, rows = {
        "#########################################",
        "#..................................z....#",
        "#k############..##w####################.#",
        "#.#...........................s.....s.#.#",
        "#.#.#################################.#.#",
        "#.#.#........z......................#.#.#",
        "#s#.#.#########w##############..###.#.#.#",
        "#.#...#...........#.......d.......#.#.#.#",
        "#.#...#.#########################.#.#.w.#",
        "#...#.#.#........#...f.......#..#.#z#.#.#",
        "#...#.#.#.################w#..#.#.#.#.#.#",
        "#.#.#.#.#.#..f#.Dt#....Dt#....#t#.#.#.#f#",
        "#.#.#.#.#.#.###.###.#########.#.#.#d#.#.#",
        "#.#.#.w.#.#.#.....g.......p.#...#.#.#.#.#",
        "#.#.#.#.#.#.#...................#.w.#.#.#",
        "#.w.T.#d#T#t#............p....#.#.#.#.#.#",
        "#.#...#.#.#.###..############.#.#.#.#.#d#",
        "#.#.#.#...#...s.........z.....#.#l#.#.#f#",
        "#.#.#.#...#####################.#.#.#.#.#",
        "#.#.#.#.#.E.z......f.....l......#.#.#.#.#",
        "#.#.#.#t#######################z#.#.#.#t#",
        "#.#.#.#...........................#.#k#.#",
        "#.#.#.#######################..####.#.#.#",
        "#.#.#.....t....................g....#.#.#",
        "#.#.#################################.#.#",
        "#.#......t.........t........l.....g.f.#l#",
        "#..########################w###########.#",
        "#S............g.........................#",
        "#########################################",
    } },
    { name = "Treasure Room", style = "treasure", w = 33, h = 23, jump = 0, wt = 5, ft = 3, wc = { 0.85, 0.80, 0.75 }, fc = { 0.80, 0.78, 0.75 }, trapw = false, treasure = 30, rows = {
        "#################################",
        "#tE....t.t......................#",
        "#.......t......t................#",
        "#...##########################..#",
        "#...#........................#..#",
        "#...#..............p.........#..#",
        "#t.t#...##################...#t.#",
        "#t..##..#......t.........#t..#..#",
        "#...#...#..............#.#.t.#..#",
        "#..f#...#..............f.#...#..#",
        "#t..#...#..t.............#...#t.#",
        "#...#...#..t....S.....t..#t..#..#",
        "#...#t..#....................#..#",
        "#...#.t.#...........t....#...#..#",
        "#...#...#....t...........#...#..#",
        "#...#.t.#........t...........#..#",
        "#...#...#........#.......#..t#..#",
        "#...#...###.##############...#t.#",
        "#...#.t...t...t.................#",
        "#...#.t.........t....t..t....#..#",
        "#...######################.###..#",
        "#...........t............t.t....#",
        "#################################",
    } },
}
G.LEVELS = LEVELS
------------------------------------------------------------------ heroes (arcade stats: armour, shot power, melee, speed, magic)
local HEROES = {
    { id = "war", name = "Warrior", hero = "Thor", armor = 0.8, shot = 3, melee = 4, speed = 3.4, magic = 1, shotm = "p_axe", sv = 9 },
    { id = "val", name = "Valkyrie", hero = "Thyra", armor = 0.6, shot = 2, melee = 3, speed = 3.8, magic = 2, shotm = "p_sword", sv = 10 },
    { id = "wiz", name = "Wizard", hero = "Merlin", armor = 1.0, shot = 2, melee = 1, speed = 3.8, magic = 3, shotm = "p_fire", sv = 10 },
    { id = "elf", name = "Elf", hero = "Questor", armor = 0.9, shot = 1, melee = 2, speed = 4.6, magic = 2, shotm = "p_arrow", sv = 13 },
}
G.HEROES = HEROES
local PR = 0.29                  -- hero radius (rounded collider, slightly inside the model so corners don't snag)
local MR = 0.3                   -- monster radius
local P = { x = 2, y = 2, fx = 0, fy = 1, hero = 1, alive = true }
G.P = P; G.PR, G.MR = PR, MR
G.MON, G.SHOTS, G.ESHOT, G.GENS, G.ITEMS = {}, {}, {}, {}, {}
local MAP, LW, LH
-- solid test for a cell (walls, closed doors, generators)
local function cell(i, j) if i < 0 or j < 0 or i >= LW or j >= LH then return "#" end; return MAP[j * LW + i + 1] end
local function solid(i, j) local c = cell(i, j); return c == "#" or c == "D" or c == "G" or c == "w" end
G.cell, G.solid = cell, solid
local function setc(i, j, v) MAP[j * LW + i + 1] = v end
-- circle vs grid: does a circle at (x, y) overlap any solid cell?
local function blocked(x, y, r)
    for j = floor(y - r), floor(y + r) do for i = floor(x - r), floor(x + r) do
        if solid(i, j) then
            local qx, qy = clamp(x, i, i + 1), clamp(y, j, j + 1)
            if (x - qx) ^ 2 + (y - qy) ^ 2 < r * r then return true end
        end
    end end
    return false
end
G.blocked = blocked
-- render interpolation between fixed 60 Hz steps (prev position stored at the start of each step)
function G.lerp_pos(e)
    local ox, oy = e.ox, e.oy
    if not ox or abs(e.x - ox) > 1.5 or abs(e.y - oy) > 1.5 then return e.x, e.y end
    return ox + (e.x - ox) * AL, oy + (e.y - oy) * AL
end
-- hero movement with corner assist: when the hero is blocked on one axis and the player isn't steering on the other,
-- look sideways (up to NUDGE) for a spot where the way ahead is open and slide toward it at walking speed.
local NUDGE = 0.45
local function nudge(e, axis, d, sp, r)
    for k = 1, 15 do
        local o = k * 0.03
        for _, sg in ipairs({ 1, -1 }) do
            local tx, ty = e.x, e.y
            if axis == "x" then tx = tx + o * sg else ty = ty + o * sg end
            local fx, fy = tx, ty
            if axis == "x" then fy = fy + d else fx = fx + d end
            if not blocked(tx, ty, r) and not blocked(fx, fy, r) then
                local step = min(o, sp * 0.9) * sg
                if axis == "x" then if not blocked(e.x + step, e.y, r) then e.x = e.x + step end
                else if not blocked(e.x, e.y + step, r) then e.y = e.y + step end end
                -- keep some forward progress once we're nearly through
                if o <= sp then
                    if axis == "x" then if not blocked(e.x, e.y + d * 0.5, r) then e.y = e.y + d * 0.5 end
                    else if not blocked(e.x + d * 0.5, e.y, r) then e.x = e.x + d * 0.5 end end
                end
                return true
            end
        end
    end
    return false
end
local function hero_move(e, dx, dy, r)
    local bx = dx ~= 0 and blocked(e.x + dx, e.y, r)
    if dx ~= 0 and not bx then e.x = e.x + dx end
    local by = dy ~= 0 and blocked(e.x, e.y + dy, r)
    if dy ~= 0 and not by then e.y = e.y + dy end
    local sp = math.max(abs(dx), abs(dy))
    if by and dx == 0 then nudge(e, "x", dy, sp, r) end
    if bx and dy == 0 then nudge(e, "y", dx, sp, r) end
    -- diagonal into a wall edge: the open axis already slides; if both are blocked, try each axis alone with a nudge
    if bx and by then if not nudge(e, "x", dy, sp * 0.7, r) then nudge(e, "y", dx, sp * 0.7, r) end end
    G.nudge_dbg = (by and dx == 0) or (bx and dy == 0) or (bx and by)
end
-- move with per-axis sliding: a diagonal into a wall still slides along whichever axis is open
local function move(e, dx, dy, r)
    local hit = false
    if dx ~= 0 then if not blocked(e.x + dx, e.y, r) then e.x = e.x + dx else hit = true end end
    if dy ~= 0 then if not blocked(e.x, e.y + dy, r) then e.y = e.y + dy else hit = true end end
    return hit
end
------------------------------------------------------------------ level load
local function load_level(n)
    G.level = n; G.load_id = (G.load_id or 0) + 1      -- the renderer re-dresses the floor on every load
    local L = G.LEVELS[(n - 1) % #G.LEVELS + 1]
    G.L = L; G.li = (n - 1) % #G.LEVELS + 1
    LW, LH = L.w, L.h; MAP = {}
    G.MON, G.SHOTS, G.ESHOT, G.GENS, G.ITEMS, G.DOORS = {}, {}, {}, {}, {}, {}
    G.EXITS, G.TRAPS, G.STUNS = {}, {}, {}
    G.exit = nil; G.trapped = false; P.stun, P.stun_cd = 0, 0
    G.tough = floor((n - 1) / #G.LEVELS)            -- later loops: tougher monsters
    G.ttime = (L.treasure and G.tough == 0) and L.treasure or (L.treasure and max(18, L.treasure - 4 * G.tough)) or nil
    for r, row in ipairs(L.rows) do
        local j = LH - r
        for i = 0, LW - 1 do
            local ch = row:sub(i + 1, i + 1)
            local base = (ch == "#" or ch == "D" or ch == "w") and ch or "."
            MAP[j * LW + i + 1] = base
            local x, y = i + 0.5, j + 0.5
            if ch == "S" then P.x, P.y = x, y
            elseif ch == "D" then G.DOORS[#G.DOORS + 1] = { i = i, j = j, open = 0 }
            elseif ch == "E" then G.exit = { x = x, y = y, to = n + 1 }; G.EXITS[#G.EXITS + 1] = G.exit
            elseif ch == "X" then G.EXITS[#G.EXITS + 1] = { x = x, y = y, to = n + max(2, L.jump or 2), jump = true }
            elseif ch == "T" then G.TRAPS[#G.TRAPS + 1] = { x = x, y = y }
            elseif ch == "z" then G.STUNS[#G.STUNS + 1] = { x = x, y = y, t = 0 }
            elseif ch == "k" or ch == "f" or ch == "p" or ch == "t" then G.ITEMS[#G.ITEMS + 1] = { k = ch, x = x, y = y, alive = true }
            elseif ch:match("[gGrdls]") then
                local kind = ({ g = "ghost", r = "grunt", d = "demon", l = "lobber", s = "sorc" })[ch:lower()]
                local lv = min(3, 1 + floor((i * 7 + j * 3) % 3) + G.tough)
                G.GENS[#G.GENS + 1] = { kind = kind, lv = lv, hp = lv * 3, i = i, j = j, x = x, y = y, t = rr(0.5, 2.5), alive = true, flash = 0 }
                MAP[j * LW + i + 1] = "G"
            end
        end
    end
    G.LW, G.LH = LW, LH
    G.death_t = (not L.treasure and (n >= 6 or G.tough > 0)) and max(12, 25 - 4 * G.tough) or nil
    P.fx, P.fy = 0, 1
    P.ox, P.oy = nil, nil
    G.phase = "play"; G.pt = 0
    G.next_level = n + 1
    G.banner_set((L.treasure and (L.name .. "  ·  Grab the gold!") or ("Level " .. n)) .. (G.tough > 0 and ("  ·  Round " .. (G.tough + 1)) or ""), 2.2)
end
G.load_level = load_level
function G.new_game_sim(hero)
    P.hero = hero or P.hero or 1
    G.score = 0; G.health = 2000; G.keys = 0; G.potions = 0; G.won = false; G.out = false
    P.alive = true; G.warned = false
    load_level(1)
end
local function H() return HEROES[P.hero] end
G.H = H
------------------------------------------------------------------ damage, pickups, potions
local function hurt(n)
    if not P.alive then return end
    G.health = G.health - n * H().armor
    G.hurt_t = 0.15
    if G.health <= 0 then G.health = 0; P.alive = false; G.phase = "dead"; G.pt = 0; sfx("die"); G.puff(WP(P.x, P.y, 0.4), { 1, .3, .2 }, 30) end
end
G.hurt = hurt
local PTS = { ghost = 10, grunt = 10, demon = 20, lobber = 20, sorc = 30, death = 1000 }
local function kill_mon(m, by)
    m.alive = false
    add_score(PTS[m.kind] * m.lv)
    sfx("kill"); G.puff(WP(m.x, m.y, 0.4), m.kind == "ghost" and { .8, .85, .95 } or { .6, .5, .4 }, 12)
end
local function hit_gen(g, dmg)
    g.hp = g.hp - dmg; g.flash = 1
    if g.hp <= 0 then
        g.alive = false; setc(g.i, g.j, "."); add_score(100 * g.lv); sfx("gen"); G.boom(WP(g.x, g.y, 0.4), false)
    else
        sfx("hit")
        g.lv = max(1, min(g.lv, math.ceil(g.hp / 3)))   -- damaged generators drop a level, like the arcade
    end
end
-- potion: everything on screen (and Death) is destroyed, generators take a heavy hit
local function smart_bomb(power, radius)
    sfx("bomb"); G.boom(WP(P.x, P.y, 1.0), true); G.shake = 0.8
    for _, m in ipairs(G.MON) do
        if m.alive and abs(m.x - P.x) < radius and abs(m.y - P.y) < radius * 0.7 then
            if m.kind ~= "death" or power >= 1 then kill_mon(m) end
        end
    end
    for _, g in ipairs(G.GENS) do if g.alive and abs(g.x - P.x) < radius and abs(g.y - P.y) < radius * 0.7 then hit_gen(g, 2 + H().magic * power) end end
    G.ESHOT = {}
end
local function pickup(it)
    it.alive = false
    if it.k == "k" then G.keys = G.keys + 1; add_score(100); sfx("key")
    elseif it.k == "f" then G.health = G.health + 100; add_score(10); sfx("food"); G.warned = false
    elseif it.k == "p" then G.potions = G.potions + 1; add_score(50); sfx("potion")
    elseif it.k == "t" then add_score(100); sfx("treasure") end
end
-- doors: a key opens the whole connected door run
local function open_door(i, j)
    if G.keys <= 0 then return false end
    G.keys = G.keys - 1; sfx("door"); add_score(10)
    local q = { { i, j } }
    while #q > 0 do
        local c = table.remove(q)
        if cell(c[1], c[2]) == "D" then
            setc(c[1], c[2], ".")
            for _, d in ipairs(G.DOORS) do if d.i == c[1] and d.j == c[2] then d.open = 0.001 end end
            q[#q + 1] = { c[1] + 1, c[2] }; q[#q + 1] = { c[1] - 1, c[2] }; q[#q + 1] = { c[1], c[2] + 1 }; q[#q + 1] = { c[1], c[2] - 1 }
        end
    end
    return true
end
------------------------------------------------------------------ monsters
local SPEED = { ghost = 2.4, grunt = 1.9, demon = 1.8, lobber = 1.6, sorc = 2.0, death = 2.2 }
local function spawn(kind, lv, x, y) G.MON[#G.MON + 1] = { kind = kind, lv = lv, hp = lv, x = x, y = y, alive = true, t = rr(0, 2), atk = 0, fire = rr(1, 3), vis = true, drained = 0, fx = 0, fy = -1 } end
G.spawn = spawn
local function los(x0, y0, x1, y1)
    local d = sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2); local n = max(1, math.ceil(d * 3))
    for k = 1, n - 1 do local t = k / n; if solid(floor(lerp(x0, x1, t)), floor(lerp(y0, y1, t))) then return false end end
    return true
end
local function mon_step(m, dt)
    m.t = m.t + dt
    local dx, dy = P.x - m.x, P.y - m.y
    local d = sqrt(dx * dx + dy * dy)
    if d > 14 or not P.alive then return end
    local sp = SPEED[m.kind] * dt
    local ux, uy = dx / max(d, 1e-3), dy / max(d, 1e-3)
    if m.kind == "lobber" and d < 4 then ux, uy = -ux, -uy end
    if m.kind == "sorc" then m.vis = (m.t % 2.4) < 1.4 end
    -- 8-way like the arcade: snap the chase direction to the nearest 45 degrees
    local a = math.atan2(uy, ux); a = math.floor(a / (PI / 4) + 0.5) * (PI / 4)
    local mx, my = cos(a) * sp, sin(a) * sp
    if not (m.kind == "lobber" and d > 3.5 and d < 5.5) then
        if move(m, mx, my, MR) then
            -- blocked: try the two neighbouring directions
            local ok = false
            for _, da in ipairs({ PI / 4, -PI / 4, PI / 2, -PI / 2 }) do
                local bx, by = cos(a + da) * sp, sin(a + da) * sp
                if not blocked(m.x + bx, m.y + by, MR) then m.x, m.y = m.x + bx, m.y + by; ok = true; break end
            end
        end
    end
    m.fx, m.fy = cos(a), sin(a)
    -- contact
    local touch = d < PR + MR + 0.04
    if touch then
        if m.kind == "ghost" then hurt(10 * m.lv); m.alive = false; sfx("hurt"); G.puff(WP(m.x, m.y, 0.4), { .8, .85, .95 }, 10); return
        elseif m.kind == "death" then
            local n = min(200 - m.drained, 60 * dt * 10)
            m.drained = m.drained + n; G.health = max(0, G.health - n); G.hurt_t = 0.15
            if (G.drain_s or 0) <= 0 then sfx("drain"); G.drain_s = 0.6 end
            if G.health <= 0 then hurt(1) end
            if m.drained >= 200 then m.alive = false; G.puff(WP(m.x, m.y, 0.5), { .2, .2, .25 }, 20) end
        else
            m.atk = m.atk - dt
            if m.atk <= 0 then m.atk = 0.5; m.swing = 1; hurt(({ grunt = 5, demon = 8, lobber = 3, sorc = 8 })[m.kind] * m.lv); sfx("hurt") end
        end
    end
    -- ranged attacks
    m.fire = m.fire - dt
    if m.kind == "demon" and m.fire <= 0 and d < 8 and los(m.x, m.y, P.x, P.y) then
        m.fire = rr(2, 3); m.swing = 1; G.ESHOT[#G.ESHOT + 1] = { k = "p_dfire", x = m.x, y = m.y, vx = ux * 6, vy = uy * 6, dmg = 10, lob = false }
    elseif m.kind == "lobber" and m.fire <= 0 and d < 7 then
        -- rocks are lobbed over walls to where you are standing
        m.fire = rr(2.2, 3); m.swing = 1; local T = 0.9
        G.ESHOT[#G.ESHOT + 1] = { k = "p_rock", x = m.x, y = m.y, vx = dx / T, vy = dy / T, dmg = 10, lob = true, t = 0, T = T }
    end
end
------------------------------------------------------------------ main step
function G.level_step(inp, dt)
    G.pt = G.pt + dt
    P.ox, P.oy = P.x, P.y
    for _, m in ipairs(G.MON) do m.ox, m.oy = m.x, m.y end
    for _, s in ipairs(G.SHOTS) do s.ox, s.oy = s.x, s.y end
    for _, s in ipairs(G.ESHOT) do s.ox, s.oy = s.x, s.y end
    G.hurt_t = max(0, (G.hurt_t or 0) - dt); G.drain_s = (G.drain_s or 0) - dt
    if G.phase == "dead" then if G.pt > 2.5 then G.out = true end; return end
    if G.phase == "exit" then
        if G.pt > 1.2 then load_level(G.next_level or (G.level + 1)); sfx("start") end
        return
    end
    -- health drains one point a second, like the arcade
    G.drain = (G.drain or 0) + dt
    if G.drain >= 1 then G.drain = G.drain - 1; G.health = G.health - 1; if G.health <= 0 then hurt(1) end end
    if G.health < 200 and not G.warned then G.warned = true; sfx("warn"); G.banner_set(H().name .. " Needs Food Badly", 2.5) end
    -- hero movement
    local mx, my = inp.mx, inp.my
    P.stun = max(0, (P.stun or 0) - dt); P.stun_cd = max(0, (P.stun_cd or 0) - dt)
    if P.stun > 0 then mx, my = 0, 0 end
    if mx ~= 0 or my ~= 0 then
        local l = sqrt(mx * mx + my * my); mx, my = mx / l, my / l
        P.fx, P.fy = mx, my
        local sp = H().speed * dt
        -- doors open when you walk into them holding a key
        local nx, ny = P.x + mx * (PR + 0.08), P.y + my * (PR + 0.08)
        local ci, cj = floor(nx), floor(ny)
        if cell(ci, cj) == "D" then open_door(ci, cj) end
        hero_move(P, mx * sp, my * sp, PR)
        P.walk = (P.walk or 0) + dt
    else P.walk = 0 end
    -- melee: walking into a monster or generator fights it
    P.melee = (P.melee or 0) - dt
    -- shots: one per press
    if inp.fire and #G.SHOTS < 2 and P.stun <= 0 then
        local h = H()
        G.SHOTS[#G.SHOTS + 1] = { x = P.x + P.fx * 0.3, y = P.y + P.fy * 0.3, px = P.x, py = P.y, vx = P.fx * h.sv, vy = P.fy * h.sv, dmg = h.shot, m = h.shotm, spin = 0 }
        sfx(h.id == "wiz" and "magic" or "shot"); P.atk_t = 1
        G.muzzle(WP(P.x + P.fx * 0.45, P.y + P.fy * 0.45, 0.5), h.id)
    end
    if inp.potion and G.potions > 0 then G.potions = G.potions - 1; smart_bomb(1, 10) end
    -- shots (swept in small steps)
    for i = #G.SHOTS, 1, -1 do
        local s = G.SHOTS[i]
        local gone = false
        local n = 4
        s.spin = s.spin + dt * 900
        for _ = 1, n do
            s.px, s.py = s.x, s.y
            s.x, s.y = s.x + s.vx * dt / n, s.y + s.vy * dt / n
            local ci, cj = floor(s.x), floor(s.y)
            local c = cell(ci, cj)
            if c == "G" then for _, g in ipairs(G.GENS) do if g.alive and g.i == ci and g.j == cj then hit_gen(g, s.dmg) end end; gone = true
            elseif c == "#" or c == "D" or c == "w" then gone = true; G.sparks(WP(s.px, s.py, 0.4), 5) end
            if not gone then
                for _, m in ipairs(G.MON) do
                    if m.alive and m.vis and m.kind ~= "death" and (m.x - s.x) ^ 2 + (m.y - s.y) ^ 2 < (MR + 0.12) ^ 2 then
                        m.hp = m.hp - s.dmg; gone = true
                        if m.hp <= 0 then kill_mon(m) else sfx("hit") end
                        break
                    end
                end
            end
            if not gone then
                for _, it in ipairs(G.ITEMS) do
                    if it.alive and it.k == "p" and (it.x - s.x) ^ 2 + (it.y - s.y) ^ 2 < 0.16 then it.alive = false; gone = true; smart_bomb(0.5, 5) end
                    -- shooting food destroys it, as in the arcade
                    if it.alive and it.k == "f" and (it.x - s.x) ^ 2 + (it.y - s.y) ^ 2 < 0.16 then it.alive = false; gone = true; G.puff(WP(it.x, it.y, 0.2), { .7, .4, .3 }, 8) end
                end
            end
            if gone then break end
        end
        if gone or abs(s.x - P.x) > 14 or abs(s.y - P.y) > 10 then table.remove(G.SHOTS, i) end
    end
    -- generators spawn while you are near
    local count = 0
    for _, m in ipairs(G.MON) do if m.alive then count = count + 1 end end
    for _, g in ipairs(G.GENS) do
        g.flash = max(0, g.flash - dt * 4)
        if g.alive and abs(g.x - P.x) < 11 and abs(g.y - P.y) < 8 then
            g.t = g.t - dt
            if g.t <= 0 and count < 70 then
                g.t = (rr(1.6, 2.8) - g.lv * 0.25) / (1 + 0.25 * G.tough)
                local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }
                local d = dirs[1 + floor(rand() * 8)]
                local x, y = g.x + d[1], g.y + d[2]
                if not blocked(x, y, MR) then spawn(g.kind, g.lv, x, y); count = count + 1; G.puff(WP(x, y, 0.3), { .5, .45, .42 }, 8) end
            end
        end
    end
    -- Death drifts in on the later levels
    if G.death_t then
        G.death_t = G.death_t - dt
        if G.death_t <= 0 then
            G.death_t = 40
            for _ = 1, 12 do
                local x, y = P.x + rr(-9, 9), P.y + rr(-7, 7)
                if not blocked(x, y, MR) and (x - P.x) ^ 2 + (y - P.y) ^ 2 > 25 then spawn("death", 1, x, y); break end
            end
        end
    end
    -- monsters
    for _, m in ipairs(G.MON) do if m.alive then mon_step(m, dt) end end
    -- simple separation so crowds don't stack (and never pushed into walls)
    for a = 1, #G.MON do
        local m = G.MON[a]
        if m.alive then
            for b = a + 1, min(#G.MON, a + 12) do
                local o = G.MON[b]
                if o.alive then
                    local dx, dy = o.x - m.x, o.y - m.y
                    local d2 = dx * dx + dy * dy
                    if d2 < (2 * MR) ^ 2 and d2 > 1e-6 then
                        local d = sqrt(d2); local push = (2 * MR - d) * 0.5
                        move(m, -dx / d * push, -dy / d * push, MR); move(o, dx / d * push, dy / d * push, MR)
                    end
                end
            end
            -- monsters never overlap the hero
            local dx, dy = m.x - P.x, m.y - P.y
            local d = sqrt(dx * dx + dy * dy)
            if d < PR + MR and d > 1e-4 then
                move(m, dx / d * (PR + MR - d), dy / d * (PR + MR - d), MR)
                if m.alive and m.kind ~= "death" and (P.melee <= 0) and (inp.mx ~= 0 or inp.my ~= 0) and (dx * P.fx + dy * P.fy) > 0 then
                    P.melee = 0.3; P.atk_t = 1; m.hp = m.hp - H().melee * 0.5; sfx("hit"); G.sparks(WP((m.x + P.x) / 2, (m.y + P.y) / 2, 0.5), 6)
                    if m.hp <= 0 then kill_mon(m) end
                end
            end
        end
    end
    -- melee against generators
    if (inp.mx ~= 0 or inp.my ~= 0) and P.melee <= 0 then
        local ci, cj = floor(P.x + P.fx * (PR + 0.1)), floor(P.y + P.fy * (PR + 0.1))
        if cell(ci, cj) == "G" then for _, g in ipairs(G.GENS) do if g.alive and g.i == ci and g.j == cj then P.melee = 0.35; P.atk_t = 1; hit_gen(g, H().melee * 0.5) end end end
    end
    for i = #G.MON, 1, -1 do if not G.MON[i].alive then table.remove(G.MON, i) end end
    -- enemy shots
    for i = #G.ESHOT, 1, -1 do
        local s = G.ESHOT[i]
        local gone = false
        if s.lob then
            s.t = s.t + dt; s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
            s.h = 0.4 + 2.2 * math.sin(PI * clamp(s.t / s.T, 0, 1))
            if s.t >= s.T then
                gone = true; G.puff(WP(s.x, s.y, 0.1), { .5, .48, .45 }, 8); G.dust(WP(s.x, s.y, 0.05), 10)
                if (s.x - P.x) ^ 2 + (s.y - P.y) ^ 2 < (PR + 0.25) ^ 2 then hurt(s.dmg); sfx("hurt") end
            end
        else
            s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt; s.h = 0.45
            if solid(floor(s.x), floor(s.y)) then gone = true; G.sparks(WP(s.x, s.y, 0.4), 5, { 1.6, .7, .3 })
            elseif (s.x - P.x) ^ 2 + (s.y - P.y) ^ 2 < (PR + 0.12) ^ 2 then gone = true; hurt(s.dmg); sfx("hurt") end
        end
        if gone then table.remove(G.ESHOT, i) end
    end
    -- items
    for _, it in ipairs(G.ITEMS) do if it.alive and (it.x - P.x) ^ 2 + (it.y - P.y) ^ 2 < (PR + 0.25) ^ 2 then pickup(it) end end
    -- doors animate open
    for _, d in ipairs(G.DOORS) do if d.open > 0 and d.open < 1 then d.open = min(1, d.open + dt * 3) end end
    -- trap tiles: stepping on one makes every trap wall on the floor vanish (shortcuts and sealed treasure open up)
    if not G.trapped then
        for _, t in ipairs(G.TRAPS) do
            if (t.x - P.x) ^ 2 + (t.y - P.y) ^ 2 < 0.16 then
                G.trapped = true; sfx("door"); G.shake = 0.35; G.banner_set("Trap!  The walls give way", 1.6)
                for j = 0, LH - 1 do for i = 0, LW - 1 do
                    if cell(i, j) == "w" then setc(i, j, "."); G.puff(WP(i + 0.5, j + 0.5, 0.5), { .55, .5, .45 }, 10); G.dust(WP(i + 0.5, j + 0.5, 0.05), 8) end
                end end
                break
            end
        end
    end
    -- stun tiles: a jolt that freezes the hero for a moment (and can't re-trigger straight away)
    for _, z in ipairs(G.STUNS) do
        z.t = max(0, z.t - dt)
        if P.stun_cd <= 0 and (z.x - P.x) ^ 2 + (z.y - P.y) ^ 2 < 0.12 then
            P.stun = 0.8; P.stun_cd = 2.0; z.t = 0.8; sfx("hurt"); G.hurt_t = 0.1
            G.sparks(WP(P.x, P.y, 0.3), 14, { 1.4, 1.3, .7 })
        end
    end
    -- treasure rooms run on a clock: when it runs out you are sent on without the bonus
    if G.ttime then
        G.ttime = G.ttime - dt
        if G.ttime <= 0 then
            G.ttime = 0; G.phase = "exit"; G.pt = 0; G.next_level = G.level + 1; sfx("warn"); G.banner_set("Time's Up", 1.2); return
        end
    end
    -- exits: the plain exit leads on one floor, a marked exit skips ahead
    for _, e in ipairs(G.EXITS) do
        local d2 = (e.x - P.x) ^ 2 + (e.y - P.y) ^ 2
        if e.jump and d2 < 9 and not e.told then e.told = true; G.banner_set("Exit to Level " .. e.to, 1.8) end
        if d2 < 0.2 then
            G.phase = "exit"; G.pt = 0; sfx("exit"); add_score(100 * G.level); G.next_level = e.to
            if G.ttime then local b = floor(G.ttime) * 100; add_score(b); G.banner_set("Treasure Bonus  " .. b, 1.2)
            else G.banner_set(e.jump and ("Exit to Level " .. e.to) or "Exit", 1.2) end
            G.ttime = nil
            break
        end
    end
end
G.puff, G.sparks, G.boom, G.flash = puff, sparks, boom, flash
------------------------------------------------------------------ world nodes
local function V(x, y, z) return vec3(x, y, z) end
G.shake = 0
local W = { lv = {}, doors = {} }
G.W = W   -- (tests)
local HR = {}
------------------------------------------------------------------ rigged characters: one node per segment (body, legs, arms, wings),
-- each carrying one mesh per material; joints are animated here (walk cycle, attacks, wing flaps, floating)
function G.rig_new(kind)
    local root = empty("rig_" .. kind, nil, HIDE)
    local r = { root = root, seg = {}, kind = kind, rot = {} }
    for _, sg in ipairs(G.RIG[kind]) do
        local n = empty(kind .. "_" .. sg.name, root, V(sg.piv[1], sg.piv[2], sg.piv[3]))
        for _, m in ipairs(sg.meshes) do local t = tpl("T_" .. m); if t and t.mesh then n:add_mesh_ref(t.mesh) end end
        r.seg[sg.name] = n
    end
    return r
end
local function jrot(r, name, x, y, z)
    local n = r.seg[name]; if not n then return end
    -- skip redundant writes (keeps motion vectors clean and saves Lua->engine calls)
    local k = r.rot[name]
    if k and abs(k[1] - x) < 0.05 and abs(k[2] - y) < 0.05 and abs(k[3] - z) < 0.05 then return end
    r.rot[name] = { x, y, z }; n:set_rotation(V(x, y, z))
end
-- pose: ph = walk phase (rad), amp = 0..1 walking, atk = 0..1 attack swing, t = clock, cast = 0..1 spell pose
function G.rig_pose(r, ph, amp, atk, t, cast)
    local k = r.kind
    local sw = sin(ph) * amp
    local strike = atk > 0 and -sin(atk * PI) * 105 or 0
    if k == "ghost" then
        jrot(r, "arm_l", -12 + 10 * sin(t * 3.1), 0, -6 * sin(t * 2.3)); jrot(r, "arm_r", -12 + 10 * sin(t * 3.1 + 1.7) + strike * 0.5, 0, 6 * sin(t * 2.3))
        return
    end
    if k == "sorc" or k == "death" then
        local lift = (k == "sorc") and (-35 - 55 * (cast or 0)) or -10
        jrot(r, "arm_l", lift + 8 * sin(t * 2.2) - sw * 10, 0, k == "sorc" and -12 * (cast or 0) or 0)
        jrot(r, "arm_r", (k == "death" and -18 + 16 * sin(t * 2.6) or lift + 8 * sin(t * 2.2 + 1)) + sw * 10 + strike, 0, k == "sorc" and 12 * (cast or 0) or 0)
        return
    end
    local legA = (k == "grunt" or k == "lobber") and 26 or 34
    jrot(r, "leg_l", sw * legA, 0, 0); jrot(r, "leg_r", -sw * legA, 0, 0)
    local armA = 26
    local idle = 3 * sin(t * 2.0)
    jrot(r, "arm_l", -sw * armA + idle, 0, 0)
    jrot(r, "arm_r", sw * armA - idle + strike, 0, 0)
    if k == "demon" then
        local f = 28 * sin(t * 10) + 10
        jrot(r, "wing_l", 0, -15, f); jrot(r, "wing_r", 0, 15, -f)
    end
end
local RIGP = {}
local function R_begin(kind) local p = RIGP[kind]; if not p then p = { r = {}, used = 0 }; RIGP[kind] = p end; p.used = 0 end
local function R_get(kind)
    local p = RIGP[kind]; if not p then R_begin(kind); p = RIGP[kind] end
    p.used = p.used + 1
    local r = p.r[p.used]; if not r then r = G.rig_new(kind); p.r[p.used] = r end
    return r
end
local function R_end(kind) local p = RIGP[kind]; if not p then return end; for i = p.used + 1, #p.r do local r = p.r[i]; if not r.hidden then r.hidden = true; r.root:set_position(HIDE) end end end
local function place_rig(r, pos, rot, sc) r.hidden = false; r.root:set_position(pos); r.root:set_rotation(rot); r.root:set_scale(sc) end
local function build_world()
    for i, L in ipairs(G.LEVELS) do
        W.lv[i] = { clone("lv" .. i .. "_wall", HIDE), clone("lv" .. i .. "_floor", HIDE) }
        if L.trapw then W.lv[i].tw = clone("lv" .. i .. "_trapw", HIDE) end
    end
    W.ex = {}
    for _, h in ipairs(G.HEROES) do HR[h.id] = G.rig_new(h.id) end
    W.sh = clone("shadow")
end
function G.reset_world() W.cur = nil end
local function show_level()
    if W.cur == G.load_id then return end
    W.cur = G.load_id
    for i, l in ipairs(W.lv) do
        for _, n in ipairs(l) do n:set_position(i == G.li and V(0, 0, 0) or HIDE) end
        if l.tw then l.tw:set_position(i == G.li and V(0, 0, 0) or HIDE) end
    end
    W.trapped = false
    for _, d in ipairs(W.doors) do d:set_position(HIDE) end
    for k, d in ipairs(G.DOORS) do
        local n = W.doors[k]; if not n then n = clone("door"); W.doors[k] = n end
        d.node = n
        -- bars run across the corridor: rotate when the door is in a north-south passage
        local ns = not G.solid(d.i, d.j + 1) or not G.solid(d.i, d.j - 1)
        n:set_rotation(V(0, ns and 0 or 90, 0))
    end
    for _, e in ipairs(W.ex) do for _, n in pairs(e) do n:set_position(HIDE) end end
    for k, e in ipairs(G.EXITS or {}) do
        local w = W.ex[k]; if not w then w = { a = clone("exit", HIDE), b = clone("exit_steps", HIDE), c = clone("exit_rim", HIDE) }; W.ex[k] = w end
        w.a:set_position(WP(e.x, e.y, 0.002)); w.b:set_position(WP(e.x, e.y, 0.004))
        w.c:set_position(e.jump and WP(e.x, e.y, 0.003) or HIDE)
    end
end
local ITEMM = { k = { "key" }, f = { "food_plate", "food_ham" }, p = { "potion", "potion_cork" }, t = { "chest", "chest_lid", "chest_band" } }
local MONK = { "ghost", "grunt", "demon", "lobber", "sorc", "death" }
local function render_world(dt)
    show_level()
    local P = G.P
    if G.trapped and not W.trapped then W.trapped = true; local l = W.lv[G.li]; if l and l.tw then l.tw:set_position(HIDE) end end
    -- trap and stun plates (a stun plate crackles while it is discharging)
    P_begin("trap_tile"); P_begin("stun_tile")
    for _, t in ipairs(G.TRAPS or {}) do if abs(t.x - P.x) < 14 and abs(t.y - P.y) < 11 then P_get("trap_tile"):set_position(WP(t.x, t.y, 0.003)) end end
    for _, z in ipairs(G.STUNS or {}) do
        if abs(z.x - P.x) < 14 and abs(z.y - P.y) < 11 then
            P_get("stun_tile"):set_position(WP(z.x, z.y, 0.003))
            if z.t > 0 and rand() < 0.25 then G.sparks(WP(z.x + rr(-.3, .3), z.y + rr(-.3, .3), 0.08), 2, { 1.3, 1.2, .6 }) end
        end
    end
    P_end("trap_tile"); P_end("stun_tile")
    if P.stun and P.stun > 0 and rand() < 0.2 then G.sparks(WP(P.x + rr(-.2, .2), P.y + rr(-.2, .2), 0.9), 2, { 1.3, 1.2, .6 }) end
    for _, d in ipairs(G.DOORS) do
        if d.node then d.node:set_position(d.open >= 1 and HIDE or WP(d.i + 0.5, d.j + 0.5, -d.open * 0.95)) end
    end
    -- items
    for _, list in pairs(ITEMM) do for _, mname in ipairs(list) do P_begin(mname) end end
    for _, it in ipairs(G.ITEMS) do
        if it.alive and abs(it.x - P.x) < 14 and abs(it.y - P.y) < 11 then
            for _, mname in ipairs(ITEMM[it.k]) do
                local n = P_get(mname); n:set_position(WP(it.x, it.y, it.k == "k" and 0.05 * sin(G.t * 3) or 0))
                n:set_rotation(V(0, it.k == "k" and G.t * 90 % 360 or 0, 0))
            end
        end
    end
    for _, list in pairs(ITEMM) do for _, mname in ipairs(list) do P_end(mname) end end
    -- generators (bigger = higher level)
    P_begin("gen"); P_begin("gen_bones")
    for _, g in ipairs(G.GENS) do
        if g.alive and abs(g.x - P.x) < 14 and abs(g.y - P.y) < 11 then
            local s = 0.75 + 0.12 * g.lv + g.flash * 0.06
            local a = P_get("gen"); a:set_position(WP(g.x, g.y, 0)); a:set_scale(V(s, s, s))
            local b = P_get("gen_bones"); b:set_position(WP(g.x, g.y, 0)); b:set_scale(V(s, s, s)); b:set_rotation(V(0, g.i * 37 % 360, 0))
        end
    end
    P_end("gen"); P_end("gen_bones")
    -- monsters (rigged, animated)
    for _, k in ipairs(MONK) do R_begin(k) end
    P_begin("shadow")
    for _, m in ipairs(G.MON) do
        if abs(m.x - P.x) < 14 and abs(m.y - P.y) < 11 and (m.vis or (G.t * 10) % 2 < 0.3) then
            local s = (0.85 + 0.1 * m.lv) * 1.2
            local yaw = math.deg(atan2(-m.fx, m.fy))
            local fly = m.kind == "ghost" or m.kind == "death" or m.kind == "sorc"
            local bob = fly and (0.06 + 0.05 * sin(m.t * 4)) or abs(sin(m.t * 8)) * 0.03
            if m.kind == "demon" then bob = 0.02 + 0.03 * sin(m.t * 10) end
            local mx, my = G.lerp_pos(m)
            local r = R_get(m.kind)
            place_rig(r, WP(mx, my, bob), V(fly and 0 or 6, yaw, 0), V(s, s, s))
            m.swing = max(0, (m.swing or 0) - dt * 3.2)
            G.rig_pose(r, m.t * (m.kind == "lobber" and 12 or 9), m.kind == "lobber" and 1 or 0.9, m.swing > 0 and (1 - m.swing) or 0, m.t, m.vis and 0.5 + 0.5 * sin(m.t * 2.6) or 1)
            local sh = P_get("shadow"); sh:set_position(WP(mx + 0.06, my - 0.05, 0.004)); sh:set_scale(V(0.4 * s, 1, 0.4 * s))
        end
    end
    -- hero (rigged): walk cycle, swing on shots and melee, lean into motion
    local h = G.H()
    local hx, hy = G.lerp_pos(P)
    local yaw = math.deg(atan2(-P.fx, P.fy))
    local moving = (P.walk or 0) > 0
    G.hamp = damp(G.hamp or 0, moving and 1 or 0, 12, dt)
    G.hph = (G.hph or 0) + dt * 11 * (h.speed / 3.8) * (moving and 1 or 0.3)
    P.atk_t = max(0, (P.atk_t or 0) - dt * 4)
    for id, r in pairs(HR) do
        local on = id == h.id and (P.alive or G.phase ~= "dead")
        if on then
            local bob = abs(sin(G.hph)) * 0.03 * G.hamp
            place_rig(r, WP(hx, hy, bob), V(7 * G.hamp, yaw, 0), V(1.25, 1.25, 1.25))
            G.rig_pose(r, G.hph, G.hamp, P.atk_t > 0 and (1 - P.atk_t) or 0, G.t, 0)
        elseif not r.hidden then r.hidden = true; r.root:set_position(HIDE) end
    end
    if P.alive then local sh = P_get("shadow"); sh:set_position(WP(hx + 0.06, hy - 0.05, 0.004)); sh:set_scale(V(0.42, 1, 0.42)) end
    for _, k in ipairs(MONK) do R_end(k) end
    P_end("shadow")
    G.render_showcase(dt)
    -- shots
    for _, k in ipairs({ "p_axe", "p_sword", "p_fire", "p_arrow", "p_rock", "p_dfire" }) do P_begin(k) end
    G.trail_t = (G.trail_t or 0) - dt
    local tr = G.trail_t <= 0; if tr then G.trail_t = 0.05 end
    for _, s in ipairs(G.SHOTS) do
        local sx, sy = G.lerp_pos(s)
        local n = P_get(s.m); n:set_position(WP(sx, sy, 0.45))
        if tr and s.m == "p_fire" then G.trail(WP(sx, sy, 0.45), { 1.6, .8, 2.0 }, 3) end
        local yaw = math.deg(atan2(-s.vx, s.vy))
        n:set_rotation(s.m == "p_axe" and V(0, yaw + s.spin, 0) or V(0, yaw, 0))
    end
    for _, s in ipairs(G.ESHOT) do
        local sx, sy = G.lerp_pos(s)
        P_get(s.k):set_position(WP(sx, sy, s.h or 0.45))
        if tr and s.k == "p_dfire" then G.trail(WP(sx, sy, s.h or 0.45), { 1.8, .7, .2 }, 3) end
    end
    for _, k in ipairs({ "p_axe", "p_sword", "p_fire", "p_arrow", "p_rock", "p_dfire" }) do P_end(k) end
end

-- showcase for screenshots/tests: every hero and monster in a row at G.showcase = {x, y}, camera close
local SHOW = {}
function G.render_showcase(dt)
    local sc = G.showcase
    local kinds = { "war", "val", "wiz", "elf", "ghost", "grunt", "demon", "lobber", "sorc", "death" }
    for i, k in ipairs(kinds) do
        local r = SHOW[k]; if not r then r = G.rig_new(k); SHOW[k] = r end
        if sc then
            local x, y = sc.x + (i - 5.5) * 0.95, sc.y
            local s = i <= 4 and 1.25 or 1.2
            place_rig(r, WP(x, y, (k == "ghost" or k == "sorc" or k == "death") and 0.08 or 0), V(0, 180 + (sc.yaw or 0), 0), V(s, s, s))
            G.rig_pose(r, G.t * 9, sc.walk and 1 or 0, (type(sc.atk) == "number") and sc.atk or (sc.atk and (G.t * 1.5 % 1) or 0), G.t, 0.6)
        elseif not r.hidden then r.hidden = true; r.root:set_position(HIDE) end
    end
end
------------------------------------------------------------------ camera: follows the hero over the maze
local function update_camera(dt)
    local P = G.P
    local c = G.cam
    local k = G.cam_snap and 1 or (1 - math.exp(-6 * dt)); G.cam_snap = false
    local tx, ty = G.lerp_pos(P)
    if G.state == "title" then tx, ty = G.LW / 2 + 8 * sin(G.t * 0.07), G.LH / 2 + 5 * sin(G.t * 0.05) end
    tx, ty = clamp(tx, 9.5, G.LW - 9.5), clamp(ty, 4.2, G.LH - 6.5)
    c.x, c.y = c.x + (tx - c.x) * k, c.y + (ty - c.y) * k
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.3 * SET:shake_scale()
    if G.showcase then
        local sc = G.showcase
        cam:set_position(WP(sc.x, sc.y - (sc.dist or 4.2), sc.h or 4.2)); cam:look_at(WP(sc.x, sc.y, 0.45)); return
    end
    cam:set_position(WP(c.x + a * sin(G.t * 53), c.y - 5.6 + a * cos(G.t * 61), 12.0))
    cam:look_at(WP(c.x, c.y + 0.4, 0))
end

------------------------------------------------------------------ collider debug overlay (F3)
G.DBG = { on = false, pool = {}, used = 0, w = 0.04 }
local DC = { me = { .2, 1, .3 }, enemy = { 1, .25, .2 }, wall = { .4, .7, 1 }, shot = { 1, .9, .3 }, item = { .3, .8, 1 }, gen = { 1, .5, .1 } }
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
local function dbox(x0, y0, x1, y1, col, h)
    h = h or 1.02
    local a, b, c, d = WP(x0, y0, h), WP(x1, y0, h), WP(x1, y1, h), WP(x0, y1, h)
    G.dbg_bar(a, b, col); G.dbg_bar(b, c, col); G.dbg_bar(c, d, col); G.dbg_bar(d, a, col)
end
local function dcircle(x, y, r, col, h, n)
    n = n or 12; h = h or 0.05
    for i = 0, n - 1 do
        local a0, a1 = i / n * 6.2832, (i + 1) / n * 6.2832
        G.dbg_bar(WP(x + cos(a0) * r, y + sin(a0) * r, h), WP(x + cos(a1) * r, y + sin(a1) * r, h), col)
    end
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and G.state ~= "title" then
        local P = G.P
        -- solid cells near the hero
        for j = floor(P.y) - 7, floor(P.y) + 8 do for i = floor(P.x) - 10, floor(P.x) + 10 do
            local c = G.cell(i, j)
            if c == "#" or c == "w" then
                -- only draw edges that face open floor
                if not G.solid(i - 1, j) then G.dbg_bar(WP(i, j, 1.02), WP(i, j + 1, 1.02), DC.wall) end
                if not G.solid(i + 1, j) then G.dbg_bar(WP(i + 1, j, 1.02), WP(i + 1, j + 1, 1.02), DC.wall) end
                if not G.solid(i, j - 1) then G.dbg_bar(WP(i, j, 1.02), WP(i + 1, j, 1.02), DC.wall) end
                if not G.solid(i, j + 1) then G.dbg_bar(WP(i, j + 1, 1.02), WP(i + 1, j + 1, 1.02), DC.wall) end
            elseif c == "D" then dbox(i, j, i + 1, j + 1, DC.wall, 0.95)
            elseif c == "G" then dbox(i, j, i + 1, j + 1, DC.gen, 0.7) end
        end end
        if P.alive then dcircle(P.x, P.y, G.PR, DC.me, 0.05, 14) end
        for _, m in ipairs(G.MON) do if abs(m.x - P.x) < 11 and abs(m.y - P.y) < 8 then dcircle(m.x, m.y, G.MR, DC.enemy, 0.05, 10) end end
        for _, s in ipairs(G.SHOTS) do G.dbg_bar(WP(s.px, s.py, 0.45), WP(s.x, s.y, 0.45), DC.shot) end
        for _, s in ipairs(G.ESHOT) do dcircle(s.x, s.y, s.lob and 0.25 or 0.12, DC.enemy, s.h or 0.45, 8) end
        for _, it in ipairs(G.ITEMS) do if it.alive and abs(it.x - P.x) < 11 and abs(it.y - P.y) < 8 then dcircle(it.x, it.y, 0.25, DC.item, 0.05, 8) end end
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
G.sel = 1
local HCOL = { war = { 1, .4, .3, 1 }, val = { .45, .65, 1, 1 }, wiz = { 1, .85, .3, 1 }, elf = { .45, .9, .45, 1 } }
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause") and not G.set_open
    local h = G.H()
    panel("lp", 20 * US, 20 * US, LW, 330 * US, play, 0.5)
    text("l1", h.name, 40 * US, 30 * US, LW - 40 * US, 40 * US, 1.3, HCOL[h.id], "left", play)
    text("l2", "Health", 40 * US, 76 * US, LW - 40 * US, 30 * US, 0.9, DIM, "left", play)
    text("l3", tostring(floor(G.health or 0)), 40 * US, 102 * US, LW - 40 * US, 56 * US, 2.0, (G.health or 0) < 200 and RED or WHITE, "left", play)
    text("l4", "Score  " .. tostring(G.score), 40 * US, 166 * US, LW - 40 * US, 36 * US, 1.1, WHITE, "left", play)
    text("l5", "Keys  " .. tostring(G.keys or 0) .. "     Potions  " .. tostring(G.potions or 0), 40 * US, 210 * US, LW - 40 * US, 36 * US, 1.0, GOLD, "left", play)
    text("l6", "High Score  " .. tostring(max(G.hiscore, G.score)), 40 * US, 254 * US, LW - 40 * US, 34 * US, 0.9, CYAN, "left", play)
    text("l7", G.L and ((G.L.treasure and G.L.name or ("Level " .. (G.level or 1))) .. ((G.tough or 0) > 0 and ("  ·  Round " .. (G.tough + 1)) or "")) or "", 40 * US, 294 * US, LW - 40 * US, 34 * US, 0.9, DIM, "left", play)
    local tt = G.ttime and G.phase == "play"
    text("ttime", tt and ("Treasure Room  ·  " .. math.ceil(G.ttime) .. " s") or "", 0, 24 * US, SW, 60 * US, 1.7, (G.ttime or 9) < 6 and RED or GOLD, "center", play and tt and true or false)
    -- health flashes red when hurt
    panel("hurt", 0, 0, SW, SH, play and (G.hurt_t or 0) > 0, 0.12, { 1, 0.1, 0.05, 0.6 })
    G.banner.t = (G.banner.t or 0) - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    text("ban", G.banner.text or "", 0, SH * 0.2, SW, 80 * US, 2.4, { 1, .88, .45, ba }, "center", play and G.banner.t > 0)
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 470 * US, SH * 0.06, 940 * US, SH * 0.8, title, 0.62)
    text("t_title", "Gauntlet Remix", 0, SH * 0.08, SW, 130 * US, 4.2, { 1, .55, .3, 1 }, "center", title)
    text("t_sub", "Choose your hero and fight down through the dungeon", 0, SH * 0.08 + 120 * US, SW, 40 * US, 1.0, DIM, "center", title)
    local CL = { "WASD / Arrows: move (8 ways)  ·  Space / J / Left Click: shoot (one per press)  ·  walk into monsters to fight",
        "Shift / X / Right Click: potion (destroys everything on screen)  ·  a key opens a door",
        "Health drains over time: eat food  ·  shoot generators to stop the monsters  ·  find the exit",
        "1-4 or Left / Right: choose hero  ·  P / Esc: pause  ·  O: settings  ·  M: mute  ·  F3: colliders" }
    for i, l in ipairs(CL) do text("t_c" .. i, l, SW / 2 - 460 * US, SH * 0.6 + (i - 1) * 34 * US, 920 * US, 34 * US, 0.88, DIM, "center", title) end
    local sel = G.HEROES[G.sel or 1]
    text("t_hero", sel.hero .. " the " .. sel.name .. string.format("   ·   armour %d  shot %d  fight %d  speed %d  magic %d",
        floor((1.2 - sel.armor) * 10 + 0.5), sel.shot, sel.melee, floor(sel.speed - 2), sel.magic), 0, SH * 0.6 + 140 * US, SW, 36 * US, 1.0, HCOL[sel.id], "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, GOLD, "center", pause)
    local over = st == "over" and not G.set_open
    panel("o_bg", SW / 2 - 400 * US, SH * 0.22, 800 * US, SH * 0.56, over, 0.78)
    text("o_t", "Game Over", 0, SH * 0.24, SW, 90 * US, 3.0, RED, "center", over)
    text("o_m", h.name .. " fell on " .. (G.L and G.L.name or ""), 0, SH * 0.24 + 92 * US, SW, 40 * US, 1.2, DIM, "center", over)
    text("o_s", "Score " .. tostring(G.score), 0, SH * 0.24 + 140 * US, SW, 44 * US, 1.4, WHITE, "center", over)
    local c = {}
    local yb = SH * 0.3
    c.hero = {}
    for i, hh in ipairs(G.HEROES) do
        local lab = (i == (G.sel or 1) and "> " or "") .. hh.name .. " (" .. i .. ")"
        c.hero[i] = button("b_h" .. i, lab, SW / 2 + (i - 2.5) * 222 * US, yb, title, 210)
    end
    c.start = button("b_start", "Start (Enter)", SW / 2 - 190 * US, yb + 80 * US, title, 300)
    c.jev = button("b_jev", "Jev", SW / 2 + 190 * US, yb + 80 * US, title, 300)
    c.set_t = button("b_set_t", "Settings (O)", SW / 2, yb + 156 * US, title)
    c.quit_app = button("b_quit_app", "Quit Game", SW / 2, yb + 232 * US, title)
    c.resume = button("b_resume", "Resume (P)", SW / 2, SH * 0.42, pause)
    c.set_p = button("b_set_p", "Settings (O)", SW / 2, SH * 0.42 + 76 * US, pause)
    c.quit = button("b_quit", "Quit to Title (Q)", SW / 2, SH * 0.42 + 152 * US, pause)
    local ov = over and (G.over_t or 0) > 1.2
    c.again = button("b_again", "Play Again (Enter)", SW / 2, SH * 0.52, ov)
    c.title = button("b_title", "Title (Esc)", SW / 2, SH * 0.52 + 76 * US, ov)
    return c
end

------------------------------------------------------------------ Jev. Direction holds and shot/potion pulses sit in G.vk,
-- which held() already treats as a key. apply() only stores that and returns.
local JEV_MOVE = {
    n = { 0, 1 },
    ne = { 1, 1 },
    e = { 1, 0 },
    se = { 1, -1 },
    s = { 0, -1 },
    sw = { -1, -1 },
    w = { -1, 0 },
    nw = { -1, 1 },
    stop = { 0, 0 },
}
local JEV_ACTIONS = {
    { id = "n", description = "Hold north" },
    { id = "ne", description = "Hold northeast" },
    { id = "e", description = "Hold east" },
    { id = "se", description = "Hold southeast" },
    { id = "s", description = "Hold south" },
    { id = "sw", description = "Hold southwest" },
    { id = "w", description = "Hold west" },
    { id = "nw", description = "Hold northwest" },
    { id = "stop", description = "Stop moving" },
    { id = "shot", description = "Shoot once" },
    { id = "potion", description = "Use a potion once" },
}
local JEV_KEYS = {
    "W", "A", "S", "D", "Up", "Down", "Left", "Right",
    "Space", "J", "X", "LeftShift", "RightShift",
}
local JevHold = {
    q = { Space = 0, X = 0 },
    down = {},
    raw = {},
    seen = false,
}
local jev

local function clear_move()
    G.vk = G.vk or {}
    G.vk.W = nil
    G.vk.A = nil
    G.vk.S = nil
    G.vk.D = nil
    G.vk.Up = nil
    G.vk.Down = nil
    G.vk.Left = nil
    G.vk.Right = nil
end

local function clear_jev_input()
    clear_move()
    JevHold.q.Space = 0
    JevHold.q.X = 0
    JevHold.down.Space = nil
    JevHold.down.X = nil
    G.vk.Space = nil
    G.vk.X = nil
end

local function apply_jev(id)
    local step = JEV_MOVE[id]
    if step then
        clear_move()
        if step[2] > 0 then
            G.vk.W = true
        elseif step[2] < 0 then
            G.vk.S = true
        end
        if step[1] > 0 then
            G.vk.D = true
        elseif step[1] < 0 then
            G.vk.A = true
        end
        JevHold.q.Space = JevHold.q.Space + 1
        return
    end

    if id == "shot" then
        JevHold.q.Space = JevHold.q.Space + 1
        return
    end
    if id == "potion" then
        JevHold.q.X = JevHold.q.X + 1
    end
end

-- A pulse is one virtual key-down, then a release on the next frame so edge() can fire again.
local function arm_pulses()
    local play = G.state == "play" and not G.set_open
    G.vk = G.vk or {}
    for _, key in ipairs({ "Space", "X" }) do
        if JevHold.down[key] or not play then
            G.vk[key] = nil
            JevHold.down[key] = nil
        elseif JevHold.q[key] > 0 then
            G.vk[key] = true
            JevHold.down[key] = true
            JevHold.q[key] = JevHold.q[key] - 1
        end
    end
end

local function human_edge()
    local hit = false
    for _, key in ipairs(JEV_KEYS) do
        local ok, down = pcall(input.is_key_down_raw, key)
        down = ok and down and true or false
        if JevHold.seen and down and not JevHold.raw[key] then
            hit = true
        end
        JevHold.raw[key] = down
    end
    JevHold.seen = true
    return hit
end

local function nearest_monster()
    local px = G.P and G.P.x or 0
    local py = G.P and G.P.y or 0
    local best
    local bd
    for _, m in ipairs(G.MON or {}) do
        if m.alive ~= false then
            local d = (m.x - px) * (m.x - px) + (m.y - py) * (m.y - py)
            if not bd or d < bd then
                best = m
                bd = d
            end
        end
    end
    if not best then
        return px, py, 0, 0
    end
    return px, py, best.x, best.y
end

------------------------------------------------------------------ flow
local function to_title()
    if jev then
        jev:begin_human()
    end
    G.state = "title"
    G.new_game_sim(G.sel or 1); G.reset_world()
    music("title")
end
G.to_title = to_title
local function new_game()
    G.reset_world(); G.new_game_sim(G.sel or 1)
    G.state = "play"; G.cam_snap = true
    music("level"); sfx("start")
end
G.new_game = new_game
local function game_over()
    G.state = "over"
    G.over_t = 0
    music(nil)
    sfx("gameover")
    clear_jev_input()
    if jev and jev:assisted() then
        return
    end
    if G.score > G.hiscore then
        G.hiscore = G.score
        save_hi()
    end
end
local acc = 0
local mprev = { x = 0, y = 0 }
local q = { fire = false, potion = false }
local lmouse_prev, rmouse_prev = true, true
local function update(dt)
    jev:tick(dt)

    flush_mats()
    dt = clamp(dt, 0, 0.1)   -- a negative frame time (timer hitch) would make every damp() explode
    G.t = G.t + dt; G.dt = dt
    arm_pulses()
    local k = { ret = edge("Return"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), qk = edge("Q"), f3 = edge("F3"),
        space = edge("Space"), j = edge("J"), x = edge("X"), sh = edge("LeftShift"), sh2 = edge("RightShift"),
        k1 = edge("1"), k2 = edge("2"), k3 = edge("3"), k4 = edge("4"), lf = edge("Left"), rt = edge("Right"), a = edge("A"), d = edge("D") }
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
        local s0 = G.sel or 1
        for i = 1, 4 do if k["k" .. i] or c.hero[i] then G.sel = i end end
        if k.lf or k.a then G.sel = (s0 + 2) % 4 + 1 elseif k.rt or k.d then G.sel = s0 % 4 + 1 end
        if G.sel ~= s0 then sfx("click"); G.P.hero = G.sel end
        if k.ret or k.space or c.start then
            sfx("click")
            G.new_game()
        elseif c.jev then
            sfx("click")
            local ok = jev:start()
            lclick, rclick = false, false
            if not ok then
                local err = tostring(jev:error() or "Jev failed")
                G.banner_set(err, 6)
                pe_log("[GT] " .. err)
            end
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click")
        else
            if k.space or k.j or lclick then q.fire = true end
            if k.x or k.sh or k.sh2 or rclick then q.potion = true end
        end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.qk or c.quit then to_title() end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then
                sfx("click")
                G.new_game()
            elseif k.esc or c.title then
                to_title()
            end
        end
    end
    st = G.state
    if st == "play" and not G.set_open then
        local mx = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0)
        local my = (any("Up", "W") and 1 or 0) - (any("Down", "S") and 1 or 0)
        if (mx ~= 0 or my ~= 0) and (mx ~= mprev.x or my ~= mprev.y) and G.P.alive then sfx("step") end
        mprev.x, mprev.y = mx, my
        if G.autoplay then mx, my, q.fire = G.autoplay_fn() end
        local inp = { mx = mx, my = my }
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 4 do
            inp.fire, inp.potion = q.fire, q.potion; q.fire, q.potion = false, false
            G.level_step(inp, FR)
            acc = acc - FR; n = n + 1
        end
        if acc > FR * 4 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if G.out and G.state == "play" then G.out = false; game_over() end
        G.step_t = (G.step_t or 0) - dt
        if (mx ~= 0 or my ~= 0) and G.step_t <= 0 and G.P.alive then G.step_t = 0.32; sfx("step"); G.dust(WP(G.P.x, G.P.y, 0.03), 3) end
    else AL = 1 end
    render_world(dt)
    update_camera(dt)
    update_lights(dt, G.P.x, G.P.y)
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end
-- debug autopilot for tests/screenshots only: walks the shortest path to the exit (G.ap_jump: the skip-ahead exit),
-- shooting generators that block the way and monsters that get close
local function ap_path(P, tx, ty)
    local LW = G.LW
    local si, sj, ti, tj = floor(P.x), floor(P.y), floor(tx), floor(ty)
    local prev, q, h = { [sj * LW + si] = -1 }, { sj * LW + si }, 1
    while h <= #q do
        local c = q[h]; h = h + 1
        if c == tj * LW + ti then break end
        local i, j = c % LW, floor(c / LW)
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local ni, nj = i + d[1], j + d[2]; local k = nj * LW + ni
            local ch = G.cell(ni, nj)
            if prev[k] == nil and (not G.solid(ni, nj) or ch == "G") then prev[k] = c; q[#q + 1] = k end
        end
    end
    local c = tj * LW + ti; if prev[c] == nil then return nil end
    local path = {}
    while c ~= -1 do table.insert(path, 1, c); c = prev[c] end
    return path
end
function G.autoplay_fn()
    local P = G.P
    G.ap_t = (G.ap_t or 0) + 1
    local tgt = G.exit
    if G.ap_jump then for _, e in ipairs(G.EXITS) do if e.jump then tgt = e end end end
    if not tgt then return 0, 0, false end
    if G.ap_t % 10 == 1 or not G.ap_path or G.ap_lv ~= G.level then G.ap_path = ap_path(P, tgt.x, tgt.y); G.ap_lv = G.level end
    local best, bd
    for _, m in ipairs(G.MON) do local d = (m.x - P.x) ^ 2 + (m.y - P.y) ^ 2; if not bd or d < bd then best, bd = m, d end end
    if best and bd < 6 and G.ap_t % 8 == 0 then local d = sqrt(bd); P.fx, P.fy = (best.x - P.x) / d, (best.y - P.y) / d; return 0, 0, true end
    local path = G.ap_path; if not path or #path < 1 then return 0, 0, false end
    local LW = G.LW
    local nk = path[min(2, #path)]
    local ni, nj = nk % LW, floor(nk / LW)
    if G.cell(ni, nj) == "G" then
        local dx, dy = ni + 0.5 - P.x, nj + 0.5 - P.y; local d = sqrt(dx * dx + dy * dy)
        P.fx, P.fy = dx / d, dy / d; return 0, 0, G.ap_t % 6 == 0
    end
    if floor(P.x) == ni and floor(P.y) == nj and #path > 2 then table.remove(path, 1); nk = path[2]; ni, nj = nk % LW, floor(nk / LW) end
    local mx, my = ni + 0.5 - P.x, nj + 0.5 - P.y
    local ax = abs(mx) > 0.12 and (mx > 0 and 1 or -1) or 0
    local ay = abs(my) > 0.12 and (my > 0 and 1 or -1) or 0
    return ax, ay, false
end

local jev_source = assert(fs.read("Scripts/jev_auto.lua"), "Missing Scripts/jev_auto.lua")
local JevAuto = assert(load(jev_source, "@Scripts/jev_auto.lua", "t", _ENV))()
jev = JevAuto.attach({
    port = 9139,
    id = "gauntlet-remix",
    description = "Gauntlet Remix. North is +y and east is +x. The offered action walks toward the nearest monster and shoots. Prefer the higher action score.",
    playing = function()
        return G.state == "play" and not G.set_open
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
    observe = function()
        local hx, hy, mx, my = nearest_monster()
        return {
            hero_x = hx,
            hero_y = hy,
            monster_x = mx,
            monster_y = my,
            health = G.health or 0,
            score = G.score or 0,
        }
    end,
    actions = function()
        local hx, hy, mx, my = nearest_monster()
        local dx = mx - hx
        local dy = my - hy
        if dx == 0 and dy == 0 then
            return { { id = "n", description = "Walk north and shoot.", score = 1 } }
        end
        local best_id = "n"
        local best = -1e18
        for id, step in pairs(JEV_MOVE) do
            if id ~= "stop" then
                local dot = step[1] * dx + step[2] * dy
                if dot > best then
                    best = dot
                    best_id = id
                end
            end
        end
        return { { id = best_id, description = "Walk toward the monster and shoot.", score = best } }
    end,
    apply = apply_jev,
    reset = function(seed)
        clear_jev_input()
        math.randomseed(seed)
        new_game()
    end,
    on_human = clear_jev_input,
})
G.new_game = function()
    jev:begin_human()
    new_game()
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_world()
to_title()
G.update = update; G.SET = SET
hooks { update = update }
pe_log("[GT] ready")
