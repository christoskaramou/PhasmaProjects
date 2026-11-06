-- Resonance Break 3D world (prototype, engine primitives): a warm stone hall with a wooden floor, brass
-- lane inlays, a brass strike rail, four brass tuning forks on walnut stands, and tinted cathedral-glass
-- panes in lead frames sliding toward the line. Engine Y is up; the hall runs away from the camera (-Z).
return function(R)
local W = {}
local floor, min, max, abs, sin, cos = math.floor, math.min, math.max, math.abs, math.sin, math.cos
local function v3(x, y, z) return vec3(x, y, z) end

W.LANE_X = { -2.4, -0.8, 0.8, 2.4 }
W.TINT = { { 0.25, 0.45, 0.85 }, { 0.85, 0.3, 0.38 }, { 0.95, 0.68, 0.22 }, { 0.3, 0.7, 0.4 } }   -- cobalt, rose, amber, green
local STRIKE_Z = -2.0      -- the strike line
local FORK_Z = -1.1
local PANE_W, PANE_H = 1.3, 1.9
local cam
local S = { t = 0, shake = 0 }
local LT = {}

local function mat(n, base, emis, metal, rough)
    pcall(material.set, n, "base_color", vec4(base[1], base[2], base[3], base[4] or 1))
    pcall(material.set, n, "emissive", v3(emis and emis[1] or 0, emis and emis[2] or 0, emis and emis[3] or 0))
    pcall(material.set, n, "metallic", metal or 0)
    pcall(material.set, n, "roughness", rough or 0.5)
end
local function box(x, y, z, sx, sy, sz, base, metal, rough, emis)
    local n = primitives.cube(1)
    n:set_position(v3(x, y, z)); n:set_scale(v3(sx, sy, sz))
    mat(n, base, emis, metal, rough)
    return n
end
local function cyl(x, y, z, r, h, base, metal, rough)
    local n = primitives.cylinder(r, h)
    n:set_position(v3(x, y, z))
    mat(n, base, nil, metal, rough)
    return n
end
local BRASS, BRASS_POL = { 0.85, 0.62, 0.3 }, { 0.92, 0.72, 0.4 }
local WALNUT, LEAD = { 0.09, 0.045, 0.022 }, { 0.07, 0.07, 0.075 }
local WOOD, STONE, STONE_D = { 0.3, 0.16, 0.07 }, { 0.42, 0.38, 0.33 }, { 0.27, 0.24, 0.21 }

------------------------------------------------------------------ init
function W.init()
    cam = scene.get_active_camera()
    pcall(function() cam:set_projection_mode("perspective") end)
    if not W.settings_node then
        W.settings_node = scene.add_empty_node("Scene Settings")
        pcall(function() W.settings_node:set_scene_settings(true) end)
    end
    -- Natural look: tonemapped, gentle bloom only for real highlights (sun windows, lanterns).
    for k, v in pairs({ bloom = true, bloom_strength = 0.35, bloom_range = 1.0, render_scale = 1.0, taa = true, fxaa = false,
        cas_sharpening = false, motion_blur = false, tonemapping = true, ssao = true, ssr = true, IBL_intensity = 1.3,
        shadows = false, color_grading = false }) do pcall(settings.set, k, v) end
    pcall(function() lights.set_directional_light(0, v3(-0.7, -0.75, -0.55), v3(1.0, 0.84, 0.62), 5.0) end)
    pcall(function()
        local base = #lights.get_point_lights()
        for _ = 1, 16 do lights.add_point() end
        for i = 0, 15 do LT[i + 1] = base + i end
    end)

    -- Hall: wooden floor with plank seams, stone walls, pillars and arches, sunlit windows, lanterns.
    box(0, -0.1, -30, 7.6, 0.2, 70, WOOD, 0.0, 0.32)
    for k = -9, 9 do box(k * 0.4, 0.002, -30, 0.012, 0.004, 70, { 0.04, 0.025, 0.012 }, 0, 0.8) end
    for _, sx in ipairs({ -1, 1 }) do box(sx * 4.05, 3.0, -30, 0.5, 6.0, 70, STONE, 0, 0.85) end
    box(0, 6.2, -30, 8.6, 0.4, 70, STONE_D, 0, 0.9)
    box(0, 3.0, -64, 8.6, 6.4, 0.5, STONE_D, 0, 0.9)      -- end wall
    -- Daylight pooling on the floor under each window, and warm light at the forks.
    for k = 0, 5 do
        local li = LT[9 + k]
        if li then pcall(lights.set_point_light, li, v3(-1.6, 4.2, -1.5 - k * 5.5), v3(1, 0.85, 0.65), k == 0 and 4 or 8 - k, 8) end
    end
    if LT[15] then pcall(lights.set_point_light, LT[15], v3(0, 3.2, 0.6), v3(1, 0.86, 0.7), 2.5, 6) end
    for k = 0, 13 do
        local z = -3.5 - k * 3.5
        for _, sx in ipairs({ -1, 1 }) do
            box(sx * 3.55, 2.8, z, 0.55, 5.6, 0.6, STONE_D, 0, 0.88)
            box(sx * 3.55, 0.12, z, 0.7, 0.25, 0.75, STONE_D, 0, 0.88)
        end
        box(0, 5.6, z, 7.6, 0.5, 0.6, STONE_D, 0, 0.88)
        if k < 13 then
            -- Window in the left wall: warm daylight.
            box(-3.82, 3.9, z - 1.75, 0.05, 2.0, 1.3, { 1, 0.9, 0.75 }, 0, 0.5, { 3.2, 2.6, 1.9 })
            box(-3.84, 3.9, z - 1.75, 0.08, 2.0, 0.06, LEAD, 0.8, 0.45)
        end
        if k % 2 == 0 and k < 10 then
            box(3.68, 2.6, z - 1.75, 0.12, 0.3, 0.2, LEAD, 0.8, 0.45)
            local f = primitives.sphere(0.05); f:set_position(v3(3.62, 2.6, z - 1.75)); mat(f, { 1, 0.6, 0.25 }, { 6, 3.2, 1.1 }, 0, 0.5)
            local li = LT[3 + k / 2]
            if li then pcall(lights.set_point_light, li, v3(3.4, 2.6, z - 1.75), v3(1, 0.62, 0.3), 3.0, 5) end
        end
    end
    -- Brass lane inlays and the strike rail.
    for _, x in ipairs({ -3.2, -1.6, 0, 1.6, 3.2 }) do box(x, 0.004, -30, 0.035, 0.008, 70, BRASS, 1, 0.25) end
    W.rail = box(0, 0.035, STRIKE_Z, 6.8, 0.07, 0.12, BRASS_POL, 1, 0.12)

    -- Forks.
    W.forks = {}
    for i, x in ipairs(W.LANE_X) do
        local fk = { x = x, hit = 0, t = 9 }
        box(x, 0.07, FORK_Z, 0.62, 0.14, 0.42, WALNUT, 0, 0.35)
        box(x, 0.15, FORK_Z, 0.5, 0.02, 0.3, BRASS, 1, 0.25)
        local en = cyl(x, 0.12, FORK_Z + 0.215, 0.07, 0.012, W.TINT[i], 0, 0.25)
        en:set_rotation(v3(90, 0, 0))
        cyl(x, 0.36, FORK_Z, 0.035, 0.4, BRASS_POL, 1, 0.12)
        box(x, 0.6, FORK_Z, 0.34, 0.06, 0.06, BRASS_POL, 1, 0.12)
        fk.tines = {}
        for k, sx in ipairs({ -1, 1 }) do fk.tines[k] = cyl(x + sx * 0.14, 1.0, FORK_Z, 0.03, 0.78, BRASS_POL, 1, 0.12) end
        W.forks[i] = fk
    end
    W.shards = {}
    W.panes = {}
end

------------------------------------------------------------------ panes (pooled)
local pool, slot_of = {}, {}
local function new_pane()
    local P = { parts = {} }
    P.glass = primitives.cube(1)
    pcall(material.set_render_type, P.glass, "alpha_blend")
    P.frame = {}
    for i = 1, 7 do P.frame[i] = primitives.cube(1); mat(P.frame[i], LEAD, nil, 0.8, 0.5) end
    return P
end
local function place_pane(P, x, z, tint, a)
    local y0 = 0.2
    P.glass:set_enabled(true)
    P.glass:set_position(v3(x, y0 + PANE_H / 2, z)); P.glass:set_scale(v3(PANE_W, PANE_H, 0.035))
    mat(P.glass, { tint[1], tint[2], tint[3], 0.5 * a }, nil, 0, 0.06)
    local f = P.frame
    local parts = {
        { x, y0 + PANE_H, z, PANE_W + 0.05, 0.05, 0.06 }, { x, y0, z, PANE_W + 0.05, 0.05, 0.06 },
        { x - PANE_W / 2, y0 + PANE_H / 2, z, 0.05, PANE_H, 0.06 }, { x + PANE_W / 2, y0 + PANE_H / 2, z, 0.05, PANE_H, 0.06 },
        { x, y0 + PANE_H / 2, z, PANE_W, 0.018, 0.045 },
    }
    for i, q in ipairs(parts) do
        f[i]:set_enabled(true); f[i]:set_position(v3(q[1], q[2], q[3])); f[i]:set_scale(v3(q[4], q[5], q[6])); f[i]:set_rotation(v3(0, 0, 0))
    end
    -- Diagonal lead cames.
    for k, s in ipairs({ -1, 1 }) do
        local n = f[5 + k]
        n:set_enabled(true); n:set_position(v3(x, y0 + PANE_H / 2, z)); n:set_scale(v3(0.018, PANE_H * 1.12, 0.045)); n:set_rotation(v3(0, 0, s * 31))
    end
end
local function hide_pane(P)
    P.glass:set_enabled(false)
    for _, n in ipairs(P.frame) do n:set_enabled(false) end
end

-- Draw the game's visible panes. Shifting panes show their current colour.
function W.sync_panes(g)
    local seen = {}
    for _, p in ipairs(g:visible()) do
        if not p.done or p.result == "miss" then
            local P = slot_of[p]
            if not P then
                P = table.remove(pool) or new_pane()
                slot_of[p] = P
            end
            seen[p] = true
            local ahead = p.t - g.t
            local z = STRIKE_Z - ahead * R.speed(p.wave)
            local tint = W.TINT[R.key_at(p, g.t)]
            local a = min(1, (R.LEAD - ahead) / 0.35)              -- fade in from the far dark
            if p.result == "miss" then a = max(0, 1 + ahead / 0.4) end
            place_pane(P, W.LANE_X[p.lane], z, tint, a)
        end
    end
    for p, P in pairs(slot_of) do
        if not seen[p] then hide_pane(P); pool[#pool + 1] = P; slot_of[p] = nil end
    end
end

------------------------------------------------------------------ effects
-- A pane breaks: tinted shards burst and tumble to the floor; the fork rings.
function W.shatter(lane, key)
    local x = W.LANE_X[lane]
    local tint = W.TINT[key]
    for i = 1, 16 do
        local n = primitives.cube(1)
        pcall(material.set_render_type, n, "alpha_blend")
        local s = 0.06 + math.random() * 0.12
        n:set_scale(v3(s, s * 0.7, 0.01))
        local px, py = x + (math.random() - 0.5) * PANE_W, 0.2 + math.random() * PANE_H
        n:set_position(v3(px, py, STRIKE_Z))
        mat(n, { tint[1], tint[2], tint[3], 0.6 }, nil, 0, 0.05)
        W.shards[#W.shards + 1] = { n = n, x = px, y = py, z = STRIKE_Z, vx = (px - x) * 2.2 + (math.random() - 0.5),
            vy = 1 + math.random() * 2, vz = 1.5 + math.random() * 2.5, rx = math.random() * 360, ry = math.random() * 360,
            wx = (math.random() - 0.5) * 900, wy = (math.random() - 0.5) * 900, life = 1.1 + math.random() * 0.5 }
    end
    pcall(particles.emit_burst, { position = v3(x, 1.1, STRIKE_Z), velocity = v3(0, 0.6, 1.2),
        color_start = vec4(1, 0.95, 0.85, 0.9), color_end = vec4(tint[1], tint[2], tint[3], 0), gravity = v3(0, -6, 0),
        count = 40, size_min = 0.006, size_max = 0.018, life_min = 0.3, life_max = 0.8, spawn_radius = 0.6, noise_strength = 2, drag = 1 })
    W.ring(lane)
end
function W.ring(lane) local fk = W.forks[lane]; if fk then fk.hit, fk.t = 1, 0 end end
function W.shake(a) S.shake = max(S.shake, a) end

------------------------------------------------------------------ per frame
function W.update(dt, g)
    S.t = S.t + dt
    if g then W.sync_panes(g) end
    -- Fork tines quiver after a strike (decaying, fast).
    for _, fk in ipairs(W.forks or {}) do
        fk.t = fk.t + dt
        fk.hit = max(0, fk.hit - dt * 2.2)
        local q = 0.02 * fk.hit * sin(fk.t * 140)
        fk.tines[1]:set_position(v3(fk.x - 0.14 - q, 1.0, FORK_Z))
        fk.tines[2]:set_position(v3(fk.x + 0.14 + q, 1.0, FORK_Z))
    end
    -- Shards: ballistic, spin, settle on the floor and fade.
    for i = #W.shards, 1, -1 do
        local s = W.shards[i]
        s.life = s.life - dt
        s.vy = s.vy - 9.8 * dt
        s.x, s.y, s.z = s.x + s.vx * dt, s.y + s.vy * dt, s.z + s.vz * dt
        if s.y < 0.01 then s.y, s.vy, s.vx, s.vz = 0.01, 0, s.vx * 0.6, s.vz * 0.6; s.wx, s.wy = 0, 0 end
        s.rx, s.ry = s.rx + s.wx * dt, s.ry + s.wy * dt
        s.n:set_position(v3(s.x, s.y, s.z)); s.n:set_rotation(v3(s.rx, s.ry, 0))
        if s.life <= 0 then pcall(function() s.n:remove() end); table.remove(W.shards, i) end
    end
    -- Camera: fixed view down the hall, a breath of sway, shake on a crack.
    S.shake = max(0, S.shake - dt * 2.5)
    local sk = S.shake
    local sx = sk * 0.12 * sin(S.t * 41) + 0.03 * sin(S.t * 0.4)
    local sy = sk * 0.1 * sin(S.t * 37 + 1)
    local sw, sh = W.screen_size()
    pcall(function() cam:set_fov(math.deg(2 * math.atan(math.tan(math.rad(25)) * sw / max(1, sh)))) end)
    cam:set_position(v3(sx, 2.4 + sy, 3.2))
    cam:look_at(v3(sx * 0.3, 1.0, -12))
    W.vp = cam:get_view_projection()
end

function W.screen_size()
    local s = runtime_ui.get_surface_size()
    return s.width or 1280, s.height or 800
end
-- World -> UI pixels.
function W.project(X, Y, Z)
    local vp = W.vp or cam:get_view_projection()
    local c = vp * vec4(X, Y, Z, 1)
    if c.w <= 1e-5 then return nil end
    local sw, sh = W.screen_size()
    if W.flip == nil then
        local a = vp * vec4(0, 3, -5, 1)
        local b = vp * vec4(0, 0, -5, 1)
        W.flip = (a.y / a.w) > (b.y / b.w)    -- higher world point -> larger NDC y means y-up NDC
    end
    local ny = c.y / c.w
    local sy = W.flip and (0.5 - ny * 0.5) or (0.5 + ny * 0.5)
    return (c.x / c.w * 0.5 + 0.5) * sw, sy * sh
end
W.STRIKE_Z, W.FORK_Z = STRIKE_Z, FORK_Z
return W
end
