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
