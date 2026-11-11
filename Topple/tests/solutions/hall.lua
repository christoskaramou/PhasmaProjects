-- One way to win each Hallway challenge (same order as Scripts/challenges/hall.lua). See tests/challenge_test.lua.
local function paint() return "cream" end
return {
    function(b)
        b:place_path({ { -11.38, 29 }, { 2, 29 }, { 7.5, 33 }, { 10.6, 39 }, { 12.2, 43.6 } }, paint, 0)
    end,
    {
        -- North under the bench (the trap-avoiding step), then round the coat stand to the door.
        solve = function(b)
            b:place_path({ { -13.6, -21.38 }, { -13.6, 18 }, { -10, 27 }, { 2, 30 }, { 9, 36 }, { 12.2, 43.6 } }, paint, 0)
        end,
        -- The same, but beside the bench across the mopped floor.
        without = function(b)
            b:place_path({ { -13.6, -21.38 }, { -13.6, -14 }, { -7, -8 }, { -7, 18 }, { -10, 27 }, { 2, 30 }, { 9, 36 }, { 12.2, 43.6 } }, paint, 0)
        end,
        -- The long way: east across the hall before turning for the door (too slow for the clock).
        misses = { time = function(b)
            b:place_path({ { -13.6, -21.38 }, { -13.6, 18 }, { -4, 16 }, { 8, 16 }, { 12.5, 20 }, { 10, 26 }, { 8.6, 30 }, { 9, 36 }, { 12.2, 43.6 } }, paint, 0)
        end },
    },
    {
        solve = function(b)
            b:place_path({ { 4, -11.38 }, { 2.5, -8 }, { -2, -7.5 }, { -8, -11.5 }, { -12.8, -11 }, { -13.4, -6 }, { -13.4, 16 }, { -9, 27 }, { 2, 30.5 }, { 9, 36 }, { 12.2, 43.6 } }, paint, 0.12)
        end,
        without = function(b)
            b:place_path({ { 4, -11.38 }, { 4, 30 }, { 9, 36 }, { 12.2, 43.6 } }, paint, 0.12)
        end,
        misses = { time = function(b)
            b:place_path({ { 4, -11.38 }, { 2.5, -8 }, { -2, -7.5 }, { -8, -11.5 }, { -12.8, -11 }, { -13.4, -6 }, { -13.4, 16 }, { -4, 16 }, { 8, 16 }, { 12.5, 20 }, { 10, 26 }, { 8.6, 30 }, { 9, 36 }, { 12.2, 43.6 } }, paint, 0.12)
        end },
    },
}
