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
