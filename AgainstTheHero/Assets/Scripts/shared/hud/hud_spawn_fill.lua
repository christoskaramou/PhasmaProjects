-- Attached to the authored "HUD Spawn Fill" panel. Scales its width to the
-- remaining wave budget / reserve of the running arena (_G.ATH_ACTIVE_DUEL).
-- Same width-as-bar trick as hud_hp_fill.

local base

hooks {
    init = function()
        base = self:get_scale()
    end,
    update = function()
        if not base then base = self:get_scale() end
        local D = _G.ATH_ACTIVE_DUEL
        local ratio = 1.0
        if D and D.reserve then
            local start = D.reserve_start or (D.config and D.config.reserve_start)
            if start and start > 0 then
                ratio = math.max(0.0, math.min(1.0, D.reserve / start))
            end
        end
        self:set_scale(vec3(base.x * ratio, base.y, base.z))
    end,
}
