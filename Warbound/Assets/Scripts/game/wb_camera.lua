-- wb_camera — the angled RTS command camera + the picking math.
--
-- The engine exposes no screen->world pick, so we build it ourselves from the
-- camera basis (position/front/right/up) and the FOV. screen->ground (ray vs the
-- y=0 plane) drives move orders; world->screen (the inverse projection) drives unit
-- picking, the selection box, floating HP bars, and the minimap ping. Both use the
-- SAME fov/aspect, so they stay mutually consistent; `fov_scale` is the single dial
-- to nudge if absolute calibration ever drifts from the renderer.

local U = WB.util
local World = WB.world

local Camera = {}

Camera.PITCH_DEG = 57.0        -- camera tilt from horizontal (bigger = more top-down)
Camera.FOV_DEG = 48.0          -- vertical field of view we set on the camera
Camera.fov_scale = 1.0         -- calibration dial (see header)
Camera.MIN_DIST = 16.0         -- closest zoom (view distance from focus)
Camera.MAX_DIST = 50.0         -- farthest zoom
Camera.EDGE_PX = 6.0           -- screen-edge scroll band
Camera.debug = false

Camera.focus_x = 0.0
Camera.focus_z = 6.0
Camera.dist = 30.0

local cam = nil

local function get_cam()
    if cam and cam.is_valid and not cam:is_valid() then cam = nil end
    if not cam then
        cam = (get_camera and get_camera()) or (scene.get_active_camera and scene.get_active_camera()) or nil
    end
    return cam
end

-- Camera eye position for a given focus/dist at the fixed pitch.
local function cam_eye(fx, fz, dist)
    local p = math.rad(Camera.PITCH_DEG)
    return fx, dist * math.sin(p), fz + dist * math.cos(p)
end

function Camera.init(focus_x, focus_z)
    local c = get_cam()
    Camera.focus_x = focus_x or 0.0
    Camera.focus_z = focus_z or 6.0
    -- Reset projection sampling/calibration so a fresh play session (incl. editor
    -- Play->Stop->Play, which reuses the persisted module) re-samples the real VP and
    -- re-detects flips against the live camera rather than trusting last session's.
    cam = nil
    Camera._anchor = nil; Camera._p = nil
    Camera._calibrated = false; Camera._n = 0; Camera._settle_until = 0
    Camera.flip_x = false; Camera.flip_y = false
    c = get_cam()
    if not c then return end
    if c.set_projection_mode then c:set_projection_mode("perspective") end
    if c.set_fov then c:set_fov(Camera.FOV_DEG) end
    if c.set_near then c:set_near(0.1) end
    if c.set_far then c:set_far(2000.0) end
    -- Establish orientation ONCE here via look_at. The orientation is CONSTANT for
    -- this rig (fixed pitch, fixed look direction — panning/zooming only translate
    -- the camera), so afterwards we never re-orient; we only set_position. Calling
    -- look_at every frame while the camera was moving crashed the renderer.
    local ex, ey, ez = cam_eye(Camera.focus_x, Camera.focus_z, Camera.dist)
    c:set_position(vec3(ex, ey, ez))
    if c.look_at then c:look_at(vec3(Camera.focus_x, 0.0, Camera.focus_z)) end
    Camera._applied_key = nil
end

-- Move the camera to match the current focus/dist (position only; orientation was
-- fixed at init). No-op when nothing changed, so an idle camera is never touched.
function Camera.apply()
    local c = get_cam()
    if not c then return end
    local key = string.format("%.3f|%.3f|%.3f", Camera.focus_x, Camera.focus_z, Camera.dist)
    if key == Camera._applied_key then return end
    Camera._applied_key = key
    local ex, ey, ez = cam_eye(Camera.focus_x, Camera.focus_z, Camera.dist)
    c:set_position(vec3(ex, ey, ez))
end

-- Window pixel size (player viewport is the whole window).
function Camera.screen()
    local w, h = 1920.0, 1080.0
    if engine and engine.get_window_size then
        local s = engine.get_window_size()
        if s and s.w and s.w > 0 then w, h = s.w, s.h end
    end
    return w, h
end

-- Exact projection using the camera's REAL view-projection matrix (not a
-- hand-reconstructed basis+FOV), so screen<->world agrees with what the engine
-- actually draws — handedness, Vulkan-Y, and reverse-depth are all baked into the
-- matrix. flip_x / flip_y are auto-calibrated on the first frame (see calibrate())
-- so the NDC->pixel sense always matches, regardless of clip-space convention.
Camera.flip_x = false
Camera.flip_y = false
Camera._calibrated = false

-- PROJECTION WITHOUT PER-FRAME MATRIX CALLS.
-- Calling the engine matrix bindings (get_view_projection / mat4*vec4) repeatedly
-- corrupts and crashes the player (0xC0000005) after ~10-15k calls. So we sample the
-- real view-projection's 4 columns exactly ONCE (the anchor) and thereafter update
-- it in pure Lua: panning and zooming are both pure camera TRANSLATIONS (the look
-- direction and up never change at fixed pitch), so VP_now = VP_anchor * Translate(
-- -Δeye), which only changes the 4th column: col3' = col3 - Δx*col0 - Δy*col1 -
-- Δz*col2. This is exact and convention-agnostic (handedness is baked into the
-- sampled anchor). The binding is touched only at startup and on window resize.
Camera._anchor = nil   -- sampled columns + the focus/dist/size they were taken at
Camera._p = nil        -- effective per-frame coeffs {c0x,c0y,c0w,...,c3x,c3y,c3w,w,h}

local function sample_anchor()
    local c = get_cam()
    if not c or not c.get_view_projection then return false end
    local vp = c:get_view_projection()
    if not vp then return false end
    local c0 = vp * vec4(1.0, 0.0, 0.0, 0.0)
    local c1 = vp * vec4(0.0, 1.0, 0.0, 0.0)
    local c2 = vp * vec4(0.0, 0.0, 1.0, 0.0)
    local c3 = vp * vec4(0.0, 0.0, 0.0, 1.0)
    local w, h = Camera.screen()
    Camera._anchor = {
        c0x = c0.x, c0y = c0.y, c0w = c0.w,
        c1x = c1.x, c1y = c1.y, c1w = c1.w,
        c2x = c2.x, c2y = c2.y, c2w = c2.w,
        c3x = c3.x, c3y = c3.y, c3w = c3.w,
        fx = Camera.focus_x, fz = Camera.focus_z, dist = Camera.dist, w = w, h = h,
    }
    return true
end

-- Recompute the effective coefficients for the current focus/dist (pure Lua).
-- Re-samples the real VP when: there's no anchor yet, the window was resized, OR we're
-- still in the startup settle window. The standalone Player can hand us a not-yet-final
-- view-projection on the first frames (the camera's look_at matrix / swapchain aspect
-- settle a beat after Camera.init), and the old "sample exactly once" caught that stale
-- matrix — leaving world_to_screen projecting every unit to the screen edge so clicks
-- never landed (fine in the editor, which owns a stable viewport). Re-sampling for a
-- bounded burst (first SETTLE_FRAMES, plus a short burst after each resize) captures the
-- final matrix without the sustained per-frame matrix calls that crash the player.
Camera.SETTLE_FRAMES = 90
Camera._n = 0
Camera._settle_until = 0

function Camera.refresh_if_needed()
    Camera._n = Camera._n + 1
    local a = Camera._anchor
    local w, h = Camera.screen()
    local size_changed = a and (math.floor(w) ~= math.floor(a.w) or math.floor(h) ~= math.floor(a.h))
    if size_changed then Camera._settle_until = Camera._n + 30 end
    if not a or size_changed or Camera._n <= Camera.SETTLE_FRAMES or Camera._n <= Camera._settle_until then
        if not sample_anchor() then return end
        a = Camera._anchor
    end
    local ex, ey, ez = cam_eye(Camera.focus_x, Camera.focus_z, Camera.dist)
    local ax, ay, az = cam_eye(a.fx, a.fz, a.dist)
    local tx, ty, tz = ex - ax, ey - ay, ez - az
    local c3x = a.c3x - tx * a.c0x - ty * a.c1x - tz * a.c2x
    local c3y = a.c3y - tx * a.c0y - ty * a.c1y - tz * a.c2y
    local c3w = a.c3w - tx * a.c0w - ty * a.c1w - tz * a.c2w
    Camera._p = { a.c0x, a.c0y, a.c0w, a.c1x, a.c1y, a.c1w, a.c2x, a.c2y, a.c2w, c3x, c3y, c3w, a.w, a.h }
end

-- World point (wx,wy,wz) -> screen pixel. Returns sx, sy, w_clip (w_clip>0 => in front).
function Camera.world_to_screen(wx, wy, wz)
    local p = Camera._p
    if not p then return nil end
    local cx = p[1] * wx + p[4] * wy + p[7] * wz + p[10]
    local cy = p[2] * wx + p[5] * wy + p[8] * wz + p[11]
    local cw = p[3] * wx + p[6] * wy + p[9] * wz + p[12]
    if cw <= 1e-5 then return nil, nil, -1.0 end
    local ndc_x = cx / cw
    local ndc_y = cy / cw
    local sx = (Camera.flip_x and (0.5 - ndc_x * 0.5) or (ndc_x * 0.5 + 0.5)) * p[13]
    local sy = (Camera.flip_y and (0.5 - ndc_y * 0.5) or (ndc_y * 0.5 + 0.5)) * p[14]
    return sx, sy, cw
end

-- Screen pixel (sx,sy) -> ground point (x,z) on the y=0 plane, by INVERTING
-- world_to_screen numerically (Newton on the ground plane). Plane->screen under a
-- pinhole camera is a homography, so a few iterations from the focus converge fast.
-- Pure scalar math over the cached coefficients (no engine matrix calls).
function Camera.pick_ground(sx, sy)
    Camera.refresh_if_needed()
    local x, z = Camera.focus_x, Camera.focus_z
    local eps = 0.5
    for _ = 1, 8 do
        local u, v = Camera.world_to_screen(x, 0.0, z)
        if not u then return nil end
        local du, dv = u - sx, v - sy
        if du * du + dv * dv < 0.25 then return x, z end -- within ~0.5 px
        local ux, vx = Camera.world_to_screen(x + eps, 0.0, z)
        local uz, vz = Camera.world_to_screen(x, 0.0, z + eps)
        if not (ux and uz) then return nil end
        local j11, j21 = (ux - u) / eps, (vx - v) / eps
        local j12, j22 = (uz - u) / eps, (vz - v) / eps
        local det = j11 * j22 - j12 * j21
        if math.abs(det) < 1e-9 then return nil end
        local dx = (j22 * du - j12 * dv) / det
        local dz = (-j21 * du + j11 * dv) / det
        x = x - dx
        z = z - dz
        if x ~= x or z ~= z then return nil end -- NaN guard
    end
    return x, z
end

-- Auto-calibrate the screen-axis sense. With the camera looking north (-Z) from
-- the south, a point EAST of the focus must land screen-right and a point NORTH of
-- it must land screen-up; if either comes out reversed we flip that axis. Runs once
-- the matrices are live (first update frame). Returns true when it succeeded.
function Camera.calibrate()
    Camera.flip_x, Camera.flip_y = false, false
    local fx, fz = Camera.focus_x, Camera.focus_z
    local sx0, sy0 = Camera.world_to_screen(fx, 0.0, fz)
    local sxe = Camera.world_to_screen(fx + 6.0, 0.0, fz)
    local _, syn = Camera.world_to_screen(fx, 0.0, fz - 6.0)
    if not (sx0 and sy0 and sxe and syn) then return false end
    if sxe < sx0 then Camera.flip_x = true end -- east landed left -> X reversed
    if syn > sy0 then Camera.flip_y = true end -- north landed lower -> Y reversed
    Camera._calibrated = true
    -- Round-trip self-test: project the focus to screen, then unproject back to the
    -- ground. They should match within a pixel/world unit. A NIL here means
    -- pick_ground (free move orders) is broken (e.g. no inverse matrix).
    local rx, rz = Camera.pick_ground(sx0, sy0)
    if pe_log then
        if rx then
            pe_log(string.format("[Warbound] camera calibrated flip_x=%s flip_y=%s; pick round-trip focus(%.1f,%.1f)->(%.1f,%.1f)",
                tostring(Camera.flip_x), tostring(Camera.flip_y), fx, fz, rx, rz))
        else
            pe_log(string.format("[Warbound] camera calibrated flip_x=%s flip_y=%s; pick_ground returned NIL (no inverse matrix)",
                tostring(Camera.flip_x), tostring(Camera.flip_y)))
        end
    end
    return true
end

-- Pan/zoom from input each frame. `mouse_in_ui` suppresses edge-scroll while the
-- cursor is over the HUD.
function Camera.update(dt, mouse_in_ui)
    local c = get_cam()
    if not c then return end

    -- Keep the cached projection coefficients current (cheap: only re-samples the
    -- matrix when the view actually changed).
    Camera.refresh_if_needed()
    -- Calibrate only once the VP has settled (see refresh_if_needed) so flip detection
    -- doesn't latch onto a stale first-frame matrix.
    if not Camera._calibrated and Camera._n >= 20 then Camera.calibrate() end

    -- zoom (wheel)
    if input and input.get_mouse_wheel then
        local wheel = input.get_mouse_wheel()
        if wheel and wheel.y and wheel.y ~= 0 then
            Camera.dist = U.clamp(Camera.dist - wheel.y * 3.0, Camera.MIN_DIST, Camera.MAX_DIST)
        end
    end

    -- pan direction from keys (screen-aligned: up = -Z, right = +X)
    local function down(k) return input and input.is_key_down and input.is_key_down(k) == true end
    local px, pz = 0.0, 0.0
    if down("d") or down("right") then px = px + 1.0 end
    if down("a") or down("left") then px = px - 1.0 end
    if down("s") or down("down") then pz = pz + 1.0 end
    if down("w") or down("up") then pz = pz - 1.0 end

    -- edge scroll: fires at the very screen border, but not when the cursor is over an
    -- actual HUD panel (minimap / command card / portrait / resources). The open
    -- bottom-center gap between panels still scrolls south, so the command bar doesn't
    -- block scrolling while corner panels don't hijack the camera.
    if not mouse_in_ui and input and input.get_mouse_position then
        local m = input.get_mouse_position()
        -- The engine returns (0,0) as a sentinel when the mouse is captured by the UI
        -- (cursor over an interactive widget — minimap, command buttons). Ignore it, or
        -- hovering those would read as the top-left corner and edge-scroll up-left.
        if m and m.x and not (m.x == 0 and m.y == 0) then
            local w, h = Camera.screen()
            local e = Camera.EDGE_PX
            if m.x >= 0 and m.x < w and m.y >= 0 and m.y < h then
                if m.x <= e then px = px - 1.0 elseif m.x >= w - 1 - e then px = px + 1.0 end
                if m.y <= e then pz = pz - 1.0 elseif m.y >= h - 1 - e then pz = pz + 1.0 end
            end
        end
    end

    if px ~= 0.0 or pz ~= 0.0 then
        local nx, nz = U.norm2(px, pz)
        local speed = 16.0 + Camera.dist * 0.7
        Camera.focus_x = Camera.focus_x + nx * speed * dt
        Camera.focus_z = Camera.focus_z + nz * speed * dt
        Camera.focus_x, Camera.focus_z = World.clamp(Camera.focus_x, Camera.focus_z, -6.0)
    end

    Camera.apply()
end

-- Recenter the camera on a world point (used by minimap clicks / hero focus).
function Camera.center_on(x, z)
    Camera.focus_x, Camera.focus_z = World.clamp(x, z, -6.0)
    Camera.apply()
end

return Camera
