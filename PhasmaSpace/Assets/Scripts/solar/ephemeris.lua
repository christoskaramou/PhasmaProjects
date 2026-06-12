-- Standish (JPL) "Keplerian Elements for Approximate Positions of the Major Planets",
-- Table 1, valid 1800-2050 AD. https://ssd.jpl.nasa.gov/planets/approx_pos.html
-- Major-planet values verified digit-by-digit against the JPL page on 2026-06-10.
-- Pluto uses JPL Horizons heliocentric J2000 osculating elements queried on
-- 2026-06-12; angular rate is its J2000 mean motion converted to deg/century.
-- Returns heliocentric J2000-ecliptic positions in AU. Pure Lua, no engine deps.

local M = {}

M.J2000 = 2451545.0
M.AU_KM = 1.495978707e8

-- { a[AU], aDot, e, eDot, I[deg], IDot, L[deg], LDot, varpi[deg], varpiDot, Omega[deg], OmegaDot }
-- (rates are per Julian century)
M.elements = {
    mercury = { 0.38709927, 0.00000037, 0.20563593, 0.00001906, 7.00497902, -0.00594749, 252.25032350, 149472.67411175, 77.45779628, 0.16047689, 48.33076593, -0.12534081 },
    venus   = { 0.72333566, 0.00000390, 0.00677672, -0.00004107, 3.39467605, -0.00078890, 181.97909950, 58517.81538729, 131.60246718, 0.00268329, 76.67984255, -0.27769418 },
    earth   = { 1.00000261, 0.00000562, 0.01671123, -0.00004392, -0.00001531, -0.01294668, 100.46457166, 35999.37244981, 102.93768193, 0.32327364, 0.0, 0.0 },
    mars    = { 1.52371034, 0.00001847, 0.09339410, 0.00007882, 1.84969142, -0.00813131, -4.55343205, 19140.30268499, -23.94362959, 0.44441088, 49.55953891, -0.29257343 },
    jupiter = { 5.20288700, -0.00011607, 0.04838624, -0.00013253, 1.30439695, -0.00183714, 34.39644051, 3034.74612775, 14.72847983, 0.21252668, 100.47390909, 0.20469106 },
    saturn  = { 9.53667594, -0.00125060, 0.05386179, -0.00050991, 2.48599187, 0.00193609, 49.95424423, 1222.49362201, 92.59887831, -0.41897216, 113.66242448, -0.28867794 },
    uranus  = { 19.18916464, -0.00196176, 0.04725744, -0.00004397, 0.77263783, -0.00242939, 313.23810451, 428.48202785, 170.95427630, 0.40805281, 74.01692503, 0.04240589 },
    neptune = { 30.06992276, 0.00026291, 0.00859048, 0.00005105, 1.77004347, 0.00035372, -55.12002969, 218.45945325, 44.96476227, -0.32241464, 131.78422574, -0.00508664 },
    pluto   = { 39.57126152, 0.0, 0.24944850, 0.0, 17.23565302, 0.0, 239.36226047, 144.61870104, 225.21860593, 0.0, 110.03993995, 0.0 },
}

-- Solve Kepler's equation M = E - e*sin(E); degrees in/out (per the Standish memo,
-- which works in degrees with e* = 57.29578 * e).
local function solve_kepler(M_deg, e)
    local e_star = math.deg(e)
    local E_deg = M_deg + e_star * math.sin(math.rad(M_deg))
    for _ = 1, 12 do
        local E_rad = math.rad(E_deg)
        local dM = M_deg - (E_deg - e_star * math.sin(E_rad))
        local dE = dM / (1.0 - e * math.cos(E_rad))
        E_deg = E_deg + dE
        if math.abs(dE) < 1e-7 then break end
    end
    return E_deg
end

-- Heliocentric J2000 ecliptic position [AU]. Returns x, y, z (z = ecliptic north).
function M.heliocentric(name, jd)
    local el = M.elements[name]
    if not el then error("ephemeris: unknown body " .. tostring(name)) end
    local T = (jd - M.J2000) / 36525.0
    local a, e    = el[1] + el[2] * T, el[3] + el[4] * T
    local I       = math.rad(el[5] + el[6] * T)
    local L       = el[7] + el[8] * T
    local varpi   = el[9] + el[10] * T
    local Omega_d = el[11] + el[12] * T
    local omega   = math.rad(varpi - Omega_d)
    local Omega   = math.rad(Omega_d)

    local Mdeg = (L - varpi) % 360.0
    if Mdeg > 180.0 then Mdeg = Mdeg - 360.0 end

    local E = math.rad(solve_kepler(Mdeg, e))
    local xp = a * (math.cos(E) - e)
    local yp = a * math.sqrt(1.0 - e * e) * math.sin(E)

    local cw, sw = math.cos(omega), math.sin(omega)
    local cO, sO = math.cos(Omega), math.sin(Omega)
    local cI, sI = math.cos(I), math.sin(I)
    local x = (cw * cO - sw * sO * cI) * xp + (-sw * cO - cw * sO * cI) * yp
    local y = (cw * sO + sw * cO * cI) * xp + (-sw * sO + cw * cO * cI) * yp
    local z = (sw * sI) * xp + (cw * sI) * yp
    return x, y, z
end

return M
