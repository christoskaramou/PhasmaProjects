-- Colosseum — the cast (DATA only).
--
-- COLOSSEUM is a bespoke 2D top-down arena mode (escalating ROUND survival in a
-- gladiatorial pit, rendered on the runtime_ui canvas — see mode.lua). It does
-- NOT run on the 3D Duel engine. So, like THE PIT and GRAVEWARDEN, this file is
-- split into two clearly-labelled halves:
--
--   1. Colo.colo2d — the data the 2D game actually reads: the rectangular sand
--      arena ringed by crowd stands, the four PORTCULLIS gates the waves pour
--      from, the five escalating ROUNDS, the horde the rounds release (Gladiator /
--      Net Thrower / Sand Beast / Iron Champion), the Colosseum Master boss, the
--      two playable heroes (Pit Fighter / Duelist), the CROWD FURY tuning, sprite
--      paths, and the grim Dark-Souls sand-and-blood palette. THIS is the heart.
--
--   2. Colo.theme / hero_actor / archetypes / roles — a MINIMAL but valid shared-
--      Duel config so the mode still shows up and plays if launched from the menu
--      (which always drives index modes through ath_duel.lua). The same cast,
--      reshaped into horde/creep.lua archetypes; CROWD FURY there feeds a free
--      Iron Champion straight onto the field (the Duel exposes Duel:spawn_one).
--
-- Every sprite below is produced by tools/gen_textures_colosseum.py into
--   Assets/Textures/modes/colosseum/   (referenced as "Textures/modes/colosseum/
-- <file>.png"; the engine roots texture/image paths at Assets/). The art is
-- OPTIONAL: if the PNGs are absent, every entity still draws as its flat
-- silhouette colour, so the mode is fully playable before art exists.
--
-- Aesthetic: Dark Souls arena. Black-brown shadow, dried blood in the sand,
-- cold iron, and the one warm note — the torch-gold of the roaring stands.

local Colo = {}

-- ---------------------------------------------------------------------------
-- Palette — the brief's five notes plus tints derived from them.
--   #1a0f00 shadow · #3d2200 dark sand · #6b3300 sand · #8b0000 blood
--   · #cc9900 torch gold
-- ---------------------------------------------------------------------------
local C = {
    shadow    = { 0.102, 0.059, 0.000 },   -- #1a0f00 — the pit's deepest dark
    sand_lo   = { 0.239, 0.133, 0.000 },   -- #3d2200 — packed dark sand
    sand      = { 0.420, 0.200, 0.000 },   -- #6b3300 — raked arena sand
    sand_hi   = { 0.560, 0.300, 0.080 },   -- sun-bleached high sand
    blood     = { 0.545, 0.000, 0.000 },   -- #8b0000 — spilled blood
    blood_hot = { 0.760, 0.120, 0.090 },
    gold      = { 0.800, 0.600, 0.000 },   -- #cc9900 — torchfire / crowd gold
    gold_hot  = { 1.000, 0.780, 0.220 },
    iron      = { 0.340, 0.320, 0.300 },   -- weapons, grates, plate
    iron_hi   = { 0.520, 0.500, 0.470 },
    bone      = { 0.780, 0.740, 0.600 },
    flesh     = { 0.620, 0.460, 0.300 },   -- gladiator skin/leather
}
Colo.palette = C

local TEX = "Textures/modes/colosseum/"

-- ===========================================================================
-- 1. Colo.colo2d — the data the 2D arena game reads.
-- ===========================================================================

Colo.colo2d = {
    palette = C,

    -- Shared environment art (drawn on the canvas in mode.lua).
    sprites = {
        floor      = TEX .. "floor_tile.png",     -- 64x64 dark blood-stained sand, tiled
        crowd      = TEX .. "crowd_tile.png",     -- 64x64 stone stands w/ crowd silhouettes
        gateway    = TEX .. "gateway.png",         -- the dark arch behind each portcullis
        portcullis = TEX .. "portcullis.png",      -- the iron grate that lifts (open/close)
        net        = TEX .. "net.png",             -- the Net Thrower's thrown net
        splat      = TEX .. "splat.png",           -- blood decal
        glow       = TEX .. "glow.png",            -- radial glow (fury flare / boss sweep / lunge)
        torch_frames = { TEX .. "torch_f0.png", TEX .. "torch_f1.png", TEX .. "torch_f2.png", TEX .. "torch_f3.png" },
        -- Blood accumulation overlays — one per round, the sand grows bloodier (0..4).
        blood_stages = { TEX .. "blood_0.png", TEX .. "blood_1.png", TEX .. "blood_2.png", TEX .. "blood_3.png", TEX .. "blood_4.png" },
    },

    -- The rectangular sand pit. Centred on the origin: x in [-half_w, half_w],
    -- y in [-half_h, half_h] (world units). The whole arena + stands fit in frame
    -- (a fixed top-down camera, so the crowd on all four sides is always visible).
    arena = {
        half_w     = 16.0, half_h = 12.0,         -- playable sand half-extents
        hero_spawn = { x = 0.0, y = 0.0 },        -- the hero is thrown into the centre
        stand_depth = 3.6,                        -- how far the crowd stands ring the pit
        -- The four PORTCULLIS gates, set into the wall midpoints; `n` is the
        -- outward normal the grate retracts along (and the side waves pour from).
        gates = {
            { x =  0.0, y = -12.0, nx =  0.0, ny = -1.0 },  -- north
            { x =  0.0, y =  12.0, nx =  0.0, ny =  1.0 },  -- south
            { x =  16.0, y =  0.0, nx =  1.0, ny =  0.0 },  -- east
            { x = -16.0, y =  0.0, nx = -1.0, ny =  0.0 },  -- west
        },
    },

    -- ---- ROUND TUNING --------------------------------------------------------
    -- Combat runs as five escalating rounds. Each round the portcullis ASCENDS to
    -- release that round's wave; clear it and the gates DESCEND, the sand drinks
    -- another stage of blood, and the next round opens. Round 5 looses the
    -- COLOSSEUM MASTER. The composition of each round is `rounds[i]` (a map of
    -- archetype id -> count); round 5 also rises the boss.
    rounds = {
        { gladiator = 4 },
        { gladiator = 5, net_thrower = 2 },
        { gladiator = 6, net_thrower = 2, sand_beast = 3 },
        { gladiator = 6, net_thrower = 3, sand_beast = 4, iron_champion = 1 },
        { gladiator = 3, sand_beast = 2 },   -- + the Colosseum Master (boss)
    },
    boss_round = 5,
    gate_open_time  = 1.6,   -- the portcullis takes this long to ASCEND (release)
    gate_close_time = 1.3,   -- ...and this long to DESCEND between rounds
    round_break     = 1.4,   -- a beat of held breath once the gates have shut

    -- ---- CROWD FURY ----------------------------------------------------------
    -- The signature mechanic. The crowd's bloodlust (0..max) climbs whenever blood
    -- is spilled — the hero KILLS a foe, or the hero TAKES a hit. The stands roar
    -- louder (brighter, pulsing gold) as it fills. At MAX the mob bays for a
    -- champion: the horde gets a FREE Iron Champion through a gate, and the fury
    -- empties to begin again.
    fury = {
        max          = 100.0,
        per_kill     = 13.0,    -- crowd-pleasing: a clean kill stokes the mob
        per_damage   = 0.45,    -- ...and so does the hero bleeding (× damage taken)
        decay        = 1.4,     -- bleeds down slowly during a lull (per second)
        champion     = "iron_champion",
    },

    -- ---- HORDE: what the rounds release (spawned at the gates) ----------------
    horde = {
        -- GLADIATOR — the balanced melee backbone. Seeks the hero and spreads from
        -- its kin (separation) so a pack flanks instead of stacking; strikes on
        -- contact. The roar of the rounds.
        gladiator = {
            id = "gladiator", name = "Gladiator", kind = "melee",
            frames = 6, fps = 7.0, sprite_base = TEX .. "gladiator_f",
            color = C.flesh, glow = C.iron,
            size = 1.7, radius = 0.55,
            hp = 46.0, speed = 2.9,
            touch_damage = 12.0, touch_cd = 0.75,
            sep_radius = 1.5, sep_weight = 1.4,
            sway_amp = 0.08, sway_freq = 4.0,
            blurb = "Balanced melee. Flanks in a spreading pack.",
        },
        -- NET THROWER — ranged control. Holds a band and lobs a weighted net that
        -- lands on a leading arc; caught in it, the hero is SLOWED (and grazed).
        net_thrower = {
            id = "net_thrower", name = "Net Thrower", kind = "thrower",
            frames = 5, fps = 5.5, sprite_base = TEX .. "net_thrower_f",
            color = C.bone, glow = C.gold,
            size = 1.7, radius = 0.55,
            hp = 30.0, speed = 2.2,
            prefer_range = 9.0, retreat_range = 5.5, hold_range = 12.0,
            throw_cd = 2.4,
            net = { speed = 11.0, arc_peak = 2.8, lead = 0.55, damage = 8.0, blast = 1.9,
                    size = 1.6, slow = 0.42, slow_time = 1.9 },  -- catch = slowed for slow_time
            sep_radius = 1.4, sep_weight = 1.0,
            sway_amp = 0.05, sway_freq = 3.0,
            blurb = "Ranged. Lobs a net that snares and slows you.",
        },
        -- SAND BEAST — the fast ambusher. Low, quick, and it LUNGES: when it gets a
        -- clear line it bursts forward in a pounce, then recovers. Fragile but it
        -- closes the gap before you can read it.
        sand_beast = {
            id = "sand_beast", name = "Sand Beast", kind = "beast",
            frames = 4, fps = 9.0, sprite_base = TEX .. "sand_beast_f",
            color = C.sand_hi, glow = C.blood,
            size = 1.6, radius = 0.50,
            hp = 26.0, speed = 4.6,
            touch_damage = 14.0, touch_cd = 0.6,
            lunge = { range = 6.0, speed = 11.0, time = 0.32, cd = 2.6 },
            sep_radius = 1.1, sep_weight = 0.9,
            sway_amp = 0.12, sway_freq = 6.0,
            blurb = "Fast ambusher. Pounces from range.",
        },
        -- IRON CHAMPION — the elite. Hulking, armoured, slow but punishing; the
        -- prize the crowd screams for at full FURY. A wide 128x64 sprite.
        iron_champion = {
            id = "iron_champion", name = "Iron Champion", kind = "champion",
            frames = 8, fps = 6.0, sprite_base = TEX .. "iron_champion_f", aspect = 2.0,
            color = C.iron, glow = C.gold_hot,
            size = 2.8, radius = 0.95,
            hp = 220.0, speed = 2.1,
            touch_damage = 26.0, touch_cd = 0.85,
            sep_radius = 1.8, sep_weight = 1.2,
            sway_amp = 0.04, sway_freq = 2.4,
            blurb = "Elite. Released when the crowd's fury peaks.",
        },
    },
    -- Display order (used by the round-card readout / minimap legend).
    horde_order = { "gladiator", "net_thrower", "sand_beast", "iron_champion" },

    -- ---- BOSS: the Colosseum Master ------------------------------------------
    -- The arena's undefeated master, loosed at round 5. Slow but relentless; he
    -- periodically TELEGRAPHS and SWEEPS his greatblade in a wide killing ring.
    -- A 128x128 sprite, drawn large. Cut him down to win the games.
    boss = {
        id = "colosseum_master", name = "The Colosseum Master", kind = "boss",
        frames = 8, fps = 6.0, sprite_base = TEX .. "master_f",
        color = C.iron, glow = C.gold_hot,
        size = 5.0, radius = 1.6,
        hp = 820.0, speed = 1.6,
        touch_damage = 30.0, touch_cd = 0.9,
        sweep = { range = 4.6, telegraph = 1.1, active = 0.35, damage = 56.0, cd = 4.2 },
        sway_amp = 0.05, sway_freq = 1.8,
    },

    -- ---- HEROES: the two you can be thrown in as -----------------------------
    heroes = {
        -- PIT FIGHTER — the brawler. Heavy, durable, a wide punishing cleave that
        -- carves the whole pack at once. Slow to swing but built to outlast.
        pit_fighter = {
            id = "pit_fighter", name = "Pit Fighter",
            sprite_base = TEX .. "hero_pitfighter_d",   -- + "<dir>.png", dir 0..7
            color = C.flesh, glow = C.gold_hot,
            size = 1.8, radius = 0.60,
            hp = 170.0, speed = 4.6,
            attack_damage = 48.0, attack_range = 2.2, attack_cd = 0.60,
            walk_bob = 0.12, walk_freq = 9.0,
            blurb = "Brawler. Tanky, with a wide crowd-clearing cleave.",
        },
        -- DUELIST — the counter-attack specialist. Fragile and fast; getting hit
        -- opens a RIPOSTE window — strike inside it and the blow lands for far
        -- more. Punish the swarm's mistakes instead of trading blows.
        duelist = {
            id = "duelist", name = "Duelist",
            sprite_base = TEX .. "hero_duelist_d",
            color = C.bone, glow = C.blood_hot,
            size = 1.6, radius = 0.50,
            hp = 100.0, speed = 5.6,
            attack_damage = 26.0, attack_range = 1.7, attack_cd = 0.34,
            counter = { window = 0.85, mult = 2.6 },    -- riposte after a hit
            walk_bob = 0.16, walk_freq = 12.0,
            blurb = "Counter specialist. Riposte right after you're hit.",
        },
    },
    hero_order = { "pit_fighter", "duelist" },
}

-- ===========================================================================
-- 2. Shared-Duel fallback (menu launch). Minimal but valid: the SAME cast as
--    horde/creep.lua archetypes, so Colosseum is playable from the battlefield
--    menu too. mode.lua's signature hook keeps CROWD FURY there — it climbs as
--    the hero deals/takes damage and, at max, looses a FREE Iron Champion
--    straight onto the field via Duel:spawn_one.
-- ===========================================================================

Colo.theme = {
    accent        = { 0.800, 0.600, 0.0, 0.95 },
    floor         = C.sand_lo,
    floor_texture = TEX .. "floor_tile.png",
    wall          = C.shadow,
    spawn_sigil   = C.gold,
    aura          = { 0.800, 0.600, 0.0, 0.45 },
    hero_body     = C.flesh,
    hero_trim     = C.gold_hot,
    hud_title     = "COLOSSEUM",
    win_text      = "The crowd roars your name. You walk out of the sand alive.\nPress R to run it back  -  M for menu",
    lose_text     = "The sand drinks you, and the crowd bays for the next.\nPress R to run it back  -  M for menu",
}

-- The Duel hero rig (primitive actor; part keys match ath_art's walk/attack clips).
Colo.hero_actor = {
    name = "Colosseum_Hero",
    parts = {
        body   = { kind = "cube",   position = { 0.0, 0.56, 0.0 },  scale = { 0.50, 0.76, 0.36 }, color = C.flesh,  emissive = 0.45 },
        head   = { kind = "sphere", position = { 0.0, 1.10, 0.0 },  scale = { 0.38, 0.40, 0.40 }, color = C.bone,   emissive = 0.40 },
        hand_r = { kind = "sphere", position = { 0.34, 0.66, 0.05 }, scale = { 0.16, 0.16, 0.16 }, color = C.flesh, emissive = 0.40 },
        hand_l = { kind = "sphere", position = { -0.34, 0.66, 0.05 },scale = { 0.16, 0.16, 0.16 }, color = C.flesh, emissive = 0.40 },
        foot_r = { kind = "cube",   position = { 0.14, 0.05, 0.0 }, scale = { 0.18, 0.10, 0.24 }, color = C.sand_lo, emissive = 0.25 },
        foot_l = { kind = "cube",   position = { -0.14, 0.05, 0.0 },scale = { 0.18, 0.10, 0.24 }, color = C.sand_lo, emissive = 0.25 },
        sword  = { kind = "cube",   position = { 0.38, 0.52, 0.10 },scale = { 0.08, 0.74, 0.10 }, color = C.iron_hi, emissive = 0.70 },
        crest  = { kind = "sphere", position = { 0.0, 0.66, -0.10 },scale = { 0.14, 0.16, 0.06 }, color = C.gold_hot, emissive = 1.7 },
    },
}

local function net_bolt(color)
    return {
        kind = "orb", speed = 12.0, cooldown = 1.3, start_y = 0.85, target_y = 0.85,
        particle_size = 0.30, scale = { 0.26, 0.10, 0.26 }, color = color or C.bone,
        emissive = 1.2, arc = 0.18, pulse = true, impact = false, gravity = -2.0,
        hit_radius = 0.8, flight_grace = 0.10,
    }
end

Colo.archetypes = {
    -- GLADIATOR — the swarm, and the cheap wall the hero's cleave chews through.
    gladiator = {
        name = "Gladiator", threat_cost = 1, hp = 13, dps = 3.4, range = 0.6, speed = 2.7,
        color = C.flesh, head = C.bone, weapon = C.iron,
        body_scale = { 0.40, 0.54, 0.32 }, head_scale = { 0.24, 0.26, 0.24 },
        weapon_pos = { 0.34, 0.52, 0.06 }, weapon_scale = { 0.07, 0.56, 0.07 },
        parts = 3, scale = 1.0, texture = TEX .. "gladiator_f0.png",
        extras = {
            { name = "Glad_Shield", kind = "cube", position = { -0.30, 0.52, 0.06 }, scale = { 0.10, 0.34, 0.30 }, color = C.iron_hi, emissive = 0.6 },
        },
    },
    -- NET THROWER — the ranged anchor that lobs nets (a thrown orb here).
    net_thrower = {
        name = "Net Thrower", threat_cost = 3, hp = 16, dps = 2.6, range = 6.0, speed = 1.4,
        color = C.bone, head = C.flesh, weapon = C.bone,
        body_scale = { 0.38, 0.62, 0.30 }, head_scale = { 0.26, 0.28, 0.26 },
        weapon_pos = { 0.34, 0.58, 0.08 }, weapon_scale = { 0.06, 0.44, 0.06 },
        parts = 3, scale = 1.05, hold_range = 6.0, anchor_hold = true, needs_los = true, los_reposition_seconds = 2.0,
        projectile = net_bolt(C.bone),
        texture = TEX .. "net_thrower_f0.png",
        extras = {
            { name = "Net_Coil", kind = "sphere", position = { -0.28, 0.50, 0.0 }, scale = { 0.22, 0.20, 0.22 }, color = C.bone, emissive = 0.7 },
        },
    },
    -- SAND BEAST — the fast chaser; a low, quick body that closes hard.
    sand_beast = {
        name = "Sand Beast", threat_cost = 2, hp = 10, dps = 4.4, range = 0.6, speed = 3.8,
        color = C.sand_hi, head = C.blood_hot, body_scale = { 0.50, 0.34, 0.40 }, head_scale = { 0.22, 0.22, 0.26 },
        parts = 2, scale = 1.0, texture = TEX .. "sand_beast_f0.png",
        extras = {
            { name = "Beast_Maw", kind = "cube", position = { 0.0, 0.30, 0.22 }, scale = { 0.26, 0.10, 0.06 }, color = C.bone, emissive = 0.8 },
        },
    },
    -- IRON CHAMPION — the elite; the crowd's prize, a tanky armoured wall.
    iron_champion = {
        name = "Iron Champion", threat_cost = 4, hp = 44, dps = 8.0, range = 0.95, speed = 2.0,
        color = C.iron, head = C.iron_hi, weapon = C.iron_hi,
        body_scale = { 0.62, 0.66, 0.48 }, head_pos = { 0.0, 0.86, -0.04 }, head_scale = { 0.30, 0.30, 0.30 },
        weapon_pos = { 0.44, 0.46, 0.04 }, weapon_scale = { 0.14, 0.66, 0.14 },
        parts = 3, scale = 1.4, texture = TEX .. "iron_champion_f0.png",
        extras = {
            { name = "Champ_Crest", kind = "cylinder", position = { 0.0, 1.16, 0.0 }, scale = { 0.34, 0.10, 0.34 }, color = C.gold_hot, emissive = 1.8 },
            { name = "Champ_Pauldron", kind = "sphere", position = { -0.34, 0.72, 0.0 }, scale = { 0.22, 0.20, 0.22 }, color = C.iron_hi, emissive = 0.8 },
        },
    },
    -- THE COLOSSEUM MASTER — the boss; a slow, devastating colossus that arrives late.
    colosseum_master = {
        name = "The Colosseum Master", threat_cost = 6, hp = 84, dps = 9.5, range = 1.1, speed = 1.3,
        color = C.iron, head = C.iron_hi, weapon = C.gold,
        body_scale = { 0.80, 0.84, 0.62 }, head_pos = { 0.0, 1.12, -0.04 }, head_scale = { 0.40, 0.38, 0.40 },
        weapon_pos = { 0.54, 0.56, 0.06 }, weapon_scale = { 0.16, 0.96, 0.16 },
        parts = 3, scale = 2.0, texture = TEX .. "master_f0.png",
        extras = {
            { name = "Master_Crown", kind = "cylinder", position = { 0.0, 1.42, 0.0 }, scale = { 0.50, 0.12, 0.50 }, color = C.gold_hot, emissive = 1.8 },
            { name = "Master_Eye_L", kind = "sphere", position = { -0.12, 1.14, 0.22 }, scale = { 0.09, 0.09, 0.05 }, color = C.gold_hot, emissive = 2.2 },
            { name = "Master_Eye_R", kind = "sphere", position = { 0.12, 1.14, 0.22 }, scale = { 0.09, 0.09, 0.05 }, color = C.gold_hot, emissive = 2.2 },
            { name = "Master_Blade", kind = "cube", position = { 0.54, 1.06, 0.06 }, scale = { 0.34, 0.10, 0.06 }, color = C.iron_hi, emissive = 1.0 },
        },
    },
}

Colo.roles = {
    swarm  = "gladiator",
    ranged = "net_thrower",
    elite  = "iron_champion",
    brute  = "colosseum_master",
}

return Colo
