------------------------------------------------------------------ rendering
local function V(x, y, z) return vec3(x, y, z) end
G.shake = 0
------------------------------------------------------------------ plane rigs (pooled per kind)
local RIG_MESH = {
    p38 = { "p38_body", "p38_fin", "p38_glass", "p38_mark" },
    zero = EK.zero.meshes, red = EK.red.meshes, mid = EK.mid.meshes, big = EK.big.meshes,
}
local SHMESH = { p38 = "sh_p38", esc = "sh_p38", zero = "sh_zero", red = "sh_zero", mid = "sh_mid", big = "sh_big" }
local RFREE = {}
local function new_rig(kind)
    -- root carries position + heading (yaw); the child 'att' carries pitch + bank, so the bank is a roll about the
    -- plane's OWN nose axis. (The engine's euler applies Z after Y, i.e. about the world axis: rolling the root made a
    -- plane heading down-screen bank the opposite way and a crossing plane pitch instead of bank.)
    local r = { kind = kind, root = empty("rig_" .. kind, nil, HIDE), props = {} }
    r.att = empty("att_" .. kind, r.root)
    for _, m in ipairs(RIG_MESH[kind == "esc" and "p38" or kind]) do clone(m, V(0, 0, 0), nil, r.att) end
    if kind == "p38" or kind == "esc" then
        for _, sx in ipairs({ 0.42, -0.42 }) do r.props[#r.props + 1] = clone("p38_prop", V(sx, 0.01, 0.71), nil, r.att) end
    end
    r.shadow = clone(SHMESH[kind])
    if kind == "esc" then r.root:set_scale(V(0.72, 0.72, 0.72)) end
    return r
end
local function take_rig(kind)
    local f = RFREE[kind]
    if f and #f > 0 then return table.remove(f) end
    return new_rig(kind)
end
local function give_rig(r)
    r.root:set_position(HIDE); r.shadow:set_position(HIDE)
    RFREE[r.kind] = RFREE[r.kind] or {}; table.insert(RFREE[r.kind], r)
end
local function pose_rig(r, x, y, h, yaw, pitch, roll, vis)
    if not vis then r.root:set_position(HIDE); r.shadow:set_position(HIDE); return end
    r.root:set_position(WP(x, y, h)); r.root:set_rotation(V(0, yaw, 0)); r.att:set_rotation(V(pitch or 0, 0, roll or 0))
    local k = clamp(1.2 - h * 0.04, 0.6, 1.2) * ((r.kind == "esc") and 0.72 or 1)
    r.shadow:set_position(WP(x + 0.12 * h, y - 0.18 * h, 0.05)); r.shadow:set_rotation(V(0, yaw, 0)); r.shadow:set_scale(V(k, 1, k))
end
local function yaw_of(h) return -math.deg(h) end
------------------------------------------------------------------ world: ocean tiles, islands, clouds, carrier
local OCEAN = {}
local TILE = 24
local ISL, CLD = {}, {}
local function build_world()
    for i = -2, 2 do for j = 0, 3 do OCEAN[#OCEAN + 1] = { n = clone("ocean", V(0, 0, 0), V(TILE + 0.02, 1, TILE + 0.02)), i = i, j = j } end end
    G.cv = { hull = clone("carrier_hull"), deck = clone("carrier_deck"), isl = clone("carrier_island") }
    G.next_isl, G.next_cld = 0, 0
end
local IFREE = {}
local function itake(m) local f = IFREE[m]; if f and #f > 0 then return table.remove(f) end; return clone(m) end
local function igive(m, n) n:set_position(HIDE); IFREE[m] = IFREE[m] or {}; table.insert(IFREE[m], n) end
local function spawn_island(y0)
    local v = floor(rand() * 3)
    local side = rand() < 0.5 and -1 or 1
    local o = { v = v, x = side * rr(5, 21), y = y0, yaw = rr(0, 360), parts = {} }
    for _, m in ipairs({ "isl_reef" .. v, "isl_sand" .. v, "isl_jungle" .. v }) do o.parts[#o.parts + 1] = { m = m, n = itake(m), dx = 0, dz = 0, h = 0 } end
    for k = 1, 3 + floor(rand() * 4) do
        local a, r = rr(0, 6.28), rr(2.4, 4.6)
        local dx, dz = cos(a) * r, sin(a) * r * 0.65
        o.parts[#o.parts + 1] = { m = "palm_trunk", n = itake("palm_trunk"), dx = dx, dz = dz, h = 0.12, s = rr(0.9, 1.3), ry = rr(0, 360) }
        o.parts[#o.parts + 1] = { m = "palm_leaves", n = itake("palm_leaves"), dx = dx, dz = dz, h = 0.12, s = o.parts[#o.parts].s, ry = o.parts[#o.parts].ry }
    end
    ISL[#ISL + 1] = o
end
local function spawn_cloud(y0)
    local v = floor(rand() * 3)
    CLD[#CLD + 1] = { m = "cloud" .. v, n = itake("cloud" .. v), x = rr(-20, 20), y = y0, h = rr(2.2, 3.0), s = rr(0.8, 1.4), yaw = rr(0, 360) }
end
function G.reset_world()
    for _, o in ipairs(ISL) do for _, p in ipairs(o.parts) do igive(p.m, p.n) end end
    for _, c in ipairs(CLD) do igive(c.m, c.n) end
    ISL, CLD = {}, {}
    G.scroll = 0; G.next_isl = 0; G.next_cld = 0; G.isl_scroll = nil
    for k = 0, 2 do spawn_island(10 + k * 26 + rr(-4, 4)) end
    for k = 0, 3 do spawn_cloud(6 + k * 14) end
end
local function render_world(dt)
    local sc = G.scroll or 0
    local off = sc % TILE
    for _, t in ipairs(OCEAN) do t.n:set_position(V(t.i * TILE, 0, -TILE / 2 + t.j * TILE - off + TILE / 2)) end
    -- islands drift with the scroll
    G.isl_scroll = G.isl_scroll or sc
    local d = sc - G.isl_scroll; G.isl_scroll = sc
    for i = #ISL, 1, -1 do
        local o = ISL[i]
        o.y = o.y - d
        local cy, sy = cos(math.rad(o.yaw)), sin(math.rad(o.yaw))
        for _, p in ipairs(o.parts) do
            local wx, wz = p.dx * cy + p.dz * sy, -p.dx * sy + p.dz * cy
            p.n:set_position(V(-o.x + wx, p.h, o.y + wz)); p.n:set_rotation(V(0, p.ry or o.yaw, 0))
            if p.s then p.n:set_scale(V(p.s, p.s, p.s)) end
        end
        if o.y < -16 then for _, p in ipairs(o.parts) do igive(p.m, p.n) end; table.remove(ISL, i) end
    end
    local top = -99; for _, o in ipairs(ISL) do top = max(top, o.y) end
    if top < FH + 12 then spawn_island(top + rr(22, 34)) end
    for i = #CLD, 1, -1 do
        local c = CLD[i]
        c.y = c.y - d * 1.6
        c.n:set_position(V(-c.x, c.h, c.y)); c.n:set_rotation(V(0, c.yaw, 0)); c.n:set_scale(V(c.s, c.s, c.s))
        if c.y < -14 then igive(c.m, c.n); table.remove(CLD, i) end
    end
    local ctop = -99; for _, c in ipairs(CLD) do ctop = max(ctop, c.y) end
    if ctop < FH + 10 then spawn_cloud(ctop + rr(10, 20)) end
    -- carrier
    local cv = G.cv
    if G.carrier and G.carrier.on and G.carrier.y > -20 then
        local p = V(0, 0, G.carrier.y)
        cv.hull:set_position(p); cv.deck:set_position(p); cv.isl:set_position(p)
    else cv.hull:set_position(HIDE); cv.deck:set_position(HIDE); cv.isl:set_position(HIDE) end
end
------------------------------------------------------------------ planes, shots, POWs
local PR = {}
local ER = {}
local function render_planes(dt)
    -- player
    if not PR.me then PR.me = new_rig("p38"); PR.esc = { new_rig("esc"), new_rig("esc") } end
    local x, y = lerp(P.px, P.x, AL), lerp(P.py, P.y, AL)
    local vis = P.alive and not (P.inv > 0 and floor(G.t * 10) % 2 == 0) and G.state ~= "title"
    local pitch, hh, yo = 0, P.h, 0
    if P.roll > 0 then
        local u = 1 - P.roll / G.ROLL_T
        pitch = -360 * u; hh = P.h + 2.6 * sin(math.pi * u); yo = 1.8 * sin(2 * math.pi * u)
    end
    pose_rig(PR.me, x, y + yo, hh, 0, pitch, P.bank, vis)   -- +bank = roll into the turn (right wing down when moving right)
    for _, pr in ipairs(PR.me.props) do pr:set_rotation(V(0, 0, G.t * 2200 % 360)) end
    for i = 1, 2 do
        local ex, ey = G.esc_pos(i)
        ex, ey = ex - P.x + x, ey - P.y + y
        pose_rig(PR.esc[i], ex, ey + yo, hh, 0, pitch, P.bank, vis and P.esc[i])
        for _, pr in ipairs(PR.esc[i].props) do pr:set_rotation(V(0, 0, G.t * 2200 % 360)) end
    end
    -- enemies
    local seen = {}
    for _, e in ipairs(G.EN) do
        seen[e] = true
        local r = ER[e]
        if not r then r = take_rig(e.kind); ER[e] = r end
        local turn = 0
        if e.ph then turn = ((e.h - e.ph + math.pi) % (2 * math.pi) - math.pi) / max(G.dt, 0.001) end
        e.ph = e.h
        e.bank = damp(e.bank or 0, clamp(turn * 18, -50, 50), 6, G.dt)
        if G.bank_test then e.bank = G.bank_test end   -- test hook (nil in play)
        local hgt = ALT + ((e.kind == "big") and 0.6 or 0) + ((e.kind == "mid") and 0.3 or 0)
        pose_rig(r, e.x, e.y, hgt, yaw_of(e.h), 0, e.bank, not (e.hit_t > 0 and floor(G.t * 30) % 2 == 0))
        if (e.kind == "mid" or e.kind == "big") and e.hp < EK[e.kind].hp * 0.5 and rand() < 0.3 then trail(e.x + rr(-1, 1), e.y - 0.5, hgt) end
    end
    for e, r in pairs(ER) do if not seen[e] then give_rig(r); ER[e] = nil end end
    P_begin("shot"); P_begin("ebul_core"); P_begin("ebul_star")
    for _, s in ipairs(G.SHOTS) do local n = P_get("shot"); n:set_position(WP(s.x, s.y, ALT + 0.05)) end
    -- enemy fire: a white-hot pulsing core inside a spinning magenta star (bloom gives the glow); round and spiky,
    -- so it never reads as the player's elongated yellow tracers or as anything on the sea/islands below
    for i, b in ipairs(G.BUL) do
        local ph = G.t * 16 + i * 1.7
        local p = WP(b.x, b.y, ALT + 0.12)
        local c = P_get("ebul_core"); c:set_position(p); local k = 1.8 + 0.45 * sin(ph); c:set_scale(V(k, k, k))
        local st = P_get("ebul_star"); st:set_position(p); st:set_rotation(V(0, (G.t * 420 + i * 37) % 360, 0))
        local q = 1.3 + 0.16 * sin(ph + 1.6); st:set_scale(V(q, 1, q))
    end
    P_end("shot"); P_end("ebul_core"); P_end("ebul_star")
    for _, c in ipairs({ "red", "green", "white", "gray", "yellow", "orange" }) do P_begin("pow_" .. c) end
    for _, w in ipairs(G.POWS) do
        local n = P_get("pow_" .. w.c)
        n:set_position(WP(w.x, w.y, ALT - 0.6 + 0.15 * sin(w.t * 4))); n:set_rotation(V(18 * sin(w.t * 2.3), 0, 18 * cos(w.t * 1.9))); n:set_scale(V(1.45, 1.45, 1.45))
    end
    for _, c in ipairs({ "red", "green", "white", "gray", "yellow", "orange" }) do P_end("pow_" .. c) end
end
------------------------------------------------------------------ camera
local function update_camera(dt)
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.35 * SET:shake_scale()
    local c, l = G.cam.pos, G.cam.look
    cam:set_position(V(c.x + a * sin(G.t * 53), c.y, c.z + a * cos(G.t * 61)))
    cam:look_at(l)
end
------------------------------------------------------------------ collider debug overlay (F3)
G.DBG = { on = false, pool = {}, used = 0, w = 0.09 }
local DC = { me = { .2, 1, .3 }, enemy = { 1, .25, .2 }, shot = { 1, .9, .3 }, bul = { 1, .5, .1 }, pow = { .3, .8, 1 }, wall = { .4, .7, 1 } }
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
local function dcircle(x, y, r, col, h, n)
    n = n or 10
    h = (h or ALT) + 0.6
    for i = 0, n - 1 do
        local a0, a1 = i / n * 6.2832, (i + 1) / n * 6.2832
        G.dbg_bar(WP(x + cos(a0) * r, y + sin(a0) * r, h), WP(x + cos(a1) * r, y + sin(a1) * r, h), col)
    end
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and G.state ~= "title" then
        local hw = FW / 2
        G.dbg_bar(WP(-hw, 0, ALT), WP(-hw, FH, ALT), DC.wall); G.dbg_bar(WP(hw, 0, ALT), WP(hw, FH, ALT), DC.wall)
        if P.alive then
            dcircle(P.x, P.y, 0.36, DC.me)
            for i = 1, 2 do if P.esc[i] then local ex, ey = G.esc_pos(i); dcircle(ex, ey, 0.3, DC.me, nil, 8) end end
        end
        for _, e in ipairs(G.EN) do for _, c in ipairs(G.circles(e)) do dcircle(c[1], c[2], c[3], DC.enemy, nil, 8) end end
        for _, s in ipairs(G.SHOTS) do G.dbg_bar(WP(s.x, s.py, ALT + 0.6), WP(s.x, s.y, ALT + 0.6), DC.shot) end
        for _, b in ipairs(G.BUL) do dcircle(b.x, b.y, 0.17, DC.bul, nil, 6) end
        for _, w in ipairs(G.POWS) do dcircle(w.x, w.y, 1.25 - 0.5, DC.pow, nil, 10) end
    end
    for i = D.used + 1, #D.pool do D.pool[i].n:set_position(HIDE) end
end
