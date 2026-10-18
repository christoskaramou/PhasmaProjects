------------------------------------------------------------------ world nodes
local function V(x, y, z) return vec3(x, y, z) end
G.shake = 0
local W = {}
local function build_world()
    W.floor = clone("floor", WP(0, FH / 2, -0.01), V(FW + 0.2, 1, FH + 0.2))
    -- straight pipes stop where the corner elbows begin (bend radius ER = 0.7), so the frame is one continuous tube
    local ER = 0.7
    local y0, y1 = -0.3, FH + 0.32 - ER
    local L = y1 - y0
    W.walls = { clone("wall_side", WP(-FW / 2 - 0.32, (y0 + y1) / 2, 0), V(1, 1, L)), clone("wall_side", WP(FW / 2 + 0.32, (y0 + y1) / 2, 0), V(1, 1, L)),
        clone("wall_top", WP(0, FH + 0.32, 0), V(FW + 0.64 - 2 * ER, 1, 1)) }
    W.elbows = {}
    for i, sx in ipairs({ -1, 1 }) do
        local yaw = (sx < 0) and 0 or -90
        for _, nm in ipairs({ "wall_elbow", "elbow_collar" }) do
            local n = clone(nm, WP(sx * (FW / 2 + 0.32), FH + 0.32, 0)); n:set_rotation(V(0, yaw, 0)); W.elbows[#W.elbows + 1] = n
        end
    end
    W.rings = {}
    for _, sx in ipairs({ -1, 1 }) do for y = 1.5, FH - 1, 3 do W.rings[#W.rings + 1] = clone("wall_ring", WP(sx * (FW / 2 + 0.32), y, 0)) end end
    W.corners = {}
    W.gates = {}
    for _, gx in ipairs({ -3.5, 3.5 }) do W.gates[#W.gates + 1] = { base = clone("gate", WP(gx, FH + 0.32, 0)), door = clone("gate_door", WP(gx, FH + 0.32, 0)), x = gx } end
    W.warp = clone("warp", HIDE)
    W.vaus = { mid = clone("vaus_mid"), strip = clone("vaus_strip"), capL = clone("vaus_cap"), capR = clone("vaus_cap"), gL = clone("vaus_gun"), gR = clone("vaus_gun"), sh = clone("shadow") }
    W.doh = { head = clone("doh_head"), brow = clone("doh_brow"), nose = clone("doh_nose"), eye = clone("doh_eye"), mouth = clone("doh_mouth") }
end
function G.reset_world() W.bg = nil end

-- interpolated position: blend the previous and current fixed step by AL (a jump > 2 units, e.g. a respawn, snaps)
local function ix(o, k) local v, w = o[k], o["o" .. k]; if not w or abs(v - w) > 2 then return v end; return w + (v - w) * AL end
G.ix = ix
local function render_world(dt)
    -- backdrop cycles through four patterns, like the arcade
    local bgi = ((G.round or 1) - 1) % 4
    if W.bg ~= bgi then W.bg = bgi; G.set_bg(tnode("floor"), bgi) end
    -- gates open while an enemy is coming through
    for _, g in ipairs(W.gates) do
        local open = 0
        for _, e in ipairs(G.EN) do if e.alive and abs(e.x - g.x) < 1 and e.y > FH - 1.2 then open = 1 end end
        g.o = (g.o or 0) + (open - (g.o or 0)) * min(1, dt * 8)
        g.door:set_position(WP(g.x + g.o * 0.7, FH + 0.32, 0.01))
    end
    W.warp:set_position(G.warp and WP(FW / 2 + 0.25, 1.0, 0.0) or HIDE)
    if G.warp then local s = 1 + 0.15 * sin(G.t * 10); W.warp:set_scale(V(s, 1, 1)) end
    -- bricks (pooled per colour)
    for k in pairs(G.BRICK) do P_begin("brick_" .. k) end
    for _, b in ipairs(G.BRICKS) do
        if b.alive then
            local n = P_get("brick_" .. b.k)
            local f = b.flash
            n:set_position(WP(b.x, b.y, f * 0.06)); n:set_scale(V(1 + f * 0.04, 1 + f * 0.5, 1 + f * 0.04))
        end
    end
    for k in pairs(G.BRICK) do P_end("brick_" .. k) end
    -- Vaus
    local v = W.vaus
    local P = G.P
    if P.alive or G.phase ~= "dead" then
        local hw = P.w / 2
        local PX = ix(P, "x")
        local body = max(0.2, P.w - 0.36)
        v.mid:set_position(WP(PX, G.VY, 0)); v.mid:set_scale(V(body, 1, 1))
        v.strip:set_position(WP(PX, G.VY, 0)); v.strip:set_scale(V(P.mode == "E" and 1.6 or 1, 1, 1))
        v.capL:set_position(WP(PX - hw + 0.18, G.VY, 0)); v.capL:set_rotation(V(0, 0, 0))
        v.capR:set_position(WP(PX + hw - 0.18, G.VY, 0)); v.capR:set_rotation(V(0, 180, 0))
        v.gL:set_position(P.guns and WP(PX - hw + 0.22, G.VY, 0) or HIDE); v.gR:set_position(P.guns and WP(PX + hw - 0.22, G.VY, 0) or HIDE)
        v.sh:set_position(WP(PX + 0.12, G.VY - 0.14, 0.004)); v.sh:set_scale(V(P.w * 0.9, 1, 0.36))
    else for _, n in pairs(v) do n:set_position(HIDE) end end
    -- balls and their shadows
    P_begin("ball"); P_begin("shadow")
    for _, b in ipairs(G.BALLS) do
        local bx, by = ix(b, "x"), ix(b, "y")
        P_get("ball"):set_position(WP(bx, by, 0.22))
        local s = P_get("shadow"); s:set_position(WP(bx + 0.1, by - 0.1, 0.004)); s:set_scale(V(0.32, 1, 0.32))
    end
    P_end("ball"); P_end("shadow")
    -- capsules
    for k in pairs(G.CAPC) do P_begin("cap_" .. k); P_begin("lbl_" .. k) end
    for _, c in ipairs(G.CAPS) do
        local cx, cy = ix(c, "x"), ix(c, "y")
        local a = P_get("cap_" .. c.k); a:set_position(WP(cx, cy, 0)); a:set_rotation(V(c.spin % 360, 0, 0))
        local l = P_get("lbl_" .. c.k); l:set_position(WP(cx, cy, 0.005))
    end
    for k in pairs(G.CAPC) do P_end("cap_" .. k); P_end("lbl_" .. k) end
    -- shots
    P_begin("laser"); for _, s in ipairs(G.SHOTS) do P_get("laser"):set_position(WP(ix(s, "x"), ix(s, "y"), 0)) end; P_end("laser")
    P_begin("doh_shot"); for _, s in ipairs(G.DSHOT) do P_get("doh_shot"):set_position(WP(ix(s, "x"), ix(s, "y"), 0.1)) end; P_end("doh_shot")
    -- enemies
    for _, k in ipairs({ "en_cone", "en_pyr", "en_orb", "en_cube" }) do P_begin(k) end
    for _, e in ipairs(G.EN) do
        if e.alive then local n = P_get(e.k); n:set_position(WP(ix(e, "x"), ix(e, "y"), 0.1 + 0.08 * sin(e.t * 3))); n:set_rotation(V(e.k == "en_cube" and e.t * 90 or 0, e.t * 120, 0)) end
    end
    for _, k in ipairs({ "en_cone", "en_pyr", "en_orb", "en_cube" }) do P_end(k) end
    -- DOH
    local D = G.doh
    for name, n in pairs(W.doh) do
        if D and (D.alive or (D.dead_t or 0) < 2.4) then
            local sink = D.alive and 0 or -(D.dead_t or 0) * 0.5
            local f = 1 + D.flash * 0.04
            n:set_position(WP(D.x + (D.alive and 0 or 0.08 * sin(G.t * 60)), D.y, sink)); n:set_scale(V(f, f, f))
        else n:set_position(HIDE) end
    end
end

------------------------------------------------------------------ camera (fixed, tilted over the field)
local function update_camera(dt)
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.3 * SET:shake_scale()
    local c, l = G.cam.pos, G.cam.look
    cam:set_position(V(c.x + a * sin(G.t * 53), c.y, c.z + a * cos(G.t * 61)))
    cam:look_at(l)
end

------------------------------------------------------------------ collider debug overlay (F3)
G.DBG = { on = false, pool = {}, used = 0, w = 0.05 }
local DC = { me = { .2, 1, .3 }, enemy = { 1, .25, .2 }, brick = { 1, .9, .3 }, shot = { 1, .5, .1 }, cap = { .3, .8, 1 }, wall = { .4, .7, 1 } }
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
local function dbox(x, y, hw, hh, col, h)
    h = h or 0.45
    local a, b, c, d = WP(x - hw, y - hh, h), WP(x + hw, y - hh, h), WP(x + hw, y + hh, h), WP(x - hw, y + hh, h)
    G.dbg_bar(a, b, col); G.dbg_bar(b, c, col); G.dbg_bar(c, d, col); G.dbg_bar(d, a, col)
end
local function dcircle(x, y, r, col, h, n)
    n = n or 12; h = h or 0.45
    for i = 0, n - 1 do
        local a0, a1 = i / n * 6.2832, (i + 1) / n * 6.2832
        G.dbg_bar(WP(x + cos(a0) * r, y + sin(a0) * r, h), WP(x + cos(a1) * r, y + sin(a1) * r, h), col)
    end
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and G.state ~= "title" then
        dbox(0, FH / 2, FW / 2, FH / 2, DC.wall, 0.3)
        local P = G.P
        if P.alive then dbox(P.x, G.VY, P.w / 2, G.VH, DC.me) end
        for _, b in ipairs(G.BALLS) do dcircle(b.x, b.y, G.BR, DC.me, 0.22, 10) end
        for _, b in ipairs(G.BRICKS) do if b.alive then dbox(b.x, b.y, 0.5, 0.25, DC.brick, 0.4) end end
        for _, c in ipairs(G.CAPS) do dbox(c.x, c.y, 0.37, 0.17, DC.cap) end
        for _, e in ipairs(G.EN) do if e.alive then dcircle(e.x, e.y, 0.3, DC.enemy) end end
        for _, s in ipairs(G.SHOTS) do G.dbg_bar(WP(s.x, s.py, 0.4), WP(s.x, s.y, 0.4), DC.shot) end
        for _, s in ipairs(G.DSHOT) do dbox(s.x, s.y, 0.12, 0.12, DC.enemy) end
        local Dh = G.doh; if Dh and Dh.alive then dbox(Dh.x, Dh.y, Dh.hw, Dh.hh, DC.enemy, 1.0) end
    end
    for i = D.used + 1, #D.pool do D.pool[i].n:set_position(HIDE) end
end
