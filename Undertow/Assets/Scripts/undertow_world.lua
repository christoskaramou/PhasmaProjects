-- Undertow world: draws the harbour the way .concepts/next/undertow/LOOKPLAN.md says.
--   sky        one unlit quad facing the camera (the camera never turns), Textures/sky_view.png; storm.hdr for IBL
--   far layer  unlit alpha cards every FAR.w along x (far_layer.png), the lighthouse beam card on each
--   set pieces cooked meshes drawn unlit with their Cycles-baked texture (emissive), pooled and recycled
--   sea        pooled swell tiles slid along x by SEA_C * t, vertex colours (troughs / backs / foam), a looping
--              ripple normal-map flipbook; beyond them the far sea is painted into the sky quad (it never changes)
--   live       the float (alpha glass, inner glow, core, rope net), chain links, trail ribbon, point lights,
--              particles for rain (3 depth bands), spray and lamp halos
-- Blender axes everywhere in the logic; E() converts to engine (x, z, -y).
return function(D, Sea, Course)
local W = {}
local floor, min, max, abs, sin, cos, sqrt = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt
local deg, rad, atan2 = math.deg, math.rad, math.atan2 or math.atan
local function v3(x, y, z) return vec3(x, y, z) end
local function E(x, y, z) return x, z, -y end
W.E = E
local cam

------------------------------------------------------------------ materials (template clones replay writes: engine quirk)
local mat_q = {}
local function mq(f) f(); mat_q[#mat_q + 1] = { f = f, c = 0 } end
local function flush_mats()
    for i = #mat_q, 1, -1 do
        local q = mat_q[i]
        q.c = q.c + 1
        if q.c == 2 or q.c == 6 or q.c == 20 then pcall(q.f) end
        if q.c >= 20 then table.remove(mat_q, i) end
    end
end
local function mat(n, base, metal, rough, emis)
    mq(function()
        pcall(material.set, n, "base_color", vec4(base[1], base[2], base[3], base[4] or 1))
        pcall(material.set, n, "emissive", v3(emis and emis[1] or 0, emis and emis[2] or 0, emis and emis[3] or 0))
        pcall(material.set, n, "metallic", metal or 0)
        pcall(material.set, n, "roughness", rough or 0.5)
    end)
end
local function tex(n, slot, path) mq(function() pcall(material.set_texture, n, slot, path) end) end
local function render_type(n, t) mq(function() pcall(material.set_render_type, n, t) end) end
W.flush_mats = flush_mats

local LOOK = {}
-- Baked pieces: emissive only. Metallic 1 on a black base makes F0 black, so no light (the strong glitter light
-- gave the breakwater rocks bright rims at metallic 0's 4% specular) and no IBL adds to the bake.
local function unlit(png, k) return function(n)
    local g = type(k) == "function" and k() or k or 1
    mat(n, { 0, 0, 0, 1 }, 1, 1, { g, g, g }); tex(n, "emissive", "Textures/" .. png)
end end
for _, v in ipairs({ "buoy_red_lit", "buoy_red_unlit", "buoy_white_lit", "buoy_white_unlit", "pier_lit", "pier_unlit" }) do
    LOOK[v] = unlit(v .. ".png")
end
W.BOAT_EMIS = 0.8      -- the moored boats' bake brightness (the target's hull sits darker, in the dusk shadow)
LOOK.boat = unlit("boat.png", function() return W.BOAT_EMIS end)
LOOK.bw = unlit("bw.png")
LOOK.bw_gap = unlit("bw_gap.png")
LOOK.sky = unlit("sky_view.png")
LOOK.far_card = function(n)
    render_type(n, "alpha_blend")
    mat(n, { 0, 0, 0, 1 }, 1, 1, { 1, 1, 1 })
    tex(n, "base_color", "Textures/far_layer.png")
    tex(n, "emissive", "Textures/far_layer.png")
end
-- Engine-side gain on the shared vertex colours: the engine's sky reflection on the water is weaker than Cycles'
-- (IBL 1.0 -> 2.6 moved the near-sea mean by 6 levels), so the diffuse base carries more of the grey-green.
W.SEA_COLOUR = { 1.12, 1.18, 1.23 }   -- (21:5x x1.1: the brighter band IBL carries the dashes; 1.43.. painted the swell backs teal)   -- x1.4 (18:5x): the ripple maps now tilt the mirror off the bright horizon band
                                      -- (dark baseline, short bright streaks), so the diffuse base carries the water's tone   -- was 1.43/1.65/1.76: lamp light on that base painted swell faces teal; IBL carries more
W.SEA_ROUGH = 0.85      -- x sea_rough.png (22:3x live: 0.6-1.0 compared; 1.0 smeared the dashes, 0.8 left rings)
W.RIPPLE_PREFIX = "sea_normal_"    -- the ripple flipbook's files (Textures/<prefix>NN.png)
-- Sky glitter under the beam (the engine cannot reflect the beam card). Above ~3 its grazing Fresnel (Lighting.hlsl
-- DirectLight) puts bright rims on the baked breakwater rocks even at metallic 1 / black base: 3 is the compromise.
W.GLITTER = { intensity = 0.0, colour = { 1.0, 0.82, 0.6 } }   -- (22:5x: off; on the rough near swell faces it made the white patches, live L0-L5)
-- sea_rough.png: roughness by depth (G), the slope of the ripples too fine to draw there (tools/uw_ripple.world_maps);
-- the factor W.SEA_ROUGH multiplies it (1 = as baked).
LOOK.sea_tile = function(n)
    mat(n, { W.SEA_COLOUR[1], W.SEA_COLOUR[2], W.SEA_COLOUR[3], 1 }, 0, W.SEA_ROUGH)
    tex(n, "base_color", "Textures/sea_detail.png")
    tex(n, "normal", "Textures/sea_normal_00.png")
    tex(n, "metallic_roughness", "Textures/sea_rough.png")
end
LOOK.trail = function(n)
    render_type(n, "alpha_blend")
    mat(n, { 0, 0, 0, 1 }, 0, 1, { 0.7, 1.0, 0.75 })
    tex(n, "base_color", "Textures/trail.png")
    tex(n, "emissive", "Textures/trail.png")
end
W.BEAM_EMIS = { 1.0, 1.0, 1.0 }    -- x the card's warm colour; above 1 it clipped to white (tonemapping off)
W.BEAM_W = 2.0           -- card width scale (the target's wedge is about twice the card's texture core)
LOOK.beam = function(n)
    render_type(n, "alpha_blend")
    mat(n, { 0, 0, 0, 1 }, 0, 1, W.BEAM_EMIS)
    tex(n, "base_color", "Textures/beam_card.png")
    tex(n, "emissive", "Textures/beam_card.png")
end
W.GLASS = { base = { 0.22, 0.62, 0.36, 0.28 }, emis = { 0.45, 0.95, 0.60 }, inner = { 0.66, 1.0, 0.74 }, halo = { 0.5, 1.0, 0.6 } }
-- The shell: green glass that brightens to a lit rim at its silhouette (float_glass_rim.png, baked for the play camera).
-- At alpha 0.28 it was nearly clear, so the net's back bars showed through as a second offset cage (state B).
-- float_glass_alpha.png (baked for the play camera too) keeps the centre clear (0.2), so the white core shows, and the
-- band outside the core nearly opaque (0.95). The emissive factor x GLASS_RIM_K lets the rim clip toward pale green.
W.GLASS_ALPHA, W.GLASS_RIM_K = 1.0, 1.9
LOOK.float_glass = function(n)
    render_type(n, "alpha_blend")
    local b, e, k = W.GLASS.base, W.GLASS.emis, W.GLASS_RIM_K
    mat(n, { b[1], b[2], b[3], W.GLASS_ALPHA }, 0, 0.04, { e[1] * k, e[2] * k, e[3] * k })
    tex(n, "base_color", "Textures/float_glass_alpha.png")
    tex(n, "emissive", "Textures/float_glass_rim.png")
end
-- The inner glow is opaque and emissive: nested alpha-blend spheres lose the inner one to the glass's depth write.
W.FLOAT_HALO = 1.2    -- the float's glow particle strength (x HALO_K); 22:5x live: B float 124 -> 134 vs target 135
W.CORE_K = 2.5      -- the core's emissive gain: above 1 the tone curve turns it near-white, as the target's (22:4x live)
LOOK.float_inner = function(n)
    local c, k = W.GLASS.inner or { 0.66, 1.0, 0.74 }, W.CORE_K
    mat(n, { 0, 0, 0, 1 }, 0, 1, { c[1] * k, c[2] * k, c[3] * k })
end
-- Glass colours (unlocked by best score in undertow.lua). green is the approved look; the others keep its values'
-- brightness and swap the hue. light: the float's point light; halo: its glow particle (r, g, b before HALO_K).
W.GLASSES = {
    green = { base = { 0.22, 0.62, 0.36, 0.28 }, emis = { 0.45, 0.95, 0.60 }, inner = { 1.0, 1.0, 1.0 }, light = { 0.75, 1.0, 0.6 }, halo = { 0.5, 1.0, 0.6 } },
    amber = { base = { 0.66, 0.42, 0.14, 0.28 }, emis = { 0.98, 0.66, 0.30 }, inner = { 1.0, 0.80, 0.50 }, light = { 1.0, 0.78, 0.45 }, halo = { 1.0, 0.68, 0.32 } },
    cobalt = { base = { 0.16, 0.34, 0.70, 0.28 }, emis = { 0.42, 0.66, 1.0 }, inner = { 0.62, 0.80, 1.0 }, light = { 0.6, 0.76, 1.0 }, halo = { 0.45, 0.68, 1.0 } },
    rose = { base = { 0.66, 0.22, 0.34, 0.28 }, emis = { 1.0, 0.48, 0.62 }, inner = { 1.0, 0.68, 0.78 }, light = { 1.0, 0.62, 0.7 }, halo = { 1.0, 0.5, 0.64 } },
}
W.glass_name = "green"
LOOK.float_core = function(n) mat(n, { 1, 0.95, 0.7, 1 }, 0, 0.5, { 1, 0.95, 0.65 }) end
-- dark tarred rope bars, as the target's (0.42 base lit by IBL 6 and the lamps read pale)
LOOK.float_net = function(n) mat(n, { 0.11, 0.09, 0.06, 1 }, 0, 0.9) end
LOOK.chain_link = function(n) mat(n, { 0.2, 0.18, 0.16, 1 }, 0.85, 0.3) end   -- (0.09: black on the dark sea)
LOOK.chain_ring = function(n) mat(n, { 0.75, 0.52, 0.25, 1 }, 1.0, 0.3) end
-- Buoy number decals (one look per number; the bake's plate is blank)
for i = 1, 2 * D.PLATE_N do
    local name = string.format("plate_%02d", i)
    LOOK[name] = function(n)
        render_type(n, "alpha_blend")
        mat(n, { 0, 0, 0, 1 }, 1, 1, { 1, 1, 1 })
        tex(n, "base_color", "Textures/" .. name .. ".png")
        tex(n, "emissive", "Textures/" .. name .. ".png")
    end
end
W.LOOK = LOOK

------------------------------------------------------------------ nodes and pools
local TPL = {}
local seq = 0
W.created = 0
local function clone(name)
    local t = TPL[name]
    if not t then
        local n = scene.find_model and scene.find_model("T_" .. name)
        t = { mesh = n and n:get_mesh_refs()[1] or nil, styled = false }
        TPL[name] = t
    end
    seq = seq + 1
    W.created = W.created + 1
    local n = scene.add_empty_node(name .. "_" .. seq)
    if t.mesh then n:add_mesh_ref(t.mesh) end
    if not t.styled and LOOK[name] then LOOK[name](n); t.styled = true end   -- copies share the material
    return n
end
local function show(n, on) if n then pcall(function() n:set_enabled(on and true or false) end) end end
W.show = show

-- Pools: every node is made at init (adding nodes rebuilds the scene list) and shown / hidden after that.
local POOL = {}
W.POOL = POOL
local POOL_SIZE = {
    -- each = the peak in the view window over 30 play courses x 3000 units (scratch/peak_window.lua, 2026-11-13);
    -- lit and unlit each get the full count (a lamp lights in view)
    buoy_red_lit = 11, buoy_red_unlit = 11, buoy_white_lit = 10, buoy_white_unlit = 10, boat = 7, pier_lit = 10, pier_unlit = 10,
    bw = 9, bw_gap = 7, sea_tile = 5, far_card = 2, beam = 2,
}
for i = 1, 2 * D.PLATE_N do POOL_SIZE[string.format("plate_%02d", i)] = 1 end   -- numbers never repeat in view
local function make_pool(name, n)
    local p = { free = {}, used = {}, name = name, size = n }
    for i = 1, n do
        local node = clone(name)
        show(node, false)
        p.free[#p.free + 1] = node
    end
    POOL[name] = p
    return p
end
local function acquire(name)
    local p = POOL[name]
    local n = table.remove(p.free)
    if not n then
        W.starved = (W.starved or 0) + 1
        W.starved_by = W.starved_by or {}
        W.starved_by[name] = (W.starved_by[name] or 0) + 1
        return nil
    end
    p.used[n] = true
    show(n, not (W.hide and W.hide[name]))
    return n
end
local function release(name, n)
    local p = POOL[name]
    if not p.used[n] then return end
    p.used[n] = nil
    p.free[#p.free + 1] = n
    show(n, false)
end
W.acquire, W.release = acquire, release
function W.pool_counts()
    local t = {}
    for k, p in pairs(POOL) do
        local u = 0
        for _ in pairs(p.used) do u = u + 1 end
        t[k] = { used = u, free = #p.free, size = p.size }
    end
    return t
end

-- Batched transforms.
local PB, PN, RB, RN = {}, 0, {}, 0
local function setpos(n, bx, by, bz)
    local x, y, z = E(bx, by, bz)
    PB[PN * 4 + 1], PB[PN * 4 + 2], PB[PN * 4 + 3], PB[PN * 4 + 4] = n, x, y, z
    PN = PN + 1
end
local function setrot(n, rx, ry, rz)
    RB[RN * 4 + 1], RB[RN * 4 + 2], RB[RN * 4 + 3], RB[RN * 4 + 4] = n, rx, ry, rz
    RN = RN + 1
end
local function flush_xf()
    if PN > 0 then pcall(scene.set_positions, PB, PN) end
    if RN > 0 then pcall(scene.set_rotations, RB, RN) end
    PN, RN = 0, 0
end
W.setpos = setpos

------------------------------------------------------------------ lights and particles
local LIGHTS = {}
W.LIGHTS = LIGHTS
W.LAMP = { intensity = 1.5, radius = 9.0 }   -- (3.0: buoy lamps lit the water round state A's float too bright)
W.FLOAT_LIGHT = { intensity = 2.0, radius = 5.0, colour = { 0.75, 1.0, 0.6 } }   -- 7 painted swell faces teal
function W.set_glass(name)
    local g = W.GLASSES[name]
    if not g then return false end
    W.glass_name, W.GLASS = name, g
    W.FLOAT_LIGHT.colour = g.light
    if W.float then LOOK.float_glass(W.float.glass); LOOK.float_inner(W.float.inner) end
    return true
end
-- A point light follows its scene node, so move the node too. Node handles and the last values are cached: the
-- name lookups and unchanged writes cost frame time.
local LNODE, LLAST = {}, {}
local function point_light(i, bx, by, bz, col, inten, radius)
    local x, y, z = E(bx, by, bz)
    local key = string.format("%.3f %.3f %.3f %.2f %.2f %.2f %.2f %.2f", x, y, z, col[1], col[2], col[3], inten, radius)
    if LLAST[i] == key then return end
    LLAST[i] = key
    local pos = v3(x, y, z)
    pcall(lights.set_point_light, i, pos, v3(col[1], col[2], col[3]), inten, radius)
    if LNODE[i] == nil then
        local l = lights.get_point_lights and lights.get_point_lights()[i + 1]
        LNODE[i] = (l and scene.find_model and scene.find_model(l.name)) or false
    end
    if LNODE[i] then pcall(function() LNODE[i]:set_position(pos) end) end
end
local TEXI = {}
local function ptex(path)
    if TEXI[path] == nil then
        local ok, i = pcall(particles.load_texture, path)
        TEXI[path] = ok and i or 0
    end
    return TEXI[path]
end
local EMIT = {}
W.EMIT = EMIT
local function emitter(opts)
    local ok, i = pcall(particles.add_emitter, opts)
    return ok and i or -1
end
-- Every set_emitter re-uploads the emitter buffer: skip writes that change nothing (positions to the centimetre).
local ELAST = {}
local function set_emitter(i, t)
    if not i or i < 0 then return end
    local parts = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            parts[#parts + 1] = string.format("%s=%.2f,%.2f,%.2f,%.2f", k, v.x or 0, v.y or 0, v.z or 0, v.w or 0)
        else
            parts[#parts + 1] = k .. "=" .. tostring(v)
        end
    end
    table.sort(parts)
    local key = table.concat(parts, ";")
    if ELAST[i] == key then return end
    ELAST[i] = key
    pcall(particles.set_emitter, i, t)
end
W.set_emitter = set_emitter

-- Rain: three depth bands around the camera. Near streaks are long and bright, far ones short and faint. The sprite
-- (gen_assets make_rain_streak) leans RAIN_SLANT = 0.12; the drift (1.32 / 11) matches it.
W.RAIN = {
    { d = 6.5, r = 3.0, count = 220, rate = 220, size = { 0.45, 0.75 }, life = { 0.45, 0.7 }, col = { 0.20, 0.21, 0.22, 0.20 } },
    { d = 10.0, r = 8.0, count = 900, rate = 900, size = { 0.26, 0.42 }, life = { 0.6, 0.9 }, col = { 0.125, 0.13, 0.135, 0.125 } },
    { d = 22.0, r = 16.0, count = 2200, rate = 2200, size = { 0.12, 0.2 }, life = { 0.8, 1.2 }, col = { 0.075, 0.075, 0.08, 0.075 } },
}
W.HALO = { amber = { 1.0, 0.72, 0.40 }, green = { 0.6, 1.0, 0.65 }, dim = { 0.55, 0.33, 0.16 }, light = { 1.0, 0.86, 0.62 },
    cabin = { 0.5, 0.33, 0.15 } }
W.SPRAY = { 0.80, 1.0, 0.90 }    -- mint-white like the target (the float's light in the droplets)
-- The mist plume: its live particles fade out within ~0.25 s once the skim ends (the GPU sim colours every particle
-- from the emitter's current colour, ParticleCS.hlsl:153), so a finished skim does not leave a glowing ball behind.
W.MIST_COL = { 0.04, 0.062, 0.051 }
W.SPRAY_RATE = 5200      -- the target's plume half hides the hull behind the float (21:5x: region means vs target)
W.MIST_RATE = 100
W.HALO_K = 0.35          -- per particle (about three overlap)
local N_HALO = 16
W.halo_used = 0

------------------------------------------------------------------ init
function W.init()
    cam = scene.get_active_camera()
    pcall(function() cam:set_projection_mode("perspective") end)
    pcall(function() cam:set_far(3000) end)
    pcall(function() cam:set_near(0.1) end)
    if not W.settings_node then
        W.settings_node = scene.add_empty_node("Scene Settings")
        pcall(function() W.settings_node:set_scene_settings(true) end)
    end
    pcall(settings.set_render_mode, "raster")
    if skybox and skybox.load then pcall(skybox.load, "storm.hdr") end
    -- Baked layers are already graded (AgX): no tone curve on top. SSR gives the sea its reflections of the scene.
    for k, v in pairs({ tonemapping = false, bloom = true, bloom_strength = 0.12, bloom_range = 1.0, render_scale = 1.0,
        taa = true, fxaa = false, cas_sharpening = false, motion_blur = false, ssao = false, ssr = true, IBL = true,
        IBL_intensity = 6.0, shadows = false, color_grading = false, dof = false, fog = false }) do pcall(settings.set, k, v) end
    -- the scene's one directional light is the glitter light (aimed in tools/gen_assets.py write_scene, GLITTER_AT)
    pcall(lights.set_property, "directional", 0, "intensity", W.GLITTER.intensity)
    pcall(lights.set_property, "directional", 0, "color", vec3(W.GLITTER.colour[1], W.GLITTER.colour[2], W.GLITTER.colour[3]))
    for name, n in pairs(POOL_SIZE) do make_pool(name, n) end
    for _, b in ipairs(POOL.beam.free) do pcall(function() b:set_scale(v3(1, W.BEAM_W, 1)) end) end
    W.sky = clone("sky")
    W.float = { glass = clone("float_glass"), inner = clone("float_inner"), core = clone("float_core"), net = clone("float_net"),
        ring = clone("chain_ring"), trail = clone("trail") }
    W.links = {}
    for i = 1, 60 do W.links[i] = clone("chain_link"); show(W.links[i], false) end
    -- point lights: slot 1 the float, the rest the nearest lit lamps
    pcall(function()
        local base = #lights.get_point_lights()
        for _ = 1, 10 do lights.add_point() end
        for i = 0, 9 do LIGHTS[i + 1] = base + i end
        for i = 1, 10 do point_light(LIGHTS[i], 0, 0, -50, { 0, 0, 0 }, 0, 0.1) end
    end)
    -- particles
    local rt, gt, st = ptex("Textures/p_rain.png"), ptex("Textures/p_glow.png"), ptex("Textures/p_spray.png")
    for i, r in ipairs(W.RAIN) do
        EMIT["rain" .. i] = emitter({ position = v3(0, 0, 0), velocity = v3(1.32, -11, 0), gravity = v3(0, -2, 0),
            color_start = vec4(r.col[1], r.col[2], r.col[3], r.col[4]), color_end = vec4(r.col[1], r.col[2], r.col[3], r.col[4]),
            count = r.count, spawn_rate = r.rate, spawn_radius = r.r, size_min = r.size[1], size_max = r.size[2],
            life_min = r.life[1], life_max = r.life[2], noise_strength = 0, drag = 0, texture_index = rt, orientation = "vertical" })
    end
    -- spray: fine crisp droplets thrown up and back off the skimming float (not a mist: a mist read as speckle on hulls)
    -- (target crop: droplets 1-2 px at 2560 wide, many, mint-white, inside a faint mint mist)
    EMIT.spray = emitter({ position = v3(0, -50, 0), velocity = v3(-4.2, 1.5, 0.3), gravity = v3(0, -3, 0),
        color_start = vec4(W.SPRAY[1] * 0.8, W.SPRAY[2] * 0.8, W.SPRAY[3] * 0.8, 1), color_end = vec4(0.4, 0.5, 0.45, 0), count = 3000, spawn_rate = 0,
        spawn_radius = 0.16, size_min = 0.006, size_max = 0.017, life_min = 0.25, life_max = 0.65, noise_strength = 1.2, drag = 0.5,
        texture_index = st, orientation = "billboard" })
    EMIT.mist = emitter({ position = v3(0, -50, 0), velocity = v3(-3.0, 0.9, 0.2), gravity = v3(0, 0, 0),
        color_start = vec4(W.MIST_COL[1], W.MIST_COL[2], W.MIST_COL[3], 1), color_end = vec4(0, 0, 0, 0), count = 160, spawn_rate = 0,
        spawn_radius = 0.4, size_min = 0.7, size_max = 1.25, life_min = 0.6, life_max = 1.0, noise_strength = 0.6, drag = 0.8, texture_index = gt,
        orientation = "billboard" })
    W.halos = {}
    for i = 1, N_HALO do
        W.halos[i] = emitter({ position = v3(0, -50, 0), velocity = v3(0, 0, 0), gravity = v3(0, 0, 0),
            color_start = vec4(0, 0, 0, 0), color_end = vec4(0, 0, 0, 0), count = 3, spawn_rate = 0, spawn_radius = 0,
            size_min = 1, size_max = 1, life_min = 0.09, life_max = 0.1, noise_strength = 0, drag = 0, texture_index = gt,
            orientation = "billboard" })
    end
    W.ITEM = {}     -- course item id -> { pool, node }
end

------------------------------------------------------------------ the frame
local function pool_of(it)
    if it.kind == "buoy_red" or it.kind == "buoy_white" or it.kind == "pier" then
        return it.kind .. (it.lit and "_lit" or "_unlit")
    end
    return it.kind
end
local WIN = { near = { -22, 36 }, bw = { -30, 44 } }     -- measured view edges at y = 16 and y = 19, plus margin
W.WIN = WIN
local function in_window(it, cx)
    local w = (it.kind == "bw" or it.kind == "bw_gap") and WIN.bw or WIN.near
    local len = it.kind == "bw" and D.BW_SEG or (it.kind == "bw_gap" and D.BW_GAP or (it.kind == "pier" and D.PIER_SEG or 6))
    return it.x + len > cx + w[1] and it.x - 6 < cx + w[2]
end

-- Release every pooled set piece (a new course replaces the old one).
local function drop(id, cur)
    release(cur.pool, cur.node)
    if cur.plate then release(cur.plate_pool, cur.plate) end
    W.ITEM[id] = nil
end
function W.reset()
    for id, cur in pairs(W.ITEM or {}) do drop(id, cur) end
end

-- view: { t = sea time, cx = camera x, float = {x,y,z} or nil, hook = {x,y,z} or nil, theta, L, skim, trail }
function W.frame(course, view)
    W.frame_dt = view.dt or (W.frame_dt or 1 / 60)
    W.real_dt = view.real_dt or W.frame_dt
    local t, cx = view.t, view.cx
    -- set pieces: release what left the window (or changed look), acquire what entered
    local want = {}
    for _, it in ipairs(course.items) do
        if in_window(it, cx) then want[it.id] = it end
    end
    for id, cur in pairs(W.ITEM) do            -- release first, so a frame never needs more than the pool holds
        local it = want[id]
        if not it or pool_of(it) ~= cur.pool then drop(id, cur) end
    end
    for id, it in pairs(want) do
        if not W.ITEM[id] then
            local p = pool_of(it)
            local n = acquire(p)
            if n then
                local cur = { pool = p, node = n, it = it }
                if it.no then
                    cur.plate_pool = string.format("plate_%02d", it.no)
                    cur.plate = acquire(cur.plate_pool)
                end
                W.ITEM[id] = cur
            end
        end
    end
    -- pose them; collect lamps for lights and halos
    local lamps = {}
    for _, cur in pairs(W.ITEM) do
        local it, n = cur.it, cur.node
        local ox, oy, oz = Course.origin(it, t)
        setpos(n, ox, oy, oz)
        local sc = it.p.scale or 1
        local pl = cur.plate
        if pl then setpos(pl, ox, oy, oz) end
        if cur.scale ~= sc then        -- always set: a recycled node keeps the last item's scale (far markers are 0.9)
            pcall(function() n:set_scale(v3(sc, sc, sc)) end)
            if pl then pcall(function() pl:set_scale(v3(sc, sc, sc)) end) end
            cur.scale = sc
        end
        if it.kind == "buoy_red" or it.kind == "buoy_white" then
            local pitch = it.p.pitch or D.BUOY_TILT[2]
            setrot(n, 0, 0, -pitch)          -- Blender pitch about +y is engine roll about -z
            if pl then setrot(pl, 0, 0, -pitch) end
            local lx, ly, lz = Course.tilt(0, 0, D.LAMP_LOCAL * sc, pitch)
            local red = it.kind == "buoy_red"
            lamps[#lamps + 1] = { x = ox + lx, y = oy + ly, z = oz + lz, lit = it.lit, col = red and "amber" or "green", s = sc }
        elseif it.kind == "boat" then
            setrot(n, it.p.roll or 0, it.p.yaw or 0, 0)
            local a = rad(it.p.yaw or 0)
            lamps[#lamps + 1] = { x = ox - 1.5 * cos(a), y = oy - 1.5 * sin(a) - 1.2, z = oz + 2.05, lit = true, col = "cabin", s = 1,
                cabin = true }
        elseif it.kind == "pier" then
            lamps[#lamps + 1] = { x = it.x + D.PIER_SEG / 2, y = D.PIER_Y - 1.25, z = 5.2, lit = it.lit, col = "amber", s = 1 }
        elseif it.kind == "bw_gap" then
            lamps[#lamps + 1] = { x = it.x + 0.9, y = oy + 0.2, z = 3.62, lit = true, col = "amber", s = 0.8 }
            lamps[#lamps + 1] = { x = it.x + D.BW_GAP - 0.9, y = oy + 0.2, z = 3.62, lit = true, col = "green", s = 0.8 }
        end
    end
    -- sea tiles slide with the swell; the ripple flipbook loops
    local shift = Sea.shift(t)
    local k0 = floor((cx - 45 - shift) / D.SEA_P)
    local tp = POOL.sea_tile
    for n in pairs(tp.used) do release("sea_tile", n) end
    local amp = Sea.amp(t)          -- the swell breathes: tile height scale (rules use the same Sea.height)
    for k = k0, k0 + tp.size - 1 do
        local n = acquire("sea_tile")
        if n then
            setpos(n, k * D.SEA_P + shift, 0, 0)
            pcall(function() n:set_scale(v3(1, amp, 1)) end)
        end
    end
    local fr = floor(t * D.RIPPLE_FPS) % D.RIPPLE_FRAMES
    if fr ~= W.ripple_frame and not W.no_ripple then        -- no_ripple: timing A/B only
        W.ripple_frame = fr
        local path = string.format("Textures/%s%02d.png", W.RIPPLE_PREFIX, fr)
        local any = next(tp.used)
        if any then pcall(material.set_texture, any, "normal", path) end
    end
    -- sky and the far layer
    local camx, camy, camz = cx, D.CAM.y, view.cz or D.CAM.z      -- cz: the play camera rises with a high float
    do   -- the sky quad sits SKY_D ahead of the camera; W.sky_pull (debug) moves it nearer along the view axis
        local f0, k = D.CAM.front, -(W.sky_pull or 0)
        local ex, ey, ez = E(camx, camy, camz)
        pcall(function() W.sky:set_position(v3(ex + f0[1] * k, ey + f0[2] * k, ez + f0[3] * k)) end)
    end
    local fp, bp = POOL.far_card, POOL.beam
    for n in pairs(fp.used) do release("far_card", n) end
    for n in pairs(bp.used) do release("beam", n) end
    local kf = floor((cx - 80) / D.FAR.w + 0.5)
    for k = kf, kf + 1 do
        local n = acquire("far_card")
        if n then setpos(n, k * D.FAR.w, 0, 0) end
        local b = acquire("beam")
        if b then
            setpos(b, D.FAR.lantern[1] + k * D.FAR.w, D.FAR.lantern[2], W.LANTERN_Z)
            setrot(b, 0, 0, W.beam_angle or -8)
        end
        lamps[#lamps + 1] = { x = D.FAR.lantern[1] + k * D.FAR.w, y = D.FAR.lantern[2] - 1, z = W.LANTERN_Z, lit = true,
            col = "light", s = 3.2, nolight = true }
    end
    -- the float, its chain and trail
    local F = view.float
    local fl = W.float
    if view.shattered then          -- the glass broke: no float, no chain; a burst of shards (below) for a moment
        W.shatter_frames = (W.shatter_frames or 0) + 1
        for _, k in pairs(fl) do show(k, false) end
        for i = 1, #W.links do show(W.links[i], false) end
        W.links_used, W.chain = 0, nil
        local x, y, z = E(F.x, F.y - 0.2, F.z)
        set_emitter(EMIT.spray, { position = v3(x, y, z), spawn_rate = W.shatter_frames < 10 and 4000 or 0 })
        set_emitter(EMIT.mist, { spawn_rate = 0 })
        F = nil
    else
        W.shatter_frames = 0
    end
    if F then
        for _, k in ipairs({ "glass", "inner", "core", "net" }) do show(fl[k], true); setpos(fl[k], F.x, F.y, F.z) end
        local H = view.hook
        local links_used = 0
        if H then
            local dx, dz = H.x - F.x, H.z - F.z
            local phi = deg(atan2(-dx, dz))           -- engine roll about +z that turns +Y to the hook
            setrot(fl.net, 0, 0, phi)
            show(fl.ring, true)
            setpos(fl.ring, H.x, H.y, H.z + 0.04)
            local len = sqrt(dx * dx + dz * dz)
            local rf = D.FLOAT_R + 0.06
            local ax, az = H.x, H.z + 0.1 - 0.1      -- chain from the hook's throat
            local bx, bz = F.x + dx / len * rf, F.z + dz / len * rf
            local L = sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
            local nl = min(#W.links, floor(L / D.CHAIN_LINK[3]))
            for i = 1, nl do
                local u = (i - 0.5) / nl
                local n = W.links[i]
                show(n, true)
                setpos(n, ax + (bx - ax) * u, H.y, az + (bz - az) * u)
                setrot(n, 0, (i % 2) * 90 + 45, phi)
            end
            links_used = nl
            W.chain = { ax = ax, az = az, bx = bx, bz = bz, y = H.y, n = nl }
            if view.trail then
                show(fl.trail, true)
                setpos(fl.trail, H.x, H.y, H.z)
                setrot(fl.trail, 0, 0, deg(view.theta or 0))
                local s = (view.L or D.TRAIL_L) / D.TRAIL_L
                pcall(function() fl.trail:set_scale(v3(s, s, s)) end)
            else
                show(fl.trail, false)
            end
        else
            show(fl.ring, false)
            show(fl.trail, false)
            setrot(fl.net, 0, 0, 0)
            W.chain = nil
        end
        for i = links_used + 1, #W.links do show(W.links[i], false) end
        W.links_used = links_used
    else
        for _, k in pairs(fl) do show(k, false) end
        for i = 1, #W.links do show(W.links[i], false) end
        W.links_used, W.chain = 0, nil
    end
    -- point lights: the float, then the nearest lit lamps
    local li = 1
    if F and LIGHTS[1] and not view.sunk then
        local c = W.FLOAT_LIGHT.colour
        point_light(LIGHTS[1], F.x, F.y, F.z, c, W.FLOAT_LIGHT.intensity, W.FLOAT_LIGHT.radius)
        li = 2
    end
    table.sort(lamps, function(a, b) return abs(a.x - cx) + a.y < abs(b.x - cx) + b.y end)
    local hi = 0
    if F and W.halos[1] then         -- the float's own glow (the target's bloom around the hero)
        hi = 1
        local x, y, z = E(F.x, F.y - 0.5, F.z)
        local k = W.HALO_K * W.FLOAT_HALO
        local hc = W.GLASS.halo or { 0.5, 1.0, 0.6 }
        -- The glow particles live 0.1 s; spawned still, they trailed a fast float by a float's width (live play
        -- frames: the glow beside the glass). They move with the float's own velocity instead.
        local P, vx, vz = W.halo_prev, 0, 0
        -- the engine moves particles by its real frame time; the game moved the float by the clamped one (slow frames)
        local dt = W.real_dt or W.frame_dt or 0
        if P and dt > 1e-4 and abs(F.x - P.x) + abs(F.z - P.z) < 3 then vx, vz = (F.x - P.x) / dt, (F.z - P.z) / dt end
        W.halo_prev = { x = F.x, z = F.z }
        W.halo_v = { vx, vz }
        set_emitter(W.halos[1], { position = v3(x, y, z), velocity = v3(vx, vz, 0), color_start = vec4(hc[1] * k, hc[2] * k, hc[3] * k, 1),
            color_end = vec4(hc[1] * k, hc[2] * k, hc[3] * k, 1), size_min = 1.5, size_max = 1.5, spawn_rate = W.no_particles and 0 or 60 })
    else
        W.halo_prev = nil
    end
    for _, L in ipairs(lamps) do
        if L.lit and not L.nolight and li <= #LIGHTS then
            local c = W.HALO[L.col]
            local k = L.cabin and 0.6 or 1
            point_light(LIGHTS[li], L.x, L.y, L.z, c, W.LAMP.intensity * k * L.s, W.LAMP.radius)
            li = li + 1
        end
        if hi < N_HALO and (L.x - cx) > -40 and (L.x - cx) < 70 then
            hi = hi + 1
            local c0, hk = W.HALO[L.lit and L.col or "dim"], W.HALO_K
            local c = { c0[1] * hk, c0[2] * hk, c0[3] * hk }
            local size = (L.lit and 1.6 or 0.6) * L.s * (L.cabin and 1.0 or 1)
            local x, y, z = E(L.x, L.y - 0.3, L.z)
            set_emitter(W.halos[hi], { position = v3(x, y, z), color_start = vec4(c[1], c[2], c[3], 1),
                color_end = vec4(c[1], c[2], c[3], 1), size_min = size, size_max = size, spawn_rate = W.no_particles and 0 or 60 })
        end
    end
    for i = li, #LIGHTS do point_light(LIGHTS[i], 0, 0, -50, { 0, 0, 0 }, 0, 0.1) end
    for i = hi + 1, N_HALO do set_emitter(W.halos[i], { spawn_rate = 0, position = v3(0, -50, 0) }) end
    W.halo_used, W.lights_used = hi, li - 1
    -- rain bands follow the camera; spray where the float skims
    local f = D.CAM.front
    local px, py, pz = E(camx, camy, camz)
    for i, r in ipairs(W.RAIN) do
        set_emitter(EMIT["rain" .. i], { position = v3(px + f[1] * r.d, py + f[2] * r.d + 2.5, pz + f[3] * r.d),
            spawn_rate = W.no_particles and 0 or r.rate })
    end
    if view.shattered then
        -- (the burst was set above)
    elseif F and view.skim and not W.no_particles then
        local x, y, z = E(F.x - 0.45, F.y - 0.25, max(F.z - 0.02, Sea.height(F.x, 0, t) + 0.1))   -- behind the glass, at its middle
        W.mist_k = 1
        local c = W.MIST_COL
        set_emitter(EMIT.spray, { position = v3(x, y, z), spawn_rate = W.SPRAY_RATE })
        set_emitter(EMIT.mist, { position = v3(x, y, z), spawn_rate = W.MIST_RATE, color_start = vec4(c[1], c[2], c[3], 1) })
    else
        W.mist_k = max(0, (W.mist_k or 0) - (W.frame_dt or 1 / 60) * 4)
        local c, k = W.MIST_COL, W.mist_k
        set_emitter(EMIT.spray, { spawn_rate = 0 })
        set_emitter(EMIT.mist, { spawn_rate = 0, color_start = vec4(c[1] * k, c[2] * k, c[3] * k, 1) })
    end
    flush_xf()
    flush_mats()
    -- camera
    local cpx, cpy, cpz = E(camx, camy, camz)
    pcall(function() cam:set_fov(D.CAM.fovx) end)
    pcall(function() cam:set_position(v3(cpx, cpy, cpz)) end)
    pcall(function() cam:look_at(v3(cpx + f[1] * 10, cpy + f[2] * 10, cpz + f[3] * 10)) end)
end

-- the lantern height on the far card (as tools/scene.py beam_card)
do
    local Wf = D.FAR.w
    local harm = { { 1, 2.2, 0.4 }, { 2, 1.4, 1.7 }, { 3, 0.9, 3.0 }, { 5, 0.6, 0.6 }, { 9, 0.35, 2.1 }, { 17, 0.18, 4.4 }, { 31, 0.08, 1.2 } }
    local h = 2.6 + 9.0
    for _, c in ipairs(harm) do h = h + c[2] * sin(2 * math.pi * c[1] * 52.0 / Wf + c[3]) end
    W.LANTERN_Z = h - 0.5 + 13.9
end

return W
end
