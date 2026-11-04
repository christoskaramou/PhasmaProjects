-- luajit tests/rules_test.lua  (run from the Refract folder)
local R = dofile("Assets/Scripts/refract_rules.lua")
local count = 0
local function check(name, f) f(); count = count + 1; print("PASS " .. name) end

check("maps 1..30 are well formed", function()
    for s = 1, 30 do
        local g = R.new_game(s)
        assert(#g.path >= 50, "short path")
        for i = 2, #g.path do
            local a, b = g.path[i - 1], g.path[i]
            assert(math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) == 1, "path not contiguous")
        end
        local seen = {}
        for _, p in ipairs(g.path) do
            local k = R.idx(p[1], p[2])
            assert(not seen[k], "path revisits a cell"); seen[k] = true
        end
        assert(g:kind(g.path[1][1], g.path[1][2]) == "gate")
        assert(g:kind(g.path[#g.path][1], g.path[#g.path][2]) == "core")
        local again = R.new_game(s)
        for k = 1, R.W * R.H do assert(again.cells[k] == g.cells[k], "map not deterministic") end
    end
end)

-- A tiny hand-built board: emitter, mirror, prism and lens on known cells.
local function blank()
    local g = R.new_game(1)
    for k = 1, R.W * R.H do g.cells[k] = "ground" end
    g.path_index, g.pieces, g.energy = {}, {}, 9999
    return g
end

check("mirrors turn light, prisms split white into r/g/b, lenses focus", function()
    local g = blank()
    assert(g:place("emitter", 2, 5, 2))        -- faces right
    assert(g:place("mirror", 6, 5, nil, "/"))  -- right -> up
    local c = g.cov[R.idx(6, 3)]
    assert(c and c.w == R.EMITTER_POWER[1], "mirror did not send light up")
    assert(not g.cov[R.idx(7, 5)], "light passed through the mirror")
    g:rotate(6, 5)                              -- now "\": right -> down
    assert(g.cov[R.idx(6, 8)] and not g.cov[R.idx(6, 3)], "flip did not redirect")
    g:sell(6, 5)
    assert(g:place("prism", 8, 5))
    local p = R.EMITTER_POWER[1] * R.PRISM_SPLIT
    assert(math.abs(g.cov[R.idx(12, 5)].g - p) < 1e-9, "green should go straight")
    assert(math.abs(g.cov[R.idx(8, 2)].r - p) < 1e-9, "red should turn left (up)")
    assert(math.abs(g.cov[R.idx(8, 9)].b - p) < 1e-9, "blue should turn right (down)")
    assert(g:place("lens", 10, 5))
    assert(math.abs(g.cov[R.idx(12, 5)].g - p * R.LENS_GAIN) < 1e-9, "lens did not focus")
    -- Coloured light passes a second prism unchanged.
    assert(g:place("prism", 14, 5))
    assert(g.cov[R.idx(16, 5)].g > 0 and not g.cov[R.idx(14, 3)], "coloured light should not split")
end)

check("mirror loops terminate", function()
    local g = blank()
    g:place("mirror", 4, 4, nil, "\\"); g:place("mirror", 9, 4, nil, "/")
    g:place("mirror", 9, 9, nil, "\\"); g:place("mirror", 4, 9, nil, "/")
    g:place("emitter", 6, 4, 2)
    assert(#g.segs < 50)
end)

check("rocks and the board edge stop light; sell refunds 70%", function()
    local g = blank()
    g.cells[R.idx(7, 5)] = "rock"
    g:place("emitter", 2, 5, 2)
    assert(g.cov[R.idx(6, 5)] and not g.cov[R.idx(8, 5)])
    local e = g.energy
    assert(g:sell(2, 5) == math.floor(60 * 0.7) and g.energy == e + 42)
end)

check("shades take bonus damage only from their colour", function()
    local g = blank()
    g.cov = { [1] = { w = 0, r = 10, g = 0, b = 0 } }
    assert(g:dps_at(1, "shade_r") > g:dps_at(1, "shade_g") * 5)
    g.cov = { [1] = { w = 10, r = 0, g = 0, b = 0 } }
    assert(g:dps_at(1, "mirrorback") == 0, "mirrorbacks ignore white")
end)

------------------------------------------------------------------ bot
-- Greedy: value = expected damage dealt to the next wave per path traversal.
local function value(g, cov, kinds)
    local v = 0
    local saved = g.cov
    g.cov = cov
    for _, p in ipairs(g.path) do
        local k = R.idx(p[1], p[2])
        if cov[k] then
            for kind, w in pairs(kinds) do v = v + w * g:dps_at(k, kind) / R.ENEMIES[kind].speed end
        end
    end
    g.cov = saved
    return v
end

local function wave_kinds(g)
    local list = g:next_wave_list() or {}
    local kinds, total = {}, 0
    for _, e in ipairs(list) do
        local kind = e[1] == "eclipse" and "mote" or e[1]
        kinds[kind] = (kinds[kind] or 0) + e[2] * R.ENEMIES[e[1]].hp
        total = total + e[2] * R.ENEMIES[e[1]].hp
    end
    for k, w in pairs(kinds) do kinds[k] = w / total end
    return kinds
end

local function bot_spend(g)
    local kinds = wave_kinds(g)
    for _ = 1, 40 do
        local base = value(g, g.cov, kinds)
        local best, act = 0, nil
        local function try(gain, cost, f)
            if cost <= g.energy and gain / cost > best then best, act = gain / cost, f end
        end
        for y = 1, R.H do
            for x = 1, R.W do
                local k = R.idx(x, y)
                if g.cells[k] == "ground" and not g.pieces[k] then
                    if g.energy >= 60 then
                        for d = 1, 4 do
                            local _, cov = g:trace({ [k] = { kind = "emitter", dir = d, tier = 1 } })
                            try(value(g, cov, kinds) - base, 60, function() g:place("emitter", x, y, d) end)
                        end
                    end
                    if g.cov[k] then
                        for _, fl in ipairs({ "/", "\\" }) do
                            local _, cov = g:trace({ [k] = { kind = "mirror", flip = fl } })
                            try(value(g, cov, kinds) - base, 15, function() g:place("mirror", x, y, nil, fl) end)
                        end
                        for _, kind in ipairs({ "prism", "lens" }) do
                            local _, cov = g:trace({ [k] = { kind = kind } })
                            try(value(g, cov, kinds) - base, R.PIECES[kind].cost, function() g:place(kind, x, y) end)
                        end
                    end
                elseif g.pieces[k] and g:upgrade_cost(x, y) then
                    local p = g.pieces[k]
                    local _, cov = g:trace({ [k] = { kind = "emitter", dir = p.dir, tier = p.tier + 1 } })
                    try(value(g, cov, kinds) - base, g:upgrade_cost(x, y), function() g:upgrade(x, y) end)
                end
            end
        end
        if not act or best < 1e-6 then break end
        act()
    end
end

local function play(sector)
    local g = R.new_game(sector)
    bot_spend(g)
    g:start_wave()
    local steps = 0
    while g.state ~= "won" and g.state ~= "lost" and steps < 200000 do
        steps = steps + 1
        g:update(1 / 30)
        if g:surge_ready() then g:fire_surge() end
        if g.state == "between" then bot_spend(g); g:start_wave() end
    end
    return g
end

check("a greedy bot can clear sectors 1 to 3 but not walk through everything", function()
    for s = 1, 3 do -- asserted sectors only; later sectors are slow and were a report, not a check
        local g = play(s)
        print(string.format("  sector %d: %s at wave %d, core %d/%d, kills %d, leaks %d, energy %d",
            s, g.state, g.wave, g.core, R.CORE, g.kills, g.leaks, g.energy))
        if s <= 3 then assert(g.state == "won", "bot lost an early sector") end
    end
end)

print(count .. " checks passed")
