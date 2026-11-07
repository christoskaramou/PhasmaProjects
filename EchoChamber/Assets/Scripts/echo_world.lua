-- Echo Chamber 3D world: a glossy tiled chamber with acoustic pillars, a horn, hanging bells and the
-- player's pieces, built from cooked meshes (tools/gen_meshes.py) and primitives. Plays a send back as
-- a glowing pulse with wave fronts, a trail that stays as a faint echo, ringing bells and ripples.
-- Board cell (x, y) -> world (x - (w+1)/2, *, y - (h+1)/2). Y is up; the camera looks down from +Z.
return function(R)
local W = {}
local floor, min, max, abs, sin, cos, sqrt = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt
local function v3(x, y, z) return vec3(x, y, z) end

local BEAM_Y = 0.4          -- the pulse travels at this height, under the bells and across the mirrors
local LIP = 0.5             -- bell lip height
local BELL_S = 0.72         -- bell size (the cooked bell mesh is scaled down to this)
local YOKE_W, YOKE_V = 0.85, 0.84   -- yoke width / height scale so the frame fits the smaller bell
local PIVOT = 1.5 * YOKE_V  -- bells swing from the yoke's crossbar
local TICK = 0.1            -- seconds per cell at speed 1
local N_LIGHTS = 26
local CYAN = { 0.4, 0.88, 1 }
local GOLD = { 1, 0.62, 0.18 }
local RED = { 1, 0.16, 0.12 }
local VIOLET = { 0.55, 0.3, 1 }
W.CYAN, W.GOLD, W.RED = CYAN, GOLD, RED
W.BEAM_Y = BEAM_Y

local cam
local S = { t = 0, shake = 0, flash = 0, flash_c = { 1, 1, 1 }, flash_x = 0, flash_z = 0, flip = nil }
local GW, GH = 8, 6
local board, pieces, bells = {}, {}, {}
local ghost = { key = nil, nodes = {} }
local hint = { key = nil, nodes = {} }
local cursor = {}
local LT, LT_used = {}, 0
-- The engine copies each light's position from its scene node every frame, so set_point_light's position alone is
-- overwritten and every lamp stays at the origin. Move the node too (looked up once per lamp), as 1942Remix does.
local LNODE = {}
local function point_light(i, pos, col, inten, rad)
    pcall(lights.set_point_light, i, pos, col, inten, rad)
    local n = LNODE[i]
    if n == nil then
        local l = lights.get_point_lights()[i + 1]
        n = (l and scene.find_model and scene.find_model(l.name)) or false
        LNODE[i] = n
    end
    if n then n:set_position(pos) end
end
local function light_off(i) point_light(i, v3(0, -50, 0), v3(0, 0, 0), 0, 0.1) end
local horn = {}
local scale_particles = function() return 1 end
local scale_shake = function() return 1 end

local function wx(x) return x - (GW + 1) / 2 end
local function wz(y) return y - (GH + 1) / 2 end
function W.cell_world(x, y) return wx(x), wz(y) end

------------------------------------------------------------------ materials (clones replay writes: engine quirk)
local mat_q = {}
local function mset(n, k, v)
    pcall(material.set, n, k, v)
    mat_q[#mat_q + 1] = { n = n, k = k, v = v, c = 0 }
end
local function flush_mats()
    for i = #mat_q, 1, -1 do
        local q = mat_q[i]
        q.c = q.c + 1
        if q.c == 2 or q.c == 6 then pcall(material.set, q.n, q.k, q.v) end
        if q.c >= 6 then table.remove(mat_q, i) end
    end
end
local function mat(n, base, emis, metal, rough)
    mset(n, "base_color", vec4(base[1], base[2], base[3], base[4] or 1))
    mset(n, "emissive", v3(emis and emis[1] or 0, emis and emis[2] or 0, emis and emis[3] or 0))
    mset(n, "metallic", metal or 0.5)
    mset(n, "roughness", rough or 0.4)
end
local function glow(n, c, e)
    mat(n, { c[1] * 0.2, c[2] * 0.2, c[3] * 0.2 }, { c[1] * e, c[2] * e, c[3] * e }, 0.1, 0.4)
end
local function emis(n, c, e) pcall(material.set, n, "emissive", v3(c[1] * e, c[2] * e, c[3] * e)) end

-- Material presets.
local M = {
    tile = function(n) mat(n, { 0.06, 0.06, 0.1 }, nil, 0.5, 0.14) end,
    slab = function(n) mat(n, { 0.03, 0.028, 0.05 }, nil, 0.6, 0.35) end,
    rail = function(n) mat(n, { 0.05, 0.05, 0.08 }, nil, 0.9, 0.25) end,
    wall = function(n) mat(n, { 0.07, 0.06, 0.13 }, nil, 0.15, 0.42) end,
    mirror = function(n) mat(n, { 0.88, 0.94, 1 }, { 0.02, 0.05, 0.07 }, 1, 0.03) end,
    steel = function(n) mat(n, { 0.6, 0.63, 0.7 }, nil, 1, 0.22) end,
    yoke = function(n) mat(n, { 0.07, 0.06, 0.08 }, nil, 0.8, 0.3) end,
    chrome = function(n) mat(n, { 0.88, 0.9, 0.96 }, nil, 1, 0.1) end,
    cabinet = function(n) mat(n, { 0.035, 0.04, 0.07 }, nil, 0.4, 0.28) end,
    bronze = function(n) mat(n, { 0.2, 0.12, 0.07 }, nil, 0.75, 0.55) end,
    gold = function(n, e) mat(n, { 1, 0.6, 0.16 }, { GOLD[1] * e, GOLD[2] * e, GOLD[3] * e }, 1, 0.2) end,
    felt = function(n) mat(n, { 0.16, 0.05, 0.1 }, nil, 0, 0.9) end,
    brass = function(n) mat(n, { 0.85, 0.6, 0.25 }, { 0.12, 0.07, 0.01 }, 1, 0.25) end,
}

------------------------------------------------------------------ nodes
local TPL = {}
local seq = 0
local function clone(name, list, parent, x, y, z)
    local t = TPL[name]
    if not t then
        local n = scene.find_model and scene.find_model("T_" .. name)
        if n then t = { mesh = n:get_mesh_refs()[1] } else t = {} end
        TPL[name] = t
    end
    seq = seq + 1
    local n = scene.add_empty_node(name .. "_" .. seq)
    if t.mesh then n:add_mesh_ref(t.mesh) end
    if parent then n:set_parent(parent) end
    n:set_position(v3(x or 0, y or 0, z or 0))
    if list then list[#list + 1] = n end
    return n
end
local function empty(list, parent, x, y, z)
    seq = seq + 1
    local n = scene.add_empty_node("echo_e" .. seq)
    if parent then n:set_parent(parent) end
    n:set_position(v3(x or 0, y or 0, z or 0))
    if list then list[#list + 1] = n end
    return n
end
local function prim(n, list, parent, x, y, z, sx, sy, sz)
    if parent then n:set_parent(parent) end
    n:set_position(v3(x, y, z))
    if sx then n:set_scale(v3(sx, sy, sz)) end
    if list then list[#list + 1] = n end
    return n
end
local function box(list, parent, x, y, z, sx, sy, sz) return prim(primitives.cube(1), list, parent, x, y, z, sx, sy, sz) end
local function ring(list, parent, x, y, z, R0, r0, rx, rz)
    local n = prim(primitives.torus(R0, r0, 72, 10), list, parent, x, y, z)
    if rx or rz then n:set_rotation(v3(rx or 0, 0, rz or 0)) end
    return n
end
local function remove_all(list)
    for i = #list, 1, -1 do pcall(function() list[i]:remove() end); list[i] = nil end
end

------------------------------------------------------------------ tweens
local function ease_out(t) return 1 - (1 - t) ^ 3 end
local function ease_in(t) return t * t * t end
local function ease_inout(t) return t < 0.5 and 4 * t * t * t or 1 - (-2 * t + 2) ^ 3 / 2 end
local function ease_back(t) local c = 1.6; return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2 end
local function ease_bounce(t)
    local n, d = 7.5625, 2.75
    if t < 1 / d then return n * t * t
    elseif t < 2 / d then t = t - 1.5 / d; return n * t * t + 0.75
    elseif t < 2.5 / d then t = t - 2.25 / d; return n * t * t + 0.9375 end
    t = t - 2.625 / d; return n * t * t + 0.984375
end
W.ease = { out = ease_out, inn = ease_in, inout = ease_inout, back = ease_back, bounce = ease_bounce }
local anims = {}
local SETTER = { pos = "set_position", scale = "set_scale", rot = "set_rotation" }
local function apply(a, f)
    local e = a.e(f)
    local v = v3(a.a[1] + (a.b[1] - a.a[1]) * e, a.a[2] + (a.b[2] - a.a[2]) * e, a.a[3] + (a.b[3] - a.a[3]) * e)
    pcall(a.n[SETTER[a.p]], a.n, v)
end
-- Tween a node's position / scale / rotation (degrees) from -> to after `delay` seconds.
local function anim(n, prop, from, to, dur, delay, ease, done)
    local a = { n = n, p = prop, a = from, b = to, d = max(1e-3, dur), t = -(delay or 0), e = ease or ease_out, done = done }
    apply(a, 0)
    anims[#anims + 1] = a
    return a
end
W.anim = anim
local function update_anims(dt)
    for i = #anims, 1, -1 do
        local a = anims[i]
        a.t = a.t + dt
        if a.t >= 0 then
            local f = min(1, a.t / a.d)
            apply(a, f)
            if f >= 1 then
                table.remove(anims, i)
                if a.done then a.done() end
            end
        end
    end
end
local function cancel_anims(n)
    for i = #anims, 1, -1 do if anims[i].n == n then table.remove(anims, i) end end
end

------------------------------------------------------------------ init
function W.init(opts)
    scale_particles = opts and opts.particle_scale or scale_particles
    scale_shake = opts and opts.shake_scale or scale_shake
    cam = scene.get_active_camera()
    pcall(function() cam:set_projection_mode("perspective") end)
    -- Post-processing (TAA, bloom, tonemapping) only runs with a Scene Settings node.
    if not W.settings_node then
        W.settings_node = scene.add_empty_node("Scene Settings")
        pcall(function() W.settings_node:set_scene_settings(true) end)
    end
    -- Raster: the engine's hybrid default refits a ray-tracing TLAS every frame, which can fault the GPU.
    pcall(settings.set_render_mode, "raster")
    settings.set("bloom", true)
    settings.set("bloom_strength", 1.0)
    settings.set("bloom_range", 1.0)
    settings.set("render_scale", 1.0)
    settings.set("taa", true)
    settings.set("cas_sharpening", false)
    settings.set("motion_blur", false)
    settings.set("tonemapping", true)
    settings.set("fxaa", false)
    settings.set("ssao", true)
    settings.set("ssr", true)
    settings.set("IBL_intensity", 0.9)
    settings.set("shadows", false)
    settings.set("color_grading", false)
    pcall(function() lights.set_directional_light(0, v3(-6, 30, 16), v3(0.7, 0.68, 1.0), 3.6) end)
    pcall(function()
        local base = #lights.get_point_lights()
        for _ = 1, N_LIGHTS do lights.add_point() end
        for i = 0, N_LIGHTS - 1 do LT[i + 1] = base + i end
        -- New lamps default to intensity 1, radius 10 at the origin. Slots 17-26 are never set below, and the horn,
        -- pulse and bell lamps only once in use; keep them all dark until then.
        for i = 1, N_LIGHTS do light_off(LT[i]) end
    end)
    -- Void around the chamber: a dark floor far below, faint nebula glows and drifting dust.
    local back = primitives.plane(240, 180)
    back:set_position(v3(0, -10, -12))
    mat(back, { 0, 0, 0.01 }, { 0.002, 0.002, 0.01 }, 0, 1)
    for _, nb in ipairs({ { -26, -9, -26, 15, { 0.35, 0.08, 0.6 } }, { 30, -9, -10, 16, { 0.05, 0.2, 0.5 } }, { 2, -9.5, -40, 14, { 0.3, 0.06, 0.4 } } }) do
        local s = primitives.sphere(nb[4]); s:set_position(v3(nb[1], nb[2], nb[3]))
        mat(s, { 0, 0, 0 }, { nb[5][1] * 0.12, nb[5][2] * 0.12, nb[5][3] * 0.12 }, 0, 1)
    end
    W.dust = particles.add_emitter({ name = "echo_dust", position = v3(0, 0.8, 0), velocity = v3(0, 0.1, 0),
        color_start = vec4(0.35, 0.45, 0.9, 0.35), color_end = vec4(0.4, 0.25, 0.8, 0), gravity = v3(0, 0, 0),
        count = floor(160 * scale_particles()), size_min = 0.005, size_max = 0.014, life_min = 5, life_max = 9,
        spawn_rate = 16 * scale_particles(), spawn_radius = 8, noise_strength = 0.25, drag = 0 })
    for i = 1, 4 do
        cursor[i] = primitives.cube(1)
        glow(cursor[i], { 1, 1, 1 }, 2)
        cursor[i]:set_enabled(false)
    end
end

function W.refresh_particles()
    local k = scale_particles()
    if W.dust then pcall(particles.set_emitter, W.dust, { count = floor(160 * k), spawn_rate = 16 * k }) end
end

------------------------------------------------------------------ board
local function yaw_of(dx, dy) return math.deg(math.atan2(-dy, dx)) end

local function build_bell(b, delay)
    local X, Z = wx(b.x), wz(b.y)
    local set = { n = b.n, x = b.x, y = b.y, X = X, Z = Z, list = {}, state = "idle", swing = 0, ring_t = 9, ph = b.n * 1.7 }
    set.pivot = empty(set.list, nil, X, PIVOT, Z)
    set.bell = clone("bell_" .. min(8, b.n), set.list, set.pivot, 0, LIP - PIVOT, 0)
    set.bell:set_scale(v3(BELL_S, BELL_S, BELL_S))
    M.bronze(set.bell)
    set.yoke = clone("yoke", set.list, nil, X, 0, Z)
    set.yoke:set_scale(v3(YOKE_W, YOKE_V, YOKE_W))
    M.yoke(set.yoke)
    set.next_ring = ring(set.list, nil, X, 0.014, Z, 0.4, 0.013)
    glow(set.next_ring, CYAN, 0)
    set.next_ring:set_enabled(false)
    set.ripples = {}
    for i, r0 in ipairs({ 0.45, 0.78, 1.15 }) do
        local rp = ring(set.list, nil, X, 0.012, Z, r0, 0.016 - i * 0.003)
        glow(rp, GOLD, 0)
        rp:set_enabled(false)
        set.ripples[i] = rp
    end
    -- Build-in: the yoke rises, then the bell drops onto its hanger and swings.
    if delay then
        anim(set.yoke, "scale", { YOKE_W, 0.01, YOKE_W }, { YOKE_W, YOKE_V, YOKE_W }, 0.45, delay, ease_back)
        set.dropping = true
        anim(set.pivot, "pos", { X, PIVOT + 3.5, Z }, { X, PIVOT, Z }, 0.55, delay + 0.25, ease_in, function()
            set.dropping = false
            set.swing, set.ring_t = 0.55, 0
            W.burst(X, Z, { 1, 0.7, 0.3 }, 10, 2, PIVOT)
        end)
    end
    return set
end

local walls = {}           -- cell index -> { root, band, X, Z, flash }
local rails = {}           -- glowing frame strips
W.build_t = 9
function W.build(game, quiet)
    for i = #anims, 1, -1 do anims[i] = nil end
    remove_all(board)
    for _, set in pairs(bells) do remove_all(set.list) end
    bells, walls, rails = {}, {}, {}
    W.clear_pieces()
    W.clear_trail()
    GW, GH = game.w, game.h
    local B = board
    local e = game.emitter
    local d0 = quiet and nil or 0       -- build-in delays (nil: appear in place)
    local function dist(x, y) return sqrt((x - e.x) ^ 2 + (y - e.y) ^ 2) end
    -- Slab, glowing seams under the tiles, tiles rising out of the slab in a wave from the horn.
    M.slab(box(B, nil, 0, -0.38, 0, GW + 1.5, 0.6, GH + 1.5))
    W.seams = box(B, nil, 0, -0.055, 0, GW, 0.02, GH)
    glow(W.seams, VIOLET, 0.22)
    for y = 1, GH do
        for x = 1, GW do
            local t = clone("tile", B, nil, wx(x), 0, wz(y))
            M.tile(t)
            if d0 then anim(t, "pos", { wx(x), -1.2, wz(y) }, { wx(x), 0, wz(y) }, 0.5, d0 + dist(x, y) * 0.045 + ((x * 7 + y * 3) % 5) * 0.012, ease_back) end
        end
    end
    -- Raised metal frame with a glowing inner strip.
    local hw, hh = GW / 2, GH / 2
    for _, r in ipairs({ { 0, hh + 0.4, GW + 1.1, 0.36 }, { 0, -hh - 0.4, GW + 1.1, 0.36 }, { hw + 0.4, 0, 0.36, GH + 0.44 }, { -hw - 0.4, 0, 0.36, GH + 0.44 } }) do
        M.rail(box(B, nil, r[1], 0.05, r[2], r[3], 0.24, r[4]))
    end
    for _, r in ipairs({ { 0, hh + 0.23, GW + 0.32, 0.035 }, { 0, -hh - 0.23, GW + 0.32, 0.035 }, { hw + 0.23, 0, 0.035, GH + 0.32 }, { -hw - 0.23, 0, 0.035, GH + 0.32 } }) do
        local n = box(B, nil, r[1], 0.16, r[2], r[3], 0.035, r[4])
        glow(n, { 0.25, 0.55, 1 }, 2.6)
        rails[#rails + 1] = n
    end
    -- Acoustic pillars grow out of the floor.
    for i in pairs(game.walls) do
        local x, y = (i - 1) % GW + 1, floor((i - 1) / GW) + 1
        local root = empty(B, nil, wx(x), 0, wz(y))
        M.wall(clone("wall", B, root))
        local band = box(B, root, 0, 0.58, 0, 0.875, 0.035, 0.875)
        glow(band, VIOLET, 1.1)
        walls[i] = { root = root, band = band, X = wx(x), Z = wz(y), flash = 0, shud = 0 }
        if d0 then anim(root, "scale", { 1, 0.02, 1 }, { 1, 1, 1 }, 0.55, d0 + 0.3 + dist(x, y) * 0.04, ease_back) end
    end
    -- The horn: cabinet, flared horn, glowing membrane and rim, turned to face into the board.
    horn = { x = e.x, y = e.y, kick = 0, dx = e.dx, dy = e.dy }
    local root = empty(B, nil, wx(e.x), 0, wz(e.y))
    horn.root, horn.yaw = root, yaw_of(e.dx, e.dy)
    root:set_rotation(v3(0, horn.yaw, 0))
    M.cabinet(clone("cabinet", B, root))
    M.chrome(clone("horn", B, root))
    horn.membrane = prim(primitives.cylinder(0.075, 0.02), B, root, 0.0, BEAM_Y, 0)
    horn.membrane:set_rotation(v3(0, 0, 90))
    glow(horn.membrane, CYAN, 5)
    horn.lip = ring(B, root, 0.538, BEAM_Y, 0, 0.385, 0.012, 0, 90)
    glow(horn.lip, CYAN, 3)
    glow(box(B, root, -0.2, 0.62, 0, 0.43, 0.03, 0.63), CYAN, 2.2)
    horn.X, horn.Z = wx(e.x), wz(e.y)
    horn.mx, horn.mz = horn.X + e.dx * 0.55, horn.Z + e.dy * 0.55
    if d0 then
        anim(root, "scale", { 0.01, 0.01, 0.01 }, { 1, 1, 1 }, 0.6, d0 + 0.1, ease_back)
        anim(root, "rot", { 0, horn.yaw - 160, 0 }, { 0, horn.yaw, 0 }, 0.8, d0 + 0.1, ease_out)
    end
    -- Bells.
    for k, b in ipairs(game.bells) do bells[b.n] = build_bell(b, d0 and (d0 + 0.55 + k * 0.11)) end
    W.frame_camera()
    W.build_t = quiet and 9 or 0
    S.cam_t = quiet and 9 or 0
end

-- Pulse fired: the horn kicks back, its membrane flares and a wave front leaves the mouth.
function W.fire()
    horn.kick = 1
    local d = horn.dx and v3(horn.dx, 0, horn.dy)
    if not d then return end
    local r = primitives.torus(0.4, 0.02, 64, 8)
    r:set_position(v3(horn.mx, BEAM_Y, horn.mz))
    r:set_rotation(horn.dx ~= 0 and v3(0, 0, 90) or v3(90, 0, 0))
    glow(r, CYAN, 4)
    anim(r, "scale", { 0.5, 0.5, 0.5 }, { 2.4, 2.4, 2.4 }, 0.5, 0, ease_out, function() pcall(function() r:remove() end) end)
    anim(r, "pos", { horn.mx, BEAM_Y, horn.mz }, { horn.mx + horn.dx * 0.9, BEAM_Y, horn.mz + horn.dy * 0.9 }, 0.5, 0, ease_out)
    W.burst(horn.mx, horn.mz, CYAN, 30, 3)
    W.flash(horn.mx, horn.mz, CYAN, 1.2)
end

-- All bells ring again in a wave: the chamber resonates.
function W.celebrate()
    local k = 0
    for n = 1, 8 do
        local set = bells[n]
        if set then
            k = k + 1
            set.celebrate = -0.12 * k
        end
    end
    for _, w in pairs(walls) do w.flash = 1.5 end
    S.zoom_t = 0
end

-- Bell state: "idle" (bronze), "next" (cyan ring on the floor), "rung" (gold glow, ripples), "wrong" (red).
function W.set_bell(n, state)
    local set = bells[n]
    if not set or set.state == state then return end
    set.state = state
    if state == "rung" then
        set.ring_t, set.swing = 0, 1
        M.gold(set.bell, 0.25)
    elseif state == "wrong" then
        set.ring_t, set.swing = 0, 0.6
        mat(set.bell, { 0.5, 0.12, 0.08 }, { RED[1] * 1.2, RED[2] * 1.2, RED[3] * 1.2 }, 1, 0.3)
    else
        M.bronze(set.bell)
    end
    for _, rp in ipairs(set.ripples) do rp:set_enabled(state == "rung") end
    set.next_ring:set_enabled(state == "next")
end
function W.reset_bells(next_n)
    for n in pairs(bells) do W.set_bell(n, n == next_n and "next" or "idle") end
end
function W.bell_anchor(n)
    local set = bells[n]
    if not set then return nil end
    return set.X, PIVOT + 0.3, set.Z, set.state
end

------------------------------------------------------------------ pieces
local function build_piece(p, X, Z, list, alpha, variant)
    local root = empty(list, nil, X, 0, Z)
    local set = { root = root, kind = p.kind, parts = {} }
    local sfx = variant and ("_" .. variant) or ""
    local function part(n, preset, arg)
        if alpha then
            pcall(material.set_render_type, n, "alpha_blend")
            -- Raster draws faint see-through surfaces much fainter than hybrid ray tracing did (these alphas were
            -- tuned there), so lift them: matched to the hybrid look by measurement (2026-11-07).
            local al = 0.2 + 1.2 * alpha
            if variant == "hint" then mat(n, { 1, 0.75, 0.3, al }, { 0.8, 0.5, 0.1 }, 0.2, 0.4)
            else mat(n, { 0.5, 0.85, 1, al }, { 0.2, 0.5, 0.7 }, 0.2, 0.4) end
        elseif preset then preset(n, arg) end
        set.parts[#set.parts + 1] = n
        return n
    end
    local function lit(n, c, e)
        if alpha then return part(n) end
        glow(n, c, e)
        set.parts[#set.parts + 1] = n
        return n
    end
    if p.kind == "reflector" then
        set.yaw = p.flip == "/" and 45 or -45
        root:set_rotation(v3(0, set.yaw, 0))
        part(clone("reflector_frame" .. sfx, list, root), M.steel)
        part(clone("mirror" .. sfx, list, root), M.mirror)
        set.accent = lit(box(list, root, 0, 0.732, 0, 0.94, 0.014, 0.096), CYAN, 3)
        lit(ring(list, root, 0, 0.073, 0, 0.27, 0.01), CYAN, 2.4)
    elseif p.kind == "fork" then
        set.spin = empty(list, root, 0, 0, 0)
        part(clone("fork" .. sfx, list, set.spin), M.steel)
        set.accent = lit(ring(list, root, 0, 0.063, 0, 0.23, 0.012), CYAN, 3)
        lit(prim(primitives.sphere(0.05), list, set.spin, 0, 0.36, 0), CYAN, 4)
    elseif p.kind == "resonator" then
        part(clone("resonator" .. sfx, list, root), M.brass)
        set.orb = lit(prim(primitives.sphere(0.085), list, root, 0, 0.52, 0), GOLD, 4)
        set.r1 = lit(ring(list, root, 0, 0.52, 0, 0.2, 0.012), GOLD, 3)
        set.r2 = lit(ring(list, root, 0, 0.52, 0, 0.27, 0.01), GOLD, 2)
        lit(ring(list, root, 0, 0.062, 0, 0.27, 0.01), GOLD, 2)
    elseif p.kind == "damper" then
        part(clone("damper" .. sfx, list, root), M.felt)
        set.accent = lit(box(list, root, 0, 0.07, 0, 0.735, 0.03, 0.735), RED, 2.4)
    end
    return set
end

local function sig(p) return p.kind .. (p.flip or "") end
local dying = {}           -- removed pieces shrinking away
function W.clear_pieces()
    for _, set in pairs(pieces) do remove_all(set.list) end
    for _, set in ipairs(dying) do remove_all(set.list) end
    pieces, dying = {}, {}
end
-- Mirror the game's pieces: new ones drop in and bounce, removed ones lift and shrink away, a flipped
-- reflector turns on its pedestal.
function W.sync_pieces(game, quiet)
    for i, set in pairs(pieces) do
        local p = game.pieces[i]
        if p and set.kind == "reflector" and p.kind == "reflector" and sig(p) ~= set.sig then
            local to = p.flip == "/" and 45 or -45
            cancel_anims(set.root)
            anim(set.root, "rot", { 0, set.yaw, 0 }, { 0, to, 0 }, 0.32, 0, ease_back)
            set.yaw, set.sig = to, sig(p)
            W.burst(set.X, set.Z, CYAN, 10, 2, 0.75)
        elseif not p or sig(p) ~= set.sig then
            pieces[i] = nil
            cancel_anims(set.root)
            dying[#dying + 1] = set
            anim(set.root, "scale", { 1, 1, 1 }, { 0.05, 0.05, 0.05 }, 0.24, 0, ease_in)
            anim(set.root, "pos", { set.X, 0, set.Z }, { set.X, 0.7, set.Z }, 0.24, 0, ease_out, function()
                remove_all(set.list)
                for k, d in ipairs(dying) do if d == set then table.remove(dying, k) break end end
            end)
        end
    end
    for i, p in pairs(game.pieces) do
        if not pieces[i] then
            local x, y = (i - 1) % GW + 1, floor((i - 1) / GW) + 1
            local list = {}
            local X, Z = wx(x), wz(y)
            local set = build_piece(p, X, Z, list)
            set.list, set.sig, set.t, set.x, set.y, set.X, set.Z = list, sig(p), 9, x, y, X, Z
            pieces[i] = set
            if not quiet then
                set.landing = true
                anim(set.root, "pos", { X, 1.6, Z }, { X, 0, Z }, 0.42, 0, ease_bounce, function()
                    set.landing = false
                    W.burst(X, Z, { 0.5, 0.85, 1 }, 18, 2.5, 0.08)
                    W.shock(X, Z, { 0.5, 0.85, 1 }, 1.3, 0.03, 1.6)
                end)
            end
        end
    end
end
function W.pop(x, y)
    local set = pieces[(y - 1) * GW + x]
    if set then set.t = 0; set.pop = true end
end
function W.piece_flash(x, y)
    local set = pieces[(y - 1) * GW + x]
    if set then set.flash = 1 end
end

local function show_ghost(slot, p, x, y, a, variant)
    local key = p and (sig(p) .. x .. "_" .. y .. a) or nil
    if key == slot.key then return end
    remove_all(slot.nodes); slot.key = key
    slot.set = nil
    if p then slot.X, slot.Z = wx(x), wz(y); slot.set = build_piece(p, wx(x), wz(y), slot.nodes, a, variant) end
end
function W.set_ghost(p, x, y, ok) show_ghost(ghost, p, x, y, ok and 0.42 or 0.16, "ghost") end
function W.set_hint(s) show_ghost(hint, s, s and s.x, s and s.y, 0.5, "hint") end

function W.set_cursor(x, y, c, on)
    if not cursor[1] then return end
    if not on then for i = 1, 4 do cursor[i]:set_enabled(false) end; S.cur = nil; return end
    -- Glide toward the hovered cell rather than snapping (frame-rate independent).
    local tx, tz = wx(x), wz(y)
    if not S.cur then S.cur = { tx, tz } end
    local k = 1 - math.exp(-(S.dt or 0.016) * 22)
    S.cur[1], S.cur[2] = S.cur[1] + (tx - S.cur[1]) * k, S.cur[2] + (tz - S.cur[2]) * k
    local X, Z = S.cur[1], S.cur[2]
    local s = 1.0 + 0.03 * sin(S.t * 7)
    local parts = { { 0, -0.5, 1, 0.035 }, { 0, 0.5, 1, 0.035 }, { -0.5, 0, 0.035, 1 }, { 0.5, 0, 0.035, 1 } }
    for i, q in ipairs(parts) do
        local n = cursor[i]
        n:set_enabled(true)
        n:set_position(v3(X + q[1] * s, 0.02, Z + q[2] * s))
        n:set_scale(v3(q[3] * s, 0.03, q[4] * s))
        emis(n, c, 2.2)
    end
end

------------------------------------------------------------------ pulse playback
local bar_pool, bar_used = {}, 0
local head_pool, head_used = {}, 0
local P = nil          -- active playback
W.echo = false         -- a finished send's trail is still shown

local function bar(i)
    local b = bar_pool[i]
    if not b then
        b = primitives.cube(1)
        glow(b, CYAN, 3)
        bar_pool[i] = b
    end
    return b
end
local function head(i)
    local h = head_pool[i]
    if not h then
        h = { core = primitives.sphere(0.1), w1 = primitives.torus(0.2, 0.012, 48, 8), w2 = primitives.torus(0.32, 0.009, 48, 8) }
        glow(h.core, { 0.85, 1, 1 }, 9)
        glow(h.w1, CYAN, 5)
        glow(h.w2, CYAN, 2.5)
        head_pool[i] = h
    end
    return h
end

function W.clear_trail()
    for i = 1, bar_used do bar_pool[i]:set_enabled(false) end
    bar_used = 0
    for i = 1, head_used do
        local h = head_pool[i]
        h.core:set_enabled(false); h.w1:set_enabled(false); h.w2:set_enabled(false)
    end
    head_used = 0
    P = nil
    W.echo = false
end

-- Start playing a send result. on_event(ev) fires as each tick lands; on_done() at the end.
function W.play(res, strength, on_event, on_done)
    W.clear_trail()
    P = { res = res, S = strength, t = 0, fired = 0, on_event = on_event, on_done = on_done, speed = 1, ev_by_t = {} }
    for _, ev in ipairs(res.events) do
        local l = P.ev_by_t[ev.t] or {}
        l[#l + 1] = ev
        P.ev_by_t[ev.t] = l
    end
end
function W.playing() return P ~= nil and not P.done end
function W.skip() if P and not P.done then P.speed = 6 end end
function W.set_speed(v) if P then P.speed = v end end

-- Live pulse strength 0..1 (strongest pulse in flight), or nil when nothing is playing.
function W.live_strength() return P and not P.done and P.live or nil end

local function draw_trail(k, frac, echo)
    local frames = P.res.frames
    -- Merge consecutive same-direction steps of each pulse into one bar.
    local bars, last = {}, {}
    for t = 1, k do
        local f = frames[t]
        if not f then break end
        local fr = (t == k) and frac or 1
        for _, s in ipairs(f) do
            local x1 = s[1] + (s[3] - s[1]) * fr
            local y1 = s[2] + (s[4] - s[2]) * fr
            local dx, dy = s[3] - s[1], s[4] - s[2]
            local b = last[s[6]]
            if b and b.x1 == s[1] and b.y1 == s[2] and b.dx == (dx > 0 and 1 or (dx < 0 and -1 or 0)) and b.dy == (dy > 0 and 1 or (dy < 0 and -1 or 0)) then
                b.x1, b.y1, b.s = x1, y1, s[5]
            else
                b = { x0 = s[1], y0 = s[2], x1 = x1, y1 = y1, s = s[5], dx = dx > 0 and 1 or (dx < 0 and -1 or 0), dy = dy > 0 and 1 or (dy < 0 and -1 or 0) }
                bars[#bars + 1] = b
                last[s[6]] = b
            end
            if t < k or fr >= 1 then b.x1, b.y1 = s[3], s[4] end
        end
    end
    for i, b in ipairs(bars) do
        local n = bar(i)
        local X0, Z0, X1, Z1 = wx(b.x0), wz(b.y0), wx(b.x1), wz(b.y1)
        local len = abs(X1 - X0) + abs(Z1 - Z0)
        local th = 0.05
        n:set_enabled(len > 1e-3)
        n:set_position(v3((X0 + X1) / 2, BEAM_Y, (Z0 + Z1) / 2))
        if abs(Z1 - Z0) < 1e-4 then n:set_scale(v3(len + th, th, th)) else n:set_scale(v3(th, th, len + th)) end
        local f = max(0, min(1, b.s / max(1, P.S)))
        local e = echo and (0.35 + 0.4 * f) or (0.7 + 1.9 * f)
        emis(n, { 0.1 + 0.25 * f, 0.55 + 0.25 * f, 1 }, e)
    end
    for i = #bars + 1, bar_used do bar_pool[i]:set_enabled(false) end
    bar_used = #bars
    return bars
end

local function update_play(dt)
    if not P then return end
    if P.done then return end
    P.t = P.t + dt * P.speed
    local ticks = P.res.ticks
    local k = min(ticks, floor(P.t / TICK) + 1)
    local frac = min(1, (P.t - (k - 1) * TICK) / TICK)
    -- Fire events for every tick that has landed.
    while P.fired < ticks and P.t >= (P.fired + 1) * TICK do
        P.fired = P.fired + 1
        for _, ev in ipairs(P.ev_by_t[P.fired] or {}) do if P.on_event then P.on_event(ev) end end
    end
    draw_trail(k, frac, false)
    -- Heads: one per pulse in flight this tick, with wave fronts facing the way it travels.
    local used, live = 0, 0
    local f = P.res.frames[k] or {}
    if P.t < ticks * TICK then
        for _, s in ipairs(f) do
            if not (s.stop and frac > 0.5) then
                used = used + 1
                local h = head(used)
                local x = s[1] + (s[3] - s[1]) * frac
                local y = s[2] + (s[4] - s[2]) * frac
                local X, Z = wx(x), wz(y)
                local horiz = abs(s[3] - s[1]) > abs(s[4] - s[2])
                local sgn = horiz and ((s[3] - s[1]) >= 0 and 1 or -1) or ((s[4] - s[2]) >= 0 and 1 or -1)
                local str = max(0, min(1, s[5] / max(1, P.S)))
                live = max(live, str)
                local ph = (S.t * 3) % 1
                h.core:set_enabled(true); h.w1:set_enabled(true); h.w2:set_enabled(true)
                h.core:set_position(v3(X, BEAM_Y, Z))
                local rot = horiz and v3(0, 0, 90) or v3(90, 0, 0)
                for j, w in ipairs({ h.w1, h.w2 }) do
                    local off = (0.06 + 0.12 * j + ph * 0.12) * sgn
                    w:set_rotation(rot)
                    w:set_position(v3(X + (horiz and off or 0), BEAM_Y, Z + (horiz and 0 or off)))
                    local sc = 0.8 + ph * 0.5
                    w:set_scale(v3(sc, sc, sc))
                    emis(w, CYAN, (j == 1 and 5 or 2.5) * (0.4 + 0.6 * str) * (1 - ph * 0.6))
                end
                emis(h.core, { 0.85, 1, 1 }, 4 + 8 * str)
                if LT[2 + used] and used <= 6 then
                    point_light(LT[2 + used], v3(X, BEAM_Y + 0.3, Z), v3(CYAN[1], CYAN[2], CYAN[3]), 2.5 + 4 * str, 2.6)
                end
            end
        end
    end
    for i = used + 1, head_used do
        local h = head_pool[i]
        h.core:set_enabled(false); h.w1:set_enabled(false); h.w2:set_enabled(false)
    end
    for i = used + 1, 6 do if LT[2 + i] then light_off(LT[2 + i]) end end
    head_used = max(used, 0)
    if used > 0 then P.live = live end
    if P.t >= ticks * TICK + 0.35 then
        P.done = true
        draw_trail(ticks, 1, true)
        W.echo = true
        if P.on_done then P.on_done() end
    end
end

------------------------------------------------------------------ fx
function W.burst(X, Z, c, n, speed, y)
    n = max(1, floor((n or 40) * scale_particles()))
    particles.emit_burst({ position = v3(X, y or BEAM_Y, Z), velocity = v3(0, 1.2, 0),
        color_start = vec4(c[1] * 1.8 + 0.2, c[2] * 1.8 + 0.2, c[3] * 1.8 + 0.2, 1), color_end = vec4(c[1], c[2] * 0.6, c[3], 0),
        gravity = v3(0, -3, 0), count = n, size_min = 0.008, size_max = 0.03, life_min = 0.4, life_max = 1.1,
        spawn_radius = 0.2, noise_strength = speed or 4, drag = 1.4 })
end

function W.shock(X, Z, c, size, y, e)
    local r = primitives.torus(0.5, 0.03, 72, 8)
    r:set_position(v3(X, y or 0.05, Z))
    glow(r, c, e or 2.4)
    local s1 = size or 2.4
    tween.to(v3(0.2, 0.2, 0.2), v3(s1, 1, s1), 0.6, function(sv) r:set_scale(sv) end, { on_done = function() r:remove() end })
end

function W.flash(X, Z, c, e) S.flash, S.flash_c, S.flash_x, S.flash_z = e or 1, c, X, Z end
function W.shake(a) S.shake = max(S.shake, a * scale_shake()) end

-- Pulse events -> visuals (sounds and HUD are the caller's). Pieces and bells react physically.
local function piece_at(x, y) return pieces[(y - 1) * GW + x] end
function W.event_fx(ev)
    local X, Z = wx(ev.x or 0), wz(ev.y or 0)
    if ev.kind == "ring" then
        W.set_bell(ev.bell, "rung")
        local set = bells[ev.bell]
        if set then set.hop = 1 end
        W.shock(X, Z, GOLD, 3.2, 0.03, 3)
        W.shock(X, Z, GOLD, 2.0, 0.03, 2)
        W.shock(X, Z, { 1, 0.85, 0.5 }, 1.6, LIP + 0.35, 2)
        W.burst(X, Z, GOLD, 60, 4, LIP + 0.2)
        W.flash(X, Z, GOLD, 1.2)
        if bells[ev.bell + 1] then W.set_bell(ev.bell + 1, "next") end
    elseif ev.kind == "wrong" then
        W.set_bell(ev.bell, "wrong")
        local set = bells[ev.bell]
        if set then set.shudder = 1 end
        W.shock(X, Z, RED, 3, 0.03, 3)
        W.burst(X, Z, RED, 70, 5, LIP + 0.2)
        W.flash(X, Z, RED, 2)
        W.shake(0.6)
    elseif ev.kind == "bounce" then
        W.burst(X, Z, CYAN, 18, 3)
        local set = piece_at(ev.x, ev.y)
        if set then set.flash, set.wob = 1, 1 end
    elseif ev.kind == "split" then
        W.burst(X, Z, CYAN, 36, 5)
        W.shock(X, Z, CYAN, 1.6, BEAM_Y)
        local set = piece_at(ev.x, ev.y)
        if set then set.flash, set.vib = 1, 1 end
    elseif ev.kind == "charge" then
        W.burst(X, Z, GOLD, 40, 4)
        W.shock(X, Z, GOLD, 2.0, BEAM_Y)
        W.flash(X, Z, GOLD, 0.8)
        local set = piece_at(ev.x, ev.y)
        if set then set.flash, set.boost = 1, 1 end
    elseif ev.kind == "damp" then
        W.burst(X, Z, RED, 24, 2, 0.35)
        local set = piece_at(ev.x, ev.y)
        if set then set.flash, set.squash = 1, 1 end
    elseif ev.kind == "absorb" then
        local w = ev.wall and ev.bx and walls[(ev.by - 1) * GW + ev.bx]
        if w then w.flash, w.fc, w.shud = 1, CYAN, 1 end
        W.burst(X, Z, ev.wall and VIOLET or CYAN, 12, 2)
    elseif ev.kind == "fade" then
        W.burst(X, Z, CYAN, 24, 1.5)
    end
end

------------------------------------------------------------------ camera
-- Frame the board: the same composition at every board size (bigger boards sit further away).
function W.frame_camera()
    local s = max(GW / 14, GH / 9, 0.62)
    W.cam_pos = { 0, 14.2 * s + 1.4, 14.2 * s + 1.8 }
    W.cam_look = { 0, 0.2, 0.75 * s + 0.2 }
end

local function aspect_fov()
    local sw, sh = W.screen_size()
    local vf = math.rad(30)
    return math.deg(2 * math.atan(math.tan(vf / 2) * sw / max(1, sh)))
end

------------------------------------------------------------------ per-frame
local function decay(v, rate, dt) return max(0, (v or 0) - rate * dt) end

local function update_pieces(dt)
    for _, set in pairs(pieces) do
        set.t = set.t + dt
        set.flash = decay(set.flash, 3, dt)
        set.wob = decay(set.wob, 2.2, dt)
        set.vib = decay(set.vib, 1.4, dt)
        set.boost = decay(set.boost, 0.8, dt)
        set.squash = decay(set.squash, 2.2, dt)
        local busy = set.landing
        if set.pop and not busy then
            local f = min(1, set.t / 0.32)
            local s = 1 + 0.35 * sin(f * math.pi) * (1 - f) - 0.3 * (1 - f) ^ 3
            set.root:set_scale(v3(s, s, s))
            if f >= 1 then set.pop = false; set.root:set_scale(v3(1, 1, 1)) end
        end
        if set.kind == "reflector" then
            -- A hit mirror rings on its pedestal for a moment.
            if set.wob > 0 then
                set.root:set_rotation(v3(sin(S.t * 38) * 5 * set.wob, set.yaw + sin(S.t * 31) * 4 * set.wob, 0))
                set.was_wob = true
            elseif set.was_wob then
                set.was_wob = false
                set.root:set_rotation(v3(0, set.yaw, 0))
            end
            emis(set.accent, CYAN, 2.3 + 0.5 * sin(S.t * 2.5 + set.x * 0.7 + set.y * 0.4) + 6 * set.flash)
        elseif set.kind == "fork" then
            -- Slow spin; struck tines blur and the whole fork whirls.
            set.spin_a = (set.spin_a or 0) + dt * (40 + 700 * set.vib)
            set.spin:set_rotation(v3(0, set.spin_a, 0))
            set.spin:set_scale(v3(1 + 0.06 * sin(S.t * 95) * set.vib, 1, 1 + 0.06 * sin(S.t * 95 + 1.5) * set.vib))
            emis(set.accent, CYAN, 2.4 + 0.6 * sin(S.t * 3 + set.x) + 6 * set.flash)
        elseif set.kind == "resonator" then
            set.ra = (set.ra or 0) + dt * (1 + 6 * set.boost)
            set.r1:set_rotation(v3(70, set.ra * 80, 0))
            set.r2:set_rotation(v3(-55, -set.ra * 60, 20))
            local s = 1 + 0.08 * sin(S.t * 3) + 0.8 * set.boost
            set.orb:set_scale(v3(s, s, s))
            emis(set.orb, GOLD, 3 + 1.2 * sin(S.t * 4) + 8 * set.flash)
            emis(set.r1, GOLD, 3 + 5 * set.boost)
            emis(set.r2, GOLD, 2 + 4 * set.boost)
        elseif set.kind == "damper" then
            -- Breathes when idle; squashes and wobbles back when it swallows a pulse.
            if not busy and not set.pop then
                local o = set.squash * sin((1 - set.squash) * 20)
                local b = 0.012 * sin(S.t * 1.8 + set.x)
                set.root:set_scale(v3(1 + 0.14 * o - b * 0.5, 1 - 0.3 * o + b, 1 + 0.14 * o - b * 0.5))
            end
            emis(set.accent, RED, 2.1 + 0.4 * sin(S.t * 2 + set.y) + 6 * set.flash)
        end
    end
    -- Ghost and hint float above their cell.
    for i, slot in ipairs({ ghost, hint }) do
        local g = slot.set
        if g then
            if g.kind == "fork" and g.spin then g.spin:set_rotation(v3(0, S.t * 40, 0)) end
            if slot.X then g.root:set_position(v3(slot.X, 0.06 + 0.05 * sin(S.t * (i == 1 and 4 or 2.6)), slot.Z)) end
        end
    end
end

local function update_bells(dt)
    local li = 9
    for _, set in pairs(bells) do
        set.ring_t = set.ring_t + dt
        if set.celebrate then
            set.celebrate = set.celebrate + dt
            if set.celebrate >= 0 then
                set.celebrate = nil
                set.swing, set.ring_t, set.hop = 1, 0, 1
                W.shock(set.X, set.Z, GOLD, 2.6, 0.03, 2.4)
                W.burst(set.X, set.Z, GOLD, 40, 4, LIP + 0.3)
            end
        end
        set.swing = decay(set.swing, 0.7, dt)
        set.hop = decay(set.hop, 3, dt)
        set.shudder = decay(set.shudder, 1.2, dt)
        -- Ring: a damped swing. Idle: the faintest sway, each bell on its own phase.
        local idle = 0.9 * sin(S.t * 1.1 + set.ph)
        local ang = set.swing * 14 * sin(set.ring_t * 9) + idle
        local roll = ang * 0.3 + set.shudder * 7 * sin(S.t * 55) + 0.6 * sin(S.t * 0.9 + set.ph * 2)
        set.pivot:set_rotation(v3(ang, 0, roll))
        if not set.dropping then
            set.pivot:set_position(v3(set.X, PIVOT + 0.07 * set.hop * abs(sin((1 - set.hop) * 9)), set.Z))
        end
        if set.state == "rung" then
            local e = 0.1 + 0.55 * math.exp(-set.ring_t * 2.5) + 0.03 * sin(S.t * 3 + set.n)
            emis(set.bell, GOLD, e)
            for i, rp in ipairs(set.ripples) do
                -- Ripples breathe outward.
                local ph = (S.t * 0.35 + i / 3) % 1
                local sc = 0.92 + 0.16 * ph
                rp:set_scale(v3(sc, 1, sc))
                emis(rp, GOLD, (1.3 - i * 0.35) * (1 - ph * 0.6) + 3 * math.exp(-set.ring_t * 3))
            end
            if LT[li] then point_light(LT[li], v3(set.X, LIP + 0.25, set.Z), v3(1, 0.65, 0.3), 2.2 + 6 * math.exp(-set.ring_t * 2), 3) end
        elseif set.state == "wrong" then
            emis(set.bell, RED, 0.8 + 0.6 * sin(S.t * 10))
            if LT[li] then point_light(LT[li], v3(set.X, LIP + 0.25, set.Z), v3(1, 0.2, 0.15), 4, 3) end
        else
            if set.state == "next" then
                local s = 1 + 0.06 * sin(S.t * 4)
                set.next_ring:set_scale(v3(s, 1, s))
                emis(set.next_ring, CYAN, 1.4 + 0.9 * sin(S.t * 4))
            end
            if LT[li] then light_off(LT[li]) end
        end
        li = li + 1
    end
    for i = li, 16 do if LT[i] then light_off(LT[i]) end end
end

local function update_room(dt)
    W.build_t = W.build_t + dt
    local lit = min(1, W.build_t / 1.0)
    -- Light runs along the pillar bands in a slow wave; hit pillars flash and shudder.
    for _, w in pairs(walls) do
        w.flash = decay(w.flash, 1.6, dt)
        w.shud = decay(w.shud, 3, dt)
        local c = w.fc or VIOLET
        local base = 1.0 + 0.35 * sin(S.t * 1.6 - (w.X + w.Z) * 0.55)
        if w.flash > 0 then
            local f = min(1, w.flash)
            pcall(material.set, w.band, "emissive", v3(VIOLET[1] * base * (1 - f) + c[1] * 4 * f, VIOLET[2] * base * (1 - f) + c[2] * 4 * f, VIOLET[3] * base * (1 - f) + c[3] * 4 * f))
        else
            emis(w.band, VIOLET, base * lit)
        end
        if w.shud > 0 then w.root:set_position(v3(w.X + 0.025 * w.shud * sin(S.t * 60), 0, w.Z)) end
    end
    for i, n in ipairs(rails) do emis(n, { 0.25, 0.55, 1 }, 2.6 * lit * (0.85 + 0.15 * sin(S.t * 0.8 + i * 1.3))) end
    if W.seams then emis(W.seams, VIOLET, 0.22 * lit * (0.8 + 0.2 * sin(S.t * 0.6))) end
    -- Horn: breathes; brighter while a pulse is out; kicks back when it fires.
    if horn.membrane then
        horn.kick = decay(horn.kick, 3.2, dt)
        if horn.root and horn.dx then
            local back = 0.16 * horn.kick * horn.kick
            horn.root:set_position(v3(horn.X - horn.dx * back, 0, horn.Z - horn.dy * back))
        end
        local e = (P and not P.done) and (8 + 3 * sin(S.t * 20)) or (3.5 + 1.5 * sin(S.t * 2.2))
        e = e + 25 * horn.kick
        emis(horn.membrane, CYAN, e)
        emis(horn.lip, CYAN, e * 0.45)
        if LT[1] then point_light(LT[1], v3(horn.mx, BEAM_Y + 0.3, horn.mz), v3(CYAN[1], CYAN[2], CYAN[3]), 1.6 + e * 0.15, 2.4) end
    end
end

function W.update(dt, game)
    S.t = S.t + dt
    S.dt = dt
    flush_mats()
    update_anims(dt)
    update_play(dt)
    update_pieces(dt)
    update_bells(dt)
    update_room(dt)
    -- Flash light.
    S.flash = max(0, S.flash - dt * 3)
    if LT[2] then point_light(LT[2], v3(S.flash_x, 1.0, S.flash_z), v3(S.flash_c[1], S.flash_c[2], S.flash_c[3]), S.flash * 10, 4.5) end
    -- Camera: flies in on a new chamber, then holds the framing with a slow drift; leans in when the
    -- chamber resonates; smooth shake.
    S.shake = max(0, S.shake - dt * 1.8)
    local sk, t = S.shake, S.t
    local sx = sk * 0.25 * (sin(t * 31.7) + 0.6 * sin(t * 17.3 + 1.3))
    local sy = sk * 0.25 * (sin(t * 27.1 + 0.7) + 0.6 * sin(t * 13.9 + 2.1))
    local d = sin(S.t * 0.22) * 0.18
    local cp, cl = W.cam_pos or { 0, 15, 17 }, W.cam_look or { 0, 0, 1 }
    S.cam_t = (S.cam_t or 9) + dt
    local f = ease_inout(min(1, S.cam_t / 1.9))
    local c0 = { cp[1] + cp[3] * 0.55, cp[2] * 1.5, cp[3] * 1.2 }
    local px, py, pz = c0[1] + (cp[1] - c0[1]) * f, c0[2] + (cp[2] - c0[2]) * f, c0[3] + (cp[3] - c0[3]) * f
    -- Menus: the camera pulls back and sways slowly round the chamber, shifted so it sits right of the
    -- menu panel; it eases back to the play framing when a chamber resumes.
    S.orbit_amt = (S.orbit_amt or 0) + ((W.orbit and 1 or 0) - (S.orbit_amt or 0)) * min(1, dt * 1.6)
    local lx = cl[1]
    if S.orbit_amt > 0.001 then
        local am = S.orbit_amt
        S.orbit_a = (S.orbit_a or 0) + dt * 0.22
        local ang = sin(S.orbit_a) * 0.5 * am
        local ox, oz = px - cl[1], pz - cl[3]
        local ca, sa = cos(ang), sin(ang)
        local back = 1 + 0.2 * am
        px, pz, py = cl[1] + (ox * ca - oz * sa) * back, cl[3] + (ox * sa + oz * ca) * back, cl[2] + (py - cl[2]) * back
        local shift = -GW * 0.3 * am
        px, lx = px + shift, lx + shift
    end
    if S.zoom_t then
        S.zoom_t = S.zoom_t + dt
        local z = 0.09 * sin(math.pi * min(1, S.zoom_t / 2.8))
        px, py, pz = px + (cl[1] - px) * z, py + (cl[2] - py) * z, pz + (cl[3] - pz) * z
        if S.zoom_t > 2.8 then S.zoom_t = nil end
    end
    pcall(function() cam:set_fov(aspect_fov()) end)
    cam:set_position(v3(px + d + sx, py, pz + sy))
    cam:look_at(v3(lx + d * 0.4 + sx * 0.4, cl[2], cl[3] + sy * 0.4))
    W.begin_frame()
end

------------------------------------------------------------------ picking
function W.screen_size()
    local s = runtime_ui.get_surface_size()
    return s.width or 1280, s.height or 800
end
local VC = {}
function W.begin_frame()
    VC.vp, VC.inv = cam:get_view_projection(), cam:get_inv_view_projection()
    VC.sw, VC.sh = W.screen_size()
    -- TAA shifts the projection by a new sub-pixel jitter every frame; badges projected through it trembled.
    local ok, j = pcall(function() return cam:get_jitter() end)
    VC.jx, VC.jy = ok and j and j.x or 0, ok and j and j.y or 0
end
function W.project(X, Y, Z)
    local vp = VC.vp or cam:get_view_projection()
    local c = vp * vec4(X, Y, Z, 1)
    if c.w <= 1e-5 then return nil end
    local nx, ny = c.x / c.w - (VC.jx or 0), c.y / c.w - (VC.jy or 0)   -- jitter-free, so badges hold still
    local sw, sh = VC.sw, VC.sh
    if not sw then sw, sh = W.screen_size() end
    if S.flip == nil then
        local a = vp * vec4(0, 0, -3, 1)
        local b = vp * vec4(0, 0, 3, 1)
        S.flip = (b.y / b.w) < (a.y / a.w)
    end
    local sy = S.flip and (0.5 - ny * 0.5) or (0.5 + ny * 0.5)
    return (nx * 0.5 + 0.5) * sw, sy * sh
end
-- UI pixels -> board cell (or nil): the mouse ray meets the floor.
function W.cell_at(mx, my)
    local inv = VC.inv or cam:get_inv_view_projection()
    local sw, sh = VC.sw, VC.sh
    if not sw then sw, sh = W.screen_size() end
    if S.flip == nil then W.project(0, 0, 0) end
    local nx = mx / sw * 2 - 1 + (VC.jx or 0)                          -- back into the jittered space inv lives in
    local ny = (S.flip and (1 - my / sh * 2) or (my / sh * 2 - 1)) + (VC.jy or 0)
    local a = inv * vec4(nx, ny, 0.25, 1)
    local b = inv * vec4(nx, ny, 0.75, 1)
    local ax, ay, az = a.x / a.w, a.y / a.w, a.z / a.w
    local bx, by, bz = b.x / b.w, b.y / b.w, b.z / b.w
    local dy = by - ay
    if abs(dy) < 1e-6 then return nil end
    local t = (0 - ay) / dy
    local X, Z = ax + (bx - ax) * t, az + (bz - az) * t
    local x = floor(X + (GW + 1) / 2 + 0.5)
    local y = floor(Z + (GH + 1) / 2 + 0.5)
    if x < 1 or y < 1 or x > GW or y > GH then return nil end
    return x, y
end

function W.time() return S.t end
function W.set_orbit(on) W.orbit = on end
return W
end
