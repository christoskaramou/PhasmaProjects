-- IRON GALLOWS — the cast (DATA only).
--
-- IRON GALLOWS is a bespoke 2D top-down EXECUTION CHAMBER, drawn on the
-- runtime_ui canvas (see mode.lua) — NOT the shared 3D Duel engine. So, exactly
-- like THE PIT, this file is split into two clearly-labelled halves:
--
--   1. Gallows.gallows2d — the data the 2D game actually reads: the stone
--      chamber, the four execution DEVICES bolted to the floor (guillotine,
--      iron maiden, spike panel, wall press), the three Horde OPERATORS the
--      player deploys to work them, the two condemned HEROES, sprite paths, and
--      the grim iron palette. THIS is the heart of the mode.
--
--   2. Gallows.theme / hero_actor / archetypes / roles — a MINIMAL but valid
--      shared-Duel config so the mode still shows up and plays if launched from
--      the battlefield menu (which always drives index modes through ath_duel).
--      The same cast reshaped into horde/creep.lua archetypes; the execution
--      devices become the Duel's environmental hazard rather than props.
--
-- Every sprite below is produced by tools/gen_textures_gallows.py into
--   Assets/Textures/modes/iron_gallows/   (referenced as "Textures/modes/iron_gallows/<file>",
-- the engine roots texture/image paths at the Assets/ folder). The art is
-- OPTIONAL: if a PNG is absent, every entity still draws as its flat silhouette
-- colour, so the game is fully playable before art exists.
--
-- Aesthetic: Dark Souls. Black iron, cold rust, dried blood, and the one signal
-- that means death is coming — the alert-red glow of an arming device.

local Gallows = {}

-- ---------------------------------------------------------------------------
-- Palette — the brief's six notes plus tints derived from them.
--   #0a0a0a void · #1e1e1e dark · #3c3c3c iron · #5a3a00 rust
--   #8b0000 blood · #ff3300 alert-red
-- ---------------------------------------------------------------------------
local C = {
    void      = { 0.039, 0.039, 0.039 },   -- #0a0a0a — the chamber's pitch black
    dark      = { 0.118, 0.118, 0.118 },   -- #1e1e1e — sooty stone
    iron      = { 0.235, 0.235, 0.235 },   -- #3c3c3c — device iron
    iron_hi   = { 0.36, 0.36, 0.38 },
    rust      = { 0.353, 0.227, 0.0 },     -- #5a3a00 — old rust on the chains
    rust_hot  = { 0.52, 0.34, 0.06 },
    blood     = { 0.545, 0.0, 0.0 },       -- #8b0000 — dried blood
    blood_hot = { 0.74, 0.10, 0.10 },
    alert     = { 1.0, 0.20, 0.0 },        -- #ff3300 — the arming glow / death tell
    alert_hi  = { 1.0, 0.42, 0.18 },
    bone      = { 0.74, 0.71, 0.62 },
    pale      = { 0.60, 0.60, 0.64 },      -- convict flesh / steel
}
Gallows.palette = C

local TEX = "Textures/modes/iron_gallows/"

-- ===========================================================================
-- 1. Gallows.gallows2d — the data the 2D execution-chamber game reads.
-- ===========================================================================

Gallows.gallows2d = {
    palette = C,

    -- Shared environment art (drawn on the canvas in mode.lua). Missing PNGs are
    -- harmless — the canvas just shows the flat fill underneath.
    sprites = {
        floor = TEX .. "floor_tile.png",   -- 64x64 cracked stone, tiled
        wall  = TEX .. "wall_tile.png",    -- 64x64 dark chamber wall band
        chain = TEX .. "chain.png",        -- overhead ceiling-chain detail
        blood = TEX .. "blood_splat.png",  -- RGBA decal
        door  = TEX .. "door.png",         -- the far door (escape, north wall)
    },

    -- The rectangular chamber, centred on the origin. World units; mode.lua maps
    -- them to canvas pixels with a fixed top-down transform (the whole room fits
    -- in frame). Screen +y is SOUTH, so the hero drops in at +y and must reach
    -- the door at -y (the far, north wall).
    arena = {
        half_w     = 11.5,                 -- chamber spans x in [-half_w, half_w]
        half_h     = 8.5,                  --              and y in [-half_h, half_h]
        tile       = 1.6,                  -- floor-tile world size (drawing only)
        hero_spawn = { x = 0.0, y = 7.2 }, -- the condemned is shoved in at the south
        door       = { x = 0.0, y = -7.6 },-- and must thread the gauntlet to the door
        door_radius = 1.7,                 -- step into this to escape
        chain_count = 7,                   -- decorative ceiling chains swaying overhead
    },

    -- How many devices may be ARMING (telegraph) or KILLING (trigger) at once.
    -- This is the signature EXECUTION QUEUE: the Horde can only line up so many
    -- killings at a time, so the hero always has a safe seam to run through.
    queue_cap = 3,

    -- The deployable Horde. Up to `budget` operators, any mix, placed before the
    -- hero is released. Each one drives the chamber's fixed devices.
    deploy = { budget = 4 },

    -- ---- DEVICES: the four execution machines bolted into the floor ----------
    -- Fixed props (laid out by mode.lua). Each cycles a 4-state machine:
    --   idle -> telegraph (red glow, `telegraph`s) -> trigger (lethal, `trigger`s)
    --   -> reset (`reset`s, sped up by a Blood Engineer) -> idle.
    -- `zone` is the kill rectangle (world units) centred on the device.
    devices = {
        -- GUILLOTINE — a blade drops down a narrow vertical lane (1 tile wide).
        guillotine = {
            id = "guillotine", name = "Guillotine",
            sprites = {
                idle      = TEX .. "guillotine_idle.png",
                telegraph = TEX .. "guillotine_telegraph.png",
                trigger   = TEX .. "guillotine_trigger.png",
                reset     = TEX .. "guillotine_reset.png",
            },
            color = C.iron, size = 2.0,
            zone = { w = 1.5, h = 4.4 },   -- tall thin lane
            telegraph = 1.5, trigger = 0.45, reset = 2.4,
            damage = 80.0,
        },
        -- IRON MAIDEN — a 2x2 sarcophagus slams shut on whatever it caught.
        iron_maiden = {
            id = "iron_maiden", name = "Iron Maiden",
            sprites = {
                idle      = TEX .. "iron_maiden_idle.png",
                telegraph = TEX .. "iron_maiden_telegraph.png",
                trigger   = TEX .. "iron_maiden_trigger.png",
                reset     = TEX .. "iron_maiden_reset.png",
            },
            color = C.iron, size = 2.6,
            zone = { w = 2.9, h = 2.9 },   -- the 2x2 slam
            telegraph = 1.5, trigger = 0.55, reset = 3.0,
            damage = 95.0,
        },
        -- SPIKE PANEL — a floor section erupts with iron spikes over a wide area.
        spike_panel = {
            id = "spike_panel", name = "Spike Panel",
            sprites = {
                idle      = TEX .. "spike_panel_idle.png",
                telegraph = TEX .. "spike_panel_telegraph.png",
                trigger   = TEX .. "spike_panel_trigger.png",
                reset     = TEX .. "spike_panel_reset.png",
            },
            color = C.dark, size = 3.2,
            zone = { w = 3.3, h = 3.3 },   -- the panel footprint
            telegraph = 1.5, trigger = 0.7, reset = 2.0,
            damage = 55.0,
        },
        -- WALL PRESS — a wall slab sweeps the full width of the room at its row.
        wall_press = {
            id = "wall_press", name = "Wall Press",
            sprites = {
                idle      = TEX .. "wall_press_idle.png",
                telegraph = TEX .. "wall_press_telegraph.png",
                trigger   = TEX .. "wall_press_trigger.png",
                reset     = TEX .. "wall_press_reset.png",
            },
            color = C.iron, size = 2.4,
            zone = { w = 0.0, h = 2.0 },   -- w=0 -> mode fills it with chamber width
            full_width = true,
            telegraph = 1.5, trigger = 0.6, reset = 3.4,
            damage = 70.0,
        },
    },

    -- ---- OPERATORS: the three Horde villains you deploy to work the devices --
    operators = {
        -- TORTURER — the headsman. Roams toward the hero and pulls TWO levers at
        -- once (arms two devices per activation, queue permitting). Slow, tough.
        torturer = {
            id = "torturer", name = "Torturer", role = "headsman",
            sprite_frames = {
                TEX .. "torturer_f0.png", TEX .. "torturer_f1.png", TEX .. "torturer_f2.png",
                TEX .. "torturer_f3.png", TEX .. "torturer_f4.png",
            },
            anim_fps = 6.0,
            color = C.blood, glow = C.alert, size = 1.9, radius = 0.62,
            hp = 90.0, speed = 2.6, keep_range = 6.0,   -- hangs back at a lever
            activate_cd = 3.2, activate_count = 2,      -- arms two devices at a time
            sep_radius = 1.8, sep_weight = 1.2,
            sway_amp = 0.06, sway_freq = 2.4,
            blurb = "Arms TWO devices at once.",
        },
        -- BLOOD ENGINEER — the mechanic. Rearms (resets) nearby devices far
        -- faster, so the gauntlet never goes quiet. Arms one device occasionally.
        blood_engineer = {
            id = "blood_engineer", name = "Blood Engineer", role = "mechanic",
            sprite = TEX .. "blood_engineer.png",
            color = C.rust_hot, glow = C.alert_hi, size = 1.7, radius = 0.55,
            hp = 60.0, speed = 2.2, keep_range = 8.0,
            activate_cd = 4.5, activate_count = 1,
            repair_radius = 6.5, repair_mult = 3.0,     -- resets devices 3x faster in range
            sep_radius = 1.6, sep_weight = 1.0,
            sway_amp = 0.05, sway_freq = 2.0,
            blurb = "Resets nearby devices 3x faster.",
        },
        -- INQUISITOR — the elite. Chases the hero down for a melee kill AND arms
        -- a device on the way. The one operator you cannot simply outrun.
        inquisitor = {
            id = "inquisitor", name = "Inquisitor", role = "elite",
            sprite = TEX .. "inquisitor.png",
            color = C.pale, glow = C.blood_hot, size = 1.8, radius = 0.58,
            hp = 110.0, speed = 4.6,                    -- runs the hero down
            touch_damage = 20.0, touch_cd = 0.7,
            activate_cd = 3.8, activate_count = 1,
            sep_radius = 1.6, sep_weight = 1.3,
            sway_amp = 0.07, sway_freq = 3.2,
            blurb = "Elite melee. Hunts you AND arms devices.",
        },
    },
    operator_order = { "torturer", "blood_engineer", "inquisitor" },

    -- ---- HEROES: the two condemned the player drives to the door ------------
    heroes = {
        -- CONDEMNED KNIGHT — tanky, slow, a wide punishing cleave. Eats a graze
        -- and keeps walking; cut the operators down to silence the chamber.
        condemned_knight = {
            id = "condemned_knight", name = "Condemned Knight",
            sprite_base = TEX .. "hero_knight_d",  -- + "<dir>.png", dir 0..3 (E,S,W,N)
            color = C.iron, glow = C.alert, size = 1.8, radius = 0.60,
            hp = 165.0, speed = 4.2,
            attack_damage = 48.0, attack_range = 1.9, attack_cd = 0.60,
            dash = nil,
            walk_bob = 0.12, walk_freq = 9.0,
            blurb = "Tanky. Slow. A wide, punishing cleave.",
        },
        -- ESCAPED PRISONER — fragile, fast, a short dash to slip a closing device.
        escaped_prisoner = {
            id = "escaped_prisoner", name = "Escaped Prisoner",
            sprite_base = TEX .. "hero_convict_d",
            color = C.pale, glow = C.alert_hi, size = 1.5, radius = 0.48,
            hp = 92.0, speed = 6.6,
            attack_damage = 22.0, attack_range = 1.4, attack_cd = 0.32,
            dash = { speed = 16.0, time = 0.16, cd = 1.0 },  -- [Shift] burst
            walk_bob = 0.16, walk_freq = 12.0,
            blurb = "Fast, fragile. [Shift] dashes through a closing trap.",
        },
    },
    hero_order = { "condemned_knight", "escaped_prisoner" },
}

-- ===========================================================================
-- 2. Shared-Duel fallback (menu launch). Minimal but valid: the SAME cast as
--    horde/creep.lua archetypes, so IRON GALLOWS is playable from the menu too.
--    mode.lua's signature hook turns the execution devices into erupting floor
--    hazards there (a fixed prop can't be a roaming creep). A cheap chained
--    THRALL fills the swarm role the duel deck needs.
-- ===========================================================================

Gallows.theme = {
    accent        = { 1.0, 0.20, 0.0, 0.95 },
    floor         = C.void,
    floor_texture = TEX .. "floor_tile.png",
    wall          = C.dark,
    spawn_sigil   = C.alert,
    aura          = { 1.0, 0.20, 0.0, 0.45 },
    hero_body     = C.iron,
    hero_trim     = C.alert,
    hud_title     = "IRON GALLOWS",
    win_text      = "You walked out of the execution chamber alive.\nPress R to run it back  -  M for menu",
    lose_text     = "The chamber claims another. The devices reset.\nPress R to run it back  -  M for menu",
}

-- The Duel hero rig (primitive actor; part keys match ath_art's walk/attack clips).
Gallows.hero_actor = {
    name = "Gallows_Hero",
    parts = {
        body   = { kind = "cube",   position = { 0.0, 0.56, 0.0 },  scale = { 0.50, 0.76, 0.36 }, color = C.iron,  emissive = 0.40 },
        head   = { kind = "sphere", position = { 0.0, 1.10, 0.0 },  scale = { 0.38, 0.40, 0.40 }, color = C.pale,  emissive = 0.40 },
        hand_r = { kind = "sphere", position = { 0.34, 0.66, 0.05 }, scale = { 0.16, 0.16, 0.16 }, color = C.iron, emissive = 0.40 },
        hand_l = { kind = "sphere", position = { -0.34, 0.66, 0.05 }, scale = { 0.16, 0.16, 0.16 }, color = C.iron, emissive = 0.40 },
        foot_r = { kind = "cube",   position = { 0.14, 0.05, 0.0 }, scale = { 0.18, 0.10, 0.24 }, color = C.void,  emissive = 0.20 },
        foot_l = { kind = "cube",   position = { -0.14, 0.05, 0.0 }, scale = { 0.18, 0.10, 0.24 }, color = C.void, emissive = 0.20 },
        sword  = { kind = "cube",   position = { 0.38, 0.52, 0.10 }, scale = { 0.08, 0.74, 0.10 }, color = C.bone, emissive = 0.70 },
        shackle = { kind = "sphere", position = { 0.0, 0.30, 0.18 }, scale = { 0.18, 0.10, 0.06 }, color = C.alert, emissive = 1.4 },
    },
}

local function rust_bolt(color)
    return {
        kind = "orb", speed = 13.0, cooldown = 1.3, start_y = 0.85, target_y = 0.85,
        particle_size = 0.28, scale = { 0.20, 0.20, 0.40 }, color = color or C.rust_hot,
        emissive = 1.6, arc = 0.16, pulse = true, impact = false, gravity = -2.0,
        hit_radius = 0.7, flight_grace = 0.10,
    }
end

Gallows.archetypes = {
    -- GALLOWS THRALL — cheap chained chaff that floods the chamber (swarm role).
    gallows_thrall = {
        name = "Gallows Thrall", threat_cost = 1, hp = 10, dps = 3.2, range = 0.6, speed = 2.8,
        color = C.pale, head = C.blood_hot, body_scale = { 0.34, 0.48, 0.30 }, head_scale = { 0.24, 0.24, 0.24 },
        parts = 2, scale = 0.95,
        extras = {
            { name = "Thrall_Shackle", kind = "cube", position = { 0.0, 0.30, 0.16 }, scale = { 0.22, 0.10, 0.05 }, color = C.rust, emissive = 0.8 },
        },
    },
    -- BLOOD ENGINEER — the ranged anchor; lobs a rust-iron wrench/bolt.
    blood_engineer = {
        name = "Blood Engineer", threat_cost = 3, hp = 16, dps = 2.6, range = 6.0, speed = 1.2,
        color = C.dark, head = C.rust_hot, weapon = C.iron_hi,
        body_scale = { 0.40, 0.66, 0.32 }, head_scale = { 0.28, 0.30, 0.28 },
        weapon_pos = { 0.36, 0.62, 0.08 }, weapon_scale = { 0.07, 0.70, 0.07 },
        parts = 3, scale = 1.1, hold_range = 6.0, anchor_hold = true, needs_los = true, los_reposition_seconds = 2.0,
        projectile = rust_bolt(C.rust_hot),
        texture = TEX .. "blood_engineer.png",
        extras = {
            { name = "Engineer_Tool", kind = "sphere", position = { -0.30, 0.50, 0.0 }, scale = { 0.20, 0.22, 0.20 }, color = C.iron_hi, emissive = 0.9 },
        },
    },
    -- INQUISITOR — tanky elite the cleave must chew through.
    inquisitor = {
        name = "Inquisitor", threat_cost = 4, hp = 36, dps = 7.5, range = 0.95, speed = 1.9,
        color = C.iron, head = C.pale, weapon = C.bone,
        body_scale = { 0.60, 0.58, 0.46 }, head_pos = { 0.0, 0.84, -0.04 }, head_scale = { 0.32, 0.30, 0.32 },
        weapon_pos = { 0.44, 0.40, 0.04 }, weapon_scale = { 0.10, 0.78, 0.10 },
        parts = 3, scale = 1.35, texture = TEX .. "inquisitor.png",
        extras = {
            { name = "Inquisitor_Hood", kind = "cube", position = { 0.0, 0.92, 0.0 }, scale = { 0.38, 0.18, 0.34 }, color = C.void, emissive = 0.3 },
            { name = "Inquisitor_Brand", kind = "cube", position = { 0.0, 0.52, -0.22 }, scale = { 0.26, 0.34, 0.04 }, color = C.alert, emissive = 1.4 },
        },
    },
    -- TORTURER — the slow, devastating heavy/boss (brute role).
    torturer = {
        name = "Torturer", threat_cost = 6, hp = 64, dps = 9.5, range = 1.0, speed = 1.3,
        color = C.blood, head = C.dark, weapon = C.iron,
        body_scale = { 0.74, 0.74, 0.56 }, head_pos = { 0.0, 1.00, -0.04 }, head_scale = { 0.34, 0.30, 0.34 },
        weapon_pos = { 0.48, 0.46, 0.06 }, weapon_scale = { 0.18, 0.30, 0.18 },
        parts = 3, scale = 1.9,
        extras = {
            { name = "Torturer_Mask", kind = "cube", position = { 0.0, 1.02, 0.12 }, scale = { 0.30, 0.24, 0.06 }, color = C.iron_hi, emissive = 0.6 },
            { name = "Torturer_Coal", kind = "sphere", position = { 0.0, 0.66, -0.26 }, scale = { 0.28, 0.30, 0.10 }, color = C.alert, emissive = 1.8 },
            { name = "Torturer_Hook", kind = "cube", position = { 0.46, 0.30, 0.06 }, scale = { 0.08, 0.40, 0.08 }, color = C.rust_hot, emissive = 1.0 },
        },
    },
}

Gallows.roles = {
    swarm  = "gallows_thrall",
    ranged = "blood_engineer",
    elite  = "inquisitor",
    brute  = "torturer",
}

return Gallows
