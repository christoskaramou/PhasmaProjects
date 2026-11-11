-- The Dining Room's challenges (room 4, unlocks the Mini): start the record player. Format: topple_challenges.lua.
-- A cutting board laid across two jam jars on the sideboard leaves a gap 0.8 high: only a Mini stands and falls under
-- it. The glass tower on the table is fragile: knock it and the chain ends there.
local BOARD = {
    { name = "jam jar", x0 = -3, x1 = -2, y0 = 22.6, y1 = 23.6, z0 = 17, z1 = 17.8 },
    { name = "jam jar", x0 = -3, x1 = -2, y0 = 30.6, y1 = 31.6, z0 = 17, z1 = 17.8 },
    { name = "cutting board", x0 = -3.5, x1 = -1.5, y0 = 22.6, y1 = 31.6, z0 = 17.8, z1 = 18.1 },
}
local TOWER = { kind = "support", id = "fragile glass tower", x0 = -19, x1 = -13, y0 = -5, y1 = 1, z0 = 15, z1 = 20.6 }
local GOAL = { x = 4.9, y = 25.5, h = 17 }
return {
    finish = { x = 4.02, y = 25.5, h = 17, a = 0 },              -- the End: a locked domino in front of the record player switch
    goal = GOAL,                                               -- the goal the End sets off
    {
        id = "record", name = "Drop the Needle", icon = "dominoes", unlock = "mini",
        brief = "Only a Mini fits under the cutting board. Change size with - and =.",
        goal_word = "Play the record", win = "THE MUSIC'S ON!", fail = "SILENCE",
        tools = { "draw", "line" }, sizes = { 1, 2 },
        start = { x = -15, y = 25.5, h = 17, a = 0 },
        props = BOARD,
        budget = { domino = 49 },
        challenges = { { kind = "thrift", n = 40 }, { kind = "all_fall" } },
        camera = { x = -4, y = 26, h = 17, yaw = -90, pitch = 36, dist = 40 },
    },
    {
        id = "dining_glasses", name = "Mind the Glasses",
        brief = "Round the glass tower, up a ramp to the sideboard, and Minis under the board.",
        goal_word = "Play the record", win = "THE MUSIC'S ON!", fail = "SMASH!",
        tools = { "draw", "line", "ramp" }, sizes = { 1, 2 },
        start = { x = -16, y = -10, h = 15, a = math.pi / 2 },
        props = BOARD,
        traps = { TOWER },
        budget = { domino = 106, ramp = 1 },
        challenges = { { kind = "thrift", n = 94 }, { kind = "time", t = 4.2 }, { kind = "via", box = { -4, 6, -10, 0, 14, 16 }, what = "middle of the table" } },
        camera = { x = -8, y = 8, h = 15, yaw = -70, pitch = 42, dist = 70 },
    },
    {
        id = "dining_turn", name = "About Turn",
        brief = "You start facing the glasses. Turn round tight, then all the way to the record player.",
        goal_word = "Play the record", win = "THE MUSIC'S ON!", fail = "SMASH!",
        tools = { "draw", "line", "ramp" }, sizes = { 1, 2 },
        start = { x = -12.25, y = -2, h = 15, a = math.pi },
        props = BOARD,
        traps = { TOWER },
        budget = { domino = 85, ramp = 1 },
        challenges = { { kind = "thrift", n = 76 }, { kind = "time", t = 3.4 }, { kind = "all_fall" }, { kind = "avoid", box = { -4, 6, -10, 0, 14, 16 }, what = "middle of the table" } },
        camera = { x = -8, y = 8, h = 15, yaw = -70, pitch = 42, dist = 70 },
    },
}
