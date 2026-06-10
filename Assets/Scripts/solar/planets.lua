-- Physical + presentation data for the demo. Units: km, hours (sidereal rotation,
-- negative = retrograde), degrees. Values from NASA NSSDC planetary fact sheets.
-- Textures: Solar System Scope (CC BY 4.0).
local P = {}

P.KM_PER_UNIT      = 1.0e4   -- 1 engine unit = 10,000 km (distances)
P.RADIUS_SCALE     = 10.0    -- planets/moons drawn 10x real radius
P.SUN_RADIUS_SCALE = 3.0
P.AU_UNITS         = 1.495978707e8 / P.KM_PER_UNIT  -- 14959.787 units
P.TEX              = "Textures/Solar/"

P.sun = { radius_km = 695700.0, tex = "2k_sun.jpg" }

P.planets = {
    { name = "Mercury", body = "mercury", radius_km = 2439.7,  rot_h = 1407.6,  tilt = 0.03,   tex = "2k_mercury.jpg" },
    { name = "Venus",   body = "venus",   radius_km = 6051.8,  rot_h = -5832.5, tilt = 177.36, tex = "2k_venus_atmosphere.jpg" },
    { name = "Earth",   body = "earth",   radius_km = 6371.0,  rot_h = 23.9345, tilt = 23.44,  tex = "2k_earth_daymap.jpg",
      moon = { name = "Moon", radius_km = 1737.4, a_km = 384400.0, period_d = 27.321661, incl = 5.14, tex = "2k_moon.jpg" } },
    { name = "Mars",    body = "mars",    radius_km = 3389.5,  rot_h = 24.6229, tilt = 25.19,  tex = "2k_mars.jpg" },
    { name = "Jupiter", body = "jupiter", radius_km = 69911.0, rot_h = 9.925,   tilt = 3.13,   tex = "2k_jupiter.jpg" },
    { name = "Saturn",  body = "saturn",  radius_km = 58232.0, rot_h = 10.656,  tilt = 26.73,  tex = "2k_saturn.jpg",
      rings = { inner_km = 74500.0, outer_km = 140220.0, tex = "saturn_rings.png" } },
    { name = "Uranus",  body = "uranus",  radius_km = 25362.0, rot_h = -17.24,  tilt = 97.77,  tex = "2k_uranus.jpg" },
    { name = "Neptune", body = "neptune", radius_km = 24622.0, rot_h = 16.11,   tilt = 28.32,  tex = "2k_neptune.jpg" },
}

function P.radius_units(km) return km * P.RADIUS_SCALE / P.KM_PER_UNIT end
function P.dist_units(km) return km / P.KM_PER_UNIT end

return P
