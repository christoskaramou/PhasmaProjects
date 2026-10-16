-- MISSILE COMMAND : NEON NIGHT  (PhasmaEngine remake)
-- Single-file Lua gameplay: pooled 3D nodes, emissive materials + bloom, particles,
-- point lights, runtime_ui HUD, engine tweens and synthesized audio.

local PROJECT = ""  -- Assets-relative (was /workspace/... Linux path)
local CAMY, CAMZ, FOVX = 10.0, 32.0, 1.2
local HW = CAMZ * math.tan(FOVX * 0.5)
local GROUND = 0.0
local rand, floor, sqrt, abs, min, max = math.random, math.floor, math.sqrt, math.abs, math.min, math.max
local sin, cos, atan2, pi = math.sin, math.cos, math.atan2 or math.atan, math.pi

------------------------------------------------------------------ helpers
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function lerp(a, b, t) return a + (b - a) * t end
local function ease_out(t) return 1 - (1 - t) * (1 - t) end
local function sfx(name) pcall(audio.play, name .. ".wav") end
-- shared settings menu (Assets/Scripts/Lib/settings_menu.lua; see /workspace/games/common/SETTINGS_API.md)
local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "SETTINGS", subtitle = "- NEON NIGHT -", click = function() sfx("tick") end,
    theme = { accent = { 1.0, 0.3, 0.45, 1 }, accent2 = { 0.4, 0.9, 1.0, 1 } } })
local function hsv(h, s, v)
    local i = floor(h * 6) % 6; local f = h * 6 - floor(h * 6)
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v end
    return v, p, q
end

local function mk(kind, a, b)
    local n
    if kind == "cube" then n = primitives.cube(a or 1)
    elseif kind == "sphere" then n = primitives.uv_sphere(a or 1, b or 20, b or 14)
    elseif kind == "ico" then n = primitives.ico_sphere(a or 1, b or 2)
    elseif kind == "cone" then n = primitives.cone(a or 1, b or 2)
    elseif kind == "cyl" then n = primitives.cylinder(a or 1, b or 2)
    elseif kind == "pyr" then n = primitives.pyramid(a or 1, b or 1) end
    return n
end
local function paint(n, base, emi, rough, metal)
    material.set(n, "base_color", vec4(base[1], base[2], base[3], 1.0))
    material.set(n, "emissive", vec3(emi[1], emi[2], emi[3]))
    material.set(n, "roughness", rough or 0.6)
    material.set(n, "metallic", metal or 0.0)
end
local function ghost(n, r, g, b, a)
    pcall(material.set_render_type, n, "alpha_blend")
    material.set(n, "base_color", vec4(r, g, b, a))
    material.set(n, "emissive", vec3(r, g, b))
end
local function glow(n, r, g, b) material.set(n, "emissive", vec3(r, g, b)) end
local function place(n, x, y, z, rz, sx, sy, sz)
    n:set_transform(vec3(x, y, z), vec3(0, 0, rz or 0), vec3(sx or 1, sy or 1, sz or 1))
end
local function show(n, on) if n then n:set_enabled(on) end end

------------------------------------------------------------------ state
local S = {
    mode = "boot", t = 0, wave = 0, score = 0, hi = 0, mult = 1,
    next_bonus = 10000, bonus_cities = 0, banner_t = 0, shake = 0,
    paused = false,
}
local cities, bases = {}, {}
local enemies, shots, booms = {}, {}, {}
local pool = { etrail = {}, ehead = {}, ptrail = {}, phead = {}, mark = {}, boom = {}, halo = {}, eglow = {}, pglow = {} }
local lightsIdx, lightsNode = {}, {}
local cross = {}
local flyer = nil
local W, H = 1280, 720
local ui = { tally = nil }
local mouse_prev, keys_prev = false, {}
local wave_plan = nil

local function multiplier(w) return min(6, floor((w + 1) / 2)) end

------------------------------------------------------------------ world build
local CITY_X = { -13.6, -9.4, -5.0, 5.0, 9.4, 13.6 }
local BASE_X = { -18.6, 0.0, 18.6 }

local function build_sky_and_post()
    pcall(skybox.load, "night.hdr")  -- bare name: skybox.load resolves it to Assets/Skybox/ (a path with "/" is taken literally)
    local ok, node = pcall(scene.add_empty_node, "MC_SceneSettings")
    if ok and node then pcall(function() node:set_scene_settings(true) end) end
    local function st(k, v) pcall(settings.set, k, v) end
    st("hdr", false)  -- HDR+bloom shows blocky holes on lavapipe (engine bug); LDR bloom is clean
    st("bloom", true); st("bloom_strength", 1.05); st("bloom_range", 0.55); st("cas_sharpening", true)  -- RENDER_SETTINGS.md
    st("tonemapping", true); st("taa", true); st("fxaa", false); st("ssao", false)
    st("ssr", false); st("motion_blur", false); st("dof", false); st("shadows", false)
    st("color_grading", true); st("color_grading_saturation", 1.15); st("color_grading_contrast", 1.08)
end

local function build_ground()
    local g = mk("cube", 1); place(g, 0, -2.0, 0, 0, 80, 4.0, 10)
    paint(g, { 0.05, 0.03, 0.08 }, { 0.012, 0.006, 0.02 }, 0.95)
    -- neon horizon line on the ground lip
    local lip = mk("cube", 1); place(lip, 0, 0.02, 2.0, 0, 80, 0.05, 0.05)
    paint(lip, { 0, 0, 0 }, { 0.6, 0.15, 1.2 })
    -- foreground dunes
    for i = -9, 9 do
        local d = mk("sphere", 1, 14); local x = i * 4.6 + rand() * 1.5
        place(d, x, -0.7, -1.5 - rand() * 2, 0, 3.2 + rand() * 2, 1.0 + rand() * 0.6, 2.0)
        paint(d, { 0.06, 0.035, 0.09 }, { 0.008, 0.004, 0.016 }, 0.9)
    end
end

------------------------------------------------------------------ cooked scene nodes
local function node(name) local ok, n = pcall(scene.find_model, name); if ok then return n end end
local function park(n) if n then n:set_position(vec3(0, -1000, 0)); n:set_enabled(false) end end
local TEX = { spark = 0, smoke = 0, fire = 0 }
local EM = { fire = {}, smoke = {}, ember = {}, exh = {}, psmoke = {}, cfire = {}, csmoke = {} }
local deferred_mats = {}   -- materials applied a few frames after creation (engine quirk)
local function later(fn) deferred_mats[#deferred_mats + 1] = fn end

local function build_cities()
    local tint = { { 1.0, 0.78, 0.45 }, { 0.75, 0.88, 1.0 }, { 1.0, 0.7, 0.5 }, { 0.8, 1.0, 0.9 }, { 1.0, 0.85, 0.6 }, { 0.7, 0.85, 1.0 } }
    for ci, cx in ipairs(CITY_X) do
        local c = { x = cx, alive = true, parts = {}, col = { tint[ci][1] * 2, tint[ci][2] * 2, tint[ci][3] * 2 } }
        c.body = node("City" .. (ci - 1) .. "_body"); c.lit = node("City" .. (ci - 1) .. "_lit")
        c.dark = node("City" .. (ci - 1) .. "_dark"); c.trim = node("City" .. (ci - 1) .. "_trim")
        c.beacon = node("City" .. (ci - 1) .. "_beacon"); c.rubble = node("Rubble" .. (ci - 1))
        for _, n in ipairs({ c.body, c.lit, c.dark, c.trim, c.beacon }) do c.parts[#c.parts + 1] = { n = n } end
        local tn = tint[ci]
        later(function()
            -- reflective dark glass towers, lit window grids, concrete/steel trim
            material.set(c.body, "base_color", vec4(0.16, 0.19, 0.26, 1)); material.set(c.body, "metallic", 0.75)
            material.set(c.body, "roughness", 0.12); material.set(c.body, "emissive", vec3(0.06, 0.07, 0.11))
            material.set(c.lit, "base_color", vec4(tn[1], tn[2], tn[3], 1)); material.set(c.lit, "emissive", vec3(tn[1] * 1.3, tn[2] * 1.3, tn[3] * 1.3))
            material.set(c.dark, "base_color", vec4(0.03, 0.05, 0.09, 1)); material.set(c.dark, "metallic", 0.9)
            material.set(c.dark, "roughness", 0.05); material.set(c.dark, "emissive", vec3(0.03, 0.05, 0.1))
            material.set(c.trim, "base_color", vec4(0.32, 0.33, 0.38, 1)); material.set(c.trim, "metallic", 0.4)
            material.set(c.trim, "roughness", 0.55); material.set(c.trim, "emissive", vec3(0.02, 0.02, 0.03))
            material.set(c.beacon, "base_color", vec4(1, 0.1, 0.05, 1)); material.set(c.beacon, "emissive", vec3(3, 0.2, 0.1))
            material.set(c.rubble, "base_color", vec4(0.12, 0.1, 0.1, 1)); material.set(c.rubble, "roughness", 0.9)
            material.set(c.rubble, "emissive", vec3(0.35, 0.08, 0.02))
        end)
        park(c.rubble)
        cities[ci] = c
    end
end

local function build_bases()
    for bi, bx in ipairs(BASE_X) do
        local b = { x = bx, y = 2.1, ammo = 10, alive = true, stock = {}, flash = 0 }
        local mound = mk("sphere", 1, 32); place(mound, bx, -0.2, -0.2, 0, 3.2, 1.0, 2.4)
        paint(mound, { 0.09, 0.08, 0.1 }, { 0.0, 0.0, 0.0 }, 0.95)
        b.silo = node("Silo" .. (bi - 1))
        later(function()
            material.set(b.silo, "base_color", vec4(0.35, 0.37, 0.42, 1)); material.set(b.silo, "metallic", 0.7)
            material.set(b.silo, "roughness", 0.35); material.set(b.silo, "emissive", vec3(0.02, 0.03, 0.05))
        end)
        local ring = mk("cyl", 1, 1); place(ring, bx, 1.12, 0, 0, 1.02, 0.03, 1.02)
        paint(ring, { 0.1, 0.1, 0.1 }, { 0.2, 1.6, 2.4 })
        b.ring = ring
        local i = 0
        for row = 1, 4 do
            for k = 1, 5 - row do
                i = i + 1
                if i <= 10 then
                    local n = node(string.format("Stock_%02d", (bi - 1) * 10 + i - 1))
                    local px = bx + (k - (5 - row + 1) * 0.5) * 0.3
                    local py = 0.55 + (4 - row) * 0.0
                    if n then n:set_transform(vec3(px, 0.3 + row * 0.0 + 0.62, 1.55 - row * 0.28), vec3(0, 0, 0), vec3(1.6, 1.6, 1.6)) end
                    b.stock[i] = n
                end
            end
        end
        bases[bi] = b
    end
end

local function emitter(o)
    o.spawn_rate = o.spawn_rate or 0
    local ok, idx = pcall(particles.add_emitter, o)
    return ok and idx or -1
end
local function em_set(idx, t) if idx and idx >= 0 then pcall(particles.set_emitter, idx, t) end end

local function build_pools()
    local ps = SET:particle_scale()
    for i = 1, 24 do
        local t = mk("cube", 1); paint(t, { 0, 0, 0 }, { 0.9, 0.3, 0.08 }); show(t, false); pool.etrail[i] = t
        local tg = mk("cube", 1); ghost(tg, 1.0, 0.25, 0.05, 0.12); show(tg, false); pool.eglow[i] = tg
        local h = node(string.format("Meteor_%02d", i - 1)); park(h); pool.ehead[i] = h
        local hh = mk("sphere", 0.62, 16); ghost(hh, 1, 0.42, 0.1, 0.3); show(hh, false); pool.ehalo = pool.ehalo or {}; pool.ehalo[i] = hh
        EM.fire[i] = emitter({ position = vec3(0, -100, 0), velocity = vec3(0, 1, 0), color_start = vec4(0.6, 0.3, 0.08, 0.9),
            color_end = vec4(0.5, 0.06, 0.01, 0.0), count = floor(70 * ps) + 1, size_min = 0.25, size_max = 0.55, life_min = 0.25, life_max = 0.6,
            spawn_radius = 0.25, noise_strength = 0.6, drag = 1.5, gravity = vec3(0, 0, 0), texture_index = TEX.fire })
        EM.smoke[i] = emitter({ position = vec3(0, -100, 0), velocity = vec3(0, 0.3, 0), color_start = vec4(0.12, 0.1, 0.1, 0.5),
            color_end = vec4(0.06, 0.06, 0.09, 0.0), count = floor(140 * ps) + 1, size_min = 0.35, size_max = 0.9, life_min = 1.8, life_max = 3.6,
            spawn_radius = 0.2, noise_strength = 0.35, drag = 0.8, gravity = vec3(0, 0.25, 0), texture_index = TEX.smoke })
        EM.ember[i] = emitter({ position = vec3(0, -100, 0), velocity = vec3(0, 0.5, 0), color_start = vec4(1.0, 0.8, 0.35, 1.0),
            color_end = vec4(1.0, 0.2, 0.0, 0.0), count = floor(40 * ps) + 1, size_min = 0.025, size_max = 0.06, life_min = 0.5, life_max = 1.3,
            spawn_radius = 0.3, noise_strength = 1.6, drag = 0.6, gravity = vec3(0, -2.5, 0), texture_index = TEX.spark })
    end
    for i = 1, 16 do
        local t = mk("cube", 1); paint(t, { 0, 0, 0 }, { 0.3, 0.7, 1.0 }); show(t, false); pool.ptrail[i] = t
        local tg = mk("cube", 1); ghost(tg, 0.2, 0.6, 1.0, 0.1); show(tg, false); pool.pglow[i] = tg
        local h = node(string.format("Missile_%02d", i - 1)); park(h); pool.phead[i] = h
        local m1 = mk("cube", 1); paint(m1, { 0, 0, 0 }, { 0.3, 2.5, 3.5 }); show(m1, false)
        local m2 = mk("cube", 1); paint(m2, { 0, 0, 0 }, { 0.3, 2.5, 3.5 }); show(m2, false)
        pool.mark[i] = { m1, m2 }
        EM.exh[i] = emitter({ position = vec3(0, -100, 0), velocity = vec3(0, -1, 0), color_start = vec4(0.75, 0.9, 1.0, 1.0),
            color_end = vec4(1.0, 0.4, 0.1, 0.0), count = floor(50 * ps) + 1, size_min = 0.1, size_max = 0.22, life_min = 0.08, life_max = 0.22,
            spawn_radius = 0.04, noise_strength = 0.4, drag = 2, gravity = vec3(0, 0, 0), texture_index = TEX.fire })
        EM.psmoke[i] = emitter({ position = vec3(0, -100, 0), velocity = vec3(0, 0.15, 0), color_start = vec4(0.17, 0.18, 0.21, 0.5),
            color_end = vec4(0.08, 0.08, 0.12, 0.0), count = floor(170 * ps) + 1, size_min = 0.16, size_max = 0.42, life_min = 1.6, life_max = 3.2,
            spawn_radius = 0.05, noise_strength = 0.25, drag = 1.0, gravity = vec3(0, 0.12, 0), texture_index = TEX.smoke })
    end
    for ci, c in ipairs(cities) do
        EM.cfire[ci] = emitter({ position = vec3(c.x, -100, 0), velocity = vec3(0, 1.6, 0), color_start = vec4(0.6, 0.3, 0.08, 0.9),
            color_end = vec4(0.5, 0.06, 0.01, 0.0), count = floor(160 * ps) + 1, size_min = 0.2, size_max = 0.5, life_min = 0.4, life_max = 1.0,
            spawn_radius = 1.2, noise_strength = 0.5, drag = 0.4, gravity = vec3(0, 0.8, 0), texture_index = TEX.fire })
        EM.csmoke[ci] = emitter({ position = vec3(c.x, -100, 0), velocity = vec3(0.35, 1.2, 0), color_start = vec4(0.12, 0.09, 0.09, 0.5),
            color_end = vec4(0.05, 0.05, 0.08, 0.0), count = floor(220 * ps) + 1, size_min = 0.5, size_max = 1.4, life_min = 3, life_max = 6,
            spawn_radius = 1.0, noise_strength = 0.3, drag = 0.3, gravity = vec3(0.1, 0.35, 0), texture_index = TEX.smoke })
    end
    for i = 1, 40 do
        local b = mk("sphere", 1, 28); paint(b, { 1, 1, 1 }, { 1, 0.6, 0.3 }, 0.2); show(b, false); pool.boom[i] = b
        local h = mk("sphere", 1, 24); ghost(h, 1, 0.5, 0.2, 0.22); show(h, false); pool.halo[i] = h
        local rg = primitives.torus(1, 0.03, 64, 8); paint(rg, { 0, 0, 0 }, { 1, 0.8, 0.6 }); show(rg, false); pool.ring = pool.ring or {}; pool.ring[i] = rg
    end
    pool.debris = {}
    for i = 1, 48 do
        local d = node(string.format("Debris_%02d", i - 1)); park(d)
        pool.debris[i] = { n = d, live = false }
    end
    later(function()
        for i = 1, 24 do
            local h = pool.ehead[i]
            material.set(h, "base_color", vec4(0.16, 0.13, 0.12, 1)); material.set(h, "roughness", 0.95)
            material.set(h, "emissive", vec3(0.55, 0.16, 0.03))
        end
        for i = 1, 16 do
            local h = pool.phead[i]
            material.set(h, "base_color", vec4(0.85, 0.87, 0.9, 1)); material.set(h, "metallic", 0.8); material.set(h, "roughness", 0.3)
            material.set(h, "emissive", vec3(0.05, 0.08, 0.12))
        end
        for i = 1, 48 do
            local d = pool.debris[i].n
            material.set(d, "base_color", vec4(0.2, 0.17, 0.15, 1)); material.set(d, "roughness", 0.9)
            material.set(d, "emissive", vec3(0.6, 0.2, 0.04))
        end
    end)
    -- crosshair
    for i = 1, 4 do
        local n = mk("cube", 1); paint(n, { 0, 0, 0 }, { 0.4, 3.5, 1.2 }); cross[i] = n
    end
    local d = mk("sphere", 0.06, 8); paint(d, { 0, 0, 0 }, { 1, 6, 2 }); cross[5] = d
    -- point lights: 6 explosion lights + 3 city glow lights (moved via their scene nodes)
    local before = #(lights.get_point_lights() or {})
    for i = 1, 9 do lights.add_point() end
    local pls = lights.get_point_lights() or {}
    for i = 1, 9 do
        lightsIdx[i] = before + i - 1
        local L = pls[before + i]
        lightsNode[i] = L and L.name and node(L.name) or nil
        lights.set_point_light(lightsIdx[i], vec3(0, -50, 0), vec3(1, 1, 1), 0.0, 1.0)
    end
    -- bomber / satellite
    local body = mk("cube", 1); paint(body, { 0.2, 0.2, 0.25 }, { 2.5, 0.2, 1.8 }, 0.3, 0.8); show(body, false)
    local wing = mk("cube", 1); paint(wing, { 0.1, 0.1, 0.1 }, { 1.4, 0.1, 0.9 }); show(wing, false)
    local eye = mk("sphere", 0.14, 10); paint(eye, { 0, 0, 0 }, { 8, 2, 0.5 }); show(eye, false)
    flyer = { body = body, wing = wing, eye = eye, active = false }
end

-- point light helper: colour/intensity via lights API, position via the light's scene node
local function set_light(i, x, y, z, r, g, b, inten, rad)
    lights.set_point_light(lightsIdx[i], vec3(x, y, z), vec3(r, g, b), inten, rad)
    local n = lightsNode[i]; if n then pcall(function() n:set_position(vec3(x, y, z)) end) end
end

------------------------------------------------------------------ pools
local function take(list, used)
    for i = 1, #list do if not used[i] then used[i] = true; return i end end
    return nil
end
local used = { e = {}, p = {}, b = {} }

local function set_seg(n, x1, y1, x2, y2, w)
    local dx, dy = x2 - x1, y2 - y1
    local len = sqrt(dx * dx + dy * dy)
    if len < 0.02 then len = 0.02 end
    n:set_transform(vec3((x1 + x2) * 0.5, (y1 + y2) * 0.5, 0), vec3(0, 0, math.deg(atan2(dy, dx))), vec3(len, w, w))
end

------------------------------------------------------------------ fx
local light_rr = 0
local function flash_light(x, y, r, g, b, inten, rad, life)
    light_rr = light_rr % 6 + 1
    booms.lights = booms.lights or {}
    booms.lights[light_rr] = { x = x, y = y, r = r, g = g, b = b, i = inten, rad = rad, t = 0, life = life }
end

local function burst(o)
    o.count = max(1, floor((o.count or 40) * SET:particle_scale()))
    o.cleanup_delay = o.cleanup_delay or ((o.life_max or 1) + 0.5)
    pcall(particles.emit_burst, o)
end
-- hot sparks: small, bright, fast, falling
local function sparks(x, y, r, g, b, count, speed, life)
    burst({ position = vec3(x, y, 0.4), velocity = vec3(0, 1.0, 0), color_start = vec4(r, g, b, 1.0),
        color_end = vec4(r, g * 0.3, b * 0.1, 0.0), count = count or 60, size_min = 0.025, size_max = 0.07,
        life_min = (life or 1.0) * 0.4, life_max = life or 1.0, spawn_radius = 0.15, noise_strength = speed or 6.0,
        drag = 1.2, gravity = vec3(0, -6.0, 0), texture_index = TEX.spark })
end
-- rolling fireball: big soft fire sprites
local function fireball(x, y, size, count)
    burst({ position = vec3(x, y, 0.3), velocity = vec3(0, 0.8, 0), color_start = vec4(0.75, 0.45, 0.16, 1.0),
        color_end = vec4(0.5, 0.08, 0.01, 0.0), count = count or 45, size_min = 0.35 * size, size_max = 0.8 * size,
        life_min = 0.35, life_max = 0.9, spawn_radius = 0.5 * size, noise_strength = 2.6 * size, drag = 2.5,
        gravity = vec3(0, 1.2, 0), texture_index = TEX.fire })
end
-- billowing smoke column
local function smoke_puff(x, y, size, count, life)
    burst({ position = vec3(x, y, -0.1), velocity = vec3(0.2, 0.9, 0), color_start = vec4(0.13, 0.11, 0.11, 0.5),
        color_end = vec4(0.05, 0.05, 0.08, 0.0), count = count or 40, size_min = 0.5 * size, size_max = 1.2 * size,
        life_min = (life or 3) * 0.5, life_max = life or 3, spawn_radius = 0.6 * size, noise_strength = 1.0 * size,
        drag = 0.9, gravity = vec3(0.1, 0.4, 0), texture_index = TEX.smoke })
end
-- ground shockwave dust: wide, flat, fast-decelerating
local function dust_ring(x, y)
    for k = -1, 1, 2 do
        burst({ position = vec3(x + k * 0.3, y + 0.15, 0.6), velocity = vec3(k * 4.5, 0.35, 0), color_start = vec4(0.17, 0.14, 0.13, 0.5),
            color_end = vec4(0.08, 0.07, 0.09, 0.0), count = 30, size_min = 0.3, size_max = 0.7, life_min = 1.0, life_max = 2.2,
            spawn_radius = 0.25, noise_strength = 1.4, drag = 2.2, gravity = vec3(0, 0.15, 0), texture_index = TEX.smoke })
    end
end
local function smoke(x, y) smoke_puff(x, y + 0.5, 1.2, 70, 4) end

-- tumbling rock/concrete debris (cooked chunks) with simple ballistic physics
local debris_live = {}
local function throw_debris(x, y, n, power, up)
    for k = 1, n do
        for _, d in ipairs(pool.debris) do
            if not d.live then
                d.live = true; d.x, d.y = x + (rand() - 0.5) * 0.6, y + rand() * 0.3
                local a = (rand() * 0.8 + 0.1) * pi
                if not up then a = rand() * 2 * pi end
                local sp = power * (0.5 + rand() * 0.7)
                d.vx, d.vy = cos(a) * sp, sin(a) * sp
                d.rx, d.rz, d.wr = rand() * 360, rand() * 360, (rand() - 0.5) * 900
                d.s = 0.6 + rand() * 0.9; d.t = 0
                d.n:set_enabled(true)
                debris_live[#debris_live + 1] = d
                break
            end
        end
    end
end
local function update_debris(dt)
    local k = 1
    while k <= #debris_live do
        local d = debris_live[k]
        d.t = d.t + dt
        d.vy = d.vy - 9.0 * dt; d.vx = d.vx * (1 - 0.3 * dt)
        d.x = d.x + d.vx * dt; d.y = d.y + d.vy * dt
        d.rx = d.rx + d.wr * dt; d.rz = d.rz + d.wr * 0.7 * dt
        if d.y < 0.05 or d.t > 4 then
            if d.y < 0.05 and rand() < 0.5 then
                burst({ position = vec3(d.x, 0.1, 0.4), velocity = vec3(0, 0.6, 0), color_start = vec4(0.4, 0.32, 0.3, 0.45),
                    color_end = vec4(0.05, 0.05, 0.07, 0), count = 6, size_min = 0.15, size_max = 0.35, life_min = 0.6, life_max = 1.4,
                    spawn_radius = 0.1, noise_strength = 0.8, drag = 1.5, gravity = vec3(0, 0.2, 0), texture_index = TEX.smoke })
            end
            d.live = false; park(d.n); table.remove(debris_live, k)
        else
            d.n:set_transform(vec3(d.x, d.y, 0.5), vec3(d.rx, 0, d.rz), vec3(d.s, d.s, d.s))
            -- burning chunks leave little ember trails
            if rand() < dt * 18 then
                burst({ position = vec3(d.x, d.y, 0.5), velocity = vec3(0, 0.2, 0), color_start = vec4(1, 0.5, 0.15, 0.9),
                    color_end = vec4(0.4, 0.05, 0.0, 0), count = 3, size_min = 0.06, size_max = 0.14, life_min = 0.3, life_max = 0.7,
                    spawn_radius = 0.05, noise_strength = 0.3, drag = 1, gravity = vec3(0, 0.4, 0), texture_index = TEX.fire, cleanup_delay = 1.2 })
            end
            k = k + 1
        end
    end
end

local function spawn_boom(x, y, owner, maxr)
    local i = take(pool.boom, used.b)
    if not i then return end
    local b = { i = i, x = x, y = y, t = 0, r = 0, maxr = maxr or 2.5, owner = owner, hue = rand() }
    booms[#booms + 1] = b
    show(pool.boom[i], true); show(pool.halo[i], true); show(pool.ring[i], true)
    place(pool.boom[i], x, y, 0, 0, 0.05, 0.05, 0.05); place(pool.halo[i], x, y, 0, 0, 0.05, 0.05, 0.05)
    local sz = (maxr or 2.5) / 2.5
    if owner == "player" then
        sparks(x, y, 1.0, 0.85, 0.55, 70, 9, 1.0)
        fireball(x, y, sz, 30)
        smoke_puff(x, y, sz, 22, 3.0)
        flash_light(x, y, 1.0, 0.7, 0.4, 40, 10, 1.3)
    elseif owner == "ground" then
        sparks(x, y, 1.0, 0.6, 0.25, 90, 10, 1.3)
        fireball(x, y + 0.3, sz * 1.3, 55)
        smoke_puff(x, y + 0.5, sz * 1.4, 45, 4.5)
        dust_ring(x, 0)
        throw_debris(x, y + 0.2, 8, 7, true)
        flash_light(x, y + 1, 1.0, 0.45, 0.15, 60, 12, 1.6)
    else
        sparks(x, y, 1.0, 0.55, 0.2, 80, 9, 1.2)
        fireball(x, y, sz, 40)
        smoke_puff(x, y, sz, 30, 3.5)
        throw_debris(x, y, 4, 5, false)
        flash_light(x, y, 1.0, 0.45, 0.15, 50, 10, 1.4)
    end
    sfx("explode")
end

------------------------------------------------------------------ HUD
local function txt(id, x, y, w, h, text, scale, col, align, z)
    runtime_ui.set_quad("hud", id, {
        x = x, y = y, w = w, h = h, z = z or 5, style = "text", label = text, body = text,
        fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 }, text_color = col or { 1, 1, 1, 1 },
        font_scale = scale or 1.0, align_h = align or "center", align_v = "middle", no_input = true,
    })
end
local function panel(id, x, y, w, h, fill, border, z, visible)
    runtime_ui.set_quad("hud", id, {
        x = x, y = y, w = w, h = h, z = z or 1, style = "text", label = "",
        fill = fill, border = border or { 0, 0, 0, 0 }, corner_radius = 10, no_input = true,
        visible = visible ~= false,
    })
end
local hud_ids = {}
local function hud_hide(prefix)
    for id, _ in pairs(hud_ids) do
        if id:sub(1, #prefix) == prefix then runtime_ui.set_quad("hud", id, { visible = false, w = 0, h = 0 }) ; hud_ids[id] = nil end
    end
end
local function T(id, ...) hud_ids[id] = true; txt(id, ...) end
local function P(id, ...) hud_ids[id] = true; panel(id, ...) end

local function surface()
    local ok, s = pcall(runtime_ui.get_surface_size)
    if ok and s and (s.w or s.width) then return (s.w or s.width), (s.h or s.height) end
    return W, H
end

local function draw_fx(dt)
    local sw, sh = surface()
    S.flash = max(0, (S.flash or 0) - dt * 2.5)
    runtime_ui.set_quad("hud", "fx_flash", { x = 0, y = 0, w = S.flash > 0.01 and sw or 0, h = S.flash > 0.01 and sh or 0, z = 30, style = "text", label = "", fill = { 1.0, 0.55, 0.3, S.flash * 0.35 }, border = { 0, 0, 0, 0 }, no_input = true, visible = S.flash > 0.01 })
end
local function draw_hud()
    local sw, sh = surface()
    local pulse = 0.75 + 0.25 * sin(S.t * 3)
    P("top_bar", 0, 0, sw, sh * 0.075, { 0.02, 0.0, 0.06, 0.55 }, { 0.5, 0.2, 1.0, 0.0 }, 1)
    T("score_l", sw * 0.02, sh * 0.005, sw * 0.12, sh * 0.03, "SCORE", 0.9, { 0.6, 0.5, 1.0, 1 }, "left")
    T("score", sw * 0.02, sh * 0.03, sw * 0.25, sh * 0.045, string.format("%07d", S.score), 1.8, { 1.0, 0.35, 0.55, 1 }, "left")
    T("hi_l", sw * 0.4, sh * 0.005, sw * 0.2, sh * 0.03, "HIGH SCORE", 0.9, { 0.6, 0.5, 1.0, 1 })
    T("hi", sw * 0.4, sh * 0.03, sw * 0.2, sh * 0.045, string.format("%07d", math.max(S.hi, S.score)), 1.8, { 0.3, 0.9, 1.0, 1 })
    T("wave_l", sw * 0.78, sh * 0.005, sw * 0.2, sh * 0.03, "WAVE", 0.9, { 0.6, 0.5, 1.0, 1 }, "right")
    T("wave", sw * 0.68, sh * 0.03, sw * 0.3, sh * 0.045,
        string.format("%02d   x%d", math.max(S.wave, 1), S.mult), 1.8, { 1.0, 0.85, 0.3, 1 }, "right")
    -- ammo counters under each base
    for bi, b in ipairs(bases) do
        local fx = (b.x / HW) * 0.5 + 0.5
        local col = b.ammo == 0 and { 1.0, 0.2, 0.2, pulse } or (b.ammo <= 3 and { 1, 0.7, 0.2, 1 } or { 0.5, 0.95, 1.0, 0.95 })
        local label = (b.ammo == 0) and "OUT" or (b.ammo <= 3 and ("LOW " .. b.ammo) or tostring(b.ammo))
        T("ammo" .. bi, sw * fx - 60, sh * 0.945, 120, sh * 0.045, label, 1.15, col)
    end
end

------------------------------------------------------------------ crosshair
local aimx, aimy = 0, 8
local function mouse_world()
    local ok, ws = pcall(engine.get_window_size)
    if ok and ws and ws.w and ws.w > 0 then W, H = ws.w, ws.h end
    local m = input.get_mouse_position()
    local hh = HW * H / W
    local nx = (m.x / W) * 2 - 1
    local ny = (m.y / H) * 2 - 1
    return nx * HW, CAMY - ny * hh
end
local function update_cross(dt)
    local x, y = mouse_world()
    aimx, aimy = clamp(x, -HW + 0.5, HW - 0.5), clamp(y, 2.6, 21)
    local s = 0.55 + 0.08 * sin(S.t * 8)
    local g = 0.07
    place(cross[1], aimx - s, aimy, 0.5, 0, 0.45, g, g)
    place(cross[2], aimx + s, aimy, 0.5, 0, 0.45, g, g)
    place(cross[3], aimx, aimy - s, 0.5, 0, g, 0.45, g)
    place(cross[4], aimx, aimy + s, 0.5, 0, g, 0.45, g)
    place(cross[5], aimx, aimy, 0.5)
end
local function cross_visible(on) for i = 1, 5 do show(cross[i], on) end end

------------------------------------------------------------------ bases / firing
local function refresh_stock(b)
    for i = 1, 10 do if b.stock[i] then show(b.stock[i], b.alive and i <= b.ammo) end end
end

local function fire(bi, demo_tx, demo_ty)
    local b = bases[bi]
    local demo = demo_tx ~= nil
    if not demo and (not b or not b.alive or b.ammo <= 0) then sfx("empty"); return false end
    local ti = take(pool.ptrail, used.p)
    if not ti then return false end
    if not demo then b.ammo = b.ammo - 1; refresh_stock(b) end
    b.flash = 1
    local sx, sy = b.x, b.y
    local tx, ty = demo_tx or aimx, demo_ty or aimy
    local dx, dy = tx - sx, ty - sy
    local d = sqrt(dx * dx + dy * dy)
    local speed = (bi == 2) and 34 or 24
    shots[#shots + 1] = { i = ti, sx = sx, sy = sy, x = sx, y = sy, tx = tx, ty = ty, vx = dx / d * speed, vy = dy / d * speed, dist = d, trav = 0 }
    show(pool.ptrail[ti], true); show(pool.phead[ti], true); show(pool.pglow[ti], true)
    local m = pool.mark[ti]
    show(m[1], true); show(m[2], true)
    place(m[1], tx, ty, 0.2, 45, 0.6, 0.06, 0.06)
    place(m[2], tx, ty, 0.2, -45, 0.6, 0.06, 0.06)
    sparks(sx, sy + 0.2, 0.6, 0.9, 1.0, 25, 3.0, 0.5)
    burst({ position = vec3(sx, sy - 0.4, 0.3), velocity = vec3(0, 0.4, 0), color_start = vec4(0.2, 0.2, 0.23, 0.5),
        color_end = vec4(0.06, 0.06, 0.09, 0), count = 25, size_min = 0.25, size_max = 0.6, life_min = 0.8, life_max = 2.0,
        spawn_radius = 0.3, noise_strength = 1.6, drag = 2.0, gravity = vec3(0, 0.3, 0), texture_index = TEX.smoke })
    em_set(EM.exh[ti], { spawn_rate = 220 * SET:particle_scale(), position = vec3(sx, sy, 0.3) })
    em_set(EM.psmoke[ti], { spawn_rate = 75 * SET:particle_scale(), position = vec3(sx, sy, 0.2) })
    sfx("launch")
    return true
end

local function fire_nearest()
    local best, bd = nil, 1e9
    for bi, b in ipairs(bases) do
        if b.alive and b.ammo > 0 then
            local d = abs(b.x - aimx)
            if d < bd then best, bd = bi, d end
        end
    end
    if best then return fire(best) end
    sfx("empty"); return false
end

------------------------------------------------------------------ enemies
local function targets()
    local t = {}
    for _, c in ipairs(cities) do if c.alive then t[#t + 1] = { x = c.x, kind = "city", ref = c } end end
    for _, b in ipairs(bases) do if b.alive then t[#t + 1] = { x = b.x, kind = "base", ref = b } end end
    if #t == 0 then
        for _, c in ipairs(cities) do t[#t + 1] = { x = c.x, kind = "city", ref = c } end
    end
    return t
end

local function spawn_enemy(sx, sy, speed, can_split)
    local i = take(pool.etrail, used.e)
    if not i then return end
    local ts = targets()
    local tg = ts[rand(1, #ts)]
    local tx = tg.x + (rand() - 0.5) * 0.8
    local ty = (tg.kind == "base") and 1.4 or 0.6
    local dx, dy = tx - sx, ty - sy
    local d = sqrt(dx * dx + dy * dy)
    enemies[#enemies + 1] = {
        i = i, sx = sx, sy = sy, x = sx, y = sy, tx = tx, ty = ty, vx = dx / d * speed, vy = dy / d * speed,
        target = tg, split = can_split and (rand() < 0.35) and (6 + rand() * 7) or nil, speed = speed,
    }
    show(pool.etrail[i], true); show(pool.ehead[i], true); show(pool.ehalo[i], true); show(pool.eglow[i], true)
    set_seg(pool.etrail[i], sx, sy, sx, sy, 0.04); set_seg(pool.eglow[i], sx, sy, sx, sy, 0.2)
    local e = enemies[#enemies]; e.rot = rand() * 360; e.spin = (rand() - 0.5) * 200; e.scale = 1.1 + rand() * 0.6
    local ps = SET:particle_scale()
    em_set(EM.fire[i], { spawn_rate = 70 * ps, position = vec3(sx, sy, 0.1), velocity = vec3(-e.vx * 0.3, -e.vy * 0.3, 0) })
    em_set(EM.smoke[i], { spawn_rate = 30 * ps, position = vec3(sx, sy, -0.1) })
    em_set(EM.ember[i], { spawn_rate = 28 * ps, position = vec3(sx, sy, 0.2) })
end

local function kill_enemy(k, exploded)
    local e = enemies[k]
    show(pool.etrail[e.i], false); park(pool.ehead[e.i]); show(pool.ehalo[e.i], false); show(pool.eglow[e.i], false)
    em_set(EM.fire[e.i], { spawn_rate = 0 }); em_set(EM.smoke[e.i], { spawn_rate = 0 }); em_set(EM.ember[e.i], { spawn_rate = 0 })
    used.e[e.i] = nil
    table.remove(enemies, k)
end

local function destroy_city(c)
    if not c.alive then return end
    c.alive = false
    for _, p in ipairs(c.parts) do show(p.n, false) end
    if c.rubble then c.rubble:set_position(vec3(c.x, 0, 0)); c.rubble:set_enabled(true) end
    smoke(c.x, 0.3)
    sparks(c.x, 0.8, 1.0, 0.5, 0.2, 160, 11, 1.8)
    fireball(c.x, 1.0, 1.8, 80)
    dust_ring(c.x, 0)
    throw_debris(c.x, 1.0, 14, 9, true)
    local ps = SET:particle_scale()
    em_set(EM.cfire[c.i or 0], {})
    for ci, cc in ipairs(cities) do if cc == c then
        em_set(EM.cfire[ci], { spawn_rate = 70 * ps, position = vec3(c.x, 0.35, 0.3) })
        em_set(EM.csmoke[ci], { spawn_rate = 26 * ps, position = vec3(c.x, 0.9, -0.2) })
    end end
    flash_light(c.x, 1.5, 1.0, 0.4, 0.1, 80, 14, 2.0)
    S.shake = 0.6; S.flash = 1.0
    sfx("city")
end
local function restore_city(c)
    c.alive = true
    for _, p in ipairs(c.parts) do show(p.n, true) end
    park(c.rubble)
    for ci, cc in ipairs(cities) do if cc == c then
        em_set(EM.cfire[ci], { spawn_rate = 0 }); em_set(EM.csmoke[ci], { spawn_rate = 0 })
    end end
end
local function destroy_base(b)
    if not b.alive then return end
    b.alive = false; b.ammo = 0; refresh_stock(b)
    glow(b.ring, 0.6, 0.05, 0.02)
    smoke(b.x, 1.0); fireball(b.x, 1.2, 1.5, 60); throw_debris(b.x, 1.2, 10, 8, true)
    S.shake = 0.5; S.flash = 0.7
    sfx("city")
end

------------------------------------------------------------------ waves
local function begin_wave()
    S.wave = S.wave + 1
    S.mult = multiplier(S.wave)
    for _, b in ipairs(bases) do
        b.alive = true; b.ammo = 10; refresh_stock(b); glow(b.ring, 0.2, 1.6, 2.4)
    end
    -- award bonus cities
    while S.bonus_cities > 0 do
        local dead = {}
        for _, c in ipairs(cities) do if not c.alive then dead[#dead + 1] = c end end
        if #dead == 0 then break end
        restore_city(dead[rand(1, #dead)]); S.bonus_cities = S.bonus_cities - 1
    end
    local w = S.wave
    wave_plan = {
        total = min(10 + w * 2, 34), spawned = 0, timer = 1.5,
        speed = 1.5 + w * 0.32, salvo = min(2 + floor(w / 2), 6),
        gap = max(1.4, 4.2 - w * 0.25), flyers = (w >= 2) and min(1 + floor(w / 3), 4) or 0, flyer_timer = 6 + rand() * 4,
    }
    S.mode = "wavestart"; S.banner_t = 0
    sfx("alarm")
end

local function spawn_flyer()
    local dir = (rand() < 0.5) and 1 or -1
    local sat = rand() < 0.5
    flyer.active = true; flyer.dir = dir; flyer.x = -dir * (HW + 2); flyer.y = 12 + rand() * 4
    flyer.sat = sat; flyer.drop = 1.5 + rand() * 1.5; flyer.speed = 3 + S.wave * 0.2
    show(flyer.body, true); show(flyer.wing, true); show(flyer.eye, true)
end
local function kill_flyer(exploded)
    flyer.active = false
    show(flyer.body, false); show(flyer.wing, false); show(flyer.eye, false)
end

local function update_flyer(dt)
    if not flyer.active then return end
    flyer.x = flyer.x + flyer.dir * flyer.speed * dt
    local bob = sin(S.t * 3) * 0.2
    if flyer.sat then
        place(flyer.body, flyer.x, flyer.y + bob, 0, S.t * 90, 0.7, 0.7, 0.7)
        place(flyer.wing, flyer.x, flyer.y + bob, 0, 0, 2.4, 0.08, 0.5)
    else
        place(flyer.body, flyer.x, flyer.y + bob, 0, 0, 1.6, 0.35, 0.5)
        place(flyer.wing, flyer.x - flyer.dir * 0.2, flyer.y + bob, 0, flyer.dir * 25, 0.6, 0.12, 1.6)
    end
    place(flyer.eye, flyer.x + flyer.dir * 0.6, flyer.y + bob, 0.3)
    glow(flyer.eye, 6 + 4 * sin(S.t * 12), 1.5, 0.4)
    flyer.drop = flyer.drop - dt
    if flyer.drop <= 0 and wave_plan.spawned < wave_plan.total then
        flyer.drop = 2.0 + rand() * 2
        spawn_enemy(flyer.x, flyer.y - 0.5, wave_plan.speed * 0.9, false)
        wave_plan.spawned = wave_plan.spawned + 1
    end
    if abs(flyer.x) > HW + 3 then kill_flyer(false) end
end

local function add_score(p)
    S.score = S.score + p * S.mult
    if S.score >= S.next_bonus then
        S.next_bonus = S.next_bonus + 10000; S.bonus_cities = S.bonus_cities + 1
        sfx("bonus"); S.bonus_flash = 2.5
    end
end

------------------------------------------------------------------ update loops
local function update_shots(dt)
    local k = 1
    while k <= #shots do
        local s = shots[k]
        local step = sqrt(s.vx * s.vx + s.vy * s.vy) * dt
        s.trav = s.trav + step
        if s.trav >= s.dist then
            show(pool.ptrail[s.i], false); park(pool.phead[s.i]); show(pool.pglow[s.i], false)
            local m = pool.mark[s.i]; show(m[1], false); show(m[2], false)
            em_set(EM.exh[s.i], { spawn_rate = 0 }); em_set(EM.psmoke[s.i], { spawn_rate = 0 })
            used.p[s.i] = nil
            spawn_boom(s.tx, s.ty, "player", 2.6)
            table.remove(shots, k)
        else
            s.x = s.x + s.vx * dt; s.y = s.y + s.vy * dt
            set_seg(pool.ptrail[s.i], s.sx, s.sy, s.x, s.y, 0.03); set_seg(pool.pglow[s.i], s.sx, s.sy, s.x, s.y, 0.14)
            local ang = math.deg(atan2(s.vy, s.vx)) - 90
            local hn = pool.phead[s.i]
            if hn then hn:set_enabled(true); hn:set_transform(vec3(s.x, s.y, 0.3), vec3(0, 0, ang), vec3(1.5, 1.5, 1.5)) end
            local sp = sqrt(s.vx * s.vx + s.vy * s.vy)
            local tx, ty = s.x - s.vx / sp * 0.5, s.y - s.vy / sp * 0.5
            em_set(EM.exh[s.i], { position = vec3(tx, ty, 0.3), velocity = vec3(-s.vx * 0.12, -s.vy * 0.12, 0) })
            em_set(EM.psmoke[s.i], { position = vec3(tx, ty, 0.2) })
            local blink = (floor(S.t * 10) % 2 == 0) and 3.5 or 1.0
            local m = pool.mark[s.i]; glow(m[1], 0.3 * blink, 2.5 * blink, 3.5 * blink); glow(m[2], 0.3 * blink, 2.5 * blink, 3.5 * blink)
            k = k + 1
        end
    end
end

local function update_enemies(dt)
    local k = 1
    while k <= #enemies do
        local e = enemies[k]
        e.x = e.x + e.vx * dt; e.y = e.y + e.vy * dt
        local hit = false
        -- explosion collision
        for _, b in ipairs(booms) do
            if b.r > 0.1 then
                local dx, dy = e.x - b.x, e.y - b.y
                if dx * dx + dy * dy < b.r * b.r then hit = true; break end
            end
        end
        if hit then
            add_score(25)
            spawn_boom(e.x, e.y, "chain", 2.2)
            kill_enemy(k)
        elseif e.y <= e.ty then
            local tg = e.target
            spawn_boom(e.x, e.y + 0.3, "ground", 2.0)
            if tg.kind == "city" then destroy_city(tg.ref) elseif tg.kind == "base" then destroy_base(tg.ref) end
            -- splash: missiles landing near an un-targeted city still kill it
            kill_enemy(k)
        else
            if e.split and e.y < e.sy - e.split and e.y > 7 then
                e.split = nil
                local n = rand(1, 3)
                for j = 1, n do
                    if wave_plan.spawned < wave_plan.total + 6 then spawn_enemy(e.x, e.y, e.speed, false) end
                end
            end
            set_seg(pool.etrail[e.i], e.sx, e.sy, e.x, e.y, 0.035); set_seg(pool.eglow[e.i], e.sx, e.sy, e.x, e.y, 0.18)
            e.rot = (e.rot or 0) + (e.spin or 90) * dt
            local hn = pool.ehead[e.i]
            if hn then hn:set_enabled(true); hn:set_transform(vec3(e.x, e.y, 0.1), vec3(e.rot, e.rot * 0.6, e.rot * 0.3), vec3(e.scale or 1, e.scale or 1, e.scale or 1)) end
            local pu = (0.8 + 0.25 * sin(S.t * 23 + e.i)) * (e.scale or 1)
            place(pool.ehalo[e.i], e.x, e.y, -0.1, 0, pu, pu, pu)
            local sp = sqrt(e.vx * e.vx + e.vy * e.vy)
            local bx, by = e.x - e.vx / sp * 0.25, e.y - e.vy / sp * 0.25
            em_set(EM.fire[e.i], { position = vec3(bx, by, 0.15) })
            em_set(EM.smoke[e.i], { position = vec3(bx - e.vx / sp * 0.3, by - e.vy / sp * 0.3, -0.1) })
            em_set(EM.ember[e.i], { position = vec3(bx, by, 0.2) })
            k = k + 1
        end
    end
    if flyer.active then
        for _, b in ipairs(booms) do
            local dx, dy = flyer.x - b.x, flyer.y - b.y
            if b.r > 0.1 and dx * dx + dy * dy < (b.r + 0.6) ^ 2 then
                add_score(100); spawn_boom(flyer.x, flyer.y, "chain", 2.8)
                sparks(flyer.x, flyer.y, 1, 0.3, 0.9, 120, 10, 1.4)
                kill_flyer(true); break
            end
        end
    end
end

local function update_booms(dt)
    local k = 1
    while k <= #booms do
        local b = booms[k]
        b.t = b.t + dt
        local grow, hold, shrink = 0.55, 0.35, 0.75
        local r
        if b.t < grow then r = b.maxr * ease_out(b.t / grow)
        elseif b.t < grow + hold then r = b.maxr
        elseif b.t < grow + hold + shrink then r = b.maxr * (1 - (b.t - grow - hold) / shrink)
        else r = -1 end
        if r < 0 then
            show(pool.boom[b.i], false); show(pool.halo[b.i], false); show(pool.ring[b.i], false); used.b[b.i] = nil
            table.remove(booms, k)
        else
            b.r = r
            local n = pool.boom[b.i]
            place(n, b.x, b.y, 0, b.t * 40, r, r, r)
            -- classic colour flashing, modernised: hot white core cycling through neon hues
            local life = b.t / (grow + hold + shrink)
            -- blackbody-ish fireball: white-hot -> orange -> deep red, with flicker
            local fl = 0.88 + 0.12 * sin(S.t * 47 + b.i * 3.1)
            local hr, hg, hb
            if life < 0.25 then local q = life / 0.25; hr, hg, hb = 1.0, lerp(0.95, 0.62, q), lerp(0.8, 0.22, q)
            elseif life < 0.65 then local q = (life - 0.25) / 0.4; hr, hg, hb = 1.0, lerp(0.62, 0.32, q), lerp(0.22, 0.06, q)
            else local q = (life - 0.65) / 0.35; hr, hg, hb = lerp(1.0, 0.45, q), lerp(0.32, 0.08, q), lerp(0.06, 0.02, q) end
            if b.owner == "player" and life < 0.3 then hb = hb + 0.25 * (1 - life / 0.3); hg = hg + 0.08 end
            hr, hg, hb = hr * fl * 1.5, hg * fl * 1.5, hb * fl * 1.5
            place(n, b.x, b.y, 0, b.t * 40, r * 0.82, r * 0.82, r * 0.82)
            glow(n, hr, hg, hb)
            local hn = pool.halo[b.i]
            local hrr = r * 1.25
            place(hn, b.x, b.y, -0.3, 0, hrr, hrr, hrr)
            material.set(hn, "base_color", vec4(hr / 1.5, hg / 1.5, hb / 1.5, 0.35 * (1 - life * 0.8)))
            material.set(hn, "emissive", vec3(hr * 0.6, hg * 0.6, hb * 0.6))
            local rr = b.maxr * (0.3 + 1.8 * ease_out(min(1, b.t / 0.6)))
            local fade = max(0, 1 - b.t / 0.6)
            pool.ring[b.i]:set_transform(vec3(b.x, b.y, 1.2), vec3(90, 0, 0), vec3(rr, rr, rr))
            glow(pool.ring[b.i], 0.9 * fade, 0.75 * fade, 0.6 * fade)
            k = k + 1
        end
    end
    -- lights
    if booms.lights then
        for i = 1, 6 do
            local L = booms.lights[i]
            if L then
                L.t = L.t + dt
                local f = 1 - L.t / L.life
                if f <= 0 then
                    booms.lights[i] = nil
                    set_light(i, 0, -50, 0, 1, 1, 1, 0.0, 1.0)
                else
                    set_light(i, L.x, L.y, 2.0, L.r, L.g, L.b, L.i * f * f, L.rad)
                end
            end
        end
    end
end

local function update_cities(dt)
    for ci, c in ipairs(cities) do
        if c.alive and c.beacon then
            local on = (floor(S.t * 1.5 + ci * 0.37) % 2 == 0)
            glow(c.beacon, on and 5 or 0.3, on and 0.4 or 0.02, on and 0.25 or 0.02)
        end
    end
    -- city glow lights (3 lights for 6 cities: pairs)
    for j = 1, 3 do
        local a, b = cities[(j - 1) * 2 + 1], cities[(j - 1) * 2 + 2]
        local n = (a.alive and 1 or 0) + (b.alive and 1 or 0)
        local x = (a.x + b.x) * 0.5
        local col = a.alive and a.col or b.col
        set_light(6 + j, x, 3.0, 3.0, col[1] / 2, col[2] / 2, col[3] / 2, 5.0 * n, 8.0)
    end
    for _, b in ipairs(bases) do
        if b.flash > 0 then
            b.flash = max(0, b.flash - dt * 4)
            if b.alive then glow(b.ring, 0.2 + b.flash * 4, 1.6 + b.flash * 4, 2.4 + b.flash * 3) end
        end
    end
end

------------------------------------------------------------------ input
local function key_edge(k)
    local d = false
    local ok, v = pcall(input.is_key_down_raw or input.is_key_pressed, k)  -- raw: not swallowed by runtime UI
    d = ok and v
    local was = keys_prev[k]; keys_prev[k] = d
    return d and not was
end
local rmb_prev = false
local function mouse_edge()
    local d = input.is_left_mouse_down()
    local e = d and not mouse_prev
    mouse_prev = d
    return e
end
local function rmouse_edge()
    local ok, d = pcall(input.is_right_mouse_down); d = ok and d
    local e = d and not rmb_prev
    rmb_prev = d
    return e
end

------------------------------------------------------------------ screens
local function save_hi()
    pcall(fs.write, PROJECT .. "highscore.txt", tostring(S.hi))
end
local function load_hi()
    local ok, s = pcall(fs.read, PROJECT .. "highscore.txt")
    if ok and s then S.hi = tonumber(s) or 0 end
end

local function clear_actors()
    for k = #enemies, 1, -1 do kill_enemy(k) end
    for _, s in ipairs(shots) do
        show(pool.ptrail[s.i], false); park(pool.phead[s.i]); show(pool.pglow[s.i], false)
        em_set(EM.exh[s.i], { spawn_rate = 0 }); em_set(EM.psmoke[s.i], { spawn_rate = 0 })
        show(pool.mark[s.i][1], false); show(pool.mark[s.i][2], false); used.p[s.i] = nil
    end
    shots = {}
    kill_flyer(false)
end

local function new_game()
    clear_actors()
    S.score = 0; S.wave = 0; S.next_bonus = 10000; S.bonus_cities = 0
    for _, c in ipairs(cities) do restore_city(c) end
    hud_hide("menu_")
    begin_wave()
end

local cam_intro = { y = CAMY, z = CAMZ }
local function set_cam(x, y, z, pitch)
    local ok, cam = pcall(get_camera)
    if ok and cam then
        pcall(function() cam:set_position(vec3(x, y, z)) end)
        pcall(function() cam:set_euler(vec3(pitch or 0, pi, 0)) end)
    end
end

local function title_screen()
    S.mode = "title"; S.t_title = 0
    local sw, sh = surface()
    P("menu_bg", sw * 0.2, sh * 0.16, sw * 0.6, sh * 0.6, { 0.03, 0.0, 0.09, 0.62 }, { 0.6, 0.2, 1.0, 0.9 }, 20)
    T("menu_t1", sw * 0.2, sh * 0.2, sw * 0.6, sh * 0.12, "MISSILE  COMMAND", 3.4, { 1.0, 0.3, 0.45, 1 }, "center", 21)
    T("menu_t2", sw * 0.2, sh * 0.31, sw * 0.6, sh * 0.05, "- NEON NIGHT -", 1.4, { 0.4, 0.9, 1.0, 1 }, "center", 21)
    T("menu_c1", sw * 0.2, sh * 0.42, sw * 0.6, sh * 0.04, "MOUSE: aim    |    LEFT CLICK / SPACE: fire from nearest base", 1.0, { 0.85, 0.8, 1.0, 1 }, "center", 21)
    T("menu_c2", sw * 0.2, sh * 0.47, sw * 0.6, sh * 0.04, "A / S / D  (1 2 3, right-click = centre): fire a specific base    |    P: pause    ESC: menu", 1.0, { 0.85, 0.8, 1.0, 1 }, "center", 21)
    T("menu_c3", sw * 0.2, sh * 0.52, sw * 0.6, sh * 0.04, "Bonus city every 10,000 points  -  defend all six cities", 1.0, { 1.0, 0.8, 0.4, 1 }, "center", 21)
    T("menu_hi", sw * 0.2, sh * 0.58, sw * 0.6, sh * 0.04, string.format("HIGH SCORE  %07d", S.hi), 1.2, { 0.3, 0.9, 1.0, 1 }, "center", 21)
end

-- mouse-clickable menu buttons (runtime_ui quads; state read back with get_state)
local btn_hover = {}
local ui_hovered = false
local function button(id, x, y, w, h, label, accent, z)
    hud_ids[id] = true
    local hov = btn_hover[id]
    accent = accent or { 0.4, 0.9, 1.0 }
    runtime_ui.set_quad("hud", id, { x = x, y = y, w = w, h = h, z = z or 24, style = "text", label = label,
        fill = hov and { accent[1] * 0.35, accent[2] * 0.35, accent[3] * 0.35, 0.95 } or { 0.05, 0.02, 0.12, 0.85 },
        border = { accent[1], accent[2], accent[3], hov and 1.0 or 0.7 }, text_color = hov and { 1, 1, 1, 1 } or { accent[1], accent[2], accent[3], 1 },
        font_scale = 1.25, align_h = "center", align_v = "middle", corner_radius = 10, visible = true })
    local ok, st = pcall(runtime_ui.get_state, "hud", id)
    local h2 = ok and st and st.hovered or false
    if h2 and not hov then sfx("tick") end
    btn_hover[id] = h2
    if h2 then ui_hovered = true end
    return ok and st and st.clicked or false
end
local want_settings = false
local function settings_button(show) end
local function settings_button_clicked() local w = want_settings; want_settings = false; return w end

------------------------------------------------------------------ main
local demo_t = 0
local function init()
    pe_log("[MC] init")
    pcall(function() math.randomseed(floor((engine.get_metrics().delta_ms or 1) * 100000)) end)
    build_sky_and_post()
    for k, f in pairs({ spark = "Textures/spark.png", smoke = "Textures/smoke.png", fire = "Textures/fire.png" }) do
        local ok, idx = pcall(particles.load_texture, f); if ok and idx then TEX[k] = idx end
    end
    SET:apply()
    build_ground()
    build_cities()
    build_bases()
    build_pools()
    load_hi()
    pcall(particles.add_emitter, { name = "embers", position = vec3(0, 0.5, 1.0), velocity = vec3(0, 0.7, 0),
        color_start = vec4(1.0, 0.45, 0.2, 0.8), color_end = vec4(0.6, 0.1, 0.5, 0.0), count = floor(260 * SET:particle_scale()), spawn_rate = 40 * SET:particle_scale(),
        size_min = 0.03, size_max = 0.08, life_min = 3, life_max = 7, spawn_radius = 20, noise_strength = 0.5, drag = 0.1, gravity = vec3(0, 0.15, 0) })
    pcall(runtime_ui.show, "hud")
    pcall(runtime_ui.set_screen_overlay, "hud", true)
    -- engine tween: dolly in from a high wide shot
    pcall(tween.to, vec3(0, 26, 55), vec3(0, CAMY, CAMZ), 2.6, function(v) cam_intro.y = v.y; cam_intro.z = v.z end, { ease = "smooth" })
    cam_intro.y, cam_intro.z = 26, 55
    title_screen()
end

local function update_title(dt)
    S.t_title = (S.t_title or 0) + dt
    local sw, sh = surface()
    local a = 0.55 + 0.45 * sin(S.t * 4)
    local bw, bh = sw * 0.17, sh * 0.065
    local go = button("menu_b_start", sw * 0.5 - bw - 10, sh * 0.65, bw, bh, "START GAME", { 1.0, 0.45, 0.5 })
    if button("menu_b_set", sw * 0.5 + 10, sh * 0.65, bw, bh, "SETTINGS", { 0.4, 0.9, 1.0 }) then want_settings = true end
    T("menu_start", sw * 0.2, sh * 0.725, sw * 0.6, sh * 0.04, "ENTER: start    O: settings", 1.0, { 1, 1, 1, a * 0.7 }, "center", 21)
    -- attract mode: missiles rain and get intercepted automatically
    demo_t = demo_t - dt
    if demo_t <= 0 then
        demo_t = 0.8 + rand() * 0.8
        wave_plan = wave_plan or { total = 999, spawned = 0, speed = 3.0 }
        spawn_enemy(-HW + rand() * HW * 2, 22.5, 3.5, false)
    end
    for _, e in ipairs(enemies) do
        if e.y < 9 and not e.demo_fired then
            e.demo_fired = true
            local bi = (e.x < -7) and 1 or ((e.x > 7) and 3 or 2)
            fire(bi, e.x + e.vx * 0.9, e.y + e.vy * 0.9)
        end
    end
    -- in attract mode cities are immortal
    for _, e in ipairs(enemies) do e.target = { kind = "none" } end
    mouse_edge()
    if go or key_edge("Return") or key_edge("Space") then
        if S.t_title > 0.5 then new_game() end
    end
end

local function enemies_remaining()
    return #enemies > 0 or flyer.active or (wave_plan and wave_plan.spawned < wave_plan.total)
end

local function start_tally()
    S.mode = "tally"; S.tally = { phase = 0, t = 0.8, ammo_i = 0, city_i = 0, ammo_pts = 0, city_pts = 0, bases = {} }
    for _, b in ipairs(bases) do S.tally.bases[#S.tally.bases + 1] = b.ammo end
end

local function update_tally(dt)
    local tl = S.tally
    local sw, sh = surface()
    P("menu_tbg", sw * 0.3, sh * 0.3, sw * 0.4, sh * 0.32, { 0.03, 0.0, 0.09, 0.6 }, { 0.3, 0.8, 1.0, 0.9 }, 20)
    T("menu_tt", sw * 0.3, sh * 0.32, sw * 0.4, sh * 0.06, "BONUS POINTS", 2.0, { 0.4, 0.9, 1.0, 1 }, "center", 21)
    T("menu_ta", sw * 0.3, sh * 0.41, sw * 0.4, sh * 0.06, string.format("MISSILES  %d  x %d  =  %d", tl.ammo_i, 5 * S.mult, tl.ammo_pts), 1.4, { 0.8, 0.9, 1.0, 1 }, "center", 21)
    T("menu_tc", sw * 0.3, sh * 0.48, sw * 0.4, sh * 0.06, string.format("CITIES  %d  x %d  =  %d", tl.city_i, 100 * S.mult, tl.city_pts), 1.4, { 1.0, 0.85, 0.4, 1 }, "center", 21)
    tl.t = tl.t - dt
    if tl.t > 0 then return end
    if tl.phase == 0 then
        -- count remaining missiles one at a time
        for _, b in ipairs(bases) do
            if b.ammo > 0 then
                b.ammo = b.ammo - 1; refresh_stock(b)
                tl.ammo_i = tl.ammo_i + 1; tl.ammo_pts = tl.ammo_pts + 5 * S.mult; add_score(5)
                sfx("tick"); tl.t = 0.07; return
            end
        end
        tl.phase = 1; tl.t = 0.5; tl.ci = 0
    elseif tl.phase == 1 then
        tl.ci = tl.ci + 1
        local c = cities[tl.ci]
        if c then
            if c.alive then
                tl.city_i = tl.city_i + 1; tl.city_pts = tl.city_pts + 100 * S.mult; add_score(100)
                sparks(c.x, 2.2, c.col[1] / 2.4, c.col[2] / 2.4, c.col[3] / 2.4, 40, 3, 0.8)
                sfx("tick"); tl.t = 0.28
            else tl.t = 0.05 end
        else
            tl.phase = 2; tl.t = 1.6
        end
    elseif tl.phase == 2 then
        hud_hide("menu_")
        local any = false
        for _, c in ipairs(cities) do if c.alive then any = true end end
        if not any and S.bonus_cities <= 0 then
            S.mode = "gameover"; S.go_t = 0; sfx("gameover")
            if S.score > S.hi then S.hi = S.score; save_hi() end
        else
            begin_wave()
        end
    end
end

local function update_play(dt)
    local wp = wave_plan
    wp.timer = wp.timer - dt
    if wp.timer <= 0 and wp.spawned < wp.total then
        wp.timer = wp.gap * (0.7 + rand() * 0.6)
        local n = min(wp.salvo, wp.total - wp.spawned)
        for j = 1, n do
            spawn_enemy(-HW + 1 + rand() * (HW * 2 - 2), 22.5, wp.speed * (0.85 + rand() * 0.3), S.wave >= 2)
            wp.spawned = wp.spawned + 1
        end
    end
    if wp.flyers > 0 then
        wp.flyer_timer = wp.flyer_timer - dt
        if wp.flyer_timer <= 0 and not flyer.active then
            wp.flyers = wp.flyers - 1; wp.flyer_timer = 8 + rand() * 6; spawn_flyer()
        end
    end
    update_flyer(dt)
    -- on-screen pause button (top bar)
    local sw, sh = surface()
    if button("pbtn", sw * 0.62, sh * 0.012, sw * 0.1, sh * 0.05, "II PAUSE", { 0.85, 0.8, 1.0 }, 6) then S.paused = true end
    -- fire controls (a click on a UI button never fires a missile)
    local me = mouse_edge()
    if (me and not ui_hovered) or key_edge("Space") then fire_nearest() end
    if key_edge("A") or key_edge("1") or key_edge("Q") then fire(1) end
    if key_edge("S") or key_edge("2") or key_edge("W") or rmouse_edge() then fire(2) end
    if key_edge("D") or key_edge("3") or key_edge("E") then fire(3) end
    -- all cities dead: end after the sky clears
    if not enemies_remaining() and #shots == 0 and #booms == 0 then start_tally() end
end

local function update_wavestart(dt)
    S.banner_t = S.banner_t + dt
    local sw, sh = surface()
    local a = min(1, S.banner_t * 3) * min(1, (2.6 - S.banner_t) * 2)
    T("menu_w1", 0, sh * 0.34, sw, sh * 0.1, string.format("WAVE  %d", S.wave), 3.2, { 1.0, 0.85, 0.3, a }, "center", 21)
    T("menu_w2", 0, sh * 0.45, sw, sh * 0.06, string.format("%d X  POINTS", S.mult), 1.8, { 0.4, 0.9, 1.0, a }, "center", 21)
    T("menu_w3", 0, sh * 0.52, sw, sh * 0.05, "DEFEND  CITIES", 1.4, { 1.0, 0.35, 0.5, a * (0.6 + 0.4 * sin(S.t * 10)) }, "center", 21)
    -- you can already fire during the banner
    if (mouse_edge() and not ui_hovered) or key_edge("Space") then fire_nearest() end
    if S.banner_t > 2.6 then hud_hide("menu_"); S.mode = "play" end
end

local function update_gameover(dt)
    S.go_t = S.go_t + dt
    local sw, sh = surface()
    if S.go_t < 2.5 and rand() < dt * 3 then spawn_boom(-HW + 2 + rand() * (HW * 2 - 4), 3 + rand() * 6, "chain", 1.8 + rand() * 1.2) end
    local a = min(1, S.go_t)
    P("menu_gobg", 0, sh * 0.3, sw, sh * 0.32, { 0.12, 0.0, 0.03, 0.55 * a }, { 1, 0.2, 0.3, 0 }, 20)
    T("menu_go", 0, sh * 0.33, sw, sh * 0.14, "THE  END", 4.4, { 1.0, 0.25, 0.3, a }, "center", 21)
    T("menu_go2", 0, sh * 0.47, sw, sh * 0.05, string.format("FINAL SCORE  %07d    WAVE %d", S.score, S.wave), 1.5, { 1, 0.9, 0.6, a }, "center", 21)
    if S.go_t > 2.5 then
        local bw, bh = sw * 0.17, sh * 0.065
        local again = button("menu_b_again", sw * 0.5 - bw - 10, sh * 0.55, bw, bh, "PLAY AGAIN", { 1.0, 0.45, 0.5 })
        local totitle = button("menu_b_title", sw * 0.5 + 10, sh * 0.55, bw, bh, "TITLE SCREEN", { 0.4, 0.9, 1.0 })
        mouse_edge()
        if again then hud_hide("menu_"); new_game()
        elseif totitle or key_edge("Return") then
            hud_hide("menu_")
            for _, c in ipairs(cities) do restore_city(c) end
            for _, b in ipairs(bases) do b.alive = true; b.ammo = 10; refresh_stock(b); glow(b.ring, 0.2, 1.6, 2.4) end
            S.score = 0; S.wave = 0; S.mult = 1
            title_screen()
        end
    else mouse_edge() end
end

local frame_no = 0
local function update(dt)
    if dt > 0.1 then dt = 0.1 end
    S.t = S.t + dt
    frame_no = frame_no + 1
    if frame_no == 3 then for _, fn in ipairs(deferred_mats) do pcall(fn) end end
    -- edges are sampled every frame (even while settings is open) so the ESC that closes it is not re-seen
    local k_p, k_esc, k_o, k_tab = key_edge("P"), key_edge("Escape"), key_edge("O"), key_edge("Tab")
    local set_open = SET:update(dt)
    ui_hovered = false
    local can_set = (S.mode == "title" or S.paused)
    if not set_open and can_set and (k_o or k_tab or settings_button_clicked()) then
        sfx("tick"); hud_hide("menu_"); settings_button(false)
        SET:open(function() if S.mode == "title" then title_screen() end end)
        set_open = true
    end
    settings_button(can_set and not set_open)
    if set_open then k_p, k_esc = false, false; mouse_edge() end
    if k_p and (S.mode == "play" or S.mode == "wavestart") then
        S.paused = not S.paused
        if not S.paused then hud_hide("menu_p") end
    end
    if S.quit_req then S.quit_req = false; k_esc = true end
    if k_esc and S.mode ~= "title" then
        clear_actors(); hud_hide("menu_"); S.paused = false
        if S.score > S.hi then S.hi = S.score; save_hi() end
        S.score = 0; S.wave = 0; S.mult = 1
        for _, c in ipairs(cities) do restore_city(c) end
        title_screen()
    end
    if S.paused then
        local sw, sh = surface()
        if not set_open then
            P("menu_pbg", sw * 0.35, sh * 0.26, sw * 0.3, sh * 0.5, { 0.03, 0.0, 0.09, 0.7 }, { 0.4, 0.9, 1.0, 0.9 }, 20)
            T("menu_pause", sw * 0.35, sh * 0.28, sw * 0.3, sh * 0.1, "PAUSED", 2.6, { 0.4, 0.9, 1.0, 0.7 + 0.3 * sin(S.t * 3) }, "center", 21)
            local bw, bh = sw * 0.2, sh * 0.065
            if button("menu_b_resume", sw * 0.4, sh * 0.41, bw, bh, "RESUME", { 0.5, 1.0, 0.6 }) then S.paused = false; hud_hide("menu_") end
            if button("menu_b_pset", sw * 0.4, sh * 0.49, bw, bh, "SETTINGS", { 0.4, 0.9, 1.0 }) then want_settings = true end
            if button("menu_b_quit", sw * 0.4, sh * 0.57, bw, bh, "QUIT TO TITLE", { 1.0, 0.45, 0.5 }) then S.quit_req = true end
            T("menu_phint", sw * 0.35, sh * 0.66, sw * 0.3, sh * 0.05, "P: resume   O: settings   ESC: title", 0.95, { 0.85, 0.8, 1.0, 0.8 }, "center", 21)
        end
        return
    end
    -- camera: intro dolly + impact shake
    S.shake = max(0, S.shake - dt * 1.2)
    local sk = S.shake * SET:shake_scale()
    local sx = (rand() - 0.5) * sk * 0.6
    local sy = (rand() - 0.5) * sk * 0.6
    local pitch = (cam_intro.y - CAMY) * -0.012
    set_cam(sx, cam_intro.y + sy, cam_intro.z, pitch)

    update_cross(dt)
    cross_visible(S.mode == "play" or S.mode == "wavestart")
    if S.mode == "title" then if not set_open then update_title(dt) end
    elseif S.mode == "wavestart" then update_wavestart(dt)
    elseif S.mode == "play" then update_play(dt)
    elseif S.mode == "tally" then update_tally(dt)
    elseif S.mode == "gameover" then update_gameover(dt) end
    update_shots(dt)
    update_enemies(dt)
    update_booms(dt)
    update_cities(dt)
    update_debris(dt)
    draw_fx(dt)
    if S.bonus_flash and S.bonus_flash > 0 then
        S.bonus_flash = S.bonus_flash - dt
        local sw, sh = surface()
        T("bonus_msg", 0, sh * 0.82, sw, sh * 0.06, "BONUS CITY!", 2.0, { 0.4, 1.0, 0.6, min(1, S.bonus_flash) }, "center", 21)
        if S.bonus_flash <= 0 then hud_hide("bonus_") end
    end
    if S.mode ~= "play" then hud_hide("pbtn") end
    if S.mode ~= "title" then draw_hud() else hud_hide("score"); hud_hide("hi"); hud_hide("wave"); hud_hide("ammo"); hud_hide("top_") end
end

-- debug/automation hook for MCP screenshots
_G.MC = { S = S, fire = fire, new_game = new_game, aim = function(x, y) aimx, aimy = x, y end,
    spawn = function(x, y, s) spawn_enemy(x, y, s or 3, false) end, boom = spawn_boom,
    city = destroy_city, tally = function() wave_plan.spawned = wave_plan.total; clear_actors(); start_tally() end, over = function() for _, c in ipairs(cities) do destroy_city(c) end; hud_hide('menu_'); S.mode = 'gameover'; S.go_t = 0 end, cities = cities, title = title_screen, set_mode = function(m) S.mode = m end, pause = function(p) S.paused = p end }

hooks { init = init, update = update }
