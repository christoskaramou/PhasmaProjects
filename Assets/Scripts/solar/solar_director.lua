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

local props = exposed {
    time_scale        = 2.0,       -- simulated days per real second (0 freezes)
    epoch_jd          = 2461201.5, -- 2026-06-10 00:00 UTC (verified vs Horizons)
    animate_in_editor = true,
    follow            = "Earth",   -- body to track with the camera ("" = free cam)
    follow_distance   = 6.0,       -- camera distance in multiples of body radius
}

local sim_days = 0.0
local handles = {}  -- node name -> SceneNodeHandle

local function index_children(h)
    for _, child in ipairs(h:get_children()) do
        handles[child:get_name()] = child
        index_children(child)
    end
end

-- Track a body with the active camera: keep the current viewing direction but
-- re-anchor position to the (moving) target each frame. Orbit/zoom by hand still
-- works; clear `follow` in the Properties panel for a fully free camera.
local function follow_camera()
    if props.follow == "" then return end
    local body = handles[props.follow]
    local cam = get_camera and get_camera() or nil
    if not body or not cam then return end

    local target = body:get_world_position()
    local radius = body:get_scale().x
    local dist = math.max(props.follow_distance * radius, radius * 2.0)

    local cp = cam:get_position()
    local dx, dy, dz = cp.x - target.x, cp.y - target.y, cp.z - target.z
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < radius * 0.5 or len > dist * 50.0 then
        -- camera lost (inside the body or far away): snap to a pleasant angle
        dx, dy, dz = 0.94, 0.23, 0.94
        len = math.sqrt(dx * dx + dy * dy + dz * dz)
    end
    local s = dist / len
    cam:set_position(vec3(target.x + dx * s, target.y + dy * s, target.z + dz * s))
    cam:look_at(target)
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

        if p.moon then
            local morbit = handles[p.moon.name .. "_orbit"]
            local mbody = handles[p.moon.name]
            if morbit then
                -- Demo simplification: circular orbit, inclined about X.
                local ang = 2.0 * math.pi * (((jd - E.J2000) / p.moon.period_d) % 1.0)
                local a = P.dist_units(p.moon.a_km)
                local ci = math.cos(math.rad(p.moon.incl))
                local si = math.sin(math.rad(p.moon.incl))
                morbit:set_position(vec3(a * math.cos(ang), a * math.sin(ang) * si, a * math.sin(ang) * ci))
            end
            if mbody then
                -- Tidally locked: one rotation per orbit.
                local mdeg = (((jd - E.J2000) / p.moon.period_d) % 1.0) * 360.0
                mbody:set_rotation(vec3(0.0, mdeg, 0.0))
            end
        end
    end

    follow_camera()
end

function init()
    index_children(self)
    local n = 0
    for _ in pairs(handles) do n = n + 1 end
    pe_log("[solar] director bound, " .. tostring(n) .. " nodes indexed")
end

function update()
    tick()
end

function update_editor()
    if props.animate_in_editor then
        tick()
    end
end
