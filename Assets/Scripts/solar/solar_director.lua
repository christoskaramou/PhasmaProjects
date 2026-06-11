-- Per-node script on the SolarSystem root. Advances a simulated Julian date and
-- drives heliocentric planet positions (Standish ephemeris) + axial spins.
--
-- Node-name contract (created by build_solar_system.lua):
--   SolarSystem (this script)
--   |- Sun
--   |- <Name>_orbit            position set here (heliocentric)
--      |- <Name>_tilt          static Euler X = axial tilt
--         |- <Name>            spun about local Y here
--         |- <Name>_rings      (Saturn) static
--         |- Moon_orbit        (Earth) local circular orbit set here
--            |- Moon           tidally-locked spin

local function load_module(path)
    local source = fs and fs.read and fs.read(path) or nil
    if not source then error("PhasmaSpace: missing module " .. path) end
    local chunk, err = load(source, "@" .. assets_path .. path, "t", _ENV)
    if not chunk then error(err) end
    return chunk()
end

local E = load_module("Scripts/solar/ephemeris.lua")
local P = load_module("Scripts/solar/planets.lua")
local UI = load_module("Scripts/solar/solar_ui.lua")

local props = exposed {
    time_scale        = 1.0 / 86400.0, -- sim days per real second; default = real time (0 freezes)
    epoch_jd          = 2461201.5, -- 2026-06-10 00:00 UTC (verified vs Horizons)
    animate_in_editor = true,
    follow            = "Earth",   -- body to track with the camera ("" = free cam)
    follow_distance   = 6.0,       -- camera distance in multiples of body radius
    follow_orbit      = true,      -- drag RMB/MMB to orbit while following
    auto_exposure     = true,      -- expose for the followed body (camera-style)
}

local function pos(x, y, z)
    return { x = x, y = y, z = z }
end

local function zero_pos()
    return pos(0.0, 0.0, 0.0)
end

local function pos_from_vec3(v)
    return pos(v.x, v.y, v.z)
end

local function to_vec3(v)
    return vec3(v.x, v.y, v.z)
end

local function shifted(v, by)
    return pos(v.x + by.x, v.y + by.y, v.z + by.z)
end

local function shifted_vec3(v, by)
    return vec3(v.x + by.x, v.y + by.y, v.z + by.z)
end

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

local function points_to_vec3(points)
    local out = {}
    for i, p in ipairs(points) do
        out[i] = to_vec3(p)
    end
    return out
end

local sim_days = 0.0
local handles = {}  -- node name -> SceneNodeHandle
local sun_light_node = nil
local scene_shift = zero_pos()
local universe_positions = {} -- body name -> heliocentric world position before root rebase
local moon_locals = {}        -- moon name -> local orbit position before parent planet tilt

local function index_children(h)
    for _, child in ipairs(h:get_children()) do
        handles[child:get_name()] = child
        index_children(child)
    end
end

-- Orbit lines: sampled from the real ephemeris into closed polyline ribbons.
-- Rebuilt from scratch on every load (polyline meshes do not round-trip through
-- the .pescene), so any stale serialized "Orbits" tree is removed first.
--
-- Ribbons are rebuilt at load/epoch only. Planet orbit vertices stay in
-- heliocentric coordinates and the Orbits root receives the floating-origin
-- shift, so ticks never mutate ribbon geometry. Keep widths small and body-scale
-- bounded; screen-constant widths require geometry rebuilds and cause editor
-- catch-up hitches when scripts mutate scene meshes during ticks.
local ORBIT_MIN_WIDTH = 0.003
local ORBIT_MAX_WIDTH = 0.08
local MOON_ORBIT_MAX_WIDTH = 0.04
local ORBIT_BODY_WIDTH_FRACTION = 0.08
local ORBIT_MIN_SAMPLES = 240
local ORBIT_MAX_SAMPLES = 4096
local ORBIT_SAGITTA_RADIUS_FRACTION = 0.2
local MOON_ORBIT_SEGMENT_TARGET = 0.75
local FREE_REBASE_DISTANCE = 1000.0
local FOLLOW_ORBIT_SENSITIVITY = 0.0035
local FOLLOW_ORBIT_PITCH_LIMIT = math.rad(84.0)

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

local function orbit_width_for_line(o)
    local width = o and o.fixed_width or ORBIT_MIN_WIDTH
    local cap = o and o.width_cap or ORBIT_MAX_WIDTH
    if width < ORBIT_MIN_WIDTH then width = ORBIT_MIN_WIDTH end
    if width > cap then width = cap end
    return width
end

local function orbit_normal_from_points(pts)
    local samples = #pts
    local p1, p2 = pts[1], pts[math.floor(samples / 4)]
    local nx = p1.y * p2.z - p1.z * p2.y
    local ny = p1.z * p2.x - p1.x * p2.z
    local nz = p1.x * p2.y - p1.y * p2.x
    local nl = math.sqrt(nx * nx + ny * ny + nz * nz)
    if nl < 1e-9 then nx, ny, nz, nl = 0.0, 1.0, 0.0, 1.0 end
    if ny < 0.0 then nx, ny, nz = -nx, -ny, -nz end
    return pos(nx / nl, ny / nl, nz / nl)
end

local function sample_planet_orbit(o, jd)
    local pts = {}
    for i = 0, o.samples - 1 do
        local sample_jd = jd + (i / o.samples) * o.period_days
        local x, y, z = E.heliocentric(o.body, sample_jd)
        pts[#pts + 1] = pos(x * P.AU_UNITS, z * P.AU_UNITS, y * P.AU_UNITS)
    end
    local normal = orbit_normal_from_points(pts)
    o.pts = pts
    o.normal = to_vec3(normal)
    o.anchor_jd = jd
end

local function orbit_width_for_radius(radius_units, cap)
    local width = radius_units * ORBIT_BODY_WIDTH_FRACTION
    if width < ORBIT_MIN_WIDTH then width = ORBIT_MIN_WIDTH end
    if width > cap then width = cap end
    return width
end

local function rebuild_orbit_line(name, o, width, jd)
    if o.body and jd then
        sample_planet_orbit(o, jd)
    end

    if o.node then o.node:remove() end
    local line = scene.add_empty_node("Orbit_" .. name)
    line:set_parent(o.parent_node or handles["Orbits"])
    local pts = points_to_vec3(o.pts)
    scene.attach_polyline(line, pts, width, o.normal, true)
    material.set(line, "base_color", vec4(0.0, 0.0, 0.0, 1.0))
    material.set(line, "emissive", vec3(1.5, 2.8, 5.0))
    material.set(line, "roughness", 1.0)
    material.set(line, "metallic", 0.0)
    o.node = line
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
    if not lights or not lights.get_point_lights or not lights.set_point_light then return end
    local sun_light = choose_sun_point_light(lights.get_point_lights())
    if not sun_light then return end
    if (not sun_light_node or not sun_light_node:is_valid()) and sun_light.name and scene.find_model then
        sun_light_node = scene.find_model(sun_light.name)
    end
    if sun_light_node and sun_light_node:is_valid() then
        sun_light_node:set_position(to_vec3(world_pos))
    end
    lights.set_point_light(sun_light.index or 0,
                           to_vec3(world_pos),
                           sun_light.color or vec3(1.0, 0.96, 0.9),
                           sun_light.intensity or 4.9e8,
                           sun_light.radius or 5.0e6)
end

local function build_orbit_lines(jd)
    if handles["Orbits"] then
        handles["Orbits"]:remove()
        handles["Orbits"] = nil
    end
    local orbits = scene.add_empty_node("Orbits")
    orbits:set_parent(self)
    handles["Orbits"] = orbits

    for _, p in ipairs(P.planets) do
        local a_units = E.elements[p.body][1] * P.AU_UNITS
        local period_days = (E.elements[p.body][1] ^ 1.5) * 365.25
        local o = {
            body = p.body,
            samples = orbit_sample_count(a_units, P.radius_units(p.radius_km)),
            period_days = period_days,
            fixed_width = orbit_width_for_radius(P.radius_units(p.radius_km), ORBIT_MAX_WIDTH),
            width_cap = ORBIT_MAX_WIDTH,
            node = nil,
        }
        sample_planet_orbit(o, jd)
        rebuild_orbit_line(p.name, o, orbit_width_for_line(o))

        local tilt = handles[p.name .. "_tilt"]
        if tilt then
            for _, m in ipairs(p.moons or {}) do
                local ma = P.dist_units(m.a_km) * (m.dist_scale or 1.0)
                local msamples = moon_orbit_sample_count(ma)
                local mpts = {}
                local ci = math.cos(math.rad(m.incl))
                local si = math.sin(math.rad(m.incl))
                for i = 0, msamples - 1 do
                    local ang = 2.0 * math.pi * (i / msamples)
                    mpts[#mpts + 1] = pos(ma * math.cos(ang), ma * math.sin(ang) * si, ma * math.sin(ang) * ci)
                end
                local normal = orbit_normal_from_points(mpts)
                local mo = {
                    pts = mpts,
                    normal = to_vec3(normal),
                    parent_node = tilt,
                    fixed_width = orbit_width_for_radius(P.radius_units(m.radius_km), MOON_ORBIT_MAX_WIDTH),
                    width_cap = MOON_ORBIT_MAX_WIDTH,
                    node = nil,
                }
                rebuild_orbit_line(m.name, mo, orbit_width_for_line(mo))
            end
        end
    end
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

local function atan2(y, x)
    if x > 0.0 then
        return math.atan(y / x)
    elseif x < 0.0 and y >= 0.0 then
        return math.atan(y / x) + math.pi
    elseif x < 0.0 then
        return math.atan(y / x) - math.pi
    elseif y > 0.0 then
        return math.pi * 0.5
    elseif y < 0.0 then
        return -math.pi * 0.5
    end
    return 0.0
end

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

    local yaw = atan2(t, r) + yaw_delta
    local pitch = atan2(u, math.sqrt(r * r + t * t)) + pitch_delta
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
    self:set_position(vec3(0.0, 0.0, 0.0))
    if props.follow == "" then
        follow_state.target = ""
        release_follow_orbit_mouse()
        set_editor_fly_camera_blocked(false)
        local cam = get_camera and get_camera() or nil
        if cam then
            local cp = pos_from_vec3(cam:get_position())
            if length_pos(cp) > FREE_REBASE_DISTANCE then
                scene_shift = pos(scene_shift.x - cp.x, scene_shift.y - cp.y, scene_shift.z - cp.z)
                cam:set_position(vec3(0.0, 0.0, 0.0))
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

    scene_shift = pos(-universe_target.x, -universe_target.y, -universe_target.z)
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
        universe_target = unshifted(pos_from_vec3(body:get_world_position()), scene_shift)
    end
    local target = shifted(universe_target, scene_shift)
    if props.follow == "Sun" then
        -- The Sun sits at the origin, so metering its own solar distance (d=0)
        -- clamps exposure to the floor and blacks out every planet; meter the
        -- scene as if at 1 AU instead.
        apply_exposure(pos(P.AU_UNITS, 0.0, 0.0))
    else
        apply_exposure(universe_target)
    end
    local radius = body:get_scale().x
    -- The Sun is enormous (208.7 u): the default 6-radius distance fills the
    -- whole view. Keep sun viewing at >= 25 radii; wheel zoom still works above.
    local dist_mult = props.follow == "Sun" and math.max(props.follow_distance, 25.0)
        or props.follow_distance
    local dist = math.max(dist_mult * radius, radius * 2.0)
    local rx, ry, rz, ux, uy, uz, tx, ty, tz = solar_frame(universe_target)

    local orbiting_follow = apply_follow_orbit_input()
    local cp = pos_from_vec3(cam:get_position())
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
        local moved = math.sqrt((cp.x - e.x) ^ 2 + (cp.y - e.y) ^ 2 + (cp.z - e.z) ^ 2)
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
        local ox, oy, oz = cp.x - target.x, cp.y - target.y, cp.z - target.z
        local olen = math.sqrt(ox * ox + oy * oy + oz * oz)
        if olen > radius * 0.5 then
            follow_state.r = (ox * rx + oy * ry + oz * rz) / olen
            follow_state.u = (ox * ux + oy * uy + oz * uz) / olen
            follow_state.t = (ox * tx + oy * ty + oz * tz) / olen
        end
    end
    follow_state.target = props.follow

    local n = math.sqrt(follow_state.r ^ 2 + follow_state.u ^ 2 + follow_state.t ^ 2)
    local fr, fu, ft = follow_state.r / n * dist, follow_state.u / n * dist, follow_state.t / n * dist
    local px = target.x + rx * fr + ux * fu + tx * ft
    local py = target.y + ry * fr + uy * fu + ty * ft
    local pz = target.z + rz * fr + uz * fu + tz * ft
    cam:set_position(vec3(px, py, pz))
    cam:look_at(to_vec3(target))
    follow_state.expected = pos(px, py, pz)
end

local function spin_deg(jd, rot_h)
    local days_per_turn = math.abs(rot_h) / 24.0
    local turns = (jd - E.J2000) / days_per_turn
    local deg = (turns % 1.0) * 360.0
    if rot_h < 0 then deg = -deg end
    return deg
end

local function compute_universe_positions(jd)
    universe_positions = {}
    universe_positions["Sun"] = zero_pos()
    moon_locals = {}
    for _, p in ipairs(P.planets) do
        local x, y, z = E.heliocentric(p.body, jd)  -- AU, J2000 ecliptic
        -- ecliptic -> engine: x->X, y->Z, z->Y (ecliptic north = +Y)
        local planet_pos = pos(x * P.AU_UNITS, z * P.AU_UNITS, y * P.AU_UNITS)
        universe_positions[p.name] = planet_pos

        for _, m in ipairs(p.moons or {}) do
            -- Demo simplification: circular orbit, inclined about X.
            local ang = 2.0 * math.pi * (((jd - E.J2000) / m.period_d) % 1.0)
            local a = P.dist_units(m.a_km) * (m.dist_scale or 1.0)
            local ci = math.cos(math.rad(m.incl))
            local si = math.sin(math.rad(m.incl))
            local moon_local = pos(a * math.cos(ang), a * math.sin(ang) * si, a * math.sin(ang) * ci)
            moon_locals[m.name] = moon_local
            universe_positions[m.name] = shifted(planet_pos, rotate_x(moon_local, p.tilt))
        end
    end
end

local function apply_scene_positions(jd)
    local orbits = handles["Orbits"]
    if orbits then
        orbits:set_position(to_vec3(scene_shift))
    end

    local sun = handles["Sun"]
    if sun then
        sun:set_position(to_vec3(scene_shift))
    end

    for _, p in ipairs(P.planets) do
        local planet_pos = universe_positions[p.name]
        local orbit = handles[p.name .. "_orbit"]
        local body = handles[p.name]
        if orbit and planet_pos then
            orbit:set_position(shifted_vec3(planet_pos, scene_shift))
        end
        if body then
            body:set_rotation(vec3(0.0, spin_deg(jd, p.rot_h), 0.0))
        end

        if p.clouds then
            local clouds = handles[p.name .. "_clouds"]
            if clouds then
                clouds:set_rotation(vec3(0.0, spin_deg(jd, p.clouds.rot_h), 0.0))
            end
        end

        for _, m in ipairs(p.moons or {}) do
            local morbit = handles[m.name .. "_orbit"]
            local moon_local = moon_locals[m.name]
            if morbit and moon_local then
                morbit:set_position(to_vec3(moon_local))
            end

            local mbody = handles[m.name]
            if mbody then
                -- Tidally locked: one rotation per orbit.
                local mdeg = (((jd - E.J2000) / m.period_d) % 1.0) * 360.0
                mbody:set_rotation(vec3(0.0, mdeg, 0.0))
            end
        end
    end
end

local function tick()
    local dt = engine.get_metrics().delta_ms * 0.001
    if dt > 0.25 then dt = 0.25 end  -- ignore hitches (loads, resizes)
    sim_days = sim_days + dt * props.time_scale
    local jd = props.epoch_jd + sim_days

    compute_universe_positions(jd)
    update_scene_shift()
    apply_scene_positions(jd)

    UI.tick({ props = props, handles = handles, planets = P })
    follow_camera()
end

function init()
    handles = {}
    index_children(self)
    self:set_position(vec3(0.0, 0.0, 0.0))
    scene_shift = zero_pos()
    local jd = props.epoch_jd + sim_days
    compute_universe_positions(jd)
    update_scene_shift()
    build_orbit_lines(jd)
    apply_scene_positions(jd)
    -- Re-apply per-load material state: night_emissive lives on the material,
    -- which round-trips the scene, but re-asserting it keeps older saved
    -- scenes correct without a rebuild.
    for _, p in ipairs(P.planets) do
        if p.night_tex and handles[p.name] then
            material.set(handles[p.name], "night_emissive", 1.0)
        end
    end
    UI.init({ props = props, handles = handles, planets = P })
    local n = 0
    for _ in pairs(handles) do n = n + 1 end
    pe_log("[solar] director bound, " .. tostring(n) .. " nodes indexed")
end

-- Free-camera flight for PLAY MODE (PhasmaPlayer + editor Play). The editor's
-- fly_camera.lua hooks update_editor only — play-mode camera behavior is
-- project-owned by design — so without this, "Free Camera" has no driver in
-- the player. Mirrors the editor feel: hold RMB to look, WASD to fly.
local fly = { fwd = 0.0, side = 0.0, skip_rotation = false, smoothing = 12.0 }

local function free_fly()
    local cam = get_camera and get_camera() or nil
    if not cam then return end
    local dt = engine.get_metrics().delta_ms * 0.001

    local rmb = input.is_right_mouse_down() and input.is_viewport_focused()
    if rmb then
        if not input.is_relative_mouse() then
            input.set_relative_mouse(true)
            fly.skip_rotation = true -- first relative delta is the warp jump; drop it
        end
        local mouse = input.get_mouse_delta()
        if not fly.skip_rotation then
            cam:rotate(mouse.x, mouse.y)
        else
            fly.skip_rotation = false
        end
    elseif input.is_relative_mouse() then
        input.set_relative_mouse(false)
    end

    local target_fwd, target_side = 0.0, 0.0
    if rmb then
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

function update()
    tick()
    -- Edit mode keeps fly_camera.lua (update_editor); never double-drive.
    if props.follow == "" then
        free_fly()
    end
end

function update_editor()
    if props.animate_in_editor then
        tick()
    end
end
