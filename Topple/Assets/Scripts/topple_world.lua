-- Topple world. The table, room, desk lamp and chalk board are a pre-rendered Cycles backdrop
-- (tools/make_backdrop.py) shown unlit on a quad that exactly fills the fixed camera's view. On top, in 3D: every
-- toy (cloned from cooked templates, tools/gen_meshes.py), lit by the scene's lamp lights and a lamp-lit room HDR,
-- with soft shadows cast on the pictured felt from the lamp's position, and the animation of a tip.
-- Table point (x, y) with height h is engine (x, h, -y). The camera must match the bake exactly.
return function(R)
local W = {}
local floor, min, max, abs, sin, cos, sqrt = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt
local deg, rad, pi = math.deg, math.rad, math.pi
local atan2 = math.atan2 or math.atan
local function v3(x, y, z) return vec3(x, y, z) end

W.CAM = { pos = { 12.53, 13.65, 19.93 }, look = { -0.6, 0.0, -3.6 }, vfov = 29.84 }
W.LAMP = { x = -9.0, y = -3.0, h = 11.5 }                -- table coordinates of the desk lamp
W.BOARD = { x = 3.5, y = 14.0 }                          -- the chalk board's easel (as baked)
local cam
local S = { t = 0, shake = 0 }

------------------------------------------------------------------ materials (template clones replay writes: engine quirk)
local mat_q = {}
local function mset(n, k, v)
    pcall(material.set, n, k, v)
    mat_q[#mat_q + 1] = { n = n, k = k, v = v, c = 0 }
end
local function flush_mats()
    for i = #mat_q, 1, -1 do
        local q = mat_q[i]
        q.c = q.c + 1
        if q.c == 2 or q.c == 6 or q.c == 20 then
            if q.f then q.f() else pcall(material.set, q.n, q.k, q.v) end
        end
        if q.c >= 20 then table.remove(mat_q, i) end
    end
end
local function mat(n, base, metal, rough, emis)
    mset(n, "base_color", vec4(base[1], base[2], base[3], base[4] or 1))
    mset(n, "emissive", v3(emis and emis[1] or 0, emis and emis[2] or 0, emis and emis[3] or 0))
    mset(n, "metallic", metal or 0)
    mset(n, "roughness", rough or 0.5)
end
-- The concept's paints (linear), glossy enamel on wood. Pulled a quarter of the way to grey: the backdrop went
-- through Cycles' AgX view, which rolls saturated colours off; the engine draws the toys without a tone curve,
-- so the raw paints came out hotter than the concept (measured against it, 2026-11-08).
local function agx(c, k)
    local l = 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
    return { l + (c[1] - l) * k, l + (c[2] - l) * k, l + (c[3] - l) * k }
end
local PAINT = {
    brick = agx({ 0.52, 0.14, 0.08 }, 0.7), mustard = agx({ 0.80, 0.55, 0.14 }, 0.75), sage = agx({ 0.33, 0.45, 0.31 }, 0.6),
    navy = agx({ 0.11, 0.17, 0.32 }, 0.85), cream = agx({ 0.86, 0.79, 0.64 }, 0.75),
}
W.PAINTS = { "brick", "mustard", "sage", "navy", "cream" }
local LOOK = {
    wood = function(n) mat(n, { 0.58, 0.38, 0.19 }, 0, 0.5) end,
    brass = function(n) mat(n, { 0.86, 0.62, 0.30 }, 1, 0.24) end,
    steel = function(n) mat(n, { 0.78, 0.78, 0.80 }, 1, 0.24) end,
    pipd = function(n) mat(n, { 0.03, 0.03, 0.03 }, 0, 0.35) end,
    pipl = function(n) mat(n, { 0.88, 0.82, 0.68 }, 0, 0.35) end,
    glassdark = function(n) mat(n, { 0.04, 0.05, 0.06 }, 0, 0.08) end,
}
for k, c in pairs(PAINT) do LOOK[k] = function(n) mat(n, c, 0, 0.3) end end
-- The houses: miniature model houses made with Tripo (tools/make_houses.py), one textured mesh each.
local HOUSES = { "house_cottage", "house_townhouse", "house_farmhouse" }
for _, name in ipairs(HOUSES) do
    local tex = "Textures/" .. name .. ".png"
    LOOK[name] = function(n)
        mat(n, { 1, 1, 1 }, 0, 0.7)
        pcall(material.set_texture, n, "base_color", tex)
        mat_q[#mat_q + 1] = { c = 0, f = function() pcall(material.set_texture, n, "base_color", tex) end }
    end
end

------------------------------------------------------------------ nodes
local TPL = {}
local seq = 0
-- Every node a toy makes goes on its list, so removing the toy removes them all (children first).
local LIST
local function track(n) if LIST then LIST[#LIST + 1] = n end; return n end
local function clone(name, parent, look)
    local t = TPL[name]
    if not t then
        local n = scene.find_model and scene.find_model("T_" .. name)
        t = { mesh = n and n:get_mesh_refs()[1] or nil }
        TPL[name] = t
    end
    seq = seq + 1
    local n = track(scene.add_empty_node(name .. "_" .. seq))
    if t.mesh then n:add_mesh_ref(t.mesh) end
    if parent then n:set_parent(parent) end
    if look and LOOK[look] then LOOK[look](n) end
    return n
end
local function empty(parent, x, y, z)
    seq = seq + 1
    local n = track(scene.add_empty_node("tp_e" .. seq))
    if parent then n:set_parent(parent) end
    n:set_position(v3(x or 0, y or 0, z or 0))
    return n
end
local function kill(n) if n then pcall(function() n:remove() end) end end

local function shadow_node(tex, alpha)
    local n = primitives.cube(1)
    pcall(material.set_render_type, n, "alpha_blend")
    mat(n, { 0.02, 0.025, 0.02, alpha or 0.5 }, 0, 1)
    pcall(material.set_texture, n, "base_color", tex or "Textures/shadow_box.png")
    return n
end

------------------------------------------------------------------ init
-- The table's look (also restored when Free Build hands the screen back). The backdrop is already graded (the
-- concept's AgX look): no tonemapping or bloom on top of it.
function W.apply_look()
    if skybox and skybox.load then pcall(skybox.load, "room.hdr") end
    for k, v in pairs({ tonemapping = false, bloom = false, render_scale = 1.0, taa = true, fxaa = false, cas_sharpening = false,
        motion_blur = false, ssao = false, ssr = false, IBL = true, IBL_intensity = 1.15, shadows = true, color_grading = false,
        dof = false, shadow_distance = W.shadow_distance }) do pcall(settings.set, k, v) end
end
-- Free Build borrows the screen: the backdrop and the toys go away while it is open.
function W.show(on)
    if W.backdrop then pcall(function() W.backdrop:set_enabled(on) end) end
    if not on then W.clear() end
end

function W.init()
    if W.shadow_distance == nil then
        local ok, v = pcall(settings.get, "shadow_distance")
        W.shadow_distance = ok and v or nil
    end
    cam = scene.get_active_camera()
    pcall(function() cam:set_projection_mode("perspective") end)
    if not W.settings_node then
        W.settings_node = scene.add_empty_node("Scene Settings")
        pcall(function() W.settings_node:set_scene_settings(true) end)
    end
    -- Raster, like every other game here: the engine's hybrid default refits a ray-tracing TLAS every frame,
    -- which faulted the GPU as toys were added and removed.
    pcall(settings.set_render_mode, "raster")
    W.apply_look()
    local t = scene.find_model and scene.find_model("T_backdrop")
    if t then
        W.backdrop = t
        mat(t, { 0, 0, 0, 1 }, 0, 1, { 1, 1, 1 })
        pcall(material.set_texture, t, "emissive", "Textures/backdrop.png")
        mat_q[#mat_q + 1] = { c = 0, f = function() pcall(material.set_texture, t, "emissive", "Textures/backdrop.png") end }
    end
    W.vis, W.fx = {}, {}
end

------------------------------------------------------------------ toy visuals
-- Every toy: root (position) -> fall (yaw of the fall direction) -> tilt (pivot on the edge it falls over) ->
-- body (the toy's own yaw), so dominoes and houses can topple any way. Static parts hang off the root.
local SH = {   -- shadow: height, width, alpha, texture
    domino = { 1.0, 0.5, 0.5 }, house = { 1.95, 1.45, 0.55 }, block = { 0.56, 0.6, 0.45 }, tree = { 1.85, 1.0, 0.4, "Textures/shadow.png" },
    bell = { 2.3, 0.5, 0.28 }, spring = { 0.85, 0.75, 0.45, "Textures/shadow.png" }, rocket = { 1.2, 0.6, 0.4, "Textures/shadow.png" },
    marble = { 1.0, 0.7, 0.4 },
}
local HALF = { domino = R.DOM.t / 2, house = 0.62 }
-- Height of the marble's centre s along its path from the top of the chute (the chute drops 0.88 over 1.8).
function W.chute_height(s)
    local x = R.CHUTE_TOP + s
    if x > 0.9 then return 0.28 end
    return 1.0 - (x + 0.9) * (0.88 / 1.8) + 0.31
end

local function pip_pattern(id) return (id * 7) % 10 end

local build_parts
local function build(p)
    local v = { p = p, kind = p.kind, all = {} }
    LIST = v.all
    build_parts(v, p)
    LIST = nil
    return v
end
build_parts = function(v, p)
    v.root = empty(nil, p.x, 0, -p.y)
    v.fall = empty(v.root)
    v.tilt = empty(v.fall)
    v.body = empty(v.tilt)
    v.body:set_rotation(v3(0, deg(p.a or 0), 0))
    local k = p.kind
    if k == "domino" then
        local paint = p.paint or "cream"
        clone("domino_" .. paint, v.body, paint)
        clone("pips_" .. pip_pattern(p.id) .. (paint == "navy" and "_light" or "_dark"), v.body, paint == "navy" and "pipl" or "pipd")
    elseif k == "house" then
        local name = HOUSES[((p.paint or 1) - 1) % #HOUSES + 1]
        clone(name, v.body, name)
    elseif k == "block" then
        local c = ({ "mustard", "sage", "navy", "brick" })[p.paint or 1] or "mustard"
        clone("block_" .. c, v.body, c)
    elseif k == "tree" then
        clone("tree_trunk", v.body, "wood")
        clone("tree_top", v.body, "sage")
    elseif k == "bell" then
        clone("gallows", v.body, "wood")
        v.swing = empty(v.body, 0, 2.2, 0)
        clone("bell", v.swing, "brass")
    elseif k == "spring" then
        clone("spring_base", v.body, "wood")
        v.coil = empty(v.body)
        clone("spring_coil", v.coil, "steel")
        v.cap = empty(v.body, 0, 0.8, 0)
        clone("spring_cap", v.cap, "brass")
    elseif k == "rocket" then
        clone("launcher", v.body, "wood")
        v.rocket = empty(v.body, 0, 0.06, 0)
        v.rocket:set_rotation(v3(0, 0, -25))
        for _, part in ipairs({ { "rocket_body", "brick" }, { "rocket_band", "cream" }, { "rocket_nose", "cream" }, { "rocket_fins", "mustard" } }) do
            clone(part[1], v.rocket, part[2])
        end
    elseif k == "marble" then
        clone("chute", v.body, "wood")
        v.marble = track(primitives.uv_sphere(0.28, 40, 24))
        pcall(material.set_render_type, v.marble, "alpha_blend")
        mat(v.marble, { 0.95, 0.72, 0.42, 0.55 }, 0, 0.03)
        v.core = track(primitives.uv_sphere(0.12, 24, 16))
        mat(v.core, PAINT.brick, 0, 0.3)
        -- World-placed (not parented): it leaves the chute when it rolls.
        local a, top = p.a or 0, R.CHUTE_TOP
        local mx, my, mh = p.x + cos(a) * top, p.y + sin(a) * top, W.chute_height(0)
        v.marble:set_position(v3(mx, mh, -my)); v.core:set_position(v3(mx, mh, -my))
    end
    local sh = SH[k]
    if sh then v.shadow = track(shadow_node(sh[4], sh[3])) end
end

local function destroy(v)
    for i = #v.all, 1, -1 do kill(v.all[i]) end
    v.all = {}
end

-- The lamp's shadow of a point at table (x, y) and height h, on the felt.
local function cast(x, y, h)
    local L = W.LAMP
    if h >= L.h - 0.05 then return x, y end
    local k = L.h / (L.h - h)
    return L.x + (x - L.x) * k, L.y + (y - L.y) * k
end

local function place_shadow(v, bx, by, h, width, extra)
    if not v.shadow then return end
    local sx, sy = cast(bx, by, h)
    local dx, dy = sx - bx, sy - by
    local len = sqrt(dx * dx + dy * dy)
    local ang = len > 1e-4 and atan2(dy, dx) or 0
    local L = len + (extra or width * 0.45)
    v.shadow:set_position(v3((bx + sx) / 2, 0.006 + (v.p.id % 7) * 0.0006, -(by + sy) / 2))
    v.shadow:set_rotation(v3(0, deg(ang), 0))
    v.shadow:set_scale(v3(L, 0.001, width * 1.15))
end

-- Pose a toy: tilt theta (degrees) toward fall direction (fx, fy).
local function pose(v, theta, fx, fy)
    local p = v.p
    local fyaw = (fx and atan2(fy, fx)) or (p.a or 0)
    local e = HALF[v.kind] or 0
    v.fall:set_rotation(v3(0, deg(fyaw), 0))
    v.tilt:set_position(v3(e, 0, 0))
    v.tilt:set_rotation(v3(0, 0, -(theta or 0)))
    v.body:set_position(v3(-e, 0, 0))
    v.body:set_rotation(v3(0, deg((p.a or 0) - fyaw), 0))
    local sh = SH[v.kind]
    if sh then
        local th = rad(theta or 0)
        local H = sh[1]
        local ox = e + (-e * cos(th) + H * sin(th))
        local tx, ty = p.x + cos(fyaw) * ox, p.y + sin(fyaw) * ox
        local h = e * sin(th) + H * cos(th)
        if (theta or 0) < 1 then
            place_shadow(v, p.x, p.y, H, sh[2])
        else
            -- Shadow from the base to where the lamp throws the top.
            local sx, sy = cast(tx, ty, h)
            local dx, dy = sx - p.x, sy - p.y
            local len = sqrt(dx * dx + dy * dy)
            v.shadow:set_position(v3((p.x + sx) / 2, 0.006 + (p.id % 7) * 0.0006, -(p.y + sy) / 2))
            v.shadow:set_rotation(v3(0, deg(atan2(dy, dx)), 0))
            v.shadow:set_scale(v3(len + sh[2] * 0.45, 0.001, sh[2] * 1.15))
        end
    end
end

-- Make the visuals match the board: new toys built, removed toys gone, everything standing.
function W.sync(board)
    local seen = {}
    for _, p in pairs(board and board.pieces or {}) do
        local v = W.vis[p.id]
        if v and v.p ~= p then destroy(v); v = nil end
        if not v then
            v = build(p)
            W.vis[p.id] = v
            pose(v, 0)
        end
        seen[p.id] = true
    end
    for id, v in pairs(W.vis) do
        if not seen[id] then destroy(v); W.vis[id] = nil end
    end
end

function W.clear()
    for id, v in pairs(W.vis) do destroy(v); W.vis[id] = nil end
    W.anim = nil
    W.set_starter(nil)
end

-- The brass arrow behind the domino the tip will knock over.
function W.set_starter(p)
    if not p then
        if W.arrow then W.arrow:set_enabled(false) end
        return
    end
    if not W.arrow then W.arrow = clone("arrow", nil, "brass") end
    W.arrow:set_enabled(true)
    local bx, by = p.x - cos(p.a) * 0.55, p.y - sin(p.a) * 0.55
    W.arrow:set_position(v3(bx, 0, -by))
    W.arrow:set_rotation(v3(0, deg(p.a), 0))
    W.starter = p
end

------------------------------------------------------------------ effects
local function burst(x, y, h, c, n, sp, life, grav)
    local k = W.particle_scale and W.particle_scale() or 1
    if k <= 0 then return end
    pcall(particles.emit_burst, { position = v3(x, h, -y), velocity = v3(0, 0.8, 0),
        color_start = vec4(c[1], c[2], c[3], 0.9), color_end = vec4(c[1], c[2], c[3], 0), gravity = v3(0, grav or -2.5, 0),
        count = max(1, floor(n * k)), size_min = 0.02, size_max = 0.06, life_min = 0.25, life_max = life or 0.7,
        spawn_radius = 0.18, noise_strength = sp or 1.6, drag = 2 })
end
local function ring_fx(x, y, h, R0, c, e, life, grow)
    local r = primitives.torus(R0, 0.012, 72, 8)
    mat(r, { c[1], c[2], c[3], 1 }, 0, 0.4, { c[1] * e, c[2] * e, c[3] * e })
    W.fx[#W.fx + 1] = { n = r, x = x, y = y, h = h, t = 0, life = life, c = c, e = e, grow = grow }
end
local GOLD = { 1.0, 0.72, 0.32 }
local DUST = { 0.55, 0.62, 0.5 }
local SPARK = { 1.0, 0.55, 0.18 }

------------------------------------------------------------------ playing a tip
-- res: R.simulate's result. Poses come from its fall records; effects fire as their events come due.
function W.play(res)
    -- Dominoes that strike dominoes come to lean on them.
    local F, list = W.F, {}
    if F then
        for _, f in pairs(res.falls) do
            if f.lean then
                f.lean.final = f.lean.on_id and F.rest_angle(f.lean.contact) or f.lean.final
                list[#list + 1] = f.lean
            end
        end
        table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.id < b.id end)
        local seen, waiting = {}, {}
        for _, l in ipairs(list) do
            seen[l.id] = l
            F.attach_fall(l, seen, waiting)
        end
        for id in pairs(waiting) do F.fall_missed(id, waiting) end
    end
    W.anim = { res = res, t = 0, next_ev = 1, rung = {}, launched = {}, rolled = {}, sprung = {} }
end
function W.playing() return W.anim ~= nil and W.anim.t <= (W.anim.res.duration or 0) + 0.6 end
function W.anim_time() return W.anim and W.anim.t or 0 end

local function ease_out(u) u = max(0, min(1, u)); return 1 - (1 - u) ^ 3 end

local function faller_angle(f, t)
    if t < f.t then return 0 end
    local tc = f.t_contact
    if t < tc then
        local u = (t - f.t) / max(1e-3, tc - f.t)
        return f.contact * u ^ 1.6
    end
    local final
    if f.contact >= 85 then final = 88
    elseif f.blocked then final = f.contact
    else final = min(80, f.contact + 26) end
    local u = (t - tc) / 0.3
    local a = f.contact + (final - f.contact) * ease_out(u)
    if final >= 85 and u > 0 and u < 1.6 then a = a - 4 * sin(min(1, u / 1.6) * pi) * (1 - min(1, u / 1.6)) end
    return a
end

-- Advance the tip; returns the events that came due this frame (the view plays their sounds and pops).
local function animate(dt)
    local A = W.anim
    if not A then return {} end
    A.t = A.t + dt
    local t = A.t
    local due = {}
    local evs = A.res.events
    while A.next_ev <= #evs and evs[A.next_ev].t <= t do
        due[#due + 1] = evs[A.next_ev]
        A.next_ev = A.next_ev + 1
    end
    for _, ev in ipairs(due) do
        local v = W.vis[ev.id]
        local p = v and v.p
        if ev.kind == "ring" and v then
            A.rung[ev.id] = t
            ring_fx(p.x, p.y, 1.75, 0.6, GOLD, 1.4, 0.9, 1.4)
            ring_fx(p.x, p.y, 1.65, 0.45, GOLD, 1.0, 0.7, 1.1)
        elseif ev.kind == "spring" and v then
            A.sprung[ev.id] = t
            burst(p.x, p.y, 0.8, DUST, 10, 1.4, 0.5)
        elseif ev.kind == "launch" and v then
            A.launched[ev.id] = ev
        elseif ev.kind == "roll" and v then
            A.rolled[ev.id] = ev
        elseif ev.kind == "wobble" and v then
            v.wobble = t
        elseif ev.kind == "thunk" and v then
            v.wobble = t
        end
    end
    -- Fallers.
    for id, f in pairs(A.res.falls) do
        local v = W.vis[id]
        if v and t >= f.t then
            local a = (f.lean and W.F) and deg(W.F.fall_angle(f.lean, t)) or faller_angle(f, t)
            pose(v, a, f.dx, f.dy)
            if not v.landed and t >= f.t_contact then
                v.landed = true
                if f.kind == "house" then
                    burst(v.p.x + f.dx * 1.2, v.p.y + f.dy * 1.2, 0.2, DUST, 18, 2.0, 0.8)
                    W.shake(0.25)
                elseif f.contact >= 85 then
                    burst(v.p.x + f.dx * 0.8, v.p.y + f.dy * 0.8, 0.05, DUST, 4, 1.0, 0.4)
                end
            end
        end
    end
    -- Wobbles: a quick rock that settles.
    for _, v in pairs(W.vis) do
        if v.wobble and not A.res.falls[v.p.id] then
            local u = t - v.wobble
            if u < 0.8 then
                local px, py = cos(v.p.a), sin(v.p.a)
                pose(v, 9 * sin(u * 22) * math.exp(-u * 5), px, py)
            else
                pose(v, 0); v.wobble = nil
            end
        end
    end
    -- Bells swing after ringing.
    for id, t0 in pairs(A.rung) do
        local v = W.vis[id]
        if v and v.swing then
            local u = t - t0
            v.swing:set_rotation(v3(28 * sin(u * 7) * math.exp(-u * 1.6), 0, 0))
        end
    end
    -- Springs: the cap snaps up and settles.
    for id, t0 in pairs(A.sprung) do
        local v = W.vis[id]
        if v and v.cap then
            local u = t - t0
            local up = u < 0.12 and (-0.25 * u / 0.12) or (0.4 * math.exp(-(u - 0.12) * 4) * cos((u - 0.12) * 18))
            v.cap:set_position(v3(0, 0.8 + up, 0))
            v.coil:set_scale(v3(1, (0.8 + up) / 0.8, 1))
        end
    end
    -- Rockets: up off the rails, an arc to the landing point, sparks behind, a burst on landing.
    for id, ev in pairs(A.launched) do
        local v = W.vis[id]
        if v and v.rocket then
            local u = (t - ev.t0) / max(0.05, ev.t_land - ev.t0)
            if u >= 0 and u <= 1 then
                if not v.flyer then
                    v.rocket:set_enabled(false)
                    LIST = v.all
                    v.flyer = empty(nil)                        -- yaw
                    v.flytilt = empty(v.flyer)                  -- pitch, on its own node (euler order)
                    for _, part in ipairs({ { "rocket_body", "brick" }, { "rocket_band", "cream" }, { "rocket_nose", "cream" }, { "rocket_fins", "mustard" } }) do
                        clone(part[1], v.flytilt, part[2])
                    end
                    LIST = nil
                end
                local p = v.p
                local x = p.x + (ev.lx - p.x) * u
                local y = p.y + (ev.ly - p.y) * u
                local h = 0.4 + 3.2 * 4 * u * (1 - u)
                local dh = 3.2 * 4 * (1 - 2 * u)
                local dist = sqrt((ev.lx - p.x) ^ 2 + (ev.ly - p.y) ^ 2)
                local pitch = deg(atan2(dh, max(0.01, dist)))
                v.flyer:set_position(v3(x, h, -y))
                v.flyer:set_rotation(v3(0, deg(p.a), 0))
                v.flytilt:set_rotation(v3(0, 0, pitch - 90))
                burst(x, y, h, SPARK, 3, 0.8, 0.5, -1.0)
                v.shadow:set_position(v3(x, 0.006, -y))
                v.shadow:set_scale(v3(0.6, 0.001, 0.6))
            elseif u > 1 and not v.landed_fx then
                v.landed_fx = true
                -- Down on the felt: it lies on its side where it came down.
                if v.flyer then
                    v.flyer:set_position(v3(ev.lx, 0.16, -ev.ly))
                    v.flyer:set_rotation(v3(0, deg(v.p.a) + 25, 0))
                    v.flytilt:set_rotation(v3(0, 0, -90))
                    v.shadow:set_position(v3(ev.lx + 0.3, 0.006, -ev.ly))
                    v.shadow:set_scale(v3(1.3, 0.001, 0.45))
                end
                burst(ev.lx, ev.ly, 0.3, SPARK, 40, 3.0, 0.9, -2)
                burst(ev.lx, ev.ly, 0.1, DUST, 14, 2.0, 0.7)
                ring_fx(ev.lx, ev.ly, 0.05, 0.4, SPARK, 1.2, 0.5, 2.4)
                W.shake(0.3)
            end
        end
    end
    -- Marbles: down the chute, then across the felt.
    for id, ev in pairs(A.rolled) do
        local v = W.vis[id]
        if v and v.marble then
            local s = max(0, t - ev.t0) * R.MARBLE_SPEED
            s = min(s, ev.dist)
            local x, y = ev.sx + ev.ax * s, ev.sy + ev.ay * s
            local h = W.chute_height(s)
            v.marble:set_position(v3(x, h, -y)); v.core:set_position(v3(x, h, -y))
            v.core:set_rotation(v3(0, 0, -deg(s / 0.28)))
            if ev.off and s >= ev.dist then v.marble:set_enabled(false); v.core:set_enabled(false) end
        end
    end
    return due
end

------------------------------------------------------------------ per frame
function W.update(dt)
    S.t = S.t + dt
    flush_mats()
    local due = animate(dt)
    for i = #W.fx, 1, -1 do
        local f = W.fx[i]
        f.t = f.t + dt
        local u = min(1, f.t / f.life)
        local s = 1 + (f.grow or 0) * u
        f.n:set_position(v3(f.x, f.h, -f.y)); f.n:set_scale(v3(s, 1, s))
        local a = (1 - u) ^ 1.5
        pcall(material.set, f.n, "base_color", vec4(f.c[1], f.c[2], f.c[3], a))
        pcall(material.set, f.n, "emissive", v3(f.c[1] * f.e * a, f.c[2] * f.e * a, f.c[3] * f.e * a))
        if u >= 1 then kill(f.n); table.remove(W.fx, i) end
    end
    if W.arrow and W.starter then
        local e = 0.12 + 0.1 * sin(S.t * 3)
        pcall(material.set, W.arrow, "emissive", v3(e, e * 0.75, e * 0.35))
    end
    -- Camera: fixed on the bake's view. Shake turns the view a touch (a pure rotation keeps the toys glued to the
    -- pictured felt; moving the camera would slide them against it).
    S.shake = max(0, S.shake - dt * 2.5)
    local sk = S.shake
    local sx, sy = sk * 0.06 * sin(S.t * 43), sk * 0.06 * sin(S.t * 37 + 1)
    local sw, sh = W.screen_size()
    pcall(function() cam:set_fov(deg(2 * math.atan(math.tan(rad(W.CAM.vfov / 2)) * sw / max(1, sh)))) end)
    local p, l = W.CAM.pos, W.CAM.look
    cam:set_position(v3(p[1], p[2], p[3]))
    cam:look_at(v3(l[1] + sx, l[2] + sy, l[3]))
    W.vp, W.inv = cam:get_view_projection(), cam:get_inv_view_projection()
    local ok, j = pcall(function() return cam:get_jitter() end)
    W.jx, W.jy = ok and j and j.x or 0, ok and j and j.y or 0
    return due
end

------------------------------------------------------------------ picking
function W.screen_size()
    local s = runtime_ui.get_surface_size()
    return s.width or 1280, s.height or 800
end
local function flip()
    if W.flip == nil then
        local vp = W.vp or cam:get_view_projection()
        local a, b = vp * vec4(0, 6, -3, 1), vp * vec4(0, 1, -3, 1)
        W.flip = (a.y / a.w) > (b.y / b.w)    -- y-up NDC: screen y must be inverted
    end
    return W.flip
end
-- Table point (x, y) at height h -> UI pixels (jitter-free, so labels hold still).
function W.project(x, y, h)
    local vp = W.vp or cam:get_view_projection()
    local c = vp * vec4(x, h or 0, -y, 1)
    if c.w <= 1e-5 then return nil end
    local sw, sh = W.screen_size()
    local nx, ny = c.x / c.w - (W.jx or 0), c.y / c.w - (W.jy or 0)
    return (nx * 0.5 + 0.5) * sw, (flip() and (0.5 - ny * 0.5) or (0.5 + ny * 0.5)) * sh
end
-- UI pixels -> table point, by meeting the mouse ray with the felt.
function W.table_point(mx, my)
    local inv = W.inv or cam:get_inv_view_projection()
    local sw, sh = W.screen_size()
    local nx = mx / sw * 2 - 1 + (W.jx or 0)
    local ny = (flip() and (1 - my / sh * 2) or (my / sh * 2 - 1)) + (W.jy or 0)
    local a, b = inv * vec4(nx, ny, 0.25, 1), inv * vec4(nx, ny, 0.75, 1)
    local ax, ay, az = a.x / a.w, a.y / a.w, a.z / a.w
    local bx, by, bz = b.x / b.w, b.y / b.w, b.z / b.w
    if abs(by - ay) < 1e-6 then return nil end
    local t = (0 - ay) / (by - ay)
    return ax + (bx - ax) * t, -(az + (bz - az) * t)
end
-- Screen rectangle of the chalk board's writing area (its baked frame): centre and size in pixels.
function W.board_rect()
    local cx, cy = W.CAM.pos[1], -W.CAM.pos[3]
    local fx, fy = cx - W.BOARD.x, cy - W.BOARD.y
    local L = sqrt(fx * fx + fy * fy)
    fx, fy = fx / L, fy / L
    local yaw = atan2(fx, -fy)
    local function at(lx, lz)
        local ly = -0.2
        local x = W.BOARD.x + lx * cos(yaw) - ly * sin(yaw)
        local y = W.BOARD.y + lx * sin(yaw) + ly * cos(yaw)
        return W.project(x, y, lz)
    end
    local x0, y0 = at(-2.2, 4.6)
    local x1, y1 = at(2.2, 2.0)
    if not x0 or not x1 then return nil end
    return (x0 + x1) / 2, (y0 + y1) / 2, abs(x1 - x0), abs(y1 - y0)
end
function W.shake(a) S.shake = max(S.shake, a * (W.shake_scale and W.shake_scale() or 1)) end
return W
end
