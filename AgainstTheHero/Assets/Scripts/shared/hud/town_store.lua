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
    local D = _G.ATH_ACTIVE_DUEL
    if D and D.state == "town" then D._town_shop = not D._town_shop end
end

function on_enter_map()
    local D = _G.ATH_ACTIVE_DUEL
    if D and D.start_map then D:start_map() end
end
