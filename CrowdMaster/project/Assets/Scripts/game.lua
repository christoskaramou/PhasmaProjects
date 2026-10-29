-- CROWD MASTER (Phasma Engine, Lua)
-- A Count Masters style crowd runner: steer a crowd of stickmen through math gates, merge pawns into brutes and giants,
-- crush red crowds, survive traps and treacherous terrain, then climb the Trophy Staircase or topple the King.
-- World: Y up, metres, the track runs along +Z, x = lateral (+ = right as seen from behind the crowd).
-- Fixed 60 Hz simulation with capped catch-up; everything game-specific lives in this project.
local PI = math.pi
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
math.randomseed(20261029)
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local function round(v) return floor(v + 0.5) end
local G = { state = "boot", t = 0, test = {} }
_G.CM = G

------------------------------------------------------------------ deferred materials (engine quirk: replay writes)
local _mset, _mtex, _mds = material.set, material.set_texture, material.set_double_sided
local mat_q = {}
local function qpush(f) mat_q[#mat_q + 1] = { f = f, n = 0 } end
local function mset(n, k, v) pcall(_mset, n, k, v); qpush(function() pcall(_mset, n, k, v) end) end
local function mtex(n, k, v) pcall(_mtex, n, k, v); qpush(function() pcall(_mtex, n, k, v) end) end
local function flush_mats()   -- replay in queue order so later writes (world tints) win over earlier ones (base paint)
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
G.SW, G.SH = SW, SH
local cam = (get_camera and get_camera()) or scene.get_cameras()[1]
local VFOV = math.rad(52)
local function set_vfov(v)
    VFOV = v
    pcall(function() cam:set_fov(math.deg(2 * math.atan(math.tan(VFOV / 2) * SW / SH))) end)
end
set_vfov(VFOV)
pcall(function() cam:set_far_plane(2500) end)
pcall(function() cam:set_near_plane(0.3) end)
G.cam = { pos = vec3(0, 7, -10), look = vec3(0, 0.5, 10) }
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
    if not n then pe_log("[CM] missing template " .. name); TPL[name] = false; return false end
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
G.POOL = POOL   -- debug access from MCP (lua.sh)
local function P_get(kind)
    local p = POOL[kind]; if not p then p = { n = {}, used = 0 }; POOL[kind] = p end
    p.used = p.used + 1
    local n = p.n[p.used]
    if not n then n = clone(kind); p.n[p.used] = n end
    return n
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

------------------------------------------------------------------ tiny serializer for the save file
local function ser(v, ind)
    ind = ind or ""
    local t = type(v)
    if t == "number" then return (v == floor(v)) and string.format("%d", v) or string.format("%.4f", v) end
    if t == "boolean" then return tostring(v) end
    if t == "string" then return string.format("%q", v) end
    if t == "table" then
        local parts = {}
        for k, x in pairs(v) do
            local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
            parts[#parts + 1] = ind .. " " .. key .. "=" .. ser(x, ind .. " ")
        end
        table.sort(parts)
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. ind .. "}"
    end
    return "nil"
end
local function deser(s)
    if not s or s == "" then return nil end
    local f = load("return " .. s, "@save", "t", {})
    if not f then return nil end
    local ok, v = pcall(f)
    return ok and type(v) == "table" and v or nil
end
------------------------------------------------------------------ render setup (common/RENDER_SETTINGS.md: TAA on, smooth bloom)
local function S(k, v) pcall(settings.set, k, v) end
local ss = scene.add_empty_node("CMSceneSettings"); ss:set_scene_settings(true)
pcall(settings.set_render_mode, "raster")
S("taa", true); S("cas_sharpening", false); S("fxaa", false); S("motion_blur", false); S("dof", false)
S("hdr", true)
S("bloom", true); S("bloom_strength", 0.42); S("bloom_range", 1.2)
S("tonemapping", true)
S("ssao", true); S("ssao_radius", 0.5); S("ssao_intensity", 0.9)
S("ssr", false)
S("fog", true); S("fog_density", 0.0018); S("fog_start", 60.0)
S("shadows", true); S("shadow_map_size", 2048); S("shadow_distance", 60.0); S("shadow_filter_radius", 1.5)
S("render_scale", 1.0)
S("IBL", true); S("IBL_intensity", 0.85)
S("color_grading", true); S("color_grading_saturation", 1.3); S("color_grading_contrast", 1.15)

local SET = load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")().new({
    title = "Options", subtitle = "Crowd Master", file = "Save/settings.cfg", music = true,
    click = function() sfx("click") end, defaults = { master = 0.5 },
    theme = { accent = { 0.25, 0.6, 1, 1 }, accent2 = { 1, 0.75, 0.2, 1 }, panel = { 0.07, 0.1, 0.18, 0.94 }, row = { 0.14, 0.2, 0.34, 0.8 },
        text = { 0.94, 0.96, 1, 1 }, dim = { 0.7, 0.76, 0.88, 1 }, selected_text = { 1, 1, 1, 1 } } })
SET:apply()
local function PS() return SET:particle_scale() end

------------------------------------------------------------------ palette {base, emissive, rough, metal, alpha}
local TEAM = {
    b = { { .16, .46, 1.0 }, { .0, .01, .04 }, .42, 0 },  -- pawn (blue)
    v = { { .45, .26, .98 }, { .01, .0, .04 }, .35, .1 }, -- brute (violet)
    y = { { 1.0, .74, .18 }, { .05, .03, 0 }, .28, .55 }, -- giant (gold)
    w = { { 1.0, .5, .12 }, { .04, .015, 0 }, .35, .2 },  -- boss breaker (orange)
    r = { { .95, .2, .22 }, { .04, 0, 0 }, .42, 0 },     -- enemy
    g = { { .62, .65, .7 }, { 0, 0, 0 }, .55, 0 },       -- captive
}
local PAL = {
    king = { { .9, .16, .18 }, { .03, 0, 0 }, .38, .05 }, crown = { { 1, .78, .2 }, { .08, .05, 0 }, .2, .9 }, club = { { .5, .32, .18 }, { 0, 0, 0 }, .7 },
    c_trk = { { 1, 1, 1 }, { 0, 0, 0 }, .55 }, c_trk2 = { { 1, 1, 1 }, { 0, 0, 0 }, .55 }, c_rail = { { .97, .97, 1 }, { .02, .02, .02 }, .35 },
    c_side = { { .5, .62, .82 }, { 0, 0, 0 }, .6 },
    c_step0 = { { .98, .36, .36 }, { 0, 0, 0 }, .35 }, c_step1 = { { 1, .62, .22 }, { 0, 0, 0 }, .35 }, c_step2 = { { 1, .86, .25 }, { 0, 0, 0 }, .35 },
    c_step3 = { { .36, .82, .45 }, { 0, 0, 0 }, .35 }, c_step4 = { { .3, .6, 1 }, { 0, 0, 0 }, .35 },
    c_oil = { { 1, 1, 1 }, { 0, 0, 0 }, .06, .3 }, c_mud = { { 1, 1, 1 }, { 0, 0, 0 }, .55 }, c_gravel = { { 1, 1, 1 }, { 0, 0, 0 }, .9 },
    c_thorn = { { 1, 1, 1 }, { 0, 0, 0 }, .85 }, c_ice = { { 1, 1, 1 }, { .03, .05, .06 }, .08, .05 }, c_warn = { { 1, 1, 1 }, { 0, 0, 0 }, .5 },
    c_glassb = { { .32, .66, 1 }, { .1, .26, .6 }, .18, 0 }, c_glassr = { { 1, .4, .4 }, { .5, .1, .1 }, .18, 0 },
    c_glassp = { { 1, .82, .3 }, { .5, .34, .05 }, .18, 0 },
    c_white = { { .96, .96, .98 }, { 0, 0, 0 }, .35 }, c_metal = { { .7, .72, .76 }, { 0, 0, 0 }, .25, .9 }, c_stone = { { 1, 1, 1 }, { 0, 0, 0 }, .85 },
    c_wood = { { .62, .42, .24 }, { 0, 0, 0 }, .7 }, c_gold = { { 1, .78, .22 }, { .06, .04, 0 }, .2, .95 }, c_dark = { { .08, .09, .12 }, { 0, 0, 0 }, .8 },
    c_water = { { 1, 1, 1 }, { 0, 0, 0 }, .12, 0 }, c_sand = { { 1, 1, 1 }, { 0, 0, 0 }, .9 }, c_grass = { { 1, 1, 1 }, { 0, 0, 0 }, .9 },
    c_redpaint = { { .92, .2, .2 }, { .02, 0, 0 }, .3, .1 }, c_finish = { { 1, 1, 1 }, { 0, 0, 0 }, .5 }, c_cloth = { { .95, .3, .3 }, { 0, 0, 0 }, .8 },
    post = { { .97, .97, 1 }, { .02, .02, .02 }, .3 }, post_warn = { { 1, 1, 1 }, { 0, 0, 0 }, .35 }, lamp = { { 1, .9, .5 }, { 1.4, 1.0, .3 }, .3 },
    spin_post = { { .3, .32, .38 }, { 0, 0, 0 }, .35, .7 }, spin_bar = { { .95, .22, .2 }, { .03, 0, 0 }, .25, .2 },
    saw = { { .9, .92, .95 }, { .02, .02, .02 }, .3, .6 }, saw_hub = { { .95, .25, .2 }, { 0, 0, 0 }, .3, .4 },
    hammer_handle = { { .55, .36, .2 }, { 0, 0, 0 }, .7 }, hammer_head = { { .92, .25, .22 }, { .02, 0, 0 }, .3, .3 },
    roller = { { .35, .36, .42 }, { 0, 0, 0 }, .35, .8 }, spikes = { { .85, .86, .9 }, { 0, 0, 0 }, .2, 1 },
    coin = { { 1, .8, .2 }, { .25, .16, 0 }, .2, 1 }, chest = { { 1, .78, .25 }, { .06, .04, 0 }, .25, .9 },
    trunk = { { .48, .33, .2 }, { 0, 0, 0 }, .85 }, foliage = { { .3, .7, .3 }, { 0, .01, 0 }, .7 }, pine = { { .16, .45, .28 }, { 0, .005, 0 }, .75 },
    rock = { { .62, .6, .58 }, { 0, 0, 0 }, .85 }, island = { { 1, 1, 1 }, { 0, 0, 0 }, .9 }, mountain = { { .5, .58, .55 }, { 0, 0, 0 }, .95 },
    snowcap = { { .95, .97, 1 }, { .02, .02, .03 }, .6 }, bush = { { .32, .66, .3 }, { 0, .01, 0 }, .7 }, thornspk = { { .4, .3, .2 }, { 0, 0, 0 }, .7 },
    tower = { { 1, 1, 1 }, { 0, 0, 0 }, .8 }, roof = { { .85, .22, .22 }, { .02, 0, 0 }, .5 }, flag = { { .95, .25, .25 }, { .03, 0, 0 }, .8 },
    pole = { { .8, .8, .84 }, { 0, 0, 0 }, .3, .8 },
    cage = { { .55, .38, .22 }, { 0, 0, 0 }, .7 }, crate = { { .72, .52, .3 }, { 0, 0, 0 }, .75 }, chute = { { .98, .98, 1 }, { .03, .03, .03 }, .7 },
    beach = { { 1, 1, 1 }, { 0, 0, 0 }, .9 }, mesa = { { .82, .5, .32 }, { 0, 0, 0 }, .9 }, railr = { { .97, .97, 1 }, { .02, .02, .02 }, .3, .1 },
    palm = { { .55, .4, .26 }, { 0, 0, 0 }, .85 }, fronds = { { .3, .66, .25 }, { 0, .01, 0 }, .7 }, cactus = { { .3, .6, .32 }, { 0, .01, 0 }, .65 },
}
local function paint_templates()
    for col, v in pairs(TEAM) do
        for _, p in ipairs({ "0", "1", "2", "3", "i", "c" }) do paint(tnode("man_" .. col .. p), v[1], v[2], v[3], v[4]) end
    end
    for name, v in pairs(PAL) do paint(tnode(name), v[1], v[2], v[3], v[4], v[5]) end
    for _, k in ipairs({ "oil", "mud", "gravel", "thorn", "ice", "warn", "finish", "sand", "grass", "stone" }) do mtex(tnode("c_" .. k), "base_color", "Textures/" .. k .. ".png") end
    mtex(tnode("c_trk"), "base_color", "Textures/trk.png"); mtex(tnode("c_trk2"), "base_color", "Textures/trk2.png")
    mtex(tnode("post_warn"), "base_color", "Textures/post_warn.png")
    mtex(tnode("island"), "base_color", "Textures/grass.png"); mtex(tnode("beach"), "base_color", "Textures/sand.png")
    mtex(tnode("tower"), "base_color", "Textures/stone.png")
    pcall(_mds, tnode("flag"), true); pcall(_mds, tnode("chute"), true)
    for name in pairs(TPL) do local n = tnode(name); if n then n:set_position(HIDE) end end
end

------------------------------------------------------------------ worlds (sky, light, sea, island + foliage colours)
local WORLDS = {
    { key = "meadow", name = "Meadow Isles", sky = "day.hdr", sun = { vec3(-0.35, -0.75, 0.55), vec3(1, .96, .9), 3.2 },
        water = { .1, .48, .92 }, island = { .75, 1, .7 }, beach = { 1, .95, .85 }, foliage = { .32, .72, .3 }, pine = { .16, .45, .28 }, rock = { .62, .6, .58 },
        mount = { .48, .6, .55 }, side = { .5, .62, .82 }, trk = { .95, .97, 1.02 }, rail = { 1, .84, .5 }, snow = false, ibl = 0.85 },
    { key = "canyon", name = "Sunbaked Canyon", sky = "canyon.hdr", sun = { vec3(-0.5, -0.65, 0.5), vec3(1, .9, .75), 3.4 },
        water = { .08, .55, .7 }, island = { 1.15, .85, .55 }, beach = { 1.05, .9, .7 }, foliage = { .45, .66, .25 }, pine = { .3, .5, .22 }, rock = { .78, .5, .34 },
        mount = { .8, .48, .3 }, side = { .82, .55, .4 }, trk = { 1.04, 1, .94 }, rail = { 1, .7, .52 }, snow = false, ibl = 0.8 },
    { key = "frost", name = "Frost Bay", sky = "frost.hdr", sun = { vec3(-0.3, -0.6, 0.6), vec3(.92, .96, 1), 3.0 },
        water = { .2, .5, .85 }, island = { 1.45, 1.5, 1.55 }, beach = { 1.3, 1.35, 1.4 }, foliage = { .85, .92, .98 }, pine = { .14, .38, .3 }, rock = { .6, .65, .72 },
        mount = { .7, .76, .86 }, side = { .55, .7, .9 }, trk = { .97, 1, 1.04 }, rail = { .68, .85, 1 }, snow = true, ibl = 0.95 },
    { key = "ember", name = "Ember Coast", sky = "ember.hdr", sun = { vec3(-0.6, -0.42, 0.62), vec3(1, .78, .58), 3.3 },
        water = { .16, .24, .52 }, island = { .9, .62, .5 }, beach = { 1, .8, .65 }, foliage = { .95, .5, .22 }, pine = { .7, .3, .18 }, rock = { .42, .36, .38 },
        mount = { .42, .32, .38 }, side = { .7, .45, .5 }, trk = { 1.03, .97, .95 }, rail = { 1, .66, .58 }, snow = false, ibl = 0.8 },
}
G.WORLDS = WORLDS
G.world_key = nil
local function set_world(w)
    if G.world_key == w.key then return end
    G.world_key = w.key
    pcall(skybox.load, w.sky)
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    lights.set_directional_light(0, w.sun[1], w.sun[2], w.sun[3])
    S("IBL_intensity", w.ibl)
    local function tint(name, c, r, m) local n = tnode(name); if n then mset(n, "base_color", vec4(c[1], c[2], c[3], 1)); if r then mset(n, "roughness", r) end end end
    tint("c_water", w.water); tint("island", w.island); tint("beach", w.beach); tint("foliage", w.foliage); tint("bush", w.foliage)
    tint("pine", w.pine); tint("rock", w.rock); tint("mountain", w.mount); tint("c_side", w.side); tint("c_trk", w.trk); tint("c_trk2", w.trk)
    tint("mesa", w.mount); tint("fronds", w.foliage); tint("c_rail", w.rail); tint("railr", w.rail)
end

------------------------------------------------------------------ lights: flashes that ride on events
local LT = { flash = {} }
local function build_lights()
    if #lights.get_directional_lights() == 0 then lights.add_directional() end
    for i = 1, 3 do LT.flash[i] = { idx = add_point(), t = 1, life = 1 }; set_point(LT.flash[i].idx, HIDE, vec3(1, 1, 1), 0, 1) end
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
G.fx_light = function(pos, col, power, life, radius) flash(pos.x, pos.y, pos.z, { col.x or col[1], col.y or col[2], col.z or col[3] }, power, life, radius) end

------------------------------------------------------------------ FX: particles over Scripts/Lib/particles.lua (premultiplied textures, screen blend)
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
function FX.shatter(x, y, z, col)      -- gate panel bursts into glassy shards flying forward
    for i = -1, 1 do
        FX.emit("debris", x + i * 0.9, y + 0.3 * i, z, { n = 9, vel = { 0, 3.5, 6 }, c0 = col, c1 = sc(col, 0.4), s0 = 0.12, s1 = 0.3, l0 = 0.5, l1 = 1.0,
            r = 0.8, sp = 7, drag = 0.9, grav = { 0, -14, 0 }, anim = 0.02 })
    end
    FX.emit("spark", x, y, z, { n = 12, vel = { 0, 2, 4 }, c0 = { 2, 2, 2 }, c1 = sc(col, 0.5), s0 = 0.05, s1 = 0.1, l0 = 0.2, l1 = 0.45, r = 1.2, sp = 8, drag = 1.5, grav = { 0, -6, 0 }, stretch = true })
end
function FX.boom(x, y, z, size)
    FX.lib:explosion(vec3(x, y, z), { size = size or 1, smoke = true, debris = { .45, .32, .22 }, spark_grav = -9 })
end
------------------------------------------------------------------ levels: 12 hand-made runs in 4 worlds; every 3rd ends in a boss
-- events (lane x: -4.5 .. 4.5, + = right as seen from behind the crowd):
--  g(z, a, b, kind)  gate pair; a/b = "+10" "x2" "-5" "/2" "M" (merge); kind = nil | "trick" | "timed" ; b = nil -> one full-width gate
--  E(z, n, x)        red crowd        cage(z, x, n, hp)  breakable cage of grey captives
--  coins(z, x, n)    a line of coins  drop(z, x, n)  air drop (+n), ally(z, x) a golden giant joins
--  spin(z, x, w)     spinning bar     saw(z, x0, x1, w)  saw lane     ham(z, x, ph)  swinging hammer
--  crush(z, x, w, ph) crusher block   roll(z, x, w)  spike roller rolling at you
--  pit(z0, z1, x0, x1)  hole          bridge(z0, z1, x0, x1)  only this strip is floor
--  ter(z0, z1, kind, x0, x1)  oil | ice | mud | gravel | thorn
local W = 4.5
local function g(z, a, b, kind) return { t = "gate", z = z, a = a, b = b, kind = kind } end
local function E(z, n, x) return { t = "enemy", z = z, n = n, x = x or 0 } end
local function cage(z, x, n, hp) return { t = "cage", z = z, x = x, n = n, hp = hp or n * 2 } end
local function coins(z, x, n, wave) return { t = "coins", z = z, x = x, n = n or 6, wave = wave } end
local function drop(z, x, n) return { t = "drop", z = z, x = x, n = n } end
local function ally(z, x) return { t = "ally", z = z, x = x } end
local function spin(z, x, w) return { t = "spin", z = z, x = x or 0, w = w or 1.5 } end
local function saw(z, x0, x1, w) return { t = "saw", z = z, x0 = x0, x1 = x1, w = w or 1.3 } end
local function ham(z, x, ph) return { t = "ham", z = z, x = x or 0, ph = ph or 0 } end
local function crush(z, x, w, ph) return { t = "crush", z = z, x = x, w = w or 3, ph = ph or 0 } end
local function roll(z, x, w) return { t = "roll", z = z, x = x, w = w or 4.5 } end
local function pit(z0, z1, x0, x1) return { t = "pit", z = z0, z0 = z0, z1 = z1, x0 = x0 or -W, x1 = x1 or W } end
local function bridge(z0, z1, x0, x1) return { t = "bridge", z = z0, z0 = z0, z1 = z1, x0 = x0, x1 = x1 } end
local function ter(z0, z1, kind, x0, x1) return { t = "ter", z = z0, z0 = z0, z1 = z1, kind = kind, x0 = x0 or -W, x1 = x1 or W } end
local function tip(z, text) return { t = "tip", z = z, text = text } end

local LEVELS = {
    { name = "First Steps", world = 1, len = 200, stair = 4, ev = {
        tip(4, "Drag Or Use A / D To Steer"),
        g(22, "+10", "+5"), coins(34, -2, 6), coins(34, 2, 6),
        g(56, "x2", "+8"), E(84, 14, 0), coins(100, 0, 8, true),
        g(118, "+15", "-5"), g(142, "x2", "+20"), E(166, 22, 1.5), coins(182, -1.5, 8) } },
    { name = "Spin Cycle", world = 1, len = 240, stair = 5, ev = {
        g(20, "+10", "x2"), spin(46, 0, 1.3), coins(58, 0, 6),
        cage(76, -2.3, 8, 14), coins(72, 2.3, 7), tip(88, "Merge: Two Pawns Become A Brute"),
        g(98, "M", "+10"), E(122, 25, 0), spin(144, 0, 1.8), coins(156, -2, 6),
        g(168, "x3", "+25"), g(192, "-10", "/2"), E(214, 32, -1), coins(228, 0, 8, true) } },
    { name = "King Of The Meadow", world = 1, len = 260, boss = 160, ev = {
        g(20, "+15", "x2"), saw(42, -4, 4, 1.2), coins(52, 0, 6),
        g(64, "x2", "+12"), ter(78, 100, "gravel", -W, 0.6), saw(88, 1.2, 4, 1.6), coins(84, -2.5, 8),
        drop(112, 2, 15), E(132, 40, 0), g(152, "M", "x2"), saw(172, -4, 4, 1.6), saw(180, -4, 4, -1.4),
        cage(198, 2.2, 12, 20), g(220, "+40", "x3"), E(242, 38, 0) } },
    { name = "Hot Sands", world = 2, len = 250, stair = 8, ev = {
        g(20, "+20", "x2"), ter(40, 62, "mud", -W, 0), coins(44, -2.5, 8), coins(44, 2.5, 3),
        tip(66, "Hammers Swing - Time Your Run"), ham(74, 0, 0), pit(92, 100, -1.6, 1.6), coins(96, -3.2, 4), coins(96, 3.2, 4),
        g(114, "x2", "+15"), E(134, 48, 0), ham(152, -2, 0), ham(160, 2, 0.5),
        pit(176, 184, -W, -0.4), g(198, "x3", "M"), E(218, 55, 1), coins(234, 0, 8, true) } },
    { name = "Slick Dunes", world = 2, len = 250, stair = 9, ev = {
        g(20, "+20", "x2"), tip(32, "Oil! You Slide - Units Can Slip Off"), ter(40, 66, "oil"), coins(52, 0, 8, true),
        tip(70, "Striped Gates Are Tricksters"), g(80, "x3", "-5", "trick"), crush(98, -2.2, 4.2, 0), crush(98, 2.2, 4.2, 0.5),
        ally(116, 3), E(134, 66, 0), g(152, "+30", "/2"), ter(168, 192, "oil"), pit(178, 188, 1, W),
        g(204, "x2", "M"), E(224, 80, -1), coins(240, 0, 8) } },
    { name = "Canyon King", world = 2, len = 270, boss = 420, ev = {
        g(20, "+25", "x2"), tip(32, "Lamp Gates Toggle - Watch The Light"), g(44, "x2", "+10", "timed"),
        roll(70, -2, 5), ter(86, 104, "mud", 0, W), ham(96, -1.5, 0), drop(112, -2, 20), E(128, 70, 0),
        tip(136, "Lamp Gate Ahead - Wait For The Light"), g(148, "x3", "+15", "timed"), roll(168, 2.4, 4.2), roll(186, -2.4, 4.2),
        cage(202, -2.2, 20, 30), coins(202, 2.4, 6),
        g(222, "M", "+30"), E(244, 85, 0) } },
    { name = "Thin Ice", world = 3, len = 260, stair = 12, ev = {
        g(20, "x2", "+20"), tip(30, "Ice: Fast And Slippery"), ter(40, 82, "ice"), saw(58, -4, 4, 1.4), coins(70, 0, 8, true),
        tip(86, "Narrow Bridge - Squeeze Through"), bridge(94, 112, -1.7, 1.7), E(128, 75, 0), g(146, "x3", "+30"),
        ter(160, 186, "ice"), saw(166, -4, 0, 1.6), saw(176, 0, 4, -1.6), bridge(192, 206, 0.8, W), coins(199, 2.6, 5),
        g(220, "M", "x2"), E(240, 90, 0) } },
    { name = "Frostbite", world = 3, len = 250, stair = 14, ease = 0.86, ev = {
        g(20, "+25", "x2"), tip(32, "Brambles Bleed Units - Big Ones Shrug"), ter(42, 62, "thorn", -W, -1), coins(46, -3, 8),
        spin(68, -2.25, 1.6), g(76, "x3", "+20"), g(100, "x3", "+30"), crush(112, -2.2, 4.4, 0.2),
        E(126, 100, 0), ter(140, 158, "thorn", 0.5, W), cage(150, 2.6, 25, 34), ter(168, 190, "ice"), ham(180, 0, 0),
        g(204, "x2", "M"), E(224, 120, 0), coins(238, 0, 8, true) } },
    { name = "Frost King", world = 3, len = 280, boss = 900, ev = {
        g(20, "x2", "+25"), ter(36, 60, "ice"), saw(46, -4, 4, 1.8), g(70, "x3", "-15", "trick"),
        bridge(86, 100, -W, -0.8), coins(93, -2.6, 5), E(114, 90, 0), g(132, "M", "x2", "timed"),
        roll(150, 2, 5), ter(150, 170, "thorn", -W, -1.5), drop(176, 0, 30), crush(192, -2.2, 4.4, 0), crush(192, 2.2, 4.4, 0.5),
        ally(206, -3), g(224, "x3", "+40"), E(250, 130, 0) } },
    { name = "Ember Trail", world = 4, len = 260, stair = 18, ev = {
        g(20, "+30", "x2"), ter(34, 56, "gravel"), spin(46, 0, 1.6), g(68, "x2", "-20", "timed"),
        pit(84, 92, -1.8, 1.8), ham(98, 2.2, 0), E(118, 140, 0), ter(134, 154, "oil"), pit(142, 150, -W, -1.6),
        g(166, "x3", "/2", "trick"), cage(184, 2.2, 30, 40), saw(196, -4, 4, 1.8), g(212, "M", "+40"), E(234, 170, 0) } },
    { name = "The Gauntlet", world = 4, len = 290, stair = 22, ev = {
        g(20, "x2", "+30"), roll(40, 0, 6), ter(56, 80, "thorn", 1, W), coins(66, 3, 6), crush(70, -2.4, 4.2, 0),
        g(92, "x3", "+20", "trick"), bridge(108, 124, -1.6, 1.6), E(140, 160, 0), drop(156, 2, 40),
        ter(168, 196, "ice"), saw(176, -4, 4, 2.0), ham(188, -1.5, 0.5), g(206, "x2", "-30", "timed"),
        ter(220, 240, "mud"), spin(230, 0, 2.0), g(252, "M", "x2"), E(272, 220, 0) } },
    { name = "Ember Throne", world = 4, len = 300, boss = 2600, ev = {
        g(20, "x2", "+30"), ham(38, 0, 0), ter(50, 74, "oil"), pit(60, 68, 1.2, W), g(84, "x3", "-15", "trick"),
        cage(100, 0, 35, 30), E(128, 120, 0), crush(136, 2.2, 4.4, 0.3), g(150, "M", "+40", "timed"),
        bridge(166, 180, -1.8, 1.8), roll(192, 2, 5), ally(204, 3), ter(214, 236, "thorn", -W, 0), saw(226, 0.5, 4, 1.8),
        g(246, "x3", "+50"), drop(262, -1.5, 40), E(280, 200, 0) } },
}
for i, L in ipairs(LEVELS) do
    L.idx = i
    table.sort(L.ev, function(a, b) return a.z < b.z end)
end
-- tuning (autoplay 05:15): red crowds and boss HP are sized from a "good line" through the level
-- (start 10 pawns, best gate each time, ~8% lost per trap, cages/drops/allies taken), so a smart
-- run always wins and upgrades make it comfortable. Ratio climbs with the level number.
local function sim_gate(p, b, v)
    local o, n = v:sub(1, 1), tonumber(v:sub(2)) or 2
    if o == "+" then p = p + n elseif o == "x" then p = p * n elseif o == "/" then p = math.floor(p / n)
    elseif o == "-" then local t = math.min(p, n); p = p - t; b = math.max(0, b - (n - t))
    elseif o == "M" then b = b + math.floor(p / 2) * 3; p = p % 2 end
    return p, b
end
for i, L in ipairs(LEVELS) do
    local p, b = 10, 0
    local f = (0.33 + 0.02 * i) * (L.ease or 1)   -- ease: per-level trim for crowd-heavy layouts
    for _, e in ipairs(L.ev) do
        local t = e.t
        if t == "gate" then
            local p1, b1 = sim_gate(p, b, e.a)
            if e.b then
                local p2, b2 = sim_gate(p, b, e.b)
                if e.kind == "timed" or e.kind == "trick" then
                    -- lamp / trick gates: a steady player reads them right only part of the time, so size the
                    -- crowds that follow from the middle of the two outcomes, not from a perfect read
                    p1, b1 = math.floor((p1 + p2) / 2 + 0.5), math.floor((b1 + b2) / 2 + 0.5)
                elseif p2 + b2 > p1 + b1 then p1, b1 = p2, b2 end
            end
            p, b = p1, b1
        elseif t == "cage" or t == "drop" then p = p + e.n
        elseif t == "ally" then b = b + 8
        elseif t == "spin" or t == "saw" or t == "ham" or t == "crush" or t == "roll" then p = math.floor(p * 0.85)
        elseif t == "enemy" then
            e.n = math.max(6, math.floor((p + b) * f + 0.5))
            local k = e.n; local t2 = math.min(p, k); p = p - t2; b = math.max(0, b - (k - t2))
        end
    end
    L.good = p + b
    if L.boss then L.boss = math.max(40, math.floor((p + b) * (0.4 + 0.012 * i))) end
end
G.LEVELS = LEVELS

------------------------------------------------------------------ floor: solid x intervals at a given z
local function floor_at(L, z)
    if z < -12 or z > L.len + 3 then
        if L.boss then return z < L.len + 75 and { { -W - 2, W + 2 } } or {} end
        return z < L.len + 14 and { { -W, W } } or {}
    end
    local iv = { { -W, W } }
    for _, e in ipairs(L.ev) do
        if (e.t == "pit" or e.t == "bridge") and z >= e.z0 and z < e.z1 then
            if e.t == "bridge" then
                local n = {}
                for _, s in ipairs(iv) do local a, b = max(s[1], e.x0), min(s[2], e.x1); if b > a then n[#n + 1] = { a, b } end end
                iv = n
            else
                local n = {}
                for _, s in ipairs(iv) do
                    if e.x1 <= s[1] or e.x0 >= s[2] then n[#n + 1] = s
                    else
                        if e.x0 > s[1] then n[#n + 1] = { s[1], e.x0 } end
                        if e.x1 < s[2] then n[#n + 1] = { e.x1, s[2] } end
                    end
                end
                iv = n
            end
        end
    end
    return iv
end
local function solid(iv, x) for _, s in ipairs(iv) do if x >= s[1] and x <= s[2] then return true end end return false end
local function terrain_at(L, x, z)
    for _, e in ipairs(L.ev) do
        if e.t == "ter" and z >= e.z0 and z < e.z1 and x >= e.x0 and x <= e.x1 then return e.kind end
        if e.z > z then break end
    end
    return nil
end
G.floor_at, G.solid, G.terrain_at = floor_at, solid, terrain_at
------------------------------------------------------------------ static track + world builder (lane x -> world X = -x)
local TILE = 6
local function LX(x) return -x end
-- flat track markings: every class gets its own layer so no two of them (and none of them and the track top at
-- y=0) ever share a plane. Bottoms float 2 mm above the track, tops are 4 mm apart -> plenty for a D32F reverse-Z
-- depth buffer even at grazing angles; still far too thin to see as a step.
local DECAL = { ter = { 0.002, 0.022 }, crush = { 0.002, 0.026 }, warn = { 0.002, 0.030 }, finish = { 0.002, 0.034 }, slot = { 0.002, 0.038 } }
G.DECAL = DECAL
local function box(kind, x0, x1, y0, y1, z0, z1, rot)
    local n = P_get(kind)
    n:set_position(vec3(LX((x0 + x1) / 2), (y0 + y1) / 2, (z0 + z1) / 2))
    n:set_scale(vec3(abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)))
    n:set_rotation(vec3(0, rot or 0, 0))
    return n
end
local function put(kind, x, y, z, s, ry, sy)
    local n = P_get(kind)
    n:set_position(vec3(LX(x), y, z)); n:set_scale(vec3(s, sy or s, s)); n:set_rotation(vec3(0, ry or 0, 0))
    return n
end
G.LX, G.box, G.put = LX, box, put

local function tree(world, x, y, z, s)
    local w = world.key
    if w == "canyon" then
        if rand() < 0.55 then put("cactus", x, y, z, s * rr(0.9, 1.4), rr(0, 360)) else
            local ry = rr(0, 360); put("palm", x, y, z, s * 1.3, ry); put("fronds", x, y, z, s * 1.3, ry) end
    elseif w == "frost" then
        local k = s * rr(0.9, 1.5); put("pine", x, y, z, k, rr(0, 360))
        -- snowcap = top of a unit cone r = 1 - 0.95y grown 2.5% outward (gen_meshes.py); fitted to the pine's top cone
        -- (base r 0.8 at y 3.5, apex at 5.1) it wraps it 2-4 cm proud instead of crossing the 14-sided cone
        put("snowcap", x, y + 3.5 * k, z, 0.8 * k, 0, 1.6 / 1.0526 * k)
    elseif w == "ember" then
        if rand() < 0.5 then local ry = rr(0, 360); put("palm", x, y, z, s * 1.3, ry); put("fronds", x, y, z, s * 1.3, ry)
        else put("trunk", x, y, z, s, 0); put("foliage", x, y, z, s * rr(0.9, 1.2), rr(0, 360)) end
    else
        if rand() < 0.6 then put("trunk", x, y, z, s, 0); put("foliage", x, y, z, s * rr(0.9, 1.25), rr(0, 360))
        else put("pine", x, y, z, s * rr(0.9, 1.3), rr(0, 360)) end
    end
end

local function build_world(L, world)
    local zend = L.boss and (L.len + 80) or (L.len + 14 + 20 * 2.4 + 12)
    G.zend = zend
    -- sea (flat colour: reflections come from IBL/SSR), wide enough to reach the horizon
    box("c_water", -3000, 3000, -10.5, -9.0, -3000, 3500)
    -- islands with sandy rims, trees, rocks, bushes
    math.randomseed(1000 + L.idx * 77)
    local z = -60
    while z < zend + 160 do
        for side = -1, 1, 2 do
            if rand() < 0.85 then
                local r = rr(8, 17); local x = side * (W + 8 + r * rr(0.7, 1.6)); local zz = z + rr(-12, 12)
                local top = rr(-5.5, -2.5)
                -- grass ("island") and sand ("beach") are two layers of ONE dome mesh (tools/gen_meshes.py isl_dome): the
                -- grass cap is the dome top pushed out along its normal, so both MUST share this exact transform.
                -- (Before: two different ellipsoids, scaled/offset independently, crossed at a grazing angle -> jagged
                -- grass/sand interleaving that looked like z-fighting.)  rr() call order is unchanged = same layouts.
                local sy = r * 0.35
                local pos, scl = vec3(LX(x), top - 0.4 * sy, zz), vec3(r, sy, r * rr(0.8, 1.2))
                local rot = vec3(0, rr(0, 360), 0)
                for _, kind in ipairs({ "beach", "island" }) do
                    local n = P_get(kind); n:set_position(pos); n:set_scale(scl); n:set_rotation(rot)
                end
                -- props sit on the dome surface (dome: y = -1 + 1.4*sqrt(1-rho^2) in unit space, top at 0.4), so they no
                -- longer hover over the slope; rho uses the narrower horizontal axis -> props sink slightly, never float
                local rmin = r * math.min(1, scl.z / r)
                local function yt(d) local q = math.min(0.95, d / rmin); return top - sy * 1.4 * (1 - math.sqrt(1 - q * q)) end
                for i = 1, floor(rr(3, 7)) do
                    local a, d = rr(0, 6.28), rr(0, r * 0.6)
                    tree(world, x + cos(a) * d, yt(d) - 0.25, zz + sin(a) * d * 0.8, rr(0.9, 1.5))
                end
                for i = 1, 3 do
                    local a, d = rr(0, 6.28), rr(r * 0.3, r * 0.8)
                    if world.key == "canyon" or world.key == "ember" or rand() < 0.5 then put("rock", x + cos(a) * d, yt(d) - 0.3, zz + sin(a) * d * 0.8, rr(0.8, 1.8), rr(0, 360))
                    else put("bush", x + cos(a) * d, yt(d) - 0.2, zz + sin(a) * d * 0.8, rr(1.0, 1.8), rr(0, 360)) end
                end
            end
        end
        z = z + rr(34, 52)
    end
    -- far range: mountains (meadow/frost/ember) or mesas (canyon), placed ahead and to the sides
    -- cone meshes have one UV seam edge (local +X); if it lands exactly on the silhouette it renders as a thin
    -- dark diagonal across the sky, so every backdrop cone turns its seam straight away from the track
    local function seam_away(x, zz)
        -- mountain/snowcap/mesa meshes are now seamless (tools/gen_meshes.py stube), which removed the dark
        -- silhouette crack; this yaw choice is kept only so far-backdrop layouts stay identical.
        -- (old note) the cone's UV seam (local +X) showed as a dark line when it landed on the silhouette;
        -- the camera always looks down +z, so point the seam mostly along +z (away from the viewer)
        -- pick the yaw whose seam stays farthest from the silhouette for every camera that can see
        -- this mountain (run/stairs/win cameras sit on the track centre looking down +z)
        local wx, best, bestv = LX(x), 0, -1
        for deg = 0, 355, 5 do
            local t = math.rad(deg); local sx, sz = math.cos(t), math.sin(t)
            local worst = 2
            for cz = -30, zend + 10, 15 do
                local vx, vz = wx, zz - cz; local d = math.sqrt(vx * vx + vz * vz)
                if vz > 0 and math.abs(vx) < vz * 1.3 then
                    worst = math.min(worst, math.abs(sx * vx + sz * vz) / d)
                end
            end
            if worst > bestv then best, bestv = deg, worst end
        end
        return best
    end
    for i = 1, 26 do
        local a = rr(-1.25, 1.25); local d = rr(420, 900)
        local x, zz = sin(a) * d, zend * 0.5 + cos(a) * d
        local s = rr(60, 140)
        if world.key == "canyon" then
            put("mesa", x, -9.5, zz, s * 0.9, seam_away(x, zz), s * rr(0.35, 0.7)); rr(0, 1)
        else
            local hgt = s * rr(0.6, 0.95)
            local m = P_get("mountain"); m:set_position(vec3(LX(x), -9.5, zz)); m:set_scale(vec3(s, hgt, s)); m:set_rotation(vec3(0, seam_away(x, zz), 0)); rr(0, 1)
            if world.key ~= "ember" and hgt > 60 then local c = P_get("snowcap"); c:set_position(vec3(LX(x), -9.5, zz)); c:set_scale(vec3(s, hgt, s)); c:set_rotation(m:get_rotation()) end
        end
    end
    -- side islands near the start so the opening shot is framed
    math.randomseed(G.t * 1000 % 100000)
end

local function build_track(L)
    -- breakpoints: tiles + pit/bridge edges
    local zs = {}
    local z0, z1 = -24, L.len + 14
    if L.boss then z1 = L.len + 3 end
    for z = z0, z1, TILE do zs[#zs + 1] = z end
    zs[#zs + 1] = z1
    for _, e in ipairs(L.ev) do if e.t == "pit" or e.t == "bridge" then zs[#zs + 1] = e.z0; zs[#zs + 1] = e.z1 end end
    table.sort(zs)
    local ti = 0
    for i = 1, #zs - 1 do
        local a, b = zs[i], zs[i + 1]
        if b - a > 0.01 then
            ti = ti + 1
            local iv = floor_at(L, (a + b) / 2)
            local oil = false
            for _, e in ipairs(L.ev) do if e.t == "ter" and e.kind == "oil" and a < e.z1 and b > e.z0 then oil = true end end
            for _, s in ipairs(iv) do
                box((ti % 5 == 0) and "c_trk2" or "c_trk", s[1], s[2], -0.3, 0, a, b)
                box("c_side", s[1] + 0.05, s[2] - 0.05, -1.5, -0.25, a, b)
                -- rounded lips along every edge (rails only where the edge is the track border and not oily)
                for _, ex in ipairs({ s[1], s[2] }) do
                    local lip = P_get("railr"); lip:set_position(vec3(LX(ex), -0.15, (a + b) / 2)); lip:set_scale(vec3(0.16, 0.16, b - a))
                    if abs(abs(ex) - W) < 0.01 and not oil then
                        local r = P_get("railr"); r:set_position(vec3(LX(ex + (ex > 0 and 0.12 or -0.12)), 0.38, (a + b) / 2)); r:set_scale(vec3(0.11, 0.11, b - a))
                    end
                end
            end
        end
    end
    -- support pillars down into the sea
    for z = 0, z1, 30 do
        local iv = floor_at(L, z)
        if #iv > 0 then
            local c = (iv[1][1] + iv[#iv][2]) / 2
            local p = P_get("railr"); p:set_position(vec3(LX(c), -5.2, z)); p:set_scale(vec3(1.1, 1.1, 7.6)); p:set_rotation(vec3(90, 0, 0))
        end
    end
    -- pit / bridge hazard stripes along the drop edges
    for _, e in ipairs(L.ev) do
        if e.t == "pit" then
            box("c_warn", e.x0, e.x1, DECAL.warn[1], DECAL.warn[2], e.z0 - 0.7, e.z0)
            box("c_warn", e.x0, e.x1, DECAL.warn[1], DECAL.warn[2], e.z1, e.z1 + 0.7)
        elseif e.t == "bridge" then
            box("c_warn", e.x0, e.x1, DECAL.warn[1], DECAL.warn[2], e.z0 - 0.8, e.z0)
        elseif e.t == "ter" then
            local zz = e.z0
            while zz < e.z1 - 0.01 do
                local zb = min(e.z1, zz + 4.5)
                box("c_" .. e.kind, e.x0 + 0.02, e.x1 - 0.02, DECAL.ter[1], DECAL.ter[2], zz, zb)
                zz = zb
            end
            -- readable cue at the entry: a warning stripe
            box("c_warn", e.x0, e.x1, DECAL.warn[1], DECAL.warn[2], e.z0 - 0.5, e.z0)
        end
    end
    box("c_finish", -W, W, DECAL.finish[1], DECAL.finish[2], L.len - 1, L.len + 1)
    -- finale ground
    if L.boss then
        local a = L.len + 3
        box("c_stone", -W - 2, W + 2, -0.3, 0, a, a + 72)
        box("c_side", -W - 1.95, W + 1.95, -1.6, -0.25, a, a + 72)
        local p = P_get("railr"); p:set_position(vec3(0, -5.2, a + 30)); p:set_scale(vec3(2, 2, 7.6)); p:set_rotation(vec3(90, 0, 0))
        -- castle at the end
        local cz = a + 64
        for _, tx in ipairs({ -8, 8 }) do
            put("tower", tx, 0, cz, 1.2, 0); put("roof", tx, 0.4, cz, 1.2, 0)
            put("pole", tx, 12.4, cz, 1.3, 0)
            local f = put("flag", tx, 14.6, cz, 1.6, 0); G.flags = G.flags or {}; G.flags[#G.flags + 1] = f
        end
        box("c_stone", -6.5, 6.5, 0, 6.5, cz - 1, cz + 1)
        box("c_stone", -6.5, -2.2, 6.5, 7.4, cz - 1.1, cz + 1.1); box("c_stone", 2.2, 6.5, 6.5, 7.4, cz - 1.1, cz + 1.1)
        G.castle_gate = box("c_wood", -2.2, 2.2, 0, 4.8, cz - 1.2, cz - 1.0)
        box("c_gold", -2.6, 2.6, 4.8, 5.4, cz - 1.25, cz - 1.0)
    else
        local a = L.len + 14
        G.stairs = { z0 = a, n = 20, d = 2.4, h = 0.9 }
        for i = 1, 20 do
            local zz = a + (i - 1) * 2.4
            box("c_step" .. ((i - 1) % 5), -W, W, -1.5, i * 0.9, zz, zz + 2.4)
        end
        local top = a + 20 * 2.4
        box("c_step4", -W, W, -1.5, 20 * 0.9, top, top + 6)
        G.chest = put("chest", 0, 18, top + 3, 1.6, 0)
    end
end

local function build_level(L)
    P_reset()
    G.flags = {}; G.chest = nil; G.stairs = nil; G.castle_gate = nil
    local world = G.WORLDS[L.world]
    set_world(world)
    G.world = world
    build_world(L, world)
    build_track(L)
end
G.build_level = build_level
------------------------------------------------------------------ crowd: tiers, formation, run, gates, enemies, traps, terrain
local C = { units = {}, dead = {}, cnt = { 0, 0, 0, 0 }, cx = 0, cxt = 0, cz = 0, vx = 0, speed = 0 }
local R = { list = {}, coins = {}, labels = {} }
local RUN = { stats = {} }
G.C, G.R, G.RUN = C, R, RUN
do
-- tier 1 Pawn, 2 Brute (2 pawns), 3 Giant (2 brutes), 4 Breaker (boss-breaker gem unit)
local T = {
    { name = "Pawn", pow = 1, hp = 1, s = 1.0, rad = 0.3, col = "b", cap = 110, area = 1.0 },
    { name = "Brute", pow = 3, hp = 2, s = 1.5, rad = 0.46, col = "v", cap = 32, area = 2.4 },
    { name = "Giant", pow = 8, hp = 4, s = 2.25, rad = 0.7, col = "y", cap = 12, area = 5.2 },
    { name = "Breaker", pow = 2, hp = 1, s = 1.2, rad = 0.36, col = "w", cap = 12, area = 1.4, boss = 4 },
}
G.T = T
local MESH = {}
local function mesh(col, p) local k = col .. p; local m = MESH[k]; if m == nil then m = mesh_of("man_" .. k) or false; MESH[k] = m end; return m end
local TEAMRGB = { b = { .3, .6, 1.4 }, v = { .7, .45, 1.4 }, y = { 1.4, 1.1, .4 }, w = { 1.4, .8, .3 }, r = { 1.4, .35, .3 }, g = { .9, .9, .95 } }
G.TEAMRGB = TEAMRGB

function C.power() local c = C.cnt; return c[1] + c[2] * 3 + c[3] * 8 + c[4] * 2 end
function C.total() local c = C.cnt; return c[1] + c[2] + c[3] + c[4] end
-- visible units -> one real unit each, except pawns past the cap (ratio)
function C.ratio(t) local v = 0; for _, u in ipairs(C.units) do if u.t == t then v = v + 1 end end; return v > 0 and C.cnt[t] / v or 1 end

local function new_unit(t, x, z)
    local n = F_get("man_" .. T[t].col .. "0")
    local u = { t = t, n = n, ox = x or 0, oz = z or 0, tx = 0, tz = 0, ph = rand() * 4, fr = -1, hp = T[t].hp, inv = 0, y = 0, born = 0 }
    n:set_scale(vec3(T[t].s, T[t].s, T[t].s)); n:set_rotation(vec3(0, 0, 0))
    return u
end
-- formation: biggest in the middle, phyllotaxis by area, squeezed into the floor strip
local GOLDEN = 2.39996
function C.formation()
    local list = C.units
    table.sort(list, function(a, b) local pa, pb = T[a.t].area, T[b.t].area; if pa ~= pb then return pa > pb end; return (a.id or 0) < (b.id or 0) end)
    local acc = 0
    local rmax = 0.1
    for i, u in ipairs(list) do
        local a = T[u.t].area
        acc = acc + a
        local r = sqrt(acc - a * 0.5) * 0.36
        local ang = i * GOLDEN
        u.fx, u.fz = cos(ang) * r, sin(ang) * r * 0.9
        rmax = max(rmax, r + T[u.t].rad)
    end
    C.rmax = rmax
end
function C.layout(hwmax)
    local k = 1
    if C.rmax > hwmax then k = hwmax / C.rmax end
    local kz = min(1 / k, 3.2)
    for _, u in ipairs(C.units) do u.tx, u.tz = u.fx * k, u.fz * kz end
    C.hw = min(C.rmax, hwmax); C.hd = C.rmax * kz
end

local function team_col(t) return TEAMRGB[T[t].col] end
-- bring the visible units in line with the real counts (spawn / vanish with a puff)
local seq_id = 0
function C.sync(fx, on_remove)
    local vis = { 0, 0, 0, 0 }
    for _, u in ipairs(C.units) do vis[u.t] = vis[u.t] + 1 end
    local changed = false
    for t = 1, 4 do
        local want = min(C.cnt[t], T[t].cap)
        while vis[t] < want do
            local a, r = rand() * 6.28, rand() * (C.rmax or 1) * 0.8
            local u = new_unit(t, cos(a) * r, sin(a) * r); seq_id = seq_id + 1; u.id = seq_id; u.born = 0.25
            C.units[#C.units + 1] = u; vis[t] = vis[t] + 1; changed = true
            if fx ~= false and rand() < 0.5 then local c = team_col(t); G.FX.puff(LX(C.cx + u.ox), 0.6, C.cz + u.oz, c, 0.6) end
        end
        while vis[t] > want do
            local bi
            for i = #C.units, 1, -1 do if C.units[i].t == t then bi = i; break end end
            if not bi then break end
            local u = table.remove(C.units, bi); vis[t] = vis[t] - 1; changed = true
            if on_remove then on_remove(u) else
                if fx ~= false and rand() < 0.6 then G.FX.puff(LX(C.cx + u.ox), 0.6, C.cz + u.oz, team_col(t), 0.6) end
                F_put("man_" .. T[t].col .. "0", u.n)
            end
        end
    end
    if changed or C.dirty then C.formation(); C.dirty = false end
end
-- damage in power units, pawns first (used by clashes, - gates, bosses)
function C.damage(p)
    local c = C.cnt
    while p > 0 and C.power() > 0 do
        if c[1] > 0 then local k = min(c[1], p); c[1] = c[1] - k; p = p - k
        elseif c[4] > 0 then c[4] = c[4] - 1; p = p - 2
        elseif c[2] > 0 then C.bdmg = (C.bdmg or 0) + p; local k = min(c[2], floor(C.bdmg / 3)); c[2] = c[2] - k; C.bdmg = C.bdmg - k * 3; p = 0
            if k == 0 then break end
        elseif c[3] > 0 then C.gdmg = (C.gdmg or 0) + p; local k = min(c[3], floor(C.gdmg / 8)); c[3] = c[3] - k; C.gdmg = C.gdmg - k * 8; p = 0
            if k == 0 then break end
        else break end
    end
    if c[2] == 0 then C.bdmg = 0 end
    if c[3] == 0 then C.gdmg = 0 end
end
-- remove one visible unit (trap / fall / bleed); real count drops by its share
function C.lose_unit(u, how, vx, vy, vz)
    for i, v in ipairs(C.units) do if v == u then table.remove(C.units, i); break end end
    local share = (u.t == 1) and max(1, round(C.cnt[1] / max(1, (C.vis1 or 1)))) or 1
    C.cnt[u.t] = max(0, C.cnt[u.t] - share)
    C.lost = (C.lost or 0) + share
    local wx, wz = C.cx + u.ox, C.cz + u.oz
    local d = { n = u.n, t = u.t, x = wx, y = u.y, z = wz, vx = vx or rr(-3, 3), vy = vy or rr(4, 7), vz = vz or rr(-1, 3), rx = 0, rz = 0, sp = rr(-500, 500), life = 0, how = how }
    C.dead[#C.dead + 1] = d
    if how == "fall" then d.vy = 0; d.vx = (u.ox > 0) and 1.5 or -1.5; d.vz = C.speed * 0.8 end
    C.dirty = true
    G.on_loss(u.t, how)
end
function C.hurt(u, how, vx, vy, vz)
    if u.inv > 0 then return false end
    if G.shield_t and G.shield_t > 0 then u.inv = 0.4; G.FX.sparks(LX(C.cx + u.ox), 0.8, C.cz + u.oz, 4, nil, 4, { .6, 1.2, 2 }); return false end
    if rand() < G.armor_chance() then u.inv = 0.5; G.FX.sparks(LX(C.cx + u.ox), 0.8, C.cz + u.oz, 4, nil, 4, { 1.4, 1.4, 1.4 }); G.popup_at("Blocked!", C.cx + u.ox, 2, C.cz + u.oz, { .8, .9, 1, 1 }, 0.8); return false end
    u.hp = u.hp - 1
    if u.hp <= 0 then C.lose_unit(u, how, vx, vy, vz); return true end
    u.inv = 0.8; G.sfx_hit()
    G.FX.sparks(LX(C.cx + u.ox), T[u.t].s, C.cz + u.oz, 8)
    return false
end

-- animation: swap run poses; units bob and lean; fallers tumble
local POSE = { "0", "1", "2", "3" }
function C.animate(dt, mode, ox, oz)
    local sp = C.speed
    C.vis1 = 0
    for _, u in ipairs(C.units) do
        if u.t == 1 then C.vis1 = C.vis1 + 1 end
        local s = T[u.t].s
        local fr
        if mode == "idle" then fr = "i" elseif mode == "cheer" then fr = (floor(G.t * 3 + u.ph) % 2 == 0) and "c" or "i"
        else u.ph = u.ph + dt * (2.2 + sp * 0.75) / s; fr = POSE[floor(u.ph) % 4 + 1] end
        if fr ~= u.fr then u.fr = fr; local m = mesh(T[u.t].col, fr); if m then u.n:set_mesh_ref(m) end end
        local bs = s
        if u.born > 0 then u.born = max(0, u.born - dt); bs = s * (1 - u.born / 0.25 * 0.8) end
        if u.inv > 0 then u.inv = u.inv - dt; if floor(u.inv * 12) % 2 == 0 then bs = bs * 1.12 end end
        -- run bob: lift at the flight phase of each stride (poses 1 and 3), a tiny hop when cheering
        local bob = 0
        if mode == "run" and sp > 0.5 then bob = abs(sin(u.ph * PI * 0.5)) * 0.085 * s
        elseif mode == "cheer" then bob = max(0, sin(G.t * 9.4 + u.ph * 2)) * 0.16 * s end
        u.n:set_position(vec3(LX(C.cx + u.ox), u.y + bob + (C.cy or 0), C.cz + u.oz))
        u.n:set_scale(vec3(bs, bs, bs))
        u.n:set_rotation(vec3(mode == "run" and 6 or 0, (u.yaw or 0) + clamp(-C.vx * 4, -25, 25), 0))
    end
    for i = #C.dead, 1, -1 do
        local d = C.dead[i]
        d.life = d.life + dt
        d.vy = d.vy - 22 * dt
        d.x, d.y, d.z = d.x + d.vx * dt, d.y + d.vy * dt, d.z + d.vz * dt
        d.rx = d.rx + d.sp * dt
        d.n:set_position(vec3(LX(d.x), d.y, d.z)); d.n:set_rotation(vec3(d.rx, d.rx * 0.5, d.rz))
        if d.how ~= "fall" and d.y < 0 and d.life < 1.0 and G.solid(G.floor_at(G.L, d.z), d.x) then
            d.y = 0; d.vy = -d.vy * 0.3; d.vx = d.vx * 0.6; d.vz = d.vz * 0.6
            if abs(d.vy) < 1 then d.life = 9 end
        end
        if d.y < -8.8 and not d.splash then d.splash = true; G.FX.spray(LX(d.x), -8.9, d.z, 0.5, 0.6); d.life = 9 end
        if d.life > 1.4 then
            if not d.splash then G.FX.puff(LX(d.x), d.y + 0.5, d.z, TEAMRGB[d.col or T[d.t].col], 0.7) end
            F_put("man_" .. (d.col or T[d.t].col) .. "0", d.n); table.remove(C.dead, i)
        end
    end
end
end
------------------------------------------------------------------ level objects: gates, red crowds, cages, drops, coins, traps
do
local function opval(s)
    local o, v = s:sub(1, 1), tonumber(s:sub(2)) or 0
    return o, v
end
local function good(s) local o = s:sub(1, 1); return o == "+" or o == "x" or o == "M" end
local function panel_tpl(s) if s:sub(1, 1) == "M" then return "c_glassp" end; return good(s) and "c_glassb" or "c_glassr" end
local function label_of(s)
    local o, v = opval(s)
    if o == "M" then return "Merge" end
    if o == "x" then return "×" .. v end
    if o == "/" then return "÷" .. v end
    return s
end
G.label_of = label_of
R.panel_tpl = panel_tpl

local function mk_gate(e)
    local twin = e.b ~= nil
    local post = e.kind == "trick" and "post_warn" or "post"
    e.posts = {}
    local xs = twin and { -W, 0, W } or { -W, W }
    e.postx = xs
    for _, x in ipairs(xs) do local p = P_get(post); place(p, LX(x), 0, e.z, 1, 1.05, 1); e.posts[#e.posts + 1] = p end
    e.panels = {}
    local sides = twin and { { -W, 0, e.a }, { 0, W, e.b } } or { { -W, W, e.a } }
    for i, s in ipairs(sides) do
        local n = P_get("c_glassb")
        n:set_mesh_ref(mesh_of(panel_tpl(s[3])))
        -- 4 cm clear of the 0.2 m posts on both sides (it used to end exactly on the post surface, a tangent
        -- contact that flickered), and the top tucked 6 cm into the cross bar instead of 1 cm under its bottom face
        n:set_position(vec3(LX((s[1] + s[2]) / 2), 2.27, e.z)); n:set_scale(vec3(s[2] - s[1] - 0.48, 2.06, 0.12))
        e.panels[i] = { n = n, x = (s[1] + s[2]) / 2, w = s[2] - s[1], v = s[3], tpl = panel_tpl(s[3]) }
    end
    if e.kind == "timed" then
        e.lamps = {}
        for i, pn in ipairs(e.panels) do local l = P_get("lamp"); place(l, LX(pn.x), 3.7, e.z, 0.7); e.lamps[i] = l end
        e.alt = { e.b, e.a }
    end
    local bar = P_get("c_white"); bar:set_position(vec3(0, 3.35, e.z)); bar:set_scale(vec3(2 * W + 0.3, 0.22, 0.22)); e.bar = bar
end
local function set_panel(p, v)
    p.v = v
    local t = panel_tpl(v)
    if t ~= p.tpl then p.tpl = t; p.n:set_mesh_ref(mesh_of(t)) end
end
R.set_panel = set_panel

local function enemy_units(e)
    e.units = {}
    local vis = min(e.n, 80)
    for i = 1, vis do
        local n = F_get("man_r0")
        local r = sqrt(i - 0.5) * 0.37; local a = i * 2.39996
        local u = { n = n, ox = cos(a) * r, oz = sin(a) * r * 0.9, ph = rand() * 4, fr = -1 }
        n:set_scale(vec3(1, 1, 1)); n:set_rotation(vec3(0, 180, 0))
        e.units[i] = u
    end
    e.rmax = sqrt(vis) * 0.37 + 0.3
end
function R.enemy_sync(e)
    local want = min(e.n, 80)
    while #e.units > want do
        local u = table.remove(e.units)
        C.dead[#C.dead + 1] = { n = u.n, t = 1, col = "r", x = e.x + u.ox, y = 0, z = e.cz + u.oz, vx = rr(-3, 3), vy = rr(3, 6), vz = rr(1, 4), rx = 0, rz = 0, sp = rr(-500, 500), life = 0.6 }
    end
end

function R.build(L, foe)
    foe = foe or 1
    R.list = {}; R.coins = {}
    for _, src in ipairs(L.ev) do
        local e = {}
        for k, v in pairs(src) do e[k] = v end
        e.done = false
        local t = e.t
        if t == "gate" then mk_gate(e)
        elseif t == "enemy" then e.n = max(4, floor(e.n * foe + 0.5)); e.cz = e.z; e.state = "wait"; e.n0 = e.n; enemy_units(e)
        elseif t == "cage" then e.node = put("cage", e.x, 0, e.z, 1.0, 0); e.hp0 = e.hp; e.caps = {}
            for i = 1, min(e.n, 9) do
                local a, r = i * 2.39996, sqrt(i) * 0.33
                local n = F_get("man_g0"); n:set_mesh_ref(mesh_of("man_gi")); place(n, LX(e.x + cos(a) * r), 0, e.z + sin(a) * r * 0.7, 1, 1, 1, 180)
                e.caps[i] = n
            end
        elseif t == "drop" then e.state = "wait"; e.y = 30
        elseif t == "ally" then e.node = F_get("man_y0"); e.node:set_mesh_ref(mesh_of("man_yc")); place(e.node, LX(e.x), 0, e.z, 2.25, 2.25, 2.25, 180)
        elseif t == "coins" then
            for i = 1, e.n do
                local x = e.wave and (e.x + sin(i * 0.8) * 2.2) or e.x
                local c = { x = x, z = e.z + (i - 1) * 1.6, n = P_get("coin"), on = true, ph = i * 0.4 }
                R.coins[#R.coins + 1] = c
            end
        elseif t == "spin" then
            e.post = put("spin_post", e.x, 0, e.z, 1, 0); e.bar = put("spin_bar", e.x, 0.6, e.z, 1, 0); e.a = 0
        elseif t == "saw" then
            box("c_dark", e.x0 - 0.6, e.x1 + 0.6, G.DECAL.slot[1], G.DECAL.slot[2], e.z - 0.12, e.z + 0.12)
            e.saw = P_get("saw"); e.hub = P_get("saw_hub")
        elseif t == "ham" then
            for _, sx in ipairs({ -W - 0.4, W + 0.4 }) do local p = put("post", sx, 0, e.z, 1.25, 0, 1.72); end
            local cb = P_get("c_metal"); cb:set_position(vec3(0, 5.6, e.z)); cb:set_scale(vec3(2 * W + 1.2, 0.35, 0.35))
            e.h1 = P_get("hammer_handle"); e.h2 = P_get("hammer_head")
        elseif t == "crush" then
            e.blk = P_get("c_redpaint"); e.y = 4.5
            for _, sx in ipairs({ e.x - e.w / 2 - 0.25, e.x + e.w / 2 + 0.25 }) do put("post", sx, 0, e.z, 1.0, 0, 2.0) end
            box("c_warn", e.x - e.w / 2, e.x + e.w / 2, G.DECAL.crush[1], G.DECAL.crush[2], e.z - 1.1, e.z + 1.1)
        elseif t == "roll" then e.rz = e.z; e.state = "wait"; e.node = P_get("roller"); e.sp = {}
            for i = 1, max(1, round(e.w)) do e.sp[i] = P_get("spikes") end
        end
        R.list[#R.list + 1] = e
    end
end

-- world labels (gate signs, crowd badges) drawn by the HUD
function R.label(x, y, z, text, col, size, bg)
    R.labels[#R.labels + 1] = { x = x, y = y, z = z, text = text, col = col, size = size or 1, bg = bg }
end
end
------------------------------------------------------------------ the run: steering, terrain, objects, interactions (fixed step)
do
local TER = {  -- speed, grip (lower = slides), bleed per second for a pawn standing in it, display name
    oil = { sp = 1.05, grip = 1.8, bleed = 0, name = "Oil" }, ice = { sp = 1.22, grip = 1.6, bleed = 0, name = "Ice" },
    mud = { sp = 0.55, grip = 10, bleed = 0, name = "Mud" }, gravel = { sp = 0.8, grip = 10, bleed = 0.035, name = "Gravel" },
    thorn = { sp = 0.85, grip = 10, bleed = 0.13, name = "Brambles" },
}
G.TER = TER
function RUN.start(L)
    G.L = L
    for _, u in ipairs(C.units) do F_put("man_" .. G.T[u.t].col .. "0", u.n) end
    for _, d in ipairs(C.dead) do F_put("man_" .. (d.col or G.T[d.t].col) .. "0", d.n) end
    C.units, C.dead = {}, {}
    G.build_level(L)
    G.boost = G.catchup(L.idx)
    R.build(L, G.boost.foe)
    local a = G.army_counts()
    C.cnt = { G.start_pawns() + a[1] + G.boost.pawns, a[2], a[3], G.breakers() }
    C.cx, C.cxt, C.cz, C.vx, C.speed, C.bdmg, C.gdmg, C.lost = 0, 0, 0, 0, 0, 0, 0, 0
    C.rmax = 1
    C.sync(false); C.formation(); C.layout(4.2)
    for _, u in ipairs(C.units) do u.ox, u.oz = u.tx, u.tz; u.born = 0 end
    RUN.stats = { coins = 0, kills = 0, perfect = 0, gates = 0, traps = 0, close = 0, lost_traps = 0, cages = 0, drops = 0, peak = C.power() }
    RUN.phase = "run"; RUN.clash = nil; RUN.t = 0; RUN.tip = nil
    G.shield_t = 0; G.shields = G.shield_charges()
    G.cam_reset = true
end

------------------------------------------------------------------ gates
local function apply(v)
    local o, n = v:sub(1, 1), tonumber(v:sub(2)) or 0
    local c = C.cnt
    local before = C.power()
    if o == "+" then c[1] = c[1] + round(n * G.gate_mult())
    elseif o == "x" then c[1] = c[1] * n
    elseif o == "-" then C.damage(n)
    elseif o == "/" then c[1] = math.ceil(c[1] / n)
    elseif o == "M" then
        if c[1] >= 2 then local k = floor(c[1] / 2); c[2] = c[2] + k; c[1] = c[1] - 2 * k
        elseif c[2] >= 2 then local k = floor(c[2] / 2); c[3] = c[3] + k; c[2] = c[2] - 2 * k end
    end
    return C.power() - before
end
local function outcome(v)  -- power after taking v (for the perfect-gate check)
    local save = { C.cnt[1], C.cnt[2], C.cnt[3], C.cnt[4] }; local bd, gd = C.bdmg, C.gdmg
    apply(v); local p = C.power()
    C.cnt = save; C.bdmg, C.gdmg = bd, gd
    return p
end
RUN.outcome = outcome
local function pass_gate(e)
    e.done = true
    local pi = 1
    if #e.panels == 2 and C.cx > 0 then pi = 2 end
    local p = e.panels[pi]
    local v = p.v
    if #e.panels == 2 then
        local other = e.panels[3 - pi].v
        if outcome(v) >= outcome(other) then RUN.stats.perfect = RUN.stats.perfect + 1 end
    end
    RUN.stats.gates = RUN.stats.gates + 1
    local d = apply(v)
    C.sync(); C.formation()
    local good = d >= 0
    local o = v:sub(1, 1)
    local col = o == "M" and { 1.4, 1.1, .3 } or (good and { .4, .8, 1.6 } or { 1.6, .35, .3 })
    G.FX.glow_trail(LX(p.x), 1.6, e.z, col)
    G.FX.flash(LX(p.x), 1.6, e.z, 3.5, col)
    G.FX.shatter(LX(p.x), 1.6, e.z, col)
    G.fx_light(vec3(LX(p.x), 2, e.z), col, 60, 0.35, 10)
    p.n:set_position(HIDE); p.gone = true
    if o == "M" then sfx("merge"); G.punch(6, 0.5); G.shake(0.25); G.popup("Merge!", { 1, .85, .3, 1 }, 1.4)
        G.FX.confetti(LX(C.cx), 2, C.cz + 2, 25)
    elseif good then sfx("gate_good"); G.punch((o == "x") and (2 + (tonumber(v:sub(2)) or 2) * 1.2) or 2.5, 0.35)
        G.popup(G.label_of(v), { .55, .85, 1, 1 }, 1.0)
        if o == "x" and (tonumber(v:sub(2)) or 0) >= 3 then G.FX.confetti(LX(C.cx), 2, C.cz + 3, 20) end
    else sfx("gate_bad"); G.shake(0.35); G.punch(-2.5, 0.3); G.popup(G.label_of(v), { 1, .45, .4, 1 }, 1.0) end
    if C.power() > RUN.stats.peak then RUN.stats.peak = C.power() end
end

------------------------------------------------------------------ unit vs trap helpers
local function near_miss(e, clear)
    if clear < (e.close or 99) then e.close = clear end
end
local function each_unit(f)
    local i = 1
    while i <= #C.units do
        local u = C.units[i]
        if not f(u, C.cx + u.ox, C.cz + u.oz) then i = i + 1 end
    end
end
-- each trap can only take a bite out of the crowd (max ~35%), never wipe it in one sweep
local function trap_hit(e, u, vx, vy, vz)
    -- the bite is measured in crowd POWER (one visible pawn can stand for several members)
    if not e.cap then e.cap = max(2, floor(C.power() * 0.16 + 0.5)) end
    if (e.lost or 0) >= e.cap then
        if u.inv <= 0 then u.inv = 0.3; G.FX.sparks(LX(C.cx + u.ox), 0.8, C.cz + u.oz, 2) end
        return false
    end
    local before, p0 = #C.units, C.power()
    C.hurt(u, "trap", vx, vy, vz)
    e.lost = (e.lost or 0) + max(1, p0 - C.power())
    e.hit = (e.hit or 0) + 1
    if #C.units < before then RUN.stats.lost_traps = RUN.stats.lost_traps + 1; return true end
    return false
end
------------------------------------------------------------------ per-step update
function RUN.step(dt)
    local L = G.L
    local st = RUN.stats
    RUN.t = RUN.t + dt
    -- steering target from keys / drag
    local dir = 0
    if anyheld("A", "Left") then dir = dir - 1 end
    if anyheld("D", "Right") then dir = dir + 1 end
    C.cxt = C.cxt + dir * 10 * dt
    if G.drag_dx then C.cxt = C.cxt + G.drag_dx; G.drag_dx = nil end
    -- floor under the crowd, terrain mix
    -- squeeze early: narrowest strip (the one under / nearest the crowd) over the next few metres
    local width = 2 * W
    -- dense samples from the rear row to ~1 s ahead (a long squeezed column must not un-squeeze while its tail is still over a pit)
    local wz = {}
    do local zz = C.cz - (C.hd or 1) - 0.4; while zz < C.cz + (C.hd or 1) * 0.5 + 9 do wz[#wz + 1] = zz; zz = zz + 1.25 end end
    for _, zq in ipairs(wz) do
        local iv = G.floor_at(L, zq)
        local bw, bd = nil, 1e9
        for _, s2 in ipairs(iv) do
            local d = (C.cx < s2[1]) and (s2[1] - C.cx) or ((C.cx > s2[2]) and (C.cx - s2[2]) or 0)
            if d < bd then bd, bw = d, s2[2] - s2[1] end
        end
        if bw and bw < width then width = bw end
    end
    local hwmax = max(0.7, min(4.2, width / 2 - 0.25))
    C.layout(hwmax)
    local hw = C.hw or 1
    C.cxt = clamp(C.cxt, -W + min(hw, W - 0.2), W - min(hw, W - 0.2))
    -- edge assist: when the floor ahead narrows (bridges, pit edges) the crowd is gently
    -- herded onto the strip it is already over, so falls come from fighting it, not from bad luck
    -- (samples the whole crowd depth: rear rows still over a pit keep the crowd on the strip)
    local sa, sb, any = -1e9, 1e9, false
    local zs = {}
    do local z0 = C.cz - (C.hd or 1) - 0.4; local zz = z0; while zz < C.cz + 6 do zs[#zs + 1] = zz; zz = zz + 1.5 end; zs[#zs + 1] = C.cz + 6 end
    for _, zz in ipairs(zs) do
        local bs, bd = nil, 1e9   -- nearest strip to the crowd centre (so a crowd beside a bridge is led onto it)
        for _, s2 in ipairs(G.floor_at(L, zz)) do
            local d = (C.cx < s2[1]) and (s2[1] - C.cx) or ((C.cx > s2[2]) and (C.cx - s2[2]) or 0)
            if d < bd then bd, bs = d, s2 end
        end
        if bs then
            if bs[2] - bs[1] < 2 * W - 0.01 then any = true end
            sa, sb = max(sa, bs[1]), min(sb, bs[2])
        end
    end
    RUN.safe = nil
    if any and sb > sa then
        local a, b = sa + hw * 0.95, sb - hw * 0.95
        RUN.safe = { a, b, (sa + sb) / 2 }
        local tgt = (a <= b) and clamp(C.cxt, a, b) or (sa + sb) / 2
        if dir == 0 then C.cxt = damp(C.cxt, tgt, 3.5, dt) else C.cxt = damp(C.cxt, tgt, 1.2, dt) end
    end
    local tcount, tsp, tgrip, nk = {}, 0, 0, 0
    for _, u in ipairs(C.units) do
        local k = G.terrain_at(L, C.cx + u.ox, C.cz + u.oz)
        local tt = k and TER[k]
        tsp = tsp + (tt and tt.sp or 1); tgrip = tgrip + (tt and tt.grip or 30); nk = nk + 1
        if k then tcount[k] = (tcount[k] or 0) + 1 end
        u.ter = k
    end
    if nk > 0 then tsp, tgrip = tsp / nk, tgrip / nk else tsp, tgrip = 1, 30 end
    RUN.ter = nil
    local best = 0
    for k, n in pairs(tcount) do if n > best then best = n; RUN.ter = k end end
    -- lateral motion: grip blends a firm follow with a slidey spring
    local want = (C.cxt - C.cx) * min(tgrip, 14)
    C.vx = damp(C.vx, want, min(tgrip, 30) * 0.9, dt)
    if RUN.ter == "oil" then C.vx = C.vx + sin(RUN.t * 1.7) * 3 * dt end
    C.cx = C.cx + C.vx * dt
    if RUN.ter == "oil" or RUN.ter == "ice" then local m = W - (C.hw or 1) * 0.55 + 0.2; C.cx = clamp(C.cx, -m, m); if abs(C.cx) >= m - 0.01 then C.vx = C.vx * 0.5 end else C.cx = clamp(C.cx, -W + 0.3, W - 0.3) end
    -- forward speed
    local base = 8.5 * G.speed_mult()
    local target = base * tsp
    if RUN.clash or RUN.block then target = RUN.block and base * 0.15 or 0 end
    C.speed = damp(C.speed, target, 5, dt)
    C.cz = C.cz + C.speed * dt
    -- units follow their slots; check the floor under each one; terrain bleed
    for i = #C.units, 1, -1 do
        local u = C.units[i]
        if u then
            local k = (u.ter == "oil" or u.ter == "ice") and 3 or 9
            u.ox = damp(u.ox, u.tx + sin(RUN.t * 3 + u.ph) * 0.04, k, dt)
            u.oz = damp(u.oz, u.tz + cos(RUN.t * 2.6 + u.ph) * 0.05, k, dt)
            local wx, wz = C.cx + u.ox, C.cz + u.oz
            if not G.solid(G.floor_at(L, wz), wx) then
                st.lost_traps = st.lost_traps + 1
                C.lose_unit(u, "fall")
            elseif u.ter and TER[u.ter].bleed > 0 and u.t ~= 3 then
                local b = TER[u.ter].bleed * (u.t == 2 and 0.3 or 1) * (1 - G.armor_chance())
                if rand() < b * dt then
                    st.lost_traps = st.lost_traps + 1
                    C.hurt(u, "trap", rr(-1, 1), 3, 0)
                    G.FX.grit(LX(wx), 0.3, wz, { .5, .3, .2 }, 4)
                end
            end
        end
    end
    C.sync()
    -- terrain feedback dust
    if RUN.ter and rand() < dt * 8 then
        local col = ({ oil = { .3, .3, .35 }, ice = { .8, .9, 1 }, mud = { .45, .3, .18 }, gravel = { .55, .52, .5 }, thorn = { .4, .45, .3 } })[RUN.ter]
        G.FX.dust(LX(C.cx + rr(-hw, hw)), 0.2, C.cz - 0.5, col, 0.5, 0.7)
    end
    -- objects
    RUN.block = nil
    local front = C.cz + (C.hd or 1)
    for _, e in ipairs(R.list) do
        if (not e.done or (e.t == "gate" and (e.sink or 0) < 1)) and e.z < C.cz + 70 and e.z > C.cz - 30 then RUN.obj(e, dt, front, hw) end
    end
    -- coins (magnet widens the pickup)
    local mag = G.magnet()
    for _, c in ipairs(R.coins) do
        if c.on and abs(c.z - C.cz) < (C.hd or 1) + 0.8 and abs(c.x - C.cx) < hw + 0.6 + mag then
            c.on = false; c.n:set_position(HIDE)
            st.coins = st.coins + 1; G.coin_sfx()
            G.FX.coin(LX(c.x), 1, c.z)
        end
    end
    if C.power() <= 0 then RUN.phase = "dead" end
end

function RUN.obj(e, dt, front, hw)
    local t = e.t
    local st = RUN.stats
    if t == "gate" then
        if e.done then   -- passed gates sink into the track so they never block the follow camera
            if (e.sink or 0) < 1 then
                e.sink = min(1, (e.sink or 0) + dt / 0.5); local dy = -4.4 * e.sink * e.sink
                for i, q in ipairs(e.posts) do q:set_position(vec3(LX(e.postx[i]), dy, e.z)) end
                for _, p in ipairs(e.panels) do if not p.gone then p.n:set_position(vec3(LX(p.x), 2.27 + dy, e.z)) end end
                if e.bar then e.bar:set_position(vec3(0, 3.35 + dy, e.z)) end
                if e.lamps then for i, l in ipairs(e.lamps) do l:set_position(vec3(LX(e.panels[i].x), 3.7 + dy, e.z)) end end
            end
            return
        end
        if e.kind == "trick" and not e.flipped and e.z - front < 13 then
            e.flipped = true; e.scramble = 0.7
            if not G.lucky_reveal() then
                local pi = (C.cx > 0) and 2 or 1
                local mine, other = e.panels[pi], e.panels[3 - pi]
                if mine and other and outcome(mine.v) > outcome(other.v) then e.swap = true end
            end
            sfx("deny")
        end
        if e.scramble then
            e.scramble = e.scramble - dt
            if e.scramble <= 0 then
                e.scramble = nil
                if e.swap then local a, b = e.panels[1].v, e.panels[2].v; R.set_panel(e.panels[1], b); R.set_panel(e.panels[2], a); G.popup("Trick Gate!", { 1, .6, .3, 1 }, 1) end
            end
        end
        if e.kind == "timed" then
            local on = floor((G.t + e.z * 0.13) / 1.5) % 2 == 0
            if on ~= e.on then
                e.on = on
                for i, p in ipairs(e.panels) do R.set_panel(p, on and ((i == 1) and e.a or e.b) or ((i == 1) and e.b or e.a)) end
                if abs(e.z - front) < 30 then sfx("click") end
            end
        end
        if front >= e.z and C.cz >= e.z - (C.hd or 1) * 0.5 then pass_gate(e) end
        for i, p in ipairs(e.panels) do
            local txt = e.scramble and ({ "+?", "×?", "-?", "÷?" })[floor(G.t * 14 + i) % 4 + 1] or G.label_of(p.v)
            local o = p.v:sub(1, 1)
            local col = o == "M" and { 1, .9, .45, 1 } or ((o == "+" or o == "x") and { 1, 1, 1, 1 } or { 1, .9, .9, 1 })
            R.label(p.x, 1.85, e.z, txt, col, 2.3)
        end
    elseif t == "enemy" then
        local dz = e.cz - front
        if e.state == "wait" and dz < 16 then e.state = "charge"; sfx("boss_roar") end
        if e.state == "charge" then e.cz = e.cz - 5 * dt; e.x = damp(e.x, C.cx, 2, dt) end
        if e.state ~= "clash" and e.cz - e.rmax <= front + 0.2 then e.state = "clash"; RUN.clash = e; G.shake(0.3); sfx("clash") end
        if e.state == "clash" then
            e.cz = max(front + e.rmax * 0.4, e.cz - 3 * dt)
            local rate = 14 + 0.35 * min(C.power(), e.n)
            e.acc = (e.acc or 0) + rate * dt
            while e.acc >= 1 and e.n > 0 and C.power() > 0 do
                e.acc = e.acc - 1; e.n = e.n - 1; st.kills = st.kills + 1
                if rand() >= G.might_chance() then C.damage(1) end
            end
            C.sync(false)
            R.enemy_sync(e)
            if rand() < dt * 14 then
                local x, z = (C.cx + e.x) / 2 + rr(-1.5, 1.5), front + rr(-0.3, 0.6)
                G.FX.puff(LX(x), 0.7, z, rand() < 0.5 and G.TEAMRGB.r or G.TEAMRGB.b, 0.8)
                G.FX.sparks(LX(x), 0.8, z, 5, nil, 5)
                G.sfx_hit()
            end
            if e.n <= 0 or C.power() <= 0 then
                e.done = true; RUN.clash = nil
                for _, u in ipairs(e.units) do F_put("man_r0", u.n) end; e.units = {}
                if C.power() > 0 then G.popup("Crushed!", { 1, .85, .3, 1 }, 1); G.punch(3, 0.3); sfx("gate_good") end
            end
        end
        for _, u in ipairs(e.units) do
            u.ph = u.ph + dt * (e.state == "wait" and 0.8 or 8)
            local fr = e.state == "wait" and "i" or tostring(floor(u.ph) % 4)
            if fr ~= u.fr then u.fr = fr; u.n:set_mesh_ref(mesh_of("man_r" .. fr)) end
            u.n:set_position(vec3(LX(e.x + u.ox), e.state == "wait" and 0 or abs(sin(u.ph * PI * 0.5)) * 0.085, e.cz + u.oz))
        end
        if not e.done then local cl = (e.state == "clash") and 1 or 0; R.label(e.x + cl * 1.3, 1.6 + e.rmax * 0.25 + 1.2 + cl * 0.6, e.cz, tostring(e.n), { 1, 1, 1, 1 }, 1.5, { .9, .2, .2, .92 }) end
    elseif t == "cage" then
        local inx = abs(C.cx - e.x) < 1.3 + hw * 0.5
        if e.hp > 0 and inx and front > e.z - 1.3 and C.cz < e.z + 1 then
            RUN.block = true
            e.hp = e.hp - (6 + 0.4 * C.power()) * dt
            if rand() < dt * 10 then G.FX.grit(LX(e.x + rr(-1, 1)), 1, e.z - 1, { .55, .38, .22 }, 3); G.sfx_hit() end
            local wob = sin(G.t * 40) * 3
            e.node:set_rotation(vec3(wob, 0, -wob))
            if e.hp <= 0 then
                e.done = true; e.node:set_position(HIDE); st.cages = st.cages + 1
                for _, n in ipairs(e.caps) do n:set_position(HIDE); F_put("man_g0", n) end
                C.cnt[1] = C.cnt[1] + e.n; C.sync(); G.shake(0.3); G.punch(4, 0.4)
                G.FX.grit(LX(e.x), 1.2, e.z, { .55, .38, .22 }, 20); G.FX.dust(LX(e.x), 0.5, e.z, { .6, .5, .4 }, 1.5, 1.5)
                G.FX.confetti(LX(e.x), 2, e.z, 20)
                sfx("slam"); sfx("gate_good"); G.popup("Freed +" .. e.n .. "!", { .6, 1, .6, 1 }, 1.2)
            end
        end
        if not e.done then
            R.label(e.x, 3.1, e.z, "+" .. e.n, { 1, 1, 1, 1 }, 1.3, { .25, .55, .3, .9 })
            if e.hp < e.hp0 then R.label(e.x, 3.9, e.z, string.rep("|", math.ceil(e.hp / e.hp0 * 10)), { 1, .9, .4, 1 }, 0.9) end
            if C.cz > e.z + 2 then e.done = true end
        end
    elseif t == "drop" then
        if e.state == "wait" and e.z - C.cz < 60 then
            e.state = "fall"; e.crate = P_get("crate"); e.chute = P_get("chute")
            e.ttl = max(1.5, (e.z - C.cz) / max(4, C.speed) - 0.8); e.y = 30; sfx("shield")
        end
        if e.state == "fall" then
            e.y = max(0, e.y - (e.y / max(e.ttl, 0.1)) * dt); e.ttl = max(0.05, e.ttl - dt)
            e.crate:set_position(vec3(LX(e.x), e.y, e.z)); e.crate:set_rotation(vec3(0, G.t * 30, sin(G.t * 2) * 5))
            e.chute:set_position(vec3(LX(e.x), e.y, e.z)); e.chute:set_rotation(vec3(sin(G.t * 1.6) * 6, G.t * 30, 0))
            if e.y <= 0.01 and not e.landed then e.landed = true; e.chute:set_position(HIDE); G.FX.dust(LX(e.x), 0.3, e.z, { .7, .65, .55 }, 1, 1.2); sfx("thud") end
            R.label(e.x, e.y + 2.2, e.z, "+" .. e.n, { 1, 1, 1, 1 }, 1.3, { .2, .5, .9, .9 })
            if C.cz > e.z - 0.5 then
                e.done = true
                if abs(C.cx - e.x) < hw + 1.0 + G.magnet() * 0.5 then
                    C.cnt[1] = C.cnt[1] + e.n; C.sync(); st.drops = st.drops + 1
                    G.FX.grit(LX(e.x), 1, e.z, { .72, .52, .3 }, 12); G.FX.confetti(LX(e.x), 1.5, e.z, 15)
                    sfx("gate_good"); G.punch(3, 0.3); G.popup("Air Drop +" .. e.n, { .55, .85, 1, 1 }, 1.1)
                    e.crate:set_position(HIDE); e.chute:set_position(HIDE)
                end
            end
        end
    elseif t == "ally" then
        e.node:set_mesh_ref(mesh_of(floor(G.t * 3) % 2 == 0 and "man_yc" or "man_yi"))
        R.label(e.x, 4.0, e.z, "Giant Ally", { 1, .95, .6, 1 }, 1.0, { .75, .5, .1, .9 })
        if C.cz > e.z - 0.5 then
            e.done = true
            if abs(C.cx - e.x) < hw + 1.4 + G.magnet() * 0.5 then
                e.node:set_position(HIDE); F_put("man_y0", e.node)
                C.cnt[3] = C.cnt[3] + 1; C.sync(); G.punch(7, 0.6); G.shake(0.3)
                G.FX.confetti(LX(e.x), 3, e.z, 30); sfx("trophy"); G.popup("A Giant Joins!", { 1, .85, .3, 1 }, 1.4)
            end
        end
    elseif t == "spin" then
        e.a = e.a + e.w * dt
        e.bar:set_rotation(vec3(0, math.deg(e.a), 0))
        local ca, sa = cos(e.a), sin(e.a)
        each_unit(function(u, x, z)
            local dx, dz = LX(x) - LX(e.x), z - e.z
            local along = dx * ca - dz * sa
            local perp = abs(dx * sa + dz * ca)
            if abs(along) < 4.4 then
                local clear = perp - (0.25 + G.T[u.t].rad)
                if clear < 0 then return trap_hit(e, u, -sa * 8 * (along > 0 and 1 or -1), 7, ca * 4) end
                near_miss(e, clear)
            end
        end)
        RUN.trap_done(e)
    elseif t == "saw" then
        local mid, amp = (e.x0 + e.x1) / 2, (e.x1 - e.x0) / 2
        e.sx = mid + amp * sin(G.t * e.w)
        e.saw:set_position(vec3(LX(e.sx), 0.85, e.z)); e.saw:set_rotation(vec3(0, 0, G.t * 900)); e.saw:set_scale(vec3(1, 1, 1))
        e.hub:set_position(vec3(LX(e.sx), 0.85, e.z)); e.hub:set_rotation(vec3(0, 0, 0))
        if rand() < dt * 6 then G.FX.sparks(LX(e.sx), 0.05, e.z, 3, { 0, 2, -3 }, 3) end
        each_unit(function(u, x, z)
            if abs(z - e.z) < 0.25 + G.T[u.t].rad then
                local clear = abs(x - e.sx) - (1.05 + G.T[u.t].rad * 0.6)
                if clear < 0 then sfx("saw"); return trap_hit(e, u, (x > e.sx and 1 or -1) * -6, 6, 2) end
                near_miss(e, clear)
            end
        end)
        RUN.trap_done(e)
    elseif t == "ham" then
        local phi = 1.15 * sin(G.t * 2 * PI / 2.6 + e.ph * 2 * PI)
        e.h1:set_position(vec3(LX(e.x), 5.5, e.z)); e.h1:set_rotation(vec3(0, 0, math.deg(phi)))
        e.h2:set_position(vec3(LX(e.x), 5.5, e.z)); e.h2:set_rotation(vec3(0, 0, math.deg(phi)))
        local hx, hy = e.x - 4.3 * sin(phi), 5.5 - 4.3 * cos(phi)
        if hy < 2.6 then
            each_unit(function(u, x, z)
                if abs(z - e.z) < 1.1 + G.T[u.t].rad then
                    local clear = abs(x - hx) - (0.75 + G.T[u.t].rad)
                    if clear < 0 and hy < 1.0 + G.T[u.t].s then return trap_hit(e, u, (x > hx and -1 or 1) * 9, 6, 1) end
                    near_miss(e, clear)
                end
            end)
        end
        RUN.trap_done(e)
    elseif t == "crush" then
        local cyc = (G.t / 2.3 + e.ph) % 1
        local y
        if cyc < 0.55 then y = 4.6 elseif cyc < 0.62 then y = lerp(4.6, 0.75, (cyc - 0.55) / 0.07) elseif cyc < 0.78 then y = 0.75 else y = lerp(0.75, 4.6, (cyc - 0.78) / 0.22) end
        if y <= 0.76 and (e.y or 5) > 0.76 then
            if abs(e.z - C.cz) < 25 then sfx("slam"); G.shake(0.2) end
            G.FX.dust(LX(e.x), 0.2, e.z, { .7, .65, .6 }, 1.2, 1.3)
        end
        e.y = y
        e.blk:set_position(vec3(LX(e.x), y, e.z)); e.blk:set_scale(vec3(e.w, 1.5, 2.1))
        if y < 1.5 then
            each_unit(function(u, x, z)
                if abs(z - e.z) < 1.05 + G.T[u.t].rad * 0.5 and abs(x - e.x) < e.w / 2 + G.T[u.t].rad * 0.5 then
                    if y - 0.75 < 1.15 * G.T[u.t].s then return trap_hit(e, u, rr(-2, 2), 2, 0) end
                end
            end)
        else
            each_unit(function(u, x, z) if abs(z - e.z) < 1.2 and abs(x - e.x) < e.w / 2 + 0.3 then near_miss(e, 0.3) end end)
        end
        RUN.trap_done(e)
    elseif t == "roll" then
        if e.state == "wait" and e.z - C.cz < 34 then e.state = "go"; sfx("thud") end
        if e.state == "go" then e.rz = e.rz - 7 * dt end
        e.node:set_position(vec3(LX(e.x), 0.62, e.rz)); e.node:set_scale(vec3(e.w, 1, 1)); e.node:set_rotation(vec3(-G.t * 400, 0, 0))
        local k = #e.sp
        for i, s in ipairs(e.sp) do
            s:set_position(vec3(LX(e.x - e.w / 2 + (i - 0.5) * e.w / k), 0.62, e.rz)); s:set_rotation(vec3(-G.t * 400 + i * 22, 0, 0))
        end
        each_unit(function(u, x, z)
            if abs(z - e.rz) < 0.9 + G.T[u.t].rad then
                local clear = abs(x - e.x) - (e.w / 2 + G.T[u.t].rad * 0.5)
                if clear < 0 then return trap_hit(e, u, 0, 6, -6) end
                near_miss(e, clear)
            end
        end)
        if e.rz < C.cz - 14 then e.done = true; e.node:set_position(HIDE); for _, s in ipairs(e.sp) do s:set_position(HIDE) end; RUN.trap_done(e, true) end
    elseif t == "pit" or t == "bridge" then
        if C.cz > e.z1 + 1 then e.done = true; RUN.trap_done(e, true) end
    elseif t == "tip" then
        if C.cz > e.z - 2 then e.done = true; G.tip(e.text) end
    elseif t == "ter" then
        if not e.told and C.cz > e.z0 - 2 then e.told = true end
        if C.cz > e.z1 then e.done = true end
    end
end
-- a trap counts as cleared once the crowd is past it; near misses pay a small bonus
function RUN.trap_done(e, force)
    local past = force or (C.cz - (C.hd or 1) > e.z + 2.5)
    if not past or e.scored then return end
    e.scored = true
    local st = RUN.stats
    if (e.hit or 0) == 0 then
        st.traps = st.traps + 1
        if (e.close or 99) < 0.45 then st.close = st.close + 1; G.popup("Close Call! +5", { .7, 1, .8, 1 }, 0.9) end
    end
    e.done = true
end
end
------------------------------------------------------------------ finales: multiplier staircase and the boss king at the castle
do
local FIN = {}
G.FIN = FIN
local STEP_SFX = 0
-- stairs ----------------------------------------------------------------------------------------
-- The crowd keeps running straight from the track onto the staircase as a narrow column: there is no
-- separate "approach" and "climb" mode any more (the old code snapped C.cz back by half the column depth
-- when it reached the first riser, then fell back into the approach branch the next frame -> the crowd
-- jittered at the bottom step for a second or two). Every unit's feet follow the step under it, so the
-- column turns into a pyramid going up. When the front passes a step, that step's cost is paid by the
-- frontmost units, who peel off and stand on it.
-- Merged reach: a unit that is paid out walks up as many steps as base pawns went into it
-- (FIN.PE: Brute = 2 pawns -> 1 step further, Giant = 2 Brutes = 4 pawns -> 3 steps further).
-- The payout (multiplier, stars, gems, chest) follows the highest step anyone actually stands on.
FIN.PE = { 1, 2, 4, 1 }
local POSE = { "0", "1", "2", "3" }
local function ground(z)
    local S = FIN.s
    if z < S.z0 then return 0 end
    return min(S.n, floor((z - S.z0) / S.d) + 1) * S.h
end
-- smooth version for the camera and the badge
function FIN.ramp(z)
    local S = FIN.s
    return clamp((z - S.z0) / S.d + 0.5, 0, S.n) * S.h
end
function FIN.stairs_start(L)
    local S = G.stairs
    FIN.s = { k = 0, top = 0, stood = {}, walk = {}, slots = {}, done = false, t = 0, cost = L.stair, p0 = C.power(),
        z0 = S.z0, d = S.d, h = S.h, n = S.n, v = max(C.speed, 2.6 * S.d), front = C.cz }
    RUN.phase = "stairs"; sfx("boss")
    C.cxt = 0; C.cy = 0
end
local function step_xyz(i, x) local S = FIN.s; return x, i * S.h, S.z0 + (i - 0.5) * S.d end
local function slot(i)
    local S = FIN.s
    local n = (S.slots[i] or 0) + 1; S.slots[i] = n
    local x = ((n - 1) % 9 - 4) * 0.9 + rr(-0.15, 0.15)
    local _, y, z = step_xyz(i, x)
    return x, y, z + clamp(-0.6 + floor((n - 1) / 9) * 0.6, -0.7, 0.7) + rr(-0.15, 0.15)
end
-- a unit leaves the column and walks to its step
local function walker(n, t, x, y, z, target, kind)
    local S = FIN.s
    local tx, _, tz = slot(target)
    S.walk[#S.walk + 1] = { n = n, t = t, col = G.T[t].col, kind = kind or ("man_" .. G.T[t].col .. "0"), x = x, y = y, z = z,
        tx = tx, tz = tz, step = target, bonus = target - S.k, ph = rand() * 4 }
end
local function pay(i)
    local S = FIN.s
    S.k = i
    -- frontmost units pay first: C.sync removes the LAST unit of a tier in C.units
    local T = G.T
    table.sort(C.units, function(a, b) local pa, pb = T[a.t].area, T[b.t].area; if pa ~= pb then return pa > pb end; return a.oz < b.oz end)
    local over = C.cnt[1] > T[1].cap
    C.damage(S.cost)
    local placed = 0
    C.sync(false, function(u)
        placed = placed + 1
        walker(u.n, u.t, C.cx + u.ox, u.y, C.cz + u.oz, min(S.n, i + FIN.PE[u.t] - 1))
    end)
    if placed == 0 and over then
        -- crowd above the visible pawn cap: the real pawns paid, show two of them stepping off
        for j = 1, 2 do
            local n = F_get("man_b0"); n:set_scale(vec3(1, 1, 1))
            walker(n, 1, rr(-1.2, 1.2), ground(S.front), S.front - rr(0, 1), i, "man_b0")
        end
    end
    sfx("step" .. min(9, floor((i - 1) / 2)))
    G.punch(1.2, 0.15)
    local _, y, z = step_xyz(i, 0)
    G.FX.ring(0, y + 0.05, z, 4, { .6, .6, .6 }, true)
    if i % 5 == 0 then
        G.FX.confetti(0, y + 1, z, 30); sfx("trophy"); G.popup("x" .. string.format("%.1f", 1 + 0.2 * i) .. "!", { 1, .85, .3, 1 }, 1)
        G.shake(0.15)
    end
end
-- a merged unit reached a step above everything paid so far
local function bonus_step(w)
    local S = FIN.s
    local best = max(S.k, S.top)
    if w.step > best then
        local _, y, z = step_xyz(w.step, 0)
        sfx("step" .. min(9, floor((w.step - 1) / 2))); G.punch(1.4, 0.18)
        G.FX.ring(0, y + 0.05, z, 4.5, { 1.2, 1, .4 }, true)
        local up = w.step - best
        G.popup_at((w.t == 3 and "Giant" or "Brute") .. " +" .. up .. (up > 1 and " Steps" or " Step"), w.x, y + 3.2, z, { 1, .85, .3, 1 }, 1.2)
        if w.step % 5 == 0 or (S.k % 5 ~= 0 and floor(w.step / 5) > floor(best / 5)) then
            G.FX.confetti(0, y + 1, z, 30); sfx("trophy")
        end
    end
    S.top = max(S.top, w.step)
end
function FIN.reach() local S = FIN.s; return S and max(S.k, S.top) or 0 end
function FIN.stairs_step(dt)
    local S = FIN.s
    S.t = S.t + dt
    -- the column: steer to the middle and keep walking at climbing pace (never snapped)
    C.cx = damp(C.cx, 0, 4, dt)
    local top_z = S.z0 + S.n * S.d + 4.5
    S.v = damp(S.v, S.done and 0 or 2.6 * S.d, 2.5, dt)
    local fz = -1e9
    for _, u in ipairs(C.units) do fz = max(fz, u.oz) end
    if fz < -1e8 then fz = 0 end
    C.cz = min(C.cz + S.v * dt, top_z - fz); C.speed = S.v
    S.front = C.cz + fz
    for _, u in ipairs(C.units) do u.y = damp(u.y, ground(C.cz + u.oz + 0.3), 16, dt) end
    if not S.done then
        while S.k < S.n and C.power() > 0 and S.front >= S.z0 + (S.k + 0.5) * S.d do pay(S.k + 1) end
        if C.power() <= 0 or S.k >= S.n then S.done = true; S.t = 0 end
    end
    -- walkers: run to their step, then stand and cheer
    for i = #S.walk, 1, -1 do
        local w = S.walk[i]
        local dx, dz = w.tx - w.x, w.tz - w.z
        local dl = sqrt(dx * dx + dz * dz)
        local sp = 6.5 * dt
        if dl <= sp then
            w.x, w.z = w.tx, w.tz; w.y = w.step * S.h
            w.n:set_position(vec3(LX(w.x), w.y, w.z)); w.n:set_rotation(vec3(0, 180, 0))
            w.n:set_mesh_ref(mesh_of("man_" .. w.col .. "c"))
            S.stood[#S.stood + 1] = { n = w.n, kind = w.kind, col = w.col, ph = rand() * 6, y = w.y }
            table.remove(S.walk, i)
            if w.t == 2 or w.t == 3 then bonus_step(w) else S.top = max(S.top, w.step) end
        else
            w.x, w.z = w.x + dx / dl * sp, w.z + dz / dl * sp
            w.y = damp(w.y, ground(w.z + 0.3 * (dz >= 0 and 1 or -1)), 16, dt)
            w.ph = w.ph + dt * 8 / G.T[w.t].s
            w.n:set_mesh_ref(mesh_of("man_" .. w.col .. POSE[floor(w.ph) % 4 + 1]))
            w.n:set_position(vec3(LX(w.x), w.y + abs(sin(w.ph * PI * 0.5)) * 0.08, w.z))
            w.n:set_rotation(vec3(6, math.deg(math.atan2(dx, dz)), 0))
        end
    end
    if S.done then
        if #S.walk > 0 then S.t = 0 end   -- the payout waits for the last climber
        if S.t > 0.4 and not S.paid then
            S.paid = true
            local k = FIN.reach()
            if k >= S.n then
                G.FX.boom(0, S.n * S.h + 1, S.z0 + S.n * S.d + 3, 1.3); G.FX.confetti(0, S.n * S.h + 3, S.z0 + S.n * S.d + 3, 60, 1.6)
                sfx("win"); G.popup("Treasure Chest!", { 1, .85, .3, 1 }, 1.5)
            end
            FIN.result = { kind = "stairs", k = k, paid = S.k, bonus = k - S.k, mult = 1 + 0.2 * k, stars = (k >= 15) and 3 or ((k >= 8) and 2 or ((k >= 1) and 1 or 0)),
                gems = (k >= 20) and 2 or ((k >= 17) and 1 or 0), left = S.p0 }
        end
        if S.paid and S.t > 1.8 then RUN.phase = "finished" end
    end
    for _, s in ipairs(S.stood) do s.ph = s.ph + dt * 4; s.n:set_mesh_ref(mesh_of("man_" .. s.col .. (floor(s.ph) % 2 == 0 and "c" or "i"))) end
end
-- where the camera and the crowd badge look during the climb
function FIN.focus()
    local S = FIN.s
    local z = S.front - 3
    if #C.units == 0 then
        local best = S.z0 + (max(FIN.reach(), 1) - 0.5) * S.d
        for _, w in ipairs(S.walk) do best = max(best, w.z) end
        z = best
    end
    return z, FIN.ramp(z)
end
function FIN.cleanup()
    if FIN.s then
        for _, s in ipairs(FIN.s.stood) do F_put(s.kind, s.n) end; FIN.s.stood = {}
        for _, w in ipairs(FIN.s.walk) do F_put(w.kind, w.n) end; FIN.s.walk = {}
    end
    if FIN.b then for _, c in ipairs(FIN.b.run) do F_put(c.kind, c.n) end; FIN.b.run = {} end
    FIN.s, FIN.b, FIN.result = nil, nil, nil
end

-- boss ------------------------------------------------------------------------------------------
function FIN.boss_build(L)
    local a = L.len + 3
    local hp = max(30, floor(L.boss * ((G.boost and G.boost.foe) or 1) + 0.5))
    local B = { z = a + 48, hp = hp, hp0 = hp, run = {}, t = 0, slam = 2.0, club = 0, acc = 0, state = "wait", fall = 0 }
    B.king = P_get("king"); B.crown = P_get("crown"); B.clubn = P_get("club")
    FIN.b = B
    FIN.boss_pose(0)
end
local KS = 4.6
function FIN.boss_pose(dt)
    local B = FIN.b
    local fall = B.fall
    local tilt = fall * 88
    local by = 0
    B.king:set_position(vec3(0, by, B.z)); B.king:set_scale(vec3(KS, KS, KS)); B.king:set_rotation(vec3(-tilt, 180, 0))
    -- crown rides on the head (rotate the offset with the topple)
    local hy, hz = 1.17 * KS, 0
    local th = math.rad(tilt)
    local cy, cz = hy * cos(th), B.z + hy * sin(th)
    B.crown:set_position(vec3(0, cy, cz)); B.crown:set_scale(vec3(KS * 1.1, KS * 1.1, KS * 1.1)); B.crown:set_rotation(vec3(-tilt, 0, 0))
    -- club in the right hand: raised behind, slams forward (toward -z, the crowd)
    local hx, hy2 = -0.2 * KS, 0.47 * KS
    local cyy, czz = hy2 * cos(th), B.z + hy2 * sin(th)
    B.clubn:set_position(vec3(hx, cyy, czz)); B.clubn:set_scale(vec3(KS * 1.5, KS * 1.5, KS * 1.5))
    B.clubn:set_rotation(vec3(-B.club - tilt, 0, 0))
end
function FIN.boss_step(dt)
    local B = FIN.b
    B.t = B.t + dt
    local front = C.cz + (C.hd or 1)
    if B.state == "wait" then
        C.cz = C.cz + 8 * dt; C.speed = 8; C.cx = damp(C.cx, 0, 3, dt)
        if front > B.z - 7 then B.state = "fight"; sfx("boss_roar"); G.shake(0.4); G.punch(5, 0.5); B.slam = 1.2 end
    elseif B.state == "fight" then
        C.speed = 0
        -- units charge the king one by one
        local rate = 10 + 0.12 * C.power()
        B.acc = B.acc + rate * dt
        while B.acc >= 1 and #C.units > 0 do
            B.acc = B.acc - 1
            -- weakest first so giants stay in the blob (they smash last and hardest)
            local pick
            for i = #C.units, 1, -1 do local u = C.units[i]; if not pick or G.T[u.t].pow < G.T[pick.t].pow then pick = u end end
            if not pick then break end
            local share = (pick.t == 1) and max(1, round(C.cnt[1] / max(1, C.vis1 or 1))) or 1
            for i, v in ipairs(C.units) do if v == pick then table.remove(C.units, i); break end end
            C.cnt[pick.t] = max(0, C.cnt[pick.t] - share); C.dirty = true
            local dmg = G.T[pick.t].pow * share * ((pick.t == 4) and (4 + G.breaker_level()) or 1)
            B.run[#B.run + 1] = { n = pick.n, kind = "man_" .. G.T[pick.t].col .. "0", col = G.T[pick.t].col, t = pick.t, x = C.cx + pick.ox, z = C.cz + pick.oz, dmg = dmg, ph = 0, tx = rr(-1.4, 1.4) }
        end
        C.sync(false)
        -- slam
        B.slam = B.slam - dt
        if B.slam < 0.45 then B.club = damp(B.club, -40, 6, dt) end
        if B.slam <= 0 then
            B.slam = 2.4; B.club = 95
            sfx("slam"); G.shake(0.55); G.punch(-3, 0.3)
            local sz = B.z - 5.5
            G.FX.dust(0, 0.3, sz, { .7, .65, .6 }, 2, 2.2); G.FX.ring(0, 0.1, sz, 7, { .8, .7, .6 }, true); G.FX.grit(0, 0.5, sz, { .6, .55, .5 }, 18)
            local i, cap = 1, max(2, floor(#C.units * 0.12 + 0.5))   -- a slam bites, never wipes
            while i <= #C.units and cap > 0 do
                local u = C.units[i]
                local dz, dx = C.cz + u.oz - sz, C.cx + u.ox
                if dx * dx + dz * dz < 3.2 * 3.2 and not (G.shield_t and G.shield_t > 0) then C.lose_unit(u, "trap", dx * 3, 8, -6); cap = cap - 1 else i = i + 1 end
            end
        else B.club = damp(B.club, (B.slam < 0.45) and -40 or 0, 3, dt) end
        if C.power() <= 0 and #B.run == 0 then RUN.phase = "dead" end
    elseif B.state == "fall" then
        B.fall = min(1, B.fall + dt * 1.2)
        if B.fall >= 1 and not B.landed then
            B.landed = true; sfx("slam"); G.shake(0.8); G.FX.dust(0, 0.3, B.z + 4, { .7, .65, .6 }, 3, 3); G.FX.boom(0, 1, B.z + 4, 1.4)
            G.FX.confetti(0, 4, B.z - 2, 80, 1.8); sfx("win")
            if G.castle_gate then G.castle_gate:set_position(HIDE) end
            local h = C.power()
            FIN.result = { kind = "boss", k = 0, mult = 2 + min(3, h / max(1, B.hp0) * 4), stars = (h > B.hp0 * 0.25) and 3 or ((h > 8) and 2 or 1), gems = 3, left = h }
        end
        if B.landed then
            B.post = (B.post or 0) + dt
            C.cz = C.cz + 4 * dt * min(1, B.post); C.speed = 4 * min(1, B.post)
            if B.post > 2.2 then RUN.phase = "finished" end
        end
    end
    -- chargers sprint, hop, and smash into the king
    for i = #B.run, 1, -1 do
        local c = B.run[i]
        c.ph = c.ph + dt
        c.z = c.z + 11 * dt; c.x = damp(c.x, c.tx, 3, dt)
        local y = abs(sin(c.ph * 9)) * 0.25
        c.n:set_position(vec3(LX(c.x), y, c.z)); c.n:set_mesh_ref(mesh_of("man_" .. c.col .. floor(c.ph * 9) % 4))
        if c.z > B.z - 1.6 then
            F_put(c.kind, c.n); table.remove(B.run, i)
            if B.state == "fight" then
                B.hp = B.hp - c.dmg
                G.FX.sparks(LX(c.x), 1.5 + rand() * 2, B.z - 1.5, 6, { 0, 2, -3 }, 5)
                if c.t == 4 or rand() < 0.3 then G.FX.puff(LX(c.x), 2, B.z - 1.5, G.TEAMRGB[c.col], 0.9); G.sfx_hit() end
                if c.t >= 2 then G.shake(0.12) end
                B.hit = 0.12
                if B.hp <= 0 then B.hp = 0; B.state = "fall"; G.punch(8, 0.7); sfx("boss"); G.popup("King Down!", { 1, .85, .3, 1 }, 1.6) end
            end
        end
    end
    if B.hit then B.hit = B.hit - dt; if B.hit <= 0 then B.hit = nil end end
    FIN.boss_pose(dt)
end
end
------------------------------------------------------------------ meta: save, coins/gems, upgrades, army board, treasury
do
local M = {}
G.M = M
local SAVE = "Save/crowdmaster.sav"
local function fresh()
    return { coins = 0, gems = 0, best = {}, unlocked = 1, up = {}, gem = {}, board = {}, recruits = 0, play = 0, bank = 0, last = 1, seen_tips = {}, fails = {} }
end
M.D = fresh()
function M.load()
    local ok, s = pcall(fs.read, SAVE)
    local d = ok and deser(s) or nil
    M.D = fresh()
    if d then for k, v in pairs(d) do M.D[k] = v end end
    for i = 1, 15 do M.D.board[i] = M.D.board[i] or 0 end
end
function M.save() pcall(fs.write, SAVE, ser(M.D)) end
function M.reset() M.D = fresh(); for i = 1, 15 do M.D.board[i] = 0 end; M.save() end

-- coin upgrades: id, name, blurb, base cost, max level
M.UP = {
    { id = "start", name = "Starting Crowd", desc = "+3 Runners At The Start", cost = 60, max = 10 },
    { id = "gate", name = "Gate Power", desc = "+10% On Every Plus Gate", cost = 80, max = 10 },
    { id = "armor", name = "Trap Armor", desc = "7% Chance To Shrug Off A Hit", cost = 90, max = 8 },
    { id = "speed", name = "Run Speed", desc = "+4% Running Speed", cost = 70, max = 6 },
    { id = "might", name = "Clash Might", desc = "6% Chance To Win A Duel Free", cost = 100, max = 8 },
    { id = "bank", name = "Treasury", desc = "+4 Coins Per Minute Played", cost = 120, max = 10 },
}
-- gem upgrades
M.GEM = {
    { id = "shield", name = "Shield Bubble", desc = "Space: 3s Of Immunity (Charges)", cost = 3, max = 3 },
    { id = "magnet", name = "Coin Magnet", desc = "Pull Coins And Drops From Afar", cost = 2, max = 4 },
    { id = "breaker", name = "Boss Breakers", desc = "Orange Units That Wreck Bosses", cost = 4, max = 5 },
    { id = "lucky", name = "Lucky Eye", desc = "See Through Trick Gates", cost = 3, max = 1 },
}
function M.lvl(id) return M.D.up[id] or 0 end
function M.glvl(id) return M.D.gem[id] or 0 end
function M.cost(u) return floor(u.cost * 1.55 ^ M.lvl(u.id) + 0.5) end
function M.gcost(u) return u.cost + M.glvl(u.id) * 2 end
function M.buy(u)
    if M.lvl(u.id) >= u.max then return false end
    local c = M.cost(u); if M.D.coins < c then return false end
    M.D.coins = M.D.coins - c; M.D.up[u.id] = M.lvl(u.id) + 1; M.save(); return true
end
function M.gbuy(u)
    if M.glvl(u.id) >= u.max then return false end
    local c = M.gcost(u); if M.D.gems < c then return false end
    M.D.gems = M.D.gems - c; M.D.gem[u.id] = M.glvl(u.id) + 1; M.save(); return true
end

-- effects consumed by the run
G.start_pawns = function() return 10 + 3 * M.lvl("start") end
G.gate_mult = function() return 1 + 0.1 * M.lvl("gate") end
G.armor_chance = function() return 0.07 * M.lvl("armor") end
G.speed_mult = function() return 1 + 0.04 * M.lvl("speed") end
G.might_chance = function() return 0.06 * M.lvl("might") end
G.magnet = function() return 1.2 * M.glvl("magnet") end
G.lucky_reveal = function() return M.glvl("lucky") > 0 end
G.shield_charges = function() return M.glvl("shield") end
G.breakers = function() return 2 * M.glvl("breaker") end
G.breaker_level = function() return M.glvl("breaker") end

-- underdog boost (catch-up): a player who reaches a level with fewer upgrades than the curve expects
-- (skipped the shop, or jumped ahead via Levels) gets smaller red crowds / boss HP and a few extra runners.
-- expected: ~1.5 coin-upgrade levels per cleared level; the army board counts too (1 level per board unit power 2)
function G.catchup(idx)
    local lv = 0
    for _, u in ipairs(M.UP) do if u.id ~= "bank" then lv = lv + M.lvl(u.id) end end
    local a = G.army_counts(); lv = lv + (a[1] * 0.5 + a[2] * 1.5 + a[3] * 4) / 2
    local deficit = max(0, (idx - 1) * 1.5 - lv)
    -- retry boost: every failed attempt at this level (since its last clear) adds runners and weakens foes a little
    local tries = min(4, (M.D.fails and M.D.fails[idx]) or 0)
    return { foe = max(0.68, 1 - min(0.22, 0.02 * deficit) - 0.04 * tries), pawns = min(12, floor(deficit)) + 3 * tries,
        deficit = deficit, tries = tries }
end
-- army board: 15 slots holding tier 0 (empty) / 1 pawn / 2 brute / 3 giant. merging two equal tiers makes the next tier
function M.recruit_cost() return floor(25 * 1.12 ^ (M.D.recruits or 0) + 0.5) end
function M.recruit()
    local c = M.recruit_cost(); if M.D.coins < c then return false, "Not Enough Coins" end
    for i = 1, 15 do if M.D.board[i] == 0 then
        M.D.board[i] = 1; M.D.coins = M.D.coins - c; M.D.recruits = (M.D.recruits or 0) + 1; M.save(); return true, i
    end end
    return false, "Board Full - Merge Units"
end
function M.merge(a, b)
    local B = M.D.board
    if a == b or B[a] == 0 then return false end
    if B[b] == 0 then B[b], B[a] = B[a], 0; M.save(); return "move" end
    if B[a] == B[b] and B[a] < 3 then B[b] = B[a] + 1; B[a] = 0; M.save(); return "merge" end
    B[a], B[b] = B[b], B[a]; M.save(); return "swap"
end
function M.auto_merge()  -- click helper: merge the first pair of equal units
    local B = M.D.board
    for t = 1, 2 do
        local first
        for i = 1, 15 do if B[i] == t then if first then return M.merge(i, first), first else first = i end end end
    end
    return false
end
-- each board pawn = 2 runners at the start, brute = 1 brute, giant = 1 giant
G.army_counts = function()
    local c = { 0, 0, 0 }
    for i = 1, 15 do local t = M.D.board[i]; if t == 1 then c[1] = c[1] + 2 elseif t == 2 then c[2] = c[2] + 1 elseif t == 3 then c[3] = c[3] + 1 end end
    return c
end

-- treasury: no wall clock in Lua, so it fills per in-game minute (menus included) and is collected in camp
function M.tick(dt)
    M.D.play = (M.D.play or 0) + dt
    local rate = 4 * M.lvl("bank") / 60
    M.D.bank = min((M.D.bank or 0) + rate * dt, 60 + 120 * M.lvl("bank"))
end
function M.collect() local n = floor(M.D.bank or 0); M.D.bank = (M.D.bank or 0) - n; M.D.coins = M.D.coins + n; M.save(); return n end

-- end of a run: tally the rewards
function M.tally(L, idx, won, res, st)
    local r = { lines = {} }
    local function add(name, v) if v ~= 0 then r.lines[#r.lines + 1] = { name, v } end end
    local coins = st.coins
    add("Coins Picked Up", st.coins)
    if won then
        local left = res.left or 0
        local fin = floor(left * res.mult * 0.5 + 0.5)
        add(res.kind == "boss" and "Boss Bounty" or ("Finish  x" .. string.format("%.1f", res.mult)), fin)
        add("Perfect Gates", st.perfect * 10)
        add("Traps Cleared", st.traps * 5)
        add("Close Calls", st.close * 5)
        add("Captives Freed", st.cages * 15)
        local best = M.D.best[idx]
        if not best then add("First Clear", 50) end
        coins = coins + fin + st.perfect * 10 + st.traps * 5 + st.close * 5 + st.cages * 15 + (best and 0 or 50)
        if res.kind == "boss" then add("Boss Kill", 100); coins = coins + 100 end
    else
        add("Enemies Beaten", floor(st.kills * 0.5))
        coins = coins + floor(st.kills * 0.5)
    end
    r.coins = coins
    r.gems = won and (res.gems or 0) or 0
    if won and st.lost_traps == 0 and st.gates > 0 and st.perfect == st.gates then r.gems = r.gems + 1; r.perfect_run = true end
    r.stars = won and res.stars or 0
    r.score = won and floor((res.left or 0) * res.mult * 10 + st.perfect * 50 + st.traps * 25) or 0
    M.D.coins = M.D.coins + r.coins
    M.D.gems = M.D.gems + r.gems
    M.D.fails = M.D.fails or {}
    if won then M.D.fails[idx] = nil else M.D.fails[idx] = min(4, (M.D.fails[idx] or 0) + 1) end
    if won then
        local b = M.D.best[idx] or { score = 0, stars = 0 }
        r.new_best = r.score > b.score
        M.D.best[idx] = { score = max(b.score, r.score), stars = max(b.stars, r.stars) }
        M.D.unlocked = max(M.D.unlocked, min(#G.LEVELS, idx + 1))
    end
    M.save()
    return r
end
end
------------------------------------------------------------------ UI kit: runtime_ui quads, one mouse backdrop, keyboard focus
local UI = { name = "cm" }
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
-- measured on this engine's "text" quads: a glyph is ~7 px wide per font_scale unit, and a line wraps once text + ~10 px per side passes the quad width
local function text_w(label, sc) return #label * 7.0 * sc end
UI.text_w = text_w
-- the largest font size (in UI fs units) that keeps label on one line inside width w
local function fit_fs(label, fs, w)
    if label == "" or label:find("\n") then return fs end
    local m = (w - 6 * US) / ((#label * 7.2 + 24) * US)
    return min(fs, m)
end
UI.fit_fs = fit_fs
function UI.text(id, label, x, y, w, h, fs, col, align, z, shadow)
    fs = fit_fs(label, fs, w)
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
    K.ok = anyedge("Return", "Space"); K.back = anyedge("Escape"); K.pause = anyedge("P")
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
    local idx = #list + 1
    list[idx] = id
    local hov = inside(x, y, w, h)
    if hov and MS.moved then focus = idx; UI.kbd = false end
    local foc = (focus == idx)
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
function UI.gem_icon(id, cx, cy, s, z) UI.img(id, "gem", cx, cy, s, z) end
-- "[prefix] (icon) value" laid out as one centred row, so icon and numbers never collide
function UI.icon_label(id, prefix, icon, value, cx, cy, fs, z, col, shadow)
    local sc = fs * US
    local h = fs * 26 * US
    local isz = fs * 12.5                       -- icon size in 1080p px
    local gap = fs * 2.6 * US
    local w1 = prefix ~= "" and text_w(prefix, sc) or 0
    local w2 = text_w(value, sc)
    local total = w1 + (w1 > 0 and gap * 1.6 or 0) + isz * US + gap + w2
    local x = cx - total / 2
    local box = 26 * sc
    if w1 > 0 then
        UI.text(id .. "_p", prefix, x - box / 2, cy - h / 2, w1 + box, h, fs, col, "center", z, shadow)
        x = x + w1 + gap * 1.6
    end
    UI.img(id .. "_i", icon, x + isz * US / 2, cy - 1 * US, isz, z + 0.3)
    x = x + isz * US + gap
    UI.text(id .. "_v", value, x - box / 2, cy - h / 2, w2 + box, h, fs, col, "center", z, shadow)
end
function UI.star(id, cx, cy, s, on, z) UI.img(id, on and "star" or "star_off", cx, cy, s, z) end
-- currency pill
function UI.pill(id, x, y, w, icon, value, z)
    local h = 58 * US
    UI.rect(id, x, y, w * US, h, { .08, .14, .32, 0.55 }, 29, z or 30)
    if icon == "coin" then UI.coin_icon(id .. "i", x + 30 * US, y + h / 2, 40, (z or 30) + 1) else UI.gem_icon(id .. "i", x + 30 * US, y + h / 2, 36, (z or 30) + 1) end
    UI.text(id .. "v", value, x + 56 * US, y, w * US - 66 * US, h, 1.9, { 1, 1, 1, 1 }, "left", (z or 30) + 1)
end
end
------------------------------------------------------------------ HUD + G hooks (popups, punch, shake, tips) + world labels
do
local U = G.UI
local M = G.M
local US = U.US
local HUD = { pops = {}, wpops = {}, tip = nil }
G.HUD = HUD
-- hooks used by the run / finale code
G.fovp, G.fovp_t, G.fovp_d, G.shk = 0, 1, 1, 0
function G.punch(deg, dur) if abs(deg) >= abs(G.fovp * (1 - G.fovp_t / G.fovp_d)) then G.fovp, G.fovp_t, G.fovp_d = deg, 0, dur or 0.3 end end
function G.shake(a) G.shk = max(G.shk, (a or 0.2) * SET:shake_scale()) end
function G.popup(text, col, dur)
    table.insert(HUD.pops, 1, { text = text, col = col or { 1, 1, 1, 1 }, t = 0, dur = dur or 1 })
    while #HUD.pops > 3 do table.remove(HUD.pops) end
end
function G.popup_at(text, x, y, z, col, dur)
    HUD.wpops[#HUD.wpops + 1] = { text = text, x = x, y = y, z = z, col = col or { 1, 1, 1, 1 }, t = 0, dur = dur or 0.8 }
    while #HUD.wpops > 8 do table.remove(HUD.wpops, 1) end
end
function G.tip(text) HUD.tip = { text = text, t = 0 } end
local last_coin, last_hit, last_pop = 0, 0, 0
function G.coin_sfx() if G.t - last_coin > 0.07 then last_coin = G.t; sfx("coin") end end
function G.sfx_hit() if G.t - last_hit > 0.06 then last_hit = G.t; sfx("hit") end end
function G.on_loss(t, how) if G.t - last_pop > 0.09 then last_pop = G.t; sfx(how == "fall" and "pop" or "pop") end end
function G.use_shield()
    if (G.shields or 0) > 0 and (G.shield_t or 0) <= 0 and RUN.phase ~= "dead" then
        G.shields = G.shields - 1; G.shield_t = 3; sfx("shield"); G.punch(3, 0.3)
        G.popup("Shield Up!", { .6, .85, 1, 1 }, 0.9)
        return true
    end
end

local function fmt(n) n = floor(n + 0.5); local s = tostring(n); if n >= 10000 then s = string.format("%.1fk", n / 1000) end; return s end
HUD.fmt = fmt
-- one world label (projected), auto-sized by distance
local function wlabel(id, l)
    local sx, sy, zc = project(LX(l.x), l.y, l.z)
    if zc < 1 or zc > 75 or sx < -200 or sx > SW + 200 then return end
    local fs = clamp(l.size * 30 / zc, 1.15, 5.5)
    if l.bg then
        local w = (#l.text * 0.52 + 1.1) * fs * 16 * US
        local h = fs * 22 * US
        U.rect(id .. "b", sx - w / 2, sy - h / 2 + 3 * US, w, h, { l.bg[1] * 0.6, l.bg[2] * 0.6, l.bg[3] * 0.6, l.bg[4] }, h / US / 2, 6)
        U.rect(id .. "f", sx - w / 2, sy - h / 2, w, h, l.bg, h / US / 2, 6.1)
        U.text(id .. "t", l.text, sx - w / 2, sy - h / 2, w, h, fs, l.col, "center", 6.3, false)
        return { sx - w / 2, sy - h / 2, w, h }
    else
        U.big(id, l.text, sx, sy, fs, l.col, clamp(fs * 0.8, 1.2, 3.5), 6)
        local w, h = (#l.text * 0.6 + 0.6) * fs * 16 * US, fs * 26 * US
        return { sx - w / 2, sy - h / 2, w, h }
    end
end
local function progress_bar(L)
    local w, h = 560 * US, 22 * US
    local x, y = SW / 2 - w / 2, 92 * US
    U.text("lvname", "Level " .. L.idx .. "  ·  " .. L.name, x - 200 * US, 26 * US, w + 400 * US, 54 * US, 2.0, { 1, 1, 1, 1 }, "center", 31)
    U.rect("pb_bg", x, y, w, h, { .08, .14, .32, 0.5 }, 11, 30)
    local fin = L.len + (L.boss and 51 or 0)
    local k = clamp(C.cz / fin, 0, 1)
    U.rect("pb_fill", x + 4 * US, y + 4 * US, max(h - 8 * US, (w - 8 * US) * k), h - 8 * US, { .35, .75, 1, 1 }, 7, 30.1)
    U.rect("pb_shine", x + 6 * US, y + 5 * US, max(1, (w - 12 * US) * k), (h - 8 * US) * 0.4, { 1, 1, 1, 0.35 }, 4, 30.2)
    U.img("pb_end", L.boss and "man_r" or "star", x + w + 26 * US, y + h / 2, 52, 31)
end
-- the in-run HUD. returns "pause" when the pause button is hit
function HUD.play(dt, L)
    local act
    -- currency pills
    U.pill("hc", 28 * US, 26 * US, 210, "coin", fmt(M.D.coins + (RUN.stats and RUN.stats.coins or 0)), 30)
    U.pill("hg", 252 * US, 26 * US, 150, "gem", fmt(M.D.gems), 30)
    progress_bar(L)
    -- pause
    if U.button("b_pause", "", SW - 70 * US, 62 * US, 84, 84, "white", { r = 42, z = 40 }) then act = "pause" end
    U.img("b_pause_i", "pause", SW - 70 * US, 58 * US, 50, 40.6, { .2, .3, .55, 1 })
    -- shield button
    if (G.shields or 0) > 0 or (G.shield_t or 0) > 0 then
        local cx, cy = SW - 100 * US, SH - 120 * US
        if U.button("b_shield", "", cx, cy, 130, 130, (G.shield_t or 0) > 0 and "purple" or "blue", { r = 65, z = 40 }) then G.use_shield() end
        U.img("b_shield_i", "shield", cx, cy - 6 * US, 84, 40.6)
        U.text("b_shield_n", (G.shield_t or 0) > 0 and string.format("%.1f", G.shield_t) or ("x" .. G.shields), cx - 60 * US, cy + 30 * US, 120, 40 * US, 1.7, { 1, 1, 1, 1 }, "center", 40.7)
        U.text("b_shield_k", "Space", cx - 60 * US, cy + 72 * US, 120, 30 * US, 1.1, { 1, 1, 1, 0.85 }, "center", 40.7)
    end
    -- world labels from the run code
    -- staircase multipliers painted on the coming steps (x1.2 ... x5.0)
    local S = G.stairs
    if S and C.cz > S.z0 - 70 and RUN.phase ~= "dead" then
        local k0 = (G.FIN.s and G.FIN.s.k) or 0
        for i = k0 + 1, min(S.n, k0 + 9) do
            local gold = (i % 5 == 0)
            R.labels[#R.labels + 1] = { x = W - 1.5, y = (i - 0.45) * S.h, z = S.z0 + (i - 1) * S.d - 0.06, text = "x" .. string.format("%.1f", 1 + 0.2 * i),
                col = gold and { 1, .86, .3, 1 } or { 1, 1, 1, 1 }, size = gold and 1.6 or 1.25, bg = { .08, .12, .3, .78 } }
        end
    end
    local rects = {}
    for i, l in ipairs(R.labels) do local r = wlabel("wl" .. i, l); if r then rects[#rects + 1] = r end end
    R.labels = {}
    -- crowd counter badge
    if #C.units > 0 and RUN.phase ~= "dead" then
        local bz, by0 = C.cz + (C.hd or 1) * 0.3, (C.cy or 0)
        -- on the staircase the column is long and climbing: ride just behind its front, on the smooth ramp
        if RUN.phase == "stairs" and G.FIN.s then local S = G.FIN.s; bz = S.front - 1.2; by0 = G.FIN.ramp(bz) end
        local sx, sy, zc = project(LX(C.cx), 2.1 + by0 + min(2, (C.rmax or 1) * 0.15) + (C.cnt[3] > 0 and 1.6 or (C.cnt[2] > 0 and 0.7 or 0)), bz)
        if zc > 1 then
            local txt = fmt(C.power())
            local fs = clamp(52 / zc, 1.8, 3.2)
            local w, h = (#txt * 0.55 + 1.3) * fs * 16 * US, fs * 22 * US
            if RUN.clash then sx = sx - w * 0.6 end   -- keep clear of the red badge during a clash
            -- gate numbers win: the badge sits behind world labels and fades where it overlaps one
            local bx, by = sx - w / 2, sy - h / 2
            local a = 1
            for _, r in ipairs(rects) do
                if bx < r[1] + r[3] and bx + w > r[1] and by < r[2] + r[4] + 6 * US and by + h > r[2] then a = 0.28 end
            end
            HUD.badge_a = damp(HUD.badge_a or 1, a, 10, dt)
            local ba = HUD.badge_a
            U.rect("cnt_b", sx - w / 2, sy - h / 2 + 4 * US, w, h, { .1, .3, .7, ba }, h / US / 2, 5)
            U.rect("cnt_f", sx - w / 2, sy - h / 2, w, h, { .25, .55, 1, ba }, h / US / 2, 5.1)
            U.rect("cnt_h", sx - w / 2 + 6 * US, sy - h / 2 + 3 * US, w - 12 * US, h * 0.4, { 1, 1, 1, .25 * ba }, h / US / 4, 5.2)
            U.text("cnt_t", txt, sx - w / 2, sy - h / 2, w, h, fs, { 1, 1, 1, ba }, "center", 5.3, false)
        end
    end

    -- boss bar
    local B = G.FIN.b
    if B and (B.state == "fight" or (B.state == "wait" and C.cz > B.z - 40)) then
        local w, h = 640 * US, 34 * US
        local x, y = SW / 2 - w / 2, 150 * US
        U.text("boss_n", "The King  " .. fmt(B.hp), x, y - 46 * US, w, 44 * US, 2.0, { 1, .9, .6, 1 }, "center", 31)
        U.rect("boss_bg", x, y, w, h, { .2, .05, .05, 0.65 }, 17, 30)
        local k = clamp(B.hp / max(1, B.hp0), 0, 1)
        U.rect("boss_f", x + 5 * US, y + 5 * US, max(h - 10 * US, (w - 10 * US) * k), h - 10 * US, B.hit and { 1, 1, 1, 1 } or { .95, .25, .25, 1 }, 12, 30.1)
        U.rect("boss_s", x + 8 * US, y + 7 * US, max(1, (w - 16 * US) * k), (h - 10 * US) * 0.4, { 1, 1, 1, .3 }, 6, 30.2)
    end
    HUD.overlays(dt)
    return act
end
-- popups / world pops / tips (also used on the finale)
function HUD.overlays(dt)
    for i = #HUD.pops, 1, -1 do
        local p = HUD.pops[i]
        p.t = p.t + dt
        if p.t > p.dur + 0.3 then table.remove(HUD.pops, i) end
    end
    for i, p in ipairs(HUD.pops) do
        local pop = 1 + 0.45 * max(0, 1 - p.t * 7)
        local a = clamp((p.dur + 0.3 - p.t) / 0.3, 0, 1)
        local col = { p.col[1], p.col[2], p.col[3], a }
        U.big("pop" .. i, p.text, SW / 2, SH * 0.3 - (i - 1) * 80 * US - p.t * 30 * US, 4.2 * pop * (i == 1 and 1 or 0.7), col, 4, 50)
    end
    for i = #HUD.wpops, 1, -1 do
        local p = HUD.wpops[i]
        p.t = p.t + dt
        if p.t > p.dur then table.remove(HUD.wpops, i) end
    end
    for i, p in ipairs(HUD.wpops) do
        local sx, sy, zc = project(LX(p.x), p.y + p.t * 1.5, p.z)
        if zc > 1 then
            local a = clamp((p.dur - p.t) / 0.25, 0, 1)
            U.big("wp" .. i, p.text, sx, sy, clamp(36 / zc, 1, 2.6), { p.col[1], p.col[2], p.col[3], a }, 2, 45)
        end
    end
    local t = HUD.tip
    if t then
        t.t = t.t + dt
        if t.t > 4.2 then HUD.tip = nil
        else
            local a = clamp(min(t.t * 5, (4.2 - t.t) * 3), 0, 1)
            local w, h = max(520, #t.text * 22 + 120) * US, 76 * US
            local y = SH - 190 * US + (1 - a) * 40 * US
            U.rect("tip_s", SW / 2 - w / 2 + 4 * US, y + 8 * US, w, h, { .05, .1, .25, .25 * a }, 38, 44)
            U.rect("tip_b", SW / 2 - w / 2, y, w, h, { 1, 1, 1, .96 * a }, 38, 44.1)
            U.rect("tip_a", SW / 2 - w / 2 + 14 * US, y + 14 * US, h - 28 * US, h - 28 * US, { 1, .75, .2, a }, 24, 44.2)
            U.text("tip_ai", "!", SW / 2 - w / 2 + 14 * US, y + 14 * US, h - 28 * US, h - 28 * US, 2.2, { 1, 1, 1, a }, "center", 44.3, false)
            U.text("tip_t", t.text, SW / 2 - w / 2 + h, y, w - h - 20 * US, h, 2.1, { .15, .22, .42, a }, "center", 44.3, false)
        end
    end
end
end
------------------------------------------------------------------ menu screens: title, level select, camp (shop / gems / army board), pause, win, lose
do
local U = G.UI
local M = G.M
local US = U.US
local SCR = {}
G.SCR = SCR
local fmt = G.HUD.fmt
local WCOL = { { .35, .75, .35, 1 }, { .95, .7, .35, 1 }, { .45, .7, .95, 1 }, { .9, .45, .4, 1 } }
local WNAME = { "Meadow", "Dunes", "Glacier", "Ember" }
SCR.WCOL = WCOL

local function dim(a) U.rect("dim", 0, 0, SW, SH, { .05, .12, .3, a or 0.35 }, 0, 1) end
local function pills()
    U.pill("mc", 28 * US, 26 * US, 210, "coin", fmt(M.D.coins), 30)
    U.pill("mg", 252 * US, 26 * US, 150, "gem", fmt(M.D.gems), 30)
end
local function ribbon(id, text, cx, cy, w, col, fs)
    w = w * US
    local h = 96 * US
    U.rect(id .. "s", cx - w / 2 + 6 * US, cy - h / 2 + 10 * US, w, h, { .05, .1, .25, .3 }, 30, 19.5)
    U.rect(id .. "l", cx - w / 2, cy - h / 2 + 8 * US, w, h, { col[1] * .6, col[2] * .6, col[3] * .6, 1 }, 30, 19.6)
    U.rect(id, cx - w / 2, cy - h / 2, w, h, col, 30, 19.7)
    U.rect(id .. "h", cx - w / 2 + 12 * US, cy - h / 2 + 6 * US, w - 24 * US, h * 0.36, { 1, 1, 1, .22 }, 20, 19.8)
    U.big(id .. "t", text, cx, cy, fs or 3.6, { 1, 1, 1, 1 }, 3, 20)
end
SCR.ribbon = ribbon

-- title ------------------------------------------------------------------------------------------
function SCR.title(dt)
    local act
    pills()
    local t = G.t
    local bob = sin(t * 2) * 6 * US
    U.big("logo2", "Crowd", SW / 2, 190 * US + bob, 8.5, { .35, .7, 1, 1 }, 6, 20)
    U.big("logo1", "Master", SW / 2, 330 * US + bob, 9.5, { 1, .82, .25, 1 }, 6, 20)
    U.text("logo3", "Run  ·  Merge  ·  Conquer", SW / 2 - 400 * US, 420 * US, 800 * US, 50 * US, 2.0, { 1, 1, 1, .95 }, "center", 20)
    local nx = M.D.unlocked
    local y0 = 560 * US
    if U.button("t_play", "Play", SW / 2, y0, 420, 110, "green", { fs = 4.2 }) then act = "play" end
    U.text("t_play_s", "Level " .. min(nx, #G.LEVELS), SW / 2 - 200 * US, y0 + 66 * US, 400 * US, 40 * US, 1.5, { 1, 1, 1, .95 }, "center", 21)
    if U.button("t_lv", "Levels", SW / 2 - 140 * US, y0 + 150 * US, 260, 84, "blue") then act = "levels" end
    if U.button("t_shop", "Shop", SW / 2 + 140 * US, y0 + 150 * US, 260, 84, "orange") then act = "camp" end
    if U.button("t_opt", "Options", SW / 2 - 140 * US, y0 + 260 * US, 260, 84, "white") then act = "options" end
    if U.button("t_quit", "Quit", SW / 2 + 140 * US, y0 + 260 * US, 260, 84, "red") then act = "quit" end
    U.text("t_help", "Mouse Or Arrows + Enter", SW / 2 - 300 * US, SH - 60 * US, 600 * US, 40 * US, 1.3, { 1, 1, 1, .8 }, "center", 20)
    return act
end

-- level select -----------------------------------------------------------------------------------
function SCR.levels(dt)
    local act
    dim(0.3); pills()
    ribbon("lv_r", "Choose A Level", SW / 2, 120 * US, 640, { .3, .6, 1, 1 })
    local cw, ch, gx, gy = 330, 190, 26, 26
    local cols = 4
    local x0 = SW / 2 - (cols * cw + (cols - 1) * gx) * US / 2
    local y0 = 210 * US
    for i, L in ipairs(G.LEVELS) do
        local c, r = (i - 1) % cols, floor((i - 1) / cols)
        local x, y = x0 + c * (cw + gx) * US, y0 + r * (ch + gy) * US
        local cx, cy = x + cw * US / 2, y + ch * US / 2
        local locked = i > M.D.unlocked
        local wc = WCOL[L.world] or WCOL[1]
        local id = "lv" .. i
        if U.button(id, "", cx, cy, cw, ch, locked and "grey" or "white", { r = 24, z = 20 }) and not locked then act = i end
        U.rect(id .. "_band", cx - cw * US / 2 + 10 * US, cy - ch * US / 2 + 10 * US, cw * US - 20 * US, 54 * US, locked and { .55, .58, .65, 1 } or wc, 18, 20.25)
        U.text(id .. "_n", tostring(i), cx - cw * US / 2 + 10 * US, cy - ch * US / 2 + 10 * US, 70 * US, 54 * US, 2.5, { 1, 1, 1, 1 }, "center", 20.4)
        U.text(id .. "_w", WNAME[L.world] or "", cx - cw * US / 2 + 70 * US, cy - ch * US / 2 + 10 * US, cw * US - 90 * US, 54 * US, 1.4, { 1, 1, 1, .95 }, "right", 20.4, false)
        U.text(id .. "_nm", L.name, cx - cw * US / 2, cy - 18 * US, cw * US, 50 * US, 1.75, locked and { 1, 1, 1, .9 } or { .15, .22, .42, 1 }, "center", 20.4, false)
        if locked then
            U.img(id .. "_lk", "lock", cx, cy + 50 * US, 56, 20.5, { 1, 1, 1, .9 })
        else
            local b = M.D.best[i]
            for s = 1, 3 do U.star(id .. "_s" .. s, cx + (s - 2) * 56 * US, cy + 52 * US - (s == 2 and 8 * US or 0), s == 2 and 54 or 46, b and b.stars >= s, 20.5) end
            if L.boss then U.img(id .. "_bs", "man_r", cx + cw * US / 2 - 40 * US, cy + 50 * US, 50, 20.5) end
        end
    end
    if U.button("lv_back", "Back", 150 * US, SH - 80 * US, 220, 80, "white") or U.K.back then act = "back" end
    return act
end

-- camp: Upgrades / Gems / Army -------------------------------------------------------------------
SCR.tab = "Upgrades"
local drag = nil   -- army board drag {from, x, y}
local sel = nil    -- click-to-merge selection
local note = nil
local function say(text, col) note = { text = text, col = col or { .15, .22, .42, 1 }, t = 0 } end
SCR.say = say
local function upgrade_card(id, u, x, y, w, h, gem)
    local lv = gem and M.glvl(u.id) or M.lvl(u.id)
    U.card(id, x, y, w, h, { 1, 1, 1, .97 }, 12)
    U.text(id .. "_n", u.name, x + 24 * US, y + 14 * US, w - 48 * US, 50 * US, 2.0, { .15, .22, .42, 1 }, "left", 12.5, false)
    U.text(id .. "_d", u.desc, x + 24 * US, y + 62 * US, w - 48 * US, 40 * US, 1.25, { .35, .42, .58, 1 }, "left", 12.5, false)
    -- level pips
    local pw = (w - 48 * US - (u.max - 1) * 6 * US) / u.max
    for k = 1, u.max do
        U.rect(id .. "_p" .. k, x + 24 * US + (k - 1) * (pw + 6 * US), y + 112 * US, pw, 16 * US, k <= lv and (gem and { .9, .35, .85, 1 } or { .3, .7, 1, 1 }) or { .86, .89, .94, 1 }, 8, 12.5)
    end
    local maxed = lv >= u.max
    local cost = gem and M.gcost(u) or M.cost(u)
    local can = not maxed and ((gem and M.D.gems or M.D.coins) >= cost)
    local bx, by = x + w / 2, y + h - 52 * US
    local label = maxed and "Max" or ""
    local kind = maxed and "grey" or (can and (gem and "purple" or "green") or "grey")
    local hit = U.button(id .. "_b", label, bx, by, (w / US) - 60, 72, kind, { z = 14, disabled = false })
    if not maxed then
        U.icon_label(id .. "_bl", "", gem and "gem" or "coin", fmt(cost), bx, by - 2 * US, 3.1, 14.4, { 1, 1, 1, 1 }, true)
    end
    if hit then
        if maxed then say("Already Maxed") 
        elseif (gem and M.gbuy(u)) or (not gem and M.buy(u)) then sfx("buy"); say(u.name .. " Upgraded!", { .2, .6, .25, 1 }); G.FX.confetti(LX(C.cx), 2, C.cz + 2, 20)
        else sfx("deny"); say(gem and "Not Enough Gems" or "Not Enough Coins", { .8, .25, .2, 1 }) end
    end
end
local TIERN = { "Pawn", "Brute", "Giant" }
local TIMG = { "man_b", "man_v", "man_y" }
local function board(x0, y0)
    local sz, gap = 132, 14
    local B = M.D.board
    local rects = {}
    local hover
    for i = 1, 15 do
        local c, r = (i - 1) % 5, floor((i - 1) / 5)
        local x, y = x0 + c * (sz + gap) * US, y0 + r * (sz + gap) * US
        local cx, cy = x + sz * US / 2, y + sz * US / 2
        local t = B[i]
        rects[i] = { x, y, sz * US, sz * US }
        local id = "bd" .. i
        local kind = (sel == i) and "gold" or (t == 0 and "white" or ({ "blue", "purple", "orange" })[t])
        local hit = U.button(id, "", cx, cy, sz, sz, kind, { r = 26, z = 12 })
        if U.inside(x, y, sz * US, sz * US) then hover = i end
        if t > 0 and not (drag and drag.from == i and drag.moved) then
            U.img(id .. "_m", TIMG[t] , cx, cy - 8 * US, 70 + t * 16, 13)
            U.text(id .. "_t", TIERN[t], x, y + sz * US - 40 * US, sz * US, 32 * US, 1.2, { 1, 1, 1, 1 }, "center", 13.1)
        elseif t == 0 then U.text(id .. "_t", "+", x, y, sz * US, sz * US, 3, { .7, .75, .85, 1 }, "center", 13.1, false) end
        -- keyboard: Enter selects, Enter on another slot merges / moves. mouse click on an empty slot moves the selection
        if U.activate == id then
            if sel and sel ~= i then local r = M.merge(sel, i); SCR.merged(r, i); sel = nil
            elseif t > 0 then sel = (sel == i) and nil or i end
        elseif hit and U.MS.click and t == 0 and sel then local r = M.merge(sel, i); SCR.merged(r, i); sel = nil end
    end
    -- mouse drag-to-merge (press on a unit, release on a slot). a click without moving selects / merges into the selection
    local MS = U.MS
    if MS.click and hover and B[hover] > 0 and not drag then drag = { from = hover, moved = false } end
    if drag then
        if MS.down and (abs(MS.x - (MS.px or MS.x)) + abs(MS.y - (MS.py or MS.y)) > 12 * US) then drag.moved = true end
        if drag.moved and B[drag.from] > 0 then U.img("drag_m", TIMG[B[drag.from]], MS.x, MS.y, 100 + B[drag.from] * 16, 60) end
        if MS.release or not MS.down then
            if drag.moved then
                if hover and hover ~= drag.from then local r = M.merge(drag.from, hover); SCR.merged(r, hover) end
                sel = nil
            else
                if sel and sel ~= drag.from then local r = M.merge(sel, drag.from); SCR.merged(r, drag.from); sel = nil
                elseif sel == drag.from then sel = nil else sel = drag.from; sfx("hover") end
            end
            drag = nil
        end
    end
    return rects
end
function SCR.merged(r, at)
    if r == "merge" then sfx("merge"); say(TIERN[M.D.board[at]] .. " Forged!", { .55, .3, .9, 1 }); G.punch(2, 0.3)
    elseif r == "move" or r == "swap" then sfx("click") else sfx("deny") end
end
function SCR.camp(dt)
    local act
    dim(0.38); pills()
    ribbon("cp_r", "Camp", SW / 2, 100 * US, 420, { 1, .62, .2, 1 })
    -- tabs
    local tabs = { "Upgrades", "Gems", "Army" }
    for i, tname in ipairs(tabs) do
        local on = SCR.tab == tname
        if U.button("tab" .. i, tname, SW / 2 + (i - 2) * 260 * US, 205 * US, 240, 70, on and "blue" or "white", { z = 15 }) then SCR.tab = tname; sel = nil end
    end
    local px, py, pw = SW / 2 - 820 * US, 270 * US, 1640 * US
    if SCR.tab == "Upgrades" or SCR.tab == "Gems" then
        local list = SCR.tab == "Upgrades" and M.UP or M.GEM
        local cols = SCR.tab == "Upgrades" and 3 or 2
        local cw = (pw - (cols - 1) * 26 * US) / cols
        local ch = 250 * US
        for i, u in ipairs(list) do
            local c, r = (i - 1) % cols, floor((i - 1) / cols)
            upgrade_card("up" .. i, u, px + c * (cw + 26 * US), py + r * (ch + 26 * US), cw, ch, SCR.tab == "Gems")
        end
    else
        -- army board + info
        U.card("arm_bg", px, py, 760 * US, 500 * US, { 1, 1, 1, .5 }, 10)
        board(px + 22 * US, py + 22 * US)
        local ix = px + 790 * US
        U.card("arm_info", ix, py, pw - 790 * US, 500 * US, { 1, 1, 1, .97 }, 10)
        local a = G.army_counts()
        local lines = {
            "Drag A Unit Onto A Twin To Merge",
            "Pawn  =  2 Runners At The Start",
            "Brute  =  Power 3  ·  Takes 2 Hits",
            "Giant  =  Power 8  ·  Takes 4 Hits",
            "Big Units Shrug Off Traps And Wreck Bosses,",
            "But Plus Gates Only Add Pawns.",
        }
        for i, l in ipairs(lines) do U.text("arm_l" .. i, l, ix + 30 * US, py + (14 + (i - 1) * 46) * US, pw - 850 * US, 44 * US, i == 1 and 1.75 or 1.45, i == 1 and { .15, .22, .42, 1 } or { .35, .42, .58, 1 }, "left", 10.5, false) end
        U.text("arm_sum", "Starts With  " .. (G.start_pawns() + a[1]) .. " Pawns  ·  " .. a[2] .. " Brutes  ·  " .. a[3] .. " Giants", ix + 30 * US, py + 300 * US, pw - 850 * US, 44 * US, 1.6, { .25, .5, .95, 1 }, "left", 10.5, false)
        local rc = M.recruit_cost()
        local rx, ry = ix + 230 * US, py + 420 * US
        if U.button("arm_rec", "", rx, ry, 380, 84, M.D.coins >= rc and "green" or "grey", { z = 14 }) then
            local ok, why = M.recruit()
            if ok then sfx("buy"); say("A New Pawn Joins!", { .2, .6, .25, 1 }) else sfx("deny"); say(why, { .8, .25, .2, 1 }) end
        end
        U.icon_label("arm_rec_l", "Recruit", "coin", fmt(rc), rx, ry - 2 * US, 3.2, 14.4, { 1, 1, 1, 1 }, true)
        if U.button("arm_auto", "Auto Merge", ix + 640 * US, py + 420 * US, 340, 84, "purple", { z = 14 }) then
            local r, at = M.auto_merge(); if r then SCR.merged(r, at) else sfx("deny"); say("No Twins To Merge", { .8, .25, .2, 1 }) end
        end
    end
    -- treasury
    local bank = floor(M.D.bank or 0)
    local ty = SH - 150 * US
    U.card("tre", SW / 2 - 820 * US, ty - 56 * US, 640 * US, 112 * US, { 1, 1, 1, .97 }, 10)
    U.coin_icon("tre_i", SW / 2 - 770 * US, ty, 56, 10.5)
    U.text("tre_t", "Treasury  " .. bank .. " / " .. floor(60 + 120 * M.lvl("bank")), SW / 2 - 730 * US, ty - 50 * US, 360 * US, 100 * US, 1.7, { .15, .22, .42, 1 }, "left", 10.5, false)
    if U.button("tre_b", "Collect", SW / 2 - 300 * US, ty, 200, 76, bank > 0 and "gold" or "grey", { z = 14 }) then
        if bank > 0 then local n = M.collect(); sfx("coin"); say("+" .. n .. " Coins Collected", { .7, .5, .05, 1 }) else sfx("deny"); say("Treasury Is Empty - Upgrade It To Earn While You Play", { .8, .25, .2, 1 }) end
    end
    if U.button("cp_next", "Next Level", SW / 2 + 620 * US, ty, 340, 96, "green", { fs = 3 }) then act = "next" end
    if U.button("cp_menu", "Menu", SW / 2 + 330 * US, ty, 200, 80, "white") or U.K.back then act = "back" end
    -- feedback note
    if note then
        note.t = note.t + dt
        if note.t > 2.2 then note = nil else
            local a = clamp((2.2 - note.t) * 3, 0, 1)
            local w = (#note.text * 20 + 100) * US
            U.rect("note_b", SW / 2 - w / 2, 236 * US + 520 * US, w, 64 * US, { 1, 1, 1, .95 * a }, 32, 50)
            U.text("note_t", note.text, SW / 2 - w / 2, 236 * US + 520 * US, w, 64 * US, 1.8, { note.col[1], note.col[2], note.col[3], a }, "center", 50.1, false)
        end
    end
    return act
end

-- pause --------------------------------------------------------------------------------------------
function SCR.pause(dt)
    local act
    dim(0.45)
    local w, h = 560 * US, 600 * US
    U.card("pz", SW / 2 - w / 2, SH / 2 - h / 2, w, h, { 1, 1, 1, .97 }, 15)
    ribbon("pz_r", "Paused", SW / 2, SH / 2 - h / 2, 480, { .3, .6, 1, 1 })
    if U.button("pz_res", "Resume", SW / 2, SH / 2 - 120 * US, 380, 92, "green", { fs = 4 }) or U.K.back or U.K.pause then act = "resume" end
    if U.button("pz_ret", "Retry", SW / 2, SH / 2 - 5 * US, 380, 80, "blue") then act = "retry" end
    if U.button("pz_opt", "Options", SW / 2, SH / 2 + 100 * US, 380, 80, "purple") then act = "options" end
    if U.button("pz_menu", "Menu", SW / 2, SH / 2 + 205 * US, 380, 80, "orange") then act = "menu" end
    return act
end

-- win / lose cards -----------------------------------------------------------------------------------
SCR.res = nil   -- { won, tally, t, L }
function SCR.result(dt)
    local S = SCR.res
    S.t = S.t + dt
    local act
    dim(0.4)
    local w, h = 820 * US, 820 * US
    local x, y = SW / 2 - w / 2, SH / 2 - h / 2 + 30 * US
    local pop = clamp(S.t * 4, 0, 1)
    U.card("rs", x, y, w, h, { 1, 1, 1, .97 }, 15)
    local T = S.tally
    if S.won then
        ribbon("rs_r", "Level Complete!", SW / 2, y, 640, { .3, .78, .35, 1 })
        for s = 1, 3 do
            local on = T.stars >= s and S.t > 0.3 + s * 0.25
            if on and not S["st" .. s] then S["st" .. s] = true; sfx("trophy"); G.punch(1.5, 0.2) end
            local sp = on and (1 + 0.5 * max(0, 1 - (S.t - 0.3 - s * 0.25) * 6)) or 1
            U.star("rs_s" .. s, SW / 2 + (s - 2) * 150 * US, y + 150 * US - (s == 2 and 22 * US or 0), (s == 2 and 140 or 116) * sp, on, 16)
        end
        local R0 = S.res
        local head = R0.kind == "boss" and "The King Has Fallen!" or ("Climbed " .. R0.k .. " Steps  ·  x" .. string.format("%.1f", R0.mult))
        U.text("rs_h", head, x, y + 230 * US, w, 50 * US, 2.2, { .15, .22, .42, 1 }, "center", 16, false)
    else
        ribbon("rs_r", "Crowd Lost!", SW / 2, y, 560, { .95, .35, .3, 1 })
        local k = clamp(S.prog or 0, 0, 1)
        U.text("rs_h", "You Made It " .. floor(k * 100) .. "% Of The Way", x, y + 110 * US, w, 50 * US, 2.2, { .15, .22, .42, 1 }, "center", 16, false)
        U.rect("rs_pb", x + 120 * US, y + 180 * US, w - 240 * US, 26 * US, { .86, .89, .94, 1 }, 13, 16)
        U.rect("rs_pf", x + 124 * US, y + 184 * US, max(18 * US, (w - 248 * US) * k), 18 * US, { .95, .4, .35, 1 }, 9, 16.1)
        U.text("rs_tip", S.hint or "", x + 40 * US, y + 220 * US, w - 80 * US, 50 * US, 1.5, { .35, .42, .58, 1 }, "center", 16, false)
        local st = G.RUN.stats or {}
        local chips = { { "Biggest Crowd", st.peak or 0, { .25, .55, 1, 1 } }, { "Gates", st.gates or 0, { .3, .75, .35, 1 } }, { "Enemies Beaten", st.kills or 0, { .95, .4, .35, 1 } } }
        local cw = (w - 160 * US) / 3
        for i, c in ipairs(chips) do
            local cx = x + 60 * US + (i - 1) * (cw + 20 * US)
            U.rect("rs_cb" .. i, cx, y + 290 * US, cw, 120 * US, { .95, .96, 1, 1 }, 22, 16)
            U.text("rs_cv" .. i, fmt(c[2]), cx, y + 295 * US, cw, 64 * US, 3.0, c[3], "center", 16.1, false)
            U.text("rs_cl" .. i, c[1], cx, y + 357 * US, cw, 40 * US, 1.4, { .35, .42, .58, 1 }, "center", 16.1, false)
        end
    end
    -- tally lines roll in
    local ly = y + (S.won and 300 or 430) * US
    local shown = floor((S.t - 0.4) / 0.18)
    for i, l in ipairs(T.lines) do
        if i <= shown then
            if not S["ln" .. i] then S["ln" .. i] = true; sfx("coin") end
            local yy = ly + (i - 1) * 46 * US
            U.text("rs_l" .. i, l[1], x + 90 * US, yy, w * 0.6, 44 * US, 1.7, { .3, .38, .55, 1 }, "left", 16, false)
            U.text("rs_v" .. i, "+" .. fmt(l[2]), x + w * 0.55, yy, w * 0.45 - 140 * US, 44 * US, 1.8, { .85, .55, .05, 1 }, "right", 16, false)
            U.coin_icon("rs_c" .. i, x + w - 110 * US, yy + 22 * US, 34, 16.2)
        end
    end
    if shown >= #T.lines then
        local yy = y + h - 230 * US
        U.rect("rs_tb", x + 60 * US, yy - 8 * US, w - 120 * US, 70 * US, { .95, .96, 1, 1 }, 26, 16)
        U.text("rs_tt", "Total", x + 90 * US, yy - 8 * US, 200 * US, 70 * US, 2.2, { .15, .22, .42, 1 }, "left", 16.2, false)
        U.coin_icon("rs_ti", x + 330 * US, yy + 27 * US, 48, 16.3)
        U.text("rs_tv", "+" .. fmt(T.coins), x + 360 * US, yy - 8 * US, 200 * US, 70 * US, 2.6, { .85, .55, .05, 1 }, "left", 16.2, false)
        if T.gems > 0 then
            U.gem_icon("rs_gi", x + 580 * US, yy + 27 * US, 44, 16.3)
            U.text("rs_gv", "+" .. T.gems, x + 610 * US, yy - 8 * US, 120 * US, 70 * US, 2.6, { .8, .25, .75, 1 }, "left", 16.2, false)
        end
        if S.won then
            U.text("rs_sc", "Score " .. fmt(T.score) .. (T.new_best and "   New Best!" or ""), x, yy - 70 * US, w, 50 * US, 1.8, T.new_best and { .95, .5, .1, 1 } or { .35, .42, .58, 1 }, "center", 16, false)
            if T.perfect_run then U.text("rs_pr", "Flawless Run  +1 Gem", x, yy - 112 * US, w, 44 * US, 1.6, { .8, .25, .75, 1 }, "center", 16, false) end
        end
    end
    -- buttons
    local by = y + h - 70 * US
    if S.won then
        local last = (S.L.idx >= #G.LEVELS)
        local nx = SW / 2 - 265 * US
        if U.button("rs_next", last and "Replay" or "Next", SW / 2 - 269 * US, by, 210, 92, "green", { fs = 3.6 }) then act = "next" end
        if U.button("rs_shop", "Shop", SW / 2 - 63 * US, by, 170, 80, "orange") then act = "camp" end
        if U.button("rs_retry", "Retry", SW / 2 + 123 * US, by, 170, 80, "blue") then act = "retry" end
        if U.button("rs_menu", "Menu", SW / 2 + 299 * US, by, 150, 80, "purple") or U.K.back then act = "menu" end
    else
        if U.button("rs_retry", "Retry", SW / 2 - 200 * US, by, 240, 92, "green", { fs = 3.8 }) then act = "retry" end
        if U.button("rs_shop", "Shop", SW / 2 + 30 * US, by, 190, 80, "orange") then act = "camp" end
        if U.button("rs_menu", "Menu", SW / 2 + 220 * US, by, 160, 80, "purple") or U.K.back then act = "menu" end
    end
    return act
end
end
------------------------------------------------------------------ main: states, fixed step, camera, music, test hooks
do
local U, HUD, SCR, FIN, M = G.UI, G.HUD, G.SCR, G.FIN, G.M
local US = U.US
build_lights()
paint_templates()
M.load()
G.state = "title"
local STEP = 1 / 60   -- largest simulation sub-step (each frame's dt is split into equal sub-steps of at most this)
local acc = 0
local sim_dt = STEP  -- the sub-step being simulated (the test bot steers with it)
local CAM = { p = vec3(0, 8, -12), l = vec3(0, 1, 8), fov = 52 }
local menu_level = min(M.D.last or 1, #G.LEVELS)
local end_t = 0

------------------------------------------------------------------ level flow
local function load_level(i, showcase)
    i = clamp(i, 1, #G.LEVELS)
    local L = G.LEVELS[i]
    FIN.cleanup()
    RUN.start(L)
    if L.boss then FIN.boss_build(L) end
    C.cy = 0
    for _, u in ipairs(C.units) do u.y = 0 end   -- staircase feet heights (FIN.stairs_step) never leak into a new run
    G.HUD.pops, G.HUD.wpops, G.HUD.tip = {}, {}, nil
    R.labels = {}
    G.showcase = showcase
    if not showcase then M.D.last = i; M.save()
        if G.boost and G.boost.tries > 0 then G.popup("Retry Boost: +" .. G.boost.pawns .. " Runners, Weaker Foes", { .7, 1, .75, 1 }, 2.6)
        elseif G.boost and G.boost.deficit >= 2 then G.popup("Underdog Boost: +" .. G.boost.pawns .. " Runners, Weaker Foes", { .7, 1, .75, 1 }, 2.6) end
    end
    end_t = 0
    G.hb_reset()
    return L
end
G.goto_level = function(i) load_level(i, false); G.state = "play"; music("run") end
local function go(state)
    G.state = state
    if state == "title" or state == "levels" or state == "camp" then music("title") end
end
local function finish(won)
    local L = G.L
    local res = FIN.result or {}
    local T = M.tally(L, L.idx, won, res, RUN.stats)
    local fin = L.len + (L.boss and 51 or 0)
    local hint = nil
    if not won then
        local hints = { "Upgrade Starting Crowd In The Shop", "Merge Pawns Into Brutes On The Army Board", "Pick Gates By Their Result, Not Their Number",
            "Big Units Survive Traps Better", "Shield Bubble Blocks Every Trap For 3s" }
        hint = "Tip: " .. hints[rand(1, #hints)]
        -- a stuck player sitting on coins: point at the shop first
        local cheap = nil
        for _, u in ipairs(M.UP) do if u.id ~= "bank" and (not u.max or M.lvl(u.id) < u.max) then local c = M.cost(u); if not cheap or c < cheap then cheap = c end end end
        if cheap and M.D.coins >= cheap then hint = "Tip: You Have " .. M.D.coins .. " Coins - Upgrade At The Camp" end
    end
    SCR.res = { won = won, tally = T, t = 0, L = L, res = res, prog = C.cz / fin, hint = hint }
    sfx(won and "win" or "lose")
    G.state = won and "win" or "lose"
    music(nil)
end

------------------------------------------------------------------ autoplay bot (tests): greedy gates, dodges hazards
-- "human" test mode: a steady but imperfect player (reaction delay, keyboard-speed steering, some wrong gate reads,
-- some trap hits, skipped pickups). G.hp overrides the odds; tools/headless.lua runs it in bulk.
local HB = {}
G.hb_reset = function() HB = { t = 0, tx = 0, dec = {}, skip = {}, take = {} } end
local function hazard_at(x, z0, z1, noter)
    for _, e in ipairs(R.list) do
        if not e.done and e.z > z0 and e.z < z1 and not (HB.skip and HB.skip[e]) then
            local t = e.t
            if t == "saw" and x > e.x0 - 0.9 and x < e.x1 + 0.9 then return true end
            if (t == "crush" or t == "roll") and abs(x - e.x) < e.w / 2 + 0.9 then return true end
            if t == "ham" and abs(x - e.x) < 1.6 then return true end
            if t == "spin" then return true end
        end
    end
    local hw = min(C.hw or 1, 1.3) * 0.9   -- the crowd squeezes itself for narrow floor
    for _, zz in ipairs({ z0 - (C.hd or 1) - 0.5, z0, z0 + 3, z0 + 6, z0 + 9, z1 }) do
        local iv = G.floor_at(G.L, zz)
        if not (G.solid(iv, x - hw) and G.solid(iv, x + hw)) then return true end
    end
    if not noter and G.terrain_at(G.L, x, z0 + 6) == "thorn" or G.terrain_at(G.L, x, z0 + 6) == "gravel" then return true end
    return false
end
local function bot(mode)
    if RUN.phase ~= "run" then return end
    local tx = C.cxt
    local front = C.cz + (C.hd or 1)
    local gate
    for _, e in ipairs(R.list) do if e.t == "gate" and not e.done and e.z > front - 0.5 then gate = e; break end end
    if gate and gate.z - front < 28 then
        local best, bv = gate.panels[1], -1e9
        -- timed gates: judge the panels by what they will show on arrival (the lamps let a player read the beat)
        local on_arr
        if gate.kind == "timed" then
            local ta = G.t + max(0, gate.z - (C.hd or 1) * 0.5 - C.cz) / max(3, C.speed)
            on_arr = floor((ta + gate.z * 0.13) / 1.5) % 2 == 0
        end
        for i, p in ipairs(gate.panels) do
            local pv = p.v
            if on_arr ~= nil then pv = on_arr and ((i == 1) and gate.a or gate.b) or ((i == 1) and gate.b or gate.a) end
            local v = RUN.outcome(pv); if mode == "bad" then v = -v end
            if v > bv then bv, best = v, p end
        end
        tx = best.x
    end
    local pick
    -- otherwise grab the next pickup (cage / air drop / ally) like a player would
    if not (gate and gate.z - front < 28) then
        for _, e in ipairs(R.list) do
            if (e.t == "cage" or e.t == "drop" or e.t == "ally") and not e.done and e.z > C.cz - 1 and e.z - front < 24 then
                if mode ~= "bad" then tx = e.x; pick = true end; break
            end
        end
    end
    -- dodge anything in the next ~12 m
    -- with a gate coming up, only dodge what stands before it (a player commits to the panel, then dodges)
    local hz1 = (gate and gate.z - front < 28) and min(C.cz + 12, gate.z - 0.5) or C.cz + 12
    if hazard_at(tx, C.cz, hz1, pick) then
        local cands = { 0, -1, 1, -2, 2, -2.8, 2.8, -3.4, 3.4, -1.5, 1.5 }
        local t0 = tx
        table.sort(cands, function(a, b) return abs(a - t0) < abs(b - t0) end)
        local lim = (gate and gate.z - front < 28) and 1.8 or 99   -- never dodge off the chosen gate panel
        for _, x in ipairs(cands) do if abs(x - t0) <= lim and not hazard_at(x, C.cz, hz1, pick) then tx = x; break end end
    end
    if RUN.safe then local a, b = RUN.safe[1], RUN.safe[2]; tx = (a <= b) and clamp(tx, a, b) or RUN.safe[3] end
    C.cxt = damp(C.cxt, tx, 6, sim_dt)
end
local function human()
    if RUN.phase ~= "run" then return end
    local hp = G.hp or {}
    local dt = sim_dt
    HB.t = HB.t - dt
    if HB.t <= 0 then
        HB.t = (hp.react or 0.32) * rr(0.7, 1.3)
        local front = C.cz + (C.hd or 1)
        local tx = HB.tx
        HB.pick = false
        local gate
        for _, e in ipairs(R.list) do if e.t == "gate" and not e.done and e.z > front - 0.5 then gate = e; break end end
        local see = hp.see or 20
        local near = gate and gate.z - front < see
        if near then
            local d = HB.dec[gate]
            local function vals(arrival)
                local out = {}
                local on
                if gate.kind == "timed" then
                    local ta = G.t + (arrival and max(0, gate.z - (C.hd or 1) * 0.5 - C.cz) / max(3, C.speed) or 0)
                    on = floor((ta + gate.z * 0.13) / 1.5) % 2 == 0
                end
                for i, p in ipairs(gate.panels) do
                    local pv = p.v
                    if on ~= nil then pv = on and ((i == 1) and gate.a or gate.b) or ((i == 1) and gate.b or gate.a) end
                    out[i] = RUN.outcome(pv)
                end
                return out
            end
            local function pick(v, wrong)
                local bi, bv = 1, -1e9
                for i = 1, #v do local x = wrong and -v[i] or v[i]; if x > bv then bi, bv = i, x end end
                return bi
            end
            if not d then
                -- one look at the gate: timed gates are often read by what they show now, not on arrival
                local arrival = not (gate.kind == "timed" and rand() < (hp.p_timed or 0.4))
                local vv = vals(arrival); local wr = rand() < (hp.p_gate or 0.12)
                d = { i = pick(vv, wr) }
                if G.hdebug then print("GATE", gate.z, gate.panels[1].v, gate.panels[1].x, vv[1], gate.panels[2].v, gate.panels[2].x, vv[2], wr, d.i) end
                HB.dec[gate] = d
            end
            if gate.kind == "trick" and gate.flipped and not gate.scramble and not d.re then
                d.re = true
                if rand() < (hp.p_trick or 0.5) then d.i = pick(vals(true), false) end   -- noticed the swap in time
            end
            if gate.kind == "timed" and not d.re2 and gate.z - front < 8 then
                d.re2 = true
                if rand() < (hp.p_late or 0.3) then d.i = pick(vals(true), false) end      -- last-second correction
            end
            tx = gate.panels[d.i].x
        else
            for _, e in ipairs(R.list) do
                if (e.t == "cage" or e.t == "drop" or e.t == "ally") and not e.done and e.z > C.cz - 1 and e.z - front < 22 then
                    if HB.take[e] == nil then HB.take[e] = rand() < (hp.p_pick or 0.75) end
                    if HB.take[e] then tx = e.x; HB.pick = true end
                    break
                end
            end
            if not near and not (gate and gate.z - front < see) then
                -- drift back toward the middle when nothing is going on
                local any = false
                for _, e in ipairs(R.list) do if not e.done and e.z > C.cz and e.z - front < 22 and e.t ~= "enemy" then any = true; break end end
                if not any then tx = tx * 0.7 end
            end
        end
        -- traps: each one is either seen and dodged or (p_miss) run into
        local look = hp.look or 10
        for _, e in ipairs(R.list) do
            if not e.done and HB.skip[e] == nil and e.z > C.cz and e.z - C.cz < look
                and (e.t == "saw" or e.t == "crush" or e.t == "roll" or e.t == "ham" or e.t == "spin") then
                HB.skip[e] = rand() < (hp.p_miss or 0.2)
            end
        end
        local hz1 = near and min(C.cz + look, gate.z - 0.5) or C.cz + look
        if hazard_at(tx, C.cz, hz1, HB.pick) then
            local cands = { 0, -1, 1, -2, 2, -2.8, 2.8, -3.4, 3.4, -1.5, 1.5 }
            local t0 = tx
            table.sort(cands, function(a, b) return abs(a - t0) < abs(b - t0) end)
            local lim = near and 1.8 or 99
            for _, x in ipairs(cands) do if abs(x - t0) <= lim and not hazard_at(x, C.cz, hz1) then tx = x; break end end
        end
        if G.hdebug then print(string.format("    plan z%.1f tx%.2f from %.2f near=%s pick=%s", C.cz, tx, HB.tx, tostring(near), tostring(HB.pick))) end
        -- never cut across a hole to reach the line: hold the current strip until the way over is clear
        local hw = min(C.hw or 1, 1.3) * 0.9
        local function hole(x)
            for _, zz in ipairs({ C.cz - (C.hd or 1), C.cz, C.cz + 2, C.cz + 4, C.cz + 6 }) do
                local iv = G.floor_at(G.L, zz)
                if not (G.solid(iv, x - hw) and G.solid(iv, x + hw)) then return true end
            end
            return false
        end
        local a0, a1 = min(C.cx, tx), max(C.cx, tx)
        local blocked = false
        local x = a0
        while x <= a1 do if hole(x) then blocked = true; break end; x = x + 0.4 end
        if blocked and not hole(C.cx) then tx = C.cx end
        HB.tx = tx
    end
    -- keyboard-speed steering toward the planned line (10 m/s like A/D)
    local d = HB.tx - C.cxt
    C.cxt = C.cxt + clamp(d, -10 * dt, 10 * dt)
end
G.bot = nil   -- "greedy" / "bad" from tests

------------------------------------------------------------------ fixed simulation step
local function follow(dt, hwmax)
    C.layout(hwmax)
    for _, u in ipairs(C.units) do
        u.ox = damp(u.ox, u.tx, 7, dt); u.oz = damp(u.oz, u.tz, 7, dt)
    end
end
local function sim(dt)
    sim_dt = dt
    local L = G.L
    if G.shield_t and G.shield_t > 0 then G.shield_t = max(0, G.shield_t - dt) end
    local ph = RUN.phase
    if ph == "run" then
        if G.bot == "human" then human() elseif G.bot then bot(G.bot) end
        RUN.step(dt)
        if RUN.phase == "run" and C.cz >= L.len + 2 then
            if L.boss then RUN.phase = "boss"; music("boss") else FIN.stairs_start(L) end
        end
    elseif ph == "stairs" then
        follow(dt, 1.6); C.sync(); FIN.stairs_step(dt)
    elseif ph == "boss" then
        follow(dt, 3.6); C.sync(); FIN.boss_step(dt)
    elseif ph == "dead" or ph == "finished" then
        end_t = end_t + dt
        C.speed = damp(C.speed, 0, 4, dt)
        -- several fixed steps can run in one frame: only pay out once (G.state leaves "play" in finish)
        if end_t > (ph == "dead" and 1.4 or 0.9) and G.state == "play" then finish(ph == "finished") end
    end
end

------------------------------------------------------------------ camera
local function camera(dt)
    local st = G.state
    local p, l
    local blob = min(C.rmax or 1, 6)
    local cy = C.cy or 0
    if st == "title" or st == "levels" or st == "camp" then
        local a = G.t * 0.12
        -- low hero orbit: horizon and sky in frame, crowd large on one side
        p = vec3(LX(C.cx) + sin(a) * 11, 2.7 + blob * 0.2, C.cz + cos(a) * 11 - 2)
        l = vec3(LX(C.cx) - sin(a) * 2.5, 2.1, C.cz + 3)
        if st == "camp" then p = vec3(LX(C.cx) + 5, 3.2, C.cz + 8); l = vec3(LX(C.cx), 1.0, C.cz) end
    elseif RUN.phase == "stairs" then
        -- follow the column's front up the staircase on the smooth ramp (not C.cz/C.cy, which no longer jump)
        local fz, fy = C.cz, cy
        if FIN.s then fz, fy = FIN.focus() end
        p = vec3(LX(5.5), fy + 7.5, fz - 11); l = vec3(0, fy + 2.5, fz + 7)
    elseif RUN.phase == "boss" and FIN.b then
        local B = FIN.b
        if B.state == "fall" then p = vec3(LX(9), 7, B.z - 16); l = vec3(0, 3, B.z)
        else p = vec3(LX(C.cx * 0.3 + 3), 7.5 + blob * 0.15, C.cz - 12 - blob * 0.2); l = vec3(0, 3.2, B.z - 2) end
    else
        p = vec3(LX(C.cx * 0.35), 8 + blob * 0.12 + cy, C.cz - 11 - blob * 0.18)
        l = vec3(LX(C.cx * 0.5), 0.8 + cy, C.cz + 8)
        if st == "win" or st == "lose" then p = vec3(p.x + 3, p.y - 1.5, p.z + 4) end
    end
    if G.cam_dbg then p, l = G.cam_dbg[1], G.cam_dbg[2]; G.cam_reset = true end   -- dev inspection camera (MCP: CM.cam_dbg = {vec3, vec3})
    if G.cam_reset then G.cam_reset = false; CAM.p, CAM.l = p, l end
    local k = (st == "play") and 6 or 2.2
    CAM.p = vec3(damp(CAM.p.x, p.x, k, dt), damp(CAM.p.y, p.y, k, dt), damp(CAM.p.z, p.z, k * 1.6, dt))
    CAM.l = vec3(damp(CAM.l.x, l.x, k, dt), damp(CAM.l.y, l.y, k, dt), damp(CAM.l.z, l.z, k * 1.6, dt))
    -- shake + fov punch
    G.shk = max(0, G.shk - dt * 1.8)
    local s = G.shk * G.shk
    local sx, sy = (rand() - 0.5) * s * 1.2, (rand() - 0.5) * s * 0.8
    G.fovp_t = G.fovp_t + dt
    local pk = G.fovp_t < G.fovp_d and G.fovp * sin(PI * min(1, G.fovp_t / G.fovp_d * 1.0)) or 0
    local speedfov = (st == "play" and RUN.phase == "run") and clamp((C.speed - 8.5) * 0.6, -2, 3) or 0
    CAM.fov = damp(CAM.fov, 52 + speedfov, 3, dt)
    set_vfov(math.rad(CAM.fov + pk))
    G.cam.pos = vec3(CAM.p.x + sx, CAM.p.y + sy, CAM.p.z)
    G.cam.look = vec3(CAM.l.x + sx * 0.5, CAM.l.y + sy * 0.5, CAM.l.z)
    cam:set_position(G.cam.pos); cam:look_at(G.cam.look)
end

------------------------------------------------------------------ shield visuals
local sh_t = 0
local function shield_fx(dt)
    if (G.shield_t or 0) > 0 then
        sh_t = sh_t - dt
        if sh_t <= 0 then
            sh_t = 0.12
            local r = (C.hw or 1) + 0.6
            G.FX.ring(LX(C.cx), 0.15 + (C.cy or 0), C.cz, r * 2, { .3, .6, 1.2 }, true)
            G.FX.sparks(LX(C.cx + rr(-r, r)), 1 + rand(), C.cz + rr(-1, 1), 2, { 0, 1, 0 }, 2, { .5, .9, 1.6 })
        end
    end
end

------------------------------------------------------------------ frame
load_level(menu_level, true)
music("title")
local mx_last = nil
local frames = 0
local cam_done = false
local function update(dt)
    dt = min(dt or 0.016, 0.25)
    cam_done = false
    frames = frames + 1
    G.t = G.t + dt
    flush_mats()
    M.tick(dt)
    U.begin_frame()
    local st = G.state
    -- options overlay (settings_menu owns its own screen while open)
    if st == "options" then
        if not SET:update(dt) then G.state = G.opt_back or "title" end
        U.end_frame()
        C.animate(dt, "idle"); camera(dt); update_lights(dt)
        return
    end
    U.poll(st)
    if st == "play" then
        -- drag steering
        local MS = U.MS
        if MS.down and not U.inside(SW - 130 * US, 0, 130 * US, 130 * US) and not U.inside(SW - 180 * US, SH - 200 * US, 180 * US, 200 * US) then
            if mx_last then G.drag_dx = (G.drag_dx or 0) + (MS.x - mx_last) / SW * 14 end
            mx_last = MS.x
        else mx_last = nil end
        if U.K.ok or anyedge("Space") then G.use_shield() end
        -- semi-fixed step: split this frame's dt into n equal sub-steps of at most 1/60 s. The old loop ran whole 1/60 s
        -- steps and carried the remainder, with no interpolation, so at 75/120/144 Hz or with uneven frame times the crowd,
        -- traps and the camera target advanced 0, 1 or 2 steps per rendered frame (visible judder that TAA then smears).
        -- Now every rendered frame shows the world exactly dt further on. G.freeze (tests) holds the simulation.
        acc = G.freeze and 0 or min(acc + dt, 0.2)
        if acc > 0 then
            local n = math.ceil(acc / STEP - 1e-6)
            local h = acc / n
            for _ = 1, n do if G.state ~= "play" then break end; sim(h) end
            acc = 0
        end
        -- move the camera before the HUD projects its world labels (badge, gate numbers, step multipliers): projecting
        -- with last frame's camera made every label trail the 3D scene by one frame
        camera(dt); cam_done = true
        if G.state == "play" then
            local act = HUD.play(dt, G.L)
            if act == "pause" or U.K.back or U.K.pause then G.state = "pause"; sfx("click") end
        end
        local mode = (RUN.phase == "stairs" and FIN.s and FIN.s.done) and "cheer" or ((RUN.phase == "finished" or (FIN.b and FIN.b.state == "fall")) and "cheer" or "run")
        if RUN.phase == "boss" and FIN.b and FIN.b.state == "fight" then mode = "idle" end
        if RUN.phase == "dead" then mode = "idle" end
        C.animate(dt, mode)
        shield_fx(dt)
    elseif st == "pause" then
        local act = SCR.pause(dt)
        C.animate(0, "idle")
        if act == "resume" then G.state = "play"
        elseif act == "retry" then G.goto_level(G.L.idx)
        elseif act == "options" then G.opt_back = "pause"; G.state = "options"; SET:open()
        elseif act == "menu" then load_level(G.L.idx, true); go("title") end
    elseif st == "win" or st == "lose" then
        HUD.overlays(dt)
        local act = SCR.result(dt)
        C.animate(dt, st == "win" and "cheer" or "idle")
        if act == "next" then G.goto_level(G.L.idx >= #G.LEVELS and G.L.idx or G.L.idx + 1)
        elseif act == "retry" then G.goto_level(G.L.idx)
        elseif act == "camp" then load_level(min(M.D.unlocked, G.L.idx + (st == "win" and 1 or 0)), true); go("camp")
        elseif act == "menu" then load_level(G.L.idx, true); go("title") end
    else
        -- menus run the showcase crowd idling in the level
        C.animate(dt, "idle")
        local act
        if st == "title" then
            act = SCR.title(dt)
            if act == "play" then G.goto_level(M.D.unlocked)
            elseif act == "levels" then go("levels")
            elseif act == "camp" then go("camp")
            elseif act == "options" then G.opt_back = "title"; G.state = "options"; SET:open()
            elseif act == "quit" then M.save(); pcall(function() app.quit() end); pcall(function() engine.quit() end) end
        elseif st == "levels" then
            act = SCR.levels(dt)
            if act == "back" then go("title") elseif type(act) == "number" then G.goto_level(act) end
        elseif st == "camp" then
            act = SCR.camp(dt)
            if act == "back" then go("title") elseif act == "next" then G.goto_level(min(M.D.unlocked, (M.D.last or 1) + ((M.D.best[M.D.last or 1] and 1) or 0))) end
        end
        HUD.overlays(dt)
    end
    U.end_frame()
    if not cam_done then camera(dt) end
    update_lights(dt)
end
G.update = update; G.RUN, G.C, G.R = RUN, C, R
hooks { update = update }
pe_log("[CM] ready")
end
