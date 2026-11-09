-- luajit tests/hall_test.lua  (run from the Topple folder)
-- The Great Hall's rules, without the engine: it must agree with Free Build's chain on the same dominoes, keep its
-- promises about a build (undo, save, erase, the box's size), and run a million dominoes in reasonable time.
package.path = "Assets/Scripts/?.lua;" .. package.path
local function read(path)
    local f = assert(io.open("Assets/" .. path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end
local F = assert(load(read("Scripts/topple_free.lua"), "@topple_free.lua", "t", _G))()
F.set_room(assert(load(read("Scripts/free_room.lua"), "@free_room.lua", "t", _G))())
local HC = assert(load(read("Scripts/topple_hall_core.lua"), "@topple_hall_core.lua", "t", _G))()(F)

local checks = 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then error("FAILED: " .. msg, 2) end
end

local falls
local sink = { clear = function() end, append = function() end, hide = function() end, rebuild = function() end,
    stand_all = function() end, fall = function(flat, n)
        for i = 0, n - 1 do falls[#falls + 1] = { id = flat[i * 6 + 1], t0 = flat[i * 6 + 2], tc = flat[i * 6 + 3], side = flat[i * 6 + 6] } end
    end }

local function fresh()
    HC.ops, HC.redo_ops = {}, {}
    HC.init(sink)
    falls = {}
end

-- The same line in both sets of rules: every domino falls, and at the same moments.
do
    local b = F.new_board()
    b:begin_action(); b:place_line(-30, 0, 30, 0, nil, 0); b:end_action()
    local res = F.simulate(b)
    fresh()
    HC.add({ k = "line", ax = -30, ay = 0, bx = 30, by = 0 })
    check(HC.count() == b.count, "the same dominoes: " .. HC.count() .. " vs " .. b.count)
    check(HC.tip(), "it tips")
    HC.advance(1e9)
    check(HC.toppled == res.toppled, "the whole line falls alike: " .. HC.toppled .. " vs " .. res.toppled)
    check(HC.finished(1e9), "and the run ends")
    check(#falls == HC.toppled, "the engine hears of every fall once")
    check(math.abs(HC.last_t - res.duration) < 0.2, "over the same time: " .. HC.last_t .. " vs " .. res.duration)
end

-- A field in both.
do
    local b = F.new_board()
    b:begin_action(); b:place_spots(F.field_spots(-20, -30, -20, -12, 6), nil, 0); b:end_action()   -- clear floor
    local res = F.simulate(b)
    fresh()
    HC.add({ k = "field", ax = -20, ay = -30, bx = -20, by = -12, w = 6 })
    check(HC.count() == b.count, "the same field: " .. HC.count() .. " vs " .. b.count)
    HC.tip(); HC.advance(1e9)
    check(math.abs(HC.toppled - res.toppled) <= res.toppled * 0.02, "a field falls alike: " .. HC.toppled .. " vs " .. res.toppled)
end

-- Laying over dominoes refuses the spots already taken; off the floor is refused too.
do
    fresh()
    HC.add({ k = "line", ax = -5, ay = 0, bx = 5, by = 0 })
    local n = HC.count()
    HC.add({ k = "line", ax = -5, ay = 0, bx = 5, by = 0 })
    check(HC.count() == n, "the second copy finds every place taken")
    fresh()
    HC.add({ k = "line", ax = 1190, ay = 0, bx = 1300, by = 0 })
    check(HC.count() > 0 and HC.count() < 30, "a line stops at the edge of the hall: " .. HC.count())
end

-- Erase, undo and the starter.
do
    fresh()
    HC.add({ k = "line", ax = -30, ay = 0, bx = 30, by = 0 })
    local n = HC.count()
    HC.add({ k = "erase", pts = { 0, 0, 2 } })
    local after = HC.count()
    check(after < n and after > 0, "the brush lifts some")
    HC.tip(); HC.advance(1e9)
    check(HC.toppled < after, "a gap stops the chain: " .. HC.toppled .. " of " .. after)
    HC.stand()
    check(HC.undo() and HC.count() == n, "undo brings them back")
    check(HC.redo() and HC.count() == after, "redo lifts them again")
    fresh()
    HC.add({ k = "line", ax = -30, ay = 0, bx = 30, by = 0 })
    local i, x, y = HC.starter()
    check(i == 1, "the first domino laid starts it")
    local j, jx, jy = HC.pick(10, 0, 1)
    HC.add({ k = "start", x = jx, y = jy, dir = 1 })
    check(HC.starter() == j, "the chosen domino starts it")
    HC.tip(); HC.advance(1e9)
    check(HC.toppled < HC.count() and HC.toppled > 5, "the chain runs on from there only: " .. HC.toppled)
    check(x and y, "(starter position)")
end

-- A save is the shapes, and a damaged line loses only its own.
do
    fresh()
    HC.add({ k = "field", ax = -20, ay = -2, bx = 20, by = -2, w = 20, paint = "navy" })
    HC.add({ k = "line", ax = -30, ay = 12, bx = 30, by = 12 })
    HC.add({ k = "draw", pts = { -30, 20, 0, 22, 30, 20 }, paint = "cream" })
    HC.add({ k = "spiral", cx = 0, cy = -40, sx = 8, sy = -40, cw = true })
    HC.add({ k = "erase", pts = { 0, 12, 3, 2, 12, 3 } })
    HC.add({ k = "start", x = -5, y = -2, dir = -1 })
    local n = HC.count()
    local text = HC.serialize()
    check(#text < 1000, "a save is small: " .. #text .. " bytes")
    check(HC.deserialize(text), "it reads back")
    HC.rebuild()
    check(HC.count() == n, "and lays the same build: " .. HC.count() .. " vs " .. n)
    check(not HC.deserialize("rubbish"), "junk is refused")
    check(HC.deserialize("TOPPLE-HALL 1\nfield a b c d e -\nline 0 0 10 0 -\nerase 1 2\nsample nan\n"), "damage is survived")
    HC.rebuild()
    check(#HC.ops == 1 and HC.count() > 0, "only the good line is laid")
end

-- A picture: its pixels land where they should, the wave crosses all of it, and it survives saving.
do
    fresh()
    local colors = {}
    local keep = sink.append
    sink.append = function(flat, n) for i = 0, n - 1 do colors[#colors + 1] = flat[i * 5 + 5] end end
    local loads = 0
    sink.load_picture = function(name)
        if name ~= "four.png" then return nil end
        loads = loads + 1
        return { w = 2, h = 2, rgb = string.char(200, 0, 0,  0, 200, 0,  0, 0, 200,  200, 200, 0) }    -- red green / blue yellow
    end
    local function rgb(r, g, b) return r + g * 256 + b * 65536 + 4278190080 end
    local op = { k = "picture", src = "four.png", ax = -60, ay = 0, bx = 40, by = 0 }
    HC.add(op)
    local w, fan, len, n = HC.picture_layout("four.png", 100)
    check(math.abs(len - w) < 1e-6 and math.abs(fan + len - 100) < 1e-6, "a square picture is as long as it is wide, after its fan")
    check(math.abs(HC.count() - n) < n * 0.03, "the estimate is close: " .. n .. " vs " .. HC.count())
    local function at(s, l) return colors[(HC.pick(-60 + s, l, 1.5))] end
    local q = len / 4
    check(at(fan + q, w / 4) == rgb(200, 0, 0), "top of the picture is on the left of the wave: its first pixel")
    check(at(fan + 3 * q, w / 4) == rgb(0, 200, 0), "the second pixel further along")
    check(at(fan + q, -w / 4) == rgb(0, 0, 200) and at(fan + 3 * q, -w / 4) == rgb(200, 200, 0), "the bottom row")
    check(at(fan / 2, 2) == rgb(200, 0, 0) and at(fan / 2, -2) == rgb(0, 0, 200), "the fan carries the first column's colours")
    HC.tip(); HC.advance(1e9)
    check(HC.toppled > HC.count() * 0.97, "the wave crosses all of it: " .. HC.toppled .. " of " .. HC.count())
    HC.stand()
    local count = HC.count()
    local text = HC.serialize()
    check(HC.deserialize(text) and #HC.ops == 1 and HC.ops[1].src == "four.png", "it saves by name")
    colors = {}
    HC.rebuild()
    check(HC.count() == count and loads == 1, "and lays the same again without reading the file twice")
    -- A drawing is carried in the save itself; a missing file only loses its own shape.
    fresh()
    local cells = string.rep("1", 4) .. string.rep("4", 2)
    HC.add({ k = "picture", src = "draw:3:2:" .. cells, ax = 0, ay = 0, bx = 40, by = 0 })
    check(HC.count() > 100, "a drawing is laid: " .. HC.count())
    check(HC.deserialize(HC.serialize()) and HC.ops[1].src:match("^draw:3:2:"), "and is kept in the save")
    fresh()
    HC.add({ k = "picture", src = "gone.png", ax = 0, ay = 0, bx = 40, by = 0 })
    HC.add({ k = "line", ax = -10, ay = 20, bx = 10, by = 20 })
    check(HC.count() > 10 and HC.count() < 40, "a missing picture lays nothing and spoils nothing else")
    sink.append, sink.load_picture = keep, nil
end

-- A splitter: every branch gets the wave, right to its far end, for any number of branches and heading.
do
    for n = HC.SPLIT.min, HC.SPLIT.max do
        for _, a in ipairs({ 0, 0.7, 2.4 }) do
            fresh()
            local x0, y0 = 11 * math.cos(a), 11 * math.sin(a)
            HC.add({ k = "line", ax = 0, ay = 0, bx = x0, by = y0 })
            local i = HC.count()
            local op = { k = "splitter", ax = x0 + 0.62 * math.cos(a), ay = y0 + 0.62 * math.sin(a),
                bx = 90 * math.cos(a), by = 90 * math.sin(a), n = n }
            HC.add(op)
            local _, _, paths = HC.splitter_paths(op)
            check(#paths == n, "one path per branch")
            check(i > 5, "(the line in)")
            HC.tip(); HC.advance(1e9)
            for j, p in ipairs(paths) do
                local tail = HC.pick(p[#p - 1], p[#p], 1.3)
                check(tail and HC.fell(tail), n .. " branches at " .. a .. ": branch " .. j .. " reaches its end")
            end
            local _, _, _, _ = i, x0, y0, a
        end
    end
    fresh()
    HC.add({ k = "splitter", ax = 0, ay = 0, bx = 80, by = 0, n = 4, paint = "navy" })
    local n = HC.count()
    check(n > 100 and HC.deserialize(HC.serialize()) and HC.ops[1].n == 4 and HC.ops[1].paint == "navy", "a splitter saves")
    HC.rebuild()
    check(HC.count() == n, "and lays the same again")
    check(not HC.splitter_paths({ ax = 0, ay = 0, bx = 3, by = 0, n = 3 }), "too short a drag has no room for one")
end

-- Bells: beside a line, ringing once a run when the wave gets there, and not before.
do
    fresh()
    HC.add({ k = "line", ax = -30, ay = 0, bx = 30, by = 0 })
    local x, y, a = HC.bell_spot(0, 2)
    check(x and math.abs(y - 2.2) < 0.4 and math.abs(a) < 1e-6, "a click beside a line hangs the bell along it, on that side")
    HC.add({ k = "bell", x = x, y = y, a = a })
    local x2, y2 = HC.bell_spot(20, -2)
    check(x2 and y2 < 0, "the other side of the line works too")
    HC.add({ k = "bell", x = x2, y = y2, a = 0 })
    check(HC.bell_count() == 2, "two bells")
    check(not HC.bell_spot(x + 1, 6), "no bell on top of another")
    local n = HC.count()
    HC.add({ k = "line", ax = x - 6, ay = y, bx = x + 6, by = y })
    check(not HC.pick(x, y, 1.9), "no domino stands where a bell does")
    HC.ops[#HC.ops] = nil
    HC.rebuild()
    check(HC.count() == n and HC.bell_count() == 2, "and it comes back the same")

    HC.tip()
    local t = 0
    local rung_at = {}
    while t < 60 and not HC.finished(t) do
        t = t + 1 / 60
        HC.advance(t)
        for i = #HC.rung, 1, -1 do rung_at[#rung_at + 1] = { b = HC.rung[i], t = t }; HC.rung[i] = nil end
    end
    check(#rung_at == 2 and HC.rung_total == 2, "each rings exactly once: " .. #rung_at)
    table.sort(rung_at, function(p, q) return p.t < q.t end)
    check(rung_at[1].b.x < rung_at[2].b.x and rung_at[2].t > rung_at[1].t + 0.5, "in the order the wave reaches them")
    HC.stand()
    HC.tip(); HC.advance(1e9)
    check(HC.rung_total == 2, "and again on the next run")
    HC.stand()

    -- A gap before the bell: the wave never arrives, the bell stays silent.
    HC.add({ k = "erase", pts = { -5, 0, 2 } })
    HC.tip(); HC.advance(1e9)
    check(HC.rung_total == 0, "a chain that stops short rings nothing: " .. HC.rung_total)
    HC.stand()
    HC.add({ k = "erase", pts = { x, y, 1 } })
    check(HC.bell_count() == 1, "the brush lifts a bell")
    HC.ops = { { k = "line", ax = -9, ay = 0, bx = 9, by = 0 }, { k = "bell", x = 0, y = 2.2, a = 0 } }
    HC.rebuild()
    local text = HC.serialize()
    check(HC.deserialize(text) and #HC.ops == 2 and HC.ops[2].k == "bell", "a bell saves")
    HC.rebuild()
    check(HC.bell_count() == 1, "and hangs again")
end

-- Solid dominoes: at every moment of a fall, a domino never passes through the one it struck, for spacings from the
-- closest allowed to the widest that still topple, and when the next gap differs from this one.
do
    local FW = assert(load(read("Scripts/topple_free_world.lua"), "@topple_free_world.lua", "t", _G))()(F)
    local T, H = F.DOM.t, F.DOM.h
    local function fall_of(d, t0)
        local c = math.max(d - T, 0.02)
        local contact = math.asin(c / H)
        local tc = t0 + F.fall_time(contact)
        return { t = t0, tc = tc, contact = contact, final = F.rest_angle(contact), t_end = tc + 0.15 }
    end
    local function corners(x, a)
        local out = {}
        for _, p in ipairs({ { 0, 0 }, { -T, 0 }, { -T, H }, { 0, H } }) do
            out[#out + 1] = { x + p[1] * math.cos(a) + p[2] * math.sin(a), -p[1] * math.sin(a) + p[2] * math.cos(a) }
        end
        return out
    end
    local function overlap(A, B)       -- depth of two convex quads' overlap (separating axes); 0 if apart
        local depth = 1e9
        for _, Q in ipairs({ A, B }) do
            for i = 1, 4 do
                local p, q = Q[i], Q[i % 4 + 1]
                local nx, ny = q[2] - p[2], p[1] - q[1]
                local L = math.sqrt(nx * nx + ny * ny)
                nx, ny = nx / L, ny / L
                local a0, a1, b0, b1 = 1e9, -1e9, 1e9, -1e9
                for _, v in ipairs(A) do local s = v[1] * nx + v[2] * ny; a0, a1 = math.min(a0, s), math.max(a1, s) end
                for _, v in ipairs(B) do local s = v[1] * nx + v[2] * ny; b0, b1 = math.min(b0, s), math.max(b1, s) end
                depth = math.min(depth, math.min(a1, b1) - math.max(a0, b0))
            end
        end
        return math.max(0, depth)
    end
    local worst, at = 0, ""
    for d1 = 0.45, 1.2001, 0.05 do
        for d2 = 0.45, 1.2001, 0.05 do
            local f1 = fall_of(d1, 0)
            local f2 = fall_of(d2, f1.tc)
            for t = 0, f2.t_end + 0.5, 0.001 do
                local o = overlap(corners(0, FW.fall_angle(f1, t)), corners(d1, FW.fall_angle(f2, t)))
                if o > worst then worst, at = o, string.format("gaps %.2f, %.2f at %.3f s", d1, d2, t) end
            end
        end
    end
    print(string.format("  deepest overlap between falling dominoes: %.4f (%s)", worst, at))
    check(worst < 0.002, "a domino never passes through the next: " .. worst .. " at " .. at)
end

-- The sample comes out near its size, on the floor, in time; and a million fall.
do
    fresh()
    local t0 = os.clock()
    local co = coroutine.create(function() HC.add({ k = "sample", n = 1000000 }) end)
    local slices = 0
    while coroutine.status(co) ~= "dead" do
        local ok, err = coroutine.resume(co)
        check(ok, tostring(err))
        slices = slices + 1
    end
    local built = os.clock() - t0
    local n = HC.count()
    check(n >= 950000 and n <= 1050000, "the million is a million: " .. n)
    check(slices > 3, "laying it hands back between slices: " .. slices)
    local b = 0
    for _ = 1, 1 do b = b + 1 end
    t0 = os.clock()
    check(HC.tip(), "the million tips")
    local t, frames = 0, 0
    local worst = 0
    while not HC.finished(t) do
        local f0 = os.clock()
        t = t + 1 / 30
        falls = {}
        HC.advance(t)
        worst = math.max(worst, os.clock() - f0)
        frames = frames + 1
        if t > 1000 then break end
    end
    local ran = os.clock() - t0
    print(string.format("  %d dominoes laid in %.0f ms; %d fell over %.0f s of chain, %.0f ms of work (worst frame %.1f ms)", n, built * 1000, HC.toppled, t, ran * 1000, worst * 1000))
    check(HC.toppled > n * 0.9, "almost all of a fan falls: " .. HC.toppled .. " of " .. n)
    check(worst < 0.05, "no frame of the wave takes long: " .. worst)
end

print(checks .. " checks passed")
print("PASS hall rules")
