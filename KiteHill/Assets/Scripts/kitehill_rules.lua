-- Kite Hill rules: race a kite through ribbon gates above the hills, against three rival kites, steering with the
-- gusts. Pure Lua (no engine calls) so tests run under luajit.
--
-- Field coordinates: x right, y away from the camera, h up (engine (x, h, -y)). Every kite flies in one upright
-- plane at y = R.PLANE_Y, above the valley floor, so a kite is (x, h) and a heading a (radians, 0 = right,
-- pi/2 = up). Kites fly like stunt kites: always moving along their nose, the player turns them (toward the
-- pointer, or left / right keys). Turning hard costs speed; the edges of the wind window are slower.
-- A gust blows every kite for a couple of seconds (announced first): flying with it is faster, against it slower,
-- and it drifts you off your line. Dip below the grass line and the kite crashes and relaunches a second later.
-- A race is a course of numbered gates (rings on poles) taken in order. Finish high enough to go on to the next
-- heat (more gates, smaller rings, stronger gusts, faster rivals). Coins (kept between runs) buy kite upgrades
-- and new kite designs at the workshop.
local R = {}
local floor, min, max, abs, sqrt, sin, cos, exp = math.floor, math.min, math.max, math.abs, math.sqrt, math.sin, math.cos, math.exp
local pi = math.pi
local atan2 = math.atan2 or math.atan

R.PLANE_Y = 12.0
R.FIELD = { x0 = -13.0, x1 = 13.0, h1 = 14.5 }      -- the wind window in the kite plane (the floor is the grass)
R.CLEAR = 0.5                                       -- a kite whose centre comes this close to the grass crashes
R.SPEED, R.TURN = 6.2, 2.7                          -- units / s, rad / s
R.TURN_COST = 0.3                                   -- speed lost at full turn
R.BOOST_SPEED, R.BOOST_TIME = 1.55, 1.1
R.CRASH_TIME = 1.3
R.COUNTDOWN = 3.0
R.TIME_LIMIT = 120.0
R.BULLSEYE = 0.45                                   -- fraction of a ring's radius
R.WARN = 1.3                                        -- gust warning, seconds

-- The ground: a valley floor with gaussian hills. tools/kh_common.py has the same numbers (the baked backdrop
-- is made from them): change both together.
R.BASE = -0.6
R.HILLS = {
    { -6, -12, 1.6, 14, 9 }, { 14, -6, 1.4, 9, 7 },                         -- the foreground slope and its shoulder
    { -16, 26, 3.0, 12, 10 }, { 6, 31, 2.6, 14, 9 }, { 25, 22, 2.4, 10, 9 },  -- the low hills behind the gates
    { -8, 48, 6.0, 16, 12 }, { 17, 50, 7.0, 12, 12 },                         -- the village hill, the windmill hill
    { -40, 90, 14, 30, 20 }, { 20, 112, 16, 40, 25 }, { 62, 82, 12, 25, 20 }, -- far hills
    { -75, 60, 9, 22, 18 },
}
function R.ground(x, y)
    local g = R.BASE
    for i = 1, #R.HILLS do
        local hh = R.HILLS[i]
        local dx, dy = (x - hh[1]) / hh[4], (y - hh[2]) / hh[5]
        g = g + hh[3] * exp(-(dx * dx + dy * dy))
    end
    return g
end
function R.floor(x) return R.ground(x, R.PLANE_Y) end

R.FLYER = { x = -6.0, y = 4.0 }                     -- the player's kite flyer, in the valley before the gates
R.LAUNCH = { -4.5, -10.0, 2.5, 9.5 }                 -- relaunch x: player, then the three rivals

R.RIVALS = {
    { name = "Marta", design = "poppy", pace = 1.0 },
    { name = "Theo", design = "harbour", pace = 0.97 },
    { name = "Ilse", design = "orchard", pace = 1.03 },
}

-- Kite designs: four sail panels (top left, top right, bottom left, bottom right) and the tail's bows.
R.DESIGNS = {
    { id = "meadow", name = "Meadow", price = 0, panels = { "cream", "terracotta", "terracotta", "cream" }, tail = "terracotta" },
    { id = "sunflower", name = "Sunflower", price = 10, panels = { "mustard", "cream", "cream", "mustard" }, tail = "mustard" },
    { id = "heather", name = "Heather", price = 16, panels = { "plum", "rose", "rose", "plum" }, tail = "rose" },
    { id = "sea", name = "Sea Breeze", price = 22, panels = { "sky", "white", "white", "sky" }, tail = "sky" },
    { id = "harvest", name = "Harvest", price = 30, panels = { "ochre", "sage", "terracotta", "ochre" }, tail = "sage" },
    -- The rivals' kites (not for sale).
    { id = "poppy", name = "Poppy", rival = true, panels = { "red", "red", "white", "red" }, tail = "red" },
    { id = "harbour", name = "Harbour", rival = true, panels = { "navy", "white", "navy", "navy" }, tail = "navy" },
    { id = "orchard", name = "Orchard", rival = true, panels = { "sage", "sage", "cream", "sage" }, tail = "olive" },
}
function R.design(id)
    for _, d in ipairs(R.DESIGNS) do if d.id == id then return d end end
    return R.DESIGNS[1]
end

R.UPGRADES = {
    { id = "sail", name = "Silk Sail", text = "Fly 7% faster.", price = { 6, 10, 16, 24 } },
    { id = "bridle", name = "Tuned Bridle", text = "Turn 12% tighter.", price = { 5, 9, 14 } },
    { id = "tail", name = "Long Tail", text = "Gusts push you 22% less.", price = { 5, 9, 14 } },
    { id = "updraft", name = "Updraft", text = "One more speed burst a heat.", price = { 6, 11, 18 } },
    { id = "eye", name = "Keen Eye", text = "Rings count 12% wider.", price = { 8, 14 } },
}
function R.upgrade(id)
    for _, u in ipairs(R.UPGRADES) do if u.id == id then return u end end
end

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
local function wrap(a)
    a = (a + pi) % (2 * pi)
    if a < 0 then a = a + 2 * pi end
    return a - pi
end
R.wrap = wrap
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end

------------------------------------------------------------------ save (coins, upgrades and designs, kept between runs)
function R.new_save()
    return { coins = 0, best = 0, runs = 0, design = "meadow", owned = { meadow = true },
        sail = 0, bridle = 0, tail = 0, updraft = 0, eye = 0 }
end
function R.load_save(text)
    local s = R.new_save()
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k == "owned" then
            for id in v:gmatch("[%w_]+") do s.owned[id] = true end
        elseif k == "design" then
            s.design = v
        elseif k and s[k] ~= nil and tonumber(v) then
            s[k] = max(0, floor(tonumber(v)))
        end
    end
    for _, u in ipairs(R.UPGRADES) do s[u.id] = min(s[u.id], #u.price) end
    if not s.owned[s.design] or R.design(s.design).rival then s.design = "meadow" end
    return s
end
function R.save_text(s)
    local owned = {}
    for _, d in ipairs(R.DESIGNS) do if s.owned[d.id] then owned[#owned + 1] = d.id end end
    local lines = { "coins=" .. s.coins, "best=" .. s.best, "runs=" .. s.runs, "design=" .. s.design, "owned=" .. table.concat(owned, ",") }
    for _, u in ipairs(R.UPGRADES) do lines[#lines + 1] = u.id .. "=" .. s[u.id] end
    return table.concat(lines, "\n") .. "\n"
end
-- The workshop. Upgrades: id; designs: "design:<id>" buys (or, once owned, chooses) a kite.
function R.price(save, id)
    local did = id:match("^design:(.+)$")
    if did then
        local d = R.design(did)
        if d.id ~= did or d.rival then return nil end
        return save.owned[did] and 0 or d.price
    end
    local u = R.upgrade(id)
    if not u then return nil end
    return u.price[save[id] + 1]                      -- nil when maxed
end
function R.buy(save, id)
    local p = R.price(save, id)
    if not p then return false, "maxed" end
    if save.coins < p then return false, "coins" end
    save.coins = save.coins - p
    local did = id:match("^design:(.+)$")
    if did then
        save.owned[did] = true
        save.design = did
    else
        save[id] = save[id] + 1
    end
    return true
end

------------------------------------------------------------------ heats
function R.heat(n)
    return {
        n = n,
        gates = min(10, 4 + n),
        radius = max(1.35, 2.25 - 0.09 * (n - 1)),
        rival = min(1.5, 0.8 + 0.045 * (n - 1)),          -- rival speed, times the base
        gust = 1.4 + 0.4 * n,                              -- gust drift, units / s
        gust_every = max(2.6, 6.5 - 0.45 * n),
        need = n <= 2 and 3 or (n <= 5 and 2 or 1),        -- finish in this place or better to go on
    }
end
function R.need_text(need) return ({ "1st", "top 2", "top 3" })[need] or ("top " .. need) end

R.SHOWN = 3                                         -- a kite sees its next ring and the two after it
-- A course: rings in the plane, each clear of the others and of the grass, a fair hop from the last.
function R.course(n, seed)
    local H = R.heat(n)
    local r = rng(seed * 31 + n * 977 + 5)
    local gates = {}
    local px, ph = -3.0, 4.0
    -- How badly a ring at (x, h) clashes with the rings shown with it (each kite sees its next R.SHOWN, so a
    -- ring stands with the R.SHOWN before it): rings must not overlap, and no pole may run through another's ring.
    local function clash(i, x, h)
        local worst = 0
        for j = max(1, i - R.SHOWN), i - 1 do
            local g = gates[j]
            local d = sqrt((g.x - x) ^ 2 + (g.h - h) ^ 2)
            worst = max(worst, (2 * H.radius + 1.0) - d, (H.radius + 0.35) - abs(g.x - x))
        end
        return worst
    end
    for i = 1, H.gates do
        local best, best_c
        for _, hop in ipairs({ { 6.0, 15.0 }, { 4.0, 18.0 }, { 2.5, 26.0 } }) do
            for _ = 1, 600 do
                local x = r(R.FIELD.x0 + H.radius + 0.4, R.FIELD.x1 - H.radius - 0.4)
                local h = r(R.floor(x) + H.radius + 1.6, R.FIELD.h1 - H.radius - 0.6)
                local d = sqrt((x - px) ^ 2 + (h - ph) ^ 2)
                local c = clash(i, x, h)
                if c <= 0 and d >= hop[1] and d <= hop[2] then best, best_c = { x = x, h = h }, c; break end
                if not best_c or c < best_c then best, best_c = { x = x, h = h }, c end
            end
            if best_c <= 0 then break end
        end
        best.r, best.i = H.radius, i
        gates[i] = best
        px, ph = best.x, best.h
    end
    return gates
end

------------------------------------------------------------------ gusts
local function make_gusts(H, r)
    local gusts = {}
    local t = r(1.5, 3.0)
    while t < R.TIME_LIMIT do
        local dir = r() < 0.5 and -1 or 1
        local g = { t0 = t, dur = r(1.6, 2.6), vx = dir * H.gust * r(0.8, 1.15), vh = H.gust * r(-0.35, 0.35) }
        gusts[#gusts + 1] = g
        t = t + g.dur + H.gust_every * r(0.7, 1.3)
    end
    return gusts
end
-- Gust strength at time t: a smooth rise and fall over its duration.
local function gust_env(g, t)
    local u = (t - g.t0) / g.dur
    if u <= 0 or u >= 1 then return 0 end
    return sin(u * pi) ^ 0.6
end
function R.wind(race, t)
    t = t or race.t
    local vx, vh = 0, 0
    for _, g in ipairs(race.gusts) do
        if t >= g.t0 - 0.1 and t <= g.t0 + g.dur then
            local e = gust_env(g, t)
            vx, vh = vx + g.vx * e, vh + g.vh * e
        end
    end
    return vx, vh
end

------------------------------------------------------------------ races
local function new_kite(i, x, opts)
    local h = R.floor(x) + 3.0
    return { i = i, x = x, h = h, a = pi / 2, launch = x, gate = 1, crashed = 0, boost = 0, turn = 0,
        speed = opts.speed, turn_rate = opts.turn, resist = opts.resist or 0, eye = opts.eye or 0,
        boosts = opts.boosts or 0, ai = opts.ai, name = opts.name, design = opts.design, passes = 0, bulls = 0, crashes = 0 }
end
function R.player_kite(save)
    return { speed = R.SPEED * (1 + 0.07 * save.sail), turn = R.TURN * (1 + 0.12 * save.bridle),
        resist = 0.22 * save.tail, boosts = 1 + save.updraft, eye = 0.12 * save.eye, design = save.design, name = "You" }
end
function R.new_race(n, seed, save)
    local H = R.heat(n)
    local r = rng(seed * 7 + n * 131 + 1)
    local race = { n = n, H = H, t = -R.COUNTDOWN, gates = R.course(n, seed), kites = {}, order = {}, events = {},
        gusts = nil, done = false, next_count = -R.COUNTDOWN, warned = 0, started = 0 }
    race.gusts = make_gusts(H, r)
    race.kites[1] = new_kite(1, R.LAUNCH[1], R.player_kite(save or R.new_save()))
    for i, rv in ipairs(R.RIVALS) do
        local pace = rv.pace * H.rival
        race.kites[i + 1] = new_kite(i + 1, R.LAUNCH[i + 1], { speed = R.SPEED * pace, turn = R.TURN * (0.95 + 0.1 * r()),
            resist = 0.1, ai = { aim = r(-0.35, 0.35), aim2 = r(-0.35, 0.35), lazy = r(0.0, 0.25) }, name = rv.name, design = rv.design })
    end
    return race
end

local function emit(race, ev) race.events[#race.events + 1] = ev end

-- Where a kite stands in the race (for the live place): finished kites by finish time, then gates passed, then
-- distance to the next ring.
function R.progress(race, k)
    if k.finished then return 1e6 - k.finished end
    local g = race.gates[k.gate]
    local d = g and sqrt((k.x - g.x) ^ 2 + (k.h - g.h) ^ 2) or 0
    return k.gate * 1000 - d
end
function R.standings(race)
    local list = {}
    for _, k in ipairs(race.kites) do list[#list + 1] = k end
    table.sort(list, function(a, b)
        local pa, pb = R.progress(race, a), R.progress(race, b)
        if pa ~= pb then return pa > pb end
        return a.i < b.i
    end)
    return list
end
function R.place(race, i)
    for p, k in ipairs(R.standings(race)) do if k.i == i then return p end end
end

-- The AI's steer: toward its aim point in the next ring (each rival aims a little off centre), up and away
-- from the grass when low, and back over the field near its edges.
local function ai_turn(race, k)
    local g = race.gates[k.gate]
    local tx, th
    if g then
        local ai = k.ai
        tx, th = g.x + ai.aim * g.r, g.h + ai.aim2 * g.r
    else
        tx, th = k.launch, R.FIELD.h1 - 3                -- finished: drift up and wait
    end
    local want = atan2(th - k.h, tx - k.x)
    if k.h - R.floor(k.x) < 2.0 and sin(k.a) < 0.4 then want = pi / 2 end
    local d = wrap(want - k.a)
    return clamp(d * 2.6, -1, 1) * (1 - k.ai.lazy * 0.3)
end
R.ai_turn = ai_turn

-- Turn toward a point (the pointer): -1..1.
function R.turn_toward(k, tx, th)
    local d = wrap(atan2(th - k.h, tx - k.x) - k.a)
    if abs(d) < 0.04 then return 0 end
    return clamp(d * 3.5, -1, 1)
end

local function finish_kite(race, k)
    k.finished = race.t
    race.order[#race.order + 1] = k.i
    emit(race, { kind = "finish", k = k.i, place = #race.order })
end

local function fly(race, k, turn, dt, wx, wh)
    if k.crashed > 0 then
        k.crashed = k.crashed - dt
        if k.crashed <= 0 then
            k.crashed = 0
            k.x, k.h, k.a = k.launch, R.floor(k.launch) + 2.6, pi / 2
            emit(race, { kind = "relaunch", k = k.i })
        end
        return
    end
    turn = clamp(turn or 0, -1, 1)
    k.turn = turn
    k.a = wrap(k.a + turn * k.turn_rate * dt)
    local zone = 1 - 0.22 * (k.x / R.FIELD.x1) ^ 2
    local v = k.speed * (1 - R.TURN_COST * abs(turn)) * zone
    if k.boost > 0 then
        v = v * R.BOOST_SPEED
        k.boost = max(0, k.boost - dt)
    end
    local push = 1 - k.resist
    k.x = k.x + (cos(k.a) * v + wx * push) * dt
    k.h = k.h + (sin(k.a) * v + wh * push) * dt
    k.x = clamp(k.x, R.FIELD.x0, R.FIELD.x1)
    if k.h > R.FIELD.h1 then k.h = R.FIELD.h1 end
    if k.h < R.floor(k.x) + R.CLEAR then
        k.h = R.floor(k.x) + R.CLEAR
        k.crashed, k.boost = R.CRASH_TIME, 0
        k.crashes = k.crashes + 1
        emit(race, { kind = "crash", k = k.i, x = k.x, h = k.h })
        return
    end
    if k.finished then return end
    local g = race.gates[k.gate]
    if g then
        local d = sqrt((k.x - g.x) ^ 2 + (k.h - g.h) ^ 2)
        local reach = g.r * (1 + k.eye)
        if d < reach then
            local bull = d < g.r * R.BULLSEYE
            k.passes = k.passes + 1
            if bull then k.bulls = k.bulls + 1 end
            emit(race, { kind = "pass", k = k.i, gate = k.gate, bull = bull })
            k.gate = k.gate + 1
            if k.gate > #race.gates then finish_kite(race, k) end
        end
    end
end

-- Has the race been decided for the player? Sets race.done and race.outcome ("advance" / "out").
local function decide(race)
    if race.done then return end
    local me = race.kites[1]
    local need = race.H.need
    if me.finished then
        local place
        for p, i in ipairs(race.order) do if i == 1 then place = p end end
        race.done, race.place = true, place
        race.outcome = place <= need and "advance" or "out"
    elseif #race.order >= need or race.t >= R.TIME_LIMIT then
        race.done, race.place, race.outcome = true, R.place(race, 1), "out"
    end
    if race.done then
        emit(race, { kind = "decided", outcome = race.outcome, place = race.place })
    end
end

-- One step. input: { turn = -1..1 } or { tx, th } (steer toward a point) and boost = true to spend a burst.
-- Returns this step's events.
function R.step(race, dt, input)
    race.events = {}
    input = input or {}
    local t0 = race.t
    race.t = race.t + dt
    if race.t < 0 then
        while race.next_count <= race.t + 1e-9 and race.next_count < 0 do
            emit(race, { kind = "count", n = floor(-race.next_count + 0.5) })
            race.next_count = race.next_count + 1
        end
        return race.events
    end
    if t0 < 0 then emit(race, { kind = "go" }) end
    -- Gust warnings and starts.
    for i, g in ipairs(race.gusts) do
        if not g.warned and race.t >= g.t0 - R.WARN then g.warned = true; emit(race, { kind = "gust_warn", gust = i }) end
        if not g.started and race.t >= g.t0 then g.started = true; emit(race, { kind = "gust", gust = i }) end
    end
    local wx, wh = R.wind(race)
    for _, k in ipairs(race.kites) do
        local turn
        if k.ai then
            turn = ai_turn(race, k)
            -- Rivals spend their bursts only in later heats, on long straights.
        else
            if input.tx then turn = R.turn_toward(k, input.tx, input.th) else turn = input.turn or 0 end
            if input.boost and k.boosts > 0 and k.boost <= 0 and k.crashed <= 0 then
                k.boosts, k.boost = k.boosts - 1, R.BOOST_TIME
                emit(race, { kind = "boost", k = k.i })
            end
        end
        fly(race, k, turn, dt, wx, wh)
    end
    decide(race)
    return race.events
end

-- The gust that is blowing or about to (for the HUD): gust, seconds until it starts (<= 0 while blowing).
function R.gust_now(race)
    for _, g in ipairs(race.gusts) do
        if race.t < g.t0 + g.dur and race.t >= g.t0 - R.WARN then return g, g.t0 - race.t end
    end
end

------------------------------------------------------------------ runs
R.PLACE_BONUS = { 6, 4, 2, 0 }
function R.race_coins(race)
    local me = race.kites[1]
    local c = me.passes + me.bulls
    if race.outcome == "advance" then c = c + (R.PLACE_BONUS[race.place] or 0) + race.n end
    return c
end

local Run = {}
Run.__index = Run
function R.new_run(save, seed)
    save.runs = save.runs + 1
    return setmetatable({ save = save, heat = 1, seed = seed or (save.runs * 7919 + 13), earned = 0, history = {} }, Run)
end
function Run:new_race()
    self.race = R.new_race(self.heat, self.seed + self.heat * 101, self.save)
    return self.race
end
-- Bank the race's coins; returns "advance" (the next heat is ready) or "over".
function Run:finish_race()
    local race = self.race
    local c = R.race_coins(race)
    self.save.coins = self.save.coins + c
    self.earned = self.earned + c
    race.coins = c
    self.history[#self.history + 1] = { heat = self.heat, place = race.place, coins = c }
    if race.outcome == "advance" then
        self.save.best = max(self.save.best, self.heat)
        self.heat = self.heat + 1
        return "advance"
    end
    return "over"
end

R.Run = Run
return R
