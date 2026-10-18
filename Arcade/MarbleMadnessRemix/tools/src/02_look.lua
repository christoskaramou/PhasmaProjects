------------------------------------------------------------------ palette {base, emissive, rough, metal}
local PAL = {
    marble = { { 1, 1, 1 }, { .02, .02, .03 }, .08, .1 }, steelie = { { .1, .1, .12 }, { 0, 0, 0 }, .15, .9 },
    shadow = { { .02, .02, .03 }, { 0, 0, 0 }, 1 },
    mun_coil = { { .3, .62, .25 }, { .01, .03, .01 }, .45, .3 }, mun_head = { { .35, .68, .28 }, { .01, .03, .01 }, .4, .2 },
    mun_eye = { { .95, .9, .6 }, { .3, .25, .05 }, .3 },
    acid = { { .45, .8, .25 }, { .08, .22, .04 }, .15, 0 },
    ham_post = { { .5, .5, .55 }, { 0, 0, 0 }, .4, .7 }, ham_head = { { .55, .25, .15 }, { .01, 0, 0 }, .55, .1 },
    flag_pole = { { .85, .85, .9 }, { 0, 0, 0 }, .3, .8 }, flag_cloth = { { 1, 1, 1 }, { .15, .15, .15 }, .6 },
    chute = { { .55, .58, .65 }, { 0, 0, 0 }, .3, .8 }, shard = { { .3, .5, .95 }, { .05, .08, .15 }, .1 },
    floor = { { .05, .05, .09 }, { 0, 0, 0 }, 1 },
}
-- slope shade classes: "" flat (bright, warm), 1 falls toward the camera, 2 sideways, 3 falls away (darkest, cooler)
local SHADE = { [""] = { 1.0, 0.98, 0.94 }, ["1"] = { 0.80, 0.80, 0.86 }, ["2"] = { 0.60, 0.60, 0.70 }, ["3"] = { 0.42, 0.42, 0.54 } }
local function paint_templates()
    for k, c in ipairs(G.COURSES) do
        for _, m in ipairs(c.meshes) do
            local col, sc = m:match("_top(%a)(%d?)$")
            if col then
                local t = SHADE[sc] or SHADE[""]
                PAL[m] = { t, col == "G" and { .04, .04, .04 } or { 0, 0, 0 }, sc == "" and .65 or .8 }
            else PAL[m] = { { .9, .9, .95 }, { 0, 0, 0 }, .85 } end
        end
    end
    for name, v in pairs(PAL) do paint(tnode(name), v[1], v[2], v[3], v[4]) end
    mtex(tnode("marble"), "base_color", "Textures/marble.png")
    mtex(tnode("flag_cloth"), "base_color", "Textures/flag.png")
    for k, c in ipairs(G.COURSES) do
        for _, m in ipairs(c.meshes) do
            local col = m:match("_top(%a)%d?$")
            mtex(tnode(m), "base_color", col and ("Textures/c" .. k .. "_" .. col .. ".png") or ("Textures/c" .. k .. "_wall.png"))
        end
    end
    for name in pairs(PAL) do local n = tnode(name); if n then n:set_position(HIDE) end end
end

------------------------------------------------------------------ lights
local LT = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(0.45, -0.8, 0.35), vec3(1.0, 0.97, 0.92), 2.7)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    LT.key = addp(vec3(0, 12, 0), vec3(1.0, 0.95, 0.88), 30, 30)
    LT.fill = addp(vec3(0, 8, 0), vec3(0.7, 0.8, 1.0), 22, 34)
    LT.flash = {}
    for i = 1, 3 do LT.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1 } end
end
G.flash_next = 1
local function flash(p, col, power, life, rad)
    local f = LT.flash[G.flash_next]; G.flash_next = G.flash_next % #LT.flash + 1
    f.t, f.life, f.p, f.col, f.power, f.rad = 0, life or 0.3, p, vec3(col[1], col[2], col[3]), power or 40, rad or 7
end
local function update_lights(dt, p)
    set_point(LT.key, vec3(p.x - 5, p.y + 9, p.z - 4), vec3(1.0, 0.95, 0.88), 30, 30)
    set_point(LT.fill, vec3(p.x + 6, p.y + 5, p.z + 6), vec3(0.7, 0.8, 1.0), 22, 34)
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
local function shatter(p, col)          -- the marble breaks: glass chips, glints, a puff of dust
    col = col or { .4, .6, 1 }
    G.FX.emit("debris", p.x, p.y, p.z, { n = 22, c0 = { col[1] * 1.4, col[2] * 1.4, col[3] * 1.4 }, c1 = { col[1] * .3, col[2] * .3, col[3] * .3 },
        s0 = .12, s1 = .3, l0 = .5, l1 = 1.1, r = .3, sp = 9, drag = 1.2, grav = { 0, -12, 0 }, anim = 0.01 })
    G.FX.sparks(p.x, p.y, p.z, 16, nil, 12)
    G.FX.dust(p.x, p.y, p.z, { .45, .45, .5 }, 1, { 0, .5, 0 }, 1)
    flash(vec3(p.x, p.y + 1, p.z), { .6, .75, 1 }, 40, 0.3, 6)
end
local function sparks(p, n)
    G.FX.sparks(p.x, p.y, p.z, n or 10, nil, 8)
end
local function goo(p)                    -- acid puddle / slinky melt: green vapour
    G.FX.emit("smoke", p.x, p.y, p.z, { n = 6, c0 = { .3, .6, .15 }, c1 = { 0, 0, 0 }, s0 = .8, s1 = 1.5, l0 = .5, l1 = 1.0, r = .4, sp = 2, drag = 2, grav = { 0, 1.5, 0 } })
    G.FX.emit("ember", p.x, p.y, p.z, { n = 10, c0 = { .6, 1.1, .3 }, c1 = { 0, 0, 0 }, s0 = .1, s1 = .2, l0 = .3, l1 = .7, r = .4, sp = 4, drag = 2, grav = { 0, 1.5, 0 } })
end
local function dust(p, n)
    G.FX.dust(p.x, p.y, p.z, { .28, .28, .32 }, clamp((n or 6) / 6, 0.3, 2), { 0, .2, 0 }, 0.8)   -- dim: pale tiles + screen blend
end

------------------------------------------------------------------ score state
G.score, G.hiscore = 0, 0
pcall(function() local s = fs.read("Save/marble_hiscore.txt"); if s then G.hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, "Save/marble_hiscore.txt", tostring(G.hiscore)) end
local function add_score(n) G.score = G.score + n end
G.banner = { text = "", t = 0 }
function G.banner_set(t, d) G.banner.text = t; G.banner.t = d or 1.5 end
