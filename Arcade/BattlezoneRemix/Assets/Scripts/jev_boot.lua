-- Starts Bots/PhasmaGameDriver.exe and reads its lines without waiting.
-- proc.start only runs programs under this project's Assets/ tree. The launcher
-- (or the game's run.ps1) copies the engine build into Assets/Bots.
local Jev = {}
Jev.__index = Jev

local DRIVER = "Bots/PhasmaGameDriver.exe"
local COST_PER_TOKEN = 0.042 / 1000000
local STOP_GRACE = 3

local function missing_hint(message)
    if tostring(message):find("not found", 1, true) then
        return " (build it with Phasma/GameDriver/build.ps1, then launch this project from PhasmaLauncher or run.ps1 so it is copied into Assets/Bots)"
    end
    return ""
end

function Jev.new(port)
    return setmetatable({ port = port }, Jev):clear()
end

function Jev:clear()
    self.running = false
    self.think_ms = 0
    self.calls = 0
    self.input_tokens = 0
    self.cost = 0
    self.error = nil
    self.finished = false
    self.stop_timer = nil
    return self
end

-- Attaches to the match already running. No --seed: that would reset again.
function Jev:start()
    self:clear()
    if not self.port then
        self.error = "Jev needs Assets/Agent/agent_config.json with \"mcp\": true and an \"mcp_port\". Restart the player after changing it."
        return false
    end

    if not proc or not proc.start then
        self.error = "This player has no proc binding, so it cannot start the Jev driver."
        return false
    end

    local ok, message = proc.start(DRIVER, {
        "--url", "http://127.0.0.1:" .. self.port .. "/mcp",
        "--policy", "jev",
        "--key-source", "vault",
        "--steps", "5000",
    })
    if not ok then
        self.error = "Jev could not start: " .. tostring(message) .. missing_hint(message)
        return false
    end

    self.running = true
    return true
end

function Jev:add_call(tokens)
    self.calls = self.calls + 1
    self.input_tokens = self.input_tokens + tokens
    self.cost = self.input_tokens * COST_PER_TOKEN
end

function Jev:parse(line)
    local think, step_tokens = line:match("^%S+ step %d+ .*decision_ms=(%d+) input_tokens=(%d+)")
    if think then
        self.think_ms = tonumber(think)
        self:add_call(tonumber(step_tokens))
        return true
    end

    local redecide_tokens = line:match("^%S+ re%-decide %d+ .*input_tokens=(%d+)")
    if redecide_tokens then
        self:add_call(tonumber(redecide_tokens))
        return true
    end

    if line:match("^Finished:") then
        self.finished = true
        return false
    end

    local failure = line:match("^Game driver failed: (.+)")
    if failure then
        self.error = failure
    end
    return false
end

function Jev:drain()
    if not proc or not proc.read_line then
        return false
    end

    local changed = false
    local line = proc.read_line()
    while line do
        changed = self:parse(line) or changed
        line = proc.read_line()
    end
    return changed
end

function Jev:update(dt)
    if not self.running then
        return false
    end

    local changed = self:drain()
    if self.stop_timer then
        self.stop_timer = self.stop_timer - dt
        if self.stop_timer <= 0 then
            proc.stop()
        end
    end

    if proc.is_running() then
        return changed
    end

    self:drain()
    self.running = false
    self.stop_timer = nil
    return true
end

function Jev:stop(graceful)
    if not self.running then
        return
    end

    if graceful then
        self.stop_timer = self.stop_timer or STOP_GRACE
        return
    end

    if proc and proc.stop then
        proc.stop()
    end
    self.running = false
    self.stop_timer = nil
end

return Jev
