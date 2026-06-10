-- ONE-SHOT scene builder: run via the editor MCP (execute_lua) with the PhasmaSpace
-- project active and an empty scene, then the saved solar_system.pescene is the
-- shipping artifact. Binding semantics verified against engine source 2026-06-10:
--   * node.set_script / skybox.load need ABSOLUTE paths (relative resolves vs exe
--     dir, not project Assets) -> both go through assets_path.
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

local EPOCH_JD = 2461201.5 -- 2026-06-10 00:00 UTC; matches solar_director default

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

-- Demo look (saved with the scene): no editor grid, soft bloom for the sun.
settings.set("draw_grid", false)
settings.set("bloom", true)
settings.set("bloom_strength", 1.2)
settings.set("bloom_range", 2.5)

local function make_body(name, parent, radius_units, tex)
    local h = scene.add_empty_node(name)
    h:set_parent(parent)
    scene.attach_primitive(h, "uv_sphere")
    h:set_scale(vec3(radius_units, radius_units, radius_units))
    material.set_texture(h, "base_color", P.TEX .. tex)
    material.set(h, "roughness", 1.0)
    material.set(h, "metallic", 0.0)
    return h
end

local root = scene.add_empty_node("SolarSystem")

-- Sun: emissive, lit from within (the point light below does the actual lighting)
local sun_r = P.sun.radius_km * P.SUN_RADIUS_SCALE / P.KM_PER_UNIT
local sun = make_body("Sun", root, sun_r, P.sun.tex)
-- Pure emissive star: black base so the point light contributes nothing; the
-- emissive texture x factor carries the look, bloom adds the glow.
material.set(sun, "base_color", vec4(0.0, 0.0, 0.0, 1.0))
material.set_texture(sun, "emissive", P.TEX .. P.sun.tex)
material.set(sun, "emissive", vec3(25.0, 21.0, 16.0))

local pls = lights.get_point_lights and lights.get_point_lights() or {}
if #pls == 0 then
    scene.add_point_light()
end
lights.set_point_light(0, vec3(0, 0, 0), vec3(1.0, 0.96, 0.9), 50.0, 1.0e6)

for _, p in ipairs(P.planets) do
    local orbit = scene.add_empty_node(p.name .. "_orbit")
    orbit:set_parent(root)
    local tilt = scene.add_empty_node(p.name .. "_tilt")
    tilt:set_parent(orbit)
    tilt:set_rotation(vec3(p.tilt, 0.0, 0.0)) -- demo simplification: tilt about X

    make_body(p.name, tilt, P.radius_units(p.radius_km), p.tex)

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

    if p.moon then
        local morbit = scene.add_empty_node(p.moon.name .. "_orbit")
        morbit:set_parent(tilt)
        morbit:set_position(vec3(P.dist_units(p.moon.a_km), 0.0, 0.0))
        make_body(p.moon.name, morbit, P.radius_units(p.moon.radius_km), p.moon.tex)
    end
end

skybox.load(assets_path .. "Textures/Solar/starmap_2020_4k.hdr")
root:set_script(assets_path .. "Scripts/solar/solar_director.lua")

save_scene("solar_system.pescene")
pe_log("[solar] scene built and saved")
return "built"
