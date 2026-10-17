-- BUBBLE BOBBLE REMIX  (PhasmaEngine, Lua)
-- A modernized remake of Taito's Bubble Bobble (1986). Faithful core: a bubble dragon on single-screen levels, blow
-- bubbles to trap enemies, pop them to defeat them, collect the fruit they turn into, chain pops for doubling points,
-- EXTEND letter bubbles for an extra life, a wrap-through hole in the floor and ceiling, and Baron von Blubba who
-- hunts you when you take too long ("Hurry up!").
-- Modern visuals: cooked 3D dragon/enemies/bubbles/fruit, glowing tiled levels, layered pop VFX with dynamic lights,
-- HDR + TAA with soft bloom (see /workspace/games/common/RENDER_SETTINGS.md).
local PI, TAU = math.pi, math.pi * 2
local sin, cos, sqrt, rand, floor, abs, min, max = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max
math.randomseed(floor((engine.get_metrics and (engine.get_metrics() or {}).frame or 0) + 1986))
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local G = { state = "boot", t = 0, dt = 0 }
_G.BB = G; pcall(function() engine.BB = G end)

------------------------------------------------------------------ deferred materials (engine quirk: replay writes)
local _mset, _mtex, _mds = material.set, material.set_texture, material.set_double_sided
local mat_q = {}
local function qpush(f) mat_q[#mat_q + 1] = { f = f, n = 0 } end
local function mset(n, k, v) pcall(_mset, n, k, v); qpush(function() pcall(_mset, n, k, v) end) end
local function mtex(n, k, v) qpush(function() pcall(_mtex, n, k, v) end) end
local function mds(n) pcall(_mds, n, true); qpush(function() pcall(_mds, n, true) end) end
local function flush_mats()
    for i = #mat_q, 1, -1 do
        local q = mat_q[i]; q.n = q.n + 1
        if q.n == 2 or q.n == 6 then q.f() end
        if q.n >= 6 then table.remove(mat_q, i) end
    end
end
local function mlive(n, k, v) pcall(_mset, n, k, v) end
local function paint(n, base, emis, rough, metal)
    if not n then return end
    mset(n, "base_color", vec4(base[1], base[2], base[3], base[4] or 1))
    mset(n, "emissive", vec3(emis[1], emis[2], emis[3]))
    mset(n, "roughness", rough or 0.3)
    mset(n, "metallic", metal or 0.0)
end
local function sfx(name) pcall(audio.play, name .. ".wav") end

------------------------------------------------------------------ render setup
local function S(k, v) pcall(settings.set, k, v) end
local ss = scene.add_empty_node("BBSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "bubbles.hdr")
S("hdr", true); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false); S("dof", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.25)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", true); S("IBL_intensity", 0.7)
S("color_grading", true); S("color_grading_saturation", 1.12); S("color_grading_contrast", 1.04)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "SETTINGS", subtitle = "Bubble Bobble Remix", file = "Save/settings.cfg",
    click = function() sfx("click") end, defaults = { master = 0.5 },
    theme = { accent = { 0.45, 0.95, 0.6, 1 }, accent2 = { 1, 0.55, 0.85, 1 }, text = { 0.82, 0.86, 0.9, 1 }, selected_text = { 1, 1, 1, 1 } } })
SET:apply()
local set_open = false

------------------------------------------------------------------ arena + camera
local LEVELS = load(fs.read("Scripts/levels.lua"), "@levels.lua")()
local XMIN, XMAX = -14, 14          -- inner walls
local TOP = 25                      -- ceiling row bottom
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1600, surf.height or 900
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local FOVX = 0.9
local VIEW_HH = 14.4
local VIEW_HW = VIEW_HH * SW / SH
local CAMZ = VIEW_HW / math.tan(FOVX * 0.5)
local CAMY = 12.9
pcall(function() cam:set_fov(math.deg(FOVX)) end)
local HIDE = vec3(0, -1000, 0)
local function to_screen(x, y) return SW / 2 + x / VIEW_HW * SW / 2, SH / 2 - (y - CAMY) / VIEW_HH * SH / 2 end

------------------------------------------------------------------ templates -> clones
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[BB] missing template " .. name); return nil end
    TPL[name] = { node = n, mesh = n:get_mesh_refs()[1] }
    return TPL[name]
end
local seq = 0
local function clone(name, pos, scale, parent)
    local t = tpl(name); seq = seq + 1
    local n = scene.add_empty_node(name .. "_c" .. seq)
    if t and t.mesh then n:add_mesh_ref(t.mesh) end
    if parent then n:set_parent(parent) end
    n:set_position(pos or HIDE)
    if scale then n:set_scale(scale) end
    return n
end
local function prim(kind, pos, scale)
    seq = seq + 1
    local n = scene.add_empty_node(kind .. "_p" .. seq)
    scene.attach_primitive(n, kind)
    n:set_position(pos); n:set_scale(scale)
    return n
end
local function tnode(name) local t = tpl(name); return t and t.node end
local function empty(name) seq = seq + 1; local n = scene.add_empty_node(name .. seq); n:set_position(HIDE); return n end

------------------------------------------------------------------ lights
local LNODE = {}
local LIGHT_GAIN = 0.12
local function add_point() lights.add_point(); return #lights.get_point_lights() - 1 end
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
    lights.set_directional_light(0, vec3(-0.35, -0.5, -0.8), vec3(0.85, 0.85, 1.0), 1.4)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    L.key = addp(vec3(-10, 24, 18), vec3(0.8, 0.85, 1.0), 70, 60)
    L.fill = addp(vec3(10, 4, 22), vec3(1.0, 0.85, 0.95), 55, 60)
    L.accent = addp(vec3(0, 13, 6), vec3(1, 0.5, 0.8), 40, 30)
    L.player = addp(HIDE, vec3(0.5, 1.0, 0.6), 0, 1)
    L.baron = addp(HIDE, vec3(1, 0.3, 0.3), 0, 1)
    L.flash = {}
    for i = 1, 6 do L.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1, power = 0, rad = 6 } end
end
local flash_next = 1
local function flash(x, y, col, power, life, rad)
    local f = L.flash[flash_next]; flash_next = flash_next % #L.flash + 1
    f.t, f.life, f.x, f.y, f.col, f.power, f.rad = 0, life or 0.35, x, y, vec3(col[1], col[2], col[3]), power or 40, rad or 7
end
local function update_flashes(dt)
    for _, f in ipairs(L.flash) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = 1 - clamp(f.t / f.life, 0, 1)
            set_point(f.idx, vec3(f.x, f.y, 2.5), f.col, f.power * k * k, f.rad)
            if f.t >= f.life then set_point(f.idx, HIDE, f.col, 0, 1) end
        end
    end
end

------------------------------------------------------------------ particles
local function PS() return SET:particle_scale() end
local function burst(x, y, o)
    pcall(particles.emit_burst, {
        position = vec3(x, y, o.z or 0.6), velocity = o.vel or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = max(1, floor((o.count or 40) * PS())),
        size_min = o.smin or 0.05, size_max = o.smax or 0.16, life_min = o.lmin or 0.25, life_max = o.lmax or 0.7,
        spawn_radius = o.radius or 0.3, noise_strength = o.spread or 14, drag = o.drag or 2.0,
        gravity = o.grav or vec3(0, 0, 0), cleanup_delay = 3.0,
    })
end
local function hot(c, k) return vec4(c[1] * k + 0.6, c[2] * k + 0.6, c[3] * k + 0.6, 1) end
local function new_emitter(o)
    local ok, e = pcall(particles.add_emitter, {
        position = HIDE, velocity = o.vel or vec3(0, 0, 0), gravity = o.grav or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = o.count or 300, spawn_rate = 0,
        spawn_radius = o.radius or 0.1, size_min = o.smin or 0.06, size_max = o.smax or 0.16,
        life_min = o.lmin or 0.15, life_max = o.lmax or 0.4, noise_strength = o.noise or 1.0, drag = o.drag or 1.5 })
    return ok and e or nil
end
local function emitter_at(e, x, y, z, rate, vel)
    if not e then return end
    pcall(particles.set_emitter, e, "position", vec3(x, y, z or 0))
    pcall(particles.set_emitter, e, "spawn_rate", rate * PS())
    if vel then pcall(particles.set_emitter, e, "velocity", vel) end
end

------------------------------------------------------------------ VFX: tumbling star debris + expanding pop rings
local STAR_COL = { [0] = { 1, .85, .3 }, { .4, 1, .6 }, { 1, .45, .85 }, { .45, .8, 1 }, { 1, .5, .3 } }
local STARS, live_stars = {}, {}
local function build_stars()
    for c = 0, 4 do
        local col = STAR_COL[c]
        paint(tnode("T_star_" .. c), col, { col[1] * 1.6, col[2] * 1.6, col[3] * 1.6 }, 0.3, 0.2)
        STARS[c] = { next = 1 }
        for k = 1, 14 do STARS[c][k] = { node = clone("T_star_" .. c, HIDE), life = 0 } end
    end
end
local function star_burst(slot, x, y, n, power)
    local pool = STARS[slot] or STARS[0]
    for _ = 1, floor((n or 6) * (0.4 + 0.6 * PS()) + 0.5) do
        local s = pool[pool.next]; pool.next = pool.next % #pool + 1
        local a, sp = rr(0, TAU), rr(4, 10) * (power or 1)
        s.x, s.y, s.z = x, y, rr(0.2, 1.2)
        s.vx, s.vy = cos(a) * sp, sin(a) * sp + 4
        s.r, s.w = rr(0, 360), rr(-600, 600)
        s.sz = rr(0.5, 0.9); s.life = rr(0.6, 1.1)
        if not s.live then s.live = true; live_stars[#live_stars + 1] = s end
    end
end
local function update_stars(dt)
    for i = #live_stars, 1, -1 do
        local s = live_stars[i]
        s.life = s.life - dt
        if s.life <= 0 then s.live = false; s.node:set_position(HIDE); table.remove(live_stars, i)
        else
            local d = math.exp(-1.5 * dt)
            s.vx, s.vy = s.vx * d, s.vy * d - 14 * dt
            s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
            s.r = s.r + s.w * dt
            local k = clamp(s.life / 0.3, 0, 1) * s.sz
            s.node:set_position(vec3(s.x, s.y, s.z)); s.node:set_rotation(vec3(s.r * 0.3, s.r, s.r * 0.5)); s.node:set_scale(vec3(k, k, k))
        end
    end
end
local RINGS, ring_next = {}, 1
local function build_rings()
    for i = 1, 10 do RINGS[i] = { node = clone("T_bub_ring", HIDE), t = 9, life = 0.2 } end
end
local function pop_ring(x, y, size)
    local r = RINGS[ring_next]; ring_next = ring_next % #RINGS + 1
    r.x, r.y, r.size, r.t, r.life = x, y, size or 1, 0, 0.18
end
local function update_rings(dt)
    for _, r in ipairs(RINGS) do
        if r.t < r.life then
            r.t = r.t + dt
            local k = clamp(r.t / r.life, 0, 1)
            local s = r.size * (1 + 0.9 * (1 - (1 - k) ^ 2))
            r.node:set_position(vec3(r.x, r.y, 0.5)); r.node:set_scale(vec3(s, s, 0.4 + (1 - k)))
            if r.t >= r.life then r.node:set_position(HIDE) end
        end
    end
end
local shake = 0
local function add_shake(a) shake = min(1.0, shake + a) end

------------------------------------------------------------------ world: backdrop, level blocks with glow trims, ambient bubbles
local BG = {}
local LVN = {}         -- per-level { blk, trim }
local function build_world()
    local z = -60
    local hw, hh = (CAMZ - z) * math.tan(FOVX * 0.5), (CAMZ - z) * math.tan(FOVX * 0.5) * SH / SW
    BG.sky = prim("quad", vec3(0, CAMY, z), vec3(hw * 2.2, hh * 2.2, 1))
    paint(BG.sky, { 0, 0, 0 }, { 0.75, 0.75, 0.85 }, 1, 0); mds(BG.sky); mtex(BG.sky, "emissive", "Textures/backdrop.png")
    paint(tnode("T_backwall"), { .1, .1, .14 }, { .012, .012, .025 }, 0.85, 0); mtex(tnode("T_backwall"), "base_color", "Textures/block.png")
    BG.wall = clone("T_backwall", vec3(0, 0, 0))
    for i, lv in ipairs(LEVELS) do
        local c = lv.col
        local b, t = tnode("T_level" .. (i - 1)), tnode("T_trim" .. (i - 1))
        paint(b, { c[1] * 0.75, c[2] * 0.75, c[3] * 0.75 }, { c[1] * 0.05, c[2] * 0.05, c[3] * 0.05 }, 0.45, 0.1); mtex(b, "base_color", "Textures/block.png")
        paint(t, c, { c[1] * 2.2, c[2] * 2.2, c[3] * 2.2 }, 0.3, 0)
        LVN[i] = { blk = clone("T_level" .. (i - 1), HIDE), trim = clone("T_trim" .. (i - 1), HIDE) }
    end
    BG.amb = {}
    for i = 1, 1 do
        BG.amb[i] = new_emitter({ c0 = vec4(0.5, 0.9, 1.1, 0.4), c1 = vec4(0.4, 0.6, 1.0, 0), count = 120, radius = 12, smin = 0.03, smax = 0.08,
            lmin = 3, lmax = 6, noise = 0.8, drag = 0.3, vel = vec3(0, 1.4, 0) })
    end
    BG.sparkle = new_emitter({ c0 = vec4(1.4, 1.2, 1.6, 0.7), c1 = vec4(0.6, 0.5, 1, 0), count = 250, radius = 14, smin = 0.03, smax = 0.07,
        lmin = 2, lmax = 4, noise = 0.5, drag = 0.2, vel = vec3(0, 0.2, 0) })
end
local AMB_X = { -18.5, 18.5, -21, 21 }
local function update_world(dt)
    local t = G.t
    for i, e in ipairs(BG.amb) do emitter_at(e, 0, 2, -1.2, 0.6) end
    emitter_at(BG.sparkle, 0, 13, -4, 5)
end

------------------------------------------------------------------ input
local prev = {}
local keyfn = input.is_key_down_raw or input.is_key_pressed
local function held(k) local ok, v = pcall(keyfn, k); return ok and v end
local function edge(k) local d = held(k); local p = prev[k]; prev[k] = d; return d and not p end
local function any(...) for _, k in ipairs({ ... }) do if held(k) then return true end end; return false end

------------------------------------------------------------------ state
local score, hiscore, lives, level_no = 0, 0, 3, 0
local next_extra = 30000
pcall(function() local s = fs.read("Save/bb_hiscore.txt"); if s then hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, "Save/bb_hiscore.txt", tostring(hiscore)) end
local banner = { text = "", sub = "", t = 0, col = { 1, .9, .6 } }
local function show_banner(s, sub, d, col) banner.text, banner.sub, banner.t, banner.col = s, sub or "", d or 2.4, col or { 1, .9, .6 } end
local POP = {}
for i = 1, 10 do POP[i] = { t = 9 } end
local pop_next = 1
local function popup(x, y, txt, col)
    local p = POP[pop_next]; pop_next = pop_next % #POP + 1
    p.x, p.y, p.txt, p.col, p.t = x, y, txt, col or { 1, .95, .6 }, 0
end
local function add_score(p, x, y, col)
    score = score + p
    if x then popup(x, y, tostring(p), col) end
    if score >= next_extra then next_extra = next_extra + 50000; lives = lives + 1; sfx("extend"); show_banner("Extra Life", "", 1.8) end
end

------------------------------------------------------------------ level collision (one-way platforms, solid side walls, wrap-through hole)
local SOL = {}
local GAP0, GAP1 = -3, 3
local function set_solids(lv)
    SOL = {}
    for _, b in ipairs(lv.solids) do if b[1] >= XMIN and b[3] <= XMAX then SOL[#SOL + 1] = b end end
end
local function land_check(x, hw, yo, yn)
    for _, b in ipairs(SOL) do
        if x + hw > b[1] + 0.05 and x - hw < b[3] - 0.05 and yo >= b[4] - 0.02 and yn <= b[4] then return b[4] end
    end
end
local function ground_at(x, hw, y)
    for _, b in ipairs(SOL) do
        if x + hw > b[1] + 0.05 and x - hw < b[3] - 0.05 and abs(y - b[4]) < 0.03 then return b end
    end
end
local GRAV, JUMP_V, FALL_MAX = 44, 19.5, -15
-- integrate a walking body {x,y,vx,vy,hw,h,ground}; returns true when it just landed
local function step_body(a, dt, grav_k)
    local landed = false
    a.x = clamp(a.x + a.vx * dt, XMIN + a.hw, XMAX - a.hw)
    if a.ground then
        if not ground_at(a.x, a.hw, a.y) then a.ground = false; a.vy = 0 end
    end
    if not a.ground then
        a.vy = max(FALL_MAX, a.vy - GRAV * (grav_k or 1) * dt)
        local yo = a.y
        a.y = a.y + a.vy * dt
        if a.vy <= 0 then
            local top = land_check(a.x, a.hw, yo, a.y)
            if top then a.y = top; a.vy = 0; a.ground = true; landed = true end
        end
        local in_gap = a.x - a.hw > GAP0 and a.x + a.hw < GAP1
        if not in_gap and a.y + a.h > TOP and a.vy > 0 then a.y = TOP - a.h; a.vy = 0 end
        if a.y < -1.8 then a.y = 26.3 end          -- fell through the floor hole: drop in from the top
        if a.y > 26.6 then a.y = -1.6 end
    end
    return landed
end

------------------------------------------------------------------ palettes + model building
local PAL = {
    dragon = { body = { { .25, .85, .3 }, { .02, .08, .02 }, .45, 0 }, belly = { { 1, .9, .55 }, { .08, .06, .02 }, .5, 0 },
        spikes = { { 1, 1, 1 }, { .25, .25, .25 }, .35, 0 }, eye = { { 1, 1, 1 }, { .35, .35, .35 }, .2, 0 },
        pupil = { { .02, .02, .05 }, { 0, 0, 0 }, .1, 0 }, foot = { { 1, .7, .3 }, { .06, .03, 0 }, .5, 0 } },
    zen = { body = { { .85, .88, .95 }, { .05, .05, .07 }, .3, .3 }, visor = { { .08, .08, .15 }, { 0, 0, .02 }, .15, .2 },
        eye = { { .4, 1, 1 }, { 1.2, 3.0, 3.2 }, .2, 0 }, feet = { { .95, .55, .2 }, { .05, .02, 0 }, .5, 0 }, key = { { 1, .8, .3 }, { .25, .15, .02 }, .25, .8 } },
    zenA = { body = { { 1, .3, .3 }, { .35, .03, .03 }, .3, .3 }, visor = { { .15, .02, .02 }, { 0, 0, 0 }, .15, .2 },
        eye = { { 1, 1, .4 }, { 3.5, 2.6, .5 }, .2, 0 }, feet = { { .95, .55, .2 }, { .05, .02, 0 }, .5, 0 }, key = { { 1, .8, .3 }, { .25, .15, .02 }, .25, .8 } },
    monsta = { body = { { .6, .35, .95 }, { .06, .02, .12 }, .35, 0 }, eye = { { 1, 1, 1 }, { .8, .8, .9 }, .2, 0 }, fin = { { .9, .6, 1 }, { .1, .05, .15 }, .4, 0 } },
    monstaA = { body = { { 1, .3, .45 }, { .3, .03, .06 }, .35, 0 }, eye = { { 1, 1, .5 }, { 3, 2.4, .6 }, .2, 0 }, fin = { { 1, .6, .5 }, { .12, .04, .02 }, .4, 0 } },
    baron = { body = { { .78, .8, .92 }, { .05, .05, .08 }, .4, 0 }, eye = { { 1, .2, .15 }, { 4, .5, .3 }, .2, 0 }, brow = { { .1, .1, .15 }, { 0, 0, 0 }, .4, 0 } },
    bub = { ring = { { .5, 1, .8 }, { .7, 2.0, 1.3 }, .1, 0 }, band = { { .8, 1, 1 }, { .25, .55, .6 }, .1, 0 },
        shell = { { .03, .1, .08 }, { .07, .26, .2 }, .1, 0 }, hl = { { 1, 1, 1 }, { 2.4, 2.4, 2.4 }, .1, 0 } },
    cherry = { { .95, .08, .12 }, { .25, .01, .02 }, .2, 0 }, cherry_stem = { { .3, .8, .2 }, { .02, .06, .01 }, .5, 0 },
    peach = { { 1, .62, .45 }, { .12, .05, .03 }, .45, 0 }, leaf = { { .3, .85, .25 }, { .02, .08, .01 }, .5, 0 },
    gem = { { .4, .8, 1 }, { .5, 1.3, 2.2 }, .05, .2 }, banana = { { 1, .88, .2 }, { .14, .1, 0 }, .4, 0 },
}
local LCOL = { { 1, .45, .45 }, { 1, .7, .25 }, { 1, 1, .35 }, { .4, 1, .5 }, { .4, .75, 1 }, { .85, .45, 1 } }
local LETTERS = { "E", "X", "T", "E", "N", "D" }
local function paint_templates()
    for k, parts in pairs(PAL) do
        if parts[1] then paint(tnode("T_" .. k), parts[1], parts[2], parts[3], parts[4])
        else for p, v in pairs(parts) do paint(tnode("T_" .. k .. "_" .. p), v[1], v[2], v[3], v[4]) end end
    end
    for i = 1, 6 do
        local c = LCOL[i]
        paint(tnode("T_lb" .. (i - 1) .. "_ring"), c, { c[1] * 1.6, c[2] * 1.6, c[3] * 1.6 }, .1, 0)
        paint(tnode("T_lb" .. (i - 1) .. "_shell"), { c[1] * .1, c[2] * .1, c[3] * .1 }, { c[1] * .35, c[2] * .35, c[3] * .35 }, .1, 0)
    end
    for i = 0, 2 do local c = ({ { .6, 1, .8 }, { 1, .8, .4 }, { 1, .4, .8 } })[i + 1]; paint(tnode("T_orb_" .. i), c, { c[1] * 3, c[2] * 3, c[3] * 3 }, .2, 0) end
end
local PARTS = { dragon = { "body", "belly", "spikes", "eye", "pupil" }, zen = { "body", "visor", "eye", "feet", "key" }, monsta = { "body", "eye", "fin" }, baron = { "body", "eye", "brow" } }
local function make_model(kind, base)
    local root = empty("m_" .. kind)
    local m = { root = root }
    for _, p in ipairs(PARTS[base or kind]) do m[p] = clone("T_" .. kind .. "_" .. p, vec3(0, 0, 0), nil, root) end
    if m.key then m.key:set_position(vec3(-0.5, 0.78, 0)) end
    if kind == "dragon" then
        m.f1 = clone("T_dragon_foot", vec3(0, 0, 0.24), nil, root); m.f2 = clone("T_dragon_foot", vec3(0, 0, -0.24), nil, root)
    end
    return m
end

------------------------------------------------------------------ player (Bub)
local START_X, START_Y = -11, 1
local P = { x = START_X, y = START_Y, vx = 0, vy = 0, hw = 0.42, h = 1.6, ground = true, face = 1, yaw = 90, alive = true,
    inv = 0, dead_t = 0, cool = 0, blow_t = 9, squash = 0, walk = 0, hold = 0, visible = true }
local function build_player()
    P.m = make_model("dragon")
    P.trail = new_emitter({ c0 = vec4(.8, 1.6, 1.0, 0.7), c1 = vec4(.3, .9, .5, 0), count = 150, radius = 0.25, smin = 0.03, smax = 0.07, lmin = 0.2, lmax = 0.45, noise = 0.8, drag = 2 })
end
local function dust(x, y, n, col)
    col = col or { .8, .85, 1 }
    burst(x, y + 0.1, { c0 = vec4(col[1], col[2], col[3], 0.6), c1 = vec4(col[1] * .5, col[2] * .5, col[3] * .5, 0), count = n or 8, smin = 0.06, smax = 0.16,
        lmin = 0.25, lmax = 0.5, radius = 0.35, spread = 3.5, drag = 3, grav = vec3(0, 1.2, 0), z = 0.8 })
end
local function anim_dragon(dt)
    local m = P.m
    if not P.visible then m.root:set_position(HIDE); return end
    P.yaw = damp(P.yaw, P.face > 0 and 28 or 152, 16, dt)
    P.squash = damp(P.squash, 0, 10, dt)
    local sq = P.squash
    local bob = 0
    if P.ground and abs(P.vx) > 0.5 then P.walk = P.walk + dt * (6 + abs(P.vx) * 1.6); bob = abs(sin(P.walk)) * 0.08 end
    local blow = P.blow_t < 0.18 and sin(P.blow_t / 0.18 * PI) or 0
    local spin = 0
    if not P.alive then spin = P.dead_t * 900 end
    local flick = (P.inv > 0 and P.alive and (G.t * 14) % 2 < 0.7)
    m.root:set_position(flick and HIDE or vec3(P.x, P.y + bob, 0))
    m.root:set_rotation(vec3(0, P.yaw + spin, P.ground and 0 or clamp(P.vy * 0.8, -12, 12)))
    m.root:set_scale(vec3(1 + sq * 0.25 + blow * 0.08, 1 - sq * 0.3 + blow * 0.04, 1 + sq * 0.25))
    m.belly:set_scale(vec3(1 + blow * 0.25, 1 + blow * 0.15, 1 + blow * 0.2))
    local fa = P.ground and sin(P.walk) * min(1, abs(P.vx) / 3) * 0.25 or 0.12
    m.f1:set_position(vec3(fa, P.ground and max(0, -sin(P.walk)) * 0.08 or 0.05, 0.24)); m.f2:set_position(vec3(-fa, P.ground and max(0, sin(P.walk)) * 0.08 or 0.05, -0.24))
    m.spikes:set_position(vec3(0, (P.ground and 0 or 0.03) + bob * 0.3, 0))
end

------------------------------------------------------------------ enemies
local ENEMIES = {}
local POOL = { zen = {}, monsta = {} }
local function build_enemies()
    for kind, n in pairs({ zen = 8, monsta = 6 }) do
        for i = 1, n do POOL[kind][i] = { m = make_model(kind), ma = make_model(kind .. "A", kind), used = false } end
    end
end
local ESPD = { zen = 3.3, monsta = 3.0 }
local function spawn_enemy(kind, x, y, delay)
    for _, slot in ipairs(POOL[kind]) do
        if not slot.used then
            slot.used = true
            local e = { kind = kind, slot = slot, x = x, y = 28 + rr(0, 1), ty = y, vx = 0, vy = 0, hw = 0.45, h = 1.3, ground = false,
                face = x > 0 and -1 or 1, state = "enter", delay = delay or 0, angry = false, t = 0, jump_t = rr(1, 3), yaw = 90, walk = rr(0, 6) }
            if kind == "monsta" then e.vx = (rand() < 0.5 and -1 or 1); e.vy = -1 end
            ENEMIES[#ENEMIES + 1] = e
            return e
        end
    end
end
local function despawn(e)
    e.slot.used = false; e.slot.m.root:set_position(HIDE); e.slot.ma.root:set_position(HIDE)
    for i = #ENEMIES, 1, -1 do if ENEMIES[i] == e then table.remove(ENEMIES, i) end end
end
local function enemies_left() local n = 0; for _, e in ipairs(ENEMIES) do if e.state ~= "dead" then n = n + 1 end end; return n end
local function anim_enemy(e, dt, pos, scale, spin)
    local m, other = e.angry and e.slot.ma or e.slot.m, e.angry and e.slot.m or e.slot.ma
    other.root:set_position(HIDE)
    e.yaw = damp(e.yaw, (e.face > 0 and 38 or 142), 10, dt)
    m.root:set_position(pos); m.root:set_rotation(vec3(spin and spin * 0.7 or 0, e.yaw + (spin or 0), spin and spin * 0.4 or 0)); m.root:set_scale(vec3(scale, scale, scale))
    if e.kind == "zen" then
        m.key:set_rotation(vec3(G.t * (e.angry and 900 or 400), 0, 0))
        m.feet:set_position(vec3(sin(e.walk) * 0.08, abs(cos(e.walk)) * 0.05, 0))
        m.body:set_position(vec3(0, abs(sin(e.walk)) * 0.05, 0))
    else
        m.fin:set_rotation(vec3(sin(G.t * 9 + e.walk) * 20, 0, 0))
    end
end
local function ai_enemy(e, dt)
    local spd = ESPD[e.kind] * (e.angry and 1.7 or 1) * (1 + 0.05 * min(level_no, 10))
    if e.kind == "monsta" then
        e.x = e.x + e.vx * spd * dt; e.y = e.y + e.vy * spd * 0.75 * dt
        if e.x < XMIN + 0.6 then e.x = XMIN + 0.6; e.vx = 1 elseif e.x > XMAX - 0.6 then e.x = XMAX - 0.6; e.vx = -1 end
        if e.y < 1.0 then e.y = 1.0; e.vy = 1 elseif e.y > 23.6 then e.y = 23.6; e.vy = -1 end
        e.face = e.vx; e.walk = e.walk + dt
        return
    end
    if e.ground then
        e.vx = e.face * spd
        local ahead = e.x + e.face * 0.7
        if e.x <= XMIN + e.hw + 0.01 or e.x >= XMAX - e.hw - 0.01 then e.face = -e.face
        elseif not ground_at(ahead, 0.05, e.y) and e.y > 1.5 and not (P.alive and P.y < e.y - 1) and rand() < 0.4 then e.face = -e.face; e.vx = e.face * spd end
        e.jump_t = e.jump_t - dt
        local above = P.alive and P.y > e.y + 2 and abs(P.x - e.x) < 7
        if e.jump_t <= 0 then
            e.jump_t = rr(1.2, 3.0) / (e.angry and 1.6 or 1)
            if above or rand() < 0.3 then e.vy = JUMP_V * 1.02; e.ground = false end
        end
        if P.alive and abs(P.y - e.y) < 1 and rand() < dt * 0.6 then e.face = P.x > e.x and 1 or -1 end
    else
        e.vx = damp(e.vx, e.face * spd * 0.6, 3, dt)
    end
    step_body(e, dt, 0.8)
    e.walk = e.walk + dt * spd * 2.4
end

------------------------------------------------------------------ bubbles
local BUBS, LBUBS = {}, {}
local function make_bubble(prefix)
    local root = empty("bub")
    local b = { root = root, live = false }
    b.shell = clone(prefix .. "_shell", vec3(0, 0, 0), nil, root)
    b.ring = clone(prefix .. "_ring", vec3(0, 0, 0), nil, root)
    b.band = clone("T_bub_band", vec3(0, 0, 0), nil, root)
    b.hl = clone("T_bub_hl", vec3(0, 0, 0), nil, root)
    return b
end
local function build_bubbles()
    for i = 1, 22 do BUBS[i] = make_bubble("T_bub") end
    for i = 1, 6 do LBUBS[i] = make_bubble("T_lb" .. (i - 1)); LBUBS[i].letter = i end
end
local function blow_bubble()
    for _, b in ipairs(BUBS) do
        if not b.live then
            b.live = true; b.x = clamp(P.x + P.face * 0.7, XMIN + 0.5, XMAX - 0.5); b.y = P.y + 0.85; b.vx = P.face * 17; b.vy = 0
            b.age = 0; b.shot = true; b.life = 11; b.enemy = nil; b.r = 0.35; b.ph = rr(0, TAU); b.pop_t = nil; b.wob = 0
            burst(b.x, b.y, { c0 = vec4(1, 2, 1.5, .8), c1 = vec4(.3, .9, .6, 0), count = 10, smin = .04, smax = .1, lmin = .15, lmax = .35, radius = .2, spread = 6, drag = 4, vel = vec3(P.face * 6, 0, 0) })
            sfx("blow")
            return b
        end
    end
end
local letter_t = 10
local GOT = { false, false, false, false, false, false }
local function spawn_letter()
    local miss = {}
    for i = 1, 6 do if not GOT[i] and not LBUBS[i].live then miss[#miss + 1] = i end end
    if #miss == 0 then return end
    local b = LBUBS[miss[rand(1, #miss)]]
    b.live = true; b.x = rr(GAP0 + 1, GAP1 - 1); b.y = -1.2; b.vx = 0; b.vy = 2.2; b.age = 1; b.shot = false; b.life = 15; b.r = 0.95; b.ph = rr(0, TAU); b.pop_t = nil; b.wob = 0
end

------------------------------------------------------------------ fruit
local FRUIT_KINDS = { { name = "cherry", parts = { "T_cherry", "T_cherry_stem" }, pts = 500, col = { 1, .3, .35 } },
    { name = "banana", parts = { "T_banana" }, pts = 700, col = { 1, .9, .3 } },
    { name = "peach", parts = { "T_peach", "T_leaf" }, pts = 1000, col = { 1, .65, .5 } },
    { name = "gem", parts = { "T_gem" }, pts = 2000, col = { .5, .85, 1 } } }
local FRUITS = {}
local function build_fruit()
    for k, fk in ipairs(FRUIT_KINDS) do
        for i = 1, 8 do
            local root = empty("fruit")
            for _, p in ipairs(fk.parts) do clone(p, vec3(0, 0, 0), nil, root) end
            FRUITS[#FRUITS + 1] = { root = root, kind = k, live = false }
        end
    end
end
local function spawn_fruit(x, y, chain)
    local k = clamp(1 + floor(level_no / 2) % 2 + (chain or 0), 1, 4)
    for _, f in ipairs(FRUITS) do
        if not f.live and f.kind == k then
            f.live = true; f.x, f.y, f.vx, f.vy = x, y, 0, 6; f.hw, f.h, f.ground = 0.35, 0.8, false; f.t = 0; f.life = 11
            return f
        end
    end
end
local function update_fruit(dt)
    for _, f in ipairs(FRUITS) do
        if f.live then
            f.t = f.t + dt; f.life = f.life - dt
            if step_body(f, dt, 0.7) then dust(f.x, f.y, 5, FRUIT_KINDS[f.kind].col) end
            local bob = f.ground and 0.12 + sin(f.t * 4) * 0.1 or 0
            local blink = f.life < 2 and (f.t * 10) % 2 < 0.8
            f.root:set_position(blink and HIDE or vec3(f.x, f.y + bob, 0.3)); f.root:set_rotation(vec3(0, f.t * 90, 0))
            local s = min(1, f.t * 4) * 1.1; f.root:set_scale(vec3(s, s, s))
            if f.ground and rand() < dt * 2.5 then local c = FRUIT_KINDS[f.kind].col; burst(f.x + rr(-.4, .4), f.y + rr(.3, 1), { c0 = hot(c, 1.2), c1 = vec4(c[1], c[2], c[3], 0), count = 2, smin = .04, smax = .08, lmin = .4, lmax = .7, radius = .1, spread = 1, drag = 1, grav = vec3(0, 1, 0) }) end
            if f.life <= 0 then f.live = false; f.root:set_position(HIDE)
            elseif P.alive and abs(P.x - f.x) < 0.9 and f.y > P.y - 0.8 and f.y < P.y + 1.6 then
                local fk = FRUIT_KINDS[f.kind]
                add_score(fk.pts, f.x, f.y + 1.2, fk.col); sfx("fruit")
                burst(f.x, f.y + 0.5, { c0 = hot(fk.col, 2), c1 = vec4(fk.col[1], fk.col[2], fk.col[3], 0), count = 30, smin = .04, smax = .1, lmin = .3, lmax = .6, radius = .3, spread = 10, drag = 3 })
                flash(f.x, f.y + 0.6, fk.col, 30, 0.3, 5)
                f.live = false; f.root:set_position(HIDE)
            end
        end
    end
end

------------------------------------------------------------------ popping + enemy defeat
local function kill_enemy(e, chain_n)
    e.state = "dead"; e.t = 0; e.vx = rr(4, 8) * (rand() < 0.5 and -1 or 1); e.vy = rr(13, 17); e.ground = false; e.chain = chain_n
    local pts = 1000 * 2 ^ min(chain_n - 1, 5)
    add_score(pts, e.x, e.y + 1.5, { .7, 1, .8 })
    star_burst(chain_n % 5, e.x, e.y + 0.5, 6 + chain_n * 2, 1)
    flash(e.x, e.y, { .6, 1, .7 }, 70, 0.4, 8); add_shake(0.12 + chain_n * 0.04); sfx("kill")
    if chain_n >= 2 then popup(e.x, e.y + 2.6, chain_n .. "x combo", { 1, .6, .9 }) end
end
local function pop_fx(b, col)
    col = col or { .5, 1, .8 }
    local r = b.r or 0.95
    burst(b.x, b.y, { c0 = hot(col, 1.6), c1 = vec4(col[1], col[2], col[3], 0), count = 28, smin = .04, smax = .11, lmin = .2, lmax = .45, radius = r * 0.9, spread = 9, drag = 3.5 })
    burst(b.x, b.y, { c0 = vec4(1.8, 1.8, 1.9, 1), c1 = vec4(.6, .9, 1, 0), count = 10, smin = .08, smax = .2, lmin = .08, lmax = .18, radius = r * 0.5, spread = 3, drag = 5 })
    pop_ring(b.x, b.y, r)
    sfx("pop")
end
-- pop a bubble and every bubble touching it (chain), counting trapped enemies for the combo bonus
local function pop_chain(first)
    local chain = { n = 0 }
    local queue, qi = { first }, 1
    first.pop_t = 0
    while qi <= #queue do
        local b = queue[qi]; qi = qi + 1
        for _, o in ipairs(BUBS) do
            if o.live and not o.pop_t and not o.shot then
                local dx, dy = o.x - b.x, o.y - b.y
                if dx * dx + dy * dy < 2.3 * 2.3 then o.pop_t = qi * 0.06; o.chain = chain; queue[#queue + 1] = o end
            end
        end
    end
    first.chain = chain
end
local function finish_pop(b)
    local col = nil
    if b.letter then
        col = LCOL[b.letter]
        GOT[b.letter] = true; sfx("letter"); popup(b.x, b.y + 1.4, "Letter " .. LETTERS[b.letter], col)
        flash(b.x, b.y, col, 50, 0.35, 7)
        local all = true
        for i = 1, 6 do all = all and GOT[i] end
        if all then
            lives = lives + 1; sfx("extend"); show_banner("EXTEND", "Extra life!", 2.6, { 1, .8, .4 })
            for i = 1, 6 do GOT[i] = false end
            for i = 1, 6 do star_burst(i % 5, rr(-10, 10), rr(4, 20), 6, 1.2) end
        end
    elseif b.enemy then
        local ch = b.chain or { n = 0 }
        ch.n = ch.n + 1
        local e = b.enemy; e.x, e.y = b.x, b.y - 0.6
        kill_enemy(e, ch.n); col = { .7, 1, .8 }
    end
    pop_fx(b, col)
    b.live = false; b.enemy = nil; b.root:set_position(HIDE)
end
local function update_bubble(b, dt)
    b.age = b.age + dt; b.life = b.life - dt; b.ph = b.ph + dt
    if b.pop_t then b.pop_t = b.pop_t - dt; if b.pop_t <= 0 then finish_pop(b) end; return end
    if b.shot then
        b.x = b.x + b.vx * dt; b.vx = b.vx * math.exp(-7 * dt)
        b.r = min(0.95, b.r + dt * 3.5)
        if b.x < XMIN + b.r then b.x = XMIN + b.r; b.vx = 0 elseif b.x > XMAX - b.r then b.x = XMAX - b.r; b.vx = 0 end
        if abs(b.vx) < 2.5 then b.shot = false end
        for _, e in ipairs(ENEMIES) do
            if (e.state == "walk") and abs(e.x - b.x) < 0.95 and abs(e.y + 0.6 - b.y) < 1.0 then
                e.state = "trapped"; b.enemy = e; b.shot = false; b.r = 0.95; b.life = 8.5; b.vx = b.vx * 0.3; sfx("trap")
                burst(b.x, b.y, { c0 = vec4(1.2, 2, 1.6, 1), c1 = vec4(.3, .8, .6, 0), count = 18, smin = .04, smax = .1, lmin = .2, lmax = .5, radius = .8, spread = 5, drag = 3 })
                flash(b.x, b.y, { .5, 1, .8 }, 25, 0.3, 5)
                break
            end
        end
    else
        b.r = min(0.95, b.r + dt * 3)
        local cy = 22.4 - (b.letter and 0 or 0)
        if b.y < cy then b.vy = damp(b.vy, 2.6, 2, dt) else b.vy = damp(b.vy, (cy - b.y) * 1.5, 3, dt) end
        local tx = (b.y > cy - 1) and sin(b.ph * 0.4 + b.x) * 6 or b.x
        b.vx = damp(b.vx, clamp((tx - b.x) * 0.5, -2, 2) + sin(b.ph * 1.7) * 0.3, 1.5, dt)
        for _, o in ipairs(BUBS) do      -- bubbles push apart
            if o ~= b and o.live and not o.shot then
                local dx, dy = b.x - o.x, b.y - o.y; local d2 = dx * dx + dy * dy
                if d2 < 3.4 and d2 > 1e-4 then local d = sqrt(d2); b.vx = b.vx + dx / d * 6 * dt; b.vy = b.vy + dy / d * 6 * dt end
            end
        end
        b.x = clamp(b.x + b.vx * dt, XMIN + b.r, XMAX - b.r); b.y = min(23.8, b.y + b.vy * dt)
    end
    -- player contact: bounce off the top while holding jump, otherwise pop it
    if P.alive and b.age > 0.2 and not b.shot then
        local dx, dy = b.x - P.x, b.y - (P.y + 0.8)
        if dx * dx + dy * dy < 1.5 * 1.5 then
            if P.vy < 0 and P.y > b.y - 0.15 and P.jump_held then
                P.vy = JUMP_V * 0.92; P.ground = false; b.wob = 1; sfx("bounce"); dust(P.x, P.y, 5, { .6, 1, .8 })
            elseif not b.pop_t then
                if b.letter then b.pop_t = 0 else pop_chain(b) end
            end
        end
    end
    if b.life <= 0 and not b.pop_t then
        if b.enemy then local e = b.enemy; e.state = "walk"; e.angry = true; e.x, e.y = b.x, b.y - 0.6; e.ground = false; e.vy = 2 end
        pop_fx(b, b.letter and LCOL[b.letter] or nil); b.live = false; b.enemy = nil; b.root:set_position(HIDE); return
    end
    -- draw
    b.wob = damp(b.wob, 0, 6, dt)
    local warn = b.life < 2 and (b.life * 8) % 2 < 1
    local w = sin(b.ph * 5) * 0.03 + b.wob * 0.15 * sin(b.ph * 30)
    local r = b.r
    b.root:set_position(vec3(b.x, b.y, 0.2)); b.root:set_scale(vec3(r * (1 + w), r * (1 - w), r))
    b.band:set_rotation(vec3(0, b.ph * 70, 0)); b.hl:set_scale(warn and vec3(0.01, 0.01, 0.01) or vec3(1, 1, 1))
    if b.enemy then
        local e = b.enemy; e.x, e.y = b.x, b.y - 0.55
        anim_enemy(e, dt, vec3(b.x, b.y - 0.5, 0), 0.72, nil)
        local m = e.angry and e.slot.ma or e.slot.m
        m.root:set_rotation(vec3(sin(b.ph * 2) * 15, b.ph * 60, sin(b.ph * 1.3) * 20))
    end
end
local function update_bubbles(dt)
    for _, b in ipairs(BUBS) do if b.live then update_bubble(b, dt) end end
    for _, b in ipairs(LBUBS) do if b.live then update_bubble(b, dt) end end
end

------------------------------------------------------------------ Baron von Blubba (hurry-up hunter)
local BARON = { on = false, x = 0, y = 30, t = 0, spd = 2.5 }
local function build_baron()
    BARON.m = make_model("baron")
    BARON.smoke = new_emitter({ c0 = vec4(.9, .9, 1.1, .5), c1 = vec4(.4, .3, .6, 0), count = 250, radius = 0.9, smin = 0.08, smax = 0.22, lmin = 0.5, lmax = 1.0, noise = 1.2, drag = 1.5 })
end
local function baron_spawn()
    BARON.on = true; BARON.leaving = false; BARON.x, BARON.y = 0, 28; BARON.t = 0; BARON.spd = 2.6
    sfx("baron"); show_banner("Baron von Blubba!", "Run!", 2.0, { 1, .5, .5 })
end
local function update_baron(dt)
    local B = BARON
    if not B.on then B.m.root:set_position(HIDE); emitter_at(B.smoke, 0, -1000, 0, 0); set_point(L.baron, HIDE, vec3(1, 1, 1), 0, 1); return end
    B.t = B.t + dt
    if B.leaving then B.y = B.y + 9 * dt; if B.y > 32 then B.on = false end
    else
        B.spd = min(7.5, B.spd + dt * 0.12)
        local tx, ty = P.x, P.y + 0.6
        local dx, dy = tx - B.x, ty - B.y; local d = sqrt(dx * dx + dy * dy) + 1e-4
        B.x = B.x + dx / d * B.spd * dt; B.y = B.y + dy / d * B.spd * dt
        if P.alive and P.inv <= 0 and d < 1.6 then G.player_die() end
    end
    local face = (P.x > B.x) and 20 or 160
    B.yaw = damp(B.yaw or 90, face, 5, dt)
    B.m.root:set_position(vec3(B.x, B.y - 1 + sin(B.t * 3) * 0.2, 0.6)); B.m.root:set_rotation(vec3(0, B.yaw, sin(B.t * 2) * 8))
    local s = 0.95 + sin(B.t * 6) * 0.04; B.m.root:set_scale(vec3(s, s, s))
    emitter_at(B.smoke, B.x, B.y, -0.2, 22)
    set_point(L.baron, vec3(B.x, B.y, 3), vec3(1, 0.3, 0.3), 25 + 10 * sin(B.t * 8), 9)
end

------------------------------------------------------------------ per-frame enemies
local function update_enemies(dt, active)
    for i = #ENEMIES, 1, -1 do
        local e = ENEMIES[i]
        if e then
            e.t = e.t + dt
            if e.state == "enter" then
                e.delay = e.delay - dt
                if e.delay <= 0 then
                    e.y = e.y - 9 * dt
                    if e.y <= e.ty then e.y = e.ty; e.state = "walk"; e.ground = e.kind == "zen" and ground_at(e.x, e.hw, e.y) ~= nil end
                end
                anim_enemy(e, dt, vec3(e.x, e.delay > 0 and -1000 or e.y, 0), 1, nil)
            elseif e.state == "walk" then
                if active then ai_enemy(e, dt) end
                anim_enemy(e, dt, vec3(e.x, e.y, 0), 1.12, nil)
                if P.alive and P.inv <= 0 and abs(P.x - e.x) < 0.8 and abs((P.y + 0.8) - (e.y + 0.65)) < 1.1 then G.player_die() end
            elseif e.state == "dead" then
                e.vy = max(FALL_MAX, e.vy - GRAV * 0.7 * dt)
                local yo = e.y
                e.x = e.x + e.vx * dt; e.y = e.y + e.vy * dt
                if e.x < XMIN + 0.5 then e.x = XMIN + 0.5; e.vx = abs(e.vx) elseif e.x > XMAX - 0.5 then e.x = XMAX - 0.5; e.vx = -abs(e.vx) end
                if e.y < -1.8 then e.y = 26.3 end
                if e.y > 24 then e.vy = -abs(e.vy) end
                if rand() < 0.6 then burst(e.x, e.y + 0.5, { c0 = vec4(2, 1.8, 1, 1), c1 = vec4(1, .5, .9, 0), count = 2, smin = .04, smax = .09, lmin = .2, lmax = .4, radius = .2, spread = 2, drag = 2 }) end
                local top = e.vy < 0 and e.t > 0.7 and land_check(e.x, 0.3, yo, e.y)
                anim_enemy(e, dt, vec3(e.x, e.y, 0), 1, e.t * 720)
                if top then
                    spawn_fruit(e.x, top, min(3, (e.chain or 1) - 1)); star_burst((e.chain or 1) % 5, e.x, top + 0.5, 3, 0.6)
                    despawn(e)
                end
            end
        end
    end
end

------------------------------------------------------------------ player update
local function player_die()
    if not P.alive or P.inv > 0 then return end
    P.alive = false; P.dead_t = 0; sfx("death"); add_shake(0.6)
    star_burst(1, P.x, P.y + 0.8, 10, 1.2); flash(P.x, P.y + 1, { .5, 1, .6 }, 80, 0.6, 9)
    burst(P.x, P.y + 0.8, { c0 = vec4(1.5, 2.5, 1.5, 1), c1 = vec4(.2, .8, .3, 0), count = 60, smin = .05, smax = .14, lmin = .3, lmax = .8, radius = .4, spread = 14, drag = 2.5 })
end
G.player_die = player_die
local function update_player(dt, ctl)
    P.blow_t = P.blow_t + dt
    if not P.alive then
        P.dead_t = P.dead_t + dt; P.vy = P.vy - 0 * dt
        P.y = P.y + (P.dead_t < 0.4 and 3 or -1) * dt
        emitter_at(P.trail, 0, -1000, 0, 0); set_point(L.player, HIDE, vec3(1, 1, 1), 0, 1)
        P.visible = P.dead_t < 1.4
        anim_dragon(dt); return
    end
    P.visible = true
    P.inv = max(0, P.inv - dt); P.cool = P.cool - dt
    P.jump_held = ctl.jump_held
    local spd = 7.2
    local target = ctl.h * spd
    P.vx = damp(P.vx, target, P.ground and 18 or 9, dt)
    if ctl.h ~= 0 then P.face = ctl.h end
    if ctl.jump and P.ground then P.vy = JUMP_V; P.ground = false; P.squash = -0.6; sfx("jump"); dust(P.x, P.y, 6) end
    if not ctl.jump_held and P.vy > 6 then P.vy = P.vy - GRAV * 0.9 * dt end   -- short hop when jump is released early
    if ctl.fire and P.cool <= 0 then if blow_bubble() then P.cool = 0.24; P.blow_t = 0 end end
    if step_body(P, dt, 1) then P.squash = 0.7; sfx("land"); dust(P.x, P.y, 6) end
    anim_dragon(dt)
    emitter_at(P.trail, P.x, P.y + 0.7, -0.3, P.ground and 0 or 25)
    set_point(L.player, vec3(P.x + P.face * 0.6, P.y + 1.2, 2.5), vec3(0.6, 1.0, 0.7), 12, 6)
end

------------------------------------------------------------------ camera
local shake_t = 0
local function update_camera(dt)
    shake = max(0, shake - dt * 2.2); shake_t = shake_t + dt
    local a = shake * shake * 0.6 * SET:shake_scale()
    local ox, oy = a * (sin(shake_t * 53) + 0.5 * sin(shake_t * 97)), a * (cos(shake_t * 61) + 0.5 * sin(shake_t * 83))
    if G.cam_ov then local o = G.cam_ov; cam:set_position(vec3(o[1], o[2], o[3])); cam:look_at(vec3(o[4], o[5], 0)); return end
    cam:set_position(vec3(ox, CAMY + oy, CAMZ)); cam:look_at(vec3(ox, CAMY + oy, 0))
end

------------------------------------------------------------------ levels + flow
local LV = { cur = 0, t = 0, hurry = false, clear_t = nil, tr = nil }
local function lv_index(n) return (n - 1) % #LEVELS + 1 end
local function place_level(i, off)
    for j, n in ipairs(LVN) do
        if j ~= i then if not (LV.tr and j == LV.tr.from) then n.blk:set_position(HIDE); n.trim:set_position(HIDE) end end
    end
    LVN[i].blk:set_position(vec3(0, off, 0)); LVN[i].trim:set_position(vec3(0, off, 0))
end
local function tint_accent(i) local c = LEVELS[i].col; L.accent_col = c end
local function clear_actors()
    for i = #ENEMIES, 1, -1 do despawn(ENEMIES[i]) end
    for _, b in ipairs(BUBS) do b.live = false; b.enemy = nil; b.root:set_position(HIDE) end
    for _, b in ipairs(LBUBS) do b.live = false; b.root:set_position(HIDE) end
    for _, f in ipairs(FRUITS) do f.live = false; f.root:set_position(HIDE) end
    BARON.on = false
end
local function populate(n)
    local lv = LEVELS[lv_index(n)]
    for k, kind in ipairs(lv.enemies) do
        local sp = lv.spawn[(k - 1) % #lv.spawn + 1]
        spawn_enemy(kind, sp[1], sp[2], 0.15 * k)
    end
    if n > #LEVELS then for _ = 1, min(3, floor((n - 1) / #LEVELS)) do spawn_enemy("zen", rr(-8, 8), 22, 1) end end
end
local function start_level(n)
    level_no = n; LV.cur = lv_index(n); LV.t = 0; LV.hurry = false; LV.clear_t = nil
    set_solids(LEVELS[LV.cur]); place_level(LV.cur, 0); tint_accent(LV.cur)
    P.x, P.y, P.vx, P.vy, P.ground, P.face = START_X, START_Y, 0, 0, true, 1
    populate(n); letter_t = rr(8, 12)
    show_banner("Round " .. n, LEVELS[LV.cur].name, 2.2); sfx("level")
end
local function begin_transition()
    local from = LV.cur
    clear_actors()
    LV.tr = { t = 0, from = from, to = lv_index(level_no + 1), px = P.x, py = P.y }
    G.state = G.state == "title" and "title" or "next"
    LV.tr.bub = BUBS[1]
end
local function update_transition(dt)
    local T = LV.tr
    T.t = T.t + dt
    local k = clamp(T.t / 2.2, 0, 1); local e = k * k * (3 - 2 * k)
    LVN[T.from].blk:set_position(vec3(0, e * 28, 0)); LVN[T.from].trim:set_position(vec3(0, e * 28, 0))
    LVN[T.to].blk:set_position(vec3(0, (e - 1) * 28, 0)); LVN[T.to].trim:set_position(vec3(0, (e - 1) * 28, 0))
    -- Bub floats to the start point inside a bubble, as in the arcade
    P.x = lerp(T.px, START_X, e); P.y = lerp(T.py, START_Y + 0.2, e) + sin(k * PI) * 3; P.face = 1; P.ground = false; P.alive = true; P.inv = 0
    P.vx, P.vy = 0, 0; P.blow_t = 9
    anim_dragon(dt)
    local b = T.bub
    b.root:set_position(vec3(P.x, P.y + 0.8, 0.2)); b.root:set_scale(vec3(1.25, 1.25, 1.25)); b.band:set_rotation(vec3(0, G.t * 70, 0))
    set_point(L.player, vec3(P.x, P.y + 1, 2.5), vec3(0.6, 1.0, 0.7), 14, 7)
    if T.t >= 2.4 then
        b.root:set_position(HIDE); pop_fx({ x = P.x, y = P.y + 0.8, r = 1.2 })
        local wasT = G.state == "title"
        LV.tr = nil; LVN[T.from].blk:set_position(HIDE); LVN[T.from].trim:set_position(HIDE)
        start_level(level_no + 1); P.ground = false
        if not wasT then G.state = "play" end
    end
end
local function update_level(dt, st)
    if LV.tr then update_transition(dt); return end
    LV.t = LV.t + dt
    if st == "play" then
        if not LV.hurry and LV.t > 32 and enemies_left() > 0 then
            LV.hurry = true; sfx("hurry"); show_banner("Hurry Up!", "", 1.8, { 1, .55, .4 })
            for _, e in ipairs(ENEMIES) do e.angry = true end
        end
        if LV.t > 42 and not BARON.on and enemies_left() > 0 then baron_spawn() end
        letter_t = letter_t - dt
        if letter_t <= 0 then letter_t = rr(11, 16); spawn_letter() end
    end
    if enemies_left() == 0 and #ENEMIES == 0 then
        if BARON.on then BARON.leaving = true end
        LV.clear_t = (LV.clear_t or 0) + dt
        if LV.clear_t > (st == "play" and 4.5 or 2.5) then begin_transition() end
    end
end

------------------------------------------------------------------ HUD + menus (runtime_ui, pixel coords)
local UI = "hud"
runtime_ui.show(UI); pcall(runtime_ui.set_screen_overlay, UI, true)
local NONE = { 0, 0, 0, 0 }
local hc = {}
local US = SH / 1080
local function quad(id, o)
    local key = ""
    for _, k in ipairs({ "x", "y", "w", "h", "label", "visible", "font_scale" }) do key = key .. tostring(o[k]) .. "|" end
    if o.fill then key = key .. o.fill[1] .. o.fill[2] .. o.fill[3] .. o.fill[4] end
    if o.text_color then key = key .. o.text_color[1] .. o.text_color[4] end
    if hc[id] == key then return end
    hc[id] = key
    pcall(runtime_ui.set_quad, UI, id, o)
end
local function text(id, label, x, y, w, h, fs, col, align, vis)
    quad(id, { x = floor(x), y = floor(y), w = floor(w), h = floor(h), z = 10, style = "text", label = label, fill = NONE, border = NONE, text_color = col,
        font_scale = fs * US, align_h = align or "center", align_v = "middle", no_input = true, visible = vis ~= false })
end
local function panel(id, x, y, w, h, vis, a, border)
    quad(id, { x = x, y = y, w = w, h = h, z = 4, style = "text", label = "", fill = { 0.03, 0.04, 0.09, a or 0.55 },
        border = border or { 0.45, 0.95, 0.65, 0.5 }, corner_radius = 14 * US, no_input = true, visible = vis ~= false })
end
local function button(id, label, cx, cy, vis)
    local w, h = 340 * US, 62 * US
    local st = vis and select(2, pcall(runtime_ui.get_state, UI, id))
    local hov = type(st) == "table" and st.hovered
    quad(id, { x = cx - w / 2, y = cy - h / 2, w = w, h = h, z = 12, style = "text", label = label,
        fill = hov and { 0.12, 0.35, 0.22, 0.95 } or { 0.04, 0.07, 0.12, 0.88 }, border = hov and { 0.6, 1, 0.75, 1 } or { 0.4, 0.85, 0.6, 0.9 },
        text_color = hov and { 1, 1, 1, 1 } or { 0.88, 0.95, 0.92, 1 }, font_scale = 1.25 * US, align_h = "center", align_v = "middle",
        corner_radius = 16 * US, visible = vis })
    return vis and type(st) == "table" and st.clicked
end
local function fmt(n) local s = tostring(floor(n)); return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end
local AC, AC2, DIM = { .55, 1, .7, 1 }, { 1, .6, .88, 1 }, { 0.78, 0.82, 0.88, 1 }
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause" or st == "over" or st == "next") and not set_open
    local lx0 = to_screen(-16, 0)
    local sidew = lx0 - 30 * US
    local pw = min(300 * US, sidew)
    local px = (lx0 - pw) / 2
    panel("hud_l", px, 90 * US, pw, 330 * US, play, 0.5)
    text("sc_l", "Score", px, 104 * US, pw, 34 * US, 1.0, DIM, "center", play)
    text("score", fmt(score), px, 136 * US, pw, 56 * US, 2.0, AC, "center", play)
    text("hi", "Best " .. fmt(max(hiscore, score)), px, 196 * US, pw, 34 * US, 1.0, DIM, "center", play)
    text("lvl", "Round " .. level_no, px, 250 * US, pw, 46 * US, 1.5, AC2, "center", play)
    text("lives", "Lives " .. lives, px, 305 * US, pw, 46 * US, 1.4, { 1, .9, .6, 1 }, "center", play)
    text("timer", LV.hurry and "Hurry!" or "", px, 352 * US, pw, 40 * US, 1.2, { 1, .5, .4, 1 }, "center", play and LV.hurry)
    local rx = SW - px - pw
    panel("hud_r", rx, 90 * US, pw, 560 * US, play, 0.5, { 1, .6, .85, .5 })
    text("ext_t", "Extend", rx, 104 * US, pw, 40 * US, 1.2, DIM, "center", play)
    for i = 1, 6 do
        local c = LCOL[i]; local got = GOT[i]
        local sz = 66 * US; local cx = rx + pw / 2 - sz / 2; local cy = 150 * US + (i - 1) * 80 * US
        quad("ext_b" .. i, { x = cx, y = cy, w = sz, h = sz, z = 6, style = "text", label = LETTERS[i],
            fill = got and { c[1] * .7, c[2] * .7, c[3] * .7, 0.95 } or { 0.05, 0.06, 0.1, 0.7 }, border = { c[1], c[2], c[3], got and 1 or 0.45 },
            text_color = got and { 1, 1, 1, 1 } or { c[1] * .6, c[2] * .6, c[3] * .6, 1 }, font_scale = 1.6 * US, align_h = "center", align_v = "middle",
            corner_radius = sz / 2, no_input = true, visible = play })
    end
    -- letters on letter bubbles
    for i, b in ipairs(LBUBS) do
        local vis = b.live and not set_open and (st == "play" or st == "pause")
        local sx_, sy_ = 0, 0
        if vis then sx_, sy_ = to_screen(b.x, b.y) end
        local c = LCOL[i]
        text("lb" .. i, LETTERS[i], sx_ - 40 * US, sy_ - 40 * US, 80 * US, 80 * US, 2.2, { min(1, c[1] + .5), min(1, c[2] + .5), min(1, c[3] + .5), 1 }, "center", vis)
    end
    for i, p in ipairs(POP) do
        p.t = p.t + dt
        local vis = (st == "play" or st == "next") and not set_open and p.t < 1.1
        local qx, qy = 0, 0
        if vis then qx, qy = to_screen(p.x, p.y + p.t * 1.2) end
        local a = floor(clamp((1.1 - p.t) / 0.4, 0, 1) * 10) / 10
        text("pop" .. i, p.txt or "", qx - 200 * US, qy - 20 * US, 400 * US, 40 * US, 1.1, { p.col and p.col[1] or 1, p.col and p.col[2] or 1, p.col and p.col[3] or 1, a }, "center", vis)
    end
    banner.t = banner.t - dt
    local ba = floor(clamp(banner.t / 0.4, 0, 1) * 20) / 20
    local bvis = (st == "play" or st == "next") and not set_open and banner.t > 0
    text("ban", banner.text, 0, SH * 0.36, SW, 90 * US, 2.8, { banner.col[1], banner.col[2], banner.col[3], ba }, "center", bvis)
    text("bans", banner.sub, 0, SH * 0.36 + 80 * US, SW, 44 * US, 1.3, { .85, .95, 1, ba }, "center", bvis)
    local title = st == "title" and not set_open
    panel("t_bg", SW / 2 - 480 * US, SH * 0.1, 960 * US, SH * 0.76, title, 0.62)
    text("t_title", "Bubble Bobble Remix", 0, SH * 0.13, SW, 130 * US, 4.2, { .55, 1, .7, 1 }, "center", title)
    text("t_sub", "Trap the monsters in bubbles, then pop them!", 0, SH * 0.13 + 115 * US, SW, 40 * US, 1.15, { 1, .7, .9, 1 }, "center", title)
    text("t_ctl1", "Move: A / D or arrows   ·   Jump: W, Up or Space   ·   Blow bubble: J, X or Ctrl", 0, SH * 0.68, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_ctl2", "Hold jump to bounce on bubbles   ·   P / Esc: pause   ·   O: settings   ·   M: mute", 0, SH * 0.68 + 34 * US, SW, 34 * US, 0.95, DIM, "center", title)
    text("t_hi", "Best score " .. fmt(hiscore), 0, SH * 0.68 + 80 * US, SW, 36 * US, 1.1, AC2, "center", title)
    local pause = st == "pause" and not set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.28, 600 * US, SH * 0.44, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.3, SW, 80 * US, 2.6, AC, "center", pause)
    local over = st == "over" and not set_open
    panel("o_bg", SW / 2 - 360 * US, SH * 0.26, 720 * US, SH * 0.5, over, 0.75, { 1, .5, .6, .6 })
    text("o_t", "Game Over", 0, SH * 0.28, SW, 90 * US, 3.0, { 1, .55, .65, 1 }, "center", over)
    text("o_s", "Score " .. fmt(score) .. "  ·  Round " .. level_no, 0, SH * 0.28 + 90 * US, SW, 40 * US, 1.3, DIM, "center", over)
    local c = {}
    c.start = button("b_start", "Start (Enter)", SW / 2, SH * 0.42, title)
    c.set_t = button("b_set_t", "Settings (O)", SW / 2, SH * 0.42 + 78 * US, title)
    c.quit_app = button("b_quit_app", "Quit Game", SW / 2, SH * 0.42 + 156 * US, title)
    c.resume = button("b_resume", "Resume (P)", SW / 2, SH * 0.44, pause)
    c.set_p = button("b_set_p", "Settings (O)", SW / 2, SH * 0.44 + 78 * US, pause)
    c.quit = button("b_quit", "Quit to Title (Q)", SW / 2, SH * 0.44 + 156 * US, pause)
    local ov = over and (G.over_t or 0) > 1.0
    c.again = button("b_again", "Play Again (Enter)", SW / 2, SH * 0.5, ov)
    c.title = button("b_title", "Title (Esc)", SW / 2, SH * 0.5 + 78 * US, ov)
    return c
end

------------------------------------------------------------------ game flow
local function new_game()
    clear_actors(); LV.tr = nil
    score, lives, next_extra = 0, 3, 30000
    for i = 1, 6 do GOT[i] = false end
    P.alive = true; P.inv = 2.0; P.dead_t = 0
    G.state = "play"
    start_level(1); sfx("start")
end
local function to_title()
    clear_actors(); LV.tr = nil
    P.alive = true; P.inv = 0
    G.state = "title"
    start_level(1); banner.t = 0
end
local _die = player_die
G.player_die = function() if G.state == "play" then _die() end end
local function respawn()
    P.alive = true; P.inv = 2.5; P.x, P.y, P.vx, P.vy, P.ground, P.face = START_X, START_Y, 0, 0, true, 1
    BARON.on = false; LV.t = min(LV.t, 18); LV.hurry = false
    for _, e in ipairs(ENEMIES) do e.angry = false end
    pop_fx({ x = P.x, y = P.y + 0.8, r = 1.1 })
end
local function update(dt)
    flush_mats()
    dt = min(dt, 1 / 20)
    G.t = G.t + dt; G.dt = dt
    local k = { ret = edge("Return"), space = edge("Space"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), q = edge("Q"),
        up = edge("Up"), w = edge("W"), j = edge("J"), x = edge("X"), lc = edge("LeftCtrl") }
    set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if set_open then for kk in pairs(k) do k[kk] = false end end
    local function open_settings() sfx("click"); SET:open(); set_open = true end
    if k.m then SET:toggle_mute() end
    local consumed = false
    if st == "title" then
        if k.ret or k.space or c.start then sfx("click"); new_game(); consumed = true
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "play" or st == "next" then
        if k.p or k.esc then G.prev_state = st; G.state = "pause"; sfx("click") end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = G.prev_state or "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.q or c.quit then to_title() end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.0 then
            if k.ret or k.space or c.again then sfx("click"); new_game(); consumed = true
            elseif k.esc or c.title then to_title() end
        end
    end
    st = G.state
    local running = (st == "play" or st == "title" or st == "over" or st == "next") and not (set_open and st ~= "title")
    if running then
        if LV.tr then update_level(dt, st)
        else
            local ctl = { h = 0, jump = false, jump_held = false, fire = false }
            if st == "play" then
                ctl.h = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0)
                ctl.jump_held = any("Space", "W", "Up", "K")
                ctl.jump = ((k.space or k.w or k.up or edge("K")) and not consumed) or (ctl.jump_held and P.ground and (P.jbuf or 0) > 0)
                local fh = any("J", "X", "LeftCtrl", "RightCtrl", "F")
                ctl.fire = k.j or k.x or k.lc or (fh and P.cool <= -0.06)
                -- jump buffer: a press shortly before landing still jumps
                if k.space or k.w or k.up then P.jbuf = 0.12 else P.jbuf = (P.jbuf or 0) - dt end
            end
            update_player(dt, ctl)
            update_enemies(dt, true)
            update_bubbles(dt)
            update_fruit(dt)
            update_baron(dt)
            if st ~= "over" then update_level(dt, st) end
            if not P.alive and st == "play" and P.dead_t > 1.8 then
                lives = lives - 1
                if lives <= 0 then
                    G.state = "over"; G.over_t = 0; sfx("gameover"); BARON.leaving = true
                    if score > hiscore then hiscore = score; save_hi() end
                else respawn() end
            end
        end
    end
    local ac = L.accent_col or { 1, .5, .8 }
    set_point(L.accent, vec3(0, 13, 7), vec3(ac[1], ac[2], ac[3]), 45 + 8 * sin(G.t * 1.5), 30)
    update_camera(dt)
    update_world(dt)
    update_stars(dt); update_rings(dt); update_flashes(dt)
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_world()
build_stars(); build_rings()
build_player(); build_enemies(); build_bubbles(); build_fruit(); build_baron()
to_title()
G.P = P; G.new_game = new_game; G.to_title = to_title; G.ENEMIES = ENEMIES; G.BUBS = BUBS; G.LBUBS = LBUBS; G.SET = SET
G.blow = blow_bubble; G.spawn_letter = spawn_letter; G.baron = baron_spawn; G.kill = kill_enemy; G.LV = LV; G.GOT = GOT; G.pop_chain = pop_chain
G.state_set = function(s) G.state = s; G.over_t = 5 end
G.info = function() return score, lives, level_no end
G.begin_transition = begin_transition; G.start_level = function(n) clear_actors(); start_level(n) end
hooks { update = update }
pe_log("[BB] ready  camz " .. floor(CAMZ))
