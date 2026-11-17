-- Scripted inputs: the game's own input path for tests, live runs and the level solver. A script maps sim time t to the
-- lantern and the props the player moves, exactly as if the player held them there.
--   for_level(L, "nothing")   the level as it starts (the do-nothing run: it must lose)
--   for_level(L, "solution")  the level's keyframed solution (puppet_solutions.lua: tools/solve_levels.lua + hand)
--   for_level(L, "win")       the reference level's drag into state A's bridge (target.png's play)
-- Keyframes: { t, dur, lantern = { x, y }, <prop> = x (the balloon: its height) }: from t the stage is dragged linearly
-- over dur from where the previous keyframe left it; before the first it is the level's start.
return function(D, read)
    local M = {}
    local function lerp(a, b, u) return a + (b - a) * u end

    function M.start_input(L)
        local s = L.start
        local inp = { lantern = { s.lantern[1], s.lantern[2] } }
        for name, p in pairs(L.props) do
            if p.move == "x" then inp[name] = s[name] elseif p.move == "z" then inp[name] = s[name] or 0 end
        end
        return inp
    end

    function M.keyframes(L, keys)
        local s0 = M.start_input(L)
        local states = { s0 }
        for i, k in ipairs(keys) do
            local p = states[i]
            local st = { lantern = { k.lantern and k.lantern[1] or p.lantern[1], k.lantern and k.lantern[2] or p.lantern[2] } }
            for name in pairs(L.props) do st[name] = k[name] ~= nil and k[name] or p[name] end
            states[i + 1] = st
        end
        return function(t)
            local cur = states[1]
            for i, k in ipairs(keys) do
                local a, b = states[i], states[i + 1]
                if t < k.t then break end
                local u = math.min(1, (t - k.t) / math.max(1e-6, k.dur or 0.8))
                local st = { lantern = { lerp(a.lantern[1], b.lantern[1], u), lerp(a.lantern[2], b.lantern[2], u) } }
                for name in pairs(L.props) do
                    if a[name] ~= nil and b[name] ~= nil then st[name] = lerp(a[name], b[name], u) else st[name] = b[name] end
                end
                cur = st
            end
            return cur
        end
    end

    -- the generated solutions (absent: none)
    M.solutions = {}
    local src = read and read("Scripts/puppet_solutions.lua")
    if src then
        local f = load(src, "@puppet_solutions.lua", "t", {})
        if f then M.solutions = f() or {} end
    end

    -- the reference level's drag into state A's bridge between 1 s and 4 s (kept for the look frames' play)
    local A = D.SOLUTION or D.STATE_A
    local function ref_win(L)
        local st = L.start
        return function(t)
            local u = math.max(0, math.min(1, (t - 1) / 3))
            return { lantern = { lerp(st.lantern[1], A.lantern[1], u), lerp(st.lantern[2], A.lantern[2], u) },
                cup = lerp(st.cup, A.cup, u), comb = lerp(st.comb, A.comb, u), ladder = lerp(st.ladder, A.ladder, u) }
        end
    end

    function M.for_level(L, name)
        if name == "nothing" then
            local s = M.start_input(L)
            return function() return s end
        elseif name == "solution" then
            local keys = M.solutions[L.id]
            return keys and M.keyframes(L, keys) or nil
        elseif name == "win" and L.id == "1-3" then
            return ref_win(L)
        end
        return nil
    end
    M.names = { nothing = true, solution = true, win = true }
    return M
end
