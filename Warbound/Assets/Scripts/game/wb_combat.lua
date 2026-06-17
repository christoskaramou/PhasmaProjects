-- wb_combat — target acquisition, auto-attack, damage, death, and hero XP.
-- `state` (owned by wb_game) carries the unit lists, live counts, gold, kills, and
-- the hero reference.

local U = WB.util

local Combat = {}

local PLAYER_AGGRO = 8.0     -- idle player units defend within this radius
local ENEMY_AGGRO = 14.0     -- the camp seeks you out within this radius
local MAX_LEVEL = 10

local function nearest(u, foes, radius)
    local best, bd
    local r2 = radius * radius
    for _, e in ipairs(foes) do
        if e.alive then
            local d = U.dist2_sq(u.x, u.z, e.x, e.z)
            if d <= r2 and (not bd or d < bd) then best, bd = e, d end
        end
    end
    return best
end

-- Acquire / validate targets. Auto-acquisition never overrides an explicit
-- move/attack order; it only kicks in for idle (defend) and hold (attack-in-place).
function Combat.acquire(player_units, enemy_units)
    for _, u in ipairs(player_units) do
        if u.alive and not u.no_combat then -- Laborers never auto-engage (they harvest)
            if u.order == "idle" then
                local foe = nearest(u, enemy_units, PLAYER_AGGRO)
                if foe then u.order = "attack"; u.target = foe; u.attack_move = true end
            elseif u.order == "hold" then
                u.target = nearest(u, enemy_units, u.range + 0.8)
            elseif u.order == "attack" and (not u.target or not u.target.alive) then
                -- finished the target: if we auto-engaged, look for another nearby; else stand down
                local foe = u.attack_move and nearest(u, enemy_units, PLAYER_AGGRO) or nil
                if foe then u.target = foe else u.order = "idle"; u.target = nil end
            end
        end
    end
    for _, e in ipairs(enemy_units) do
        if e.alive then
            if (e.order == "idle") or (e.order == "attack" and (not e.target or not e.target.alive)) then
                local foe = nearest(e, player_units, ENEMY_AGGRO)
                if foe then e.order = "attack"; e.target = foe; e.attack_move = true
                elseif e.order == "attack" then e.order = "idle"; e.target = nil end
            end
        end
    end
end

function Combat.grant_xp(hero, amount)
    if not hero or not hero.is_hero then return end
    hero.xp = (hero.xp or 0) + amount
    while hero.level < MAX_LEVEL and hero.xp >= hero.xp_to_level do
        hero.xp = hero.xp - hero.xp_to_level
        hero.level = hero.level + 1
        hero.xp_to_level = math.floor(hero.xp_to_level * 1.4)
        hero.hp_max = hero.hp_max + 70; hero.hp = hero.hp + 70
        hero.dps = hero.dps + 5
        hero.mana_max = hero.mana_max + 25; hero.mana = hero.mana_max
        WB.fx_levelup(hero.x, hero.z)
    end
    if hero.level >= MAX_LEVEL then hero.xp = 0 end
end

function Combat.die(target, attacker, state)
    if not target.alive then return end
    WB.units.kill(target)
    WB.selection.prune()
    WB.fx_death(target.x, target.z)
    if target.faction == "enemy" then
        state.enemy_alive = math.max(0, state.enemy_alive - 1)
        state.kills = (state.kills or 0) + 1
        state.gold = (state.gold or 0) + (WB.units.ARCH[target.arch].bounty or 12)
        if state.hero and state.hero.alive then
            Combat.grant_xp(state.hero, target.xp_value or 25)
        end
    else
        state.player_alive = math.max(0, state.player_alive - 1)
        if target.is_hero then state.hero_dead = true end
    end
end

function Combat.apply_damage(target, amount, attacker, state)
    if not target or not target.alive or amount <= 0.0 then return end
    local mit = 1.0 - U.clamp(target.armor or 0.0, 0.0, 0.85)
    target.hp = target.hp - amount * mit
    target.hit_flash = 0.14
    if target.hp <= 0.0 then
        target.hp = 0.0
        Combat.die(target, attacker, state)
    end
end

-- Execute attacks for every unit whose target is alive and within reach.
function Combat.attacks(dt, units, state)
    for _, u in ipairs(units) do
        if u.alive and u.target and u.target.alive then
            local reach = u.range + (u.target.radius or 0.0) + 0.2
            if U.dist2(u.x, u.z, u.target.x, u.target.z) <= reach then
                u.attack_t = (u.attack_t or 0.0) - dt
                if u.attack_t <= 0.0 then
                    u.attack_t = u.interval
                    u.attack_swing = 0.25
                    Combat.apply_damage(u.target, u.dps * u.interval, u, state)
                end
            end
        end
    end
end

return Combat
