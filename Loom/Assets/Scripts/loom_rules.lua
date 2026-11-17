-- Loom rules (pure Lua: no engine calls; tests/rules_test.lua runs them under LuaJIT).
-- The cloth is a grid COLS cells wide. Woven rows are numbered 1..K (K the newest, at the fell). The row being
-- woven lies loose on the warp: the player lays a kind of land into each of its cells from the wool bobbins,
-- then beats it in. Beaten rows never change. A traveller walks the woven path (path, bridge, house cells)
-- and stays LAG rows behind the newest row. The run ends when no walkable route joins the traveller to the
-- newest row: the cloth only grows from that row, so the path can never be mended.
-- Kinds (one character, as tools/loom_grid.py): '.' meadow, 'p' path, '~' water, 'b' bridge over an E-W river
-- (path N-S), 'B' bridge over a N-S river (path E-W), 'w' woods, 'f' field, 'h' hill, 'r' rock, 'H' house.
-- Directions: n = toward the fell (row k + 1), s = row k - 1, e = column c + 1, w = column c - 1.
local R = {}
local floor, min, max, abs = math.floor, math.min, math.max, math.abs

R.COLS = 9
R.LAG = 2                      -- the traveller stands on the third row behind the fell (row index 2, as target.png)
R.MAXWOOL = 9                  -- a full bobbin
R.VILLAGE_AT = 12              -- best rows walked that unlock the cream bobbin (village houses)
R.RIVER_EVERY = 9              -- from level 2 a river crosses the whole row every RIVER_EVERY rows
R.HILL_EVERY = 4               -- from the first rows the pattern brings a 2-wide hill ridge every HILL_EVERY rows ...
R.HILL_ROWS = { 2, 5 }         -- ... running on for 2 to 4 rows
-- The nine kinds, in key order 1..9: what each costs and which bobbin it spends.
R.KINDS = {
    { k = ".", name = "meadow", wool = "sage", cost = 0 },
    { k = "p", name = "path", wool = "tan", cost = 1 },
    { k = "~", name = "water", wool = "indigo", cost = 1 },
    { k = "b", name = "bridge", wool = "brown", cost = 1 },
    { k = "w", name = "woods", wool = "brown", cost = 1 },
    { k = "f", name = "field", wool = "ochre", cost = 1 },
    { k = "h", name = "hill", wool = "sage", cost = 1 },
    { k = "r", name = "rock", wool = "grey", cost = 1 },
    { k = "H", name = "house", wool = "cream", cost = 1 },
}
R.KIND_OF = {}
for i, d in ipairs(R.KINDS) do R.KIND_OF[d.k] = d; d.i = i end
R.KIND_OF.B = R.KIND_OF.b
R.WOOLS = { "sage", "indigo", "tan", "brown", "ochre", "grey", "cream" }
R.START_WOOL = { sage = 5, indigo = 4, tan = 9, brown = 4, ochre = 4, grey = 2, cream = 3 }
-- What a cell pays (once) when the traveller first stands on it or beside it (8 neighbours).
R.HARVEST = {
    f = { tan = 2 }, w = { ochre = 1, brown = 2 }, H = { tan = 1, ochre = 1, brown = 1 }, r = { cream = 1 },
    h = { tan = 1, sage = 1 }, ["~"] = { indigo = 1 }, b = { brown = 1, tan = 1 }, B = { brown = 1, tan = 1 },
}
local WALK = {
    p = { n = true, e = true, s = true, w = true }, H = { n = true, e = true, s = true, w = true },
    b = { n = true, s = true }, B = { e = true, w = true },
}
R.WALK = WALK
local DIRS = { n = { 0, 1 }, e = { 1, 0 }, s = { 0, -1 }, w = { -1, 0 } }
local OPP = { n = "s", s = "n", e = "w", w = "e" }
R.DIRS, R.OPP = DIRS, OPP

-- The cloth the run starts with (oldest first): a path up the middle through quiet country.
R.START = {
    "ff......h", "ff...p.hh", "f..w.p..h", "...w.p...", ".h...p.w.", "hh...p...", "h..f.p...", "...f.p.ww",
    ".....p..w", "..w..p...", "....fp...", "w...fp.h.", "w....p.hh", ".....p..h",
}

function R.level_of(beats) return 1 + floor(beats / 10) end
-- Seconds for one row before the loom beats it by itself: shrinks with the level.
function R.beat_time(level) return max(12, 45 - 5 * (level - 1)) end

------------------------------------------------------------------ the cloth
local function cell(st, c, k)
    local row = st.rows[k]
    if not row or c < 0 or c >= R.COLS then return nil end
    return row:sub(c + 1, c + 1)
end
R.cell = cell
local function walkable(kind) return kind ~= nil and WALK[kind] ~= nil end
R.walkable = walkable
-- Can the traveller step from (c, k) in direction d? Both cells must be walkable and open toward each other.
local function step_ok(st, c, k, d)
    local a = cell(st, c, k)
    local dc, dk = DIRS[d][1], DIRS[d][2]
    local b = cell(st, c + dc, k + dk)
    return walkable(a) and walkable(b) and WALK[a][d] and WALK[b][OPP[d]] or false
end
R.step_ok = step_ok

-- Breadth-first search over the woven path from the traveller. Returns dist[id], prev[id] (id = k * 16 + c).
local function id_of(c, k) return k * 16 + c end
R.id_of = id_of
local function search(st, c0, k0)
    local dist, prev = { [id_of(c0, k0)] = 0 }, {}
    local q, h = { { c0, k0 } }, 1
    local lo = st.K - 40
    while q[h] do
        local c, k = q[h][1], q[h][2]
        h = h + 1
        for _, d in ipairs({ "n", "e", "w", "s" }) do
            if step_ok(st, c, k, d) then
                local nc, nk = c + DIRS[d][1], k + DIRS[d][2]
                local nid = id_of(nc, nk)
                if nk >= lo and dist[nid] == nil then
                    dist[nid] = dist[id_of(c, k)] + 1
                    prev[nid] = id_of(c, k)
                    q[#q + 1] = { nc, nk }
                end
            end
        end
    end
    return dist, prev
end
R.search = search

-- Is the path still whole: a walkable route from the traveller to the newest row?
function R.path_whole(st)
    local dist = search(st, st.trav.c, st.trav.k)
    for c = 0, R.COLS - 1 do if dist[id_of(c, st.K)] then return true end end
    return false
end

------------------------------------------------------------------ a run
local function rng_new(seed) return { s = (seed or 1) % 2147483647 } end
local function rnd(g, n)    -- 1..n (Park-Miller)
    g.s = (g.s * 16807) % 2147483647
    return 1 + floor(g.s / 2147483647 * n)
end
R.rnd = rnd

local function emit(st, e) st.nev = st.nev + 1; e.n = st.nev; st.events[#st.events + 1] = e; if #st.events > 64 then table.remove(st.events, 1) end end

local function harvest_around(st, c, k)
    for dk = -1, 1 do
        for dc = -1, 1 do
            local cc, kk = c + dc, k + dk
            local kind = cell(st, cc, kk)
            local id = id_of(cc, kk)
            if kind and R.HARVEST[kind] and not st.harvested[id] then
                st.harvested[id] = true
                local got = 0
                for wool, n in pairs(R.HARVEST[kind]) do
                    if wool ~= "cream" or st.village then
                        local before = st.wool[wool]
                        st.wool[wool] = min(R.MAXWOOL, before + n)
                        got = got + (st.wool[wool] - before)
                    end
                end
                if got > 0 then
                    st.harvest = st.harvest + got
                    emit(st, { kind = "wool", c = cc, k = kk, what = kind, amount = got })
                end
            end
        end
    end
end

local function new_row_forced(st)
    st.forced = {}
    local lv = st.level
    local nk = st.K + 1
    if lv >= 2 and nk % R.RIVER_EVERY == 0 then
        -- round 4: the pattern's river crosses the cloth over two rows with a bend - from one edge to column j in this
        -- row, then on from j to the other edge in the next (it winds, it is no straight canal). j is never a column
        -- where the newest row is walkable, so the path's head can always bridge it on one of the two rows.
        local j, tries = nil, 0
        while not j and tries < 30 do
            tries = tries + 1
            local c = rnd(st.g, R.COLS - 2)               -- 1..7
            if not walkable(cell(st, c, st.K)) then j = c end
        end
        j = j or 4
        local west = rnd(st.g, 2) == 1
        for c = 0, R.COLS - 1 do if (west and c <= j) or (not west and c >= j) then st.forced[c] = "~" end end
        st.river2 = { j = j, west = west }
    elseif st.river2 then
        local j, west = st.river2.j, st.river2.west
        for c = 0, R.COLS - 1 do if (west and c >= j) or (not west and c <= j) then st.forced[c] = "~" end end
        st.river2 = nil
    end
    -- a bridge over a N-S river carries the river on into the next row
    for c = 0, R.COLS - 1 do if cell(st, c, st.K) == "B" then st.forced[c] = "~" end end
    -- the pattern brings hills (round 3): a 2-wide ridge that runs on for HILL_ROWS rows, every HILL_EVERY rows, never
    -- on a column where the newest row is walkable (the path's head always has a way on) nor on a river row
    local function free(c) return c >= 0 and c < R.COLS and not st.forced[c] and not walkable(cell(st, c, st.K)) end
    if not st.hillrun and nk % R.HILL_EVERY == 3 then
        local tries = 0
        while tries < 12 do
            tries = tries + 1
            local c = rnd(st.g, R.COLS - 1) - 1
            if free(c) and free(c + 1) then st.hillrun = { c = c, left = R.HILL_ROWS[1] + rnd(st.g, R.HILL_ROWS[2] - R.HILL_ROWS[1] + 1) - 1 }; break end
        end
    end
    if st.hillrun then
        local h = st.hillrun
        for c = h.c, h.c + 1 do if free(c) then st.forced[c] = "h" end end
        h.left = h.left - 1
        if h.left <= 0 then st.hillrun = nil end
    end
    if lv >= 3 and not st.forced[0] then
        local n = rnd(st.g, 3) - 1                     -- 0..2 rock outcrops
        for _ = 1, n do
            local c = rnd(st.g, R.COLS) - 1
            -- never right ahead of the path's head (the path could not go on): only beside it
            if not st.forced[c] and not walkable(cell(st, c, st.K)) then st.forced[c] = "r" end
        end
    end
    st.cur = {}
    for c = 0, R.COLS - 1 do st.cur[c] = st.forced[c] end
    st.order = {}
end

-- opts: village (bool: the cream bobbin is unlocked), rows (start cloth, oldest first)
function R.new(seed, opts)
    opts = opts or {}
    local st = { seed = seed or 1, g = rng_new(seed or 1), rows = {}, K = 0, beats = 0, level = 1, walked = 0, harvest = 0,
        score = 0, wool = {}, harvested = {}, events = {}, nev = 0, cursor = 4, village = opts.village and true or false,
        over = nil, route = nil }
    for i, r in ipairs(opts.rows or R.START) do st.rows[i] = r end
    st.K = #st.rows
    for _, w in ipairs(R.WOOLS) do st.wool[w] = R.START_WOOL[w] end
    if not st.village then st.wool.cream = 0 end
    -- the traveller: on the path in row K - LAG
    local k = st.K - R.LAG
    local tc
    for c = 0, R.COLS - 1 do if walkable(cell(st, c, k)) and (not tc or abs(c - 4) < abs(tc - 4)) then tc = c end end
    tc = tc or 4
    st.trav = { c = tc, k = k }
    for kk = 1, k do for c = 0, R.COLS - 1 do st.harvested[id_of(c, kk)] = true end end   -- the start cloth is spent
    harvest_around(st, tc, k)
    st.timer = R.beat_time(1)
    new_row_forced(st)
    return st
end

-- Is a bridge legal in cell c of the row being woven? It needs water on both sides across it: west and east
-- (the selvedge counts as river running off the cloth) for an E-W river, or water behind it for a N-S river
-- (the river then carries on into the next row). Returns 'b', 'B' or nil. lenient (while laying): one side of an
-- E-W river is enough, the other may still be woven; the beat checks both.
local function is_water(k) return k == "~" or k == "b" end
function R.bridge_kind(st, c, lenient)
    local row = st.cur
    local function side(cc)
        if cc < 0 or cc >= R.COLS then return true end
        return is_water(row[cc])
    end
    local real = (c > 0 and is_water(row[c - 1])) or (c < R.COLS - 1 and is_water(row[c + 1]))
    if real and (lenient or (side(c - 1) and side(c + 1))) then return "b" end
    local behind = cell(st, c, st.K)
    if behind == "~" or behind == "B" then return "B" end
    return nil
end

local function row_string(st)
    local t = {}
    for c = 0, R.COLS - 1 do t[c + 1] = st.cur[c] or "." end
    return table.concat(t)
end
R.row_string = row_string

-- Lay kind i (1..9) into cell c of the row being woven. Returns true or false and a reason.
function R.lay(st, c, i)
    if st.over then return false, "the run is over" end
    local d = R.KINDS[i]
    if not d or c < 0 or c >= R.COLS then return false, "no such cell" end
    local f = st.forced[c]
    if f == "r" then return false, "rock is woven into the pattern here" end
    if f == "~" and d.k ~= "b" then return false, "the river runs here: only a bridge can cross it" end
    if d.k == "H" and not st.village then return false, "village houses unlock at best " .. R.VILLAGE_AT .. " rows" end
    local old = st.cur[c]
    if old == d.k or (old == "B" and d.k == "b") then return false, "already " .. d.name end
    -- refund what is replaced (never a forced cell)
    local refund = (old and not f) and R.KIND_OF[old] or nil
    local have = st.wool[d.wool] + ((refund and refund.wool == d.wool) and refund.cost or 0)
    if d.cost > 0 and have < d.cost then return false, "out of " .. d.wool .. " wool" end
    if d.k == "~" and not R.water_joins(st, c, true) then
        return false, "a river must start at the cloth's edge or join water"
    end
    if d.k == "b" then
        local saved = st.cur[c]
        st.cur[c] = nil
        local bk = R.bridge_kind(st, c, true)
        st.cur[c] = saved
        if not bk then return false, "a bridge needs river beside it (or behind it)" end
    end
    if refund then st.wool[refund.wool] = st.wool[refund.wool] + refund.cost end
    st.wool[d.wool] = st.wool[d.wool] - d.cost
    st.cur[c] = d.k
    st.order[#st.order + 1] = { c = c, old = old }
    emit(st, { kind = "lay", c = c, what = d.k })
    -- the shuttle moves on: next empty cell to the right, else to the left
    local nxt
    for cc = c + 1, R.COLS - 1 do if not st.cur[cc] then nxt = cc; break end end
    if not nxt then for cc = c - 1, 0, -1 do if not st.cur[cc] then nxt = cc; break end end end
    st.cursor = nxt or c
    return true
end

-- Take back the last pick laid in the row being woven (beaten rows cannot be unpicked).
function R.undo(st)
    if st.over then return false end
    local o = table.remove(st.order)
    if not o then return false, "nothing to take back" end
    local now = R.KIND_OF[st.cur[o.c]]
    st.wool[now.wool] = st.wool[now.wool] + now.cost
    if o.old and not st.forced[o.c] then
        local od = R.KIND_OF[o.old]
        if st.wool[od.wool] >= od.cost then st.wool[od.wool] = st.wool[od.wool] - od.cost else o.old = nil end
    end
    st.cur[o.c] = o.old
    st.cursor = o.c
    emit(st, { kind = "undo", c = o.c })
    return true
end

-- Rivers only (round 3: no lone ponds). A water cell must belong to a run of water / E-W bridges in its row that
-- touches the selvedge or lies on water behind it ('~' or a N-S bridge 'B'). lenient (while laying): beside water in
-- the row is enough, since its run may still reach the edge.
local function is_wet(k) return k == "~" or k == "b" end
function R.water_joins(st, c, lenient)
    local row = st.cur
    local function behind(cc) local k = cell(st, cc, st.K); return k == "~" or k == "B" end
    if c == 0 or c == R.COLS - 1 or behind(c) then return true end
    if lenient then return is_wet(row[c - 1]) or is_wet(row[c + 1]) or false end
    local a, b = c, c
    while a > 0 and is_wet(row[a - 1]) do a = a - 1 end
    while b < R.COLS - 1 and is_wet(row[b + 1]) do b = b + 1 end
    if a == 0 or b == R.COLS - 1 then return true end
    for cc = a, b do if behind(cc) then return true end end
    return false
end

------------------------------------------------------------------ teaching helpers (round 5): what a beat would do
-- The row the beat would weave from cur (default st.cur): bridges resolved (an illegal one falls back to the forced
-- kind), orphan water dropped, empty cells meadow. Pure: st is left as it was.
function R.resolved_row(st, cur)
    local saved = st.cur
    st.cur = {}
    for c = 0, R.COLS - 1 do st.cur[c] = (cur or saved)[c] end
    local out = {}
    for c = 0, R.COLS - 1 do
        local k = st.cur[c]
        if k == "b" or k == "B" then k = R.bridge_kind(st, c) or st.forced[c] end
        out[c] = k
    end
    for c = 0, R.COLS - 1 do
        if out[c] == "~" and not st.forced[c] and not R.water_joins(st, c) then out[c] = nil end
    end
    st.cur = saved
    local t = {}
    for c = 0, R.COLS - 1 do t[c + 1] = out[c] or "." end
    return table.concat(t)
end
-- The traveller's reach if `row` were the newest row: dist table from search (row K + 1 included).
local function reach_with(st, row)
    st.rows[st.K + 1] = row
    st.K = st.K + 1
    local ok, dist = pcall(search, st, st.trav.c, st.trav.k)
    st.K = st.K - 1
    st.rows[st.K + 1] = nil
    if not ok then error(dist) end
    return dist
end
-- Would beating the row in now end the run? (no walkable route from the traveller into it)
function R.would_break(st)
    local dist = reach_with(st, R.resolved_row(st))
    for c = 0, R.COLS - 1 do if dist[id_of(c, st.K + 1)] then return false end end
    return true
end
-- Which cells of the row being woven would continue the path if path wool (a bridge where the river is forced) were
-- laid there, with the rest of the row as it is: marks[c] = true. A forced rock is never marked.
function R.path_marks(st)
    local marks = {}
    for c = 0, R.COLS - 1 do
        if st.forced[c] ~= "r" then
            local hyp = {}
            for cc = 0, R.COLS - 1 do hyp[cc] = st.cur[cc] end
            if not walkable(hyp[c]) then hyp[c] = st.forced[c] == "~" and "b" or "p" end
            local dist = reach_with(st, R.resolved_row(st, hyp))
            marks[c] = dist[id_of(c, st.K + 1)] ~= nil
        else
            marks[c] = false
        end
    end
    return marks
end

-- Beat the row in. Empty cells become meadow. auto (the timer ran out): bridges that are no longer legal become
-- meadow and are refunded; otherwise an illegal bridge refuses the beat.
function R.beat(st, auto)
    if st.over then return false, "the run is over" end
    for c = 0, R.COLS - 1 do
        local k = st.cur[c]
        if k == "b" or k == "B" then
            local bk = R.bridge_kind(st, c)
            if not bk then
                if not auto then return false, "the bridge in column " .. (c + 1) .. " has no river across it" end
                st.cur[c] = st.forced[c]
                st.wool.brown = st.wool.brown + 1
            else
                st.cur[c] = bk
            end
        end
    end
    for c = 0, R.COLS - 1 do
        if st.cur[c] == "~" and not st.forced[c] and not R.water_joins(st, c) then
            if not auto then return false, "the water in column " .. (c + 1) .. " joins no river: start rivers at the edge" end
            st.cur[c] = nil
            st.wool.indigo = st.wool.indigo + 1
        end
    end
    local row = row_string(st)
    st.K = st.K + 1
    st.rows[st.K] = row
    st.beats = st.beats + 1
    st.level = R.level_of(st.beats)
    emit(st, { kind = "beat", k = st.K, auto = auto and true or false })
    -- the traveller walks on toward the fell, along the shortest route to the newest row
    local goal = st.K - R.LAG
    local dist, prev = search(st, st.trav.c, st.trav.k)
    local best
    for c = 0, R.COLS - 1 do
        local d = dist[id_of(c, st.K)]
        if d and (not best or d < best.d) then best = { c = c, d = d } end
    end
    local route = { { c = st.trav.c, k = st.trav.k } }
    if best then
        local chain, id = {}, id_of(best.c, st.K)
        while id do chain[#chain + 1] = id; id = prev[id] end
        -- chain runs newest-row -> traveller; walk it from the traveller until the goal row
        for i = #chain - 1, 1, -1 do
            local k, c = floor(chain[i] / 16), chain[i] % 16
            route[#route + 1] = { c = c, k = k }
            if k >= goal then break end
        end
    end
    for i = 2, #route do
        local p = route[i]
        if p.k > st.trav.k then st.walked = st.walked + (p.k - st.trav.k) end
        st.trav = { c = p.c, k = p.k }
        harvest_around(st, p.c, p.k)
        emit(st, { kind = "step", c = p.c, k = p.k })
    end
    st.route = route
    if not best then
        st.over = "break"
        -- why (for the game-over card): which columns the path ended at in the row before, and what this row held
        local heads, walk_n, river_head = {}, 0, false
        for c = 0, R.COLS - 1 do
            local k = cell(st, c, st.K - 1)
            if dist[id_of(c, st.K - 1)] and WALK[k] and WALK[k].n then
                heads[#heads + 1] = c
                if st.forced[c] == "~" then river_head = true end
            end
            if walkable(cell(st, c, st.K)) then walk_n = walk_n + 1 end
        end
        local cause = walk_n == 0 and (auto and "clock" or "nopath") or "detached"
        if river_head and walk_n == 0 then cause = "river" end
        st.over_info = { cause = cause, auto = auto and true or false, heads = heads, row = row, walkable = walk_n }
        emit(st, { kind = "over", cause = "break" })
    end
    st.score = st.walked * 10 + st.harvest
    st.timer = R.beat_time(st.level)
    new_row_forced(st)
    return true
end

-- Advance the loom's clock: the row beats itself in when its time runs out.
function R.update(st, dt)
    if st.over then return end
    st.timer = st.timer - dt
    if st.timer <= 0 then R.beat(st, true) end
end

------------------------------------------------------------------ what the cloth shows (mirror of tools/loom_grid.py)
-- grid(r, c): kind of visible row r (0 = newest) or nil. The world uses this to pick each cell's cooked variant.
local NB_ORDER = { { 0, 1 }, { 1, 1 }, { 1, 0 }, { 1, -1 }, { 0, -1 }, { -1, -1 }, { -1, 0 }, { -1, 1 } }
local SIDE_D = { n = { 0, 1 }, e = { 1, 0 }, s = { 0, -1 }, w = { -1, 0 } }
local function nb_of(grid, c, r)
    local t = {}
    for dx = -1, 1 do
        for dy = -1, 1 do
            local cc, rr = c + dx, r - dy
            t[dx * 3 + dy] = (cc >= 0 and cc < R.COLS) and grid(rr, cc) or nil
        end
    end
    return t
end
local function nbget(nb, dx, dy) return nb[dx * 3 + dy] end
local function connects(set, nb, side)
    local k = nbget(nb, SIDE_D[side][1], SIDE_D[side][2])
    if k == nil then return nil end
    if set == "water" then
        return k == "~" or (k == "b" and (side == "e" or side == "w")) or (k == "B" and (side == "n" or side == "s"))
    end
    return k == "p" or k == "H" or (k == "b" and (side == "n" or side == "s")) or (k == "B" and (side == "e" or side == "w"))
end
local function arms_of(set, nb)
    local on, off = {}, {}
    local n_on, last = 0, nil
    for _, s in ipairs({ "n", "e", "s", "w" }) do
        local v = connects(set, nb, s)
        if v then on[s] = true; n_on = n_on + 1; last = s elseif v == nil then off[s] = true end
    end
    if n_on == 1 and off[OPP[last]] then on[OPP[last]] = true end
    local t = {}
    for _, s in ipairs({ "n", "e", "s", "w" }) do if on[s] then t[#t + 1] = s end end
    return table.concat(t)
end
local function blob_key(nb, kind)
    local function is(dx, dy) return nbget(nb, dx, dy) == kind end
    local n, e, s, w = is(0, 1), is(1, 0), is(0, -1), is(-1, 0)
    local bits = { n, is(1, 1) and n and e, e, is(1, -1) and s and e, s, is(-1, -1) and s and w, w, is(-1, 1) and n and w }
    local t = {}
    for i = 1, 8 do t[i] = bits[i] and "1" or "0" end
    return table.concat(t)
end
local NAME = { ["."] = "meadow", h = "hill", w = "woods", ["~"] = "water", p = "path", f = "field", r = "rock", b = "bridgeEW", B = "bridgeNS" }
-- (kind, mask) of visible cell (c, r); row = the row's absolute number (keeps meadow / woods / rock looks stable)
function R.variant_key(grid, c, r, row)
    local nb = nb_of(grid, c, r)
    local kind = nbget(nb, 0, 0)
    if kind == "h" or kind == "f" then return kind, blob_key(nb, kind) end
    if kind == "~" then
        -- straight river cells meander: the bulge alternates by row (N-S) or column (E-W), as tools/loom_grid.py
        local arms = arms_of("water", nb)
        if arms == "ns" and (row or r) % 2 == 1 then arms = "ns2" elseif arms == "ew" and c % 2 == 1 then arms = "ew2" end
        return kind, arms
    end
    if kind == "p" or kind == "H" then return "p", arms_of("path", nb) end
    if kind == "b" then return "b", "ew" end
    if kind == "B" then return "B", "ns" end
    return kind, tostring(R.alt_of(kind, c, row or r))
end
R.ALTS = { ["."] = 4, w = 3, r = 2 }
function R.alt_of(kind, c, row) return (c * 7 + row * 3 + (c * row) % 3) % R.ALTS[kind] end
function R.key_name(kind, mask)
    if mask == "" then mask = "x" end
    return "c_" .. NAME[kind] .. "_" .. mask
end
-- The visible grid of a run: r = 0 is row K.
function R.grid_fn(st)
    return function(r, c)
        local row = st.rows[st.K - r]
        return row and row:sub(c + 1, c + 1) or nil
    end
end

------------------------------------------------------------------ a simple weaver (title-card attract and live tests)
-- Plans the row: carry the path on from its head (bridge where the river forces it), wander now and then, fill
-- the rest with land it can afford. careless = true weaves no path at all (it breaks the run: game-over tests).
function R.bot_row(st, careless)
    local plan = {}
    local dist = search(st, st.trav.c, st.trav.k)
    local heads = {}
    for c = 0, R.COLS - 1 do
        local k = cell(st, c, st.K)
        if dist[id_of(c, st.K)] and WALK[k].n then heads[#heads + 1] = c end
    end
    local used = {}
    if not careless and #heads > 0 then
        local h = heads[1]
        for _, c in ipairs(heads) do if abs(c - 4) < abs(h - 4) then h = c end end
        local up = cell(st, h, st.K)
        -- the head must open north (a bridge B only opens east-west: step sideways first)
        local col = h
        if st.forced[h] == "~" then
            plan[#plan + 1] = { c = h, i = 4 }
        elseif st.forced[h] == nil then
            plan[#plan + 1] = { c = h, i = 2 }
            -- now and then the path bends one cell sideways in this row
            local turn = rnd(st.g, 5)
            if up ~= "B" and turn == 1 and h > 1 and not st.forced[h - 1] then plan[#plan + 1] = { c = h - 1, i = 2 }; col = h - 1 end
            if up ~= "B" and turn == 2 and h < R.COLS - 2 and not st.forced[h + 1] then plan[#plan + 1] = { c = h + 1, i = 2 }; col = h + 1 end
        end
        used[h], used[col] = true, true
    end
    -- beside the path's new cell: land that pays back when the traveller passes (field: tan, woods: ochre and
    -- brown, house: all three); elsewhere mostly meadow (free), and now and then a hill or a pond for the look
    local function afford(i) local d = R.KINDS[i]; return st.wool[d.wool] >= d.cost + (d.wool == "tan" and 2 or 0) end
    local pathc = {}
    for _, p in ipairs(plan) do pathc[p.c] = true end
    local function side_kind()
        -- what the stocks need most: fields pay tan, woods pay brown and ochre, houses pay all three
        if st.wool.tan < 6 and afford(6) then return 6 end
        if afford(5) then return 5 end
        if afford(6) then return 6 end
        if st.village and afford(9) then return 9 end
        return 1
    end
    for c = 0, R.COLS - 1 do
        if not used[c] and not st.forced[c] then
            local i = 1
            if pathc[c - 1] or pathc[c + 1] then
                i = side_kind()
            else
                local r = rnd(st.g, 10)
                local behind = cell(st, c, st.K)
                -- one river runs on per row (more made loops), and not out of a full-width river row
                local full = true
                for cc = 0, R.COLS - 1 do if cell(st, cc, st.K) ~= "~" and cell(st, cc, st.K) ~= "b" then full = false end end
                if (behind == "~" or behind == "B") and not full and not plan.river and st.wool.indigo >= 1 and r <= 8 then
                    i = 3; plan.river = true                                                              -- a river runs on
                elseif r == 1 and st.wool.sage >= 4 then i = 7
                elseif r == 2 and st.wool.indigo >= 4 and (c == 0 or c == R.COLS - 1) then i = 3          -- a new river at the edge
                elseif r == 3 and st.wool.brown >= 5 then i = 5 end
            end
            if i > 1 then plan[#plan + 1] = { c = c, i = i } end
        end
    end
    return plan
end
-- Weave one whole row with the bot (anything it cannot afford stays meadow) and beat it in.
function R.bot_weave(st, careless)
    for _, p in ipairs(R.bot_row(st, careless)) do R.lay(st, p.c, p.i) end
    return R.beat(st, true)
end

return R
