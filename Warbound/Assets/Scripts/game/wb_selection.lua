-- wb_selection — left-click / drag-box unit selection (player units only).
-- Stores the active selection and the live drag rectangle (the HUD draws the box).

local U = WB.util
local Camera = WB.camera

local Selection = {}

Selection.list = {}                 -- selected player units
Selection.building = nil            -- a single selected player building (mutually exclusive with units)
Selection.box = { active = false, x0 = 0, y0 = 0, x1 = 0, y1 = 0 }

local DRAG_MIN = 8.0                 -- px movement before a click becomes a box
local PICK_PX = 56.0                 -- single-click pick radius (screen px)

local prev_down = false
local press_x, press_y = 0.0, 0.0

local function mouse()
    if input and input.get_mouse_position then
        local m = input.get_mouse_position()
        if m and m.x then return m.x, m.y end
    end
    return nil
end

function Selection.clear()
    for _, u in ipairs(Selection.list) do WB.units.set_selected(u, false) end
    Selection.list = {}
    if Selection.building then WB.units.set_selected(Selection.building, false); Selection.building = nil end
end

function Selection.set(units)
    Selection.clear()
    for _, u in ipairs(units) do
        if u.alive then
            WB.units.set_selected(u, true)
            Selection.list[#Selection.list + 1] = u
        end
    end
end

-- Select a single building (clears any unit selection; they're mutually exclusive).
function Selection.set_building(b)
    Selection.clear()
    if b and b.alive then
        Selection.building = b
        WB.units.set_selected(b, true) -- toggles the building's ground ring
    end
end

function Selection.add(u)
    if not u.alive or u.selected then return end
    WB.units.set_selected(u, true)
    Selection.list[#Selection.list + 1] = u
end

-- Prune dead units from the selection (call when something dies).
function Selection.prune()
    U.compact(Selection.list, function(u) return u.alive end)
end

-- Nearest live unit in `units` whose on-screen center is within PICK_PX of (sx,sy).
function Selection.unit_at(sx, sy, units)
    local best, best_d
    for _, u in ipairs(units) do
        if u.alive then
            local px, py, depth = Camera.world_to_screen(u.x, 1.0, u.z)
            if px and depth and depth > 0.0 then
                local dx, dy = px - sx, py - sy
                local d = dx * dx + dy * dy
                if d <= PICK_PX * PICK_PX and (not best_d or d < best_d) then best, best_d = u, d end
            end
        end
    end
    return best
end

-- Handle selection input. `mouse_in_ui` suppresses world clicks over the HUD.
-- `state` is the match state (used for build confirm/cancel).
-- Returns nothing; mutates Selection.list/box.
function Selection.update(player_units, mouse_in_ui, state)
    -- Build-placement mode: left-click confirms, right-click cancels; consume the event.
    if WB.build and WB.build.is_placing and WB.build.is_placing() then
        local l = input and input.is_left_mouse_down and input.is_left_mouse_down() == true
        local r = input and input.is_right_mouse_down and input.is_right_mouse_down() == true
        if l and not prev_down then WB.build.confirm(state) end
        if r then WB.build.cancel() end
        prev_down = l
        return
    end

    local down = input and input.is_left_mouse_down and input.is_left_mouse_down() == true
    local mx, my = mouse()

    if down and not prev_down then
        -- press
        if mouse_in_ui or not mx then
            prev_down = down
            return
        end
        press_x, press_y = mx, my
        Selection.box.active = true
        Selection.box.x0, Selection.box.y0 = mx, my
        Selection.box.x1, Selection.box.y1 = mx, my
    elseif down and prev_down and Selection.box.active then
        -- drag
        if mx then Selection.box.x1, Selection.box.y1 = mx, my end
    elseif (not down) and prev_down and Selection.box.active then
        -- release -> resolve
        Selection.box.active = false
        local ex, ey = mx or press_x, my or press_y
        local moved = U.len2(ex - press_x, ey - press_y)
        if moved < DRAG_MIN then
            local hit = Selection.unit_at(press_x, press_y, player_units)
            if hit then
                Selection.set({ hit })
            else
                -- no unit under the cursor: try a player building, else clear
                local b = WB.economy and WB.economy.building_at and WB.economy.building_at(press_x, press_y)
                if b then Selection.set_building(b) else Selection.clear() end
            end
        else
            local x0, x1 = math.min(press_x, ex), math.max(press_x, ex)
            local y0, y1 = math.min(press_y, ey), math.max(press_y, ey)
            local picked = {}
            for _, u in ipairs(player_units) do
                if u.alive then
                    local px, py, depth = Camera.world_to_screen(u.x, 0.8, u.z)
                    if px and depth and depth > 0.0 and px >= x0 and px <= x1 and py >= y0 and py <= y1 then
                        picked[#picked + 1] = u
                    end
                end
            end
            if #picked > 0 then Selection.set(picked) else Selection.clear() end
        end
    end

    prev_down = down
end

return Selection
