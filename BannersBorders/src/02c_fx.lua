------------------------------------------------------------------ 02c_fx: particle effects (Scripts/Lib/particles.lua), all positions in WORLD space
do
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
function FX.boom(x, y, z, size)
    FX.lib:explosion(vec3(x, y, z), { size = size or 1, smoke = true, debris = { .45, .32, .22 }, spark_grav = -9 })
end
function FX.shards(x, y, z, col, n)   -- glass gate / ice
    FX.emit("debris", x, y, z, { n = n or 10, vel = { 0, 2, 0 }, c0 = col, c1 = sc(col, 0.4), s0 = 0.08, s1 = 0.2, l0 = 0.5, l1 = 0.9, r = 1.2, sp = 5, drag = 0.8, grav = { 0, -12, 0 }, anim = 0.2 })
end
function FX.fire(x, y, z, size)
    FX.emit("fire", x, y, z, { n = 3, vel = { 0, 2, 0 }, c0 = { 1.6, 1.1, .5 }, c1 = { .3, .1, .02 }, s0 = 0.6 * size, s1 = 1.2 * size, l0 = 0.4, l1 = 0.7, r = 0.3 * size, sp = 1, drag = 1.5, grav = { 0, 2, 0 } })
end
FX.trails = {}
function FX.trail(kind)
    if kind == "smoke" then
        return FX.lib:trail("smoke", { c0 = { .7, .7, .72, .6 }, c1 = { .2, .2, .2, 0 }, smin = .25, smax = .5, lmin = .35, lmax = .7, radius = .05, spread = .4, grav = { 0, .8, 0 }, max = 160 })
    end
    return FX.lib:trail("ember", { c0 = { 1.8, 1.0, .4, 1 }, c1 = { .5, .1, .02, 0 }, smin = .1, smax = .22, lmin = .12, lmax = .25, radius = .05, spread = .5, max = 120 })
end
------------------------------------------------------------------ Banners & Borders effects
-- region captured: white flash, faction-coloured confetti + ring, light pop
function FX.capture(x, y, z, col)
    FX.flash(x, y + 0.6, z, 2.2, { 1, 1, 1 })
    FX.ring(x, y + 0.08, z, 2.6, col, true)
    FX.emit("spark", x, y + 0.6, z, { n = 14, c0 = { col[1] * 2.2, col[2] * 2.2, col[3] * 2.2 }, c1 = { col[1], col[2], col[3] }, s0 = 0.08, s1 = 0.16, l0 = 0.5, l1 = 1.1, r = 0.3, sp = 4, drag = 1.2, grav = { 0, -3, 0 }, vel = { 0, 4.5, 0 } })
    FX.confetti(x, y + 1.0, z, 18, 0.7)
    FX.dust(x, y + 0.1, z, { 0.9, 0.85, 0.75 }, 1.2, 1.4)
    if G.flash then G.flash(x, y + 1.2, z, col, 60, 0.5, 6) end
end
-- two streams meet: little steel sparks + dust
function FX.clash(x, y, z, n)
    FX.emit("spark", x, y + 0.25, z, { n = 2 + min(4, n), c0 = { 2, 1.7, 1.1 }, c1 = { 0.8, 0.3, 0.1 }, s0 = 0.05, s1 = 0.1, l0 = 0.15, l1 = 0.35, r = 0.12, sp = 4, drag = 2, grav = { 0, -4, 0 }, vel = { 0, 2, 0 } })
    FX.emit("dust", x, y + 0.1, z, { n = 1, c0 = { .75, .7, .62 }, c1 = { 0, 0, 0 }, s0 = 0.25, s1 = 0.45, l0 = 0.3, l1 = 0.55, r = 0.1, sp = 1.5, drag = 3, grav = { 0, 0.5, 0 } })
end
-- troops arriving at a hostile region
function FX.hit(x, y, z, col)
    FX.emit("dust", x, y + 0.15, z, { n = 1, c0 = { .8, .74, .62 }, c1 = { 0, 0, 0 }, s0 = 0.25, s1 = 0.5, l0 = 0.3, l1 = 0.6, r = 0.2, sp = 1.5, drag = 3, grav = { 0, 0.6, 0 } })
end
function FX.frost(x, y, z, rad)
    FX.emit("soft", x, y + 0.5, z, { n = 26, c0 = { 0.9, 1.4, 2.0 }, c1 = { 0.3, 0.5, 0.9 }, s0 = 0.5, s1 = 1.1, l0 = 0.8, l1 = 1.6, r = rad * 0.8, sp = 1.0, drag = 2, grav = { 0, -0.4, 0 } })
    FX.ring(x, y + 0.1, z, rad * 2.0, { 0.6, 0.85, 1.0 }, true)
    if G.flash then G.flash(x, y + 2, z, { 0.6, 0.8, 1 }, 60, 0.8, rad * 1.6) end
end
function FX.barrage(x, y, z)
    FX.boom(x, y + 0.3, z, 1.4)
    FX.smoke(x, y + 0.4, z, 1.3, 1.4)
    FX.emit("debris", x, y + 0.3, z, { n = 10, c0 = { .55, .45, .35 }, c1 = { .3, .25, .2 }, s0 = 0.08, s1 = 0.18, l0 = 0.6, l1 = 1.1, r = 0.4, sp = 3, drag = 0.6, grav = { 0, -9, 0 }, vel = { 0, 5, 0 } })
    if G.flash then G.flash(x, y + 1, z, { 1, 0.6, 0.3 }, 90, 0.4, 7) end
end
function FX.airdrop(x, y, z, col)
    FX.dust(x, y + 0.1, z, { 0.9, 0.85, 0.75 }, 1.4, 1.6)
    FX.ring(x, y + 0.08, z, 2.0, col, true)
end
end
