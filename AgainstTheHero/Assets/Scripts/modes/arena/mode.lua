-- Arena — manual hero experiment.
--
-- A deliberately thin mode for PLAN.md experiment #1: same shared Duel spine,
-- current flat-sprite presentation, no cards, no shell, no hero AI. The player
-- drives the hero with WASD/arrow keys while auto-attacks and wave/gear logic
-- live behind config.manual_hero in ath_duel.lua.

local Art  = ATH_COMMON.load_script("Scripts/shared/ath_art.lua",              "shared art",       _ENV)
local View = ATH_COMMON.load_script("Scripts/shared/ath_topdown_view.lua",     "top-down view",    _ENV)
local Spud = ATH_COMMON.load_script("Scripts/modes/spud_fields/characters.lua", "spud_fields cast", _ENV)

local Balance = ATH_COMMON.load_script("Scripts/shared/ath_balance.lua", "balance database", _ENV)
local ARCHETYPES = Balance.build_monsters(Spud.archetypes)
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
            -- World-size multiplier on the hero body quad (hitbox tracks it).
            -- Bumped after animated sheets: fit-to-cell left more transparent
            -- padding, so 1.0 read tiny vs creeps. Tune with console O/P + R.
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
            sprite_texture = "Textures/modes/arena/hero_ranger.png",
            -- Selectable classes (chosen on a pick screen at run start). Each is an
            -- attack IDENTITY — ranged bolts, melee cleave, or seed-scatter — that
            -- gear/cards later bend. Stats here override the hero baseline above.
            default_class = "ranger",
            classes = Balance.classes,
        },
        archetypes = ARCHETYPES,
        roles = Spud.roles,
        spawn = Balance.rules.arena.spawn,
        waves = {
            count = 5,
            budgets = Balance.rules.arena.wave_budgets,
        },
        -- Fallback boss when no map def is active; maps override per run.
        boss_archetype = "gourd_king",
        boss_title = "GOURD KING",
        -- MAPS — the run ladder. Each map is the same authored stage with its own
        -- wave count, boss, enemy mix (auto_mix reads D.map_index), difficulty
        -- multipliers and loot weights. Clearing a map unlocks the next
        -- (persisted in Save/profile.lua). Gold scales steeply with rank so
        -- deeper maps are the real income (suicide-farming map I stays poor).
        -- pos = {x, y} fraction of the painted world-map ARTWORK (raw surface,
        -- full-bleed) — each map anchors to a building painted on it.
        worldmap_image = "Textures/ui/map/worldmap.png",
        -- The journey road the dots trace — the user's numbered stations 1..12:
        -- bottom row west->east (1-5), middle row back east->west (5-10), then
        -- the top run past the old castle to the great castle (10-12).
        worldmap_route = {
            { 0.225, 0.590 }, -- 1 Spud Fields
            { 0.290, 0.630 },
            { 0.372, 0.635 }, -- 2 Hollow Hive
            { 0.478, 0.548 }, -- 3 Sprout Hamlet
            { 0.560, 0.530 },
            { 0.628, 0.510 }, -- 4 Bramble Cottages
            { 0.705, 0.440 }, -- 5 Mossy Croft
            { 0.812, 0.422 }, -- 6 The Old Mill
            { 0.740, 0.400 },
            { 0.645, 0.380 }, -- 7 Harvest Row
            { 0.600, 0.415 },
            { 0.530, 0.425 }, -- 8 Gourdhall
            { 0.565, 0.370 },
            { 0.585, 0.320 }, -- 9 Withervane Farm
            { 0.475, 0.295 }, -- 10 Crowfield Grange
            { 0.400, 0.345 },
            { 0.280, 0.355 },
            { 0.150, 0.360 }, -- 11 Wyrmroot Hermitage
            { 0.210, 0.300 },
            { 0.295, 0.295 }, -- 12 Royal Garden (the old castle)
            { 0.450, 0.265 },
            { 0.650, 0.245 },
            { 0.805, 0.185 }, -- 13 Castle Ovrevand
        },
        -- THE LADDER — all 13 painted stations are maps, built from parallel
        -- curves so every knob stays visible. Maps 1-3 keep the smoke-validated
        -- numbers exactly; the rest extend the same curves. Bosses cycle the
        -- three arches with escalating titles; floors live in
        -- Textures/modes/arena/floors/<id>.png (map 1 keeps the authored floor).
        maps = (function()
            local defs = {
                { id = "spud_fields", name = "Spud Fields", boss = "gourd_king", boss_title = "GOURD KING",
                  pos = { 0.225, 0.590 }, blurb = "Rolling farmland overrun by the sprouting dead." },
                { id = "hollow_hive", name = "Hollow Hive", boss = "wasp_queen", boss_title = "WASP QUEEN",
                  pos = { 0.372, 0.635 }, blurb = "A droning windmill - the air itself stings." },
                { id = "sprout_hamlet", name = "Sprout Hamlet", boss = "corn_colossus", boss_title = "CORN COLOSSUS",
                  pos = { 0.478, 0.548 }, blurb = "A sleepy hamlet gone to seed." },
                { id = "bramble_cottages", name = "Bramble Cottages", boss = "gourd_king", boss_title = "ELDER GOURD KING",
                  pos = { 0.628, 0.510 }, blurb = "Briars swallowed these cottages years ago." },
                { id = "mossy_croft", name = "Mossy Croft", boss = "wasp_queen", boss_title = "ELDER WASP QUEEN",
                  pos = { 0.705, 0.440 }, blurb = "Moss-choked crofts where the ground squelches." },
                { id = "old_mill", name = "The Old Mill", boss = "corn_colossus", boss_title = "ELDER CORN COLOSSUS",
                  pos = { 0.812, 0.422 }, blurb = "The millstone still turns, though no miller lives." },
                { id = "harvest_row", name = "Harvest Row", boss = "gourd_king", boss_title = "DREAD GOURD KING",
                  pos = { 0.645, 0.380 }, blurb = "Market stalls picked clean by crow and creep." },
                { id = "gourdhall", name = "Gourdhall", boss = "wasp_queen", boss_title = "DREAD WASP QUEEN",
                  pos = { 0.530, 0.425 }, blurb = "The harvest lords feasted here. Something still does." },
                { id = "withervane_farm", name = "Withervane Farm", boss = "corn_colossus", boss_title = "DREAD CORN COLOSSUS",
                  pos = { 0.585, 0.320 }, blurb = "The weathervane spins with no wind." },
                { id = "crowfield_grange", name = "Crowfield Grange", boss = "gourd_king", boss_title = "ETERNAL GOURD KING",
                  pos = { 0.475, 0.295 }, blurb = "Crows watch the pale fields. They are not crows." },
                { id = "wyrmroot_hermitage", name = "Wyrmroot Hermitage", boss = "wasp_queen", boss_title = "ETERNAL WASP QUEEN",
                  pos = { 0.150, 0.360 }, blurb = "A hermit's hollow twisted by old roots." },
                { id = "royal_garden", name = "Royal Garden", boss = "corn_colossus", boss_title = "ETERNAL CORN COLOSSUS",
                  pos = { 0.295, 0.295 }, blurb = "The overgrown palace grounds of the Corn Court." },
                { id = "castle_ovrevand", name = "Castle Ovrevand", boss = "gourd_king", boss_title = "KING OF OVREVAND",
                  pos = { 0.805, 0.185 }, blurb = "The throne of Ovrevand. The King is home." },
            }
            Balance.apply_map_progression(defs)
            for i, map in ipairs(defs) do
                if i > 1 then map.floor = "Textures/modes/arena/floors/" .. map.id .. ".png" end
            end
            return defs
        end)(),
        reserve_start = Balance.rules.arena.reserve_start,
        round_seconds = 9999.0,
        -- Creeps spawn a bit beefier than their base archetype HP (applied in
        -- Duel:spawn_one via Creep.create's hp_multiplier).
        creep_hp_mult = Balance.rules.arena.creep_hp_mult,
        kill_fx_budget_per_frame = 6,
        warm_pool_count = 0,
        prewarm_order = { "sprout", "husk_knight", "crow", "pumpkin_brute", "seed_spitter", "beetle", "corn_mortar", "wasp", "ram_beetle", "blast_bud", "thorn_guard", "spore_witch", "brood_pod", "stinger_drone", "hive_matron", "bomber_beetle", "royal_guard", "corn_arbalest", "gourd_sapper", "flask_hunter", "briar_hound", "mill_wraith", "harvest_reaper", "carrion_flock", "root_horror", "royal_sentinel", "gourd_king", "wasp_queen", "corn_colossus" },
        -- One bounded visual pool budget: sprite variants sharing an atlas share
        -- their identical quad rigs. Keep enough interchangeable quads for the
        -- live cap plus one spawn batch and the short deferred-death overlap.
        prewarm_total = Balance.rules.arena.spawn.cap_max + Balance.rules.arena.spawn.batch_max + 5,
        prewarm = { sprout = 18, husk_knight = 6, pumpkin_brute = 2, crow = 4, seed_spitter = 4, beetle = 8, corn_mortar = 2, wasp = 5, ram_beetle = 2, blast_bud = 2, thorn_guard = 2, spore_witch = 2, brood_pod = 1,
            stinger_drone = 3, hive_matron = 1, bomber_beetle = 2, royal_guard = 2, corn_arbalest = 2, gourd_sapper = 2, flask_hunter = 2,
            briar_hound = 2, mill_wraith = 2, harvest_reaper = 2, carrion_flock = 2, root_horror = 1, royal_sentinel = 1,
            gourd_king = 1, wasp_queen = 1, corn_colossus = 1 },

        gear = {
            gold_per_kill = Balance.rules.economy.gold_per_kill,
            drop_every = Balance.rules.economy.drop_every,
            -- Loot table for the 6-slot paper-doll (helmet/body/pants/gloves/
            -- weapon/jewelry). Drops cycle this list into the backpack; rarity
            -- tints the slot border in the inventory.
            items = Balance.items,
        },

        -- seed_spitter is back: it now fires a VISIBLE seed bolt (Duel creep
        -- projectiles), so its damage is attributable and dodgeable instead of the
        -- old silent stand-off field.
        auto_mix = Balance.auto_mix,

        hooks = {
            on_reset = function(D)
                if D.hero then D.hero.move_mult = 1.0 end
                if D.mode_started then View.prewarm(D) end
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
                -- Draft/town/classpick freeze combat_tick, but the adopted scene hero
                -- still ships with Spud's chicken texture until View.tick skins it.
                if D.state ~= "combat" then View.tick(D) end

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
                if D.state == "pause" or D.state == "town" or D.state == "worldmap" or D.state == "specpick" then
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
