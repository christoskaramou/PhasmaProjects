-- The Kitchen's challenges (room 3, unlocks RAMP): pop the toast. Format: topple_challenges.lua.
-- The toaster stands on the counter (18 high). A ramp climbs from the kitchen table, or all the way from the floor;
-- the counter's front edge is the drop to watch, and a fragile stack of plates leaves only a strip along it.
local PLATES = { kind = "support", id = "stack of plates", x0 = -6.5, x1 = -1.5, y0 = 20.3, y1 = 21.7, z0 = 18, z1 = 21 }
return {
    finish = { x = -2.7, y = 22.46, h = 18, a = math.pi },       -- the End, east of the toaster switch (level 1 has its own)
    goal = { x = -4, y = 22.4, h = 18 },                       -- the goal the End sets off
    {
        id = "toaster", name = "Breakfast", icon = "tool_ramp", unlock = "ramp",
        finish = { x = -4, y = 21.46, h = 18, a = math.pi / 2 },     -- (its own End: this level comes in from the south)
        brief = "Bridge a ramp from the table up to the counter, then line up to the toaster.",
        goal_word = "Pop the toast", win = "TOAST IS UP!", fail = "STILL HUNGRY",
        tools = { "draw", "line", "ramp" },
        start = { x = -4, y = -10, h = 15, a = math.pi / 2 },
        budget = { domino = 72, ramp = 1 },
        challenges = { { kind = "thrift", n = 59 }, { kind = "all_fall" } },
        camera = { x = -4, y = 6, h = 15, yaw = -40, pitch = 30, dist = 58 },
    },
    {
        id = "kitchen_plates", name = "Mind the Plates",
        brief = "A stack of plates fills the counter. Squeeze past it along the edge.",
        goal_word = "Pop the toast", win = "TOAST IS UP!", fail = "CRASH!",
        tools = { "draw", "line", "ramp" },
        start = { x = -4, y = -10, h = 15, a = math.pi / 2 },
        traps = { PLATES },
        budget = { domino = 79, ramp = 1 },
        challenges = { { kind = "thrift", n = 69 }, { kind = "time", t = 3.3 }, { kind = "via", box = { 4, 10, 17, 29, 17, 19 }, what = "oven end of the counter" } },
        camera = { x = -3, y = 10, h = 16, yaw = -30, pitch = 38, dist = 46 },
    },
    {
        id = "kitchen_long", name = "The Long Way Up",
        brief = "Start under a chair. Climb all the way to the counter, and don't touch the plates.",
        goal_word = "Pop the toast", win = "TOAST IS UP!", fail = "STILL HUNGRY",
        tools = { "draw", "line", "ramp" },
        start = { x = -12, y = -23.5, h = 0, a = math.pi },
        traps = { PLATES },
        budget = { domino = 175, ramp = 1 },
        challenges = { { kind = "thrift", n = 157 }, { kind = "time", t = 7.3 }, { kind = "all_fall" }, { kind = "avoid", box = { -19, 11, -18, -1, 14, 16 }, what = "kitchen table" } },
        camera = { x = -16, y = -2, h = 8, yaw = -60, pitch = 34, dist = 80 },
    },
}
