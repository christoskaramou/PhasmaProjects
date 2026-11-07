-- Ricochet Parlour world. The static board (walnut frame and arch, felt, brass pins, rubber bumpers, cups,
-- slot, the papered room under a warm lamp) is a pre-rendered Cycles backdrop (tools/make_backdrop.py) shown
-- unlit on a quad that exactly fills the fixed camera's view. On top, in 3D: the balls (lit by the scene's
-- lamp and a lamp-lit parlour HDR), their soft shadows on the felt, ghost trails and the effects.
-- The board stands in the XY plane facing the camera (+Z); board point (x, y) is world (x, y, *).
-- The camera must match the bake exactly (tools/gen_meshes.py, tools/backdrop_scene.py).
return function(R)
local W = {}
local floor, min, max, abs, sin, cos, sqrt = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt
local function v3(x, y, z) return vec3(x, y, z) end

local BALL_Z = R.BALL_R + 0.01          -- balls roll against the felt (front face at z = 0)
W.BALL_Z = BALL_Z
W.CAM = { pos = { 1.3, 4.4, 12.6 }, look = { 0.15, 4.05, 0.0 }, vfov = 46 }
local cam
local S = { t = 0, shake = 0 }

------------------------------------------------------------------ materials (template clones replay writes: engine quirk)
local mat_q = {}
local function later(f)
    f()
    mat_q[#mat_q + 1] = { f = f, c = 0 }
end
local function flush_mats()
    for i = #mat_q, 1, -1 do
        local q = mat_q[i]
        q.c = q.c + 1
        if q.c == 2 or q.c == 6 or q.c == 30 then q.f() end
        if q.c >= 30 then table.remove(mat_q, i) end
    end
end
local function mat(n, base, metal, rough, emis)
    pcall(material.set, n, "base_color", vec4(base[1], base[2], base[3], base[4] or 1))
    pcall(material.set, n, "emissive", v3(emis and emis[1] or 0, emis and emis[2] or 0, emis and emis[3] or 0))
    pcall(material.set, n, "metallic", metal or 0)
    pcall(material.set, n, "roughness", rough or 0.5)
end
W.BALL_LOOK = {
    steel = function(n) mat(n, { 0.8, 0.81, 0.84 }, 1, 0.08) end,
    iron = function(n) mat(n, { 0.13, 0.13, 0.14 }, 0.85, 0.32) end,
    gold = function(n) mat(n, { 1.0, 0.76, 0.33 }, 1, 0.1) end,
    -- Raster draws one see-through layer where hybrid ray tracing blended front and back faces, so the
    -- alpha is higher; matched to the hybrid look by measurement (2026-11-07).
    glass = function(n)
        pcall(material.set_render_type, n, "alpha_blend")
        mat(n, { 0.92, 0.96, 0.8, 0.62 }, 0, 0.02)
    end,
}

------------------------------------------------------------------ init
function W.init()
    cam = scene.get_active_camera()
    pcall(function() cam:set_projection_mode("perspective") end)
    if not W.settings_node then
        W.settings_node = scene.add_empty_node("Scene Settings")
        pcall(function() W.settings_node:set_scene_settings(true) end)
    end
    -- Raster, like every Arcade game. The engine defaults to hybrid ray tracing, whose per-frame TLAS refit
    -- faulted the GPU (device lost) as kicks added and removed effect nodes; it adds nothing visible here.
    pcall(settings.set_render_mode, "raster")
    if skybox and skybox.load then pcall(skybox.load, "parlour.hdr") end
    -- The backdrop is already graded (bloom, tone curve, vignette): no tonemapping or bloom on top of it.
    for k, v in pairs({ tonemapping = false, bloom = false, render_scale = 1.0, taa = true, fxaa = false, cas_sharpening = false,
        motion_blur = false, ssao = false, ssr = true, IBL = true, IBL_intensity = 0.55, shadows = false, color_grading = false,
        dof = false }) do pcall(settings.set, k, v) end
    -- The backdrop: drawn as-is (black base, the picture as emissive).
    local t = scene.find_model and scene.find_model("T_backdrop")
    if t then
        W.backdrop = t
        later(function()
            mat(t, { 0, 0, 0, 1 }, 0, 1, { 1, 1, 1 })
            pcall(material.set_texture, t, "emissive", "Textures/backdrop.png")
        end)
    end
    W.balls, W.fx = {}, {}
end

------------------------------------------------------------------ balls, shadows, trails
local GHOSTS = { { 0.05, 0.39 }, { 0.1, 0.24 }, { 0.16, 0.13 } }   -- { seconds back, alpha: raster's single layer, 1-(1-a)^2 of the old two }
-- Lamp direction (from the bake's lamp at (0.4, 10.5, 4.5) toward the board): a ball's shadow falls this far
-- down the felt per unit of height above it.
local SH_DX, SH_DY = -0.4 / 4.5, -6.5 / 4.5
local function shadow_node()
    local n = primitives.cube(1)
    pcall(material.set_render_type, n, "alpha_blend")
    mat(n, { 1, 1, 1, 0.62 }, 0, 1)
    pcall(material.set_texture, n, "base_color", "Textures/shadow.png")
    return n
end
function W.sync_balls(g)
    local seen = {}
    for _, b in ipairs(g and g.balls or {}) do
        local e = W.balls[b.id]
        if not e then
            local n = primitives.uv_sphere(R.BALL_R, 48, 32)
            W.BALL_LOOK[b.kind](n)
            e = { n = n, hist = {}, ghosts = {}, shadow = shadow_node(), kind = b.kind }
            for k, gd in ipairs(GHOSTS) do
                local gn = primitives.uv_sphere(R.BALL_R, 24, 16)
                pcall(material.set_render_type, gn, "alpha_blend")
                mat(gn, b.kind == "gold" and { 1, 0.8, 0.45, gd[2] } or { 0.8, 0.82, 0.88, gd[2] }, 0.5, 0.3)
                e.ghosts[k] = gn
            end
            W.balls[b.id] = e
        end
        seen[b.id] = true
        e.n:set_position(v3(b.x, b.y, BALL_Z))
        -- Shadow on the felt: offset along the lamp, a little stretched, soft.
        local h = BALL_Z * 0.85
        e.shadow:set_position(v3(b.x + SH_DX * h, b.y + SH_DY * h * 0.55, 0.004))
        e.shadow:set_scale(v3(0.62, 0.78, 0.001))
        -- Trail: ghosts where the ball was a moment ago, only while it moves fast.
        table.insert(e.hist, 1, { t = S.t, x = b.x, y = b.y })
        while #e.hist > 40 do table.remove(e.hist) end
        local fast = (b.vx * b.vx + b.vy * b.vy) > 4
        for k, gd in ipairs(GHOSTS) do
            local gn, hp = e.ghosts[k], nil
            for _, hh in ipairs(e.hist) do if S.t - hh.t >= gd[1] then hp = hh break end end
            if fast and hp then
                gn:set_enabled(true)
                gn:set_position(v3(hp.x, hp.y, BALL_Z - 0.005 * k))
                local s = 1 - 0.05 * k
                gn:set_scale(v3(s, s, s))
            else
                gn:set_enabled(false)
            end
        end
    end
    for id, e in pairs(W.balls) do
        if not seen[id] then
            pcall(function() e.n:remove() end)
            pcall(function() e.shadow:remove() end)
            for _, gn in ipairs(e.ghosts) do pcall(function() gn:remove() end) end
            W.balls[id] = nil
        end
    end
end

------------------------------------------------------------------ effects
local function burst(x, y, c, n, sp, life, z)
    pcall(particles.emit_burst, { position = v3(x, y, z or BALL_Z), velocity = v3(0, 0, 0.6),
        color_start = vec4(c[1], c[2], c[3], 0.85), color_end = vec4(c[1], c[2], c[3], 0), gravity = v3(0, -1.2, 0),
        count = n, size_min = 0.008, size_max = 0.025, life_min = 0.2, life_max = life or 0.5, spawn_radius = 0.12, noise_strength = sp or 1.5, drag = 2 })
end
local function ring_fx(x, y, z, R0, r0, c, e, life, grow)
    local r = primitives.torus(R0, r0, 72, 8)
    mat(r, { c[1], c[2], c[3], 1 }, 0, 0.4, { c[1] * e, c[2] * e, c[3] * e })
    W.fx[#W.fx + 1] = { n = r, x = x, y = y, z = z, t = 0, life = life, kind = "ring", c = c, e = e, grow = grow }
end
-- A kick: a soft puff of air under the ball and a thin white ring that spreads and fades.
function W.kick(x, y, quality)
    burst(x, y - R.BALL_R, { 1, 0.97, 0.9 }, floor(10 + 22 * quality), 2.2)
    ring_fx(x, y, BALL_Z + 0.02, 0.24, 0.007, { 1, 0.96, 0.88 }, 0.6, 0.32, 1.5)
end
function W.whiff(x, y) burst(x, y, { 0.8, 0.75, 0.65 }, 6, 1) end
-- A ball off a rubber bumper: a red-orange flick at the ring.
function W.pin_hit(p, speed)
    if p.rubber and speed > 1.5 then ring_fx(p.x, p.y, BALL_Z, 0.13, 0.03, { 1, 0.35, 0.25 }, 0.6, 0.18, 0.3) end
end
-- A ball through a cup: the brass ring glints.
function W.cup(i, x, y)
    local c = R.CUPS[i]
    if c then ring_fx(c.x, c.y, 0.02, c.r, 0.04, { 1, 0.82, 0.45 }, 1.6, 0.6, 0.12) end
    burst(x, y, { 1, 0.85, 0.5 }, 28, 2.5, 0.7)
end
-- Lost through the slot: dust from the pocket and a jolt.
function W.drop(x)
    burst(x or 0, -0.1, { 0.5, 0.45, 0.4 }, 24, 1.6, 0.8, 0.2)
    S.shake = 0.6
end
function W.shatter(x, y)
    for i = 1, 16 do
        local n = primitives.cube(1)
        pcall(material.set_render_type, n, "alpha_blend")
        local s = 0.03 + math.random() * 0.06
        n:set_scale(v3(s, s * 0.7, 0.008))
        mat(n, { 0.88, 0.94, 1, 0.55 }, 0, 0.03)
        W.fx[#W.fx + 1] = { n = n, x = x, y = y, z = BALL_Z, vx = (math.random() - 0.5) * 4, vy = math.random() * 3, vz = math.random() * 2,
            r = math.random() * 360, w = (math.random() - 0.5) * 800, t = 0, life = 0.9, kind = "shard" }
    end
    S.shake = 0.4
end

------------------------------------------------------------------ per frame
function W.update(dt, g)
    S.t = S.t + dt
    flush_mats()
    W.sync_balls(g)
    for i = #W.fx, 1, -1 do
        local f = W.fx[i]
        f.t = f.t + dt
        local u = min(1, f.t / f.life)
        if f.kind == "ring" then
            local s = 1 + (f.grow or 0) * u
            f.n:set_position(v3(f.x, f.y, f.z)); f.n:set_scale(v3(s, s, 1)); f.n:set_rotation(v3(90, 0, 0))
            local a = (1 - u) ^ 1.5
            pcall(material.set, f.n, "base_color", vec4(f.c[1], f.c[2], f.c[3], a))
            pcall(material.set, f.n, "emissive", v3(f.c[1] * f.e * a, f.c[2] * f.e * a, f.c[3] * f.e * a))
        elseif f.kind == "shard" then
            f.vy = f.vy - 9 * dt
            f.x, f.y, f.z = f.x + f.vx * dt, f.y + f.vy * dt, f.z + f.vz * dt
            f.r = f.r + f.w * dt
            f.n:set_position(v3(f.x, f.y, f.z)); f.n:set_rotation(v3(f.r, f.r * 0.7, 0))
        end
        if u >= 1 then pcall(function() f.n:remove() end); table.remove(W.fx, i) end
    end
    -- Camera: fixed on the bake's view. Shake turns the view a touch (a pure rotation, so the 3D balls stay
    -- glued to the pictured felt; moving the camera would slide them against it).
    S.shake = max(0, S.shake - dt * 2.5)
    local sk = S.shake
    local sx, sy = sk * 0.05 * sin(S.t * 43), sk * 0.05 * sin(S.t * 37 + 1)
    local sw, sh = W.screen_size()
    pcall(function() cam:set_fov(math.deg(2 * math.atan(math.tan(math.rad(W.CAM.vfov / 2)) * sw / max(1, sh)))) end)
    local p, l = W.CAM.pos, W.CAM.look
    cam:set_position(v3(p[1], p[2], p[3]))
    cam:look_at(v3(l[1] + sx, l[2] + sy, l[3]))
    W.vp, W.inv = cam:get_view_projection(), cam:get_inv_view_projection()
    -- TAA shifts the projection by a new sub-pixel jitter every frame; labels projected through it trembled.
    local ok, j = pcall(function() return cam:get_jitter() end)
    W.jx, W.jy = ok and j and j.x or 0, ok and j and j.y or 0
end

------------------------------------------------------------------ picking
function W.screen_size()
    local s = runtime_ui.get_surface_size()
    return s.width or 1280, s.height or 800
end
local function flip()
    if W.flip == nil then
        local vp = W.vp or cam:get_view_projection()
        local a, b = vp * vec4(0, 6, 0, 1), vp * vec4(0, 2, 0, 1)
        W.flip = (a.y / a.w) > (b.y / b.w)    -- y-up NDC: screen y must be inverted
    end
    return W.flip
end
function W.project(X, Y, Z)
    local vp = W.vp or cam:get_view_projection()
    local c = vp * vec4(X, Y, Z, 1)
    if c.w <= 1e-5 then return nil end
    local sw, sh = W.screen_size()
    local nx, ny = c.x / c.w - (W.jx or 0), c.y / c.w - (W.jy or 0)   -- jitter-free, so labels hold still
    return (nx * 0.5 + 0.5) * sw, (flip() and (0.5 - ny * 0.5) or (0.5 + ny * 0.5)) * sh
end
-- UI pixels -> board point, by meeting the mouse ray with the plane the balls roll in.
function W.board_point(mx, my)
    local inv = W.inv or cam:get_inv_view_projection()
    local sw, sh = W.screen_size()
    local nx = mx / sw * 2 - 1 + (W.jx or 0)                          -- back into the jittered space inv lives in
    local ny = (flip() and (1 - my / sh * 2) or (my / sh * 2 - 1)) + (W.jy or 0)
    local a, b = inv * vec4(nx, ny, 0.25, 1), inv * vec4(nx, ny, 0.75, 1)
    local ax, ay, az = a.x / a.w, a.y / a.w, a.z / a.w
    local bx, by, bz = b.x / b.w, b.y / b.w, b.z / b.w
    if abs(bz - az) < 1e-6 then return nil end
    local t = (BALL_Z - az) / (bz - az)
    return ax + (bx - ax) * t, ay + (by - ay) * t
end
function W.shake(a) S.shake = max(S.shake, a) end
return W
end
