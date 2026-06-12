-- Shadow Hunt — the cast.
--
-- Pure DATA. Every creature is a horde/creep.lua-compatible archetype, plus two
-- ATH extensions the shared Duel honours:
--   * extras  = a list of decorative ath_art PART specs welded on after build
--               (the creature's signature silhouette — no code, just data).
--   * texture = an optional "Textures/..." painted onto the body.
--
-- This level is a predator/prey hunt in the dark. The horde are SHADOW entities:
-- they live in the near-void and are barely visible until the hero's torch (or a
-- lit sconce) catches them — at which point they FLARE white and freeze (see the
-- stun system in mode.lua). So every creature here is painted near-black with a
-- tiny emissive floor; the mode raises/lowers that emissive each frame to fake
-- the dual-layer visibility. Keep new shadows dark and amorphous to match.
--
-- Two HERO rigs ship here (Torch Bearer / Blind Swordsman). The Duel runs ONE
-- hero, so mode.lua picks a rig at launch (ATH_SHADOW_HERO) and tunes the torch
-- to match. Roles map the four level-agnostic card/spawn roles to this cast so
-- the shared 50-card deck works here unchanged.

local Shadow = {}

-- Shared palette (the brief's hex, normalised). The whole level reads as one
-- claustrophobic stone tomb: near-void floor, faint cold stone, warm torch.
local C = {
    void       = { 0.020, 0.020, 0.020 }, -- #050505 near-void
    shadow     = { 0.067, 0.067, 0.067 }, -- #111111 shadow
    stone      = { 0.133, 0.133, 0.133 }, -- #222222 stone
    amber      = { 1.000, 0.600, 0.000 }, -- #ff9900 torch amber
    torchlight = { 1.000, 0.933, 0.533 }, -- #ffee88 torchlight yellow
    deep       = { 0.102, 0.000, 0.000 }, -- #1a0000 deep shadow
    pale       = { 0.62, 0.60, 0.66 },    -- a cold corpse highlight (sconce-lit flesh)
    voidlit    = { 0.30, 0.18, 0.42 },    -- the cold violet a shadow leaks when revealed
}
Shadow.palette = C

Shadow.theme = {
    accent       = { 1.0, 0.60, 0.0, 0.95 },
    floor        = { 0.06, 0.055, 0.05 },          -- near-void flagstone
    floor_texture = "Textures/modes/shadow/floor.png",
    wall         = { 0.12, 0.12, 0.13 },           -- dark stone
    spawn_sigil  = { 0.20, 0.06, 0.30 },           -- a cold violet rift the shades pour from
    aura         = { 1.0, 0.6, 0.0, 0.35 },        -- the hero's torch ring
    hero_body    = { 0.16, 0.15, 0.17 },
    hero_trim    = { 1.0, 0.62, 0.10 },
    hud_title    = "SHADOW HUNT",
    win_text     = "The torch gutters out. The dark keeps what it takes.\nPress R to run it back  -  M for menu",
    lose_text    = "The hunter becomes the hunted. The dark is full.\nPress R to run it back  -  M for menu",
}

-- ---------------------------------------------------------------------------
-- HERO RIGS — two variants. Part keys (body/head/hand_*/foot_*/sword) match
-- ath_art's built-in walk/attack clips; extra keys ride the root for flavour.
-- mode.lua selects one and applies the matching torch tuning below.
-- ---------------------------------------------------------------------------

-- Torch Bearer: a lantern-knight. More light, weaker blade. The torch part is a
-- bright amber flame the mode flickers; the cone of vision is wide.
Shadow.hero_torch = {
    name = "Torch_Bearer",
    parts = {
        body   = { kind = "cube",   position = { 0.0, 0.55, 0.0 },  scale = { 0.46, 0.72, 0.32 }, color = { 0.18, 0.16, 0.18 }, emissive = 0.30 },
        head   = { kind = "sphere", position = { 0.0, 1.06, 0.0 },  scale = { 0.38, 0.36, 0.38 }, color = C.pale,              emissive = 0.40 },
        hand_r = { kind = "sphere", position = { 0.30, 0.66, 0.05 },scale = { 0.15, 0.15, 0.15 }, color = { 0.20, 0.18, 0.20 },emissive = 0.30 },
        hand_l = { kind = "sphere", position = {-0.34, 0.78, 0.10 },scale = { 0.15, 0.15, 0.15 }, color = { 0.20, 0.18, 0.20 },emissive = 0.30 },
        foot_r = { kind = "cube",   position = { 0.13, 0.05, 0.0 }, scale = { 0.18, 0.10, 0.22 }, color = C.void,              emissive = 0.20 },
        foot_l = { kind = "cube",   position = {-0.13, 0.05, 0.0 }, scale = { 0.18, 0.10, 0.22 }, color = C.void,              emissive = 0.20 },
        sword  = { kind = "cube",   position = { 0.36, 0.46, 0.10 },scale = { 0.06, 0.52, 0.07 }, color = { 0.55, 0.50, 0.40 },emissive = 0.40 },
        -- The torch: a haft in the off-hand topped by a bright flame the mode
        -- flickers each frame (see Shadow torch animation). Texture-ready.
        torch_haft = { kind = "cylinder", position = {-0.34, 0.92, 0.10 }, scale = { 0.06, 0.40, 0.06 }, color = { 0.28, 0.18, 0.08 }, emissive = 0.3 },
        torch_flame= { kind = "sphere",   position = {-0.34, 1.20, 0.10 }, scale = { 0.22, 0.30, 0.22 }, color = C.amber, emissive = 2.4, texture = "Textures/modes/shadow/torch_flame.png" },
    },
}

-- Blind Swordsman: blindfolded, hears the dark. Less light, far stronger blade.
-- No torch part (his "torch" is a dim ember at the belt); the cone is narrow.
Shadow.hero_blind = {
    name = "Blind_Swordsman",
    parts = {
        body   = { kind = "cube",   position = { 0.0, 0.56, 0.0 },  scale = { 0.50, 0.74, 0.34 }, color = { 0.14, 0.13, 0.15 }, emissive = 0.26 },
        head   = { kind = "sphere", position = { 0.0, 1.08, 0.0 },  scale = { 0.40, 0.38, 0.40 }, color = C.pale,              emissive = 0.32 },
        hand_r = { kind = "sphere", position = { 0.32, 0.64, 0.06 },scale = { 0.16, 0.16, 0.16 }, color = { 0.18, 0.16, 0.18 },emissive = 0.26 },
        hand_l = { kind = "sphere", position = {-0.30, 0.64, 0.06 },scale = { 0.16, 0.16, 0.16 }, color = { 0.18, 0.16, 0.18 },emissive = 0.26 },
        foot_r = { kind = "cube",   position = { 0.13, 0.05, 0.0 }, scale = { 0.18, 0.10, 0.24 }, color = C.void,              emissive = 0.18 },
        foot_l = { kind = "cube",   position = {-0.13, 0.05, 0.0 }, scale = { 0.18, 0.10, 0.24 }, color = C.void,              emissive = 0.18 },
        -- A long, heavy two-hander — his answer to the dark.
        sword  = { kind = "cube",   position = { 0.38, 0.50, 0.10 },scale = { 0.09, 0.78, 0.10 }, color = { 0.66, 0.64, 0.58 },emissive = 0.55 },
        -- The blindfold and a dim belt ember (his only light).
        blindfold  = { kind = "cube",   position = { 0.0, 1.12, -0.02 }, scale = { 0.42, 0.10, 0.42 }, color = { 0.08, 0.06, 0.06 }, emissive = 0.10 },
        torch_flame= { kind = "sphere", position = { 0.0, 0.46, -0.16 }, scale = { 0.12, 0.12, 0.10 }, color = C.amber, emissive = 1.4, texture = "Textures/modes/shadow/torch_flame.png" },
    },
}

-- Per-rig tuning the mode applies: HP/DPS trade and torch reach/spread. The
-- Torch Bearer sees far and wide but hits soft; the Blind Swordsman is a slim
-- candle of vision wrapped around a brutal blade.
Shadow.hero_tuning = {
    torch_bearer   = { hp_max = 92.0,  dps = 17.0, cleave = 3, attack_range = 1.25, speed = 2.25, kite_speed = 2.8, torch_radius = 7.5, cone_deg = 78.0, inner_radius = 2.6 },
    blind_swordsman= { hp_max = 108.0, dps = 27.0, cleave = 4, attack_range = 1.45, speed = 2.10, kite_speed = 2.6, torch_radius = 4.2, cone_deg = 46.0, inner_radius = 1.9 },
}

-- A faint default the menu/Duel reach for before the mode picks; mode.lua sets
-- config.hero.actor explicitly, so this is just a safe fallback.
Shadow.hero_actor = Shadow.hero_torch

-- ---------------------------------------------------------------------------
-- SHADOW BOLT — the wraith's ranged attack. A cold void orb that still has to
-- read against the near-black floor, so it leaks the revealed-violet glow.
-- ---------------------------------------------------------------------------
local function shadow_bolt(color)
    return {
        kind = "orb", speed = 11.0, cooldown = 1.05, start_y = 0.86, target_y = 0.92,
        particle_size = 0.32, scale = { 0.22, 0.22, 0.30 }, color = color or C.voidlit,
        emissive = 1.6, arc = 0.16, pulse = true, impact = false,
        hit_radius = 0.7, flight_grace = 0.10,
    }
end

-- ---------------------------------------------------------------------------
-- THE SHADOWS. All near-black with a low emissive floor; mode.lua drives the
-- per-frame reveal/pulse. `extras` give each an amorphous blob silhouette.
-- ---------------------------------------------------------------------------

Shadow.archetypes = {
    -- SHADE — fast glass-cannon chaff that streaks out of the dark. Cheap, frail,
    -- quick. The thing that catches a hero who lets his torch wander.
    shade = {
        name = "Shade", threat_cost = 1, hp = 5, dps = 3.0, range = 0.55, speed = 3.2,
        color = C.shadow, head = C.deep, body_scale = { 0.36, 0.42, 0.30 }, head_scale = { 0.26, 0.24, 0.26 },
        parts = 2, scale = 0.95,
        extras = {
            -- A ragged smoke-tail and two cold pin-prick eyes.
            { name = "Shade_Wisp",   kind = "sphere", position = { 0.0, 0.40, -0.18 }, scale = { 0.26, 0.34, 0.22 }, color = C.void,    emissive = 0.10 },
            { name = "Shade_Eye_L",  kind = "sphere", position = {-0.07, 0.74, 0.16 }, scale = { 0.05, 0.05, 0.05 }, color = C.voidlit, emissive = 1.1 },
            { name = "Shade_Eye_R",  kind = "sphere", position = { 0.07, 0.74, 0.16 }, scale = { 0.05, 0.05, 0.05 }, color = C.voidlit, emissive = 1.1 },
        },
    },

    -- WRAITH — a ranged caster that hangs back in the black and lobs void bolts.
    -- Holds line-of-sight like the shared archer/priest pattern.
    wraith = {
        name = "Wraith", threat_cost = 3, hp = 12, dps = 2.2, range = 6.0, speed = 1.1,
        color = C.deep, head = C.voidlit, weapon = C.voidlit,
        body_scale = { 0.40, 0.66, 0.30 }, head_scale = { 0.28, 0.28, 0.28 },
        weapon_pos = { 0.34, 0.66, 0.06 }, weapon_scale = { 0.06, 0.74, 0.06 },
        parts = 3, scale = 1.1, hold_range = 5.5, anchor_hold = true, needs_los = true, los_reposition_seconds = 2.0,
        projectile = shadow_bolt(C.voidlit),
        extras = {
            { name = "Wraith_Shroud", kind = "cylinder", position = { 0.0, 0.36, 0.0 }, scale = { 0.52, 0.62, 0.52 }, color = C.void,    emissive = 0.08 },
            { name = "Wraith_Orb",    kind = "sphere",   position = { 0.34, 1.06, 0.06 },scale = { 0.20, 0.20, 0.20 }, color = C.voidlit, emissive = 1.4 },
        },
    },

    -- UMBRAL STALKER — the deadly one. Slow, tanky, and INVISIBLE EVEN IN
    -- TORCHLIGHT (mode never raises its emissive and never stuns it). You only
    -- ever feel it. Elite role. Tagged by id in mode.lua.
    umbral_stalker = {
        name = "Umbral Stalker", threat_cost = 4, hp = 32, dps = 6.5, range = 0.95, speed = 1.3,
        color = C.void, head = C.void, weapon = C.void,
        body_scale = { 0.54, 0.86, 0.40 }, head_pos = { 0.0, 1.12, -0.04 }, head_scale = { 0.30, 0.30, 0.30 },
        weapon_pos = { 0.44, 0.46, 0.04 }, weapon_scale = { 0.10, 0.62, 0.10 },
        parts = 3, scale = 1.35,
        extras = {
            -- A tall, elongated wraith-cloak. Kept pure void — it does not flare.
            { name = "Stalker_Mantle", kind = "cylinder", position = { 0.0, 0.70, 0.0 }, scale = { 0.62, 1.10, 0.50 }, color = C.void, emissive = 0.04 },
            { name = "Stalker_Claw_L", kind = "cube",      position = {-0.40, 0.40, 0.10 }, scale = { 0.08, 0.46, 0.08 }, color = C.deep, emissive = 0.10 },
            { name = "Stalker_Claw_R", kind = "cube",      position = { 0.40, 0.40, 0.10 }, scale = { 0.08, 0.46, 0.08 }, color = C.deep, emissive = 0.10 },
        },
    },

    -- SHADOW MIMIC — copies the hero's movement, MIRRORED across the maze centre
    -- (mode.lua drives its position). Disorienting: it apes you from the far side
    -- of every corridor and lunges when the mirror folds you together.
    shadow_mimic = {
        name = "Shadow Mimic", threat_cost = 3, hp = 16, dps = 4.0, range = 0.85, speed = 2.2,
        color = C.shadow, head = C.deep, weapon = C.shadow,
        body_scale = { 0.46, 0.72, 0.32 }, head_scale = { 0.36, 0.34, 0.36 },
        weapon_pos = { 0.36, 0.46, 0.10 }, weapon_scale = { 0.06, 0.56, 0.07 },
        parts = 3, scale = 1.0,
        extras = {
            -- A hollow, hero-shaped echo: faint reversed glow so you half-recognise
            -- yourself in the dark.
            { name = "Mimic_Echo",  kind = "cube",   position = { 0.0, 0.55, -0.04 }, scale = { 0.50, 0.76, 0.30 }, color = C.void,    emissive = 0.06 },
            { name = "Mimic_Eye_L", kind = "sphere", position = {-0.08, 1.06, 0.14 }, scale = { 0.05, 0.05, 0.05 }, color = C.voidlit, emissive = 0.9 },
            { name = "Mimic_Eye_R", kind = "sphere", position = { 0.08, 1.06, 0.14 }, scale = { 0.05, 0.05, 0.05 }, color = C.voidlit, emissive = 0.9 },
        },
    },

    -- GLOOM BEHEMOTH — the late brute. A slow avalanche of living dark that herds
    -- the hero toward the kill zone. Brute role.
    gloom_behemoth = {
        name = "Gloom Behemoth", threat_cost = 6, hp = 64, dps = 9.0, range = 1.05, speed = 1.05,
        color = C.void, head = C.shadow, weapon = C.deep,
        body_scale = { 0.78, 0.80, 0.62 }, head_pos = { 0.0, 1.06, -0.04 }, head_scale = { 0.40, 0.36, 0.40 },
        weapon_pos = { 0.50, 0.50, 0.06 }, weapon_scale = { 0.18, 0.78, 0.18 },
        parts = 3, scale = 1.95,
        extras = {
            { name = "Behemoth_Hump_L", kind = "sphere", position = {-0.42, 0.72, -0.10 }, scale = { 0.34, 0.30, 0.34 }, color = C.void,    emissive = 0.05 },
            { name = "Behemoth_Hump_R", kind = "sphere", position = { 0.42, 0.72, -0.10 }, scale = { 0.34, 0.30, 0.34 }, color = C.void,    emissive = 0.05 },
            { name = "Behemoth_Maw",    kind = "cube",   position = { 0.0, 0.66, 0.30 },   scale = { 0.42, 0.20, 0.06 }, color = C.voidlit, emissive = 1.2 },
        },
    },
}

-- Role mapping for the shared deck (swarm/ranged/elite/brute). The named hunt
-- creatures fill swarm/elite/special; wraith + behemoth fill ranged/brute so the
-- 50-card deck plays here unchanged.
Shadow.roles = {
    swarm  = "shade",
    ranged = "wraith",
    elite  = "umbral_stalker",
    brute  = "gloom_behemoth",
}

return Shadow
