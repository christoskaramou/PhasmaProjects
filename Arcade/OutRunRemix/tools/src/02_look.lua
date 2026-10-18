------------------------------------------------------------------ palette {base, emissive, rough, metal}
local PAL = {
    car_body = { { .78, .03, .03 }, { .02, 0, 0 }, .22, .35 }, car_under = { { .05, .05, .05 }, { 0, 0, 0 }, .8 },
    car_strake = { { .04, .04, .04 }, { 0, 0, 0 }, .4 }, car_grille = { { .06, .06, .06 }, { 0, 0, 0 }, .4, .3 },
    car_tail = { { .9, .1, .08 }, { .9, .06, .03 }, .3 }, car_head = { { .95, .95, .9 }, { .4, .4, .35 }, .2 },
    car_glass = { { .25, .3, .35 }, { 0, 0, 0 }, .05, .6 }, car_frame = { { .08, .08, .08 }, { 0, 0, 0 }, .3, .5 },
    car_seat = { { .62, .42, .25 }, { 0, 0, 0 }, .6 }, car_cabin = { { .08, .07, .06 }, { 0, 0, 0 }, .8 },
    car_wheelin = { { .1, .1, .1 }, { 0, 0, 0 }, .5 }, car_mirror = { { .78, .03, .03 }, { .02, 0, 0 }, .22, .35 },
    car_tire = { { .05, .05, .05 }, { 0, 0, 0 }, .85 }, car_rim = { { .75, .76, .8 }, { 0, 0, 0 }, .25, .9 },
    car_shadow = { { .09, .09, .08 }, { 0, 0, 0 }, 1 },
    drv_skin = { { .95, .7, .55 }, { .01, .005, .005 }, .55 }, drv_hair = { { .08, .05, .03 }, { 0, 0, 0 }, .6 },
    pas_hair = { { .98, .85, .45 }, { .03, .02, 0 }, .5 }, drv_shirt = { { .92, .92, .9 }, { .01, .01, .01 }, .7 },
    tr_beetle = { { .95, .78, .1 }, { .02, .015, 0 }, .3, .2 }, tr_vette = { { .15, .3, .8 }, { 0, .005, .02 }, .25, .35 },
    tr_cab = { { .85, .85, .88 }, { .01, .01, .01 }, .4, .2 }, tr_box = { { .92, .9, .85 }, { .01, .01, .01 }, .6 },
    tr_glass = { { .15, .18, .22 }, { 0, 0, 0 }, .05, .6 }, tr_wind = { { .15, .18, .22 }, { 0, 0, 0 }, .05, .6 }, tr_lamp = { { .9, .1, .08 }, { .8, .05, .02 }, .3 },
    road = { { .9, .9, .9 }, { 0, 0, 0 }, .85 }, rumble_r = { { .8, .08, .06 }, { .02, 0, 0 }, .6 }, rumble_w = { { .92, .92, .92 }, { .02, .02, .02 }, .6 },
    ground = { { 1, 1, 1 }, { 0, 0, 0 }, .95 }, divider = { { .85, .85, .85 }, { 0, 0, 0 }, .5 }, horizon = { { 0, 0, 0 }, { 1, 1, 1 }, 1 },
    palm_trunk = { { .48, .36, .24 }, { 0, 0, 0 }, .85 }, palm_leaves = { { .2, .55, .18 }, { .005, .02, .005 }, .6 },
    bush = { { .22, .45, .16 }, { 0, .01, 0 }, .8 }, rock = { { .55, .5, .45 }, { 0, 0, 0 }, .9 }, cliff = { { .62, .36, .24 }, { 0, 0, 0 }, .95 },
    pine_trunk = { { .35, .23, .15 }, { 0, 0, 0 }, .9 }, pine_leaves = { { .1, .32, .15 }, { 0, .01, 0 }, .8 }, pine_snow = { { .8, .85, .88 }, { .03, .03, .04 }, .7 },
    cactus = { { .28, .5, .22 }, { 0, .01, 0 }, .7 }, bld_0 = { { 1, 1, 1 }, { 0, 0, 0 }, .7 }, bld_1 = { { 1, 1, 1 }, { 0, 0, 0 }, .7 },
    bld_2 = { { 1, 1, 1 }, { 0, 0, 0 }, .7 }, roof = { { .6, .22, .14 }, { 0, 0, 0 }, .7 },
    windmill = { { .88, .85, .78 }, { 0, 0, 0 }, .7 }, blades = { { .45, .3, .2 }, { 0, 0, 0 }, .7 },
    column = { { .9, .88, .82 }, { .01, .01, .01 }, .6 }, vine = { { .25, .42, .15 }, { 0, .01, 0 }, .8 },
    lamp = { { .3, .32, .35 }, { 0, 0, 0 }, .4, .7 }, fence = { { .85, .85, .85 }, { 0, 0, 0 }, .5, .3 },
    sign_post = { { .5, .5, .5 }, { 0, 0, 0 }, .4, .6 }, sign_board = { { 1, 1, 1 }, { .25, .25, .25 }, .5 }, sign_board_r = { { 1, 1, 1 }, { .25, .25, .25 }, .5 },
    arch = { { .85, .85, .88 }, { .01, .01, .01 }, .5, .3 }, ban_start = { { 1, 1, 1 }, { .35, .35, .35 }, .5 },
    ban_check = { { 1, 1, 1 }, { .35, .35, .35 }, .5 }, ban_goal = { { 1, 1, 1 }, { .35, .35, .35 }, .5 },
    deb_red = { { .78, .03, .03 }, { .02, 0, 0 }, .3, .3 }, deb_dark = { { .06, .06, .06 }, { 0, 0, 0 }, .6 },
    flagman = { { .2, .2, .25 }, { 0, 0, 0 }, .7 }, flag = { { 1, 1, 1 }, { .2, .2, .2 }, .6 },
}
local function paint_templates()
    for name, v in pairs(PAL) do paint(tnode(name), v[1], v[2], v[3], v[4]) end
    mtex(tnode("road"), "base_color", "Textures/road.png")
    for _, k in ipairs({ "bld_0", "bld_1", "bld_2" }) do mtex(tnode(k), "base_color", "Textures/facade.png") end
    mtex(tnode("sign_board"), "base_color", "Textures/sign_curve.png"); mtex(tnode("sign_board_r"), "base_color", "Textures/sign_curve_r.png")
    for _, k in ipairs({ "ban_start", "ban_check", "ban_goal" }) do mtex(tnode(k), "base_color", "Textures/" .. k .. ".png") end
    mtex(tnode("flag"), "base_color", "Textures/flag.png")
    pcall(_mds, tnode("horizon"), true); pcall(_mds, tnode("flag"), true)
    for name in pairs(PAL) do local n = tnode(name); if n then n:set_position(HIDE) end end
end
G.theme_key = nil
local function set_theme(th)
    if G.theme_key == th.key then return end
    G.theme_key = th.key
    mtex(tnode("ground"), "base_color", "Textures/gr_" .. th.ground .. ".png")
    mtex(tnode("horizon"), "emissive", "Textures/hz_" .. th.sky .. ".png")
    if G.farplane then paint(G.farplane, th.far, { 0, 0, 0 }, 1, 0) end
end

------------------------------------------------------------------ lights (sun + fill that ride with the car)
local LT = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(-0.35, -0.8, 0.45), vec3(1.0, 0.96, 0.9), 1.5)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    LT.key = addp(vec3(0, 20, 0), vec3(1.0, 0.96, 0.9), 50, 60)
    LT.fill = addp(vec3(0, 6, 0), vec3(0.85, 0.9, 1.0), 25, 30)
    LT.flash = {}
    for i = 1, 3 do LT.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1 } end
end
G.LT = LT
G.flash_next = 1
local function flash(p, col, power, life, rad)
    local f = LT.flash[G.flash_next]; G.flash_next = G.flash_next % #LT.flash + 1
    f.t, f.life, f.p, f.col, f.power, f.rad = 0, life or 0.3, p, vec3(col[1], col[2], col[3]), power or 40, rad or 7
end
local function update_lights(dt, carp)
    set_point(LT.key, vec3(carp.x - 8, carp.y + 18, carp.z - 6), vec3(1.0, 0.96, 0.9), 50, 60)
    set_point(LT.fill, vec3(carp.x + 4, carp.y + 5, carp.z - 9), vec3(0.85, 0.9, 1.0), 25, 30)
    for _, f in ipairs(LT.flash) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = 1 - clamp(f.t / f.life, 0, 1)
            set_point(f.idx, f.p, f.col, f.power * k * k, f.rad)
            if f.t >= f.life then set_point(f.idx, HIDE, f.col, 0, 1) end
        end
    end
end

------------------------------------------------------------------ particles (x, y, z world)
local function PS() return SET:particle_scale() end
local function burst(x, y, z, o)
    pcall(particles.emit_burst, {
        position = vec3(x, y, z), velocity = o.vel or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = max(1, floor((o.count or 30) * PS())),
        size_min = o.smin or 0.05, size_max = o.smax or 0.14, life_min = o.lmin or 0.25, life_max = o.lmax or 0.7,
        spawn_radius = o.radius or 0.3, noise_strength = o.spread or 10, drag = o.drag or 2.0,
        gravity = o.grav or vec3(0, 0, 0), cleanup_delay = 3.0,
    })
end
local function sparks(x, y, z, col, n, spread, radius)
    burst(x, y, z, { c0 = vec4(col[1] * 1.6 + .4, col[2] * 1.6 + .4, col[3] * 1.6 + .4, 1), c1 = vec4(col[1], col[2], col[3], 0), count = n or 24,
        smin = .07, smax = .18, lmin = .25, lmax = .6, radius = radius or .3, spread = spread or 14, drag = 2.2, grav = vec3(0, -10, 0) })
end
local function smoke(x, y, z, n, r)
    burst(x, y, z, { c0 = vec4(.35, .33, .3, .7), c1 = vec4(.2, .2, .2, 0), count = n or 10, smin = .25, smax = .5, lmin = .5, lmax = 1.1,
        radius = r or .5, spread = 3, drag = 2.5, grav = vec3(0, 2.2, 0) })
end
local function fire_puff(x, z, n)
    burst(x, 0.8, z, { c0 = vec4(1.8, 1.0, .3, 1), c1 = vec4(.9, .2, .05, 0), count = n or 8, smin = .18, smax = .4, lmin = .2, lmax = .45,
        radius = .6, spread = 5, drag = 3, grav = vec3(0, 4, 0) })
end

------------------------------------------------------------------ score state
G.score, G.hiscore = 0, 0
pcall(function() local s = fs.read("Save/outrun_hiscore.txt"); if s then G.hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, "Save/outrun_hiscore.txt", tostring(G.hiscore)) end
local function add_score(n) G.score = G.score + n end
