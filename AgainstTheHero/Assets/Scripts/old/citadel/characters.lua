-- Bone Citadel — the cast.
--
-- Pure DATA. Every creature is a horde/creep.lua-compatible archetype, plus two
-- ATH extensions the shared Duel honours:
--   * extras  = a list of decorative ath_art PART specs welded on after build
--               (the creature's signature silhouette — no code, just data).
--   * texture = an optional "Textures/foo.png" painted onto the body. The
--               companion tools/gen_textures_citadel.py writes real PNGs into
--               Assets/Textures/modes/citadel/, referenced here as
--               "Textures/modes/citadel/<name>.png" (asset root = Assets/).
--
-- Theme: a crumbling dark-souls citadel — a dying empire's last bastion, moss
-- creeping over ancient bone-grey stone, oil-fire flickering on the battlements.
-- Everything is self-lit (emissive) — scene lighting barely reaches the built
-- stage, so colours double as the light source.
--
-- The HEADLINE defenders the design calls for are here:
--   * battlement_archer — ranged bowman on the wall.
--   * oil_cauldron      — the deployable cousin of the wall's oil-pour TRAP
--                         (the trap itself is the mode's signature mechanic in
--                         mode.lua; this is the unit you can summon to lob it).
--   * undead_swordsman  — the gate defender that holds the breach.
-- Two more (bone_rabble swarm, barrow_hound chaser, marrow_colossus brute) round
-- the cast to the five role-slots the shared 50-card deck expects.
--
-- HEROES: two siege rigs are provided. Bone Citadel defaults to the SIEGE KNIGHT
-- (battering-ram specialist); swap config.hero.actor to Cit.hero_actor_mage in
-- mode.lua for the SIEGE MAGE (catapult + spell). Both keep the part keys
-- body/head/hand_r/hand_l/foot_r/foot_l/sword so ath_art's walk/attack clips play.

local Cit = {}

-- ---- Shared palette (the brief's colours) ----------------------------------
-- #1c1c1c stone black, #3a3a3a mortar grey, #5c5c5c highlight, #8b4513 wood
-- siege, #ff6600 fire oil, #cc0000 blood — plus moss/bone/rust to sell "ancient".
local C = {
    stone   = { 0.11, 0.11, 0.11 },   -- #1c1c1c stone black
    mortar  = { 0.23, 0.23, 0.23 },   -- #3a3a3a mortar grey
    highlight = { 0.36, 0.36, 0.36 }, -- #5c5c5c worn highlight
    wood    = { 0.55, 0.27, 0.08 },   -- #8b4513 siege timber
    oil     = { 1.00, 0.40, 0.00 },   -- #ff6600 boiling oil-fire
    blood   = { 0.80, 0.00, 0.00 },   -- #cc0000 blood
    moss    = { 0.30, 0.42, 0.22 },   -- creeping moss over old stone
    bone    = { 0.86, 0.84, 0.74 },   -- bleached bone-white
    rust    = { 0.45, 0.30, 0.18 },   -- rusted iron fittings
    ember   = { 1.00, 0.62, 0.22 },   -- guttering brazier ember
}
Cit.palette = C

Cit.theme = {
    accent      = { 0.80, 0.40, 0.12, 0.95 },   -- oil-fire orange
    floor       = { 0.12, 0.12, 0.13 },          -- mud-churned siege ground
    floor_texture = nil,  -- drop in "Textures/modes/citadel/stone_wall.png" when wired
    wall        = { 0.20, 0.20, 0.21 },          -- arena perimeter (the citadel's outer ring)
    spawn_sigil = { 0.80, 0.00, 0.00 },          -- gate-mouths the dead pour from
    aura        = { 0.80, 0.40, 0.12, 0.45 },
    hero_body   = { 0.24, 0.22, 0.20 },
    hero_trim   = { 0.86, 0.84, 0.74 },
    hud_title   = "BONE CITADEL",
    win_text    = "The wall is breached — the citadel falls to ruin.\nPress R to run it back  •  M for menu",
    lose_text   = "The hero is broken against the ancient stone.\nPress R to run it back  •  M for menu",
}

-- ---- Hero rigs --------------------------------------------------------------

-- SIEGE KNIGHT — battering-ram specialist. Heavy bone-plate, a ram-headed maul
-- for a "sword" so the attack clip swings the ram-head, a tower-shield on the
-- off hand, and a battered helm crest. This is the default hero.
Cit.hero_actor_knight = {
    name = "Citadel_Knight",
    scale = 1.05,
    parts = {
        body   = { kind = "cube",   position = { 0.0,  0.58,  0.0  }, scale = { 0.54, 0.78, 0.40 }, color = C.mortar,    emissive = 0.55,
                   -- texture = "Textures/modes/citadel/hero_knight.png",
                 },
        head   = { kind = "cube",   position = { 0.0,  1.12,  0.0  }, scale = { 0.36, 0.34, 0.36 }, color = C.highlight, emissive = 0.55 },
        hand_r = { kind = "sphere", position = { 0.36, 0.66,  0.06 }, scale = { 0.17, 0.17, 0.17 }, color = C.rust,      emissive = 0.55 },
        hand_l = { kind = "sphere", position = {-0.36, 0.66,  0.06 }, scale = { 0.17, 0.17, 0.17 }, color = C.rust,      emissive = 0.55 },
        foot_r = { kind = "cube",   position = { 0.15, 0.05,  0.0  }, scale = { 0.20, 0.12, 0.26 }, color = C.stone,     emissive = 0.35 },
        foot_l = { kind = "cube",   position = {-0.15, 0.05,  0.0  }, scale = { 0.20, 0.12, 0.26 }, color = C.stone,     emissive = 0.35 },
        -- The "sword" is the ram-headed maul (the attack clip rocks it like a swing).
        sword  = { kind = "cube",   position = { 0.40, 0.50,  0.12 }, scale = { 0.12, 0.70, 0.12 }, color = C.wood,      emissive = 0.9 },
        -- Flavour extras that ride the root.
        ram_head   = { kind = "cylinder", position = { 0.40, 0.92, 0.12 }, scale = { 0.22, 0.18, 0.22 }, color = C.rust,    emissive = 1.0 },
        shield     = { kind = "cube",     position = {-0.42, 0.62, 0.10 }, scale = { 0.10, 0.52, 0.40 }, color = C.bone,    emissive = 0.7 },
        helm_crest = { kind = "cube",     position = { 0.0,  1.36, 0.0  }, scale = { 0.08, 0.20, 0.30 }, color = C.blood,   emissive = 1.0 },
        pauldron_r = { kind = "sphere",   position = { 0.34, 0.86, 0.0  }, scale = { 0.22, 0.16, 0.22 }, color = C.stone,   emissive = 0.6 },
        pauldron_l = { kind = "sphere",   position = {-0.34, 0.86, 0.0  }, scale = { 0.22, 0.16, 0.22 }, color = C.stone,   emissive = 0.6 },
    },
}

-- SIEGE MAGE — catapult + spell specialist. Robed, hooded, a long staff for a
-- "sword", a crackling spell-orb at the staff head and a sigil at the chest.
-- Lighter plate, a frailer silhouette than the knight. (Alternate hero.)
Cit.hero_actor_mage = {
    name = "Citadel_Mage",
    scale = 1.0,
    parts = {
        body   = { kind = "cube",   position = { 0.0,  0.56,  0.0  }, scale = { 0.46, 0.80, 0.34 }, color = C.stone,    emissive = 0.55 },
        head   = { kind = "sphere", position = { 0.0,  1.12,  0.0  }, scale = { 0.32, 0.32, 0.32 }, color = C.bone,     emissive = 0.5  },
        hand_r = { kind = "sphere", position = { 0.34, 0.66,  0.06 }, scale = { 0.14, 0.14, 0.14 }, color = C.bone,     emissive = 0.5  },
        hand_l = { kind = "sphere", position = {-0.34, 0.66,  0.06 }, scale = { 0.14, 0.14, 0.14 }, color = C.bone,     emissive = 0.5  },
        foot_r = { kind = "cube",   position = { 0.13, 0.05,  0.0  }, scale = { 0.18, 0.10, 0.22 }, color = C.stone,    emissive = 0.35 },
        foot_l = { kind = "cube",   position = {-0.13, 0.05,  0.0  }, scale = { 0.18, 0.10, 0.22 }, color = C.stone,    emissive = 0.35 },
        sword  = { kind = "cube",   position = { 0.36, 0.56,  0.10 }, scale = { 0.06, 0.92, 0.06 }, color = C.wood,     emissive = 0.9  },
        -- Flavour extras.
        spell_orb = { kind = "sphere", position = { 0.36, 1.10, 0.10 }, scale = { 0.20, 0.20, 0.20 }, color = C.oil,    emissive = 2.0 },
        hood      = { kind = "cube",   position = { 0.0,  1.24, -0.04}, scale = { 0.34, 0.20, 0.34 }, color = C.stone,  emissive = 0.4 },
        chest_sig = { kind = "sphere", position = { 0.0,  0.66, -0.18}, scale = { 0.16, 0.16, 0.06 }, color = C.oil,    emissive = 1.6 },
    },
}

-- The default hero the mode launches with (the battering-ram knight).
Cit.hero_actor = Cit.hero_actor_knight

-- ---- Projectile helpers -----------------------------------------------------

-- A loosed arrow — thin, fast, bone-fletched, near-flat trajectory.
local function arrow()
    return {
        kind = "orb", speed = 20.0, cooldown = 1.2, start_y = 1.0, target_y = 0.85,
        particle_size = 0.16, scale = { 0.08, 0.08, 0.52 }, color = C.bone,
        emissive = 1.4, arc = 0.05, pulse = false, impact = false, gravity = -1.0,
        hit_radius = 0.6, flight_grace = 0.10,
    }
end

-- A lobbed glob of boiling oil — slow, heavy, high arc, fire-orange.
local function oil_glob()
    return {
        kind = "orb", speed = 11.0, cooldown = 2.0, start_y = 1.2, target_y = 0.6,
        particle_size = 0.34, scale = { 0.24, 0.24, 0.24 }, color = C.oil,
        emissive = 2.2, arc = 0.30, pulse = true, impact = true, gravity = -4.0,
        hit_radius = 0.85, flight_grace = 0.12,
    }
end

-- ---- Archetypes (the wall's defenders) -------------------------------------

Cit.archetypes = {
    -- BONE RABBLE — cheap skeleton chaff that spills from the gate-mouths in
    -- numbers. The role=swarm filler. Lurching, mismatched limbs.
    bone_rabble = {
        name = "Bone Rabble", threat_cost = 1, hp = 7, dps = 2.6, range = 0.6, speed = 2.6,
        color = C.bone, head = C.highlight,
        body_scale = { 0.30, 0.42, 0.26 }, head_scale = { 0.24, 0.22, 0.24 },
        parts = 2, scale = 0.92,
        -- texture = "Textures/modes/citadel/archer.png",  -- shares the undead sheet
        extras = {
            { name = "Rabble_Ribs", kind = "cube",   position = { 0.0, 0.46, 0.14 }, scale = { 0.24, 0.10, 0.04 }, color = C.bone,  emissive = 0.9 },
            { name = "Rabble_Jaw",  kind = "cube",   position = { 0.0, 0.78, 0.10 }, scale = { 0.14, 0.06, 0.10 }, color = C.bone,  emissive = 0.8 },
        },
    },

    -- BARROW HOUND — an undead war-hound, faster than baseline and frail; the
    -- thing that runs a kiting hero down between the siege engines. (role: chaser)
    barrow_hound = {
        name = "Barrow Hound", threat_cost = 1, hp = 5, dps = 2.2, range = 0.5, speed = 3.5,
        color = C.stone, head = C.bone,
        body_scale = { 0.48, 0.24, 0.34 }, head_pos = { 0.0, 0.40, 0.20 }, head_scale = { 0.22, 0.20, 0.26 },
        parts = 2, scale = 0.88,
        extras = {
            { name = "Hound_Spine", kind = "cube",   position = { 0.0, 0.44, -0.04 }, scale = { 0.06, 0.16, 0.34 }, color = C.bone,  emissive = 1.0 },
            { name = "Hound_Eye",   kind = "sphere", position = { 0.0, 0.42,  0.30 }, scale = { 0.08, 0.06, 0.06 }, color = C.blood, emissive = 1.6 },
        },
    },

    -- BATTLEMENT ARCHER — the wall's bowman. Holds the line behind the swordsmen
    -- and rains arrows; needs line of sight, repositions if blocked. (role: ranged)
    battlement_archer = {
        name = "Battlement Archer", threat_cost = 3, hp = 13, dps = 2.6, range = 7.0, speed = 1.2,
        color = C.mortar, head = C.bone, weapon = C.wood,
        body_scale = { 0.38, 0.64, 0.30 }, head_scale = { 0.28, 0.28, 0.28 },
        weapon_pos = { 0.34, 0.66, 0.10 }, weapon_scale = { 0.06, 0.78, 0.06 },
        parts = 3, scale = 1.05, hold_range = 6.0, anchor_hold = true, needs_los = true, los_reposition_seconds = 2.0,
        projectile = arrow(),
        -- texture = "Textures/modes/citadel/archer.png",
        extras = {
            { name = "Archer_Bow",   kind = "cylinder", position = { 0.36, 0.78, 0.12 }, scale = { 0.05, 0.62, 0.05 }, color = C.wood,  emissive = 0.9, rotation = { 0.0, 0.0, 18.0 } },
            { name = "Archer_Quiver",kind = "cube",     position = {-0.20, 0.84, -0.12}, scale = { 0.10, 0.30, 0.10 }, color = C.rust,  emissive = 0.7 },
            { name = "Archer_Hood",  kind = "cube",     position = { 0.0,  0.98, -0.02}, scale = { 0.30, 0.16, 0.30 }, color = C.stone, emissive = 0.4 },
        },
    },

    -- OIL CAULDRON — the deployable cousin of the wall's oil-pour trap. A slow,
    -- iron-bellied brazier-bearer that lobs guttering oil at the hero. The MOBILE
    -- counterpart to the static oil hazard the mode pours from the battlements.
    oil_cauldron = {
        name = "Oil Cauldron", threat_cost = 4, hp = 22, dps = 3.2, range = 6.0, speed = 0.7,
        color = C.rust, head = C.stone, weapon = C.oil,
        body_scale = { 0.56, 0.50, 0.54 }, head_pos = { 0.0, 0.78, -0.04 }, head_scale = { 0.34, 0.22, 0.34 },
        weapon_pos = { 0.0, 0.74, 0.0 }, weapon_scale = { 0.40, 0.18, 0.40 },
        parts = 3, scale = 1.25, hold_range = 5.0, anchor_hold = true, needs_los = true, los_reposition_seconds = 3.0,
        projectile = oil_glob(),
        -- texture = "Textures/modes/citadel/cauldron.png",
        extras = {
            { name = "Cauldron_Pot",  kind = "cylinder", position = { 0.0,  0.86, 0.0 }, scale = { 0.46, 0.26, 0.46 }, color = C.stone, emissive = 0.6 },
            { name = "Cauldron_Fire", kind = "sphere",   position = { 0.0,  1.02, 0.0 }, scale = { 0.34, 0.20, 0.34 }, color = C.oil,   emissive = 2.2 },
            { name = "Cauldron_Foot", kind = "cylinder", position = { 0.0,  0.10, 0.0 }, scale = { 0.50, 0.16, 0.50 }, color = C.rust,  emissive = 0.5 },
        },
    },

    -- UNDEAD SWORDSMAN — the gate defender. Tanky, armoured in rusted plate, the
    -- wall the hero's cleave must chew through to reach a breach. (role: elite)
    undead_swordsman = {
        name = "Undead Swordsman", threat_cost = 4, hp = 36, dps = 7.0, range = 1.0, speed = 1.6,
        color = C.highlight, head = C.bone, weapon = C.bone,
        body_scale = { 0.60, 0.58, 0.46 }, head_pos = { 0.0, 0.84, -0.04 }, head_scale = { 0.32, 0.30, 0.32 },
        weapon_pos = { 0.46, 0.42, 0.06 }, weapon_scale = { 0.08, 0.66, 0.10 },
        parts = 3, scale = 1.38,
        extras = {
            { name = "Sword_Shield",  kind = "cube",   position = {-0.42, 0.56, 0.08 }, scale = { 0.10, 0.50, 0.40 }, color = C.rust,  emissive = 0.7 },
            { name = "Sword_Pauldron",kind = "sphere", position = { 0.40, 0.82, 0.0  }, scale = { 0.24, 0.18, 0.24 }, color = C.stone, emissive = 0.6 },
            { name = "Sword_Ribcage", kind = "cube",   position = { 0.0,  0.56, 0.22 }, scale = { 0.34, 0.30, 0.04 }, color = C.bone,  emissive = 0.9 },
        },
    },

    -- MARROW COLOSSUS — a towering bone-giant the citadel rouses late: massive,
    -- slow, devastating. The last-stand boss. (role: brute)
    marrow_colossus = {
        name = "Marrow Colossus", threat_cost = 6, hp = 70, dps = 9.5, range = 1.1, speed = 1.1,
        color = C.stone, head = C.bone, weapon = C.rust,
        body_scale = { 0.78, 0.80, 0.62 }, head_pos = { 0.0, 1.08, -0.04 }, head_scale = { 0.42, 0.38, 0.42 },
        weapon_pos = { 0.52, 0.52, 0.06 }, weapon_scale = { 0.18, 0.80, 0.18 },
        parts = 3, scale = 1.95,
        extras = {
            { name = "Colossus_Crown",  kind = "cylinder", position = { 0.0,  1.42, 0.0 }, scale = { 0.50, 0.14, 0.50 }, color = C.bone,  emissive = 1.4 },
            { name = "Colossus_Eye",    kind = "sphere",   position = { 0.0,  1.10, 0.30}, scale = { 0.12, 0.12, 0.08 }, color = C.blood, emissive = 2.2 },
            { name = "Colossus_RibsL",  kind = "cube",     position = {-0.30, 0.66, 0.30}, scale = { 0.10, 0.40, 0.04 }, color = C.bone,  emissive = 1.0 },
            { name = "Colossus_RibsR",  kind = "cube",     position = { 0.30, 0.66, 0.30}, scale = { 0.10, 0.40, 0.04 }, color = C.bone,  emissive = 1.0 },
            { name = "Colossus_Moss",   kind = "cube",     position = { 0.0,  0.50,-0.30}, scale = { 0.40, 0.40, 0.04 }, color = C.moss,  emissive = 0.6 },
        },
    },
}

-- Map the four level-agnostic card/spawn roles to this cast so the shared
-- 50-card deck works here unchanged. (barrow_hound + oil_cauldron ride the
-- auto_mix in mode.lua for variety.)
Cit.roles = {
    swarm  = "bone_rabble",
    ranged = "battlement_archer",
    elite  = "undead_swordsman",
    brute  = "marrow_colossus",
}

return Cit
