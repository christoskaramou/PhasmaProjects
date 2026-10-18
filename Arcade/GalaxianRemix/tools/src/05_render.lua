------------------------------------------------------------------ world nodes
local function V(x, y, z) return vec3(x, y, z) end
G.shake = 0
local RIG = {
    drone = { "drone_body", "drone_wing", "drone_eye" }, purple = { "purple_body", "purple_wing", "purple_eye" },
    red = { "red_body", "red_wing", "red_eye" }, flag = { "flag_body", "flag_wing", "flag_eye" },
    ship = { "gx_body", "gx_accent", "gx_glass", "gx_engine" },
}
local ALLM = {}
for _, n in ipairs(RIG.ship) do ALLM[n] = true end
-- alien rigs (pooled per kind): root = position + heading (yaw), child 'att' = bank (roll about the alien's OWN nose).
-- The engine applies an euler Z after Y, i.e. about the world axis, so rolling a yawed node directly banks the
-- wrong way (or pitches) depending on the heading; the child keeps the bank local in every direction.
local ARFREE, AR = {}, {}
local function alien_rig(k)
    local f = ARFREE[k]
    if f and #f > 0 then return table.remove(f) end
    local r = { k = k, root = empty("alien_" .. k, nil, HIDE) }
    r.att = empty("alien_att_" .. k, r.root)
    local m = RIG[k]
    r.body = clone(m[1], V(0, 0, 0), nil, r.att); r.wing = clone(m[2], V(0, 0.002, 0), nil, r.att); r.eye = clone(m[3], V(0, 0, 0), nil, r.att)
    return r
end
local function alien_rig_free(r) r.root:set_position(HIDE); ARFREE[r.k] = ARFREE[r.k] or {}; table.insert(ARFREE[r.k], r) end
for _, n in ipairs({ "pshot", "bomb", "wflag_pole", "wflag_cloth", "star_w", "star_b", "star_y", "star_r" }) do ALLM[n] = true end
local W = { stars = {} }
local STARC = { "star_w", "star_w", "star_b", "star_y", "star_r" }
local function build_world()
    -- a gas giant far below the field, and a slowly scrolling, twinkling starfield (Galaxian's stars scroll down)
    W.planet = clone("planet", WP(-46, 44, -55), V(8, 8, 8))
    W.ring = clone("planet_ring", WP(-46, 44, -55), V(8, 0.25, 8))
    W.ring:set_rotation(V(20, 0, -24))
    for i = 1, 170 do
        W.stars[i] = { x = rr(-24, 24), y = rr(-10, 40), h = rr(-14, -7), c = STARC[(i % #STARC) + 1], ph = rr(0, 6.28), rate = rr(1.5, 4) }
    end
end
function G.reset_world() end
local function pose(list, x, y, h, yaw, roll, sc)
    for _, mname in ipairs(list) do
        local n = P_get(mname); n:set_position(WP(x, y, h or 0)); n:set_rotation(V(0, yaw or 0, roll or 0))
        n:set_scale(sc and V(sc, sc, sc) or V(1, 1, 1))
    end
end
local function render_world(dt)
    for mname in pairs(ALLM) do P_begin(mname) end
    local P = G.P
    W.planet:set_rotation(V(0, G.t * 2 % 360, 12))
    -- stars
    for _, s in ipairs(W.stars) do
        s.y = s.y - dt * 2.4
        if s.y < -10 then s.y = s.y + 50; s.x = rr(-24, 24) end
        if sin(G.t * s.rate + s.ph) > -0.55 then
            local n = P_get(s.c); n:set_position(WP(s.x, s.y, s.h))
            local k = 0.8 + 0.4 * sin(G.t * s.rate * 0.7 + s.ph); n:set_scale(V(k, k, k))
        end
    end
    -- aliens: bank into the turn (turn rate from the heading change; + roll = right wing down = turning right)
    local seen = {}
    local fdt = max(G.dt or dt, 0.001)
    for _, a in ipairs(G.A) do
        if a.alive and a.grow > 0 then
            seen[a] = true
            local r = AR[a]
            if not r then r = alien_rig(a.k); AR[a] = r end
            local g = a.grow; local sc = g * g * (3 - 2 * g) * AS
            local fast = a.st ~= "form"
            local flap = 0.5 + 0.5 * sin(G.t * (fast and 14 or 6) + a.col * 0.7 + a.row)
            local ang = a.ang or 180
            local turn = 0                                  -- deg/s to the alien's right (heading decreases when turning right)
            if a.pang and fast then turn = -(((ang - a.pang) + 180) % 360 - 180) / fdt end
            a.pang = ang
            a.bank = damp(a.bank or 0, fast and clamp(turn * 0.3, -40, 40) or 0, 8, fdt)
            if G.bank_test then a.bank = G.bank_test end   -- test hook (nil in play)
            local h = 0.3 + (fast and 0.25 or 0)
            r.root:set_position(WP(a.x, a.y, h)); r.root:set_rotation(V(0, ang, 0)); r.root:set_scale(V(sc, sc, sc))
            r.att:set_rotation(V(0, 0, a.bank))
            r.wing:set_scale(V(1 - 0.3 * flap, 1 + 0.4 * flap, 1))
        end
    end
    for a, r in pairs(AR) do if not seen[a] then alien_rig_free(r); AR[a] = nil end end
    -- the Galaxip, its loaded missile and engine glow
    if P.alive then
        local roll = clamp(P.vx * 3.5, -25, 25)   -- + = right wing down when moving right (roll into the move)
        pose(RIG.ship, P.x, P.y, 0.3, 0, roll, SS)
        if not P.shot then local n = P_get("pshot"); n:set_position(WP(P.x, P.y + 0.62 * SS, 0.32)); n:set_rotation(V(0, 0, 0)); n:set_scale(V(SS, SS, SS)) end
    end
    -- engine glow trail behind the Galaxip, fire trail behind the missile in flight
    FX:trail_at(TR.engine, P.alive and WP(P.x, P.y - 0.52 * SS, 0.32) or nil, P.alive and 70 or 0)
    local sh = P.shot
    local my = sh and sh.y - 0.25
    local prev = (sh and TR.my_prev and TR.my_prev < my and my - TR.my_prev < 6) and TR.my_prev or my
    -- streak length follows the per-frame spacing so low frame rates don't break the trail into dots
    local ss = sh and clamp((my - prev) / 3 * 1.3, 0.22, 0.42) or 0.26
    for i, id in ipairs(TR.missile) do
        FX:trail_at(id, sh and WP(sh.x, my + (prev - (my or 0)) * (i - 1) / 3, 0.32) or nil, sh and 160 or 0)
        if sh then pcall(particles.set_emitter, id, { size_min = ss, size_max = ss * 1.2 }) end
    end
    TR.my_prev = my
    if P.shot then local n = P_get("pshot"); n:set_position(WP(P.shot.x, P.shot.y, 0.32)); n:set_rotation(V(0, 0, 0)); n:set_scale(V(SS, SS, SS)) end
    for _, b in ipairs(G.BOMBS) do local n = P_get("bomb"); n:set_position(WP(b.x, b.y, 0.35)); n:set_scale(V(1.2, 1.2, 1.2)); n:set_rotation(V(0, 180 + math.deg(math.atan(b.vx / -b.vy)), 0)) end
    -- reserve ships (bottom left) and wave flags (bottom right), as on the arcade screen
    for i = 1, (G.state == "title") and 0 or min(G.ships, 6) do pose({ "gx_body", "gx_accent", "gx_glass" }, -XMAX - 1.6 - (i - 1) * 0.85, 0.6, 0.2, 0, 0, 0.7) end
    local nf = (G.state == "title") and 0 or min(G.wave, 10)
    for i = 1, nf do
        local x = XMAX + 1.5 + (i - 1) * 0.5
        pose({ "wflag_pole" }, x, 0.6, 0.2, 0, 0)
        local c = P_get("wflag_cloth"); c:set_position(WP(x, 0.6, 0.2)); c:set_rotation(V(0, 0, 4 * sin(G.t * 3 + i))); c:set_scale(V(1, 1, 1))
    end
    for mname in pairs(ALLM) do P_end(mname) end
end
G.exhaust = exhaust

------------------------------------------------------------------ camera: high view down the field, slightly tilted
local function update_camera(dt)
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.3 * SET:shake_scale()
    local pos, look = WP(a * sin(G.t * 53), -5.0 + a * cos(G.t * 61), 25.5), WP(0, 9.4, 0)
    if G.cam_test then pos, look = G.cam_test[1], G.cam_test[2] end     -- screenshot/test override (unset in play)
    cam:set_position(pos); cam:look_at(look)
    G.cam.pos, G.cam.look = pos, look
end

------------------------------------------------------------------ collider debug overlay (F3)
G.DBG = { on = false, pool = {}, used = 0, w = 0.04 }
local DC = { me = { .2, 1, .3 }, enemy = { 1, .25, .2 }, form = { 1, .7, .2 }, edge = { .4, .7, 1 }, shot = { 1, .95, .4 } }
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
local function dbox(x, y, hx, hy, col, h)
    h = h or 0.6
    local a, b, c, d = WP(x - hx, y - hy, h), WP(x + hx, y - hy, h), WP(x + hx, y + hy, h), WP(x - hx, y + hy, h)
    G.dbg_bar(a, b, col); G.dbg_bar(b, c, col); G.dbg_bar(c, d, col); G.dbg_bar(d, a, col)
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and G.state ~= "title" then
        local P = G.P
        G.dbg_bar(WP(-XMAX - SHIP_HB[1], -0.2, 0.6), WP(-XMAX - SHIP_HB[1], 20, 0.6), DC.edge)
        G.dbg_bar(WP(XMAX + SHIP_HB[1], -0.2, 0.6), WP(XMAX + SHIP_HB[1], 20, 0.6), DC.edge)
        if P.alive then dbox(P.x, P.y, SHIP_HB[1], SHIP_HB[2], DC.me) end
        for _, a in ipairs(G.A) do if a.alive then local hb = HB[a.k]; dbox(a.x, a.y, hb[1], hb[2], a.st == "form" and DC.form or DC.enemy, 0.62) end end
        if P.shot then G.dbg_bar(WP(P.shot.x, P.shot.py - 0.18, 0.6), WP(P.shot.x, P.shot.y + 0.14, 0.6), DC.shot) end
        for _, b in ipairs(G.BOMBS) do dbox(b.x, b.y - 0.02, 0.05, 0.14, DC.enemy, 0.6) end
    end
    for i = D.used + 1, #D.pool do D.pool[i].n:set_position(HIDE) end
end
