-- Attached to the authored "HUD HP Text" node. Shows live hero HP from the
-- running arena (_G.ATH_ACTIVE_DUEL, set by game_boot). The node's static
-- "HERO -- / --" is the editor placeholder for visual tweaking.

hooks {
    update = function()
        local D = _G.ATH_ACTIVE_DUEL
        local hero = D and D.hero
        if not hero then return end
        self:set_ui({ body = string.format("HERO  %d / %d",
            math.floor((hero.hp or 0) + 0.5), math.floor((hero.hp_max or 0) + 0.5)) })
    end,
}
