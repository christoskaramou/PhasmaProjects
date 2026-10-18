-- Scenery/road clearance check: builds all 16 routes (every left/right choice at the 4 forks) and measures, for every
-- scenery object, the distance from its footprint to the nearest drivable road (both fork branches, every stage, incl.
-- the kerbs). Usage (from the game folder): bin/luajit tools/check_scenery.lua src/03_track.lua [src/04_sim.lua]
floor, min, max, abs, sqrt, atan2 = math.floor, math.min, math.max, math.abs, math.sqrt, math.atan2
PI = math.pi
function clamp(v, a, b) return v < a and a or (v > b and b or v) end
function lerp(a, b, t) return a + (b - a) * t end
function vec3(x, y, z) return { x = x, y = y, z = z } end
G = {}
assert(loadstring(io.open(arg[1]):read("*a")))()
local SG, STAGES, TC = G.SG, G.STAGES, G.TC
local HALF, RUMB = TC.HALF, TC.RUMB
local right_of = G.right_of
local HW = { palm = 0.7, bush = 1.2, rock = 2.0, cliff = 7.5, pine = 1.0, pine_s = 1.0, cactus = 0.7, bld = 6.5, windmill = 2.2,
    column = 0.9, vine = 0.5, lamp = 0.3, fence = 0.2, sign_l = 1.5, sign_r = 1.5 }
local MARGIN = 0.5
local function pseg(px, pz, x0, z0, x1, z1)
    local dx, dz = x1 - x0, z1 - z0
    local t = clamp(((px - x0) * dx + (pz - z0) * dz) / max(dx * dx + dz * dz, 1e-9), 0, 1)
    return sqrt((px - x0 - t * dx) ^ 2 + (pz - z0 - t * dz) ^ 2)
end
-- distance from (px,pz) to the nearest road centre line (all branches) over segments g-lo .. g+hi
local function road_dist(px, pz, g)
    local best, bh = 1e9, nil
    for h = max(1, g - 80), min(#SG - 1, g + 80) do
        local a, b = SG[h], G.seg_end(h)
        if a and b then
            local offs = { 0 }
            if a.fork and a.fork > 0.01 then offs = { -a.fork, a.fork } end
            local fb = (b.fork and b.st == a.st) and b.fork or (a.fork or 0)   -- branch offset at the segment end
            local rax, raz = right_of(a.yaw); local rbx, rbz = right_of(b.yaw)
            for k, off in ipairs(offs) do
                local ob = (#offs == 2) and ((k == 1) and -fb or fb) or 0
                local d = pseg(px, pz, a.x + rax * off, a.z + raz * off, b.x + rbx * ob, b.z + rbz * ob)
                if d < best then best, bh = d, h end
            end
        end
    end
    return best, bh
end
local total, bad, worst, kinds = 0, 0, {}, {}
local seen = {}
local function check_route(tag)
    for _, st in ipairs(STAGES) do
        for _, o in ipairs(st.objs) do
            if not o.arch then
                local key = st.row .. "," .. st.col .. ":" .. o.g .. ":" .. o.x .. o.k
                local a = SG[o.g]
                local x = G.obj_x and G.obj_x(o) or o.x
                local rx, rz = right_of(a.yaw)
                local px, pz = a.x + rx * x, a.z + rz * x
                local d, h = road_dist(px, pz, o.g)
                local clr = d - HALF - RUMB - (HW[o.k] or 1)
                total = total + 1
                if clr < MARGIN and not seen[key] then
                    seen[key] = true
                    bad = bad + 1; kinds[o.k] = (kinds[o.k] or 0) + 1
                    if #worst < 30 then worst[#worst + 1] = string.format("%s road %d,%d %-7s g=%d (i=%d) x=%.1f fork=%.1f clearance=%.2f m%s",
                        tag, st.row, st.col, o.k, o.g, a.i, x, a.fork or 0, clr, o.median and " median" or "") end
                end
            end
        end
    end
end
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
    check_route("route" .. mask)
end
local ks = {} for k, n in pairs(kinds) do ks[#ks + 1] = k .. "=" .. n end
print(string.format("objects checked %d, distinct objects closer than %.1f m to a road: %d  (%s)", total, MARGIN, bad, table.concat(ks, " ")))
for _, w in ipairs(worst) do print(w) end
