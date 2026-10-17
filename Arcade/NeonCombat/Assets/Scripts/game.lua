-- NEON COMBAT : a modern remake of Atari 2600 COMBAT (tank battle) for PhasmaEngine
-- Procedural geometry cooked with PhasmaCook (tools/gen_meshes.py), emissive materials + bloom,
-- GPU particles, dynamic point lights, runtime_ui HUD. Assets-relative paths only.

local rand, floor, sqrt, abs, min, max = math.random, math.floor, math.sqrt, math.abs, math.min, math.max
local sin, cos, atan2, pi, rad, deg = math.sin, math.cos, math.atan2 or math.atan, math.pi, math.rad, math.deg

local AR = load(fs.read("Scripts/arenas.lua"), "@arenas.lua")()
local CELL, HWID, HDEP = AR.cell, AR.w, AR.d
local ROWS, COLS = 14, 24

------------------------------------------------------------------ helpers
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function lerp(a, b, t) return a + (b - a) * t end
local function wrapdeg(a) a = (a + 180) % 360; if a < 0 then a = a + 360 end; return a - 180 end
local function sfx(name, vol, pitch) pcall(audio.play, name .. ".wav") end
local function sfx3(name, x, z) pcall(audio.play_3d, name .. ".wav", x, 0.5, z) end
local function key(k) local ok, v = pcall(input.is_key_down_raw, k); return ok and v end
local VK = {}                       -- virtual keys (automation / tests)
local function down(k) return VK[k] or key(k) end
local prevk = {}
-- left mouse button (fire); VK.LMB lets automation click
local function lmb()
    if VK.LMB then return true end
    local ok, v = pcall(input.is_left_mouse_down)
    return ok and v or false
end
local function edge(k) local d = down(k); local was = prevk[k]; prevk[k] = d; return d and not was end
local EDGE_KEYS = { "Return", "Space", "Escape", "Up", "Down", "Left", "Right", "W", "S", "A", "D", "P", "M", "B", "Keypad Enter" }

local deferred = {}
local function later(frames, fn) deferred[#deferred + 1] = { f = frames, fn = fn } end
local function paint(n, slot, base, emi, rough, metal)
    if slot then
        if base then material.set(n, slot, "base_color", vec4(base[1], base[2], base[3], base[4] or 1)) end
        if emi then material.set(n, slot, "emissive", vec3(emi[1], emi[2], emi[3])) end
        if rough then material.set(n, slot, "roughness", rough) end
        if metal then material.set(n, slot, "metallic", metal) end
    else
        if base then material.set(n, "base_color", vec4(base[1], base[2], base[3], base[4] or 1)) end
        if emi then material.set(n, "emissive", vec3(emi[1], emi[2], emi[3])) end
        if rough then material.set(n, "roughness", rough) end
        if metal then material.set(n, "metallic", metal) end
    end
end
local function emis(n, r, g, b) material.set(n, "emissive", vec3(r, g, b)) end
local VISP
local function place(n, x, y, z, ry, sx, sy, sz, rx, rz)
    VISP(n)
    n:set_transform(vec3(x, y, z), vec3(rx or 0, ry or 0, rz or 0), vec3(sx or 1, sy or sx or 1, sz or sx or 1))
end
local function show(n, on) n:set_enabled(on) end
local VIS = setmetatable({}, { __mode = "k" })
local function hide_far(n) if VIS[n] ~= false then n:set_enabled(false); VIS[n] = false end end
local function unhide(n) if VIS[n] ~= true then n:set_enabled(true); VIS[n] = true end end
VISP = unhide

------------------------------------------------------------------ state
local TEAM = {
    { name = "GREEN",   col = { 0.25, 1.0, 0.45 }, body = { 0.30, 0.55, 0.32 } },
    { name = "MAGENTA", col = { 1.0, 0.22, 0.62 }, body = { 0.58, 0.22, 0.40 } },
}
local ARENA_STYLE = {
    classic = { glow = { 0.05, 0.6, 1.4 },  grid = { 0.02, 0.10, 0.22 }, label = "CLASSIC" },
    maze    = { glow = { 0.9, 0.25, 1.8 },  grid = { 0.10, 0.03, 0.20 }, label = "LABYRINTH" },
    pillars = { glow = { 1.8, 0.75, 0.15 }, grid = { 0.18, 0.08, 0.02 }, label = "PILLARS" },
}
local S = {
    mode = "boot", t = 0, frame = 0, players = 1, arena = 1, bounce = true, target = 10, ai_level = 2,
    menu_i = 1, shake = 0, paused = false, flash = 0, banner = nil, banner_t = 0, countdown = 0, winner = nil,
}
local tanks, shells = {}, {}
local walls = {}       -- active arena AABBs {x,z,hx,hz}
local grid = {}        -- walkable[r][c]
local N = {}           -- scene nodes
local L = {}           -- light indices
local SET = nil        -- settings menu

------------------------------------------------------------------ HUD
local hud_ids = {}
local function surface()
    local ok, s = pcall(runtime_ui.get_surface_size)
    if ok and s and (s.w or s.width) then return (s.w or s.width), (s.h or s.height) end
    return 1280, 720
end
local function txt(id, x, y, w, h, text, scale, col, align, z)
    hud_ids[id] = true
    runtime_ui.set_quad("hud", id, {
        x = x, y = y, w = w, h = h, z = z or 5, style = "text", label = text, body = text,
        fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 }, text_color = col or { 1, 1, 1, 1 },
        font_scale = scale or 1.0, align_h = align or "center", align_v = "middle", no_input = true, visible = true,
    })
end
local function panel(id, x, y, w, h, fill, border, z, radius)
    hud_ids[id] = true
    runtime_ui.set_quad("hud", id, {
        x = x, y = y, w = w, h = h, z = z or 1, style = "text", label = "",
        fill = fill, border = border or { 0, 0, 0, 0 }, corner_radius = radius or 10, no_input = true, visible = true,
    })
end
-- transparent mouse target for menu rows; returns its state (hover selects after the mouse moves, click activates)
local hit_mxy = nil
local function hit(id, x, y, w, h)
    hud_ids[id] = true
    runtime_ui.set_quad("hud", id, { x = x, y = y, w = w, h = h, z = 40, style = "text", label = "",
        fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 }, visible = true })
    local ok, st = pcall(runtime_ui.get_state, "hud", id)
    if not (ok and st) then return nil, false end
    local moved = st.mouse_x and hit_mxy and (math.abs(st.mouse_x - hit_mxy[1]) + math.abs(st.mouse_y - hit_mxy[2]) > 2)
    if st.mouse_x then hit_mxy = { st.mouse_x, st.mouse_y } end
    return st, st.hovered and moved
end
local function hud_hide(prefix)
    for id, _ in pairs(hud_ids) do
        if id:sub(1, #prefix) == prefix then runtime_ui.set_quad("hud", id, { visible = false, w = 0, h = 0 }); hud_ids[id] = nil end
    end
end

------------------------------------------------------------------ world
local function wall_at(x, z, r)
    r = r or 0
    for i = 1, #walls do
        local b = walls[i]
        if abs(x - b[1]) < b[3] + r and abs(z - b[2]) < b[4] + r then return b end
    end
    return nil
end
local function cell_of(x, z) return floor(z / CELL + ROWS / 2) + 1, floor(x / CELL + COLS / 2) + 1 end   -- row, col (1-based)
local function cell_center(r, c) return (c - 1 - (COLS - 1) / 2) * CELL, (r - 1 - (ROWS - 1) / 2) * CELL end
local function free(r, c) return grid[r] and grid[r][c] end

local function find_spawn(c0, r0)
    for d = 0, 8 do
        for dr = -d, d do for dc = -d, d do
            local r, c = r0 + dr, c0 + dc
            if free(r, c) and free(r, c + 1) and free(r, c - 1) and free(r + 1, c) and free(r - 1, c) then return cell_center(r, c) end
        end end
    end
    return cell_center(r0, c0)
end

local function set_arena(i)
    S.arena = i
    local a = AR.arenas[i]
    walls = a.boxes
    grid = {}
    for r = 1, ROWS do
        grid[r] = {}
        local row = a.rows[r]
        for c = 1, COLS do grid[r][c] = row:sub(c, c) ~= "#" end
    end
    for k, ar in ipairs(AR.arenas) do
        local n = N["arena_" .. ar.name]
        if k == i then place(n, 0, 0, 0) else hide_far(n) end
        show(n, k == i)
    end
    local st = ARENA_STYLE[a.name]
    local n = N["arena_" .. a.name]
    paint(n, 0, { 0.30, 0.32, 0.40 }, { 0, 0, 0 }, 0.55, 0.15)
    paint(n, 1, { 0.45, 0.48, 0.58 }, { st.glow[1] * 0.04, st.glow[2] * 0.04, st.glow[3] * 0.04 }, 0.3, 0.8)
    paint(n, 2, { 1, 1, 1 }, st.glow, 0.2, 0)
    paint(n, 3, { 0.03, 0.03, 0.04 }, { st.glow[1] * 0.25, st.glow[2] * 0.25, st.glow[3] * 0.25 }, 0.6, 0.3)
    paint(N.floor, 0, { 0.13, 0.14, 0.18 }, nil, 0.35, 0.4)
    paint(N.floor, 1, { 0.17, 0.18, 0.23 }, nil, 0.35, 0.4)
    paint(N.floor, 2, { 0.25, 0.27, 0.33 }, { st.glow[1] * 0.03, st.glow[2] * 0.03, st.glow[3] * 0.03 }, 0.3, 0.6)
    paint(N.floor, 4, { 0.03, 0.03, 0.04 }, nil, 0.8, 0)
    paint(N.floor, 3, { 0, 0, 0 }, st.grid, 0.5, 0)
    paint(N.floor, 5, { 1, 1, 1 }, { st.glow[1] * 0.8, st.glow[2] * 0.8, st.glow[3] * 0.8 }, 0.2, 0)
    S.arena_glow = st.glow
end

------------------------------------------------------------------ pools of fx nodes
local FX = { fire = {}, ring = {}, scorch = {}, debris = {}, flash = {}, trail = {}, cone = {} }
local function mkprim(kind, a, b, c, d)
    local n
    if kind == "sphere" then n = primitives.uv_sphere(a or 1, b or 20, c or 14)
    elseif kind == "torus" then n = primitives.torus(a or 1, b or 0.05, c or 48, d or 8)
    elseif kind == "cyl" then n = primitives.cylinder(a or 1, b or 1)
    elseif kind == "cone" then n = primitives.cone(a or 1, b or 1)
    else n = primitives.cube(a or 1) end
    hide_far(n)
    return n
end

local function build_fx_pools()
    for i = 1, 10 do
        FX.fire[i] = { n = mkprim("sphere", 1, 24, 16), h = mkprim("sphere", 1, 20, 12), t = -1 }
        FX.ring[i] = { n = mkprim("torus", 1, 0.06, 64, 8), t = -1 }
    end
    for i = 1, 16 do FX.scorch[i] = { n = mkprim("cyl", 1, 0.02), t = -1 } end
    for i = 1, 6 do FX.flash[i] = { n = mkprim("sphere", 1, 16, 10), c = mkprim("cone", 1, 1), t = -1 } end
    for k = 1, 2 do
        FX.trail[k] = {}
        for j = 1, 10 do FX.trail[k][j] = mkprim("cube", 1) end
    end
    -- debris: instances of the cooked debris meshes
    for i = 1, 36 do
        local src = N["debris" .. ((i - 1) % 3)]
        local n = scene.add_empty_node("Debris_" .. i)
        local ok, mi = pcall(function() return src:get_mesh_index() end)
        if ok and mi and mi >= 0 then n:add_mesh_ref(mi) end
        hide_far(n)
        FX.debris[i] = { n = n, t = -1 }
    end
    later(2, function()
        for i = 1, 10 do
            pcall(material.set_render_type, FX.fire[i].h, "alpha_blend")
            pcall(material.set_render_type, FX.fire[i].n, "alpha_blend")
            paint(FX.fire[i].n, nil, { 1, 0.8, 0.5 }, { 3, 1.5, 0.4 }, 0.5, 0)
            paint(FX.fire[i].h, nil, { 1, 0.4, 0.1, 0.3 }, { 1, 0.4, 0.1 }, 0.5, 0)
            paint(FX.ring[i].n, nil, { 1, 1, 1 }, { 2, 1.2, 0.5 }, 0.5, 0)
        end
        for i = 1, 16 do
            pcall(material.set_render_type, FX.scorch[i].n, "alpha_blend")
            paint(FX.scorch[i].n, nil, { 0.01, 0.01, 0.01, 0.0 }, { 0, 0, 0 }, 1.0, 0)
        end
        for i = 1, 6 do
            pcall(material.set_render_type, FX.flash[i].c, "alpha_blend")
            paint(FX.flash[i].n, nil, { 1, 1, 1 }, { 6, 4.5, 2 }, 0.5, 0)
            paint(FX.flash[i].c, nil, { 1, 0.8, 0.4, 0.6 }, { 4, 2.5, 0.8 }, 0.5, 0)
        end
        for k = 1, 2 do
            local c = TEAM[k].col
            for j = 1, 10 do
                local f = (1 - (j - 1) / 10)
                paint(FX.trail[k][j], nil, { 0, 0, 0 }, { c[1] * 3 * f, c[2] * 3 * f, c[3] * 3 * f }, 0.5, 0)
            end
        end
        paint(N.debris0, 0, { 0.12, 0.12, 0.14 }, { 0.6, 0.18, 0.03 }, 0.6, 0.6)
    end)
end

local function take(list) for i = 1, #list do if list[i].t < 0 then return list[i] end end return list[1] end

------------------------------------------------------------------ lights
local NL = 0
local function build_lights()
    local before = #(lights.get_point_lights() or {})
    local want = 14
    for i = 1, want do lights.add_point() end
    for i = 1, want do L[i] = before + i - 1; lights.set_point_light(L[i], vec3(0, -50, 0), vec3(1, 1, 1), 0, 1) end
    NL = want
    -- 1,2 tank underglow / 3,4 shell / 5..10 flashes / 11..14 arena corners
end
local flashes = {}
local fl_rr = 0
local function flash_light(x, y, z, r, g, b, inten, radius, life)
    fl_rr = fl_rr % 6 + 1
    flashes[fl_rr] = { x = x, y = y, z = z, r = r, g = g, b = b, i = inten, rad = radius, t = 0, life = life }
end
local function update_lights(dt)
    for i = 1, 6 do
        local F = flashes[i]
        if F then
            F.t = F.t + dt
            local f = 1 - F.t / F.life
            if f <= 0 then flashes[i] = nil; lights.set_point_light(L[4 + i], vec3(0, -50, 0), vec3(1, 1, 1), 0, 1)
            else lights.set_point_light(L[4 + i], vec3(F.x, F.y, F.z), vec3(F.r, F.g, F.b), F.i * f * f, F.rad) end
        end
    end
    local g = S.arena_glow or { 0.2, 0.7, 1.5 }
    local corners = { { -HWID + 2, -HDEP + 2 }, { HWID - 2, -HDEP + 2 }, { -HWID + 2, HDEP - 2 }, { HWID - 2, HDEP - 2 } }
    for i = 1, 4 do
        local p = 0.8 + 0.2 * sin(S.t * 1.7 + i * 1.3)
        lights.set_point_light(L[10 + i], vec3(corners[i][1], 2.5, corners[i][2]), vec3(g[1] / 1.8, g[2] / 1.8, g[3] / 1.8), 10 * p, 9)
    end
end

------------------------------------------------------------------ particles
local function pscale() return SET and SET:particle_scale() or 1.0 end
local function burst(t)
    t.count = max(1, floor((t.count or 30) * pscale()))
    t.cleanup_delay = t.cleanup_delay or 3
    pcall(particles.emit_burst, t)
end
local function sparks(x, y, z, r, g, b, count, speed, life)
    burst({ position = vec3(x, y, z), velocity = vec3(0, 1.5, 0),
        color_start = vec4(r, g, b, 1), color_end = vec4(r * 0.4, g * 0.2, b * 0.1, 0),
        count = count or 40, size_min = 0.03, size_max = 0.09, life_min = (life or 0.6) * 0.4, life_max = life or 0.6,
        spawn_radius = 0.1, noise_strength = speed or 7, drag = 2.2, gravity = vec3(0, -9, 0) })
end
local function smoke(x, y, z, count, size, life, dark)
    local c = dark and 0.06 or 0.35
    burst({ position = vec3(x, y, z), velocity = vec3(0, 1.2, 0),
        color_start = vec4(c * 1.2, c, c * 1.1, 0.55), color_end = vec4(c * 0.3, c * 0.3, c * 0.35, 0),
        count = count or 30, size_min = (size or 0.4) * 0.5, size_max = size or 0.4, life_min = (life or 1.6) * 0.5, life_max = life or 1.6,
        spawn_radius = 0.35, noise_strength = 0.9, drag = 0.8, gravity = vec3(0, 0.8, 0) })
end
local function fireburst(x, y, z, count)
    burst({ position = vec3(x, y, z), velocity = vec3(0, 2.0, 0),
        color_start = vec4(1.0, 0.75, 0.3, 1), color_end = vec4(0.8, 0.12, 0.02, 0),
        count = count or 80, size_min = 0.15, size_max = 0.45, life_min = 0.25, life_max = 0.7,
        spawn_radius = 0.4, noise_strength = 5, drag = 2.5, gravity = vec3(0, 2, 0) })
end
local function dust(x, z, count, col)
    burst({ position = vec3(x, 0.08, z), velocity = vec3(0, 0.5, 0),
        color_start = vec4(col and col[1] or 0.3, col and col[2] or 0.32, col and col[3] or 0.4, 0.35), color_end = vec4(0.1, 0.1, 0.14, 0),
        count = count or 4, size_min = 0.12, size_max = 0.3, life_min = 0.5, life_max = 1.1,
        spawn_radius = 0.15, noise_strength = 0.7, drag = 1.5, gravity = vec3(0, 0.25, 0) })
end

------------------------------------------------------------------ fx spawners
local function spawn_fire(x, y, z, size, hot)
    local f = take(FX.fire); f.t = 0; f.x, f.y, f.z, f.size, f.hot = x, y, z, size, hot or 1
    local r = take(FX.ring); r.t = 0; r.x, r.z, r.size = x, z, size * 2.2
end
local function spawn_scorch(x, z, size)
    local s = take(FX.scorch); s.t = 0; s.x, s.z, s.size = x, z, size
    s.rot = rand() * 360
end
local function spawn_debris(x, z, count, vx, vz)
    for i = 1, count do
        local d = take(FX.debris)
        local a = rand() * pi * 2; local sp = 2 + rand() * 6
        d.t = 0; d.x, d.y, d.z = x, 0.5, z
        d.vx, d.vy, d.vz = cos(a) * sp + (vx or 0) * 0.3, 4 + rand() * 6, sin(a) * sp + (vz or 0) * 0.3
        d.rx, d.ry, d.rz = rand() * 360, rand() * 360, rand() * 360
        d.wx, d.wy, d.wz = (rand() - 0.5) * 900, (rand() - 0.5) * 900, (rand() - 0.5) * 900
        d.s = 0.8 + rand() * 1.6; d.life = 2.5 + rand() * 1.5; d.smoke = rand() < 0.5
    end
end
local function muzzle_flash(x, y, z, yaw, col)
    local f = take(FX.flash); f.t = 0; f.x, f.y, f.z, f.yaw = x, y, z, yaw
    flash_light(x, y + 0.4, z, 1.0, 0.75, 0.4, 35, 7, 0.22)
    local fx, fz = cos(rad(yaw)), -sin(rad(yaw))
    burst({ position = vec3(x, y, z), velocity = vec3(fx * 6, 0.3, fz * 6),
        color_start = vec4(1, 0.85, 0.5, 1), color_end = vec4(1, 0.3, 0.05, 0),
        count = 45, size_min = 0.04, size_max = 0.12, life_min = 0.1, life_max = 0.3,
        spawn_radius = 0.05, noise_strength = 3.5, drag = 3, gravity = vec3(0, 0, 0) })
    burst({ position = vec3(x + fx * 0.2, y, z + fz * 0.2), velocity = vec3(fx * 1.6, 0.6, fz * 1.6),
        color_start = vec4(0.5, 0.48, 0.5, 0.5), color_end = vec4(0.15, 0.15, 0.18, 0),
        count = 26, size_min = 0.2, size_max = 0.45, life_min = 0.6, life_max = 1.4,
        spawn_radius = 0.15, noise_strength = 0.8, drag = 1.8, gravity = vec3(0, 0.6, 0) })
end
local function explosion(x, z, big, vx, vz)
    local s = big and 1.6 or 0.6
    spawn_fire(x, 0.6, z, s, big and 1.4 or 1)
    fireburst(x, 0.6, z, big and 140 or 40)
    sparks(x, 0.6, z, 1, 0.7, 0.3, big and 140 or 50, big and 11 or 7, big and 1.2 or 0.6)
    smoke(x, 0.8, z, big and 70 or 18, big and 0.9 or 0.45, big and 3.2 or 1.4, big)
    flash_light(x, 1.2, z, 1.0, 0.55, 0.2, big and 120 or 40, big and 14 or 6, big and 0.9 or 0.35)
    if big then
        spawn_debris(x, z, 14, vx, vz)
        spawn_scorch(x, z, 1.4)
        S.shake = max(S.shake, 0.9)
        S.flash = max(S.flash, 0.5)
        sfx("explode")
    else
        spawn_scorch(x, z, 0.45)
        S.shake = max(S.shake, 0.18)
    end
end

local function update_fx(dt)
    for _, f in ipairs(FX.fire) do
        if f.t >= 0 then
            f.t = f.t + dt
            local life = 0.75 * f.hot
            local k = f.t / life
            if k >= 1 then f.t = -1; hide_far(f.n); hide_far(f.h)
            else
                local r = f.size * (0.35 + 0.9 * (1 - (1 - k) ^ 3))
                place(f.n, f.x, f.y + k * 0.8, f.z, f.t * 60, r * (1 - k * 0.6))
                local hot = (1 - k) ^ 1.5
                material.set(f.n, "base_color", vec4(1, 0.7 * hot + 0.2, 0.3 * hot, 0.9 * (1 - k) ^ 0.7))
                emis(f.n, 6 * hot + 0.4, 2.6 * hot + 0.08, 0.7 * hot)
                place(f.h, f.x, f.y + k * 1.0, f.z, -f.t * 40, r * 1.3)
                material.set(f.h, "base_color", vec4(1, 0.55 + 0.3 * hot, 0.25, 0.22 * (1 - k) ^ 2))
                emis(f.h, 2.4 * hot, 1.0 * hot, 0.25 * hot)
            end
        end
    end
    for _, r in ipairs(FX.ring) do
        if r.t >= 0 then
            r.t = r.t + dt
            local k = r.t / 0.55
            if k >= 1 then r.t = -1; hide_far(r.n)
            else
                local s = r.size * (0.2 + (1 - (1 - k) ^ 2))
                place(r.n, r.x, 0.12, r.z, 0, s, 0.4, s)
                local f = (1 - k) ^ 2
                emis(r.n, 3 * f, 1.8 * f, 0.7 * f)
            end
        end
    end
    for _, s in ipairs(FX.scorch) do
        if s.t >= 0 then
            s.t = s.t + dt
            local k = s.t / 14
            if k >= 1 then s.t = -1; hide_far(s.n)
            else
                place(s.n, s.x, 0.012, s.z, s.rot, s.size, 1, s.size)
                local a = 0.75 * min(1, s.t * 6) * (1 - k)
                local glow = max(0, 1 - s.t * 0.8)
                material.set(s.n, "base_color", vec4(0.01, 0.01, 0.01, a))
                emis(s.n, 0.8 * glow, 0.18 * glow, 0.02 * glow)
            end
        end
    end
    for _, f in ipairs(FX.flash) do
        if f.t >= 0 then
            f.t = f.t + dt
            local k = f.t / 0.09
            if k >= 1 then f.t = -1; hide_far(f.n); hide_far(f.c)
            else
                local fx, fz = cos(rad(f.yaw)), -sin(rad(f.yaw))
                local s = 0.35 * (1 - k * 0.5)
                place(f.n, f.x, f.y, f.z, 0, s)
                -- cone points along +Y by default: tip it forward along the barrel
                place(f.c, f.x + fx * 0.35, f.y, f.z + fz * 0.35, f.yaw, 0.22 * (1 - k * 0.3), 0.8 * (1 + k), 0.22 * (1 - k * 0.3), 0, -90)
            end
        end
    end
    for _, d in ipairs(FX.debris) do
        if d.t >= 0 then
            d.t = d.t + dt
            if d.t > d.life then d.t = -1; hide_far(d.n)
            else
                d.vy = d.vy - 22 * dt
                local nx, nz = d.x + d.vx * dt, d.z + d.vz * dt
                if wall_at(nx, d.z, 0.05) and d.y < 1.1 then d.vx = -d.vx * 0.5; nx = d.x end
                if wall_at(d.x, nz, 0.05) and d.y < 1.1 then d.vz = -d.vz * 0.5; nz = d.z end
                d.x, d.z = nx, nz
                d.y = d.y + d.vy * dt
                if d.y < 0.06 then
                    d.y = 0.06
                    if d.vy < -2 then sparks(d.x, 0.1, d.z, 1, 0.5, 0.2, 5, 2, 0.3) end
                    d.vy = -d.vy * 0.35; d.vx = d.vx * 0.6; d.vz = d.vz * 0.6
                    d.wx, d.wy, d.wz = d.wx * 0.6, d.wy * 0.6, d.wz * 0.6
                end
                d.rx, d.ry, d.rz = d.rx + d.wx * dt, d.ry + d.wy * dt, d.rz + d.wz * dt
                local sh = d.s * min(1, (d.life - d.t) * 2)
                place(d.n, d.x, d.y, d.z, d.ry, sh, sh, sh, d.rx, d.rz)
                if d.smoke and rand() < dt * 14 and d.t < 1.6 then smoke(d.x, d.y, d.z, 2, 0.25, 0.8, true) end
            end
        end
    end
end

------------------------------------------------------------------ tanks
local TANK_R = 0.64
local TS = 1.32          -- tank model scale
local function new_tank(i)
    local t = { i = i, n = N["tank" .. i], x = 0, z = 0, yaw = 0, v = 0, w = 0, cd = 0, score = 0,
        spin = 0, kx = 0, kz = 0, recoil = 0, dust_t = 0, inv = 0, ai = false, ai_state = {}, hit_flash = 0, bob = 0 }
    return t
end
local function tank_spawn(t)
    local a = AR.arenas[S.arena]
    local x, z
    if t.i == 1 then x, z = find_spawn(3, 7); t.yaw = 0 else x, z = find_spawn(22, 8); t.yaw = 180 end
    t.x, t.z, t.v, t.w, t.spin, t.kx, t.kz, t.cd, t.recoil = x, z, 0, 0, 0, 0, 0, 0.6, 0
end
local function tank_paint(t)
    local c, b = TEAM[t.i].col, TEAM[t.i].body
    local hf = floor(t.hit_flash * 20) / 20
    local g0 = (t.spin > 0) and (floor(S.t * 16) % 2) or 2
    local keyv = hf * 10 + g0
    if t.pkey == keyv and S.frame > 5 then return end
    t.pkey = keyv
    paint(t.n, 0, { b[1] + hf, b[2] + hf * 0.6, b[3] + hf * 0.3 }, { c[1] * 0.02 + hf * 2, c[2] * 0.02 + hf, c[3] * 0.02 + hf * 0.3 }, 0.38, 0.55)
    paint(t.n, 1, { 0.03, 0.03, 0.035 }, nil, 0.8, 0.2)
    paint(t.n, 2, { 0.07, 0.07, 0.07 }, nil, 0.9, 0.4)
    paint(t.n, 3, { 0.38, 0.39, 0.42 }, nil, 0.25, 0.95)
    local g = (t.spin > 0) and (0.3 + 0.7 * (floor(S.t * 16) % 2)) or 1
    paint(t.n, 4, { c[1], c[2], c[3] }, { c[1] * 3.2 * g, c[2] * 3.2 * g, c[3] * 3.2 * g }, 0.3, 0)
    paint(t.n, 5, { 1, 1, 0.9 }, { 5, 5, 4 }, 0.3, 0)
    paint(t.n, 6, { 1, 0.1, 0.05 }, { 4, 0.3, 0.1 }, 0.3, 0)
end

local function collide_tank(t)
    for _ = 1, 2 do
        for i = 1, #walls do
            local b = walls[i]
            local cx = clamp(t.x, b[1] - b[3], b[1] + b[3])
            local cz = clamp(t.z, b[2] - b[4], b[2] + b[4])
            local dx, dz = t.x - cx, t.z - cz
            local d2 = dx * dx + dz * dz
            if d2 < TANK_R * TANK_R then
                local d = sqrt(d2)
                if d < 1e-4 then dx, dz, d = 0, 1, 1 end
                local push = TANK_R - d
                t.x, t.z = t.x + dx / d * push, t.z + dz / d * push
                t.hitwall = true
            end
        end
    end
    t.x = clamp(t.x, -HWID + CELL + TANK_R, HWID - CELL - TANK_R)
    t.z = clamp(t.z, -HDEP + CELL + TANK_R, HDEP - CELL - TANK_R)
end

local function fire(t)
    if t.cd > 0 or t.spin > 0 or S.mode ~= "play" then return end
    local sh = shells[t.i]
    if sh.alive then return end
    local fx, fz = cos(rad(t.yaw)), -sin(rad(t.yaw))
    local mx, mz = t.x + fx * 1.12 * TS, t.z + fz * 1.12 * TS
    sh.alive, sh.x, sh.z, sh.vx, sh.vz, sh.life, sh.bounces = true, mx, mz, fx * 17, fz * 17, 2.6, 0
    sh.hist = {}
    for j = 1, 10 do sh.hist[j] = { mx, mz } end
    -- shell spawned inside a wall (barrel poking through): detonate right away
    if wall_at(mx, mz, 0.05) then sh.x, sh.z = t.x + fx * 0.6, t.z + fz * 0.6 end
    t.cd = 0.45; t.recoil = 1
    t.v = t.v - 1.4
    muzzle_flash(mx, 0.56 * TS, mz, t.yaw, TEAM[t.i].col)
    S.shake = max(S.shake, 0.12)
    sfx("fire")
end

local function hit_tank(t, by, vx, vz)
    if t.spin > 0 or t.inv > 0 then return end
    t.spin = 1.4; t.inv = 2.0; t.hit_flash = 1
    local sp = sqrt(vx * vx + vz * vz) + 1e-5
    t.kx, t.kz = vx / sp * 7, vz / sp * 7
    tanks[by].score = tanks[by].score + 1
    explosion(t.x, t.z, true, vx, vz)
    S.banner = (by == t.i) and "SELF HIT!" or (TEAM[by].name .. " SCORES")
    S.banner_t = 1.4; S.banner_col = TEAM[by].col
    if tanks[by].score >= S.target then
        S.mode = "win"; S.winner = by; S.win_t = 0; S.banner_t = 0; sfx("win")
    end
end

------------------------------------------------------------------ AI
local function los(x1, z1, x2, z2)
    local dx, dz = x2 - x1, z2 - z1
    local d = sqrt(dx * dx + dz * dz)
    local n = max(1, floor(d / 0.3))
    for k = 1, n - 1 do
        local u = k / n
        if wall_at(x1 + dx * u, z1 + dz * u, 0.08) then return false end
    end
    return true
end
-- predict a shell fired now along `yaw`; returns true if it passes near (tx,tz)
local function predict_hit(x, z, yaw, tx, tz, bounce)
    local fx, fz = cos(rad(yaw)), -sin(rad(yaw))
    local px, pz = x + fx * 1.2, z + fz * 1.2
    local vx, vz = fx, fz
    local bounces = 0
    for step = 1, 140 do
        local nx, nz = px + vx * 0.3, pz + vz * 0.3
        if wall_at(nx, nz, 0.08) then
            if not bounce or bounces >= 3 then return false end
            if wall_at(nx, pz, 0.08) then vx = -vx end
            if wall_at(px, nz, 0.08) then vz = -vz end
            bounces = bounces + 1
        else px, pz = nx, nz end
        local dx, dz = px - tx, pz - tz
        if dx * dx + dz * dz < 0.55 * 0.55 then return true end
    end
    return false
end
local dist_field, dist_t = nil, 0
local function build_field(tr, tc)
    local D = {}
    for r = 1, ROWS do D[r] = {} end
    local q, h = { { tr, tc } }, 1
    if not free(tr, tc) then return D end
    D[tr][tc] = 0
    while h <= #q do
        local r, c = q[h][1], q[h][2]; h = h + 1
        for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local rr, cc = r + o[1], c + o[2]
            if free(rr, cc) and D[rr][cc] == nil then D[rr][cc] = D[r][c] + 1; q[#q + 1] = { rr, cc } end
        end
    end
    return D
end
local AI_LV = { { aim = 9, react = 0.55, turn = 0.65 }, { aim = 4, react = 0.3, turn = 0.85 }, { aim = 1.5, react = 0.12, turn = 1.0 } }
local function ai_control(t, foe, dt)
    local A = t.ai_state
    local lv = AI_LV[S.ai_level]
    A.think = (A.think or 0) - dt
    A.ft = (A.ft or 0) - dt
    if A.ft <= 0 or not A.field then
        local r, c = cell_of(foe.x, foe.z); A.field = build_field(r, c); A.ft = 0.4
    end
    local dist_field = A.field
    local dx, dz = foe.x - t.x, foe.z - t.z
    local dist = sqrt(dx * dx + dz * dz)
    local want = deg(atan2(-dz, dx))
    local seen = los(t.x, t.z, foe.x, foe.z)
    local thrust, turn = 0, 0
    local goal_yaw
    if seen and dist < 13 then
        goal_yaw = want + (A.err or 0)
        thrust = dist > 6 and 0.6 or (dist < 3.5 and -0.5 or 0)
    else
        -- follow the distance field downhill
        local r, c = cell_of(t.x, t.z)
        local best, br, bc = (dist_field[r] and dist_field[r][c]) or 999, nil, nil
        for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local rr, cc = r + o[1], c + o[2]
            local v = dist_field[rr] and dist_field[rr][cc]
            if v and v < best then best, br, bc = v, rr, cc end
        end
        if br then
            local wx, wz = cell_center(br, bc)
            goal_yaw = deg(atan2(-(wz - t.z), wx - t.x))
        else goal_yaw = want end
        thrust = 1
    end
    -- bank shots: periodically scan a fan of headings
    if A.think <= 0 then
        A.think = lv.react
        A.err = (rand() - 0.5) * 2 * lv.aim
        A.shoot = false
        if seen and abs(wrapdeg(want - t.yaw)) < 6 + lv.aim and dist < 22 then A.shoot = true end
        if A.bank and predict_hit(t.x, t.z, t.yaw, foe.x, foe.z, true) then A.shoot = true end
        A.bank_t = (A.bank_t or 0) - lv.react
        if A.bank_t <= 0 then A.bank = nil end
        if S.bounce and not A.shoot and not A.bank and dist < 20 then
            for k = -6, 6 do
                local y = t.yaw + k * 5
                if predict_hit(t.x, t.z, y, foe.x, foe.z, true) then A.bank = y; A.bank_t = 1.2; break end
            end

        end
        -- unstick
        if abs(t.v) < 0.4 and thrust ~= 0 then A.stuck = (A.stuck or 0) + lv.react else A.stuck = 0 end
        if (A.stuck or 0) > 1.0 then A.reverse = 0.6; A.stuck = 0; A.rev_turn = rand() < 0.5 and -1 or 1 end
    end
    if A.bank then goal_yaw = A.bank; thrust = 0.1 end
    if A.shoot then A.bank = nil end
    if A.reverse and A.reverse > 0 then
        A.reverse = A.reverse - dt
        return -1, A.rev_turn, false
    end
    local diff = wrapdeg(goal_yaw - t.yaw)
    turn = -clamp(diff / 25, -1, 1) * lv.turn
    if abs(diff) > 55 then thrust = thrust * 0.15 end
    local shoot = A.shoot and abs(wrapdeg(want - t.yaw)) < 25 or (A.shoot and S.bounce)
    if shoot then A.shoot = false end
    return thrust, turn, shoot
end

------------------------------------------------------------------ tank update
local MAXV, MAXREV, ACC, MAXW = 5.6, 3.4, 16, 160
local function update_tank(t, dt, thrust, turn, shoot)
    t.cd = max(0, t.cd - dt); t.inv = max(0, t.inv - dt); t.hit_flash = max(0, t.hit_flash - dt * 2.5)
    t.recoil = max(0, t.recoil - dt * 5)
    if t.spin > 0 then
        t.spin = t.spin - dt
        t.yaw = t.yaw + 720 * dt * (t.spin / 1.4 + 0.2)
        t.x, t.z = t.x + t.kx * dt, t.z + t.kz * dt
        t.kx, t.kz = t.kx * (1 - 3 * dt), t.kz * (1 - 3 * dt)
        t.v, t.w = 0, 0
        if rand() < dt * 25 then smoke(t.x, 0.7, t.z, 3, 0.5, 1.4, true) end
        if rand() < dt * 12 then sparks(t.x, 0.6, t.z, 1, 0.6, 0.2, 8, 4, 0.5) end
    else
        local tv = thrust > 0 and thrust * MAXV or thrust * MAXREV
        local a = (abs(tv) > abs(t.v) and ACC or ACC * 1.4) * dt
        if t.v < tv then t.v = min(tv, t.v + a) else t.v = max(tv, t.v - a) end
        local tw = turn * MAXW
        local wa = 900 * dt
        if t.w < tw then t.w = min(tw, t.w + wa) else t.w = max(tw, t.w - wa) end
        t.yaw = t.yaw - t.w * dt     -- right = clockwise when seen from above
        local fx, fz = cos(rad(t.yaw)), -sin(rad(t.yaw))
        t.x, t.z = t.x + fx * t.v * dt, t.z + fz * t.v * dt
        if shoot then fire(t) end
    end
    t.hitwall = false
    collide_tank(t)
    if t.hitwall and abs(t.v) > 3 then sparks(t.x + cos(rad(t.yaw)) * 0.6, 0.3, t.z - sin(rad(t.yaw)) * 0.6, 0.8, 0.8, 1, 6, 3, 0.3); t.v = t.v * 0.7 end
    -- dust from tracks + exhaust
    local moving = abs(t.v) + abs(t.w) * 0.02
    t.dust_t = t.dust_t - dt * moving
    if t.dust_t <= 0 then
        t.dust_t = 0.35
        local fx, fz = cos(rad(t.yaw)), -sin(rad(t.yaw))
        local sx, sz = -fz, fx
        dust(t.x - fx * 0.5 + sx * 0.4, t.z - fz * 0.5 + sz * 0.4, 3)
        dust(t.x - fx * 0.5 - sx * 0.4, t.z - fz * 0.5 - sz * 0.4, 3)
    end
    if rand() < dt * (2 + abs(t.v)) then
        local fx, fz = cos(rad(t.yaw)), -sin(rad(t.yaw))
        burst({ position = vec3(t.x - fx * 0.7, 0.5, t.z - fz * 0.7), velocity = vec3(-fx * 0.6, 0.9, -fz * 0.6),
            color_start = vec4(0.25, 0.25, 0.28, 0.35), color_end = vec4(0.05, 0.05, 0.06, 0),
            count = 2, size_min = 0.08, size_max = 0.18, life_min = 0.6, life_max = 1.1, spawn_radius = 0.05,
            noise_strength = 0.4, drag = 1.0, gravity = vec3(0, 0.6, 0) })
    end
    t.bob = t.bob + dt * abs(t.v) * 3
end

local function draw_tank(t)
    local fx, fz = cos(rad(t.yaw)), -sin(rad(t.yaw))
    local rk = t.recoil * 0.12
    local pitch = -t.recoil * 4 + clamp(t.v, -3, 3) * -0.5 + sin(t.bob) * 0.4
    t.n:set_transform(vec3(t.x - fx * rk, 0.0, t.z - fz * rk), vec3(0, t.yaw, pitch), vec3(TS, TS, TS))
    tank_paint(t)
    local c = TEAM[t.i].col
    lights.set_point_light(L[t.i], vec3(t.x, 1.4, t.z), vec3(c[1], c[2], c[3]), 9 + 3 * sin(S.t * 5), 4.5)
end

------------------------------------------------------------------ shells
local function update_shell(sh, k, dt)
    local node = N["shell" .. k]
    if not sh.alive then
        hide_far(node)
        for j = 1, 10 do hide_far(FX.trail[k][j]) end
        lights.set_point_light(L[2 + k], vec3(0, -50, 0), vec3(1, 1, 1), 0, 1)
        return
    end
    sh.life = sh.life - dt
    local steps = 4
    for _ = 1, steps do
        local nx, nz = sh.x + sh.vx * dt / steps, sh.z + sh.vz * dt / steps
        local b = wall_at(nx, nz, 0.08)
        if b then
            if S.bounce and sh.bounces < 4 then
                local bx, bz = wall_at(nx, sh.z, 0.08), wall_at(sh.x, nz, 0.08)
                if bx then sh.vx = -sh.vx end
                if bz then sh.vz = -sh.vz end
                if not bx and not bz then sh.vx, sh.vz = -sh.vx, -sh.vz end
                sh.bounces = sh.bounces + 1
                sparks(sh.x, 0.55, sh.z, TEAM[k].col[1], TEAM[k].col[2], TEAM[k].col[3], 30, 6, 0.4)
                flash_light(sh.x, 0.8, sh.z, TEAM[k].col[1], TEAM[k].col[2], TEAM[k].col[3], 25, 4, 0.2)
                sfx("bounce")
            else
                explosion(sh.x, sh.z, false)
                sparks(sh.x, 0.55, sh.z, 0.8, 0.9, 1, 30, 6, 0.5)
                sfx("hitwall")
                sh.alive = false; return
            end
        else
            sh.x, sh.z = nx, nz
        end
        for _, t in ipairs(tanks) do
            local dx, dz = sh.x - t.x, sh.z - t.z
            if dx * dx + dz * dz < (TANK_R + 0.06) ^ 2 and not (t.i == k and sh.bounces == 0) and t.spin <= 0 and t.inv <= 0 then
                hit_tank(t, k, sh.vx, sh.vz)
                sh.alive = false; return
            end
        end
    end
    if sh.life <= 0 then
        sparks(sh.x, 0.5, sh.z, 1, 0.8, 0.5, 20, 3, 0.4); smoke(sh.x, 0.5, sh.z, 6, 0.3, 0.8)
        sh.alive = false; return
    end
    -- visuals
    table.insert(sh.hist, 1, { sh.x, sh.z }); sh.hist[12] = nil
    local yaw = deg(atan2(-sh.vz, sh.vx))
    place(node, sh.x, 0.56, sh.z, yaw, 1.6, 1.6, 1.6)
    local c = TEAM[k].col
    local fl = 1 + 0.25 * sin(S.t * 60)
    paint(node, 0, { 1, 1, 1 }, { 2 + c[1] * 6 * fl, 2 + c[2] * 6 * fl, 2 + c[3] * 6 * fl })
    for j = 1, 10 do
        local a, b = sh.hist[j], sh.hist[j + 1] or sh.hist[j]
        local dx, dz = a[1] - b[1], a[2] - b[2]
        local len = sqrt(dx * dx + dz * dz)
        local w = 0.07 * (1 - (j - 1) / 11)
        if len < 0.001 then hide_far(FX.trail[k][j])
        else place(FX.trail[k][j], (a[1] + b[1]) / 2, 0.56, (a[2] + b[2]) / 2, deg(atan2(-dz, dx)), len + 0.02, w, w) end
    end
    lights.set_point_light(L[2 + k], vec3(sh.x, 0.9, sh.z), vec3(c[1], c[2], c[3]), 16, 4.0)
    burst({ position = vec3(sh.x, 0.56, sh.z), velocity = vec3(-sh.vx * 0.04, 0.2, -sh.vz * 0.04),
        color_start = vec4(c[1], c[2], c[3], 0.9), color_end = vec4(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 0),
        count = 5, size_min = 0.03, size_max = 0.09, life_min = 0.15, life_max = 0.45, spawn_radius = 0.04,
        noise_strength = 0.6, drag = 2, gravity = vec3(0, 0.2, 0), cleanup_delay = 1.5 })
    if rand() < 0.5 then
        burst({ position = vec3(sh.x, 0.56, sh.z), velocity = vec3(0, 0.3, 0),
            color_start = vec4(0.4, 0.4, 0.45, 0.25), color_end = vec4(0.1, 0.1, 0.12, 0),
            count = 2, size_min = 0.08, size_max = 0.16, life_min = 0.4, life_max = 0.9, spawn_radius = 0.03,
            noise_strength = 0.3, drag = 1.2, gravity = vec3(0, 0.3, 0), cleanup_delay = 1.5 })
    end
end

------------------------------------------------------------------ camera
local cam = { x = 0, y = 26, z = 17.5, pitch = 0.98, intro = 0 }
local function update_camera(dt)
    local ok, c = pcall(get_camera)
    if not ok or not c then return end
    local tx, tz = 0, 0
    if S.mode == "play" or S.mode == "countdown" or S.mode == "win" then
        tx = (tanks[1].x + tanks[2].x) * 0.5 * 0.08
        tz = (tanks[1].z + tanks[2].z) * 0.5 * 0.06
    end
    local orbit = 0
    if S.mode == "title" then orbit = sin(S.t * 0.15) * 3.5 end
    cam.x = lerp(cam.x, tx + orbit, min(1, dt * 2))
    cam.z = lerp(cam.z, 17.0 + tz, min(1, dt * 2))
    local intro = cam.intro
    if intro < 1 then cam.intro = min(1, intro + dt * 0.45) end
    local e = 1 - (1 - cam.intro) ^ 3
    local y = lerp(40, 25.5, e)
    local z = lerp(30, cam.z, e)
    local sh = S.shake * (SET and SET:shake_scale() or 1)
    S.shake = max(0, S.shake - dt * 1.6)
    local sx, sy = (rand() - 0.5) * sh * 0.7, (rand() - 0.5) * sh * 0.7
    if cam.override then c:set_position(cam.override[1]); c:set_euler(cam.override[2]); return end
    c:set_position(vec3(cam.x + sx, y + sy, z))
    c:set_euler(vec3(lerp(0.9, 0.99, e) + sy * 0.01, pi, sx * 0.01))
end

------------------------------------------------------------------ menus / HUD
local MENU = {
    { id = "start1", label = function() return "1 PLAYER  vs  AI" end },
    { id = "start2", label = function() return "2 PLAYERS  (LOCAL)" end },
    { id = "arena", label = function() return "ARENA :  < " .. ARENA_STYLE[AR.arenas[S.arena].name].label .. " >" end },
    { id = "bounce", label = function() return "BOUNCING SHOTS :  " .. (S.bounce and "ON" or "OFF") end },
    { id = "target", label = function() return "SCORE TO WIN :  < " .. S.target .. " >" end },
    { id = "ai", label = function() return "AI SKILL :  < " .. ({ "ROOKIE", "VETERAN", "ACE" })[S.ai_level] .. " >" end },
    { id = "settings", label = function() return "SETTINGS" end },
    { id = "quit", label = function() return "QUIT" end },
}
local PAUSE = { { id = "resume", label = "RESUME" }, { id = "restart", label = "RESTART MATCH" }, { id = "settings", label = "SETTINGS" }, { id = "title", label = "QUIT TO TITLE" } }

local function draw_title()
    local sw, sh = surface()
    local cx, w = sw * 0.5, sw * 0.44
    panel("m_bg", cx - w / 2, sh * 0.12, w, sh * 0.78, { 0.01, 0.02, 0.05, 0.72 }, { 0.2, 0.8, 1.0, 0.7 }, 20, 16)
    local p = 0.85 + 0.15 * sin(S.t * 2.2)
    txt("m_t1", cx - w / 2, sh * 0.15, w, sh * 0.1, "N E O N    C O M B A T", 3.0, { 0.3 * p, 1.0 * p, 0.6 * p, 1 }, "center", 21)
    txt("m_t2", cx - w / 2, sh * 0.245, w, sh * 0.04, "ARMORED  ARENA  DUEL", 1.15, { 1.0, 0.35, 0.7, 1 }, "center", 21)
    for i, m in ipairs(MENU) do
        local sel = (i == S.menu_i)
        local y = sh * (0.32 + (i - 1) * 0.058)
        if sel then panel("m_sel", cx - w * 0.42, y - sh * 0.004, w * 0.84, sh * 0.05, { 0.1, 0.6, 1.0, 0.18 + 0.08 * sin(S.t * 6) }, { 0.3, 0.9, 1.0, 0.9 }, 21, 8) end
        local st, hov = hit("m_k" .. i, cx - w * 0.42, y - sh * 0.004, w * 0.84, sh * 0.05)
        if hov then S.menu_i = i end
        if st and st.clicked then S.menu_i = i; S.m_click = true end
        txt("m_i" .. i, cx - w / 2, y, w, sh * 0.042, (sel and "> " or "") .. m.label() .. (sel and " <" or ""), 1.35,
            sel and { 1, 1, 1, 1 } or { 0.62, 0.72, 0.85, 1 }, "center", 22)
    end
    txt("m_h1", cx - w / 2, sh * 0.80, w, sh * 0.03, "P1:  A / D  TURN  ·  SPACE  FORWARD  ·  S  REVERSE  ·  LEFT CLICK  FIRE   |   P2:  ARROWS + ENTER / R-CTRL", 0.9, { 0.6, 0.85, 1.0, 0.9 }, "center", 21)
    txt("m_h2", cx - w / 2, sh * 0.835, w, sh * 0.03, "UP/DOWN select   LEFT/RIGHT change   ENTER confirm   ESC pause", 0.85, { 0.55, 0.6, 0.75, 0.9 }, "center", 21)
end

local function draw_hud()
    local sw, sh = surface()
    for i = 1, 2 do
        local c = TEAM[i].col
        local x = (i == 1) and sw * 0.03 or sw * 0.77
        panel("h_bg" .. i, x, sh * 0.02, sw * 0.2, sh * 0.095, { 0.01, 0.02, 0.04, 0.6 }, { c[1], c[2], c[3], 0.8 }, 3, 12)
        local who = (i == 2 and tanks[2].ai) and "AI" or ("P" .. i)
        txt("h_n" .. i, x + sw * 0.01, sh * 0.025, sw * 0.18, sh * 0.03, who .. "  " .. TEAM[i].name, 0.95, { c[1], c[2], c[3], 1 }, i == 1 and "left" or "right", 4)
        txt("h_s" .. i, x + sw * 0.01, sh * 0.05, sw * 0.18, sh * 0.06, string.format("%02d", tanks[i].score), 2.6, { 1, 1, 1, 1 }, i == 1 and "left" or "right", 4)
        -- pips toward target
        for k = 1, S.target do
            local filled = k <= tanks[i].score
            local px = (i == 1) and (x + sw * 0.08 + (k - 1) * sw * 0.011) or (x + sw * 0.12 - (k - 1) * sw * 0.011)
            panel("h_p" .. i .. "_" .. k, px, sh * 0.083, sw * 0.007, sh * 0.012, filled and { c[1], c[2], c[3], 1 } or { 0.2, 0.2, 0.25, 0.6 }, { 0, 0, 0, 0 }, 4, 3)
        end
        for k = S.target + 1, 15 do hud_hide("h_p" .. i .. "_" .. k) end
    end
    local st = ARENA_STYLE[AR.arenas[S.arena].name]
    txt("h_ar", sw * 0.3, sh * 0.02, sw * 0.4, sh * 0.035, st.label .. "   |   FIRST TO " .. S.target .. "   |   " .. (S.bounce and "RICOCHET ON" or "RICOCHET OFF"), 0.95, { 0.7, 0.8, 0.95, 0.85 }, "center", 4)
    if S.banner_t > 0 then
        local a = min(1, S.banner_t * 3)
        local c = S.banner_col or { 1, 1, 1 }
        txt("h_ban", 0, sh * 0.42, sw, sh * 0.1, S.banner, 2.6, { c[1], c[2], c[3], a }, "center", 10)
    else hud_hide("h_ban") end
    -- full-screen hit flash
    hud_ids["h_flash"] = true
    runtime_ui.set_quad("hud", "h_flash", { x = 0, y = 0, w = S.flash > 0.01 and sw or 0, h = S.flash > 0.01 and sh or 0, z = 30, style = "text", label = "",
        fill = { 1.0, 0.6, 0.3, S.flash * 0.3 }, border = { 0, 0, 0, 0 }, no_input = true, visible = S.flash > 0.01 })
end

------------------------------------------------------------------ flow
local function reset_round()
    for _, t in ipairs(tanks) do tank_spawn(t) end
    for k = 1, 2 do shells[k].alive = false end
end
local function start_match(players)
    S.players = players
    tanks[2].ai = (players == 1)
    tanks[1].score, tanks[2].score = 0, 0
    tanks[1].ai_state, tanks[2].ai_state = {}, {}
    set_arena(S.arena)
    reset_round()
    hud_hide("m_"); hud_hide("w_")
    S.mode = "countdown"; S.countdown = 2.4; S.paused = false
    sfx("start")
end
local function to_title()
    S.mode = "title"; S.paused = false
    hud_hide("h_"); hud_hide("p_"); hud_hide("w_"); hud_hide("c_")
    for k = 1, 2 do shells[k].alive = false end
end

local function menu_input()
    local n = #MENU
    if edge("Up") or edge("W") then S.menu_i = (S.menu_i - 2) % n + 1; sfx("click") end
    if edge("Down") or edge("S") then S.menu_i = S.menu_i % n + 1; sfx("click") end
    local d = (edge("Right") or edge("D")) and 1 or ((edge("Left") or edge("A")) and -1 or 0)
    local ok = edge("Return") or edge("Space") or edge("Keypad Enter") or S.m_click
    S.m_click = false
    local id = MENU[S.menu_i].id
    if id == "arena" and (d ~= 0 or ok) then
        S.arena = (S.arena - 1 + (d == 0 and 1 or d)) % #AR.arenas + 1; set_arena(S.arena); sfx("click")
    elseif id == "bounce" and (d ~= 0 or ok) then S.bounce = not S.bounce; sfx("click")
    elseif id == "target" and (d ~= 0 or ok) then
        local opts = { 3, 5, 10, 15 }; local j = 1
        for k, v in ipairs(opts) do if v == S.target then j = k end end
        j = (j - 1 + (d == 0 and 1 or d)) % #opts + 1; S.target = opts[j]; sfx("click")
    elseif id == "ai" and (d ~= 0 or ok) then S.ai_level = (S.ai_level - 1 + (d == 0 and 1 or d)) % 3 + 1; sfx("click")
    elseif ok then
        if id == "start1" then start_match(1)
        elseif id == "start2" then start_match(2)
        elseif id == "settings" then hud_hide("m_"); SET:open(function() end); sfx("click")
        elseif id == "quit" then pcall(engine.quit) end
    end
end

local function pause_input()
    local sw, sh = surface()
    S.pause_i = S.pause_i or 1
    panel("p_bg", sw * 0.36, sh * 0.3, sw * 0.28, sh * 0.4, { 0.01, 0.02, 0.05, 0.8 }, { 0.3, 0.9, 1.0, 0.8 }, 20, 14)
    txt("p_t", sw * 0.36, sh * 0.32, sw * 0.28, sh * 0.06, "PAUSED", 2.2, { 0.4, 0.95, 1.0, 1 }, "center", 21)
    for i, m in ipairs(PAUSE) do
        local sel = i == S.pause_i
        local st, hov = hit("p_k" .. i, sw * 0.38, sh * (0.41 + (i - 1) * 0.06), sw * 0.24, sh * 0.05)
        if hov then S.pause_i = i end
        if st and st.clicked then S.pause_i = i; S.p_click = true end
        txt("p_i" .. i, sw * 0.36, sh * (0.41 + (i - 1) * 0.06), sw * 0.28, sh * 0.045, (sel and "> " or "") .. m.label .. (sel and " <" or ""), 1.3,
            sel and { 1, 1, 1, 1 } or { 0.6, 0.7, 0.85, 1 }, "center", 22)
    end
    if edge("Up") or edge("W") then S.pause_i = (S.pause_i - 2) % #PAUSE + 1; sfx("click") end
    if edge("Down") or edge("S") then S.pause_i = S.pause_i % #PAUSE + 1; sfx("click") end
    if edge("Escape") or edge("P") then S.paused = false; hud_hide("p_") return end
    local pc = S.p_click; S.p_click = false
    if edge("Return") or edge("Space") or edge("Keypad Enter") or pc then
        local id = PAUSE[S.pause_i].id
        hud_hide("p_")
        if id == "resume" then S.paused = false
        elseif id == "restart" then start_match(S.players)
        elseif id == "settings" then SET:open(function() end)
        elseif id == "title" then to_title() end
    end
end

------------------------------------------------------------------ main
local function build_post()
    pcall(skybox.load, "dusk.hdr")
    local ok, node = pcall(scene.add_empty_node, "NC_SceneSettings")
    if ok and node then pcall(function() node:set_scene_settings(true) end) end
    local function st(k, v) pcall(settings.set, k, v) end
    st("hdr", false); st("bloom", true); st("bloom_strength", 0.55); st("bloom_range", 1.25)  -- see common/RENDER_SETTINGS.md
    st("tonemapping", true); st("fxaa", false); st("taa", true); st("cas_sharpening", false); st("motion_blur", false); st("dof", false)
    st("ssao", false); st("ssr", false); st("shadows", true)
    st("color_grading", true); st("color_grading_saturation", 1.2); st("color_grading_contrast", 1.1)
end

local function init()
    pe_log("[NC] init")
    pcall(function() math.randomseed(floor((engine.get_metrics().delta_ms or 1) * 100000)) end)
    for i = 1, 2 do N["tank" .. i] = scene.find_model(i == 1 and "TankA" or "TankB") end
    N.shell1, N.shell2 = scene.find_model("ShellA"), scene.find_model("ShellB")
    for i = 0, 2 do N["debris" .. i] = scene.find_model("Debris" .. i) end
    N.floor = scene.find_model("Floor")
    for _, a in ipairs(AR.arenas) do N["arena_" .. a.name] = scene.find_model("Arena_" .. a.name) end
    place(N.floor, 0, 0, 0)
    for i = 0, 2 do hide_far(N["debris" .. i]) end
    build_post()
    build_lights()
    build_fx_pools()
    for i = 1, 2 do tanks[i] = new_tank(i); shells[i] = { alive = false, hist = {} } end
    set_arena(1)
    reset_round()
    -- floating ambient dust motes over the arena
    pcall(particles.add_emitter, { name = "motes", position = vec3(0, 1.5, 0), velocity = vec3(0, 0.15, 0),
        color_start = vec4(0.5, 0.8, 1.0, 0.5), color_end = vec4(0.8, 0.3, 1.0, 0), count = 220, spawn_rate = 30,
        size_min = 0.02, size_max = 0.06, life_min = 4, life_max = 8, spawn_radius = 16, noise_strength = 0.35, drag = 0.2, gravity = vec3(0, 0.05, 0) })
    pcall(runtime_ui.show, "hud")
    pcall(runtime_ui.set_screen_overlay, "hud", true)
    local ok, SM = pcall(function() return load(fs.read("Scripts/Lib/settings_menu.lua"), "@settings_menu.lua")() end)
    if ok and SM then
        SET = SM.new({ title = "SETTINGS", subtitle = "P1:  A / D  TURN  ·  SPACE  FORWARD  ·  LEFT CLICK  FIRE   |   P2:  ARROWS + ENTER", file = "Save/settings.cfg", click = function() sfx("click") end, music = false,
            defaults = { master = 0.5 }, theme = { accent = { 0.25, 1.0, 0.55, 1 }, accent2 = { 1.0, 0.25, 0.65, 1 } } })
        SET:apply()
    else pe_log("[NC] settings menu failed: " .. tostring(SM)) end
    S.mode = "title"
end

local function update(dt)
    if dt > 0.1 then dt = 0.1 end
    S.t = S.t + dt; S.frame = S.frame + 1
    for i = #deferred, 1, -1 do
        local d = deferred[i]; d.f = d.f - 1
        if d.f <= 0 then table.remove(deferred, i); local ok, e = pcall(d.fn); if not ok then pe_log("[NC] deferred: " .. tostring(e)) end end
    end
    local menu_open = SET and SET:update(dt)
    if menu_open then for _, k in ipairs(EDGE_KEYS) do edge(k) end end
    if not menu_open then
        if S.mode == "title" then
            draw_title(); menu_input()
        elseif S.paused then
            pause_input()
        else
            if (edge("Escape") or edge("P")) and (S.mode == "play" or S.mode == "countdown") then S.paused = true; S.pause_i = 1; sfx("click") end
            if edge("M") and SET then SET:toggle_mute() end
        end
    end
    local frozen = S.paused or menu_open
    if not frozen then
        if S.mode == "countdown" then
            S.countdown = S.countdown - dt
            local sw, sh = surface()
            local n = math.ceil(S.countdown / 0.8)
            local label = n >= 1 and tostring(n) or "FIGHT!"
            local f = (S.countdown / 0.8) % 1
            txt("c_n", 0, sh * 0.38, sw, sh * 0.16, label, 4.0 + (n < 1 and 1 or f), { 1, 1, 1, 0.4 + 0.6 * f }, "center", 12)
            if S.countdown <= -0.4 then S.mode = "play"; hud_hide("c_") end
            if S.countdown <= 0 and S.mode == "countdown" then
                -- tanks may already move during FIGHT!
                S.mode = "play"; S.fight_t = 0.6
            end
        end
        if S.fight_t then
            S.fight_t = S.fight_t - dt
            local sw, sh = surface()
            txt("c_n", 0, sh * 0.38, sw, sh * 0.16, "FIGHT!", 4.2 + (0.6 - S.fight_t), { 1, 0.9, 0.4, max(0, S.fight_t / 0.6) }, "center", 12)
            if S.fight_t <= 0 then S.fight_t = nil; hud_hide("c_") end
        end
        -- tanks
        local live = (S.mode == "play")
        for i, t in ipairs(tanks) do
            local th, tu, sh = 0, 0, false
            if live then
                if t.ai then
                    th, tu, sh = ai_control(t, tanks[3 - i], dt)
                elseif i == 1 then
                    -- P1: A/D turn, SPACE drives forward (W also), S reverses, LEFT CLICK fires
                    th = ((down("Space") or down("W")) and 1 or 0) - (down("S") and 1 or 0)
                    tu = (down("D") and 1 or 0) - (down("A") and 1 or 0)
                    sh = lmb() or down("F") or down("Left Shift")
                    if S.players == 1 then
                        th = th + (down("Up") and 1 or 0) - (down("Down") and 1 or 0)
                        tu = tu + (down("Right") and 1 or 0) - (down("Left") and 1 or 0)
                        sh = sh or down("Return") or down("Right Ctrl")
                    end
                    th, tu = clamp(th, -1, 1), clamp(tu, -1, 1)
                else
                    th = (down("Up") and 1 or 0) - (down("Down") and 1 or 0)
                    tu = (down("Right") and 1 or 0) - (down("Left") and 1 or 0)
                    sh = down("Return") or down("Right Ctrl") or down("Keypad 0") or down("Right Shift") or down("Keypad Enter")
                end
            end
            update_tank(t, dt, th, tu, sh)
        end
        -- tank vs tank
        local a, b = tanks[1], tanks[2]
        local dx, dz = b.x - a.x, b.z - a.z
        local d = sqrt(dx * dx + dz * dz)
        if d < TANK_R * 2 and d > 1e-4 then
            local p = (TANK_R * 2 - d) * 0.5
            a.x, a.z, b.x, b.z = a.x - dx / d * p, a.z - dz / d * p, b.x + dx / d * p, b.z + dz / d * p
            collide_tank(a); collide_tank(b)
        end
        for k = 1, 2 do update_shell(shells[k], k, dt) end
        update_fx(dt)
        S.banner_t = max(0, S.banner_t - dt)
        S.flash = max(0, S.flash - dt * 2.5)
        if S.mode == "win" then
            S.win_t = S.win_t + dt
            local sw, sh = surface()
            local c = TEAM[S.winner].col
            local who = (S.winner == 2 and tanks[2].ai) and "AI WINS" or ("PLAYER " .. S.winner .. " WINS")
            panel("w_bg", 0, sh * 0.33, sw, sh * 0.3, { 0.01, 0.01, 0.03, 0.6 * min(1, S.win_t) }, { 0, 0, 0, 0 }, 9, 0)
            txt("w_t", 0, sh * 0.36, sw, sh * 0.13, who, 4.0, { c[1], c[2], c[3], min(1, S.win_t * 2) }, "center", 10)
            txt("w_s", 0, sh * 0.49, sw, sh * 0.05, string.format("%d  -  %d", tanks[1].score, tanks[2].score), 2.0, { 1, 1, 1, min(1, S.win_t) }, "center", 10)
            if S.win_t > 1.5 then txt("w_h", 0, sh * 0.55, sw, sh * 0.04, "ENTER  rematch      ESC  title", 1.2, { 0.8, 0.9, 1, 0.6 + 0.4 * sin(S.t * 4) }, "center", 10) end
            if rand() < dt * 5 then
                local x, z = (rand() - 0.5) * 30, (rand() - 0.5) * 16
                sparks(x, 2 + rand() * 3, z, c[1], c[2], c[3], 70, 9, 1.2)
                flash_light(x, 3, z, c[1], c[2], c[3], 40, 8, 0.6)
            end
            if S.win_t > 1.5 and (edge("Return") or edge("Space")) then start_match(S.players)
            elseif edge("Escape") then to_title() end
        end
    end
    for _, t in ipairs(tanks) do draw_tank(t) end
    if S.mode ~= "title" then draw_hud() else hud_hide("h_") end
    update_lights(dt)
    update_camera(frozen and 0 or dt)
    for _, k in ipairs(EDGE_KEYS) do if prevk[k] == nil then prevk[k] = down(k) end end
end

-- automation hook (MCP tests / screenshots)
_G.NC = { S = S, tanks = tanks, shells = shells, VK = VK, start = start_match, title = to_title, fire = fire,
    explode = explosion, arena = set_arena, hit = hit_tank, cam = cam }

hooks { init = init, update = update }
