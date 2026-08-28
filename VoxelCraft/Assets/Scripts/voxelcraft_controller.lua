-- Voxel Phase-1 playground (node script).
--
-- Attached to a node in voxelcraft.pescene. Runs in the player on load and
-- in the editor when you press Play (default Script Component run mode = Player).
-- Regenerates the voxel world each run (arena chunks are not serialized into the
-- scene), then gives a first-person walk + break/place controller over it.
--
-- Minecraft-style first person: the cursor is grabbed so the mouse always looks
-- (no button to hold). Look + move use the engine's own camera primitives
-- (cam:rotate / cam:get_front) so directions match the engine's handedness;
-- gravity + wall collision are resolved on the CPU via voxel.move_aabb.
--
-- The cursor stays captured while the window has focus. Alt-Tab frees it (SDL
-- drops relative mode on focus loss); click the window to re-grab. Esc is NOT a
-- release key here — the player host quits on Esc.
--
-- NOTE: this script streams voxel geometry every frame (GPU-heavy, not editor-
-- edit-mode safe yet), so keep its Script Component run mode = Player.
--
-- Controls: mouse = look, WASD = walk, Shift = run, Space = jump, LMB/Q = break, RMB/E = place, 1/2/3 = block.

local FP = (function()
    local path = "Scripts/voxelcraft_fp.lua"
    local src = fs.read(path)
    if not src then error("[voxelcraft] missing " .. path) end
    return load(src, "@" .. path, "bt", _ENV)()
end)()

local GROUND_Y = 64
local HALF = { 0.3, 0.9, 0.3 } -- player AABB half-extents (center-anchored)
local EYE = HALF[2] * 0.85     -- eye height above center
local GRAVITY = 22.0
local JUMP = 8.0
local RUN_MULT = 1.8           -- walk speed multiplier while Shift is held
local COYOTE = 0.12 -- grace window so a press still jumps across the 1-frame ground-contact flicker
local REACH = 6.0            -- block edit reach
local selected_slot = 1

-- Player state (P is the AABB CENTER, in world blocks).
local P = { x = 0.5, y = GROUND_Y + 3.0, z = 0.5 }
local vy = 0.0
local grounded = false
local coyote = 0.0
local prevJump = false
local prevBreak, prevPlace = false, false
local skip_look = false -- swallow the cursor-capture snap on the frame the mouse is grabbed
local world_ready, world_frames = false, 0

-- Horizontal (XZ) unit vector from a camera basis vector.
local function flat(v)
    local x, z = v.x, v.z
    local l = math.sqrt(x * x + z * z)
    if l < 1e-5 then return 0.0, 0.0 end
    return x / l, z / l
end

function init()
    -- Build the selection outline (regular scene mesh) FIRST. Adding a regular
    -- mesh after the voxel arena is reserved destroys the arena (engine invariant,
    -- SceneBuffers.cpp), so world creation is deferred to the first update -- by
    -- then this mesh has uploaded and the arena reserves safely around it.
    -- Scene already has a directional light; do not add another (doubles shadow cascades).
    FP.make_highlight()
    if input and input.set_relative_mouse then
        input.set_relative_mouse(true) -- grab the cursor so the mouse always looks
        skip_look = true               -- ignore the snap delta on the grab frame
    end
    if runtime_ui and runtime_ui.set_screen_overlay then
        runtime_ui.set_screen_overlay("hud", true) -- bare full-window overlay, no panel chrome
        if runtime_ui.show then runtime_ui.show("hud") end -- screens default hidden until shown
    end
    local cam = get_camera()
    if cam then
        cam:set_position(vec3(P.x, P.y + EYE, P.z))
        cam:look_at(vec3(P.x, GROUND_Y, P.z - 12.0)) -- face forward, slightly down at the ground
    end
    pe_log("[voxelcraft] mouse look, WASD move, Shift run, Space jump, LMB/Q break, RMB/E place, 1/2/3 block")
end

function update(dt)
    if dt <= 0.0 or dt > 0.25 then dt = 1.0 / 60.0 end
    local cam = get_camera()
    if not cam then return end

    FP.crosshair()
    FP.hotbar(selected_slot)

    -- Defer voxel-world creation one frame so the highlight mesh (init) has
    -- uploaded before the arena reserves around it. Until then, no world exists.
    world_frames = world_frames + 1
    if not world_ready then
        if world_frames < 2 then return end
        if settings and settings.set then
            settings.set("occlusion_culling", true) -- temporal voxel Hi-Z
            settings.set("occlusion_culling_bias", 0.004) -- extra slack for 1-frame-late pyramid
        end
        voxel.create({ load_radius = 8, ground_y = GROUND_Y, upload_budget = 16, save_dir = "VoxelWorlds/voxelcraft" })
        voxel.set_anchor(P.x, P.y, P.z)
        world_ready = true
    end

    selected_slot = FP.hotbar_slot(selected_slot)
    skip_look = FP.look(cam, skip_look)

    -- Move basis = camera forward flattened to the ground; right is forward
    -- rotated +90deg about up. (Engine is left-handed, so cam:get_right() points
    -- the opposite way and would mirror A/D — derive right from front instead.)
    local front = cam:get_front()
    local fx, fz = flat(front)
    local rx, rz = -fz, fx
    local mx, mz = 0.0, 0.0
    if input.is_key_down("W") then mx = mx + fx; mz = mz + fz end
    if input.is_key_down("S") then mx = mx - fx; mz = mz - fz end
    if input.is_key_down("D") then mx = mx + rx; mz = mz + rz end
    if input.is_key_down("A") then mx = mx - rx; mz = mz - rz end
    local len = math.sqrt(mx * mx + mz * mz)
    local speed = cam:get_speed()
    if input.is_key_down("Left Shift") or input.is_key_down("Right Shift") then
        speed = speed * RUN_MULT
    end
    if len > 1e-4 then mx, mz = mx / len * speed, mz / len * speed end

    -- Gravity + jump. Ground contact flickers a frame at a time while resting
    -- (sub-mm collision epsilon), so a plain "grounded and pressed" check drops
    -- ~half the presses. A short coyote window keeps "can jump" alive across the
    -- flicker; the press edge (prevJump) still gives one jump per press.
    if grounded then coyote = COYOTE else coyote = math.max(0.0, coyote - dt) end
    local jumpKey = input.is_key_down("Space")
    if coyote > 0.0 and jumpKey and not prevJump then
        vy = JUMP; grounded = false; coyote = 0.0
    end
    prevJump = jumpKey
    vy = vy - GRAVITY * dt

    -- Swept move (per-axis slide resolved engine-side).
    local dx, dy, dz = mx * dt, vy * dt, mz * dt
    local np = voxel.move_aabb(P.x, P.y, P.z, HALF[1], HALF[2], HALF[3], dx, dy, dz)

    grounded = false
    if dy < 0.0 and np.y > P.y + dy + 1e-3 then grounded = true; vy = 0.0 end
    if dy > 0.0 and np.y < P.y + dy - 1e-3 then vy = 0.0 end

    P.x, P.y, P.z = np.x, np.y, np.z
    if P.y < GROUND_Y - 64.0 then P.x, P.y, P.z = 0.5, GROUND_Y + 3.0, 0.5; vy = 0.0 end

    -- Move the camera to the player eye (position only; orientation owned by cam:rotate).
    local ex, ey, ez = P.x, P.y + EYE, P.z
    cam:set_position(vec3(ex, ey, ez))
    voxel.set_anchor(P.x, P.y, P.z)

    -- One look-ray per frame, shared by the selection outline and break/place.
    local hit = voxel.raycast(ex, ey, ez, front.x, front.y, front.z, REACH)
    FP.highlight(hit)
    prevBreak, prevPlace = FP.edit(hit, P.x, P.y, P.z, HALF[1], HALF[2], HALF[3],
        FP.HOTBAR[selected_slot].id, skip_look, prevBreak, prevPlace)
end

function destroy()
    FP.destroy_highlight()
end
