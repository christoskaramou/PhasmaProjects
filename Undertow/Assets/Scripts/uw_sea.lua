-- The sea's height: the same formula as tools/uw_common.py (sea_point / pattern_height / sea_height), read from the
-- generated uw_data.lua. tests/view_smoke.lua checks it against heights sampled in Python (tests/sea_samples.lua).
-- Blender axes: x along the harbour, y depth (away from the camera), z up.
return function(D)
local S = {}
local sin, cos, sqrt, max, pi = math.sin, math.cos, math.sqrt, math.max, math.pi
local P, C, CHOP = D.SEA_P, D.SEA_C, D.CHOP
local F0, F1 = D.SEA_FADE_Y[1], D.SEA_FADE_Y[2]
local W = {}
for i, s in ipairs(D.SWELLS) do
    local kx, ky = 2 * pi * s[2] / P, 2 * pi / s[3]
    W[i] = { a = s[1], kx = kx, ky = ky, ph = s[4], k = sqrt(kx * kx + ky * ky) }
end

local function fade(y)
    if y <= F0 then return 1 end
    return max(0, 1 - (y - F0) / (F1 - F0))
end

-- Displaced pattern vertex for pattern coords (x, y): x', y', z.
function S.point(x, y)
    local f = fade(y)
    local dx, dy, h = 0, 0, 0
    for i = 1, #W do
        local w = W[i]
        local s = w.kx * x + w.ky * y + w.ph
        h = h + w.a * sin(s)
        local q = CHOP * w.a * cos(s)
        dx = dx + q * w.kx / w.k
        dy = dy + q * w.ky / w.k
    end
    return x + dx * f, y + dy * f, h * f
end

-- Height of the displaced pattern above pattern point (x, y): inverts the Gerstner shift (8 fixed-point steps).
function S.pattern_height(x, y)
    local x0, y0 = x, y
    for _ = 1, 8 do
        local px, py = S.point(x0, y0)
        x0, y0 = x0 + (x - px), y0 + (y - py)
    end
    local _, _, h = S.point(x0, y0)
    return h
end

-- Swell breathing (uw_common.sea_amp): the pattern's height scale at time t; the view scales the tiles by it.
local BA, BT0, BH, BT = D.SEA_BREATH[1], D.SEA_BREATH[2], D.SEA_BREATH[3], D.SEA_BREATH[4]
function S.amp(t)
    return 1 + BA * sin(pi * (t - BT0) / BH) * cos(2 * pi * t / BT)
end

-- Water height under world point (x, y) at sea time t: the pattern slides along x at SEA_C and breathes.
function S.height(x, y, t)
    return S.amp(t) * S.pattern_height((x - C * t) % P, y)
end

-- Where the tile pattern sits at time t: tile k's origin is at k * SEA_P + S.shift(t).
function S.shift(t) return (C * t) % P end

return S
end
