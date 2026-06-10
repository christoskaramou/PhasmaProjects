-- Physical + presentation data for the demo. Units: km, hours (sidereal rotation,
-- negative = retrograde), degrees. Values from NASA NSSDC planetary fact sheets.
-- Textures: Solar System Scope (CC BY 4.0); Galilean moons use flat tints.
--
-- Moon entries: { name, radius_km, a_km, period_d, incl, tex | tint, dist_scale }.
-- dist_scale is a cosmetic orbit multiplier (unused at true scale — real orbits
-- clear the real planet radii). All listed moons are tidally locked.
local P = {}

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
      clouds = { tex = "earth_clouds.png", rot_h = 30.0, scale = 1.012 },
      moons = {
          { name = "Moon", radius_km = 1737.4, a_km = 384400.0, period_d = 27.321661, incl = 5.14, tex = "2k_moon.jpg" },
      } },
    { name = "Mars",    body = "mars",    radius_km = 3389.5,  rot_h = 24.6229, tilt = 25.19,  tex = "2k_mars.jpg" },
    { name = "Jupiter", body = "jupiter", radius_km = 69911.0, rot_h = 9.925,   tilt = 3.13,   tex = "2k_jupiter.jpg",
      moons = {
          { name = "Io",       radius_km = 1821.6, a_km = 421800.0,  period_d = 1.769138,  incl = 0.0, tint = { 0.93, 0.82, 0.45 } },
          { name = "Europa",   radius_km = 1560.8, a_km = 671100.0,  period_d = 3.551181,  incl = 0.0, tint = { 0.85, 0.82, 0.74 } },
          { name = "Ganymede", radius_km = 2634.1, a_km = 1070400.0, period_d = 7.154553,  incl = 0.0, tint = { 0.60, 0.56, 0.50 } },
          { name = "Callisto", radius_km = 2410.3, a_km = 1882700.0, period_d = 16.689017, incl = 0.0, tint = { 0.45, 0.41, 0.38 } },
      } },
    { name = "Saturn",  body = "saturn",  radius_km = 58232.0, rot_h = 10.656,  tilt = 26.73,  tex = "2k_saturn.jpg",
      rings = { inner_km = 74500.0, outer_km = 140220.0, tex = "saturn_rings.png" } },
    { name = "Uranus",  body = "uranus",  radius_km = 25362.0, rot_h = -17.24,  tilt = 97.77,  tex = "2k_uranus.jpg" },
    { name = "Neptune", body = "neptune", radius_km = 24622.0, rot_h = 16.11,   tilt = 28.32,  tex = "2k_neptune.jpg" },
}

function P.radius_units(km) return km * P.RADIUS_SCALE / P.KM_PER_UNIT end
function P.dist_units(km) return km / P.KM_PER_UNIT end

return P
