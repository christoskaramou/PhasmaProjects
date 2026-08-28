-- Shared look / break / place / highlight / HUD for voxelcraft_controller and mine_controller.
-- Chess-style module (fs.read + load). Not a voxel framework: controllers keep spawn, world, move.
--
-- Block outline is one attach_lines cube (LinesPass, screen-constant 1px). Must be created in
-- init() before voxel.create — a regular mesh after the arena is reserved destroys it.

local FP = {}

FP.HOTBAR = {
    { id = 1, label = "1", fill = { r = 0.48, g = 0.48, b = 0.50, a = 0.92 } }, -- stone
    { id = 2, label = "2", fill = { r = 0.43, g = 0.28, b = 0.15, a = 0.92 } }, -- dirt
    { id = 3, label = "3", fill = { r = 0.27, g = 0.55, b = 0.20, a = 0.92 } }, -- grass
}

local highlight = nil
local hl_x, hl_y, hl_z = nil, nil, nil
local hl_shown = false

local cross_w, cross_h = 0, 0
local hotbar_w, hotbar_h, hotbar_selected = 0, 0, 0

local function block_overlaps_aabb(px, py, pz, hx, hy, hz, bx, by, bz)
    return bx < px + hx and bx + 1.0 > px - hx
        and by < py + hy and by + 1.0 > py - hy
        and bz < pz + hz and bz + 1.0 > pz - hz
end

function FP.make_highlight()
    if not (scene and scene.add_empty_node and scene.attach_lines) then return end
    local h = scene.add_empty_node("BlockHighlight")
    if not h then return end
    local lo, hi = -0.003, 1.003
    -- Cube wireframe as one strip (3 edges retraced). closed=false.
    scene.attach_lines(h, {
        vec3(lo, lo, lo), vec3(hi, lo, lo), vec3(hi, lo, hi), vec3(lo, lo, hi), vec3(lo, lo, lo),
        vec3(lo, hi, lo), vec3(hi, hi, lo), vec3(hi, hi, hi), vec3(lo, hi, hi), vec3(lo, hi, lo),
        vec3(hi, hi, lo), vec3(hi, lo, lo), vec3(hi, lo, hi), vec3(hi, hi, hi),
        vec3(lo, hi, hi), vec3(lo, lo, hi),
    }, false)
    if material and material.set then material.set(h, "emissive", vec3(1.0, 1.0, 1.0)) end
    if h.set_visible then h:set_visible(false) end
    highlight = h
    hl_x, hl_y, hl_z = nil, nil, nil
    hl_shown = false
end

function FP.destroy_highlight()
    if highlight and scene and scene.delete_node then scene.delete_node(highlight) end
    highlight = nil
    hl_shown = false
end

function FP.crosshair()
    if not (runtime_ui and runtime_ui.get_surface_size) then return end
    local s = runtime_ui.get_surface_size()
    if not s.valid then return end
    if s.w == cross_w and s.h == cross_h then return end
    cross_w, cross_h = s.w, s.h
    local sc = s.ui_scale or 1.0
    local L, T = 24.0 * sc, 4.0 * sc
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

function FP.hotbar(selected_slot)
    if not (runtime_ui and runtime_ui.get_surface_size) then return end
    local s = runtime_ui.get_surface_size()
    if not s.valid then return end
    if s.w == hotbar_w and s.h == hotbar_h and selected_slot == hotbar_selected then return end
    hotbar_w, hotbar_h, hotbar_selected = s.w, s.h, selected_slot
    local sc = s.ui_scale or 1.0
    local slot, gap = 34.0 * sc, 6.0 * sc
    local n = #FP.HOTBAR
    local total = (n * slot) + ((n - 1) * gap)
    local x0 = s.w * 0.5 - total * 0.5
    local y = s.h - (slot + 22.0 * sc)
    local text = { r = 1.0, g = 1.0, b = 1.0, a = 0.95 }
    for i, b in ipairs(FP.HOTBAR) do
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

function FP.hotbar_slot(selected_slot)
    for i = 1, #FP.HOTBAR do
        if input.is_key_down(FP.HOTBAR[i].label) then selected_slot = i end
    end
    return selected_slot
end

function FP.look(cam, skip)
    if input.is_relative_mouse() then
        local md = input.get_mouse_delta()
        if skip then
            -- Hold skip until LMB is up so click-to-regrab does not break a block next frame.
            if not input.is_left_mouse_down() then skip = false end
        elseif (md.x or 0) ~= 0 or (md.y or 0) ~= 0 then
            cam:rotate(md.x, md.y)
        end
    elseif input.is_left_mouse_down() then
        input.set_relative_mouse(true)
        skip = true
    end
    return skip
end

function FP.highlight(hit)
    if not highlight then return end
    if hit.hit then
        local c = hit.cell
        if not hl_shown then highlight:set_visible(true); hl_shown = true end
        if c.x ~= hl_x or c.y ~= hl_y or c.z ~= hl_z then
            hl_x, hl_y, hl_z = c.x, c.y, c.z
            highlight:set_position(vec3(c.x, c.y, c.z))
        end
    elseif hl_shown then
        highlight:set_visible(false); hl_shown = false
    end
end

function FP.edit(hit, px, py, pz, hx, hy, hz, block_id, skip, prev_break, prev_place)
    local mouse_edit = input.is_relative_mouse() and not skip
    local brk = input.is_key_down("Q") or (mouse_edit and input.is_left_mouse_down())
    local plc = input.is_key_down("E") or (mouse_edit and input.is_right_mouse_down())
    if (brk and not prev_break) or (plc and not prev_place) then
        if hit.hit then
            if brk and not prev_break then
                voxel.set_block(hit.cell.x, hit.cell.y, hit.cell.z, 0)
            else
                local a = hit.adjacent
                if not block_overlaps_aabb(px, py, pz, hx, hy, hz, a.x, a.y, a.z) then
                    voxel.set_block(a.x, a.y, a.z, block_id)
                end
            end
        end
    end
    return brk, plc
end

return FP
