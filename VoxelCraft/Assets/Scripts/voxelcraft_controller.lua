-- Voxel Phase-1 playground (node script).
--
-- Attached to a node in voxelcraft.pescene. Runs in the player on load and
-- in the editor when you press Play (default Script Component run mode = Player).
-- Regenerates the voxel world each run (arena chunks are not serialized into the
-- scene), then gives a first-person walk + break/place controller over it.
--
-- Minecraft-style first person. Look + move use the engine's own camera primitives
-- (cam:rotate / cam:get_front) so directions match the engine's handedness;
-- gravity + wall collision are resolved on the CPU via voxel.move_aabb.
--
-- The cursor starts free so the top-left Jev button can be clicked, then the
-- first click in the world captures it. Alt-Tab frees it; click the window to
-- re-grab. Esc is NOT a release key here — the player host quits on Esc.
-- J (or that button) toggles Jev while play continues.
--
-- NOTE: this script streams voxel geometry every frame (GPU-heavy, not editor-
-- edit-mode safe yet), so keep its Script Component run mode = Player.
--
-- Controls: mouse = look, WASD = walk, Shift = run, Space = jump, LMB/Q = break, RMB/E = place, 1/2/3 = block.
-- Jev toggle: top-left HUD button "Jev", or the J key.

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

-- cam:rotate units per second. Rotate scales by the camera's rotation speed
-- (~2.864 degrees per unit), so 48 is about 140 deg/s. Held until another look.
local LOOK_RATE = 48
local held = {}
local pulse = {}
local look_yaw = 0.0
local look_pitch = 0.0
local jev_message = nil
local human_edge_now = false
local raw_prev = {}
local raw_ready = false
local swallow_mouse = 0
local j_prev = false
local jev

local HUMAN_KEYS = {
    "W", "A", "S", "D",
    "Space", "Q", "E",
    "Left Shift", "Right Shift",
    "1", "2", "3",
}

if input and input.is_key_down then
    local hardware_key_down = input.is_key_down

    input.is_key_down = function(key)
        if held[key] or pulse[key] then
            return true
        end
        return hardware_key_down(key)
    end
end

local function clear_hold()
    held.W = nil
    held.A = nil
    held.S = nil
    held.D = nil
    pulse.Space = nil
    pulse.Q = nil
    pulse.E = nil
    look_yaw = 0.0
    look_pitch = 0.0
end

local function release_pulses()
    pulse.Space = nil
    pulse.Q = nil
    pulse.E = nil
end

local function mouse_moved()
    if not (input and input.peek_mouse_delta) then
        return false
    end

    local delta = input.peek_mouse_delta()
    if type(delta) ~= "table" then
        return false
    end

    local x = math.abs(delta.x or 0)
    local y = math.abs(delta.y or 0)
    return x > 2 or y > 2
end

local function sample_human()
    human_edge_now = false
    for i = 1, #HUMAN_KEYS do
        local key = HUMAN_KEYS[i]
        local down = input.is_key_down_raw(key) == true
        if raw_ready and down and not raw_prev[key] then
            human_edge_now = true
        end
        raw_prev[key] = down
    end

    local ignore_mouse = swallow_mouse > 0
    if swallow_mouse > 0 then
        swallow_mouse = swallow_mouse - 1
    end

    if mouse_moved() and not ignore_mouse then
        human_edge_now = true
    end

    local function mouse_button(name, down)
        if raw_ready and down and not raw_prev[name] and not ignore_mouse then
            human_edge_now = true
        end
        raw_prev[name] = down
    end

    mouse_button("LMB", input.is_left_mouse_down() == true)
    mouse_button("RMB", input.is_right_mouse_down() == true)
    raw_ready = true
end

local function respawn()
    P.x = 0.5
    P.y = GROUND_Y + 3.0
    P.z = 0.5
    vy = 0.0
    grounded = false
    coyote = 0.0
    prevJump = false
    prevBreak = false
    prevPlace = false

    local cam = get_camera()
    if not cam then
        return
    end

    cam:set_position(vec3(P.x, P.y + EYE, P.z))
    cam:look_at(vec3(P.x, GROUND_Y, P.z - 12.0))
end

local function jev_running()
    local note = jev:note()
    return type(note) == "string" and note:sub(1, 4) == "Jev "
end

local function toggle_jev()
    if jev_running() then
        jev:begin_human()
        jev_message = nil
        return
    end

    jev_message = nil
    local ok = jev:start()
    if ok then
        swallow_mouse = 3
        return
    end

    local err = jev:error()
    if not err or err == "" then
        err = "Jev could not start"
    end
    jev_message = err
    pe_log("[voxelcraft] " .. err)
end

local function jev_button_state()
    if not (runtime_ui and runtime_ui.get_state) then
        return nil
    end

    local ok, st = pcall(runtime_ui.get_state, "hud", "jev_toggle")
    if ok and type(st) == "table" then
        return st
    end
    return nil
end

local function jev_key_edge()
    if not (input and input.is_key_down_raw) then
        return false
    end

    local down = input.is_key_down_raw("J") == true
    local edge = down and not j_prev
    j_prev = down
    return edge
end

local function draw_jev()
    if not (runtime_ui and runtime_ui.set_quad and runtime_ui.get_surface_size) then
        return
    end

    local s = runtime_ui.get_surface_size()
    if not s.valid then
        return
    end

    local sc = s.ui_scale or 1.0
    local x = 16.0 * sc
    local y = 16.0 * sc
    local w = 148.0 * sc
    local h = 40.0 * sc
    local on = jev_running()
    local fill = { r = 0.1, g = 0.1, b = 0.12, a = 0.9 }
    if on then
        fill = { r = 0.16, g = 0.38, b = 0.22, a = 0.94 }
    end

    runtime_ui.set_quad("hud", "jev_toggle", {
        x = x,
        y = y,
        z = 200.0,
        w = w,
        h = h,
        style = "button",
        label = "Jev",
        align_h = "center",
        align_v = "middle",
        font_scale = 1.1,
        fill = fill,
        border = { r = 1.0, g = 1.0, b = 1.0, a = 0.95 },
        text_color = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 },
    })

    local message = jev_message
    if on then
        message = jev:note()
    end
    local show = type(message) == "string" and message ~= ""
    runtime_ui.set_quad("hud", "jev_status", {
        x = x,
        y = y + h + 6.0 * sc,
        z = 200.0,
        w = 640.0 * sc,
        h = 28.0 * sc,
        style = "text",
        body = show and message or "",
        align_h = "left",
        align_v = "middle",
        font_scale = 0.8,
        fill = { r = 0.0, g = 0.0, b = 0.0, a = show and 0.55 or 0.0 },
        border = { r = 0.0, g = 0.0, b = 0.0, a = 0.0 },
        text_color = { r = 1.0, g = 0.86, b = 0.45, a = show and 1.0 or 0.0 },
        no_input = true,
        visible = show,
    })
end

local function begin_frame(dt)
    -- Pulses are stored by MCP before this update and cleared after the read.
    sample_human()
    jev:tick(dt)
    if pulse.Space then
        prevJump = false
    end
    if pulse.Q then
        prevBreak = false
    end
    if pulse.E then
        prevPlace = false
    end

    local button = jev_button_state()
    local button_hit = button ~= nil and button.clicked == true
    if button_hit or jev_key_edge() then
        toggle_jev()
    end
    draw_jev()

    local over_button = button ~= nil and button.down == true
    return button_hit or over_button
end

local function apply_action(id)
    if id == "forward" then
        held.W = true
        held.S = nil
    elseif id == "back" then
        held.S = true
        held.W = nil
    elseif id == "left" then
        held.A = true
        held.D = nil
    elseif id == "right" then
        held.D = true
        held.A = nil
    elseif id == "stop" then
        held.W = nil
        held.A = nil
        held.S = nil
        held.D = nil
    elseif id == "jump" then
        pulse.Space = true
    elseif id == "break" then
        pulse.Q = true
    elseif id == "place" then
        pulse.E = true
    elseif id == "look_left" then
        look_yaw = -LOOK_RATE
    elseif id == "look_right" then
        look_yaw = LOOK_RATE
    elseif id == "look_up" then
        look_pitch = -LOOK_RATE
    elseif id == "look_down" then
        look_pitch = LOOK_RATE
    elseif id == "look_stop" then
        look_yaw = 0.0
        look_pitch = 0.0
    end
end

local function observe_player()
    local block_hit = false
    local block_id = 0
    local block_x = 0
    local block_y = 0
    local block_z = 0

    if world_ready then
        local cam = get_camera()
        if cam then
            local front = cam:get_front()
            local hit = voxel.raycast(
                P.x, P.y + EYE, P.z,
                front.x, front.y, front.z,
                REACH)
            if hit and hit.hit then
                block_hit = true
                block_x = hit.cell.x
                block_y = hit.cell.y
                block_z = hit.cell.z
                block_id = voxel.get_block(block_x, block_y, block_z)
            end
        end
    end

    return {
        x = P.x,
        y = P.y,
        z = P.z,
        block_hit = block_hit,
        block_id = block_id,
        block_x = block_x,
        block_y = block_y,
        block_z = block_z,
    }
end

local ACTIONS = {
    { id = "forward", description = "Hold W. Strafe and look stay as they are." },
    { id = "back", description = "Hold S. Strafe and look stay as they are." },
    { id = "left", description = "Hold A. Forward, back and look stay as they are." },
    { id = "right", description = "Hold D. Forward, back and look stay as they are." },
    { id = "stop", description = "Release W, A, S and D. Look stays." },
    { id = "jump", description = "Jump once." },
    { id = "break", description = "Break the block in front once." },
    { id = "place", description = "Place the selected block on the face in front once." },
    { id = "look_left", description = "Hold a left yaw rate, applied every frame." },
    { id = "look_right", description = "Hold a right yaw rate, applied every frame." },
    { id = "look_up", description = "Hold an upward pitch rate, applied every frame." },
    { id = "look_down", description = "Hold a downward pitch rate, applied every frame." },
    { id = "look_stop", description = "Stop yaw and pitch. Movement stays held." },
}

local jev_source = fs.read("Scripts/jev_auto.lua")
assert(jev_source, "Missing Scripts/jev_auto.lua")
local JevAuto = assert(load(jev_source, "@Scripts/jev_auto.lua", "t", _ENV))()

jev = JevAuto.attach({
    port = 9148,
    id = "voxelcraft",
    description = "VoxelCraft. Walk, look, jump, and break or place blocks. "
        .. "Move and look are holds. Jump, break and place are one tap. No score.",
    playing = function()
        return world_ready
    end,
    terminal = function()
        return false
    end,
    score = function()
        return 0
    end,
    busy = function()
        return false
    end,
    human_edge = function()
        return human_edge_now
    end,
    observe = observe_player,
    actions = function()
        return { { id = "forward", description = "Hold W and walk forward.", score = 1 } }
    end,
    apply = apply_action,
    reset = function(seed)
        math.randomseed(seed or 1)
        clear_hold()
        respawn()
    end,
    on_human = clear_hold,
})

function init()
    -- Build the selection outline (regular scene mesh) FIRST. Adding a regular
    -- mesh after the voxel arena is reserved destroys the arena (engine invariant,
    -- SceneBuffers.cpp), so world creation is deferred to the first update -- by
    -- then this mesh has uploaded and the arena reserves safely around it.
    -- Scene already has a directional light; do not add another (doubles shadow cascades).
    FP.make_highlight()
    if runtime_ui and runtime_ui.set_screen_overlay then
        runtime_ui.set_screen_overlay("hud", true) -- bare full-window overlay, no panel chrome
        if runtime_ui.show then runtime_ui.show("hud") end -- screens default hidden until shown
    end
    respawn()
    pe_log("[voxelcraft] WASD, mouse look, Space jump, Q/E break/place. Jev: top-left button or J")
end

function update(dt)
    if dt <= 0.0 or dt > 0.25 then dt = 1.0 / 60.0 end
    local hold_cursor = begin_frame(dt)
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
    if hold_cursor and input.set_relative_mouse then
        input.set_relative_mouse(false)
        skip_look = true
    end
    if look_yaw ~= 0.0 or look_pitch ~= 0.0 then
        cam:rotate(look_yaw * dt, look_pitch * dt)
    end

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
    release_pulses()
end

function destroy()
    FP.destroy_highlight()
end
