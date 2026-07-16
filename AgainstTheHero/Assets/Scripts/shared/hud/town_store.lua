-- Actions for the authored town-store buttons in game.pescene.

local function buy(slot)
    local D = _G.ATH_ACTIVE_DUEL
    if D and D.buy_store_offer then D:buy_store_offer(slot) end
end

function on_buy_helmet() buy("helmet") end
function on_buy_body() buy("body") end
function on_buy_pants() buy("pants") end
function on_buy_gloves() buy("gloves") end
function on_buy_weapon() buy("weapon") end
function on_buy_jewelry() buy("jewelry") end

function on_toggle_shop()
    -- Orphaned: Town Shop Toggle node removed (store is a hub tab).
end

function on_enter_map()
    local D = _G.ATH_ACTIVE_DUEL
    if not D or (D.console and D.console.visible) then return end
    if D.state == "town" and D.start_map then
        D:start_map()
    elseif D.state == "pause" and D._between_wave and D.resume_combat then
        D:resume_combat() -- advances into the next round
    end
end

-- Stale binding — destination is display-only; use EXIT TO MAP.
function on_open_worldmap()
    local D = _G.ATH_ACTIVE_DUEL
    if D and D.exit_to_worldmap then
        D:exit_to_worldmap()
    elseif D and D.enter_worldmap then
        D:enter_worldmap()
    end
end
