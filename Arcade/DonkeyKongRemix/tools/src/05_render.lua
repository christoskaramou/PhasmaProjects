------------------------------------------------------------------ rendering (interpolated between sim steps)
local AL = 1
local function ip(e) return lerp(e.ox or e.x, e.x, AL), lerp(e.oy or e.y, e.y, AL) end
G.vis = { mz = 0, myaw = -20, ham = 10, kyaw = 0 }
local VIS = G.vis
local EMIT = {}
local function build_fx()
    EMIT.drum = new_emitter({ c0 = vec4(2.4, 1.0, .25, 1), c1 = vec4(.8, .2, .05, 0), vel = vec3(0, 2.2, 0), radius = 0.45, smin = .1, smax = .26, lmin = .25, lmax = .6, noise = 2.5, drag = 1.2, count = 300 })
    EMIT.smoke = new_emitter({ c0 = vec4(.25, .22, .2, .35), c1 = vec4(.15, .14, .13, 0), vel = vec3(0, 1.6, 0), radius = 0.4, smin = .25, smax = .5, lmin = .8, lmax = 1.6, noise = 1.5, drag = .6, count = 200 })
    for _, r in ipairs(RIGS.fire) do r.em = new_emitter({ c0 = vec4(2.2, 1.1, .25, 1), c1 = vec4(.8, .25, .05, 0), vel = vec3(0, 1.6, 0), radius = 0.3, smin = .06, smax = .15, lmin = .15, lmax = .35, noise = 2, count = 120 }) end
    for _, r in ipairs(RIGS.fox) do r.em = new_emitter({ c0 = vec4(2.2, .6, .15, 1), c1 = vec4(.7, .1, .03, 0), vel = vec3(0, 1.6, 0), radius = 0.3, smin = .06, smax = .15, lmin = .15, lmax = .35, noise = 2, count = 120 }) end
    G.held = rig_pool(1, { "b_wood", "b_hoop" })[1]
    G.held_spring = rig_pool(1, { "spring" })[1]
    G.intro_lad = { clone("ladder"), clone("ladder") }
end
local function render_mario(dt)
    local r = RIGS.mario
    if M.st == "hidden" then r.root:set_position(HIDE); return end
    local x, y = ip(M)
    local climbing = M.st == "climb"
    VIS.mz = damp(VIS.mz, climbing and 0.8 or 0, 14, dt)
    local yaw_t = climbing and 90 or (M.face > 0 and -20 or 200)
    VIS.myaw = damp(VIS.myaw, yaw_t, 18, dt)
    local o = { pos = V(WX(x), WY(y), VIS.mz), yaw = VIS.myaw }
    local s = sin(M.ph * 1.4)
    if M.st == "walk" then
        local moving = abs(M.x - M.ox) > 0.05
        local a = moving and 32 or 0
        o.ll, o.lr, o.al, o.ar = a * s, -a * s, -a * 0.8 * s, a * 0.8 * s
        o.pos = V(WX(x), WY(y) + (moving and abs(s) * 0.05 or 0), VIS.mz)
    elseif climbing then
        o.al, o.ar = 150 + 25 * s, 150 - 25 * s
        o.ll, o.lr = 30 * max(0, s), 30 * max(0, -s)
    elseif M.st == "jump" or M.st == "fall" then
        o.ll, o.lr, o.al, o.ar = 28, -18, 160, -25
    elseif M.st == "dead" then
        local f = M.dead_f or 0
        if f < 70 then o.yaw = VIS.myaw + f * 21; o.al, o.ar = 60, 60
        else o.yaw = -20; o.rz = 90; o.pos = V(WX(x) - 0.9, WY(y) + 0.32, 0.2); o.al, o.ar = 160, 20 end
    elseif M.st == "win" then
        o.yaw = 15; o.al, o.ar = 0, 0
    end
    if M.ham > 0 and M.st ~= "dead" then
        local up = floor(M.hph / 9) % 2 == 0
        VIS.ham = damp(VIS.ham, up and 8 or -100, 30, dt)
        o.ham = VIS.ham
        o.al = up and 165 or 75; o.ar = o.al
        if M.ham < 120 and floor(M.ham / 6) % 2 == 0 then o.ham = nil end
    end
    pose_mario(r, o)
end
local function render_kong(dt)
    local r = RIGS.dk
    if G.kong_hidden then r.root:set_position(HIDE); return end
    local x, y = ip(KONG)
    local t = G.t
    local o = { pos = V(WX(x), WY(y), -0.25), s = 1 }
    local st = KONG.st
    local yaw_t = 0
    o.alx, o.arx = -8 + 4 * sin(t * 2), -8 + 4 * sin(t * 2 + 1)
    o.alz, o.arz = -10, 10
    o.bob = 0.04 * sin(t * 3)
    if st == "beat" then
        local b = sin(t * 18)
        o.alx = -75 + 25 * b; o.arx = -75 - 25 * b; o.alz, o.arz = 30, -30; o.hx = -10
    elseif st == "grab" then yaw_t = -70; o.alx, o.arx = -60, -60; o.lean = 18
    elseif st == "hold" then yaw_t = 0; o.alx, o.arx = -175, -175; o.alz, o.arz = 12, -12
    elseif st == "throw" then yaw_t = 70; o.alx, o.arx = -85, -85; o.lean = 15
    elseif st == "walk" then
        local s = sin(t * 7)
        yaw_t = KONG.dir * 35; o.llx, o.lrx = 22 * s, -22 * s; o.alx, o.arx = -22 * s, 22 * s; o.bob = abs(s) * 0.12
    elseif st == "climb" then
        local s = sin(t * 7)
        yaw_t = 180; o.alx, o.arx = -165 + 20 * s, -165 - 20 * s; o.llx, o.lrx = -30 * max(0, s), -30 * max(0, -s)
    elseif st == "hop" then o.alx, o.arx = -150, -150; o.alz, o.arz = 30, -30; o.llx, o.lrx = -25, -25
    elseif st == "grin" then o.alz, o.arz = -40 + 10 * sin(t * 6), 40 - 10 * sin(t * 6); o.hz = 8 * sin(t * 5)
    elseif st == "fall" then o.rx = 180; o.pos = V(WX(x), WY(y) + 4.2, -0.25); o.alz, o.arz = -120 + 30 * sin(t * 14), 120 - 30 * sin(t * 14); o.llx, o.lrx = 40 * sin(t * 12), -40 * sin(t * 12)
    elseif st == "dazed" then o.rx = 180; o.pos = V(WX(x), WY(y) + 4.1, -0.25); o.alz, o.arz = -95, 95; o.hy = 25 * sin(t * 4) end
    VIS.kyaw = damp(VIS.kyaw, KONG.yaw_ov or yaw_t, 10, dt)
    o.yaw = VIS.kyaw
    pose_dk(r, o)
    -- barrel / spring in his hands
    local hb = G.held
    if ST and ST.kind == "25" and (st == "grab" or st == "hold") and not G.cut then
        local hx, hy = WX(x), WY(y) + (st == "hold" and 5.1 or 1.8)
        local hz = st == "grab" and 0.9 or 0.2
        if st == "grab" then hx = hx - 1.6 end
        hb.root:set_position(V(hx, hy, hz)); hb.root:set_rotation(V(0, 0, 0))
    else hb.root:set_position(HIDE) end
    if ST and ST.kind == "75" and st == "grab" then G.held_spring.root:set_position(V(WX(x) + 1.4, WY(y) + 2.6, 0.6)) else G.held_spring.root:set_position(HIDE) end
end
local function render_pauline(dt)
    local r = RIGS.pauline
    if G.paul_hidden then r.root:set_position(HIDE); return end
    local x, y = PAUL.x, PAUL.y
    local t = G.t
    local o = { pos = V(WX(x), WY(y), PAUL.z or 0.1), yaw = PAUL.yaw or (sin(t * 0.7) * 12) }
    if PAUL.carried then
        o.pos = PAUL.carried; o.rx = 0; o.rz = 80; o.yaw = 0
        o.alz, o.arz = -150 + 30 * sin(t * 10), 150 - 30 * sin(t * 10)
    elseif PAUL.help > 0 then
        o.arz = 150 + 22 * sin(t * 11); o.alz = -20; o.hz = 6 * sin(t * 3)
    else
        o.alz, o.arz = -12 + 4 * sin(t * 2), 12 - 4 * sin(t * 2.3)
    end
    pose_pauline(r, o)
end
local function render_ents(dt)
    local t = G.t
    for _, b in ipairs(B) do
        local x, y = ip(b)
        b.rig.root:set_position(V(WX(x), WY(y) + 0.63, 0.05))
        b.rig.root:set_rotation(V(0, b.st == "ladder" and 70 or 0, b.spin or 0))
    end
    for _, pool in ipairs({ RIGS.fire, RIGS.fox }) do for _, r in ipairs(pool) do if not r.used then emitter_at(r.em, 0, 2000, 0, 0) end end end
    for _, f in ipairs(F) do
        local x, y = ip(f)
        local sc = 1 + 0.08 * sin(f.ph * 3)
        if f.pop then f.pop = max(0, f.pop - dt * 2); sc = sc * (1 - f.pop) end
        f.rig.root:set_position(V(WX(x), WY(y) + 0.02 + 0.06 * abs(sin(f.ph)), 0.1))
        f.rig.root:set_rotation(V(0, (f.st == "climb") and 0 or f.dir * 35, 4 * sin(f.ph * 2)))
        f.rig.root:set_scale(V(sc, sc * (1 + 0.05 * sin(f.ph * 5)), sc))
        emitter_at(f.rig.em, x, y - 7, 0.1, 40)
    end
    for _, p in ipairs(PIES) do
        local x, y = ip(p)
        p.rig.root:set_position(V(WX(x), WY(y), 0.05))
    end
    for _, s in ipairs(SPR) do
        local x, y = ip(s)
        s.rig.root:set_position(V(WX(x), WY(y), 0.1))
        s.rig.root:set_scale(V(1 + 0.2 * (s.sq or 0), 1 - 0.35 * (s.sq or 0), 1 + 0.2 * (s.sq or 0)))
    end
end
local function render_stage(dt)
    if not ST then return end
    local t = G.t
    -- conveyors: moving slats + spinning end rollers
    for gi, g in ipairs(ST.girders) do
        if g.conv and g.treads then
            local x0, len = g.x0, gx1(g) - g.x0
            local y = WY(g.ys[1])
            for i, n in ipairs(g.treads) do
                local px = x0 + ((i - 1) * 8 + (g.phase or 0)) % len
                n:set_position(V(WX(px), y + 0.03, 0)); n:set_scale(V(0.22, 1, 1))
            end
            g.rollers[1]:set_position(V(WX(x0), y - 0.3, 0)); g.rollers[2]:set_position(V(WX(x0 + len), y - 0.3, 0))
            local a = -(g.phase or 0) * 20
            g.rollers[1]:set_rotation(V(0, 0, a)); g.rollers[2]:set_rotation(V(0, 0, a))
        end
    end
    -- retractable ladders follow their state
    local any_r = false
    for _, l in ipairs(ST.ladders) do if l.retract then any_r = true end end
    if any_r then G.refresh_ladders() end
    -- rivets: pop out and tumble away
    for _, r in ipairs(ST.rivets) do
        if r.h.open then
            if not r.placed then r.placed = true; place_girders(ST.girders[r.g], r.g) end
            if r.fly then
                r.fly = r.fly + dt
                local k = r.fly
                r.node:set_position(V(WX(r.x) + k * 2.5, WY(r.y) + 2.2 * k - 9 * k * k, 0.6 + k)); r.node:set_rotation(V(k * 400, 0, k * 300))
                if k > 1.2 then r.fly = nil; r.node:set_position(HIDE) end
            end
        end
    end
    -- elevator platforms
    if ST.plats then for _, p in ipairs(ST.plats) do
        local y = lerp(p.oy or p.y, p.y, AL)
        if p.live then p.node:set_position(V(WX(p.x), WY(y), 0)); p.node:set_scale(V(1, 0.6, 1)) else p.node:set_position(HIDE) end
    end end
    -- oil drum fire
    if ST.drum_xy then
        local d = ST.drum_xy
        if ST.lit then
            local fl = 1 + 0.12 * sin(t * 17) + 0.08 * sin(t * 29)
            ST.flame:set_position(V(WX(d.x), WY(d.y) + 1.9, 0)); ST.flame:set_scale(V(1.0, fl * 1.1, 1.0))
            emitter_at(EMIT.drum, d.x, d.y - 17, 0, 60); emitter_at(EMIT.smoke, d.x, d.y - 24, -0.2, 8)
            set_point(LT.fire, V(WX(d.x), WY(d.y) + 3.2, 2.2), V(1, .5, .15), 55 * fl, 12)
        else
            ST.flame:set_position(HIDE); emitter_at(EMIT.drum, 0, 2000, 0, 0); emitter_at(EMIT.smoke, 0, 2000, 0, 0)
            set_point(LT.fire, HIDE, V(1, .5, .15), 0, 1)
        end
    else
        emitter_at(EMIT.drum, 0, 2000, 0, 0); emitter_at(EMIT.smoke, 0, 2000, 0, 0)
        set_point(LT.fire, HIDE, V(1, .5, .15), 0, 1)
    end
    for _, h in ipairs(ST.hammer_props) do
        if h.live then
            local yaw = t * 60
            h.n1:set_position(V(WX(h.x), WY(h.y + 6) + 0.05 * sin(t * 3), 0.1)); h.n1:set_rotation(V(0, yaw, 0))
            h.n2:set_position(V(WX(h.x), WY(h.y + 6) + 0.05 * sin(t * 3), 0.1)); h.n2:set_rotation(V(0, yaw, 0))
        else h.n1:set_position(HIDE); h.n2:set_position(HIDE) end
    end
    for _, it in ipairs(ST.items) do
        if it.live then it.node:set_position(V(WX(it.x), WY(it.y) + 0.05, 0.1)); it.node:set_rotation(V(0, 25 * sin(t * 1.5), 0))
        else it.node:set_position(HIDE) end
    end
    -- Kong's barrel stack (25m)
    for i, r in ipairs(RIGS.stack) do
        if ST.kind == "25" and not G.stack_hidden then
            local cx = ({ 8, 19, 8, 19 })[i]; local lay = i > 2 and 1 or 0
            r.root:set_position(V(WX(cx), WY(84) + lay * 0.96, -0.1)); r.root:set_rotation(V(90, 0, 0))
        else r.root:set_position(HIDE) end
    end
end

------------------------------------------------------------------ camera
G.shake = 0
local function update_camera(dt)
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.5 * SET:shake_scale()
    local ox, oy = a * sin(G.t * 53), a * cos(G.t * 61)
    if G.cam_ov then local o = G.cam_ov; cam:set_position(V(o[1], o[2], o[3])); cam:look_at(V(o[4], o[5], o[6] or 0)); return end
    local fx = (M.st ~= "hidden" and WX(M.x) or 0) * 0.04
    local sway = sin(G.t * 0.21) * 0.25
    cam:set_position(V(fx + sway + ox, 0.3 + oy, CAMZ)); cam:look_at(V(fx * 0.6 + sway * 0.5 + ox * 0.5, -0.1 + oy * 0.5, 0))
end

------------------------------------------------------------------ collider debug overlay (F3)
-- thin emissive bars; every point is pulled along its camera ray to z = DBG.z so outlines sit on the z = 0 gameplay plane
G.DBG = { on = false, pool = {}, used = 0, z = 3.0, w = 0.07 }
G.DBG_COL = { floor = { .1, 1, 1 }, ladder = { 1, .9, .2 }, mario = { .2, 1, .3 }, enemy = { 1, .25, .2 }, hammer = { 1, .6, .1 }, item = { 1, .4, .9 }, plat = { .3, .6, 1 } }
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
    local ax, ay = c.x + (WX(x0) - c.x) * k, c.y + (WY(y0) - c.y) * k
    local bx, by = c.x + (WX(x1) - c.x) * k, c.y + (WY(y1) - c.y) * k
    local dx, dy = bx - ax, by - ay
    local L = sqrt(dx * dx + dy * dy)
    b.n:set_position(V((ax + bx) * .5, (ay + by) * .5, D.z))
    b.n:set_rotation(V(0, 0, math.deg(atan2(dy, dx))))
    b.n:set_scale(V(L + D.w, D.w, D.w))
end
function G.dbg_box(x0, y0, x1, y1, col)
    G.dbg_bar(x0, y0, x1, y0, col); G.dbg_bar(x1, y0, x1, y1, col); G.dbg_bar(x1, y1, x0, y1, col); G.dbg_bar(x0, y1, x0, y0, col)
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and ST and (G.state == "play" or G.state == "pause" or G.state == "title") then
        local C = G.DBG_COL
        for _, g in ipairs(ST.girders) do
            for i, y in ipairs(g.ys) do
                local a, b = g.x0 + (i - 1) * g.sw, g.x0 + i * g.sw
                local x = a
                if g.holes then for _, h in ipairs(g.holes) do if h.open and h.a >= a and h.b <= b + 0.1 then G.dbg_bar(a, y, h.a, y, C.floor); x = h.b end end end
                if x < b then G.dbg_bar(x, y, b, y, C.floor) end
            end
        end
        for _, l in ipairs(ST.ladders) do G.dbg_box(l.x - 3, ladder_limit(l), l.x + 3, l.ylo, C.ladder) end
        if ST.plats then for _, p in ipairs(ST.plats) do if p.live then G.dbg_bar(p.x - 8, p.y, p.x + 8, p.y, C.plat) end end end
        if M.st ~= "hidden" then local a, b, c, d = mario_box(); G.dbg_box(a, b, c, d, C.mario) end
        local hx0, hy0, hx1, hy1 = hammer_box(); if hx0 then G.dbg_box(hx0, hy0, hx1, hy1, C.hammer) end
        for _, list in ipairs({ B, F, PIES, SPR }) do for _, e in ipairs(list) do local a, b, c, d = ent_box(e); G.dbg_box(a, b, c, d, C.enemy) end end
        local kh = HB.kong
        G.dbg_box(KONG.x - kh[1], KONG.y - kh[2], KONG.x + kh[1], KONG.y, C.enemy)
        if ST.fire then G.dbg_box(ST.fire.x - 8, ST.fire.y - 22, ST.fire.x + 8, ST.fire.y, C.enemy) end
        for _, h in ipairs(ST.hammer_props) do if h.live then G.dbg_box(h.x - 5, h.y - 6, h.x + 5, h.y + 6, C.hammer) end end
        for _, it in ipairs(ST.items) do if it.live then G.dbg_box(it.x - 6, it.y - 10, it.x + 6, it.y, C.item) end end
    end
    for i = D.used + 1, #D.pool do local b = D.pool[i]; if not b.hidden_ then b.n:set_position(HIDE) end end
end
