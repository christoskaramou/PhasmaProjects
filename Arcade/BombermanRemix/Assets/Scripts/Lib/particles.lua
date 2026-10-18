-- particles.lua : shared particle-FX helper for the arcade remakes (PhasmaEngine Lua).
-- Copy into <project>/Assets/Scripts/Lib/particles.lua and generate the textures with
-- common/tools/gen_fx_textures.py <project>/Assets (writes Assets/Textures/fx/*.png).
--
--   local FX = load(fs.read("Scripts/Lib/particles.lua"), "@particles.lua")().new({
--       scale = function() return SET:particle_scale() end,          -- optional quality multiplier
--       light = function(pos, col, power, life, radius) ... end,      -- optional flash light hook
--       gain = 1,                                                      -- optional colour multiplier (bright, high-exposure scenes)
--   })
--   FX:explosion(pos, { size = 1, tint = {1, .6, .3}, debris = {.5,.4,.3}, smoke = true })
--   FX:fireball(pos, size)  FX:flash(pos, size)  FX:sparks(pos, n, size, vel, col, grav)  FX:embers(pos, n, size)
--   FX:smoke(pos, n, size, grey)  FX:debris(pos, n, size, col)  FX:burst(texture, opts)
--   local t = FX:trail("fire", opts); FX:trail_at(t, pos, rate)   -- persistent emitter (exhaust etc.)
--
-- Engine notes: particles.emit_burst(opts) returns the emitter index it created; flipbook settings
-- (anim_cols/anim_rows/anim_speed/interpolate) only take effect through particles.set_emitter afterwards.
-- Particles are camera-facing (orientation 0); orientation = 3 aligns/stretches them along their velocity (sparks).
-- (orientation 1 is a fixed horizontal plane, not velocity-aligned.) Textures from gen_fx_textures.py are premultiplied.
local M = {}
M.__index = M
local rand, floor, max, min = math.random, math.floor, math.max, math.min
local function rr(a, b) return a + (b - a) * rand() end
local TEX = { soft = "soft.png", ember = "ember.png", spark = "spark.png", ring = "ring.png", fire = "fire.png", smoke = "smoke.png", debris = "debris.png" }
local BOOK = { fire = { 4, 4 }, smoke = { 4, 4 }, debris = { 2, 2 } }

function M.new(cfg)
    local s = setmetatable({ cfg = cfg or {}, tex = {}, trails = {} }, M)
    local dir = s.cfg.dir or "Textures/fx/"
    for k, f in pairs(TEX) do
        local ok, idx = pcall(particles.load_texture, dir .. f)
        s.tex[k] = ok and idx or 0
    end
    return s
end
function M:k() local f = self.cfg.scale; return f and f() or 1 end
local function v3(t, d) if t == nil then return d end; if type(t) == "table" then return vec3(t[1], t[2], t[3]) end; return t end
local function v4(t, g) g = g or 1; return vec4(t[1] * g, t[2] * g, t[3] * g, t[4] or 1) end
-- low level: one burst with a named texture
function M:burst(tex, o)
    local n = max(1, floor((o.count or 10) * self:k() + 0.5))
    local id = particles.emit_burst({
        position = o.pos, velocity = v3(o.vel, vec3(0, 0, 0)), color_start = v4(o.c0 or { 1, 1, 1, 1 }, self.cfg.gain), color_end = v4(o.c1 or { 1, 1, 1, 0 }, self.cfg.gain),
        count = n, size_min = o.smin or 0.1, size_max = o.smax or 0.2, life_min = o.lmin or 0.3, life_max = o.lmax or 0.6,
        spawn_radius = o.radius or 0.1, noise_strength = o.spread or 2, drag = o.drag or 1, gravity = v3(o.grav, vec3(0, 0, 0)),
        texture_index = self.tex[tex] or 0, orientation = o.stretch and 3 or 0, cleanup_delay = (o.lmax or 0.6) + 1.5,
    })
    local b = BOOK[tex]
    if b and id then pcall(particles.set_emitter, id, { anim_cols = b[1], anim_rows = b[2], anim_speed = o.anim or 1, interpolate = true }) end
    return id
end
-- presets ------------------------------------------------------------------------------------------
function M:flash(p, s, col)
    s = s or 1; col = col or { 1, .8, .55 }
    self:burst("soft", { pos = p, count = 1 / self:k(), c0 = { col[1] * .9, col[2] * .8, col[3] * .7, .45 }, c1 = { col[1] * .4, col[2] * .25, col[3] * .1, 0 }, smin = 1.3 * s, smax = 1.4 * s, lmin = .1, lmax = .14, radius = 0, spread = 0 })
    if self.cfg.light then self.cfg.light(p, col, 40 * s, 0.35, 5 * s) end
end
function M:fireball(p, s, tint)
    s = s or 1; local t = tint or { 1, .62, .3 }
    -- hot billowing core (flipbook), then a wider cooler shell
    self:burst("fire", { pos = p, count = 6 + 4 * s, c0 = { 1.3, .85, .45, 1 }, c1 = { t[1] * .8, t[2] * .4, t[3] * .2, 0 }, smin = .55 * s, smax = .9 * s, lmin = .35, lmax = .6, radius = .25 * s, spread = 1.6 * s, drag = 3, grav = { 0, .8, 0 }, anim = 1.6 })
    self:burst("fire", { pos = p, count = 8 + 4 * s, c0 = { t[1] * 1.25, t[2] * 1.0, t[3] * .85, .8 }, c1 = { .3, .1, .04, 0 }, smin = .4 * s, smax = .75 * s, lmin = .5, lmax = .9, radius = .45 * s, spread = 3.2 * s, drag = 2.5, grav = { 0, 1.2, 0 }, anim = 1.1 })
end
function M:sparks(p, n, s, vel, col, grav)
    s = s or 1; col = col or { 1.8, 1.4, .9 }
    self:burst("spark", { pos = p, count = n or 16, vel = vel, c0 = { col[1], col[2], col[3], 1 }, c1 = { 1, .35, .1, 0 }, smin = .07 * s, smax = .14 * s, lmin = .25, lmax = .55, radius = .05 * s, spread = 9 * s, drag = 2.2, grav = { 0, grav or -5 * s, 0 }, stretch = true })
end
function M:embers(p, n, s)
    s = s or 1
    self:burst("ember", { pos = p, count = n or 12, c0 = { 2, 1.1, .45, 1 }, c1 = { .8, .2, .05, 0 }, smin = .05 * s, smax = .1 * s, lmin = .8, lmax = 1.6, radius = .3 * s, spread = 3 * s, drag = 1.4, grav = { 0, 1.0 * s, 0 } })
end
function M:smoke(p, n, s, grey, rise)
    s = s or 1; grey = grey or .35
    self:burst("smoke", { pos = p, count = n or 8, c0 = { grey * 1.2, grey * 1.15, grey * 1.1, .38 }, c1 = { grey * .8, grey * .8, grey * .82, 0 }, smin = .7 * s, smax = 1.2 * s, lmin = 1.0, lmax = 1.9, radius = .4 * s, spread = 1.2 * s, drag = 1.2, grav = { 0, rise or .9, 0 }, anim = .6 })
end
function M:debris(p, n, s, col, grav)
    s = s or 1; col = col or { .5, .45, .4 }
    self:burst("debris", { pos = p, count = n or 10, c0 = { col[1], col[2], col[3], 1 }, c1 = { col[1] * .6, col[2] * .6, col[3] * .6, 0 }, smin = .08 * s, smax = .18 * s, lmin = .6, lmax = 1.1, radius = .2 * s, spread = 7 * s, drag = .8, grav = { 0, grav or -12, 0 }, anim = .01 })
end
-- a full explosion: flash, fireball, sparks, embers, optional smoke and debris
function M:explosion(p, o)
    o = o or {}; local s = o.size or 1
    self:flash(p, s, o.flash)
    self:fireball(p, s, o.tint)
    self:sparks(p, floor(14 * s + 6), s, nil, o.spark, o.spark_grav)
    self:embers(p, floor(8 * s + 4), s)
    if o.smoke ~= false then self:smoke(p, floor(4 + 4 * s), s, o.grey) end
    if o.debris then self:debris(p, floor(8 * s + 4), s, o.debris, o.debris_grav) end
end
-- persistent trail emitters (one per owner); rate 0 hides it
function M:trail(tex, o)
    o = o or {}
    local ok, id = pcall(particles.add_emitter, {})
    if not ok or not id then return nil end
    local b = BOOK[tex]
    pcall(particles.set_emitter, id, {
        position = vec3(0, -1000, 0), velocity = v3(o.vel, vec3(0, 0, 0)), color_start = v4(o.c0 or { 1.6, 1, .5, .9 }, self.cfg.gain), color_end = v4(o.c1 or { .4, .15, .05, 0 }, self.cfg.gain),
        size_min = o.smin or .08, size_max = o.smax or .16, life_min = o.lmin or .15, life_max = o.lmax or .3, spawn_radius = o.radius or .03,
        noise_strength = o.spread or .5, drag = o.drag or 2, gravity = v3(o.grav, vec3(0, 0, 0)), texture_index = self.tex[tex] or 0,
        spawn_rate = 0, count = o.max or 200, orientation = o.stretch and 3 or 0,
        anim_cols = b and b[1] or 1, anim_rows = b and b[2] or 1, anim_speed = o.anim or 1, interpolate = b ~= nil,
    })
    self.trails[#self.trails + 1] = id
    return id
end
function M:trail_at(id, p, rate, vel)
    if not id then return end
    local t = { position = p or vec3(0, -1000, 0), spawn_rate = (rate or 0) * self:k() }
    if vel then t.velocity = vel end
    pcall(particles.set_emitter, id, t)
end
return M
