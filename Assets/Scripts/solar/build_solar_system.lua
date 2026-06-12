-- ONE-SHOT scene builder: run via the editor MCP (execute_lua) with the PhasmaSpace
-- project active and an empty scene, then the saved solar_system.pescene is the
-- shipping artifact. Binding semantics verified against engine source 2026-06-10:
--   * skybox.load needs an ABSOLUTE path (relative resolves vs exe dir, not project
--     Assets) -> goes through assets_path; it serializes back project-relative.
--   * The director is NOT attached via set_script (that would bake this machine's
--     absolute path into the scene); it auto-loads from Assets/Scripts/global.
--   * material.set_texture resolves "Textures/..." against project Assets (portable).
--   * material.set(h, "emissive", v) takes vec3; set_rotation takes Euler degrees.

local function load_module(path)
    local source = fs and fs.read and fs.read(path) or nil
    if not source then error("PhasmaSpace: missing module " .. path) end
    local chunk, err = load(source, "@" .. assets_path .. path, "t", _ENV)
    if not chunk then error(err) end
    return chunk()
end

local E = load_module("Scripts/solar/ephemeris.lua")
local P = load_module("Scripts/solar/planets.lua")

local EPOCH_JD = 2461201.5 -- authoring seed only; solar_director overwrites runtime positions from the current clock

-- Idempotency: delete any prior SolarSystem tree so re-runs don't duplicate nodes.
for _, e in ipairs(scene.get_entities()) do
    if e.label == "SolarSystem" then
        e.node:remove()
    end
end

-- Space has no ambient directional light; the sun point light is the only source.
local dls = lights.get_directional_lights and lights.get_directional_lights() or {}
if #dls > 0 then
    scene.remove_light("directional", 0)
end

-- Demo render settings (serialized into the .pescene). Pinned to the user-tuned
-- Global panel state of 2026-06-10 so rebuilds reproduce it from any session.
settings.set("render_scale", 0.75)
settings.set("dynamic_rendering", true)
settings.set("IBL", false)
settings.set("ssao", false)
settings.set("ssr", false)
settings.set("use_Disney_PBR", true)
settings.set("fxaa", false)
settings.set("taa", true)
settings.set("cas_sharpening", true)
settings.set("cas_sharpness", 0.5)
settings.set("tonemapping", false)
settings.set("bloom", false)
settings.set("bloom_strength", 1.0)
settings.set("bloom_range", 1.0)
settings.set("dof", false)
settings.set("motion_blur", false)
settings.set("motion_blur_strength", 1.0)
settings.set("motion_blur_samples", 16)
settings.set("shadows", true)
settings.set("shadow_distance", 250.0)
settings.set("shadow_cascade_lambda", 0.85)
settings.set("shadow_normal_bias", 1.5)
settings.set("shadow_fade_fraction", 0.15)
settings.set("shadow_filter_radius", 0.75)
settings.set("shadow_debug_mode", 0)
settings.set_depth_bias(0.0, 0.0, -6.2)
settings.set("time_scale", 1.0)
settings.set("lights_intensity", 1.0)
settings.set("frustum_culling", true)
settings.set("freeze_frustum_culling", false)
settings.set("draw_aabbs", false)
settings.set("draw_grid", false)
settings.set("physical_point_falloff", true)
settings.set_render_mode("raster")

-- opts: tex (Assets-relative texture) OR tint ({r,g,b} flat color)
local function make_body(name, parent, radius_units, opts)
    local h = scene.add_empty_node(name)
    h:set_parent(parent)
    scene.attach_primitive(h, "uv_sphere")
    h:set_scale(vec3(radius_units, radius_units, radius_units))
    if opts.tex then
        material.set_texture(h, "base_color", P.TEX .. opts.tex)
    elseif opts.tint then
        material.set(h, "base_color", vec4(opts.tint[1], opts.tint[2], opts.tint[3], 1.0))
    end
    material.set(h, "roughness", 1.0)
    material.set(h, "metallic", 0.0)
    return h
end

local root = scene.add_empty_node("SolarSystem")

-- Sun: emissive, lit from within (the point light below does the actual lighting)
local sun_r = P.sun.radius_km * P.SUN_RADIUS_SCALE / P.KM_PER_UNIT
local sun = make_body("Sun", root, sun_r, { tex = P.sun.tex })
-- Pure emissive star: black base so the point light contributes nothing; the
-- emissive texture x factor carries the look, bloom adds the glow.
material.set(sun, "base_color", vec4(0.0, 0.0, 0.0, 1.0))
material.set_texture(sun, "emissive", P.TEX .. P.sun.tex)
material.set(sun, "emissive", vec3(25.0, 21.0, 16.0))

local pls = lights.get_point_lights and lights.get_point_lights() or {}
if #pls == 0 then
    scene.add_point_light()
end
-- Physical falloff: intensity = luminance * distance^2, anchored so Earth (1 AU =
-- 14,960 u) peaks around ~2.2 — properly exposed, day side not clipped. The
-- director's auto-exposure (lights_intensity = (d/AU)^2 for the followed body)
-- keeps outer planets readable, camera-style. Range 5e6 keeps the cutoff window
-- ~1.0 across all planets (Neptune d/r = 0.09).
lights.set_point_light(0, vec3(0, 0, 0), vec3(1.0, 0.96, 0.9), 4.9e8, 5.0e6)

for _, p in ipairs(P.planets) do
    local orbit = scene.add_empty_node(p.name .. "_orbit")
    orbit:set_parent(root)
    local tilt = scene.add_empty_node(p.name .. "_tilt")
    tilt:set_parent(orbit)
    tilt:set_rotation(vec3(p.tilt, 0.0, 0.0)) -- demo simplification: tilt about X

    local body = make_body(p.name, tilt, P.radius_units(p.radius_km), { tex = p.tex })

    -- City lights: emissive nightmap. night_emissive makes the lighting pass
    -- fade emissive where direct sunlight is strong, so the lights only show
    -- on the night side (the director re-applies the flag on every load too).
    if p.night_tex then
        material.set_texture(body, "emissive", P.TEX .. p.night_tex)
        material.set(body, "emissive", vec3(5.0, 4.6, 3.6))
        material.set(body, "night_emissive", 1.0)
    end

    -- Cloud layer: slightly larger sphere, luminance-as-alpha texture, own spin.
    if p.clouds then
        local cr = P.radius_units(p.radius_km) * p.clouds.scale
        local clouds = scene.add_empty_node(p.name .. "_clouds")
        clouds:set_parent(tilt)
        scene.attach_primitive(clouds, "uv_sphere")
        clouds:set_scale(vec3(cr, cr, cr))
        material.set_texture(clouds, "base_color", P.TEX .. p.clouds.tex)
        material.set_render_type(clouds, "alpha_blend")
        material.set(clouds, "roughness", 1.0)
        material.set(clouds, "metallic", 0.0)
    end

    -- initial heliocentric position so the saved scene looks right pre-play
    local x, y, z = E.heliocentric(p.body, EPOCH_JD)
    orbit:set_position(vec3(x * P.AU_UNITS, z * P.AU_UNITS, y * P.AU_UNITS))

    if p.rings then
        local outer_u = P.radius_units(p.rings.outer_km)
        local rings = scene.add_empty_node(p.name .. "_rings")
        rings:set_parent(tilt)
        scene.attach_primitive(rings, "plane") -- 10x10, planar UVs, XZ plane
        local s = outer_u * 2.0 / 10.0
        rings:set_scale(vec3(s, 1.0, s))
        material.set_texture(rings, "base_color", P.TEX .. p.rings.tex)
        material.set_render_type(rings, "alpha_blend")
        material.set(rings, "roughness", 1.0)
        material.set(rings, "metallic", 0.0)
    end

    for _, m in ipairs(p.moons or {}) do
        local morbit = scene.add_empty_node(m.name .. "_orbit")
        morbit:set_parent(tilt)
        morbit:set_position(vec3(P.dist_units(m.a_km) * (m.dist_scale or 1.0), 0.0, 0.0))
        make_body(m.name, morbit, P.radius_units(m.radius_km), { tex = m.tex, tint = m.tint })
    end
end

skybox.load(assets_path .. "Textures/Solar/starmap_2020_4k.hdr")
-- No set_script: the director lives in Assets/Scripts/global and auto-loads from
-- the active project, finding the SolarSystem node by name. Baking an absolute
-- set_script path here would hard-code this machine's path into the scene and the
-- director would not load on any other checkout.

save_scene("solar_system.pescene")
pe_log("[solar] scene built and saved")
return "built"
