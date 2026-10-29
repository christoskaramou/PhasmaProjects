------------------------------------------------------------------ static track + world builder (lane x -> world X = -x)
local TILE = 6
local function LX(x) return -x end
-- flat track markings: every class gets its own layer so no two of them (and none of them and the track top at
-- y=0) ever share a plane. Bottoms float 2 mm above the track, tops are 4 mm apart -> plenty for a D32F reverse-Z
-- depth buffer even at grazing angles; still far too thin to see as a step.
local DECAL = { ter = { 0.002, 0.022 }, crush = { 0.002, 0.026 }, warn = { 0.002, 0.030 }, finish = { 0.002, 0.034 }, slot = { 0.002, 0.038 } }
G.DECAL = DECAL
local function box(kind, x0, x1, y0, y1, z0, z1, rot)
    local n = P_get(kind)
    n:set_position(vec3(LX((x0 + x1) / 2), (y0 + y1) / 2, (z0 + z1) / 2))
    n:set_scale(vec3(abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)))
    n:set_rotation(vec3(0, rot or 0, 0))
    return n
end
local function put(kind, x, y, z, s, ry, sy)
    local n = P_get(kind)
    n:set_position(vec3(LX(x), y, z)); n:set_scale(vec3(s, sy or s, s)); n:set_rotation(vec3(0, ry or 0, 0))
    return n
end
G.LX, G.box, G.put = LX, box, put

local function tree(world, x, y, z, s)
    local w = world.key
    if w == "canyon" then
        if rand() < 0.55 then put("cactus", x, y, z, s * rr(0.9, 1.4), rr(0, 360)) else
            local ry = rr(0, 360); put("palm", x, y, z, s * 1.3, ry); put("fronds", x, y, z, s * 1.3, ry) end
    elseif w == "frost" then
        local k = s * rr(0.9, 1.5); put("pine", x, y, z, k, rr(0, 360))
        -- snowcap = top of a unit cone r = 1 - 0.95y grown 2.5% outward (gen_meshes.py); fitted to the pine's top cone
        -- (base r 0.8 at y 3.5, apex at 5.1) it wraps it 2-4 cm proud instead of crossing the 14-sided cone
        put("snowcap", x, y + 3.5 * k, z, 0.8 * k, 0, 1.6 / 1.0526 * k)
    elseif w == "ember" then
        if rand() < 0.5 then local ry = rr(0, 360); put("palm", x, y, z, s * 1.3, ry); put("fronds", x, y, z, s * 1.3, ry)
        else put("trunk", x, y, z, s, 0); put("foliage", x, y, z, s * rr(0.9, 1.2), rr(0, 360)) end
    else
        if rand() < 0.6 then put("trunk", x, y, z, s, 0); put("foliage", x, y, z, s * rr(0.9, 1.25), rr(0, 360))
        else put("pine", x, y, z, s * rr(0.9, 1.3), rr(0, 360)) end
    end
end

local function build_world(L, world)
    local zend = L.boss and (L.len + 80) or (L.len + 14 + 20 * 2.4 + 12)
    G.zend = zend
    -- sea (flat colour: reflections come from IBL/SSR), wide enough to reach the horizon
    box("c_water", -3000, 3000, -10.5, -9.0, -3000, 3500)
    -- islands with sandy rims, trees, rocks, bushes
    math.randomseed(1000 + L.idx * 77)
    local z = -60
    while z < zend + 160 do
        for side = -1, 1, 2 do
            if rand() < 0.85 then
                local r = rr(8, 17); local x = side * (W + 8 + r * rr(0.7, 1.6)); local zz = z + rr(-12, 12)
                local top = rr(-5.5, -2.5)
                -- grass ("island") and sand ("beach") are two layers of ONE dome mesh (tools/gen_meshes.py isl_dome): the
                -- grass cap is the dome top pushed out along its normal, so both MUST share this exact transform.
                -- (Before: two different ellipsoids, scaled/offset independently, crossed at a grazing angle -> jagged
                -- grass/sand interleaving that looked like z-fighting.)  rr() call order is unchanged = same layouts.
                local sy = r * 0.35
                local pos, scl = vec3(LX(x), top - 0.4 * sy, zz), vec3(r, sy, r * rr(0.8, 1.2))
                local rot = vec3(0, rr(0, 360), 0)
                for _, kind in ipairs({ "beach", "island" }) do
                    local n = P_get(kind); n:set_position(pos); n:set_scale(scl); n:set_rotation(rot)
                end
                -- props sit on the dome surface (dome: y = -1 + 1.4*sqrt(1-rho^2) in unit space, top at 0.4), so they no
                -- longer hover over the slope; rho uses the narrower horizontal axis -> props sink slightly, never float
                local rmin = r * math.min(1, scl.z / r)
                local function yt(d) local q = math.min(0.95, d / rmin); return top - sy * 1.4 * (1 - math.sqrt(1 - q * q)) end
                for i = 1, floor(rr(3, 7)) do
                    local a, d = rr(0, 6.28), rr(0, r * 0.6)
                    tree(world, x + cos(a) * d, yt(d) - 0.25, zz + sin(a) * d * 0.8, rr(0.9, 1.5))
                end
                for i = 1, 3 do
                    local a, d = rr(0, 6.28), rr(r * 0.3, r * 0.8)
                    if world.key == "canyon" or world.key == "ember" or rand() < 0.5 then put("rock", x + cos(a) * d, yt(d) - 0.3, zz + sin(a) * d * 0.8, rr(0.8, 1.8), rr(0, 360))
                    else put("bush", x + cos(a) * d, yt(d) - 0.2, zz + sin(a) * d * 0.8, rr(1.0, 1.8), rr(0, 360)) end
                end
            end
        end
        z = z + rr(34, 52)
    end
    -- far range: mountains (meadow/frost/ember) or mesas (canyon), placed ahead and to the sides
    -- cone meshes have one UV seam edge (local +X); if it lands exactly on the silhouette it renders as a thin
    -- dark diagonal across the sky, so every backdrop cone turns its seam straight away from the track
    local function seam_away(x, zz)
        -- mountain/snowcap/mesa meshes are now seamless (tools/gen_meshes.py stube), which removed the dark
        -- silhouette crack; this yaw choice is kept only so far-backdrop layouts stay identical.
        -- (old note) the cone's UV seam (local +X) showed as a dark line when it landed on the silhouette;
        -- the camera always looks down +z, so point the seam mostly along +z (away from the viewer)
        -- pick the yaw whose seam stays farthest from the silhouette for every camera that can see
        -- this mountain (run/stairs/win cameras sit on the track centre looking down +z)
        local wx, best, bestv = LX(x), 0, -1
        for deg = 0, 355, 5 do
            local t = math.rad(deg); local sx, sz = math.cos(t), math.sin(t)
            local worst = 2
            for cz = -30, zend + 10, 15 do
                local vx, vz = wx, zz - cz; local d = math.sqrt(vx * vx + vz * vz)
                if vz > 0 and math.abs(vx) < vz * 1.3 then
                    worst = math.min(worst, math.abs(sx * vx + sz * vz) / d)
                end
            end
            if worst > bestv then best, bestv = deg, worst end
        end
        return best
    end
    for i = 1, 26 do
        local a = rr(-1.25, 1.25); local d = rr(420, 900)
        local x, zz = sin(a) * d, zend * 0.5 + cos(a) * d
        local s = rr(60, 140)
        if world.key == "canyon" then
            put("mesa", x, -9.5, zz, s * 0.9, seam_away(x, zz), s * rr(0.35, 0.7)); rr(0, 1)
        else
            local hgt = s * rr(0.6, 0.95)
            local m = P_get("mountain"); m:set_position(vec3(LX(x), -9.5, zz)); m:set_scale(vec3(s, hgt, s)); m:set_rotation(vec3(0, seam_away(x, zz), 0)); rr(0, 1)
            if world.key ~= "ember" and hgt > 60 then local c = P_get("snowcap"); c:set_position(vec3(LX(x), -9.5, zz)); c:set_scale(vec3(s, hgt, s)); c:set_rotation(m:get_rotation()) end
        end
    end
    -- side islands near the start so the opening shot is framed
    math.randomseed(G.t * 1000 % 100000)
end

local function build_track(L)
    -- breakpoints: tiles + pit/bridge edges
    local zs = {}
    local z0, z1 = -24, L.len + 14
    if L.boss then z1 = L.len + 3 end
    for z = z0, z1, TILE do zs[#zs + 1] = z end
    zs[#zs + 1] = z1
    for _, e in ipairs(L.ev) do if e.t == "pit" or e.t == "bridge" then zs[#zs + 1] = e.z0; zs[#zs + 1] = e.z1 end end
    table.sort(zs)
    local ti = 0
    for i = 1, #zs - 1 do
        local a, b = zs[i], zs[i + 1]
        if b - a > 0.01 then
            ti = ti + 1
            local iv = floor_at(L, (a + b) / 2)
            local oil = false
            for _, e in ipairs(L.ev) do if e.t == "ter" and e.kind == "oil" and a < e.z1 and b > e.z0 then oil = true end end
            for _, s in ipairs(iv) do
                box((ti % 5 == 0) and "c_trk2" or "c_trk", s[1], s[2], -0.3, 0, a, b)
                box("c_side", s[1] + 0.05, s[2] - 0.05, -1.5, -0.25, a, b)
                -- rounded lips along every edge (rails only where the edge is the track border and not oily)
                for _, ex in ipairs({ s[1], s[2] }) do
                    local lip = P_get("railr"); lip:set_position(vec3(LX(ex), -0.15, (a + b) / 2)); lip:set_scale(vec3(0.16, 0.16, b - a))
                    if abs(abs(ex) - W) < 0.01 and not oil then
                        local r = P_get("railr"); r:set_position(vec3(LX(ex + (ex > 0 and 0.12 or -0.12)), 0.38, (a + b) / 2)); r:set_scale(vec3(0.11, 0.11, b - a))
                    end
                end
            end
        end
    end
    -- support pillars down into the sea
    for z = 0, z1, 30 do
        local iv = floor_at(L, z)
        if #iv > 0 then
            local c = (iv[1][1] + iv[#iv][2]) / 2
            local p = P_get("railr"); p:set_position(vec3(LX(c), -5.2, z)); p:set_scale(vec3(1.1, 1.1, 7.6)); p:set_rotation(vec3(90, 0, 0))
        end
    end
    -- pit / bridge hazard stripes along the drop edges
    for _, e in ipairs(L.ev) do
        if e.t == "pit" then
            box("c_warn", e.x0, e.x1, DECAL.warn[1], DECAL.warn[2], e.z0 - 0.7, e.z0)
            box("c_warn", e.x0, e.x1, DECAL.warn[1], DECAL.warn[2], e.z1, e.z1 + 0.7)
        elseif e.t == "bridge" then
            box("c_warn", e.x0, e.x1, DECAL.warn[1], DECAL.warn[2], e.z0 - 0.8, e.z0)
        elseif e.t == "ter" then
            local zz = e.z0
            while zz < e.z1 - 0.01 do
                local zb = min(e.z1, zz + 4.5)
                box("c_" .. e.kind, e.x0 + 0.02, e.x1 - 0.02, DECAL.ter[1], DECAL.ter[2], zz, zb)
                zz = zb
            end
            -- readable cue at the entry: a warning stripe
            box("c_warn", e.x0, e.x1, DECAL.warn[1], DECAL.warn[2], e.z0 - 0.5, e.z0)
        end
    end
    box("c_finish", -W, W, DECAL.finish[1], DECAL.finish[2], L.len - 1, L.len + 1)
    -- finale ground
    if L.boss then
        local a = L.len + 3
        box("c_stone", -W - 2, W + 2, -0.3, 0, a, a + 72)
        box("c_side", -W - 1.95, W + 1.95, -1.6, -0.25, a, a + 72)
        local p = P_get("railr"); p:set_position(vec3(0, -5.2, a + 30)); p:set_scale(vec3(2, 2, 7.6)); p:set_rotation(vec3(90, 0, 0))
        -- castle at the end
        local cz = a + 64
        for _, tx in ipairs({ -8, 8 }) do
            put("tower", tx, 0, cz, 1.2, 0); put("roof", tx, 0.4, cz, 1.2, 0)
            put("pole", tx, 12.4, cz, 1.3, 0)
            local f = put("flag", tx, 14.6, cz, 1.6, 0); G.flags = G.flags or {}; G.flags[#G.flags + 1] = f
        end
        box("c_stone", -6.5, 6.5, 0, 6.5, cz - 1, cz + 1)
        box("c_stone", -6.5, -2.2, 6.5, 7.4, cz - 1.1, cz + 1.1); box("c_stone", 2.2, 6.5, 6.5, 7.4, cz - 1.1, cz + 1.1)
        G.castle_gate = box("c_wood", -2.2, 2.2, 0, 4.8, cz - 1.2, cz - 1.0)
        box("c_gold", -2.6, 2.6, 4.8, 5.4, cz - 1.25, cz - 1.0)
    else
        local a = L.len + 14
        G.stairs = { z0 = a, n = 20, d = 2.4, h = 0.9 }
        for i = 1, 20 do
            local zz = a + (i - 1) * 2.4
            box("c_step" .. ((i - 1) % 5), -W, W, -1.5, i * 0.9, zz, zz + 2.4)
        end
        local top = a + 20 * 2.4
        box("c_step4", -W, W, -1.5, 20 * 0.9, top, top + 6)
        G.chest = put("chest", 0, 18, top + 3, 1.6, 0)
    end
end

local function build_level(L)
    P_reset()
    G.flags = {}; G.chest = nil; G.stairs = nil; G.castle_gate = nil
    local world = G.WORLDS[L.world]
    set_world(world)
    G.world = world
    build_world(L, world)
    build_track(L)
end
G.build_level = build_level
