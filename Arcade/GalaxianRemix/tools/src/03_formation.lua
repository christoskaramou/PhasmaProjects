------------------------------------------------------------------ the convoy (arcade layout)
-- 10 columns x 6 rows: 2 flagships (columns 4 and 7), 6 red escorts, 8 purple emissaries and 30 blue drones (46 in all).
local XMAX = 7.2          -- the Galaxip's travel either side of centre
local PY = 1.2            -- the Galaxip's height on the field
local TOPY = 21.5         -- divers that fall off the bottom reappear here
local COLW, ROW0, ROWH = 1.38, 18.3, 1.2
local AS, SS = 1.2, 1.2      -- model scale for aliens and the Galaxip (hit boxes below already include it)
local ROWS = {
    { k = "flag", cols = { 3, 6 } },
    { k = "red", cols = { 2, 3, 4, 5, 6, 7 } },
    { k = "purple", cols = { 1, 2, 3, 4, 5, 6, 7, 8 } },
    { k = "drone", cols = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 } },
    { k = "drone", cols = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 } },
    { k = "drone", cols = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 } },
}
-- points: in formation / diving (flagship diving points depend on its escorts, see 04_sim)
local PTS_FORM = { drone = 30, purple = 40, red = 50, flag = 60 }
local PTS_DIVE = { drone = 60, purple = 80, red = 100, flag = 150 }
-- hit boxes (half sizes) match the models: wingspan x body length
local HB = { drone = { .54, .41 }, purple = { .6, .42 }, red = { .6, .46 }, flag = { .72, .54 } }
local SHIP_HB = { .6, .48 }
local COLS = { drone = { .16, .3, .82 }, purple = { .5, .2, .72 }, red = { .82, .14, .1 }, flag = { .95, .78, .2 } }
G.XMAX, G.PY, G.HB, G.SHIP_HB = XMAX, PY, HB, SHIP_HB
local function slot_x(col) return (col - 4.5) * COLW end
local function slot_y(row) return ROW0 - (row - 1) * ROWH end
