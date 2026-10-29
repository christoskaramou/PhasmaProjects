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

local src = read("Arcade/NeonInvaders/Assets/Scripts/game.lua")

-- Invaders are built with ox/oy (game.lua:213) and moved through formation.x/y;
-- only inv_pos() (game.lua:309) turns that into a world position.
if src:find("ax = iv.x", 1, true) then
    fail("aim_dx still reads iv.x, which is nil for every invader, so actions() errors")
end
if not src:find("local x, y = inv_pos(iv)", 1, true) then
    fail("aim_dx does not use inv_pos() to resolve the invader's world position")
end
if not src:find("ax = x", 1, true) then
    fail("aim_dx does not assign the resolved world x to the aim")
end

print("neon invaders: aim resolves invader world position")
