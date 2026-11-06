-- Resonance Break rules: glass panes slide down four lanes toward a strike line; strike the tuning fork
-- whose colour matches each pane as it arrives. Pure Lua (no engine calls) so tests run under luajit.
--
-- Time is in seconds of song time. A pane has a hit time; it reaches the strike line then.
-- A pane's "key" is the fork that breaks it: normally its lane's colour, but shifting panes cycle
-- colours and the key is the colour they show at the hit time.
local R = {}
local floor, min, max, abs = math.floor, math.min, math.max, math.abs

R.LANES = 4
R.WINDOW = { perfect = 0.045, great = 0.09, good = 0.135 }   -- seconds either side of the hit time
R.POINTS = { perfect = 300, great = 200, good = 100 }
R.SHIELD = 5
R.WAVE_PANES = 24
R.BREAK = 2.4            -- seconds between waves
R.LEAD = 2.0             -- a pane is visible this long before its hit time

local function rng(seed)
    local s = (seed * 1103515245 + 12345) % 2147483648
    local r = {}
    function r.next() s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 end
    function r.int(a, b) return a + floor(r.next() * (b - a + 1)) end
    return r
end

-- Tempo per wave: starts relaxed, climbs, then keeps climbing slowly.
function R.bpm(wave) return min(196, 92 + (wave - 1) * 10 - max(0, wave - 8) * 4) end
-- How far (world units) a pane travels per second: faster songs scroll faster.
function R.speed(wave) return 6 + (R.bpm(wave) - 92) * 0.05 end

-- Shifting panes cycle their colour every half beat; key at time t.
function R.key_at(p, t)
    if not p.shift then return p.key end
    local step = floor((t - p.shift0) / p.shift_dt)
    return (p.shift_from - 1 + max(0, step)) % R.LANES + 1
end

-- Build one wave of panes starting at song time t0.
local function make_wave(wave, t0, seed)
    local r = rng(seed + wave * 977)
    local beat = 60 / R.bpm(wave)
    local panes = {}
    local t = t0 + beat * 2
    local last = 0
    local n = 0
    while n < R.WAVE_PANES do
        -- Rhythm: quarter notes early; eighths and the odd rest later.
        local step = beat
        if wave >= 3 and r.next() < 0.25 + 0.04 * min(wave, 10) then step = beat / 2 end
        if r.next() < 0.08 then step = step + beat end
        local lane
        repeat lane = r.int(1, R.LANES) until lane ~= last or r.next() < 0.25
        last = lane
        local chord = wave >= 2 and r.next() < min(0.35, 0.08 + 0.04 * wave)
        local p = { lane = lane, key = lane, t = t, wave = wave }
        if wave >= 5 and not chord and r.next() < min(0.3, 0.06 * (wave - 4)) then
            -- Shifting pane: cycles colours; the key is the colour it shows when it arrives.
            p.shift = true
            p.shift_dt = beat / 2
            p.shift0 = t - R.LEAD
            p.shift_from = r.int(1, R.LANES)
            p.key = R.key_at(p, t)
        end
        panes[#panes + 1] = p
        n = n + 1
        if chord and n < R.WAVE_PANES then
            local other
            repeat other = r.int(1, R.LANES) until other ~= lane
            panes[#panes + 1] = { lane = other, key = other, t = t, wave = wave, chord = true }
            p.chord = true
            n = n + 1
        end
        t = t + step
    end
    return panes, t + beat
end

local Game = {}
Game.__index = Game

function R.new(seed)
    local g = setmetatable({ seed = seed or 1, t = -1.5, wave = 0, panes = {}, events = {},
        score = 0, combo = 0, best_combo = 0, shield = R.SHIELD, state = "play", counts = { perfect = 0, great = 0, good = 0, miss = 0, empty = 0 } }, Game)
    g:next_wave(0)
    return g
end

function Game:next_wave(t0)
    self.wave = self.wave + 1
    local panes, t_end = make_wave(self.wave, t0, self.seed)
    for _, p in ipairs(panes) do self.panes[#self.panes + 1] = p end
    self.wave_end = t_end
    self.events[#self.events + 1] = { kind = "wave", wave = self.wave, bpm = R.bpm(self.wave), t = t0 }
end

function Game:multiplier() return 1 + min(3, floor(self.combo / 20)) end

local function judge(dt)
    dt = abs(dt)
    if dt <= R.WINDOW.perfect then return "perfect" end
    if dt <= R.WINDOW.great then return "great" end
    if dt <= R.WINDOW.good then return "good" end
end

-- Strike fork `key` at the current time. Breaks the closest unresolved pane with that key inside the
-- window; a strike with nothing to break is "empty" and breaks the combo (spam does not pay).
function Game:strike(key)
    if self.state ~= "play" then return nil end
    local best, bd
    for _, p in ipairs(self.panes) do
        if not p.done and R.key_at(p, p.t) == key then
            local d = abs(p.t - self.t)
            if d <= R.WINDOW.good and (not bd or d < bd) then best, bd = p, d end
        end
    end
    local ev
    if best then
        local j = judge(self.t - best.t)
        best.done, best.result = true, j
        self.combo = self.combo + 1
        self.best_combo = max(self.best_combo, self.combo)
        self.score = self.score + R.POINTS[j] * self:multiplier()
        self.counts[j] = self.counts[j] + 1
        ev = { kind = "break", pane = best, judge = j, key = key, early = self.t < best.t }
    else
        self.combo = 0
        self.counts.empty = self.counts.empty + 1
        ev = { kind = "empty", key = key }
    end
    self.events[#self.events + 1] = ev
    return ev
end

-- Advance song time. Panes past the window crack against the shield.
function Game:update(dt)
    if self.state ~= "play" then return end
    self.t = self.t + dt
    for _, p in ipairs(self.panes) do
        if not p.done and self.t > p.t + R.WINDOW.good then
            p.done, p.result = true, "miss"
            self.combo = 0
            self.shield = self.shield - 1
            self.counts.miss = self.counts.miss + 1
            self.events[#self.events + 1] = { kind = "crack", pane = p }
            if self.shield <= 0 then
                self.state = "over"
                self.events[#self.events + 1] = { kind = "over" }
                return
            end
        end
    end
    -- Drop resolved panes well behind the line.
    for i = #self.panes, 1, -1 do
        local p = self.panes[i]
        if p.done and self.t > p.t + 1.5 then table.remove(self.panes, i) end
    end
    if self.t >= self.wave_end then
        local clean = true
        for _, p in ipairs(self.panes) do if p.wave == self.wave and p.result == "miss" then clean = false end end
        if self.shield < R.SHIELD then self.shield = self.shield + 1; self.events[#self.events + 1] = { kind = "repair" } end
        self.events[#self.events + 1] = { kind = "wave_clear", wave = self.wave, clean = clean }
        self:next_wave(self.t + R.BREAK)
    end
end

function Game:take_events()
    local e = self.events
    self.events = {}
    return e
end

-- Panes in view: { pane, distance-to-line in seconds } (0 at the strike line, R.LEAD far away).
function Game:visible()
    local out = {}
    for _, p in ipairs(self.panes) do
        local ahead = p.t - self.t
        if ahead <= R.LEAD and (not p.done or ahead > -0.4) then out[#out + 1] = p end
    end
    return out
end

R.judge = judge
return R
