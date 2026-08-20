-- camera.lua — orbit camera locked to the board.
--
-- Right-drag orbits, wheel zooms, and that is all: no WASD, no free flight, and the
-- camera cannot descend below the board surface or pass over the top. The engine's
-- fly_camera_play.lua stays on the camera node for EDITOR navigation only (run mode
-- "editor"), so during play this module is the sole owner of the camera.
--
-- Left mouse belongs to piece selection, which is why orbit is on the right button.

local cam = {}

local target                 -- board centre, on the playing surface
local yaw, pitch, dist       -- spherical offset from the target
local ORBIT = 0.005          -- radians per pixel of drag
local ZOOM = 0.12            -- fraction of distance per wheel notch

-- Elevation limits. The lower bound is what keeps the view above the board: at 10° the
-- eye still sits clear of the surface, so you never see the underside. The upper bound
-- stops just short of straight down, where yaw becomes meaningless and look_at degenerates.
local MIN_PITCH, MAX_PITCH = math.rad(10), math.rad(85)
local MIN_DIST, MAX_DIST = 0.30, 1.40

-- LuaJIT is 5.1, where two-argument arctangent is math.atan2.
local atan2 = math.atan2 or math.atan

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function apply()
    local c = scene.get_active_camera()
    if not c then return end
    local flat = math.cos(pitch) * dist
    c:set_position(vec3(target.x + math.sin(yaw) * flat,
                        target.y + math.sin(pitch) * dist,
                        target.z + math.cos(yaw) * flat))
    -- look_at derives pitch/yaw from the direction itself, which sidesteps the camera's
    -- radians-based set_euler entirely.
    c:look_at(target)
end

-- Adopt whatever viewpoint the scene was authored with, so entering play does not snap
-- the view somewhere else.
function cam.init(board)
    target = vec3(0.0, board.top_y, 0.0)
    local c = scene.get_active_camera()
    local p = c and c:get_position() or vec3(0.0, 0.42, -0.55)
    local dx, dy, dz = p.x - target.x, p.y - target.y, p.z - target.z
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 1e-4 then dx, dy, dz, len = 0.0, 0.4, -0.55, 0.68 end

    dist = clamp(len, MIN_DIST, MAX_DIST)
    pitch = clamp(math.asin(clamp(dy / len, -1.0, 1.0)), MIN_PITCH, MAX_PITCH)
    yaw = atan2(dx, dz)
    apply()
end

-- `allow_zoom` is false while the cursor is over the move list, which scrolls with the
-- same wheel; without the gate one notch would scroll the list AND pull the camera in.
function cam.update(allow_zoom)
    if not target then return end
    local moved = false

    if input.is_right_mouse_down() then
        local d = input.get_mouse_delta()
        if d.x ~= 0 or d.y ~= 0 then
            yaw = yaw - d.x * ORBIT
            pitch = clamp(pitch + d.y * ORBIT, MIN_PITCH, MAX_PITCH)
            moved = true
        end
    end

    local wheel = input.get_mouse_wheel()
    if wheel.y ~= 0 and allow_zoom ~= false then
        dist = clamp(dist * (1.0 - wheel.y * ZOOM), MIN_DIST, MAX_DIST)
        moved = true
    end

    if moved then apply() end
end

-- Exposed so a session can drive the view without a mouse.
function cam.set(yaw_deg, pitch_deg, distance)
    if yaw_deg then yaw = math.rad(yaw_deg) end
    if pitch_deg then pitch = clamp(math.rad(pitch_deg), MIN_PITCH, MAX_PITCH) end
    if distance then dist = clamp(distance, MIN_DIST, MAX_DIST) end
    apply()
    return {yaw = math.deg(yaw), pitch = math.deg(pitch), dist = dist}
end

-- Raw orbit state for anything that has to compensate for the viewing angle (grid.set_view).
function cam.view()
    return dist or 0.6, pitch or 1.0
end

function cam.get()
    return {yaw = math.deg(yaw), pitch = math.deg(pitch), dist = dist,
            min_pitch = math.deg(MIN_PITCH), max_pitch = math.deg(MAX_PITCH),
            min_dist = MIN_DIST, max_dist = MAX_DIST}
end

-- Sit behind White (yaw pi, looking from -z) or Black (yaw 0, looking from +z).
-- Absolute, not +180 from wherever the camera last was — rematch as Black would
-- otherwise alternate sides because C.init re-adopts the live node position.
function cam.face(side)
    yaw = (side == "B") and 0 or math.pi
    apply()
    return cam.get()
end

return cam
