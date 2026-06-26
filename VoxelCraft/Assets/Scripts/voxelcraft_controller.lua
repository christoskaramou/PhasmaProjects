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
-- Controls: mouse = look, WASD = walk, Space = jump, LMB/Q = break, RMB/E = place, 1/2/3 = block.

local GROUND_Y = 64
local HALF = { 0.3, 0.9, 0.3 } -- player AABB half-extents (center-anchored)
local EYE = HALF[2] * 0.85     -- eye height above center
local GRAVITY = 22.0
local JUMP = 8.0
local COYOTE = 0.12 -- grace window so a press still jumps across the 1-frame ground-contact flicker
local REACH = 6.0            -- block edit reach
local HOTBAR = {
    { id = 1, label = "1", fill = { r = 0.48, g = 0.48, b = 0.50, a = 0.92 } }, -- stone
    { id = 2, label = "2", fill = { r = 0.43, g = 0.28, b = 0.15, a = 0.92 } }, -- dirt
    { id = 3, label = "3", fill = { r = 0.27, g = 0.55, b = 0.20, a = 0.92 } }, -- grass
}
local selected_slot = 1

-- Player state (P is the AABB CENTER, in world blocks).
local P = { x = 0.5, y = GROUND_Y + 3.0, z = 0.5 }
local vy = 0.0
local grounded = false
local coyote = 0.0
local prevJump = false
local prevBreak, prevPlace = false, false
local skip_look = false -- swallow the cursor-capture snap on the frame the mouse is grabbed

-- Block-selection wireframe (Minecraft-style outline of the targeted block).
local highlight = nil
local hl_x, hl_y, hl_z = nil, nil, nil
local hl_shown = false

-- Horizontal (XZ) unit vector from a camera basis vector.
local function flat(v)
    local x, z = v.x, v.z
    local l = math.sqrt(x * x + z * z)
    if l < 1e-5 then return 0.0, 0.0 end
    return x / l, z / l
end

-- Screen-space crosshair: two thin quads centred on the viewport. Rebuilt only
-- when the surface size changes, so it's cheap to call every frame.
local cross_w, cross_h = 0, 0
local function update_crosshair()
    if not (runtime_ui and runtime_ui.get_surface_size) then return end
    local s = runtime_ui.get_surface_size()
    if not s.valid then return end
    if s.w == cross_w and s.h == cross_h then return end
    cross_w, cross_h = s.w, s.h
    local sc = s.ui_scale or 1.0
    local L, T = 24.0 * sc, 4.0 * sc -- arm length / thickness
    local cx, cy = s.w * 0.5, s.h * 0.5
    local col = { r = 1.0, g = 1.0, b = 1.0, a = 0.85 }
    local none = { r = 0.0, g = 0.0, b = 0.0, a = 0.0 }
    runtime_ui.set_quad("hud", "cross_h", {
        x = cx - L * 0.5, y = cy - T * 0.5, z = 100.0, w = L, h = T,
        style = "text", fill = col, border = none, no_input = true,
    })
    runtime_ui.set_quad("hud", "cross_v", {
        x = cx - T * 0.5, y = cy - L * 0.5, z = 100.0, w = T, h = L,
        style = "text", fill = col, border = none, no_input = true,
    })
end

local hotbar_w, hotbar_h, hotbar_selected = 0, 0, 0
local function update_hotbar()
    if not (runtime_ui and runtime_ui.get_surface_size) then return end
    local s = runtime_ui.get_surface_size()
    if not s.valid then return end
    if s.w == hotbar_w and s.h == hotbar_h and selected_slot == hotbar_selected then return end

    hotbar_w, hotbar_h, hotbar_selected = s.w, s.h, selected_slot
    local sc = s.ui_scale or 1.0
    local slot, gap = 34.0 * sc, 6.0 * sc
    local total = (#HOTBAR * slot) + ((#HOTBAR - 1) * gap)
    local x0 = s.w * 0.5 - total * 0.5
    local y = s.h - (slot + 22.0 * sc)
    local text = { r = 1.0, g = 1.0, b = 1.0, a = 0.95 }

    for i, b in ipairs(HOTBAR) do
        local selected = i == selected_slot
        runtime_ui.set_quad("hud", "hotbar_" .. i, {
            x = x0 + (i - 1) * (slot + gap),
            y = y,
            z = 10.0,
            w = slot,
            h = slot,
            style = "text",
            body = b.label,
            align_h = "center",
            align_v = "middle",
            font_scale = selected and 1.25 or 1.0,
            fill = b.fill,
            border = selected and { r = 1.0, g = 1.0, b = 1.0, a = 0.95 } or { r = 0.0, g = 0.0, b = 0.0, a = 0.55 },
            text_color = text,
            no_input = true,
        })
    end
end

-- Selection outline: 12 thin cubes (one per box edge). World-space bars shrink on
-- screen with distance, so thickness is recomputed each frame from camera distance
-- to keep ~HL_SCREEN_PX pixels on screen (like attach_lines' screen-constant stroke).
local HL_SCREEN_PX = 2.5
local hl_bars = {} -- { bar, axis='x'|'y'|'z' }
local HL_E = 0.003

local function hl_world_thickness(cam, block_x, block_y, block_z)
    local cp = cam:get_position()
    local dx = (block_x + 0.5) - cp.x
    local dy = (block_y + 0.5) - cp.y
    local dz = (block_z + 0.5) - cp.z
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist < 1e-3 then dist = 1e-3 end
    local fov_rad = cam:get_fov() * math.pi / 180.0
    local tan_half_y = math.tan(fov_rad * 0.5) / cam:get_aspect()
    local vp_h = (rhi and rhi.get_height_f) and rhi.get_height_f() or 1080.0
    return HL_SCREEN_PX * 2.0 * dist * tan_half_y / vp_h
end

local function update_highlight_thickness(cam, block_x, block_y, block_z)
    if #hl_bars == 0 then return end
    local thk = hl_world_thickness(cam, block_x, block_y, block_z)
    local S = 1.0 + 2.0 * HL_E
    local L = S + thk
    for _, b in ipairs(hl_bars) do
        if b.axis == "x" then
            b.bar:set_scale(vec3(L, thk, thk))
        elseif b.axis == "z" then
            b.bar:set_scale(vec3(thk, thk, L))
        else
            b.bar:set_scale(vec3(thk, L, thk))
        end
    end
end

local function make_highlight()
    if not (scene and scene.add_empty_node and scene.attach_primitive) then return end
    local h = scene.add_empty_node("BlockHighlight")
    if not h then return end
    hl_bars = {}

    local lo, hi = -HL_E, 1.0 + HL_E
    local mid = (lo + hi) * 0.5

    local function edge(mx, my, mz, axis)
        local bar = scene.add_empty_node()
        if not bar then return end
        scene.attach_primitive(bar, "cube")
        bar:set_position(vec3(mx, my, mz))
        if material and material.set then material.set(bar, "emissive", vec3(1.0, 1.0, 1.0)) end
        bar:set_parent(h)
        hl_bars[#hl_bars + 1] = { bar = bar, axis = axis }
    end

    edge(mid, lo, lo, "x")
    edge(mid, lo, hi, "x")
    edge(lo, lo, mid, "z")
    edge(hi, lo, mid, "z")
    edge(mid, hi, lo, "x")
    edge(mid, hi, hi, "x")
    edge(lo, hi, mid, "z")
    edge(hi, hi, mid, "z")
    edge(lo, mid, lo, "y")
    edge(hi, mid, lo, "y")
    edge(lo, mid, hi, "y")
    edge(hi, mid, hi, "y")

    if h.set_visible then h:set_visible(false) end
    highlight = h
end

function init()
    -- Build the selection outline (regular scene meshes) FIRST. Adding a regular
    -- mesh after the voxel arena is reserved destroys the arena (engine invariant,
    -- SceneBuffers.cpp), so world creation is deferred to the first update -- by
    -- then these meshes have uploaded and the arena reserves safely around them.
    make_highlight()
    if scene and scene.add_directional_light then
        scene.add_directional_light() -- deferred voxels need a light
    end
    if input and input.set_relative_mouse then
        input.set_relative_mouse(true) -- grab the cursor so the mouse always looks
        skip_look = true               -- ignore the snap delta on the grab frame
    end
    if runtime_ui and runtime_ui.set_screen_overlay then
        runtime_ui.set_screen_overlay("hud", true) -- bare full-window overlay, no panel chrome
        if runtime_ui.show then runtime_ui.show("hud") end -- screens default hidden until shown
        cross_w, cross_h = 0, 0 -- force crosshair layout on first update
    end
    local cam = get_camera()
    if cam then
        cam:set_position(vec3(P.x, P.y + EYE, P.z))
        cam:look_at(vec3(P.x, GROUND_Y, P.z - 12.0)) -- face forward, slightly down at the ground
    end
    pe_log("[voxelcraft] mouse look, WASD move, Space jump, LMB/Q break, RMB/E place, 1/2/3 block")
end

function update(dt)
    if dt <= 0.0 or dt > 0.25 then dt = 1.0 / 60.0 end
    local cam = get_camera()
    if not cam then return end

    update_crosshair()
    update_hotbar()

    -- Defer voxel-world creation one frame so the highlight mesh (init) has
    -- uploaded before the arena reserves around it. Until then, no world exists.
    world_frames = (world_frames or 0) + 1
    if not world_ready then
        if world_frames < 2 then return end
        voxel.create({ load_radius = 6, ground_y = GROUND_Y, upload_budget = 8 })
        voxel.set_anchor(P.x, P.y, P.z)
        world_ready = true
    end

    for i = 1, #HOTBAR do
        if input.is_key_down(tostring(i)) then selected_slot = i end
    end

    -- Look: cursor is grabbed, so the mouse always looks (Minecraft-style). If the
    -- grab was dropped (Alt-Tab, or the window launched unfocused), a click on the
    -- window re-grabs it. Swallow the snap delta on the frame we (re)grab.
    if input.is_relative_mouse() then
        local md = input.get_mouse_delta()
        if skip_look then
            skip_look = false
        elseif (md.x or 0) ~= 0 or (md.y or 0) ~= 0 then
            cam:rotate(md.x, md.y)
        end
    elseif input.is_left_mouse_down() then
        input.set_relative_mouse(true)
        skip_look = true
    end

    -- Move basis = camera forward flattened to the ground; right is forward
    -- rotated +90deg about up. (Engine is left-handed, so cam:get_right() points
    -- the opposite way and would mirror A/D — derive right from front instead.)
    local fx, fz = flat(cam:get_front())
    local rx, rz = -fz, fx
    local mx, mz = 0.0, 0.0
    if input.is_key_down("W") then mx = mx + fx; mz = mz + fz end
    if input.is_key_down("S") then mx = mx - fx; mz = mz - fz end
    if input.is_key_down("D") then mx = mx + rx; mz = mz + rz end
    if input.is_key_down("A") then mx = mx - rx; mz = mz - rz end
    local len = math.sqrt(mx * mx + mz * mz)
    local speed = cam:get_speed()
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
    local d = cam:get_front()
    local hit = voxel.raycast(ex, ey, ez, d.x, d.y, d.z, REACH)

    -- Selection outline: move onto the targeted block; scale bars for screen-constant thickness.
    if highlight then
        if hit.hit then
            local c = hit.cell
            if not hl_shown then highlight:set_visible(true); hl_shown = true end
            if c.x ~= hl_x or c.y ~= hl_y or c.z ~= hl_z then
                hl_x, hl_y, hl_z = c.x, c.y, c.z
                highlight:set_position(vec3(c.x, c.y, c.z))
            end
            update_highlight_thickness(cam, c.x, c.y, c.z)
        elseif hl_shown then
            highlight:set_visible(false); hl_shown = false
        end
    end

    -- Break/place on the press edge.
    local mouse_edit = input.is_relative_mouse() and not skip_look
    local brk = input.is_key_down("Q") or (mouse_edit and input.is_left_mouse_down())
    local plc = input.is_key_down("E") or (mouse_edit and input.is_right_mouse_down())
    if (brk and not prevBreak) or (plc and not prevPlace) then
        if hit.hit then
            if brk and not prevBreak then
                voxel.set_block(hit.cell.x, hit.cell.y, hit.cell.z, 0)
            else
                voxel.set_block(hit.adjacent.x, hit.adjacent.y, hit.adjacent.z, HOTBAR[selected_slot].id)
            end
        end
    end
    prevBreak, prevPlace = brk, plc
end

function destroy()
    if highlight and scene and scene.delete_node then scene.delete_node(highlight) end
    highlight = nil
    hl_bars = {}
end
