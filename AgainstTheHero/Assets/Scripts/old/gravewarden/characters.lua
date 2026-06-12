-- Gravewarden — the cast (DATA only).
--
-- GRAVEWARDEN is a bespoke 2D top-down arena mode (placement -> real-time combat
-- under a fog of war, rendered on the runtime_ui canvas — see mode.lua). It does
-- NOT run on the 3D Duel engine. So, like THE PIT, this file is split into two
-- clearly-labelled halves:
--
--   1. Grave.grave2d — the data the 2D game actually reads: the rectangular
--      graveyard, the TOMBSTONE SPAWNERS the player places (Grave / Archer Cairn /
--      Wraith Crypt), the undead those graves RISE in waves, the Gravewarden boss,
--      the two playable heroes (Exorcist / Gravedigger), sprite paths, the wave
--      tuning, and the grim Dark-Souls palette. THIS is the heart of the mode.
--
--   2. Grave.theme / hero_actor / archetypes / roles — a MINIMAL but valid shared-
--      Duel config so the mode still shows up and plays if launched from the menu
--      (which always drives index modes through ath_duel.lua). The same cast,
--      reshaped into horde/creep.lua archetypes; the RISE mechanic becomes the
--      Duel's "risen graves" floor hazard there (a roaming creep can't be a grave).
--
-- Every sprite below is produced by tools/gen_textures_gravewarden.py into
--   Assets/Textures/modes/gravewarden/   (referenced as "Textures/modes/
-- gravewarden/<file>.png"; the engine roots texture/image paths at Assets/). The
-- art is OPTIONAL: if the PNGs are absent, every entity still draws as its flat
-- silhouette colour, so the game is fully playable before art exists.
--
-- Aesthetic: Dark Souls necropolis. Near-black rotting grass, cold tombstone
-- stone, bone-white dead, blood-red eyes, and the one otherworldly note — the
-- spectral blue of a wraith. Grim, foggy, oppressive.

local Grave = {}

-- ---------------------------------------------------------------------------
-- Palette — the brief's six notes plus tints derived from them.
--   #0a0f0a void · #1a2e1a grass · #3d3d2e stone · #c8c8a0 bone
--   · #cc0000 blood-red · #7777ff spectral
-- ---------------------------------------------------------------------------
local C = {
    void      = { 0.039, 0.059, 0.039 },   -- #0a0f0a — the fog-swallowed dark
    grass     = { 0.102, 0.180, 0.102 },   -- #1a2e1a — dead graveyard grass
    grass_lo  = { 0.063, 0.110, 0.063 },
    stone     = { 0.239, 0.239, 0.180 },   -- #3d3d2e — tombstone granite
    stone_lo  = { 0.150, 0.150, 0.115 },
    bone      = { 0.784, 0.784, 0.627 },   -- #c8c8a0 — bone white
    bone_lo   = { 0.560, 0.560, 0.450 },
    rot       = { 0.300, 0.380, 0.220 },   -- sickly undead flesh
    blood     = { 0.800, 0.000, 0.000 },   -- #cc0000 — dead eyes / gore
    blood_hot = { 0.920, 0.180, 0.120 },
    spectral  = { 0.467, 0.467, 1.000 },   -- #7777ff — wraith-light
    spectral_hot = { 0.640, 0.640, 1.000 },
}
Grave.palette = C

local TEX = "Textures/modes/gravewarden/"

-- ===========================================================================
-- 1. Grave.grave2d — the data the 2D arena game reads.
-- ===========================================================================

Grave.grave2d = {
    palette = C,

    -- Shared environment art (drawn on the canvas in mode.lua).
    sprites = {
        grass      = TEX .. "grass_tile.png",   -- 64x64 dark grass, tiled
        fog        = TEX .. "fog.png",           -- 64x64 RGBA drifting fog puff
        mausoleum  = TEX .. "mausoleum.png",     -- the boss crypt at the north end
        grave_glow = TEX .. "grave_glow.png",    -- the warning aura before a RISE
        arrow      = TEX .. "bone_arrow.png",    -- the Grave Archer's projectile
        splat      = TEX .. "splat.png",         -- blood/bone-dust decal
        -- The three tombstone variants the player plants (index by grave type).
        tomb       = { TEX .. "tomb_0.png", TEX .. "tomb_1.png", TEX .. "tomb_2.png" },
    },

    -- The rectangular graveyard. Centred on the origin: x in [-half_w, half_w],
    -- y in [-half_h, half_h] (world units). The camera FOLLOWS the hero across it,
    -- so only the fog-lit patch around him is ever readable.
    arena = {
        half_w      = 22.0, half_h = 20.0,        -- playable half-extents
        hero_spawn  = { x = 0.0, y = 16.0 },      -- the hero starts at the south gate
        mausoleum   = { x = 0.0, y = -16.0 },     -- the Gravewarden's crypt (north)
        -- Fog of war: full sight inside `sight_inner`, fading to black at
        -- `sight_outer`. The Exorcist's Consecrate briefly pushes both outward.
        sight_inner = 7.5, sight_outer = 13.0,
    },

    -- Placement: plant up to `budget` tombstone spawners, any mix of the three.
    placement = { budget = 6 },

    -- ---- WAVE TUNING ---------------------------------------------------------
    -- Combat runs in three waves. A wave advances once enough undead have risen
    -- (`quota`) OR enough time has passed (`time_limit`, so a sparse graveyard
    -- still escalates). Wave 1: only Graves rise (Risen). Wave 2: Archer Cairns
    -- and Wraith Crypts wake too. Wave 3: the mausoleum tears open — the
    -- GRAVEWARDEN rises. Slay it to win.
    waves = {
        rise_telegraph = 1.5,            -- a grave glows this long before it births
        rise_time      = 0.7,            -- the undead's emerge-from-earth animation
        quota          = { 7, 16 },      -- summoned-count to reach wave 2, then wave 3
        time_limit     = { 22.0, 26.0 }, -- ...or this much time in the wave
        boss_telegraph = 2.6,            -- the mausoleum shudders this long, then opens
    },

    -- ---- GRAVES: the three spawners you plant before the dead walk -----------
    -- `wave_active` is the wave at which the grave starts rising undead; `rise_cd`
    -- is its cadence between births. `spawns` keys into `undead` below.
    graves = {
        risen_grave = {
            id = "risen_grave", name = "Grave", tomb = 1, spawns = "risen",
            color = C.stone, glow = C.blood, size = 1.9,
            rise_cd = 3.6, wave_active = 1,
            blurb = "Births shambling Risen from wave 1.",
        },
        archer_cairn = {
            id = "archer_cairn", name = "Archer Cairn", tomb = 2, spawns = "grave_archer",
            color = C.stone_lo, glow = C.bone, size = 2.0,
            rise_cd = 6.0, wave_active = 2,
            blurb = "Raises a Grave Archer (wakes at wave 2).",
        },
        wraith_crypt = {
            id = "wraith_crypt", name = "Wraith Crypt", tomb = 3, spawns = "bonewraith",
            color = C.stone, glow = C.spectral, size = 2.1,
            rise_cd = 8.0, wave_active = 2,
            blurb = "Looses a Bonewraith (wakes at wave 2).",
        },
    },
    grave_order = { "risen_grave", "archer_cairn", "wraith_crypt" },

    -- ---- UNDEAD: what the graves RISE (spawned, never placed) ----------------
    undead = {
        -- RISEN — the basic shambler. Slow, but it pours out in numbers and
        -- spreads (separation) so a horde surrounds rather than queues.
        risen = {
            id = "risen", name = "Risen", kind = "shambler",
            frames = 6, fps = 6.5, sprite_base = TEX .. "risen_f",
            color = C.rot, eye = C.blood,
            size = 1.7, radius = 0.55,
            hp = 40.0, speed = 2.6,
            touch_damage = 12.0, touch_cd = 0.8,
            sep_radius = 1.5, sep_weight = 1.4,
            sway_amp = 0.08, sway_freq = 4.0,
        },
        -- GRAVE ARCHER — ranged undead. Holds a preferred distance and lobs a
        -- bone arrow on a leading arc; backs off if the hero closes.
        grave_archer = {
            id = "grave_archer", name = "Grave Archer", kind = "archer",
            frames = 5, fps = 5.5, sprite_base = TEX .. "archer_f",
            color = C.bone_lo, eye = C.blood,
            size = 1.7, radius = 0.55,
            hp = 28.0, speed = 2.0,
            prefer_range = 9.0, retreat_range = 5.5, hold_range = 12.0,
            throw_cd = 2.0,
            projectile = { speed = 12.0, arc_peak = 2.6, lead = 0.5, damage = 16.0, blast = 1.2, size = 0.75 },
            sep_radius = 1.4, sep_weight = 1.0,
            sway_amp = 0.05, sway_freq = 3.0,
        },
        -- BONEWRAITH — elite spectral. Fast, semi-transparent, PHASES through its
        -- kin (no separation), and hits hard. Faintly lit even in the fog.
        bonewraith = {
            id = "bonewraith", name = "Bonewraith", kind = "wraith",
            frames = 4, fps = 8.0, sprite_base = TEX .. "wraith_f",
            color = C.spectral, eye = C.spectral_hot,
            size = 1.9, radius = 0.60,
            hp = 90.0, speed = 3.7,
            touch_damage = 22.0, touch_cd = 0.7,
            sep_radius = 0.0, sep_weight = 0.0,   -- phases freely
            spectral = true, min_alpha = 0.30,
            sway_amp = 0.14, sway_freq = 5.0,
        },
    },

    -- ---- BOSS: the Gravewarden -----------------------------------------------
    -- A massive skeleton with a scythe, risen from the mausoleum at wave 3. Slow
    -- but relentless; periodically TELEGRAPHS and SWEEPS its scythe in a wide ring.
    -- Always faintly visible through the fog — a looming dread. Kill it to win.
    boss = {
        id = "gravewarden", name = "The Gravewarden", kind = "boss",
        frames = 8, fps = 6.0, sprite_base = TEX .. "warden_f",
        color = C.bone, eye = C.spectral_hot,
        size = 5.4, radius = 1.7,             -- the 128x128 sprite, drawn large
        hp = 900.0, speed = 1.5,
        touch_damage = 30.0, touch_cd = 0.9,
        min_alpha = 0.55,
        sweep = { range = 4.8, telegraph = 1.1, active = 0.35, damage = 58.0, cd = 4.5 },
        sway_amp = 0.05, sway_freq = 1.6,
    },

    -- ---- HEROES: the two you can drive into the graveyard --------------------
    heroes = {
        -- EXORCIST — holy caster. A wide CONSECRATE burst burns the dead and, for
        -- a heartbeat, flares the fog back so you can see what's coming.
        exorcist = {
            id = "exorcist", name = "Exorcist",
            sprite_base = TEX .. "hero_exorcist_d",   -- + "<dir>.png", dir 0..7
            color = C.bone, glow = C.spectral_hot,
            size = 1.7, radius = 0.55,
            hp = 110.0, speed = 5.2,
            attack_damage = 30.0, attack_range = 2.6, attack_cd = 0.55,
            holy = true,                              -- attack flares the fog + smites spectral
            walk_bob = 0.14, walk_freq = 11.0,
            blurb = "Holy caster. Consecrate scours the dead and flares the dark.",
        },
        -- GRAVEDIGGER — the tank. Slow, leathery, with a brutal shovel cleave that
        -- unearths anything standing too close.
        gravedigger = {
            id = "gravedigger", name = "Gravedigger",
            sprite_base = TEX .. "hero_gravedigger_d",
            color = C.stone, glow = C.blood_hot,
            size = 1.8, radius = 0.62,
            hp = 170.0, speed = 4.4,
            attack_damage = 50.0, attack_range = 2.0, attack_cd = 0.64,
            walk_bob = 0.12, walk_freq = 9.0,
            blurb = "Tanky. A heavy shovel cleave unearths the nearby dead.",
        },
    },
    hero_order = { "exorcist", "gravedigger" },
}

-- ===========================================================================
-- 2. Shared-Duel fallback (menu launch). Minimal but valid: the SAME cast as
--    horde/creep.lua archetypes, so Gravewarden is playable from the battlefield
--    menu too. mode.lua's signature hook turns the RISE into "risen graves" —
--    stone markers that erupt a bone-burst at the hero (the static graves can't
--    be roaming creeps in the Duel).
-- ===========================================================================

Grave.theme = {
    accent        = { 0.467, 0.467, 1.0, 0.95 },
    floor         = C.grass_lo,
    floor_texture = TEX .. "grass_tile.png",
    wall          = C.stone_lo,
    spawn_sigil   = C.spectral,
    aura          = { 0.467, 0.467, 1.0, 0.45 },
    hero_body     = C.bone_lo,
    hero_trim     = C.spectral,
    hud_title     = "GRAVEWARDEN",
    win_text      = "The Gravewarden crumbles back into the cold earth.\nPress R to run it back  -  M for menu",
    lose_text     = "The graveyard claims another. You go to your rest.\nPress R to run it back  -  M for menu",
}

-- The Duel hero rig (primitive actor; part keys match ath_art's walk/attack clips).
Grave.hero_actor = {
    name = "Gravewarden_Hero",
    parts = {
        body   = { kind = "cube",   position = { 0.0, 0.56, 0.0 },  scale = { 0.48, 0.76, 0.34 }, color = C.bone_lo, emissive = 0.45 },
        head   = { kind = "sphere", position = { 0.0, 1.10, 0.0 },  scale = { 0.38, 0.40, 0.40 }, color = C.bone,    emissive = 0.40 },
        hand_r = { kind = "sphere", position = { 0.34, 0.66, 0.05 }, scale = { 0.16, 0.16, 0.16 }, color = C.bone_lo, emissive = 0.40 },
        hand_l = { kind = "sphere", position = { -0.34, 0.66, 0.05 },scale = { 0.16, 0.16, 0.16 }, color = C.bone_lo, emissive = 0.40 },
        foot_r = { kind = "cube",   position = { 0.14, 0.05, 0.0 }, scale = { 0.18, 0.10, 0.24 }, color = C.stone_lo, emissive = 0.25 },
        foot_l = { kind = "cube",   position = { -0.14, 0.05, 0.0 },scale = { 0.18, 0.10, 0.24 }, color = C.stone_lo, emissive = 0.25 },
        sword  = { kind = "cube",   position = { 0.38, 0.52, 0.10 },scale = { 0.08, 0.74, 0.10 }, color = C.spectral, emissive = 1.2 },
        ward   = { kind = "sphere", position = { 0.0, 0.66, -0.10 },scale = { 0.16, 0.18, 0.06 }, color = C.spectral_hot, emissive = 1.7 },
    },
}

local function bone_arc(color)
    return {
        kind = "orb", speed = 13.0, cooldown = 1.2, start_y = 0.85, target_y = 0.85,
        particle_size = 0.26, scale = { 0.20, 0.20, 0.42 }, color = color or C.bone,
        emissive = 1.4, arc = 0.16, pulse = true, impact = false, gravity = -2.0,
        hit_radius = 0.7, flight_grace = 0.10,
    }
end

Grave.archetypes = {
    -- RISEN — the swarm, and the cheap wall the hero's cleave chews through.
    risen = {
        name = "Risen", threat_cost = 1, hp = 12, dps = 3.2, range = 0.6, speed = 2.6,
        color = C.rot, head = C.bone_lo, body_scale = { 0.36, 0.50, 0.30 }, head_scale = { 0.24, 0.26, 0.24 },
        parts = 2, scale = 1.0, texture = TEX .. "risen_f0.png",
        extras = {
            { name = "Risen_Eye_L", kind = "sphere", position = { -0.08, 0.78, 0.18 }, scale = { 0.06, 0.06, 0.04 }, color = C.blood, emissive = 1.6 },
            { name = "Risen_Eye_R", kind = "sphere", position = { 0.08, 0.78, 0.18 }, scale = { 0.06, 0.06, 0.04 }, color = C.blood, emissive = 1.6 },
        },
    },
    -- GRAVE ARCHER — the ranged anchor that lobs bone arrows.
    grave_archer = {
        name = "Grave Archer", threat_cost = 3, hp = 16, dps = 2.6, range = 6.0, speed = 1.4,
        color = C.bone_lo, head = C.bone, weapon = C.bone,
        body_scale = { 0.38, 0.64, 0.30 }, head_scale = { 0.26, 0.28, 0.26 },
        weapon_pos = { 0.34, 0.60, 0.08 }, weapon_scale = { 0.06, 0.80, 0.06 },
        parts = 3, scale = 1.1, hold_range = 6.0, anchor_hold = true, needs_los = true, los_reposition_seconds = 2.0,
        projectile = bone_arc(C.bone),
        texture = TEX .. "archer_f0.png",
        extras = {
            { name = "Archer_Quiver", kind = "cube", position = { -0.26, 0.58, -0.06 }, scale = { 0.10, 0.34, 0.10 }, color = C.bone, emissive = 0.7 },
        },
    },
    -- BONEWRAITH — the spectral elite; a fast, hard-hitting wall.
    bonewraith = {
        name = "Bonewraith", threat_cost = 4, hp = 36, dps = 7.5, range = 0.95, speed = 2.6,
        color = C.spectral, head = C.spectral_hot, weapon = C.spectral,
        body_scale = { 0.56, 0.58, 0.42 }, head_pos = { 0.0, 0.84, -0.04 }, head_scale = { 0.30, 0.28, 0.30 },
        weapon_pos = { 0.40, 0.40, 0.04 }, weapon_scale = { 0.14, 0.42, 0.14 },
        parts = 3, scale = 1.35, texture = TEX .. "wraith_f0.png",
        extras = {
            { name = "Wraith_Halo", kind = "cylinder", position = { 0.0, 1.20, 0.0 }, scale = { 0.34, 0.06, 0.34 }, color = C.spectral_hot, emissive = 1.8 },
            { name = "Wraith_Core", kind = "sphere", position = { 0.0, 0.62, -0.20 }, scale = { 0.26, 0.30, 0.10 }, color = C.spectral_hot, emissive = 2.0 },
        },
    },
    -- THE GRAVEWARDEN — the boss; a slow, devastating colossus that arrives late.
    gravewarden = {
        name = "The Gravewarden", threat_cost = 6, hp = 80, dps = 9.5, range = 1.1, speed = 1.2,
        color = C.bone, head = C.bone_lo, weapon = C.stone,
        body_scale = { 0.78, 0.82, 0.60 }, head_pos = { 0.0, 1.10, -0.04 }, head_scale = { 0.40, 0.36, 0.40 },
        weapon_pos = { 0.52, 0.54, 0.06 }, weapon_scale = { 0.14, 0.92, 0.14 },
        parts = 3, scale = 2.0, texture = TEX .. "warden_f0.png",
        extras = {
            { name = "Warden_Crown", kind = "cylinder", position = { 0.0, 1.40, 0.0 }, scale = { 0.48, 0.12, 0.48 }, color = C.spectral, emissive = 1.6 },
            { name = "Warden_Eye_L", kind = "sphere", position = { -0.12, 1.12, 0.22 }, scale = { 0.09, 0.09, 0.05 }, color = C.spectral_hot, emissive = 2.2 },
            { name = "Warden_Eye_R", kind = "sphere", position = { 0.12, 1.12, 0.22 }, scale = { 0.09, 0.09, 0.05 }, color = C.spectral_hot, emissive = 2.2 },
            { name = "Warden_Scythe", kind = "cube", position = { 0.52, 1.04, 0.06 }, scale = { 0.30, 0.10, 0.06 }, color = C.bone, emissive = 1.0 },
        },
    },
}

Grave.roles = {
    swarm  = "risen",
    ranged = "grave_archer",
    elite  = "bonewraith",
    brute  = "gravewarden",
}

return Grave
