-- luajit tests/rules_test.lua  (run from the KiteHill folder)
local R = dofile("Assets/Scripts/kitehill_rules.lua")
local count = 0
local function check(name, f) f(); count = count + 1; print("PASS " .. name) end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local DT = 1 / 60

-- A race with no gusts, started (past the countdown), the player at a chosen spot and heading.
local function calm(n, seed, save)
    local race = R.new_race(n or 1, seed or 1, save)
    race.gusts = {}
    race.t = 0
    return race
end
local function place_kite(k, x, h, a) k.x, k.h, k.a = x, h, a end
-- Fly the player at the next ring's centre (a perfect pointer), climbing off the grass.
local function bot(race)
    local k = race.kites[1]
    local g = race.gates[k.gate]
    if not g then return { turn = 0 } end
    if k.h - R.floor(k.x) < 1.8 and math.sin(k.a) < 0.3 then return { tx = k.x, th = k.h + 5 } end
    return { tx = g.x, th = g.h, boost = race.t > 3 }
end
local function run_race(race, input_fn, limit)
    local t = 0
    while not race.done and t < (limit or 200) do
        R.step(race, DT, input_fn and input_fn(race) or { turn = 0 })
        t = t + DT
    end
    return race
end

check("the ground matches the baked backdrop's (tools/kh_common.py) at sample points", function()
    for _, s in ipairs({ { -13, 12, -0.196552 }, { 0, 12, -0.500258 }, { 13, 12, -0.407358 }, { -6, 4, -0.518838 },
        { 18, 50, 6.864328 }, { -8, 48, 5.600245 }, { 0, -10, 0.757208 } }) do
        assert(near(R.ground(s[1], s[2]), s[3], 1e-5), "ground differs at " .. s[1] .. ", " .. s[2] .. ": " .. R.ground(s[1], s[2]))
    end
    assert(near(R.floor(3), R.ground(3, R.PLANE_Y)), "floor is the ground under the kite plane")
end)

check("heats get harder: more rings, smaller rings, faster rivals, stronger and more frequent gusts", function()
    local last = R.heat(1)
    assert(last.gates == 5 and last.need == 3, "heat 1: five rings, top 3 goes on")
    for n = 2, 14 do
        local h = R.heat(n)
        assert(h.gates >= last.gates and h.radius <= last.radius and h.rival >= last.rival, "heat " .. n .. " is not harder")
        assert(h.gust > last.gust and h.gust_every <= last.gust_every and h.need <= last.need, "heat " .. n .. " gusts / place")
        last = h
    end
    assert(R.heat(14).need == 1 and R.heat(14).gates == 10, "late heats: ten rings, win to go on")
end)

check("courses: deterministic, inside the wind window, clear of the grass, rings shown together apart", function()
    for n = 1, 12 do
        for seed = 1, 15 do
            local a, b = R.course(n, seed), R.course(n, seed)
            assert(#a == R.heat(n).gates, "ring count")
            for i, g in ipairs(a) do
                assert(g.x == b[i].x and g.h == b[i].h, "course not deterministic")
                assert(g.x - g.r >= R.FIELD.x0 and g.x + g.r <= R.FIELD.x1, "ring off the side")
                assert(g.h + g.r <= R.FIELD.h1 and g.h - g.r >= R.floor(g.x) + 1.0, "ring too high or in the grass")
                for j = math.max(1, i - R.SHOWN), i - 1 do
                    local q = a[j]
                    assert(math.sqrt((q.x - g.x) ^ 2 + (q.h - g.h) ^ 2) >= 2 * g.r + 1.0, "rings overlap (" .. n .. "/" .. seed .. ")")
                    assert(math.abs(q.x - g.x) >= g.r + 0.35, "a pole runs through a ring shown with it (" .. n .. "/" .. seed .. ")")
                end
            end
        end
    end
end)

check("flight: along the nose at speed, turning costs speed, the edges are slower, an updraft is faster", function()
    local race = calm()
    local k = race.kites[1]
    place_kite(k, 0, 6, 0)
    R.step(race, 0.1, { turn = 0 })
    assert(near(k.x, R.SPEED * 0.1, 1e-9) and near(k.h, 6, 1e-9), "straight flight at the base speed")
    place_kite(k, 0, 6, math.pi / 2)
    R.step(race, 0.1, { turn = 1 })
    assert(k.a > math.pi / 2, "turn +1 is to the kite's left (anticlockwise)")
    local moved = math.sqrt(k.x ^ 2 + (k.h - 6) ^ 2)
    assert(moved < R.SPEED * 0.1 * 0.75, "a hard turn should slow the kite")
    place_kite(k, 12, 6, math.pi / 2)
    R.step(race, 0.1, { turn = 0 })
    assert(k.h - 6 < R.SPEED * 0.1 * 0.85, "the edge of the wind window is slower")
    place_kite(k, 0, 6, 0)
    local b0 = k.boosts
    R.step(race, 0.1, { turn = 0, boost = true })
    assert(k.boosts == b0 - 1 and k.boost > 0 and k.x > R.SPEED * 0.1 * 1.4, "the updraft spends a charge and speeds up")
    place_kite(k, 0, 6, 0)
    R.step(race, 0.1, { turn = 0, boost = true })
    assert(k.boosts == b0 - 1, "no second updraft while one is blowing")
    -- Pointer steering turns toward the point.
    place_kite(k, 0, 6, 0)
    k.boost = 0
    R.step(race, 0.05, { tx = 0, th = 12 })
    assert(k.a > 0, "steering at a point above turns the kite up")
    -- The wind window: no flying off the sides or the top.
    place_kite(k, R.FIELD.x1 - 0.05, R.FIELD.h1 - 0.05, math.pi / 4)
    R.step(race, 0.2, { turn = 0 })
    assert(k.x <= R.FIELD.x1 and k.h <= R.FIELD.h1, "kept inside the wind window")
end)

check("the grass: a kite that dips into it crashes, then relaunches above its spot", function()
    local race = calm()
    local k = race.kites[1]
    place_kite(k, -2, R.floor(-2) + R.CLEAR + 0.05, -math.pi / 2)
    local evs = R.step(race, 0.05, { turn = 0 })
    local crashed = false
    for _, e in ipairs(evs) do if e.kind == "crash" and e.k == 1 then crashed = true end end
    assert(crashed and k.crashed > 0 and k.crashes == 1, "diving into the grass should crash")
    local x0 = k.x
    R.step(race, 0.5, { turn = 1 })
    assert(k.x == x0, "a crashed kite does not fly")
    local relaunched = false
    for _ = 1, 120 do
        for _, e in ipairs(R.step(race, DT, { turn = 0 })) do if e.kind == "relaunch" and e.k == 1 then relaunched = true end end
        if relaunched then break end
    end
    assert(relaunched and k.crashed == 0 and near(k.x, k.launch) and k.h > R.floor(k.x) + 2, "relaunch above the launch spot")
end)

check("gusts: warned first, then they push every kite; a long tail resists", function()
    local race = R.new_race(3, 4)
    local g = race.gusts[1]
    assert(g and g.t0 > 0 and #race.gusts >= 5, "a heat has gusts")
    local warned_at, started_at
    local t = -R.COUNTDOWN
    while t < g.t0 + 0.1 do
        for _, e in ipairs(R.step(race, DT, { turn = 0 })) do
            if e.kind == "gust_warn" and e.gust == 1 then warned_at = race.t end
            if e.kind == "gust" and e.gust == 1 then started_at = race.t end
        end
        t = t + DT
    end
    assert(warned_at and started_at and started_at - warned_at >= R.WARN - 0.05, "the warning comes first")
    -- Drift with and without the tail.
    local function drift(tail)
        local s = R.new_save(); s.tail = tail
        local r2 = calm(3, 4, s)
        r2.gusts = { { t0 = 0, dur = 2, vx = 4, vh = 0 } }
        local k = r2.kites[1]
        place_kite(k, 0, 8, math.pi / 2)
        r2.t = 1.0
        R.step(r2, 0.1, { turn = 0 })
        return k.x
    end
    local d0, d3 = drift(0), drift(3)
    assert(d0 > 0.3 and d3 > 0 and d3 < d0 * 0.4, "the gust drifts the kite and a long tail resists it")
end)

check("rings count only in order; a pass in the middle is a bullseye", function()
    local race = calm(1, 3)
    local k = race.kites[1]
    local g1, g2 = race.gates[1], race.gates[2]
    place_kite(k, g2.x - 0.2, g2.h, 0)
    R.step(race, DT, { turn = 0 })
    assert(k.gate == 1 and k.passes == 0, "flying through ring 2 first does not count")
    place_kite(k, g1.x - 0.05, g1.h, 0)
    local evs = R.step(race, DT, { turn = 0 })
    local pass
    for _, e in ipairs(evs) do if e.kind == "pass" and e.k == 1 then pass = e end end
    assert(pass and pass.gate == 1 and pass.bull and k.gate == 2 and k.bulls == 1, "ring 1 through the middle")
    place_kite(k, g2.x, g2.h + g2.r * 0.8, 0)
    evs = R.step(race, DT, { turn = 0 })
    pass = nil
    for _, e in ipairs(evs) do if e.kind == "pass" and e.k == 1 then pass = e end end
    assert(pass and not pass.bull and k.gate == 3, "ring 2 near its rim: a pass, not a bullseye")
    -- Keen Eye widens the rings.
    local s = R.new_save(); s.eye = 2
    local r2 = calm(1, 3, s)
    local k2 = r2.kites[1]
    place_kite(k2, r2.gates[1].x, r2.gates[1].h + r2.gates[1].r * 1.1, 0)
    R.step(r2, DT, { turn = 0 })
    assert(k2.gate == 2, "Keen Eye counts a pass just outside the rim")
end)

check("flown through a ring: the middle is a bullseye and the rim is not, at any frame rate", function()
    for _, hz in ipairs({ 20, 30, 60, 144, 240 }) do
        local function fly_at(offset)
            local race = calm(1, 3)
            local k, g = race.kites[1], race.gates[1]
            place_kite(k, g.x - g.r * 1.6, g.h + g.r * offset, 0)
            for _ = 1, hz * 10 do
                R.step(race, 1 / hz, { turn = 0 })
                if k.passes > 0 then break end
            end
            return k
        end
        local mid, rim = fly_at(0.1), fly_at(0.8)
        assert(mid.passes == 1 and mid.bulls == 1, hz .. " Hz: through the middle is a bullseye")
        assert(rim.passes == 1 and rim.bulls == 0, hz .. " Hz: near the rim is a pass only")
    end
end)

check("nobody starts inside ring 1, so nobody gets a free ring at GO", function()
    for n = 1, 12 do
        for seed = 1, 300 do
            local race = R.new_race(n, seed)
            for _, gate in ipairs(race.gates) do        -- a crashed kite relaunches 2.6 above its launch spot
                for _, lx in ipairs(R.LAUNCH) do
                    local d = math.sqrt((lx - gate.x) ^ 2 + (R.floor(lx) + 2.6 - gate.h) ^ 2)
                    assert(d > gate.r * 1.24, "heat " .. n .. " seed " .. seed .. ": a relaunch at " .. lx .. " is inside ring " .. gate.i)
                end
            end
            local g = race.gates[1]
            for _, k in ipairs(race.kites) do
                local d = math.sqrt((k.x - g.x) ^ 2 + (k.h - g.h) ^ 2)
                assert(d > g.r * 1.5, "heat " .. n .. " seed " .. seed .. ": kite " .. k.i .. " starts " .. d .. " from ring 1")
            end
            while race.t <= 0 do R.step(race, DT, { turn = 0 }) end
            R.step(race, DT, { turn = 0 })
            for _, k in ipairs(race.kites) do
                assert(k.passes == 0, "heat " .. n .. " seed " .. seed .. ": kite " .. k.i .. " passed ring 1 right after GO")
            end
        end
    end
end)

check("the countdown ticks 3, 2, 1, then go, and nobody moves before it", function()
    local race = R.new_race(1, 1)
    local counts, go = {}, false
    local x0, h0 = race.kites[2].x, race.kites[2].h
    for _ = 1, math.floor(R.COUNTDOWN / DT) + 3 do
        for _, e in ipairs(R.step(race, DT, { turn = 1 })) do
            if e.kind == "count" then counts[#counts + 1] = e.n end
            if e.kind == "go" then go = true end
        end
        if not go then assert(race.kites[2].x == x0 and race.kites[2].h == h0, "a rival moved before the start") end
    end
    assert(table.concat(counts, ",") == "3,2,1" and go, "countdown " .. table.concat(counts, ","))
end)

check("rivals fly every course to the end, without circling for ever", function()
    for n = 1, 12, 2 do
        for seed = 1, 10 do
            local race = R.new_race(n, seed)
            local t = 0
            while t < 90 do
                R.step(race, DT, { turn = 0 })
                t = t + DT
                local all = true
                for i = 2, 4 do if not race.kites[i].finished then all = false end end
                if all then break end
            end
            for i = 2, 4 do assert(race.kites[i].finished, "rival " .. i .. " did not finish heat " .. n .. " seed " .. seed) end
        end
    end
end)

check("races are decided: win to go on; out as soon as the rivals fill the places that go on", function()
    local race = run_race(R.new_race(1, 2), bot)
    assert(race.done and race.outcome == "advance" and race.place <= 3, "a good flyer goes through heat 1")
    -- An idle player: out once three rivals are home (heat 1 needs top 3).
    local idle = run_race(R.new_race(1, 2), function() return { turn = 0 } end)
    assert(idle.done and idle.outcome == "out" and #idle.order == 3 and idle.place == 4, "idle player is out in 4th")
    -- Heat 7 needs a win: out the moment one rival finishes first.
    local h7 = run_race(R.new_race(7, 2), function() return { turn = 0 } end)
    assert(h7.done and h7.outcome == "out" and #h7.order == 1, "heat 7: out when a rival wins")
end)

check("a perfect flyer clears the early heats on a plain kite and finds the late ones hard", function()
    local adv = { 0, 0 }
    for seed = 1, 12 do
        if run_race(R.new_race(1, seed), bot).outcome == "advance" then adv[1] = adv[1] + 1 end
        if run_race(R.new_race(9, seed), bot).outcome == "advance" then adv[2] = adv[2] + 1 end
    end
    assert(adv[1] == 12, "heat 1 should be fair: " .. adv[1] .. "/12")
    assert(adv[2] <= 4, "heat 9 should be hard on a plain kite: " .. adv[2] .. "/12")
    -- Upgrades make the difference.
    local s = R.new_save()
    s.sail, s.bridle, s.tail, s.updraft, s.eye = 4, 3, 3, 3, 2
    local up = 0
    for seed = 1, 12 do if run_race(R.new_race(9, seed, s), bot).outcome == "advance" then up = up + 1 end end
    assert(up > adv[2] + 4, "a fully upgraded kite should do much better at heat 9: " .. up)
end)

check("runs: coins banked per race, heats go on, the best heat is kept, a lost race ends the run", function()
    local save = R.new_save()
    local run = R.new_run(save, 5)
    assert(save.runs == 1 and run.heat == 1)
    local race = run:new_race()
    run_race(race, bot)
    local coins = R.race_coins(race)
    assert(coins >= race.kites[1].passes + R.PLACE_BONUS[race.place], "coins for rings, bullseyes and the place")
    assert(run:finish_race() == "advance" and run.heat == 2 and save.coins == coins and save.best == 1, "advance banks coins")
    race = run:new_race()
    assert(race.n == 2, "the next race is heat 2")
    run_race(race, function() return { turn = 0 } end)
    local before = save.coins
    assert(run:finish_race() == "over", "losing ends the run")
    assert(save.coins == before + race.kites[1].passes + race.kites[1].bulls and save.best == 1, "a lost race still pays its rings")
end)

check("the workshop: prices rise, coins are spent, upgrades max out, kites are bought then chosen", function()
    local s = R.new_save()
    s.coins = 100
    assert(R.price(s, "sail") == 6 and R.buy(s, "sail") and s.sail == 1 and s.coins == 94, "first sail level")
    assert(R.price(s, "sail") == 10, "the next level costs more")
    for _ = 1, 3 do assert(R.buy(s, "sail")) end
    local ok, why = R.buy(s, "sail")
    assert(not ok and why == "maxed" and s.sail == 4, "sail maxes at 4")
    assert(R.buy(s, "design:sunflower") and s.design == "sunflower" and s.owned.sunflower, "buy a kite")
    local c = s.coins
    assert(R.buy(s, "design:meadow") and s.design == "meadow" and s.coins == c, "choosing an owned kite is free")
    assert(not R.price(s, "design:poppy"), "the rivals' kites are not for sale")
    s.coins = 0
    ok, why = R.buy(s, "bridle")
    assert(not ok and why == "coins" and s.bridle == 0, "no coins, no bridle")
end)

check("the save round-trips and shrugs off junk", function()
    local s = R.new_save()
    s.coins, s.best, s.runs, s.sail, s.eye, s.design = 42, 6, 3, 2, 1, "heather"
    s.owned.heather = true
    local back = R.load_save(R.save_text(s))
    for _, k in ipairs({ "coins", "best", "runs", "sail", "eye", "design" }) do assert(back[k] == s[k], "lost " .. k) end
    assert(back.owned.heather and back.owned.meadow, "owned kites kept")
    local junk = R.load_save("coins=-5\nsail=99\ndesign=poppy\nowned=poppy,zzz\nfoo=bar\n")
    assert(junk.coins == 0 and junk.sail == 4 and junk.design == "meadow", "junk clamped")
    assert(R.load_save(nil).coins == 0, "no save file: a fresh save")
end)

print(count .. " checks passed")
