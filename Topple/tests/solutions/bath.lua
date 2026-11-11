-- One way to win each Bathroom challenge (same order as Scripts/challenges/bath.lua). See tests/challenge_test.lua.
local GAP = 1.35         -- the gap before a ball that gives it the hardest hit
-- A straight run of size k from `last` along its facing up to distance d (the first one spaced for the size change).
local function run(b, F, last, d, k)
    k = k or 1
    local step = F.SPACING * (last.s + k) / 2
    local c, s = math.cos(last.a), math.sin(last.a)
    local p, gone, x0, y0 = last, 0, last.x, last.y
    while gone + step <= d + 1e-9 do
        gone = gone + step
        p = assert(b:place(x0 + c * gone, y0 + s * gone, last.a, last.z, "cream", k), "run: no room")
        step = F.SPACING * k
    end
    return p
end
-- The line along the bench to the goal switch, started by a switch the floor chain hits.
local function bench(b, F, sw)
    local first = assert(b:place(-2.1, -8.4, 0, 9, "cream"), "the bench's first domino")
    run(b, F, first, 6.2)                       -- (to 4.1: the End stands at 4.72)
    b:link_switch(sw, first.id)
end
-- From the start (facing north) a quick turn east, then the ball along y = lane: through the tripwire at x 15, or,
-- without the turn onto its lane, south of the tripwire's end.
local function roll(b, F, lane, gap)
    local p = b:starter()
    p = assert(b:place_path({ { p.x, p.y + F.SPACING }, { p.x + 0.5, lane - 0.3 }, { p.x + 1.4, lane }, { p.x + 2.4, lane } },
        function() return "cream" end, 0), "turn")
    assert(b:place_ball(p.x + math.cos(p.a) * (gap or GAP), p.y + math.sin(p.a) * (gap or GAP), 0), "ball")
end
-- Round the rim's front-right corner on Minis (x, y, facing; each on its own rim tile in rooms/bath.lua), the last
-- one turned out to dive off the bath's east end onto the floor at about (9.4, 16.1).
local CORNER = {
    { 1.515, 9.045, 0.1034 },
    { 1.923, 9.1, 0.1609 },
    { 2.329, 9.176, 0.2066 },
    { 2.73, 9.274, 0.2595 },
    { 3.126, 9.39, 0.3234 },
    { 3.514, 9.531, 0.365 },
    { 3.896, 9.688, 0.4367 },
    { 4.263, 9.877, 0.4967 },
    { 4.621, 10.083, 0.5494 },
    { 4.968, 10.307, 0.6079 },
    { 5.299, 10.554, 0.6631 },
    { 5.617, 10.818, 0.7175 },
    { 5.919, 11.099, 0.7858 },
    { 6.201, 11.401, 0.8493 },
    { 6.465, 11.719, 0.8968 },
    { 6.711, 12.051, 0.9609 },
    { 6.938, 12.396, 1.028 },
    { 7.142, 12.755, 1.0795 },
    { 7.329, 13.123, 1.1292 },
    { 7.491, 13.503, 1.1903 },
    { 7.637, 13.889, 1.2563 },
    { 7.755, 14.284, 1.3156 },
    { 7.843, 14.688, 1.3816 },
    { 7.909, 15.095, 1.4378 },
    { 8.05, 15.51, 0.384 }
}
-- Along the rim (straight to x 1.5), on Minis under the caddy, round the corner on Minis, off the east end, and a
-- floor line south through the tripwire at x 11.6. Without the corner the chain ends on the rim.
local function rim(b, F, dive)
    local p = run(b, F, b:starter(), 2.0)
    p = run(b, F, p, -2.9 - p.x, F.SIZES[1])
    p = run(b, F, p, 1.05 - p.x)
    if not dive then return end
    for i, m in ipairs(CORNER) do assert(b:place(m[1], m[2], m[3], p.z, "cream", F.SIZES[1]), "corner Mini " .. i) end
    local d = CORNER[#CORNER]
    local throw = F.dive_throw(p.z, F.SIZES[1])
    local q = assert(b:place(d[1] + math.cos(d[3]) * throw, d[2] + math.sin(d[3]) * throw, d[3], 0, "cream"), "where the diver lands")
    assert(b:place_path({ { q.x + math.cos(q.a) * F.SPACING, q.y + math.sin(q.a) * F.SPACING }, { 10.5, 16.1 }, { 11.3, 15.2 }, { 11.7, 13.6 }, { 11.9, 11.8 } },
        function() return "cream" end, 0), "floor line")
end
return {
    function(b, F)
        local sw = assert(b:place_switch(11.15, -14, 0), "the switch, right in front of the first domino")
        bench(b, F, sw)
    end,
    { solve = function(b, F) roll(b, F, -12.4) end, misses = { time = function(b, F) roll(b, F, -12.4, 1.3) end }, without = function(b, F)
        local p = b:starter()       -- (straight on north: the ball rolls into the bench)
        assert(b:place_ball(p.x, p.y + GAP, 0), "ball")
    end },
    { solve = function(b, F) rim(b, F, true) end, without = function(b, F) rim(b, F, false) end },
}
