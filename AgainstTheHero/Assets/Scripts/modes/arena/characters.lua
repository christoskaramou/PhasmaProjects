-- Arena farm cast (DATA only).
--
-- A bright, sunlit chunky-cartoon farm arena. Every creature here is a FLAT 2D
-- SPRITE: a horde/creep.lua archetype carrying the ATH `sprite = true` flag, which
-- tells the shared Duel to paint its texture through the emissive slot (alpha-cut)
-- and billboard the thin body slab at the iso camera each frame.
-- If a PNG is missing the creature still draws as its flat `color` silhouette.
--
-- Roles map the four level-agnostic card/spawn roles onto this cast so the shared
-- 50-card deck works here unchanged; the crow flier is sprinkled in via auto_mix.
--
-- Aesthetic: chunky cartoon, bold black outlines, vibrant saturated fills,
-- sunny daytime palette. Goofy-cute garden critters versus one heroic spud.

local Visuals = ATH_COMMON.visuals(_ENV)
local V = Visuals.data
local Spud = {}

-- ---- Palette (0..1) — sunny farmland --------------------------------------
local C = {
    grass      = { 0.42, 0.70, 0.27 },
    grass_dk   = { 0.30, 0.54, 0.20 },
    soil       = { 0.42, 0.28, 0.17 },
    soil_dk    = { 0.28, 0.18, 0.10 },
    sky        = { 0.50, 0.78, 0.95 },
    sprout     = { 0.55, 0.82, 0.32 },
    sun        = { 0.98, 0.84, 0.28 },
    carrot     = { 0.96, 0.52, 0.16 },
    pumpkin    = { 0.96, 0.55, 0.12 },
    husk       = { 0.86, 0.74, 0.36 },
    crow       = { 0.16, 0.16, 0.20 },
    spud       = { 0.84, 0.66, 0.40 },
    leaf       = { 0.36, 0.66, 0.24 },
}
Spud.palette = C

local function creep_sheet(id)
    return assert(V.enemies[id], "missing visual enemy: " .. id).sheet
end
Spud.tex = {
    floor = V.maps.spud_fields,
    sprout = V.enemies.sprout.texture,
    spitter = V.enemies.seed_spitter.texture,
    husk = V.enemies.husk_knight.texture,
    pumpkin = V.enemies.pumpkin_brute.texture,
    crow = V.enemies.crow.texture,
    beetle = V.enemies.beetle.texture,
    corn = V.enemies.corn_mortar.texture,
    wasp = V.enemies.wasp.texture,
}

Spud.theme = {
    accent        = { 0.46, 0.78, 0.24, 0.95 },
    floor         = { 0.40, 0.66, 0.28 },         -- tint under the grass texture
    floor_texture = Spud.tex.floor,
    wall          = { 0.40, 0.27, 0.16 },          -- wooden field fence / soil berm
    spawn_sigil   = { 0.96, 0.84, 0.28 },          -- sunny spawn rings
    aura          = { 0.42, 0.82, 0.95, 0.5 },
}

-- ---- The cast — upright humanoid garden horrors -----------------------------
-- Common shape for a standing sprite: a thin body slab (depth ~0.05), the head
-- sphere hidden (scale ~0), and body_pos raised so the sprite stands on the soil.
Spud.archetypes = {
    -- SPROUT — the swarm. A tiny plant scout that legs it at the hero.
    sprout = {
        name = "Sprout", threat_cost = 1, hp = 6, dps = 2.2, range = 0.5, speed = 2.7,
        color = C.sprout, head = C.sprout,
        sprite = true, texture = Spud.tex.sprout, sprite_sheet = creep_sheet("sprout"),
        parts = 2, scale = 0.85,
        body_pos = { 0.0, 0.60, 0.0 }, body_scale = { 0.92, 1.06, 0.05 },
        head_scale = { 0.001, 0.001, 0.001 },
    },
    -- SEED SPITTER — the ranged anchor. A sunflower-headed stalk that holds the
    -- line and pelts seeds (modelled as a stand-off damage range in the Duel).
    seed_spitter = {
        name = "Seed Spitter", threat_cost = 3, hp = 13, dps = 2.6, range = 6.0, speed = 1.1,
        color = C.sun, head = C.sun,
        sprite = true, texture = Spud.tex.spitter, sprite_sheet = creep_sheet("seed_spitter"),
        parts = 2, scale = 1.05,
        body_pos = { 0.0, 0.70, 0.0 }, body_scale = { 1.00, 1.22, 0.05 },
        head_scale = { 0.001, 0.001, 0.001 },
        hold_range = 6.0, anchor_hold = true, needs_los = true, los_reposition_seconds = 2.0,
    },
    -- HUSK KNIGHT — the elite wall-in-miniature. Cornhusk-armoured, medium HP.
    husk_knight = {
        name = "Husk Knight", threat_cost = 4, hp = 34, dps = 6.5, range = 0.95, speed = 1.5,
        color = C.husk, head = C.husk,
        sprite = true, texture = Spud.tex.husk, sprite_sheet = creep_sheet("husk_knight"),
        parts = 2, scale = 1.20,
        body_pos = { 0.0, 0.78, 0.0 }, body_scale = { 1.04, 1.30, 0.05 },
        head_scale = { 0.001, 0.001, 0.001 },
    },
    -- PUMPKIN BRUTE — the brute. A huge pumpkin-headed enforcer that crushes.
    pumpkin_brute = {
        name = "Pumpkin Brute", threat_cost = 6, hp = 74, dps = 9.0, range = 1.05, speed = 1.0,
        color = C.pumpkin, head = C.pumpkin,
        sprite = true, texture = Spud.tex.pumpkin, sprite_sheet = creep_sheet("pumpkin_brute"),
        parts = 2, scale = 1.60,
        body_pos = { 0.0, 0.74, 0.0 }, body_scale = { 1.10, 1.28, 0.05 },
        head_scale = { 0.001, 0.001, 0.001 },
    },
    -- CROW — the flier. A black scarecrow-crow that ignores terrain and dives.
    crow = {
        name = "Crow", threat_cost = 2, hp = 8, dps = 3.0, range = 0.55, speed = 3.3,
        color = C.crow, head = C.crow,
        sprite = true, texture = Spud.tex.crow, sprite_sheet = creep_sheet("crow"), flies = true,
        parts = 2, scale = 0.95,
        body_pos = { 0.0, 1.05, 0.0 }, body_scale = { 0.90, 1.16, 0.05 },
        head_scale = { 0.001, 0.001, 0.001 },
    },
    -- BEETLE — armored swarm tank. Slower, chunkier, shrugs off knockback. A
    -- step up in toughness from the sprout without the elite husk's wall of HP.
    beetle = {
        name = "Spud Beetle", threat_cost = 2, hp = 20, dps = 3.2, range = 0.6, speed = 2.1,
        color = C.carrot, head = C.carrot,
        sprite = true, texture = Spud.tex.beetle, sprite_sheet = creep_sheet("beetle"),
        parts = 2, scale = 1.05,
        body_pos = { 0.0, 0.66, 0.0 }, body_scale = { 0.96, 1.16, 0.05 },
        head_scale = { 0.001, 0.001, 0.001 },
        knockback_resist = 0.4,
    },
    -- CORN MORTAR — long-range heavy lobber. Holds WAY back and flings a big slow
    -- cob the hero must read and sidestep; low HP, so closing the gap kills it.
    corn_mortar = {
        name = "Corn Mortar", threat_cost = 3, hp = 12, dps = 3.0, range = 7.5, speed = 1.0,
        color = C.sun, head = C.sun,
        sprite = true, texture = Spud.tex.corn, sprite_sheet = creep_sheet("corn_mortar"),
        parts = 2, scale = 1.1,
        body_pos = { 0.0, 0.80, 0.0 }, body_scale = { 0.86, 1.29, 0.05 },
        head_scale = { 0.001, 0.001, 0.001 },
        hold_range = 7.5, anchor_hold = true, needs_los = true, los_reposition_seconds = 2.0,
        projectile = {
            kind = "cob", speed = 9.0, cooldown = 1.9,
            start_y = 0.9, target_y = 0.55,
            scale = { 0.30, 0.30, 0.30 }, particle_size = 0.30,
            color = { 0.98, 0.80, 0.32 }, emissive = 1.1,
            hit_radius = 0.9, gravity = 0.0,
        },
    },
    -- GARDEN WASP — fast ranged flier. Darts in, holds at mid range, and pelts
    -- quick stingers; ignores terrain. Glass cannon on the wing.
    wasp = {
        name = "Garden Wasp", threat_cost = 2, hp = 7, dps = 2.4, range = 5.0, speed = 4.2,
        color = C.sun, head = C.crow,
        sprite = true, texture = Spud.tex.wasp, sprite_sheet = creep_sheet("wasp"), flies = true,
        parts = 2, scale = 0.95,
        body_pos = { 0.0, 1.05, 0.0 }, body_scale = { 0.96, 1.20, 0.05 },
        head_scale = { 0.001, 0.001, 0.001 },
        hold_range = 5.0, anchor_hold = true, needs_los = true, los_reposition_seconds = 1.5,
        projectile = {
            kind = "sting", speed = 18.0, cooldown = 0.9,
            start_y = 1.0, target_y = 0.6,
            scale = { 0.12, 0.12, 0.12 }, particle_size = 0.14,
            color = { 0.95, 0.86, 0.30 }, emissive = 1.2,
            hit_radius = 0.55, gravity = 0.0,
        },
    },
}

Spud.roles = {
    swarm  = "sprout",
    ranged = "seed_spitter",
    elite  = "husk_knight",
    brute  = "pumpkin_brute",
}

return Spud
