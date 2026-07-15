-- Skills hub tab: click a tree node to spend one skill point into that branch.

local function allocate(slot)
    local D = _G.ATH_ACTIVE_DUEL
    local Inv = _G.ATH_INVENTORY
    if not (D and Inv and Inv.try_allocate_skill) then return end
    Inv.try_allocate_skill(D, slot)
end

for i = 1, 15 do
    _G["on_skill_" .. i] = function() allocate(i) end
end
