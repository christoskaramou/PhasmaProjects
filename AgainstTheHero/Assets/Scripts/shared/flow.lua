-- ATH scene-flow controller (4-scene flow: intro -> hero_select -> map -> game).
--
-- Attach this script to authored UI Button nodes (the .pescene "script" key).
-- Each button's runtime_ui.action_function names one handler below; the engine
-- resolves it on THIS node's script env and calls it as handler(event).
--
-- scene.load(name) resolves to Assets/Scenes/<name>, so pass the bare filename.
-- Cross-scene choices live on _G.ATH_RUN (see Scripts/global/ath_run.lua), which
-- survives scene.load; the game scene's launcher reads them to start the arena.
-- (Cards are NOT a menu scene: they're drafted in-arena between rounds.)

local function log(msg)
    if pe_log then
        pe_log("[flow] " .. msg)
    else
        print("[flow] " .. msg)
    end
end

local function run()
    _G.ATH_RUN = _G.ATH_RUN or { hero_index = 1, battlefield = "arena" }
    return _G.ATH_RUN
end

local function go(name)
    log("scene.load -> " .. name)
    scene.load(name)
end

-- intro --------------------------------------------------------------------
function on_play() go("hero_select.pescene") end

-- hero_select: index into arena config.hero.classes (1=ranger, 2=brawler, 3=sower)
function on_pick_ranger()  run().hero_index = 1; log("hero = ranger");  go("map.pescene") end
function on_pick_brawler() run().hero_index = 2; log("hero = brawler"); go("map.pescene") end
function on_pick_sower()   run().hero_index = 3; log("hero = sower");   go("map.pescene") end

-- map: battlefield = modes/<id>/mode.lua (only arena is manual-playable today)
function on_map_arena() run().battlefield = "arena"; log("battlefield = arena"); go("game.pescene") end
function on_locked()    log("battlefield locked (no manual config yet)") end

-- back navigation ----------------------------------------------------------
function on_back_intro() go("intro.pescene") end
function on_back_hero()  go("hero_select.pescene") end
