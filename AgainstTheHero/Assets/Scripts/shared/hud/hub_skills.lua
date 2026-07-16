-- Skills hub tab: the authored plates are column anchors behind the tree
-- cells; a click that falls between cells buys the column's keystone.

local function allocate(slot)
    local D = _G.ATH_ACTIVE_DUEL
    local Inv = _G.ATH_INVENTORY
    if not (D and Inv and Inv.try_allocate_skill and Inv.class_specs) then return end
    local spec = Inv.class_specs(D)[slot]
    if spec then Inv.try_allocate_skill(D, spec.id, "key") end
end

for i = 1, 3 do
    _G["on_skill_" .. i] = function() allocate(i) end
end
