-- GATEBREAKER SQUAD (Phasma Engine, Lua)
-- A gate shooter: your squad holds the bottom of a long bridge and fires forward on its own. Steer left/right to
-- shoot gates up (or overload trap gates), smash crates for guns, crack containers to free allies, call airstrikes
-- and stop the mutant horde and its bosses before they reach you.
-- World: Y up, metres. Lane x (+ = screen right) maps to world X = -x; things ahead of the squad are at +Z.
-- Fixed 60 Hz simulation (04_sim is engine-agnostic and also runs headless in tools/simtest.py).
local PI = math.pi
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
math.randomseed(20261029)
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local function round(v) return floor(v + 0.5) end
local G = { state = "boot", t = 0, test = {} }
_G.GB = G

------------------------------------------------------------------ deferred materials (engine quirk: replay writes)
local _mset, _mtex, _mds = material.set, material.set_texture, material.set_double_sided
local mat_q = {}
local function qpush(f) mat_q[#mat_q + 1] = { f = f, n = 0 } end
local function mset(n, k, v) pcall(_mset, n, k, v); qpush(function() pcall(_mset, n, k, v) end) end
local function mtex(n, k, v) pcall(_mtex, n, k, v); qpush(function() pcall(_mtex, n, k, v) end) end
local function mrem(n, k) pcall(material.remove_texture, n, k); qpush(function() pcall(material.remove_texture, n, k) end) end
local function flush_mats()   -- replay in queue order so later writes win
    if #mat_q == 0 then return end
    local keep = {}
    for i = 1, #mat_q do
        local q = mat_q[i]; q.n = q.n + 1
        if q.n == 2 or q.n == 6 then q.f() end
        if q.n < 6 then keep[#keep + 1] = q end
    end
    mat_q = keep
end
local function paint(n, base, emis, rough, metal, alpha)
    if not n then return end
    mset(n, "base_color", vec4(base[1], base[2], base[3], alpha or 1))
    mset(n, "emissive", vec3(emis[1], emis[2], emis[3]))
    mset(n, "roughness", rough or 0.5)
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

------------------------------------------------------------------ camera + projection
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1920, surf.height or 1080
local cam = (get_camera and get_camera()) or scene.get_cameras()[1]
local VFOV = math.rad(54)
local function set_vfov(v)
    VFOV = v
    pcall(function() cam:set_fov(math.deg(2 * math.atan(math.tan(VFOV / 2) * SW / SH))) end)
end
set_vfov(VFOV)
pcall(function() cam:set_far_plane(4000) end)
pcall(function() cam:set_near_plane(0.25) end)
G.cam = { pos = vec3(0, 9.5, -11.5), look = vec3(0, 0.5, 17) }
local function WX(x) return -x end
local function project(x, y, z)
    local c, l = G.cam.pos, G.cam.look
    local fx, fy, fz = l.x - c.x, l.y - c.y, l.z - c.z
    local fl = sqrt(fx * fx + fy * fy + fz * fz); fx, fy, fz = fx / fl, fy / fl, fz / fl
    local rx, rz = -fz, fx; local rl = sqrt(rx * rx + rz * rz); rx, rz = rx / rl, rz / rl
    local ux, uy, uz = -rz * fy, rz * fx - rx * fz, rx * fy
    local dx, dy, dz = x - c.x, y - c.y, z - c.z
    local zc = dx * fx + dy * fy + dz * fz
    if zc < 0.3 then return -9999, -9999, zc end
    local th = math.tan(VFOV / 2)
    -- r = screen right; looking down +Z it is world -X (game code uses lane x = -world X, so +x is screen right)
    return SW / 2 + (dx * rx + dz * rz) / (zc * th) * SH / 2, SH / 2 - (dx * ux + dy * uy + dz * uz) / (zc * th) * SH / 2, zc
end

------------------------------------------------------------------ templates -> clones, pools
local TPL = {}
local function tpl(name)
    if TPL[name] ~= nil then return TPL[name] end
    local n = scene.find_model("T_" .. name)
    if not n then pe_log("[GB] missing template " .. name); TPL[name] = false; return false end
    TPL[name] = { node = n, mesh = n:get_mesh_refs()[1] }
    return TPL[name]
end
local function mesh_of(name) local t = tpl(name); return t and t.mesh end
local seq = 0
local HIDE = vec3(0, -1000, 0)
local function clone(name, pos, scale)
    local t = tpl(name); seq = seq + 1
    local n = scene.add_empty_node(name .. "_c" .. seq)
    if t and t.mesh then n:add_mesh_ref(t.mesh) end
    n:set_position(pos or HIDE)
    if scale then n:set_scale(scale) end
    return n
end
local function tnode(name) local t = tpl(name); return t and t.node end
-- pools: P_get(kind) hands out clones (reused across levels); P_reset hides everything for a rebuild
local POOL = {}
local function P_get(kind)
    local p = POOL[kind]; if not p then p = { n = {}, used = 0 }; POOL[kind] = p end
    p.used = p.used + 1
    local n = p.n[p.used]
    if not n then n = clone(kind); p.n[p.used] = n end
    return n
end
-- per-frame pools: P_begin(kind) ... P_get(kind) ... P_end(kind) hides whatever was not used this frame
local function P_begin(kind) local p = POOL[kind]; if not p then p = { n = {}, used = 0, prev = 0 }; POOL[kind] = p end; p.prev = p.used; p.used = 0 end
local function P_end(kind)
    local p = POOL[kind]; if not p then return end
    for i = p.used + 1, (p.prev or 0) do p.n[i]:set_position(HIDE) end
end
local function P_reset(kinds)
    for k, p in pairs(POOL) do
        if not kinds or kinds[k] then
            for i = 1, #p.n do p.n[i]:set_position(HIDE); p.n[i]:set_rotation(vec3(0, 0, 0)); p.n[i]:set_scale(vec3(1, 1, 1)) end
            p.used = 0
        end
    end
end
-- free-list pools for transient things (units, debris): get/put
local FREE = {}
local function F_get(kind)
    local f = FREE[kind]; if f and #f > 0 then return table.remove(f) end
    return clone(kind)
end
local function F_put(kind, n)
    n:set_position(HIDE)
    local f = FREE[kind]; if not f then f = {}; FREE[kind] = f end
    f[#f + 1] = n
end
local function place(n, x, y, z, sx, sy, sz, ry, rx, rz)
    n:set_position(vec3(x, y, z))
    n:set_scale(vec3(sx or 1, sy or sx or 1, sz or sx or 1))
    n:set_rotation(vec3(rx or 0, ry or 0, rz or 0))
    return n
end

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

------------------------------------------------------------------ input (raw keys, edges, mouse)
local prev = {}
local keyfn = input.is_key_down_raw or input.is_key_pressed
local function held(k) if G.vk and G.vk[k] then return true end local ok, v = pcall(keyfn, k); return ok and v end
local function edge(k) local d = held(k); local p = prev[k]; prev[k] = d; return d and not p end
local function anyedge(...) local r = false; for _, k in ipairs({ ... }) do if edge(k) then r = true end end; return r end
local function anyheld(...) for _, k in ipairs({ ... }) do if held(k) then return true end end; return false end
local MOUSE = { x = 0, y = 0, down = false, pressed = false, released = false, px = 0 }
local function poll_mouse()
    local ok, p = pcall(input.get_mouse_position)
    if ok and p then MOUSE.x = p.x or p[1] or MOUSE.x; MOUSE.y = p.y or p[2] or MOUSE.y end
    if G.vmouse then MOUSE.x, MOUSE.y = G.vmouse.x, G.vmouse.y end
    local ok2, d = pcall(input.is_left_mouse_down)
    d = (ok2 and d) or (G.vmouse and G.vmouse.down) or false
    MOUSE.pressed = d and not MOUSE.down
    MOUSE.released = (not d) and MOUSE.down
    MOUSE.down = d
end

------------------------------------------------------------------ render setup (common/RENDER_SETTINGS.md: TAA on, CAS off, smooth bloom)
local function S(k, v) pcall(settings.set, k, v) end
G.S = S
local ss = scene.add_empty_node("GBSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
S("taa", true); S("cas_sharpening", false); S("fxaa", false); S("motion_blur", false); S("dof", false)
S("hdr", true)
S("bloom", true); S("bloom_strength", 0.48); S("bloom_range", 1.2)
S("tonemapping", true)
S("ssao", true); S("ssao_radius", 0.55); S("ssao_intensity", 1.0)
S("ssr", true)
S("fog", true); S("fog_density", 0.0032); S("fog_start", 70.0)
S("shadows", true); S("shadow_map_size", 2048); S("shadow_distance", 70.0); S("shadow_filter_radius", 1.6)
S("render_scale", 1.0)
S("IBL", true); S("IBL_intensity", 0.9)
S("color_grading", true); S("color_grading_saturation", 1.1); S("color_grading_contrast", 1.06)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "Options", subtitle = "Gatebreaker Squad", file = "Save/settings.cfg", music = true,
    click = function() sfx("click") end, defaults = { master = 0.5 },
    theme = { accent = { 0.2, 0.55, 1, 1 }, accent2 = { 1, 0.72, 0.18, 1 }, panel = { 0.06, 0.09, 0.17, 0.95 }, row = { 0.13, 0.19, 0.33, 0.82 },
        text = { 0.95, 0.97, 1, 1 }, dim = { 0.7, 0.76, 0.88, 1 }, selected_text = { 1, 1, 1, 1 } } })
SET:apply()
local function PS() return SET:particle_scale() end

------------------------------------------------------------------ materials: one shared palette atlas for every character/prop mesh
local NON_PAL = { deck = true, sea = true, floor = true, gpanel_blue = true, gpanel_red = true, gpanel_gold = true, gpanel_grey = true,
    gpanel_orange = true, gpanel_green = true }
local MESHES = { "ally_drone", "amech_body", "amech_leg", "aimdash", "barrel_blue", "barrel_red", "barricade", "beam", "blob", "boat", "bomb", "bridge_canyon",
    "bridge_forest", "bridge_frost", "bridge_harbor", "bridge_volcano", "brute_body", "brute_leg", "buoy", "coin", "container", "container_o", "crate",
    "fly_body", "fly_rotor", "gate_frame", "gol_body", "gol_leg", "heavy", "heli", "heli_rotor", "hero_bruno", "hero_hawke", "hero_juno",
    "hero_nova", "hero_rook", "hero_vex", "hvy_leg", "iceberg", "mflash", "island", "jet", "mech_body", "mech_leg", "mesa", "mtn_autumn", "mtn_desert", "mtn_green",
    "mtn_snow", "mtn_volcano", "orb", "palm", "pellet", "pine", "pine_snow", "ring", "rock", "rock_lava", "rocket", "run_body", "run_leg", "shd_body",
    "shd_body_ns", "sniper", "sol_laser", "sol_leg", "sol_minigun", "sol_rifle", "sol_rocket", "sol_shotgun", "tracer", "tree", "tree_autumn",
    "tree_autumn2", "tur_base", "tur_gun", "vet_laser", "vet_leg", "vet_minigun", "vet_rifle", "vet_rocket", "vet_shotgun", "wasp_body", "wasp_wing" }
G.GATE_RGB = { blue = { .22, .55, 1.0 }, red = { 1.0, .25, .22 }, green = { .25, .9, .4 }, gold = { 1.0, .75, .15 }, grey = { .55, .6, .7 }, orange = { 1.0, .55, .1 } }
local function paint_pal(n, emk)
    mtex(n, "base_color", "Textures/pal.png"); mtex(n, "metallic_roughness", "Textures/pal_mr.png"); mtex(n, "emissive", "Textures/pal_em.png")
    mset(n, "base_color", vec4(1, 1, 1, 1)); mset(n, "emissive", vec3(emk, emk, emk)); mset(n, "roughness", 1.0); mset(n, "metallic", 1.0)
end
local function paint_templates()
    for _, name in ipairs(MESHES) do
        local n = tnode(name)
        if n then paint_pal(n, 1.6) end
    end
    -- glowing bits that should bloom harder
    for _, name in ipairs({ "tracer", "pellet", "beam", "orb", "ring", "mflash" }) do
        local n = tnode(name)
        if n then mrem(n, "emissive"); mrem(n, "base_color"); mrem(n, "metallic_roughness"); mset(n, "roughness", 0.4); mset(n, "metallic", 0.0); mset(n, "emissive", vec3(4, 3, 1.5)); mset(n, "base_color", vec4(1, 0.85, 0.5, 1)) end
    end
    -- glass gate panels: soft gradient, coloured, translucent
    for c, rgb in pairs(G.GATE_RGB) do
        local n = tnode("gpanel_" .. c)
        if n then
            mtex(n, "base_color", "Textures/gate_grad.png"); mtex(n, "emissive", "Textures/gate_grad.png")
            mset(n, "base_color", vec4(rgb[1], rgb[2], rgb[3], 1)); mset(n, "emissive", vec3(rgb[1] * 0.7, rgb[2] * 0.7, rgb[3] * 0.7))
            mset(n, "roughness", 0.12); mset(n, "metallic", 0.0)
            pcall(_mds, n, true)  -- alpha_blend does not render on this build: opaque glowing glass
        end
    end
        local rg = tnode("ring"); if rg then mset(rg, "base_color", vec4(1, 0.3, 0.2, 1)) end
    -- aim cue dashes: dim cool glow (well under the bloom threshold of the tracers)
    local ad = tnode("aimdash")
    if ad then mrem(ad, "emissive"); mrem(ad, "base_color"); mrem(ad, "metallic_roughness"); mset(ad, "roughness", 0.6); mset(ad, "metallic", 0.0); mset(ad, "emissive", vec3(0.8, 1.2, 1.8)); mset(ad, "base_color", vec4(0.55, 0.75, 1, 1)) end
    local dk = tnode("deck")
    if dk then
        mtex(dk, "base_color", "Textures/deck.png"); mtex(dk, "normal", "Textures/deck_n.png")
        mset(dk, "base_color", vec4(1, 1, 1, 1)); mset(dk, "roughness", 0.78); mset(dk, "metallic", 0.0); mset(dk, "emissive", vec3(0, 0, 0))
    end
    local wing = tnode("wasp_wing"); if wing then pcall(_mds, wing, true) end
    for name in pairs(TPL) do local n = tnode(name); if n then n:set_position(HIDE) end end
end
local function weapon_tint(col)
    for _, name in ipairs({ "tracer", "pellet", "mflash" }) do
        local n = tnode(name); if n then mset(n, "emissive", vec3(col[1] * 4.5, col[2] * 4.5, col[3] * 4.5)); mset(n, "base_color", vec4(col[1], col[2], col[3], 1)) end
    end
end
G.weapon_tint = weapon_tint

------------------------------------------------------------------ worlds: sky, sun, ground (sea / canyon floor / lava), scenery, mountains
local WL = {
    harbor = { sky = "harbor.hdr", sun = { vec3(-0.42, -0.72, 0.55), vec3(1, .95, .88), 3.3 }, ibl = 0.9, fog = 0.0030,
        ground = "sea", gy = -7.5, tex = "water_harbor", nrm = "water_n", rough = 0.12, tint = { 1, 1, 1 }, mtn = "mtn_green", bridge = "harbor",
        props = { { "island", 0.55, 1.0, -4.2, 60, 230 }, { "boat", 1.4, 1.8, -7.4, 18, 60 }, { "buoy", 1.0, 1.0, -7.3, 10, 22 }, { "island", 0.4, 0.7, -5, 60, 200 } } },
    canyon = { sky = "canyon.hdr", sun = { vec3(-0.55, -0.62, 0.48), vec3(1, .88, .72), 3.5 }, ibl = 0.82, fog = 0.0026,
        ground = "floor", gy = -38, tex = "canyon", nrm = "floor_n", rough = 0.92, tint = { 1, 1, 1 }, mtn = "mtn_desert", bridge = "canyon",
        props = { { "mesa", 0.7, 1.4, -38, 50, 240 }, { "rock", 2.0, 3.5, -38, 18, 90 }, { "mesa", 0.5, 0.9, -38, 70, 260 } } },
    forest = { sky = "forest.hdr", sun = { vec3(-0.38, -0.6, 0.62), vec3(1, .9, .78), 3.2 }, ibl = 0.92, fog = 0.0034,
        ground = "floor", gy = -30, tex = "autumn_floor", nrm = "floor_n", rough = 0.9, tint = { 1, 1, 1 }, mtn = "mtn_autumn", bridge = "forest",
        props = { { "tree_autumn", 2.6, 3.6, -30, 14, 90 }, { "tree_autumn2", 2.6, 3.4, -30, 14, 90 }, { "pine", 2.8, 3.8, -30, 14, 110 }, { "rock", 2.0, 3.0, -30, 14, 80 } } },
    frost = { sky = "frost.hdr", sun = { vec3(-0.3, -0.55, 0.65), vec3(.94, .97, 1), 3.1 }, ibl = 1.0, fog = 0.0032,
        ground = "sea", gy = -7.5, tex = "water_frost", nrm = "water_n", rough = 0.1, tint = { 1, 1, 1 }, mtn = "mtn_snow", bridge = "frost",
        props = { { "iceberg", 0.8, 1.8, -1.5, 24, 220 }, { "iceberg", 0.4, 0.8, -1, 16, 80 }, { "buoy", 1.0, 1.0, -7.3, 10, 22 } } },
    volcano = { sky = "volcano.hdr", sun = { vec3(-0.6, -0.45, 0.62), vec3(1, .74, .55), 3.2 }, ibl = 0.78, fog = 0.0036,
        ground = "sea", gy = -22, tex = "lava", nrm = "lava_n", em = "lava_em", rough = 0.75, tint = { 1, 1, 1 }, mtn = "mtn_volcano", bridge = "volcano",
        props = { { "rock_lava", 2.5, 4.5, -22, 16, 120 }, { "rock_lava", 1.5, 2.5, -22, 14, 60 } } },
}
G.WL = WL
local W3 = { sea = nil, floor = nil, deck = nil, bridges = {}, scen = {}, mtns = {}, key = nil }
G.W3 = W3
local function hash(i) local h = (i * 2654435761) % 4294967296; return (h % 100003) / 100003 end
local NSCEN, SPER = 46, 760
local function set_world(key)
    local w = WL[key]; if not w then return end
    if W3.key == key then return end
    W3.key = key
    pcall(skybox.load, w.sky)
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, w.sun[1], w.sun[2], w.sun[3])
    S("IBL_intensity", w.ibl); S("fog_density", w.fog)
    -- ground plane
    if not W3.sea then W3.sea = clone("sea"); W3.floor = clone("floor"); W3.deck = clone("deck") end
    local gnode = (w.ground == "sea") and W3.sea or W3.floor
    local other = (w.ground == "sea") and W3.floor or W3.sea
    other:set_position(HIDE)
    local tn = tnode(w.ground)
    mtex(tn, "base_color", "Textures/" .. w.tex .. ".png"); mtex(tn, "normal", "Textures/" .. w.nrm .. ".png")
    mset(tn, "base_color", vec4(w.tint[1], w.tint[2], w.tint[3], 1)); mset(tn, "roughness", w.rough); mset(tn, "metallic", 0.0)
    if w.em then mtex(tn, "emissive", "Textures/" .. w.em .. ".png"); mset(tn, "emissive", vec3(2.2, 2.2, 2.2)) else mset(tn, "emissive", vec3(0, 0, 0)) end
    W3.gnode, W3.gy, W3.gper = gnode, w.gy, (w.ground == "sea") and 12 or 16
    -- bridge chunks (2 bays = 40 m each)
    for _, list in pairs(W3.bridges) do for _, n in ipairs(list) do n:set_position(HIDE) end end
    if not W3.bridges[w.bridge] then
        local list = {}
        for i = 1, 30 do list[i] = clone("bridge_" .. w.bridge) end
        W3.bridges[w.bridge] = list
    end
    W3.bl = W3.bridges[w.bridge]
    -- scenery: deterministic slots along both sides, wrap-scrolled
    for _, s in ipairs(W3.scen) do F_put(s.kind, s.n) end
    W3.scen = {}
    for i = 1, NSCEN do
        local p = w.props[1 + floor(hash(i * 7 + 3) * #w.props)]
        local side = (i % 2 == 0) and 1 or -1
        local s = { kind = p[1], n = F_get(p[1]), x = side * (p[5] + hash(i * 13 + 1) * (p[6] - p[5])), z0 = (i - 1) / NSCEN * SPER + hash(i * 5) * 12,
            y = p[4], sc = p[2] + hash(i * 11 + 2) * (p[3] - p[2]), ry = hash(i * 17) * 360 }
        W3.scen[i] = s
    end
    -- mountain ring (static, far)
    for _, m in ipairs(W3.mtns) do F_put(m.kind, m.n) end
    W3.mtns = {}
    local gy = w.gy
    for i = 1, 14 do
        -- front arc only (never behind / around the camera): a in [-1.85, 1.85] rad around +z
        local a = -1.85 + (i - 1) / 13 * 3.7 + (hash(i * 3) - 0.5) * 0.15
        local r = 950 + hash(i * 19) * 450
        local kind = w.mtn
        local n = F_get(kind)
        local x, z = math.sin(a) * r, 250 + math.cos(a) * r
        local sc = 0.85 + hash(i * 23) * 0.6
        place(n, x, gy - 6, z, sc * 1.4, sc * (0.8 + hash(i * 29) * 0.6), sc * 1.4, hash(i * 31) * 360)
        W3.mtns[i] = { kind = kind, n = n }
    end
end
G.set_world = set_world
-- per-frame scroll of everything static in the world (travel = metres marched)
local function world_scroll(travel, camx)
    if not W3.key then return end
    W3.deck:set_position(vec3(0, 0, -(travel % 10)))
    local bo = travel % 40
    for i, n in ipairs(W3.bl) do n:set_position(vec3(0, 0, -40 + (i - 1) * 40 - bo)) end
    local gp = W3.gper
    W3.gnode:set_position(vec3(camx or 0, W3.gy, 200 - (travel % gp)))
    for _, s in ipairs(W3.scen) do
        local z = ((s.z0 - travel) % SPER) - 90
        s.n:set_transform(vec3(s.x, s.y, z), vec3(0, s.ry, 0), vec3(s.sc, s.sc, s.sc))
    end
end
G.world_scroll = world_scroll

------------------------------------------------------------------ lights: sun + flash pool that rides on events
local LT = { flash = {} }
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    for i = 1, 4 do LT.flash[i] = { idx = add_point(), t = 1, life = 1 }; set_point(LT.flash[i].idx, HIDE, vec3(1, 1, 1), 0, 1) end
end
G.flash_next = 1
local function flash(x, y, z, col, power, life, rad)
    local f = LT.flash[G.flash_next]; if not f then return end
    G.flash_next = G.flash_next % #LT.flash + 1
    f.t, f.life, f.p, f.col, f.power, f.rad = 0, life or 0.3, vec3(x, y, z), vec3(col[1], col[2], col[3]), power or 40, rad or 8
end
local function update_lights(dt)
    for _, f in ipairs(LT.flash) do
        if f.t < f.life then
            f.t = f.t + dt
            local k = 1 - clamp(f.t / f.life, 0, 1)
            set_point(f.idx, f.p, f.col, f.power * k * k, f.rad)
            if f.t >= f.life then set_point(f.idx, HIDE, f.col, 0, 1) end
        end
    end
end
G.flash = flash
G.fx_light = function(pos, col, power, life, radius) flash(pos.x, pos.y, pos.z, { col.x or col[1], col.y or col[2], col.z or col[3] }, power, life, radius) end
------------------------------------------------------------------ 02c_fx: particle effects (Scripts/Lib/particles.lua), all positions in WORLD space
do
local FX = { tex = {}, scale = 1 }
G.FX = FX
FX.lib = load(fs.read("Scripts/Lib/particles.lua"), "@particles.lua")().new({
    scale = PS, gain = 1, light = function(pos, col, power, life, radius) if G.fx_light then G.fx_light(pos, col, power, life, radius) end end })
FX.tex = FX.lib.tex
for _, k in ipairs({ "dust", "foam", "soft", "ring", "spark", "smoke", "debris", "ember", "fire" }) do
    if not FX.tex[k] then
        local ok, idx = pcall(particles.load_texture, "Textures/fx/" .. k .. ".png")
        FX.tex[k] = (ok and type(idx) == "number") and idx or 0
    end
end
local BOOK = { fire = { 4, 4 }, smoke = { 4, 4 }, debris = { 2, 2 } }
local function fxv(t) return vec3(t[1], t[2], t[3]) end
function FX.emit(tex, x, y, z, o)
    local n = max(1, floor((o.n or 8) * PS() + 0.5))
    local c0, c1 = o.c0 or { 1, 1, 1 }, o.c1 or { 0, 0, 0 }
    local ok, id = pcall(particles.emit_burst, {
        position = vec3(x, y, z), velocity = o.vel and fxv(o.vel) or vec3(0, 0, 0),
        color_start = vec4(c0[1], c0[2], c0[3], 1), color_end = vec4(c1[1], c1[2], c1[3], 0.02), count = n,
        size_min = o.s0 or 0.2, size_max = o.s1 or 0.4, life_min = o.l0 or 0.4, life_max = o.l1 or 0.8,
        spawn_radius = o.r or 0.2, noise_strength = o.sp or 2, drag = o.drag or 1.5,
        gravity = o.grav and fxv(o.grav) or vec3(0, 0, 0),
        texture_index = FX.tex[tex] or 0, orientation = o.flat and "horizontal" or (o.stretch and "velocity" or "billboard"),
        cleanup_delay = (o.l1 or 0.8) + 1.0,
    })
    local b = BOOK[tex]
    if ok and b and id then pcall(particles.set_emitter, id, { anim_cols = b[1], anim_rows = b[2], anim_speed = o.anim or (1 / (o.l1 or 0.8)), interpolate = true }) end
end
local function sc(c, k) return { c[1] * k, c[2] * k, c[3] * k } end
-- world x here is WORLD x (callers convert lane x with wx())
function FX.puff(x, y, z, col, k)       -- unit pops in / vanishes: soft coloured puff + tiny sparkle
    k = k or 1
    FX.emit("soft", x, y, z, { n = 2 * k, c0 = sc(col, 0.9), c1 = { 0, 0, 0 }, s0 = 0.35, s1 = 0.7, l0 = 0.18, l1 = 0.35, r = 0.15, sp = 1.5, drag = 3, grav = { 0, 1.5, 0 } })
end
function FX.dust(x, y, z, col, k, size)
    k = k or 1; size = size or 1
    FX.emit("dust", x, y, z, { n = 2 + 3 * k, c0 = sc(col, k), c1 = { 0, 0, 0 }, s0 = 0.5 * size, s1 = 1.1 * size, l0 = 0.45, l1 = 0.9, r = 0.35 * size, sp = 2.2, drag = 2.6, grav = { 0, 0.6, 0 } })
end
function FX.grit(x, y, z, col, n, vel)
    FX.emit("debris", x, y, z, { n = n or 6, vel = vel, c0 = col, c1 = sc(col, 0.3), s0 = 0.08, s1 = 0.18, l0 = 0.4, l1 = 0.8, r = 0.25, sp = 6, drag = 0.7, grav = { 0, -16, 0 }, anim = 0.01 })
end
function FX.sparks(x, y, z, n, vel, spread, col)
    col = col or { 2.0, 1.5, 0.8 }
    FX.emit("spark", x, y, z, { n = n or 14, vel = vel, c0 = col, c1 = { 0.5, 0.15, 0.02 }, s0 = 0.07, s1 = 0.14, l0 = 0.18, l1 = 0.45, r = 0.1, sp = spread or 9, drag = 1.8, grav = { 0, -9, 0 }, stretch = true })
end
function FX.confetti(x, y, z, n, size)
    size = size or 1
    local cols = { { 1.2, .35, .35 }, { .35, .7, 1.3 }, { 1.3, 1.0, .3 }, { .4, 1.1, .5 }, { 1.0, .5, 1.2 } }
    for i, c in ipairs(cols) do
        FX.emit("debris", x, y, z, { n = (n or 30) / 5, vel = { 0, 7 * size, 0 }, c0 = c, c1 = sc(c, 0.6), s0 = 0.1 * size, s1 = 0.2 * size, l0 = 1.2, l1 = 2.2,
            r = 0.6 * size, sp = 7 * size, drag = 1.6, grav = { 0, -5, 0 }, anim = 0.4 })
    end
end
function FX.flash(x, y, z, size, col)
    FX.emit("soft", x, y, z, { n = 1 / max(PS(), 0.01), c0 = col or { 1.4, 1.2, 0.8 }, c1 = { 0, 0, 0 }, s0 = size, s1 = size * 1.1, l0 = 0.1, l1 = 0.16, r = 0, sp = 0, drag = 0 })
end
function FX.ring(x, y, z, size, col, flat)
    FX.emit("ring", x, y, z, { n = 1 / max(PS(), 0.01), c0 = col or { 0.6, 0.6, 0.6 }, c1 = { 0, 0, 0 }, s0 = size, s1 = size, l0 = 0.3, l1 = 0.35, r = 0, sp = 0, flat = flat })
end
function FX.spray(x, y, z, k, size)
    k = k or 1; size = size or 1
    FX.emit("foam", x, y, z, { n = 3 + 3 * k, vel = { 0, 5, 0 }, c0 = { 0.8 * k, 0.88 * k, 0.95 * k }, c1 = { 0, 0, 0 }, s0 = 0.4 * size, s1 = 1.0 * size,
        l0 = 0.4, l1 = 0.9, r = 0.4 * size, sp = 3, drag = 1.5, grav = { 0, -9, 0 } })
end
function FX.coin(x, y, z)
    FX.emit("spark", x, y, z, { n = 5, vel = { 0, 3, 0 }, c0 = { 2.0, 1.6, 0.5 }, c1 = { 0.4, 0.25, 0 }, s0 = 0.05, s1 = 0.1, l0 = 0.25, l1 = 0.45, r = 0.2, sp = 4, drag = 2, grav = { 0, -4, 0 }, stretch = true })
end
function FX.smoke(x, y, z, k, size)
    k = k or 1; size = size or 1
    FX.emit("smoke", x, y, z, { n = 2 + 2 * k, c0 = { 0.55 * k, 0.55 * k, 0.56 * k }, c1 = { 0, 0, 0 }, s0 = 0.8 * size, s1 = 1.7 * size, l0 = 0.8, l1 = 1.6, r = 0.4 * size, sp = 1.4, drag = 2.2, grav = { 0, 1.2, 0 } })
end
function FX.glow_trail(x, y, z, col)   -- gate pass shimmer
    FX.emit("ember", x, y, z, { n = 10, vel = { 0, 2.5, 0 }, c0 = col, c1 = { 0, 0, 0 }, s0 = 0.08, s1 = 0.18, l0 = 0.5, l1 = 1.0, r = 2.0, sp = 2.5, drag = 1.2, grav = { 0, 1.5, 0 } })
end
function FX.boom(x, y, z, size)
    FX.lib:explosion(vec3(x, y, z), { size = size or 1, smoke = true, debris = { .45, .32, .22 }, spark_grav = -9 })
end
function FX.muzzle(x, y, z, col)
    FX.emit("soft", x, y, z, { n = 1 / max(PS(), 0.01), c0 = { col[1] * 1.6, col[2] * 1.4, col[3] * 1.1 }, c1 = { 0, 0, 0 }, s0 = 0.28, s1 = 0.38, l0 = 0.05, l1 = 0.08, r = 0, sp = 0, drag = 0 })
end
function FX.blood(x, y, z, n)   -- cartoon "goo" pop for the mutant horde: purple-red droplets, no gore
    FX.emit("debris", x, y, z, { n = n or 6, vel = { 0, 3, 0 }, c0 = { .85, .18, .3 }, c1 = { .4, .05, .15 }, s0 = 0.07, s1 = 0.15, l0 = 0.3, l1 = 0.6, r = 0.2, sp = 4, drag = 1, grav = { 0, -14, 0 }, anim = 0.01 })
    FX.emit("soft", x, y, z, { n = 2, c0 = { .9, .3, .45 }, c1 = { 0, 0, 0 }, s0 = 0.35, s1 = 0.6, l0 = 0.15, l1 = 0.3, r = 0.1, sp = 1, drag = 3 })
end
function FX.shards(x, y, z, col, n)   -- glass gate / ice
    FX.emit("debris", x, y, z, { n = n or 10, vel = { 0, 2, 0 }, c0 = col, c1 = sc(col, 0.4), s0 = 0.08, s1 = 0.2, l0 = 0.5, l1 = 0.9, r = 1.2, sp = 5, drag = 0.8, grav = { 0, -12, 0 }, anim = 0.2 })
end
function FX.fire(x, y, z, size)
    FX.emit("fire", x, y, z, { n = 3, vel = { 0, 2, 0 }, c0 = { 1.6, 1.1, .5 }, c1 = { .3, .1, .02 }, s0 = 0.6 * size, s1 = 1.2 * size, l0 = 0.4, l1 = 0.7, r = 0.3 * size, sp = 1, drag = 1.5, grav = { 0, 2, 0 } })
end
FX.trails = {}
function FX.trail(kind)
    if kind == "smoke" then
        return FX.lib:trail("smoke", { c0 = { .7, .7, .72, .6 }, c1 = { .2, .2, .2, 0 }, smin = .25, smax = .5, lmin = .35, lmax = .7, radius = .05, spread = .4, grav = { 0, .8, 0 }, max = 160 })
    end
    return FX.lib:trail("ember", { c0 = { 1.8, 1.0, .4, 1 }, c1 = { .5, .1, .02, 0 }, smin = .1, smax = .22, lmin = .12, lmax = .25, radius = .05, spread = .5, max = 120 })
end
end
do -- 03_data.lua
------------------------------------------------------------------ 03_data: tables (engine-agnostic; also loaded by tools/simtest)
local D = {}
G.D = D
D.STEER = 26         -- m/s the squad chases the pointer (was 14: snappy, no floaty lag)
D.STEER_KEY = 16     -- m/s with A/D or arrow keys
D.GATE_PASS = 0.75   -- share of a projectile's damage a gate takes as it flies through (projectiles are not stopped)
D.LANE = 5.0          -- usable half width of the lane (deck is 5.5)
D.SPAWN_Z = 100       -- things appear this far ahead
D.SPEED = 5.5         -- march speed (world scroll), m/s
D.VIS = 30            -- bodies drawn in the squad (the rest is a number)
D.BULLETS_PS = 150    -- cap on simulated bullets per second (damage per bullet grows instead)

-- weapons: dps = damage per second per unit of firepower; rate = seconds between shots of one rifleman
D.WEAPONS = {
    rifle = { name = "Rifle", rate = 0.32, dps = 1.0, speed = 80, spread = 0.5, range = 98, col = { 1.0, 0.82, 0.4 } },
    shotgun = { name = "Shotgun", rate = 0.8, dps = 1.35, pellets = 4, speed = 62, spread = 5.5, range = 42, col = { 1.0, 0.65, 0.3 } },
    minigun = { name = "Minigun", rate = 0.1, dps = 1.45, speed = 85, spread = 1.4, range = 92, col = { 1.0, 0.9, 0.5 } },
    rocket = { name = "Rockets", rate = 1.15, dps = 1.55, speed = 40, spread = 0.6, homing = true, lock = 55, turn = 2.6, range = 98, splash = 2.4, col = { 1.0, 0.55, 0.2 } },
    laser = { name = "Laser", rate = 0.6, dps = 1.75, beam = true, pierce = 3, range = 80, col = { 0.4, 0.95, 1.0 } },
}
D.WORDER = { "rifle", "shotgun", "minigun", "rocket", "laser" }
D.WPRICE = { rifle = 0, shotgun = 400, minigun = 1100, rocket = 2200, laser = 4000 }
D.POWER = { sol = 1, vet = 5, hvy = 22, hero = 8 }   -- firepower per body (heavy: +10% over its 4 vets)
D.WORTH = { sol = 1, vet = 5, hvy = 20, hero = 1 }   -- counter worth = merge ratios, so merging never lowers it

-- enemies (hp before level scaling)
D.ENEMY = {
    runner = { hp = 4, spd = 3.0, r = 0.45, dmg = 1, coin = 1, score = 10, steer = 1.0, aggro = 22 },
    brute = { hp = 70, spd = 1.9, r = 1.0, dmg = 6, coin = 6, score = 60, steer = 0.3, aggro = 18 },
    shield = { hp = 7, shield = 32, spd = 2.5, r = 0.55, dmg = 2, coin = 3, score = 30, steer = 0.7, aggro = 18 },
    flyer = { hp = 9, spd = 4.6, r = 0.6, dmg = 3, coin = 3, score = 30, steer = 1.3, aggro = 26, fly = true },
    orb = { hp = 5, spd = 9, r = 0.5, dmg = 3, coin = 0, score = 5, steer = 2.4, aggro = 30, fly = true },
}
D.BOSS = {
    goliath = { name = "Goliath", hp = 4800, r = 2.0, stop = 16, coin = 120, score = 2000, body = "gol" },
    ironclad = { name = "Ironclad", hp = 6500, r = 2.2, stop = 18, coin = 180, score = 3000, body = "mech" },
    wasp = { name = "Wasp Queen", hp = 8000, r = 2.0, stop = 17, coin = 260, score = 4000, body = "wasp", fly = true },
}
-- allies freed from containers
D.ALLY = {
    turret = { name = "Sentry Turret", dps = 14 },
    heli = { name = "Gunship", dps = 0, rocket = 34, every = 1.1, life = 32 },
    mech = { name = "Ally Mech", dps = 18, hp = 90 },
    sniper = { name = "Sniper Nest", shot = 90, every = 1.3 },
    drones = { name = "Drone Swarm", dps = 5, n = 3 },
}
D.AORDER = { "turret", "heli", "mech", "sniper", "drones" }

-- gate kinds; colour = panel mesh
D.GATE = {
    add = { col = "blue" }, sub = { col = "red" }, mul = { col = "green" }, div = { col = "red" },
    lock = { col = "grey" }, rate = { col = "blue" }, dmg = { col = "blue" }, merge = { col = "gold" }, trap = { col = "orange" },
}
D.MUL = { 0.25, 1 / 3, 0.5, 1.5, 2, 2.5 }          -- ladder; shooting climbs it
D.MULTXT = { "÷4", "÷3", "÷2", "x1.5", "x2", "x2.5" }

-- worlds: 2 levels each
D.WORLDS = {
    harbor = { name = "Harbor", sky = "harbor.hdr" }, canyon = { name = "Canyon", sky = "canyon.hdr" },
    forest = { name = "Autumn Woods", sky = "forest.hdr" }, frost = { name = "Frost Bay", sky = "frost.hdr" },
    volcano = { name = "Ember Peaks", sky = "volcano.hdr" },
}
-- levels: len (m), hp scale, horde size scale, features, boss
D.LEVELS = {
    { name = "Harbor Run", world = "harbor", len = 430, hpk = 1.0, nk = 1.00, feat = { add = 1, mul = 1, crate = 1 }, ally = "turret" },
    { name = "Dockyard Siege", world = "harbor", len = 500, hpk = 1.25, nk = 1.38, feat = { add = 1, mul = 1, crate = 1, brute = 1, rate = 1, barrel = 1 }, ally = "heli" },
    { name = "Red Mesa", world = "canyon", len = 520, hpk = 1.55, nk = 1.50, feat = { add = 1, mul = 1, crate = 1, brute = 1, shield = 1, trap = 1, barrel = 1 }, ally = "sniper", boss = "goliath" },
    { name = "Dust Bridge", world = "canyon", len = 580, hpk = 1.9, nk = 1.62, feat = { add = 1, mul = 1, crate = 1, brute = 1, shield = 1, flyer = 1, lock = 1, barricade = 1, barrel = 1, dmg = 1 }, ally = "drones" },
    { name = "Pine Pass", world = "forest", len = 600, hpk = 2.3, nk = 1.74, feat = { add = 1, mul = 1, crate = 1, brute = 1, shield = 1, flyer = 1, merge = 1, trap = 1, barrel = 1, rate = 1 }, ally = "mech", boss = "ironclad" },
    { name = "Autumn Gorge", world = "forest", len = 650, hpk = 2.8, nk = 1.86, feat = { add = 1, mul = 1, crate = 1, brute = 1, shield = 1, flyer = 1, merge = 1, lock = 1, barricade = 1, barrel = 1, dmg = 1 }, ally = "heli" },
    { name = "Frost Span", world = "frost", len = 680, hpk = 3.4, nk = 2.04, feat = { add = 1, mul = 1, crate = 1, brute = 1, shield = 1, flyer = 1, merge = 1, trap = 1, cryo = 1, lock = 1 }, ally = "turret", boss = "wasp" },
    { name = "Glacier Gate", world = "frost", len = 720, hpk = 4.1, nk = 2.22, feat = { add = 1, mul = 1, crate = 1, brute = 1, shield = 1, flyer = 1, merge = 1, trap = 1, cryo = 1, lock = 1, barricade = 1, rate = 1 }, ally = "mech" },
    { name = "Ember Crossing", world = "volcano", len = 760, hpk = 5.0, nk = 2.40, feat = { add = 1, mul = 1, crate = 1, brute = 1, shield = 1, flyer = 1, merge = 1, trap = 1, barrel = 1, lock = 1, barricade = 1, dmg = 1 }, ally = "sniper", boss = "ironclad" },
    { name = "Inferno Gate", world = "volcano", len = 820, hpk = 6.0, nk = 2.64, feat = { add = 1, mul = 1, crate = 1, brute = 1, shield = 1, flyer = 1, merge = 1, trap = 1, barrel = 1, lock = 1, barricade = 1, rate = 1, dmg = 1 }, ally = "heli", boss = "goliath", boss2 = "wasp" },
}

-- shop
D.UPG = {
    { key = "fire", name = "Firepower", desc = "+12% damage", base = 60, max = 20 },
    { key = "rate", name = "Fire Rate", desc = "+7% fire rate", base = 70, max = 15 },
    { key = "squad", name = "Starting Squad", desc = "+2 soldiers at the start", base = 50, max = 15 },
    { key = "crit", name = "Critical Hits", desc = "+4% chance of a x3 hit", base = 90, max = 10 },
    { key = "gate", name = "Gate Mastery", desc = "Gates climb 10% faster", base = 80, max = 10 },
    { key = "armor", name = "Body Armor", desc = "+5% chance to shrug off a hit", base = 100, max = 8 },
    { key = "elite", name = "Elite Training", desc = "Veterans and Heavies hit 10% harder", base = 120, max = 10 },
    { key = "air", name = "Air Support", desc = "Airstrikes charge 12% faster, +1 bomb", base = 110, max = 8 },
    { key = "ally", name = "Ally Tech", desc = "Freed allies are 15% stronger", base = 100, max = 8 },
    { key = "bounty", name = "Bounty", desc = "+10% coins", base = 120, max = 10 },
}
function D.upg_cost(u, lvl) return math.floor(u.base * (1.42 ^ lvl) / 5 + 0.5) * 5 end
D.HEROES = {
    { key = "rook", name = "Rook", desc = "Steady leader: +10% damage", coins = 0, medals = 0 },
    { key = "juno", name = "Juno", desc = "Field medic: a new recruit every 3 s", coins = 600, medals = 1 },
    { key = "bruno", name = "Bruno", desc = "Gunner: +25% fire rate", coins = 1200, medals = 2 },
    { key = "vex", name = "Vex", desc = "Demolitions: airstrikes charge 60% faster", coins = 1800, medals = 3 },
    { key = "hawke", name = "Hawke", desc = "Marksman: +15% crit chance", coins = 2600, medals = 4 },
    { key = "nova", name = "Nova", desc = "Tactician: gates climb 35% faster, +1 to plus gates", coins = 3600, medals = 5 },
}

------------------------------------------------------------------ save game (fs is optional: the sim test has none)
D.SAVE = "Save/gatebreaker.sav"
function D.new_save()
    local s = { coins = 0, medals = 0, unlocked = 1, best = {}, stars = {}, up = {}, heroes = { rook = true }, hero = "rook",
        weapons = { rifle = true }, weapon = "rifle", seen_tut = false }
    for _, u in ipairs(D.UPG) do s.up[u.key] = 0 end
    return s
end
function D.serialize(s)
    local o = {}
    local function kv(k, v) o[#o + 1] = k .. "=" .. tostring(v) end
    kv("coins", s.coins); kv("medals", s.medals); kv("unlocked", s.unlocked); kv("hero", s.hero); kv("weapon", s.weapon); kv("seen_tut", s.seen_tut)
    for i = 1, #D.LEVELS do kv("best" .. i, s.best[i] or 0); kv("stars" .. i, s.stars[i] or 0) end
    for k, v in pairs(s.up) do kv("up_" .. k, v) end
    for k in pairs(s.heroes) do kv("hero_" .. k, 1) end
    for k in pairs(s.weapons) do kv("wpn_" .. k, 1) end
    return table.concat(o, "\n")
end
function D.deserialize(txt)
    local s = D.new_save()
    for line in tostring(txt or ""):gmatch("[^\n]+") do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k then
            local n = tonumber(v)
            if k == "coins" or k == "medals" or k == "unlocked" then s[k] = n or s[k]
            elseif k == "hero" or k == "weapon" then s[k] = v
            elseif k == "seen_tut" then s.seen_tut = v == "true"
            elseif k:sub(1, 4) == "best" then s.best[tonumber(k:sub(5))] = n
            elseif k:sub(1, 5) == "stars" then s.stars[tonumber(k:sub(6))] = n
            elseif k:sub(1, 3) == "up_" then s.up[k:sub(4)] = n or 0
            elseif k:sub(1, 5) == "hero_" then s.heroes[k:sub(6)] = true
            elseif k:sub(1, 4) == "wpn_" then s.weapons[k:sub(5)] = true end
        end
    end
    if not s.heroes[s.hero] then s.hero = "rook" end
    if not s.weapons[s.weapon] then s.weapon = "rifle" end
    s.unlocked = math.max(1, math.min(#D.LEVELS, s.unlocked or 1))
    return s
end
end
do -- 03b_levels.lua
------------------------------------------------------------------ 03b_levels: deterministic level generator
local D = G.D
function D.gen_level(n)
    local L = D.LEVELS[n]
    local f = L.feat
    local seed = n * 7919 + 13
    local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
    local function ri(a, b) return a + math.floor(rnd() * (b - a + 1)) end
    local function pick(t) return t[ri(1, #t)] end
    local ev = {}
    local function E(d, t, p) p = p or {}; p.d = d; p.ev = t; ev[#ev + 1] = p; return p end
    local len, hk = L.len, L.hpk
    local lv = 1 + 0.16 * (n - 1)
    local endd = len - (L.boss and 30 or 20)

    local function wave(d, p, big)
        local count = math.floor(L.nk * (7 + 30 * p) * (big and 1.45 or 1) + 0.5)
        local nb = (f.brute and p > 0.2) and math.floor(count / (big and 11 or 16)) or 0
        local ns = (f.shield and p > 0.15) and math.floor(count / 7) or 0
        local nf = (f.flyer and p > 0.1) and math.floor(count / 8) or 0
        local nr = math.max(3, count - nb * 7 - ns * 2 - nf * 2)
        local clumps = big and 3 or (count > 18 and 2 or 1)
        local cx = {}
        for c = 1, clumps do cx[c] = (clumps == 1) and (rnd() * 7 - 3.5) or (-3.6 + 7.2 * (c - 1) / (clumps - 1) + rnd() * 1.2 - 0.6) end
        local function g() return (rnd() + rnd() + rnd() - 1.5) end
        local hm = 1 + 3.0 * p
        -- formation shapes so threats arrive at different x positions (straight fire: you have to steer onto them)
        local shape = (n == 1 and p < 0.2) and "clump" or pick({ "clump", "clump", "flank", "column", "sweep" })
        local side = rnd() < 0.5 and -1 or 1
        for i = 1, nr do
            local c = cx[1 + (i % clumps)]
            local dd, x, lane = d + rnd() * (6 + count * 0.12), c + g() * 1.5, nil
            if shape == "flank" then x = side * ((i % 2 == 0) and 1 or -1) * (2.6 + rnd() * 1.8)
            elseif shape == "column" then x = side * (1.2 + (i % 3) * 1.2) + g() * 0.3; dd = d + i * math.min(0.9, 26 / nr); lane = (i % 3 ~= 0) or nil
            elseif shape == "sweep" then local k = (i - 1) / math.max(1, nr - 1); x = side * (-4 + 8 * k) + g() * 0.4; dd = d + k * (8 + count * 0.15) + rnd() end
            E(dd, "foe", { t = "runner", hm = hm, x = x, lane = lane })
        end
        for i = 1, nb do E(d + 4 + rnd() * 6, "foe", { t = "brute", hm = hm, x = cx[1 + (i % clumps)] + g(), lane = (i % 2 == 0) or nil }) end
        for i = 1, ns do E(d - 1 + rnd() * 3, "foe", { t = "shield", hm = hm, x = -4 + 8 * ((i - 0.5) / ns) + g() * 0.4 }) end
        for i = 1, nf do E(d + 8 + rnd() * 10, "foe", { t = "flyer", hm = hm, x = (rnd() * 2 - 1) * 4 }) end
        if f.barrel and rnd() < 0.55 then E(d - 3, "prop", { t = "barrel", x = cx[1] }) end
        if f.cryo and rnd() < 0.45 then E(d - 3, "prop", { t = "cryo", x = cx[#cx] }) end
        return d + 26 + count * 0.25
    end

    local wlist = { "shotgun", "minigun" }
    if n >= 2 then wlist[#wlist + 1] = "rocket" end
    if n >= 4 then wlist[#wlist + 1] = "laser" end
    local ally_i = 0
    local function gates(d, p, first)
        local a = math.max(2, math.floor((3 + 11 * p) * (0.8 + 0.4 * rnd()) * lv + 0.5))
        local per = 3.2 * hk ^ 0.85 * (1 + 0.8 * p)
        local opts = { "addsub", "addmul", "addmul" }
        if f.trap then opts[#opts + 1] = "trap"; opts[#opts + 1] = "trap" end
        if f.lock then opts[#opts + 1] = "lock" end
        if f.rate or f.dmg then opts[#opts + 1] = "ratedmg" end
        if f.merge and p > 0.3 then opts[#opts + 1] = "merge" end
        if p > 0.15 then opts[#opts + 1] = "single" end
        local o = first and "first" or pick(opts)
        local s = rnd() < 0.5 and -1 or 1
        local function GT(x, k, t) t = t or {}; t.x = x; t.k = k; t.per = t.per or per; return t end
        local row
        if o == "first" then row = { GT(-2.5, "add", { v = 4 }), GT(2.5, "mul", { mi = 3, per = 9 * hk }) }
        elseif o == "addsub" then row = { GT(2.5 * s, "add", { v = a }), GT(-2.5 * s, "add", { v = -math.floor(a * 1.3 + 2) }) }
        elseif o == "addmul" then row = { GT(2.5 * s, "add", { v = math.floor(a * 1.4) }), GT(-2.5 * s, "mul", { mi = (p > 0.5 and 2 or 3), per = 26 * hk ^ 0.85 * (1 + p) }) }
        elseif o == "trap" then row = { GT(2.5 * s, "trap", { v = math.floor(a * 0.6) + 1, maxv = math.floor(a * 1.8) + 3, per = per * 0.8 }), GT(-2.5 * s, "add", { v = math.floor(a * 0.5) + 1 }) }
        elseif o == "lock" then row = { GT(2.5 * s, "lock", { hp = 130 * hk * (1 + 1.4 * p), mi = 5 }), GT(-2.5 * s, "add", { v = math.floor(a * 0.8) }) }
        elseif o == "ratedmg" then row = { GT(2.5 * s, f.rate and "rate" or "dmg", { v = -10, per = per * 2.2 }), GT(-2.5 * s, f.dmg and "dmg" or "rate", { v = 5, per = per * 2.2 }) }
        elseif o == "merge" then row = { GT(2.5 * s, "merge", {}), GT(-2.5 * s, "add", { v = math.floor(a * 1.2) }) }
        else row = { GT(2.5 * s + (rnd() - 0.5), "add", { v = math.floor(a * 1.6) + 2 }) } end
        E(d, "gates", { row = row })
        return d + 30
    end
    local function crate(d, p)
        E(d, "prop", { t = "crate", x = rnd() * 6 - 3, w = pick(wlist), hp = 22 * hk * (1 + 1.2 * p) })
        return d + 18
    end
    local function container(d, p)
        ally_i = ally_i + 1
        local a = (ally_i == 1) and L.ally or D.AORDER[ri(1, #D.AORDER)]
        E(d, "prop", { t = "container", x = rnd() * 4 - 2, ally = a, hp = 80 * hk * (1 + 1.3 * p) })
        return d + 22
    end
    local function barricade(d, p)
        local s = rnd() < 0.5 and -1 or 1
        E(d, "prop", { t = "barricade", x = 2.6 * s, hp = 55 * hk * (1 + 1.5 * p) })
        if rnd() < 0.5 then E(d + 2, "prop", { t = "barrel", x = -2.6 * s }) end
        return d + 16
    end
    local pat = { "gates", "wave", "crate", "gates", "wave", "container", "gates", "wave", "air", "gates", "barricade", "wave", "gates", "big", "drop", "gates", "wave", "container", "gates", "big" }
    local d, i = 32, 0
    E(30, "hint", { txt = (n == 1) and "Your Squad Fires On Its Own" or L.name })
    gates(36, 0, true); d = 70
    while d < endd do
        i = i + 1
        local b = pat[(i - 1) % #pat + 1]
        local p = d / len
        if b == "gates" then d = gates(d, p)
        elseif b == "wave" then d = wave(d, p)
        elseif b == "big" then d = wave(d, p, true)
        elseif b == "crate" then d = f.crate and crate(d, p) or d
        elseif b == "container" then d = container(d, p)
        elseif b == "barricade" then d = f.barricade and barricade(d, p) or (f.barrel and wave(d, p) or d)
        elseif b == "air" then E(d, "air", { kind = "gunship" }); d = d + 4
        elseif b == "drop" then E(d, "air", { kind = "drop", w = pick(wlist) }); d = d + 4 end
    end
    if n == 1 then
        E(60, "hint", { txt = "Shoot Gates To Raise Their Value" })
        E(150, "hint", { txt = "Break Crates For Better Guns" })
        E(240, "hint", { txt = "Bust Containers Open To Free Allies" })
    end
    if L.boss then
        wave(len - 60, 0.95)
        E(len, "boss", { b = L.boss, b2 = L.boss2 })
    else
        E(len, "finish")
    end
    table.sort(ev, function(a, b) return a.d < b.d end)
    return ev
end
end
do -- 04_sim.lua
------------------------------------------------------------------ 04_sim: gameplay simulation (engine-agnostic)
local D = G.D
local SIM = {}
G.SIM = SIM
local abs, min, max, floor, sqrt, rand = math.abs, math.min, math.max, math.floor, math.sqrt, math.random
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
SIM.clamp = clamp

-- formation: slot offsets for n visible bodies (front row at z=0, rows going back)
-- columns are capped at 7 so even a full squad covers about half the lane (straight fire: where you stand is
-- what you hit); past 30 units the spacing widens a little (up to +17%) so a huge squad sweeps a wider strip.
local fcache = {}
local S -- current run state
function SIM.formation(n)
    local wb = 0
    if S then wb = floor(clamp((SIM.units() - 30) / 90, 0, 1) * 5 + 0.5) end
    local key = n * 8 + wb
    if fcache[key] then return fcache[key] end
    local sp = 0.74 + 0.025 * wb
    local cols = clamp(math.ceil(sqrt(n * 1.5)), 1, 7)
    local F = { ox = {}, oz = {}, R = 0.45 }
    local i, row = 0, 0
    while i < n do
        local k = min(cols, n - i)
        for c = 0, k - 1 do
            i = i + 1
            F.ox[i] = (c - (k - 1) / 2) * sp + ((row % 2 == 1) and sp * 0.25 or 0)
            F.oz[i] = -row * sp * 0.92
        end
        row = row + 1
    end
    F.R = (min(cols, n) - 1) / 2 * sp + 0.45
    F.depth = (row - 1) * sp * 0.92
    fcache[key] = F
    return F
end

function SIM.state() return S end
local function ev(e) S.events[#S.events + 1] = e end
SIM.ev = function(e) ev(e) end

function SIM.units() return S.sol + S.vet + S.hvy + (S.hero_hp > 0 and 1 or 0) end
-- squad WORTH in soldier-equivalents: what the counter shows. Matches the merge ratios (5 sol = 1 vet, 4 vet = 1 hvy)
-- so merging never lowers it; the hero counts as one body (worth 1) so the number never reads 0 while he stands.
function SIM.worth() return S.sol * D.WORTH.sol + S.vet * D.WORTH.vet + S.hvy * D.WORTH.hvy + (S.hero_hp > 0 and D.WORTH.hero or 0) end
function SIM.bodies()
    -- visible body kinds, front first
    local b = {}
    if S.hero_hp > 0 then b[1] = "hero" end
    for _ = 1, min(S.hvy, D.VIS - #b) do b[#b + 1] = "hvy" end
    for _ = 1, min(S.vet, D.VIS - #b) do b[#b + 1] = "vet" end
    for _ = 1, min(S.sol, D.VIS - #b) do b[#b + 1] = "sol" end
    return b
end
function SIM.firepower()
    local el = 1 + 0.1 * S.up.elite
    return S.sol * D.POWER.sol + (S.vet * D.POWER.vet + S.hvy * D.POWER.hvy) * el + (S.hero_hp > 0 and D.POWER.hero or 0)
end

function SIM.start(n, save)
    local L = D.LEVELS[n]
    S = { lvl = n, L = L, save = save, up = save.up, hero = save.hero, weapon = save.weapon or "rifle",
        t = 0, travel = 0, hold = false, events = {}, foes = {}, props = {}, gates = {}, bullets = {}, missiles = {}, bombs = {}, markers = {},
        allies = {}, beams = {}, sol = 6 + 2 * (save.up.squad or 0), vet = 0, hvy = 0, hero_hp = 10, vdmg = 0, hdmg = 0,
        x = 0, ratep = 0, dmgp = 0, coins = 0, score = 0, kills = 0, air = 0, airs = 0, peak = 0, slow = 0,
        script = D.gen_level(n), si = 1, hpk = L.hpk, over = nil, bacc = 0, slot = 0, juno = 0, boss = nil, bosses_left = 0,
        allyk = (1 + 0.15 * (save.up.ally or 0)) * (1 + 0.3 * (n - 1)), shake = 0, gunship = nil, jet = nil, nid = 0, finish_z = nil }
    -- catch-up assist: a player who reaches a level with fewer upgrades than the curve expects (skipped the shop,
    -- jumped ahead via level select) gets softer foes and a few extra recruits; fully upgraded players get nothing.
    local ups = 0
    for _, v in pairs(save.up) do ups = ups + v end
    local deficit = max(0, (n - 1) * 4.5 - ups)
    -- (straight-fire pass: stronger so even a brand-new save can clear L10; a fully upgraded save is unaffected)
    S.assist = min(0.5, deficit * 0.02)
    S.hpk = L.hpk * (1 - S.assist)
    S.assistdmg = 1 + min(0.6, deficit * 0.02)
    local rec = min(18, floor(deficit * 0.6))
    S.sol = S.sol + rec
    if deficit >= 2 then S.events[#S.events + 1] = { k = "assist", n = rec } end
    S.peak = SIM.worth()
    S.crit = 0.04 * S.up.crit + (S.hero == "hawke" and 0.15 or 0)
    S.gatek = (1 + 0.1 * S.up.gate) * (S.hero == "nova" and 1.35 or 1)
    S.airk = (1 + 0.12 * S.up.air) * (S.hero == "vex" and 1.6 or 1)
    S.armor = 0.05 * S.up.armor
    return S
end

local function newid() S.nid = S.nid + 1; return S.nid end

------------------------------------------------------------------ damage to the squad
function SIM.hurt(d, why)
    if S.over then return end
    local w0 = SIM.worth()
    for _ = 1, d do
        if rand() >= S.armor then
            -- hit points per body = its worth (vet 5 hits, heavy 20), so a hit costs ~1 worth however the squad is merged
            if S.sol > 0 then S.sol = S.sol - 1
            elseif S.vet > 0 then S.vdmg = S.vdmg + 1; if S.vdmg >= D.WORTH.vet then S.vdmg = 0; S.vet = S.vet - 1 end
            elseif S.hvy > 0 then S.hdmg = S.hdmg + 1; if S.hdmg >= D.WORTH.hvy then S.hdmg = 0; S.hvy = S.hvy - 1 end
            elseif S.hero_hp > 0 then S.hero_hp = S.hero_hp - 1 end
        end
    end
    local lost = w0 - SIM.worth()   -- worth actually lost (a dead Veteran = 5)
    ev({ k = "hurt", n = lost, why = why })
    S.shake = max(S.shake, min(0.5, 0.08 + d * 0.02))
    if SIM.units() <= 0 then S.over = "lose"; ev({ k = "lose" }) end
end

local function add_soldiers(v)
    if v >= 0 then S.sol = S.sol + v else SIM.hurt(-v, "gate") end
end
-- merges keep worth exactly (5 sol -> 1 vet = 5, 4 vet -> 1 hvy = 20); they buy firepower and toughness, not numbers
local function automerge()
    local nv, nh = 0, 0
    while S.sol > 60 do S.sol = S.sol - 5; S.vet = S.vet + 1; nv = nv + 1 end
    while S.vet > 30 do S.vet = S.vet - 4; S.hvy = S.hvy + 1; nh = nh + 1 end
    if nv + nh > 0 then ev({ k = "merge", auto = true, nv = nv, nh = nh }) end
end
function SIM.merge_all()
    local nv = floor(S.sol / 5); S.sol = S.sol - nv * 5; S.vet = S.vet + nv
    local nh = floor(S.vet / 4); S.vet = S.vet - nh * 4; S.hvy = S.hvy + nh
    ev({ k = "merge", nv = nv, nh = nh })
end

------------------------------------------------------------------ spawning
local function spawn_foe(t, x, z, extra)
    local E = D.ENEMY[t]
    local k = S.hpk
    local f = { id = newid(), t = t, x = clamp(x, -D.LANE, D.LANE), z = z, hp = E.hp * k, r = E.r, spd = E.spd, dmg = E.dmg, coin = E.coin,
        score = E.score, fly = E.fly, steer = E.steer, aggro = E.aggro, shield = E.shield and E.shield * k or 0, slow = 0, hit = 0, ph = rand() * 6 }
    f.maxhp = f.hp; f.maxsh = f.shield
    if extra then for kk, vv in pairs(extra) do f[kk] = vv end end
    S.foes[#S.foes + 1] = f
    return f
end
SIM.spawn_foe = spawn_foe
local function spawn_boss(b, z)
    local B = D.BOSS[b]
    local k = S.hpk
    -- boss toughness follows the squad you bring (half fixed, half your current damage) so every fight lasts
    local hp = (B.hp * k * 0.5 + (S.dps or 10) * 14) * (S.lvl <= 3 and 0.75 or 1)  -- first boss is a gentler intro
    local f = spawn_foe("brute", 0, z, { boss = b, name = B.name, hp = hp, r = B.r, spd = 2.4, dmg = 999, coin = B.coin, score = B.score,
        stop = B.stop, fly = B.fly, steer = 1.1, atk = 3.0, atk2 = 5.0, arrived = false, enr = 0, shield = 0 })
    f.maxhp = f.hp
    if S.lvl == #D.LEVELS then f.hp = f.hp * 1.5; f.maxhp = f.hp end
    S.boss = f
    ev({ k = "boss", b = b, name = B.name })
    return f
end
SIM.spawn_boss = spawn_boss

local function run_script()
    local lookahead = S.travel + D.SPAWN_Z
    while S.script[S.si] and S.script[S.si].d <= lookahead do
        local e = S.script[S.si]
        S.si = S.si + 1
        local z = e.d - S.travel
        if e.ev == "foe" then
            local f = spawn_foe(e.t, e.x, z, e.lane and { lane = true } or nil)
            if e.hm then f.hp = f.hp * e.hm; f.maxhp = f.hp; f.shield = f.shield * e.hm; f.maxsh = f.shield end
        elseif e.ev == "prop" then
            local p = { id = newid(), t = e.t, x = e.x, z = z, w = e.w, ally = e.ally, hit = 0 }
            if e.t == "crate" then p.hp = e.hp; p.hw = 0.75
            elseif e.t == "container" then p.hp = e.hp; p.hw = 1.3
            elseif e.t == "barricade" then p.hp = e.hp; p.hw = 2.4
            else p.hp = 6 * S.hpk; p.hw = 0.5 end
            p.maxhp = p.hp
            S.props[#S.props + 1] = p
        elseif e.ev == "gates" then
            local rowid = newid()
            for _, g in ipairs(e.row) do
                local gg = { id = newid(), row = rowid, k = g.k, x = g.x, z = z, v = g.v or 0, c0 = math.max(5, math.abs(g.v or 0)), mi = g.mi, per = g.per, maxv = g.maxv, hp = g.hp, prog = 0, hit = 0 }
                if g.k == "lock" then gg.maxhp = g.hp end
                S.gates[#S.gates + 1] = gg
            end
        elseif e.ev == "air" then
            if e.kind == "gunship" then S.gunship = { t = 0, dur = 6.5, cd = 0.6, x = -14, side = (rand() < 0.5) and -1 or 1 }; ev({ k = "gunship" })
            else
                S.props[#S.props + 1] = { id = newid(), t = "crate", x = rand() * 6 - 3, z = 38, drop = 2.2, w = e.w, hp = 12 * S.hpk, maxhp = 12 * S.hpk, hw = 0.75, hit = 0 }
                ev({ k = "drop" })
            end
        elseif e.ev == "hint" then ev({ k = "hint", txt = e.txt })
        elseif e.ev == "boss" then
            local b = spawn_boss(e.b, z + 10)
            S.bosses_left = e.b2 and 2 or 1
            S.boss2 = e.b2
        elseif e.ev == "finish" then S.finish_z = z end
    end
end

------------------------------------------------------------------ hits
local function award(f)
    local c = f.coin * (1 + 0.1 * S.up.bounty)
    S.coins = S.coins + c
    S.score = S.score + f.score
    S.kills = S.kills + 1
end
local splash
local function kill_foe(f, why)
    if f.dead then return end
    f.dead = true
    award(f)
    if not f.boss then S.air = min(1, S.air + 0.007 * S.airk) end
    ev({ k = "kill", t = f.t, x = f.x, z = f.z, fly = f.fly, boss = f.boss, why = why })
    if f.boss then
        S.bosses_left = S.bosses_left - 1
        S.shake = 1.0
        if S.bosses_left > 0 and S.boss2 then
            local b2 = S.boss2; S.boss2 = nil
            S.after = { t = 3.0, b = b2 }
        else S.boss = nil; S.win_t = 2.5 end
    end
end
local function dmg_foe(f, d, why)
    if f.dead then return end
    if rand() < S.crit then d = d * 3 end
    if f.shield > 0 then
        f.shield = f.shield - d
        f.hit = 0.12
        if f.shield <= 0 then d = -f.shield; f.shield = 0; ev({ k = "shieldbreak", x = f.x, z = f.z }) else return end
    end
    f.hp = f.hp - d
    f.hit = 0.12
    if f.hp <= 0 then kill_foe(f, why) end
end
SIM.dmg_foe = dmg_foe

local function explode(x, z, r, d, hurt_squad, kind)
    ev({ k = "boom", x = x, z = z, r = r, kind = kind or "red" })
    S.shake = max(S.shake, 0.35)
    for _, f in ipairs(S.foes) do
        if not f.dead then
            local dx, dz = f.x - x, f.z - z
            if dx * dx + dz * dz < (r + f.r) ^ 2 then dmg_foe(f, f.boss and d * 0.5 or d, "boom") end
        end
    end
    for _, p in ipairs(S.props) do
        if not p.dead and (p.t == "barrel" or p.t == "cryo") then
            local dx, dz = p.x - x, p.z - z
            if dx * dx + dz * dz < r * r then p.hp = 0; p.chain = 0.12 end
        end
    end
    if hurt_squad then
        local F = SIM.formation(min(D.VIS, SIM.units()))
        local dx = abs(S.x - x)
        if z < 2.5 + F.depth * 0.3 and dx < r + F.R then SIM.hurt(hurt_squad, "boom") end
    end
end
splash = explode
SIM.explode = explode

local function cryo(x, z, r)
    ev({ k = "boom", x = x, z = z, r = r, kind = "cryo" })
    for _, f in ipairs(S.foes) do
        if not f.dead then
            local dx, dz = f.x - x, f.z - z
            if dx * dx + dz * dz < r * r then f.slow = 5; dmg_foe(f, 3 * S.hpk, "cryo") end
        end
    end
end

local function prop_destroyed(p)
    p.dead = true
    if p.t == "crate" then
        S.weapon = p.w
        ev({ k = "weapon", w = p.w, x = p.x, z = p.z })
        S.coins = S.coins + 5
    elseif p.t == "container" then
        SIM.free_ally(p.ally, p.x, p.z)
        S.coins = S.coins + 10
    elseif p.t == "barrel" then explode(p.x, p.z, 4.0, 60 * S.hpk, 4, "red")
    elseif p.t == "cryo" then cryo(p.x, p.z, 6.5)
    elseif p.t == "barricade" then ev({ k = "breakwall", x = p.x, z = p.z }); S.coins = S.coins + 8 end
end

local function gate_color(g)
    if g.k == "lock" then return "grey" end
    if g.k == "merge" then return "gold" end
    if g.k == "mul" then return (g.mi <= 3) and "red" or "green" end
    if g.k == "trap" then return g.flip and "red" or "orange" end
    return (g.v < 0) and "red" or "blue"
end
SIM.gate_color = gate_color
function SIM.gate_label(g)
    if g.k == "lock" then return "x3", "LOCKED" end
    if g.k == "merge" then return "MERGE", "5 = 1 Elite" end
    if g.k == "mul" then return D.MULTXT[g.mi], nil end
    if g.k == "rate" then return (g.v >= 0 and "+" or "") .. g.v .. "%", "Fire Rate" end
    if g.k == "dmg" then return (g.v >= 0 and "+" or "") .. g.v .. "%", "Damage" end
    if g.k == "trap" then
        if g.flip then return tostring(g.v), "Overloaded!" end
        return "+" .. g.v, "Max " .. g.maxv
    end
    return (g.v >= 0 and "+" or "") .. g.v, nil
end

-- damage needed for the next step: climbing gets steeper the higher a gate already is
-- crits now count on gates too; the cost carries the average crit gain (1 + 2*crit) so fill pace stays as before
function SIM.gate_cost(g)
    local ck = 1 + 2 * (S.crit or 0)
    if g.k == "mul" then return ck * g.per * 2 ^ math.max(0, g.mi - 3) end
    if g.k == "rate" or g.k == "dmg" then return ck * g.per * (1 + math.max(0, g.v) / 15) ^ 2 end
    local c = g.c0 or 6
    return ck * g.per * (1 + math.max(0, g.v) / c) ^ 2
end
-- every point of squad damage that reaches a gate counts (bullets, pellets, laser, rocket hits and splash), with
-- the same crit roll as on foes; upgrades and catch-up assist are already inside the shot's damage. Allies,
-- gunship and airstrikes never call this.
local function hit_gate(g, d)
    g.hit = 0.1
    if rand() < S.crit then d = d * 3 end
    S.gdmg = (S.gdmg or 0) + d
    if g.k == "lock" then
        g.hp = g.hp - d
        if g.hp <= 0 then g.k = "mul"; g.mi = 5; ev({ k = "unlock", x = g.x, z = g.z }) end
        return
    end
    if g.k == "merge" or g.flip then return end
    g.prog = g.prog + d * S.gatek
    while g.prog >= SIM.gate_cost(g) do
        g.prog = g.prog - SIM.gate_cost(g)
        if g.k == "mul" then
            if g.mi < #D.MUL then g.mi = g.mi + 1; ev({ k = "gatetick", x = g.x, z = g.z, up = true }) else g.prog = 0 end
        elseif g.k == "rate" or g.k == "dmg" then
            g.v = min(g.v + 5, 60); ev({ k = "gatetick", x = g.x, z = g.z })
        else
            g.v = g.v + 1
            ev({ k = "gatetick", x = g.x, z = g.z, v = g.v })
            if g.k == "trap" and g.v > g.maxv then
                g.flip = true; g.v = -2 * g.v; g.prog = 0
                ev({ k = "flip", x = g.x, z = g.z })
                return
            end
        end
    end
end

------------------------------------------------------------------ allies
function SIM.free_ally(a, x, z)
    local A = D.ALLY[a]
    local al = { t = a, x = x, z = z, cd = 0.5, life = A.life, hp = A.hp and A.hp * S.allyk or nil, ang = 0, side = (x >= S.x) and 1 or -1, id = newid() }
    if a == "drones" then al.n = A.n end
    S.allies[#S.allies + 1] = al
    ev({ k = "ally", t = a, name = A.name, x = x, z = z })
end
local function nearest_foe(x, z, maxd, prefer_big)
    local best, bs = nil, 1e9
    for _, f in ipairs(S.foes) do
        if not f.dead and f.z > z - 1 and f.z - z < maxd and f.z < D.SPAWN_Z - 8 then
            local s = (f.z - z) + abs(f.x - x) * 0.5
            if prefer_big then s = s - f.hp * 0.05 - (f.boss and 100 or 0) end
            if s < bs then bs, best = s, f end
        end
    end
    return best
end
SIM.nearest_foe = nearest_foe
local function ally_shot(al, f, d, kind)
    dmg_foe(f, d, "ally")
    ev({ k = "trace", x0 = al.x, z0 = al.z, y0 = al.y or 1.2, x1 = f.x, z1 = f.z, y1 = f.fly and 2.2 or 1.0, kind = kind })
end
local function update_allies(dt)
    local F = SIM.formation(min(D.VIS, SIM.units()))
    for i = #S.allies, 1, -1 do
        local al = S.allies[i]
        local A = D.ALLY[al.t]
        al.cd = al.cd - dt
        -- follow the squad
        if al.t == "turret" then
            al.tx = clamp(S.x + al.side * (F.R + 1.3), -D.LANE, D.LANE)
            if abs(al.tx - S.x) < F.R + 0.6 then al.side = -al.side end
            al.tz = 0.4
        elseif al.t == "heli" then
            al.tx = clamp(S.x + al.side * 2.5 + math.sin(S.t * 0.7) * 1.5, -6, 6); al.tz = 4 + math.sin(S.t * 0.43) * 1.5; al.y = 7
            al.life = al.life - dt
            if al.life <= 0 then table.remove(S.allies, i); ev({ k = "allyleave", t = "heli" }); goto continue end
        elseif al.t == "mech" then al.tx = S.x; al.tz = 4.5 + F.R * 0.2
        elseif al.t == "sniper" then al.tx = (S.x > 0) and -4.6 or 4.6; al.tz = -2.5; al.y = 3.2
        else al.tx = S.x; al.tz = 0.5; al.y = 2.5 end
        al.x = al.x + (al.tx - al.x) * min(1, dt * 3)
        al.z = al.z + (al.tz - al.z) * min(1, dt * 2.5)
        if al.t == "turret" or al.t == "mech" or al.t == "drones" then
            if al.cd <= 0 then
                al.cd = 0.14
                local f = nearest_foe(al.x, al.z, 70)
                if f then
                    al.ang = math.atan2(f.x - al.x, f.z - al.z)
                    local nn = al.n or 1
                    ally_shot(al, f, A.dps * 0.14 * S.allyk * nn, al.t)
                end
            end
        elseif al.t == "sniper" then
            if al.cd <= 0 then
                local f = nearest_foe(al.x, al.z, 95, true)
                if f then al.cd = A.every; al.ang = math.atan2(f.x - al.x, f.z - al.z); ally_shot(al, f, A.shot * S.allyk * S.hpk ^ 0.5, "sniper") end
            end
        elseif al.t == "heli" then
            if al.cd <= 0 then
                local f = nearest_foe(al.x, al.z, 80, true)
                if f then
                    al.cd = A.every
                    S.missiles[#S.missiles + 1] = { x = al.x, z = al.z, y = 6.5, tgt = f, tx = f.x, tz = f.z, spd = 30, dmg = A.rocket * S.allyk, r = 2.6, id = newid() }
                    ev({ k = "missile" })
                end
            end
        end
        if al.t == "mech" and al.hp <= 0 then table.remove(S.allies, i); explode(al.x, al.z, 3, 40 * S.hpk, nil, "red"); ev({ k = "allydown", t = "mech" }) end
        ::continue::
    end
end

------------------------------------------------------------------ squad fire
local function fire(dt)
    local W = D.WEAPONS[S.weapon]
    local units = SIM.units()
    if units <= 0 then return end
    local nvis = min(units, D.VIS)
    local F = SIM.formation(nvis)
    local dmgmul = (1 + 0.12 * S.up.fire) * (1 + S.dmgp) * (S.hero == "rook" and 1.1 or 1) * (S.assistdmg or 1)
    local ratemul = (1 + 0.07 * S.up.rate) * (1 + S.ratep) * (S.hero == "bruno" and 1.25 or 1)
    local dps = SIM.firepower() * W.dps * dmgmul * ratemul
    S.dps = dps
    if W.beam then
        local nb = min(nvis, 6)
        S.beams = {}
        local per = dps * dt / nb
        for b = 1, nb do
            local slot = 1 + floor((b - 0.5) / nb * nvis)
            local bx = S.x + F.ox[slot]
            local bz0 = F.oz[slot] + 0.6
            -- collect hits in this column
            local hits = {}
            for _, f in ipairs(S.foes) do if not f.dead and abs(f.x - bx) < f.r + 0.15 and f.z > bz0 and f.z - bz0 < W.range then hits[#hits + 1] = { z = f.z, f = f } end end
            for _, p in ipairs(S.props) do if not p.dead and abs(p.x - bx) < p.hw and p.z > bz0 and p.z - bz0 < W.range then hits[#hits + 1] = { z = p.z, p = p } end end
            for _, g in ipairs(S.gates) do if not g.passed and abs(g.x - bx) < 2.3 and g.z > bz0 and g.z - bz0 < W.range then hits[#hits + 1] = { z = g.z, g = g } end end
            table.sort(hits, function(a, c) return a.z < c.z end)
            local endz = bz0 + W.range
            local pierce = W.pierce
            for _, h in ipairs(hits) do
                if h.f then dmg_foe(h.f, per, "laser")
                elseif h.p then h.p.hp = h.p.hp - per; h.p.hit = 0.1
                else hit_gate(h.g, per * D.GATE_PASS) end
                if not h.g then pierce = pierce - 1 end
                if pierce <= 0 or h.p then endz = h.z; break end
            end
            S.beams[b] = { x = bx, z0 = bz0, z1 = endz, slot = slot }
        end
        S.fire_t = (S.fire_t or 0) + dt
        return
    end
    S.beams = nil
    -- straight fire: every soldier shoots straight down the lane from where he stands. Rifle/minigun get a tiny
    -- jitter, the shotgun throws a fixed fan per volley, only Rockets lock on (a narrow forward cone) and curve in.
    local pellets = W.pellets or 1
    local bps = min(nvis / (W.rate / ratemul) * pellets, D.BULLETS_PS)
    local bd = dps / bps
    S.bacc = S.bacc + bps * dt
    while S.bacc >= 1 do
        S.bacc = S.bacc - 1
        S.pj = ((S.pj or 0) % pellets) + 1
        if S.pj == 1 or S.slot > nvis then S.slot = S.slot % nvis + 1 end
        local s = S.slot
        local a
        if pellets > 1 then a = math.rad(((S.pj - 1) / (pellets - 1) * 2 - 1) * W.spread + (rand() - 0.5) * 0.6)
        else a = math.rad((rand() - 0.5) * 2 * W.spread) end
        local bx0, bz0 = S.x + F.ox[s], F.oz[s] + 0.7
        local b = { x = bx0, z = bz0, vx = math.sin(a) * W.speed, vz = math.cos(a) * W.speed, d = bd, range = W.range, splash = W.splash, slot = s, id = newid() }
        if W.homing then
            -- lock on: closest foe inside a narrow forward cone (half-angle ~22 deg, at most 5 m to the side)
            local best, bz = nil, 1e9
            for _, f in ipairs(S.foes) do
                if not f.dead and f.z > bz0 + 3 and f.z < W.lock then
                    local dz = f.z - bz0
                    if abs(f.x - bx0) < min(dz * 0.4, 5) + f.r and dz < bz then bz, best = dz, f end
                end
            end
            if best then b.tgt = best; best.lockt = 0.6 end
            b.turn = W.turn
        end
        b.z0 = b.z
        S.bullets[#S.bullets + 1] = b
        S.shots = (S.shots or 0) + 1
        if S.pj == 1 then ev({ k = "shot", slot = s }) end
    end
end

-- a rocket's blast also fills any gate it overlaps (once per rocket per gate, shared with its fly-through hit)
local function splash_gates(b, x, z)
    local r = b.splash
    for _, g in ipairs(S.gates) do
        if not g.passed and abs(g.z - z) < r and abs(g.x - x) < 2.3 + r then
            b.gh = b.gh or {}
            if not b.gh[g.id] then b.gh[g.id] = true; hit_gate(g, b.d * D.GATE_PASS) end
        end
    end
end

local function step_bullets(dt)
    local bl = S.bullets
    local i = 1
    while i <= #bl do
        local b = bl[i]
        local z0 = b.z
        if b.tgt then
            local t = b.tgt
            if t.dead then b.tgt = nil
            else
                -- steer the heading toward the locked target at a capped turn rate: the trail visibly curves
                local h = math.atan2(b.vx, b.vz)
                local want = math.atan2(t.x - b.x, t.z - b.z)
                local dh = (want - h + math.pi) % (2 * math.pi) - math.pi
                h = h + clamp(dh, -b.turn * dt, b.turn * dt)
                local sp = sqrt(b.vx * b.vx + b.vz * b.vz)
                b.vx, b.vz = math.sin(h) * sp, math.cos(h) * sp
                t.lockt = max(t.lockt or 0, 0.25)
            end
        end
        b.x = b.x + b.vx * dt
        b.z = b.z + b.vz * dt
        local hit, hz, kind = nil, 1e9, nil
        local bx = b.x
        for _, f in ipairs(S.foes) do
            if not f.dead and f.z >= z0 - f.r and f.z - f.r <= b.z and abs(f.x - bx) < f.r + 0.1 and f.z < hz and f.z < D.SPAWN_Z - 5 then hit, hz, kind = f, f.z, 1 end
        end
        for _, p in ipairs(S.props) do
            if not p.dead and not p.drop and p.z >= z0 - 0.6 and p.z - 0.6 <= b.z and abs(p.x - bx) < p.hw and p.z < hz then hit, hz, kind = p, p.z, 2 end
        end
        -- gates never stop a projectile: it scores the gate once on the way through and keeps flying
        for _, g in ipairs(S.gates) do
            if not g.passed and g.z >= z0 and g.z <= b.z and abs(g.x - bx) < 2.3 and g.z < hz then
                b.gh = b.gh or {}
                if not b.gh[g.id] then b.gh[g.id] = true; hit_gate(g, b.d * D.GATE_PASS); ev({ k = "impact", x = bx, z = g.z - 0.3, kind = 3, thru = true }) end
            end
        end
        local dead = false
        if hit then
            dead = true
            if kind == 1 then
                if b.splash then explode(bx, hz, b.splash, b.d, nil, "rocket"); splash_gates(b, bx, hz) else dmg_foe(hit, b.d, "bullet") end
            elseif kind == 2 then
                hit.hp = hit.hp - b.d; hit.hit = 0.1
                if b.splash then explode(bx, hz, b.splash, b.d, nil, "rocket"); splash_gates(b, bx, hz) end
            end
            ev({ k = "impact", x = bx, z = hz - 0.3, kind = kind, t = (kind == 1) and hit.t or nil, fly = (kind == 1) and hit.fly or nil })
        elseif b.z - b.z0 > b.range then dead = true end
        if dead then bl[i] = bl[#bl]; bl[#bl] = nil else i = i + 1 end
    end
end

------------------------------------------------------------------ boss behaviour
local function boss_ai(f, dt)
    if not f.arrived then
        if f.z <= f.stop then
            f.arrived = true; S.hold = true; ev({ k = "bossarrive", b = f.boss })
            -- clear the arena: leftover gates sink away so the whole squad can fire at the boss
            for _, g in ipairs(S.gates) do if not g.passed then g.passed = true; g.gone = 0 end end
        end
        return
    end
    f.enr = f.enr + dt
    -- strafes across the lane (only loosely following you): keep lining up with it while dodging its attacks
    local btx = clamp(math.sin(f.enr * 0.42 + f.id) * 2.8 + S.x * 0.35, -3.6, 3.6)
    f.x = f.x + clamp(btx - f.x, -1.4 * dt, 1.4 * dt)
    f.atk = f.atk - dt
    f.atk2 = f.atk2 - dt
    local dk = (1 + 0.12 * (S.lvl - 1))
    local B = f.boss
    if B == "goliath" then
        if f.atk <= 0 then
            f.atk = max(2.4, 3.8 - f.enr * 0.02)
            S.markers[#S.markers + 1] = { x = S.x, z = 0.4, r = 2.4, t = 1.35, t0 = 1.35, dmg = floor(5 * dk), kind = "slam", from = f }
            ev({ k = "windup", b = B })
        end
        if f.atk2 <= 0 then f.atk2 = 7; for j = 1, 6 do spawn_foe("runner", f.x + (j - 3.5) * 1.1, f.z - 2) end; ev({ k = "roar" }) end
    elseif B == "ironclad" then
        if f.atk <= 0 then
            f.atk = max(2.8, 4.4 - f.enr * 0.02)
            for j = -1, 1 do S.markers[#S.markers + 1] = { x = clamp(S.x + j * 2.6 + (rand() - 0.5), -5, 5), z = 0.4 + rand() * 1.5, r = 1.8, t = 1.6 + j * 0.15, t0 = 1.6, dmg = floor(4 * dk), kind = "rocket", from = f } end
            ev({ k = "volley", b = B })
        end
        if f.atk2 <= 0 then f.atk2 = 8; for j = 1, 3 do spawn_foe("shield", (j - 2) * 3, f.z - 2) end end
    elseif B == "wasp" then
        if f.atk <= 0 then
            f.atk = max(1.6, 2.6 - f.enr * 0.015)
            spawn_foe("orb", f.x, f.z - 1.5, { hp = 5 * S.hpk ^ 0.7, maxhp = 5 * S.hpk ^ 0.7 })
            ev({ k = "spit" })
        end
        if f.atk2 <= 0 then f.atk2 = 6.5; for j = 1, 4 do spawn_foe("flyer", f.x + (j - 2.5) * 1.6, f.z - 1) end; ev({ k = "roar" }) end
    end
    -- the boss creeps forward slowly once it has stood its ground for a while
    if f.enr > 25 then f.z = f.z - dt * 0.25 * (1 + (f.enr - 25) / 30) end
    if f.z < 3 then SIM.hurt(9999, "boss") end
end

------------------------------------------------------------------ main step
function SIM.step(dt, input)
    if not S then return end
    S.t = S.t + dt
    if S.over then return end
    S.shake = max(0, S.shake - dt * 1.6)
    -- steering
    local nvis = min(SIM.units(), D.VIS)
    local F = SIM.formation(max(1, nvis))
    local lim = D.LANE - F.R * 0.6
    if input.tx then S.x = S.x + clamp(input.tx - S.x, -D.STEER * dt, D.STEER * dt) end
    if input.dir and input.dir ~= 0 then S.x = S.x + input.dir * D.STEER_KEY * dt end
    S.x = clamp(S.x, -lim, lim)
    -- world scroll
    local v = S.hold and 0 or D.SPEED
    S.travel = S.travel + v * dt
    S.v = v
    run_script()
    if S.after then S.after.t = S.after.t - dt; if S.after.t <= 0 then spawn_boss(S.after.b, 40); S.after = nil end end
    -- hero perks
    if S.hero == "juno" then S.juno = S.juno + dt; if S.juno >= 3 then S.juno = 0; S.sol = S.sol + 1; ev({ k = "recruit" }) end end
    automerge()
    S.peak = max(S.peak, SIM.worth())
    S.peakb = max(S.peakb or 0, SIM.units())   -- bodies (reports only)
    fire(dt)
    step_bullets(dt)
    update_allies(dt)
    -- foes
    local fr = F.R
    for _, f in ipairs(S.foes) do
        if not f.dead then
            f.hit = max(0, f.hit - dt)
            f.slow = max(0, f.slow - dt)
            local sp = (f.slow > 0) and 0.35 or 1
            if f.boss then
                if not f.arrived then f.z = f.z - (v + 4) * dt end
                boss_ai(f, dt)
            else
                f.z = f.z - (v + f.spd * sp) * dt
                f.lockt = max(0, (f.lockt or 0) - dt)
                if f.z < (f.aggro or 22) and not f.lane then
                    local tx = S.x
                    f.x = clamp(f.x + clamp(tx - f.x, -f.steer * dt * sp, f.steer * dt * sp), -D.LANE, D.LANE)
                end
                if f.fly then f.x = clamp(f.x + math.sin(S.t * 2.1 + f.ph) * dt * 1.2, -D.LANE, D.LANE) end
                -- ally mech blocks
                for _, al in ipairs(S.allies) do
                    if al.t == "mech" and abs(f.z - al.z) < f.r + 0.8 and abs(f.x - al.x) < f.r + 1.1 then
                        al.hp = al.hp - f.dmg * 6; f.dead = true; S.coins = S.coins + f.coin * 0.5
                        ev({ k = "stomp", x = f.x, z = f.z, t = f.t }); break
                    end
                end
                if not f.dead and f.z <= 0.6 + f.r and f.z > -F.depth - 1 and abs(f.x - S.x) < fr + f.r * 0.8 then
                    f.dead = true
                    ev({ k = "contact", x = f.x, z = f.z, t = f.t })
                    SIM.hurt(f.dmg, f.t)
                elseif f.z < -F.depth - 3 then f.dead = true; f.escaped = true end
            end
        end
    end
    -- props
    for _, p in ipairs(S.props) do
        if not p.dead then
            p.hit = max(0, (p.hit or 0) - dt)
            if p.drop then p.drop = max(0, p.drop - dt); if p.drop == 0 then p.drop = nil; ev({ k = "land", x = p.x, z = p.z }) end
            else p.z = p.z - v * dt end
            if p.chain then p.chain = p.chain - dt; if p.chain <= 0 then p.chain = nil; prop_destroyed(p) end
            elseif p.hp <= 0 then prop_destroyed(p)
            elseif p.z <= 0.5 + 0.6 then
                if abs(p.x - S.x) < fr + p.hw then
                    if p.t == "barrel" then p.dead = true; explode(p.x, p.z, 3.5, 30 * S.hpk, 5, "red")
                    elseif p.t == "cryo" then p.dead = true; cryo(p.x, p.z, 5)
                    elseif p.t == "barricade" then p.dead = true; ev({ k = "breakwall", x = p.x, z = p.z, crash = true }); SIM.hurt(math.ceil(p.hp / (6 * S.hpk)), "wall")
                    elseif p.z < -2 then p.dead = true end
                elseif p.z < -3 then p.dead = true end
            end
        end
    end
    -- gates
    for _, g in ipairs(S.gates) do
        g.hit = max(0, g.hit - dt)
        if not g.passed then g.z = g.z - v * dt end
    end
    local passed_row = nil
    for _, g in ipairs(S.gates) do
        if not g.passed and g.z <= 0.2 then
            passed_row = g.row
            break
        end
    end
    if passed_row then
        local best, bd = nil, 1e9
        for _, g in ipairs(S.gates) do
            if g.row == passed_row then
                local d = abs(S.x - g.x)
                if d < bd then bd, best = d, g end
            end
        end
        if best and bd > 2.4 then best = nil end
        for _, g in ipairs(S.gates) do if g.row == passed_row then g.passed = true; g.gone = 0 end end
        if best then SIM.apply_gate(best) end
    end
    for i = #S.gates, 1, -1 do
        local g = S.gates[i]
        if g.passed then g.gone = g.gone + dt; g.z = g.z - D.SPEED * dt; if g.gone > 1.2 then table.remove(S.gates, i) end end
    end
    -- missiles (heli / gunship)
    for i = #S.missiles, 1, -1 do
        local m = S.missiles[i]
        if m.tgt and not m.tgt.dead then m.tx, m.tz = m.tgt.x, m.tgt.z end
        local dx, dz, dy = m.tx - m.x, m.tz - m.z, 1 - m.y
        local d = sqrt(dx * dx + dz * dz + dy * dy)
        local st = m.spd * dt
        if d <= st then
            explode(m.tx, m.tz, m.r, m.dmg * S.hpk ^ 0.6, nil, "rocket")
            table.remove(S.missiles, i)
        else m.x = m.x + dx / d * st; m.z = m.z + dz / d * st; m.y = m.y + dy / d * st end
    end
    -- boss markers
    for i = #S.markers, 1, -1 do
        local mk = S.markers[i]
        mk.t = mk.t - dt
        if mk.t <= 0 then
            table.remove(S.markers, i)
            ev({ k = "boom", x = mk.x, z = mk.z, r = mk.r, kind = mk.kind })
            local dx = abs(S.x - mk.x)
            if dx < mk.r + F.R * 0.5 then SIM.hurt(mk.dmg, "boss") elseif dx < mk.r + F.R then SIM.hurt(floor(mk.dmg / 2 + 0.5), "boss") end
            S.shake = max(S.shake, 0.6)
        end
    end
    -- airstrike
    S.air = min(1, S.air + dt / 24 * S.airk)
    if input.strike and S.air >= 1 and not S.jet then SIM.airstrike() end
    if S.jet then
        S.jet.t = S.jet.t + dt
        while S.jet.bombs[1] and S.jet.bombs[1].at <= S.jet.t do
            local b = table.remove(S.jet.bombs, 1)
            S.bombs[#S.bombs + 1] = { x = b.x, z = b.z, y = 22, vy = -4 }
            ev({ k = "bombdrop" })
        end
        if S.jet.t > 4 then S.jet = nil end
    end
    for i = #S.bombs, 1, -1 do
        local b = S.bombs[i]
        b.vy = b.vy - 30 * dt; b.y = b.y + b.vy * dt; b.z = b.z - v * dt
        if b.y <= 0.4 then table.remove(S.bombs, i); explode(b.x, b.z, 4.2, 70 * S.hpk * (1 + 0.1 * S.up.air), nil, "bomb") end
    end
    -- scripted gunship pass
    if S.gunship then
        local gs = S.gunship
        gs.t = gs.t + dt
        gs.cd = gs.cd - dt
        if gs.cd <= 0 and gs.t > 1 and gs.t < gs.dur - 1 then
            gs.cd = 0.35
            local f = nearest_foe(0, 0, 85, true)
            if f then
                S.missiles[#S.missiles + 1] = { x = gs.side * (-9 + gs.t * 3), z = 8, y = 9, tgt = f, tx = f.x, tz = f.z, spd = 34, dmg = 22, r = 2.4, id = newid() }
                ev({ k = "missile" })
            end
        end
        if gs.t > gs.dur then S.gunship = nil end
    end
    -- cleanup dead
    local fo = S.foes
    for i = #fo, 1, -1 do if fo[i].dead then table.remove(fo, i) end end
    local pr = S.props
    for i = #pr, 1, -1 do if pr[i].dead then table.remove(pr, i) end end
    -- win
    if S.win_t then S.win_t = S.win_t - dt; if S.win_t <= 0 then SIM.finish(true) end end
    if S.finish_z then
        S.finish_z = S.finish_z - v * dt
        if S.finish_z <= 0 and not S.win_t then
            local any = false
            for _, f in ipairs(S.foes) do if f.z > 0 then any = true end end
            if not any then S.win_t = 0.8; ev({ k = "finishline" }) else S.finish_z = 0 end
        end
    end
end

function SIM.airstrike()
    S.air = 0
    S.airs = S.airs + 1
    local nb = 6 + S.up.air
    local tg = {}
    for _, f in ipairs(S.foes) do if not f.dead and f.z > 4 and f.z < 85 then tg[#tg + 1] = f end end
    table.sort(tg, function(a, b) return (a.boss and 1e6 or a.hp) > (b.boss and 1e6 or b.hp) end)
    local bombs = {}
    for j = 1, nb do
        local f = tg[((j - 1) % max(1, #tg)) + 1]
        local x = f and (f.x + (rand() - 0.5) * 1.5) or (rand() * 8 - 4)
        local z = f and (f.z - 2 + rand() * 2) or (12 + j * 7)
        bombs[j] = { x = x, z = z + 0.5 * 8 * 0.35 * 0, at = 0.5 + j * 0.13 }
    end
    S.jet = { t = 0, bombs = bombs }
    ev({ k = "airstrike" })
end

function SIM.apply_gate(g)
    local before = SIM.worth()
    if g.k == "add" or g.k == "trap" then add_soldiers(g.v)
    elseif g.k == "mul" then
        -- multiply the whole squad's WORTH (new troops arrive as soldiers, automerge folds them up), so merged
        -- squads are never punished; a divide gate takes worth via hits (1 hit ~ 1 worth)
        local m = D.MUL[g.mi]
        if m > 1 then S.sol = S.sol + floor(before * (m - 1) + 0.5)
        else SIM.hurt(before - max(1, floor(before * m + 0.5)), "gate") end
    elseif g.k == "lock" then -- passed while still locked: nothing
    elseif g.k == "rate" then S.ratep = max(-0.5, S.ratep + g.v / 100)
    elseif g.k == "dmg" then S.dmgp = max(-0.5, S.dmgp + g.v / 100)
    elseif g.k == "merge" then SIM.merge_all() end
    local good = (g.k == "merge") or ((g.k == "rate" or g.k == "dmg") and g.v >= 0) or (g.k == "mul" and g.mi > 3) or ((g.k == "add" or g.k == "trap") and g.v >= 0)
    if g.k == "lock" then good = nil end
    ev({ k = "gate", good = good, mult = g.k == "mul" and g.mi > 3, g = g, delta = SIM.worth() - before })
end

function SIM.finish(win)
    if S.over then return end
    S.over = win and "win" or "lose"
    local surv = SIM.worth()
    S.surv = surv
    if win then
        S.bonus = 40 + 20 * S.lvl + floor(surv / 10)
        S.coins = S.coins + S.bonus
        S.score = S.score + surv * 2   -- worth is ~5-10x bodies; keeps score scale near the old body-based one
        local r = surv / max(1, S.peak)
        S.stars = (r >= 0.55) and 3 or ((r >= 0.25) and 2 or 1)
    end
    ev({ k = win and "win" or "lose" })
end
end
do -- 04b_bot.lua
------------------------------------------------------------------ 04b_bot: autopilot (title-screen attract run, harness, tools/simtest)
-- Fire goes straight, so the bot steers: it scores candidate lane positions by what the squad's fire strip would
-- cover (foes it can kill in time, the gate it wants, crates/containers, the boss) minus what would hit it
-- (foes it can't kill before contact, walls, barrels, boss strike markers), then heads for the best one.
local D, SIM = G.D, G.SIM
local BOT = {}
G.BOT = BOT
local abs, min, max = math.abs, math.min, math.max
local function cover(x, half, ox, r) -- 0..1: how much of a target of radius r sits inside the fire strip
    local d = abs(ox - x) - half - r
    if d <= -0.3 then return 1 elseif d >= 0.3 then return 0 end
    return (0.3 - d) / 0.6
end
local function gate_value(g, S, units, gain)
    if g.k == "add" then return g.v + gain / g.per
    elseif g.k == "trap" then
        if g.flip then return g.v end
        local v = g.v + gain / g.per
        return (v > g.maxv) and -2 * v or v
    elseif g.k == "mul" then local mi = min(#D.MUL, g.mi + math.floor(gain / g.per)); return units * (D.MUL[mi] - 1)
    elseif g.k == "lock" then return (g.hp < gain) and units * 2 or -1
    elseif g.k == "merge" then return units * 0.05 end   -- worth unchanged, small firepower/toughness gain
    return (g.v + gain / g.per * 5) * units / 40
end
function BOT.target(S)
    local units = SIM.units()
    local nvis = min(units, D.VIS)
    local F = SIM.formation(max(1, nvis))
    local lim = D.LANE - F.R * 0.6
    local half = max(0.1, F.R - 0.45)
    local dps = S.dps or units
    local v = S.v or D.SPEED
    -- candidates
    local nc = 33
    local best, bs = S.x, -1e18
    -- gate row: work out each gate's value once, assuming all fire goes into it from now on
    local row, rz = nil, 1e9
    for _, g in ipairs(S.gates) do if not g.passed and g.z > 0.3 and g.z < 75 and g.z < rz then rz, row = g.z, g.row end end
    local gl = {}
    if row then
        local tarr = rz / max(0.1, v)
        for _, g in ipairs(S.gates) do
            if g.row == row then
                local val = gate_value(g, S, SIM.worth(), dps * tarr * 0.75 * S.gatek)   -- gates scale worth
                local wv = 2 - min(1.5, rz / 50) -- the closer the row, the more it matters
                gl[#gl + 1] = { g = g, val = val, w = wv }
            end
        end
    end
    local share = min(1, 0.95 / (2 * half + 0.74)) -- fraction of the squad's fire one runner-size target soaks up
    for c = 0, nc - 1 do
        local x = -lim + 2 * lim * c / (nc - 1)
        local sc = -0.08 * abs(x - S.x)
        for _, f in ipairs(S.foes) do
            if not f.dead and f.z > 0 and f.z < 50 then
                local tz = f.z / max(0.5, v + (f.spd or 2))
                local cv = cover(x, half, f.x, f.r)
                local ehp = f.hp + (f.shield or 0)
                if f.boss then
                    if f.arrived then sc = sc + 12 * cv end
                else
                    local kill = min(1, dps * share * max(1, f.r * 2) * tz / max(1, ehp))
                    local urg = (f.z < 30) and 1 or 0.5
                    sc = sc + cv * (kill * (f.dmg * 1.4 + f.coin * 0.15) + 0.2) * urg
                    -- contact: will it reach the squad? steering foes close in on you, lane keepers don't
                    local reach = (f.lane or f.boss) and 0 or (f.steer or 0) * min(tz, (f.aggro or 22) / max(1, v + (f.spd or 2)))
                    local dx = abs(f.x - x) - (F.R + f.r * 0.8) - reach
                    if dx < 0.4 and f.z < 28 then sc = sc - f.dmg * (1 - cv * kill) * 1.6 * urg end
                end
            end
        end
        for _, gg in ipairs(gl) do
            local g = gg.g
            -- the gate we'd pass is the nearest one within 2.4 m
            local near, nd = nil, 1e9
            for _, h in ipairs(gl) do local d = abs(h.g.x - x); if d < nd then nd, near = d, h end end
            if near == gg and nd < 2.4 then sc = sc + gg.val * gg.w * (1 - nd / 6) end
            if gg.val > 0 then sc = sc + gg.w * 0.6 * cover(x, half, g.x, 2.2) end
        end
        for _, p in ipairs(S.props) do
            if not p.dead and p.z > 0 and p.z < 55 then
                local cv = cover(x, half, p.x, p.hw - 0.2)
                if p.t == "crate" then sc = sc + cv * 3
                elseif p.t == "container" then sc = sc + cv * 6
                elseif p.t == "barricade" then
                    sc = sc + cv * 0.8
                    if p.z < 26 and abs(p.x - x) < F.R + p.hw + 0.3 then sc = sc - math.ceil(p.hp / (6 * S.hpk)) * (p.z < 14 and 1.5 or 0.6) end
                elseif p.t == "barrel" or p.t == "cryo" then
                    if p.z < 22 and abs(p.x - x) < F.R + p.hw + 0.4 then sc = sc - (p.t == "barrel" and 6 or 1) end
                end
            end
        end
        for _, mk in ipairs(S.markers) do
            local dx = abs(x - mk.x)
            if dx < mk.r + F.R * 0.5 + 0.4 then sc = sc - mk.dmg * 4 elseif dx < mk.r + F.R + 0.4 then sc = sc - mk.dmg * 1.5 end
        end
        if sc > bs then bs, best = sc, x end
    end
    return best
end
end
------------------------------------------------------------------ 05_render: draws the sim state (lane x -> world X = -x), event -> fx/sfx
do
local D, SIM = G.D, G.SIM
local FX = G.FX
local R = { kinds = {}, sl = {}, kick = {}, coins = {}, streaks = {}, debris = {}, popups = {}, sfxt = {}, fxbudget = 0, t = 0 }
G.R = R
local deg = math.deg
local function use(kind) if not R.kinds[kind] then R.kinds[kind] = true end; return P_get(kind) end
local function xf(n, x, y, z, rx, ry, rz, s, sy, sz)
    n:set_transform(vec3(x, y, z), vec3(rx or 0, ry or 0, rz or 0), vec3(s or 1, sy or s or 1, sz or s or 1))
end
-- rate-limited sound
local function sfxr(name, gap)
    local t = R.sfxt[name] or -1
    if R.t - t >= (gap or 0.06) then R.sfxt[name] = R.t; sfx(name) end
end
G.sfxr = sfxr
local function fxok(cost) if R.fxbudget >= (cost or 1) then R.fxbudget = R.fxbudget - (cost or 1); return true end return false end

-- body + two legs, hip pivot; yaw in degrees; swing in degrees
local RIG = {
    sol = { leg = "sol_leg", hip = 0.45, hx = 0.1 }, vet = { leg = "vet_leg", hip = 0.45, hx = 0.1 }, hero = { leg = "sol_leg", hip = 0.45, hx = 0.1 },
    hvy = { leg = "hvy_leg", hip = 0.66, hx = 0.17 }, runner = { leg = "run_leg", hip = 0.45, hx = 0.1 }, shield = { leg = "run_leg", hip = 0.45, hx = 0.1 },
    brute = { leg = "brute_leg", hip = 0.95, hx = 0.32 }, goliath = { leg = "gol_leg", hip = 0.95, hx = 0.32 }, ironclad = { leg = "mech_leg", hip = 1.17, hx = 0.5 },
    amech = { leg = "amech_leg", hip = 0.73, hx = 0.31 }, sniper = { leg = "sol_leg", hip = 0.45, hx = 0.1 },
}
local function rig(body, rk, x, y, z, yaw, swing, sc, bob, lean, flash, roll)
    local r = RIG[rk]
    sc = sc or 1
    local fs = sc * (1 + (flash or 0))
    xf(use(body), x, y + (bob or 0) * sc, z, lean or 0, yaw, roll or 0, fs)
    if r then
        local a = math.rad(yaw)
        local ca, sa = math.cos(a), math.sin(a)
        for s = -1, 1, 2 do
            local lx = r.hx * s * sc
            xf(use(r.leg), x + lx * ca, y + r.hip * sc, z - lx * sa, swing * s, yaw, 0, sc)
        end
    end
end
R.rig = rig

function R.reset()
    P_reset(); R.sl = {}; R.kick = {}; R.coins = {}; R.streaks = {}; R.popups = {}; R.boss_seen = nil
    if R.trail_ids then for _, id in ipairs(R.trail_ids) do FX.lib:trail_at(id, nil, 0) end end
end

------------------------------------------------------------------ squad
local SOLW = { rifle = true, shotgun = true, minigun = true, rocket = true, laser = true }
local function body_mesh(kind, S)
    local w = SOLW[S.weapon] and S.weapon or "rifle"
    if kind == "hero" then return "hero_" .. (S.hero or "rook") end
    if kind == "hvy" then return "heavy" end
    if kind == "vet" then return "vet_" .. w end
    return "sol_" .. w
end
R.body_mesh = body_mesh
-- muzzle tip of each carried gun in body space (x right, y up, z forward), from gen_meshes.py (gun on the right side)
local TIP = { rifle = { 0.15, 0.75, 0.89 }, shotgun = { 0.15, 0.76, 0.88 }, minigun = { 0.15, 0.73, 1.06 }, rocket = { 0.31, 1.0, 0.71 }, laser = { 0.15, 0.75, 0.89 } }
local function draw_squad(S, dt)
    local bodies = SIM.bodies()
    local n = #bodies
    if n == 0 then return end
    local F = SIM.formation(n)
    local moving = (S.v or 0) > 0.1
    local wph = R.t * 10.5
    for i = 1, n do
        local tx, tz = S.x + F.ox[i], F.oz[i]
        local sl = R.sl[i]
        if not sl then sl = { x = tx, z = tz - 1.5 }; R.sl[i] = sl; if R.t > 0.5 and fxok(1) then FX.puff(WX(tx), 0.6, tz, { .4, .7, 1.2 }, 1) end end
        -- frame-rate independent catch-up (exp decay): ~95% of the way in 0.1 s sideways, so the squad never trails the steering
        sl.x = sl.x + (tx - sl.x) * (1 - math.exp(-dt * 30))
        sl.z = sl.z + (tz - sl.z) * (1 - math.exp(-dt * 16))
        local k = R.kick[i] or 0
        R.kick[i] = max(0, k - dt * 9)
        local ph = wph + i * 1.7
        local sw = moving and math.sin(ph) * 30 or math.sin(R.t * 2 + i) * 3
        local bob = moving and abs(math.cos(ph)) * 0.07 or 0
        local roll = moving and math.sin(ph) * 4 or 0
        local bk = bodies[i]
        local bz = sl.z - k * 0.09
        rig(body_mesh(bk, S), bk, WX(sl.x), 0, bz, 0, sw, 1.18, bob, -k * 7, 0, roll)
        -- muzzle flash star at the gun tip for a few frames after each shot (cheap: one emissive mesh)
        if k > 0.5 and (bk == "sol" or bk == "vet" or bk == "hero") then
            local tp = TIP[S.weapon] or TIP.rifle
            local fsz = (S.weapon == "minigun" and 0.75 or (S.weapon == "shotgun" and 1.25 or 1.0)) * (0.55 + k * 0.6)
            xf(use("mflash"), WX(sl.x) + tp[1] * 1.18, tp[2] * 1.18 + bob * 1.18, bz + tp[3] * 1.18, 0, 0, (i * 47 + R.t * 700) % 360, fsz)
        end
    end
    for i = n + 1, #R.sl do
        local sl = R.sl[i]
        if sl and R.t > 0.5 and fxok(1) then FX.puff(WX(sl.x), 0.7, sl.z, { 1.2, .3, .3 }, 1.5) end
        R.sl[i] = nil
    end
    R.sqF = F
end

------------------------------------------------------------------ foes
local function draw_foe(f, S)
    local x, z = WX(f.x), f.z
    if z > D.SPAWN_Z - 2 then return end
    local yaw = 180 + deg(math.atan2(min(1, max(-1, (S.x - f.x) * 0.15)), 1))
    local fl = (f.hit or 0) * 1.6
    local ph = R.t * (f.slow > 0 and 4 or 11) + f.ph
    local sw = math.sin(ph) * 32
    if f.boss then
        local b = f.boss
        local walk = not f.arrived or f.enr > 25
        local swb = walk and math.sin(R.t * 4) * 22 or math.sin(R.t * 1.4) * 4
        if b == "goliath" then
            rig("gol_body", "goliath", x, 0, z, 180, swb, 2.3, abs(math.cos(R.t * 4)) * 0.06, 0, fl * 0.15)
        elseif b == "ironclad" then
            rig("mech_body", "ironclad", x, 0, z, 180, swb * 0.8, 1.75, abs(math.cos(R.t * 4)) * 0.05, 0, fl * 0.15)
        else
            local y = 4.2 + math.sin(R.t * 2.2) * 0.4
            local sc = 1.7 * (1 + fl * 0.1)
            xf(use("wasp_body"), x, y, z, 8, 180, math.sin(R.t * 1.3) * 6, sc)
            local fa = math.sin(R.t * 38) * 35
            xf(use("wasp_wing"), x - 0.4 * sc, y + 0.55 * sc, z - 0.25 * sc, 0, 180, -fa, sc * 1.5)
            xf(use("wasp_wing"), x + 0.4 * sc, y + 0.55 * sc, z - 0.25 * sc, 0, 0, fa, sc * 1.5)
        end
        return
    end
    local t = f.t
    if t == "runner" then rig("run_body", "runner", x, 0, z, yaw, sw, 1.25, abs(math.cos(ph)) * 0.06, 8, fl * 0.25)
    elseif t == "shield" then rig(f.shield > 0 and "shd_body" or "shd_body_ns", "shield", x, 0, z, yaw, sw * 0.8, 1.25, abs(math.cos(ph)) * 0.05, 4, fl * 0.2)
    elseif t == "brute" then rig("brute_body", "brute", x, 0, z, yaw, math.sin(ph * 0.6) * 24, 1.3, abs(math.cos(ph * 0.6)) * 0.07, 3, fl * 0.12)
    elseif t == "flyer" then
        local y = 2.0 + math.sin(R.t * 3 + f.ph) * 0.25
        xf(use("fly_body"), x, y, z, 12, yaw, math.sin(R.t * 2 + f.ph) * 10, 1.3 * (1 + fl * 0.2))
        xf(use("fly_rotor"), x, y, z, 12, R.t * 2200 % 360, 0, 1.3)
    elseif t == "orb" then
        local s = 0.9 + math.sin(R.t * 18 + f.ph) * 0.1
        xf(use("orb"), x, 1.6, z, 0, R.t * 200, 0, s)
        if fxok(0.3) then FX.emit("ember", x, 1.6, z + 0.4, { n = 1, c0 = { 1.6, .7, .2 }, c1 = { 0, 0, 0 }, s0 = .15, s1 = .3, l0 = .2, l1 = .35, r = .2, sp = .5, drag = 2 }) end
    end
end

------------------------------------------------------------------ props, gates
local function draw_prop(p, S)
    local x, z = WX(p.x), p.z
    local fl = (p.hit or 0) * 1.2
    if p.t == "crate" then
        local y = p.drop and (p.drop * 9) or 0
        local wob = p.drop and math.sin(R.t * 3) * 8 or 0
        xf(use("crate"), x, y, z, wob, 20 + (p.drop and R.t * 40 or 0), 0, 1.15 * (1 + fl))
        if p.drop and fxok(0.3) then FX.smoke(x, y + 1.2, z, 0.5, 0.4) end
    elseif p.t == "container" then
        local orange = (p.ally == "heli" or p.ally == "sniper")
        xf(use(orange and "container_o" or "container"), x, 0, z, 0, 0, 0, 1 + fl * 0.3)
    elseif p.t == "barrel" then xf(use("barrel_red"), x, 0, z, 0, 30, 0, 1.2 * (1 + fl))
    elseif p.t == "cryo" then xf(use("barrel_blue"), x, 0, z, 0, 30, 0, 1.2 * (1 + fl))
    elseif p.t == "barricade" then xf(use("barricade"), x, 0, z, 0, 0, 0, 1 + fl * 0.2) end
end
local function draw_gate(g, S)
    local x, z = WX(g.x), g.z
    local sink = g.passed and g.gone * 3.5 or 0
    local s = g.passed and max(0.01, 1 - g.gone * 0.6) or 1
    local pulse = 1 + (g.hit or 0) * 0.5
    xf(use("gate_frame"), x, -sink, z, 0, 0, 0, 1, s, 1)
    xf(use("gpanel_" .. SIM.gate_color(g)), x, -sink, z, 0, 0, 0, pulse * s, s, 1)
end

------------------------------------------------------------------ shots, beams, missiles, bombs, markers, allies, air support
local function draw_bullets(S)
    local W = D.WEAPONS[S.weapon]
    local mesh = (S.weapon == "rocket") and "rocket" or ((S.weapon == "shotgun") and "pellet" or "tracer")
    local nb = #S.bullets
    local step = (nb > 140) and 2 or 1
    local homing = W.homing
    for i = 1, nb, step do
        local b = S.bullets[i]
        local yaw = deg(math.atan2(-b.vx, b.vz))
        if homing then
            -- guided rocket: a shallow lob (rises then dives onto the lock) with a smoke trail, so it reads as the one curved shot
            local u = min(1, max(0, (b.z - (b.z0 or b.z)) / 26))
            local y = 0.78 + math.sin(u * math.pi) * 1.1
            local pitch = -math.cos(u * math.pi) * 9
            xf(use("rocket"), WX(b.x), y, b.z, pitch, yaw, 0, 1.6)
            if fxok(0.3) then FX.emit("soft", WX(b.x - b.vx * 0.012), y, b.z - 0.45, { n = 1, c0 = { 1.5, .95, .5 }, c1 = { .45, .45, .5 }, s0 = .28, s1 = .45, l0 = .22, l1 = .4, r = .03, sp = .3, drag = 2, grav = { 0, .5, 0 } }) end
        else
            xf(use(mesh), WX(b.x), 0.78, b.z, 0, yaw, 0, 1.0)
        end
    end
    -- lock-on reticle under every foe a rocket is tracking (spinning red ring)
    if homing then
        for _, f in ipairs(S.foes) do
            if not f.dead and (f.lockt or 0) > 0 and f.z < D.SPAWN_Z - 2 then
                local r = (f.r or 0.6) * 1.35 * (1 + math.sin(R.t * 14) * 0.08)
                xf(use("ring"), WX(f.x), (f.fly and 1.4 or 0) + 0.1, f.z, 0, R.t * 220 % 360, 0, r, 1, r)
            end
        end
    end
    -- subtle aim cue: faint glow dashes flowing straight ahead along the edges of the squad's fire strip
    local F = R.sqF
    if F and F.R and (#S.bullets > 0 or S.beams) then
        local hw = max(0.5, F.R - 0.35)
        local ph = (R.t * 9) % 2.2
        for side = -1, 1, 2 do
            for k = 0, 5 do
                local z = 1.6 + ph + k * 2.2
                local sc = 1 - (z - 1.6) / 16
                if sc > 0 then xf(use("aimdash"), WX(S.x + side * hw), 0.035, z, 0, 0, 0, sc, 1, 1) end
            end
        end
    end
    if S.beams then
        for _, bm in ipairs(S.beams) do
            local len = max(0.1, bm.z1 - bm.z0)
            local wob = 1 + math.sin(R.t * 50 + bm.slot) * 0.25
            xf(use("beam"), WX(bm.x), 0.78, bm.z0, 0, 0, 0, wob * 1.4, wob * 1.4, len)
            if fxok(0.4) then FX.sparks(WX(bm.x), 0.9, bm.z1, 2, { 0, 2, -2 }, 4, { .6, 1.6, 2.0 }) end
        end
    end
end
local function draw_air(S, dt)
    for _, m in ipairs(S.missiles) do
        local dx, dz, dy = m.tx - m.x, m.tz - m.z, 1 - m.y
        local yaw = deg(math.atan2(-dx, dz))
        local pitch = -deg(math.atan2(dy, sqrt(dx * dx + dz * dz)))
        xf(use("rocket"), WX(m.x), m.y, m.z, pitch, yaw, 0, 2.2)
        if fxok(0.5) then FX.emit("smoke", WX(m.x), m.y, m.z - 0.5, { n = 1, c0 = { .8, .8, .82 }, c1 = { 0, 0, 0 }, s0 = .35, s1 = .6, l0 = .4, l1 = .7, r = .05, sp = .4, drag = 2, grav = { 0, .6, 0 } }) end
    end
    for _, b in ipairs(S.bombs) do xf(use("bomb"), WX(b.x), b.y, b.z, 70, 0, R.t * 300 % 360, 1.6) end
    for _, mk in ipairs(S.markers) do
        local k = 1 - mk.t / mk.t0
        local pul = 1 + math.sin(R.t * (10 + k * 30)) * 0.06
        -- two rings at clearly different heights, and the inner one never reaches the outer radius (they used to coincide at y .06/.07)
        xf(use("ring"), WX(mk.x), 0.08, mk.z, 0, R.t * 60, 0, mk.r * pul, 1, mk.r * pul)
        xf(use("ring"), WX(mk.x), 0.16, mk.z, 0, -R.t * 60, 0, mk.r * k * 0.88, 1, mk.r * k * 0.88)
        if mk.kind == "rocket" then xf(use("rocket"), WX(mk.x), 0.5 + 26 * (mk.t / mk.t0), mk.z, 90, 0, 0, 3.0) end
    end
    if S.jet then
        local t = S.jet.t
        xf(use("jet"), 0, 19 + t * 0.6, -35 + t * 55, -4, 0, math.sin(t * 2) * 8, 1.6)
        xf(use("jet"), 9, 21 + t * 0.6, -45 + t * 55, -4, 0, math.sin(t * 2 + 1) * 8, 1.6)
    end
    if S.gunship then
        local gs = S.gunship
        local x = gs.side * (-9 + gs.t * 3)
        local y = 9 + math.sin(gs.t * 1.3) * 0.4
        xf(use("heli"), WX(x), y, 8, 6, 180 + gs.side * 20, math.sin(gs.t) * 5, 1.5)
        xf(use("heli_rotor"), WX(x), y, 8, 6, R.t * 1600 % 360, 0, 1.5)
    end
    -- allies
    for _, al in ipairs(S.allies) do
        local x, z = WX(al.x), al.z
        local yaw = -deg(al.ang or 0)
        if al.t == "turret" then
            xf(use("tur_base"), x, 0, z, 0, 0, 0, 1.1)
            xf(use("tur_gun"), x, 1.05, z, 0, yaw, 0, 1.1)
        elseif al.t == "heli" then
            local y = (al.y or 7) + math.sin(R.t * 1.7) * 0.3
            xf(use("heli"), x, y, z, 4, yaw * 0.3, math.sin(R.t * 1.1) * 4, 1.3)
            xf(use("heli_rotor"), x, y, z, 4, R.t * 1700 % 360, 0, 1.3)
        elseif al.t == "mech" then
            rig("amech_body", "amech", x, 0, z, yaw * 0.5, math.sin(R.t * 6) * 18, 1.25, abs(math.cos(R.t * 6)) * 0.04)
        elseif al.t == "sniper" then
            xf(use("container_o"), x, 0, z, 0, 0, 0, 0.75)
            rig("sniper", "sniper", x, 1.8, z, yaw, 0, 1.1)
        else
            local nn = al.n or 3
            for j = 1, nn do
                local a = R.t * 1.6 + j * 2 * PI / nn
                local dx, dz = math.cos(a) * 1.6, math.sin(a) * 0.8
                local y = (al.y or 2.5) + math.sin(R.t * 3 + j) * 0.2
                xf(use("ally_drone"), x + dx, y, z + dz + 1, 0, yaw, 0, 1.0)
                xf(use("fly_rotor"), x + dx, y, z + dz + 1, 0, R.t * 2000 % 360, 0, 1.0)
            end
        end
    end
    -- short-lived streaks (ally shots)
    for i = #R.streaks, 1, -1 do
        local s = R.streaks[i]
        s.t = s.t - dt
        if s.t <= 0 then table.remove(R.streaks, i)
        else
            local k = s.t / s.t0
            local dx, dy, dz = s.x1 - s.x0, s.y1 - s.y0, s.z1 - s.z0
            local len = sqrt(dx * dx + dy * dy + dz * dz)
            local h = 1 - k
            local cx, cy, cz = s.x0 + dx * (0.2 + h * 0.6), s.y0 + dy * (0.2 + h * 0.6), s.z0 + dz * (0.2 + h * 0.6)
            local yaw = deg(math.atan2(dx, dz))
            local pitch = -deg(math.atan2(dy, sqrt(dx * dx + dz * dz)))
            xf(use("tracer"), cx, cy, cz, pitch, yaw, 0, s.w, s.w, min(len * 0.35, 6) / 1.1 * 2)
        end
    end
    -- coin pops
    for i = #R.coins, 1, -1 do
        local c = R.coins[i]
        c.t = c.t + dt; c.vy = c.vy - 22 * dt; c.y = max(0.2, c.y + c.vy * dt); c.z = c.z - (S.v or 0) * dt
        if c.t > 0.9 then table.remove(R.coins, i)
        else xf(use("coin"), c.x, c.y + 0.2, c.z, 90, 0, R.t * 720 % 360, 1.3 * min(1, (0.9 - c.t) * 5)) end
    end
    -- finish banner
    if S.finish_z and S.finish_z > -5 and not S.over then
        xf(use("gate_frame"), 0, 0, S.finish_z, 0, 0, 0, 2.45, 1.25, 1.2)
        xf(use("gpanel_gold"), 0, 0, S.finish_z, 0, 0, 0, 2.45, 1.25, 0.4)
    end
end

------------------------------------------------------------------ events -> fx / sfx / hud
local KILL_COL = { runner = { .9, .25, .35 }, shield = { .9, .5, .2 }, brute = { .9, .2, .3 }, flyer = { .9, .3, .3 }, orb = { 1.4, .6, .2 } }
local function coin_pop(x, z, n)
    for j = 1, min(n, 4) do
        R.coins[#R.coins + 1] = { x = x + (rand() - 0.5) * 0.6, y = 1.0, z = z, vy = 6 + rand() * 3, t = 0 }
    end
end
function R.events(S)
    local H = G.HUD
    for _, e in ipairs(S.events) do
        local k = e.k
        if k == "shot" then
            R.kick[e.slot] = 1
            local sl = R.sl[e.slot]
            if sl and fxok(0.35) then FX.muzzle(WX(sl.x) + 0.18, 0.9, sl.z + 1.05, D.WEAPONS[S.weapon].col) end
            sfxr("shot_" .. S.weapon, S.weapon == "minigun" and 0.05 or 0.08)
        elseif k == "impact" then
            if fxok(0.6) then
                if e.kind == 1 then FX.blood(WX(e.x), e.fly and 2.0 or 0.9, e.z, 3)
                elseif e.kind == 3 and e.thru then FX.sparks(WX(e.x), 1.5, e.z, 2, { 0, 0.5, 3 }, 2, { 1.2, 1.4, 2.0 })   -- shot passing through the glass
                elseif e.kind == 3 then FX.sparks(WX(e.x), 1.8, e.z - 0.1, 3, { 0, 1, -3 }, 4, { 1.2, 1.4, 2.0 })
                else FX.sparks(WX(e.x), 0.8, e.z, 4, { 0, 2, -3 }, 5) end
            end
            sfxr("hit", 0.07)
        elseif k == "kill" then
            local x = WX(e.x)
            if e.boss then
                FX.boom(x, 2.5, e.z, 3.0); FX.boom(x + 1.5, 1.5, e.z + 1, 2.0); FX.confetti(x, 3, e.z, 60, 2)
                G.flash(x, 4, e.z, { 1, .7, .4 }, 120, 0.8, 30)
                sfx("boom_big"); coin_pop(x, e.z, 4)
                if H then H.toast(D.BOSS[e.boss].name .. " Destroyed!", "gold") end
            else
                if fxok(1) then FX.blood(x, e.fly and 2 or 0.8, e.z, e.t == "brute" and 14 or 6); FX.puff(x, 0.8, e.z, KILL_COL[e.t] or { .9, .3, .3 }, e.t == "brute" and 3 or 1) end
                if e.t == "brute" then FX.dust(x, 0.3, e.z, { .6, .5, .45 }, 2, 1.6); sfxr("boom_small", 0.1) end
                if e.fly then FX.sparks(x, 2, e.z, 8) end
                sfxr("splat", 0.05)
                if e.t ~= "orb" and (e.t ~= "runner" or rand() < 0.35) then coin_pop(x, e.z, e.t == "brute" and 3 or 1) end
            end
        elseif k == "shieldbreak" then FX.sparks(WX(e.x), 1, e.z, 16, { 0, 3, -2 }, 7); FX.shards(WX(e.x), 1, e.z, { 1.2, .9, .2 }, 8); sfxr("unlock", 0.1)
        elseif k == "boom" then
            local x = WX(e.x)
            if e.kind == "cryo" then
                FX.ring(x, 0.3, e.z, e.r * 2, { .4, .8, 1.4 }, true); FX.emit("soft", x, 1, e.z, { n = 10, c0 = { .5, .8, 1.3 }, c1 = { 0, 0, 0 }, s0 = 1, s1 = 2, l0 = .4, l1 = .8, r = e.r * 0.6, sp = 2, drag = 2 })
                FX.shards(x, 1, e.z, { .7, .9, 1.3 }, 14); sfx("flip")
            else
                local s = (e.kind == "rocket") and 0.55 or (e.r / 3.2)
                if e.kind ~= "rocket" or fxok(1.5) then FX.boom(x, 0.8, e.z, s) end
                if e.kind ~= "rocket" then G.flash(x, 2, e.z, { 1, .6, .3 }, 60, 0.4, 14); FX.ring(x, 0.2, e.z, e.r * 2.2, { .7, .45, .2 }, true) end
                sfxr(e.kind == "rocket" and "boom_small" or "boom", 0.06)
            end
        elseif k == "weapon" then
            FX.confetti(WX(e.x), 1.5, e.z, 30, 1); sfx("crate"); G.weapon_tint(D.WEAPONS[e.w].col)
            if H then H.toast(D.WEAPONS[e.w].name .. "!", "orange", "w_" .. e.w) end
        elseif k == "ally" then
            FX.confetti(WX(e.x), 2, e.z, 40, 1.2); FX.boom(WX(e.x), 1, e.z, 0.6); sfx("ally")
            if H then H.toast(e.name .. " Freed!", "blue") end
        elseif k == "gatetick" then
            local v = e.v or 0
            sfxr("tick" .. (e.up and 5 or min(5, floor(abs(v) / 4))), 0.05)
        elseif k == "flip" then FX.shards(WX(e.x), 1.8, e.z, { 1.4, .3, .2 }, 16); sfx("flip"); if H then H.toast("Trap Gate Overloaded!", "red") end
        elseif k == "unlock" then FX.shards(WX(e.x), 1.8, e.z, { .8, .85, .9 }, 22); FX.ring(WX(e.x), 1.8, e.z, 4, { .5, 1.2, .6 }); sfx("unlock")
        elseif k == "gate" then
            local x = WX(S.x)
            local c = e.good and { .4, 1.0, 1.4 } or { 1.4, .4, .3 }
            if e.good == nil then c = { .6, .6, .7 } end
            FX.glow_trail(x, 1, 0.5, c); FX.shards(x, 2.2, 0.4, c, 18)
            if e.good then sfx(e.mult and "gate_mult" or "gate_good") elseif e.good == false then sfx("gate_bad") end
            if H then H.gate_pop(e) end
        elseif k == "merge" then
            FX.ring(WX(S.x), 0.3, -1, 5, { 1.4, 1.0, .3 }, true); FX.confetti(WX(S.x), 1.5, -1, 25, 1); sfx("merge")
            -- reads as an upgrade: the counter (worth) does not move; merges inside 1.5 s fold into one toast
            local m = R.mg
            if not m or R.t - m.t > 1.5 then m = { nv = 0, nh = 0 }; R.mg = m end
            m.t = R.t; m.nv = m.nv + (e.nv or 0); m.nh = m.nh + (e.nh or 0)
            if H then
                if m.nh > 0 then H.toast("Merged! " .. (m.nh * 4) .. " Veterans into " .. m.nh .. (m.nh == 1 and " Heavy" or " Heavies"), "gold", nil, "merge_h") end
                if m.nv > 0 then H.toast("Merged! " .. (m.nv * 5) .. " Soldiers into " .. m.nv .. (m.nv == 1 and " Veteran" or " Veterans"), "gold", nil, "merge_v") end
                H.merge_flash()
            end
        elseif k == "hurt" then
            if e.n > 0 then sfxr("hurt", 0.1); if H then H.hurt(e.n) end end
        elseif k == "contact" then if fxok(1) then FX.blood(WX(e.x), 0.8, e.z, 5) end
        elseif k == "boss" then
            music("music_boss"); sfx("roar")
            if H then H.banner(e.name, "Boss Incoming!") end
        elseif k == "bossarrive" then S.shake = max(S.shake, 0.6); sfx("roar"); FX.dust(0, 0.3, 16, { .7, .6, .5 }, 3, 3)
        elseif k == "windup" or k == "volley" then sfxr("warn", 0.3)
        elseif k == "roar" then sfxr("roar", 0.5)
        elseif k == "spit" then sfxr("shot_rocket", 0.2)
        elseif k == "airstrike" then sfx("jet"); if H then H.toast("Airstrike Inbound!", "blue", "air") end
        elseif k == "bombdrop" then sfxr("whistle", 0.6)
        elseif k == "gunship" then sfx("heli"); if H then H.toast("Gunship Support!", "blue") end
        elseif k == "missile" then sfxr("shot_rocket", 0.12)
        elseif k == "drop" then sfx("whistle"); if H then H.toast("Supply Drop!", "orange") end
        elseif k == "land" then FX.dust(WX(e.x), 0.2, e.z, { .8, .75, .7 }, 2, 1.4); sfx("crate")
        elseif k == "hint" then if H and not G.demo then H.hint(e.txt) end
        elseif k == "assist" then if H and not G.demo then H.toast("Rookie Boost: +" .. e.n .. " Recruits", "green") end
        elseif k == "recruit" then FX.puff(WX(S.x), 0.8, -1.5, { .4, 1.2, .5 }, 2)
        elseif k == "stomp" then FX.blood(WX(e.x), 0.6, e.z, 8); sfxr("splat", 0.05)
        elseif k == "breakwall" then FX.grit(WX(e.x), 1, e.z, { .6, .5, .4 }, 18, { 0, 4, -2 }); FX.dust(WX(e.x), 0.5, e.z, { .7, .65, .6 }, 3, 2); sfx("boom_small")
        elseif k == "trace" then
            R.streaks[#R.streaks + 1] = { x0 = WX(e.x0), y0 = e.y0 or 1.2, z0 = e.z0, x1 = WX(e.x1), y1 = e.y1, z1 = e.z1, t = 0.09, t0 = 0.09, w = (e.kind == "sniper") and 2.2 or 1.2 }
            if e.kind == "sniper" then sfxr("shot_sniper", 0.2); FX.sparks(WX(e.x1), e.y1, e.z1, 8) else sfxr("shot_minigun", 0.09) end
        elseif k == "allyleave" then if H then H.toast("Gunship Leaving", "grey") end
        elseif k == "allydown" then if H then H.toast("Ally Mech Down!", "red") end
        elseif k == "finishline" then sfx("levelup")
        end
    end
    S.events = {}
end

------------------------------------------------------------------ frame
local DRAWN = {}
function R.draw(S, dt)
    R.t = R.t + dt
    R.fxbudget = min(30, R.fxbudget + dt * 90)
    for kind in pairs(R.kinds) do P_begin(kind) end
    if S then
        G.world_scroll(S.travel, WX(S.x) * 0.3)
        draw_squad(S, dt)
        for _, f in ipairs(S.foes) do if not f.dead then draw_foe(f, S) end end
        for _, p in ipairs(S.props) do if not p.dead then draw_prop(p, S) end end
        for _, g in ipairs(S.gates) do draw_gate(g, S) end
        draw_bullets(S)
        draw_air(S, dt)
    end
    for kind in pairs(R.kinds) do P_end(kind) end
end
end
------------------------------------------------------------------ UI kit: runtime_ui quads, one mouse backdrop, keyboard focus
local UI = { name = "gb" }
G.UI = UI
do
local NAME = UI.name
runtime_ui.show(NAME); pcall(runtime_ui.set_screen_overlay, NAME, true)
local US = SH / 1080
UI.US = US
local CLEAR = { 0, 0, 0, 0 }
local cache, last, used, shown = {}, {}, {}, {}
local function Q(id, o)
    used[id] = true
    o.visible = true
    if o.style == nil then o.style = "text" end
    if o.fill == nil then o.fill = CLEAR end
    if o.border == nil then o.border = CLEAR end
    if o.no_input == nil then o.no_input = true end
    local f, tc, b = o.fill, o.text_color or CLEAR, o.border
    local key = string.format("%.1f|%.1f|%.1f|%.1f|%s|%.2f|%.3f%.3f%.3f%.3f|%.3f%.3f%.3f%.3f|%.2f%.2f%.2f%.2f|%s|%s|", o.x, o.y, o.w, o.h, o.label or "",
        o.font_scale or 1, f[1], f[2], f[3], f[4], tc[1], tc[2], tc[3], tc[4], b[1], b[2], b[3], b[4], tostring(o.z), (o.align_h or "") .. (o.image or "") .. (o.image_tint and string.format("%.2f", o.image_tint[4]) or ""))
    if cache[id] == key then return end
    cache[id] = key; last[id] = o
    pcall(runtime_ui.set_quad, NAME, id, o)
end
UI.Q = Q
function UI.begin_frame() used = {} end
function UI.end_frame()
    for id in pairs(shown) do
        if not used[id] and last[id] then local o = last[id]; o.visible = false; pcall(runtime_ui.set_quad, NAME, id, o); cache[id] = nil end
    end
    shown = used
end
-- shapes
function UI.rect(id, x, y, w, h, fill, r, z, border)
    Q(id, { x = x, y = y, w = w, h = h, z = z or 5, label = "", fill = fill, border = border, corner_radius = (r or 0) * US })
end
function UI.text(id, label, x, y, w, h, fs, col, align, z, shadow)
    if shadow ~= false then
        Q(id .. "~", { x = x + 3 * US, y = y + 4 * US, w = w, h = h, z = (z or 10) - 0.5, label = label, text_color = { 0.05, 0.08, 0.2, (col and col[4] or 1) * 0.45 },
            font_scale = fs * US, align_h = align or "center", align_v = "middle" })
    end
    Q(id, { x = x, y = y, w = w, h = h, z = z or 10, label = label, text_color = col or { 1, 1, 1, 1 }, font_scale = fs * US, align_h = align or "center", align_v = "middle" })
end
-- outlined big text (four dark copies around) - the chunky mobile look for counters and gate values
function UI.big(id, label, cx, cy, fs, col, out, z)
    local w, h = 900 * US, fs * 26 * US
    local x, y = cx - w / 2, cy - h / 2
    local o = (out or 3) * US
    local oc = { 0.06, 0.1, 0.25, (col and col[4] or 1) * 0.85 }
    local k = 0
    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { 0.8, 1.6 } }) do
        k = k + 1
        Q(id .. "~" .. k, { x = x + d[1] * o, y = y + d[2] * o, w = w, h = h, z = (z or 10) - 0.5, label = label, text_color = oc, font_scale = fs * US, align_h = "center", align_v = "middle" })
    end
    Q(id, { x = x, y = y, w = w, h = h, z = z or 10, label = label, text_color = col or { 1, 1, 1, 1 }, font_scale = fs * US, align_h = "center", align_v = "middle" })
end
-- palettes for buttons {top, lip, text}
local BTN = {
    green = { { .30, .80, .32, 1 }, { .15, .52, .2, 1 } }, blue = { { .25, .58, 1, 1 }, { .12, .34, .75, 1 } },
    orange = { { 1, .62, .16, 1 }, { .78, .38, .06, 1 } }, red = { { .95, .32, .3, 1 }, { .66, .14, .14, 1 } },
    purple = { { .6, .4, 1, 1 }, { .38, .22, .74, 1 } }, white = { { .97, .97, 1, 1 }, { .72, .76, .86, 1 } },
    grey = { { .62, .65, .72, 1 }, { .42, .45, .52, 1 } }, gold = { { 1, .8, .25, 1 }, { .8, .55, .1, 1 } },
}
UI.BTN = BTN
-- mouse via one transparent backdrop (all visuals are no_input) + keyboard focus over this frame's buttons
local MS = { x = -1, y = -1, down = false, prev = false, click = false, got = false, release = false }
UI.MS = MS
local list, focus, fscreen = {}, 1, nil
UI.list = list
function UI.poll(screen)
    if screen ~= fscreen then fscreen = screen; focus = 1; UI.kbd = false end
    Q("backdrop", { x = 0, y = 0, w = SW, h = SH, z = 900, label = "", no_input = false, bring_to_front = true })
    local ok, s = pcall(runtime_ui.get_state, NAME, "backdrop")
    local down = false
    local clicked = false
    if ok and type(s) == "table" then
        if s.mouse_x then MS.moved = abs((s.mouse_x or 0) - MS.x) + abs((s.mouse_y or 0) - MS.y) > 2; MS.x, MS.y = s.mouse_x, s.mouse_y end
        down = s.down and true or false
        clicked = s.clicked and true or false
    end
    poll_mouse()
    if G.vmouse then MS.moved = abs(MOUSE.x - MS.x) + abs(MOUSE.y - MS.y) > 2; MS.x, MS.y = MOUSE.x, MOUSE.y; down = G.vmouse.down or false; clicked = G.vmouse.click or false; G.vmouse.click = false end
    if not down and MOUSE.down and not G.vmouse then down = true end
    MS.click = false
    if down and not MS.prev then MS.click = true; MS.got = true; MS.px, MS.py = MS.x, MS.y end
    if clicked and not MS.got then MS.click = true; MS.px, MS.py = MS.x, MS.y end
    MS.release = (not down and MS.prev) or (clicked and not MS.prev)
    if not down then MS.got = false end
    MS.prev = down; MS.down = down
    -- keys
    local K = {}
    K.up = anyedge("Up", "W"); K.down = anyedge("Down", "S"); K.left = anyedge("Left", "A"); K.right = anyedge("Right", "D")
    K.ok = anyedge("Return", "Space"); K.back = anyedge("Escape")
    UI.K = K
    -- focus moves on this frame using last frame's button list
    local n = #list
    if n > 0 then
        if K.down or K.right then focus = focus % n + 1; UI.kbd = true; sfx("hover") end
        if K.up or K.left then focus = (focus - 2) % n + 1; UI.kbd = true; sfx("hover") end
    end
    UI.prev_list = list
    UI.activate = (K.ok and n > 0) and list[focus] or nil
    list = {}
    UI.list = list
end
local function inside(x, y, w, h) return MS.x >= x and MS.x <= x + w and MS.y >= y and MS.y <= y + h end
UI.inside = inside
-- button: returns true when clicked (mouse) or activated (keyboard focus + Enter/Space)
function UI.button(id, label, cx, cy, w, h, kind, opt)
    opt = opt or {}
    w, h = w * US, h * US
    local x, y = cx - w / 2, cy - h / 2
    local idx = -1
    if not opt.nokbd then idx = #list + 1; list[idx] = id end
    local hov = inside(x, y, w, h)
    if hov and MS.moved and idx > 0 then focus = idx; UI.kbd = false end
    local foc = (focus == idx) or (opt.nokbd and hov)
    local pal = BTN[opt.disabled and "grey" or (kind or "blue")]
    local press = (hov and MS.down) and 4 * US or 0
    local grow = (foc and not opt.disabled) and 1.04 or 1
    local gw, gh = w * grow, h * grow
    local gx, gy = cx - gw / 2, cy - gh / 2
    local lip = 7 * US
    local r = opt.r or min(h / US / 2, 26)
    if foc then UI.rect(id .. "_f", gx - 5 * US, gy - 5 * US + press, gw + 10 * US, gh + lip + 10 * US, { 1, 1, 1, 0.95 }, r + 5, (opt.z or 20) - 1) end
    UI.rect(id .. "_l", gx, gy + lip, gw, gh, pal[2], r, (opt.z or 20))
    UI.rect(id .. "_t", gx, gy + press, gw, gh, pal[1], r, (opt.z or 20) + 0.1)
    UI.rect(id .. "_h", gx + 8 * US, gy + press + 5 * US, gw - 16 * US, gh * 0.38, { 1, 1, 1, foc and 0.28 or 0.18 }, r * 0.7, (opt.z or 20) + 0.2)
    if label ~= "" then
        local tc = (kind == "white") and { .15, .22, .4, 1 } or { 1, 1, 1, 1 }
        UI.text(id .. "_x", label, gx, gy + press + (opt.ty or 0) * US, gw, gh, opt.fs or (h / US / 22), tc, "center", (opt.z or 20) + 0.3, kind ~= "white")
    end
    if opt.disabled then return false end
    local hit = (MS.click and inside(x, y, w, h)) or UI.activate == id
    if hit then sfx("click") end
    return hit
end
function UI.focus_index() return focus end
function UI.set_focus(i) focus = i end
-- panel card with a soft drop shadow
function UI.card(id, x, y, w, h, fill, z)
    UI.rect(id .. "_s", x + 6 * US, y + 10 * US, w, h, { 0.05, 0.1, 0.25, 0.25 }, 30, (z or 5) - 0.2)
    UI.rect(id, x, y, w, h, fill or { .98, .98, 1, 0.97 }, 30, z or 5)
end
-- icons are generated PNGs (tools/gen_ui.py)
function UI.img(id, name, cx, cy, size, z, tint)
    local s = size * US
    Q(id, { style = "image", image = "Textures/ui/" .. name .. ".png", image_tint = tint or { 1, 1, 1, 1 }, x = cx - s / 2, y = cy - s / 2, w = s, h = s, z = z or 12, label = "" })
end
function UI.coin_icon(id, cx, cy, s, z) UI.img(id, "coin", cx, cy, s, z) end
function UI.gem_icon(id, cx, cy, s, z) UI.img(id, "medal", cx, cy, s, z) end
function UI.star(id, cx, cy, s, on, z) UI.img(id, on and "star" or "star_off", cx, cy, s, z) end
-- currency pill
function UI.pill(id, x, y, w, icon, value, z)
    local h = 58 * US
    UI.rect(id, x, y, w * US, h, { .08, .14, .32, 0.55 }, 29, z or 30)
    if icon == "coin" then UI.coin_icon(id .. "i", x + 30 * US, y + h / 2, 40, (z or 30) + 1) else UI.gem_icon(id .. "i", x + 30 * US, y + h / 2, 36, (z or 30) + 1) end
    UI.text(id .. "v", value, x + 60 * US, y, w * US - 66 * US, h, 1.9, { 1, 1, 1, 1 }, "left", (z or 30) + 1)
end
end
------------------------------------------------------------------ 07_hud: in-run HUD (squad count, gate values, bars, toasts) + menu screens
do
local U, D, SIM = G.UI, G.D, G.SIM
local US = U.US
local HUD = { toasts = {}, pops = {}, hurt_a = 0 }
G.HUD = HUD
local function fmt(n)
    n = floor((n or 0) + 0.5)
    local s = tostring(abs(n))
    local o = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if o:sub(1, 1) == "," then o = o:sub(2) end
    return (n < 0 and "-" or "") .. o
end
HUD.fmt = fmt
local TCOL = { gold = { 1, .78, .2, 1 }, orange = { 1, .58, .18, 1 }, blue = { .35, .7, 1, 1 }, red = { 1, .35, .3, 1 }, grey = { .8, .84, .9, 1 }, green = { .4, .95, .45, 1 } }
local WHITE = { 1, 1, 1, 1 }
local NAVY = { .06, .1, .24, 1 }

function HUD.reset() HUD.toasts, HUD.pops, HUD.hurt_a, HUD.ban, HUD.hnt = {}, {}, 0, nil, nil end
function HUD.toast(txt, col, icon, key)
    for _, t in ipairs(HUD.toasts) do if t.txt == txt or (key and t.key == key) then t.txt = txt; t.t = math.min(t.t, 0.2); return end end
    table.insert(HUD.toasts, 1, { txt = txt, col = TCOL[col] or TCOL.gold, icon = icon, t = 0, key = key })
    if #HUD.toasts > 3 then HUD.toasts[4] = nil end
end
function HUD.banner(a, b) HUD.ban = { a = a, b = b, t = 0 } end
function HUD.hint(txt) HUD.hnt = { txt = txt, t = 0 } end
function HUD.merge_flash() HUD.mfl = 1.2 end
function HUD.hurt(n) HUD.hurt_a = min(0.55, HUD.hurt_a + 0.12 + n * 0.02) end
function HUD.gate_pop(e)
    local g = e.g
    local txt
    if g.k == "rate" or g.k == "dmg" then txt = (g.v >= 0 and "+" or "") .. g.v .. "% " .. (g.k == "rate" and "Rate" or "Damage")
    elseif g.k == "merge" then txt = "Merged!"
    elseif g.k == "lock" then txt = "Locked"
    else txt = (e.delta >= 0 and "+" or "") .. e.delta end
    HUD.pops[#HUD.pops + 1] = { txt = txt, good = e.good, t = 0 }
end

local function bar(id, cx, cy, w, h, k, col, z, back)
    U.rect(id .. "b", cx - w / 2 - 2 * US, cy - h / 2 - 2 * US, w + 4 * US, h + 4 * US, back or { .05, .08, .18, .75 }, h, z or 8)
    if k > 0.003 then U.rect(id .. "f", cx - w / 2, cy - h / 2, w * clamp(k, 0, 1), h, col, h * 0.8, (z or 8) + 0.1) end
end
HUD.bar = bar

------------------------------------------------------------------ world-anchored labels
local GCOL = { blue = { .85, .95, 1, 1 }, red = { 1, .9, .88, 1 }, green = { .9, 1, .9, 1 }, gold = { 1, .97, .85, 1 }, grey = { .92, .94, 1, 1 }, orange = { 1, .95, .85, 1 } }
local function gate_labels(S)
    for i, g in ipairs(S.gates) do
        if not g.passed and g.z < 78 and g.z > -1 then
            local sx, sy, zc = project(WX(g.x), 1.78, g.z)
            if zc > 2 then
                local px = 2.18 / (zc * math.tan(VFOV / 2)) * SH / 2
                local fs = clamp(px / 24 / US, 0.6, 7) * (1 + (g.hit or 0) * 0.35)
                local big, small = SIM.gate_label(g)
                local a = clamp((80 - g.z) / 12, 0, 1)
                local col = GCOL[SIM.gate_color(g)] or WHITE
                U.big("gl" .. i, big, sx, sy - (small and px * 0.08 or 0), fs, { col[1], col[2], col[3], a }, max(1.5, fs * 0.8), 6)
                if small then U.text("gs" .. i, small, sx - px * 0.6, sy + px * 0.13, px * 1.2, px * 0.2, fs * 0.36, { 1, 1, 1, a }, "center", 6, false) end
                if g.k == "add" or g.k == "mul" or g.k == "rate" or g.k == "dmg" then
                    -- damage meter: fills smoothly with every point of squad damage, empties on each step up
                    local top = g.k == "mul" and g.mi >= #D.MUL
                    local raw = top and 1 or clamp((g.prog or 0) / SIM.gate_cost(g), 0, 1)
                    local p = g.pshow or raw
                    if raw < p - 0.3 then p = 0 end
                    p = p + (raw - p) * math.min(1, (G.HUDDT or 0.016) * 12)
                    g.pshow = p
                    bar("gp" .. i, sx, sy + px * 0.3, px * 0.8, max(5 * US, px * 0.05), p, top and { 1, .8, .3, 1 } or { .55, .95, 1, 1 }, 6)
                end
                if g.k == "lock" and g.hp then bar("gb" .. i, sx, sy + px * 0.3, px * 0.8, max(5 * US, px * 0.05), g.hp / g.maxhp, { 1, .8, .3, 1 }, 6) end
                if g.k == "trap" and not g.flip then
                    local k = g.v / max(1, g.maxv)
                    bar("gt" .. i, sx, sy + px * 0.3, px * 0.8, max(5 * US, px * 0.05), k, k > 0.8 and { 1, .3, .25, 1 } or { 1, .65, .2, 1 }, 6)
                end
            end
        end
    end
end
local function prop_labels(S)
    for i, p in ipairs(S.props) do
        if not p.dead and p.z < 70 and p.z > 0 and (p.t == "crate" or p.t == "container" or p.t == "barricade") then
            local h = (p.t == "container") and 3.4 or ((p.t == "crate") and (2.0 + (p.drop or 0) * 9) or 2.4)
            local sx, sy, zc = project(WX(p.x), h, p.z)
            if zc > 2 then
                local k = clamp(26 / zc, 0.45, 1.4)
                local a = clamp((72 - p.z) / 10, 0, 1)
                if p.t == "crate" and p.w then U.img("pw" .. i, "w_" .. p.w, sx, sy - 34 * k * US, 70 * k, 7, { 1, 1, 1, a }) end
                if p.t == "container" and p.ally then
                    U.text("pa" .. i, D.ALLY[p.ally].name, sx - 160 * US, sy - 46 * k * US, 320 * US, 40 * US, 1.25 * k, { 1, .95, .7, a }, "center", 7)
                end
                if p.hp < p.maxhp then bar("ph" .. i, sx, sy, 100 * k * US, 10 * k * US, p.hp / p.maxhp, { .4, .9, .4, 1 }, 7) end
            end
        end
    end
end
local function foe_bars(S)
    local nb = 0
    for i, f in ipairs(S.foes) do
        if not f.dead and not f.boss and (f.t == "brute" or f.t == "shield") and f.z < 70 and (f.hp < f.maxhp or (f.shield or 0) > 0) then
            nb = nb + 1
            if nb > 14 then break end
            local h = (f.t == "brute") and 2.7 or 2.0
            local sx, sy, zc = project(WX(f.x), h, f.z)
            if zc > 2 then
                local k = clamp(24 / zc, 0.4, 1.3)
                if (f.shield or 0) > 0 then bar("fs" .. i, sx, sy, 80 * k * US, 8 * k * US, f.shield / f.maxsh, { .4, .75, 1, 1 }, 7)
                else bar("fh" .. i, sx, sy, 80 * k * US, 8 * k * US, f.hp / f.maxhp, { 1, .35, .3, 1 }, 7) end
            end
        end
    end
end

------------------------------------------------------------------ the in-run HUD; returns "pause" / "air" / "merge"
function HUD.play(S, dt, demo)
    G.HUDDT = dt
    local act
    if not demo then gate_labels(S); prop_labels(S); foe_bars(S) end
    local L = S.L
    -- squad counter bubble (in-run only: on menus it would float behind the buttons)
    if demo then return end
    local F = G.R.sqF
    local n = SIM.worth()   -- total worth in soldier-equivalents: merges never lower it
    HUD.mfl = math.max(0, (HUD.mfl or 0) - (dt or 0))
    if F and n > 0 then
        local sx, sy = project(WX(S.x), 2.1 + min(n, 30) * 0.012, -F.depth * 0.5)
        local w = (70 + #tostring(n) * 22) * US
        local k = math.min(1, HUD.mfl / 0.6)   -- gold pulse right after a merge
        local pk = 1 + 0.18 * k
        sy = sy - 4 * US * k
        U.rect("sq_b", sx - w * pk / 2, sy - 32 * US * pk, w * pk, 64 * US * pk, { .2 + .8 * k, .5 + .3 * k, 1 - .8 * k, .92 }, 32 * pk, 9)
        U.rect("sq_bh", sx - w / 2 + 6 * US, sy - 28 * US, w - 12 * US, 22 * US, { 1, 1, 1, .2 }, 16, 9.1)
        U.big("sq_n", tostring(n), sx, sy + 1 * US, 2.4, WHITE, 2, 9.5)
    end
    if demo then return end
    -- top: level name, progress
    U.text("lvname", "Level " .. S.lvl .. "  " .. L.name, 30 * US, 22 * US, 700 * US, 50 * US, 1.8, WHITE, "left", 20)
    local pw = 560 * US
    local prog = clamp(S.travel / L.len, 0, 1)
    if S.boss or S.bosses_left and S.bosses_left > 0 and prog >= 1 then prog = 1 end
    bar("prog", SW / 2, 44 * US, pw, 18 * US, prog, { .35, .85, .4, 1 }, 20)
    U.img("prog_s", "u_sol", SW / 2 - pw / 2 + pw * prog, 44 * US, 44, 21)
    if L.boss then U.img("prog_b", "skull", SW / 2 + pw / 2 + 30 * US, 44 * US, 46, 21) end
    -- coins + pause
    U.pill("hc", SW - 330 * US, 22 * US, 200, "coin", fmt(S.coins), 30)
    if U.button("h_pause", "", SW - 70 * US, 52 * US, 84, 84, "white", { nokbd = true, r = 20 }) then act = "pause" end
    U.img("h_pause_i", "pause", SW - 70 * US, 50 * US, 50, 21, { .2, .3, .55, 1 })
    -- boss bar
    if S.boss and not S.boss.dead then
        local b = S.boss
        local bw = 820 * US
        U.big("bossn", D.BOSS[b.boss].name, SW / 2, 104 * US, 2.6, { 1, .85, .8, 1 }, 2.5, 20)
        bar("bossb", SW / 2, 146 * US, bw, 24 * US, b.hp / b.maxhp, { .95, .25, .25, 1 }, 20)
    end
    -- bottom-left: weapon + composition
    local W = D.WEAPONS[S.weapon]
    U.rect("wpn_bg", 24 * US, SH - 150 * US, 380 * US, 126 * US, { .06, .1, .24, .55 }, 26, 18)
    U.img("wpn_i", "w_" .. S.weapon, 100 * US, SH - 87 * US, 104, 19)
    U.text("wpn_n", W.name, 160 * US, SH - 140 * US, 240 * US, 50 * US, 2.0, { W.col[1], W.col[2], W.col[3], 1 }, "left", 19)
    local cx = 166 * US
    for _, c in ipairs({ { "u_sol", S.sol }, { "u_vet", S.vet }, { "u_hvy", S.hvy } }) do
        U.img("cmp_" .. c[1], c[1], cx + 16 * US, SH - 62 * US, 38, 19)
        U.text("cmp_t" .. c[1], tostring(c[2]), cx + 36 * US, SH - 82 * US, 60 * US, 40 * US, 1.4, WHITE, "left", 19)
        cx = cx + 78 * US
    end
    -- bottom-right: airstrike + merge
    local ax, ay = SW - 120 * US, SH - 120 * US
    local ready = S.air >= 1 and not S.jet
    local pul = ready and (1 + math.sin(G.t * 8) * 0.04) or 1
    if U.button("h_air", "", ax, ay, 150 * pul, 150 * pul, ready and "orange" or "grey", { nokbd = true, r = 75 }) and ready then act = "air" end
    U.img("h_air_i", "air", ax, ay - 8 * US, 92, 21, ready and WHITE or { 1, 1, 1, .7 })
    bar("h_airm", ax, ay + 98 * US, 140 * US, 14 * US, S.air, ready and { 1, .75, .2, 1 } or { .5, .75, 1, 1 }, 20)
    U.text("h_airk", ready and "Space" or "Airstrike", ax - 100 * US, ay + 110 * US, 200 * US, 36 * US, 1.15, WHITE, "center", 20)
    if S.sol >= 8 then
        if U.button("h_merge", "Merge", SW - 300 * US, SH - 100 * US, 170, 76, "gold", { nokbd = true, fs = 2.3 }) then act = "merge" end
        U.text("h_mk", "M", SW - 300 * US - 85 * US, SH - 62 * US, 170 * US, 30 * US, 1.0, { 1, 1, 1, .8 }, "center", 21)
    end
    -- gate result pops over the squad
    for i = #HUD.pops, 1, -1 do
        local p = HUD.pops[i]
        p.t = p.t + dt
        if p.t > 1.3 then table.remove(HUD.pops, i)
        else
            local sx, sy = project(WX(S.x), 3.0, 0)
            local col = p.good and { .45, 1, .5, 1 } or (p.good == false and { 1, .4, .35, 1 } or WHITE)
            col[4] = clamp((1.3 - p.t) * 3, 0, 1)
            U.big("pop" .. i, p.txt, sx, sy - p.t * 110 * US, 3.4 * (1 + max(0, 0.25 - p.t) * 2), col, 3, 22)
        end
    end
    -- tutorial-ish first seconds
    if S.lvl == 1 and S.t < 6 then
        local a = clamp((6 - S.t) * 0.8, 0, 1)
        U.big("tut", "Drag Or A / D To Move", SW / 2, SH * 0.885, 2.6, { 1, 1, 1, a }, 2.5, 22)
        U.text("tut2", "Shoot Gates To Raise Them, Then Walk Through", SW / 2 - 500 * US, SH * 0.885 + 34 * US, 1000 * US, 50 * US, 1.7, { 1, 1, 1, a }, "center", 22)
    end
    return act
end

-- overlays drawn in every state (toasts, banner, hint, hurt vignette)
function HUD.overlays(dt)
    for i = #HUD.toasts, 1, -1 do
        local t = HUD.toasts[i]
        t.t = t.t + dt
        if t.t > 2.2 then table.remove(HUD.toasts, i) end
    end
    for i, t in ipairs(HUD.toasts) do
        local a = clamp(min(t.t * 6, (2.2 - t.t) * 3), 0, 1)
        local y = 200 * US + (i - 1) * 64 * US
        local s = 1 + max(0, 0.15 - t.t) * 2
        local w = (#t.txt * 21 + 80) * US
        U.rect("to" .. i, SW / 2 - w / 2, y - 26 * US, w, 54 * US, { t.col[1] * .55, t.col[2] * .55, t.col[3] * .55, .82 * a }, 27, 24)
        U.big("tt" .. i, t.txt, SW / 2, y, 2.1 * s, { 1, 1, 1, a }, 2, 25)
    end
    local b = HUD.ban
    if b then
        b.t = b.t + dt
        if b.t > 2.8 then HUD.ban = nil
        else
            local a = clamp(min(b.t * 4, (2.8 - b.t) * 3), 0, 1)
            local s = 1 + max(0, 0.25 - b.t) * 2
            U.rect("ban_bg", 0, SH * 0.36, SW, 170 * US, { .45, .05, .05, .55 * a }, 0, 24)
            U.big("ban_b", b.b, SW / 2, SH * 0.36 + 45 * US, 2.4, { 1, .8, .7, a }, 2, 25)
            U.big("ban_a", b.a, SW / 2, SH * 0.36 + 112 * US, 5.0 * s, { 1, 1, 1, a }, 4, 25)
        end
    end
    local h = HUD.hnt
    if h then
        h.t = h.t + dt
        if h.t > 4 then HUD.hnt = nil
        else
            local a = clamp(min(h.t * 4, (4 - h.t) * 2), 0, 1)
            local w = (#h.txt * 17 + 70) * US
            U.rect("hn_bg", SW / 2 - w / 2, 96 * US, w, 58 * US, { .05, .1, .25, .6 * a }, 29, 24)
            U.text("hn_t", h.txt, SW / 2 - w / 2, 96 * US, w, 58 * US, 1.7, { 1, 1, 1, a }, "center", 25)
        end
    end
    HUD.hurt_a = max(0, HUD.hurt_a - dt * 1.4)
    if HUD.hurt_a > 0.01 then
        local a = HUD.hurt_a
        local e = 70 * US
        U.rect("hv_l", 0, 0, e, SH, { .9, .05, .05, a }, 0, 3)
        U.rect("hv_r", SW - e, 0, e, SH, { .9, .05, .05, a }, 0, 3)
        U.rect("hv_t", e, 0, SW - 2 * e, e * 0.7, { .9, .05, .05, a * 0.8 }, 0, 3)
        U.rect("hv_b", e, SH - e * 0.7, SW - 2 * e, e * 0.7, { .9, .05, .05, a * 0.8 }, 0, 3)
    end
end

------------------------------------------------------------------ screens
local SCR = {}
G.SCR = SCR
local WCOL = { harbor = { .25, .62, .95, 1 }, canyon = { .9, .55, .28, 1 }, forest = { .85, .45, .2, 1 }, frost = { .45, .78, .95, 1 }, volcano = { .9, .3, .2, 1 } }
local function dim(a) U.rect("dim", 0, 0, SW, SH, { .04, .08, .2, a or 0.35 }, 0, 1) end
local function pills(sv)
    U.pill("mc", SW - 470 * US, 26 * US, 220, "coin", fmt(sv.coins), 30)
    U.pill("mm", SW - 236 * US, 26 * US, 200, "medal", fmt(sv.medals), 30)
end
local function ribbon(id, text, cx, cy, w, col, fs)
    w = w * US
    local h = 96 * US
    U.rect(id .. "s", cx - w / 2 + 6 * US, cy - h / 2 + 10 * US, w, h, { .05, .1, .25, .3 }, 30, 19.5)
    U.rect(id .. "l", cx - w / 2, cy - h / 2 + 8 * US, w, h, { col[1] * .6, col[2] * .6, col[3] * .6, 1 }, 30, 19.6)
    U.rect(id, cx - w / 2, cy - h / 2, w, h, col, 30, 19.7)
    U.rect(id .. "h", cx - w / 2 + 12 * US, cy - h / 2 + 6 * US, w - 24 * US, h * 0.36, { 1, 1, 1, .22 }, 20, 19.8)
    U.big(id .. "t", text, cx, cy, fs or 3.6, WHITE, 3, 20)
end

function SCR.title(dt, sv)
    local act
    pills(sv)
    local bob = math.sin(G.t * 2) * 5 * US
    -- solid title card: drop shadow, white rim, deep-blue face, top sheen (nothing from the world shows through)
    U.rect("logo_sh", SW / 2 - 512 * US, 84 * US, 1040 * US, 330 * US, { .02, .05, .15, .35 }, 64, 17.5)
    U.rect("logo_rim", SW / 2 - 528 * US, 62 * US, 1056 * US, 346 * US, { 1, 1, 1, 1 }, 68, 17.7)
    U.rect("logo_bg", SW / 2 - 520 * US, 70 * US, 1040 * US, 330 * US, { .1, .24, .55, 1 }, 60, 17.8)
    U.rect("logo_hl", SW / 2 - 500 * US, 80 * US, 1000 * US, 120 * US, { 1, 1, 1, .1 }, 50, 17.9)
    U.big("logo1", "Gatebreaker", SW / 2, 170 * US + bob, 9.0, { 1, .8, .22, 1 }, 6, 20)
    U.big("logo2", "Squad", SW / 2, 285 * US + bob, 6.4, { 1, 1, 1, 1 }, 5, 20)
    U.text("logo3", "Shoot The Gates  ·  Grow The Squad  ·  Break The Horde", SW / 2 - 600 * US, 338 * US, 1200 * US, 50 * US, 1.8, { 1, 1, 1, .95 }, "center", 20)
    local y0 = 560 * US
    local nx = min(sv.unlocked, #D.LEVELS)
    if U.button("t_play", "Play", SW / 2, y0, 440, 116, "green", { fs = 4.4 }) then act = "play" end
    U.text("t_play_s", "Level " .. nx .. "  ·  " .. D.LEVELS[nx].name, SW / 2 - 300 * US, y0 + 70 * US, 600 * US, 40 * US, 1.5, { 1, 1, 1, .95 }, "center", 21)
    if U.button("t_lv", "Levels", SW / 2 - 145 * US, y0 + 160 * US, 270, 86, "blue") then act = "levels" end
    if U.button("t_shop", "Shop", SW / 2 + 145 * US, y0 + 160 * US, 270, 86, "orange") then act = "shop" end
    if U.button("t_opt", "Options", SW / 2 - 145 * US, y0 + 272 * US, 270, 86, "white") then act = "options" end
    if U.button("t_quit", "Quit", SW / 2 + 145 * US, y0 + 272 * US, 270, 86, "red") then act = "quit" end
    U.text("t_help", "Mouse  ·  Arrows + Enter", SW / 2 - 300 * US, SH - 56 * US, 600 * US, 40 * US, 1.3, { 1, 1, 1, .85 }, "center", 20)
    return act
end

function SCR.levels(dt, sv)
    local act
    dim(0.38); pills(sv)
    ribbon("lv_r", "Choose A Level", SW / 2, 130 * US, 640, { .3, .6, 1, 1 })
    local cw, ch, gx, gy, cols = 330, 250, 24, 28, 5
    local x0 = SW / 2 - (cols * cw + (cols - 1) * gx) * US / 2
    local y0 = 230 * US
    for i, L in ipairs(D.LEVELS) do
        local c, r = (i - 1) % cols, floor((i - 1) / cols)
        local x, y = x0 + c * (cw + gx) * US, y0 + r * (ch + gy) * US
        local cx, cy = x + cw * US / 2, y + ch * US / 2
        local locked = i > sv.unlocked
        local wc = WCOL[L.world]
        local id = "lv" .. i
        if U.button(id, "", cx, cy, cw, ch, locked and "grey" or "white", { r = 24, z = 20 }) and not locked then act = i end
        local l0 = cx - cw * US / 2
        U.rect(id .. "_band", l0 + 10 * US, cy - ch * US / 2 + 10 * US, cw * US - 20 * US, 56 * US, locked and { .55, .58, .65, 1 } or wc, 18, 20.25)
        U.text(id .. "_n", tostring(i), l0 + 12 * US, cy - ch * US / 2 + 10 * US, 64 * US, 56 * US, 2.6, WHITE, "center", 20.4)
        U.text(id .. "_w", D.WORLDS[L.world].name, l0 + 70 * US, cy - ch * US / 2 + 10 * US, cw * US - 92 * US, 56 * US, 1.35, { 1, 1, 1, .95 }, "right", 20.4, false)
        U.text(id .. "_nm", L.name, l0, cy - 40 * US, cw * US, 50 * US, 1.85, locked and { 1, 1, 1, .9 } or { .12, .2, .42, 1 }, "center", 20.4, false)
        if locked then
            U.img(id .. "_lk", "lock", cx, cy + 50 * US, 60, 20.5, { 1, 1, 1, .9 })
        else
            local st = sv.stars[i] or 0
            for s = 1, 3 do U.star(id .. "_s" .. s, cx + (s - 2) * 58 * US, cy + 30 * US - (s == 2 and 8 * US or 0), s == 2 and 56 or 48, st >= s, 20.5) end
            local b = sv.best[i] or 0
            U.text(id .. "_bs", b > 0 and ("Best " .. fmt(b)) or "New", l0, cy + 66 * US, cw * US, 40 * US, 1.3, { .3, .38, .55, 1 }, "center", 20.4, false)
            if L.boss then U.img(id .. "_sk", "skull", cx + cw * US / 2 - 36 * US, cy + 72 * US, 44, 20.5) end
        end
    end
    if U.button("lv_back", "Back", 160 * US, SH - 80 * US, 230, 84, "white") or U.K.back then act = "back" end
    return act
end

-- shop: upgrades / heroes / arsenal
SCR.tab = "upg"
local function buy_ok(sv, cost) return sv.coins >= cost end
function SCR.shop(dt, sv)
    local act
    dim(0.45); pills(sv)
    ribbon("sh_r", "Shop", SW / 2, 110 * US, 420, { 1, .6, .18, 1 })
    local tabs = { { "upg", "Upgrades" }, { "hero", "Heroes" }, { "arms", "Arsenal" } }
    for i, t in ipairs(tabs) do
        local on = SCR.tab == t[1]
        if U.button("tab_" .. t[1], t[2], SW / 2 + (i - 2) * 300 * US, 222 * US, 270, 72, on and "blue" or "white", { fs = 2.2 }) then SCR.tab = t[1] end
    end
    if SCR.tab == "upg" then
        local cw, ch = 820, 112
        for i, u in ipairs(D.UPG) do
            local c, r = (i - 1) % 2, floor((i - 1) / 2)
            local cx = SW / 2 + (c - 0.5) * (cw + 30) * US
            local cy = 340 * US + r * (ch + 18) * US
            local l0, t0 = cx - cw * US / 2, cy - ch * US / 2
            U.card("uc" .. i, l0, t0, cw * US, ch * US, { .97, .97, 1, .97 }, 19)
            U.text("un" .. i, u.name, l0 + 26 * US, t0 + 8 * US, 440 * US, 50 * US, 2.0, { .12, .2, .42, 1 }, "left", 20, false)
            U.text("ud" .. i, u.desc, l0 + 26 * US, t0 + 56 * US, 460 * US, 40 * US, 1.3, { .35, .42, .6, 1 }, "left", 20, false)
            local lv = sv.up[u.key] or 0
            U.text("ul" .. i, "Lv " .. lv .. " / " .. u.max, l0 + 440 * US, t0 + 8 * US, 150 * US, 50 * US, 1.5, { .3, .38, .58, 1 }, "right", 20, false)
            bar("upb" .. i, l0 + 515 * US, t0 + 78 * US, 150 * US, 12 * US, lv / u.max, { .35, .75, 1, 1 }, 20, { .8, .84, .92, 1 })
            if lv >= u.max then
                U.text("um" .. i, "Max", cx + 230 * US, t0, 170 * US, ch * US, 2.0, { .3, .7, .35, 1 }, "center", 20, false)
            else
                local cost = D.upg_cost(u, lv)
                local ok = buy_ok(sv, cost)
                if U.button("ub" .. i, fmt(cost), cx + 315 * US, cy, 170, 76, ok and "green" or "grey", { fs = 2.1, z = 21 }) then
                    if ok then sv.coins = sv.coins - cost; sv.up[u.key] = lv + 1; act = "buy"; sfx("levelup") else sfx("gate_bad") end
                end
                U.coin_icon("ubc" .. i, cx + 248 * US, cy - 2 * US, 30, 22)
            end
        end
    elseif SCR.tab == "hero" then
        local cw, ch = 520, 300
        for i, h in ipairs(D.HEROES) do
            local c, r = (i - 1) % 3, floor((i - 1) / 3)
            local cx = SW / 2 + (c - 1) * (cw + 30) * US
            local cy = 450 * US + r * (ch + 26) * US
            local l0, t0 = cx - cw * US / 2, cy - ch * US / 2
            local own = sv.heroes[h.key]
            local eq = sv.hero == h.key
            U.card("hc" .. i, l0, t0, cw * US, ch * US, eq and { 1, .95, .8, .98 } or { .97, .97, 1, .97 }, 19)
            U.text("hn" .. i, h.name, l0, t0 + 14 * US, cw * US, 60 * US, 2.8, { .12, .2, .42, 1 }, "center", 20, false)
            U.text("hd" .. i, h.desc, l0 + 20 * US, t0 + 80 * US, cw * US - 40 * US, 90 * US, 1.35, { .35, .42, .6, 1 }, "center", 20, false)
            if eq then U.text("he" .. i, "Leading The Squad", l0, cy + 70 * US, cw * US, 60 * US, 1.8, { .85, .55, .1, 1 }, "center", 20, false)
            elseif own then
                if U.button("hb" .. i, "Select", cx, cy + 92 * US, 240, 76, "blue", { z = 21 }) then sv.hero = h.key; act = "buy" end
            else
                local ok = sv.coins >= h.coins and sv.medals >= h.medals
                if U.button("hb" .. i, fmt(h.coins), cx, cy + 92 * US, 240, 76, ok and "green" or "grey", { z = 21, fs = 2.1 }) then
                    if ok then sv.coins = sv.coins - h.coins; sv.heroes[h.key] = true; sv.hero = h.key; act = "buy"; sfx("levelup") else sfx("gate_bad") end
                end
                U.coin_icon("hbc" .. i, cx - 80 * US, cy + 90 * US, 30, 22)
                U.img("hm" .. i, "medal", cx - 60 * US, cy + 22 * US, 36, 20)
                U.text("hmt" .. i, "Needs " .. h.medals, cx - 36 * US, cy + 2 * US, 200 * US, 40 * US, 1.4, sv.medals >= h.medals and { .3, .6, .3, 1 } or { .8, .3, .25, 1 }, "left", 20, false)
            end
        end
        U.text("h_tip", "Medals: Beat A Boss Level For The First Time", SW / 2 - 500 * US, SH - 150 * US, 1000 * US, 40 * US, 1.4, { 1, 1, 1, .9 }, "center", 20)
    else
        local cw, ch = 330, 420
        for i, k in ipairs(D.WORDER) do
            local W = D.WEAPONS[k]
            local cx = SW / 2 + (i - 3) * (cw + 22) * US
            local cy = 520 * US
            local l0, t0 = cx - cw * US / 2, cy - ch * US / 2
            local own = sv.weapons[k]
            local eq = sv.weapon == k
            U.card("wc" .. i, l0, t0, cw * US, ch * US, eq and { 1, .95, .8, .98 } or { .97, .97, 1, .97 }, 19)
            U.img("wi" .. i, "w_" .. k, cx, t0 + 110 * US, 170, 20)
            U.text("wn" .. i, W.name, l0, t0 + 190 * US, cw * US, 56 * US, 2.5, { .12, .2, .42, 1 }, "center", 20, false)
            local info = ({ rifle = "Fast, Long Range", shotgun = "Spread Of 4 Pellets", minigun = "Bullet Storm", rocket = "Splash Damage", laser = "Pierces 3 Targets" })[k]
            U.text("wd" .. i, info, l0, t0 + 244 * US, cw * US, 40 * US, 1.35, { .35, .42, .6, 1 }, "center", 20, false)
            if eq then U.text("we" .. i, "Equipped", l0, cy + 120 * US, cw * US, 60 * US, 2.0, { .85, .55, .1, 1 }, "center", 20, false)
            elseif own then
                if U.button("wb" .. i, "Equip", cx, cy + 140 * US, 220, 76, "blue", { z = 21 }) then sv.weapon = k; act = "buy" end
            else
                local cost = D.WPRICE[k]
                local ok = sv.coins >= cost
                if U.button("wb" .. i, fmt(cost), cx, cy + 140 * US, 220, 76, ok and "green" or "grey", { z = 21, fs = 2.1 }) then
                    if ok then sv.coins = sv.coins - cost; sv.weapons[k] = true; sv.weapon = k; act = "buy"; sfx("levelup") else sfx("gate_bad") end
                end
                U.coin_icon("wbc" .. i, cx - 72 * US, cy + 138 * US, 30, 22)
            end
        end
        U.text("w_tip", "Your Squad Starts Each Level With The Equipped Weapon. Crates Swap It Mid-Run.", SW / 2 - 700 * US, SH - 150 * US, 1400 * US, 40 * US, 1.4, { 1, 1, 1, .9 }, "center", 20)
    end
    if U.button("sh_back", "Back", 160 * US, SH - 80 * US, 230, 84, "white") or U.K.back then act = "back" end
    return act
end

function SCR.pause(dt)
    local act
    dim(0.5)
    ribbon("pa_r", "Paused", SW / 2, 260 * US, 520, { .3, .6, 1, 1 })
    if U.button("pa_res", "Resume", SW / 2, 420 * US, 400, 96, "green", { fs = 3.2 }) then act = "resume" end
    if U.button("pa_ret", "Retry", SW / 2, 540 * US, 400, 86, "orange") then act = "retry" end
    if U.button("pa_opt", "Options", SW / 2, 650 * US, 400, 86, "white") then act = "options" end
    if U.button("pa_men", "Menu", SW / 2, 760 * US, 400, 86, "red") then act = "menu" end
    if U.K.back then act = "resume" end
    return act
end

-- res = { won, stars, coins, score, best, kills, surv, lvl, newbest, medal, t }
function SCR.result(dt, res)
    local act
    res.t = res.t + dt
    dim(0.42)
    local won = res.won
    local cw, ch = 760, 640
    local l0, t0 = SW / 2 - cw * US / 2, SH / 2 - ch * US / 2 + 20 * US
    U.card("rc", l0, t0, cw * US, ch * US, { .97, .97, 1, .97 }, 15)
    ribbon("rr", won and "Victory!" or "Squad Down", SW / 2, t0, 560, won and { .3, .78, .35, 1 } or { .9, .32, .3, 1 }, 4.0)
    U.text("rl", "Level " .. res.lvl .. "  ·  " .. D.LEVELS[res.lvl].name, l0, t0 + 64 * US, cw * US, 50 * US, 1.7, { .3, .38, .58, 1 }, "center", 16, false)
    if won then
        for s = 1, 3 do
            local on = res.stars >= s and res.t > 0.3 + s * 0.25
            local pop = on and (1 + max(0, 0.5 + s * 0.25 - res.t + 0.3) * 1.2) or 1
            U.star("rs" .. s, SW / 2 + (s - 2) * 120 * US, t0 + 180 * US - (s == 2 and 20 * US or 0), (s == 2 and 120 or 100) * pop, on, 16)
        end
    else
        U.text("rpr", string.format("Reached %d%% Of The Way", floor(res.prog * 100 + 0.5)), l0, t0 + 140 * US, cw * US, 60 * US, 2.2, { .8, .3, .25, 1 }, "center", 16, false)
        if res.hint then U.text("rh", res.hint, l0 + 30 * US, t0 + 200 * US, cw * US - 60 * US, 50 * US, 1.4, { .35, .42, .6, 1 }, "center", 16, false) end
    end
    local rows = { { "Survivors", fmt(res.surv) }, { "Kills", fmt(res.kills) }, { "Score", fmt(res.score) .. (res.newbest and "  New Best!" or "") }, { "Coins", "+" .. fmt(res.coins) } }
    if res.medal then rows[#rows + 1] = { "Medal", "+1" } end
    for i, r in ipairs(rows) do
        local y = t0 + 262 * US + (i - 1) * 50 * US
        U.text("rk" .. i, r[1], l0 + 90 * US, y, 300 * US, 46 * US, 1.8, { .35, .42, .6, 1 }, "left", 16, false)
        U.text("rv" .. i, r[2], l0 + 330 * US, y, cw * US - 420 * US, 46 * US, 2.0, { .12, .2, .42, 1 }, "right", 16, false)
    end
    local by = t0 + ch * US - 70 * US
    if won then
        local last = res.lvl >= #D.LEVELS
        if U.button("r_next", last and "Replay" or "Next", SW / 2 + 220 * US, by, 230, 92, "green", { fs = 3.0 }) then act = "next" end
    else
        if U.button("r_shop", "Shop", SW / 2 + 220 * US, by, 230, 92, "orange", { fs = 3.0 }) then act = "shop" end
    end
    if U.button("r_retry", "Retry", SW / 2, by, 200, 92, won and "blue" or "green", { fs = 2.8 }) then act = "retry" end
    if U.button("r_menu", "Menu", SW / 2 - 220 * US, by, 200, 92, "white", { fs = 2.8 }) then act = "menu" end
    if res.t < 0.6 then act = nil end
    return act
end
end
------------------------------------------------------------------ 08_main: states, fixed step, camera, music, save, test hooks
do
local U, D, SIM, R, HUD, SCR, BOT = G.UI, G.D, G.SIM, G.R, G.HUD, G.SCR, G.BOT
local US = U.US
paint_templates()
build_lights()
------------------------------------------------------------------ save
local SV
local function load_save()
    local ok, s = pcall(fs.read, D.SAVE)
    SV = D.deserialize(ok and s or "")
end
local function save() pcall(fs.write, D.SAVE, D.serialize(SV)) end
load_save()
G.SV = function() return SV end
G.save = save

------------------------------------------------------------------ level flow
local S
local STEP = 1 / 60
local acc, end_t, res = 0, 0, nil
local demo_lvl = 1
local function demo_save()
    local s = D.new_save()
    for k in pairs(s.up) do s.up[k] = 3 end
    s.up.squad = 6; s.up.fire = 6
    s.hero = SV.hero
    s.weapon = ({ "rifle", "minigun", "rifle", "shotgun", "laser" })[(demo_lvl - 1) % 5 + 1]
    return s
end
local function start(n, demo)
    n = clamp(n, 1, #D.LEVELS)
    S = SIM.start(n, demo and demo_save() or SV)
    G.S = S
    G.set_world(D.LEVELS[n].world)
    G.weapon_tint(D.WEAPONS[S.weapon].col)
    R.reset(); HUD.reset()
    acc, end_t, res = 0, 0, nil; G.strike_q = false
    G.tx = 0
    G.demo = demo
    G.cam_reset = true
    if not demo then G.state = "play"; music("music_battle") end
end
G.start_level = start
local function go(st)
    G.state = st
    if st == "title" or st == "levels" or st == "shop" then music("music_title") end
end
local function to_menu(st)
    demo_lvl = ({ 1, 3, 5, 7, 9 })[rand(1, 5)]
    start(demo_lvl, true)
    go(st or "title")
end

local HINTS = { "Tip: Shoot A Gate Before Walking Through - Every Hit Raises It", "Tip: Merge 5 Soldiers Into A Veteran - Elites Survive Longer",
    "Tip: Upgrade Starting Squad And Firepower In The Shop", "Tip: Save Airstrikes For Brutes And Bosses",
    "Tip: Crack Containers To Free Turrets, Gunships And Mechs", "Tip: Do Not Over-Shoot Orange Trap Gates" }
local function finish()
    local won = S.over == "win"
    local n = S.lvl
    local coins = floor(S.coins + 0.5)
    if not won then coins = floor(coins * 0.5) end
    SV.coins = SV.coins + coins
    local newbest = S.score > (SV.best[n] or 0)
    if won then
        if newbest then SV.best[n] = S.score end
        SV.stars[n] = max(SV.stars[n] or 0, S.stars or 1)
        local medal = false
        if D.LEVELS[n].boss and n >= SV.unlocked then SV.medals = SV.medals + 1; medal = true end
        SV.unlocked = max(SV.unlocked, min(#D.LEVELS, n + 1))
        res = { won = true, stars = S.stars or 1, coins = coins, score = S.score, kills = S.kills, surv = S.surv or SIM.worth(), lvl = n, newbest = newbest, medal = medal, t = 0 }
    else
        res = { won = false, stars = 0, coins = coins, score = S.score, kills = S.kills, surv = 0, lvl = n, prog = clamp(S.travel / (S.L.len + 30), 0, 1), hint = HINTS[rand(1, #HINTS)], t = 0 }
    end
    save()
    sfx(won and "win" or "lose")
    music(nil)
    G.state = won and "win" or "lose"
    G.res = res
end

------------------------------------------------------------------ input -> sim
local mx_last
local function steer_input(dt)
    local MS = U.MS
    local hud_zone = U.inside(SW - 420 * US, SH - 240 * US, 420 * US, 240 * US) or U.inside(SW - 130 * US, 0, 130 * US, 120 * US)
    if MS.down and not hud_zone then
        if mx_last then G.tx = G.tx + (MS.x - mx_last) / SW * 15 end
        mx_last = MS.x
    else mx_last = nil end
    local k = 0
    if anyheld("A", "Left") then k = k - 1 end
    if anyheld("D", "Right") then k = k + 1 end
    if k ~= 0 then G.tx = G.tx + k * 20 * dt end   -- was 11 m/s: keys now sweep the 10 m lane in 0.5 s
    G.tx = clamp(G.tx, -D.LANE, D.LANE)
end

------------------------------------------------------------------ camera
local CAM = { p = vec3(0, 10.5, -12.2), l = vec3(0, 0, 12) }
local function camera(dt)
    local st = G.state
    local x = WX(S.x)
    local n = min(SIM.units(), 60)
    local up = n * 0.03
    local p, l
    if G.demo then
        local a = G.t * 0.09
        p = vec3(x * 0.3 + math.sin(a) * 2.5, 9.6 + up, -11.6 - up * 0.5)
        l = vec3(x * 0.4 + math.sin(a) * 1.5, 0.2, 13)
    else
        local boss = S.boss and S.boss.arrived
        p = vec3(x * 0.38, 10.5 + up + (boss and 1.4 or 0), -12.2 - up * 0.6 - (boss and 1.5 or 0))
        l = vec3(x * 0.5, 0.0 + (boss and 0.8 or 0), 11.8 + (boss and 3 or 0))
        if st == "win" then local a = math.sin((res and res.t or 0) * 0.35) * 1.2; p = vec3(x * 0.6 + a, 4.5, -5.5); l = vec3(x * 0.8, 1.5, 12) end
    end
    if G.cam_reset then G.cam_reset = false; CAM.p, CAM.l = p, l end
    local k = 3.5
    CAM.p = vec3(damp(CAM.p.x, p.x, k, dt), damp(CAM.p.y, p.y, k, dt), damp(CAM.p.z, p.z, k, dt))
    CAM.l = vec3(damp(CAM.l.x, l.x, k, dt), damp(CAM.l.y, l.y, k, dt), damp(CAM.l.z, l.z, k, dt))
    local s = (S.shake or 0) * (G.demo and 0.3 or 1)
    s = s * s
    local sx, sy = (rand() - 0.5) * s * 0.9, (rand() - 0.5) * s * 0.6
    G.cam.pos = vec3(CAM.p.x + sx, CAM.p.y + sy, CAM.p.z)
    G.cam.look = vec3(CAM.l.x + sx * 0.4, CAM.l.y + sy * 0.4, CAM.l.z)
    cam:set_position(G.cam.pos); cam:look_at(G.cam.look)
end

------------------------------------------------------------------ frame
to_menu("title")
local function sim_steps(dt, input_fn)
    -- equal substeps (Crowd Master fix): split this frame's time into n identical steps of <= STEP instead of a fixed-STEP
    -- accumulator that alternates 0/1/2 steps per frame (that beat against the display rate and made the squad judder)
    local sp = G.test.speed or 1
    acc = min(acc + dt * sp, 0.2 * sp)
    if acc > 0 then
        local n = math.ceil(acc / STEP - 1e-6)
        local h = acc / n
        for _ = 1, n do
            SIM.step(h, input_fn())
            R.events(S)
        end
        acc = 0
    end
end
local function update(dt)
    dt = min(dt or 0.016, 0.1)
    G.t = G.t + dt
    flush_mats()
    U.begin_frame()
    local st = G.state
    if st == "options" then
        if not SET:update(dt) then G.state = G.opt_back or "title" end
        U.end_frame()
        R.draw(S, 0); camera(dt); update_lights(dt)
        return
    end
    U.poll(st)
    if st == "play" then
        steer_input(dt)
        local strike = G.strike_q or U.K.ok
        G.strike_q = false
        if G.test.auto then G.tx = BOT.target(S) end
        sim_steps(dt, function() local s = strike; strike = false; return { tx = G.tx, strike = s or (G.test.auto and S.air >= 1) } end)
        R.draw(S, dt)
        camera(dt)   -- camera BEFORE the HUD: world-anchored labels/bars project with this frame's camera (no 1-frame lag wobble)
        local act = HUD.play(S, dt, false)
        if act == "air" then G.strike_q = true end   -- consumed by the next sim step (one frame later)
        if act == "merge" or anyedge("M") then if S.sol >= 5 then SIM.merge_all() end end
        if S.over then
            end_t = end_t + dt
            if end_t > (S.over == "win" and 0.6 or 1.4) then finish() end
        end
        if act == "pause" or U.K.back or anyedge("P") then G.state = "pause"; sfx("click") end
    elseif st == "pause" then
        R.draw(S, 0)
        camera(dt)
        HUD.play(S, 0, false)
        local act = SCR.pause(dt)
        if act == "resume" then G.state = "play"
        elseif act == "retry" then start(S.lvl)
        elseif act == "options" then G.opt_back = "pause"; G.state = "options"; SET:open()
        elseif act == "menu" then to_menu("title") end
    elseif st == "win" or st == "lose" then
        -- the world keeps living behind the card (the squad cheers / the horde keeps coming)
        if st == "win" then R.draw(S, dt) else R.draw(S, dt * 0.3) end
        camera(dt)
        local act = SCR.result(dt, res)
        if act == "next" then start(min(#D.LEVELS, res.lvl + 1))
        elseif act == "retry" then start(res.lvl)
        elseif act == "shop" then to_menu("shop")
        elseif act == "menu" then to_menu("title") end
    else
        -- menus: attract run of the bot behind them
        sim_steps(dt, function() return { tx = BOT.target(S), strike = S.air >= 1 } end)
        if S.over then end_t = end_t + dt; if end_t > 2 then demo_lvl = demo_lvl % #D.LEVELS + 1; start(demo_lvl, true) end end
        R.draw(S, dt)
        camera(dt)
        HUD.play(S, dt, true)
        local act
        if st == "title" then
            act = SCR.title(dt, SV)
            if act == "play" then start(SV.unlocked)
            elseif act == "levels" then go("levels")
            elseif act == "shop" then go("shop")
            elseif act == "options" then G.opt_back = "title"; G.state = "options"; SET:open()
            elseif act == "quit" then save(); pcall(function() app.quit() end); pcall(function() engine.quit() end) end
        elseif st == "levels" then
            act = SCR.levels(dt, SV)
            if act == "back" then go("title") elseif type(act) == "number" then start(act) end
        elseif st == "shop" then
            act = SCR.shop(dt, SV)
            if act == "buy" then save() elseif act == "back" then go("title") end
        end
    end
    HUD.overlays(dt)
    U.end_frame()
    update_lights(dt)
end
G.update = update
G.test.menu = to_menu
hooks { update = update }
pe_log("[GB] ready")
end
