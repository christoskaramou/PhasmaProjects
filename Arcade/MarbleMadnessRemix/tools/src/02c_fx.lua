------------------------------------------------------------------ FX: particle effects on top of Scripts/Lib/particles.lua
-- Scripts/Lib/particles.lua is a verbatim copy of the shared helper (common/particles.lua). It loads the textures in
-- Textures/fx/ and provides the explosion / fireball / embers / debris presets used here.
-- Engine facts this layer works around (see tools/gen_fx_pm.py):
--   * the particle pass SCREEN-blends and multiplies colour by texture RGB; alpha only kills/discards, so the
--     textures in Textures/fx/ are premultiplied, particles can only brighten (smoke is a light veil) and every
--     fade happens in RGB (color_end rgb -> 0);
--   * orientation strings: "billboard", "horizontal" (flat on the ground), "velocity" (stretched streaks);
--   * flipbook settings only apply through particles.set_emitter after emit_burst.
local FX = { tex = {}, scale = 1 }   -- scale: world size of the effects (1 = metre-sized cars)
G.FX = FX
FX.lib = load(fs.read("Scripts/Lib/particles.lua"), "@particles.lua")().new({
    scale = PS, gain = 1, light = function(pos, col, power, life, radius) if G.fx_light then G.fx_light(pos, col, power, life, radius) end end })
FX.tex = FX.lib.tex
for _, k in ipairs({ "dust", "foam" }) do
    local ok, idx = pcall(particles.load_texture, "Textures/fx/" .. k .. ".png")
    FX.tex[k] = (ok and type(idx) == "number") and idx or 0
end
local BOOK = { fire = { 4, 4 }, smoke = { 4, 4 }, debris = { 2, 2 } }
local function fxv(t) return vec3(t[1], t[2], t[3]) end
-- one burst; o: n, vel{}, c0{}, c1{}, s0, s1, l0, l1, r, sp(read), drag, grav{}, stretch, flat, anim
function FX.emit(tex, x, y, z, o)
    local n = max(1, floor((o.n or 8) * PS() + 0.5))
    local k = FX.scale
    local c0, c1 = o.c0 or { 1, 1, 1 }, o.c1 or { 0, 0, 0 }
    local ok, id = pcall(particles.emit_burst, {
        position = vec3(x, y, z), velocity = o.vel and fxv(o.vel) or vec3(0, 0, 0),
        color_start = vec4(c0[1], c0[2], c0[3], 1), color_end = vec4(c1[1], c1[2], c1[3], 0.02), count = n,
        size_min = (o.s0 or 0.2) * k, size_max = (o.s1 or 0.4) * k, life_min = o.l0 or 0.4, life_max = o.l1 or 0.8,
        spawn_radius = (o.r or 0.2) * k, noise_strength = (o.sp or 2) * k, drag = o.drag or 1.5,
        gravity = o.grav and vec3(o.grav[1] * k, o.grav[2] * k, o.grav[3] * k) or vec3(0, 0, 0),
        texture_index = FX.tex[tex] or 0, orientation = o.flat and "horizontal" or (o.stretch and "velocity" or "billboard"),
        cleanup_delay = (o.l1 or 0.8) + 1.0,
    })
    local b = BOOK[tex]
    if ok and b and id then pcall(particles.set_emitter, id, { anim_cols = b[1], anim_rows = b[2], anim_speed = o.anim or (1 / (o.l1 or 0.8)), interpolate = true }) end
end
local function sc(c, k) return { c[1] * k, c[2] * k, c[3] * k } end
-- presets (k = intensity 0..1+, vel = carried velocity table)
function FX.smoke(x, y, z, k, vel, grey, size)   -- light grey billow (flipbook)
    k = k or 1; local g = (grey or 0.42) * 1.7; size = size or 1   -- the premultiplied flipbook peaks near half density
    FX.emit("smoke", x, y, z, { n = 2 + 2 * k, vel = vel, c0 = { g * k, g * k, g * 1.02 * k }, c1 = { 0, 0, 0 }, s0 = 0.8 * size, s1 = 1.7 * size,
        l0 = 0.9, l1 = 1.8, r = 0.3 * size, sp = 1.4, drag = 2.2, grav = { 0, 0.9, 0 } })
end
function FX.dust(x, y, z, col, k, vel, size)      -- grainy cloud tinted by the ground
    k = k or 1; size = size or 1
    FX.emit("dust", x, y, z, { n = 2 + 3 * k, vel = vel, c0 = sc(col, k), c1 = { 0, 0, 0 }, s0 = 0.5 * size, s1 = 1.2 * size,
        l0 = 0.5, l1 = 1.1, r = 0.35 * size, sp = 2.4, drag = 2.6, grav = { 0, 0.5, 0 } })
end
function FX.grit(x, y, z, col, n, vel)            -- thrown clods / clippings / snow chunks
    FX.emit("debris", x, y, z, { n = n or 6, vel = vel, c0 = col, c1 = sc(col, 0.3), s0 = 0.06, s1 = 0.14, l0 = 0.35, l1 = 0.7,
        r = 0.2, sp = 5, drag = 0.8, grav = { 0, -14, 0 }, anim = 0.01 })
end
function FX.sparks(x, y, z, n, vel, spread)       -- streaks stretched along their velocity
    FX.emit("spark", x, y, z, { n = n or 16, vel = vel, c0 = { 2.2, 1.6, 0.8 }, c1 = { 0.6, 0.15, 0.02 }, s0 = 0.08, s1 = 0.16,
        l0 = 0.2, l1 = 0.5, r = 0.1, sp = spread or 10, drag = 1.8, grav = { 0, -9, 0 }, stretch = true })
end
function FX.flash(x, y, z, size, col)
    col = col or { 1.6, 1.1, 0.6 }
    FX.emit("soft", x, y, z, { n = 1 / max(PS(), 0.01), c0 = col, c1 = { 0, 0, 0 }, s0 = size, s1 = size * 1.1, l0 = 0.08, l1 = 0.12, r = 0, sp = 0, drag = 0 })
end
function FX.fire(x, y, z, k, size, vel)           -- licking flames, rising (flipbook)
    k = k or 1; size = size or 1
    FX.emit("fire", x, y, z, { n = 2 + 3 * k, vel = vel, c0 = { 1.5 * k, 1.0 * k, 0.55 * k }, c1 = { 0.25, 0.04, 0 }, s0 = 0.4 * size, s1 = 0.9 * size,
        l0 = 0.25, l1 = 0.55, r = 0.3 * size, sp = 1.5, drag = 2.5, grav = { 0, 3.5, 0 } })
end
function FX.ring(x, y, z, size, col, flat)
    FX.emit("ring", x, y, z, { n = 1 / max(PS(), 0.01), c0 = col or { 0.6, 0.55, 0.5 }, c1 = { 0, 0, 0 }, s0 = size, s1 = size, l0 = 0.25, l1 = 0.3, r = 0, sp = 0, flat = flat })
end
-- full explosion: the shared preset (flash, fireball, sparks, embers, smoke, debris) at this game's scale,
-- plus a carried smoke column so a wreck moving with the traffic leaves a trail
function FX.explosion(x, y, z, size, vel, debris_col)
    size = size or 1
    FX.lib:explosion(vec3(x, y, z), { size = size * FX.scale, smoke = true, debris = debris_col or { .35, .3, .26 }, spark_grav = -9 * FX.scale })
    FX.emit("smoke", x, y + 0.5 * FX.scale, z, { n = 4 * size, vel = vel, c0 = { 0.3, 0.29, 0.28 }, c1 = { 0, 0, 0 }, s0 = 1.4 * size, s1 = 2.8 * size,
        l0 = 1.2, l1 = 2.4, r = 1.0 * size, sp = 2.5 * size, drag = 1.6, grav = { 0, 1.6, 0 } })
end
function FX.spray(x, y, z, k, vel, size)          -- water spray / foam
    k = k or 1; size = size or 1
    FX.emit("foam", x, y, z, { n = 2 + 3 * k, vel = vel, c0 = { 0.75 * k, 0.82 * k, 0.88 * k }, c1 = { 0, 0, 0 }, s0 = 0.4 * size, s1 = 1.0 * size,
        l0 = 0.35, l1 = 0.8, r = 0.3 * size, sp = 3, drag = 1.8, grav = { 0, -6, 0 } })
end
FX.scale = 0.5    -- Marble Madness: the marble is half a unit across
G.fx_light = function(pos, col, power, life, radius) flash(pos, col, power * 0.5, life, radius) end
