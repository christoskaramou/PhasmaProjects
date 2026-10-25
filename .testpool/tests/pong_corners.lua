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

local src = read("Arcade/PongRemix/Assets/Scripts/game.lua")
local hit = src:match("local function hit_pad%(side%)(.-)\n    end")
if not hit then fail("hit_pad missing") end
if hit:find("BALL_R * 0.15", 1, true) then
    fail("paddle end still drops most of the ball radius, so a corner clip passes through")
end
if not hit:find("p.h * 0.5 + BALL_R", 1, true) then
    fail("paddle hit height is not the paddle plus the full ball")
end

local ai = src:match("local function ai_target%(%)(.-)\nend")
if not ai then fail("ai_target missing") end
if ai:find("y * skill", 1, true) then
    fail("AI still shrinks the intercept toward center, so the rail stays open")
end
if not ai:find("predict_y(PADDLE_X)", 1, true) then
    fail("AI does not aim at the paddle intercept")
end

if src:find("HALF_H - p.h * 0.5 - 0.05", 1, true) then
    fail("paddle still stops short of the rail")
end
if not src:find("predict_y(-PADDLE_X)", 1, true) then
    fail("Jev still tracks the ball's current height instead of the corner intercept")
end

local HALF_H, PADDLE_H, BALL_R = 10.0, 2.6, 0.38
local lim = HALF_H - PADDLE_H * 0.5
local ball_y = HALF_H - BALL_R
local hh = PADDLE_H * 0.5 + BALL_R
if math.abs(ball_y - lim) >= hh then
    fail(string.format("ball on the rail (y=%.2f) misses a paddle at the rail (center=%.2f, reach=%.2f)", ball_y, lim, hh))
end

local old_aim = ball_y * 0.82
local old_hh = PADDLE_H * 0.5 + BALL_R * 0.15
if math.abs(ball_y - old_aim) < old_hh then
    fail("old corner formula unexpectedly covered the rail; the regression no longer matches the bug")
end

print("pong corners: rail ball is inside the paddle")
