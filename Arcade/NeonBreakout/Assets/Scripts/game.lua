-- NEON BREAKOUT  (PhasmaEngine, Lua)
-- A modern remake of Atari's Breakout (1976). Faithful core rules:
--   8 rows x 14 bricks, two rows each of yellow (1), green (3), orange (5) and red (7) points;
--   the ball speeds up after 4 hits, after 12 hits and on first contact with the orange and red rows;
--   the paddle shrinks to half width once the ball reaches the top wall; 3 balls; a second wall after the first.
-- Modern extras: bevelled PBR/emissive bricks, shard + spark particles, ball trails, dynamic lights, bloom,
-- screen shake, mouse+keyboard control, and NEON stages (levels 2+) with multi-hit steel bricks and power-ups.
local PI, TAU = math.pi, math.pi * 2
local sin, cos, sqrt, rand, floor, abs, min, max = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local G = { state = "boot", t = 0 }
_G.BO = G

------------------------------------------------------------------ deferred materials
-- Engine quirk: material writes in the same frame a node is created are ignored, so every
-- write is applied now AND replayed a couple of frames later.
local _mset, _mtex, _mds = material.set, material.set_texture, material.set_double_sided
local mat_q = {}
local function qpush(f) mat_q[#mat_q + 1] = { f = f, n = 0 } end
local function mset(n, k, v) pcall(_mset, n, k, v); qpush(function() pcall(_mset, n, k, v) end) end
local function mtex(n, k, v) qpush(function() pcall(_mtex, n, k, v) end) end
local function flush_mats()
    for i = #mat_q, 1, -1 do
        local q = mat_q[i]; q.n = q.n + 1
        if q.n == 2 or q.n == 6 then q.f() end
        if q.n >= 6 then table.remove(mat_q, i) end
    end
end
-- live material writes on already-resolved meshes (no replay needed)
local function mlive(n, k, v) pcall(_mset, n, k, v) end
local function paint(n, base, emis, rough, metal)
    mset(n, "base_color", vec4(base[1], base[2], base[3], 1))
    mset(n, "emissive", vec3(emis[1], emis[2], emis[3]))
    mset(n, "roughness", rough or 0.3)
    mset(n, "metallic", metal or 0.0)
end

------------------------------------------------------------------ audio
local function sfx(name) pcall(audio.play, name .. ".wav") end

------------------------------------------------------------------ playfield constants
local COLS, ROWS = 14, 8
local BW, BH = 2.0, 0.8           -- brick cell size
local HW = COLS * BW * 0.5        -- inner half width (14)
local TOP = 15.0                  -- inner top wall y
local BRICK_TOP = 11.6            -- y of the top row centre
local PADDLE_Y = -13.0
local BOTTOM = -16.5              -- ball lost below this
local BALL_R = 0.36
local PADDLE_H = 0.6

------------------------------------------------------------------ render setup
local function S(k, v) pcall(settings.set, k, v) end
local ss = scene.add_empty_node("BreakoutSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "neon.hdr")
S("taa", true); S("motion_blur", false)          -- TAA on (RENDER_SETTINGS.md); motion blur smears bloom
S("hdr", true)             -- R16F targets: bloom survives TAA
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.8)   -- weaker + smooth (no stair-steps)
S("tonemapping", true); S("fxaa", false); S("cas_sharpening", true)
S("ssao", false); S("ssr", false); S("dof", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0)
S("IBL", true); S("IBL_intensity", 1.0)
S("color_grading", true); S("color_grading_saturation", 1.15); S("color_grading_contrast", 1.1)

local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1280, surf.height or 720
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local CAM_BASE = vec3(0, -9.0, 62.0)
local CAM_LOOK = vec3(0, 0.2, 0)
local FOVX = 1.0
pcall(function() cam:set_fov(math.deg(FOVX)) end)
cam:set_position(CAM_BASE); cam:look_at(CAM_LOOK)

------------------------------------------------------------------ templates (cooked meshes in the .pescene) -> clones
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[Breakout] missing template " .. name); return nil end
    TPL[name] = { node = n, mesh = n:get_mesh_refs()[1] }
    return TPL[name]
end
local seq = 0
local function clone(name, pos, scale, parent)
    local t = tpl(name); seq = seq + 1
    local n = scene.add_empty_node(name .. "_c" .. seq)
    if t and t.mesh then n:add_mesh_ref(t.mesh) end
    if parent then n:set_parent(parent) end
    n:set_position(pos or vec3(0, 0, 0))
    if scale then n:set_scale(scale) end
    return n
end
local function swap_mesh(n, from, to)
    local a, b = tpl(from), tpl(to)
    if a and b then pcall(n.remove_mesh_ref, n, a.mesh); n:add_mesh_ref(b.mesh) end
end
local function prim(kind, pos, scale)
    seq = seq + 1
    local n = scene.add_empty_node(kind .. "_p" .. seq)
    scene.attach_primitive(n, kind)
    n:set_position(pos); n:set_scale(scale)
    return n
end
local HIDE = vec3(0, -1000, 0)

------------------------------------------------------------------ palette / template materials
-- brick slots: 0 red 1 orange 2 green 3 yellow 4 cyan 5 magenta 6 violet 7 white 8 steel 9 steel(cracked) 10 gold
local PAL = {
    [0] = { 1.00, 0.08, 0.14 }, { 1.00, 0.30, 0.00 }, { 0.15, 1.00, 0.15 }, { 1.00, 0.95, 0.25 },
    { 0.10, 0.85, 1.00 }, { 1.00, 0.20, 0.85 }, { 0.55, 0.30, 1.00 }, { 0.90, 0.95, 1.00 },
    { 0.62, 0.68, 0.80 }, { 0.50, 0.42, 0.52 }, { 1.00, 0.72, 0.20 },
}
G.glow = 1.0
local function paint_bricks(glow)
    for i = 0, 10 do
        local c = PAL[i]
        local b, f = tpl("T_brick_" .. i), tpl("T_face_" .. i)
        if i == 8 or i == 9 or i == 10 then
            -- metal bricks: polished PBR, faint glow
            paint(b.node, c, { c[1] * 0.04, c[2] * 0.04, c[3] * 0.05 }, i == 9 and 0.45 or 0.12, 1.0)
            local e = (i == 10) and 1.6 or (i == 9 and 0.5 or 0.9)
            paint(f.node, c, { c[1] * e, c[2] * e, c[3] * e }, 0.2, 0.0)
        else
            -- glossy coloured glass-like body + bright emissive face plate (blooms)
            paint(b.node, { c[1] * 0.8, c[2] * 0.8, c[3] * 0.8 }, { c[1] * 0.28 * glow, c[2] * 0.28 * glow, c[3] * 0.28 * glow }, 0.1, 0.5)
            paint(f.node, c, { c[1] * 1.15 * glow + 0.1, c[2] * 1.15 * glow + 0.1, c[3] * 1.15 * glow + 0.1 }, 0.25, 0.0)
        end
        local sh = tpl("T_shard_" .. math.min(i, 7))
        if i <= 7 then paint(sh.node, c, { c[1] * 1.2, c[2] * 1.2, c[3] * 1.2 }, 0.2, 0.2) end
    end
end

------------------------------------------------------------------ backdrop + frame
local function build_world()
    local bg = prim("quad", vec3(0, 2, -30), vec3(150, 94, 1))
    paint(bg, { 0, 0, 0 }, { 0.55, 0.55, 0.62 }, 1.0, 0.0)
    pcall(_mds, bg, true); qpush(function() pcall(_mds, bg, true) end)
    mtex(bg, "emissive", "Textures/backdrop.png")
    G.backdrop = bg
    -- dark glossy back plate behind the playfield (catches light from the ball and flashes)
    local plate = prim("cube", vec3(0, (TOP + BOTTOM) * 0.5 + 0.8, -1.4), vec3(HW * 2 + 0.6, TOP - BOTTOM + 1.0, 0.4))
    paint(plate, { 0.05, 0.05, 0.09 }, { 0.55, 0.55, 0.75 }, 0.42, 0.6)
    mtex(plate, "emissive", "Textures/playfield.png")
    G.plate = plate
    -- frame rails (chrome) with neon inner strips
    local T = 1.2
    -- side rails run from below the floor line to the very top of the top rail so the corners close
    local yb, yt = BOTTOM - 1.0, TOP + T
    local rails = {
        { vec3(-HW - T * 0.5, (yb + yt) * 0.5, 0), vec3(T, yt - yb, 1.4) },
        { vec3(HW + T * 0.5, (yb + yt) * 0.5, 0), vec3(T, yt - yb, 1.4) },
        { vec3(0, TOP + T * 0.5, 0), vec3(HW * 2 + T * 2, T, 1.4) },
    }
    for _, r in ipairs(rails) do clone("T_rail", r[1], r[2]) end
    paint(tpl("T_rail").node, { 0.55, 0.58, 0.68 }, { 0.0, 0.0, 0.0 }, 0.16, 1.0)
    -- neon strips sit IN FRONT of the rail face (rail front is z=0.7); they used to be buried inside the
    -- rail (z 0.2..0.5), which made the border show only in broken segments / z-fight.
    local g, gz = 0.22, 0.82
    local gy = (yb + TOP + g) * 0.5
    clone("T_rail_glow", vec3(-HW - g * 0.5, gy, gz), vec3(g, TOP + g - yb, 0.12))
    clone("T_rail_glow", vec3(HW + g * 0.5, gy, gz), vec3(g, TOP + g - yb, 0.12))
    clone("T_rail_glow", vec3(0, TOP + g * 0.5, gz), vec3(HW * 2 + g * 2, g, 0.12))
    G.rail_glow = tpl("T_rail_glow").node
    paint(G.rail_glow, { 0.2, 0.9, 1 }, { 0.3, 1.4, 2.2 }, 0.3, 0)
end

------------------------------------------------------------------ dynamic lights
local function add_point()
    lights.add_point()
    return #lights.get_point_lights() - 1
end
-- Engine bug: the position passed to lights.set_point_light is overwritten every frame from the light's
-- scene node (lights.add_point creates one at the origin), so we also move that node.
local LNODE = {}
local LIGHT_GAIN = 0.12   -- intensities below were authored before the light-position fix; scale to taste
local function set_point(i, pos, col, inten, rad)
    pcall(lights.set_point_light, i, pos, col, inten * LIGHT_GAIN, rad)
    local n = LNODE[i]
    if n == nil then
        local l = lights.get_point_lights()[i + 1]
        n = (l and scene.find_model(l.name)) or false
        LNODE[i] = n
    end
    if n then n:set_position(pos) end
end
local L = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(-0.25, -0.55, -1.0), vec3(0.75, 0.8, 1.0), 1.6)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    L.key_l = addp(vec3(-HW - 6, 8, 14), vec3(0.3, 0.75, 1.0), 60, 60)
    L.key_r = addp(vec3(HW + 6, 8, 14), vec3(1.0, 0.3, 0.8), 60, 60)
    L.paddle = addp(vec3(0, PADDLE_Y, 3), vec3(0.3, 0.9, 1.0), 14, 9)
    L.balls = {}
    for i = 1, 3 do L.balls[i] = addp(HIDE, vec3(1, 1, 1), 0, 1) end
    L.flash = {}
    for i = 1, 5 do L.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1, pos = HIDE, col = vec3(1, 1, 1), power = 0, rad = 6 } end
end
local flash_next = 1
local function flash(x, y, col, power, life, rad)
    local f = L.flash[flash_next]; flash_next = flash_next % #L.flash + 1
    f.t, f.life, f.pos, f.col, f.power, f.rad = 0, life or 0.35, vec3(x, y, 2.2), vec3(col[1], col[2], col[3]), power or 30, rad or 7
end
local function update_flashes(dt)
    for _, f in ipairs(L.flash) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = 1 - clamp(f.t / f.life, 0, 1)
            set_point(f.idx, f.pos, f.col, f.power * k * k, f.rad)
            if f.t >= f.life then set_point(f.idx, HIDE, f.col, 0, 1) end
        end
    end
end

------------------------------------------------------------------ levels
-- slot chars: 0 red 1 orange 2 green 3 yellow 4 cyan 5 magenta 6 violet 7 white  S steel(2 hits)  G gold(unbreakable)  . empty
local POINTS = { [0] = 7, 5, 3, 1, 2, 4, 6, 8, [8] = 10, [9] = 10, [10] = 0 }
local LEVELS = {
    { name = "CLASSIC", classic = true, rows = {
        "00000000000000", "00000000000000", "11111111111111", "11111111111111",
        "22222222222222", "22222222222222", "33333333333333", "33333333333333" } },
    { name = "PRISM", rows = {
        "SSSSSSSSSSSSSS", "05.14.25.36.47", "5.14.25.36.470", ".14.25.36.4705",
        "14.25.36.4705.", "4.25.36.4705.1", "..............", "77777777777777" } },
    { name = "DIAMOND", rows = {
        "......55......", ".....5445.....", "....5411145...", "...541GG1145..",
        "...541GG1145..", "....5411145...", ".....5445.....", "......55......" } },
    { name = "INVADERS", rows = {
        "...4......4...", "....4....4....", "...SSSSSSSS...", "..SS0SSSS0SS..",
        ".SSSSSSSSSSSS.", ".S.SSSSSSSS.S.", ".S.S......S.S.", "....33..33...." } },
    { name = "FORTRESS", rows = {
        "G666666666666G", "G............G", "G.2222222222.G", "G.2SSSSSSSS2.G",
        "G.2S777777S2.G", "G.2SSSSSSSS2.G", "G.2222222222.G", "GGGGGG..GGGGGG" } },
}
local SLOT = { ["0"] = 0, ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6, ["7"] = 7, S = 8, G = 10 }

------------------------------------------------------------------ particles
local PSCALE = 1.0   -- settings menu particle scale
local function burst(x, y, o)
    pcall(particles.emit_burst, {
        position = vec3(x, y, o.z or 0.8), velocity = o.vel or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = max(1, floor((o.count or 40) * PSCALE)),
        size_min = o.smin or 0.05, size_max = o.smax or 0.16, life_min = o.lmin or 0.25, life_max = o.lmax or 0.7,
        spawn_radius = o.radius or 0.3, noise_strength = o.spread or 14, drag = o.drag or 2.0,
        gravity = o.grav or vec3(0, -9, 0), cleanup_delay = 2.5,
    })
end
local function sparks(x, y, col, n, spread, up)
    burst(x, y, { c0 = vec4(col[1] * 2.2 + 0.6, col[2] * 2.2 + 0.6, col[3] * 2.2 + 0.6, 1), c1 = vec4(col[1], col[2], col[3], 0),
        count = n or 26, smin = 0.04, smax = 0.11, lmin = 0.15, lmax = 0.45, radius = 0.08, spread = spread or 22, drag = 3.0,
        vel = up and vec3(0, up, 0) or nil, grav = vec3(0, -14, 0) })
end

------------------------------------------------------------------ brick shards (pooled cooked-mesh debris)
local SHARDS = {}
local SHARD_PER = 18
local function build_shards()
    for c = 0, 7 do
        SHARDS[c] = { next = 1 }
        for k = 1, SHARD_PER do
            local n = clone("T_shard_" .. c, HIDE, vec3(0.3, 0.3, 0.3))
            n:set_enabled(false)
            SHARDS[c][k] = { node = n, life = 0 }
        end
    end
end
local live_shards = {}
local function shatter(slot, x, y, dirx, diry, n)
    local pool = SHARDS[math.min(slot, 7)]
    if slot == 8 or slot == 9 then pool = SHARDS[7] end
    for k = 1, floor((n or 7) * (0.4 + 0.6 * PSCALE) + 0.5) do
        local s = pool[pool.next]; pool.next = pool.next % SHARD_PER + 1
        local sz = rr(0.28, 0.5)
        s.x, s.y, s.z = x + rr(-0.7, 0.7), y + rr(-0.2, 0.2), rr(0, 0.5)
        s.vx, s.vy, s.vz = rr(-6, 6) + dirx * 5, rr(-1, 7) + diry * 4, rr(2, 9)
        s.rx, s.ry, s.rz = rr(0, TAU), rr(0, TAU), rr(0, TAU)
        s.wx, s.wy, s.wz = rr(-12, 12), rr(-12, 12), rr(-12, 12)
        s.sx, s.sy, s.sz = sz, sz * rr(0.5, 1.1), sz * rr(0.6, 1.2)
        s.life, s.max = rr(0.7, 1.2), 1.2
        s.node:set_enabled(true)
        if not s.live then s.live = true; live_shards[#live_shards + 1] = s end
    end
end
local function update_shards(dt)
    for i = #live_shards, 1, -1 do
        local s = live_shards[i]
        s.life = s.life - dt
        if s.life <= 0 then
            s.live = false; s.node:set_enabled(false); s.node:set_position(HIDE)
            table.remove(live_shards, i)
        else
            s.vy = s.vy - 22 * dt
            s.x, s.y, s.z = s.x + s.vx * dt, s.y + s.vy * dt, s.z + s.vz * dt
            s.rx, s.ry, s.rz = s.rx + s.wx * dt, s.ry + s.wy * dt, s.rz + s.wz * dt
            local k = clamp(s.life / 0.4, 0, 1)
            s.node:set_position(vec3(s.x, s.y, s.z))
            s.node:set_rotation(vec3(s.rx * 57.3, s.ry * 57.3, s.rz * 57.3))
            s.node:set_scale(vec3(s.sx * k, s.sy * k, s.sz * k))
        end
    end
end

------------------------------------------------------------------ bricks
local bricks = {}          -- list of live bricks
G.bricks = bricks
local breakable_left = 0
local function brick_pos(r, c) return -HW + (c - 0.5) * BW, BRICK_TOP - (r - 1) * BH end
local BSX, BSY, BSZ = 1.86, 0.70 / 0.42, 1.4         -- body scale (mesh 1.0 x 0.42 x 0.5)
local FSX, FSY = 1.86 * 0.86, 1.25              -- face plate scale (mesh 0.8 x 0.24 x 0.06)
local function place_brick(b, x, y, s)
    s = s or 1
    b.node:set_position(vec3(x, y, 0)); b.node:set_scale(vec3(BSX * s, BSY * s, BSZ * s))
    b.face:set_position(vec3(x, y, 0.36 * s)); b.face:set_scale(vec3(FSX * s, FSY * s, s))
end
local function clear_bricks()
    for i = #bricks, 1, -1 do
        local b = bricks[i]
        pcall(scene.delete_node, b.node); pcall(scene.delete_node, b.face)
        bricks[i] = nil
    end
    breakable_left = 0
end
local function build_level(li)
    clear_bricks()
    local lv = LEVELS[(li - 1) % #LEVELS + 1]
    for r = 1, ROWS do
        local row = lv.rows[r]
        for c = 1, COLS do
            local slot = SLOT[row:sub(c, c)]
            if slot then
                local x, y = brick_pos(r, c)
                local b = { r = r, c = c, x = x, y = y, slot = slot, hp = (slot == 8) and 2 or 1,
                    gold = slot == 10, pts = POINTS[slot] or 1, pop = 0 }
                b.node = clone("T_brick_" .. slot, HIDE)
                b.face = clone("T_face_" .. slot, HIDE)
                b.delay = (ROWS - r) * 0.05 + abs(c - 7.5) * 0.025
                b.intro = 0
                place_brick(b, x, y + 25, 1)
                bricks[#bricks + 1] = b
                if not b.gold then breakable_left = breakable_left + 1 end
            end
        end
    end
    G.level_name = lv.name
    G.classic = lv.classic == true
end
local function update_bricks(dt)
    for _, b in ipairs(bricks) do
        if b.intro < 1 then
            b.delay = b.delay - dt
            if b.delay <= 0 then
                b.intro = min(1, b.intro + dt * 2.2)
                local t = 1 - b.intro
                local e = 1 - t * t * t                         -- ease out
                local bounce = sin(b.intro * PI) * 0.25 * (1 - b.intro)
                place_brick(b, b.x, b.y + (1 - e) * 22 - bounce, 0.6 + 0.4 * e)
            end
        elseif b.pop > 0 then
            b.pop = max(0, b.pop - dt * 5)
            place_brick(b, b.x, b.y, 1 + 0.18 * b.pop)
        end
    end
end
local function bricks_ready()
    for _, b in ipairs(bricks) do if b.intro < 1 then return false end end
    return true
end

------------------------------------------------------------------ paddle
local PAD = { x = 0, vx = 0, w = 3.6, tw = 3.6, target = 0, squash = 0, tilt = 0, glow = 0 }
G.pad = PAD
local PAD_W, PAD_W_SHRUNK = 3.6, 1.9
local function build_paddle()
    PAD.mid = clone("T_paddle_mid", HIDE)
    PAD.capl = clone("T_paddle_cap", HIDE)
    PAD.capr = clone("T_paddle_cap", HIDE)
    PAD.strip = clone("T_paddle_strip", HIDE)
    paint(tpl("T_paddle_mid").node, { 0.25, 0.3, 0.5 }, { 0.10, 0.22, 0.45 }, 0.12, 0.4)
    paint(tpl("T_paddle_cap").node, { 0.3, 0.9, 1.0 }, { 0.35, 1.3, 1.8 }, 0.2, 0.3)
    paint(tpl("T_paddle_strip").node, { 0.3, 0.9, 1.0 }, { 0.5, 1.8, 2.6 }, 0.2, 0.0)
end
local function draw_paddle()
    local w = PAD.w
    local sq = PAD.squash
    local sy, sx = (1 - 0.35 * sq) * 1.5, 1 + 0.06 * sq
    local y = PADDLE_Y - 0.1 * sq
    local tilt = PAD.tilt
    local hw = w * 0.5 * sx
    local function at(n, dx, dy, dz)
        -- roll the paddle around its centre by `tilt` degrees
        local a = math.rad(tilt)
        n:set_position(vec3(PAD.x + dx * cos(a), y + dx * sin(a) + dy, dz))
        n:set_rotation(vec3(0, 0, tilt))
    end
    at(PAD.mid, 0, 0, 0); PAD.mid:set_scale(vec3(max(0.1, (w - 0.44) * sx), sy, 1))
    at(PAD.capl, -(hw - 0.22), 0, 0); PAD.capl:set_scale(vec3(1, sy, 1))
    at(PAD.capr, hw - 0.22, 0, 0); PAD.capr:set_scale(vec3(1, sy, 1))
    at(PAD.strip, 0, 0, 0.2); PAD.strip:set_scale(vec3(max(0.1, w - 0.7) * sx, 0.3 * sy, 0.55))
    set_point(L.paddle, vec3(PAD.x, PADDLE_Y + 0.6, 2.5), vec3(0.3, 0.85, 1.0), 10 + 30 * PAD.glow, 6 + w)
end

------------------------------------------------------------------ balls
local balls = {}
G.balls = balls
local GHOSTS = 8
local BALL_POOL = {}
local function build_ball_pool()
    paint(tpl("T_ball").node, { 1, 1, 1 }, { 3.0, 3.3, 3.8 }, 0.1, 0.0)
    paint(tpl("T_ghost").node, { 0.4, 0.9, 1 }, { 0.5, 1.4, 2.2 }, 0.3, 0.0)
    for i = 1, 3 do
        local p = { node = clone("T_ball", HIDE, vec3(BALL_R * 2, BALL_R * 2, BALL_R * 2)), ghosts = {}, light = L.balls[i] }
        for k = 1, GHOSTS do p.ghosts[k] = clone("T_ghost", HIDE, vec3(0.1, 0.1, 0.1)) end
        p.em = particles.add_emitter({ position = HIDE, velocity = vec3(0, 0, 0), gravity = vec3(0, 0, 0),
            color_start = vec4(0.6, 1.4, 2.0, 1), color_end = vec4(0.6, 0.2, 1.6, 0), count = 260, spawn_rate = 0,
            spawn_radius = 0.12, size_min = 0.05, size_max = 0.14, life_min = 0.15, life_max = 0.4, noise_strength = 1.5, drag = 2.0 })
        p.used = false
        BALL_POOL[i] = p
    end
end
local function spawn_ball(x, y, vx, vy, stuck)
    for _, p in ipairs(BALL_POOL) do
        if not p.used then
            p.used = true
            local b = { p = p, x = x, y = y, vx = vx or 0, vy = vy or 1, stuck = stuck, off = 0, hist = {}, alive = true }
            balls[#balls + 1] = b
            return b
        end
    end
end
local function free_ball(i)
    local b = balls[i]
    local p = b.p
    p.used = false
    p.node:set_position(HIDE)
    for k = 1, GHOSTS do p.ghosts[k]:set_position(HIDE) end
    pcall(particles.set_emitter, p.em, "spawn_rate", 0.0)
    pcall(particles.set_emitter, p.em, "position", HIDE)
    set_point(p.light, HIDE, vec3(1, 1, 1), 0, 1)
    table.remove(balls, i)
end

------------------------------------------------------------------ game state
local SHAKE_SCALE = 1.0
G.score, G.hiscore, G.lives, G.level = 0, 0, 3, 1
G.hits, G.tier, G.hit_orange, G.hit_red, G.shrunk = 0, 0, false, false, false
G.pow = { wide = 0, slow = 0, laser = 0, fire = 0 }
local HISAVE = "Save/breakout_hiscore.txt"
pcall(function() local s = fs.read(HISAVE); if s then G.hiscore = tonumber(s) or 0 end end)
local shake = 0
local function add_shake(a) shake = min(1.0, shake + a) end
local score_pop = 0
local banner = { text = "", sub = "", t = 0, dur = 0 }
local function show_banner(t, sub, dur) banner.text, banner.sub, banner.t, banner.dur = t, sub or "", 0, dur or 2.0 end
local function add_score(p)
    G.score = G.score + p; score_pop = 1
    if G.score > G.hiscore then G.hiscore = G.score end
end
-- speed: Breakout's four speed-ups + a per-wall increase
local BASE_SPEED = 15.0
local TIER_MULT = { [0] = 1.0, 1.14, 1.28, 1.44, 1.6 }
local TIER_COL = { [0] = { 0.6, 1.5, 2.6 }, { 1.2, 1.8, 2.4 }, { 2.4, 2.2, 0.8 }, { 2.8, 1.3, 0.4 }, { 3.0, 0.6, 0.4 } }
local function ball_speed()
    local s = BASE_SPEED * TIER_MULT[G.tier] * (1 + 0.06 * (G.level - 1))
    if G.pow.slow > 0 then s = s * 0.68 end
    return s
end
local function ball_colour()
    if G.pow.fire > 0 then return { 3.0, 1.1, 0.25 } end
    return TIER_COL[G.tier]
end
local function speed_up(why)
    if G.tier < 4 then
        G.tier = G.tier + 1; sfx("speedup")
        show_banner("SPEED UP", why, 1.0)
        local c = ball_colour(); mlive(tpl("T_ball").node, "emissive", vec3(c[1] * 1.3, c[2] * 1.3, c[3] * 1.3))
        mlive(tpl("T_ghost").node, "emissive", vec3(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6))
    end
end
local function refresh_ball_colour()
    local c = ball_colour()
    mlive(tpl("T_ball").node, "emissive", vec3(c[1] * 1.3, c[2] * 1.3, c[3] * 1.3))
    mlive(tpl("T_ghost").node, "emissive", vec3(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6))
end

------------------------------------------------------------------ power-ups (NEON stages only)
local PU = {
    { key = "wide", name = "WIDE", col = { 0.2, 0.9, 1.0 }, dur = 15 },
    { key = "multi", name = "MULTI", col = { 1.0, 0.25, 0.9 } },
    { key = "slow", name = "SLOW", col = { 0.25, 1.0, 0.4 }, dur = 12 },
    { key = "laser", name = "LASER", col = { 1.0, 0.15, 0.2 }, dur = 12 },
    { key = "fire", name = "FIRE", col = { 1.0, 0.55, 0.1 }, dur = 8 },
    { key = "life", name = "+1 BALL", col = { 1.0, 1.0, 1.0 } },
}
local caps = {}
local CAP_POOL = {}
local function build_caps()
    for i, d in ipairs(PU) do
        local t = tpl("T_pu_" .. (i - 1))
        local c = d.col
        paint(t.node, c, { c[1] * 1.6, c[2] * 1.6, c[3] * 1.6 }, 0.15, 0.2)
        CAP_POOL[i] = {}
        for k = 1, 3 do
            local n = clone("T_pu_" .. (i - 1), HIDE, vec3(2.2, 1.4, 1.2))
            CAP_POOL[i][k] = { node = n, used = false }
        end
    end
end
local function drop_cap(x, y)
    local r = rand()
    local kind = r < 0.22 and 1 or r < 0.40 and 2 or r < 0.58 and 3 or r < 0.76 and 4 or r < 0.93 and 5 or 6
    for _, slot in ipairs(CAP_POOL[kind]) do
        if not slot.used then
            slot.used = true
            caps[#caps + 1] = { slot = slot, kind = kind, x = x, y = y, t = 0 }
            return
        end
    end
end
local function free_cap(i)
    local c = caps[i]; c.slot.used = false; c.slot.node:set_position(HIDE); table.remove(caps, i)
end
local function apply_power(kind)
    local d = PU[kind]
    sfx("powerup"); flash(PAD.x, PADDLE_Y + 1, d.col, 60, 0.5, 10)
    sparks(PAD.x, PADDLE_Y + 0.5, d.col, 50, 18, 6)
    show_banner(d.name, "", 1.0)
    add_score(50)
    if d.key == "multi" then
        local src = balls[1]
        if src then
            for _, a in ipairs({ -0.5, 0.5 }) do
                local sp = ball_speed()
                local ang = math.atan2(src.vx, src.vy) + a
                if src.stuck then ang = a end
                spawn_ball(src.x, src.y, sp * sin(ang), sp * abs(cos(ang)), false)
            end
            if src.stuck then src.stuck = false; src.vx, src.vy = 0, ball_speed() end
        end
    elseif d.key == "life" then
        G.lives = min(G.lives + 1, 9)
    else
        G.pow[d.key] = d.dur
        if d.key == "fire" then refresh_ball_colour() end
    end
end
local function update_caps(dt)
    for i = #caps, 1, -1 do
        local c = caps[i]
        c.t = c.t + dt; c.y = c.y - 6.5 * dt
        c.slot.node:set_position(vec3(c.x, c.y, 0.4))
        c.slot.node:set_rotation(vec3(c.t * 240, 0, 0))
        if c.y < PADDLE_Y + 0.9 and c.y > PADDLE_Y - 0.8 and abs(c.x - PAD.x) < PAD.w * 0.5 + 0.6 then
            apply_power(c.kind); free_cap(i)
        elseif c.y < BOTTOM then free_cap(i) end
    end
end

------------------------------------------------------------------ lasers
local bolts = {}
local BOLT_POOL = {}
local laser_cd = 0
local function build_bolts()
    for i = 1, 10 do
        local n = prim("cube", HIDE, vec3(0.12, 0.7, 0.12))
        paint(n, { 1, 0.2, 0.3 }, { 3.0, 0.4, 0.6 }, 0.3, 0)
        BOLT_POOL[i] = { node = n, used = false }
    end
end
local function fire_lasers()
    local n = 0
    for _, s in ipairs(BOLT_POOL) do
        if not s.used and n < 2 then
            n = n + 1; s.used = true
            local x = PAD.x + (n == 1 and -1 or 1) * (PAD.w * 0.5 - 0.3)
            bolts[#bolts + 1] = { s = s, x = x, y = PADDLE_Y + 0.6 }
        end
    end
    if n > 0 then sfx("laser"); flash(PAD.x, PADDLE_Y + 1, { 1, 0.2, 0.3 }, 20, 0.15, 6) end
end

------------------------------------------------------------------ hits / scoring
local function level_cleared() return breakable_left <= 0 end
local function hit_brick(b, dirx, diry, by_laser)
    if b.dead then return end
    local c = PAL[b.slot]
    if b.gold then
        sfx("steel"); sparks(b.x + dirx * 0.9, b.y + diry * 0.35, { 1, 0.8, 0.3 }, 18, 14)
        b.pop = 1; flash(b.x, b.y, { 1, 0.7, 0.3 }, 14, 0.2, 5)
        return
    end
    b.hp = b.hp - 1
    if b.hp > 0 then
        -- steel brick cracks: swap to the damaged mesh/material
        swap_mesh(b.node, "T_brick_8", "T_brick_9"); swap_mesh(b.face, "T_face_8", "T_face_9")
        b.slot = 9; b.pop = 1
        sfx("steel"); sparks(b.x, b.y, { 0.8, 0.85, 1.0 }, 30, 18)
        flash(b.x, b.y, { 0.7, 0.8, 1.0 }, 20, 0.25, 6)
        add_shake(0.12)
        return
    end
    b.dead = true
    breakable_left = breakable_left - 1
    add_score(b.pts)
    -- classic Breakout speed-ups
    G.hits = G.hits + 1
    if not by_laser then
        if G.hits == 4 then speed_up("4 HITS")
        elseif G.hits == 12 then speed_up("12 HITS") end
        if b.slot == 1 and not G.hit_orange then G.hit_orange = true; speed_up("ORANGE ROW") end
        if b.slot == 0 and not G.hit_red then G.hit_red = true; speed_up("RED ROW") end
    end
    sfx("brick" .. clamp(ROWS - b.r, 0, 7))
    if b.slot <= 9 then pcall(audio.play, "shatter.wav") end
    shatter(b.slot, b.x, b.y, dirx, diry, 7)
    sparks(b.x, b.y, c, 34, 20)
    burst(b.x, b.y, { c0 = vec4(c[1] * 2, c[2] * 2, c[3] * 2, 0.9), c1 = vec4(c[1], c[2], c[3], 0), count = 30, smin = 0.12, smax = 0.3,
        lmin = 0.2, lmax = 0.5, radius = 0.6, spread = 6, drag = 4, grav = vec3(0, 0, 0) })
    flash(b.x, b.y, c, 45, 0.35, 8)
    add_shake(0.16)
    PAD.glow = max(PAD.glow, 0.0)
    pcall(scene.delete_node, b.node); pcall(scene.delete_node, b.face)
    for i, bb in ipairs(bricks) do if bb == b then table.remove(bricks, i) break end end
    if not G.classic and rand() < 0.15 then drop_cap(b.x, b.y) end
end
local function update_bolts(dt)
    for i = #bolts, 1, -1 do
        local o = bolts[i]
        o.y = o.y + 34 * dt
        o.s.node:set_position(vec3(o.x, o.y, 0.3))
        local hit = nil
        for _, b in ipairs(bricks) do
            if b.intro >= 1 and abs(o.x - b.x) < BW * 0.5 and abs(o.y - b.y) < BH * 0.5 + 0.3 then hit = b break end
        end
        if hit or o.y > TOP then
            if hit then hit_brick(hit, 0, 1, true) else sparks(o.x, TOP - 0.2, { 1, 0.2, 0.3 }, 8, 10, -2) end
            o.s.used = false; o.s.node:set_position(HIDE); table.remove(bolts, i)
        end
    end
end

------------------------------------------------------------------ ball physics
local HBX, HBY = BSX * 0.5, 0.70 * 0.5      -- brick half extents for collision
local function set_dir(b, vx, vy)
    local sp = ball_speed()
    local l = sqrt(vx * vx + vy * vy); if l < 1e-6 then vx, vy, l = 0, 1, 1 end
    vx, vy = vx / l, vy / l
    -- never let the ball go (nearly) horizontal
    if abs(vy) < 0.28 then vy = (vy < 0 and -0.28 or 0.28); local s = sqrt(1 - vy * vy); vx = (vx < 0 and -s or s) end
    b.vx, b.vy = vx * sp, vy * sp
end
local function launch(b)
    if not b.stuck then return end
    b.stuck = false
    local a = clamp(b.off / (PAD.w * 0.5), -1, 1) * 0.5 + clamp(PAD.vx * 0.01, -0.25, 0.25)
    set_dir(b, sin(a), cos(a))
    sfx("launch"); sparks(b.x, b.y, ball_colour(), 20, 10, 4)
end
local function ball_step(b, dt)
    local x, y = b.x + b.vx * dt, b.y + b.vy * dt
    local col = ball_colour()
    -- walls
    if x < -HW + BALL_R then x = -HW + BALL_R; b.vx = abs(b.vx); sfx("wall"); sparks(-HW, y, { 0.3, 0.9, 1 }, 10, 12); G.rail_hit = 1 end
    if x > HW - BALL_R then x = HW - BALL_R; b.vx = -abs(b.vx); sfx("wall"); sparks(HW, y, { 0.3, 0.9, 1 }, 10, 12); G.rail_hit = 1 end
    if y > TOP - BALL_R then
        y = TOP - BALL_R; b.vy = -abs(b.vy); sfx("wall"); sparks(x, TOP, { 0.3, 0.9, 1 }, 12, 12, -3); G.rail_hit = 1
        -- classic rule: the paddle shrinks to half once the ball breaks through to the top wall
        if not G.shrunk then G.shrunk = true; sfx("shrink"); show_banner("BREAKTHROUGH!", "PADDLE HALVED", 1.4); add_shake(0.25) end
    end
    -- paddle
    local hw = PAD.w * 0.5
    if b.vy < 0 and y - BALL_R <= PADDLE_Y + PADDLE_H * 0.5 and y > PADDLE_Y - PADDLE_H and abs(x - PAD.x) <= hw + BALL_R * 0.8 then
        local off = clamp((x - PAD.x) / hw, -1, 1)
        local a = off * math.rad(62) + clamp(PAD.vx * 0.006, -0.18, 0.18)
        set_dir(b, sin(a), cos(a))
        y = PADDLE_Y + PADDLE_H * 0.5 + BALL_R
        PAD.squash = 1; PAD.glow = 1
        sfx("paddle"); sparks(x, PADDLE_Y + 0.3, { 0.3, 0.9, 1.0 }, 22, 16, 4)
        flash(x, PADDLE_Y + 0.5, { 0.3, 0.9, 1.0 }, 25, 0.25, 6)
        add_shake(0.06)
        if PAD.sticky then b.stuck = true; b.off = x - PAD.x end
        if level_cleared() then return x, y end
    end
    -- bricks (one contact per sub-step)
    for _, br in ipairs(bricks) do
        if br.intro >= 1 then
            local dx, dy = x - br.x, y - br.y
            if abs(dx) < HBX + BALL_R and abs(dy) < HBY + BALL_R then
                local cx, cy = clamp(dx, -HBX, HBX), clamp(dy, -HBY, HBY)
                local ex, ey = dx - cx, dy - cy
                if ex * ex + ey * ey <= BALL_R * BALL_R then
                    local pierce = G.pow.fire > 0 and not br.gold
                    local nx, ny = 0, 0
                    if not pierce then
                        local px = HBX + BALL_R - abs(dx)  -- penetration depths
                        local py = HBY + BALL_R - abs(dy)
                        if px < py then nx = dx < 0 and -1 or 1; b.vx = nx * abs(b.vx); x = br.x + nx * (HBX + BALL_R)
                        else ny = dy < 0 and -1 or 1; b.vy = ny * abs(b.vy); y = br.y + ny * (HBY + BALL_R) end
                    end
                    hit_brick(br, -nx + b.vx * 0.02, -ny + b.vy * 0.02)
                    break
                end
            end
        end
    end
    return x, y
end
local function update_balls(dt)
    local sp = ball_speed()
    for i = #balls, 1, -1 do
        local b = balls[i]
        if b.stuck then
            b.x = PAD.x + b.off; b.y = PADDLE_Y + PADDLE_H * 0.5 + BALL_R + 0.02
        else
            -- keep speed in sync with tier/slow changes
            local l = sqrt(b.vx * b.vx + b.vy * b.vy)
            if l > 0 then b.vx, b.vy = b.vx / l * sp, b.vy / l * sp end
            local steps = max(1, math.ceil(sp * dt / (BALL_R * 0.5)))
            local h = dt / steps
            for _ = 1, steps do b.x, b.y = ball_step(b, h) end
        end
        if b.y < BOTTOM then
            sparks(b.x, BOTTOM + 1, { 1, 0.3, 0.3 }, 40, 20, 8); flash(b.x, BOTTOM + 2, { 1, 0.2, 0.2 }, 40, 0.5, 10)
            free_ball(i)
        end
    end
end
local function draw_balls(dt)
    local col = ball_colour()
    for _, b in ipairs(balls) do
        local p = b.p
        local pulse = 1 + 0.06 * sin(G.t * 20)
        p.node:set_position(vec3(b.x, b.y, 0.2))
        p.node:set_scale(vec3(BALL_R * 2.3 * pulse, BALL_R * 2.3 * pulse, BALL_R * 2.3 * pulse))
        -- trail samples are spaced by distance (frame-rate independent)
        local h0 = b.hist[1]
        if not h0 or (b.x - h0[1]) ^ 2 + (b.y - h0[2]) ^ 2 > 0.09 then
            table.insert(b.hist, 1, { b.x, b.y })
            if #b.hist > GHOSTS * 2 + 2 then b.hist[#b.hist] = nil end
        end
        for k = 1, GHOSTS do
            local h = b.hist[k * 2]
            local s = BALL_R * 2 * (1 - k / (GHOSTS + 1)) * 0.95
            if b.stuck or not h then p.ghosts[k]:set_position(HIDE)
            else p.ghosts[k]:set_position(vec3(h[1], h[2], 0.15)); p.ghosts[k]:set_scale(vec3(s, s, s)) end
        end
        pcall(particles.set_emitter, p.em, "position", vec3(b.x, b.y, 0.2))
        pcall(particles.set_emitter, p.em, "spawn_rate", b.stuck and 0.0 or 90.0 * PSCALE)
        set_point(p.light, vec3(b.x, b.y, 1.6), vec3(col[1] / 3, col[2] / 3, col[3] / 3), G.pow.fire > 0 and 90 or 55, 8.5)
    end
end

------------------------------------------------------------------ HUD / menus
local HUD = "hud"
runtime_ui.show(HUD); runtime_ui.set_screen_overlay(HUD, true)
local NONE = { 0, 0, 0, 0 }
local CYAN, MAG, WHITE, GOLD = { 0.5, 0.95, 1.0, 1 }, { 1.0, 0.45, 0.9, 1 }, { 1, 1, 1, 1 }, { 1, 0.85, 0.4, 1 }
local cache = {}
local function upd(id, key, q)
    if cache[id] == key then return end
    cache[id] = key
    runtime_ui.set_quad(HUD, id, q)
end
local function text(id, label, x, y, w, h, fs, col, align, vis)
    vis = vis ~= false
    local key = label .. "|" .. floor(x) .. "|" .. floor(y) .. "|" .. tostring(vis) .. "|" .. string.format("%.2f|%.2f", col[4], fs) .. col[1] .. col[2]
    upd(id, key, { x = x, y = y, w = w, h = h, z = 10, style = "text", label = label, fill = NONE, border = NONE,
        text_color = col, font_scale = fs, align_h = align or "center", align_v = "middle", no_input = true, visible = vis })
end
local function panel(id, x, y, w, h, vis, fill, border, z, input)
    vis = vis ~= false
    local key = floor(x) .. "|" .. floor(y) .. "|" .. floor(w) .. "|" .. floor(h) .. "|" .. tostring(vis) .. "|" .. table.concat(fill, ",") .. table.concat(border or NONE, ",")
    upd(id, key, { x = x, y = y, w = w, h = h, z = z or 5, style = "text", label = "", fill = fill, border = border or NONE,
        corner_radius = 14, no_input = not input, visible = vis })
end
local function ui_state(id) local ok, s = pcall(runtime_ui.get_state, HUD, id); if ok then return s end end

-- menu definition
local MENU = { items = {}, sel = 1, id = "" }
local function set_menu(id, items) MENU.id, MENU.items, MENU.sel = id, items, 1 end
local function draw_menu(vis, y0)
    local s = SH / 1080
    for i = 1, 4 do
        local it = MENU.items[i]
        local v = vis and it ~= nil
        local sel = v and MENU.sel == i
        local x, w, h = SW / 2 - 230 * s, 460 * s, 66 * s
        local y = y0 + (i - 1) * 80 * s
        panel("mi_bg" .. i, x, y, w, h, v, sel and { 0.15, 0.6, 0.9, 0.35 } or { 0.03, 0.03, 0.1, 0.55 },
            sel and { 0.4, 0.95, 1.0, 0.95 } or { 0.5, 0.3, 0.9, 0.5 }, 20, true)
        text("mi_tx" .. i, v and it.label or "", x, y, w, h, (sel and 1.7 or 1.5) * s, sel and WHITE or { 0.75, 0.8, 1.0, 1 }, "center", v)
    end
end
local function menu_input(pressed)
    if #MENU.items == 0 then return nil end
    for i = 1, #MENU.items do
        local st = ui_state("mi_bg" .. i)
        if st and st.hovered and (G.mouse_moved or false) then MENU.sel = i end
        if st and st.clicked then MENU.sel = i; return MENU.items[i].act end
    end
    if pressed("Up") or pressed("W") then MENU.sel = (MENU.sel - 2) % #MENU.items + 1; sfx("click") end
    if pressed("Down") or pressed("S") then MENU.sel = MENU.sel % #MENU.items + 1; sfx("click") end
    if pressed("Return") or pressed("Space") then return MENU.items[MENU.sel].act end
end

local function draw_hud(dt)
    local s = SH / 1080
    local st = G.state
    local play = (st == "play" or st == "serve" or st == "paused" or st == "clear" or st == "over" or st == "levelintro")
    local title = st == "title"
    -- side panels
    local pw, px = SW * 0.19, SW * 0.025
    panel("lp", px, SH * 0.12, pw, SH * 0.5, play, { 0.02, 0.02, 0.07, 0.55 }, { 0.3, 0.8, 1.0, 0.45 })
    panel("rp", SW - px - pw, SH * 0.12, pw, SH * 0.5, play, { 0.02, 0.02, 0.07, 0.55 }, { 1.0, 0.35, 0.85, 0.45 })
    local lx, rx = px + 24 * s, SW - px - pw + 24 * s
    local iw = pw - 48 * s
    text("l_score_t", "SCORE", lx, SH * 0.14, iw, 40 * s, 1.0 * s, { 0.5, 0.8, 1, 0.8 }, "left", play)
    text("l_score", string.format("%05d", G.score), lx, SH * 0.14 + 40 * s, iw, 70 * s, (2.4 + 0.5 * score_pop) * s, CYAN, "left", play)
    text("l_hi_t", "HIGH SCORE", lx, SH * 0.14 + 125 * s, iw, 40 * s, 1.0 * s, { 0.5, 0.8, 1, 0.8 }, "left", play)
    text("l_hi", string.format("%05d", G.hiscore), lx, SH * 0.14 + 160 * s, iw, 60 * s, 1.7 * s, GOLD, "left", play)
    text("l_lv_t", "WALL", lx, SH * 0.14 + 240 * s, iw, 40 * s, 1.0 * s, { 0.5, 0.8, 1, 0.8 }, "left", play)
    text("l_lv", G.level .. "  " .. (G.level_name or ""), lx, SH * 0.14 + 275 * s, iw, 60 * s, 1.6 * s, MAG, "left", play)
    text("l_mode", G.classic and "CLASSIC RULES" or "NEON STAGE  ·  POWER-UPS", lx, SH * 0.14 + 330 * s, iw, 40 * s, 0.9 * s, { 0.8, 0.8, 1, 0.7 }, "left", play)
    text("r_balls_t", "BALLS", rx, SH * 0.14, iw, 40 * s, 1.0 * s, { 1, 0.6, 0.9, 0.8 }, "left", play)
    text("r_balls", string.rep("O ", G.lives), rx, SH * 0.14 + 40 * s, iw, 70 * s, 2.0 * s, WHITE, "left", play)
    text("r_spd_t", "BALL SPEED", rx, SH * 0.14 + 125 * s, iw, 40 * s, 1.0 * s, { 1, 0.6, 0.9, 0.8 }, "left", play)
    local bar = string.rep("|", (G.tier + 1) * 3) .. string.rep(".", (4 - G.tier) * 3)
    local tc = TIER_COL[G.tier]
    text("r_spd", bar, rx, SH * 0.14 + 160 * s, iw, 60 * s, 1.7 * s, { min(1, tc[1] / 2.6), min(1, tc[2] / 2.6), min(1, tc[3] / 2.6), 1 }, "left", play)
    local pl = {}
    for _, d in ipairs(PU) do
        if d.dur and G.pow[d.key] > 0 then pl[#pl + 1] = string.format("%s %d", d.name, math.ceil(G.pow[d.key])) end
    end
    if G.shrunk then pl[#pl + 1] = "PADDLE HALVED" end
    text("r_pow_t", "ACTIVE", rx, SH * 0.14 + 240 * s, iw, 40 * s, 1.0 * s, { 1, 0.6, 0.9, 0.8 }, "left", play)
    text("r_pow", #pl > 0 and table.concat(pl, "\n") or "-", rx, SH * 0.14 + 280 * s, iw, 120 * s, 1.15 * s, { 1, 0.9, 0.6, 1 }, "left", play)
    -- banner
    local bvis = banner.t < banner.dur and play
    local ba = bvis and min(1, banner.t * 6, (banner.dur - banner.t) * 3) or 0
    local bs = 1 + 0.25 * max(0, 1 - banner.t * 5)
    text("banner", banner.text, 0, SH * 0.47, SW, 110 * s, 3.4 * s * bs, { 1, 0.85, 0.45, ba }, "center", bvis)
    text("banner2", banner.sub, 0, SH * 0.47 + 95 * s, SW, 50 * s, 1.3 * s, { 0.7, 0.95, 1, ba }, "center", bvis and banner.sub ~= "")
    local serve = st == "serve"
    text("hint", "CLICK  /  SPACE  TO LAUNCH", 0, SH * 0.80, SW, 60 * s, 1.4 * s, { 1, 1, 1, 0.55 + 0.45 * sin(G.t * 5) }, "center", serve)
    -- title
    panel("tpanel", SW * 0.5 - 520 * s, SH * 0.07, 1040 * s, SH * 0.81, title, { 0.01, 0.0, 0.05, 0.62 }, { 0.6, 0.3, 1.0, 0.5 }, 3)
    text("title", "N E O N", 0, SH * 0.10, SW, 120 * s, 3.2 * s, MAG, "center", title)
    text("title2", "BREAKOUT", 0, SH * 0.17, SW, 200 * s, 7.0 * s, { 0.55 + 0.1 * sin(G.t * 2), 1.0, 1.0, 1 }, "center", title)
    text("tsub", "HIGH SCORE  " .. G.hiscore, 0, SH * 0.36, SW, 60 * s, 1.4 * s, GOLD, "center", title)
    text("ctl", "MOUSE  or  ARROWS / A D  MOVE      CLICK / SPACE  LAUNCH · FIRE      P / ESC  PAUSE      M  MUTE",
        0, SH * 0.90, SW, 50 * s, 1.0 * s, { 0.7, 0.85, 1, 0.85 }, "center", title)
    text("ctl2", "RED 7 · ORANGE 5 · GREEN 3 · YELLOW 1      WALL 2+ : NEON STAGES WITH STEEL & GOLD BRICKS AND POWER-UPS",
        0, SH * 0.94, SW, 50 * s, 0.85 * s, { 1, 0.75, 0.45, 0.8 }, "center", title)
    -- pause / game over
    local pause = st == "paused"
    panel("dim", 0, 0, SW, SH, pause or st == "over", { 0, 0, 0.02, 0.5 }, NONE, 2)
    text("pause", "PAUSED", 0, SH * 0.25, SW, 140 * s, 4.5 * s, CYAN, "center", pause)
    local over = st == "over"
    text("over", "GAME  OVER", 0, SH * 0.22, SW, 150 * s, 5.0 * s, { 1, 0.35, 0.6, 1 }, "center", over)
    text("over2", (G.newhi and "NEW HIGH SCORE  " or "FINAL SCORE  ") .. G.score, 0, SH * 0.36, SW, 80 * s, 2.0 * s, GOLD, "center", over)
    draw_menu(title or pause or over, title and SH * 0.50 or SH * 0.50)
end

------------------------------------------------------------------ settings menu (shared module)
local SET = nil
do
    local src = fs.read("Scripts/Lib/settings_menu.lua")
    if src then
        local ok, mod = pcall(function() return load(src, "@settings_menu.lua")() end)
        if ok and mod then
            local ok2, s = pcall(mod.new, { title = "SETTINGS", file = "Save/settings.cfg", click = function() sfx("click") end,
                music = false, defaults = { master = 0.5 }, theme = { accent = { 0.3, 0.9, 1, 1 }, accent2 = { 1, 0.35, 0.85, 1 } } })
            if ok2 then SET = s else pe_log("[Breakout] settings menu init failed: " .. tostring(s)) end
        else pe_log("[Breakout] settings menu load failed: " .. tostring(mod)) end
    end
end

------------------------------------------------------------------ input
local prev = {}
G.vkeys = {}
local function kdown(k) if G.vkeys[k] then return true end local ok, r = pcall(input.is_key_down_raw, k); return ok and r end
local function pressed(k)
    local d = kdown(k); local p = prev[k]; prev[k] = d
    return d and not p
end
local WATCH = { "Left", "Right", "A", "D", "Up", "Down", "W", "S", "Space", "Return", "Escape", "P", "M" }
local function latch() for _, k in ipairs(WATCH) do prev[k] = kdown(k) end end
local mouse_prev_down, mouse_last = false, nil
local function mouse_clicked()
    local ok, d = pcall(input.is_left_mouse_down); d = ok and d
    if G.vkeys.Click then d = true end
    local c = d and not mouse_prev_down; mouse_prev_down = d
    return c
end
local function mouse_down() local ok, d = pcall(input.is_left_mouse_down); return (ok and d) or G.vkeys.Click end
-- screen-space mouse x -> world x on the paddle line (perspective-correct for the tilted camera)
local function mouse_world_x(mx)
    local C = cam:get_position()
    local fx, fy, fz = CAM_LOOK.x - C.x, CAM_LOOK.y - C.y, CAM_LOOK.z - C.z
    local fl = sqrt(fx * fx + fy * fy + fz * fz)
    local depth = ((0 - C.x) * fx + (PADDLE_Y - C.y) * fy + (0 - C.z) * fz) / fl
    local ndc = (mx / SW) * 2 - 1
    return C.x + ndc * depth * math.tan(FOVX * 0.5)
end

------------------------------------------------------------------ game flow
local function clear_actors()
    for i = #balls, 1, -1 do free_ball(i) end
    for i = #caps, 1, -1 do free_cap(i) end
    for _, o in ipairs(bolts) do o.s.used = false; o.s.node:set_position(HIDE) end
    for i = #bolts, 1, -1 do bolts[i] = nil end
end
local function serve()
    clear_actors()
    PAD.tw = G.shrunk and PAD_W_SHRUNK or PAD_W
    local b = spawn_ball(PAD.x, PADDLE_Y + 1, 0, 1, true); b.off = rr(-0.5, 0.5)
    G.state = "serve"; G.serve_t = 0
end
local function reset_wall()
    clear_actors()
    build_level(G.level)
    G.hits, G.tier, G.hit_orange, G.hit_red, G.shrunk = 0, 0, false, false, false
    for k in pairs(G.pow) do G.pow[k] = 0 end
    refresh_ball_colour()
    PAD.tw = PAD_W
    G.state = "levelintro"; G.intro_t = 0
    show_banner("WALL " .. G.level, G.level_name .. (G.classic and "  ·  CLASSIC" or "  ·  NEON STAGE"), 2.0)
end
local function new_game(demo)
    G.score, G.lives, G.level, G.newhi = 0, 3, 1, false
    G.demo = demo or false
    reset_wall()
end
local function to_title()
    G.state = "title"
    set_menu("title", { { label = "PLAY", act = "play" }, { label = "SETTINGS", act = "settings" }, { label = "QUIT", act = "quit" } })
    G.demo = true
    G.score, G.lives, G.level = 0, 3, 1
    reset_wall(); G.state = "title"
end
local function lose_ball()
    G.lives = G.lives - 1
    add_shake(0.6); sfx("lose")
    if G.lives <= 0 then
        sfx("gameover")
        G.state = "over"
        G.newhi = G.score > 0 and G.score >= G.hiscore
        pcall(fs.write, HISAVE, tostring(G.hiscore))
        set_menu("over", { { label = "PLAY AGAIN", act = "play" }, { label = "TITLE", act = "title" } })
    else
        G.shrunk = false
        G.tier = max(0, G.tier - 1)   -- a lost ball eases the speed by one step
        refresh_ball_colour()
        show_banner("BALL LOST", G.lives .. " LEFT", 1.4)
        serve()
    end
end
local function celebrate()
    for k = 1, 10 do
        local x, y = rr(-HW + 2, HW - 2), rr(-4, 12)
        local c = PAL[floor(rr(0, 7.99))]
        sparks(x, y, c, 50, 26, 3)
    end
    flash(0, 4, { 1, 0.8, 1 }, 90, 1.2, 25)
end

------------------------------------------------------------------ autopilot (title attract mode + automation)
local function autopilot_target()
    local best = nil
    for _, b in ipairs(balls) do if not best or (b.vy < 0 and b.y < best.y) then best = b end end
    if not best then return PAD.x end
    local tx = best.x
    if best.vy < 0 and not best.stuck then
        -- predict where the ball crosses the paddle line (with wall reflections)
        local t = (best.y - (PADDLE_Y + 0.5)) / -best.vy
        local x = best.x + best.vx * t
        local w = 2 * (HW - BALL_R)
        x = (x + HW - BALL_R) % (2 * w); if x > w then x = 2 * w - x end
        tx = x - HW + BALL_R
    end
    -- aim: hit slightly off-centre toward the side with most bricks
    local side = 0
    for _, b in ipairs(bricks) do side = side + (b.x > 0 and 1 or -1) end
    return tx - clamp(side, -1, 1) * PAD.w * 0.22 + sin(G.t * 1.3) * 0.3
end

------------------------------------------------------------------ main update
local function update_paddle(dt, control)
    PAD.w = lerp(PAD.w, PAD.tw * (G.pow.wide > 0 and 1.6 or 1.0), 1 - math.exp(-dt * 10))
    local lim = HW - PAD.w * 0.5
    if control == "auto" then
        PAD.target = autopilot_target()
    elseif control == "player" then
        local ok, mp = pcall(input.get_mouse_position)
        if ok and mp and mp.x then
            if mouse_last and (abs(mp.x - mouse_last.x) + abs(mp.y - mouse_last.y)) > 0.5 then G.use_mouse = true end
            mouse_last = { x = mp.x, y = mp.y }
            if G.use_mouse then PAD.target = mouse_world_x(mp.x) end
        end
        local kx = (kdown("Right") or kdown("D")) and 1 or 0
        kx = kx - ((kdown("Left") or kdown("A")) and 1 or 0)
        if kx ~= 0 then
            G.use_mouse = false
            PAD.kv = clamp((PAD.kv or 0) + kx * dt * 140, -30, 30)
            PAD.target = PAD.x + PAD.kv * 0.06
        else PAD.kv = 0 end
    end
    PAD.target = clamp(PAD.target, -lim, lim)
    local nx = clamp(lerp(PAD.x, PAD.target, 1 - math.exp(-dt * 28)), -lim, lim)
    PAD.vx = lerp(PAD.vx, (nx - PAD.x) / max(dt, 1e-4), 0.5)
    PAD.x = nx
    PAD.tilt = lerp(PAD.tilt, clamp(-PAD.vx * 0.12, -6, 6), 1 - math.exp(-dt * 12))
    PAD.squash = max(0, PAD.squash - dt * 6)
    PAD.glow = max(0, PAD.glow - dt * 3)
end
local function update_visuals(dt)
    update_flashes(dt); update_shards(dt); update_bricks(dt)
    -- neon frame pulse: hue drifts, flares on hits
    G.rail_hit = max(0, (G.rail_hit or 0) - dt * 4)
    local h = G.t * 0.25
    local r, g, b = 0.5 + 0.5 * sin(h), 0.5 + 0.5 * sin(h + 2.1), 0.5 + 0.5 * sin(h + 4.2)
    local k = 1.4 + 2.5 * G.rail_hit
    mlive(G.rail_glow, "emissive", vec3((0.2 + r) * k, (0.2 + g) * k, (0.4 + b) * k))
    -- brick glow breathing
    G.breath = (G.breath or 0) + dt
    -- key lights slowly swing for moving reflections on the glossy bricks
    set_point(L.key_l, vec3(-HW - 4 + sin(G.t * 0.5) * 4, 22 + cos(G.t * 0.4) * 4, 16), vec3(0.3, 0.75, 1.0), 90, 70)
    set_point(L.key_r, vec3(HW + 4 + cos(G.t * 0.45) * 4, 22 + sin(G.t * 0.35) * 4, 16), vec3(1.0, 0.3, 0.8), 90, 70)
    -- camera: gentle drift + trauma shake
    shake = max(0, shake - dt * 2.5)
    local sk = shake * shake * SHAKE_SCALE
    local ox = (sin(G.t * 47) + sin(G.t * 31.7) * 0.5) * 0.5 * sk
    local oy = (cos(G.t * 41) + sin(G.t * 23.3) * 0.5) * 0.5 * sk
    -- no idle sway: camera only eases gently toward the paddle (smoothed) + decaying hit shake
    G.cam_px = lerp(G.cam_px or 0, PAD.x * 0.06, 1 - math.exp(-dt * 3))
    if shake < 0.02 then ox, oy = 0, 0 end
    local px = G.cam_px
    cam:set_position(vec3(CAM_BASE.x + px + ox, CAM_BASE.y + oy, CAM_BASE.z))
    cam:look_at(vec3(CAM_LOOK.x + px * 0.5 + ox * 0.3, CAM_LOOK.y + oy * 0.3, CAM_LOOK.z))
    score_pop = max(0, score_pop - dt * 4)
    banner.t = banner.t + dt
end
local function play_tick(dt, control)
    for k, v in pairs(G.pow) do
        if v > 0 then G.pow[k] = max(0, v - dt); if G.pow[k] == 0 and k == "fire" then refresh_ball_colour() end end
    end
    update_paddle(dt, control)
    local fire = (control == "player") and (G.click or pressed("Space")) and (G.serve_t or 1) > 0.25 or false
    if G.state == "serve" or (control == "auto" and #balls > 0 and balls[1].stuck) then
        G.serve_t = (G.serve_t or 0) + dt
        if fire or (control == "auto" and G.serve_t > 0.8) then
            for _, b in ipairs(balls) do launch(b) end
            if G.state == "serve" then G.state = "play" end
            fire = false
        end
    end
    if G.pow.laser > 0 then
        laser_cd = laser_cd - dt
        if (fire or (control == "player" and (mouse_down() or kdown("Space"))) or control == "auto") and laser_cd <= 0 then
            fire_lasers(); laser_cd = 0.28
        end
    end
    update_balls(dt); update_caps(dt); update_bolts(dt)
    draw_paddle(); draw_balls(dt)
end

local function do_menu_action(act)
    sfx("click")
    if act == "play" then
        runtime_ui.show(HUD); new_game(false)
    elseif act == "resume" then
        G.state = G.paused_from or "play"
    elseif act == "settings" then
        if SET then
            G.in_settings = true
            SET:open(function() G.in_settings = false end)
        end
    elseif act == "title" then
        to_title()
    elseif act == "quit" then
        pcall(fs.write, HISAVE, tostring(G.hiscore)); pcall(engine.quit)
    end
end

local function update(dt)
    dt = min(dt, 1 / 20)
    G.t = G.t + dt
    local okS, sz = pcall(runtime_ui.get_surface_size)
    if okS and sz and (sz.width or 0) > 0 and (sz.width ~= SW or sz.height ~= SH) then SW, SH = sz.width, sz.height; cache = {} end
    flush_mats()
    if G.state == "boot" then
        G.boot = (G.boot or 0) + 1
        if G.boot == 3 then
            paint_bricks(1.0)
            if SET then pcall(SET.apply, SET) end
            to_title()
            pe_log("[Breakout] ready")
        end
        return
    end
    if SET then
        PSCALE = SET:particle_scale() or 1; SHAKE_SCALE = SET:shake_scale() or 1
        if SET:update(dt) then latch(); mouse_clicked(); update_visuals(dt); draw_hud(dt); return end
    end
    -- mouse motion flag for menu hover
    local ok, mp = pcall(input.get_mouse_position)
    G.mouse_moved = ok and mp and G._mx and (abs(mp.x - G._mx) + abs(mp.y - G._my) > 1) or false
    if ok and mp then G._mx, G._my = mp.x, mp.y end
    G.click = mouse_clicked()
    if pressed("M") then if SET then SET:toggle_mute() end end
    local st = G.state
    if st == "title" then
        local act = menu_input(pressed)
        if act then do_menu_action(act) end
        if G.state == "title" then
            play_tick(dt, "auto")
            if #balls == 0 then serve(); G.state = "title" end
            if bricks_ready() and level_cleared() then G.level = G.level % #LEVELS + 1; reset_wall(); G.state = "title" end
        end
    elseif st == "levelintro" then
        G.intro_t = G.intro_t + dt
        update_paddle(dt, "player"); draw_paddle()
        if bricks_ready() and G.intro_t > 1.0 then serve() end
    elseif st == "serve" or st == "play" then
        if pressed("Escape") or pressed("P") then
            G.paused_from = st; G.state = "paused"; sfx("click")
            set_menu("pause", { { label = "RESUME", act = "resume" }, { label = "SETTINGS", act = "settings" }, { label = "QUIT TO TITLE", act = "title" } })
        else
            play_tick(dt, G.autoplay and "auto" or "player")
            if G.state == "play" and #balls == 0 then lose_ball()
            elseif level_cleared() then
                G.state = "clear"; G.clear_t = 0; sfx("clear"); celebrate()
                show_banner("WALL CLEARED", "+" .. (100 * G.level) .. " BONUS", 2.2); add_score(100 * G.level)
                add_shake(0.4)
            end
        end
    elseif st == "paused" then
        if pressed("Escape") or pressed("P") then G.state = G.paused_from or "play"
        else local act = menu_input(pressed); if act then do_menu_action(act) end end
        draw_paddle(); draw_balls(0)
    elseif st == "clear" then
        G.clear_t = G.clear_t + dt
        clear_actors(); update_paddle(dt, "player"); draw_paddle()
        if G.clear_t > 0.6 and G.clear_t < 1.6 and rand() < 0.2 then celebrate() end
        if G.clear_t > 2.6 then G.level = G.level + 1; reset_wall() end
    elseif st == "over" then
        local act = menu_input(pressed)
        if act then do_menu_action(act) end
        update_paddle(dt, "player"); draw_paddle()
    end
    update_visuals(dt)
    draw_hud(dt)
    latch()
end

local function init()
    build_world(); build_lights(); build_shards(); build_paddle(); build_ball_pool(); build_caps(); build_bolts()
    pcall(audio.set_master_volume, 0.5)
    G.state = "boot"
end
init()
hooks { update = update }

-- automation helpers (MCP): BO.sim(seconds, keys) steps the game deterministically at 60 Hz
function G.sim(sec, keys)
    G.vkeys = keys or {}
    for _ = 1, floor(sec * 60) do update(1 / 60) end
    G.vkeys = {}
    return G.state .. " score=" .. G.score .. " lives=" .. G.lives .. " bricks=" .. #bricks .. " balls=" .. #balls
end
G.SET = SET; G.new_game = new_game; G.reset_wall = reset_wall; G.apply_power = apply_power; G.to_title = to_title
G.set_level = function(l) G.level = l; reset_wall() end
