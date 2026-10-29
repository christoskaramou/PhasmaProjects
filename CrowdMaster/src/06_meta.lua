------------------------------------------------------------------ meta: save, coins/gems, upgrades, army board, treasury
do
local M = {}
G.M = M
local SAVE = "Save/crowdmaster.sav"
local function fresh()
    return { coins = 0, gems = 0, best = {}, unlocked = 1, up = {}, gem = {}, board = {}, recruits = 0, play = 0, bank = 0, last = 1, seen_tips = {}, fails = {} }
end
M.D = fresh()
function M.load()
    local ok, s = pcall(fs.read, SAVE)
    local d = ok and deser(s) or nil
    M.D = fresh()
    if d then for k, v in pairs(d) do M.D[k] = v end end
    for i = 1, 15 do M.D.board[i] = M.D.board[i] or 0 end
end
function M.save() pcall(fs.write, SAVE, ser(M.D)) end
function M.reset() M.D = fresh(); for i = 1, 15 do M.D.board[i] = 0 end; M.save() end

-- coin upgrades: id, name, blurb, base cost, max level
M.UP = {
    { id = "start", name = "Starting Crowd", desc = "+3 Runners At The Start", cost = 60, max = 10 },
    { id = "gate", name = "Gate Power", desc = "+10% On Every Plus Gate", cost = 80, max = 10 },
    { id = "armor", name = "Trap Armor", desc = "7% Chance To Shrug Off A Hit", cost = 90, max = 8 },
    { id = "speed", name = "Run Speed", desc = "+4% Running Speed", cost = 70, max = 6 },
    { id = "might", name = "Clash Might", desc = "6% Chance To Win A Duel Free", cost = 100, max = 8 },
    { id = "bank", name = "Treasury", desc = "+4 Coins Per Minute Played", cost = 120, max = 10 },
}
-- gem upgrades
M.GEM = {
    { id = "shield", name = "Shield Bubble", desc = "Space: 3s Of Immunity (Charges)", cost = 3, max = 3 },
    { id = "magnet", name = "Coin Magnet", desc = "Pull Coins And Drops From Afar", cost = 2, max = 4 },
    { id = "breaker", name = "Boss Breakers", desc = "Orange Units That Wreck Bosses", cost = 4, max = 5 },
    { id = "lucky", name = "Lucky Eye", desc = "See Through Trick Gates", cost = 3, max = 1 },
}
function M.lvl(id) return M.D.up[id] or 0 end
function M.glvl(id) return M.D.gem[id] or 0 end
function M.cost(u) return floor(u.cost * 1.55 ^ M.lvl(u.id) + 0.5) end
function M.gcost(u) return u.cost + M.glvl(u.id) * 2 end
function M.buy(u)
    if M.lvl(u.id) >= u.max then return false end
    local c = M.cost(u); if M.D.coins < c then return false end
    M.D.coins = M.D.coins - c; M.D.up[u.id] = M.lvl(u.id) + 1; M.save(); return true
end
function M.gbuy(u)
    if M.glvl(u.id) >= u.max then return false end
    local c = M.gcost(u); if M.D.gems < c then return false end
    M.D.gems = M.D.gems - c; M.D.gem[u.id] = M.glvl(u.id) + 1; M.save(); return true
end

-- effects consumed by the run
G.start_pawns = function() return 10 + 3 * M.lvl("start") end
G.gate_mult = function() return 1 + 0.1 * M.lvl("gate") end
G.armor_chance = function() return 0.07 * M.lvl("armor") end
G.speed_mult = function() return 1 + 0.04 * M.lvl("speed") end
G.might_chance = function() return 0.06 * M.lvl("might") end
G.magnet = function() return 1.2 * M.glvl("magnet") end
G.lucky_reveal = function() return M.glvl("lucky") > 0 end
G.shield_charges = function() return M.glvl("shield") end
G.breakers = function() return 2 * M.glvl("breaker") end
G.breaker_level = function() return M.glvl("breaker") end

-- underdog boost (catch-up): a player who reaches a level with fewer upgrades than the curve expects
-- (skipped the shop, or jumped ahead via Levels) gets smaller red crowds / boss HP and a few extra runners.
-- expected: ~1.5 coin-upgrade levels per cleared level; the army board counts too (1 level per board unit power 2)
function G.catchup(idx)
    local lv = 0
    for _, u in ipairs(M.UP) do if u.id ~= "bank" then lv = lv + M.lvl(u.id) end end
    local a = G.army_counts(); lv = lv + (a[1] * 0.5 + a[2] * 1.5 + a[3] * 4) / 2
    local deficit = max(0, (idx - 1) * 1.5 - lv)
    -- retry boost: every failed attempt at this level (since its last clear) adds runners and weakens foes a little
    local tries = min(4, (M.D.fails and M.D.fails[idx]) or 0)
    return { foe = max(0.68, 1 - min(0.22, 0.02 * deficit) - 0.04 * tries), pawns = min(12, floor(deficit)) + 3 * tries,
        deficit = deficit, tries = tries }
end
-- army board: 15 slots holding tier 0 (empty) / 1 pawn / 2 brute / 3 giant. merging two equal tiers makes the next tier
function M.recruit_cost() return floor(25 * 1.12 ^ (M.D.recruits or 0) + 0.5) end
function M.recruit()
    local c = M.recruit_cost(); if M.D.coins < c then return false, "Not Enough Coins" end
    for i = 1, 15 do if M.D.board[i] == 0 then
        M.D.board[i] = 1; M.D.coins = M.D.coins - c; M.D.recruits = (M.D.recruits or 0) + 1; M.save(); return true, i
    end end
    return false, "Board Full - Merge Units"
end
function M.merge(a, b)
    local B = M.D.board
    if a == b or B[a] == 0 then return false end
    if B[b] == 0 then B[b], B[a] = B[a], 0; M.save(); return "move" end
    if B[a] == B[b] and B[a] < 3 then B[b] = B[a] + 1; B[a] = 0; M.save(); return "merge" end
    B[a], B[b] = B[b], B[a]; M.save(); return "swap"
end
function M.auto_merge()  -- click helper: merge the first pair of equal units
    local B = M.D.board
    for t = 1, 2 do
        local first
        for i = 1, 15 do if B[i] == t then if first then return M.merge(i, first), first else first = i end end end
    end
    return false
end
-- each board pawn = 2 runners at the start, brute = 1 brute, giant = 1 giant
G.army_counts = function()
    local c = { 0, 0, 0 }
    for i = 1, 15 do local t = M.D.board[i]; if t == 1 then c[1] = c[1] + 2 elseif t == 2 then c[2] = c[2] + 1 elseif t == 3 then c[3] = c[3] + 1 end end
    return c
end

-- treasury: no wall clock in Lua, so it fills per in-game minute (menus included) and is collected in camp
function M.tick(dt)
    M.D.play = (M.D.play or 0) + dt
    local rate = 4 * M.lvl("bank") / 60
    M.D.bank = min((M.D.bank or 0) + rate * dt, 60 + 120 * M.lvl("bank"))
end
function M.collect() local n = floor(M.D.bank or 0); M.D.bank = (M.D.bank or 0) - n; M.D.coins = M.D.coins + n; M.save(); return n end

-- end of a run: tally the rewards
function M.tally(L, idx, won, res, st)
    local r = { lines = {} }
    local function add(name, v) if v ~= 0 then r.lines[#r.lines + 1] = { name, v } end end
    local coins = st.coins
    add("Coins Picked Up", st.coins)
    if won then
        local left = res.left or 0
        local fin = floor(left * res.mult * 0.5 + 0.5)
        add(res.kind == "boss" and "Boss Bounty" or ("Finish  x" .. string.format("%.1f", res.mult)), fin)
        add("Perfect Gates", st.perfect * 10)
        add("Traps Cleared", st.traps * 5)
        add("Close Calls", st.close * 5)
        add("Captives Freed", st.cages * 15)
        local best = M.D.best[idx]
        if not best then add("First Clear", 50) end
        coins = coins + fin + st.perfect * 10 + st.traps * 5 + st.close * 5 + st.cages * 15 + (best and 0 or 50)
        if res.kind == "boss" then add("Boss Kill", 100); coins = coins + 100 end
    else
        add("Enemies Beaten", floor(st.kills * 0.5))
        coins = coins + floor(st.kills * 0.5)
    end
    r.coins = coins
    r.gems = won and (res.gems or 0) or 0
    if won and st.lost_traps == 0 and st.gates > 0 and st.perfect == st.gates then r.gems = r.gems + 1; r.perfect_run = true end
    r.stars = won and res.stars or 0
    r.score = won and floor((res.left or 0) * res.mult * 10 + st.perfect * 50 + st.traps * 25) or 0
    M.D.coins = M.D.coins + r.coins
    M.D.gems = M.D.gems + r.gems
    M.D.fails = M.D.fails or {}
    if won then M.D.fails[idx] = nil else M.D.fails[idx] = min(4, (M.D.fails[idx] or 0) + 1) end
    if won then
        local b = M.D.best[idx] or { score = 0, stars = 0 }
        r.new_best = r.score > b.score
        M.D.best[idx] = { score = max(b.score, r.score), stars = max(b.stars, r.stars) }
        M.D.unlocked = max(M.D.unlocked, min(#G.LEVELS, idx + 1))
    end
    M.save()
    return r
end
end
