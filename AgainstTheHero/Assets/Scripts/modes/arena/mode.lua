-- Arena — manual hero experiment.
--
-- A deliberately thin mode for PLAN.md experiment #1: same shared Duel spine,
-- current flat-sprite presentation, no cards, no shell, no hero AI. The player
-- drives the hero with WASD/arrow keys while auto-attacks and wave/gear logic
-- live behind config.manual_hero in ath_duel.lua.

local Art  = ATH_COMMON.load_script("Scripts/shared/ath_art.lua",              "shared art",       _ENV)
local View = ATH_COMMON.load_script("Scripts/shared/ath_topdown_view.lua",     "top-down view",    _ENV)
local Spud = ATH_COMMON.load_script("Scripts/modes/spud_fields/characters.lua", "spud_fields cast", _ENV)

-- Arena-tuned COPIES of the spud cast (never mutate the shared tables).
-- Contact ranges are shrunk to roughly what the small top-down sprites visually
-- touch — the stock ranges land hits from several sprite-widths away, which
-- reads as damage out of nowhere. Speeds are rebuilt around the manual hero:
-- the basic swarm is a touch SLOWER than the hero so kiting works, crows
-- punish straight-line running, and the spitter's stand-off range stays on
-- screen so its hits are attributable.
local function tuned(base, overrides)
    local t = {}
    for k, v in pairs(base) do t[k] = v end
    for k, v in pairs(overrides) do t[k] = v end
    return t
end
-- Creep walk speeds are ~2x the old arena tuning (swarm is faster/scarier now).
-- They keep full speed all the way to the hero (the near-hero slow is now the
-- opt-in hero.slow_aura buff, off by default).
local ARCHETYPES = {
    sprout        = tuned(Spud.archetypes.sprout,        { range = 0.35, speed = 4.2 }),
    -- The spitter now lobs a VISIBLE seed (Duel creep-projectile system) instead
    -- of a silent stand-off damage field, so it's back in the mix. It holds at
    -- ~5 units and pelts the hero; kite out of range to break line of fire.
    seed_spitter  = tuned(Spud.archetypes.seed_spitter,  {
        range = 4.5, hold_range = 4.8, speed = 2.2,
        projectile = {
            kind = "seed", speed = 15.0, cooldown = 1.15,
            start_y = 0.7, target_y = 0.55,
            scale = { 0.18, 0.18, 0.18 }, particle_size = 0.20,
            color = { 0.98, 0.86, 0.30 }, emissive = 1.3,
            hit_radius = 0.7, gravity = 0.0,
        },
    }),
    husk_knight   = tuned(Spud.archetypes.husk_knight,   { range = 0.6, speed = 3.0, knockback_resist = 0.45 }),
    pumpkin_brute = tuned(Spud.archetypes.pumpkin_brute, { range = 0.7, speed = 2.2, knockback_resist = 0.75 }),
    -- Crow stays BELOW hero speed (8.5): anything faster than the hero is
    -- unavoidable by movement alone (there is no dash/dodge yet).
    crow          = tuned(Spud.archetypes.crow,          { range = 0.4, speed = 5.0 }),
    -- Armored swarm tank: chunkier than a sprout, shrugs off knockback (resist
    -- carried from the base archetype), but slow enough to kite.
    beetle        = tuned(Spud.archetypes.beetle,        { range = 0.6, speed = 2.6 }),
    -- Long-range heavy: holds far back (hold_range 7.5) and lobs a big slow cob.
    corn_mortar   = tuned(Spud.archetypes.corn_mortar,   { speed = 0.9 }),
    -- Fast ranged flier: darts, holds at ~5, pelts quick stingers. Below hero
    -- speed so a committed chase still catches it.
    wasp          = tuned(Spud.archetypes.wasp,          { speed = 5.2 }),
    -- BLAST BUD (wave 3+) — a walking bomb: sprout art tinted hot orange; the
    -- fuse strobe (View) warns, then it pops for real AoE damage. Killing it
    -- before the fuse ends defuses it — shoot it at range or step away.
    blast_bud     = tuned(Spud.archetypes.sprout,        {
        name = "Blast Bud", threat_cost = 2, hp = 9, dps = 1.0, range = 0.4, speed = 4.6,
        tint = { 1.5, 0.55, 0.35 },
        -- fuse = 0.8 matches the telegraph grammar: ground decal 0.8s before impact.
        explode = { trigger = 2.6, fuse = 0.8, radius = 2.6, damage = 24.0, fuse_speed_mult = 1.35 },
    }),
    -- RAM BEETLE (wave 2+) — a telegraphed charger: beetle art tinted crimson;
    -- it plants, shivers red (windup), then dashes a locked line. Step aside —
    -- a landed slam hits hard and shoves.
    ram_beetle    = tuned(Spud.archetypes.beetle,        {
        name = "Ram Beetle", threat_cost = 3, hp = 26, dps = 9.0, range = 0.6, speed = 2.3,
        knockback_resist = 0.6, tint = { 1.6, 0.55, 0.55 },
        charge = { trigger = 8.0, windup = 0.55, mult = 3.4, duration = 0.85, cooldown = 3.2, dmg_mult = 1.8 },
    }),
    -- GOURD KING — the wave-5 boss. A huge gold-tinted pumpkin: charges like a
    -- ram, sheds sprout summons, and showers rare loot on death.
    gourd_king    = tuned(Spud.archetypes.pumpkin_brute, {
        name = "Gourd King", threat_cost = 20, hp = 620, dps = 26.0, range = 1.1, speed = 2.7,
        scale = 2.2, knockback_resist = 1.0, boss = true, tint = { 1.35, 1.1, 0.55 },
        charge = { trigger = 11.0, windup = 0.8, mult = 3.0, duration = 1.1, cooldown = 4.5, dmg_mult = 2.0 },
        summon_archetype = "sprout", summon_every = 4.5,
    }),
}
-- Reuse the existing movement/attack behaviors with distinct combat jobs.
ARCHETYPES.thorn_guard = tuned(ARCHETYPES.husk_knight, {
    name = "Thorn Guard", threat_cost = 5, hp = 58, dps = 8.0, speed = 2.1,
    knockback_resist = 0.85, tint = { 0.55, 1.15, 0.52 },
})
ARCHETYPES.spore_witch = tuned(ARCHETYPES.seed_spitter, {
    name = "Spore Witch", threat_cost = 4, hp = 20, dps = 5.0, range = 6.5, hold_range = 6.5,
    speed = 2.7, tint = { 0.90, 0.55, 1.30 },
    projectile = {
        kind = "spore", speed = 12.0, cooldown = 0.72,
        start_y = 0.8, target_y = 0.55, scale = { 0.22, 0.22, 0.22 }, particle_size = 0.22,
        color = { 0.78, 0.42, 1.0 }, emissive = 1.5, hit_radius = 0.72, gravity = 0.0,
    },
})
ARCHETYPES.brood_pod = tuned(ARCHETYPES.pumpkin_brute, {
    name = "Brood Pod", threat_cost = 6, hp = 52, dps = 3.0, speed = 1.8, scale = 1.25,
    knockback_resist = 0.65, tint = { 0.72, 0.48, 1.20 },
    split_into = { archetype = "wasp", count = 3 },
})
-- The brute now splits on death: a felled pumpkin bursts into three sprouts.
ARCHETYPES.pumpkin_brute.split_into = { archetype = "sprout", count = 3 }

-- ---- Map II (Hollow Hive) cast — insect pressure, all reused art + tints ----
-- STINGER DRONE — cheap fast melee flier; the hive's sprout.
ARCHETYPES.stinger_drone = tuned(ARCHETYPES.crow, {
    name = "Stinger Drone", threat_cost = 1, hp = 10, dps = 3.4, range = 0.45, speed = 5.4,
    tint = { 0.55, 1.05, 1.25 },
})
-- HIVE MATRON — slow summoner; sheds wasps until put down.
ARCHETYPES.hive_matron = tuned(ARCHETYPES.pumpkin_brute, {
    name = "Hive Matron", threat_cost = 7, hp = 95, dps = 6.0, range = 0.9, speed = 1.3,
    knockback_resist = 0.8, tint = { 1.35, 1.05, 0.45 },
    summon_archetype = "wasp", summon_every = 5.0,
})
-- LUA TRAP: `key = nil` in an overrides literal is invisible to pairs(), so
-- inherited fields must be nilled AFTER tuned() — the matron must not split.
ARCHETYPES.hive_matron.split_into = nil
-- BOMBER BEETLE — charger AND walking bomb: it dashes in, then the fuse lights.
ARCHETYPES.bomber_beetle = tuned(ARCHETYPES.beetle, {
    name = "Bomber Beetle", threat_cost = 4, hp = 30, dps = 3.0, range = 0.6, speed = 2.6,
    knockback_resist = 0.5, tint = { 1.45, 0.85, 0.30 },
    charge = { trigger = 8.5, windup = 0.5, mult = 3.0, duration = 0.8, cooldown = 3.6, dmg_mult = 1.5 },
    explode = { trigger = 2.4, fuse = 0.8, radius = 2.8, damage = 30.0, fuse_speed_mult = 1.3 },
})
-- WASP QUEEN — Map II boss: a diving summoner. Base hp is tuned knowing the
-- config creep_hp_mult (1.56) and the map hp_mult stack on top.
ARCHETYPES.wasp_queen = tuned(ARCHETYPES.wasp, {
    name = "Wasp Queen", threat_cost = 20, hp = 350, dps = 24.0, range = 1.2, speed = 3.4,
    scale = 2.3, knockback_resist = 1.0, boss = true, tint = { 1.30, 0.85, 1.35 },
    charge = { trigger = 12.0, windup = 0.7, mult = 3.6, duration = 1.0, cooldown = 3.8, dmg_mult = 1.9 },
    summon_archetype = "stinger_drone", summon_every = 4.0,
})
-- Melee diver, not a shooter: strip the wasp's stand-off kit (post-tuned, see
-- the nil-override trap above).
ARCHETYPES.wasp_queen.hold_range = nil
ARCHETYPES.wasp_queen.anchor_hold = nil
ARCHETYPES.wasp_queen.needs_los = nil
ARCHETYPES.wasp_queen.projectile = nil

-- ---- Map III (Royal Garden) cast — armored royalty, reused art + tints ------
-- ROYAL GUARD — tanky knight that charges in formation.
ARCHETYPES.royal_guard = tuned(ARCHETYPES.husk_knight, {
    name = "Royal Guard", threat_cost = 6, hp = 85, dps = 11.0, range = 0.95, speed = 1.9,
    knockback_resist = 0.9, tint = { 0.75, 0.90, 1.40 },
    charge = { trigger = 9.0, windup = 0.6, mult = 3.2, duration = 0.8, cooldown = 4.0, dmg_mult = 1.7 },
})
-- CORN ARBALEST — long-range sniper; fast bolts that beg for the dodge.
ARCHETYPES.corn_arbalest = tuned(ARCHETYPES.corn_mortar, {
    name = "Corn Arbalest", threat_cost = 4, hp = 26, dps = 5.5, range = 9.0, speed = 1.4,
    hold_range = 9.0, tint = { 0.70, 0.95, 1.35 },
    projectile = {
        kind = "quarrel", speed = 22.0, cooldown = 1.6,
        start_y = 0.9, target_y = 0.55, scale = { 0.14, 0.14, 0.52 }, particle_size = 0.18,
        color = { 0.62, 0.86, 1.0 }, emissive = 1.6, hit_radius = 0.6, gravity = 0.0,
    },
})
-- GOURD SAPPER — a bomb with a catch: shoot it early and it SPLITS into sprouts;
-- let the fuse run and it detonates hard. Pick your poison.
ARCHETYPES.gourd_sapper = tuned(ARCHETYPES.pumpkin_brute, {
    name = "Gourd Sapper", threat_cost = 5, hp = 46, dps = 3.0, range = 0.7, speed = 2.4,
    knockback_resist = 0.6, tint = { 1.10, 0.55, 1.35 },
    explode = { trigger = 2.8, fuse = 0.8, radius = 3.2, damage = 36.0, fuse_speed_mult = 1.35 },
    split_into = { archetype = "sprout", count = 3 },
})
-- CORN COLOSSUS — Map III boss: mortar barrage + a slow crushing charge.
ARCHETYPES.corn_colossus = tuned(ARCHETYPES.corn_mortar, {
    name = "Corn Colossus", threat_cost = 20, hp = 400, dps = 30.0, range = 1.3, speed = 2.2,
    scale = 2.6, knockback_resist = 1.0, boss = true, tint = { 1.40, 1.15, 0.50 },
    hold_range = 8.0, anchor_hold = true, needs_los = true, los_reposition_seconds = 1.5,
    projectile = {
        kind = "boulder_cob", speed = 11.0, cooldown = 1.3,
        start_y = 1.4, target_y = 0.55, scale = { 0.42, 0.42, 0.42 }, particle_size = 0.38,
        color = { 1.0, 0.78, 0.30 }, emissive = 1.4, hit_radius = 1.05, gravity = 0.0, pulse = true,
    },
    charge = { trigger = 7.0, windup = 0.8, mult = 3.0, duration = 1.0, cooldown = 5.0, dmg_mult = 1.8 },
    summon_archetype = "husk_knight", summon_every = 6.0,
})

return {
    meta = {
        id      = "arena",
        name    = "Hero Arena",
        tagline = "manual movement feel test",
        blurb   = "Drive the hero through five escalating waves, auto-attack the swarm, and equip dropped gear between waves.",
        side_hint = "hero",
        accent  = { 0.46, 0.78, 0.24, 0.95 },
        minimap = {
            bg = { 0.30, 0.54, 0.20, 1.0 },
            rects = {
                { 0.05, 0.05, 0.90, 0.90, { 0.42, 0.70, 0.27, 1.0 } },
                { 0.46, 0.44, 0.10, 0.10, { 0.84, 0.66, 0.40, 1.0 } },
                { 0.10, 0.10, 0.05, 0.05, { 0.96, 0.84, 0.28, 1.0 } },
                { 0.85, 0.85, 0.05, 0.05, { 0.96, 0.84, 0.28, 1.0 } },
            },
        },
    },

    config = {
        id = "arena",
        name = "Hero Arena",
        manual_hero = true,
        theme = {
            accent        = Spud.theme.accent,
            floor         = Spud.theme.floor,
            floor_texture = Spud.theme.floor_texture,
            wall          = Spud.theme.wall,
            spawn_sigil   = Spud.theme.spawn_sigil,
            aura          = Spud.theme.aura,
            hud_title     = "HERO ARENA",
            win_text      = "Five waves down. The run has a pulse.\nPress R to run it back",
            lose_text     = "The swarm got you. Press R and make a better path.",
        },
        arena = {
            -- Playable pit the hero roams. ortho_size feeds Art.setup_iso_camera
            -- (50/zoom ≈ 30 in the 20:9 band); the band is ~67 wide, so a 64-wide
            -- pit puts the fence walls just inside the screen edges. NOTE: the view
            -- WIDTH is ~67 for any landscape aspect (crop cancels), but the view
            -- HEIGHT grows on less-wide screens (ortho ~31 at 19.5:9 up to ~37 at
            -- 16:9). Since the letterbox bars are gone (Free aspect), the floor must
            -- OVER-fill that full height or background shows top/bottom -> hence
            -- floor_extent height 40 (covers ortho up to ~40) and width 76 margin.
            width = 64, height = 28, pad = 2,
            ortho_size = 50.0,
            floor_extent = { width = 76.0, height = 40.0 },
            -- No fixed spawn ring: the manual arena spawns randomly along the
            -- walls (Duel:pick_spawn_point), and the decorative sigils fall back
            -- to the auto-generated perimeter, both scaled to the pit size.
            cam_offset = View.CAM_OFFSET,
        },
        topdown = {
            -- 1.0 = the sizes as actually rendered (build-time char scale).
            -- KNOWN LIMITATION: runtime sprite-scale multipliers don't reach
            -- the renderer reliably (engine transform/flush issue — needs a
            -- dedicated engine session with a minimal repro). Until then the
            -- look is the baseline and the hitboxes are derived to MATCH it.
            hero_scale = 1.0,
            creep_scale = 1.0,
        },
        hero = {
            -- RANGED auto-attacker: fires bolts at the nearest creeps within
            -- attack_range. cleave = bolts per volley (multi-shot / auto-aim at
            -- the N nearest). dps scales per-bolt damage; fire_interval = seconds
            -- between volleys. Gear maps cleanly: +reach -> attack_range,
            -- +cleave -> more bolts, +damage -> per-bolt damage.
            hp_max = 105.0, dps = 22.0, cleave = 3, attack_range = 9.0,
            fire_interval = 0.26,
            -- Comfortably faster than the swarm so kiting reads clearly.
            -- body_radius is derived from the rendered sprite size in
            -- ath_topdown_view, not set here.
            speed = 8.5, kite_speed = 8.5,
            sprite_texture = Spud.tex.hero,
            -- Selectable classes (chosen on a pick screen at run start). Each is an
            -- attack IDENTITY — ranged bolts, melee cleave, or seed-scatter — that
            -- gear/cards later bend. Stats here override the hero baseline above.
            default_class = "ranger",
            classes = {
                {
                    id = "ranger", name = "Ranger", attack = "ranged",
                    blurb = "Long-range bolts. Pick the swarm off from afar.",
                    accent = { 0.96, 0.84, 0.36, 0.95 },
                    hp_max = 115.0, dps = 25.0, cleave = 3, attack_range = 9.0,
                    fire_interval = 0.26, speed = 8.5, kite_speed = 8.5,
                    sprite_texture = Spud.tex.hero,
                    bolt_color = { 1.0, 0.90, 0.42 }, bolt_scale = 0.34,
                },
                {
                    id = "brawler", name = "Brawler", attack = "melee",
                    blurb = "Wide cleave plus an orbiting spin. Armored for close combat.",
                    accent = { 0.92, 0.42, 0.34, 0.95 },
                    hp_max = 240.0, dps = 60.0, cleave = 8, attack_range = 5.0,
                    speed = 9.0, kite_speed = 9.0,
                    armor = 0.35, lifesteal = 1.0, regen = 3.0, whirl = 1,
                    sprite_texture = Spud.tex.brawler,
                },
                {
                    id = "sower", name = "Sower", attack = "ranged",
                    blurb = "Sprays seed-shot at the nearest five. Short range, fast.",
                    accent = { 0.54, 0.82, 0.40, 0.95 },
                    hp_max = 105.0, dps = 16.0, cleave = 5, attack_range = 6.0,
                    fire_interval = 0.30, speed = 8.3, kite_speed = 8.3,
                    sprite_texture = Spud.tex.sower,
                    bolt_color = { 0.66, 0.92, 0.40 }, bolt_scale = 0.30,
                },
            },
        },
        archetypes = ARCHETYPES,
        roles = Spud.roles,
        spawn = {
            interval_start = 0.60, interval_min = 0.20,
            batch_start = 3, batch_max = 10,
            cap_start = 44, cap_max = 85,
            brute_after = 26.0,
        },
        waves = {
            count = 5,
            budgets = { 130, 173, 230, 302, 389, 500, 640 },
        },
        -- Fallback boss when no map def is active; maps override per run.
        boss_archetype = "gourd_king",
        boss_title = "GOURD KING",
        -- MAPS — the run ladder. Each map is the same authored stage with its own
        -- wave count, boss, enemy mix (auto_mix reads D.map_index), difficulty
        -- multipliers and loot weights. Clearing a map unlocks the next
        -- (persisted in Save/profile.lua). Gold scales steeply with rank so
        -- deeper maps are the real income (suicide-farming map I stays poor).
        -- pos = normalized {x, y} on the painted world map (Textures/ui/map/worldmap.png).
        worldmap_image = "Textures/ui/map/worldmap.png",
        maps = {
            { id = "spud_fields", name = "Spud Fields", rank = "I",
              waves = 5, boss = "gourd_king", boss_title = "GOURD KING",
              budget_mult = 1.0, hp_mult = 1.0, dps_mult = 1.0, gold_mult = 1.0, elite_bonus = 0.0,
              drop_weights = { common = 60, uncommon = 30, rare = 9, epic = 1 },
              pos = { 0.21, 0.40 }, icon = "Textures/ui/map/badge_spud.png",
              blurb = "Rolling farmland overrun by the sprouting dead." },
            { id = "hollow_hive", name = "Hollow Hive", rank = "II",
              waves = 6, boss = "wasp_queen", boss_title = "WASP QUEEN",
              budget_mult = 1.25, hp_mult = 1.55, dps_mult = 1.45, gold_mult = 1.8, elite_bonus = 0.02,
              drop_weights = { common = 28, uncommon = 44, rare = 24, epic = 4 },
              pos = { 0.50, 0.28 }, icon = "Textures/ui/map/badge_hive.png",
              blurb = "A droning hollow wood - the air itself stings." },
            { id = "royal_garden", name = "Royal Garden", rank = "III",
              waves = 7, boss = "corn_colossus", boss_title = "CORN COLOSSUS",
              budget_mult = 1.55, hp_mult = 2.4, dps_mult = 2.0, gold_mult = 3.0, elite_bonus = 0.04,
              drop_weights = { common = 8, uncommon = 34, rare = 42, epic = 16 },
              pos = { 0.79, 0.34 }, icon = "Textures/ui/map/badge_garden.png",
              blurb = "The overgrown palace grounds of the Corn Court." },
        },
        reserve_start = 130.0,
        round_seconds = 9999.0,
        -- Creeps spawn a bit beefier than their base archetype HP (applied in
        -- Duel:spawn_one via Creep.create's hp_multiplier).
        creep_hp_mult = 1.56,
        kill_fx_budget_per_frame = 6,
        warm_pool_count = 0,
        prewarm_order = { "sprout", "husk_knight", "crow", "pumpkin_brute", "seed_spitter", "beetle", "corn_mortar", "wasp", "ram_beetle", "blast_bud", "thorn_guard", "spore_witch", "brood_pod", "stinger_drone", "hive_matron", "bomber_beetle", "royal_guard", "corn_arbalest", "gourd_sapper", "gourd_king", "wasp_queen", "corn_colossus" },
        -- Pre-build + PARK this many rigs per type at run start (warm_archetype
        -- now populates the pool). Kept ABOVE each type's realistic peak-alive at
        -- cap_max=85 so the pool never empties -> combat spawns reuse parked rigs
        -- and never build a rig mid-frame (the spawn spike). Also avoids the
        -- mid-combat alpha-cut geometry-add RT hazard.
        prewarm = { sprout = 56, husk_knight = 32, pumpkin_brute = 16, crow = 22, seed_spitter = 14, beetle = 26, corn_mortar = 10, wasp = 18, ram_beetle = 10, blast_bud = 12, thorn_guard = 10, spore_witch = 8, brood_pod = 6,
            stinger_drone = 22, hive_matron = 5, bomber_beetle = 10, royal_guard = 10, corn_arbalest = 8, gourd_sapper = 8,
            gourd_king = 1, wasp_queen = 1, corn_colossus = 1 },

        gear = {
            gold_per_kill = 1,
            drop_every = 25,
            -- Loot table for the 6-slot paper-doll (helmet/body/pants/gloves/
            -- weapon/jewelry). Drops cycle this list into the backpack; rarity
            -- tints the slot border in the inventory.
            items = {
                -- helmet
                { id = "straw_hat", slot = "helmet", rarity = "common", name = "Straw Hat", weight = 4,
                  desc = "+18 HP", effect = { hp_max_add = 18.0 } },
                { id = "iron_helm", slot = "helmet", rarity = "uncommon", name = "Iron Helm", weight = 18,
                  desc = "+28 HP, +8% armor", effect = { hp_max_add = 28.0, armor_add = 0.08 } },
                { id = "leather_cap", slot = "helmet", rarity = "common", name = "Leather Cap", weight = 6,
                  desc = "+12 HP, +5% move", effect = { hp_max_add = 12.0, speed_mult = 1.05, kite_speed_mult = 1.05 } },
                { id = "thorn_hood", slot = "helmet", rarity = "uncommon", name = "Thorn Hood", weight = 10,
                  desc = "+20 HP, +4 thorns", effect = { hp_max_add = 20.0, thorns_add = 4.0 } },
                { id = "spore_mask", slot = "helmet", rarity = "rare", name = "Spore Mask", weight = 8,
                  desc = "+12% armor, +1.5 regen", effect = { armor_add = 0.12, regen_add = 1.5 } },
                { id = "gourd_visor", slot = "helmet", rarity = "epic", name = "Gourd Visor", weight = 20,
                  desc = "+60 HP, +18% armor", effect = { hp_max_add = 60.0, armor_add = 0.18 } },
                -- body
                { id = "field_vest", slot = "body", rarity = "common", name = "Field Vest", weight = 12,
                  desc = "+30 HP", effect = { hp_max_add = 30.0 } },
                { id = "husk_plate", slot = "body", rarity = "uncommon", name = "Husk Plate", weight = 32,
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
                { id = "wind_leggings", slot = "pants", rarity = "uncommon", name = "Wind Leggings", weight = 6,
                  desc = "+22% move", effect = { speed_mult = 1.22, kite_speed_mult = 1.22 } },
                { id = "plated_greaves", slot = "pants", rarity = "rare", name = "Plated Greaves", weight = 25,
                  desc = "+35 HP, +10% armor, +5% move", effect = { hp_max_add = 35.0, armor_add = 0.10, speed_mult = 1.05, kite_speed_mult = 1.05 } },
                { id = "phase_steps", slot = "pants", rarity = "epic", name = "Phase Steps", weight = 5,
                  desc = "+20 HP, +30% move", effect = { hp_max_add = 20.0, speed_mult = 1.30, kite_speed_mult = 1.30 } },
                -- gloves
                { id = "garden_gloves", slot = "gloves", rarity = "common", name = "Garden Gloves", weight = 3,
                  desc = "+12% attack speed", effect = { fire_interval_mult = 0.88 } },
                { id = "gauntlets", slot = "gloves", rarity = "uncommon", name = "Gauntlets", weight = 14,
                  desc = "+4 damage, +6% attack speed", effect = { dps_add = 4.0, fire_interval_mult = 0.94 } },
                { id = "grip_wraps", slot = "gloves", rarity = "common", name = "Grip Wraps", weight = 4,
                  desc = "+2 damage", effect = { dps_add = 2.0 } },
                { id = "thorn_grips", slot = "gloves", rarity = "uncommon", name = "Thorn Grips", weight = 8,
                  desc = "+3 damage, +4 thorns", effect = { dps_add = 3.0, thorns_add = 4.0 } },
                { id = "duelist_gloves", slot = "gloves", rarity = "rare", name = "Duelist Gloves", weight = 6,
                  desc = "+8 damage, +15% attack speed", effect = { dps_add = 8.0, fire_interval_mult = 0.85 } },
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
                { id = "twin_blades", slot = "weapon", rarity = "rare", name = "Twin Blades",
                  desc = "+10 damage, +3 cleave", effect = { dps_add = 10.0, cleave_add = 3 } },
                { id = "sun_reaper", slot = "weapon", rarity = "epic", name = "Sun Reaper",
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
                { id = "storm_loop", slot = "jewelry", rarity = "epic", name = "Storm Loop",
                  desc = "+20% crit, +15% attack and move speed", effect = { crit_add = 0.20, fire_interval_mult = 0.85, speed_mult = 1.15, kite_speed_mult = 1.15 } },
                -- boss-tier (rare pool feeds the Gourd King's shower)
                { id = "kings_crown", slot = "helmet", rarity = "rare", name = "King's Crown", weight = 16,
                  desc = "+40 HP, +10% damage, +20% gold", effect = { hp_max_add = 40.0, dps_mult = 1.10, gold_find_add = 0.2 } },
                -- Map II/III expansion — deeper rarity ladders per slot, dodge
                -- synergy pieces, and boss-flavoured epics for the new maps.
                { id = "sentry_visor", slot = "helmet", rarity = "rare", name = "Sentry Visor", weight = 14,
                  desc = "+25 HP, +1 cleave", effect = { hp_max_add = 25.0, cleave_add = 1 } },
                { id = "queens_diadem", slot = "helmet", rarity = "epic", name = "Queen's Diadem", weight = 8,
                  desc = "+45 HP, +15% attack speed, +8% move", effect = { hp_max_add = 45.0, fire_interval_mult = 0.85, speed_mult = 1.08, kite_speed_mult = 1.08 } },
                { id = "beetle_shell", slot = "body", rarity = "rare", name = "Beetle Shell", weight = 30,
                  desc = "+40 HP, +15% armor", effect = { hp_max_add = 40.0, armor_add = 0.15 } },
                { id = "dancer_garb", slot = "body", rarity = "rare", name = "Dancer's Garb", weight = 6,
                  desc = "+12% move, +10% crit, dodge 20% faster", effect = { speed_mult = 1.12, kite_speed_mult = 1.12, crit_add = 0.10, dodge_recharge_mult = 0.80 } },
                { id = "queen_carapace", slot = "body", rarity = "epic", name = "Queen's Carapace", weight = 26,
                  desc = "+70 HP, +12% armor, +1 regen", effect = { hp_max_add = 70.0, armor_add = 0.12, regen_add = 1.0 } },
                { id = "guard_sabatons", slot = "pants", rarity = "rare", name = "Guard Sabatons", weight = 24,
                  desc = "+30 HP, +8% armor, +6 thorns", effect = { hp_max_add = 30.0, armor_add = 0.08, thorns_add = 6.0 } },
                { id = "zephyr_boots", slot = "pants", rarity = "epic", name = "Zephyr Boots", weight = 6,
                  desc = "+20% move, dodge 25% faster", effect = { speed_mult = 1.20, kite_speed_mult = 1.20, dodge_recharge_mult = 0.75 } },
                { id = "leech_wraps", slot = "gloves", rarity = "rare", name = "Leech Wraps", weight = 7,
                  desc = "+1.5 lifesteal, +4 damage", effect = { lifesteal_add = 1.5, dps_add = 4.0 } },
                { id = "colossus_fists", slot = "gloves", rarity = "epic", name = "Colossus Fists", weight = 22,
                  desc = "+18 damage, +10% armor", effect = { dps_add = 18.0, armor_add = 0.10 } },
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
                { id = "hive_locket", slot = "jewelry", rarity = "rare", name = "Hive Locket", weight = 0,
                  desc = "+15 HP, +2 regen, +10% gold", effect = { hp_max_add = 15.0, regen_add = 2.0, gold_find_add = 0.10 } },
                { id = "phase_charm", slot = "jewelry", rarity = "epic", name = "Phase Charm", weight = 0,
                  desc = "+1 dodge charge", effect = { dodge_charge_add = 1 } },
                { id = "kings_signet", slot = "jewelry", rarity = "epic", name = "King's Signet", weight = 0,
                  desc = "+25% gold, +12% damage", effect = { gold_find_add = 0.25, dps_mult = 1.12 } },
            },
        },

        -- seed_spitter is back: it now fires a VISIBLE seed bolt (Duel creep
        -- projectiles), so its damage is attributable and dodgeable instead of the
        -- old silent stand-off field.
        auto_mix = function(D)
            local wave = D.wave_index or 1
            local n = D.spawn_counter
            local map = D.map_index or 1
            if map >= 3 then
                -- ROYAL GARDEN — armored formations, snipers, sappers.
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
        end,

        hooks = {
            on_reset = function(D)
                if D.hero then D.hero.move_mult = 1.0 end
                D._topdown_dressed = nil
                View.prewarm(D)
            end,
            on_prewarm_spawn = function(D, creep)
                View.on_spawn(D, creep)
            end,
            on_spawn = function(D, creep)
                View.on_spawn(D, creep)
            end,
            on_combat_tick = function(D, _dt)
                View.tick(D)
            end,
            -- Per-frame HUD overlay hook (runs at the end of update_hud, every frame
            -- in all states: classpick/combat/pause/end).
            draw_hud = function(D)
                -- Hide the attack-range disc. The Duel builds a Hero_Aura cylinder
                -- sized to attack_range*2 (a big ring) and re-scales it every frame;
                -- it renders on the OPAQUE deferred path (ignores base_color alpha),
                -- so a transparent colour just yields a black disc, and post-creation
                -- scale writes don't reach the renderer. PARK it offstage instead:
                -- position writes always render (same trick the dev hitbox pool uses).
                local aura = D.hero and D.hero.parts and D.hero.parts.aura
                if aura and Art.valid(aura) then aura:set_position(vec3(1.0e6, 0.0, 0.0)) end

                -- HUD declutter (draw_hud runs at the END of update_hud, after the
                -- Duel set these quads, so removals win this frame). The authored HUD
                -- nodes + the authored Pause Menu own the screen now, so the transient
                -- top-left "stat" panel is always removed (it overlapped the authored
                -- pause/inventory). Drop the duel's HP-bar quads on the gear screen too.
                Art.remove(D.hud, "stat")
                if D.state == "pause" or D.state == "town" or D.state == "worldmap" then
                    Art.remove(D.hud, "hp_bg"); Art.remove(D.hud, "hp_fg"); Art.remove(D.hud, "hp_label")
                end

                local vw = Art.surface_size()
                -- FPS clock (top-right) on the DIRECT-BOOT path only (Android, or the
                -- ATH_MODE=arena quick-launch) — there is no menu shell to draw it.
                -- On the menu path the shell owns the FPS clock, so this stays off to
                -- avoid a double. ath_android_boot sets config.direct_boot.
                if D.config.direct_boot then Art.draw_fps_clock(D.hud, vw) end

                -- NO letterbox: the scene-driven build fills the window at its
                -- native aspect (Free) with an anchored authored HUD, and the floor
                -- over-fills the view (arena.floor_extent), so the green covers the
                -- whole screen instead of masking the overscan to a 20:9 band.
            end,
        },
    },
}
