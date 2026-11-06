-- luajit tests/rules_test.lua  (run from the ResonanceBreak folder)
local f = assert(io.open("Assets/Scripts/rb_rules.lua", "rb"))
local R = assert(loadstring(f:read("*a"), "@rb_rules.lua"))()
f:close()
local fails = 0
local function check(c, m) if not c then fails = fails + 1; print("FAIL: " .. m) end end

-- Step the clock in 1/120 s ticks; strike every pane at its hit time (+ offset) with its key.
local function autoplay(g, waves, offset, skip_every)
    local struck = {}
    local n = 0
    while g.state == "play" and g.wave <= waves do
        for _, p in ipairs(g.panes) do
            if not p.done and not struck[p] and g.t >= p.t + (offset or 0) then
                struck[p] = true
                n = n + 1
                if not (skip_every and n % skip_every == 0) then g:strike(R.key_at(p, p.t)) end
            end
        end
        g:update(1 / 120)
        g:take_events()
    end
end

-- 1. A perfect player clears waves 1-10 without losing shield; tempo rises; every pane breaks.
local g = R.new(7)
autoplay(g, 10)
check(g.state == "play" and g.wave == 11, "perfect play reaches wave 11 (" .. g.state .. ", wave " .. g.wave .. ")")
check(g.counts.miss == 0 and g.counts.empty == 0, "perfect play misses nothing")
check(g.counts.perfect > 200, "perfect play scores perfects: " .. g.counts.perfect)
check(R.bpm(10) > R.bpm(1) and R.speed(10) > R.speed(1), "tempo and scroll speed rise")
print(string.format("perfect run: score %d, best combo %d, perfects %d, bpm %d -> %d", g.score, g.best_combo, g.counts.perfect, R.bpm(1), R.bpm(10)))

-- 2. Waves contain chords (from wave 2) and shifting panes (from wave 5).
local chords, shifts = 0, 0
for w = 1, 10 do
    local h = R.new(3)
    while h.wave < w do
        for _, q in ipairs(h.panes) do q.done = true end   -- skip ahead without cracking the shield
        h.t = h.wave_end; h:update(0.001); h:take_events()
    end
    for _, p in ipairs(h.panes) do
        if p.wave == w and p.chord then chords = chords + 1; check(w >= 2, "no chords in wave 1") end
        if p.wave == w and p.shift then shifts = shifts + 1; check(w >= 5, "no shifting panes before wave 5") end
    end
end
check(chords > 0 and shifts > 0, "chords and shifting panes appear (" .. chords .. ", " .. shifts .. ")")

-- 3. Judgement windows.
check(R.judge(0.02) == "perfect" and R.judge(-0.07) == "great" and R.judge(0.12) == "good" and R.judge(0.2) == nil, "timing windows")

-- 4. Hand-built lane: strike early, late, wrong key, empty strike, miss.
local function lane_game(panes)
    local h = R.new(1)
    h.panes, h.t, h.wave_end = panes, 0, 999
    h:take_events()
    return h
end
local h = lane_game({ { lane = 2, key = 2, t = 1.0, wave = 1 } })
h.t = 0.95
local ev = h:strike(2)
check(ev.kind == "break" and ev.judge == "great" and ev.early, "50 ms early is a great")
h = lane_game({ { lane = 2, key = 2, t = 1.0, wave = 1 } })
h.t = 1.0
check(h:strike(3).kind == "empty" and h.combo == 0, "wrong fork is an empty strike")
check(h:strike(2).judge == "perfect", "right fork on time is perfect")
h = lane_game({ { lane = 1, key = 1, t = 1.0, wave = 1 } })
h:update(1.2)
check(h.shield == R.SHIELD - 1 and h.counts.miss == 1, "a pane past the window cracks the shield")
-- Chords need both forks.
h = lane_game({ { lane = 1, key = 1, t = 1.0, wave = 1, chord = true }, { lane = 3, key = 3, t = 1.0, wave = 1, chord = true } })
h.t = 1.0
h:strike(1)
h:update(0.2)
check(h.shield == R.SHIELD - 1, "striking one fork of a chord lets the other crack")
-- Shifting pane: the key is the colour at arrival, not the lane.
local p = { lane = 1, key = 1, t = 2.0, wave = 5, shift = true, shift_dt = 0.25, shift0 = 0.0, shift_from = 2 }
p.key = R.key_at(p, p.t)
check(p.key == 2 and R.key_at(p, 0.3) == 3, "shifting key cycles every half beat")
h = lane_game({ p })
h.t = 2.0
check(h:strike(1).kind == "empty", "the lane's own fork does not break a shifted pane")
check(h:strike(p.key).kind == "break", "the arrival colour's fork breaks it")

-- 5. Losing: a player who never strikes runs out of shield.
g = R.new(5)
for _ = 1, 120 * 40 do g:update(1 / 120); g:take_events(); if g.state ~= "play" then break end end
check(g.state == "over" and g.shield == 0, "no strikes loses the game")
-- A player missing every 4th pane survives early waves thanks to the repair between waves?
g = R.new(5)
autoplay(g, 3, 0.03, 9)
check(g.wave >= 3, "a sloppy player still gets through early waves (wave " .. g.wave .. ", " .. g.state .. ")")

-- 6. Determinism.
local a, b = R.new(11), R.new(11)
check(#a.panes == #b.panes and a.panes[5].t == b.panes[5].t and a.panes[5].lane == b.panes[5].lane, "same seed, same song")

if fails > 0 then print(fails .. " checks failed"); os.exit(1) end
print("PASS rules")
