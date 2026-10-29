------------------------------------------------------------------ 03_data: tables (engine-agnostic; also loaded by tools/simtest)
local D = {}
G.D = D
D.STEER = 26         -- m/s the squad chases the pointer (was 14: snappy, no floaty lag)
D.STEER_KEY = 16     -- m/s with A/D or arrow keys
D.GATE_PASS = 0.75   -- share of a projectile's damage a gate takes as it flies through (projectiles are not stopped)
D.LANE = 5.0          -- usable half width of the lane (deck is 5.5)
D.SPAWN_Z = 100       -- things appear this far ahead
D.SPEED = 5.5         -- march speed (world scroll), m/s
D.VIS = 30            -- bodies drawn in the squad (the rest is a number)
D.BULLETS_PS = 150    -- cap on simulated bullets per second (damage per bullet grows instead)

-- weapons: dps = damage per second per unit of firepower; rate = seconds between shots of one rifleman
D.WEAPONS = {
    rifle = { name = "Rifle", rate = 0.32, dps = 1.0, speed = 80, spread = 0.5, range = 98, col = { 1.0, 0.82, 0.4 } },
    shotgun = { name = "Shotgun", rate = 0.8, dps = 1.35, pellets = 4, speed = 62, spread = 5.5, range = 42, col = { 1.0, 0.65, 0.3 } },
    minigun = { name = "Minigun", rate = 0.1, dps = 1.45, speed = 85, spread = 1.4, range = 92, col = { 1.0, 0.9, 0.5 } },
    rocket = { name = "Rockets", rate = 1.15, dps = 1.55, speed = 40, spread = 0.6, homing = true, lock = 55, turn = 2.6, range = 98, splash = 2.4, col = { 1.0, 0.55, 0.2 } },
    laser = { name = "Laser", rate = 0.6, dps = 1.75, beam = true, pierce = 3, range = 80, col = { 0.4, 0.95, 1.0 } },
}
D.WORDER = { "rifle", "shotgun", "minigun", "rocket", "laser" }
D.WPRICE = { rifle = 0, shotgun = 400, minigun = 1100, rocket = 2200, laser = 4000 }
D.POWER = { sol = 1, vet = 5, hvy = 22, hero = 8 }   -- firepower per body (heavy: +10% over its 4 vets)
D.WORTH = { sol = 1, vet = 5, hvy = 20, hero = 1 }   -- counter worth = merge ratios, so merging never lowers it

-- enemies (hp before level scaling)
D.ENEMY = {
    runner = { hp = 4, spd = 3.0, r = 0.45, dmg = 1, coin = 1, score = 10, steer = 1.0, aggro = 22 },
    brute = { hp = 70, spd = 1.9, r = 1.0, dmg = 6, coin = 6, score = 60, steer = 0.3, aggro = 18 },
    shield = { hp = 7, shield = 32, spd = 2.5, r = 0.55, dmg = 2, coin = 3, score = 30, steer = 0.7, aggro = 18 },
    flyer = { hp = 9, spd = 4.6, r = 0.6, dmg = 3, coin = 3, score = 30, steer = 1.3, aggro = 26, fly = true },
    orb = { hp = 5, spd = 9, r = 0.5, dmg = 3, coin = 0, score = 5, steer = 2.4, aggro = 30, fly = true },
}
D.BOSS = {
    goliath = { name = "Goliath", hp = 4800, r = 2.0, stop = 16, coin = 120, score = 2000, body = "gol" },
    ironclad = { name = "Ironclad", hp = 6500, r = 2.2, stop = 18, coin = 180, score = 3000, body = "mech" },
    wasp = { name = "Wasp Queen", hp = 8000, r = 2.0, stop = 17, coin = 260, score = 4000, body = "wasp", fly = true },
}
-- allies freed from containers
D.ALLY = {
    turret = { name = "Sentry Turret", dps = 14 },
    heli = { name = "Gunship", dps = 0, rocket = 34, every = 1.1, life = 32 },
    mech = { name = "Ally Mech", dps = 18, hp = 90 },
    sniper = { name = "Sniper Nest", shot = 90, every = 1.3 },
    drones = { name = "Drone Swarm", dps = 5, n = 3 },
}
D.AORDER = { "turret", "heli", "mech", "sniper", "drones" }

-- gate kinds; colour = panel mesh
D.GATE = {
    add = { col = "blue" }, sub = { col = "red" }, mul = { col = "green" }, div = { col = "red" },
    lock = { col = "grey" }, rate = { col = "blue" }, dmg = { col = "blue" }, merge = { col = "gold" }, trap = { col = "orange" },
}
D.MUL = { 0.25, 1 / 3, 0.5, 1.5, 2, 2.5 }          -- ladder; shooting climbs it
D.MULTXT = { "÷4", "÷3", "÷2", "x1.5", "x2", "x2.5" }

-- worlds: 2 levels each
D.WORLDS = {
    harbor = { name = "Harbor", sky = "harbor.hdr" }, canyon = { name = "Canyon", sky = "canyon.hdr" },
    forest = { name = "Autumn Woods", sky = "forest.hdr" }, frost = { name = "Frost Bay", sky = "frost.hdr" },
    volcano = { name = "Ember Peaks", sky = "volcano.hdr" },
}
-- levels: len (m), hp scale, horde size scale, features, boss
D.LEVELS = {
    { name = "Harbor Run", world = "harbor", len = 430, hpk = 1.0, nk = 1.00, feat = { add = 1, mul = 1, crate = 1 }, ally = "turret" },
    { name = "Dockyard Siege", world = "harbor", len = 500, hpk = 1.25, nk = 1.38, feat = { add = 1, mul = 1, crate = 1, brute = 1, rate = 1, barrel = 1 }, ally = "heli" },
    { name = "Red Mesa", world = "canyon", len = 520, hpk = 1.55, nk = 1.50, feat = { add = 1, mul = 1, crate = 1, brute = 1, shield = 1, trap = 1, barrel = 1 }, ally = "sniper", boss = "goliath" },
    { name = "Dust Bridge", world = "canyon", len = 580, hpk = 1.9, nk = 1.62, feat = { add = 1, mul = 1, crate = 1, brute = 1, shield = 1, flyer = 1, lock = 1, barricade = 1, barrel = 1, dmg = 1 }, ally = "drones" },
    { name = "Pine Pass", world = "forest", len = 600, hpk = 2.3, nk = 1.74, feat = { add = 1, mul = 1, crate = 1, brute = 1, shield = 1, flyer = 1, merge = 1, trap = 1, barrel = 1, rate = 1 }, ally = "mech", boss = "ironclad" },
    { name = "Autumn Gorge", world = "forest", len = 650, hpk = 2.8, nk = 1.86, feat = { add = 1, mul = 1, crate = 1, brute = 1, shield = 1, flyer = 1, merge = 1, lock = 1, barricade = 1, barrel = 1, dmg = 1 }, ally = "heli" },
    { name = "Frost Span", world = "frost", len = 680, hpk = 3.4, nk = 2.04, feat = { add = 1, mul = 1, crate = 1, brute = 1, shield = 1, flyer = 1, merge = 1, trap = 1, cryo = 1, lock = 1 }, ally = "turret", boss = "wasp" },
    { name = "Glacier Gate", world = "frost", len = 720, hpk = 4.1, nk = 2.22, feat = { add = 1, mul = 1, crate = 1, brute = 1, shield = 1, flyer = 1, merge = 1, trap = 1, cryo = 1, lock = 1, barricade = 1, rate = 1 }, ally = "mech" },
    { name = "Ember Crossing", world = "volcano", len = 760, hpk = 5.0, nk = 2.40, feat = { add = 1, mul = 1, crate = 1, brute = 1, shield = 1, flyer = 1, merge = 1, trap = 1, barrel = 1, lock = 1, barricade = 1, dmg = 1 }, ally = "sniper", boss = "ironclad" },
    { name = "Inferno Gate", world = "volcano", len = 820, hpk = 6.0, nk = 2.64, feat = { add = 1, mul = 1, crate = 1, brute = 1, shield = 1, flyer = 1, merge = 1, trap = 1, barrel = 1, lock = 1, barricade = 1, rate = 1, dmg = 1 }, ally = "heli", boss = "goliath", boss2 = "wasp" },
}

-- shop
D.UPG = {
    { key = "fire", name = "Firepower", desc = "+12% damage", base = 60, max = 20 },
    { key = "rate", name = "Fire Rate", desc = "+7% fire rate", base = 70, max = 15 },
    { key = "squad", name = "Starting Squad", desc = "+2 soldiers at the start", base = 50, max = 15 },
    { key = "crit", name = "Critical Hits", desc = "+4% chance of a x3 hit", base = 90, max = 10 },
    { key = "gate", name = "Gate Mastery", desc = "Gates climb 10% faster", base = 80, max = 10 },
    { key = "armor", name = "Body Armor", desc = "+5% chance to shrug off a hit", base = 100, max = 8 },
    { key = "elite", name = "Elite Training", desc = "Veterans and Heavies hit 10% harder", base = 120, max = 10 },
    { key = "air", name = "Air Support", desc = "Airstrikes charge 12% faster, +1 bomb", base = 110, max = 8 },
    { key = "ally", name = "Ally Tech", desc = "Freed allies are 15% stronger", base = 100, max = 8 },
    { key = "bounty", name = "Bounty", desc = "+10% coins", base = 120, max = 10 },
}
function D.upg_cost(u, lvl) return math.floor(u.base * (1.42 ^ lvl) / 5 + 0.5) * 5 end
D.HEROES = {
    { key = "rook", name = "Rook", desc = "Steady leader: +10% damage", coins = 0, medals = 0 },
    { key = "juno", name = "Juno", desc = "Field medic: a new recruit every 3 s", coins = 600, medals = 1 },
    { key = "bruno", name = "Bruno", desc = "Gunner: +25% fire rate", coins = 1200, medals = 2 },
    { key = "vex", name = "Vex", desc = "Demolitions: airstrikes charge 60% faster", coins = 1800, medals = 3 },
    { key = "hawke", name = "Hawke", desc = "Marksman: +15% crit chance", coins = 2600, medals = 4 },
    { key = "nova", name = "Nova", desc = "Tactician: gates climb 35% faster, +1 to plus gates", coins = 3600, medals = 5 },
}

------------------------------------------------------------------ save game (fs is optional: the sim test has none)
D.SAVE = "Save/gatebreaker.sav"
function D.new_save()
    local s = { coins = 0, medals = 0, unlocked = 1, best = {}, stars = {}, up = {}, heroes = { rook = true }, hero = "rook",
        weapons = { rifle = true }, weapon = "rifle", seen_tut = false }
    for _, u in ipairs(D.UPG) do s.up[u.key] = 0 end
    return s
end
function D.serialize(s)
    local o = {}
    local function kv(k, v) o[#o + 1] = k .. "=" .. tostring(v) end
    kv("coins", s.coins); kv("medals", s.medals); kv("unlocked", s.unlocked); kv("hero", s.hero); kv("weapon", s.weapon); kv("seen_tut", s.seen_tut)
    for i = 1, #D.LEVELS do kv("best" .. i, s.best[i] or 0); kv("stars" .. i, s.stars[i] or 0) end
    for k, v in pairs(s.up) do kv("up_" .. k, v) end
    for k in pairs(s.heroes) do kv("hero_" .. k, 1) end
    for k in pairs(s.weapons) do kv("wpn_" .. k, 1) end
    return table.concat(o, "\n")
end
function D.deserialize(txt)
    local s = D.new_save()
    for line in tostring(txt or ""):gmatch("[^\n]+") do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k then
            local n = tonumber(v)
            if k == "coins" or k == "medals" or k == "unlocked" then s[k] = n or s[k]
            elseif k == "hero" or k == "weapon" then s[k] = v
            elseif k == "seen_tut" then s.seen_tut = v == "true"
            elseif k:sub(1, 4) == "best" then s.best[tonumber(k:sub(5))] = n
            elseif k:sub(1, 5) == "stars" then s.stars[tonumber(k:sub(6))] = n
            elseif k:sub(1, 3) == "up_" then s.up[k:sub(4)] = n or 0
            elseif k:sub(1, 5) == "hero_" then s.heroes[k:sub(6)] = true
            elseif k:sub(1, 4) == "wpn_" then s.weapons[k:sub(5)] = true end
        end
    end
    if not s.heroes[s.hero] then s.hero = "rook" end
    if not s.weapons[s.weapon] then s.weapon = "rifle" end
    s.unlocked = math.max(1, math.min(#D.LEVELS, s.unlocked or 1))
    return s
end
