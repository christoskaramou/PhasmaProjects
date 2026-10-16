-- FROGGER REMIX  (PhasmaEngine, Lua)
-- A modernized remake of Konami's Frogger (1981). Faithful core rules:
--   5 traffic lanes, a safe median, 5 river lanes of logs and (diving) turtles, five home bays,
--   a countdown timer per frog, 3 lives (+1 at 10,000), 10 pts per new row, 50 per frog home (+10 per
--   half-second left), 1000 for filling all five bays, bonus flies, and levels that speed everything up.
-- Modern look: procedural PBR meshes (cooked with PhasmaCook, cloned from .pescene templates), a lit
--   twilight road with dynamic headlights, glossy scrolling water, bloom and dense particle VFX.
local PI, TAU = math.pi, math.pi * 2
local sin, cos, sqrt, rand, floor, abs, min, max = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function smooth(t) t = clamp(t, 0, 1); return t * t * (3 - 2 * t) end
local G = { state = "boot", t = 0 }
_G.FR = G

------------------------------------------------------------------ deferred materials
-- Engine quirk: material writes in the same frame a node is created are ignored, so every
-- write is applied now AND replayed a couple of frames later.
local _mset, _mtex = material.set, material.set_texture
local mat_q = {}
local function qpush(f) mat_q[#mat_q + 1] = { f = f, n = 0 } end
local function mset(n, k, v) pcall(_mset, n, k, v); qpush(function() pcall(_mset, n, k, v) end) end
local function mtex(n, k, v) qpush(function() pcall(_mtex, n, k, v) end) end
local function flush_mats()
    for i = #mat_q, 1, -1 do
        local q = mat_q[i]; q.n = q.n + 1
        if q.n == 2 or q.n == 8 then q.f() end
        if q.n >= 8 then table.remove(mat_q, i) end
    end
end
local function mlive(n, k, v) pcall(_mset, n, k, v) end
local function paint(n, base, emis, rough, metal)
    if not n then return end
    mset(n, "base_color", vec4(base[1], base[2], base[3], 1))
    mset(n, "emissive", vec3(emis[1], emis[2], emis[3]))
    mset(n, "roughness", rough or 0.5)
    mset(n, "metallic", metal or 0.0)
end

------------------------------------------------------------------ audio
local SET -- settings menu (created at init)
local function sfx(name) pcall(audio.play, name .. ".wav") end

------------------------------------------------------------------ input (edge detection; raw keys while UI is up)
local keys_prev, keys_now = {}, {}
G.vkeys = {}
local WATCH = { "Up", "Down", "Left", "Right", "W", "A", "S", "D", "Space", "Return", "Escape", "P", "O", "M", "R", "Q", "F1" }
local function rawdown(k)
    if G.vkeys[k] then return true end
    local ok, v = pcall(input.is_key_down_raw, k)
    if ok and v ~= nil then return v end
    return input.is_key_pressed(k)
end
local function poll_keys() for _, k in ipairs(WATCH) do keys_now[k] = rawdown(k) end end
local function held(k) return keys_now[k] end
local function pressed(...)
    for _, k in ipairs({ ... }) do if keys_now[k] and not keys_prev[k] then return true end end
    return false
end
local function latch_keys() for _, k in ipairs(WATCH) do keys_prev[k] = keys_now[k] end end

------------------------------------------------------------------ playfield constants
local COLS_HALF = 6          -- columns -6..6
local ROW_HOME = 12
local LOOP = 30              -- lane wrap length (objects live in [-15,15])
local HOP_T = 0.17           -- hop duration (s), arcade-like (~0.15-0.2 s)
local HOP_H = 0.42           -- hop arc height
local TIME_PER_FROG = 40.0
local BAYS = { -5.0, -2.5, 0.0, 2.5, 5.0 }
local HIDE = vec3(0, -1000, 0)
local function rowz(r) return -r end

------------------------------------------------------------------ render setup
local function S(k, v) pcall(settings.set, k, v) end
local function setup_render()
    local ss = scene.add_empty_node("FroggerSceneSettings"); ss:set_scene_settings(true)
    pcall(settings.set_render_mode, "raster")
    pcall(skybox.load, "twilight.hdr")
    S("taa", true); S("motion_blur", false)          -- TAA on (RENDER_SETTINGS.md); motion blur smears bloom
    S("hdr", true)             -- R16F targets: bloom survives TAA
    S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.25)   -- weaker + smooth (no stair-steps)
    S("tonemapping", true); S("fxaa", false); S("cas_sharpening", false)  -- CAS overwrites bloom when TAA is on
    S("ssao", true); S("ssao_radius", 0.5); S("ssao_intensity", 1.0)
    S("ssr", true); S("dof", false)
    S("fog", true); S("fog_density", 0.012); S("fog_start", 22.0)
    S("shadows", true); S("shadow_map_size", 2048); S("shadow_distance", 45.0)
    S("render_scale", 1.0)
    S("IBL", true); S("IBL_intensity", 0.9)
    S("color_grading", true); S("color_grading_saturation", 1.18); S("color_grading_contrast", 1.08)
end

------------------------------------------------------------------ templates -> clones
local TPL = {}
local function tpl(name)
    if TPL[name] then return TPL[name] end
    local n = scene.find_model(name)
    if not n then pe_log("[Frogger] missing template " .. name); return nil end
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
local function empty(name, pos, parent)
    seq = seq + 1
    local n = scene.add_empty_node(name .. "_e" .. seq)
    if parent then n:set_parent(parent) end
    n:set_position(pos or vec3(0, 0, 0))
    return n
end
local function tpaint(name, ...) local t = tpl(name); if t then paint(t.node, ...) end end
local function ttex(name, kind, file) local t = tpl(name); if t then mtex(t.node, kind, "Textures/" .. file) end end
local DEG = 180 / PI
local function setrot(n, x, y, z) n:set_rotation(vec3((x or 0) * DEG, (y or 0) * DEG, (z or 0) * DEG)) end

------------------------------------------------------------------ materials (per template mesh)
local LANE_KIND = { [1] = "sedan", [2] = "dozer", [3] = "sedan", [4] = "racer", [5] = "truck" }
local LANE_PAINT = {
    [1] = { 1.0, 0.72, 0.05 },   -- yellow sedan (taxi)
    [2] = { 0.95, 0.42, 0.04 },  -- orange bulldozer
    [3] = { 0.9, 0.08, 0.45 },   -- magenta sedan
    [4] = { 0.92, 0.95, 1.0 },   -- white racer
    [5] = { 0.75, 0.05, 0.06 },  -- red truck cab
}
local function setup_materials()
    -- frog: vivid lime body with dark spots, cream belly, golden eyes that glow a touch
    tpaint("T_frog_body", { 0.22, 0.85, 0.12 }, { 0.01, 0.05, 0.0 }, 0.32, 0.0)
    ttex("T_frog_body", "base_color", "frogskin.png")
    tpaint("T_frog_legb", { 0.2, 0.78, 0.1 }, { 0.01, 0.04, 0.0 }, 0.35, 0.0)
    tpaint("T_frog_legf", { 0.2, 0.78, 0.1 }, { 0.01, 0.04, 0.0 }, 0.35, 0.0)
    tpaint("T_frog_spots", { 0.04, 0.3, 0.05 }, { 0, 0, 0 }, 0.4, 0.0)
    tpaint("T_frog_belly", { 0.95, 0.9, 0.55 }, { 0.03, 0.03, 0.01 }, 0.5, 0.0)
    tpaint("T_frog_eye", { 1.0, 0.78, 0.1 }, { 0.5, 0.32, 0.0 }, 0.08, 0.0)
    tpaint("T_frog_pupil", { 0.01, 0.01, 0.01 }, { 0, 0, 0 }, 0.05, 0.0)
    -- vehicles: clear-coat paint, dark tinted glass, chrome, emissive lights
    for lane = 1, 5 do
        local c = LANE_PAINT[lane]
        tpaint("T_L" .. lane .. "_body", c, { c[1] * 0.02, c[2] * 0.02, c[3] * 0.02 }, 0.18, 0.45)
        tpaint("T_L" .. lane .. "_glass", { 0.03, 0.05, 0.08 }, { 0.0, 0.01, 0.02 }, 0.04, 0.9)
        tpaint("T_L" .. lane .. "_dark", { 0.035, 0.035, 0.04 }, { 0, 0, 0 }, 0.7, 0.0)
        tpaint("T_L" .. lane .. "_chrome", { 0.9, 0.9, 0.92 }, { 0, 0, 0 }, 0.12, 1.0)
        tpaint("T_L" .. lane .. "_head", { 1.0, 0.95, 0.8 }, { 7.0, 6.4, 5.0 }, 0.1, 0.0)
        tpaint("T_L" .. lane .. "_tail", { 1.0, 0.05, 0.03 }, { 5.0, 0.25, 0.12 }, 0.2, 0.0)
    end
    tpaint("T_L5_trailer", { 0.85, 0.87, 0.9 }, { 0.01, 0.01, 0.01 }, 0.3, 0.6)
    -- logs, turtles
    for _, s in ipairs({ "s", "m", "l" }) do
        tpaint("T_log_" .. s, { 0.85, 0.75, 0.65 }, { 0, 0, 0 }, 0.8, 0.0)
        ttex("T_log_" .. s, "base_color", "bark.png"); ttex("T_log_" .. s, "normal", "bark_n.png")
        tpaint("T_log_" .. s .. "_end", { 1, 1, 1 }, { 0.02, 0.012, 0.004 }, 0.7, 0.0)
        ttex("T_log_" .. s .. "_end", "base_color", "logend.png")
    end
    tpaint("T_turtle_shell", { 1.0, 1.0, 1.0 }, { 0, 0, 0 }, 0.25, 0.1)
    ttex("T_turtle_shell", "base_color", "shell.png")
    tpaint("T_turtle_rim", { 0.75, 0.6, 0.25 }, { 0, 0, 0 }, 0.4, 0.0)
    tpaint("T_turtle_body", { 0.25, 0.55, 0.32 }, { 0, 0.01, 0 }, 0.5, 0.0)
    tpaint("T_turtle_eye", { 0.02, 0.02, 0.02 }, { 0, 0, 0 }, 0.1, 0.0)
    -- home bays
    tpaint("T_lily_pad", { 0.15, 0.55, 0.12 }, { 0.0, 0.03, 0.0 }, 0.3, 0.0)
    tpaint("T_lotus", { 1.0, 0.55, 0.8 }, { 0.6, 0.15, 0.35 }, 0.4, 0.0)
    tpaint("T_lotus_core", { 1.0, 0.9, 0.3 }, { 3.0, 2.2, 0.4 }, 0.3, 0.0)
    tpaint("T_fly_body", { 0.1, 0.1, 0.12 }, { 0.2, 0.5, 0.2 }, 0.3, 0.5)
    tpaint("T_fly_wing", { 0.7, 1.0, 0.9 }, { 1.6, 3.0, 2.2 }, 0.1, 0.0)
    -- environment
    tpaint("T_road", { 1, 1, 1 }, { 0, 0, 0 }, 0.62, 0.0)
    ttex("T_road", "base_color", "asphalt.png"); ttex("T_road", "normal", "asphalt_n.png")
    tpaint("T_walk", { 1, 1, 1 }, { 0, 0, 0 }, 0.75, 0.0)
    ttex("T_walk", "base_color", "pavement.png"); ttex("T_walk", "normal", "pavement_n.png")
    tpaint("T_water", { 0.45, 0.7, 1.0 }, { 0.0, 0.03, 0.06 }, 0.08, 0.35)
    ttex("T_water", "base_color", "water.png"); ttex("T_water", "normal", "water_n.png")
    tpaint("T_grass", { 1, 1, 1 }, { 0, 0, 0 }, 0.9, 0.0)
    ttex("T_grass", "base_color", "grass.png")
    tpaint("T_curb", { 0.6, 0.6, 0.62 }, { 0, 0, 0 }, 0.6, 0.0)
    tpaint("T_bank_wall", { 1, 1, 1 }, { 0, 0, 0 }, 0.85, 0.0)
    ttex("T_bank_wall", "base_color", "stone.png")
    tpaint("T_hedge", { 0.12, 0.42, 0.1 }, { 0.0, 0.015, 0.0 }, 0.75, 0.0)
    ttex("T_hedge", "base_color", "grass.png")
    tpaint("T_bay_stone", { 0.55, 0.52, 0.5 }, { 0, 0, 0 }, 0.7, 0.0)
    ttex("T_bay_stone", "base_color", "stone.png")
    tpaint("T_lamp_pole", { 0.08, 0.09, 0.1 }, { 0, 0, 0 }, 0.35, 0.9)
    tpaint("T_lamp_bulb", { 1.0, 0.8, 0.5 }, { 9.0, 6.0, 2.6 }, 0.2, 0.0)
    tpaint("T_tuft", { 0.2, 0.55, 0.12 }, { 0, 0.01, 0 }, 0.8, 0.0)
    tpaint("T_refl_lamp", { 0.3, 0.2, 0.1 }, { 1.1, 0.55, 0.18 }, 0.1, 0.0)
    tpaint("T_refl_moon", { 0.2, 0.25, 0.3 }, { 0.42, 0.52, 0.8 }, 0.1, 0.0)
    local bc = { a = { 1.0, 0.85, 0.6 }, b = { 0.6, 0.85, 1.0 }, c = { 1.0, 0.5, 0.85 } }
    for k, c in pairs(bc) do
        tpaint("T_bldg_" .. k, { 0.06, 0.06, 0.08 }, { c[1] * 1.3, c[2] * 1.3, c[3] * 1.3 }, 0.5, 0.3)
        ttex("T_bldg_" .. k, "emissive", "windows.png")
    end
end

------------------------------------------------------------------ lights
-- Engine quirk: point lights own a scene node and Scene::UpdateLights() copies the node's world position
-- over the light every frame, so lights.set_point_light(pos) alone never moves a light. Move the node instead.
local LNODE = {}
local function set_point(idx, pos, col, inten, rad)
    lights.set_point_light(idx, pos, col, inten, rad)
    local n = LNODE[idx]
    if n then n:set_position(pos) end
end
local function new_point(pos, col, inten, rad)
    lights.add_point()
    local all = lights.get_point_lights()
    local idx = #all - 1
    local nm = all[#all] and all[#all].name
    if nm then LNODE[idx] = scene.find_model(nm) end
    set_point(idx, pos or HIDE, col or vec3(1, 1, 1), inten or 0, rad or 1)
    return idx
end

------------------------------------------------------------------ static world
local WORLD = { lamps = {}, bays = {} }
local function build_world()
    clone("T_grass", vec3(0, -0.02, 7.0))                         -- near verge
    clone("T_walk", vec3(0, 0.02, 0))                             -- start sidewalk (row 0)
    clone("T_curb", vec3(0, 0.05, -0.5))
    clone("T_road", vec3(0, 0.0, -3))
    clone("T_curb", vec3(0, 0.05, -5.5))
    clone("T_walk", vec3(0, 0.02, -6))                            -- median (row 6)
    clone("T_bank_wall", vec3(0, 0, -6.62))
    WORLD.water = clone("T_water", vec3(0, -0.3, -9.2))
    local fw = clone("T_bank_wall", vec3(0, 0.12, -11.58)); setrot(fw, 0, PI, 0)
    clone("T_grass", vec3(0, 0.12, -18.5))                        -- far bank
    -- home row: hedges between bays, little ponds with lily pads in each bay
    for _, x in ipairs({ -12.4, -10.8, -9.2, -7.6, 7.6, 9.2, 10.8, 12.4 }) do clone("T_hedge", vec3(x, 0.1, -12.1), vec3(1, 1.1, 1.25)) end
    for i = 1, 4 do clone("T_hedge", vec3((BAYS[i] + BAYS[i + 1]) * 0.5, 0.1, -12.1), vec3(0.95, 1.15, 1.25)) end
    for _, x in ipairs({ -6.3, 6.3 }) do clone("T_hedge", vec3(x, 0.1, -12.1), vec3(0.8, 1.1, 1.25)) end
    for i, x in ipairs(BAYS) do
        clone("T_water", vec3(x, 0.135, -12.05), vec3(1.25 / 70, 1, 1.05 / 6.4))
        clone("T_bay_stone", vec3(x, 0.1, -12.05))
        local pad = clone("T_lily_pad", vec3(x, 0.15, -12.05)); setrot(pad, 0, i * 1.3, 0)
        WORLD.bays[i] = { x = x, pad = pad }
    end
    -- shimmering reflections on the river (lamps + moon)
    WORLD.refl = {}
    for _, x in ipairs({ -10, -3.5, 3.5, 10 }) do
        WORLD.refl[#WORLD.refl + 1] = { node = clone("T_refl_lamp", vec3(x, -0.235, -8.3)), x = x, z = -8.3, ph = x }
    end
    WORLD.refl[#WORLD.refl + 1] = { node = clone("T_refl_moon", vec3(1.2, -0.236, -9.2), vec3(0.6, 1, 1)), x = 1.2, z = -9.2, ph = 0.5, w = 0.6 }
    -- grass tufts along the banks
    for i = 0, 40 do
        local x = -16 + i * 0.8 + (i * 37 % 7) * 0.05
        clone("T_tuft", vec3(x, 0.12, -11.75 - (i % 3) * 0.08), vec3(1, 0.8 + (i % 4) * 0.15, 1))
        clone("T_tuft", vec3(x + 0.3, -0.02, 0.62 + (i % 2) * 0.1), vec3(0.9, 0.7 + (i % 3) * 0.15, 0.9))
    end
    -- street lamps (median and near verge), each with a warm point light
    local function lamp(x, z, ang, dz)
        local p = clone("T_lamp_pole", vec3(x, 0, z)); setrot(p, 0, ang, 0)
        local b = clone("T_lamp_bulb", vec3(x, 0, z)); setrot(b, 0, ang, 0)
        WORLD.lamps[#WORLD.lamps + 1] = { x = x, z = z + dz * 0.75, light = new_point(vec3(x, 2.6, z + dz * 0.75), vec3(1.0, 0.68, 0.35), 3.0, 6.0) }
    end
    for _, x in ipairs({ -10, -3.5, 3.5, 10 }) do lamp(x, -5.75, PI / 2, -1) end        -- arms reach over the river
    for _, x in ipairs({ -8, 0.0, 8 }) do                                               -- verge lights (poles out of shot)
        WORLD.lamps[#WORLD.lamps + 1] = { x = x, z = 1.6, light = new_point(vec3(x, 3.0, 1.6), vec3(1.0, 0.7, 0.4), 1.6, 6.5), nomoth = true }
    end
    -- bushes and reeds scattered over the far bank
    for i = 0, 26 do
        local x = -15 + i * 1.15 + ((i * 53) % 9) * 0.1
        local z = -13.6 - ((i * 29) % 5) * 0.75
        local s = 0.6 + ((i * 17) % 5) * 0.12
        clone("T_hedge", vec3(x, 0.08, z), vec3(s * 0.8, s, s * 0.8))
        clone("T_tuft", vec3(x + 0.5, 0.12, z + 0.4), vec3(1.2, 1.2, 1.2))
    end
    -- city skyline behind the far bank
    local r = 7
    for i = 0, 34 do
        r = (r * 1103515245 + 12345) % 2147483648
        local x = -34 + i * 2.0 + (r % 100) / 100
        local h = 3 + (floor(r / 7) % 1000) / 1000 * 10
        local z = -24 - (r % 7)
        clone("T_bldg_" .. ({ "a", "b", "c" })[(i % 3) + 1], vec3(x, 0, z), vec3(1.6 + (r % 5) * 0.2, h, 1.8))
    end
    -- moonlight
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(0.05, -0.8, 0.6), vec3(0.72, 0.8, 1.0), 4.0)
end

------------------------------------------------------------------ the frog
local F = { x = 0, row = 0, yaw = 0, yaw_t = 0, hop = nil, land = 0, alive = true, blink = 0, y = 0 }
local function build_frog(name)
    local f = {}
    f.root = empty(name or "Frog", vec3(0, 0, 0))
    f.pivot = empty("FrogPivot", vec3(0, 0, 0), f.root)
    f.body = clone("T_frog_body", vec3(0, 0, 0), nil, f.pivot)
    f.belly = clone("T_frog_belly", vec3(0, 0, 0), nil, f.pivot)
    f.spots = clone("T_frog_spots", vec3(0, 0, 0), nil, f.pivot)
    f.eyes = empty("FrogEyes", vec3(0, 0.36, -0.26), f.pivot)
    f.eye = clone("T_frog_eye", vec3(0, -0.36, 0.26), nil, f.eyes)
    f.pupil = clone("T_frog_pupil", vec3(0, -0.36, 0.26), nil, f.eyes)
    f.legb = clone("T_frog_legb", vec3(0, 0.16, 0.2), nil, f.pivot)
    f.legf = clone("T_frog_legf", vec3(0, 0.16, -0.12), nil, f.pivot)
    return f
end
local FN -- frog nodes

-- pose: t = hop phase 0..1 (nil when grounded), land = landing squash 0..1
local function pose_frog(f, t, land, breathe, blink)
    local sy, sxz, lb, lf = 1, 1, 1, 1
    if t then
        local s = sin(PI * t)
        sy = 1 + 0.22 * s; sxz = 1 - 0.08 * s
        lb = 1 + 1.25 * s; lf = 1 + 0.5 * s
    else
        sy = 1 - 0.2 * land + 0.025 * breathe; sxz = 1 + 0.1 * land
        lb = 1 - 0.15 * land; lf = 1
    end
    f.pivot:set_scale(vec3(sxz, sy, sxz))
    f.legb:set_scale(vec3(1, 1, lb))
    f.legf:set_scale(vec3(1, 1, lf))
    f.belly:set_scale(vec3(1 + 0.04 * breathe, 1, 1))
    f.eyes:set_scale(vec3(1, blink and 0.15 or 1, 1))
end

------------------------------------------------------------------ lanes
local VEH_EXT = { sedan = { -0.78, 0.78 }, dozer = { -0.62, 0.78 }, racer = { -0.88, 0.85 }, truck = { -1.72, 1.52 } }
local VEH_HEAD = { sedan = { 0.75, 0.34 }, dozer = { 0.5, 0.6 }, racer = { 0.82, 0.27 }, truck = { 1.5, 0.3 } }
local LANES = {
    { row = 1, kind = "sedan", dir = -1, speed = 0.8, xs = { -10, 0, 10 } },
    { row = 2, kind = "dozer", dir = 1, speed = 0.6, xs = { -12, -4.5, 3, 10.5 } },
    { row = 3, kind = "sedan", dir = -1, speed = 1.0, xs = { -12, -2, 8 } },
    { row = 4, kind = "racer", dir = 1, speed = 2.0, xs = { -9, 6 } },
    { row = 5, kind = "truck", dir = -1, speed = 0.7, xs = { -9, 1, 11 } },
    { row = 7, kind = "turtle", n = 3, dir = -1, speed = 0.75, xs = { -12, -6, 0, 6, 12 }, dive = { [2] = true, [5] = true } },
    { row = 8, kind = "log", size = "s", len = 2.6, dir = 1, speed = 0.6, xs = { -12, -6, 0, 6, 12 } },
    { row = 9, kind = "log", size = "l", len = 5.6, dir = 1, speed = 1.3, xs = { -10, 0, 10 } },
    { row = 10, kind = "turtle", n = 2, dir = -1, speed = 0.9, xs = { -12.5, -7.5, -2.5, 2.5, 7.5, 12.5 }, dive = { [3] = true, [6] = true } },
    { row = 11, kind = "log", size = "m", len = 3.8, dir = 1, speed = 0.9, xs = { -11.25, -3.75, 3.75, 11.25 } },
}
local LANE_BY_ROW = {}
local OBJS = {}
local EMIT = {}   -- particle emitters (filled in the VFX section)

local function build_vehicle(lane, idx)
    local L = LANES[lane]; local k = L.kind
    local o = { lane = L, kind = k, x = L.xs[idx], z = rowz(L.row), phase = rand() * 10 }
    o.root = empty("Veh", vec3(o.x, 0, o.z))
    setrot(o.root, 0, L.dir > 0 and 0 or PI, 0)
    local parts = { "body", "glass", "dark", "chrome", "head", "tail" }
    if k == "truck" then parts[#parts + 1] = "trailer" end
    for _, p in ipairs(parts) do clone("T_L" .. L.row .. "_" .. p, vec3(0, 0, 0), nil, o.root) end
    local e = VEH_EXT[k]; o.ea, o.eb = e[1], e[2]
    local hd = VEH_HEAD[k]; o.hx, o.hy = hd[1], hd[2]
    o.light = new_point(HIDE, vec3(1.0, 0.92, 0.75), 0, 1)
    o.tail_light = (k == "truck" or k == "racer") and new_point(HIDE, vec3(1.0, 0.1, 0.05), 0, 1) or nil
    return o
end

local function build_log(lane, idx)
    local L = LANES[lane]
    local o = { lane = L, kind = "log", x = L.xs[idx], z = rowz(L.row), phase = rand() * 10, half = L.len * 0.5 }
    o.root = empty("Log", vec3(o.x, -0.2, o.z))
    o.log = clone("T_log_" .. L.size, vec3(0, 0, 0), nil, o.root)
    o.ends = clone("T_log_" .. L.size .. "_end", vec3(0, 0, 0), nil, o.root)
    o.ea, o.eb = -o.half + 0.12, o.half - 0.12
    return o
end

local function build_turtles(lane, idx)
    local L = LANES[lane]
    local o = { lane = L, kind = "turtle", x = L.xs[idx], z = rowz(L.row), phase = rand() * 10, n = L.n, dives = L.dive and L.dive[idx] or false,
        dive_t = rand() * 7, depth = 0, turtles = {} }
    o.root = empty("Turtles", vec3(o.x, -0.25, o.z))
    for i = 1, L.n do
        local t = {}
        t.node = empty("Turtle", vec3((i - (L.n + 1) / 2) * 0.95, 0, 0), o.root)
        setrot(t.node, 0, L.dir > 0 and PI or 0, 0)      -- head leads the swim direction
        clone("T_turtle_shell", vec3(0, 0, 0), nil, t.node)
        clone("T_turtle_rim", vec3(0, 0, 0), nil, t.node)
        t.flip = clone("T_turtle_body", vec3(0, 0, 0), nil, t.node)
        clone("T_turtle_eye", vec3(0, 0, 0), nil, t.node)
        t.ph = rand() * TAU
        o.turtles[i] = t
    end
    o.half = L.n * 0.95 * 0.5
    o.ea, o.eb = -o.half + 0.05, o.half - 0.05
    return o
end

local function build_lanes()
    for li, L in ipairs(LANES) do
        LANE_BY_ROW[L.row] = L
        L.objs = {}
        for i = 1, #L.xs do
            local o
            if L.kind == "log" then o = build_log(li, i)
            elseif L.kind == "turtle" then o = build_turtles(li, i)
            else o = build_vehicle(li, i) end
            L.objs[i] = o; OBJS[#OBJS + 1] = o
        end
    end
end

------------------------------------------------------------------ VFX helpers
local function pscale() return (SET and SET.particle_scale) and SET:particle_scale() or 1.0 end
local function burst(o)
    o.count = max(1, floor((o.count or 20) * pscale()))
    pcall(particles.emit_burst, o)
end
local function emitter(o) local ok, id = pcall(particles.add_emitter, o); return ok and id or nil end
local function eset(id, k, v) if id then pcall(particles.set_emitter, id, k, v) end end

local function hop_dust(x, y, z, kind)
    if kind == "water" then
        burst({ position = vec3(x, y + 0.05, z), velocity = vec3(0, 1.4, 0), count = 18, color_start = vec4(0.75, 0.9, 1.0, 0.9), color_end = vec4(0.4, 0.7, 1.0, 0),
            size_min = 0.03, size_max = 0.07, life_min = 0.25, life_max = 0.5, spawn_radius = 0.3, gravity = vec3(0, -7, 0), drag = 0.5 })
    elseif kind == "log" then
        burst({ position = vec3(x, y + 0.05, z), velocity = vec3(0, 1.0, 0), count = 10, color_start = vec4(0.55, 0.38, 0.2, 0.9), color_end = vec4(0.3, 0.2, 0.1, 0),
            size_min = 0.025, size_max = 0.05, life_min = 0.25, life_max = 0.5, spawn_radius = 0.25, gravity = vec3(0, -6, 0) })
    else
        burst({ position = vec3(x, y + 0.04, z), velocity = vec3(0, 0.45, 0), count = 16, color_start = vec4(0.6, 0.58, 0.55, 0.55), color_end = vec4(0.4, 0.4, 0.42, 0),
            size_min = 0.05, size_max = 0.12, life_min = 0.3, life_max = 0.6, spawn_radius = 0.28, gravity = vec3(0, -0.5, 0), drag = 2.5, noise_strength = 0.4 })
    end
end
local function sparkle(x, y, z, n, col, up)
    col = col or vec4(1.0, 0.9, 0.4, 1)
    burst({ position = vec3(x, y, z), velocity = vec3(0, up or 2.5, 0), count = n or 60, color_start = col, color_end = vec4(col.x, col.y * 0.6, col.z * 0.4, 0),
        size_min = 0.03, size_max = 0.08, life_min = 0.6, life_max = 1.3, spawn_radius = 0.45, gravity = vec3(0, -2.5, 0), noise_strength = 1.2, drag = 0.6 })
end
local function splash(x, z)
    burst({ position = vec3(x, -0.25, z), velocity = vec3(0, 4.2, 0), count = 90, color_start = vec4(0.85, 0.95, 1.0, 1), color_end = vec4(0.4, 0.7, 1.0, 0),
        size_min = 0.04, size_max = 0.11, life_min = 0.5, life_max = 1.0, spawn_radius = 0.35, gravity = vec3(0, -12, 0), noise_strength = 0.6 })
    burst({ position = vec3(x, -0.22, z), velocity = vec3(0, 0.3, 0), count = 70, color_start = vec4(0.9, 1.0, 1.0, 0.8), color_end = vec4(0.6, 0.85, 1.0, 0),
        size_min = 0.06, size_max = 0.14, life_min = 0.6, life_max = 1.2, spawn_radius = 0.75, gravity = vec3(0, -0.3, 0), drag = 2.0 })
end
local function squash_burst(x, z)
    burst({ position = vec3(x, 0.2, z), velocity = vec3(0, 3.0, 0), count = 80, color_start = vec4(0.4, 1.0, 0.2, 1), color_end = vec4(0.1, 0.4, 0.05, 0),
        size_min = 0.04, size_max = 0.1, life_min = 0.4, life_max = 0.9, spawn_radius = 0.35, gravity = vec3(0, -9, 0), noise_strength = 0.8 })
    burst({ position = vec3(x, 0.3, z), velocity = vec3(0, 1.5, 0), count = 50, color_start = vec4(1.0, 1.0, 0.85, 1), color_end = vec4(1.0, 0.5, 0.1, 0),
        size_min = 0.02, size_max = 0.05, life_min = 0.3, life_max = 0.7, spawn_radius = 0.6, gravity = vec3(0, -3, 0), noise_strength = 2.0, drag = 1.0 })
    burst({ position = vec3(x, 0.1, z), velocity = vec3(0, 0.3, 0), count = 30, color_start = vec4(0.5, 0.5, 0.5, 0.6), color_end = vec4(0.3, 0.3, 0.3, 0),
        size_min = 0.1, size_max = 0.25, life_min = 0.5, life_max = 1.0, spawn_radius = 0.4, gravity = vec3(0, 0.3, 0), drag = 2.0 })
end
local function firework(x, y, z, col)
    burst({ position = vec3(x, y, z), velocity = vec3(0, 0.5, 0), count = 120, color_start = col, color_end = vec4(col.x, col.y, col.z, 0),
        size_min = 0.04, size_max = 0.09, life_min = 0.8, life_max = 1.6, spawn_radius = 0.2, gravity = vec3(0, -1.5, 0), noise_strength = 5.0, drag = 0.8 })
end

local function build_ambient_fx()
    -- glints on the river surface
    for i = -6, 6 do
        for _, z in ipairs({ -7.6, -9.2, -10.8 }) do
            emitter({ position = vec3(i * 2.2 + (z * 1.7 % 1), -0.27, z), velocity = vec3(0, 0.02, 0), color_start = vec4(0.8, 0.9, 1.0, 0.8), color_end = vec4(0.5, 0.7, 1.0, 0),
                gravity = vec3(0, 0, 0), count = 12, size_min = 0.008, size_max = 0.02, life_min = 0.2, life_max = 0.6, spawn_rate = 5, spawn_radius = 1.3, noise_strength = 0.05, drag = 1.0 })
        end
    end
    -- fireflies over the far bank and hedges
    for i = -4, 4 do
        emitter({ position = vec3(i * 3, 0.9, -13.2), velocity = vec3(0, 0.05, 0), color_start = vec4(0.8, 1.0, 0.3, 1), color_end = vec4(0.4, 1.0, 0.2, 0),
            gravity = vec3(0, 0, 0), count = 10, size_min = 0.03, size_max = 0.06, life_min = 2.0, life_max = 4.0, spawn_rate = 2, spawn_radius = 1.2, noise_strength = 0.6, drag = 0.8 })
    end
    -- moths / dust motes in each lamp cone
    for _, l in ipairs(WORLD.lamps) do if not l.nomoth then
        emitter({ position = vec3(l.x, 2.0, l.z), velocity = vec3(0, 0.02, 0), color_start = vec4(1.0, 0.85, 0.55, 0.9), color_end = vec4(1.0, 0.6, 0.3, 0),
            gravity = vec3(0, -0.02, 0), count = 24, size_min = 0.012, size_max = 0.03, life_min = 2.0, life_max = 4.0, spawn_rate = 6, spawn_radius = 0.7, noise_strength = 0.5, drag = 0.7 })
    end end
    -- per-object emitters: exhaust for vehicles, foam for logs and turtles
    for _, o in ipairs(OBJS) do
        if o.kind == "log" or o.kind == "turtle" then
            o.foam = emitter({ position = HIDE, velocity = vec3(0, 0.15, 0), color_start = vec4(0.85, 0.95, 1.0, 0.75), color_end = vec4(0.6, 0.85, 1.0, 0),
                gravity = vec3(0, -0.2, 0), count = 30, size_min = 0.03, size_max = 0.08, life_min = 0.4, life_max = 0.9, spawn_rate = 18, spawn_radius = 0.28, noise_strength = 0.2, drag = 1.5 })
        else
            o.exhaust = emitter({ position = HIDE, velocity = vec3(0, 0.35, 0), color_start = vec4(0.16, 0.16, 0.18, 0.25), color_end = vec4(0.05, 0.05, 0.06, 0),
                gravity = vec3(0, 0.2, 0), count = 30, size_min = 0.03, size_max = 0.08, life_min = 0.5, life_max = 1.1, spawn_rate = (o.kind == "racer") and 6 or 14, spawn_radius = 0.06, noise_strength = 0.5, drag = 1.6 })
        end
    end
end

------------------------------------------------------------------ lane simulation
G.mult = 1.0
local DIVE_PERIOD = 7.0
local function turtle_depth(o)
    if not o.dives then return 0 end
    local s = o.dive_t % DIVE_PERIOD
    if s < 4.0 then return 0
    elseif s < 4.8 then return smooth((s - 4.0) / 0.8)
    elseif s < 6.0 then return 1
    else return 1 - smooth((s - 6.0) / 1.0) end
end
local function update_lanes(dt, visual)
    local t = G.t
    for _, L in ipairs(LANES) do
        local v = L.dir * L.speed * G.mult
        L.v = v
        for _, o in ipairs(L.objs) do
            o.x = o.x + v * dt
            if o.x > LOOP * 0.5 then o.x = o.x - LOOP elseif o.x < -LOOP * 0.5 then o.x = o.x + LOOP end
            if o.kind == "turtle" then
                o.dive_t = o.dive_t + dt
                local was = o.depth; o.depth = turtle_depth(o)
                if visual and o.dives and was < 0.05 and o.depth >= 0.05 then
                    burst({ position = vec3(o.x, -0.25, o.z), velocity = vec3(0, 0.8, 0), count = 30, color_start = vec4(0.8, 0.95, 1, 0.9), color_end = vec4(0.5, 0.8, 1, 0),
                        size_min = 0.03, size_max = 0.08, life_min = 0.4, life_max = 0.9, spawn_radius = o.half, gravity = vec3(0, -1, 0) })
                end
            end
            if visual then
                local wx = o.x
                if o.kind == "log" then
                    o.y = -0.2 + 0.03 * sin(t * 1.8 + o.phase)
                    o.root:set_position(vec3(wx, o.y, o.z))
                    setrot(o.root, 0.04 * sin(t * 1.3 + o.phase), 0, 0.012 * sin(t * 1.1 + o.phase))
                    eset(o.foam, "position", vec3(wx - L.dir * o.half, -0.27, o.z))
                elseif o.kind == "turtle" then
                    local warn = o.dives and ((o.dive_t % DIVE_PERIOD) > 3.2 and (o.dive_t % DIVE_PERIOD) < 4.0)
                    o.y = -0.25 - o.depth * 0.55 + 0.02 * sin(t * 2.2 + o.phase) + (warn and 0.03 * sin(t * 40) or 0)
                    o.root:set_position(vec3(wx, o.y, o.z))
                    for _, tu in ipairs(o.turtles) do
                        tu.flip:set_rotation(vec3(0, 9 * sin(t * 5 + tu.ph), 0))
                    end
                    eset(o.foam, "position", vec3(wx - L.dir * o.half, -0.27, o.z))
                    eset(o.foam, "spawn_rate", o.depth > 0.6 and 0 or 18)
                else
                    o.root:set_position(vec3(wx, 0.008 * sin(t * 23 + o.phase), o.z))
                    local hx = wx + L.dir * (o.hx + 1.05)
                    set_point(o.light, vec3(hx, G.hl_y or 0.6, o.z), vec3(1.0, 0.9, 0.72), G.hl_i or 5.0, G.hl_r or 2.3)
                    if o.tail_light then set_point(o.tail_light, vec3(wx - L.dir * (-o.ea + 0.25), 0.4, o.z), vec3(1.0, 0.08, 0.04), 0.9, 1.2) end
                    eset(o.exhaust, "position", vec3(wx + L.dir * (o.ea - 0.08), (o.kind == "dozer") and 1.05 or 0.18, o.z + ((o.kind == "dozer") and 0.15 * -L.dir or 0.2)))
                end
            end
        end
    end
end
-- world-space extents of an object along X
local function extents(o)
    local d = o.lane.dir
    if d > 0 then return o.x + o.ea, o.x + o.eb end
    return o.x - o.eb, o.x - o.ea
end

------------------------------------------------------------------ game state
G.score, G.hi, G.lives, G.level, G.time = 0, 0, 3, 1, TIME_PER_FROG
G.filled = {}
G.home_frogs = {}
G.fly = { bay = nil, t = 0, next = 6 }
G.shake, G.flash = 0, 0
G.flash_col = { 1, 1, 1 }
local toast = { text = "", t = 0 }
local function show_toast(s, d) toast.text = s; toast.t = d or 2.0 end
local function load_hi()
    local ok, s = pcall(fs.read, "Save/hiscore.txt")
    if ok and s then G.hi = tonumber(s:match("%d+")) or 0 end
end
local function save_hi() pcall(fs.write, "Save/hiscore.txt", tostring(G.hi)) end
local function add_score(n)
    local before = G.score
    G.score = G.score + n
    if before < 10000 and G.score >= 10000 then G.lives = G.lives + 1; sfx("extra"); show_toast("EXTRA FROG!") end
    if G.score > G.hi then G.hi = G.score end
end
local function flash(r, g, b, a) G.flash_col = { r, g, b }; G.flash = a end
local function shake(a) G.shake = max(G.shake, a * ((SET and SET.shake_scale) and SET:shake_scale() or 1)) end

------------------------------------------------------------------ frog control
local queue = nil          -- (unused: no input buffering)
local hop_lock = nil       -- direction of the last hop; cleared when its key is released
local queue_t = 0
local hold_t = 0
local DIRS = { up = { 0, 1, 0 }, down = { 0, -1, PI }, left = { -1, 0, PI / 2 }, right = { 1, 0, -PI / 2 } }

local function frog_y_at(row, x)
    if row >= 7 and row <= 11 and F.ride then return (F.ride.y or -0.2) + (F.ride.kind == "log" and 0.31 or 0.17) end
    if row == ROW_HOME then return 0.16 end
    if row == 0 or row == 6 then return 0.03 end
    return 0.0
end

local function respawn()
    F.x, F.row, F.yaw, F.yaw_t = 0, 0, 0, 0
    F.hop, F.ride, F.land, F.alive, F.max_row, F.dead_t = nil, nil, 0, true, 0, 0
    F.y = 0.03
    queue = nil
    G.time = TIME_PER_FROG
    FN.root:set_enabled(true)
    FN.root:set_scale(vec3(1, 1, 1))
    pose_frog(FN, nil, 0, 0, false)
end

local function die(cause)
    if not F.alive then return end
    F.alive = false; F.cause = cause; F.dead_t = 0; F.hop = nil; queue = nil
    G.state = "dying"
    local z = rowz(F.row)
    if cause == "water" then
        sfx("splash"); splash(F.x, z); shake(0.15); flash(0.2, 0.5, 1.0, 0.25)
    elseif cause == "car" then
        sfx("squash"); squash_burst(F.x, z); shake(0.45); flash(1.0, 0.2, 0.1, 0.35)
    else
        sfx("squash"); sparkle(F.x, F.y + 0.3, z, 50, vec4(1, 0.4, 0.3, 1), 2.0); shake(0.25); flash(1.0, 0.4, 0.2, 0.25)
    end
end

local function start_hop(d)
    local D = DIRS[d]
    local r1 = F.row + D[2]
    local x1 = F.x + D[1]
    if r1 < 0 or r1 > ROW_HOME then F.yaw_t = D[3]; return false end
    if abs(x1) > COLS_HALF + 0.01 then F.yaw_t = D[3]; return false end
    -- leaving the river onto land: snap X to the half-cell grid so lanes stay readable
    F.hop = { t = 0, x0 = F.x, x1 = x1, r0 = F.row, r1 = r1, y0 = F.y, ride_v = (F.ride and F.ride.lane.v) or 0 }
    F.yaw_t = D[3]
    F.ride = nil
    sfx("hop")
    return true
end

local function find_platform(row, x)
    local L = LANE_BY_ROW[row]; if not L then return nil end
    for _, o in ipairs(L.objs) do
        if not (o.kind == "turtle" and o.depth > 0.55) then
            local a, b = extents(o)
            if x >= a - 0.12 and x <= b + 0.12 then return o end
        end
    end
    return nil
end

local function hits_vehicle(row, x)
    local L = LANE_BY_ROW[row]; if not L or L.kind == "log" or L.kind == "turtle" then return false end
    for _, o in ipairs(L.objs) do
        local a, b = extents(o)
        if x + 0.26 > a and x - 0.26 < b then return true end
    end
    return false
end

local function spawn_home_frog(i)
    local hf = G.home_frogs[i]
    if not hf then hf = build_frog("HomeFrog"); G.home_frogs[i] = hf end
    hf.root:set_enabled(true)
    hf.root:set_position(vec3(BAYS[i], 0.16, -12.05))
    setrot(hf.pivot, 0, PI, 0)    -- sits facing the player
    hf.pop = 0
end

local level_clear_t = nil
local function reach_home(i)
    G.filled[i] = true
    spawn_home_frog(i)
    local bonus = 50 + floor(G.time * 2) * 10
    local fly = (G.fly.bay == i)
    if fly then bonus = bonus + 200; G.fly.bay = nil; sfx("fly"); show_toast("BONUS FLY  +200") end
    add_score(bonus)
    sfx("home")
    sparkle(BAYS[i], 0.4, -12.05, 90)
    sparkle(BAYS[i], 0.4, -12.05, 40, vec4(1.0, 0.5, 0.8, 1), 3.5)
    flash(0.6, 1.0, 0.5, 0.18)
    local all = true
    for k = 1, 5 do if not G.filled[k] then all = false end end
    if all then
        add_score(1000)
        sfx("level")
        show_toast("LEVEL " .. G.level .. " CLEAR!  +1000", 2.6)
        level_clear_t = 2.8
        G.state = "clear"
        FN.root:set_enabled(false)
    else
        respawn()
    end
end

local function land()
    local h = F.hop
    F.hop = nil
    F.row = h.r1; F.x = h.x1
    F.land = 1
    if F.row > F.max_row then F.max_row = F.row; add_score(10) end
    local z = rowz(F.row)
    if F.row >= 7 and F.row <= 11 then
        local p = find_platform(F.row, F.x)
        if not p then F.y = -0.3; die("water"); return end
        F.ride = p
        F.y = frog_y_at(F.row, F.x)
        hop_dust(F.x, F.y, z, p.kind == "log" and "log" or "water")
    elseif F.row == ROW_HOME then
        for i, bx in ipairs(BAYS) do
            if abs(F.x - bx) < 0.62 then
                if G.filled[i] then die("hedge"); return end
                F.x = bx
                reach_home(i)
                return
            end
        end
        die("hedge")
    else
        if F.row ~= 0 and F.row ~= 6 then F.x = floor(F.x * 2 + 0.5) / 2 end
        F.y = frog_y_at(F.row, F.x)
        hop_dust(F.x, F.y, z, "ground")
    end
end

local function read_dir()
    if pressed("Up", "W") then return "up" end
    if pressed("Down", "S") then return "down" end
    if pressed("Left", "A") then return "left" end
    if pressed("Right", "D") then return "right" end
    return nil
end
local function held_dir()
    if held("Up") or held("W") then return "up" end
    if held("Down") or held("S") then return "down" end
    if held("Left") or held("A") then return "left" end
    if held("Right") or held("D") then return "right" end
    return nil
end

local function update_frog(dt)
    -- input: exactly ONE hop per key press. A hop starts only on a fresh key-down edge while the
    -- frog is grounded; presses during a hop, holding a key and OS key repeat are all ignored.
    -- After a hop the pressed key must be released before it can trigger again.
    local d = read_dir()
    if not F.hop and d and not hop_lock then
        if start_hop(d) then hop_lock = d end
    end
    if hop_lock and not F.hop and not held_dir() then hop_lock = nil end
    if hop_lock and not F.hop and held_dir() and held_dir() ~= hop_lock then hop_lock = nil end
    if F.hop then
        local h = F.hop
        h.t = h.t + dt / HOP_T
        h.x0 = h.x0 + h.ride_v * dt; h.x1 = h.x1 + h.ride_v * dt
        local k = clamp(h.t, 0, 1)
        F.x = lerp(h.x0, h.x1, k)
        local zrow = lerp(h.r0, h.r1, k)
        F.zrow = zrow
        local y1 = (h.r1 >= 7 and h.r1 <= 11) and -0.0 or frog_y_at(h.r1, h.x1)
        F.y = lerp(h.y0, y1, k) + HOP_H * 4 * k * (1 - k)
        if h.t >= 1 then land() end
        -- traffic can still clip you mid-hop
        if F.alive and F.hop then
            local r = floor(zrow + 0.5)
            if hits_vehicle(r, F.x) and k > 0.25 then F.row = r; die("car") end
        end
    else
        F.zrow = F.row
        if F.row >= 7 and F.row <= 11 then
            local p = F.ride
            if p then
                F.x = F.x + p.lane.v * dt
                F.y = frog_y_at(F.row, F.x)
                local a, b = extents(p)
                if (p.kind == "turtle" and p.depth > 0.55) or F.x < a - 0.2 or F.x > b + 0.2 then F.y = -0.3; die("water") end
            end
            if F.alive and abs(F.x) > COLS_HALF + 0.6 then die("edge") end
        elseif hits_vehicle(F.row, F.x) then
            die("car")
        end
    end
    F.land = max(0, F.land - dt * 6)
    -- turn towards the hop direction along the short way round
    local dy = (F.yaw_t - F.yaw + PI) % TAU - PI
    F.yaw = F.yaw + dy * min(1, dt * 28)
end

------------------------------------------------------------------ visuals per frame
local frog_light
local FROG_S = 1.35
local fly_nodes = {}
local function update_frog_visual(dt)
    local z = rowz(F.zrow or F.row)
    local y = F.y
    local t = F.hop and clamp(F.hop.t, 0, 1) or nil
    G.blink_t = (G.blink_t or 2) - dt
    local blink = G.blink_t < 0.12
    if G.blink_t < 0 then G.blink_t = 2 + rand() * 3 end
    if F.alive then
        pose_frog(FN, t, F.land, sin(G.t * 5), blink)
        FN.root:set_scale(vec3(FROG_S, FROG_S, FROG_S))
        setrot(FN.pivot, 0, F.yaw, 0)
    else
        F.dead_t = F.dead_t + dt
        local k = clamp(F.dead_t / 0.35, 0, 1)
        if F.cause == "car" then
            FN.pivot:set_scale(vec3(lerp(1, 1.55, k), lerp(1, 0.1, k), lerp(1, 1.55, k)))
            y = 0.01
        elseif F.cause == "water" then
            y = -0.3 - F.dead_t * 0.6
            FN.root:set_scale(vec3(1, 1, 1) * FROG_S * max(0.01, 1 - F.dead_t))
        else
            setrot(FN.pivot, 0, F.yaw + F.dead_t * 18, 0)
            FN.root:set_scale(vec3(1, 1, 1) * FROG_S * max(0.01, 1 - F.dead_t * 1.2))
            y = y + F.dead_t * 0.5
        end
    end
    FN.root:set_position(vec3(F.x, y, z))
    set_point(frog_light, vec3(F.x, y + 0.9, z + 0.35), vec3(0.75, 1.0, 0.7), F.alive and 0.9 or 0.0, 1.8)
    -- home frogs pop in, then idle
    for i, hf in pairs(G.home_frogs) do
        if G.filled[i] then
            hf.pop = min(1, (hf.pop or 0) + dt * 4)
            local s = 1.1 * (hf.pop < 1 and (1 + 0.35 * sin(hf.pop * PI)) or 1)
            hf.root:set_scale(vec3(s, s, s))
            pose_frog(hf, nil, 0, sin(G.t * 4 + i), false)
        end
    end
    -- lily pads drift gently
    for i, b in ipairs(WORLD.bays) do
        b.pad:set_position(vec3(b.x + 0.03 * sin(G.t * 0.7 + i), 0.15, -12.05 + 0.03 * cos(G.t * 0.6 + i)))
    end
    for i, r in ipairs(WORLD.refl) do
        r.node:set_scale(vec3((r.w or 1) * (1 + 0.18 * sin(G.t * 3.1 + r.ph * 1.7) + 0.08 * sin(G.t * 7.3 + i)), 1, 1 + 0.05 * sin(G.t * 1.3 + i)))
        r.node:set_position(vec3(r.x + 0.04 * sin(G.t * 2.3 + r.ph), -0.235, r.z))
    end
    -- the scrolling river: the water mesh slides along X (texture period 7u) for a flowing surface
    WORLD.water:set_position(vec3(-((G.t * 0.35) % 7.0), -0.3, -9.2))
end

local function update_fly(dt, playing)
    local fl = G.fly
    if playing then
        fl.t = fl.t - dt
        if fl.bay then
            if fl.t <= 0 or G.filled[fl.bay] then fl.bay = nil; fl.t = 4 + rand() * 6 end
        elseif fl.t <= 0 then
            local free = {}
            for i = 1, 5 do if not G.filled[i] then free[#free + 1] = i end end
            if #free > 0 then fl.bay = free[rand(#free)]; fl.t = 5.5; sparkle(BAYS[fl.bay], 0.5, -12.05, 20, vec4(0.6, 1.0, 0.8, 1), 1.0) end
        end
    end
    local on = fl.bay ~= nil
    fly_nodes.root:set_enabled(on)
    if on then
        local bx = BAYS[fl.bay]
        fly_nodes.root:set_position(vec3(bx + 0.12 * sin(G.t * 3.1), 0.55 + 0.1 * sin(G.t * 5.3), -12.05 + 0.1 * cos(G.t * 2.7)))
        setrot(fly_nodes.root, 0, G.t * 1.5, 0)
        fly_nodes.wing:set_scale(vec3(1, 1, 0.3 + 0.7 * abs(sin(G.t * 60))))
    end
end

------------------------------------------------------------------ camera
local cam
local CAM_POS = vec3(0, 23.5, 4.4)
local CAM_LOOK = vec3(0, -0.4, -6.0)
local cam_cur = { x = 0, y = 23.5, z = 4.4, lx = 0, ly = -0.4, lz = -6.0 }
local function update_camera(dt, mode)
    local tp, tl
    if mode == "title" then
        local a = G.t * 0.12
        tp = { x = 7.5 * sin(a), y = 6.2 + 0.8 * sin(a * 1.7), z = 4.5 + 2.0 * cos(a) }
        tl = { x = 0.5 * sin(a), y = 0.0, z = -6.5 }
    else
        local fx = clamp(F.x, -6, 6) * 0.18
        local fz = clamp(F.zrow or F.row, 0, 12)
        tp = { x = CAM_POS.x + fx, y = CAM_POS.y, z = CAM_POS.z - fz * 0.08 }
        tl = { x = CAM_LOOK.x + fx * 1.4, y = CAM_LOOK.y, z = CAM_LOOK.z - fz * 0.12 }
    end
    local k = min(1, dt * (mode == "title" and 1.5 or 4.0))
    cam_cur.x = lerp(cam_cur.x, tp.x, k); cam_cur.y = lerp(cam_cur.y, tp.y, k); cam_cur.z = lerp(cam_cur.z, tp.z, k)
    cam_cur.lx = lerp(cam_cur.lx, tl.x, k); cam_cur.ly = lerp(cam_cur.ly, tl.y, k); cam_cur.lz = lerp(cam_cur.lz, tl.z, k)
    G.shake = max(0, G.shake - dt * 1.5)
    local s = G.shake * G.shake
    local sx, sy = s * (rand() - 0.5) * 0.8, s * (rand() - 0.5) * 0.8
    cam:set_position(vec3(cam_cur.x + sx, cam_cur.y + sy, cam_cur.z))
    cam:look_at(vec3(cam_cur.lx + sx * 0.5, cam_cur.ly + sy * 0.5, cam_cur.lz))
end

------------------------------------------------------------------ HUD + menus (runtime_ui)
local function col(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end
local NONE = col(0, 0, 0, 0)
local function surf()
    local s = runtime_ui.get_surface_size()
    return (s and (s.width or s.w)) or 1280, (s and (s.height or s.h)) or 720
end
local function quad(screen, id, x, y, w, h, o)
    o.x, o.y, o.w, o.h = x, y, w, h
    if o.style == "text" then o.fill = o.fill or NONE; o.border = o.border or NONE end
    o.no_input = not o.input; o.input = nil
    runtime_ui.set_quad(screen, id, o)
end
local function text(screen, id, x, y, w, h, str, c, scale, align)
    quad(screen, id, x, y, w, h, { title = str, style = "text", text_color = c, font_scale = scale, align_h = align or "center" })
end

local function draw_hud()
    local sw, sh = surf(); local k = sw / 1280
    local function S(v) return v * k end
    runtime_ui.show("hud")
    quad("hud", "bar", S(14), S(6), sw - S(28), S(40), { style = "panel", fill = col(0.02, 0.03, 0.08, 0.55), corner_radius = S(14), border = col(0.3, 1.0, 0.5, 0.55) })
    text("hud", "score", S(34), S(6), S(360), S(40), string.format("SCORE  %06d", G.score), col(0.55, 1.0, 0.45), 1.5 * k, "left")
    text("hud", "hi", sw / 2 - S(180), S(6), S(360), S(40), string.format("HI  %06d", G.hi), col(1.0, 0.45, 0.75), 1.5 * k, "center")
    text("hud", "level", sw - S(330), S(6), S(300), S(40), string.format("LEVEL  %d", G.level), col(0.55, 0.85, 1.0), 1.5 * k, "right")
    -- lives (little frog pips) and the timer bar along the bottom
    quad("hud", "bot", S(14), sh - S(58), sw - S(28), S(46), { style = "panel", fill = col(0.02, 0.03, 0.08, 0.55), corner_radius = S(14), border = col(0.3, 1.0, 0.5, 0.4) })
    for i = 1, 6 do
        quad("hud", "life" .. i, S(30) + (i - 1) * S(30), sh - S(46), S(22), S(22), { style = "panel", fill = col(0.35, 1.0, 0.25, 0.95), corner_radius = S(11),
            border = col(0.9, 1.0, 0.6, 0.9), visible = i <= G.lives - ((G.state == "dying") and 1 or 0) })
    end
    local frac = clamp(G.time / TIME_PER_FROG, 0, 1)
    local bw = S(520)
    local tc = frac > 0.3 and col(0.35, 1.0, 0.35) or col(1.0, 0.25 + 0.2 * sin(G.t * 12), 0.15)
    text("hud", "tlabel", sw - bw - S(150), sh - S(58), S(110), S(46), "TIME", tc, 1.3 * k, "right")
    quad("hud", "tback", sw - bw - S(30), sh - S(44), bw, S(18), { style = "panel", fill = col(0.0, 0.0, 0.0, 0.6), corner_radius = S(9), border = col(1, 1, 1, 0.25) })
    quad("hud", "tbar", sw - S(30) - bw * frac, sh - S(44), max(1, bw * frac), S(18), { style = "panel", fill = tc, corner_radius = S(9), border = NONE })
    local a = clamp(toast.t, 0, 1)
    quad("hud", "toast", sw / 2 - S(330), sh * 0.44, S(660), S(56), { title = toast.text, style = "panel", fill = col(0.02, 0.05, 0.02, 0.6 * a), border = col(0.4, 1.0, 0.5, 0.6 * a),
        text_color = col(0.7, 1.0, 0.5, a), font_scale = 1.6 * k, corner_radius = S(14), visible = a > 0.01 })
    local f = G.flash
    quad("hud", "flash", 0, 0, sw, sh, { style = "panel", fill = col(G.flash_col[1], G.flash_col[2], G.flash_col[3], f), border = NONE, corner_radius = 0, visible = f > 0.01 })
end

local MENU = { sel = 1 }
local PAUSE_ITEMS = { "RESUME", "SETTINGS", "RESTART", "QUIT TO TITLE" }
local function draw_menu(kind)
    local sw, sh = surf(); local k = sw / 1280
    local function S(v) return v * k end
    runtime_ui.show("menu")
    runtime_ui.set_screen_overlay("menu", true)
    local pulse = 0.6 + 0.4 * sin(G.t * 4)
    quad("menu", "dim", 0, 0, sw, sh, { style = "panel", fill = col(0.0, 0.01, 0.04, kind == "title" and 0.25 or 0.55), border = NONE, corner_radius = 0 })
    local vis = {}
    local function T(id, ...) vis[id] = true; text("menu", id, ...) end
    -- mouse-clickable button (hover selects, click activates; see menu_click)
    local function B(id, i, x, y, w, h, label)
        vis[id] = true
        local hv = MENU.hover == id
        local on = (i == MENU.sel) or hv
        quad("menu", id, x, y, w, h, { style = "text", title = label, label = label, input = true, z = 20, align_h = "center", align_v = "middle", corner_radius = S(12),
            fill = on and col(0.15, 0.45, 0.12, 0.75) or col(0.02, 0.06, 0.03, 0.6), border = on and col(0.6, 1.0, 0.4, 0.95) or col(0.4, 0.8, 0.4, 0.45),
            text_color = on and col(1.0, 0.95, 0.4) or col(0.8, 0.9, 1.0, 0.85), font_scale = 1.6 * k })
    end
    if kind == "title" then
        T("logo_s", sw / 2 - S(500) + S(6), S(90) + S(6), S(1000), S(150), "FROGGER", col(0.0, 0.15, 0.0, 0.85), 7.0 * k)
        T("logo", sw / 2 - S(500), S(90), S(1000), S(150), "FROGGER", col(0.45, 1.0, 0.3), 7.0 * k)
        T("sub", sw / 2 - S(500), S(232), S(1000), S(60), "R  E  M  I  X", col(1.0, 0.45, 0.8), 2.4 * k)
        B("tb1", 1, sw / 2 - S(200), sh - S(330), S(400), S(56), "PLAY")
        B("tb2", 2, sw / 2 - S(200), sh - S(262), S(400), S(56), "SETTINGS")
        T("help", sw / 2 - S(560), sh - S(180), S(1120), S(40), "ARROWS / WASD  hop   |   ESC  pause   |   O  settings   |   M  mute", col(0.75, 0.9, 1.0, 0.9), 1.2 * k)
        T("hi", sw / 2 - S(300), sh - S(130), S(600), S(40), string.format("HI-SCORE  %06d", G.hi), col(1.0, 0.8, 0.35), 1.3 * k)
    elseif kind == "pause" then
        T("ptitle", sw / 2 - S(300), S(150), S(600), S(90), "PAUSED", col(0.5, 1.0, 0.4), 4.0 * k)
        for i, it in ipairs(PAUSE_ITEMS) do
            local on = (i == MENU.sel)
            B("pi" .. i, i, sw / 2 - S(250), S(270) + (i - 1) * S(68), S(500), S(58), it)
        end
    elseif kind == "over" then
        -- stack the texts upward from the PLAY AGAIN button so nothing ever overlaps it (any aspect)
        local by = sh - S(290)
        local hy = math.min(S(270), by - S(110))
        local sy = hy - S(70)
        local ty = math.max(S(20), sy - S(125))
        T("otitle", sw / 2 - S(400), ty, S(800), S(110), "GAME OVER", col(1.0, 0.3, 0.35), 5.0 * k)
        T("oscore", sw / 2 - S(400), sy, S(800), S(60), string.format("SCORE  %06d   LEVEL %d", G.score, G.level), col(1, 1, 1), 2.0 * k)
        T("ohi", sw / 2 - S(400), hy, S(800), S(50), (G.score >= G.hi and G.score > 0) and "NEW HI-SCORE!" or string.format("HI  %06d", G.hi), col(1.0, 0.8, 0.35), 1.6 * k)
        B("ob1", 1, sw / 2 - S(200), sh - S(290), S(400), S(56), "PLAY AGAIN")
        B("ob2", 2, sw / 2 - S(200), sh - S(222), S(400), S(56), "TITLE")
    end
    for _, id in ipairs({ "logo_s", "logo", "sub", "tb1", "tb2", "help", "hi", "ptitle", "pi1", "pi2", "pi3", "pi4", "otitle", "oscore", "ohi", "ob1", "ob2" }) do
        if not vis[id] then pcall(runtime_ui.set_quad, "menu", id, { visible = false, x = 0, y = 0, w = 1, h = 1, style = "text", title = "", fill = NONE, border = NONE, no_input = true }) end
    end
end
local function hide_menu() pcall(runtime_ui.hide, "menu") end
-- returns the index of a clicked button among ids (and tracks hover for highlight/keyboard sync)
local function menu_click(ids)
    MENU.hover = nil
    for i, id in ipairs(ids) do
        local ok, st = pcall(runtime_ui.get_state, "menu", id)
        if ok and st then
            if st.hovered then MENU.hover = id; MENU.sel = i end
            if st.clicked then return i end
        end
    end
end

------------------------------------------------------------------ flow
local function reset_bays()
    for i = 1, 5 do
        G.filled[i] = false
        if G.home_frogs[i] then G.home_frogs[i].root:set_enabled(false) end
    end
end
local function new_game()
    G.score, G.lives, G.level, G.mult = 0, 3, 1, 1.0
    reset_bays()
    G.fly = { bay = nil, t = 6, next = 6 }
    respawn()
    G.state = "play"
    hide_menu()
    show_toast("GET ALL FIVE FROGS HOME!", 1.4)
end
G.new_game = new_game
local function next_level()
    G.level = G.level + 1
    G.mult = min(1.6, 1.0 + 0.1 * (G.level - 1))  -- gentle arcade-like ramp
    -- from level 3 every turtle group can dive
    if G.level >= 3 then for _, L in ipairs(LANES) do if L.kind == "turtle" then for i, o in ipairs(L.objs) do o.dives = (i % 2 == 0) or G.level >= 5 end end end end
    reset_bays()
    respawn()
    G.state = "play"
    show_toast("LEVEL " .. G.level .. "  -  FASTER!", 2.0)
end
local function game_over()
    G.state = "over"; MENU.sel = 1
    sfx("over")
    save_hi()
end

local last_tick = 99
local function update_play(dt)
    G.time = G.time - dt
    if G.time <= 8 and floor(G.time) ~= last_tick and G.time > 0 then last_tick = floor(G.time); sfx("tick") end
    if G.time <= 0 then G.time = 0; die("time"); show_toast("OUT OF TIME!", 1.6) end
    local n = max(1, math.ceil(dt / (1 / 120)))
    for _ = 1, n do
        if G.state == "play" then update_frog(dt / n) end
    end
end

local function update(dt)
    dt = min(dt, 0.05)
    G.t = G.t + dt
    flush_mats()
    poll_keys()
    local menu_open = SET and SET:update(dt) or false
    G.flash = max(0, G.flash - dt * 1.8)
    toast.t = max(0, toast.t - dt)
    local playing = (G.state == "play" or G.state == "dying" or G.state == "clear")
    if not menu_open and pressed("M") and SET then SET:toggle_mute() end

    if G.state ~= "pause" and not menu_open then update_lanes(dt, true) end
    if G.state == "title" then
        update_camera(dt, "title")
        if not menu_open then
            draw_menu("title")
            if MENU.tsel == nil then MENU.sel = 1; MENU.tsel = true end
            local c = menu_click({ "tb1", "tb2" })
            if pressed("Up", "W", "Down", "S") then MENU.sel = 3 - MENU.sel; sfx("click") end
            if pressed("Return", "Space") then c = MENU.sel end
            if c == 1 then sfx("click"); MENU.tsel = nil; new_game()
            elseif (c == 2 or pressed("O")) and SET then sfx("click"); hide_menu(); SET:open(function() end) end
        end
    elseif G.state == "play" then
        if not menu_open then
            update_play(dt)
            if pressed("Escape", "P") and G.state == "play" then G.state = "pause"; MENU.sel = 1; sfx("click") end
            if pressed("O") and SET then G.state = "pause"; hide_menu(); SET:open(function() end) end
        end
        update_camera(dt, "play")
    elseif G.state == "dying" then
        update_camera(dt, "play")
        if F.dead_t > 1.4 then
            G.lives = G.lives - 1
            if G.lives <= 0 then game_over() else respawn(); G.state = "play" end
        end
    elseif G.state == "clear" then
        update_camera(dt, "play")
        level_clear_t = level_clear_t - dt
        if rand() < dt * 6 then
            local cols = { vec4(1, 0.4, 0.8, 1), vec4(0.4, 1, 0.5, 1), vec4(0.4, 0.8, 1, 1), vec4(1, 0.9, 0.3, 1) }
            firework(rr(-6, 6), rr(2.5, 4.5), rr(-13, -10), cols[rand(4)])
        end
        if level_clear_t <= 0 then next_level() end
    elseif G.state == "pause" then
        update_camera(dt, "play")
        if not menu_open then
            draw_menu("pause")
            if pressed("Up", "W") then MENU.sel = (MENU.sel - 2) % #PAUSE_ITEMS + 1; sfx("click") end
            if pressed("Down", "S") then MENU.sel = MENU.sel % #PAUSE_ITEMS + 1; sfx("click") end
            local pick = menu_click({ "pi1", "pi2", "pi3", "pi4" })
            if pressed("Return", "Space") then pick = MENU.sel end
            if pressed("Escape", "P") then pick = 1 end
            if pressed("O") then pick = 2 end
            if pick == 1 then G.state = "play"; hide_menu(); sfx("click")
            elseif pick == 2 and SET then sfx("click"); hide_menu(); SET:open(function() end)
            elseif pick == 3 then sfx("click"); new_game()
            elseif pick == 4 then sfx("click"); save_hi(); G.state = "title"; hide_menu(); pcall(runtime_ui.hide, "hud") end
        end
    elseif G.state == "over" then
        update_camera(dt, "play")
        if not menu_open then
            draw_menu("over")
            local c = menu_click({ "ob1", "ob2" })
            if pressed("Up", "W", "Down", "S") then MENU.sel = (MENU.sel == 1) and 2 or 1; sfx("click") end
            if pressed("Return", "Space") then c = (MENU.sel == 2) and 2 or 1 end
            if c == 1 then sfx("click"); MENU.sel = 1; new_game()
            elseif c == 2 or pressed("Escape") then MENU.sel = 1; G.state = "title"; hide_menu(); pcall(runtime_ui.hide, "hud") end
        end
    end
    update_fly(dt, G.state == "play")
    update_frog_visual(dt)
    if G.state ~= "title" then draw_hud() end
    latch_keys()
end

------------------------------------------------------------------ init
local function init()
    pe_log("[Frogger] init")
    math.randomseed(1981)
    setup_render()
    cam = get_camera and get_camera() or scene.get_cameras()[1]
    pcall(function() cam:set_fov(62) end)
    setup_materials()
    build_world()
    FN = build_frog("Frog")
    fly_nodes.root = empty("Fly", HIDE)
    clone("T_fly_body", vec3(0, 0, 0), nil, fly_nodes.root)
    fly_nodes.wing = clone("T_fly_wing", vec3(0, 0, 0), nil, fly_nodes.root)
    build_lanes()
    build_ambient_fx()
    frog_light = new_point(HIDE, vec3(0.8, 1, 0.7), 0, 2)
    for i = 1, 5 do G.home_frogs[i] = build_frog("HomeFrog"); G.home_frogs[i].root:set_enabled(false) end
    load_hi()
    -- settings menu (shared module)
    local ok, mod = pcall(function() return load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")() end)
    if ok and mod then
        SET = mod.new({ title = "SETTINGS", file = "Save/settings.cfg", click = function() sfx("click") end, music = true,
            defaults = { master = 0.5 }, theme = { accent = { 0.4, 1.0, 0.45, 1 }, accent2 = { 1.0, 0.4, 0.8, 1 } } })
        SET:apply(); G.SET = SET
    else pe_log("[Frogger] settings menu unavailable: " .. tostring(mod)) end
    pcall(audio.set_music_volume, 0.45)
    pcall(audio.play_music, "music.wav")
    respawn()
    FN.root:set_position(vec3(0, 0.03, 0))
    runtime_ui.show("hud"); runtime_ui.set_screen_overlay("hud", true); runtime_ui.hide("hud")
    G.state = "title"
    pe_log("[Frogger] ready")
end

------------------------------------------------------------------ automation helpers (MCP / tests)
G.new_game = new_game
G.fx = { splash = splash, squash = squash_burst, sparkle = sparkle, firework = firework, dust = hop_dust }
G.F = F; G.LANES = LANES; G.die = die; G.respawn = respawn; G.reach_home = reach_home
G.press = function(k, frames) G.vkeys[k] = true; G.release_in = frames or 2 end
G.sim = function(sec, keys)
    G.vkeys = keys or {}
    local n = floor(sec * 60 + 0.5)
    for _ = 1, n do update(1 / 60) end
    G.vkeys = {}
    return string.format("%s row=%d x=%.2f y=%.2f lives=%d score=%d alive=%s", G.state, F.row, F.x, F.y, G.lives, G.score, tostring(F.alive))
end

hooks { init = init, update = update }
