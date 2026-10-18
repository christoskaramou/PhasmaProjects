-- ARKANOID REMIX  (PhasmaEngine, Lua)
-- A faithful modern remake of Taito's Arkanoid (1986): steer the Vaus, keep the energy ball in play and clear 32
-- rounds of bricks, then face DOH in round 33. Capsules: S slow, C catch, L laser, E enlarge, D disruption, B break, P extra Vaus.
-- Logic coords: x across (-6.5..6.5 inside the walls), y up the field (0 bottom .. 15 top wall). WP maps to world.
local PI = math.pi
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
math.randomseed(os and os.time and os.time() or 1942)
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local G = { state = "boot", t = 0 }
_G.AK = G

------------------------------------------------------------------ deferred materials (engine quirk: replay writes)
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
local function paint(n, base, emis, rough, metal)
    if not n then return end
    mset(n, "base_color", vec4(base[1], base[2], base[3], 1))
    mset(n, "emissive", vec3(emis[1], emis[2], emis[3]))
    mset(n, "roughness", rough or 0.4)
    mset(n, "metallic", metal or 0.0)
end
local function sfx(name) pcall(audio.play, name .. ".wav") end
G.music_cur = nil
local function music(name)
    if G.music_cur == name then return end
    G.music_cur = name
    pcall(audio.stop_music)
    if name then pcall(audio.play_music, name .. ".wav") end
end

------------------------------------------------------------------ render setup (see /workspace/games/common/RENDER_SETTINGS.md)
local function S(k, v) pcall(settings.set, k, v) end
local ss = scene.add_empty_node("ArkanoidSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "night.hdr")
S("hdr", false); S("taa", true); S("cas_sharpening", false); S("motion_blur", false); S("fxaa", false); S("dof", false)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.2)
S("tonemapping", true); S("ssao", false); S("ssr", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0); S("IBL", false)
S("color_grading", true); S("color_grading_saturation", 1.05); S("color_grading_contrast", 1.04)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "SETTINGS", subtitle = "Arkanoid Remix", file = "Save/settings.cfg", music = true,
    click = function() sfx("click") end, defaults = { master = 0.5 },
    theme = { accent = { 0.35, 0.75, 1, 1 }, accent2 = { 1, 0.55, 0.3, 1 }, text = { 0.86, 0.84, 0.8, 1 }, selected_text = { 1, 0.97, 0.9, 1 } } })
SET:apply()
G.set_open = false

------------------------------------------------------------------ camera
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1600, surf.height or 900
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local VFOV = math.rad(40)
local FOVX = 2 * math.atan(math.tan(VFOV / 2) * SW / SH)
pcall(function() cam:set_fov(math.deg(FOVX)) end)
pcall(function() cam:set_far_plane(300) end)
local FW, FH = 13, 15
local function WP(x, y, h) return vec3(-x, h or 0, y) end
G.cam = { pos = vec3(0, 18.5, -1.8), look = vec3(0, 0, 7.1) }
local function project(p)
    local c, l = G.cam.pos, G.cam.look
    local fx, fy, fz = l.x - c.x, l.y - c.y, l.z - c.z
    local fl = sqrt(fx * fx + fy * fy + fz * fz); fx, fy, fz = fx / fl, fy / fl, fz / fl
    local rx, rz = -fz, fx; local rl = sqrt(rx * rx + rz * rz); rx, rz = rx / rl, rz / rl
    local ux, uy, uz = -rz * fy, rz * fx - rx * fz, rx * fy
    local dx, dy, dz = p.x - c.x, p.y - c.y, p.z - c.z
    local zc = dx * fx + dy * fy + dz * fz
    if zc < 0.1 then return -9999, -9999 end
    local th = math.tan(VFOV / 2)
    return SW / 2 + (dx * rx + dz * rz) / (zc * th) * SH / 2, SH / 2 - (dx * ux + dy * uy + dz * uz) / (zc * th) * SH / 2
end
------------------------------------------------------------------ templates -> clones
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[AK] missing template " .. name); return nil end
    TPL[name] = { node = n, mesh = n:get_mesh_refs()[1] }
    return TPL[name]
end
local seq = 0
local HIDE = vec3(0, -1000, 0)
local function clone(name, pos, scale, parent)
    local t = tpl("T_" .. name); seq = seq + 1
    local n = scene.add_empty_node(name .. "_c" .. seq)
    if t and t.mesh then n:add_mesh_ref(t.mesh) end
    if parent then n:set_parent(parent) end
    n:set_position(pos or HIDE)
    if scale then n:set_scale(scale) end
    return n
end
local function empty(name, parent, pos)
    seq = seq + 1
    local n = scene.add_empty_node(name .. "_e" .. seq)
    if parent then n:set_parent(parent) end
    n:set_position(pos or vec3(0, 0, 0))
    return n
end
local function prim(kind, pos, scale)
    seq = seq + 1
    local n = scene.add_empty_node(kind .. "_p" .. seq)
    scene.attach_primitive(n, kind)
    n:set_position(pos); n:set_scale(scale)
    return n
end
local function tnode(name) local t = tpl("T_" .. name); return t and t.node end
-- pools for stage geometry and props: P_get(kind) hands out clones, P_end(kind) hides the rest
local POOL = {}
local function P_begin(kind) local p = POOL[kind]; if not p then p = { n = {}, used = 0 }; POOL[kind] = p end; p.used = 0 end
local function P_get(kind)
    local p = POOL[kind]; if not p then P_begin(kind); p = POOL[kind] end
    p.used = p.used + 1
    local n = p.n[p.used]
    if not n then n = clone(kind); p.n[p.used] = n end
    return n
end
local function P_end(kind) local p = POOL[kind]; if not p then return end; for i = p.used + 1, #p.n do p.n[i]:set_position(HIDE) end end

------------------------------------------------------------------ lights
local LIGHT_GAIN = 0.12
local LNODE = {}
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
------------------------------------------------------------------ input
local prev = {}
local keyfn = input.is_key_down_raw or input.is_key_pressed
local function held(k) if G.vk and G.vk[k] then return true end local ok, v = pcall(keyfn, k); return ok and v end
local function edge(k) local d = held(k); local p = prev[k]; prev[k] = d; return d and not p end
local function any(...) for _, k in ipairs({ ... }) do if held(k) then return true end end; return false end

local FR = 1 / 60
local AL = 1
------------------------------------------------------------------ palette {base, emissive, rough, metal}
local BRICK = { W = { .92, .92, .9 }, O = { 1, .5, .12 }, C = { .2, .8, .95 }, G = { .2, .8, .3 }, R = { .9, .15, .12 },
    B = { .15, .3, .95 }, P = { .95, .3, .75 }, Y = { 1, .85, .15 }, S = { .8, .8, .85 }, X = { 1, .78, .3 } }
G.BRICK = BRICK
local CAPC = { S = { 1, .5, .1 }, C = { .2, .8, .3 }, L = { .9, .15, .12 }, E = { .15, .35, .95 }, D = { .2, .8, .95 }, B = { .95, .3, .75 }, P = { .7, .7, .75 } }
G.CAPC = CAPC
local PAL = {
    vaus_mid = { { .8, .82, .88 }, { .05, .05, .06 }, .3, .45 }, vaus_strip = { { .15, .4, .9 }, { .05, .12, .3 }, .3, .4 },
    vaus_cap = { { .85, .12, .1 }, { .05, 0, 0 }, .3, .5 }, vaus_gun = { { .6, .62, .68 }, { .03, .03, .03 }, .35, .45 },
    ball = { { .95, .95, 1 }, { .45, .45, .5 }, .25, .3 }, shadow = { { .01, .01, .02 }, { 0, 0, 0 }, 1 },
    wall_side = { { .7, .72, .78 }, { .03, .03, .04 }, .3, .5 }, wall_top = { { .7, .72, .78 }, { .03, .03, .04 }, .3, .5 },
    wall_ring = { { .3, .32, .38 }, { 0, 0, 0 }, .35, .9 }, wall_elbow = { { .7, .72, .78 }, { .03, .03, .04 }, .3, .5 }, elbow_collar = { { .3, .32, .38 }, { 0, 0, 0 }, .35, .9 }, corner = { { .45, .47, .55 }, { 0, 0, 0 }, .3, .9 },
    gate = { { .4, .42, .5 }, { 0, 0, 0 }, .35, .8 }, gate_door = { { .15, .16, .2 }, { 0, 0, 0 }, .4, .6 },
    warp = { { .9, .4, .8 }, { .5, .2, .45 }, .3, .2 }, floor = { { .62, .62, .66 }, { 0, 0, 0 }, .85 },
    en_cone = { { .25, .55, .95 }, { .02, .05, .1 }, .3, .6 }, en_pyr = { { .3, .85, .35 }, { .02, .08, .02 }, .35, .3 },
    en_orb = { { .9, .25, .2 }, { .08, .02, .02 }, .25, .4 }, en_cube = { { .95, .75, .2 }, { .08, .06, .01 }, .3, .6 },
    debris = { { .8, .8, .8 }, { 0, 0, 0 }, .5, .2 }, laser = { { 1, .5, .3 }, { 1.2, .45, .2 }, .4 },
    doh_head = { { .55, .45, .32 }, { 0, 0, 0 }, .85, 0 }, doh_brow = { { .5, .4, .28 }, { 0, 0, 0 }, .85 },
    doh_nose = { { .58, .48, .34 }, { 0, 0, 0 }, .85 }, doh_eye = { { .05, .03, .02 }, { .5, .12, .05 }, .5 },
    doh_mouth = { { .05, .03, .02 }, { 0, 0, 0 }, .6 }, doh_shot = { { .9, .3, .2 }, { .9, .25, .1 }, .4 },
}
for k, c in pairs(BRICK) do PAL["brick_" .. k] = { c, (k == "S" or k == "X") and { c[1] * .12, c[2] * .1, c[3] * .08 } or { 0, 0, 0 }, (k == "S" or k == "X") and .28 or .42, (k == "S" or k == "X") and .45 or .05 } end
for k, c in pairs(CAPC) do PAL["cap_" .. k] = { c, { c[1] * .05, c[2] * .05, c[3] * .05 }, .3, .3 }; PAL["lbl_" .. k] = { { 1, 1, 1 }, { .2, .2, .2 }, .5 } end
local function paint_templates()
    for name, v in pairs(PAL) do paint(tnode(name), v[1], v[2], v[3], v[4]) end
    mtex(tnode("brick_X"), "base_color", "Textures/gold.png")
    for k in pairs(CAPC) do mtex(tnode("lbl_" .. k), "base_color", "Textures/lbl_" .. k .. ".png") end
    for name in pairs(PAL) do local n = tnode(name); if n then n:set_position(HIDE) end end
end
G.set_bg = function(n, i) mtex(n, "base_color", "Textures/bg" .. i .. ".png") end

------------------------------------------------------------------ lights
local LT = {}
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(-0.35, -0.85, 0.4), vec3(1.0, 0.97, 0.92), 2.4)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    LT.key = addp(WP(0, 3, 6), vec3(1.0, 0.95, 0.88), 26, 22)
    LT.fill = addp(WP(0, 12, 5), vec3(0.75, 0.82, 1.0), 20, 22)
    LT.ball = addp(HIDE, vec3(0.7, 0.85, 1), 0, 3)
    LT.sheen = addp(HIDE, vec3(1, 0.95, 0.85), 0, 6)
    LT.flash = {}
    for i = 1, 4 do LT.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1 } end
end
G.flash_next = 1
local function flash(p, col, power, life, rad)
    local f = LT.flash[G.flash_next]; G.flash_next = G.flash_next % #LT.flash + 1
    f.t, f.life, f.p, f.col, f.power, f.rad = 0, life or 0.3, p, vec3(col[1], col[2], col[3]), power or 30, rad or 4
end
local function update_lights(dt, bp)
    -- a slow glint sweeps over the brick wall so gold reads as polished metal
    set_point(LT.sheen, WP(6 * sin(G.t * 0.45), 11.5 + 1.5 * sin(G.t * 0.31), 2.2), vec3(1, 0.95, 0.85), 16, 6)
    set_point(LT.ball, bp or HIDE, vec3(0.7, 0.85, 1), bp and 5 or 0, 2.5)
    for _, f in ipairs(LT.flash) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = 1 - clamp(f.t / f.life, 0, 1)
            set_point(f.idx, f.p, f.col, f.power * k * k, f.rad)
            if f.t >= f.life then set_point(f.idx, HIDE, f.col, 0, 1) end
        end
    end
end

------------------------------------------------------------------ particles
local function PS() return SET:particle_scale() end
local function burst(p, o)
    pcall(particles.emit_burst, {
        position = p, velocity = o.vel or vec3(0, 0, 0),
        color_start = o.c0, color_end = o.c1, count = max(1, floor((o.count or 30) * PS())),
        size_min = o.smin or 0.05, size_max = o.smax or 0.14, life_min = o.lmin or 0.25, life_max = o.lmax or 0.7,
        spawn_radius = o.radius or 0.3, noise_strength = o.spread or 10, drag = o.drag or 2.0,
        gravity = o.grav or vec3(0, 0, 0), cleanup_delay = 3.0,
    })
end
local function brick_burst(p, c)
    burst(p, { c0 = vec4(c[1] * 1.4, c[2] * 1.4, c[3] * 1.4, 1), c1 = vec4(c[1] * .5, c[2] * .5, c[3] * .5, 0), count = 18, smin = .04, smax = .1,
        lmin = .25, lmax = .6, radius = .3, spread = 6, drag = 2, grav = vec3(0, -6, 0) })
end
local function sparks(p, n, col)
    col = col or { 1.6, 1.4, 1.0 }
    burst(p, { c0 = vec4(col[1], col[2], col[3], 1), c1 = vec4(1, .5, .2, 0), count = n or 8, smin = .025, smax = .06, lmin = .12, lmax = .3, radius = .05, spread = 9, drag = 2.5 })
end
local function boom(p, big)
    burst(p, { c0 = vec4(2.0, 1.2, .5, 1), c1 = vec4(.5, .2, .1, 0), count = big and 80 or 26, smin = .06, smax = big and .3 or .16, lmin = .3, lmax = big and 1.4 or .7, radius = big and 1.2 or .3, spread = big and 7 or 6, drag = 1.6 })
    burst(p, { c0 = vec4(.4, .4, .42, .6), c1 = vec4(.2, .2, .22, 0), count = big and 30 or 8, smin = .15, smax = big and .5 or .25, lmin = .5, lmax = 1.2, radius = big and 1 or .2, spread = 2, drag = 2, grav = vec3(0, 1, 0) })
    flash(p, { 1, .7, .4 }, big and 80 or 25, big and 0.8 or 0.25, big and 9 or 4)
end

------------------------------------------------------------------ score state
G.score, G.hiscore = 0, 0
pcall(function() local s = fs.read("Save/arkanoid_hiscore.txt"); if s then G.hiscore = tonumber(s) or 0 end end)
local function save_hi() pcall(fs.write, "Save/arkanoid_hiscore.txt", tostring(G.hiscore)) end
local function add_score(n) G.score = G.score + n end
G.banner = { text = "", t = 0 }
function G.banner_set(t, d) G.banner.text = t; G.banner.t = d or 1.5 end
PAL.brick_X = { { 1, .8, .5 }, { .3, .19, .04 }, .2, .5 }
PAL.brick_Y = { { 1, .93, .38 }, { 0, 0, 0 }, .85, 0 }
------------------------------------------------------------------ rounds
-- 13 columns per row, top row first. W O C G R B P Y = coloured bricks (50..120 pts), S = silver (2 hits, +1 every
-- 8 rounds; 50 x round pts), X = gold (indestructible), . = empty. Rounds 1, 2, 3 and 5 follow the arcade layouts;
-- the rest are built in the same style. Round 33 is DOH.
local RAW = {
    -- 1: six full rows
    { "", "", "", "SSSSSSSSSSSSS", "RRRRRRRRRRRRR", "YYYYYYYYYYYYY", "BBBBBBBBBBBBB", "PPPPPPPPPPPPP", "GGGGGGGGGGGGG" },
    -- 2: the staircase
    { "", "", "W............", "WO...........", "WOC..........", "WOCG.........", "WOCGR........", "WOCGRB.......", "WOCGRBP......",
      "WOCGRBPY.....", "WOCGRBPYW....", "WOCGRBPYWO...", "WOCGRBPYWOC..", "WOCGRBPYWOCG.", "SSSSSSSSSSSSR" },
    -- 3: full rows between gold bars
    { "", "", "", "GGGGGGGGGGGGG", "", "WWWXXXXXXXXXX", "", "RRRRRRRRRRRRR", "", "XXXXXXXXXXWWW", "", "PPPPPPPPPPPPP", "",
      "BBBXXXXXXXXXX", "", "CCCCCCCCCCCCC", "", "XXXXXXXXXXCCC" },
    -- 4: columns of colour
    { "", "", "", ".OCGS.BPYW.OC", ".CGSB.PYWO.CG", ".GSBP.YWOC.GS", ".SBPY.WOCG.SB", ".BPYW.OCGS.BP", ".PYWO.CGSB.PY",
      ".YWOC.GSBP.YW", ".WOCG.SBPY.WO", ".OCGS.BPYW.OC", ".CGSB.PYWO.CG", ".GSBP.YWOC.GS", ".SBPY.WOCG.SB" },
    -- 5: the space invader
    { "", "", "", "...Y.....Y...", "...Y.....Y...", "....Y...Y....", "....Y...Y....", "...SSSSSSS...", "...SSSSSSS...",
      "..SSRSSSRSS..", "..SSRSSSRSS..", ".SSSSSSSSSSS.", ".SSSSSSSSSSS.", ".SSSSSSSSSSS.", ".S.SSSSSSS.S.", ".S.S.....S.S.", "....SS.SS...." },
    -- 6: gold pillars
    { "", "", "", "B.R.G.X.G.R.B", "B.R.G.X.G.R.B", "B.R.G.X.G.R.B", "B.R.G.X.G.R.B", "B.R.G.X.G.R.B", "OXOXOXOXOXOXO",
      "B.R.G.X.G.R.B", "B.R.G.X.G.R.B", "B.R.G.X.G.R.B", "B.R.G.X.G.R.B" },
    -- 7: diamond
    { "", "", "", "......Y......", ".....YPY.....", "....YPBPY....", "...YPBRBPY...", "..YPBRGRBPY..", ".YPBRGCGRBPY.",
      "YPBRGCWCGRBPY", ".YPBRGCGRBPY.", "..YPBRGRBPY..", "...YPBRBPY...", "....YPBPY....", ".....YPY.....", "......Y......" },
    -- 8: gold maze
    { "", "", "", "X.X.X.X.X.X.X", "", "X.X..W.W..X.X", "...XXXXXXX...", "X.X.......X.X", "..X.XXXXX.X..", "X.X.X.C.X.X.X",
      "..X.X...X.X..", "X.X.XXXXX.X.X", "..X.......X..", "X.XXXXXXXXX.X" },
}
-- style generators for the remaining rounds (checkerboards, castles, waves, silver walls)
local COLS = "WOCGRBPY"
local function gen(n)
    local L = { "", "", "" }
    local kind = n % 6
    for r = 1, 12 do
        local row = {}
        for c = 1, 13 do
            local ch = COLS:sub((r + c + n) % 8 + 1, (r + c + n) % 8 + 1)
            if kind == 0 then if (r + c) % 2 == 1 then ch = "." end; if r == 12 then ch = "S" end
            elseif kind == 1 then if c == 7 or r == 1 then ch = "S" end; if r > 10 and c % 3 == 1 then ch = "X" end
            elseif kind == 2 then local w = floor(3 + 2.5 * math.sin((c + n) * 0.7)); if r < w or r > w + 6 then ch = "." end
            elseif kind == 3 then if r % 4 == 0 then ch = (c % 4 == 2) and "." or "X" end; if r == 1 then ch = "S" end
            elseif kind == 4 then local d = abs(c - 7) + abs(r - 6); if d > 6 then ch = "." elseif d == 6 then ch = "S" end
            else if (c - 1) % 4 == 3 then ch = "." end; if r % 3 == 0 then ch = "S" end end
            row[c] = ch
        end
        L[#L + 1] = table.concat(row)
    end
    return L
end
local ROUNDS = {}
for n = 1, 32 do ROUNDS[n] = RAW[n] or gen(n) end
G.ROUNDS = ROUNDS
G.LAST = 33
------------------------------------------------------------------ state
local BR = 0.15                 -- ball radius
local VY = 1.0                  -- Vaus centre line
local VH = 0.2                  -- Vaus half height (collider)
local BW, BH = 1.0, 0.5         -- brick cell
local PTS = { W = 50, O = 60, C = 70, G = 80, R = 90, B = 100, P = 110, Y = 120 }
local P = { x = 0, w = 2.0, wt = 2.0, mode = nil, alive = true, guns = false }
G.P = P; G.BR, G.VY, G.VH = BR, VY, VH
G.BALLS, G.BRICKS, G.CAPS, G.SHOTS, G.EN, G.DSHOT = {}, {}, {}, {}, {}, {}
G.lives = 3
local function add_pts(n)
    local before = G.score
    add_score(n)
    local function thr(s) if s < 20000 then return 0 end; return 1 + floor((s - 20000) / 60000) end
    if thr(G.score) > thr(before) then G.lives = G.lives + 1; sfx("extra"); G.banner_set("Extra Vaus", 1.5) end
end
G.add_pts = add_pts
local function brick_xy(r, c) return -FW / 2 + (c - 0.5) * BW, FH - 0.25 - (r - 1) * BH end
G.brick_xy = brick_xy
local function load_round(n)
    G.round = n; G.BRICKS = {}; G.grid = {}
    G.CAPS, G.SHOTS, G.EN, G.DSHOT = {}, {}, {}, {}
    G.left = 0
    if n <= 32 then
        for r, row in ipairs(G.ROUNDS[n]) do
            for c = 1, #row do
                local ch = row:sub(c, c)
                if ch ~= "." and ch ~= " " then
                    local x, y = brick_xy(r, c)
                    local b = { r = r, c = c, x = x, y = y, k = ch, hp = ch == "S" and (2 + floor((n - 1) / 8)) or 1, alive = true, flash = 0 }
                    G.BRICKS[#G.BRICKS + 1] = b; G.grid[r * 100 + c] = b
                    if ch ~= "X" then G.left = G.left + 1 end
                end
            end
        end
        G.doh = nil
    else
        G.doh = { x = 0, y = 10.6, hw = 1.9, hh = 2.9, hp = 16, flash = 0, fire_t = 2.5, alive = true, t = 0 }
    end
    G.speed_lv = 0; G.hits = 0; G.top_hit = false
    G.en_t = 4; G.warp = false
    P.mode = nil; P.wt = 2.0; P.guns = false
    G.phase = "ready"; G.pt = 0
    G.banner_set(n <= 32 and ("Round " .. n) or "Round 33  ·  DOH", 2.0)
end
G.load_round = load_round
local function serve()
    P.x = 0; P.alive = true
    G.BALLS = { { x = 0, y = VY + VH + BR + 0.01, vx = 0, vy = 0, stuck = true, off = 0.35, hold = 3.0, spd = 7.0 } }
end
G.serve = serve
function G.new_game_sim()
    G.score = 0; G.lives = 3; G.won = false; G.out_of_lives = false
    load_round(1); serve()
end
local function base_speed() return 7.0 + G.speed_lv * 0.55 end
local function set_speed(b, s) local m = sqrt(b.vx * b.vx + b.vy * b.vy); if m > 1e-4 then b.vx, b.vy = b.vx / m * s, b.vy / m * s end; b.spd = s end
local function launch(b)
    b.stuck = false
    local t = clamp(b.off / (P.w / 2), -1, 1)
    local a = math.rad(t * 55 + (abs(t) < 0.05 and 25 or 0))
    b.vx, b.vy = sin(a), cos(a); set_speed(b, P.mode == "S" and 6.0 or base_speed())
    sfx("paddle")
end

------------------------------------------------------------------ capsules
local CAP_ORDER = { "S", "C", "L", "E", "D", "B", "P" }
local function drop_capsule(x, y)
    if #G.BALLS > 1 or #G.CAPS > 0 or rand() > 0.18 then return end
    local k
    repeat k = CAP_ORDER[1 + floor(rand() ^ 1.25 * 7)] until k
    if k == "P" and rand() < 0.6 then k = "E" end
    if k == "B" and rand() < 0.5 then k = "L" end
    G.CAPS[#G.CAPS + 1] = { k = k, x = x, y = y, spin = 0 }
end
local function apply_cap(k)
    sfx("capsule"); add_pts(1000)
    -- a new capsule ends the previous effect (catch releases, laser and enlarge are lost)
    for _, b in ipairs(G.BALLS) do if b.stuck and P.mode == "C" then launch(b) end end
    P.mode = nil; P.wt = 2.0; P.guns = false
    if k == "S" then P.mode = "S"; for _, b in ipairs(G.BALLS) do if not b.stuck then set_speed(b, 6.0) end end; G.speed_lv = 0
    elseif k == "C" then P.mode = "C"
    elseif k == "L" then P.mode = "L"; P.guns = true
    elseif k == "E" then P.mode = "E"; P.wt = 3.0; sfx("enlarge")
    elseif k == "D" then
        sfx("split")
        local b = G.BALLS[1]
        if b then
            if b.stuck then launch(b) end
            local a0 = math.atan2(b.vx, b.vy)
            for _, d in ipairs({ -0.45, 0.45 }) do
                local a = a0 + d
                G.BALLS[#G.BALLS + 1] = { x = b.x, y = b.y, vx = sin(a) * b.spd, vy = cos(a) * b.spd, spd = b.spd }
            end
        end
    elseif k == "B" then G.warp = true; sfx("warp"); G.banner_set("Break", 1.2)
    elseif k == "P" then G.lives = G.lives + 1; sfx("extra") end
    G.banner_set(({ S = "Slow", C = "Catch", L = "Laser", E = "Enlarge", D = "Disruption", B = "Break", P = "Extra Vaus" })[k], 1.0)
end

------------------------------------------------------------------ bricks
local function hit_brick(b)
    if b.k == "X" then b.flash = 1; sfx("hard"); return end
    b.hp = b.hp - 1; b.flash = 1
    if b.hp > 0 then sfx("hard"); return end
    b.alive = false; G.grid[b.r * 100 + b.c] = nil; G.left = G.left - 1
    add_pts(b.k == "S" and 50 * G.round or PTS[b.k])
    sfx("brick"); G.brick_burst(WP(b.x, b.y, 0.2), G.BRICK[b.k])
    if b.k ~= "S" then drop_capsule(b.x, b.y) end
end
local function bricks_near(x, y, f)
    local c0, c1 = floor((x + FW / 2 - 0.4) / BW) + 1, floor((x + FW / 2 + 0.4) / BW) + 1
    local r0, r1 = floor((FH - y - 0.4) / BH) + 1, floor((FH - y + 0.4) / BH) + 1
    for r = r0, r1 do for c = c0, c1 do local b = G.grid[r * 100 + c]; if b then f(b) end end end
end
-- circle vs box: returns push normal (nx, ny) and depth, or nil
local function circ_box(x, y, r, cx, cy, hw, hh)
    local qx, qy = clamp(x, cx - hw, cx + hw), clamp(y, cy - hh, cy + hh)
    local dx, dy = x - qx, y - qy
    local d2 = dx * dx + dy * dy
    if d2 >= r * r then return nil end
    if d2 > 1e-9 then local d = sqrt(d2); return dx / d, dy / d, r - d end
    -- centre inside: push out along the shallow axis
    local px, py = hw - abs(x - cx) + r, hh - abs(y - cy) + r
    if px < py then return (x > cx and 1 or -1), 0, px else return 0, (y > cy and 1 or -1), py end
end
G.circ_box = circ_box

------------------------------------------------------------------ ball step (swept: sub-steps of at most 0.08 units)
local function ball_step(b, dt)
    if b.stuck then b.x = P.x + b.off; b.y = VY + VH + BR + 0.01; return end
    local dist = sqrt(b.vx * b.vx + b.vy * b.vy) * dt
    local n = max(1, math.ceil(dist / 0.08))
    local h = dt / n
    for _ = 1, n do
        b.x, b.y = b.x + b.vx * h, b.y + b.vy * h
        -- walls
        local L, Rr, T = -FW / 2 + BR, FW / 2 - BR, FH - BR
        if b.x < L then b.x = L; b.vx = abs(b.vx); sfx("wall") elseif b.x > Rr then b.x = Rr; b.vx = -abs(b.vx); sfx("wall") end
        if b.y > T then b.y = T; b.vy = -abs(b.vy); sfx("wall")
            if not G.top_hit then G.top_hit = true; if P.mode ~= "S" then G.speed_lv = G.speed_lv + 2; set_speed(b, base_speed()) end end
        end
        -- bricks: resolve the deepest contact only (one brick per sub-step, like the arcade)
        local best, bn
        bricks_near(b.x, b.y, function(k)
            local nx, ny, d = circ_box(b.x, b.y, BR, k.x, k.y, BW / 2, BH / 2)
            if nx and (not best or d > bn[3]) then best, bn = k, { nx, ny, d } end
        end)
        if best then
            b.x, b.y = b.x + bn[1] * bn[3], b.y + bn[2] * bn[3]
            if abs(bn[1]) > abs(bn[2]) then b.vx = bn[1] * abs(b.vx) else b.vy = bn[2] * abs(b.vy) end
            hit_brick(best)
        end
        -- DOH
        local D = G.doh
        if D and D.alive then
            local nx, ny, d = circ_box(b.x, b.y, BR, D.x, D.y, D.hw, D.hh)
            if nx then
                b.x, b.y = b.x + nx * d, b.y + ny * d
                if abs(nx) > abs(ny) then b.vx = nx * abs(b.vx) else b.vy = ny * abs(b.vy) end
                D.hp = D.hp - 1; D.flash = 1; sfx("doh_hit"); G.sparks(WP(b.x, b.y, 0.6), 14)
                if D.hp <= 0 then D.alive = false; D.dead_t = 0; add_pts(0); sfx("doh_die"); G.boom(WP(D.x, D.y, 1), true); G.shake = 1.2 end
            end
        end
        -- enemies: the ball destroys them and bounces off
        for _, e in ipairs(G.EN) do
            if e.alive and (b.x - e.x) ^ 2 + (b.y - e.y) ^ 2 < (BR + 0.3) ^ 2 then
                e.alive = false; add_pts(100); sfx("pop"); G.boom(WP(e.x, e.y, 0.3), false)
                b.vy = -b.vy
            end
        end
        -- Vaus
        if b.vy < 0 and P.alive then
            local hw = P.w / 2
            if b.y - BR < VY + VH and b.y > VY - VH and abs(b.x - P.x) < hw + BR then
                local t = clamp((b.x - P.x) / hw, -1, 1)
                -- angle from vertical grows toward the ends of the Vaus (min 20 deg above horizontal)
                local a = math.rad(t * 62)
                local s = b.spd
                b.vx, b.vy = sin(a) * s, cos(a) * s
                b.y = VY + VH + BR
                G.hits = G.hits + 1
                if G.hits % 12 == 0 and P.mode ~= "S" then G.speed_lv = min(G.speed_lv + 1, 11); set_speed(b, base_speed()) end
                if P.mode == "C" then b.stuck = true; b.off = b.x - P.x; b.hold = 3.0; sfx("catch"); return end
                sfx("paddle")
            end
        end
    end
    -- keep the angle away from horizontal so the ball never stalls sideways
    local s = sqrt(b.vx * b.vx + b.vy * b.vy)
    if abs(b.vy) < s * 0.3 then b.vy = (b.vy >= 0 and 1 or -1) * s * 0.3; b.vx = (b.vx >= 0 and 1 or -1) * s * math.sqrt(1 - 0.09) end
end

------------------------------------------------------------------ death
local function lose_vaus()
    P.alive = false; G.phase = "dead"; G.pt = 0
    sfx("die"); G.boom(WP(P.x, VY, 0.3), false); G.shake = 0.6
    G.lives = G.lives - 1
end
G.lose_vaus = lose_vaus

------------------------------------------------------------------ main step
-- remember where everything was before a fixed step, so the renderer can blend the last two steps by AL
-- (the leftover fraction of a step). Without this the ball moved 0, 1 or 2 steps per displayed frame (judder).
function G.snap_prev()
    P.ox = P.x
    for _, t in ipairs({ G.BALLS, G.CAPS, G.SHOTS, G.DSHOT, G.EN }) do for _, o in ipairs(t) do o.ox, o.oy = o.x, o.y end end
end
function G.round_step(inp, dt)
    G.pt = G.pt + dt
    for _, b in ipairs(G.BRICKS) do if b.flash > 0 then b.flash = max(0, b.flash - dt * 5) end end
    if G.phase == "dead" then
        if G.pt > 2.2 then
            if G.lives <= 0 then G.out_of_lives = true; return end
            P.mode = nil; P.wt = 2.0; P.guns = false; G.CAPS, G.SHOTS, G.DSHOT = {}, {}, {}
            serve(); G.phase = "ready"; G.pt = 0
        end
        return
    end
    if G.phase == "clear" then
        if G.pt > 2.0 then
            if G.round >= G.LAST then G.won = true; G.out_of_lives = true
            else load_round(G.round + 1); serve(); sfx("start") end
        end
        return
    end
    -- Vaus
    P.w = P.w + (P.wt - P.w) * min(1, dt * 10)
    local lim = FW / 2 - P.w / 2
    P.x = clamp(P.x + inp.mx * 13 * dt + inp.mdx, -lim, G.warp and lim + P.w or lim)
    if G.warp and P.x > lim + 0.05 then
        -- through the break gate
        add_pts(10000); sfx("warp"); G.phase = "clear"; G.pt = 1.0; G.BALLS = {}
        return
    end
    if G.phase == "ready" then
        if G.pt > 0.8 then G.phase = "play" end
    end
    -- balls
    for _, b in ipairs(G.BALLS) do
        if b.stuck then
            b.hold = b.hold - dt
            if (inp.fire and G.phase == "play") or b.hold <= 0 then launch(b); inp.fire = false end
        end
        ball_step(b, dt)
    end
    for i = #G.BALLS, 1, -1 do if G.BALLS[i].y < -0.6 then table.remove(G.BALLS, i) end end
    if #G.BALLS == 0 and P.alive then lose_vaus(); return end
    -- laser
    if inp.fire and P.guns and #G.SHOTS < 4 then
        for _, s in ipairs({ -1, 1 }) do G.SHOTS[#G.SHOTS + 1] = { x = P.x + s * (P.w / 2 - 0.22), y = VY + 0.3, py = VY + 0.3 } end
        sfx("laser")
    end
    for i = #G.SHOTS, 1, -1 do
        local s = G.SHOTS[i]
        s.py = s.y; s.y = s.y + 18 * dt
        local hit = false
        -- swept: test every brick row the shot crossed this step
        for y = s.py, s.y, 0.2 do
            bricks_near(s.x, y, function(k) if not hit and abs(s.x - k.x) < BW / 2 and abs(y - k.y) < BH / 2 + 0.1 then hit_brick(k); hit = true end end)
            if hit then break end
        end
        for _, e in ipairs(G.EN) do if not hit and e.alive and abs(s.x - e.x) < 0.35 and e.y > s.py - 0.3 and e.y < s.y + 0.3 then e.alive = false; hit = true; add_pts(100); sfx("pop"); G.boom(WP(e.x, e.y, 0.3), false) end end
        local D = G.doh
        if not hit and D and D.alive and abs(s.x - D.x) < D.hw and s.y > D.y - D.hh then hit = true; G.sparks(WP(s.x, D.y - D.hh, 0.5), 5) end
        if hit or s.y > FH then table.remove(G.SHOTS, i) end
    end
    -- capsules
    for i = #G.CAPS, 1, -1 do
        local c = G.CAPS[i]
        c.y = c.y - 3.2 * dt; c.spin = c.spin + dt * 220
        if P.alive and c.y < VY + VH + 0.17 and c.y > VY - VH - 0.17 and abs(c.x - P.x) < P.w / 2 + 0.37 then apply_cap(c.k); table.remove(G.CAPS, i)
        elseif c.y < -0.6 then table.remove(G.CAPS, i) end
    end
    -- enemies drift in from the two top gates
    if not G.doh then
        G.en_t = G.en_t - dt
        if G.en_t <= 0 and #G.EN < 3 then
            G.en_t = rr(5, 9)
            local kinds = { "en_cone", "en_pyr", "en_orb", "en_cube" }
            G.EN[#G.EN + 1] = { k = kinds[(G.round - 1) % 4 + 1], x = rand() < 0.5 and -3.5 or 3.5, y = FH + 0.3, t = 0, alive = true, ph = rr(0, 6), gate = 0 }
        end
    end
    for i = #G.EN, 1, -1 do
        local e = G.EN[i]
        e.t = e.t + dt
        if e.alive then
            local nx = e.x + cos(e.t * 1.3 + e.ph) * 1.4 * dt
            local ny = e.y - (e.y > 3 and 0.9 or 0.25 * sin(e.t)) * dt
            -- they slide around bricks rather than through them
            local blocked = false
            bricks_near(nx, ny, function(k) if abs(nx - k.x) < 0.75 and abs(ny - k.y) < 0.55 then blocked = true end end)
            if not blocked then e.x, e.y = clamp(nx, -FW / 2 + 0.4, FW / 2 - 0.4), ny
            else e.x = clamp(e.x + (e.x > 0 and -1 or 1) * 1.2 * dt, -FW / 2 + 0.4, FW / 2 - 0.4) end
            if P.alive and abs(e.x - P.x) < P.w / 2 + 0.3 and abs(e.y - VY) < VH + 0.3 then e.alive = false; add_pts(100); sfx("pop"); G.boom(WP(e.x, e.y, 0.3), false) end
            if e.y < -0.5 then e.alive = false end
        else table.remove(G.EN, i) end
    end
    -- DOH
    local D = G.doh
    if D then
        D.t = D.t + dt; D.flash = max(0, D.flash - dt * 4)
        if D.alive then
            D.fire_t = D.fire_t - dt
            if D.fire_t <= 0 and P.alive then
                D.fire_t = rr(1.2, 2.0); sfx("doh_fire")
                local sx, sy = D.x, D.y - 1.6
                local dx, dy = P.x - sx, VY - sy
                local m = sqrt(dx * dx + dy * dy)
                G.DSHOT[#G.DSHOT + 1] = { x = sx, y = sy, vx = dx / m * 5.5, vy = dy / m * 5.5 }
            end
        else
            D.dead_t = D.dead_t + dt
            if D.dead_t > 2.5 then G.phase = "clear"; G.pt = 0; G.BALLS = {} end
        end
    end
    for i = #G.DSHOT, 1, -1 do
        local s = G.DSHOT[i]
        s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
        if P.alive and abs(s.x - P.x) < P.w / 2 + 0.12 and abs(s.y - VY) < VH + 0.12 then table.remove(G.DSHOT, i); lose_vaus(); return
        elseif s.y < -0.5 then table.remove(G.DSHOT, i) end
    end
    -- round clear
    if not G.doh and G.left <= 0 then G.phase = "clear"; G.pt = 0; G.BALLS = {}; sfx("start"); G.banner_set("Round Clear", 1.8) end
end
G.brick_burst, G.sparks, G.boom, G.flash = brick_burst, sparks, boom, flash
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
    if o.text_color then key = key .. o.text_color[4] end
    if hc[id] == key then return end
    hc[id] = key
    pcall(runtime_ui.set_quad, UI, id, o)
end
local function text(id, label, x, y, w, h, fs, col, align, vis)
    quad(id, { x = x, y = y, w = w, h = h, z = 10, style = "text", label = label, fill = NONE, border = NONE, text_color = col,
        font_scale = fs * US, align_h = align or "center", align_v = "middle", no_input = true, visible = vis ~= false })
end
local function panel(id, x, y, w, h, vis, a, border)
    quad(id, { x = x, y = y, w = w, h = h, z = 4, style = "text", label = "", fill = { 0.04, 0.04, 0.06, a or 0.55 },
        border = border or { 1, 0.55, 0.3, 0.55 }, corner_radius = 12 * US, no_input = true, visible = vis ~= false })
end
local function button(id, label, cx, cy, vis)
    local w, h = 340 * US, 60 * US
    local st = vis and select(2, pcall(runtime_ui.get_state, UI, id))
    local hov = type(st) == "table" and st.hovered
    quad(id, { x = cx - w / 2, y = cy - h / 2, w = w, h = h, z = 12, style = "text", label = label,
        fill = hov and { 0.55, 0.12, 0.08, 0.92 } or { 0.08, 0.05, 0.05, 0.85 }, border = hov and { 1, 0.75, 0.5, 1 } or { 1, 0.5, 0.3, 0.9 },
        text_color = { 0.95, 0.95, 0.92, 1 }, font_scale = 1.25 * US, align_h = "center", align_v = "middle",
        corner_radius = 12 * US, visible = vis })
    return vis and type(st) == "table" and st.clicked
end
local function pad6(n) local s = tostring(floor(n)); return string.rep("0", max(0, 6 - #s)) .. s end
local RED, WHITE, CYAN, DIM, GOLD = { 1, .35, .3, 1 }, { 1, 1, 1, 1 }, { .5, .85, 1, 1 }, { .85, .82, .78, 1 }, { 1, .85, .35, 1 }
local LW = 300 * US
local CAPN = { S = "Slow", C = "Catch", L = "Laser", E = "Enlarge" }
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause") and not G.set_open
    panel("lp", 20 * US, 20 * US, LW, 300 * US, play, 0.5)
    text("l1", "1UP", 40 * US, 30 * US, LW - 40 * US, 34 * US, 1.0, RED, "left", play)
    text("l2", pad6(G.score), 40 * US, 62 * US, LW - 40 * US, 52 * US, 1.8, WHITE, "left", play)
    text("l3", "High Score", 40 * US, 120 * US, LW - 40 * US, 34 * US, 1.0, RED, "left", play)
    text("l4", pad6(max(G.hiscore, G.score)), 40 * US, 152 * US, LW - 40 * US, 52 * US, 1.5, WHITE, "left", play)
    text("l5", "Vaus  " .. tostring(max(0, G.lives - 1)), 40 * US, 220 * US, LW - 40 * US, 40 * US, 1.1, DIM, "left", play)
    text("l6", G.P.mode and CAPN[G.P.mode] or "", 40 * US, 262 * US, LW - 40 * US, 40 * US, 1.1, CYAN, "left", play)
    panel("rp", SW - LW - 20 * US, 20 * US, LW, 150 * US, play, 0.5)
    text("r1", "Round", SW - LW, 30 * US, LW - 40 * US, 34 * US, 1.0, RED, "right", play)
    text("r2", tostring(G.round or 1), SW - LW, 62 * US, LW - 40 * US, 70 * US, 2.6, GOLD, "right", play)
    G.banner.t = (G.banner.t or 0) - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    text("ban", G.banner.text or "", 0, SH * 0.5, SW, 80 * US, 2.4, { 1, .88, .45, ba }, "center", play and G.banner.t > 0)
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 470 * US, SH * 0.06, 940 * US, SH * 0.62, title, 0.62)
    text("t_title", "Arkanoid Remix", 0, SH * 0.08, SW, 130 * US, 4.2, { 1, .55, .3, 1 }, "center", title)
    text("t_sub", "Pilot the Vaus through 32 rounds of bricks, then destroy DOH", 0, SH * 0.08 + 120 * US, SW, 40 * US, 1.0, DIM, "center", title)
    local CL = { "A / D / Arrows / Mouse: move the Vaus   ·   Space / Z / Left Click: launch / fire laser (one per press)",
        "Capsules: S Slow · C Catch · L Laser · E Enlarge · D Disruption · B Break (warp out) · P Extra Vaus",
        "Silver bricks need several hits · gold bricks can't be broken",
        "P / Esc: pause   ·   O: settings   ·   M: mute   ·   F3: colliders" }
    for i, l in ipairs(CL) do text("t_c" .. i, l, SW / 2 - 460 * US, SH * 0.47 + (i - 1) * 34 * US, 920 * US, 34 * US, 0.92, DIM, "center", title) end
    text("t_hi", "High Score " .. tostring(G.hiscore), 0, SH * 0.47 + 150 * US, SW, 36 * US, 1.1, CYAN, "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, GOLD, "center", pause)
    local over = st == "over" and not G.set_open
    panel("o_bg", SW / 2 - 400 * US, SH * 0.22, 800 * US, SH * 0.56, over, 0.78)
    text("o_t", G.won and "Congratulations!" or "Game Over", 0, SH * 0.24, SW, 90 * US, 3.0, G.won and GOLD or RED, "center", over)
    text("o_m", G.won and "DOH is destroyed and the Arkanoid's dimension is restored" or ("Round " .. tostring(G.round or 1)), 0, SH * 0.24 + 92 * US, SW, 40 * US, 1.2, DIM, "center", over)
    text("o_s", "Score " .. tostring(G.score), 0, SH * 0.24 + 140 * US, SW, 44 * US, 1.4, WHITE, "center", over)
    local c = {}
    local yb = SH * 0.3
    c.start = button("b_start", "Start (Enter)", SW / 2, yb, title)
    c.set_t = button("b_set_t", "Settings (O)", SW / 2, yb + 76 * US, title)
    c.quit_app = button("b_quit_app", "Quit Game", SW / 2, yb + 152 * US, title)
    c.resume = button("b_resume", "Resume (P)", SW / 2, SH * 0.42, pause)
    c.set_p = button("b_set_p", "Settings (O)", SW / 2, SH * 0.42 + 76 * US, pause)
    c.quit = button("b_quit", "Quit to Title (Q)", SW / 2, SH * 0.42 + 152 * US, pause)
    local ov = over and (G.over_t or 0) > 1.2
    c.again = button("b_again", "Play Again (Enter)", SW / 2, SH * 0.52, ov)
    c.title = button("b_title", "Title (Esc)", SW / 2, SH * 0.52 + 76 * US, ov)
    return c
end

------------------------------------------------------------------ flow
local function to_title()
    G.state = "title"; G.won = false
    G.new_game_sim(); G.reset_world()
    music("title")
end
G.to_title = to_title
local function new_game()
    G.reset_world(); G.new_game_sim()
    G.state = "play"
    music(nil); sfx("start")
end
G.new_game = new_game
local function game_over()
    G.state = "over"; G.over_t = 0
    music(G.won and "ending" or nil); sfx(G.won and "extra" or "gameover")
    if G.score > G.hiscore then G.hiscore = G.score; save_hi() end
end
local acc = 0
local mprev = 0
local q = { fire = false }
local lmouse_prev = true
local function update(dt)
    flush_mats()
    dt = min(dt, 0.1)
    G.t = G.t + dt; G.dt = dt
    local k = { ret = edge("Return"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), qk = edge("Q"), f3 = edge("F3"),
        space = edge("Space"), z = edge("Z"), j = edge("J"), up = edge("Up"), w = edge("W") }
    local ld = false
    pcall(function() ld = input.is_left_mouse_down and input.is_left_mouse_down() and true or false end)
    local lclick = ld and not lmouse_prev; lmouse_prev = ld
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end; lclick = false end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        if k.ret or k.space or c.start then sfx("click"); new_game()
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click")
        elseif k.space or k.z or k.j or k.up or k.w or lclick then q.fire = true end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.qk or c.quit then to_title() end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then sfx("click"); new_game()
            elseif k.esc or c.title then to_title() end
        end
    end
    st = G.state
    local mdx = 0
    pcall(function() local d = input.get_mouse_delta(); if d then mdx = d.x or d[1] or 0 end end)
    if st == "play" and not G.set_open then
        local mx = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0)
        if mx ~= 0 and mx ~= mprev and G.P.alive then sfx("move") end
        mprev = mx
        local mouse = clamp(mdx * 0.012, -1.5, 1.5)
        if G.autoplay then mx, mouse, q.fire = G.autoplay_fn() end
        local inp = { mx = mx, mdx = 0, fire = false }
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 7 do   -- 7 steps cover the 0.1 s dt clamp, so the game never runs slow above 10 fps
            inp.fire = q.fire; q.fire = false
            inp.mdx = n == 0 and mouse or 0
            G.snap_prev()
            G.round_step(inp, FR)
            acc = acc - FR; n = n + 1
        end
        if acc > FR * 7 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if G.out_of_lives and G.state == "play" then G.out_of_lives = false; game_over() end
        if G.doh and G.phase ~= "dead" and not G.doh_music then G.doh_music = true; music("doh") end
        if not G.doh then G.doh_music = false end
    else AL = 1 end
    render_world(dt)
    if G.on_frame then G.on_frame(dt) end   -- test/capture hook (nil in play)
    update_camera(dt)
    local b = G.BALLS[1]
    update_lights(dt, b and WP(G.ix(b, "x"), G.ix(b, "y"), 0.9) or nil)   -- the ball light follows the interpolated ball too
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end
-- debug autopilot for tests/screenshots only: track the lowest descending ball (and capsules when safe)
function G.autoplay_fn()
    local P = G.P
    local tx = 0
    local best
    for _, b in ipairs(G.BALLS) do if not best or (b.vy < 0 and b.y < best.y) then best = b end end
    if best then tx = best.x + (G.ap_off or 0) end
    G.ap_t = (G.ap_t or 0) + 1
    if G.ap_t % 90 == 0 then G.ap_off = rr(-0.6, 0.6) end
    local mx = clamp((tx - P.x) * 3, -1, 1)
    return mx, 0, (G.ap_t % 20 == 0)
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_world()
to_title()
G.update = update; G.SET = SET
hooks { update = update }
pe_log("[AK] ready")
