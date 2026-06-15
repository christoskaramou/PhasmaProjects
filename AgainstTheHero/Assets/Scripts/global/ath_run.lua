-- Cross-scene run state for the ATH 4-scene flow (intro -> hero_select -> map -> game).
--
-- Lives on the TRUE global table (_G) so it survives scene.load, which tears
-- down per-node script instances but NOT the shared Lua state. Auto-loaded from
-- Assets/Scripts/global (Always lifecycle) so it exists before any menu runs.
-- The menu buttons (shared/flow.lua) write the player's choices here; the game
-- scene's launcher (shared/game_boot.lua) reads them to start the arena.
_G.ATH_RUN = _G.ATH_RUN or {
    hero_index = 1,        -- 1-based index into arena config.hero.classes (1=ranger, 2=brawler, 3=sower)
    battlefield = "arena", -- modes/<battlefield>/mode.lua (only "arena" is manual-playable today)
}
