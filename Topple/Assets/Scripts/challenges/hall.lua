-- The Hallway's challenges (room 1, unlocks DRAW): ring the doorbell by the front door. Format: topple_challenges.lua.
-- Its trap is the gap under the shoe bench: the shelf is high enough for a Standard to stand and fall under it, so when
-- the floor beside the bench is closed (the mopped strip), under the bench is the only way north.
local MOPPED = { kind = "zone", id = "mopped floor", x0 = -9.6, x1 = 17.4, y0 = -3, y1 = 3 }
return {
    finish = { x = 12.08, y = 43.25, h = 0, a = 1.25 },          -- the End: a locked domino in front of the bell
    goal = { x = 12.2, y = 44.3, h = 0 },                      -- the goal the End sets off
    {
        id = "doorbell", name = "Someone's at the Door", icon = "bell", unlock = "draw",
        brief = "Draw a path of dominoes round the coat stand to the bell by the door.",
        goal_word = "Ring the bell", win = "DING-DONG!", fail = "NOBODY HEARD IT",
        tools = { "draw" },
        start = { x = -12, y = 29, h = 0, a = 0 },
        budget = { domino = 78 },
        challenges = { { kind = "thrift", n = 64 }, { kind = "all_fall" } },
        camera = { x = 0, y = 36, h = 1, yaw = -70, pitch = 42, dist = 62 },
    },
    {
        id = "hall_bench", name = "Under the Bench",
        brief = "The floor's just been mopped. Take the chain under the shoe bench.",
        goal_word = "Ring the bell", win = "DING-DONG!", fail = "STUCK IN THE HALL",
        tools = { "draw" },
        start = { x = -13.6, y = -22, h = 0, a = math.pi / 2 },
        traps = { MOPPED },
        budget = { domino = 167 },
        challenges = { { kind = "thrift", n = 148 }, { kind = "time", t = 6.8 }, { kind = "all_fall" } },
        camera = { x = -4, y = 8, h = 1, yaw = -62, pitch = 50, dist = 104 },
    },
    {
        id = "hall_wrong_way", name = "Wrong Side of the Hall",
        brief = "You start facing the mopped floor. Find the one way round, with not a domino to spare.",
        goal_word = "Ring the bell", win = "DING-DONG!", fail = "STUCK IN THE HALL",
        tools = { "draw" },
        start = { x = 4, y = -12, h = 0.12, a = math.pi / 2 },
        traps = { MOPPED },
        budget = { domino = 172 },
        challenges = { { kind = "thrift", n = 155 }, { kind = "time", t = 7.1 }, { kind = "all_fall" }, { kind = "avoid", box = { -6, 0, 31, 35 }, what = "end of the runner" } },
        camera = { x = -2, y = 6, h = 1, yaw = -62, pitch = 52, dist = 108 },
    },
}
