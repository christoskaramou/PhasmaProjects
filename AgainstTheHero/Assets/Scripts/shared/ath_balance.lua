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
    flask = { charges = 6, health_allocation = 4, heal_fraction = 0.40,
        invulnerability = 2.0, mana = 40, drink_time = 0.70, lock_time = 2.0,
        move_mult = 0.45, interrupt_hp_fraction = 0.10 },
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
        draft_weights = { common = 60, uncommon = 32, rare = 8 },
    },
    arena = {
        spawn = { interval_start = 0.60, interval_min = 0.20, batch_start = 3,
            batch_max = 10, cap_start = 44, cap_max = 85, brute_after = 26.0 },
        wave_budgets = { 130, 173, 230, 302, 389, 500, 640 },
        reserve_start = 130.0, creep_hp_mult = 1.56,
    },
}

Balance.benchmarks = { single_targets = 1, pack_targets = 5, horde_targets = 10 }

Balance.gearsets = {
    mid = { "iron_helm", "husk_plate", "sprint_greaves", "gauntlets", "cleaver", "moss_locket" },
    top = { "gourd_visor", "royal_carapace", "plated_greaves", "duelist_gloves", "twin_blades", "crit_ring" },
}

Balance.draft_cards = {
    { id = "whetstone", name = "Whetstone", rarity = "common", desc = "+15% damage", effect = { dps_mult = 1.15 } },
    { id = "quick_hands", name = "Quick Hands", rarity = "common", desc = "+12% attack speed", effect = { fire_interval_mult = 0.88 } },
    { id = "field_rations", name = "Field Rations", rarity = "common", tags = { "Flask" }, desc = "+25 max HP, heal 40", effect = { hp_max_add = 25.0, heal = 40.0 } },
    { id = "swift_soles", name = "Swift Soles", rarity = "common", desc = "+10% move speed", effect = { speed_mult = 1.10, kite_speed_mult = 1.10 } },
    { id = "tough_hide", name = "Tough Hide", rarity = "common", desc = "+8% armor", effect = { armor_add = 0.08 } },
    { id = "long_arms", name = "Long Arms", rarity = "common", desc = "+1.5 attack range", effect = { attack_range_add = 1.5 } },
    { id = "extra_bolt", name = "Extra Bolt", rarity = "uncommon", tags = { "Cleave" }, desc = "+1 shot per volley", effect = { cleave_add = 1 } },
    { id = "leech_fang", name = "Leech Fang", rarity = "uncommon", desc = "+2 lifesteal per hit", effect = { lifesteal_add = 2.0 } },
    { id = "green_blood", name = "Green Blood", rarity = "uncommon", desc = "+1.5 HP/s regen", effect = { regen_add = 1.5 } },
    { id = "bramble_coat", name = "Bramble Coat", rarity = "uncommon", tags = { "Guard", "Retaliation" }, desc = "+6 thorns", effect = { thorns_add = 6.0 } },
    { id = "magnet_pouch", name = "Magnet Pouch", rarity = "uncommon", desc = "+1.2 pickup range, +25% gold", effect = { pickup_range_add = 1.2, gold_find_add = 0.25 } },
    { id = "keen_eye", name = "Keen Eye", rarity = "uncommon", tags = { "Bleed" }, desc = "+15% crit chance", effect = { crit_add = 0.15 } },
    { id = "whirlwind", name = "Whirlwind", rarity = "rare", tags = { "Orbit" }, desc = "Spin attack around you", effect = { whirl_add = 1 } },
    { id = "chill_aura", name = "Chill Aura", rarity = "rare", desc = "Nearby enemies slow to a crawl", effect = { slow_aura = true } },
    { id = "glass_edge", name = "Glass Edge", rarity = "rare", desc = "+35% damage, -8% move", effect = { dps_mult = 1.35, speed_mult = 0.92, kite_speed_mult = 0.92 } },
    { id = "gold_rush", name = "Gold Rush", rarity = "common", desc = "+30% gold", effect = { gold_find_add = 0.30 } },
    { id = "quick_step", name = "Quick Step", rarity = "uncommon", tags = { "Dodge" }, desc = "Dodge recharges 25% faster", effect = { dodge_recharge_mult = 0.75 } },
    { id = "bulwark", name = "Bulwark", rarity = "rare", tags = { "Guard", "Stagger" }, desc = "+15% armor, +20 max HP", effect = { armor_add = 0.15, hp_max_add = 20.0 } },
    { id = "second_wind", name = "Second Wind", rarity = "rare", tags = { "Dodge" }, desc = "+1 dodge charge", effect = { dodge_charge_add = 1 } },
    { id = "crimson_edge", name = "Crimson Edge", rarity = "rare", tags = { "Bleed" }, desc = "Crits inflict bleed", effect = { bleed_on_crit = 8.0 } },
    { id = "mana_echo", name = "Mana Echo", rarity = "rare", tags = { "Mana", "Orbit" }, desc = "Skills and mana flasks burst nearby foes", effect = { mana_burst = 0.7 } },
    { id = "flask_ward", name = "Flask Ward", rarity = "rare", tags = { "Flask", "Guard" }, desc = "Health restored erupts as damage", effect = { flask_nova = 0.55 } },
}

Balance.skills = {
    brawler = { id = "ground_slam", name = "GROUND SLAM", cost = 35, hit = "aoe", delivery = "instant",
        radius = 4.5, damage = 1.5, effects = { armor_break = 5.0, knockback = 2.4 } },
    ranger = { id = "piercing_shot", name = "PIERCING SHOT", cost = 35, hit = "single_line", delivery = "projectile", life = 2.2,
        damage = 2.4, effects = { piercing = true } },
    sower = { id = "seed_mine", name = "SEED MINE", cost = 35, hit = "aoe", delivery = "trap",
        radius = 3.3, damage = 4.0, effects = { arm = 0.25, trigger_delay = 0.5, life = 6.0 } },
    mage = { id = "arcane_bolt", name = "ARCANE BOLT", cost = 35,
        hit = "single_projectile", delivery = "projectile", life = 2.2,
        damage = 2.0, round_growth = 0.08, color = { 0.68, 0.58, 1.0 } },
    rogue = { id = "dagger_flurry", name = "DAGGER FLURRY", cost = 40,
        hit = "single_projectile", delivery = "projectile", life = 1.5,
        damage = 2.15, round_growth = 0.08, color = { 0.72, 0.30, 0.82 } },
}

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
            { id = "marksman", name = "Marksman", short = "M", tags = { "Mark" },
              desc = "Skill marks targets for +6% damage taken per rank for 3s.",
              accent = { 0.96, 0.84, 0.36, 0.95 }, mark_per_rank = 0.06, mark_seconds = 3.0 },
            { id = "volley", name = "Volleyer", short = "V", tags = { "Cleave" },
              desc = "+1 secondary arrow per rank for 35% hero damage.",
              accent = { 0.92, 0.58, 0.26, 0.95 }, chain_per_rank = 1, chain_damage = 0.35, chain_radius = 6.0 },
            { id = "skirmish", name = "Skirmisher", short = "S", tags = { "Dodge", "Move" },
              desc = "+5% move speed and -0.5s dodge recharge on skill hit per rank.",
              accent = { 0.40, 0.82, 0.92, 0.95 }, move_speed_per_rank = 0.05,
              dodge_refund_per_rank = 0.5 },
            { id = "warden", name = "Warden", short = "W", tags = { "Slow", "Root" },
              desc = "-15% speed and +0.15s root per rank for 2.5s.",
              accent = { 0.38, 0.78, 0.42, 0.95 }, slow_per_rank = 0.15, slow_min = 0.25,
              slow_seconds = 2.5, root_seconds_per_rank = 0.15 },
        },
    },
    {
        id = "brawler", name = "Brawler", attack = "melee", hit = "aoe_cleave",
        blurb = "Wide cleave plus an orbiting spin. Armored for close combat.",
        accent = { 0.92, 0.42, 0.34, 0.95 }, hp_max = 190.0, dps = 60.0,
        cleave = 8, attack_range = 5.0, speed = 9.0, kite_speed = 9.0,
        armor = 0.15, lifesteal = 0.5, regen = 1.5, whirl = 1,
        sprite_texture = "Textures/modes/arena/hero_brawler.png",
        progressive_specializations = true,
        specializations = {
            { id = "juggernaut", name = "Juggernaut", short = "J", tags = { "Guard" },
              desc = "+8% damage guard per rank for 4s after Ground Slam.",
              accent = { 0.92, 0.42, 0.34, 0.95 }, guard_per_rank = 0.08, guard_seconds = 4.0 },
            { id = "ironfist", name = "Ironfist", short = "I", tags = { "Stagger" },
              desc = "+50% hero damage per rank against elites hit by Ground Slam.",
              accent = { 0.86, 0.62, 0.30, 0.95 }, elite_damage_per_rank = 0.50 },
            { id = "cyclone", name = "Cyclone", short = "C", tags = { "Cleave", "Orbit" },
              desc = "Ground Slam adds a 20% hero-damage shockwave per rank.",
              accent = { 0.96, 0.68, 0.24, 0.95 }, shockwave_damage_per_rank = 0.20 },
            { id = "counter", name = "Counterfighter", short = "R", tags = { "Retaliation" },
              desc = "Ground Slam arms 35% hero-damage retaliation per rank for 4s.",
              accent = { 0.76, 0.30, 0.32, 0.95 }, retaliation_damage_per_rank = 0.35,
              retaliation_seconds = 4.0 },
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
            { id = "trapper", name = "Trapper", short = "T", tags = { "Trap" },
              desc = "+0.25 mine radius per rank.", accent = { 0.54, 0.82, 0.40, 0.95 },
              radius_per_rank = 0.25 },
            { id = "thorn", name = "Thornwarden", short = "T", tags = { "Root", "Slow" },
              desc = "Mine roots for 0.2s and slows 15% per rank.", accent = { 0.30, 0.72, 0.32, 0.95 },
              root_seconds_per_rank = 0.20, slow_per_rank = 0.15, slow_min = 0.25, slow_seconds = 2.5 },
            { id = "bloom", name = "Bloomkeeper", short = "B", tags = { "Guard" },
              desc = "+6% damage guard per rank for 4s after planting.",
              accent = { 0.88, 0.62, 0.86, 0.95 }, guard_per_rank = 0.06, guard_seconds = 4.0 },
            { id = "harvest", name = "Harveststorm", short = "H", tags = { "Cleave" },
              desc = "Mine adds 25% hero damage per rank on every target hit.",
              accent = { 0.86, 0.72, 0.26, 0.95 }, bonus_damage_per_rank = 0.25 },
        },
    },
    {
        id = "mage", name = "Mage", attack = "ranged", hit = "single_projectile",
        blurb = "Fire one stable spell; elemental cards add compatible effects.",
        accent = { 0.58, 0.48, 1.0, 0.95 }, hp_max = 100.0, dps = 24.0,
        cleave = 2, attack_range = 8.0, fire_interval = 0.30, speed = 8.2, kite_speed = 8.2,
        sprite_texture = "Textures/modes/arena/hero_mage.png",
        bolt_color = { 0.68, 0.58, 1.0 }, bolt_scale = 0.34,
        progressive_specializations = true,
        specializations = {
            { id = "fire", name = "Pyromancer", short = "F", tags = { "Burn" },
              desc = "+15% fire hit and +25% hero DPS as Burn per rank for 4s. Refreshes; spreads on death.",
              accent = { 1.0, 0.30, 0.10, 0.95 },
              hit_damage_per_rank = 0.15, burn_dps_per_rank = 0.25,
              burn_seconds = 4.0, spread_radius = 4.0,
              spread_targets_per_rank = 1 },
            { id = "ice", name = "Cryomancer", short = "I", tags = { "Slow", "Freeze" },
              desc = "+12% cold hit and -30% speed per rank for 3s. Every third hit freezes.",
              accent = { 0.35, 0.78, 1.0, 0.95 },
              hit_damage_per_rank = 0.12, slow_per_rank = 0.30, slow_min = 0.20, slow_seconds = 3.0,
              freeze_hits = 3, freeze_seconds_per_rank = 0.25, boss_freeze_mult = 0.35 },
            { id = "earth", name = "Geomancer", short = "G", tags = { "Armor", "Poise" },
              desc = "+10% earth hit, -8% armor and -12% poise per rank for 3s.",
              accent = { 0.72, 0.46, 0.20, 0.95 },
              hit_damage_per_rank = 0.10, armor_reduction_per_rank = 0.08, poise_reduction_per_rank = 0.12,
              debuff_seconds = 3.0 },
            { id = "air", name = "Stormcaller", short = "S", tags = { "Move", "Lightning" },
              desc = "+18% lightning hit, +6% move speed and +1 bounce per rank.",
              accent = { 0.62, 0.95, 1.0, 0.95 },
              hit_damage_per_rank = 0.18, move_speed_per_rank = 0.06, bounces_per_rank = 1,
              bounce_damage = 0.50, bounce_radius = 6.0 },
        },
    },
    {
        id = "rogue", name = "Rogue", attack = "ranged", hit = "single_projectile", resource = "energy",
        blurb = "Fast short-range daggers. Energy regenerates constantly.",
        accent = { 0.62, 0.24, 0.72, 0.95 }, hp_max = 92.0, dps = 27.0,
        cleave = 2, attack_range = 6.5, fire_interval = 0.22, speed = 9.5, kite_speed = 9.5,
        sprite_texture = "Textures/modes/arena/hero_rogue.png",
        bolt_color = { 0.72, 0.30, 0.82 }, bolt_scale = 0.27,
        progressive_specializations = true,
        specializations = {
            { id = "poison", name = "Venomblade", short = "P", tags = { "Poison" },
              desc = "+6% hero DPS as stacking Poison per rank for 4s; maximum 3 stacks.",
              accent = { 0.42, 0.92, 0.28, 0.95 }, poison_dps_per_rank = 0.06,
              poison_seconds = 4.0, poison_max_stacks = 3 },
            { id = "hemorrhage", name = "Bloodletter", short = "H", tags = { "Hemorrhage" },
              desc = "Every third skill hit ruptures for +60% hero damage per rank.",
              accent = { 0.92, 0.18, 0.28, 0.95 }, hemorrhage_hits = 3,
              hemorrhage_damage_per_rank = 0.60, hemorrhage_seconds = 4.0 },
            { id = "shadow", name = "Shadowdancer", short = "S", tags = { "Dodge", "Energy" },
              desc = "+0.08s skill i-frames and +3 energy on hit per rank.",
              accent = { 0.48, 0.38, 0.88, 0.95 }, iframe_seconds_per_rank = 0.08,
              energy_refund_per_rank = 3 },
            { id = "execute", name = "Executioner", short = "E", tags = { "Execute" },
              desc = "Executes normal enemies below 8% HP per rank; bosses use 2%.",
              accent = { 0.96, 0.64, 0.22, 0.95 }, execute_threshold_per_rank = 0.08,
              boss_execute_threshold_per_rank = 0.02 },
        },
    },
}

-- Progressive classes offer every specialization beside normal wave boons.
-- Re-picking a card raises that effect's rank; the base skill remains unchanged.
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
                specialization = spec.id,
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
    gourd_king = { base = "pumpkin_brute", name = "Gourd King", threat_cost = 20, hp = 4400, dps = 26.0,
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
    end
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
        control_seconds = spec and (spec.freeze_seconds_per_rank or spec.debuff_seconds) and
            ((spec.freeze_seconds_per_rank or spec.debuff_seconds) * (spec.freeze_seconds_per_rank and rank or 1))
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
        resource_refund = spec and (spec.energy_refund_per_rank or 0.0) * rank or 0.0,
        execute_threshold = spec and (spec.execute_threshold_per_rank or 0.0) * rank or 0.0,
    }
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
            skills = {},
        }
        if class.progressive_specializations then
            row.skills.base = Balance.skill_metrics(class.id, nil, Balance.benchmarks.pack_targets)
            for _, spec in ipairs(class.specializations) do
                row.skills[spec.id] = Balance.skill_metrics(class.id, spec.id, Balance.benchmarks.pack_targets)
            end
        else
            row.skills.default = Balance.skill_metrics(class.id, nil, Balance.benchmarks.pack_targets)
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
    return true
end

assert(Balance.audit())

_G.ATH_BALANCE = Balance
return Balance
