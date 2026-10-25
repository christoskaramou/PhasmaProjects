-- PITFALL! REMASTERED -- a modern 2.5D remake of Activision's Pitfall! (1982) for PhasmaEngine.
-- Original rules (255 LFSR screens, 20:00, 3 lives, tunnel = 3 screens) with a modern feel:
-- acceleration, coyote time, jump buffer, variable jump height, floaty apex, forgiving hitboxes,
-- magnetised vine catch. Fixed 120 Hz simulation. Cooked meshes come from template nodes M_<name>.

local W, UG, CEIL, STEP = 24.0, -5.0, -1.5, 1 / 120
local MAX_RUN = 5.4
local ACCEL_GROUND, DECEL_GROUND, ACCEL_AIR = 34.0, 42.0, 16.0
local JUMP_V = 9.4
local GRAV_UP, GRAV_DOWN, GRAV_APEX = 21.0, 30.0, 11.0
local JUMP_CUT = 2.4
local COYOTE, BUFFER = 0.13, 0.15
local CLIMB, PHW = 3.4, 0.3
local PIT_C, PIT_HW = 12.0, 3.9
local VINE_PIVOT = { x = 12.0, y = 7.6 }
local VINE_LEN, VINE_AMP, VINE_PERIOD, VINE_CATCH, HAND = 5.4, 0.95, 3.4, 1.7, 2.15
local CROC_X = { 9.0, 12.0, 15.0 }
local CROC_Y = 0.3
-- croc collision matches the cooked mesh (root at CROC_X+0.15, scale 1.15, body x -0.96..1.9, jaw -0.86..0.06):
-- the whole back/head is solid ground; ONLY the jaw zone kills, and only while the mouth is open
local CROC_L, CROC_R = -0.90, 2.25      -- standable span relative to CROC_X
local CROC_MOUTH_R = 0.15               -- x < CROC_X + this is the jaw (head end faces -X)
local TZ_STEP = 0.002                   -- per-block z offset for terrain (just above depth precision)
local TREASURE_VALUES = { [0] = 2000, 3000, 4000, 5000 }
local TREASURE_NAMES = { [0] = "MONEY BAG", "SILVER BAR", "GOLD BAR", "DIAMOND RING" }

local G = { state = "boot", t = 0, vkeys = {} }
_G.PF = G
local SET = nil
local function pscale() return SET and SET:particle_scale() or 1 end
local function shscale() return SET and SET:shake_scale() or 1 end

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function lerp(a, b, t) return a + (b - a) * t end
local function approach(v, t, d) if v < t then return math.min(v + d, t) end return math.max(v - d, t) end
local function damp(a, b, r, dt) return lerp(a, b, 1 - math.exp(-r * dt)) end
local function bitof(v, n) return math.floor(v / 2 ^ n) % 2 end
local function rshift(v, n) return math.floor(v / 2 ^ n) end
local function band(v, m)
    local r, p = 0, 1
    for _ = 0, 7 do
        if v % 2 == 1 and m % 2 == 1 then r = r + p end
        v = math.floor(v / 2); m = math.floor(m / 2); p = p * 2
    end
    return r
end
local function tex(node, kind, file, slot)
    if slot then
        if not material.set_texture(node, slot, kind, "Textures/" .. file) then material.set_texture(node, slot, kind, "Assets/Textures/" .. file) end
    elseif not material.set_texture(node, kind, "Textures/" .. file) then
        material.set_texture(node, kind, "Assets/Textures/" .. file)
    end
end
local seq = 0
local function empty(name, pos, parent)
    seq = seq + 1
    local n = scene.add_empty_node(name .. "_" .. seq)
    if parent then n:set_parent(parent) end
    n:set_position(pos or vec3(0, 0, 0))
    return n
end
local function mk(prim, pos, scale, color, o)
    o = o or {}
    seq = seq + 1
    local n = scene.add_empty_node((o.name or prim) .. "_" .. seq)
    scene.attach_primitive(n, prim)
    if o.parent then n:set_parent(o.parent) end
    n:set_position(pos)
    if o.rot then n:set_rotation(o.rot) end
    n:set_scale(scale)
    material.set(n, "base_color", color)
    material.set(n, "roughness", o.rough or 0.8)
    material.set(n, "metallic", o.metal or 0.0)
    if o.emis then material.set(n, "emissive", o.emis) end
    if o.tex then tex(n, "base_color", o.tex) end
    return n
end
local function show(n, on) n:set_enabled(on) end

local TPL = {}
local function find_templates()
    for _, e in ipairs(scene.get_entities()) do
        local l = e.label or ""
        if l:sub(1, 2) == "M_" then TPL[l:sub(3)] = e.node end
    end
end
local function tmat(name, o)
    local h = TPL[name]
    if not h then return end
    for slot = 0, #h:get_mesh_refs() - 1 do
        material.set(h, slot, "base_color", o.color or vec3(1, 1, 1))
        material.set(h, slot, "roughness", o.rough or 0.7)
        material.set(h, slot, "metallic", o.metal or 0.0)
        if o.emis then material.set(h, slot, "emissive", o.emis) end
        if o.tex and slot == 0 then tex(h, "base_color", o.tex, slot) end
    end
end
local function inst(name, pos, scale, rot, parent)
    seq = seq + 1
    local n = scene.add_empty_node(name .. "_i" .. seq)
    local h = TPL[name]
    if h then for _, m in ipairs(h:get_mesh_refs()) do n:add_mesh_ref(m) end
    else scene.attach_primitive(n, "sphere") end
    if parent then n:set_parent(parent) end
    n:set_position(pos or vec3(0, 0, 0))
    if rot then n:set_rotation(rot) end
    if scale then n:set_scale(type(scale) == "number" and vec3(scale, scale, scale) or scale) end
    return n
end
local function sfx(name) if audio and audio.play then pcall(audio.play, name .. ".wav") end end

local keys_prev = {}
local function down(k) return G.vkeys[k] or input.is_key_pressed(k) end
local function anydown(...) for _, k in ipairs({ ... }) do if down(k) then return true end end return false end
local function pressed(...)
    for _, k in ipairs({ ... }) do if down(k) and not keys_prev[k] then return true end end
    return false
end
local watched = { "Left", "Right", "Up", "Down", "A", "D", "W", "S", "Space", "Return", "Escape", "P", "M", "Tab" }
local function latch_keys() for _, k in ipairs(watched) do keys_prev[k] = down(k) end end

local ROOMS = {}
do
    local b = 0xC4
    for i = 0, 254 do
        ROOMS[i] = b
        local fb = (bitof(b, 7) + bitof(b, 5) + bitof(b, 4) + bitof(b, 3)) % 2
        b = (b * 2) % 256 + fb
    end
end
local function room(i)
    local b = ROOMS[i % 255]
    local r = { byte = b, obj = band(b, 7), kind = band(rshift(b, 3), 7), trees = band(rshift(b, 6), 3), wall_right = band(b, 0x80) ~= 0 }
    r.ladder = (r.kind == 0 or r.kind == 1)
    r.holes = {}
    if r.kind == 0 then r.holes = { 12.0 } elseif r.kind == 1 then r.holes = { 6.0, 12.0, 18.0 } end
    if r.kind == 2 then r.pit = "tar" elseif r.kind == 3 then r.pit = "swamp"
    elseif r.kind == 4 then r.pit = "croc" elseif r.kind == 5 or r.kind == 6 then r.pit = "shift_tar"
    elseif r.kind == 7 then r.pit = "quicksand" end
    r.vine = (r.kind == 2 or r.kind == 3 or r.kind == 6 or (r.kind == 4 and band(b, 2) ~= 0))
    r.treasure = (r.kind == 5) and band(r.obj, 3) or nil
    r.logs, r.fire, r.cobra = {}, false, false
    if r.kind ~= 4 and r.kind ~= 5 then
        local o = r.obj
        if o == 0 then r.logs = { { 19, true } }
        elseif o == 1 then r.logs = { { 17, true }, { 20.5, true } }
        elseif o == 2 then r.logs = { { 9, true }, { 20.5, true } }
        elseif o == 3 then r.logs = { { 9, true }, { 17, true }, { 20.5, true } }
        elseif o == 4 then r.logs = { { 19.5, false } }
        elseif o == 5 then r.logs = { { 18.0, false }, { 20.0, false }, { 22.0, false } }
        elseif o == 6 then r.fire = true
        else r.cobra = true end
        if r.pit then for _, l in ipairs(r.logs) do if not l[2] then l[1] = math.max(l[1], 18.0) end end end
    end
    r.wall = r.ladder and (r.wall_right and 20.5 or 3.5) or nil
    r.scorpion = not r.ladder
    return r
end
local TOTAL_TREASURES = 0
for i = 0, 254 do if band(rshift(ROOMS[i], 3), 7) == 5 then TOTAL_TREASURES = TOTAL_TREASURES + 1 end end

local cam
local CAM_POS = { y = 2.7, z = 17.5 }
local cam_kick, cam_shake, cam_x = 0.0, 0.0, 12.0
local function new_light()
    lights.add_point()
    local idx = #lights.get_point_lights() - 1
    lights.set_point_light(idx, vec3(0, -100, 0), vec3(1, 1, 1), 0.0, 1.0)
    return idx
end
local function set_light(idx, pos, c, i, r) lights.set_point_light(idx, pos, c, i, r) end
local function hide_light(idx) set_light(idx, vec3(0, -100, 0), vec3(1, 1, 1), 0, 1) end

local function setup_render()
    local s = scene.add_empty_node("PitfallSceneSettings")
    s:set_scene_settings(true)
    local function S(k, v) pcall(settings.set, k, v) end
    pcall(settings.set_render_mode, "raster")
    S("motion_blur", false); S("taa", true); S("cas_sharpening", false); S("dof", false)
    S("shadows", true); S("shadow_map_size", 2048); S("shadow_distance", 60.0)
    S("bloom", true); S("bloom_strength", 0.6); S("bloom_range", 0.65)  -- see common/RENDER_SETTINGS.md
    S("tonemapping", true); S("fxaa", false)
    S("ssao", true); S("ssao_radius", 0.6); S("ssao_intensity", 1.3)
    S("fog", true); S("fog_density", 0.017); S("fog_start", 12.0)
    S("color_grading", true); S("color_grading_saturation", 1.2); S("color_grading_contrast", 1.1)
    S("IBL", true); S("IBL_intensity", 1.4)
    cam = get_camera()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(-0.4, -1.0, -0.5), vec3(1.0, 0.88, 0.68), 5.5)
end

local SKIN, SHIRT, PANTS = vec3(0.93, 0.66, 0.48), vec3(0.32, 0.58, 0.22), vec3(0.62, 0.5, 0.32)
local function setup_materials()
    tmat("trunk", { color = vec3(0.75, 0.62, 0.5), tex = "bark.png", rough = 0.95 })
    tmat("canopy", { color = vec3(0.45, 0.8, 0.35), tex = "leaves.png", rough = 0.55 })
    tmat("fern", { color = vec3(0.32, 0.7, 0.26), rough = 0.6 })
    tmat("grass", { color = vec3(0.4, 0.75, 0.25), rough = 0.7 })
    tmat("rock", { color = vec3(0.5, 0.48, 0.44), tex = "dirt.png", rough = 0.85 })
    tmat("liana", { color = vec3(0.3, 0.42, 0.16), rough = 0.8 })
    tmat("log", { color = vec3(0.7, 0.5, 0.32), tex = "bark.png", rough = 0.9 })
    tmat("logends", { color = vec3(0.95, 0.75, 0.48), rough = 0.8 })
    tmat("croc_body", { color = vec3(0.5, 0.95, 0.35), tex = "scales.png", rough = 0.4, emis = vec3(0.05, 0.12, 0.03) })
    tmat("croc_jaw", { color = vec3(0.5, 0.95, 0.35), tex = "scales.png", rough = 0.4, emis = vec3(0.05, 0.12, 0.03) })
    tmat("croc_teeth", { color = vec3(0.95, 0.93, 0.85), rough = 0.3 })
    tmat("scorpion", { color = vec3(0.92, 0.9, 0.95), rough = 0.25, metal = 0.2 })
    tmat("vine_rope", { color = vec3(0.42, 0.5, 0.2), rough = 0.8 })
    tmat("vine_leaves", { color = vec3(0.35, 0.75, 0.25), rough = 0.5 })
    for _, n in ipairs({ "h_head", "h_hand", "h_upperarm", "h_forearm" }) do tmat(n, { color = SKIN, rough = 0.6 }) end
    tmat("h_torso", { color = SHIRT, tex = "cloth.png", rough = 0.9 })
    tmat("h_collar", { color = SHIRT * 0.8, rough = 0.9 })
    tmat("h_hips", { color = PANTS, tex = "cloth.png", rough = 0.9 })
    tmat("h_thigh", { color = PANTS, tex = "cloth.png", rough = 0.9 })
    tmat("h_shin", { color = PANTS * 0.95, tex = "cloth.png", rough = 0.9 })
    tmat("h_boot", { color = vec3(0.28, 0.17, 0.08), rough = 0.45 })
    tmat("h_belt", { color = vec3(0.3, 0.18, 0.08), rough = 0.5 })
    tmat("h_hair", { color = vec3(0.32, 0.18, 0.08), rough = 0.7 })
    tmat("h_hat", { color = vec3(0.86, 0.76, 0.52), tex = "cloth.png", rough = 0.85 })
    tmat("h_hatband", { color = vec3(0.35, 0.2, 0.1), rough = 0.6 })
    tmat("h_eyes", { color = vec3(0.05, 0.05, 0.05), rough = 0.2 })
end

local WORLD = {}
local EMIT = {}  -- ambient emitters with base spawn rates (scaled by particle quality)
local function amb(o) local i = particles.add_emitter(o); EMIT[#EMIT + 1] = { i, o.spawn_rate }; return i end

local function build_static()
    WORLD.sky = mk("cube", vec3(12, 6, -42), vec3(160, 40, 0.2), vec3(0, 0, 0), { tex = "sky.png", rough = 1.0, name = "sky" })
    tex(WORLD.sky, "emissive", "sky.png")
    material.set(WORLD.sky, "emissive", vec3(1, 1, 1))
    WORLD.far = empty("farlayer")
    for i = 0, 24 do
        local x, z = -26 + i * 3.2, -20 - (i % 3) * 2
        inst("trunk", vec3(x, -0.5, z), vec3(0.7, 1.2 + (i % 4) * 0.15, 0.7), vec3(0, i * 40, 0), WORLD.far)
        inst("canopy", vec3(x + 0.5, 9.5 + (i % 3) * 0.8, z), 2.2, vec3(0, i * 57, 0), WORLD.far)
    end
    WORLD.mid = empty("midlayer")
    for i = 0, 12 do
        local x, z = -8 + i * 3.4 + (i % 3) * 0.7, -9.5 - (i % 2) * 2.5
        inst("trunk", vec3(x, -0.2, z), vec3(0.8, 1.0, 0.8), vec3(0, i * 67, 0), WORLD.mid)
        inst("canopy", vec3(x + 0.3, 8.6 + (i % 2) * 0.6, z), 1.9, vec3(0, i * 33, 0), WORLD.mid)
        inst("fern", vec3(x + 1.5, 0, z + 1.5), 1.2, vec3(0, i * 29, 0), WORLD.mid)
    end
    for i = 0, 7 do inst("rock", vec3(-4 + i * 4.3, 0.05, -6.8 - (i % 2) * 2), vec3(1, 0.8, 1), vec3(0, i * 50, 0), WORLD.mid) end
    mk("cube", vec3(12, -0.3, -16), vec3(120, 0.6, 22), vec3(0.09, 0.17, 0.06), { tex = "grass.png", rough = 1.0, name = "field" })
    WORLD.grass, WORLD.dirt = {}, {}
    WORLD.gz, WORLD.dz = {}, {}
    for i = 1, 4 do
        WORLD.gz[i], WORLD.dz[i] = -2.4 + (2 * i) * TZ_STEP, -2.4 + (2 * i + 1) * TZ_STEP
        WORLD.grass[i] = mk("cube", vec3(0, -0.2, WORLD.gz[i]), vec3(1, 0.4, 7.2), vec3(0.5, 0.6, 0.4), { tex = "grass.png", rough = 0.95, name = "grass" })
        WORLD.dirt[i] = mk("cube", vec3(0, -0.95, WORLD.dz[i]), vec3(1, 1.1, 7.2), vec3(0.9, 0.85, 0.8), { tex = "dirt.png", rough = 1.0, name = "dirt" })
    end
    -- side blocks sit slightly lower/behind so their top + front faces never coincide with the crust segments
    mk("cube", vec3(-12, -0.75 - TZ_STEP, -2.4 - 1 * TZ_STEP), vec3(24, 1.5, 7.2), vec3(0.5, 0.6, 0.4), { tex = "grass.png", name = "grassL" })
    mk("cube", vec3(36, -0.75 - TZ_STEP, -2.4 - 2 * TZ_STEP), vec3(24, 1.5, 7.2), vec3(0.5, 0.6, 0.4), { tex = "grass.png", name = "grassR" })
    mk("cube", vec3(12, (UG + CEIL) / 2, -2.6), vec3(80, CEIL - UG, 0.6), vec3(0.52, 0.47, 0.44), { tex = "brick.png", rough = 0.9, name = "tunnelback" })
    mk("cube", vec3(12, UG - 1.25, -1.5), vec3(80, 2.5, 9), vec3(0.55, 0.45, 0.38), { tex = "dirt.png", name = "tunnelfloor" })
    mk("cube", vec3(12, -10, -1.5), vec3(80, 5, 9), vec3(0.08, 0.06, 0.05), { name = "bedrock" })
    for i = 0, 6 do
        mk("cube", vec3(-4 + i * 5.5, (UG + CEIL) / 2, -2.1), vec3(0.35, CEIL - UG, 0.35), vec3(0.35, 0.22, 0.12), { tex = "bark.png", name = "beam" })
    end
    mk("cube", vec3(12, CEIL - 0.15, -2.1), vec3(80, 0.3, 0.35), vec3(0.35, 0.22, 0.12), { tex = "bark.png", name = "lintel" })
    WORLD.trees = {}
    for i = 1, 4 do
        WORLD.trees[i] = { trunk = inst("trunk", vec3(0, -0.1, -4.5), 1.0, vec3(0, i * 80, 0)),
            crown = inst("canopy", vec3(0, 8.0, -4.5), 2.0, vec3(0, i * 45, 0)) }
    end
    for i = 0, 13 do inst("canopy", vec3(-3 + i * 2.3, 7.2 + (i % 3) * 0.5, -3.0 - (i % 2) * 1.5), 1.5 + (i % 3) * 0.25, vec3(0, i * 71, 0)) end
    for i = 0, 9 do inst("liana", vec3(-1 + i * 2.8 + (i % 2) * 0.6, 7.0, -2.2 - (i % 3) * 0.4), vec3(1, 0.8 + (i % 3) * 0.25, 1), vec3(0, i * 40, 0)) end
    for i = 0, 15 do inst("fern", vec3(-1 + i * 1.75, 0.0, -2.0 - (i % 3) * 0.6), 0.8 + (i % 3) * 0.2, vec3(0, i * 47, 0)) end
    for i = 0, 30 do inst("grass", vec3(-1.5 + i * 0.9, 0.0, -1.0 - (i % 4) * 0.5), 1.0 + (i % 3) * 0.3, vec3(0, i * 61, 0)) end
    WORLD.torch_lights = {}
    for i, x in ipairs({ 3.5, 12.0, 20.5 }) do
        mk("cylinder", vec3(x, -3.6, -1.9), vec3(0.06, 0.35, 0.06), vec3(0.3, 0.2, 0.1), { name = "torchstick" })
        mk("sphere", vec3(x, -3.1, -1.85), vec3(0.16, 0.26, 0.16), vec3(1, 0.45, 0.05), { emis = vec3(9.0, 2.8, 0.3), name = "torchflame" })
        WORLD.torch_lights[i] = { idx = new_light(), x = x }
        amb({ position = vec3(x, -2.9, -1.85), velocity = vec3(0, 1.1, 0), color_start = vec4(1.0, 0.7, 0.2, 1), color_end = vec4(0.6, 0.1, 0.0, 0),
            gravity = vec3(0, 0.6, 0), count = 70, size_min = 0.03, size_max = 0.09, life_min = 0.3, life_max = 0.9, spawn_rate = 55,
            spawn_radius = 0.08, noise_strength = 0.9, drag = 0.2 })
    end
    WORLD.fill_light = new_light()
    set_light(WORLD.fill_light, vec3(12, -3.0, 3.0), vec3(0.5, 0.65, 1.0), 22.0, 16.0)
    -- god rays: chains of faint large particles along slanted beams, plus glittering motes
    for i, sx in ipairs({ 4.0, 10.5, 17.0, 23.0 }) do
        local z = -2.4 - (i % 2) * 1.0
        for k = 0, 10 do
            local f = k / 10
            amb({ position = vec3(sx + 3.6 * (1 - f) - 1.0, 0.3 + 7.0 * (1 - f), z), velocity = vec3(0.05, -0.08, 0),
                color_start = vec4(0.06, 0.048, 0.028, 0.05), color_end = vec4(0, 0, 0, 0), gravity = vec3(0, 0, 0), count = 24,
                size_min = 0.45, size_max = 0.8, life_min = 2.5, life_max = 4.0, spawn_rate = 6, spawn_radius = 0.3, noise_strength = 0.05, drag = 0.9 })
        end
        amb({ position = vec3(sx + 0.8, 2.0, z + 0.3), velocity = vec3(0, -0.05, 0), color_start = vec4(1.0, 0.92, 0.7, 0.9), color_end = vec4(1.0, 0.8, 0.5, 0),
            gravity = vec3(0, -0.02, 0), count = 40, size_min = 0.015, size_max = 0.04, life_min = 3.0, life_max = 5.0, spawn_rate = 8,
            spawn_radius = 1.4, noise_strength = 0.3, drag = 0.6 })
    end
    for i, x in ipairs({ 3, 9, 15, 21 }) do  -- falling leaves
        amb({ position = vec3(x, 6.5, -0.5 - (i % 2)), velocity = vec3(0.3, -0.6, 0), color_start = vec4(0.45, 0.75, 0.2, 1), color_end = vec4(0.75, 0.55, 0.15, 0.9),
            gravity = vec3(0.1, -0.35, 0), count = 18, size_min = 0.06, size_max = 0.12, life_min = 6.0, life_max = 9.0, spawn_rate = 2.0,
            spawn_radius = 2.5, noise_strength = 1.4, drag = 0.8 })
    end
    for i = 0, 5 do  -- ground mist
        amb({ position = vec3(i * 4.8, 0.25, -1.5), velocity = vec3(0.12, 0.02, 0), color_start = vec4(0.05, 0.06, 0.06, 0.05), color_end = vec4(0, 0, 0, 0),
            gravity = vec3(0, 0, 0), count = 20, size_min = 0.9, size_max = 1.5, life_min = 4.0, life_max = 7.0, spawn_rate = 4, spawn_radius = 2.2,
            noise_strength = 0.1, drag = 0.9 })
    end
    amb({ position = vec3(12, 2.5, -1.0), velocity = vec3(0, 0.05, 0), color_start = vec4(1.0, 0.95, 0.5, 1), color_end = vec4(0.6, 1.0, 0.3, 0),
        gravity = vec3(0, 0.02, 0), count = 220, size_min = 0.03, size_max = 0.07, life_min = 3.0, life_max = 6.0, spawn_rate = 40,
        spawn_radius = 12.0, noise_strength = 0.6, drag = 0.4 })  -- fireflies
    WORLD.flies = {}
    for i = 1, 2 do
        local n = mk("sphere", vec3(0, -100, 0), vec3(0.06, 0.06, 0.06), vec3(0.8, 1, 0.4), { emis = vec3(6, 8, 2), name = "firefly" })
        WORLD.flies[i] = { node = n, light = new_light(), ph = i * 2.1 }
    end
    amb({ position = vec3(12, -3.3, -0.5), velocity = vec3(0.05, 0.0, 0), color_start = vec4(0.9, 0.7, 0.5, 0.6), color_end = vec4(0.5, 0.4, 0.3, 0),
        gravity = vec3(0, -0.01, 0), count = 80, size_min = 0.015, size_max = 0.035, life_min = 4.0, life_max = 7.0, spawn_rate = 15,
        spawn_radius = 11.0, noise_strength = 0.3, drag = 0.6 })  -- tunnel dust
end
local function apply_particle_quality()
    local s = pscale()
    for _, e in ipairs(EMIT) do particles.set_emitter(e[1], "spawn_rate", e[2] * s) end
end

local OBJ = {}
local function build_dynamic()
    OBJ.pit = mk("cylinder", vec3(PIT_C, 0.01, 0), vec3(PIT_HW, 0.03, 1.15), vec3(0.05, 0.04, 0.03), { rough = 0.05, tex = "tar.png", name = "pit" })
    OBJ.pit_rim = mk("cylinder", vec3(PIT_C, -0.02, 0), vec3(PIT_HW + 0.3, 0.03, 1.35), vec3(0.25, 0.18, 0.1), { tex = "dirt.png", name = "pitrim" })
    OBJ.pit_bubbles = particles.add_emitter({ position = vec3(PIT_C, 0.05, 0), velocity = vec3(0, 0.6, 0), color_start = vec4(0.12, 0.1, 0.08, 1),
        color_end = vec4(0.05, 0.05, 0.05, 0), gravity = vec3(0, 0, 0), count = 80, size_min = 0.08, size_max = 0.22, life_min = 0.3,
        life_max = 0.9, spawn_rate = 0, spawn_radius = 2.0, noise_strength = 0.2, drag = 0.5 })
    OBJ.ripples = particles.add_emitter({ position = vec3(PIT_C, 0.06, 0), velocity = vec3(0, 0.05, 0), color_start = vec4(0.85, 1.0, 1.0, 0.8),
        color_end = vec4(0.6, 0.9, 1.0, 0), gravity = vec3(0, 0, 0), count = 70, size_min = 0.04, size_max = 0.1, life_min = 0.6,
        life_max = 1.4, spawn_rate = 0, spawn_radius = 2.6, noise_strength = 0.05, drag = 0.8 })
    OBJ.pit_mist = particles.add_emitter({ position = vec3(PIT_C, 0.3, 0), velocity = vec3(0, 0.15, 0), color_start = vec4(0.06, 0.08, 0.07, 0.05),
        color_end = vec4(0, 0, 0, 0), gravity = vec3(0, 0, 0), count = 30, size_min = 0.8, size_max = 1.4, life_min = 2.0,
        life_max = 4.0, spawn_rate = 0, spawn_radius = 2.4, noise_strength = 0.1, drag = 0.9 })
    OBJ.lily = {}
    for i, lx in ipairs({ 9.3, 11.2, 13.4, 14.8 }) do
        OBJ.lily[i] = mk("cylinder", vec3(lx, 0.05, (i % 2 == 0) and 0.55 or -0.5), vec3(0.42, 0.03, 0.36), vec3(0.2, 0.5, 0.15), { rough = 0.6, name = "lily" })
        if i % 2 == 1 then mk("sphere", vec3(0.1, 2.0, 0), vec3(0.3, 4, 0.3), vec3(1, 0.6, 0.8), { parent = OBJ.lily[i], emis = vec3(0.8, 0.3, 0.5), name = "lotus" }) end
    end
    OBJ.shafts = {}
    for i = 1, 3 do OBJ.shafts[i] = mk("cube", vec3(0, -0.8, -1.5), vec3(2.0, 1.6, 0.1), vec3(0.02, 0.02, 0.02), { name = "shaft" }) end
    OBJ.ladder = empty("ladder", vec3(12, 0, 0))
    for _, sx in ipairs({ -0.45, 0.45 }) do
        mk("cylinder", vec3(sx, -2.5, 0), vec3(0.07, 2.6, 0.07), vec3(0.6, 0.42, 0.22), { parent = OBJ.ladder, tex = "bark.png", name = "rail" })
    end
    for i = 0, 8 do
        mk("cylinder", vec3(0, -4.7 + i * 0.58, 0), vec3(0.04, 0.46, 0.04), vec3(0.7, 0.5, 0.28), { parent = OBJ.ladder, rot = vec3(0, 0, 90), name = "rung" })
    end
    OBJ.vine = empty("vine", vec3(VINE_PIVOT.x, VINE_PIVOT.y, 0))
    inst("vine_rope", vec3(0, 0, 0), 1.0, nil, OBJ.vine)
    inst("vine_leaves", vec3(0, 0, 0), 1.0, nil, OBJ.vine)
    OBJ.vine_tip = mk("sphere", vec3(0, -VINE_LEN, 0), vec3(0.16, 0.16, 0.16), vec3(0.4, 0.6, 0.2), { parent = OBJ.vine, emis = vec3(0, 0, 0), name = "vinetip" })
    OBJ.vine_light = new_light()
    OBJ.crocs = {}
    for i = 1, 3 do
        local c = { root = empty("croc") }
        c.root:set_scale(vec3(1.15, 2.0, 1.6))
        inst("croc_body", vec3(0, 0, 0), 1.0, nil, c.root)
        c.jaw = empty("crocjaw", vec3(-0.05, 0.02, 0), c.root)
        inst("croc_jaw", vec3(0, 0, 0), 1.0, nil, c.jaw)
        inst("croc_teeth", vec3(0, 0, 0), 1.0, nil, c.jaw)
        for _, z in ipairs({ 0.13, -0.13 }) do
            mk("sphere", vec3(-0.04, 0.15, z), vec3(0.045, 0.04, 0.03), vec3(1, 0.85, 0.1), { parent = c.jaw, emis = vec3(2.4, 1.8, 0.1), name = "eye" })
        end
        c.jaw_a = 0
        OBJ.crocs[i] = c
    end
    OBJ.logs = {}
    for i = 1, 3 do
        local l = { root = empty("log", vec3(0, 0.45, 0)) }
        l.spin = empty("logspin", vec3(0, 0, 0), l.root)
        inst("log", vec3(0, 0, 0), 1.0, nil, l.spin)
        inst("logends", vec3(0, 0, 0), 1.0, nil, l.spin)
        OBJ.logs[i] = l
    end
    OBJ.fire = empty("fire")
    inst("log", vec3(-0.15, 0.12, 0), vec3(0.3, 0.3, 0.6), vec3(0, 60, 0), OBJ.fire)
    inst("log", vec3(0.15, 0.12, 0), vec3(0.3, 0.3, 0.6), vec3(0, -60, 0), OBJ.fire)
    OBJ.flames = {}
    for i = 1, 4 do
        OBJ.flames[i] = mk("cone", vec3((i - 2.5) * 0.16, 0.55, (i % 2) * 0.1), vec3(0.2, 0.5, 0.2), vec3(1, 0.5, 0.1), { parent = OBJ.fire, emis = vec3(8, 2.6, 0.3), name = "flame" })
    end
    OBJ.fire_light = new_light()
    OBJ.fire_emitter = particles.add_emitter({ position = vec3(0, -100, 0), velocity = vec3(0, 2.4, 0), color_start = vec4(1.0, 0.75, 0.2, 1),
        color_end = vec4(0.7, 0.1, 0.0, 0), gravity = vec3(0, 1.0, 0), count = 150, size_min = 0.05, size_max = 0.18,
        life_min = 0.3, life_max = 0.9, spawn_rate = 0, spawn_radius = 0.25, noise_strength = 1.4, drag = 0.3 })
    OBJ.smoke_emitter = particles.add_emitter({ position = vec3(0, -100, 0), velocity = vec3(0.1, 1.2, 0), color_start = vec4(0.05, 0.05, 0.05, 0.1),
        color_end = vec4(0, 0, 0, 0), gravity = vec3(0, 0.3, 0), count = 40, size_min = 0.3, size_max = 0.7, life_min = 1.5,
        life_max = 2.5, spawn_rate = 0, spawn_radius = 0.2, noise_strength = 0.4, drag = 0.4 })
    OBJ.cobra = empty("cobra")
    local cg = vec3(0.6, 0.55, 0.15)
    mk("torus", vec3(0, 0.12, 0), vec3(0.45, 0.6, 0.45), cg, { parent = OBJ.cobra, rough = 0.35, name = "coil" })
    mk("torus", vec3(0, 0.3, 0), vec3(0.32, 0.6, 0.32), cg, { parent = OBJ.cobra, rough = 0.35, name = "coil" })
    OBJ.cobra_neck = empty("cobraneck", vec3(0, 0.3, 0), OBJ.cobra)
    mk("cylinder", vec3(0, 0.45, 0), vec3(0.11, 0.45, 0.11), cg, { parent = OBJ.cobra_neck, rough = 0.35, name = "neck" })
    mk("sphere", vec3(0, 0.95, 0), vec3(0.32, 0.3, 0.07), cg * 0.85, { parent = OBJ.cobra_neck, name = "hood" })
    mk("sphere", vec3(-0.12, 1.0, 0), vec3(0.18, 0.11, 0.13), cg, { parent = OBJ.cobra_neck, name = "head" })
    for _, z in ipairs({ 0.08, -0.08 }) do
        mk("sphere", vec3(-0.2, 1.05, z), vec3(0.035, 0.035, 0.035), vec3(1, 0, 0), { parent = OBJ.cobra_neck, emis = vec3(5, 0.2, 0.1), name = "eye" })
    end
    OBJ.tre, OBJ.tre_root = {}, empty("treasure")
    OBJ.tre_root:set_scale(vec3(1.5, 1.5, 1.5))
    OBJ.tre[0] = empty("moneybag", nil, OBJ.tre_root)
    mk("sphere", vec3(0, 0.4, 0), vec3(0.42, 0.4, 0.42), vec3(0.75, 0.62, 0.38), { parent = OBJ.tre[0], tex = "cloth.png", name = "bag" })
    mk("cone", vec3(0, 0.88, 0), vec3(0.18, 0.15, 0.18), vec3(0.7, 0.58, 0.35), { parent = OBJ.tre[0], name = "bagtop" })
    mk("cube", vec3(0, 0.42, 0.42), vec3(0.3, 0.3, 0.02), vec3(0.2, 0.6, 0.2), { parent = OBJ.tre[0], emis = vec3(0.3, 1.0, 0.3), name = "dollar" })
    OBJ.tre[1] = empty("silver", nil, OBJ.tre_root)
    mk("cube", vec3(0, 0.3, 0), vec3(0.9, 0.35, 0.45), vec3(0.85, 0.87, 0.9), { parent = OBJ.tre[1], metal = 1.0, rough = 0.15, emis = vec3(0.3, 0.3, 0.35), name = "silverbar" })
    OBJ.tre[2] = empty("gold", nil, OBJ.tre_root)
    mk("cube", vec3(0, 0.3, 0), vec3(0.9, 0.35, 0.45), vec3(1.0, 0.78, 0.25), { parent = OBJ.tre[2], metal = 1.0, rough = 0.2, emis = vec3(0.6, 0.4, 0.05), name = "goldbar" })
    OBJ.tre[3] = empty("ring", nil, OBJ.tre_root)
    mk("torus", vec3(0, 0.45, 0), vec3(0.4, 0.4, 0.4), vec3(1.0, 0.8, 0.3), { parent = OBJ.tre[3], rot = vec3(90, 0, 0), metal = 1.0, rough = 0.2, emis = vec3(0.5, 0.35, 0.05), name = "band" })
    mk("ico_sphere", vec3(0, 0.95, 0), vec3(0.2, 0.2, 0.2), vec3(0.8, 0.95, 1.0), { parent = OBJ.tre[3], rough = 0.02, emis = vec3(2.5, 3.0, 4.0), name = "diamond" })
    OBJ.tre_light = new_light()
    OBJ.tre_emitter = particles.add_emitter({ position = vec3(0, -100, 0), velocity = vec3(0, 0.6, 0), color_start = vec4(1.0, 0.95, 0.6, 1),
        color_end = vec4(1.0, 0.8, 0.2, 0), gravity = vec3(0, 0.2, 0), count = 70, size_min = 0.03, size_max = 0.08,
        life_min = 0.5, life_max = 1.2, spawn_rate = 0, spawn_radius = 0.6, noise_strength = 0.6, drag = 0.4 })
    OBJ.wall = mk("cube", vec3(0, (UG + CEIL) / 2, -0.4), vec3(1.0, CEIL - UG, 3.6), vec3(1.0, 0.85, 0.8), { tex = "brick.png", name = "ugwall" })
    OBJ.scorp = empty("scorpion", vec3(0, UG, 0))
    inst("scorpion", vec3(0, 0, 0), 1.2, nil, OBJ.scorp)
end

local H = {}
local function build_harry()
    H.root = empty("Harry", vec3(2, 0, 0))
    H.yaw = empty("HarryYaw", nil, H.root)
    H.pelvis = empty("HarryPelvis", vec3(0, 0.92, 0), H.yaw)
    inst("h_hips", vec3(0, -0.04, 0), 1.0, nil, H.pelvis)
    inst("h_belt", vec3(0, -0.04, 0), 1.0, nil, H.pelvis)
    mk("cube", vec3(0.17, 0.09, 0), vec3(0.03, 0.06, 0.08), vec3(1.0, 0.8, 0.3), { parent = H.pelvis, metal = 1.0, rough = 0.25, emis = vec3(0.25, 0.18, 0.02), name = "buckle" })
    local function leg(z)
        local hip = empty("hip", vec3(0, -0.02, z), H.pelvis)
        inst("h_thigh", nil, 1.0, nil, hip)
        local knee = empty("knee", vec3(0, -0.42, 0), hip)
        inst("h_shin", nil, 1.0, nil, knee)
        inst("h_boot", nil, 1.0, nil, knee)
        return hip, knee
    end
    H.hipL, H.kneeL = leg(0.1)
    H.hipR, H.kneeR = leg(-0.1)
    H.spine = empty("spine", vec3(0, 0.1, 0), H.pelvis)
    inst("h_torso", nil, 1.0, nil, H.spine)
    inst("h_collar", nil, 1.0, nil, H.spine)
    H.neck = empty("neck", vec3(0, 0.6, 0), H.spine)
    H.head = empty("head", vec3(0, 0.18, 0), H.neck)
    for _, n in ipairs({ "h_head", "h_hair", "h_eyes" }) do inst(n, nil, 1.0, nil, H.head) end
    inst("h_hat", vec3(0, 0.08, 0), 1.0, vec3(0, 0, -5), H.head)
    inst("h_hatband", vec3(0, 0.08, 0), 1.0, vec3(0, 0, -5), H.head)
    local function arm(z)
        local sh = empty("shoulder", vec3(0, 0.52, z), H.spine)
        inst("h_upperarm", nil, 1.0, nil, sh)
        local el = empty("elbow", vec3(0, -0.3, 0), sh)
        inst("h_forearm", nil, 1.0, nil, el)
        inst("h_hand", nil, 1.0, nil, el)
        return sh, el
    end
    H.shL, H.elL = arm(0.21)
    H.shR, H.elR = arm(-0.21)
    H.squash, H.lean = 0, 0
end

local function col(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end
local function surf()
    local s = runtime_ui.get_surface_size()
    return (s and (s.w or s.width)) or 1280, (s and (s.h or s.height)) or 720
end
local function quad(screen, id, x, y, w, h, o)
    o.x, o.y, o.w, o.h = x, y, w, h
    if o.style == "text" then o.fill = o.fill or col(0, 0, 0, 0); o.border = o.border or col(0, 0, 0, 0) end
    runtime_ui.set_quad(screen, id, o)
end
local function fmt_time(t) t = math.max(0, t); return string.format("%02d:%02d", math.floor(t / 60), math.floor(t % 60)) end
local toast = { text = "", t = 0 }
local function show_toast(s) toast.text = s; toast.t = 2.2 end
G.flash, G.flash_col = 0, col(1, 1, 1)
local function flash(r, g, b, a) G.flash = a; G.flash_col = col(r, g, b) end
local score_shown = 2000

local function draw_hud(dt)
    local sw, sh = surf()
    local k = sw / 1280
    local function S(v) return v * k end
    score_shown = damp(score_shown, G.score, 10, dt)
    if math.abs(score_shown - G.score) < 1 then score_shown = G.score end
    quad("hud", "bar", S(16), S(10), sw - S(32), S(52), { style = "panel", fill = col(0.02, 0.06, 0.03, 0.55), corner_radius = S(16), border = col(0.95, 0.8, 0.35, 0.7), no_input = true })
    quad("hud", "score", S(36), S(10), S(330), S(52), { title = string.format("SCORE  %06d", math.floor(math.max(0, score_shown) + 0.5)), style = "text", text_color = col(1.0, 0.86, 0.35), font_scale = 1.6 * k, align_h = "left", no_input = true })
    quad("hud", "time", sw / 2 - S(130), S(10), S(260), S(52), { title = "TIME  " .. fmt_time(G.time), style = "text", text_color = G.time < 60 and col(1, 0.35, 0.3) or col(0.92, 0.96, 0.85), font_scale = 1.6 * k, align_h = "center", no_input = true })
    local lives = string.rep("| ", math.max(0, G.lives - 1))
    quad("hud", "lives", sw - S(520), S(10), S(200), S(52), { title = "LIVES  " .. (lives ~= "" and lives or "-"), style = "text", text_color = col(0.6, 1.0, 0.5), font_scale = 1.6 * k, align_h = "center", no_input = true })
    quad("hud", "tre", sw - S(320), S(10), S(290), S(52), { title = string.format("TREASURE  %d/%d", G.found, TOTAL_TREASURES), style = "text", text_color = col(1.0, 0.8, 0.3), font_scale = 1.6 * k, align_h = "right", no_input = true })
    quad("hud", "room", S(16), sh - S(46), S(420), S(34), { title = string.format("JUNGLE %03d%s", G.screen + 1, G.under and "  -  TUNNEL" or ""), style = "text", text_color = col(0.85, 0.95, 0.75, 0.8), font_scale = 1.2 * k, align_h = "left", no_input = true })
    quad("hud", "hint", sw - S(420), sh - S(46), S(400), S(34), { title = "TAB settings   M mute   P pause", style = "text", text_color = col(0.85, 0.95, 0.75, 0.55), font_scale = 1.1 * k, align_h = "right", no_input = true })
    local a = clamp(toast.t, 0, 1)
    quad("hud", "toast", sw / 2 - S(320), S(80), S(640), S(54), { title = toast.text, style = "panel", fill = col(0.08, 0.06, 0.0, 0.6 * a), border = col(0.9, 0.75, 0.3, 0.6 * a), text_color = col(1, 0.9, 0.4, a), font_scale = 1.6 * k, corner_radius = S(12), visible = a > 0.01, no_input = true })
    local f = G.flash or 0
    quad("hud", "flash", 0, 0, sw, sh, { style = "panel", fill = col(G.flash_col.r, G.flash_col.g, G.flash_col.b, f), border = col(0, 0, 0, 0), visible = f > 0.01, no_input = true })
end

local function draw_menu(kind)
    local sw, sh = surf()
    local k = sw / 1280
    local function S(v) return v * k end
    runtime_ui.show("menu")
    runtime_ui.set_screen_overlay("menu", true)
    local pulse = 0.65 + 0.35 * math.sin(G.t * 4)
    quad("menu", "dim", 0, 0, sw, sh, { style = "panel", fill = col(0.0, 0.03, 0.0, kind == "title" and 0.3 or 0.55), border = col(0, 0, 0, 0), corner_radius = 0, no_input = true })
    if kind == "title" then
        local bob = math.sin(G.t * 1.6) * S(6)
        quad("menu", "logo_shadow", sw / 2 - S(414), S(96) + bob, S(840), S(150), { title = "PITFALL!", style = "text", text_color = col(0.15, 0.05, 0.0, 0.8), font_scale = 6.0 * k, align_h = "center", no_input = true })
        quad("menu", "logo", sw / 2 - S(420), S(90) + bob, S(840), S(150), { title = "PITFALL!", style = "text", text_color = col(1.0, 0.78 + 0.1 * pulse, 0.2), font_scale = 6.0 * k, align_h = "center", no_input = true })
        quad("menu", "sub", sw / 2 - S(420), S(232), S(840), S(40), { title = "HARRY'S JUNGLE ADVENTURE  -  REMASTERED", style = "text", text_color = col(0.85, 1.0, 0.7), font_scale = 1.4 * k, align_h = "center", no_input = true })
        quad("menu", "card", sw / 2 - S(300), S(296), S(600), S(226), { style = "panel", fill = col(0.02, 0.06, 0.02, 0.72), border = col(0.9, 0.75, 0.3, 0.8), corner_radius = S(18), no_input = true,
            title = "HOW TO PLAY", text_color = col(1, 0.85, 0.4), font_scale = 1.2 * k, align_h = "center",
            body = "ARROWS / WASD  run, climb ladders\nSPACE  jump (hold for higher), grab vines\nDOWN  drop from vine   SPACE  leap off it\nP pause   TAB settings & volume   M mute\nFind all " .. TOTAL_TREASURES .. " treasures in 20 minutes." })
        quad("menu", "start", 0, 0, 1, 1, { visible = false, no_input = true })  -- replaced by clickable buttons below
        quad("menu", "credit", sw / 2 - S(400), sh - S(52), S(800), S(32), { title = "A tribute to David Crane's 1982 Activision classic", style = "text", text_color = col(0.8, 0.9, 0.7, 0.6), font_scale = 1.1 * k, align_h = "center", no_input = true })
    else
        local title = kind == "pause" and "PAUSED" or (kind == "win" and "ALL TREASURES FOUND!" or (G.time <= 0 and "TIME'S UP" or "GAME OVER"))
        local body = kind == "pause" and "ENTER / P  resume\nTAB  settings\nESC  quit to title" or
            string.format("Final score  %d\nTreasures  %d / %d\nTime left  %s\nPress ENTER to play again", math.max(0, math.floor(G.score)), G.found, TOTAL_TREASURES, fmt_time(G.time))
        quad("menu", "logo_shadow", sw / 2 - S(415), S(175), S(840), S(110), { title = title, style = "text", text_color = col(0.1, 0.03, 0, 0.8), font_scale = 4.0 * k, align_h = "center", no_input = true })
        quad("menu", "logo", sw / 2 - S(420), S(170), S(840), S(110), { title = title, style = "text", text_color = kind == "over" and col(1, 0.4, 0.25) or col(1, 0.8, 0.25), font_scale = 4.0 * k, align_h = "center", no_input = true })
        quad("menu", "card", sw / 2 - S(260), S(300), S(520), S(200), { style = "panel", fill = col(0.02, 0.06, 0.02, 0.75), border = col(0.9, 0.75, 0.3, 0.8), corner_radius = S(18), no_input = true, body = body, text_color = col(0.95, 1, 0.85), font_scale = 1.3 * k, align_h = "center" })
        for _, id in ipairs({ "sub", "start", "credit" }) do quad("menu", id, 0, 0, 1, 1, { visible = false, no_input = true }) end
    end
    -- clickable buttons (mouse); keyboard keys still work. G.mclick = id of the clicked button this frame.
    local btns
    if kind == "title" then btns = { { "start", "START  (ENTER)" }, { "jev", "JEV" }, { "settings", "SETTINGS  (TAB)" } }
    elseif kind == "pause" then btns = { { "resume", "RESUME  (P)" }, { "settings", "SETTINGS  (TAB)" }, { "quit", "QUIT  (ESC)" } }
    else btns = { { "again", "PLAY AGAIN" }, { "settings", "SETTINGS  (TAB)" } } end
    local bw, gap = S(230), S(16)
    local x0 = sw / 2 - (#btns * bw + (#btns - 1) * gap) / 2
    local by = kind == "title" and S(548) or S(516)
    G.mclick = nil
    for i = 1, 3 do
        local b = btns[i]
        local id = "btn" .. i
        if b then
            quad("menu", id, x0 + (i - 1) * (bw + gap), by, bw, S(54), { title = b[2], label = b[2], style = "text",
                fill = col(0.06, 0.12, 0.03, 0.85), border = col(0.95, 0.8, 0.3, 0.9), corner_radius = S(14),
                text_color = col(1, 0.95, 0.75), font_scale = 1.35 * k, align_h = "center", align_v = "center", visible = true, z = 20 })
            local ok, st = pcall(runtime_ui.get_state, "menu", id)
            if ok and st and st.clicked then G.mclick = b[1] end
        else
            quad("menu", id, 0, 0, 1, 1, { visible = false })
        end
    end
end

local R
local logs = {}
local TREE_SETS = { [0] = { 2.5, 8.5, 15.5, 21.5 }, { 1.5, 6.0, 18.0, 22.5 }, { 3.5, 10.0, 14.0, 20.5 }, { 1.0, 7.5, 16.5, 23.0 } }

local function layout_crust(holes)
    local segs, x0 = {}, -0.5
    for _, h in ipairs(holes) do segs[#segs + 1] = { x0, h - 1.0 }; x0 = h + 1.0 end
    segs[#segs + 1] = { x0, W + 0.5 }
    for i = 1, 4 do
        local s = segs[i]
        if s then
            local cx, w = (s[1] + s[2]) / 2, s[2] - s[1]
            WORLD.grass[i]:set_position(vec3(cx, -0.2 + i * TZ_STEP * 0.5, WORLD.gz[i])); WORLD.grass[i]:set_scale(vec3(w, 0.4, 7.2))
            WORLD.dirt[i]:set_position(vec3(cx, -0.95, WORLD.dz[i])); WORLD.dirt[i]:set_scale(vec3(w, 1.1, 7.2))
        end
        show(WORLD.grass[i], s ~= nil); show(WORLD.dirt[i], s ~= nil)
    end
    for i = 1, 3 do
        show(OBJ.shafts[i], holes[i] ~= nil)
        if holes[i] then OBJ.shafts[i]:set_position(vec3(holes[i], -0.8, -5.9)) end
    end
end

local function setup_room(i)
    G.screen = i % 255
    R = room(G.screen)
    layout_crust(R.holes)
    local ts = TREE_SETS[R.trees]
    for k, t in ipairs(WORLD.trees) do
        local z = -4.6 - (k % 2) * 0.8
        t.trunk:set_position(vec3(ts[k], -0.1, z))
        t.crown:set_position(vec3(ts[k] + 0.4, 8.2 + (k % 2) * 0.4, z))
    end
    local pit = R.pit
    show(OBJ.pit, pit ~= nil); show(OBJ.pit_rim, pit ~= nil)
    for _, lp in ipairs(OBJ.lily) do show(lp, pit == "swamp") end
    local ps = pscale()
    if pit then
        local c, rough, file, metal, em = vec3(0.03, 0.025, 0.02), 0.04, "tar.png", 0.6, vec3(0.02, 0.012, 0.005)
        if pit == "swamp" then c, file, rough, metal, em = vec3(0.18, 0.4, 0.25), "water.png", 0.03, 0.35, vec3(0.03, 0.12, 0.07)
        elseif pit == "croc" then c, file, rough, metal, em = vec3(0.2, 0.55, 0.62), "water.png", 0.02, 0.4, vec3(0.03, 0.16, 0.2)
        elseif pit == "quicksand" then c, file, rough, metal, em = vec3(0.75, 0.6, 0.35), "dirt.png", 0.9, 0.0, vec3(0, 0, 0) end
        material.set(OBJ.pit, "base_color", c); material.set(OBJ.pit, "roughness", rough)
        material.set(OBJ.pit, "metallic", metal); material.set(OBJ.pit, "emissive", em)
        tex(OBJ.pit, "base_color", file)
    end
    local wet = (pit == "swamp" or pit == "croc")
    local tarry = (pit == "tar" or pit == "shift_tar")
    particles.set_emitter(OBJ.pit_bubbles, "spawn_rate", ps * (tarry and 12.0 or (pit == "swamp" and 5.0 or 0.0)))
    particles.set_emitter(OBJ.ripples, "spawn_rate", ps * (wet and 16.0 or 0.0))
    particles.set_emitter(OBJ.pit_mist, "spawn_rate", ps * (wet and 5.0 or 0.0))
    for _, c in ipairs(OBJ.crocs) do show(c.root, pit == "croc") end
    show(OBJ.ladder, R.ladder)
    show(OBJ.vine, R.vine)
    if not R.vine then hide_light(OBJ.vine_light) end
    logs = {}
    for k, l in ipairs(OBJ.logs) do
        local d = R.logs[k]
        show(l.root, d ~= nil)
        if d then logs[#logs + 1] = { node = l.root, spin = l.spin, x = d[1], roll = d[2], ang = 0, touching = false } end
    end
    show(OBJ.fire, R.fire)
    OBJ.fire:set_position(vec3(19.5, 0, 0))
    particles.set_emitter(OBJ.fire_emitter, "position", vec3(19.5, 0.4, 0))
    particles.set_emitter(OBJ.fire_emitter, "spawn_rate", R.fire and 80.0 * ps or 0.0)
    particles.set_emitter(OBJ.smoke_emitter, "position", vec3(19.5, 1.2, 0))
    particles.set_emitter(OBJ.smoke_emitter, "spawn_rate", R.fire and 6.0 * ps or 0.0)
    if not R.fire then hide_light(OBJ.fire_light) end
    show(OBJ.cobra, R.cobra)
    OBJ.cobra:set_position(vec3(19.5, 0, 0))
    local tr = R.treasure
    local have = tr ~= nil and not G.collected[G.screen]
    show(OBJ.tre_root, have)
    for k = 0, 3 do show(OBJ.tre[k], have and k == tr) end
    particles.set_emitter(OBJ.tre_emitter, "spawn_rate", have and 20.0 * ps or 0.0)
    particles.set_emitter(OBJ.tre_emitter, "position", vec3(20.0, 0.6, 0))
    if have then
        local lc = ({ [0] = vec3(0.6, 1.0, 0.5), vec3(0.8, 0.85, 1.0), vec3(1.0, 0.75, 0.3), vec3(0.7, 0.85, 1.0) })[tr]
        set_light(OBJ.tre_light, vec3(20.0, 1.4, 1.2), lc, 12.0, 6.0)
    else hide_light(OBJ.tre_light) end
    show(OBJ.wall, R.wall ~= nil)
    if R.wall then OBJ.wall:set_position(vec3(R.wall, (UG + CEIL) / 2, -0.4)) end
    show(OBJ.scorp, R.scorpion)
    G.scorp_x = ((G.px or 2) < 12) and 19.0 or 5.0
end

local P = { x = 2.5, y = 0, vx = 0, vy = 0, mode = "ground", face = 1, coyote = 0, buffer = 0, inv = 0, stumble = 0, regrab = 0, run_phase = 0 }
local function respawn()
    P.mode, P.x, P.y, P.vx, P.vy = "air", 2.5, 6.5, 0, 0
    P.face, P.inv, P.coyote, P.buffer = 1, 1.5, 0, 0
    G.under, G.px = false, P.x
end
local function new_game()
    G.score, G.lives, G.time, G.found = 2000, 3, 20 * 60, 0
    score_shown, G.collected, G.px = 2000, {}, 2.5
    setup_room(0)
    respawn()
    G.state = "play"
    runtime_ui.hide("menu"); runtime_ui.show("hud")
    show_toast("FIND THE LOST TREASURES!")
    sfx("select")
end
local function burst(o)
    o.gravity = o.gravity or vec3(0, -6, 0)
    o.count = math.max(1, math.floor(o.count * pscale()))
    particles.emit_burst(o)
end
local function puff(x, y, n, c, up, spread)
    burst({ position = vec3(x, y, 0.05), velocity = vec3(0, up or 1.5, 0), count = n, color_start = c or vec4(0.6, 0.5, 0.35, 0.9),
        color_end = vec4(0.45, 0.38, 0.28, 0), size_min = 0.06, size_max = 0.2, life_min = 0.35, life_max = 0.85,
        spawn_radius = spread or 0.35, gravity = vec3(0, -2.5, 0), drag = 1.2, noise_strength = 0.6 })
end
local function shake(v) cam_shake = math.max(cam_shake, v * shscale()) end

local function die(cause)
    if G.state ~= "play" then return end
    G.state, G.die_t, G.die_cause, P.mode = "dying", 0, cause, "dead"
    sfx("death"); shake(0.5)
    if cause == "tar" or cause == "swamp" or cause == "croc" or cause == "quicksand" or cause == "water" then
        sfx("splash")
        local wet = cause ~= "tar" and cause ~= "quicksand"
        burst({ position = vec3(P.x, 0.1, 0), velocity = vec3(0, 4.5, 0), count = 90, color_start = wet and vec4(0.7, 0.95, 1.0, 1) or vec4(0.15, 0.12, 0.1, 1),
            color_end = wet and vec4(0.3, 0.6, 0.8, 0) or vec4(0.05, 0.05, 0.05, 0), size_min = 0.05, size_max = 0.16, life_min = 0.5, life_max = 1.1, spawn_radius = 0.6, gravity = vec3(0, -10, 0) })
        burst({ position = vec3(P.x, 0.05, 0), velocity = vec3(0, 0.3, 0), count = 40, color_start = vec4(0.9, 1, 1, 0.8), color_end = vec4(0.5, 0.8, 1, 0),
            size_min = 0.1, size_max = 0.3, life_min = 0.6, life_max = 1.2, spawn_radius = 1.0, gravity = vec3(0, 0, 0), drag = 2 })
        flash(0.1, 0.0, 0.0, 0.35)
    else
        burst({ position = vec3(P.x, P.y + 1.0, 0.2), velocity = vec3(0, 3, 0), count = 80, color_start = vec4(1, 0.35, 0.2, 1),
            color_end = vec4(0.4, 0.0, 0.0, 0), size_min = 0.05, size_max = 0.14, life_min = 0.4, life_max = 1.0, spawn_radius = 0.4 })
        burst({ position = vec3(P.x, P.y + 1.0, 0.2), velocity = vec3(0, 1, 0), count = 40, color_start = vec4(1, 0.9, 0.6, 1),
            color_end = vec4(1, 0.4, 0.1, 0), size_min = 0.02, size_max = 0.05, life_min = 0.2, life_max = 0.5, spawn_radius = 0.3, noise_strength = 4 })
        flash(1.0, 0.15, 0.1, 0.45)
    end
end

G.flashlight_t = 0
local function collect_treasure()
    local v = TREASURE_VALUES[R.treasure]
    G.score, G.found = G.score + v, G.found + 1
    G.collected[G.screen] = true
    show(OBJ.tre_root, false)
    particles.set_emitter(OBJ.tre_emitter, "spawn_rate", 0.0)
    burst({ position = vec3(20, 0.8, 0), velocity = vec3(0, 4, 0), count = 140, color_start = vec4(1, 0.9, 0.4, 1), color_end = vec4(1, 0.5, 0.1, 0),
        size_min = 0.05, size_max = 0.14, life_min = 0.6, life_max = 1.4, spawn_radius = 0.5, gravity = vec3(0, -4, 0) })
    burst({ position = vec3(20, 1.0, 0), velocity = vec3(0, 1.0, 0), count = 90, color_start = vec4(1, 1, 0.85, 1), color_end = vec4(1, 0.7, 0.2, 0),
        size_min = 0.1, size_max = 0.28, life_min = 0.3, life_max = 0.7, spawn_radius = 1.6, gravity = vec3(0, 0, 0), drag = 2.0 })
    burst({ position = vec3(20, 0.5, 0), velocity = vec3(0, 7.5, 0), count = 70, color_start = vec4(1, 0.95, 0.6, 1), color_end = vec4(1, 0.4, 0.1, 0),
        size_min = 0.03, size_max = 0.07, life_min = 1.0, life_max = 2.0, spawn_radius = 0.3, noise_strength = 1.5 })
    G.flashlight_t = 1.0
    sfx("treasure"); flash(1.0, 0.9, 0.5, 0.35)
    show_toast(string.format("%s  +%d", TREASURE_NAMES[R.treasure], v))
    if G.found >= TOTAL_TREASURES then G.state = "win" end
end

local function over_hole(x)
    for _, h in ipairs(R.holes) do if math.abs(x - h) < 0.85 then return h end end
end
local function croc_under(x)
    if R.pit ~= "croc" then return nil end
    -- feet (not just the centre) decide support, so Harry can't drop through the narrow seams between crocs
    local f = PHW * 0.7
    for _, cx in ipairs(CROC_X) do if x + f >= cx + CROC_L and x - f <= cx + CROC_R then return cx end end
end
local function ground_at(x) return croc_under(x) and CROC_Y or 0.0 end
local function pit_halfwidth()
    if not R.pit then return 0 end
    if R.pit == "shift_tar" or R.pit == "quicksand" then
        local c = 0.5 + 0.5 * math.sin(G.t * (2 * math.pi / 7.0))
        return PIT_HW * clamp(c * 1.25, 0, 1)
    end
    return PIT_HW
end
local function vine_state(t)
    t = t or G.t
    local w = 2 * math.pi / VINE_PERIOD
    local a = VINE_AMP * math.sin(t * w)
    local av = VINE_AMP * w * math.cos(t * w)
    return a, VINE_PIVOT.x + math.sin(a) * VINE_LEN, VINE_PIVOT.y - math.cos(a) * VINE_LEN, math.cos(a) * VINE_LEN * av, math.sin(a) * VINE_LEN * av
end
local function croc_open_amount()
    local p = G.t % 4.0
    if p < 2.0 then return 0 end
    return clamp(math.min((p - 2.0) / 0.25, (4.0 - p) / 0.25), 0, 1)
end

local function land(floor)
    local impact = -P.vy
    P.y, P.vy, P.mode = floor, 0, "ground"
    if floor == CROC_Y then P.vx = P.vx * 0.35 end  -- sticky croc backs: easier to chain hops
    local fell = P.from_surface; P.from_surface = false
    if floor == UG and fell then
        G.score = G.score - 100
        show_toast("FELL INTO THE TUNNEL  -100")
        sfx("thud"); shake(0.25)
    else sfx("step") end
    H.squash = clamp(impact / 14, 0.1, 0.35)
    puff(P.x, floor + 0.03, math.floor(10 + impact * 2), nil, 1.0 + impact * 0.08, 0.35)
end
local function start_jump(v)
    P.mode, P.vy, P.buffer, P.coyote = "air", v, 0, 0
    sfx("jump"); puff(P.x, P.y + 0.05, 22, nil, 1.3, 0.3)
    H.squash = -0.18
end

local function step_player(dt, inp)
    P.inv = math.max(0, P.inv - dt); P.stumble = math.max(0, P.stumble - dt)
    P.regrab = math.max(0, P.regrab - dt); P.buffer = math.max(0, P.buffer - dt)
    P.coyote = math.max(0, P.coyote - dt)
    if inp.jump_pressed then P.buffer = BUFFER; inp.jump_pressed = false end
    local dir = (inp.right and 1 or 0) - (inp.left and 1 or 0)
    if P.mode == "ground" or P.mode == "air" then
        local target = dir * (P.stumble > 0 and MAX_RUN * 0.4 or MAX_RUN)
        local acc = ACCEL_AIR
        if P.mode == "ground" then acc = (dir ~= 0 and P.vx * dir >= 0) and ACCEL_GROUND or DECEL_GROUND end
        P.vx = approach(P.vx, target, acc * dt)
        if dir ~= 0 then P.face = dir end
        local nx = P.x + P.vx * dt
        if G.under and R.wall and math.abs(nx - R.wall) < 0.5 + PHW then nx = P.x; P.vx = 0 end
        P.x = nx
    end
    if P.mode == "ground" then
        P.coyote = COYOTE
        if not G.under then P.y = ground_at(P.x) end
        if math.abs(P.vx) > 0.3 then
            P.run_phase = P.run_phase + math.abs(P.vx) * dt * 1.6
            P.step_t = (P.step_t or 0) + math.abs(P.vx) * dt
            if P.step_t > 1.25 then
                P.step_t = 0; sfx("step")
                puff(P.x - P.face * 0.2, P.y + 0.03, 7, vec4(0.55, 0.47, 0.35, 0.6), 0.6, 0.12)
            end
        end
        if R.ladder and math.abs(P.x - 12) < 1.0 and ((G.under and inp.up) or ((not G.under) and inp.down)) then
            P.mode, P.x, P.vx = "climb", 12, 0
        elseif not G.under and over_hole(P.x) then
            P.mode, P.vy, P.vx = "air", 0, P.vx * 0.3   -- coyote stays armed for a late jump
        elseif P.buffer > 0 then
            start_jump(JUMP_V)
        end
    elseif P.mode == "air" then
        if P.buffer > 0 and P.coyote > 0 then start_jump(JUMP_V) end
        local g = P.vy > 0 and GRAV_UP or GRAV_DOWN
        if math.abs(P.vy) < 1.6 then g = GRAV_APEX end
        if P.vy > 0 and not inp.jump_held then g = g * JUMP_CUT end
        P.vy = math.max(P.vy - g * dt, -22)
        local ny = P.y + P.vy * dt
        if G.under and ny + 1.9 > CEIL and P.y < CEIL then ny = CEIL - 1.9; P.vy = math.min(P.vy, 0) end
        local floor = (P.y >= -0.05 and not over_hole(P.x)) and ground_at(P.x) or UG
        if ny <= floor and P.vy <= 0 then land(floor)
        else
            P.y = ny
            if P.y < -0.6 and not G.under then G.under = true; P.from_surface = true end
        end
        if R.vine and P.regrab <= 0 and not G.under and P.mode == "air" then
            local _, tx, ty = vine_state()
            local dx, dy = tx - P.x, ty - (P.y + HAND)
            if dx * dx + dy * dy < VINE_CATCH * VINE_CATCH then
                P.mode, P.catch_t, P.catch_from = "catch", 0, { x = P.x, y = P.y }
                sfx("yell")
                burst({ position = vec3(tx, ty, 0.2), velocity = vec3(0, 0.5, 0), count = 30, color_start = vec4(0.8, 1, 0.5, 1),
                    color_end = vec4(0.4, 0.8, 0.2, 0), size_min = 0.04, size_max = 0.1, life_min = 0.3, life_max = 0.7, spawn_radius = 0.3, gravity = vec3(0, -1, 0) })
            end
        end
    elseif P.mode == "catch" then
        P.catch_t = P.catch_t + dt
        local f = clamp(P.catch_t / 0.16, 0, 1)
        f = f * f * (3 - 2 * f)
        local _, tx, ty, tvx = vine_state()
        P.x, P.y = lerp(P.catch_from.x, tx, f), lerp(P.catch_from.y, ty - HAND, f)
        P.face = tvx >= 0 and 1 or -1
        if f >= 1 then P.mode = "vine" end
    elseif P.mode == "vine" then
        local _, tx, ty, tvx, tvy = vine_state()
        P.x, P.y = tx, ty - HAND
        P.face = tvx >= 0 and 1 or -1
        if inp.down then
            P.mode, P.vx, P.vy, P.regrab = "air", tvx * 0.85, math.max(0, tvy * 0.6), 0.6
        elseif P.buffer > 0 then
            P.mode, P.vx, P.vy, P.regrab, P.buffer = "air", tvx * 0.9 + P.face * 1.5, 6.5, 0.6, 0
            sfx("jump")
        end
    elseif P.mode == "climb" then
        P.vx = 0
        if inp.up then P.y = P.y + CLIMB * dt elseif inp.down then P.y = P.y - CLIMB * dt end
        P.y = clamp(P.y, UG, 0.0)
        G.under = P.y < -0.01
        if P.y >= 0.0 and (inp.left or inp.right) then
            P.x = 12 + (inp.left and -1.45 or 1.45); P.face = inp.left and -1 or 1; P.mode = "ground"; G.under = false
        elseif P.y <= UG and (inp.left or inp.right) then
            P.mode, G.under = "ground", true
        end
        if inp.up or inp.down then
            P.step_t = (P.step_t or 0) + dt
            if P.step_t > 0.25 then P.step_t = 0; sfx("step") end
        end
    end
    if P.x < 0 or P.x > W then
        local d = P.x < 0 and -1 or 1
        P.x = P.x - d * W
        G.px = P.x
        if P.mode == "vine" or P.mode == "catch" then P.mode = "air" end
        setup_room(G.screen + 255 + d * (G.under and 3 or 1))
        cam_kick, cam_x = d * 3.0, cam_x - d * W
    end
    G.px = P.x
    if P.inv > 0 then return end
    if not G.under and P.mode == "ground" and R.pit then
        local hw, dx = pit_halfwidth(), math.abs(P.x - PIT_C)
        if R.pit == "croc" then
            if dx < hw - 0.35 then
                local on = croc_under(P.x)
                if not on then die("water")
                elseif croc_open_amount() > 0.5 and P.x < on + CROC_MOUTH_R then die("croc") end   -- closed mouth = safe
            end
        elseif dx < hw - 0.5 then die(R.pit) end
    end
    if not G.under and P.mode ~= "vine" and P.mode ~= "catch" then
        for _, l in ipairs(logs) do
            local hit = math.abs(P.x - l.x) < 0.55 and P.y < 0.55
            if hit and not l.touching then
                G.score = G.score - 100
                P.stumble, P.vx = 0.45, P.vx * 0.3
                sfx("thud"); shake(0.2)
                show_toast("OUCH!  -100"); flash(0.8, 0.4, 0.1, 0.18)
                burst({ position = vec3(l.x, 0.6, 0.4), velocity = vec3(0, 3.5, 0), count = 45, color_start = vec4(0.75, 0.5, 0.25, 1),
                    color_end = vec4(0.4, 0.25, 0.1, 0), size_min = 0.05, size_max = 0.13, life_min = 0.4, life_max = 0.9, spawn_radius = 0.3, gravity = vec3(0, -12, 0) })
                burst({ position = vec3((P.x + l.x) / 2, 0.8, 0.4), velocity = vec3(0, 1.5, 0), count = 35, color_start = vec4(1, 0.9, 0.5, 1),
                    color_end = vec4(1, 0.3, 0.0, 0), size_min = 0.02, size_max = 0.05, life_min = 0.15, life_max = 0.4, spawn_radius = 0.2, gravity = vec3(0, -4, 0), noise_strength = 4 })
            elseif hit then G.score = G.score - dt * 30 end
            l.touching = hit
        end
        if (R.fire or R.cobra) and math.abs(P.x - 19.5) < 0.5 and P.y < 0.8 then die(R.fire and "fire" or "cobra") end
        if R.treasure and not G.collected[G.screen] and math.abs(P.x - 20.0) < 1.0 and P.y < 1.4 then collect_treasure() end
    elseif G.under and R.scorpion and math.abs(P.x - G.scorp_x) < 0.55 and P.y < UG + 0.45 then
        die("scorpion")
    end
end

local function step_world(dt)
    for _, l in ipairs(logs) do
        if l.roll then
            l.x = l.x - 3.0 * dt
            if l.x < -0.8 then l.x = l.x + W + 1.6 end
            l.ang = l.ang + 3.0 * dt / 0.45 * 57.3
        end
    end
    if R.scorpion and G.under and G.state == "play" then
        local d = G.px - G.scorp_x
        if math.abs(d) > 0.05 then G.scorp_x = G.scorp_x + (d > 0 and 1 or -1) * 1.5 * dt end
    end
end

local function present_world(dt)
    for _, l in ipairs(logs) do
        local bob = l.roll and math.abs(math.sin(l.ang / 57.3 * 2)) * 0.04 or 0
        l.node:set_position(vec3(l.x, 0.45 + bob, 0))
        l.node:set_rotation(vec3(0, 18, 0))
        l.spin:set_rotation(vec3(0, 0, l.ang))
        if l.roll and math.random() < dt * 6 then puff(l.x + 0.3, 0.05, 3, vec4(0.5, 0.42, 0.3, 0.5), 0.4, 0.15) end
    end
    if R.pit then
        local hw = math.max(0.001, pit_halfwidth())
        OBJ.pit:set_scale(vec3(hw, 0.03, 1.15))
        OBJ.pit_rim:set_scale(vec3(hw + 0.3, 0.03, 1.35))
        show(OBJ.pit, hw > 0.05); show(OBJ.pit_rim, hw > 0.05)
        particles.set_emitter(OBJ.ripples, "spawn_radius", math.max(0.2, hw * 0.65))
    end
    if R.vine then
        local a, tx, ty = vine_state()
        OBJ.vine:set_rotation(vec3(0, 0, math.deg(a)))
        local near = 0
        if P.mode == "air" and not G.under then
            local d = math.sqrt((tx - P.x) ^ 2 + (ty - P.y - HAND) ^ 2)
            near = clamp(1 - (d - VINE_CATCH) / 2.5, 0, 1)
        end
        local glow = 0.4 + near * 3.0 * (0.7 + 0.3 * math.sin(G.t * 18))
        material.set(OBJ.vine_tip, "emissive", vec3(0.6 * glow, 1.2 * glow, 0.3 * glow))
        set_light(OBJ.vine_light, vec3(tx, ty, 0.6), vec3(0.7, 1.0, 0.4), 1.5 + near * 8, 3.5)
    end
    if R.pit == "croc" then
        local open = croc_open_amount()
        for k, c in ipairs(OBJ.crocs) do
            local prev = c.jaw_a
            c.jaw_a = damp(c.jaw_a, -38 * open, 18, dt)
            c.jaw:set_rotation(vec3(0, 0, c.jaw_a))
            c.root:set_position(vec3(CROC_X[k] + 0.15, 0.06 + 0.025 * math.sin(G.t * 2 + k), 0.3))
            c.root:set_rotation(vec3(0, 3 * math.sin(G.t * 0.7 + k), 0))
            if prev < -25 and c.jaw_a >= -25 then
                burst({ position = vec3(CROC_X[k] - 0.6, 0.1, 0.2), velocity = vec3(0, 2.2, 0), count = 26, color_start = vec4(0.7, 0.95, 1, 1),
                    color_end = vec4(0.4, 0.7, 0.9, 0), size_min = 0.03, size_max = 0.08, life_min = 0.3, life_max = 0.7, spawn_radius = 0.3, gravity = vec3(0, -9, 0) })
            end
        end
    end
    if R.fire then
        local fl = 0.75 + 0.25 * math.sin(G.t * 23) * math.sin(G.t * 7.3)
        set_light(OBJ.fire_light, vec3(19.5, 1.0, 0.8), vec3(1.0, 0.55, 0.15), 12 * fl, 6.5)
        for i, f in ipairs(OBJ.flames) do
            local s = 0.8 + 0.3 * math.sin(G.t * (9 + i * 3) + i)
            f:set_scale(vec3(0.2 * s, 0.5 * s + 0.1, 0.2 * s))
        end
    end
    if R.cobra then OBJ.cobra_neck:set_rotation(vec3(0, 0, 8 * math.sin(G.t * 2.2))) end
    if G.flashlight_t > 0 then
        G.flashlight_t = math.max(0, G.flashlight_t - dt * 1.5)
        set_light(OBJ.tre_light, vec3(20.0, 1.5, 1.5), vec3(1.0, 0.85, 0.45), 40 * G.flashlight_t, 10.0)
    end
    if R.treasure and not G.collected[G.screen] then
        OBJ.tre_root:set_position(vec3(20.0, 0.15 + 0.12 * math.sin(G.t * 2.5), 0))
        OBJ.tre_root:set_rotation(vec3(0, (G.t * 60) % 360, 0))
    end
    if R.scorpion then
        OBJ.scorp:set_position(vec3(G.scorp_x, UG + 0.02 * math.abs(math.sin(G.t * 12)), 0))
        OBJ.scorp:set_rotation(vec3(0, (G.px < G.scorp_x) and 0 or 180, 0))
    end
    for _, tl in ipairs(WORLD.torch_lights) do
        set_light(tl.idx, vec3(tl.x, -3.0, -0.9), vec3(1.0, 0.6, 0.28), 16 * (0.8 + 0.2 * math.sin(G.t * 17 + tl.x)), 8.0)
    end
    for i, f in ipairs(WORLD.flies) do
        local t = G.t * 0.35 + f.ph
        local p = vec3(12 + 10 * math.sin(t * 1.3), 1.6 + 0.9 * math.sin(t * 2.1), -0.6 + 0.8 * math.sin(t * 1.7))
        f.node:set_position(p)
        set_light(f.light, p, vec3(0.75, 1.0, 0.35), 2.5 + 1.5 * math.sin(G.t * 6 + i), 3.0)
    end
end

local function animate_harry(dt)
    local yaw = P.face > 0 and 0 or 180
    H.cur_yaw = damp(H.cur_yaw or yaw, yaw, 16, dt)
    local runf = clamp(math.abs(P.vx) / MAX_RUN, 0, 1)
    local ph = P.run_phase * math.pi
    local hipL, hipR, kneeL, kneeR, shL, shR, elL, elR = 0, 0, 0, 0, 0, 0, -10, -10
    local bob, lean, m = 0, 0, P.mode
    if m == "ground" then
        local s = math.sin(ph)
        hipL, hipR = 40 * s * runf, -40 * s * runf
        kneeL = -(60 * math.max(0, -math.cos(ph)) + 8) * runf
        kneeR = -(60 * math.max(0, math.cos(ph)) + 8) * runf
        shL, shR = -38 * s * runf, 38 * s * runf
        elL, elR = -(35 + 25 * runf), -(35 + 25 * runf)
        bob, lean = math.abs(math.cos(ph)) * 0.06 * runf, -10 * runf
        if runf < 0.05 then
            local br = math.sin(G.t * 2.2)
            shL, shR, bob = 4 + 2 * br, -4 - 2 * br, 0.008 * br
        end
    elseif m == "air" then
        local up = clamp(P.vy / JUMP_V, -1, 1)
        hipL, hipR, kneeL, kneeR = 35, -15, -70 + 20 * up, -40
        shL, shR = 140 * clamp(up, 0, 1) + 40, -50 + 90 * clamp(-up, 0, 1)
        elL, elR = -20, -40
        lean = -6 * (P.vx * P.face) / MAX_RUN
    elseif m == "vine" or m == "catch" then
        local _, _, _, tvx = vine_state()
        local lag = clamp(tvx / 6, -1, 1) * P.face
        shL, shR, elL, elR = 175, 168, -8, -14
        hipL, hipR, kneeL, kneeR = -15 * lag + 15, -15 * lag - 5, -25, -45
        lean = 8 * lag
    elseif m == "climb" then
        H.cur_yaw = 90
        local c = math.sin(P.y * 3.5)
        shL, shR, elL, elR = 150 + 20 * c, 150 - 20 * c, -40, -40
        hipL, hipR = 30 * math.max(0, c), 30 * math.max(0, -c)
        kneeL, kneeR = -60 * math.max(0, c), -60 * math.max(0, -c)
    end
    local y, roll = P.y, 0
    if m == "dead" then
        local c = G.die_cause
        if c == "tar" or c == "swamp" or c == "quicksand" or c == "water" or c == "croc" then
            y = P.y - math.min(2.4, G.die_t * 1.3); shL, shR = 170, 160
        else roll = math.min(90, G.die_t * 320); shL, shR = 120, 100 end
    end
    H.squash = damp(H.squash or 0, 0, 10, dt)
    local sq = H.squash
    H.root:set_position(vec3(P.x, y + bob, 0.0))
    H.root:set_scale(vec3(1.12 * (1 + sq * 0.6), 1.12 * (1 - sq), 1.12 * (1 + sq * 0.6)))
    H.yaw:set_rotation(vec3(0, H.cur_yaw, 0))
    H.lean = damp(H.lean or 0, lean, 12, dt)
    H.pelvis:set_rotation(vec3(0, 0, -roll))
    H.spine:set_rotation(vec3(0, 0, H.lean))
    H.head:set_rotation(vec3(0, 0, -H.lean * 0.6))
    H.hipL:set_rotation(vec3(0, 0, hipL)); H.hipR:set_rotation(vec3(0, 0, hipR))
    H.kneeL:set_rotation(vec3(0, 0, kneeL)); H.kneeR:set_rotation(vec3(0, 0, kneeR))
    H.shL:set_rotation(vec3(0, 0, shL)); H.shR:set_rotation(vec3(0, 0, shR))
    H.elL:set_rotation(vec3(0, 0, -elL)); H.elR:set_rotation(vec3(0, 0, -elR))
    show(H.root, not (P.inv > 0 and math.floor(G.t * 12) % 2 == 0))
end

local function update_camera(dt)
    cam_kick = cam_kick * math.exp(-6 * dt)
    cam_shake = math.max(0, cam_shake - dt)
    local sx = cam_shake > 0 and (math.random() - 0.5) * cam_shake * 0.6 or 0
    local sy = cam_shake > 0 and (math.random() - 0.5) * cam_shake * 0.6 or 0
    cam_x = damp(cam_x, 12 + (P.x - 12) * 0.22, 4, dt)
    local depth = G.under and -0.7 or 0
    cam:set_position(vec3(cam_x - cam_kick + sx, CAM_POS.y + depth + sy + 0.08 * math.sin(G.t * 0.7), CAM_POS.z))
    cam:look_at(vec3(cam_x + (P.x - 12) * 0.08 - cam_kick * 0.6, depth * 1.4, 0))
    local off = cam_x - 12
    WORLD.mid:set_position(vec3(off * 0.25, 0, 0))
    WORLD.far:set_position(vec3(off * 0.55, 0, 0))
end

local function load_settings()
    local src = fs and fs.read and fs.read("Scripts/Lib/settings_menu.lua")
    if not src then return nil end
    local chunk = load(src, "@settings_menu.lua")
    if not chunk then return nil end
    local ok, SM = pcall(chunk)
    if not ok or not SM or not SM.new then return nil end
    local ok2, s = pcall(SM.new, { title = "SETTINGS", file = "Save/settings.cfg", music = true,
        click = function() sfx("select") end, defaults = { master = 0.5, music = 0.5 },
        theme = { accent = { 1.0, 0.8, 0.3, 1 }, accent2 = { 0.5, 1.0, 0.4, 1 } },
        on_change = function() apply_particle_quality() end })
    return ok2 and s or nil
end

local inp = { jump_pressed = false }
local acc, title_t = 0, 0
local pulse_space = false
local function gather_input()
    if pulse_space then
        keys_prev.Space = false
    end
    inp.left, inp.right = anydown("Left", "A"), anydown("Right", "D")
    inp.up, inp.down = anydown("Up", "W"), anydown("Down", "S")
    inp.jump_held = down("Space")
    if pressed("Space") then inp.jump_pressed = true end
end

local function init()
    pe_log("[Pitfall] init")
    setup_render()
    find_templates()
    setup_materials()
    build_static()
    build_dynamic()
    build_harry()
    G.score, G.lives, G.time, G.found, G.collected, G.px = 2000, 3, 1200, 0, {}, 2.5
    runtime_ui.show("hud"); runtime_ui.set_screen_overlay("hud", true); runtime_ui.hide("hud")
    pcall(audio.set_master_volume, 0.5)
    pcall(audio.play_music, "jungle.wav")
    SET = load_settings()
    if SET then SET:apply() end
    apply_particle_quality()
    setup_room(0)
    G.state = "title"
    local n = 0
    for _ in pairs(TPL) do n = n + 1 end
    pe_log("[Pitfall] ready: " .. TOTAL_TREASURES .. " treasures, " .. n .. " cooked mesh templates, settings " .. (SET and "loaded" or "absent"))
end

local jev
local pulse_down = false
local hop = false
local hop_saw_air = false
local hop_wait = 0
local raw_prev = {}
local raw_primed = false
local hazard_best = { dist = 1e9, side = "none" }

local function clear_hold()
    G.vkeys.Left = nil
    G.vkeys.Right = nil
    G.vkeys.Space = nil
    G.vkeys.Down = nil
    pulse_space = false
    pulse_down = false
    hop = false
    hop_saw_air = false
    hop_wait = 0
end

local function release_pulses()
    if pulse_space then
        G.vkeys.Space = nil
        pulse_space = false
    end
    if pulse_down then
        G.vkeys.Down = nil
        pulse_down = false
    end
end

local function settle_hop()
    if not hop then
        return
    end
    if G.state == "play" and (P.mode == "air" or P.mode == "catch") then
        hop_saw_air = true
        return
    end
    if hop_saw_air or G.state ~= "play" then
        hop = false
        hop_saw_air = false
        return
    end
    hop_wait = hop_wait - 1
    if hop_wait <= 0 then
        hop = false
        hop_saw_air = false
    end
end

local function human_edge()
    local keys = { "Left", "Right", "A", "D", "Up", "W", "Down", "S", "Space" }
    local edge = false
    for _, k in ipairs(keys) do
        local ok, raw = pcall(input.is_key_down_raw, k)
        local held = ok and raw == true
        if raw_primed and held and not raw_prev[k] then
            edge = true
        end
        raw_prev[k] = held
    end
    raw_primed = true
    return edge
end

local function consider_hazard(hx, pad)
    local delta = hx - P.x
    local dist = math.abs(delta) - (pad or 0)
    if dist < 0 then
        dist = 0
    end
    if dist < hazard_best.dist then
        hazard_best.dist = dist
        if delta < 0 then
            hazard_best.side = "left"
        else
            hazard_best.side = "right"
        end
    end
end

local function consider_pit()
    if R.pit == "croc" then
        if croc_open_amount() > 0.5 then
            for _, cx in ipairs(CROC_X) do
                consider_hazard(cx, 0.9)
            end
        end
        local hw = pit_halfwidth()
        consider_hazard(PIT_C - hw, 0)
        consider_hazard(PIT_C + hw, 0)
        return
    end
    if not R.pit then
        return
    end
    local reach = pit_halfwidth() - 0.5
    if reach < 0 then
        reach = 0
    end
    local left = PIT_C - reach
    local right = PIT_C + reach
    if P.x >= left and P.x <= right then
        if 0 < hazard_best.dist then
            hazard_best.dist = 0
            if P.x < PIT_C then
                hazard_best.side = "right"
            else
                hazard_best.side = "left"
            end
        end
        return
    end
    if P.x < left then
        consider_hazard(left, 0)
    else
        consider_hazard(right, 0)
    end
end

local function nearest_hazard()
    if not R then
        return "none", 999
    end
    hazard_best.dist = 1e9
    hazard_best.side = "none"
    for _, h in ipairs(R.holes) do
        consider_hazard(h, 0.85)
    end
    for _, l in ipairs(logs) do
        consider_hazard(l.x, 0.55)
    end
    if R.fire or R.cobra then
        consider_hazard(19.5, 0.5)
    end
    if G.under and R.scorpion then
        consider_hazard(G.scorp_x, 0.55)
    end
    consider_pit()
    if hazard_best.dist >= 1e9 then
        return "none", 999
    end
    return hazard_best.side, hazard_best.dist
end

local function round2(v)
    return math.floor(v * 100 + 0.5) / 100
end

local function observe_match()
    local side, dist = nearest_hazard()
    return {
        x = round2(P.x),
        on_ground = P.mode == "ground",
        on_vine = P.mode == "vine" or P.mode == "catch",
        hazard_side = side,
        hazard_distance = round2(dist),
        lives = G.lives or 0,
        score = G.score or 0,
    }
end

local ACTIONS = {
    { id = "left", description = "Hold left" },
    { id = "right", description = "Hold right" },
    { id = "stop", description = "Release left and right" },
    { id = "jump", description = "Jump" },
    { id = "down", description = "Drop from a vine" },
}

local function apply_action(id)
    if id == "left" then
        G.vkeys.Left = true
        G.vkeys.Right = nil
    elseif id == "right" then
        G.vkeys.Right = true
        G.vkeys.Left = nil
    elseif id == "stop" then
        G.vkeys.Left = nil
        G.vkeys.Right = nil
    elseif id == "jump" then
        G.vkeys.Right = true
        G.vkeys.Left = nil
        G.vkeys.Space = true
        pulse_space = true
        if G.state == "play" then
            hop = true
            hop_saw_air = false
            hop_wait = 2
        end
    elseif id == "down" then
        G.vkeys.Down = true
        pulse_down = true
    end
end

local function reset_match(seed)
    math.randomseed(seed or 1)
    clear_hold()
    new_game()
end

local function start_jev()
    raw_primed = false
    jev:begin_human()
    if jev:start() then
        return
    end
    local message = jev:error() or "Jev could not start"
    pe_log("[Pitfall] " .. message)
    show_toast(message)
    toast.t = 6
end

local function update(dt)
    dt = math.min(dt, 0.25)
    jev:tick(dt)
    G.flash = math.max(0, (G.flash or 0) - dt * 1.6)
    toast.t = math.max(0, toast.t - dt)
    if SET and SET:update(dt) then latch_keys(); return end
    local mclick = G.mclick; G.mclick = nil
    if SET and (pressed("Tab") or mclick == "settings") then
        local was = G.state
        if was == "play" then G.state = "pause" end
        runtime_ui.hide("menu")
        SET:open(function() if was == "play" then G.state = "play" end end)
        latch_keys(); return
    end
    if SET and pressed("M") then SET:toggle_mute() end
    if G.state == "title" then
        G.t = G.t + dt; title_t = title_t + dt
        P.mode, P.vx, P.face, P.y = "ground", MAX_RUN * 0.55, 1, 0
        P.x = 2.5 + (title_t * MAX_RUN * 0.55) % 19
        P.run_phase = P.run_phase + P.vx * dt * 1.6
        present_world(dt); animate_harry(dt); update_camera(dt)
        draw_menu("title")
        if pressed("Return", "Space") or mclick == "start" then
            jev:begin_human()
            new_game()
        elseif mclick == "jev" then
            start_jev()
        end
    elseif G.state == "play" or G.state == "dying" then
        gather_input()
        release_pulses()
        acc = acc + dt
        local steps = 0
        while acc >= STEP and steps < 60 do
            acc, steps = acc - STEP, steps + 1
            G.t = G.t + STEP
            if G.state == "play" then G.time = G.time - STEP; step_player(STEP, inp)
            else G.die_t = G.die_t + STEP end
            step_world(STEP)
        end
        if steps >= 60 then acc = 0 end
        present_world(dt); animate_harry(dt); update_camera(dt); draw_hud(dt)
        if G.state == "play" then
            if G.time <= 0 then G.time = 0; G.state = "over"; sfx("death") end
            if pressed("P", "Escape") then G.state = "pause"; sfx("select") end
        elseif G.state == "dying" and G.die_t > 2.0 then
            G.lives = G.lives - 1
            if G.lives <= 0 then G.state = "over" else G.state = "play"; respawn(); show_toast("WATCH YOUR STEP, HARRY!") end
        end
        settle_hop()
    elseif G.state == "pause" then
        draw_hud(dt); draw_menu("pause")
        if pressed("Return", "P") or mclick == "resume" then G.state = "play"; runtime_ui.hide("menu"); sfx("select")
        elseif pressed("Escape") or mclick == "quit" then G.state = "title"; runtime_ui.hide("hud"); title_t = 0; setup_room(0) end
    elseif G.state == "over" or G.state == "win" then
        G.t = G.t + dt
        present_world(dt); update_camera(dt); draw_hud(dt); draw_menu(G.state)
        if pressed("Return") or mclick == "again" then
            jev:begin_human()
            new_game()
        end
    end
    latch_keys()
end

G.sim = function(sec, keys, hold_only)
    G.vkeys = keys or {}
    local n, first = math.floor(sec / STEP + 0.5), true
    for _ = 1, n do
        local li = { left = down("Left"), right = down("Right"), up = down("Up"), down = down("Down"), jump_held = down("Space"),
            jump_pressed = first and down("Space") and not hold_only }
        first = false
        G.t = G.t + STEP
        if G.state == "play" then step_player(STEP, li) elseif G.state == "dying" then G.die_t = (G.die_t or 0) + STEP end
        step_world(STEP)
    end
    G.vkeys = {}
    return string.format("%s mode=%s x=%.2f y=%.2f vy=%.2f under=%s screen=%d score=%d found=%d", G.state, P.mode, P.x, P.y, P.vy, tostring(G.under), G.screen, G.score, G.found)
end
G.new_game, G.setup_room, G.P, G.die = new_game, setup_room, P, die
G.room = function() return R end
G.find_room = function(pred) for i = 0, 254 do if pred(room(i)) then return i end end end
G.H, G.OBJ, G.WORLD, G.TPL = H, OBJ, WORLD, TPL
G.set = function() return SET end
G.vine = vine_state
G.croc_open = croc_open_amount

local jev_src = assert(fs.read("Scripts/jev_auto.lua"), "Missing Scripts/jev_auto.lua")
local JevAuto = assert(load(jev_src, "@Scripts/jev_auto.lua", "t", _ENV))()
jev = JevAuto.attach({
    port = 9102,
    id = "pitfall",
    description = "Pitfall! Remastered. Run, jump, and swing on vines. Left and right are holds. Jump and down are one-frame taps.",
    playing = function()
        return G.state == "play" or G.state == "dying"
    end,
    terminal = function()
        return G.state == "over" or G.state == "win"
    end,
    score = function()
        return G.score or 0
    end,
    busy = function()
        return hop
    end,
    human_edge = human_edge,
    observe = observe_match,
    actions = function()
        local side, dist = nearest_hazard()
        if dist and dist >= 0 and dist < 2.2 then
            return { { id = "jump", description = "Jump while running right.", score = 2 } }
        end
        if side == "left" then
            return { { id = "left", description = "Run left, away from the hazard.", score = 1 } }
        end
        return { { id = "right", description = "Run right.", score = 1 } }
    end,
    apply = apply_action,
    reset = reset_match,
    on_human = clear_hold,
})

hooks { init = init, update = update }
