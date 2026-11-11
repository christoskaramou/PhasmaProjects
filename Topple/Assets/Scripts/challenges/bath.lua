-- The Bathroom's challenges (room 6, unlocks the Switch): wind up the music box. Format: topple_challenges.lua.
-- The goal is a switch on the wooden bench beside the music box (bench top 9). From the normal on, a brass weight
-- hangs over it on a string tied down to a tripwire across the floor: cut the tripwire and the weight drops on the
-- switch. The bath is a roll-top: its rim (11.95 up) is straight and 0.56 wide only along the front (x -18 to 1.5);
-- round its corners only Minis stand on it. It drops 8.9 into the bath or 11.95 to the floor.
local GOAL = { x = 6, y = -8.4, h = 9 }
local WEIGHT = { kind = "weight", id = "weight", x = 4.72, y = -8.4, h = 15.5, r = 0.9 }
return {
    finish = { x = 4.72, y = -8.4, h = 9, a = 0 },               -- the End, under the weight, in front of the switch
    goal = GOAL,                                               -- the goal the End sets off
    {
        id = "bath_switch", name = "Wind It Up", icon = "tool_switch", unlock = "switch",
        brief = "The bench is too high to climb. Hit a switch on the floor and link it to a line on the bench.",
        goal_word = "Play the music box", win = "TING-A-LING!", fail = "NOT A NOTE",
        tools = { "draw", "line", "switch" },
        start = { x = 12, y = -14, h = 0, a = math.pi },
        budget = { domino = 16, switch = 1 },
        challenges = { { kind = "thrift", n = 14 }, { kind = "all_fall" } },
        camera = { x = 4, y = -10, h = 5, yaw = -70, pitch = 38, dist = 46 },
    },
    {
        id = "bath_weight", name = "Hang On",
        brief = "A weight hangs over the switch. Turn east and roll a ball through the tripwire that holds it.",
        goal_word = "Play the music box", win = "TING-A-LING!", fail = "THE WEIGHT HUNG ON",
        tools = { "draw", "line", "ball", "switch" },
        start = { x = -16, y = -14, h = 0, a = math.pi / 2 },
        traps = {
            WEIGHT,
            { kind = "string", id = "tripwire", a = { 15, -17, 0.45 }, b = { 15, -11, 0.45 }, holds = "weight" },
        },
        budget = { domino = 8, ball = 1, switch = 1 },
        challenges = { { kind = "thrift", n = 6 }, { kind = "time", t = 5.1 }, { kind = "without", gadget = "switch" } },
        camera = { x = 2, y = -12, h = 5, yaw = -80, pitch = 40, dist = 56 },
    },
    {
        id = "bath_rim", name = "Off the Rim",
        brief = "The floor by the bath is wet. Along the rim, Minis under the caddy and round the corner, off its far end, through the tripwire.",
        goal_word = "Play the music box", win = "TING-A-LING!", fail = "SPLASH!",
        tools = { "draw", "line", "ramp", "switch" }, sizes = { 1, 2 },
        start = { x = -8.5, y = 9.02, h = 11.95, a = 0 },
        props = {
            { name = "bath caddy", x0 = -6, x1 = -3.5, y0 = 8.6, y1 = 23.6, z0 = 12.85, z1 = 13.3 },
        },
        traps = {
            WEIGHT,
            { kind = "string", id = "tripwire", a = { 11.6, 5.5, 0.45 }, b = { 11.6, 12.5, 0.45 }, holds = "weight" },
            { kind = "zone", id = "wet floor", x0 = -26, x1 = 8.4, y0 = 4.4, y1 = 8.6 },
        },
        budget = { domino = 60, switch = 1 },
        challenges = { { kind = "thrift", n = 54 }, { kind = "without", gadget = "switch" }, { kind = "all_fall" }, { kind = "avoid", box = { -24, 7, 9.8, 22, 0, 11 }, what = "bath" } },
        camera = { x = 0, y = 4, h = 8, yaw = -80, pitch = 40, dist = 64 },
    },
}
