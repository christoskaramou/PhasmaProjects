-- RIVER RAID REMIX -- a modern 3D remake of Activision's River Raid (Atari 2600, 1982) for Phasma Engine.
-- Faithful rules: vertical scroll up a procedurally generated river, speed control, fuel that drains and
-- refills over FUEL depots, bridges as checkpoints, tankers / helicopters / jets, lives and bonus lives.
-- Visuals first: cooked procedural meshes (template nodes T_* in main.pescene, cloned with add_mesh_ref),
-- glossy water, rocky banks, dynamic lights, bloom and dense particle VFX.

local PI = math.pi
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
local DEG = 180 / PI
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, r, dt) return lerp(a, b, 1 - math.exp(-r * dt)) end
local function sfx(name) pcall(audio.play, "Audio/" .. name .. ".wav") end

local G = { state = "boot", t = 0, vkeys = {} }
local jev
local nearest_obstacle
_G.RR = G
local SET = nil
local function pscale() return SET and SET:particle_scale() or 1 end
local function shscale() return SET and SET:shake_scale() or 1 end

---------------------------------------------------------------- deferred material writes
-- (a colour set in the same frame an object is created is ignored, so writes are replayed later)
local _mset, _mtex = material.set, material.set_texture
local mat_q = {}
local function qpush(f) mat_q[#mat_q + 1] = { f = f, n = 0 } end
local function flush_mats()
    for i = #mat_q, 1, -1 do
        local q = mat_q[i]; q.n = q.n + 1
        if q.n == 2 or q.n == 8 or q.n == 30 then q.f() end
        if q.n >= 30 then table.remove(mat_q, i) end
    end
end

---------------------------------------------------------------- keys
local WATCH = { "Up", "Down", "Left", "Right", "W", "A", "S", "D", "Space", "Return", "Escape", "P", "O", "M", "R", "Q", "Z", "J", "X", "LShift" }
local keys_prev, keys_now = {}, {}
local function rawdown(k)
    if G.vkeys[k] then return true end
    local ok, v = pcall(input.is_key_down_raw, k)
    if ok and v ~= nil then return v end
    return input.is_key_pressed(k)
end
local function poll_keys() for _, k in ipairs(WATCH) do keys_now[k] = rawdown(k) end end
local function held(...) for _, k in ipairs({ ... }) do if keys_now[k] then return true end end return false end
local function pressed(...)
    for _, k in ipairs({ ... }) do if keys_now[k] and not keys_prev[k] then return true end end
    return false
end
local function latch_keys() for _, k in ipairs(WATCH) do keys_prev[k] = keys_now[k] end end

-- Hardware edges only, and only during a live match. Menu arrows share those keys.
local HUMAN_KEYS = { "Left", "Right", "Up", "Down", "W", "A", "S", "D", "Space", "Z", "J", "X" }
local human_down = {}
local function human_edge()
    local edge = false
    for _, key in ipairs(HUMAN_KEYS) do
        local ok, down = pcall(input.is_key_down_raw, key)
        local pressed_key = ok and down == true
        if pressed_key and not human_down[key] then
            edge = true
        end
        human_down[key] = pressed_key
    end
    if G.state ~= "play" then
        return false
    end
    return edge
end

---------------------------------------------------------------- render setup
local function S(k, v) pcall(settings.set, k, v) end
local function setup_render()
    local ss = scene.add_empty_node("RiverRaidSceneSettings"); ss:set_scene_settings(true)
    pcall(settings.set_render_mode, "raster")
    pcall(skybox.load, "golden.hdr")
    S("taa", true); S("hdr", true); S("motion_blur", false)          -- TAA on (RENDER_SETTINGS.md); motion blur smears bloom
    S("bloom", true); S("bloom_strength", 0.55); S("bloom_range", 1.25)   -- weaker + smooth (no stair-steps)
    S("tonemapping", true); S("fxaa", false); S("cas_sharpening", false)  -- CAS overwrites bloom when TAA is on
    S("ssao", false); S("ssr", false); S("dof", false)
    S("fog", true); S("fog_density", 0.008); S("fog_start", 40.0)
    S("shadows", true); S("shadow_map_size", 2048); S("shadow_distance", 70.0)
    S("render_scale", 1.0)
    S("IBL", true); S("IBL_intensity", 0.9)
    S("color_grading", true); S("color_grading_saturation", 1.15); S("color_grading_contrast", 1.07)
end

---------------------------------------------------------------- templates & clones
local TPL = {}
local function tpl(name)
    if TPL[name] ~= nil then return TPL[name] or nil end
    local n = scene.find_model("T_" .. name)
    if not n then pe_log("[RR] missing template T_" .. name); TPL[name] = false; return nil end
    TPL[name] = { node = n, refs = n:get_mesh_refs() }
    return TPL[name]
end
local function tpaint(name, base, emis, rough, metal)
    local t = tpl(name); if not t then return end
    local f = function()
        for slot = 0, #t.refs - 1 do
            pcall(_mset, t.node, slot, "base_color", vec4(base[1], base[2], base[3], 1))
            pcall(_mset, t.node, slot, "emissive", vec3(emis[1], emis[2], emis[3]))
            pcall(_mset, t.node, slot, "roughness", rough or 0.5)
            pcall(_mset, t.node, slot, "metallic", metal or 0.0)
        end
    end
    f(); qpush(f)
end
local function temis(name, e)   -- live emissive change (shared by every clone)
    local t = tpl(name); if not t then return end
    for slot = 0, #t.refs - 1 do pcall(_mset, t.node, slot, "emissive", e) end
end
local function ttex(name, kind, file)
    local t = tpl(name); if not t then return end
    qpush(function()
        for slot = 0, #t.refs - 1 do
            if not pcall(_mtex, t.node, slot, kind, "Textures/" .. file) then pcall(_mtex, t.node, kind, "Textures/" .. file) end
        end
    end)
end
local HIDE = vec3(0, -1000, 0)
local seq = 0
local function clone(name, pos, scale, parent, rot)
    local t = tpl(name); seq = seq + 1
    local n = scene.add_empty_node(name .. "_c" .. seq)
    if t then for _, m in ipairs(t.refs) do n:add_mesh_ref(m) end end
    if parent then n:set_parent(parent) end
    n:set_position(pos or vec3(0, 0, 0))
    if rot then n:set_rotation(rot) end
    if scale then n:set_scale(type(scale) == "number" and vec3(scale, scale, scale) or scale) end
    return n
end
local function empty(name, pos)
    seq = seq + 1
    local n = scene.add_empty_node(name .. "_e" .. seq)
    n:set_position(pos or HIDE)
    return n
end
-- composite: root empty + child part clones (all parts share the root transform)
local function composite(name, parts, scale)
    local root = empty(name)
    local kids = {}
    for _, p in ipairs(parts) do kids[p] = clone(p, vec3(0, 0, 0), scale, root) end
    return root, kids
end

---------------------------------------------------------------- world constants
local ROW = 2.0            -- river row length (world units along -Z)
local SEC_ROWS = 56        -- rows per section (bridge to bridge)
local FIELD = 34.0         -- land extends this far from the river centre
local BRIDGE_HW = 3.0      -- channel half-width under bridges
local ALT = 1.55           -- flight altitude
local SPD_MIN, SPD_CRUISE, SPD_MAX = 9.0, 15.0, 25.0
local STEER = 8.0          -- max strafe speed (was 11.5)
local STEER_ACC = 26.0     -- lateral acceleration toward target velocity (eased)
local FUEL_DRAIN = 1 / 38  -- per second at cruise
local FUEL_FILL = 0.42
local AHEAD, BEHIND = 26, 6  -- rows kept alive in front of / behind the player

---------------------------------------------------------------- river generator (deterministic per section)
-- boundary b (z = -b*ROW) has half-width HW[b] and island half-width IW[b]; edges are linear between boundaries.
local HW, IW = {}, {}
local SECT_GEN = {}
local function lcg(seed)
    local s = seed % 2147483647; if s <= 0 then s = s + 2147483646 end
    return function(a, b)
        s = (s * 16807) % 2147483647
        local u = (s - 1) / 2147483646
        if a then return a + (b - a) * u end
        return u
    end
end
local function gen_section(sec)
    if SECT_GEN[sec] then return end
    SECT_GEN[sec] = true
    local R = lcg(1013 + sec * 7919)
    local b0 = sec * SEC_ROWS
    local diff = min(1, sec / 8)
    -- bridge channel: boundaries b0-2 .. b0+3
    for b = b0 - 2, b0 + 3 do HW[b] = BRIDGE_HW; IW[b] = 0 end
    local hw, iw = BRIDGE_HW, 0
    local b = b0 + 4
    local last = b0 + SEC_ROWS - 9
    while b < last do
        local len = floor(R(4, 11))
        local th, ti
        local pick = R()
        if sec == 0 and b < b0 + 14 then th, ti = 8.5, 0
        elseif pick < 0.18 + 0.12 * diff then th = R(3.4, 4.6); ti = 0          -- narrow gorge
        elseif pick < 0.55 then th = R(6.0, 10.5); ti = 0                        -- open water
        else th = R(8.5, 12.5); ti = R(1.6, th - 5.0) end                        -- island split
        for k = 1, len do
            if b >= last then break end
            local step = 1.7
            hw = hw + clamp(th - hw, -step, step)
            local itarget = (k < len - 1) and ti or 0
            if hw - iw < 4.2 then itarget = 0 end
            iw = iw + clamp(itarget - iw, -1.4, 1.4)
            if iw < 0.45 and itarget == 0 then iw = 0 end
            HW[b] = hw; IW[b] = iw
            b = b + 1
        end
    end
    -- converge to the next bridge channel
    while b < b0 + SEC_ROWS - 2 do
        hw = hw + clamp(BRIDGE_HW - hw, -1.7, 1.7); iw = max(0, iw - 1.5)
        if hw - iw < 3.5 then iw = max(0, iw - 1.5) end
        HW[b] = hw; IW[b] = iw; b = b + 1
    end
end
local function ensure(b)
    local sec = floor(b / SEC_ROWS)
    gen_section(sec); gen_section(sec + 1)
    if sec > 0 then gen_section(sec - 1) end
end
local function bound(b) ensure(b); return HW[b] or BRIDGE_HW, IW[b] or 0 end
-- river half-width and island half-width at world z
local function river_at(z)
    local fb = -z / ROW
    local b = floor(fb); local t = fb - b
    local h0, i0 = bound(b); local h1, i1 = bound(b + 1)
    return lerp(h0, h1, t), lerp(i0, i1, t)
end
local function is_land(x, z, margin)
    local hw, iw = river_at(z)
    margin = margin or 0
    if abs(x) > hw - margin then return true end
    if iw > 0.05 and abs(x) < iw + margin then return true end
    return false
end
-- random water x in row b (avoids banks and island)
local function water_x(b, R, pad)
    local hw, iw = bound(b)
    pad = pad or 1.0
    if iw > 0.05 then
        local side = (R() < 0.5) and -1 or 1
        local a, c = iw + pad, hw - pad
        if c <= a then return side * (iw + hw) * 0.5 end
        return side * R(a, c)
    end
    local c = hw - pad
    if c <= 0 then return 0 end
    return R(-c, c)
end

---------------------------------------------------------------- materials (per template mesh, shared by clones)
local function setup_materials()
    tpaint("jet_body", { 0.98, 0.74, 0.12 }, { 0.02, 0.012, 0 }, 0.26, 0.35)
    tpaint("jet_wing", { 0.92, 0.55, 0.08 }, { 0.015, 0.006, 0 }, 0.3, 0.35)
    tpaint("jet_trim", { 0.12, 0.13, 0.15 }, { 0, 0, 0 }, 0.35, 0.85)
    tpaint("jet_canopy", { 0.03, 0.08, 0.14 }, { 0.02, 0.08, 0.16 }, 0.04, 0.9)
    tpaint("jet_glow", { 1.0, 0.7, 0.3 }, { 14.0, 6.0, 1.6 }, 0.3, 0.0)
    tpaint("ejet_body", { 0.22, 0.28, 0.36 }, { 0, 0, 0 }, 0.3, 0.6)
    tpaint("ejet_wing", { 0.14, 0.18, 0.24 }, { 0, 0, 0 }, 0.35, 0.6)
    tpaint("ejet_trim", { 0.6, 0.08, 0.06 }, { 0.05, 0, 0 }, 0.4, 0.4)
    tpaint("ejet_canopy", { 0.15, 0.05, 0.02 }, { 0.2, 0.06, 0.0 }, 0.05, 0.9)
    tpaint("ejet_glow", { 1.0, 0.3, 0.2 }, { 12.0, 2.5, 1.0 }, 0.3, 0.0)
    tpaint("heli_body", { 0.24, 0.33, 0.14 }, { 0, 0, 0 }, 0.45, 0.25)
    tpaint("heli_glass", { 0.03, 0.06, 0.08 }, { 0.01, 0.03, 0.04 }, 0.04, 0.9)
    tpaint("heli_skid", { 0.08, 0.08, 0.09 }, { 0, 0, 0 }, 0.4, 0.8)
    tpaint("heli_rotor", { 0.1, 0.1, 0.11 }, { 0, 0, 0 }, 0.5, 0.6)
    tpaint("heli_trotor", { 0.1, 0.1, 0.11 }, { 0, 0, 0 }, 0.5, 0.6)
    tpaint("heli_glow", { 1.0, 0.1, 0.05 }, { 14.0, 0.8, 0.3 }, 0.3, 0.0)
    tpaint("ship_hull", { 0.48, 0.07, 0.05 }, { 0, 0, 0 }, 0.4, 0.3)
    tpaint("ship_deck", { 0.2, 0.26, 0.22 }, { 0, 0, 0 }, 0.6, 0.4)
    tpaint("ship_cabin", { 0.92, 0.92, 0.88 }, { 0.01, 0.01, 0.01 }, 0.35, 0.1)
    tpaint("ship_funnel", { 0.08, 0.08, 0.08 }, { 0, 0, 0 }, 0.5, 0.3)
    tpaint("ship_glow", { 1.0, 0.85, 0.5 }, { 9.0, 6.5, 2.8 }, 0.3, 0.0)
    tpaint("depot_base", { 0.5, 0.5, 0.52 }, { 0, 0, 0 }, 0.6, 0.5); ttex("depot_base", "base_color", "metal.png")
    tpaint("depot_tank", { 1, 1, 1 }, { 0.02, 0.0, 0.0 }, 0.3, 0.2); ttex("depot_tank", "base_color", "fuel.png")
    tpaint("depot_dome", { 0.85, 0.86, 0.88 }, { 0, 0, 0 }, 0.25, 0.8)
    tpaint("depot_glow", { 0.3, 1.0, 0.4 }, { 1.5, 10.0, 2.5 }, 0.3, 0.0)
    tpaint("bridge_road", { 0.6, 0.6, 0.6 }, { 0, 0, 0 }, 0.7, 0.0); ttex("bridge_road", "base_color", "asphalt.png")
    tpaint("bridge_deck", { 0.7, 0.68, 0.65 }, { 0, 0, 0 }, 0.8, 0.0); ttex("bridge_deck", "base_color", "concrete.png")
    tpaint("bridge_steel", { 0.78, 0.2, 0.07 }, { 0.02, 0.003, 0 }, 0.38, 0.65)
    tpaint("bridge_pier", { 0.62, 0.6, 0.57 }, { 0, 0, 0 }, 0.85, 0.0); ttex("bridge_pier", "base_color", "concrete.png")
    tpaint("bridge_lamp", { 0.1, 0.1, 0.11 }, { 0, 0, 0 }, 0.4, 0.8)
    tpaint("bridge_glow", { 1.0, 0.8, 0.45 }, { 12.0, 8.0, 3.0 }, 0.3, 0.0)
    tpaint("road", { 0.07, 0.07, 0.075 }, { 0, 0, 0 }, 0.6, 0.0)
    tpaint("road_kerb", { 0.55, 0.53, 0.5 }, { 0, 0, 0 }, 0.8, 0.0)
    tpaint("shore_grass", { 0.9, 0.9, 0.75 }, { 0, 0, 0 }, 0.92, 0.0); ttex("shore_grass", "base_color", "grass.png"); ttex("shore_grass", "normal", "grass_n.png")
    tpaint("shore_rock", { 1, 1, 1 }, { 0, 0, 0 }, 0.85, 0.0); ttex("shore_rock", "base_color", "rock.png"); ttex("shore_rock", "normal", "rock_n.png")
    tpaint("land", { 0.85, 0.85, 0.7 }, { 0, 0, 0 }, 0.95, 0.0); ttex("land", "base_color", "grass.png")
    tpaint("tree_trunk", { 0.3, 0.2, 0.12 }, { 0, 0, 0 }, 0.9, 0.0)
    tpaint("tree_pine", { 0.17, 0.44, 0.17 }, { 0, 0.004, 0 }, 0.8, 0.0)
    tpaint("tree_leaf", { 0.25, 0.48, 0.12 }, { 0.004, 0.01, 0 }, 0.75, 0.0)
    tpaint("boulder", { 0.5, 0.48, 0.45 }, { 0, 0, 0 }, 0.85, 0.0); ttex("boulder", "base_color", "rock.png")
    tpaint("house_wall", { 0.92, 0.86, 0.72 }, { 0, 0, 0 }, 0.8, 0.0)
    tpaint("house_roof", { 0.62, 0.13, 0.08 }, { 0, 0, 0 }, 0.6, 0.1)
    tpaint("house_win", { 1.0, 0.8, 0.45 }, { 4.0, 2.6, 0.9 }, 0.3, 0.0)
    tpaint("water", { 0.38, 0.7, 0.8 }, { 0.0, 0.012, 0.02 }, 0.06, 0.15); ttex("water", "normal", "water_n.png"); ttex("water", "base_color", "water.png")
    tpaint("fx_fire", { 0.35, 0.07, 0.01 }, { 1.1, 0.2, 0.015 }, 0.5, 0.0)
    tpaint("fx_core", { 1.0, 0.7, 0.3 }, { 2.2, 1.1, 0.22 }, 0.5, 0.0)
    tpaint("fx_smoke", { 0.3, 0.28, 0.26 }, { 0.05, 0.045, 0.04 }, 1.0, 0.0)
    tpaint("fx_ring", { 1.0, 0.7, 0.4 }, { 0.8, 0.3, 0.08 }, 0.5, 0.0)
    tpaint("fx_debris", { 0.15, 0.13, 0.12 }, { 0.8, 0.22, 0.03 }, 0.6, 0.6)
    tpaint("missile_body", { 0.85, 0.86, 0.9 }, { 0, 0, 0 }, 0.3, 0.8)
    tpaint("missile_glow", { 1.0, 0.7, 0.3 }, { 20.0, 9.0, 2.0 }, 0.3, 0.0)
end

---------------------------------------------------------------- node pools
local KIND_PARTS = {
    shore = { "shore_grass", "shore_rock" }, rockonly = { "shore_rock" }, land = { "land" },
    pine = { "tree_trunk", "tree_pine" }, leaf = { "tree_trunk", "tree_leaf" }, boulder = { "boulder" },
    house = { "house_wall", "house_roof", "house_win" }, road = { "road", "road_kerb" },
    ship = { "ship_hull", "ship_deck", "ship_cabin", "ship_funnel", "ship_glow" },
    heli = { "heli_body", "heli_glass", "heli_skid", "heli_rotor", "heli_trotor", "heli_glow" },
    jet = { "jet_body", "jet_wing", "jet_trim", "jet_canopy", "jet_glow" },
    ejet = { "ejet_body", "ejet_wing", "ejet_trim", "ejet_canopy", "ejet_glow" },
    depot = { "depot_base", "depot_tank", "depot_dome", "depot_glow" },
    bridge = { "bridge_road", "bridge_deck", "bridge_steel", "bridge_pier", "bridge_lamp", "bridge_glow" },
    fire = { "fx_fire" }, core = { "fx_core" }, smoke = { "fx_smoke" }, ring = { "fx_ring" }, debris = { "fx_debris" },
    missile = { "missile_body", "missile_glow" },
}
local POOL = {}
local function take(kind)
    local p = POOL[kind]; if not p then p = {}; POOL[kind] = p end
    local it = p[#p]
    if it then p[#p] = nil; return it end
    local root, kids = composite(kind, KIND_PARTS[kind])
    return { root = root, kids = kids, kind = kind }
end
local function release(it)
    if not it then return end
    it.root:set_position(HIDE)
    local p = POOL[it.kind]; p[#p + 1] = it
end
local function prewarm(kind, n)
    local list = {}
    for i = 1, n do list[i] = take(kind) end
    for i = 1, n do release(list[i]) end
end
local function place(it, x, y, z, yaw, sx, sy, sz)
    it.root:set_position(vec3(x, y, z))
    it.root:set_rotation(vec3(0, (yaw or 0) * DEG, 0))
    if sx then it.root:set_scale(vec3(sx, sy or sx, sz or sx)) end
end

---------------------------------------------------------------- rows: banks, islands, decor
local ROWS = {}     -- active rows: r -> { items = {...} }
local ENT = {}      -- live entities (ships, helis, jets, depots, bridges)
local function shore_piece(items, x0, x1, z0, water_left, kind)
    -- edge line from (x0,z0) to (x1,z0-ROW); strip local +X faces the water
    local dx = x0 - x1
    local L = sqrt(ROW * ROW + dx * dx)
    local yaw = atan2(dx, ROW)
    if water_left then yaw = yaw + PI end
    local it = take(kind or "shore")
    place(it, (x0 + x1) * 0.5, 0, z0 - ROW * 0.5, yaw, 1, 1, L * 1.06)
    items[#items + 1] = it
end
local function land_piece(items, xedge, z, width, flip)
    local it = take("land")
    place(it, xedge, 0, z, flip and PI or 0, width, 1, ROW * 1.02)
    items[#items + 1] = it
end
local DECOR_KINDS = { "pine", "pine", "pine", "leaf", "leaf", "boulder", "house" }
local function decor(items, R, x, z, kind)
    local it = take(kind)
    local s = R(0.8, 1.35)
    if kind == "house" then s = R(0.9, 1.15) end
    if kind == "boulder" then s = R(0.6, 1.4) end
    place(it, x, 0.6, z, R(0, 2 * PI), s, s * (kind == "pine" and R(0.9, 1.5) or 1), s)
    items[#items + 1] = it
end
local spawn_row_entities -- forward
local function build_row(r)
    local items = {}
    local h0, i0 = bound(r); local h1, i1 = bound(r + 1)
    local z0 = -r * ROW; local zm = z0 - ROW * 0.5
    shore_piece(items, -h0, -h1, z0, false)
    shore_piece(items, h0, h1, z0, true)
    local hm = max(h0, h1) + 0.95
    land_piece(items, -hm, zm, FIELD, false)
    land_piece(items, hm, zm, FIELD, true)
    if i0 > 0.05 or i1 > 0.05 then
        local tip = (i0 < 1.2 or i1 < 1.2) and "rockonly" or "shore"
        shore_piece(items, i0, i1, z0, false, tip)
        shore_piece(items, -i0, -i1, z0, true, tip)
        local im = min(i0, i1) - 0.95
        if im > 0.05 then land_piece(items, im, zm, 2 * im, false) end
    end
    -- decor (deterministic per row)
    local R = lcg(r * 131 + 17)
    local sec = floor(r / SEC_ROWS); local k = r - sec * SEC_ROWS
    local bridge_row = (k == 0)
    for side = -1, 1, 2 do
        local n = floor(R(1, 4.2))
        for j = 1, n do
            local d = R(2.4, 17)
            local kind = DECOR_KINDS[floor(R(1, #DECOR_KINDS + 0.999))]
            if kind == "house" and d < 4.5 then kind = "leaf" end
            local zz = zm + R(-0.9, 0.9)
            if not (bridge_row and abs(zz - zm) < 1.4) then decor(items, R, side * (hm + d - 0.6), zz, kind) end
        end
    end
    if min(i0, i1) > 2.2 and R() < 0.8 then
        decor(items, R, R(-1, 1) * (min(i0, i1) - 1.6), zm + R(-0.6, 0.6), R() < 0.6 and "pine" or "leaf")
    end
    if bridge_row then
        for side = -1, 1, 2 do
            for x = 7.0, FIELD, 2.0 do
                local it = take("road"); place(it, side * x, x < 8.5 and 0.18 or 0.0, zm, 0, 1.0, 1, 1)
                items[#items + 1] = it
            end
        end
    end
    ROWS[r] = { items = items }
    spawn_row_entities(r)
end
local function free_row(r)
    local row = ROWS[r]; if not row then return end
    for _, it in ipairs(row.items) do release(it) end
    ROWS[r] = nil
end
local function clear_rows()
    for r in pairs(ROWS) do free_row(r) end
    for i = #ENT, 1, -1 do release(ENT[i].it); ENT[i] = nil end
end

---------------------------------------------------------------- entities
local KINDS = {
    ship = { hx = 2.15, hz = 0.62, y = 0.0, pts = 30 },
    heli = { hx = 1.25, hz = 0.55, y = 1.25, pts = 60 },
    ejet = { hx = 1.0, hz = 0.95, y = 1.9, pts = 100 },
    depot = { hx = 1.2, hz = 1.6, y = 0.0, pts = 80 },
    bridge = { hx = 6.2, hz = 0.95, y = 0.0, pts = 500 },
}
local function add_ent(kind, x, z, r, extra)
    local e = { kind = kind, it = take(kind), x = x, z = z, row = r, alive = true, vx = 0, active = false, t = rand() * 10 }
    local K = KINDS[kind]; e.hx, e.hz, e.y, e.pts = K.hx, K.hz, K.y, K.pts
    if extra then for k, v in pairs(extra) do e[k] = v end end
    e.dir = (rand() < 0.5) and -1 or 1
    place(e.it, x, e.y, z, (kind == "ship" or kind == "heli" or kind == "ejet") and (e.dir > 0 and -PI / 2 or PI / 2) or 0, 1)
    ENT[#ENT + 1] = e
    return e
end
spawn_row_entities = function(r)
    local sec = floor(r / SEC_ROWS); local k = r - sec * SEC_ROWS
    if k == 0 then
        if not (G.bridges_down and G.bridges_down[sec]) then add_ent("bridge", 0, -(r + 0.5) * ROW, r, { sec = sec }) end
        return
    end
    if k < 6 or k > SEC_ROWS - 5 then return end
    if sec == 0 and k < 10 then return end
    local R = lcg(r * 977 + 3 + G.seed)
    local diff = min(1, sec / 10)
    local forced = (k % 15 == 13)
    if not forced then
        if R() > 0.36 + 0.2 * diff then return end
        if (r % 2 == 1) and R() < 0.6 then return end
    end
    local hw, iw = bound(r)
    local z = -(r + R(0.2, 0.8)) * ROW
    local p = R()
    local kind
    if p < 0.21 - 0.05 * diff then kind = "depot"
    elseif p < 0.58 then kind = "ship"
    elseif p < 0.9 - (sec >= 1 and 0.12 or 0) then kind = "heli"
    else kind = "ejet" end
    if forced then kind = "depot" end
    if kind == "ejet" then
        add_ent("ejet", (R() < 0.5 and -1 or 1) * (FIELD * 0.6), z, r, { speed = R(7, 10) + 3 * diff })
        return
    end
    local pad = (kind == "ship") and 2.4 or ((kind == "depot") and 1.45 or 1.4)
    local ha, ia = bound(r); local hb, ib = bound(r + 1)
    local hmin, imax = min(ha, hb), max(ia, ib)
    local lane_ok = (imax > 0.05) and (hmin - imax > 2 * pad + 0.2) or (hmin > pad + 0.3)
    if not lane_ok then
        if kind == "ship" then kind = "heli"; pad = 1.4 else return end
        lane_ok = (imax > 0.05) and (hmin - imax > 2 * pad + 0.2) or (hmin > pad + 0.3)
        if not lane_ok then return end
    end
    local x = water_x(r, R, pad)
    add_ent(kind, x, z, r, { speed = R(2.2, 4.2) + 2.5 * diff, wake_p = R() < 0.55 + 0.4 * diff, pad = pad })
end
local function ensure_rows(pz)
    local pr = floor(-pz / ROW)
    for r = pr - BEHIND, pr + AHEAD do
        if r >= -4 and not ROWS[r] then build_row(r) end
    end
    for r in pairs(ROWS) do
        if r < pr - BEHIND - 1 or r > pr + AHEAD + 2 then free_row(r) end
    end
    for i = #ENT, 1, -1 do
        local e = ENT[i]
        if e.z > pz + (BEHIND + 2) * ROW or e.z < pz - (AHEAD + 4) * ROW or e.dead then
            release(e.it); table.remove(ENT, i)
        end
    end
end

---------------------------------------------------------------- lights
local function add_point(pos, col, inten, rad)
    lights.add_point()
    local i = #lights.get_point_lights() - 1
    lights.set_point_light(i, pos, col, inten, rad)
    return i
end
local LT = {}
-- point the sun: quaternion (x,y,z,w) rotating the light's base -Z axis onto (dx,dy,dz)
G.sun_dir = function(dx, dy, dz)
    local l = sqrt(dx * dx + dy * dy + dz * dz); dx, dy, dz = dx / l, dy / l, dz / l
    -- a = (0,0,-1); axis = a x d = (dy, -dx, 0); cos = -dz
    local ax, ay, az = dy, -dx, 0
    local al = sqrt(ax * ax + ay * ay)
    local ang = math.acos(clamp(-dz, -1, 1))
    if al < 1e-6 then ax, ay, al = 1, 0, 1 end
    local sh = sin(ang / 2)
    pcall(lights.set_rotation, "directional", 0, vec4(ax / al * sh, ay / al * sh, az * sh, cos(ang / 2)))
end
local flashes, flash_i = {}, 1
local function setup_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(0, 30, 0), vec3(1.0, 0.86, 0.68), 4.2)
    G.sun_dir(0.5, -0.75, -0.38)
    LT.engine = add_point(HIDE, vec3(1.0, 0.55, 0.2), 0, 6)
    LT.missile = add_point(HIDE, vec3(1.0, 0.75, 0.4), 0, 6)
    LT.depot = add_point(HIDE, vec3(0.3, 1.0, 0.45), 0, 7)
    LT.bridge = { add_point(HIDE, vec3(1.0, 0.8, 0.5), 0, 8), add_point(HIDE, vec3(1.0, 0.8, 0.5), 0, 8) }
    for i = 1, 5 do flashes[i] = { idx = add_point(HIDE, vec3(1, 0.6, 0.3), 0, 1), t = 99, life = 0.5 } end
end
local function flash(pos, col, power, life, radius)
    local f = flashes[flash_i]; flash_i = flash_i % #flashes + 1
    f.t, f.life, f.pos, f.col, f.power, f.rad = 0, life or 0.5, pos, col, power or 20, radius or 14
end
local function update_flashes(dt)
    for _, f in ipairs(flashes) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = max(0, 1 - f.t / f.life)
            lights.set_point_light(f.idx, f.pos, f.col, f.power * k * k, f.rad)
        elseif f.t < 90 then
            f.t = 99; lights.set_point_light(f.idx, HIDE, f.col, 0, 1)
        end
    end
end

---------------------------------------------------------------- particles
local function burst(pos, o)
    o = o or {}
    local n = floor((o.count or 40) * pscale())
    if n < 1 then return end
    pcall(particles.emit_burst, {
        position = pos, velocity = o.vel or vec3(0, 1, 0),
        color_start = o.c0 or vec4(1, 0.8, 0.3, 1), color_end = o.c1 or vec4(0.2, 0.05, 0, 0),
        count = n, size_min = o.smin or 0.06, size_max = o.smax or 0.2,
        life_min = o.lmin or 0.3, life_max = o.lmax or 0.9, spawn_radius = o.radius or 0.3,
        noise_strength = o.spread or 8, drag = o.drag or 1.2, gravity = o.grav or vec3(0, -6, 0),
        cleanup_delay = o.cleanup or 3.0,
    })
end
local EM = {}
local function emitter(o)
    local ok, id = pcall(particles.add_emitter, o)
    return ok and id or nil
end
local function eset(id, k, v) if id then pcall(particles.set_emitter, id, k, v) end end
local function setup_emitters()
    EM.exhaust = emitter({ position = HIDE, velocity = vec3(0, 0.2, 5), color_start = vec4(1.0, 0.75, 0.35, 1), color_end = vec4(0.3, 0.3, 0.5, 0),
        count = 500, spawn_rate = 160, spawn_radius = 0.06, size_min = 0.05, size_max = 0.13, life_min = 0.12, life_max = 0.35,
        noise_strength = 0.6, drag = 0.5, gravity = vec3(0, 0.3, 0) })
    EM.heat = emitter({ position = HIDE, velocity = vec3(0, 0.3, 3), color_start = vec4(0.65, 0.65, 0.7, 0.25), color_end = vec4(0.5, 0.5, 0.55, 0),
        count = 300, spawn_rate = 60, spawn_radius = 0.1, size_min = 0.12, size_max = 0.3, life_min = 0.4, life_max = 0.9,
        noise_strength = 0.8, drag = 0.8, gravity = vec3(0, 0.5, 0) })
    EM.spray = emitter({ position = HIDE, velocity = vec3(0, 1.6, 2.5), color_start = vec4(0.85, 0.95, 1.0, 0.75), color_end = vec4(0.7, 0.85, 0.95, 0),
        count = 700, spawn_rate = 140, spawn_radius = 0.55, size_min = 0.04, size_max = 0.14, life_min = 0.3, life_max = 0.85,
        noise_strength = 2.2, drag = 0.9, gravity = vec3(0, -5, 0) })
    EM.trail = {}
    for i = 1, 3 do
        EM.trail[i] = emitter({ position = HIDE, velocity = vec3(0, 0.25, 1.5), color_start = vec4(1.0, 0.85, 0.55, 0.9), color_end = vec4(0.55, 0.55, 0.6, 0),
            count = 400, spawn_rate = 0, spawn_radius = 0.04, size_min = 0.05, size_max = 0.14, life_min = 0.2, life_max = 0.55,
            noise_strength = 0.5, drag = 1.5, gravity = vec3(0, 0.4, 0) })
    end
    EM.wake = {}
    for i = 1, 6 do
        EM.wake[i] = emitter({ position = HIDE, velocity = vec3(0, 0.9, 0), color_start = vec4(0.9, 0.97, 1.0, 0.7), color_end = vec4(0.8, 0.9, 1.0, 0),
            count = 300, spawn_rate = 0, spawn_radius = 0.5, size_min = 0.05, size_max = 0.15, life_min = 0.35, life_max = 0.9,
            noise_strength = 1.4, drag = 1.0, gravity = vec3(0, -2.5, 0) })
    end
    EM.refuel = emitter({ position = HIDE, velocity = vec3(0, 2.0, 0), color_start = vec4(0.4, 1.0, 0.5, 1), color_end = vec4(0.2, 0.8, 1.0, 0),
        count = 300, spawn_rate = 0, spawn_radius = 0.7, size_min = 0.03, size_max = 0.08, life_min = 0.3, life_max = 0.7,
        noise_strength = 1.5, drag = 0.6, gravity = vec3(0, 1.0, 0) })
    EM.pollen = emitter({ position = HIDE, velocity = vec3(0.1, 0.1, 0.3), color_start = vec4(1.0, 0.9, 0.5, 0.8), color_end = vec4(1.0, 0.8, 0.3, 0),
        count = 200, spawn_rate = 30, spawn_radius = 14, size_min = 0.015, size_max = 0.04, life_min = 2, life_max = 4,
        noise_strength = 0.4, drag = 0.4, gravity = vec3(0, 0.05, 0) })
end

---------------------------------------------------------------- explosion meshes (fireballs, shock rings, smoke, debris)
local FX = {}
local function fx_mesh(kind, pos, life, s0, s1, vel, spin)
    local it = take(kind)
    local f = { it = it, t = 0, life = life, s0 = s0, s1 = s1, p = pos, v = vel or vec3(0, 0, 0), spin = spin or 0, rot = rand() * 360, kind = kind }
    place(it, pos.x, pos.y, pos.z, 0, s0)
    FX[#FX + 1] = f
end
local function update_fx(dt)
    for i = #FX, 1, -1 do
        local f = FX[i]
        f.t = f.t + dt
        local k = f.t / f.life
        if k >= 1 then release(f.it); table.remove(FX, i)
        else
            if f.kind == "debris" then f.v = vec3(f.v.x * (1 - dt), f.v.y - 14 * dt, f.v.z * (1 - dt)) end
            f.p = vec3(f.p.x + f.v.x * dt, f.p.y + f.v.y * dt, f.p.z + f.v.z * dt)
            if f.kind == "debris" and f.p.y < 0 then
                burst(vec3(f.p.x, 0.05, f.p.z), { count = 8, c0 = vec4(0.9, 0.95, 1, 0.8), c1 = vec4(0.8, 0.9, 1, 0), vel = vec3(0, 2.5, 0), smin = 0.04, smax = 0.1, spread = 3, grav = vec3(0, -7, 0), lmax = 0.6 })
                release(f.it); table.remove(FX, i); goto cont
            end
            local e = (f.kind == "ring") and (1 - (1 - k) ^ 3) or sqrt(k)
            local s = lerp(f.s0, f.s1, e)
            if f.kind == "fire" or f.kind == "core" then s = f.s1 * sin(min(1, k * 1.15) * PI) ^ 0.6 + 0.01 end
            if f.kind == "ring" then f.it.root:set_scale(vec3(s, 1 + 2 * (1 - k), s))
            else f.it.root:set_scale(vec3(s, s, s)) end
            f.rot = f.rot + f.spin * dt
            if f.kind ~= "ring" then f.it.root:set_rotation(vec3(f.rot * 0.7, f.rot, f.rot * 0.3)) end
            f.it.root:set_position(f.p)
        end
        ::cont::
    end
end
local function explode(x, y, z, size, on_water)
    size = (size or 1) * 0.7   -- smaller, less blinding explosions
    local ps = pscale()
    local P = vec3(x, y, z)
    fx_mesh("fire", P, 0.5 * size, 0.2, 1.05 * size, vec3(0, 1.2, 0), 120)
    fx_mesh("core", vec3(x, y + 0.1, z), 0.3 * size, 0.1, 0.6 * size, vec3(0, 0.6, 0), 80)
    if size > 0.9 then fx_mesh("fire", vec3(x + rr(-0.6, 0.6) * size, y + 0.4, z + rr(-0.5, 0.5)), 0.6 * size, 0.2, 0.75 * size, vec3(0, 2, 0), -90) end
    fx_mesh("ring", vec3(x, max(0.08, y - 0.3), z), 0.45, 0.3, 3.2 * size, nil, 0)
    for i = 1, floor((5 + 4 * size) * ps + 0.5) do
        local a = rand() * 2 * PI
        local sp = rr(4, 11) * size
        fx_mesh("debris", vec3(x, y + 0.2, z), rr(0.8, 1.6), rr(0.6, 1.4) * size, rr(0.5, 1.0) * size, vec3(cos(a) * sp, rr(4, 10), sin(a) * sp), rr(-600, 600))
    end
    for i = 1, floor(2 * size) do
        fx_mesh("smoke", vec3(x + rr(-0.5, 0.5), y + 0.3, z + rr(-0.5, 0.5)), rr(1.4, 2.2) * size, 0.15, rr(0.5, 0.9) * size, vec3(rr(-0.3, 0.3), rr(1.0, 2.0), rr(0.3, 1.2)), rr(-40, 40))
    end
    burst(P, { count = 90 * size, c0 = vec4(0.8, 0.5, 0.2, 0.8), c1 = vec4(0.6, 0.12, 0.02, 0), smin = 0.08, smax = 0.28 * size, lmin = 0.25, lmax = 0.8, spread = 14 * size, radius = 0.4 * size, grav = vec3(0, 1.5, 0), drag = 2.0 })
    burst(P, { count = 60 * size, c0 = vec4(0.85, 0.7, 0.4, 0.8), c1 = vec4(1.0, 0.35, 0.05, 0), smin = 0.02, smax = 0.06, lmin = 0.4, lmax = 1.3, spread = 26 * size, vel = vec3(0, 6, 0), grav = vec3(0, -12, 0), drag = 0.6 })
    burst(vec3(x, y + 0.6, z), { count = 90 * size, c0 = vec4(0.22, 0.2, 0.19, 0.85), c1 = vec4(0.45, 0.43, 0.42, 0), smin = 0.3, smax = 0.9 * size, lmin = 1.2, lmax = 2.6, spread = 3, radius = 0.6 * size, vel = vec3(0, 1.6, 0.6), grav = vec3(0, 0.6, 0), drag = 1.0, cleanup = 4 })
    if on_water then
        burst(vec3(x, 0.1, z), { count = 160 * size, c0 = vec4(0.9, 0.97, 1.0, 0.9), c1 = vec4(0.75, 0.88, 1.0, 0), smin = 0.06, smax = 0.18, lmin = 0.5, lmax = 1.2, spread = 6 * size, radius = 0.9 * size, vel = vec3(0, 7.5, 0), grav = vec3(0, -13, 0), drag = 0.5 })
        sfx("splash")
    end
    flash(vec3(x, y + 1.2, z), vec3(1.0, 0.6, 0.25), 16 * size, 0.45 * size, 9 * size)
    G.shake = max(G.shake, 0.25 * size)
end

---------------------------------------------------------------- player
local P = { x = 0, z = 0, vx = 0, spd = SPD_CRUISE, roll = 0, pitch = 0, fuel = 1, alive = true, dead_t = 0, it = nil, inv = 0, fire_cd = 0 }
local MIS = {}
local WATER, CAM = nil, nil
local CAMS = { x = 0, z = 8, lx = 0, fov = 1.1 }
local function start_z(sec) return -(sec * SEC_ROWS + 3) * ROW end

local function fire_missile()
    if #MIS >= 2 or P.fire_cd > 0 then return end
    P.fire_cd = 0.2
    local m = { it = take("missile"), x = P.x, z = P.z - 1.0, y = ALT - 0.12, t = 0, slot = nil }
    for i = 1, #EM.trail do
        local used = false
        for _, o in ipairs(MIS) do if o.slot == i then used = true end end
        if not used then m.slot = i; break end
    end
    if m.slot then eset(EM.trail[m.slot], "spawn_rate", 220 * pscale()) end
    place(m.it, m.x, m.y, m.z, 0, 1.4)
    MIS[#MIS + 1] = m
    burst(vec3(P.x, ALT - 0.1, P.z - 1.2), { count = 18, c0 = vec4(1, 0.9, 0.6, 1), c1 = vec4(1, 0.5, 0.1, 0), smin = 0.03, smax = 0.08, lmin = 0.06, lmax = 0.18, spread = 5, grav = vec3(0, 0, 0) })
    sfx("shoot")
end
local function kill_missile(i)
    local m = MIS[i]
    if m.slot then eset(EM.trail[m.slot], "spawn_rate", 0) end
    release(m.it); table.remove(MIS, i)
end

local function award(pts)
    if G.state ~= "play" then return end
    local before = G.score
    G.score = G.score + pts
    if floor(G.score / 10000) > floor(before / 10000) then G.lives = G.lives + 1; sfx("extra"); G.banner = { text = "BONUS JET!", t = 2.0 } end
end

local function destroy(e, by_player)
    if not e.alive then return end
    e.alive = false
    local on_water = (e.kind == "ship" or e.kind == "depot" or e.kind == "bridge")
    if e.kind == "bridge" then
        G.bridges_down[e.sec] = true
        G.checkpoint = e.sec
        for k = -1, 1 do explode(e.x + k * 3.4 + rr(-0.4, 0.4), 1.0, e.z + rr(-0.3, 0.3), 1.3, k == 0) end
        burst(vec3(0, 1.2, e.z), { count = 260, c0 = vec4(1.0, 0.7, 0.3, 1), c1 = vec4(0.5, 0.1, 0.02, 0), smin = 0.1, smax = 0.35, lmin = 0.4, lmax = 1.2, spread = 18, radius = 4.5, grav = vec3(0, 2, 0), drag = 1.5 })
        sfx("bigboom"); sfx("bridge")
        G.shake = 1.2
        G.bridge_count = G.bridge_count + 1
        G.banner = { text = string.format("BRIDGE %d DOWN", G.bridge_count), t = 1.8 }
    else
        explode(e.x, e.y + (e.kind == "ship" and 0.5 or 0.2), e.z, e.kind == "ship" and 1.2 or 1.0, on_water)
        sfx("explode")
    end
    if by_player then award(e.pts) end
    e.dead = true
end

local function hit_test(e, x, z, rx, rz)
    return abs(e.x - x) < e.hx + rx and abs(e.z - z) < e.hz + rz
end
-- player crash hitboxes are ~63% of the visual size (forgiving near-misses); missiles keep full boxes
local HB = 0.63
local P_RX, P_RZ = 0.85 * HB, 0.9 * HB          -- player half extents (were 0.85 / 0.9)
local function crash_test(e, x, z)
    return abs(e.x - x) < e.hx * HB + P_RX and abs(e.z - z) < e.hz * HB + P_RZ
end

local function player_die(reason)
    if not P.alive then return end
    P.alive = false; P.dead_t = 0
    explode(P.x, ALT, P.z, 1.6, not is_land(P.x, P.z))
    release(P.it); P.it = nil
    sfx("crash")
    G.shake = 1.4
    G.lives = G.lives - 1
    G.banner = { text = reason or "", t = 2.0 }
    for i = #MIS, 1, -1 do kill_missile(i) end
    eset(EM.exhaust, "spawn_rate", 0); eset(EM.heat, "spawn_rate", 0); eset(EM.spray, "spawn_rate", 0)
    lights.set_point_light(LT.engine, HIDE, vec3(1, 1, 1), 0, 1)
end

local function spawn_player(sec)
    clear_rows()
    for i = #FX, 1, -1 do release(FX[i].it); FX[i] = nil end
    P.x, P.z, P.vx, P.spd, P.roll, P.fuel = 0, start_z(sec), 0, SPD_CRUISE, 0, 1
    P.ax, P.yaw = 0, 0
    P.alive, P.inv, P.fire_cd = true, 1.5, 0
    if not P.it then P.it = take("jet") end
    place(P.it, P.x, ALT, P.z, 0, 1)
    CAMS.x, CAMS.z, CAMS.lx = 0, P.z, 0
    ensure_rows(P.z)
    eset(EM.exhaust, "spawn_rate", 160 * pscale()); eset(EM.heat, "spawn_rate", 60 * pscale()); eset(EM.spray, "spawn_rate", 140 * pscale())
    G.low_beep = 0
end

---------------------------------------------------------------- per-frame player update
local function update_player(dt, auto)
    local left = held("Left", "A"); local right = held("Right", "D")
    local up = held("Up", "W"); local down = held("Down", "S")
    local fire = held("Space", "Z", "J", "X")
    if auto then
        -- attract-mode autopilot: steer to the middle of the nearest open channel ahead
        local hw, iw = river_at(P.z - 7)
        local tx = 0
        if iw > 0.05 then tx = (P.x >= 0 and 1 or -1) * (iw + hw) * 0.5 end
        for _, e in ipairs(ENT) do
            if e.alive and e.kind ~= "bridge" and e.z < P.z and e.z > P.z - 9 and abs(e.x - tx) < e.hx + 1.4 then
                tx = tx + ((e.x > tx) and -1 or 1) * 1.5
            end
        end
        left, right = tx < P.x - 0.35, tx > P.x + 0.35
        up, down = false, false
        fire = false
        for _, e in ipairs(ENT) do
            if e.alive and e.kind ~= "depot" and e.z < P.z and e.z > P.z - 30 and abs(e.x - P.x) < e.hx then fire = true end
        end
        if P.fuel < 0.35 then
            for _, e in ipairs(ENT) do
                if e.alive and e.kind == "depot" and e.z < P.z and e.z > P.z - 25 then left, right = e.x < P.x - 0.3, e.x > P.x + 0.3 end
            end
        end
    end
    local ax = (right and 1 or 0) - (left and 1 or 0)
    -- eased lateral motion: smoothed input -> acceleration-limited velocity (no instant snaps)
    P.ax = damp(P.ax or 0, ax, 7, dt)
    local tv = P.ax * STEER
    local dv = tv - P.vx
    local acc = STEER_ACC * (ax == 0 and 1.25 or 1.0) * dt
    if dv > acc then dv = acc elseif dv < -acc then dv = -acc end
    P.vx = damp(P.vx + dv, tv, 1.5, dt)
    P.x = P.x + P.vx * dt
    local target = up and SPD_MAX or (down and SPD_MIN or SPD_CRUISE)
    P.spd = damp(P.spd, target, 2.6, dt)
    P.z = P.z - P.spd * dt
    P.roll = damp(P.roll, -P.vx / STEER * 32, 5, dt)   -- visual bank, eased
    P.yaw = damp(P.yaw or 0, -P.vx / STEER * 6, 4, dt)
    P.pitch = damp(P.pitch, (P.spd - SPD_CRUISE) * -0.5, 4, dt)
    P.fire_cd = max(0, P.fire_cd - dt)
    if fire then fire_missile() end
    P.inv = max(0, P.inv - dt)

    -- fuel
    local refuel = false
    for _, e in ipairs(ENT) do
        if e.alive and e.kind == "depot" and hit_test(e, P.x, P.z, 0.7, 0.9) then refuel = true; G.refuel_x, G.refuel_z = e.x, e.z end
    end
    if refuel then
        local was = P.fuel
        P.fuel = min(1, P.fuel + FUEL_FILL * dt)
        G.refuel_tick = (G.refuel_tick or 0) - dt
        if G.refuel_tick <= 0 and P.fuel < 1 then sfx("refuel"); G.refuel_tick = 0.11 end
        if was < 1 and P.fuel >= 1 then sfx("full") end
        eset(EM.refuel, "position", vec3(P.x, ALT - 0.4, P.z)); eset(EM.refuel, "spawn_rate", 160 * pscale())
        lights.set_point_light(LT.depot, vec3(G.refuel_x, 2.2, G.refuel_z), vec3(0.3, 1.0, 0.45), 10 + 4 * sin(G.t * 30), 8)
    else
        eset(EM.refuel, "spawn_rate", 0)
        lights.set_point_light(LT.depot, HIDE, vec3(1, 1, 1), 0, 1)
        if not auto then P.fuel = P.fuel - FUEL_DRAIN * (0.55 + 0.45 * P.spd / SPD_CRUISE) * dt else P.fuel = max(0.5, P.fuel - FUEL_DRAIN * dt) end
    end
    if P.fuel < 0.25 and P.fuel > 0 then
        G.low_beep = (G.low_beep or 0) - dt
        if G.low_beep <= 0 then sfx("lowfuel"); G.low_beep = 0.9 end
    end
    if P.fuel <= 0 then P.fuel = 0; player_die("OUT OF FUEL"); return end

    -- collisions: banks / island
    -- banks / island: probes at 63% of the old wing/nose offsets and a margin that tucks the
    -- terrain edge slightly inside the visible bank
    if is_land(P.x - 0.75 * HB, P.z, -0.12) or is_land(P.x + 0.75 * HB, P.z, -0.12) or is_land(P.x, P.z - 0.9 * HB, -0.12) then
        if auto then P.x = damp(P.x, 0, 3, dt) else player_die("CRASHED"); return end
    end
    for _, e in ipairs(ENT) do
        if e.alive and e.kind ~= "depot" and P.inv <= 0 and crash_test(e, P.x, P.z) then
            if e.kind == "bridge" then
                if auto then destroy(e, false) else destroy(e, false); player_die("HIT THE BRIDGE"); return end
            else
                destroy(e, true); if not auto then player_die("COLLISION"); return end
            end
        end
    end

    -- visuals
    place(P.it, P.x, ALT + 0.05 * sin(G.t * 2.3), P.z, 0, 1)
    P.it.root:set_rotation(vec3(P.pitch, P.yaw or 0, P.roll))
    local nz = P.z + 1.2
    eset(EM.exhaust, "position", vec3(P.x, ALT, nz)); eset(EM.exhaust, "velocity", vec3(-P.vx * 0.3, 0.1, 5 + (P.spd - SPD_CRUISE) * 0.3))
    eset(EM.heat, "position", vec3(P.x, ALT, nz + 0.4))
    eset(EM.spray, "position", vec3(P.x, 0.05, P.z + 0.8))
    eset(EM.spray, "spawn_rate", (110 + 6 * (P.spd - SPD_CRUISE)) * pscale())
    local boost = (P.spd - SPD_MIN) / (SPD_MAX - SPD_MIN)
    lights.set_point_light(LT.engine, vec3(P.x, ALT + 0.2, nz + 0.6), vec3(1.0, 0.55, 0.22), 6 + 7 * boost + 1.2 * sin(G.t * 40), 7)
    temis("jet_glow", vec3(10 + 10 * boost, 4.5 + 3 * boost, 1.2 + boost))
end

---------------------------------------------------------------- missiles
local function update_missiles(dt)
    local lit = false
    for i = #MIS, 1, -1 do
        local m = MIS[i]
        m.t = m.t + dt
        local step = (P.spd + 48) * dt
        local hit = nil
        -- swept test in two halves for fast missiles
        for s = 1, 2 do
            m.z = m.z - step * 0.5
            for _, e in ipairs(ENT) do
                if e.alive and hit_test(e, m.x, m.z, 0.15, 0.4) and (e.kind ~= "ejet" or true) then hit = e; break end
            end
            if hit then break end
        end
        place(m.it, m.x, m.y, m.z, 0, 1.4)
        if m.slot then eset(EM.trail[m.slot], "position", vec3(m.x, m.y, m.z + 0.5)) end
        if not lit then lights.set_point_light(LT.missile, vec3(m.x, m.y + 0.3, m.z + 0.4), vec3(1.0, 0.75, 0.4), 6, 6); lit = true end
        if hit then
            destroy(hit, true); kill_missile(i)
        elseif is_land(m.x, m.z, -0.4) then
            burst(vec3(m.x, 0.7, m.z), { count = 40, c0 = vec4(0.7, 0.6, 0.45, 1), c1 = vec4(0.4, 0.35, 0.3, 0), smin = 0.05, smax = 0.16, spread = 7, vel = vec3(0, 3, 0) })
            burst(vec3(m.x, 0.7, m.z), { count = 25, c0 = vec4(1, 0.8, 0.4, 1), c1 = vec4(1, 0.3, 0, 0), smin = 0.03, smax = 0.07, spread = 10, lmax = 0.4 })
            flash(vec3(m.x, 1.2, m.z), vec3(1, 0.7, 0.35), 12, 0.25, 6)
            kill_missile(i)
        elseif m.z < P.z - 46 then
            kill_missile(i)
        end
    end
    if not lit then lights.set_point_light(LT.missile, HIDE, vec3(1, 1, 1), 0, 1) end
end

---------------------------------------------------------------- enemies
local function update_entities(dt)
    local wi = 1
    local bl = 1
    for _, e in ipairs(ENT) do
        if not e.alive then goto cont end
        e.t = e.t + dt
        if e.kind == "ship" or e.kind == "heli" then
            if not e.active and e.z > P.z - 26 and e.wake_p then e.active = true end
            if e.active then
                local nx = e.x + e.dir * e.speed * dt
                local edge_x = nx + e.dir * (e.hx + 0.25)
                if is_land(edge_x, e.z) or is_land(edge_x, e.z - e.hz) or is_land(edge_x, e.z + e.hz) then e.dir = -e.dir
                else e.x = nx end
            end
            local yaw = (e.dir > 0) and -PI / 2 or PI / 2
            if e.kind == "heli" then
                local bob = 0.12 * sin(e.t * 2.2)
                place(e.it, e.x, e.y + bob, e.z, yaw, 1)
                e.it.root:set_rotation(vec3(e.active and 9 or 0, yaw * DEG, 4 * sin(e.t * 1.7)))
                e.it.kids.heli_rotor:set_rotation(vec3(0, (e.t * 1500) % 360, 0))
                e.it.kids.heli_trotor:set_position(vec3(0.1, 0.62, 1.78)); e.it.kids.heli_trotor:set_rotation(vec3((e.t * 2400) % 360, 0, 0))
            else
                place(e.it, e.x, e.y + 0.03 * sin(e.t * 1.6), e.z, yaw, 1)
                e.it.root:set_rotation(vec3(1.2 * sin(e.t * 1.3), yaw * DEG, 1.5 * sin(e.t * 1.1)))
            end
            if wi <= #EM.wake and e.z > P.z - 34 and e.z < P.z + 8 then
                local wy = (e.kind == "heli") and 0.05 or 0.1
                eset(EM.wake[wi], "position", vec3(e.x - e.dir * (e.kind == "ship" and 1.9 or 0), wy, e.z))
                local rate = (e.kind == "heli") and 90 or (e.active and 120 or 30)
                eset(EM.wake[wi], "spawn_rate", rate * pscale())
                eset(EM.wake[wi], "spawn_radius", e.kind == "heli" and 1.1 or 0.45)
                eset(EM.wake[wi], "velocity", vec3(-e.dir * (e.active and 1.5 or 0.2), e.kind == "heli" and 0.6 or 1.0, 0))
                wi = wi + 1
            end
        elseif e.kind == "ejet" then
            if e.z > P.z - 30 then e.active = true end
            if e.active then
                e.x = e.x + e.dir * e.speed * dt
                if abs(e.x) > FIELD * 0.7 then e.x = -e.dir * FIELD * 0.65 end
            end
            local yaw = (e.dir > 0) and -PI / 2 or PI / 2
            place(e.it, e.x, e.y, e.z, yaw, 1)
            e.it.root:set_rotation(vec3(0, yaw * DEG, 0))
        elseif e.kind == "depot" then
            place(e.it, e.x, 0.02 * sin(e.t * 1.4), e.z, 0, 1.35)
        elseif e.kind == "bridge" then
            place(e.it, 0, 0, e.z, 0, 1)
            if bl <= 2 and e.z > P.z - 30 and e.z < P.z + 10 then
                lights.set_point_light(LT.bridge[bl], vec3(bl == 1 and -3 or 3, 2.2, e.z), vec3(1.0, 0.8, 0.5), 7, 9); bl = bl + 1
            end
        end
        ::cont::
    end
    for i = wi, #EM.wake do eset(EM.wake[i], "spawn_rate", 0) end
    for i = bl, 2 do lights.set_point_light(LT.bridge[i], HIDE, vec3(1, 1, 1), 0, 1) end
end

---------------------------------------------------------------- camera & water
local function update_camera(dt)
    if G.camdbg then CAM:set_position(G.camdbg[1]); pcall(function() CAM:look_at(G.camdbg[2]) end); return end
    local tx = P.x * 0.55
    CAMS.x = damp(CAMS.x, tx, 3.5, dt)
    CAMS.lx = damp(CAMS.lx, P.x * 0.7, 4.5, dt)
    local boost = clamp((P.spd - SPD_CRUISE) / (SPD_MAX - SPD_CRUISE), -1, 1)
    CAMS.h = damp(CAMS.h or 12.0, 11.5 + 1.6 * boost, 2.5, dt)
    CAMS.back = damp(CAMS.back or 9.5, 9.5 + 1.2 * boost, 2.5, dt)
    if P.alive then CAMS.z = P.z end
    G.shake = max(0, (G.shake or 0) - dt * 1.4)
    local sk = G.shake * G.shake * shscale()
    local sx, sy = (rand() - 0.5) * sk * 1.2, (rand() - 0.5) * sk * 0.8
    CAM:set_position(vec3(CAMS.x + sx, CAMS.h + sy, CAMS.z + CAMS.back))
    pcall(function() CAM:look_at(vec3(CAMS.lx + sx * 0.5, 0, CAMS.z - 6.5)) end)
    -- water snaps to its texture tile (8u) so the ripples stay world-locked, plus a slow downstream drift
    local flow = (G.t * 1.1) % 8
    local wz = floor((CAMS.z - 30) / 8) * 8 + flow
    WATER:set_position(vec3(floor(CAMS.x / 8) * 8, 0, wz))
    eset(EM.pollen, "position", vec3(CAMS.x, 2.5, CAMS.z - 10))
end

---------------------------------------------------------------- HUD / menus
local UI = { hud = "rr_hud", menu = "rr_menu" }
local NONE = { 0, 0, 0, 0 }
local function col(r, g, b, a) return { r, g, b, a or 1 } end
local function surf()
    local s = runtime_ui.get_surface_size()
    local w = (s and (s.w or s.width or s.x or s[1])) or 1280
    local h = (s and (s.h or s.height or s.y or s[2])) or 720
    return w, h
end
local function quad(screen, id, x, y, w, h, o)
    o = o or {}
    o.x, o.y, o.w, o.h = x, y, w, h
    o.style = o.style or "text"
    if o.style == "text" then o.fill = o.fill or NONE; o.border = o.border or NONE end
    o.no_input = not o.input; o.input = nil; o.bring_to_front = true
    pcall(runtime_ui.set_quad, screen, id, o)
end
local function hide_quad(screen, id) quad(screen, id, -10, -10, 1, 1, { style = "text", title = "" }) end

local function draw_hud()
    local sw, sh = surf(); local k = sw / 1280
    local function s(v) return v * k end
    runtime_ui.show(UI.hud); runtime_ui.set_screen_overlay(UI.hud, true)
    -- top bar
    quad(UI.hud, "topbar", s(16), s(12), sw - s(32), s(52), { style = "panel", fill = col(0.02, 0.04, 0.08, 0.55), border = col(1.0, 0.75, 0.2, 0.7), corner_radius = s(14) })
    quad(UI.hud, "score", s(34), s(12), s(380), s(52), { title = string.format("SCORE  %06d", G.score), text_color = col(1.0, 0.85, 0.3), font_scale = 1.7 * k, align_h = "left" })
    quad(UI.hud, "bridge", sw / 2 - s(160), s(12), s(320), s(52), { title = string.format("BRIDGE  %d", G.bridge_count), text_color = col(0.55, 0.9, 1.0), font_scale = 1.5 * k, align_h = "center" })
    quad(UI.hud, "lives", sw - s(400), s(12), s(366), s(52), { title = string.format("JETS  x%d", max(0, G.lives)), text_color = col(1.0, 0.55, 0.4), font_scale = 1.6 * k, align_h = "right" })
    -- fuel gauge (bottom centre): E . 1/2 . F with a coloured bar
    local gw, gh = s(460), s(30)
    local gx, gy = sw / 2 - gw / 2, sh - s(66)
    quad(UI.hud, "fuelbg", gx - s(64), gy - s(12), gw + s(128), gh + s(24), { style = "panel", fill = col(0.02, 0.03, 0.06, 0.6), border = col(1.0, 0.75, 0.2, 0.7), corner_radius = s(14) })
    quad(UI.hud, "fuelE", gx - s(56), gy, s(44), gh, { title = "E", text_color = col(1.0, 0.35, 0.3), font_scale = 1.5 * k, align_h = "center" })
    quad(UI.hud, "fuelF", gx + gw + s(12), gy, s(44), gh, { title = "F", text_color = col(0.45, 1.0, 0.55), font_scale = 1.5 * k, align_h = "center" })
    quad(UI.hud, "fueltrack", gx, gy + s(4), gw, gh - s(8), { style = "panel", fill = col(0.1, 0.1, 0.12, 0.85), border = col(0.4, 0.4, 0.45, 0.8), corner_radius = s(6) })
    local f = clamp(P.fuel, 0, 1)
    local c = (f > 0.5) and col(lerp(1.0, 0.3, (f - 0.5) * 2), 0.95, 0.35) or col(1.0, lerp(0.2, 0.95, f * 2), 0.2)
    local blink = (f < 0.25) and (0.55 + 0.45 * sin(G.t * 14)) or 1
    c[4] = blink
    quad(UI.hud, "fuelbar", gx + s(3), gy + s(7), max(s(2), (gw - s(6)) * f), gh - s(14), { style = "panel", fill = c, border = NONE, corner_radius = s(4) })
    quad(UI.hud, "fuelhalf", gx + gw / 2 - s(1), gy, s(2), gh, { style = "panel", fill = col(1, 1, 1, 0.6), border = NONE })
    quad(UI.hud, "fueltxt", gx, gy - s(34), gw, s(24), { title = (f < 0.25) and "LOW FUEL" or "FUEL", text_color = (f < 0.25) and col(1, 0.3, 0.25, blink) or col(0.9, 0.9, 0.95, 0.8), font_scale = 1.0 * k, align_h = "center" })
    -- speed indicator (left bottom)
    local sp = (P.spd - SPD_MIN) / (SPD_MAX - SPD_MIN)
    quad(UI.hud, "spdbg", s(24), sh - s(78), s(240), s(54), { style = "panel", fill = col(0.02, 0.03, 0.06, 0.55), border = col(0.4, 0.8, 1.0, 0.5), corner_radius = s(12) })
    quad(UI.hud, "spdtxt", s(36), sh - s(78), s(220), s(28), { title = string.format("SPEED  %d KT", floor(P.spd * 22)), text_color = col(0.6, 0.9, 1.0), font_scale = 1.0 * k, align_h = "left" })
    quad(UI.hud, "spdbar", s(38), sh - s(44), max(s(2), s(210) * sp), s(10), { style = "panel", fill = col(0.4, 0.85, 1.0, 0.9), border = NONE, corner_radius = s(4) })
    quad(UI.hud, "hint", sw - s(420), sh - s(52), s(400), s(28), { title = "ARROWS steer/throttle   SPACE fire   ESC pause", text_color = col(0.8, 0.85, 0.95, 0.6), font_scale = 0.9 * k, align_h = "right" })
    -- banner
    if G.banner and G.banner.t > 0 and G.banner.text ~= "" then
        local a = clamp(G.banner.t * 2, 0, 1)
        quad(UI.hud, "banner", sw / 2 - s(400), sh * 0.36, s(800), s(70), { title = G.banner.text, text_color = col(1.0, 0.85, 0.35, a), font_scale = 3.0 * k, align_h = "center" })
    else hide_quad(UI.hud, "banner") end
end

local MBTN = { n = 0, sel = 1 }
-- index of the clicked menu button (hover highlights); nil if none
local function menu_clicked()
    for i = 1, MBTN.n do
        local ok, st = pcall(runtime_ui.get_state, UI.menu, "mb" .. i)
        if ok and st then
            if st.hovered then MBTN.sel = i end
            if st.clicked then return i end
        end
    end
end
local function menu_card(title, sub, lines, foot, tc, btns)
    if G.nomenu then runtime_ui.hide(UI.menu); return end
    local sw, sh = surf(); local k = sw / 1280
    local function s(v) return v * k end
    runtime_ui.show(UI.menu); runtime_ui.set_screen_overlay(UI.menu, true)
    quad(UI.menu, "dim", 0, 0, sw, sh, { style = "panel", fill = col(0.01, 0.02, 0.05, 0.38), border = NONE })
    quad(UI.menu, "logo", sw / 2 - s(500), s(92), s(1000), s(110), { title = title, text_color = tc or col(1.0, 0.78, 0.18), font_scale = 5.6 * k, align_h = "center" })
    quad(UI.menu, "sub", sw / 2 - s(500), s(205), s(1000), s(44), { title = sub, text_color = col(0.55, 0.9, 1.0), font_scale = 1.6 * k, align_h = "center" })
    if lines then
        quad(UI.menu, "card", sw / 2 - s(330), s(280), s(660), s(232), { style = "panel", fill = col(0.02, 0.04, 0.08, 0.72), border = col(1.0, 0.75, 0.2, 0.85), corner_radius = s(18),
            title = lines[1], text_color = col(1.0, 0.85, 0.4), font_scale = 1.25 * k, body = lines[2], align_h = "center" })
    else hide_quad(UI.menu, "card") end
    local pulse = 0.65 + 0.35 * sin(G.t * 3.2)
    -- mouse-clickable buttons
    btns = btns or {}
    if MBTN.n ~= #btns then MBTN.sel = 1 end
    MBTN.n = #btns
    local y0 = lines and s(526) or s(290)
    for i = 1, 4 do
        local b = btns[i]
        if b then
            local on = (i == MBTN.sel)
            quad(UI.menu, "mb" .. i, sw / 2 - s(190), y0 + (i - 1) * s(56), s(380), s(48), { style = "text", label = b, title = b, input = true, z = 20,
                fill = on and col(0.35, 0.25, 0.05, 0.8) or col(0.02, 0.04, 0.08, 0.7), border = on and col(1.0, 0.8, 0.3, 1) or col(1.0, 0.75, 0.2, 0.45),
                corner_radius = s(12), text_color = on and col(1.0, 0.95, 0.7, 1) or col(0.85, 0.88, 0.95, 0.9), font_scale = 1.35 * k, align_h = "center", align_v = "middle" })
        else hide_quad(UI.menu, "mb" .. i) end
    end
    hide_quad(UI.menu, "start")
    quad(UI.menu, "set", sw / 2 - s(450), y0 + #btns * s(56) + s(6), s(900), s(32), { title = foot[2] or "", text_color = col(0.7, 0.78, 0.9, 0.85), font_scale = 1.0 * k, align_h = "center" })
end
local function show_title()
    menu_card("RIVER RAID", "R E M I X", { "MISSION BRIEFING",
        "Fly up the river and destroy the bridges.\nTankers 30   Helicopters 60   Fuel depots 80   Jets 100   Bridges 500\nFly over FUEL depots to refuel - shoot them only if you must!\nDon't touch the banks. Every bridge is a checkpoint.\nBonus jet every 10,000 points." },
        { "PRESS ENTER / SPACE TO FLY", "ENTER fly   O settings   ARROWS / WASD steer & throttle   SPACE fire" }, nil, { "FLY", "Jev", "SETTINGS" })
end
local function show_pause()
    menu_card("PAUSED", string.format("SCORE  %06d", G.score), nil, { "ESC  RESUME", "ESC resume   O settings   R restart   Q quit" }, col(1, 0.9, 0.5), { "RESUME", "SETTINGS", "RESTART", "QUIT TO TITLE" })
end
local function show_gameover()
    menu_card("GAME OVER", string.format("SCORE  %06d      BRIDGES  %d      BEST  %06d", G.final and G.final.score or 0, G.final and G.final.bridges or 0, G.best or 0), nil,
        { "PRESS ENTER TO FLY AGAIN", "ENTER fly again   O settings   Q title" }, col(1, 0.35, 0.25), { "FLY AGAIN", "SETTINGS", "TITLE" })
end

---------------------------------------------------------------- settings menu (shared module)
local function load_settings_menu()
    local ok, mod = pcall(function() return load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")() end)
    if not ok or not mod then pe_log("[RR] settings_menu missing: " .. tostring(mod)); return end
    SET = mod.new({
        title = "SETTINGS", file = "Save/settings.cfg",
        click = function() sfx("click") end, music = false,
        defaults = { master = 0.5, sfx = 0.85 },
        theme = { accent = { 1.0, 0.75, 0.2, 1 }, accent2 = { 0.4, 0.85, 1.0, 1 } },
    })
    SET:apply()
    _G.RRSET = SET
end

---------------------------------------------------------------- game flow
local function load_best()
    local ok, s = pcall(fs.read, "Save/best.txt")
    G.best = (ok and tonumber(s)) or 0
end
local function save_best()
    if jev and jev:assisted() then
        return
    end
    if G.score > (G.best or 0) then
        G.best = G.score
        pcall(fs.write, "Save/best.txt", tostring(G.best))
    end
end
local function new_game(attract, seed)
    G.vkeys = {}
    G.score, G.lives, G.bridge_count, G.checkpoint = 0, 4, 0, 0
    G.bridges_down = {}
    G.seed = seed or 0
    G.banner = nil
    for i = #MIS, 1, -1 do
        kill_missile(i)
    end
    spawn_player(0)
    if not attract then
        G.state = "play"
        runtime_ui.hide(UI.menu)
        sfx("start")
        G.banner = { text = "GO!", t = 1.2 }
    end
end
_G.rr_start = function()
    jev:begin_human()
    new_game(false)
end

local function init()
    math.randomseed(1982)
    setup_render()
    setup_materials()
    setup_lights()
    setup_emitters()
    CAM = scene.get_cameras()[1]
    pcall(function() CAM:set_fov(64) end)
    WATER = clone("water", vec3(0, 0, 0))
    -- prewarm pools so gameplay never creates nodes mid-flight
    prewarm("shore", 150); prewarm("land", 110); prewarm("rockonly", 24)
    prewarm("pine", 80); prewarm("leaf", 60); prewarm("boulder", 30); prewarm("house", 26); prewarm("road", 30)
    prewarm("ship", 8); prewarm("heli", 8); prewarm("ejet", 3); prewarm("depot", 6); prewarm("bridge", 2)
    prewarm("fire", 24); prewarm("core", 12); prewarm("smoke", 24); prewarm("ring", 8); prewarm("debris", 50); prewarm("missile", 3)
    for _, n in ipairs({ "jet_body", "ejet_body", "heli_body", "ship_hull", "depot_base", "bridge_road", "shore_grass", "land", "water" }) do
        local t = tpl(n); if t then t.node:set_position(HIDE) end
    end
    load_settings_menu()
    load_best()
    new_game(true)
    G.state = "title"
    show_title()
    pe_log("[RiverRaid] ready")
end

local function step_world(dt, auto)
    if P.alive then update_player(dt, auto) else P.dead_t = P.dead_t + dt end
    update_missiles(dt)
    update_entities(dt)
    ensure_rows(P.alive and P.z or CAMS.z)
    update_fx(dt)
    update_flashes(dt)
    update_camera(dt)
    -- blinking beacons
    temis("heli_glow", (sin(G.t * 9) > 0) and vec3(16, 0.8, 0.3) or vec3(0.6, 0.02, 0.01))
    temis("depot_glow", vec3(1.5, 8 + 4 * sin(G.t * 5), 2.5))
    if G.banner then G.banner.t = G.banner.t - dt end
end

local function update(dt)
    if dt > 0.05 then dt = 0.05 end
    flush_mats()
    G.t = G.t + dt
    jev:tick(dt)
    human_edge()
    poll_keys()
    if SET and SET:update(dt) then latch_keys(); return end

    if G.state == "title" or G.state == "gameover" then
        step_world(dt, true)
        if not P.alive and P.dead_t > 1.5 then spawn_player(G.checkpoint or 0) end
        local c = menu_clicked()
        if pressed("Up", "W") then
            MBTN.sel = (MBTN.sel - 2) % max(1, MBTN.n) + 1
        elseif pressed("Down", "S") then
            MBTN.sel = MBTN.sel % max(1, MBTN.n) + 1
        end
        if pressed("Return") then
            c = MBTN.sel
        end

        local open_settings = pressed("O")
        if G.state == "title" then
            open_settings = open_settings or c == 3
        else
            open_settings = open_settings or c == 2
        end

        if G.state == "title" and c == 2 then
            local ok = jev:start()
            if not ok then
                local message = jev:error() or "Jev failed to start"
                G.banner = { text = message, t = 6 }
                pe_log("[RiverRaid] " .. message)
            end
        elseif open_settings and SET then
            runtime_ui.hide(UI.menu)
            local st = G.state
            SET:open(function()
                if st == "title" then
                    show_title()
                else
                    show_gameover()
                end
            end)
        elseif c == 1 or pressed("Space") then
            MBTN.sel = 1
            jev:begin_human()
            new_game(false)
        elseif G.state == "gameover" and (pressed("Q") or c == 3) then
            jev:begin_human()
            G.state = "title"
            new_game(true)
            G.state = "title"
        end
        if G.state == "title" then show_title() elseif G.state == "gameover" then show_gameover() end
        runtime_ui.hide(UI.hud)
        latch_keys(); return
    end

    if G.state == "pause" then
        local c = menu_clicked()
        if pressed("Up", "W") then MBTN.sel = (MBTN.sel - 2) % 4 + 1 elseif pressed("Down", "S") then MBTN.sel = MBTN.sel % 4 + 1 end
        if pressed("Return") then c = MBTN.sel end
        if pressed("Escape", "P") or c == 1 then G.state = "play"; runtime_ui.hide(UI.menu)
        elseif (pressed("O") or c == 2) and SET then runtime_ui.hide(UI.menu); SET:open(function() show_pause() end)
        elseif pressed("R") or c == 3 then
            jev:begin_human()
            new_game(false)
        elseif pressed("Q") or c == 4 then
            save_best()
            jev:begin_human()
            new_game(true)
            G.state = "title"
        else show_pause() end
        latch_keys(); return
    end

    -- play
    if pressed("Escape", "P") then G.state = "pause"; MBTN.sel = 1; show_pause(); latch_keys(); return end
    if pressed("M") and SET then SET:toggle_mute() end
    step_world(dt, false)
    if not P.alive and P.dead_t > 2.3 then
        if G.lives > 0 then
            spawn_player(G.checkpoint or 0)
            G.banner = { text = string.format("JETS LEFT  %d", G.lives), t = 1.4 }
        else
            save_best()
            G.final = {
                score = G.score,
                bridges = G.bridge_count,
                x = P.x,
                speed = P.spd,
                fuel = P.fuel,
                lives = 0,
                obstacle = nearest_obstacle(),
            }
            G.state = "gameover"; sfx("over")
            new_game(true); G.state = "gameover"
        end
    end
    draw_hud()
    latch_keys()
end

nearest_obstacle = function()
    local kind = "none"
    local x = 0
    local ahead = 40
    local w = 0

    for i = 1, #ENT do
        local e = ENT[i]
        local ahead_of = e.alive and e.z <= P.z + 0.5
        if ahead_of then
            local dz = P.z - e.z
            if dz < 0 then
                dz = 0
            end
            if dz < ahead then
                ahead = dz
                kind = e.kind
                x = e.x
                w = e.hx or 0
            end
        end
    end

    for dist = 0, ahead - 0.01, 2 do
        if is_land(P.x, P.z - dist, 0) then
            local hw, iw = river_at(P.z - dist)
            local on_island = iw > 0.05 and abs(P.x) <= iw + 0.05
            if on_island then
                kind = "island"
                x = 0
                w = iw
            else
                kind = "bank"
                w = 0
                if P.x >= 0 then
                    x = hw
                else
                    x = -hw
                end
            end
            ahead = dist
            break
        end
    end

    if kind == "none" then
        ahead = 0
    end

    return { kind = kind, x = x, ahead = ahead, w = w }
end

local HOLDS = {
    left = { Left = true, Space = true },
    right = { Right = true, Space = true },
    faster = { Up = true, Space = true },
}

local function apply_hold(id)
    local hold = HOLDS[id]
    if not hold then
        return
    end

    G.vkeys = {}
    G.vkeys.Left = hold.Left
    G.vkeys.Right = hold.Right
    G.vkeys.Up = hold.Up
    G.vkeys.Down = hold.Down
    G.vkeys.Space = hold.Space
end

local jev_source = assert(fs.read("Scripts/jev_auto.lua"), "Missing Scripts/jev_auto.lua")
local JevAuto = assert(load(jev_source, "@Scripts/jev_auto.lua", "t", _ENV))()
jev = JevAuto.attach({
    port = 9110,
    id = "river-raid-remix",
    description = "Fly up the river. The offered action steers off the banks and islands, or speeds up when the river is clear, and the gun keeps firing. Prefer the higher action score.",
    playing = function()
        return G.state == "play"
    end,
    terminal = function()
        return G.state == "gameover"
    end,
    score = function()
        if G.state == "gameover" and G.final then
            return G.final.score or 0
        end
        return G.score or 0
    end,
    human_edge = human_edge,
    observe = function()
        if G.state == "gameover" and G.final then
            return {
                x = G.final.x or 0,
                speed = G.final.speed or 0,
                obstacle = G.final.obstacle or { kind = "none", x = 0, ahead = 0, w = 0 },
                fuel = G.final.fuel or 0,
                lives = G.final.lives or 0,
                score = G.final.score or 0,
            }
        end
        return {
            x = P.x or 0,
            speed = P.spd or 0,
            obstacle = nearest_obstacle(),
            fuel = P.fuel or 0,
            lives = G.lives or 0,
            score = G.score or 0,
        }
    end,
    actions = function()
        local ob = nearest_obstacle()
        local x = P.x or 0
        if ob and ob.kind ~= "none" and (ob.ahead or 0) < 22 then
            local go_left = ob.x >= 0
            if ob.kind == "island" then
                go_left = x >= 0
            end
            if go_left then
                return { { id = "left", description = "Steer left off the obstacle. The gun keeps firing.", score = ob.ahead or 1 } }
            end
            return { { id = "right", description = "Steer right off the obstacle. The gun keeps firing.", score = ob.ahead or 1 } }
        end
        if x > 1.2 then
            return { { id = "left", description = "Steer back toward the river. The gun keeps firing.", score = x } }
        end
        if x < -1.2 then
            return { { id = "right", description = "Steer back toward the river. The gun keeps firing.", score = -x } }
        end
        return { { id = "faster", description = "The river is clear. Speed up and fire.", score = 1 } }
    end,
    apply = apply_hold,
    reset = function(seed)
        math.randomseed(seed or 0)
        new_game(false, seed or 0)
    end,
    on_human = function()
        G.vkeys = {}
    end,
})

_G.RRD = { spawn = spawn_player, ensure = ensure_rows, river_at = river_at, P = P, ROWS = ROWS, ENT = ENT, clear_rows = clear_rows, POOL = POOL, TPL = TPL, take = take, place = place, CAMS = CAMS }
hooks { init = init, update = update }
