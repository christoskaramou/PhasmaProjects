-- The Study's challenges (room 7, unlocks Grow and the Large, Giant and Titan sizes): topple the big dictionary.
-- Format: topple_challenges.lua. The dictionary is the goal preset: Titan size, standing on the cabinet (top 15) at the
-- east end, so only a Giant (or a Titan) tips it. From the normal on, a plank stands at the desk's east end, tied
-- back by a string to a pin at the back of the desk (x -6, y 24.8 to 27): cut it and the plank falls across the 8 gap
-- and lands on the cabinet at x 10.4, knocking over what stands there. A line straight along the desk misses it.
local DICT = { id = "dict", x = 22.8, y = 23.6, h = 15, a = 0, size = 5, paint = "navy" }
local PLANK = { kind = "plank", id = "plank", x = -0.6, y = 22, h = 15, a = 0, len = 11, width = 3, art = "plank" }
local CAM = { x = 4, y = 20, h = 15, yaw = -90, pitch = 40, dist = 66 }
return {
    finish = { preset = "dict" },                                 -- the End is the dictionary itself
    goal = { preset = "dict", x = DICT.x, y = DICT.y, h = DICT.h }, -- the goal the End sets off
    {
        id = "study_grow", name = "Big Words", icon = "dominoes", unlock = "grow",
        brief = "Only a Giant can tip the dictionary. Grow your line from Standard up to Giant on the way.",
        goal_word = "Topple the dictionary", win = "THUD!", fail = "IT DIDN'T BUDGE",
        tools = { "draw", "line", "grow" }, sizes = { 2, 3, 4 },
        start = { x = 9, y = 23.6, h = 15, a = 0 },
        preset = { DICT },
        budget = { domino = 14 },
        challenges = { { kind = "thrift", n = 13 }, { kind = "all_fall" } },
        camera = { x = 16, y = 22, h = 15, yaw = -80, pitch = 34, dist = 34 },
    },
    {
        id = "study_plank", name = "Walk the Plank",
        brief = "Cut the plank's string at the back of the desk: it falls over the gap to the cabinet. Grow to Giant there.",
        goal_word = "Topple the dictionary", win = "THUD!", fail = "THE PLANK STAYED UP",
        tools = { "draw", "line", "grow" }, sizes = { 2, 3, 4 },
        start = { x = -12, y = 22, h = 15, a = 0 },
        preset = { DICT },
        traps = { PLANK, { kind = "string", id = "plank string", a = { -6, 24.8, 15.45 }, b = { -6, 27.0, 15.45 }, holds = "plank" } },
        budget = { domino = 27 },
        challenges = { { kind = "thrift", n = 25 }, { kind = "time", t = 1.5 }, { kind = "all_fall" } },
        camera = CAM,
    },
    {
        id = "study_ruler", name = "Mind the Ruler",
        brief = "Minis under the ruler, cut the string, over on the plank, round the inkwell, Giant to the dictionary.",
        goal_word = "Topple the dictionary", win = "THUD!", fail = "THE PLANK STAYED UP",
        tools = { "draw", "line", "grow", "ramp" }, sizes = { 1, 2, 3, 4 },
        start = { x = -26, y = 22, h = 15, a = 0 },
        preset = { DICT },
        props = {
            { name = "ruler", x0 = -16, x1 = -13, y0 = 19, y1 = 25, z0 = 15.85, z1 = 16.2 },
            { name = "book pile", x0 = -16, x1 = -13, y0 = 18.2, y1 = 19, z0 = 15, z1 = 15.85 },
            { name = "book pile", x0 = -16, x1 = -13, y0 = 25, y1 = 25.8, z0 = 15, z1 = 15.85 },
            { name = "inkwell", x0 = 13, x1 = 15.5, y0 = 21, y1 = 23.2, z0 = 15, z1 = 16.6 },
        },
        traps = { PLANK, { kind = "string", id = "plank string", a = { -6, 24.8, 15.45 }, b = { -6, 27.0, 15.45 }, holds = "plank" } },
        budget = { domino = 56 },
        challenges = { { kind = "thrift", n = 51 }, { kind = "time", t = 2.55 }, { kind = "all_fall" }, { kind = "avoid", box = { -28, 0, 14, 20, 14, 16 }, what = "front of the desk" } },
        camera = { x = -6, y = 20, h = 15, yaw = -90, pitch = 42, dist = 70 },
    },
}
