------------------------------------------------------------------ render setup (common/RENDER_SETTINGS.md: TAA on, smooth bloom)
local function S(k, v) pcall(settings.set, k, v) end
local ss = scene.add_empty_node("CMSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
S("taa", true); S("cas_sharpening", false); S("fxaa", false); S("motion_blur", false); S("dof", false)
S("hdr", true)
S("bloom", true); S("bloom_strength", 0.42); S("bloom_range", 1.2)
S("tonemapping", true)
S("ssao", true); S("ssao_radius", 0.5); S("ssao_intensity", 0.9)
S("ssr", false)
S("fog", true); S("fog_density", 0.0018); S("fog_start", 60.0)
S("shadows", true); S("shadow_map_size", 2048); S("shadow_distance", 60.0); S("shadow_filter_radius", 1.5)
S("render_scale", 1.0)
S("IBL", true); S("IBL_intensity", 0.85)
S("color_grading", true); S("color_grading_saturation", 1.3); S("color_grading_contrast", 1.15)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "Options", subtitle = "Crowd Master", file = "Save/settings.cfg", music = true,
    click = function() sfx("click") end, defaults = { master = 0.5 },
    theme = { accent = { 0.25, 0.6, 1, 1 }, accent2 = { 1, 0.75, 0.2, 1 }, panel = { 0.07, 0.1, 0.18, 0.94 }, row = { 0.14, 0.2, 0.34, 0.8 },
        text = { 0.94, 0.96, 1, 1 }, dim = { 0.7, 0.76, 0.88, 1 }, selected_text = { 1, 1, 1, 1 } } })
SET:apply()
local function PS() return SET:particle_scale() end

------------------------------------------------------------------ palette {base, emissive, rough, metal, alpha}
local TEAM = {
    b = { { .16, .46, 1.0 }, { .0, .01, .04 }, .42, 0 },  -- pawn (blue)
    v = { { .45, .26, .98 }, { .01, .0, .04 }, .35, .1 }, -- brute (violet)
    y = { { 1.0, .74, .18 }, { .05, .03, 0 }, .28, .55 }, -- giant (gold)
    w = { { 1.0, .5, .12 }, { .04, .015, 0 }, .35, .2 },  -- boss breaker (orange)
    r = { { .95, .2, .22 }, { .04, 0, 0 }, .42, 0 },     -- enemy
    g = { { .62, .65, .7 }, { 0, 0, 0 }, .55, 0 },       -- captive
}
local PAL = {
    king = { { .9, .16, .18 }, { .03, 0, 0 }, .38, .05 }, crown = { { 1, .78, .2 }, { .08, .05, 0 }, .2, .9 }, club = { { .5, .32, .18 }, { 0, 0, 0 }, .7 },
    c_trk = { { 1, 1, 1 }, { 0, 0, 0 }, .55 }, c_trk2 = { { 1, 1, 1 }, { 0, 0, 0 }, .55 }, c_rail = { { .97, .97, 1 }, { .02, .02, .02 }, .35 },
    c_side = { { .5, .62, .82 }, { 0, 0, 0 }, .6 },
    c_step0 = { { .98, .36, .36 }, { 0, 0, 0 }, .35 }, c_step1 = { { 1, .62, .22 }, { 0, 0, 0 }, .35 }, c_step2 = { { 1, .86, .25 }, { 0, 0, 0 }, .35 },
    c_step3 = { { .36, .82, .45 }, { 0, 0, 0 }, .35 }, c_step4 = { { .3, .6, 1 }, { 0, 0, 0 }, .35 },
    c_oil = { { 1, 1, 1 }, { 0, 0, 0 }, .06, .3 }, c_mud = { { 1, 1, 1 }, { 0, 0, 0 }, .55 }, c_gravel = { { 1, 1, 1 }, { 0, 0, 0 }, .9 },
    c_thorn = { { 1, 1, 1 }, { 0, 0, 0 }, .85 }, c_ice = { { 1, 1, 1 }, { .03, .05, .06 }, .08, .05 }, c_warn = { { 1, 1, 1 }, { 0, 0, 0 }, .5 },
    c_glassb = { { .32, .66, 1 }, { .1, .26, .6 }, .18, 0 }, c_glassr = { { 1, .4, .4 }, { .5, .1, .1 }, .18, 0 },
    c_glassp = { { 1, .82, .3 }, { .5, .34, .05 }, .18, 0 },
    c_white = { { .96, .96, .98 }, { 0, 0, 0 }, .35 }, c_metal = { { .7, .72, .76 }, { 0, 0, 0 }, .25, .9 }, c_stone = { { 1, 1, 1 }, { 0, 0, 0 }, .85 },
    c_wood = { { .62, .42, .24 }, { 0, 0, 0 }, .7 }, c_gold = { { 1, .78, .22 }, { .06, .04, 0 }, .2, .95 }, c_dark = { { .08, .09, .12 }, { 0, 0, 0 }, .8 },
    c_water = { { 1, 1, 1 }, { 0, 0, 0 }, .12, 0 }, c_sand = { { 1, 1, 1 }, { 0, 0, 0 }, .9 }, c_grass = { { 1, 1, 1 }, { 0, 0, 0 }, .9 },
    c_redpaint = { { .92, .2, .2 }, { .02, 0, 0 }, .3, .1 }, c_finish = { { 1, 1, 1 }, { 0, 0, 0 }, .5 }, c_cloth = { { .95, .3, .3 }, { 0, 0, 0 }, .8 },
    post = { { .97, .97, 1 }, { .02, .02, .02 }, .3 }, post_warn = { { 1, 1, 1 }, { 0, 0, 0 }, .35 }, lamp = { { 1, .9, .5 }, { 1.4, 1.0, .3 }, .3 },
    spin_post = { { .3, .32, .38 }, { 0, 0, 0 }, .35, .7 }, spin_bar = { { .95, .22, .2 }, { .03, 0, 0 }, .25, .2 },
    saw = { { .9, .92, .95 }, { .02, .02, .02 }, .3, .6 }, saw_hub = { { .95, .25, .2 }, { 0, 0, 0 }, .3, .4 },
    hammer_handle = { { .55, .36, .2 }, { 0, 0, 0 }, .7 }, hammer_head = { { .92, .25, .22 }, { .02, 0, 0 }, .3, .3 },
    roller = { { .35, .36, .42 }, { 0, 0, 0 }, .35, .8 }, spikes = { { .85, .86, .9 }, { 0, 0, 0 }, .2, 1 },
    coin = { { 1, .8, .2 }, { .25, .16, 0 }, .2, 1 }, chest = { { 1, .78, .25 }, { .06, .04, 0 }, .25, .9 },
    trunk = { { .48, .33, .2 }, { 0, 0, 0 }, .85 }, foliage = { { .3, .7, .3 }, { 0, .01, 0 }, .7 }, pine = { { .16, .45, .28 }, { 0, .005, 0 }, .75 },
    rock = { { .62, .6, .58 }, { 0, 0, 0 }, .85 }, island = { { 1, 1, 1 }, { 0, 0, 0 }, .9 }, mountain = { { .5, .58, .55 }, { 0, 0, 0 }, .95 },
    snowcap = { { .95, .97, 1 }, { .02, .02, .03 }, .6 }, bush = { { .32, .66, .3 }, { 0, .01, 0 }, .7 }, thornspk = { { .4, .3, .2 }, { 0, 0, 0 }, .7 },
    tower = { { 1, 1, 1 }, { 0, 0, 0 }, .8 }, roof = { { .85, .22, .22 }, { .02, 0, 0 }, .5 }, flag = { { .95, .25, .25 }, { .03, 0, 0 }, .8 },
    pole = { { .8, .8, .84 }, { 0, 0, 0 }, .3, .8 },
    cage = { { .55, .38, .22 }, { 0, 0, 0 }, .7 }, crate = { { .72, .52, .3 }, { 0, 0, 0 }, .75 }, chute = { { .98, .98, 1 }, { .03, .03, .03 }, .7 },
    beach = { { 1, 1, 1 }, { 0, 0, 0 }, .9 }, mesa = { { .82, .5, .32 }, { 0, 0, 0 }, .9 }, railr = { { .97, .97, 1 }, { .02, .02, .02 }, .3, .1 },
    palm = { { .55, .4, .26 }, { 0, 0, 0 }, .85 }, fronds = { { .3, .66, .25 }, { 0, .01, 0 }, .7 }, cactus = { { .3, .6, .32 }, { 0, .01, 0 }, .65 },
}
local function paint_templates()
    for col, v in pairs(TEAM) do
        for _, p in ipairs({ "0", "1", "2", "3", "i", "c" }) do paint(tnode("man_" .. col .. p), v[1], v[2], v[3], v[4]) end
    end
    for name, v in pairs(PAL) do paint(tnode(name), v[1], v[2], v[3], v[4], v[5]) end
    for _, k in ipairs({ "oil", "mud", "gravel", "thorn", "ice", "warn", "finish", "sand", "grass", "stone" }) do mtex(tnode("c_" .. k), "base_color", "Textures/" .. k .. ".png") end
    mtex(tnode("c_trk"), "base_color", "Textures/trk.png"); mtex(tnode("c_trk2"), "base_color", "Textures/trk2.png")
    mtex(tnode("post_warn"), "base_color", "Textures/post_warn.png")
    mtex(tnode("island"), "base_color", "Textures/grass.png"); mtex(tnode("beach"), "base_color", "Textures/sand.png")
    mtex(tnode("tower"), "base_color", "Textures/stone.png")
    pcall(_mds, tnode("flag"), true); pcall(_mds, tnode("chute"), true)
    for name in pairs(TPL) do local n = tnode(name); if n then n:set_position(HIDE) end end
end

------------------------------------------------------------------ worlds (sky, light, sea, island + foliage colours)
local WORLDS = {
    { key = "meadow", name = "Meadow Isles", sky = "day.hdr", sun = { vec3(-0.35, -0.75, 0.55), vec3(1, .96, .9), 3.2 },
        water = { .1, .48, .92 }, island = { .75, 1, .7 }, beach = { 1, .95, .85 }, foliage = { .32, .72, .3 }, pine = { .16, .45, .28 }, rock = { .62, .6, .58 },
        mount = { .48, .6, .55 }, side = { .5, .62, .82 }, trk = { .95, .97, 1.02 }, rail = { 1, .84, .5 }, snow = false, ibl = 0.85 },
    { key = "canyon", name = "Sunbaked Canyon", sky = "canyon.hdr", sun = { vec3(-0.5, -0.65, 0.5), vec3(1, .9, .75), 3.4 },
        water = { .08, .55, .7 }, island = { 1.15, .85, .55 }, beach = { 1.05, .9, .7 }, foliage = { .45, .66, .25 }, pine = { .3, .5, .22 }, rock = { .78, .5, .34 },
        mount = { .8, .48, .3 }, side = { .82, .55, .4 }, trk = { 1.04, 1, .94 }, rail = { 1, .7, .52 }, snow = false, ibl = 0.8 },
    { key = "frost", name = "Frost Bay", sky = "frost.hdr", sun = { vec3(-0.3, -0.6, 0.6), vec3(.92, .96, 1), 3.0 },
        water = { .2, .5, .85 }, island = { 1.45, 1.5, 1.55 }, beach = { 1.3, 1.35, 1.4 }, foliage = { .85, .92, .98 }, pine = { .14, .38, .3 }, rock = { .6, .65, .72 },
        mount = { .7, .76, .86 }, side = { .55, .7, .9 }, trk = { .97, 1, 1.04 }, rail = { .68, .85, 1 }, snow = true, ibl = 0.95 },
    { key = "ember", name = "Ember Coast", sky = "ember.hdr", sun = { vec3(-0.6, -0.42, 0.62), vec3(1, .78, .58), 3.3 },
        water = { .16, .24, .52 }, island = { .9, .62, .5 }, beach = { 1, .8, .65 }, foliage = { .95, .5, .22 }, pine = { .7, .3, .18 }, rock = { .42, .36, .38 },
        mount = { .42, .32, .38 }, side = { .7, .45, .5 }, trk = { 1.03, .97, .95 }, rail = { 1, .66, .58 }, snow = false, ibl = 0.8 },
}
G.WORLDS = WORLDS
G.world_key = nil
local function set_world(w)
    if G.world_key == w.key then return end
    G.world_key = w.key
    pcall(skybox.load, w.sky)
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, w.sun[1], w.sun[2], w.sun[3])
    S("IBL_intensity", w.ibl)
    local function tint(name, c, r, m) local n = tnode(name); if n then mset(n, "base_color", vec4(c[1], c[2], c[3], 1)); if r then mset(n, "roughness", r) end end end
    tint("c_water", w.water); tint("island", w.island); tint("beach", w.beach); tint("foliage", w.foliage); tint("bush", w.foliage)
    tint("pine", w.pine); tint("rock", w.rock); tint("mountain", w.mount); tint("c_side", w.side); tint("c_trk", w.trk); tint("c_trk2", w.trk)
    tint("mesa", w.mount); tint("fronds", w.foliage); tint("c_rail", w.rail); tint("railr", w.rail)
end

------------------------------------------------------------------ lights: flashes that ride on events
local LT = { flash = {} }
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    for i = 1, 3 do LT.flash[i] = { idx = add_point(), t = 1, life = 1 }; set_point(LT.flash[i].idx, HIDE, vec3(1, 1, 1), 0, 1) end
end
G.flash_next = 1
local function flash(x, y, z, col, power, life, rad)
    local f = LT.flash[G.flash_next]; if not f then return end
    G.flash_next = G.flash_next % #LT.flash + 1
    f.t, f.life, f.p, f.col, f.power, f.rad = 0, life or 0.3, vec3(x, y, z), vec3(col[1], col[2], col[3]), power or 40, rad or 8
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
G.fx_light = function(pos, col, power, life, radius) flash(pos.x, pos.y, pos.z, { col.x or col[1], col.y or col[2], col.z or col[3] }, power, life, radius) end

------------------------------------------------------------------ FX: particles over Scripts/Lib/particles.lua (premultiplied textures, screen blend)
local FX = { tex = {}, scale = 1 }
G.FX = FX
FX.lib = load(fs.read("Scripts/Lib/particles.lua"), "@particles.lua")().new({
    scale = PS, gain = 1, light = function(pos, col, power, life, radius) if G.fx_light then G.fx_light(pos, col, power, life, radius) end end })
FX.tex = FX.lib.tex
for _, k in ipairs({ "dust", "foam", "soft", "ring", "spark", "smoke", "debris", "ember", "fire" }) do
    if not FX.tex[k] then
        local ok, idx = pcall(particles.load_texture, "Textures/fx/" .. k .. ".png")
        FX.tex[k] = (ok and type(idx) == "number") and idx or 0
    end
end
local BOOK = { fire = { 4, 4 }, smoke = { 4, 4 }, debris = { 2, 2 } }
local function fxv(t) return vec3(t[1], t[2], t[3]) end
function FX.emit(tex, x, y, z, o)
    local n = max(1, floor((o.n or 8) * PS() + 0.5))
    local c0, c1 = o.c0 or { 1, 1, 1 }, o.c1 or { 0, 0, 0 }
    local ok, id = pcall(particles.emit_burst, {
        position = vec3(x, y, z), velocity = o.vel and fxv(o.vel) or vec3(0, 0, 0),
        color_start = vec4(c0[1], c0[2], c0[3], 1), color_end = vec4(c1[1], c1[2], c1[3], 0.02), count = n,
        size_min = o.s0 or 0.2, size_max = o.s1 or 0.4, life_min = o.l0 or 0.4, life_max = o.l1 or 0.8,
        spawn_radius = o.r or 0.2, noise_strength = o.sp or 2, drag = o.drag or 1.5,
        gravity = o.grav and fxv(o.grav) or vec3(0, 0, 0),
        texture_index = FX.tex[tex] or 0, orientation = o.flat and "horizontal" or (o.stretch and "velocity" or "billboard"),
        cleanup_delay = (o.l1 or 0.8) + 1.0,
    })
    local b = BOOK[tex]
    if ok and b and id then pcall(particles.set_emitter, id, { anim_cols = b[1], anim_rows = b[2], anim_speed = o.anim or (1 / (o.l1 or 0.8)), interpolate = true }) end
end
local function sc(c, k) return { c[1] * k, c[2] * k, c[3] * k } end
-- world x here is WORLD x (callers convert lane x with wx())
function FX.puff(x, y, z, col, k)       -- unit pops in / vanishes: soft coloured puff + tiny sparkle
    k = k or 1
    FX.emit("soft", x, y, z, { n = 2 * k, c0 = sc(col, 0.9), c1 = { 0, 0, 0 }, s0 = 0.35, s1 = 0.7, l0 = 0.18, l1 = 0.35, r = 0.15, sp = 1.5, drag = 3, grav = { 0, 1.5, 0 } })
end
function FX.dust(x, y, z, col, k, size)
    k = k or 1; size = size or 1
    FX.emit("dust", x, y, z, { n = 2 + 3 * k, c0 = sc(col, k), c1 = { 0, 0, 0 }, s0 = 0.5 * size, s1 = 1.1 * size, l0 = 0.45, l1 = 0.9, r = 0.35 * size, sp = 2.2, drag = 2.6, grav = { 0, 0.6, 0 } })
end
function FX.grit(x, y, z, col, n, vel)
    FX.emit("debris", x, y, z, { n = n or 6, vel = vel, c0 = col, c1 = sc(col, 0.3), s0 = 0.08, s1 = 0.18, l0 = 0.4, l1 = 0.8, r = 0.25, sp = 6, drag = 0.7, grav = { 0, -16, 0 }, anim = 0.01 })
end
function FX.sparks(x, y, z, n, vel, spread, col)
    col = col or { 2.0, 1.5, 0.8 }
    FX.emit("spark", x, y, z, { n = n or 14, vel = vel, c0 = col, c1 = { 0.5, 0.15, 0.02 }, s0 = 0.07, s1 = 0.14, l0 = 0.18, l1 = 0.45, r = 0.1, sp = spread or 9, drag = 1.8, grav = { 0, -9, 0 }, stretch = true })
end
function FX.confetti(x, y, z, n, size)
    size = size or 1
    local cols = { { 1.2, .35, .35 }, { .35, .7, 1.3 }, { 1.3, 1.0, .3 }, { .4, 1.1, .5 }, { 1.0, .5, 1.2 } }
    for i, c in ipairs(cols) do
        FX.emit("debris", x, y, z, { n = (n or 30) / 5, vel = { 0, 7 * size, 0 }, c0 = c, c1 = sc(c, 0.6), s0 = 0.1 * size, s1 = 0.2 * size, l0 = 1.2, l1 = 2.2,
            r = 0.6 * size, sp = 7 * size, drag = 1.6, grav = { 0, -5, 0 }, anim = 0.4 })
    end
end
function FX.flash(x, y, z, size, col)
    FX.emit("soft", x, y, z, { n = 1 / max(PS(), 0.01), c0 = col or { 1.4, 1.2, 0.8 }, c1 = { 0, 0, 0 }, s0 = size, s1 = size * 1.1, l0 = 0.1, l1 = 0.16, r = 0, sp = 0, drag = 0 })
end
function FX.ring(x, y, z, size, col, flat)
    FX.emit("ring", x, y, z, { n = 1 / max(PS(), 0.01), c0 = col or { 0.6, 0.6, 0.6 }, c1 = { 0, 0, 0 }, s0 = size, s1 = size, l0 = 0.3, l1 = 0.35, r = 0, sp = 0, flat = flat })
end
function FX.spray(x, y, z, k, size)
    k = k or 1; size = size or 1
    FX.emit("foam", x, y, z, { n = 3 + 3 * k, vel = { 0, 5, 0 }, c0 = { 0.8 * k, 0.88 * k, 0.95 * k }, c1 = { 0, 0, 0 }, s0 = 0.4 * size, s1 = 1.0 * size,
        l0 = 0.4, l1 = 0.9, r = 0.4 * size, sp = 3, drag = 1.5, grav = { 0, -9, 0 } })
end
function FX.coin(x, y, z)
    FX.emit("spark", x, y, z, { n = 5, vel = { 0, 3, 0 }, c0 = { 2.0, 1.6, 0.5 }, c1 = { 0.4, 0.25, 0 }, s0 = 0.05, s1 = 0.1, l0 = 0.25, l1 = 0.45, r = 0.2, sp = 4, drag = 2, grav = { 0, -4, 0 }, stretch = true })
end
function FX.smoke(x, y, z, k, size)
    k = k or 1; size = size or 1
    FX.emit("smoke", x, y, z, { n = 2 + 2 * k, c0 = { 0.55 * k, 0.55 * k, 0.56 * k }, c1 = { 0, 0, 0 }, s0 = 0.8 * size, s1 = 1.7 * size, l0 = 0.8, l1 = 1.6, r = 0.4 * size, sp = 1.4, drag = 2.2, grav = { 0, 1.2, 0 } })
end
function FX.glow_trail(x, y, z, col)   -- gate pass shimmer
    FX.emit("ember", x, y, z, { n = 10, vel = { 0, 2.5, 0 }, c0 = col, c1 = { 0, 0, 0 }, s0 = 0.08, s1 = 0.18, l0 = 0.5, l1 = 1.0, r = 2.0, sp = 2.5, drag = 1.2, grav = { 0, 1.5, 0 } })
end
function FX.shatter(x, y, z, col)      -- gate panel bursts into glassy shards flying forward
    for i = -1, 1 do
        FX.emit("debris", x + i * 0.9, y + 0.3 * i, z, { n = 9, vel = { 0, 3.5, 6 }, c0 = col, c1 = sc(col, 0.4), s0 = 0.12, s1 = 0.3, l0 = 0.5, l1 = 1.0,
            r = 0.8, sp = 7, drag = 0.9, grav = { 0, -14, 0 }, anim = 0.02 })
    end
    FX.emit("spark", x, y, z, { n = 12, vel = { 0, 2, 4 }, c0 = { 2, 2, 2 }, c1 = sc(col, 0.5), s0 = 0.05, s1 = 0.1, l0 = 0.2, l1 = 0.45, r = 1.2, sp = 8, drag = 1.5, grav = { 0, -6, 0 }, stretch = true })
end
function FX.boom(x, y, z, size)
    FX.lib:explosion(vec3(x, y, z), { size = size or 1, smoke = true, debris = { .45, .32, .22 }, spark_grav = -9 })
end
