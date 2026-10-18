------------------------------------------------------------------ palette {base, emissive, rough, metal}
local BRICK = { W = { .92, .92, .9 }, O = { 1, .5, .12 }, C = { .2, .8, .95 }, G = { .2, .8, .3 }, R = { .9, .15, .12 },
    B = { .15, .3, .95 }, P = { .95, .3, .75 }, Y = { 1, .85, .15 }, S = { .8, .8, .85 }, X = { 1, .78, .3 } }
G.BRICK = BRICK
local CAPC = { S = { 1, .5, .1 }, C = { .2, .8, .3 }, L = { .9, .15, .12 }, E = { .15, .35, .95 }, D = { .2, .8, .95 }, B = { .95, .3, .75 }, P = { .7, .7, .75 } }
G.CAPC = CAPC
local PAL = {
    vaus_mid = { { .8, .82, .88 }, { .05, .05, .06 }, .3, .45 }, vaus_strip = { { .15, .4, .9 }, { .05, .12, .3 }, .3, .4 },
    vaus_cap = { { .85, .12, .1 }, { .05, 0, 0 }, .3, .5 }, vaus_gun = { { .6, .62, .68 }, { .03, .03, .03 }, .35, .45 },
    ball = { { .95, .95, 1 }, { .45, .45, .5 }, .25, .3 }, shadow = { { .01, .01, .02 }, { 0, 0, 0 }, 1 },
    wall_side = { { .7, .72, .78 }, { .03, .03, .04 }, .3, .5 }, wall_top = { { .7, .72, .78 }, { .03, .03, .04 }, .3, .5 },
    wall_ring = { { .3, .32, .38 }, { 0, 0, 0 }, .35, .9 }, wall_elbow = { { .7, .72, .78 }, { .03, .03, .04 }, .3, .5 }, elbow_collar = { { .3, .32, .38 }, { 0, 0, 0 }, .35, .9 }, corner = { { .45, .47, .55 }, { 0, 0, 0 }, .3, .9 },
    gate = { { .4, .42, .5 }, { 0, 0, 0 }, .35, .8 }, gate_door = { { .15, .16, .2 }, { 0, 0, 0 }, .4, .6 },
    warp = { { .9, .4, .8 }, { .5, .2, .45 }, .3, .2 }, floor = { { .62, .62, .66 }, { 0, 0, 0 }, .85 },
    en_cone = { { .25, .55, .95 }, { .02, .05, .1 }, .3, .6 }, en_pyr = { { .3, .85, .35 }, { .02, .08, .02 }, .35, .3 },
    en_orb = { { .9, .25, .2 }, { .08, .02, .02 }, .25, .4 }, en_cube = { { .95, .75, .2 }, { .08, .06, .01 }, .3, .6 },
    debris = { { .8, .8, .8 }, { 0, 0, 0 }, .5, .2 }, laser = { { 1, .5, .3 }, { 1.2, .45, .2 }, .4 },
    doh_head = { { .55, .45, .32 }, { 0, 0, 0 }, .85, 0 }, doh_brow = { { .5, .4, .28 }, { 0, 0, 0 }, .85 },
    doh_nose = { { .58, .48, .34 }, { 0, 0, 0 }, .85 }, doh_eye = { { .05, .03, .02 }, { .5, .12, .05 }, .5 },
    doh_mouth = { { .05, .03, .02 }, { 0, 0, 0 }, .6 }, doh_shot = { { .9, .3, .2 }, { .9, .25, .1 }, .4 },
}
for k, c in pairs(BRICK) do PAL["brick_" .. k] = { c, (k == "S" or k == "X") and { c[1] * .12, c[2] * .1, c[3] * .08 } or { 0, 0, 0 }, (k == "S" or k == "X") and .28 or .42, (k == "S" or k == "X") and .45 or .05 } end
for k, c in pairs(CAPC) do PAL["cap_" .. k] = { c, { c[1] * .05, c[2] * .05, c[3] * .05 }, .3, .3 }; PAL["lbl_" .. k] = { { 1, 1, 1 }, { .2, .2, .2 }, .5 } end
local function paint_templates()
    for name, v in pairs(PAL) do paint(tnode(name), v[1], v[2], v[3], v[4]) end
    mtex(tnode("brick_X"), "base_color", "Textures/gold.png")
    for k in pairs(CAPC) do mtex(tnode("lbl_" .. k), "base_color", "Textures/lbl_" .. k .. ".png") end
    for name in pairs(PAL) do local n = tnode(name); if n then n:set_position(HIDE) end end
end
G.set_bg = function(n, i) mtex(n, "base_color", "Textures/bg" .. i .. ".png") end

------------------------------------------------------------------ lights
local LT = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(-0.35, -0.85, 0.4), vec3(1.0, 0.97, 0.92), 2.4)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    LT.key = addp(WP(0, 3, 6), vec3(1.0, 0.95, 0.88), 26, 22)
    LT.fill = addp(WP(0, 12, 5), vec3(0.75, 0.82, 1.0), 20, 22)
    LT.ball = addp(HIDE, vec3(0.7, 0.85, 1), 0, 3)
    LT.sheen = addp(HIDE, vec3(1, 0.95, 0.85), 0, 6)
    LT.flash = {}
    for i = 1, 4 do LT.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1 } end
end
G.flash_next = 1
local function flash(p, col, power, life, rad)
    local f = LT.flash[G.flash_next]; G.flash_next = G.flash_next % #LT.flash + 1
    f.t, f.life, f.p, f.col, f.power, f.rad = 0, life or 0.3, p, vec3(col[1], col[2], col[3]), power or 30, rad or 4
end
local function update_lights(dt, bp)
    -- a slow glint sweeps over the brick wall so gold reads as polished metal
    set_point(LT.sheen, WP(6 * sin(G.t * 0.45), 11.5 + 1.5 * sin(G.t * 0.31), 2.2), vec3(1, 0.95, 0.85), 16, 6)
    set_point(LT.ball, bp or HIDE, vec3(0.7, 0.85, 1), bp and 5 or 0, 2.5)
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
local function brick_burst(p, c)
    burst(p, { c0 = vec4(c[1] * 1.4, c[2] * 1.4, c[3] * 1.4, 1), c1 = vec4(c[1] * .5, c[2] * .5, c[3] * .5, 0), count = 18, smin = .04, smax = .1,
        lmin = .25, lmax = .6, radius = .3, spread = 6, drag = 2, grav = vec3(0, -6, 0) })
end
local function sparks(p, n, col)
    col = col or { 1.6, 1.4, 1.0 }
    burst(p, { c0 = vec4(col[1], col[2], col[3], 1), c1 = vec4(1, .5, .2, 0), count = n or 8, smin = .025, smax = .06, lmin = .12, lmax = .3, radius = .05, spread = 9, drag = 2.5 })
end
local function boom(p, big)
    burst(p, { c0 = vec4(2.0, 1.2, .5, 1), c1 = vec4(.5, .2, .1, 0), count = big and 80 or 26, smin = .06, smax = big and .3 or .16, lmin = .3, lmax = big and 1.4 or .7, radius = big and 1.2 or .3, spread = big and 7 or 6, drag = 1.6 })
    burst(p, { c0 = vec4(.4, .4, .42, .6), c1 = vec4(.2, .2, .22, 0), count = big and 30 or 8, smin = .15, smax = big and .5 or .25, lmin = .5, lmax = 1.2, radius = big and 1 or .2, spread = 2, drag = 2, grav = vec3(0, 1, 0) })
    flash(p, { 1, .7, .4 }, big and 80 or 25, big and 0.8 or 0.25, big and 9 or 4)
end

------------------------------------------------------------------ score state
G.score, G.hiscore = 0, 0
pcall(function() local s = fs.read("Save/arkanoid_hiscore.txt"); if s then G.hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, "Save/arkanoid_hiscore.txt", tostring(G.hiscore)) end
local function add_score(n) G.score = G.score + n end
G.banner = { text = "", t = 0 }
function G.banner_set(t, d) G.banner.text = t; G.banner.t = d or 1.5 end
PAL.brick_X = { { 1, .8, .5 }, { .3, .19, .04 }, .2, .5 }
PAL.brick_Y = { { 1, .93, .38 }, { 0, 0, 0 }, .85, 0 }
