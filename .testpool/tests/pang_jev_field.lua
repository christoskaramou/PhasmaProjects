local function read(path)
    local f = assert(io.open(path, "rb"), "missing " .. path)
    local text = f:read("*a")
    f:close()
    return text
end

local function fail(msg)
    io.stderr:write(msg .. "\n")
    os.exit(1)
end

local function creep_side(player_x, crab_x)
    local away = crab_x >= player_x and -1 or 1
    local lo, hi = -23.5, 23.5
    local function clamp(v)
        if v < lo then return lo elseif v > hi then return hi end
        return v
    end
    local dest = clamp(player_x + away * 4.5)
    if math.abs(dest - player_x) < 0.4 then
        away = -away
        dest = clamp(player_x + away * 4.5)
    end
    return dest
end

if not (creep_side(0, 4) < -1) then fail("a crab on the right must send Jev left") end
if not (creep_side(0, -4) > 1) then fail("a crab on the left must send Jev right") end
if creep_side(-23.2, -22) <= -23 then fail("a crab pinning the left wall must send Jev back into the field") end

local auto = read("Arcade/PangRemix/Assets/Scripts/jev_auto.lua")
local engage = auto:match("function api%.engage%(%)(.-)\n    end")
if not engage then fail("settings cannot turn Jev on: there is no engage()") end
if engage:find("hooks.reset", 1, true) or engage:find("new_game", 1, true) then
    fail("turning Jev on resets the stage")
end

local menu = read("Arcade/PangRemix/Assets/Scripts/Lib/settings_menu.lua")
if not menu:find("self.opts.extra", 1, true) then
    fail("settings has no row slot for Jev")
end
local after = menu:match("function M:after_change%(id%)(.-)\nend")
if not after then fail("settings after_change is missing") end
if after:find("else self:apply_graphics", 1, true) then
    fail("the Jev toggle reloads graphics")
end

local function has(path, needle, msg)
    local src = read(path)
    if not src:find(needle, 1, true) then fail(path .. " " .. msg) end
end

for _, path in ipairs({
    "Arcade/PangRemix/Assets/Scripts/game.lua",
    "Arcade/PangRemix/tools/src/01_core.lua",
}) do
    has(path, 'label = "JEV"', "has no JEV switch in settings")
end

for _, path in ipairs({
    "Arcade/PangRemix/Assets/Scripts/game.lua",
    "Arcade/PangRemix/tools/src/06_hud.lua",
}) do
    has(path, "jev:engage()", "turns Jev on by starting a new game")
    has(path, 'kind == "crab"', "does not step away from a crab")
    has(path, 'it.kind == "fruit"', "does not pick up fruit")
    has(path, "Step away from the crab", "does not tell Jev to leave the crab")
    has(path, "Climb the ladder", "does not climb for a pickup")
    has(path, "not G.set_open", "treats the settings keys as the player grabbing the match")
end

print("pang jev: settings, crabs, ladders, fruit")
