-- Global auto-loaded director (Assets/Scripts/global). Advances a simulated Julian
-- date and drives heliocentric planet positions (Standish ephemeris) + axial spins.
-- It finds the SolarSystem node by name rather than being attached via set_script,
-- so the scene carries no machine-specific script path and the project is portable.
--
-- Node-name contract (created by build_solar_system.lua):
--   SolarSystem (root)
--   |- Sun
--   |- <Name>_orbit            position set here (heliocentric)
--      |- <Name>_tilt          static Euler X = axial tilt
--         |- <Name>            spun about local Y here
--         |- <Name>_rings      (Saturn) static
--         |- <Name>_rings_back (Saturn) static flipped backside
--         |- <Moon>_orbit      local satellite orbit set here
--            |- Moon           tidally-locked spin

local function load_module(path)
    local source = fs and fs.read and fs.read(path) or nil
    if not source then error("PhasmaSpace: missing module " .. path) end
    local chunk, err = load(source, "@" .. assets_path .. path, "bt", _ENV)
    if not chunk then error(err) end
    return chunk()
end

local E = load_module("Scripts/solar/ephemeris.lua")
local P = load_module("Scripts/solar/planets.lua")
local UI = load_module("Scripts/solar/solar_ui.lua")
local ui_ctx = { props = nil, handles = nil, planets = P }

local UNIX_EPOCH_JD = 2440587.5
local FALLBACK_EPOCH_JD = 2461201.5

local function current_julian_date()
    if os and os.time then
        return UNIX_EPOCH_JD + (os.time() / 86400.0)
    end
    return FALLBACK_EPOCH_JD
end

if _G.solar_manual_orbit_cleanup then
    pcall(_G.solar_manual_orbit_cleanup, true)
    _G.solar_manual_orbit_cleanup = nil
end

local start_epoch_jd = current_julian_date()
local props = exposed {
    time_scale        = 1.0 / 86400.0, -- sim days per real second; default = real time (0 freezes)
    epoch_jd          = start_epoch_jd, -- current UTC at script load
    animate_in_editor = true,
    follow            = "Earth",   -- body to track with the camera ("" = free cam)
    follow_distance   = 180.0,     -- camera distance in multiples of body radius
    follow_orbit      = true,      -- drag RMB/MMB to orbit while following
    auto_exposure     = true,      -- expose for the followed body (camera-style)
}
props.epoch_jd = start_epoch_jd

local function pos(x, y, z)
    return { x = x, y = y, z = z }
end

local function zero_pos()
    return pos(0.0, 0.0, 0.0)
end

-- Reused at the engine boundary. set_position/look_at/set_point_light copy, so
-- mutating this between calls is safe. Never store VEC3 on a node.
local VEC3_ZERO = vec3(0.0, 0.0, 0.0)
local VEC3 = vec3(0.0, 0.0, 0.0)
local AU_EXPOSURE = pos(P.AU_UNITS, 0.0, 0.0)

local function unshifted(v, by)
    return pos(v.x - by.x, v.y - by.y, v.z - by.z)
end

local function length_pos(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local function rotate_x(v, deg)
    local a = math.rad(deg)
    local c = math.cos(a)
    local s = math.sin(a)
    return pos(v.x, v.y * c - v.z * s, v.y * s + v.z * c)
end

local sim_days = 0.0
local handles = {}  -- node name -> SceneNodeHandle
local root = nil    -- the SolarSystem node (found by name as a global script, or `self`)
local bound = false -- true once the tree is indexed and orbit lines are built
local sun_light_node = nil
local sun_light_cached = nil
local scene_shift = zero_pos()
local universe_positions = {} -- body name -> heliocentric world position before root rebase
local moon_locals = {}        -- moon name -> local orbit position before parent planet tilt
local last_dt = 0.0
-- Bind-time node cache: kills per-tick `name .. "_orbit"` concat + handle lookup.
local solar_bodies = {} -- { p, orbit, body, clouds, tilt, moons = { { m, orbit, body } } }
local orbit_owner_by_index = {} -- node_index -> body name for selected-orbit highlight
local POS_B, POS_N = {}, 0
local ROT_B, ROT_N = {}, 0

local function push_pos(node, x, y, z)
    if not node then return end
    if scene.set_positions then
        local i = POS_N * 4
        POS_B[i + 1], POS_B[i + 2], POS_B[i + 3], POS_B[i + 4] = node, x, y, z
        POS_N = POS_N + 1
    else
        VEC3.x, VEC3.y, VEC3.z = x, y, z
        node:set_position(VEC3)
    end
end

local function push_rot(node, x, y, z)
    if not node then return end
    if scene.set_rotations then
        local i = ROT_N * 4
        ROT_B[i + 1], ROT_B[i + 2], ROT_B[i + 3], ROT_B[i + 4] = node, x, y, z
        ROT_N = ROT_N + 1
    else
        VEC3.x, VEC3.y, VEC3.z = x, y, z
        node:set_rotation(VEC3)
    end
end

local function flush_transforms()
    if POS_N > 0 and scene.set_positions then
        scene.set_positions(POS_B, POS_N)
        POS_N = 0
    end
    if ROT_N > 0 and scene.set_rotations then
        scene.set_rotations(ROT_B, ROT_N)
        ROT_N = 0
    end
end

local function remember_orbit_owner(node, owner)
    if node then
        orbit_owner_by_index[node:get_index()] = owner
    end
end

local function cache_solar_bodies()
    solar_bodies = {}
    orbit_owner_by_index = {}
    for _, p in ipairs(P.planets) do
        local rec = {
            p = p,
            orbit = handles[p.name .. "_orbit"],
            body = handles[p.name],
            clouds = p.clouds and handles[p.name .. "_clouds"] or nil,
            tilt = handles[p.name .. "_tilt"],
            moons = {},
        }
        remember_orbit_owner(rec.orbit, p.name)
        remember_orbit_owner(rec.body, p.name)
        remember_orbit_owner(rec.tilt, p.name)
        remember_orbit_owner(handles[p.name .. "_rings"], p.name)
        remember_orbit_owner(handles[p.name .. "_rings_back"], p.name)
        for _, m in ipairs(p.moons) do
            local mr = {
                m = m,
                orbit = handles[m.name .. "_orbit"],
                body = handles[m.name],
            }
            rec.moons[#rec.moons + 1] = mr
            remember_orbit_owner(mr.orbit, m.name)
            remember_orbit_owner(mr.body, m.name)
        end
        solar_bodies[#solar_bodies + 1] = rec
    end
end

local function reset_simulation_clock()
    props.epoch_jd = current_julian_date()
    sim_days = 0.0
end

local function index_children(h)
    for _, child in ipairs(h:get_children()) do
        handles[child:get_name()] = child
        index_children(child)
    end
end

-- Orbit lines: temporary manual render_graph pass test. The lines are sampled
-- into Lua-owned line-strip vertex buffers and drawn by a script-created pass, without
-- creating RenderType::Lines meshes for the engine's predefined LinesPass.
--
-- Line strips are rebuilt at load/epoch only. Planet orbit vertices stay in
-- heliocentric coordinates; the manual pass applies the floating-origin shift
-- as a push constant every frame. Moon orbit vertices are pre-tilted and drawn
-- around their parent planet.
local ORBIT_MIN_SAMPLES = 240
local ORBIT_MAX_SAMPLES = 4096
local ORBIT_SAGITTA_RADIUS_FRACTION = 0.2
local MOON_ORBIT_SEGMENT_TARGET = 0.75
local MOON_ORBIT_LINE_LIMIT = 4
local MANUAL_ORBIT_PASS_NAME = "SolarManualOrbitLines"
local MANUAL_ORBIT_PASS_ORDER = 721
local MANUAL_ORBIT_COLOR = { x = 1.0, y = 1.0, z = 1.0, w = 1.0 }
local SELECTED_ORBIT_COLOR = { x = 1.0, y = 0.82, z = 0.05, w = 1.0 }
local FREE_REBASE_DISTANCE = 1000.0
local FOLLOW_ORBIT_SENSITIVITY = 0.0035
local FOLLOW_ORBIT_PITCH_LIMIT = math.rad(84.0)
local manual_orbit_lines = {
    items = {},
    pass_info = nil,
    registered = false,
    frames = 0,
    draws = 0,
}

local function orbit_sample_count(a_units, radius_units)
    local sagitta = math.max((radius_units or 1.0) * ORBIT_SAGITTA_RADIUS_FRACTION, 0.02)
    local samples = math.ceil(math.pi * math.sqrt(a_units / (2.0 * sagitta)))
    if samples < ORBIT_MIN_SAMPLES then samples = ORBIT_MIN_SAMPLES end
    if samples > ORBIT_MAX_SAMPLES then samples = ORBIT_MAX_SAMPLES end
    return samples
end

local function moon_orbit_sample_count(a_units)
    local samples = math.floor((2.0 * math.pi * a_units) / MOON_ORBIT_SEGMENT_TARGET)
    if samples < 96 then samples = 96 end
    if samples > 512 then samples = 512 end
    return samples
end

local function sample_planet_orbit(o, jd)
    local pts = {}
    for i = 0, o.samples - 1 do
        local sample_jd = jd + (i / o.samples) * o.period_days
        local x, y, z = E.heliocentric(o.body, sample_jd)
        pts[#pts + 1] = pos(x * P.AU_UNITS, z * P.AU_UNITS, y * P.AU_UNITS)
    end
    o.pts = pts
    o.anchor_jd = jd
end

local function sample_region_ring(radius_units, samples)
    local pts = {}
    for i = 0, samples - 1 do
        local ang = 2.0 * math.pi * (i / samples)
        pts[#pts + 1] = pos(radius_units * math.cos(ang), 0.0, radius_units * math.sin(ang))
    end
    return pts
end

local function orbit_color(c)
    if not c then return MANUAL_ORBIT_COLOR end
    return {
        x = c.x or c[1] or MANUAL_ORBIT_COLOR.x,
        y = c.y or c[2] or MANUAL_ORBIT_COLOR.y,
        z = c.z or c[3] or MANUAL_ORBIT_COLOR.z,
        w = c.w or c[4] or MANUAL_ORBIT_COLOR.w,
    }
end

local function append_vertex_floats(out, v)
    out[#out + 1] = v.x
    out[#out + 1] = v.y
    out[#out + 1] = v.z
end

local function closed_points_to_line_strip_floats(points)
    local out = {}
    local count = #points
    if count < 2 then return out end

    for i = 1, count do
        append_vertex_floats(out, points[i])
    end
    append_vertex_floats(out, points[1])
    return out
end

local function destroy_manual_orbit_lines(clear_globals)
    if render_graph and render_graph.remove_pass then
        render_graph.remove_pass(MANUAL_ORBIT_PASS_NAME)
    end
    manual_orbit_lines.registered = false
    manual_orbit_lines.frames = 0
    manual_orbit_lines.draws = 0

    if destroy_buffer then
        for _, item in ipairs(manual_orbit_lines.items) do
            if item.buffer then
                destroy_buffer(item.buffer)
                item.buffer = nil
            end
        end
    end
    manual_orbit_lines.items = {}

    if manual_orbit_lines.pass_info and destroy_pass_info then
        destroy_pass_info(manual_orbit_lines.pass_info)
        manual_orbit_lines.pass_info = nil
    end

    if clear_globals then
        if _G.solar_manual_orbit_cleanup == destroy_manual_orbit_lines then
            _G.solar_manual_orbit_cleanup = nil
        end
        _G.solar_manual_orbit_debug = nil
    end
end

local function create_manual_orbit_line(name, points, owner, color, visible)
    if not create_buffer then
        pe_log("[solar] manual orbit line skipped; create_buffer binding is missing")
        return
    end

    local vertices = closed_points_to_line_strip_floats(points)
    if #vertices < 6 then return end

    local vertex_count = math.floor(#vertices / 3)
    local byte_size = #vertices * 4
    local buffer = create_buffer(byte_size, "vertex", "cpu_to_gpu", "SolarOrbit_" .. name)
    if not buffer then return end
    buffer:set_data(vertices, "float")
    buffer:flush(byte_size, 0)
    buffer:unmap()

    manual_orbit_lines.items[#manual_orbit_lines.items + 1] = {
        name = name,
        buffer = buffer,
        vertex_count = vertex_count,
        owner = owner,
        color = orbit_color(color),
        visible = visible ~= false,
    }
end

local function ensure_manual_orbit_pipeline(target, depth)
    if manual_orbit_lines.pass_info then return true end
    if not create_pass_info then
        pe_log("[solar] manual orbit pass skipped; create_pass_info binding is missing")
        return false
    end

    local pi = create_pass_info()
    manual_orbit_lines.pass_info = pi
    pi:set_name("SolarManualOrbitLine_pipeline")
    pi:set_vertex_shader("Shaders/Utilities/ManualOrbitLinesVS.hlsl", "mainVS")
    pi:set_fragment_shader("Shaders/Utilities/ManualOrbitLinesPS.hlsl", "mainPS")
    pi:set_topology("line_strip")
    pi:set_cull_mode("none")
    pi:set_dynamic_states({ "viewport", "scissor" })
    pi:set_color_format(target)
    pi:set_depth_format(depth)
    pi:set_depth_test(true)
    pi:set_depth_write(false)
    pi:set_blend_mode("default")
    pi:update()
    return true
end

local function manual_orbit_offset(item)
    if item.owner then
        local owner_pos = universe_positions[item.owner]
        if not owner_pos then return nil end
        local o = item.world_offset
        if not o then
            o = pos(0.0, 0.0, 0.0)
            item.world_offset = o
        end
        o.x = owner_pos.x + scene_shift.x
        o.y = owner_pos.y + scene_shift.y
        o.z = owner_pos.z + scene_shift.z
        return o
    end
    return scene_shift
end

local function selected_node_index()
    if type(selection) ~= "table" or type(selection.get) ~= "function" then return nil end
    local ok, sel = pcall(selection.get)
    if not ok or type(sel) ~= "table" or not sel.has_selection then return nil end
    if sel.type ~= "node" and sel.type ~= "mesh" then return nil end
    return sel.node_index
end

local function selected_orbit_owner()
    local selected_index = selected_node_index()
    if selected_index then
        local owner = orbit_owner_by_index[selected_index]
        if owner then return owner end
    end
    return props.follow ~= "" and props.follow or nil
end

local function register_manual_orbit_pass()
    if not render_graph or not render_graph.add_pass then
        pe_log("[solar] manual orbit pass skipped; render_graph.add_pass binding is missing")
        return
    end

    render_graph.remove_pass(MANUAL_ORBIT_PASS_NAME)
    local target = render_graph.get_target and render_graph.get_target("viewport") or nil
    local depth = render_graph.get_target and render_graph.get_target("depthStencil") or nil
    if target and depth then
        ensure_manual_orbit_pipeline(target, depth)
    end

    render_graph.add_pass(MANUAL_ORBIT_PASS_NAME, MANUAL_ORBIT_PASS_ORDER, function(cmd)
        local orbits = handles["Orbits"]
        if not orbits or not orbits:is_valid() then return end
        if orbits.is_enabled and not orbits:is_enabled() then return end
        if #manual_orbit_lines.items == 0 then return end

        local target = render_graph.get_target("viewport")
        local depth = render_graph.get_target("depthStencil")
        local cam = get_camera and get_camera() or nil
        if not target or not depth or not cam then return end
        if not ensure_manual_orbit_pipeline(target, depth) then return end

        local width = target.get_width
        local height = target.get_height
        if width == 0 or height == 0 then return end

        manual_orbit_lines.frames = manual_orbit_lines.frames + 1
        manual_orbit_lines.draws = 0

        cmd:begin_pass({ { target, "load", "store" }, { depth, "load", "store", "load", "store" } },
                       MANUAL_ORBIT_PASS_NAME)
        cmd:set_viewport(0.0, 0.0, target.get_width_f, target.get_height_f, 0.0, 1.0)
        cmd:set_scissor(0, 0, width, height)
        cmd:bind_pipeline(manual_orbit_lines.pass_info, false)

        cmd:set_constant_mat4(0, cam:get_view_projection())

        local highlighted = selected_orbit_owner()
        for _, item in ipairs(manual_orbit_lines.items) do
            local offset = manual_orbit_offset(item)
            if offset and item.buffer and (item.visible or item.name == highlighted) then
                local color = item.name == highlighted and SELECTED_ORBIT_COLOR or item.color
                cmd:set_constant_vec4(16, offset.x, offset.y, offset.z, 0.0)
                cmd:set_constant_vec4(20, color.x, color.y, color.z, color.w)
                cmd:push_constants()
                cmd:bind_vertex_buffer(item.buffer, 0)
                cmd:draw(item.vertex_count, 1, 0, 0)
                manual_orbit_lines.draws = manual_orbit_lines.draws + 1
            end
        end

        cmd:end_pass()
    end)
    manual_orbit_lines.registered = true
end

_G.solar_manual_orbit_cleanup = destroy_manual_orbit_lines
_G.solar_manual_orbit_debug = function()
    local first = manual_orbit_lines.items[1]
    local visible_count = 0
    for _, item in ipairs(manual_orbit_lines.items) do
        if item.visible then visible_count = visible_count + 1 end
    end
    return {
        count = #manual_orbit_lines.items,
        visible_count = visible_count,
        hidden_count = #manual_orbit_lines.items - visible_count,
        registered = manual_orbit_lines.registered,
        frames = manual_orbit_lines.frames,
        draws = manual_orbit_lines.draws,
        first_vertices = first and first.vertex_count or 0,
        topology = "line_strip",
        epoch_jd = props.epoch_jd,
        jd = props.epoch_jd + sim_days,
        highlighted = selected_orbit_owner(),
    }
end

function destroy()
    destroy_manual_orbit_lines(true)
end

local function choose_sun_point_light(pls)
    local best = nil
    local best_score = -math.huge
    for _, l in ipairs(pls or {}) do
        local name = tostring(l.name or "")
        local lower = string.lower(name)
        local score = tonumber(l.intensity or 0.0) or 0.0
        if string.find(lower, "sun", 1, true) then
            score = score + 1.0e30
        end
        if not best or score > best_score then
            best = l
            best_score = score
        end
    end
    return best
end

local function sync_sun_light(world_pos)
    if not lights or not lights.set_point_light then return end
    if not sun_light_cached then
        if not lights.get_point_lights then return end
        local sun_light = choose_sun_point_light(lights.get_point_lights())
        if not sun_light then return end
        sun_light_cached = {
            index = sun_light.index or 0,
            color = sun_light.color or vec3(1.0, 0.96, 0.9),
            intensity = sun_light.intensity or 4.9e8,
            radius = sun_light.radius or 5.0e6,
            name = sun_light.name,
        }
    end
    if (not sun_light_node or not sun_light_node:is_valid()) and sun_light_cached.name and scene.find_model then
        sun_light_node = scene.find_model(sun_light_cached.name)
    end
    local wp = world_pos
    VEC3.x, VEC3.y, VEC3.z = wp.x, wp.y, wp.z
    if sun_light_node and sun_light_node:is_valid() then
        sun_light_node:set_position(VEC3)
    end
    lights.set_point_light(sun_light_cached.index, VEC3,
                           sun_light_cached.color,
                           sun_light_cached.intensity,
                           sun_light_cached.radius)
end

local function build_orbit_lines(jd)
    destroy_manual_orbit_lines()

    if handles["Orbits"] then
        handles["Orbits"]:remove()
        handles["Orbits"] = nil
    end
    local orbits = scene.add_empty_node("Orbits")
    orbits:set_parent(root)
    handles["Orbits"] = orbits

    for _, rec in ipairs(solar_bodies) do
        local p = rec.p
        local a_units = E.elements[p.body][1] * P.AU_UNITS
        local period_days = (E.elements[p.body][1] ^ 1.5) * 365.25
        local o = {
            body = p.body,
            samples = orbit_sample_count(a_units, P.radius_units(p.radius_km)),
            period_days = period_days,
        }
        sample_planet_orbit(o, jd)
        create_manual_orbit_line(p.name, o.pts, nil)

        if rec.tilt then
            for moon_index, mr in ipairs(rec.moons) do
                local m = mr.m
                local ma = P.dist_units(m.a_km) * (m.dist_scale or 1.0)
                local msamples = moon_orbit_sample_count(ma)
                local mpts = P.sample_moon_orbit_units(m, msamples, jd)
                local tilted = {}
                for i, pt in ipairs(mpts) do
                    tilted[i] = rotate_x(pt, p.tilt)
                end
                create_manual_orbit_line(m.name, tilted, p.name, nil, moon_index <= MOON_ORBIT_LINE_LIMIT)
            end
        end
    end

    for _, r in ipairs(P.regions or {}) do
        local samples = r.samples or 720
        if samples < 96 then samples = 96 elseif samples > ORBIT_MAX_SAMPLES then samples = ORBIT_MAX_SAMPLES end
        local pts = sample_region_ring((r.radius_au or 1.0) * P.AU_UNITS, samples)
        create_manual_orbit_line(r.name, pts, nil, r.color)
    end

    register_manual_orbit_pass()
end

-- Photographic auto-exposure: sunlight falls off physically (1/d^2), so expose for
-- the followed body by scaling the global light multiplier with its solar distance
-- squared (1.0 at 1 AU). Earth, Mercury, and Neptune all read correctly exposed,
-- like a camera metering its subject.
local function apply_exposure(target)
    if not props.auto_exposure then return end
    local d2 = target.x * target.x + target.y * target.y + target.z * target.z
    local f = d2 / (P.AU_UNITS * P.AU_UNITS)
    if f < 0.02 then f = 0.02 end
    if f > 2000.0 then f = 2000.0 end
    settings.set("lights_intensity", f)
end

local function set_editor_fly_camera_blocked(blocked)
    _G.phasma_editor_fly_camera_blocked = blocked and true or false
end

-- Track a body with the active camera. The offset is stored in the body's rotating
-- SOLAR frame (radial = away from sun, vertical, tangential), so the phase angle you
-- chose stays put while the body sweeps along its orbit — re-deriving the offset from
-- the lagged camera position would make the camera trail the orbit and lock every
-- view to the terminator. With follow_orbit enabled, RMB/MMB drag rotates this
-- stored offset while the camera remains anchored to the moving body; clear
-- `follow` in the Properties panel for a fully free camera.
local follow_state = { target = "", r = -0.82, u = 0.25, t = -0.51, expected = nil }

local function release_follow_orbit_mouse()
    follow_state.orbit_dragging = false
    follow_state.skip_orbit_delta = false
    if follow_state.orbit_mouse_owner and type(input) == "table" and input.set_relative_mouse then
        input.set_relative_mouse(false)
    end
    follow_state.orbit_mouse_owner = false
end

local function rotate_follow_offset(yaw_delta, pitch_delta)
    local n = math.sqrt(follow_state.r ^ 2 + follow_state.u ^ 2 + follow_state.t ^ 2)
    local r, u, t = follow_state.r, follow_state.u, follow_state.t
    if n < 1e-6 then
        r, u, t, n = -0.82, 0.25, -0.51, 1.0
    end
    r, u, t = r / n, u / n, t / n

    local yaw = math.atan2(t, r) + yaw_delta
    local pitch = math.atan2(u, math.sqrt(r * r + t * t)) + pitch_delta
    if pitch > FOLLOW_ORBIT_PITCH_LIMIT then pitch = FOLLOW_ORBIT_PITCH_LIMIT end
    if pitch < -FOLLOW_ORBIT_PITCH_LIMIT then pitch = -FOLLOW_ORBIT_PITCH_LIMIT end

    local h = math.cos(pitch)
    follow_state.r = math.cos(yaw) * h
    follow_state.u = math.sin(pitch)
    follow_state.t = math.sin(yaw) * h
end

local function apply_follow_orbit_input()
    if props.follow_orbit == false or type(input) ~= "table" or
        not input.is_viewport_focused or not input.is_viewport_focused() then
        release_follow_orbit_mouse()
        set_editor_fly_camera_blocked(false)
        return false
    end
    set_editor_fly_camera_blocked(true)

    local orbiting = (input.is_right_mouse_down and input.is_right_mouse_down()) or
        (input.is_middle_mouse_down and input.is_middle_mouse_down())
    if not orbiting then
        release_follow_orbit_mouse()
        return false
    end

    if not follow_state.orbit_dragging then
        follow_state.skip_orbit_delta = true
        follow_state.orbit_dragging = true
        if input.is_relative_mouse and input.set_relative_mouse and not input.is_relative_mouse() then
            input.set_relative_mouse(true)
            follow_state.orbit_mouse_owner = true
        end
    end

    local mouse = input.peek_mouse_delta and input.peek_mouse_delta()
        or input.get_mouse_delta and input.get_mouse_delta()
        or nil
    if not mouse then return true end
    if follow_state.skip_orbit_delta then
        follow_state.skip_orbit_delta = false
        return true
    end

    local mx = mouse.x or mouse[1] or 0.0
    local my = mouse.y or mouse[2] or 0.0
    rotate_follow_offset(-mx * FOLLOW_ORBIT_SENSITIVITY,
                         my * FOLLOW_ORBIT_SENSITIVITY)
    follow_state.drag_frames = 0
    return true
end

local function solar_frame(p)
    local len = length_pos(p)
    if len < 1e-6 then
        return 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, -1.0
    end
    local rx, ry, rz = p.x / len, p.y / len, p.z / len      -- radial (sun -> body)
    local tx, ty, tz = rz, 0.0, -rx                        -- horizontal tangential
    local tlen = math.sqrt(tx * tx + tz * tz)
    if tlen < 1e-6 then tx, ty, tz, tlen = 1.0, 0.0, 0.0, 1.0 end
    tx, tz = tx / tlen, tz / tlen
    -- vertical = radial x tangential (right-handed-ish, good enough for a cam rig)
    local ux = ry * tz - rz * ty
    local uy = rz * tx - rx * tz
    local uz = rx * ty - ry * tx
    return rx, ry, rz, ux, uy, uz, tx, ty, tz
end

local function update_scene_shift()
    if root then root:set_position(VEC3_ZERO) end
    if props.follow == "" then
        follow_state.target = ""
        release_follow_orbit_mouse()
        set_editor_fly_camera_blocked(false)
        local cam = get_camera and get_camera() or nil
        if cam then
            local cp = cam:get_position()
            local cpx, cpy, cpz = cp.x, cp.y, cp.z
            if math.sqrt(cpx * cpx + cpy * cpy + cpz * cpz) > FREE_REBASE_DISTANCE then
                scene_shift.x = scene_shift.x - cpx
                scene_shift.y = scene_shift.y - cpy
                scene_shift.z = scene_shift.z - cpz
                cam:set_position(VEC3_ZERO)
            end
        end
        sync_sun_light(scene_shift)
        return
    end

    local universe_target = universe_positions[props.follow]
    if not universe_target then
        sync_sun_light(scene_shift)
        return
    end

    scene_shift.x, scene_shift.y, scene_shift.z = -universe_target.x, -universe_target.y, -universe_target.z
    sync_sun_light(scene_shift)
end

local function follow_camera()
    if props.follow == "" then
        follow_state.target = ""
        release_follow_orbit_mouse()
        set_editor_fly_camera_blocked(false)
        return
    end
    local body = handles[props.follow]
    local cam = get_camera and get_camera() or nil
    if not body or not cam then
        release_follow_orbit_mouse()
        set_editor_fly_camera_blocked(false)
        return
    end

    local universe_target = universe_positions[props.follow]
    if not universe_target then
        local wp = body:get_world_position()
        universe_target = unshifted(pos(wp.x, wp.y, wp.z), scene_shift)
    end
    local target = follow_state.scene_target
    if not target then
        target = pos(0.0, 0.0, 0.0)
        follow_state.scene_target = target
    end
    target.x = universe_target.x + scene_shift.x
    target.y = universe_target.y + scene_shift.y
    target.z = universe_target.z + scene_shift.z
    if props.follow == "Sun" then
        -- The Sun sits at the origin, so metering its own solar distance (d=0)
        -- clamps exposure to the floor and blacks out every planet; meter the
        -- scene as if at 1 AU instead.
        apply_exposure(AU_EXPOSURE)
    else
        apply_exposure(universe_target)
    end
    if follow_state.target ~= props.follow or not follow_state.radius then
        follow_state.radius = body:get_scale().x
    end
    local radius = follow_state.radius
    -- The Sun is enormous (208.7 u): the default 6-radius distance fills the
    -- whole view. Keep sun viewing at >= 25 radii; wheel zoom still works above.
    local dist_mult = props.follow == "Sun" and math.max(props.follow_distance, 25.0)
        or props.follow_distance
    local dist = math.max(dist_mult * radius, radius * 2.0)
    local rx, ry, rz, ux, uy, uz, tx, ty, tz = solar_frame(universe_target)

    local orbiting_follow = apply_follow_orbit_input()
    local cv = cam:get_position()
    local cpx, cpy, cpz = cv.x, cv.y, cv.z
    local switched = follow_state.target ~= props.follow
    -- Adopt a user-chosen angle only after TWO consecutive displaced frames:
    -- single-frame displacement can come from editor camera damping or pipeline
    -- timing and adopting it caused slow tangential lag on fast moons (Io).
    local user_adjusting = type(input) == "table" and
        input.is_viewport_focused and input.is_viewport_focused() and
        ((input.is_right_mouse_down and input.is_right_mouse_down()) or
         (input.is_middle_mouse_down and input.is_middle_mouse_down()))
    local dragged = false
    if not orbiting_follow and props.follow_orbit == false and not switched and user_adjusting and follow_state.expected then
        local e = follow_state.expected
        local moved = math.sqrt((cpx - e.x) ^ 2 + (cpy - e.y) ^ 2 + (cpz - e.z) ^ 2)
        if moved > dist * 0.02 then
            follow_state.drag_frames = (follow_state.drag_frames or 0) + 1
        else
            follow_state.drag_frames = 0
        end
        dragged = (follow_state.drag_frames or 0) >= 2
    else
        follow_state.drag_frames = 0
    end
    if dragged then
        -- user moved the camera: adopt the new offset, expressed in the solar frame
        local ox, oy, oz = cpx - target.x, cpy - target.y, cpz - target.z
        local olen = math.sqrt(ox * ox + oy * oy + oz * oz)
        if olen > radius * 0.5 then
            follow_state.r = (ox * rx + oy * ry + oz * rz) / olen
            follow_state.u = (ox * ux + oy * uy + oz * uz) / olen
            follow_state.t = (ox * tx + oy * ty + oz * tz) / olen
        end
    end
    follow_state.target = props.follow

    local n = math.sqrt(follow_state.r ^ 2 + follow_state.u ^ 2 + follow_state.t ^ 2)
    if n < 1e-6 then n = 1.0 end
    local fr, fu, ft = follow_state.r / n * dist, follow_state.u / n * dist, follow_state.t / n * dist
    local px = target.x + rx * fr + ux * fu + tx * ft
    local py = target.y + ry * fr + uy * fu + ty * ft
    local pz = target.z + rz * fr + uz * fu + tz * ft
    VEC3.x, VEC3.y, VEC3.z = px, py, pz
    cam:set_position(VEC3)
    VEC3.x, VEC3.y, VEC3.z = target.x, target.y, target.z
    cam:look_at(VEC3)
    local e = follow_state.expected
    if e then
        e.x, e.y, e.z = px, py, pz
    else
        follow_state.expected = pos(px, py, pz)
    end
end

local function spin_deg(jd, rot_h)
    local days_per_turn = math.abs(rot_h) / 24.0
    local turns = (jd - E.J2000) / days_per_turn
    local deg = (turns % 1.0) * 360.0
    if rot_h < 0 then deg = -deg end
    return deg
end

local function moon_spin_deg(jd, m)
    local period = m.period_d or 1.0
    if math.abs(period) < 1e-9 then period = 1.0 end
    return (((m.mean_anomaly_deg or 0.0) + ((jd - (m.epoch_jd or E.J2000)) / period) * 360.0) % 360.0)
end

local function compute_universe_positions(jd)
    local sun_pos = universe_positions["Sun"]
    if sun_pos then
        sun_pos.x, sun_pos.y, sun_pos.z = 0.0, 0.0, 0.0
    else
        universe_positions["Sun"] = zero_pos()
    end
    for _, p in ipairs(P.planets) do
        local x, y, z = E.heliocentric(p.body, jd)  -- AU, J2000 ecliptic
        -- ecliptic -> engine: x->X, y->Z, z->Y (ecliptic north = +Y)
        x, y, z = x * P.AU_UNITS, z * P.AU_UNITS, y * P.AU_UNITS
        local planet_pos = universe_positions[p.name]
        if planet_pos then
            planet_pos.x, planet_pos.y, planet_pos.z = x, y, z
        else
            planet_pos = pos(x, y, z)
            universe_positions[p.name] = planet_pos
        end

        local moons = p.moons
        if moons[1] then
            local tilt = math.rad(p.tilt)
            local c, s = math.cos(tilt), math.sin(tilt)
            for _, m in ipairs(moons) do
                local moon_local = P.moon_local_units(m, jd, moon_locals[m.name])
                moon_locals[m.name] = moon_local
                local ry = moon_local.y * c - moon_local.z * s
                local rz = moon_local.y * s + moon_local.z * c
                local moon_pos = universe_positions[m.name]
                if moon_pos then
                    moon_pos.x = moon_local.x + planet_pos.x
                    moon_pos.y = ry + planet_pos.y
                    moon_pos.z = rz + planet_pos.z
                else
                    universe_positions[m.name] = pos(moon_local.x + planet_pos.x,
                                                    ry + planet_pos.y,
                                                    rz + planet_pos.z)
                end
            end
        end
    end
end

local function apply_scene_positions(jd)
    local sx, sy, sz = scene_shift.x, scene_shift.y, scene_shift.z
    push_pos(handles["Orbits"], sx, sy, sz)
    push_pos(handles["Sun"], sx, sy, sz)

    for _, rec in ipairs(solar_bodies) do
        local p = rec.p
        local planet_pos = universe_positions[p.name]
        if rec.orbit and planet_pos then
            push_pos(rec.orbit, planet_pos.x + sx, planet_pos.y + sy, planet_pos.z + sz)
        end
        if rec.body then
            push_rot(rec.body, 0.0, spin_deg(jd, p.rot_h), 0.0)
        end
        if rec.clouds then
            push_rot(rec.clouds, 0.0, spin_deg(jd, p.clouds.rot_h), 0.0)
        end
        for _, mr in ipairs(rec.moons) do
            local moon_local = moon_locals[mr.m.name]
            if mr.orbit and moon_local then
                push_pos(mr.orbit, moon_local.x, moon_local.y, moon_local.z)
            end
            if mr.body then
                -- Tidally locked: one rotation per orbit.
                push_rot(mr.body, 0.0, moon_spin_deg(jd, mr.m), 0.0)
            end
        end
    end
    flush_transforms()
end

-- The SolarSystem node: `self` when attached as a node script (editor authoring),
-- otherwise found by name. As a global script the director auto-loads from
-- Assets/Scripts/global with no machine-specific set_script path baked into the
-- scene, which is what makes the project portable across checkouts.
local function resolve_root()
    if self ~= nil then return self end
    if scene and scene.get_entities then
        for _, e in ipairs(scene.get_entities()) do
            if e.label == "SolarSystem" then return e.node end
        end
    end
    return nil
end

-- Index the tree and build orbit lines once the node exists. A global script can
-- tick before the startup scene has finished loading, so binding is deferred until
-- resolve_root() succeeds (and re-runs if the node goes stale on a scene change).
local function bind()
    handles = {}
    index_children(root)
    cache_solar_bodies()
    root:set_position(VEC3_ZERO)
    sun_light_node = nil
    sun_light_cached = nil
    scene_shift.x, scene_shift.y, scene_shift.z = 0.0, 0.0, 0.0
    reset_simulation_clock()
    local jd = props.epoch_jd + sim_days
    compute_universe_positions(jd)
    update_scene_shift()
    build_orbit_lines(jd)
    apply_scene_positions(jd)
    -- Re-apply per-load material state. night_emissive is a base-material flag
    -- and is not serialized into the scene, so it must be re-asserted on load.
    -- Crucially, runtime edits to a *base* material are not re-uploaded to the
    -- GPU material table (only MaterialInstances are), so setting the flag alone
    -- never reaches the shader. Re-setting emissive forces a MaterialInstance,
    -- whose GPU data carries the parent's night_emissive — this is what makes the
    -- lighting pass gate the city lights to the night hemisphere instead of
    -- glowing them across the sunlit day side.
    for _, p in ipairs(P.planets) do
        if p.night_tex and handles[p.name] then
            local node = handles[p.name]
            material.set(node, "night_emissive", 1.0)
            local m = material.get(node)
            if m and m.emissive then
                material.set(node, "emissive", m.emissive)
            end
        end
    end
    ui_ctx.props = props
    ui_ctx.handles = handles
    ui_ctx.universe_positions = universe_positions
    ui_ctx.scene_shift = scene_shift
    UI.init(ui_ctx)
    local n = 0
    for _ in pairs(handles) do n = n + 1 end
    pe_log("[solar] director bound, " .. tostring(n) .. " nodes indexed")
    bound = true
end

local function ensure_bound()
    if bound then
        if root and root:is_valid() then return true end
        bound, root = false, nil -- scene changed under us; re-bind
    end
    if not root then root = resolve_root() end
    if not root then return false end
    bind()
    return true
end

local function tick(dt)
    if not ensure_bound() then return end
    if type(dt) ~= "number" then
        dt = engine.get_metrics().delta_ms * 0.001
    end
    if dt > 0.25 then dt = 0.25 end  -- ignore hitches (loads, resizes)
    last_dt = dt
    sim_days = sim_days + dt * props.time_scale
    local jd = props.epoch_jd + sim_days

    compute_universe_positions(jd)
    update_scene_shift()
    apply_scene_positions(jd)

    UI.tick(ui_ctx)
    follow_camera()
end

function init()
    -- Bind now if the scene is already loaded; otherwise the first tick() will.
    ensure_bound()
end

-- Free-camera flight for PLAY MODE (PhasmaPlayer + editor Play). The editor's
-- fly_camera.lua hooks update_editor only — play-mode camera behavior is
-- project-owned by design — so without this, "Free Camera" has no driver in
-- the player. Mirrors the editor feel: hold RMB to look, WASD to fly.
local fly = { fwd = 0.0, side = 0.0, skip_rotation = false, smoothing = 12.0 }

local function free_fly(dt)
    if type(input) ~= "table" then return end
    local cam = get_camera and get_camera() or nil
    if not cam then return end
    dt = dt or last_dt

    local rmb = input.is_right_mouse_down and input.is_right_mouse_down()
        and input.is_viewport_focused and input.is_viewport_focused()
    if rmb then
        if input.set_relative_mouse and input.is_relative_mouse and not input.is_relative_mouse() then
            input.set_relative_mouse(true)
            fly.skip_rotation = true -- first relative delta is the warp jump; drop it
        end
        local mouse = input.get_mouse_delta and input.get_mouse_delta() or nil
        if mouse and not fly.skip_rotation then
            cam:rotate(mouse.x, mouse.y)
        else
            fly.skip_rotation = false
        end
    elseif input.is_relative_mouse and input.set_relative_mouse and input.is_relative_mouse() then
        input.set_relative_mouse(false)
    end

    local target_fwd, target_side = 0.0, 0.0
    if rmb and input.is_key_down then
        if input.is_key_down("W") then target_fwd = target_fwd + 1.0 end
        if input.is_key_down("S") then target_fwd = target_fwd - 1.0 end
        if input.is_key_down("D") then target_side = target_side + 1.0 end
        if input.is_key_down("A") then target_side = target_side - 1.0 end
    end

    local k = 1.0 - math.exp(-fly.smoothing * dt)
    fly.fwd = fly.fwd + (target_fwd - fly.fwd) * k
    fly.side = fly.side + (target_side - fly.side) * k

    local mag = math.sqrt(fly.fwd * fly.fwd + fly.side * fly.side)
    if mag > 0.0001 then
        local speed = cam:get_speed() * dt
        local scale = mag > 1.0 and (1.0 / mag) or 1.0
        local f = fly.fwd * scale * speed
        local s = fly.side * scale * speed
        if f > 0.0 then cam:move("forward", f) elseif f < 0.0 then cam:move("backward", -f) end
        if s > 0.0 then cam:move("right", s) elseif s < 0.0 then cam:move("left", -s) end
    else
        fly.fwd, fly.side = 0.0, 0.0
    end
end

function update(dt)
    tick(dt)
    -- Edit mode keeps fly_camera.lua (update_editor); never double-drive.
    if props.follow == "" then
        free_fly(last_dt)
    end
end

function update_editor(dt)
    if props.animate_in_editor then
        tick(dt)
    end
end
