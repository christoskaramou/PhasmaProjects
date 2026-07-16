-- Paper balance harness — simulates full arena runs from ath_balance.lua alone.
-- No engine, no player: run via `python tools/paper_balance.py`.
--
-- Everything tunable is read live from Balance (budgets, auto_mix, monsters,
-- items, riders, map progression), so edits to ath_balance.lua flow straight
-- into the sim. The only paper-model inventions are the ASSUME knobs below:
-- positioning and player-skill abstractions the real game resolves with a mouse.
--
-- Modeled: waves/budgets/auto_mix spawn stream, elites (expected value),
-- splits, summoners, walking bombs, boss + arcs + phase2 + adds, gear, draft
-- cards, specialization on-hit riders (EV, always armed), in-run item drops
-- (rarity-averaged), flasks, armor/lifesteal/regen/thorns, gold economy.
-- NOT modeled (v1): charge-hit spikes beyond sustained dps, knockback, dodge
-- charges, spread-on-death bonus targets, retaliation/nova gear.

local ROOT = PAPER_ROOT or "."
local ARGS = PAPER_ARGS or {}
local Balance = dofile(ROOT .. "/Assets/Scripts/shared/ath_balance.lua")
local R = Balance.rules

-- Paper-model assumptions (player skill / geometry abstractions).
local ASSUME = {
    dt = 0.05,
    spawn_distance = 13.0,          -- wall spawns to a mid-arena hero
    -- Exposure: every creep is slower than the hero's kite speed, so contact
    -- for ranged heroes only lands in cornered moments; shooters are mostly
    -- outranged and dodged. Melee heroes face contact at their damage uptime.
    contact_exposure_ranged = 0.10,
    projectile_exposure_ranged = 0.20,
    projectile_exposure_melee = 0.35,
    contact_cap = 7,                -- bodies that can physically ring the hero
    telegraph_hit_fraction = 0.35,  -- windup-telegraphed hits (bombs, boss arcs) that land
    boss_armor_uptime = 0.85,       -- armor breaks only on rider "skill" hits (5s windows)
    melee_hits_per_second = 2.0,    -- melee hit-event rate (lifesteal / riders / refill)
    whirl_targets_cap = 6,          -- bodies inside the spin radius at swarm density
    ranged_closing_delay = 1.0,     -- hero repositioning before a held ranged creep is shootable
    between_wave_downtime = 10.0,   -- draft pause: regen ticks, no combat
    wave_timeout = 240.0,           -- stalled = hero DPS can't beat the budget
    flask_use_fraction = 0.45,      -- drink when hp dips below this
    interval_ramp = 0.05,           -- duel default, not in Balance.rules
    reserve_add = 40.0,             -- manual_wave_budget fallback beyond wave_budgets[]
    big_cost = 6,                   -- TELEGRAPH_BIG_COST coin bonus threshold
    rider_coverage = 0.7,           -- debuff riders reach this share of attackers
    avg_stack_fraction = 0.6,       -- average stacks held vs max_stacks
    stack_tick_fraction = 0.5,      -- stacks ramp, so ticks average half strength
    splash_ev = 0.6,                -- death explosions/shockwaves that hit a neighbour
    elite_drop_chance = 0.20,       -- guaranteed-roll chance on elite kills (duel value)
}

-- ---------------------------------------------------------------------------
-- Monster templates: Balance rows only (art/behaviour bases stubbed empty).
local stub = setmetatable({}, { __index = function() return {} end })
local MON = Balance.build_monsters(stub)

local MAP_BOSSES = { "gourd_king", "wasp_queen", "corn_colossus" } -- mode.lua cycle
local MAPS = {}
for i = 1, #Balance.map_progression.rank do MAPS[i] = { boss = MAP_BOSSES[(i - 1) % 3 + 1] } end
Balance.apply_map_progression(MAPS)

-- ---------------------------------------------------------------------------
-- Hero build: mirrors Duel apply_gear_effect. Unknown keys are a hard error so
-- this harness can never silently drift behind new item effects.
local function clampn(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local NONCOMBAT = { dash_add = 1, pickup_range_add = 1, slow_aura = 1, dodge_blades = 1,
    retaliation_orbit = 1, flask_nova = 1, flask_burst = 1, bleed_on_crit = 1,
    dodge_charge_add = 1, dodge_recharge_mult = 1, upgrade_rank = 1, specialization_rank = 1, heal = 1 }
local COMBAT = { dps_mult = 1, dps_add = 1, cleave_add = 1, attack_range_add = 1,
    speed_mult = 1, kite_speed_mult = 1, hp_max_add = 1, armor_add = 1, lifesteal_add = 1,
    regen_add = 1, whirl_add = 1, thorns_add = 1, fire_interval_mult = 1, crit_add = 1,
    gold_find_add = 1 }

-- Mirrors Duel apply_gear_effect: *_mult is additive from the hero's starting
-- (base) values captured once in build_hero, not compounded on current.
local function apply_effect(hero, effect)
    for k in pairs(effect) do
        if not NONCOMBAT[k] and not COMBAT[k] then
            error("paper harness out of date: unknown effect key '" .. k .. "'")
        end
    end
    local ref = hero._ref or hero
    if effect.dps_mult then
        hero.dps = hero.dps + (ref.dps or 0.0) * (effect.dps_mult - 1.0)
    end
    if effect.dps_add then hero.dps = hero.dps + effect.dps_add end
    if effect.cleave_add then hero.cleave = hero.cleave + effect.cleave_add end
    if effect.attack_range_add then hero.attack_range = hero.attack_range + effect.attack_range_add end
    if effect.speed_mult then
        hero.speed = hero.speed + (ref.speed or 0.0) * (effect.speed_mult - 1.0)
    end
    if effect.kite_speed_mult then
        hero.kite_speed = hero.kite_speed + (ref.kite_speed or ref.speed or 0.0) * (effect.kite_speed_mult - 1.0)
    end
    if effect.hp_max_add then hero.hp_max = hero.hp_max + effect.hp_max_add end
    if effect.armor_add then hero.armor = clampn((hero.armor or 0.0) + effect.armor_add, -0.5, 0.85) end
    if effect.lifesteal_add then hero.lifesteal = (hero.lifesteal or 0.0) + effect.lifesteal_add end
    if effect.regen_add then hero.regen = (hero.regen or 0.0) + effect.regen_add end
    if effect.whirl_add then hero.whirl = (hero.whirl or 0) + effect.whirl_add end
    if effect.thorns_add then hero.thorns = (hero.thorns or 0.0) + effect.thorns_add end
    if effect.fire_interval_mult and hero.fire_interval then
        hero._as_pct = (hero._as_pct or 0.0) + (1.0 / effect.fire_interval_mult - 1.0)
        local bfi = ref.fire_interval or hero.fire_interval
        hero.fire_interval = bfi / math.max(0.05, 1.0 + hero._as_pct)
    end
    if effect.crit_add then hero.crit_chance = (hero.crit_chance or 0.0) + effect.crit_add end
    if effect.gold_find_add then hero.gold_find = (hero.gold_find or 1.0) + effect.gold_find_add end
end

local function item_by_id(id)
    for _, item in ipairs(Balance.items) do if item.id == id then return item end end
    error("unknown item: " .. tostring(id))
end

local function class_by_id(id)
    for _, c in ipairs(Balance.classes) do if c.id == id then return c end end
    error("unknown class: " .. tostring(id))
end

local function build_hero(class_id, gear_ids)
    local c = class_by_id(class_id)
    local hero = { id = c.id, attack = c.attack, hp_max = c.hp_max, dps = c.dps,
        cleave = c.cleave or 1, attack_range = c.attack_range, fire_interval = c.fire_interval,
        speed = c.speed, kite_speed = c.kite_speed, armor = c.armor or 0.0,
        lifesteal = c.lifesteal or 0.0, regen = c.regen or 0.0, whirl = c.whirl or 0,
        thorns = 0.0, crit_chance = R.crit.base_chance, gold_find = 1.0, spec_rank = 0 }
    hero._ref = { dps = hero.dps, speed = hero.speed, kite_speed = hero.kite_speed,
        fire_interval = hero.fire_interval, attack_range = hero.attack_range }
    for _, id in ipairs(gear_ids or {}) do apply_effect(hero, item_by_id(id).effect) end
    return hero
end

-- In-run drops: the average effect of one item of a rarity (mult keys averaged
-- as offsets from 1.0). Applied as fractional gear whenever the drop cadence
-- (drop_every kills, elite/boss rolls) grants an item.
local AVG_DROP = {}
for _, item in ipairs(Balance.items) do
    local bucket = AVG_DROP[item.rarity] or { n = 0, sum = {} }
    bucket.n = bucket.n + 1
    for k, v in pairs(item.effect) do
        if COMBAT[k] then
            local off = k:find("_mult") and (v - 1.0) or (v == true and 0.0 or v)
            bucket.sum[k] = (bucket.sum[k] or 0.0) + off
        end
    end
    AVG_DROP[item.rarity] = bucket
end
-- Expected effect of one drop on this map: rarity-weighted mix of the
-- per-rarity average items (mult keys handled as offsets from 1.0).
local function avg_drop_effect(map)
    local effect, total = {}, 0.0
    for _, w in pairs(map.drop_weights or {}) do total = total + w end
    for rarity, w in pairs(total > 0 and map.drop_weights or { common = 1 }) do
        local bucket = AVG_DROP[rarity]
        if bucket and w > 0 then
            for k, sum in pairs(bucket.sum) do
                effect[k] = (effect[k] or 0.0) + (sum / bucket.n) * (w / math.max(total, 1))
            end
        end
    end
    for k, v in pairs(effect) do
        if k:find("_mult") then effect[k] = 1.0 + v end
    end
    return effect
end

-- ---------------------------------------------------------------------------
-- Specialization riders — Hero Grid edition. EV is computed from the SAME
-- Balance.compute_spec_fx table the game runtime reads, so tree coefficients
-- flow through with no second copy. Mutations/techniques/capstones fold in as
-- EV adjustments (documented inline). Units: one basic hit's damage —
-- `initial` per landed hit, `dot` per dotted target per second.
local function rider_ev(spec, fx)
    if not fx or (fx.points or 0) < 1 then return {} end
    local k = spec.kind
    local spread_mult = spec.spread and Balance.on_hit.spread_damage_mult or 1.0
    local ev = {}
    if k == "dot" or k == "vampirism" then
        -- vampirism never spreads, so its spread_mult is already 1.0
        local tick_amount = (fx.tick or 0) * spread_mult
        ev.initial = (fx.initial or 0) * spread_mult
        ev.dot = tick_amount / Balance.on_hit.tick
        if spec.spread then
            -- Spread-on-death re-applies to spread_targets neighbours.
            local targets = fx.spread_plus and (fx.spread_plus.targets or 2) or 1
            ev.spread_kill = tick_amount * (1.0 + 0.5 * Balance.on_hit.duration / Balance.on_hit.tick)
                * targets
        end
        ev.heal_mult = fx.lifesteal_mult or (fx.rider_heal and fx.rider_heal.mult) or 0.0
        if fx.capstone and fx.capstone.kind == "low_hp_boost" then
            ev.heal_mult = ev.heal_mult * 1.3 -- EV of the sub-40% double
        end
    elseif k == "stack_dot" then
        local amount = (fx.stack_per or 0.2) * (fx.max_stacks or 5) * ASSUME.avg_stack_fraction
        ev.initial = amount
        ev.dot = amount / Balance.on_hit.tick * ASSUME.stack_tick_fraction
        if fx.fast_tick_max then ev.dot = ev.dot * 1.15 end -- max-stack fast ticks
        if fx.double_stack_full then ev.initial = ev.initial * 1.1 end -- faster ramp
        ev.heal_mult = fx.rider_heal and fx.rider_heal.mult or nil
        if fx.capstone and fx.capstone.kind == "max_stack_burst" then
            -- One burst per target per ICD while at max stacks.
            ev.dot = ev.dot + (fx.capstone.params.pct or 1.0)
                / (fx.capstone.params.per_target_icd or 4.0) * 0.6
        end
        if fx.capstone and fx.capstone.kind == "refresh_on_kill" then
            ev.spread_kill = (ev.spread_kill or 0) + 0.5 -- bleed smear on kills
        end
    elseif k == "pierce" then
        ev.extra_target = fx.damage or 0.6
        if fx.capstone and fx.capstone.kind == "full_pierce" then
            ev.extra_target = ev.extra_target
                + (1.0 - (fx.damage or 0.6)) / (fx.capstone.params.every or 5)
        end
        if fx.skewer then ev.dps_mult = (ev.dps_mult or 1.0) * (1.0 + (fx.skewer.amp or 0.08) * 0.7) end
        if fx.cripple then ev.avoid = (ev.avoid or 0) + 0.03 end
    elseif k == "explosion" or k == "shockwave" then
        ev.on_kill = (fx.damage or 0) * ASSUME.splash_ev * 2.0 -- ~2 neighbours splashed
        if fx.capstone and fx.capstone.kind == "chain_death" then
            ev.on_kill = ev.on_kill * (1.0 + (fx.capstone.params.mult or 0.5) * 0.4)
        end
        if fx.stun_wave then ev.avoid = (ev.avoid or 0) + 0.02 end
        if fx.kill_heal then ev.regen_frac = (ev.regen_frac or 0) + 0.001 end
    elseif k == "frost" then
        ev.initial = fx.damage or 0
        ev.avoid = math.min(0.75, fx.slow or 0) * 0.5
    elseif k == "shadow" then
        ev.initial = fx.damage or 0
        ev.avoid = math.min(0.75, fx.miss or 0)
        if fx.capstone and fx.capstone.kind == "aura_buff" then
            local p = fx.capstone.params
            ev.dps_mult = (ev.dps_mult or 1.0)
                * (1.0 + (p.dmg or 0.15) * (p.dur or 4.0) / ((p.icd or 8.0) + (p.dur or 4.0)))
        end
    elseif k == "daze" then
        local reduction = fx.reduction or 0
        if fx.capstone and fx.capstone.kind == "debuff_amp" then
            reduction = reduction + (fx.capstone.params.extra or 0.10)
        end
        ev.avoid = math.min(0.75, reduction)
    elseif k == "frenzy" then
        local stacks = (fx.max_stacks or 5) * ASSUME.avg_stack_fraction
        -- Additive buckets multiply out: damage x attack rate (both stack-fed).
        ev.dps_mult = (1.0 + (fx.dmg_per_stack or 0.01) * stacks)
            * (1.0 + (fx.as_per_stack or 0.01) * stacks)
        if fx.dr_at_max then ev.avoid = (ev.avoid or 0) + (fx.dr_at_max.dr or 0.08) * 0.6 end
        if fx.kill_heal_max then ev.regen_frac = (ev.regen_frac or 0) + 0.002 end
    elseif k == "preservation" then
        ev.avoid = (fx.dr or 0) * 0.8
        local seconds = (fx.heal_seconds or 5.0) + (fx.long_guard and fx.long_guard.dur or 0.0)
        ev.regen_frac = (fx.heal or 0) / seconds * 0.5
        if fx.capstone and fx.capstone.kind == "guardian" then ev.guardian = true end
    elseif k == "summon" then
        local cap = math.min(Balance.minions.skeleton.cap_max, fx.cap or 2)
        local dmg_mult = (fx.minion_dmg and (fx.minion_dmg.mult or 1.25) or 1.0)
            * (fx.legion and (fx.legion.dmg_mult or 0.8) or 1.0)
        ev.pack_dps_mult = Balance.minions.skeleton.dps_mult * cap * dmg_mult
        ev.tank = 0.15
        if fx.bone_armor then ev.avoid = (ev.avoid or 0) + math.min(fx.bone_armor.cap or 0.06,
            (fx.bone_armor.dr or 0.01) * cap) * 0.7 end
        if fx.soul_harvest then ev.regen_frac = (ev.regen_frac or 0) + 0.001 end
        if fx.capstone and fx.capstone.kind == "summon_burst" then
            ev.pack_dps_mult = ev.pack_dps_mult
                + Balance.minions.skeleton.dps_mult * (fx.capstone.params.count or 4) * 0.3
        end
    elseif k == "shard_cone" then
        -- Shards hit every enemy in the cone: pack damage per landed hit.
        local per = (fx.damage or 0.4) * (fx.shards or 4)
        ev.extra_target = per * 0.35 -- cone coverage of the swarm
        if fx.shard_slow then ev.avoid = (ev.avoid or 0) + 0.03 end
        if fx.capstone and fx.capstone.kind == "shard_nova" then
            ev.extra_target = ev.extra_target * (1.0 + 3.0 / (fx.capstone.params.every or 6))
        end
    end
    -- Cross-kind extras.
    if fx.status_dmg_down then
        ev.avoid = (ev.avoid or 0) + (fx.status_dmg_down.pct or 0.08) * ASSUME.rider_coverage
    end
    if fx.elite_mult then ev.boss_mult = fx.elite_mult.mult or 1.2 end
    if fx.assassin then ev.dps_mult = (ev.dps_mult or 1.0) * 1.03 end -- full-HP first hits
    if fx.brittle then ev.dps_mult = (ev.dps_mult or 1.0) * (1.0 + (fx.brittle.amp or 0.08) * 0.8) end
    local cap = fx.capstone
    if cap and cap.kind == "proc_bonus" then
        local p = cap.params
        ev.initial = (ev.initial or 0) + (p.pct or 1.0) / (p.every or 5)
            + (p.splash_pct or 0) * (p.splash_targets or 0) * ASSUME.splash_ev / (p.every or 5)
    elseif cap and cap.kind == "status_amp" then
        local p = cap.params
        if p.elites_only then
            ev.boss_mult = (ev.boss_mult or 1.0) * (1.0 + (p.amp or 0.2) * 0.9)
        else
            ev.dps_mult = (ev.dps_mult or 1.0) * (1.0 + (p.amp or 0.15) * 0.8)
        end
    elseif cap and cap.kind == "detonate" then
        ev.dot = (ev.dot or 0) * ((cap.params.targets or 1) > 1 and 1.15 or 1.10)
    elseif cap and cap.kind == "death_burst" then
        ev.spread_kill = (ev.spread_kill or 0) * (1.0 + (cap.params.pct or 0.5))
    end
    return ev
end

-- Merge the primary and secondary riders into one EV table.
local function merge_ev(evs)
    local m = {}
    for _, ev in ipairs(evs) do
        m.initial = (m.initial or 0) + (ev.initial or 0)
        m.dot = (m.dot or 0) + (ev.dot or 0)
        m.extra_target = (m.extra_target or 0) + (ev.extra_target or 0)
        m.on_kill = (m.on_kill or 0) + (ev.on_kill or 0)
        m.spread_kill = (m.spread_kill or 0) + (ev.spread_kill or 0)
        m.pack_dps_mult = (m.pack_dps_mult or 0) + (ev.pack_dps_mult or 0)
        m.regen_frac = (m.regen_frac or 0) + (ev.regen_frac or 0)
        m.dps_mult = (m.dps_mult or 1.0) * (ev.dps_mult or 1.0)
        m.boss_mult = (m.boss_mult or 1.0) * (ev.boss_mult or 1.0)
        m.avoid = 1.0 - (1.0 - (m.avoid or 0)) * (1.0 - math.min(0.75, ev.avoid or 0))
        m.heal_mult = math.max(m.heal_mult or 0, ev.heal_mult or 0)
        m.tank = math.max(m.tank or 0, ev.tank or 0)
        m.guardian = m.guardian or ev.guardian
    end
    m.avoid = math.min(0.75, m.avoid or 0)
    return m
end

-- The canonical scripted build order for one spec tree (acceptance baseline):
-- keystone -> damage foundation -> mutation (prefer longshot on pierce) ->
-- techniques -> capstone.
local function spine_primary_for(spec)
    local mut = (spec.kind == "pierce") and "mb" or "ma"
    return { "key", "fa", "fa", "fb", "fb", mut, "ta", "tb", "cap" }
end
local SPINE_SECONDARY = { "key", "fa", "fa", "fb", "fb" }

local function spec_score(class, spec)
    local fx = Balance.compute_spec_fx(class.id, spec, { key = 1, fa = 2, fb = 2 })
    local ev = rider_ev(spec, fx)
    -- Deep maps are sustain-bound: avoid/heal/DoT weigh beside pack EV so
    -- paper prefers fire/shadow/vampirism over glass shard/curse primaries.
    return 2.0 * (ev.initial or 0) + 2.5 * (ev.dot or 0) + 1.0 * (ev.extra_target or 0)
        + (ev.on_kill or 0) + (ev.spread_kill or 0) * 0.4
        + ((ev.dps_mult or 1) - 1) * 3.0 + (ev.pack_dps_mult or 0) * 1.5
        + (ev.avoid or 0) * 6.0 + (ev.heal_mult or 0) * 14.0
        + (ev.regen_frac or 0) * 40.0 + (ev.guardian and 1.0 or 0)
end

-- Primary = requested tree (or best damage tree); secondary = next best.
local function pick_specs(class, requested_spec)
    local scored = {}
    for _, spec in ipairs(class.specializations or {}) do
        scored[#scored + 1] = { spec = spec, s = spec_score(class, spec) }
    end
    table.sort(scored, function(a, b) return a.s > b.s end)
    local primary = scored[1].spec
    if requested_spec then
        primary = Balance.specialization(class.id, requested_spec) or primary
    end
    local secondary
    for _, row in ipairs(scored) do
        if row.spec.id ~= primary.id then secondary = row.spec; break end
    end
    return primary, secondary
end

-- Hero damage output vs `engaged` targets — basic_metrics math on the geared
-- hero, crit as EV, precomputed rider dps folded in.
local function hero_output(hero, engaged, rider_dps, ev)
    if engaged <= 0 then return 0.0, 0 end
    local hits = math.min(engaged, hero.cleave or 1)
    local primary
    if hero.attack == "ranged" then
        primary = hero.dps * R.basic_attack.ranged_damage_mult / hero.fire_interval * hits
    else
        primary = hero.dps * (1.0 + math.max(0, hits - 1) * R.basic_attack.melee_secondary_mult)
    end
    primary = primary * (ev.dps_mult or 1.0)
    local whirl = (hero.whirl or 0) * hero.dps
        * (hero.attack == "melee" and R.whirl.melee_damage_mult / R.whirl.melee_cooldown
            or R.whirl.ranged_damage_mult / R.whirl.cooldown)
        * math.min(engaged, ASSUME.whirl_targets_cap)
    local pack = (ev.pack_dps_mult or 0.0) * hero.dps
    local crit_ev = 1.0 + (hero.crit_chance or 0.0) * (R.crit.damage_mult - 1.0)
    return (primary + rider_dps + whirl) * crit_ev + pack, hits
end

-- ---------------------------------------------------------------------------
-- Duel pacing mirrors (ath_duel.lua spawn_interval / batch_size / live_cap /
-- manual_wave_budget).
local S = R.arena.spawn
local function spawn_interval(t) return math.max(S.interval_min, S.interval_start - ASSUME.interval_ramp * (t / 10.0)) end
local function batch_size(t) return math.min(S.batch_max, S.batch_start + math.floor(t / 16.0)) end
local function live_cap(t) return math.min(S.cap_max, S.cap_start + math.floor(t / 8.0) * 4) end

local function wave_budget(wave, map)
    local budgets = R.arena.wave_budgets
    if budgets[wave] then return budgets[wave] * map.budget_mult end
    return (R.arena.reserve_start + (wave - 1) * ASSUME.reserve_add) * map.budget_mult
end

-- ---------------------------------------------------------------------------
-- Run simulation: one hero through every wave of one map, then the boss.
local function make_creep(state, arch, elite, near)
    local def = MON[arch]
    if not def then return nil end
    local map = state.map
    local hp = def.hp * R.arena.creep_hp_mult * map.hp_mult * (elite and R.enemy.elite_hp_mult or 1.0)
    local dps = def.dps * map.dps_mult * (elite and R.enemy.elite_dps_mult or 1.0)
    local dist = near and 2.0 or ASSUME.spawn_distance
    local hold = def.hold_range or (def.projectile and def.range) or nil
    local stop = hold or (def.range or 0.5)
    local arrive = math.max(0.0, (dist - stop) / math.max(0.5, def.speed))
    local in_range = math.max(0.0, (dist - math.max(state.hero.attack_range, stop)) / math.max(0.5, def.speed))
    if hold and hold > state.hero.attack_range then in_range = in_range + ASSUME.ranged_closing_delay end
    return { arch = arch, def = def, hp = hp, dps = dps, elite = elite,
        ranged = def.projectile ~= nil, boss = def.boss == true,
        arrive_at = state.t + arrive, in_range_at = state.t + in_range,
        exploded = false, next_summon = def.summon_every and (state.t + def.summon_every) or nil,
        threat = def.threat_cost or 1 }
end

local function alive_count(state)
    local n = 0
    for _, c in ipairs(state.creeps) do if c.hp > 0 then n = n + 1 end end
    return n
end

local function elite_roll(state, cost)
    if state.wave < 2 or cost > 5 then return false end
    local p = R.enemy.elite_base_chance + R.enemy.elite_wave_chance * state.wave
        + (state.map.elite_bonus or 0.0)
    state.elite_acc = state.elite_acc + p -- deterministic error diffusion
    if state.elite_acc >= 1.0 then state.elite_acc = state.elite_acc - 1.0; return true end
    return false
end

local function grant_drop(state)
    state.drops = state.drops + 1
    -- Six gear slots: only the first six drops of the map's rarity mix are
    -- upgrades; the rest are vendor trash (the real game replaces, not stacks).
    if state.drops <= 6 then
        apply_effect(state.hero, avg_drop_effect(state.map))
    end
end

local function on_kill(state, c)
    state.kills = state.kills + 1
    local coins = c.boss and 7 or (c.elite and 4 or (c.threat >= ASSUME.big_cost and 2 or 1))
    local base_gold = math.max(1, math.floor(R.economy.gold_per_kill * state.map.gold_mult + 0.5))
    state.gold = state.gold + coins * base_gold * (c.threat >= ASSUME.big_cost and 2 or 1)
        * state.hero.gold_find
    if state.hero.lifesteal > 0 then
        state.hp = math.min(state.hero.hp_max, state.hp + state.hero.lifesteal)
    end
    -- In-run item drops: cadence + elite/boss rolls (deterministic EV).
    if c.boss then
        grant_drop(state); grant_drop(state)
    elseif c.elite then
        state.elite_drop_acc = state.elite_drop_acc + ASSUME.elite_drop_chance
        if state.elite_drop_acc >= 1.0 then
            state.elite_drop_acc = state.elite_drop_acc - 1.0
            grant_drop(state)
        end
    elseif state.kills % R.economy.drop_every == 0 then
        grant_drop(state)
    end
    local split = c.def.split_into
    if split then
        for _ = 1, split.count or 1 do
            local child = make_creep(state, split.archetype, false, true)
            if child then state.creeps[#state.creeps + 1] = child end
        end
    end
    if not c.exploded and c.def.explode and state.t >= c.arrive_at then
        -- Bomb reached the hero: the death IS the detonation for a fraction of them.
        state.pending_hit = state.pending_hit + c.def.explode.damage * ASSUME.telegraph_hit_fraction
            * state.map.dps_mult
        c.exploded = true
    end
end

local function sim_map_run(class_id, gear_ids, map_index, policy, primary_spec)
    local map = MAPS[map_index]
    local class = class_by_id(class_id)
    local primary, secondary = pick_specs(class, primary_spec)
    local hero = build_hero(class_id, gear_ids)
    local rules = Balance.tree_rules
        or { starting_points = 1, point_cap = 14, wave_points = 1, boss_points = 2 }
    local starting_points = rules.starting_points or 1
    local state = { hero = hero, map = map, t = 0.0, hp = hero.hp_max, creeps = {},
        kills = 0, gold = 0.0, spawn_counter = 0,
        elite_acc = 0.0, elite_drop_acc = 0.0, drops = 0, pending_hit = 0.0,
        wave = 1, flasks = R.flask.charges, flask_lock = 0.0, invuln_until = 0.0,
        -- Hero Grid: milestone income against the 14-point cap, spent along
        -- the scripted primary-then-secondary spine.
        banked = starting_points, earned = starting_points, alloc = { [primary.id] = {} },
        build = {}, build_i = 1, ev = {}, guardian_used = false }
    for _, nid in ipairs(spine_primary_for(primary)) do
        state.build[#state.build + 1] = { spec = primary, node = nid }
    end
    if secondary then
        for _, nid in ipairs(SPINE_SECONDARY) do
            state.build[#state.build + 1] = { spec = secondary, node = nid }
        end
    end
    local function award_points(n)
        local give = math.max(0, math.min(n, (rules.point_cap or 14) - state.earned))
        state.banked = state.banked + give
        state.earned = state.earned + give
    end
    local function allocate_banked()
        while state.banked > 0 and state.build_i <= #state.build do
            local step = state.build[state.build_i]
            local mine = state.alloc[step.spec.id]
            if not mine then mine = {}; state.alloc[step.spec.id] = mine end
            mine[step.node] = (mine[step.node] or 0) + 1
            state.banked = state.banked - 1
            state.build_i = state.build_i + 1
        end
        local evs = {}
        local range_add = 0.0
        for _, sp in ipairs({ primary, secondary }) do
            if sp and state.alloc[sp.id] then
                local fx = Balance.compute_spec_fx(class_id, sp, state.alloc[sp.id])
                evs[#evs + 1] = rider_ev(sp, fx)
                range_add = range_add + (fx.range_add or 0.0)
            end
        end
        state.ev = merge_ev(evs)
        -- Longshot / Punch-Through: same attack_range bump the duel applies.
        hero.attack_range = (hero._ref.attack_range or hero.attack_range) + range_add
    end
    allocate_banked() -- the starting point buys the primary keystone
    local result = { class_id = class_id, map = map_index, spec = primary.id, waves = {},
        min_hp_frac = 1.0, flasks_used = 0, cleared = false, gold = 0, kills = 0, drops = 0 }
    local exposure_contact = hero.attack == "ranged" and ASSUME.contact_exposure_ranged
        or Balance.benchmarks.melee_uptime -- melee hero faces contact at its damage uptime
    local exposure_proj = hero.attack == "ranged" and ASSUME.projectile_exposure_ranged
        or ASSUME.projectile_exposure_melee
    local drink_time = R.flask.drink_time * (hero.attack == "melee" and R.flask.melee_drink_mult or 1.0)

    local function step_combat(dt, spawning)
        -- Hero output: adds first, boss last (players clear adds), front-first
        -- pool across at most `cleave` in-range targets.
        local in_range, boss_target = {}, nil
        for _, c in ipairs(state.creeps) do
            if c.hp > 0 and state.t >= c.in_range_at then
                if c.boss then boss_target = c else in_range[#in_range + 1] = c end
            end
        end
        if boss_target then in_range[#in_range + 1] = boss_target end
        local ev = state.ev or {}
        local engaged_hits = math.min(#in_range, hero.cleave)
        local hit_rate = hero.attack == "ranged" and engaged_hits / hero.fire_interval
            or ASSUME.melee_hits_per_second * engaged_hits
        local hit_dmg = hero.attack == "ranged" and hero.dps * R.basic_attack.ranged_damage_mult
            or hero.dps / ASSUME.melee_hits_per_second
        -- Rider dps: immediate part per landed hit + refreshed DoT on the
        -- targets being cycled (dots outlive the cycle, hence the x2 cap).
        local dotted = math.min(#in_range, engaged_hits * 2)
        local rider_dps = hit_dmg * ((ev.initial or 0) * hit_rate + (ev.dot or 0) * dotted)
        if ev.extra_target and #in_range > engaged_hits then
            rider_dps = rider_dps + hit_dmg * hit_rate / math.max(1, engaged_hits)
                * ev.extra_target
        end
        local out_dps, hits = hero_output(hero, #in_range, rider_dps, ev)
        local pool, used = out_dps * dt, 0
        for _, c in ipairs(in_range) do
            if pool <= 0 or used >= math.max(hits, 1) then break end
            local dmg = pool
            if c.boss then
                dmg = dmg * (1.0 - ASSUME.boss_armor_uptime * (1.0 - R.boss.armored_damage_mult))
                    * (ev.boss_mult or 1.0)
                if c.hp < (c.max_hp or c.hp) * R.boss.phase2.hp_fraction then c.phase2 = true end
            end
            local dealt = math.min(dmg, c.hp)
            c.hp = c.hp - dealt
            pool = pool - dealt
            used = used + 1
            if c.hp <= 0 then
                on_kill(state, c)
                -- Death splashes (explosion/shockwave) and dot spread cascade
                -- into the pool.
                local cascade = (ev.on_kill or 0) + (ev.spread_kill or 0)
                if cascade > 0 then pool = pool + hit_dmg * cascade end
            end
        end
        -- Sustain: lifesteal per landed hit, vampirism rider heal, preservation
        -- regen, melee flask refill (dps-second normalised).
        if #in_range > 0 then
            if hero.lifesteal > 0 then
                state.hp = math.min(hero.hp_max, state.hp + hero.lifesteal * hit_rate * dt)
            end
            if ev.heal_mult and rider_dps > 0 then
                state.hp = math.min(hero.hp_max, state.hp + rider_dps * ev.heal_mult * dt)
            end
            if hero.attack == "melee" and state.flasks < R.flask.charges then
                state.flasks = math.min(R.flask.charges,
                    state.flasks + R.flask.melee_refill_rate * (out_dps / hero.dps) * dt)
            end
        end
        if ev.regen_frac then
            state.hp = math.min(hero.hp_max, state.hp + hero.hp_max * ev.regen_frac * dt)
        end
        -- Incoming damage from arrived creeps (+ thorns back at biters). Only
        -- `contact_cap` melee bodies fit around the hero at once.
        local incoming, biters = 0.0, 0
        for _, c in ipairs(state.creeps) do
            if c.hp > 0 and state.t >= c.arrive_at then
                local dps = c.dps
                if c.boss and c.def.boss_arc then
                    local arc = c.def.boss_arc
                    dps = dps + arc.damage * state.map.dps_mult * ASSUME.telegraph_hit_fraction
                        / ((arc.cooldown + arc.rest) * (c.phase2 and R.boss.phase2.cooldown_mult or 1.0))
                end
                local in_contact = c.ranged or c.boss or biters < ASSUME.contact_cap
                if not c.ranged and not c.boss then biters = biters + 1 end
                if in_contact then
                    incoming = incoming + dps * (c.ranged and exposure_proj or exposure_contact)
                end
                if not c.ranged and hero.thorns > 0 and in_contact then
                    c.hp = c.hp - hero.thorns * dt
                    if c.hp <= 0 then on_kill(state, c) end
                end
                if c.next_summon and state.t >= c.next_summon then
                    local every = c.def.summon_every * (c.phase2 and R.boss.phase2.summon_mult or 1.0)
                    c.next_summon = state.t + every
                    local add = make_creep(state, c.def.summon_archetype, false, true)
                    if add then state.creeps[#state.creeps + 1] = add end
                end
            end
        end
        -- Debuff riders (daze/frost/shadow/preservation) blunt the incoming.
        if ev.avoid then
            incoming = incoming * (1.0 - ev.avoid * ASSUME.rider_coverage)
        end
        if ev.tank then incoming = incoming * (1.0 - ev.tank) end -- minions soak aggro
        incoming = incoming + state.pending_hit / dt -- one-shot bomb hits this tick
        state.pending_hit = 0.0
        if state.t < state.invuln_until then incoming = 0.0 end
        state.hp = state.hp - incoming * (1.0 - hero.armor) * dt + hero.regen * dt
        state.hp = math.min(state.hp, hero.hp_max)
        result.min_hp_frac = math.min(result.min_hp_frac, state.hp / hero.hp_max)
        -- Flask.
        if state.hp < hero.hp_max * ASSUME.flask_use_fraction and state.flasks >= 1.0
            and state.t >= state.flask_lock then
            state.flasks = state.flasks - 1.0
            result.flasks_used = result.flasks_used + 1
            state.hp = math.min(hero.hp_max, state.hp + hero.hp_max * R.flask.heal_fraction)
            state.invuln_until = state.t + R.flask.invulnerability
            state.flask_lock = state.t + drink_time + R.flask.lock_time
        end
        state.t = state.t + dt
        if spawning then state.combat_time = (state.combat_time or 0.0) + dt end
        -- Last Stand: once per map the warrior shrugs off the killing blow.
        if state.hp <= 0.0 and ev.guardian and not state.guardian_used then
            state.guardian_used = true
            state.hp = hero.hp_max * 0.20
            state.invuln_until = state.t + 2.0
        end
        return state.hp > 0
    end

    local function finish(outcome)
        result.outcome = outcome
        result.gold, result.kills, result.drops = math.floor(state.gold), state.kills, state.drops
        return result
    end

    -- Waves. Hero Grid income: +1 per wave clear (paid at the next wave's
    -- start here), spent down the scripted spine at the hub pause.
    for wave = 1, map.waves do
        state.wave = wave
        if wave > 1 then award_points(rules.wave_points or 1) end
        allocate_banked()
        state.hp = math.min(hero.hp_max, state.hp + hero.regen * ASSUME.between_wave_downtime)
        local reserve = wave_budget(wave, map)
        local spawn_t = 0.0
        local start_t = state.t
        state.combat_time = state.combat_time or 0.0
        while true do
            local ct = state.combat_time
            if reserve >= 1 then -- min threat cost is 1
                spawn_t = spawn_t - ASSUME.dt
                if spawn_t <= 0.0 then
                    spawn_t = spawn_interval(ct)
                    for _ = 1, batch_size(ct) do
                        if alive_count(state) >= live_cap(ct) then break end
                        -- Mirror pick_affordable_auto_archetype: probe forward
                        -- until an affordable archetype turns up.
                        local pick, cost
                        for probe = 1, 25 do
                            local arch = Balance.auto_mix({ wave_index = wave, map_index = map_index,
                                spawn_counter = state.spawn_counter + probe, combat_time = ct,
                                spawn_cfg = { brute_after = S.brute_after } })
                            local d = MON[arch]
                            if d and (d.threat_cost or 1) <= reserve then
                                pick, cost = arch, d.threat_cost or 1
                                break
                            end
                        end
                        if not pick then reserve = 0; break end
                        reserve = reserve - cost
                        state.spawn_counter = state.spawn_counter + 1
                        local c = make_creep(state, pick, elite_roll(state, cost), false)
                        if c then state.creeps[#state.creeps + 1] = c end
                    end
                end
            end
            if not step_combat(ASSUME.dt, true) then
                result.waves[wave] = { outcome = "DIED", t = state.t - start_t }
                return finish(string.format("DIED w%d", wave))
            end
            if reserve < 1 and alive_count(state) == 0 then break end
            if state.t - start_t > ASSUME.wave_timeout then
                if ARGS.debug then
                    for _, c in ipairs(state.creeps) do
                        if c.hp > 0 then
                            print(string.format("  stall: %s hp=%.1f reserve=%.0f t=%.0f",
                                c.arch, c.hp, reserve, state.t))
                        end
                    end
                end
                result.waves[wave] = { outcome = "STALL", t = state.t - start_t }
                return finish(string.format("STALL w%d", wave))
            end
        end
        result.waves[wave] = { outcome = "clear", t = state.t - start_t }
        state.creeps = {}
    end

    -- Boss round: its own round in-game — the last wave's +1 and the boss
    -- entry +2 land before the rise, plus the between-round downtime regen.
    local bwave = map.waves + 1
    state.wave = bwave
    award_points(rules.wave_points or 1)
    award_points(rules.boss_points or 2)
    allocate_banked()
    state.hp = math.min(hero.hp_max, state.hp + hero.regen * ASSUME.between_wave_downtime)
    local boss = make_creep(state, map.boss, false, false)
    boss.max_hp = boss.hp
    state.creeps = { boss }
    local boss_start = state.t
    while true do
        if not step_combat(ASSUME.dt, false) then return finish("DIED boss") end
        if boss.hp <= 0 then break end
        if state.t - boss_start > ASSUME.wave_timeout then return finish("STALL boss") end
    end
    result.cleared = true
    result.boss_ttk = state.t - boss_start
    result.total_time = state.t
    return finish("CLEAR")
end

-- ---------------------------------------------------------------------------
-- Scenario matrix + report.
local GEAR = { none = {}, mid = Balance.gearsets.mid, top = Balance.gearsets.top }

-- Intended gear ladder from the 2026-07-11 autoplay-pilot smokes: map I is
-- naked onboarding, map II expects mid gear, map III+ expects top (in-run
-- drops carry the deeper maps).
local SCENARIOS = {
    { map = 1, gear = "none" }, { map = 2, gear = "mid" }, { map = 3, gear = "top" },
    { map = 5, gear = "top" }, { map = 8, gear = "top" }, { map = 11, gear = "top" },
}

local function class_ids()
    local ids = {}
    for _, c in ipairs(Balance.classes) do
        if not ARGS.class or ARGS.class == c.id then ids[#ids + 1] = c.id end
    end
    return ids
end

local results = {}
print(string.format("%-6s %-5s %-12s %-12s %-10s %8s %7s %7s %6s %8s %7s",
    "map", "gear", "class", "spec", "outcome", "time", "minHP%", "flasks", "drops", "bossTTK", "gold"))
for _, sc in ipairs(SCENARIOS) do
    if (not ARGS.map or ARGS.map == sc.map) and (not ARGS.gear or ARGS.gear == sc.gear) then
        for _, id in ipairs(class_ids()) do
            local class = class_by_id(id)
            for _, spec in ipairs(class.specializations or {}) do
                if not ARGS.spec or ARGS.spec == spec.id then
                    local r = sim_map_run(id, GEAR[sc.gear], sc.map, ARGS.policy or "spec", spec.id)
                    r.gear = sc.gear
                    results[#results + 1] = r
                    print(string.format("%-6s %-5s %-12s %-12s %-10s %7.1fs %6.0f%% %7d %6d %8s %7d",
                        Balance.map_progression.rank[sc.map], sc.gear, id, r.spec, r.outcome,
                        r.total_time or 0.0, r.min_hp_frac * 100.0, r.flasks_used, r.drops,
                        r.boss_ttk and string.format("%.0fs", r.boss_ttk) or "-", r.gold))
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Verdicts.
-- 1) Baseline diff — THE balancing tool: tools/paper_baseline.txt captures the
--    last accepted outcome table; any flip after editing ath_balance.lua is
--    listed. Re-run with --save-baseline to accept intentional changes.
-- 2) Structural gates — model-robust invariants of the current balance.
-- 3) Findings — data oddities worth a human look, never failures.
local failures = {}
local function gate(name, ok, detail)
    if not ok then failures[#failures + 1] = name .. (detail and (" — " .. detail) or "") end
end

local function result_key(r)
    return string.format("%d|%s|%s|%s", r.map, r.gear, r.class_id, r.spec)
end
local function result_line(r)
    return string.format("%s|%s|%d", result_key(r), r.outcome,
        r.boss_ttk and math.floor(r.boss_ttk + 0.5) or -1)
end

local BASELINE_PATH = ROOT .. "/tools/paper_baseline.txt"
local full_matrix = not (ARGS.map or ARGS.gear or ARGS.class or ARGS.spec or ARGS.policy)

if ARGS.save_baseline and full_matrix then
    local f = assert(io.open(BASELINE_PATH, "w"))
    for _, r in ipairs(results) do f:write(result_line(r), "\n") end
    f:close()
    print("\nbaseline saved: tools/paper_baseline.txt (" .. #results .. " scenarios)")
elseif full_matrix then
    local f = io.open(BASELINE_PATH)
    if f then
        local base = {}
        for line in f:lines() do
            local key, outcome, ttk = line:match("^(.-)|([^|]*)|(-?%d+)$")
            if key then base[key] = { outcome = outcome, ttk = tonumber(ttk) } end
        end
        f:close()
        for _, r in ipairs(results) do
            local b = base[result_key(r)]
            if not b then
                gate("baseline: new scenario " .. result_key(r), false, r.outcome)
            elseif b.outcome ~= r.outcome then
                gate("baseline flip: " .. result_key(r), false,
                    b.outcome .. " -> " .. r.outcome)
            elseif b.ttk > 0 and r.boss_ttk
                and math.abs(r.boss_ttk - b.ttk) > math.max(10.0, b.ttk * 0.25) then
                gate("baseline boss-TTK drift: " .. result_key(r), false,
                    string.format("%ds -> %.0fs", b.ttk, r.boss_ttk))
            end
        end
    else
        print("\n(no baseline yet — run with --save-baseline to pin current outcomes)")
    end
end

if full_matrix and not ARGS.no_gates then
    -- Structural invariants, robust to paper-model knobs.
    for _, r in ipairs(results) do
        if r.cleared then
            gate("boss TTK band: " .. result_key(r),
                r.boss_ttk >= 5.0 and r.boss_ttk <= 180.0, string.format("%.0fs", r.boss_ttk))
            gate("cleared without hitting zero: " .. result_key(r), r.min_hp_frac > 0.0)
        end
    end
    -- Melee sustain identity: the brawler ladder must hold end to end.
    for _, sc in ipairs({ { 1, "none" }, { 2, "mid" }, { 3, "top" }, { 5, "top" }, { 8, "top" } }) do
        for _, r in ipairs(results) do
            if r.map == sc[1] and r.gear == sc[2] and r.class_id == "brawler" then
                gate(string.format("brawler gear ladder map %d %s", sc[1], sc[2]),
                    r.cleared, r.outcome)
            end
        end
    end
    -- Every class's best paper primary must clear VIII with top gear. The
    -- other trees still run and stay baseline-pinned without requiring every
    -- utility-first build to be a deep-map solo clearer.
    for _, r in ipairs(results) do
        if r.map == 8 and r.gear == "top" then
            local best = pick_specs(class_by_id(r.class_id))
            if r.spec == best.id then
                gate("class clears map VIII: " .. r.class_id, r.cleared, r.outcome)
            end
        end
    end
    -- Economy: any cleared map I run affords a common store item.
    for _, r in ipairs(results) do
        if r.map == 1 and r.gear == "none" and r.cleared then
            gate("map I gold buys a common item: " .. r.class_id,
                r.gold >= R.economy.store_prices.common, tostring(r.gold))
        end
    end
end

-- Findings: data oddities (reported, never failed).
local findings = {}
for i, map in ipairs(MAPS) do
    for wave = 2, map.waves do
        if wave_budget(wave, map) < wave_budget(wave - 1, map) then
            findings[#findings + 1] = string.format(
                "map %s wave %d budget DROPS: %.0f -> %.0f (wave_budgets[] ends at %d, fallback is reserve_start+40/wave)",
                Balance.map_progression.rank[i], wave,
                wave_budget(wave - 1, map), wave_budget(wave, map), #R.arena.wave_budgets)
            break
        end
    end
end

print("")
for _, f in ipairs(findings) do print("  FINDING " .. f) end
if #failures == 0 then
    print(string.format("PAPER BALANCE: PASS (%d runs, audit() ok)", #results))
else
    print(string.format("PAPER BALANCE: %d FAILURES:", #failures))
    for _, f in ipairs(failures) do print("  FAIL " .. f) end
end
return #failures
