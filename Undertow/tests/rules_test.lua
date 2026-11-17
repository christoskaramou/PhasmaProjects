-- luajit tests/rules_test.lua [quick | pass <level> [seeds] | all]   (run from the Undertow folder)
-- Pure-Lua tests of the rules (Assets/Scripts/uw_rules.lua) and the bot (uw_bot.lua):
--   1. a taut pendulum conserves energy within 1% over a full swing
--   2. release keeps the float's velocity
--   3. water: shallow and fast skips (keeping most along-surface speed); steep, or slow, sinks
--   4. every hazard kind ends the run (a float on a mesh point of each), a clear float does not
--   5. the same seed and input (the bot) give the same run at 30, 60 and 144 fps
--   6. doing nothing ends the run
--   7. passability: the bot survives 2,000 units at a difficulty step for 20 seeds  (mode "pass <level>")
-- The hit shapes against the drawn pieces: tests/hit_shapes_test.py (meshes) and tests/view_smoke.lua (placement).
local function load_mod(path)
    local f = assert(io.open("Assets/" .. path, "rb")); local src = f:read("*a"); f:close()
    return assert(loadstring(src, "@" .. path))()
end
local D = load_mod("Scripts/uw_data.lua")
local Sea = load_mod("Scripts/uw_sea.lua")(D)
local Course = load_mod("Scripts/uw_course.lua")(D, Sea)
local R = load_mod("Scripts/uw_rules.lua")(D, Sea, Course)
local B = load_mod("Scripts/uw_bot.lua")(D, R)
local RL = D.RULES
local G = RL.G
local mode = arg[1] or "quick"
local fails = 0
local function check(ok, msg)
    print((ok and "ok   " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
end

-- a course holding only the given items (no generation), for staged situations
local function staged(items)
    local c = Course.new_play(1, {})
    c.items, c.plane = {}, {}
    for _, it in ipairs(items) do
        it.id = it.id or (#c.items + 1000)
        it.p = it.p or {}
        c.items[#c.items + 1] = it
        c.plane[#c.plane + 1] = it
    end
    table.sort(c.plane, function(a, b) return a.x < b.x end)
    c.gen_x = 1e9
    return c
end
local function state_on(course)
    local s = R.new(1, {})
    s.course = course
    s.last_x = -1e9
    return s
end

if mode == "quick" or mode == "all" then
    -- 1. energy over one swing on a fixed pier hook (no bob), chain 3.5, from 80 degrees (above the pump's PUMP_THETA,
    -- so the pendulum is free); nothing to touch
    do
        local pier = { kind = "pier", x = 1000 }
        local s = state_on(staged({ pier }))
        local hx, _, hz = Course.hook(pier, 0)
        s.hook, s.hx, s.hz, s.hvx, s.hvz = pier, hx, hz, 0, 0
        s.L, s.Lt, s.th, s.om, s.slack = 3.5, 3.5, math.rad(80), 0, false
        s.x, s.z = hx + 3.5 * math.sin(s.th), hz - 3.5 * math.cos(s.th)
        local function E() return G * (s.z - (hz - s.L)) + 0.5 * (s.vx * s.vx + s.vz * s.vz) end
        local E0, worst, crossings, last = E(), 0, 0, s.th
        local n = 0
        while crossings < 2 and n < 2000 do
            R.step(s, true)
            n = n + 1
            worst = math.max(worst, math.abs(E() - E0) / E0)
            if (last > 0) ~= (s.th > 0) then crossings = crossings + 1 end
            last = s.th
        end
        -- one full swing: out to -80 and back to the start side
        while s.om < 0 and n < 2000 do R.step(s, true); n = n + 1; worst = math.max(worst, math.abs(E() - E0) / E0) end
        check(s.mode == "swing" and crossings == 2 and worst < 0.01,
            string.format("pendulum energy over a full swing (%d steps): worst drift %.4f%% (< 1%%)", n, worst * 100))
    end

    -- 1b. the pump: a 30-degree swing grows to PUMP_THETA within 30 s and stays there (no runaway), so no run can hang
    -- on a hook for ever
    do
        local pier = { kind = "pier", x = 1000 }
        local s = state_on(staged({ pier }))
        local hx, _, hz = Course.hook(pier, 0)
        s.hook, s.hx, s.hz, s.hvx, s.hvz = pier, hx, hz, 0, 0
        s.L, s.Lt, s.th, s.om, s.slack = 3.5, 3.5, math.rad(30), 0, false
        s.x, s.z = hx + 3.5 * math.sin(s.th), hz - 3.5 * math.cos(s.th)
        local amp, reached = 0, nil
        for n = 1, 120 * 60 do
            R.step(s, true)
            local a = math.deg(math.abs(s.th))
            if n > 120 * 40 then amp = math.max(amp, a) end
            if not reached and a >= RL.PUMP_THETA - 0.5 then reached = n / 120 end
        end
        check(s.mode == "swing" and reached and reached < 30 and amp >= RL.PUMP_THETA - 1 and amp <= RL.PUMP_THETA + 2,
            string.format("the pump lifts a 30 deg swing to %.0f deg in %.1f s and holds it (amplitude %.1f deg after 40 s)",
                RL.PUMP_THETA, reached or -1, amp))
    end

    -- 2. release keeps velocity: swinging fast on a pier hook, let go at 30 degrees
    do
        local pier = { kind = "pier", x = 1000 }
        local s = state_on(staged({ pier }))
        local hx, _, hz = Course.hook(pier, 0)
        s.hook, s.hx, s.hz, s.hvx, s.hvz = pier, hx, hz, 0, 0
        s.L, s.Lt, s.th, s.om, s.slack = 3.2, 3.2, math.rad(30), 2.2, false
        s.x, s.z = hx + 3.2 * math.sin(s.th), hz - 3.2 * math.cos(s.th)
        s.vx, s.vz = 3.2 * 2.2 * math.cos(s.th), 3.2 * 2.2 * math.sin(s.th)
        R.step(s, true)
        local vx, vz, x, z = s.vx, s.vz, s.x, s.z
        R.step(s, false)
        local dt = RL.DT
        local ok = s.mode == "fly" and math.abs(s.vx - vx) < 1e-12 and math.abs(s.vz - (vz - G * dt)) < 1e-12
            and math.abs(s.x - (x + vx * dt)) < 1e-12 and math.abs(s.z - (z + vz * dt - 0.5 * G * dt * dt)) < 1e-12
        check(ok, string.format("release keeps the velocity (%.3f, %.3f) -> (%.3f, %.3f) and flies ballistically", vx, vz, s.vx, s.vz))
    end

    -- 3. water: a float hits the sea at a chosen angle to the surface and speed
    do
        local function hit_water(angle, speed)
            local s = state_on(staged({}))
            s.hook, s.mode = nil, "fly"
            local x, t = 500.3, 3.0
            s.t = t
            local h = Sea.height(x, 0, t)
            local e = 0.02
            local sx = (Sea.height(x + e, 0, t) - Sea.height(x - e, 0, t)) / (2 * e)
            local ht = (Sea.height(x, 0, t + e) - Sea.height(x, 0, t - e)) / (2 * e)
            local a = math.atan(sx) - math.rad(angle)          -- direction: into the surface by `angle`
            s.x, s.z = x, h + D.FLOAT_R - 0.004
            s.vx, s.vz = speed * math.cos(a), speed * math.sin(a) + ht
            s.t = t - RL.DT * RL.LEVEL.sea_rate[1]           -- the step advances the sea to t
            s.x = s.x - s.vx * RL.DT
            s.z = s.z - s.vz * RL.DT
            local vt0 = speed
            R.step(s, false)
            return s, vt0
        end
        local s1, v1 = hit_water(12, 8)
        local keep = s1.skips == 1 and math.sqrt(s1.vx ^ 2 + (s1.vz) ^ 2) or 0
        check(s1.mode == "fly" and s1.skips == 1 and s1.vx > 0.8 * 8 * math.cos(math.rad(12)) * RL.SKIP_KEEP,
            string.format("12 deg at 8 u/s skips (vx %.2f after, %.2f before)", s1.vx, 8 * math.cos(math.rad(12))))
        local s2 = hit_water(RL.SKIP_ANGLE + 6, 8)
        check(s2.mode == "dead" and s2.cause == "sink", string.format("%.0f deg at 8 u/s sinks (%s)", RL.SKIP_ANGLE + 6, tostring(s2.cause)))
        local s3 = hit_water(10, RL.SKIP_SPEED - 1.5)
        check(s3.mode == "dead" and s3.cause == "sink", string.format("10 deg at %.1f u/s sinks (%s)", RL.SKIP_SPEED - 1.5, tostring(s3.cause)))
        local s4 = hit_water(RL.SKIP_ANGLE - 3, RL.SKIP_SPEED + 0.6)
        check(s4.mode == "fly" and s4.skips == 1, string.format("%.0f deg at %.1f u/s (just inside the thresholds) skips", RL.SKIP_ANGLE - 3, RL.SKIP_SPEED + 0.6))
    end

    -- 4. hazards: a float centred on a mesh point of each piece breaks; the same float 1.5 units above clear water does not
    do
        local kinds = {
            { grid = "buoy_red", item = { kind = "buoy_red", x = 300 } },
            { grid = "buoy_white", item = { kind = "buoy_white", x = 300 } },
            { grid = "pier", item = { kind = "pier", x = 300 } },
            { grid = "boat_0", item = { kind = "boat", x = 300, p = { y = RL.BOAT_IN_Y, yaw = 0, roll = 0, inplane = true } } },
            { grid = "boat_180", item = { kind = "boat", x = 300, p = { y = RL.BOAT_IN_Y, yaw = 180, roll = 0, inplane = true } } },
            { grid = "bw_gap", item = { kind = "bw_gap", x = 300, p = { y = RL.GAP_IN_Y, inplane = true } } },
        }
        for _, k in ipairs(kinds) do
            local probes = R.HIT[k.grid].probes
            local broke, tried = 0, 0
            for pi = 1, #probes, 3 do
                local s = state_on(staged({ k.item }))
                s.hook, s.mode = nil, "fly"
                local t = 2.0
                s.t = t - RL.DT * RL.LEVEL.sea_rate[1]
                local ox, _, oz = Course.origin(k.item, t)
                local p = probes[pi]
                local lx, lz = p[1], p[3]
                if k.item.kind == "buoy_red" or k.item.kind == "buoy_white" then
                    local tx, _, tz = Course.tilt(lx, 0, lz, D.BUOY_TILT[2])
                    lx, lz = tx, tz
                end
                s.x, s.z, s.vx, s.vz = ox + lx, oz + lz + 0.003, 0, 0.0
                s.x0 = s.x
                -- keep the water out of it: probes under the sea surface are judged by the hazard alone
                local before = s.z
                R.step(s, false)
                tried = tried + 1
                if s.mode == "dead" and (s.cause == "hit" and s.what == k.item.kind or s.cause == "sink") then
                    if s.cause == "hit" then broke = broke + 1 end
                end
            end
            check(broke >= tried - 1 and broke > 0, string.format("%s: a float on its mesh breaks (%d of %d probes)", k.grid, broke, tried))
        end
        local s = state_on(staged({ { kind = "boat", x = 300, p = { y = RL.BOAT_IN_Y, yaw = 0, roll = 0, inplane = true } } }))
        s.hook, s.mode, s.x, s.z, s.vx, s.vz, s.t = nil, "fly", 312, 3.0, 0, 0, 2.0
        R.step(s, false)
        check(s.mode == "fly", "a float clear of every piece flies on")
    end

    -- 5. same seed, same input (the bot), at 30, 60 and 144 fps: the same run step for step
    do
        local runs = {}
        for _, fps in ipairs({ 30, 60, 144 }) do
            local s = R.new(11, {})
            local b = B.new()
            local trace = {}
            local input = function(st) return B.input(b, st) end
            local frames = 0
            while s.steps < 120 * 25 and s.mode ~= "dead" do
                R.advance(s, 1 / fps, input)
                frames = frames + 1
                trace[#trace + 1] = s.steps
            end
            runs[#runs + 1] = { fps = fps, s = s, frames = frames }
        end
        -- compare by replaying traces: record x, z per step via a fresh run at each rate
        local function steptrace(fps)
            local s = R.new(11, {})
            local b = B.new()
            local tr = {}
            local input = function(st)
                local h = B.input(b, st)
                tr[#tr + 1] = string.format("%.12f %.12f %s", st.x, st.z, tostring(h))
                return h
            end
            while s.steps < 120 * 25 and s.mode ~= "dead" do R.advance(s, 1 / fps, input) end
            return tr, s
        end
        local t30, s30 = steptrace(30)
        local t60, s60 = steptrace(60)
        local t144, s144 = steptrace(144)
        local n = math.min(#t30, #t60, #t144)
        local same = n > 2000
        for i = 1, n do if t30[i] ~= t60[i] or t30[i] ~= t144[i] then same = false; print("     differs at step " .. i); break end end
        check(same and s30.score == s60.score and s60.score == s144.score,
            string.format("30 / 60 / 144 fps: %d steps identical, scores %s %s %s, distance %.1f", n, s30.score, s60.score, s144.score, s30.dist))
    end

    -- 6. doing nothing (never holding) ends the run
    do
        local s = R.new(3, {})
        local n = 0
        while s.mode ~= "dead" and n < 120 * 30 do R.step(s, false); n = n + 1 end
        check(s.mode == "dead", string.format("never holding ends the run (%s after %.2f s)", tostring(s.cause), n / 120))
    end

    -- 9. the chain only pulls: a 4.1-chain swing whose bottom meets a crest (a red buoy at 317.357, t 0, as course 77
    -- level 0 had it: the old rigid chain sank it at step 121) rides over, its bottom never more than RIDE_DEPTH under;
    -- a slow float on a taut chain in the water still sinks
    do
        local h0 = { kind = "buoy_red", x = 317.35684809687365 }
        local s = state_on(staged({ h0 }))
        s.t = 0
        local hx, _, hz = Course.hook(h0, 0)
        s.hook, s.hx, s.hz, s.hvx, s.hvz, s.last_x = h0, hx, hz, 0, 0, h0.x
        s.L, s.Lt, s.th, s.om, s.slack = 4.1, 4.1, math.rad(-RL.PUMP_THETA), 0, false
        s.x, s.z = hx + 4.1 * math.sin(s.th), hz - 4.1 * math.cos(s.th)
        local deepest, rides, n = 0, 0, 0
        while s.mode ~= "dead" and n < 120 * 3 do
            local was = s.slack
            R.step(s, true); n = n + 1
            local d = Sea.height(s.x, 0, s.t) - (s.z - D.FLOAT_R)
            if d > deepest then deepest = d end
            if s.slack and not was and s.skimming then rides = rides + 1 end
        end
        check(s.mode ~= "dead" and rides > 0 and deepest <= RL.RIDE_DEPTH + 0.05,
            string.format("a crest under a 4.1 chain lifts the float (%s after %.1f s, %d rides, deepest %.2f <= %.2f)",
                s.mode, n / 120, rides, deepest, RL.RIDE_DEPTH))
        local pier = { kind = "pier", x = 1000 }
        local s2 = state_on(staged({ pier }))
        local px, _, pz = Course.hook(pier, 0)
        local zf = Sea.height(px, 0, 0) - 0.1
        s2.hook, s2.hx, s2.hz, s2.hvx, s2.hvz = pier, px, pz, 0, 0
        s2.L, s2.Lt, s2.th, s2.om, s2.slack = pz - zf, pz - zf, 0, 0.5, false
        s2.x, s2.z = px, zf
        R.step(s2, true)
        local d2 = Sea.height(s2.x, 0, s2.t) - (s2.z - D.FLOAT_R)
        check(s2.mode ~= "dead" and d2 <= RL.RIDE_DEPTH + 0.05, string.format("a slow float (%.1f u/s) on a chain in the water floats (%s, depth %.2f)",
            0.5 * s2.L, s2.mode, d2))
        local s3 = state_on(staged({ { kind = "pier", x = 1000 } }))
        s3.x, s3.z, s3.vx, s3.vz = 1000, Sea.height(1000, 0, 0) + D.FLOAT_R + 0.01, 3, -1
        R.step(s3, false)
        check(s3.mode == "dead" and s3.cause == "sink", "a slow free float in the water still sinks (" .. tostring(s3.cause) .. ")")
    end

    -- 10. holding is safe: hangs on a 4.1 chain from a buoy (75 deg, and small 15 / 30 deg swings, as a snap onto a
    -- hook leaves them), held for 60 s at 10 sea times each, skim at the bottom of every swing but never sink, and the
    -- swing comes back above 60 deg (SKIM_DRAG 0.9 sank 11 of 20 75-deg holds; the rigid, slow-on-chain and
    -- slack-steep sinks 32 of 60 small ones: scratch/diag/hang2.lua)
    do
        local sunk, first, low = 0, nil, 0
        for k = 0, 29 do
            local a0 = ({ 75, 30, 15 })[k % 3 + 1]
            local h = { kind = k % 2 == 0 and "buoy_red" or "buoy_white", x = 100 + 7.3 * k }
            local s = state_on(staged({ h }))
            s.t = k * 1.7
            local hx, _, hz = Course.hook(h, s.t)
            s.hook, s.hx, s.hz, s.hvx, s.hvz, s.last_x = h, hx, hz, 0, 0, h.x
            s.L, s.Lt, s.th, s.om, s.slack = 4.1, 4.1, math.rad(-a0), 0, false
            s.x, s.z = hx + 4.1 * math.sin(s.th), hz - 4.1 * math.cos(s.th)
            local i, amax = 0, 0
            while s.mode ~= "dead" and i < 120 * 60 do
                R.step(s, true); i = i + 1
                if i > 120 * 40 and not s.slack then amax = math.max(amax, math.abs(math.deg(s.th))) end
            end
            if s.mode == "dead" then
                sunk = sunk + 1
                first = first or string.format("%d deg t0 %.1f: %s after %.0f s", a0, k * 1.7, tostring(s.what), i / 120)
            elseif amax < 60 then low = low + 1 end
        end
        check(sunk == 0 and low == 0, string.format("60 s holds on a 4.1 chain (75/30/15 deg): %d of 30 sink, %d stay under 60 deg%s",
            sunk, low, first and ("; first " .. first) or ""))
    end

    -- 11. the bot plans the run-up to a boat: level 4 seed 11 reaches its first boat (x 64.5) fast on the run-up buoy
    -- with no release left over the hull; planning one hook ahead it hung there for ever (stopped at 63)
    do
        local s = R.new(4011, { level = 4 })
        local b = B.new()
        while s.mode ~= "dead" and s.dist < 160 and s.steps < 120 * 90 do R.step(s, B.input(b, s)) end
        check(s.mode ~= "dead" and s.dist >= 160, string.format("level 4 seed 11 gets past its first boat: %s at %.0f units after %.0f s",
            s.mode, s.dist, s.steps / 120))
    end

    -- 12. a float that loops its hook can go on: level 0 seed 18 hooks a buoy 2.6 away flying up at 14.6 u/s and loops
    -- it backwards (om < 0 for ever); the angle grew without bound (-6424 deg) and the bot waited for om > 0 at 101
    do
        local s = R.new(18, { level = 0 })
        local b = B.new()
        local thmax = 0
        while s.mode ~= "dead" and s.dist < 200 and s.steps < 120 * 90 do
            R.step(s, B.input(b, s))
            if s.hook and math.abs(s.th) > thmax then thmax = math.abs(s.th) end
        end
        check(s.mode ~= "dead" and s.dist >= 200 and thmax <= math.pi + 1e-9,
            string.format("level 0 seed 18 gets past its loop: %s at %.0f units, |angle| <= %.0f deg", s.mode, s.dist, math.deg(thmax)))
    end

    -- 13. the bot judges an arrival on a taut chain and alive 3 s on: level 0 seed 9 hooked a buoy slack from above
    -- (stale angle counted as "through the bottom") and fell onto its lamp arm at 681
    do
        local s = R.new(9, { level = 0 })
        local b = B.new()
        while s.mode ~= "dead" and s.dist < 720 and s.steps < 120 * 240 do R.step(s, B.input(b, s)) end
        check(s.mode ~= "dead" and s.dist >= 720, string.format("level 0 seed 9 gets past 720 units: %s at %.0f (%s)", s.mode, s.dist,
            tostring(s.what)))
    end

    -- 14. the guided first run's gentle stretch (opts.gentle: close buoys, no hazards) is passable: the bot crosses it
    -- and 120 units beyond on 10 seeds (a 5.8-6.6 spacing put fast skims into the next buoy's fender: view_smoke)
    do
        local ok, first = 0, nil
        for seed = 1, 10 do
            local s = R.new(500 + seed, { gentle = 80 })
            local b = B.new()
            while s.mode ~= "dead" and s.dist < 200 and s.steps < 120 * 120 do R.step(s, B.input(b, s)) end
            if s.mode ~= "dead" and s.dist >= 200 then ok = ok + 1 else first = first or string.format("seed %d %s %s at %.0f", seed, tostring(s.cause), tostring(s.what), s.dist) end
        end
        check(ok == 10, string.format("the guided run's gentle course is passable: %d of 10 seeds reach 200%s", ok, first and ("; " .. first) or ""))
    end

    -- 8. boats are crossable from the worst arrival: hanging pumped (75 deg, no other energy) on the hook two before
    -- each generated in-plane boat, at chains 2.6 / 3.0 / 4.1, the bot gets past the hook after the boat. (Hook to hook
    -- over a hull is 12.7-14.3, which no dead hang flies; the course's BOAT_RUNUP buoy is what makes this pass.)
    do
        local tried, ok, worst = 0, 0, nil
        local c = Course.new_play(77, { level = 0 })
        c:extend(900)
        local hooks = {}
        for _, it in ipairs(c.plane) do if Course.has_hook(it) then hooks[#hooks + 1] = it end end
        local boats = 0
        for _, bt in ipairs(c.plane) do
            if bt.kind == "boat" and bt.p.inplane and boats < 4 then
                boats = boats + 1
                local k = 1
                while hooks[k + 1] and hooks[k + 1].x < bt.x do k = k + 1 end   -- hooks[k]: last hook before the boat
                local h0, after = hooks[k - 1], hooks[k + 1]
                for _, L0 in ipairs({ 2.6, 3.0, 4.1 }) do
                    for t0 = 0, 10, 5 do
                        local s = R.new(77, { level = 0 })
                        s.course, s.t = c, t0
                        local hx, _, hz = Course.hook(h0, t0)
                        s.hook, s.hx, s.hz, s.hvx, s.hvz, s.last_x = h0, hx, hz, 0, 0, h0.x
                        s.L, s.Lt, s.th, s.om, s.slack = L0, L0, math.rad(-RL.PUMP_THETA), 0, false
                        s.x, s.z = hx + L0 * math.sin(s.th), hz - L0 * math.cos(s.th)
                        s.x0 = s.x
                        local b = B.new()
                        while s.mode ~= "dead" and s.x < after.x + 2 and s.steps < 120 * 40 do R.step(s, B.input(b, s)) end
                        tried = tried + 1
                        if s.mode ~= "dead" and s.x >= after.x + 2 then ok = ok + 1
                        elseif not worst then
                            worst = string.format("boat at %.1f, hook %.1f -> %.1f, L %.1f t %.0f: %s %s", bt.x, h0.x, hooks[k].x,
                                L0, t0, s.mode, tostring(s.cause))
                        end
                    end
                end
            end
        end
        check(boats == 4 and ok == tried, string.format("boats crossable from a dead hang two hooks before: %d of %d (%d boats)%s",
            ok, tried, boats, worst and ("; first fail " .. worst) or ""))
    end
end

-- 7. passability: the bot survives 2,000 units at one difficulty step for N seeds
local function passability(level, nseeds, units)
    local worst, t0 = nil, os.clock()
    local ok = 0
    for seed = 1, nseeds do
        local s = R.new(1000 * level + seed, { level = level })
        local b = B.new()
        while s.mode ~= "dead" and s.dist < units and s.steps < 120 * 600 do R.step(s, B.input(b, s)) end
        local passed = s.mode ~= "dead" and s.dist >= units
        if passed then ok = ok + 1 end
        if not passed then
            print(string.format("     level %d seed %d stopped at %.0f: %s %s (%s)", level, seed, s.dist, tostring(s.mode),
                tostring(s.cause), tostring(s.what)))
        end
        if not worst or s.dist < worst then worst = s.dist end
    end
    check(ok == nseeds, string.format("level %d: the bot survives %d units on %d of %d seeds (shortest %.0f; %.0f s)",
        level, units, ok, nseeds, worst, os.clock() - t0))
end
if mode == "pass" then
    passability(tonumber(arg[2]) or 0, tonumber(arg[3]) or 20, tonumber(arg[4]) or 2000)
elseif mode == "all" then
    for lv = 0, RL.LEVELS - 1 do passability(lv, 20, 2000) end
end

if fails > 0 then print(fails .. " FAILED"); os.exit(1) end
print("rules_test (" .. mode .. "): all passed")
