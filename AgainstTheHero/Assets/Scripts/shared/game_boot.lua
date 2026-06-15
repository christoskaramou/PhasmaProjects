-- Game-scene launcher (attach to a node in game.pescene via the "script" key).
--
-- Reads the menu's choices from _G.ATH_RUN (hero class index + battlefield),
-- loads the Duel engine + the chosen battlefield mode, and starts the manual
-- arena with that hero. Mirrors Player/ath_android_boot.lua's bootstrap, but is
-- SCENE-DRIVEN (runs only while game.pescene is the active scene, via its node
-- hooks) instead of auto-booting from the Player script dir.

local COMMON_PATH = "Scripts/shared/ath_common.lua"
local Duel, active

local function boot_common()
    local src = fs and fs.read and fs.read(COMMON_PATH) or nil
    if not src then
        if pe_error then pe_error("ATH game boot: missing " .. COMMON_PATH) end
        return nil
    end
    local chunk, err = load(src, "@" .. tostring(assets_path or "") .. COMMON_PATH, "t", _ENV)
    if not chunk then
        if pe_error then pe_error("ATH game boot: " .. tostring(err)) end
        return nil
    end
    return chunk()
end

local function run()
    _G.ATH_RUN = _G.ATH_RUN or { hero_index = 1, battlefield = "arena" }
    return _G.ATH_RUN
end

-- Tear down any arena left over from a previous launch before building a fresh
-- one. This matters in the EDITOR: play-stop does NOT call node destroy() hooks
-- (StopRuntimePlaySession only stops audio/physics) and the play-stop snapshot
-- restore leaves script-built top-level nodes in place, so without this guard the
-- arena's "<id>_Root" group would stack up on every play/stop cycle. In the real
-- player the scene is built once, so this is a no-op there.
local function cleanup_previous()
    if _G.ATH_ACTIVE_DUEL and _G.ATH_ACTIVE_DUEL.stop then
        pcall(function() _G.ATH_ACTIVE_DUEL:stop() end)
    end
    _G.ATH_ACTIVE_DUEL = nil
    -- Belt-and-suspenders: delete any orphaned top-level "*_Root" arena group whose
    -- Duel handle was lost across a snapshot restore. get_entities() returns only
    -- top-level nodes (the arena root is parented to nil), so this is well scoped.
    if scene and scene.get_entities and scene.delete_node then
        for _, e in ipairs(scene.get_entities() or {}) do
            if type(e.label) == "string" and e.label:match("_Root$") and e.node then
                pcall(function() scene.delete_node(e.node) end)
            end
        end
    end
end

local function init()
    local Common = boot_common()
    if not Common then return end
    cleanup_previous()
    local R = run()
    local field = R.battlefield or "arena"
    Duel = Common.load_script("Scripts/shared/ath_duel.lua", "shared duel", _ENV)
    local mode = Common.load_script("Scripts/modes/" .. field .. "/mode.lua", "battlefield " .. field, _ENV)
    if not (Duel and mode and mode.config) then
        if pe_error then pe_error("ATH game boot: failed to load battlefield '" .. tostring(field) .. "'") end
        return
    end
    -- Match the Android direct-boot path: skip IBL (prebaked SPIR-V only) and let
    -- the arena draw its own FPS clock since there's no menu shell here.
    mode.config.no_ibl = true
    -- The authored scene UI (game.pescene HUD nodes) draws the HP + wave-budget
    -- bars and the FPS readout, so suppress the arena's built-in versions.
    mode.config.external_hud = true
    mode.config.direct_boot = false
    -- game.pescene also authors the arena's STATIC stage (Floor / Wall_* / Spawn_*
    -- under the "Stage" group) and the hero sprite ("Hero" + child "Hero Body") as
    -- real scene nodes. Tell the Duel to ADOPT those instead of building them, so the
    -- script only drives the dynamic side (spawns / movement / HP). Scoped to the
    -- arena field, whose authored node names + transforms match these.
    if field == "arena" then
        mode.config.arena = mode.config.arena or {}
        mode.config.arena.scene_stage = true
        mode.config.hero = mode.config.hero or {}
        mode.config.hero.scene_node = "Hero"
        mode.config.hero.scene_body = "Hero Body"
    end
    active = Duel.new(mode.config, { side = "hero" }, {
        return_to_menu = function() scene.load("intro.pescene") end,
    })
    _G.ATH_ACTIVE_DUEL = active
    active:start()
    local idx = R.hero_index or 1
    if active.choose_class then active:choose_class(idx) end
    if pe_log then pe_log("[ATH] game boot: battlefield=" .. field .. " hero_index=" .. tostring(idx)) end
end

local present_set = false
local function update(dt)
    -- The engine doesn't always pass dt to node update hooks; derive from metrics.
    if not dt or dt <= 0.0 then
        local m = engine and engine.get_metrics and engine.get_metrics()
        dt = (m and m.delta_ms and m.delta_ms / 1000.0) or (1.0 / 60.0)
    end
    if dt > 0.1 then dt = 0.1 end
    if active then active:update(dt) end
    if not present_set then
        present_set = true
        if rhi and rhi.change_present_mode then pcall(rhi.change_present_mode, "fifo") end
    end
end

local function destroy()
    if active and active.stop then active:stop() end
    if _G.ATH_ACTIVE_DUEL == active then _G.ATH_ACTIVE_DUEL = nil end
    active = nil
end

hooks {
    init = init,
    update = update,
    destroy = destroy,
}
