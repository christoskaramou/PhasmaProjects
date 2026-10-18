------------------------------------------------------------------ world nodes
local function V(x, y, z) return vec3(x, y, z) end
G.shake = 0
local RIG = {
    int = { "int_body", "int_glass", "int_wheel", "int_gun" }, boat = { "boat_hull", "boat_deck" },
    civ = { "civ_body", "civ_glass", "civ_wheel" }, truck = { "truck_cab", "truck_box", "truck_wheel" }, van = { "van_box", "van_ramp", "truck_wheel" },
    sw = { "sw_body", "sw_glass", "civ_wheel", "sw_blade" }, rl = { "rl_body", "rl_glass", "rl_plate", "civ_wheel" },
    enf = { "enf_body", "enf_glass", "enf_wheel" }, eboat = { "eboat_hull", "eboat_deck" }, dumper = { "eboat_hull", "eboat_deck", "barrel" },
    heli = { "heli_body", "heli_glass", "heli_rotor" },
}
local ALLM = {}
for _, list in pairs(RIG) do for _, n in ipairs(list) do ALLM[n] = true end end
for _, n in ipairs({ "road", "curb", "water", "bank", "rail", "tree_trunk", "tree_top", "pine", "bush", "house_wall", "house_roof", "boathouse",
    "bullet", "missile", "bomb", "oil", "crater", "barrel", "torpedo", "shadow" }) do ALLM[n] = true end
local W = {}
local function build_world()
    W.ground = clone("ground", HIDE, V(90, 1, 90))
end
function G.reset_world() G.set_season(1) end
local function pose(list, x, y, h, yaw, roll)
    for _, mname in ipairs(list) do
        local n = P_get(mname); n:set_position(WP(x, y, h or 0)); n:set_rotation(V(0, yaw or 0, roll or 0))
    end
end
local function hash(i) local h = (i * 2654435761) % 4294967296; return (h % 10007) / 10007 end
local function slab(name, x0, x1, y, len, ang, h, sx)
    len = len * 1.1
    local n = P_get(name); n:set_position(WP((x0 + x1) / 2, y, (h or 0) + (floor(y / 2) % 2) * 0.0015)); n:set_scale(V((x1 - x0) * (sx or 1), 1, len)); n:set_rotation(V(0, ang, 0))
end
local function render_world(dt)
    for mname in pairs(ALLM) do P_begin(mname) end
    local P = G.P
    local cy = P.y
    W.ground:set_position(WP(P.x, cy + 10, 0))
    -- road / river slices (2 units each)
    local y0 = floor((cy - 12) / 2) * 2
    for y = y0, cy + 48, 2 do
        local cx, hw, isl, kind, si = G.course(y + 1)
        local ca, ha, ia = G.course(y)
        local cb, hb, ib = G.course(y + 2)
        local yc = y + 1
        -- each strip runs between its own edge positions at both ends of the slice, so curves and island
        -- splits stay continuous instead of stepping
        local function strip(name, fa0, fa1, h, sx)
            local x0a, x1a = fa0(ca, ha, ia), fa1(ca, ha, ia)
            local x0b, x1b = fa0(cb, hb, ib), fa1(cb, hb, ib)
            if x1a - x0a < 0.01 and x1b - x0b < 0.01 then return end
            local ang = -math.deg(math.atan(((x0b + x1b) - (x0a + x1a)) / 4))
            local w = ((x1a - x0a) + (x1b - x0b)) / 2
            local m = (x0a + x1a + x0b + x1b) / 4
            slab(name, m - w / 2, m + w / 2, yc, 2.04, ang, h, sx)
        end
        local L0 = function(c, h) return c - h end
        local R0 = function(c, h) return c + h end
        local IL = function(c, h, i) return c - i end
        local IR = function(c, h, i) return c + i end
        local off = function(f, d) return function(c, h, i) return f(c, h, i) + d end end
        local ang = -math.deg(math.atan((cb - ca) / 2))
        if kind == "river" then
            strip("water", L0, R0, 0)
            strip("bank", off(L0, -0.6), L0, 0.004); strip("bank", R0, off(R0, 0.6), 0.004)
            if isl > 0 then strip("bank", IL, IR, 0.004) end
        else
            if kind == "bridge" then
                slab("water", cx - 14, cx + 14, yc, 2.04, 0, -0.03)
                strip("rail", off(L0, -0.05), off(L0, 0.03), 0, 12); strip("rail", off(R0, -0.03), off(R0, 0.05), 0, 12)
            elseif kind == "dock" then
                strip("water", L0, R0, -0.05)
            end
            if isl > 0.05 or (ia or 0) > 0.05 or (ib or 0) > 0.05 then
                strip("road", L0, IL, 0.002); strip("road", IR, R0, 0.002)
                strip("curb", IL, off(IL, 0.15), 0.004); strip("curb", off(IR, -0.15), IR, 0.004)
            else strip("road", L0, R0, kind == "dock" and 0.02 or 0.002) end
            if kind ~= "bridge" then strip("curb", off(L0, -0.15), L0, 0.004); strip("curb", R0, off(R0, 0.15), 0.004) end
        end
        -- scenery beside the road (deterministic per slice)
        local idx = floor(y / 2)
        if kind ~= "bridge" then
            for s = -1, 1, 2 do
                local h = hash(idx * 2 + (s > 0 and 1 or 0))
                local x = cx + s * (hw + 1.6 + h * 7)
                if h < 0.55 then
                    local tp = h < 0.18 and "pine" or "tree"
                    if tp == "pine" then pose({ "pine" }, x, yc, 0, 0) else pose({ "tree_trunk", "tree_top" }, x, yc, 0, h * 900) end
                elseif h < 0.75 then pose({ "bush" }, x, yc, 0, h * 900)
                elseif h > 0.97 and kind == "road" then pose({ "house_wall", "house_roof" }, cx + s * (hw + 5.5), yc, 0, 0) end
            end
        end
        if kind == "dock" and G.course(y - 1) ~= nil then
            local _, _, _, kp = G.course(y - 1)
            if kp ~= "dock" then pose({ "boathouse" }, cx, y + 1, 0, 0) end
        end
    end
    -- drops
    for _, o in ipairs(G.DROPS) do
        if o.k == "oil" then
            -- the slick spreads out as it hits the road, then lies as a glossy puddle
            local n = P_get("oil"); local sp = 0.3 + 0.7 * (1 - (1 - clamp(o.t / 0.45, 0, 1)) ^ 3)
            n:set_position(WP(o.x, o.y, 0.01)); n:set_scale(V(sp, 1, sp)); n:set_rotation(V(0, o.rot or 0, 0))
        elseif o.k == "crater" then local n = P_get("crater"); n:set_position(WP(o.x, o.y, 0.012)); n:set_scale(V(1, 1, 1)); n:set_rotation(V(0, 0, 0))
        elseif o.k == "barrel" then local n = P_get("barrel"); n:set_position(WP(o.x, o.y, -0.12 + 0.04 * sin(o.t * 4))); n:set_rotation(V(o.t * 120, 0, 0))
        elseif o.k == "smoke" and o.t < 2.5 and rand() < 0.3 then G.smoke(WP(o.x + rr(-0.6, 0.6), o.y, 0.4), 2) end
    end
    -- vehicles
    for _, e in ipairs(G.EN) do
        local yaw = -math.deg(math.atan(e.vx * 0.06)) + (e.spin > 0 and e.t * 400 or 0)
        if e.k == "heli" then
            pose({ "heli_body", "heli_glass" }, e.x, e.y, 3.0, 180 + 8 * sin(e.t))
            local r = P_get("heli_rotor"); r:set_position(WP(e.x, e.y, 3.0)); r:set_rotation(V(0, G.t * 1400 % 360, 0))
            local sh = P_get("shadow"); sh:set_position(WP(e.x + 0.8, e.y - 0.6, 0.01)); sh:set_scale(V(0.95, 1, 1.25))
        else
            local h = (e.k == "eboat" or e.k == "dumper") and (-0.12 + 0.03 * sin(e.t * 5)) or 0
            pose(RIG[e.k], e.x, e.y, h, yaw)
            if e.k == "sw" and e.slash > 0 then for _, n in ipairs({ P_get("sw_blade"), P_get("sw_blade") }) do end end
            local sh = P_get("shadow"); local d = G.DIM[e.k] or G.DIM.civ
            sh:set_position(WP(e.x + 0.08, e.y - 0.08, 0.008)); sh:set_scale(V(d[1] * 2.2, 1, d[2] * 2.1))
        end
    end
    -- the Interceptor (flickers while protected)
    if (P.alive or G.phase == "dock") and G.phase ~= "dock" and (P.inv <= 0 or (G.t * 12) % 2 < 1.4) then
        local yaw = -math.deg(math.atan(P.vx * 0.05))
        -- dock swap: the boat settles into the water with a dip, the car rises out onto the ramp
        P.swap_t = (P.swap_t or 9) + dt
        local sw = clamp(P.swap_t / 0.45, 0, 1)
        if P.mode == "car" then pose(RIG.int, P.x, P.y, -0.12 * (1 - sw), yaw, P.vx * 1.2)
        else pose(RIG.boat, P.x, P.y, -0.12 + 0.03 * sin(G.t * 6) - 0.1 * sin(PI * sw) * (1 - sw * 0.5), yaw, P.vx * 2 + 6 * sin(PI * sw) * (1 - sw)) end
        local sh = P_get("shadow"); local d = G.pdim(); sh:set_position(WP(P.x + 0.08, P.y - 0.08, 0.008)); sh:set_scale(V(d[1] * 2.2, 1, d[2] * 2.1))
    end
    -- shots
    for _, s in ipairs(G.SHOTS) do local n = P_get(s.k); n:set_position(WP(s.x, s.y, 0)) end
    for _, s in ipairs(G.ESHOT) do local n = P_get(s.k); n:set_position(WP(s.x, s.y, s.k == "torpedo" and -0.15 or 0)); n:set_rotation(V(0, s.vx ~= 0 and 90 or 0, 0)) end
    for _, b in ipairs(G.BOMBS) do local n = P_get("bomb"); n:set_position(WP(b.x, b.y, 3.0 * (1 - b.t / b.T) + 0.1)) end
    for mname in pairs(ALLM) do P_end(mname) end
    G.sh_frame_fx(dt)
end

------------------------------------------------------------------ camera: high chase view up the road
local function update_camera(dt)
    local P = G.P
    local c = G.cam
    local cx = G.course(P.y + 6)
    local tx = lerp(cx, P.x, 0.55)
    local k = G.cam_snap and 1 or (1 - math.exp(-3 * dt)); G.cam_snap = false
    c.x = c.x + (tx - c.x) * k
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.3 * SET:shake_scale()
    cam:set_position(WP(c.x + a * sin(G.t * 53), P.y - 7.5 + a * cos(G.t * 61), 10.0))
    cam:look_at(WP(c.x, P.y + 4.2, 0))
end

------------------------------------------------------------------ collider debug overlay (F3)
G.DBG = { on = false, pool = {}, used = 0, w = 0.04 }
local DC = { me = { .2, 1, .3 }, enemy = { 1, .25, .2 }, civ = { .3, .8, 1 }, edge = { .4, .7, 1 }, shot = { 1, .9, .3 }, drop = { 1, .5, .1 } }
function G.dbg_bar(p0, p1, col)
    local D = G.DBG
    D.used = D.used + 1
    local b = D.pool[D.used]
    if not b then
        if #D.pool >= 2500 then return end
        b = { n = prim("cube", HIDE, V(1, 1, 1)), col = nil }
        D.pool[D.used] = b
    end
    if b.col ~= col then b.col = col; paint(b.n, { col[1] * .3, col[2] * .3, col[3] * .3 }, { col[1] * 1.4, col[2] * 1.4, col[3] * 1.4 }, 0.5, 0) end
    local dx, dy, dz = p1.x - p0.x, p1.y - p0.y, p1.z - p0.z
    local len = sqrt(dx * dx + dy * dy + dz * dz)
    b.n:set_position(V((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, (p0.z + p1.z) / 2))
    b.n:set_rotation(V(-math.deg(math.atan(dy / max(sqrt(dx * dx + dz * dz), 0.001))), math.deg(atan2(dx, dz)), 0))
    b.n:set_scale(V(D.w, D.w, len + D.w))
end
local function dbox(x, y, hx, hy, col, h)
    h = h or 0.5
    local a, b, c, d = WP(x - hx, y - hy, h), WP(x + hx, y - hy, h), WP(x + hx, y + hy, h), WP(x - hx, y + hy, h)
    G.dbg_bar(a, b, col); G.dbg_bar(b, c, col); G.dbg_bar(c, d, col); G.dbg_bar(d, a, col)
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and G.state ~= "title" then
        local P = G.P
        -- drivable edges
        for y = floor(P.y - 6), P.y + 30, 1 do
            local cx, hw, isl = G.course(y); local cx2, hw2, isl2 = G.course(y + 1)
            G.dbg_bar(WP(cx - hw, y, 0.1), WP(cx2 - hw2, y + 1, 0.1), DC.edge); G.dbg_bar(WP(cx + hw, y, 0.1), WP(cx2 + hw2, y + 1, 0.1), DC.edge)
            if isl > 0.05 then G.dbg_bar(WP(cx - isl, y, 0.1), WP(cx2 - isl2, y + 1, 0.1), DC.edge); G.dbg_bar(WP(cx + isl, y, 0.1), WP(cx2 + isl2, y + 1, 0.1), DC.edge) end
        end
        if P.alive then local d = G.pdim(); dbox(P.x, P.y, d[1], d[2], DC.me) end
        for _, e in ipairs(G.EN) do local d = G.DIM[e.k] or G.DIM.civ; dbox(e.x, e.y, d[1], d[2], (e.k == "civ" or e.k == "truck" or e.k == "van") and DC.civ or DC.enemy, e.k == "heli" and 3 or 0.5) end
        for _, s in ipairs(G.SHOTS) do G.dbg_bar(WP(s.x, s.py, 0.4), WP(s.x, s.y, 0.4), DC.shot) end
        for _, s in ipairs(G.ESHOT) do dbox(s.x, s.y, 0.1, 0.1, DC.enemy, 0.4) end
        for _, o in ipairs(G.DROPS) do if o.k ~= "smoke" then dbox(o.x, o.y, o.k == "oil" and 0.8 or 0.25, o.k == "oil" and 1.2 or 0.25, DC.drop, 0.1) end end
        for _, b in ipairs(G.BOMBS) do dbox(b.x, b.y, 0.7, 0.9, DC.enemy, 0.1) end
    end
    for i = D.used + 1, #D.pool do D.pool[i].n:set_position(HIDE) end
end
