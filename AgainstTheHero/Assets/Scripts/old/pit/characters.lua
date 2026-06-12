-- The Pit — the cast (DATA only).
--
-- THE PIT is a bespoke 2D top-down arena mode (placement → real-time combat,
-- rendered on the runtime_ui canvas — see mode.lua). It does NOT run on the 3D
-- Duel engine. So this file is split into two clearly-labelled halves:
--
--   1. Pit.pit2d   — the data the 2D game actually reads: the circular arena, the
--                    horde entities the player places (Shade Walker / Bone Thrower
--                    / Spike Trap), the two hero archetypes, sprite paths, and the
--                    grim Dark-Souls palette. THIS is the heart of the mode.
--
--   2. Pit.theme / Pit.hero_actor / Pit.archetypes / Pit.roles — a MINIMAL but
--      valid shared-Duel config so the mode still shows up and plays if launched
--      from the menu (which always drives index modes through ath_duel.lua). The
--      same cast, reshaped into horde/creep.lua archetypes. Spike Trap becomes the
--      Duel's environmental hazard rather than a creep.
--
-- Every sprite below is produced by tools/gen_textures_pit.py into
--   Assets/Textures/modes/pit/   (referenced as "Textures/modes/pit/<file>.png",
-- the engine roots texture/image paths at the Assets/ folder). The art is
-- OPTIONAL: if the PNGs are absent, every entity still draws as its flat silhouette
-- colour, so the game is fully playable before art exists.
--
-- Aesthetic: Dark Souls. Ash-grey stone, dried-blood crimson, and the one warm
-- thing in this place — torchfire orange. No bright colours. Grim and oppressive.

local Pit = {}

-- ---------------------------------------------------------------------------
-- Palette — the brief's four notes plus tints derived from them.
--   #1a1a1a ash · #3d3d3d stone · #8b0000 blood · #ff6600 fire
-- ---------------------------------------------------------------------------
local C = {
    ash       = { 0.102, 0.102, 0.102 },   -- #1a1a1a — the pit's stone dark
    stone     = { 0.239, 0.239, 0.239 },   -- #3d3d3d — flagstone
    stone_lo  = { 0.160, 0.160, 0.170 },
    iron      = { 0.30, 0.30, 0.34 },
    grave     = { 0.13, 0.14, 0.15 },
    blood     = { 0.545, 0.0, 0.0 },        -- #8b0000 — dried blood
    blood_hot = { 0.74, 0.10, 0.10 },
    fire      = { 1.0, 0.40, 0.0 },         -- #ff6600 — torchfire
    fire_hot  = { 1.0, 0.58, 0.18 },
    bone      = { 0.78, 0.76, 0.66 },
    pale      = { 0.62, 0.64, 0.68 },       -- hollow/shade flesh
}
Pit.palette = C

local TEX = "Textures/modes/pit/"

-- ===========================================================================
-- 1. Pit.pit2d — the data the 2D arena game reads.
-- ===========================================================================

Pit.pit2d = {
    palette = C,

    -- Shared environment art (drawn on the canvas in mode.lua).
    sprites = {
        floor      = TEX .. "floor_tile.png",     -- 64x64 cracked stone, tiled
        rim        = TEX .. "rim_tile.png",       -- 64x64 darker pit-wall stone
        blood      = TEX .. "blood_splat.png",    -- 64x64 RGBA decal
        exit       = TEX .. "exit.png",           -- the way out (north gap)
        bolt       = TEX .. "bone_proj.png",      -- the thrown bone
        -- Torch flicker: 4 discrete frames swapped at 8fps (a "sprite sheet" in
        -- spirit; we ship the frames separately so the canvas can swap `image`
        -- without needing UV sub-rects). torch_sheet.png is also generated for
        -- reference / re-skinning.
        torch_frames = { TEX .. "torch_f0.png", TEX .. "torch_f1.png", TEX .. "torch_f2.png", TEX .. "torch_f3.png" },
    },

    -- The circular stone pit. All units are world units; mode.lua maps them to
    -- canvas pixels with a fixed top-down transform (the whole pit fits in frame).
    arena = {
        radius      = 13.0,                 -- playable disc radius
        hero_spawn  = { x = 0.0, y = 10.6 },-- the hero drops in at the south lip
        exit        = { x = 0.0, y = -12.4 },-- and must reach the gap in the north
        exit_radius = 1.8,                  -- step into this to escape
        torch_count = 8,                    -- evenly spaced around the rim
    },

    -- The horde the player places before the hero is released. Up to `budget`
    -- entities, any mix. Each is one of three archetypes.
    placement = { budget = 5 },

    -- ---- HORDE: the three things you place around the pit --------------------
    horde = {
        -- SHADE WALKER — fast melee. Beelines at the hero; steers to spread out
        -- from its kin (separation) so a pack surrounds instead of stacking.
        shade_walker = {
            id = "shade_walker", name = "Shade Walker", role = "melee",
            sprite = TEX .. "shade_walker.png", color = C.pale, glow = C.blood,
            size = 1.5,                      -- world-units sprite footprint
            radius = 0.55,                   -- collision / contact radius
            hp = 64.0, speed = 5.0,          -- a touch faster than the knight
            touch_damage = 16.0, touch_cd = 0.7,
            sep_radius = 1.6, sep_weight = 1.5,
            sway_amp = 0.10, sway_freq = 4.0,
            blurb = "Fast melee. Hunts in a spreading pack.",
        },
        -- BONE THROWER — ranged. Holds a preferred distance and lobs a bone on a
        -- high parabolic arc, leading the hero's movement.
        bone_thrower = {
            id = "bone_thrower", name = "Bone Thrower", role = "ranged",
            sprite = TEX .. "bone_thrower.png", color = C.bone, glow = C.fire,
            size = 1.6, radius = 0.55,
            hp = 44.0, speed = 3.0,
            prefer_range = 8.0, retreat_range = 5.5, hold_range = 10.0,
            throw_cd = 1.9,
            projectile = {
                speed = 10.0,                -- horizontal travel speed (u/s)
                arc_peak = 3.2,              -- visual lob height at apex
                lead = 0.55,                 -- how much it leads hero velocity
                damage = 22.0, blast = 1.4,  -- splash radius at the landing point
                size = 0.9,
            },
            sway_amp = 0.06, sway_freq = 3.0,
            blurb = "Ranged. Lobs bones on an arc that leads you.",
        },
        -- SPIKE TRAP — static. Arms, telegraphs when stepped on, then erupts.
        spike_trap = {
            id = "spike_trap", name = "Spike Trap", role = "trap",
            sprite = TEX .. "spike_trap_armed.png",
            sprite_fire = TEX .. "spike_trap_fire.png",
            color = C.iron, glow = C.fire,
            size = 1.7, radius = 0.9,
            trigger_radius = 1.7, telegraph = 0.45, active = 0.40,
            damage = 38.0, rearm = 2.6,
            blurb = "Static. Erupts when the hero lingers on it.",
        },
    },
    -- Display order for the placement palette.
    horde_order = { "shade_walker", "bone_thrower", "spike_trap" },

    -- ---- HEROES: the two playstyles released into the pit (player drives one) --
    heroes = {
        -- ASHEN KNIGHT — tanky, slow, heavy cleaving swing.
        ashen_knight = {
            id = "ashen_knight", name = "Ashen Knight",
            sprite_base = TEX .. "hero_knight_d", -- + "<dir>.png", dir 0..7
            color = C.iron, glow = C.fire,
            size = 1.7, radius = 0.60,
            hp = 150.0, speed = 4.4,
            attack_damage = 46.0, attack_range = 1.9, attack_cd = 0.62, attack_arc = 1.0,
            dash = nil,
            walk_bob = 0.12, walk_freq = 9.0,
            blurb = "Tanky. Slow. A wide, punishing cleave.",
        },
        -- PALE HUNTER — fragile, fast, with a short dash to slip the pack.
        pale_hunter = {
            id = "pale_hunter", name = "Pale Hunter",
            sprite_base = TEX .. "hero_hunter_d",
            color = C.pale, glow = C.fire_hot,
            size = 1.5, radius = 0.50,
            hp = 92.0, speed = 6.4,
            attack_damage = 24.0, attack_range = 1.4, attack_cd = 0.34, attack_arc = 0.7,
            dash = { speed = 15.0, time = 0.16, cd = 1.1 }, -- [Shift] burst
            walk_bob = 0.16, walk_freq = 12.0,
            blurb = "Fast, fragile. [Shift] dashes through the swarm.",
        },
    },
    hero_order = { "ashen_knight", "pale_hunter" },
}

-- ===========================================================================
-- 2. Shared-Duel fallback (menu launch). Minimal but valid: the SAME cast as
--    horde/creep.lua archetypes, so The Pit is playable from the battlefield
--    menu too. mode.lua's signature hook turns Spike Traps into erupting floor
--    hazards there (the trap can't be a roaming creep).
-- ===========================================================================

Pit.theme = {
    accent       = { 1.0, 0.40, 0.0, 0.95 },
    floor        = C.ash,
    floor_texture = TEX .. "floor_tile.png",
    wall         = C.stone_lo,
    spawn_sigil  = C.blood,
    aura         = { 1.0, 0.40, 0.0, 0.45 },
    hero_body    = C.iron,
    hero_trim    = C.fire,
    hud_title    = "THE PIT",
    win_text     = "You climbed out of the pit alive.\nPress R to run it back  -  M for menu",
    lose_text    = "The pit keeps another. You go Hollow.\nPress R to run it back  -  M for menu",
}

-- The Duel hero rig (primitive actor; part keys match ath_art's walk/attack clips).
Pit.hero_actor = {
    name = "Pit_Hero",
    parts = {
        body   = { kind = "cube",   position = { 0.0, 0.56, 0.0 },  scale = { 0.50, 0.76, 0.36 }, color = C.iron,  emissive = 0.45 },
        head   = { kind = "sphere", position = { 0.0, 1.10, 0.0 },  scale = { 0.38, 0.40, 0.40 }, color = C.stone, emissive = 0.40 },
        hand_r = { kind = "sphere", position = { 0.34, 0.66, 0.05 },scale = { 0.16, 0.16, 0.16 }, color = C.iron,  emissive = 0.40 },
        hand_l = { kind = "sphere", position = { -0.34, 0.66, 0.05 },scale = { 0.16, 0.16, 0.16 }, color = C.iron, emissive = 0.40 },
        foot_r = { kind = "cube",   position = { 0.14, 0.05, 0.0 }, scale = { 0.18, 0.10, 0.24 }, color = C.ash,   emissive = 0.25 },
        foot_l = { kind = "cube",   position = { -0.14, 0.05, 0.0 },scale = { 0.18, 0.10, 0.24 }, color = C.ash,   emissive = 0.25 },
        sword  = { kind = "cube",   position = { 0.38, 0.52, 0.10 },scale = { 0.08, 0.74, 0.10 }, color = C.pale,  emissive = 0.70 },
        soul   = { kind = "sphere", position = { 0.0, 0.66, -0.10 },scale = { 0.14, 0.16, 0.06 }, color = C.fire_hot, emissive = 1.7 },
    },
}

local function bone_bolt(color)
    return {
        kind = "orb", speed = 14.0, cooldown = 1.2, start_y = 0.85, target_y = 0.85,
        particle_size = 0.28, scale = { 0.20, 0.20, 0.42 }, color = color or C.bone,
        emissive = 1.6, arc = 0.18, pulse = true, impact = false, gravity = -2.0,
        hit_radius = 0.7, flight_grace = 0.10,
    }
end

Pit.archetypes = {
    -- Shade Walker doubles as the swarm AND the elite wall in the Duel fallback.
    shade_walker = {
        name = "Shade Walker", threat_cost = 1, hp = 12, dps = 3.4, range = 0.6, speed = 2.8,
        color = C.pale, head = C.blood_hot, body_scale = { 0.36, 0.50, 0.30 }, head_scale = { 0.24, 0.26, 0.24 },
        parts = 2, scale = 1.0, texture = TEX .. "shade_walker.png",
        extras = {
            { name = "Shade_Claw", kind = "cube", position = { 0.0, 0.52, 0.18 }, scale = { 0.26, 0.30, 0.04 }, color = C.bone, emissive = 0.6 },
        },
    },
    -- Bone Thrower — the ranged anchor that lobs bones.
    bone_thrower = {
        name = "Bone Thrower", threat_cost = 3, hp = 16, dps = 2.6, range = 6.0, speed = 1.2,
        color = C.grave, head = C.bone, weapon = C.bone,
        body_scale = { 0.40, 0.66, 0.32 }, head_scale = { 0.28, 0.30, 0.28 },
        weapon_pos = { 0.36, 0.62, 0.08 }, weapon_scale = { 0.07, 0.86, 0.07 },
        parts = 3, scale = 1.1, hold_range = 6.0, anchor_hold = true, needs_los = true, los_reposition_seconds = 2.0,
        projectile = bone_bolt(C.bone),
        texture = TEX .. "bone_thrower.png",
        extras = {
            { name = "Thrower_Sack", kind = "sphere", position = { -0.30, 0.50, 0.0 }, scale = { 0.22, 0.24, 0.22 }, color = C.bone, emissive = 0.8 },
        },
    },
    -- Spike Trap as a stationary "creep" so role mapping is valid; it never roams
    -- (speed 0) and is excluded from auto_mix — the signature hook erupts spikes.
    spike_trap = {
        name = "Spike Trap", threat_cost = 2, hp = 24, dps = 6.0, range = 1.0, speed = 0.0,
        color = C.iron, head = C.fire, body_scale = { 0.6, 0.18, 0.6 }, head_scale = { 0.2, 0.2, 0.2 },
        parts = 2, scale = 1.2, texture = TEX .. "spike_trap_armed.png",
    },
}

Pit.roles = {
    swarm  = "shade_walker",
    ranged = "bone_thrower",
    elite  = "spike_trap",
    brute  = "shade_walker",
}

return Pit
