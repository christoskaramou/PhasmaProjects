-- Void Collapse — the cast (DATA only).
--
-- VOID COLLAPSE is a bespoke 2D top-down arena mode (placement -> real-time
-- combat, rendered on the runtime_ui canvas — see mode.lua). It does NOT run on
-- the 3D Duel engine. So, exactly like THE PIT, this file is split into two
-- clearly-labelled halves:
--
--   1. Void.void2d — the data the 2D game actually reads: the collapsing arena
--      (a safe disc that shrinks from 40 -> 5 units while the void eats the edge),
--      the four void creatures the Horde fields (Void Fragment / Collapse Echo /
--      Unraveler / Void Architect), the two heroes thrown in, sprite paths, and
--      the cold Dark-Souls void palette. THIS is the heart of the mode.
--
--   2. Void.theme / Void.hero_actor / Void.archetypes / Void.roles — a MINIMAL
--      but valid shared-Duel config so the mode still shows up and plays if it is
--      launched from the battlefield menu (which always drives index modes through
--      ath_duel.lua). The same cast reshaped into horde/creep.lua archetypes; the
--      collapse becomes the Duel's shrinking-arena hazard rather than a creep.
--
-- Every sprite below is produced by tools/gen_textures_void_collapse.py into
--   Assets/Textures/modes/void_collapse/  (referenced as
-- "Textures/modes/void_collapse/<file>.png" — the engine roots image paths at the
-- Assets/ folder). The art is OPTIONAL: if a PNG is absent, each entity still
-- draws as its flat silhouette colour, so the game is fully playable before art.
--
-- Aesthetic: Dark Souls in the key of the abyss. Pitch-black void, deep purples
-- bleeding toward a magenta singularity. The only warm thing is the edge that
-- kills you.

local Void = {}

-- ---------------------------------------------------------------------------
-- Palette — the brief's six notes plus tints derived from them.
--   #000000 void · #05000a deep · #1a0033 collapse purple
--   · #4400aa void core · #aa00ff edge · #ff00ff singularity
-- ---------------------------------------------------------------------------
local C = {
    void        = { 0.000, 0.000, 0.000 },   -- #000000 — the nothing
    deep        = { 0.020, 0.000, 0.039 },   -- #05000a — deep dark
    collapse    = { 0.102, 0.000, 0.200 },   -- #1a0033 — collapse purple
    core        = { 0.267, 0.000, 0.667 },   -- #4400aa — void core
    edge        = { 0.667, 0.000, 1.000 },   -- #aa00ff — the killing edge
    singularity = { 1.000, 0.000, 1.000 },   -- #ff00ff — singularity
    -- Derived tints (so the place reads as one).
    fragment    = { 0.55, 0.10, 0.85 },      -- swarm flesh
    echo        = { 0.45, 0.20, 0.95 },      -- the blinking thing
    unravel     = { 0.78, 0.10, 0.95 },      -- elite
    architect   = { 0.90, 0.05, 1.00 },      -- boss
    -- Heroes read LIGHT so they stand out against the purple dark.
    anchor      = { 0.66, 0.70, 0.78 },      -- cold steel
    anchor_glow = { 0.40, 0.85, 0.95 },      -- anchor's cyan ward
    walker      = { 0.80, 0.74, 0.92 },      -- pale violet
    walker_glow = { 1.00, 0.55, 1.00 },      -- phase-light
    bone        = { 0.82, 0.80, 0.74 },
}
Void.palette = C

local TEX = "Textures/modes/void_collapse/"

-- ===========================================================================
-- 1. Void.void2d — the data the 2D arena game reads.
-- ===========================================================================

Void.void2d = {
    palette = C,

    -- Shared environment / actor art (drawn on the canvas in mode.lua). Frame
    -- lists are swapped on a fixed-fps clock — a "sprite sheet" in spirit; we ship
    -- the frames separately so the canvas can swap `image` without UV sub-rects.
    sprites = {
        floor       = TEX .. "floor_tile.png",      -- 64x64 arena flagstone, tiled
        danger_ring = TEX .. "danger_ring.png",     -- radial-gradient edge overlay
        -- The roiling darkness that closes in (4-frame loop, drawn round the rim).
        edge_frames     = { TEX .. "void_edge_f0.png", TEX .. "void_edge_f1.png", TEX .. "void_edge_f2.png", TEX .. "void_edge_f3.png" },
        -- Creature animation cycles.
        fragment_frames  = { TEX .. "void_fragment_f0.png", TEX .. "void_fragment_f1.png", TEX .. "void_fragment_f2.png", TEX .. "void_fragment_f3.png", TEX .. "void_fragment_f4.png", TEX .. "void_fragment_f5.png" },
        echo_frames      = { TEX .. "collapse_echo_f0.png", TEX .. "collapse_echo_f1.png", TEX .. "collapse_echo_f2.png", TEX .. "collapse_echo_f3.png" },
        unraveler_frames = { TEX .. "unraveler_f0.png", TEX .. "unraveler_f1.png", TEX .. "unraveler_f2.png", TEX .. "unraveler_f3.png", TEX .. "unraveler_f4.png" },
        architect_frames = { TEX .. "void_architect_f0.png", TEX .. "void_architect_f1.png", TEX .. "void_architect_f2.png", TEX .. "void_architect_f3.png", TEX .. "void_architect_f4.png", TEX .. "void_architect_f5.png", TEX .. "void_architect_f6.png", TEX .. "void_architect_f7.png" },
    },

    -- The collapsing arena. All units are world units; mode.lua maps them to
    -- canvas pixels with a top-down transform that ZOOMS as the safe zone shrinks,
    -- so the squeeze stays readable to the very end.
    arena = {
        radius_start = 40.0,            -- the safe disc at t=0
        radius_floor = 5.0,             -- where the collapse bottoms out (singularity)
        collapse_seconds = 240.0,       -- nominal 40 -> 5 over four minutes
        hero_spawn   = { x = 0.0, y = 0.0 },  -- the hero drops dead-centre
        edge_count   = 28,              -- roiling void-edge motes round the rim
    },

    -- The void creatures the Horde seeds before the collapse begins. Up to
    -- `budget` placed by hand; the Horde AI then summons more inside the shrinking
    -- safe zone (and can surge the collapse) all through combat.
    placement = { budget = 6 },

    -- ---- HORDE: the four void creatures ------------------------------------
    horde = {
        -- VOID FRAGMENT — fast melee swarm. Beelines at the hero and steers to
        -- spread from its kin (separation) so a shard-storm surrounds, not stacks.
        void_fragment = {
            id = "void_fragment", name = "Void Fragment", role = "swarm",
            frames = "fragment_frames", fps = 14.0,
            color = C.fragment, glow = C.edge,
            size = 1.3, radius = 0.50,
            hp = 30.0, speed = 5.4,                 -- a hair faster than the heroes
            touch_damage = 11.0, touch_cd = 0.6,
            sep_radius = 1.5, sep_weight = 1.5,
            sway_amp = 0.10, sway_freq = 5.0,
            ap_cost = 10.0,                          -- Horde AP to summon one
            blurb = "Fast swarm. Surrounds in a shard-storm.",
        },
        -- COLLAPSE ECHO — a blink-stalker. Drifts, then teleports to the hero's
        -- flank and strikes; gone the instant you turn on it.
        collapse_echo = {
            id = "collapse_echo", name = "Collapse Echo", role = "blink",
            frames = "echo_frames", fps = 10.0,
            color = C.echo, glow = C.singularity,
            size = 1.5, radius = 0.55,
            hp = 44.0, speed = 2.4,
            touch_damage = 20.0, touch_cd = 0.9,
            blink_cd = 3.2, blink_range = 2.2,       -- teleports beside the hero
            blink_telegraph = 0.45,                  -- a beat of warning before it lands
            sway_amp = 0.14, sway_freq = 3.0,
            ap_cost = 22.0,
            blurb = "Teleports to your flank, then strikes.",
        },
        -- UNRAVELER — elite. A slow heavy whose unwinding aura drags the hero's
        -- pace to a crawl; the wall you must cut down before the void does it for you.
        unraveler = {
            id = "unraveler", name = "Unraveler", role = "elite",
            frames = "unraveler_frames", fps = 8.0,
            color = C.unravel, glow = C.edge,
            size = 2.2, radius = 0.85,
            hp = 150.0, speed = 2.0,
            touch_damage = 16.0, touch_cd = 0.8,
            slow_range = 4.2, slow_mult = 0.55,      -- hero move-speed multiplier in aura
            sep_radius = 1.8, sep_weight = 0.8,
            sway_amp = 0.05, sway_freq = 2.2,
            ap_cost = 60.0,
            blurb = "Elite. Its aura unwinds your speed.",
        },
        -- VOID ARCHITECT — boss. Hauls the safe zone's centre toward itself, so the
        -- void bulges in from one side: it can "extend the collapse in a direction".
        void_architect = {
            id = "void_architect", name = "Void Architect", role = "boss",
            frames = "architect_frames", fps = 9.0,
            color = C.architect, glow = C.singularity,
            size = 3.2, radius = 1.25,
            hp = 420.0, speed = 1.5,
            touch_damage = 26.0, touch_cd = 1.0,
            pull_strength = 1.6,                     -- u/s it drags the safe centre
            pull_range = 30.0,
            sway_amp = 0.04, sway_freq = 1.6,
            ap_cost = 140.0,
            blurb = "Boss. Drags the void in from one side.",
        },
    },
    horde_order = { "void_fragment", "collapse_echo", "unraveler", "void_architect" },

    -- ---- HEROES: the two ways to be squeezed (player drives one) ------------
    heroes = {
        -- ANCHOR — tanky and slow, warded against the void. Lives long in the edge
        -- but can never outrun the squeeze; survival is attrition and positioning.
        anchor = {
            id = "anchor", name = "Anchor",
            color = C.anchor, glow = C.anchor_glow,
            size = 1.8, radius = 0.62,
            hp = 180.0, speed = 4.2,
            attack_damage = 46.0, attack_range = 1.9, attack_cd = 0.60,
            void_resist = 0.45,                      -- takes 45% of edge damage
            walk_bob = 0.10, walk_freq = 9.0,
            phase = nil,
            blurb = "Tanky. Warded — endures the void's edge.",
        },
        -- VOID WALKER — fast and fragile, full void damage normally, BUT [Shift]
        -- phases: a brief window of speed and total void immunity to cross the dark.
        void_walker = {
            id = "void_walker", name = "Void Walker",
            color = C.walker, glow = C.walker_glow,
            size = 1.5, radius = 0.50,
            hp = 110.0, speed = 6.2,
            attack_damage = 26.0, attack_range = 1.5, attack_cd = 0.34,
            void_resist = 1.0,                       -- normal: full edge damage
            phase = { time = 1.0, cd = 4.0, speed = 9.5 },  -- [Shift] cross the void safely
            walk_bob = 0.16, walk_freq = 12.0,
            blurb = "Fast, fragile. [Shift] phases through the void.",
        },
    },
    hero_order = { "anchor", "void_walker" },
}

-- ===========================================================================
-- 2. Shared-Duel fallback (menu launch). Minimal but valid: the SAME cast as
--    horde/creep.lua archetypes, so Void Collapse is playable from the menu too.
--    mode.lua's signature hook turns the collapse into a shrinking safe-radius
--    hazard there — stray outside the closing ring and the void corrodes you.
-- ===========================================================================

Void.theme = {
    accent        = { 0.667, 0.0, 1.0, 0.95 },
    floor         = C.collapse,
    floor_texture = TEX .. "floor_tile.png",
    wall          = C.deep,
    spawn_sigil   = C.edge,
    aura          = { 0.667, 0.0, 1.0, 0.45 },
    hero_body     = C.anchor,
    hero_trim     = C.edge,
    hud_title     = "VOID COLLAPSE",
    win_text      = "You held the centre as the void closed.\nPress R to run it back  -  M for menu",
    lose_text     = "The edge took you. You unravel into the dark.\nPress R to run it back  -  M for menu",
}

-- The Duel hero rig (primitive actor; part keys match ath_art's walk/attack clips).
Void.hero_actor = {
    name = "Void_Hero",
    parts = {
        body   = { kind = "cube",   position = { 0.0, 0.56, 0.0 },  scale = { 0.50, 0.76, 0.36 }, color = C.anchor, emissive = 0.45 },
        head   = { kind = "sphere", position = { 0.0, 1.10, 0.0 },  scale = { 0.38, 0.40, 0.40 }, color = C.bone,   emissive = 0.40 },
        hand_r = { kind = "sphere", position = { 0.34, 0.66, 0.05 },scale = { 0.16, 0.16, 0.16 }, color = C.anchor, emissive = 0.40 },
        hand_l = { kind = "sphere", position = { -0.34, 0.66, 0.05 },scale = { 0.16, 0.16, 0.16 }, color = C.anchor,emissive = 0.40 },
        foot_r = { kind = "cube",   position = { 0.14, 0.05, 0.0 }, scale = { 0.18, 0.10, 0.24 }, color = C.deep,   emissive = 0.25 },
        foot_l = { kind = "cube",   position = { -0.14, 0.05, 0.0 },scale = { 0.18, 0.10, 0.24 }, color = C.deep,   emissive = 0.25 },
        sword  = { kind = "cube",   position = { 0.38, 0.52, 0.10 },scale = { 0.08, 0.74, 0.10 }, color = C.edge,   emissive = 1.4 },
        ward   = { kind = "sphere", position = { 0.0, 0.66, -0.10 },scale = { 0.16, 0.18, 0.06 }, color = C.singularity, emissive = 1.8 },
    },
}

local function void_bolt(color)
    return {
        kind = "orb", speed = 15.0, cooldown = 1.1, start_y = 0.85, target_y = 0.85,
        particle_size = 0.30, scale = { 0.20, 0.20, 0.42 }, color = color or C.edge,
        emissive = 2.2, arc = 0.06, pulse = true, impact = false, gravity = -1.4,
        hit_radius = 0.7, flight_grace = 0.10,
    }
end

Void.archetypes = {
    -- Void Fragment — the cheap fast chaff that pours in.
    void_fragment = {
        name = "Void Fragment", threat_cost = 1, hp = 9, dps = 3.2, range = 0.6, speed = 2.9,
        color = C.fragment, head = C.edge, body_scale = { 0.34, 0.42, 0.30 }, head_scale = { 0.24, 0.24, 0.24 },
        parts = 2, scale = 0.95, texture = TEX .. "void_fragment_f0.png",
        extras = {
            { name = "Frag_Shard", kind = "cube", position = { 0.0, 0.52, -0.06 }, scale = { 0.10, 0.30, 0.10 }, color = C.singularity, emissive = 1.6, rotation = { 0.0, 0.0, 0.5 } },
        },
    },
    -- Collapse Echo — the ranged caster that lobs a void bolt (its blink doesn't
    -- survive into the Duel, so it holds and casts instead).
    collapse_echo = {
        name = "Collapse Echo", threat_cost = 3, hp = 15, dps = 2.6, range = 6.0, speed = 1.6,
        color = C.echo, head = C.singularity, weapon = C.edge,
        body_scale = { 0.38, 0.62, 0.30 }, head_scale = { 0.28, 0.28, 0.28 },
        weapon_pos = { 0.34, 0.62, 0.08 }, weapon_scale = { 0.07, 0.80, 0.07 },
        parts = 3, scale = 1.1, hold_range = 5.5, anchor_hold = true, needs_los = true, los_reposition_seconds = 2.0,
        projectile = void_bolt(C.singularity),
        texture = TEX .. "collapse_echo_f0.png",
        extras = {
            { name = "Echo_Orb", kind = "sphere", position = { 0.34, 1.12, 0.08 }, scale = { 0.22, 0.22, 0.22 }, color = C.singularity, emissive = 1.9 },
        },
    },
    -- Unraveler — the tanky elite wall the cleave must chew through.
    unraveler = {
        name = "Unraveler", threat_cost = 4, hp = 40, dps = 7.0, range = 0.95, speed = 1.6,
        color = C.unravel, head = C.core, weapon = C.deep,
        body_scale = { 0.62, 0.58, 0.48 }, head_pos = { 0.0, 0.84, -0.04 }, head_scale = { 0.34, 0.30, 0.34 },
        weapon_pos = { 0.44, 0.38, 0.04 }, weapon_scale = { 0.18, 0.40, 0.18 },
        parts = 3, scale = 1.45, texture = TEX .. "unraveler_f0.png",
        extras = {
            { name = "Unravel_Ring", kind = "cylinder", position = { 0.0, 1.20, 0.0 }, scale = { 0.46, 0.10, 0.46 }, color = C.edge, emissive = 1.6 },
            { name = "Unravel_Core", kind = "sphere", position = { 0.0, 0.56, -0.24 }, scale = { 0.28, 0.32, 0.10 }, color = C.singularity, emissive = 1.9 },
        },
    },
    -- Void Architect — the slow, devastating boss that arrives late.
    void_architect = {
        name = "Void Architect", threat_cost = 6, hp = 72, dps = 9.0, range = 1.0, speed = 1.2,
        color = C.architect, head = C.singularity, weapon = C.core,
        body_scale = { 0.76, 0.80, 0.58 }, head_pos = { 0.0, 1.06, -0.04 }, head_scale = { 0.40, 0.36, 0.40 },
        weapon_pos = { 0.48, 0.50, 0.06 }, weapon_scale = { 0.16, 0.78, 0.16 },
        parts = 3, scale = 2.0, texture = TEX .. "void_architect_f0.png",
        extras = {
            { name = "Architect_Crown", kind = "cylinder", position = { 0.0, 1.40, 0.0 }, scale = { 0.50, 0.12, 0.50 }, color = C.singularity, emissive = 2.0 },
            { name = "Architect_Core", kind = "sphere", position = { 0.0, 0.74, -0.28 }, scale = { 0.32, 0.36, 0.12 }, color = C.edge, emissive = 2.2 },
            { name = "Architect_Spire_L", kind = "cube", position = { -0.36, 0.96, 0.0 }, scale = { 0.10, 0.30, 0.10 }, color = C.edge, emissive = 1.6 },
            { name = "Architect_Spire_R", kind = "cube", position = { 0.36, 0.96, 0.0 }, scale = { 0.10, 0.30, 0.10 }, color = C.edge, emissive = 1.6 },
        },
    },
}

Void.roles = {
    swarm  = "void_fragment",
    ranged = "collapse_echo",
    elite  = "unraveler",
    brute  = "void_architect",
}

return Void
