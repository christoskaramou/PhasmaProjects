-- Async Jev session. The network call lives in PhasmaGameDriver.exe.
-- observe/act/reset return on the same frame. The match keeps ticking on the
-- last intent until the next reply replaces it.
local function module(path)
    local source = assert(fs.read(path), "Missing Jev module: " .. path)
    return assert(load(source, "@" .. path, "t", _ENV))()
end

local Driver = module("Scripts/gamekit/driver.lua")
Driver._json = module("Scripts/gamekit/json.lua")
local Boot = module("Scripts/jev_boot.lua")

local Auto = {}

-- hooks:
--   port, id, description
--   playing() -> bool          live match, not a menu
--   terminal() -> bool
--   score() -> number
--   busy() -> bool             optional; true only after apply has started a short
--                              in-game animation (a hop). Never true while waiting on Jev.
--   human_edge() -> bool       a real gameplay key went down this frame. Read the
--                              hardware key, never the virtual keys apply() sets.
--   observe() -> table         compact public facts, no functions
--   actions() -> { {id, description, score?}, ... }
--   apply(id)                  store a hold or a one-shot pulse. Return immediately.
--   reset(seed)                start a fresh match. Do not stop Jev and do not write a hi-score.
--   on_human()                 optional; drop held virtual keys
function Auto.attach(hooks)
    local human = false
    local jev = false
    local assisted = false
    local epoch = 0
    local boot = Boot.new(hooks.port)

    local function owned()
        return jev and not human and hooks.playing() and not hooks.terminal()
    end

    Driver.attach({
        id = hooks.id,
        description = hooks.description,
        observe = function()
            local actions = {}
            if owned() then
                actions = hooks.actions()
            end
            local mode = "menu"
            if hooks.terminal() then
                mode = "over"
            elseif hooks.playing() then
                mode = "playing"
            end
            return {
                mode = mode,
                terminal = hooks.terminal() == true,
                score = hooks.score() or 0,
                busy = hooks.busy and hooks.busy() or false,
                observation = hooks.observe(),
                actions = actions,
            }
        end,
        -- Mode and ownership only. Positions, timers and score stay out, so a reply
        -- that arrives late still applies and the frame loop never waits.
        state_key = function()
            local mode = "menu"
            if hooks.terminal() then
                mode = "over"
            elseif hooks.playing() then
                mode = "playing"
            end
            return {
                epoch = epoch,
                owned = owned(),
                mode = mode,
                busy = hooks.busy and hooks.busy() or false,
            }
        end,
        act = function(id)
            if not owned() then
                return
            end
            hooks.apply(id)
        end,
        reset = function(seed)
            human = false
            jev = true
            assisted = true
            epoch = epoch + 1
            hooks.reset(seed)
        end,
    })

    local api = {}

    function api.tick(dt)
        if jev and not human and hooks.human_edge and hooks.human_edge() then
            human = true
            if hooks.on_human then
                hooks.on_human()
            end
        end
        boot:update(dt)
        if hooks.terminal() and boot.running then
            boot:stop(true)
        end
    end

    function api.start()
        human = false
        jev = true
        assisted = true
        epoch = epoch + 1
        hooks.reset(math.random(1, 2147483646))
        local ok = boot:start()
        if not ok then
            jev = false
            return false, boot.error
        end
        return true
    end

    function api.begin_human()
        jev = false
        human = false
        assisted = false
        if hooks.on_human then
            hooks.on_human()
        end
        boot:stop(false)
    end

    function api.assisted()
        return assisted
    end

    function api.error()
        return boot.error
    end

    function api.note()
        if boot.error then
            return boot.error
        end
        if boot.running then
            return string.format("Jev %d ms", boot.think_ms or 0)
        end
        return nil
    end

    return api
end

return Auto
