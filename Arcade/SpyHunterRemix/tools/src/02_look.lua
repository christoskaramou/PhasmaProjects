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
