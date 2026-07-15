-- Orphaned: game.pescene System buttons use hub_system.lua.

function on_next_wave()
    local D = _G.ATH_ACTIVE_DUEL
    if D and D.state == "pause" and D._between_wave and D.resume_combat then
        D:resume_combat()
    end
end
