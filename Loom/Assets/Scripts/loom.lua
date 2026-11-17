-- Loom (PhasmaEngine, Lua): weave a landscape row by row on a hand loom and keep the little traveller's path going.
-- This file wires the modules and runs the loom's state machine:
--   mode  "state"  a look pose (loom.state("A") / ("B") = the two target frames, frozen)
--         "play"   a rules run: phase "weave" (picks are laid) -> beat -> "scroll" (the cloth slides one row toward the
--                  weaver, the oldest row rolls over the front beam) -> "walk" (the traveller walks the new path) -> "weave"
-- loom_game.lua runs the game flow on top (title, run, pause, game over, settings, HUD, input, saves, sounds).
--   loom_data.lua   numbers generated from tools/loom_grid.py and the cooked meshes (tools/gen_assets.py)
--   loom_rules.lua  the rules (pure Lua)        loom_world.lua  drawing
-- Console (execute_lua): loom.state("A"), loom.play(seed), loom.G.info(), loom.info(), loom.timing_reset() / loom.timing().
local function module(path)
    local source = assert(fs.read(path), "Missing Loom module: " .. path)
    return assert(load(source, "@" .. path, "t", _ENV))()
end
local D = module("Scripts/loom_data.lua")
local R = module("Scripts/loom_rules.lua")
local W = module("Scripts/loom_world.lua")(D, R)

local floor, min, max, abs, sqrt, sin = math.floor, math.min, math.max, math.abs, math.sqrt, math.sin
local deg, atan2 = math.deg, math.atan2 or math.atan
local CELL = D.CELL
local SCROLL_T = 0.35           -- seconds for the cloth to slide one row on
local WALK_SPEED = 1.5          -- cells per second

local S = { mode = "state", t = 0, frozen = true, scroll = 1, phase = "weave", frames = 0, pirn = "tan", cursor = 4 }
_G.loom = { S = S, D = D, R = R, W = W }

------------------------------------------------------------------ the traveller's walk (cloth coordinates)
local OPP = R.OPP
local function cell_kind_mask(st, c, k)
    local kind = R.cell(st, c, k)
    local grid = R.grid_fn(st)
    local _, mask = R.variant_key(grid, c, st.K - k, k)
    return kind, mask
end
local function stand_pose(st, c, k)
    local kind, mask = cell_kind_mask(st, c, k)
    local u, v = W.stand_point(kind, mask)
    return { c = c, k = k, u = u, v = v, heading = 0 }
end
_G.loom.stand_pose = stand_pose
-- Points { c, k, u, v } along the drawn path from the traveller's pose through the rules' route.
local function route_points(st, route, from)
    local pts = { { c = from.c, k = from.k, u = from.u, v = from.v } }
    for i = 1, #route - 1 do
        local a, b = route[i], route[i + 1]
        local d = (b.k > a.k and "n") or (b.k < a.k and "s") or (b.c > a.c and "e") or "w"
        local ka, ma = cell_kind_mask(st, a.c, a.k)
        local half = W.cell_half(ka, ma, d)
        for j = #half, 1, -1 do pts[#pts + 1] = { c = a.c, k = a.k, u = half[j][1], v = half[j][2] } end
        local kb, mb = cell_kind_mask(st, b.c, b.k)
        for _, p in ipairs(W.cell_half(kb, mb, OPP[d])) do pts[#pts + 1] = { c = b.c, k = b.k, u = p[1], v = p[2] } end
    end
    -- distances along it (metres, cloth coordinates)
    local acc = 0
    pts[1].d = 0
    for i = 2, #pts do
        local p, q = pts[i - 1], pts[i]
        local dx, dy = (q.c + q.u - p.c - p.u) * CELL, (q.k + q.v - p.k - p.v) * CELL
        acc = acc + sqrt(dx * dx + dy * dy)
        q.d = acc
    end
    return pts, acc
end
_G.loom.route_points = route_points
local function walk_at(pts, d)
    for i = 2, #pts do
        local p, q = pts[i - 1], pts[i]
        if d <= q.d or i == #pts then
            local L = q.d - p.d
            local t = L > 1e-9 and max(0, min(1, (d - p.d) / L)) or 1
            local dx, dy = (q.c + q.u - p.c - p.u), (q.k + q.v - p.k - p.v)
            local w = { c = q.c, k = q.k, u = q.u - (1 - t) * (q.c + q.u - p.c - p.u), v = q.v - (1 - t) * (q.k + q.v - p.k - p.v) }
            -- stay in the end cell's frame: (c, k) is q's cell, (u, v) may run past its edge by a hair
            if abs(dx) + abs(dy) > 1e-9 then w.heading = deg(atan2(-dx, dy)) end
            return w
        end
    end
    return pts[#pts]
end

------------------------------------------------------------------ look states (the target frames)
local WOOL_KIND = { sage = ".", tan = "p", brown = "w", indigo = "~", ochre = "f", grey = "r", cream = "H" }
function _G.loom.state(name)
    local P = assert(D.STATES[name], "no state " .. tostring(name))
    local rows = {}
    for i = #P.rows, 1, -1 do rows[#rows + 1] = P.rows[i] end
    local st = R.new(1, { rows = rows, village = true })
    for c = 0, R.COLS - 1 do st.cur[c] = nil end
    for _, cw in ipairs(P.row) do st.cur[cw[1]] = WOOL_KIND[cw[2]] end
    for w, f in pairs(P.fill) do st.wool[w] = floor(f * R.MAXWOOL + 0.5) end
    st.trav = { c = P.trav[1], k = st.K - P.trav[2] }
    S.st, S.mode, S.frozen, S.scroll, S.phase = st, "state", true, 1, "weave"
    S.pts, S.len, S.wd = nil, 0, 0
    S.walk = { c = st.trav.c, k = st.trav.k, u = P.trav_uv[1], v = P.trav_uv[2], heading = P.heading }
    S.cursor, S.shuttle_col, S.pirn = nil, P.shuttle_col, P.row[#P.row][2]
    S.state_name = name
    if _G.loom.G then _G.loom.G.manual = true end
    return "state " .. name
end

------------------------------------------------------------------ a rules run
function _G.loom.play(seed, opts)
    local st = R.new(seed or 1, opts)
    S.st, S.mode, S.frozen, S.scroll, S.phase = st, "play", false, 1, "weave"
    S.pts, S.len, S.wd = nil, 0, 0          -- never carry the last run's walk into this one
    S.walk = stand_pose(st, st.trav.c, st.trav.k)
    S.walk.heading = -20
    S.cursor, S.shuttle_col, S.pirn = st.cursor, nil, "tan"
    S.K_seen = st.K
    return st
end
-- After the rules beat (player, bot or the clock): slide the cloth, then walk the route.
local function on_beat(st)
    S.scroll, S.phase = 0, "scroll"
    -- the walk starts from where the traveller stands now (cloth coordinates do not move with the scroll)
    S.pts, S.len = route_points(st, st.route or { { c = st.trav.c, k = st.trav.k } }, S.walk)
    S.wd = 0
end
function _G.loom.play_frame(dt)
    local st = S.st
    if not st or S.mode ~= "play" then return end
    if S.phase == "weave" or S.phase == "walk" then R.update(st, dt) end
    if st.K ~= S.K_seen then
        -- finish an unfinished walk at once (the player beat again while the traveller walked)
        if S.pts then S.walk = walk_at(S.pts, S.len); S.walk.heading = S.walk.heading or -20 end
        S.K_seen = st.K
        on_beat(st)
    end
    if S.phase == "scroll" then
        S.scroll = min(1, S.scroll + dt / SCROLL_T)
        if S.scroll >= 1 then S.phase = "walk" end
    elseif S.phase == "walk" then
        S.wd = S.wd + dt * WALK_SPEED * CELL
        local w = walk_at(S.pts, min(S.wd, S.len))
        w.heading = w.heading or S.walk.heading
        w.bob = 0.0010 * abs(sin(S.wd / CELL * math.pi * 2.2))
        S.walk = w
        if S.wd >= S.len then
            S.walk.bob = 0
            S.phase = "weave"
            S.pts = nil
        end
    end
    S.cursor = st.cursor
end
function _G.loom.busy() return S.phase == "scroll" end

------------------------------------------------------------------ the loop
W.init()
local Game = module("Scripts/loom_game.lua")(_G.loom, module("Scripts/Lib/settings_menu.lua"))
_G.loom.G = Game
function _G.loom.game_mode() Game.manual = false; Game.to_title(); return "game" end

function _G.loom.timing_reset() S.timing = { n = 0, sum = 0, max = 0, over = 0 }; return "timing reset" end
function _G.loom.timing()
    local T = S.timing
    if not T or T.n == 0 then return "no samples" end
    return string.format("frames=%d mean_ms=%.2f max_ms=%.2f over_16.7ms=%d", T.n, T.sum / T.n, T.max, T.over)
end
function _G.loom.info()
    local st = S.st
    return string.format("mode=%s phase=%s K=%s trav=%s,%s walked=%s score=%s over=%s nodes_created=%d swaps=%d",
        S.mode, S.phase, st and st.K or "-", st and st.trav.c or "-", st and st.trav.k or "-", st and st.walked or "-",
        st and st.score or "-", st and tostring(st.over) or "-", W.created, W.swaps or 0)
end

script.on_update("loom", function()
    local dms = engine.get_metrics().delta_ms
    local raw = max(0, min(0.05, dms / 1000))
    S.frames = S.frames + 1
    S.t = S.t + raw
    local T = S.timing
    if T then T.n = T.n + 1; T.sum = T.sum + dms; T.max = max(T.max, dms); if dms > 16.7 then T.over = T.over + 1 end end
    Game.update(raw)
    if Game.manual and S.mode == "play" then _G.loom.play_frame(raw) end     -- console runs (the game draws no cards)
    local st = S.st
    if st and not _G.loom.no_draw then
        local surf = runtime_ui.get_surface_size and runtime_ui.get_surface_size()
        local aspect = surf and surf.height and surf.height > 0 and surf.width / surf.height or nil
        W.frame({ st = st, scroll = S.scroll, walk = S.walk, cursor = Game.cursor_visible() and S.cursor or nil,
            shuttle_col = S.shuttle_col, pirn = S.pirn, dt = raw, aspect = aspect })
    end
end, "play")

print("[Loom] Ready. Left/Right move along the row, 1-9 lay wool, Space beats the row in. Esc pause, M mute.")
