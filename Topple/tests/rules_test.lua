-- luajit tests/rules_test.lua  (run from the Topple folder)
local R = dofile("Assets/Scripts/topple_rules.lua")
local count = 0
local function check(name, f) f(); count = count + 1; print("PASS " .. name) end

-- An empty table with plenty of every toy.
local function blank(charms)
    local run = R.new_run(1)
    run.tb.layout = {}
    run.charms = charms or {}
    run.dominoes = 200
    run.box = { bell = 20, spring = 20, rocket = 20, marble = 20 }
    return run:new_board(), run
end
local function line(b, x0, y0, n, a, gap_at, gap)
    a = a or 0
    local ids, x, y = {}, x0, y0
    for i = 1, n do
        if gap_at and i == gap_at then x, y = x + math.cos(a) * gap, y + math.sin(a) * gap end
        local p = assert(b:place("domino", x, y, a))
        ids[#ids + 1] = p.id
        x, y = x + math.cos(a) * R.SPACING, y + math.sin(a) * R.SPACING
    end
    return ids, x, y
end
local function fell(res, id) return res.falls[id] ~= nil end

check("tables: targets rise, layouts are deterministic, inside the area and not overlapping", function()
    local last = 0
    for n = 1, 20 do
        local t = R.target(n)
        assert(t > last, "target does not rise at table " .. n); last = t
        local L, again = R.layout(n, 5), R.layout(n, 5)
        assert(#L == #again and #L >= 3, "layout size")
        for i, p in ipairs(L) do
            assert(p.x == again[i].x and p.y == again[i].y and p.kind == again[i].kind, "layout not deterministic")
            assert(R.inside(p.x, p.y, R.LAYOUT), "layout piece outside its area")
            for j = i + 1, #L do
                local q = L[j]
                local need = R.KINDS[p.kind].r + R.KINDS[q.kind].r
                assert((p.x - q.x) ^ 2 + (p.y - q.y) ^ 2 >= need * need, "layout pieces overlap")
            end
        end
    end
    assert(R.target(1) == 40, "table 1 target")
end)

check("placing: crowding and the edge are refused, counts go down and back up, fixed toys stay", function()
    local b, run = blank()
    local left = b.left.domino
    local p = assert(b:place("domino", 0, 0, 0))
    assert(b.left.domino == left - 1)
    assert(not b:place("domino", 0.3, 0, 0), "overlapping domino accepted")
    assert(b:place("domino", R.SPACING, 0, 0), "a domino one spacing on was refused")
    assert(not b:place("domino", 30, 0, 0), "off the table accepted")
    assert(b:remove(p.id) and b.left.domino == left - 1, "remove did not return the domino")
    run.tb.layout = R.layout(1, 1)
    local b2 = run:new_board()
    for _, q in pairs(b2.pieces) do assert(q.fixed and not b2:remove(q.id), "a fixed toy was removed") end
    b2.left.bell = 0
    assert(not b2:place("bell", -11, -5, 0), "placed a toy the box does not have")
end)

check("a straight line of dominoes all falls, in order, one score each", function()
    local b = blank()
    local ids = line(b, -8, 0, 12)
    local res = R.simulate(b)
    assert(res.toppled == 12 and res.score == 12, "toppled " .. res.toppled .. " score " .. res.score)
    for i = 2, #ids do assert(res.falls[ids[i]].t > res.falls[ids[i - 1]].t, "out of order") end
    local per = res.falls[ids[3]].t - res.falls[ids[2]].t
    assert(per > 0.05 and per < 0.2, "chain speed " .. per)
    assert(res.falls[ids[1]].starter and res.falls[ids[1]].contact < 60, "the first domino rests on the second")
    assert(res.falls[ids[12]].contact >= 85, "the last domino lies flat")
end)

check("a gap wider than a domino's reach breaks the chain; Light Touch bridges a small one", function()
    local b = blank()
    local ids = line(b, -8, 0, 10, 0, 6, 0.55)            -- 0.62 + 0.55 apart: too far for a height-1 domino
    local res = R.simulate(b)
    assert(res.toppled == 5, "toppled " .. res.toppled)
    local b2, run = blank({ touch = true })
    line(b2, -8, 0, 10, 0, 6, 0.55)
    assert(R.simulate(b2, run).toppled == 10, "Light Touch did not bridge the gap")
end)

check("a domino struck edge-on only wobbles; one struck from behind falls backwards", function()
    local b = blank()
    line(b, -8, 0, 4)
    local side = assert(b:place("domino", -8 + 4 * R.SPACING, 0, math.pi / 2))
    line(b, -8 + 5 * R.SPACING, 0, 3)
    local res = R.simulate(b)
    assert(not fell(res, side.id) and res.toppled == 4, "edge-on domino fell")
    local wob = false
    for _, ev in ipairs(res.events) do if ev.kind == "wobble" and ev.id == side.id then wob = true end end
    assert(wob, "no wobble event")
    local b2 = blank()
    line(b2, -8, 0, 3)
    local back = assert(b2:place("domino", -8 + 3 * R.SPACING, 0, math.pi))
    local r2 = R.simulate(b2)
    assert(fell(r2, back.id) and r2.falls[back.id].dx > 0.99, "a reversed domino should still fall forward along the push")
end)

check("a bell beside the line rings once and multiplies what falls after it", function()
    local b = blank()
    line(b, -8, 0, 10)
    local bell = assert(b:place("bell", -8 + 2 * R.SPACING + 0.3, 0.75, 0))
    local res = R.simulate(b)
    local rings = 0
    for _, ev in ipairs(res.events) do if ev.kind == "ring" then rings = rings + 1; assert(ev.id == bell.id and ev.mult == 3) end end
    assert(rings == 1, "rings " .. rings)
    assert(res.toppled == 10, "the bell blocked the chain")
    assert(res.score > 10 and res.score < 30, "score " .. res.score)
    -- The window beside a line where a bell may stand and still ring: 0.6 to 1.0 off it.
    for _, off in ipairs({ 0.62, 0.95, 1.1 }) do
        local b3 = blank()
        line(b3, -8, 0, 10)
        assert(b3:place("bell", -8 + 4 * R.SPACING + 0.31, off, math.pi / 2), "a bell " .. off .. " off the line was refused")
        local rang = false
        for _, ev in ipairs(R.simulate(b3).events) do if ev.kind == "ring" then rang = true end end
        assert(rang == (off < 1.0), "a bell " .. off .. " off the line " .. (rang and "rang" or "stayed silent"))
    end
    local _, run = blank({ brass = true })
    local b2 = run:new_board()
    line(b2, -8, 0, 10)
    b2:place("bell", -8 + 2 * R.SPACING + 0.3, 0.75, 0)
    assert(R.simulate(b2, run).score > res.score, "Polished Brass did not raise the score")
end)

check("blocks and trees stop a chain", function()
    for _, kind in ipairs({ "block", "tree" }) do
        local b, run = blank()
        run.tb.layout = { { kind = kind, x = -8 + 5 * R.SPACING + 0.12, y = 0, a = 0 } }
        b = run:new_board()
        line(b, -8, 0, 5)
        line(b, -8 + 6 * R.SPACING + 0.6, 0, 4)
        local res = R.simulate(b, run)
        assert(res.toppled == 5, kind .. " let the chain through: " .. res.toppled)
    end
end)

check("a spring jumps a gap and starts the next line", function()
    local b = blank()
    local _, x = line(b, -8, 0, 5)
    assert(b:place("spring", x + 0.1, 0, 0))
    local after = line(b, x + 0.1 + 2.6, 0, 5)
    local res = R.simulate(b)
    assert(res.toppled == 10, "toppled " .. res.toppled)
    assert(fell(res, after[1]), "the line past the gap did not fall")
end)

check("a rocket lands 5 ahead and knocks over the toys around it", function()
    local b = blank()
    local _, x = line(b, -8, 0, 4)
    local rk = assert(b:place("rocket", x + 0.05, 0, 0))
    local lx = rk.x + R.ROCKET_RANGE
    local a = assert(b:place("domino", lx + 0.5, 0, 0))
    local c = assert(b:place("domino", lx - 0.5, 0, math.pi))
    local far = assert(b:place("domino", lx + 3, 0, 0))
    local res = R.simulate(b)
    assert(fell(res, a.id) and fell(res, c.id), "the landing did not knock the dominoes down")
    assert(not fell(res, far.id), "a far domino fell")
    local land
    for _, ev in ipairs(res.events) do if ev.kind == "launch" then land = ev end end
    assert(land and math.abs(land.lx - lx) < 1e-6 and res.falls[a.id].t >= land.t_land, "launch event")
end)

check("a marble rolls down its chute and on across the felt to the next toy", function()
    local b = blank()
    local _, x = line(b, -8, 0, 4)
    local m = assert(b:place("marble", x + 0.5, 0, 0))
    local after = line(b, m.x + 6, 0, 4)
    local res = R.simulate(b)
    assert(fell(res, after[1]) and res.toppled == 8, "toppled " .. res.toppled)
    local roll
    for _, ev in ipairs(res.events) do if ev.kind == "roll" then roll = ev end end
    assert(roll and not roll.off and roll.dist > 5, "roll event")
    local b2 = blank()
    local _, x2 = line(b2, -8, 0, 3)
    b2:place("marble", x2 + 0.5, 0, 0)
    local r2 = R.simulate(b2)
    for _, ev in ipairs(r2.events) do if ev.kind == "roll" then assert(ev.off, "a marble with nothing ahead should leave the table") end end
end)

check("houses fall far enough to knock the next house over, and score 5 (15 at the Village Fair)", function()
    local b, run = blank()
    run.tb.layout = { { kind = "house", x = 0, y = 0, a = 0 }, { kind = "house", x = 1.95, y = 0, a = 0 } }
    b = run:new_board()
    local _, _ = line(b, -0.7 - 4 * R.SPACING, 0, 4)
    local res = R.simulate(b, run)
    assert(res.score == 4 + 5 + 5, "score " .. res.score)
    run.charms.fair = true
    assert(R.simulate(b, run).score == 4 + 15 + 15, "Village Fair")
end)

check("side-by-side dominoes fork the chain", function()
    local b = blank()
    local _, x = line(b, -8, 0, 4)
    local l = assert(b:place("domino", x, 0.27, 0))
    local r = assert(b:place("domino", x, -0.27, 0))
    line(b, x + R.SPACING, 0.27, 3)
    line(b, x + R.SPACING, -0.27, 3)
    local res = R.simulate(b)
    assert(fell(res, l.id) and fell(res, r.id) and res.toppled == 12, "toppled " .. res.toppled)
end)

check("drawing: the next domino stands one spacing toward the cursor, facing along the stroke", function()
    assert(R.stroke_next(0, 0, 0.3, 0) == nil)
    local x, y, a = R.stroke_next(0, 0, 0, 2)
    assert(math.abs(x) < 1e-9 and math.abs(y - R.SPACING) < 1e-9 and math.abs(a - math.pi / 2) < 1e-9)
end)

check("a run: tips add up to the target, the shop sells, an unmet target ends the run", function()
    local run = R.new_run(3)
    assert(run.tb.tips_left == R.TIPS and run.tb.target == 40)
    assert(run:finish_tip({ score = 15 }) == "again" and run.tb.tips_left == 2)
    assert(run:finish_tip({ score = 30 }) == "cleared" and run.coins > 0)
    local coins = run.coins
    local offers = run:shop_offers()
    assert(#offers == 4)
    local seen = {}
    for _, o in ipairs(offers) do assert(not seen[o.id], "duplicate offer"); seen[o.id] = true end
    run.coins = 100
    for i, o in ipairs(offers) do assert(run:buy(i), "could not buy " .. o.id); assert(not run:buy(i), "bought twice") end
    run.coins = 0
    run:shop_offers()
    assert(not run:buy(1), "bought without coins")
    run:next_table()
    assert(run.table_n == 2 and run.tb.score == 0 and run.tb.target == R.target(2))
    for _ = 1, run.tb.tips_left - 1 do assert(run:finish_tip({ score = 0 }) == "again") end
    assert(run:finish_tip({ score = 0 }) == "over" and run.over)
    assert(coins >= 3)
end)

check("one straight line and the starting bell clear the first tables in a tip or two", function()
    local run = R.new_run(7)
    for n = 1, 3 do
        local tips = 0
        while not run.tb.cleared and run.tb.tips_left > 0 do
            tips = tips + 1
            local b = run:new_board()
            -- Draw left to right through the middle of the table, skipping crowded spots; the bell beside domino 3.
            local x, y, placed = -11.5, -3.5, 0
            while placed < b.left.domino + placed and x < 10.5 do
                if b:place("domino", x, y, 0) then placed = placed + 1 end
                x = x + R.SPACING
            end
            b:place("bell", -11.5 + 2 * R.SPACING + 0.3, y + 0.75, 0)
            local res = R.simulate(b, run)
            assert(res.toppled >= 25, "table " .. n .. ": the line broke at " .. res.toppled)
            run:finish_tip(res)
        end
        print(string.format("  table %d: target %d, scored %d in %d tip(s)", n, run.tb.target, run.tb.score, tips))
        if n <= 2 then assert(run.tb.cleared, "table " .. n .. " not cleared by a plain line") end
        if not run.tb.cleared then break end
        run:next_table()
    end
end)

------------------------------------------------------------------ the bigger toy box: twists, grand tables, charms
check("twists: none at table 1, deterministic, all eight turn up; every 5th table is grand", function()
    assert(R.twist(1, 3) == nil)
    local seen = {}
    for n = 2, 200 do
        local t = R.twist(n, 3)
        assert(R.TWISTS[t], "unknown twist")
        assert(t == R.twist(n, 3), "twist not deterministic")
        seen[t] = true
    end
    for _, id in ipairs(R.TWIST_IDS) do assert(seen[id], "twist never drawn: " .. id) end
    local run = R.new_run(4)
    for _ = 1, 4 do run:next_table() end
    assert(run.table_n == 5 and run.tb.grand and run.tb.target == math.floor(R.target(5) * 1.5 / 10 + 0.5) * 10)
    run.tb.twist = nil
    run.tb.tips_left = 3
    assert(run:finish_tip({ score = run.tb.target }) == "cleared")
    assert(run.tb.reward == 2 * (3 + 2 * 2), "grand tables pay double: " .. tostring(run.tb.reward))
end)

check("twists change the table: echo, festival, market, short box, spare tip, gift box, heavy felt", function()
    local function with(tw, charms)
        local b, run = blank(charms)
        run.tb.twist = tw
        return run:new_board(), run
    end
    local function plain_score(tw)
        local b, run = with(tw)
        line(b, -8, 0, 6)
        return R.simulate(b, run).score
    end
    assert(plain_score("echo") == 2 * plain_score(nil), "echo should start at x2")
    local b, run = with("festival")
    run.tb.layout = { { kind = "house", x = 0, y = 0, a = 0 } }
    b = run:new_board()
    line(b, -0.62 * 4 - 0.8, 0, 4)
    local res = R.simulate(b, run)
    assert(res.score == 4 + 10, "festival house: " .. res.score)
    b, run = with("market")
    line(b, -8, 0, 6)
    b:place("bell", -8 + 2 * R.SPACING + 0.3, 0.75, 0)
    local mk = R.simulate(b, run).score
    b, run = with(nil)
    line(b, -8, 0, 6)
    b:place("bell", -8 + 2 * R.SPACING + 0.3, 0.75, 0)
    assert(mk > R.simulate(b, run).score, "market day did not raise the multiplier")
    b, run = with("shortbox"); assert(b.left.domino == 192)
    b, run = with("gift"); assert(b.left.rocket == 21 and b.left.marble == 21)
    run = R.new_run(1); assert(run:tips_per_table("spare") == R.TIPS + 1)
    -- Heavy felt: a gap the plain reach just bridges stops the chain.
    local function gap_chain(tw)
        local b2, run2 = with(tw)
        line(b2, -8, 0, 3)
        line(b2, -8 + 2 * R.SPACING + 1.02, 0, 3)
        return R.simulate(b2, run2).toppled
    end
    assert(gap_chain(nil) == 6 and gap_chain("heavy") == 3, "heavy felt: " .. gap_chain(nil) .. " / " .. gap_chain("heavy"))
end)

check("new charms: chime, glass, lucky seven, stonemason, long fuse, tight coil, toolbox, thrifty, piggy bank", function()
    local function score(charms, build)
        local b, run = blank(charms)
        build(b, run)
        return R.simulate(b, run)
    end
    local function bell_line(b) line(b, -8, 0, 6); b:place("bell", -8 + 2 * R.SPACING + 0.3, 0.75, 0) end
    assert(score({ chime = true }, bell_line).score > score({}, bell_line).score, "chime")
    local function marble(b) local _, x = line(b, -8, 0, 3); b:place("marble", x + 0.3, 0, 0); line(b, x + 4, 0, 3) end
    assert(score({ glass = true }, marble).score > score({}, marble).score, "glass")
    local function long(b) line(b, -9, 0, 16) end
    local lk = score({ lucky = true }, long)
    assert(lk.mult == 3 and lk.score > score({}, long).score, "lucky seven: mult " .. lk.mult)
    local function blocked(b, run)
        run.tb.layout = { { kind = "block", x = -8 + 5 * R.SPACING + 0.12, y = 0, a = 0 } }
        local b2 = run:new_board(); for k, v in pairs(b2) do b[k] = v end
        line(b, -8, 0, 5)
    end
    assert(score({ mason = true }, blocked).score == 5 + 4, "stonemason")
    local function rocket(b) local _, x = line(b, -8, 0, 3); b:place("rocket", x + 0.2, 0, 0); line(b, x + 0.2 + 7, 0, 3) end
    assert(score({ fuse = true }, rocket).toppled == 6 and score({}, rocket).toppled == 3, "long fuse")
    local function spring(b) local _, x = line(b, -8, 0, 3); b:place("spring", x + 0.1, 0, 0); line(b, x + 0.1 + 4.6, 0, 3) end
    assert(score({ coil = true }, spring).toppled == 6 and score({}, spring).toppled == 3, "tight coil")
    local run = R.new_run(1); run.charms.kit = true; run.box = { bell = 0, spring = 0 }
    local b = run:new_board(); assert(b.left.bell == 1 and b.left.spring == 1, "toolbox")
    run = R.new_run(2); local full = run:shop_offers()
    run.charms.thrift = true; local cheap = run:shop_offers()
    for i = 1, #cheap do assert(cheap[i].price <= full[i].price, "thrifty") end
    run = R.new_run(3); run.charms.piggy = true; run.tb.tips_left = 3
    run:finish_tip({ score = 40 }); assert(run.tb.reward == 3 + 4 + 3, "piggy bank: " .. tostring(run.tb.reward))
    run = R.new_run(5); run.box = { bell = 0, spring = 0, rocket = 0, marble = 0 }
    run.coins = 99; run.offers = { { id = "crate", price = 9 } }
    assert(run:buy(1) and run.box.rocket == 1 and run.box.marble == 1 and run.box.bell == 1, "toy crate")
end)

print(count .. " checks passed")
