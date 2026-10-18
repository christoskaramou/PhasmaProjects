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
