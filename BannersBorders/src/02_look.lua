------------------------------------------------------------------ 02_look: render settings, materials, the tabletop board
local function S(k, v) pcall(settings.set, k, v) end
G.setr = S
local ss = scene.add_empty_node("BBSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
S("taa", true); S("cas_sharpening", false); S("fxaa", false); S("motion_blur", false); S("dof", false)
S("hdr", true)
S("bloom", true); S("bloom_strength", 0.42); S("bloom_range", 1.1)
S("tonemapping", true)
S("ssao", true); S("ssao_radius", 0.6); S("ssao_intensity", 1.1)
S("ssr", true)
S("fog", true); S("fog_density", 0.0018); S("fog_start", 90.0)
S("shadows", true); S("shadow_map_size", 2048); S("shadow_distance", 110.0); S("shadow_filter_radius", 1.8)
S("render_scale", 1.0)
S("lod_enabled", false)   -- engine LOD simplification collapses the thin coast bevels into black jagged patches at map zoom
S("IBL", true); S("IBL_intensity", 1.0)
S("color_grading", true); S("color_grading_saturation", 1.12); S("color_grading_contrast", 1.05)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "Options", subtitle = "Banners & Borders", file = "Save/settings.cfg", music = true,
    click = function() sfx("click") end, defaults = { master = 0.5, difficulty = 2, lock_mouse = true },
    extra = { { id = "difficulty", label = "DIFFICULTY", kind = "cycle", values = { "RELAXED", "NORMAL", "HARD" } },
        { id = "lock_mouse", label = "LOCK MOUSE TO WINDOW", kind = "toggle" } },
    theme = { accent = { 0.25, 0.56, 0.94, 1 }, accent2 = { 0.95, 0.72, 0.25, 1 }, panel = { 0.16, 0.11, 0.07, 0.95 }, row = { 0.32, 0.23, 0.15, 0.85 },
        text = { 1, 0.97, 0.9, 1 }, dim = { 0.85, 0.78, 0.66, 1 }, selected_text = { 1, 1, 1, 1 } } })
SET:apply()
G.SET = SET
local function PS() return SET:particle_scale() end

------------------------------------------------------------------ materials
local PALS = { "capital", "fort", "town", "port", "mine", "tree", "tree2", "pine", "peak", "peak2", "crate", "shell", "ice" }
for f = 1, 5 do PALS[#PALS + 1] = "sol_" .. f; PALS[#PALS + 1] = "ber_" .. f; PALS[#PALS + 1] = "boat_" .. f end
for f = 0, 5 do PALS[#PALS + 1] = "flag_" .. f end
local function paint_pal(n, emk)
    mtex(n, "base_color", "Textures/pal.png"); mtex(n, "metallic_roughness", "Textures/pal_mr.png"); mtex(n, "emissive", "Textures/pal_em.png")
    mset(n, "base_color", vec4(1, 1, 1, 1)); mset(n, "emissive", vec3(emk, emk, emk)); mset(n, "roughness", 1.0); mset(n, "metallic", 1.0)
end
local function glow(name, base, em)
    local n = tnode(name); if not n then return end
    mrem(n, "emissive"); mrem(n, "base_color"); mrem(n, "metallic_roughness")
    mset(n, "base_color", vec4(base[1], base[2], base[3], 1)); mset(n, "emissive", vec3(em[1], em[2], em[3])); mset(n, "roughness", 0.5); mset(n, "metallic", 0.0)
end
local function wood(name, tint)
    local n = tnode(name); if not n then return end
    mtex(n, "base_color", "Textures/wood.png"); mtex(n, "normal", "Textures/wood_n.png")
    mset(n, "base_color", vec4(tint[1], tint[2], tint[3], 1)); mset(n, "roughness", 0.7); mset(n, "metallic", 0.0); mset(n, "emissive", vec3(0, 0, 0))
end
local function paint_templates()
    for _, name in ipairs(PALS) do local n = tnode(name); if n then paint_pal(n, 1.6) end end
    glow("ring_sel", { 1, .9, .55 }, { 2.4, 2.0, 1.0 })
    glow("ring_tgt", { 1, .45, .35 }, { 2.6, 1.0, 0.7 })
    glow("chev", { 1, 1, 1 }, { 1.6, 1.6, 1.6 })
    -- send-path dots: bright white core on an Azure rim (valid), grey core on a dark rim (no target)
    glow("dot", { 1, 1, 1 }, { 1.25, 1.3, 1.4 })
    glow("dot_bad", { .62, .6, .58 }, { .25, .24, .23 })
    glow("dot_rim", { .1, .32, .72 }, { .12, .38, .95 })
    local c = tnode("cloud"); if c then paint(c, { 1, 1, 1 }, { 0.35, 0.36, 0.4 }, 0.95, 0) end
    wood("bar", { 0.86, 0.66, 0.46 }); wood("table", { 0.62, 0.45, 0.32 })
    local d = tnode("deep"); if d then paint(d, { 0.05, 0.16, 0.26 }, { 0, 0, 0 }, 0.6, 0) end
    local b = tnode("blob"); if b then paint(b, { 0, 0, 0 }, { 0, 0, 0 }, 1, 0) end
    for _, name in ipairs({ "cloud", "bar", "table", "deep", "blob", "ring_sel", "ring_tgt", "chev", "dot", "dot_bad", "dot_rim" }) do local n = tnode(name); if n then n:set_position(HIDE) end end
    for _, name in ipairs(PALS) do local n = tnode(name); if n then n:set_position(HIDE) end end
end
G.paint_templates = paint_templates
-- live material write (no deferred replay): used for per-frame tile colour changes on long-lived nodes
local function mlive(n, k, v) pcall(_mset, n, k, v) end
G.mlive = mlive

------------------------------------------------------------------ board
local SH_OF = setmetatable({}, { __index = function(_, k) return BB_MAPS[k] and BB_MAPS[k].sh end })
local BD = { key = nil, tiles = {}, statics = {}, clouds = {} }
G.BD = BD
local function hash(i) local h = (i * 2654435761) % 4294967296; return (h % 100003) / 100003 end
G.hash = hash
local function tint_tile(i, col, em)
    local t = BD.tiles[i]; if not t then return end
    mlive(t.n, "base_color", vec4(col[1], col[2], col[3], 1))
    mlive(t.n, "emissive", vec3(em[1], em[2], em[3]))
end
G.tint_tile = tint_tile
local function hide_board()
    if not BD.key then return end
    local sh = SH_OF[BD.key]
    for _, t in ipairs(BD.tiles) do t.n:set_position(HIDE) end
    for _, nm in ipairs({ "land_", "ctx_", "sea_" }) do local n = tnode(nm .. sh); if n then n:set_position(HIDE) end end
    for _, s in ipairs(BD.statics) do F_put(s.kind, s.n) end
    BD.statics, BD.tiles = {}, {}
    BD.key = nil
end
G.hide_board = hide_board
local function stat(kind, x, y, z, s, ry)
    local n = F_get(kind)
    place(n, x, y, z, s, s, s, ry or 0)
    BD.statics[#BD.statics + 1] = { kind = kind, n = n }
    return n
end
local function build_board(key, R)
    if BD.key == key then return end
    hide_board()
    local M = BB_MAPS[key]
    local sh = SH_OF[key]
    BD.key, BD.M = key, M
    -- sea, land context, neighbouring countries
    local sea = tnode("sea_" .. sh)
    if sea then
        sea:set_position(vec3(0, 0, 0))
        mtex(sea, "base_color", "Textures/sea_" .. sh .. ".png"); mrem(sea, "normal")
        mset(sea, "base_color", vec4(1, 1, 1, 1)); mset(sea, "roughness", 0.18); mset(sea, "metallic", 0.0); mset(sea, "emissive", vec3(0, 0, 0))
    end
    local land = tnode("land_" .. sh)
    if land then
        land:set_position(vec3(0, 0, 0))
        mtex(land, "base_color", "Textures/grain.png"); mtex(land, "normal", "Textures/grain_n.png")
        mset(land, "base_color", vec4(0.93, 0.86, 0.68, 1)); mset(land, "roughness", 0.95); mset(land, "metallic", 0.0); mset(land, "emissive", vec3(0, 0, 0))
    end
    local ctx = tnode("ctx_" .. sh)
    if ctx then
        ctx:set_position(vec3(0, 0, 0))
        mtex(ctx, "base_color", "Textures/grain.png"); mtex(ctx, "normal", "Textures/grain_n.png")
        mset(ctx, "base_color", vec4(0.74, 0.78, 0.62, 1)); mset(ctx, "roughness", 0.95); mset(ctx, "metallic", 0.0); mset(ctx, "emissive", vec3(0, 0, 0))
    end
    -- region tiles: each has its own template node -> own material; owner colour is a pastel multiplied over the felt grain
    for i = 1, #M.regions do
        local n = tnode(string.format("r_%s_%02d", sh, i - 1))
        if n then
            n:set_position(vec3(0, 0, 0))
            mtex(n, "base_color", "Textures/grain.png"); mtex(n, "normal", "Textures/grain_n.png")
            mset(n, "roughness", 0.9); mset(n, "metallic", 0.0)
            local p = G.D.FAC[0].pastel
            mset(n, "base_color", vec4(p[1], p[2], p[3], 1)); mset(n, "emissive", vec3(0, 0, 0))
            BD.tiles[i] = { n = n, col = { p[1], p[2], p[3] }, em = 0, owner = -1 }
        end
    end
    -- scenery on each region (deco points come from the map pipeline, already inside the region shape)
    -- kept sparse and light: at the default zoom dense dark pines/peaks read as dirt specks on the felt
    for i, src in ipairs(M.regions) do
        local d = src.deco or {}
        local cnt, maxn = 0, (src.area or 40) > 60 and 4 or 3
        for j = 1, #d - 1, 2 do
            local x, z = d[j], d[j + 1]
            local dx, dz = x - src.x, z - src.z
            if dx * dx + dz * dz > 2.2 then   -- keep the castle / badge area clear
                cnt = cnt + 1
                if cnt > maxn then break end
                local hsh = hash(i * 31 + j)
                local kind
                if src.hill then kind = (hsh < 0.6) and "peak2" or "tree2"
                else kind = (hsh < 0.6) and "tree2" or "tree" end
                local s = (kind:sub(1, 4) == "peak") and (0.42 + 0.2 * hsh) or (0.26 + 0.12 * hsh)
                stat(kind, x, src.h, z, s, hsh * 360)
            end
        end
    end
    -- buildings by region type
    BD.bld = {}
    for i, r in ipairs(R) do
        local s = r.ty == "capital" and 0.62 or 0.52
        BD.bld[i] = stat(r.ty, r.x, r.h, r.z + 0.15, s, 180 + (hash(i * 3) - 0.5) * 30)
    end
    -- wooden frame around the sea + table
    local pe = M.pe
    local x0, x1, z0, z1 = -pe[3], -pe[1], pe[2], pe[4]
    local cx, cz, w, h = (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0
    stat("bar", cx, -0.05, z0 - 0.6, 1)
    BD.statics[#BD.statics].n:set_scale(vec3(w + 2.4, 1.1, 1.2))
    stat("bar", cx, -0.05, z1 + 0.6, 1); BD.statics[#BD.statics].n:set_scale(vec3(w + 2.4, 1.1, 1.2))
    stat("bar", x0 - 0.6, -0.05, cz, 1); BD.statics[#BD.statics].n:set_scale(vec3(1.2, 1.1, h))
    stat("bar", x1 + 0.6, -0.05, cz, 1); BD.statics[#BD.statics].n:set_scale(vec3(1.2, 1.1, h))
    stat("table", cx, -0.7, cz, 1); BD.statics[#BD.statics].n:set_scale(vec3(w * 3, 1, h * 3))
    stat("deep", cx, -0.02, cz, 1); BD.statics[#BD.statics].n:set_scale(vec3(w, 1, h))
    -- clouds: the engine has no per-object "cast shadows" switch and cloud shadows read as black holes on the sea,
    -- so the clouds now drift beyond the wooden frame and their shadows (sun offset ~+0.67*y in z) fall on the table, never on the map
    BD.clouds = {}
    for k = 1, 4 do
        local side = (k % 2 == 0) and 1 or -1
        local n = stat("cloud", 0, 7, 0, 1, hash(k) * 360)
        BD.clouds[k] = { n = n, x = x0 + hash(k * 13) * w, z = (side > 0) and (z1 + 5.5 + hash(k * 17) * 3) or (z0 - 10.5 - hash(k * 17) * 3),
            y = 9 + hash(k * 5) * 2, s = 1.1 + hash(k * 7) * 0.6, v = 0.25 + hash(k * 11) * 0.3, w = w, x0 = x0 }
        n:set_scale(vec3(BD.clouds[k].s, BD.clouds[k].s, BD.clouds[k].s))
    end
end
G.build_board = build_board
local function update_clouds(dt)
    for _, c in ipairs(BD.clouds) do
        c.x = c.x - c.v * dt
        if c.x < c.x0 - 6 then c.x = c.x0 + c.w + 6 end
        c.n:set_position(vec3(c.x, c.y, c.z))
    end
end
G.update_clouds = update_clouds

------------------------------------------------------------------ sky, sun, flash lights
local LT = { flash = {} }
local function build_lights()
    pcall(skybox.load, "table.hdr")
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, vec3(0.35, -0.78, 0.52), vec3(1, .95, .86), 3.4)
    for i = 1, 4 do LT.flash[i] = { idx = add_point(), t = 1, life = 1 }; set_point(LT.flash[i].idx, HIDE, vec3(1, 1, 1), 0, 1) end
end
G.build_lights = build_lights
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
G.update_lights = update_lights
G.fx_light = function(pos, col, power, life, radius) flash(pos.x, pos.y, pos.z, { col.x or col[1], col.y or col[2], col.z or col[3] }, power, life, radius) end
