-- One way to win each Attic challenge (same order as Scripts/challenges/attic.lua). See tests/challenge_test.lua.
local function paint() return "cream" end
-- A straight run from `last` along its facing up to distance d.
local function run(b, F, last, d)
    local c, s = math.cos(last.a), math.sin(last.a)
    local p, gone = last, 0
    while gone + F.SPACING <= d + 1e-9 do
        gone = gone + F.SPACING
        p = assert(b:place(last.x + c * gone, last.y + s * gone, last.a, last.z, "cream"), "run: no room")
    end
    return p
end
-- A swing hanging at (x, y) swinging along a, and a line from `last` that ends just short of its latch.
local function swing(b, F, last, x, y, a)
    assert(b:place_swing(x, y, 0, a), "swing")
    local lx = F.swing_latch(x, y, a, F.SWING.len, "stand")
    return run(b, F, last, (lx - 0.85) - last.x)
end
return {
    function(b, F)
        swing(b, F, b:starter(), 37.5, -8, 0)
    end,
    {
        -- The swing's bob cuts the iron's string at the top of its swing (the trap-avoiding step); without it, a line
        -- under the string leaves it whole.
        solve = function(b, F) swing(b, F, b:starter(), 16.5, -8, 0) end,
        without = function(b, F) run(b, F, b:starter(), 7.0) end,
    },
    {
        -- On the trunk, a swerve across the plank's string at its back; the plank falls off the trunk's end onto the
        -- floor line, which runs round the crates' west side and along to the swing's latch; the bob cuts the iron's
        -- string. Without the way round, the floor line runs straight at the latch through the crates.
        solve = function(b, F)
            local p = b:starter()
            assert(b:place_path({ { p.x + F.SPACING, 22 }, { -28, 22.6 }, { -26.6, 25.8 }, { -25.6, 27.4 }, { -24.6, 27.6 } }, paint, 11), "swerve")
            assert(b:place_path({ { -12.2, 24 }, { -11.2, 23.8 }, { -10.5, 23.1 }, { -10.2, 22.0 }, { -10.2, 13.6 }, { -9.9, 12.2 }, { -9.0, 11.2 }, { -7.0, 11 } }, paint, 0), "round")
            assert(b:place_swing(-1.5, 11, 0, 0), "swing")
        end,
        misses = { time = function(b, F)
            local p = b:starter()
            assert(b:place_path({ { p.x + F.SPACING, 22 }, { -28, 22.6 }, { -26.6, 25.8 }, { -25.6, 27.4 }, { -24.6, 27.6 } }, paint, 11), "swerve")
            assert(b:place_path({ { -12.2, 24 }, { -11.2, 23.8 }, { -10.5, 23.1 }, { -10.6, 21.4 }, { -12.4, 19.6 }, { -14.2, 17.4 }, { -13, 15 }, { -10.8, 13.8 }, { -9.9, 12.2 }, { -9.0, 11.2 }, { -7.0, 11 } }, paint, 0), "wide round")
            assert(b:place_swing(-1.5, 11, 0, 0), "swing")
        end },
        without = function(b, F)
            local p = b:starter()
            assert(b:place_path({ { p.x + F.SPACING, 22 }, { -28, 22.6 }, { -26.6, 25.8 }, { -25.6, 27.4 }, { -24.6, 27.6 } }, paint, 11), "swerve")
            assert(b:place_path({ { -12.2, 24 }, { -11.4, 23.2 }, { -9.8, 20.9 }, { -9.4, 20.3 } }, paint, 0), "straight")
            assert(b:place_path({ { -8.0, 12.8 }, { -7.0, 11 } }, paint, 0), "beyond the crates")
            assert(b:place_swing(-1.5, 11, 0, 0), "swing")
        end,
    },
}
