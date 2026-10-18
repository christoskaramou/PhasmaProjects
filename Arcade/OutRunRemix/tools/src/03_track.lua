------------------------------------------------------------------ the route: 15 roads in 5 stages (left/right fork after each)
local SEG = 5.0                      -- metres per segment
local HALF = 9.0                     -- road half width (4 lanes of 4.5 m)
local RUMB = 1.3                     -- rumble strip width
local FORK = 110                     -- fork length in segments
local FORK_D = 46                    -- branch offset at the end of a fork (m)
local COMMIT = 70                    -- segment in the fork where the choice is locked
local STAGE_LEN = 820                -- segments per road before the fork
G.TC = { SEG = SEG, HALF = HALF, RUMB = RUMB, FORK = FORK, FORK_D = FORK_D, COMMIT = COMMIT, STAGE_LEN = STAGE_LEN }
-- themes: ground texture, horizon panorama, far-plane colour, scenery mix {kind, weight}, curviness, hilliness, traffic
local TH = {
    beach   = { key = "beach", ground = "beach", sky = "beach", far = { .82, .74, .55 }, mix = { { "palm", 6 }, { "bush", 1 } }, curve = 0.8, hill = 0.4, traffic = 1.0, right = { { "palm", 1 } } },
    gateway = { key = "gateway", ground = "grass", sky = "green", far = { .3, .5, .22 }, mix = { { "column", 3 }, { "bush", 3 }, { "palm", 1 } }, curve = 1.0, hill = 0.6, traffic = 1.0 },
    canyon  = { key = "canyon", ground = "canyon", sky = "canyon", far = { .6, .33, .22 }, mix = { { "cliff", 3 }, { "rock", 4 } }, curve = 1.3, hill = 0.8, traffic = 0.9 },
    deso    = { key = "deso", ground = "dry", sky = "pale", far = { .6, .55, .38 }, mix = { { "rock", 3 }, { "bush", 2 }, { "sign", 1 } }, curve = 1.0, hill = 1.2, traffic = 1.0 },
    alps    = { key = "alps", ground = "alps", sky = "alps", far = { .45, .6, .42 }, mix = { { "pine_s", 5 }, { "rock", 1 } }, curve = 1.2, hill = 1.0, traffic = 1.0 },
    cloudy  = { key = "cloudy", ground = "dark", sky = "cloudy", far = { .24, .4, .24 }, mix = { { "pine", 5 }, { "rock", 1 } }, curve = 1.4, hill = 1.1, traffic = 1.1 },
    wheat   = { key = "wheat", ground = "wheat", sky = "wheat", far = { .8, .68, .35 }, mix = { { "windmill", 1 }, { "bush", 2 }, { "fence", 3 } }, curve = 0.8, hill = 0.7, traffic = 1.2 },
    town    = { key = "town", ground = "town", sky = "town", far = { .42, .42, .4 }, mix = { { "bld", 4 }, { "lamp", 3 }, { "palm", 1 } }, curve = 1.0, hill = 0.5, traffic = 1.4 },
    capital = { key = "capital", ground = "grass", sky = "dusk", far = { .3, .45, .22 }, mix = { { "column", 4 }, { "bld", 2 }, { "bush", 2 } }, curve = 1.1, hill = 0.7, traffic = 1.2 },
    wild    = { key = "wild", ground = "dry", sky = "desert", far = { .62, .52, .34 }, mix = { { "cactus", 3 }, { "rock", 3 } }, curve = 1.3, hill = 1.0, traffic = 1.0 },
    vine    = { key = "vine", ground = "vine", sky = "green", far = { .4, .45, .22 }, mix = { { "vine", 5 }, { "bush", 1 } }, curve = 1.1, hill = 0.8, traffic = 1.2 },
    death   = { key = "death", ground = "desert", sky = "canyon", far = { .8, .65, .45 }, mix = { { "rock", 3 }, { "cliff", 2 }, { "cactus", 1 } }, curve = 1.5, hill = 1.1, traffic = 1.0 },
    desert  = { key = "desert", ground = "desert", sky = "desert", far = { .85, .72, .5 }, mix = { { "cactus", 4 }, { "rock", 2 } }, curve = 1.2, hill = 0.9, traffic = 1.0 },
    autobahn = { key = "autobahn", ground = "grass", sky = "green", far = { .3, .5, .22 }, mix = { { "pine", 3 }, { "lamp", 2 }, { "fence", 2 } }, curve = 0.7, hill = 0.4, traffic = 1.6 },
    lake    = { key = "lake", ground = "lake", sky = "lake", far = { .3, .5, .22 }, mix = { { "pine", 4 }, { "bush", 1 } }, curve = 1.2, hill = 0.8, traffic = 1.1 },
}
-- the original map (row = stage 1..5, left to right); branch i of row k leads to i (left) or i+1 (right) of row k+1
local ROUTE = {
    { { "Coconut Beach", "beach" } },
    { { "Gateway", "gateway" }, { "Devil's Canyon", "canyon" } },
    { { "Desolation Hill", "deso" }, { "Alps", "alps" }, { "Cloudy Mountain", "cloudy" } },
    { { "Wheat Field", "wheat" }, { "Seaside Town", "town" }, { "Old Capital", "capital" }, { "Wilderness", "wild" } },
    { { "Vineyard", "vine" }, { "Death Valley", "death" }, { "Desert", "desert" }, { "Autobahn", "autobahn" }, { "Lakeside", "lake" } },
}
local GOALS = { "A", "B", "C", "D", "E" }
local EXTEND = { 75, 64, 62, 60, 58 }          -- start time, then time added at each checkpoint
G.ROUTE, G.TH, G.GOALS, G.EXTEND = ROUTE, TH, GOALS, EXTEND

------------------------------------------------------------------ segment storage (global index g, appended stage by stage)
local SG = {}          -- SG[g] = { x, y, z (start point), yaw (deg), curve (deg/seg), dy, fork (offset or nil), st (stage rec) }
local STAGES = {}      -- { row, col, name, th, g0, g1 (first seg of fork), gend, side, objs }
G.SG, G.STAGES = SG, STAGES
local function road_rng(row, col)
    local seed = row * 977 + col * 131 + 7
    return function() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
end
local function append_stage(row, col, base, gstart)
    local def = ROUTE[row][col]
    local th = TH[def[2]]
    local lr = road_rng(row, col)
    local st = { row = row, col = col, name = def[1], th = th, objs = {}, last = (row == 5) }
    local g = gstart or (#SG + 1)
    st.g0 = g
    local x, y, z, yaw = base[1], base[2], base[3], base[4]
    -- sections: {length, curve, hill amplitude}
    local secs = { { 40, 0, 0 } }
    local total = 40
    while total < STAGE_LEN - 40 do
        local len = 40 + floor(lr() * 70)
        local r = lr()
        local cv = 0
        if r < 0.62 * th.curve then
            local mag = (lr() < 0.35) and 1.9 or (lr() < 0.6 and 1.15 or 0.6)
            cv = mag * (lr() < 0.5 and -1 or 1)
        end
        local hl = (lr() < 0.55 * th.hill) and (lr() * 2 - 1) * 0.55 * th.hill or 0
        secs[#secs + 1] = { len, cv, hl }
        total = total + len
    end
    secs[#secs + 1] = { STAGE_LEN + (st.last and 60 or FORK) - total, 0, 0 }
    local i0 = 0
    for _, sc in ipairs(secs) do
        for k = 0, sc[1] - 1 do
            local t = k / sc[1]
            local ease = math.sin(PI * t)                 -- curves and hills ease in and out
            local cv = sc[2] * min(1, ease * 1.6)
            local dy = sc[3] * math.sin(2 * PI * t)
            SG[g] = { x = x, y = y, z = z, yaw = yaw, curve = cv, dy = dy, st = st, i = i0 }
            local yr = math.rad(yaw)
            x = x + SEG * math.sin(yr); z = z + SEG * math.cos(yr); y = y + dy
            yaw = yaw + cv
            g = g + 1; i0 = i0 + 1
        end
    end
    SG[g] = { x = x, y = y, z = z, yaw = yaw, curve = 0, dy = 0, st = st, i = i0, tail = true }
    st.gend = g
    -- keep the unshifted end point: once the next road is appended, SG[gend] becomes that road's first segment, which
    -- starts 46 m to one side (on the chosen branch). Geometry for the last fork segment must still end here.
    st.tail = SG[g]
    if not st.last then
        st.g1 = st.g0 + STAGE_LEN
        for gg = st.g1, st.gend do
            local j = (gg - st.g1) / FORK
            SG[gg].fork = FORK_D * clamp(j, 0, 1) ^ 1.7
        end
    end
    -- scenery (both sides, plus the median of the fork); s is the segment index inside the road
    local mix = th.mix
    local wsum = 0
    for _, m in ipairs(mix) do wsum = wsum + m[2] end
    local function pick()
        local r = lr() * wsum
        for _, m in ipairs(mix) do r = r - m[2]; if r <= 0 then return m[1] end end
        return mix[1][1]
    end
    local gi = st.g0 + 8
    while gi < st.gend - 2 do
        for _, sd in ipairs({ -1, 1 }) do
            if lr() < 0.75 then
                local k = pick()
                if th.right and sd > 0 and th.key == "beach" then k = (lr() < 0.4) and "palm" or nil end
                if k then
                    local off = HALF + RUMB + 3 + lr() * 9
                    if k == "cliff" then off = off + 9 end
                    if k == "bld" then off = off + 8 end
                    if k == "fence" or k == "lamp" then off = HALF + RUMB + 2.5 end
                    st.objs[#st.objs + 1] = { g = gi, x = sd * off, k = k, v = floor(lr() * 3), ry = lr() * 360 }
                end
            end
        end
        gi = gi + 3 + floor(lr() * 4)
    end
    -- warning signs before every sharp curve
    for gg = st.g0 + 20, st.gend - 1 do
        local s2 = SG[gg + 12]
        if s2 and abs(s2.curve) > 1.0 and abs(SG[gg].curve) < 0.4 and SG[gg].i % 7 == 0 then
            local left = s2.curve > 0
            st.objs[#st.objs + 1] = { g = gg, x = (left and 1 or -1) * (HALF + RUMB + 2.2), k = left and "sign_l" or "sign_r", v = 0, ry = 0 }
        end
    end
    -- roadside offsets were measured from the unsplit centre line, but inside the fork the two roads slide out to
    -- +-46 m, straight over that scenery (palms on the road ~1 min in, at the first fork). Inside the fork every
    -- roadside object now rides out with its branch: x is measured from the outer kerb of its own road.
    for _, o in ipairs(st.objs) do
        local f = SG[o.g] and SG[o.g].fork
        if f and o.x ~= 0 then o.x = o.x + (o.x > 0 and f or -f) end
    end
    -- the fork median: bushes and rocks only once the inner kerbs are far enough apart to hold them
    if st.g1 then
        for gg = st.g1, st.gend - 1, 5 do
            local k = (gg % 15 == 0) and "rock" or "bush"
            local need = HALF + RUMB + ((k == "rock") and 2.0 or 1.2) + 1.0
            if SG[gg].fork >= need then st.objs[#st.objs + 1] = { g = gg, x = 0, k = k, v = 0, ry = gg * 37, median = true } end
        end
    end
    -- gantries: START on the first road, CHECKPOINT on the others, GOAL at the end of stage 5
    st.objs[#st.objs + 1] = { g = st.g0 + 2, x = 0, k = (row == 1) and "start" or "check", v = 0, ry = 0, arch = true }
    if st.last then st.objs[#st.objs + 1] = { g = st.g0 + STAGE_LEN, x = 0, k = "goal", v = 0, ry = 0, arch = true } end
    table.sort(st.objs, function(a, b) return a.g < b.g end)
    STAGES[#STAGES + 1] = st
    return st
end
G.append_stage = append_stage
local function reset_route()
    for k in pairs(SG) do SG[k] = nil end
    for k in pairs(STAGES) do STAGES[k] = nil end
    append_stage(1, 1, { 0, 0, 0, 0 })
end
G.reset_route = reset_route
-- right vector of a heading (deg)
local function right_of(yaw) local r = math.rad(yaw); return -math.cos(r), math.sin(r) end
G.right_of = right_of
-- end point of segment g for geometry (road/ground pieces): the next segment, except across a road change where it
-- is this road's own unshifted tail (see append_stage)
local function seg_end(g)
    local a, b = SG[g], SG[g + 1]
    if a and b and b.st ~= a.st and a.st.tail then return a.st.tail end
    return b
end
G.seg_end = seg_end
-- lateral shift of the drivable centre line: after the fork choice the frame follows the chosen branch
local function shift_of(sg) if sg and sg.fork and sg.st.side then return sg.st.side * sg.fork end return 0 end
G.shift_of = shift_of
-- interpolated frame at distance s (m along the driven route); raw = the unshifted centre line
local function frame(s, raw)
    local gf = s / SEG
    local g = floor(gf); local t = gf - g
    g = g + 1
    local a, b = SG[g], SG[g + 1]
    if not a then a = SG[#SG]; t = 0 end
    if not b then b = a end
    local ax, az, bx, bz = a.x, a.z, b.x, b.z
    if not raw then
        local sa, sb = shift_of(a), shift_of(b)
        if sa ~= 0 then local rx, rz = right_of(a.yaw); ax, az = ax + rx * sa, az + rz * sa end
        if sb ~= 0 then local rx, rz = right_of(b.yaw); bx, bz = bx + rx * sb, bz + rz * sb end
    end
    local x, y, z = lerp(ax, bx, t), lerp(a.y, b.y, t), lerp(az, bz, t)
    local yaw = lerp(a.yaw, b.yaw, t)
    return x, y, z, yaw, a, t
end
G.frame = frame
local function world_at(s, x, h, raw)
    local cx, cy, cz, yaw = frame(s, raw)
    local rx, rz = right_of(yaw)
    return vec3(cx + rx * x, cy + (h or 0), cz + rz * x), yaw
end
G.world_at = world_at
