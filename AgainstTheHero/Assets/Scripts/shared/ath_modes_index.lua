-- ath_modes_index — the list of menu-launchable modes, in display order.
--
-- The shell loads each "Scripts/modes/<id>/mode.lua", expects it to return
-- { meta = {...}, config = {...} }, and renders it on the battlefield-select
-- screen. To add a mode: drop modes/<id>/ and add its id.

return {
    modes = {
        "arena",         -- manual-hero 5-wave experiment; launch with ATH_DUEL_MODE=arena ATH_SIDE=hero
        -- Chunky-cartoon flat-sprite arenas; per-enemy + hero textures.
        "spud_fields",    -- sunny farm; goofy garden horde + diving crows; mud wallows slow the hero
        "alien_hive",     -- glowing bio-hive; cute-grotesque brood + stingers; acid sumps melt the hero
    },
}
