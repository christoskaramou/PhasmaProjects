-- luajit tests/rules_test.lua  (run from the EchoChamber folder)
-- Generates chambers 1..60 and checks: every chamber is solvable with exactly its inventory, the bare
-- horn does not solve it, the same number always gives the same chamber, and the send rules (order,
-- fading, resonator, damper, fork, walls) behave.
local f = assert(io.open("Assets/Scripts/echo_rules.lua", "rb"))
local R = assert(loadstring(f:read("*a"), "@echo_rules.lua"))()
f:close()

local fails = 0
local function check(cond, msg)
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
end

-- 1. Generation: solvable, not trivial, inventory matches the solution.
local t0 = os.clock()
local kinds = {}
for L = 1, 60 do
    local g = R.new(L)
    check(#g.bells >= 2, "chamber " .. L .. " has bells")
    for _, s in ipairs(g.solution) do
        check(g:place(s.kind, s.x, s.y, s.flip), "chamber " .. L .. ": solution piece places (" .. s.kind .. ")")
        kinds[s.kind] = (kinds[s.kind] or 0) + 1
    end
    for _, k in ipairs(R.PIECES) do check(g:left(k) == 0, "chamber " .. L .. ": inventory used up exactly (" .. k .. ")") end
    local res = g:send()
    check(res.ok, "chamber " .. L .. " solution rings every bell (" .. tostring(res.fail and res.fail.why) .. ")")
    check(g.state == "won" and g.stars == 3, "chamber " .. L .. " first-send win gives 3 stars")
    check(not g:simulate({}).ok, "chamber " .. L .. " is not solved by the bare horn")
    if L <= 12 or L % 10 == 0 then
        print(string.format("chamber %2d  %2dx%d  bells %d  pieces %d  strength %2d  ticks %3d", L, g.w, g.h, #g.bells,
            g:total_pieces(), g.strength, res.ticks))
    end
end
print(string.format("generated 60 chambers in %.2f s; pieces used: reflector %d, fork %d, resonator %d, damper %d",
    os.clock() - t0, kinds.reflector or 0, kinds.fork or 0, kinds.resonator or 0, kinds.damper or 0))
check((kinds.fork or 0) > 0 and (kinds.resonator or 0) > 0 and (kinds.damper or 0) > 0, "every piece kind appears in some chamber")

-- 2. Determinism.
local a, b = R.new(17), R.new(17)
check(a.w == b.w and a.strength == b.strength and #a.bells == #b.bells and a.emitter.x == b.emitter.x
    and a.bells[#a.bells].x == b.bells[#b.bells].x, "same chamber number gives the same chamber")

-- 3. Hand-built rules checks on a fixed board.
local function board(w, h)
    local g = R.new(1)
    g.w, g.h = w, h
    g.walls, g.bell_at, g.bells, g.pieces = {}, {}, {}, {}
    g.emitter = { x = 1, y = 3, dx = 1, dy = 0 }
    g.strength = 30
    g.inventory = { reflector = 5, fork = 2, resonator = 1, damper = 1 }
    g.state, g.sends, g.hints = "plan", 0, 0
    return g
end
local function bell(g, x, y, n) g.bells[n] = { x = x, y = y, n = n }; g.bell_at[g:idx(x, y)] = n end

-- Order: bell 2 sits before bell 1 on a straight line -> fails on bell 2.
local g = board(8, 5)
bell(g, 3, 3, 2); bell(g, 6, 3, 1)
local r = g:simulate()
check(not r.ok and r.fail.why == "order" and r.fail.bell == 2 and r.fail.expected == 1, "wrong order fails on the early bell")
-- Reflector routes around: "/" at (2,3) sends it up... use a detour: 1 first via a turn.
g = board(8, 5)
bell(g, 4, 3, 1); bell(g, 4, 1, 2)
g:place("reflector", 6, 3, "/")           -- right -> up
g:place("reflector", 6, 1, "/")           -- up -> right? "/" maps (0,-1) -> (1,0)
check(not g:simulate().ok, "pulse leaving to the right misses bell 2")
g:rotate(6, 1)                             -- "\" maps (0,-1) -> (-1,0): back left over bell 2
check(g:simulate().ok, "flipping a reflector routes the pulse over bell 2")
-- Fading: strength too low.
g.strength = 7
r = g:simulate()
check(not r.ok and r.fail.why == "faded", "short strength fades before the last bell")
-- Resonator recharges once.
g:place("resonator", 5, 3)
check(g:simulate().ok, "resonator recharges the pulse")
-- Damper stops it.
g:remove(5, 3)
g.strength = 30
g:place("damper", 5, 3)
r = g:simulate()
check(not r.ok and r.fail.why == "lost" and #r.rings == 1, "damper stops the pulse after bell 1")
-- Fork: two branches ring bells on both sides on the same tick, lowest first.
g = board(9, 7)
g.emitter = { x = 1, y = 4, dx = 1, dy = 0 }
g:place("fork", 4, 4)
bell(g, 4, 2, 1); bell(g, 4, 6, 2)
r = g:simulate()
check(r.ok and r.rings[1].t == r.rings[2].t, "fork rings both branches on one tick, in number order")
-- Walls absorb.
g = board(8, 5)
bell(g, 6, 3, 1)
g.walls[g:idx(4, 3)] = true
r = g:simulate()
check(not r.ok and r.fail.why == "lost", "wall absorbs the pulse")
check(not g:place("reflector", 4, 3), "cannot place on a wall")
check(not g:place("reflector", 6, 3), "cannot place on a bell")
check(not g:place("reflector", 1, 3), "cannot place on the horn")
-- Inventory limits.
g = board(8, 5)
g.inventory = { reflector = 1 }
check(g:place("reflector", 3, 2), "first reflector places")
check(not g:place("reflector", 3, 4), "second reflector refused when none left")
check(not g:place("fork", 3, 4), "pieces not in the chamber are refused")
-- Stars and hints.
g = R.new(9)
local h = g:hint()
check(h and h.kind, "hint reveals a solution piece")
for _, s in ipairs(g.solution) do g:place(s.kind, s.x, s.y, s.flip) end
g:send()
check(g.state == "won" and g.stars == 2, "a hint costs a star")

if fails > 0 then print(fails .. " checks failed"); os.exit(1) end
print("PASS rules")
