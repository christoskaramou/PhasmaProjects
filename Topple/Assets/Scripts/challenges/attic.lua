-- The Attic's challenges (room 8, unlocks the Swing, Field and Spiral): throw the master light switch. Format:
-- topple_challenges.lua. The goal is a switch on the floor in front of the old switch box on the right gable. A swing's
-- bob reaches 4.6 past where it hangs and, near the end of its swing, rises to about 2: high enough to cut a string a
-- Standard cannot reach. From the normal on, an old flat iron hangs over the goal on a string stretched 1.6 up between
-- two posts: cut it and the iron drops on the switch.
local GOAL = { x = 41.6, y = -8, h = 0 }
local IRON = { kind = "weight", id = "iron", x = 40.65, y = -8, h = 6, r = 1.0 }
-- Cameras sit under the roof (14 at the knee walls, 58 at the ridge along y = 0), below the collar ties (42 to 44), at
-- the gable end looking along the room: the boards run east-west.
local CAM = { x = 34, y = -8, h = 1, yaw = -160, pitch = 50, dist = 30 }
return {
    finish = { x = 40.65, y = -8, h = 0, a = 0 },                -- the End, under the iron, in front of the switch
    goal = GOAL,                                               -- the goal the End sets off
    {
        id = "attic_swing", name = "Lights On", icon = "tool_swing", unlock = "swing",
        brief = "Your dominoes run out short of the switch. Hang a swing: tip its latch and the bob does the rest.",
        goal_word = "Throw the switch", win = "LET THERE BE LIGHT!", fail = "STILL IN THE DARK",
        tools = { "draw", "line", "swing" },
        start = { x = 28, y = -8, h = 0, a = 0 },
        budget = { domino = 9, swing = 1 },
        challenges = { { kind = "thrift", n = 8 }, { kind = "all_fall" } },
        camera = CAM,
    },
    {
        id = "attic_iron", name = "Iron Out",
        brief = "The iron's string is too high for a domino. Swing for it, and the iron drops on the switch.",
        goal_word = "Throw the switch", win = "LET THERE BE LIGHT!", fail = "THE IRON HUNG ON",
        tools = { "draw", "line", "swing", "field", "spiral" },
        start = { x = 4, y = -8, h = 0, a = 0 },
        traps = { IRON, { kind = "string", id = "iron string", a = { 20, -11, 1.6 }, b = { 20, -5, 1.6 }, holds = "iron" } },
        budget = { domino = 14, swing = 1 },
        challenges = { { kind = "thrift", n = 13 }, { kind = "all_fall" }, { kind = "avoid", box = { 13, 27, 5, 25 }, what = "rocking chair" } },
        camera = { x = 26, y = -8, h = 1, yaw = 64, pitch = 30, dist = 42 },
    },
    {
        id = "attic_finale", name = "Lights Out, Lights On",
        brief = "Cut the plank's string on the trunk, run round the fragile crates, and swing for the iron's string.",
        goal_word = "Throw the switch", win = "LET THERE BE LIGHT!", fail = "STILL IN THE DARK",
        tools = { "draw", "line", "swing", "field", "spiral", "ramp" }, sizes = { 1, 2 },
        start = { x = -30, y = 22, h = 11, a = 0 },
        traps = {
            IRON,
            { kind = "string", id = "iron string", a = { 2, 8, 1.6 }, b = { 2, 14, 1.6 }, holds = "iron" },
            { kind = "plank", id = "plank", x = -21.4, y = 24, h = 11, a = 0, len = 14, width = 3 },
            { kind = "string", id = "plank string", a = { -25, 26.6, 11.45 }, b = { -25, 28.6, 11.45 }, holds = "plank" },
            { kind = "support", id = "crates", x0 = -9, x1 = -5, y0 = 14, y1 = 20, z0 = 0, z1 = 9 },
        },
        budget = { domino = 48, swing = 1 },
        challenges = { { kind = "thrift", n = 43 }, { kind = "time", t = 3.0 }, { kind = "all_fall" }, { kind = "avoid", box = { 13, 27, 5, 25 }, what = "rocking chair" } },
        camera = { x = 6, y = 20, h = 1, yaw = -152, pitch = 32, dist = 70 },
    },
}
