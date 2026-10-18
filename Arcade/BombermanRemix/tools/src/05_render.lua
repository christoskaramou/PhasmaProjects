------------------------------------------------------------------ static arena
local function V(x, y, z) return vec3(x, y, z) end
local function build_world()
    clone("floor", V((NC + 1) / 2 * CS, 0, (NR + 1) / 2 * CS), V(NC * CS, 1, NR * CS))
    for c = 0, NC + 1 do for r = 0, NR + 1 do
        local border = c == 0 or r == 0 or c == NC + 1 or r == NR + 1
        if border then clone("border", V(c * CS, 0, r * CS))
        elseif c % 2 == 0 and r % 2 == 0 then clone("pillar", V(c * CS, 0, r * CS)); clone("pillar_top", V(c * CS, 0.001, r * CS)) end
    end end
    -- ground beyond the arena
    local g = prim("cube", V(32, -0.6, 14), V(160, 1, 100)); paint(g, { .2, .32, .16 }, { 0, 0, 0 }, .95, 0)
end
function G.build_bricks()
    P_begin("brick")
    for _, br in pairs(BRICKS) do br.node = P_get("brick"); br.node:set_position(V(br.c * CS, 0, br.r * CS)); br.node:set_scale(V(1, 1, 1)); br.node:set_rotation(V(0, 0, 0)) end
    P_end("brick")
end

------------------------------------------------------------------ Bomberman rig
local function grp(parent, pos, meshes)
    local g = empty("grp", parent, pos)
    for _, m in ipairs(meshes) do clone(m, V(0, 0, 0), nil, g) end
    return g
end
local R = {}
local function build_player()
    local root = empty("Bomber", nil, HIDE)
    R.root = root
    R.body = grp(root, V(0, 0.42, 0), { "bm_body", "bm_belt" })
    R.head = grp(root, V(0, 1.0, 0), { "bm_helmet", "bm_face", "bm_eye", "bm_antenna", "bm_knob" })
    R.arm_l = grp(root, V(0.42, 0.95, 0), { "bm_arm", "bm_glove" })
    R.arm_r = grp(root, V(-0.42, 0.95, 0), { "bm_arm", "bm_glove" })
    R.leg_l = grp(root, V(0.16, 0.42, 0), { "bm_leg", "bm_boot" })
    R.leg_r = grp(root, V(-0.16, 0.42, 0), { "bm_leg", "bm_boot" })
    R.shadow = clone("shadow")
end
G.R = R
local AL = 1
local YAW = { down = 0, right = 90, left = -90, up = 180 }
G.vis = { yaw = 0 }
local function render_player(dt)
    if G.hide_player then R.root:set_position(HIDE); R.shadow:set_position(HIDE); return end
    local x, z = lerp(P.ox, P.x, AL) * CS, lerp(P.oz, P.z, AL) * CS
    local VIS = G.vis
    local yt = YAW[P.dir] or 0
    if yt - VIS.yaw > 180 then VIS.yaw = VIS.yaw + 360 elseif VIS.yaw - yt > 180 then VIS.yaw = VIS.yaw - 360 end
    VIS.yaw = damp(VIS.yaw, yt, 20, dt)
    local s = sin(P.ph)
    local ll, lr, al, ar, bob = 0, 0, 0, 0, 0
    if P.moving and P.st == "walk" then ll, lr, al, ar = 35 * s, -35 * s, -30 * s, 30 * s; bob = abs(cos(P.ph)) * 0.06 end
    local sc, rz, ry = 1, 0, VIS.yaw
    if P.st == "dead" then
        local k = clamp(P.dead_t / 1.4, 0, 1)
        ry = VIS.yaw + P.dead_t * 720 * (1 - k); al, ar = 150, 150
        sc = 1 - 0.85 * clamp((P.dead_t - 0.9) / 0.8, 0, 1)
    end
    if P.st == "win" then al, ar = 160 + 15 * sin(G.t * 10), 160 - 15 * sin(G.t * 10); bob = abs(sin(G.t * 8)) * 0.3 end
    local blink = P.inv > 0 and P.inv < 10 and floor(G.t * 12) % 2 == 0 and P.st == "walk"
    R.root:set_position(blink and HIDE or V(x, bob, z))
    R.root:set_rotation(V(0, ry, rz)); R.root:set_scale(V(sc, sc, sc))
    R.leg_l:set_rotation(V(ll, 0, 0)); R.leg_r:set_rotation(V(lr, 0, 0))
    R.arm_l:set_rotation(V(al, 0, -8)); R.arm_r:set_rotation(V(ar, 0, 8))
    R.head:set_rotation(V(0, 0, P.st == "walk" and 0 or 0))
    R.shadow:set_position(V(x, 0.03, z)); R.shadow:set_scale(V(0.45 * sc, 1, 0.45 * sc))
end

------------------------------------------------------------------ dynamic objects (pooled per frame)
local EYE_Y = { ballom = 0.95, onil = 0.72, dahl = 0.9, minvo = 0.85, doria = 0.62, ovape = 1.0, pass = 0.85, pontan = 0.85 }
local EYE_Z = { ballom = 0.66, onil = 0.6, dahl = 0.6, minvo = 0.58, doria = 0.66, ovape = 0.56, pass = 0.6, pontan = 0.2 }
local DYN = { "brick", "brick_chunk", "bomb", "bomb_cap", "bomb_fuse", "bomb_shine", "fl_core", "fl_arm", "fl_end", "fl_inner", "door_frame", "door", "door_light",
    "en_eye", "en_pupil", "en_ballom", "en_onil", "en_dahl", "en_minvo", "en_doria", "en_ovape", "en_pass", "en_pontan", "en_stripe", "shadow", "ring",
    "pu_bombs", "pu_fire", "pu_speed", "pu_wallpass", "pu_detonator", "pu_bombpass", "pu_flamepass", "pu_mystery" }
local function render_dyn(dt)
    for _, k in ipairs(DYN) do if k ~= "brick" then P_begin(k) end end
    local t = G.t
    -- bricks: burning ones shake, char and crumble
    for _, br in pairs(BRICKS) do
        if br.node then
            if br.burn > 0 then
                local k = clamp(1 - br.burn / 0.5, 0, 1)
                local sh = 0.06 * sin(t * 70)
                br.node:set_position(V(br.c * CS + sh, -k * 0.6, br.r * CS)); br.node:set_scale(V(1 - k * 0.3, 1 - k * 0.6, 1 - k * 0.3))
            end
        end
    end
    -- brick chunks: ballistic, bounce once or twice on the floor, shrink away at the end of their life
    for i = #G.CHUNKS, 1, -1 do
        local c = G.CHUNKS[i]
        c.t = c.t + dt
        if c.t >= c.life then table.remove(G.CHUNKS, i) else
            c.vy = c.vy - 26 * dt; c.x = c.x + c.vx * dt; c.y = c.y + c.vy * dt; c.z = c.z + c.vz * dt
            c.rx = c.rx + c.wr * dt; c.ry = c.ry + c.wr * 0.6 * dt
            local h = 0.15 * c.s
            if c.y < h then c.y = h; c.vy = abs(c.vy) * 0.35; c.vx = c.vx * 0.6; c.vz = c.vz * 0.6; c.wr = c.wr * 0.6 end
            local k = clamp((c.life - c.t) / 0.25, 0, 1) * c.s
            local n = P_get("brick_chunk"); n:set_position(V(c.x, c.y, c.z)); n:set_rotation(V(c.rx, c.ry, 0)); n:set_scale(V(k, k, k))
        end
    end
    -- hidden items revealed
    if EXIT.exposed then
        local x, z = EXIT.c * CS, EXIT.r * CS
        P_get("door_frame"):set_position(V(x, 0, z)); P_get("door"):set_position(V(x, 0, z))
        local dl = P_get("door_light")
        dl:set_position(EXIT.open and V(x, 0, z + 0.002) or HIDE)
    end
    if PU.exposed and not PU.taken then
        local n = P_get("pu_" .. PU.kind)
        n:set_position(V(PU.c * CS, 0.05 + 0.08 * sin(t * 4), PU.r * CS))
    end
    -- bombs: breathe while the fuse burns, fuse sparks
    for _, b in ipairs(BOMBS) do
        local x, z = b.c * CS, b.r * CS
        local p = 1 + 0.08 * sin(b.age * (b.remote and 6 or (8 + (G.CONST.FUSE - b.t) * 6)))
        for _, m in ipairs({ "bomb", "bomb_cap", "bomb_fuse", "bomb_shine" }) do
            local n = P_get(m); n:set_position(V(x, 0, z)); n:set_scale(V(p, 2 - p, p))
        end
        local sd = P_get("shadow"); sd:set_position(V(x, 0.03, z)); sd:set_scale(V(0.75, 1, 0.75))
        b.spark = (b.spark or 0) - dt
        if b.spark <= 0 then b.spark = 0.09; G.FX:sparks(V(x + 0.2 * p, 1.6, z), 3, 0.6, V(0, 1.2, 0), { 2.2, 1.6, .7 }, -5)
            G.FX:burst("ember", { pos = V(x + 0.2 * p, 1.65, z), count = 1, c0 = { 2, 1.3, .5, 1 }, c1 = { 1, .3, .05, 0 }, smin = .12, smax = .16, lmin = .08, lmax = .12, radius = 0, spread = 0 }) end
    end
    -- flames: a slim white-hot core keeps the burning cells readable; the body of the flame is particles
    for _, f in ipairs(FLS) do
        local k = f.t / G.CONST.FLAME_T
        local w = 0.55 + 0.55 * sin(PI * clamp(1 - k, 0, 1) ^ 0.6) + 0.05 * sin(t * 40 + f.c)
        local x, z = f.c * CS, f.r * CS
        local live = (G.CONST.FLAME_T - f.t) >= (f.fxd or 0)
        local inner = P_get("fl_inner"); inner:set_position(live and V(x, 0.02, z) or HIDE); inner:set_rotation(V(0, f.ax or 0, 0))
        inner:set_scale(f.kind == "core" and V(w * 0.6, w * 0.6, 0.35 * w) or V(w * 0.36, w * 0.36, f.kind == "end" and 0.6 or 1))
        f.fx = (f.fx or (f.fxd or 0)) - dt
        if f.fx <= 0 then f.fx = 0.06; G.fx_flame(x, z, f.kind == "core", k) end
    end
    -- enemies
    for _, e in ipairs(ENEMIES) do
        local x, z = lerp(e.ox, e.x, AL) * CS, lerp(e.oz, e.z, AL) * CS
        local def = EN[e.k]
        local hop = abs(sin(e.ph * 6)) * 0.15
        local sc, ry, rx = 1, 0, 0
        if e.k == "pontan" then ry = e.ph * 260 end
        if e.k == "ovape" or e.k == "doria" then hop = 0.1 + 0.1 * sin(e.ph * 3) end
        if not e.alive then
            local k = clamp(e.die_t / 1.0, 0, 1)
            ry = e.die_t * 900; sc = 1 - k; hop = k * 1.2
        end
        local vis = not (e.inv > 0 and floor(t * 16) % 2 == 0)
        local pos = vis and V(x, hop, z) or HIDE
        local n = P_get(def[1]); n:set_position(pos); n:set_rotation(V(rx, ry, 0)); n:set_scale(V(sc, sc * (1 + 0.06 * sin(e.ph * 12)), sc))
        if e.k == "pass" then local s2 = P_get("en_stripe"); s2:set_position(pos); s2:set_scale(V(sc * 1.05, sc, sc * 1.05)) end
        if e.k ~= "pontan" then
            local ey, ez = EYE_Y[e.k] * sc + hop, EYE_Z[e.k] * sc
            local ep = vis and V(x, ey, z + ez) or HIDE
            local ee = P_get("en_eye"); ee:set_position(ep); ee:set_scale(V(sc, sc, sc))
            local pp = P_get("en_pupil")
            pp:set_position(vis and V(x + (e.dx or 0) * 0.07 * sc, ey - 0.02 + ((e.dz or 0) < 0 and 0.05 or 0), z + ez + 0.02) or HIDE); pp:set_scale(V(sc, sc, sc))
        end
        local sd = P_get("shadow"); sd:set_position(V(x, 0.03, z)); sd:set_scale(V(0.55 * sc, 1, 0.55 * sc))
    end
    for _, k in ipairs(DYN) do if k ~= "brick" then P_end(k) end end
end

------------------------------------------------------------------ camera: tilted top-down, scrolls along X with the player
G.shake = 0
local CAM_D, CAM_P = 46, math.rad(62)
local function update_camera(dt)
    G.shake = max(0, G.shake - dt * 2.2)
    local a = G.shake * G.shake * 0.5 * SET:shake_scale()
    local ox, oz = a * sin(G.t * 53), a * cos(G.t * 61)
    local C = G.cam
    if G.cam_ov then
        local o = G.cam_ov; cam:set_position(V(o[1], o[2], o[3])); cam:look_at(V(o[4], o[5], o[6])); C.tx, C.tz = o[4], o[6]; return
    end
    local half = CAM_D * math.tan(VFOV / 2) * SW / SH * 0.92
    local lo, hi = half - 1.5, (NC + 1) * CS + 1.5 - half
    local want = G.hide_player and (G.title_x or 32) or lerp(P.ox, P.x, AL) * CS
    local tx = lo < hi and clamp(want, lo, hi) or (NC + 1) / 2 * CS
    C.tx = damp(C.tx, tx, 6, dt)
    C.tz = (NR + 1) / 2 * CS + 0.4
    cam:set_position(V(C.tx + ox, CAM_D * sin(CAM_P), C.tz + CAM_D * cos(CAM_P) + oz))
    cam:look_at(V(C.tx + ox * 0.5, 0, C.tz + oz * 0.5))
end

------------------------------------------------------------------ collider debug overlay (F3): boxes on the ground plane
G.DBG = { on = false, pool = {}, used = 0, y = 2.3, w = 0.09 }
local DC = { wall = { .2, .9, 1 }, brick = { 1, .8, .2 }, player = { .2, 1, .3 }, enemy = { 1, .25, .2 }, flame = { 1, .55, .1 }, bomb = { .8, .4, 1 }, item = { 1, .4, .9 } }
function G.dbg_bar(x0, z0, x1, z1, col)
    local D = G.DBG
    D.used = D.used + 1
    local b = D.pool[D.used]
    if not b then
        if #D.pool >= 2500 then return end
        b = { n = prim("cube", HIDE, V(1, 1, 1)), col = nil }
        D.pool[D.used] = b
    end
    if b.col ~= col then b.col = col; paint(b.n, { col[1] * .3, col[2] * .3, col[3] * .3 }, { col[1] * 1.4, col[2] * 1.4, col[3] * 1.4 }, 0.5, 0) end
    local dx, dz = x1 - x0, z1 - z0
    b.n:set_position(V((x0 + x1) * .5, D.y, (z0 + z1) * .5))
    b.n:set_rotation(V(0, -math.deg(atan2(dz, dx)), 0))
    b.n:set_scale(V(sqrt(dx * dx + dz * dz) + D.w, D.w, D.w))
end
local function dbox(cx, cz, hx, hz, c)   -- centre + half extents in cells
    local x0, x1, z0, z1 = (cx - hx) * CS, (cx + hx) * CS, (cz - hz) * CS, (cz + hz) * CS
    G.dbg_bar(x0, z0, x1, z0, c); G.dbg_bar(x1, z0, x1, z1, c); G.dbg_bar(x1, z1, x0, z1, c); G.dbg_bar(x0, z1, x0, z0, c)
end
function G.dbg_draw()
    local D = G.DBG
    D.used = 0
    if D.on and G.ST() then
        local cx = floor(G.cam.tx / CS + 0.5)
        for c = max(0, cx - 14), min(NC + 1, cx + 14) do for r = 0, NR + 1 do
            local s = solid_raw(c, r)
            if s == 1 then dbox(c, r, 0.5, 0.5, DC.wall) elseif s == 2 then dbox(c, r, 0.47, 0.47, DC.brick) end
        end end
        for _, b in ipairs(BOMBS) do dbox(b.c, b.r, 0.44, 0.44, DC.bomb) end
        for _, f in ipairs(FLS) do dbox(f.c, f.r, 0.4, 0.4, DC.flame) end
        if P.st ~= "dead" then dbox(P.x, P.z, G.CONST.HW, G.CONST.HW, DC.player); dbox(P.x, P.z, G.CONST.HIT_EN / 2, G.CONST.HIT_EN / 2, DC.player) end
        for _, e in ipairs(ENEMIES) do if e.alive then dbox(e.x, e.z, G.CONST.HIT_EN / 2, G.CONST.HIT_EN / 2, DC.enemy) end end
        if PU.exposed and not PU.taken then dbox(PU.c, PU.r, 0.3, 0.3, DC.item) end
        if EXIT.exposed then dbox(EXIT.c, EXIT.r, 0.3, 0.3, DC.item) end
    end
    for i = D.used + 1, #D.pool do D.pool[i].n:set_position(HIDE) end
end
