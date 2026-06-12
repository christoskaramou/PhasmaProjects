-- Frozen Depths — the cast (DATA only).
--
-- FROZEN DEPTHS is a bespoke 2D SIDE-SCROLLER with gravity (run-and-leap through
-- an ice cave; ice physics make the hero SLIDE — see mode.lua). Like THE PIT it
-- does NOT run on the 3D Duel engine; it has its own real-time loop drawn on the
-- runtime_ui canvas. So this file is split into two clearly-labelled halves:
--
--   1. Frozen.frozen2d — the data the 2D game actually reads: the long horizontal
--      cave (3 chambers, each more iced-over), the floor tile types, the horde the
--      player seeds before the run (Ice Wight / Frost Archer / Ice Wall / Freeze
--      Trap), the Glacial Warden boss that garrisons chamber 3, the two heroes
--      (Forge Walker / Ice Born), every sprite path, and the frozen palette.
--      THIS is the heart of the mode.
--
--   2. Frozen.theme / hero_actor / archetypes / roles — a MINIMAL but valid
--      shared-Duel config so the mode still shows up and plays if launched from
--      the menu (which always drives index modes through ath_duel.lua). The same
--      cast reshaped into horde/creep.lua archetypes; the Freeze Trap becomes the
--      Duel's environmental hazard (a floor patch that FREEZES the hero in place)
--      rather than a placeable.
--
-- Every sprite below is produced by tools/gen_textures_frozen.py into
--   Assets/Objects/frozen_depths/   (the engine roots texture/image paths at the
-- Assets/ folder, so the Lua side references them as "Objects/frozen_depths/...").
-- The art is OPTIONAL: if a PNG is absent, every entity still draws as its flat
-- silhouette colour, so the game is fully playable before art exists.
--
-- Aesthetic: Dark Souls in deep blue. Lightless cave-black, glacier blues, frost
-- white, and the one warm thing down here — the Forge Walker's ember. Grim, cold.

local Frozen = {}

-- ---------------------------------------------------------------------------
-- Palette — the brief's notes plus tints derived from them.
--   #000d1a deep cave · #001a33 cave · #0033aa ice blue · #88ccff ice bright
--   #ffffff frost · #8b0000 blood-on-ice
-- ---------------------------------------------------------------------------
local C = {
    deep      = { 0.000, 0.051, 0.102 },   -- #000d1a — the cave dark
    cave      = { 0.000, 0.102, 0.200 },   -- #001a33 — wall stone
    cave_lo   = { 0.000, 0.075, 0.150 },
    ice       = { 0.000, 0.200, 0.667 },   -- #0033aa — glacier ice
    ice_lo    = { 0.000, 0.149, 0.420 },
    bright    = { 0.533, 0.800, 1.000 },   -- #88ccff — lit ice / shine
    frost     = { 1.000, 1.000, 1.000 },   -- #ffffff — frost / rime
    blood     = { 0.545, 0.000, 0.000 },   -- #8b0000 — blood on ice
    blood_hot = { 0.740, 0.100, 0.100 },
    steel     = { 0.450, 0.520, 0.620 },   -- iron / weapon
    stone     = { 0.180, 0.210, 0.260 },   -- bare rock floor
    stone_lo  = { 0.120, 0.150, 0.190 },
    fire      = { 1.000, 0.450, 0.120 },   -- the Forge Walker's ember (only warmth)
    fire_hot  = { 1.000, 0.620, 0.260 },
}
Frozen.palette = C

local TEX = "Objects/frozen_depths/"

-- ===========================================================================
-- 1. Frozen.frozen2d — the data the 2D side-scroller reads.
-- ===========================================================================

Frozen.frozen2d = {
    palette = C,

    -- Shared environment / projectile / decal art (drawn on the canvas).
    sprites = {
        floor_stone = TEX .. "floor_stone.png",   -- 64x64 bare rock (high friction)
        floor_ice   = TEX .. "floor_ice.png",     -- 64x64 blue ice + shine (slides!)
        ice_wall    = TEX .. "ice_wall.png",       -- breakable blocker tile
        icicle      = TEX .. "icicle.png",         -- hanging stalactite (ceiling dressing)
        frost       = TEX .. "frost_particle.png", -- spark of frost (bursts / trail)
        arrow       = TEX .. "frost_arrow.png",    -- the Frost Archer's bolt
        gate        = TEX .. "ice_gate.png",       -- the sealed exit (drops when boss dies)
        blood       = TEX .. "blood_ice.png",      -- blood-on-ice splat decal
        -- Animated sheets are shipped as separate frames the canvas swaps by
        -- `image` (no UV sub-rects needed) — same trick THE PIT uses for torches.
        wight_frames  = { TEX .. "ice_wight_f0.png", TEX .. "ice_wight_f1.png", TEX .. "ice_wight_f2.png",
                          TEX .. "ice_wight_f3.png", TEX .. "ice_wight_f4.png", TEX .. "ice_wight_f5.png" },
        archer_frames = { TEX .. "frost_archer_f0.png", TEX .. "frost_archer_f1.png", TEX .. "frost_archer_f2.png",
                          TEX .. "frost_archer_f3.png", TEX .. "frost_archer_f4.png" },
        warden_frames = { TEX .. "glacial_warden_f0.png", TEX .. "glacial_warden_f1.png", TEX .. "glacial_warden_f2.png",
                          TEX .. "glacial_warden_f3.png", TEX .. "glacial_warden_f4.png", TEX .. "glacial_warden_f5.png",
                          TEX .. "glacial_warden_f6.png", TEX .. "glacial_warden_f7.png" },
        trap_frames   = { TEX .. "freeze_trap_f0.png", TEX .. "freeze_trap_f1.png", TEX .. "freeze_trap_f2.png" },
    },

    -- The cave: ONE long horizontal corridor read left->right, split into three
    -- chambers each more iced-over than the last. World units; mode.lua maps them
    -- to canvas pixels with a side-on, hero-tracking camera (y is UP).
    arena = {
        length     = 90.0,                 -- total span (x: 0 .. length)
        height     = 16.0,                 -- visible vertical world units
        floor_y    = 0.0,                  -- the cave floor the hero stands on
        ceiling_y  = 11.0,                 -- icicles hang from here
        tile       = 2.0,                  -- floor-tile span along x
        chambers   = 3,
        hero_spawn = { x = 4.0, y = 0.0 }, -- the hero drops in at the mouth (west)
        exit       = { x = 87.0, y = 0.0 },-- and must reach the breach (east)
        exit_radius = 2.2,
        warden_x   = 74.0,                 -- the Glacial Warden garrisons chamber 3
        -- Fraction of floor tiles that are ICE in each chamber: deeper = more
        -- coverage, more slide (the brief's "deeper into the cave = more ice").
        ice_density = { 0.22, 0.58, 0.92 },
    },

    -- The hero can leap (gravity-arc). Tuned here so both the game and the HUD
    -- agree on the physics.
    physics = {
        gravity   = 30.0,                  -- units/s^2 downward pull
        jump_apex = 3.4,                   -- peak leap height (world units)
    },

    -- The horde the player SEEDS before the run (up to `budget`, any mix). The
    -- Glacial Warden is NOT placeable — it always garrisons chamber 3.
    placement = { budget = 7 },

    -- ---- HORDE: the four things you place down the cave ----------------------
    horde = {
        -- ICE WIGHT — melee. Shambles toward the hero and LEAVES A FREEZE TRAIL:
        -- a wake of frost patches that slow (and, if you linger, freeze) the hero.
        ice_wight = {
            id = "ice_wight", name = "Ice Wight", kind = "wight", role = "melee",
            frames = "wight_frames", color = C.bright, glow = C.ice,
            size = 1.7, radius = 0.55,
            hp = 70.0, speed = 3.0,
            touch_damage = 14.0, touch_cd = 0.8,
            trail_cd = 0.35,                 -- drops a trail patch this often while moving
            trail_life = 3.2, trail_slow = 0.45,
            sway_amp = 0.08, sway_freq = 4.0, anim_fps = 8.0,
            blurb = "Melee. Shambles in, trailing freezing frost.",
        },
        -- FROST ARCHER — ranged. Holds a distance and looses bolts that SLOW the
        -- hero on hit (a sticky rime, not a freeze).
        frost_archer = {
            id = "frost_archer", name = "Frost Archer", kind = "archer", role = "ranged",
            frames = "archer_frames", color = C.steel, glow = C.bright,
            size = 1.6, radius = 0.55,
            hp = 50.0, speed = 2.4,
            prefer_range = 12.0, retreat_range = 7.0, hold_range = 16.0,
            shoot_cd = 1.7,
            projectile = {
                speed = 16.0,                -- horizontal travel (u/s)
                gravity = 9.0,               -- the bolt drops, so it leads a runner
                damage = 12.0, hit_radius = 0.7, size = 0.9,
                slow_mult = 0.50, slow_time = 2.4,   -- "slow-on-hit"
            },
            sway_amp = 0.05, sway_freq = 3.0, anim_fps = 7.0,
            blurb = "Ranged. Bolts that slow you to a crawl on hit.",
        },
        -- ICE WALL — a deployable blocker. Static, tall, breakable: the hero must
        -- SMASH it (melee) to open the passage. Deeper walls are tougher.
        ice_wall = {
            id = "ice_wall", name = "Ice Wall", kind = "wall", role = "blocker",
            sprite = TEX .. "ice_wall.png", color = C.ice, glow = C.bright,
            size = 2.4, radius = 0.9,
            hp = 120.0, wall_w = 1.4, wall_h = 4.4,
            blurb = "Static blocker. Smash it to pass.",
        },
        -- FREEZE TRAP — a floor patch. Arms; when the hero steps over it it
        -- SHIMMERS (0.8s telegraph), then FREEZES him in place for 2s.
        freeze_trap = {
            id = "freeze_trap", name = "Freeze Trap", kind = "trap", role = "trap",
            frames = "trap_frames", color = C.bright, glow = C.frost,
            size = 1.9, radius = 0.95,
            trigger_radius = 1.6, telegraph = 0.8, freeze_time = 2.0, rearm = 3.2,
            blurb = "Floor patch. Shimmers, then freezes you solid (2s).",
        },
    },
    -- Display order for the placement palette.
    horde_order = { "ice_wight", "frost_archer", "ice_wall", "freeze_trap" },

    -- ---- THE BOSS: the Glacial Warden (auto-garrisons chamber 3) --------------
    -- A mountainous ice giant. Approaches slow, leaving a freeze trail; rears back
    -- and exhales an ICE-BREATH CONE that damages and freezes anything grounded in
    -- it (leap to clear it). Slaying it drops the ice gate and opens the breach.
    boss = {
        id = "glacial_warden", name = "The Glacial Warden",
        frames = "warden_frames", color = C.bright, glow = C.ice,
        size = 6.0, radius = 2.0, height = 5.2,
        hp = 900.0, speed = 1.7,
        contact_damage = 26.0, contact_cd = 1.0,
        trail_cd = 0.5, trail_life = 4.0, trail_slow = 0.35, trail_freeze = 1.0,
        -- Ice-breath cone.
        breath_range = 18.0, breath_telegraph = 1.1, breath_active = 0.8, breath_cd = 4.5,
        breath_length = 16.0, breath_height = 2.8, breath_dps = 30.0, breath_freeze = 1.6,
        anim_fps = 6.0,
    },

    -- ---- HEROES: the two survivors the player drives ------------------------
    heroes = {
        -- FORGE WALKER — fire affinity. His ember MELTS the cold: freeze traps and
        -- the Warden's freeze hold him a fraction of the time (melt_mult < 1). He
        -- still SLIDES on ice (slips = true) — the heat doesn't fix his footing.
        forge_walker = {
            id = "forge_walker", name = "Forge Walker",
            sprite_r = TEX .. "forge_walker_r.png", sprite_l = TEX .. "forge_walker_l.png",
            color = C.fire, glow = C.fire_hot,
            size = 1.8, radius = 0.55,
            hp = 130.0, speed = 8.0, accel = 26.0,
            slips = true,                    -- ice carries him forward
            melt_mult = 0.45,                -- freezes last <half as long
            attack_damage = 30.0, attack_range = 1.9, attack_cd = 0.46,
            walk_bob = 0.16, walk_freq = 11.0,
            blurb = "Fire affinity. Slides on ice, but melts freezes fast.",
        },
        -- ICE BORN — born to the cold. IMMUNE TO SLIP (full footing on every
        -- surface), but heavy and SLOW. Freezes hold him the full duration.
        ice_born = {
            id = "ice_born", name = "Ice Born",
            sprite_r = TEX .. "ice_born_r.png", sprite_l = TEX .. "ice_born_l.png",
            color = C.bright, glow = C.frost,
            size = 1.9, radius = 0.58,
            hp = 165.0, speed = 5.4, accel = 30.0,
            slips = false,                   -- never slides — sure-footed on ice
            melt_mult = 1.0,                 -- freezes last the full duration
            attack_damage = 26.0, attack_range = 2.0, attack_cd = 0.52,
            walk_bob = 0.12, walk_freq = 9.0,
            blurb = "Immune to slip — sure-footed, but slow and heavy.",
        },
    },
    hero_order = { "forge_walker", "ice_born" },
}

-- ===========================================================================
-- 2. Shared-Duel fallback (menu launch). Minimal but valid: the SAME cast as
--    horde/creep.lua archetypes, so Frozen Depths is playable from the
--    battlefield menu too. mode.lua's signature hook turns Freeze Traps into
--    floor patches that FREEZE the hero in place (move_mult = 0) — the cold
--    analogue of THE PIT's erupting spikes.
-- ===========================================================================

Frozen.theme = {
    accent        = { 0.0, 0.55, 1.0, 0.95 },
    floor         = C.cave,
    floor_texture = TEX .. "floor_ice.png",      -- iced flagstone, wired live
    wall          = C.cave_lo,
    spawn_sigil   = C.bright,
    aura          = { 0.0, 0.55, 1.0, 0.45 },
    hero_body     = C.steel,
    hero_trim     = C.fire,
    hud_title     = "FROZEN DEPTHS",
    win_text      = "The Warden is shattered. You walk out of the cold.\nPress R to descend again  -  M for menu",
    lose_text     = "The deep keeps you. You freeze where you fell.\nPress R to descend again  -  M for menu",
}

-- The Duel hero rig (Forge Walker; part keys match ath_art's walk/attack clips).
Frozen.hero_actor = {
    name = "Frozen_Hero",
    parts = {
        body   = { kind = "cube",   position = { 0.0, 0.56, 0.0 },  scale = { 0.50, 0.78, 0.36 }, color = C.steel,  emissive = 0.50 },
        head   = { kind = "sphere", position = { 0.0, 1.10, 0.0 },  scale = { 0.36, 0.38, 0.38 }, color = C.steel,  emissive = 0.45 },
        hand_r = { kind = "sphere", position = { 0.34, 0.66, 0.05 },scale = { 0.16, 0.16, 0.16 }, color = C.fire,   emissive = 0.9 },
        hand_l = { kind = "sphere", position = { -0.34, 0.66, 0.05 },scale = { 0.16, 0.16, 0.16 }, color = C.fire,  emissive = 0.9 },
        foot_r = { kind = "cube",   position = { 0.14, 0.05, 0.0 }, scale = { 0.18, 0.10, 0.24 }, color = C.cave,   emissive = 0.25 },
        foot_l = { kind = "cube",   position = { -0.14, 0.05, 0.0 },scale = { 0.18, 0.10, 0.24 }, color = C.cave,   emissive = 0.25 },
        sword  = { kind = "cube",   position = { 0.38, 0.52, 0.10 },scale = { 0.08, 0.74, 0.10 }, color = C.bright, emissive = 0.70 },
        ember  = { kind = "sphere", position = { 0.0, 0.70, -0.10 },scale = { 0.16, 0.18, 0.08 }, color = C.fire_hot, emissive = 1.9 },
    },
}

-- A frost bolt the Frost Archer looses (drops under gravity, so it leads a runner).
local function frost_bolt(color)
    return {
        kind = "orb", speed = 15.0, cooldown = 1.6, start_y = 0.95, target_y = 0.55,
        particle_size = 0.20, scale = { 0.12, 0.12, 0.52 }, color = color or C.bright,
        emissive = 1.5, arc = 0.06, gravity = -6.0, impact = true,
        hit_radius = 0.7, flight_grace = 0.10,
    }
end

Frozen.archetypes = {
    -- ICE WIGHT — the chaff spine; cheap, fast, beelines at the hero.
    ice_wight = {
        name = "Ice Wight", threat_cost = 1, hp = 12, dps = 3.2, range = 0.6, speed = 2.7,
        color = C.bright, head = C.ice, body_scale = { 0.36, 0.52, 0.30 }, head_scale = { 0.26, 0.26, 0.26 },
        parts = 2, scale = 1.0, texture = TEX .. "ice_wight_f0.png",
        extras = {
            { name = "Wight_Claw_L", kind = "cube", position = { -0.28, 0.50, 0.16 }, scale = { 0.06, 0.30, 0.06 }, color = C.frost, emissive = 0.8 },
            { name = "Wight_Claw_R", kind = "cube", position = { 0.28, 0.50, 0.16 }, scale = { 0.06, 0.30, 0.06 }, color = C.frost, emissive = 0.8 },
            { name = "Wight_Eye", kind = "sphere", position = { 0.0, 0.62, 0.18 }, scale = { 0.18, 0.06, 0.04 }, color = C.bright, emissive = 1.8 },
        },
    },
    -- FROST ARCHER — the ranged anchor; arcs gravity-dropping frost bolts.
    frost_archer = {
        name = "Frost Archer", threat_cost = 3, hp = 16, dps = 2.6, range = 6.5, speed = 1.2,
        color = C.steel, head = C.bright, weapon = C.frost,
        body_scale = { 0.38, 0.62, 0.30 }, head_scale = { 0.26, 0.28, 0.26 },
        weapon_pos = { 0.36, 0.60, 0.06 }, weapon_scale = { 0.06, 0.66, 0.06 },
        parts = 3, scale = 1.05, hold_range = 6.5, anchor_hold = true, needs_los = true, los_reposition_seconds = 2.0,
        projectile = frost_bolt(C.bright),
        texture = TEX .. "frost_archer_f0.png",
        extras = {
            { name = "Archer_Bow", kind = "cube", position = { 0.44, 0.60, 0.10 }, scale = { 0.06, 0.50, 0.06 }, color = C.bright, emissive = 0.9 },
            { name = "Archer_Eye", kind = "sphere", position = { 0.0, 0.90, 0.12 }, scale = { 0.16, 0.05, 0.04 }, color = C.bright, emissive = 1.6 },
        },
    },
    -- ICE WALL as a stationary "creep" so role mapping is valid; it never roams
    -- (speed 0) and is excluded from auto_mix — the signature hook freezes the floor.
    ice_wall = {
        name = "Ice Wall", threat_cost = 2, hp = 40, dps = 4.0, range = 1.0, speed = 0.0,
        color = C.ice, head = C.bright, body_scale = { 0.5, 1.1, 0.4 }, head_scale = { 0.3, 0.3, 0.3 },
        parts = 2, scale = 1.3, texture = TEX .. "ice_wall.png",
        extras = {
            { name = "Wall_Shine", kind = "cube", position = { -0.10, 0.70, 0.18 }, scale = { 0.10, 0.80, 0.04 }, color = C.frost, emissive = 1.0 },
        },
    },
    -- GLACIAL WARDEN — the boss. A mountain of living ice that breaks any line.
    glacial_warden = {
        name = "The Glacial Warden", threat_cost = 7, hp = 110, dps = 12.0, range = 1.2, speed = 1.0,
        color = C.bright, head = C.ice, weapon = C.frost,
        body_scale = { 0.88, 0.92, 0.70 }, head_pos = { 0.0, 1.14, -0.04 }, head_scale = { 0.44, 0.42, 0.44 },
        weapon_pos = { 0.58, 0.52, 0.06 }, weapon_scale = { 0.26, 0.54, 0.26 },
        parts = 3, scale = 2.2, texture = TEX .. "glacial_warden_f0.png",
        extras = {
            { name = "Warden_Shoulder_L", kind = "sphere", position = { -0.50, 0.74, 0.0 }, scale = { 0.34, 0.34, 0.34 }, color = C.ice, emissive = 0.8 },
            { name = "Warden_Shoulder_R", kind = "sphere", position = { 0.50, 0.74, 0.0 }, scale = { 0.34, 0.34, 0.34 }, color = C.ice, emissive = 0.8 },
            { name = "Warden_Core", kind = "sphere", position = { 0.0, 0.78, 0.30 }, scale = { 0.30, 0.38, 0.12 }, color = C.bright, emissive = 2.0 },
            { name = "Warden_Eye_L", kind = "sphere", position = { -0.16, 1.18, 0.22 }, scale = { 0.12, 0.10, 0.05 }, color = C.frost, emissive = 2.0 },
            { name = "Warden_Eye_R", kind = "sphere", position = { 0.16, 1.18, 0.22 }, scale = { 0.12, 0.10, 0.05 }, color = C.frost, emissive = 2.0 },
            { name = "Warden_Crown", kind = "cube", position = { 0.0, 1.46, 0.0 }, scale = { 0.50, 0.30, 0.10 }, color = C.bright, emissive = 1.2 },
        },
    },
}

-- The four level-agnostic roles, mapped onto this cast so the shared deck works.
Frozen.roles = {
    swarm  = "ice_wight",
    ranged = "frost_archer",
    elite  = "ice_wall",
    brute  = "glacial_warden",
}

return Frozen
