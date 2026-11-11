-- One way to win each Kids' Room challenge (same order as Scripts/challenges/kids.lua). See tests/challenge_test.lua.
local function paint() return "cream" end
local GAP = 1.35         -- the gap before a ball that gives it the hardest hit
-- A straight run of dominoes of size k from `last` along its facing up to (and including) distance d, then the last one.
local function run(b, F, last, d, k)
    k = k or 1
    local step = F.SPACING * (last.s + k) / 2
    local c, s = math.cos(last.a), math.sin(last.a)
    local p, gone = last, 0
    while gone + step <= d + 1e-9 do
        gone = gone + step
        p = assert(b:place(last.x + c * gone, last.y + s * gone, last.a, last.z, "cream", k), "run: no room")
        step = F.SPACING * k
    end
    return p
end
-- The ball in front of `last`, the hardest hit.
local function ball(b, last, gap)
    gap = gap or GAP
    return assert(b:place_ball(last.x + math.cos(last.a) * gap, last.y + math.sin(last.a) * gap, last.z), "ball")
end
-- Carry on from `last` with size k along a path through pts.
local function path(b, F, last, pts, k, h)
    k = k or 1
    local d = F.SPACING * (last.s + k) / 2
    local all = { { last.x + math.cos(last.a) * d, last.y + math.sin(last.a) * d } }
    for _, p in ipairs(pts) do all[#all + 1] = p end
    return assert(b:place_path(all, paint, h or last.z, k), "path")
end
-- The way south round the tower: a curve down to the lane y = -29.2, the ball west along it, and the catch: a line
-- that takes the ball's hit and climbs back up to the goal (the trap-avoiding step of the normal).
local function south(b, F, gap)
    local p = path(b, F, b:starter(), { { 19.5, -26.3 }, { 17.5, -27.2 }, { 16.0, -28.4 }, { 14.6, -29.1 }, { 14.0, -29.25 }, { 13.4, -29.25 } })
    p = run(b, F, p, 0.0)
    ball(b, p, gap)
    assert(b:place_path({ { 2.0, -29.25 }, { -1.6, -29.25 }, { -3.0, -29.25 }, { -4.6, -28.9 }, { -5.9, -28.3 }, { -6.8, -27.6 } }, paint, 0.1), "catch")
    -- (the End stands at -7.0, -27.05 facing north: the catch runs into it)
end
-- Straight west: the ball's lane runs through where the tower stands.
local function straight(b, F)
    ball(b, run(b, F, b:starter(), 0.7))
end
-- The hard one's detour: north, west under the toy bridge on Minis (cutting the crane's string), back down to the lane.
local function detour(b, F, gap)
    local p = path(b, F, b:starter(), { { 19.6, -26.0 }, { 17.6, -25.2 }, { 16.4, -23.8 }, { 15.8, -22.4 }, { 15.2, -21.4 }, { 14.6, -21.2 } })
    local m = F.SIZES[1]
    -- (west on Minis, under the bridge's plank from x 14 to 12)
    p = assert(b:place(p.x - F.SPACING * (p.s + m) / 2, -21.2, math.pi, 0, "cream", m), "first Mini")
    p = run(b, F, p, 14.4 - 11.0, m)
    p = path(b, F, p, { { 10.0, -21.7 }, { 9.8, -22.8 }, { 9.6, -24.2 }, { 9.2, -25.5 }, { 8.6, -26.0 }, { 8.0, -26.1 }, { 7.4, -26.1 }, { 6.8, -26.1 } }, 1, 0.1)   -- (onto the play mat)
    ball(b, p, gap)
end
return {
    function(b, F)
        ball(b, run(b, F, b:starter(), 0.7))
    end,
    { solve = south, without = straight, misses = { time = function(b, F) south(b, F, 1.25) end } },
    { solve = detour, without = straight, misses = { time = function(b, F) detour(b, F, 1.2) end } },
}
