------------------------------------------------------------------ road + ground: ring of slots, one per segment in view
local function V(x, y, z) return vec3(x, y, z) end
local NSLOT, AHEAD, BEHIND = 170, 160, 4
local SEGL, HALF, RUMB = G.TC.SEG, G.TC.HALF, G.TC.RUMB
local SLOTS = {}
local SLOT_KINDS = { "ground", "roadA", "roadB", "rumAl", "rumAr", "rumBl", "rumBr" }
local function build_slots()
    for _, k in ipairs(SLOT_KINDS) do
        SLOTS[k] = {}
        for i = 0, NSLOT - 1 do
            local mesh = (k == "ground") and "ground" or ((k == "roadA" or k == "roadB") and "road" or nil)
            if mesh then SLOTS[k][i] = { n = clone(mesh), g = nil }
            else SLOTS[k][i] = { r = clone("rumble_r"), w = clone("rumble_w"), g = nil } end
        end
    end
end
function G.invalidate_slots() for _, k in ipairs(SLOT_KINDS) do for i = 0, NSLOT - 1 do SLOTS[k][i].g = nil end end end
local function place(n, g, off, width, dy)
    local a, b = SG[g], G.seg_end(g)
    local rax, raz = right_of(a.yaw); local rbx, rbz = right_of(b.yaw)
    local x0, z0 = a.x + rax * off, a.z + raz * off
    local x1, z1 = b.x + rbx * off, b.z + rbz * off
    local dx, dy_, dz = x1 - x0, b.y - a.y, z1 - z0
    local len = sqrt(dx * dx + dz * dz)
    n:set_position(V(x0, a.y + (dy or 0), z0))
    n:set_rotation(V(-math.deg(math.atan(dy_ / max(len, 0.01))), math.deg(atan2(dx, dz)), 0))
    n:set_scale(V(width, 1, len + 0.12))
end
local function render_road(gcur)
    for g = max(1, gcur - BEHIND), gcur + AHEAD do
        local a, b = SG[g], SG[g + 1]
        if not a or not b then break end
        local i = g % NSLOT
        local gs = SLOTS.ground[i]
        if gs.g ~= g then
            gs.g = g
            -- z-fighting: every slot is stretched 12 cm past its segment end (closes wedge gaps on curves), so
            -- neighbouring slots overlap; on curves the 420 m ground slabs fan over each other far from the road.
            -- Equal heights there are coplanar and flicker. Give each slot its own millimetre layer instead:
            -- ground cycles 16 levels (pairs that share a level are 80 m apart), road/kerbs alternate per segment,
            -- and fork road B sits a layer above road A where the two overlap.
            place(gs.n, g, 0, 420, -0.06 - (g % 16) * 0.004)
            local offs = { 0 }
            if a.fork and a.fork > 0.01 then offs = { -a.fork, a.fork } end
            local red = (floor(g / 2) % 2 == 0)
            local lay = (g % 2) * 0.004
            local merged = a.fork and a.fork > 0.01 and a.fork < HALF + RUMB   -- roads still overlap: hide the inner kerbs
            for k, nm in ipairs({ "A", "B" }) do
                local rs = SLOTS["road" .. nm][i]
                local rl, rr_ = SLOTS["rum" .. nm .. "l"][i], SLOTS["rum" .. nm .. "r"][i]
                rs.g, rl.g, rr_.g = g, g, g
                local off = offs[k]
                if off then
                    local dy = lay + (k - 1) * 0.009
                    place(rs.n, g, off, HALF * 2, dy)
                    local on, offn = red and "r" or "w", red and "w" or "r"
                    rl[offn]:set_position(HIDE); rr_[offn]:set_position(HIDE)
                    if merged and k == 2 then rl[on]:set_position(HIDE) else place(rl[on], g, off - HALF - RUMB / 2, RUMB, dy) end
                    if merged and k == 1 then rr_[on]:set_position(HIDE) else place(rr_[on], g, off + HALF + RUMB / 2, RUMB, dy) end
                else
                    rs.n:set_position(HIDE); rl.r:set_position(HIDE); rl.w:set_position(HIDE); rr_.r:set_position(HIDE); rr_.w:set_position(HIDE)
                end
            end
        end
    end
end

------------------------------------------------------------------ scenery (assigned from per-mesh free lists while in view)
local OBJ_MESH = { palm = { "palm_trunk", "palm_leaves" }, pine = { "pine_trunk", "pine_leaves" }, pine_s = { "pine_trunk", "pine_snow" },
    bush = { "bush" }, rock = { "rock" }, cliff = { "cliff" }, cactus = { "cactus" }, column = { "column" }, vine = { "vine" }, lamp = { "lamp" },
    fence = { "fence" }, windmill = { "windmill", "blades" }, sign_l = { "sign_post", "sign_board" }, sign_r = { "sign_post", "sign_board_r" },
    start = { "arch", "ban_start", "flagman", "flag" }, check = { "arch", "ban_check" }, goal = { "arch", "ban_goal" } }
local FREE = {}
local function take(m)
    local f = FREE[m]; if f and #f > 0 then return table.remove(f) end
    return clone(m)
end
local function give(m, n) n:set_position(HIDE); FREE[m] = FREE[m] or {}; table.insert(FREE[m], n) end
local ACTIVE = {}
local function obj_meshes(o)
    if o.k == "bld" then return { "bld_" .. o.v, "roof" } end
    return OBJ_MESH[o.k] or { "rock" }
end
local function show_obj(o)
    local ms = obj_meshes(o)
    local a = SG[o.g]
    if not a then return end
    local rx, rz = right_of(a.yaw)
    local x, z = a.x + rx * o.x, a.z + rz * o.x
    o.nodes = {}
    local natural = not (o.arch or o.k == "sign_l" or o.k == "sign_r" or o.k == "lamp" or o.k == "fence" or o.k == "bld" or o.k == "vine")
    local yaw = a.yaw + (natural and o.ry or 0) + ((o.arch or o.k == "sign_l" or o.k == "sign_r") and 180 or 0)
    if o.k == "lamp" and o.x < 0 then yaw = yaw + 180 end
    for i, m in ipairs(ms) do
        local n = take(m); o.nodes[i] = { m = m, n = n }
        local px, pz = x, z
        if m == "flagman" or m == "flag" then local fx, fz = right_of(a.yaw); px, pz = x + fx * -11, z + fz * -11 end
        local s = 1
        if natural then s = 0.85 + 0.3 * ((o.v or 0) / 2) end
        if m == "roof" then s = ({ 0.85, 1.2, 0.7 })[(o.v or 0) + 1] end
        local py = a.y - 0.05
        if m == "roof" then py = py + ({ 14, 22, 9 })[(o.v or 0) + 1] - 9 end
        if m == "blades" then py = py + 8.6; o.blade = n end
        n:set_position(V(px, py, pz)); n:set_rotation(V(0, yaw, 0)); n:set_scale(V(s, s, s))
    end
    o.yaw = yaw
end
local function hide_obj(o) for _, e in ipairs(o.nodes or {}) do give(e.m, e.n) end; o.nodes = nil; o.blade = nil end
local function render_scenery(gcur)
    local seen = {}
    local lo, hi = gcur - BEHIND, gcur + AHEAD
    for si = max(1, #STAGES - 1), #STAGES do
        local st = STAGES[si]
        for _, o in ipairs(st.objs) do
            if o.g > hi then break end
            if o.g >= lo then
                seen[o] = true
                if not ACTIVE[o] then ACTIVE[o] = true; show_obj(o) end
                if o.blade then o.blade:set_rotation(V(0, o.yaw, G.t * 60)) end
            end
        end
    end
    for o in pairs(ACTIVE) do if not seen[o] then hide_obj(o); ACTIVE[o] = nil end end
end
function G.clear_scenery() for o in pairs(ACTIVE) do hide_obj(o); ACTIVE[o] = nil end end

------------------------------------------------------------------ the Testarossa rig
local function grp(parent, pos, meshes)
    local g = empty("grp", parent, pos)
    for _, m in ipairs(meshes) do clone(m, V(0, 0, 0), nil, g) end
    return g
end
local R = {}
local function build_car()
    R.root = empty("Car", nil, HIDE)
    R.body = grp(R.root, V(0, 0, 0), { "car_body", "car_under", "car_strake", "car_grille", "car_tail", "car_head", "car_glass", "car_frame",
        "car_seat", "car_cabin", "car_wheelin", "car_mirror", "drv_skin", "drv_hair", "pas_hair", "drv_shirt" })
    R.wheels = {}
    for _, w in ipairs({ { 0.86, 1.42, true }, { -0.86, 1.42, true }, { 0.88, -1.38 }, { -0.88, -1.38 } }) do
        local hub = empty("hub", R.root, V(w[1], 0.34, w[2]))
        local spin = grp(hub, V(0, 0, 0), { "car_tire", "car_rim" })
        R.wheels[#R.wheels + 1] = { hub = hub, spin = spin, front = w[3] }
    end
    R.shadow = clone("car_shadow")
    R.wrot = 0
end
local AL = 1
local function car_pose(dt)
    local s = lerp(P.os or P.s, P.s, AL)
    local x = lerp(P.ox or P.x, P.x, AL)
    local p, yaw = world_at(s, x, 0)
    local a = seg_at(s)
    local pitch = 0
    if a then pitch = -math.deg(math.atan(a.dy / SEGL)) end
    return p, yaw, pitch, s, x
end
G.car_pose = car_pose
-- ground FX colours per theme ground texture: { dust cloud, thrown grit }
local GROUND_FX = {
    grass = { { .34, .36, .22 }, { .3, .55, .16 } }, vine = { { .36, .34, .22 }, { .32, .5, .16 } }, lake = { { .32, .36, .24 }, { .3, .52, .2 } },
    dark = { { .3, .32, .24 }, { .24, .42, .16 } }, wheat = { { .62, .54, .32 }, { .8, .68, .3 } }, beach = { { .7, .64, .5 }, { .9, .82, .62 } },
    desert = { { .7, .58, .4 }, { .85, .7, .45 } }, dry = { { .6, .52, .38 }, { .7, .6, .42 } }, canyon = { { .62, .42, .3 }, { .72, .45, .3 } },
    alps = { { .75, .78, .82 }, { .95, .97, 1 } }, town = { { .45, .44, .42 }, { .55, .54, .5 } },
}
-- car-local point -> world (engine yaw: +Z forward rotates toward +X for positive degrees)
local function car_pt(p, ry, lx, ly, lz)
    local r = math.rad(ry); local c, s = cos(r), sin(r)
    return p.x + lx * c + lz * s, p.y + ly, p.z - lx * s + lz * c
end
local FXS = { tire = 0, dirt = 0, exh = 0, wreck = 0 }
local DEB = {}
function G.crash_fx(p, yaw, v)
    local r = math.rad(yaw); local fx, fz = sin(r), cos(r)
    local cv = { fx * v * 0.35, 1.5, fz * v * 0.35 }
    FX.flash(p.x, p.y, p.z, 3, { 0.8, 0.65, 0.5 })
    FX.sparks(p.x, p.y - 0.3, p.z, 40, cv, 16)
    FX.ring(p.x, p.y - 0.55, p.z, 6, { 0.5, 0.48, 0.45 }, true)
    FX.smoke(p.x, p.y, p.z, 1.5, cv, 0.24, 1.8)
    FX.dust(p.x, p.y - 0.4, p.z, { .3, .29, .27 }, 1.5, cv, 2)
    FX.emit("soft", p.x, p.y, p.z, { n = 14, vel = cv, c0 = { 1.2, 1.15, 1.0 }, c1 = { 0.2, 0.2, 0.25 }, s0 = 0.04, s1 = 0.1, l0 = 0.5, l1 = 1.0, r = 0.6, sp = 8, drag = 0.6, grav = { 0, -12, 0 } })  -- glass
    -- body-panel and trim shards: real meshes so they can be dark, tumbling with gravity and a bounce
    for i = 1, 12 do
        local d = DEB[i]
        if not d then d = { n = clone((i % 3 == 0) and "deb_dark" or "deb_red") }; DEB[i] = d end
        local a = rand() * 2 * PI
        d.x, d.y, d.z, d.floor = p.x, p.y, p.z, p.y - 0.6
        d.vx, d.vy, d.vz = fx * v * (0.25 + rand() * 0.35) + cos(a) * (3 + rand() * 6), 4 + rand() * 7, fz * v * (0.25 + rand() * 0.35) + sin(a) * (3 + rand() * 6)
        d.rx, d.ry, d.rz = rand() * 360, rand() * 360, rand() * 360
        d.wx, d.wy, d.wz = (rand() - 0.5) * 1400, (rand() - 0.5) * 1400, (rand() - 0.5) * 1400
        d.t = 0; d.life = 2.4 + rand() * 0.8
        local s = 0.7 + rand() * 0.8; d.n:set_scale(V(s, s, s))
    end
    FXS.wreck = 2.8
end
local function update_debris(dt)
    for _, d in ipairs(DEB) do
        if d.t and d.t < d.life then
            d.t = d.t + dt
            d.vy = d.vy - 18 * dt
            local k = math.exp(-0.6 * dt); d.vx, d.vz = d.vx * k, d.vz * k
            d.x, d.y, d.z = d.x + d.vx * dt, d.y + d.vy * dt, d.z + d.vz * dt
            if d.y < d.floor then
                d.y = d.floor; d.vy = -d.vy * 0.35; d.vx, d.vz = d.vx * 0.6, d.vz * 0.6; d.wx, d.wy, d.wz = d.wx * 0.5, d.wy * 0.5, d.wz * 0.5
                if abs(d.vy) > 2 then FX.emit("dust", d.x, d.y, d.z, { n = 1, c0 = { .3, .3, .28 }, s0 = .3, s1 = .5, l0 = .3, l1 = .6, r = .1, sp = 1 }) end
            end
            d.rx, d.ry, d.rz = d.rx + d.wx * dt, d.ry + d.wy * dt, d.rz + d.wz * dt
            d.n:set_position(V(d.x, d.y, d.z)); d.n:set_rotation(V(d.rx, d.ry, d.rz))
            if d.t >= d.life then d.n:set_position(HIDE) end
        end
    end
end
function G.hide_debris() for _, d in ipairs(DEB) do d.t = nil; d.n:set_position(HIDE) end; FXS.wreck = 0 end
local function car_fx(dt, p, ry)
    local v = P.v
    local r = math.rad(ry); local fx, fz = sin(r), cos(r)
    local drive = P.st == "drive" or P.st == "timeup" or P.st == "spin"
    local onroad = P.surf ~= "off"
    -- tyre smoke from both rear contact patches: power slides, hard cornering, heavy braking, spins
    local tk = 0
    if drive and v > 12 and onroad then
        if P.skid or P.st == "spin" then tk = 1
        elseif abs(P.slip or 0) > 8 then tk = 0.75
        elseif P.brk and v > 25 then tk = 0.6
        elseif abs(P.steer) > 0.85 and v > 55 then tk = 0.35 end
    end
    FXS.tire = FXS.tire - dt
    if tk > 0 and FXS.tire <= 0 then
        FXS.tire = 0.045
        local cv = { fx * v * 0.78, 0.8, fz * v * 0.78 }   -- dragged along behind the car, then left hanging
        for _, side in ipairs({ 0.95, -0.95 }) do
            local x, y, z = car_pt(p, ry, side, 0.25, -1.6)
            FX.smoke(x, y, z, tk * 1.15, cv, 0.42, 1.35)
        end
    end
    -- off-road: theme-coloured dust cloud + thrown clods/clippings/snow from the rear wheels
    FXS.dirt = FXS.dirt - dt
    if drive and not onroad and v > 4 and FXS.dirt <= 0 then
        FXS.dirt = 0.05
        local a = seg_at(P.s); local gk = a and a.st and a.st.th and a.st.th.ground or "grass"
        local gc = GROUND_FX[gk] or GROUND_FX.grass
        local k = clamp(v / 50, 0.3, 1.2)
        local cv = { fx * v * 0.4, 1.2, fz * v * 0.4 }
        for _, side in ipairs({ 0.9, -0.9 }) do
            local x, y, z = car_pt(p, ry, side, 0.2, -1.5)
            FX.dust(x, y, z, gc[1], k, cv, 1.0 + 0.5 * k)
            FX.grit(x, y, z, gc[2], 3, { fx * v * 0.3, 3.5, fz * v * 0.3 })
        end
    end
    -- exhaust: twin tailpipes, visible puffs under throttle at low speed, a pop + flame on every gear change
    FXS.exh = FXS.exh - dt
    if drive and FXS.exh <= 0 then
        FXS.exh = (P.gas and v < 30) and 0.06 or 0.12
        local k = (P.gas and 1 or 0.35) * clamp(1.2 - v / 80, 0.25, 1)
        for _, side in ipairs({ 0.55, -0.55 }) do
            local x, y, z = car_pt(p, ry, side, 0.36, -2.35)
            FX.emit("smoke", x, y, z, { n = 1, vel = { fx * v * 0.8 - fx * 2, 0.4, fz * v * 0.8 - fz * 2 }, c0 = { .2 * k, .2 * k, .21 * k }, c1 = { 0, 0, 0 },
                s0 = .18, s1 = .35, l0 = .35, l1 = .7, r = .03, sp = .6, drag = 3, grav = { 0, .6, 0 } })
        end
    end
    if P.pop then
        P.pop = false
        for _, side in ipairs({ 0.55, -0.55 }) do
            local x, y, z = car_pt(p, ry, side, 0.36, -2.4)
            local cv = { fx * v * 0.9 - fx * 6, 0.2, fz * v * 0.9 - fz * 6 }
            FX.emit("fire", x, y, z, { n = 3, vel = cv, c0 = { 1.8, 1.0, .4 }, c1 = { .2, .03, 0 }, s0 = .25, s1 = .45, l0 = .08, l1 = .16, r = .02, sp = 1, drag = 4 })
            FX.emit("smoke", x, y, z, { n = 2, vel = cv, c0 = { .3, .3, .3 }, c1 = { 0, 0, 0 }, s0 = .3, s1 = .5, l0 = .4, l1 = .8, r = .05, sp = 1, drag = 3, grav = { 0, .7, 0 } })
        end
    end
    -- wreck: smoke pouring off the tumbling car, plus a few licks of flame early on
    if FXS.wreck > 0 then
        FXS.wreck = FXS.wreck - dt
        FXS.wk = (FXS.wk or 0) - dt
        if FXS.wk <= 0 then
            FXS.wk = 0.09
            local k = clamp(FXS.wreck / 2.8, 0.2, 1)   -- screen-blended puffs add up: keep each one dim
            FX.smoke(p.x, p.y + 0.8, p.z, 0.6 * k, { 0, 1.4, 0 }, 0.2, 1.6)
            if FXS.wreck > 2.0 and rand() < 0.35 then FX.fire(p.x, p.y + 0.6, p.z, 0.4, 0.5) end
        end
    end
    update_debris(dt)
end
local function render_car(dt)
    local p, yaw, pitch = car_pose(dt)
    -- body slip: in a power slide the nose points INTO the bend and the tail swings OUT (centrifugal side).
    -- Engine yaw is positive toward +X = screen left, while steer > 0 moves the car right (right_of = -X), so
    -- the steering yaw must be subtracted (it used to be added, which pointed the nose out and the tail in).
    local tgt = 0
    if (P.st == "drive" or P.st == "timeup") and P.v > 30 and abs(P.drift or 0) > 5 and P.steer * (P.drift or 0) < 0 then
        tgt = (P.drift > 0 and 1 or -1) * clamp((abs(P.drift) - 5) * 1.4, 0, 20) * clamp(abs(P.steer) * 1.3, 0, 1)
    end
    P.slip = clamp(damp(P.slip or 0, tgt, (tgt ~= 0) and 3.5 or 6, dt), -25, 25)
    if abs(P.slip) < 1e-3 then P.slip = 0 end   -- never decay into denormals
    local roll = -P.steer * 2.5 * clamp(P.v / 60, 0, 1) - (P.slip or 0) * 0.12
    local ry, rx, rz, lift = yaw - P.steer * 6 + P.slip, pitch, roll, 0
    if P.st == "spin" then ry = ry + P.t / 1.4 * 720 end
    if P.st == "crash" then
        local t = clamp(P.t / 1.6, 0, 1)
        lift = math.sin(PI * t) * 3.2
        rz = rz + t * 540; rx = rx + t * 180
        if P.t > 1.6 then rz, rx, lift = 0, pitch, 0 end
    end
    R.root:set_position(V(p.x, p.y + lift, p.z)); R.root:set_rotation(V(rx, ry, rz))
    R.wrot = R.wrot + P.v * dt / 0.34 * 57.3
    for _, w in ipairs(R.wheels) do
        -- front wheels follow the steering (same sign fix) and counter-steer against the slide
        w.hub:set_rotation(V(0, w.front and (-P.steer * 22 - P.slip * 0.7) or 0, 0))
        w.spin:set_rotation(V(R.wrot, 0, 0))
    end
    R.shadow:set_position(V(p.x, p.y + 0.03, p.z)); R.shadow:set_rotation(V(pitch, yaw, 0))
    car_fx(dt, V(p.x, p.y + lift, p.z), (P.st == "crash") and yaw or ry)
    return p, yaw
end

------------------------------------------------------------------ traffic
local TMESH = { beetle = { "tr_beetle", "tr_glass", "tr_lamp" }, vette = { "tr_vette", "tr_glass", "tr_lamp" }, truck = { "tr_cab", "tr_box", "tr_wind", "tr_lamp" } }
local DYN = { "tr_beetle", "tr_vette", "tr_cab", "tr_box", "tr_glass", "tr_wind", "tr_lamp", "car_tire" }
local function render_traffic(dt)
    for _, k in ipairs(DYN) do P_begin(k) end
    for _, c in ipairs(CARS) do
        local s = lerp(c.os or c.s, c.s, AL)
        local p, yaw = world_at(s, car_x(c), 0)
        for _, m in ipairs(TMESH[c.k]) do local n = P_get(m); n:set_position(p); n:set_rotation(V(0, yaw, 0)); n:set_scale(V(1, 1, 1)) end
        c.wr = (c.wr or 0) + c.v * dt / 0.34 * 57.3
        local rx, rz = right_of(yaw); local fx, fz = math.sin(math.rad(yaw)), math.cos(math.rad(yaw))
        local L = (c.k == "truck") and 2.6 or 1.3
        for _, w in ipairs({ { 0.8, L }, { -0.8, L }, { 0.8, -L }, { -0.8, -L } }) do
            local n = P_get("car_tire")
            n:set_position(V(p.x + rx * w[1] + fx * w[2], p.y + 0.34, p.z + rz * w[1] + fz * w[2])); n:set_rotation(V(c.wr, yaw, 0)); n:set_scale(V(1, 1, 1))
        end
    end
    for _, k in ipairs(DYN) do P_end(k) end
    for _, c in ipairs(CARS) do c.os = c.s end
end

------------------------------------------------------------------ camera, horizon and the far plane
G.shake = 0
local CAMV = { y = 3 }
local function update_camera(dt, carp, yaw)
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.35 * SET:shake_scale()
    if G.cam_ov then
        local o = G.cam_ov; G.cam.pos = V(o[1], o[2], o[3]); G.cam.look = V(o[4], o[5], o[6])
    else
        local fx, fz = math.sin(math.rad(yaw)), math.cos(math.rad(yaw))
        local s = lerp(P.os or P.s, P.s, AL)
        local _, ry = frame(max(0, s - 7.5))
        CAMV.y = damp(CAMV.y, ry + 2.75, 8, dt)
        local cx, cz = carp.x - fx * 7.6, carp.z - fz * 7.6
        G.cam.pos = V(cx + a * sin(G.t * 53), CAMV.y + a * cos(G.t * 61), cz)
        local _, ly = frame(s + 14)
        G.cam.look = V(carp.x + fx * 12, max(ly, carp.y) + 1.1, carp.z + fz * 12)
    end
    cam:set_position(G.cam.pos); cam:look_at(G.cam.look)
    if G.trace and #G.trace < 4000 then local cp = G.cam.pos; G.trace[#G.trace + 1] = { G.t, cp.x, cp.z, P.s, P.x, AL } end   -- MCP test hook
    local c = G.cam.pos
    G.hz:set_position(V(c.x, c.y - 70, c.z))
    -- far plane (fills the view beyond the ground slabs): it used to sit 1.2 m under the road at the CAR, so any road
    -- ahead that dropped more than ~0.7 m below the car (every downhill, a crest with a dip behind it) went under its
    -- top face and was painted over by a flat green band. Keep it under the lowest road in view instead.
    if G.farplane then
        local g0 = floor(lerp(P.os or P.s, P.s, AL) / SEGL) + 1
        local lo = math.huge
        for g = max(1, g0 - BEHIND), g0 + AHEAD do local sg = SG[g]; if not sg then break end; if sg.y < lo then lo = sg.y end end
        if lo == math.huge then lo = c.y - 3 end
        G.far_y = (G.far_y and G.far_y < lo - 1.6) and damp(G.far_y, lo - 2.0, 1.5, dt) or (lo - 2.0)   -- drop at once, rise slowly
        G.farplane:set_position(V(c.x, G.far_y, c.z))
    end
end
local function build_world()
    build_slots()
    G.hz = clone("horizon", V(0, 0, 0), V(2600, 1400, 2600))
    G.farplane = prim("cube", V(0, -2, 0), V(9000, 1, 9000)); paint(G.farplane, { .3, .5, .22 }, { 0, 0, 0 }, 1, 0)
end

------------------------------------------------------------------ collider debug overlay (F3)
G.DBG = { on = false, pool = {}, used = 0, w = 0.14 }
local DC = { edge = { .2, .9, 1 }, car = { .2, 1, .3 }, traffic = { 1, .25, .2 }, obj = { 1, .8, .2 } }
function G.dbg_bar(p0, p1, col)
    local D = G.DBG
    D.used = D.used + 1
    local b = D.pool[D.used]
    if not b then
        if #D.pool >= 1500 then return end
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
local function dbox(s, x, hw, hl, col, raw)
    local h = 0.4
    local a, b, c, d = world_at(s - hl, x - hw, h, raw), world_at(s - hl, x + hw, h, raw), world_at(s + hl, x + hw, h, raw), world_at(s + hl, x - hw, h, raw)
    G.dbg_bar(a, b, col); G.dbg_bar(b, c, col); G.dbg_bar(c, d, col); G.dbg_bar(d, a, col)
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and SG[1] then
        local s0 = P.s
        for k = -2, 30 do
            local s = s0 + k * 4
            local a = seg_at(s)
            local offs = { 0 }
            if a and a.fork then offs = a.st.side and { 0, -2 * a.st.side * a.fork } or { -a.fork, a.fork } end
            for _, o in ipairs(offs) do
                for _, e in ipairs({ -HALF - RUMB, HALF + RUMB }) do G.dbg_bar(world_at(s, o + e, 0.3), world_at(s + 4, o + e, 0.3), DC.edge) end
            end
        end
        dbox(P.s, P.x, G.CONST.CAR_HW, G.CONST.CAR_HL, DC.car)
        for _, c in ipairs(CARS) do
            if abs(c.s - P.s) < 160 then dbox(c.s, car_x(c), (c.k == "truck") and 1.2 or 0.9, (c.k == "truck") and 3.4 or 2.1, DC.traffic) end
        end
        local g = floor(P.s / SEGL) + 1
        for si = max(1, #STAGES - 1), #STAGES do
            for _, o in ipairs(STAGES[si].objs) do
                if o.g > g + 30 then break end
                if o.g >= g - 2 then
                    local s = (o.g - 1) * SEGL
                    if o.arch then for _, px in ipairs({ -12.5, 12.5 }) do dbox(s, px, 0.7, 1.0, DC.obj, true) end
                    else dbox(s, o.x, OBJ_HW[o.k] or 1, 1.0, DC.obj, true) end
                end
            end
        end
    end
    for i = D.used + 1, #D.pool do D.pool[i].n:set_position(HIDE) end
end
