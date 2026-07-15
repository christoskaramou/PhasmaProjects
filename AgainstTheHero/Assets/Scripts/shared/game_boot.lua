-- Game-scene launcher (attach to a node in game.pescene via the "script" key).
--
-- Reads the menu's choices from _G.ATH_RUN (hero class index + battlefield),
-- loads the Duel engine + the chosen battlefield mode, and starts the manual
-- arena with that hero. Mirrors Player/ath_android_boot.lua's bootstrap, but is
-- SCENE-DRIVEN (runs only while game.pescene is the active scene, via its node
-- hooks) instead of auto-booting from the Player script dir.
--
-- Plan C: game.pescene ships an opaque "Boot Cover" UI panel. The gap frame
-- after scene.load (before this init runs) only shows that veil. We finish
-- hero + town setup under the cover, then disable it so the first real view
-- is already ready.

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

local function set_boot_cover(on)
    local cover = scene and scene.find_model and scene.find_model("Boot Cover")
    if cover and cover.set_enabled then cover:set_enabled(on and true or false) end
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
    if scene and scene.get_entities and scene.delete_node then
        for _, e in ipairs(scene.get_entities() or {}) do
            if type(e.label) == "string" and e.label:match("_Root$") and e.node then
                pcall(function() scene.delete_node(e.node) end)
            end
        end
    end
end

local function init()
    -- Keep the veil up for the whole boot (authored enabled; re-assert here).
    set_boot_cover(true)
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
    mode.config.no_ibl = true
    mode.config.external_hud = true
    mode.config.direct_boot = false
    if field == "arena" then
        mode.config.arena = mode.config.arena or {}
        mode.config.arena.scene_stage = true
        mode.config.hero = mode.config.hero or {}
        mode.config.hero.scene_node = "Hero"
        mode.config.hero.scene_body = "Hero Body"
    end
    active = Duel.new(mode.config, { side = "hero" }, {
        return_to_menu = function()
            if _G.ATH_REQUEST_SCENE then
                _G.ATH_REQUEST_SCENE("intro.pescene")
            else
                scene.load("intro.pescene")
            end
        end,
    })
    _G.ATH_ACTIVE_DUEL = active
    active:start()
    local idx = R.hero_index or 1
    local requested = Common.getenv("ATH_HERO_CLASS", nil)
    for i, class in ipairs((mode.config.hero and mode.config.hero.classes) or {}) do
        if class.id == requested then idx = i; break end
    end
    if active.choose_class then active:choose_class(idx) end
    -- Ready: drop the veil so the next Draw shows map + hub + skinned hero.
    set_boot_cover(false)
    if pe_log then pe_log("[ATH] game boot: ready battlefield=" .. field .. " hero_index=" .. tostring(idx)) end
end

local present_set = false
local function update(dt)
    if _G.ATH_FLUSH_SCENE then _G.ATH_FLUSH_SCENE() end
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
