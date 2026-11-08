-- luajit tests/free_test.lua  (run from the Topple folder)
-- Free Build rules: placing on the room's surfaces, the shape tools, the chain simulation (lines, curves, fields,
-- spirals, the book stairs, furniture, gaps, edge-on pushes), the pose maths the world uses, undo / redo, saving,
-- and that a 5,000-domino build simulates quickly.
local F = dofile("Assets/Scripts/topple_free.lua")
local room = F.set_room(dofile("Assets/Scripts/free_room.lua"))
local floor, abs, sqrt, sin, cos, pi = math.floor, math.abs, math.sqrt, math.sin, math.cos, math.pi
local checks = 0
local function check(cond, msg) checks = checks + 1; if not cond then error("FAIL: " .. msg, 2) end end
local function near(a, b, e) return abs(a - b) <= (e or 1e-6) end

local function line(b, x0, y0, x1, y1, h0, paint)
    b:begin_action()
    local n = b:place_line(x0, y0, x1, y1, function() return paint or "cream" end, h0 or 0)
    b:end_action()
    return n
end
local function surface(name)
    for _, s in ipairs(room.surfaces) do if s.name == name then return s end end
end

-- Placement on surfaces.
do
    local b = F.new_board()
    check(b:place(0, -26, 0, 0) ~= nil, "a domino stands on the bare floor")
    check(b:place(0.3, -26, 0, 0) == nil, "too close to another")
    local _, why = b:place(-10, 25, 0, 0)
    check(why == "furniture", "nothing goes inside the sofa, got " .. tostring(why))
    local tbl = surface("coffee table")
    local p = b:place_auto(-12, 1, 0, "brick")
    check(p and near(p.z, tbl.h), "clicking above the coffee table puts it on the top (h " .. tostring(p and p.z) .. ")")
    _, why = b:place(tbl.x1 - 0.1, 1, pi / 2, tbl.h)
    check(why == "air", "a domino may not hang off the table's edge")
    local rug = surface("rug")
    p = b:place_auto(-30, 0, 0, "sage")
    check(p and near(p.z, rug.h), "on the rug it stands on the rug")
    _, why = b:place(-39.8, 0, 0, 0)
    check(why == "furniture", "nothing inside the wall")
    -- Under the coffee table (between its legs) is fine.
    check(b:place(-12, 1, 0, 0) ~= nil, "a domino fits under the coffee table")
end

-- A straight line falls end to end; the first placed starts it; a gap stops it and is reported.
do
    local b = F.new_board()
    local n = line(b, -30, -32, 30, -32)
    check(n >= 95, "a 60-unit line lays about 97 dominoes, got " .. n)
    local res = F.simulate(b)
    check(res.toppled == n, "the whole line falls: " .. res.toppled .. " of " .. n)
    check(res.duration > 1 and res.duration < 30, "duration " .. res.duration)
    local st = b:starter()
    check(st.x < -29.9, "the first domino placed is the starter")
    -- Cut a gap of three in the middle.
    local mid = {}
    for _, p in pairs(b.pieces) do if p.x > -1 and p.x < 1 then mid[#mid + 1] = p.id end end
    b:begin_action(); for _, id in ipairs(mid) do b:remove(id) end; b:end_action()
    res = F.simulate(b)
    check(res.toppled < n / 2 + 2 and res.toppled > n / 2 - 6, "the chain stops at the gap: " .. res.toppled)
    check(#res.gaps >= 1 and abs(res.gaps[1].x) < 2, "the gap is reported where it is")
    -- Undo puts them back; the whole line falls again. Redo takes them away again.
    b:undo()
    check(F.simulate(b).toppled == n, "undo restores the gap's dominoes")
    b:redo()
    check(F.simulate(b).toppled == res.toppled, "redo removes them again")
end

-- Starting the other way round, from the far end.
do
    local b = F.new_board()
    local n = line(b, -10, -32, 10, -32)
    local last
    for _, p in pairs(b.pieces) do if not last or p.x > last.x then last = p end end
    b:begin_action(); b:set_start(last.id); b:end_action()
    local res = F.simulate(b)
    check(res.toppled == 1, "pushed along its facing the last one falls off the end alone")
    b:set_start(last.id)
    res = F.simulate(b)
    check(res.toppled == n, "pushed back the other way it runs the whole line: " .. res.toppled)
    b:undo()
    local st, dir = b:starter()
    check(st.x < -9.9 and dir == 1, "undo restores the original start")
end

-- Curves: a freehand-style arc of strokes still falls through.
do
    local b = F.new_board()
    b:begin_action()
    local lx, ly, lz = 0, -26, 0
    b:place(lx, ly, 0, 0, "navy")
    local placed = 1
    for i = 1, 400 do
        local ang = i / 400 * pi * 1.4
        local cx, cy = 10 * sin(ang), -16 - 10 * cos(ang)
        local p = b:stroke_step(lx, ly, lz, cx, cy, "navy")
        if p then lx, ly, lz = p.x, p.y, p.z; placed = placed + 1 end
    end
    b:end_action()
    local res = F.simulate(b)
    check(placed > 30 and res.toppled == placed, "a curve falls through: " .. res.toppled .. " of " .. placed)
end

-- A field fans out and every domino in it falls; a spiral runs to its middle.
do
    local b = F.new_board()
    local spots = F.field_spots(-20, -30, -20, -12, 6)
    check(#spots > 250, "a 6-wide, 18-long field has a few hundred dominoes: " .. #spots)
    b:begin_action(); local n = b:place_spots(spots, nil, 0); b:end_action()
    check(n == #spots, "every field spot stands: " .. n .. " of " .. #spots)
    local res = F.simulate(b)
    check(res.toppled == n, "the whole field falls: " .. res.toppled .. " of " .. n)
    local b2 = F.new_board()
    local sp = F.spiral_spots(24, -2, 24 + 8, -2, false)
    b2:begin_action(); local m = b2:place_spots(sp, nil, 0); b2:end_action()
    check(m == #sp and m > 100, "a spiral of radius 8 lays " .. m)
    local r2 = F.simulate(b2)
    check(r2.toppled == m, "the spiral falls to its middle: " .. r2.toppled .. " of " .. m)
    local inner = r2.falls[r2.order[#r2.order].id]
    local p = b2.pieces[inner.id]
    check(sqrt((p.x - 24) ^ 2 + (p.y + 2) ^ 2) < 2.4, "the last to fall is at the middle")
end

-- Up and over the staircase of books, and on down the other side.
do
    local b = F.new_board()
    local n = line(b, 8, -19, 40, -19, 0)
    local heights = {}
    for _, p in pairs(b.pieces) do heights[string.format("%.2f", p.z)] = true end
    check(heights["2.25"] and heights["0.45"], "the line climbs every book (top at 2.25)")
    local res = F.simulate(b)
    check(res.toppled == n, "the chain runs up and over the books: " .. res.toppled .. " of " .. n)
end

-- Furniture stops a chain; the table top and the floor beneath are separate worlds.
do
    local b = F.new_board()
    line(b, -10, 12, -10, 17.4)          -- runs into the front of the sofa
    local res = F.simulate(b)
    local last = res.order[#res.order]
    check(last.blocked and math.deg(last.contact) < 80, "the last one stops against the sofa")
    local b2 = F.new_board()
    local tbl = surface("coffee table")
    local n1 = line(b2, -23, 1, -3, 1, tbl.h)
    local n2 = line(b2, -23, 2.5, -3, 2.5, 0)
    check(n1 > 25 and n2 > 25, "lines on the table top and under it")
    local res2 = F.simulate(b2)
    check(res2.toppled == n1, "the table-top line falls without touching the one underneath: " .. res2.toppled)
end

-- Pushed edge-on, a domino only wobbles.
do
    local b = F.new_board()
    b:place(0, -26, 0, 0); b:place(0.6, -26, pi / 2, 0)
    local res = F.simulate(b)
    check(res.toppled == 1 and #res.events == 1 and res.events[1].kind == "wobble", "edge-on it wobbles")
end

-- Pose maths: rebuild R = Rz * Ry * Rx from the Euler angles and compare with Ry(yaw) Rz(-theta) [Ry(pi)].
do
    local function Rx(a) return { { 1, 0, 0 }, { 0, cos(a), -sin(a) }, { 0, sin(a), cos(a) } } end
    local function Ry(a) return { { cos(a), 0, sin(a) }, { 0, 1, 0 }, { -sin(a), 0, cos(a) } } end
    local function Rz(a) return { { cos(a), -sin(a), 0 }, { sin(a), cos(a), 0 }, { 0, 0, 1 } } end
    local function mul(A, B)
        local C = {}
        for i = 1, 3 do C[i] = {} for j = 1, 3 do local s = 0 for k = 1, 3 do s = s + A[i][k] * B[k][j] end C[i][j] = s end end
        return C
    end
    local worst = 0
    for _, yaw in ipairs({ 0, 0.4, pi / 2, 2.1, pi, -1.2, -pi / 2 }) do
        for _, th in ipairs({ 0, 0.3, 0.9, 1.5 }) do
            for _, flip in ipairs({ false, true }) do
                local _, _, _, ex, ey, ez = F.pose({ x = 0, y = 0, z = 0 }, yaw, flip, th)
                local got = mul(mul(Rz(math.rad(ez)), Ry(math.rad(ey))), Rx(math.rad(ex)))
                local want = mul(Ry(yaw), Rz(-th))
                if flip then want = mul(want, Ry(pi)) end
                for i = 1, 3 do for j = 1, 3 do worst = math.max(worst, abs(got[i][j] - want[i][j])) end end
            end
        end
    end
    check(worst < 1e-9, "pose Euler angles rebuild the rotation (worst error " .. worst .. ")")
    local x, h, z = F.pose({ x = 1, y = 2, z = 0.5 }, 0, false, pi / 2)
    check(near(x, 1 + F.DOM.t / 2) and near(h, 0.5 + F.DOM.t / 2) and near(z, -2), "flat on its face it lies just ahead of its base")
end

-- Saving: a build survives the round trip, start and direction included, and plays the same.
do
    local b = F.new_board()
    line(b, -10, -32, 10, -32, 0, "brick")
    b:begin_action(); b:place_spots(F.field_spots(-20, -10, -20, 0, 4), function() return "navy" end, room.surfaces[1].h); b:end_action()
    local last
    for _, p in pairs(b.pieces) do if p.y < -31 and (not last or p.x > last.x) then last = p end end
    b:set_start(last.id); b:set_start(last.id)
    local text = F.serialize(b)
    local b2, ok = F.deserialize(text)
    check(ok and b2.count == b.count, "loaded " .. b2.count .. " of " .. b.count)
    local r1, r2 = F.simulate(b), F.simulate(b2)
    check(r1.toppled == r2.toppled and near(r1.duration, r2.duration, 1e-3), "a loaded build plays the same")
    local st, dir = b2:starter()
    check(dir == -1 and near(st.x, last.x, 1e-3), "the start and its direction survive saving")
    check(not select(2, F.deserialize("rubbish")), "junk is refused")
    local damaged, ok3 = F.deserialize("TOPPLE-FREE 1\nb abc 2.000 0.000\nd 1.000 x 0.000 0.0000 cream\nd nan 2.000 0.000 0.0000 cream\nd 1.000 2.000 0.000 0.0000 cream\n")
    check(ok3 and damaged.count == 1 and damaged.ball_count == 0, "damaged lines lose only their own pieces")
end

-- The first-visit demo build: it lays a few hundred dominoes and the whole chain falls.
do
    local b = F.demo(F.new_board())
    local res = F.simulate(b)
    check(b.count > 400, "the demo lays " .. b.count)
    check(res.toppled == b.count, "the demo falls end to end: " .. res.toppled .. " of " .. b.count)
    check(#b.undo_stack == 0, "the demo is not an undo step")
end

-- Clearing is one undoable action; the box holds F.CAP.
do
    local b = F.new_board()
    line(b, -30, -32, 30, -32)
    local n = b.count
    b:clear()
    check(b.count == 0, "clear empties the room")
    b:undo()
    check(b.count == n, "undo brings the cleared build back")
end

-- Scale: one chain of thousands (a field the width of the room fanning out down its length, then a line on round
-- the walls to the box's limit) simulates in well under a second, and nearly all of it falls.
do
    local b = F.new_board()
    b:begin_action()
    b:place_spots(F.field_spots(-36, -2, 36, -2, 24), nil, 0)
    b:end_action()
    local field_n = b.count
    local res0 = F.simulate(b)
    check(field_n >= 3000, "the room-wide field placed " .. field_n)
    check(res0.toppled >= field_n * 0.97, "the room-wide field falls (round the furniture): " .. res0.toppled .. " of " .. field_n)
    b:begin_action()
    b:place_line(-38, -33, 38, -33, nil, 0)
    b:place_line(38, -32.4, 38, 26, nil, 0)
    b:end_action()
    local t0 = os.clock()
    local res = F.simulate(b)
    local dt = os.clock() - t0
    print(string.format("  %d dominoes simulated in %.0f ms (%d fell, %.1f s of chain)", b.count, dt * 1000, res.toppled, res.duration))
    check(dt < 1.0, "simulating " .. b.count .. " dominoes took " .. dt .. " s")
    local t1 = os.clock()
    local text = F.serialize(b)
    local b2 = F.deserialize(text)
    print(string.format("  saved %d KB, round trip %.0f ms", floor(#text / 1024), (os.clock() - t1) * 1000))
    check(b2.count == b.count, "the big build saves and loads")
end

-- Balls.
local function ball_of(res, p)
    for _, b in ipairs(res.balls) do if b.id == p.id then return b end end
end
-- A straight push: a domino at x0 facing +x (h high), the ball just beyond it.
local function pusher(b, x, y, a, h)
    local p = b:place(x, y, a, h, "cream")
    local q = b:place_ball(x + math.cos(a) * 0.95, y + math.sin(a) * 0.95, h)     -- a wide gap: a falling domino's best hit
    return p, q
end
do
    -- Placing: on a surface, not in furniture, not on a domino, and a domino not on a ball.
    local b = F.new_board()
    local p = b:place_ball(0, -26, 0)
    check(p and b.ball_count == 1 and b.count == 0, "a ball sits on the floor and is not counted as a domino")
    check(p.kind == "ball" and b:pick_ball(0.2, -26, 0) == p, "a ball can be picked")
    local _, why = b:place_ball(-10, 25, 0)
    check(why == "furniture", "no ball inside the sofa, got " .. tostring(why))
    _, why = b:place_ball(0.3, -26, 0)
    check(why == "crowded", "no ball on top of a ball")
    _, why = b:place(0.2, -26, 0, 0)
    check(why == "crowded", "no domino inside a ball")
    check(b:starter() == nil, "a ball alone gives no run")
    check(next(F.simulate(b).balls) == nil, "a ball alone does not move")
end
do
    -- A domino pushes it; it rolls in a straight line, slows and stops.
    local b = F.new_board()
    local p, q = pusher(b, -20, -28, 0, 0)
    local res = F.simulate(b)
    local r = ball_of(res, q)
    check(r ~= nil, "the falling domino launches the ball")
    check(res.falls[p.id].final > math.rad(85), "the domino carries on and lies flat, it does not lean on the ball")
    check(res.falls[p.id].hits == 1, "a ball struck counts as a hit, so the domino is not reported as a gap")
    check(r.x > q.x + 8 and r.x < q.x + 14 and near(r.y, q.y, 0.05), "a push sends the light ball about 50 cm, got x " .. r.x)
    check(r.t_end > r.t0 + 1 and res.duration >= r.t_end, "the run waits for the ball")
    check(res.toppled == 1 and res.total == 1, "balls are not counted among the dominoes")
end
do
    -- Off the bookshelf: rolls along the top, drops to the floor, knocks over a chain standing there.
    local b = F.new_board()
    local top = surface("bookshelf")
    local _, q = pusher(b, 24, 27.6, -pi / 2, top.h)
    check(q ~= nil and q.z == top.h, "a ball stands on the bookshelf")
    local n = line(b, 24, 23.4, 24, 12, 0)                -- it first lands about 3.5 out from the shelf's front
    local res = F.simulate(b)
    local r = ball_of(res, q)
    local lowest = 99
    for i = 4, #r.pts, 4 do lowest = math.min(lowest, r.pts[i]) end
    check(lowest < 0.2, "it reaches the floor, lowest " .. lowest)
    check(r.bumps[1] ~= nil, "it lands with a bump")
    check(res.toppled > n * 0.8, "it comes down on the chain and knocks it over: " .. res.toppled .. " of " .. (n + 1))
    check(r.bumps[2] ~= nil and r.y > 12, "and goes on bouncing, ending near where it fell, y " .. r.y)
end
do
    -- A chain that starts on the floor, sends a ball, and the ball starts a second chain further on.
    local b = F.new_board()
    local n1 = line(b, -22, -28, -16, -28, 0)
    local last
    for _, p in pairs(b.pieces) do if not last or p.x > last.x then last = p end end
    b:place_ball(last.x + 0.95, -28, 0)
    local n2 = line(b, -11.5, -28, -5.5, -28, 0)              -- within what a domino's push gives the ball
    local res = F.simulate(b)
    check(res.toppled == n1 + n2, "dominoes, ball, dominoes: " .. res.toppled .. " of " .. (n1 + n2))
    local t_first, t_second = 0, 1e9
    for _, f in ipairs(res.order) do
        local p = b.pieces[f.id]
        if p.x < -13 then t_first = math.max(t_first, f.t) else t_second = math.min(t_second, f.t) end
    end
    check(t_second > t_first, "the second chain falls after the ball arrives")
end
do
    -- Struck edge-on the domino only rocks and the ball comes back off it.
    local b = F.new_board()
    local _, q = pusher(b, -20, -28, 0, 0)
    local side = b:place(-17, -28, pi / 2, 0, "sage")
    local res = F.simulate(b)
    local r = ball_of(res, q)
    check(res.falls[side.id] == nil, "a domino hit edge-on stays up")
    local wob = false
    for _, e in ipairs(res.events) do if e.kind == "wobble" and e.id == side.id then wob = true end end
    check(wob, "it wobbles")
    check(r.x < -17, "the ball does not pass through it, ended at x " .. r.x)
end
do
    -- Walls and furniture turn it back; it stays in the room and off the furniture.
    local b = F.new_board()
    local _, q = pusher(b, 38, -28, 0, 0)
    local res = F.simulate(b)
    local r = ball_of(res, q)
    for i = 1, #r.pts, 4 do check(r.pts[i + 1] <= room.bounds.x1 + 1e-6, "inside the wall") end
    check(r.x < 39.7 and r.vx ~= nil, "it comes off the wall")
    local b2 = F.new_board()
    local _, q2 = pusher(b2, -10, 15, pi / 2, 0)
    local r2 = ball_of(F.simulate(b2), q2)
    check(r2.y < 17.8, "the sofa stops it, ended at y " .. r2.y)
end
do
    -- A ball strikes a ball at rest and hands on its speed.
    local b = F.new_board()
    local _, q = pusher(b, -20, -28, 0, 0)
    local q2 = b:place_ball(-15, -28, 0)
    local res = F.simulate(b)
    check(ball_of(res, q2) and ball_of(res, q2).x > ball_of(res, q).x, "the second ball takes over")
end
do
    -- The same board gives the same run, also after saving and loading.
    local function make()
        local b = F.new_board()
        local _, q = pusher(b, 24, 27.6, -pi / 2, surface("bookshelf").h)
        line(b, 24, 18.5, 24, 8, 0)
        return b, q
    end
    local function trace(res)
        local t = {}
        for _, r in ipairs(res.balls) do t[#t + 1] = table.concat(r.pts, ",") end
        for _, f in ipairs(res.order) do t[#t + 1] = string.format("%.6f", f.t) end
        return table.concat(t, ";")
    end
    local b = make()
    local a = trace(F.simulate(b))
    check(a == trace(F.simulate(b)), "simulating twice gives the same run")
    local b2, ok = F.deserialize(F.serialize(b))
    check(ok and b2.ball_count == 1 and b2.count == b.count, "balls save and load")
    check(a:len() > 0 and #F.simulate(b2).balls == 1, "a loaded ball still launches")
    -- Old saves (no ball lines) still load.
    local old, ok2 = F.deserialize("TOPPLE-FREE 1\nd 1.000 2.000 0.000 0.0000 cream\n")
    check(ok2 and old.count == 1 and old.ball_count == 0, "an old save loads")
end
do
    -- Undo, redo, erase and clear.
    local b = F.new_board()
    b:begin_action(); local q = b:place_ball(0, -26, 0); b:end_action()
    b:undo(); check(b.ball_count == 0, "undo takes the ball away")
    b:redo(); check(b.balls[q.id] == q, "redo brings it back")
    check(b:erase_at(0, -26, 0, 1) == 1 and b.ball_count == 0, "erase takes a ball")
    b:undo(); b:place_ball(5, -26, 0); b:clear()
    check(b.ball_count == 0, "clear takes the balls")
    b:undo(); check(b.ball_count > 0, "undoing clear restores them")
end
do
    -- A big build with a ball off every end of its wave still simulates quickly (the balls really fly).
    local b = F.new_board()
    b:begin_action()
    b:place_spots(F.field_spots(-36, -2, 36, -2, 24), nil, 0)
    b:place_line(-38, -33, 38, -33, nil, 0)
    b:place_line(38, -32.4, 38, 26, nil, 0)
    b:end_action()
    for _, f in ipairs(F.simulate(b).order) do
        local p = b.pieces[f.id]
        if not f.hits and b.ball_count < F.BALL.cap then b:place_ball(p.x + f.dx * 0.7, p.y + f.dy * 0.7, p.z) end
    end
    local t0 = os.clock()
    local res = F.simulate(b)
    local dt = os.clock() - t0
    print(string.format("  %d dominoes + %d balls (%d launched) simulated in %.0f ms", b.count, b.ball_count, #res.balls, dt * 1000))
    check(b.count >= 4000 and #res.balls >= 20, "the big build launches balls: " .. b.count .. " dominoes, " .. #res.balls .. " launched")
    check(dt < 1.0, "simulating with balls took " .. dt .. " s")
    check(res.total == b.count, "the total counts dominoes only")
end

-- Swings (a ball on a string).
local function swing_of(res, p)
    for _, s in ipairs(res.swings) do if s.id == p.id then return s end end
end
-- A domino set to strike a swing hanging at (x, y), along the swing's axis a.
local function swing_hit(b, x, y, a, h)
    local s = b:place_swing(x, y, h or 0, a)
    local d = s and b:place(s.lx - cos(a) * 0.9, s.ly - sin(a) * 0.9, a, h or 0, "cream")
    return d, s
end
local function bob_range(s, p)
    local lo, hi = 1e9, -1e9
    for i = 2, #s.pts, 2 do
        local along = p.L * sin(s.pts[i])
        lo, hi = math.min(lo, along), math.max(hi, along)
    end
    return lo, hi
end
do
    -- Placing: over a surface, clear of furniture and of what stands there; nothing placed inside it.
    local b = F.new_board()
    local s = b:place_swing(-20, -28, 0, 0)
    check(s and s.hang == "stand" and near(s.L, F.SWING.len), "a swing stands on the floor from its stand")
    check(b.swing_count == 1 and b.count == 0 and b.ball_count == 0, "it is its own kind of piece")
    check(b:pick_swing(-20.2, -28, 0) == s, "a swing can be picked")
    local _, why = b:place_swing(-10, 25, 0, 0)
    check(why == "furniture", "no swing in the sofa, got " .. tostring(why))
    _, why = b:place_swing(-20.3, -28, 0, 0)
    check(why == "crowded", "no swing on a swing")
    _, why = b:place(-20.2, -28, 0, 0)
    check(why == "crowded", "no domino in its ball")
    _, why = b:place(-20, -26.7, 0, 0)
    check(why == "crowded", "no domino in its post")
    _, why = b:place_ball(-20, -29.3, 0)
    check(why == "crowded", "no ball in its post")
    _, why = b:place_swing(-39.3, 0, 0, 0)
    check(why ~= nil, "no swing with a post through the wall")
    check(next(F.simulate(b).swings) == nil, "a swing alone does not move")
end
do
    -- Hung by the bookshelf it hangs from the top, on a long string.
    local b = F.new_board()
    local top = surface("bookshelf")
    local s = b:place_swing(20, 25.2, 0, 0)
    check(s and s.hang == "shelf" and s.L > 37 and s.L < 39, "by the bookshelf it hangs from the top, L " .. tostring(s and s.L))
    local _, why = b:place_swing(20, 26, 0, 0)
    check(why == "furniture", "not inside the shelf, got " .. tostring(why))
    check(near(F.swing_top(s), top.h, 1e-6), "tied at the top of the shelf")
    local far = F.new_board():place_swing(20, 20, 0, 0)
    check(far and far.hang == "stand", "further out it has its own stand")
end
do
    -- A domino sets it going and its arc knocks over a domino standing beyond, but not one out of reach.
    local b = F.new_board()
    local d, s = swing_hit(b, -20, -28, 0)
    local hit = b:place(-17, -28, 0, 0, "sage")
    local out = b:place(-14, -28, 0, 0, "navy")
    local res = F.simulate(b)
    local r = swing_of(res, s)
    check(r ~= nil, "the falling domino sets the swing going")
    check(res.falls[d.id].hits == 1, "the domino that hit the latch is not reported as a gap")
    check(res.falls[hit.id] ~= nil, "the far end of the arc knocks over a domino")
    check(res.falls[hit.id].t > r.t0 + 0.05, "that domino falls after the swing has travelled")
    check(res.falls[out.id] == nil, "a domino beyond the arc stays up")
    local lo, hi = bob_range(r, s)
    check(hi > 2.8 and lo < 0, "it swings out and back: " .. lo .. " .. " .. hi)
    check(r.t_end > r.t0 + 1 and res.duration >= r.t_end, "the run waits for it to settle")
    check(res.toppled == 2 and res.total == 3, "swings are not counted among the dominoes")
    check(r.bumps[1] ~= nil, "it bumps what it strikes")
end
do
    -- Without anything in the way the arc reaches about amp.
    local b = F.new_board()
    local _, s = swing_hit(b, -10, -28, 0)
    local r = swing_of(F.simulate(b), s)
    local _, hi = bob_range(r, s)
    local amp = F.SWING.len * sin(F.SWING.amp)
    check(hi > amp * 0.9 and hi < amp * 1.1, "its reach is the amplitude: " .. hi .. " of " .. amp)
end
do
    -- From the shelf the arc is much longer.
    local b = F.new_board()
    local _, s = swing_hit(b, 24, 25.2, 0)
    check(s and s.hang == "shelf", "(hung from the shelf)")
    local far = b:place(30, 25.2, 0, 0, "sage")
    local res = F.simulate(b)
    check(swing_of(res, s) ~= nil and res.falls[far.id] ~= nil, "the long string reaches a domino 6 away")
end
do
    -- Only its latch sets it off.
    local b = F.new_board()
    b:place(-22, -32, 0, 0, "cream")
    local s = b:place_swing(-10, -32, 0, 0)
    local res = F.simulate(b)
    check(s and swing_of(res, s) == nil, "nothing touched the latch, so it stays held back")
end
do
    -- A ball sets it going; it launches a ball at rest; it sets another swing going.
    local b = F.new_board()
    pusher(b, -20, -28, 0, 0)
    local s = b:place_swing(-10.4, -28, 0, 0)               -- its latch is 4.6 back along the ball's path
    local res = F.simulate(b)
    check(s and swing_of(res, s) ~= nil, "a rolling ball hits the latch and lets it go")
    check(res.balls[1].x < s.lx, "the ball comes off the latch, ended at x " .. res.balls[1].x)
    local b2 = F.new_board()
    local _, s2 = swing_hit(b2, -20, -28, 0)
    local q = b2:place_ball(-17.5, -28, 0)
    local res2 = F.simulate(b2)
    local rb = ball_of(res2, q)
    check(rb ~= nil and rb.x > -15, "the swing launches a ball at rest, ended at x " .. tostring(rb and rb.x))
    check(swing_of(res2, s2) ~= nil, "and swung to do it")
    local b3 = F.new_board()
    local _, s3 = swing_hit(b3, -20, -28, 0)
    local s4 = b3:place_swing(-12.41, -28, 0, 0)            -- the first bob strikes its latch at the bottom of its arc
    local res3 = F.simulate(b3)
    check(s3 and s4 and swing_of(res3, s4) ~= nil, "a swing sets the next one going")
end
do
    -- The full chain the piece is for: dominoes, a ball, a swing, more dominoes.
    local b = F.new_board()
    local n1 = line(b, -30, -32, -24, -32, 0)
    local last
    for _, p in pairs(b.pieces) do if not last or p.x > last.x then last = p end end
    local q = b:place_ball(last.x + 0.95, -32, 0)
    local s = b:place_swing(last.x + 4.6 + 4.59, -32, 0, 0)       -- the ball rolls 3.6 on to its latch
    local n2 = line(b, s.x + 2.5, -32, s.x + 9, -32, 0)
    local res = F.simulate(b)
    check(q and s and ball_of(res, q) and swing_of(res, s), "ball and swing both go")
    check(res.toppled == n1 + n2, "dominoes, ball, swing, dominoes: " .. res.toppled .. " of " .. (n1 + n2))
end
do
    -- Furniture turns it back; the posts are solid.
    local b = F.new_board()
    local _, s = swing_hit(b, -10, 14.5, pi / 2)
    local r = swing_of(F.simulate(b), s)
    local _, hi = bob_range(r, s)
    check(14.5 + hi + F.SWING.r < 17.8 + 0.3, "the sofa turns it back, reached y " .. (14.5 + hi))
    check(r.bumps[1] ~= nil, "with a bump")
    local b2 = F.new_board()
    local _, q = pusher(b2, -20, -28, 0, 0)
    local s2 = b2:place_swing(-14, -26.7, 0, 0)            -- one of its posts stands in the ball's path
    local res2 = F.simulate(b2)
    check(s2 and ball_of(res2, q).x < -14, "a stand's post stops a ball, ended at x " .. ball_of(res2, q).x)
end
do
    -- Repeatable; saved and loaded; undo, erase, clear; old saves.
    local function make()
        local b = F.new_board()
        swing_hit(b, -20, -28, 0)
        b:place(-17, -28, 0, 0, "sage")
        return b
    end
    local function trace(res)
        local t = {}
        for _, r in ipairs(res.swings) do t[#t + 1] = table.concat(r.pts, ",") end
        for _, f in ipairs(res.order) do t[#t + 1] = string.format("%.6f", f.t) end
        return table.concat(t, ";")
    end
    local b = make()
    local a = trace(F.simulate(b))
    check(a == trace(F.simulate(b)) and a == trace(F.simulate(make())), "the same board gives the same swing")
    local b2, ok = F.deserialize(F.serialize(b))
    check(ok and b2.swing_count == 1 and b2.count == b.count, "swings save and load")
    local loaded
    for _, s in pairs(b2.swings) do loaded = s end
    check(loaded.hang == "stand" and near(loaded.L, F.SWING.len, 1e-3) and loaded.ax ~= nil, "with their mount and axis")
    check(#F.simulate(b2).swings == 1, "a loaded swing still goes")
    local c = F.new_board()
    c:begin_action(); local s = c:place_swing(0, -26, 0, 0); c:end_action()
    c:undo(); check(c.swing_count == 0, "undo takes the swing away")
    c:redo(); check(c.swings[s.id] == s, "redo brings it back")
    check(c:erase_at(0, -26, 0, 1) == 1 and c.swing_count == 0, "erase takes a swing")
    c:begin_action(); c:place_swing(0, -26, 0, 0); c:end_action()
    c:clear()
    check(c.swing_count == 0, "clear takes the swings")
    c:undo(); check(c.swing_count == 1, "undoing clear restores them")
end
do
    -- The placing preview marks the low part of the arc, along the axis, both ways.
    local spots = F.swing_spots(0, -26, 3, -26, 0)
    check(#spots > 8, "the preview has marks")
    check(spots[1].x < -3 and spots[#spots].x > 3 and near(spots[1].y, -26, 1e-6), "both ways along the axis")
    check(#F.swing_spots(0, -26, 0.1, -26, 0) == 0, "no marks before a drag")
end

do
    -- A row of swings, each setting off the next, all stepped at once near the end, stays quick.
    local b = F.new_board()
    b:place(-25.5, -27, 0, 0, "cream")
    local n = 0
    for i = 0, 8 do if b:place_swing(-20 + i * 6.2, -27, 0, 0) then n = n + 1 end end      -- each bob strikes the next latch
    local t0 = os.clock()
    local res = F.simulate(b)
    local dt = os.clock() - t0
    print(string.format("  %d swings in a row: %d swung, simulated in %.0f ms", n, #res.swings, dt * 1000))
    check(n >= 8 and #res.swings == n, "the whole row swings: " .. #res.swings .. " of " .. n)
    check(dt < 0.5, "simulating the row took " .. dt .. " s")
end

-- Switches.
local function top_domino(b, x)
    local best
    for _, p in pairs(b.pieces) do if not best or (x and p.x < best.x or not x and p.order < best.order) then best = p end end
    return best
end
-- A line along y = -30 that ends just short of a switch: returns the switch and the number of dominoes.
local function line_to_switch(b)
    local n = line(b, -24, -30, -18, -30, 0)
    local last
    for _, p in pairs(b.pieces) do if not last or p.x > last.x then last = p end end
    return b:place_switch(last.x + 0.8, -30, 0), n
end
do
    -- Placing.
    local b = F.new_board()
    local w = b:place_switch(0, -26, 0)
    check(w and w.dir == 1 and w.lamp == false and b.switch_count == 1 and b.count == 0, "a switch stands on the floor, not counted as a domino")
    check(b:pick_switch(0.2, -26, 0) == w, "a switch can be picked")
    local _, why = b:place_switch(-10, 25, 0)
    check(why == "furniture", "no switch in the sofa, got " .. tostring(why))
    _, why = b:place_switch(0.3, -26, 0)
    check(why == "crowded", "no switch on a switch")
    _, why = b:place(0.2, -26, 0, 0)
    check(why == "crowded", "no domino in a switch")
    _, why = b:place_ball(0.4, -26, 0)
    check(why == "crowded", "no ball in a switch")
    _, why = b:place_swing(0.5, -26, 0, 0)
    check(why == "crowded", "no swing on a switch")
    check(next(F.simulate(b).switches) == nil, "a switch alone does nothing")
end
do
    -- A domino strikes it and a chain on another surface, far away, starts.
    local b = F.new_board()
    local w, n1 = line_to_switch(b)
    local tbl = surface("coffee table")
    local before = b.count
    local n2 = line(b, -23, 1, -3, 1, tbl.h)
    local first
    for _, p in pairs(b.pieces) do if p.z == tbl.h and (not first or p.x < first.x) then first = p end end
    check(F.simulate(b).toppled == n1, "unlinked, the far chain stays up")
    b:begin_action(); b:link_switch(w, first.id); b:end_action()
    local res = F.simulate(b)
    check(res.toppled == n1 + n2, "the switch starts the chain on the table: " .. res.toppled .. " of " .. (n1 + n2))
    check(b.count == before + n2 and res.switches[1] and res.switches[1].id == w.id and res.switches[1].target == first.id, "it reports what it pressed")
    check(near(res.falls[first.id].t, res.switches[1].t + F.SWITCH.delay, 1e-9), "after its delay")
    local last_near
    for _, f in ipairs(res.order) do if b.pieces[f.id].z == 0 then last_near = f end end
    check(last_near.hits == 1, "the domino that struck it is not reported as a gap")
    check(res.falls[first.id].dx > 0, "it pushes the way the domino faces")
    b:begin_action(); b:link_switch(w, first.id); b:end_action()
    check(w.dir == -1, "linking the same domino again turns the push round")
    local res2 = F.simulate(b)
    check(res2.falls[first.id].dx < 0 and res2.toppled == n1 + 1, "pushed the other way, it falls away from its chain")
end
do
    -- Far away on the bookshelf, and a switch linked to a domino that has already fallen.
    local b = F.new_board()
    local w, n1 = line_to_switch(b)
    local top = surface("bookshelf")
    local q = b:place(23, 28, 0, top.h, "sage")
    b:begin_action(); b:link_switch(w, q.id); b:end_action()
    local res = F.simulate(b)
    check(res.falls[q.id] ~= nil and res.toppled == n1 + 1, "it reaches the top of the bookshelf from the floor")
    local b2 = F.new_board()
    local w2, n2 = line_to_switch(b2)
    b2:begin_action(); b2:link_switch(w2, top_domino(b2).id); b2:end_action()
    local res2 = F.simulate(b2)
    check(res2.toppled == n2 and #res2.order == n2, "a domino that already fell is not started twice")
end
do
    -- Struck by a ball rolling into it, by a ball dropping onto it, and by a swing; once only.
    local b = F.new_board()
    pusher(b, -20, -28, 0, 0)
    local w = b:place_switch(-14, -28, 0)
    local q = b:place(-5, -28, 0, 0, "navy")
    b:begin_action(); b:link_switch(w, q.id); b:end_action()
    local res = F.simulate(b)
    check(res.falls[q.id] ~= nil and #res.switches == 1, "a rolling ball presses it, once")
    check(res.balls[1].x < -14, "and comes off it, ended at x " .. res.balls[1].x)
    -- Find where the ball first lands, then put a switch there.
    local b2 = F.new_board()
    local top = surface("bookshelf")
    pusher(b2, 14, 27.6, -pi / 2, top.h)
    local r = F.simulate(b2).balls[1]
    local lx, ly
    for i = 1, #r.pts, 4 do
        if r.pts[i + 3] < 0.01 and not lx then lx, ly = r.pts[i + 1], r.pts[i + 2] end
    end
    check(lx ~= nil, "the ball lands")
    local w2 = b2:place_switch(lx, ly, 0)
    local q2 = b2:place(-5, -28, 0, 0, "navy")
    b2:begin_action(); b2:link_switch(w2, q2.id); b2:end_action()
    local res2 = F.simulate(b2)
    check(res2.falls[q2.id] ~= nil, "a ball dropping from the shelf presses it from above")
    local b3 = F.new_board()
    swing_hit(b3, -20, -28, 0)
    local w3 = b3:place_switch(-17, -28, 0)
    local q3 = b3:place(-5, -28, 0, 0, "navy")
    b3:begin_action(); b3:link_switch(w3, q3.id); b3:end_action()
    local res3 = F.simulate(b3)
    check(res3.falls[q3.id] ~= nil and #res3.switches == 1, "a swing presses it")
end
do
    -- The lamp: off, and back on with a second switch.
    local b = F.new_board()
    local w, n = line_to_switch(b)
    b:begin_action(); b:set_switch_lamp(w, true); b:end_action()
    local res = F.simulate(b)
    check(res.switches[1].lamp_on == false and res.switches[1].target == nil, "a switch can work the lamp and start nothing")
    check(res.toppled == n, "and the chain stops there")
    local b2 = F.new_board()
    local w2 = line_to_switch(b2)
    local q = b2:place(-10, -28, 0, 0, "navy")
    local w3 = b2:place_switch(-9.2, -28, 0)
    b2:begin_action(); b2:link_switch(w2, q.id); b2:set_switch_lamp(w2, true); b2:set_switch_lamp(w3, true); b2:end_action()
    local res2 = F.simulate(b2)
    check(res2.switches[1].lamp_on == false and res2.switches[2].lamp_on == true, "the second turns it back on")
    local b3 = F.new_board()
    line_to_switch(b3)
    check(F.simulate(b3).switches[1].lamp_on == nil, "an ordinary switch leaves the lamp alone")
end
do
    -- Links through erase, undo and redo.
    local b = F.new_board()
    local w = b:place_switch(0, -26, 0)
    local q = b:place(5, -26, 0, 0, "navy")
    b:begin_action(); b:link_switch(w, q.id); b:end_action()
    b:begin_action(); b:set_switch_lamp(w, true); b:end_action()
    b:undo(); check(w.lamp == false and w.target == q.id, "undo takes back the lamp setting")
    b:undo(); check(w.target == nil, "undo takes back the link")
    b:redo(); b:redo(); check(w.target == q.id and w.lamp == true, "redo brings both back")
    b:begin_action(); b:remove(q.id); b:end_action()
    local d = b:place(-24, -30, 0, 0, "cream")
    local w5 = b:place_switch(-23.2, -30, 0)
    b:begin_action(); b:link_switch(w5, 99999); b:end_action()
    check(F.simulate(b).toppled == 1, "a link to a missing domino does nothing")
    check(d ~= nil, "(the domino was placed)")
    b:undo(); b:undo()
    check(b.pieces[q.id] == q and w.target == q.id, "undoing the removal restores the linked domino")
    local c = F.new_board()
    c:begin_action(); local s = c:place_switch(0, -26, 0); c:end_action()
    c:undo(); check(c.switch_count == 0, "undo takes the switch away")
    c:redo(); check(c.switches[s.id] == s, "redo brings it back")
    c:begin_action(); check(c:erase_at(0, -26, 0, 1) == 1 and c.switch_count == 0, "erase takes a switch"); c:end_action()
    c:undo(); c:clear(); check(c.switch_count == 0, "clear takes the switches")
    c:undo(); check(c.switch_count == 1, "undoing clear restores them")
end
do
    -- Saved and loaded with their links, whatever order things were placed in; old saves still load.
    local b = F.new_board()
    local w, n1 = line_to_switch(b)
    local tbl = surface("coffee table")
    b:place_ball(0, -26, 0)
    local q = b:place(-20, 1, 0, tbl.h, "sage")
    local q2 = b:place(-19.4, 1, 0, tbl.h, "navy")
    b:begin_action(); b:link_switch(w, q.id); b:set_switch_lamp(w, true); b:link_switch(w, q.id); b:end_action()
    local b2, ok = F.deserialize(F.serialize(b))
    check(ok and b2.switch_count == 1 and b2.count == b.count, "switches save and load")
    local w2
    for _, s in pairs(b2.switches) do w2 = s end
    local t2 = b2.pieces[w2.target]
    check(t2 and near(t2.x, q.x, 1e-3) and near(t2.z, q.z, 1e-3), "still linked to the same domino")
    check(w2.dir == -1 and w2.lamp == true, "with its direction and lamp setting")
    local function trace(res)
        local t = {}
        for _, e in ipairs(res.switches) do t[#t + 1] = string.format("%.6f", e.t) end
        for _, f in ipairs(res.order) do t[#t + 1] = string.format("%.6f", f.t) end
        return table.concat(t, ";")
    end
    check(trace(F.simulate(b)) == trace(F.simulate(b2)), "the loaded build runs the same")
    check(n1 > 3 and q2 ~= nil, "(build placed)")
    local old, ok2 = F.deserialize("TOPPLE-FREE 1\nb 1.000 2.000 0.000\nd 1.000 4.000 0.000 0.0000 cream\n")
    check(ok2 and old.count == 1 and old.switch_count == 0, "an old save loads")
    local gone = F.new_board()
    local g = gone:place_switch(0, -26, 0)
    local gq = gone:place(5, -26, 0, 0, "navy")
    gone:begin_action(); gone:link_switch(g, gq.id); gone:remove(gq.id); gone:end_action()
    local reload = F.deserialize(F.serialize(gone))
    local rs
    for _, s in pairs(reload.switches) do rs = s end
    check(rs and rs.target == nil, "a link to a removed domino saves as no link")
end
do
    -- A long relay: domino, switch, far domino, switch... stays quick.
    local b = F.new_board()
    local n, prev = 0, nil
    for i = 0, 31 do
        local x = -30 + i * 2
        local d = b:place(x, -32, 0, 0, "cream")
        local w = b:place_switch(x + 0.9, -32, 0)
        if d and w then
            n = n + 1
            if prev then b:begin_action(); b:link_switch(prev, d.id); b:end_action() end
            prev = w
        end
    end
    local t0 = os.clock()
    local res = F.simulate(b)
    local dt = os.clock() - t0
    print(string.format("  relay of %d switches: %d pressed, simulated in %.1f ms", n, #res.switches, dt * 1000))
    check(n >= 30 and #res.switches == n and res.toppled == n, "the whole relay runs: " .. #res.switches .. " of " .. n)
    check(dt < 0.2, "the relay took " .. dt .. " s")
end

-- Ramps.
-- From the floor up to the coffee table's near edge (y0), along y at x.
local function table_ramp(b, x)
    return b:place_ramp(x or -12, -25, 0, x or -12, 1, surface("coffee table").h)
end
do
    -- Fitting.
    local b = F.new_board()
    local tbl = surface("coffee table")
    local r, why = table_ramp(b)
    check(r ~= nil, "a ramp goes from the floor to the table: " .. tostring(why))
    check(near(r.y1, tbl.y0) and near(r.z1, tbl.h) and near(r.z0, 0) and near(r.x1, -12), "its top stops at the table's edge")
    check(r.n == 44 and near(r.rise, 0.2) and r.d >= F.RAMP.run, "in steps no higher than a rise and no shorter than a run")
    check(b.ramp_count == 1 and b.count == 0, "it is its own kind of piece")
    check(b:pick_ramp(-12, -15, r.z0 + 3) == r, "a ramp can be picked")
    local rd = F.new_board():place_ramp(-12, 1, tbl.h, -12, -25, 0)
    check(rd and near(rd.y0, -25) and near(rd.y1, tbl.y0), "dragged downhill it is the same ramp")
    local _, w = F.new_board():place_ramp(0, -26, 0, 5, -26, 0)
    check(w == "flat", "not on one level, got " .. tostring(w))
    _, w = F.new_board():place_ramp(-12, -10, 0, -12, 1, tbl.h)
    check(w == "steep", "not too steep, got " .. tostring(w))
    _, w = F.new_board():place_ramp(-12, -25, 0, -12, -30, 0.5)
    check(w == "air", "its top must be on a surface, got " .. tostring(w))
    _, w = F.new_board():place_ramp(-24.5, -25, 0, -24.5, 1, tbl.h)
    check(w == "air", "and fit within the surface's width, got " .. tostring(w))
    _, w = F.new_board():place_ramp(-10, 40, 0, -10, 1, tbl.h)
    check(w ~= nil, "not through the sofa or out of the room, got " .. tostring(w))
    local c = F.new_board()
    table_ramp(c)
    _, w = table_ramp(c, -12.5)
    check(w == "furniture", "not through another ramp, got " .. tostring(w))
    local d = F.new_board()
    d:place(-12, -15, 0, 0, "cream")
    _, w = table_ramp(d)
    check(w == "crowded", "not over a standing domino, got " .. tostring(w))
    local e = F.new_board()
    table_ramp(e)
    _, w = e:place(-12, -15, 0, 0, "cream")
    check(w == "furniture", "no domino on the floor inside it, got " .. tostring(w))
    _, w = e:place_ball(-12, -15, 0)
    check(w == "furniture", "no ball inside it, got " .. tostring(w))
    _, w = e:place_switch(-12, -15, 0)
    check(w == "furniture", "no switch inside it, got " .. tostring(w))
end
do
    -- A chain climbs it onto the table and carries on along the top; and comes down it.
    local b = F.new_board()
    local tbl = surface("coffee table")
    table_ramp(b)
    local n = line(b, -12, -27, -12, 2, 0)
    local top, steps = 0, 0
    for _, p in pairs(b.pieces) do
        top = math.max(top, p.z)
        if p.z > 0.01 and p.z < tbl.h - 0.01 then steps = steps + 1 end
    end
    check(near(top, tbl.h) and steps > 20, "a line climbs the steps onto the table: top " .. top .. ", " .. steps .. " on the steps")
    local res = F.simulate(b)
    check(res.toppled == n, "the chain climbs all the way: " .. res.toppled .. " of " .. n)
    local b2 = F.new_board()
    table_ramp(b2)
    local n2 = line(b2, -12, 2, -12, -27, tbl.h)
    local low = 99
    for _, p in pairs(b2.pieces) do low = math.min(low, p.z) end
    check(near(low, 0), "a line comes down it to the floor")
    local res2 = F.simulate(b2)
    check(res2.toppled == n2, "and the chain runs down: " .. res2.toppled .. " of " .. n2)
end
do
    -- A ball pushed off the table rolls down it, speeds up and bowls over a chain on the floor.
    local b = F.new_board()
    local tbl = surface("coffee table")
    table_ramp(b)
    local _, q = pusher(b, -12, 2, -pi / 2, tbl.h)
    local n = line(b, -12, -28, -12, -33, 0)
    local res = F.simulate(b)
    local r = ball_of(res, q)
    check(r ~= nil, "the ball goes")
    local lowest, last, prev_z, rises, descending = 99, nil, nil, 0, true
    for i = 1, #r.pts, 4 do
        local y, z = r.pts[i + 2], r.pts[i + 3]
        lowest = math.min(lowest, z)
        if y < -25 then descending = false end       -- the first run down is over (it may roll back a little later)
        if descending and y < -5 then
            if prev_z and z > prev_z + 1e-6 then rises = rises + 1 end
            prev_z = z
        end
        last = y
    end
    check(lowest < 0.05, "it reaches the floor, lowest " .. lowest)
    check(rises == 0, "going steadily down the slope, not bouncing on the steps")
    check(res.toppled == n + 1, "and knocks over the chain below: " .. res.toppled .. " of " .. (n + 1))
    check(last < -25, "it ends beyond the foot of the ramp, y " .. last)
end
do
    -- Up a gentle ramp a ball climbs; up a steep one it stops short and rolls back.
    local b = F.new_board()
    local book = surface("book 1")
    local p = b:place_ramp(24, -30, 0, 24, -20, book.h)
    check(p ~= nil and near(p.y1, book.y0), "a ramp up to the books")
    local _, q = pusher(b, 24, -32, pi / 2, 0)
    local r = ball_of(F.simulate(b), q)
    local top = 0
    for i = 1, #r.pts, 4 do top = math.max(top, r.pts[i + 3]) end
    check(top < book.h, "a push cannot pay for the climb to the books, top " .. top)
    local rug = surface("rug")
    local e2 = F.new_board()
    check(e2:place_ramp(-12, -22, 0, -12, -10, rug.h) ~= nil, "a ramp up to the rug")
    local _, q3 = pusher(e2, -12, -24, pi / 2, 0)
    local r3 = ball_of(F.simulate(e2), q3)
    check(r3.y < -22 and near(r3.z, 0, 0.02), "even 6 mm is more than a push pays for: it rolls back off the ramp, y " .. r3.y)
    local c = F.new_board()
    table_ramp(c)
    local _, q2 = pusher(c, -12, -27.5, pi / 2, 0)
    local r2 = ball_of(F.simulate(c), q2)
    local top2 = 0
    for i = 1, #r2.pts, 4 do top2 = math.max(top2, r2.pts[i + 3]) end
    check(top2 > 0.15 and top2 < 1, "up the long ramp it climbs only what its speed pays for, top " .. top2)
    check(r2.y < -25, "and rolls back to the floor, y " .. r2.y)
end
do
    -- The ramp's sides are solid to a ball and to a falling domino.
    local b = F.new_board()
    table_ramp(b)
    local _, q = pusher(b, -20, -15, 0, 0)
    local r = ball_of(F.simulate(b), q)
    check(r.x < -13.3, "the side turns a ball back, ended at x " .. r.x)
    local c = F.new_board()
    table_ramp(c)
    local d = c:place(-13.6, -15, 0, 0, "cream")
    local res = F.simulate(c)
    check(res.falls[d.id].blocked, "a domino falls against its side")
end
do
    -- With other pieces: a switch on the table, a ball on the ramp's path, saved and undone.
    local b = F.new_board()
    local r = table_ramp(b)
    local n = line(b, -12, -27, -12, 0, 0)
    local on = 0
    for _, p in pairs(b.pieces) do if p.z > 0.01 and p.z < r.z1 - 1e-3 then on = on + 1 end end
    local b2, ok = F.deserialize(F.serialize(b))
    check(ok and b2.ramp_count == 1 and b2.count == n, "ramps save and load")
    local loaded
    for _, x in pairs(b2.ramps) do loaded = x end
    check(loaded.n == r.n and near(loaded.y1, r.y1, 1e-3), "the same ramp")
    check(F.simulate(b2).toppled == F.simulate(b).toppled, "the loaded build runs the same")
    local _, w = b:place_ramp(-12, -25, 0, -12, 1, 8.8)
    check(w == "furniture", "(still one there)")
    b:begin_action(); b:remove(r.id); b:end_action()
    check(b.ramp_count == 0 and b.count == n - on, "removing a ramp takes the dominoes on it: " .. b.count .. " left")
    check(b:all_surfaces() == room.surfaces and b:all_solids() == room.solids, "and its steps")
    b:undo()
    check(b.ramp_count == 1 and b.count == n, "undo brings them all back")
    check(F.simulate(b).toppled == n, "and the chain still climbs")
    b:redo(); b:undo()
    local c = F.new_board()
    c:begin_action(); local x = table_ramp(c); c:end_action()
    c:undo(); check(c.ramp_count == 0, "undo takes the ramp away")
    check(select(2, c:place(-12, -15, 0, 0, "cream")) == nil, "and the floor under it is clear")
    c:clear(); c:redo()
    check(x ~= nil, "(ramp built)")
    local e = F.new_board()
    table_ramp(e)
    line(e, -12, -27, -12, 2, 0)
    local before = e.count
    check(e:erase_at(-12, -15, 3.8, 1.2) > 0 and e.ramp_count == 1 and e.count < before, "a brush over its dominoes leaves the ramp")
    local f2 = F.new_board()
    table_ramp(f2)
    check(f2:erase_at(-12, -15, 4, 0.5) == 1 and f2.ramp_count == 0, "a brush over a bare ramp takes it")
    local g = F.new_board()
    table_ramp(g); g:clear()
    check(g.ramp_count == 0, "clear takes the ramps")
    local old, ok2 = F.deserialize("TOPPLE-FREE 1\nd 1.000 2.000 0.000 0.0000 cream\n")
    check(ok2 and old.ramp_count == 0, "an old save loads")
    local spots = F.ramp_spots(r)
    check(#spots == 13 and near(spots[1].h, 0) and near(spots[13].h, r.z1), "the preview climbs the ramp")
end
do
    -- A big build with the most ramps stays quick.
    local b = F.new_board()
    local tbl = surface("coffee table")
    local made = 0
    for i = 0, F.RAMP.cap - 1 do
        if b:place_ramp(-22.5 + i * 2.7, -25, 0, -22.5 + i * 2.7, 1, tbl.h) then made = made + 1 end
    end
    b:begin_action()
    b:place_spots(F.field_spots(2, 6, 38, 6, 30), nil, 0)
    b:end_action()
    local t0 = os.clock()
    local res = F.simulate(b)
    local dt = os.clock() - t0
    print(string.format("  %d dominoes with %d ramps: %d fell, simulated in %.0f ms", b.count, made, res.toppled, dt * 1000))
    check(made == F.RAMP.cap, "the most ramps fit: " .. made)
    check(res.toppled >= 1500 and dt < 1.0, "simulating with ramps took " .. dt .. " s, " .. res.toppled .. " fell")
end

-- What stands on the bookshelf is solid, and the rest of the top is free.
do
    local top = surface("bookshelf")
    local b = F.new_board()
    for _, spot in ipairs({ { 18, 30, "vase" }, { 29.7, 29.6, "plant pot" } }) do
        local _, why = b:place(spot[1], spot[2], 0, top.h, "cream")
        check(why == "furniture", "no domino inside the " .. spot[3] .. ", got " .. tostring(why))
        _, why = b:place_ball(spot[1], spot[2], top.h)
        check(why == "furniture", "no ball inside the " .. spot[3] .. ", got " .. tostring(why))
    end
    check(b:place(23, 30, 0, top.h, "cream") ~= nil, "the top between them is free")
    check(b:place(14, 30, 0, top.h, "cream") ~= nil, "and beside them")
    local c = F.new_board()
    local n = line(c, 15, 27, 33, 27, top.h)
    check(F.simulate(c).toppled == n and n > 20, "a chain runs along the front, past them both")
    local d = F.new_board()
    local _, q = pusher(d, 22, 30, pi, top.h)
    local r = ball_of(F.simulate(d), q)
    check(r.x > 19.69, "the vase turns a ball back, ended at x " .. r.x)
    local e = F.new_board()
    local p = e:place(26.4, 29.6, 0, top.h, "sage")
    local q2 = e:place(27, 29.6, 0, top.h, "navy")
    local res = F.simulate(e)
    check(res.falls[p.id] and res.falls[q2.id] and res.falls[q2.id].blocked, "a domino falls against the plant pot")
    for _, s in ipairs(room.solids) do
        if s.name == "vase" or s.name == "plant pot" or s.name == "shelf plant" then check(s.z0 >= top.h, s.name .. " stands on the top, not through the shelf") end
    end
end

-- Real motion: what a ball does on a slope follows from gravity.
do
    local g, k = F.BALL.g, F.RAMP.grav
    check(near(g, 196.2, 0.01), "gravity is 9.81 m/s2 at 1 unit = 5 cm")
    check(near(k, 5 / 7, 1e-9), "a rolling solid ball feels 5/7 of the slope's pull")
    -- Down: the speed at the foot of a ramp is what the drop gives, less rolling resistance.
    local b = F.new_board()
    local tbl = surface("coffee table")
    local r = table_ramp(b)
    local _, q = pusher(b, -12, 2, -pi / 2, tbl.h)
    local path = ball_of(F.simulate(b), q)
    local P, foot = path.pts, nil
    for i = 5, #P, 4 do
        if P[i + 2] < -24.5 and not foot then foot = abs(P[i + 2] - P[i - 2]) / (P[i] - P[i - 4]) end
    end
    local v0 = abs(P[7] - P[3]) / (P[5] - P[1])                  -- its speed as the domino sent it off
    local ideal = sqrt(v0 * v0 + 2 * k * g * tbl.h) * cos(math.atan(r.slope))      -- measured along the floor
    check(foot > ideal * 0.82 and foot < ideal * 1.02, "speed at the foot (a light ball loses some to the air) " .. foot .. " against the drop's " .. ideal)
    check(r ~= nil, "(ramp built)")
    -- Up: it climbs to the height its speed pays for, then rolls back.
    local c = F.new_board()
    table_ramp(c)
    local _, q2 = pusher(c, -12, -27.5, pi / 2, 0)
    local p2 = ball_of(F.simulate(c), q2)
    local top = 0
    for i = 1, #p2.pts, 4 do top = math.max(top, p2.pts[i + 3]) end
    local v1 = abs(p2.pts[7] - p2.pts[3]) / (p2.pts[5] - p2.pts[1])
    local rise = v1 * v1 / (2 * k * g)
    check(top < rise + F.RAMP.rise + 0.05 and top > rise * 0.5, "it climbs " .. top .. ", its speed pays for " .. rise)
    -- A pendulum's period is 2 pi sqrt(L / g).
    local e = F.new_board()
    local _, s = swing_hit(e, -10, -28, 0)
    local sw = swing_of(F.simulate(e), s)
    local t0, t_cross
    for i = 3, #sw.pts - 2, 2 do
        if sw.pts[i + 1] < 0 and sw.pts[i + 3] >= 0 and not t0 then t0 = sw.pts[i]
        elseif t0 and not t_cross and sw.pts[i + 1] > 0 and sw.pts[i + 3] <= 0 then t_cross = sw.pts[i] end
    end
    local half = t_cross - t0
    local ideal_half = pi * sqrt(F.SWING.len / g)
    check(abs(half - ideal_half) < ideal_half * 0.1, "half a swing takes " .. half .. " s against " .. ideal_half)
end

print(checks .. " checks passed")
print("PASS free rules")
