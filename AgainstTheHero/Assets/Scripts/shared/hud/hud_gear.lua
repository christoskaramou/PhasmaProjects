-- Attached to the authored "HUD Gear Hit" button. Opens / closes the authored
-- "Pause Menu" (inventory) by asking the active Duel to toggle its inventory
-- pause. The Duel owns the pause state + the authored Pause Menu group's
-- visibility; this script only forwards the action.

function on_toggle_gear()
    local D = _G.ATH_ACTIVE_DUEL
    if D and D.toggle_inventory then
        D:toggle_inventory()
        if pe_log then pe_log("[hud] toggle inventory") end
    end
end
