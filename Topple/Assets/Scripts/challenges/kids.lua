-- The Kids' Room's challenges (room 5, unlocks the Ball): set the toy train off. Format: topple_challenges.lua.
-- The goal is a switch on the play mat just south of the train. A ball rolls about 32 on the mat from a good hit (the
-- gap before it about 1.35), about 24 if it first climbs the mat's 0.1 lip from the floor: far more than a box of
-- dominoes reaches. Level 1 starts on the mat, so its ball meets no lip. The block tower in the lane east of the
-- train is fragile: a ball that hits it brings it down and bounces back.
local GOAL = { x = -7, y = -26.1, h = 0.1 }
local CAM = { x = 6, y = -24, h = 1, yaw = -100, pitch = 38, dist = 52 }
local TOWER = { kind = "support", id = "block tower", x0 = 1.0, x1 = 4.0, y0 = -27.6, y1 = -24.6, z0 = 0, z1 = 6 }
return {
    finish = { x = -6.05, y = -26.1, h = 0.1, a = math.pi },     -- the End, east of the train switch (level 2 has its own)
    goal = GOAL,                                               -- the goal the End sets off
    {
        id = "kids_ball", name = "All Aboard", icon = "tool_ball", unlock = "ball",
        brief = "Too far for your dominoes: tip one into a ball and let it roll to the train.",
        goal_word = "Start the train", win = "TOOT TOOT!", fail = "THE TRAIN STAYED PUT",
        tools = { "draw", "line", "ball" },
        start = { x = 10, y = -26.1, h = 0.1, a = math.pi },
        budget = { domino = 8, ball = 1 },
        challenges = { { kind = "thrift", n = 2 }, { kind = "all_fall" } },
        camera = CAM,
    },
    {
        id = "kids_tower", name = "Mind the Blocks",
        finish = { x = -7, y = -27.05, h = 0.1, a = math.pi / 2 },   -- (its own End: this level comes in from the south)
        brief = "The block tower is in the ball's way and falls at a touch. Roll round it and bend back to the train.",
        goal_word = "Start the train", win = "TOOT TOOT!", fail = "CRASH! THE TOWER'S DOWN",
        tools = { "draw", "line", "ball" },
        start = { x = 22, y = -26.1, h = 0, a = math.pi },
        traps = { TOWER },
        budget = { domino = 34, ball = 1 },
        challenges = { { kind = "thrift", n = 32 }, { kind = "time", t = 2.8 }, { kind = "all_fall" } },
        camera = CAM,
    },
    {
        id = "kids_crane", name = "Clear the Line",
        brief = "The crane's string holds the tower up. Cut it under the toy bridge (Minis only) and the line is clear.",
        goal_word = "Start the train", win = "TOOT TOOT!", fail = "CRASH! THE TOWER'S STILL UP",
        tools = { "draw", "line", "ramp", "ball" }, sizes = { 1, 2 },
        start = { x = 22, y = -26.1, h = 0, a = math.pi },
        props = {
            { name = "toy garage", x0 = 5.5, x1 = 10.5, y0 = -31.6, y1 = -27.2, z0 = 0, z1 = 4 },
            { name = "toy bridge", x0 = 12, x1 = 14, y0 = -23.6, y1 = -18.8, z0 = 0.85, z1 = 1.25 },
            { name = "bridge block", x0 = 12, x1 = 14, y0 = -24.4, y1 = -23.6, z0 = 0, z1 = 0.85 },
            { name = "bridge block", x0 = 12, x1 = 14, y0 = -18.8, y1 = -18.0, z0 = 0, z1 = 0.85 },
        },
        traps = {
            TOWER,
            { kind = "string", id = "crane string", a = { 13, -23.3, 0.45 }, b = { 13, -19.1, 0.45 }, holds = "block tower" },
        },
        budget = { domino = 46, ball = 1 },
        challenges = { { kind = "thrift", n = 37 }, { kind = "time", t = 3.0 }, { kind = "all_fall" }, { kind = "avoid", box = { -14, 8, -24, -9 }, what = "train track" } },
        camera = { x = 10, y = -22, h = 1, yaw = -100, pitch = 44, dist = 56 },
    },
}
