------------------------------------------------------------------ 03_data: tables (engine-agnostic; also loaded by tools/simtest.py)
local D = {}
G.D = D
D.SAVE = "Save/banners.sav"
D.STEP = 1 / 30          -- fixed simulation step
D.SPEED = 3.0            -- march speed, world units per second
D.EMIT = 12              -- packets leaving a region per second while a stream is being sent
D.PACK = 30              -- a send of N troops is split into ~N/k packets with k = ceil(N / PACK)
D.PROD = 0.85            -- troops per second for a medium region
D.CAP = { 25, 35, 45 }   -- size classes S/M/L
D.SIZEMUL = { 0.85, 1.0, 1.2 }
D.NEUTRAL = { 6, 10, 14 } -- neutral garrisons by size (scaled per level)
D.SEA_SLOW = 0.65        -- non-port troops crossing water
D.HILL_SLOW = 0.8        -- crossing hill regions
D.CLASH_R = 0.5          -- streams meeting closer than this fight
D.DECAY = 1.0            -- troops per second lost above the cap (overextension)
D.NREGEN = 0.25          -- neutral garrisons regrow +1 every 4 s back up to their starting garrison
D.NREGEN_WAIT = 5        -- ...after a 5 s pause since they were last attacked
D.TYPES = {
    town = { name = "Town", prod = 1.0, cap = 1.0, def = 1.0 },
    capital = { name = "Capital", prod = 1.4, cap = 1.5, def = 1.2, val = 8 },
    fort = { name = "Fort", prod = 0.9, cap = 1.2, def = 1.5, val = 3 },
    port = { name = "Port", prod = 1.0, cap = 1.0, def = 1.0, val = 2 },
    mine = { name = "Mine", prod = 0.8, cap = 0.9, def = 1.0, val = 5 },
}
D.TYPE_DESC = {
    capital = "Capital: +40% recruits, +50% cap, sturdy walls",
    fort = "Fort: defenders count 1.5x",
    port = "Port: troops sent from here sail at full speed",
    mine = "Mine: +6% recruits everywhere, abilities recharge 15% faster",
    town = "Town",
}
-- factions (0 = neutral). col = banner colour, pastel = map tile tint
D.FAC = {
    [0] = { name = "Neutral", col = { .81, .78, .72 }, pastel = { .86, .83, .76 } },
    { name = "Azure League", short = "Azure", col = { .25, .56, .94 }, pastel = { .55, .74, .98 } },
    { name = "Crimson Pact", short = "Crimson", col = { .88, .28, .25 }, pastel = { .96, .58, .54 } },
    { name = "Amber Host", short = "Amber", col = { .95, .65, .19 }, pastel = { .99, .82, .5 } },
    { name = "Jade Order", short = "Jade", col = { .18, .70, .43 }, pastel = { .52, .86, .64 } },
    { name = "Violet Empire", short = "Violet", col = { .56, .35, .85 }, pastel = { .76, .62, .95 } },
}
D.PERS = {
    steady = { name = "Steady", desc = "expands carefully, defends its borders", iv = 2.2, keep = 0.35, pbias = 1.0, nbias = 1.25, acts = 1, reach = 13, vult = 0 },
    warlord = { name = "Warlord", desc = "hunts your banners relentlessly", iv = 1.5, keep = 0.2, pbias = 1.7, nbias = 0.8, acts = 2, reach = 15, vult = 0 },
    vulture = { name = "Vulture", desc = "pounces on weakened regions", iv = 1.8, keep = 0.3, pbias = 1.1, nbias = 1.0, acts = 2, reach = 15, vult = 1.6 },
    empire = { name = "Emperor", desc = "a great empire that wields every ability", iv = 1.2, keep = 0.25, pbias = 1.5, nbias = 1.0, acts = 2, reach = 16, vult = 0.6, abil = true },
    passive = { name = "Recruit", desc = "a sleepy garrison", iv = 6.0, keep = 0.6, pbias = 0.6, nbias = 1.0, acts = 1, reach = 9, vult = 0 },
}
-- abilities: unlock = first level index where it is available
D.ABIL = {
    { key = "airdrop", name = "Airdrop", icon = "ab_airdrop", cd = 25, unlock = 2, target = true, desc = "Drop 12 troops on any region", n = 12 },
    { key = "march", name = "Forced March", icon = "ab_march", cd = 30, unlock = 3, target = false, desc = "Your troops march 80% faster for 8 s", dur = 8, mul = 1.8 },
    { key = "frost", name = "Frost", icon = "ab_frost", cd = 35, unlock = 5, target = true, desc = "Freeze enemy regions in an area for 7 s", dur = 7, rad = 5.5 },
    { key = "barrage", name = "Barrage", icon = "ab_barrage", cd = 40, unlock = 7, target = true, desc = "Shell a region: -40% garrison, wipes nearby streams", rad = 3.2, frac = 0.4, maxk = 25 },
}
D.ABIX = {}
for i, a in ipairs(D.ABIL) do D.ABIX[a.key] = i end
D.UPG = {
    { key = "recruit", name = "Recruitment", icon = "up_recruit", desc = "+6% troop production", step = 0.06 },
    { key = "boots", name = "Swift Boots", icon = "up_boots", desc = "+6% march speed", step = 0.06 },
    { key = "veteran", name = "Veteran Start", icon = "up_veteran", desc = "+3 troops on your starting regions", step = 3 },
    { key = "bastion", name = "Bastions", icon = "up_bastion", desc = "+8% defence of your regions", step = 0.08 },
    { key = "quarter", name = "Quartermaster", icon = "up_quarter", desc = "-8% ability cooldowns", step = 0.08 },
}
D.UPG_MAX = 5
D.UPG_COST = { 60, 120, 200, 320, 500 }
function D.upg_cost(l) return D.UPG_COST[l + 1] end
-- number of upgrades the player can buy right now (drives the "!" badge on Upgrades / War Chest buttons)
function D.affordable(sv)
    local n = 0
    for _, u in ipairs(D.UPG) do
        local lv = (sv.up or {})[u.key] or 0
        if lv < D.UPG_MAX and (sv.coins or 0) >= D.upg_cost(lv) then n = n + 1 end
    end
    return n
end
-- difficulty modes (Options > Difficulty). Level diffs in 03b_levels are the HARD tuning; the others scale them.
-- aiprod: AI recruit rate x, ivm: AI think interval x (higher = slower reactions), delay: + seconds before AIs move,
-- ng: neutral garrisons x, pstart: player start troops x, aicd: AI ability cooldown x
D.MODES = {
    { name = "Relaxed", aiprod = 0.72, ivm = 1.8, delay = 12, ng = 0.8, pstart = 1.5, aicd = 1.6 },
    { name = "Normal",  aiprod = 0.84, ivm = 1.4, delay = 7,  ng = 0.9, pstart = 1.3, aicd = 1.3 },
    { name = "Hard",    aiprod = 0.95, ivm = 1.1, delay = 3,  ng = 1.0, pstart = 1.1, aicd = 1.1 },
}
-- retry boost after each failed attempt on a level (cap 4 tries, reset on a win)
D.RETRY = { max = 4, troops = 0.12, aiprod = 0.04 }
function D.new_save()
    local s = { ver = 1, coins = 0, unlocked = 1, stars = {}, best = {}, up = {}, fails = {}, tut = false, wins = 0 }
    for _, u in ipairs(D.UPG) do s.up[u.key] = 0 end
    return s
end
-- tiny serializer for the save table (numbers, strings, booleans, nested tables)
local function ser(v, ind)
    local t = type(v)
    if t == "number" then return string.format("%.6g", v)
    elseif t == "boolean" then return tostring(v)
    elseif t == "string" then return string.format("%q", v)
    elseif t == "table" then
        local o = {}
        for k, x in pairs(v) do
            local kk = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
            o[#o + 1] = kk .. "=" .. ser(x)
        end
        table.sort(o)
        return "{" .. table.concat(o, ",") .. "}"
    end
    return "nil"
end
function D.serialize(s) return "return " .. ser(s) end
function D.deserialize(str)
    local base = D.new_save()
    if type(str) ~= "string" or #str < 8 then return base end
    local f = load(str, "save", "t", {})
    if f and setfenv then setfenv(f, {}) end
    if not f then return base end
    local ok, s = pcall(f)
    if not ok or type(s) ~= "table" then return base end
    for k, v in pairs(base) do if s[k] == nil then s[k] = v end end
    for k, v in pairs(base.up) do if type(s.up[k]) ~= "number" then s.up[k] = v end end
    return s
end
function D.stars_for(t, par) if t <= par then return 3 elseif t <= par * 1.6 then return 2 end return 1 end
function D.coins_for(lvl, stars) return 40 + 20 * stars + lvl * 10 end
