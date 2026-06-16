-- Attached to the authored "Pause Next Wave" button (game.pescene, under the
-- "Pause Menu" group). The button's runtime_ui.action_function = "on_next_wave";
-- the engine resolves it on THIS node's script env. It only RESUMES the run —
-- all pause/inventory state lives on the active Duel. Action-only, by design.

function on_next_wave()
    local D = _G.ATH_ACTIVE_DUEL
    if D and D.resume_combat then D:resume_combat() end
end
