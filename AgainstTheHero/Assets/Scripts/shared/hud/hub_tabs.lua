-- Hub tab bar actions (game.pescene Pause Menu). Each authored tab node's
-- action_function calls the matching on_tab_* handler here.

local function tab(name)
    local D = _G.ATH_ACTIVE_DUEL
    local Inv = _G.ATH_INVENTORY
    if D and Inv and Inv.set_tab then Inv.set_tab(D, name) end
end

function on_tab_inventory() tab("inventory") end
function on_tab_settings() tab("settings") end
function on_tab_store() tab("store") end
function on_tab_skills() tab("skills") end
function on_tab_cards() tab("skills") end -- legacy alias
function on_tab_map() tab("map") end
function on_tab_system() tab("system") end
