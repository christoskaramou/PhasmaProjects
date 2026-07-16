-- Cross-scene run state for the ATH flow (intro -> hero_select -> game).
--
-- Lives on the TRUE global table (_G) so it survives scene.load, which tears
-- down per-node script instances but NOT the shared Lua state. Auto-loaded from
-- Assets/Scripts/global (Always lifecycle) so it exists before any menu runs.
-- The menu buttons (shared/flow.lua) write the player's choices here; the game
-- scene's launcher (shared/game_boot.lua) reads them to start the arena.
_G.ATH_RUN = _G.ATH_RUN or {
    hero_index = 1,        -- 1-based index into arena config.hero.classes
    battlefield = "arena", -- modes/<battlefield>/mode.lua (only "arena" is manual-playable today)
    -- save_slot set by Profile.set_active / New Game / Continue (not defaulted to 1)
}

-- Runtime UI dispatches authored button actions inside EndFrame/BuildFrame —
-- AFTER SyncSceneWidgets for that frame. A synchronous scene.load there swaps
-- the 3D world while the previous menu's widgets still draw on top (chicken
-- under CHOOSE YOUR HERO). Queue the load; any scene update hook flushes it
-- before the next SyncSceneWidgets + Draw.
function _G.ATH_REQUEST_SCENE(name)
    if type(name) ~= "string" or name == "" then return end
    _G.ATH_RUN = _G.ATH_RUN or {}
    _G.ATH_RUN._pending_scene = name
end

function _G.ATH_FLUSH_SCENE()
    local r = _G.ATH_RUN
    local name = r and r._pending_scene
    if not name then return end
    r._pending_scene = nil
    if scene and scene.load then scene.load(name) end
    -- Plan C: veil the game scene for the gap frame before game_boot init.
    -- Boot Cover ships disabled (editor stays usable); raise it here so the
    -- first Draw after load never shows the unfinished arena.
    if name == "game.pescene" and scene.find_model then
        local cover = scene.find_model("Boot Cover")
        if cover and cover.set_enabled then cover:set_enabled(true) end
        local hero = scene.find_model("Hero")
        if hero and hero.set_enabled then hero:set_enabled(false) end
    end
end

-- Locale + persisted settings. Always re-run so a long-lived Lua state picks up
-- newly added fields/methods (ath_i18n merges into the existing singleton).
do
    local path = "Scripts/shared/ath_i18n.lua"
    local src = fs and fs.read and fs.read(path) or nil
    if src then
        local chunk = load(src, "@" .. tostring(assets_path or "") .. path, "t", _ENV)
        if chunk then pcall(chunk) end
    end
end
