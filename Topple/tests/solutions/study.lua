-- One way to win each Study challenge (same order as Scripts/challenges/study.lua). See tests/challenge_test.lua.
local function paint() return "cream" end
-- A straight run of size k from `last` along its facing up to distance d (the first one spaced for the size change).
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
-- Where the plank comes down (x 10.4, y 22): a line from just beyond it, growing to Giant on a path to the dictionary.
local function cabinet(b, F, pts)
    assert(b:place_path(pts, paint, 15, F.SIZES[2], F.SIZES[4]), "the cabinet's line")
end
local STRAIGHT = { { 11.0, 22 }, { 13.0, 22.4 }, { 15.5, 23.4 }, { 18.0, 23.6 }, { 21.4, 23.6 } }
local ROUND = { { 11.0, 22 }, { 11.8, 23.0 }, { 13.0, 23.9 }, { 15.6, 24.0 }, { 18.0, 23.7 }, { 21.4, 23.6 } }
return {
    function(b, F)
        b:place_line(9.62, 23.6, 21.6, 23.6, paint, 15, F.SIZES[2], F.SIZES[4])
    end,
    {
        -- Swerve to the back of the desk across the plank's string (the trap-avoiding step); without it, straight along
        -- the desk to its end, the plank stays up and the gap stays open.
        solve = function(b, F)
            local p = b:starter()
            assert(b:place_path({ { p.x + F.SPACING, 22 }, { -10, 22.3 }, { -8.2, 23.6 }, { -6.8, 25.4 }, { -5.5, 25.9 } }, paint, 15), "swerve")
            cabinet(b, F, STRAIGHT)
        end,
        without = function(b, F)
            run(b, F, b:starter(), -1.4 - -12)
            cabinet(b, F, STRAIGHT)
        end,
        misses = { time = function(b, F)
            local p = b:starter()
            assert(b:place_path({ { p.x + F.SPACING, 22 }, { -10, 20.6 }, { -8, 20.4 }, { -7.4, 22.2 }, { -6.9, 24.4 }, { -6.2, 25.6 }, { -5.5, 25.9 } }, paint, 15), "s-curve")
            cabinet(b, F, STRAIGHT)
        end },
    },
    {
        -- Standards to the ruler, Minis under it, then swerving back across the string at x -6; round the inkwell on
        -- the cabinet. Without the swerve (straight on to the desk's end) the plank stays up.
        solve = function(b, F)
            local p = run(b, F, b:starter(), -16.6 - -26)
            p = run(b, F, p, -12.6 - p.x, F.SIZES[1])
            assert(b:place_path({ { p.x + F.SPACING * (p.s + 1) / 2, 22 }, { -11, 22.3 }, { -9, 23.5 }, { -7.2, 25.3 }, { -5.5, 25.9 } }, paint, 15), "swerve")
            b:erase_at(-5.53, 25.89, 15, 0.2)          -- (the swerve's last one stands past the string: not needed)
            cabinet(b, F, ROUND)
        end,
        misses = { time = function(b, F)
            local p = assert(b:place_path({ { -25.38, 22 }, { -23, 19.6 }, { -20.5, 19.8 }, { -19, 22 }, { -17.8, 22 }, { -16.6, 22 } }, paint, 15), "s-curve")
            p = run(b, F, p, -12.6 - p.x, F.SIZES[1])
            assert(b:place_path({ { p.x + F.SPACING * (p.s + 1) / 2, 22 }, { -11, 22.3 }, { -9, 23.5 }, { -7.2, 25.3 }, { -5.5, 25.9 } }, paint, 15), "swerve")
            b:erase_at(-5.53, 25.89, 15, 0.2)
            cabinet(b, F, ROUND)
        end },
        without = function(b, F)
            local p = run(b, F, b:starter(), -16.6 - -26)
            p = run(b, F, p, -12.6 - p.x, F.SIZES[1])
            run(b, F, p, -1.4 - p.x)
            cabinet(b, F, ROUND)
        end,
    },
}
