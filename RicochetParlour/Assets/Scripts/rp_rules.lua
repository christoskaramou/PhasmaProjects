-- Ricochet Parlour rules: balls ricochet on an upright bagatelle board and fall toward an open slot at
-- the bottom. Click a ball to kick it back up; a click nearer its underside kicks harder and scores more.
-- Pure Lua (no engine calls) so tests run under luajit.
--
-- Board space: x in [-3, 3], y up from 0 (bottom rail) to 8 (top of the arch). The slot is |x| < SLOT.
local R = {}
local floor, min, max, abs, sqrt = math.floor, math.min, math.max, math.abs, math.sqrt

R.W, R.H = 6, 8
R.BALL_R = 0.2
R.SLOT = 0.55
R.TOKENS = 3
R.MAX_BALLS = 7
R.KICK_REACH = 0.28        -- clicks this far outside a ball still count
R.KICK_V = 7.6             -- upward speed of a full kick
R.GRAVITY = 5.5
R.VMAX = 14
R.TYPES = {
    steel = { kick = 1.0, gravity = 1.0, points = 1 },
    iron  = { kick = 0.55, gravity = 1.1, points = 2 },   -- heavy: one kick only slows it, two lift it
    glass = { kick = 1.0, gravity = 0.95, points = 2 },   -- shatters if kicked twice without touching anything
    gold  = { kick = 1.0, gravity = 1.5, points = 3 },    -- falls fast, pays triple
}

local function rng(seed)
    local s = (seed * 1103515245 + 12345) % 2147483648
    local r = {}
    function r.next() s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 end
    function r.range(a, b) return a + (b - a) * r.next() end
    return r
end

------------------------------------------------------------------ board geometry
-- Pins: a staggered field; every third is a rubber bumper (livelier bounce).
local function make_pins()
    local pins = {}
    for row = 0, 5 do
        local y = 1.6 + row * 0.95
        local n = row % 2 == 0 and 5 or 4
        for i = 0, n - 1 do
            local x = (i - (n - 1) / 2) * 1.05
            local rubber = (row + i) % 3 == 0
            pins[#pins + 1] = { x = x, y = y, r = rubber and 0.16 or 0.07, e = rubber and 1.08 or 0.72, rubber = rubber }
        end
    end
    return pins
end

-- Segments (walls, aprons) as { ax, ay, bx, by, e }. The top is an arch of short segments.
-- The arched top: a half-ellipse; its peak sits just under the top rail so the walnut blocks show.
R.ARCH = { cy = 6.3, rx = 3, ry = 1.55 }
local function make_walls()
    local s = {}
    local function seg(ax, ay, bx, by, e) s[#s + 1] = { ax, ay, bx, by, e or 0.7 } end
    local A = R.ARCH
    seg(-3, 0.95, -3, A.cy); seg(3, 0.95, 3, A.cy)
    local n = 16
    for k = 0, n - 1 do
        local a0, a1 = math.pi * k / n, math.pi * (k + 1) / n
        seg(math.cos(a0) * A.rx, A.cy + math.sin(a0) * A.ry, math.cos(a1) * A.rx, A.cy + math.sin(a1) * A.ry, 0.75)
    end
    -- Aprons slope down from the side walls to the slot.
    seg(-3, 0.95, -R.SLOT, 0.42, 0.45); seg(3, 0.95, R.SLOT, 0.42, 0.45)
    return s
end
R.PINS, R.WALLS = make_pins(), make_walls()
-- Bonus cups: brass rings on the felt. A ball passing through the middle scores the plate's value.
R.CUPS = { { x = -1.8, y = 3.1, r = 0.3, points = 50 }, { x = 1.82, y = 3.98, r = 0.3, points = 100 } }
R.CUP_HIT = 0.17       -- a ball centre this close to a cup's centre goes through it

------------------------------------------------------------------ game
local Game = {}
Game.__index = Game

function R.new(seed)
    local g = setmetatable({ rng = rng(seed or 1), t = 0, balls = {}, events = {}, next_id = 0,
        score = 0, streak = 0, best_streak = 0, tokens = R.TOKENS, state = "play", kicks = 0, lost = 0,
        spawn_t = 0, pins = R.PINS, walls = R.WALLS }, Game)
    g:spawn("steel")
    return g
end

-- Spawn interval shortens as the run goes on.
function R.spawn_every(t) return max(9, 20 - t / 15) end

function Game:pick_type()
    local r, t = self.rng.next(), self.t
    if t > 40 and r < 0.12 then return "gold" end
    if t > 60 and r < 0.32 then return "iron" end
    if #self.balls >= 2 and r < 0.52 then return "glass" end
    return "steel"
end

function Game:spawn(kind)
    self.next_id = self.next_id + 1
    local b = { id = self.next_id, kind = kind or self:pick_type(), x = self.rng.range(-1.2, 1.2), y = 7.2,
        vx = self.rng.range(-1.5, 1.5), vy = 0, touched = true, cooldown = 0, age = 0 }
    self.balls[#self.balls + 1] = b
    self.events[#self.events + 1] = { kind = "spawn", ball = b }
    return b
end

local function reflect(b, nx, ny, e)
    local vn = b.vx * nx + b.vy * ny
    if vn < 0 then
        b.vx, b.vy = b.vx - (1 + e) * vn * nx, b.vy - (1 + e) * vn * ny
        return -vn
    end
    return 0
end

-- Push b out of a circle obstacle; returns impact speed (0 if none).
local function hit_circle(b, cx, cy, cr, e)
    local dx, dy = b.x - cx, b.y - cy
    local rr = cr + R.BALL_R
    local d2 = dx * dx + dy * dy
    if d2 >= rr * rr or d2 < 1e-12 then return 0 end
    local d = sqrt(d2)
    local nx, ny = dx / d, dy / d
    b.x, b.y = cx + nx * rr, cy + ny * rr
    return reflect(b, nx, ny, e)
end

local function hit_segment(b, s)
    local ax, ay, bx, by, e = s[1], s[2], s[3], s[4], s[5]
    local ex, ey = bx - ax, by - ay
    local L2 = ex * ex + ey * ey
    local u = max(0, min(1, ((b.x - ax) * ex + (b.y - ay) * ey) / L2))
    return hit_circle(b, ax + ex * u, ay + ey * u, 0, e)
end

function Game:step(dt)
    local events = self.events
    for _, b in ipairs(self.balls) do
        local def = R.TYPES[b.kind]
        b.age = b.age + dt
        b.cooldown = max(0, b.cooldown - dt)
        b.cups = b.cups or {}
        b.vy = b.vy - R.GRAVITY * def.gravity * self:gravity_scale() * dt
        local sp = sqrt(b.vx * b.vx + b.vy * b.vy)
        if sp > R.VMAX then b.vx, b.vy = b.vx / sp * R.VMAX, b.vy / sp * R.VMAX end
        b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
        for _, p in ipairs(self.pins) do
            local imp = hit_circle(b, p.x, p.y, p.r, p.e)
            if imp > 0.4 then b.touched = true; events[#events + 1] = { kind = "pin", ball = b, pin = p, speed = imp } end
        end
        for _, s in ipairs(self.walls) do
            local imp = hit_segment(b, s)
            if imp > 0.4 then b.touched = true; events[#events + 1] = { kind = "wall", ball = b, speed = imp } end
        end
        -- Bonus cups: once per pass (the ball must leave the ring before it can score it again).
        for ci, c in ipairs(R.CUPS) do
            local inside = (b.x - c.x) ^ 2 + (b.y - c.y) ^ 2 < R.CUP_HIT * R.CUP_HIT
            if inside and not b.cups[ci] then
                b.cups[ci] = true
                local pts = c.points * def.points
                self.score = self.score + pts
                events[#events + 1] = { kind = "cup", ball = b, cup = c, points = pts }
            elseif not inside and b.cups[ci] and (b.x - c.x) ^ 2 + (b.y - c.y) ^ 2 > (c.r + 0.05) ^ 2 then
                b.cups[ci] = nil
            end
        end
        -- Safety: never leave the board sideways or through the top.
        if b.x < -3 + R.BALL_R then b.x = -3 + R.BALL_R; b.vx = abs(b.vx) * 0.6 end
        if b.x > 3 - R.BALL_R then b.x = 3 - R.BALL_R; b.vx = -abs(b.vx) * 0.6 end
        if b.y > R.H - R.BALL_R then b.y = R.H - R.BALL_R; b.vy = -abs(b.vy) * 0.6 end
    end
    -- Ball-ball: equal-mass elastic-ish collisions (iron counts double).
    local bs = self.balls
    for i = 1, #bs do
        for j = i + 1, #bs do
            local a, c = bs[i], bs[j]
            local dx, dy = c.x - a.x, c.y - a.y
            local d2 = dx * dx + dy * dy
            local rr = 2 * R.BALL_R
            if d2 < rr * rr and d2 > 1e-12 then
                local d = sqrt(d2)
                local nx, ny = dx / d, dy / d
                local ma, mc = a.kind == "iron" and 2 or 1, c.kind == "iron" and 2 or 1
                local push = (rr - d) / 2
                a.x, a.y, c.x, c.y = a.x - nx * push, a.y - ny * push, c.x + nx * push, c.y + ny * push
                local rv = (c.vx - a.vx) * nx + (c.vy - a.vy) * ny
                if rv < 0 then
                    local j_ = -(1 + 0.85) * rv / (1 / ma + 1 / mc)
                    a.vx, a.vy = a.vx - j_ / ma * nx, a.vy - j_ / ma * ny
                    c.vx, c.vy = c.vx + j_ / mc * nx, c.vy + j_ / mc * ny
                    a.touched, c.touched = true, true
                    if -rv > 0.6 then events[#events + 1] = { kind = "clack", a = a, b = c, speed = -rv } end
                end
            end
        end
    end
    -- Drops: a ball below the rail (through the slot) is lost.
    for i = #bs, 1, -1 do
        local b = bs[i]
        if b.y < -0.3 then
            table.remove(bs, i)
            self:lose(b, "drop")
        end
    end
end

function Game:gravity_scale() return 1 + min(0.45, self.t / 400) end

function Game:lose(b, why)
    self.tokens = self.tokens - 1
    self.lost = self.lost + 1
    self.streak = 0
    self.events[#self.events + 1] = { kind = "lost", ball = b, why = why }
    if self.tokens <= 0 then
        self.state = "over"
        self.events[#self.events + 1] = { kind = "over" }
    end
end

function Game:update(dt)
    if self.state ~= "play" then return end
    self.t = self.t + dt
    local n = max(1, math.ceil(dt / (1 / 240)))
    for _ = 1, n do
        self:step(dt / n)
        if self.state ~= "play" then return end
    end
    -- Score trickles in for every ball kept alive.
    self.score = self.score + floor(10 * #self.balls * dt * 100) / 100
    -- New balls arrive on a timer, and at once if the board empties.
    self.spawn_t = self.spawn_t + dt
    if (#self.balls < R.MAX_BALLS and self.spawn_t >= R.spawn_every(self.t)) or #self.balls == 0 then
        self.spawn_t = 0
        self:spawn()
    end
end

-- Click at board point (px, py). Kicks the ball under the click (nearest within reach).
-- Returns the kick event, or a "whiff" event (which breaks the streak).
function Game:kick(px, py)
    if self.state ~= "play" then return nil end
    local best, bd
    for _, b in ipairs(self.balls) do
        local d = sqrt((px - b.x) ^ 2 + (py - b.y) ^ 2)
        if d <= R.BALL_R + R.KICK_REACH and b.cooldown <= 0 and (not bd or d < bd) then best, bd = b, d end
    end
    if not best then
        self.streak = 0
        local ev = { kind = "whiff", x = px, y = py }
        self.events[#self.events + 1] = ev
        return ev
    end
    local b = best
    -- Glass: a second kick before it touches anything shatters it.
    if b.kind == "glass" and not b.touched then
        for i, o in ipairs(self.balls) do if o == b then table.remove(self.balls, i) break end end
        self.events[#self.events + 1] = { kind = "shatter", ball = b }
        self:lose(b, "shatter")
        return { kind = "shatter", ball = b }
    end
    local def = R.TYPES[b.kind]
    -- Closeness: 1 when the click is at (or under) the ball's bottom, 0 at its centre or above.
    local q = max(0, min(1, (b.y - py) / R.BALL_R))
    local power = def.kick * (0.65 + 0.35 * q)
    b.vy = max(b.vy, 0) * (b.kind == "iron" and 0.85 or 0.3) + R.KICK_V * power   -- iron keeps rising speed: kicks stack
    b.vx = b.vx * 0.6 + (b.x - px) * 6
    b.touched = false
    b.cooldown = 0.12
    self.kicks = self.kicks + 1
    self.streak = self.streak + 1
    self.best_streak = max(self.best_streak, self.streak)
    local base = 50 + floor(100 * q)
    local pts = floor(base * def.points * (1 + min(2, self.streak / 20)))
    self.score = self.score + pts
    local ev = { kind = "kick", ball = b, quality = q, close = q >= 0.6, points = pts, x = px, y = py }
    self.events[#self.events + 1] = ev
    return ev
end

function Game:take_events()
    local e = self.events
    self.events = {}
    return e
end

return R
