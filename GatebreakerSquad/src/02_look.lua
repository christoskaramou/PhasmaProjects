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
