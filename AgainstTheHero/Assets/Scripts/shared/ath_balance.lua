-- Runtime balance database. Edit this file to tune classes, skills, and arena monsters.
-- Damage fields are deliberately explicit: dps drives contact/shots, charge.dmg_mult
-- drives single charge hits, and explode/boss_arc damage are fixed AoE hits.

if rawget(_G, "ATH_BALANCE") then return _G.ATH_BALANCE end

local Balance = {}

-- One nested source of truth. Keep visual/pooling constants out: they do not
-- change who wins a fight. `benchmarks` are shared assumptions for comparisons;
-- viability is derived below so it cannot drift from the live damage fields.
Balance.rules = {
    basic_attack = { ranged_damage_mult = 0.60, melee_secondary_mult = 0.45,
        projectile_speed = 19.0, projectile_hit_radius = 0.7, projectile_life = 1.4 },
    whirl = { cooldown = 1.2, melee_cooldown = 0.65, radius = 2.0,
        radius_per_stack = 0.4, melee_damage_mult = 0.30, ranged_damage_mult = 0.6 },
    knockback = { creep_melee = 2.2, creep_projectile = 3.4,
        hero_contact = 1.4, hero_projectile = 2.6 },
    crit = { base_chance = 0.03, damage_mult = 2.0, bleed_seconds = 3.0 },
    mana = { max = 100, normal_kill = 3, elite_kill = 15, boss_hit_cap = 35 },
    energy = { max = 100, start = 100, regen_per_second = 20 },
    -- Rage: no passive generation. dealt_rate = rage per second of full-DPS
    -- output (normalised by hero.dps so gear scaling doesn't inflate casts);
    -- received_rate = rage per 100% max-HP taken, hard-capped per wave so
    -- face-tanking is never the optimal generator.
    rage = { max = 100, start = 0, dealt_rate = 9.0, received_rate = 40.0,
        received_cap_per_wave = 30 },
    flask = { charges = 6, health_allocation = 4, heal_fraction = 0.40,
        invulnerability = 2.0, mana = 40, drink_time = 0.70, lock_time = 2.0,
        move_mult = 0.45, interrupt_hp_fraction = 0.10,
        -- Melee sustain identity: landing blows refills flask charges (fraction
        -- of a charge per dps-second dealt, same normalisation as rage) and the
        -- committed drink is half as long.
        melee_refill_rate = 0.02, melee_drink_mult = 0.5 },
    load = {
        max = 100, dash_duration = 0.20,
        light = { max_weight = 30, speed_mult = 1.10, charges = 2, recharge = 3.0,
            distance = 3.5, invulnerability = 0.25, guard = 0.0, poise = 0.0 },
        normal = { max_weight = 70, speed_mult = 1.0, charges = 1, recharge = 4.0,
            distance = 3.0, invulnerability = 0.20, guard = 0.0, poise = 0.0 },
        heavy = { speed_mult = 0.85, charges = 1, recharge = 5.0,
            distance = 2.2, invulnerability = 0.0, guard = 0.50, poise = 0.50 },
    },
    enemy = { elite_hp_mult = 2.6, elite_dps_mult = 1.4,
        bite_windup = 0.4, bite_cooldown = 0.8, bite_grace = 0.35, shot_windup = 0.4,
        elite_base_chance = 0.03, elite_wave_chance = 0.012 },
    boss = { armored_damage_mult = 0.60, armor_break_seconds = 5.0,
        phase2 = { hp_fraction = 0.50, cooldown_mult = 0.65, summon_mult = 0.70 } },
    economy = {
        gold_per_kill = 1, drop_every = 25,
        store_prices = { common = 50, uncommon = 150, rare = 400, epic = 1000, legendary = 2500 },
    },
    arena = {
        spawn = { interval_start = 0.60, interval_min = 0.20, batch_start = 3,
            batch_max = 10, cap_start = 44, cap_max = 85, brute_after = 26.0 },
        -- Covers the deepest map's 10 waves; maps VI+ used to fall off this
        -- table onto the flat reserve_start+40/wave fallback, so wave 8 had
        -- ~35% LESS budget than wave 7 right before the boss.
        wave_budgets = { 130, 173, 230, 302, 389, 500, 640, 815, 1025, 1280 },
        reserve_start = 130.0, creep_hp_mult = 1.56,
    },
}

Balance.benchmarks = { single_targets = 1, pack_targets = 5, horde_targets = 10,
    -- Resource-throughput assumptions: seconds of real fighting per wave, the
    -- melee hero's damage uptime, and the average threat cost of a wave-budget
    -- kill (feeds mana-per-kill income).
    wave_seconds = 40.0, melee_uptime = 0.65, avg_threat_cost = 2.0 }

Balance.gearsets = {
    mid = { "iron_helm", "husk_plate", "sprint_greaves", "gauntlets", "cleaver", "moss_locket" },
    top = { "gourd_visor", "royal_carapace", "plated_greaves", "duelist_gloves", "twin_blades", "crit_ring" },
}

Balance.draft_cards = {
    { id = "universal_offense", rank_id = "offense", name = "Relentless Assault",
      rarity = "universal", tags = { "Damage", "Attack Speed" },
      desc = "+10% damage and attack speed per rank.",
      effect = { upgrade_rank = "offense", dps_mult = 1.10, fire_interval_mult = 1.0 / 1.10 } },
    { id = "universal_defense", rank_id = "defense", name = "Iron Constitution",
      rarity = "universal", tags = { "Health", "Armor" },
      desc = "+20 max health and +3% armor per rank.",
      effect = { upgrade_rank = "defense", hp_max_add = 20.0, armor_add = 0.03 } },
    { id = "universal_projectiles", rank_id = "projectiles", name = "Extra Projectile",
      rarity = "universal", tags = { "Projectiles" }, desc = "+1 projectile per rank.",
      effect = { upgrade_rank = "projectiles", cleave_add = 1 } },
}

-- Spells are gone. Ranked specialization riders spend the class resource only
-- when a basic hit lands. Spread riders use half the damage coefficient of the
-- equivalent local rider by design.
Balance.skills = {}
Balance.on_hit = { tick = 0.5, duration = 4.0, spread_radius = 4.0,
    spread_damage_mult = 0.5 }

Balance.classes = {
    {
        id = "ranger", name = "Ranger", attack = "ranged", hit = "single_projectile",
        blurb = "Long-range bolts. Pick the swarm off from afar.",
        accent = { 0.96, 0.84, 0.36, 0.95 }, hp_max = 115.0, dps = 25.0,
        cleave = 3, attack_range = 9.0, fire_interval = 0.26, speed = 8.5, kite_speed = 8.5,
        sprite_texture = "Textures/modes/arena/hero_ranger.png",
        bolt_color = { 1.0, 0.90, 0.42 }, bolt_scale = 0.34,
        progressive_specializations = true,
        specializations = {
            { id = "poison", name = "Poison Arrows", short = "P", tags = { "Poison", "Spread" },
              icon = "Textures/modes/arena/specs/poison.png",
              desc = "Hits poison immediately and over time; spreads on death at 50% damage.",
              accent = { 0.42, 0.92, 0.28, 0.95 }, kind = "dot", status = "poison", cost = 2,
              initial_per_rank = 0.10, tick_per_rank = 0.10, spread = true },
            { id = "bleed", name = "Bleed Arrows", short = "B", tags = { "Hemorrhage" },
              icon = "Textures/modes/arena/specs/bleed.png",
              desc = "Hits stack Hemorrhage five times: 20/40/60/80/100% hit damage at rank 1.",
              accent = { 0.95, 0.14, 0.20, 0.95 }, kind = "stack_dot", status = "bleed", cost = 2,
              stack_base = 0.20, stack_rank_add = 0.10, max_stacks = 5 },
            { id = "piercing", name = "Piercing Arrows", short = "I", tags = { "Pierce" },
              icon = "Textures/modes/arena/specs/ranger_piercing.png",
              desc = "Arrows pierce for 60% hit damage and carry every on-hit effect.",
              accent = { 0.96, 0.84, 0.36, 0.95 }, kind = "pierce", status = "pierce", cost = 1,
              damage = 0.60, damage_per_rank = 0.10 },
        },
    },
    {
        id = "brawler", name = "Brawler", attack = "melee", hit = "aoe_cleave", resource = "rage",
        blurb = "Wide cleave plus an orbiting spin. Armored for close combat.",
        accent = { 0.92, 0.42, 0.34, 0.95 }, hp_max = 190.0, dps = 60.0,
        cleave = 8, attack_range = 5.0, speed = 9.0, kite_speed = 9.0,
        armor = 0.15, lifesteal = 0.5, regen = 1.5, whirl = 1,
        sprite_texture = "Textures/modes/arena/hero_brawler.png",
        progressive_specializations = true,
        specializations = {
            { id = "bleed", name = "Bleed", short = "B", tags = { "Hemorrhage" },
              icon = "Textures/modes/arena/specs/bleed.png",
              desc = "Hits stack Hemorrhage five times: 20/40/60/80/100% hit damage per tick.",
              accent = { 0.95, 0.14, 0.20, 0.95 }, kind = "stack_dot", status = "bleed", cost = 2,
              stack_base = 0.20, stack_rank_add = 0.10, max_stacks = 5 },
            { id = "frenzy", name = "Frenzy", short = "F", tags = { "Frenzy" },
              icon = "Textures/modes/arena/specs/brawler_frenzy.png",
              desc = "Hits stack short damage, attack-speed, and movement-speed buffs up to five.",
              accent = { 0.96, 0.55, 0.20, 0.95 }, kind = "frenzy", status = "frenzy", cost = 2,
              stack_per_rank = 0.10, max_stacks = 5, duration = 3.0 },
            { id = "shockwave", name = "Shockwave", short = "S", tags = { "Impact" },
              icon = "Textures/modes/arena/specs/brawler_shockwave.png",
              desc = "A killing hit launches a corpse shockwave into enemies behind it.",
              accent = { 0.92, 0.42, 0.34, 0.95 }, kind = "shockwave", status = "shockwave", cost = 2,
              damage = 0.50, damage_per_rank = 0.10, radius = 3.0 },
        },
    },
    {
        id = "sower", name = "Sower", attack = "ranged", hit = "single_projectile",
        blurb = "Sprays seed-shot at the nearest five. Short range, fast.",
        accent = { 0.54, 0.82, 0.40, 0.95 }, hp_max = 110.0, dps = 22.0,
        cleave = 5, attack_range = 7.0, fire_interval = 0.30, speed = 8.3, kite_speed = 8.3,
        sprite_texture = "Textures/modes/arena/hero_sower.png",
        bolt_color = { 0.66, 0.92, 0.40 }, bolt_scale = 0.30,
        progressive_specializations = true,
        specializations = {
            { id = "explosion", name = "Explosion", short = "X", tags = { "Explosion" },
              icon = "Textures/modes/arena/specs/sower_explosion.png",
              desc = "Hits prime enemies to explode on death. Does not spread.",
              accent = { 0.96, 0.58, 0.18, 0.95 }, kind = "explosion", status = "explosion", cost = 2,
              damage = 0.20, damage_per_rank = 0.10, radius = 3.0 },
            { id = "seed", name = "Seed", short = "S", tags = { "Seed", "Spread" },
              icon = "Textures/modes/arena/specs/sower_seed.png",
              desc = "Hits seed immediate and periodic damage; spreads on death at 50% damage.",
              accent = { 0.54, 0.82, 0.40, 0.95 }, kind = "dot", status = "seed", cost = 2,
              initial_per_rank = 0.10, tick_per_rank = 0.10, spread = true },
            { id = "thorns", name = "Thorns", short = "T", tags = { "Thorns" },
              icon = "Textures/modes/arena/specs/sower_thorns.png",
              desc = "Hits stack Thorns five times: 20/40/60/80/100% hit damage at rank 1.",
              accent = { 0.30, 0.72, 0.32, 0.95 }, kind = "stack_dot", status = "thorns", cost = 2,
              stack_base = 0.20, stack_rank_add = 0.10, max_stacks = 5 },
        },
    },
    {
        id = "mage", name = "Mage", attack = "ranged", hit = "single_projectile",
        blurb = "Elemental on-hit effects reshape every basic projectile.",
        accent = { 0.58, 0.48, 1.0, 0.95 }, hp_max = 118.0, dps = 24.0,
        cleave = 2, attack_range = 8.0, fire_interval = 0.28, speed = 8.2, kite_speed = 8.2,
        sprite_texture = "Textures/modes/arena/hero_mage.png",
        bolt_color = { 0.68, 0.58, 1.0 }, bolt_scale = 0.34,
        progressive_specializations = true,
        specializations = {
            { id = "fire", name = "Pyromancer", short = "F", tags = { "Burn" },
              icon = "Textures/modes/arena/specs/mage_fire.png",
              desc = "Hits burn immediately and over time; spreads on death at 50% damage.",
              -- 0.14/rank (vs the 0.10 poison/seed baseline): the elemental
              -- class runs the lowest base dps, so its signature burn carries.
              accent = { 1.0, 0.30, 0.10, 0.95 }, kind = "dot", status = "fire", cost = 2,
              initial_per_rank = 0.14, tick_per_rank = 0.14, spread = true },
            { id = "frost", name = "Cryomancer", short = "F", tags = { "Frost", "Slow" },
              icon = "Textures/modes/arena/specs/mage_frost.png",
              desc = "Hits deal Frost damage and slow enemy movement and attack speed.",
              accent = { 0.35, 0.78, 1.0, 0.95 }, kind = "frost", status = "frost", cost = 2,
              damage_per_rank = 0.20, slow_per_rank = 0.12, duration = 3.0 },
            { id = "earth", name = "Geomancer", short = "G", tags = { "Armor", "Poise" },
              icon = "Textures/modes/arena/specs/mage_earth.png",
              desc = "Projectiles pierce in a small cone and carry every on-hit effect.",
              accent = { 0.72, 0.46, 0.20, 0.95 }, kind = "pierce", status = "earth", cost = 1,
              damage = 0.55, damage_per_rank = 0.10 },
        },
    },
    {
        id = "rogue", name = "Rogue", attack = "ranged", hit = "single_projectile", resource = "energy",
        blurb = "Fast short-range daggers. Energy regenerates constantly.",
        accent = { 0.62, 0.24, 0.72, 0.95 }, hp_max = 102.0, dps = 27.0,
        cleave = 2, attack_range = 6.5, fire_interval = 0.22, speed = 9.5, kite_speed = 9.5,
        sprite_texture = "Textures/modes/arena/hero_rogue.png",
        bolt_color = { 0.72, 0.30, 0.82 }, bolt_scale = 0.27,
        progressive_specializations = true,
        specializations = {
            { id = "shadow", name = "Shadowdancer", short = "S", tags = { "Dodge", "Energy" },
              icon = "Textures/modes/arena/specs/rogue_shadow.png",
              desc = "Hits deal pure damage and apply Smoke, giving enemies a miss chance.",
              accent = { 0.48, 0.38, 0.88, 0.95 }, kind = "shadow", status = "shadow", cost = 2,
              damage_per_rank = 0.15, miss_per_rank = 0.08, duration = 3.0 },
            { id = "poison", name = "Poison", short = "P", tags = { "Poison", "Spread" },
              icon = "Textures/modes/arena/specs/poison.png",
              desc = "Hits poison immediately and over time; spreads on death at 50% damage.",
              accent = { 0.42, 0.92, 0.28, 0.95 }, kind = "dot", status = "poison", cost = 2,
              initial_per_rank = 0.10, tick_per_rank = 0.10, spread = true },
            { id = "daggers", name = "Daggers", short = "D", tags = { "Pierce" },
              icon = "Textures/modes/arena/specs/rogue_daggers.png",
              desc = "Thrown daggers pierce for 60% hit damage and carry on-hit effects.",
              accent = { 0.72, 0.30, 0.82, 0.95 }, kind = "pierce", status = "daggers", cost = 1,
              damage = 0.60, damage_per_rank = 0.10 },
        },
    },
    {
        id = "warrior", name = "Warrior", attack = "melee", hit = "aoe_cleave", resource = "rage",
        blurb = "Iron line-holder. Rage fuels punishing on-hit effects and guard.",
        accent = { 0.85, 0.32, 0.22, 0.95 }, hp_max = 175.0, dps = 54.0,
        cleave = 6, attack_range = 4.6, speed = 8.8, kite_speed = 8.8,
        armor = 0.18, regen = 1.0,
        sprite_texture = "Textures/modes/arena/hero_warrior.png",
        progressive_specializations = true,
        specializations = {
            { id = "bleed", name = "Lacerator", short = "L", tags = { "Bleed" },
              icon = "Textures/modes/arena/specs/bleed.png",
              desc = "Hits stack Hemorrhage five times: 20/40/60/80/100% hit damage per tick.",
              accent = { 0.95, 0.20, 0.22, 0.95 }, kind = "stack_dot", status = "bleed", cost = 2,
              stack_base = 0.20, stack_rank_add = 0.10, max_stacks = 5 },
            { id = "daze", name = "Daze", short = "D", tags = { "Daze" },
              icon = "Textures/modes/arena/specs/warrior_daze.png",
              desc = "Hits reduce enemy damage, attack speed, and movement speed.",
              accent = { 0.92, 0.78, 0.30, 0.95 }, kind = "daze", status = "daze", cost = 2,
              reduction_per_rank = 0.10, duration = 3.0 },
            { id = "preservation", name = "Preservation", short = "P", tags = { "Guard", "Regen" },
              icon = "Textures/modes/arena/specs/preservation.png",
              desc = "Taking damage briefly reduces damage and regenerates a share of maximum health.",
              accent = { 0.55, 0.70, 0.95, 0.95 }, kind = "preservation", status = "preservation", cost = 0,
              damage_reduction_per_rank = 0.10, heal_fraction_per_rank = 0.05, heal_seconds = 5.0 },
        },
    },
    {
        id = "necromancer", name = "Necromancer", attack = "ranged", hit = "single_projectile",
        blurb = "Frail speaker for the dead. Marked kills grow a skeleton-mage pack.",
        accent = { 0.48, 0.85, 0.55, 0.95 }, hp_max = 112.0, dps = 24.0,
        cleave = 2, attack_range = 8.0, fire_interval = 0.30, speed = 8.2, kite_speed = 8.2,
        sprite_texture = "Textures/modes/arena/hero_necromancer.png",
        bolt_color = { 0.55, 0.95, 0.62 }, bolt_scale = 0.30,
        progressive_specializations = true,
        specializations = {
            { id = "curse", name = "Curseweaver", short = "C", tags = { "Curse" },
              icon = "Textures/modes/arena/specs/necromancer_curse.png",
              desc = "Hits curse for damage; spreads on death at 50% damage.",
              accent = { 0.72, 0.30, 0.95, 0.95 }, kind = "dot", status = "curse", cost = 2,
              initial_per_rank = 0.40, tick_per_rank = 0.40, spread = true },
            { id = "vampirism", name = "Vampirism", short = "V", tags = { "Lifesteal" },
              icon = "Textures/modes/arena/specs/necromancer_vampirism.png",
              desc = "Hits deal immediate and periodic damage and heal for half that damage.",
              accent = { 0.88, 0.18, 0.42, 0.95 }, kind = "vampirism", status = "vampirism", cost = 2,
              initial_per_rank = 0.20, tick_per_rank = 0.20, lifesteal_mult = 0.50 },
            { id = "summoner", name = "Summoner", short = "S", tags = { "Summon" },
              icon = "Textures/modes/arena/specs/necromancer_summoner.png",
              desc = "Marked kills raise skeleton mages; starts at two, +1 maximum per rank.",
              accent = { 0.88, 0.90, 0.78, 0.95 }, kind = "summon", status = "revive", cost = 2,
              cap_base = 2, cap_per_rank = 1 },
        },
    },
}

-- Necromancer assistants. Stats scale off the LIVE hero (hp_mult of hero max HP,
-- dps_mult of hero DPS) so gear and map depth carry the pack; caps live on the
-- specialization rows above (cap_base + cap_per_rank, hard-clamped by cap_max here).
Balance.minions = {
    skeleton = { kind = "ranged", hp_mult = 0.55, dps_mult = 0.50, range = 6.0,
        speed = 7.2, attack_interval = 0.8, duration = 30.0, cap_max = 6,
        color = { 0.86, 0.92, 0.78 }, scale = 1.0,
        bolt_color = { 0.62, 0.95, 0.72 }, bolt_scale = 0.22,
        texture = "Textures/modes/arena/minion_skeleton.png" },
    imp = { kind = "ranged", hp_mult = 0.28, dps_mult = 0.35, range = 6.0,
        speed = 7.6, attack_interval = 0.9, duration = 15.0, cap_max = 3,
        color = { 0.95, 0.45, 0.22 }, scale = 0.85,
        bolt_color = { 1.0, 0.55, 0.25 }, bolt_scale = 0.22,
        texture = "Textures/modes/arena/minion_imp.png" },
}

-- Every class offers its three on-hit specializations beside the three shared
-- universal upgrades. Class specializations cap at rank 5.
Balance.specialization_cards = {}
for _, class in ipairs(Balance.classes) do
    if class.progressive_specializations then
        local cards = {}
        for _, spec in ipairs(class.specializations or {}) do
            cards[#cards + 1] = {
                id = class.id .. "_spec_" .. spec.id,
                name = spec.name,
                rarity = "specialization",
                tags = spec.tags,
                desc = spec.desc,
                class_id = class.id,
                specialization = spec.id,
                max_rank = 5,
                accent = spec.accent,
                effect = { specialization_rank = spec.id },
            }
        end
        Balance.specialization_cards[class.id] = cards
    end
end

-- `base` inherits art/behaviour fields from the spud cast or another database
-- entry. Every arena override keeps its live HP and damage knobs here.
Balance.monsters = {
    sprout = { base = "sprout", name = "Sprout", threat_cost = 1, hp = 6, dps = 2.2, range = 0.35, speed = 4.2 },
    seed_spitter = { base = "seed_spitter", name = "Seed Spitter", threat_cost = 3, hp = 13, dps = 2.6,
        range = 4.5, hold_range = 4.8, speed = 2.2, tactical_role = "ranged",
        projectile = { kind = "seed", speed = 15.0, cooldown = 1.15, start_y = 0.7, target_y = 0.55,
            scale = { 0.18, 0.18, 0.18 }, particle_size = 0.20, color = { 0.98, 0.86, 0.30 },
            emissive = 1.3, hit_radius = 0.7, gravity = 0.0 } },
    husk_knight = { base = "husk_knight", name = "Husk Knight", threat_cost = 4, hp = 34, dps = 6.5,
        range = 0.6, speed = 3.0, knockback_resist = 0.45 },
    pumpkin_brute = { base = "pumpkin_brute", name = "Pumpkin Brute", threat_cost = 6, hp = 74, dps = 9.0,
        range = 0.7, speed = 2.2, knockback_resist = 0.75, split_into = { archetype = "sprout", count = 3 } },
    crow = { base = "crow", name = "Crow", threat_cost = 2, hp = 8, dps = 3.0, range = 0.4, speed = 5.0 },
    beetle = { base = "beetle", name = "Spud Beetle", threat_cost = 2, hp = 20, dps = 3.2, range = 0.6, speed = 2.6 },
    corn_mortar = { base = "corn_mortar", name = "Corn Mortar", threat_cost = 3, hp = 12, dps = 3.0,
        range = 7.5, hold_range = 7.5, speed = 0.9, anchor_hold = true, needs_los = true,
        los_reposition_seconds = 2.0, tactical_role = "ranged",
        projectile = { kind = "cob", speed = 9.0, cooldown = 1.9, start_y = 0.9, target_y = 0.55,
            scale = { 0.30, 0.30, 0.30 }, particle_size = 0.30, color = { 0.98, 0.80, 0.32 },
            emissive = 1.1, hit_radius = 0.9, gravity = 0.0 } },
    wasp = { base = "wasp", name = "Garden Wasp", threat_cost = 2, hp = 7, dps = 2.4,
        range = 5.0, hold_range = 5.0, speed = 5.2, anchor_hold = true, needs_los = true,
        los_reposition_seconds = 1.5, tactical_role = "ranged",
        projectile = { kind = "sting", speed = 18.0, cooldown = 0.9, start_y = 1.0, target_y = 0.6,
            scale = { 0.12, 0.12, 0.12 }, particle_size = 0.14, color = { 0.95, 0.86, 0.30 },
            emissive = 1.2, hit_radius = 0.55, gravity = 0.0 } },
    blast_bud = { base = "sprout", name = "Blast Bud", threat_cost = 2, hp = 9, dps = 1.0, range = 0.4,
        speed = 4.6, tint = { 1.5, 0.55, 0.35 }, tactical_role = "bomb",
        explode = { trigger = 2.6, fuse = 0.8, radius = 2.6, damage = 24.0, fuse_speed_mult = 1.35 } },
    ram_beetle = { base = "beetle", name = "Ram Beetle", threat_cost = 3, hp = 26, dps = 9.0, range = 0.6,
        speed = 2.3, knockback_resist = 0.6, tint = { 1.6, 0.55, 0.55 }, tactical_role = "charger",
        charge = { trigger = 8.0, windup = 0.55, mult = 3.4, duration = 0.85, cooldown = 3.2, dmg_mult = 1.8 } },
    -- First boss: onboarding fight. 4400 hp made it a 100-140s naked DPS race
    -- for low-dps classes — effectively HARDER than the geared map II/III bosses.
    gourd_king = { base = "pumpkin_brute", name = "Gourd King", threat_cost = 20, hp = 3000, dps = 26.0,
        range = 1.1, speed = 2.7, scale = 2.2, knockback_resist = 1.0, boss = true, tint = { 1.35, 1.1, 0.55 },
        charge = { trigger = 11.0, windup = 0.8, mult = 3.0, duration = 1.1, cooldown = 4.5, dmg_mult = 2.0 },
        summon_archetype = "sprout", summon_every = 4.5,
        boss_arc = { windup = 0.8, radius = 5.5, range = 7.5, damage = 32.0, cooldown = 5.0, rest = 1.25 },
        unset = { "split_into" } },
    thorn_guard = { base = "husk_knight", name = "Thorn Guard", threat_cost = 5, hp = 58, dps = 8.0,
        speed = 2.1, knockback_resist = 0.85, tint = { 0.55, 1.15, 0.52 }, tactical_role = "guard" },
    spore_witch = { base = "seed_spitter", name = "Spore Witch", threat_cost = 4, hp = 20, dps = 5.0,
        range = 6.5, hold_range = 6.5, speed = 2.7, tint = { 0.90, 0.55, 1.30 }, tactical_role = "ranged",
        projectile = { kind = "spore", speed = 12.0, cooldown = 0.72, start_y = 0.8, target_y = 0.55,
            scale = { 0.22, 0.22, 0.22 }, particle_size = 0.22, color = { 0.78, 0.42, 1.0 },
            emissive = 1.5, hit_radius = 0.72, gravity = 0.0 } },
    brood_pod = { base = "pumpkin_brute", name = "Brood Pod", threat_cost = 6, hp = 52, dps = 3.0,
        speed = 1.8, scale = 1.25, knockback_resist = 0.65, tint = { 0.72, 0.48, 1.20 },
        tactical_role = "summoner", split_into = { archetype = "wasp", count = 3 } },
    stinger_drone = { base = "crow", name = "Stinger Drone", threat_cost = 1, hp = 10, dps = 3.4,
        range = 0.45, speed = 5.4, tint = { 0.55, 1.05, 1.25 } },
    hive_matron = { base = "pumpkin_brute", name = "Hive Matron", threat_cost = 7, hp = 95, dps = 6.0,
        range = 0.9, speed = 1.3, knockback_resist = 0.8, tint = { 1.35, 1.05, 0.45 },
        tactical_role = "summoner", summon_archetype = "wasp", summon_every = 5.0, unset = { "split_into" } },
    bomber_beetle = { base = "beetle", name = "Bomber Beetle", threat_cost = 4, hp = 30, dps = 3.0,
        range = 0.6, speed = 2.6, knockback_resist = 0.5, tint = { 1.45, 0.85, 0.30 }, tactical_role = "bomb",
        charge = { trigger = 8.5, windup = 0.5, mult = 3.0, duration = 0.8, cooldown = 3.6, dmg_mult = 1.5 },
        explode = { trigger = 2.4, fuse = 0.8, radius = 2.8, damage = 30.0, fuse_speed_mult = 1.3 } },
    wasp_queen = { base = "wasp", name = "Wasp Queen", threat_cost = 20, hp = 2840, dps = 24.0,
        range = 1.2, speed = 3.4, scale = 2.3, knockback_resist = 1.0, boss = true, tint = { 1.30, 0.85, 1.35 },
        charge = { trigger = 12.0, windup = 0.7, mult = 3.6, duration = 1.0, cooldown = 3.8, dmg_mult = 1.9 },
        summon_archetype = "stinger_drone", summon_every = 4.0,
        boss_arc = { windup = 0.8, radius = 5.5, range = 8.0, damage = 30.0, cooldown = 4.8, rest = 1.2 },
        unset = { "hold_range", "anchor_hold", "needs_los", "projectile", "tactical_role", "split_into" } },
    royal_guard = { base = "husk_knight", name = "Royal Guard", threat_cost = 6, hp = 85, dps = 11.0,
        range = 0.95, speed = 1.9, knockback_resist = 0.9, tint = { 0.75, 0.90, 1.40 }, tactical_role = "guard",
        charge = { trigger = 9.0, windup = 0.6, mult = 3.2, duration = 0.8, cooldown = 4.0, dmg_mult = 1.7 } },
    corn_arbalest = { base = "corn_mortar", name = "Corn Arbalest", threat_cost = 4, hp = 26, dps = 5.5,
        range = 9.0, speed = 1.4, hold_range = 9.0, tint = { 0.70, 0.95, 1.35 }, tactical_role = "ranged",
        projectile = { kind = "quarrel", speed = 22.0, cooldown = 1.6, start_y = 0.9, target_y = 0.55,
            scale = { 0.14, 0.14, 0.52 }, particle_size = 0.18, color = { 0.62, 0.86, 1.0 },
            emissive = 1.6, hit_radius = 0.6, gravity = 0.0 } },
    gourd_sapper = { base = "pumpkin_brute", name = "Gourd Sapper", threat_cost = 5, hp = 46, dps = 3.0,
        range = 0.7, speed = 2.4, knockback_resist = 0.6, tint = { 1.10, 0.55, 1.35 }, tactical_role = "bomb",
        explode = { trigger = 2.8, fuse = 0.8, radius = 3.2, damage = 36.0, fuse_speed_mult = 1.35 },
        split_into = { archetype = "sprout", count = 3 } },
    corn_colossus = { base = "corn_mortar", name = "Corn Colossus", threat_cost = 20, hp = 1835, dps = 30.0,
        range = 1.3, speed = 2.2, scale = 2.6, knockback_resist = 1.0, boss = true, tint = { 1.40, 1.15, 0.50 },
        hold_range = 8.0, anchor_hold = true, needs_los = true, los_reposition_seconds = 1.5,
        projectile = { kind = "boulder_cob", speed = 11.0, cooldown = 1.3, start_y = 1.4, target_y = 0.55,
            scale = { 0.42, 0.42, 0.42 }, particle_size = 0.38, color = { 1.0, 0.78, 0.30 },
            emissive = 1.4, hit_radius = 1.05, gravity = 0.0, pulse = true },
        charge = { trigger = 7.0, windup = 0.8, mult = 3.0, duration = 1.0, cooldown = 5.0, dmg_mult = 1.8 },
        summon_archetype = "husk_knight", summon_every = 6.0,
        boss_arc = { windup = 0.8, radius = 6.0, range = 8.0, damage = 36.0, cooldown = 5.2, rest = 1.35 },
        unset = { "tactical_role" } },
    flask_hunter = { base = "ram_beetle", name = "Flask Hunter", threat_cost = 4, hp = 34, dps = 10.0,
        speed = 3.0, tint = { 0.45, 0.95, 1.35 }, tactical_role = "hunter", flask_hunter = true,
        charge = { trigger = 12.0, windup = 0.45, mult = 3.8, duration = 0.9, cooldown = 4.0, dmg_mult = 1.7 } },
    briar_hound = { base = "crow", name = "Briar Hound", threat_cost = 2, hp = 16, dps = 5.0,
        range = 0.5, speed = 5.4, tint = { 0.55, 0.95, 0.40 }, tactical_role = "charger",
        charge = { trigger = 6.0, windup = 0.4, mult = 2.8, duration = 0.5, cooldown = 2.6, dmg_mult = 1.4 } },
    mill_wraith = { base = "spore_witch", name = "Mill Wraith", threat_cost = 5, hp = 26, dps = 6.0,
        range = 7.0, hold_range = 7.0, speed = 2.9, tint = { 1.05, 1.05, 1.15 }, tactical_role = "ranged",
        projectile = { kind = "chaff", speed = 16.0, cooldown = 0.6, start_y = 0.8, target_y = 0.55,
            scale = { 0.20, 0.20, 0.20 }, particle_size = 0.20, color = { 0.92, 0.94, 1.0 },
            emissive = 1.6, hit_radius = 0.7, gravity = 0.0 } },
    harvest_reaper = { base = "husk_knight", name = "Harvest Reaper", threat_cost = 7, hp = 90, dps = 14.0,
        range = 0.8, speed = 2.6, knockback_resist = 0.9, tint = { 0.95, 0.45, 0.35 }, tactical_role = "guard" },
    carrion_flock = { base = "beetle", name = "Carrion Flock", threat_cost = 6, hp = 55, dps = 5.0,
        range = 0.6, speed = 3.2, tint = { 0.50, 0.46, 0.62 }, split_into = { archetype = "crow", count = 4 } },
    root_horror = { base = "brood_pod", name = "Root Horror", threat_cost = 9, hp = 130, dps = 8.0,
        speed = 1.6, scale = 1.4, knockback_resist = 0.85, tint = { 0.50, 0.85, 0.45 },
        tactical_role = "summoner", summon_archetype = "beetle", summon_every = 4.0, unset = { "split_into" } },
    royal_sentinel = { base = "royal_guard", name = "Royal Sentinel", threat_cost = 10, hp = 170, dps = 16.0,
        range = 0.8, speed = 2.4, knockback_resist = 1.0, tint = { 1.10, 0.98, 0.55 },
        charge = { trigger = 9.0, windup = 0.6, mult = 3.2, duration = 0.9, cooldown = 3.4, dmg_mult = 1.8 } },
}

Balance.items = {
    -- helmet
    { id = "straw_hat", slot = "helmet", rarity = "common", name = "Straw Hat", weight = 4,
      desc = "+18 HP", effect = { hp_max_add = 18.0 } },
    { id = "iron_helm", slot = "helmet", rarity = "uncommon", name = "Iron Helm", weight = 18, tags = { "Guard", "Stagger" },
      desc = "+28 HP, +8% armor", effect = { hp_max_add = 28.0, armor_add = 0.08 } },
    { id = "leather_cap", slot = "helmet", rarity = "common", name = "Leather Cap", weight = 6, tags = { "Dodge" },
      desc = "+12 HP, +5% move", effect = { hp_max_add = 12.0, speed_mult = 1.05, kite_speed_mult = 1.05 } },
    { id = "thorn_hood", slot = "helmet", rarity = "uncommon", name = "Thorn Hood", weight = 10,
      desc = "+20 HP, +4 thorns", effect = { hp_max_add = 20.0, thorns_add = 4.0 } },
    { id = "spore_mask", slot = "helmet", rarity = "rare", name = "Spore Mask", weight = 8, tags = { "Mana", "Guard" },
      desc = "+12% armor, +1.5 regen", effect = { armor_add = 0.12, regen_add = 1.5 } },
    { id = "gourd_visor", slot = "helmet", rarity = "epic", name = "Gourd Visor", weight = 20,
      desc = "+60 HP, +18% armor", effect = { hp_max_add = 60.0, armor_add = 0.18 } },
    -- body
    { id = "field_vest", slot = "body", rarity = "common", name = "Field Vest", weight = 12,
      desc = "+30 HP", effect = { hp_max_add = 30.0 } },
    { id = "husk_plate", slot = "body", rarity = "uncommon", name = "Husk Plate", weight = 32, tags = { "Guard", "Stagger" },
      desc = "+55 HP, +12% armor", effect = { hp_max_add = 55.0, armor_add = 0.12 } },
    { id = "patched_coat", slot = "body", rarity = "common", name = "Patched Coat", weight = 14,
      desc = "+22 HP, +0.5 regen", effect = { hp_max_add = 22.0, regen_add = 0.5 } },
    { id = "runner_tunic", slot = "body", rarity = "uncommon", name = "Runner Tunic", weight = 9,
      desc = "+20 HP, +8% move", effect = { hp_max_add = 20.0, speed_mult = 1.08, kite_speed_mult = 1.08 } },
    { id = "thornmail", slot = "body", rarity = "rare", name = "Thornmail", weight = 28,
      desc = "+45 HP, +10% armor, +8 thorns", effect = { hp_max_add = 45.0, armor_add = 0.10, thorns_add = 8.0 } },
    { id = "royal_carapace", slot = "body", rarity = "epic", name = "Royal Carapace", weight = 38,
      desc = "+80 HP, +18% armor", effect = { hp_max_add = 80.0, armor_add = 0.18 } },
    -- pants
    { id = "work_trousers", slot = "pants", rarity = "common", name = "Work Trousers", weight = 8,
      desc = "+10% move", effect = { speed_mult = 1.10, kite_speed_mult = 1.10 } },
    { id = "sprint_greaves", slot = "pants", rarity = "uncommon", name = "Sprint Greaves", weight = 7,
      desc = "+18% move, +12 HP", effect = { speed_mult = 1.18, kite_speed_mult = 1.18, hp_max_add = 12.0 } },
    { id = "mud_boots", slot = "pants", rarity = "common", name = "Mud Boots", weight = 10,
      desc = "+8 HP, +8% move", effect = { hp_max_add = 8.0, speed_mult = 1.08, kite_speed_mult = 1.08 } },
    { id = "wind_leggings", slot = "pants", rarity = "uncommon", name = "Wind Leggings", weight = 6, tags = { "Dodge" },
      desc = "+22% move", effect = { speed_mult = 1.22, kite_speed_mult = 1.22 } },
    { id = "plated_greaves", slot = "pants", rarity = "rare", name = "Plated Greaves", weight = 25, tags = { "Guard", "Stagger" },
      desc = "+35 HP, +10% armor, +5% move", effect = { hp_max_add = 35.0, armor_add = 0.10, speed_mult = 1.05, kite_speed_mult = 1.05 } },
    { id = "phase_steps", slot = "pants", rarity = "epic", name = "Phase Steps", weight = 5, tags = { "Dodge", "Mana" },
      desc = "+20 HP, +30% move", effect = { hp_max_add = 20.0, speed_mult = 1.30, kite_speed_mult = 1.30 } },
    -- gloves
    { id = "garden_gloves", slot = "gloves", rarity = "common", name = "Garden Gloves", weight = 3,
      desc = "+12% attack speed", effect = { fire_interval_mult = 0.88 } },
    { id = "gauntlets", slot = "gloves", rarity = "uncommon", name = "Gauntlets", weight = 14,
      desc = "+4 damage, +6% attack speed", effect = { dps_add = 4.0, fire_interval_mult = 0.94 } },
    { id = "grip_wraps", slot = "gloves", rarity = "common", name = "Grip Wraps", weight = 4,
      desc = "+2 damage", effect = { dps_add = 2.0 } },
    { id = "thorn_grips", slot = "gloves", rarity = "uncommon", name = "Thorn Grips", weight = 8, tags = { "Retaliation", "Orbit" },
      desc = "+3 damage, +4 thorns, retaliation orbit", effect = { dps_add = 3.0, thorns_add = 4.0, retaliation_orbit = 0.5 } },
    { id = "duelist_gloves", slot = "gloves", rarity = "rare", name = "Duelist Gloves", weight = 6, tags = { "Bleed" },
      desc = "+8 damage, +15% attack speed, crit bleed", effect = { dps_add = 8.0, fire_interval_mult = 0.85, bleed_on_crit = 5.0 } },
    { id = "kings_gauntlets", slot = "gloves", rarity = "epic", name = "King's Gauntlets", weight = 18,
      desc = "+12 damage, +25% attack speed", effect = { dps_add = 12.0, fire_interval_mult = 0.75 } },
    -- weapon
    { id = "field_spear", slot = "weapon", rarity = "common", name = "Field Spear",
      desc = "+0.6 reach, +3 damage", effect = { attack_range_add = 0.6, dps_add = 3.0 } },
    { id = "cleaver", slot = "weapon", rarity = "uncommon", name = "Cleaver",
      desc = "+2 cleave, -8% move", effect = { cleave_add = 2, speed_mult = 0.92, kite_speed_mult = 0.92 } },
    { id = "seed_cannon", slot = "weapon", rarity = "rare", name = "Seed Cannon",
      desc = "+1 shot, +2 range, +15% damage", effect = { cleave_add = 1, attack_range_add = 2.0, dps_mult = 1.15 } },
    { id = "pitchfork", slot = "weapon", rarity = "common", name = "Pitchfork",
      desc = "+5 damage, +0.8 reach", effect = { dps_add = 5.0, attack_range_add = 0.8 } },
    { id = "harvest_hammer", slot = "weapon", rarity = "uncommon", name = "Harvest Hammer",
      desc = "+10 damage, -5% move", effect = { dps_add = 10.0, speed_mult = 0.95, kite_speed_mult = 0.95 } },
    { id = "twin_blades", slot = "weapon", rarity = "rare", name = "Twin Blades", tags = { "Cleave", "Bleed" },
      desc = "+10 damage, +3 cleave, crit bleed", effect = { dps_add = 10.0, cleave_add = 3, bleed_on_crit = 7.0 } },
    { id = "sun_reaper", slot = "weapon", rarity = "epic", name = "Sun Reaper", tags = { "Cleave", "Orbit" },
      desc = "+25% damage, +2 cleave, +1 spin", effect = { dps_mult = 1.25, cleave_add = 2, whirl_add = 1 } },
    -- jewelry
    { id = "swift_band", slot = "jewelry", rarity = "common", name = "Swift Band",
      desc = "+12% move, +8 HP", effect = { speed_mult = 1.12, kite_speed_mult = 1.12, hp_max_add = 8.0 } },
    { id = "red_charm", slot = "jewelry", rarity = "uncommon", name = "Red Charm",
      desc = "+1 lifesteal, +10% damage", effect = { lifesteal_add = 1.0, dps_mult = 1.10 } },
    { id = "magnet_charm", slot = "jewelry", rarity = "uncommon", name = "Magnet Charm",
      desc = "+1.4 pickup range, +25% gold", effect = { pickup_range_add = 1.4, gold_find_add = 0.25 } },
    { id = "crit_ring", slot = "jewelry", rarity = "rare", name = "Crit Ring",
      desc = "+30% crit, +5 damage", effect = { crit_add = 0.30, dps_add = 5.0 } },
    { id = "copper_coin", slot = "jewelry", rarity = "common", name = "Copper Coin",
      desc = "+15% gold", effect = { gold_find_add = 0.15 } },
    { id = "moss_locket", slot = "jewelry", rarity = "uncommon", name = "Moss Locket",
      desc = "+15 HP, +1 regen", effect = { hp_max_add = 15.0, regen_add = 1.0 } },
    { id = "vampire_tooth", slot = "jewelry", rarity = "rare", name = "Vampire Tooth",
      desc = "+2 lifesteal, +12% damage", effect = { lifesteal_add = 2.0, dps_mult = 1.12 } },
    { id = "storm_loop", slot = "jewelry", rarity = "epic", name = "Storm Loop", tags = { "Mana", "Orbit" },
      desc = "+20% crit, +15% attack/move, mana burst", effect = { crit_add = 0.20, fire_interval_mult = 0.85, speed_mult = 1.15, kite_speed_mult = 1.15, whirl_add = 1, mana_burst = 0.65 } },
    -- boss-tier (rare pool feeds the Gourd King's shower)
    { id = "kings_crown", slot = "helmet", rarity = "rare", name = "King's Crown", weight = 16,
      desc = "+40 HP, +10% damage, +20% gold", effect = { hp_max_add = 40.0, dps_mult = 1.10, gold_find_add = 0.2 } },
    -- Map II/III expansion — deeper rarity ladders per slot, dodge
    -- synergy pieces, and boss-flavoured epics for the new maps.
    { id = "sentry_visor", slot = "helmet", rarity = "rare", name = "Sentry Visor", weight = 14,
      desc = "+25 HP, +1 cleave", effect = { hp_max_add = 25.0, cleave_add = 1 } },
    { id = "queens_diadem", slot = "helmet", rarity = "epic", name = "Queen's Diadem", weight = 8, tags = { "Mana" },
      desc = "+45 HP, +15% attack speed, +8% move", effect = { hp_max_add = 45.0, fire_interval_mult = 0.85, speed_mult = 1.08, kite_speed_mult = 1.08 } },
    { id = "beetle_shell", slot = "body", rarity = "rare", name = "Beetle Shell", weight = 30,
      desc = "+40 HP, +15% armor", effect = { hp_max_add = 40.0, armor_add = 0.15 } },
    { id = "dancer_garb", slot = "body", rarity = "rare", name = "Dancer's Garb", weight = 6, tags = { "Dodge", "Bleed" },
      desc = "+12% move, +10% crit, dodge blades", effect = { speed_mult = 1.12, kite_speed_mult = 1.12, crit_add = 0.10, dodge_recharge_mult = 0.80, dodge_blades = 0.55 } },
    { id = "queen_carapace", slot = "body", rarity = "epic", name = "Queen's Carapace", weight = 26,
      desc = "+70 HP, +12% armor, +1 regen", effect = { hp_max_add = 70.0, armor_add = 0.12, regen_add = 1.0 } },
    { id = "guard_sabatons", slot = "pants", rarity = "rare", name = "Guard Sabatons", weight = 24,
      desc = "+30 HP, +8% armor, +6 thorns", effect = { hp_max_add = 30.0, armor_add = 0.08, thorns_add = 6.0 } },
    { id = "zephyr_boots", slot = "pants", rarity = "epic", name = "Zephyr Boots", weight = 6,
      desc = "+20% move, dodge 25% faster", effect = { speed_mult = 1.20, kite_speed_mult = 1.20, dodge_recharge_mult = 0.75 } },
    { id = "leech_wraps", slot = "gloves", rarity = "rare", name = "Leech Wraps", weight = 7,
      desc = "+1.5 lifesteal, +4 damage", effect = { lifesteal_add = 1.5, dps_add = 4.0 } },
    { id = "colossus_fists", slot = "gloves", rarity = "epic", name = "Colossus Fists", weight = 22, tags = { "Guard", "Retaliation" },
      desc = "+18 damage, +10% armor, retaliation orbit", effect = { dps_add = 18.0, armor_add = 0.10, retaliation_orbit = 0.8 } },
    { id = "sting_lance", slot = "weapon", rarity = "rare", name = "Sting Lance", weight = 12,
      desc = "+8 damage, +1.2 reach, +10% attack speed", effect = { dps_add = 8.0, attack_range_add = 1.2, fire_interval_mult = 0.90 } },
    { id = "whirl_scythe", slot = "weapon", rarity = "rare", name = "Whirl Scythe", weight = 18,
      desc = "+1 spin, +6 damage", effect = { whirl_add = 1, dps_add = 6.0 } },
    { id = "royal_halberd", slot = "weapon", rarity = "epic", name = "Royal Halberd", weight = 30,
      desc = "+14 damage, +2 cleave, +1.5 reach", effect = { dps_add = 14.0, cleave_add = 2, attack_range_add = 1.5 } },
    { id = "lucky_clover", slot = "jewelry", rarity = "common", name = "Lucky Clover", weight = 0,
      desc = "+10% gold, +6 HP", effect = { gold_find_add = 0.10, hp_max_add = 6.0 } },
    { id = "dodge_band", slot = "jewelry", rarity = "uncommon", name = "Dodge Band", weight = 0,
      desc = "Dodge recharges 20% faster", effect = { dodge_recharge_mult = 0.80 } },
    { id = "hive_locket", slot = "jewelry", rarity = "rare", name = "Hive Locket", weight = 0, tags = { "Mana", "Flask" },
      desc = "+15 HP, +2 regen, mana burst", effect = { hp_max_add = 15.0, regen_add = 2.0, gold_find_add = 0.10, mana_burst = 0.4 } },
    { id = "phase_charm", slot = "jewelry", rarity = "epic", name = "Phase Charm", weight = 0, tags = { "Dodge" },
      desc = "+1 dodge charge", effect = { dodge_charge_add = 1 } },
    { id = "kings_signet", slot = "jewelry", rarity = "epic", name = "King's Signet", weight = 0, tags = { "Flask", "Retaliation" },
      desc = "+25% gold, +12% damage, health nova", effect = { gold_find_add = 0.25, dps_mult = 1.12, flask_nova = 0.6 } },
    -- LEGENDARY (orange) — endgame drops, maps IX+. One per slot,
    -- ~1.6x epic power with a signature effect each.
    { id = "crown_of_ovrevand", slot = "helmet", rarity = "legendary", name = "Crown of Ovrevand", weight = 0, tags = { "Guard", "Mana" },
      desc = "+100 HP, +20% armor, +15% attack speed", effect = { hp_max_add = 100.0, armor_add = 0.20, fire_interval_mult = 0.85 } },
    { id = "kingsguard_plate", slot = "body", rarity = "legendary", name = "Kingsguard Plate", weight = 0, tags = { "Guard", "Retaliation" },
      desc = "+140 HP, +25% armor, +2 regen, +12 thorns", effect = { hp_max_add = 140.0, armor_add = 0.25, regen_add = 2.0, thorns_add = 12.0 } },
    { id = "wyrmstriders", slot = "pants", rarity = "legendary", name = "Wyrmstriders", weight = 0, tags = { "Dodge" },
      desc = "+35% move, +1 dodge, dodge 30% faster", effect = { speed_mult = 1.35, kite_speed_mult = 1.35, dodge_charge_add = 1, dodge_recharge_mult = 0.70 } },
    { id = "reapers_grasp", slot = "gloves", rarity = "legendary", name = "Reaper's Grasp", weight = 0, tags = { "Bleed" },
      desc = "+24 damage, +35% attack speed, +15% crit", effect = { dps_add = 24.0, fire_interval_mult = 0.65, crit_add = 0.15 } },
    { id = "kingmaker", slot = "weapon", rarity = "legendary", name = "Kingmaker", weight = 0, tags = { "Cleave", "Orbit" },
      desc = "+45% damage, +3 cleave, +2 spin, crit bleed", effect = { dps_mult = 1.45, cleave_add = 3, whirl_add = 2, bleed_on_crit = 10.0 } },
    { id = "heart_of_the_hive", slot = "jewelry", rarity = "legendary", name = "Heart of the Hive", weight = 0, tags = { "Mana", "Bleed" },
      desc = "+3 lifesteal, +20% damage, +25% crit, mana burst", effect = { lifesteal_add = 3.0, dps_mult = 1.20, crit_add = 0.25, mana_burst = 0.85 } },
}

function Balance.auto_mix(D)
    local wave = D.wave_index or 1
    local n = D.spawn_counter
    local map = D.map_index or 1
    -- Band newcomers: one new foe every two maps from III on; residues
    -- are distinct so higher bands keep every earlier newcomer too.
    if map >= 13 and n % 6 == 0 then return "royal_sentinel" end
    if map >= 11 and n % 8 == 0 then return "root_horror" end
    if map >= 9 and n % 8 == 1 then return "carrion_flock" end
    if map >= 7 and n % 7 == 0 then return "harvest_reaper" end
    if map >= 5 and n % 7 == 1 then return "mill_wraith" end
    if map >= 3 and n % 6 == 1 then return "briar_hound" end
    if map >= 3 then
        -- ROYAL GARDEN — armored formations, snipers, sappers.
        if wave >= 2 and n % 17 == 0 then return "flask_hunter" end
        if D.combat_time >= D.spawn_cfg.brute_after and (n % 13 == 0) then return "pumpkin_brute" end
        if wave >= 3 and n % 21 == 0 then return "brood_pod" end
        if wave >= 2 and n % 12 == 0 then return "royal_guard" end
        if n % 11 == 0 then return "gourd_sapper" end
        if n % 9 == 0 then return "corn_arbalest" end
        if wave >= 2 and n % 10 == 0 then return "ram_beetle" end
        if n % 7 == 0 then return "spore_witch" end
        if n % 5 == 0 then return "thorn_guard" end
        if n % 3 == 0 then return "husk_knight" end
        if n % 4 == 0 then return "beetle" end
        return "sprout"
    elseif map >= 2 then
        -- HOLLOW HIVE — fast fliers, summoners, bombers.
        if wave >= 2 and n % 17 == 0 then return "flask_hunter" end
        if n % 21 == 0 then return "hive_matron" end
        if wave >= 2 and n % 13 == 0 then return "bomber_beetle" end
        if n % 11 == 0 then return "spore_witch" end
        if wave >= 3 and n % 10 == 0 then return "blast_bud" end
        if wave >= 2 and n % 9 == 0 then return "ram_beetle" end
        if n % 7 == 0 then return "wasp" end
        if n % 6 == 0 then return "corn_mortar" end
        if n % 4 == 0 then return "beetle" end
        if n % 3 == 0 then return "stinger_drone" end
        return "sprout"
    end
    -- SPUD FIELDS — the original curve.
    if wave >= 3 and n % 29 == 0 then return "flask_hunter" end
    if D.combat_time >= D.spawn_cfg.brute_after and (n % 13 == 0) then
        return "pumpkin_brute"
    end
    -- Behaviour enemies phase in as the run deepens: chargers wave 2+,
    -- walking bombs wave 3+.
    if wave >= 4 and n % 23 == 0 then return "brood_pod" end
    if wave >= 3 and n % 19 == 0 then return "spore_witch" end
    if wave >= 2 and n % 17 == 0 then return "thorn_guard" end
    if wave >= 3 and n % 10 == 0 then return "blast_bud" end
    if wave >= 2 and n % 9 == 0 then return "ram_beetle" end
    if n % 11 == 0 then return "corn_mortar" end
    if n % 8 == 0 then return "crow" end
    if n % 7 == 0 then return "wasp" end
    if n % 6 == 0 then return "seed_spitter" end
    if n % 4 == 0 then return "beetle" end
    if n % 3 == 0 then return "husk_knight" end
    return "sprout"
end

Balance.map_progression = {
    rank = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII" },
    waves = { 5, 6, 7, 7, 7, 8, 8, 8, 9, 9, 9, 10, 10 },
    budget_mult = { 1.0, 1.25, 1.55, 1.8, 2.05, 2.3, 2.55, 2.8, 3.05, 3.3, 3.55, 3.8, 4.1 },
    hp_mult = { 1.0, 1.55, 2.4, 3.3, 4.4, 5.8, 7.5, 9.6, 12, 15, 19, 24, 30 },
    dps_mult = { 1.0, 1.45, 2.0, 2.5, 3.1, 3.8, 4.6, 5.5, 6.5, 7.6, 8.8, 10.2, 12.0 },
    gold_mult = { 1.0, 1.8, 3.0, 4.4, 6.2, 8.5, 11.5, 15, 19, 24, 30, 38, 48 },
    elite_bonus = { 0.0, 0.02, 0.04, 0.06, 0.08, 0.10, 0.12, 0.14, 0.16, 0.18, 0.20, 0.22, 0.25 },
    drops = {
        common = { 100, 100, 70, 55, 45, 30, 0, 0, 0, 0, 0, 0, 0 },
        uncommon = { 0, 0, 30, 45, 35, 40, 40, 25, 0, 0, 0, 0, 0 },
        rare = { 0, 0, 0, 0, 20, 30, 40, 45, 0, 0, 0, 0, 0 },
        epic = { 0, 0, 0, 0, 0, 0, 20, 30, 70, 50, 0, 0, 0 },
        legendary = { 0, 0, 0, 0, 0, 0, 0, 0, 30, 50, 100, 100, 100 },
    },
}

function Balance.apply_map_progression(defs)
    local p = Balance.map_progression
    assert(#defs == #p.rank, "map progression count does not match map definitions")
    for i, map in ipairs(defs) do
        map.rank, map.waves = p.rank[i], p.waves[i]
        map.budget_mult, map.hp_mult, map.dps_mult = p.budget_mult[i], p.hp_mult[i], p.dps_mult[i]
        map.gold_mult, map.elite_bonus = p.gold_mult[i], p.elite_bonus[i]
        map.drop_weights = {}
        for rarity, values in pairs(p.drops) do map.drop_weights[rarity] = values[i] end
    end
    return defs
end

function Balance.build_monsters(spud)
    local built, resolving = {}, {}
    local function build(id)
        if built[id] then return built[id] end
        assert(not resolving[id], "balance monster inheritance cycle: " .. tostring(id))
        local def = assert(Balance.monsters[id], "unknown balance monster: " .. tostring(id))
        resolving[id] = true
        local parent = def.base ~= id and Balance.monsters[def.base] and build(def.base)
            or assert(spud[def.base], "unknown monster base: " .. tostring(def.base))
        local out = {}
        for k, v in pairs(parent) do out[k] = v end
        for k, v in pairs(def) do if k ~= "base" and k ~= "unset" then out[k] = v end end
        for _, k in ipairs(def.unset or {}) do out[k] = nil end
        if out.boss and not out.phase2 then out.phase2 = Balance.rules.boss.phase2 end
        resolving[id], built[id] = nil, out
        return out
    end
    for id in pairs(Balance.monsters) do build(id) end
    return built
end

local function class_by_id(id)
    for _, class in ipairs(Balance.classes) do if class.id == id then return class end end
end

function Balance.specialization(class_id, id)
    local class = class_by_id(class_id)
    for _, spec in ipairs(class and class.specializations or {}) do
        if spec.id == id then return spec end
    end
end

function Balance.preservation_effect(rank)
    local spec = assert(Balance.specialization("warrior", "preservation"),
        "missing Warrior Preservation specialization")
    rank = math.max(0, math.floor(rank or 0))
    return math.min(0.50, rank * (spec.damage_reduction_per_rank or 0.10)),
        math.min(0.25, rank * (spec.heal_fraction_per_rank or 0.05)), spec.heal_seconds or 5.0
end

function Balance.specialization_upgrade_text(class_id, id, current_rank)
    local class = assert(class_by_id(class_id), "unknown balance class: " .. tostring(class_id))
    local spec = assert(Balance.specialization(class_id, id),
        "unknown specialization: " .. tostring(class_id) .. ":" .. tostring(id))
    local rank = math.max(1, math.floor(current_rank or 0) + 1)
    local resource = string.upper(class.resource or "mana")
    local cost = string.format("Cost %d %s/%s.", spec.cost or 1, resource,
        spec.kind == "preservation" and "hit taken" or "hit")
    local function pct(value) return tostring(math.floor(value * 100.0 + 0.5)) .. "%" end
    local kind = spec.kind
    if kind == "dot" then
        local spread = spec.spread and Balance.on_hit.spread_damage_mult or 1.0
        return string.format("Next rank: %s hit %s + %s per tick.\n%s  %s",
            spec.name, pct((spec.initial_per_rank or 0.0) * rank * spread),
            pct((spec.tick_per_rank or 0.0) * rank * spread),
            spec.spread and "Spreads on death at half strength." or "Does not spread.", cost)
    elseif kind == "stack_dot" then
        local per_stack = (spec.stack_base or 0.20) + (rank - 1) * (spec.stack_rank_add or 0.10)
        local values = {}
        for stack = 1, spec.max_stacks or 5 do values[#values + 1] = pct(per_stack * stack) end
        return "Next rank: " .. spec.name .. " deals " .. table.concat(values, "/")
            .. " hit damage on hit + per tick at 1-5 stacks.\n" .. cost
    elseif kind == "pierce" then
        local damage = (spec.damage or 0.0) + (rank - 1) * (spec.damage_per_rank or 0.0)
        return string.format("Next rank: piercing hit deals %s hit damage.\nCarries all on-hit effects.  %s",
            pct(damage), cost)
    elseif kind == "frenzy" then
        local per_stack = (spec.stack_per_rank or 0.10) * rank
        return string.format("Next rank: +%s damage, attack speed, and speed per stack; %s at 5 stacks for %.0fs.\n%s",
            pct(per_stack), pct(per_stack * (spec.max_stacks or 5)), spec.duration or 3.0, cost)
    elseif kind == "explosion" or kind == "shockwave" then
        local damage = (spec.damage or 0.0) + (rank - 1) * (spec.damage_per_rank or 0.0)
        return string.format("Next rank: death %s deals %s hit damage in %.1f range.\n%s",
            kind, pct(damage), spec.radius or 3.0, cost)
    elseif kind == "frost" then
        return string.format("Next rank: %s Frost damage; -%s move and attack speed for %.0fs.\n%s",
            pct((spec.damage_per_rank or 0.0) * rank),
            pct(math.min(0.75, (spec.slow_per_rank or 0.0) * rank)), spec.duration or 3.0, cost)
    elseif kind == "shadow" then
        return string.format("Next rank: %s pure damage; Smoke gives %s miss chance for %.0fs.\n%s",
            pct((spec.damage_per_rank or 0.0) * rank),
            pct(math.min(0.75, (spec.miss_per_rank or 0.0) * rank)), spec.duration or 3.0, cost)
    elseif kind == "daze" then
        local reduction = math.min(0.75, (spec.reduction_per_rank or 0.0) * rank)
        return string.format("Next rank: -%s enemy damage, attack speed, and speed for %.0fs.\n%s",
            pct(reduction), spec.duration or 3.0, cost)
    elseif kind == "preservation" then
        local reduction, healing, seconds = Balance.preservation_effect(rank)
        return string.format("Next rank: after taking damage, gain %s damage reduction and restore %s max health over %.0fs.\nCost: 0 Rage.",
            pct(reduction), pct(healing), seconds)
    elseif kind == "vampirism" then
        return string.format("Next rank: %s hit + %s per tick; heals %s from each.\n%s",
            pct((spec.initial_per_rank or 0.0) * rank),
            pct((spec.tick_per_rank or 0.0) * rank),
            pct((spec.tick_per_rank or 0.0) * rank * (spec.lifesteal_mult or 0.0)), cost)
    elseif kind == "summon" then
        local cap = math.min(Balance.minions.skeleton.cap_max,
            (spec.cap_base or 2) + (rank - 1) * (spec.cap_per_rank or 1))
        return string.format("Next rank: skeleton-mage cap %d; each deals %s hit damage and inherits statuses.\n%s; free while capped.",
            cap, pct(Balance.minions.skeleton.dps_mult), cost)
    end
    return spec.desc .. "\n" .. cost
end

function Balance.universal_upgrade_text(card, current_rank)
    local rank = math.max(0, math.floor(current_rank or 0)) + 1
    if card.rank_id == "offense" then
        local total = (card.effect.dps_mult or 1.0) ^ rank
        return string.format("Next rank: +10%% damage and attack speed.\nTotal from cards: +%d%% each.",
            math.floor((total - 1.0) * 100.0 + 0.5))
    elseif card.rank_id == "defense" then
        return string.format("Next rank: +20 max health and +3%% armor.\nTotal from cards: +%d health, +%d%% armor.",
            20 * rank, 3 * rank)
    elseif card.rank_id == "projectiles" then
        return string.format("Next rank: +1 projectile.\nTotal from cards: +%d projectiles.", rank)
    end
    return card.desc or ""
end

function Balance.basic_metrics(class_id, targets)
    local class = assert(class_by_id(class_id), "unknown balance class: " .. tostring(class_id))
    targets = math.max(1, math.floor(targets or Balance.benchmarks.pack_targets))
    local hits = math.min(targets, class.cleave or 1)
    local primary_single, primary_total
    if class.attack == "ranged" then
        primary_single = class.dps * Balance.rules.basic_attack.ranged_damage_mult / class.fire_interval
        primary_total = primary_single * hits
    else
        primary_single = class.dps
        primary_total = primary_single
            * (1.0 + math.max(0, hits - 1) * Balance.rules.basic_attack.melee_secondary_mult)
    end
    local innate_aoe_dps = (class.whirl or 0) * class.dps
        * (class.attack == "melee" and Balance.rules.whirl.melee_damage_mult
            / Balance.rules.whirl.melee_cooldown
            or Balance.rules.whirl.ranged_damage_mult / Balance.rules.whirl.cooldown)
    return { primary_single_dps = primary_single, primary_total_dps = primary_total,
        innate_aoe_dps = innate_aoe_dps,
        single_dps = primary_single + innate_aoe_dps,
        total_dps = primary_total + innate_aoe_dps * targets,
        targets_hit = hits,
        effective_hp = class.hp_max / math.max(0.01, 1.0 - (class.armor or 0.0)) }
end

function Balance.skill_metrics(class_id, specialization, targets, round, rank)
    local class = assert(class_by_id(class_id), "unknown balance class: " .. tostring(class_id))
    local skill = Balance.skills[class_id]
    if skill and not skill.id then skill = skill[specialization] end
    assert(skill, "unknown balance skill for " .. tostring(class_id) .. ":" .. tostring(specialization))
    targets = math.max(1, math.floor(targets or Balance.benchmarks.pack_targets))
    round = math.max(1, math.floor(round or 1))
    rank = math.max(1, math.floor(rank or 1))
    local effects = skill.effects or {}
    local base = class.dps * skill.damage * (1.0 + (round - 1) * (skill.round_growth or 0.0))
    local per_target = base
        + class.dps * (effects.burn_dps or 0.0) * (effects.burn_seconds or 0.0)
    local multi = skill.hit == "aoe" or effects.piercing == true
    local hits = multi and math.min(targets, skill.target_cap or targets) or 1
    local secondary, secondary_targets = 0.0, 1
    local spec = Balance.specialization(class_id, specialization)
    local status_hit = class.dps * ((spec and spec.hit_damage_per_rank) or 0.0) * rank
    if spec and spec.burn_dps_per_rank then
        secondary = class.dps * spec.burn_dps_per_rank * rank * spec.burn_seconds
        secondary_targets = math.min(targets, 1 + spec.spread_targets_per_rank * rank)
    elseif spec and spec.bounce_damage then
        secondary_targets = math.min(math.max(0, targets - 1), spec.bounces_per_rank * rank)
        secondary = class.dps * spec.bounce_damage * secondary_targets
    elseif spec and spec.poison_dps_per_rank then
        secondary = class.dps * spec.poison_dps_per_rank * rank * spec.poison_seconds
    elseif spec and spec.hemorrhage_damage_per_rank then
        secondary = class.dps * spec.hemorrhage_damage_per_rank * rank / spec.hemorrhage_hits
    elseif spec and spec.bleed_dps_per_rank then
        secondary = class.dps * spec.bleed_dps_per_rank * rank * spec.bleed_seconds
    end
    local minion = spec and spec.minion and Balance.minions[spec.minion]
    local minion_cap = minion and math.min((spec.cap_base or 1) + (spec.cap_per_rank or 1) * rank,
        minion.cap_max) or 0
    return {
        base_single_damage = base,
        secondary_damage = secondary,
        status_hit_damage = status_hit,
        single_damage = per_target + status_hit + (targets == 1 and secondary or 0.0),
        total_damage = (per_target + status_hit) * hits
            + secondary * (spec and spec.burn_dps_per_rank and secondary_targets or 1),
        targets_hit = hits,
        single_damage_per_mana = (per_target + status_hit + (targets == 1 and secondary or 0.0)) / skill.cost,
        total_damage_per_mana = ((per_target + status_hit) * hits
            + secondary * (spec and spec.burn_dps_per_rank and secondary_targets or 1)) / skill.cost,
        delivery_delay = (effects.arm or 0.0) + (effects.trigger_delay or 0.0),
        control_seconds = spec and (spec.freeze_seconds_per_rank or spec.stagger_seconds_per_rank or spec.debuff_seconds) and
            ((spec.freeze_seconds_per_rank or spec.stagger_seconds_per_rank or spec.debuff_seconds)
                * ((spec.freeze_seconds_per_rank or spec.stagger_seconds_per_rank) and rank or 1))
            or effects.slow_seconds or effects.armor_break or 0.0,
        slow_mult = spec and spec.slow_per_rank and math.max(spec.slow_min, 1.0 - spec.slow_per_rank * rank)
            or effects.speed_mult or 1.0,
        knockback = effects.knockback or 0.0,
        area = skill.radius and math.pi * skill.radius * skill.radius or 0.0,
        line_reach = skill.life and Balance.rules.basic_attack.projectile_speed * skill.life or 0.0,
        armor_reduction = spec and (spec.armor_reduction_per_rank or 0.0) * rank or 0.0,
        poise_reduction = spec and (spec.poise_reduction_per_rank or 0.0) * rank or 0.0,
        move_speed_mult = spec and 1.0 + (spec.move_speed_per_rank or 0.0) * rank or 1.0,
        bounces = spec and (spec.bounces_per_rank or 0) * rank or 0,
        poison_dps = spec and (spec.poison_dps_per_rank or 0.0) * class.dps * rank or 0.0,
        poison_max_stacks = spec and spec.poison_max_stacks or 0,
        hemorrhage_burst = spec and (spec.hemorrhage_damage_per_rank or 0.0) * class.dps * rank or 0.0,
        iframe_seconds = spec and (spec.iframe_seconds_per_rank or 0.0) * rank or 0.0,
        resource_refund = spec and ((spec.energy_refund_per_rank or spec.mana_steal_per_rank
            or spec.rage_refund_per_rank or 0.0)) * rank or 0.0,
        execute_threshold = spec and (spec.execute_threshold_per_rank or 0.0) * rank or 0.0,
        bleed_dps = spec and (spec.bleed_dps_per_rank or 0.0) * class.dps * rank or 0.0,
        frenzy_mult = spec and (spec.frenzy_damage_per_rank or 0.0) * rank or 0.0,
        guard = spec and (spec.guard_per_rank or 0.0) * rank or 0.0,
        poise = spec and (spec.poise_per_rank or 0.0) * rank or 0.0,
        knockback_mult = spec and 1.0 + (spec.knockback_per_rank or 0.0) * rank or 1.0,
        curse_amp = spec and (spec.curse_amp_per_rank or 0.0) * rank or 0.0,
        minion_cap = minion_cap,
        minion_dps = minion and minion.dps_mult * class.dps or 0.0,
        minion_pack_dps = minion and minion.dps_mult * class.dps * minion_cap or 0.0,
        minion_hp = minion and minion.hp_mult * class.hp_max or 0.0,
        minion_duration = minion and minion.duration or 0.0,
    }
end

-- Estimated skill casts per wave — the pacing gate ("at least three meaningful
-- casts per wave by wave three") derived from each resource's real income:
-- mana = kills (wave budget / avg threat cost), energy = flat regen,
-- rage = damage-dealt uptime + the capped received-damage trickle.
function Balance.resource_metrics(class_id, wave)
    local class = assert(class_by_id(class_id), "unknown balance class: " .. tostring(class_id))
    local skill = Balance.skills[class_id]
    if skill and not skill.id then local _, first = next(skill); skill = first end
    if not skill then return { income = 0.0, casts_per_wave = 0.0, cost = 1.0 } end
    wave = math.max(1, math.floor(wave or 3))
    local b = Balance.benchmarks
    local resource = class.resource or "mana"
    local income
    if resource == "energy" then
        income = Balance.rules.energy.regen_per_second * b.wave_seconds
    elseif resource == "rage" then
        income = Balance.rules.rage.dealt_rate * b.wave_seconds * b.melee_uptime
            + Balance.rules.rage.received_cap_per_wave * 0.5
    else
        local budget = Balance.rules.arena.wave_budgets[wave]
            or Balance.rules.arena.wave_budgets[#Balance.rules.arena.wave_budgets]
        income = budget / b.avg_threat_cost * Balance.rules.mana.normal_kill
    end
    return { income = income, casts_per_wave = income / skill.cost, cost = skill.cost }
end

function Balance.monster_metrics(id)
    local monster = assert(Balance.monsters[id], "unknown balance monster: " .. tostring(id))
    local projectile = monster.projectile
    local single_hit = projectile
        and monster.dps * (projectile.cooldown or 0.65)
        or monster.dps * (Balance.rules.enemy.bite_windup + Balance.rules.enemy.bite_cooldown)
    return {
        hp = monster.hp,
        sustained_dps = monster.dps,
        hit = projectile and "single_projectile" or "single_contact",
        single_hit = single_hit,
        charge_hit = monster.charge and monster.dps * (monster.charge.dmg_mult or 1.0) or 0.0,
        aoe_hit = monster.explode and monster.explode.damage
            or monster.boss_arc and monster.boss_arc.damage or 0.0,
        aoe_radius = monster.explode and monster.explode.radius
            or monster.boss_arc and monster.boss_arc.radius or 0.0,
        summons = monster.split_into and monster.split_into.count
            or monster.summon_archetype and 1 or 0,
    }
end

function Balance.report()
    local report = { classes = {}, monsters = {} }
    for _, class in ipairs(Balance.classes) do
        local row = {
            basic_single = Balance.basic_metrics(class.id, Balance.benchmarks.single_targets),
            basic_pack = Balance.basic_metrics(class.id, Balance.benchmarks.pack_targets),
            basic_horde = Balance.basic_metrics(class.id, Balance.benchmarks.horde_targets),
            on_hit = {},
        }
        for _, spec in ipairs(class.specializations or {}) do
            row.on_hit[spec.id] = { kind = spec.kind, cost = spec.cost, spread = spec.spread == true }
        end
        report.classes[class.id] = row
    end
    for id in pairs(Balance.monsters) do report.monsters[id] = Balance.monster_metrics(id) end
    return report
end

function Balance.audit()
    local item_ids = {}
    for _, class in ipairs(Balance.classes) do
        assert(class.id and class.hp_max > 0 and class.dps > 0 and class.hit, "invalid class balance row")
    end
    for id, monster in pairs(Balance.monsters) do
        assert(monster.hp > 0 and monster.dps >= 0 and monster.threat_cost > 0,
            "invalid monster balance row: " .. tostring(id))
    end
    for id, skill in pairs(Balance.skills) do
        if not skill.id then
            for _, spell in pairs(skill) do
                assert(spell.hit and spell.delivery and spell.cost > 0 and spell.damage > 0, "invalid nested skill")
            end
        else
            assert(skill.hit and skill.delivery and skill.cost > 0 and skill.damage > 0, "invalid skill: " .. tostring(id))
        end
    end
    for _, item in ipairs(Balance.items) do
        assert(item.id and item.slot and item.effect and not item_ids[item.id], "invalid or duplicate item balance row")
        item_ids[item.id] = true
    end
    for name, ids in pairs(Balance.gearsets) do
        for _, id in ipairs(ids) do assert(item_ids[id], "unknown item in gearset " .. name .. ": " .. id) end
    end
    for _, values in pairs(Balance.map_progression.drops) do
        assert(#values == #Balance.map_progression.rank, "drop progression count mismatch")
    end
    if next(Balance.skills) == nil then
        for _, class in ipairs(Balance.classes) do
            assert(#(class.specializations or {}) == 3, class.id .. " must have three specializations")
            for _, spec in ipairs(class.specializations) do
                assert(spec.kind and spec.status and spec.cost >= 0 and spec.icon,
                    "invalid on-hit specialization: " .. class.id)
                local upgrade = Balance.specialization_upgrade_text(class.id, spec.id, 0)
                assert(upgrade:find("Next rank:", 1, true)
                    and (upgrade:find("Cost", 1, true) or upgrade:find("Passive", 1, true)),
                    "missing specialization upgrade text: " .. class.id .. ":" .. spec.id)
                if spec.spread then
                    assert(Balance.on_hit.spread_damage_mult == 0.50,
                        "spread specialization damage must remain at half strength: " .. class.id)
                end
            end
        end
        assert(#Balance.draft_cards == 3, "exactly three universal upgrades are required")
        local p1_reduction, p1_healing = Balance.preservation_effect(1)
        local p5_reduction, p5_healing = Balance.preservation_effect(5)
        assert(math.abs(p1_reduction - 0.10) < 0.0001 and math.abs(p1_healing - 0.05) < 0.0001
            and math.abs(p5_reduction - 0.50) < 0.0001 and math.abs(p5_healing - 0.25) < 0.0001,
            "Warrior Preservation scaling must be 10% reduction and 5% healing per rank")
        local universal_ids = {}
        for _, card in ipairs(Balance.draft_cards) do
            assert(card.rank_id and card.rarity == "universal" and not universal_ids[card.rank_id],
                "invalid universal upgrade")
            universal_ids[card.rank_id] = true
            assert(Balance.universal_upgrade_text(card, 0):find("Next rank:", 1, true),
                "missing universal upgrade text: " .. card.id)
        end
        return true
    end
    local ranger = Balance.basic_metrics("ranger", 1)
    local brawler = Balance.basic_metrics("brawler", 1)
    local sower = Balance.basic_metrics("sower", 1)
    local mage = Balance.basic_metrics("mage", 1)
    local brawler_ratio = brawler.single_dps / ranger.single_dps
    assert(brawler_ratio >= 1.4 and brawler_ratio <= 1.65, "Brawler practical DPS band failed")
    local brawler_ehp_ratio = brawler.effective_hp / ranger.effective_hp
    assert(brawler_ehp_ratio >= 1.7 and brawler_ehp_ratio <= 2.2, "Brawler defense band failed")
    assert(sower.single_dps / ranger.single_dps >= 0.70
        and sower.single_dps / ranger.single_dps <= 0.85, "Sower single-target band failed")
    assert(Balance.basic_metrics("sower", 5).total_dps > Balance.basic_metrics("ranger", 5).total_dps,
        "Sower pack identity failed")
    assert(mage.single_dps / ranger.single_dps >= 0.75
        and mage.single_dps / ranger.single_dps <= 0.90, "Mage basic-attack band failed")
    local mage_base = Balance.skill_metrics("mage", nil, 1, 1).base_single_damage
    for _, spec in ipairs(class_by_id("mage").specializations) do
        assert(Balance.skill_metrics("mage", spec.id, 1, 1).base_single_damage == mage_base,
            "Mage specialization changed base spell damage")
    end
    assert(Balance.skill_metrics("mage", "fire", 1).secondary_damage >= class_by_id("mage").dps,
        "Pyromancer burn too weak to read")
    assert(Balance.skill_metrics("mage", "ice", 1).slow_mult <= 0.70, "Cryomancer slow too weak to read")
    assert(Balance.skill_metrics("mage", "earth", 1).armor_reduction > 0.0, "Geomancer debuff missing")
    assert(Balance.skill_metrics("mage", "air", 5).bounces > 0, "Stormcaller bounces missing")
    assert(Balance.skill_metrics("mage", nil, 1, 3).base_single_damage > mage_base,
        "Mage round damage growth missing")
    local rogue = Balance.basic_metrics("rogue", 1)
    assert(rogue.single_dps / ranger.single_dps >= 1.10
        and rogue.single_dps / ranger.single_dps <= 1.30, "Rogue single-target band failed")
    assert(rogue.effective_hp / ranger.effective_hp >= 0.70
        and rogue.effective_hp / ranger.effective_hp <= 0.90, "Rogue defense band failed")
    local rogue_base = Balance.skill_metrics("rogue", nil, 1, 1).base_single_damage
    for _, spec in ipairs(class_by_id("rogue").specializations) do
        assert(Balance.skill_metrics("rogue", spec.id, 1, 1).base_single_damage == rogue_base,
            "Rogue specialization changed base skill damage")
    end
    assert(Balance.skill_metrics("rogue", "poison", 1).poison_dps > 0.0, "Venomblade poison missing")
    assert(Balance.skill_metrics("rogue", "hemorrhage", 1).hemorrhage_burst > 0.0, "Bloodletter rupture missing")
    assert(Balance.skill_metrics("rogue", "shadow", 1).resource_refund > 0.0, "Shadowdancer refund missing")
    assert(Balance.skill_metrics("rogue", "execute", 1).execute_threshold > 0.0, "Executioner threshold missing")
    -- Warrior: durable close-range identity, below Brawler's raw output.
    local warrior = Balance.basic_metrics("warrior", 1)
    assert(warrior.single_dps < brawler.single_dps * 0.75, "Warrior must sit below Brawler raw DPS")
    assert(warrior.single_dps / ranger.single_dps >= 0.85
        and warrior.single_dps / ranger.single_dps <= 1.10, "Warrior single-target band failed")
    assert(warrior.effective_hp / ranger.effective_hp >= 1.70
        and warrior.effective_hp / ranger.effective_hp <= 2.10, "Warrior defense band failed")
    local warrior_base = Balance.skill_metrics("warrior", nil, 1, 1).base_single_damage
    for _, spec in ipairs(class_by_id("warrior").specializations) do
        assert(Balance.skill_metrics("warrior", spec.id, 1, 1).base_single_damage == warrior_base,
            "Warrior specialization changed base skill damage")
    end
    assert(Balance.skill_metrics("warrior", nil, 1, 3).base_single_damage > warrior_base,
        "Warrior round damage growth missing")
    assert(Balance.skill_metrics("warrior", "bleed", 1).bleed_dps > 0.0, "Lacerator bleed missing")
    local berserker = Balance.skill_metrics("warrior", "berserker", 1)
    assert(berserker.frenzy_mult > 0.0 and berserker.resource_refund > 0.0, "Berserker tempo/refund missing")
    local vanguard = Balance.skill_metrics("warrior", "vanguard", 1)
    assert(vanguard.guard > 0.0 and vanguard.poise > 0.0, "Vanguard guard/poise missing")
    local warlord = Balance.skill_metrics("warrior", "warlord", 1)
    assert(warlord.armor_reduction > 0.0 and warlord.control_seconds > 0.0
        and warlord.knockback_mult > 1.0, "Warlord break/stagger/knockback missing")
    assert(Balance.rules.rage.received_cap_per_wave < Balance.rules.rage.max * 0.5,
        "Rage received-damage cap must stay a trickle, not the engine")
    -- Necromancer: frail caster whose power rides the capped pack.
    local necro = Balance.basic_metrics("necromancer", 1)
    assert(necro.single_dps / ranger.single_dps >= 0.50
        and necro.single_dps / ranger.single_dps <= 0.75, "Necromancer solo band failed")
    assert(necro.effective_hp < ranger.effective_hp, "Necromancer must stay frailer than Ranger")
    local necro_base = Balance.skill_metrics("necromancer", nil, 1, 1).base_single_damage
    for _, spec in ipairs(class_by_id("necromancer").specializations) do
        assert(Balance.skill_metrics("necromancer", spec.id, 1, 1).base_single_damage == necro_base,
            "Necromancer specialization changed base skill damage")
    end
    assert(Balance.skill_metrics("necromancer", nil, 1, 3).base_single_damage > necro_base,
        "Necromancer round damage growth missing")
    assert(Balance.skill_metrics("necromancer", "curse", 1).curse_amp > 0.0, "Curseweaver amp missing")
    assert(Balance.skill_metrics("necromancer", "steal", 1).resource_refund > 0.0
        and Balance.skill_metrics("necromancer", "steal", 1).slow_mult < 1.0, "Spellstealer steal missing")
    local bone = Balance.skill_metrics("necromancer", "bone", 1)
    assert(bone.minion_cap > 0 and bone.minion_dps > 0.0 and bone.minion_hp > 0.0
        and bone.minion_duration > 0.0, "Bonecaller pack metrics missing")
    local demon = Balance.skill_metrics("necromancer", "demon", 1)
    assert(demon.minion_cap > 0 and demon.minion_pack_dps > 0.0, "Demonologist pact metrics missing")
    local bone_max = Balance.skill_metrics("necromancer", "bone", 1, 1, 4)
    assert(bone_max.minion_cap <= Balance.minions.skeleton.cap_max, "Bonecaller cap must clamp to the pool")
    -- Pack identity: at max rank the pack + caster must clearly beat the frail
    -- solo caster, without the caster alone matching Ranger.
    assert(necro.single_dps + bone_max.minion_pack_dps > ranger.single_dps,
        "Necromancer max-rank pack fails to carry the class")
    for kind, m in pairs(Balance.minions) do
        assert(m.hp_mult > 0 and m.dps_mult > 0 and m.cap_max > 0 and m.duration > 0,
            "invalid minion balance row: " .. kind)
    end
    -- Pacing gate: every class affords at least three casts by wave three.
    for _, class in ipairs(Balance.classes) do
        assert(Balance.resource_metrics(class.id, 3).casts_per_wave >= 3.0,
            "resource throughput below three casts per wave: " .. class.id)
    end
    return true
end

assert(Balance.audit())

_G.ATH_BALANCE = Balance
return Balance

