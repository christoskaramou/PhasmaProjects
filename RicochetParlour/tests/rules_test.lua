-- luajit tests/rules_test.lua  (run from the RicochetParlour folder)
local f = assert(io.open("Assets/Scripts/rp_rules.lua", "rb"))
local R = assert(loadstring(f:read("*a"), "@rp_rules.lua"))()
f:close()
local fails = 0
local function check(c, m) if not c then fails = fails + 1; print("FAIL: " .. m) end end
local DT = 1 / 120

local function bare(kind, x, y, vx, vy)
    local g = R.new(1)
    g.balls = {}
    g:take_events()
    g.spawn_t = -1e9                    -- no timed spawns
    local b = g:spawn(kind)
    b.x, b.y, b.vx, b.vy = x, y, vx or 0, vy or 0
    g:take_events()
    return g, b
end
local function run(g, secs, fn)
    for _ = 1, math.floor(secs / DT) do
        if fn then fn(g) end
        g:update(DT)
        if g.state ~= "play" then break end
    end
end
local function has(evs, kind) for _, e in ipairs(evs) do if e.kind == kind then return e end end end

-- 1. Physics: a ball dropped over the slot (no pins in the way) falls through and costs a token.
local g, b = bare("steel", 0, 1.2)
g.pins = {}
local evs = {}
run(g, 3, function(h) for _, e in ipairs(h:take_events()) do evs[#evs + 1] = e end end)
check(has(evs, "lost") and g.tokens == R.TOKENS - 1, "a ball through the slot costs a token")
-- A ball on an apron rolls down into the slot.
g, b = bare("steel", -2.4, 1.3)
g.pins = {}
run(g, 6)
check(g.lost == 1, "a ball on the apron rolls into the slot")
-- Balls stay on the board: long chaotic run, every ball inside the walls.
g = R.new(3)
local inside = true
run(g, 90, function(h)
    for _, q in ipairs(h.balls) do
        if q.x < -3.01 or q.x > 3.01 or q.y > R.H + 0.01 then inside = false end
    end
    h:take_events()
end)
check(inside, "balls never leave the board sideways or through the top")

-- 2. Kicks: under the ball is strong and "close"; at the centre is weaker; empty clicks whiff.
g, b = bare("steel", 0, 3, 0, -3)
local ev = g:kick(0, 3 - R.BALL_R)
check(ev.kind == "kick" and ev.close and b.vy > 7, "a click at the underside is a close, strong kick (vy " .. b.vy .. ")")
local strong = b.vy
g, b = bare("steel", 0, 3, 0, -3)
ev = g:kick(0, 3 + 0.05)
check(ev.kind == "kick" and not ev.close and b.vy < strong, "a click at the centre is a weaker kick")
g, b = bare("steel", 0, 3)
g.streak = 5
ev = g:kick(2, 6)
check(ev.kind == "whiff" and g.streak == 0, "a click on nothing whiffs and breaks the streak")
-- Clicks a little outside the ball still count.
g, b = bare("steel", 0, 3)
check(g:kick(0.35, 2.85).kind == "kick", "clicks just outside the ball still kick it")

-- 3. Ball types.
g, b = bare("iron", 0, 3, 0, -3)
g:kick(0, 3 - R.BALL_R)
check(b.vy < 5, "iron: one kick only half lifts it (vy " .. b.vy .. ")")
b.cooldown = 0
g:kick(b.x, b.y - R.BALL_R)
check(b.vy > 6, "iron: a second kick lifts it")
-- Gold falls faster than steel.
local gs, s1 = bare("steel", 0, 6); gs.pins = {}
local gg, g1 = bare("gold", 0, 6); gg.pins = {}
run(gs, 0.6); run(gg, 0.6)
check(g1.y < s1.y, "gold falls faster than steel")
check(R.TYPES.gold.points == 3, "gold pays triple")
-- Glass: kick, kick again before touching anything -> shatters (a token).
g, b = bare("glass", 0, 4, 0, -2)
g.pins = {}
g:kick(0, 4 - R.BALL_R)
run(g, 0.2)
ev = g:kick(b.x, b.y - R.BALL_R)
check(ev.kind == "shatter" and g.tokens == R.TOKENS - 1, "glass kicked twice in a row shatters")
-- Glass: kick, bounce off something, kick again -> fine.
g, b = bare("glass", 0, 4, 0, -2)
g:kick(0, 4 - R.BALL_R)
b.touched = true          -- as after a pin or wall hit
b.cooldown = 0
check(g:kick(b.x, b.y - R.BALL_R).kind == "kick", "glass kicked after a bounce is fine")

-- 4. Streak and score: consecutive kicks raise the streak and the multiplier.
g, b = bare("steel", 0, 3)
local p1 = g:kick(0, 3 - R.BALL_R).points
for _ = 1, 20 do b.cooldown = 0; b.vy = -2; g:kick(b.x, b.y - R.BALL_R) end
b.cooldown = 0
local p2 = g:kick(b.x, b.y - R.BALL_R).points
check(g.streak == 22 and p2 > p1 * 1.8, "a long streak multiplies points (" .. p1 .. " -> " .. p2 .. ")")

-- 5. Spawning: balls arrive over time, up to the cap; the board never stays empty.
g = R.new(5)
local most = 0
run(g, 200, function(h)
    for _, q in ipairs(h.balls) do q.y = math.max(q.y, 3); if q.vy < 0 then q.vy = 2 end end   -- keep everything alive
    most = math.max(most, #h.balls)
    h:take_events()
end)
check(most == R.MAX_BALLS, "balls build up to the cap (" .. most .. ")")
check(R.spawn_every(0) > R.spawn_every(300), "balls arrive faster later in a run")

-- 6. Balance: an idle player loses; a bot kicking the lowest falling ball survives a good while.
g = R.new(7)
run(g, 300, function(h) h:take_events() end)
check(g.state == "over", "an idle player loses all tokens")
local idle_t = g.t
g = R.new(7)
run(g, 180, function(h)
    h:take_events()
    local low
    for _, q in ipairs(h.balls) do
        if q.vy < 0 and q.y < 2.2 and q.cooldown <= 0 and (q.kind ~= "glass" or q.touched) and (not low or q.y < low.y) then low = q end
    end
    if low then h:kick(low.x, low.y - R.BALL_R) end
end)
print(string.format("idle player lasts %.1f s; bot after %.0f s: state %s, kicks %d, lost %d, score %d, best streak %d, balls %d",
    idle_t, g.t, g.state, g.kicks, g.lost, g.score, g.best_streak, #g.balls))
check(g.t >= 120, "a quick, accurate player survives two minutes (" .. string.format("%.0f", g.t) .. " s)")

-- 7. Bonus cups: a ball through a cup scores it once per pass; a gold ball scores triple.
g, b = bare("steel", R.CUPS[1].x, R.CUPS[1].y + 0.6, 0, -2)
g.pins = {}
local cups = {}
run(g, 0.6, function(h) for _, e in ipairs(h:take_events()) do if e.kind == "cup" then cups[#cups + 1] = e end end end)
check(#cups == 1 and cups[1].points == 50, "a ball through the 50 cup scores 50 once (" .. #cups .. ")")
g, b = bare("gold", R.CUPS[2].x, R.CUPS[2].y + 0.6, 0, -2)
g.pins = {}
cups = {}
run(g, 0.5, function(h) for _, e in ipairs(h:take_events()) do if e.kind == "cup" then cups[#cups + 1] = e end end end)
check(#cups == 1 and cups[1].points == 300, "gold through the 100 cup scores 300")
-- Cups sit clear of every pin.
for _, c in ipairs(R.CUPS) do
    for _, p in ipairs(R.PINS) do
        check(math.sqrt((c.x - p.x) ^ 2 + (c.y - p.y) ^ 2) > c.r + p.r + 0.05, "cup clear of pin at " .. p.x .. "," .. p.y)
    end
end

-- 8. Determinism.
local a, c = R.new(11), R.new(11)
run(a, 20); run(c, 20)
check(a.balls[1].x == c.balls[1].x and a.score == c.score, "same seed, same run")

if fails > 0 then print(fails .. " checks failed"); os.exit(1) end
print("PASS rules")
