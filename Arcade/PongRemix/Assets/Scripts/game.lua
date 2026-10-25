-- Pong Remix  (PhasmaEngine, Lua)
-- Modern remake of Atari's Pong (1972): 1P vs AI + local 2P.
-- Visuals: cooked bevelled paddles, emissive faces, arena rails, ball trails,
-- impact sparks/rings, dynamic lights, HDR + TAA + smooth bloom.
local PI, TAU = math.pi, math.pi * 2
local sin, cos, sqrt, rand, floor, abs, min, max = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function sign(v) return v < 0 and -1 or 1 end
local G = { state = "boot", t = 0, mode = "1p", score = {0, 0}, hiscore = 0 }
_G.PR = G

------------------------------------------------------------------ deferred materials
local _mset, _mtex, _mds = material.set, material.set_texture, material.set_double_sided
local mat_q = {}
local function qpush(f) mat_q[#mat_q + 1] = { f = f, n = 0 } end
local function mset(n, k, v) pcall(_mset, n, k, v); qpush(function() pcall(_mset, n, k, v) end) end
local function mtex(n, k, v) qpush(function() pcall(_mtex, n, k, v) end) end
local function flush_mats()
    for i = #mat_q, 1, -1 do
        local q = mat_q[i]; q.n = q.n + 1
        if q.n == 2 or q.n == 6 then q.f() end
        if q.n >= 6 then table.remove(mat_q, i) end
    end
end
local function mlive(n, k, v) pcall(_mset, n, k, v) end
local function paint(n, base, emis, rough, metal)
    mset(n, "base_color", vec4(base[1], base[2], base[3], 1))
    mset(n, "emissive", vec3(emis[1], emis[2], emis[3]))
    mset(n, "roughness", rough or 0.3)
    mset(n, "metallic", metal or 0.0)
end

------------------------------------------------------------------ audio
local function sfx(name) pcall(audio.play, name .. ".wav") end

------------------------------------------------------------------ court
local HALF_W, HALF_H = 16.0, 10.0
local PADDLE_X = 14.2
local PADDLE_H, PADDLE_W = 2.6, 0.55
local BALL_R = 0.38
local WIN_SCORE = 11
local BALL_SPEED0, BALL_SPEED_MAX = 14.0, 26.0

------------------------------------------------------------------ render (HDR + TAA, CAS off, smooth bloom — RENDER_SETTINGS addendum)
local function S(k, v) pcall(settings.set, k, v) end
local ss = scene.add_empty_node("PongSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "studio.hdr")
S("taa", true)
S("cas_sharpening", false)   -- CAS off (user/addendum); with hdr=true bloom still survives either way
S("hdr", true)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.5)
S("tonemapping", true); S("fxaa", false); S("motion_blur", false)
S("ssao", false); S("ssr", false); S("dof", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0)
S("IBL", true); S("IBL_intensity", 1.05)
S("color_grading", true); S("color_grading_saturation", 1.08); S("color_grading_contrast", 1.06)

local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1280, surf.height or 720
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local CAM_BASE = vec3(0, -0.4, 42.0)
local CAM_LOOK = vec3(0, 0.0, 0)
local FOVX = 0.98
pcall(function() cam:set_fov(math.deg(FOVX)) end)
cam:set_position(CAM_BASE); cam:look_at(CAM_LOOK)

------------------------------------------------------------------ templates
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[Pong] missing template " .. name); return nil end
    TPL[name] = { node = n, mesh = n:get_mesh_refs()[1] }
    return TPL[name]
end
local seq = 0
local function clone(name, pos, scale, parent)
    local t = tpl(name); seq = seq + 1
    local n = scene.add_empty_node(name .. "_c" .. seq)
    if t and t.mesh then n:add_mesh_ref(t.mesh) end
    if parent then n:set_parent(parent) end
    n:set_position(pos or vec3(0, 0, 0))
    if scale then n:set_scale(scale) end
    return n
end
local function prim(kind, pos, scale)
    seq = seq + 1
    local n = scene.add_empty_node(kind .. "_p" .. seq)
    scene.attach_primitive(n, kind)
    n:set_position(pos); n:set_scale(scale)
    return n
end
local HIDE = vec3(0, -1000, 0)

------------------------------------------------------------------ palette
local COL_L = { 0.25, 0.85, 1.00 }   -- cool teal (player 1)
local COL_R = { 1.00, 0.45, 0.28 }   -- warm coral (player 2 / AI)
local COL_BALL = { 0.95, 0.96, 1.00 }
local COL_NET = { 0.45, 0.70, 1.00 }

------------------------------------------------------------------ world
local function paint_templates()
    local function paddle_slot(side, c)
        local b, f, e = tpl("T_paddle_" .. side), tpl("T_pface_" .. side), tpl("T_pedge_" .. side)
        paint(b.node, { c[1] * 0.55, c[2] * 0.55, c[3] * 0.55 }, { c[1] * 0.15, c[2] * 0.15, c[3] * 0.15 }, 0.18, 0.65)
        paint(f.node, c, { c[1] * 1.4, c[2] * 1.4, c[3] * 1.4 }, 0.25, 0.0)
        paint(e.node, c, { c[1] * 0.9, c[2] * 0.9, c[3] * 0.9 }, 0.3, 0.1)
    end
    paddle_slot("L", COL_L); paddle_slot("R", COL_R)
    paint(tpl("T_ball").node, { 0.85, 0.88, 0.95 }, { 0.55, 0.65, 0.9 }, 0.12, 0.4)
    paint(tpl("T_ball_core").node, COL_BALL, { 1.6, 1.7, 2.2 }, 0.2, 0.0)
    paint(tpl("T_ghost").node, { 0.5, 0.7, 1.0 }, { 0.3, 0.5, 0.9 }, 0.4, 0.0)
    paint(tpl("T_rail").node, { 0.42, 0.46, 0.55 }, { 0, 0, 0 }, 0.18, 1.0)
    paint(tpl("T_rail_glow").node, COL_NET, { 0.4, 0.9, 1.5 }, 0.3, 0)
    paint(tpl("T_floor").node, { 0.06, 0.07, 0.11 }, { 0.35, 0.4, 0.55 }, 0.45, 0.55)
    for i = 0, 11 do
        local m = tpl("T_marker_" .. i)
        if m then paint(m.node, COL_NET, { 0.35, 0.7, 1.2 }, 0.3, 0.1) end
    end
    for i = 0, 7 do
        local r = tpl("T_ring_" .. i)
        if r then paint(r.node, { 1, 1, 1 }, { 1.2, 1.4, 2.0 }, 0.2, 0.0) end
    end
    for i = 0, 9 do
        local s = tpl("T_shard_" .. i)
        if s then
            local c = (i % 2 == 0) and COL_L or COL_R
            paint(s.node, c, { c[1] * 1.3, c[2] * 1.3, c[3] * 1.3 }, 0.25, 0.2)
        end
    end
end

local function build_world()
    local bg = prim("quad", vec3(0, 0, -28), vec3(120, 75, 1))
    paint(bg, { 0, 0, 0 }, { 0.5, 0.52, 0.58 }, 1.0, 0.0)
    pcall(_mds, bg, true); qpush(function() pcall(_mds, bg, true) end)
    mtex(bg, "emissive", "Textures/backdrop.png")
    G.backdrop = bg
    -- glossy playfield plate
    local plate = clone("T_floor", vec3(0, 0, -0.9), vec3(HALF_W * 2 + 1.2, HALF_H * 2 + 1.2, 1.0))
    mtex(plate, "emissive", "Textures/playfield.png")
    G.plate = plate
    -- frame rails (top / bottom; open sides for goals)
    local T = 0.55
    local rails = {
        { vec3(0, HALF_H + T * 0.5, 0), vec3(HALF_W * 2 + T * 2, T, 1.1) },
        { vec3(0, -HALF_H - T * 0.5, 0), vec3(HALF_W * 2 + T * 2, T, 1.1) },
    }
    for _, r in ipairs(rails) do clone("T_rail", r[1], r[2]) end
    -- neon glow strips on rails
    local g = 0.18
    clone("T_rail_glow", vec3(0, HALF_H + g * 0.15, 0.65), vec3(HALF_W * 2 + 0.4, g, 0.1))
    clone("T_rail_glow", vec3(0, -HALF_H - g * 0.15, 0.65), vec3(HALF_W * 2 + 0.4, g, 0.1))
    G.rail_glow = tpl("T_rail_glow").node
    -- centre net markers
    G.markers = {}
    for i = 0, 11 do
        local y = -HALF_H + 0.9 + i * ((HALF_H * 2 - 1.8) / 11)
        local n = clone("T_marker_" .. i, vec3(0, y, 0.15), vec3(0.35, 0.55, 0.5))
        G.markers[#G.markers + 1] = n
    end
    -- goal glow posts (subtle)
    G.goal_L = clone("T_rail_glow", vec3(-HALF_W - 0.15, 0, 0.4), vec3(0.12, HALF_H * 2 - 0.4, 0.08))
    G.goal_R = clone("T_rail_glow", vec3(HALF_W + 0.15, 0, 0.4), vec3(0.12, HALF_H * 2 - 0.4, 0.08))
end

------------------------------------------------------------------ lights
local function add_point()
    lights.add_point()
    return #lights.get_point_lights() - 1
end
local LNODE = {}
local LIGHT_GAIN = 0.12
local function set_point(i, pos, col, inten, rad)
    pcall(lights.set_point_light, i, pos, col, inten * LIGHT_GAIN, rad)
    local n = LNODE[i]
    if n == nil then
        local l = lights.get_point_lights()[i + 1]
        n = (l and scene.find_model(l.name)) or false
        LNODE[i] = n
    end
    if n then n:set_position(pos) end
end
local L = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(-0.2, -0.5, -1.0), vec3(0.85, 0.88, 1.0), 1.4)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    L.key_l = addp(vec3(-12, 6, 14), vec3(0.3, 0.75, 1.0), 70, 55)
    L.key_r = addp(vec3(12, 6, 14), vec3(1.0, 0.4, 0.3), 70, 55)
    L.fill = addp(vec3(0, 0, 18), vec3(0.7, 0.75, 0.9), 40, 70)
    L.pad_l = addp(vec3(-PADDLE_X, 0, 3), vec3(COL_L[1], COL_L[2], COL_L[3]), 20, 10)
    L.pad_r = addp(vec3(PADDLE_X, 0, 3), vec3(COL_R[1], COL_R[2], COL_R[3]), 20, 10)
    L.ball = addp(HIDE, vec3(1, 1, 1), 0, 1)
    L.flash = {}
    for i = 1, 6 do L.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1, pos = HIDE, col = vec3(1, 1, 1), power = 0, rad = 6 } end
end
local flash_next = 1
local function flash(x, y, col, power, life, rad)
    local f = L.flash[flash_next]; flash_next = flash_next % #L.flash + 1
    f.t, f.life, f.pos, f.col, f.power, f.rad = 0, life or 0.3, vec3(x, y, 2.0), vec3(col[1], col[2], col[3]), power or 28, rad or 7
end
local function update_flashes(dt)
    for _, f in ipairs(L.flash) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = 1 - clamp(f.t / f.life, 0, 1)
            set_point(f.idx, f.pos, f.col, f.power * k * k, f.rad)
            if f.t >= f.life then set_point(f.idx, HIDE, f.col, 0, 1) end
        end
    end
end

------------------------------------------------------------------ particles / VFX
local PSCALE, SHAKE_SCALE = 1.0, 1.0
local shake = 0
local function add_shake(a) shake = min(1.2, shake + a) end
local function burst(x, y, o)
    pcall(particles.emit_burst, {
        position = vec3(x, y, o.z or 0.6), velocity = o.vel or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = max(1, floor((o.count or 36) * PSCALE)),
        size_min = o.smin or 0.04, size_max = o.smax or 0.14, life_min = o.lmin or 0.2, life_max = o.lmax or 0.55,
        spawn_radius = o.radius or 0.2, noise_strength = o.spread or 12, drag = o.drag or 2.2,
        gravity = o.grav or vec3(0, -6, 0), cleanup_delay = 2.0,
    })
end
-- fix: particles API may use noise_strength; try both via pcall in burst — check breakout used noise_strength
local function sparks(x, y, col, n, spd, z)
    burst(x, y, { c0 = vec4(col[1], col[2], col[3], 1), c1 = vec4(col[1] * 0.2, col[2] * 0.2, col[3] * 0.2, 0),
        count = n or 40, spread = spd or 16, z = z or 0.8, smin = 0.03, smax = 0.12, lmin = 0.15, lmax = 0.5 })
end

-- impact rings pool
local rings = {}
local function build_rings()
    for i = 0, 7 do
        local n = clone("T_ring_" .. i, HIDE, vec3(0.01, 0.01, 0.01))
        rings[i + 1] = { node = n, t = 1, life = 0.4, x = 0, y = 0, col = COL_BALL }
    end
end
local ring_i = 1
local function spawn_ring(x, y, col)
    local r = rings[ring_i]; ring_i = ring_i % #rings + 1
    r.t, r.life, r.x, r.y, r.col = 0, 0.45, x, y, col or COL_BALL
end
local function update_rings(dt)
    for _, r in ipairs(rings) do
        if r.t < r.life then
            r.t = r.t + dt
            local k = r.t / r.life
            local sc = 0.4 + k * 2.8
            r.node:set_position(vec3(r.x, r.y, 0.5))
            r.node:set_scale(vec3(sc, sc, 0.3))
            local a = 1 - k
            mlive(r.node, "emissive", vec3(r.col[1] * 2 * a, r.col[2] * 2 * a, r.col[3] * 2.2 * a))
            if r.t >= r.life then r.node:set_position(HIDE) end
        end
    end
end

-- shards
local shards = {}
local function build_shards()
    for i = 0, 9 do
        local n = clone("T_shard_" .. i, HIDE, vec3(0.5, 0.5, 0.5))
        shards[i + 1] = { node = n, alive = false, x = 0, y = 0, vx = 0, vy = 0, life = 0, t = 0, rot = 0, rv = 0 }
    end
end
local shard_i = 1
local function spawn_shards(x, y, col, n)
    n = min(n or 6, #shards)
    for k = 1, n do
        local s = shards[shard_i]; shard_i = shard_i % #shards + 1
        s.alive, s.x, s.y = true, x, y
        local a = rr(0, TAU)
        local sp = rr(4, 14)
        s.vx, s.vy = cos(a) * sp, sin(a) * sp
        s.t, s.life, s.rot, s.rv = 0, rr(0.35, 0.7), rr(0, 360), rr(-400, 400)
        s.node:set_position(vec3(x, y, 0.4))
    end
end
local function update_shards(dt)
    for _, s in ipairs(shards) do
        if s.alive then
            s.t = s.t + dt; s.vy = s.vy - 18 * dt
            s.x = s.x + s.vx * dt; s.y = s.y + s.vy * dt; s.rot = s.rot + s.rv * dt
            local k = 1 - s.t / s.life
            s.node:set_position(vec3(s.x, s.y, 0.4))
            s.node:set_scale(vec3(0.6 * k, 0.6 * k, 0.6 * k))
            pcall(s.node.set_euler, s.node, vec3(s.rot * 0.01, s.rot * 0.02, s.rot))
            if s.t >= s.life then s.alive = false; s.node:set_position(HIDE) end
        end
    end
end

------------------------------------------------------------------ paddles + ball
local PAD = {
    L = { y = 0, target = 0, vy = 0, h = PADDLE_H, glow = 0, squash = 0, nodes = {} },
    R = { y = 0, target = 0, vy = 0, h = PADDLE_H, glow = 0, squash = 0, nodes = {} },
}
local BALL = { x = 0, y = 0, vx = 0, vy = 0, speed = BALL_SPEED0, stuck = true, trail = {}, nodes = {}, em = nil }

local function build_paddles()
    for _, side in ipairs({"L", "R"}) do
        local p = PAD[side]
        local sx = (side == "L") and -PADDLE_X or PADDLE_X
        p.nodes.body = clone("T_paddle_" .. side, vec3(sx, 0, 0), vec3(PADDLE_W / 0.36, PADDLE_H / 1.8, 1.0))
        p.nodes.face = clone("T_pface_" .. side, vec3(sx + (side == "L" and 0.22 or -0.22), 0, 0.35), vec3(1.0, PADDLE_H / 1.6, 1.0))
        p.nodes.edge = clone("T_pedge_" .. side, vec3(sx, 0, 0.2), vec3(PADDLE_W / 0.2, PADDLE_H / 1.85, 0.8))
        p.x = sx
    end
end

local function draw_paddle(side)
    local p = PAD[side]
    local sq = 1 - 0.12 * p.squash
    local scy = (PADDLE_H / 1.8) * sq
    local scx = (PADDLE_W / 0.36) / sq
    p.nodes.body:set_position(vec3(p.x, p.y, 0))
    p.nodes.body:set_scale(vec3(scx, scy, 1.0))
    local fx = p.x + (side == "L" and 0.22 or -0.22)
    p.nodes.face:set_position(vec3(fx, p.y, 0.35))
    p.nodes.face:set_scale(vec3(1.0, (PADDLE_H / 1.6) * sq, 1.0))
    p.nodes.edge:set_position(vec3(p.x, p.y, 0.2))
    p.nodes.edge:set_scale(vec3(PADDLE_W / 0.2, (PADDLE_H / 1.85) * sq, 0.8))
    -- pulse face emissive on hit
    local c = (side == "L") and COL_L or COL_R
    local g = 1.2 + 1.8 * p.glow
    mlive(p.nodes.face, "emissive", vec3(c[1] * g, c[2] * g, c[3] * g))
end

local function build_ball()
    BALL.nodes.body = clone("T_ball", HIDE, vec3(BALL_R * 2, BALL_R * 2, BALL_R * 2))
    BALL.nodes.core = clone("T_ball_core", HIDE, vec3(BALL_R * 1.2, BALL_R * 1.2, BALL_R * 1.2))
    BALL.ghosts = {}
    for i = 1, 6 do
        BALL.ghosts[i] = clone("T_ghost", HIDE, vec3(BALL_R * 1.6, BALL_R * 1.6, BALL_R * 1.6))
    end
    local ok, em = pcall(particles.add_emitter, {
        position = HIDE, velocity = vec3(0, 0, 0), gravity = vec3(0, 0, 0),
        color_start = vec4(0.6, 0.85, 1.0, 0.7), color_end = vec4(0.2, 0.4, 0.9, 0),
        spawn_rate = 0.0, size_min = 0.04, size_max = 0.1, life_min = 0.15, life_max = 0.4,
        spawn_radius = 0.05, noise_strength = 0.5, drag = 1.5, cleanup_delay = 999,
    })
    if ok then BALL.em = em end
end

local function draw_ball(dt)
    if BALL.stuck then
        BALL.nodes.body:set_position(HIDE); BALL.nodes.core:set_position(HIDE)
        for _, g in ipairs(BALL.ghosts) do g:set_position(HIDE) end
        if BALL.em then pcall(particles.set_emitter, BALL.em, "spawn_rate", 0.0); pcall(particles.set_emitter, BALL.em, "position", HIDE) end
        set_point(L.ball, HIDE, vec3(1, 1, 1), 0, 1)
        return
    end
    BALL.nodes.body:set_position(vec3(BALL.x, BALL.y, 0.2))
    BALL.nodes.core:set_position(vec3(BALL.x, BALL.y, 0.25))
    local pulse = 1.0 + 0.08 * sin(G.t * 14)
    BALL.nodes.body:set_scale(vec3(BALL_R * 2 * pulse, BALL_R * 2 * pulse, BALL_R * 2 * pulse))
    -- trail ghosts
    BALL.trail = BALL.trail or {}
    BALL.trail[#BALL.trail + 1] = { x = BALL.x, y = BALL.y, t = 0 }
    while #BALL.trail > 12 do table.remove(BALL.trail, 1) end
    for i, g in ipairs(BALL.ghosts) do
        local idx = #BALL.trail - i * 2
        if idx >= 1 then
            local tr = BALL.trail[idx]
            local a = 1 - i / (#BALL.ghosts + 1)
            g:set_position(vec3(tr.x, tr.y, 0.1))
            local sc = BALL_R * 1.5 * a
            g:set_scale(vec3(sc, sc, sc))
            mlive(g, "emissive", vec3(0.3 * a, 0.5 * a, 0.9 * a))
        else g:set_position(HIDE) end
    end
    if BALL.em then
        pcall(particles.set_emitter, BALL.em, "position", vec3(BALL.x, BALL.y, 0.15))
        pcall(particles.set_emitter, BALL.em, "spawn_rate", 70.0 * PSCALE)
    end
    local spd = BALL.speed / BALL_SPEED_MAX
    set_point(L.ball, vec3(BALL.x, BALL.y, 1.5), vec3(0.7 + 0.3 * spd, 0.8, 1.0), 45 + 40 * spd, 7)
end

------------------------------------------------------------------ AI
local function predict_y(at_x)
    if BALL.stuck or (at_x - BALL.x) * BALL.vx <= 0 then
        return BALL.y
    end
    local x, y, vx, vy = BALL.x, BALL.y, BALL.vx, BALL.vy
    local guard = 0
    while (at_x - x) * vx > 0 and guard < 80 do
        local step = min((at_x - x) / vx, 0.05)
        x = x + vx * step; y = y + vy * step
        if y > HALF_H - BALL_R then y = (HALF_H - BALL_R) * 2 - y; vy = -vy end
        if y < -HALF_H + BALL_R then y = (-HALF_H + BALL_R) * 2 - y; vy = -vy end
        guard = guard + 1
    end
    return y
end

local function ai_target()
    if BALL.stuck or BALL.vx <= 0 then
        return lerp(PAD.R.y, 0, 0.02)
    end
    local y = predict_y(PADDLE_X)
    local skill = G.ai_skill or 0.82
    local slack = (1 - skill) * (PADDLE_H * 0.25)
    return y + rr(-slack, slack)
end

------------------------------------------------------------------ physics
local function serve_ball(dir)
    BALL.stuck = false
    BALL.x, BALL.y = 0, rr(-2, 2)
    BALL.speed = BALL_SPEED0
    local ang = rr(-0.35, 0.35)
    BALL.vx = dir * BALL.speed * cos(ang)
    BALL.vy = BALL.speed * sin(ang)
    BALL.trail = {}
    sfx("serve")
end

local function reset_serve(to_side)
    BALL.stuck = true
    BALL.x, BALL.y = 0, 0
    BALL.vx, BALL.vy = 0, 0
    BALL.trail = {}
    G.serve_dir = to_side or (rand() < 0.5 and -1 or 1)
    G.serve_t = 0
    G.state = "serve"
end

local function paddle_bounce(side)
    local p = PAD[side]
    local rel = clamp((BALL.y - p.y) / (p.h * 0.5), -1, 1)
    -- max deflection ~50 deg
    local ang = rel * 0.85
    local dir = (side == "L") and 1 or -1
    BALL.speed = min(BALL_SPEED_MAX, BALL.speed + 0.85)
    BALL.vx = dir * BALL.speed * cos(ang)
    BALL.vy = BALL.speed * sin(ang)
    -- add paddle motion influence
    BALL.vy = BALL.vy + p.vy * 0.25
    -- nudge out of paddle
    BALL.x = p.x + dir * (PADDLE_W * 0.5 + BALL_R + 0.02)
    p.glow = 1.0; p.squash = 1.0
    local c = (side == "L") and COL_L or COL_R
    local hi = floor(clamp((rel + 1) * 2.5, 0, 5))
    sfx("hit" .. hi)
    sparks(BALL.x, BALL.y, c, 28, 14)
    spawn_ring(BALL.x, BALL.y, c)
    spawn_shards(BALL.x, BALL.y, c, 4)
    flash(BALL.x, BALL.y, c, 35, 0.25, 6)
    add_shake(0.12)
end

local jev

local function score_point(scorer)
    G.score[scorer] = G.score[scorer] + 1
    local c = (scorer == 1) and COL_L or COL_R
    local gx = (scorer == 1) and HALF_W or -HALF_W
    sparks(gx * 0.9, BALL.y, c, 55, 22)
    spawn_ring(gx * 0.85, BALL.y, c)
    flash(gx * 0.7, BALL.y, c, 60, 0.5, 12)
    add_shake(0.35)
    if scorer == 1 then sfx("score") else sfx("score2") end
    G.banner = { text = (scorer == 1 and "PLAYER 1" or (G.mode == "1p" and "AI" or "PLAYER 2")) .. " SCORES",
                 sub = G.score[1] .. "  -  " .. G.score[2], t = 0, dur = 1.4 }
    if G.attract or G.state == "title" then
        G.score = { 0, 0 }
        reset_serve(scorer == 1 and 1 or -1)
        G.state = "title"
        return
    end
    if G.score[scorer] >= WIN_SCORE and abs(G.score[1] - G.score[2]) >= 2 then
        G.state = "over"
        G.winner = scorer
        local total = G.score[1] + G.score[2]
        if total > G.hiscore and not (jev and jev:assisted()) then
            G.hiscore = total
            pcall(fs.write, "Save/hiscore.txt", tostring(G.hiscore))
        end
        sfx(scorer == 1 and "win" or "lose")
        set_menu_over()
    else
        reset_serve(scorer == 1 and 1 or -1)
    end
end

local function update_ball(dt)
    if BALL.stuck then return end
    BALL.x = BALL.x + BALL.vx * dt
    BALL.y = BALL.y + BALL.vy * dt
    -- top/bottom walls
    if BALL.y > HALF_H - BALL_R then
        BALL.y = HALF_H - BALL_R; BALL.vy = -abs(BALL.vy)
        sfx("wall"); sparks(BALL.x, BALL.y, COL_NET, 18, 10); spawn_ring(BALL.x, BALL.y, COL_NET); add_shake(0.05)
    elseif BALL.y < -HALF_H + BALL_R then
        BALL.y = -HALF_H + BALL_R; BALL.vy = abs(BALL.vy)
        sfx("wall"); sparks(BALL.x, BALL.y, COL_NET, 18, 10); spawn_ring(BALL.x, BALL.y, COL_NET); add_shake(0.05)
    end
    -- paddle collisions (AABB vs circle)
    local function hit_pad(side)
        local p = PAD[side]
        local px = p.x
        local hw = PADDLE_W * 0.5 + BALL_R
        local hh = p.h * 0.5 + BALL_R
        local x0, y0 = BALL.x - BALL.vx * dt, BALL.y - BALL.vy * dt
        local x1, y1 = BALL.x, BALL.y
        local lo, hi = min(x0, x1), max(x0, x1)
        if hi <= px - hw or lo >= px + hw then return false end
        local t = 0
        if abs(x1 - x0) > 1e-8 then t = clamp((px - x0) / (x1 - x0), 0, 1) end
        local y = y0 + (y1 - y0) * t
        if (abs(y - p.y) < hh or abs(y1 - p.y) < hh)
            and ((side == "L" and BALL.vx < 0) or (side == "R" and BALL.vx > 0)) then
            paddle_bounce(side)
            return true
        end
        return false
    end
    hit_pad("L"); hit_pad("R")
    -- goals
    if BALL.x < -HALF_W - 1.0 then score_point(2)
    elseif BALL.x > HALF_W + 1.0 then score_point(1) end
end

local function update_paddle_side(side, dt, control)
    local p = PAD[side]
    local lim = HALF_H - p.h * 0.5
    local speed = 22.0
    if control == "ai" then
        p.target = ai_target()
        -- smooth AI follow with capped speed
        local dy = clamp(p.target - p.y, -speed * dt * 1.1, speed * dt * 1.1)
        p.y = clamp(p.y + dy, -lim, lim)
        p.vy = dy / max(dt, 1e-4)
    elseif control == "keys" then
        local up = (side == "L") and (kdown("W")) or (kdown("Up"))
        local dn = (side == "L") and (kdown("S")) or (kdown("Down"))
        -- P1 can also use arrows in 1P mode
        if side == "L" and G.mode == "1p" then
            up = up or kdown("Up"); dn = dn or kdown("Down")
        end
        local dir = (up and 1 or 0) - (dn and 1 or 0)
        if dir ~= 0 then
            p.vy = clamp(p.vy + dir * dt * 160, -speed, speed)
        else
            p.vy = p.vy * math.exp(-dt * 14)
        end
        -- mouse for P1 in 1P
        if side == "L" and G.mode == "1p" and G.use_mouse then
            local ok, mp = pcall(input.get_mouse_position)
            if ok and mp and mp.y then
                -- screen y -> world y
                local C = cam:get_position()
                local ndc = 1 - (mp.y / SH) * 2
                local depth = abs(C.z)
                local wy = C.y + ndc * depth * math.tan(FOVX * 0.5) * (SH / SW)
                p.target = wy
                p.y = lerp(p.y, clamp(p.target, -lim, lim), 1 - math.exp(-dt * 22))
                p.vy = 0
            end
        else
            p.y = clamp(p.y + p.vy * dt, -lim, lim)
        end
    elseif control == "auto" then
        -- attract-mode: both paddles track
        local tgt = BALL.stuck and 0 or BALL.y + sin(G.t * 3 + (side == "L" and 0 or 1)) * 0.4
        p.y = lerp(p.y, clamp(tgt, -lim, lim), 1 - math.exp(-dt * 8))
        p.vy = 0
    end
    p.glow = max(0, p.glow - dt * 3.5)
    p.squash = max(0, p.squash - dt * 7)
end

-- forward decls filled after input helpers
kdown = function() return false end

------------------------------------------------------------------ HUD / menus
local HUD = "hud"
runtime_ui.show(HUD); runtime_ui.set_screen_overlay(HUD, true)
local NONE = { 0, 0, 0, 0 }
local CYAN, CORAL, WHITE, GOLD = { 0.45, 0.9, 1.0, 1 }, { 1.0, 0.5, 0.35, 1 }, { 1, 1, 1, 1 }, { 1, 0.85, 0.45, 1 }
local cache = {}
local function upd(id, key, q)
    if cache[id] == key then return end
    cache[id] = key
    runtime_ui.set_quad(HUD, id, q)
end
local function text(id, label, x, y, w, h, fs, col, align, vis)
    vis = vis ~= false
    local key = label .. "|" .. floor(x) .. "|" .. floor(y) .. "|" .. tostring(vis) .. "|" .. string.format("%.2f|%.2f", col[4], fs) .. col[1] .. col[2]
    upd(id, key, { x = x, y = y, w = w, h = h, z = 10, style = "text", label = label, fill = NONE, border = NONE,
        text_color = col, font_scale = fs, align_h = align or "center", align_v = "middle", no_input = true, visible = vis })
end
local function panel(id, x, y, w, h, vis, fill, border, z, input)
    vis = vis ~= false
    local key = floor(x) .. "|" .. floor(y) .. "|" .. floor(w) .. "|" .. floor(h) .. "|" .. tostring(vis) .. "|" .. table.concat(fill, ",") .. table.concat(border or NONE, ",")
    upd(id, key, { x = x, y = y, w = w, h = h, z = z or 5, style = "text", label = "", fill = fill, border = border or NONE,
        corner_radius = 14, no_input = not input, visible = vis })
end
local function ui_state(id) local ok, s = pcall(runtime_ui.get_state, HUD, id); if ok then return s end end

local MENU = { items = {}, sel = 1, id = "" }
local function set_menu(id, items) MENU.id, MENU.items, MENU.sel = id, items, 1 end
local function draw_menu(vis, y0)
    local s = SH / 1080
    for i = 1, 5 do
        local it = MENU.items[i]
        local v = vis and it ~= nil
        local sel = v and MENU.sel == i
        local x, w, h = SW / 2 - 240 * s, 480 * s, 68 * s
        local y = y0 + (i - 1) * 82 * s
        panel("mi_bg" .. i, x, y, w, h, v, sel and { 0.12, 0.45, 0.7, 0.4 } or { 0.04, 0.05, 0.1, 0.6 },
            sel and { 0.45, 0.9, 1.0, 0.95 } or { 0.4, 0.5, 0.7, 0.45 }, 20, true)
        text("mi_tx" .. i, v and it.label or "", x, y, w, h, (sel and 1.7 or 1.5) * s, sel and WHITE or { 0.75, 0.82, 0.95, 1 }, "center", v)
    end
end
local function menu_input(pressed)
    if #MENU.items == 0 then return nil end
    for i = 1, #MENU.items do
        local st = ui_state("mi_bg" .. i)
        if st and st.hovered and (G.mouse_moved or false) then MENU.sel = i end
        if st and st.clicked then MENU.sel = i; return MENU.items[i].act end
    end
    if pressed("Up") or pressed("W") then MENU.sel = (MENU.sel - 2) % #MENU.items + 1; sfx("click") end
    if pressed("Down") or pressed("S") then MENU.sel = MENU.sel % #MENU.items + 1; sfx("click") end
    if pressed("Return") or pressed("Space") then return MENU.items[MENU.sel].act end
end

function set_menu_over()
    set_menu("over", {
        { label = "PLAY AGAIN", act = "again" },
        { label = "TITLE", act = "title" },
    })
end

local function draw_hud(dt)
    local s = SH / 1080
    local st = G.state
    local play = (st == "play" or st == "serve" or st == "paused" or st == "over")
    local title = st == "title"
    -- scores
    text("sc1", tostring(G.score[1] or 0), SW * 0.28, SH * 0.06, SW * 0.18, 100 * s, 4.2 * s, CYAN, "center", play)
    text("sc2", tostring(G.score[2] or 0), SW * 0.54, SH * 0.06, SW * 0.18, 100 * s, 4.2 * s, CORAL, "center", play)
    text("sep", " - ", SW * 0.45, SH * 0.08, SW * 0.1, 70 * s, 2.2 * s, { 0.6, 0.7, 0.85, 0.7 }, "center", play)
    local mode_lbl = G.mode == "1p" and "1P  vs  AI" or "LOCAL  2P"
    text("mode", mode_lbl, 0, SH * 0.025, SW, 40 * s, 1.0 * s, { 0.7, 0.8, 0.95, 0.75 }, "center", play)
    -- banner
    local ban = G.banner
    if ban then
        ban.t = ban.t + dt
        local bvis = ban.t < ban.dur and play
        local ba = bvis and min(1, ban.t * 5, (ban.dur - ban.t) * 3) or 0
        text("banner", ban.text or "", 0, SH * 0.42, SW, 90 * s, 2.8 * s, { 1, 0.9, 0.6, ba }, "center", bvis)
        text("banner2", ban.sub or "", 0, SH * 0.42 + 80 * s, SW, 50 * s, 1.4 * s, { 0.7, 0.9, 1, ba }, "center", bvis and (ban.sub or "") ~= "")
        if ban.t >= ban.dur then G.banner = nil end
    else
        text("banner", "", 0, 0, 1, 1, 1, NONE, "center", false)
        text("banner2", "", 0, 0, 1, 1, 1, NONE, "center", false)
    end
    local serve = st == "serve"
    text("hint", "CLICK  /  SPACE  TO SERVE", 0, SH * 0.82, SW, 55 * s, 1.35 * s, { 1, 1, 1, 0.5 + 0.45 * sin(G.t * 4) }, "center", serve)
    -- title
    panel("tpanel", SW * 0.5 - 500 * s, SH * 0.08, 1000 * s, SH * 0.78, title, { 0.02, 0.03, 0.06, 0.72 }, { 0.4, 0.65, 0.9, 0.45 }, 3)
    text("title", "PONG REMIX", 0, SH * 0.14, SW, 160 * s, 5.2 * s, { 0.75 + 0.1 * sin(G.t * 1.5), 0.92, 1.0, 1 }, "center", title)
    text("tsub", "FIRST TO " .. WIN_SCORE .. "  ·  WIN BY 2", 0, SH * 0.30, SW, 50 * s, 1.3 * s, GOLD, "center", title)
    text("ctl", "P1  W/S  or  ARROWS  or  MOUSE      P2  UP/DOWN      P / ESC  PAUSE      M  MUTE",
        0, SH * 0.88, SW, 45 * s, 0.95 * s, { 0.7, 0.82, 0.95, 0.85 }, "center", title)
    -- pause / over
    local pause = st == "paused"
    panel("dim", 0, 0, SW, SH, pause or st == "over", { 0, 0, 0.02, 0.55 }, NONE, 2)
    text("pause", "PAUSED", 0, SH * 0.22, SW, 130 * s, 4.2 * s, CYAN, "center", pause)
    local over = st == "over"
    local wname = (G.winner == 1) and "PLAYER 1 WINS" or ((G.mode == "1p") and "AI WINS" or "PLAYER 2 WINS")
    text("over", wname or "GAME OVER", 0, SH * 0.20, SW, 130 * s, 4.0 * s, (G.winner == 1) and CYAN or CORAL, "center", over)
    text("over2", G.score[1] .. "  -  " .. G.score[2], 0, SH * 0.34, SW, 70 * s, 2.2 * s, GOLD, "center", over)
    draw_menu(title or pause or over, title and SH * 0.40 or SH * 0.48)
end

------------------------------------------------------------------ settings
local SET = nil
do
    local src = fs.read("Scripts/Lib/settings_menu.lua")
    if src then
        local ok, mod = pcall(function() return load(src, "@settings_menu.lua")() end)
        if ok and mod then
            local ok2, s = pcall(mod.new, { title = "SETTINGS", file = "Save/settings.cfg", click = function() sfx("click") end,
                music = false, defaults = { master = 0.5 },
                theme = { accent = { 0.35, 0.85, 1, 1 }, accent2 = { 1.0, 0.5, 0.35, 1 } } })
            if ok2 then SET = s else pe_log("[Pong] settings menu init failed: " .. tostring(s)) end
        else pe_log("[Pong] settings menu load failed: " .. tostring(mod)) end
    end
end

------------------------------------------------------------------ input
local prev = {}
G.vkeys = {}
kdown = function(k) if G.vkeys[k] then return true end local ok, r = pcall(input.is_key_down_raw, k); return ok and r end
local function pressed(k)
    local d = kdown(k); local p = prev[k]; prev[k] = d
    return d and not p
end
local WATCH = { "Left", "Right", "A", "D", "Up", "Down", "W", "S", "Space", "Return", "Escape", "P", "M" }
local function latch() for _, k in ipairs(WATCH) do prev[k] = kdown(k) end end
local mouse_prev_down, mouse_last = false, nil
local function mouse_clicked()
    local ok, d = pcall(input.is_left_mouse_down); d = ok and d
    if G.vkeys.Click then d = true end
    local c = d and not mouse_prev_down; mouse_prev_down = d
    return c
end

------------------------------------------------------------------ flow
local function new_game(mode)
    G.mode = mode or "1p"
    G.attract = false
    G.score = { 0, 0 }
    G.winner = nil
    G.ai_skill = 0.78
    PAD.L.y, PAD.R.y = 0, 0
    PAD.L.target, PAD.R.target = 0, 0
    sfx("start")
    reset_serve(rand() < 0.5 and -1 or 1)
end

local function to_title()
    jev:begin_human()
    G.state = "title"
    set_menu("title", {
        { label = "1P  vs  AI", act = "1p" },
        { label = "Jev", act = "jev" },
        { label = "LOCAL  2P", act = "2p" },
        { label = "SETTINGS", act = "settings" },
        { label = "QUIT", act = "quit" },
    })
    BALL.stuck = true; BALL.x, BALL.y = 0, 0
    G.score = { 0, 0 }
    G.attract = true
end

------------------------------------------------------------------ jev
local jev_keys = false
local pulse_arm = false
local pulse_live = false
local human_prev = {}
local HUMAN_KEYS = { "W", "S", "Up", "Down", "Space" }
local SERVE_STEP = 0.5

local function clear_hold()
    pulse_arm = false
    pulse_live = false
    if not G.vkeys then
        return
    end

    G.vkeys.W = nil
    G.vkeys.S = nil
    G.vkeys.Space = nil
end

local function sample_human_keys()
    for i = 1, #HUMAN_KEYS do
        local key = HUMAN_KEYS[i]
        local ok, down = pcall(input.is_key_down_raw, key)
        human_prev[key] = ok and down and true or false
    end
end

local function human_edge()
    local edge = false
    for i = 1, #HUMAN_KEYS do
        local key = HUMAN_KEYS[i]
        local ok, down = pcall(input.is_key_down_raw, key)
        down = ok and down and true or false
        if down and not human_prev[key] then
            edge = true
        end
        human_prev[key] = down
    end
    return edge
end

local function arm_pulse_frame(dt)
    if not pulse_arm then
        return
    end
    if G.state ~= "serve" or not G.vkeys then
        pulse_arm = false
        return
    end
    if (G.serve_t or 0) + dt <= 0.2 then
        return
    end

    G.vkeys.Space = true
    pulse_arm = false
    pulse_live = true
end

local function settle_input()
    if G.state ~= "play" and G.state ~= "serve" then
        pulse_arm = false
        if G.vkeys then
            G.vkeys.W = nil
            G.vkeys.S = nil
        end
    end
    if pulse_live and G.vkeys then
        G.vkeys.Space = nil
        pulse_live = false
    end
end

local function toward_score(gap, dir)
    return -abs(gap - dir * SERVE_STEP)
end

local jev_source = assert(fs.read("Scripts/jev_auto.lua"), "Missing Scripts/jev_auto.lua")
local JevAuto = assert(load(jev_source, "@Scripts/jev_auto.lua", "t", _ENV))()
jev = JevAuto.attach({
    port = 9129,
    id = "pong_remix",
    description = "Pong Remix. The offered action moves the left paddle onto the ball, or serves when the ball is stuck. The right paddle is the AI. First to 11, win by 2.",
    playing = function()
        return G.state == "play" or G.state == "serve"
    end,
    terminal = function()
        return G.state == "over"
    end,
    score = function()
        return G.score[1] or 0
    end,
    busy = function()
        return false
    end,
    human_edge = human_edge,
    observe = function()
        return {
            paddle_y = PAD.L.y,
            ball_x = BALL.x,
            ball_y = BALL.y,
            ball_vx = BALL.vx,
            ball_vy = BALL.vy,
            score_left = G.score[1] or 0,
            score_right = G.score[2] or 0,
        }
    end,
    actions = function()
        local gap = predict_y(-PADDLE_X) - PAD.L.y
        if BALL.stuck and abs(gap) <= SERVE_STEP then
            return { { id = "serve", description = "Serve the ball.", score = 1 } }
        end
        if gap > 0.15 then
            return { { id = "up", description = "Move the paddle up toward the ball.", score = gap } }
        end
        if gap < -0.15 then
            return { { id = "down", description = "Move the paddle down toward the ball.", score = -gap } }
        end
        if BALL.stuck then
            return { { id = "serve", description = "Serve the ball.", score = 1 } }
        end
        return { { id = "stop", description = "The paddle is on the ball.", score = 1 } }
    end,
    apply = function(id)
        if id == "serve" then
            if BALL.stuck then
                G.vkeys.W = nil
                G.vkeys.S = nil
                if pulse_live then
                    G.vkeys.Space = nil
                    pulse_live = false
                end
                pulse_arm = true
            end
            return
        end

        pulse_arm = false
        if pulse_live then
            G.vkeys.Space = nil
            pulse_live = false
        end
        if id == "up" then
            G.vkeys.W = true
            G.vkeys.S = nil
        elseif id == "down" then
            G.vkeys.W = nil
            G.vkeys.S = true
        elseif id == "stop" then
            G.vkeys.W = nil
            G.vkeys.S = nil
        end
    end,
    reset = function(seed)
        jev_keys = true
        clear_hold()
        math.randomseed(seed)
        rand()
        new_game("1p")
        sample_human_keys()
    end,
    on_human = function()
        jev_keys = false
        clear_hold()
    end,
})

local function do_menu_action(act)
    sfx("click")
    if act == "1p" then
        jev:begin_human()
        runtime_ui.show(HUD)
        new_game("1p")
    elseif act == "2p" then
        jev:begin_human()
        runtime_ui.show(HUD)
        new_game("2p")
    elseif act == "again" then
        jev:begin_human()
        new_game(G.mode)
    elseif act == "resume" then
        G.state = G.paused_from or "play"
    elseif act == "settings" then
        if SET then
            G.in_settings = true
            SET:open(function() G.in_settings = false end)
        end
    elseif act == "title" then
        to_title()
    elseif act == "quit" then
        pcall(engine.quit)
    elseif act == "jev" then
        runtime_ui.show(HUD)
        local started = jev:start()
        if not started then
            local err = jev:error()
            jev:begin_human()
            if not err or err == "" then
                err = "Jev failed to start"
            end
            pe_log("[Pong] " .. err)
            G.banner = { text = err, sub = "", t = 0, dur = 4 }
        end
    end
end

local function update_visuals(dt)
    update_flashes(dt); update_rings(dt); update_shards(dt)
    G.rail_hit = max(0, (G.rail_hit or 0) - dt * 3)
    local h = G.t * 0.2
    local r, g, b = 0.45 + 0.25 * sin(h), 0.55 + 0.25 * sin(h + 2), 0.75 + 0.2 * sin(h + 4)
    mlive(G.rail_glow, "emissive", vec3(r * 1.6, g * 1.8, b * 2.0))
    -- goal post tint
    mlive(G.goal_L, "emissive", vec3(COL_L[1] * 0.8, COL_L[2] * 0.8, COL_L[3] * 1.1))
    mlive(G.goal_R, "emissive", vec3(COL_R[1] * 1.1, COL_R[2] * 0.7, COL_R[3] * 0.6))
    set_point(L.key_l, vec3(-10 + sin(G.t * 0.4) * 3, 8 + cos(G.t * 0.35) * 2, 14), vec3(0.3, 0.75, 1.0), 75, 55)
    set_point(L.key_r, vec3(10 + cos(G.t * 0.38) * 3, 8 + sin(G.t * 0.32) * 2, 14), vec3(1.0, 0.4, 0.3), 75, 55)
    set_point(L.pad_l, vec3(PAD.L.x, PAD.L.y, 3), vec3(COL_L[1], COL_L[2], COL_L[3]), 18 + 25 * PAD.L.glow, 9)
    set_point(L.pad_r, vec3(PAD.R.x, PAD.R.y, 3), vec3(COL_R[1], COL_R[2], COL_R[3]), 18 + 25 * PAD.R.glow, 9)
    shake = max(0, shake - dt * 2.2)
    local sk = shake * shake * SHAKE_SCALE
    local ox = (sin(G.t * 47) + sin(G.t * 31.7) * 0.5) * 0.4 * sk
    local oy = (cos(G.t * 41) + sin(G.t * 23.3) * 0.5) * 0.4 * sk
    if shake < 0.02 then ox, oy = 0, 0 end
    local follow = (BALL.stuck and 0 or BALL.x) * 0.04
    G.cam_px = lerp(G.cam_px or 0, follow, 1 - math.exp(-dt * 3))
    cam:set_position(vec3(CAM_BASE.x + G.cam_px + ox, CAM_BASE.y + oy, CAM_BASE.z))
    cam:look_at(vec3(CAM_LOOK.x + G.cam_px * 0.4, CAM_LOOK.y + oy * 0.3, CAM_LOOK.z))
end

local function play_tick(dt, attract)
    if attract then
        update_paddle_side("L", dt, "auto")
        update_paddle_side("R", dt, "auto")
        if BALL.stuck then
            G.serve_t = (G.serve_t or 0) + dt
            if G.serve_t > 1.0 then serve_ball(G.serve_dir or 1); G.state = "title" end
        else
            update_ball(dt)
            if G.state ~= "title" and G.state ~= "serve" then
                -- score_point may change state during attract; keep title
                if G.state == "over" or G.state == "serve" then
                    G.score = { 0, 0 }; G.state = "title"; reset_serve(); G.state = "title"
                end
            end
        end
    else
        update_paddle_side("L", dt, "keys")
        if G.mode == "1p" then update_paddle_side("R", dt, "ai")
        else update_paddle_side("R", dt, "keys") end
        if G.state == "serve" then
            G.serve_t = (G.serve_t or 0) + dt
            -- hold ball near serving side briefly visually at centre
            BALL.x, BALL.y = 0, 0
            if (G.click or pressed("Space")) and G.serve_t > 0.2 then
                serve_ball(G.serve_dir or 1); G.state = "play"
            end
        elseif G.state == "play" then
            update_ball(dt)
        end
    end
    draw_paddle("L"); draw_paddle("R"); draw_ball(dt)
end

local function update(dt)
    dt = min(dt, 1 / 20)
    arm_pulse_frame(dt)
    jev:tick(dt)
    G.t = G.t + dt
    local okS, sz = pcall(runtime_ui.get_surface_size)
    if okS and sz and (sz.width or 0) > 0 and (sz.width ~= SW or sz.height ~= SH) then SW, SH = sz.width, sz.height; cache = {} end
    flush_mats()
    if G.state == "boot" then
        G.boot = (G.boot or 0) + 1
        if G.boot == 3 then
            paint_templates()
            if SET then pcall(SET.apply, SET) end
            to_title()
            pe_log("[Pong] ready")
        end
        settle_input()
        return
    end
    if SET then
        PSCALE = SET:particle_scale() or 1; SHAKE_SCALE = SET:shake_scale() or 1
        if SET:update(dt) then
            settle_input()
            latch()
            mouse_clicked()
            update_visuals(dt)
            draw_hud(dt)
            return
        end
    end
    local ok, mp = pcall(input.get_mouse_position)
    G.mouse_moved = ok and mp and G._mx and (abs(mp.x - G._mx) + abs(mp.y - G._my) > 1) or false
    if ok and mp then
        if mouse_last and (abs(mp.x - mouse_last.x) + abs(mp.y - mouse_last.y)) > 0.5 then G.use_mouse = true end
        mouse_last = { x = mp.x, y = mp.y }
        G._mx, G._my = mp.x, mp.y
    end
    if kdown("W") or kdown("S") or kdown("Up") or kdown("Down") then G.use_mouse = false end
    if jev_keys then
        G.use_mouse = false
    end
    G.click = mouse_clicked()
    if pressed("M") then if SET then SET:toggle_mute() end end
    local st = G.state
    if st == "title" then
        local act = menu_input(pressed)
        if act then do_menu_action(act) end
        if G.state == "title" then play_tick(dt, true) end
    elseif st == "serve" or st == "play" then
        if pressed("Escape") or pressed("P") then
            G.paused_from = st; G.state = "paused"; sfx("click")
            set_menu("pause", { { label = "RESUME", act = "resume" }, { label = "SETTINGS", act = "settings" }, { label = "QUIT TO TITLE", act = "title" } })
        else play_tick(dt, false) end
    elseif st == "paused" then
        if pressed("Escape") or pressed("P") then G.state = G.paused_from or "play"
        else local act = menu_input(pressed); if act then do_menu_action(act) end end
        draw_paddle("L"); draw_paddle("R"); draw_ball(0)
    elseif st == "over" then
        local act = menu_input(pressed)
        if act then do_menu_action(act) end
        draw_paddle("L"); draw_paddle("R"); draw_ball(0)
    end
    update_visuals(dt)
    draw_hud(dt)
    settle_input()
    latch()
end

local function init()
    paint_templates()
    build_world(); build_lights(); build_rings(); build_shards(); build_paddles(); build_ball()
    local hs = fs.read("Save/hiscore.txt")
    G.hiscore = tonumber(hs) or 0
    pcall(audio.set_master_volume, 0.5)
    G.state = "boot"
end
init()
hooks { update = update }

-- MCP automation
function G.sim(sec, keys)
    G.vkeys = keys or {}
    for _ = 1, floor(sec * 60) do update(1 / 60) end
    G.vkeys = {}
    return G.state .. " score=" .. G.score[1] .. "-" .. G.score[2] .. " mode=" .. tostring(G.mode)
end
G.SET = SET; G.new_game = new_game; G.to_title = to_title; G.serve_ball = serve_ball
G.set_menu = set_menu; G.do_menu_action = do_menu_action
