------------------------------------------------------------------ world nodes
local function V(x, y, z) return vec3(x, y, z) end
G.shake = 0
local W = { lv = {}, doors = {} }
G.W = W   -- (tests)
local HR = {}
------------------------------------------------------------------ rigged characters: one node per segment (body, legs, arms, wings),
-- each carrying one mesh per material; joints are animated here (walk cycle, attacks, wing flaps, floating)
function G.rig_new(kind)
    local root = empty("rig_" .. kind, nil, HIDE)
    local r = { root = root, seg = {}, kind = kind, rot = {} }
    for _, sg in ipairs(G.RIG[kind]) do
        local n = empty(kind .. "_" .. sg.name, root, V(sg.piv[1], sg.piv[2], sg.piv[3]))
        for _, m in ipairs(sg.meshes) do local t = tpl("T_" .. m); if t and t.mesh then n:add_mesh_ref(t.mesh) end end
        r.seg[sg.name] = n
    end
    return r
end
local function jrot(r, name, x, y, z)
    local n = r.seg[name]; if not n then return end
    -- skip redundant writes (keeps motion vectors clean and saves Lua->engine calls)
    local k = r.rot[name]
    if k and abs(k[1] - x) < 0.05 and abs(k[2] - y) < 0.05 and abs(k[3] - z) < 0.05 then return end
    r.rot[name] = { x, y, z }; n:set_rotation(V(x, y, z))
end
-- pose: ph = walk phase (rad), amp = 0..1 walking, atk = 0..1 attack swing, t = clock, cast = 0..1 spell pose
function G.rig_pose(r, ph, amp, atk, t, cast)
    local k = r.kind
    local sw = sin(ph) * amp
    local strike = atk > 0 and -sin(atk * PI) * 105 or 0
    if k == "ghost" then
        jrot(r, "arm_l", -12 + 10 * sin(t * 3.1), 0, -6 * sin(t * 2.3)); jrot(r, "arm_r", -12 + 10 * sin(t * 3.1 + 1.7) + strike * 0.5, 0, 6 * sin(t * 2.3))
        return
    end
    if k == "sorc" or k == "death" then
        local lift = (k == "sorc") and (-35 - 55 * (cast or 0)) or -10
        jrot(r, "arm_l", lift + 8 * sin(t * 2.2) - sw * 10, 0, k == "sorc" and -12 * (cast or 0) or 0)
        jrot(r, "arm_r", (k == "death" and -18 + 16 * sin(t * 2.6) or lift + 8 * sin(t * 2.2 + 1)) + sw * 10 + strike, 0, k == "sorc" and 12 * (cast or 0) or 0)
        return
    end
    local legA = (k == "grunt" or k == "lobber") and 26 or 34
    jrot(r, "leg_l", sw * legA, 0, 0); jrot(r, "leg_r", -sw * legA, 0, 0)
    local armA = 26
    local idle = 3 * sin(t * 2.0)
    jrot(r, "arm_l", -sw * armA + idle, 0, 0)
    jrot(r, "arm_r", sw * armA - idle + strike, 0, 0)
    if k == "demon" then
        local f = 28 * sin(t * 10) + 10
        jrot(r, "wing_l", 0, -15, f); jrot(r, "wing_r", 0, 15, -f)
    end
end
local RIGP = {}
local function R_begin(kind) local p = RIGP[kind]; if not p then p = { r = {}, used = 0 }; RIGP[kind] = p end; p.used = 0 end
local function R_get(kind)
    local p = RIGP[kind]; if not p then R_begin(kind); p = RIGP[kind] end
    p.used = p.used + 1
    local r = p.r[p.used]; if not r then r = G.rig_new(kind); p.r[p.used] = r end
    return r
end
local function R_end(kind) local p = RIGP[kind]; if not p then return end; for i = p.used + 1, #p.r do local r = p.r[i]; if not r.hidden then r.hidden = true; r.root:set_position(HIDE) end end end
local function place_rig(r, pos, rot, sc) r.hidden = false; r.root:set_position(pos); r.root:set_rotation(rot); r.root:set_scale(sc) end
local function build_world()
    for i, L in ipairs(G.LEVELS) do
        W.lv[i] = { clone("lv" .. i .. "_wall", HIDE), clone("lv" .. i .. "_floor", HIDE) }
        if L.trapw then W.lv[i].tw = clone("lv" .. i .. "_trapw", HIDE) end
    end
    W.ex = {}
    for _, h in ipairs(G.HEROES) do HR[h.id] = G.rig_new(h.id) end
    W.sh = clone("shadow")
end
function G.reset_world() W.cur = nil end
local function show_level()
    if W.cur == G.load_id then return end
    W.cur = G.load_id
    for i, l in ipairs(W.lv) do
        for _, n in ipairs(l) do n:set_position(i == G.li and V(0, 0, 0) or HIDE) end
        if l.tw then l.tw:set_position(i == G.li and V(0, 0, 0) or HIDE) end
    end
    W.trapped = false
    for _, d in ipairs(W.doors) do d:set_position(HIDE) end
    for k, d in ipairs(G.DOORS) do
        local n = W.doors[k]; if not n then n = clone("door"); W.doors[k] = n end
        d.node = n
        -- bars run across the corridor: rotate when the door is in a north-south passage
        local ns = not G.solid(d.i, d.j + 1) or not G.solid(d.i, d.j - 1)
        n:set_rotation(V(0, ns and 0 or 90, 0))
    end
    for _, e in ipairs(W.ex) do for _, n in pairs(e) do n:set_position(HIDE) end end
    for k, e in ipairs(G.EXITS or {}) do
        local w = W.ex[k]; if not w then w = { a = clone("exit", HIDE), b = clone("exit_steps", HIDE), c = clone("exit_rim", HIDE) }; W.ex[k] = w end
        w.a:set_position(WP(e.x, e.y, 0.002)); w.b:set_position(WP(e.x, e.y, 0.004))
        w.c:set_position(e.jump and WP(e.x, e.y, 0.003) or HIDE)
    end
end
local ITEMM = { k = { "key" }, f = { "food_plate", "food_ham" }, p = { "potion", "potion_cork" }, t = { "chest", "chest_lid", "chest_band" } }
local MONK = { "ghost", "grunt", "demon", "lobber", "sorc", "death" }
local function render_world(dt)
    show_level()
    local P = G.P
    if G.trapped and not W.trapped then W.trapped = true; local l = W.lv[G.li]; if l and l.tw then l.tw:set_position(HIDE) end end
    -- trap and stun plates (a stun plate crackles while it is discharging)
    P_begin("trap_tile"); P_begin("stun_tile")
    for _, t in ipairs(G.TRAPS or {}) do if abs(t.x - P.x) < 14 and abs(t.y - P.y) < 11 then P_get("trap_tile"):set_position(WP(t.x, t.y, 0.003)) end end
    for _, z in ipairs(G.STUNS or {}) do
        if abs(z.x - P.x) < 14 and abs(z.y - P.y) < 11 then
            P_get("stun_tile"):set_position(WP(z.x, z.y, 0.003))
            if z.t > 0 and rand() < 0.25 then G.sparks(WP(z.x + rr(-.3, .3), z.y + rr(-.3, .3), 0.08), 2, { 1.3, 1.2, .6 }) end
        end
    end
    P_end("trap_tile"); P_end("stun_tile")
    if P.stun and P.stun > 0 and rand() < 0.2 then G.sparks(WP(P.x + rr(-.2, .2), P.y + rr(-.2, .2), 0.9), 2, { 1.3, 1.2, .6 }) end
    for _, d in ipairs(G.DOORS) do
        if d.node then d.node:set_position(d.open >= 1 and HIDE or WP(d.i + 0.5, d.j + 0.5, -d.open * 0.95)) end
    end
    -- items
    for _, list in pairs(ITEMM) do for _, mname in ipairs(list) do P_begin(mname) end end
    for _, it in ipairs(G.ITEMS) do
        if it.alive and abs(it.x - P.x) < 14 and abs(it.y - P.y) < 11 then
            for _, mname in ipairs(ITEMM[it.k]) do
                local n = P_get(mname); n:set_position(WP(it.x, it.y, it.k == "k" and 0.05 * sin(G.t * 3) or 0))
                n:set_rotation(V(0, it.k == "k" and G.t * 90 % 360 or 0, 0))
            end
        end
    end
    for _, list in pairs(ITEMM) do for _, mname in ipairs(list) do P_end(mname) end end
    -- generators (bigger = higher level)
    P_begin("gen"); P_begin("gen_bones")
    for _, g in ipairs(G.GENS) do
        if g.alive and abs(g.x - P.x) < 14 and abs(g.y - P.y) < 11 then
            local s = 0.75 + 0.12 * g.lv + g.flash * 0.06
            local a = P_get("gen"); a:set_position(WP(g.x, g.y, 0)); a:set_scale(V(s, s, s))
            local b = P_get("gen_bones"); b:set_position(WP(g.x, g.y, 0)); b:set_scale(V(s, s, s)); b:set_rotation(V(0, g.i * 37 % 360, 0))
        end
    end
    P_end("gen"); P_end("gen_bones")
    -- monsters (rigged, animated)
    for _, k in ipairs(MONK) do R_begin(k) end
    P_begin("shadow")
    for _, m in ipairs(G.MON) do
        if abs(m.x - P.x) < 14 and abs(m.y - P.y) < 11 and (m.vis or (G.t * 10) % 2 < 0.3) then
            local s = (0.85 + 0.1 * m.lv) * 1.2
            local yaw = math.deg(atan2(-m.fx, m.fy))
            local fly = m.kind == "ghost" or m.kind == "death" or m.kind == "sorc"
            local bob = fly and (0.06 + 0.05 * sin(m.t * 4)) or abs(sin(m.t * 8)) * 0.03
            if m.kind == "demon" then bob = 0.02 + 0.03 * sin(m.t * 10) end
            local mx, my = G.lerp_pos(m)
            local r = R_get(m.kind)
            place_rig(r, WP(mx, my, bob), V(fly and 0 or 6, yaw, 0), V(s, s, s))
            m.swing = max(0, (m.swing or 0) - dt * 3.2)
            G.rig_pose(r, m.t * (m.kind == "lobber" and 12 or 9), m.kind == "lobber" and 1 or 0.9, m.swing > 0 and (1 - m.swing) or 0, m.t, m.vis and 0.5 + 0.5 * sin(m.t * 2.6) or 1)
            local sh = P_get("shadow"); sh:set_position(WP(mx + 0.06, my - 0.05, 0.004)); sh:set_scale(V(0.4 * s, 1, 0.4 * s))
        end
    end
    -- hero (rigged): walk cycle, swing on shots and melee, lean into motion
    local h = G.H()
    local hx, hy = G.lerp_pos(P)
    local yaw = math.deg(atan2(-P.fx, P.fy))
    local moving = (P.walk or 0) > 0
    G.hamp = damp(G.hamp or 0, moving and 1 or 0, 12, dt)
    G.hph = (G.hph or 0) + dt * 11 * (h.speed / 3.8) * (moving and 1 or 0.3)
    P.atk_t = max(0, (P.atk_t or 0) - dt * 4)
    for id, r in pairs(HR) do
        local on = id == h.id and (P.alive or G.phase ~= "dead")
        if on then
            local bob = abs(sin(G.hph)) * 0.03 * G.hamp
            place_rig(r, WP(hx, hy, bob), V(7 * G.hamp, yaw, 0), V(1.25, 1.25, 1.25))
            G.rig_pose(r, G.hph, G.hamp, P.atk_t > 0 and (1 - P.atk_t) or 0, G.t, 0)
        elseif not r.hidden then r.hidden = true; r.root:set_position(HIDE) end
    end
    if P.alive then local sh = P_get("shadow"); sh:set_position(WP(hx + 0.06, hy - 0.05, 0.004)); sh:set_scale(V(0.42, 1, 0.42)) end
    for _, k in ipairs(MONK) do R_end(k) end
    P_end("shadow")
    G.render_showcase(dt)
    -- shots
    for _, k in ipairs({ "p_axe", "p_sword", "p_fire", "p_arrow", "p_rock", "p_dfire" }) do P_begin(k) end
    G.trail_t = (G.trail_t or 0) - dt
    local tr = G.trail_t <= 0; if tr then G.trail_t = 0.05 end
    for _, s in ipairs(G.SHOTS) do
        local sx, sy = G.lerp_pos(s)
        local n = P_get(s.m); n:set_position(WP(sx, sy, 0.45))
        if tr and s.m == "p_fire" then G.trail(WP(sx, sy, 0.45), { 1.6, .8, 2.0 }, 3) end
        local yaw = math.deg(atan2(-s.vx, s.vy))
        n:set_rotation(s.m == "p_axe" and V(0, yaw + s.spin, 0) or V(0, yaw, 0))
    end
    for _, s in ipairs(G.ESHOT) do
        local sx, sy = G.lerp_pos(s)
        P_get(s.k):set_position(WP(sx, sy, s.h or 0.45))
        if tr and s.k == "p_dfire" then G.trail(WP(sx, sy, s.h or 0.45), { 1.8, .7, .2 }, 3) end
    end
    for _, k in ipairs({ "p_axe", "p_sword", "p_fire", "p_arrow", "p_rock", "p_dfire" }) do P_end(k) end
end

-- showcase for screenshots/tests: every hero and monster in a row at G.showcase = {x, y}, camera close
local SHOW = {}
function G.render_showcase(dt)
    local sc = G.showcase
    local kinds = { "war", "val", "wiz", "elf", "ghost", "grunt", "demon", "lobber", "sorc", "death" }
    for i, k in ipairs(kinds) do
        local r = SHOW[k]; if not r then r = G.rig_new(k); SHOW[k] = r end
        if sc then
            local x, y = sc.x + (i - 5.5) * 0.95, sc.y
            local s = i <= 4 and 1.25 or 1.2
            place_rig(r, WP(x, y, (k == "ghost" or k == "sorc" or k == "death") and 0.08 or 0), V(0, 180 + (sc.yaw or 0), 0), V(s, s, s))
            G.rig_pose(r, G.t * 9, sc.walk and 1 or 0, (type(sc.atk) == "number") and sc.atk or (sc.atk and (G.t * 1.5 % 1) or 0), G.t, 0.6)
        elseif not r.hidden then r.hidden = true; r.root:set_position(HIDE) end
    end
end
------------------------------------------------------------------ camera: follows the hero over the maze
local function update_camera(dt)
    local P = G.P
    local c = G.cam
    local k = G.cam_snap and 1 or (1 - math.exp(-6 * dt)); G.cam_snap = false
    local tx, ty = G.lerp_pos(P)
    if G.state == "title" then tx, ty = G.LW / 2 + 8 * sin(G.t * 0.07), G.LH / 2 + 5 * sin(G.t * 0.05) end
    tx, ty = clamp(tx, 9.5, G.LW - 9.5), clamp(ty, 4.2, G.LH - 6.5)
    c.x, c.y = c.x + (tx - c.x) * k, c.y + (ty - c.y) * k
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.3 * SET:shake_scale()
    if G.showcase then
        local sc = G.showcase
        cam:set_position(WP(sc.x, sc.y - (sc.dist or 4.2), sc.h or 4.2)); cam:look_at(WP(sc.x, sc.y, 0.45)); return
    end
    cam:set_position(WP(c.x + a * sin(G.t * 53), c.y - 5.6 + a * cos(G.t * 61), 12.0))
    cam:look_at(WP(c.x, c.y + 0.4, 0))
end

------------------------------------------------------------------ collider debug overlay (F3)
G.DBG = { on = false, pool = {}, used = 0, w = 0.04 }
local DC = { me = { .2, 1, .3 }, enemy = { 1, .25, .2 }, wall = { .4, .7, 1 }, shot = { 1, .9, .3 }, item = { .3, .8, 1 }, gen = { 1, .5, .1 } }
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
local function dbox(x0, y0, x1, y1, col, h)
    h = h or 1.02
    local a, b, c, d = WP(x0, y0, h), WP(x1, y0, h), WP(x1, y1, h), WP(x0, y1, h)
    G.dbg_bar(a, b, col); G.dbg_bar(b, c, col); G.dbg_bar(c, d, col); G.dbg_bar(d, a, col)
end
local function dcircle(x, y, r, col, h, n)
    n = n or 12; h = h or 0.05
    for i = 0, n - 1 do
        local a0, a1 = i / n * 6.2832, (i + 1) / n * 6.2832
        G.dbg_bar(WP(x + cos(a0) * r, y + sin(a0) * r, h), WP(x + cos(a1) * r, y + sin(a1) * r, h), col)
    end
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and G.state ~= "title" then
        local P = G.P
        -- solid cells near the hero
        for j = floor(P.y) - 7, floor(P.y) + 8 do for i = floor(P.x) - 10, floor(P.x) + 10 do
            local c = G.cell(i, j)
            if c == "#" or c == "w" then
                -- only draw edges that face open floor
                if not G.solid(i - 1, j) then G.dbg_bar(WP(i, j, 1.02), WP(i, j + 1, 1.02), DC.wall) end
                if not G.solid(i + 1, j) then G.dbg_bar(WP(i + 1, j, 1.02), WP(i + 1, j + 1, 1.02), DC.wall) end
                if not G.solid(i, j - 1) then G.dbg_bar(WP(i, j, 1.02), WP(i + 1, j, 1.02), DC.wall) end
                if not G.solid(i, j + 1) then G.dbg_bar(WP(i, j + 1, 1.02), WP(i + 1, j + 1, 1.02), DC.wall) end
            elseif c == "D" then dbox(i, j, i + 1, j + 1, DC.wall, 0.95)
            elseif c == "G" then dbox(i, j, i + 1, j + 1, DC.gen, 0.7) end
        end end
        if P.alive then dcircle(P.x, P.y, G.PR, DC.me, 0.05, 14) end
        for _, m in ipairs(G.MON) do if abs(m.x - P.x) < 11 and abs(m.y - P.y) < 8 then dcircle(m.x, m.y, G.MR, DC.enemy, 0.05, 10) end end
        for _, s in ipairs(G.SHOTS) do G.dbg_bar(WP(s.px, s.py, 0.45), WP(s.x, s.y, 0.45), DC.shot) end
        for _, s in ipairs(G.ESHOT) do dcircle(s.x, s.y, s.lob and 0.25 or 0.12, DC.enemy, s.h or 0.45, 8) end
        for _, it in ipairs(G.ITEMS) do if it.alive and abs(it.x - P.x) < 11 and abs(it.y - P.y) < 8 then dcircle(it.x, it.y, 0.25, DC.item, 0.05, 8) end end
    end
    for i = D.used + 1, #D.pool do D.pool[i].n:set_position(HIDE) end
end
