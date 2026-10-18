------------------------------------------------------------------ palette {base, emissive, rough, metal}
local function paint_templates()
    local P = {
        bm_helmet = { { .93, .93, .95 }, { .02, .02, .02 }, .35 }, bm_face = { { 1, .72, .62 }, { .02, .01, .01 }, .5 },
        bm_eye = { { .03, .03, .06 }, { 0, 0, 0 }, .2 }, bm_antenna = { { .85, .85, .9 }, { 0, 0, 0 }, .4, .3 },
        bm_knob = { { 1, .3, .55 }, { .12, .02, .05 }, .3 }, bm_body = { { .15, .35, .9 }, { .01, .02, .05 }, .45 },
        bm_belt = { { .1, .1, .12 }, { 0, 0, 0 }, .4 }, bm_arm = { { .15, .35, .9 }, { .01, .02, .05 }, .45 },
        bm_glove = { { .95, .95, .97 }, { .02, .02, .02 }, .45 }, bm_leg = { { .15, .35, .9 }, { .01, .02, .05 }, .45 },
        bm_boot = { { 1, .35, .55 }, { .03, .01, .015 }, .45 },
        bomb = { { .07, .07, .1 }, { 0, 0, 0 }, .22, .2 }, bomb_cap = { { .5, .5, .55 }, { 0, 0, 0 }, .3, .8 },
        bomb_fuse = { { .85, .75, .55 }, { .05, .03, 0 }, .7 }, bomb_shine = { { 1, 1, 1 }, { 1.2, 1.2, 1.2 }, .1 },
        floor = { { .9, .9, .9 }, { 0, 0, 0 }, .85 }, pillar = { { .55, .56, .6 }, { .005, .005, .005 }, .75 },
        pillar_top = { { .62, .63, .67 }, { .005, .005, .005 }, .65 }, brick = { { .85, .8, .78 }, { .005, .003, .003 }, .8 }, brick_chunk = { { .78, .7, .66 }, { .004, .002, .002 }, .85 },
        border = { { .7, .7, .74 }, { 0, 0, 0 }, .8 },
        door_frame = { { .55, .55, .6 }, { 0, 0, 0 }, .5, .6 }, door = { { .3, .3, .36 }, { .02, .02, .03 }, .4, .5 },
        door_light = { { .9, .95, 1 }, { .6, .8, 1.1 }, .3 },
        fl_core = { { 1, .75, .3 }, { 1.7, .95, .25 }, .5 }, fl_arm = { { 1, .35, .05 }, { 1.35, .36, .03 }, .5 },
        fl_end = { { 1, .35, .05 }, { 1.35, .36, .03 }, .5 }, fl_inner = { { 1, .8, .5 }, { 1.5, .95, .4 }, .5 },
        debris = { { .7, .38, .25 }, { 0, 0, 0 }, .8 },
        en_eye = { { .97, .97, .97 }, { .05, .05, .05 }, .3 }, en_pupil = { { .02, .02, .04 }, { 0, 0, 0 }, .2 },
        en_ballom = { { .95, .42, .12 }, { .02, .01, 0 }, .35 }, en_onil = { { .3, .55, 1 }, { .02, .04, .08 }, .3 },
        en_dahl = { { .95, .45, .2 }, { .04, .02, 0 }, .5 }, en_minvo = { { 1, .45, .65 }, { .06, .02, .04 }, .4 },
        en_doria = { { .35, .45, .95 }, { .02, .03, .07 }, .25 }, en_ovape = { { .7, .45, .95 }, { .05, .03, .08 }, .35 },
        en_pass = { { 1, .65, .1 }, { .05, .03, 0 }, .5 }, en_pontan = { { 1, .82, .2 }, { .1, .07, .01 }, .25, .8 },
        en_stripe = { { .15, .1, .05 }, { 0, 0, 0 }, .5 },
        shadow = { { .02, .03, .02 }, { 0, 0, 0 }, 1 }, ring = { { 1, .8, .4 }, { 1.4, 1.0, .4 }, .4 },
    }
    for _, k in ipairs({ "bombs", "fire", "speed", "wallpass", "detonator", "bombpass", "flamepass", "mystery" }) do P["pu_" .. k] = { { 1, 1, 1 }, { .18, .18, .18 }, .4 } end
    for name, v in pairs(P) do paint(tnode(name), v[1], v[2], v[3], v[4]) end
    mtex(tnode("floor"), "base_color", "Textures/field.png")
    mtex(tnode("brick"), "base_color", "Textures/brick.png"); mtex(tnode("brick_chunk"), "base_color", "Textures/brick.png")
    mtex(tnode("pillar"), "base_color", "Textures/concrete.png"); mtex(tnode("pillar_top"), "base_color", "Textures/concrete.png")
    mtex(tnode("border"), "base_color", "Textures/stone.png")
    for _, k in ipairs({ "bombs", "fire", "speed", "wallpass", "detonator", "bombpass", "flamepass", "mystery" }) do mtex(tnode("pu_" .. k), "base_color", "Textures/pu_" .. k .. ".png") end
    for name in pairs(P) do local n = tnode(name); if n then n:set_position(HIDE) end end
end

------------------------------------------------------------------ lights
local LT = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(-0.35, -0.85, -0.4), vec3(1.0, 0.97, 0.92), 1.3)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    LT.key = addp(vec3(10, 30, 30), vec3(1.0, 0.96, 0.9), 60, 90)
    LT.fill = addp(vec3(50, 20, 34), vec3(0.85, 0.9, 1.0), 35, 90)
    LT.flash = {}
    for i = 1, 8 do LT.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1 } end
end
G.LT = LT
G.flash_next = 1
local function flash(x, z, col, power, life, rad)
    local f = LT.flash[G.flash_next]; G.flash_next = G.flash_next % #LT.flash + 1
    f.t, f.life, f.x, f.z, f.col, f.power, f.rad = 0, life or 0.3, x, z, vec3(col[1], col[2], col[3]), power or 40, rad or 7
end
local function update_flashes(dt)
    -- key/fill follow the camera so the lit area stays even while scrolling
    local cx = G.cam.tx
    set_point(LT.key, vec3(cx - 6, 30, 30), vec3(1.0, 0.96, 0.9), 60, 90)
    set_point(LT.fill, vec3(cx + 14, 18, 34), vec3(0.85, 0.9, 1.0), 35, 90)
    for _, f in ipairs(LT.flash) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = 1 - clamp(f.t / f.life, 0, 1)
            set_point(f.idx, vec3(f.x, 2.5, f.z), f.col, f.power * k * k, f.rad)
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

------------------------------------------------------------------ explosion FX (common/particles.lua)
-- Particles here blend additively, so colours are kept low (gain) and overlap builds the hot centre.
-- Flipbook fire, stretched sparks, embers, smoke and brick debris.
-- The flame cross is staggered outward from the bomb (FX only; the sim's flame cells all exist at once).
local FX = load(fs.read("Scripts/Lib/particles.lua"), "@particles.lua")().new({ scale = PS, gain = 0.5 })
G.FX = FX
local FXQ = {}
local function later(d, fn) FXQ[#FXQ + 1] = { t = d, fn = fn } end
function G.fx_update(dt)
    for i = #FXQ, 1, -1 do local q = FXQ[i]; q.t = q.t - dt; if q.t <= 0 then table.remove(FXQ, i); pcall(q.fn) end end
end
function G.fx_clear() for i = #FXQ, 1, -1 do FXQ[i] = nil end end
local function heat(x, z, s, a, life)
    FX:burst("soft", { pos = vec3(x, 0.35, z), count = 1 / FX:k(), c0 = { 1, .42, .12, a or .3 }, c1 = { .6, .12, .02, 0 }, smin = s, smax = s * 1.05,
        lmin = life or .5, lmax = (life or .5) * 1.1, radius = 0, spread = 0, drag = 0 })
end
local function fx_core(x, z)
    local p = vec3(x, 0.9, z)
    FX:flash(vec3(x, 1.8, z), 1.7, { 1, .7, .4 })
    FX:fireball(p, 1.45, { 1, .38, .1 })
    FX:burst("fire", { pos = vec3(x, 1.4, z), count = 6, vel = { 0, 3.2, 0 }, c0 = { 1.6, .75, .3, 1 }, c1 = { .6, .15, .04, 0 }, smin = .7, smax = 1.1,
        lmin = .35, lmax = .55, radius = .3, spread = 1.2, drag = 3, grav = { 0, 1.5, 0 }, anim = 1.5 })        -- rising column
    FX:sparks(p, 34, 1.5, nil, { 2, 1.5, .9 }, -9)
    FX:embers(vec3(x, 1.2, z), 16, 1.4)
    later(0.28, function() FX:smoke(vec3(x, 1.6, z), 5, 1.7, .14, 1.5) end)
    later(0.55, function() FX:smoke(vec3(x, 1.0, z), 3, 1.3, .1, 1.1) end)
end
local function fx_arm(x, z, dx, dz, i, last)
    later(0.035 * i, function()
        local p = vec3(x, 0.8, z)
        FX:burst("fire", { pos = p, count = 5, vel = { dx * 4.0, 0.7, dz * 4.0 }, c0 = { 2.0, .6, .16, 1 }, c1 = { .8, .1, .02, 0 }, smin = .75, smax = 1.15,
            lmin = .3, lmax = .5, radius = .35, spread = 1.3, drag = 3.2, grav = { 0, 1.2, 0 }, anim = 1.7 })
        FX:burst("fire", { pos = vec3(x, 0.6, z), count = 3, c0 = { 1.2, .6, .25, .8 }, c1 = { .4, .1, .03, 0 }, smin = .9, smax = 1.3,
            lmin = .4, lmax = .6, radius = .5, spread = .8, drag = 2.5, grav = { 0, 1.6, 0 }, anim = 1.1 })
        if last then flash(x, z, { 1, .55, .22 }, 30, 0.55, 6) end
        FX:embers(vec3(x, 1.0, z), 3, 1.0)
        if last then FX:sparks(p, 10, 1.1, { dx * 6, 1.5, dz * 6 }, { 2, 1.4, .8 }, -9) end
    end)
    later(0.3 + 0.035 * i, function() FX:smoke(vec3(x, 1.3, z), 1, 1.3, .1, 1.3) end)
end
local function fx_brick_hit(x, z)
    FX:fireball(vec3(x, 1.0, z), 0.9, { 1, .55, .25 })
    FX:sparks(vec3(x, 1.0, z), 12, 1.1, nil, { 2, 1.4, .8 }, -9)
    FX:debris(vec3(x, 1.2, z), 8, 1.3, { .75, .5, .38 }, -14)
end
G.CHUNKS = {}
local function fx_brick_break(x, z)
    -- solid lit chunks that tumble and bounce, plus particle grit
    for i = 1, 9 do
        local a = rand() * 2 * PI
        local sp = 2.5 + rand() * 4
        G.CHUNKS[#G.CHUNKS + 1] = { x = x + (rand() - .5) * 1.2, y = 0.4 + rand() * 0.8, z = z + (rand() - .5) * 1.2, vx = math.cos(a) * sp, vz = math.sin(a) * sp,
            vy = 5 + rand() * 5, rx = rand() * 360, ry = rand() * 360, wr = (rand() - .5) * 900, s = 0.6 + rand() * 0.7, t = 0, life = 0.9 + rand() * 0.5 }
    end
    FX:debris(vec3(x, 1.0, z), 22, 1.6, { .72, .46, .33 }, -16)
    FX:debris(vec3(x, 0.8, z), 10, 1.0, { .3, .22, .18 }, -16)                                   -- charred bits
    FX:smoke(vec3(x, 0.9, z), 5, 1.5, .3, .9)                                                    -- brick dust
    FX:embers(vec3(x, 1.0, z), 8, 1.2)
end
-- sustained flame body on a live flame cell (re-emitted every few frames while the cell burns; k = 1 fresh .. 0 dying)
function G.fx_flame(x, z, core, k)
    local s = 0.55 + 0.45 * k
    FX:burst("fire", { pos = vec3(x, 0.75, z), count = core and 3 or 2, vel = { 0, 1.4, 0 }, c0 = { 1.9, .5, .12, 1 }, c1 = { .8, .1, .02, 0 },
        smin = 0.75 * s, smax = 1.1 * s, lmin = .18, lmax = .3, radius = .6, spread = .9, drag = 2.5, grav = { 0, 1.0, 0 }, anim = 2.2 })
end
G.fx_core, G.fx_arm, G.fx_brick_hit, G.fx_brick_break = fx_core, fx_arm, fx_brick_hit, fx_brick_break

------------------------------------------------------------------ score state
G.score, G.lives, G.hiscore = 0, 3, 0
pcall(function() local s = fs.read("Save/bomberman_hiscore.txt"); if s then G.hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, "Save/bomberman_hiscore.txt", tostring(G.hiscore)) end
G.POP = {}
for i = 1, 12 do G.POP[i] = { t = 9, col = { 1, 1, 1 }, x = 0, z = 0 } end
G.pop_next = 1
local function popup(x, z, txt, col)
    local p = G.POP[G.pop_next]; G.pop_next = G.pop_next % #G.POP + 1
    p.t, p.x, p.z, p.txt, p.col = 0, x, z, txt, col or { 1, 1, 1 }
end
local function add_score(n, x, z)
    G.score = G.score + n
    if x then popup(x, z, tostring(n), { 1, .95, .7 }) end
end
