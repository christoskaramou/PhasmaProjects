------------------------------------------------------------------ world nodes
local function V(x, y, z) return vec3(x, y, z) end
G.shake = 0
local W = { course = {}, cur = nil }
local NM = {}
local function build_world()
    for k, c in ipairs(COURSES) do
        local list = {}
        for _, m in ipairs(c.meshes) do
            if tnode(m) then list[#list + 1] = clone(m, HIDE) end
        end
        W.course[k] = list
    end
    W.floor = clone("floor", HIDE)
    NM.marble = clone("marble", HIDE); NM.shadow = clone("shadow", HIDE)
    NM.shards = {}
    for i = 1, 10 do NM.shards[i] = { n = clone("shard", HIDE) } end
    NM.pole = clone("flag_pole", HIDE); NM.cloth = clone("flag_cloth", HIDE); NM.chute = clone("chute", HIDE)
end
local ENR = {}
local function enemy_nodes()
    for _, r in ipairs(ENR) do for _, n in pairs(r) do n:set_position(HIDE) end end
    ENR = {}
    for i, e in ipairs(G.EN) do
        local r = {}
        if e.k == "steelie" then r.ball = clone("steelie", HIDE); r.sh = clone("shadow", HIDE)
        elseif e.k == "muncher" then r.coil = clone("mun_coil", HIDE); r.head = clone("mun_head", HIDE); r.eye = clone("mun_eye", HIDE)
        elseif e.k == "acid" then r.blob = clone("acid", HIDE)
        elseif e.k == "hammer" then r.post = clone("ham_post", HIDE); r.head = clone("ham_head", HIDE) end
        ENR[i] = r
    end
end
-- node reuse: course switch hides the old course and shows the new (meshes are authored in world space)
-- Every other course is hidden explicitly. (Bug fix: reset_world() used to clear W.cur without hiding the course that
-- was showing, so after a game over on race 2+ and a new game, that course's geometry stayed visible on top of the
-- Practice Race: its higher funnel buried the start platform, which looked low, and the marble seemed trapped.)
local function show_course(k)
    if W.cur == k then return end
    for kk, list in ipairs(W.course) do if kk ~= k then for _, n in ipairs(list) do n:set_position(HIDE) end end end
    for _, n in ipairs(W.course[k]) do n:set_position(V(0, 0, 0)) end
    W.cur = k
    local c = COURSES[k]
    W.floor:set_position(V(c.nx / 2, c.lo - 7, c.nz / 2)); W.floor:set_scale(V(c.nx * 3, 1, c.nz * 3))
    local g = c.goal
    local gx, gz = g[3] + 0.1, (g[2] + g[4]) / 2
    local gy = G.hgt((g[1] + g[3]) / 2, gz) or 0
    NM.pole:set_position(V(gx, gy, gz)); NM.cloth:set_position(V(gx, gy, gz))
    local s = c.start
    NM.chute:set_position(V(s[1], (G.hgt(s[1], s[2]) or 0) + 3.2, s[2]))
    G.ens_ver = nil
end
G.show_course = show_course
function G.reset_world() W.cur = nil end

-- render interpolation: the simulation runs at a fixed 60 Hz, the display at any rate; draw the state between the
-- last two steps (AL = leftover fraction of a step) so the marble moves the same distance every displayed frame.
local function ip(e, k) local o = e["o" .. k]; local v = e[k]; if not o or abs(v - o) > 3 then return v end; return o + (v - o) * AL end
function G.marble_pos() local M = G.M; return ip(M, "x"), ip(M, "y"), ip(M, "z") end
function G.rendered_pos() local x, y, z = G.marble_pos(); return { x, y, z } end
-- rotation matrix (rows) -> engine euler degrees (engine builds R = Rz * Ry * Rx from set_rotation)
local function mat_euler(m)
    local sy = -m[7]; sy = sy > 1 and 1 or (sy < -1 and -1 or sy)
    local y = math.asin(sy)
    local x, z
    if abs(sy) < 0.9999 then x = atan2(m[8], m[9]); z = atan2(m[4], m[1]) else x = atan2(-m[6], m[5]); z = 0 end
    return V(math.deg(x), math.deg(y), math.deg(z))
end
local function render_world(dt)
    local k = G.ci or 1
    show_course(k)
    if G.ens_ver ~= G.EN then G.ens_ver = G.EN; enemy_nodes() end
    local M = G.M
    NM.cloth:set_rotation(V(0, 8 * sin(G.t * 2.1), 0))
    -- marble
    local vis = M.alive
    local shvis = vis   -- the contact shadow stays on while the marble blinks, so you never lose track of it
    -- respawn grace: the marble blinks while it can't be killed (steady for the last moment so it's clear it ended)
    if vis and (M.inv or 0) > 0.15 and floor(M.inv * 12) % 2 == 1 then vis = false end
    local sq = 1
    local mx, my, mz = G.marble_pos()
    NM.marble:set_position(vis and V(mx, my, mz) or HIDE)
    -- orientation: last step's rotation advanced by the same interpolation fraction (no Euler flips when the heading reverses)
    local Rm = M.rot
    if M.prot and M.wang and M.wang > 0 and AL < 1 then Rm = G.mmul(G.mrot_axis(M.wax, 0, M.waz, M.wang * AL), M.prot) end
    NM.marble:set_rotation(mat_euler(Rm))
    G.rend_R = Rm      -- (tests: per-frame rendered orientation)
    -- contact shadow on the surface under the marble
    local gy = G.hgt(mx, mz)
    if shvis and gy then
        local h = my - R - gy
        local s = clamp(1 - h * 0.12, 0.35, 1) * 0.52
        NM.shadow:set_position(V(mx + 0.06, gy + 0.02, mz + 0.04)); NM.shadow:set_scale(V(s, 1, s))
    else NM.shadow:set_position(HIDE) end
    -- broken-marble shards (break, slam) / dissolved (acid, munch) show no shards
    local d = G.dead
    for i, s in ipairs(NM.shards) do
        if d and (d.kind == "break" or d.kind == "slam") and d.t < 1.6 then
            if d.t == 0 or not s.vx or s.gen ~= d then
                local a = i / #NM.shards * 6.2832
                s.gen = d; s.x, s.y, s.z = M.x, M.y, M.z
                s.vx, s.vy, s.vz = cos(a) * rr(1.5, 3.5), d.kind == "slam" and 0.5 or rr(2, 5), sin(a) * rr(1.5, 3.5)
                s.rx, s.ry = rr(0, 360), rr(0, 360)
            end
            s.vy = s.vy - 18 * dt
            s.x, s.y, s.z = s.x + s.vx * dt, s.y + s.vy * dt, s.z + s.vz * dt
            local fy = G.hgt(s.x, s.z)
            if fy and s.y < fy + 0.05 and s.vy < 0 then s.y = fy + 0.05; s.vy = -s.vy * 0.3; s.vx, s.vz = s.vx * 0.6, s.vz * 0.6 end
            s.rx = s.rx + dt * 400
            s.n:set_position(V(s.x, s.y, s.z)); s.n:set_rotation(V(s.rx, s.ry, s.rx * 0.5))
        else s.n:set_position(HIDE) end
    end
    -- enemies
    for i, e in ipairs(G.EN) do
        local r = ENR[i]
        if r then
            local y = G.hgt(e.x, e.z) or 0
            if e.k == "steelie" then
                local ex, ey, ez = ip(e, "x"), ip(e, "y"), ip(e, "z")
                r.ball:set_position(V(ex, ey, ez)); r.ball:set_rotation(V((e.roll or 0) * 57.3 % 360, math.deg(atan2(e.vx, e.vz)), 0))
                r.sh:set_position(V(ex + 0.06, (G.hgt(ex, ez) or y) + 0.02, ez + 0.04)); r.sh:set_scale(V(0.52, 1, 0.52))
            elseif e.k == "muncher" then
                local hp = sin(e.hop * PI)
                local st = 0.55 + 0.6 * hp
                r.coil:set_position(V(e.x, y, e.z)); r.coil:set_scale(V(1, st, 1))
                r.head:set_position(V(e.x, y + st * 0.9, e.z)); r.head:set_rotation(V(0, math.deg(atan2(M.x - e.x, M.z - e.z)), 0))
                r.eye:set_position(V(e.x, y + st * 0.9, e.z)); r.eye:set_rotation(V(0, math.deg(atan2(M.x - e.x, M.z - e.z)), 0))
            elseif e.k == "acid" then
                local ex, ez = ip(e, "x"), ip(e, "z"); y = G.hgt(ex, ez) or y
                local w = 1 + 0.12 * sin(G.t * 5 + i)
                r.blob:set_position(V(ex, y + 0.03, ez)); r.blob:set_scale(V(w, 1 + 0.2 * sin(G.t * 7 + i), 2 - w))
            elseif e.k == "hammer" then
                r.post:set_position(V(e.x, y, e.z))
                r.head:set_position(V(e.x, y + 0.3 + 2.4 * (1 - e.drop), e.z))
            end
        end
    end
end

------------------------------------------------------------------ camera: fixed isometric-style view that follows the marble
local function update_camera(dt)
    local M = G.M
    local yaw = G.CAM_YAW
    local fx, fz = sin(yaw), cos(yaw)
    local tx, ty, tz = G.marble_pos()
    if G.state == "title" then
        local c = COURSES[G.ci or 1]
        tx, tz = c.nx / 2 + 6 * sin(G.t * 0.1), c.nz * 0.55 + c.nz * 0.3 * sin(G.t * 0.05)
        ty = G.hgt(tx, tz) or (c.lo + 10)
    end
    local L = G.cam.look
    local k = G.cam_snap and 1 or (1 - math.exp(-4 * dt))
    G.cam_snap = false
    L.x, L.y, L.z = L.x + (tx - L.x) * k, L.y + (ty - L.y) * k * 0.7, L.z + (tz - L.z) * k
    local D, H = 21, 25
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.3 * SET:shake_scale()
    cam:set_position(V(L.x - fx * D + a * sin(G.t * 53), L.y + H, L.z - fz * D + a * cos(G.t * 61)))
    cam:look_at(V(L.x, L.y, L.z))
end
-- camera-relative input axes: forward (screen up) and right
function G.cam_axes() local yaw = G.CAM_YAW; local fx, fz = sin(yaw), cos(yaw); return fx, fz, -fz, fx end

------------------------------------------------------------------ collider debug overlay (F3)
G.DBG = { on = false, pool = {}, used = 0, w = 0.05 }
local DC = { me = { .2, 1, .3 }, enemy = { 1, .25, .2 }, wall = { .4, .7, 1 }, goal = { 1, .9, .3 }, check = { .3, .8, 1 } }
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
local function dcircle(x, y, z, r, col, n)
    n = n or 12
    for i = 0, n - 1 do
        local a0, a1 = i / n * 6.2832, (i + 1) / n * 6.2832
        G.dbg_bar(V(x + cos(a0) * r, y, z + sin(a0) * r), V(x + cos(a1) * r, y, z + sin(a1) * r), col)
    end
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and G.state ~= "title" then
        local M, C = G.M, G.CUR
        if M.alive then dcircle(M.x, M.y, M.z, R, DC.me); dcircle(M.x, M.y - R + 0.03, M.z, R * 0.6, DC.me, 8) end
        for _, e in ipairs(G.EN) do
            local y = (G.hgt(e.x, e.z) or 0) + 0.06
            if e.k == "steelie" then dcircle(e.x, e.y, e.z, R, DC.enemy)
            elseif e.k == "muncher" then dcircle(e.x, y, e.z, 0.75, DC.enemy)
            elseif e.k == "acid" then dcircle(e.x, y, e.z, 0.85, DC.enemy)
            elseif e.k == "hammer" then
                local r = 0.75 + R * 0.5
                G.dbg_bar(V(e.x - r, y, e.z - r), V(e.x + r, y, e.z - r), DC.enemy); G.dbg_bar(V(e.x + r, y, e.z - r), V(e.x + r, y, e.z + r), DC.enemy)
                G.dbg_bar(V(e.x + r, y, e.z + r), V(e.x - r, y, e.z + r), DC.enemy); G.dbg_bar(V(e.x - r, y, e.z + r), V(e.x - r, y, e.z - r), DC.enemy)
            end
        end
        -- wall edges (rises taller than a step) near the marble
        local ci, cj = floor(M.x), floor(M.z)
        for j = cj - 6, cj + 6 do for i = ci - 6, ci + 6 do
            local a = G.hgt(i + 0.5, j + 0.5)
            if a then
                local function edge(ni, nj, x0, z0, x1, z1)
                    local b = G.hgt(ni + 0.5, nj + 0.5)
                    if not b or abs(b - a) > STEP + 0.2 then G.dbg_bar(V(x0, (G.hgt(x0 * 0.98 + (i + .5) * .02, z0 * 0.98 + (j + .5) * .02) or a) + 0.04, z0), V(x1, (G.hgt(x1 * 0.98 + (i + .5) * .02, z1 * 0.98 + (j + .5) * .02) or a) + 0.04, z1), DC.wall) end
                end
                edge(i - 1, j, i, j, i, j + 1); edge(i + 1, j, i + 1, j, i + 1, j + 1); edge(i, j - 1, i, j, i + 1, j); edge(i, j + 1, i, j + 1, i + 1, j + 1)
            end
        end end
        local g = C.goal; local gy = (G.hgt((g[1] + g[3]) / 2, (g[2] + g[4]) / 2) or 0) + 0.08
        G.dbg_bar(V(g[1], gy, g[2]), V(g[3], gy, g[2]), DC.goal); G.dbg_bar(V(g[3], gy, g[2]), V(g[3], gy, g[4]), DC.goal)
        G.dbg_bar(V(g[3], gy, g[4]), V(g[1], gy, g[4]), DC.goal); G.dbg_bar(V(g[1], gy, g[4]), V(g[1], gy, g[2]), DC.goal)
        for q, c in ipairs(C.checks) do local y = (G.hgt(c[1], c[2]) or 0) + 0.08; dcircle(c[1], y, c[2], 3, q <= G.check and DC.me or DC.check, 16) end
    end
    for i = D.used + 1, #D.pool do D.pool[i].n:set_position(HIDE) end
end
