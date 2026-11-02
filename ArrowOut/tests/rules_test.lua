-- luajit tests/rules_test.lua  (run from the ArrowOut folder)
local R = dofile("Assets/Scripts/arrow_rules.lua")
local count = 0
local function check(name, f) f(); count = count + 1; print("PASS " .. name) end

check("every level 1..40 is solvable, dense and well formed", function()
    for n = 1, 40 do
        local g = R.new_game(n)
        local cells, filled = 0, 0
        for k = 1, g.w * g.h do if g.mask[k] then cells = cells + 1 end end
        for _, a in ipairs(g.arrows) do
            assert(#a.cells >= 2, "short arrow")
            filled = filled + #a.cells
            for i = 2, #a.cells do -- consecutive cells are orthogonal neighbours
                local p, q = a.cells[i - 1], a.cells[i]
                assert(math.abs(p[1] - q[1]) + math.abs(p[2] - q[2]) == 1, "broken body")
            end
        end
        local density = filled / cells
        assert(density >= 0.75, ("level %d density %.2f"):format(n, density))
        -- Greedy removal must clear the board (removal never blocks anything new).
        local guard = 0
        while not g:won() do
            local id = g:hint()
            assert(id, ("level %d stuck with %d left"):format(n, g.left))
            assert(g:tap_arrow(id).ok)
            guard = guard + 1; assert(guard < 10000)
        end
        assert(g.lives == R.LIVES and g.mistakes == 0)
        if n % 8 == 1 then print(("  level %2d %2dx%2d %-9s arrows %3d density %.2f"):format(n, g.w, g.h, g.spec.shape.name, #g.arrows, density)) end
    end
end)

check("generation is deterministic per level", function()
    local a, b = R.new_game(7), R.new_game(7)
    assert(#a.arrows == #b.arrows)
    for i, x in ipairs(a.arrows) do
        assert(x.dir == b.arrows[i].dir and #x.cells == #b.arrows[i].cells)
        assert(x.cells[1][1] == b.arrows[i].cells[1][1] and x.cells[1][2] == b.arrows[i].cells[1][2])
    end
end)

check("a blocked tap costs a heart, reports the blocker and keeps the arrow", function()
    local g = R.new_game(12)
    local blocked
    for id, a in ipairs(g.arrows) do if g:blocked(id) then blocked = id; break end end
    assert(blocked, "level 12 should start with a blocked arrow")
    local hd = g:head(blocked)
    local r = g:tap(hd[1], hd[2])
    assert(r and not r.ok and r.id == blocked and r.blocker ~= blocked and r.blocker > 0)
    assert(g.lives == R.LIVES - 1 and g.arrows[blocked].alive and g.left == #g.arrows)
end)

check("tapping the same arrow into the same blocker again costs no extra heart", function()
    local g = R.new_game(12)
    local blocked
    for id in ipairs(g.arrows) do if g:blocked(id) then blocked = id; break end end
    local first = g:tap_arrow(blocked)
    local again = g:tap_arrow(blocked)
    assert(not first.free and again.free and again.blocker == first.blocker)
    assert(g.lives == R.LIVES - 1 and g.mistakes == 1)
end)

check("losing every heart ends the level and ignores further taps", function()
    local g = R.new_game(12)
    local hit = 0
    for id in ipairs(g.arrows) do
        if hit < R.LIVES and g:blocked(id) then g:tap_arrow(id); hit = hit + 1 end
    end
    assert(hit == R.LIVES, "level 12 needs enough blocked arrows")
    assert(g:lost() and g:over())
    assert(g:tap_arrow(g:free_arrows()[1]) == nil)
end)

check("tapping an empty cell does nothing", function()
    local g = R.new_game(3)
    for y = 1, g.h do for x = 1, g.w do
        if g:at(x, y) == 0 then assert(g:tap(x, y) == nil and g.moves == 0); return end
    end end
end)

print(count .. " checks passed")
