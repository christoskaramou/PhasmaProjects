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
