------------------------------------------------------------------ 03b_levels: deterministic level generator
local D = G.D
function D.gen_level(n)
    local L = D.LEVELS[n]
    local f = L.feat
    local seed = n * 7919 + 13
    local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
    local function ri(a, b) return a + math.floor(rnd() * (b - a + 1)) end
    local function pick(t) return t[ri(1, #t)] end
    local ev = {}
    local function E(d, t, p) p = p or {}; p.d = d; p.ev = t; ev[#ev + 1] = p; return p end
    local len, hk = L.len, L.hpk
    local lv = 1 + 0.16 * (n - 1)
    local endd = len - (L.boss and 30 or 20)

    local function wave(d, p, big)
        local count = math.floor(L.nk * (7 + 30 * p) * (big and 1.45 or 1) + 0.5)
        local nb = (f.brute and p > 0.2) and math.floor(count / (big and 11 or 16)) or 0
        local ns = (f.shield and p > 0.15) and math.floor(count / 7) or 0
        local nf = (f.flyer and p > 0.1) and math.floor(count / 8) or 0
        local nr = math.max(3, count - nb * 7 - ns * 2 - nf * 2)
        local clumps = big and 3 or (count > 18 and 2 or 1)
        local cx = {}
        for c = 1, clumps do cx[c] = (clumps == 1) and (rnd() * 7 - 3.5) or (-3.6 + 7.2 * (c - 1) / (clumps - 1) + rnd() * 1.2 - 0.6) end
        local function g() return (rnd() + rnd() + rnd() - 1.5) end
        local hm = 1 + 3.0 * p
        -- formation shapes so threats arrive at different x positions (straight fire: you have to steer onto them)
        local shape = (n == 1 and p < 0.2) and "clump" or pick({ "clump", "clump", "flank", "column", "sweep" })
        local side = rnd() < 0.5 and -1 or 1
        for i = 1, nr do
            local c = cx[1 + (i % clumps)]
            local dd, x, lane = d + rnd() * (6 + count * 0.12), c + g() * 1.5, nil
            if shape == "flank" then x = side * ((i % 2 == 0) and 1 or -1) * (2.6 + rnd() * 1.8)
            elseif shape == "column" then x = side * (1.2 + (i % 3) * 1.2) + g() * 0.3; dd = d + i * math.min(0.9, 26 / nr); lane = (i % 3 ~= 0) or nil
            elseif shape == "sweep" then local k = (i - 1) / math.max(1, nr - 1); x = side * (-4 + 8 * k) + g() * 0.4; dd = d + k * (8 + count * 0.15) + rnd() end
            E(dd, "foe", { t = "runner", hm = hm, x = x, lane = lane })
        end
        for i = 1, nb do E(d + 4 + rnd() * 6, "foe", { t = "brute", hm = hm, x = cx[1 + (i % clumps)] + g(), lane = (i % 2 == 0) or nil }) end
        for i = 1, ns do E(d - 1 + rnd() * 3, "foe", { t = "shield", hm = hm, x = -4 + 8 * ((i - 0.5) / ns) + g() * 0.4 }) end
        for i = 1, nf do E(d + 8 + rnd() * 10, "foe", { t = "flyer", hm = hm, x = (rnd() * 2 - 1) * 4 }) end
        if f.barrel and rnd() < 0.55 then E(d - 3, "prop", { t = "barrel", x = cx[1] }) end
        if f.cryo and rnd() < 0.45 then E(d - 3, "prop", { t = "cryo", x = cx[#cx] }) end
        return d + 26 + count * 0.25
    end

    local wlist = { "shotgun", "minigun" }
    if n >= 2 then wlist[#wlist + 1] = "rocket" end
    if n >= 4 then wlist[#wlist + 1] = "laser" end
    local ally_i = 0
    local function gates(d, p, first)
        local a = math.max(2, math.floor((3 + 11 * p) * (0.8 + 0.4 * rnd()) * lv + 0.5))
        local per = 3.2 * hk ^ 0.85 * (1 + 0.8 * p)
        local opts = { "addsub", "addmul", "addmul" }
        if f.trap then opts[#opts + 1] = "trap"; opts[#opts + 1] = "trap" end
        if f.lock then opts[#opts + 1] = "lock" end
        if f.rate or f.dmg then opts[#opts + 1] = "ratedmg" end
        if f.merge and p > 0.3 then opts[#opts + 1] = "merge" end
        if p > 0.15 then opts[#opts + 1] = "single" end
        local o = first and "first" or pick(opts)
        local s = rnd() < 0.5 and -1 or 1
        local function GT(x, k, t) t = t or {}; t.x = x; t.k = k; t.per = t.per or per; return t end
        local row
        if o == "first" then row = { GT(-2.5, "add", { v = 4 }), GT(2.5, "mul", { mi = 3, per = 9 * hk }) }
        elseif o == "addsub" then row = { GT(2.5 * s, "add", { v = a }), GT(-2.5 * s, "add", { v = -math.floor(a * 1.3 + 2) }) }
        elseif o == "addmul" then row = { GT(2.5 * s, "add", { v = math.floor(a * 1.4) }), GT(-2.5 * s, "mul", { mi = (p > 0.5 and 2 or 3), per = 26 * hk ^ 0.85 * (1 + p) }) }
        elseif o == "trap" then row = { GT(2.5 * s, "trap", { v = math.floor(a * 0.6) + 1, maxv = math.floor(a * 1.8) + 3, per = per * 0.8 }), GT(-2.5 * s, "add", { v = math.floor(a * 0.5) + 1 }) }
        elseif o == "lock" then row = { GT(2.5 * s, "lock", { hp = 130 * hk * (1 + 1.4 * p), mi = 5 }), GT(-2.5 * s, "add", { v = math.floor(a * 0.8) }) }
        elseif o == "ratedmg" then row = { GT(2.5 * s, f.rate and "rate" or "dmg", { v = -10, per = per * 2.2 }), GT(-2.5 * s, f.dmg and "dmg" or "rate", { v = 5, per = per * 2.2 }) }
        elseif o == "merge" then row = { GT(2.5 * s, "merge", {}), GT(-2.5 * s, "add", { v = math.floor(a * 1.2) }) }
        else row = { GT(2.5 * s + (rnd() - 0.5), "add", { v = math.floor(a * 1.6) + 2 }) } end
        E(d, "gates", { row = row })
        return d + 30
    end
    local function crate(d, p)
        E(d, "prop", { t = "crate", x = rnd() * 6 - 3, w = pick(wlist), hp = 22 * hk * (1 + 1.2 * p) })
        return d + 18
    end
    local function container(d, p)
        ally_i = ally_i + 1
        local a = (ally_i == 1) and L.ally or D.AORDER[ri(1, #D.AORDER)]
        E(d, "prop", { t = "container", x = rnd() * 4 - 2, ally = a, hp = 80 * hk * (1 + 1.3 * p) })
        return d + 22
    end
    local function barricade(d, p)
        local s = rnd() < 0.5 and -1 or 1
        E(d, "prop", { t = "barricade", x = 2.6 * s, hp = 55 * hk * (1 + 1.5 * p) })
        if rnd() < 0.5 then E(d + 2, "prop", { t = "barrel", x = -2.6 * s }) end
        return d + 16
    end
    local pat = { "gates", "wave", "crate", "gates", "wave", "container", "gates", "wave", "air", "gates", "barricade", "wave", "gates", "big", "drop", "gates", "wave", "container", "gates", "big" }
    local d, i = 32, 0
    E(30, "hint", { txt = (n == 1) and "Your Squad Fires On Its Own" or L.name })
    gates(36, 0, true); d = 70
    while d < endd do
        i = i + 1
        local b = pat[(i - 1) % #pat + 1]
        local p = d / len
        if b == "gates" then d = gates(d, p)
        elseif b == "wave" then d = wave(d, p)
        elseif b == "big" then d = wave(d, p, true)
        elseif b == "crate" then d = f.crate and crate(d, p) or d
        elseif b == "container" then d = container(d, p)
        elseif b == "barricade" then d = f.barricade and barricade(d, p) or (f.barrel and wave(d, p) or d)
        elseif b == "air" then E(d, "air", { kind = "gunship" }); d = d + 4
        elseif b == "drop" then E(d, "air", { kind = "drop", w = pick(wlist) }); d = d + 4 end
    end
    if n == 1 then
        E(60, "hint", { txt = "Shoot Gates To Raise Their Value" })
        E(150, "hint", { txt = "Break Crates For Better Guns" })
        E(240, "hint", { txt = "Bust Containers Open To Free Allies" })
    end
    if L.boss then
        wave(len - 60, 0.95)
        E(len, "boss", { b = L.boss, b2 = L.boss2 })
    else
        E(len, "finish")
    end
    table.sort(ev, function(a, b) return a.d < b.d end)
    return ev
end
