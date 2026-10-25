-- ASTEROIDS: NEON REMAKE  (PhasmaEngine, Lua)
-- Gameplay faithful to the 1979 original: inertia, wraparound, splitting rocks,
-- large/small saucers, hyperspace, extra lives, rising heartbeat.
local ROOT = ""  -- Assets-relative (was /workspace/... Linux path)
-- Optional unattended capture: Assets/Agent/capture.cfg = "<shot dir>\n<quit 0/1>"
local CAP = fs.read("Agent/capture.cfg")
local SHOT_DIR, AUTO_QUIT = nil, false
if CAP and #CAP > 2 then
    local l1, l2 = CAP:match("([^\n]+)\n?([^\n]*)")
    SHOT_DIR = l1; AUTO_QUIT = l2 == "1"
end
local AUTOPILOT = SHOT_DIR ~= nil

local PI, TAU = math.pi, math.pi * 2
local sin, cos, sqrt, rand, floor, abs, min, max = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max
math.randomseed(math.floor((engine.get_metrics and (engine.get_metrics() or {}).frame or 0) + 1234))
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end

------------------------------------------------------------------ deferred materials
-- Engine quirk: material.set on a node whose primitive was attached this frame is a
-- silent no-op (mesh not resolved yet), so material writes are queued and replayed.
local _mset, _mtex, _mds = material.set, material.set_texture, material.set_double_sided
local mat_q = {}
local function qpush(f) mat_q[#mat_q + 1] = { f = f, n = 0 } end
material = setmetatable({
    set = function(n, k, v) _mset(n, k, v); qpush(function() _mset(n, k, v) end) end,
    set_texture = function(n, k, v) qpush(function() pcall(_mtex, n, k, v) end) end,
    set_double_sided = function(n, v) qpush(function() pcall(_mds, n, v) end) end,
}, { __index = material })
local function flush_mats()
    for i = #mat_q, 1, -1 do
        local q = mat_q[i]; q.n = q.n + 1
        if q.n == 2 or q.n == 6 then q.f() end
        if q.n >= 6 then table.remove(mat_q, i) end
    end
end

------------------------------------------------------------------ render setup
local ss = scene.add_empty_node("SceneSettings"); ss:set_scene_settings(true)
local function S(k, v) pcall(settings.set, k, v) end
-- TAA + smooth bloom, see /workspace/games/common/RENDER_SETTINGS.md
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.25)
S("tonemapping", true); S("fxaa", false); S("taa", true); S("cas_sharpening", false); S("ssao", false); S("ssr", false)
S("shadows", false); S("motion_blur", false); S("dof", false)
S("color_grading", true); S("color_grading_saturation", 1.15); S("color_grading_contrast", 1.08)

-- shared settings menu (Assets/Scripts/Lib/settings_menu.lua; see /workspace/games/common/SETTINGS_API.md)
local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "SETTINGS", subtitle = "A / D  TURN   ·   SPACE  THRUST   ·   LEFT CLICK  FIRE   ·   SHIFT / H  HYPERSPACE", click = function() pcall(audio.play, "blip.wav") end,
    theme = { accent = { 0.16, 0.62, 0.68, 1 }, accent2 = { 0.7, 0.22, 0.6, 1 }, text = { 0.7, 0.76, 0.85, 1 }, selected_text = { 0.8, 0.86, 0.92, 1 } } })  -- dimmer: this game blooms its UI
SET:apply()   -- after the look above (it is the HIGH preset baseline)
local set_open = false

local ORTHO = 36.0
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1920, surf.height or 1080
local ASPECT = SW / SH
local HH = ORTHO * 0.5          -- playfield half height (calibrated)
local HW = HH * ASPECT

local camNode = scene.find and nil
local cams = scene.get_cameras()
local cam = cams[1]
local CAMZ = 60
local function place_camera(ox, oy)
    cam:set_position(vec3(ox, oy, CAMZ))
end
pcall(function() cam:set_euler(vec3(0, PI, 0)) end)
pcall(function() cam:set_orthographic_size(ORTHO) end)
place_camera(0, 0)

local FX = 1 -- x sign for rendering (camera handedness)
local function P(x, y, z) return vec3(FX * x, y, z or 0) end

-- Backdrop: textured emissive quad far behind the playfield.
local bg = scene.add_empty_node("Backdrop")
scene.attach_primitive(bg, "quad")
bg:set_position(vec3(0, 0, -40))
bg:set_scale(vec3(HW * 2.3, HH * 2.3, 1))
material.set(bg, "base_color", vec4(0, 0, 0, 1))
material.set(bg, "emissive", vec3(0.95, 0.95, 1.0))
material.set(bg, "roughness", 1.0)
pcall(material.set_double_sided, bg, true)
material.set_texture(bg, "emissive", ROOT .. "Textures/space_bg.png")

-- Lights for the PBR rock cores: a cool key and a warm rim.
local function add_point(pos, col, inten, rad)
    lights.add_point()
    local i = #lights.get_point_lights() - 1
    lights.set_point_light(i, pos, col, inten, rad)
    return i
end
local L_KEY = add_point(vec3(-HW * 0.6, HH * 0.7, 25), vec3(0.7, 0.8, 1.0), 6, 200)
local L_RIM = add_point(vec3(HW * 0.7, -HH * 0.6, 20), vec3(1.0, 0.5, 0.3), 4, 200)
-- Flash light pool for explosions
local flashes = {}
for i = 1, 4 do flashes[i] = { idx = add_point(vec3(0, 0, -500), vec3(1, 0.6, 0.3), 0, 1), t = 0, life = 1, pos = vec3(0,0,0), col = vec3(1,1,1), power = 0 } end
local flash_next = 1
local function flash(x, y, col, power, life)
    local f = flashes[flash_next]; flash_next = flash_next % #flashes + 1
    f.t, f.life, f.pos, f.col, f.power = 0, life or 0.5, P(x, y, 6), col, power
end

------------------------------------------------------------------ helpers
local function emissive(n, r, g, b) material.set(n, "emissive", vec3(r, g, b)) end
local function line_node(name, pts, width, col, closed)
    local n = scene.add_empty_node(name)
    local v = {}
    for i, p in ipairs(pts) do v[i] = vec3(FX * p[1], p[2], 0) end
    scene.attach_polyline(n, v, width, vec3(0, 0, 1), closed ~= false)
    material.set(n, "base_color", vec4(0, 0, 0, 1))
    emissive(n, col[1] * 0.55, col[2] * 0.55, col[3] * 0.55)
    material.set(n, "base_color", vec4(col[1] * 0.25, col[2] * 0.25, col[3] * 0.25, 1))
    pcall(material.set_double_sided, n, true)
    return n
end
local function play(s) pcall(audio.play, s) end

local function wrap(o)
    if o.x > HW then o.x = o.x - 2 * HW elseif o.x < -HW then o.x = o.x + 2 * HW end
    if o.y > HH then o.y = o.y - 2 * HH elseif o.y < -HH then o.y = o.y + 2 * HH end
end
local function wdist2(ax, ay, bx, by)
    local dx, dy = abs(ax - bx), abs(ay - by)
    if dx > HW then dx = 2 * HW - dx end
    if dy > HH then dy = 2 * HH - dy end
    return dx * dx + dy * dy
end

------------------------------------------------------------------ particles
local function burst(x, y, opts)
    local o = {
        position = P(x, y, 1), velocity = opts.vel and P(opts.vel[1], opts.vel[2], 0) or vec3(0, 0, 0),
        color_start = opts.c0, color_end = opts.c1, count = max(1, floor((opts.count or 60) * SET:particle_scale())),
        size_min = opts.smin or 0.08, size_max = opts.smax or 0.25,
        life_min = opts.lmin or 0.4, life_max = opts.lmax or 1.1,
        spawn_radius = opts.radius or 0.4, noise_strength = opts.spread or 20, drag = opts.drag or 1.5,
        gravity = vec3(0, 0, 0), cleanup_delay = 3,
    }
    pcall(particles.emit_burst, o)
end
-- Persistent thruster emitter (repositioned every frame)
local thrust_em = particles.add_emitter({ position = vec3(0, 0, -500), velocity = vec3(0, 0, 0), gravity = vec3(0, 0, 0),
    color_start = vec4(0.4, 0.8, 1.6, 1), color_end = vec4(1.2, 0.2, 0.6, 0), count = floor(400 * SET:particle_scale()), spawn_rate = 0,
    spawn_radius = 0.15, size_min = 0.08, size_max = 0.22, life_min = 0.2, life_max = 0.5, noise_strength = 3, drag = 1.0 })
-- Ambient space dust
particles.add_emitter({ position = vec3(0, 0, -10), velocity = vec3(0, 0, 0), gravity = vec3(0, 0, 0),
    color_start = vec4(0.5, 0.6, 1.0, 0.5), color_end = vec4(0.6, 0.3, 1.0, 0), count = floor(300 * SET:particle_scale()), spawn_rate = 40 * SET:particle_scale(),
    spawn_radius = HW * 1.1, size_min = 0.03, size_max = 0.09, life_min = 4, life_max = 8, noise_strength = 0.6, drag = 0 })

------------------------------------------------------------------ shockwaves (expanding neon rings)
local waves = {}
local function ring_pts(r) local t = {} for k = 0, 31 do local a = k / 32 * TAU; t[#t + 1] = { cos(a) * r, sin(a) * r } end return t end
for i = 1, 6 do
    local n = line_node("Shock" .. i, ring_pts(1), 0.06, { 1, 1, 1 })
    n:set_enabled(false)
    waves[i] = { node = n, t = 1, life = 1 }
end
local wave_next = 1
local function shockwave(x, y, col, size, life)
    local w = waves[wave_next]; wave_next = wave_next % #waves + 1
    w.x, w.y, w.col, w.size, w.t, w.life = x, y, col, size, 0, life or 0.5
    w.node:set_enabled(true)
end
local function update_waves(dt)
    for _, w in ipairs(waves) do
        if w.t < w.life then
            w.t = w.t + dt
            local u = min(1, w.t / w.life)
            local r = 0.3 + w.size * (1 - (1 - u) ^ 3)
            w.node:set_position(vec3(w.x, w.y, 0.6)); w.node:set_scale(vec3(r, r, 1))
            local k = (1 - u) ^ 2 * 1.4
            material.set(w.node, "emissive", vec3(w.col[1] * k, w.col[2] * k, w.col[3] * k))
            if u >= 1 then w.node:set_enabled(false) end
        end
    end
end

------------------------------------------------------------------ shake / tweens
local shake, shake_t = 0, 0
local function add_shake(a) shake = min(1.6, shake + a) end
local tweens = {}
local function tween_num(from, to, dur, fn, ease, done)
    tweens[#tweens + 1] = { a = from, b = to, d = dur, t = 0, fn = fn, ease = ease or "out", done = done }
end
local EASE = {
    out = function(u) return 1 - (1 - u) ^ 3 end,
    inout = function(u) return u < 0.5 and 4 * u ^ 3 or 1 - (-2 * u + 2) ^ 3 / 2 end,
    back = function(u) local c = 1.70158; return 1 + (c + 1) * (u - 1) ^ 3 + c * (u - 1) ^ 2 end,
    linear = function(u) return u end,
}
local function update_tweens(dt)
    for i = #tweens, 1, -1 do
        local tw = tweens[i]; tw.t = tw.t + dt
        local u = min(1, tw.t / tw.d)
        tw.fn(tw.a + (tw.b - tw.a) * EASE[tw.ease](u))
        if u >= 1 then table.remove(tweens, i); if tw.done then tw.done() end end
    end
end

------------------------------------------------------------------ ship
local SHIP_PTS = { { 1.25, 0 }, { -0.85, 0.75 }, { -0.5, 0.42 }, { -0.5, -0.42 }, { -0.85, -0.75 } }
local ship = { x = 0, y = 0, vx = 0, vy = 0, a = PI / 2, alive = false, inv = 0, respawn = 0, hyper = 0 }
ship.node = line_node("Ship", SHIP_PTS, 0.13, { 0.6, 1.6, 2.4 })
ship.core = scene.add_empty_node("ShipCore"); scene.attach_primitive(ship.core, "pyramid")
material.set(ship.core, "base_color", vec4(0.15, 0.2, 0.3, 1)); material.set(ship.core, "metallic", 0.9); material.set(ship.core, "roughness", 0.3)
ship.flame = line_node("Flame", { { -0.55, 0.3 }, { -1.5, 0 }, { -0.55, -0.3 } }, 0.1, { 2.5, 1.0, 0.3 }, false)
ship.shield = line_node("Shield", (function() local t = {} for k = 0, 23 do local a = k / 24 * TAU t[#t + 1] = { cos(a) * 1.7, sin(a) * 1.7 } end return t end)(), 0.05, { 0.2, 0.6, 1.2 })
local function ship_show(v)
    ship.node:set_enabled(v); ship.core:set_enabled(v)
    if not v then ship.flame:set_enabled(false); ship.shield:set_enabled(false) end
end
ship_show(false)

-- Ship debris (vector pieces flying apart on death)
local debris = {}
for i = 1, #SHIP_PTS do
    local a, b = SHIP_PTS[i], SHIP_PTS[i % #SHIP_PTS + 1]
    local mx, my = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
    local n = line_node("Debris" .. i, { { a[1] - mx, a[2] - my }, { b[1] - mx, b[2] - my } }, 0.1, { 0.6, 1.6, 2.4 }, false)
    n:set_enabled(false)
    debris[i] = { node = n, mx = mx, my = my, t = 0 }
end
local function spawn_debris()
    for _, d in ipairs(debris) do
        local c, s = cos(ship.a), sin(ship.a)
        d.x = ship.x + d.mx * c - d.my * s; d.y = ship.y + d.mx * s + d.my * c
        d.vx = ship.vx * 0.3 + rr(-4, 4); d.vy = ship.vy * 0.3 + rr(-4, 4)
        d.r = ship.a; d.vr = rr(-6, 6); d.t = 2.2
        d.node:set_enabled(true)
    end
end

------------------------------------------------------------------ asteroids
local SIZES = { [3] = 3.1, [2] = 1.65, [1] = 0.85 }
local POINTS = { [3] = 20, [2] = 50, [1] = 100 }
local ROCK_COL = { { 1.4, 0.75, 2.2 }, { 0.5, 1.6, 2.2 }, { 2.2, 0.9, 0.5 }, { 0.6, 2.0, 1.0 } }
local rocks = {}
local rock_pool = {}
local function make_rock_node(size)
    local r = SIZES[size]
    local pts, n = {}, 11 + size
    for k = 0, n - 1 do
        local a = k / n * TAU + rr(-0.12, 0.12)
        local rad = r * rr(0.72, 1.08)
        pts[#pts + 1] = { cos(a) * rad, sin(a) * rad }
    end
    local col = ROCK_COL[rand(#ROCK_COL)]
    local outline = line_node("Rock", pts, 0.07 + 0.03 * size, col)
    local core = scene.add_empty_node("RockCore"); scene.attach_primitive(core, "ico_sphere")
    core:set_parent(outline)
    core:set_scale(vec3(r * rr(0.8, 0.92), r * rr(0.8, 0.92), r * 0.7))
    core:set_rotation(vec3(rr(0, 360), rr(0, 360), rr(0, 360)))
    local tone = rr(0.08, 0.14)
    material.set(core, "base_color", vec4(tone, tone * 0.92, tone * 0.85, 1))
    material.set(core, "roughness", 0.85); material.set(core, "metallic", 0.15)
    material.set(core, "emissive", vec3(col[1] * 0.06, col[2] * 0.06, col[3] * 0.06))
    return { node = outline, core = core, col = col }
end
local function get_rock_node(size)
    local pool = rock_pool[size]
    if pool and #pool > 0 then local g = table.remove(pool); g.node:set_enabled(true); return g end
    return make_rock_node(size)
end
local function spawn_rock(size, x, y, vx, vy)
    local g = get_rock_node(size)
    local spd = ({ [3] = rr(1.5, 3.2), [2] = rr(2.8, 5.5), [1] = rr(4.5, 8) })[size]
    if not vx then local a = rr(0, TAU); vx, vy = cos(a) * spd, sin(a) * spd end
    local r = { g = g, size = size, x = x, y = y, vx = vx, vy = vy, a = rr(0, TAU), va = rr(-1.2, 1.2) * (4 - size) * 0.6, rad = SIZES[size] * 0.92 }
    rocks[#rocks + 1] = r
    return r
end
local function release_rock(i)
    local r = rocks[i]
    r.g.node:set_enabled(false)
    rock_pool[r.size] = rock_pool[r.size] or {}
    table.insert(rock_pool[r.size], r.g)
    table.remove(rocks, i)
end

------------------------------------------------------------------ bullets
local bullets = {}
local bullet_pool = {}
local function get_bullet_node(hostile)
    local key = hostile and "h" or "p"
    bullet_pool[key] = bullet_pool[key] or {}
    local p = bullet_pool[key]
    if #p > 0 then local n = table.remove(p); n:set_enabled(true); return n end
    local n = scene.add_empty_node("Bullet"); scene.attach_primitive(n, "ico_sphere")
    n:set_scale(vec3(0.26, 0.26, 0.26))
    material.set(n, "base_color", vec4(0, 0, 0, 1))
    if hostile then emissive(n, 1.6, 0.25, 0.5) else emissive(n, 0.8, 1.4, 1.8) end
    return n
end
local function fire(x, y, vx, vy, hostile)
    local b = { x = x, y = y, vx = vx, vy = vy, life = hostile and 1.1 or 1.05, hostile = hostile, node = get_bullet_node(hostile) }
    bullets[#bullets + 1] = b
end
local function release_bullet(i)
    local b = bullets[i]
    b.node:set_enabled(false)
    table.insert(bullet_pool[b.hostile and "h" or "p"], b.node)
    table.remove(bullets, i)
end

------------------------------------------------------------------ saucer
local SAUCER_PTS = { { -1.0, 0 }, { -0.45, 0.32 }, { 0.45, 0.32 }, { 1.0, 0 }, { 0.45, -0.34 }, { -0.45, -0.34 } }
local saucer = { active = false, timer = 12 }
local saucer_nodes = {}
for i, sz in ipairs({ 2.2, 1.25 }) do
    local pts = {}
    for k, p in ipairs(SAUCER_PTS) do pts[k] = { p[1] * sz, p[2] * sz } end
    local body = line_node("Saucer" .. i, pts, 0.12, i == 1 and { 2.4, 0.4, 2.0 } or { 2.6, 1.6, 0.3 })
    local dome = line_node("Dome" .. i, { { -0.45 * sz, 0.32 * sz }, { -0.25 * sz, 0.7 * sz }, { 0.25 * sz, 0.7 * sz }, { 0.45 * sz, 0.32 * sz } }, 0.1, i == 1 and { 2.4, 0.4, 2.0 } or { 2.6, 1.6, 0.3 }, false)
    local belt = line_node("Belt" .. i, { { -1.0 * sz, 0 }, { 1.0 * sz, 0 } }, 0.08, { 1.2, 1.2, 1.4 }, false)
    dome:set_parent(body); belt:set_parent(body)
    body:set_enabled(false)
    saucer_nodes[i] = body
end

------------------------------------------------------------------ game state
local state = "title"     -- title | play | pause | over
local score, hiscore, lives, wave, next_extra = 0, 0, 3, 0, 10000
local wave_delay = 0
local beat_t, beat_int, beat_flip = 0, 1.0, false
local thrust_snd_t = 0
local saucer_snd_t = 0
local title_t = 0
local game_over_t = 0
local jev
local SAVE = "Save/asteroids_hiscore.txt"
pcall(function() local s = fs.read(SAVE); if s then hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, SAVE, tostring(hiscore)) end

------------------------------------------------------------------ HUD / menus
runtime_ui.show("hud"); runtime_ui.set_screen_overlay("hud", true)
local CYAN = { 0.55, 0.95, 1.0, 1 }
local MAG = { 1.0, 0.45, 0.9, 1 }
local WHITE = { 1, 1, 1, 1 }
local NONE = { 0, 0, 0, 0 }
local hud_cache = {}
local function text(id, label, x, y, w, h, fs, col, align, visible)
    local key = label .. "|" .. x .. "|" .. y .. "|" .. tostring(visible) .. "|" .. col[4] .. "|" .. fs
    if hud_cache[id] == key then return end
    hud_cache[id] = key
    runtime_ui.set_quad("hud", id, { x = x, y = y, w = w, h = h, z = 10, style = "text", label = label, fill = NONE, border = NONE,
        text_color = col, font_scale = fs, align_h = align or "center", align_v = "middle", no_input = true, visible = visible ~= false })
end
local function panel(id, x, y, w, h, visible, a)
    local key = x .. "|" .. y .. "|" .. w .. "|" .. h .. "|" .. tostring(visible) .. "|" .. (a or 0.55)
    if hud_cache[id] == key then return end
    hud_cache[id] = key
    runtime_ui.set_quad("hud", id, { x = x, y = y, w = w, h = h, z = 5, style = "text", label = "", fill = { 0.02, 0.03, 0.08, a or 0.55 },
        border = { 0.4, 0.8, 1.0, 0.6 }, corner_radius = 14, no_input = true, visible = visible ~= false })
end
local banner = { text = "", t = 0, alpha = 0, scale = 1 }
local function show_banner(s)
    banner.text, banner.t = s, 2.2
    tween_num(0, 1, 0.35, function(v) banner.alpha = v end, "out")
    tween_num(2.2, 1.0, 0.45, function(v) banner.scale = v end, "back")
end
local score_pop = 1
local function add_score(p)
    local before = score
    score = score + p
    tween_num(1.35, 1.0, 0.25, function(v) score_pop = v end, "out")
    if score >= next_extra then
        next_extra = next_extra + 10000
        lives = lives + 1
        play("extra_life.wav"); show_banner("EXTRA SHIP")
    end
end

local function draw_hud(dt)
    local s = SW / 1920
    local play_vis = state ~= "title"
    text("score", string.format("%06d", score), 40 * s, 24 * s, 420 * s, 70 * s, 2.6 * s * score_pop, CYAN, "left", play_vis)
    local hs = string.format("HI %06d", max(hiscore, score))
    text("hi", hs, SW / 2 - 220 * s, 24 * s, 440 * s, 60 * s, 1.7 * s, { 0.9, 0.9, 1, 0.85 }, "center", true)
    local ships = string.rep("Δ ", min(lives, 10))
    text("lives", ships, 40 * s, 96 * s, 520 * s, 50 * s, 1.8 * s, CYAN, "left", play_vis)
    text("wave", "WAVE " .. wave, SW - 380 * s, 24 * s, 340 * s, 60 * s, 1.7 * s, MAG, "right", play_vis)
    -- banner
    if banner.t > 0 then banner.t = banner.t - dt; if banner.t < 0.4 then banner.alpha = max(0, banner.t / 0.4) end end
    text("banner", banner.text, 0, SH * 0.36, SW, 120 * s, 3.2 * s * banner.scale, { 1, 0.8, 0.4, banner.alpha }, "center", banner.t > 0 and state == "play")

    -- title
    local tvis = state == "title" and not set_open
    local pulse = 0.55 + 0.45 * sin(title_t * 4)
    text("title", "A S T E R O I D S", 0, SH * 0.22, SW, 200 * s, 6.0 * s, { 0.6, 1.0, 1.0, 1 }, "center", tvis)
    text("subtitle", "N E O N  ·  E D I T I O N", 0, SH * 0.36, SW, 70 * s, 1.9 * s, MAG, "center", tvis)
    text("press", "", 0, SH * 0.56, SW, 80 * s, 2.0 * s, { 1, 1, 1, pulse }, "center", false)  -- replaced by the clickable START button
    panel("ctl_panel", SW / 2 - 470 * s, SH * 0.66, 940 * s, 250 * s, tvis, 0.45)
    text("ctl1", "A / D  TURN  ·  SPACE  THRUST  ·  LEFT CLICK  FIRE", SW / 2 - 470 * s, SH * 0.66 + 20 * s, 940 * s, 60 * s, 1.15 * s, CYAN, "center", tvis)
    text("ctl2", "SHIFT / H  HYPERSPACE  ·  P / ESC  PAUSE  ·  M  MUTE  ·  O  SETTINGS", SW / 2 - 470 * s, SH * 0.66 + 85 * s, 940 * s, 60 * s, 1.15 * s, CYAN, "center", tvis)
    text("ctl3", "20 · 50 · 100  ROCKS        200 · 1000  SAUCERS        EXTRA SHIP EVERY 10000", SW / 2 - 470 * s, SH * 0.66 + 150 * s, 940 * s, 60 * s, 1.0 * s, { 1, 0.75, 0.45, 1 }, "center", tvis)
    -- pause
    local pvis = state == "pause" and not set_open
    panel("pause_panel", SW / 2 - 360 * s, SH * 0.35, 720 * s, 260 * s, pvis, 0.7)
    text("pause", "PAUSED", 0, SH * 0.37, SW, 120 * s, 4.0 * s, CYAN, "center", pvis)
    text("pause2", "P  RESUME      O  SETTINGS      Q  QUIT TO TITLE", 0, SH * 0.37 + 140 * s, SW, 60 * s, 1.3 * s, WHITE, "center", pvis)
    -- game over
    local ovis = state == "over"
    local over_label = "FINAL SCORE  " .. score
    if score >= hiscore and score > 0 and not jev:assisted() then
        over_label = "NEW HIGH SCORE  " .. score
    end
    text("over", "GAME  OVER", 0, SH * 0.33, SW, 150 * s, 5.0 * s, { 1, 0.35, 0.6, min(1, game_over_t) }, "center", ovis)
    text("over2", over_label, 0, SH * 0.48, SW, 80 * s, 2.0 * s, { 1, 0.85, 0.4, min(1, game_over_t) }, "center", ovis)
    text("over3", "PRESS ENTER", 0, SH * 0.58, SW, 70 * s, 1.6 * s, { 1, 1, 1, game_over_t > 1.5 and pulse or 0 }, "center", ovis)
end

------------------------------------------------------------------ game flow
local function clear_field()
    for i = #rocks, 1, -1 do release_rock(i) end
    for i = #bullets, 1, -1 do release_bullet(i) end
    saucer.active = false; for _, n in ipairs(saucer_nodes) do n:set_enabled(false) end
end
local function start_wave()
    wave = wave + 1
    local n = min(11, 3 + wave)
    for i = 1, n do
        local x, y
        repeat x, y = rr(-HW, HW), rr(-HH, HH) until wdist2(x, y, ship.x, ship.y) > 100
        if rand() < 0.5 then x = (rand() < 0.5) and -HW or HW else y = (rand() < 0.5) and -HH or HH end
        spawn_rock(3, x, y)
    end
    beat_int = 1.0
    saucer.timer = rr(14, 22) - min(wave, 6)
    show_banner("WAVE " .. wave)
end
local function spawn_ship()
    ship.x, ship.y, ship.vx, ship.vy, ship.a = 0, 0, 0, 0, PI / 2
    ship.alive, ship.inv = true, 2.5
    ship_show(true)
    burst(0, 0, { c0 = vec4(0.5, 1.2, 2.0, 1), c1 = vec4(0.2, 0.2, 1.0, 0), count = 80, spread = 14, smin = 0.05, smax = 0.15, lmin = 0.3, lmax = 0.8 })
end
local function new_game()
    clear_field()
    ship.hyper = 0
    ship.respawn = 0
    wave_delay = 0
    score, lives, wave, next_extra = 0, 3, 0, 10000
    state = "play"
    play("start.wav")
    spawn_ship()
    start_wave()
end
local function to_title()
    clear_field(); ship.alive = false; ship_show(false)
    state = "title"
    wave = 0
    for i = 1, 6 do spawn_rock(({ 3, 3, 2, 2, 1, 3 })[i], rr(-HW, HW), rr(-HH, HH)) end
end

local function explode_rock(i, by_player)
    local r = rocks[i]
    local c = r.g.col
    local n = ({ [3] = 140, [2] = 90, [1] = 55 })[r.size]
    burst(r.x, r.y, { c0 = vec4(c[1], c[2], c[3], 1), c1 = vec4(c[1] * 0.3, c[2] * 0.2, c[3] * 0.6, 0), count = n, spread = 10 + r.size * 5, radius = r.rad * 0.5, smin = 0.1, smax = 0.18 + r.size * 0.1, lmin = 0.4, lmax = 1.2 })
    burst(r.x, r.y, { c0 = vec4(3, 2.2, 1.4, 1), c1 = vec4(1.0, 0.3, 0.1, 0), count = 30 + r.size * 10, spread = 6, radius = r.rad * 0.3, smin = 0.15, smax = 0.3 + r.size * 0.12, lmin = 0.15, lmax = 0.45 })
    flash(r.x, r.y, vec3(c[1], c[2], c[3]), 25 * r.size, 0.35 + 0.1 * r.size)
    add_shake(0.12 * r.size)
    shockwave(r.x, r.y, c, r.rad * 2.2, 0.35 + 0.1 * r.size)
    play(({ [3] = "bang_large.wav", [2] = "bang_medium.wav", [1] = "bang_small.wav" })[r.size])
    if by_player then add_score(POINTS[r.size]) end
    local size, x, y, vx, vy = r.size, r.x, r.y, r.vx, r.vy
    release_rock(i)
    if size > 1 then
        for k = 1, 2 do
            local a = rr(0, TAU)
            local spd = ({ [2] = rr(3, 5.5), [1] = rr(4.5, 8.5) })[size - 1] + min(wave, 8) * 0.15
            spawn_rock(size - 1, x, y, vx * 0.4 + cos(a) * spd, vy * 0.4 + sin(a) * spd)
        end
    end
end

local function kill_ship()
    if not ship.alive then return end
    ship.alive = false; ship_show(false)
    spawn_debris()
    burst(ship.x, ship.y, { c0 = vec4(0.6, 1.6, 2.6, 1), c1 = vec4(1.2, 0.2, 0.8, 0), count = 220, spread = 22, smin = 0.06, smax = 0.25, lmin = 0.5, lmax = 1.6 })
    burst(ship.x, ship.y, { c0 = vec4(4, 3, 2, 1), c1 = vec4(1, 0.2, 0, 0), count = 60, spread = 8, smin = 0.25, smax = 0.6, lmin = 0.2, lmax = 0.5 })
    flash(ship.x, ship.y, vec3(0.6, 0.9, 1.0), 80, 0.8)
    add_shake(1.2)
    shockwave(ship.x, ship.y, { 0.6, 1.4, 2 }, 9, 0.9)
    play("ship_explode.wav")
    lives = lives - 1
    if lives <= 0 then
        state = "over"; game_over_t = 0
        if score > hiscore and not jev:assisted() then hiscore = score; save_hi() end
    else
        ship.respawn = 2.5
    end
end

local function destroy_saucer(by_player)
    local n = saucer_nodes[saucer.kind]
    n:set_enabled(false); saucer.active = false
    burst(saucer.x, saucer.y, { c0 = vec4(2.6, 0.6, 2.2, 1), c1 = vec4(2, 1, 0.2, 0), count = 160, spread = 18, smin = 0.06, smax = 0.25, lmin = 0.4, lmax = 1.2 })
    flash(saucer.x, saucer.y, vec3(1, 0.4, 1), 60, 0.6)
    add_shake(0.6)
    shockwave(saucer.x, saucer.y, { 2, 0.5, 1.8 }, 6, 0.6)
    play("bang_large.wav")
    if by_player then add_score(saucer.kind == 1 and 200 or 1000) end
    saucer.timer = rr(10, 18) - min(wave, 6)
end
local function spawn_saucer()
    local small = score > 40000 or (score > 10000 and rand() < 0.5) or (wave >= 3 and rand() < 0.3)
    saucer.kind = small and 2 or 1
    saucer.active = true
    saucer.dir = rand() < 0.5 and 1 or -1
    saucer.x = -saucer.dir * HW; saucer.y = rr(-HH * 0.8, HH * 0.8)
    saucer.vx = saucer.dir * (small and 7.5 or 5.0); saucer.vy = 0
    saucer.turn = rr(1, 2.5); saucer.shot = 1.0; saucer.travel = 0
    saucer.rad = small and 1.1 or 1.9
    saucer_nodes[saucer.kind]:set_enabled(true)
end

local function hyperspace()
    burst(ship.x, ship.y, { c0 = vec4(1.0, 2.0, 3.0, 1), c1 = vec4(0.6, 0.2, 2, 0), count = 120, spread = 4, radius = 1.2, smin = 0.05, smax = 0.2, lmin = 0.3, lmax = 0.8, drag = 0.2 })
    play("hyperspace.wav")
    ship.alive = false; ship_show(false)
    ship.hyper = 0.6
    ship.vx, ship.vy = 0, 0
    ship.x, ship.y = rr(-HW * 0.9, HW * 0.9), rr(-HH * 0.9, HH * 0.9)
end

------------------------------------------------------------------ input edge detection
local prev = {}
local keyfn = input.is_key_down_raw or input.is_key_pressed   -- raw: not swallowed while runtime UI is visible
local function down(k) return keyfn(k) end
local function pressed(k)
    local d = down(k)
    local p = prev[k]; prev[k] = d
    return d and not p
end
local muted = false
-- left mouse button edge (fire). Sampled once per frame in update(); _G.AST_VMOUSE lets automation click.
local mouse_prev, mouse_click = false, false
local function sample_mouse()
    local ok, d = pcall(input.is_left_mouse_down)
    d = (ok and d) or (_G.AST_VMOUSE == true)
    mouse_click = d and not mouse_prev
    mouse_prev = d
end

-- Simple autopilot used only for unattended screenshot capture (AST_DEMO=1)
local demo = { fire = false, thrust = false, turn = 0 }
local function autopilot()
    local best, bd = nil, 1e9
    for _, r in ipairs(rocks) do local d = wdist2(r.x, r.y, ship.x, ship.y); if d < bd then best, bd = r, d end end
    demo.turn, demo.fire, demo.thrust = 0, false, false
    if best then
        local want = math.atan2(best.y - ship.y, best.x - ship.x)
        local diff = (want - ship.a + PI) % TAU - PI
        demo.turn = diff > 0.08 and 1 or (diff < -0.08 and -1 or 0)
        demo.fire = abs(diff) < 0.3 and rand() < 0.35
        demo.thrust = bd > 120 and rand() < 0.4
    end
end

-- Virtual holds sit beside the hardware reads. Hyperspace is a one-shot pulse.
local hold = { left = false, right = false, thrust = false, fire = false }
local hyper_pulse = false
local HUMAN_KEYS = {
    "A", "D", "Left", "Right",
    "W", "Up", "Space",
    "H", "Left Shift", "Right Shift",
}
local human_prev = {}
local human_edge_now = false

local function clear_hold()
    hold.left = false
    hold.right = false
    hold.thrust = false
    hold.fire = false
    hyper_pulse = false
end

local function sample_human()
    local edge = false
    local raw = input.is_key_down_raw

    for i = 1, #HUMAN_KEYS do
        local key = HUMAN_KEYS[i]
        local down_now = false
        if raw then
            down_now = raw(key) and true or false
        end
        if down_now and not human_prev[key] then
            edge = true
        end
        human_prev[key] = down_now
    end

    human_edge_now = edge
end

------------------------------------------------------------------ update
local shots_taken, run_t = 0, 0
local flicker = 0
local function update_ship(dt)
    if ship.hyper > 0 then
        ship.hyper = ship.hyper - dt
        if ship.hyper <= 0 then
            ship.alive = true; ship_show(true)
            burst(ship.x, ship.y, { c0 = vec4(1.0, 2.0, 3.0, 1), c1 = vec4(0.6, 0.2, 2, 0), count = 120, spread = 16, smin = 0.05, smax = 0.2, lmin = 0.2, lmax = 0.6 })
            if rand() < 0.04 + min(#rocks, 30) * 0.004 then kill_ship() end -- original: hyperspace can kill you
        end
        return
    end
    if not ship.alive then
        if state == "play" and lives > 0 and ship.respawn > 0 then
            ship.respawn = ship.respawn - dt
            if ship.respawn <= 0 then
                local safe = true
                for _, r in ipairs(rocks) do if wdist2(r.x, r.y, 0, 0) < 36 then safe = false end end
                if safe then spawn_ship() else ship.respawn = 0.2 end
            end
        end
        return
    end
    if AUTOPILOT then autopilot() end
    local left = down("Left") or down("A") or hold.left or (AUTOPILOT and demo.turn > 0)
    local right = down("Right") or down("D") or hold.right or (AUTOPILOT and demo.turn < 0)
    local thrust = down("Space") or down("Up") or down("W") or hold.thrust or (AUTOPILOT and demo.thrust)
    if left then ship.a = ship.a + 4.6 * dt end
    if right then ship.a = ship.a - 4.6 * dt end
    local c, s = cos(ship.a), sin(ship.a)
    if thrust then
        ship.vx = ship.vx + c * 20 * dt; ship.vy = ship.vy + s * 20 * dt
        thrust_snd_t = thrust_snd_t - dt
        if thrust_snd_t <= 0 then play("thrust.wav"); thrust_snd_t = 0.85 end
    else thrust_snd_t = 0 end
    local sp = sqrt(ship.vx ^ 2 + ship.vy ^ 2)
    if sp > 22 then ship.vx, ship.vy = ship.vx / sp * 22, ship.vy / sp * 22 end
    local damp = 0.55 ^ dt  -- gentle friction like the arcade
    ship.vx, ship.vy = ship.vx * damp, ship.vy * damp
    ship.x, ship.y = ship.x + ship.vx * dt, ship.y + ship.vy * dt
    wrap(ship)
    -- fire
    local nplayer = 0
    for _, b in ipairs(bullets) do if not b.hostile then nplayer = nplayer + 1 end end
    if (mouse_click or hold.fire or (AUTOPILOT and demo.fire)) and nplayer < 4 then
        fire(ship.x + c * 1.3, ship.y + s * 1.3, ship.vx + c * 30, ship.vy + s * 30, false)
        play("fire.wav")
        flash(ship.x + c * 1.5, ship.y + s * 1.5, vec3(0.6, 0.9, 1), 12, 0.12)
        burst(ship.x + c * 1.3, ship.y + s * 1.3, { c0 = vec4(2, 3, 4, 1), c1 = vec4(0.5, 1, 2, 0), count = 10, spread = 4, vel = { c * 8, s * 8 }, smin = 0.04, smax = 0.1, lmin = 0.08, lmax = 0.2 })
    end
    if pressed("Left Shift") or pressed("H") or pressed("Right Shift") or hyper_pulse then
        hyper_pulse = false
        hyperspace()
        return
    end
    if ship.inv > 0 then ship.inv = ship.inv - dt end
    -- visuals
    local deg = math.deg(ship.a) * FX
    ship.node:set_position(P(ship.x, ship.y, 0.5)); ship.node:set_rotation(vec3(0, 0, deg))
    ship.core:set_position(P(ship.x - c * 0.1, ship.y - s * 0.1, 0))
    ship.core:set_rotation(vec3(0, 0, deg - 90 * FX)); ship.core:set_scale(vec3(0.95, 1.6, 0.35))
    flicker = flicker + dt * 30
    local fl = thrust and (sin(flicker) > -0.3)
    ship.flame:set_enabled(fl)
    if fl then
        ship.flame:set_position(P(ship.x, ship.y, 0.5)); ship.flame:set_rotation(vec3(0, 0, deg))
        ship.flame:set_scale(vec3(rr(0.8, 1.3), 1, 1))
    end
    local blink = ship.inv > 0
    ship.shield:set_enabled(blink)
    if blink then ship.shield:set_position(P(ship.x, ship.y, 0.4)); local k = 1 + 0.08 * sin(run_t * 12); ship.shield:set_scale(vec3(k, k, 1)) end
    particles.set_emitter(thrust_em, {
        position = P(ship.x - c * 0.8, ship.y - s * 0.8, 0.2),
        velocity = P(ship.vx - c * 14, ship.vy - s * 14, 0),
        spawn_rate = thrust and 260 or 0,
    })
end

local function update_world(dt)
    -- rocks
    for _, r in ipairs(rocks) do
        r.x, r.y = r.x + r.vx * dt, r.y + r.vy * dt; wrap(r)
        r.a = r.a + r.va * dt
        r.g.node:set_position(P(r.x, r.y, 0)); r.g.node:set_rotation(vec3(0, 0, math.deg(r.a) * FX))
    end
    -- bullets
    for i = #bullets, 1, -1 do
        local b = bullets[i]
        b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt; wrap(b)
        b.life = b.life - dt
        local dead = b.life <= 0
        if not dead then
            for j = #rocks, 1, -1 do
                local r = rocks[j]
                if wdist2(b.x, b.y, r.x, r.y) < (r.rad + 0.15) ^ 2 then explode_rock(j, not b.hostile); dead = true; break end
            end
        end
        if not dead and not b.hostile and saucer.active and wdist2(b.x, b.y, saucer.x, saucer.y) < saucer.rad ^ 2 then destroy_saucer(true); dead = true end
        if not dead and b.hostile and ship.alive and ship.inv <= 0 and wdist2(b.x, b.y, ship.x, ship.y) < 0.9 then kill_ship(); dead = true end
        if dead then release_bullet(i) else b.node:set_position(P(b.x, b.y, 0.3)) end
    end
    -- ship vs rocks
    if ship.alive and ship.inv <= 0 then
        for j = #rocks, 1, -1 do
            local r = rocks[j]
            if wdist2(ship.x, ship.y, r.x, r.y) < (r.rad + 0.7) ^ 2 then explode_rock(j, true); kill_ship(); break end
        end
        if ship.alive and saucer.active and wdist2(ship.x, ship.y, saucer.x, saucer.y) < (saucer.rad + 0.7) ^ 2 then destroy_saucer(true); kill_ship() end
    end
    -- saucer
    if saucer.active then
        saucer.x = saucer.x + saucer.vx * dt; saucer.y = saucer.y + saucer.vy * dt
        saucer.travel = saucer.travel + abs(saucer.vx * dt)
        if saucer.y > HH then saucer.y = saucer.y - 2 * HH elseif saucer.y < -HH then saucer.y = saucer.y + 2 * HH end
        saucer.turn = saucer.turn - dt
        if saucer.turn <= 0 then saucer.turn = rr(0.8, 2.2); saucer.vy = ({ -1, 0, 1 })[rand(3)] * abs(saucer.vx) * 0.7 end
        saucer.shot = saucer.shot - dt
        if saucer.shot <= 0 and state == "play" then
            saucer.shot = saucer.kind == 1 and 1.1 or 0.85
            local a
            if saucer.kind == 2 and ship.alive then
                local err = max(0.04, 0.35 - score / 100000)
                a = math.atan2(ship.y - saucer.y, ship.x - saucer.x) + rr(-err, err)
            else a = rr(0, TAU) end
            fire(saucer.x, saucer.y, cos(a) * 20, sin(a) * 20, true)
            play("fire.wav")
        end
        saucer_snd_t = saucer_snd_t - dt
        if saucer_snd_t <= 0 then play(saucer.kind == 1 and "saucer_big.wav" or "saucer_small.wav"); saucer_snd_t = 0.95 end
        for j = #rocks, 1, -1 do
            local r = rocks[j]
            if wdist2(saucer.x, saucer.y, r.x, r.y) < (r.rad + saucer.rad * 0.7) ^ 2 then explode_rock(j, false); destroy_saucer(false); break end
        end
        if saucer.active then
            if saucer.travel > 2 * HW then saucer.active = false; saucer_nodes[saucer.kind]:set_enabled(false); saucer.timer = rr(8, 16)
            else
                local n = saucer_nodes[saucer.kind]
                n:set_position(P(saucer.x, saucer.y, 0.4))
                n:set_rotation(vec3(0, 0, 6 * sin(run_t * 5)))
            end
        end
    elseif state == "play" then
        saucer.timer = saucer.timer - dt
        if saucer.timer <= 0 and #rocks > 0 then spawn_saucer() end
    end
    -- debris
    for _, d in ipairs(debris) do
        if d.t > 0 then
            d.t = d.t - dt
            d.x, d.y, d.r = d.x + d.vx * dt, d.y + d.vy * dt, d.r + d.vr * dt
            d.node:set_position(P(d.x, d.y, 0.5)); d.node:set_rotation(vec3(0, 0, math.deg(d.r) * FX))
            local k = clamp(d.t / 2.2, 0, 1)
            emissive(d.node, 0.33 * k, 0.9 * k, 1.3 * k)
            if d.t <= 0 then d.node:set_enabled(false) end
        end
    end
end

local function update_fx(dt)
    update_waves(dt)
    -- flashes
    for _, f in ipairs(flashes) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = max(0, 1 - f.t / f.life)
            lights.set_point_light(f.idx, f.pos, f.col, f.power * k * k, 40)
        end
    end
    -- screen shake (decaying, smooth noise)
    shake = max(0, shake - dt * 2.2)
    shake_t = shake_t + dt
    local a = shake * shake * 1.2 * SET:shake_scale()
    place_camera(a * (sin(shake_t * 53) + 0.5 * sin(shake_t * 97)), a * (cos(shake_t * 61) + 0.5 * sin(shake_t * 83)))
    -- bloom kicks with shake
    S("bloom_strength", 0.55 + shake * 0.375)
end

local function screenshot(name)
    if SHOT_DIR then engine.take_screenshot(SHOT_DIR .. "/" .. name .. ".png") end
end

local function update(dt)
    flush_mats()
    dt = min(dt, 1 / 20)
    sample_human()
    jev:tick(dt)
    run_t = run_t + dt
    title_t = title_t + dt
    update_tweens(dt)
    -- edges sampled every frame, even while settings is open, so its closing ESC is not re-seen
    local k_o, k_tab = pressed("O"), pressed("Tab")
    local k_m, k_p, k_esc, k_ret, k_q = pressed("M"), pressed("P"), pressed("Escape"), pressed("Return"), pressed("Q")
    set_open = SET:update(dt)
    sample_mouse()
    if set_open then mouse_click = false end
    local can_set = (state == "title" or state == "pause")
    local bs = 1.0 * SH / 1080
    runtime_ui.set_quad("hud", "set_btn", { x = SW / 2 - 150 * bs, y = SH * (state == "pause" and 0.62 or 0.47), w = 300 * bs, h = 58 * bs, z = 12,
        style = "text", label = "SETTINGS  (O)", fill = { 0.03, 0.06, 0.16, 0.85 }, border = { 0.4, 1.0, 1.0, 0.9 },
        text_color = { 0.8, 1, 1, 1 }, font_scale = 1.3 * bs, align_h = "center", align_v = "middle", corner_radius = 12,
        visible = can_set and not set_open })
    -- clickable title / pause buttons (mouse); keyboard keys still work
    local function hudbtn(id, label, x, y, vis)
        runtime_ui.set_quad("hud", id, { x = x, y = y, w = 300 * bs, h = 58 * bs, z = 12,
            style = "text", label = label, fill = { 0.03, 0.06, 0.16, 0.85 }, border = { 0.4, 1.0, 1.0, 0.9 },
            text_color = { 0.8, 1, 1, 1 }, font_scale = 1.3 * bs, align_h = "center", align_v = "middle", corner_radius = 12,
            visible = vis })
        local st = vis and runtime_ui.get_state("hud", id)
        return st and st.clicked
    end
    local c_start = hudbtn("start_btn", "START  (ENTER)", SW / 2 - 150 * bs, SH * 0.565, state == "title" and not set_open)
    local c_jev = hudbtn("jev_btn", "JEV", SW / 2 + 170 * bs, SH * 0.565, state == "title" and not set_open)
    local c_resume = hudbtn("resume_btn", "RESUME  (P)", SW / 2 - 480 * bs, SH * 0.62, state == "pause" and not set_open)
    local c_quit = hudbtn("quit_btn", "QUIT TO TITLE  (Q)", SW / 2 + 180 * bs, SH * 0.62, state == "pause" and not set_open)
    local c_over = hudbtn("over_btn", "CONTINUE", SW / 2 - 150 * bs, SH * 0.66, state == "over" and game_over_t > 1.5 and not set_open)
    local btn = runtime_ui.get_state("hud", "set_btn")
    if not set_open and can_set and (k_o or k_tab or (btn and btn.clicked)) then
        play("blip.wav"); SET:open(); set_open = true
    end
    if set_open then k_m, k_p, k_esc, k_ret, k_q = false, false, false, false, false; pressed("Space")
    else
        if c_start or c_over then k_ret = true end
        if c_resume then k_p = true end
        if c_quit then k_q = true end
    end
    local edge = pressed
    local function pressed(k)   -- this frame's edges (shadows the sampler above); Space stays live for update_ship
        if k == "M" then return k_m elseif k == "P" then return k_p elseif k == "Escape" then return k_esc
        elseif k == "Return" then return k_ret elseif k == "Q" then return k_q end
        return not set_open and edge(k)
    end
    if pressed("M") then muted = SET:toggle_mute() end
    if state == "title" then
        update_world(dt)
        local start_key = pressed("Return") or pressed("Space")
        if c_jev then
            play("blip.wav")
            if not jev:start() then
                local message = jev:error() or "Jev could not start."
                pe_log("[asteroids] " .. message)
                show_banner(message)
            end
        elseif start_key or (AUTOPILOT and run_t > 3) then
            if start_key then
                jev:begin_human()
            end
            play("blip.wav")
            new_game()
        end
    elseif state == "play" then
        if pressed("P") or pressed("Escape") then state = "pause"; play("blip.wav")
        else
            update_ship(dt)
            update_world(dt)
            -- heartbeat
            beat_t = beat_t - dt
            if beat_t <= 0 and ship.alive then
                beat_flip = not beat_flip; play(beat_flip and "beat1.wav" or "beat2.wav")
                beat_int = max(0.25, beat_int - 0.012); beat_t = beat_int
            end
            if #rocks == 0 and not saucer.active then
                wave_delay = wave_delay + dt
                if wave_delay > 2.0 then wave_delay = 0; start_wave() end
            end
        end
    elseif state == "pause" then
        if pressed("P") or pressed("Escape") or pressed("Return") then state = "play"; play("blip.wav") end
        if pressed("Q") then to_title() end
    elseif state == "over" then
        game_over_t = game_over_t + dt
        update_world(dt)
        if game_over_t > 1.5 and (pressed("Return") or pressed("Space")) then play("blip.wav"); to_title() end
    end
    if not ship.alive and ship.hyper <= 0 then particles.set_emitter(thrust_em, { spawn_rate = 0 }) end
    update_fx(dt)
    draw_hud(dt)
    -- unattended capture sequence
    if SHOT_DIR then
        local plan = { { 2.5, "01_title" }, { 9, "02_gameplay" }, { 12.6, "03_action" }, { 17, "04_late" } }
        for _, p in ipairs(plan) do if run_t >= p[1] and run_t - dt < p[1] then screenshot(p[2]) end end
        if AUTOPILOT and run_t > 10.5 and run_t - dt <= 10.5 then spawn_saucer() end
        if AUTOPILOT and run_t > 12.4 and run_t - dt <= 12.4 and #rocks > 0 then explode_rock(1, true) end
        if AUTO_QUIT and run_t > 17.5 then engine.quit() end
    end
end

local function match_score()
    return score
end

local function nearest_rock()
    local best = nil
    local best_d = math.huge

    for i = 1, #rocks do
        local rock = rocks[i]
        local dist2 = wdist2(rock.x, rock.y, ship.x, ship.y)
        if dist2 < best_d then
            best = rock
            best_d = dist2
        end
    end

    if not best then
        return 0, -1
    end

    local dx = best.x - ship.x
    local dy = best.y - ship.y
    if dx > HW then
        dx = dx - 2 * HW
    elseif dx < -HW then
        dx = dx + 2 * HW
    end
    if dy > HH then
        dy = dy - 2 * HH
    elseif dy < -HH then
        dy = dy + 2 * HH
    end

    return math.atan2(dy, dx), sqrt(dx * dx + dy * dy)
end

local function observe_match()
    local rock_angle, rock_distance = nearest_rock()
    local ship_angle = (ship.a + PI) % TAU - PI
    local speed = sqrt(ship.vx * ship.vx + ship.vy * ship.vy)

    return {
        ship_angle = ship_angle,
        speed = speed,
        nearest_rock_angle = rock_angle,
        nearest_rock_distance = rock_distance,
        lives = lives,
        score = score,
    }
end

local function apply_action(id)
    hold.left = false
    hold.right = false
    hold.thrust = false
    hold.fire = false
    hyper_pulse = false

    if id == "left" then
        hold.left = true
        hold.fire = true
    elseif id == "right" then
        hold.right = true
        hold.fire = true
    elseif id == "thrust_fire" then
        hold.thrust = true
        hold.fire = true
    end
end

local function jev_actions()
    local rock_angle, rock_distance = nearest_rock()
    if not rock_distance or rock_distance < 0 then
        return { { id = "thrust_fire", description = "Thrust. The gun keeps firing.", score = 1 } }
    end
    local ship_angle = (ship.a + PI) % TAU - PI
    local err = (rock_angle - ship_angle + PI) % TAU - PI
    if err > 0.28 then
        return { { id = "left", description = "Turn left toward the rock. The gun keeps firing.", score = err } }
    end
    if err < -0.28 then
        return { { id = "right", description = "Turn right toward the rock. The gun keeps firing.", score = -err } }
    end
    return { { id = "thrust_fire", description = "Facing the rock. Thrust and fire.", score = 1 } }
end

local jev_src = fs.read("Scripts/jev_auto.lua")
if not jev_src then
    error("Missing Scripts/jev_auto.lua")
end

local jev_loader, jev_err = load(jev_src, "@Scripts/jev_auto.lua", "t", _ENV)
if not jev_loader then
    error(jev_err)
end

local JevAuto = jev_loader()

jev = JevAuto.attach({
    port = 9105,
    id = "neon_asteroids",
    description = "Neon Asteroids. The offered action turns toward the nearest rock or thrusts once lined up, and the gun keeps firing. Prefer the higher action score.",
    playing = function()
        return state == "play"
    end,
    terminal = function()
        return state == "over"
    end,
    score = match_score,
    busy = function()
        return ship.hyper > 0
    end,
    human_edge = function()
        return human_edge_now
    end,
    observe = observe_match,
    actions = jev_actions,
    apply = apply_action,
    reset = function(seed)
        math.randomseed(seed)
        clear_hold()
        new_game()
    end,
    on_human = clear_hold,
})

to_title()
hooks { update = update }
pe_log("[asteroids] ready  field " .. HW .. " x " .. HH)
