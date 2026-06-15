-- Attached to the authored "HUD Gear" button. Toggles the authored "HUD
-- Inventory" panel (a top-level node, authored hidden via "enabled": false).
-- Demonstrates the button -> script -> show/hide-authored-panel pattern.

local function find_top(name)
    if not (scene and scene.get_entities) then return nil end
    for _, e in ipairs(scene.get_entities() or {}) do
        if e.label == name and e.node then return e.node end
    end
    return nil
end

function on_toggle_gear()
    local inv = find_top("HUD Inventory")
    if inv and inv.is_enabled and inv.set_enabled then
        local now = inv:is_enabled()
        inv:set_enabled(not now)
        if pe_log then pe_log("[hud] inventory " .. (now and "hidden" or "shown")) end
    end
end
