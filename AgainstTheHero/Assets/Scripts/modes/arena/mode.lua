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
    seed_spitter  = tuned(Spud.archetypes.seed_spitter,  { range = 4.5, hold_range = 4.5, speed = 2.2 }),
    husk_knight   = tuned(Spud.archetypes.husk_knight,   { range = 0.6, speed = 3.0 }),
    pumpkin_brute = tuned(Spud.archetypes.pumpkin_brute, { range = 0.7, speed = 2.2 }),
    -- Crow stays BELOW hero speed (8.5): anything faster than the hero is
    -- unavoidable by movement alone (there is no dash/dodge yet).
    crow          = tuned(Spud.archetypes.crow,          { range = 0.4, speed = 5.0 }),
}

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
            -- Playable pit fills the whole visible band so the hero can roam the
            -- WHOLE map. ortho_size = world height visible in the letterboxed band
            -- (see Art.setup_iso_camera); 50/zoom ≈ 30, and the 20:9 band is
            -- ~67x30 world units, so a 64x28 pit puts the fence walls right at the
            -- screen edges with the floor covering the rest.
            width = 64, height = 28, pad = 2,
            ortho_size = 50.0,
            floor_extent = { width = 72.0, height = 34.0 },
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
            budgets = { 90, 120, 160, 210, 270 },
        },
        reserve_start = 90.0,
        round_seconds = 9999.0,
        -- Creeps spawn a bit beefier than their base archetype HP (applied in
        -- Duel:spawn_one via Creep.create's hp_multiplier).
        creep_hp_mult = 1.3,
        kill_fx_budget_per_frame = 6,
        warm_pool_count = 0,
        prewarm_order = { "sprout", "husk_knight", "crow", "pumpkin_brute" },
        -- Pre-build + PARK this many rigs per type at run start (warm_archetype
        -- now populates the pool). Kept ABOVE each type's realistic peak-alive at
        -- cap_max=85 so the pool never empties -> combat spawns reuse parked rigs
        -- and never build a rig mid-frame (the spawn spike). Also avoids the
        -- mid-combat alpha-cut geometry-add RT hazard.
        prewarm = { sprout = 72, husk_knight = 40, pumpkin_brute = 16, crow = 24 },

        gear = {
            gold_per_kill = 1,
            drop_every = 7,
            items = {
                {
                    id = "field_spear", slot = "weapon", name = "Field Spear",
                    desc = "+0.40 reach, +3 damage",
                    effect = { attack_range_add = 0.40, dps_add = 3.0 },
                },
                {
                    id = "cleaver", slot = "weapon", name = "Cleaver",
                    desc = "+2 cleave, -10% speed",
                    effect = { cleave_add = 2, speed_mult = 0.90, kite_speed_mult = 0.90 },
                },
                {
                    id = "fleet_boots", slot = "trinket", name = "Fleet Boots",
                    desc = "+22% move speed",
                    effect = { speed_mult = 1.22, kite_speed_mult = 1.22 },
                },
                {
                    id = "field_plate", slot = "armor", name = "Field Plate",
                    desc = "+35 HP, +12% armor, -8% speed",
                    effect = { hp_max_add = 35.0, armor_add = 0.12, speed_mult = 0.92, kite_speed_mult = 0.92 },
                },
                {
                    id = "red_charm", slot = "trinket", name = "Red Charm",
                    desc = "+1 lifesteal, +10% damage",
                    effect = { lifesteal_add = 1.0, dps_mult = 1.10 },
                },
            },
        },

        -- NO seed_spitter in the mix for now: its "attack" is a silent stand-off
        -- damage field (no projectile visual exists), which on-device reads as
        -- the hero constantly losing HP out of nowhere (confirmed via [DMG]
        -- logging). Bring it back once ranged attacks have a visible projectile.
        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 13 == 0) then
                return "pumpkin_brute"
            end
            if D.spawn_counter % 8 == 0 then return "crow" end
            if D.spawn_counter % 3 == 0 then return "husk_knight" end
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
        },
    },
}
