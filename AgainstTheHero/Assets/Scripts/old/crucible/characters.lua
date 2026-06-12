-- THE CRUCIBLE — the cast (DATA only).
--
-- THE CRUCIBLE is a bespoke 2D top-down arena mode (placement -> real-time combat
-- over a sea of lava, rendered on the runtime_ui canvas — see mode.lua). It does
-- NOT run on the shared 3D Duel engine. So, like THE PIT and GRAVEWARDEN, this
-- file is split into two clearly-labelled halves:
--
--   1. Cru.crucible2d — the data the 2D game actually reads: the volcanic forge
--      chamber (stone PLATFORMS connected by narrow WALKWAYS over instant-death
--      LAVA), the horde the player places (Ember Shade / Cinder Archer / Lava
--      Warden), the Molten Colossus boss, the two playable heroes (Ashen Knight /
--      Void Touched), the HEAT and LAVA-SURGE tuning, the sprite paths, and the
--      molten Dark-Souls palette. THIS is the heart of the mode.
--
--   2. Cru.theme / hero_actor / archetypes / roles — a MINIMAL but valid shared-
--      Duel config so the mode still shows up and plays if launched from the menu
--      (which always drives index modes through ath_duel.lua). The same cast,
--      reshaped into horde/creep.lua archetypes; the LAVA SURGE becomes the Duel's
--      "lava upwelling" floor hazard there (a roaming creep can't be a sluice gate).
--
-- Every sprite below is produced by tools/gen_textures_crucible.py into
--   Assets/Textures/modes/crucible/   (referenced as "Textures/modes/crucible/
-- <file>.png"; the engine roots texture/image paths at Assets/). The art is
-- OPTIONAL: if the PNGs are absent, every entity still draws as its flat silhouette
-- colour, so the mode is fully playable before art exists.
--
-- Aesthetic: Dark Souls forge. Near-black scorched stone, dried-blood deeps, the
-- searing red-orange of molten rock, and the white-hot glow of the forge. Grim,
-- oppressive, lit only by the lava it floats upon.

local Cru = {}

-- ---------------------------------------------------------------------------
-- Palette — the brief's seven notes plus tints derived from them.
--   #0d0000 abyss · #1a0000 dark · #3d0000 deep · #ff2200 lava
--   · #ff6600 ember · #ffaa00 hot glow · #1a1a1a stone
-- ---------------------------------------------------------------------------
local C = {
    abyss     = { 0.051, 0.000, 0.000 },   -- #0d0000 — the dark beneath the chamber
    dark      = { 0.102, 0.000, 0.000 },   -- #1a0000 — scorched shadow
    deep      = { 0.239, 0.000, 0.000 },   -- #3d0000 — cooling crust
    lava      = { 1.000, 0.133, 0.000 },   -- #ff2200 — molten rock (instant death)
    ember     = { 1.000, 0.400, 0.000 },   -- #ff6600 — burning ash / fire foes
    glow      = { 1.000, 0.667, 0.000 },   -- #ffaa00 — white-hot forge glow
    stone     = { 0.102, 0.102, 0.102 },   -- #1a1a1a — cold forge stone
    stone_hi  = { 0.180, 0.176, 0.172 },
    stone_lo  = { 0.063, 0.060, 0.060 },
    iron      = { 0.270, 0.250, 0.250 },   -- gates / heavy armour
    ash       = { 0.380, 0.360, 0.350 },   -- pale ash / bone
}
Cru.palette = C

local TEX = "Textures/modes/crucible/"

-- ===========================================================================
-- 1. Cru.crucible2d — the data the 2D arena game reads.
-- ===========================================================================

Cru.crucible2d = {
    palette = C,

    -- Shared environment art (drawn on the canvas in mode.lua).
    sprites = {
        floor   = TEX .. "floor_tile.png",     -- 64x64 dark scorched stone (platforms/walkways)
        platform = TEX .. "platform.png",      -- a round stone platform disc (RGBA)
        glow    = TEX .. "heat_glow.png",       -- radial mask: boss slam / surge / heat-shimmer
        shimmer = TEX .. "heat_shimmer.png",    -- the heat-haze overlay at high HEAT
        gate    = TEX .. "sluice_gate.png",     -- the sluice gate at a walkway mouth
        bolt    = TEX .. "firebolt.png",        -- the Cinder Archer's projectile
        splat   = TEX .. "scorch.png",          -- scorch / cinder decal
        -- Lava field — a 4-frame bubbling cycle swapped on the lava clock.
        lava_frames  = { TEX .. "lava_f0.png", TEX .. "lava_f1.png", TEX .. "lava_f2.png", TEX .. "lava_f3.png" },
        -- Lava SURGE flow — a 4-frame advancing channel poured over a flooded walkway.
        surge_frames = { TEX .. "surge_f0.png", TEX .. "surge_f1.png", TEX .. "surge_f2.png", TEX .. "surge_f3.png" },
    },

    -- The forge chamber. Centred on the origin: x in [-half_w, half_w], y in
    -- [-half_h, half_h] (world units). The WHOLE chamber fits in frame (a fixed
    -- top-down camera, like THE PIT) so the player can read every walkway and plan
    -- a reroute when the lava surges. Everything OFF the platforms/walkways is lava.
    arena = {
        half_w = 21.0, half_h = 18.0,

        -- Stone PLATFORMS (discs over the lava). Index 1 is the central forge heart
        -- where the Molten Colossus sleeps; the hero drops in on the south platform.
        platforms = {
            { x =   0.0, y =   0.0, r = 5.4 },   -- 1 CENTRE — the forge heart / boss arena
            { x =   0.0, y =  13.0, r = 4.2 },   -- 2 SOUTH  — the hero's landing
            { x =   0.0, y = -13.0, r = 4.0 },   -- 3 NORTH
            { x = -15.0, y =   0.0, r = 4.0 },   -- 4 WEST
            { x =  15.0, y =   0.0, r = 4.0 },   -- 5 EAST
        },
        spawn_platform = 2,
        boss_platform  = 1,

        -- Narrow WALKWAYS bridging the platforms (capsules). A hub of four spokes to
        -- the centre, plus a ring of four — so when the horde floods ONE walkway with
        -- a surge there is always an alternate route. `a` is the gate (sluice) end.
        walkways = {
            { a = 2, b = 1, half = 1.5 },   -- south -> centre
            { a = 3, b = 1, half = 1.5 },   -- north -> centre
            { a = 4, b = 1, half = 1.5 },   -- west  -> centre
            { a = 5, b = 1, half = 1.5 },   -- east  -> centre
            { a = 2, b = 5, half = 1.3 },   -- south -> east  (ring)
            { a = 5, b = 3, half = 1.3 },   -- east  -> north (ring)
            { a = 3, b = 4, half = 1.3 },   -- north -> west  (ring)
            { a = 4, b = 2, half = 1.3 },   -- west  -> south (ring)
        },
    },

    -- Placement: set up to `budget` horde, any mix of the three, on the stone.
    placement = { budget = 6 },

    -- ---- HEAT — the hero's rising-temperature meter (0..100%) ----------------
    -- HEAT climbs while the hero is exposed to lava (out on a narrow walkway, at a
    -- platform's lip, near a fire foe or an active surge) and falls in the SHADE at
    -- a platform's cool centre. At 100% the hero takes constant burn damage. The
    -- Ashen Knight's `heat_resist` scales how fast he soaks it up.
    heat = {
        shade_clear = 2.4,     -- lava-clearance (units from the nearest lava) that counts as shade
        hot_clear   = 2.0,     -- below this clearance, HEAT rises (walkways/lips are always hot)
        rise_rate   = 15.0,    -- %/s at the lava's edge
        cool_rate   = 24.0,    -- %/s in the deep shade
        fire_rate   = 26.0,    -- extra %/s when close to a fire foe / lava trail / surge
        fire_radius = 3.4,     -- how near a fire source must be to add heat
        burn_dps    = 16.0,    -- damage/s once HEAT hits 100%
    },

    -- ---- LAVA SURGE — the signature. The horde banks AP, then spends it to open --
    -- a sluice gate: lava ADVANCES along one walkway (outrun it or be caught), holds
    -- for `hold` seconds (the walkway is instant death), then recedes. One at a time.
    surge = {
        ap_rate   = 11.0,      -- AP the horde banks per second
        ap_cost   = 100.0,     -- AP spent to open a gate
        telegraph = 2.0,       -- the gate rumbles + glows this long before lava pours
        flood_in  = 1.2,       -- lava advances from the gate to the far platform
        hold      = 8.0,       -- the walkway stays drowned this long
        flood_out = 1.4,       -- then the lava recedes back toward the gate
    },

    -- ---- THE MOLTEN COLOSSUS — the boss -------------------------------------
    -- A lava-dripping giant that sleeps on the forge heart. It WAKES when the hero
    -- nears the centre (or after `wake_time`), then WALKS ON LAVA — it ignores the
    -- walkways entirely, wading straight at the hero — and periodically TELEGRAPHS
    -- and ERUPTS a slam: a growing ring of fire at the hero's feet. Slay it to win.
    boss = {
        id = "molten_colossus", name = "The Molten Colossus", kind = "boss",
        frames = 8, fps = 6.0, sprite_base = TEX .. "colossus_f",
        color = C.ember, eye = C.glow,
        size = 6.0, radius = 2.0,             -- the 128x128 sprite, drawn large
        hp = 1100.0, speed = 1.9,
        touch_damage = 30.0, touch_cd = 0.9,
        wake_dist = 8.0, wake_time = 20.0,    -- wakes on proximity OR this long survived
        rise_time = 2.0,                      -- the heave-up-from-the-forge animation
        -- ERUPTION SLAM: a telegraphed AoE that erupts where the hero stands.
        slam = { range = 5.0, telegraph = 1.3, active = 0.4, damage = 54.0, cd = 4.5, heat = 30.0 },
        sway_amp = 0.05, sway_freq = 1.5,
    },

    -- ---- HORDE: the three you place before the hero drops in -----------------
    horde = {
        -- EMBER SHADE — fast fire melee. Beelines at the hero, spreads from its kin
        -- (separation), and its burning touch dumps HEAT as well as damage.
        ember_shade = {
            id = "ember_shade", name = "Ember Shade", kind = "shade",
            frames = 6, fps = 7.0, sprite_base = TEX .. "shade_f",
            color = C.ember, glow = C.glow, fire = true,
            size = 1.6, radius = 0.55,
            hp = 56.0, speed = 4.9,
            touch_damage = 13.0, touch_cd = 0.7, touch_heat = 22.0,
            sep_radius = 1.5, sep_weight = 1.5,
            sway_amp = 0.10, sway_freq = 5.0,
            blurb = "Fast fire melee. Its touch sears — and stokes your HEAT.",
        },
        -- CINDER ARCHER — ranged. Holds a band and lobs a firebolt on a leading arc;
        -- the bolt's blast scorches and adds heat where it lands.
        cinder_archer = {
            id = "cinder_archer", name = "Cinder Archer", kind = "archer",
            frames = 5, fps = 5.5, sprite_base = TEX .. "archer_f",
            color = C.glow, glow = C.lava, fire = true,
            size = 1.6, radius = 0.55,
            hp = 34.0, speed = 2.2,
            prefer_range = 9.0, retreat_range = 5.5, hold_range = 12.0,
            throw_cd = 2.0,
            projectile = { speed = 12.0, arc_peak = 2.8, lead = 0.5, damage = 16.0, blast = 1.4, size = 0.85, heat = 18.0 },
            sep_radius = 1.4, sep_weight = 1.0,
            sway_amp = 0.05, sway_freq = 3.0,
            blurb = "Ranged. Lobs firebolts on a leading arc; the blast burns.",
        },
        -- LAVA WARDEN — the heavy. Slow, tanky, and it WEEPS a trail of molten slag
        -- as it walks: hot patches that linger, burning and stoking HEAT on contact.
        lava_warden = {
            id = "lava_warden", name = "Lava Warden", kind = "warden",
            frames = 5, fps = 4.0, sprite_base = TEX .. "warden_f",
            color = C.lava, glow = C.glow, fire = true,
            size = 2.2, radius = 0.85,
            hp = 150.0, speed = 1.9,
            touch_damage = 22.0, touch_cd = 0.9,
            sep_radius = 1.8, sep_weight = 1.0,
            trail = { cd = 0.45, life = 4.0, radius = 1.2, dps = 14.0, heat = 22.0 },
            sway_amp = 0.04, sway_freq = 2.0,
            blurb = "Heavy. Leaves a burning slag trail that lingers behind it.",
        },
    },
    horde_order = { "ember_shade", "cinder_archer", "lava_warden" },

    -- ---- HEROES: the two you can drive into the chamber ----------------------
    heroes = {
        -- ASHEN KNIGHT — the tank, sworn to the forge. HEAT RESISTANCE: he soaks
        -- molten air far slower than flesh should. Slow, heavy, a wide cleave.
        ashen_knight = {
            id = "ashen_knight", name = "Ashen Knight",
            sprite_base = TEX .. "hero_ashen_d",       -- + "<dir>.png", dir 0..7
            color = C.iron, glow = C.ember,
            size = 1.8, radius = 0.62,
            hp = 185.0, speed = 4.6,
            attack_damage = 48.0, attack_range = 2.1, attack_cd = 0.60,
            heat_resist = 0.45,                          -- gains HEAT at 45% the rate
            walk_bob = 0.12, walk_freq = 9.0,
            blurb = "Tank. HEAT RESISTANCE — soaks the forge slowly. A heavy cleave.",
        },
        -- VOID TOUCHED — the fragile blinker. No heat resistance, but a BLINK [Shift]
        -- teleports him a short hop in his heading — the only clean way out of a
        -- walkway the lava has already drowned. (Blink into lava still kills.)
        void_touched = {
            id = "void_touched", name = "Void Touched",
            sprite_base = TEX .. "hero_void_d",
            color = C.deep, glow = C.lava,
            size = 1.6, radius = 0.52,
            hp = 100.0, speed = 5.6,
            attack_damage = 26.0, attack_range = 1.7, attack_cd = 0.36,
            heat_resist = 1.0,
            blink = { dist = 6.2, cd = 2.0 },            -- [Shift] hop along the heading
            walk_bob = 0.16, walk_freq = 12.0,
            blurb = "Fragile, fast. [Shift] BLINK escapes a surging walkway.",
        },
    },
    hero_order = { "ashen_knight", "void_touched" },
}

-- ===========================================================================
-- 2. Shared-Duel fallback (menu launch). Minimal but valid: the SAME cast as
--    horde/creep.lua archetypes, so The Crucible is playable from the battlefield
--    menu too. mode.lua's signature hook turns the LAVA SURGE into "lava
--    upwellings" — molten discs that tear open, telegraph, then erupt under the
--    hero (a roaming creep can't be a sluice gate in the Duel).
-- ===========================================================================

Cru.theme = {
    accent        = { 1.0, 0.133, 0.0, 0.95 },
    floor         = C.stone,
    floor_texture = TEX .. "floor_tile.png",
    wall          = C.stone_lo,
    spawn_sigil   = C.lava,
    aura          = { 1.0, 0.40, 0.0, 0.45 },
    hero_body     = C.iron,
    hero_trim     = C.ember,
    hud_title     = "THE CRUCIBLE",
    win_text      = "The Molten Colossus cools to slag. The forge is yours.\nPress R to run it back  -  M for menu",
    lose_text     = "The crucible takes another. You are rendered to ash.\nPress R to run it back  -  M for menu",
}

-- The Duel hero rig (primitive actor; part keys match ath_art's walk/attack clips).
Cru.hero_actor = {
    name = "Crucible_Hero",
    parts = {
        body   = { kind = "cube",   position = { 0.0, 0.56, 0.0 },  scale = { 0.50, 0.78, 0.36 }, color = C.iron,  emissive = 0.45 },
        head   = { kind = "sphere", position = { 0.0, 1.12, 0.0 },  scale = { 0.38, 0.40, 0.40 }, color = C.stone_hi, emissive = 0.40 },
        hand_r = { kind = "sphere", position = { 0.34, 0.66, 0.05 }, scale = { 0.16, 0.16, 0.16 }, color = C.iron,  emissive = 0.40 },
        hand_l = { kind = "sphere", position = { -0.34, 0.66, 0.05 },scale = { 0.16, 0.16, 0.16 }, color = C.iron,  emissive = 0.40 },
        foot_r = { kind = "cube",   position = { 0.14, 0.05, 0.0 }, scale = { 0.18, 0.10, 0.24 }, color = C.stone_lo, emissive = 0.25 },
        foot_l = { kind = "cube",   position = { -0.14, 0.05, 0.0 },scale = { 0.18, 0.10, 0.24 }, color = C.stone_lo, emissive = 0.25 },
        sword  = { kind = "cube",   position = { 0.38, 0.52, 0.10 },scale = { 0.08, 0.78, 0.10 }, color = C.ember, emissive = 1.3 },
        forge  = { kind = "sphere", position = { 0.0, 0.66, -0.10 },scale = { 0.16, 0.18, 0.06 }, color = C.glow,  emissive = 1.8 },
    },
}

local function firebolt(color)
    return {
        kind = "orb", speed = 13.0, cooldown = 1.2, start_y = 0.85, target_y = 0.85,
        particle_size = 0.28, scale = { 0.24, 0.24, 0.44 }, color = color or C.ember,
        emissive = 1.7, arc = 0.16, pulse = true, impact = false, gravity = -2.0,
        hit_radius = 0.7, flight_grace = 0.10,
    }
end

Cru.archetypes = {
    -- EMBER SHADE — the swarm, and the cheap wall the hero's cleave burns through.
    ember_shade = {
        name = "Ember Shade", threat_cost = 1, hp = 12, dps = 3.4, range = 0.6, speed = 2.7,
        color = C.ember, head = C.glow, body_scale = { 0.36, 0.50, 0.30 }, head_scale = { 0.24, 0.26, 0.24 },
        parts = 2, scale = 1.0, texture = TEX .. "shade_f0.png",
        extras = {
            { name = "Shade_Core", kind = "sphere", position = { 0.0, 0.52, 0.10 }, scale = { 0.18, 0.20, 0.10 }, color = C.glow, emissive = 1.9 },
        },
    },
    -- CINDER ARCHER — the ranged anchor that lobs firebolts.
    cinder_archer = {
        name = "Cinder Archer", threat_cost = 3, hp = 16, dps = 2.6, range = 6.0, speed = 1.5,
        color = C.glow, head = C.ember, weapon = C.lava,
        body_scale = { 0.38, 0.64, 0.30 }, head_scale = { 0.26, 0.28, 0.26 },
        weapon_pos = { 0.34, 0.60, 0.08 }, weapon_scale = { 0.06, 0.80, 0.06 },
        parts = 3, scale = 1.1, hold_range = 6.0, anchor_hold = true, needs_los = true, los_reposition_seconds = 2.0,
        projectile = firebolt(C.ember),
        texture = TEX .. "archer_f0.png",
        extras = {
            { name = "Archer_Brand", kind = "cube", position = { -0.26, 0.58, -0.06 }, scale = { 0.10, 0.34, 0.10 }, color = C.lava, emissive = 1.4 },
        },
    },
    -- LAVA WARDEN — the heavy, molten elite; a slow, hard-hitting wall.
    lava_warden = {
        name = "Lava Warden", threat_cost = 4, hp = 38, dps = 7.5, range = 0.95, speed = 1.9,
        color = C.lava, head = C.glow, weapon = C.ember,
        body_scale = { 0.58, 0.60, 0.44 }, head_pos = { 0.0, 0.86, -0.04 }, head_scale = { 0.30, 0.28, 0.30 },
        weapon_pos = { 0.42, 0.42, 0.04 }, weapon_scale = { 0.16, 0.46, 0.16 },
        parts = 3, scale = 1.4, texture = TEX .. "warden_f0.png",
        extras = {
            { name = "Warden_Vent", kind = "cylinder", position = { 0.0, 1.10, 0.0 }, scale = { 0.30, 0.06, 0.30 }, color = C.glow, emissive = 1.9 },
            { name = "Warden_Core", kind = "sphere", position = { 0.0, 0.60, -0.18 }, scale = { 0.26, 0.30, 0.10 }, color = C.lava, emissive = 2.0 },
        },
    },
    -- THE MOLTEN COLOSSUS — the boss; a slow, devastating giant that arrives late.
    molten_colossus = {
        name = "The Molten Colossus", threat_cost = 6, hp = 90, dps = 9.5, range = 1.2, speed = 1.3,
        color = C.ember, head = C.glow, weapon = C.lava,
        body_scale = { 0.82, 0.86, 0.64 }, head_pos = { 0.0, 1.14, -0.04 }, head_scale = { 0.42, 0.38, 0.42 },
        weapon_pos = { 0.54, 0.56, 0.06 }, weapon_scale = { 0.16, 0.96, 0.16 },
        parts = 3, scale = 2.1, texture = TEX .. "colossus_f0.png",
        extras = {
            { name = "Colossus_Crown", kind = "cylinder", position = { 0.0, 1.46, 0.0 }, scale = { 0.50, 0.12, 0.50 }, color = C.lava, emissive = 1.8 },
            { name = "Colossus_Eye_L", kind = "sphere", position = { -0.13, 1.16, 0.22 }, scale = { 0.10, 0.10, 0.05 }, color = C.glow, emissive = 2.3 },
            { name = "Colossus_Eye_R", kind = "sphere", position = { 0.13, 1.16, 0.22 }, scale = { 0.10, 0.10, 0.05 }, color = C.glow, emissive = 2.3 },
            { name = "Colossus_Maul", kind = "cube", position = { 0.54, 1.08, 0.06 }, scale = { 0.34, 0.12, 0.10 }, color = C.lava, emissive = 1.5 },
        },
    },
}

Cru.roles = {
    swarm  = "ember_shade",
    ranged = "cinder_archer",
    elite  = "lava_warden",
    brute  = "molten_colossus",
}

return Cru
