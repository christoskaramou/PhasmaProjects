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

local src = read("Arcade/NeonCombat/Assets/Scripts/game.lua")

-- Tanks never get an `alive` field; only shells do. Gating on it makes the
-- guard always true and returns thrust_fire before the turn maths.
if src:find("not a.alive or not b.alive", 1, true) then
    fail("actions() still gates on tank.alive, which tanks never set, so no turn is ever offered")
end
if not src:find("local dx = b.x - a.x", 1, true) then
    fail("actions() does not compute the bearing to the other tank")
end
if not src:find("if err > 8 then", 1, true) then
    fail("actions() never offers left for a positive heading error")
end
if not src:find("if err < -8 then", 1, true) then
    fail("actions() never offers right for a negative heading error")
end

print("neon combat: turn actions are reachable")
