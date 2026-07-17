-- Runtime balance database. Edit this file to tune classes, skills, and arena monsters.
-- Damage fields are deliberately explicit: dps drives contact/shots, charge.dmg_mult
-- drives single charge hits, and explode/boss_arc damage are fixed AoE hits.

if rawget(_G, "ATH_BALANCE") then return _G.ATH_BALANCE end

local Visuals = ATH_COMMON.visuals(_ENV)
local V = Visuals.data
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
        hero_contact = 1.4, hero_projectile = 2.6,
        shockwave_death = 4.5 },
    crit = { base_chance = 0.03, damage_mult = 2.0, bleed_seconds = 3.0 },
    flask = { charges = 6, heal_fraction = 0.40,
        invulnerability = 2.0, drink_time = 0.70, lock_time = 2.0,
        move_mult = 0.45, interrupt_hp_fraction = 0.10,
        -- Melee sustain identity: landing blows refills flask charges (fraction
        -- of a charge per dps-second dealt) and the committed drink is half as long.
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
        -- Proc-boon delivery: elites roll this chance to drop a BOON beacon (only
        -- boons the hero lacks); tuned so a ~10-wave run sees ~2-3. Boss always
        -- guarantees one. Independent of item-drop / wave_drop_floor rolls.
        boon_elite_chance = 0.12,
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
    -- Pacing assumptions: seconds of real fighting per wave and the melee
    -- hero's damage uptime (paper_balance exposure model).
    wave_seconds = 40.0, melee_uptime = 0.65 }

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
    { id = "universal_sustain", rank_id = "sustain", name = "Vital Conduit",
      rarity = "universal", tags = { "Health", "Regen" },
      desc = "+1% max health/s per rank.",
      effect = { upgrade_rank = "sustain", hp_regen_pct_add = 0.01 } },
}

-- Proc boons (Wave Director Phase 2): run-scoped draft cards whose effects are a
-- single visible proc each, built entirely on existing combat pools (tracer
-- bolts, death-burst particles, melee-aggregation dps, damage-number popups).
-- Rare-ish by design (uncommon/rare, never the common bucket). Applied via
-- run_cards -> apply_gear_effect (sets a hero.<proc> field), reset by
-- recompute_hero_stats. `weight` is the draft rarity weight (lower = rarer),
-- kept modest so these never flood a draft. NOT one of the 3 universal upgrades
-- (Balance.draft_cards is asserted == 3); a separate pool.
Balance.draft_boons = {
    { id = "chain_bolt", name = "Chain Bolt", rarity = "uncommon", weight = 10, boon = true,
      tags = { "Ranged", "Bounce" },
      desc = "Bolt impacts arc to the nearest other foe within 4m for 50% damage.",
      effect = { chain_bolt = { fraction = 0.5, range = 4.0 } } },
    { id = "crit_burst", name = "Critical Burst", rarity = "rare", weight = 6, boon = true,
      tags = { "Crit", "AoE" },
      desc = "Critical hits detonate a small blast around the victim for 60% of the hit.",
      effect = { crit_burst = { radius = 2.2, dmg_mult = 0.6 } } },
    { id = "orbit_blades", name = "Orbit Blades", rarity = "rare", weight = 6, boon = true,
      tags = { "Orbit", "Melee" },
      desc = "Two blades circle you, shredding foes they pass through.",
      effect = { orbit_blades = { dps = 16.0, radius = 2.4 } } },
    { id = "vampiric_surge", name = "Vampiric Surge", rarity = "uncommon", weight = 10, boon = true,
      tags = { "Lifesteal", "Heal" },
      desc = "Each kill restores 5 health.",
      effect = { vampiric_surge = { heal = 5.0 } } },
}

-- Spells are gone. Ranked specialization riders ride every basic attack for
-- free; breadth is the cost instead — the player invests in any TWO of the
-- three class specs, their pick at any draft; the third locks out once two
-- hold ranks (see Duel:spec_card_allowed). Spread riders use half the damage
-- coefficient of the equivalent local rider by design.
Balance.on_hit = { tick = 0.5, duration = 4.0, spread_radius = 4.0,
    spread_damage_mult = 0.5 }

Balance.classes = {
    {
        id = "ranger", name = "Ranger", attack = "ranged", hit = "single_projectile",
        blurb = "Long-range bolts. Pick the swarm off from afar.",
        accent = { 0.96, 0.84, 0.36, 0.95 }, hp_max = 115.0, dps = 25.0,
        cleave = 3, attack_range = 9.0, fire_interval = 0.26, speed = 8.5, kite_speed = 8.5,
        sprite_texture = V.heroes.ranger.texture,
        sprite_sheet = V.heroes.ranger.sheet,
        bolt_color = { 1.0, 0.90, 0.42 }, bolt_scale = 0.34,
        progressive_specializations = true,
        specializations = {
            { id = "poison", name = "Poison Arrows", short = "P", tags = { "Poison", "Spread" },
              icon = V.specializations.poison,
              desc = "Hits poison immediately and over time; spreads on death at 50% damage.",
              accent = { 0.42, 0.92, 0.28, 0.95 }, kind = "dot", status = "poison",
              initial_per_rank = 0.10, tick_per_rank = 0.10, spread = true },
            { id = "bleed", name = "Bleed Arrows", short = "B", tags = { "Hemorrhage" },
              icon = V.specializations.bleed,
              desc = "Hits stack Hemorrhage five times: 20/40/60/80/100% hit damage at rank 1.",
              accent = { 0.95, 0.14, 0.20, 0.95 }, kind = "stack_dot", status = "bleed",
              stack_base = 0.20, stack_rank_add = 0.10, max_stacks = 5 },
            { id = "piercing", name = "Piercing Arrows", short = "I", tags = { "Pierce" },
              icon = V.specializations.ranger_piercing,
              desc = "Arrows pierce for 60% hit damage and carry every on-hit effect.",
              accent = { 0.96, 0.84, 0.36, 0.95 }, kind = "pierce", status = "pierce",
              damage = 0.90, damage_per_rank = 0.15 },
        },
    },
    {
        id = "brawler", name = "Brawler", attack = "melee", hit = "aoe_cleave",
        blurb = "Wide cleave plus an orbiting spin. Armored for close combat.",
        accent = { 0.92, 0.42, 0.34, 0.95 }, hp_max = 190.0, dps = 60.0,
        cleave = 8, attack_range = 5.0, speed = 9.0, kite_speed = 9.0,
        armor = 0.15, lifesteal = 0.5, regen = 1.5, whirl = 1,
        sprite_texture = V.heroes.brawler.texture,
        sprite_sheet = V.heroes.brawler.sheet,
        progressive_specializations = true,
        specializations = {
            { id = "bleed", name = "Bleed", short = "B", tags = { "Hemorrhage" },
              icon = V.specializations.bleed,
              desc = "Hits stack Hemorrhage five times: 20/40/60/80/100% hit damage per tick.",
              accent = { 0.95, 0.14, 0.20, 0.95 }, kind = "stack_dot", status = "bleed",
              stack_base = 0.20, stack_rank_add = 0.10, max_stacks = 5 },
            { id = "frenzy", name = "Frenzy", short = "F", tags = { "Frenzy" },
              icon = V.specializations.brawler_frenzy,
              desc = "Hits stack short damage, attack-speed, and movement-speed buffs up to five.",
              accent = { 0.96, 0.55, 0.20, 0.95 }, kind = "frenzy", status = "frenzy",
              stack_per_rank = 0.10, max_stacks = 5, duration = 3.0 },
            { id = "shockwave", name = "Shockwave", short = "S", tags = { "Impact" },
              icon = V.specializations.brawler_shockwave,
              desc = "A killing hit launches a corpse shockwave into enemies behind it.",
              accent = { 0.92, 0.42, 0.34, 0.95 }, kind = "shockwave", status = "shockwave",
              damage = 0.70, damage_per_rank = 0.15, radius = 3.5 },
        },
    },
    {
        id = "sower", name = "Sower", attack = "ranged", hit = "single_projectile",
        blurb = "Sprays seed-shot at the nearest five. Short range, fast.",
        accent = { 0.54, 0.82, 0.40, 0.95 }, hp_max = 110.0, dps = 22.0,
        cleave = 5, attack_range = 7.0, fire_interval = 0.30, speed = 8.3, kite_speed = 8.3,
        sprite_texture = V.heroes.sower.texture,
        sprite_sheet = V.heroes.sower.sheet,
        bolt_color = { 0.66, 0.92, 0.40 }, bolt_scale = 0.30,
        progressive_specializations = true,
        specializations = {
            { id = "explosion", name = "Explosion", short = "X", tags = { "Explosion" },
              icon = V.specializations.sower_explosion,
              desc = "Hits prime enemies to explode on death. Does not spread.",
              accent = { 0.96, 0.58, 0.18, 0.95 }, kind = "explosion", status = "explosion",
              damage = 0.55, damage_per_rank = 0.20, radius = 4.0 },
            { id = "seed", name = "Seed", short = "S", tags = { "Seed", "Spread" },
              icon = V.specializations.sower_seed,
              desc = "Hits seed immediate and periodic damage; spreads on death at 50% damage.",
              accent = { 0.54, 0.82, 0.40, 0.95 }, kind = "dot", status = "seed",
              initial_per_rank = 0.10, tick_per_rank = 0.10, spread = true },
            { id = "thorns", name = "Thorns", short = "T", tags = { "Thorns" },
              icon = V.specializations.sower_thorns,
              desc = "Hits stack Thorns five times: 20/40/60/80/100% hit damage at rank 1.",
              accent = { 0.30, 0.72, 0.32, 0.95 }, kind = "stack_dot", status = "thorns",
              stack_base = 0.20, stack_rank_add = 0.10, max_stacks = 5 },
        },
    },
    {
        id = "mage", name = "Mage", attack = "ranged", hit = "single_projectile",
        blurb = "Elemental on-hit effects reshape every basic projectile.",
        accent = { 0.58, 0.48, 1.0, 0.95 }, hp_max = 135.0, dps = 30.0,
        cleave = 3, attack_range = 8.0, fire_interval = 0.26, speed = 8.3, kite_speed = 8.3,
        regen = 1.5,
        sprite_texture = V.heroes.mage.texture,
        sprite_sheet = V.heroes.mage.sheet,
        bolt_color = { 0.68, 0.58, 1.0 }, bolt_scale = 0.34,
        progressive_specializations = true,
        specializations = {
            { id = "fire", name = "Pyromancer", short = "F", tags = { "Burn" },
              icon = V.specializations.mage_fire,
              desc = "Hits burn immediately and over time; spreads on death at 50% damage.",
              -- 0.24/rank: mage's only deep-map carrier; needs to outpace
              -- wave pressure without a bleed-style stack DoT.
              accent = { 1.0, 0.30, 0.10, 0.95 }, kind = "dot", status = "fire",
              initial_per_rank = 0.24, tick_per_rank = 0.24, spread = true },
            { id = "frost", name = "Cryomancer", short = "F", tags = { "Frost", "Slow" },
              icon = V.specializations.mage_frost,
              desc = "Hits deal Frost damage and slow enemy movement and attack speed.",
              accent = { 0.35, 0.78, 1.0, 0.95 }, kind = "frost", status = "frost",
              damage_per_rank = 0.20, slow_per_rank = 0.12, duration = 3.0 },
            { id = "earth", name = "Geomancer", short = "G", tags = { "Shards", "Cone" },
              icon = V.specializations.mage_earth,
              desc = "Each hit sprays rock shards forward in a tight cone; shards damage every enemy they touch.",
              accent = { 0.72, 0.46, 0.20, 0.95 }, kind = "shard_cone", status = "earth",
              damage = 0.50, damage_per_rank = 0.10,
              shards_base = 5, shards_per_rank = 1, cone_deg = 22.0,
              range = 5.5, speed = 15.0 },
        },
    },
    {
        id = "rogue", name = "Rogue", attack = "ranged", hit = "single_projectile",
        blurb = "Fast short-range daggers with deadly on-hit riders.",
        accent = { 0.62, 0.24, 0.72, 0.95 }, hp_max = 102.0, dps = 27.0,
        cleave = 2, attack_range = 6.5, fire_interval = 0.22, speed = 9.5, kite_speed = 9.5,
        sprite_texture = V.heroes.rogue.texture,
        sprite_sheet = V.heroes.rogue.sheet,
        bolt_color = { 0.72, 0.30, 0.82 }, bolt_scale = 0.27,
        progressive_specializations = true,
        specializations = {
            { id = "shadow", name = "Shadowdancer", short = "S", tags = { "Dodge", "Energy" },
              icon = V.specializations.rogue_shadow,
              desc = "Hits deal pure damage and apply Smoke, giving enemies a miss chance.",
              accent = { 0.48, 0.38, 0.88, 0.95 }, kind = "shadow", status = "shadow",
              damage_per_rank = 0.15, miss_per_rank = 0.08, duration = 3.0 },
            { id = "poison", name = "Poison", short = "P", tags = { "Poison", "Spread" },
              icon = V.specializations.poison,
              desc = "Hits poison immediately and over time; spreads on death at 50% damage.",
              accent = { 0.42, 0.92, 0.28, 0.95 }, kind = "dot", status = "poison",
              initial_per_rank = 0.10, tick_per_rank = 0.10, spread = true },
            { id = "daggers", name = "Daggers", short = "D", tags = { "Pierce" },
              icon = V.specializations.rogue_daggers,
              desc = "Thrown daggers pierce for 60% hit damage and carry on-hit effects.",
              accent = { 0.72, 0.30, 0.82, 0.95 }, kind = "pierce", status = "daggers",
              damage = 0.90, damage_per_rank = 0.15 },
        },
    },
    {
        id = "warrior", name = "Warrior", attack = "melee", hit = "aoe_cleave",
        blurb = "Iron line-holder with punishing on-hit effects and guard.",
        accent = { 0.85, 0.32, 0.22, 0.95 }, hp_max = 175.0, dps = 54.0,
        cleave = 6, attack_range = 4.6, speed = 8.8, kite_speed = 8.8,
        armor = 0.18, regen = 1.0,
        sprite_texture = V.heroes.warrior.texture,
        sprite_sheet = V.heroes.warrior.sheet,
        progressive_specializations = true,
        specializations = {
            { id = "bleed", name = "Lacerator", short = "L", tags = { "Bleed" },
              icon = V.specializations.bleed,
              desc = "Hits stack Hemorrhage five times: 20/40/60/80/100% hit damage per tick.",
              accent = { 0.95, 0.20, 0.22, 0.95 }, kind = "stack_dot", status = "bleed",
              stack_base = 0.20, stack_rank_add = 0.10, max_stacks = 5 },
            { id = "daze", name = "Daze", short = "D", tags = { "Daze" },
              icon = V.specializations.warrior_daze,
              desc = "Hits reduce enemy damage, attack speed, and movement speed.",
              accent = { 0.92, 0.78, 0.30, 0.95 }, kind = "daze", status = "daze",
              reduction_per_rank = 0.10, duration = 3.0 },
            { id = "preservation", name = "Preservation", short = "P", tags = { "Guard", "Regen" },
              icon = V.specializations.preservation,
              desc = "Taking damage briefly reduces damage and regenerates a share of maximum health.",
              accent = { 0.55, 0.70, 0.95, 0.95 }, kind = "preservation", status = "preservation",
              damage_reduction_per_rank = 0.10, heal_fraction_per_rank = 0.05, heal_seconds = 5.0 },
        },
    },
    {
        id = "necromancer", name = "Necromancer", attack = "ranged", hit = "single_projectile",
        blurb = "Frail speaker for the dead. Marked kills grow a skeleton-mage pack.",
        accent = { 0.48, 0.85, 0.55, 0.95 }, hp_max = 112.0, dps = 24.0,
        cleave = 2, attack_range = 8.0, fire_interval = 0.30, speed = 8.2, kite_speed = 8.2,
        sprite_texture = V.heroes.necromancer.texture,
        sprite_sheet = V.heroes.necromancer.sheet,
        bolt_color = { 0.55, 0.95, 0.62 }, bolt_scale = 0.30,
        progressive_specializations = true,
        specializations = {
            { id = "curse", name = "Curseweaver", short = "C", tags = { "Curse" },
              icon = V.specializations.necromancer_curse,
              desc = "Hits curse for damage; spreads on death at 50% damage.",
              accent = { 0.72, 0.30, 0.95, 0.95 }, kind = "dot", status = "curse",
              initial_per_rank = 0.40, tick_per_rank = 0.40, spread = true },
            { id = "vampirism", name = "Vampirism", short = "V", tags = { "Lifesteal" },
              icon = V.specializations.necromancer_vampirism,
              desc = "Hits deal immediate and periodic damage and heal for half that damage.",
              accent = { 0.88, 0.18, 0.42, 0.95 }, kind = "vampirism", status = "vampirism",
              initial_per_rank = 0.20, tick_per_rank = 0.20, lifesteal_mult = 0.50 },
            { id = "summoner", name = "Summoner", short = "S", tags = { "Summon" },
              icon = V.specializations.necromancer_summoner,
              desc = "Marked kills raise skeleton mages; starts at two, +1 maximum per rank.",
              accent = { 0.88, 0.90, 0.78, 0.95 }, kind = "summon", status = "revive",
              cap_base = 2, cap_per_rank = 1 },
        },
    },
}

-- Necromancer assistants. Stats scale off the LIVE hero (hp_mult of hero max HP,
-- dps_mult of hero DPS) so gear and map depth carry the pack; caps live on the
-- specialization rows above (cap_base + cap_per_rank, hard-clamped by cap_max here).
Balance.minions = {
    skeleton = { kind = "ranged", hp_mult = 0.70, dps_mult = 0.85, range = 6.5,
        speed = 7.4, attack_interval = 0.70, duration = 35.0, cap_max = 6,
        color = { 0.86, 0.92, 0.78 }, scale = 1.0,
        bolt_color = { 0.62, 0.95, 0.72 }, bolt_scale = 0.22,
        texture = V.minions.skeleton.texture,
        sprite_sheet = V.minions.skeleton.sheet },
    imp = { kind = "ranged", hp_mult = 0.28, dps_mult = 0.35, range = 6.0,
        speed = 7.6, attack_interval = 0.9, duration = 15.0, cap_max = 3,
        color = { 0.95, 0.45, 0.22 }, scale = 0.85,
        bolt_color = { 1.0, 0.55, 0.25 }, bolt_scale = 0.22,
        texture = V.minions.imp.texture,
        sprite_sheet = V.minions.imp.sheet },
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

-- ---------------------------------------------------------------------------
-- Hero Grid 9/5 spec trees (docs/SPEC_TREE_DESIGN.md).
-- Every spec is a 9-point tree: keystone (the old rank-1 rider) -> two 2-rank
-- Foundation nodes whose endpoint equals the old rank-5 coefficients -> one
-- 1-of-2 Mutation choice -> two Technique nodes -> a bounded Capstone.
-- Primary spec caps at 9 (only it may take the capstone); the secondary caps
-- at 5; the third spec locks while two hold points. New characters start with
-- 1 point, then earn +1 per wave clear and +2 at boss entry, capped at 14.
-- ---------------------------------------------------------------------------
Balance.tree_rules = {
    primary_cap = 9, secondary_cap = 5, secondary_unlock = 5, point_cap = 14,
    gates = { keystone = 0, foundation = 1, mutation = 4, technique = 5, capstone = 7 },
    starting_points = 1, wave_points = 1, boss_points = 2,
    -- Legacy profiles banked unlimited points (+3/boss kill, no cap). Points
    -- above what the 14-point cap can ever spend convert to gold on load.
    excess_point_gold = 100,
}

-- Old rank N (1..5) maps onto this allocation order (save migration + tips).
Balance.tree_legacy_spine = { "key", "fa", "fb", "fa", "fb" }

-- Foundation per-rank adds by rider kind. `hi`/`lo` mark the biased dot split
-- (1.5x / 0.5x per_rank); everything else replays one old rank per rank so the
-- full spine lands exactly on the old rank-5 coefficients.
local function foundation_adds(spec)
    local k = spec.kind
    if k == "dot" or k == "vampirism" then
        local ipr, tpr = spec.initial_per_rank or 0.0, spec.tick_per_rank or 0.0
        return { initial = ipr * 1.5, tick = tpr * 0.5 }, { initial = ipr * 0.5, tick = tpr * 1.5 }
    elseif k == "stack_dot" then
        local a = { stack_per = spec.stack_rank_add or 0.10 }
        return a, { stack_per = spec.stack_rank_add or 0.10 }
    elseif k == "pierce" or k == "explosion" or k == "shockwave" then
        local a = { damage = spec.damage_per_rank or 0.10 }
        return a, { damage = spec.damage_per_rank or 0.10 }
    elseif k == "frost" then
        local a = { damage = spec.damage_per_rank or 0.0, slow = spec.slow_per_rank or 0.0 }
        return a, { damage = spec.damage_per_rank or 0.0, slow = spec.slow_per_rank or 0.0 }
    elseif k == "shadow" then
        local a = { damage = spec.damage_per_rank or 0.0, miss = spec.miss_per_rank or 0.0 }
        return a, { damage = spec.damage_per_rank or 0.0, miss = spec.miss_per_rank or 0.0 }
    elseif k == "daze" then
        local a = { reduction = spec.reduction_per_rank or 0.0 }
        return a, { reduction = spec.reduction_per_rank or 0.0 }
    elseif k == "preservation" then
        local a = { dr = spec.damage_reduction_per_rank or 0.0, heal = spec.heal_fraction_per_rank or 0.0 }
        return a, { dr = spec.damage_reduction_per_rank or 0.0, heal = spec.heal_fraction_per_rank or 0.0 }
    elseif k == "summon" then
        local a = { cap = spec.cap_per_rank or 1 }
        return a, { cap = spec.cap_per_rank or 1 }
    elseif k == "shard_cone" then
        local a = { damage = spec.damage_per_rank or 0.0, shards = spec.shards_per_rank or 1 }
        return a, { damage = spec.damage_per_rank or 0.0, shards = spec.shards_per_rank or 1 }
    elseif k == "frenzy" then
        -- Rework: additive buckets (no multiplicative double-dip). Keystone
        -- starts at 2%/stack; foundation lands the spine at 8%/stack so a
        -- full frenzy primary can clear deep maps without matching bleed.
        return { dmg_per_stack = 0.03 }, { as_per_stack = 0.03 }
    end
    return {}, {}
end

-- Per-spec tree identity: node names + capstone mechanics (WoW borrow-bank in
-- the design doc). Mutation/technique mechanics default per rider kind below;
-- `cap` is { name, kind, params }.
local TREE_FLAVOR = {
    ranger_poison = { fa = "Concentrated Dose", fb = "Slow-Release Venom",
        ma = "Epidemic", mb = "Predator's Dose", ta = "Numbing Venom", tb = "Toxic Recuperation",
        cap = { "Venom Burst", "proc_bonus", { every = 5, pct = 1.5, icd = 2.0 } } },
    ranger_bleed = { fa = "Jagged Broadheads", fb = "Deep Wounds",
        ma = "Quickening", mb = "Overwhelm", ta = "Weakening Cuts", tb = "Blood Rites",
        cap = { "Rupture", "max_stack_burst", { pct = 1.0, per_target_icd = 4.0 } } },
    ranger_piercing = { fa = "Sharpened Bodkins", fb = "Heavy Draw",
        ma = "Skewer", mb = "Longshot", ta = "Crippling Shafts", tb = "Punch-Through",
        cap = { "Sniper's Lane", "full_pierce", { every = 5 } } },
    brawler_bleed = { fa = "Lacerating Fists", fb = "Deep Wounds",
        ma = "Quickening", mb = "Overwhelm", ta = "Weakening Cuts", tb = "Blood Rites",
        cap = { "Bloodbath", "max_stack_burst", { pct = 1.0, per_target_icd = 4.0, heal = 0.5 } } },
    brawler_frenzy = { fa = "Savage Momentum", fb = "Accelerated Pulse",
        ma = "Relentless", mb = "Sixth Gear", ta = "Iron Fury", tb = "Bloodsport",
        cap = { "Breakneck", "proc_bonus", { every = 5, pct = 0.6, splash_pct = 0.3, splash_targets = 3, icd = 1.5 } } },
    brawler_shockwave = { fa = "Heavy Impact", fb = "Corpse Momentum",
        ma = "Wide Front", mb = "Stunning Wave", ta = "Fuse Discipline", tb = "Scavenger",
        cap = { "Seismic Chain", "chain_death", { mult = 0.5 } } },
    sower_explosion = { fa = "Volatile Pods", fb = "Packed Charges",
        ma = "Big Bang", mb = "Culling Blast", ta = "Fuse Discipline", tb = "Scavenger",
        cap = { "Soul Shatter", "chain_death", { mult = 0.5 } } },
    sower_seed = { fa = "Fertile Rot", fb = "Creeping Roots",
        ma = "Epidemic", mb = "Predator's Dose", ta = "Sapping Spores", tb = "Verdant Recovery",
        cap = { "Blooming Death", "death_burst", { pct = 0.5, radius = 2.5 } } },
    sower_thorns = { fa = "Barbed Growth", fb = "Hardened Spines",
        ma = "Quickening", mb = "Overwhelm", ta = "Weakening Barbs", tb = "Thorn Sap",
        cap = { "Bramble Ward", "status_amp", { amp = 0.15, at_max_stacks = true } } },
    mage_fire = { fa = "White Heat", fb = "Lingering Embers",
        ma = "Epidemic", mb = "Predator's Dose", ta = "Searing Dread", tb = "Cauterize",
        cap = { "Combustion", "detonate", { period = 8.0, pct = 1.0, targets = 2 } } },
    mage_frost = { fa = "Biting Cold", fb = "Deep Winter",
        ma = "Deep Freeze", mb = "Brittle", ta = "Chilling Presence", tb = "Winter's Grasp",
        cap = { "Shatter", "status_amp", { amp = 0.15 } } },
    mage_earth = { fa = "Heavy Shards", fb = "Splintering Force",
        ma = "Wide Spray", mb = "Dense Cores", ta = "Grinding Dust", tb = "Stone Skin",
        cap = { "Great Sundering", "shard_nova", { every = 6 } } },
    rogue_shadow = { fa = "Umbral Edge", fb = "Thicker Smoke",
        ma = "Blinding Smoke", mb = "Assassinate", ta = "Distraction", tb = "Fleet Shadow",
        cap = { "Symbols of Death", "aura_buff", { min_statused = 3, dmg = 0.15, dur = 4.0, icd = 8.0 } } },
    rogue_poison = { fa = "Deadly Brew", fb = "Numbing Toxin",
        ma = "Epidemic", mb = "Predator's Dose", ta = "Enfeebling Venom", tb = "Leeching Toxins",
        cap = { "Kingsbane", "status_amp", { amp = 0.20, elites_only = true } } },
    rogue_daggers = { fa = "Balanced Blades", fb = "Killer Instinct",
        ma = "Skewer", mb = "Longshot", ta = "Crippling Throws", tb = "Punch-Through",
        cap = { "Death from Above", "proc_bonus", { every = 5, pct = 0.4, splash_pct = 0.4, splash_targets = 3, icd = 1.5 } } },
    warrior_bleed = { fa = "Rending Strikes", fb = "Deep Wounds",
        ma = "Quickening", mb = "Overwhelm", ta = "Weakening Cuts", tb = "Blood Rites",
        cap = { "Bladestorm", "refresh_on_kill", { radius = 5.0 } } },
    warrior_daze = { fa = "Thunderous Blows", fb = "Rattling Force",
        ma = "Concussion", mb = "Lasting Daze", ta = "Demoralize", tb = "Battle Trance",
        cap = { "Demoralizing Shout", "debuff_amp", { extra = 0.10 } } },
    warrior_preservation = { fa = "Ignore Pain", fb = "Second Wind",
        ma = "Bulwark", mb = "Second Skin", ta = "Long Guard", tb = "Grim Harvest",
        cap = { "Last Stand", "guardian", { heal = 0.20, immune = 2.0 } } },
    necromancer_curse = { fa = "Deepening Malady", fb = "Grave Chill",
        ma = "Epidemic", mb = "Predator's Dose", ta = "Enfeebling Curse", tb = "Ghoulish Feast",
        cap = { "Malefic Rapture", "detonate", { period = 8.0, pct = 0.3, targets = 99 } } },
    necromancer_vampirism = { fa = "Crimson Hunger", fb = "Lingering Draught",
        ma = "Crimson Feast", mb = "Sanguine Ward", ta = "Red Thirst", tb = "Pallid Grasp",
        cap = { "Vampiric Blood", "low_hp_boost", { threshold = 0.4, mult = 2.0 } } },
    necromancer_summoner = { fa = "Restless Dead", fb = "Marrow Pact",
        ma = "Bone Fervor", mb = "Legion", ta = "Bone Armor", tb = "Soul Harvest",
        cap = { "Apocalypse", "summon_burst", { count = 4 } } },
}

-- Default mutation mechanics per rider kind: { kind_a, params_a, kind_b, params_b }.
local KIND_MUTATIONS = {
    dot = { "spread_plus", { radius = 5.5, targets = 2 }, "elite_mult", { mult = 1.2 } },
    stack_dot = { "fast_tick_max", { tick = 0.35 }, "double_stack_full", {} },
    pierce = { "skewer", { amp = 0.08, dur = 3.0 }, "longshot", { range = 1.5 } },
    frenzy = { "relentless", { dur = 5.0 }, "sixth_gear", { stacks = 1 } },
    frost = { "deep_slow", { slow = 0.12 }, "brittle", { amp = 0.08 } },
    shadow = { "blind", { miss = 0.08 }, "assassin", { mult = 1.2 } },
    daze = { "concussion", { reduction = 0.05 }, "lasting", { dur = 2.0 } },
    explosion = { "blast_radius", { add = 1.5 }, "elite_mult", { mult = 1.25 } },
    shockwave = { "blast_radius", { add = 1.5 }, "stun_wave", { daze = 0.2, dur = 2.0 } },
    summon = { "minion_dmg", { mult = 1.25 }, "legion", { cap = 1, dmg_mult = 0.8 } },
    vampirism = { "lifesteal_plus", { add = 0.15 }, "overheal_shield", { cap = 0.10 } },
    preservation = { "bulwark", { dr = 0.05 }, "second_skin", { heal = 0.05 } },
    shard_cone = { "wide_spray", { cone = 12.0, shards = 1 }, "dense_cores", { dmg = 0.10 } },
}

-- Default technique mechanics per rider kind: { kind_a, params_a, kind_b, params_b }.
local KIND_TECHNIQUES = {
    dot = { "status_dmg_down", { pct = 0.08 }, "rider_heal", { mult = 0.05, cap = 0.005 } },
    stack_dot = { "status_dmg_down", { pct = 0.08 }, "rider_heal", { mult = 0.05, cap = 0.005 } },
    pierce = { "cripple", { slow = 0.15, dur = 2.0 }, "punch_through", { dmg = 0.05, range = 0.5 } },
    frenzy = { "dr_at_max", { dr = 0.08 }, "kill_heal_max", { heal = 0.01, cap = 0.03 } },
    frost = { "status_dmg_down", { pct = 0.08 }, "long_status", { dur = 1.0 } },
    shadow = { "status_dmg_down", { pct = 0.08 }, "fleet", { move = 0.05 } },
    daze = { "status_dmg_down", { pct = 0.05 }, "kill_heal", { heal = 0.005, cap = 0.02 } },
    explosion = { "blast_dmg", { add = 0.10 }, "kill_heal", { heal = 0.005, cap = 0.02 } },
    shockwave = { "blast_dmg", { add = 0.10 }, "kill_heal", { heal = 0.005, cap = 0.02 } },
    summon = { "bone_armor", { dr = 0.01, cap = 0.06 }, "soul_harvest", { heal = 0.005, cap = 0.02 } },
    vampirism = { "lifesteal_plus", { add = 0.10 }, "status_dmg_down", { pct = 0.06 } },
    preservation = { "long_guard", { dur = 1.0 }, "kill_heal", { heal = 0.005, cap = 0.02 } },
    shard_cone = { "shard_slow", { slow = 0.15, dur = 2.0 }, "status_dmg_down", { pct = 0.06 } },
}

-- Plain-words, one sentence per node mechanic (EL falls back to EN via T at
-- render). Keystones use the spec's own desc; foundation lines are generated
-- from the stats they raise; mutations/techniques/capstones key off fx_kind.
-- Hand-written to read naturally and stay honest to compute_spec_fx.
local NODE_PLAIN = {
    -- mutations
    spread_plus = "When afflicted enemies die, the ailment leaps to nearby foes.",
    elite_mult = "Your ailment hits elites and bosses harder.",
    fast_tick_max = "At full stacks the ailment ticks much faster.",
    double_stack_full = "Hits on near-full-health enemies build stacks twice as fast.",
    skewer = "Enemies you pierce take extra damage from you for a while.",
    longshot = "Extends your attack range.",
    relentless = "Your stacks linger longer before fading.",
    sixth_gear = "Raises your maximum stack count.",
    deep_slow = "Your chill slows enemies even more.",
    brittle = "Chilled enemies take extra damage from you.",
    blind = "Thicker smoke makes enemies miss more often.",
    assassin = "You deal bonus damage to near-full-health enemies.",
    concussion = "Your daze weakens enemy attacks further.",
    lasting = "Your ailment lasts longer.",
    blast_radius = "Widens your death explosions.",
    stun_wave = "Enemies caught in the blast are slowed.",
    minion_dmg = "Your minions hit harder.",
    legion = "Raises your minion cap; the extra minions hit a little softer.",
    lifesteal_plus = "You heal for more of your rider damage.",
    overheal_shield = "Healing past full grants a temporary shield.",
    bulwark = "You take less damage while guarding.",
    second_skin = "Each guard also restores some health.",
    wide_spray = "Widens your shard cone and adds a shard.",
    dense_cores = "Your shards hit harder.",
    -- techniques
    status_dmg_down = "Afflicted enemies deal less damage to you.",
    rider_heal = "You heal for a share of this ailment's damage.",
    cripple = "Enemies you pierce are slowed.",
    punch_through = "Your pierce hits harder and reaches farther.",
    dr_at_max = "At full stacks you take less damage.",
    kill_heal_max = "Kills at full stacks heal you.",
    long_status = "Your ailment lasts longer.",
    fleet = "You move faster while your smoke is out.",
    kill_heal = "Your kills heal you a little.",
    blast_dmg = "Your death blasts hit harder.",
    bone_armor = "Each active minion reduces the damage you take.",
    soul_harvest = "Your kills heal you a little.",
    long_guard = "Extends your guard window.",
    shard_slow = "Your shards slow the enemies they hit.",
    -- capstones
    proc_bonus = "Every few hits detonate for a burst of bonus damage.",
    max_stack_burst = "Reaching full stacks bursts the target for heavy damage.",
    full_pierce = "Every few pierces strike for full damage.",
    chain_death = "Enemies killed by your blast explode again.",
    death_burst = "Afflicted enemies burst when they die, spreading damage.",
    status_amp = "Afflicted enemies take extra damage from you.",
    detonate = "Periodically detonates your ailments for big damage.",
    aura_buff = "With enough afflicted enemies nearby, you gain a burst of damage.",
    refresh_on_kill = "Bleeding kills smear fresh stacks onto nearby enemies.",
    debuff_amp = "Your daze saps even more enemy damage.",
    guardian = "Once per map, a lethal hit leaves you barely alive and briefly immune.",
    low_hp_boost = "While low on health, your healing riders heal for double.",
    shard_nova = "Every few hits erupt in extra shard sprays.",
    summon_burst = "Each boss fight begins by raising a squad of free skeletons.",
}

-- Plain phrase + canonical order for a foundation add key.
local ADD_PLAIN = {
    initial = "on-hit damage", tick = "damage-over-time", stack_per = "per-stack damage",
    damage = "rider damage", slow = "slow strength", miss = "miss chance",
    dmg_per_stack = "damage per stack", as_per_stack = "attack speed per stack",
    move_per_stack = "move speed per stack", reduction = "enemy weakening",
    dr = "damage reduction", heal = "regeneration", cap = "minion cap", shards = "shard count",
}
local ADD_ORDER = { initial = 1, tick = 2, stack_per = 3, damage = 4, slow = 5, miss = 6,
    dmg_per_stack = 7, as_per_stack = 8, move_per_stack = 9, reduction = 10, dr = 11,
    heal = 12, cap = 13, shards = 14 }

-- Returns the plain-words sentence for a tree node (never nil for a real node).
function Balance.node_plain(spec, node)
    if node.tier == "keystone" then return spec.desc or spec.name or spec.id end
    if node.fx_kind then return NODE_PLAIN[node.fx_kind] end
    if node.adds then
        local ks = {}
        for k in pairs(node.adds) do ks[#ks + 1] = k end
        table.sort(ks, function(a, b) return (ADD_ORDER[a] or 99) < (ADD_ORDER[b] or 99) end)
        local phrases = {}
        for _, k in ipairs(ks) do phrases[#phrases + 1] = ADD_PLAIN[k] or k end
        local joined
        if #phrases <= 1 then
            joined = phrases[1] or "power"
        elseif #phrases == 2 then
            joined = phrases[1] .. " and " .. phrases[2]
        else
            joined = table.concat(phrases, ", ", 1, #phrases - 1) .. " and " .. phrases[#phrases]
        end
        return "Strengthens your " .. joined .. "."
    end
    return spec.desc or node.name or node.id
end

-- Build Balance.spec_trees[class_id][spec_id] = ordered node list, and
-- Balance.tree_cards[class_id] = allocation cards (persisted by id in
-- run_cards, exactly like the old repeated spec cards).
Balance.spec_trees, Balance.tree_cards = {}, {}
for _, class in ipairs(Balance.classes) do
    if class.progressive_specializations then
        local trees, cards = {}, {}
        for _, spec in ipairs(class.specializations or {}) do
            local flavor = assert(TREE_FLAVOR[class.id .. "_" .. spec.id],
                "missing tree flavor: " .. class.id .. "_" .. spec.id)
            local muts = assert(KIND_MUTATIONS[spec.kind], "no mutations for kind " .. spec.kind)
            local techs = assert(KIND_TECHNIQUES[spec.kind], "no techniques for kind " .. spec.kind)
            local fa_add, fb_add = foundation_adds(spec)
            local gates = Balance.tree_rules.gates
            local nodes = {
                { id = "key", tier = "keystone", gate = gates.keystone, max_rank = 1,
                  name = spec.name },
                { id = "fa", tier = "foundation", gate = gates.foundation, max_rank = 2,
                  name = flavor.fa, adds = fa_add },
                { id = "fb", tier = "foundation", gate = gates.foundation, max_rank = 2,
                  name = flavor.fb, adds = fb_add },
                { id = "ma", tier = "mutation", gate = gates.mutation, max_rank = 1,
                  name = flavor.ma, choice = "m", fx_kind = muts[1], fx = muts[2] },
                { id = "mb", tier = "mutation", gate = gates.mutation, max_rank = 1,
                  name = flavor.mb, choice = "m", fx_kind = muts[3], fx = muts[4] },
                { id = "ta", tier = "technique", gate = gates.technique, max_rank = 1,
                  name = flavor.ta, fx_kind = techs[1], fx = techs[2] },
                { id = "tb", tier = "technique", gate = gates.technique, max_rank = 1,
                  name = flavor.tb, fx_kind = techs[3], fx = techs[4] },
                { id = "cap", tier = "capstone", gate = gates.capstone, max_rank = 1,
                  name = flavor.cap[1], primary_only = true,
                  fx_kind = flavor.cap[2], fx = flavor.cap[3] },
            }
            local by_id = {}
            for _, node in ipairs(nodes) do by_id[node.id] = node end
            trees[spec.id] = { spec = spec, nodes = nodes, by_id = by_id }
            for _, node in ipairs(nodes) do
                cards[#cards + 1] = {
                    id = "node_" .. class.id .. "_" .. spec.id .. "_" .. node.id,
                    name = node.name, rarity = "specialization",
                    class_id = class.id, specialization = spec.id,
                    tree_node = node.id, max_rank = node.max_rank,
                    accent = spec.accent,
                    -- class key: spec ids repeat across classes (ranger poison
                    -- vs rogue poison), and profiles carry every class's cards.
                    effect = { tree_node = { class = class.id, spec = spec.id, node = node.id } },
                }
            end
        end
        Balance.spec_trees[class.id] = trees
        Balance.tree_cards[class.id] = cards
    end
end

-- Every tree node must resolve a plain-words description and (for mechanic
-- nodes) an FX_DESC-covered fx_kind. Fail loudly at load if a tree adds a
-- mechanic without a matching plain line, so tooltips never fall back to a blank.
for _, class in ipairs(Balance.classes) do
    for spec_id, tree in pairs(Balance.spec_trees[class.id] or {}) do
        for _, node in ipairs(tree.nodes) do
            assert(Balance.node_plain(tree.spec, node) ~= nil,
                "missing plain description: " .. class.id .. "/" .. spec_id .. "/" .. node.id)
        end
    end
end

function Balance.spec_tree(class_id, spec_id)
    local trees = Balance.spec_trees[class_id]
    return trees and trees[spec_id]
end

function Balance.tree_card(class_id, spec_id, node_id)
    for _, card in ipairs(Balance.tree_cards[class_id] or {}) do
        if card.specialization == spec_id and card.tree_node == node_id then return card end
    end
end

-- Effective rider values from a tree allocation ({node_id = rank}). Returns a
-- flat fx table the duel runtime reads instead of rank-scaled coefficients.
function Balance.compute_spec_fx(class_id, spec, alloc)
    alloc = alloc or {}
    local fx = { points = 0 }
    for _, rank in pairs(alloc) do fx.points = fx.points + rank end
    if fx.points <= 0 or (alloc.key or 0) < 1 then return fx end
    local k = spec.kind
    -- Keystone base = the old rank-1 rider.
    if k == "dot" or k == "vampirism" then
        fx.initial, fx.tick = spec.initial_per_rank or 0.0, spec.tick_per_rank or 0.0
        fx.lifesteal_mult = spec.lifesteal_mult
    elseif k == "stack_dot" then
        fx.stack_per, fx.max_stacks = spec.stack_base or 0.20, spec.max_stacks or 5
    elseif k == "pierce" then
        fx.damage = spec.damage or 0.60
    elseif k == "frost" then
        fx.damage, fx.slow = spec.damage_per_rank or 0.0, spec.slow_per_rank or 0.0
        fx.duration = spec.duration or 3.0
    elseif k == "shadow" then
        fx.damage, fx.miss = spec.damage_per_rank or 0.0, spec.miss_per_rank or 0.0
        fx.duration = spec.duration or 3.0
    elseif k == "daze" then
        fx.reduction, fx.duration = spec.reduction_per_rank or 0.0, spec.duration or 3.0
    elseif k == "preservation" then
        fx.dr, fx.heal = spec.damage_reduction_per_rank or 0.0, spec.heal_fraction_per_rank or 0.0
        fx.heal_seconds = spec.heal_seconds or 5.0
    elseif k == "summon" then
        fx.cap = spec.cap_base or 2
    elseif k == "shard_cone" then
        fx.damage, fx.shards = spec.damage or 0.40, spec.shards_base or 4
        fx.cone_deg, fx.range, fx.speed = spec.cone_deg or 18.0, spec.range or 5.0, spec.speed or 15.0
    elseif k == "explosion" or k == "shockwave" then
        fx.damage, fx.radius = spec.damage or 0.0, spec.radius or 3.0
    elseif k == "frenzy" then
        fx.dmg_per_stack, fx.as_per_stack, fx.move_per_stack = 0.02, 0.02, 0.02
        fx.max_stacks, fx.duration = spec.max_stacks or 5, spec.duration or 3.0
    end
    -- Foundation, mutation, technique, capstone.
    local tree = Balance.spec_tree(class_id, spec.id)
    if not tree then return fx end
    for _, node in ipairs(tree.nodes) do
        local rank = alloc[node.id] or 0
        if rank > 0 then
            for key, add in pairs(node.adds or {}) do
                fx[key] = (fx[key] or 0.0) + add * rank
            end
            if node.fx_kind then
                fx[node.fx_kind] = node.fx or true
                if node.tier == "capstone" then
                    fx.capstone = { kind = node.fx_kind, params = node.fx or {} }
                end
            end
        end
    end
    if fx.sixth_gear then fx.max_stacks = (fx.max_stacks or 5) + (fx.sixth_gear.stacks or 1) end
    if fx.relentless then fx.duration = fx.relentless.dur or fx.duration end
    if fx.lifesteal_plus then fx.lifesteal_mult = (fx.lifesteal_mult or 0.0) + (fx.lifesteal_plus.add or 0.0) end
    if fx.long_status then fx.duration = (fx.duration or 3.0) + (fx.long_status.dur or 0.0) end
    if fx.lasting then fx.duration = (fx.duration or 3.0) + (fx.lasting.dur or 0.0) end
    if fx.deep_slow then fx.slow = (fx.slow or 0.0) + (fx.deep_slow.slow or 0.0) end
    if fx.blind then fx.miss = (fx.miss or 0.0) + (fx.blind.miss or 0.0) end
    if fx.concussion then fx.reduction = (fx.reduction or 0.0) + (fx.concussion.reduction or 0.0) end
    if fx.bulwark then fx.dr = (fx.dr or 0.0) + (fx.bulwark.dr or 0.0) end
    if fx.second_skin then fx.heal = (fx.heal or 0.0) + (fx.second_skin.heal or 0.0) end
    if fx.blast_radius then fx.radius = (fx.radius or 3.0) + (fx.blast_radius.add or 0.0) end
    if fx.blast_dmg then fx.damage = (fx.damage or 0.0) + (fx.blast_dmg.add or 0.0) end
    if fx.dense_cores then fx.damage = (fx.damage or 0.0) + (fx.dense_cores.dmg or 0.0) end
    if fx.wide_spray then
        fx.cone_deg = (fx.cone_deg or 18.0) + (fx.wide_spray.cone or 0.0)
        fx.shards = (fx.shards or 4) + (fx.wide_spray.shards or 0)
    end
    if fx.punch_through then
        fx.damage = (fx.damage or 0.0) + (fx.punch_through.dmg or 0.0)
        fx.range_add = fx.punch_through.range or 0.0
    end
    if fx.longshot then fx.range_add = (fx.range_add or 0.0) + (fx.longshot.range or 0.0) end
    if fx.legion then fx.cap = (fx.cap or 2) + (fx.legion.cap or 1) end
    return fx
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
        summon_archetype = "sprout", summon_every = 4.5,
        boss_arc = { windup = 0.8, radius = 5.5, range = 7.5, damage = 32.0, cooldown = 5.0, rest = 1.25 },
        boss_skill = { id = "ground_slam", windup = 0.9, radius = 4.6, damage = 30.0, knockback = 8.0, cooldown = 4.6 },
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
        summon_archetype = "stinger_drone", summon_every = 4.0,
        boss_arc = { windup = 0.8, radius = 5.5, range = 8.0, damage = 30.0, cooldown = 4.8, rest = 1.2 },
        boss_skill = { id = "dive_strafe", windup = 1.0, sweep = 0.55, damage = 26.0, cooldown = 4.8 },
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
        summon_archetype = "husk_knight", summon_every = 6.0,
        boss_arc = { windup = 0.8, radius = 6.0, range = 8.0, damage = 36.0, cooldown = 5.2, rest = 1.35 },
        boss_skill = { id = "popcorn_weather" },
        unset = { "tactical_role" } },
    popcorn_kernel = { base = "sprout", name = "Popcorn Kernel", threat_cost = 1, hp = 36, dps = 0.1,
        range = 0.1, speed = 0.1, scale = 0.75, knockback_resist = 1.0,
        hold_range = 99.0, anchor_hold = true, tint = { 1.45, 1.18, 0.42 } },
    -- Each ladder boss keeps a proven combat shell and adds one signature test.
    briar_matriarch = { base = "gourd_king", name = "Briar Matriarch", threat_cost = 20,
        hp = 3000, dps = 26.0, scale = 2.35,
        tint = { 1.0, 1.0, 1.0 },
        boss_skill = { id = "thorn_leash" } },
    bog_cantor = { base = "corn_colossus", name = "Bog Cantor", threat_cost = 20,
        hp = 1835, dps = 30.0, scale = 2.35,
        tint = { 1.0, 1.0, 1.0 },
        boss_skill = { id = "call_response" } },
    millwright_spectre = { base = "gourd_king", name = "Millwright Spectre", threat_cost = 20,
        hp = 3000, dps = 26.0, scale = 2.45,
        tint = { 1.0, 1.0, 1.0 },
        boss_skill = { id = "grind_schedule" } },
    fox = { base = "wasp_queen", name = "The Fox", threat_cost = 20,
        hp = 2840, dps = 24.0, scale = 2.85,
        tint = { 1.0, 1.0, 1.0 },
        boss_skill = { id = "vanish_pounce" } },
    feast_warden = { base = "gourd_king", name = "Feast Warden", threat_cost = 20,
        hp = 3000, dps = 26.0, scale = 2.5,
        tint = { 1.0, 1.0, 1.0 },
        boss_skill = { id = "dinner_bell" } },
    weathervane_horror = { base = "wasp_queen", name = "Weathervane Horror", threat_cost = 20,
        hp = 2840, dps = 24.0, scale = 2.7,
        tint = { 1.0, 1.0, 1.0 },
        boss_skill = { id = "gale_shift" } },
    pale_scarecrow = { base = "gourd_king", name = "Pale Scarecrow", threat_cost = 20,
        hp = 3000, dps = 26.0, scale = 2.7,
        tint = { 1.0, 1.0, 1.0 },
        boss_skill = { id = "reap_echo" } },
    wyrmroot_ascetic = { base = "corn_colossus", name = "Wyrmroot Ascetic", threat_cost = 20,
        hp = 1835, dps = 30.0, scale = 2.45,
        tint = { 1.0, 1.0, 1.0 },
        boss_skill = { id = "karmic_rosary" } },
    corn_court_herald = { base = "corn_colossus", name = "Corn Court Herald", threat_cost = 20,
        hp = 1835, dps = 30.0, scale = 2.5,
        tint = { 1.0, 1.0, 1.0 },
        boss_skill = { id = "royal_writ" } },
    king_of_ovrevand = { base = "gourd_king", name = "King of Ovrevand", threat_cost = 20,
        hp = 3000, dps = 26.0, scale = 2.75,
        tint = { 1.0, 1.0, 1.0 },
        boss_skill = { id = "royal_tribute" } },
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

for id, monster in pairs(Balance.monsters) do
    local art = assert(V.enemies[id], "missing visual enemy: " .. id)
    monster.texture = assert(art.texture, "missing enemy texture: " .. id)
    monster.sprite_sheet = assert(art.sheet, "missing enemy sheet: " .. id)
end

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
    { id = "spore_mask", slot = "helmet", rarity = "rare", name = "Spore Mask", weight = 8, tags = { "Regen", "Guard" },
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
    { id = "phase_steps", slot = "pants", rarity = "epic", name = "Phase Steps", weight = 5, tags = { "Dodge" },
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
    { id = "storm_loop", slot = "jewelry", rarity = "epic", name = "Storm Loop", tags = { "Flask", "Orbit" },
      desc = "+20% crit, +15% attack/move, flask burst", effect = { crit_add = 0.20, fire_interval_mult = 0.85, speed_mult = 1.15, kite_speed_mult = 1.15, whirl_add = 1, flask_burst = 0.65 } },
    -- boss-tier (rare pool feeds the Gourd King's shower)
    { id = "kings_crown", slot = "helmet", rarity = "rare", name = "King's Crown", weight = 16,
      desc = "+40 HP, +10% damage, +20% gold", effect = { hp_max_add = 40.0, dps_mult = 1.10, gold_find_add = 0.2 } },
    -- Map II/III expansion — deeper rarity ladders per slot, dodge
    -- synergy pieces, and boss-flavoured epics for the new maps.
    { id = "sentry_visor", slot = "helmet", rarity = "rare", name = "Sentry Visor", weight = 14,
      desc = "+25 HP, +1 cleave", effect = { hp_max_add = 25.0, cleave_add = 1 } },
    { id = "queens_diadem", slot = "helmet", rarity = "epic", name = "Queen's Diadem", weight = 8, tags = { "Dodge" },
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
    { id = "hive_locket", slot = "jewelry", rarity = "rare", name = "Hive Locket", weight = 0, tags = { "Regen", "Flask" },
      desc = "+15 HP, +2 regen, flask burst", effect = { hp_max_add = 15.0, regen_add = 2.0, gold_find_add = 0.10, flask_burst = 0.4 } },
    { id = "phase_charm", slot = "jewelry", rarity = "epic", name = "Phase Charm", weight = 0, tags = { "Dodge" },
      desc = "+1 dodge charge", effect = { dodge_charge_add = 1 } },
    { id = "kings_signet", slot = "jewelry", rarity = "epic", name = "King's Signet", weight = 0, tags = { "Flask", "Retaliation" },
      desc = "+25% gold, +12% damage, health nova", effect = { gold_find_add = 0.25, dps_mult = 1.12, flask_nova = 0.6 } },
    -- LEGENDARY (orange) — endgame drops, maps IX+. One per slot,
    -- ~1.6x epic power with a signature effect each.
    { id = "crown_of_ovrevand", slot = "helmet", rarity = "legendary", name = "Crown of Ovrevand", weight = 0, tags = { "Guard" },
      desc = "+100 HP, +20% armor, +15% attack speed", effect = { hp_max_add = 100.0, armor_add = 0.20, fire_interval_mult = 0.85 } },
    { id = "kingsguard_plate", slot = "body", rarity = "legendary", name = "Kingsguard Plate", weight = 0, tags = { "Guard", "Retaliation" },
      desc = "+140 HP, +25% armor, +2 regen, +12 thorns", effect = { hp_max_add = 140.0, armor_add = 0.25, regen_add = 2.0, thorns_add = 12.0 } },
    { id = "wyrmstriders", slot = "pants", rarity = "legendary", name = "Wyrmstriders", weight = 0, tags = { "Dodge" },
      desc = "+35% move, +1 dodge, dodge 30% faster", effect = { speed_mult = 1.35, kite_speed_mult = 1.35, dodge_charge_add = 1, dodge_recharge_mult = 0.70 } },
    { id = "reapers_grasp", slot = "gloves", rarity = "legendary", name = "Reaper's Grasp", weight = 0, tags = { "Bleed" },
      desc = "+24 damage, +35% attack speed, +15% crit", effect = { dps_add = 24.0, fire_interval_mult = 0.65, crit_add = 0.15 } },
    { id = "kingmaker", slot = "weapon", rarity = "legendary", name = "Kingmaker", weight = 0, tags = { "Cleave", "Orbit" },
      desc = "+45% damage, +3 cleave, +2 spin, crit bleed", effect = { dps_mult = 1.45, cleave_add = 3, whirl_add = 2, bleed_on_crit = 10.0 } },
    { id = "heart_of_the_hive", slot = "jewelry", rarity = "legendary", name = "Heart of the Hive", weight = 0, tags = { "Flask", "Bleed" },
      desc = "+3 lifesteal, +20% damage, +25% crit, flask burst", effect = { lifesteal_add = 3.0, dps_mult = 1.20, crit_add = 0.25, flask_burst = 0.85 } },
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
    -- Spine-equivalent: rank N mirrors the first N points of the legacy
    -- key→fa→fb→fa→fb order so old callers stay correct under trees.
    local alloc = {}
    for i = 1, math.min(rank, #Balance.tree_legacy_spine) do
        local nid = Balance.tree_legacy_spine[i]
        alloc[nid] = (alloc[nid] or 0) + 1
    end
    if rank > 0 then
        local fx = Balance.compute_spec_fx("warrior", spec, alloc)
        return fx.dr or 0.0, fx.heal or 0.0, fx.heal_seconds or spec.heal_seconds or 5.0
    end
    return 0.0, 0.0, spec.heal_seconds or 5.0
end

-- Legacy draft tip: maps old flat ranks 1..5 onto the tree spine and reads
-- live coefficients from compute_spec_fx (never a second formula).
function Balance.specialization_upgrade_text(class_id, id, current_rank)
    local function T(key, ...)
        local I18n = _G.ATH_I18N
        if I18n and I18n.t then return I18n.t(key, ...) end
        if select("#", ...) > 0 then return string.format(key, ...) end
        return key
    end
    local class = assert(class_by_id(class_id), "unknown balance class: " .. tostring(class_id))
    local spec = assert(Balance.specialization(class_id, id),
        "unknown specialization: " .. tostring(class_id) .. ":" .. tostring(id))
    local rank = math.max(1, math.floor(current_rank or 0) + 1)
    local function pct(value) return tostring(math.floor((value or 0) * 100.0 + 0.5)) .. "%" end
    local alloc = {}
    for i = 1, math.min(rank, #Balance.tree_legacy_spine) do
        local nid = Balance.tree_legacy_spine[i]
        alloc[nid] = (alloc[nid] or 0) + 1
    end
    local fx = Balance.compute_spec_fx(class_id, spec, alloc)
    local kind, sname = spec.kind, T(spec.name)
    if kind == "dot" then
        local spread = spec.spread and Balance.on_hit.spread_damage_mult or 1.0
        return T("Next rank: %s hit %s + %s per tick.\n%s",
            sname, pct((fx.initial or 0) * spread), pct((fx.tick or 0) * spread),
            T(spec.spread and "Spreads on death at half strength." or "Does not spread."))
    elseif kind == "stack_dot" then
        local per_stack = fx.stack_per or 0.20
        local values = {}
        for stack = 1, fx.max_stacks or spec.max_stacks or 5 do
            values[#values + 1] = pct(per_stack * stack)
        end
        return T("Next rank: %s deals %s hit damage on hit + per tick at 1-5 stacks.",
            sname, table.concat(values, "/"))
    elseif kind == "pierce" then
        return T("Next rank: piercing hit deals %s hit damage.\nCarries all on-hit effects.",
            pct(fx.damage or 0.0))
    elseif kind == "shard_cone" then
        return T("Next rank: %d rock shards past the hit, each %s hit damage (no riders).",
            fx.shards or 4, pct(fx.damage or 0.0))
    elseif kind == "frenzy" then
        local dmg = fx.dmg_per_stack or 0.02
        local stacks = fx.max_stacks or 5
        return T("Next rank: +%s damage, +%s attack speed, +%s move per stack; %s dmg at %d stacks for %.0fs.",
            pct(dmg), pct(fx.as_per_stack or dmg), pct(fx.move_per_stack or dmg),
            pct(dmg * stacks), stacks, fx.duration or 3.0)
    elseif kind == "explosion" or kind == "shockwave" then
        return T("Next rank: death %s deals %s hit damage in %.1f range.",
            T(kind), pct(fx.damage or 0.0), fx.radius or 3.0)
    elseif kind == "frost" then
        return T("Next rank: %s Frost damage; -%s move and attack speed for %.0fs.",
            pct(fx.damage or 0.0), pct(math.min(0.75, fx.slow or 0.0)), fx.duration or 3.0)
    elseif kind == "shadow" then
        return T("Next rank: %s pure damage; Smoke gives %s miss chance for %.0fs.",
            pct(fx.damage or 0.0), pct(math.min(0.75, fx.miss or 0.0)), fx.duration or 3.0)
    elseif kind == "daze" then
        return T("Next rank: -%s enemy damage, attack speed, and speed for %.0fs.",
            pct(math.min(0.75, fx.reduction or 0.0)), fx.duration or 3.0)
    elseif kind == "preservation" then
        return T("Next rank: after taking damage, gain %s damage reduction and restore %s max health over %.0fs.",
            pct(fx.dr or 0.0), pct(fx.heal or 0.0), fx.heal_seconds or 5.0)
    elseif kind == "vampirism" then
        return T("Next rank: %s hit + %s per tick; heals %s from each.",
            pct(fx.initial or 0.0), pct(fx.tick or 0.0),
            pct((fx.tick or 0.0) * (fx.lifesteal_mult or 0.0)))
    elseif kind == "summon" then
        return T("Next rank: skeleton-mage cap %d; each deals %s hit damage and inherits statuses.",
            math.min(Balance.minions.skeleton.cap_max, fx.cap or 2),
            pct(Balance.minions.skeleton.dps_mult))
    end
    return T(spec.desc)
end

function Balance.universal_upgrade_text(card, current_rank)
    local function T(key, ...)
        local I18n = _G.ATH_I18N
        if I18n and I18n.t then return I18n.t(key, ...) end
        if select("#", ...) > 0 then return string.format(key, ...) end
        return key
    end
    local rank = math.max(0, math.floor(current_rank or 0)) + 1
    if card.rank_id == "offense" then
        -- Additive from base: N ranks of +10% => +10N%, not 1.10^N.
        local per = (card.effect.dps_mult or 1.0) - 1.0
        return T("Next rank: +10%% damage and attack speed.\nTotal from cards: +%d%% each.",
            math.floor(per * rank * 100.0 + 0.5))
    elseif card.rank_id == "defense" then
        return T("Next rank: +20 max health and +3%% armor.\nTotal from cards: +%d health, +%d%% armor.",
            20 * rank, 3 * rank)
    elseif card.rank_id == "sustain" then
        return T("Next rank: +1%% max health/s.\nTotal from cards: +%d%% health/s.", rank)
    end
    return T(card.desc or "")
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
            row.on_hit[spec.id] = { kind = spec.kind, spread = spec.spread == true }
        end
        report.classes[class.id] = row
    end
    for id in pairs(Balance.monsters) do report.monsters[id] = Balance.monster_metrics(id) end
    return report
end

function Balance.audit()
    -- Upgrade-text checks look for English markers ("Next rank:", "Cost"). A saved
    -- EL locale would translate those and false-fail boot — pin EN for the audit.
    local I18n = _G.ATH_I18N
    local prev_lang = I18n and I18n.lang
    if I18n then I18n.lang = "en" end
    local ok, err = pcall(Balance._audit_body)
    if I18n then I18n.lang = prev_lang end
    assert(ok, err)
    return true
end

function Balance._audit_body()
    local item_ids = {}
    for _, class in ipairs(Balance.classes) do
        assert(class.id and class.hp_max > 0 and class.dps > 0 and class.hit, "invalid class balance row")
    end
    for id, monster in pairs(Balance.monsters) do
        assert(monster.hp > 0 and monster.dps >= 0 and monster.threat_cost > 0,
            "invalid monster balance row: " .. tostring(id))
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
    for _, class in ipairs(Balance.classes) do
        assert(#(class.specializations or {}) == 3, class.id .. " must have three specializations")
        for _, spec in ipairs(class.specializations) do
            assert(spec.kind and spec.status and spec.icon,
                "invalid on-hit specialization: " .. class.id)
            local upgrade = Balance.specialization_upgrade_text(class.id, spec.id, 0)
            assert(upgrade:find("Next rank:", 1, true),
                "missing specialization upgrade text: " .. class.id .. ":" .. spec.id)
            if spec.spread then
                assert(Balance.on_hit.spread_damage_mult == 0.50,
                    "spread specialization damage must remain at half strength: " .. class.id)
            end
        end
    end
    -- Hero Grid trees: identical structure across all 21 specs (the
    -- Dragonflight failure mode was inconsistent gate budgets per spec).
    local tree_card_ids = {}
    for _, class in ipairs(Balance.classes) do
        local trees = Balance.spec_trees[class.id]
        assert(trees, "missing spec trees for class " .. class.id)
        for _, spec in ipairs(class.specializations) do
            local tree = trees[spec.id]
            assert(tree and #tree.nodes == 8, class.id .. ":" .. spec.id .. " tree must have 8 nodes")
            local total, choice, capstones, keystones = 0, 0, 0, 0
            for _, node in ipairs(tree.nodes) do
                assert(node.max_rank >= 1 and node.gate ~= nil, "invalid tree node")
                total = total + node.max_rank
                if node.choice then choice = choice + 1 end
                if node.tier == "capstone" then
                    capstones = capstones + 1
                    assert(node.primary_only and node.gate == Balance.tree_rules.gates.capstone,
                        "capstone must be primary-only at gate 7: " .. class.id .. ":" .. spec.id)
                end
                if node.tier == "keystone" then keystones = keystones + 1 end
            end
            -- 9 spendable + the locked-out mutation twin = 10 rank capacity.
            assert(total == 10 and choice == 2 and capstones == 1 and keystones == 1,
                "tree shape mismatch: " .. class.id .. ":" .. spec.id)
            -- Full spine must land exactly on the old rank-5 rider values.
            local fx = Balance.compute_spec_fx(class.id, spec,
                { key = 1, fa = 2, fb = 2 })
            assert(fx.points == 5, "spine points mismatch")
            local k = spec.kind
            if k == "dot" or k == "vampirism" then
                assert(math.abs(fx.initial - (spec.initial_per_rank or 0) * 5) < 1e-6
                    and math.abs(fx.tick - (spec.tick_per_rank or 0) * 5) < 1e-6,
                    "dot spine endpoint drifted: " .. class.id .. ":" .. spec.id)
            elseif k == "stack_dot" then
                assert(math.abs(fx.stack_per - ((spec.stack_base or 0.2) + 4 * (spec.stack_rank_add or 0.1))) < 1e-6,
                    "stack spine endpoint drifted: " .. class.id .. ":" .. spec.id)
            elseif k == "pierce" then
                assert(math.abs(fx.damage - ((spec.damage or 0.6) + 4 * (spec.damage_per_rank or 0.1))) < 1e-6,
                    "pierce spine endpoint drifted: " .. class.id .. ":" .. spec.id)
            elseif k == "summon" then
                assert(fx.cap == (spec.cap_base or 2) + 4 * (spec.cap_per_rank or 1),
                    "summon spine endpoint drifted: " .. class.id)
            elseif k == "frost" then
                assert(math.abs(fx.damage - (spec.damage_per_rank or 0) * 5) < 1e-6
                    and math.abs(fx.slow - (spec.slow_per_rank or 0) * 5) < 1e-6,
                    "frost spine endpoint drifted: " .. class.id)
            elseif k == "shadow" then
                assert(math.abs(fx.damage - (spec.damage_per_rank or 0) * 5) < 1e-6
                    and math.abs(fx.miss - (spec.miss_per_rank or 0) * 5) < 1e-6,
                    "shadow spine endpoint drifted: " .. class.id)
            elseif k == "daze" then
                assert(math.abs(fx.reduction - (spec.reduction_per_rank or 0) * 5) < 1e-6,
                    "daze spine endpoint drifted: " .. class.id)
            elseif k == "preservation" then
                assert(math.abs(fx.dr - (spec.damage_reduction_per_rank or 0) * 5) < 1e-6
                    and math.abs(fx.heal - (spec.heal_fraction_per_rank or 0) * 5) < 1e-6,
                    "preservation spine endpoint drifted: " .. class.id)
            elseif k == "explosion" or k == "shockwave" then
                assert(math.abs(fx.damage - ((spec.damage or 0) + 4 * (spec.damage_per_rank or 0))) < 1e-6,
                    k .. " spine endpoint drifted: " .. class.id .. ":" .. spec.id)
            elseif k == "shard_cone" then
                assert(math.abs(fx.damage - ((spec.damage or 0) + 4 * (spec.damage_per_rank or 0))) < 1e-6
                    and fx.shards == (spec.shards_base or 4) + 4 * (spec.shards_per_rank or 1),
                    "shard_cone spine endpoint drifted: " .. class.id)
            elseif k == "frenzy" then
                -- Keystone 0.02 + foundation 2×0.03 on each bucket.
                assert(math.abs((fx.dmg_per_stack or 0) - 0.08) < 1e-6
                    and math.abs((fx.as_per_stack or 0) - 0.08) < 1e-6,
                    "frenzy spine endpoint drifted: " .. class.id)
            else
                error("unaudited rider kind: " .. tostring(k))
            end
        end
        for _, card in ipairs(Balance.tree_cards[class.id] or {}) do
            assert(card.id and not tree_card_ids[card.id], "duplicate tree card id: " .. tostring(card.id))
            tree_card_ids[card.id] = true
            assert(card.effect and card.effect.tree_node, "tree card missing effect")
        end
    end
    assert(#Balance.tree_legacy_spine == 5, "legacy spine must cover old ranks 1..5")
    assert(#Balance.draft_cards == 3, "exactly three universal upgrades are required")
    local p1_reduction, p1_healing = Balance.preservation_effect(1)
    local p5_reduction, p5_healing = Balance.preservation_effect(5)
    assert(math.abs(p1_reduction - 0.10) < 0.0001 and math.abs(p1_healing - 0.05) < 0.0001
        and math.abs(p5_reduction - 0.50) < 0.0001 and math.abs(p5_healing - 0.25) < 0.0001,
        "Warrior Preservation scaling must be 10% reduction and 5% healing per rank")
    -- Frenzy tip must describe additive tree values, not the retired 10%/stack.
    local frenzy_tip = Balance.specialization_upgrade_text("brawler", "frenzy", 0)
    assert(frenzy_tip:find("+2% damage", 1, true),
        "frenzy upgrade text must mirror compute_spec_fx keystone: " .. frenzy_tip)
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

assert(Balance.audit())

_G.ATH_BALANCE = Balance
return Balance
