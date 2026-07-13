-- Attached to the authored "HUD HP Text" node. Shows live hero HP from the
-- running arena (_G.ATH_ACTIVE_DUEL, set by game_boot). The node's static
-- "HERO -- / --" is the editor placeholder for visual tweaking.

hooks {
    update = function()
        local D = _G.ATH_ACTIVE_DUEL
        local hero = D and D.hero
        if not hero then return end
        local I18n = _G.ATH_I18N
        local fmt = (I18n and I18n.t("HERO  %d / %d",
            math.floor((hero.hp or 0) + 0.5), math.floor((hero.hp_max or 0) + 0.5)))
            or string.format("HERO  %d / %d",
                math.floor((hero.hp or 0) + 0.5), math.floor((hero.hp_max or 0) + 0.5))
        self:set_ui({ body = fmt })
    end,
}
