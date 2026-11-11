-- One way to win each Kitchen challenge (same order as Scripts/challenges/kitchen.lua). See tests/challenge_test.lua.
local function paint() return "cream" end
-- Off the top of a ramp at x (heading north onto the counter), a tight turn east along the front strip.
local function top_turn(x)
    return { { x, 15.4 }, { x, 16.4 }, { x + 0.4, 18.6 }, { x + 1.6, 19.5 }, { x + 3, 19.7 } }
end
-- East along the strip under the plates and back round the far side of them to the toaster's switch.
local PAST = { { -1, 19.7 }, { 0.8, 20.1 }, { 1.6, 21.1 }, { 1, 22.1 }, { -0.5, 22.45 }, { -3.2, 22.45 } }
-- The long way round: east along the counter to the oven end, then back west in front of the toaster.
local OVEN = { { -1, 19.7 }, { 3, 19.7 }, { 6.5, 19.9 }, { 8.3, 21.0 }, { 7.6, 22.3 }, { 6, 22.45 }, { 2, 22.45 }, { -0.5, 22.45 }, { -3.2, 22.45 } }
-- (the same with a tighter turn, short enough for the normal's budget)
local OVEN_SHORT = { { -1, 19.7 }, { 3, 19.7 }, { 6.5, 20.3 }, { 7.6, 21.6 }, { 6.5, 22.45 }, { 2, 22.45 }, { -0.5, 22.45 }, { -3.2, 22.45 } }
local function join(...)
    local out = {}
    for _, list in ipairs({ ... }) do for _, p in ipairs(list) do out[#out + 1] = p end end
    return out
end
return {
    function(b)
        assert(b:place_ramp(-4, -3, 15, -4, 20, 18))
        b:place_line(-4, -9.38, -4, 21.7, paint, 15)
    end,
    {
        -- Up the ramp, then east along the edge round the plates (the trap-avoiding step).
        solve = function(b)
            assert(b:place_ramp(-4, -3, 15, -4, 20, 18))
            b:place_path(join({ { -4, -9.38 } }, top_turn(-4), PAST), paint, 15)
        end,
        without = function(b)
            assert(b:place_ramp(-4, -3, 15, -4, 20, 18))
            b:place_line(-4, -9.38, -4, 21.7, paint, 15)
        end,
        objectives = { via = function(b)
            assert(b:place_ramp(-4, -3, 15, -4, 20, 18))
            b:place_path(join({ { -4, -9.38 } }, top_turn(-4), OVEN_SHORT), paint, 15)
        end },
    },
    {
        -- West out from under the chair, onto a ramp from the floor to the counter at its foot, then round the plates.
        solve = function(b)
            assert(b:place_ramp(-27, -23.5, 0, -27, 20, 18))
            b:place_path(join({ { -12.62, -23.5 }, { -19, -24 }, { -24.5, -26.2 }, { -27, -24.6 }, { -27, -22 } }, top_turn(-27), { { -2.4, 19.7 } }, PAST), paint, 0)
            b:erase_at(-27.17, -25.18, 0, 0.2)         -- (the curve's one stray, left standing outside the turn)
        end,
        misses = { time = function(b)
            assert(b:place_ramp(-27, -23.5, 0, -27, 20, 18))
            b:place_path(join({ { -12.62, -23.5 }, { -19, -24 }, { -24.5, -26.2 }, { -27, -24.6 }, { -27, -22 } }, top_turn(-27), { { -2.4, 19.7 } }, OVEN), paint, 0)
        end },
        without = function(b)
            assert(b:place_ramp(-27, -23.5, 0, -27, 20, 18))
            b:place_path(join({ { -12.62, -23.5 }, { -19, -24 }, { -24.5, -26.2 }, { -27, -24.6 }, { -27, -22 } }, top_turn(-27),
                { { -8, 19 }, { -5.5, 21.6 }, { -4.6, 22 } }), paint, 0)
        end,
    },
}
