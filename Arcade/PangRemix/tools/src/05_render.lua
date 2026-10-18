------------------------------------------------------------------ player rig (pivots match tools/gen_meshes.py)
local function V(x, y, z) return vec3(x, y, z) end
local function grp(parent, pos, meshes)
    local g = empty("grp", parent, pos)
    for _, m in ipairs(meshes) do clone(m, V(0, 0, 0), nil, g) end
    return g
end
local R = {}
local function build_player()
    local root = empty("Hero", nil, HIDE)
    R.root = root
    R.body = empty("body", root, V(0, 0, 0))           -- death pose pivot (keyframed in render_player)
    local B = R.body
    R.torso = grp(B, V(0, 1.0, 0), { "pl_shirt", "pl_trim", "pl_button", "pl_belt", "pl_buckle", "pl_shorts", "pl_pack", "pl_packflap", "pl_strap" })
    R.head = grp(B, V(0, 1.95, 0), { "pl_skin", "pl_eyew", "pl_eye", "pl_mouth", "pl_hair", "pl_helmet", "pl_hband" })
    R.arm_l = grp(B, V(0, 1.78, 0.38), { "pl_sleeve", "pl_hand" })
    R.arm_r = grp(B, V(0, 1.78, -0.38), { "pl_sleeve", "pl_hand" })
    R.leg_l = grp(B, V(0, 0.98, 0.16), { "pl_shortleg", "pl_leg", "pl_sock", "pl_boot", "pl_sole", "pl_lace" })
    R.leg_r = grp(B, V(0, 0.98, -0.16), { "pl_shortleg", "pl_leg", "pl_sock", "pl_boot", "pl_sole", "pl_lace" })
    R.gun = grp(B, V(0.3, 1.0, 0), { "pl_gun", "pl_gunwood" })
    R.shield = clone("shield_ring")
end
G.R = R
local AL = 1
local function ip(e) return lerp(e.ox or e.x, e.x, AL), lerp(e.oy or e.y, e.y, AL) end
G.vis = { yaw = -25, z = 0 }
local VIS = G.vis
local function render_player(dt)
    if G.hide_player then R.root:set_position(HIDE); R.shield:set_position(HIDE); return end
    local x, y = ip(P)
    local st = P.st
    local shooting = P.shoot_t > 0 and st ~= "dead"
    local yaw_t = (st == "climb") and 90 or (shooting and -90 or (P.face > 0 and -25 or 205))
    if yaw_t - VIS.yaw > 180 then VIS.yaw = VIS.yaw + 360 elseif VIS.yaw - yaw_t > 180 then VIS.yaw = VIS.yaw - 360 end
    VIS.yaw = damp(VIS.yaw, yaw_t, 22, dt)
    VIS.z = damp(VIS.z, st == "climb" and 0.9 or 0, 14, dt)
    local s = sin(P.ph)
    local ll, lr, al, ar, rz, rx, hz = 0, 0, 0, 0, 0, 0, 0
    local gpos, grot = V(0.32, 1.05, 0.05), -80
    if st == "walk" and abs(P.x - P.ox) > 0.001 then ll, lr, al, ar = 32 * s, -32 * s, -26 * s, 26 * s end
    if st == "climb" then al, ar = 150 + 25 * s, 150 - 25 * s; ll, lr = 30 * max(0, s), 30 * max(0, -s); gpos = V(-0.3, 1.2, 0) end
    if st == "fall" then ll, lr, al, ar = 20, -20, 60, 60 end
    if shooting or (P.weapon == "vulcan" and P.shoot_t > 0) then al, ar = 172, 172; gpos, grot = V(0.12, 2.35, 0), 0 end
    local piv = 0
    if st == "dead" then
        -- keyframed knock-back pose (timing shared with the arc in 04_sim): shock, flail through the spin, limp on the floor
        local t, kf, D = P.dead_t or 0, G.kf, G.DIE
        local d = P.die and P.die.d or 1
        rz = -d * kf(D.spin, t)
        local shock = 1 - kf({ { 0, 0 }, { 0.1, 0, "inout" }, { 0.3, 1 } }, t)               -- 1 during the hit-stop
        local limp = kf({ { 0, 0 }, { 0.9, 0, "inout" }, { 1.3, 1 } }, t)
        local fl = sin(t * 26) * (1 - limp) * (1 - shock)
        al = lerp(lerp(150 + 40 * fl, 165, shock), 100, limp); ar = lerp(lerp(140 - 40 * fl, 165, shock), 75, limp)
        ll = lerp(lerp(35 + 25 * fl, 40, shock), 12, limp); lr = lerp(lerp(-30 - 25 * fl, -40, shock), -6, limp)
        hz = 25 * fl
        piv = 1.25                                                                           -- spin about the body centre
        VIS.yaw = -90
    end
    if P.stun > 0 then hz = 18 * sin(G.t * 16) end
    local blink = (P.inv > 0 and st ~= "dead" and floor(G.t * 14) % 2 == 0)
    -- dead: root sits at the body centre so the spin turns about it; lift keeps the body above the floor at any angle
    local lift = piv > 0 and (piv * abs(cos(math.rad(rz))) + 0.42 * abs(sin(math.rad(rz)))) or 0
    R.root:set_position(blink and HIDE or V(x, y + lift, VIS.z))
    R.body:set_position(V(0, -piv, 0))
    R.root:set_rotation(V(rx, VIS.yaw, rz))
    R.leg_l:set_rotation(V(0, 0, ll)); R.leg_r:set_rotation(V(0, 0, lr))
    R.arm_l:set_rotation(V(0, 0, al)); R.arm_r:set_rotation(V(0, 0, ar))
    R.head:set_rotation(V(hz, 0, 0))
    R.gun:set_position(gpos); R.gun:set_rotation(V(0, 0, grot))
    if P.shield and st ~= "dead" then
        R.shield:set_position(V(x, y + 1.3, 0.2)); R.shield:set_scale(V(1.55, 1.75, 1.55)); R.shield:set_rotation(V(0, G.t * 120, 0))
    else R.shield:set_position(HIDE) end
end

------------------------------------------------------------------ balloons, wires, shots, items, animals (pooled each frame)
G.RINGS = {}
function G.ring_fx(x, y, r, col) G.RINGS[#G.RINGS + 1] = { x = x, y = y, r = r, t = 0 } end
local ITEM_MESH = { double = { "it_double" }, power = { "it_power" }, vulcan = { "it_vulcan" }, clock = { "it_clock", "it_hands" },
    hourglass = { "it_hourglass", "it_hg_frame" }, dynamite = { "it_dynamite", "it_fuse" }, shield = { "it_shield" }, life = { "it_life" } }
local FRUIT_MESH = { { "fr_cherry", "fr_stem" }, { "fr_apple", "fr_stem" }, { "fr_grape", "fr_stem" } }
local DYN = { "ball_red", "ball_blue", "ball_green", "ball_yellow", "ball_purple", "ball_shine", "shadow", "pop_ring", "wire", "wire_tip", "hook", "bullet",
    "it_double", "it_power", "it_vulcan", "it_clock", "it_hands", "it_hourglass", "it_hg_frame", "it_dynamite", "it_fuse", "it_shield", "it_life",
    "fr_cherry", "fr_stem", "fr_apple", "fr_grape", "cr_body", "cr_claw", "cr_legs", "cr_eye", "bd_body", "bd_beak", "bd_wing" }
local function shadow_y(x, y)
    local best = 0
    if ST then for _, k in ipairs(ST.blocks) do if k.live and x > k.x0 and x < k.x1 and k.y1 <= y + 0.01 and k.y1 > best then best = k.y1 end end end
    return best
end
local function render_dyn(dt)
    for _, k in ipairs(DYN) do P_begin(k) end
    local t = G.t
    for _, b in ipairs(BALLS) do
        local x, y = ip(b)
        local r = b.r
        local sq = 0
        if b.bounced then b.sq = 1; b.bounced = false end
        if b.sq then b.sq = max(0, b.sq - dt * 7); sq = b.sq * 0.12 end
        local n = P_get("ball_" .. b.col)
        n:set_position(V(x, y - r * sq, 0)); n:set_scale(V(r * (1 + sq), r * (1 - sq), r * (1 + sq)))
        local sh = P_get("ball_shine"); sh:set_position(V(x, y - r * sq, 0)); sh:set_scale(V(r, r * (1 - sq), r))
        local gy = shadow_y(x, y - r)
        local h = y - r - gy
        local ss = r * clamp(1.1 - h * 0.04, 0.35, 1.1)
        local d = P_get("shadow"); d:set_position(V(x, gy + 0.02, 0.2)); d:set_rotation(V(90, 0, 0)); d:set_scale(V(ss, ss * 0.6, 1))
    end
    for i = #G.RINGS, 1, -1 do
        local g = G.RINGS[i]; g.t = g.t + dt
        if g.t > 0.3 then table.remove(G.RINGS, i) else
            local k = g.t / 0.3; local s = g.r * (1 + 1.4 * k)
            local n = P_get("pop_ring"); n:set_position(V(g.x, g.y, 0.3)); n:set_scale(V(s, s, s * (1 - k) + 0.05))
        end
    end
    for _, r in ipairs(ROPES) do
        local tip = lerp(r.otip or r.tip, r.tip, AL)
        local y = r.y0
        while y < tip - 0.001 do
            local len = min(1, tip - y)
            local n = P_get("wire"); n:set_position(V(r.x, y, 0.3)); n:set_scale(V(2.2, len, 2.2))
            y = y + 1
        end
        local tipn = P_get(r.power and "hook" or "wire_tip"); tipn:set_position(V(r.x, tip, 0.3))
        if r.st == "stick" and r.t < 0.8 and floor(t * 12) % 2 == 0 then tipn:set_position(HIDE) end
    end
    for _, s in ipairs(SHOTS) do local n = P_get("bullet"); n:set_position(V(s.x, lerp(s.oy, s.y, AL), 0.3)) end
    for _, it in ipairs(ITEMS) do
        local vis = not (it.t > 5 and floor(t * 10) % 2 == 0)
        local ms = it.kind == "fruit" and FRUIT_MESH[it.fruit] or ITEM_MESH[it.kind]
        for _, m in ipairs(ms) do
            local n = P_get(m)
            n:set_position(vis and V(it.x, lerp(it.oy, it.y, AL) + 0.05, 0.3) or HIDE); n:set_rotation(V(0, 30 * sin(t * 2 + it.x), 0)); n:set_scale(V(1.15, 1.15, 1.15))
        end
    end
    for _, a in ipairs(ANIMALS) do
        local x, y = ip(a)
        local rz = a.st == "hit" and t * 600 or 0
        if a.kind == "crab" then
            local yaw = 15 * sin(t * 2)
            for _, m in ipairs({ "cr_body", "cr_claw", "cr_legs", "cr_eye" }) do
                local n = P_get(m); n:set_position(V(x, y + (m == "cr_legs" and 0 or 0.05 * abs(sin(t * 14))), 0.4)); n:set_rotation(V(0, yaw, rz)); n:set_scale(V(1.1, 1.1, 1.1))
            end
        else
            local yaw = a.vx > 0 and 0 or 180
            local b = P_get("bd_body"); b:set_position(V(x, y, 0.4)); b:set_rotation(V(0, yaw, rz))
            local bk = P_get("bd_beak"); bk:set_position(V(x, y, 0.4)); bk:set_rotation(V(0, yaw, rz))
            local f = 50 * sin(t * 16)
            local w1 = P_get("bd_wing"); w1:set_position(V(x, y + 0.1, 0.55)); w1:set_rotation(V(f, yaw, 0))
            local w2 = P_get("bd_wing"); w2:set_position(V(x, y + 0.1, 0.25)); w2:set_rotation(V(180 - f, yaw, 0))
        end
    end
    for _, k in ipairs(DYN) do P_end(k) end
end

------------------------------------------------------------------ camera
G.shake = 0
local function update_camera(dt)
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.45 * SET:shake_scale()
    local ox, oy = a * sin(G.t * 53), a * cos(G.t * 61)
    if G.cam_ov then local o = G.cam_ov; cam:set_position(V(o[1], o[2], o[3])); cam:look_at(V(o[4], o[5], o[6] or 0)); return end
    local sway = sin(G.t * 0.23) * 0.2
    cam:set_position(V(sway + ox, CAMY + 0.6 + oy, CAMZ)); cam:look_at(V(sway * 0.4 + ox * 0.5, CAMY + oy * 0.5, 0))
end

------------------------------------------------------------------ collider debug overlay (F3)
G.DBG = { on = false, pool = {}, used = 0, z = 3.0, w = 0.16 }
local DC = { floor = { .1, 1, 1 }, block = { 1, .9, .2 }, ladder = { .9, .6, .2 }, player = { .2, 1, .3 }, ball = { 1, .25, .2 }, rope = { 1, .6, .1 }, item = { 1, .4, .9 } }
function G.dbg_bar(x0, y0, x1, y1, col)
    local D = G.DBG
    D.used = D.used + 1
    local b = D.pool[D.used]
    if not b then
        if #D.pool >= 1500 then return end
        b = { n = prim("cube", HIDE, V(1, 1, 1)), col = nil }
        D.pool[D.used] = b
    end
    if b.col ~= col then b.col = col; paint(b.n, { col[1] * .3, col[2] * .3, col[3] * .3 }, { col[1] * 1.4, col[2] * 1.4, col[3] * 1.4 }, 0.5, 0) end
    local c = cam:get_position()
    local k = (c.z - D.z) / c.z
    local ax, ay = c.x + (x0 - c.x) * k, c.y + (y0 - c.y) * k
    local bx, by = c.x + (x1 - c.x) * k, c.y + (y1 - c.y) * k
    local dx, dy = bx - ax, by - ay
    b.n:set_position(V((ax + bx) * .5, (ay + by) * .5, D.z))
    b.n:set_rotation(V(0, 0, math.deg(atan2(dy, dx))))
    b.n:set_scale(V(sqrt(dx * dx + dy * dy) + D.w, D.w, D.w))
end
local function dbox(x0, y0, x1, y1, c) G.dbg_bar(x0, y0, x1, y0, c); G.dbg_bar(x1, y0, x1, y1, c); G.dbg_bar(x1, y1, x0, y1, c); G.dbg_bar(x0, y1, x0, y0, c) end
local function dcirc(x, y, r, c)
    local n = 16
    for i = 0, n - 1 do
        local a0, a1 = i / n * 2 * PI, (i + 1) / n * 2 * PI
        G.dbg_bar(x + r * cos(a0), y + r * sin(a0), x + r * cos(a1), y + r * sin(a1), c)
    end
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and ST then
        G.dbg_bar(X0, 0, X1, 0, DC.floor); G.dbg_bar(X0, 0, X0, CEIL, DC.floor); G.dbg_bar(X1, 0, X1, CEIL, DC.floor); G.dbg_bar(X0, CEIL, X1, CEIL, DC.floor)
        for _, k in ipairs(ST.blocks) do if k.live then dbox(k.x0, k.y0, k.x1, k.y1, DC.block) end end
        for _, l in ipairs(ST.ladders) do dbox(l.x - 0.75, l.y0, l.x + 0.75, l.y1, DC.ladder) end
        if P.st ~= "dead" then dbox(P.x - HB.pw, P.y + HB.py0, P.x + HB.pw, P.y + HB.py1, DC.player) end
        for _, b in ipairs(BALLS) do dcirc(b.x, b.y, b.r * HB.ball_k, DC.ball) end
        for _, r in ipairs(ROPES) do dbox(r.x - HB.rope, r.y0, r.x + HB.rope, r.tip, DC.rope) end
        for _, it in ipairs(ITEMS) do dbox(it.x - 0.6, it.y, it.x + 0.6, it.y + 1, DC.item) end
        for _, a in ipairs(ANIMALS) do dbox(a.x - 0.9, a.y, a.x + 0.9, a.y + 1, DC.ball) end
    end
    for i = D.used + 1, #D.pool do D.pool[i].n:set_position(HIDE) end
end
