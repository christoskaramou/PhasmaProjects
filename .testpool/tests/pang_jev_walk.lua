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

local function actions_of(path)
    local src = read(path)
    local body = src:match("actions = function%(%)(.-)\n    end,")
    if not body then fail(path .. " has no Jev actions()") end
    return body
end

local function check(path)
    local body = actions_of(path)
    if body:find("math.abs(dy) > math.abs(dx)", 1, true) then
        fail(path .. " still climbs when the balloon is above, so Jev never walks under it")
    end
    if not body:find('id = "right"', 1, true) or not body:find('id = "left"', 1, true) then
        fail(path .. " does not offer a horizontal walk under the balloon")
    end
    local right_at = body:find('id = "right"', 1, true)
    local up_at = body:find('id = "up"', 1, true)
    if up_at and right_at and up_at < right_at then
        fail(path .. " offers climb before the walk")
    end
end

check("Arcade/PangRemix/Assets/Scripts/game.lua")
check("Arcade/PangRemix/tools/src/06_hud.lua")

-- Same aim as jev_aim. shot=false means the wire is already out.
local function jev_aim(b, player_x, shot)
    local grav, wire, pw, phw = 34, 30, 9.2, 0.5
    local x0, x1, ceil = -24, 24, 26
    local function clamp(v, a, c)
        if v < a then return a elseif v > c then return c end
        return v
    end
    local function escape()
        local safe = b.r * 0.9 + 0.45 + 0.45
        local dir = 1
        if b.vx > 0.4 then dir = -1 elseif b.vx < -0.4 then dir = 1
        else dir = ((x1 - b.x) >= (b.x - x0)) and 1 or -1 end
        if player_x > b.x + 0.35 then dir = 1 elseif player_x < b.x - 0.35 then dir = -1 end
        local side = b.x + dir * safe
        if side < x0 + phw or side > x1 - phw then dir = -dir end
        return clamp(b.x + dir * safe, x0 + phw, x1 - phw)
    end
    local clear = escape()
    local y_hit = b.r + 2.15
    if not shot or b.y <= y_hit then return clear end
    local y0 = 1.8
    local A = 0.5 * grav
    local B = wire - b.vy
    local C = y0 - b.y
    local disc = B * B - 4 * A * C
    if disc < 0 then return clear end
    local root = math.sqrt(disc)
    local t = (-B + root) / (2 * A)
    if t <= 0.02 then t = (-B - root) / (2 * A) end
    local y = y0 + wire * t
    if t <= 0.02 or t > 2.5 or y >= ceil - 0.2 or y <= y0 or y < y_hit + 2 then return clear end
    local lead = clamp(b.x + b.vx * t, x0 + phw, x1 - phw)
    local walk = math.abs(lead - player_x) / pw
    if walk > t - 0.05 then return clear end
    -- The shot is fired after the walk, not now. If the balloon has left the wire by then,
    -- the miss runs on to the ceiling and Jev must stay on the side instead.
    local y2 = b.y + b.vy * walk - 0.5 * grav * walk * walk
    local flight2 = (y2 - y0) / wire
    if flight2 <= 0.02 or y0 + wire * flight2 >= ceil - 0.2 then return clear end
    local ball_x = b.x + b.vx * (walk + flight2)
    if math.abs(ball_x - lead) > b.r + 0.12 then return clear end
    return lead
end

local function goal(balloon_x, player_x)
    local aim = jev_aim({ x = balloon_x, y = 18, vy = 0, vx = -4.8, r = 2.1 }, player_x, true)
    local dx = aim - player_x
    if dx > 0.3 then return "right" end
    if dx < -0.3 then return "left" end
    return "stop"
end

if goal(-30, -23.5) ~= "stop" then fail("a balloon past the left wall must not keep Jev walking into it") end
if goal(-10, -23.5) ~= "right" then fail("Jev must leave the left wall when the balloon moves right") end
if goal(-14, 0) ~= "left" then fail("Jev must still walk left toward a balloon") end

local low = jev_aim({ x = -21, y = 3.2, vy = -8, vx = 4.8, r = 2.1 }, -21, true)
if low <= -21 then fail("a low balloon on the left must send Jev off that spot, not into the wall") end
if low < -23.5 then fail("the dodge must stay inside the walk range") end

local busy = jev_aim({ x = -14, y = 18, vy = 0, vx = -4.8, r = 2.1 }, -14, false)
if math.abs(busy - -14) < 1 then
    fail("with the wire already out, Jev must not stand under the balloon")
end

-- Wire flight to y=16 is 0.47s. A size-1 balloon moves 2.3 in that time, past the 0.5 hit radius.
-- Firing anyway locks the wire until the ceiling, so the aim has to be the side, not underneath.
local miss = jev_aim({ x = 0, y = 16, vy = 0, vx = 4.8, r = 0.38 }, 0, true)
if miss >= -0.2 then
    fail("a shot that misses must step aside, not onto the wire, or the miss runs until the ceiling")
end

for _, path in ipairs({
    "Arcade/PangRemix/Assets/Scripts/game.lua",
    "Arcade/PangRemix/tools/src/06_hud.lua",
}) do
    local src = read(path)
    if not src:find("G.jev_x", 1, true) then
        fail(path .. " still holds Left into the wall instead of a point under the balloon")
    end
    if path:find("game.lua", 1, true) and not src:find("or G.jev_x", 1, true) then
        fail(path .. " still freezes Jev for the whole shot, so a fast reply pins it in place")
    end
    if not src:find("shot_free", 1, true) or not src:find("Stay beside the balloon", 1, true) then
        fail(path .. " still tells Jev to stand under a balloon when the wire cannot fire")
    end
    if not src:find("wire_outcome", 1, true) or not src:find("until the ceiling", 1, true) then
        fail(path .. " still fires a wire that will miss, then stands under the balloon for the whole trip to the ceiling")
    end
end

print("pang jev: walk under the balloon")
