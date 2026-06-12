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
local ARCHETYPES = {
    sprout        = tuned(Spud.archetypes.sprout,        { range = 0.35, speed = 2.1 }),
    seed_spitter  = tuned(Spud.archetypes.seed_spitter,  { range = 4.5, hold_range = 4.5, speed = 1.1 }),
    husk_knight   = tuned(Spud.archetypes.husk_knight,   { range = 0.6, speed = 1.5 }),
    pumpkin_brute = tuned(Spud.archetypes.pumpkin_brute, { range = 0.7, speed = 1.1 }),
    -- Crow stays BELOW hero speed (2.8): anything faster than the hero is
    -- unavoidable by movement alone (there is no dash/dodge yet).
    crow          = tuned(Spud.archetypes.crow,          { range = 0.4, speed = 2.5 }),
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
            -- Smaller pit than the card modes: creeps reach the hero in seconds
            -- and everything reads bigger. ortho_size = world height visible in
            -- the letterboxed band (see Art.setup_iso_camera); 50/zoom ≈ 30
            -- shows the full 26-tall arena plus a small margin.
            width = 36, height = 26, pad = 2,
            ortho_size = 50.0,
            -- Grass fills the whole visible 20:9 band (~67x30 world units) even
            -- though the playable pit stays 36x26 — the fence walls mark the edge.
            floor_extent = { width = 70.0, height = 32.0 },
            -- Spawn ON SCREEN: a ring around the hero start (18,13) instead of
            -- the far arena perimeter, so creeps are visible the moment they
            -- spawn and reach the fight in a few seconds.
            spawns = {
                { x = 5, y = 13 }, { x = 31, y = 13 },
                { x = 18, y = 4 }, { x = 18, y = 22 },
                { x = 8, y = 5 }, { x = 28, y = 5 },
                { x = 8, y = 21 }, { x = 28, y = 21 },
            },
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
            hp_max = 105.0, dps = 22.0, cleave = 3, attack_range = 1.35,
            -- Comfortably faster than the swarm (creep speeds also pass through
            -- Creep.SPEED_SCALE). body_radius is derived from the rendered
            -- sprite size in ath_topdown_view, not set here.
            speed = 1.4, kite_speed = 1.4,
            sprite_texture = Spud.tex.hero,
        },
        archetypes = ARCHETYPES,
        roles = Spud.roles,
        spawn = {
            interval_start = 0.90, interval_min = 0.34,
            batch_start = 2, batch_max = 6,
            cap_start = 26, cap_max = 58,
            brute_after = 26.0,
        },
        waves = {
            count = 5,
            budgets = { 42, 58, 76, 98, 124 },
        },
        reserve_start = 42.0,
        round_seconds = 9999.0,
        kill_fx_budget_per_frame = 5,
        warm_pool_count = 0,
        prewarm_order = { "sprout", "husk_knight", "crow", "pumpkin_brute" },
        prewarm = { sprout = 64, husk_knight = 20, pumpkin_brute = 8, crow = 16 },

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
