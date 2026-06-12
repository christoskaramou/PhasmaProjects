-- In-game control panel + HUD for the solar demo, built on runtime_ui (ImGui-backed,
-- works in editor viewport and PhasmaPlayer). The director calls M.init() once and
-- M.tick(ctx) every frame with ctx = { props, handles, planets }.
local M = {}

local PANEL = "solar_panel"
local HUD = "solar_hud"
local MARKERS = "solar_markers"
local C_LIGHT = 299792458.0 -- m/s
local M_PER_UNIT = 1.0e7    -- 1 engine unit = 10,000 km

M.bodies = {}

local state = {
    built = false,
    orbits_visible = true,
    markers_on = true,
    moon_info = {},
    last_follow = nil,
    last_ts_text = nil,
    last_speed_text = nil,
    prev_time_scale = 1.0 / 86400.0, -- real time
}

local function fmt_speed(mps)
    if mps >= 0.1 * C_LIGHT then
        return string.format("%.2f c", mps / C_LIGHT)
    elseif mps >= 1.0e6 then
        return string.format("%.1f Mm/s", mps / 1.0e6)
    elseif mps >= 1.0e3 then
        return string.format("%.1f km/s", mps / 1.0e3)
    end
    return string.format("%.0f m/s", mps)
end

local function build_body_list(ctx)
    local bodies = { "Sun" }
    local seen = { Sun = true }
    local always = {
        Moon = true, Phobos = true, Deimos = true,
        Io = true, Europa = true, Ganymede = true, Callisto = true,
        Charon = true, Styx = true, Nix = true, Kerberos = true, Hydra = true,
    }

    local function add(name)
        if name and not seen[name] then
            bodies[#bodies + 1] = name
            seen[name] = true
        end
    end

    for _, p in ipairs(ctx.planets.planets) do
        add(p.name)
        for _, m in ipairs(p.moons or {}) do
            if always[m.name] or (m.radius_km and m.radius_km >= 100.0) then
                add(m.name)
            end
        end
    end
    return bodies
end

function M.init(ctx)
    runtime_ui.clear(PANEL)
    M.bodies = build_body_list(ctx)
    runtime_ui.set_title(PANEL, "PhasmaSpace")
    runtime_ui.set_bool(PANEL, "orbits", "Orbit Lines", state.orbits_visible)
    runtime_ui.set_bool(PANEL, "markers", "Body Markers", state.markers_on)
    runtime_ui.set_bool(PANEL, "auto_exp", "Auto Exposure", ctx.props.auto_exposure)
    runtime_ui.set_bool(PANEL, "follow_orbit", "Orbit Follow Cam", ctx.props.follow_orbit ~= false)
    runtime_ui.set_text(PANEL, "ts", "Time Scale", string.format("%.2f days/s", ctx.props.time_scale))
    runtime_ui.set_button(PANEL, "ts_pause", "Pause / Resume")
    runtime_ui.set_button(PANEL, "ts_slow", "Time  /2")
    runtime_ui.set_button(PANEL, "ts_fast", "Time  x2")
    runtime_ui.set_button(PANEL, "spd_slow", "Cam Speed  /2")
    runtime_ui.set_button(PANEL, "spd_fast", "Cam Speed  x2")
    runtime_ui.set_text(PANEL, "follow_lbl", "Following", ctx.props.follow)
    runtime_ui.set_button(PANEL, "f_free", "Free Camera")
    for _, name in ipairs(M.bodies) do
        runtime_ui.set_button(PANEL, "f_" .. name, name)
    end
    runtime_ui.show(PANEL)

    runtime_ui.clear(HUD)
    runtime_ui.set_screen_overlay(HUD, true)
    runtime_ui.set_text(HUD, "speed", "Cam", "")
    runtime_ui.show(HUD)

    runtime_ui.clear(MARKERS)
    runtime_ui.set_screen_overlay(MARKERS, true)
    runtime_ui.show(MARKERS)

    -- moon -> parent map for marker decluttering (system-scale views would
    -- otherwise stack moon labels on top of their parent planets)
    state.moon_info = {}
    for _, p in ipairs(ctx.planets.planets) do
        for _, m in ipairs(p.moons or {}) do
            state.moon_info[m.name] = {
                parent = p.name,
                a_units = ctx.planets.dist_units(m.a_km) * (m.dist_scale or 1.0),
            }
        end
    end

    state.built = true
end

local function apply_orbit_visibility(ctx)
    local orbits = ctx.handles["Orbits"]
    if orbits then
        orbits:set_enabled(state.orbits_visible)
    end
end

-- Screen-space body markers: when a body is too far/small to see, draw a small
-- labeled chip at its projected position; clicking it follows that body. Moon
-- markers only appear near their parent planet so system-scale views don't
-- stack moon labels on their parent planets.
local MARKER_MAX_ANGULAR = 0.002 -- body angular radius below this -> show marker

local function update_markers(ctx)
    local cam = get_camera and get_camera() or nil
    if not cam then return end
    local surf = runtime_ui.get_surface_size() -- table: { w, h, valid }
    if not surf or not surf.valid then return end
    local sw, sh = surf.w, surf.h
    if not sw or not sh or sw <= 0 or sh <= 0 then return end

    local vp = cam:get_view_projection()
    local cp = cam:get_position()

    for _, name in ipairs(M.bodies) do
        local id = "m_" .. name
        local body = ctx.handles[name]
        local shown = false
        if state.markers_on and body and name ~= ctx.props.follow then
            local wp = body:get_world_position()
            local dx, dy, dz = wp.x - cp.x, wp.y - cp.y, wp.z - cp.z
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            local small = dist > 0.0 and (body:get_scale().x / dist) < MARKER_MAX_ANGULAR
            local moon = state.moon_info[name]
            if small and moon then
                local parent = ctx.handles[moon.parent]
                if parent then
                    local pp = parent:get_world_position()
                    local pd = math.sqrt((pp.x - cp.x) ^ 2 + (pp.y - cp.y) ^ 2 + (pp.z - cp.z) ^ 2)
                    if pd > moon.a_units * 30.0 then small = false end
                end
            end
            if small then
                local c = vp * vec4(wp.x, wp.y, wp.z, 1.0)
                if c.w > 0.0 then -- in front of the camera
                    local nx, ny = c.x / c.w, c.y / c.w
                    if nx > -1.0 and nx < 1.0 and ny > -1.0 and ny < 1.0 then
                        -- engine NDC is y-down: +y maps down the screen
                        local sx = (nx * 0.5 + 0.5) * sw
                        local sy = (ny * 0.5 + 0.5) * sh
                        runtime_ui.set_quad(MARKERS, id, {
                            x = sx - 45.0, y = sy + 8.0, width = 90.0, height = 32.0,
                            label = name, font_scale = 1.0, visible = true,
                            -- colors are plain tables: vec4 userdata is ignored by ReadColorOption
                            fill = { 0.05, 0.09, 0.16, 0.55 },
                            accent = { 0.05, 0.09, 0.16, 0.0 },
                            border = { 0.45, 0.70, 1.00, 0.8 },
                            text_color = { 0.85, 0.93, 1.00, 0.95 },
                        })
                        shown = true
                        local st = runtime_ui.get_state(MARKERS, id)
                        if st and st.clicked then ctx.props.follow = name end
                    end
                end
            end
        end
        if not shown then
            runtime_ui.set_quad(MARKERS, id, { x = -1000.0, y = -1000.0, width = 8.0, height = 8.0, visible = false })
        end
    end
end

function M.tick(ctx)
    if not state.built then return end
    local props = ctx.props

    -- toggles
    local orbits_now = runtime_ui.get_bool(PANEL, "orbits", state.orbits_visible)
    if orbits_now ~= state.orbits_visible then
        state.orbits_visible = orbits_now
        apply_orbit_visibility(ctx)
    end
    props.auto_exposure = runtime_ui.get_bool(PANEL, "auto_exp", props.auto_exposure)
    props.follow_orbit = runtime_ui.get_bool(PANEL, "follow_orbit", props.follow_orbit ~= false)
    state.markers_on = runtime_ui.get_bool(PANEL, "markers", state.markers_on)
    update_markers(ctx)

    -- time controls
    if runtime_ui.consume_click(PANEL, "ts_pause") then
        if props.time_scale ~= 0.0 then
            state.prev_time_scale = props.time_scale
            props.time_scale = 0.0
        else
            props.time_scale = state.prev_time_scale
        end
    end
    if runtime_ui.consume_click(PANEL, "ts_slow") then
        props.time_scale = props.time_scale / 2.0
        -- floor well below real time (1.157e-5 days/s) so halving can't zero it
        if math.abs(props.time_scale) < 1e-7 then props.time_scale = 0.0 end
    end
    if runtime_ui.consume_click(PANEL, "ts_fast") then
        if props.time_scale == 0.0 then
            props.time_scale = 1.0 / 86400.0 -- resume at real time
        else
            props.time_scale = props.time_scale * 2.0
        end
    end
    -- readable as a multiple of real time (1x = wall clock)
    local ts_text = props.time_scale == 0.0 and "paused"
        or string.format("%.4gx real", props.time_scale * 86400.0)
    if ts_text ~= state.last_ts_text then
        runtime_ui.set_text(PANEL, "ts", "Time Scale", ts_text)
        state.last_ts_text = ts_text
    end

    -- follow picker
    if runtime_ui.consume_click(PANEL, "f_free") then
        props.follow = ""
        -- editor default fly speed is meter-scale; at 1 u = 10,000 km it reads as
        -- frozen. Give free cam a usable starting speed (wheel/buttons adjust).
        local cam0 = get_camera and get_camera() or nil
        if cam0 and cam0:get_speed() < 150.0 then
            cam0:set_speed(150.0)
        end
    end
    for _, name in ipairs(M.bodies) do
        if runtime_ui.consume_click(PANEL, "f_" .. name) then
            props.follow = name
        end
    end
    if props.follow ~= state.last_follow then
        runtime_ui.set_text(PANEL, "follow_lbl", "Following", props.follow ~= "" and props.follow or "(free)")
        state.last_follow = props.follow
    end

    -- camera speed: panel buttons always work; the wheel zooms the followed body
    -- or, in free cam, scales fly speed.
    local cam = get_camera and get_camera() or nil
    if cam then
        local function scale_speed(f)
            local speed = cam:get_speed() * f
            if speed < 0.01 then speed = 0.01 end
            if speed > 100000.0 then speed = 100000.0 end
            cam:set_speed(speed)
        end
        if runtime_ui.consume_click(PANEL, "spd_slow") then scale_speed(0.5) end
        if runtime_ui.consume_click(PANEL, "spd_fast") then scale_speed(2.0) end

        local wheel = input.get_mouse_wheel and input.get_mouse_wheel() or nil
        local wy = 0.0
        if type(wheel) == "table" then
            wy = wheel.y or wheel[2] or 0.0
        elseif type(wheel) == "number" then
            wy = wheel
        end
        if wy ~= 0.0 then
            if props.follow ~= "" then
                -- wheel-up zooms in on the followed body
                local d = props.follow_distance * (0.85 ^ wy)
                if d < 2.0 then d = 2.0 end
                if d > 500.0 then d = 500.0 end
                props.follow_distance = d
            else
                scale_speed(1.25 ^ wy)
            end
        end

        local text = fmt_speed(cam:get_speed() * M_PER_UNIT)
        if props.follow ~= "" then
            text = text .. string.format("  |  zoom %.1f R", props.follow_distance)
        end
        if text ~= state.last_speed_text then
            runtime_ui.set_text(HUD, "speed", "Cam", text)
            state.last_speed_text = text
        end
    end
end

return M
