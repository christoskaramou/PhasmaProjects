-- CENTIPEDE REMIX  (PhasmaEngine, Lua)
-- Faithful modern remake of Atari's Centipede (1981):
--   snaking / splitting centipede, damageable mushrooms, flea, spider, scorpion (poison),
--   trackball-like mouse + keyboard blaster. Bioluminescent forest-floor look.
local PI, TAU = math.pi, math.pi * 2
local sin, cos, sqrt, rand, floor, abs, min, max = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local G = { state = "boot", t = 0, score = 0, lives = 3, level = 1, hiscore = 0 }
_G.CE = G

------------------------------------------------------------------ deferred materials
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
local function mlive(n, k, v) pcall(_mset, n, k, v) end
local function paint(n, base, emis, rough, metal)
    mset(n, "base_color", vec4(base[1], base[2], base[3], 1))
    mset(n, "emissive", vec3(emis[1], emis[2], emis[3]))
    mset(n, "roughness", rough or 0.3)
    mset(n, "metallic", metal or 0.0)
end

------------------------------------------------------------------ audio
local function sfx(name) pcall(audio.play, name .. ".wav") end

------------------------------------------------------------------ grid / playfield
-- Classic Atari: ~30x30; we use 24x28 cells for a tall portrait field.
local COLS, ROWS = 24, 28
local CELL = 1.05
local HW = COLS * CELL * 0.5
local HH = ROWS * CELL * 0.5
local PLAYER_ROWS = 6                    -- blaster free area at bottom
local ORIGIN_X, ORIGIN_Y = -HW + CELL * 0.5, HH - CELL * 0.5   -- col0,row0 centre (top-left)

local function cell_to_world(c, r)
    return ORIGIN_X + c * CELL, ORIGIN_Y - r * CELL
end
local function world_to_cell(x, y)
    local c = floor((x - ORIGIN_X) / CELL + 0.5)
    local r = floor((ORIGIN_Y - y) / CELL + 0.5)
    return c, r
end

------------------------------------------------------------------ render (TAA + smooth bloom — see /workspace/games/common/RENDER_SETTINGS.md)
local function S(k, v) pcall(settings.set, k, v) end
local ss = scene.add_empty_node("CentipedeSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
pcall(skybox.load, "forest.hdr")
S("taa", true); S("cas_sharpening", false)
S("motion_blur", false)
S("hdr", true)
S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.4)
S("tonemapping", true); S("fxaa", false)
S("ssao", false); S("ssr", false); S("dof", false); S("fog", false)
S("shadows", false); S("render_scale", 1.0)
S("IBL", true); S("IBL_intensity", 0.85)
S("color_grading", true); S("color_grading_saturation", 1.2); S("color_grading_contrast", 1.08)

local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1280, surf.height or 720
local cam = get_camera and get_camera() or scene.get_cameras()[1]
local FOVX = 1.05
local function fit_dist()
    local aspect = SW / max(SH, 1)
    local fovy = 2 * math.atan(math.tan(FOVX * 0.5) / aspect)
    local needH = (HH + 1.4) / math.tan(fovy * 0.5)
    local needW = (HW + 3.0) / math.tan(FOVX * 0.5)
    return max(needH, needW)
end
local CAM_BASE = vec3(0, -0.3, fit_dist())
local CAM_LOOK = vec3(0, 0, 0)
pcall(function() cam:set_fov(math.deg(FOVX)) end)
cam:set_position(CAM_BASE); cam:look_at(CAM_LOOK)

------------------------------------------------------------------ templates
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[Centipede] missing template " .. name); return nil end
    TPL[name] = { node = n, mesh = n:get_mesh_refs()[1] }
    return TPL[name]
end
local seq = 0
local HIDE = vec3(0, -1000, 0)
local function clone(name, pos, scale, parent)
    local t = tpl(name); seq = seq + 1
    local n = scene.add_empty_node(name .. "_c" .. seq)
    if t and t.mesh then n:add_mesh_ref(t.mesh) end
    if parent then n:set_parent(parent) end
    n:set_position(pos or vec3(0, 0, 0))
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

------------------------------------------------------------------ palette
-- mushroom slots 0..5 healthy hues, 6..7 poisoned
local MUSH_PAL = {
    [0] = { 0.15, 0.85, 0.45 }, { 0.25, 0.95, 0.70 }, { 0.55, 0.95, 0.35 },
    { 0.90, 0.55, 0.95 }, { 0.35, 0.75, 1.00 }, { 1.00, 0.75, 0.30 },
    [6] = { 0.85, 0.15, 0.95 }, [7] = { 1.00, 0.25, 0.55 },
}
local CENTI_PAL = {
    [0] = { 0.35, 1.00, 0.55 }, { 0.25, 0.95, 0.85 }, { 0.85, 1.00, 0.35 }, { 0.55, 0.95, 1.00 },
}
G.glow = 1.0
local function paint_templates()
    for i = 0, 7 do
        local c = MUSH_PAL[i]
        local poison = i >= 6
        local stem, cap, glow = tpl("T_mush_stem_" .. i), tpl("T_mush_cap_" .. i), tpl("T_mush_glow_" .. i)
        local eg = poison and 1.8 or 1.15
        paint(stem.node, { 0.35, 0.28, 0.18 }, { c[1]*0.15, c[2]*0.15, c[3]*0.12 }, 0.55, 0.0)
        paint(cap.node, { c[1]*0.7, c[2]*0.7, c[3]*0.7 }, { c[1]*0.55*eg, c[2]*0.55*eg, c[3]*0.55*eg }, 0.22, 0.15)
        paint(glow.node, c, { c[1]*1.4*eg, c[2]*1.4*eg, c[3]*1.4*eg }, 0.35, 0.0)
        mtex(cap.node, "base_color", "Textures/mush_cap.png")
    end
    for i = 0, 3 do
        local c = CENTI_PAL[i]
        local b, h = tpl("T_centi_body_" .. i), tpl("T_centi_head_" .. i)
        paint(b.node, { c[1]*0.55, c[2]*0.55, c[3]*0.55 }, { c[1]*0.38, c[2]*0.38, c[3]*0.38 }, 0.22, 0.35)
        paint(h.node, { 0.95, 0.25, 0.55 }, { 0.75, 0.12, 0.38 }, 0.18, 0.35)
    end
    paint(tpl("T_blaster").node, { 0.45, 0.6, 0.75 }, { 0.08, 0.35, 0.55 }, 0.2, 0.6)
    paint(tpl("T_blaster_glow").node, { 0.2, 0.9, 1.0 }, { 0.2, 0.8, 1.1 }, 0.3, 0.0)
    paint(tpl("T_bullet").node, { 1.0, 0.95, 0.6 }, { 2.4, 2.1, 0.9 }, 0.2, 0.0)
    paint(tpl("T_bullet_glow").node, { 1.0, 0.8, 0.2 }, { 1.4, 0.9, 0.2 }, 0.4, 0.0)
    paint(tpl("T_spider").node, { 0.85, 0.15, 0.35 }, { 1.4, 0.25, 0.55 }, 0.18, 0.4)
    paint(tpl("T_flea").node, { 0.95, 0.55, 0.15 }, { 1.6, 0.9, 0.2 }, 0.2, 0.3)
    paint(tpl("T_scorpion").node, { 0.95, 0.85, 0.2 }, { 1.5, 1.2, 0.25 }, 0.15, 0.5)
    paint(tpl("T_floor").node, { 0.08, 0.14, 0.07 }, { 0.04, 0.18, 0.10 }, 0.75, 0.0)
    paint(tpl("T_floor_glow").node, { 0.1, 0.5, 0.3 }, { 0.2, 1.0, 0.55 }, 0.5, 0.0)
    paint(tpl("T_moss").node, { 0.12, 0.35, 0.15 }, { 0.08, 0.45, 0.22 }, 0.85, 0.0)
    paint(tpl("T_leaf").node, { 0.25, 0.45, 0.12 }, { 0.05, 0.15, 0.04 }, 0.7, 0.0)
    paint(tpl("T_spore").node, { 0.5, 1.0, 0.7 }, { 0.6, 1.6, 0.9 }, 0.4, 0.0)
    paint(tpl("T_shard").node, { 0.3, 1.0, 0.5 }, { 0.8, 1.8, 0.9 }, 0.2, 0.3)
    for i = 0, 5 do
        local L = tpl("T_leg_" .. i)
        if L then paint(L.node, { 0.2, 0.7, 0.4 }, { 0.3, 0.9, 0.5 }, 0.25, 0.2) end
    end
end
------------------------------------------------------------------ world
local function build_world()
    local bg = prim("quad", vec3(0, 2, -28), vec3(120, 80, 1))
    paint(bg, { 0, 0, 0 }, { 0.35, 0.55, 0.40 }, 1.0, 0.0)
    pcall(_mds, bg, true); qpush(function() pcall(_mds, bg, true) end)
    mtex(bg, "emissive", "Textures/backdrop.png")
    G.backdrop = bg
    -- forest floor plate
    local floor = prim("cube", vec3(0, -HH + CELL * 0.5 - 0.35, -0.6), vec3(HW * 2 + 1.5, ROWS * CELL + 1.5, 0.5))
    paint(floor, { 0.06, 0.12, 0.06 }, { 0.08, 0.35, 0.18 }, 0.7, 0.05)
    mtex(floor, "base_color", "Textures/forest_floor.png")
    mtex(floor, "emissive", "Textures/floor_glow.png")
    G.floor = floor
    -- soft side / top frame with biolume strips
    local T = 0.55
    local frame = {
        { vec3(-HW - T * 0.5, 0, 0.2), vec3(T, ROWS * CELL + 1.2, 1.0) },
        { vec3(HW + T * 0.5, 0, 0.2), vec3(T, ROWS * CELL + 1.2, 1.0) },
        { vec3(0, HH + T * 0.5, 0.2), vec3(HW * 2 + T * 2, T, 1.0) },
        { vec3(0, -HH - T * 0.5, 0.2), vec3(HW * 2 + T * 2, T, 1.0) },
    }
    for _, r in ipairs(frame) do
        local n = prim("cube", r[1], r[2])
        paint(n, { 0.12, 0.22, 0.16 }, { 0.05, 0.15, 0.10 }, 0.4, 0.3)
    end
    local g = 0.18
    G.frame_glow = {}
    for _, p in ipairs({
        { vec3(-HW - g * 0.3, 0, 0.7), vec3(g, ROWS * CELL, 0.08) },
        { vec3(HW + g * 0.3, 0, 0.7), vec3(g, ROWS * CELL, 0.08) },
        { vec3(0, HH + g * 0.3, 0.7), vec3(HW * 2, g, 0.08) },
    }) do
        local n = prim("cube", p[1], p[2])
        paint(n, { 0.2, 0.95, 0.55 }, { 0.35, 1.5, 0.9 }, 0.3, 0)
        G.frame_glow[#G.frame_glow + 1] = n
    end
    -- decorative moss / leaves around edges
    for i = 1, 12 do
        local side = (i % 2 == 0) and 1 or -1
        local x = side * (HW + rr(0.6, 2.2))
        local y = rr(-HH + 1, HH - 1)
        local m = clone("T_moss", vec3(x, y, rr(-0.2, 0.4)), vec3(rr(0.4, 1.1), rr(0.3, 0.7), rr(0.4, 1.0)))
        m:set_rotation(vec3(0, 0, rr(0, TAU)))
        if rand() < 0.5 then
            local lf = clone("T_leaf", vec3(x + rr(-0.5, 0.5), y + rr(-0.5, 0.5), 0.3), vec3(rr(0.6, 1.2), 1, rr(0.6, 1.2)))
            lf:set_rotation(vec3(0, 0, rr(0, TAU)))
        end
    end
end

------------------------------------------------------------------ dynamic lights
local function add_point()
    lights.add_point()
    return #lights.get_point_lights() - 1
end
local LNODE = {}
local LIGHT_GAIN = 0.12
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
    lights.set_directional_light(0, vec3(-0.2, -0.7, -0.5), vec3(0.45, 0.7, 0.55), 0.9)
    local function addp(pos, col, inten, rad) local i = add_point(); set_point(i, pos, col, inten, rad); return i end
    L.key_l = addp(vec3(-HW - 4, 6, 12), vec3(0.2, 0.9, 0.55), 70, 55)
    L.key_r = addp(vec3(HW + 4, 6, 12), vec3(0.7, 0.35, 1.0), 60, 55)
    L.moon = addp(vec3(4, HH + 8, 18), vec3(0.7, 0.85, 1.0), 40, 70)
    L.player = addp(HIDE, vec3(0.3, 0.9, 1.2), 0, 1)
    L.spider = addp(HIDE, vec3(1.2, 0.2, 0.5), 0, 1)
    L.flea = addp(HIDE, vec3(1.4, 0.8, 0.2), 0, 1)
    L.scorp = addp(HIDE, vec3(1.3, 1.1, 0.2), 0, 1)
    L.flash = {}
    for i = 1, 6 do L.flash[i] = { idx = addp(HIDE, vec3(1, 1, 1), 0, 1), t = 1, life = 1, pos = HIDE, col = vec3(1, 1, 1), power = 0, rad = 6 } end
end
local flash_next = 1
local function flash(x, y, col, power, life, rad)
    local f = L.flash[flash_next]; flash_next = flash_next % #L.flash + 1
    f.t, f.life, f.pos, f.col, f.power, f.rad = 0, life or 0.3, vec3(x, y, 2.0), vec3(col[1], col[2], col[3]), power or 28, rad or 6
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

------------------------------------------------------------------ mushrooms
-- mush[r+1][c+1] = { hp=1..4, poison=bool, stem=, cap=, glow=, slot=, pulse= }
local mush = {}
local MUSH_SCALE = vec3(1.05, 1.05, 1.05)
local function mush_at(c, r)
    if c < 0 or c >= COLS or r < 0 or r >= ROWS then return nil end
    return mush[r + 1] and mush[r + 1][c + 1]
end
local function free_mush_nodes(m)
    if not m then return end
    if m.stem then m.stem:set_position(HIDE) end
    if m.cap then m.cap:set_position(HIDE) end
    if m.glow then m.glow:set_position(HIDE) end
end
local function place_mush(c, r, hp, poison, slot)
    if c < 0 or c >= COLS or r < 0 or r >= ROWS then return end
    -- keep player spawn area mostly clear on initial layout (still allow flea drops)
    mush[r + 1] = mush[r + 1] or {}
    local prev = mush[r + 1][c + 1]
    if prev and prev.hp and prev.hp > 0 then
        prev.hp = max(prev.hp, hp or 4)
        if poison then prev.poison = true; prev.slot = prev.slot >= 6 and prev.slot or (6 + (prev.slot % 2)) end
        return prev
    end
    free_mush_nodes(prev)
    slot = slot or (poison and (6 + floor(rr(0, 1.99))) or floor(rr(0, 5.99)))
    local x, y = cell_to_world(c, r)
    local stem = clone("T_mush_stem_" .. slot, vec3(x, y - 0.15, 0.15), MUSH_SCALE)
    local cap = clone("T_mush_cap_" .. slot, vec3(x, y - 0.15, 0.15), MUSH_SCALE)
    local glow = clone("T_mush_glow_" .. slot, vec3(x, y - 0.15, 0.15), MUSH_SCALE)
    local m = { hp = hp or 4, poison = poison or false, stem = stem, cap = cap, glow = glow, slot = slot, c = c, r = r, pulse = rr(0, TAU) }
    mush[r + 1][c + 1] = m
    return m
end
local function destroy_mush(c, r, scored)
    local m = mush_at(c, r)
    if not m or not m.hp or m.hp <= 0 then return end
    local x, y = cell_to_world(c, r)
    free_mush_nodes(m)
    mush[r + 1][c + 1] = { hp = 0 }
    if scored then
        G.score = G.score + 1
        -- spore burst
        pcall(particles.emit_burst, {
            position = vec3(x, y, 0.6), velocity = vec3(0, 0.5, 0),
            color_start = vec4(0.4, 1.0, 0.6, 1), color_end = vec4(0.1, 0.4, 0.2, 0),
            count = max(1, floor(28 * (G.pscale or 1))), size_min = 0.04, size_max = 0.14,
            life_min = 0.3, life_max = 0.7, spawn_radius = 0.25, velocity_strength = 8,
            drag = 1.5, gravity = vec3(0, -4, 0), cleanup_delay = 2.0,
        })
        flash(x, y, MUSH_PAL[m.slot] or { 0.4, 1, 0.5 }, 18, 0.25, 4)
        sfx("mush")
    end
end
local function damage_mush(c, r)
    local m = mush_at(c, r)
    if not m or not m.hp or m.hp <= 0 then return false end
    m.hp = m.hp - 1
    local x, y = cell_to_world(c, r)
    local s = 0.55 + 0.12 * m.hp
    if m.stem then m.stem:set_scale(vec3(s, s * (0.7 + 0.1 * m.hp), s)) end
    if m.cap then m.cap:set_scale(vec3(s, s, s)) end
    if m.glow then m.glow:set_scale(vec3(s, s, s)) end
    if m.hp <= 0 then destroy_mush(c, r, true); return true end
    sfx("mush")
    pcall(particles.emit_burst, {
        position = vec3(x, y, 0.5), velocity = vec3(0, 0.2, 0),
        color_start = vec4(0.5, 1.0, 0.7, 1), color_end = vec4(0.2, 0.5, 0.3, 0),
        count = max(1, floor(12 * (G.pscale or 1))), size_min = 0.03, size_max = 0.08,
        life_min = 0.2, life_max = 0.45, spawn_radius = 0.15, velocity_strength = 5,
        drag = 2.0, gravity = vec3(0, -3, 0), cleanup_delay = 1.5,
    })
    return true
end
local function poison_mush(c, r)
    local m = mush_at(c, r)
    if not m or not m.hp or m.hp <= 0 or m.poison then return end
    m.poison = true
    local slot = 6 + (m.slot % 2)
    -- rebuild with poisoned templates
    local x, y = cell_to_world(c, r)
    free_mush_nodes(m)
    local s = 0.55 + 0.12 * m.hp
    m.slot = slot
    m.stem = clone("T_mush_stem_" .. slot, vec3(x, y - 0.15, 0.15), vec3(s, s, s))
    m.cap = clone("T_mush_cap_" .. slot, vec3(x, y - 0.15, 0.15), vec3(s, s, s))
    m.glow = clone("T_mush_glow_" .. slot, vec3(x, y - 0.15, 0.15), vec3(s, s, s))
    flash(x, y, { 1.0, 0.2, 0.9 }, 22, 0.35, 5)
    sfx("poison")
end
local function clear_mushrooms()
    for r = 0, ROWS - 1 do
        mush[r + 1] = mush[r + 1] or {}
        for c = 0, COLS - 1 do
            free_mush_nodes(mush[r + 1][c + 1])
            mush[r + 1][c + 1] = nil
        end
    end
end
local function seed_mushrooms(count)
    clear_mushrooms()
    local n = 0
    local attempts = 0
    while n < count and attempts < count * 8 do
        attempts = attempts + 1
        local c = floor(rr(0, COLS - 0.01))
        local r = floor(rr(1, ROWS - PLAYER_ROWS - 0.01))  -- leave player area mostly empty
        if not mush_at(c, r) or (mush_at(c, r).hp or 0) <= 0 then
            place_mush(c, r, 4, false); n = n + 1
        end
    end
end
local function count_mush_in_player_area()
    local n = 0
    for r = ROWS - PLAYER_ROWS, ROWS - 1 do
        for c = 0, COLS - 1 do
            local m = mush_at(c, r)
            if m and m.hp and m.hp > 0 then n = n + 1 end
        end
    end
    return n
end
local function restore_damaged_mushrooms()
    -- between lives: repair remaining mushrooms toward full hp (classic Centipede)
    for r = 0, ROWS - 1 do
        for c = 0, COLS - 1 do
            local m = mush_at(c, r)
            if m and m.hp and m.hp > 0 and m.hp < 4 then
                m.hp = 4
                if m.stem then m.stem:set_scale(MUSH_SCALE) end
                if m.cap then m.cap:set_scale(MUSH_SCALE) end
                if m.glow then m.glow:set_scale(MUSH_SCALE) end
                G.score = G.score + 5
                local x, y = cell_to_world(c, r)
                pcall(particles.emit_burst, {
                    position = vec3(x, y, 0.5), velocity = vec3(0, 1, 0),
                    color_start = vec4(0.6, 1, 0.8, 1), color_end = vec4(0.2, 0.6, 0.3, 0),
                    count = max(1, floor(10 * (G.pscale or 1))), size_min = 0.04, size_max = 0.1,
                    life_min = 0.3, life_max = 0.6, spawn_radius = 0.2, velocity_strength = 4,
                    drag = 1.2, gravity = vec3(0, -2, 0), cleanup_delay = 1.5,
                })
            end
        end
    end
end
local function update_mush_visuals(dt)
    for r = 0, ROWS - 1 do
        for c = 0, COLS - 1 do
            local m = mush_at(c, r)
            if m and m.hp and m.hp > 0 and m.glow then
                m.pulse = (m.pulse or 0) + dt * (m.poison and 4.0 or 2.2)
                local k = 0.85 + 0.25 * sin(m.pulse)
                -- slight bob
                local x, y = cell_to_world(c, r)
                local bob = sin(m.pulse * 0.7) * 0.02
                if m.cap then m.cap:set_position(vec3(x, y - 0.15 + bob, 0.15)) end
                if m.glow then m.glow:set_position(vec3(x, y - 0.15 + bob, 0.15)) end
            end
        end
    end
end
------------------------------------------------------------------ centipede
-- A centipede is a list of segments: {c, r, x, y, node, head?, dir, drop_dir, poison_dive}
-- Movement: along rows left/right; on edge or mushroom ahead, drop one row and reverse.
local worms = {}   -- list of worms (each a list of segments)
local CENTI_SPEED0 = 5.5   -- cells per second
local function centi_speed()
    return CENTI_SPEED0 * (1 + (G.level - 1) * 0.12)
end
local function seg_slot(i) return i % 4 end

local function spawn_centipede(length, start_c, start_r, dir)
    length = length or 12
    start_c = start_c or floor(COLS / 2)
    start_r = start_r or 0
    dir = dir or ((rand() < 0.5) and 1 or -1)
    local worm = { segs = {}, dir = dir, drop = 1, poison_dive = false, t = 0, slot = floor(rr(0, 3.99)) }
    for i = 1, length do
        local c = start_c - dir * (i - 1)
        local r = start_r
        -- wrap into field if needed
        if c < 0 then c = 0 elseif c >= COLS then c = COLS - 1 end
        local x, y = cell_to_world(c, r)
        local is_head = (i == 1)
        local tname = is_head and ("T_centi_head_" .. worm.slot) or ("T_centi_body_" .. worm.slot)
        local node = clone(tname, vec3(x, y, 0.45), vec3(1.55, 1.55, 1.55))
        worm.segs[#worm.segs + 1] = {
            c = c, r = r, x = x, y = y, node = node, head = is_head,
            dist = 0,  -- progress within current cell (0..1)
        }
    end
    worms[#worms + 1] = worm
    sfx("spawn")
    return worm
end

local function kill_seg_vfx(seg, head)
    local c = head and CENTI_PAL[0] or { 0.3, 0.9, 0.5 }
    pcall(particles.emit_burst, {
        position = vec3(seg.x, seg.y, 0.6), velocity = vec3(0, 0.5, 0),
        color_start = vec4(c[1], c[2], c[3], 1), color_end = vec4(c[1]*0.3, c[2]*0.3, c[3]*0.3, 0),
        count = max(1, floor((head and 50 or 28) * (G.pscale or 1))),
        size_min = 0.04, size_max = head and 0.18 or 0.12,
        life_min = 0.25, life_max = 0.7, spawn_radius = 0.3, velocity_strength = head and 16 or 10,
        drag = 1.8, gravity = vec3(0, -6, 0), cleanup_delay = 2.2,
    })
    -- sap drip
    pcall(particles.emit_burst, {
        position = vec3(seg.x, seg.y, 0.4), velocity = vec3(0, -1, 0),
        color_start = vec4(0.2, 0.85, 0.45, 1), color_end = vec4(0.05, 0.3, 0.1, 0),
        count = max(1, floor(18 * (G.pscale or 1))), size_min = 0.03, size_max = 0.09,
        life_min = 0.4, life_max = 0.9, spawn_radius = 0.15, velocity_strength = 3,
        drag = 0.8, gravity = vec3(0, -10, 0), cleanup_delay = 2.0,
    })
    flash(seg.x, seg.y, c, head and 40 or 22, 0.35, head and 7 or 5)
    if seg.node then seg.node:set_position(HIDE) end
end

local function split_worm(wi, si)
    -- Shoot segment si (1-based) of worm wi. Head=100, body=10. Leaves a mushroom.
    local worm = worms[wi]
    if not worm then return end
    local seg = worm.segs[si]
    if not seg then return end
    local was_head = seg.head
    G.score = G.score + (was_head and 100 or 10)
    sfx(was_head and "hit_head" or "hit_body")
    kill_seg_vfx(seg, was_head)
    place_mush(seg.c, seg.r, 4, false)

    local front, back = {}, {}
    for i = 1, si - 1 do front[#front + 1] = worm.segs[i] end
    for i = si + 1, #worm.segs do back[#back + 1] = worm.segs[i] end

    -- remove original worm
    table.remove(worms, wi)

    local function promote(list, dir, drop, slot)
        if #list == 0 then return end
        list[1].head = true
        -- swap mesh to head
        if list[1].node then
            list[1].node:set_position(HIDE)
            local x, y = list[1].x, list[1].y
            list[1].node = clone("T_centi_head_" .. slot, vec3(x, y, 0.45), vec3(1.55, 1.55, 1.55))
        end
        for i = 2, #list do list[i].head = false end
        worms[#worms + 1] = { segs = list, dir = dir, drop = drop, poison_dive = false, t = 0, slot = slot }
    end
    -- front keeps current direction; back becomes new worm (often reverse)
    promote(front, worm.dir, worm.drop, worm.slot)
    promote(back, -worm.dir, worm.drop, (worm.slot + 1) % 4)
end

local function clear_worms()
    for _, w in ipairs(worms) do
        for _, s in ipairs(w.segs) do if s.node then s.node:set_position(HIDE) end end
    end
    worms = {}
end

local function blocked(c, r)
    if c < 0 or c >= COLS then return true end
    local m = mush_at(c, r)
    return m and m.hp and m.hp > 0
end

local function update_worms(dt)
    local spd = centi_speed()
    local i = 1
    while i <= #worms do
        local w = worms[i]
        if #w.segs == 0 then table.remove(worms, i)
        else
            local head = w.segs[1]
            -- poison dive: drop straight down every step
            local step = spd * dt
            head.dist = (head.dist or 0) + step
            while head.dist >= 1 do
                head.dist = head.dist - 1
                local nc, nr = head.c + w.dir, head.r
                local dive = w.poison_dive
                local hit_edge = nc < 0 or nc >= COLS
                local hit_mush = (not hit_edge) and blocked(nc, nr)
                if dive or hit_edge or hit_mush then
                    -- drop a row
                    nr = head.r + (w.drop or 1)
                    if nr >= ROWS then
                        nr = ROWS - 1
                        w.drop = -1
                    elseif nr < ROWS - PLAYER_ROWS and w.drop == -1 then
                        -- bounce in player area: stay in bottom zone
                        w.drop = 1
                    end
                    if not dive then w.dir = -w.dir end
                    nc = head.c
                    -- if still blocked after drop (mushroom), try slide
                    if blocked(nc, nr) then
                        -- stay and keep trying next frame (will jitter); classic queues the turn
                        nr = min(ROWS - 1, head.r + 1)
                    end
                    -- entering a poisoned mushroom: arm dive for THIS worm
                    local m = mush_at(nc, nr)
                    if m and m.poison then w.poison_dive = true end
                end
                -- shift body: each segment follows previous path by taking old head cells
                local prev_c, prev_r = head.c, head.r
                head.c, head.r = clamp(nc, 0, COLS - 1), clamp(nr, 0, ROWS - 1)
                for s = 2, #w.segs do
                    local seg = w.segs[s]
                    local pc, pr = seg.c, seg.r
                    seg.c, seg.r = prev_c, prev_r
                    prev_c, prev_r = pc, pr
                end
            end
            -- interpolate positions
            for si, seg in ipairs(w.segs) do
                local tx, ty = cell_to_world(seg.c, seg.r)
                -- head eases toward next cell
                if si == 1 then
                    local nx = seg.c + w.dir
                    local ny = seg.r
                    if w.poison_dive or nx < 0 or nx >= COLS or blocked(nx, seg.r) then
                        nx, ny = seg.c, seg.r + (w.drop or 1)
                    end
                    nx, ny = clamp(nx, 0, COLS - 1), clamp(ny, 0, ROWS - 1)
                    local x2, y2 = cell_to_world(nx, ny)
                    local t = head.dist or 0
                    seg.x = lerp(tx, x2, t)
                    seg.y = lerp(ty, y2, t)
                else
                    -- body follows the exact cell path: moves from its cell toward the cell of the segment ahead
                    local prev = w.segs[si - 1]
                    local x2, y2 = cell_to_world(prev.c, prev.r)
                    local t = head.dist or 0
                    seg.x = lerp(tx, x2, t)
                    seg.y = lerp(ty, y2, t)
                end
                if seg.node then
                    local bob = sin(G.t * 10 + si * 0.7) * 0.04
                    seg.node:set_position(vec3(seg.x, seg.y + bob, 0.45))
                    local yaw = (w.dir > 0) and (-PI * 0.5) or (PI * 0.5)
                    if w.poison_dive then yaw = 0 end
                    if si > 1 then
                        local p = w.segs[si - 1]
                        local dx, dy = p.x - seg.x, p.y - seg.y
                        if dx * dx + dy * dy > 1e-4 then yaw = math.atan2(dy, dx) - PI * 0.5 end
                    end
                    seg.node:set_rotation(vec3(0.12 * sin(G.t * 9 + si * 0.9), 0, yaw))
                    local pulse = 0.88 + 0.08 * sin(G.t * 6 + si)
                    local pulse = 0.96 + 0.04 * sin(G.t * 6 + si)
                    seg.node:set_scale(vec3(pulse, pulse, pulse) * (seg.head and 1.2 or 1.1))
                end
            end
            i = i + 1
        end
    end
end

local function worms_remaining()
    local n = 0
    for _, w in ipairs(worms) do n = n + #w.segs end
    return n
end

------------------------------------------------------------------ player blaster
local PL = { x = 0, y = 0, vx = 0, vy = 0, node = nil, glow = nil, fire_cd = 0, invuln = 0 }
local function player_limits()
    local min_y = -HH + CELL * 0.5
    local max_y = -HH + PLAYER_ROWS * CELL - CELL * 0.5
    return -HW + CELL * 0.4, HW - CELL * 0.4, min_y, max_y
end
local function build_player()
    local x, y = 0, -HH + CELL * 1.5
    PL.x, PL.y = x, y
    PL.node = clone("T_blaster", vec3(x, y, 0.55), vec3(1.7, 1.7, 1.7))
    PL.glow = clone("T_blaster_glow", vec3(x, y, 0.7), vec3(1.0, 0.5, 1.3))
end
local function draw_player()
    if not PL.node then return end
    local bob = sin(G.t * 7) * 0.03
    PL.node:set_position(vec3(PL.x, PL.y + bob, 0.5))
    if PL.glow then PL.glow:set_position(vec3(PL.x, PL.y + 0.25 + bob, 0.7)) end
    set_point(L.player, vec3(PL.x, PL.y, 2.5), vec3(0.3, 0.9, 1.2), 16 + 8 * sin(G.t * 5), 7)
end

------------------------------------------------------------------ bullets
local bullets = {}
local BULLET_SPD = 46
local function fire_bullet()
    if PL.fire_cd > 0 or #bullets > 0 then return end
    PL.fire_cd = 0.06
    local n = clone("T_bullet", vec3(PL.x, PL.y + 0.5, 0.9), vec3(1.0, 1.0, 1.0))
    local g = clone("T_bullet_glow", vec3(PL.x, PL.y + 0.2, 0.8), vec3(1.6, 1.8, 1.6))
    bullets[#bullets + 1] = { x = PL.x, y = PL.y + 0.5, node = n, glow = g }
    sfx("shoot")
    -- muzzle sparks
    pcall(particles.emit_burst, {
        position = vec3(PL.x, PL.y + 0.6, 0.6), velocity = vec3(0, 8, 0),
        color_start = vec4(1.0, 0.95, 0.4, 1), color_end = vec4(1.0, 0.4, 0.1, 0),
        count = max(1, floor(10 * (G.pscale or 1))), size_min = 0.03, size_max = 0.08,
        life_min = 0.1, life_max = 0.25, spawn_radius = 0.1, velocity_strength = 6,
        drag = 3.0, gravity = vec3(0, 0, 0), cleanup_delay = 1.0,
    })
end
local function clear_bullets()
    for _, b in ipairs(bullets) do
        if b.node then b.node:set_position(HIDE) end
        if b.glow then b.glow:set_position(HIDE) end
    end
    bullets = {}
end
local function hit_test_bullet(b)
    local c, r = world_to_cell(b.x, b.y)
    -- mushrooms
    if damage_mush(c, r) then return "mush" end
    -- centipede segments
    for wi = #worms, 1, -1 do
        local w = worms[wi]
        for si = #w.segs, 1, -1 do
            local s = w.segs[si]
            if abs(s.x - b.x) < CELL * 0.6 and abs(s.y - b.y) < CELL * 0.55 then
                split_worm(wi, si)
                return "centi"
            end
        end
    end
    return nil
end
------------------------------------------------------------------ flea / spider / scorpion
local flea = nil
local spider = nil
local scorp = nil
local SPAWN = { flea_cd = 0, spider_cd = 4, scorp_cd = 8 }

local function spawn_flea()
    if flea then return end
    local c = floor(rr(1, COLS - 2))
    local x, y = cell_to_world(c, 0)
    flea = {
        x = x, y = y + CELL, vy = -7.5 - G.level * 0.4,
        node = clone("T_flea", vec3(x, y, 0.55), vec3(1.5, 1.5, 1.5)),
        drop_acc = 0, c = c, hp = 2,
    }
    sfx("flea")
end
local function spawn_spider()
    if spider then return end
    local from_left = rand() < 0.5
    local x = from_left and (-HW - 1) or (HW + 1)
    local y = -HH + rr(CELL, PLAYER_ROWS * CELL - CELL)
    spider = {
        x = x, y = y, dir = from_left and 1 or -1,
        vx = (from_left and 1 or -1) * (5.5 + G.level * 0.3),
        vy = rr(-3, 3), zig = 0,
        node = clone("T_spider", vec3(x, y, 0.6), vec3(1.15, 1.15, 1.15)),
    }
    sfx("spider")
end
local function spawn_scorpion()
    if scorp then return end
    local from_left = rand() < 0.5
    local r = floor(rr(2, ROWS - PLAYER_ROWS - 2))
    local x, y = cell_to_world(from_left and 0 or (COLS - 1), r)
    x = from_left and (-HW - 1) or (HW + 1)
    scorp = {
        x = x, y = y, dir = from_left and 1 or -1,
        vx = (from_left and 1 or -1) * (4.0 + G.level * 0.25),
        r = r,
        node = clone("T_scorpion", vec3(x, y, 0.55), vec3(1.25, 1.25, 1.25)),
        last_c = -99,
    }
    sfx("scorpion")
end

local function kill_flea(scored)
    if not flea then return end
    if scored then
        G.score = G.score + 200
        flash(flea.x, flea.y, { 1.4, 0.8, 0.2 }, 35, 0.4, 6)
        pcall(particles.emit_burst, {
            position = vec3(flea.x, flea.y, 0.5), velocity = vec3(0, 1, 0),
            color_start = vec4(1, 0.7, 0.2, 1), color_end = vec4(0.5, 0.2, 0, 0),
            count = max(1, floor(40 * (G.pscale or 1))), size_min = 0.04, size_max = 0.14,
            life_min = 0.25, life_max = 0.65, spawn_radius = 0.25, velocity_strength = 12,
            drag = 1.5, gravity = vec3(0, -5, 0), cleanup_delay = 2.0,
        })
        sfx("hit_head")
    end
    if flea.node then flea.node:set_position(HIDE) end
    set_point(L.flea, HIDE, vec3(1, 1, 1), 0, 1)
    flea = nil
end
local function kill_spider(scored)
    if not spider then return end
    if scored then
        -- proximity score: closer = more points (900 / 600 / 300)
        local dy = abs(spider.y - PL.y)
        local pts = (dy < CELL * 1.5) and 900 or ((dy < CELL * 3.5) and 600 or 300)
        G.score = G.score + pts
        flash(spider.x, spider.y, { 1.2, 0.2, 0.5 }, 40, 0.45, 7)
        pcall(particles.emit_burst, {
            position = vec3(spider.x, spider.y, 0.5), velocity = vec3(0, 1, 0),
            color_start = vec4(1, 0.2, 0.45, 1), color_end = vec4(0.4, 0.05, 0.15, 0),
            count = max(1, floor(55 * (G.pscale or 1))), size_min = 0.05, size_max = 0.16,
            life_min = 0.3, life_max = 0.75, spawn_radius = 0.3, velocity_strength = 14,
            drag = 1.6, gravity = vec3(0, -6, 0), cleanup_delay = 2.2,
        })
        sfx("hit_head")
    end
    if spider.node then spider.node:set_position(HIDE) end
    set_point(L.spider, HIDE, vec3(1, 1, 1), 0, 1)
    spider = nil
end
local function kill_scorp(scored)
    if not scorp then return end
    if scored then
        G.score = G.score + 1000
        flash(scorp.x, scorp.y, { 1.4, 1.2, 0.3 }, 45, 0.5, 8)
        pcall(particles.emit_burst, {
            position = vec3(scorp.x, scorp.y, 0.5), velocity = vec3(0, 1, 0),
            color_start = vec4(1, 0.9, 0.3, 1), color_end = vec4(0.5, 0.3, 0.05, 0),
            count = max(1, floor(60 * (G.pscale or 1))), size_min = 0.05, size_max = 0.18,
            life_min = 0.3, life_max = 0.8, spawn_radius = 0.35, velocity_strength = 15,
            drag = 1.5, gravity = vec3(0, -5, 0), cleanup_delay = 2.2,
        })
        sfx("hit_head")
    end
    if scorp.node then scorp.node:set_position(HIDE) end
    set_point(L.scorp, HIDE, vec3(1, 1, 1), 0, 1)
    scorp = nil
end

local function update_flea(dt)
    if not flea then return end
    flea.y = flea.y + flea.vy * dt
    flea.drop_acc = flea.drop_acc + abs(flea.vy) * dt
    -- leave mushrooms while descending
    if flea.drop_acc > CELL * 0.85 then
        flea.drop_acc = 0
        local c, r = world_to_cell(flea.x, flea.y)
        if r >= 0 and r < ROWS and (not mush_at(c, r) or (mush_at(c, r).hp or 0) <= 0) then
            if rand() < 0.55 then place_mush(c, r, 4, false) end
        end
    end
    if flea.node then
        flea.node:set_position(vec3(flea.x, flea.y, 0.5))
        flea.node:set_rotation(vec3(0, 0, sin(G.t * 20) * 0.3))
    end
    set_point(L.flea, vec3(flea.x, flea.y, 2.0), vec3(1.4, 0.8, 0.2), 22, 6)
    -- trail spores
    if rand() < 0.4 then
        pcall(particles.emit_burst, {
            position = vec3(flea.x, flea.y + 0.3, 0.4), velocity = vec3(0, 2, 0),
            color_start = vec4(1, 0.7, 0.2, 0.9), color_end = vec4(0.5, 0.3, 0.05, 0),
            count = max(1, floor(3 * (G.pscale or 1))), size_min = 0.03, size_max = 0.07,
            life_min = 0.2, life_max = 0.4, spawn_radius = 0.1, velocity_strength = 2,
            drag = 1.0, gravity = vec3(0, -2, 0), cleanup_delay = 1.0,
        })
    end
    if flea.y < -HH - 2 then kill_flea(false) end
end

local function update_spider(dt)
    if not spider then return end
    spider.zig = spider.zig + dt
    if spider.zig > rr(0.25, 0.55) then
        spider.zig = 0
        spider.vy = rr(-5.5, 5.5)
    end
    spider.x = spider.x + spider.vx * dt
    spider.y = spider.y + spider.vy * dt
    local _, _, ymin, ymax = player_limits()
    if spider.y < ymin then spider.y = ymin; spider.vy = abs(spider.vy) end
    if spider.y > ymax + CELL * 2 then spider.y = ymax + CELL * 2; spider.vy = -abs(spider.vy) end
    -- eat mushrooms
    local c, r = world_to_cell(spider.x, spider.y)
    local m = mush_at(c, r)
    if m and m.hp and m.hp > 0 and rand() < 0.08 then destroy_mush(c, r, false) end
    if spider.node then
        spider.node:set_position(vec3(spider.x, spider.y, 0.55))
        spider.node:set_rotation(vec3(0, 0, (spider.vx > 0) and -0.4 or 0.4))
        local sc = 1.3 + 0.08 * sin(G.t * 14)
        spider.node:set_scale(vec3(sc, sc, sc))
    end
    set_point(L.spider, vec3(spider.x, spider.y, 2.2), vec3(1.2, 0.2, 0.5), 20, 6)
    if spider.x < -HW - 3 or spider.x > HW + 3 then kill_spider(false) end
end

local function update_scorp(dt)
    if not scorp then return end
    scorp.x = scorp.x + scorp.vx * dt
    local c = world_to_cell(scorp.x, scorp.y)
    if c ~= scorp.last_c then
        scorp.last_c = c
        -- poison any mushroom on this row near the scorpion
        for dc = -1, 1 do
            local m = mush_at(c + dc, scorp.r)
            if m and m.hp and m.hp > 0 then poison_mush(c + dc, scorp.r) end
        end
    end
    if scorp.node then
        scorp.node:set_position(vec3(scorp.x, scorp.y, 0.5))
        scorp.node:set_rotation(vec3(0, 0, (scorp.vx > 0) and (-PI * 0.5) or (PI * 0.5)))
    end
    set_point(L.scorp, vec3(scorp.x, scorp.y, 2.0), vec3(1.3, 1.1, 0.25), 18, 7)
    -- venom drip particles
    if rand() < 0.35 then
        pcall(particles.emit_burst, {
            position = vec3(scorp.x, scorp.y - 0.2, 0.4), velocity = vec3(0, -1, 0),
            color_start = vec4(0.9, 0.2, 1.0, 1), color_end = vec4(0.4, 0.05, 0.5, 0),
            count = max(1, floor(4 * (G.pscale or 1))), size_min = 0.03, size_max = 0.07,
            life_min = 0.3, life_max = 0.55, spawn_radius = 0.15, velocity_strength = 2,
            drag = 1.0, gravity = vec3(0, -4, 0), cleanup_delay = 1.2,
        })
    end
    if scorp.x < -HW - 3 or scorp.x > HW + 3 then kill_scorp(false) end
end

local function update_bullets(dt)
    local i = 1
    while i <= #bullets do
        local b = bullets[i]
        local hit = false
        local total = BULLET_SPD * dt
        local nsteps = max(1, math.ceil(total / (CELL * 0.35)))
        for _ = 1, nsteps do
            b.y = b.y + total / nsteps
            -- enemies
            if flea and abs(flea.x - b.x) < 0.7 and abs(flea.y - b.y) < 0.7 then
                flea.hp = (flea.hp or 2) - 1
                if flea.hp <= 0 then kill_flea(true) else flea.vy = flea.vy * 2.2; sfx("hit_body"); flash(flea.x, flea.y, { 1.4, 0.8, 0.2 }, 20, 0.2, 4) end
                hit = true
            end
            if not hit and spider and abs(spider.x - b.x) < 0.85 and abs(spider.y - b.y) < 0.65 then kill_spider(true); hit = true end
            if not hit and scorp and abs(scorp.x - b.x) < 0.95 and abs(scorp.y - b.y) < 0.6 then kill_scorp(true); hit = true end
            if not hit and hit_test_bullet(b) then hit = true end
            if hit then break end
        end
        if b.node then b.node:set_position(vec3(b.x, b.y, 0.9)) end
        if b.glow then b.glow:set_position(vec3(b.x, b.y - 0.3, 0.8)) end
        if hit or b.y > HH + 2 then
            if b.node then b.node:set_position(HIDE) end
            if b.glow then b.glow:set_position(HIDE) end
            table.remove(bullets, i)
        else i = i + 1 end
    end
end

local function clear_enemies()
    kill_flea(false); kill_spider(false); kill_scorp(false)
    SPAWN.flea_cd, SPAWN.spider_cd, SPAWN.scorp_cd = 1.5, 5, 10
end

local function update_spawns(dt)
    SPAWN.flea_cd = SPAWN.flea_cd - dt
    SPAWN.spider_cd = SPAWN.spider_cd - dt
    SPAWN.scorp_cd = SPAWN.scorp_cd - dt
    -- flea when player-area mushrooms are scarce (classic: fewer than ~3)
    if not flea and SPAWN.flea_cd <= 0 and count_mush_in_player_area() < 3 then
        spawn_flea(); SPAWN.flea_cd = rr(4, 8)
    elseif SPAWN.flea_cd <= 0 then SPAWN.flea_cd = 1.0 end
    if not spider and SPAWN.spider_cd <= 0 then
        spawn_spider(); SPAWN.spider_cd = rr(6, 12) - min(G.level, 5) * 0.4
    end
    if not scorp and SPAWN.scorp_cd <= 0 and G.level >= 1 then
        spawn_scorpion(); SPAWN.scorp_cd = rr(12, 20) - min(G.level, 6) * 0.5
    end
end

------------------------------------------------------------------ collisions vs player
local function player_hit_check()
    if PL.invuln > 0 then return false end
    local pr = 0.45
    for _, w in ipairs(worms) do
        for _, s in ipairs(w.segs) do
            if abs(s.x - PL.x) < pr + 0.35 and abs(s.y - PL.y) < pr + 0.35 then return true end
        end
    end
    if flea and abs(flea.x - PL.x) < 0.55 and abs(flea.y - PL.y) < 0.55 then return true end
    if spider and abs(spider.x - PL.x) < 0.65 and abs(spider.y - PL.y) < 0.55 then return true end
    if scorp and abs(scorp.x - PL.x) < 0.8 and abs(scorp.y - PL.y) < 0.5 then return true end
    return false
end

------------------------------------------------------------------ ambient VFX
local function ambient_vfx(dt)
    -- floating spores / fireflies
    if rand() < 0.25 * (G.pscale or 1) then
        local x, y = rr(-HW, HW), rr(-HH, HH)
        pcall(particles.emit_burst, {
            position = vec3(x, y, 1.2), velocity = vec3(rr(-0.5, 0.5), rr(0.2, 1.0), 0),
            color_start = vec4(0.4, 1.0, 0.7, 0.9), color_end = vec4(0.1, 0.4, 0.25, 0),
            count = 1, size_min = 0.04, size_max = 0.09,
            life_min = 1.2, life_max = 2.4, spawn_radius = 0.05, velocity_strength = 0.5,
            drag = 0.3, gravity = vec3(0, 0.4, 0), cleanup_delay = 3.0,
        })
    end
    if rand() < 0.08 * (G.pscale or 1) then
        local x, y = rr(-HW, HW), rr(-HH, HH)
        pcall(particles.emit_burst, {
            position = vec3(x, y, 1.5), velocity = vec3(0, 0.5, 0),
            color_start = vec4(0.9, 0.5, 1.0, 0.85), color_end = vec4(0.3, 0.1, 0.4, 0),
            count = 1, size_min = 0.03, size_max = 0.07,
            life_min = 1.0, life_max = 2.0, spawn_radius = 0.05, velocity_strength = 0.3,
            drag = 0.2, gravity = vec3(0, 0.2, 0), cleanup_delay = 2.5,
        })
    end
end
------------------------------------------------------------------ UI
local HUD = "hud"
runtime_ui.show(HUD); runtime_ui.set_screen_overlay(HUD, true)
local NONE = { 0, 0, 0, 0 }
local GREEN = { 0.35, 1.0, 0.55, 1 }
local CYAN = { 0.4, 0.95, 1.0, 1 }
local MAG = { 0.95, 0.45, 1.0, 1 }
local GOLD = { 1.0, 0.85, 0.35, 1 }
local WHITE = { 0.9, 1.0, 0.95, 1 }
local cache = {}
local function upd(id, key, q)
    if cache[id] == key then return end
    cache[id] = key
    runtime_ui.set_quad(HUD, id, q)
end
local function text(id, label, x, y, w, h, fs, col, align, vis)
    vis = vis ~= false
    local key = tostring(label) .. "|" .. floor(x) .. "|" .. floor(y) .. "|" .. tostring(vis) .. "|" .. string.format("%.2f|%.2f", col[4] or 1, fs) .. (col[1] or 0) .. (col[2] or 0)
    upd(id, key, { x = x, y = y, w = w, h = h, z = 10, style = "text", label = label, fill = NONE, border = NONE,
        text_color = col, font_scale = fs, align_h = align or "center", align_v = "middle", no_input = true, visible = vis })
end
local function panel(id, x, y, w, h, vis, fill, border, z, input)
    vis = vis ~= false
    fill = fill or { 0.02, 0.05, 0.03, 0.7 }
    border = border or { 0.3, 0.9, 0.55, 0.5 }
    local key = floor(x) .. "|" .. floor(y) .. "|" .. floor(w) .. "|" .. floor(h) .. "|" .. tostring(vis) .. "|" .. table.concat(fill, ",")
    upd(id, key, { x = x, y = y, w = w, h = h, z = z or 5, style = "text", label = "", fill = fill, border = border,
        corner_radius = 14, no_input = not input, visible = vis })
end

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
        panel("mi_bg" .. i, x, y, w, h, v, sel and { 0.1, 0.55, 0.35, 0.4 } or { 0.02, 0.06, 0.04, 0.55 },
            sel and { 0.4, 1.0, 0.65, 0.95 } or { 0.3, 0.7, 0.45, 0.45 }, 20, true)
        text("mi_tx" .. i, v and it.label or "", x, y, w, h, (sel and 1.7 or 1.5) * s, sel and WHITE or { 0.7, 0.9, 0.8, 1 }, "center", v)
    end
end
local function ui_state(id) local ok, s = pcall(runtime_ui.get_state, HUD, id); if ok then return s end end
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

local banner = { t = 99, title = "", sub = "" }
local function show_banner(title, sub, life)
    banner.t, banner.title, banner.sub, banner.life = 0, title, sub or "", life or 1.8
end
local shake, SHAKE_SCALE = 0, 1
local function add_shake(a) shake = min(1.5, shake + a) end

local function draw_hud(dt)
    local s = SH / 1080
    local st = G.state
    local play = (st == "play" or st == "paused" or st == "clear" or st == "over" or st == "dying" or st == "levelintro")
    local title = st == "title"
    text("score", string.format("%06d", G.score), 36 * s, 16 * s, 360 * s, 54 * s, 1.7 * s, GREEN, "left", play or title)
    text("hiscore", "HI " .. string.format("%06d", G.hiscore), SW * 0.5 - 160 * s, 18 * s, 320 * s, 42 * s, 1.15 * s, GOLD, "center", play or title)
    text("lives", "BLADES  " .. tostring(G.lives), SW - 340 * s, 16 * s, 300 * s, 50 * s, 1.35 * s, CYAN, "right", play)
    text("level", "WAVE " .. G.level, SW - 340 * s, 58 * s, 300 * s, 36 * s, 1.05 * s, { 0.6, 0.85, 0.7, 0.85 }, "right", play)
    panel("tpanel", SW * 0.5 - 500 * s, SH * 0.08, 1000 * s, SH * 0.72, title, { 0.01, 0.04, 0.02, 0.62 }, { 0.3, 0.95, 0.55, 0.5 }, 4, false)
    text("title", "C E N T I P E D E", 0, SH * 0.14, SW, 110 * s, 4.0 * s, GREEN, "center", title)
    text("title2", "REMIX", 0, SH * 0.24, SW, 80 * s, 2.8 * s, { 0.55 + 0.1 * sin(G.t * 2), 1.0, 0.75, 1 }, "center", title)
    text("tsub", "HIGH SCORE  " .. G.hiscore, 0, SH * 0.36, SW, 50 * s, 1.35 * s, GOLD, "center", title)
    text("thint", "MOUSE trackball  ·  WASD / ARROWS  ·  CLICK / SPACE fire", 0, SH * 0.86, SW, 40 * s, 0.95 * s, { 0.6, 0.85, 0.7, 0.85 }, "center", title)
    local pause = st == "paused"
    local over = st == "over"
    panel("dim", 0, 0, SW, SH, pause or over, { 0, 0.02, 0.01, 0.5 }, NONE, 2, false)
    text("pause", "PAUSED", 0, SH * 0.25, SW, 120 * s, 4.0 * s, CYAN, "center", pause)
    text("over", "GAME  OVER", 0, SH * 0.22, SW, 140 * s, 4.5 * s, MAG, "center", over)
    text("over2", (G.newhi and "NEW HIGH SCORE  " or "FINAL SCORE  ") .. G.score, 0, SH * 0.36, SW, 70 * s, 1.8 * s, GOLD, "center", over)
    draw_menu(title or pause or over, title and SH * 0.46 or SH * 0.48)
    local bvis = banner.t < (banner.life or 1.8)
    local ba = bvis and (1 - clamp(banner.t / (banner.life or 1.8), 0, 1)) or 0
    text("ban1", banner.title or "", 0, SH * 0.40, SW, 90 * s, 3.0 * s, { GREEN[1], GREEN[2], GREEN[3], ba }, "center", bvis)
    text("ban2", banner.sub or "", 0, SH * 0.48, SW, 50 * s, 1.4 * s, { CYAN[1], CYAN[2], CYAN[3], ba * 0.9 }, "center", bvis)
end

------------------------------------------------------------------ settings
local SET = nil
do
    local src = fs.read("Scripts/Lib/settings_menu.lua")
    if src then
        local ok, mod = pcall(function() return load(src, "@settings_menu.lua")() end)
        if ok and mod then
            local ok2, s = pcall(mod.new, { title = "SETTINGS", file = "Save/settings.cfg", click = function() sfx("click") end,
                music = false, defaults = { master = 0.5 },
                theme = { accent = { 0.3, 0.95, 0.55, 1 }, accent2 = { 0.85, 0.4, 1.0, 1 } } })
            if ok2 then SET = s else pe_log("[Centipede] settings menu init failed: " .. tostring(s)) end
        else pe_log("[Centipede] settings menu load failed: " .. tostring(mod)) end
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
local WATCH = { "Left", "Right", "A", "D", "Up", "Down", "W", "S", "Space", "Return", "Escape", "P", "M", "O" }
local function latch() for _, k in ipairs(WATCH) do prev[k] = kdown(k) end end
local mouse_prev_down, mouse_last = false, nil
local function mouse_clicked()
    local ok, d = pcall(input.is_left_mouse_down); d = ok and d
    local c = d and not mouse_prev_down; mouse_prev_down = d
    return c or G.vkeys.Click
end
local function mouse_down() local ok, d = pcall(input.is_left_mouse_down); return (ok and d) or G.vkeys.Click end

-- screen mouse -> world on the playfield plane (z=0), perspective-correct
local function mouse_world(mx, my)
    local C = cam:get_position()
    local fx, fy, fz = CAM_LOOK.x - C.x, CAM_LOOK.y - C.y, CAM_LOOK.z - C.z
    local fl = sqrt(fx * fx + fy * fy + fz * fz) + 1e-6
    local depth = ((0 - C.x) * fx + (0 - C.y) * fy + (0 - C.z) * fz) / fl
    -- also account for look-at y
    depth = ((0 - C.x) * fx + ((CAM_LOOK.y) - C.y) * fy + (0 - C.z) * fz) / fl
    local ndcx = (mx / SW) * 2 - 1
    local ndcy = 1 - (my / SH) * 2
    local aspect = SW / max(SH, 1)
    local x = C.x + ndcx * depth * math.tan(FOVX * 0.5)
    -- approximate y with vertical FOV
    local fovy = 2 * math.atan(math.tan(FOVX * 0.5) / aspect)
    local y = C.y + ndcy * depth * math.tan(fovy * 0.5)
    return x, y
end

------------------------------------------------------------------ hiscore
local HISAVE = "Save/hiscore.txt"
do
    local ok, data = pcall(fs.read, HISAVE)
    if ok and data then G.hiscore = tonumber(data) or 0 end
end
local function save_hi()
    if G.score > G.hiscore then G.hiscore = G.score; G.newhi = true end
    pcall(fs.write, HISAVE, tostring(G.hiscore))
end

------------------------------------------------------------------ game flow
local function reset_wave(full_seed)
    clear_bullets(); clear_worms(); clear_enemies()
    if full_seed then seed_mushrooms(35 + G.level * 3) end
    local len = min(12 + G.level - 1, 18)
    spawn_centipede(len, floor(COLS / 2), 0, (G.level % 2 == 0) and 1 or -1)
    -- later waves: extra solo heads
    for i = 1, min(G.level - 1, 4) do
        spawn_centipede(1, floor(rr(2, COLS - 3)), i, (rand() < 0.5) and 1 or -1)
    end
    SPAWN.flea_cd, SPAWN.spider_cd, SPAWN.scorp_cd = 2.0, rr(4, 7), rr(9, 14)
    PL.x, PL.y = 0, -HH + CELL * 1.5
    PL.vx, PL.vy, PL.fire_cd, PL.invuln = 0, 0, 0, 1.5
    show_banner("WAVE " .. G.level, len .. " SEGMENTS", 2.0)
end

local function new_game()
    G.score, G.lives, G.level, G.newhi = 0, 3, 1, false
    clear_mushrooms()
    reset_wave(true)
    G.state = "levelintro"; G.intro_t = 0
end

local function to_title()
    G.state = "title"
    set_menu("title", { { label = "PLAY", act = "play" }, { label = "SETTINGS", act = "settings" }, { label = "QUIT", act = "quit" } })
    G.demo = true
    clear_bullets(); clear_worms(); clear_enemies()
    if count_mush_in_player_area() + 1 == 1 then end  -- noop keep linter quiet
    -- attract: light mushroom field + a wandering centipede
    local total = 0
    for r = 0, ROWS - 1 do for c = 0, COLS - 1 do local m = mush_at(c, r); if m and m.hp and m.hp > 0 then total = total + 1 end end end
    if total < 10 then seed_mushrooms(40) end
    if worms_remaining() == 0 then spawn_centipede(10, floor(COLS / 2), 0, 1) end
    PL.x, PL.y = 0, -HH + CELL * 1.5
end

local function kill_player()
    G.state = "dying"; G.die_t = 0
    sfx("die"); add_shake(0.8)
    flash(PL.x, PL.y, { 0.4, 1.0, 0.8 }, 50, 0.6, 10)
    pcall(particles.emit_burst, {
        position = vec3(PL.x, PL.y, 0.6), velocity = vec3(0, 2, 0),
        color_start = vec4(0.4, 1, 0.9, 1), color_end = vec4(0.1, 0.3, 0.3, 0),
        count = max(1, floor(70 * (G.pscale or 1))), size_min = 0.05, size_max = 0.2,
        life_min = 0.3, life_max = 0.9, spawn_radius = 0.3, velocity_strength = 16,
        drag = 1.5, gravity = vec3(0, -4, 0), cleanup_delay = 2.5,
    })
    clear_bullets(); clear_enemies()
end

local function after_death()
    G.lives = G.lives - 1
    restore_damaged_mushrooms()
    if G.lives <= 0 then
        sfx("gameover"); save_hi()
        G.state = "over"
        set_menu("over", { { label = "PLAY AGAIN", act = "play" }, { label = "TITLE", act = "title" } })
    else
        clear_worms()
        local len = min(12 + G.level - 1, 18)
        spawn_centipede(len, floor(COLS / 2), 0, 1)
        PL.x, PL.y = 0, -HH + CELL * 1.5
        PL.invuln = 2.0
        G.state = "play"
        show_banner("BLADE LOST", G.lives .. " LEFT", 1.5)
    end
end

local function next_level()
    G.level = G.level + 1
    sfx("level")
    -- bonus: remaining mushrooms
    local bonus = 0
    for r = 0, ROWS - 1 do for c = 0, COLS - 1 do
        local m = mush_at(c, r); if m and m.hp and m.hp > 0 then bonus = bonus + m.hp end
    end end
    G.score = G.score + bonus
    reset_wave(false)
    -- sprinkle a few more mushrooms
    for _ = 1, 8 do
        local c, r = floor(rr(0, COLS - 0.01)), floor(rr(1, ROWS - PLAYER_ROWS - 0.01))
        if not mush_at(c, r) or (mush_at(c, r).hp or 0) <= 0 then place_mush(c, r, 4, false) end
    end
    G.state = "levelintro"; G.intro_t = 0
    if G.score >= 10000 and not G.extra_given then
        G.extra_given = true; G.lives = G.lives + 1; sfx("extra")
        show_banner("EXTRA BLADE", "10000 PTS", 2.0)
    end
end
------------------------------------------------------------------ player control (trackball-like mouse + keyboard)
local function update_player(dt, control)
    PL.fire_cd = max(0, PL.fire_cd - dt)
    PL.invuln = max(0, PL.invuln - dt)
    local xmin, xmax, ymin, ymax = player_limits()
    if control == "auto" then
        -- attract: drift and shoot
        PL.x = lerp(PL.x, sin(G.t * 0.7) * HW * 0.6, 1 - math.exp(-dt * 3))
        PL.y = lerp(PL.y, ymin + CELL * 1.2 + sin(G.t * 0.9) * CELL, 1 - math.exp(-dt * 2))
        if rand() < 0.04 then fire_bullet() end
    elseif control == "player" then
        local ok, mp = pcall(input.get_mouse_position)
        if ok and mp and mp.x then
            if mouse_last and (abs(mp.x - mouse_last.x) + abs(mp.y - mouse_last.y)) > 0.5 then G.use_mouse = true end
            mouse_last = { x = mp.x, y = mp.y }
            if G.use_mouse then
                local wx, wy = mouse_world(mp.x, mp.y)
                -- trackball feel: smooth chase toward mouse world pos
                PL.x = lerp(PL.x, clamp(wx, xmin, xmax), 1 - math.exp(-dt * 14))
                PL.y = lerp(PL.y, clamp(wy, ymin, ymax), 1 - math.exp(-dt * 14))
            end
        end
        local kx = ((kdown("Right") or kdown("D")) and 1 or 0) - ((kdown("Left") or kdown("A")) and 1 or 0)
        local ky = ((kdown("Up") or kdown("W")) and 1 or 0) - ((kdown("Down") or kdown("S")) and 1 or 0)
        if kx ~= 0 or ky ~= 0 then
            G.use_mouse = false
            local spd = 16
            PL.x = clamp(PL.x + kx * spd * dt, xmin, xmax)
            PL.y = clamp(PL.y + ky * spd * dt, ymin, ymax)
        end
        if mouse_down() or kdown("Space") then fire_bullet() end
    end
    PL.x = clamp(PL.x, xmin, xmax)
    PL.y = clamp(PL.y, ymin, ymax)
    -- blink when invulnerable
    if PL.node then
        local vis = (PL.invuln <= 0) or (floor(G.t * 12) % 2 == 0)
        if not vis then PL.node:set_position(HIDE) else draw_player() end
    else draw_player() end
end

------------------------------------------------------------------ visuals tick
local function update_visuals(dt)
    update_flashes(dt)
    update_mush_visuals(dt)
    ambient_vfx(dt)
    -- frame glow pulse
    for _, n in ipairs(G.frame_glow or {}) do
        local k = 1.1 + 0.35 * sin(G.t * 2.2)
        mlive(n, "emissive", vec3(0.3 * k, 1.4 * k, 0.85 * k))
    end
    -- key lights drift
    set_point(L.key_l, vec3(-HW - 3 + sin(G.t * 0.4) * 3, 8 + cos(G.t * 0.35) * 3, 14), vec3(0.2, 0.9, 0.55), 75, 55)
    set_point(L.key_r, vec3(HW + 3 + cos(G.t * 0.38) * 3, 8 + sin(G.t * 0.32) * 3, 14), vec3(0.75, 0.35, 1.0), 65, 55)
    -- camera shake + gentle follow
    shake = max(0, shake - dt * 2.2)
    local sk = shake * shake * SHAKE_SCALE
    local ox = (sin(G.t * 47) + sin(G.t * 31.7) * 0.5) * 0.45 * sk
    local oy = (cos(G.t * 41) + sin(G.t * 23.3) * 0.5) * 0.45 * sk
    G.cam_px = lerp(G.cam_px or 0, PL.x * 0.05, 1 - math.exp(-dt * 3))
    G.cam_py = lerp(G.cam_py or 0, PL.y * 0.03, 1 - math.exp(-dt * 3))
    if shake < 0.02 then ox, oy = 0, 0 end
    cam:set_position(vec3(CAM_BASE.x + G.cam_px + ox, CAM_BASE.y + G.cam_py + oy, CAM_BASE.z))
    cam:look_at(vec3(CAM_LOOK.x + G.cam_px * 0.5, CAM_LOOK.y + G.cam_py * 0.4, CAM_LOOK.z))
    banner.t = banner.t + dt
    if G.score > G.hiscore then G.hiscore = G.score end
end

local function play_tick_one(dt, control)
    update_player(dt, control)
    update_worms(dt)
    update_bullets(dt)
    update_flea(dt); update_spider(dt); update_scorp(dt)
    if control == "player" or control == "auto" then update_spawns(dt) end
    if control == "player" and player_hit_check() then kill_player() end
end
local function play_tick(dt, control)
    local n = max(1, math.ceil(dt / (1 / 60)))
    for _ = 1, n do
        play_tick_one(dt / n, control)
        if G.state ~= "play" and G.state ~= "title" then break end
    end
end

local function do_menu_action(act)
    sfx("click")
    if act == "play" then
        runtime_ui.show(HUD); new_game()
    elseif act == "resume" then
        G.state = G.paused_from or "play"
    elseif act == "settings" then
        if SET then
            G.in_settings = true
            SET:open(function() G.in_settings = false end)
        end
    elseif act == "title" then
        save_hi(); to_title()
    elseif act == "quit" then
        save_hi(); pcall(engine.quit)
    end
end

local function update(dt)
    dt = min(dt, 0.25)
    G.t = G.t + dt
    local okS, sz = pcall(runtime_ui.get_surface_size)
    if okS and sz and (sz.width or 0) > 0 and (sz.width ~= SW or sz.height ~= SH) then SW, SH = sz.width, sz.height; cache = {}; CAM_BASE = vec3(0, -0.3, fit_dist()) end
    flush_mats()
    if G.state == "boot" then
        G.boot = (G.boot or 0) + 1
        if G.boot == 3 then
            paint_templates()
            if SET then pcall(SET.apply, SET) end
            -- re-assert TAA+bloom after settings apply (HIGH baseline)
            S("taa", true); S("cas_sharpening", false); S("motion_blur", false)
            S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.4); S("fxaa", false)
            to_title()
            pe_log("[Centipede] ready")
        end
        return
    end
    if SET then
        G.pscale = SET:particle_scale() or 1; SHAKE_SCALE = SET:shake_scale() or 1
        if SET:update(dt) then latch(); mouse_clicked(); update_visuals(dt); draw_hud(dt); return end
    end
    local ok, mp = pcall(input.get_mouse_position)
    G.mouse_moved = ok and mp and G._mx and (abs(mp.x - G._mx) + abs(mp.y - G._my) > 1) or false
    if ok and mp then G._mx, G._my = mp.x, mp.y end
    G.click = mouse_clicked()
    if pressed("M") then if SET then SET:toggle_mute() end end
    if pressed("O") and SET and not SET:is_open() then
        G.in_settings = true; SET:open(function() G.in_settings = false end)
    end

    local st = G.state
    if st == "title" then
        local act = menu_input(pressed)
        if act then do_menu_action(act) end
        if G.state == "title" then
            play_tick(dt, "auto")
            if worms_remaining() == 0 then spawn_centipede(10, floor(rr(2, COLS - 3)), 0, 1) end
        end
    elseif st == "levelintro" then
        G.intro_t = (G.intro_t or 0) + dt
        update_player(dt, "player"); draw_player()
        if G.intro_t > 1.4 then G.state = "play" end
    elseif st == "play" then
        if pressed("Escape") or pressed("P") then
            G.paused_from = st; G.state = "paused"; sfx("click")
            set_menu("pause", { { label = "RESUME", act = "resume" }, { label = "SETTINGS", act = "settings" }, { label = "QUIT TO TITLE", act = "title" } })
        else
            play_tick(dt, G.autoplay and "auto" or "player")
            if G.state == "play" and worms_remaining() == 0 then
                G.state = "clear"; G.clear_t = 0
                show_banner("WAVE CLEARED", "BONUS MUSHROOMS", 2.0)
                -- celebration spores
                for k = 1, 8 do
                    local x, y = rr(-HW + 1, HW - 1), rr(-HH + 2, HH - 2)
                    pcall(particles.emit_burst, {
                        position = vec3(x, y, 0.8), velocity = vec3(0, 3, 0),
                        color_start = vec4(0.4, 1, 0.7, 1), color_end = vec4(0.2, 0.5, 0.3, 0),
                        count = max(1, floor(35 * (G.pscale or 1))), size_min = 0.05, size_max = 0.16,
                        life_min = 0.4, life_max = 1.0, spawn_radius = 0.4, velocity_strength = 10,
                        drag = 1.2, gravity = vec3(0, -3, 0), cleanup_delay = 2.5,
                    })
                end
                add_shake(0.35); sfx("level")
            end
        end
    elseif st == "paused" then
        if pressed("Escape") or pressed("P") then G.state = G.paused_from or "play"
        else local act = menu_input(pressed); if act then do_menu_action(act) end end
        draw_player()
    elseif st == "dying" then
        G.die_t = (G.die_t or 0) + dt
        update_worms(min(dt, 0.05) * 0.3)
        if G.die_t > 1.6 then after_death() end
    elseif st == "clear" then
        G.clear_t = (G.clear_t or 0) + dt
        update_player(dt, "player"); draw_player()
        if G.clear_t > 2.2 then next_level() end
    elseif st == "over" then
        local act = menu_input(pressed)
        if act then do_menu_action(act) end
        draw_player()
    end
    update_visuals(dt)
    draw_hud(dt)
    latch()
end

local function init()
    build_world(); build_lights(); build_player()
    pcall(audio.set_master_volume, 0.5)
    G.state = "boot"; G.pscale = 1
end
init()
hooks { update = update }

-- MCP automation helpers
function G.sim(sec, keys)
    G.vkeys = keys or {}
    for _ = 1, floor(sec * 60) do update(1 / 60) end
    G.vkeys = {}
    return G.state .. " score=" .. G.score .. " lives=" .. G.lives .. " wave=" .. G.level .. " segs=" .. worms_remaining()
end
G.SET = SET; G.new_game = new_game; G.to_title = to_title
G.spawn_centipede = spawn_centipede; G.spawn_flea = spawn_flea; G.spawn_spider = spawn_spider; G.spawn_scorpion = spawn_scorpion
function G.shot_setup()
    clear_bullets(); clear_worms(); clear_enemies()
    seed_mushrooms(42)
    spawn_centipede(12, 12, 7, 1)
    spawn_centipede(7, 4, 11, -1)
    PL.x, PL.y = 2, -HH + CELL * 2.2
    PL.invuln = 8
    G.state = "play"
    spawn_spider(); spawn_flea(); spawn_scorpion()
    return "ok segs=" .. worms_remaining()
end
function G.dbg() local b = bullets[1]; return #bullets .. " " .. (b and string.format("%.2f,%.2f", b.x, b.y) or "-") .. " PL " .. string.format("%.2f,%.2f", PL.x, PL.y) end
