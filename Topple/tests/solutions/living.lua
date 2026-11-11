-- One way to win each Living Room challenge (same order as Scripts/challenges/living.lua). See tests/challenge_test.lua.
local function paint() return "cream" end
-- From where a domino diving off the coffee table's east edge lands, across the rug to the TV.
local function to_tv(b, y)
    b:place_line(0.6, y, 31.7, 12, paint, 0.12)
end
-- From the table's landing north past the front of the sofa, then east to the TV.
local function by_sofa(b, y)
    b:place_path({ { 0.6, y }, { 1.5, 8 }, { 3, 13.5 }, { 8, 16.5 }, { 14, 18.5 }, { 20, 16.5 }, { 25, 12.3 }, { 31.7, 12 } }, paint, 0.12)
end
return {
    function(b)
        b:place_line(-19.38, 12, 31.7, 12, paint, 0.12)
    end,
    {
        -- Round the south of the cards (the trap-avoiding step), then off the edge.
        solve = function(b)
            b:place_path({ { -21.38, 1 }, { -17.5, 0.5 }, { -13.5, -3.3 }, { -9.5, 0 }, { -1.3, 1 } }, paint, 8.8)
            to_tv(b, 1)
        end,
        without = function(b)
            b:place_line(-21.38, 1, -1.3, 1, paint, 8.8)
            to_tv(b, 1)
        end,
        objectives = { via = function(b)
            b:place_path({ { -21.38, 1 }, { -17.5, 0.5 }, { -13.5, -3.3 }, { -9.5, 0 }, { -1.3, 1 } }, paint, 8.8)
            by_sofa(b, 1)
        end },
    },
    {
        -- North of the first house, south of the second, then back north to jump clear of the third.
        solve = function(b)
            b:place_path({ { -21.38, -1.5 }, { -19.5, 1.5 }, { -16.5, 4 }, { -13, 2.5 }, { -11, -2.6 }, { -6, -2.4 }, { -3.5, 0.6 }, { -1.1, 1.2 } }, paint, 8.8)
            to_tv(b, 1.2)
        end,
        without = function(b)
            b:place_path({ { -21.38, -1.5 }, { -19.5, 1.5 }, { -16.5, 4 }, { -13, 2.5 }, { -11, -2.6 }, { -6, -2.4 }, { -1.3, -2.4 } }, paint, 8.8)
            to_tv(b, -2.4)
        end,
        misses = { time = function(b)
            b:place_path({ { -21.38, -1.5 }, { -19.5, 1.5 }, { -16.5, 4 }, { -13, 2.5 }, { -11, -2.6 }, { -6, -2.4 }, { -3.5, 0.6 }, { -1.1, 1.2 } }, paint, 8.8)
            by_sofa(b, 1.2)
        end },
    },
}
