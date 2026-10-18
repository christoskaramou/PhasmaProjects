------------------------------------------------------------------ rounds
-- 13 columns per row, top row first. W O C G R B P Y = coloured bricks (50..120 pts), S = silver (2 hits, +1 every
-- 8 rounds; 50 x round pts), X = gold (indestructible), . = empty. Rounds 1, 2, 3 and 5 follow the arcade layouts;
-- the rest are built in the same style. Round 33 is DOH.
local RAW = {
    -- 1: six full rows
    { "", "", "", "SSSSSSSSSSSSS", "RRRRRRRRRRRRR", "YYYYYYYYYYYYY", "BBBBBBBBBBBBB", "PPPPPPPPPPPPP", "GGGGGGGGGGGGG" },
    -- 2: the staircase
    { "", "", "W............", "WO...........", "WOC..........", "WOCG.........", "WOCGR........", "WOCGRB.......", "WOCGRBP......",
      "WOCGRBPY.....", "WOCGRBPYW....", "WOCGRBPYWO...", "WOCGRBPYWOC..", "WOCGRBPYWOCG.", "SSSSSSSSSSSSR" },
    -- 3: full rows between gold bars
    { "", "", "", "GGGGGGGGGGGGG", "", "WWWXXXXXXXXXX", "", "RRRRRRRRRRRRR", "", "XXXXXXXXXXWWW", "", "PPPPPPPPPPPPP", "",
      "BBBXXXXXXXXXX", "", "CCCCCCCCCCCCC", "", "XXXXXXXXXXCCC" },
    -- 4: columns of colour
    { "", "", "", ".OCGS.BPYW.OC", ".CGSB.PYWO.CG", ".GSBP.YWOC.GS", ".SBPY.WOCG.SB", ".BPYW.OCGS.BP", ".PYWO.CGSB.PY",
      ".YWOC.GSBP.YW", ".WOCG.SBPY.WO", ".OCGS.BPYW.OC", ".CGSB.PYWO.CG", ".GSBP.YWOC.GS", ".SBPY.WOCG.SB" },
    -- 5: the space invader
    { "", "", "", "...Y.....Y...", "...Y.....Y...", "....Y...Y....", "....Y...Y....", "...SSSSSSS...", "...SSSSSSS...",
      "..SSRSSSRSS..", "..SSRSSSRSS..", ".SSSSSSSSSSS.", ".SSSSSSSSSSS.", ".SSSSSSSSSSS.", ".S.SSSSSSS.S.", ".S.S.....S.S.", "....SS.SS...." },
    -- 6: gold pillars
    { "", "", "", "B.R.G.X.G.R.B", "B.R.G.X.G.R.B", "B.R.G.X.G.R.B", "B.R.G.X.G.R.B", "B.R.G.X.G.R.B", "OXOXOXOXOXOXO",
      "B.R.G.X.G.R.B", "B.R.G.X.G.R.B", "B.R.G.X.G.R.B", "B.R.G.X.G.R.B" },
    -- 7: diamond
    { "", "", "", "......Y......", ".....YPY.....", "....YPBPY....", "...YPBRBPY...", "..YPBRGRBPY..", ".YPBRGCGRBPY.",
      "YPBRGCWCGRBPY", ".YPBRGCGRBPY.", "..YPBRGRBPY..", "...YPBRBPY...", "....YPBPY....", ".....YPY.....", "......Y......" },
    -- 8: gold maze
    { "", "", "", "X.X.X.X.X.X.X", "", "X.X..W.W..X.X", "...XXXXXXX...", "X.X.......X.X", "..X.XXXXX.X..", "X.X.X.C.X.X.X",
      "..X.X...X.X..", "X.X.XXXXX.X.X", "..X.......X..", "X.XXXXXXXXX.X" },
}
-- style generators for the remaining rounds (checkerboards, castles, waves, silver walls)
local COLS = "WOCGRBPY"
local function gen(n)
    local L = { "", "", "" }
    local kind = n % 6
    for r = 1, 12 do
        local row = {}
        for c = 1, 13 do
            local ch = COLS:sub((r + c + n) % 8 + 1, (r + c + n) % 8 + 1)
            if kind == 0 then if (r + c) % 2 == 1 then ch = "." end; if r == 12 then ch = "S" end
            elseif kind == 1 then if c == 7 or r == 1 then ch = "S" end; if r > 10 and c % 3 == 1 then ch = "X" end
            elseif kind == 2 then local w = floor(3 + 2.5 * math.sin((c + n) * 0.7)); if r < w or r > w + 6 then ch = "." end
            elseif kind == 3 then if r % 4 == 0 then ch = (c % 4 == 2) and "." or "X" end; if r == 1 then ch = "S" end
            elseif kind == 4 then local d = abs(c - 7) + abs(r - 6); if d > 6 then ch = "." elseif d == 6 then ch = "S" end
            else if (c - 1) % 4 == 3 then ch = "." end; if r % 3 == 0 then ch = "S" end end
            row[c] = ch
        end
        L[#L + 1] = table.concat(row)
    end
    return L
end
local ROUNDS = {}
for n = 1, 32 do ROUNDS[n] = RAW[n] or gen(n) end
G.ROUNDS = ROUNDS
G.LAST = 33
