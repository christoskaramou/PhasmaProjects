------------------------------------------------------------------ 04_sim: gameplay simulation (engine-agnostic)
local D = G.D
local SIM = {}
G.SIM = SIM
local abs, min, max, floor, sqrt, rand = math.abs, math.min, math.max, math.floor, math.sqrt, math.random
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
SIM.clamp = clamp

-- formation: slot offsets for n visible bodies (front row at z=0, rows going back)
-- columns are capped at 7 so even a full squad covers about half the lane (straight fire: where you stand is
-- what you hit); past 30 units the spacing widens a little (up to +17%) so a huge squad sweeps a wider strip.
local fcache = {}
local S -- current run state
function SIM.formation(n)
    local wb = 0
    if S then wb = floor(clamp((SIM.units() - 30) / 90, 0, 1) * 5 + 0.5) end
    local key = n * 8 + wb
    if fcache[key] then return fcache[key] end
    local sp = 0.74 + 0.025 * wb
    local cols = clamp(math.ceil(sqrt(n * 1.5)), 1, 7)
    local F = { ox = {}, oz = {}, R = 0.45 }
    local i, row = 0, 0
    while i < n do
        local k = min(cols, n - i)
        for c = 0, k - 1 do
            i = i + 1
            F.ox[i] = (c - (k - 1) / 2) * sp + ((row % 2 == 1) and sp * 0.25 or 0)
            F.oz[i] = -row * sp * 0.92
        end
        row = row + 1
    end
    F.R = (min(cols, n) - 1) / 2 * sp + 0.45
    F.depth = (row - 1) * sp * 0.92
    fcache[key] = F
    return F
end

function SIM.state() return S end
local function ev(e) S.events[#S.events + 1] = e end
SIM.ev = function(e) ev(e) end

function SIM.units() return S.sol + S.vet + S.hvy + (S.hero_hp > 0 and 1 or 0) end
-- squad WORTH in soldier-equivalents: what the counter shows. Matches the merge ratios (5 sol = 1 vet, 4 vet = 1 hvy)
-- so merging never lowers it; the hero counts as one body (worth 1) so the number never reads 0 while he stands.
function SIM.worth() return S.sol * D.WORTH.sol + S.vet * D.WORTH.vet + S.hvy * D.WORTH.hvy + (S.hero_hp > 0 and D.WORTH.hero or 0) end
function SIM.bodies()
    -- visible body kinds, front first
    local b = {}
    if S.hero_hp > 0 then b[1] = "hero" end
    for _ = 1, min(S.hvy, D.VIS - #b) do b[#b + 1] = "hvy" end
    for _ = 1, min(S.vet, D.VIS - #b) do b[#b + 1] = "vet" end
    for _ = 1, min(S.sol, D.VIS - #b) do b[#b + 1] = "sol" end
    return b
end
function SIM.firepower()
    local el = 1 + 0.1 * S.up.elite
    return S.sol * D.POWER.sol + (S.vet * D.POWER.vet + S.hvy * D.POWER.hvy) * el + (S.hero_hp > 0 and D.POWER.hero or 0)
end

function SIM.start(n, save)
    local L = D.LEVELS[n]
    S = { lvl = n, L = L, save = save, up = save.up, hero = save.hero, weapon = save.weapon or "rifle",
        t = 0, travel = 0, hold = false, events = {}, foes = {}, props = {}, gates = {}, bullets = {}, missiles = {}, bombs = {}, markers = {},
        allies = {}, beams = {}, sol = 6 + 2 * (save.up.squad or 0), vet = 0, hvy = 0, hero_hp = 10, vdmg = 0, hdmg = 0,
        x = 0, ratep = 0, dmgp = 0, coins = 0, score = 0, kills = 0, air = 0, airs = 0, peak = 0, slow = 0,
        script = D.gen_level(n), si = 1, hpk = L.hpk, over = nil, bacc = 0, slot = 0, juno = 0, boss = nil, bosses_left = 0,
        allyk = (1 + 0.15 * (save.up.ally or 0)) * (1 + 0.3 * (n - 1)), shake = 0, gunship = nil, jet = nil, nid = 0, finish_z = nil }
    -- catch-up assist: a player who reaches a level with fewer upgrades than the curve expects (skipped the shop,
    -- jumped ahead via level select) gets softer foes and a few extra recruits; fully upgraded players get nothing.
    local ups = 0
    for _, v in pairs(save.up) do ups = ups + v end
    local deficit = max(0, (n - 1) * 4.5 - ups)
    -- (straight-fire pass: stronger so even a brand-new save can clear L10; a fully upgraded save is unaffected)
    S.assist = min(0.5, deficit * 0.02)
    S.hpk = L.hpk * (1 - S.assist)
    S.assistdmg = 1 + min(0.6, deficit * 0.02)
    local rec = min(18, floor(deficit * 0.6))
    S.sol = S.sol + rec
    if deficit >= 2 then S.events[#S.events + 1] = { k = "assist", n = rec } end
    S.peak = SIM.worth()
    S.crit = 0.04 * S.up.crit + (S.hero == "hawke" and 0.15 or 0)
    S.gatek = (1 + 0.1 * S.up.gate) * (S.hero == "nova" and 1.35 or 1)
    S.airk = (1 + 0.12 * S.up.air) * (S.hero == "vex" and 1.6 or 1)
    S.armor = 0.05 * S.up.armor
    return S
end

local function newid() S.nid = S.nid + 1; return S.nid end

------------------------------------------------------------------ damage to the squad
function SIM.hurt(d, why)
    if S.over then return end
    local w0 = SIM.worth()
    for _ = 1, d do
        if rand() >= S.armor then
            -- hit points per body = its worth (vet 5 hits, heavy 20), so a hit costs ~1 worth however the squad is merged
            if S.sol > 0 then S.sol = S.sol - 1
            elseif S.vet > 0 then S.vdmg = S.vdmg + 1; if S.vdmg >= D.WORTH.vet then S.vdmg = 0; S.vet = S.vet - 1 end
            elseif S.hvy > 0 then S.hdmg = S.hdmg + 1; if S.hdmg >= D.WORTH.hvy then S.hdmg = 0; S.hvy = S.hvy - 1 end
            elseif S.hero_hp > 0 then S.hero_hp = S.hero_hp - 1 end
        end
    end
    local lost = w0 - SIM.worth()   -- worth actually lost (a dead Veteran = 5)
    ev({ k = "hurt", n = lost, why = why })
    S.shake = max(S.shake, min(0.5, 0.08 + d * 0.02))
    if SIM.units() <= 0 then S.over = "lose"; ev({ k = "lose" }) end
end

local function add_soldiers(v)
    if v >= 0 then S.sol = S.sol + v else SIM.hurt(-v, "gate") end
end
-- merges keep worth exactly (5 sol -> 1 vet = 5, 4 vet -> 1 hvy = 20); they buy firepower and toughness, not numbers
local function automerge()
    local nv, nh = 0, 0
    while S.sol > 60 do S.sol = S.sol - 5; S.vet = S.vet + 1; nv = nv + 1 end
    while S.vet > 30 do S.vet = S.vet - 4; S.hvy = S.hvy + 1; nh = nh + 1 end
    if nv + nh > 0 then ev({ k = "merge", auto = true, nv = nv, nh = nh }) end
end
function SIM.merge_all()
    local nv = floor(S.sol / 5); S.sol = S.sol - nv * 5; S.vet = S.vet + nv
    local nh = floor(S.vet / 4); S.vet = S.vet - nh * 4; S.hvy = S.hvy + nh
    ev({ k = "merge", nv = nv, nh = nh })
end

------------------------------------------------------------------ spawning
local function spawn_foe(t, x, z, extra)
    local E = D.ENEMY[t]
    local k = S.hpk
    local f = { id = newid(), t = t, x = clamp(x, -D.LANE, D.LANE), z = z, hp = E.hp * k, r = E.r, spd = E.spd, dmg = E.dmg, coin = E.coin,
        score = E.score, fly = E.fly, steer = E.steer, aggro = E.aggro, shield = E.shield and E.shield * k or 0, slow = 0, hit = 0, ph = rand() * 6 }
    f.maxhp = f.hp; f.maxsh = f.shield
    if extra then for kk, vv in pairs(extra) do f[kk] = vv end end
    S.foes[#S.foes + 1] = f
    return f
end
SIM.spawn_foe = spawn_foe
local function spawn_boss(b, z)
    local B = D.BOSS[b]
    local k = S.hpk
    -- boss toughness follows the squad you bring (half fixed, half your current damage) so every fight lasts
    local hp = (B.hp * k * 0.5 + (S.dps or 10) * 14) * (S.lvl <= 3 and 0.75 or 1)  -- first boss is a gentler intro
    local f = spawn_foe("brute", 0, z, { boss = b, name = B.name, hp = hp, r = B.r, spd = 2.4, dmg = 999, coin = B.coin, score = B.score,
        stop = B.stop, fly = B.fly, steer = 1.1, atk = 3.0, atk2 = 5.0, arrived = false, enr = 0, shield = 0 })
    f.maxhp = f.hp
    if S.lvl == #D.LEVELS then f.hp = f.hp * 1.5; f.maxhp = f.hp end
    S.boss = f
    ev({ k = "boss", b = b, name = B.name })
    return f
end
SIM.spawn_boss = spawn_boss

local function run_script()
    local lookahead = S.travel + D.SPAWN_Z
    while S.script[S.si] and S.script[S.si].d <= lookahead do
        local e = S.script[S.si]
        S.si = S.si + 1
        local z = e.d - S.travel
        if e.ev == "foe" then
            local f = spawn_foe(e.t, e.x, z, e.lane and { lane = true } or nil)
            if e.hm then f.hp = f.hp * e.hm; f.maxhp = f.hp; f.shield = f.shield * e.hm; f.maxsh = f.shield end
        elseif e.ev == "prop" then
            local p = { id = newid(), t = e.t, x = e.x, z = z, w = e.w, ally = e.ally, hit = 0 }
            if e.t == "crate" then p.hp = e.hp; p.hw = 0.75
            elseif e.t == "container" then p.hp = e.hp; p.hw = 1.3
            elseif e.t == "barricade" then p.hp = e.hp; p.hw = 2.4
            else p.hp = 6 * S.hpk; p.hw = 0.5 end
            p.maxhp = p.hp
            S.props[#S.props + 1] = p
        elseif e.ev == "gates" then
            local rowid = newid()
            for _, g in ipairs(e.row) do
                local gg = { id = newid(), row = rowid, k = g.k, x = g.x, z = z, v = g.v or 0, c0 = math.max(5, math.abs(g.v or 0)), mi = g.mi, per = g.per, maxv = g.maxv, hp = g.hp, prog = 0, hit = 0 }
                if g.k == "lock" then gg.maxhp = g.hp end
                S.gates[#S.gates + 1] = gg
            end
        elseif e.ev == "air" then
            if e.kind == "gunship" then S.gunship = { t = 0, dur = 6.5, cd = 0.6, x = -14, side = (rand() < 0.5) and -1 or 1 }; ev({ k = "gunship" })
            else
                S.props[#S.props + 1] = { id = newid(), t = "crate", x = rand() * 6 - 3, z = 38, drop = 2.2, w = e.w, hp = 12 * S.hpk, maxhp = 12 * S.hpk, hw = 0.75, hit = 0 }
                ev({ k = "drop" })
            end
        elseif e.ev == "hint" then ev({ k = "hint", txt = e.txt })
        elseif e.ev == "boss" then
            local b = spawn_boss(e.b, z + 10)
            S.bosses_left = e.b2 and 2 or 1
            S.boss2 = e.b2
        elseif e.ev == "finish" then S.finish_z = z end
    end
end

------------------------------------------------------------------ hits
local function award(f)
    local c = f.coin * (1 + 0.1 * S.up.bounty)
    S.coins = S.coins + c
    S.score = S.score + f.score
    S.kills = S.kills + 1
end
local splash
local function kill_foe(f, why)
    if f.dead then return end
    f.dead = true
    award(f)
    if not f.boss then S.air = min(1, S.air + 0.007 * S.airk) end
    ev({ k = "kill", t = f.t, x = f.x, z = f.z, fly = f.fly, boss = f.boss, why = why })
    if f.boss then
        S.bosses_left = S.bosses_left - 1
        S.shake = 1.0
        if S.bosses_left > 0 and S.boss2 then
            local b2 = S.boss2; S.boss2 = nil
            S.after = { t = 3.0, b = b2 }
        else S.boss = nil; S.win_t = 2.5 end
    end
end
local function dmg_foe(f, d, why)
    if f.dead then return end
    if rand() < S.crit then d = d * 3 end
    if f.shield > 0 then
        f.shield = f.shield - d
        f.hit = 0.12
        if f.shield <= 0 then d = -f.shield; f.shield = 0; ev({ k = "shieldbreak", x = f.x, z = f.z }) else return end
    end
    f.hp = f.hp - d
    f.hit = 0.12
    if f.hp <= 0 then kill_foe(f, why) end
end
SIM.dmg_foe = dmg_foe

local function explode(x, z, r, d, hurt_squad, kind)
    ev({ k = "boom", x = x, z = z, r = r, kind = kind or "red" })
    S.shake = max(S.shake, 0.35)
    for _, f in ipairs(S.foes) do
        if not f.dead then
            local dx, dz = f.x - x, f.z - z
            if dx * dx + dz * dz < (r + f.r) ^ 2 then dmg_foe(f, f.boss and d * 0.5 or d, "boom") end
        end
    end
    for _, p in ipairs(S.props) do
        if not p.dead and (p.t == "barrel" or p.t == "cryo") then
            local dx, dz = p.x - x, p.z - z
            if dx * dx + dz * dz < r * r then p.hp = 0; p.chain = 0.12 end
        end
    end
    if hurt_squad then
        local F = SIM.formation(min(D.VIS, SIM.units()))
        local dx = abs(S.x - x)
        if z < 2.5 + F.depth * 0.3 and dx < r + F.R then SIM.hurt(hurt_squad, "boom") end
    end
end
splash = explode
SIM.explode = explode

local function cryo(x, z, r)
    ev({ k = "boom", x = x, z = z, r = r, kind = "cryo" })
    for _, f in ipairs(S.foes) do
        if not f.dead then
            local dx, dz = f.x - x, f.z - z
            if dx * dx + dz * dz < r * r then f.slow = 5; dmg_foe(f, 3 * S.hpk, "cryo") end
        end
    end
end

local function prop_destroyed(p)
    p.dead = true
    if p.t == "crate" then
        S.weapon = p.w
        ev({ k = "weapon", w = p.w, x = p.x, z = p.z })
        S.coins = S.coins + 5
    elseif p.t == "container" then
        SIM.free_ally(p.ally, p.x, p.z)
        S.coins = S.coins + 10
    elseif p.t == "barrel" then explode(p.x, p.z, 4.0, 60 * S.hpk, 4, "red")
    elseif p.t == "cryo" then cryo(p.x, p.z, 6.5)
    elseif p.t == "barricade" then ev({ k = "breakwall", x = p.x, z = p.z }); S.coins = S.coins + 8 end
end

local function gate_color(g)
    if g.k == "lock" then return "grey" end
    if g.k == "merge" then return "gold" end
    if g.k == "mul" then return (g.mi <= 3) and "red" or "green" end
    if g.k == "trap" then return g.flip and "red" or "orange" end
    return (g.v < 0) and "red" or "blue"
end
SIM.gate_color = gate_color
function SIM.gate_label(g)
    if g.k == "lock" then return "x3", "LOCKED" end
    if g.k == "merge" then return "MERGE", "5 = 1 Elite" end
    if g.k == "mul" then return D.MULTXT[g.mi], nil end
    if g.k == "rate" then return (g.v >= 0 and "+" or "") .. g.v .. "%", "Fire Rate" end
    if g.k == "dmg" then return (g.v >= 0 and "+" or "") .. g.v .. "%", "Damage" end
    if g.k == "trap" then
        if g.flip then return tostring(g.v), "Overloaded!" end
        return "+" .. g.v, "Max " .. g.maxv
    end
    return (g.v >= 0 and "+" or "") .. g.v, nil
end

-- damage needed for the next step: climbing gets steeper the higher a gate already is
-- crits now count on gates too; the cost carries the average crit gain (1 + 2*crit) so fill pace stays as before
function SIM.gate_cost(g)
    local ck = 1 + 2 * (S.crit or 0)
    if g.k == "mul" then return ck * g.per * 2 ^ math.max(0, g.mi - 3) end
    if g.k == "rate" or g.k == "dmg" then return ck * g.per * (1 + math.max(0, g.v) / 15) ^ 2 end
    local c = g.c0 or 6
    return ck * g.per * (1 + math.max(0, g.v) / c) ^ 2
end
-- every point of squad damage that reaches a gate counts (bullets, pellets, laser, rocket hits and splash), with
-- the same crit roll as on foes; upgrades and catch-up assist are already inside the shot's damage. Allies,
-- gunship and airstrikes never call this.
local function hit_gate(g, d)
    g.hit = 0.1
    if rand() < S.crit then d = d * 3 end
    S.gdmg = (S.gdmg or 0) + d
    if g.k == "lock" then
        g.hp = g.hp - d
        if g.hp <= 0 then g.k = "mul"; g.mi = 5; ev({ k = "unlock", x = g.x, z = g.z }) end
        return
    end
    if g.k == "merge" or g.flip then return end
    g.prog = g.prog + d * S.gatek
    while g.prog >= SIM.gate_cost(g) do
        g.prog = g.prog - SIM.gate_cost(g)
        if g.k == "mul" then
            if g.mi < #D.MUL then g.mi = g.mi + 1; ev({ k = "gatetick", x = g.x, z = g.z, up = true }) else g.prog = 0 end
        elseif g.k == "rate" or g.k == "dmg" then
            g.v = min(g.v + 5, 60); ev({ k = "gatetick", x = g.x, z = g.z })
        else
            g.v = g.v + 1
            ev({ k = "gatetick", x = g.x, z = g.z, v = g.v })
            if g.k == "trap" and g.v > g.maxv then
                g.flip = true; g.v = -2 * g.v; g.prog = 0
                ev({ k = "flip", x = g.x, z = g.z })
                return
            end
        end
    end
end

------------------------------------------------------------------ allies
function SIM.free_ally(a, x, z)
    local A = D.ALLY[a]
    local al = { t = a, x = x, z = z, cd = 0.5, life = A.life, hp = A.hp and A.hp * S.allyk or nil, ang = 0, side = (x >= S.x) and 1 or -1, id = newid() }
    if a == "drones" then al.n = A.n end
    S.allies[#S.allies + 1] = al
    ev({ k = "ally", t = a, name = A.name, x = x, z = z })
end
local function nearest_foe(x, z, maxd, prefer_big)
    local best, bs = nil, 1e9
    for _, f in ipairs(S.foes) do
        if not f.dead and f.z > z - 1 and f.z - z < maxd and f.z < D.SPAWN_Z - 8 then
            local s = (f.z - z) + abs(f.x - x) * 0.5
            if prefer_big then s = s - f.hp * 0.05 - (f.boss and 100 or 0) end
            if s < bs then bs, best = s, f end
        end
    end
    return best
end
SIM.nearest_foe = nearest_foe
local function ally_shot(al, f, d, kind)
    dmg_foe(f, d, "ally")
    ev({ k = "trace", x0 = al.x, z0 = al.z, y0 = al.y or 1.2, x1 = f.x, z1 = f.z, y1 = f.fly and 2.2 or 1.0, kind = kind })
end
local function update_allies(dt)
    local F = SIM.formation(min(D.VIS, SIM.units()))
    for i = #S.allies, 1, -1 do
        local al = S.allies[i]
        local A = D.ALLY[al.t]
        al.cd = al.cd - dt
        -- follow the squad
        if al.t == "turret" then
            al.tx = clamp(S.x + al.side * (F.R + 1.3), -D.LANE, D.LANE)
            if abs(al.tx - S.x) < F.R + 0.6 then al.side = -al.side end
            al.tz = 0.4
        elseif al.t == "heli" then
            al.tx = clamp(S.x + al.side * 2.5 + math.sin(S.t * 0.7) * 1.5, -6, 6); al.tz = 4 + math.sin(S.t * 0.43) * 1.5; al.y = 7
            al.life = al.life - dt
            if al.life <= 0 then table.remove(S.allies, i); ev({ k = "allyleave", t = "heli" }); goto continue end
        elseif al.t == "mech" then al.tx = S.x; al.tz = 4.5 + F.R * 0.2
        elseif al.t == "sniper" then al.tx = (S.x > 0) and -4.6 or 4.6; al.tz = -2.5; al.y = 3.2
        else al.tx = S.x; al.tz = 0.5; al.y = 2.5 end
        al.x = al.x + (al.tx - al.x) * min(1, dt * 3)
        al.z = al.z + (al.tz - al.z) * min(1, dt * 2.5)
        if al.t == "turret" or al.t == "mech" or al.t == "drones" then
            if al.cd <= 0 then
                al.cd = 0.14
                local f = nearest_foe(al.x, al.z, 70)
                if f then
                    al.ang = math.atan2(f.x - al.x, f.z - al.z)
                    local nn = al.n or 1
                    ally_shot(al, f, A.dps * 0.14 * S.allyk * nn, al.t)
                end
            end
        elseif al.t == "sniper" then
            if al.cd <= 0 then
                local f = nearest_foe(al.x, al.z, 95, true)
                if f then al.cd = A.every; al.ang = math.atan2(f.x - al.x, f.z - al.z); ally_shot(al, f, A.shot * S.allyk * S.hpk ^ 0.5, "sniper") end
            end
        elseif al.t == "heli" then
            if al.cd <= 0 then
                local f = nearest_foe(al.x, al.z, 80, true)
                if f then
                    al.cd = A.every
                    S.missiles[#S.missiles + 1] = { x = al.x, z = al.z, y = 6.5, tgt = f, tx = f.x, tz = f.z, spd = 30, dmg = A.rocket * S.allyk, r = 2.6, id = newid() }
                    ev({ k = "missile" })
                end
            end
        end
        if al.t == "mech" and al.hp <= 0 then table.remove(S.allies, i); explode(al.x, al.z, 3, 40 * S.hpk, nil, "red"); ev({ k = "allydown", t = "mech" }) end
        ::continue::
    end
end

------------------------------------------------------------------ squad fire
local function fire(dt)
    local W = D.WEAPONS[S.weapon]
    local units = SIM.units()
    if units <= 0 then return end
    local nvis = min(units, D.VIS)
    local F = SIM.formation(nvis)
    local dmgmul = (1 + 0.12 * S.up.fire) * (1 + S.dmgp) * (S.hero == "rook" and 1.1 or 1) * (S.assistdmg or 1)
    local ratemul = (1 + 0.07 * S.up.rate) * (1 + S.ratep) * (S.hero == "bruno" and 1.25 or 1)
    local dps = SIM.firepower() * W.dps * dmgmul * ratemul
    S.dps = dps
    if W.beam then
        local nb = min(nvis, 6)
        S.beams = {}
        local per = dps * dt / nb
        for b = 1, nb do
            local slot = 1 + floor((b - 0.5) / nb * nvis)
            local bx = S.x + F.ox[slot]
            local bz0 = F.oz[slot] + 0.6
            -- collect hits in this column
            local hits = {}
            for _, f in ipairs(S.foes) do if not f.dead and abs(f.x - bx) < f.r + 0.15 and f.z > bz0 and f.z - bz0 < W.range then hits[#hits + 1] = { z = f.z, f = f } end end
            for _, p in ipairs(S.props) do if not p.dead and abs(p.x - bx) < p.hw and p.z > bz0 and p.z - bz0 < W.range then hits[#hits + 1] = { z = p.z, p = p } end end
            for _, g in ipairs(S.gates) do if not g.passed and abs(g.x - bx) < 2.3 and g.z > bz0 and g.z - bz0 < W.range then hits[#hits + 1] = { z = g.z, g = g } end end
            table.sort(hits, function(a, c) return a.z < c.z end)
            local endz = bz0 + W.range
            local pierce = W.pierce
            for _, h in ipairs(hits) do
                if h.f then dmg_foe(h.f, per, "laser")
                elseif h.p then h.p.hp = h.p.hp - per; h.p.hit = 0.1
                else hit_gate(h.g, per * D.GATE_PASS) end
                if not h.g then pierce = pierce - 1 end
                if pierce <= 0 or h.p then endz = h.z; break end
            end
            S.beams[b] = { x = bx, z0 = bz0, z1 = endz, slot = slot }
        end
        S.fire_t = (S.fire_t or 0) + dt
        return
    end
    S.beams = nil
    -- straight fire: every soldier shoots straight down the lane from where he stands. Rifle/minigun get a tiny
    -- jitter, the shotgun throws a fixed fan per volley, only Rockets lock on (a narrow forward cone) and curve in.
    local pellets = W.pellets or 1
    local bps = min(nvis / (W.rate / ratemul) * pellets, D.BULLETS_PS)
    local bd = dps / bps
    S.bacc = S.bacc + bps * dt
    while S.bacc >= 1 do
        S.bacc = S.bacc - 1
        S.pj = ((S.pj or 0) % pellets) + 1
        if S.pj == 1 or S.slot > nvis then S.slot = S.slot % nvis + 1 end
        local s = S.slot
        local a
        if pellets > 1 then a = math.rad(((S.pj - 1) / (pellets - 1) * 2 - 1) * W.spread + (rand() - 0.5) * 0.6)
        else a = math.rad((rand() - 0.5) * 2 * W.spread) end
        local bx0, bz0 = S.x + F.ox[s], F.oz[s] + 0.7
        local b = { x = bx0, z = bz0, vx = math.sin(a) * W.speed, vz = math.cos(a) * W.speed, d = bd, range = W.range, splash = W.splash, slot = s, id = newid() }
        if W.homing then
            -- lock on: closest foe inside a narrow forward cone (half-angle ~22 deg, at most 5 m to the side)
            local best, bz = nil, 1e9
            for _, f in ipairs(S.foes) do
                if not f.dead and f.z > bz0 + 3 and f.z < W.lock then
                    local dz = f.z - bz0
                    if abs(f.x - bx0) < min(dz * 0.4, 5) + f.r and dz < bz then bz, best = dz, f end
                end
            end
            if best then b.tgt = best; best.lockt = 0.6 end
            b.turn = W.turn
        end
        b.z0 = b.z
        S.bullets[#S.bullets + 1] = b
        S.shots = (S.shots or 0) + 1
        if S.pj == 1 then ev({ k = "shot", slot = s }) end
    end
end

-- a rocket's blast also fills any gate it overlaps (once per rocket per gate, shared with its fly-through hit)
local function splash_gates(b, x, z)
    local r = b.splash
    for _, g in ipairs(S.gates) do
        if not g.passed and abs(g.z - z) < r and abs(g.x - x) < 2.3 + r then
            b.gh = b.gh or {}
            if not b.gh[g.id] then b.gh[g.id] = true; hit_gate(g, b.d * D.GATE_PASS) end
        end
    end
end

local function step_bullets(dt)
    local bl = S.bullets
    local i = 1
    while i <= #bl do
        local b = bl[i]
        local z0 = b.z
        if b.tgt then
            local t = b.tgt
            if t.dead then b.tgt = nil
            else
                -- steer the heading toward the locked target at a capped turn rate: the trail visibly curves
                local h = math.atan2(b.vx, b.vz)
                local want = math.atan2(t.x - b.x, t.z - b.z)
                local dh = (want - h + math.pi) % (2 * math.pi) - math.pi
                h = h + clamp(dh, -b.turn * dt, b.turn * dt)
                local sp = sqrt(b.vx * b.vx + b.vz * b.vz)
                b.vx, b.vz = math.sin(h) * sp, math.cos(h) * sp
                t.lockt = max(t.lockt or 0, 0.25)
            end
        end
        b.x = b.x + b.vx * dt
        b.z = b.z + b.vz * dt
        local hit, hz, kind = nil, 1e9, nil
        local bx = b.x
        for _, f in ipairs(S.foes) do
            if not f.dead and f.z >= z0 - f.r and f.z - f.r <= b.z and abs(f.x - bx) < f.r + 0.1 and f.z < hz and f.z < D.SPAWN_Z - 5 then hit, hz, kind = f, f.z, 1 end
        end
        for _, p in ipairs(S.props) do
            if not p.dead and not p.drop and p.z >= z0 - 0.6 and p.z - 0.6 <= b.z and abs(p.x - bx) < p.hw and p.z < hz then hit, hz, kind = p, p.z, 2 end
        end
        -- gates never stop a projectile: it scores the gate once on the way through and keeps flying
        for _, g in ipairs(S.gates) do
            if not g.passed and g.z >= z0 and g.z <= b.z and abs(g.x - bx) < 2.3 and g.z < hz then
                b.gh = b.gh or {}
                if not b.gh[g.id] then b.gh[g.id] = true; hit_gate(g, b.d * D.GATE_PASS); ev({ k = "impact", x = bx, z = g.z - 0.3, kind = 3, thru = true }) end
            end
        end
        local dead = false
        if hit then
            dead = true
            if kind == 1 then
                if b.splash then explode(bx, hz, b.splash, b.d, nil, "rocket"); splash_gates(b, bx, hz) else dmg_foe(hit, b.d, "bullet") end
            elseif kind == 2 then
                hit.hp = hit.hp - b.d; hit.hit = 0.1
                if b.splash then explode(bx, hz, b.splash, b.d, nil, "rocket"); splash_gates(b, bx, hz) end
            end
            ev({ k = "impact", x = bx, z = hz - 0.3, kind = kind, t = (kind == 1) and hit.t or nil, fly = (kind == 1) and hit.fly or nil })
        elseif b.z - b.z0 > b.range then dead = true end
        if dead then bl[i] = bl[#bl]; bl[#bl] = nil else i = i + 1 end
    end
end

------------------------------------------------------------------ boss behaviour
local function boss_ai(f, dt)
    if not f.arrived then
        if f.z <= f.stop then
            f.arrived = true; S.hold = true; ev({ k = "bossarrive", b = f.boss })
            -- clear the arena: leftover gates sink away so the whole squad can fire at the boss
            for _, g in ipairs(S.gates) do if not g.passed then g.passed = true; g.gone = 0 end end
        end
        return
    end
    f.enr = f.enr + dt
    -- strafes across the lane (only loosely following you): keep lining up with it while dodging its attacks
    local btx = clamp(math.sin(f.enr * 0.42 + f.id) * 2.8 + S.x * 0.35, -3.6, 3.6)
    f.x = f.x + clamp(btx - f.x, -1.4 * dt, 1.4 * dt)
    f.atk = f.atk - dt
    f.atk2 = f.atk2 - dt
    local dk = (1 + 0.12 * (S.lvl - 1))
    local B = f.boss
    if B == "goliath" then
        if f.atk <= 0 then
            f.atk = max(2.4, 3.8 - f.enr * 0.02)
            S.markers[#S.markers + 1] = { x = S.x, z = 0.4, r = 2.4, t = 1.35, t0 = 1.35, dmg = floor(5 * dk), kind = "slam", from = f }
            ev({ k = "windup", b = B })
        end
        if f.atk2 <= 0 then f.atk2 = 7; for j = 1, 6 do spawn_foe("runner", f.x + (j - 3.5) * 1.1, f.z - 2) end; ev({ k = "roar" }) end
    elseif B == "ironclad" then
        if f.atk <= 0 then
            f.atk = max(2.8, 4.4 - f.enr * 0.02)
            for j = -1, 1 do S.markers[#S.markers + 1] = { x = clamp(S.x + j * 2.6 + (rand() - 0.5), -5, 5), z = 0.4 + rand() * 1.5, r = 1.8, t = 1.6 + j * 0.15, t0 = 1.6, dmg = floor(4 * dk), kind = "rocket", from = f } end
            ev({ k = "volley", b = B })
        end
        if f.atk2 <= 0 then f.atk2 = 8; for j = 1, 3 do spawn_foe("shield", (j - 2) * 3, f.z - 2) end end
    elseif B == "wasp" then
        if f.atk <= 0 then
            f.atk = max(1.6, 2.6 - f.enr * 0.015)
            spawn_foe("orb", f.x, f.z - 1.5, { hp = 5 * S.hpk ^ 0.7, maxhp = 5 * S.hpk ^ 0.7 })
            ev({ k = "spit" })
        end
        if f.atk2 <= 0 then f.atk2 = 6.5; for j = 1, 4 do spawn_foe("flyer", f.x + (j - 2.5) * 1.6, f.z - 1) end; ev({ k = "roar" }) end
    end
    -- the boss creeps forward slowly once it has stood its ground for a while
    if f.enr > 25 then f.z = f.z - dt * 0.25 * (1 + (f.enr - 25) / 30) end
    if f.z < 3 then SIM.hurt(9999, "boss") end
end

------------------------------------------------------------------ main step
function SIM.step(dt, input)
    if not S then return end
    S.t = S.t + dt
    if S.over then return end
    S.shake = max(0, S.shake - dt * 1.6)
    -- steering
    local nvis = min(SIM.units(), D.VIS)
    local F = SIM.formation(max(1, nvis))
    local lim = D.LANE - F.R * 0.6
    if input.tx then S.x = S.x + clamp(input.tx - S.x, -D.STEER * dt, D.STEER * dt) end
    if input.dir and input.dir ~= 0 then S.x = S.x + input.dir * D.STEER_KEY * dt end
    S.x = clamp(S.x, -lim, lim)
    -- world scroll
    local v = S.hold and 0 or D.SPEED
    S.travel = S.travel + v * dt
    S.v = v
    run_script()
    if S.after then S.after.t = S.after.t - dt; if S.after.t <= 0 then spawn_boss(S.after.b, 40); S.after = nil end end
    -- hero perks
    if S.hero == "juno" then S.juno = S.juno + dt; if S.juno >= 3 then S.juno = 0; S.sol = S.sol + 1; ev({ k = "recruit" }) end end
    automerge()
    S.peak = max(S.peak, SIM.worth())
    S.peakb = max(S.peakb or 0, SIM.units())   -- bodies (reports only)
    fire(dt)
    step_bullets(dt)
    update_allies(dt)
    -- foes
    local fr = F.R
    for _, f in ipairs(S.foes) do
        if not f.dead then
            f.hit = max(0, f.hit - dt)
            f.slow = max(0, f.slow - dt)
            local sp = (f.slow > 0) and 0.35 or 1
            if f.boss then
                if not f.arrived then f.z = f.z - (v + 4) * dt end
                boss_ai(f, dt)
            else
                f.z = f.z - (v + f.spd * sp) * dt
                f.lockt = max(0, (f.lockt or 0) - dt)
                if f.z < (f.aggro or 22) and not f.lane then
                    local tx = S.x
                    f.x = clamp(f.x + clamp(tx - f.x, -f.steer * dt * sp, f.steer * dt * sp), -D.LANE, D.LANE)
                end
                if f.fly then f.x = clamp(f.x + math.sin(S.t * 2.1 + f.ph) * dt * 1.2, -D.LANE, D.LANE) end
                -- ally mech blocks
                for _, al in ipairs(S.allies) do
                    if al.t == "mech" and abs(f.z - al.z) < f.r + 0.8 and abs(f.x - al.x) < f.r + 1.1 then
                        al.hp = al.hp - f.dmg * 6; f.dead = true; S.coins = S.coins + f.coin * 0.5
                        ev({ k = "stomp", x = f.x, z = f.z, t = f.t }); break
                    end
                end
                if not f.dead and f.z <= 0.6 + f.r and f.z > -F.depth - 1 and abs(f.x - S.x) < fr + f.r * 0.8 then
                    f.dead = true
                    ev({ k = "contact", x = f.x, z = f.z, t = f.t })
                    SIM.hurt(f.dmg, f.t)
                elseif f.z < -F.depth - 3 then f.dead = true; f.escaped = true end
            end
        end
    end
    -- props
    for _, p in ipairs(S.props) do
        if not p.dead then
            p.hit = max(0, (p.hit or 0) - dt)
            if p.drop then p.drop = max(0, p.drop - dt); if p.drop == 0 then p.drop = nil; ev({ k = "land", x = p.x, z = p.z }) end
            else p.z = p.z - v * dt end
            if p.chain then p.chain = p.chain - dt; if p.chain <= 0 then p.chain = nil; prop_destroyed(p) end
            elseif p.hp <= 0 then prop_destroyed(p)
            elseif p.z <= 0.5 + 0.6 then
                if abs(p.x - S.x) < fr + p.hw then
                    if p.t == "barrel" then p.dead = true; explode(p.x, p.z, 3.5, 30 * S.hpk, 5, "red")
                    elseif p.t == "cryo" then p.dead = true; cryo(p.x, p.z, 5)
                    elseif p.t == "barricade" then p.dead = true; ev({ k = "breakwall", x = p.x, z = p.z, crash = true }); SIM.hurt(math.ceil(p.hp / (6 * S.hpk)), "wall")
                    elseif p.z < -2 then p.dead = true end
                elseif p.z < -3 then p.dead = true end
            end
        end
    end
    -- gates
    for _, g in ipairs(S.gates) do
        g.hit = max(0, g.hit - dt)
        if not g.passed then g.z = g.z - v * dt end
    end
    local passed_row = nil
    for _, g in ipairs(S.gates) do
        if not g.passed and g.z <= 0.2 then
            passed_row = g.row
            break
        end
    end
    if passed_row then
        local best, bd = nil, 1e9
        for _, g in ipairs(S.gates) do
            if g.row == passed_row then
                local d = abs(S.x - g.x)
                if d < bd then bd, best = d, g end
            end
        end
        if best and bd > 2.4 then best = nil end
        for _, g in ipairs(S.gates) do if g.row == passed_row then g.passed = true; g.gone = 0 end end
        if best then SIM.apply_gate(best) end
    end
    for i = #S.gates, 1, -1 do
        local g = S.gates[i]
        if g.passed then g.gone = g.gone + dt; g.z = g.z - D.SPEED * dt; if g.gone > 1.2 then table.remove(S.gates, i) end end
    end
    -- missiles (heli / gunship)
    for i = #S.missiles, 1, -1 do
        local m = S.missiles[i]
        if m.tgt and not m.tgt.dead then m.tx, m.tz = m.tgt.x, m.tgt.z end
        local dx, dz, dy = m.tx - m.x, m.tz - m.z, 1 - m.y
        local d = sqrt(dx * dx + dz * dz + dy * dy)
        local st = m.spd * dt
        if d <= st then
            explode(m.tx, m.tz, m.r, m.dmg * S.hpk ^ 0.6, nil, "rocket")
            table.remove(S.missiles, i)
        else m.x = m.x + dx / d * st; m.z = m.z + dz / d * st; m.y = m.y + dy / d * st end
    end
    -- boss markers
    for i = #S.markers, 1, -1 do
        local mk = S.markers[i]
        mk.t = mk.t - dt
        if mk.t <= 0 then
            table.remove(S.markers, i)
            ev({ k = "boom", x = mk.x, z = mk.z, r = mk.r, kind = mk.kind })
            local dx = abs(S.x - mk.x)
            if dx < mk.r + F.R * 0.5 then SIM.hurt(mk.dmg, "boss") elseif dx < mk.r + F.R then SIM.hurt(floor(mk.dmg / 2 + 0.5), "boss") end
            S.shake = max(S.shake, 0.6)
        end
    end
    -- airstrike
    S.air = min(1, S.air + dt / 24 * S.airk)
    if input.strike and S.air >= 1 and not S.jet then SIM.airstrike() end
    if S.jet then
        S.jet.t = S.jet.t + dt
        while S.jet.bombs[1] and S.jet.bombs[1].at <= S.jet.t do
            local b = table.remove(S.jet.bombs, 1)
            S.bombs[#S.bombs + 1] = { x = b.x, z = b.z, y = 22, vy = -4 }
            ev({ k = "bombdrop" })
        end
        if S.jet.t > 4 then S.jet = nil end
    end
    for i = #S.bombs, 1, -1 do
        local b = S.bombs[i]
        b.vy = b.vy - 30 * dt; b.y = b.y + b.vy * dt; b.z = b.z - v * dt
        if b.y <= 0.4 then table.remove(S.bombs, i); explode(b.x, b.z, 4.2, 70 * S.hpk * (1 + 0.1 * S.up.air), nil, "bomb") end
    end
    -- scripted gunship pass
    if S.gunship then
        local gs = S.gunship
        gs.t = gs.t + dt
        gs.cd = gs.cd - dt
        if gs.cd <= 0 and gs.t > 1 and gs.t < gs.dur - 1 then
            gs.cd = 0.35
            local f = nearest_foe(0, 0, 85, true)
            if f then
                S.missiles[#S.missiles + 1] = { x = gs.side * (-9 + gs.t * 3), z = 8, y = 9, tgt = f, tx = f.x, tz = f.z, spd = 34, dmg = 22, r = 2.4, id = newid() }
                ev({ k = "missile" })
            end
        end
        if gs.t > gs.dur then S.gunship = nil end
    end
    -- cleanup dead
    local fo = S.foes
    for i = #fo, 1, -1 do if fo[i].dead then table.remove(fo, i) end end
    local pr = S.props
    for i = #pr, 1, -1 do if pr[i].dead then table.remove(pr, i) end end
    -- win
    if S.win_t then S.win_t = S.win_t - dt; if S.win_t <= 0 then SIM.finish(true) end end
    if S.finish_z then
        S.finish_z = S.finish_z - v * dt
        if S.finish_z <= 0 and not S.win_t then
            local any = false
            for _, f in ipairs(S.foes) do if f.z > 0 then any = true end end
            if not any then S.win_t = 0.8; ev({ k = "finishline" }) else S.finish_z = 0 end
        end
    end
end

function SIM.airstrike()
    S.air = 0
    S.airs = S.airs + 1
    local nb = 6 + S.up.air
    local tg = {}
    for _, f in ipairs(S.foes) do if not f.dead and f.z > 4 and f.z < 85 then tg[#tg + 1] = f end end
    table.sort(tg, function(a, b) return (a.boss and 1e6 or a.hp) > (b.boss and 1e6 or b.hp) end)
    local bombs = {}
    for j = 1, nb do
        local f = tg[((j - 1) % max(1, #tg)) + 1]
        local x = f and (f.x + (rand() - 0.5) * 1.5) or (rand() * 8 - 4)
        local z = f and (f.z - 2 + rand() * 2) or (12 + j * 7)
        bombs[j] = { x = x, z = z + 0.5 * 8 * 0.35 * 0, at = 0.5 + j * 0.13 }
    end
    S.jet = { t = 0, bombs = bombs }
    ev({ k = "airstrike" })
end

function SIM.apply_gate(g)
    local before = SIM.worth()
    if g.k == "add" or g.k == "trap" then add_soldiers(g.v)
    elseif g.k == "mul" then
        -- multiply the whole squad's WORTH (new troops arrive as soldiers, automerge folds them up), so merged
        -- squads are never punished; a divide gate takes worth via hits (1 hit ~ 1 worth)
        local m = D.MUL[g.mi]
        if m > 1 then S.sol = S.sol + floor(before * (m - 1) + 0.5)
        else SIM.hurt(before - max(1, floor(before * m + 0.5)), "gate") end
    elseif g.k == "lock" then -- passed while still locked: nothing
    elseif g.k == "rate" then S.ratep = max(-0.5, S.ratep + g.v / 100)
    elseif g.k == "dmg" then S.dmgp = max(-0.5, S.dmgp + g.v / 100)
    elseif g.k == "merge" then SIM.merge_all() end
    local good = (g.k == "merge") or ((g.k == "rate" or g.k == "dmg") and g.v >= 0) or (g.k == "mul" and g.mi > 3) or ((g.k == "add" or g.k == "trap") and g.v >= 0)
    if g.k == "lock" then good = nil end
    ev({ k = "gate", good = good, mult = g.k == "mul" and g.mi > 3, g = g, delta = SIM.worth() - before })
end

function SIM.finish(win)
    if S.over then return end
    S.over = win and "win" or "lose"
    local surv = SIM.worth()
    S.surv = surv
    if win then
        S.bonus = 40 + 20 * S.lvl + floor(surv / 10)
        S.coins = S.coins + S.bonus
        S.score = S.score + surv * 2   -- worth is ~5-10x bodies; keeps score scale near the old body-based one
        local r = surv / max(1, S.peak)
        S.stars = (r >= 0.55) and 3 or ((r >= 0.25) and 2 or 1)
    end
    ev({ k = win and "win" or "lose" })
end
