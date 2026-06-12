-- Dark Altar — the cast.
--
-- Pure DATA. Every creature is a horde/creep.lua-compatible archetype, plus two
-- ATH extensions the shared Duel honours:
--   * extras  = a list of decorative ath_art PART specs welded on after build
--               (the creature's signature silhouette — no code, just data).
--   * texture = an optional "Textures/modes/altar/foo.png" painted onto the body
--               (paths resolve relative to Assets/; generate the set with
--               tools/gen_textures_altar.py).
--
-- To add a new horror: copy a block, retune the numbers, restyle the colours and
-- extras, and (optionally) point `texture`/part `texture` at a PNG. No engine
-- edits, ever.
--
-- Roles map the four level-agnostic card/spawn roles to this cast so the shared
-- 50-card deck works here unchanged.

local Altar = {}

-- The eldritch ritual-horror palette (the brief's hex set, 0..1):
--   #080808 void black   #1a001a deep purple   #4400aa rune blue
--   #cc00cc soul purple  #ff0055 blood
local C = {
    void_black   = { 0.031, 0.031, 0.031 },
    deep_purple  = { 0.102, 0.000, 0.102 },
    rune_blue    = { 0.267, 0.000, 0.667 },
    rune_bright  = { 0.40,  0.10,  0.90 },
    soul_purple  = { 0.800, 0.000, 0.800 },
    soul_bright  = { 0.95,  0.30,  0.95 },
    blood        = { 1.000, 0.000, 0.333 },
    blood_dark   = { 0.55,  0.00,  0.18 },
    pale_soul    = { 0.91,  0.69,  1.00 },
    bone         = { 0.86,  0.84,  0.78 },
    grave_grey   = { 0.18,  0.16,  0.22 },
    gold         = { 0.92,  0.80,  0.42 },
}
Altar.palette = C

-- Texture set (drop-ins from tools/gen_textures_altar.py).
Altar.tex = {
    floor       = "Textures/modes/altar/floor.png",
    altar       = "Textures/modes/altar/altar.png",
    soul_bolt   = "Textures/modes/altar/soul_bolt.png",
    void_shade  = "Textures/modes/altar/void_shade_0.png",
    rune        = "Textures/modes/altar/rune_particle_0.png",
    blood       = "Textures/modes/altar/blood_splatter.png",
}

Altar.theme = {
    accent        = { 0.80, 0.00, 0.80, 0.95 },
    floor         = { 0.06, 0.00, 0.07 },        -- tint under the rune-circle texture
    floor_texture = Altar.tex.floor,             -- build_arena paints this on the floor
    wall          = { 0.10, 0.00, 0.14 },
    spawn_sigil   = { 0.80, 0.00, 0.80 },
    aura          = { 0.62, 0.10, 0.92, 0.5 },
    hero_body     = { 0.16, 0.14, 0.24 },
    hero_trim     = { 0.62, 0.78, 1.00 },
    hud_title     = "DARK ALTAR",
    win_text      = "The altar is shattered; the chant dies in the dark.\nPress R to run it back  •  M for menu",
    lose_text     = "The ritual takes the hero — another soul for the altar.\nPress R to run it back  •  M for menu",
}

-- ---- Hero archetypes (TWO rigs; mode.lua picks via ATH_ALTAR_HERO) ----------
-- Part keys match ath_art's built-in walk/attack clips (body, head, hand_r,
-- hand_l, foot_r, foot_l, sword). Extra keys ride the root for flavour.

-- 1) Lightbringer — a radiant dawn-paladin whose holy light defies the void.
local lightbringer = {
    name = "Altar_Lightbringer",
    parts = {
        body   = { kind = "cube",   position = {  0.00, 0.56,  0.00 }, scale = { 0.48, 0.74, 0.34 }, color = { 0.86, 0.88, 0.96 }, emissive = 0.7 },
        head   = { kind = "sphere", position = {  0.00, 1.08,  0.00 }, scale = { 0.40, 0.36, 0.40 }, color = C.bone,            emissive = 0.5 },
        hand_r = { kind = "sphere", position = {  0.32, 0.66,  0.05 }, scale = { 0.16, 0.16, 0.16 }, color = { 0.80, 0.82, 0.90 }, emissive = 0.55 },
        hand_l = { kind = "sphere", position = { -0.32, 0.66,  0.05 }, scale = { 0.16, 0.16, 0.16 }, color = { 0.80, 0.82, 0.90 }, emissive = 0.55 },
        foot_r = { kind = "cube",   position = {  0.13, 0.05,  0.00 }, scale = { 0.18, 0.10, 0.24 }, color = { 0.40, 0.42, 0.52 }, emissive = 0.35 },
        foot_l = { kind = "cube",   position = { -0.13, 0.05,  0.00 }, scale = { 0.18, 0.10, 0.24 }, color = { 0.40, 0.42, 0.52 }, emissive = 0.35 },
        sword  = { kind = "cube",   position = {  0.36, 0.50,  0.10 }, scale = { 0.08, 0.70, 0.09 }, color = { 0.75, 0.90, 1.00 }, emissive = 1.8 },
        -- A halo of dawn-light above the helm (the anti-eldritch motif).
        halo   = { kind = "cylinder", position = { 0.00, 1.40, 0.00 }, scale = { 0.48, 0.05, 0.48 }, color = C.gold,        emissive = 1.6 },
        -- A radiant heart-sigil on the breastplate.
        sigil  = { kind = "sphere",   position = { 0.00, 0.64, -0.16 }, scale = { 0.16, 0.16, 0.06 }, color = { 0.80, 0.92, 1.00 }, emissive = 2.0 },
    },
}

-- 2) Grave Reaver — a damned anti-hero who fights the horde to claim the souls
--    himself; crimson blade, hollow soul-lit eyes, tattered void shroud.
local reaver = {
    name = "Altar_Reaver",
    parts = {
        body   = { kind = "cube",   position = {  0.00, 0.56,  0.00 }, scale = { 0.46, 0.74, 0.32 }, color = C.grave_grey,  emissive = 0.5 },
        head   = { kind = "sphere", position = {  0.00, 1.07,  0.00 }, scale = { 0.38, 0.36, 0.38 }, color = C.void_black,  emissive = 0.4 },
        hand_r = { kind = "sphere", position = {  0.30, 0.65,  0.05 }, scale = { 0.15, 0.15, 0.15 }, color = C.grave_grey,  emissive = 0.5 },
        hand_l = { kind = "sphere", position = { -0.30, 0.65,  0.05 }, scale = { 0.15, 0.15, 0.15 }, color = C.grave_grey,  emissive = 0.5 },
        foot_r = { kind = "cube",   position = {  0.12, 0.05,  0.00 }, scale = { 0.18, 0.10, 0.22 }, color = C.void_black,  emissive = 0.35 },
        foot_l = { kind = "cube",   position = { -0.12, 0.05,  0.00 }, scale = { 0.18, 0.10, 0.22 }, color = C.void_black,  emissive = 0.35 },
        sword  = { kind = "cube",   position = {  0.34, 0.48,  0.10 }, scale = { 0.07, 0.66, 0.08 }, color = C.blood,       emissive = 1.8 },
        -- Hollow soul-fire eyes and a jagged crown of grave-iron.
        eyes   = { kind = "sphere",   position = { 0.00, 1.09,  0.18 }, scale = { 0.26, 0.10, 0.10 }, color = C.soul_bright, emissive = 2.2 },
        crown  = { kind = "cube",     position = { 0.00, 1.34,  0.00 }, scale = { 0.34, 0.16, 0.34 }, color = C.void_black,  emissive = 0.5 },
        shroud = { kind = "cube",     position = { 0.00, 0.74, -0.18 }, scale = { 0.50, 0.40, 0.06 }, color = C.deep_purple, emissive = 0.7 },
    },
}

Altar.hero_actors = { lightbringer = lightbringer, reaver = reaver }
Altar.hero_actor = lightbringer  -- default; mode.lua may swap to reaver via env

-- Resolve a hero rig by name (falls back to the default).
function Altar.pick_hero(name)
    return Altar.hero_actors[name or ""] or Altar.hero_actor
end

-- Soul-bolt projectile reused by the Soul Cultist — a hurtling soul orb that the
-- engine fires when the caster holds the line. Texture-ready (soul_bolt.png).
local function soul_bolt(color)
    return {
        kind = "orb", speed = 15.0, cooldown = 1.1, start_y = 0.82, target_y = 0.90,
        particle_size = 0.32, scale = { 0.20, 0.20, 0.46 }, color = color or C.soul_bright,
        emissive = 2.4, arc = 0.08, pulse = true, impact = false, gravity = -1.0,
        hit_radius = 0.7, flight_grace = 0.10,
        texture = Altar.tex.soul_bolt,
    }
end

Altar.archetypes = {
    -- Cheap, fast soul-mote chaff conjured straight from the altar's overflow.
    -- Flies (ignores terrain), pure volume. The swarm role.
    soul_wisp = {
        name = "Soul Wisp", threat_cost = 1, hp = 5, dps = 2.2, range = 0.5, speed = 2.6,
        color = C.deep_purple, head = C.soul_bright,
        body_scale = { 0.26, 0.26, 0.26 }, head_scale = { 0.18, 0.18, 0.18 },
        parts = 2, scale = 0.80, flies = true,
        extras = {
            { name = "Wisp_Core",  kind = "sphere",   position = { 0.0, 0.22, 0.0  }, scale = { 0.13, 0.13, 0.13 }, color = C.soul_bright, emissive = 2.4 },
            { name = "Wisp_Trail", kind = "cylinder", position = { 0.0, 0.22, 0.14 }, scale = { 0.06, 0.20, 0.06 }, color = C.rune_bright, emissive = 1.4 },
        },
    },

    -- Void Shade — a fast shadowy orbiter that catches a kiting hero. Flies,
    -- frail, with the hooded silhouette of the void_shade sprite.
    void_shade = {
        name = "Void Shade", threat_cost = 1, hp = 7, dps = 2.8, range = 0.55, speed = 3.2,
        color = C.void_black, head = C.void_black,
        body_scale = { 0.34, 0.40, 0.30 }, head_scale = { 0.26, 0.24, 0.26 },
        head_pos = { 0.0, 0.46, 0.0 },
        parts = 2, scale = 0.95, flies = true,
        texture = Altar.tex.void_shade,   -- shadowy silhouette skin (drop-in)
        extras = {
            -- A drawn-up hood that gives the shade its unmistakable peak.
            { name = "Shade_Hood",  kind = "cylinder", position = { 0.00, 0.58, 0.00 }, scale = { 0.22, 0.26, 0.22 }, color = C.deep_purple, emissive = 0.6 },
            -- Twin soul-eyes glaring from under the hood.
            { name = "Shade_EyeL",  kind = "sphere",   position = { -0.07, 0.46, 0.16 }, scale = { 0.06, 0.06, 0.04 }, color = C.soul_bright, emissive = 2.4 },
            { name = "Shade_EyeR",  kind = "sphere",   position = {  0.07, 0.46, 0.16 }, scale = { 0.06, 0.06, 0.04 }, color = C.soul_bright, emissive = 2.4 },
            -- A wispy tattered hem trailing behind.
            { name = "Shade_Hem",   kind = "cube",     position = {  0.00, 0.12, -0.10 }, scale = { 0.30, 0.20, 0.04 }, color = C.deep_purple, emissive = 0.5 },
        },
    },

    -- Soul Cultist — the ranged caster. Holds the line and lobs soul-bolts at
    -- the hero; the only archetype with a `projectile`. Will reposition for LOS.
    soul_cultist = {
        name = "Soul Cultist", threat_cost = 3, hp = 13, dps = 2.6, range = 6.5, speed = 1.05,
        color = C.deep_purple, head = C.bone, weapon = C.soul_bright,
        body_scale = { 0.40, 0.66, 0.32 }, head_scale = { 0.28, 0.28, 0.28 },
        weapon_pos = { 0.34, 0.58, 0.06 }, weapon_scale = { 0.06, 0.84, 0.06 },
        parts = 3, scale = 1.08, hold_range = 6.0, anchor_hold = true, needs_los = true, los_reposition_seconds = 2.0,
        projectile = soul_bolt(C.soul_bright),
        extras = {
            -- A hovering soul-orb above the staff hand — the "charged" tell.
            { name = "Cult_Orb",   kind = "sphere", position = {  0.34, 1.10, 0.06 }, scale = { 0.24, 0.24, 0.24 }, color = C.soul_bright, emissive = 2.2 },
            -- A deep cowl hiding the face, with a single rune-blue glow within.
            { name = "Cult_Cowl",  kind = "cube",   position = {  0.00, 0.92, 0.00 }, scale = { 0.40, 0.20, 0.34 }, color = C.void_black,  emissive = 0.4 },
            { name = "Cult_Eye",   kind = "sphere", position = {  0.00, 0.92, 0.18 }, scale = { 0.08, 0.08, 0.05 }, color = C.rune_bright, emissive = 2.0 },
            -- A sacrificial dagger at the belt.
            { name = "Cult_Dagger", kind = "cube",  position = { -0.30, 0.50, 0.08 }, scale = { 0.05, 0.30, 0.05 }, color = C.blood,       emissive = 1.4 },
        },
    },

    -- Revenant — the heavy orbiter; the wall the hero's cleave must chew through.
    -- Slow, high HP, an exhumed armoured corpse with a soul-furnace chest.
    revenant = {
        name = "Revenant", threat_cost = 4, hp = 40, dps = 7.5, range = 0.95, speed = 1.45,
        color = C.grave_grey, head = C.bone, weapon = C.blood,
        body_scale = { 0.62, 0.56, 0.48 }, head_pos = { 0.0, 0.82, -0.04 }, head_scale = { 0.32, 0.28, 0.32 },
        weapon_pos = { 0.44, 0.36, 0.04 }, weapon_scale = { 0.18, 0.40, 0.16 },
        parts = 3, scale = 1.45,
        extras = {
            -- Heavy grave-iron shoulders veined with soul-fire.
            { name = "Rev_Shoulder_L", kind = "sphere", position = { -0.42, 0.62, 0.0 }, scale = { 0.28, 0.22, 0.28 }, color = C.deep_purple, emissive = 1.0 },
            { name = "Rev_Shoulder_R", kind = "sphere", position = {  0.42, 0.62, 0.0 }, scale = { 0.28, 0.22, 0.28 }, color = C.deep_purple, emissive = 1.0 },
            -- An open soul-furnace in the ribcage (its bound soul, blazing).
            { name = "Rev_Furnace",    kind = "sphere", position = {  0.00, 0.54, -0.20 }, scale = { 0.26, 0.30, 0.10 }, color = C.soul_bright, emissive = 2.0 },
            -- A broken crown of horns.
            { name = "Rev_Horn_L",     kind = "cylinder", position = { -0.16, 1.02, 0.0 }, scale = { 0.08, 0.24, 0.08 }, color = C.bone,        emissive = 0.8 },
            { name = "Rev_Horn_R",     kind = "cylinder", position = {  0.16, 1.02, 0.0 }, scale = { 0.08, 0.24, 0.08 }, color = C.bone,        emissive = 0.8 },
        },
    },

    -- Dread Harbinger — the boss horror summoned when the ritual is far along.
    -- Towering, devastating; a crown of rune-spires and a field of soul-eyes
    -- announce its arrival across the chamber.
    dread_harbinger = {
        name = "Dread Harbinger", threat_cost = 6, hp = 74, dps = 9.5, range = 1.05, speed = 1.1,
        color = C.void_black, head = C.soul_purple, weapon = C.rune_blue,
        body_scale = { 0.72, 0.78, 0.56 }, head_pos = { 0.0, 1.02, -0.04 }, head_scale = { 0.36, 0.32, 0.36 },
        weapon_pos = { 0.46, 0.48, 0.06 }, weapon_scale = { 0.14, 0.74, 0.14 },
        parts = 3, scale = 1.92,
        extras = {
            -- A tiara of three rune-spires erupting from the crown.
            { name = "Harb_Spire_C", kind = "cylinder", position = {  0.00, 1.38, 0.0  }, scale = { 0.10, 0.38, 0.10 }, color = C.soul_bright, emissive = 2.2 },
            { name = "Harb_Spire_L", kind = "cylinder", position = { -0.22, 1.26, 0.0  }, scale = { 0.08, 0.26, 0.08 }, color = C.rune_bright, emissive = 1.8 },
            { name = "Harb_Spire_R", kind = "cylinder", position = {  0.22, 1.26, 0.0  }, scale = { 0.08, 0.26, 0.08 }, color = C.rune_bright, emissive = 1.8 },
            -- A trio of soul-eyes across the torso (the horror's true face).
            { name = "Harb_Eye_L",   kind = "sphere",   position = { -0.26, 0.68, -0.26 }, scale = { 0.18, 0.18, 0.10 }, color = C.soul_bright, emissive = 2.4 },
            { name = "Harb_Eye_C",   kind = "sphere",   position = {  0.00, 0.76, -0.28 }, scale = { 0.20, 0.20, 0.10 }, color = C.blood,       emissive = 2.4 },
            { name = "Harb_Eye_R",   kind = "sphere",   position = {  0.26, 0.68, -0.26 }, scale = { 0.18, 0.18, 0.10 }, color = C.soul_bright, emissive = 2.4 },
            -- A broad collar of bound souls at the neck.
            { name = "Harb_Collar",  kind = "cylinder", position = {  0.00, 0.88, 0.0  }, scale = { 0.58, 0.08, 0.58 }, color = C.rune_blue,   emissive = 1.4 },
        },
    },
}

Altar.roles = {
    swarm  = "soul_wisp",
    ranged = "soul_cultist",
    elite  = "revenant",
    brute  = "dread_harbinger",
}

return Altar
