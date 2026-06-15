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
                    hp_max = 105.0, dps = 22.0, cleave = 3, attack_range = 9.0,
                    fire_interval = 0.26, speed = 8.5, kite_speed = 8.5,
                    sprite_texture = Spud.tex.hero,
                    bolt_color = { 1.0, 0.90, 0.42 }, bolt_scale = 0.34,
                },
                {
                    id = "brawler", name = "Brawler", attack = "melee",
                    blurb = "Cleaves all in reach. Tanky - wade into the swarm.",
                    accent = { 0.92, 0.42, 0.34, 0.95 },
                    hp_max = 155.0, dps = 30.0, cleave = 4, attack_range = 1.8,
                    speed = 9.0, kite_speed = 9.0,
                    sprite_texture = Spud.tex.brawler,
                },
                {
                    id = "sower", name = "Sower", attack = "ranged",
                    blurb = "Sprays seed-shot at the nearest five. Short range, fast.",
                    accent = { 0.54, 0.82, 0.40, 0.95 },
                    hp_max = 95.0, dps = 13.0, cleave = 5, attack_range = 6.0,
                    fire_interval = 0.32, speed = 8.3, kite_speed = 8.3,
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
            budgets = { 90, 120, 160, 210, 270 },
        },
        reserve_start = 90.0,
        round_seconds = 9999.0,
        -- Creeps spawn a bit beefier than their base archetype HP (applied in
        -- Duel:spawn_one via Creep.create's hp_multiplier).
        creep_hp_mult = 1.3,
        kill_fx_budget_per_frame = 6,
        warm_pool_count = 0,
        prewarm_order = { "sprout", "husk_knight", "crow", "pumpkin_brute", "seed_spitter", "beetle", "corn_mortar", "wasp" },
        -- Pre-build + PARK this many rigs per type at run start (warm_archetype
        -- now populates the pool). Kept ABOVE each type's realistic peak-alive at
        -- cap_max=85 so the pool never empties -> combat spawns reuse parked rigs
        -- and never build a rig mid-frame (the spawn spike). Also avoids the
        -- mid-combat alpha-cut geometry-add RT hazard.
        prewarm = { sprout = 56, husk_knight = 32, pumpkin_brute = 16, crow = 22, seed_spitter = 14, beetle = 26, corn_mortar = 10, wasp = 18 },

        gear = {
            gold_per_kill = 1,
            drop_every = 7,
            -- Loot table for the 6-slot paper-doll (helmet/body/pants/gloves/
            -- weapon/jewelry). Drops cycle this list into the backpack; rarity
            -- tints the slot border in the inventory.
            items = {
                -- helmet
                { id = "straw_hat", slot = "helmet", rarity = "common", name = "Straw Hat",
                  desc = "+18 HP", effect = { hp_max_add = 18.0 } },
                { id = "iron_helm", slot = "helmet", rarity = "uncommon", name = "Iron Helm",
                  desc = "+28 HP, +8% armor", effect = { hp_max_add = 28.0, armor_add = 0.08 } },
                -- body
                { id = "field_vest", slot = "body", rarity = "common", name = "Field Vest",
                  desc = "+30 HP", effect = { hp_max_add = 30.0 } },
                { id = "husk_plate", slot = "body", rarity = "uncommon", name = "Husk Plate",
                  desc = "+55 HP, +12% armor, -6% move", effect = { hp_max_add = 55.0, armor_add = 0.12, speed_mult = 0.94, kite_speed_mult = 0.94 } },
                -- pants
                { id = "work_trousers", slot = "pants", rarity = "common", name = "Work Trousers",
                  desc = "+10% move", effect = { speed_mult = 1.10, kite_speed_mult = 1.10 } },
                { id = "sprint_greaves", slot = "pants", rarity = "uncommon", name = "Sprint Greaves",
                  desc = "+18% move, +12 HP", effect = { speed_mult = 1.18, kite_speed_mult = 1.18, hp_max_add = 12.0 } },
                -- gloves
                { id = "garden_gloves", slot = "gloves", rarity = "common", name = "Garden Gloves",
                  desc = "+12% attack speed", effect = { fire_interval_mult = 0.88 } },
                { id = "gauntlets", slot = "gloves", rarity = "uncommon", name = "Gauntlets",
                  desc = "+4 damage, +6% attack speed", effect = { dps_add = 4.0, fire_interval_mult = 0.94 } },
                -- weapon
                { id = "field_spear", slot = "weapon", rarity = "common", name = "Field Spear",
                  desc = "+0.6 reach, +3 damage", effect = { attack_range_add = 0.6, dps_add = 3.0 } },
                { id = "cleaver", slot = "weapon", rarity = "uncommon", name = "Cleaver",
                  desc = "+2 cleave, -8% move", effect = { cleave_add = 2, speed_mult = 0.92, kite_speed_mult = 0.92 } },
                { id = "seed_cannon", slot = "weapon", rarity = "rare", name = "Seed Cannon",
                  desc = "+1 shot, +2 range, +15% damage", effect = { cleave_add = 1, attack_range_add = 2.0, dps_mult = 1.15 } },
                -- jewelry
                { id = "swift_band", slot = "jewelry", rarity = "common", name = "Swift Band",
                  desc = "+12% move, +8 HP", effect = { speed_mult = 1.12, kite_speed_mult = 1.12, hp_max_add = 8.0 } },
                { id = "red_charm", slot = "jewelry", rarity = "uncommon", name = "Red Charm",
                  desc = "+1 lifesteal, +10% damage", effect = { lifesteal_add = 1.0, dps_mult = 1.10 } },
                { id = "crit_ring", slot = "jewelry", rarity = "rare", name = "Crit Ring",
                  desc = "+30% crit, +5 damage", effect = { crit_add = 0.30, dps_add = 5.0 } },
            },
        },

        -- seed_spitter is back: it now fires a VISIBLE seed bolt (Duel creep
        -- projectiles), so its damage is attributable and dodgeable instead of the
        -- old silent stand-off field.
        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 13 == 0) then
                return "pumpkin_brute"
            end
            if D.spawn_counter % 11 == 0 then return "corn_mortar" end
            if D.spawn_counter % 8 == 0 then return "crow" end
            if D.spawn_counter % 7 == 0 then return "wasp" end
            if D.spawn_counter % 6 == 0 then return "seed_spitter" end
            if D.spawn_counter % 4 == 0 then return "beetle" end
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

                -- HUD declutter by state (draw_hud runs at the END of update_hud,
                -- after the Duel set these quads, so removals win this frame):
                --  * live play  -> hide the top-left "stat" panel; combat stays clean
                --    (just the HP bar + wave-budget bar).
                --  * pause/gear -> hide the wide top HP bar; the inventory's TOTAL
                --    STATS panel already shows Health, and the HP bar otherwise
                --    collides with the top-left stat panel on the gear screen.
                if D.state ~= "pause" then
                    Art.remove(D.hud, "stat")
                else
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
