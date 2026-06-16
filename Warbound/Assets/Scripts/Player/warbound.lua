-- Warbound — boot entry.
--
-- PhasmaPlayer auto-loads and runs every .lua in Assets/Scripts/Player/. This is the
-- one and only boot script: it bootstraps the module loader (raw fs.read + load,
-- since the loader file itself can't go through the loader), preloads the game, and
-- installs the per-frame driver via hooks{}.
--
-- The game world is built lazily on the FIRST update tick rather than in hooks.init,
-- so the game still boots even on engine paths where init isn't called for a
-- file-level script — update is the reliable signal that play mode is live.

local LOADER_PATH = "Scripts/game/wb_loader.lua"

local function bootstrap_loader()
    local src = fs and fs.read and fs.read(LOADER_PATH) or nil
    if not src then
        if pe_error then pe_error("Warbound: cannot read " .. LOADER_PATH) end
        return nil
    end
    local chunk, err = load(src, "@" .. tostring(assets_path or "") .. LOADER_PATH, "t", _ENV)
    if not chunk then
        if pe_error then pe_error("Warbound: loader compile error: " .. tostring(err)) end
        return nil
    end
    return chunk()
end

local Loader = bootstrap_loader()
local Game = nil

if Loader then
    -- Load order must respect each module's load-time `local X = WB.x` captures:
    -- a module's dependencies must be preloaded before it (util -> world -> camera ...).
    local WB = Loader.preload({
        "util", "world", "camera", "units", "selection", "orders", "combat", "abilities", "hud", "game",
    })
    Game = WB.game
end

local started = false
local present_set = false

local function ensure_started()
    if started then return end
    started = true
    if Game and Game.init then
        local ok, err = pcall(Game.init)
        if not ok and pe_error then pe_error("Warbound: init failed: " .. tostring(err)) end
    end
end

local function update(dt)
    -- Node/file update hooks aren't always handed a dt; derive it from engine metrics.
    if not dt or dt <= 0.0 then
        local m = engine and engine.get_metrics and engine.get_metrics()
        dt = (m and m.delta_ms and m.delta_ms / 1000.0) or (1.0 / 60.0)
    end
    if dt > 0.1 then dt = 0.1 end -- clamp huge hitches (alt-tab, first-frame compile)

    ensure_started()
    if Game and Game.update then
        local ok, err = pcall(Game.update, dt)
        if not ok and pe_error then pe_error("Warbound: update error: " .. tostring(err)) end
    end

    if not present_set then
        present_set = true
        if rhi and rhi.change_present_mode then pcall(rhi.change_present_mode, "fifo") end
    end
end

local function destroy()
    if Game and Game.destroy then pcall(Game.destroy) end
end

hooks {
    init = ensure_started,
    update = update,
    destroy = destroy,
}
