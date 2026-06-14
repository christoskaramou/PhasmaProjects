-- Android entry point. Mirrors Player/against_the_hero.lua's bootstrap (sets up
-- ATH_COMMON by hand, since a scene script component is loaded raw, not through
-- Common.load_script), then drops STRAIGHT into the manual arena so the touch
-- joystick, hit feedback, and the gear loop are immediately testable on a phone
-- without navigating the menu. Attached to a node in ath_bootstrap.pescene.

local COMMON_PATH = "Scripts/shared/ath_common.lua"

local Duel, arena, active

local function boot_common()
    local src = fs and fs.read and fs.read(COMMON_PATH) or nil
    if not src then
        if pe_error then pe_error("ATH android boot: missing " .. COMMON_PATH) end
        return nil
    end
    local chunk, err = load(src, "@" .. tostring(assets_path or "") .. COMMON_PATH, "t", _ENV)
    if not chunk then
        if pe_error then pe_error("ATH android boot: " .. tostring(err)) end
        return nil
    end
    return chunk()
end

local function init()
    local Common = boot_common()
    if not Common then return end
    Duel = Common.load_script("Scripts/shared/ath_duel.lua", "shared duel", _ENV)
    arena = Common.load_script("Scripts/modes/arena/mode.lua", "arena mode", _ENV)
    if not (Duel and arena and arena.config) then
        if pe_error then pe_error("ATH android boot: failed to load arena mode") end
        return
    end
    -- Android: skip IBL (its equirect->cubemap build shader isn't in the prebaked
    -- SPIR-V cache; ATH is emissive-lit so IBL adds ~nothing). Threaded through the
    -- config so Duel:start's setup_stage sets IBL off BEFORE the engine builds it.
    arena.config.no_ibl = true
    active = Duel.new(arena.config, { side = "hero" }, { return_to_menu = function() end })
    active:start()
    -- Shader-bake / headless runs set ATH_AUTOSTART so combat begins without a
    -- human picking a class — that's how the desktop bake exercises (and compiles)
    -- every render pass ATH uses (culling, particles, bolts). On device the env is
    -- unset, so the normal class-pick screen is shown.
    if Common.getenv and Common.getenv("ATH_AUTOSTART") and active.choose_class then
        active:choose_class(1)
    end
    if pe_log then pe_log("[ATH] android boot: arena started") end
end

local present_set = false
local function update(dt)
    -- The engine doesn't always pass dt to node-script update hooks (it can be
    -- nil), so derive it from the frame metrics with a 60fps fallback + a spike cap.
    if not dt or dt <= 0.0 then
        local m = engine and engine.get_metrics and engine.get_metrics()
        dt = (m and m.delta_ms and m.delta_ms / 1000.0) or (1.0 / 60.0)
    end
    if dt > 0.1 then dt = 0.1 end
    if active then active:update(dt) end
    -- FIFO vsync, deferred to the first frame: doing it in init() races the
    -- swapchain surface (getSurfacePresentModesKHR -> ErrorSurfaceLostKHR). pcall'd
    -- so any transient surface state never aborts the frame loop. render_scale stays
    -- LOW (scene's 0.75) for Mali perf; IBL/FXAA/CAS come from Art.setup_stage.
    if not present_set then
        present_set = true
        if rhi and rhi.change_present_mode then pcall(rhi.change_present_mode, "fifo") end
    end
end

local function destroy()
    if active and active.stop then active:stop() end
    active = nil
end

hooks {
    init = init,
    update = update,
    destroy = destroy,
}
