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

local function nearest_foe(u, foe_units, foe_buildings, radius)
    local best = nearest(u, foe_units, radius)
    local bd = best and U.dist2_sq(u.x, u.z, best.x, best.z) or nil
    local r2 = radius * radius
    for _, b in ipairs(foe_buildings or {}) do
        -- "done" buildings AND in-progress sites are valid targets (razing a site cancels
        -- the build), so an attack-move into the enemy base actually razes everything.
        if b.alive and (b.state == "done" or b.state == "site") then
            local d = U.dist2_sq(u.x, u.z, b.x, b.z)
            if d <= r2 and (not bd or d < bd) then best, bd = b, d end
        end
    end
    return best
end

-- Acquire / validate targets. Auto-acquisition never overrides an explicit
-- move/attack order; it only kicks in for idle (defend) and hold (attack-in-place).
function Combat.acquire(player_units, enemy_units, state)
    local pe = state and state.econ and state.econ.player
    local ee = state and state.econ and state.econ.enemy
    local player_buildings = pe and pe.buildings or {}
    local enemy_buildings = ee and ee.buildings or {}
    for _, u in ipairs(player_units) do
        if u.alive and not u.no_combat then -- Laborers never auto-engage (they harvest)
            if u.order == "idle" then
                local foe = nearest_foe(u, enemy_units, enemy_buildings, PLAYER_AGGRO)
                if foe then u.order = "attack"; u.target = foe; u.attack_move = true end
            elseif u.order == "hold" then
                u.target = nearest_foe(u, enemy_units, enemy_buildings, u.range + 0.8)
            elseif u.order == "attack" and (not u.target or not u.target.alive) then
                -- finished the target: if attack-moving, chase the next nearby foe/building;
                -- a unit on a manual single-target attack stands down (don't auto-chain).
                local foe = u.attack_move and nearest_foe(u, enemy_units, enemy_buildings, PLAYER_AGGRO) or nil
                if foe then u.target = foe else u.order = "idle"; u.target = nil end
            end
        end
    end
    for _, e in ipairs(enemy_units) do
        if e.alive then
            if (e.order == "idle") or (e.order == "attack" and (not e.target or not e.target.alive)) then
                local foe = nearest_foe(e, player_units, player_buildings, ENEMY_AGGRO)
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
    if target.is_building then
        local E = state and state.econ and state.econ[target.faction]
        -- Deactivate (park+hide the rig, alive=false) rather than kill(): kill pools the rig
        -- into a dead pool nobody reads, permanently shrinking the faction's reserves. Return
        -- it to building_reserves so this type can be rebuilt later.
        WB.units.deactivate(target)
        if E then
            U.compact(E.buildings, function(b) return b.alive end)
            E.building_reserves[target.arch] = E.building_reserves[target.arch] or {}
            table.insert(E.building_reserves[target.arch], target)
        end
        if pe_log then pe_log("[combat] " .. (target.display or target.arch) .. " razed (" .. (target.faction or "?") .. ")") end
        return
    end
    WB.units.kill(target)
    WB.selection.prune()
    WB.fx_death(target.x, target.z)
    if target.faction == "enemy" then
        state.enemy_alive = math.max(0, state.enemy_alive - 1)
        state.kills = (state.kills or 0) + 1
        state.econ.player.gold = state.econ.player.gold + (WB.units.ARCH[target.arch].bounty or 12)
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
    if target.faction == "enemy" and WB.ai then WB.ai.notify_base_attacked(target) end -- wake the Wilds defense director (only if hit near base)
    if target.hp <= 0.0 then
        target.hp = 0.0
        Combat.die(target, attacker, state)
    end
end

function Combat.buildings_pass(dt, state)
    for _, fac in ipairs({ "player", "enemy" }) do
        local E = state.econ[fac]
        local foe_fac = (fac == "player") and "enemy" or "player"
        local foes = state.econ[foe_fac].units
        for _, b in ipairs(E.buildings) do
            if b.alive and b.state == "done" and (b.dps or 0) > 0 then
                if not (b.target and b.target.alive)
                   or U.dist2(b.x, b.z, b.target.x, b.target.z) > b.range then
                    b.target = nearest(b, foes, b.range)
                end
                if b.target and b.target.alive then
                    if b.tower_target ~= b.target then
                        b.tower_target = b.target
                        if pe_log then pe_log("[combat] tower fired at " .. (b.target.display or b.target.arch)) end
                    end
                    b.attack_t = (b.attack_t or 0.0) - dt
                    if b.attack_t <= 0.0 then
                        local interval = b.interval or 1.0
                        b.attack_t = interval
                        Combat.apply_damage(b.target, b.dps * interval, b, state)
                        if WB.fx_hit then WB.fx_hit(b.target.x, b.target.z) end
                    end
                end
            end
        end
    end
end

function Combat.standing_town_halls(state)
    local counts = { player = 0, enemy = 0 }
    for _, fac in ipairs({ "player", "enemy" }) do
        for _, b in ipairs(state.econ[fac].buildings) do
            if b.alive and b.state == "done"
               and (b.arch == "town_hall" or b.arch == "enemy_town_hall") then
                counts[fac] = counts[fac] + 1
            end
        end
    end
    return counts
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
