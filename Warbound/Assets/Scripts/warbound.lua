-- Warbound — boot entry.
--
-- Referenced by skirmish.pescene's scene_scripts.on_play manifest (NOT the
-- Scripts/Player auto-load), so this boot runs only when the Warbound scene plays —
-- the scene owns its own gameplay driver. It bootstraps the module loader (raw
-- fs.read + load, since the loader file itself can't go through the loader), preloads
-- the game, and installs the per-frame driver via hooks{}. on_play scripts run with
-- the PlayerOnly lifecycle: init at play, destroy on stop, update each frame.
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
    local chunk, err = load(src, "@" .. tostring(assets_path or "") .. LOADER_PATH, "bt", _ENV)
    if not chunk then
        if pe_error then pe_error("Warbound: loader compile error: " .. tostring(err)) end
        return nil
    end
    return chunk()
end

local Loader = bootstrap_loader()
local Game = nil
local Hud = nil

if Loader then
    -- Load order must respect each module's load-time `local X = WB.x` captures:
    -- a module's dependencies must be preloaded before it (util -> world -> camera ...).
    local WB = Loader.preload({
        "util", "world", "camera", "units", "selection", "orders", "combat", "abilities", "economy", "build", "ai", "hud", "game",
    })
    Game = WB.game
    Hud = WB.hud
end

local started = false
local init_failed = false
local jev = nil

if Game then
    local jev_source = assert(fs.read("Scripts/jev_auto.lua"), "Missing Scripts/jev_auto.lua")
    local JevAuto = assert(load(jev_source, "@Scripts/jev_auto.lua", "t", _ENV))()

    -- Hardware keys and mouse buttons only. Virtual keys are never read here.
    local HUMAN_KEYS = { "q", "r", "w", "a", "s", "d", "up", "down", "left", "right" }
    local raw_prev = {}
    local human_seen = false

    local function baseline_human()
        human_seen = false
    end

    local function raw_key(name)
        if not (input and input.is_key_down_raw) then
            return false
        end

        local ok, down = pcall(input.is_key_down_raw, name)
        return ok and down == true
    end

    local function human_edge()
        local hit = false
        for i = 1, #HUMAN_KEYS do
            local name = HUMAN_KEYS[i]
            local down = raw_key(name)
            if human_seen and down and not raw_prev[name] then
                hit = true
            end
            raw_prev[name] = down
        end

        local left = input and input.is_left_mouse_down and input.is_left_mouse_down() == true
        local right = input and input.is_right_mouse_down and input.is_right_mouse_down() == true
        if human_seen and left and not raw_prev.lmb then
            hit = true
        end
        raw_prev.lmb = left
        if human_seen and right and not raw_prev.rmb then
            hit = true
        end
        raw_prev.rmb = right
        human_seen = true
        return hit
    end

    jev = JevAuto.attach({
        port = 9146,
        id = "warbound",
        description = "Warbound skirmish. Each action is one order: harvest gold, "
            .. "harvest lumber, train a laborer, train a soldier, "
            .. "attack the nearest enemy, or cast Warstomp. "
            .. "The match and the Wilds keep running.",
        playing = function()
            return Game.jev_playing()
        end,
        terminal = function()
            return Game.jev_terminal()
        end,
        score = function()
            return Game.jev_score()
        end,
        busy = function()
            return false
        end,
        human_edge = human_edge,
        observe = function()
            return Game.jev_observe()
        end,
        actions = function()
            return Game.jev_actions()
        end,
        apply = function(id)
            Game.store_pulse(id)
        end,
        reset = function(seed)
            math.randomseed(seed)
            Game.restart()
        end,
        on_human = function()
            Game.clear_pulse()
        end,
    })

    Game.human_start = function()
        jev:begin_human()
    end
    Game.jev_baseline = baseline_human
end

local function ensure_started()
    if started or init_failed then return end
    if Game and Game.init then
        local ok, err = pcall(Game.init)
        if not ok then
            init_failed = true
            if pe_error then pe_error("Warbound: init failed: " .. tostring(err)) end
            return
        end
    end
    started = true
end

local function update(dt)
    -- Node/file update hooks aren't always handed a dt; derive it from engine metrics.
    if not dt or dt <= 0.0 then
        local m = engine and engine.get_metrics and engine.get_metrics()
        dt = (m and m.delta_ms and m.delta_ms / 1000.0) or (1.0 / 60.0)
    end
    if dt > 0.1 then dt = 0.1 end -- clamp huge hitches (alt-tab, first-frame compile)

    if jev then
        jev:tick(dt)
    end
    if jev and Hud then
        if jev:error() then
            Hud.jev_note = nil
        else
            Hud.jev_note = jev:note()
        end
    end

    ensure_started()
    if started and Game and Game.update then
        local ok, err = pcall(Game.update, dt)
        if not ok and pe_error then pe_error("Warbound: update error: " .. tostring(err)) end
    end

    if not (jev and Hud and Hud.take_jev and Hud.take_jev()) then
        return
    end

    if Game.jev_baseline then
        Game.jev_baseline()
    end
    local ok = jev:start()
    if ok then
        Hud.notice = nil
        Hud.jev_note = jev:note()
        return
    end

    local err = jev:error() or "Jev could not start"
    Hud.notice = err
    Hud.jev_note = nil
    if pe_log then pe_log("[Warbound] " .. err) end
end

local function destroy()
    if jev then
        jev:begin_human()
    end
    if Game and Game.destroy then pcall(Game.destroy) end
    -- The Lua chunk persists across an editor Play -> Stop -> Play cycle, so the next
    -- Play's init hook must re-run Game.init. Without resetting `started` the second Play
    -- would skip init entirely (stale state, dead game loop while the camera still pans).
    started = false
    init_failed = false
end

hooks {
    init = ensure_started,
    update = update,
    destroy = destroy,
}
