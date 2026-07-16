-- System + Map abandon actions (game.pescene Pause Menu).

function on_resume()
    local D = _G.ATH_ACTIVE_DUEL
    if not D or (D.console and D.console.visible) then return end
    if D.state == "pause" and not D._between_wave and D.resume_combat then
        D:resume_combat()
    end
end

function on_next_wave()
    local D = _G.ATH_ACTIVE_DUEL
    if not D or (D.console and D.console.visible) then return end
    if D and D.state == "pause" and D._between_wave and D.resume_combat then
        D:resume_combat()
    end
end

function on_quit_menu()
    -- Defer: Runtime UI actions fire mid-EndFrame (see ATH_REQUEST_SCENE).
    if _G.ATH_REQUEST_SCENE then
        _G.ATH_REQUEST_SCENE("intro.pescene")
    elseif scene and scene.load then
        scene.load("intro.pescene")
    end
end

function on_quit_app()
    -- Editor play: stop play (return to edit). Standalone player: exit process.
    if engine and engine.set_play_mode and engine.is_play_mode and engine.is_play_mode() then
        engine.set_play_mode(false)
        return
    end
    if engine and engine.quit then engine.quit() end
end

-- Leave the current dungeon map for the world map (town: just open picker;
-- mid-run: soft-reset the map first). Not a full quit to the main menu.
function on_exit_map()
    local D = _G.ATH_ACTIVE_DUEL
    if not D then return end
    D._abandon_armed = nil
    if D.exit_to_worldmap then
        D:exit_to_worldmap()
    elseif D.enter_worldmap then
        D:enter_worldmap()
    end
end

-- Stale binding from older scenes.
function on_abandon_run() on_exit_map() end
