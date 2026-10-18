------------------------------------------------------------------ enemies (NES order of difficulty)
--          mesh         speed(cells/s) smart wallpass points
local EN = {
    ballom = { "en_ballom", 1.6, 0, false, 100, "Ballom" },
    onil   = { "en_onil", 2.5, 1, false, 200, "Onil" },
    dahl   = { "en_dahl", 2.5, 0, false, 400, "Dahl" },
    minvo  = { "en_minvo", 3.4, 1, false, 800, "Minvo" },
    doria  = { "en_doria", 1.0, 2, true, 1000, "Doria" },
    ovape  = { "en_ovape", 1.6, 1, true, 2000, "Ovape" },
    pass   = { "en_pass", 3.4, 2, false, 4000, "Pass" },
    pontan = { "en_pontan", 3.4, 3, true, 8000, "Pontan" },
}
local TIER = { "ballom", "onil", "dahl", "minvo", "doria", "ovape", "pass", "pontan" }
G.EN, G.TIER = EN, TIER
-- stage table: enemy counts by tier {ballom, onil, dahl, minvo, doria, ovape, pass} and the hidden power-up
local ST_EN = {
    { 6 }, { 3, 3 }, { 2, 2, 2 }, { 1, 1, 2, 2 }, { 0, 4, 3 }, { 0, 2, 3, 2 }, { 0, 2, 3, 0, 2 }, { 0, 1, 2, 4 }, { 0, 1, 1, 4, 1 },
    { 0, 1, 1, 1, 3, 1 }, { 0, 1, 2, 3, 1, 1 }, { 0, 1, 1, 1, 1, 4 }, { 0, 0, 3, 3, 0, 2 }, { 0, 0, 0, 0, 0, 7, 1 }, { 0, 0, 1, 3, 0, 3, 1 },
    { 0, 0, 0, 3, 0, 4, 1 }, { 0, 0, 5, 0, 0, 2, 1 }, { 0, 0, 3, 3, 0, 0, 2 }, { 0, 1, 1, 0, 3, 1, 2 }, { 0, 0, 1, 1, 1, 2, 2 },
}
local ST_PU = { "fire", "bombs", "detonator", "speed", "bombs", "bombs", "fire", "detonator", "bombpass", "wallpass",
    "bombs", "bombs", "fire", "bombpass", "fire", "wallpass", "bombs", "bombpass", "bombs", "detonator",
    "bombpass", "bombs", "bombs", "detonator", "bombpass", "mystery", "fire", "bombs", "bombpass", "flamepass",
    "wallpass", "bombs", "detonator", "mystery", "bombpass", "flamepass", "detonator", "fire", "wallpass", "mystery",
    "detonator", "wallpass", "bombpass", "detonator", "mystery", "wallpass", "bombpass", "detonator", "flamepass", "mystery" }
G.PU_NAME = { bombs = "Bomb Up", fire = "Fire Up", speed = "Speed Up", wallpass = "Wall Pass", detonator = "Detonator",
    bombpass = "Bomb Pass", flamepass = "Flame Pass", mystery = "Mystery" }
local function stage_enemies(n)
    if ST_EN[n] then return ST_EN[n] end
    -- 21..50: the later NES stages lean on Doria, Ovape and Pass; counts grow to 10
    local total = min(10, 7 + floor((n - 20) / 10))
    local t = {}
    local hi = (n >= 40) and 7 or 6
    for i = 1, total do
        local k = hi - ((i * 3 + n) % 4)
        if n % 5 == 0 and i <= 2 then k = 7 end
        t[k] = (t[k] or 0) + 1
    end
    for i = 1, 7 do t[i] = t[i] or 0 end
    return t
end
G.stage_enemies = stage_enemies
local function stage_def(n)
    local en = stage_enemies(n)
    local maxt = 1
    for i = 1, 7 do if (en[i] or 0) > 0 then maxt = i end end
    return { n = n, en = en, pu = ST_PU[n] or "bombs", time = 200, spawn_tier = min(7, maxt + 1) }
end
G.stage_def = stage_def

------------------------------------------------------------------ grid
-- cells c 0..32, r 0..14; 0 empty, 1 hard, 2 brick. World centre of a cell = (c * CS, r * CS)
local GRID = {}
local ST = nil
local function wx(c) return c * CS end
local function cell_of(x) return floor(x / CS + 0.5) end
local function solid_raw(c, r) local col = GRID[c]; if not col then return 1 end; return col[r] or 1 end
G.solid_raw = solid_raw
local function build_layout(n)
    local seed = n * 7919 + 13
    local function lr() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
    for c = 0, NC + 1 do
        GRID[c] = {}
        for r = 0, NR + 1 do
            local hard = c == 0 or r == 0 or c == NC + 1 or r == NR + 1 or (c % 2 == 0 and r % 2 == 0)
            GRID[c][r] = hard and 1 or 0
        end
    end
    local free = {}
    for c = 1, NC do for r = 1, NR do
        if GRID[c][r] == 0 and not (c + r <= 3) then
            if lr() < 0.26 then GRID[c][r] = 2 end
            free[#free + 1] = { c, r }
        end
    end end
    local bricks = {}
    for c = 1, NC do for r = 1, NR do if GRID[c][r] == 2 then bricks[#bricks + 1] = { c, r } end end end
    local e = table.remove(bricks, 1 + floor(lr() * #bricks))
    local p = table.remove(bricks, 1 + floor(lr() * #bricks))
    local empties = {}
    for _, f in ipairs(free) do if GRID[f[1]][f[2]] == 0 and f[1] + f[2] >= 9 then empties[#empties + 1] = f end end
    return e, p, empties, lr
end
