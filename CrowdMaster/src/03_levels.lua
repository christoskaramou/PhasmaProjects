------------------------------------------------------------------ levels: 12 hand-made runs in 4 worlds; every 3rd ends in a boss
-- events (lane x: -4.5 .. 4.5, + = right as seen from behind the crowd):
--  g(z, a, b, kind)  gate pair; a/b = "+10" "x2" "-5" "/2" "M" (merge); kind = nil | "trick" | "timed" ; b = nil -> one full-width gate
--  E(z, n, x)        red crowd        cage(z, x, n, hp)  breakable cage of grey captives
--  coins(z, x, n)    a line of coins  drop(z, x, n)  air drop (+n), ally(z, x) a golden giant joins
--  spin(z, x, w)     spinning bar     saw(z, x0, x1, w)  saw lane     ham(z, x, ph)  swinging hammer
--  crush(z, x, w, ph) crusher block   roll(z, x, w)  spike roller rolling at you
--  pit(z0, z1, x0, x1)  hole          bridge(z0, z1, x0, x1)  only this strip is floor
--  ter(z0, z1, kind, x0, x1)  oil | ice | mud | gravel | thorn
local W = 4.5
local function g(z, a, b, kind) return { t = "gate", z = z, a = a, b = b, kind = kind } end
local function E(z, n, x) return { t = "enemy", z = z, n = n, x = x or 0 } end
local function cage(z, x, n, hp) return { t = "cage", z = z, x = x, n = n, hp = hp or n * 2 } end
local function coins(z, x, n, wave) return { t = "coins", z = z, x = x, n = n or 6, wave = wave } end
local function drop(z, x, n) return { t = "drop", z = z, x = x, n = n } end
local function ally(z, x) return { t = "ally", z = z, x = x } end
local function spin(z, x, w) return { t = "spin", z = z, x = x or 0, w = w or 1.5 } end
local function saw(z, x0, x1, w) return { t = "saw", z = z, x0 = x0, x1 = x1, w = w or 1.3 } end
local function ham(z, x, ph) return { t = "ham", z = z, x = x or 0, ph = ph or 0 } end
local function crush(z, x, w, ph) return { t = "crush", z = z, x = x, w = w or 3, ph = ph or 0 } end
local function roll(z, x, w) return { t = "roll", z = z, x = x, w = w or 4.5 } end
local function pit(z0, z1, x0, x1) return { t = "pit", z = z0, z0 = z0, z1 = z1, x0 = x0 or -W, x1 = x1 or W } end
local function bridge(z0, z1, x0, x1) return { t = "bridge", z = z0, z0 = z0, z1 = z1, x0 = x0, x1 = x1 } end
local function ter(z0, z1, kind, x0, x1) return { t = "ter", z = z0, z0 = z0, z1 = z1, kind = kind, x0 = x0 or -W, x1 = x1 or W } end
local function tip(z, text) return { t = "tip", z = z, text = text } end

local LEVELS = {
    { name = "First Steps", world = 1, len = 200, stair = 4, ev = {
        tip(4, "Drag Or Use A / D To Steer"),
        g(22, "+10", "+5"), coins(34, -2, 6), coins(34, 2, 6),
        g(56, "x2", "+8"), E(84, 14, 0), coins(100, 0, 8, true),
        g(118, "+15", "-5"), g(142, "x2", "+20"), E(166, 22, 1.5), coins(182, -1.5, 8) } },
    { name = "Spin Cycle", world = 1, len = 240, stair = 5, ev = {
        g(20, "+10", "x2"), spin(46, 0, 1.3), coins(58, 0, 6),
        cage(76, -2.3, 8, 14), coins(72, 2.3, 7), tip(88, "Merge: Two Pawns Become A Brute"),
        g(98, "M", "+10"), E(122, 25, 0), spin(144, 0, 1.8), coins(156, -2, 6),
        g(168, "x3", "+25"), g(192, "-10", "/2"), E(214, 32, -1), coins(228, 0, 8, true) } },
    { name = "King Of The Meadow", world = 1, len = 260, boss = 160, ev = {
        g(20, "+15", "x2"), saw(42, -4, 4, 1.2), coins(52, 0, 6),
        g(64, "x2", "+12"), ter(78, 100, "gravel", -W, 0.6), saw(88, 1.2, 4, 1.6), coins(84, -2.5, 8),
        drop(112, 2, 15), E(132, 40, 0), g(152, "M", "x2"), saw(172, -4, 4, 1.6), saw(180, -4, 4, -1.4),
        cage(198, 2.2, 12, 20), g(220, "+40", "x3"), E(242, 38, 0) } },
    { name = "Hot Sands", world = 2, len = 250, stair = 8, ev = {
        g(20, "+20", "x2"), ter(40, 62, "mud", -W, 0), coins(44, -2.5, 8), coins(44, 2.5, 3),
        tip(66, "Hammers Swing - Time Your Run"), ham(74, 0, 0), pit(92, 100, -1.6, 1.6), coins(96, -3.2, 4), coins(96, 3.2, 4),
        g(114, "x2", "+15"), E(134, 48, 0), ham(152, -2, 0), ham(160, 2, 0.5),
        pit(176, 184, -W, -0.4), g(198, "x3", "M"), E(218, 55, 1), coins(234, 0, 8, true) } },
    { name = "Slick Dunes", world = 2, len = 250, stair = 9, ev = {
        g(20, "+20", "x2"), tip(32, "Oil! You Slide - Units Can Slip Off"), ter(40, 66, "oil"), coins(52, 0, 8, true),
        tip(70, "Striped Gates Are Tricksters"), g(80, "x3", "-5", "trick"), crush(98, -2.2, 4.2, 0), crush(98, 2.2, 4.2, 0.5),
        ally(116, 3), E(134, 66, 0), g(152, "+30", "/2"), ter(168, 192, "oil"), pit(178, 188, 1, W),
        g(204, "x2", "M"), E(224, 80, -1), coins(240, 0, 8) } },
    { name = "Canyon King", world = 2, len = 270, boss = 420, ev = {
        g(20, "+25", "x2"), tip(32, "Lamp Gates Toggle - Watch The Light"), g(44, "x2", "+10", "timed"),
        roll(70, -2, 5), ter(86, 104, "mud", 0, W), ham(96, -1.5, 0), drop(112, -2, 20), E(128, 70, 0),
        tip(136, "Lamp Gate Ahead - Wait For The Light"), g(148, "x3", "+15", "timed"), roll(168, 2.4, 4.2), roll(186, -2.4, 4.2),
        cage(202, -2.2, 20, 30), coins(202, 2.4, 6),
        g(222, "M", "+30"), E(244, 85, 0) } },
    { name = "Thin Ice", world = 3, len = 260, stair = 12, ev = {
        g(20, "x2", "+20"), tip(30, "Ice: Fast And Slippery"), ter(40, 82, "ice"), saw(58, -4, 4, 1.4), coins(70, 0, 8, true),
        tip(86, "Narrow Bridge - Squeeze Through"), bridge(94, 112, -1.7, 1.7), E(128, 75, 0), g(146, "x3", "+30"),
        ter(160, 186, "ice"), saw(166, -4, 0, 1.6), saw(176, 0, 4, -1.6), bridge(192, 206, 0.8, W), coins(199, 2.6, 5),
        g(220, "M", "x2"), E(240, 90, 0) } },
    { name = "Frostbite", world = 3, len = 250, stair = 14, ease = 0.86, ev = {
        g(20, "+25", "x2"), tip(32, "Brambles Bleed Units - Big Ones Shrug"), ter(42, 62, "thorn", -W, -1), coins(46, -3, 8),
        spin(68, -2.25, 1.6), g(76, "x3", "+20"), g(100, "x3", "+30"), crush(112, -2.2, 4.4, 0.2),
        E(126, 100, 0), ter(140, 158, "thorn", 0.5, W), cage(150, 2.6, 25, 34), ter(168, 190, "ice"), ham(180, 0, 0),
        g(204, "x2", "M"), E(224, 120, 0), coins(238, 0, 8, true) } },
    { name = "Frost King", world = 3, len = 280, boss = 900, ev = {
        g(20, "x2", "+25"), ter(36, 60, "ice"), saw(46, -4, 4, 1.8), g(70, "x3", "-15", "trick"),
        bridge(86, 100, -W, -0.8), coins(93, -2.6, 5), E(114, 90, 0), g(132, "M", "x2", "timed"),
        roll(150, 2, 5), ter(150, 170, "thorn", -W, -1.5), drop(176, 0, 30), crush(192, -2.2, 4.4, 0), crush(192, 2.2, 4.4, 0.5),
        ally(206, -3), g(224, "x3", "+40"), E(250, 130, 0) } },
    { name = "Ember Trail", world = 4, len = 260, stair = 18, ev = {
        g(20, "+30", "x2"), ter(34, 56, "gravel"), spin(46, 0, 1.6), g(68, "x2", "-20", "timed"),
        pit(84, 92, -1.8, 1.8), ham(98, 2.2, 0), E(118, 140, 0), ter(134, 154, "oil"), pit(142, 150, -W, -1.6),
        g(166, "x3", "/2", "trick"), cage(184, 2.2, 30, 40), saw(196, -4, 4, 1.8), g(212, "M", "+40"), E(234, 170, 0) } },
    { name = "The Gauntlet", world = 4, len = 290, stair = 22, ev = {
        g(20, "x2", "+30"), roll(40, 0, 6), ter(56, 80, "thorn", 1, W), coins(66, 3, 6), crush(70, -2.4, 4.2, 0),
        g(92, "x3", "+20", "trick"), bridge(108, 124, -1.6, 1.6), E(140, 160, 0), drop(156, 2, 40),
        ter(168, 196, "ice"), saw(176, -4, 4, 2.0), ham(188, -1.5, 0.5), g(206, "x2", "-30", "timed"),
        ter(220, 240, "mud"), spin(230, 0, 2.0), g(252, "M", "x2"), E(272, 220, 0) } },
    { name = "Ember Throne", world = 4, len = 300, boss = 2600, ev = {
        g(20, "x2", "+30"), ham(38, 0, 0), ter(50, 74, "oil"), pit(60, 68, 1.2, W), g(84, "x3", "-15", "trick"),
        cage(100, 0, 35, 30), E(128, 120, 0), crush(136, 2.2, 4.4, 0.3), g(150, "M", "+40", "timed"),
        bridge(166, 180, -1.8, 1.8), roll(192, 2, 5), ally(204, 3), ter(214, 236, "thorn", -W, 0), saw(226, 0.5, 4, 1.8),
        g(246, "x3", "+50"), drop(262, -1.5, 40), E(280, 200, 0) } },
}
for i, L in ipairs(LEVELS) do
    L.idx = i
    table.sort(L.ev, function(a, b) return a.z < b.z end)
end
-- tuning (autoplay 05:15): red crowds and boss HP are sized from a "good line" through the level
-- (start 10 pawns, best gate each time, ~8% lost per trap, cages/drops/allies taken), so a smart
-- run always wins and upgrades make it comfortable. Ratio climbs with the level number.
local function sim_gate(p, b, v)
    local o, n = v:sub(1, 1), tonumber(v:sub(2)) or 2
    if o == "+" then p = p + n elseif o == "x" then p = p * n elseif o == "/" then p = math.floor(p / n)
    elseif o == "-" then local t = math.min(p, n); p = p - t; b = math.max(0, b - (n - t))
    elseif o == "M" then b = b + math.floor(p / 2) * 3; p = p % 2 end
    return p, b
end
for i, L in ipairs(LEVELS) do
    local p, b = 10, 0
    local f = (0.33 + 0.02 * i) * (L.ease or 1)   -- ease: per-level trim for crowd-heavy layouts
    for _, e in ipairs(L.ev) do
        local t = e.t
        if t == "gate" then
            local p1, b1 = sim_gate(p, b, e.a)
            if e.b then
                local p2, b2 = sim_gate(p, b, e.b)
                if e.kind == "timed" or e.kind == "trick" then
                    -- lamp / trick gates: a steady player reads them right only part of the time, so size the
                    -- crowds that follow from the middle of the two outcomes, not from a perfect read
                    p1, b1 = math.floor((p1 + p2) / 2 + 0.5), math.floor((b1 + b2) / 2 + 0.5)
                elseif p2 + b2 > p1 + b1 then p1, b1 = p2, b2 end
            end
            p, b = p1, b1
        elseif t == "cage" or t == "drop" then p = p + e.n
        elseif t == "ally" then b = b + 8
        elseif t == "spin" or t == "saw" or t == "ham" or t == "crush" or t == "roll" then p = math.floor(p * 0.85)
        elseif t == "enemy" then
            e.n = math.max(6, math.floor((p + b) * f + 0.5))
            local k = e.n; local t2 = math.min(p, k); p = p - t2; b = math.max(0, b - (k - t2))
        end
    end
    L.good = p + b
    if L.boss then L.boss = math.max(40, math.floor((p + b) * (0.4 + 0.012 * i))) end
end
G.LEVELS = LEVELS

------------------------------------------------------------------ floor: solid x intervals at a given z
local function floor_at(L, z)
    if z < -12 or z > L.len + 3 then
        if L.boss then return z < L.len + 75 and { { -W - 2, W + 2 } } or {} end
        return z < L.len + 14 and { { -W, W } } or {}
    end
    local iv = { { -W, W } }
    for _, e in ipairs(L.ev) do
        if (e.t == "pit" or e.t == "bridge") and z >= e.z0 and z < e.z1 then
            if e.t == "bridge" then
                local n = {}
                for _, s in ipairs(iv) do local a, b = max(s[1], e.x0), min(s[2], e.x1); if b > a then n[#n + 1] = { a, b } end end
                iv = n
            else
                local n = {}
                for _, s in ipairs(iv) do
                    if e.x1 <= s[1] or e.x0 >= s[2] then n[#n + 1] = s
                    else
                        if e.x0 > s[1] then n[#n + 1] = { s[1], e.x0 } end
                        if e.x1 < s[2] then n[#n + 1] = { e.x1, s[2] } end
                    end
                end
                iv = n
            end
        end
    end
    return iv
end
local function solid(iv, x) for _, s in ipairs(iv) do if x >= s[1] and x <= s[2] then return true end end return false end
local function terrain_at(L, x, z)
    for _, e in ipairs(L.ev) do
        if e.t == "ter" and z >= e.z0 and z < e.z1 and x >= e.x0 and x <= e.x1 then return e.kind end
        if e.z > z then break end
    end
    return nil
end
G.floor_at, G.solid, G.terrain_at = floor_at, solid, terrain_at
