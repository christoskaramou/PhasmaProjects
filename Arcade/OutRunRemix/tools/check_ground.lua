-- Ground/far-plane check: builds all 16 routes and tests every ground slab and the far plane against every road quad
-- in view. Usage (from the game folder): bin/luajit tools/check_ground.lua src/03_track.lua new   ("old" = previous rules)
floor, min, max, abs, sqrt, atan2 = math.floor, math.min, math.max, math.abs, math.sqrt, math.atan2
PI = math.pi
function clamp(v, a, b) return v < a and a or (v > b and b or v) end
function lerp(a, b, t) return a + (b - a) * t end
function vec3(x, y, z) return { x = x, y = y, z = z } end
G = {}
local src = io.open(arg[1]):read("*a")
assert(loadstring(src))()
local SG, STAGES, TC = G.SG, G.STAGES, G.TC
local HALF, RUMB = TC.HALF, TC.RUMB
local right_of = G.right_of
local MODE = arg[2] or "old"
local WMAX = 210
local function slab(g)
    local a, b = SG[g], (MODE == "old") and SG[g + 1] or G.seg_end(g)
    local dx, dz = b.x - a.x, b.z - a.z
    local len = sqrt(dx * dx + dz * dz)
    local fx, fz = dx / len, dz / len
    local rx, rz = -fz, fx     -- placeholder; actual right: perpendicular of heading (engine X axis after yaw)
    return a, fx, fz, len, (b.y - a.y) / len
end
local function road_pts(h)
    local a = SG[h]; local b = (MODE == "old") and SG[h + 1] or G.seg_end(h); local pts = {}
    if not b then return pts end
    local offs = { 0 }
    if a.fork and a.fork > 0.01 then offs = { -a.fork, a.fork } end
    local rx, rz = right_of(a.yaw)
    for _, t in ipairs({ 0, 0.33, 0.66 }) do
        local cx, cy, cz = a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t
        for _, off in ipairs(offs) do
            for _, l in ipairs({ -HALF - RUMB, -HALF * 0.66, -HALF / 3, 0, HALF / 3, HALF * 0.66, HALF + RUMB }) do
                pts[#pts + 1] = { cx + rx * (off + l), cy, cz + rz * (off + l) }
            end
        end
    end
    return pts
end
local total, bad, worst = 0, 0, {}
local farbad = 0
local function check_route(tag)
    local n = #SG
    for g0 = 1, n - 1 do
        local lo = math.huge
        for g = max(1, g0 - 4), min(n, g0 + 160) do lo = min(lo, SG[g].y) end
        local top = (MODE == "old") and (SG[g0].y - 1.2 + 0.5) or (lo - 2.0 + 0.5)
        for g = max(1, g0 - 4), min(n, g0 + 160) do if SG[g].y < top + 0.02 then farbad = farbad + 1; break end end
    end
    for g = 1, n - 1 do
        local a, fx, fz, len, slope = slab(g)
        local W = G.GW and G.GW[g] or { -WMAX, WMAX }
        local y0 = a.y - 0.06 - (g % 16) * 0.004
        for h = max(1, g - 170), min(n, g + 170) do
            if h ~= g then
                for _, p in ipairs(road_pts(h)) do
                    local px, pz = p[1] - a.x, p[3] - a.z
                    local f = px * fx + pz * fz
                    local l = px * -fz + pz * fx       -- signed lateral (sign irrelevant for symmetric slabs)
                    total = total + 1
                    if f >= -0.06 and f <= len + 0.12 then
                        local lr = -l     -- right_of = (-cos, sin) of yaw; fwd = (sin, cos) => right = (-fz, fx)?? use both
                        local rxx, rzz = right_of(a.yaw)
                        local lat = px * rxx + pz * rzz
                        if lat >= W[1] and lat <= W[2] then
                            local sy = y0 + f * slope
                            if sy > p[2] - 0.02 then
                                bad = bad + 1
                                local k = tag .. " g" .. g .. " h" .. h
                                if #worst < 40 then worst[#worst + 1] = string.format("%s lat=%.0f slab=%.2f road=%.2f", k, lat, sy, p[2]) end
                            end
                        end
                    end
                end
            end
        end
    end
end
-- all 16 routes: choose side per fork
for mask = 0, 15 do
    for k in pairs(SG) do SG[k] = nil end
    for k in pairs(STAGES) do STAGES[k] = nil end
    G.append_stage(1, 1, { 0, 0, 0, 0 })
    local col = 1
    for row = 1, 4 do
        local st = STAGES[#STAGES]
        local side = (math.floor(mask / 2 ^ (row - 1)) % 2 == 1) and 1 or -1
        st.side = side
        local tail = SG[st.gend]
        local rx, rz = right_of(tail.yaw)
        local base = { tail.x + rx * side * TC.FORK_D, tail.y, tail.z + rz * side * TC.FORK_D, tail.yaw }
        col = col + (side > 0 and 1 or 0)
        G.append_stage(row + 1, col, base, st.gend)
    end
    if G.ground_limits then G.ground_limits() end
    check_route("r" .. mask)
end
print("samples", total, "ground-over-road", bad, "camera positions with far plane over a visible road", farbad)
for _, w in ipairs(worst) do print(w) end
