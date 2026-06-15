-- Attached to the authored "HUD HP Fill" panel (the colored bar drawn over its
-- dark "HUD HP BG" sibling). Scales its width to the hero's HP %. The width you
-- author in the editor is the 100% size; the script shrinks the X scale toward
-- the left edge (the node's translation is its left edge, so position is kept).

local base

hooks {
    init = function()
        base = self:get_scale()
    end,
    update = function()
        if not base then base = self:get_scale() end
        local D = _G.ATH_ACTIVE_DUEL
        local hero = D and D.hero
        local ratio = 1.0
        if hero and hero.hp_max and hero.hp_max > 0 then
            ratio = math.max(0.0, math.min(1.0, (hero.hp or 0) / hero.hp_max))
        end
        self:set_scale(vec3(base.x * ratio, base.y, base.z))
    end,
}
