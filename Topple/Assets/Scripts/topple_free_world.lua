-- Topple Free Build world: the living room (cloned from the T_room_* templates under one root that Table Run
-- switches off), every domino as one pooled scene node (body and pips as two mesh refs) posed in batches with
-- scene.set_positions / set_rotations, the animation of a run, an orbit / follow camera, picking on the room's
-- surfaces, and the room's light (the sun through the window re-aims Key, directional light 0, which casts the
-- shadows; Table Run gets it back on leave).
-- Table point (x, y) at height h is engine (x, h, -y).
return function(F)
local FW = {}
local floor, min, max, abs, sin, cos, sqrt = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt
local deg, rad, pi = math.deg, math.rad, math.pi
local atan2 = math.atan2 or math.atan
local function v3(x, y, z) return vec3(x, y, z) end
local ROOM

FW.VFOV = 40
FW.cam = { x = 0, y = 0, h = 2, yaw = -62, pitch = 36, dist = 92 }       -- live (smoothed toward goal)
FW.goal = { x = 0, y = 0, h = 2, yaw = -62, pitch = 36, dist = 92 }
FW.follow = true
local cam
local S = { t = 0, shake = 0 }

------------------------------------------------------------------ materials (template writes are replayed: engine quirk)
local mat_q = {}
local function mset(n, k, v, tex)
    local f = tex and material.set_texture or material.set
    pcall(f, n, k, v)
    mat_q[#mat_q + 1] = { n = n, k = k, v = v, f = f, c = 0 }
end
local function flush_mats()
    for i = #mat_q, 1, -1 do
        local q = mat_q[i]
        q.c = q.c + 1
        if q.c == 2 or q.c == 6 or q.c == 20 then pcall(q.f, q.n, q.k, q.v) end
        if q.c >= 20 then table.remove(mat_q, i) end
    end
end
local function look(n, L)
    local c = L.color or { 1, 1, 1 }
    mset(n, "base_color", vec4(c[1], c[2], c[3], 1))
    local e = L.emis or { 0, 0, 0 }
    mset(n, "emissive", v3(e[1], e[2], e[3]))
    mset(n, "metallic", L.metal or 0)
    mset(n, "roughness", L.rough or 0.5)
    if L.tex then mset(n, "base_color", L.tex, true) end
    if L.emis_tex then mset(n, "emissive", L.emis_tex, true) end
    if L.transmission then
        -- Glass: Transmission meshes cast no depth shadow, only a tint (1 - transmittance, which follows the base
        -- colour), so a white, fully transmissive pane lets the sun through and still shows the garden (emissive).
        pcall(material.set_render_type, n, "transmission")
        mset(n, "transmission", L.transmission)
    end
end

-- The dominoes' paints (glossy enamel), set on their template meshes each time Free Build opens (Table Run's toys
-- share those meshes and set their own).
local PAINT = { brick = { 0.5, 0.13, 0.07 }, mustard = { 0.78, 0.52, 0.13 }, sage = { 0.32, 0.44, 0.3 }, navy = { 0.1, 0.16, 0.32 },
    cream = { 0.84, 0.77, 0.62 } }
local function paint_templates()
    for name, c in pairs(PAINT) do
        local t = scene.find_model and scene.find_model("T_domino_" .. name)
        if t then look(t, { color = c, rough = 0.3 }) end
    end
    for k = 0, 9 do
        local d = scene.find_model and scene.find_model("T_pips_" .. k .. "_dark")
        if d then look(d, { color = { 0.03, 0.03, 0.03 }, rough = 0.35 }) end
        local l = scene.find_model and scene.find_model("T_pips_" .. k .. "_light")
        if l then look(l, { color = { 0.88, 0.82, 0.68 }, rough = 0.35 }) end
    end
end

------------------------------------------------------------------ templates
local MESH = {}
local function mesh_of(name)
    if MESH[name] == nil then
        local n = scene.find_model and scene.find_model("T_" .. name)
        local refs = n and n:get_mesh_refs()
        MESH[name] = (refs and refs[1]) or false
    end
    return MESH[name] or nil
end
local function hide_node(n, on)
    if not pcall(function() n:set_visible(on) end) then pcall(function() n:set_enabled(on) end) end
end

------------------------------------------------------------------ the room
-- How far above its surface a flat board sits: clear of the scanned top's highest facet (8.823 on the coffee table)
-- even with a ball resting the physics engine's 0.02 deep in it, or the facets nudge the ball sideways.
local BOARD_LIFT = 0.05
local function board_lift(h)
    for _, s in ipairs(ROOM.surfaces) do
        if s.board and abs(s.h - h) < 1e-3 then return BOARD_LIFT end
    end
    return 0
end
local room_root, room_nodes, decor = nil, {}, { L = {}, R = {}, B = {}, F = {} }
local function build_room()
    room_root = scene.add_empty_node("FreeRoom")
    for _, L in ipairs(ROOM.pieces) do
        local m = mesh_of(L.name)
        if m then
            local n = scene.add_empty_node("fr_" .. L.name)
            n:add_mesh_ref(m)
            n:set_parent(room_root)
            look(n, L)
            room_nodes[#room_nodes + 1] = n
            if L.name == "room_shade" then FW.shade, FW.shade_emis = n, L.emis end
            if L.group and not L.name:match("^room_wall_") then table.insert(decor[L.group], n) end
        end
    end
    -- The surfaces you build on are perfectly flat for the balls: the scanned tops have tiny facets that would nudge one.
    FW.boards = {}
    for _, s in ipairs(ROOM.surfaces) do
        if s.board then
            local n = primitives.cube(1)
            n:set_parent(room_root)
            n:set_scale(v3(s.x1 - s.x0, 0.2, s.y1 - s.y0))
            n:set_position(v3((s.x0 + s.x1) / 2, s.h + BOARD_LIFT - 0.1, -(s.y0 + s.y1) / 2))
            hide_node(n, false)
            FW.boards[#FW.boards + 1] = n
        end
    end
end

------------------------------------------------------------------ lights
local saved_lights
local function find_light(name)
    local ok, r = pcall(lights.find, name)     -- finds by substring ("Lamp" also matches "RoomLamp"): take the exact one
    if not ok or not r then return nil end
    for _, l in ipairs(r) do if l.name == name then return l end end
    return nil
end
local function node_named(name) return scene.find_model and scene.find_model(name) or nil end
-- Euler degrees (R = Rz * Ry * Rx) for a node whose local -Z points along d (engine axes): lights shine along -Z.
local function euler_toward(dx, dy, dz)
    local L = sqrt(dx * dx + dy * dy + dz * dz)
    local zx, zy, zz = -dx / L, -dy / L, -dz / L
    local ux, uy, uz = 0, 1, 0
    if abs(zy) > 0.98 then ux, uy, uz = 0, 0, 1 end
    local xx, xy, xz = uy * zz - uz * zy, uz * zx - ux * zz, ux * zy - uy * zx
    local xl = sqrt(xx * xx + xy * xy + xz * xz)
    xx, xy, xz = xx / xl, xy / xl, xz / xl
    local yz = zx * xy - zy * xx
    local ry = math.asin(max(-1, min(1, -xz)))
    local rx = atan2(yz, zz)
    local rz = atan2(xy, xx)
    return deg(rx), deg(ry), deg(rz)
end
FW.euler_toward = euler_toward

local function light_on(spec, name, kind)
    local l = find_light(name)
    if not l then return end
    if spec.dir then
        local n = node_named(name)
        local rx, ry, rz = euler_toward(spec.dir[1], spec.dir[2], spec.dir[3])
        if n then n:set_rotation(v3(rx, ry, rz)) end
    end
    if spec.color then pcall(lights.set_property, l.type, l.index, "color", v3(spec.color[1], spec.color[2], spec.color[3])) end
    pcall(lights.set_property, l.type, l.index, "intensity", spec.intensity or 0)
    if spec.radius and kind == "point" then pcall(lights.set_property, l.type, l.index, "radius", spec.radius) end
end

local function save_lights()
    if saved_lights then return end
    saved_lights = {}
    for _, name in ipairs({ "Key", "Fill", "Lamp", "RoomLamp" }) do
        local l = find_light(name)
        if l then
            local rec = { l = l }
            local list = ({ directional = lights.get_directional_lights, spot = lights.get_spot_lights, point = lights.get_point_lights })[l.type]
            local ok, all = pcall(list)
            local info = ok and all and all[l.index + 1]
            if info then rec.color, rec.intensity = info.color, info.intensity end
            local n = node_named(name)
            if n then rec.node, rec.rot = n, n:get_rotation() end
            saved_lights[name] = rec
        end
    end
end
local function restore_lights()
    for _, rec in pairs(saved_lights or {}) do
        if rec.node and rec.rot then rec.node:set_rotation(rec.rot) end
        if rec.color then pcall(lights.set_property, rec.l.type, rec.l.index, "color", rec.color) end
        if rec.intensity then pcall(lights.set_property, rec.l.type, rec.l.index, "intensity", rec.intensity) end
    end
end

------------------------------------------------------------------ look
FW.LOOK = { tonemapping = true, IBL = true, IBL_intensity = 1.35, shadows = true, shadow_distance = 420, ssr = false,
    dof = false, color_grading = false, motion_blur = false, fog = false, taa = true, fxaa = false, bloom_strength = 0.18,
    cas_sharpening = false, render_scale = 1.0, shadow_map_size = 4096, lod_enabled = false }
-- One shadow map over the whole room, wherever the camera is (the engine's fixed shadow bounds): camera-fitted
-- cascades disagreed with each other in this small, enclosed room, so the sunlight through the window came and went
-- as the camera moved. The fade distance is pushed out of reach (shadow_distance) so nothing in the room fades.
-- LODs are off: the engine swaps in simplified meshes with distance, and the simplified window wall and frame let less
-- sun in as the camera zoomed out (measured: about 40% less sunlit floor at distance 110-165; shadow_lod_bias 0 did not
-- change it). The room and the dominoes are light enough to draw at full detail.
local function shadow_bounds()
    local B = ROOM.bounds
    local hx, hy, hh = (B.x1 - B.x0) / 2, (B.y1 - B.y0) / 2, ROOM.wall_h / 2
    return (B.x0 + B.x1) / 2, hh, -(B.y0 + B.y1) / 2, sqrt(hx * hx + hy * hy + hh * hh) + 1
end
function FW.apply_look(cfg)
    ROOM = ROOM or F.ROOM
    for k, v in pairs(FW.LOOK) do
        if not (cfg and k == "shadows" and cfg.quality and cfg.quality < 2) then pcall(settings.set, k, v) end
    end
    local x, y, z, r = shadow_bounds()
    for k, v in pairs({ shadow_bounds_x = x, shadow_bounds_y = y, shadow_bounds_z = z, shadow_bounds_radius = r }) do pcall(settings.set, k, v) end
    pcall(settings.set, "shadow_fixed_bounds", true)
end

------------------------------------------------------------------ dominoes: a pool of nodes per paint
local pools, made = {}, 0
local vis = {}           -- piece id -> { n, paint, p }
FW.vis = vis
local function pips_for(paint, k) return "pips_" .. (k % 10) .. (paint == "navy" and "_light" or "_dark") end
local function grow(paint, n)
    local pool = pools[paint]
    local body = mesh_of("domino_" .. paint)
    for _ = 1, n do
        made = made + 1
        local nd = scene.add_empty_node("fd_" .. made)
        if body then nd:add_mesh_ref(body) end
        local pm = mesh_of(pips_for(paint, made * 7))
        if pm then nd:add_mesh_ref(pm) end
        hide_node(nd, false)
        pool[#pool + 1] = nd
    end
end
local function take(paint)
    local pool = pools[paint]
    if not pool then pool = {}; pools[paint] = pool end
    if #pool == 0 then grow(paint, 128) end
    local nd = pool[#pool]
    pool[#pool] = nil
    return nd
end
local function give(paint, nd)
    hide_node(nd, false)
    local pool = pools[paint]
    pool[#pool + 1] = nd
end
FW.made = function() return made end

-- Batched poses: one crossing for all the nodes that move this frame.
local BP, BR, bn = {}, {}, 0
local function queue_pose(nd, p, yaw, flip, th)
    local x, y, z, rx, ry, rz = F.pose(p, yaw, flip, th)
    local i = bn * 4
    bn = bn + 1
    BP[i + 1], BP[i + 2], BP[i + 3], BP[i + 4] = nd, x, y, z
    BR[i + 1], BR[i + 2], BR[i + 3], BR[i + 4] = nd, rx, ry, rz
end
local function flush_poses()
    if bn == 0 then return end
    if scene.set_positions and scene.set_rotations then
        scene.set_positions(BP, bn)
        scene.set_rotations(BR, bn)
    else
        for i = 0, bn - 1 do
            local k = i * 4
            BP[k + 1]:set_position(v3(BP[k + 2], BP[k + 3], BP[k + 4]))
            BP[k + 1]:set_rotation(v3(BR[k + 2], BR[k + 3], BR[k + 4]))
        end
    end
    bn = 0
end

-- The engine's rigid bodies (Jolt). Absent in the tests, which then use the rules' own stepping.
local function can_live() return physics ~= nil and physics.add_body ~= nil and physics.is_simulating ~= nil and physics.is_simulating() end
FW.can_live = can_live
local function body_off(n) if physics and physics.remove_body then pcall(physics.remove_body, n) end end
local WOOD = { friction = 0.5, restitution = 0.4 }

-- Balls: a few nodes, pooled like the dominoes.
local ball_vis, ball_pool = {}, {}
local function ball_to(n, x, y, z) n:set_position(v3(x, z + board_lift(z) + F.BALL.r, -y)) end
local function ball_give(id, v)
    body_off(v.n)
    hide_node(v.n, false)
    ball_pool[#ball_pool + 1] = v.n
    ball_vis[id] = nil
end
local function ball_take()
    local n = table.remove(ball_pool)
    if not n then
        n = primitives.uv_sphere(F.BALL.r, 40, 24)
        look(n, { color = { 0.72, 0.09, 0.05 }, rough = 0.22 })
    end
    hide_node(n, true)
    return n
end

-- The table lamp, for switches: the light and the glow of its shade. It is always on when a build stands.
function FW.set_lamp(on)
    FW.lamp_off = not on
    light_on(on and ROOM.lamp or { intensity = 0 }, "RoomLamp", "point")
    local e = on and FW.shade_emis or { 0, 0, 0 }
    if FW.shade and e then mset(FW.shade, "emissive", v3(e[1], e[2], e[3])) end
end
local function lamp_back_on() if FW.lamp_off then FW.set_lamp(true) end end

-- Switches: a block with a button that sinks and turns green; a brass block works the lamp.
local switch_vis, switch_pool = {}, {}
local function switch_look(v)
    look(v.base, v.p.lamp and { color = { 0.86, 0.62, 0.3 }, metal = 1, rough = 0.25 } or { color = { 0.34, 0.19, 0.09 }, rough = 0.5 })
    v.lamp = v.p.lamp
end
local function switch_press(v, on)
    v.pressed = on
    local p, r = v.p, F.SWITCH.r
    look(v.knob, on and { color = { 0.14, 0.62, 0.2 }, rough = 0.3, emis = { 0.06, 0.32, 0.1 } } or { color = { 0.72, 0.09, 0.05 }, rough = 0.25 })
    v.knob:set_position(v3(p.x, p.z + (on and 0.42 or 0.6), -p.y))
    v.base:set_position(v3(p.x, p.z + r / 2, -p.y))
end
local function switch_show(p)
    local set = table.remove(switch_pool)
    if not set then
        local r = F.SWITCH.r
        set = { base = primitives.cube(1), knob = primitives.uv_sphere(r * 0.62, 28, 18) }
        set.base:set_scale(v3(2 * r, r, 2 * r))
    end
    hide_node(set.base, true); hide_node(set.knob, true)
    local v = { p = p, base = set.base, knob = set.knob, set = set }
    switch_look(v)
    switch_press(v, false)
    return v
end
local function switch_give(id, v)
    body_off(v.base)
    hide_node(v.base, false); hide_node(v.knob, false)
    switch_pool[#switch_pool + 1] = v.set
    switch_vis[id] = nil
end

-- Swings: a ball, a string and a stand (or a bracket off the shelf), made of primitives and pooled as sets.
local swing_vis, swing_pool = {}, {}
local function swing_pose(v, th, bob_is_body)
    local p = v.p
    local x, y, cz = F.swing_bob(p, th)
    if not bob_is_body then v.set.bob:set_position(v3(x, cz, -y)) end
    local top = F.swing_top(p)
    v.set.str:set_position(v3((x + p.x) / 2, (cz + top) / 2, -(y + p.y) / 2))
    local _, _, _, rx, ry, rz = F.pose(p, p.a, false, -th)
    v.set.str:set_rotation(v3(rx, ry, rz))
end
local function swing_set()
    local set = table.remove(swing_pool)
    if not set then
        local wood = { color = { 0.34, 0.19, 0.09 }, rough = 0.5 }
        set = { bob = primitives.uv_sphere(F.SWING.r, 40, 24), str = primitives.cube(1), bar = primitives.cube(1), p1 = primitives.cube(1), p2 = primitives.cube(1),
            latch = primitives.cube(1), cord = primitives.cube(1) }
        look(set.latch, { color = { 0.72, 0.09, 0.05 }, rough = 0.3 })
        look(set.cord, { color = { 0.82, 0.76, 0.62 }, rough = 0.9 })
        look(set.bob, { color = { 0.86, 0.62, 0.3 }, metal = 1, rough = 0.25 })
        look(set.str, { color = { 0.82, 0.76, 0.62 }, rough = 0.9 })
        look(set.bar, wood); look(set.p1, wood); look(set.p2, wood)
    end
    return set
end
local function swing_show(p)
    local set, S = swing_set(), F.SWING
    local top = F.swing_top(p)
    hide_node(set.bob, true); hide_node(set.str, true); hide_node(set.bar, true)
    set.str:set_scale(v3(0.05, p.L, 0.05))
    if p.hang == "stand" then
        local x1, y1, x2, y2 = F.swing_posts(p.x, p.y, p.a)
        for _, c in ipairs({ { set.p1, x1, y1 }, { set.p2, x2, y2 } }) do
            hide_node(c[1], true)
            c[1]:set_scale(v3(2 * S.post_r, top - p.z, 2 * S.post_r))
            c[1]:set_position(v3(c[2], (top + p.z) / 2, -c[3]))
        end
        set.bar:set_scale(v3(2 * (S.post + S.post_r), 0.24, 0.24))
        set.bar:set_rotation(v3(0, deg(p.a + pi / 2), 0))
        set.bar:set_position(v3(p.x, top, -p.y))
    else
        hide_node(set.p1, false); hide_node(set.p2, false)
        local _, _, shelf = F.swing_mount(p.x, p.y, p.z)
        local d = shelf.y0 + 0.8 - p.y
        set.bar:set_rotation(v3(0, 0, 0))
        set.bar:set_scale(v3(0.3, 0.24, d))
        set.bar:set_position(v3(p.x, top + 0.12, -(p.y + d / 2)))
    end
    -- The latch, under the held bob, and the cord that holds it down.
    local s_r = F.SWITCH.r
    hide_node(set.latch, true); hide_node(set.cord, true)
    set.latch:set_scale(v3(2 * s_r, 2 * s_r, 2 * s_r))
    set.latch:set_position(v3(p.lx, p.z + s_r, -p.ly))
    local v = { p = p, set = set }
    swing_pose(v, -p.amp)
    local _, _, held = F.swing_bob(p, -p.amp)
    local c0 = p.z + 2 * s_r
    set.cord:set_scale(v3(0.04, max(0.05, held - c0), 0.04))
    set.cord:set_position(v3(p.lx, (held + c0) / 2, -p.ly))
    return v
end
local function swing_give(id, v)
    for _, n in pairs(v.set) do body_off(n); hide_node(n, false) end
    swing_pool[#swing_pool + 1] = v.set
    swing_vis[id] = nil
end

-- Ramps: one wooden block per step, the blocks pooled.
local ramp_vis, ramp_pool = {}, {}
local function ramp_show(p)
    local v = { p = p, n = {} }
    -- What a ball rolls on: one smooth board along the steps' near corners (a hair above them), starting on the floor.
    local slope = table.remove(ramp_pool) or primitives.cube(1)
    local t_ = 0.3
    local c_ = math.cos(math.atan(p.slope))
    local s_ = math.sin(math.atan(p.slope))
    local len = p.L / c_
    local mid = p.L / 2 - p.d
    local lift = max(0.03, board_lift(p.z1))                                   -- its top meets a flat board at the same height
    local h = p.z0 + p.rise + p.slope * mid + lift - t_ / 2 * c_
    local off = t_ / 2 * s_
    if p.on_x then
        slope:set_scale(v3(len, t_, F.RAMP.width))
        slope:set_rotation(v3(0, 0, deg(math.atan(p.slope)) * p.sgn))
        slope:set_position(v3(p.x0 + p.sgn * (mid + off), h, -p.y0))
    else
        slope:set_scale(v3(F.RAMP.width, t_, len))
        slope:set_rotation(v3(deg(math.atan(p.slope)) * p.sgn, 0, 0))
        slope:set_position(v3(p.x0, h, -(p.y0 + p.sgn * (mid + off))))
    end
    hide_node(slope, false)
    v.slope = slope
    for k, st in ipairs(p.steps) do
        local n = table.remove(ramp_pool)
        if not n then
            n = primitives.cube(1)
            look(n, { color = { 0.5, 0.31, 0.15 }, rough = 0.55 })
        end
        hide_node(n, true)
        n:set_rotation(v3(0, 0, 0))
        n:set_scale(v3(st.x1 - st.x0, st.h - p.z0, st.y1 - st.y0))
        n:set_position(v3((st.x0 + st.x1) / 2, (st.h + p.z0) / 2, -(st.y0 + st.y1) / 2))
        v.n[k] = n
    end
    return v
end
local function ramp_give(id, v)
    body_off(v.slope)
    hide_node(v.slope, false); ramp_pool[#ramp_pool + 1] = v.slope
    for _, n in ipairs(v.n) do body_off(n); hide_node(n, false); ramp_pool[#ramp_pool + 1] = n end
    ramp_vis[id] = nil
end

local last_rev, last_board
-- Make the nodes match the board: new dominoes stand, removed ones go back to the pool.
function FW.sync(board, force)
    if not force and board == last_board and board.rev == last_rev then return end
    last_board, last_rev = board, board.rev
    FW.board = board
    for id, v in pairs(ramp_vis) do
        if board.ramps[id] ~= v.p then ramp_give(id, v) end
    end
    for id, p in pairs(board.ramps) do
        if not ramp_vis[id] then ramp_vis[id] = ramp_show(p) end
    end
    for id, v in pairs(vis) do
        local p = board.pieces[id]
        if p ~= v.p then
            give(v.paint, v.n)
            vis[id] = nil
        end
    end
    for id, p in pairs(board.pieces) do
        if not vis[id] then
            local paint = p.paint or "cream"
            local nd = take(paint)
            vis[id] = { n = nd, paint = paint, p = p }
            queue_pose(nd, p, p.a, false, 0)
            hide_node(nd, true)
        end
    end
    for id, v in pairs(ball_vis) do
        if board.balls[id] ~= v.p then ball_give(id, v) end
    end
    for id, p in pairs(board.balls) do
        if not ball_vis[id] then
            ball_vis[id] = { n = ball_take(), p = p }
            ball_to(ball_vis[id].n, p.x, p.y, p.z)
        end
    end
    for id, v in pairs(swing_vis) do
        if board.swings[id] ~= v.p then swing_give(id, v) end
    end
    for id, p in pairs(board.swings) do
        if not swing_vis[id] then swing_vis[id] = swing_show(p) end
    end
    for id, v in pairs(switch_vis) do
        if board.switches[id] ~= v.p then switch_give(id, v) end
    end
    for id, p in pairs(board.switches) do
        local v = switch_vis[id]
        if not v then switch_vis[id] = switch_show(p)
        elseif v.lamp ~= p.lamp then switch_look(v) end
    end
    flush_poses()
end

function FW.clear()
    for id, v in pairs(vis) do give(v.paint, v.n); vis[id] = nil end
    for id, v in pairs(ball_vis) do ball_give(id, v) end
    for id, v in pairs(swing_vis) do swing_give(id, v) end
    for id, v in pairs(switch_vis) do switch_give(id, v) end
    for id, v in pairs(ramp_vis) do ramp_give(id, v) end
    lamp_back_on()
    last_rev, last_board = nil, nil
    FW.A = nil
end

-- Every domino standing again.
function FW.stand_all()
    for _, v in pairs(vis) do queue_pose(v.n, v.p, v.p.a, false, 0) end
    for _, v in pairs(ball_vis) do
        body_off(v.n)
        v.n:set_rotation(v3(0, 0, 0))
        ball_to(v.n, v.p.x, v.p.y, v.p.z)
        v.last = nil
    end
    for _, v in pairs(swing_vis) do
        body_off(v.set.bob)
        v.set.bob:set_rotation(v3(0, 0, 0))
        hide_node(v.set.cord, true)
        v.live, v.last = nil, nil
        swing_pose(v, -v.p.amp)
    end
    if physics and physics.set_time_scale then pcall(physics.set_time_scale, 1) end
    for _, v in pairs(switch_vis) do if v.pressed then switch_press(v, false) end end
    lamp_back_on()
    FW.settle = 2           -- a new body starts from the scene's per-frame transforms, so these moves need frames to land
    flush_poses()
    FW.A = nil
end

------------------------------------------------------------------ a run
local fall_angle = F.fall_angle
FW.fall_angle = fall_angle

-- Everything solid for this run gets its rigid body (no-op for the ones that have one).
local function arm_bodies()
    local B, S_ = F.BALL, F.SWING
    for _, v in pairs(ball_vis) do
        v.last = nil
        physics.add_body(v.n, "dynamic", "sphere", { mass = B.mass, friction = 0.5, restitution = B.bounce })
    end
    for _, v in pairs(ramp_vis) do
        physics.add_body(v.slope, "static", "box", WOOD)
        for _, n in ipairs(v.n) do physics.add_body(n, "static", "box", WOOD) end
    end
    for _, v in pairs(switch_vis) do physics.add_body(v.base, "static", "box", WOOD) end
    for _, v in pairs(swing_vis) do
        physics.add_body(v.set.latch, "static", "box", WOOD)
        if v.p.hang == "stand" then
            physics.add_body(v.set.p1, "static", "box", WOOD)
            physics.add_body(v.set.p2, "static", "box", WOOD)
        end
        physics.add_body(v.set.bob, "kinematic", "sphere", { mass = S_.mass, friction = 0.4, restitution = 0.5 })
    end
end

-- What the rules call when a domino kicks a ball or a latch lets a bob go.
function FW.hooks()
    return {
        ball = function(p, t, dx, dy, speed)
            local v = ball_vis[p.id]
            -- The rules' kick is the speed left once rolling; here the engine does the sliding, so it starts at the full speed.
            if v then physics.set_velocity(v.n, dx * speed * 7 / 5, 0, -dy * speed * 7 / 5) end
        end,
        swing = function(p, t)
            local v = swing_vis[p.id]
            if not v then return end
            local x, y, cz = F.swing_bob(p, -p.amp)
            physics.set_body_type(v.set.bob, "dynamic")
            physics.add_joint(v.set.bob, "hinge", { anchor = v3(p.x - x, F.swing_top(p) - cz, -(p.y - y)), axis = v3(-p.ay, 0, -p.ax) })
            hide_node(v.set.cord, false)
            v.live, v.t0, v.last = true, t, nil
            v.period = 2 * pi * sqrt(p.L / F.BALL.g)
            FW.ball_bump = true
        end,
    }
end

-- Each frame of a live run: rolling resistance and air on the balls, and what the bodies touch fed to the domino wave.
local function tick_live(A, t, dt)
    local run, B, S_ = A.run, F.BALL, F.SWING
    local chain = run.pending() or t < (A.res.duration or 0)       -- (the last dominoes are still falling)
    if chain then A.chain_t = t end
    local busy = chain
    local fx, fy, fz
    for _, v in pairs(ball_vis) do
        local pos, vel = v.n:get_world_position(), physics.get_velocity(v.n)
        if pos and vel then
            local x, y, c = pos.x, -pos.z, pos.y
            local vx, vy, vz = vel.x, -vel.z, vel.y
            local speed = sqrt(vx * vx + vy * vy + vz * vz)
            if v.last and speed > 0.5 then
                local nx, ny = run.strike_ball(v.last[1], v.last[2], v.last[3], x, y, c, vx, vy, vz, t, B.min_hit)
                if nx then
                    local vn = vx * nx + vy * ny
                    if vn < 0 then
                        vx, vy = vx - (1 + B.rebound) * vn * nx, vy - (1 + B.rebound) * vn * ny
                        physics.set_velocity(v.n, vx, vz, -vy)
                        FW.ball_bump = true
                    end
                end
            end
            v.last = { x, y, c }
            local hv = sqrt(vx * vx + vy * vy)
            if abs(vz) < 4 and hv > 1e-3 then
                local j = B.mass * min(hv, B.drag * dt) / hv
                physics.apply_impulse(v.n, -vx * j, 0, vy * j)
            end
            if speed > 1 then
                local j = B.mass * B.air * speed * dt
                physics.apply_impulse(v.n, -vx * j, -vz * j, vy * j)
            end
            -- Sitting still it only trembles on its contact: that is rest.
            if hv < 0.25 and abs(vz) < 4 then
                physics.set_velocity(v.n, vx, 0, -vy)
            else
                busy = true
                fx, fy, fz = x, y, c - B.r
            end
        end
    end
    for _, v in pairs(swing_vis) do
        if v.live then
            local p = v.p
            local pos, vel = v.set.bob:get_world_position(), physics.get_velocity(v.set.bob)
            if pos and vel then
                local x, y, c = pos.x, -pos.z, pos.y
                local along = (x - p.x) * p.ax + (y - p.y) * p.ay
                swing_pose(v, math.atan2(along, F.swing_top(p) - c), true)
                if v.last then run.strike_bob(v.last[1], v.last[2], v.last[3], x, y, c, vel.x, -vel.z, vel.y, t, S_.min_hit) end
                v.last = { x, y, c }
                if t - v.t0 < v.period * 1.25 then
                    busy = true
                    fx, fy, fz = x, y, c - S_.r
                end
            end
        end
    end
    A.quiet = busy and 0 or (A.quiet or 0) + dt
    -- The time limit is only for a ball that never settles: a chain is finite, so however long it runs it finishes.
    if A.quiet > 0.4 or t - (A.chain_t or 0) > 60 then
        A.ended = true
        run.finish()
        A.res.duration = t
    end
    return fx, fy, fz
end

function FW.set_time(s) if physics and physics.set_time_scale then pcall(physics.set_time_scale, s) end end

function FW.play(res, run)
    local wait = run and (FW.settle or 0) > 0        -- "Again": the stand-up happened this very frame
    if run and not wait then arm_bodies() end
    FW.A = { res = res, t = 0, next = 1, active = {}, wob = {}, next_w = 1, clacked = {}, recent = {}, landed = 0, ball_i = {}, bump_i = {}, swing_i = {}, sbump_i = {}, switch_i = 1, run = run, arm_pending = wait or nil }
end
function FW.playing()
    local A = FW.A
    if A and A.run then return not A.ended end
    return A ~= nil and A.t <= (A.res.duration or 0) + 0.4
end
function FW.run_time() return FW.A and FW.A.t or 0 end

-- Move each ball along its worked-out path; returns where a ball is in flight (for the follow camera).
local function pose_balls(A, t)
    local bx, by, bz
    for k, b in ipairs(A.res.balls) do
        local v = ball_vis[b.id]
        local P = b.pts
        local i = A.ball_i[k] or 1
        while P[i + 4] and P[i + 4] <= t do i = i + 4 end
        A.ball_i[k] = i
        if t >= b.t0 then
            local x, y, z = P[i + 1], P[i + 2], P[i + 3]
            if P[i + 4] then
                local u = max(0, min(1, (t - P[i]) / max(1e-4, P[i + 4] - P[i])))
                x, y, z = x + (P[i + 5] - x) * u, y + (P[i + 6] - y) * u, z + (P[i + 7] - z) * u
            end
            if v then ball_to(v.n, x, y, z) end
            if t <= b.t_end then bx, by, bz = x, y, z end
        end
        local j = A.bump_i[k] or 1
        while b.bumps[j] and b.bumps[j] <= t do j = j + 1; FW.ball_bump = true end
        A.bump_i[k] = j
    end
    return bx, by, bz
end
-- The same for swings.
local function pose_swings(A, t)
    local bx, by, bz
    for k, s in ipairs(A.res.swings) do
        local v = swing_vis[s.id]
        local P = s.pts
        local i = A.swing_i[k] or 1
        while P[i + 2] and P[i + 2] <= t do i = i + 2 end
        A.swing_i[k] = i
        if t >= s.t0 then
            local th = P[i + 1]
            if P[i + 2] then th = th + (P[i + 3] - th) * max(0, min(1, (t - P[i]) / max(1e-4, P[i + 2] - P[i]))) end
            if v then
                hide_node(v.set.cord, false)
                swing_pose(v, th)
                if t <= s.t_end then bx, by, bz = F.swing_bob(v.p, th) end
            end
        end
        local j = A.sbump_i[k] or 1
        while s.bumps[j] and s.bumps[j] <= t do j = j + 1; FW.ball_bump = true end
        A.sbump_i[k] = j
    end
    return bx, by, bz
end
function FW.take_bump()
    local b = FW.ball_bump
    FW.ball_bump = nil
    return b
end

local DUST = { 0.62, 0.55, 0.45 }
local function animate(dt)
    local A = FW.A
    if not A then return nil end
    if A.arm_pending then
        if FW.settle > 0 then return nil end
        A.arm_pending = nil
        arm_bodies()
    end
    A.t = A.t + dt
    local t = A.t
    local live_x, live_y, live_h
    if A.run and not A.ended then
        A.run.advance(t)
        live_x, live_y, live_h = tick_live(A, t, dt)
    end
    local order = A.res.order
    local due = {}
    while A.next <= #order and order[A.next].t <= t do
        local f = order[A.next]
        A.active[#A.active + 1] = f
        A.recent[#A.recent + 1] = f
        A.next = A.next + 1
    end
    local act = A.active
    local i = 1
    local bursts = 0
    while i <= #act do
        local f = act[i]
        local v = vis[f.id]
        if v then queue_pose(v.n, v.p, f.yaw, f.flip, fall_angle(f, t)) end
        if not A.clacked[f.id] and t >= f.tc then
            A.clacked[f.id] = true
            due[#due + 1] = f
            if v and f.final >= rad(85) and bursts < 2 and math.random() < 0.06 and FW.particle_scale and FW.particle_scale() > 0 then
                bursts = bursts + 1
                local p = v.p
                pcall(particles.emit_burst, { position = v3(p.x + f.dx * 0.9, p.z + 0.05, -(p.y + f.dy * 0.9)), velocity = v3(0, 0.4, 0),
                    color_start = vec4(DUST[1], DUST[2], DUST[3], 0.35), color_end = vec4(DUST[1], DUST[2], DUST[3], 0), gravity = v3(0, -0.6, 0),
                    count = max(1, floor(5 * FW.particle_scale())), size_min = 0.03, size_max = 0.08, life_min = 0.4, life_max = 0.9,
                    spawn_radius = 0.3, noise_strength = 0.6, drag = 3 })
            end
        end
        if t > f.t_end + 0.25 then
            if v then queue_pose(v.n, v.p, f.yaw, f.flip, f.final) end
            act[i] = act[#act]
            act[#act] = nil
        else
            i = i + 1
        end
    end
    -- Dominoes pushed edge-on rock and settle.
    local ev = A.res.events
    while A.next_w <= #ev and ev[A.next_w].t <= t do
        A.wob[#A.wob + 1] = ev[A.next_w]
        A.next_w = A.next_w + 1
    end
    for k = #A.wob, 1, -1 do
        local e = A.wob[k]
        local v = vis[e.id]
        local u = t - e.t
        if v then queue_pose(v.n, v.p, v.p.a, false, rad(8) * sin(u * 22) * math.exp(-u * 5)) end
        if u > 0.8 then
            if v then queue_pose(v.n, v.p, v.p.a, false, 0) end
            table.remove(A.wob, k)
        end
    end
    -- The front of the chain, for the follow camera: where dominoes started falling in the last 0.3 s.
    local rc = A.recent
    local sx, sy, sz, n = 0, 0, 0, 0
    local j = 1
    while j <= #rc do
        local f = rc[j]
        if t - f.t > 0.3 then
            rc[j] = rc[#rc]; rc[#rc] = nil
        else
            local v = vis[f.id]
            if v then sx, sy, sz, n = sx + v.p.x, sy + v.p.y, sz + v.p.z, n + 1 end
            j = j + 1
        end
    end
    local bx, by, bz = pose_balls(A, t)
    local sw = A.res.switches
    while sw[A.switch_i] and sw[A.switch_i].t <= t do
        local e = sw[A.switch_i]
        A.switch_i = A.switch_i + 1
        if switch_vis[e.id] then switch_press(switch_vis[e.id], true) end
        if e.lamp_on ~= nil then FW.set_lamp(e.lamp_on) end
        FW.ball_bump = true
    end
    local sx2, sy2, sz2 = pose_swings(A, t)
    if not bx then bx, by, bz = sx2, sy2, sz2 end
    if not bx then bx, by, bz = live_x, live_y, live_h end
    if n > 0 then A.front = { x = sx / n, y = sy / n, h = sz / n }
    elseif bx then A.front = { x = bx, y = by, h = bz } end
    return due
end

------------------------------------------------------------------ markers: the start arrow and the cursor ring
local arrow, ring
function FW.set_starter(p, dir)
    if not arrow then
        local m = mesh_of("arrow")
        if not m then return end
        arrow = scene.add_empty_node("free_arrow")
        arrow:add_mesh_ref(m)
        look(arrow, { color = { 0.86, 0.62, 0.30 }, metal = 1, rough = 0.25, emis = { 0.25, 0.17, 0.06 } })
    end
    if not p then hide_node(arrow, false); FW.starter = nil; return end
    hide_node(arrow, true)
    local ax, ay = cos(p.a) * dir, sin(p.a) * dir
    arrow:set_position(v3(p.x - ax * 0.62, p.z, -(p.y - ay * 0.62)))
    arrow:set_rotation(v3(0, deg(atan2(ay, ax)), 0))
    FW.starter = p
end

function FW.set_cursor(x, y, h, ok, radius)
    if not ring then
        ring = primitives.torus(1.0, 0.035, 72, 8)
        pcall(material.set_render_type, ring, "alpha_blend")
    end
    if not x then hide_node(ring, false); return end
    hide_node(ring, true)
    local r = radius or 0.42
    ring:set_position(v3(x, h + 0.02, -y))
    ring:set_scale(v3(r, 1, r))
    local c = ok and { 1.0, 0.82, 0.45 } or { 1.0, 0.35, 0.25 }
    pcall(material.set, ring, "base_color", vec4(c[1], c[2], c[3], 0.85))
    pcall(material.set, ring, "emissive", v3(c[1] * 1.6, c[2] * 1.6, c[3] * 1.6))
end

------------------------------------------------------------------ camera
function FW.reset_camera()
    local c = ROOM.camera
    for _, k in ipairs({ "yaw", "pitch", "dist" }) do FW.goal[k] = c[k] end
    FW.goal.x, FW.goal.y, FW.goal.h = c.target[1], c.target[2], c.target[3]
    for k, v in pairs(FW.goal) do FW.cam[k] = v end
end
function FW.orbit(dx, dy)
    FW.goal.yaw = FW.goal.yaw - dx * 0.25
    FW.goal.pitch = max(8, min(89, FW.goal.pitch + dy * 0.2))
end
local function clamp_goal()
    local g, B = FW.goal, FW.limits or ROOM.bounds
    g.x = max(B.x0 - 10, min(B.x1 + 10, g.x))
    g.y = max(B.y0 - 10, min(B.y1 + 10, g.y))
    g.dist = max(B.dmin or 4, min(B.dmax or 170, g.dist))
end
-- Move the target along the floor: dx toward screen right, dy away from the camera (pixel-ish units, scaled by the
-- distance). The camera sits at (cos yaw, sin yaw) from the target: screen right is (-sin yaw, cos yaw), away is
-- -(cos yaw, sin yaw).
function FW.pan(dx, dy)
    local g = FW.goal
    local k = g.dist * 0.0014
    local y = rad(g.yaw)
    g.x = g.x + (-sin(y) * dx - cos(y) * dy) * k
    g.y = g.y + (cos(y) * dx - sin(y) * dy) * k
    clamp_goal()
end
function FW.zoom(steps)
    FW.goal.dist = FW.goal.dist * (0.88 ^ steps)
    clamp_goal()
end
function FW.look_at(x, y, h, dist)
    FW.goal.x, FW.goal.y, FW.goal.h = x, y, h or FW.goal.h
    if dist then FW.goal.dist = dist end
    clamp_goal()
end
function FW.top_view(on)
    if on then FW.saved_pitch = FW.saved_pitch or FW.goal.pitch; FW.goal.pitch = 89
    else FW.goal.pitch = FW.saved_pitch or 36; FW.saved_pitch = nil end
end
function FW.cam_pos()
    local c = FW.cam
    local cp, sp = cos(rad(c.pitch)), sin(rad(c.pitch))
    return c.x + c.dist * cp * cos(rad(c.yaw)), c.y + c.dist * cp * sin(rad(c.yaw)), c.h + c.dist * sp
end
local function update_camera(dt)
    local g, c = FW.goal, FW.cam
    if FW.A and FW.follow and FW.A.front and FW.playing() then
        local f = FW.A.front
        local k = 1 - math.exp(-dt * 2.2)
        g.x, g.y, g.h = g.x + (f.x - g.x) * k, g.y + (f.y - g.y) * k, g.h + (f.h - g.h) * k
    end
    local k = 1 - math.exp(-dt * 10)
    for _, key in ipairs({ "x", "y", "h", "pitch", "dist" }) do c[key] = c[key] + (g[key] - c[key]) * k end
    c.yaw = c.yaw + (g.yaw - c.yaw) * k
    S.shake = max(0, S.shake - dt * 2.5)
    local px, py, ph = FW.cam_pos()
    local sw, sh = FW.screen_size()
    pcall(function() cam:set_fov(deg(2 * math.atan(math.tan(rad(FW.VFOV / 2)) * sw / max(1, sh)))) end)
    cam:set_position(v3(px, ph, -py))
    local sk = S.shake * 0.25
    cam:look_at(v3(c.x + sk * sin(S.t * 43), c.h + sk * sin(S.t * 37 + 1), -c.y))
    FW.vp, FW.inv = cam:get_view_projection(), cam:get_inv_view_projection()
    local ok, j = pcall(function() return cam:get_jitter() end)
    FW.jx, FW.jy = ok and j and j.x or 0, ok and j and j.y or 0
    -- Decor on a wall the camera is behind is hidden (the walls themselves are one-sided, so they vanish on their own).
    local B = ROOM.bounds
    local out = { L = px < B.x0, R = px > B.x1, B = py > B.y1, F = py < B.y0 }
    for g2, list in pairs(decor) do
        if FW.decor_hidden == nil or FW.decor_hidden[g2] ~= out[g2] then
            for _, n in ipairs(list) do hide_node(n, not out[g2]) end
        end
    end
    FW.decor_hidden = out
end
function FW.shake(a) S.shake = max(S.shake, a * (FW.shake_scale and FW.shake_scale() or 1)) end

------------------------------------------------------------------ picking
function FW.screen_size()
    local s = runtime_ui.get_surface_size()
    return s.width or 1280, s.height or 800
end
local function flip()
    if FW.flip == nil then
        local vp = FW.vp or cam:get_view_projection()
        local a, b = vp * vec4(FW.cam.x, FW.cam.h + 3, -FW.cam.y, 1), vp * vec4(FW.cam.x, FW.cam.h - 3, -FW.cam.y, 1)
        FW.flip = (a.y / a.w) > (b.y / b.w)
    end
    return FW.flip
end
function FW.project(x, y, h)
    local vp = FW.vp or cam:get_view_projection()
    local c = vp * vec4(x, h or 0, -y, 1)
    if c.w <= 1e-5 then return nil end
    local sw, sh = FW.screen_size()
    local nx, ny = c.x / c.w - (FW.jx or 0), c.y / c.w - (FW.jy or 0)
    return (nx * 0.5 + 0.5) * sw, (flip() and (0.5 - ny * 0.5) or (0.5 + ny * 0.5)) * sh
end
-- The mouse ray in table coordinates: origin and direction (x, y, h).
function FW.ray(mx, my)
    local inv = FW.inv or cam:get_inv_view_projection()
    local sw, sh = FW.screen_size()
    local nx = mx / sw * 2 - 1 + (FW.jx or 0)
    local ny = (flip() and (1 - my / sh * 2) or (my / sh * 2 - 1)) + (FW.jy or 0)
    local a, b = inv * vec4(nx, ny, 0.25, 1), inv * vec4(nx, ny, 0.75, 1)
    local ax, ay, az = a.x / a.w, a.y / a.w, a.z / a.w
    local bx, by, bz = b.x / b.w, b.y / b.w, b.z / b.w
    -- Start at the camera and point away from it: with reverse depth, depth 0.25 is the farther of the two points,
    -- and up close it lay below the floor, so clicks on the floor found nothing.
    local cx, cy, ch = FW.cam_pos()
    local pax, pay, pah = ax, -az, ay
    local pbx, pby, pbh = bx, -bz, by
    local da = (pax - cx) ^ 2 + (pay - cy) ^ 2 + (pah - ch) ^ 2
    local db = (pbx - cx) ^ 2 + (pby - cy) ^ 2 + (pbh - ch) ^ 2
    local nx_, ny_, nh_, fx, fy, fh = pax, pay, pah, pbx, pby, pbh
    if da > db then nx_, ny_, nh_, fx, fy, fh = pbx, pby, pbh, pax, pay, pah end
    local dx, dy, dh = fx - nx_, fy - ny_, fh - nh_
    local L = sqrt(dx * dx + dy * dy + dh * dh)
    if L < 1e-9 then return nx_, ny_, nh_, dx, dy, dh end
    dx, dy, dh = dx / L, dy / L, dh / L
    local back = sqrt(math.min(da, db)) + 1
    return nx_ - dx * back, ny_ - dy * back, nh_ - dh * back, dx, dy, dh
end
-- Where the mouse ray meets the horizontal plane at height h.
function FW.plane_point(mx, my, h)
    local ox, oy, oh, dx, dy, dh = FW.ray(mx, my)
    if abs(dh) < 1e-7 then return nil end
    local t = (h - oh) / dh
    if t <= 0 then return nil end
    return ox + dx * t, oy + dy * t
end
-- The first room surface under the mouse (nil if furniture is in the way or nothing is hit): x, y, h, surface.
function FW.pick(mx, my)
    local ox, oy, oh, dx, dy, dh = FW.ray(mx, my)
    local bt, bs, bx, by
    for _, s in ipairs(FW.board and FW.board:all_surfaces() or ROOM.surfaces) do
        if abs(dh) > 1e-7 then
            local t = (s.h - oh) / dh
            if t > 0 and (not bt or t < bt) then
                local x, y = ox + dx * t, oy + dy * t
                if x >= s.x0 and x <= s.x1 and y >= s.y0 and y <= s.y1 then bt, bs, bx, by = t, s, x, y end
            end
        end
    end
    if not bt then return nil end
    -- Furniture between the camera and that point hides it (walls do not: the camera sees through them).
    for _, s in ipairs(ROOM.solids) do
        if s.name ~= "wall" and s.z1 > bs.h + 0.05 then
            local t0, t1 = 0, bt - 1e-4
            for _, ax in ipairs({ { ox, dx, s.x0, s.x1 }, { oy, dy, s.y0, s.y1 }, { oh, dh, s.z0, s.z1 } }) do
                local o, d, lo, hi = ax[1], ax[2], ax[3], ax[4]
                if abs(d) < 1e-9 then
                    if o < lo or o > hi then t0 = 1; t1 = 0 end
                else
                    local a, b = (lo - o) / d, (hi - o) / d
                    if a > b then a, b = b, a end
                    t0, t1 = max(t0, a), min(t1, b)
                end
            end
            if t0 <= t1 then return nil, s end
        end
    end
    return bx, by, bs.h, bs
end

------------------------------------------------------------------ enter / leave / per frame
function FW.init()
    cam = scene.get_active_camera()
    ROOM = F.ROOM
    FW.reset_camera()
end

local function remember_settings()
    if FW.saved_lod == nil then
        local ok, v = pcall(settings.get, "lod_enabled")
        FW.saved_lod = not ok or v ~= false
    end
    if FW.saved_map_size == nil then
        local ok, v = pcall(settings.get, "shadow_map_size")
        FW.saved_map_size = ok and v or false
    end
end
local function restore_settings()
    pcall(settings.set, "shadow_fixed_bounds", false)
    pcall(settings.set, "lod_enabled", FW.saved_lod ~= false)
    if FW.saved_map_size then pcall(settings.set, "shadow_map_size", FW.saved_map_size) end
end

-- The Great Hall (topple_hall.lua): a world of its own, sharing this camera, the look and the lights.
local hall_root
function FW.enter_hall(H)
    cam = scene.get_active_camera()
    ROOM = F.ROOM
    remember_settings()
    pcall(function() cam:set_projection_mode("perspective") end)
    FW.limits = H.limits
    FW.saved_near, FW.saved_far = cam:get_near(), cam:get_far()
    cam:set_near(0.3)
    cam:set_far(H.far)
    save_lights()
    if not hall_root then
        hall_root = scene.add_empty_node("GreatHall")
        for _, L in ipairs(H.pieces) do
            local m = mesh_of(L.name)
            if m then
                local n = scene.add_empty_node("gh_" .. L.name)
                n:add_mesh_ref(m)
                n:set_parent(hall_root)
                look(n, L)
            end
        end
    end
    pcall(function() hall_root:set_enabled(true) end)
    light_on(H.sun, "Key")
    light_on(H.fill, "Fill")
    light_on({ intensity = 0 }, "Lamp")
    light_on({ intensity = 0 }, "RoomLamp", "point")
    if skybox and skybox.load then pcall(skybox.load, H.sky) end
    FW.apply_look()
    pcall(settings.set, "IBL_intensity", H.ibl)
    FW.active = true
end

function FW.leave_hall()
    restore_settings()
    if FW.saved_far then cam:set_near(FW.saved_near); cam:set_far(FW.saved_far) end
    FW.limits = nil
    FW.set_cursor(nil)
    FW.set_starter(nil)
    if hall_root then pcall(function() hall_root:set_enabled(false) end) end
    restore_lights()
    FW.active = false
end

-- A bell on its frame for the hall, beside the line at table angle a: { root, swing }. Scale: twice a Table Run bell.
function FW.make_bell()
    local frame = scene.add_empty_node("gh_bell")
    frame:set_parent(hall_root)
    local g = mesh_of("gallows")
    if g then frame:add_mesh_ref(g) end
    look(frame, { color = { 0.42, 0.28, 0.16 }, rough = 0.55 })
    frame:set_scale(v3(2, 2, 2))
    local swing = scene.add_empty_node("gh_bell_swing")
    swing:set_parent(frame)
    swing:set_position(v3(0, 2.16, 0))
    local b = mesh_of("bell")
    if b then swing:add_mesh_ref(b) end
    look(swing, { color = { 0.86, 0.62, 0.3 }, rough = 0.25, metal = 1, emis = { 0.05, 0.03, 0.01 } })
    return { root = frame, swing = swing }
end
function FW.place_bell(v, x, y, a)
    v.root:set_position(v3(x, 0, -y))
    v.root:set_rotation(v3(0, deg(a) + 90, 0))
    hide_node(v.root, true)
    hide_node(v.swing, true)
end
function FW.hide_bell(v)
    hide_node(v.root, false)
    hide_node(v.swing, false)
end

function FW.enter()
    cam = scene.get_active_camera()
    ROOM = F.ROOM
    remember_settings()
    pcall(function() cam:set_projection_mode("perspective") end)
    save_lights()
    if not room_root then build_room() end
    paint_templates()
    pcall(function() room_root:set_enabled(true) end)
    FW.decor_hidden = nil
    light_on(ROOM.sun, "Key")
    light_on(ROOM.fill, "Fill")
    light_on({ intensity = 0 }, "Lamp")
    light_on(ROOM.lamp, "RoomLamp", "point")
    if skybox and skybox.load then pcall(skybox.load, "day.hdr") end
    FW.apply_look()
    FW.active = true
    FW.statics_due = 3                 -- the room's colliders wait until its nodes have settled
    if can_live() then
        pcall(physics.set_gravity, 0, -F.BALL.g, 0)
        if FW.saved_rate == nil then
            local ok, v = pcall(settings.get, "physics_rate")
            FW.saved_rate = ok and v or false
        end
        pcall(settings.set, "physics_rate", 240)
    end
end

-- Every mesh of the room collides as itself: floor, walls, the Tripo furniture, curtains, lamp.
local statics_on
local function add_statics()
    if statics_on or not can_live() then return end
    statics_on = true
    for _, n in ipairs(room_nodes) do pcall(physics.add_body, n, "static", "mesh", WOOD) end
    for _, n in ipairs(FW.boards or {}) do pcall(physics.add_body, n, "static", "box", WOOD) end
end
local function remove_statics()
    if not statics_on then return end
    statics_on = false
    for _, n in ipairs(room_nodes) do body_off(n) end
    for _, n in ipairs(FW.boards or {}) do body_off(n) end
end

function FW.leave()
    remove_statics()
    if physics and physics.set_gravity then pcall(physics.set_gravity, 0, -9.81, 0) end
    if physics and physics.set_time_scale then pcall(physics.set_time_scale, 1) end
    if FW.saved_rate then pcall(settings.set, "physics_rate", FW.saved_rate) end
    restore_settings()
    FW.clear()
    FW.set_cursor(nil)
    FW.set_starter(nil)
    if room_root then pcall(function() room_root:set_enabled(false) end) end
    restore_lights()
    FW.active = false
end

-- dt: real time (the camera); anim_dt: the run's time (slowed for slow motion, 0 while building).
function FW.update(dt, anim_dt)
    S.t = S.t + dt
    flush_mats()
    if FW.settle and FW.settle > 0 then FW.settle = FW.settle - 1 end
    if FW.statics_due then
        FW.statics_due = FW.statics_due - 1
        if FW.statics_due <= 0 then FW.statics_due = nil; add_statics() end
    end
    local due = animate(anim_dt or dt)
    update_camera(dt)
    flush_poses()
    return due or {}
end

return FW
end
