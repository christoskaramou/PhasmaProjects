-- luajit tests/rules_test.lua   (run from the Loom folder): the pure rules, no engine.
local function load_file(path)
    local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close()
    return assert(load(s, "@" .. path))()
end
local R = load_file("Assets/Scripts/loom_rules.lua")
local fails, n = 0, 0
local function check(ok, msg)
    n = n + 1
    if ok then print("ok   " .. msg) else print("FAIL " .. msg); fails = fails + 1 end
end
local function idx(name) for i, d in ipairs(R.KINDS) do if d.name == name then return i end end end
local MEADOW, PATH, WATER, BRIDGE, WOODS, FIELD, HILL, ROCK, HOUSE = 1, 2, 3, 4, 5, 6, 7, 8, 9
assert(idx("house") == HOUSE and idx("bridge") == BRIDGE)

-- 1. a new run
do
    local st = R.new(7)
    check(st.K == #R.START and st.trav.k == st.K - R.LAG and R.walkable(R.cell(st, st.trav.c, st.trav.k)),
        "new run: traveller on the path " .. R.LAG .. " rows behind the newest row")
    check(R.path_whole(st) and not st.over, "new run: path whole")
    check(st.wool.cream == 0 and R.new(7, { village = true }).wool.cream == R.START_WOOL.cream, "cream bobbin empty until the village unlocks")
end

-- 2. laying spends wool; meadow is free; out of wool refuses; replacing refunds; undo restores
do
    local st = R.new(1)
    local tan = st.wool.tan
    check(R.lay(st, 4, PATH) and st.wool.tan == tan - 1 and st.cur[4] == "p", "a path spends one tan")
    check(st.cursor == 5, "the shuttle moves on to the next empty cell")
    local ok = R.lay(st, 4, MEADOW)
    check(ok and st.wool.tan == tan and st.cur[4] == ".", "replacing the path with meadow refunds the tan")
    check(R.undo(st) and st.cur[4] == "p" and st.wool.tan == tan - 1, "undo puts the path back and spends it again")
    check(R.undo(st) and st.cur[4] == nil and st.wool.tan == tan, "undo again leaves the cell empty, tan back")
    check(not R.undo(st), "nothing left to undo")
    st.wool.grey = 0
    local ok2, why = R.lay(st, 2, ROCK)
    check(not ok2 and why:find("grey"), "out of grey wool refuses a rock: " .. tostring(why))
    local ok3, why3 = R.lay(st, 2, HOUSE)
    check(not ok3 and why3:find("unlock"), "a house is refused until the village unlocks")
    local sv = R.new(1, { village = true })
    check(R.lay(sv, 2, HOUSE) and sv.cur[2] == "H", "with the village unlocked a house can be laid")
end

-- 3. bridges
do
    local st = R.new(3)
    local ok, why = R.lay(st, 3, BRIDGE)
    check(not ok and why:find("river"), "a bridge needs river beside it")
    R.lay(st, 0, WATER); R.lay(st, 1, WATER); R.lay(st, 2, WATER)      -- a river from the west edge
    check(st.cur[2] == "~", "a river laid from the cloth's edge")
    check(R.lay(st, 3, BRIDGE), "a bridge beside a river cell can be laid")
    local okb, whyb = R.beat(st)
    check(not okb and whyb:find("column 4"), "a bridge with river on one side only refuses the beat")
    R.lay(st, 4, WATER)
    -- the path north of the old head (col 5 in row K) is gone now: the river covers it; the bridge carries it
    st.cur[5] = "p"
    local K = st.K
    check(R.beat(st) and st.rows[K + 1]:sub(4, 4) == "b", "beaten: an E-W bridge ('b') with river both sides")
    -- a N-S river: water behind the cell makes a 'B' bridge, and the river carries on into the next row
    local s2 = R.new(4, { rows = { ".........", "...~p....", "...~p....", "...~p...." } })
    s2.wool.brown = 5
    check(R.lay(s2, 3, BRIDGE), "a bridge with river behind it can be laid")
    s2.cur[4] = "p"
    R.beat(s2)
    check(s2.rows[s2.K]:sub(4, 4) == "B" and s2.forced[3] == "~", "a N-S bridge ('B') forces the river on into the next row")
    local ok4, why4 = R.lay(s2, 3, PATH)
    check(not ok4 and why4:find("river"), "a forced river cell only takes a bridge")
end

-- 3b. rivers only (no lone ponds); hills come with the pattern in normal play
do
    local st = R.new(21)
    st.wool.indigo = 9
    local ok, why = R.lay(st, 2, WATER)
    check(not ok and why:find("edge"), "lone water in the middle of the row is refused: " .. tostring(why))
    check(R.lay(st, 8, WATER) and R.lay(st, 7, WATER) and R.lay(st, 6, WATER), "a river from the east edge can be laid cell by cell")
    st.cur[5] = "p"
    check(R.beat(st) and st.rows[st.K]:sub(7, 9) == "~~~", "beaten: the river run touching the edge")
    R.lay(st, 6, WATER)
    check(st.cur[6] == "~", "water on water behind it continues the river")
    -- water whose run neither reaches the edge nor stands on water: refused at the beat, and the clock turns it to meadow
    local s2 = R.new(22)
    s2.wool.indigo = 9
    s2.cur[3] = "~"; s2.cur[4] = "p"; s2.cur[5] = "p"
    local okb, whyb = R.beat(s2)
    check(not okb and whyb:find("column 4"), "an orphan water cell refuses the beat: " .. tostring(whyb))
    R.beat(s2, true)
    check(s2.rows[s2.K]:sub(4, 4) == ".", "the clock's beat turns orphan water into meadow")
    -- the pattern's hills: in 80 rows of normal play there are hill ridges, and never in front of the path's head
    local s3 = R.new(31, { village = true })
    local hills, blocked = 0, 0
    for _ = 1, 80 do
        if s3.over then break end
        for c = 0, R.COLS - 1 do
            if s3.forced[c] == "h" then
                hills = hills + 1
                if R.walkable(R.cell(s3, c, s3.K)) then blocked = blocked + 1 end
            end
        end
        R.bot_weave(s3)
    end
    check(hills >= 20, "the pattern brings hills into normal play (" .. hills .. " hill cells in 80 rows)")
    check(blocked == 0, "a forced hill never stands in front of a walkable cell of the newest row")
    local ponds = 0
    for k = #R.START + 1, s3.K do
        local row = s3.rows[k]
        for c = 1, R.COLS - 2 do
            if row:sub(c + 1, c + 1) == "~" then
                local l, r_ = row:sub(c, c), row:sub(c + 2, c + 2)
                local b = s3.rows[k - 1] and s3.rows[k - 1]:sub(c + 1, c + 1)
                local n = s3.rows[k + 1] and s3.rows[k + 1]:sub(c + 1, c + 1)
                if l ~= "~" and l ~= "b" and r_ ~= "~" and r_ ~= "b" and b ~= "~" and b ~= "B" and n ~= "~" and n ~= "B" then ponds = ponds + 1 end
            end
        end
    end
    check(ponds == 0, "no lone ponds in 80 rows of play (" .. ponds .. ")")
    -- the crossing's bend column is never where the newest row is walkable (the path can always bridge it)
    local s4 = R.new(41, { village = true })
    local blocked4, seen4 = 0, 0
    for _ = 1, 120 do
        if s4.over then break end
        local n = 0
        for c = 0, R.COLS - 1 do if s4.forced[c] == "~" then n = n + 1 end end
        if n >= 2 and s4.river2 then
            seen4 = seen4 + 1
            if R.walkable(R.cell(s4, s4.river2.j, s4.K)) then blocked4 = blocked4 + 1 end
        end
        R.bot_weave(s4)
    end
    check(seen4 >= 3 and blocked4 == 0, string.format("the crossing's bend never stands in front of the path's head (%d crossings)", seen4))
    -- meander keys: a straight N-S river alternates ns / ns2 by row, an E-W one ew / ew2 by column
    local rows = { "....~....", "....~....", "....~....", ".~~~~~~~." }
    local grid = function(r, c) local row = rows[r + 1]; return row and row:sub(c + 1, c + 1) or nil end
    local k1 = select(2, R.variant_key(grid, 4, 1, 11))
    local k2 = select(2, R.variant_key(grid, 4, 1, 12))
    local e1 = select(2, R.variant_key(grid, 2, 3, 5))
    local e2 = select(2, R.variant_key(grid, 3, 3, 5))
    check(k1 == "ns2" and k2 == "ns" and e1 == "ew" and e2 == "ew2", "straight river cells meander: " .. k1 .. "/" .. k2 .. " by row, " .. e1 .. "/" .. e2 .. " by column")
end

-- 4. the beat: the cloth grows, the traveller walks, the path breaks
do
    local st = R.new(5)
    local k0 = st.trav.k
    R.lay(st, 5, PATH)
    check(R.beat(st) and st.trav.k == k0 + 1 and st.walked == 1 and not st.over, "beat: the traveller walks one row on")
    check(st.score == st.walked * 10 + st.harvest, "score = rows walked x 10 + wool harvested")
    -- a sideways path: the traveller walks along it
    R.lay(st, 5, PATH); R.lay(st, 6, PATH); R.lay(st, 7, PATH)
    R.beat(st)
    R.lay(st, 7, PATH)
    R.beat(st)
    check(not st.over and R.path_whole(st), "a path that bends sideways keeps the run going")
    -- no path in the new row: the run is over (nothing can be unpicked)
    R.lay(st, 7, FIELD)
    R.beat(st)
    check(st.over == "break", "a row with no path joined to the traveller ends the run")
    check(not R.lay(st, 1, PATH) and not R.beat(st), "nothing can be woven after the run ends")
end

-- 5. harvest: a field beside the path pays two tan, once
do
    local st = R.new(9)
    st.wool.tan = 3
    R.lay(st, 5, PATH); R.lay(st, 4, FIELD)
    R.beat(st)       -- traveller one row on: the new row is still 2 rows ahead
    local t1 = st.wool.tan
    R.lay(st, 5, PATH); R.beat(st)
    R.lay(st, 5, PATH); R.beat(st)    -- now the traveller stands beside the field's row
    local paid = 0
    for _, e in ipairs(st.events) do if e.kind == "wool" and e.what == "f" then paid = paid + e.amount end end
    check(paid == 2, "the field beside the path paid 2 tan (paid " .. paid .. ")")
    local h = st.harvest
    R.lay(st, 5, PATH); R.beat(st)
    local again = 0
    for _, e in ipairs(st.events) do if e.kind == "wool" and e.what == "f" then again = again + e.amount end end
    check(again == 2, "a cell pays only once")
    st.wool.tan = R.MAXWOOL
    check(st.wool.tan <= R.MAXWOOL, "bobbins hold at most " .. R.MAXWOOL)
end

-- 6. the clock beats the row in by itself; difficulty rises
do
    local st = R.new(2)
    local K = st.K
    R.lay(st, 5, PATH)
    R.update(st, R.beat_time(1) - 0.5)
    check(st.K == K, "no beat before the time runs out")
    R.update(st, 1.0)
    check(st.K == K + 1 and st.rows[K + 1]:sub(6, 6) == "p", "the loom beats the row in when the time runs out")
    check(R.beat_time(1) > R.beat_time(3) and R.beat_time(3) > R.beat_time(6) and R.beat_time(20) == 12, "the beat time shrinks with the level")
    check(R.level_of(0) == 1 and R.level_of(10) == 2 and R.level_of(25) == 3, "a level every 10 rows")
end

-- 7. forced rivers from level 2, rocks from level 3; the bot weaves long runs
do
    local st = R.new(11, { village = true })
    local crossings, bad_cross, rock_cells, alive = 0, 0, 0, 0
    local prev = nil
    for _ = 1, 60 do
        if st.over then break end
        local w = {}
        for c = 0, R.COLS - 1 do w[c] = st.forced[c] == "~"; if st.forced[c] == "r" then rock_cells = rock_cells + 1 end end
        local n, lo, hi = 0, 99, -1
        for c = 0, R.COLS - 1 do if w[c] then n = n + 1; lo = math.min(lo, c); hi = math.max(hi, c) end end
        -- a forced river run of 2+ cells from one edge: the second row of a crossing starts where the first one ended
        if n >= 2 and (lo == 0 or hi == R.COLS - 1) and n < R.COLS then
            if prev and prev.n >= 2 then
                crossings = crossings + 1
                local j = prev.lo == 0 and prev.hi or prev.lo
                if not w[j] or (prev.lo == 0) == (lo == 0) then bad_cross = bad_cross + 1 end
            end
        end
        prev = { n = n, lo = lo, hi = hi }
        R.bot_weave(st)
        alive = alive + 1
    end
    check(crossings >= 3 and bad_cross == 0, string.format("from level 2 the pattern's river crosses the cloth over two rows with a bend (%d crossings, %d broken)", crossings, bad_cross))
    check(rock_cells >= 1, "rock outcrops are forced from level 3 (" .. rock_cells .. " cells)")
    check(alive == 60 and not st.over, "the bot weaves 60 rows without breaking the path (score " .. st.score .. ")")
    local bridges = 0
    for k = 1, st.K do local _, nb = st.rows[k]:gsub("b", ""); bridges = bridges + nb end
    check(bridges >= 3, "it bridged the rivers (" .. bridges .. " bridges)")
    local s2 = R.new(12)
    R.bot_weave(s2, true)
    check(s2.over == "break", "a careless row breaks the path")
end

-- 7b. teaching helpers (round 5): the path marks and the break check agree with what a real beat does
do
    local function clone(st)
        local t = {}
        for k, v in pairs(st) do
            if type(v) == "table" then
                local c = {}
                for k2, v2 in pairs(v) do c[k2] = v2 end
                t[k] = c
            else t[k] = v end
        end
        t.g = { s = st.g.s }
        t.events = {}
        return t
    end
    local checked, bad, brk_bad, states = 0, 0, 0, 0
    for _, seed in ipairs({ 3, 17, 29, 41, 55 }) do
        local st = R.new(seed, { village = true })
        for row = 1, 40 do
            if st.over then break end
            -- a partly woven row: the bot's plan without its path cells, so marks have work to do
            local plan = R.bot_row(st)
            for i, p in ipairs(plan) do if i > 2 and p.i ~= 2 and p.i ~= 4 then R.lay(st, p.c, p.i) end end
            local marks = R.path_marks(st)
            states = states + 1
            for c = 0, R.COLS - 1 do
                if st.forced[c] ~= "r" then
                    local t = clone(st)
                    if not R.walkable(t.cur[c]) then t.cur[c] = t.forced[c] == "~" and "b" or "p" end
                    R.beat(t, true)
                    local dist = R.search(t, t.trav.c, t.trav.k)
                    local real = not t.over and dist[R.id_of(c, t.K)] ~= nil
                    checked = checked + 1
                    if real ~= marks[c] then bad = bad + 1 end
                end
            end
            -- would_break == the real beat's outcome for the row as it is
            local t = clone(st)
            local wb = R.would_break(st)
            R.beat(t, true)
            if wb ~= (t.over == "break") then brk_bad = brk_bad + 1 end
            -- then weave the row properly and go on
            st.cur = {}
            for c = 0, R.COLS - 1 do st.cur[c] = st.forced[c] end
            st.order = {}
            R.bot_weave(st)
        end
    end
    check(checked > 900 and bad == 0, string.format("path marks == a real beat's reach on %d cells of %d rows (%d differ)", checked, states, bad))
    check(brk_bad == 0, "would_break == whether a real beat ends the run, on every row (" .. brk_bad .. " differ)")
    local st = R.new(8)
    local marks = R.path_marks(st)
    local n = 0
    for c = 0, R.COLS - 1 do if marks[c] then n = n + 1 end end
    check(n >= 1 and marks[st.trav.c] and R.would_break(st), "a new run: the cell above the path's end is marked and the empty row would break")
    -- the game-over cause
    local s2 = R.new(9)
    R.update(s2, R.beat_time(1) + 1)
    check(s2.over == "break" and s2.over_info and s2.over_info.cause == "clock", "an empty row beaten by the clock: cause 'clock'")
    local s3 = R.new(9)
    R.lay(s3, 0, 6)
    R.beat(s3, false)
    check(s3.over_info and s3.over_info.cause == "nopath", "a row with no path cell: cause 'nopath'")
    local s4 = R.new(9)
    s4.cur[0] = "p"
    R.beat(s4, false)
    check(s4.over_info and s4.over_info.cause == "detached" and #s4.over_info.heads >= 1, "a path cell away from the path's end: cause 'detached'")
end

-- 8. variant keys: the Lua mirror of tools/loom_grid.py (samples written by tools/gen_assets.py)
do
    local f = io.open("tests/variant_samples.lua", "rb")
    if not f then check(false, "tests/variant_samples.lua missing (python tools/gen_assets.py --data-only)") else
        local S = assert(load(f:read("*a")))(); f:close()
        local bad, total = 0, 0
        for _, s in ipairs(S) do
            local rows = s.rows
            local grid = function(r, c) local row = rows[r + 1]; return row and row:sub(c + 1, c + 1) or nil end
            for _, e in ipairs(s.keys) do
                local kind, mask = R.variant_key(grid, e[1], e[2], e[2])
                total = total + 1
                if R.key_name(kind, mask) ~= e[3] then
                    bad = bad + 1
                    if bad < 4 then print("   ", e[1], e[2], R.key_name(kind, mask), "python:", e[3]) end
                end
            end
        end
        check(total > 1000 and bad == 0, string.format("variant keys match Python on %d cells (%d differ)", total, bad))
    end
end

print(string.format("%d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
