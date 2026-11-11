-- Topple traps: run from the Topple folder with luajit. Each trap kind in a minimal scene of its own, in a test room:
-- an open floor, and a desk and a shelf 4 high with a gap of 4 between them.
local F = dofile("Assets/Scripts/topple_free.lua")
F.set_room({
    bounds = { x0 = -60, x1 = 60, y0 = -40, y1 = 40 },
    surfaces = {
        { name = "floor", x0 = -60, x1 = 60, y0 = -40, y1 = 40, h = 0, edge = false },
        { name = "desk", x0 = -30, x1 = 0, y0 = -10, y1 = 10, h = 4, edge = true },
        { name = "shelf", x0 = 4, x1 = 30, y0 = -10, y1 = 10, h = 4, edge = true },
    },
    solids = {
        { name = "desk", x0 = -30, x1 = 0, y0 = -10, y1 = 10, z0 = 0, z1 = 4 },
        { name = "shelf", x0 = 4, x1 = 30, y0 = -10, y1 = 10, z0 = 0, z1 = 4 },
    },
})
local checks = 0
local function check(v, msg) assert(v, msg); checks = checks + 1 end
local function paint() return "cream" end
local SP = F.SPACING

-- The first event for a trap (optionally of one kind).
local function ev(res, id, event)
    for _, e in ipairs(res.traps) do if e.id == id and (not event or e.event == event) then return e end end
end
local function fell(res, list)
    local n = 0
    for _, p in ipairs(list) do if res.falls[p.id] then n = n + 1 end end
    return n
end
-- A straight row of n dominoes from (x, y) along +x on height h; returns them in order.
local function row(b, x, y, h, n, k)
    local out = {}
    for i = 0, n - 1 do out[#out + 1] = assert(b:place(x + i * SP * (k or 1), y, 0, h, "cream", k), "row domino " .. i) end
    return out
end
local function times_ordered(res)
    for i = 2, #res.traps do if res.traps[i].t < res.traps[i - 1].t then return false end end
    return true
end

------------------------------------------------------------------ string: cut by a domino
do
    local b = F.new_board()
    local x0, y = -50, -20
    local gx = x0 + 5 * SP + SP / 2          -- between the 6th and 7th dominoes
    b:add_trap({ kind = "string", id = "s", a = { gx, y - 2, 0.6 }, b = { gx, y + 2, 0.6 } })
    local _, why = b:place(gx, y, 0, 0, "cream")
    check(why == "trap", "a domino cannot stand through a string, got " .. tostring(why))
    local line = row(b, x0, y, 0, 12)
    check(#line == 12, "a row fits under the string, either side of it")
    local res = F.simulate(b)
    local e = ev(res, "s", "cut")
    check(e and e.by == "domino" and e.kind == "string", "a falling domino cuts the string")
    check(e.t > res.falls[line[6].id].t and e.t < res.falls[line[7].id].t + 0.2, "when the domino under it falls, at " .. e.t)
    check(math.abs(e.x - gx) < 0.05 and math.abs(e.h - 0.6) < 0.05 and math.abs(e.y - y) < 0.3, "where it crossed")
    check(res.toppled == 12, "and the chain runs on through")
    -- The same row stopping short of the string leaves it.
    local b2 = F.new_board()
    b2:add_trap({ kind = "string", id = "s", a = { gx, y - 2, 0.6 }, b = { gx, y + 2, 0.6 } })
    row(b2, x0, y, 0, 4)
    check(ev(F.simulate(b2), "s") == nil, "a chain that never reaches it leaves the string")
    -- A string high over the row is out of reach.
    local b3 = F.new_board()
    b3:add_trap({ kind = "string", id = "s", a = { gx, y - 2, 1.2 }, b = { gx, y + 2, 1.2 } })
    row(b3, x0, y, 0, 12)
    check(ev(F.simulate(b3), "s") == nil, "a string above the dominoes' reach stays")
end

------------------------------------------------------------------ string: cut by a ball
local function ball_scene(with_string)
    local b = F.new_board()
    local y = -26
    if with_string then b:add_trap({ kind = "string", id = "s", a = { -31, y - 2, 0.5 }, b = { -31, y + 2, 0.5 } }) end
    local line = row(b, -40, y, 0, 7)
    local last = line[#line]
    assert(b:place_ball(last.x + 0.95, y, 0), "ball")
    return b
end
do
    local res = F.simulate(ball_scene(true))
    local e = ev(res, "s", "cut")
    check(res.balls_launched == 1, "the line launches the ball")
    check(e and e.by == "ball" and math.abs(e.x + 31) < 0.05, "a rolling ball cuts the string it rolls through")
    local bres = F.simulate(ball_scene(false))
    local bt = res.balls[1]
    check(bt and bres.balls[1] and math.abs(bt.x - bres.balls[1].x) < 1e-9, "a string does not stop the ball")
end

------------------------------------------------------------------ string: cut by an edge diver
do
    local b = F.new_board()
    -- (in the gap between desk and shelf, under the desk's edge)
    b:add_trap({ kind = "string", id = "s", a = { 0.6, -2, 2 }, b = { 0.6, 2, 2 } })
    b:place_line(-6, 0, -0.3, 0, paint, 4)
    local res = F.simulate(b)
    check(#res.lands == 1, "the last domino on the desk dives off its edge")
    local e = ev(res, "s", "cut")
    check(e and e.by == "dive", "a domino diving off the edge cuts the string it falls through, by " .. tostring(e and e.by))
    local land = res.lands[1]
    local f = res.falls[land.id]
    check(e.t > f.dive.t0 and e.t < f.dive.t1, "while it is in the air")
end

------------------------------------------------------------------ weight: presses a switch
local function weight_switch(with_line)
    local b = F.new_board()
    b:add_trap({ kind = "weight", id = "w", x = -20, y = -30, h = 6, r = 0.5 })
    local sx = -26 + 4 * SP + SP / 2
    b:add_trap({ kind = "string", id = "s", a = { sx, -36, 0.6 }, b = { sx, -32, 0.6 }, holds = "w" })
    b:check_traps()
    local start = row(b, -26, -34, 0, with_line and 8 or 1)
    local sw = assert(b:place_switch(-20, -30, 0), "a switch fits under the weight")
    local target = row(b, -14, -30, 0, 10)
    b:link_switch(sw, target[1].id)
    b.start = { id = start[1].id, dir = 1 }
    return b, sw, target
end
do
    local b, sw, target = weight_switch(true)
    local _, why = b:place(-20, -30, 0, 6.2, "cream")
    check(why == "trap" or why == "air", "nothing in the weight's body")
    local _, w2 = b:place_ball(-20, -30, 5.8)
    check(w2 == "trap" or w2 == "air", "no ball in it either")
    local res = F.simulate(b)
    local cutx, drop, land = ev(res, "s", "cut"), ev(res, "w", "drop"), ev(res, "w", "land")
    check(cutx and cutx.holds == "w" and drop and land, "cutting the string drops the weight")
    check(drop.t == cutx.t and math.abs(drop.z - 0.8) < 1e-6 and math.abs(drop.t1 - land.t) < 1e-9, "it falls onto the switch's top, from " .. drop.h .. " to " .. drop.z)
    check(math.abs((land.t - drop.t) - math.sqrt(2 * (6 - 0.8) / F.BALL.g)) < 1e-9, "in free fall")
    check(math.abs(F.weight_height(drop, drop.t) - 6) < 1e-9 and math.abs(F.weight_height(drop, land.t + 1) - 0.8) < 1e-9, "weight_height follows it")
    local pressed
    for _, e in ipairs(res.switches) do if e.id == sw.id then pressed = e end end
    check(pressed and math.abs(pressed.t - land.t) < 1e-9, "the switch is pressed as it lands")
    check(fell(res, target) == 10, "and starts its line")
    check(times_ordered(res), "res.traps is time-ordered")
    local b2, sw2, target2 = weight_switch(false)
    local res2 = F.simulate(b2)
    check(ev(res2, "w") == nil and #res2.switches == 0 and fell(res2, target2) == 0, "with the string left whole the weight hangs on")
end

------------------------------------------------------------------ weight: knocks a line
do
    local b = F.new_board()
    b:add_trap({ kind = "weight", id = "w", x = 30, y = -30, h = 5, r = 0.5 })
    local sx = 20 + 2 * SP + SP / 2
    b:add_trap({ kind = "string", id = "s", a = { sx, -36, 0.6 }, b = { sx, -32, 0.6 }, holds = "w" })
    local start = row(b, 20, -34, 0, 5)
    local line = row(b, 30, -30, 0, 15)
    b.start = { id = start[1].id, dir = 1 }
    local res = F.simulate(b)
    local land = ev(res, "w", "land")
    check(land and land.h == 0, "the weight falls to the floor")
    check(res.falls[line[1].id] and math.abs(res.falls[line[1].id].t - land.t) < 1e-9, "the domino under it goes over as it lands")
    check(fell(res, line) == 15, "and knocks the whole line over, " .. fell(res, line) .. " of 15")
    -- A ball under a weight is launched.
    local b2 = F.new_board()
    b2:add_trap({ kind = "weight", id = "w", x = 30.6, y = -30, h = 5, r = 0.5 })
    b2:add_trap({ kind = "string", id = "s", a = { sx, -36, 0.6 }, b = { sx, -32, 0.6 }, holds = "w" })
    local st2 = row(b2, 20, -34, 0, 5)
    assert(b2:place_ball(30, -30, 0))
    b2.start = { id = st2[1].id, dir = 1 }
    local r2 = F.simulate(b2)
    check(r2.balls_launched == 1 and r2.balls[1].x < 30, "a weight landing beside a ball sends it away from the middle")
end

------------------------------------------------------------------ plank: carries a chain across a gap
local function bridge(with_plank)
    local b = F.new_board()
    if with_plank then
        b:add_trap({ kind = "plank", id = "p", x = -0.1, y = 7, h = 4, a = 0, len = 6.6, width = 1.5 })
        local sx = -8 + 2 * SP + SP / 2
        b:add_trap({ kind = "string", id = "s", a = { sx, 4.5, 4.6 }, b = { sx, 9, 4.6 }, holds = "p" })
    end
    local desk = {}
    b:place_line(-8, 5, -0.3, 5, paint, 4)
    for _, p in pairs(b.pieces) do desk[#desk + 1] = p end
    local shelf = row(b, 6.4, 7, 4, 12)
    local first
    for _, p in ipairs(desk) do if not first or p.order < first.order then first = p end end
    b.start = { id = first.id, dir = 1 }
    return b, shelf
end
do
    local b0, shelf0 = bridge(false)
    local r0 = F.simulate(b0)
    check(#r0.lands == 1 and fell(r0, shelf0) == 0, "without the plank the chain dives into the gap and stops there")
    local b, shelf = bridge(true)
    local _, why = b:place(-0.25, 7, 0, 4, "cream")
    check(why == "trap", "a domino cannot stand inside the upright plank, got " .. tostring(why))
    local res = F.simulate(b)
    local fall, land = ev(res, "p", "fall"), ev(res, "p", "land")
    check(fall and land and fall.t == ev(res, "s", "cut").t, "the cut string lets the plank fall")
    check(math.abs(fall.angle - math.pi / 2) < 0.01 and math.abs(land.x - 6.5) < 0.05 and land.h == 4, "it lies flat across the gap, its end on the shelf at " .. land.x)
    check(math.abs(F.plank_angle(fall, fall.t1) - fall.angle) < 1e-9 and F.plank_angle(fall, fall.t) == 0, "plank_angle follows it")
    check(fell(res, shelf) == 12, "and its far end starts the chain on the shelf, " .. fell(res, shelf) .. " of 12")
    check(times_ordered(res), "res.traps is time-ordered")
    -- A plank longer than the drop tips on down off the desk's front, and its far end knocks over what it comes down on.
    local bg = F.new_board()
    bg:add_trap({ kind = "plank", id = "p", x = -15, y = -9.9, h = 4, a = -math.pi / 2, len = 5, width = 1.5 })
    bg:add_trap({ kind = "string", id = "s", a = { -25 + 2 * SP + SP / 2, -9, 4.6 }, b = { -25 + 2 * SP + SP / 2, -7, 4.6 }, holds = "p" })
    bg:place_line(-25, -8, -18, -8, paint, 4)
    local low = { assert(bg:place(-15, -12.7, -math.pi / 2, 0, "cream")), assert(bg:place(-15, -12.7 - SP, -math.pi / 2, 0, "cream")) }
    local rg = F.simulate(bg)
    local fg, lg = ev(rg, "p", "fall"), ev(rg, "p", "land")
    check(fg and math.abs(fg.angle - math.acos(-4 / 5)) < 0.01 and lg and lg.h == 0 and math.abs(lg.y + 12.9) < 0.05, "a plank tips down past the edge, its end on the floor at " .. (lg and lg.y or -1))
    check(rg.falls[low[1].id] and math.abs(rg.falls[low[1].id].t - lg.t) < 1e-9 and fell(rg, low) == 2, "and knocks over the domino it lands on")
    -- A plank meeting furniture stops against it.
    local b2 = F.new_board()
    b2:add_trap({ kind = "plank", id = "p", x = -0.1, y = 7, h = 4, a = 0, len = 6.6, width = 1.5 })
    b2:add_trap({ kind = "gate", id = "g", x0 = 3, x1 = 3.5, y0 = 6, y1 = 8, z0 = 4, z1 = 12 })
    b2:add_trap({ kind = "string", id = "s", a = { -8 + 2 * SP + SP / 2, 4.5, 4.6 }, b = { -8 + 2 * SP + SP / 2, 9, 4.6 }, holds = "p" })
    b2:place_line(-8, 5, -3, 5, paint, 4)
    local r2 = F.simulate(b2)
    local f2 = ev(r2, "p", "fall")
    check(f2 and f2.angle < math.rad(40) and ev(r2, "p", "land") == nil, "a plank falling into a closed gate stops against it at " .. math.deg(f2.angle))
end

------------------------------------------------------------------ gate: blocks early, passes late
-- Two side-by-side rows from one start: row A cuts the string that opens the gate on row B.
local function gate_race(string_at, gate_at)
    local b = F.new_board()
    local x0, ya, yb = 10, -15.7, -16.3
    local sx = x0 + SP + string_at * SP + SP / 2
    local gx = x0 + SP + gate_at * SP
    b:add_trap({ kind = "string", id = "s", a = { sx, -15.95, 0.6 }, b = { sx, -14, 0.6 }, holds = "g" })
    b:add_trap({ kind = "gate", id = "g", x0 = gx + 0.21, x1 = gx + 0.41, y0 = -17, y1 = -16, z0 = 0, z1 = 2 })
    local st = assert(b:place(x0, -16, 0, 0, "brick"))
    local A = row(b, x0 + SP, ya, 0, 45)
    local Bl = row(b, x0 + SP, yb, 0, 30)
    b.start = { id = st.id, dir = 1 }
    return b, A, Bl
end
do
    local b, A, Bl = gate_race(2, 20)
    local _, why = b:place(10 + SP + 20 * SP + 0.31, -16.5, 0, 0, "cream")
    check(why == "trap", "nothing stands in a gate, got " .. tostring(why))
    local res = F.simulate(b)
    local open = ev(res, "g", "open")
    check(open and res.falls[Bl[21].id].t > open.t, "the gate opens before row B reaches it")
    check(fell(res, Bl) == 30 and fell(res, A) == 45, "and a chain arriving after it opened goes through, " .. fell(res, Bl) .. " of 30")
    local b2, A2, B2 = gate_race(40, 5)
    local r2 = F.simulate(b2)
    local open2 = ev(r2, "g", "open")
    check(open2 and r2.falls[B2[6].id].t < open2.t, "row B reaches the gate before it opens")
    check(r2.falls[B2[6].id].blocked and fell(r2, B2) == 6, "a chain arriving early is blocked there, " .. fell(r2, B2) .. " of 30")
    -- Never opened: blocked as furniture.
    local b3 = F.new_board()
    b3:add_trap({ kind = "gate", id = "g", x0 = 10 + 3 * SP + 0.21, x1 = 10 + 3 * SP + 0.41, y0 = -17, y1 = -15, z0 = 0, z1 = 2 })
    local l3 = row(b3, 10, -16, 0, 10)
    check(fell(F.simulate(b3), l3) == 4, "a closed gate stops a chain")
end

------------------------------------------------------------------ support: collapses when struck, loses its dominoes
local function support_scene(route)
    local b = F.new_board()
    b:add_trap({ kind = "support", id = "c", x0 = 20, x1 = 23, y0 = -30, y1 = -28, z0 = 0, z1 = 2 })
    local top = { assert(b:place_preset(21, -29, 0, 2, "cream")), assert(b:place_preset(21 + SP, -29, 0, 2, "cream")) }
    local line
    if route == "into" then line = row(b, 12, -29, 0, 13)          -- its last domino falls against the support
    elseif route == "around" then line = row(b, 12, -26, 0, 20)    -- passes beside it
    elseif route == "ball" then
        line = row(b, 12, -29, 0, 6)
        assert(b:place_ball(line[6].x + 0.95, -29, 0))
    end
    b.start = { id = line[1].id, dir = 1 }
    return b, top, line
end
do
    local b, top = support_scene("into")
    local _, why = b:place(21.5, -28.6, 0, 2, "cream")
    check(why == "support", "the player cannot stand a domino on a support, got " .. tostring(why))
    local _, w2 = b:place(21.5, -29, 0, 0, "cream")
    check(w2 == "trap", "nor inside it, got " .. tostring(w2))
    check(top[1].fixed and top[1].preset and b.preset_count == 2, "presets stand on it, fixed")
    local res = F.simulate(b)
    local c = ev(res, "c", "collapse")
    check(c and c.by == "domino", "a domino falling against it collapses it")
    check(#res.lost == 2 and #c.lost == 2 and res.lost[1].t == c.t, "the dominoes on it are lost")
    check(not res.falls[top[1].id] and not res.falls[top[2].id], "and do not carry the chain")
    local ba = support_scene("around")
    local ra = F.simulate(ba)
    check(ev(ra, "c") == nil and #ra.lost == 0 and ra.toppled == 20, "a chain routed around it leaves it standing")
    local bb = support_scene("ball")
    local rb = F.simulate(bb)
    local cb = ev(rb, "c", "collapse")
    check(rb.balls_launched == 1 and cb and cb.by == "ball" and #rb.lost == 2, "a fast ball collapses it")
    -- A weight dropped on it.
    local bw = F.new_board()
    bw:add_trap({ kind = "support", id = "c", x0 = 20, x1 = 23, y0 = -30, y1 = -28, z0 = 0, z1 = 2 })
    bw:add_trap({ kind = "weight", id = "w", x = 21.5, y = -29, h = 7, r = 0.4 })
    bw:add_trap({ kind = "string", id = "s", a = { 12 + SP * 1.5, -36, 0.6 }, b = { 12 + SP * 1.5, -32, 0.6 }, holds = "w" })
    local t1 = assert(bw:place_preset(21, -29, 0, 2, "cream"))
    local st = row(bw, 12, -34, 0, 4)
    bw.start = { id = st[1].id, dir = 1 }
    local rw = F.simulate(bw)
    local cw = ev(rw, "c", "collapse")
    check(cw and cw.by == "weight" and cw.t == ev(rw, "w", "land").t and rw.lost[1].id == t1.id, "a dropped weight collapses it")
end

------------------------------------------------------------------ zones
do
    local b = F.new_board()
    b:add_trap({ kind = "zone", x0 = -58, x1 = -54, y0 = -38, y1 = -34 })
    local function w(_, why) return why end
    check(w(b:place(-56, -36, 0, 0, "cream")) == "zone", "no domino in a zone")
    check(w(b:place(-53.95, -36, 0, 0, "cream")) == "zone", "nor overlapping its edge")
    check(w(b:place_ball(-56, -36, 0)) == "zone" and w(b:place_switch(-56, -36, 0)) == "zone", "no ball or switch")
    check(w(b:place_swing(-56, -36, 0, 0)) == "zone", "no swing")
    check(b:fit_ramp(-45, -5, 0, -20, -5, 4) ~= nil, "a ramp up to the desk fits")
    b:add_trap({ kind = "zone", x0 = -40, x1 = -39, y0 = -4, y1 = -3 })
    check(w(b:place_ramp(-45, -5, 0, -20, -5, 4)) == "zone", "but not over a zone")
    check(b:place(-52, -36, 0, 0, "cream") ~= nil, "beside it is fine")
    local n = b:place_line(-59, -37, -45, -37, paint, 0)
    local inside = 0
    for _, p in pairs(b.pieces) do if p.y < -36 and p.x > -58.095 and p.x < -53.905 then inside = inside + 1 end end
    check(n > 10 and inside == 0, "a line across a zone leaves it empty, placed " .. n)
    local res = F.simulate(b)
    check(#res.traps == 0, "a zone has no events")
    -- A zone with a height band only covers that band.
    local b2 = F.new_board()
    b2:add_trap({ kind = "zone", x0 = -20, x1 = -10, y0 = -5, y1 = 5, z0 = 3.5, z1 = 6 })
    check(w(b2:place(-15, 0, 0, 4, "cream")) == "zone" and b2:place(-15, -20, 0, 0, "cream"), "a zone's height band")
end

------------------------------------------------------------------ installing: checks
do
    local b = F.new_board()
    check(not pcall(b.add_trap, b, { kind = "lava", id = "x" }), "an unknown kind is refused")
    check(not pcall(b.add_trap, b, { kind = "gate", x0 = 0, x1 = 1, y0 = 0, y1 = 1, z0 = 0, z1 = 1 }), "a gate needs an id")
    b:add_trap({ kind = "weight", id = "w", x = 0, y = -30, h = 5, r = 0.5 })
    check(not pcall(b.add_trap, b, { kind = "weight", id = "w", x = 5, y = -30, h = 5, r = 0.5 }), "ids are unique")
    b:add_trap({ kind = "string", id = "s", a = { 0, -31, 6 }, b = { 0, -29, 6 }, holds = "nothing" })
    check(not pcall(b.check_traps, b), "a string holding no trap is caught")
end

------------------------------------------------------------------ live runs: strings cut through the strike path
do
    local b = ball_scene(true)
    b:add_trap({ kind = "string", id = "s2", a = { -20, -28, 1.5 }, b = { -20, -24, 1.5 } })
    b:add_trap({ kind = "support", id = "c", x0 = -10, x1 = -8, y0 = -27, y1 = -25, z0 = 0, z1 = 2 })
    local launched = {}
    local run = F.begin_run(b, { ball = function(p, t, dx, dy, speed) launched[#launched + 1] = { p = p, t = t, speed = speed } end, swing = function() end })
    run.advance(5)
    check(#launched == 1 and #run.res.balls == 0, "a live run hands the ball to the engine")
    check(ev(run.res, "s") == nil, "and does not roll it itself")
    local t = launched[1].t + 0.5
    local B = F.BALL
    run.strike_ball(-31.2, -26, B.r, -30.8, -26, B.r, 20, 0, 0, t, B.min_hit)
    run.advance(t)
    local e = ev(run.res, "s", "cut")
    check(e and e.by == "ball" and e.t == t, "an engine ball crossing a string cuts it")
    run.strike_bob(-20.3, -26, 1.4, -19.7, -26, 1.6, 0, 0, 0, t + 0.1, F.SWING.min_hit)
    run.advance(t + 0.1)
    check(ev(run.res, "s2", "cut") and ev(run.res, "s2", "cut").by == "swing", "so does a swing's bob")
    run.strike_ball(-11, -26, B.r, -9.5, -26, B.r, 2, 0, 0, t + 0.2, B.min_hit)
    run.advance(t + 0.2)
    check(ev(run.res, "c") == nil, "a slow ball does not collapse a support")
    run.strike_ball(-11, -26, B.r, -9.5, -26, B.r, 12, 0, 0, t + 0.3, B.min_hit)
    run.advance(t + 0.3)
    check(ev(run.res, "c", "collapse") and ev(run.res, "c", "collapse").by == "ball", "a fast one does")
end

------------------------------------------------------------------ determinism
local function contraption()
    local b = F.new_board()
    b:add_trap({ kind = "plank", id = "p", x = -0.1, y = 7, h = 4, a = 0, len = 6.6, width = 1.5 })
    b:add_trap({ kind = "string", id = "s", a = { -8 + 2 * SP + SP / 2, 4.5, 4.6 }, b = { -8 + 2 * SP + SP / 2, 9, 4.6 }, holds = "p" })
    b:add_trap({ kind = "string", id = "s2", a = { 6.4 + 5.5 * SP, 6.9, 4.6 }, b = { 6.4 + 5.5 * SP, 9.5, 4.6 }, holds = "w" })
    b:add_trap({ kind = "weight", id = "w", x = -40, y = -20, h = 6, r = 0.5 })
    b:add_trap({ kind = "support", id = "c", x0 = 15, x1 = 18, y0 = 6, y1 = 8, z0 = 4, z1 = 6 })
    b:place_line(-8, 5, -0.3, 5, paint, 4)
    row(b, 6.4, 7, 4, 14)
    b:place_line(-40, -20, -30, -20, paint, 0)
    local first
    for _, p in pairs(b.pieces) do if not first or p.order < first.order then first = p end end
    b.start = { id = first.id, dir = 1 }
    return b
end
local function fingerprint(res)
    local out = {}
    for _, e in ipairs(res.traps) do out[#out + 1] = string.format("%s %s %.9f %s", e.id, e.event, e.t, tostring(e.by)) end
    for _, f in ipairs(res.order) do out[#out + 1] = string.format("%d %.9f %.9f", f.id, f.t, f.final) end
    for _, l in ipairs(res.lost) do out[#out + 1] = string.format("lost %d %.9f", l.id, l.t) end
    return table.concat(out, "\n")
end
do
    local r1, r2 = F.simulate(contraption()), F.simulate(contraption())
    check(#r1.traps >= 6, "the contraption sets off its traps, " .. #r1.traps .. " events")
    check(ev(r1, "w", "land") and ev(r1, "c", "collapse"), "plank, string, weight and support all go")
    check(fingerprint(r1) == fingerprint(r2), "the same build gives the same run twice")
    local b = contraption()
    check(fingerprint(F.simulate(b)) == fingerprint(F.simulate(b)), "and the same board run twice")
end

------------------------------------------------------------------ undo, erase, clear and saves leave traps alone
do
    local b = F.new_board()
    b:add_trap({ kind = "gate", id = "g", x0 = -5, x1 = -4, y0 = -30, y1 = -28, z0 = 0, z1 = 2 })
    b:add_trap({ kind = "support", id = "c", x0 = 20, x1 = 23, y0 = -30, y1 = -28, z0 = 0, z1 = 2 })
    b:add_trap({ kind = "string", id = "s", a = { -10, -31, 0.6 }, b = { -10, -27, 0.6 } })
    local pre = assert(b:place_preset(21, -29, 0, 2, "sage"))
    check(#b.undo_stack == 0, "installing is not an action")
    b:begin_action(); b:place(-20, -29, 0, 0, "cream"); b:end_action()
    check(b:undo() and not b:undo(), "undo takes back only the player's domino")
    check(#b.trap_order == 3 and b.pieces[pre.id], "traps and presets survive undo")
    b:redo()
    b:erase_at(21, -29, 2, 4)
    b:erase_at(-4.5, -29, 0, 4)
    b:erase_at(-10, -29, 0, 4)
    check(b.pieces[pre.id] and b:remove(pre.id) == nil, "erase and remove leave a preset")
    b:clear()
    check(b.count == 1 and b.pieces[pre.id] and #b.trap_order == 3 and b.traps.g and b.traps.c and b.traps.s, "clear leaves traps and presets")
    b:undo()
    check(b.count == 2 and #b.trap_order == 3, "undoing the clear brings back only the player's")
    local text = F.serialize(b)
    check(not text:find("sage") and select(2, text:gsub("\nd ", "")) == 1, "a save holds the player's dominoes, not the preset")
    local back = F.deserialize(text)
    check(#back.trap_order == 0 and back.count == 1 and back.preset_count == 0, "and loads with no traps")
    -- A ramp onto a trap is refused.
    local _, why = b:fit_ramp(-6, -29, 0, -6, -9, 4)
    check(why == "trap", "no ramp through a trap, got " .. tostring(why))
end

------------------------------------------------------------------ a big build with traps
do
    local function build(with_traps)
        local b = F.new_board()
        -- A field 24 wide across the floor in front of the desk; ten strings across it, between its rows, each
        -- holding a weight over the far floor.
        if with_traps then
            for i = 0, 9 do
                local x = -58 + (50 + 5 * i) * SP + SP / 2
                b:add_trap({ kind = "string", id = "s" .. i, a = { x, -21, 0.6 }, b = { x, -19, 0.6 }, holds = "w" .. i })
                b:add_trap({ kind = "weight", id = "w" .. i, x = 58, y = 35 - i * 1.5, h = 5, r = 0.5 })
            end
        end
        b:place_spots(F.field_spots(-58, -26, 18, -26, 24), F.field_paint, 0)
        local first
        for _, p in pairs(b.pieces) do if not first or p.order < first.order then first = p end end
        b.start = { id = first.id, dir = 1 }
        return b
    end
    local plain, trapped = build(false), build(true)
    check(#trapped.trap_order == 20 and trapped.count >= 4000, "4,000 dominoes and 20 traps, " .. trapped.count)
    local t0 = os.clock()
    local r0 = F.simulate(plain)
    local ms0 = (os.clock() - t0) * 1000
    t0 = os.clock()
    local r1 = F.simulate(trapped)
    local ms1 = (os.clock() - t0) * 1000
    local cuts = 0
    for _, e in ipairs(r1.traps) do if e.event == "cut" then cuts = cuts + 1 end end
    print(string.format("  %d dominoes, 20 traps: %d fell, %d strings cut, %d trap events; %.0f ms (%.0f ms without traps)",
        trapped.count, r1.toppled, cuts, #r1.traps, ms1, ms0))
    check(r1.toppled > 3500 and cuts == 10, "the wave runs and cuts every string")
    check(ms1 < 500 and ms1 < ms0 * 2 + 20, "simulated without a slowdown worth noting")
end

print(checks .. " checks passed")
print("PASS traps")
