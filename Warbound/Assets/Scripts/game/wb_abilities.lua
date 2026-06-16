-- wb_abilities — hero abilities (cooldown + mana). Built as a small data list so
-- more abilities slot in without new control flow. Slice 1 ships one active:
-- Warstomp (AoE damage + slow around the hero).

local U = WB.util

local Abilities = {}

Abilities.LIST = {
    {
        id = "warstomp", name = "Warstomp", hotkey = "q", letter = "Q",
        mana = 35, cooldown = 8.0, radius = 5.5, damage = 70, per_level = 12, slow = 2.5,
        desc = "Slam the ground: damage + slow nearby foes.",
    },
}

Abilities.BY_ID = {}
for _, a in ipairs(Abilities.LIST) do Abilities.BY_ID[a.id] = a end

local prev_keys = {}

local function key_pressed(k)
    local down = input and input.is_key_down and input.is_key_down(k) == true
    local was = prev_keys[k]
    prev_keys[k] = down
    return down and not was
end

function Abilities.status(hero, id)
    local def = Abilities.BY_ID[id]
    if not hero or not hero.is_hero or not def then return "none" end
    local cd = (hero.cooldowns and hero.cooldowns[id]) or 0.0
    if not hero.alive then return "dead" end
    if cd > 0.0 then return "cooldown", cd end
    if (hero.mana or 0.0) < def.mana then return "mana" end
    return "ready"
end

function Abilities.try_cast(state, id)
    local hero = state.hero
    local def = Abilities.BY_ID[id]
    if not (hero and def and hero.alive) then return false end
    hero.cooldowns = hero.cooldowns or {}
    if (hero.cooldowns[id] or 0.0) > 0.0 then return false end
    if (hero.mana or 0.0) < def.mana then return false end

    hero.mana = hero.mana - def.mana
    hero.cooldowns[id] = def.cooldown

    if id == "warstomp" then
        local dmg = def.damage + (hero.level or 1) * def.per_level
        local r2 = def.radius * def.radius
        for _, e in ipairs(state.enemy_units) do
            if e.alive and U.dist2_sq(hero.x, hero.z, e.x, e.z) <= r2 then
                e.slow_t = def.slow
                WB.combat.apply_damage(e, dmg, hero, state)
            end
        end
        hero.attack_swing = 0.25
        WB.fx_stomp(hero.x, hero.z, def.radius)
    end
    return true
end

function Abilities.update(dt, state)
    local hero = state.hero
    if not hero or not hero.is_hero then return end
    hero.cooldowns = hero.cooldowns or {}
    if hero.alive then
        hero.mana = math.min(hero.mana_max or 0.0, (hero.mana or 0.0) + 6.0 * dt)
    end
    for id, cd in pairs(hero.cooldowns) do
        if cd > 0.0 then hero.cooldowns[id] = math.max(0.0, cd - dt) end
    end
    -- hotkeys
    for _, a in ipairs(Abilities.LIST) do
        if key_pressed(a.hotkey) then Abilities.try_cast(state, a.id) end
    end
end

return Abilities
