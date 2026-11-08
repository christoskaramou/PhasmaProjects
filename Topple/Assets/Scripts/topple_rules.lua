-- Topple rules: build a chain of toys on a games table, tip the first domino, score what falls.
-- Pure Lua (no engine calls) so tests run under luajit.
--
-- Table coordinates: x right, y away from the camera (into the table); 1 unit = a domino's height.
-- A toy's facing `a` (radians) is the direction it acts along: the way a domino's broad faces look (it falls
-- along +-facing), the way a spring jumps, a rocket flies and a marble rolls.
--
-- A tip is simulated as a time-ordered event queue. Each piece triggers at most once:
--   domino  falls along whichever of +-facing the push favours (edge-on it only wobbles), sweeping its reach
--           (its height) ahead: it strikes the nearest solid toy there (or several side by side), rings any bell
--           it passes, and comes to rest leaning on what it struck.
--   house   falls along the push and sweeps its taller reach the same way.
--   bell    rings: the multiplier rises. Bells never block a chain.
--   spring  jumps the gap ahead along its facing and strikes the first solid toy past it.
--   rocket  flies 5 units along its facing and knocks over everything around where it lands.
--   marble  rolls down its chute and on across the felt until it strikes a toy (or leaves the table).
--   block / tree  stop whatever hits them.
-- Score: every piece that falls or fires is worth its value times the multiplier at that moment, so bells rung
-- early pay most. A table gives you a few tips to reach its target; then the toy shop, then a harder table.
local R = {}
local floor, min, max, abs, sqrt, sin, cos = math.floor, math.min, math.max, math.abs, math.sqrt, math.sin, math.cos
local asin, pi = math.asin, math.pi
local atan2 = math.atan2 or math.atan

R.DOM = { w = 0.5, t = 0.15, h = 1.0 }
R.SPACING = 0.62                                            -- along a drawn line
R.TABLE = { x0 = -12.0, x1 = 11.0, y0 = -6.5, y1 = 12.0 }   -- where toys may stand
R.LAYOUT = { x0 = -9.5, x1 = 7.5, y0 = -1.5, y1 = 11.0 }    -- where a table sets its houses and blocks
R.TIPS = 3
R.DOMINOES = 30
R.ROCKET_RANGE, R.ROCKET_FLIGHT, R.ROCKET_BLAST = 5.0, 0.9, 1.0
R.SPRING_FROM, R.SPRING_TO = 0.75, 3.6
R.MARBLE_SPEED = 4.5
R.CHUTE_TOP, R.CHUTE_END = -0.62, 0.95                      -- marble start / chute end, along the facing

-- r: footprint radius (placement); hit: radius others strike; reach / half: a faller's sweep.
R.KINDS = {
    domino = { r = 0.225, hit = 0.08, h = 1.0, half = 0.25, value = 1, solid = true },
    bell = { r = 0.35, hit = 0.75, value = 0 },             -- stands 0.6 to 1.0 beside a line and still rings
    spring = { r = 0.4, hit = 0.36, value = 2, solid = true },
    rocket = { r = 0.36, hit = 0.32, value = 3, solid = true },
    marble = { r = 0.62, hit = 0.42, value = 2, solid = true },
    house = { r = 0.78, hit = 0.66, h = 1.7, half = 0.7, value = 5, solid = true },
    block = { r = 0.36, hit = 0.32, solid = true },
    tree = { r = 0.5, hit = 0.34, solid = true },
}
R.SPECIALS = { "bell", "spring", "rocket", "marble" }

R.CHARMS = {
    brass = { name = "Polished Brass", text = "Bells add x3 instead of x2.", price = 6 },
    pips = { name = "Painted Pips", text = "Every domino scores 2.", price = 7 },
    touch = { name = "Light Touch", text = "Dominoes reach 20% farther.", price = 5 },
    fair = { name = "Village Fair", text = "Houses score 15.", price = 5 },
    encore = { name = "Encore", text = "One more tip at every table.", price = 8 },
    chime = { name = "Silver Chime", text = "Bells also score 5 when they ring.", price = 5 },
    fuse = { name = "Long Fuse", text = "Rockets fly 7 and blast a wider ring.", price = 6 },
    coil = { name = "Tight Coil", text = "Springs jump up to 5 ahead.", price = 5 },
    glass = { name = "Glass Marbles", text = "Marbles score 8.", price = 5 },
    thrift = { name = "Thrifty", text = "Everything in the shop costs 1 less.", price = 4 },
    piggy = { name = "Piggy Bank", text = "3 more coins for every cleared table.", price = 6 },
    lucky = { name = "Lucky Seven", text = "Every 7th domino down adds x1.", price = 8 },
    mason = { name = "Stonemason", text = "Blocks and trees score 4 when struck.", price = 5 },
    kit = { name = "Toolbox", text = "A free bell and spring at every table.", price = 7 },
}
R.TOYS = {
    bell = { name = "Brass Bell", text = "Raises the multiplier when the chain passes it.", price = 5 },
    spring = { name = "Spring", text = "Jumps a gap: strikes the first toy up to 3.6 ahead.", price = 3 },
    rocket = { name = "Rocket", text = "Flies 5 ahead and knocks over all it lands among.", price = 5 },
    marble = { name = "Marble Chute", text = "Rolls on across the felt to the next toy.", price = 4 },
    dominoes = { name = "Box of Dominoes", text = "6 more dominoes every tip.", price = 4 },
    crate = { name = "Toy Crate", text = "One bell, spring, rocket and marble.", price = 9 },
}

-- From table 2 each table has a twist; every 5th table is a Grand Table (a 1.5x target, double coins).
R.TWISTS = {
    market = { name = "Market Day", text = "Bells add one more to the multiplier." },
    festival = { name = "Festival", text = "Houses score double." },
    shortbox = { name = "Short Box", text = "8 fewer dominoes." },
    spare = { name = "Spare Tip", text = "One extra tip." },
    payday = { name = "Payday", text = "Clearing pays double coins." },
    heavy = { name = "Heavy Felt", text = "Dominoes reach 10% less." },
    gift = { name = "Gift Box", text = "A free rocket and marble." },
    echo = { name = "Echo", text = "The multiplier starts at x2." },
}
R.TWIST_IDS = { "echo", "festival", "gift", "heavy", "market", "payday", "shortbox", "spare" }
R.GRAND_EVERY = 5

------------------------------------------------------------------ helpers
local function rng(seed)
    local s = floor(seed) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function(a, b)
        s = s * 16807 % 2147483647
        local f = (s - 1) / 2147483646
        if a then return a + f * (b - a) end
        return f
    end
end
R.rng = rng

local function inside(x, y, T)
    T = T or R.TABLE
    return x >= T.x0 and x <= T.x1 and y >= T.y0 and y <= T.y1
end
R.inside = inside

function R.target(n)
    return floor(40 * 1.7 ^ (n - 1) / 10 + 0.5) * 10
end

-- What table n really asks for: a Grand Table wants 1.5x.
function R.table_target(n)
    local target = R.target(n)
    if n % R.GRAND_EVERY == 0 then target = floor(target * 1.5 / 10 + 0.5) * 10 end
    return target
end

-- Seconds from a push until a faller of height h reaches something c ahead (gravity: slow start, then quick).
function R.fall_time(c, h)
    local f = asin(min(1, max(0, c) / h)) / (pi / 2)
    return (0.03 + 0.14 * f ^ 0.7) * sqrt(h)
end

------------------------------------------------------------------ runs and tables
local Run = {}
Run.__index = Run

function R.new_run(seed)
    local run = setmetatable({ seed = seed or 1, table_n = 0, coins = 0, dominoes = R.DOMINOES,
        box = { bell = 1, spring = 1, rocket = 0, marble = 0 }, charms = {}, best = 0, over = false }, Run)
    run:next_table()
    return run
end

function Run:tips_per_table(twist)
    return R.TIPS + (self.charms.encore and 1 or 0) + (twist == "spare" and 1 or 0)
end

function R.twist(n, seed)
    if n < 2 then return nil end
    local r = rng(seed * 4513 + n * 7741 + 5)
    return R.TWIST_IDS[floor(r(0, #R.TWIST_IDS)) + 1]
end
function R.is_grand(n) return n % R.GRAND_EVERY == 0 end

-- The fixed toys of table n: a village of houses with trees, and from table 2 wooden blocks in the way.
function R.layout(n, seed)
    local r = rng(seed * 7919 + n * 104729 + 13)
    local L = R.LAYOUT
    local out = {}
    local function free(x, y, rad)
        for _, p in ipairs(out) do
            if (p.x - x) ^ 2 + (p.y - y) ^ 2 < (rad + R.KINDS[p.kind].r + 0.35) ^ 2 then return false end
        end
        return true
    end
    local function put(kind, x, y, a, paint)
        out[#out + 1] = { kind = kind, x = x, y = y, a = a or 0, paint = paint, fixed = true }
    end
    -- The village: a cluster of houses toward the back, its centre wandering table to table.
    local houses = min(3 + floor((n + 1) / 2), 8)
    local vx, vy = r(L.x0 + 2.5, L.x1 - 2.5), r(6.5, L.y1 - 1.2)
    local tries = 0
    while houses > 0 and tries < 400 do
        tries = tries + 1
        local x, y = vx + r(-3.6, 3.6), vy + r(-2.4, 2.0)
        if inside(x, y, L) and free(x, y, R.KINDS.house.r) then
            put("house", x, y, r(-0.35, 0.35), floor(r(0, 3)) + 1)
            houses = houses - 1
        end
    end
    -- A house or two out on their own from table 3; a Grand Table spreads two more about.
    for _ = 1, min(2, max(0, n - 2)) + (n % R.GRAND_EVERY == 0 and 2 or 0) do
        for _ = 1, 60 do
            local x, y = r(L.x0, L.x1), r(L.y0 + 1, L.y1 - 3)
            if free(x, y, R.KINDS.house.r + 0.6) then put("house", x, y, r(-0.5, 0.5), floor(r(0, 3)) + 1); break end
        end
    end
    for _ = 1, 2 + floor(r(0, 3)) do
        for _ = 1, 60 do
            local x, y = vx + r(-5, 5), vy + r(-3, 3)
            if inside(x, y, L) and free(x, y, R.KINDS.tree.r) then put("tree", x, y, 0); break end
        end
    end
    for _ = 1, min(6, n - 1 + floor(r(0, 2))) do
        for _ = 1, 60 do
            local x, y = r(L.x0, L.x1), r(L.y0, L.y1 - 2.5)
            if free(x, y, R.KINDS.block.r + 0.4) then put("block", x, y, r(-0.4, 0.4), floor(r(0, 4)) + 1); break end
        end
    end
    return out
end

function Run:next_table()
    self.table_n = self.table_n + 1
    local n = self.table_n
    local twist, grand = R.twist(n, self.seed), R.is_grand(n)
    local target = R.table_target(n)
    self.tb = { n = n, target = target, score = 0, tips_left = self:tips_per_table(twist), twist = twist, grand = grand,
        tips_used = 0, layout = R.layout(n, self.seed) }
    self.best = max(self.best, self.table_n)
    return self.tb
end

-- Record a finished tip. Returns "cleared", "again" or "over".
function Run:finish_tip(res)
    local tb = self.tb
    tb.score = tb.score + res.score
    tb.tips_left = tb.tips_left - 1
    tb.tips_used = tb.tips_used + 1
    if tb.score >= tb.target then
        local bonus = 3 + 2 * tb.tips_left + min(5, floor(2 * (tb.score - tb.target) / tb.target))
        if tb.twist == "payday" then bonus = bonus * 2 end
        if tb.grand then bonus = bonus * 2 end
        if self.charms.piggy then bonus = bonus + 3 end
        self.coins = self.coins + bonus
        tb.reward = bonus
        tb.cleared = true
        return "cleared"
    end
    if tb.tips_left <= 0 then
        self.over = true
        return "over"
    end
    return "again"
end

------------------------------------------------------------------ the toy shop
function Run:shop_offers()
    local r = rng(self.seed * 31 + self.table_n * 977)
    local pool = { "bell", "spring", "rocket", "marble", "dominoes", "crate" }
    for id in pairs(R.CHARMS) do if not self.charms[id] then pool[#pool + 1] = id end end
    table.sort(pool)
    local offers = {}
    while #offers < 4 and #pool > 0 do
        local i = floor(r(0, #pool)) + 1
        local id = table.remove(pool, i)
        local info = R.CHARMS[id] or R.TOYS[id]
        local price = self.charms.thrift and max(1, info.price - 1) or info.price
        offers[#offers + 1] = { id = id, charm = R.CHARMS[id] ~= nil, name = info.name, text = info.text, price = price }
    end
    self.offers = offers
    return offers
end

function Run:buy(i)
    local o = self.offers and self.offers[i]
    if not o or o.sold then return false, "gone" end
    if self.coins < o.price then return false, "coins" end
    self.coins = self.coins - o.price
    o.sold = true
    if o.charm then
        self.charms[o.id] = true                    -- Encore takes effect from the next table
    elseif o.id == "dominoes" then
        self.dominoes = self.dominoes + 6
    elseif o.id == "crate" then
        for _, k in ipairs(R.SPECIALS) do self.box[k] = (self.box[k] or 0) + 1 end
    else
        self.box[o.id] = (self.box[o.id] or 0) + 1
    end
    return true
end

------------------------------------------------------------------ the board of one tip
local Board = {}
Board.__index = Board

function Run:new_board()
    local tw = self.tb.twist
    local doms = tw == "shortbox" and max(12, self.dominoes - 8) or self.dominoes
    local b = setmetatable({ pieces = {}, next_id = 0, order = 0, left = { domino = doms }, run = self, twist = tw }, Board)
    for k, v in pairs(self.box) do b.left[k] = v end
    if tw == "gift" then b.left.rocket = (b.left.rocket or 0) + 1; b.left.marble = (b.left.marble or 0) + 1 end
    if self.charms.kit then b.left.bell = (b.left.bell or 0) + 1; b.left.spring = (b.left.spring or 0) + 1 end
    for _, p in ipairs(self.tb.layout) do
        b:add({ kind = p.kind, x = p.x, y = p.y, a = p.a, paint = p.paint, fixed = true })
    end
    return b
end

function Board:add(p)
    self.next_id = self.next_id + 1
    p.id = self.next_id
    self.pieces[p.id] = p
    return p
end

function Board:list()
    local t = {}
    for _, p in pairs(self.pieces) do t[#t + 1] = p end
    table.sort(t, function(a, b) return a.id < b.id end)
    return t
end

function Board:can_place(kind, x, y)
    local K = R.KINDS[kind]
    if not K then return false, "kind" end
    if not inside(x, y) then return false, "edge" end
    if (self.left[kind] or 0) <= 0 then return false, "none" end
    for _, q in pairs(self.pieces) do
        local need = K.r + R.KINDS[q.kind].r
        if (q.x - x) ^ 2 + (q.y - y) ^ 2 < need * need then return false, "crowded", q end
    end
    return true
end

function Board:place(kind, x, y, a, paint)
    local ok, why = self:can_place(kind, x, y)
    if not ok then return nil, why end
    self.left[kind] = self.left[kind] - 1
    self.order = self.order + 1
    return self:add({ kind = kind, x = x, y = y, a = a or 0, paint = paint, order = self.order })
end

function Board:remove(id)
    local p = self.pieces[id]
    if not p or p.fixed then return nil end
    self.pieces[id] = nil
    self.left[p.kind] = (self.left[p.kind] or 0) + 1
    return p
end

-- The piece nearest (x, y) that the player placed, within reach of the cursor.
function Board:pick(x, y, reach)
    local best, bd
    for _, p in pairs(self.pieces) do
        if not p.fixed then
            local d = sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2)
            if d <= (reach or 0.5) + R.KINDS[p.kind].r * 0.6 and (not bd or d < bd) then best, bd = p, d end
        end
    end
    return best
end

-- The domino the tip knocks over: the first one placed.
function Board:starter()
    local s
    for _, p in pairs(self.pieces) do
        if p.kind == "domino" and not p.fixed and (not s or p.order < s.order) then s = p end
    end
    return s
end

function Board:count(kind)
    local n = 0
    for _, p in pairs(self.pieces) do if p.kind == kind and not p.fixed then n = n + 1 end end
    return n
end

------------------------------------------------------------------ simulation
local function dir(a) return cos(a), sin(a) end

-- Pieces a faller at (px, py) going (dx, dy) with reach L and half-width hw strikes: the nearest solid ones
-- (several if side by side) and every bell passed on the way. Returns { piece, contact distance } lists.
local function sweep(board, done, src, px, py, dx, dy, L, hw, from)
    local cands = {}
    for _, q in pairs(board.pieces) do
        if q ~= src then
            local K = R.KINDS[q.kind]
            local rx, ry = q.x - px, q.y - py
            local along = rx * dx + ry * dy
            local lat = abs(rx * dy - ry * dx)
            local c = along - K.hit
            if along > (from or 0.05) and c <= L and lat <= hw + K.hit and not (q.kind == "bell" and done[q.id]) then
                cands[#cands + 1] = { q = q, c = max(0.02, c), solid = K.solid }
            end
        end
    end
    table.sort(cands, function(a, b) if a.c ~= b.c then return a.c < b.c end return a.q.id < b.q.id end)
    local first
    for _, h in ipairs(cands) do if h.solid then first = h.c; break end end
    local hits, bells = {}, {}
    for _, h in ipairs(cands) do
        if h.solid then
            if h.c <= first + 0.12 then hits[#hits + 1] = h end
        elseif not first or h.c <= first + 0.3 then
            bells[#bells + 1] = h
        end
    end
    return hits, bells
end

function R.simulate(board, run)
    run = run or board.run or {}
    local charms = run.charms or {}
    local tw = board.twist
    local reach_k = (charms.touch and 1.2 or 1.0) * (tw == "heavy" and 0.9 or 1.0)
    local bell_bonus = (charms.brass and 3 or 2) + (tw == "market" and 1 or 0)
    local value = { domino = charms.pips and 2 or 1, house = (charms.fair and 15 or 5) * (tw == "festival" and 2 or 1), spring = 2, rocket = 3,
        marble = charms.glass and 8 or 2, bell = charms.chime and 5 or 0, block = charms.mason and 4 or 0, tree = charms.mason and 4 or 0 }
    local rocket_range = charms.fuse and 7.0 or R.ROCKET_RANGE
    local rocket_blast = charms.fuse and 1.5 or R.ROCKET_BLAST
    local spring_to = charms.coil and 5.0 or R.SPRING_TO
    local res = { events = {}, falls = {}, score = 0, mult = tw == "echo" and 2 or 1, toppled = 0, dominoes = board:count("domino"), duration = 0 }
    res.start_mult = res.mult
    local starter = board:starter()
    if not starter then return res end
    local queue, seq = {}, 0
    local function push(t, piece, dx, dy, by)
        seq = seq + 1
        queue[#queue + 1] = { t = t, p = piece, dx = dx, dy = dy, by = by, seq = seq }
    end
    local function emit(ev)
        res.events[#res.events + 1] = ev
        res.duration = max(res.duration, ev.t_end or ev.t)
    end
    local done = {}
    local function award(p, t)
        local v = value[p.kind] or 0
        local pts = v * res.mult
        res.score = res.score + pts
        return pts
    end
    local sdx, sdy = dir(starter.a)
    push(0, starter, sdx, sdy, nil)
    while #queue > 0 do
        local bi = 1
        for i = 2, #queue do
            local a, b = queue[i], queue[bi]
            if a.t < b.t or (a.t == b.t and a.seq < b.seq) then bi = i end
        end
        local job = table.remove(queue, bi)
        local p, t = job.p, job.t
        if not done[p.id] then
            local K = R.KINDS[p.kind]
            if p.kind == "domino" or p.kind == "house" then
                local fx, fy = job.dx, job.dy
                local ok = true
                if p.kind == "domino" then
                    local ax, ay = dir(p.a)
                    local d = fx * ax + fy * ay
                    if abs(d) < 0.3 then ok = false else fx, fy = (d > 0 and ax or -ax), (d > 0 and ay or -ay) end
                end
                if not ok then
                    emit({ t = t, kind = "wobble", id = p.id })
                else
                    done[p.id] = true
                    res.toppled = res.toppled + (p.kind == "domino" and 1 or 0)
                    local h = K.h * (p.kind == "domino" and reach_k or 1)
                    local pts = award(p, t)
                    local hits, bells = sweep(board, done, p, p.x, p.y, fx, fy, h, K.half)
                    local fall = { id = p.id, t = t, dx = fx, dy = fy, kind = p.kind, starter = (p == starter) }
                    for _, b in ipairs(bells) do push(t + R.fall_time(b.c, K.h), b.q, fx, fy, p.id) end
                    if #hits > 0 then
                        local c = hits[1].c
                        fall.t_contact = t + R.fall_time(c, K.h)
                        fall.contact = math.deg(asin(min(1, (c + 0.04) / K.h)))
                        for _, hh in ipairs(hits) do push(fall.t_contact, hh.q, fx, fy, p.id) end
                        fall.blocked = true
                        for _, hh in ipairs(hits) do
                            if hh.q.kind == "domino" or hh.q.kind == "house" then fall.blocked = false end
                        end
                    else
                        fall.t_contact = t + R.fall_time(K.h, K.h)
                        fall.contact = 88
                    end
                    fall.t_end = fall.t_contact + 0.3
                    res.falls[p.id] = fall
                    emit({ t = t, kind = "fall", id = p.id, points = pts, mult = res.mult, t_end = fall.t_end, starter = fall.starter })
                    if charms.lucky and p.kind == "domino" and res.toppled % 7 == 0 then
                        res.mult = res.mult + 1
                        emit({ t = t, kind = "lucky", id = p.id, mult = res.mult })
                    end
                end
            elseif p.kind == "bell" then
                done[p.id] = true
                res.mult = res.mult + bell_bonus
                local pts = award(p, t)
                emit({ t = t, kind = "ring", id = p.id, points = pts > 0 and pts or nil, mult = res.mult, t_end = t + 1.2 })
            elseif p.kind == "block" or p.kind == "tree" then
                local pts
                if value[p.kind] > 0 and not done[p.id] then done[p.id] = true; pts = award(p, t) end
                emit({ t = t, kind = "thunk", id = p.id, points = pts })
            elseif p.kind == "spring" then
                done[p.id] = true
                local pts = award(p, t)
                local ax, ay = dir(p.a)
                local hits = sweep(board, done, p, p.x, p.y, ax, ay, spring_to, 0.42, R.SPRING_FROM)
                local land = t + 0.25 + 0.3
                local ev = { t = t, kind = "spring", id = p.id, points = pts, mult = res.mult, t_end = land + 0.1 }
                if hits[1] then
                    ev.to_x, ev.to_y = hits[1].q.x, hits[1].q.y
                    for _, hh in ipairs(hits) do push(land, hh.q, ax, ay, p.id) end
                end
                emit(ev)
            elseif p.kind == "rocket" then
                done[p.id] = true
                local pts = award(p, t)
                local ax, ay = dir(p.a)
                local t0 = t + 0.2
                local lx = min(R.TABLE.x1, max(R.TABLE.x0, p.x + ax * rocket_range))
                local ly = min(R.TABLE.y1, max(R.TABLE.y0, p.y + ay * rocket_range))
                local tl = t0 + R.ROCKET_FLIGHT
                emit({ t = t, kind = "launch", id = p.id, points = pts, mult = res.mult, t0 = t0, t_land = tl, lx = lx, ly = ly, t_end = tl + 0.4 })
                for _, q in pairs(board.pieces) do
                    if q ~= p and not done[q.id] then
                        local rx, ry = q.x - lx, q.y - ly
                        local d = sqrt(rx * rx + ry * ry)
                        if d <= rocket_blast + R.KINDS[q.kind].hit then
                            if d < 1e-3 then rx, ry, d = ax, ay, 1 end
                            push(tl + d * 0.05, q, rx / d, ry / d, p.id)
                        end
                    end
                end
            elseif p.kind == "marble" then
                done[p.id] = true
                local pts = award(p, t)
                local ax, ay = dir(p.a)
                local sx, sy = p.x + ax * R.CHUTE_TOP, p.y + ay * R.CHUTE_TOP
                local t0 = t + 0.15
                local hits = sweep(board, done, p, sx, sy, ax, ay, 30, 0.28, R.CHUTE_END - R.CHUTE_TOP)
                local ev = { t = t, kind = "roll", id = p.id, points = pts, mult = res.mult, t0 = t0, sx = sx, sy = sy, ax = ax, ay = ay }
                local dist
                if hits[1] then
                    dist = hits[1].c + 0.05
                    for _, hh in ipairs(hits) do push(t0 + dist / R.MARBLE_SPEED, hh.q, ax, ay, p.id) end
                else
                    -- Off the table: the first edge along the path.
                    dist = 30
                    for _, v in ipairs({ { ax, R.TABLE.x0 - sx, R.TABLE.x1 - sx }, { ay, R.TABLE.y0 - sy, R.TABLE.y1 - sy } }) do
                        if abs(v[1]) > 1e-6 then dist = min(dist, max(v[2] / v[1], v[3] / v[1])) end
                    end
                    ev.off = true
                end
                ev.dist = dist
                ev.t_end = t0 + dist / R.MARBLE_SPEED
                emit(ev)
            end
        end
    end
    table.sort(res.events, function(a, b) if a.t ~= b.t then return a.t < b.t end return (a.id or 0) < (b.id or 0) end)
    res.points_by = {}
    for _, ev in ipairs(res.events) do if ev.points then res.points_by[ev.id] = ev.points end end
    return res
end

------------------------------------------------------------------ drawing a line of dominoes
-- Given the last domino of a line (or the stroke's start) and the cursor, where the next one stands and how it
-- faces, once the cursor has moved a full spacing away.
function R.stroke_next(lx, ly, cx, cy)
    local dx, dy = cx - lx, cy - ly
    local d = sqrt(dx * dx + dy * dy)
    if d < R.SPACING then return nil end
    dx, dy = dx / d, dy / d
    return lx + dx * R.SPACING, ly + dy * R.SPACING, atan2(dy, dx)
end

return R
