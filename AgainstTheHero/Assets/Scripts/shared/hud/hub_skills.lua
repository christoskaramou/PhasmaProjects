-- Skills hub tab: one icon per specialization; click spends a skill point.

local function allocate(slot)
    local D = _G.ATH_ACTIVE_DUEL
    local Inv = _G.ATH_INVENTORY
    if not (D and Inv and Inv.try_allocate_skill) then return end
    Inv.try_allocate_skill(D, slot)
end

for i = 1, 3 do
    _G["on_skill_" .. i] = function() allocate(i) end
end
