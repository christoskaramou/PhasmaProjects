-- The Living Room's challenges (room 2, unlocks LINE): turn on the TV. Format: topple_challenges.lua.
-- Its trap is a fragile house of cards on the coffee table: a domino falling against it brings it down and stops there.
-- From the table the chain carries on by diving off its edge onto the rug.
local TV = { { name = "TV cabinet", x0 = 33.4, x1 = 39.4, y0 = 2, y1 = 22, z0 = 0, z1 = 6 } }
return {
    finish = { x = 31.46, y = 12, h = 0, a = 0 },                -- the End: a locked domino in front of the TV switch
    goal = { x = 32.4, y = 12, h = 0 },                        -- the goal the End sets off
    {
        id = "tv", name = "Movie Night", icon = "dominoes", unlock = "line",
        brief = "One long straight line across the room turns on the TV. Press, drag, let go.",
        goal_word = "Turn on the TV", win = "SHOWTIME!", fail = "THE SCREEN STAYED DARK",
        tools = { "draw", "line" },
        start = { x = -20, y = 12, h = 0.12, a = 0 },
        props = TV,
        budget = { domino = 124 },
        challenges = { { kind = "thrift", n = 103 }, { kind = "all_fall" } },
        camera = { x = 6, y = 12, h = 1, yaw = -90, pitch = 34, dist = 70 },
    },
    {
        id = "tv_cards", name = "House of Cards",
        brief = "Steer round the house of cards, off the table's edge and on to the TV.",
        goal_word = "Turn on the TV", win = "SHOWTIME!", fail = "THE CARDS CAME DOWN",
        tools = { "draw", "line" },
        start = { x = -22, y = 1, h = 8.8, a = 0 },
        props = TV,
        traps = { { kind = "support", id = "house of cards", x0 = -15, x1 = -12, y0 = -1.5, y1 = 3.5, z0 = 8.8, z1 = 11.8 } },
        budget = { domino = 119 },
        challenges = { { kind = "thrift", n = 105 }, { kind = "time", t = 5.3 }, { kind = "via", box = { -2, 6, 11, 16.5 }, what = "front of the sofa" } },
        camera = { x = 6, y = 4, h = 4, yaw = -100, pitch = 34, dist = 70 },
    },
    {
        id = "tv_slalom", name = "Card Slalom",
        brief = "Weave between two houses of cards, and mind the third one on the rug when you jump.",
        goal_word = "Turn on the TV", win = "SHOWTIME!", fail = "THE CARDS CAME DOWN",
        tools = { "draw", "line" },
        start = { x = -22, y = -1.5, h = 8.8, a = 0 },
        props = TV,
        traps = {
            { kind = "support", id = "house of cards", x0 = -18, x1 = -15, y0 = -4.6, y1 = 2, z0 = 8.8, z1 = 11.8 },
            { kind = "support", id = "house of cards 2", x0 = -10, x1 = -7, y0 = -0.6, y1 = 6.6, z0 = 8.8, z1 = 11.8 },
            { kind = "support", id = "house of cards 3", x0 = -0.5, x1 = 2.5, y0 = -4.5, y1 = -0.5, z0 = 0.12, z1 = 3.12 },
        },
        budget = { domino = 121 },
        challenges = { { kind = "thrift", n = 108 }, { kind = "time", t = 5.4 }, { kind = "all_fall" }, { kind = "avoid", box = { 10, 38, -26, -12 }, what = "pile of books" } },
        camera = { x = 4, y = 2, h = 4, yaw = -100, pitch = 38, dist = 66 },
    },
}
