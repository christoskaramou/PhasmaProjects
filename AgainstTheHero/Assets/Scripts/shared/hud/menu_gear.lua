-- Menu-scene gear button: toggles the authored "Menu Settings" group.
-- On the game scene, hud_gear.lua owns the gear and opens the Gear Hub instead.

function on_toggle_gear()
    local D = _G.ATH_ACTIVE_DUEL
    if D and D.toggle_inventory then
        D:toggle_inventory()
        return
    end
    if not (scene and scene.find_model) then return end
    local g = scene.find_model("Menu Settings")
    if not (g and g.set_enabled) then return end
    local on = true
    if g.is_enabled then on = not g:is_enabled() end
    g:set_enabled(on)
    if on and _G.ATH_HUB_SETTINGS and _G.ATH_HUB_SETTINGS.refresh then
        pcall(_G.ATH_HUB_SETTINGS.refresh, _G.ATH_ACTIVE_DUEL)
    end
    if pe_log then pe_log("[menu_gear] settings " .. (on and "on" or "off")) end
end
