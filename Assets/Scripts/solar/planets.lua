-- Physical + presentation data for the demo. Units: km, hours (sidereal rotation,
-- negative = retrograde), degrees. Planet values are from NASA fact sheets; moon
-- orbit/radius data is loaded from the generated JPL catalog.
-- Textures: Solar System Scope (CC BY 4.0); moons without texture use flat tints.
local P = {}

local function load_optional_module(path)
    if not fs or not fs.read then return nil end
    local source = fs.read(path)
    if not source then return nil end
    local chunk, err = load(source, "@" .. assets_path .. path, "t", _ENV)
    if not chunk then error(err) end
    return chunk()
end

local moon_catalog = load_optional_module("Scripts/solar/moon_catalog.lua") or {}

P.KM_PER_UNIT      = 1.0e4   -- 1 engine unit = 10,000 km (distances)
P.RADIUS_SCALE     = 1.0     -- TRUE SCALE: bodies drawn at real radius
P.SUN_RADIUS_SCALE = 1.0
P.AU_UNITS         = 1.495978707e8 / P.KM_PER_UNIT  -- 14959.787 units
P.TEX              = "Textures/Solar/"

P.sun = { radius_km = 695700.0, tex = "2k_sun.jpg" }

P.planets = {
    { name = "Mercury", body = "mercury", radius_km = 2439.7,  rot_h = 1407.6,  tilt = 0.03,   tex = "2k_mercury.jpg" },
    { name = "Venus",   body = "venus",   radius_km = 6051.8,  rot_h = -5832.5, tilt = 177.36, tex = "2k_venus_atmosphere.jpg" },
    { name = "Earth",   body = "earth",   radius_km = 6371.0,  rot_h = 23.9345, tilt = 23.44,  tex = "2k_earth_daymap.jpg",
      night_tex = "night_lights.png", -- thresholded city lights (bake_night_lights.py)
      clouds = { tex = "earth_clouds.png", rot_h = 30.0, scale = 1.012, tint = { 0.78, 0.82, 0.88 }, opacity = 0.30 },
      moons = moon_catalog.Earth },
    { name = "Mars",    body = "mars",    radius_km = 3389.5,  rot_h = 24.6229, tilt = 25.19,  tex = "2k_mars.jpg",
      moons = moon_catalog.Mars },
    { name = "Jupiter", body = "jupiter", radius_km = 69911.0, rot_h = 9.925,   tilt = 3.13,   tex = "2k_jupiter.jpg",
      moons = moon_catalog.Jupiter },
    { name = "Saturn",  body = "saturn",  radius_km = 58232.0, rot_h = 10.656,  tilt = 26.73,  tex = "2k_saturn.jpg",
      rings = {
          inner_km = 74500.0,
          outer_km = 140220.0,
          tex = "saturn_rings.png",
          tint = { 1.0, 0.94, 0.82 },
          emissive = { 1.35, 1.12, 0.82 },
      },
      moons = moon_catalog.Saturn },
    { name = "Uranus",  body = "uranus",  radius_km = 25362.0, rot_h = -17.24,  tilt = 97.77,  tex = "2k_uranus.jpg",
      moons = moon_catalog.Uranus },
    { name = "Neptune", body = "neptune", radius_km = 24622.0, rot_h = 16.11,   tilt = 28.32,  tex = "2k_neptune.jpg",
      moons = moon_catalog.Neptune },
    { name = "Pluto",   body = "pluto",   radius_km = 1188.3,  rot_h = -153.2928, tilt = 122.53, tint = { 0.69, 0.61, 0.53 },
      moons = moon_catalog.Pluto },
}

P.regions = {
    { name = "Kuiper_Belt_inner", radius_au = 30.0, samples = 720, color = { 0.25, 0.55, 1.0, 0.22 } },
    { name = "Kuiper_Belt_outer", radius_au = 50.0, samples = 720, color = { 0.25, 0.55, 1.0, 0.28 } },
    -- The real Oort Cloud begins far outside the camera-friendly demo scale. These
    -- are compressed visual markers for the cloud boundary, not true-distance shells.
    { name = "Oort_Cloud_inner_marker", radius_au = 95.0, true_radius_au = 2000.0, samples = 960, color = { 0.72, 0.82, 1.0, 0.16 } },
    { name = "Oort_Cloud_outer_marker", radius_au = 125.0, true_radius_au = 100000.0, samples = 960, color = { 0.72, 0.82, 1.0, 0.11 } },
}

function P.radius_units(km) return km * P.RADIUS_SCALE / P.KM_PER_UNIT end
function P.dist_units(km) return km / P.KM_PER_UNIT end

local function solve_kepler_rad(mean_anomaly, ecc)
    local e = ecc or 0.0
    local E = math.abs(e) < 0.8 and mean_anomaly or math.pi
    for _ = 1, 12 do
        local s = math.sin(E)
        local c = math.cos(E)
        local d = (E - e * s - mean_anomaly) / (1.0 - e * c)
        E = E - d
        if math.abs(d) < 1e-9 then break end
    end
    return E
end

function P.moon_local_units(m, jd)
    local a = P.dist_units(m.a_km) * (m.dist_scale or 1.0)
    local period = m.period_d or 1.0
    if math.abs(period) < 1e-9 then period = 1.0 end

    local ecc = m.ecc or 0.0
    if ecc < 0.0 then ecc = 0.0 elseif ecc > 0.95 then ecc = 0.95 end

    local epoch = m.epoch_jd or 2451545.0
    local mean_deg = (m.mean_anomaly_deg or 0.0) + ((jd - epoch) / period) * 360.0
    mean_deg = mean_deg % 360.0
    local E = solve_kepler_rad(math.rad(mean_deg), ecc)
    local xp = a * (math.cos(E) - ecc)
    local yp = a * math.sqrt(math.max(0.0, 1.0 - ecc * ecc)) * math.sin(E)

    local omega = math.rad(m.arg_peri_deg or 0.0)
    local node = math.rad(m.node_deg or 0.0)
    local incl = math.rad(m.incl or 0.0)
    local cw, sw = math.cos(omega), math.sin(omega)
    local cO, sO = math.cos(node), math.sin(node)
    local ci, si = math.cos(incl), math.sin(incl)

    local x = (cw * cO - sw * sO * ci) * xp + (-sw * cO - cw * sO * ci) * yp
    local y = (cw * sO + sw * cO * ci) * xp + (-sw * sO + cw * cO * ci) * yp
    local z = (sw * si) * xp + (cw * si) * yp
    return { x = x, y = z, z = y }
end

function P.sample_moon_orbit_units(m, samples, jd)
    local pts = {}
    local period = m.period_d or 1.0
    if math.abs(period) < 1e-9 then period = 1.0 end
    local anchor = jd or (m.epoch_jd or 2451545.0)
    for i = 0, samples - 1 do
        pts[#pts + 1] = P.moon_local_units(m, anchor + period * (i / samples))
    end
    return pts
end

return P
