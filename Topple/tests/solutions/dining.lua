-- One way to win each Dining Room challenge (same order as Scripts/challenges/dining.lua). See tests/challenge_test.lua.
local function paint() return "cream" end
-- Carry on from domino `last` with size k: a path through pts, its first domino where the chain's spacing puts it.
local function cont(b, F, last, pts, k)
    local d = F.SPACING * (last.s + k) / 2
    local first = { last.x + math.cos(last.a) * d, last.y + math.sin(last.a) * d }
    local all = { first }
    for _, p in ipairs(pts) do all[#all + 1] = p end
    local p = b:place_path(all, paint, last.z, k)
    return p
end
-- Straight on along +x from `last` with size k up to x1.
local function along(b, F, last, x1, k)
    local x, prev = last.x + F.SPACING * (last.s + k) / 2, last
    while x <= x1 + 1e-9 do
        prev = assert(b:place(x, last.y, 0, last.z, "cream", k), "along: no room at " .. x)
        x = x + F.SPACING * k
    end
    return prev
end
-- Along the sideboard from `last` (heading east at the goal's row): Standards to the board, Minis under it, Standards on.
local function under_board(b, F, last)
    local p = along(b, F, last, -4.2, 1)       -- (a Standard nearer the board falls into its edge)
    p = along(b, F, p, -1.45, F.SIZES[1])
    p = along(b, F, p, 3.42, 1)                -- (up to the End at 4.02: one more if the row leaves too wide a gap)
    if 4.02 - p.x > 0.8 then assert(b:place((p.x + 4.02) / 2, p.y, 0, p.z, "cream", 1), "the domino before the End") end
end
-- From the table up the ramp between the chairs onto the sideboard, turning east to the goal's row.
local UP = { { -7, 2 }, { -7, 3 }, { -7, 21.4 }, { -7, 22.6 }, { -6.6, 24.5 }, { -5.6, 25.4 }, { -5, 25.5 } }
local function ramp(b) assert(b:place_ramp(-7, 6.6, 15, -7, 25, 17)) end
local function finish_on(b, F, last) under_board(b, F, last) end
return {
    function(b, F)
        under_board(b, F, b:starter())
    end,
    {
        -- East round the glass tower (the trap-avoiding step), then north to the ramp.
        solve = function(b, F)
            ramp(b)
            local p = b:place_path({ { -16, -9.38 }, { -15.2, -7.6 }, { -11.6, -5.4 }, { -8.2, -2.4 }, { -7.2, 0.6 }, table.unpack(UP) }, paint, 15)
            finish_on(b, F, p)
        end,
        without = function(b, F)
            ramp(b)
            local p = b:place_path({ { -16, -9.38 }, { -16, 2.5 }, { -12, 4.5 }, { -7.5, 4.5 }, table.unpack(UP, 3) }, paint, 15)
            finish_on(b, F, p)
        end,
        objectives = { via = function(b, F)
            ramp(b)
            local p = b:place_path({ { -16, -9.38 }, { -15.2, -7.6 }, { -11.6, -5.4 }, { -4, -5.5 }, { -2, -3 }, { -4, 0 }, { -6.2, 1.2 }, { -7, 2.4 }, table.unpack(UP, 2) }, paint, 15)
            finish_on(b, F, p)
        end },
    },
    {
        -- A tight turn of Minis clear of the tower (the trap-avoiding step), Standards to the ramp.
        solve = function(b, F)
            ramp(b)
            local m
            for _, d in ipairs({ { -12.6, -1.8, 124 }, { -12.66, -1.39, 98 }, { -12.52, -1, 70 }, { -12.22, -0.72, 40 }, { -11.82, -0.6, 12 }, { -11.41, -0.57, 3 } }) do
                m = assert(b:place(d[1], d[2], math.rad(d[3]), 15, "cream", F.SIZES[1]), "a Mini of the turn")
            end
            local p = cont(b, F, m, { { -9, -0.4 }, { -7.4, 0.8 }, table.unpack(UP) }, 1)
            finish_on(b, F, p)
        end,
        without = function(b, F)
            ramp(b)
            local p = cont(b, F, b:starter(), { { -12.5, -1.4 }, { -12.4, 0.3 }, { -9, 1.2 }, { -7.4, 1.8 }, table.unpack(UP, 2) }, 1)
            finish_on(b, F, p)
        end,
        misses = { time = function(b, F)
            ramp(b)
            local m
            for _, d in ipairs({ { -12.6, -1.8, 124 }, { -12.66, -1.39, 98 }, { -12.52, -1, 70 }, { -12.22, -0.72, 40 }, { -11.82, -0.6, 12 }, { -11.41, -0.57, 3 } }) do
                m = assert(b:place(d[1], d[2], math.rad(d[3]), 15, "cream", F.SIZES[1]), "a Mini of the turn")
            end
            local p = cont(b, F, m, { { -9, -0.4 }, { -6, -2.5 }, { -4.5, -0.5 }, { -6.4, 1.6 }, { -7, 2.6 }, table.unpack(UP, 2) }, 1)
            finish_on(b, F, p)
        end },
    },
}
