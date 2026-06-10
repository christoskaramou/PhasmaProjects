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
    auto_exposure     = true,      -- expose for the followed body (camera-style)
}

local sim_days = 0.0
local handles = {}  -- node name -> SceneNodeHandle

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
-- Width is ~constant in SCREEN space: each ribbon is sized to a fixed angular
-- width from the camera's distance to that orbit's ring and rebuilt only when
-- the desired width drifts >25% (geometry rebuilds are not per-frame work).
local ORBIT_ANGULAR_WIDTH = 0.003 -- world width per unit of camera distance (~3 px)
local orbit_lines = {}            -- planet name -> { pts, normal, node, width, a_units }

local function orbit_camera_distance(o, cp)
    -- True distance to the polyline: nearest point on each SEGMENT of the closed
    -- loop. Vertex distance alone is not enough — 160 samples around Earth's
    -- orbit sit ~590 u apart, so right next to a planet (camera ~4 u from its
    -- own orbit line at true scale) the nearest vertex can still be hundreds of
    -- units away, inflating the ribbon enormously.
    local pts = o.pts
    local n = #pts
    local best = math.huge
    local ax, ay, az = pts[n].x, pts[n].y, pts[n].z -- closed: last -> first
    for i = 1, n do
        local b = pts[i]
        local bx, by, bz = b.x, b.y, b.z
        local ex, ey, ez = bx - ax, by - ay, bz - az
        local wx, wy, wz = cp.x - ax, cp.y - ay, cp.z - az
        local ee = ex * ex + ey * ey + ez * ez
        local t = ee > 0.0 and (wx * ex + wy * ey + wz * ez) / ee or 0.0
        if t < 0.0 then t = 0.0 elseif t > 1.0 then t = 1.0 end
        local dx, dy, dz = wx - ex * t, wy - ey * t, wz - ez * t
        local d2 = dx * dx + dy * dy + dz * dz
        if d2 < best then best = d2 end
        ax, ay, az = bx, by, bz
    end
    return math.sqrt(best)
end

local function rebuild_orbit_line(name, o, width)
    if o.node then o.node:remove() end
    local line = scene.add_empty_node("Orbit_" .. name)
    line:set_parent(handles["Orbits"])
    scene.attach_polyline(line, o.pts, width, o.normal, true)
    material.set(line, "base_color", vec4(0.0, 0.0, 0.0, 1.0))
    material.set(line, "emissive", vec3(1.5, 2.8, 5.0))
    material.set(line, "roughness", 1.0)
    material.set(line, "metallic", 0.0)
    o.node = line
    o.width = width
end

local function build_orbit_lines()
    if handles["Orbits"] then
        handles["Orbits"]:remove()
        handles["Orbits"] = nil
    end
    local orbits = scene.add_empty_node("Orbits")
    orbits:set_parent(self)
    handles["Orbits"] = orbits
    orbit_lines = {}

    local cam = get_camera and get_camera() or nil
    local cp = cam and cam:get_position() or vec3(0.0, 0.0, 0.0)

    for _, p in ipairs(P.planets) do
        local a = E.elements[p.body][1]               -- semi-major axis [AU]
        local period_days = (a ^ 1.5) * 365.25
        local samples = 160
        local pts = {}
        for i = 0, samples - 1 do
            local jd = E.J2000 + (i / samples) * period_days
            local x, y, z = E.heliocentric(p.body, jd)
            pts[#pts + 1] = vec3(x * P.AU_UNITS, z * P.AU_UNITS, y * P.AU_UNITS)
        end

        -- ribbon plane normal from two radius vectors of this orbit
        local p1, p2 = pts[1], pts[math.floor(samples / 4)]
        local nx = p1.y * p2.z - p1.z * p2.y
        local ny = p1.z * p2.x - p1.x * p2.z
        local nz = p1.x * p2.y - p1.y * p2.x
        local nl = math.sqrt(nx * nx + ny * ny + nz * nz)
        if nl < 1e-9 then nx, ny, nz, nl = 0.0, 1.0, 0.0, 1.0 end
        -- Ribbons with downward-facing plane normals do not render (engine quirk):
        -- keep the normal in the upper hemisphere; the tilt is preserved.
        if ny < 0.0 then nx, ny, nz = -nx, -ny, -nz end

        local o = {
            pts = pts,
            normal = vec3(nx / nl, ny / nl, nz / nl),
            a_units = a * P.AU_UNITS,
            node = nil,
            width = 0.0,
        }
        orbit_lines[p.name] = o
        rebuild_orbit_line(p.name, o, math.max(orbit_camera_distance(o, cp), 1.0) * ORBIT_ANGULAR_WIDTH)
    end
end

local function update_orbit_widths()
    local cam = get_camera and get_camera() or nil
    if not cam then return end
    local cp = cam:get_position()
    for name, o in pairs(orbit_lines) do
        local want = math.max(orbit_camera_distance(o, cp), 1.0) * ORBIT_ANGULAR_WIDTH
        if want > o.width * 1.25 or want < o.width * 0.8 then
            rebuild_orbit_line(name, o, want)
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

-- Track a body with the active camera. The offset is stored in the body's rotating
-- SOLAR frame (radial = away from sun, vertical, tangential), so the phase angle you
-- chose stays put while the body sweeps along its orbit — re-deriving the offset from
-- the lagged camera position would make the camera trail the orbit and lock every
-- view to the terminator. Dragging the camera by hand adopts the new angle; clear
-- `follow` in the Properties panel for a fully free camera.
local follow_state = { target = "", r = -0.82, u = 0.25, t = -0.51, expected = nil }

local function solar_frame(p)
    local len = math.sqrt(p.x * p.x + p.y * p.y + p.z * p.z)
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

local function follow_camera()
    if props.follow == "" then follow_state.target = "" return end
    local body = handles[props.follow]
    local cam = get_camera and get_camera() or nil
    if not body or not cam then return end

    local target = body:get_world_position()
    if props.follow == "Sun" then
        -- The Sun sits at the origin, so metering its own solar distance (d=0)
        -- clamps exposure to the floor and blacks out every planet; meter the
        -- scene as if at 1 AU instead.
        apply_exposure(vec3(P.AU_UNITS, 0.0, 0.0))
    else
        apply_exposure(target)
    end
    local radius = body:get_scale().x
    -- The Sun is enormous (208.7 u): the default 6-radius distance fills the
    -- whole view. Keep sun viewing at >= 25 radii; wheel zoom still works above.
    local dist_mult = props.follow == "Sun" and math.max(props.follow_distance, 25.0)
        or props.follow_distance
    local dist = math.max(dist_mult * radius, radius * 2.0)
    local rx, ry, rz, ux, uy, uz, tx, ty, tz = solar_frame(target)

    local cp = cam:get_position()
    local switched = follow_state.target ~= props.follow
    -- Adopt a user-chosen angle only after TWO consecutive displaced frames:
    -- single-frame displacement can come from editor camera damping or pipeline
    -- timing and adopting it caused slow tangential lag on fast moons (Io).
    local dragged = false
    if not switched and follow_state.expected then
        local e = follow_state.expected
        local moved = math.sqrt((cp.x - e.x) ^ 2 + (cp.y - e.y) ^ 2 + (cp.z - e.z) ^ 2)
        if moved > dist * 0.02 then
            follow_state.drag_frames = (follow_state.drag_frames or 0) + 1
        else
            follow_state.drag_frames = 0
        end
        dragged = (follow_state.drag_frames or 0) >= 2
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
    cam:look_at(target)
    follow_state.expected = { x = px, y = py, z = pz }
end

local function spin_deg(jd, rot_h)
    local days_per_turn = math.abs(rot_h) / 24.0
    local turns = (jd - E.J2000) / days_per_turn
    local deg = (turns % 1.0) * 360.0
    if rot_h < 0 then deg = -deg end
    return deg
end

local function tick()
    local dt = engine.get_metrics().delta_ms * 0.001
    if dt > 0.25 then dt = 0.25 end  -- ignore hitches (loads, resizes)
    sim_days = sim_days + dt * props.time_scale
    local jd = props.epoch_jd + sim_days

    for _, p in ipairs(P.planets) do
        local orbit = handles[p.name .. "_orbit"]
        local body = handles[p.name]
        if orbit then
            local x, y, z = E.heliocentric(p.body, jd)  -- AU, J2000 ecliptic
            -- ecliptic -> engine: x->X, y->Z, z->Y (ecliptic north = +Y)
            orbit:set_position(vec3(x * P.AU_UNITS, z * P.AU_UNITS, y * P.AU_UNITS))
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
            local mbody = handles[m.name]
            if morbit then
                -- Demo simplification: circular orbit, inclined about X.
                local ang = 2.0 * math.pi * (((jd - E.J2000) / m.period_d) % 1.0)
                local a = P.dist_units(m.a_km) * (m.dist_scale or 1.0)
                local ci = math.cos(math.rad(m.incl))
                local si = math.sin(math.rad(m.incl))
                morbit:set_position(vec3(a * math.cos(ang), a * math.sin(ang) * si, a * math.sin(ang) * ci))
            end
            if mbody then
                -- Tidally locked: one rotation per orbit.
                local mdeg = (((jd - E.J2000) / m.period_d) % 1.0) * 360.0
                mbody:set_rotation(vec3(0.0, mdeg, 0.0))
            end
        end
    end

    UI.tick({ props = props, handles = handles, planets = P })
    follow_camera()
    update_orbit_widths()
end

function init()
    index_children(self)
    build_orbit_lines()
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
