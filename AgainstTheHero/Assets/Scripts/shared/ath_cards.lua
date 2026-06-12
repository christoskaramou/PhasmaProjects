-- ath_cards — the unified 50-card collection for Against The Hero.
--
-- ONE catalog, shared by every mode. Each card is DUAL-FACED:
--   * FRONT face = what it does when the HERO plays it (a persistent self-upgrade)
--   * BACK  face = what it does when the HORDE plays it (swarm buff, hero debuff,
--                  a reserve-spend spawn, spawn-cadence escalation, or ammo).
-- The seat playing the card decides which face fires; the two faces of a card are
-- designed to COUNTER each other so the option sets stay balanced regardless of
-- which side you picked in the menu.
--
-- This module is DATA + deck/hand/command bookkeeping ONLY. It never touches the
-- world: faces are plain effect tables and the duel engine (ath_duel.lua)
-- interprets them. That mirrors rush/cards.lua and keeps the card layer testable
-- and level-agnostic.
--
-- LEVEL-AGNOSTIC SPAWNS: a back "spawn" face names a ROLE ("swarm"/"ranged"/
-- "elite"/"brute"), not a specific creature. Each mode maps the four roles to its
-- own characters (config.roles), so the same 50 cards work in every level.
--
-- The menu lets the player keep DECK_SIZE (20) of these 50; that chosen list is
-- handed to Cards.create as opts.deck. The AI opponent uses Cards.default_deck.

local Cards = {}

Cards.DECK_SIZE = 20 -- cards the player keeps from the 50 in the menu
Cards.HAND_SIZE = 5
Cards.HERO_COMMAND = 3
Cards.HORDE_COMMAND = 3

-- Rarity is display metadata (stars + colour). It does not gate play.
local RARITY = {
    common = { stars = 1, color = { 0.78, 0.80, 0.86, 1.0 } },
    uncommon = { stars = 2, color = { 0.40, 0.80, 0.50, 1.0 } },
    rare = { stars = 3, color = { 0.40, 0.62, 0.95, 1.0 } },
    epic = { stars = 4, color = { 0.70, 0.46, 0.92, 1.0 } },
    legendary = { stars = 5, color = { 0.96, 0.74, 0.30, 1.0 } },
}
Cards.RARITY = RARITY

-- Effect-field reference (interpreted by ath_duel.lua):
--   FRONT (kind = "hero"): dps_mult, dps_add, cleave_add, attack_range_add,
--     speed_mult, kite_speed_mult, hp_max_add, heal, lifesteal_add, regen_add,
--     whirl_add, armor_add, thorns_add, dash_add.
--   BACK kinds:
--     "swarm"    -> speed_add, dps_add, hp_add (baked into future + current spawns)
--     "weaken"   -> dps_mult, speed_mult, kite_speed_mult, attack_range_add (hero)
--     "spawn"    -> role, count, reserve_cost (immediate reserve-spend surge)
--     "escalate" -> batch_add, cap_add, interval_mult (persistent cadence change)
--     "reserve"  -> reserve_add (refill the horde's ammo bar)
Cards.catalog = {
    -- ----- Offense: sharpen the hero / harden or arm the swarm -----------
    honed_edge = { name = "Honed Edge", rarity = "common", cost = 1,
        front = { kind = "hero", dps_mult = 1.25 }, front_text = "+25% hero damage",
        back = { kind = "swarm", dps_add = 0.8 }, back_text = "swarm bites +0.8 harder" },
    keen_point = { name = "Keen Point", rarity = "common", cost = 1,
        front = { kind = "hero", dps_add = 4.0 }, front_text = "+4 flat hero damage",
        back = { kind = "swarm", dps_add = 0.6 }, back_text = "swarm bites +0.6 harder" },
    savage_blow = { name = "Savage Blow", rarity = "uncommon", cost = 2,
        front = { kind = "hero", dps_mult = 1.4 }, front_text = "+40% hero damage",
        back = { kind = "swarm", dps_add = 1.4 }, back_text = "swarm bites +1.4 harder" },
    executioner = { name = "Executioner", rarity = "rare", cost = 2,
        front = { kind = "hero", dps_mult = 1.3, cleave_add = 1 }, front_text = "+30% damage, +1 cleave",
        back = { kind = "weaken", hp_max_mult = 1.0, dps_mult = 0.9 }, back_text = "hero deals -10% damage" },
    rending_strikes = { name = "Rending Strikes", rarity = "uncommon", cost = 2,
        front = { kind = "hero", dps_add = 6.0, attack_range_add = 0.15 }, front_text = "+6 damage, slight reach",
        back = { kind = "swarm", dps_add = 1.0, hp_add = 2.0 }, back_text = "swarm +1 dmg, +2 HP" },
    bloodthirst = { name = "Bloodthirst", rarity = "rare", cost = 2,
        front = { kind = "hero", lifesteal_add = 2.0 }, front_text = "heal 2 per kill",
        back = { kind = "weaken", dps_mult = 0.85 }, back_text = "hero deals -15% damage" },
    crimson_feast = { name = "Crimson Feast", rarity = "epic", cost = 3,
        front = { kind = "hero", lifesteal_add = 3.0, dps_mult = 1.15 }, front_text = "heal 3/kill, +15% dmg",
        back = { kind = "swarm", hp_add = 6.0, dps_add = 1.0 }, back_text = "swarm +6 HP, +1 dmg" },
    berserk = { name = "Berserk", rarity = "rare", cost = 2,
        front = { kind = "hero", dps_mult = 1.5, armor_add = -0.05 }, front_text = "+50% damage, slight fragility",
        back = { kind = "escalate", interval_mult = 0.85 }, back_text = "spawns 15% more often" },
    giant_slayer = { name = "Giant Slayer", rarity = "epic", cost = 3,
        front = { kind = "hero", dps_mult = 1.25, cleave_add = 1, attack_range_add = 0.2 }, front_text = "+25% dmg, +1 cleave, reach",
        back = { kind = "spawn", role = "brute", count = 1, reserve_cost = 9 }, back_text = "summon a brute now" },
    duelists_focus = { name = "Duelist's Focus", rarity = "uncommon", cost = 2,
        front = { kind = "hero", dps_mult = 1.2, crit_add = 0.1 }, front_text = "+20% damage, sharper edge",
        back = { kind = "swarm", speed_add = 0.2, dps_add = 0.6 }, back_text = "swarm faster + meaner" },
    overpower = { name = "Overpower", rarity = "legendary", cost = 3,
        front = { kind = "hero", dps_mult = 1.6, cleave_add = 2 }, front_text = "+60% damage, +2 cleave",
        back = { kind = "spawn", role = "elite", count = 3, reserve_cost = 12 }, back_text = "surge: 3 elites now" },

    -- ----- Defense: keep the hero alive / outlast the hero --------------
    vigor = { name = "Vigor", rarity = "common", cost = 1,
        front = { kind = "hero", hp_max_add = 30.0, heal = 30.0 }, front_text = "+30 max HP and heal",
        back = { kind = "swarm", hp_add = 4.0 }, back_text = "swarm gains +4 HP" },
    iron_skin = { name = "Iron Skin", rarity = "uncommon", cost = 2,
        front = { kind = "hero", hp_max_add = 45.0, heal = 20.0 }, front_text = "+45 max HP",
        back = { kind = "swarm", hp_add = 7.0, speed_add = -0.1 }, back_text = "swarm gains +7 HP" },
    bulwark = { name = "Bulwark", rarity = "rare", cost = 2,
        front = { kind = "hero", armor_add = 0.18 }, front_text = "-18% incoming damage",
        back = { kind = "swarm", dps_add = 1.2 }, back_text = "swarm bites +1.2 harder" },
    plated_guard = { name = "Plated Guard", rarity = "epic", cost = 3,
        front = { kind = "hero", armor_add = 0.25, hp_max_add = 30.0 }, front_text = "-25% incoming, +30 HP",
        back = { kind = "spawn", role = "ranged", count = 4, reserve_cost = 10 }, back_text = "surge: 4 ranged now" },
    regeneration = { name = "Regeneration", rarity = "uncommon", cost = 2,
        front = { kind = "hero", regen_add = 2.0 }, front_text = "+2 HP per second",
        back = { kind = "weaken", speed_mult = 0.85, kite_speed_mult = 0.85 }, back_text = "hero moves -15% slower" },
    second_wind = { name = "Second Wind", rarity = "rare", cost = 2,
        front = { kind = "hero", regen_add = 3.0, heal = 25.0 }, front_text = "+3 HP/s and a heal",
        back = { kind = "reserve", reserve_add = 30.0 }, back_text = "+30 horde reserve" },
    last_stand = { name = "Last Stand", rarity = "epic", cost = 3,
        front = { kind = "hero", hp_max_add = 60.0, heal = 60.0, armor_add = 0.1 }, front_text = "+60 HP, heal, -10% incoming",
        back = { kind = "escalate", cap_add = 14 }, back_text = "+14 concurrent swarm cap" },
    thornmail = { name = "Thornmail", rarity = "rare", cost = 2,
        front = { kind = "hero", thorns_add = 2.0 }, front_text = "reflect 2 dmg to attackers",
        back = { kind = "swarm", hp_add = 5.0 }, back_text = "swarm gains +5 HP" },
    stoneblood = { name = "Stoneblood", rarity = "uncommon", cost = 2,
        front = { kind = "hero", hp_max_add = 35.0, regen_add = 1.0 }, front_text = "+35 HP, +1 HP/s",
        back = { kind = "swarm", hp_add = 4.0, speed_add = 0.1 }, back_text = "swarm tougher + a touch faster" },
    aegis = { name = "Aegis", rarity = "legendary", cost = 3,
        front = { kind = "hero", armor_add = 0.3, hp_max_add = 40.0, regen_add = 2.0 }, front_text = "-30% incoming, +40 HP, regen",
        back = { kind = "spawn", role = "brute", count = 2, reserve_cost = 16 }, back_text = "summon 2 brutes now" },
    fortify = { name = "Fortify", rarity = "common", cost = 1,
        front = { kind = "hero", hp_max_add = 20.0, armor_add = 0.06 }, front_text = "+20 HP, slight armor",
        back = { kind = "swarm", hp_add = 3.0 }, back_text = "swarm gains +3 HP" },

    -- ----- Mobility: outrun the swarm / catch the hero -----------------
    swift_boots = { name = "Swift Boots", rarity = "common", cost = 1,
        front = { kind = "hero", speed_mult = 1.15, kite_speed_mult = 1.15 }, front_text = "+15% move speed",
        back = { kind = "swarm", speed_add = 0.35 }, back_text = "swarm rushes +0.35 faster" },
    fleetfoot = { name = "Fleetfoot", rarity = "uncommon", cost = 2,
        front = { kind = "hero", speed_mult = 1.25, kite_speed_mult = 1.3 }, front_text = "+25% speed, better kiting",
        back = { kind = "swarm", speed_add = 0.5 }, back_text = "swarm rushes +0.5 faster" },
    evasive_step = { name = "Evasive Step", rarity = "rare", cost = 2,
        front = { kind = "hero", dash_add = 1.0, kite_speed_mult = 1.2 }, front_text = "gain a dodge dash",
        back = { kind = "weaken", speed_mult = 0.9 }, back_text = "hero moves -10% slower" },
    windrunner = { name = "Windrunner", rarity = "epic", cost = 3,
        front = { kind = "hero", speed_mult = 1.3, dash_add = 1.0, dps_mult = 1.1 }, front_text = "+30% speed, dash, +10% dmg",
        back = { kind = "escalate", batch_add = 2, interval_mult = 0.9 }, back_text = "+2 per batch, faster spawns" },
    hobble = { name = "Hobble", rarity = "uncommon", cost = 2,
        front = { kind = "hero", kite_speed_mult = 1.2, regen_add = 1.0 }, front_text = "better kiting, +1 HP/s",
        back = { kind = "weaken", speed_mult = 0.8, kite_speed_mult = 0.8 }, back_text = "hero moves -20% slower" },
    swarm_speed = { name = "Quickening", rarity = "rare", cost = 2,
        front = { kind = "hero", speed_mult = 1.18, attack_range_add = 0.15 }, front_text = "+18% speed, slight reach",
        back = { kind = "swarm", speed_add = 0.6 }, back_text = "swarm rushes +0.6 faster" },

    -- ----- Control / AoE: clear crowds / overwhelm with numbers --------
    wide_swing = { name = "Wide Swing", rarity = "uncommon", cost = 2,
        front = { kind = "hero", cleave_add = 1 }, front_text = "+1 cleave target",
        back = { kind = "escalate", batch_add = 2 }, back_text = "+2 creeps per spawn batch" },
    cleaving_arc = { name = "Cleaving Arc", rarity = "rare", cost = 2,
        front = { kind = "hero", cleave_add = 2 }, front_text = "+2 cleave targets",
        back = { kind = "escalate", batch_add = 3 }, back_text = "+3 creeps per spawn batch" },
    long_reach = { name = "Long Reach", rarity = "uncommon", cost = 2,
        front = { kind = "hero", attack_range_add = 0.35 }, front_text = "+0.35 hero reach",
        back = { kind = "spawn", role = "swarm", count = 6, reserve_cost = 6 }, back_text = "surge: 6 swarm now" },
    polearm = { name = "Polearm", rarity = "rare", cost = 2,
        front = { kind = "hero", attack_range_add = 0.5, cleave_add = 1 }, front_text = "+0.5 reach, +1 cleave",
        back = { kind = "escalate", cap_add = 10 }, back_text = "+10 concurrent swarm cap" },
    whirlwind = { name = "Whirlwind", rarity = "rare", cost = 2,
        front = { kind = "hero", whirl_add = 1 }, front_text = "gain a spinning AoE pulse",
        back = { kind = "escalate", cap_add = 12 }, back_text = "+12 concurrent swarm cap" },
    cyclone = { name = "Cyclone", rarity = "epic", cost = 3,
        front = { kind = "hero", whirl_add = 2 }, front_text = "stronger AoE pulse (+2)",
        back = { kind = "escalate", cap_add = 16, batch_add = 1 }, back_text = "+16 cap, +1 per batch" },
    frenzy = { name = "Frenzy", rarity = "rare", cost = 2,
        front = { kind = "hero", dps_mult = 1.2, speed_mult = 1.08 }, front_text = "+20% damage, +8% speed",
        back = { kind = "escalate", interval_mult = 0.8 }, back_text = "spawns 20% more often" },
    maelstrom = { name = "Maelstrom", rarity = "legendary", cost = 3,
        front = { kind = "hero", whirl_add = 2, cleave_add = 1, attack_range_add = 0.2 }, front_text = "+2 whirl, +1 cleave, reach",
        back = { kind = "spawn", role = "swarm", count = 10, reserve_cost = 10 }, back_text = "surge: 10 swarm now" },

    -- ----- Summon / Spawn: bring help / spend the reserve --------------
    brute_call = { name = "Brute Call", rarity = "epic", cost = 3,
        front = { kind = "hero", cleave_add = 1, attack_range_add = 0.25 }, front_text = "+1 cleave, +0.25 reach",
        back = { kind = "spawn", role = "brute", count = 2, reserve_cost = 14 }, back_text = "summon 2 brutes now" },
    onslaught = { name = "Onslaught", rarity = "epic", cost = 3,
        front = { kind = "hero", dps_mult = 1.18, cleave_add = 1 }, front_text = "+18% damage, +1 cleave",
        back = { kind = "spawn", role = "swarm", count = 8, reserve_cost = 8 }, back_text = "surge: 8 swarm now" },
    arrowstorm = { name = "Arrowstorm", rarity = "rare", cost = 2,
        front = { kind = "hero", attack_range_add = 0.3, dps_add = 3.0 }, front_text = "+0.3 reach, +3 damage",
        back = { kind = "spawn", role = "ranged", count = 3, reserve_cost = 9 }, back_text = "surge: 3 ranged now" },
    elite_guard = { name = "Elite Guard", rarity = "epic", cost = 3,
        front = { kind = "hero", hp_max_add = 40.0, dps_mult = 1.1 }, front_text = "+40 HP, +10% damage",
        back = { kind = "spawn", role = "elite", count = 2, reserve_cost = 11 }, back_text = "summon 2 elites now" },
    reinforce = { name = "Reinforce", rarity = "uncommon", cost = 2,
        front = { kind = "hero", heal = 40.0, regen_add = 1.0 }, front_text = "heal 40, +1 HP/s",
        back = { kind = "reserve", reserve_add = 45.0 }, back_text = "+45 horde reserve" },
    swell_the_ranks = { name = "Swell the Ranks", rarity = "rare", cost = 2,
        front = { kind = "hero", cleave_add = 1, hp_max_add = 20.0 }, front_text = "+1 cleave, +20 HP",
        back = { kind = "escalate", batch_add = 2, cap_add = 8 }, back_text = "+2 per batch, +8 cap" },
    war_horn = { name = "War Horn", rarity = "epic", cost = 3,
        front = { kind = "hero", dps_mult = 1.2, speed_mult = 1.1, heal = 20.0 }, front_text = "rally: +20% dmg, +10% speed",
        back = { kind = "spawn", role = "swarm", count = 6, reserve_cost = 6 }, back_text = "rally: 6 swarm now" },
    relentless_tide = { name = "Relentless Tide", rarity = "legendary", cost = 3,
        front = { kind = "hero", regen_add = 3.0, armor_add = 0.12, dps_mult = 1.1 }, front_text = "regen, armor, +10% dmg",
        back = { kind = "spawn", role = "swarm", count = 12, reserve_cost = 12 }, back_text = "the tide: 12 swarm now" },
    dark_pact = { name = "Dark Pact", rarity = "rare", cost = 2,
        front = { kind = "hero", lifesteal_add = 1.5, dps_mult = 1.12 }, front_text = "heal 1.5/kill, +12% dmg",
        back = { kind = "reserve", reserve_add = 25.0 }, back_text = "+25 horde reserve" },
    grave_summons = { name = "Grave Summons", rarity = "epic", cost = 3,
        front = { kind = "hero", whirl_add = 1, hp_max_add = 25.0 }, front_text = "+1 whirl, +25 HP",
        back = { kind = "spawn", role = "elite", count = 1, reserve_cost = 6 }, back_text = "raise an elite now" },
    champions_boon = { name = "Champion's Boon", rarity = "legendary", cost = 3,
        front = { kind = "hero", dps_mult = 1.3, hp_max_add = 40.0, heal = 40.0, armor_add = 0.1 }, front_text = "+30% dmg, +40 HP, armor",
        back = { kind = "spawn", role = "brute", count = 1, reserve_cost = 7 }, back_text = "champion brute now" },
    feral_pack = { name = "Feral Pack", rarity = "rare", cost = 2,
        front = { kind = "hero", speed_mult = 1.12, dps_mult = 1.12 }, front_text = "+12% speed and damage",
        back = { kind = "spawn", role = "swarm", count = 5, reserve_cost = 5 }, back_text = "loose a pack: 5 swarm" },
    siege_engine = { name = "Siege Engine", rarity = "epic", cost = 3,
        front = { kind = "hero", attack_range_add = 0.4, dps_mult = 1.15 }, front_text = "+0.4 reach, +15% dmg",
        back = { kind = "spawn", role = "ranged", count = 2, reserve_cost = 7 }, back_text = "deploy 2 ranged now" },
    unbreakable = { name = "Unbreakable", rarity = "legendary", cost = 3,
        front = { kind = "hero", hp_max_add = 70.0, heal = 70.0, armor_add = 0.18 }, front_text = "+70 HP, heal, armor",
        back = { kind = "escalate", cap_add = 18, interval_mult = 0.9 }, back_text = "+18 cap, faster spawns" },
}

-- The full collection (menu shows all of these; player keeps DECK_SIZE).
-- A stable display order so the menu grid doesn't reshuffle frame to frame.
Cards.all_ids = {
    -- offense
    "honed_edge", "keen_point", "savage_blow", "executioner", "rending_strikes",
    "bloodthirst", "crimson_feast", "berserk", "giant_slayer", "duelists_focus", "overpower",
    -- defense
    "vigor", "iron_skin", "bulwark", "plated_guard", "regeneration", "second_wind",
    "last_stand", "thornmail", "stoneblood", "aegis", "fortify",
    -- mobility
    "swift_boots", "fleetfoot", "evasive_step", "windrunner", "hobble", "swarm_speed",
    -- control / aoe
    "wide_swing", "cleaving_arc", "long_reach", "polearm", "whirlwind", "cyclone",
    "frenzy", "maelstrom",
    -- summon / spawn
    "brute_call", "onslaught", "arrowstorm", "elite_guard", "reinforce", "swell_the_ranks",
    "war_horn", "relentless_tide", "dark_pact", "grave_summons", "champions_boon",
    "feral_pack", "siege_engine", "unbreakable",
}

-- A solid, balanced 20-card deck used by the AI opponent and as the menu's
-- pre-checked starting selection.
Cards.default_deck = {
    "honed_edge", "savage_blow", "bloodthirst", "giant_slayer", "duelists_focus",
    "vigor", "iron_skin", "bulwark", "regeneration", "thornmail",
    "swift_boots", "fleetfoot", "evasive_step",
    "wide_swing", "whirlwind", "frenzy",
    "brute_call", "onslaught", "elite_guard", "war_horn",
}

-- --------------------------------------------------------------------------
-- Lookups
-- --------------------------------------------------------------------------

function Cards.card(card_id) return Cards.catalog[card_id] end

function Cards.rarity(card_id)
    local card = Cards.catalog[card_id]
    return card and RARITY[card.rarity] or RARITY.common
end

-- The effect table this seat's face fires, plus its world-effect description.
function Cards.face(card_id, side)
    local card = Cards.catalog[card_id]
    if not card then return nil, "" end
    if side == "hero" then return card.front, card.front_text or "" end
    return card.back, card.back_text or ""
end

-- --------------------------------------------------------------------------
-- Deck / hand / command bookkeeping (per seat) — mirrors rush/cards.lua.
-- --------------------------------------------------------------------------

local function copy_list(list)
    local out = {}
    for _, v in ipairs(list or {}) do out[#out + 1] = v end
    return out
end

local function shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

local function append_capped(list, value, max_count)
    list[#list + 1] = value
    while #list > (max_count or #list) do table.remove(list, 1) end
end

-- Validate/clean a chosen deck: drop unknown ids, fall back to default if empty.
function Cards.sanitize_deck(deck)
    local out = {}
    for _, id in ipairs(deck or {}) do
        if Cards.catalog[id] then out[#out + 1] = id end
    end
    if #out == 0 then out = copy_list(Cards.default_deck) end
    return out
end

-- side = "hero" (plays fronts) or "horde" (plays backs).
function Cards.create(opts)
    opts = opts or {}
    local side = opts.side == "hero" and "hero" or "horde"
    local deck = shuffle(Cards.sanitize_deck(opts.deck))
    local default_command = side == "hero" and Cards.HERO_COMMAND or Cards.HORDE_COMMAND
    return {
        side = side,
        deck = deck,
        discard = {},
        hand = {},
        played = {},
        command = opts.command_max or default_command,
        command_max = opts.command_max or default_command,
        hand_size = opts.hand_size or Cards.HAND_SIZE,
        log = {},
    }
end

local function draw_one(self)
    if #self.deck == 0 and #self.discard > 0 then
        self.deck = shuffle(copy_list(self.discard))
        self.discard = {}
    end
    if #self.deck == 0 then return nil end
    return table.remove(self.deck, 1)
end

function Cards.start_pause(self)
    for _, card_id in ipairs(self.hand) do self.discard[#self.discard + 1] = card_id end
    self.hand = {}
    self.played = {}
    self.command = self.command_max
    for _ = 1, self.hand_size do
        local card_id = draw_one(self)
        if card_id then self.hand[#self.hand + 1] = card_id end
    end
    append_capped(self.log, "Drew " .. tostring(#self.hand) .. " cards.", 6)
end

-- Play hand[index]. Returns ok, message, effect, card_id.
function Cards.play(self, index)
    local card_id = self.hand[index]
    local card = card_id and Cards.catalog[card_id]
    if not card then return false, "No card in slot " .. tostring(index) .. ".", nil, nil end
    if (self.command or 0) < (card.cost or 0) then
        return false, "Need " .. tostring(card.cost) .. " command for " .. card.name .. ".", nil, nil
    end
    local effect = Cards.face(card_id, self.side)
    self.command = self.command - (card.cost or 0)
    table.remove(self.hand, index)
    self.played[#self.played + 1] = card_id
    append_capped(self.log, "Played " .. card.name .. ".", 6)
    return true, "Played " .. card.name .. ".", effect, card_id
end

function Cards.can_play(self)
    for _, card_id in ipairs(self.hand) do
        local card = Cards.catalog[card_id]
        if card and (self.command or 0) >= (card.cost or 0) then return true end
    end
    return false
end

-- Slot-keyed legal options for UI + AI. `affordable_only` filters to playable.
function Cards.legal_actions(self, affordable_only)
    local out = {}
    for i, card_id in ipairs(self.hand) do
        local card = Cards.catalog[card_id]
        if card then
            local affordable = (self.command or 0) >= (card.cost or 0)
            if affordable or not affordable_only then
                local _, text = Cards.face(card_id, self.side)
                out[#out + 1] = {
                    id = "slot" .. tostring(i), slot = i, card = card_id,
                    label = card.name, desc = text, cost = card.cost or 0, affordable = affordable,
                }
            end
        end
    end
    return out
end

function Cards.slot_of_action(self, action_id)
    for _, action in ipairs(Cards.legal_actions(self, true)) do
        if action.id == action_id then return action.slot end
    end
    return nil
end

return Cards
