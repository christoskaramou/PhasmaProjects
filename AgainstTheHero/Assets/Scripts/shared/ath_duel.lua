-- ath_duel — the shared HERO-vs-HORDE duel engine every mode runs on.
--
-- This is the generalised, reusable heart of the rush prototype: one arena, one
-- auto-fighting hero, a continuous rushing swarm, and a ROUND/PAUSE loop where
-- both sides grow via the dual-faced cards. A "mode" is now mostly CONTENT — a
-- theme, an arena, a cast of characters (creep archetypes), and one signature
-- mechanic — handed to Duel.new(config). The loop, the reserve economy, the card
-- application, the HUD, the camera, win/loss, and the AI for whichever seat the
-- player did NOT pick all live here, so every mode plays consistently.
--
-- The player picked a SIDE in the menu (ctx.side). Either way the hero
-- auto-fights and the swarm auto-rushes; the only difference is which SEAT's
-- cards the human plays at each pause, and which side's victory counts as a win:
--   * side = "hero"  -> human plays the hero's FRONT upgrade cards; AI commands
--                       the horde. Win when the reserve is spent and field clear.
--   * side = "horde" -> human commands the horde's BACK cards; AI upgrades the
--                       hero. Win when the hero's HP hits 0.
--
-- Reuses shared/duel_flow.lua (map + flow field) and shared/duel_creep.lua
-- (characters with movement, projectiles, procedural animation). Visuals/HUD go
-- through ath_art.
--
-- See modes/pit/mode.lua for a worked example of a mode config.

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Cards = ATH_COMMON.load_script("Scripts/shared/ath_cards.lua", "shared cards", _ENV)
local Flow = ATH_COMMON.load_script("Scripts/shared/duel_flow.lua", "duel flow", _ENV)
local Creep = ATH_COMMON.load_script("Scripts/shared/duel_creep.lua", "duel creep", _ENV)
local Console = ATH_COMMON.load_script("Scripts/shared/ath_console.lua", "dev console", _ENV)
local Inventory = ATH_COMMON.load_script("Scripts/shared/ath_inventory.lua", "inventory", _ENV)
local Profile = ATH_COMMON.load_script("Scripts/shared/ath_profile.lua", "persistent profile", _ENV)

-- Dev-only diagnostic logging ([DMG]/[CAMDIAG]); silent unless ATH_DEV=1 at launch.
local ATH_DEV = ATH_COMMON.env_enabled and ATH_COMMON.env_enabled("ATH_DEV", false) or false

local Duel = {}
Duel.__index = Duel

local SLOWMO_SCALE = 0.4
local SLOWMO_DURATION = 1.2
local WHIRL_CD = 1.2
local WHIRL_RADIUS_BASE = 2.0

-- Feel constants (juice pass). Hit flash is a brief emissive whiteout; knockback
-- is a small decaying shove on the struck actor; telegraphs are the pre-spawn
-- ground markers that warn where the swarm is about to pour in.
local HIT_FLASH_T = 0.16          -- seconds a struck sprite stays flashed white
local CREEP_KNOCK_MELEE = 2.2     -- shove (u/s) a melee cleave/whirl puts on a creep
local CREEP_KNOCK_BOLT = 3.4      -- shove a hero bolt puts on a creep along its flight
local HERO_KNOCK_CONTACT = 1.4    -- tiny self-stagger when the swarm bites the hero
local HERO_KNOCK_BOLT = 2.6       -- tiny self-stagger when a creep projectile lands
local TELEGRAPH_T = 0.45          -- warn window before a normal creep materialises
local TELEGRAPH_T_BIG = 0.75      -- longer, scarier warn for elites/brutes
local TELEGRAPH_BIG_COST = 4      -- threat_cost at/above which a spawn reads as "big"
local CPROJ_POOL = 24             -- pooled creep projectile spheres (never deleted)

-- Kill-feel + loot constants (fun pass).
local CRIT_MULT = 2.0             -- a crit doubles the hit
local MELEE_FLUSH_T = 0.32        -- melee dt-damage aggregates into a popup this often
local DMGNUM_POOL = 26            -- concurrent floating damage numbers
local DMGNUM_LIFE = 0.7           -- seconds a number floats/fades
local COIN_POOL = 40              -- pooled gold coin nodes on the ground
local BEACON_POOL = 8             -- pooled item-drop beacons on the ground
local COIN_COLLECT_R = 1.1       -- world radius at which a magnetised coin banks
local BEACON_COLLECT_R = 1.8      -- walk-over pickup FLOOR; live hero.pickup_range wins when larger
local PICKUP_RANGE_BASE = 4.5     -- base coin-magnet / item-grab radius (Brotato-generous)
local HITSTOP_SCALE = 0.12        -- sim speed during a hitstop beat
local ELITE_HP_MULT = 2.6
local ELITE_DPS_MULT = 1.4

-- Normal-tier dodge (combat plan step 1). Kept as per-hero fields so the later
-- Light/Heavy load tiers only retune numbers, never reshape the state.
local DODGE_DIST = 3.0            -- world units one dodge covers
local DODGE_DUR = 0.20            -- seconds the dash lasts (dist/dur = dash speed)
local DODGE_IFRAMES = 0.20        -- invulnerability window from dodge start
local DODGE_RECHARGE = 4.0        -- seconds to restore a spent charge

-- Telegraph grammar (shared enemy language): a WHITE ramp-flash on the sprite =
-- an attack is winding up (0.4s), a RED tint/decal = the attack must be dodged,
-- a ground decal = area impact incoming. Melee contact damage is now discrete
-- BITES behind that white flash instead of silent per-frame contact dps.
local BITE_WINDUP = 0.4           -- white-flash seconds before a melee bite lands
local BITE_COOLDOWN = 0.8         -- rest after a bite (damage = dps * full cycle)
local BITE_GRACE = 0.35           -- reach slack at landing so edge-dancing still counts
local SHOT_WINDUP = 0.4           -- white-flash seconds before a ranged shot releases

-- Balance-smoke loadouts (ATH_DUEL_GEARSET=mid|top): fixed gear per tier so
-- map II/III tuning runs are repeatable.
local GEARSETS = {
    mid = { "iron_helm", "husk_plate", "sprint_greaves", "gauntlets", "husk_cleaver", "moss_locket" },
    top = { "gourd_visor", "royal_carapace", "plated_greaves", "duelist_gloves", "twin_blades", "crit_ring" },
}

-- Wave-start draft — pick 1 of 3 run-scoped boons. Effects use the same stat
-- vocabulary as gear (applied on top of base + gear by recompute_hero_stats);
-- `heal` fires once at pick time. A mode may override via config.draft_cards.
local DRAFT_CARDS = {
    { id = "whetstone", name = "Whetstone", rarity = "common", desc = "+15% damage",
      effect = { dps_mult = 1.15 } },
    { id = "quick_hands", name = "Quick Hands", rarity = "common", desc = "+12% attack speed",
      effect = { fire_interval_mult = 0.88 } },
    { id = "field_rations", name = "Field Rations", rarity = "common", desc = "+25 max HP, heal 40",
      effect = { hp_max_add = 25.0, heal = 40.0 } },
    { id = "swift_soles", name = "Swift Soles", rarity = "common", desc = "+10% move speed",
      effect = { speed_mult = 1.10, kite_speed_mult = 1.10 } },
    { id = "tough_hide", name = "Tough Hide", rarity = "common", desc = "+8% armor",
      effect = { armor_add = 0.08 } },
    { id = "long_arms", name = "Long Arms", rarity = "common", desc = "+1.5 attack range",
      effect = { attack_range_add = 1.5 } },
    { id = "extra_bolt", name = "Extra Bolt", rarity = "uncommon", desc = "+1 shot per volley",
      effect = { cleave_add = 1 } },
    { id = "leech_fang", name = "Leech Fang", rarity = "uncommon", desc = "+2 lifesteal per hit",
      effect = { lifesteal_add = 2.0 } },
    { id = "green_blood", name = "Green Blood", rarity = "uncommon", desc = "+1.5 HP/s regen",
      effect = { regen_add = 1.5 } },
    { id = "bramble_coat", name = "Bramble Coat", rarity = "uncommon", desc = "+6 thorns",
      effect = { thorns_add = 6.0 } },
    { id = "magnet_pouch", name = "Magnet Pouch", rarity = "uncommon", desc = "+1.2 pickup range, +25% gold",
      effect = { pickup_range_add = 1.2, gold_find_add = 0.25 } },
    { id = "keen_eye", name = "Keen Eye", rarity = "uncommon", desc = "+15% crit chance",
      effect = { crit_add = 0.15 } },
    { id = "whirlwind", name = "Whirlwind", rarity = "rare", desc = "Spin attack around you",
      effect = { whirl_add = 1 } },
    { id = "chill_aura", name = "Chill Aura", rarity = "rare", desc = "Nearby enemies slow to a crawl",
      effect = { slow_aura = true } },
    { id = "glass_edge", name = "Glass Edge", rarity = "rare", desc = "+35% damage, -8% move",
      effect = { dps_mult = 1.35, speed_mult = 0.92, kite_speed_mult = 0.92 } },
    { id = "gold_rush", name = "Gold Rush", rarity = "common", desc = "+30% gold",
      effect = { gold_find_add = 0.30 } },
    { id = "quick_step", name = "Quick Step", rarity = "uncommon", desc = "Dodge recharges 25% faster",
      effect = { dodge_recharge_mult = 0.75 } },
    { id = "bulwark", name = "Bulwark", rarity = "rare", desc = "+15% armor, +20 max HP",
      effect = { armor_add = 0.15, hp_max_add = 20.0 } },
    { id = "second_wind", name = "Second Wind", rarity = "rare", desc = "+1 dodge charge",
      effect = { dodge_charge_add = 1 } },
}
local DRAFT_WEIGHTS = { common = 60, uncommon = 32, rare = 8 }
local RARITY_COLOR = {
    common   = { 0.66, 0.70, 0.76, 1.0 },
    uncommon = { 0.42, 0.84, 0.48, 1.0 },
    rare     = { 0.38, 0.64, 0.97, 1.0 },
    epic     = { 0.78, 0.48, 0.96, 1.0 },
}

-- Display name for damage sources / the death recap.
local function creep_name(c)
    return (c and c.stats and c.stats.name) or (c and c.archetype) or "the swarm"
end

local function clampn(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function arena_actor_bounds(A, clearance)
    local c = clearance or 0.8
    return A.pad + c, A.w - A.pad - 1.0 - c,
        A.pad + c, A.h - A.pad - 1.0 - c
end

-- Pointer in surface pixels (mouse on desktop; SDL maps touch -> mouse on
-- Android, so this also tracks a finger). Used by the virtual movement joystick.
local function ui_pointer()
    if input and input.get_mouse_position then
        local p = input.get_mouse_position()
        if p and p.x then
            local w = engine and engine.get_window_size and engine.get_window_size() or nil
            local s = runtime_ui and runtime_ui.get_surface_size and runtime_ui.get_surface_size() or nil
            if w and s and w.w > 0 and w.h > 0 and s.w > 0 and s.h > 0 then
                return p.x * s.w / w.w, p.y * s.h / w.h
            end
            return p.x, p.y
        end
    end
    return nil
end
local function pointer_down()
    return input and input.is_left_mouse_down and input.is_left_mouse_down() == true
end

-- A minimal flat sprite hero (single textured quad, no sword/cape) for top-down
-- manual-hero modes. Avoids loading the large knight textures (which would only
-- be hidden anyway); ath_topdown_view lays the body flat and re-applies the
-- mode's sprite each frame.
--
local function flat_hero_actor(sprite_texture)
    return {
        name = "Flat_Hero",
        parts = {
            body = {
                kind = "quad", quad_width = 1.6, quad_height = 2.2,
                position = { 0.0, 1.1, 0.0 },
                color = { 1.0, 1.0, 1.0 }, emissive = 1.0, emissive_texture = true,
                texture = sprite_texture or "Objects/white.png",
            },
        },
    }
end

-- A sensible default hero rig (the classic knight) used when a mode does not
-- supply config.hero.actor. Part keys match ath_art's built-in walk/attack clips.
local function default_hero_actor(theme)
    return {
        name = "Souls_Knight",
        soft_cape = {
            width    = 2.0,
            height   = 1.6,
            segments = 48,
            bones    = 20,
            position = { 0.0, 0.75, 0.12 },
            rotation = { 0.0, 0.0, -90.0 },
            scale    = { 1.0, 1.0, 1.0 },
            texture  = "Textures/hero/knight/knight_cape_strip.png",
            wave_speed   = 2.5,
            wave_phase   = 3.0,
            wave_amp_deg = 10.0,
        },
        parts = {
            body  = {
                kind = "quad", quad_width = 1.6, quad_height = 2.2,
                position = { 0.0, 1.1, 0.0 },
                color = { 1.0, 1.0, 1.0 }, emissive = 1.0, emissive_texture = true,
                texture = "Textures/hero/knight/knight_body.png",
            },
            sword = {
                kind = "quad", quad_width = 1.6, quad_height = 2.2,
                position = { 0.0, 1.1, 0.05 },
                color = { 1.0, 1.0, 1.0 }, emissive = 1.0, emissive_texture = true,
                texture = "Textures/hero/knight/knight_sword.png",
            },
        },
    }
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

function Duel.new(config, ctx, shell)
    local D = setmetatable({}, Duel)
    D.config = config or {}
    D.ctx = ctx or {}
    D.shell = shell
    D.manual_hero = D.config.manual_hero == true
    D.side = D.manual_hero and "hero" or ((ctx and ctx.side == "horde") and "horde" or "hero")
    D.hud = "ath.duel.hud"
    D.theme = D.config.theme or {}
    D.key_down = {}
    D.creeps = {}
    D.spawn_queue = {}
    D.next_id = 0
    D.spawn_counter = 0
    D.realtime = 0.0
    D.fallback_dt = 1.0 / 120.0
    D.autoplay = ATH_COMMON.env_enabled("ATH_DUEL_AUTOPLAY", false)
    D.flash = ""
    D.flash_t = 0.0

    -- Arena geometry.
    local a = D.config.arena or {}
    D.arena = {
        w = a.width or 48,
        h = a.height or 34,
        pad = a.pad or 2,
        ortho_size = a.ortho_size or 34.0,
        cam_offset = a.cam_offset or { x = -44.0, y = 44.0, z = 44.0 },
    }
    D.arena.hero_start = a.hero_start or { x = math.floor(D.arena.w * 0.5), y = math.floor(D.arena.h * 0.5) }
    -- Open arenas (the default) have no interior obstacles, so creeps BEELINE
    -- straight at the hero (Creep.update falls back to direct pursuit when no flow
    -- field is supplied). A mode with a maze sets arena.flow_field = true to get
    -- the 4-connected flow-field pathing instead.
    D.use_flow_field = a.flow_field == true

    -- Hero baseline.
    local h = D.config.hero or {}
    D.hero_spec = {
        hp_max = h.hp_max or 90.0,
        dps = h.dps or 20.0,
        cleave = h.cleave or 3,
        attack_range = h.attack_range or 1.25,
        speed = h.speed or 2.2,
        kite_speed = h.kite_speed or 2.7,
        body_radius = h.body_radius or 0.6,
        kite_threshold = h.kite_threshold or 0.30,
        kite_distance = h.kite_distance or 4.5,
        actor = h.actor or default_hero_actor(D.theme),
    }
    -- Selected hero class id (manual arena). ATH_HERO_CLASS overrides the default
    -- for headless smokes; otherwise the player picks at run start.
    D.hero_class = ATH_COMMON.getenv("ATH_HERO_CLASS",
        h.default_class or (h.classes and h.classes[1] and h.classes[1].id))

    -- Spawn tuning.
    local s = D.config.spawn or {}
    D.spawn_cfg = {
        interval_start = s.interval_start or 0.7,
        interval_min = s.interval_min or 0.3,
        interval_ramp = s.interval_ramp or 0.05,
        batch_start = s.batch_start or 3,
        batch_max = s.batch_max or 7,
        cap_start = s.cap_start or 32,
        cap_max = s.cap_max or 90,
        brute_after = s.brute_after or 18.0,
    }

    -- Spawn telegraphs (pre-spawn ground markers) are on for the manual arena by
    -- default; legacy duel modes keep instant authored-ring spawns unless opted in.
    D.use_telegraph = D.manual_hero and (s.telegraph ~= false)

    D.roles = D.config.roles or {}
    D.reserve_start = ATH_COMMON.getenv_number("ATH_DUEL_RESERVE", D.config.reserve_start or 300.0)
    D.round_seconds = ATH_COMMON.getenv_number("ATH_DUEL_ROUND", D.config.round_seconds or 14.0)

    local waves = D.config.waves or {}
    D.wave_cfg = {
        count = waves.count or 5,
        budgets = waves.budgets,
        reserve_start = waves.reserve_start,
        reserve_add = waves.reserve_add or 40.0,
    }
    local gear = D.config.gear or {}
    D.gear_cfg = {
        items = gear.items or {},
        drop_every = gear.drop_every or 6,
        gold_per_kill = gear.gold_per_kill or 1,
    }
    D.store_offers = {}
    for _, item in ipairs(D.gear_cfg.items) do
        if item.slot and not D.store_offers[item.slot] then D.store_offers[item.slot] = item end
    end
    -- Map ladder: config.maps (waves/boss/difficulty/loot per rank); clearing a
    -- map unlocks the next, persisted in the profile as maps_cleared.
    D.maps = config.maps or {}
    D.maps_cleared = 0
    Profile.load(D)
    if #D.maps > 0 then
        D.map_index = math.min((D.maps_cleared or 0) + 1, #D.maps)
    else
        D.map_index = 1
    end
    return D
end

-- The active map definition ({} when the mode has no map ladder).
function Duel:active_map()
    return (self.maps and self.maps[self.map_index]) or {}
end

-- Rarity-weighted item roll. Weights come from the map def (deeper maps skew
-- rare/epic); min_rarity floors the pool (boss showers).
local RARITY_RANK_W = { common = 1, uncommon = 2, rare = 3, epic = 4 }
function Duel:roll_drop_item(items, min_rarity, weights)
    weights = weights or self:active_map().drop_weights
        or { common = 60, uncommon = 30, rare = 9, epic = 1 }
    local min_rank = RARITY_RANK_W[min_rarity or "common"] or 1
    local pool, total = {}, 0.0
    for _, it in ipairs(items) do
        local rank = RARITY_RANK_W[it.rarity or "common"] or 1
        if rank >= min_rank then
            local w = weights[it.rarity or "common"] or 1
            pool[#pool + 1] = { it = it, w = w }
            total = total + w
        end
    end
    if #pool == 0 or total <= 0.0 then return items[math.random(#items)] end
    local roll = math.random() * total
    for _, e in ipairs(pool) do
        roll = roll - e.w
        if roll <= 0.0 then return e.it end
    end
    return pool[#pool].it
end

-- Town store restock: one weighted roll per slot, rerolled every town visit so
-- the shop stays interesting; loot odds follow the highest UNLOCKED map.
function Duel:restock_store()
    local items = (self.gear_cfg and self.gear_cfg.items) or {}
    if #items == 0 then return end
    local best = self.maps and self.maps[math.min((self.maps_cleared or 0) + 1, math.max(#self.maps, 1))]
    local weights = best and best.drop_weights
    self.store_offers = {}
    for _, item in ipairs(items) do
        if item.slot and not self.store_offers[item.slot] then self.store_offers[item.slot] = item end
    end
    for slot in pairs(self.store_offers) do
        local slot_items = {}
        for _, it in ipairs(items) do
            if it.slot == slot then slot_items[#slot_items + 1] = it end
        end
        if #slot_items > 0 then
            self.store_offers[slot] = self:roll_drop_item(slot_items, nil, weights)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

function Duel:log(msg)
    if pe_log then pe_log("[ATH:" .. tostring(self.config.id or "duel"):upper() .. "] " .. tostring(msg)) end
end

function Duel:save_profile()
    return Profile.save(self)
end

function Duel:store_price(item)
    -- Priced against measured pilot income: a full map-I clear banks ~1.2k gold,
    -- map III ~4-6k — a run should buy one or two pieces, not the whole shelf.
    local prices = { common = 50, uncommon = 150, rare = 400, epic = 1000 }
    return prices[(item and item.rarity) or "common"] or prices.common
end

function Duel:buy_store_offer(slot)
    if self.state ~= "town" then return false end
    local item = self.store_offers and self.store_offers[slot]
    if not item then return false end
    local price = self:store_price(item)
    if (self.gold or 0) < price then
        self:set_flash("Need " .. tostring(price - (self.gold or 0)) .. " more gold")
        return false
    end
    if not Inventory.add_item(self, item) then
        self:set_flash("Backpack full")
        return false
    end
    self.gold = self.gold - price
    self:save_profile()
    self:haptic(12)
    self:set_flash("Bought " .. tostring(item.name or item.id))
    self:log(string.format("store buy item=%s price=%d gold=%d", tostring(item.id), price, self.gold))
    return true
end

function Duel:key_pressed(name)
    if not input or not input.is_key_down then return false end
    local down = input.is_key_down(name)
    local pressed = down and not self.key_down[name]
    self.key_down[name] = down
    return pressed
end

function Duel:is_key_down(name)
    return input and input.is_key_down and input.is_key_down(name) == true
end

function Duel:set_flash(text)
    self.flash = text or ""
end

-- ---------------------------------------------------------------------------
-- Arena
-- ---------------------------------------------------------------------------

function Duel:build_arena()
    local A = self.arena
    local theme = self.theme
    local def = self.config.arena and self.config.arena.map_def
    if not def then
        def = {
            id = (self.config.id or "duel") .. "_arena",
            title = self.config.name or "Arena",
            width = A.w, height = A.h, tile_world = 1.0,
            hero_start = A.hero_start,
            rooms = { {
                id = "pit", name = self.config.name or "The Pit",
                rect = { x = A.pad, y = A.pad, w = A.w - A.pad * 2, h = A.h - A.pad * 2 },
                anchors = {},
            } },
            corridors = {},
        }
    end
    self.map = Flow.build_map(def)

    -- Perimeter spawn points (the swarm pours in from all sides).
    self.spawns = (self.config.arena and self.config.arena.spawns) or nil
    if not self.spawns then
        local inset = A.pad + 1
        self.spawns = {
            { x = inset, y = inset },
            { x = A.w - inset - 1, y = inset },
            { x = inset, y = A.h - inset - 1 },
            { x = A.w - inset - 1, y = A.h - inset - 1 },
            { x = math.floor(A.w * 0.5), y = inset },
            { x = math.floor(A.w * 0.5), y = A.h - inset - 1 },
        }
    end

    -- Cheap, self-lit stage (emissive only — scene lighting barely reaches here).
    -- SKIPPED when the loaded scene already authors the stage as real nodes
    -- (config.arena.scene_stage, set by game_boot for game.pescene's "Stage" group):
    -- the spawn/clamp logic above is pure data and still runs; only the VISUALS move
    -- to the scene file. The authored floor/walls/sigils must match these transforms.
    if not (self.config.arena and self.config.arena.scene_stage) then
        local cx = A.w * 0.5 - 0.5
        local cz = A.h * 0.5 - 0.5
        -- The floor VISUAL may extend past the playable bounds (config.arena.
        -- floor_extent) so an ultra-wide camera never shows the raw scene around
        -- the pit; the walls still mark the real gameplay edge.
        local fx = (self.config.arena and self.config.arena.floor_extent) or {}
        local fw = fx.width or A.w
        local fh = fx.height or A.h
        Art.cube("Floor", vec3(cx, -0.05, cz), vec3(fw, 0.1, fh), theme.floor or { 0.26, 0.24, 0.32 }, self.groups.world, 0.9, theme.floor_texture)
        local wall = theme.wall or { 0.42, 0.36, 0.50 }
        Art.cube("Wall_N", vec3(cx, 0.5, A.pad - 0.5), vec3(A.w, 1.2, 0.4), wall, self.groups.world, 0.8)
        Art.cube("Wall_S", vec3(cx, 0.5, A.h - A.pad - 0.5), vec3(A.w, 1.2, 0.4), wall, self.groups.world, 0.8)
        Art.cube("Wall_W", vec3(A.pad - 0.5, 0.5, cz), vec3(0.4, 1.2, A.h), wall, self.groups.world, 0.8)
        Art.cube("Wall_E", vec3(A.w - A.pad - 0.5, 0.5, cz), vec3(0.4, 1.2, A.h), wall, self.groups.world, 0.8)
        local sigil = theme.spawn_sigil or { 0.92, 0.26, 0.22 }
        for i, sp in ipairs(self.spawns) do
            Art.cylinder("Spawn_" .. i, vec3(sp.x, 0.03, sp.y), vec3(1.1, 0.04, 1.1), sigil, self.groups.world, 1.2)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Hero (auto-fighting actor; the "hero seat" cards upgrade it)
-- ---------------------------------------------------------------------------

-- The currently-selected hero class spec (or nil when the mode defines none).
function Duel:active_class()
    local list = self.config.hero and self.config.hero.classes
    if not list or #list == 0 then return nil end
    for _, c in ipairs(list) do
        if c.id == self.hero_class then return c end
    end
    return list[1]
end

function Duel:create_hero()
    local spec = self.hero_spec
    -- Apply the chosen hero CLASS (manual arena) on top of the mode's hero spec:
    -- each class is an attack identity (melee cleave vs ranged bolt vs scatter)
    -- with its own stats + sprite. active_class() is nil for non-manual modes.
    local cls = self:active_class()
    local hp_max = (cls and cls.hp_max) or spec.hp_max
    local cdps = (cls and cls.dps) or spec.dps
    local ccleave = (cls and cls.cleave) or spec.cleave
    local crange = (cls and cls.attack_range) or spec.attack_range
    local cspeed = (cls and cls.speed) or spec.speed
    local ckite = (cls and cls.kite_speed) or spec.kite_speed
    local hero = {
        x = self.arena.hero_start.x, z = self.arena.hero_start.y,
        hp = hp_max, hp_max = hp_max,
        dps = cdps, base_dps = cdps,
        cleave = ccleave, attack_range = crange,
        speed = cspeed, base_speed = cspeed,
        kite_speed = ckite, base_kite_speed = ckite,
        body_radius = spec.body_radius,
        attack_type = (cls and cls.attack) or (self.manual_hero and "ranged") or "melee",
        fire_interval = (cls and cls.fire_interval) or (self.config.hero and self.config.hero.fire_interval) or 0.28,
        bolt_color = (cls and cls.bolt_color) or { 1.0, 0.90, 0.42 },
        bolt_scale = (cls and cls.bolt_scale) or 0.34,
        phase = 0.0, facing = 0.0, attack_flash = 0.0,
        dead = false, death_t = 0.0,
        lifesteal = (cls and cls.lifesteal) or 0.0,
        regen = (cls and cls.regen) or 0.0,
        whirl = (cls and cls.whirl) or 0, whirl_t = 0.0,
        armor = (cls and cls.armor) or 0.0, thorns = 0.0, dash = 0,
        crit_chance = (cls and cls.crit_chance) or 0.03,
        pickup_range = PICKUP_RANGE_BASE, gold_find = 1.0,
        -- Normal dodge. Light/Heavy load tiers will later retune these numbers
        -- (charges/dist/iframes/recharge) without touching the machinery.
        dodge_charges = 1, dodge_charges_max = 1,
        dodge_recharge = DODGE_RECHARGE, dodge_recharge_t = 0.0,
        dodge_dist = DODGE_DIST, dodge_iframes = DODGE_IFRAMES,
        dodge_t = 0.0, dodge_iframe_t = 0.0, dodge_dx = 0.0, dodge_dz = 1.0,
        -- Transient per-frame multipliers a mode's mechanic may set in
        -- on_combat_tick to slow/shrink the hero WITHOUT corrupting card-stacked
        -- stats (ice slow, mud, sandstorm). Mode-owned: set every tick, 1.0 = off.
        move_mult = 1.0, range_mult = 1.0,
        thought = "",
    }
    hero.base_stats = {
        hp_max = hero.hp_max,
        dps = hero.dps,
        cleave = hero.cleave,
        attack_range = hero.attack_range,
        speed = hero.speed,
        kite_speed = hero.kite_speed,
        armor = hero.armor,
        lifesteal = hero.lifesteal,
        regen = hero.regen,
        whirl = hero.whirl,
        thorns = hero.thorns,
        dash = hero.dash,
        crit_chance = hero.crit_chance,
        pickup_range = hero.pickup_range,
        gold_find = hero.gold_find,
    }
    -- fire_interval is kept as a sibling base field rather than folded into
    -- base_stats: recompute_hero_stats / gear_preview_stats both reset it from here
    -- before applying attack-speed gear, so it never double-counts. Keep the two in
    -- sync if either the field or those reset paths move.
    hero.base_fire_interval = hero.fire_interval
    -- "Replace the hero with the 2D souls-knight everywhere": every duel mode
    -- supplies its own themed actor, so force the knight rig here (set
    -- Duel.FORCE_KNIGHT = false to fall back to the mode's own rig).
    local actor_spec = spec.actor
    -- ADOPT an authored hero node (config.hero.scene_node, e.g. game.pescene's
    -- "Hero" root + "Hero Body" sprite child) instead of building a rig: the scene
    -- owns the static hero, the Duel only drives it. The base pose mirrors
    -- flat_hero_actor's body (local y 1.1, flat-laid -90° via the top-down view).
    -- Falls back to the built rig if the authored node isn't present.
    local adopt_name = self.config.hero and self.config.hero.scene_node
    if adopt_name and scene.find_model then
        local root = scene.find_model(adopt_name)
        local body = scene.find_model((self.config.hero and self.config.hero.scene_body) or "Hero Body")
        if Art.valid(root) and Art.valid(body) then
            hero.actor = { spec = {}, parts = { body = body }, base = {
                body = { position = { 0.0, 1.1, 0.0 }, scale = { 1.0, 1.0, 1.0 }, rotation = { -90.0, 0.0, 0.0 } },
            } }
            hero.root = root
            hero.parts = hero.actor.parts
            hero.adopted = true
            -- Re-dress on the next top-down tick: the view's dress-once guard keys
            -- off a root-handle change, but an adopted root is reused across class
            -- picks / R-resets, so clear it or a class swap keeps the old sprite.
            self._topdown_hero_root = nil
        end
    end
    if not hero.adopted then
        if self.manual_hero then
            -- Top-down manual hero: a single flat sprite quad, NOT the knight rig
            -- (skips loading ~1.2 MB of knight textures that would only be hidden).
            -- The class picks the sprite (ranger/brawler/sower), falling back to the
            -- mode's default hero texture.
            local tex = (cls and cls.sprite_texture) or (self.config.hero and self.config.hero.sprite_texture)
            actor_spec = flat_hero_actor(tex)
        elseif Duel.FORCE_KNIGHT ~= false then
            actor_spec = default_hero_actor(self.theme)
        end
        hero.actor = (actor_spec and actor_spec.soft_cape)
            and Art.build_soft_actor(actor_spec, self.groups.actors)
            or  Art.build_actor(actor_spec, self.groups.actors)
        hero.root = hero.actor.root
        hero.parts = hero.actor.parts
    end
    if pe_log then
        local np = 0; for _ in pairs(hero.parts or {}) do np = np + 1 end
        pe_log(string.format("[KNIGHT] forced=%s soft=%s root=%s parts=%d cape=%s",
            tostring(Duel.FORCE_KNIGHT ~= false),
            tostring(actor_spec and actor_spec.soft_cape ~= nil),
            tostring(Art.valid(hero.root)), np,
            tostring(hero.parts and Art.valid(hero.parts.soft_cape))))
    end
    -- An attack-range aura ring, if the rig didn't already provide one. Skipped for
    -- an adopted hero: it would parent to the authored (never-deleted) root and leak
    -- a ring per re-create; the manual arena parks the aura offstage regardless.
    if not hero.adopted and not hero.parts.aura then
        hero.parts.aura = Art.cylinder("Hero_Aura", vec3(0.0, 0.04, 0.0),
            vec3(spec.attack_range * 2.0, 0.03, spec.attack_range * 2.0),
            (self.theme.aura or { 0.42, 0.70, 0.95, 0.5 }), hero.root, 0.7)
    end
    -- World character scale — make the hero read clearly at the iso distance.
    local cs = Art.s("char")
    local base = (spec.actor and spec.actor.scale) or 1.0
    hero.world_scale = base * cs
    if Art.valid(hero.root) then
        hero.root:set_scale(vec3(hero.world_scale, hero.world_scale, hero.world_scale))
        hero.root:set_position(vec3(hero.x, 0.0, hero.z))
    end
    self.hero = hero
end

function Duel:swarm_centroid()
    local n, sx, sz = 0, 0.0, 0.0
    for _, c in ipairs(self.creeps) do
        if c.alive then n = n + 1; sx = sx + c.x; sz = sz + c.z end
    end
    if n == 0 then return nil end
    return sx / n, sz / n
end

function Duel:nearest_creep(hero)
    local best, best_d
    for _, c in ipairs(self.creeps) do
        if c.alive then
            local dx, dz = c.x - hero.x, c.z - hero.z
            local d = dx * dx + dz * dz
            if not best or d < best_d then best, best_d = c, d end
        end
    end
    if not best then return nil, nil end
    return best, math.sqrt(best_d)
end

function Duel:move_hero(hero, dirx, dirz, speed, dt)
    local A = self.arena
    local minx, maxx, minz, maxz = arena_actor_bounds(A, 0.8)
    speed = speed * (hero.move_mult or 1.0)
    hero.x = clampn(hero.x + dirx * speed * dt, minx, maxx)
    hero.z = clampn(hero.z + dirz * speed * dt, minz, maxz)
    if dirx * dirx + dirz * dirz > 0.0001 then hero.facing = math.atan(dirx, dirz) end
end

-- Normal dodge: spend a charge for a short locked-line dash with an
-- invulnerability window (enforced centrally by apply_hero_damage, never by
-- individual enemies). Direction = movement input; hero facing when stationary.
function Duel:try_dodge(dirx, dirz)
    local hero = self.hero
    if not hero or hero.dead then return false end
    if hero.dodge_t > 0.0 or (hero.dodge_charges or 0) < 1 then return false end
    local mag = math.sqrt((dirx or 0.0) ^ 2 + (dirz or 0.0) ^ 2)
    if mag > 0.001 then
        dirx, dirz = dirx / mag, dirz / mag
    else
        dirx, dirz = math.sin(hero.facing or 0.0), math.cos(hero.facing or 0.0)
    end
    if hero.dodge_charges >= (hero.dodge_charges_max or 1) then
        hero.dodge_recharge_t = hero.dodge_recharge -- timer idles while full; arm it now
    end
    hero.dodge_charges = hero.dodge_charges - 1
    hero.dodge_t = DODGE_DUR
    hero.dodge_speed = (hero.dodge_dist or DODGE_DIST) / DODGE_DUR
    hero.dodge_iframe_t = hero.dodge_iframes or DODGE_IFRAMES
    hero.dodge_dx, hero.dodge_dz = dirx, dirz
    hero.facing = math.atan(dirx, dirz)
    self:haptic(15)
    Art.burst("ath_dodge", vec3(hero.x, 0.2, hero.z),
        { preset = "hero_take", count = 10, life_max = 0.25, spawn_radius = 0.3, size_max = 0.14,
          color_start = vec4(0.75, 0.85, 1.0, 0.9), gravity = vec3(0.0, 0.9, 0.0) })
    return true
end

function Duel:hero_attack(hero, dt)
    local in_range = {}
    local eff_range = hero.attack_range * (hero.range_mult or 1.0)
    local r2 = eff_range * eff_range
    for _, c in ipairs(self.creeps) do
        if c.alive then
            local dx, dz = c.x - hero.x, c.z - hero.z
            local d = dx * dx + dz * dz
            if d <= r2 then in_range[#in_range + 1] = { c = c, d = d } end
        end
    end
    if #in_range == 0 then return end
    table.sort(in_range, function(a, b) return a.d < b.d end)
    hero.attack_flash = 0.12
    local attack_rate = (hero.base_fire_interval or hero.fire_interval or 0.28) / (hero.fire_interval or 0.28)
    local targets = math.min(hero.cleave, #in_range)
    for i = 1, targets do
        local mult = (i == 1) and 1.0 or 0.45
        local c = in_range[i].c
        local dx, dz = c.x - hero.x, c.z - hero.z
        local d = math.sqrt(dx * dx + dz * dz)
        local nx, nz = (d > 0.001) and dx / d or 0.0, (d > 0.001) and dz / d or 0.0
        -- Knock scaled by dt because melee damage is continuous: a gentle shove,
        -- not the one-shot punt a discrete bolt/whirl delivers.
        if self:hit_creep(c, hero.dps * attack_rate * mult * dt, nx * CREEP_KNOCK_MELEE * dt, nz * CREEP_KNOCK_MELEE * dt, { melee = true }) then
            if hero.lifesteal > 0.0 then hero.hp = math.min(hero.hp_max, hero.hp + hero.lifesteal) end
        end
    end
end

function Duel:hero_whirl(hero, dt)
    if (hero.whirl or 0) <= 0 then return end
    hero.whirl_t = (hero.whirl_t or 0.0) - dt
    if hero.whirl_t > 0.0 then return end
    hero.whirl_t = hero.attack_type == "melee" and 0.65 or WHIRL_CD
    local radius = WHIRL_RADIUS_BASE + 0.4 * hero.whirl
    if hero.attack_type == "melee" then radius = math.max(radius, hero.attack_range or radius) end
    local r2 = radius * radius
    local damage = hero.dps * (hero.attack_type == "melee" and 0.8 or 0.6) * hero.whirl
    for _, c in ipairs(self.creeps) do
        if c.alive then
            local dx, dz = c.x - hero.x, c.z - hero.z
            local dd = dx * dx + dz * dz
            if dd <= r2 then
                local d = math.sqrt(dd)
                local nx, nz = (d > 0.001) and dx / d or 0.0, (d > 0.001) and dz / d or 0.0
                if self:hit_creep(c, damage, nx * CREEP_KNOCK_MELEE * 1.8, nz * CREEP_KNOCK_MELEE * 1.8) then
                    if hero.lifesteal > 0.0 then hero.hp = math.min(hero.hp_max, hero.hp + hero.lifesteal) end
                end
            end
        end
    end
    Art.burst("ath_duel_whirl", vec3(hero.x, 0.5, hero.z),
        { preset = "hero_take", count = 18, life_max = 0.28, spawn_radius = radius * 0.5, noise_strength = 4.0, size_max = 0.18 })
end

-- ---------------------------------------------------------------------------
-- Manual-hero RANGED attack — pooled bolts.
-- POOLING IS LOAD-BEARING here too: deleting scene nodes mid-combat shuffles
-- node storage (swap-and-pop) and corrupts other sprites' draw constants, so we
-- pre-build a fixed pool of opaque bolt spheres once and PARK + REUSE them
-- (never delete). Opaque spheres also stay off the alpha-cut RT path.
-- ---------------------------------------------------------------------------
local HPROJ_POOL = 28
local HPROJ_SPEED = 19.0
local HPROJ_HIT_R = 0.7
local HPROJ_LIFE = 1.4

function Duel:hproj_hide(p)
    p.active = false
    if Art.valid(p.node) then
        p.node:set_position(vec3(-1000.0, -1000.0, -1000.0))
        p.node:set_scale(vec3(0.0001, 0.0001, 0.0001))
    end
end

function Duel:ensure_hero_projectiles()
    if self.hproj then return end
    if not (self.groups and self.groups.actors) then return end
    self.hproj = {}
    for i = 1, HPROJ_POOL do
        local node = Art.sphere("HeroBolt_" .. i, vec3(-1000.0, -1000.0, -1000.0),
            vec3(0.0001, 0.0001, 0.0001), { 1.0, 0.90, 0.42, 1.0 }, self.groups.actors, 1.5)
        self.hproj[i] = { node = node, active = false }
    end
end

function Duel:reset_hero_projectiles()
    if not self.hproj then return end
    for _, p in ipairs(self.hproj) do self:hproj_hide(p) end
end

function Duel:spawn_hero_bolt(hero, target)
    self:ensure_hero_projectiles()
    if not self.hproj then return end
    local slot
    for _, p in ipairs(self.hproj) do
        if not p.active then slot = p; break end
    end
    if not slot then return end -- pool exhausted this frame; drop the bolt (no delete)
    local dx, dz = target.x - hero.x, target.z - hero.z
    local d = math.sqrt(dx * dx + dz * dz)
    if d < 0.001 then d, dx, dz = 1.0, 0.0, 1.0 end
    slot.active = true
    slot.x, slot.z = hero.x, hero.z
    slot.vx, slot.vz = dx / d * HPROJ_SPEED, dz / d * HPROJ_SPEED
    slot.life = HPROJ_LIFE
    slot.damage = (hero.dps or 10.0) * 0.6
    slot.trail_t = 0.03
    local bc = hero.bolt_color or { 1.0, 0.90, 0.42 }
    local bs = hero.bolt_scale or 0.34
    slot.col = bc
    if Art.valid(slot.node) then
        material.set(slot.node, "base_color", vec4(bc[1], bc[2], bc[3], 1.0))
        material.set(slot.node, "emissive", vec3(bc[1] * 2.2, bc[2] * 2.2, bc[3] * 2.2))
        -- Tracer look: stretch the sphere along its flight line and yaw it into
        -- the travel direction (velocity is constant, so orient once at spawn).
        slot.node:set_scale(vec3(bs * 0.55, bs * 0.55, bs * 2.1))
        slot.node:set_rotation(vec3(0.0, math.deg(math.atan(slot.vx, slot.vz)), 0.0))
        slot.node:set_position(vec3(slot.x, 0.7, slot.z))
    end
end

function Duel:hero_fire(hero, dt)
    hero.fire_t = (hero.fire_t or 0.0) - dt
    if hero.fire_t > 0.0 then return end
    local eff_range = (hero.attack_range or 9.0) * (hero.range_mult or 1.0)
    local r2 = eff_range * eff_range
    local cand = {}
    for _, c in ipairs(self.creeps) do
        if c.alive then
            local dx, dz = c.x - hero.x, c.z - hero.z
            local d = dx * dx + dz * dz
            if d <= r2 then cand[#cand + 1] = { c = c, d = d } end
        end
    end
    if #cand == 0 then return end
    table.sort(cand, function(a, b) return a.d < b.d end)
    hero.fire_t = hero.fire_interval or 0.28
    hero.attack_flash = 0.12
    local shots = math.max(1, math.floor(hero.cleave or 1))
    for i = 1, math.min(shots, #cand) do
        self:spawn_hero_bolt(hero, cand[i].c)
    end
    local mc = hero.bolt_color or { 1.0, 0.92, 0.5 }
    Art.burst("ath_hero_muzzle", vec3(hero.x, 0.7, hero.z),
        { preset = "hero_take", count = 6, life_max = 0.16, spawn_radius = 0.18, size_max = 0.12,
          color_start = vec4(mc[1], mc[2], mc[3], 1.0) })
end

function Duel:update_hero_projectiles(dt)
    if not self.hproj then return end
    local hero = self.hero
    local A = self.arena
    local trail_budget = 6 -- particle emits per frame across all bolts
    for _, p in ipairs(self.hproj) do
        if p.active then
            p.x = p.x + p.vx * dt
            p.z = p.z + p.vz * dt
            p.life = p.life - dt
            local hit = nil
            for _, c in ipairs(self.creeps) do
                if c.alive then
                    local dx, dz = c.x - p.x, c.z - p.z
                    if dx * dx + dz * dz <= HPROJ_HIT_R * HPROJ_HIT_R then hit = c; break end
                end
            end
            local off = p.x < A.pad or p.x > A.w - A.pad or p.z < A.pad or p.z > A.h - A.pad
            if hit then
                -- hit_creep flips alive=false on kill; update_creeps then counts
                -- the kill + drops loot, same path as the melee hero. The bolt
                -- punts the creep along its flight direction (discrete = full knock).
                local d = math.sqrt(p.vx * p.vx + p.vz * p.vz)
                local nx, nz = (d > 0.001) and p.vx / d or 0.0, (d > 0.001) and p.vz / d or 0.0
                local killed, was_crit = self:hit_creep(hit, p.damage,
                    nx * CREEP_KNOCK_BOLT, nz * CREEP_KNOCK_BOLT, { discrete = true })
                if killed and hero and (hero.lifesteal or 0.0) > 0.0 then
                    hero.hp = math.min(hero.hp_max, hero.hp + hero.lifesteal)
                end
                local ic = was_crit and { 1.0, 0.72, 0.2 } or (p.col or { 1.0, 0.92, 0.5 })
                Art.burst("ath_hero_hit_" .. tostring(hit.id), vec3(p.x, 0.6, p.z),
                    { preset = "enemy_take", count = was_crit and 18 or 10,
                      life_max = was_crit and 0.26 or 0.18, spawn_radius = was_crit and 0.28 or 0.16,
                      size_max = was_crit and 0.22 or 0.16,
                      color_start = vec4(ic[1], ic[2], ic[3], 1.0) })
                self:hproj_hide(p)
            elseif p.life <= 0.0 or off then
                self:hproj_hide(p)
            elseif Art.valid(p.node) then
                p.node:set_position(vec3(p.x, 0.7, p.z))
                -- Fading ember trail behind the tracer (budgeted per frame).
                p.trail_t = (p.trail_t or 0.0) - dt
                if p.trail_t <= 0.0 and trail_budget > 0 then
                    trail_budget = trail_budget - 1
                    p.trail_t = 0.055
                    local tc = p.col or { 1.0, 0.9, 0.4 }
                    Art.burst("ath_bolt_trail", vec3(p.x, 0.7, p.z),
                        { preset = "hero_take", count = 2, life_max = 0.16, spawn_radius = 0.05,
                          size_max = 0.10, noise_strength = 0.6,
                          color_start = vec4(tc[1], tc[2], tc[3], 0.9) })
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Hit feedback — one funnel for damaging a creep so every source (melee cleave,
-- whirl, thorns, hero bolt) lights the flash + applies the same knockback model.
-- Discrete hits (bolts) roll a REAL crit here and pop a floating damage number;
-- continuous melee dt-damage aggregates per creep and flushes on a short cadence
-- (see update_creeps) so numbers stay readable instead of per-frame confetti.
-- ---------------------------------------------------------------------------
function Duel:roll_crit()
    local hero = self.hero
    return hero and math.random() < (hero.crit_chance or 0.0)
end

function Duel:hit_creep(c, amount, kx, kz, opts)
    if not c or not c.alive then return false end
    local crit = false
    if opts and opts.discrete then
        crit = self:roll_crit()
        if crit then amount = amount * CRIT_MULT end
        self:spawn_damage_number(c.x, c.z, amount, crit)
    elseif opts and opts.melee then
        c._mdmg = (c._mdmg or 0.0) + amount
        c._mdmg_t = c._mdmg_t or MELEE_FLUSH_T
    end
    local killed = Creep.damage(c, amount)
    if not killed then
        c.hit_flash = HIT_FLASH_T
        if (kx and kx ~= 0.0) or (kz and kz ~= 0.0) then Creep.knock(c, kx or 0.0, kz or 0.0) end
    end
    return killed, crit
end

-- Flush a creep's aggregated melee packet: roll the crit for the window (a crit
-- deals the same packet AGAIN as bonus damage, so crit_chance genuinely raises
-- melee dps) and pop one number.
function Duel:flush_melee_packet(c)
    local amt = c._mdmg or 0.0
    if amt < 0.5 then c._mdmg = 0.0; c._mdmg_t = nil; return end
    local crit = self:roll_crit()
    if crit and c.alive then
        if Creep.damage(c, amt) then c.alive = false end
        amt = amt * CRIT_MULT
    end
    self:spawn_damage_number(c.x, c.z, amt, crit)
    c._mdmg = 0.0
    c._mdmg_t = nil
end

-- ---------------------------------------------------------------------------
-- Floating damage numbers — a fixed pool of screen-space text quads projected
-- from world positions (runtime_ui.set_quad is retained + cheap per frame).
-- Crits pop bigger, gold pickups reuse the same pool tinted gold.
-- ---------------------------------------------------------------------------
function Duel:spawn_damage_number(x, z, amount, crit, opts)
    if not (runtime_ui and runtime_ui.set_quad) then return end
    self.dmgnums = self.dmgnums or {}
    local n = math.floor((tonumber(amount) or 0.0) + 0.5)
    if n < 1 and not (opts and opts.text) then return end
    local slot
    for i = 1, DMGNUM_POOL do
        local e = self.dmgnums[i]
        if not e then
            e = { id = "dmg_" .. i }
            self.dmgnums[i] = e
            slot = e
            break
        elseif not e.active then
            slot = e
            break
        end
    end
    if not slot then return end -- pool saturated this frame; drop the popup
    slot.active = true
    slot.x = x
    slot.z = z
    slot.t = 0.0
    slot.text = (opts and opts.text) or tostring(n)
    slot.crit = crit == true
    slot.color = (opts and opts.color) or (crit and { 1.0, 0.72, 0.2 } or { 0.97, 0.97, 1.0 })
    slot.jx = (math.random() - 0.5) * 0.8
end

function Duel:update_damage_numbers(dt)
    local list = self.dmgnums
    if not list then return end
    local vp_mat = Art.view_projection and Art.view_projection() or nil
    for _, e in ipairs(list) do
        if e.active then
            e.t = e.t + dt
            if e.t >= DMGNUM_LIFE or not vp_mat then
                e.active = false
                if runtime_ui.remove then runtime_ui.remove(self.hud, e.id) end
            else
                local k = e.t / DMGNUM_LIFE
                local sx, sy = Art.world_to_screen(vp_mat, e.x + e.jx, 0.8, e.z)
                if sx then
                    -- fit=true lets the Text widget auto-size to the glyphs; a
                    -- fixed small box clips the (large-font) number to nothing.
                    local fs = (e.crit and 1.9 or 1.2) * (1.0 + 0.25 * math.min(1.0, e.t * 8.0))
                    local a = k < 0.65 and 1.0 or (1.0 - (k - 0.65) / 0.35)
                    runtime_ui.set_quad(self.hud, e.id, {
                        x = sx - 34.0, y = sy - 52.0 * k - 30.0, style = "text", fit = true,
                        body = e.text,
                        fill = { 0.0, 0.0, 0.0, 0.0 }, border = { 0.0, 0.0, 0.0, 0.0 },
                        text_color = { e.color[1], e.color[2], e.color[3], a },
                        font_scale = fs * Art.s("text") / (Art._ui_scale or 1.0),
                        align_h = "center", no_input = true, bring_to_front = true, z = 8000.0,
                    })
                else
                    e.active = false
                    if runtime_ui.remove then runtime_ui.remove(self.hud, e.id) end
                end
            end
        end
    end
end

function Duel:clear_damage_numbers()
    for _, e in ipairs(self.dmgnums or {}) do
        if e.active then
            e.active = false
            if runtime_ui and runtime_ui.remove then runtime_ui.remove(self.hud, e.id) end
        end
    end
end

-- A short freeze-frame beat on meaty kills. Real dt keeps ticking; sim dt is
-- scaled way down for the duration (see Duel:update).
function Duel:hitstop(seconds)
    self.hitstop_t = math.max(self.hitstop_t or 0.0, seconds or 0.05)
end

-- ---------------------------------------------------------------------------
-- Death animation — a dead creep's rig spins flat + flashes out for a beat
-- BEFORE being parked (Creep.destroy is deferred, pooling untouched). Purely
-- visual: the creep is already dead, counted, and has dropped its loot. Only
-- rotation/material writes (per-frame scale on sprites is unreliable).
-- ---------------------------------------------------------------------------
function Duel:begin_death_anim(c)
    if not (c and Art.valid(c.root)) then
        Creep.destroy(c)
        return
    end
    self.dying = self.dying or {}
    local dur = (c.stats and c.stats.boss) and 0.30 or 0.16
    self.dying[#self.dying + 1] = { c = c, t = dur, dur = dur, dir = (c.id % 2 == 0) and 1.0 or -1.0 }
end

function Duel:update_dying(dt)
    local list = self.dying
    if not list or #list == 0 then return end
    local keep = {}
    for _, d in ipairs(list) do
        d.t = d.t - dt
        local c = d.c
        if d.t <= 0.0 or not Art.valid(c.root) then
            Creep.destroy(c)
        else
            local k = d.t / d.dur
            c.root:set_rotation(vec3(0.0, (1.0 - k) * 640.0 * d.dir, 0.0))
            local body = c.parts and c.parts.body
            if Art.valid(body) then
                local e = 7.0 * k
                material.set(body, "emissive", vec3(e, e, e))
            end
            keep[#keep + 1] = d
        end
    end
    self.dying = keep
end

function Duel:flush_dying()
    for _, d in ipairs(self.dying or {}) do Creep.destroy(d.c) end
    self.dying = {}
end

-- ---------------------------------------------------------------------------
-- Ground pickups — kills scatter PHYSICAL gold coins and item beacons instead
-- of silently crediting the counters. Coins magnetise to the hero inside
-- hero.pickup_range and bank on contact; item beacons are rarity-tinted discs
-- picked up by walking over them. Both are pooled nodes (parked offstage, never
-- deleted mid-combat — the same swap-and-pop rule as every other combat node).
-- ---------------------------------------------------------------------------
local PICKUP_PARK = vec3(-1000.0, -1000.0, -1000.0)

function Duel:ensure_pickup_pools()
    if self.coins or not (self.groups and self.groups.world) then return end
    self.coins = {}
    for i = 1, COIN_POOL do
        local node = Art.cylinder("Coin_" .. i, PICKUP_PARK, vec3(0.34, 0.06, 0.34),
            { 1.0, 0.84, 0.25, 1.0 }, self.groups.world, 1.8)
        self.coins[i] = { node = node, active = false }
    end
    self.beacons = {}
    for i = 1, BEACON_POOL do
        -- Root group carries disc + icon so the two share one transform: a
        -- screen-projected icon drifted off the circle per-machine (round 4);
        -- a child quad atop the disc cannot.
        local root = Art.group("ItemBeacon_" .. i, self.groups.world)
        root:set_position(PICKUP_PARK)
        -- 2.1 disc + 1.5 icon = the round-4 user-confirmed proportions: the
        -- rarity ring stays visible around the icon art.
        local disc = Art.cylinder("BeaconDisc_" .. i, vec3(0.0, 0.0, 0.0), vec3(2.1, 0.05, 2.1),
            { 0.7, 0.7, 0.8, 1.0 }, root, 1.4)
        local icon = Art.part({
            name = "BeaconIcon_" .. i, kind = "quad", quad_width = 1.5, quad_height = 1.5,
            position = { 0.0, 0.16, 0.0 }, rotation = { -90.0, 0.0, 0.0 },
            texture = "Textures/ui/items/weapon.png", emissive_texture = true,
        }, root)
        self.beacons[i] = { node = root, disc = disc, icon = icon, pool_index = i, active = false }
    end
end

local function park_pickup(e)
    e.active = false
    if Art.valid(e.node) then e.node:set_position(PICKUP_PARK) end
end

function Duel:spawn_coin(x, z, value)
    self:ensure_pickup_pools()
    if not self.coins then return end
    local slot
    for _, e in ipairs(self.coins) do
        if not e.active then slot = e; break end
    end
    if not slot then
        -- Pool saturated: merge the value into an active coin so no gold is lost.
        for _, e in ipairs(self.coins) do
            if e.active then e.value = e.value + (value or 1); return end
        end
        return
    end
    slot.active = true
    slot.x, slot.z = x, z
    slot.value = value or 1
    local ang = math.random() * 6.2831
    local sp = 2.5 + math.random() * 2.5
    slot.vx, slot.vz = math.sin(ang) * sp, math.cos(ang) * sp
    if Art.valid(slot.node) then slot.node:set_position(vec3(x, 0.22, z)) end
end

function Duel:spawn_item_beacon(x, z, item)
    self:ensure_pickup_pools()
    if not (item and self.beacons) then return end
    local slot
    for _, e in ipairs(self.beacons) do
        if not e.active then slot = e; break end
    end
    if not slot then
        -- No free beacon: fall back to the old straight-to-bag path.
        if Inventory.add_item(self, item) then self:set_flash("Found " .. tostring(item.name or item.id)) end
        return
    end
    slot.active = true
    slot.x, slot.z = x, z
    slot.item = item
    slot.retry_t = 0.0
    local col = RARITY_COLOR[item.rarity or "common"] or RARITY_COLOR.common
    if Art.valid(slot.node) then
        slot.node:set_position(vec3(x, 0.06, z))
        material.set(slot.disc, "base_color", vec4(col[1], col[2], col[3], 1.0))
        local icon = Inventory.SLOT_ICON[item.slot]
        if icon and Art.valid(slot.icon) then
            Art.texture(slot.icon, "Textures/" .. icon)
            Art.texture(slot.icon, "Textures/" .. icon, "emissive")
        end
    end
end

function Duel:update_pickups(dt)
    local hero = self.hero
    if not (hero and self.coins) then return end
    local pr = hero.pickup_range or PICKUP_RANGE_BASE
    local gf = hero.gold_find or 1.0
    for _, e in ipairs(self.coins) do
        if e.active then
            local dx, dz = hero.x - e.x, hero.z - e.z
            local d = math.sqrt(dx * dx + dz * dz)
            if not hero.dead and d <= COIN_COLLECT_R then
                self.gold = (self.gold or 0) + math.max(1, math.floor(e.value * gf + 0.5))
                self._gold_pop = (self._gold_pop or 0) + math.max(1, math.floor(e.value * gf + 0.5))
                park_pickup(e)
            else
                if not hero.dead and d <= pr and d > 0.001 then
                    -- Magnet: accelerate toward the hero, harder the closer it gets.
                    local pull = 30.0 + 40.0 * (1.0 - d / pr)
                    e.vx = e.vx + dx / d * pull * dt
                    e.vz = e.vz + dz / d * pull * dt
                else
                    e.vx = e.vx * math.max(0.0, 1.0 - 6.0 * dt)
                    e.vz = e.vz * math.max(0.0, 1.0 - 6.0 * dt)
                end
                local sp = math.sqrt(e.vx * e.vx + e.vz * e.vz)
                if sp > 22.0 then e.vx, e.vz = e.vx / sp * 22.0, e.vz / sp * 22.0 end
                e.x = e.x + e.vx * dt
                e.z = e.z + e.vz * dt
                if Art.valid(e.node) then e.node:set_position(vec3(e.x, 0.22, e.z)) end
            end
        end
    end
    -- Aggregate the gold popup so a coin shower reads as one rising "+N".
    self._gold_pop_t = math.max(0.0, (self._gold_pop_t or 0.0) - dt)
    if (self._gold_pop or 0) > 0 and self._gold_pop_t <= 0.0 then
        self:spawn_damage_number(hero.x, hero.z, 0, false,
            { text = "+" .. tostring(self._gold_pop), color = { 1.0, 0.85, 0.3 } })
        Art.burst("ath_gold_pop", vec3(hero.x, 0.6, hero.z),
            { preset = "hero_take", count = 6, life_max = 0.22, spawn_radius = 0.25, size_max = 0.12,
              color_start = vec4(1.0, 0.85, 0.3, 1.0), gravity = vec3(0.0, 2.0, 0.0) })
        self._gold_pop = 0
        self._gold_pop_t = 0.45
    end
    local pickup_vp = Art.view_projection and Art.view_projection() or nil
    local mx, my = ui_pointer()
    local hovered
    for _, e in ipairs(self.beacons or {}) do
        if e.active then
            e.retry_t = math.max(0.0, (e.retry_t or 0.0) - dt)
            local item = e.item
            local col = RARITY_COLOR[(item and item.rarity) or "common"] or RARITY_COLOR.common
            if Art.valid(e.node) then
                local p = 0.7 + 0.6 * math.abs(math.sin(self.realtime * 5.0))
                material.set(e.disc, "emissive", vec3(col[1] * p, col[2] * p, col[3] * p))
            end
            if pickup_vp and item and mx and runtime_ui and runtime_ui.set_quad then
                local sx, sy = Art.world_to_screen(pickup_vp, e.x, 0.35, e.z)
                if sx then
                    local ex, ey = Art.world_to_screen(pickup_vp, e.x + 1.05, 0.35, e.z)
                    local zx, zy = Art.world_to_screen(pickup_vp, e.x, 0.35, e.z + 1.05)
                    local hr = 36.0
                    if ex and zx then
                        hr = math.min(110.0, math.max(hr, math.sqrt(
                            (ex - sx) ^ 2 + (ey - sy) ^ 2 + (zx - sx) ^ 2 + (zy - sy) ^ 2)))
                    end
                    local dx, dy = mx - sx, my - sy
                    local d2 = dx * dx + dy * dy
                    if d2 <= hr * hr and (not hovered or d2 < hovered.d2) then
                        hovered = { item = item, col = col, sx = sx, sy = sy, d2 = d2 }
                    end
                end
            end
            local dx, dz = hero.x - e.x, hero.z - e.z
            local br = math.max(BEACON_COLLECT_R, pr)
            if not hero.dead and e.retry_t <= 0.0 and (dx * dx + dz * dz) <= br * br then
                if Inventory.add_item(self, e.item) then
                    self:log("found " .. tostring(e.item.id))
                    self:set_flash("Found " .. tostring(e.item.name or e.item.id))
                    self:spawn_damage_number(e.x, e.z, 0, false,
                        { text = tostring(e.item.name or e.item.id),
                          color = RARITY_COLOR[e.item.rarity or "common"] or RARITY_COLOR.common })
                    self:haptic(10)
                    park_pickup(e)
                else
                    self:set_flash("Bag full!")
                    -- Also say it AT the item — the top flash is easy to miss.
                    self:spawn_damage_number(e.x, e.z, 0, false,
                        { text = "BAG FULL", color = { 1.0, 0.38, 0.3 } })
                    e.retry_t = 1.2
                end
            end
        end
    end
    if hovered then
        local ts = Art.s("text")
        local vp = Art._vp
        local tw, th = 175.0 * ts, 42.0 * ts
        local tx = math.max(vp.x, math.min(hovered.sx + 24.0, vp.x + vp.w - tw))
        local ty = math.max(vp.y, math.min(hovered.sy - 70.0, vp.y + vp.h - th))
        runtime_ui.set_quad(self.hud, "beacon_tip", {
            x = tx, y = ty, style = "text", fit = true,
            body = tostring(hovered.item.name or hovered.item.id) .. "\n" .. tostring(hovered.item.desc or ""),
            fill = { 0.025, 0.03, 0.045, 0.92 }, border = hovered.col,
            text_color = { 0.94, 0.96, 1.0, 1.0 },
            font_scale = 0.72 * Art.s("text") / (Art._ui_scale or 1.0),
            align_h = "left", align_v = "top", no_input = true,
            bring_to_front = true, z = 7000.0,
        })
    elseif runtime_ui and runtime_ui.remove then
        runtime_ui.remove(self.hud, "beacon_tip")
    end
end

-- Bank everything left on the floor (wave clear / boss down): forgiving, so no
-- loot is ever stranded behind a wave transition.
function Duel:vacuum_pickups()
    local hero = self.hero
    local gf = (hero and hero.gold_find) or 1.0
    for _, e in ipairs(self.coins or {}) do
        if e.active then
            self.gold = (self.gold or 0) + math.max(1, math.floor(e.value * gf + 0.5))
            park_pickup(e)
        end
    end
    for _, e in ipairs(self.beacons or {}) do
        if e.active then
            if Inventory.add_item(self, e.item) then
                self:set_flash("Found " .. tostring(e.item.name or e.item.id))
            else
                self:set_flash("Bag full - " .. tostring(e.item.name or e.item.id) .. " lost")
            end
            park_pickup(e)
        end
    end
    if runtime_ui and runtime_ui.remove then runtime_ui.remove(self.hud, "beacon_tip") end
end

function Duel:reset_pickups()
    for _, e in ipairs(self.coins or {}) do park_pickup(e) end
    for _, e in ipairs(self.beacons or {}) do park_pickup(e) end
    if runtime_ui and runtime_ui.remove then runtime_ui.remove(self.hud, "beacon_tip") end
    self._gold_pop = 0
end

-- ---------------------------------------------------------------------------
-- Creep projectiles — ranged enemies (seed spitter, archer, necromancer) fire a
-- VISIBLE bolt at the hero instead of dealing silent stand-off damage. Pooled +
-- recoloured per shot for the same reason the hero bolts are (deleting nodes
-- mid-combat corrupts other sprites' draw constants). Opaque spheres also stay
-- off the alpha-cut RT path, so they may be scaled freely.
-- ---------------------------------------------------------------------------
function Duel:cproj_hide(p)
    p.active = false
    if Art.valid(p.node) then
        p.node:set_position(vec3(-1000.0, -1000.0, -1000.0))
        p.node:set_scale(vec3(0.0001, 0.0001, 0.0001))
    end
end

function Duel:ensure_creep_projectiles()
    if self.cproj then return end
    if not (self.groups and self.groups.actors) then return end
    self.cproj = {}
    for i = 1, CPROJ_POOL do
        local node = Art.sphere("CreepBolt_" .. i, vec3(-1000.0, -1000.0, -1000.0),
            vec3(0.0001, 0.0001, 0.0001), { 1.0, 0.5, 0.3, 1.0 }, self.groups.actors, 1.4)
        self.cproj[i] = { node = node, active = false }
    end
end

function Duel:reset_creep_projectiles()
    if not self.cproj then return end
    for _, p in ipairs(self.cproj) do self:cproj_hide(p) end
end

function Duel:spawn_creep_proj(desc)
    self:ensure_creep_projectiles()
    if not self.cproj then return end
    local slot
    for _, p in ipairs(self.cproj) do if not p.active then slot = p; break end end
    if not slot then return end -- pool exhausted this frame; drop the bolt (no delete)
    slot.active = true
    slot.x, slot.y, slot.z = desc.sx, desc.sy or 0.7, desc.sz
    slot.vx, slot.vy, slot.vz = desc.vx, desc.vy or 0.0, desc.vz
    slot.gravity = desc.gravity or 0.0
    slot.life = desc.max_flight_time or 1.4
    slot.damage = desc.damage or 0.0
    slot.source = desc.source
    slot.hit_r = desc.hit_radius or 0.6
    local col = desc.color or { 1.0, 0.5, 0.3, 1.0 }
    slot.col = col
    slot.pulse = desc.pulse == true
    slot.base_e = desc.emissive or 1.0
    slot.trail_t = 0.05
    local sz = desc.particle_size or 0.22
    if Art.valid(slot.node) then
        local e = slot.base_e
        material.set(slot.node, "base_color", vec4(col[1], col[2], col[3], 1.0))
        material.set(slot.node, "emissive", vec3(col[1] * e, col[2] * e, col[3] * e))
        -- Use the archetype's authored projectile shape (arrows are long, cobs
        -- are chunky) and aim it along the flight line at spawn.
        local sc = desc.scale or { sz, sz, sz }
        slot.node:set_scale(vec3(sc[1] or sz, sc[2] or sz, sc[3] or sz))
        local horiz = math.sqrt(slot.vx * slot.vx + slot.vz * slot.vz)
        slot.node:set_rotation(vec3(-math.deg(math.atan(slot.vy or 0.0, math.max(horiz, 0.001))),
            math.deg(math.atan(slot.vx, slot.vz)), 0.0))
        slot.node:set_position(vec3(slot.x, slot.y, slot.z))
    end
    -- Muzzle spark at the shooter, tinted to the bolt.
    Art.burst("ath_cproj_muzzle", vec3(desc.sx, desc.sy or 0.7, desc.sz),
        { preset = "enemy_give", count = 6, life_max = 0.16, spawn_radius = 0.16, size_max = 0.12,
          color_start = vec4(col[1], col[2], col[3], 1.0) })
end

function Duel:try_fire_creep(c, hero, dt)
    if hero.dead or not Creep.is_ranged(c) then return end
    local spec = c.stats.projectile
    if not spec then return end -- only true shooters fire a visible bolt
    -- Telegraph grammar: the shot is committed 0.4s early behind a white ramp-
    -- flash (View reads shoot_windup), then released re-aimed at the hero's
    -- position at release — the flying bolt stays the dodgeable part.
    if c.shoot_windup then
        c.shoot_windup = c.shoot_windup - dt
        if c.shoot_windup > 0.0 then return end
        c.shoot_windup = nil
        local desc = c._pending_shot
        c._pending_shot = nil
        if desc then
            if (desc.gravity or 0.0) == 0.0 then
                local dxr, dzr = hero.x - c.x, hero.z - c.z
                local dyr = (desc.ty or 0.55) - (desc.sy or 0.7)
                local dist = math.sqrt(dxr * dxr + dyr * dyr + dzr * dzr)
                if dist > 0.001 then
                    local spd = desc.speed or 12.0
                    desc.vx, desc.vy, desc.vz = dxr / dist * spd, dyr / dist * spd, dzr / dist * spd
                end
            end
            desc.sx, desc.sz = c.x, c.z
            self:spawn_creep_proj(desc)
        end
        return
    end
    local dx, dz = hero.x - c.x, hero.z - c.z
    -- Small margin so a creep parked AT its hold_range still reliably fires
    -- (float jitter otherwise flickers the edge check).
    local rng = (c.stats.hold_range or c.stats.range or 6.0) + 1.0
    if dx * dx + dz * dz > rng * rng then return end
    local cd = spec.cooldown or 0.9
    local desc = Creep.attack_projectile(c, hero, (c.stats.dps or 2.0) * cd)
    if desc then
        desc.source = creep_name(c) .. " (shot)"
        if self.manual_hero then
            c._pending_shot = desc
            c.shoot_windup = SHOT_WINDUP
        else
            self:spawn_creep_proj(desc)
        end
    end
end

function Duel:update_creep_projectiles(dt)
    if not self.cproj then return end
    local hero = self.hero
    local A = self.arena
    local ctrail_budget = 4 -- particle emits per frame across all creep bolts
    for _, p in ipairs(self.cproj) do
        if p.active then
            if (p.gravity or 0.0) ~= 0.0 then p.vy = (p.vy or 0.0) - p.gravity * dt end
            p.x = p.x + p.vx * dt
            p.y = (p.y or 0.7) + (p.vy or 0.0) * dt
            p.z = p.z + p.vz * dt
            p.life = p.life - dt
            local hit = false
            if hero and not hero.dead then
                local dx, dz = hero.x - p.x, hero.z - p.z
                if dx * dx + dz * dz <= p.hit_r * p.hit_r then hit = true end
            end
            local off = p.x < A.pad or p.x > A.w - A.pad or p.z < A.pad or p.z > A.h - A.pad or (p.y or 0.0) < -0.2
            -- Dodged (i-frames): the bolt flies straight through the hero.
            if hit and self:apply_hero_damage(p.damage, { source = p.source }) then
                if hero and not hero.dead then
                    local d = math.sqrt(p.vx * p.vx + p.vz * p.vz)
                    if d > 0.001 then
                        hero.knock_x = (hero.knock_x or 0.0) + p.vx / d * HERO_KNOCK_BOLT
                        hero.knock_z = (hero.knock_z or 0.0) + p.vz / d * HERO_KNOCK_BOLT
                    end
                end
                Art.burst("ath_cproj_hit", vec3(p.x, p.y or 0.7, p.z),
                    { preset = "hero_take", count = 10, life_max = 0.20, spawn_radius = 0.16,
                      color_start = vec4(p.col[1], p.col[2], p.col[3], 1.0) })
                self:cproj_hide(p)
            elseif p.life <= 0.0 or off then
                self:cproj_hide(p)
            elseif Art.valid(p.node) then
                p.node:set_position(vec3(p.x, p.y or 0.7, p.z))
                -- Throb pulsing shots (necromancer orbs, mortar cobs) + a light trail.
                if p.pulse then
                    local k = p.base_e * (1.0 + 0.5 * math.sin(self.realtime * 14.0))
                    material.set(p.node, "emissive", vec3(p.col[1] * k, p.col[2] * k, p.col[3] * k))
                end
                p.trail_t = (p.trail_t or 0.0) - dt
                if p.trail_t <= 0.0 and ctrail_budget > 0 then
                    ctrail_budget = ctrail_budget - 1
                    p.trail_t = 0.09
                    Art.burst("ath_cbolt_trail", vec3(p.x, p.y or 0.7, p.z),
                        { preset = "enemy_give", count = 2, life_max = 0.15, spawn_radius = 0.05,
                          size_max = 0.09, noise_strength = 0.6,
                          color_start = vec4(p.col[1], p.col[2], p.col[3], 0.85) })
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Spawn telegraphs — a pulsing ground ring (+ particles) warns where the swarm
-- is about to appear, so spawns never pop in on top of the player. Big spawns
-- (elites/brutes) get a longer, fancier, particle-spitting warn. Rings are
-- pooled (never deleted mid-combat) like every other combat node.
-- ---------------------------------------------------------------------------
function Duel:ensure_telegraph_pool()
    if self.tele_pool then return end
    if not (self.groups and self.groups.world) then return end
    self.tele_pool = {}
    self.telegraphs = self.telegraphs or {}
    for i = 1, 18 do
        local ring = Art.cylinder("Telegraph_" .. i, vec3(-1000.0, 0.04, -1000.0),
            vec3(2.4, 0.03, 2.4), { 0.95, 0.32, 0.2, 0.5 }, self.groups.world, 1.2)
        if Art.valid(ring) and material and material.set_render_type then
            material.set_render_type(ring, "alpha_blend")
        end
        self.tele_pool[i] = ring
    end
end

function Duel:add_telegraph(spawn, arch, free)
    self:ensure_telegraph_pool()
    local ring = self.tele_pool and table.remove(self.tele_pool) or nil
    if not ring then self:spawn_one(spawn, arch, free); return end -- pool dry: spawn now
    local big = (Creep.threat_cost(arch) or 1) >= TELEGRAPH_BIG_COST
    local col = big and { 0.86, 0.32, 0.92 } or (self.theme.spawn_sigil or { 0.95, 0.45, 0.2 })
    if Art.valid(ring) then
        material.set(ring, "base_color", vec4(col[1], col[2], col[3], 0.5))
        material.set(ring, "emissive", vec3(col[1], col[2], col[3]))
        ring:set_position(vec3(spawn.x, 0.05, spawn.y))
    end
    self.telegraphs[#self.telegraphs + 1] = {
        x = spawn.x, z = spawn.y, arch = arch, free = free, ring = ring, big = big, col = col,
        t = big and TELEGRAPH_T_BIG or TELEGRAPH_T, dur = big and TELEGRAPH_T_BIG or TELEGRAPH_T, emit_t = 0.0,
    }
    Art.burst("ath_tele_start", vec3(spawn.x, 0.3, spawn.y),
        { preset = big and "enemy_give" or "enemy_take", count = big and 16 or 8, life_max = 0.40,
          spawn_radius = big and 0.7 or 0.4, size_max = big and 0.22 or 0.14,
          color_start = vec4(col[1], col[2], col[3], 1.0), gravity = vec3(0.0, 1.2, 0.0) })
end

function Duel:park_telegraph_ring(tg)
    if Art.valid(tg.ring) then tg.ring:set_position(vec3(-1000.0, 0.04, -1000.0)) end
    if tg.ring and self.tele_pool then self.tele_pool[#self.tele_pool + 1] = tg.ring end
end

function Duel:update_telegraphs(dt)
    local list = self.telegraphs
    if not list or #list == 0 then return end
    local keep = {}
    for _, tg in ipairs(list) do
        tg.t = tg.t - dt
        if Art.valid(tg.ring) then
            local pulse = 0.35 + 0.65 * math.abs(math.sin(self.realtime * (tg.big and 10.0 or 15.0)))
            material.set(tg.ring, "base_color", vec4(tg.col[1], tg.col[2], tg.col[3], 0.22 + 0.5 * pulse))
            material.set(tg.ring, "emissive", vec3(tg.col[1] * pulse * 1.4, tg.col[2] * pulse * 1.4, tg.col[3] * pulse * 1.4))
        end
        if tg.big then
            tg.emit_t = tg.emit_t + dt
            if tg.emit_t >= 0.12 then
                tg.emit_t = 0.0
                Art.burst("ath_tele_loop", vec3(tg.x, 0.25, tg.z),
                    { preset = "enemy_give", count = 6, life_max = 0.35, spawn_radius = 0.55, size_max = 0.18,
                      color_start = vec4(tg.col[1], tg.col[2], tg.col[3], 1.0), gravity = vec3(0.0, 1.4, 0.0) })
            end
        end
        if tg.t <= 0.0 then
            Art.burst("ath_tele_pop", vec3(tg.x, 0.4, tg.z),
                { preset = tg.big and "enemy_give" or "enemy_take", count = tg.big and 20 or 10, life_max = 0.3,
                  spawn_radius = tg.big and 0.6 or 0.35, size_max = tg.big and 0.24 or 0.14,
                  color_start = vec4(tg.col[1], tg.col[2], tg.col[3], 1.0) })
            self:spawn_one({ x = tg.x, y = tg.z }, tg.arch, tg.free)
            self:park_telegraph_ring(tg)
        else
            keep[#keep + 1] = tg
        end
    end
    self.telegraphs = keep
end

function Duel:clear_telegraphs()
    if self.telegraphs then
        for _, tg in ipairs(self.telegraphs) do self:park_telegraph_ring(tg) end
    end
    self.telegraphs = {}
end

-- Blast decal — telegraph grammar's "ground decal before an area impact": a red
-- ring sized to the walking bomb's blast radius that rides the fusing creep
-- (bombs keep walking while lit). Borrows the shared telegraph ring pool;
-- pool-dry = no decal, the sprite's fuse strobe still warns.
function Duel:attach_blast_decal(c)
    self:ensure_telegraph_pool()
    local ring = self.tele_pool and table.remove(self.tele_pool) or nil
    if not (ring and Art.valid(ring)) then return end
    local r = ((c.stats and c.stats.explode) or {}).radius or 2.2
    ring:set_scale(vec3(r * 2.0, 0.03, r * 2.0))
    ring:set_position(vec3(c.x, 0.05, c.z))
    material.set(ring, "base_color", vec4(1.0, 0.16, 0.10, 0.55))
    material.set(ring, "emissive", vec3(1.4, 0.15, 0.10))
    c._blast_ring = ring
end

function Duel:park_blast_decal(c)
    local ring = c and c._blast_ring
    if not ring then return end
    c._blast_ring = nil
    if Art.valid(ring) then
        ring:set_scale(vec3(2.4, 0.03, 2.4)) -- restore the spawn-telegraph size
        ring:set_position(vec3(-1000.0, 0.04, -1000.0))
    end
    if self.tele_pool then self.tele_pool[#self.tele_pool + 1] = ring end
end

-- ---------------------------------------------------------------------------
-- Mobile — virtual movement joystick + haptics shim.
-- ---------------------------------------------------------------------------
-- Brief haptic pulse if the engine exposes input.vibrate(ms) (Android Vibrator).
-- No-op otherwise; wired here so it lights up the moment that binding lands.
function Duel:haptic(ms)
    if input and input.vibrate then input.vibrate(ms or 12) end
end

-- Floating full-screen joystick driven by the pointer (a finger via SDL's
-- touch->mouse mapping, or a desktop mouse-drag). Sets self._stick.dirx/dirz,
-- which update_hero blends in alongside WASD. Combat-only so it never fights the
-- inventory / menus; a press ANYWHERE on screen starts the stick, so either thumb
-- can drive the hero (combat has no right-side action buttons to conflict with —
-- the auto-attack is automatic).
function Duel:update_touch_stick()
    if not self.manual_hero or self.state ~= "combat" then self._stick = nil; return end
    local mx, my = ui_pointer()
    if not (mx and pointer_down()) then self._stick = nil; return end
    local _, vh = Art.surface_size() -- refresh Art._vp; vh sizes the stick radius
    local R = vh * 0.11
    if not self._stick then
        self._stick = { ox = mx, oy = my, kx = mx, ky = my, dirx = 0.0, dirz = 0.0, R = R }
    end
    local ddx, ddy = mx - self._stick.ox, my - self._stick.oy
    local d = math.sqrt(ddx * ddx + ddy * ddy)
    if d > R then ddx, ddy = ddx / d * R, ddy / d * R; d = R end
    self._stick.kx, self._stick.ky = self._stick.ox + ddx, self._stick.oy + ddy
    if d / R < 0.2 then
        self._stick.dirx, self._stick.dirz = 0.0, 0.0 -- deadzone
    else
        -- Screen +x -> world +x; screen +y (down) -> world +z (matches WASD S/Down).
        self._stick.dirx, self._stick.dirz = ddx / R, ddy / R
    end
end

function Duel:update_hero(dt)
    local hero = self.hero
    if not hero then return end
    if hero.dead then
        hero.death_t = hero.death_t + dt
        if Art.valid(hero.root) then
            hero.root:set_position(vec3(hero.x, 0.0, hero.z))
            hero.root:set_rotation(vec3(90.0, math.deg(hero.facing), 0.0))
            local ws = hero.world_scale or 1.0
            hero.root:set_scale(vec3(ws, 0.35 * ws, ws))
        end
        if Art.valid(hero.parts.aura) then hero.parts.aura:set_scale(vec3(0.01, 0.01, 0.01)) end
        return
    end

    if hero.regen > 0.0 then hero.hp = math.min(hero.hp_max, hero.hp + hero.regen * dt) end
    hero.hit_flash = math.max(0.0, (hero.hit_flash or 0.0) - dt)
    hero.dodge_iframe_t = math.max(0.0, (hero.dodge_iframe_t or 0.0) - dt)

    local target, tdist = self:nearest_creep(hero)
    if self.manual_hero then
        -- Suppress movement while the dev console is open so tuning keys don't drive.
        local console_open = self.console and self.console.visible
        self:update_touch_stick()
        local dirx, dirz = 0.0, 0.0
        if not console_open then
            dirx = (self:is_key_down("D") or self:is_key_down("Right")) and 1.0 or 0.0
            dirx = dirx - ((self:is_key_down("A") or self:is_key_down("Left")) and 1.0 or 0.0)
            dirz = (self:is_key_down("S") or self:is_key_down("Down")) and 1.0 or 0.0
            dirz = dirz - ((self:is_key_down("W") or self:is_key_down("Up")) and 1.0 or 0.0)
            -- Touch / mouse virtual joystick overrides WASD when engaged.
            if self._stick and (self._stick.dirx ~= 0.0 or self._stick.dirz ~= 0.0) then
                dirx, dirz = self._stick.dirx, self._stick.dirz
            end
        end
        -- Headless smokes (ATH_DUEL_AUTOPLAY): a tiny pilot drives the hero so
        -- balance smokes measure REAL clears — kite when hurt, hold the attack
        -- band, dodge red telegraphs. Real input always wins (keys above).
        if self.autoplay and not console_open and dirx == 0.0 and dirz == 0.0 then
            local px, pz = 0.0, 0.0
            local hpf = hero.hp / math.max(1.0, hero.hp_max)
            local ranged = hero.attack_type ~= "melee"
            local cx, cz = self:swarm_centroid()
            local danger = hpf < 0.45 or (ranged and target and tdist < hero.attack_range * 0.5)
            if danger and cx then
                px, pz = hero.x - cx, hero.z - cz
            elseif target and ((ranged and tdist > hero.attack_range * 0.85) or (not ranged and tdist > 1.2)) then
                px, pz = target.x - hero.x, target.z - hero.z
            end
            -- Soft pull off the walls so the pilot never corner-camps.
            local A = self.arena
            local bminx, bmaxx, bminz, bmaxz = arena_actor_bounds(A, 3.5)
            if hero.x < bminx then px = px + 3.0 elseif hero.x > bmaxx then px = px - 3.0 end
            if hero.z < bminz then pz = pz + 3.0 elseif hero.z > bmaxz then pz = pz - 3.0 end
            local m = math.sqrt(px * px + pz * pz)
            if m > 0.001 then dirx, dirz = px / m, pz / m end
            -- Dodge the grammar's red telegraphs: an inbound dash or a lit fuse.
            if (hero.dodge_charges or 0) > 0 and hero.dodge_t <= 0.0 then
                for _, c in ipairs(self.creeps) do
                    if c.alive then
                        local ax, az = hero.x - c.x, hero.z - c.z
                        local ad2 = ax * ax + az * az
                        local ex_r = ((c.stats and c.stats.explode or {}).radius or 2.2) + 0.5
                        if (c.charge_state == "dash" and ad2 < 9.0) or (c.fuse_t and ad2 < ex_r * ex_r) then
                            self:try_dodge(ax, az) -- away from the threat
                            break
                        end
                    end
                end
            end
        end
        -- Dodge: Space dashes along the movement input (hero facing when idle).
        -- This is the shared manual-movement choke point, so every manual-hero
        -- mode gets the same dodge; charges recharge one at a time.
        if hero.dodge_charges < (hero.dodge_charges_max or 1) then
            hero.dodge_recharge_t = hero.dodge_recharge_t - dt
            if hero.dodge_recharge_t <= 0.0 then
                hero.dodge_charges = hero.dodge_charges + 1
                hero.dodge_recharge_t = hero.dodge_recharge
            end
        end
        if not console_open and self:key_pressed("Space") then self:try_dodge(dirx, dirz) end
        if hero.dodge_t > 0.0 then
            -- Dash overrides steering: a locked line, fixed total distance.
            local step = math.min(dt, hero.dodge_t)
            hero.dodge_t = hero.dodge_t - dt
            self:move_hero(hero, hero.dodge_dx, hero.dodge_dz, hero.dodge_speed or (DODGE_DIST / DODGE_DUR), step)
            hero.vel_x = hero.dodge_dx * hero.speed -- exit the dash at run speed
            hero.vel_z = hero.dodge_dz * hero.speed
        else
            -- Smooth the input asymmetrically: starts/turns ease in over ~50 ms,
            -- but releasing the keys bites in ~25 ms — the hero plants almost
            -- (not quite) instantly instead of sliding to a stop.
            local mag = math.sqrt(dirx * dirx + dirz * dirz)
            local tvx, tvz = 0.0, 0.0
            if mag > 0.001 then
                tvx = dirx / mag * hero.speed
                tvz = dirz / mag * hero.speed
            end
            local rate = (mag > 0.001) and 20.0 or 40.0
            local blend = math.min(1.0, rate * dt)
            hero.vel_x = (hero.vel_x or 0.0) + (tvx - (hero.vel_x or 0.0)) * blend
            hero.vel_z = (hero.vel_z or 0.0) + (tvz - (hero.vel_z or 0.0)) * blend
            local sp = math.sqrt(hero.vel_x * hero.vel_x + hero.vel_z * hero.vel_z)
            if sp > 0.05 then
                self:move_hero(hero, hero.vel_x / sp, hero.vel_z / sp, sp, dt)
            elseif target then
                local dx, dz = target.x - hero.x, target.z - hero.z
                hero.facing = math.atan(dx, dz)
            end
        end
        -- Class attack identity: melee classes auto-cleave whatever's in reach;
        -- ranged classes fire pooled bolts at the nearest targets.
        if hero.attack_type == "melee" then
            self:hero_attack(hero, dt)
        else
            self:hero_fire(hero, dt)
        end
    else
        local kite_speed = hero.kite_speed * (1.0 + 0.25 * (hero.dash or 0))
        local kite_distance = self.hero_spec.kite_distance + 1.2 * (hero.dash or 0)
        local low = hero.hp <= hero.hp_max * self.hero_spec.kite_threshold
        if target then
            local dx, dz = target.x - hero.x, target.z - hero.z
            local d = tdist > 0.001 and tdist or 1.0
            if low and tdist < kite_distance then
                local cx, cz = self:swarm_centroid()
                if cx then
                    local ax, az = hero.x - cx, hero.z - cz
                    local an = math.sqrt(ax * ax + az * az)
                    if an > 0.001 then self:move_hero(hero, ax / an, az / an, kite_speed, dt) end
                end
            elseif tdist > hero.attack_range * 0.8 then
                self:move_hero(hero, dx / d, dz / d, hero.speed, dt)
            else
                hero.facing = math.atan(dx, dz)
            end
            self:hero_attack(hero, dt)
        end
    end
    self:hero_whirl(hero, dt)
    self:update_hero_projectiles(dt)

    -- Self-stagger: a small decaying shove from being bitten / shot, applied after
    -- input so the hit reads but the player stays in control.
    if (hero.knock_x or 0.0) ~= 0.0 or (hero.knock_z or 0.0) ~= 0.0 then
        local A = self.arena
        local minx, maxx, minz, maxz = arena_actor_bounds(A, 0.8)
        hero.x = clampn(hero.x + hero.knock_x * dt, minx, maxx)
        hero.z = clampn(hero.z + hero.knock_z * dt, minz, maxz)
        local dd = math.max(0.0, 1.0 - 18.0 * dt)
        hero.knock_x = hero.knock_x * dd
        hero.knock_z = hero.knock_z * dd
        if (hero.knock_x * hero.knock_x + hero.knock_z * hero.knock_z) < 0.02 then
            hero.knock_x = 0.0
            hero.knock_z = 0.0
        end
    end

    -- Locomotion + procedural animation (walk gait + an attack flash blend).
    hero.phase = hero.phase + dt * 9.0
    if Art.valid(hero.root) then
        hero.root:set_position(vec3(hero.x, 0.0, hero.z))
        hero.root:set_rotation(vec3(0.0, math.deg(hero.facing), 0.0))
    end
    -- Billboard textured quads toward the iso camera so they aren't edge-on.
    -- The iso camera offset is (-44,44,44) → face toward it: pitch ~35°, yaw −45°.
    -- Parts are children of root (which rotates by hero.facing), so counter-rotate.
    if hero.actor and hero.actor.spec and hero.actor.spec.soft_cape then
        local cam_pitch, cam_yaw = 35.26, -45.0
        local facing_deg = math.deg(hero.facing)
        local local_yaw = cam_yaw - facing_deg
        for _, key in ipairs({ "body", "sword" }) do
            local p = hero.parts[key]
            if Art.valid(p) then p:set_rotation(vec3(cam_pitch, local_yaw, 0.0)) end
        end
    else
        Art.animate(hero.actor, "walk", hero.phase / 9.0)
    end
    Art.animate_soft_cape(hero.actor, self.realtime)
    hero.attack_flash = math.max(hero.attack_flash - dt, 0.0)
    if hero.attack_flash > 0.0 then
        Art.animate(hero.actor, "attack", self.realtime, { weight = math.min(1.0, hero.attack_flash / 0.12) })
    end
    if Art.valid(hero.parts.aura) then
        local rng = hero.attack_range * 2.0
        hero.parts.aura:set_scale(vec3(rng, 0.03, rng))
    end
end

-- ---------------------------------------------------------------------------
-- Spawning
-- ---------------------------------------------------------------------------

function Duel:spawn_interval()
    local s = self.spawn_cfg
    local base = math.max(s.interval_min, s.interval_start - s.interval_ramp * (self.combat_time / 10.0))
    return base * (self.spawn_mods.interval_mult or 1.0)
end

function Duel:batch_size()
    local s = self.spawn_cfg
    return math.min(s.batch_max, s.batch_start + math.floor(self.combat_time / 16.0)) + (self.spawn_mods.batch_add or 0)
end

function Duel:live_cap()
    local s = self.spawn_cfg
    return math.min(s.cap_max, s.cap_start + math.floor(self.combat_time / 8.0) * 4) + (self.spawn_mods.cap_add or 0)
end

function Duel:count_alive()
    local n = 0
    for _, c in ipairs(self.creeps) do if c.alive then n = n + 1 end end
    return n
end

function Duel:minimum_spawn_cost()
    local min_cost = nil
    for _, role in ipairs({ "swarm", "ranged", "elite", "brute" }) do
        local arch = self:role_archetype(role)
        if arch then
            local cost = Creep.threat_cost(arch)
            if cost and (not min_cost or cost < min_cost) then min_cost = cost end
        end
    end
    return min_cost or 1
end

-- Map a role to one of the mode's archetype ids.
function Duel:role_archetype(role)
    return self.roles[role] or self.roles.swarm or Creep.default_archetype
end

-- Which archetype the auto-spawner picks over time. Modes can override with
-- config.auto_mix(duel) -> archetype_id.
function Duel:pick_auto_archetype()
    if self.config.auto_mix then return self.config.auto_mix(self) end
    if self.combat_time >= self.spawn_cfg.brute_after and (self.spawn_counter % 9 == 0) then
        return self:role_archetype("brute")
    end
    if self.spawn_counter % 5 == 0 and self.roles.ranged then return self:role_archetype("ranged") end
    if self.spawn_counter % 3 == 0 and self.roles.elite then return self:role_archetype("elite") end
    return self:role_archetype("swarm")
end

function Duel:pick_affordable_auto_archetype()
    local reserve = self.reserve or 0.0
    local picked = self:pick_auto_archetype()
    if picked and Creep.threat_cost(picked) <= reserve then return picked end
    for _, role in ipairs({ "swarm", "ranged", "elite", "brute" }) do
        local arch = self:role_archetype(role)
        if arch and Creep.threat_cost(arch) <= reserve then return arch end
    end
    return picked
end

-- Spawn one creep. `free` skips the reserve cost (a card already paid it).
function Duel:spawn_one(spawn, arch, free)
    arch = arch or (self.manual_hero and self:pick_affordable_auto_archetype() or self:pick_auto_archetype())
    local cost = Creep.threat_cost(arch)
    if not free then
        if self.reserve < cost then return nil end
        self.reserve = self.reserve - cost
    end
    self.spawn_counter = self.spawn_counter + 1
    self.next_id = self.next_id + 1
    local jx = (self.spawn_counter % 5 - 2) * 0.3
    local jz = (self.spawn_counter % 7 - 3) * 0.3
    -- ELITE roll (manual arena, wave 2+, budget-paid spawns only): a scaled-up,
    -- gold-tinted variant with a guaranteed item drop. Splits/summons/boss are
    -- exempt (`free`), and so is anything already big (boss, cost > 5).
    local map = self:active_map()
    local elite = false
    if self.manual_hero and not free and (self.wave_index or 1) >= 2 and cost <= 5 then
        local def = Creep.archetypes[Creep.resolve_archetype(arch)] or {}
        if not def.boss then
            elite = math.random() < (0.03 + 0.012 * (self.wave_index or 1) + (map.elite_bonus or 0.0))
        end
    end
    local creep = Creep.create({
        id = self.next_id, archetype = arch,
        x = spawn.x + jx, z = spawn.y + jz,
        parent = self.groups.actors,
        -- Map rank scales toughness/damage on top of the config base and elites.
        hp_multiplier = (self.config.creep_hp_mult or 1.0) * (map.hp_mult or 1.0),
        elite = elite,
        -- POOLING IS LOAD-BEARING: deleting rig nodes mid-combat (a no_pool
        -- experiment) shuffles node storage via swap-and-pop and leaves mesh
        -- draw-constants pointing at OTHER nodes' world matrices — sprites
        -- then render with arbitrary (often giant) transforms. Park & reuse.
        mods = { speed_add = self.buffs.speed, dps_add = self.buffs.power, hp_add = self.buffs.hp,
                 hp_multiplier = elite and ELITE_HP_MULT or nil,
                 dps_multiplier = (elite and ELITE_DPS_MULT or 1.0) * (map.dps_mult or 1.0) },
    })
    self:dress_creep(creep)
    if creep.stats and creep.stats.boss then self.boss_creep = creep end
    self.creeps[#self.creeps + 1] = creep
    if self.config.hooks and self.config.hooks.on_spawn then self.config.hooks.on_spawn(self, creep) end
    return creep
end

function Duel:enqueue_spawn(count, arch, free)
    local n = math.max(0, math.floor(tonumber(count) or 0))
    if n <= 0 then return end
    self.spawn_queue = self.spawn_queue or {}
    for _ = 1, n do
        self.spawn_queue[#self.spawn_queue + 1] = { arch = arch, free = free == true }
    end
end

-- A random spawn point hugging the arena walls/edges, kept at least half the
-- arena (min dimension) away from the hero so nothing materialises on top of the
-- player. Best-of-N fallback guarantees it always returns a far-ish point.
function Duel:pick_spawn_point()
    local A = self.arena
    local minx, maxx, minz, maxz = arena_actor_bounds(A, 1.25)
    local band = 3.5 -- how deep from a wall a spawn may sit
    local min_dist = 0.5 * math.min(A.w, A.h)
    local hx = (self.hero and self.hero.x) or (A.w * 0.5)
    local hz = (self.hero and self.hero.z) or (A.h * 0.5)
    local best, best_d = nil, -1.0
    for _ = 1, 16 do
        local edge = math.random(1, 4)
        local x, z
        if edge == 1 then -- west wall
            x = minx + math.random() * band
            z = minz + math.random() * (maxz - minz)
        elseif edge == 2 then -- east wall
            x = maxx - math.random() * band
            z = minz + math.random() * (maxz - minz)
        elseif edge == 3 then -- north wall
            x = minx + math.random() * (maxx - minx)
            z = minz + math.random() * band
        else -- south wall
            x = minx + math.random() * (maxx - minx)
            z = maxz - math.random() * band
        end
        local dx, dz = x - hx, z - hz
        local d = math.sqrt(dx * dx + dz * dz)
        if d >= min_dist then return { x = x, y = z } end
        if d > best_d then best, best_d = { x = x, y = z }, d end
    end
    return best or { x = minx, y = minz }
end

function Duel:clamp_creep_to_arena(creep)
    if not (creep and creep.alive and self.manual_hero) then return end
    local minx, maxx, minz, maxz = arena_actor_bounds(self.arena, 1.0)
    local x = clampn(creep.x or 0.0, minx, maxx)
    local z = clampn(creep.z or 0.0, minz, maxz)
    if x == creep.x and z == creep.z then return end
    creep.x = x
    creep.z = z
    if Art.valid(creep.root) then
        creep.root:set_position(vec3(x, 0.0, z))
    end
end

function Duel:drain_spawn_queue(per_frame)
    local q = self.spawn_queue
    if not q or #q == 0 then return end

    local n = math.min(math.max(1, math.floor(tonumber(per_frame) or 1)), #q)
    -- Pending telegraphs count against the live cap so a long warn window doesn't
    -- let the queue front-load a huge wave that all pops at once.
    local pending = self.telegraphs and #self.telegraphs or 0
    for _ = 1, n do
        if self:count_alive() + pending >= self:live_cap() then return end

        local req = table.remove(q, 1)
        -- Manual arena: random near the walls, away from the hero. Other modes
        -- keep their authored fixed spawn ring.
        local spawn = self.manual_hero and self:pick_spawn_point()
            or self.spawns[(self.spawn_counter % #self.spawns) + 1]
        if self.use_telegraph then
            self:add_telegraph(spawn, req.arch, req.free)
            pending = pending + 1
        else
            self:spawn_one(spawn, req.arch, req.free)
        end
    end
end

function Duel:spawn_batch(count)
    self:enqueue_spawn(count, nil, false)
end

function Duel:update_spawning(dt)
    if self.manual_hero and (self.reserve or 0.0) < self:minimum_spawn_cost() then
        self.spawn_queue = {}
        return
    end
    self.spawn_t = self.spawn_t - dt
    if self.spawn_t <= 0.0 then
        self.spawn_t = self:spawn_interval()
        self:spawn_batch(self:batch_size())
    end
end

-- Apply the per-archetype VISUAL dressing on top of a freshly built or reused
-- rig: self-light glow (so it reads on the dark stage), the mode's signature
-- extras/texture, and the iso-read world scale. Glow and scale are cheap and
-- constant per archetype, so they run every spawn; the extras ADD nodes, so
-- they only run for a fresh rig — a reused rig already carries them from when it
-- was first built (see Creep pooling + creep.fresh_rig in duel_creep).
function Duel:dress_creep(creep)
    local s = creep.stats or {}
    local function glow(node, color)
        if Art.valid(node) and color then
            material.set(node, "emissive", vec3(color[1] * 0.85, color[2] * 0.85, color[3] * 0.85))
        end
    end
    glow(creep.parts and creep.parts.body, s.color)
    glow(creep.parts and creep.parts.head, s.head or s.color)
    glow(creep.parts and creep.parts.weapon, s.weapon)
    local arch_def = (self.config.archetypes or {})[creep.archetype]
    if creep.fresh_rig then
        if arch_def and arch_def.extras then Art.decorate(creep.root, arch_def.extras) end
        if arch_def and arch_def.texture then Art.texture(creep.parts and creep.parts.body, arch_def.texture) end
    end
    -- World character scale: re-derive the archetype's intended scale and grow it
    -- so the swarm reads at the iso distance (gameplay radii are unaffected).
    if Art.valid(creep.root) then
        local cbase = (arch_def and arch_def.scale) or 1.0
        local cw = cbase * Art.s("char")
        if creep.elite then cw = cw * 1.35 end
        creep.root:set_scale(vec3(cw, cw, cw))
    end
end

function Duel:warm_archetype(arch, count)
    if not arch then return end
    local n = math.max(0, math.floor(tonumber(count) or 0))
    for _ = 1, n do
        self.next_id = self.next_id + 1
        -- no_pool = true forces a FRESH rig build (so Creep.create doesn't pop the
        -- very pool we're filling and just recycle one rig). We then flip it OFF so
        -- Creep.destroy PARKS the rig into the pool instead of deleting it. Net: the
        -- pool is pre-populated with `n` ready, already-dressed rigs, so combat
        -- spawns reuse them by transform and NEVER build a rig mid-frame — building
        -- a rig mid-combat (geometry add) is the spawn spike.
        local creep = Creep.create({
            id = self.next_id, archetype = arch,
            x = self.arena.hero_start.x, z = self.arena.hero_start.y,
            parent = self.groups.actors, no_pool = true,
        })
        self:dress_creep(creep)
        if self.config.hooks and self.config.hooks.on_prewarm_spawn then
            self.config.hooks.on_prewarm_spawn(self, creep)
        end
        creep.no_pool = false
        Creep.destroy(creep)
    end
end

function Duel:warm_creep_pool()
    local target = self.config.warm_pool_count
    if target == nil then target = math.min(self.spawn_cfg.cap_start or 28, 28) end
    target = ATH_COMMON.getenv_number("ATH_DUEL_WARM_POOL", target)
    target = math.max(0, math.floor(tonumber(target) or 0))
    if target <= 0 then return end

    local counts = {}
    local function add(role, count)
        local arch = self:role_archetype(role)
        if not arch then return end
        counts[arch] = (counts[arch] or 0) + math.max(0, math.floor(count or 0))
    end

    local swarm = math.max(1, math.floor(target * 0.64))
    local ranged = math.max(1, math.floor(target * 0.18))
    local elite = math.max(1, math.floor(target * 0.14))
    local brute = math.max(1, target - (swarm + ranged + elite))
    add("swarm", swarm)
    add("ranged", ranged)
    add("elite", elite)
    add("brute", brute)

    local built = 0
    for arch, count in pairs(counts) do
        if built >= target then break end
        local n = math.min(count, target - built)
        self:warm_archetype(arch, n)
        built = built + n
    end
    self:log(string.format("warm_pool rigs=%d target=%d", built, target))
end

-- ---------------------------------------------------------------------------
-- Creeps + combat
-- ---------------------------------------------------------------------------

function Duel:update_field(dt)
    local hero = self.hero
    local tx = math.floor((hero.x or 0.0) + 0.5)
    local ty = math.floor((hero.z or 0.0) + 0.5)
    -- The flow field only depends on the hero's tile over a static map, so it is
    -- valid until the hero crosses into a new tile. Standing still costs nothing;
    -- the old code rebuilt the whole grid on a fixed 0.35s timer regardless.
    if self.field and tx == self.field_tx and ty == self.field_ty then
        return
    end
    self.field_tx = tx
    self.field_ty = ty
    self.field = Flow.compute(self.map, { x = tx, y = ty }, self.field)
    self.field.sample = Flow.sample
end

function Duel:update_creeps(dt)
    local hero = self.hero
    local kill_fx_budget = self.config.kill_fx_budget_per_frame
    local kill_fx_used = 0
    local dust_budget = 3 -- dash-dust emits per frame across all chargers
    local survivors = {}
    local incoming = 0.0
    local contact = false
    local contacters = {}
    for _, c in ipairs(self.creeps) do
        local ev = nil
        if c.alive then ev = Creep.update(c, dt, self.field, self.map, hero) end
        self:clamp_creep_to_arena(c)
        if c.hit_flash then c.hit_flash = math.max(0.0, c.hit_flash - dt) end
        if c.bite_cd then c.bite_cd = math.max(0.0, c.bite_cd - dt) end
        -- Blast decal: the red area-of-impact ring rides the fusing bomb; park
        -- it the moment the creep pops or is defused (killed).
        if c._blast_ring then
            if c.alive and c.fuse_t then
                if Art.valid(c._blast_ring) then
                    c._blast_ring:set_position(vec3(c.x, 0.05, c.z))
                    local p = 0.5 + 0.5 * math.sin(self.realtime * (14.0 + 22.0 * (1.0 - math.min(1.0, c.fuse_t / 0.8))))
                    material.set(c._blast_ring, "base_color", vec4(1.0, 0.16, 0.10, 0.30 + 0.35 * p))
                end
            else
                self:park_blast_decal(c)
            end
        end
        -- Aggregated melee damage flushes into one readable popup on a cadence.
        if c.alive and c._mdmg_t then
            c._mdmg_t = c._mdmg_t - dt
            if c._mdmg_t <= 0.0 then self:flush_melee_packet(c) end
        end
        -- Behaviour FX: a red warning puff when a charger plants, an ignition
        -- spark when a fuse lights, and kicked-up dust along a dash.
        if ev and ev.windup then
            Art.burst("ath_windup_" .. tostring(c.id), vec3(c.x, 0.4, c.z),
                { preset = "enemy_give", count = 10, life_max = 0.30, spawn_radius = 0.35, size_max = 0.16,
                  color_start = vec4(1.0, 0.35, 0.3, 1.0) })
        end
        if ev and ev.fuse_started then
            Art.burst("ath_fuse_" .. tostring(c.id), vec3(c.x, 0.5, c.z),
                { preset = "enemy_give", count = 6, life_max = 0.25, spawn_radius = 0.2, size_max = 0.14,
                  color_start = vec4(1.0, 0.6, 0.25, 1.0) })
            -- Grammar: a red ground decal marks the area of impact for the fuse.
            if self.manual_hero then self:attach_blast_decal(c) end
        end
        if c.alive and c.charge_state == "dash" then
            c._dust_t = (c._dust_t or 0.0) - dt
            if c._dust_t <= 0.0 and dust_budget > 0 then
                dust_budget = dust_budget - 1
                c._dust_t = 0.07
                Art.burst("ath_dash_dust_" .. tostring(c.id), vec3(c.x, 0.15, c.z),
                    { preset = "enemy_take", count = 3, life_max = 0.28, spawn_radius = 0.22, size_max = 0.14,
                      color_start = vec4(0.62, 0.52, 0.38, 0.9), gravity = vec3(0.0, 0.8, 0.0) })
            end
        end
        -- Necromancer-style summons (Creep.update returns these; previously dropped).
        -- Arena-only for now to keep this pass from altering the archived menu duels.
        -- CAVEAT: ev.summon is fed straight into the spawn queue, so any archetype
        -- that sets summon_archetype MUST also appear in the mode's prewarm_order —
        -- otherwise its rig is built mid-combat (the frame spike the prewarm pool
        -- exists to avoid).
        if self.manual_hero and ev and ev.summon then self:enqueue_spawn(1, ev.summon, true) end
        -- Walking bomb popped its fuse: the creep killed itself; blast the hero if
        -- caught in the radius. Killing it BEFORE the fuse ends skips all of this.
        if ev and ev.exploded then
            local exs = (c.stats and c.stats.explode) or {}
            c._exploded = true
            local ex_r = exs.radius or 2.2
            Art.burst("ath_explode_" .. tostring(c.id), vec3(c.x, 0.5, c.z),
                { preset = "enemy_give", count = 30, life_max = 0.4, spawn_radius = ex_r * 0.45,
                  size_max = 0.30, noise_strength = 6.0, color_start = vec4(1.0, 0.55, 0.2, 1.0) })
            if hero and not hero.dead then
                local dx, dz = hero.x - c.x, hero.z - c.z
                local d2 = dx * dx + dz * dz
                -- Dodged (i-frames): the blast washes over the hero harmlessly.
                if d2 <= ex_r * ex_r
                    and self:apply_hero_damage(exs.damage or 20.0, { source = creep_name(c) .. " (blast)" }) then
                    local d = math.sqrt(math.max(d2, 0.0001))
                    hero.knock_x = (hero.knock_x or 0.0) + dx / d * 6.0
                    hero.knock_z = (hero.knock_z or 0.0) + dz / d * 6.0
                    self:hitstop(0.07)
                end
            end
            Art.shake(0.45, 0.35)
        end
        if c.alive and not hero.dead then
            if self.manual_hero and Creep.is_ranged(c) and not c.charge_state then
                -- Manual arena: ranged enemies do NOT deal silent contact dps; they
                -- fire a visible bolt the hero can see and dodge. Legacy menu duels
                -- keep their original stand-off contact-damage model untouched.
                -- A CHARGING shooter (Corn Colossus) holds fire and falls through
                -- to the melee branch so its dash can actually slam.
                self:try_fire_creep(c, hero, dt)
            else
                local dx, dz = hero.x - c.x, hero.z - c.z
                local d = math.sqrt(dx * dx + dz * dz)
                local reach = hero.body_radius + (c.stats.range or 0.5)
                if d <= reach and c.charge_state == "dash" then
                    -- A landed charge is a one-shot slam, not contact dps. Dodged
                    -- (i-frames): no damage, no shove, and the dash keeps going —
                    -- the hero passes clean through the red telegraph.
                    local cg = c.stats.charge or {}
                    if self:apply_hero_damage((c.stats.dps or 1.0) * (cg.dmg_mult or 1.6),
                        { source = creep_name(c) .. " (charge)" }) then
                        c.charge_state = nil
                        c.charge_cd = cg.cooldown or 3.0
                        hero.knock_x = (hero.knock_x or 0.0) + (c.charge_dx or 0.0) * 7.0
                        hero.knock_z = (hero.knock_z or 0.0) + (c.charge_dz or 0.0) * 7.0
                        Art.shake(0.4, 0.3)
                        self:hitstop(0.06)
                        Art.burst("ath_slam_" .. tostring(c.id), vec3(hero.x, 0.7, hero.z),
                            { preset = "hero_take", count = 16, life_max = 0.28, spawn_radius = 0.3, size_max = 0.2 })
                    end
                elseif self.manual_hero then
                    -- Telegraph grammar: melee contact is a discrete BITE — a 0.4s
                    -- white ramp-flash (View reads bite_windup), then the hit lands
                    -- only if the hero is still in reach. Damage = dps * full cycle,
                    -- so the average matches the old contact dps when every bite
                    -- connects; stepping out or dodging now actually avoids it.
                    if c.bite_windup then
                        c.bite_windup = c.bite_windup - dt
                        if c.bite_windup <= 0.0 then
                            c.bite_windup = nil
                            c.bite_cd = BITE_COOLDOWN
                            if d <= reach + BITE_GRACE
                                and self:apply_hero_damage((c.stats.dps or 1.0) * (BITE_WINDUP + BITE_COOLDOWN),
                                    { source = creep_name(c) }) then
                                contact = true
                                contacters[#contacters + 1] = c
                                if (hero.thorns or 0.0) > 0.0
                                    and Creep.damage(c, hero.thorns * (BITE_WINDUP + BITE_COOLDOWN)) then
                                    c.alive = false
                                end
                            end
                        end
                    elseif d <= reach and (c.bite_cd or 0.0) <= 0.0 and not c.charge_state and not c.fuse_t then
                        c.bite_windup = BITE_WINDUP
                    end
                elseif d <= reach then
                    incoming = incoming + (c.stats.dps or 1.0)
                    contact = true
                    contacters[#contacters + 1] = c
                end
            end
        end
        if c.alive then
            survivors[#survivors + 1] = c
        else
            if (c._mdmg or 0.0) > 0.5 then self:flush_melee_packet(c) end
            local s = c.stats or {}
            local col = s.color or { 0.9, 0.5, 0.3 }
            local big = (s.threat_cost or 1) >= TELEGRAPH_BIG_COST or c.elite or s.boss
            if kill_fx_budget == nil or kill_fx_used < kill_fx_budget then
                -- Two-stage pop: radial gibs in the creep's colour + an upward puff,
                -- so deaths read as a squash-pop even on flat sprites.
                Art.burst("ath_duel_kill_" .. tostring(c.id), vec3(c.x, 0.5, c.z),
                    { preset = "enemy_take", count = big and 22 or 12, life_max = big and 0.34 or 0.24,
                      spawn_radius = big and 0.4 or 0.2, size_max = big and 0.26 or 0.16,
                      color_start = vec4(col[1], col[2], col[3], 1.0) })
                Art.burst("ath_duel_pop_" .. tostring(c.id), vec3(c.x, 0.7, c.z),
                    { preset = "enemy_give", count = big and 10 or 5, life_max = 0.3, spawn_radius = 0.15,
                      size_max = 0.14, gravity = vec3(0.0, 2.2, 0.0),
                      color_start = vec4(col[1] * 1.3, col[2] * 1.3, col[3] * 1.3, 1.0) })
                if big then
                    -- Ground shockwave: a wide, low dust ring under heavy kills.
                    Art.burst("ath_duel_ring_" .. tostring(c.id), vec3(c.x, 0.16, c.z),
                        { preset = "enemy_take", count = 14, life_max = 0.32, spawn_radius = 0.95,
                          size_max = 0.18, noise_strength = 1.2, gravity = vec3(0.0, 0.6, 0.0),
                          color_start = vec4(0.72, 0.66, 0.52, 0.9) })
                end
                kill_fx_used = kill_fx_used + 1
            end
            -- Death splits (pumpkins burst into sprouts) — direct spawns at the corpse.
            if self.manual_hero and s.split_into and not c._exploded then
                local n = s.split_into.count or 2
                for i = 1, n do
                    local ang = (i / n) * 6.2831
                    self:spawn_one({ x = c.x + math.sin(ang) * 0.7, y = c.z + math.cos(ang) * 0.7 },
                        s.split_into.archetype, true)
                end
            end
            if big then
                self:hitstop(s.boss and 0.12 or (c.elite and 0.07 or 0.045))
                Art.shake(s.boss and 0.85 or 0.1, s.boss and 0.6 or 0.2)
            end
            if self.boss_creep == c then
                self.boss_creep = nil
                local title = self:active_map().boss_title or self.config.boss_title
                self:set_flash((title and ("THE " .. title .. " FALLS")) or "CHAMPION DOWN")
            end
            self:begin_death_anim(c) -- defers Creep.destroy by a spin-out beat
            self.kills = self.kills + 1
            self:maybe_drop_manual_gear(c)
        end
    end
    self.creeps = survivors

    if incoming > 0.0 and not hero.dead then
        -- DIAG: name every damage source once a second so "damage out of
        -- nowhere" is attributable (creep, distance, its contact reach).
        self._dmg_log_t = (self._dmg_log_t or 0.0) - dt
        if ATH_DEV and pe_log and self._dmg_log_t <= 0.0 then
            self._dmg_log_t = 1.0
            local parts = {}
            for _, c in ipairs(contacters) do
                local dx, dz = hero.x - c.x, hero.z - c.z
                parts[#parts + 1] = string.format("%s d=%.2f reach=%.2f+%.2f",
                    tostring(c.archetype), math.sqrt(dx * dx + dz * dz),
                    hero.body_radius or 0, (c.stats and c.stats.range) or 0)
            end
            pe_log("[DMG] hero takes " .. string.format("%.1f", incoming) .. " dps from: " .. table.concat(parts, " | "))
        end
        self:apply_hero_damage(incoming * dt) -- armor is applied inside
        -- Thorns: reflect to the creeps actually in contact. (Manual bites
        -- reflect per landed bite at the bite site instead.)
        if (hero.thorns or 0.0) > 0.0 then
            for _, c in ipairs(contacters) do
                if Creep.damage(c, hero.thorns * dt) then c.alive = false end
            end
        end
    end
    -- Contact feel (haptic + spark + a small shove off the biting cluster) —
    -- shared by legacy contact dps and landed manual bites.
    if contact and not hero.dead then
        self.hit_fx_t = (self.hit_fx_t or 0.0) - dt
        if self.hit_fx_t <= 0.0 then
            self.hit_fx_t = 0.12
            if self.manual_hero then self:haptic(10) end
            Art.burst("ath_duel_herohit", vec3(hero.x, 0.9, hero.z),
                { preset = "hero_take", count = 8, life_max = 0.16, spawn_radius = 0.12, noise_strength = 2.4, size_max = 0.12 })
            -- Tiny periodic self-stagger away from the biting cluster (not every
            -- frame — that would fight the player's control).
            local cx, cz, n = 0.0, 0.0, 0
            for _, c in ipairs(contacters) do cx = cx + c.x; cz = cz + c.z; n = n + 1 end
            if self.manual_hero and n > 0 and not hero.dead then
                local ax, az = hero.x - cx / n, hero.z - cz / n
                local d = math.sqrt(ax * ax + az * az)
                if d > 0.001 then
                    hero.knock_x = (hero.knock_x or 0.0) + ax / d * HERO_KNOCK_CONTACT
                    hero.knock_z = (hero.knock_z or 0.0) + az / d * HERO_KNOCK_CONTACT
                end
            end
        end
    end
end

-- Deal damage to the hero from ANY source (swarm contact OR a mode's signature
-- hazard) with one centralised death path. opts.ignore_armor bypasses mitigation;
-- opts.source names the attacker for the death recap. Returns true only when HP
-- was actually reduced — callers gate on-hit side effects (knockback, shake,
-- charge-end) on it so a dodged attack passes clean through.
-- This is the API modes use for environmental damage (lava, poison, storms).
function Duel:apply_hero_damage(amount, opts)
    local hero = self.hero
    if not hero or hero.dead or (amount or 0.0) <= 0.0 then return false end
    opts = opts or {}
    -- Dodge i-frames: every damage source funnels through here, so immunity
    -- lives here and never on individual enemies.
    if (hero.dodge_iframe_t or 0.0) > 0.0 then return false end
    local mitig = opts.ignore_armor and 1.0 or (1.0 - clampn(hero.armor or 0.0, -0.5, 0.85))
    hero.hp = hero.hp - amount * mitig
    hero.hit_flash = HIT_FLASH_T
    -- Death recap: a 3-entry ring buffer of the last hits (newest last).
    if self.manual_hero then
        local log = self.dmg_log or {}
        self.dmg_log = log
        log[#log + 1] = { src = opts.source or "the swarm", dmg = amount * mitig, t = self.realtime }
        if #log > 3 then table.remove(log, 1) end
    end
    -- Hurt vignette pulse (drawn by update_hud) + a jolt on meaty single hits.
    self._hurt_t = 0.25
    if amount * mitig >= 14.0 then Art.shake(0.3, 0.25) end
    if hero.hp <= 0.0 then
        hero.hp = 0.0
        hero.dead = true
        self.death_time = self.realtime
        self:haptic(45)
        self.state = "slain"
        self:save_profile()
        self.slowmo_t = SLOWMO_DURATION
        self:set_flash(opts.flash or "HERO SLAIN")
        self:log(string.format("HERO SLAIN round=%d kills=%d reserve=%.0f", self.round, self.kills, self.reserve))
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Card effect application
-- ---------------------------------------------------------------------------

function Duel:apply_front(e)
    local hero = self.hero
    if not e then return end
    if e.dps_mult then hero.dps = hero.dps * e.dps_mult end
    if e.dps_add then hero.dps = hero.dps + e.dps_add end
    if e.cleave_add then hero.cleave = hero.cleave + e.cleave_add end
    if e.attack_range_add then hero.attack_range = hero.attack_range + e.attack_range_add end
    if e.speed_mult then hero.speed = hero.speed * e.speed_mult end
    if e.kite_speed_mult then hero.kite_speed = hero.kite_speed * e.kite_speed_mult end
    if e.hp_max_add then hero.hp_max = hero.hp_max + e.hp_max_add end
    if e.heal then hero.hp = math.min(hero.hp_max, hero.hp + e.heal) end
    if e.lifesteal_add then hero.lifesteal = (hero.lifesteal or 0.0) + e.lifesteal_add end
    if e.regen_add then hero.regen = (hero.regen or 0.0) + e.regen_add end
    if e.whirl_add then hero.whirl = (hero.whirl or 0) + e.whirl_add end
    if e.armor_add then hero.armor = clampn((hero.armor or 0.0) + e.armor_add, -0.5, 0.85) end
    if e.thorns_add then hero.thorns = (hero.thorns or 0.0) + e.thorns_add end
    if e.dash_add then hero.dash = (hero.dash or 0) + e.dash_add end
    if e.crit_add then hero.crit_chance = (hero.crit_chance or 0.0) + e.crit_add end -- real rolled crits
end

function Duel:apply_back(e)
    if not e then return false, "No effect." end
    if e.kind == "swarm" then
        self.buffs.speed = self.buffs.speed + (e.speed_add or 0.0)
        self.buffs.power = self.buffs.power + (e.dps_add or 0.0)
        self.buffs.hp = self.buffs.hp + (e.hp_add or 0.0)
        for _, c in ipairs(self.creeps) do
            if c.alive and c.stats then
                c.stats.speed = math.max(0.2, (c.stats.speed or 1.0) + (e.speed_add or 0.0))
                c.stats.dps = math.max(0.0, (c.stats.dps or 1.0) + (e.dps_add or 0.0))
                -- hp_add is advertised as "future + current spawns": raise the live
                -- creep's current and max HP so "+X HP" actually hardens the wave.
                if (e.hp_add or 0.0) ~= 0.0 then
                    c.hp_max = (c.hp_max or c.hp or 1.0) + e.hp_add
                    c.hp = math.max(1.0, (c.hp or 0.0) + e.hp_add)
                    if c.stats.hp then c.stats.hp = c.stats.hp + e.hp_add end
                end
            end
        end
        return true, "Swarm strengthened."
    elseif e.kind == "weaken" then
        local hero = self.hero
        if e.dps_mult then hero.dps = math.max(6.0, hero.dps * e.dps_mult) end
        if e.speed_mult then hero.speed = math.max(0.9, hero.speed * e.speed_mult) end
        if e.kite_speed_mult then hero.kite_speed = math.max(1.1, hero.kite_speed * e.kite_speed_mult) end
        if e.attack_range_add then hero.attack_range = math.max(0.6, hero.attack_range + e.attack_range_add) end
        return true, "Hero weakened."
    elseif e.kind == "spawn" then
        local cost = e.reserve_cost or 0
        if self.reserve < cost then return false, "Not enough reserve." end
        self.reserve = self.reserve - cost
        local arch = self:role_archetype(e.role or "swarm")
        self:enqueue_spawn(e.count or 1, arch, true)
        return true, "Summoned " .. tostring(e.count or 1) .. " " .. tostring(e.role or "swarm") .. "."
    elseif e.kind == "escalate" then
        self.spawn_mods.batch_add = (self.spawn_mods.batch_add or 0) + (e.batch_add or 0)
        self.spawn_mods.cap_add = (self.spawn_mods.cap_add or 0) + (e.cap_add or 0)
        if e.interval_mult then self.spawn_mods.interval_mult = (self.spawn_mods.interval_mult or 1.0) * e.interval_mult end
        return true, "Spawn cadence escalated."
    elseif e.kind == "reserve" then
        self.reserve = self.reserve + (e.reserve_add or 0.0)
        return true, "Reserve replenished."
    end
    return false, "Unknown effect."
end

-- Apply whichever face the seat plays, fire the mode hook, return ok, message.
function Duel:resolve_card(seat, card_id, effect)
    local ok, msg
    if seat.side == "hero" then
        self:apply_front(effect)
        ok, msg = true, (select(2, Cards.face(card_id, "hero")))
    else
        ok, msg = self:apply_back(effect)
    end
    if ok and self.config.hooks and self.config.hooks.on_card then
        self.config.hooks.on_card(self, seat.side, card_id, effect)
    end
    return ok, msg
end

-- ---------------------------------------------------------------------------
-- Manual-hero wave and gear path
-- ---------------------------------------------------------------------------

function Duel:manual_wave_budget(index)
    -- An explicit ATH_DUEL_RESERVE pins EVERY wave's budget (smoke/tuning knob).
    local env = ATH_COMMON.getenv_number("ATH_DUEL_RESERVE", nil)
    if env then return env end
    local mult = self:active_map().budget_mult or 1.0
    local budgets = self.wave_cfg and self.wave_cfg.budgets
    if budgets and budgets[index] then return budgets[index] * mult end
    local base = (self.wave_cfg and self.wave_cfg.reserve_start) or self.reserve_start or 300.0
    local add = (self.wave_cfg and self.wave_cfg.reserve_add) or 40.0
    return (base + (math.max(1, index or 1) - 1) * add) * mult
end

-- ---------------------------------------------------------------------------
-- Class pick — a frozen overlay at run start; the player chooses an attack
-- identity (sprite + stats + melee/ranged path) before wave 1.
-- ---------------------------------------------------------------------------
function Duel:begin_class_pick()
    self.state = "classpick"
    self:set_flash("CHOOSE YOUR CLASS")
end

-- keep_store: re-entering town from the world map must not reroll the shop
-- (restock is once per real town visit, not a free reroll).
function Duel:enter_town(keep_store)
    self.state = "town"
    self._town_shop = false
    self._between_wave = false
    self.run_cards = {}
    self.draft_offer = nil
    self:recompute_hero_stats()
    if not keep_store then self:restock_store() end
    self:save_profile()
    Inventory.show(self)
    self:set_flash("TOWN")
end

-- World map — a painted overworld shown before the run; pick where to hunt.
function Duel:enter_worldmap()
    self._wm_from_town = self.state == "town"
    self.state = "worldmap"
    Inventory.hide(self)
    self:set_flash("WORLD MAP")
end

function Duel:start_map()
    if self.state ~= "town" then return end
    -- ATH_DUEL_MAP pins the map for smokes/tuning (bypasses the unlock gate).
    local env_map = ATH_COMMON.getenv_number("ATH_DUEL_MAP", nil)
    if env_map and #self.maps > 0 then
        self.map_index = clampn(math.floor(env_map), 1, #self.maps)
    end
    local map = self:active_map()
    if map.waves then self.wave_cfg.count = map.waves end
    self._town_shop = false
    self.run_cards = {}
    self.draft_offer = nil
    self._between_wave = false
    self:recompute_hero_stats()
    Inventory.hide(self)
    if map.name then
        self:log(string.format("map start map=%d id=%s waves=%d", self.map_index, tostring(map.id), self.wave_cfg.count or 5))
    end
    self:begin_manual_wave(ATH_COMMON.getenv_number("ATH_DUEL_WAVE", 1))
end

function Duel:choose_class(index)
    local list = self.config.hero and self.config.hero.classes
    if not (list and list[index]) then return end
    self.hero_class = list[index].id
    -- Rebuild the hero with the picked class's sprite + stats. scene.delete_node is
    -- swap-and-pop: deleting the hero while the creep pool is already prewarmed would
    -- stale a parked rig's draw handle (the exact hazard reset_run guards against with
    -- clear_pool). Mirror reset_run's safe order — empty the pool, rebuild the hero on
    -- an empty pool, then re-fire on_reset/warm so the pool is re-parked AFTER the
    -- fresh hero node exists. (warm_creep_pool is a no-op for the arena, which prewarms
    -- via the on_reset hook; both are called so this is correct for any manual mode.)
    Creep.clear_pool()
    -- Never delete an ADOPTED hero (authored scene node): create_hero re-finds and
    -- re-drives the same node; deleting it would remove it from the scene for good.
    if Art.valid(self.hero and self.hero.root) and not (self.hero and self.hero.adopted) then
        scene.delete_node(self.hero.root)
    end
    self:create_hero()
    self:reset_manual_gear()
    self:ensure_hero_projectiles()
    self:reset_hero_projectiles()
    if self.config.hooks and self.config.hooks.on_reset then self.config.hooks.on_reset(self) end
    if self.mode_started then self:warm_creep_pool() end
    -- ATH_DUEL_GEARSET=mid|top equips a fixed loadout (balance-smoke knob).
    local gearset = ATH_COMMON.getenv and ATH_COMMON.getenv("ATH_DUEL_GEARSET", nil)
    if gearset and GEARSETS[gearset] then
        local by_id = {}
        for _, it in ipairs(self.gear_cfg.items or {}) do by_id[it.id] = it end
        for _, id in ipairs(GEARSETS[gearset]) do
            local it = by_id[id]
            if it and it.slot then self.gear_equipped[it.slot] = it end
        end
        self:log("gearset applied: " .. gearset)
    end
    -- Headless smokes skip straight into the run; players pick a destination
    -- on the world map first.
    if self.autoplay then
        self:enter_town()
        self:start_map()
    else
        self:enter_worldmap()
    end
end

function Duel:begin_manual_wave(index)
    self.wave_index = math.max(1, math.floor(index or 1))
    self.round = self.wave_index
    self.reserve_start = self:manual_wave_budget(self.wave_index)
    self.reserve = self.reserve_start
    self.round_t = 0.0
    self.spawn_t = 0.35
    self.spawn_queue = {}
    self:clear_telegraphs()
    self:reset_creep_projectiles()
    -- Fresh wave: dodge back to full, stale death-recap entries dropped.
    self.dmg_log = nil
    local hero = self.hero
    if hero then
        hero.dodge_charges = hero.dodge_charges_max or 1
        hero.dodge_recharge_t = hero.dodge_recharge or DODGE_RECHARGE
        hero.dodge_t = 0.0
        hero.dodge_iframe_t = 0.0
    end
    -- PLAN step 2: every round opens with a 1-of-3 draft of run-scoped boons;
    -- combat starts when the player picks (see pick_draft_card).
    local catalog = self.config.draft_cards or DRAFT_CARDS
    if self.manual_hero and #catalog > 0 then
        self:begin_draft(catalog)
    else
        self.state = "combat"
        self:set_flash("WAVE " .. tostring(self.wave_index))
    end
    self:log(string.format("wave start wave=%d budget=%.0f", self.wave_index, self.reserve_start))
end

-- ---------------------------------------------------------------------------
-- Wave-start draft — 3 rarity-weighted, distinct boons from the catalog.
-- Picked cards stack in D.run_cards for the rest of the run (cleared on reset)
-- and are applied by recompute_hero_stats on top of base + gear.
-- ---------------------------------------------------------------------------
function Duel:begin_draft(catalog)
    local picks, used = {}, {}
    for _ = 1, 200 do
        if #picks >= 3 then break end
        local total = 0
        for _, cd in ipairs(catalog) do
            if not used[cd.id] then total = total + (DRAFT_WEIGHTS[cd.rarity or "common"] or 10) end
        end
        if total <= 0 then break end
        local r = math.random() * total
        for _, cd in ipairs(catalog) do
            if not used[cd.id] then
                r = r - (DRAFT_WEIGHTS[cd.rarity or "common"] or 10)
                if r <= 0 then
                    used[cd.id] = true
                    picks[#picks + 1] = cd
                    break
                end
            end
        end
    end
    if #picks == 0 then
        self.state = "combat"
        self:set_flash("WAVE " .. tostring(self.wave_index))
        return
    end
    self.draft_offer = picks
    self.state = "draft"
    self:set_flash("WAVE " .. tostring(self.wave_index) .. " - CHOOSE A BOON")
end

function Duel:pick_draft_card(i)
    local card = self.draft_offer and self.draft_offer[i]
    if not card then return end
    self.run_cards = self.run_cards or {}
    self.run_cards[#self.run_cards + 1] = card
    self:recompute_hero_stats()
    if card.effect and card.effect.heal and self.hero then
        self.hero.hp = math.min(self.hero.hp_max, self.hero.hp + card.effect.heal)
    end
    self.draft_offer = nil
    self.state = "combat"
    self:set_flash(tostring(card.name) .. " - WAVE " .. tostring(self.wave_index))
    self:haptic(12)
    self:log(string.format("draft pick wave=%d card=%s", self.wave_index or 1, tostring(card.id)))
end

function Duel:manual_wave_done()
    return (self.reserve or 0.0) < self:minimum_spawn_cost()
        and (not self.spawn_queue or #self.spawn_queue == 0)
        and (not self.telegraphs or #self.telegraphs == 0)
        and self:count_alive() == 0
end

-- Kills drop PHYSICAL loot at the corpse: gold coins always (heftier enemies
-- shower more), an item beacon on the drop cadence, an occasional elite piece,
-- and a two-piece rare-or-better shower from the boss.
function Duel:maybe_drop_manual_gear(c)
    if not self.manual_hero then return end
    local s = (c and c.stats) or {}
    local x = (c and c.x) or (self.hero and self.hero.x) or 0.0
    local z = (c and c.z) or (self.hero and self.hero.z) or 0.0
    local cost = s.threat_cost or 1
    -- Gold scales steeply with map rank (deep maps are the income; wave-one
    -- suicide farming on map I stays poor).
    local gold_mult = self:active_map().gold_mult or 1.0
    local base_gold = math.max(1, math.floor((self.gear_cfg.gold_per_kill or 1) * gold_mult + 0.5))
    local coins = 1
    if s.boss then coins = 7 elseif c and c.elite then coins = 4 elseif cost >= TELEGRAPH_BIG_COST then coins = 2 end
    for _ = 1, coins do
        self:spawn_coin(x, z, base_gold * (cost >= TELEGRAPH_BIG_COST and 2 or 1))
    end

    local items = self.gear_cfg.items or {}
    if #items == 0 then return end
    -- Drops roll rarity-weighted by the active map (deeper = shinier).
    if s.boss then
        self:spawn_item_beacon(x - 0.9, z, self:roll_drop_item(items, "rare"))
        self:spawn_item_beacon(x + 0.9, z, self:roll_drop_item(items, "uncommon"))
        return
    end
    if c and c.elite then
        if math.random() <= 0.20 then self:spawn_item_beacon(x, z, self:roll_drop_item(items)) end
        return
    end
    local every = math.max(1, math.floor(self.gear_cfg.drop_every or 6))
    if (self.kills % every) ~= 0 then return end
    self:spawn_item_beacon(x, z, self:roll_drop_item(items))
end

local function apply_gear_effect(hero, effect)
    if not effect then return end
    if effect.dps_mult then hero.dps = hero.dps * effect.dps_mult end
    if effect.dps_add then hero.dps = hero.dps + effect.dps_add end
    if effect.cleave_add then hero.cleave = hero.cleave + effect.cleave_add end
    if effect.attack_range_add then hero.attack_range = hero.attack_range + effect.attack_range_add end
    if effect.speed_mult then hero.speed = hero.speed * effect.speed_mult end
    if effect.kite_speed_mult then hero.kite_speed = hero.kite_speed * effect.kite_speed_mult end
    if effect.hp_max_add then hero.hp_max = hero.hp_max + effect.hp_max_add end
    if effect.armor_add then hero.armor = clampn((hero.armor or 0.0) + effect.armor_add, -0.5, 0.85) end
    if effect.lifesteal_add then hero.lifesteal = (hero.lifesteal or 0.0) + effect.lifesteal_add end
    if effect.regen_add then hero.regen = (hero.regen or 0.0) + effect.regen_add end
    if effect.whirl_add then hero.whirl = (hero.whirl or 0) + effect.whirl_add end
    if effect.thorns_add then hero.thorns = (hero.thorns or 0.0) + effect.thorns_add end
    if effect.dash_add then hero.dash = (hero.dash or 0) + effect.dash_add end
    -- Attack-speed gear (ranged): lowers fire_interval.
    if effect.fire_interval_mult then hero.fire_interval = (hero.fire_interval or 0.28) * effect.fire_interval_mult end
    -- Crit is ROLLED per hit now (see hit_creep), not folded into average dps.
    if effect.crit_add then hero.crit_chance = (hero.crit_chance or 0.0) + effect.crit_add end
    if effect.pickup_range_add then hero.pickup_range = (hero.pickup_range or PICKUP_RANGE_BASE) + effect.pickup_range_add end
    if effect.gold_find_add then hero.gold_find = (hero.gold_find or 1.0) + effect.gold_find_add end
    if effect.slow_aura then hero.slow_aura = true end
    -- Dodge gear: extra charges / faster recharge (Normal-dodge machinery).
    if effect.dodge_charge_add then hero.dodge_charges_max = (hero.dodge_charges_max or 1) + effect.dodge_charge_add end
    if effect.dodge_recharge_mult then hero.dodge_recharge = (hero.dodge_recharge or DODGE_RECHARGE) * effect.dodge_recharge_mult end
end

local ARMOR_SLOTS = { "helmet", "body", "pants", "gloves" }

local function apply_equip_load(hero, equipped)
    local load = 0
    for _, slot in ipairs(ARMOR_SLOTS) do
        local item = equipped and equipped[slot]
        load = load + ((item and item.weight) or 0)
    end
    local speed_mult, tier = 1.0, "LIGHT"
    if load > 100 then
        speed_mult, tier = 0.20, "OVERLOADED"
    elseif load > 70 then
        speed_mult, tier = 0.70, "HEAVY"
    elseif load > 30 then
        speed_mult, tier = 0.85, "NORMAL"
    end
    hero.equip_load = load
    hero.equip_load_tier = tier
    hero.speed = hero.speed * speed_mult
    hero.kite_speed = hero.kite_speed * speed_mult
end

function Duel:recompute_hero_stats()
    local hero = self.hero
    if not hero then return end
    local base = hero.base_stats or {}
    local old_hp = hero.hp or base.hp_max or 1.0
    local old_max = hero.hp_max or base.hp_max or 1.0

    hero.hp_max = base.hp_max or hero.hp_max or 1.0
    hero.dps = base.dps or hero.dps or 1.0
    hero.cleave = base.cleave or hero.cleave or 1
    hero.attack_range = base.attack_range or hero.attack_range or 1.0
    hero.speed = base.speed or hero.speed or 1.0
    hero.kite_speed = base.kite_speed or hero.kite_speed or hero.speed
    hero.armor = base.armor or 0.0
    hero.lifesteal = base.lifesteal or 0.0
    hero.regen = base.regen or 0.0
    hero.whirl = base.whirl or 0
    hero.thorns = base.thorns or 0.0
    hero.dash = base.dash or 0
    hero.crit_chance = base.crit_chance or 0.03
    hero.pickup_range = base.pickup_range or PICKUP_RANGE_BASE
    hero.gold_find = base.gold_find or 1.0
    hero.slow_aura = false
    hero.fire_interval = hero.base_fire_interval or hero.fire_interval or 0.28
    -- Dodge gear resets from the Normal-dodge baseline before gear reapplies.
    hero.dodge_charges_max = 1
    hero.dodge_recharge = DODGE_RECHARGE

    for _, slot in ipairs({ "helmet", "body", "pants", "gloves", "weapon", "jewelry" }) do
        local item = self.gear_equipped and self.gear_equipped[slot]
        if item then apply_gear_effect(hero, item.effect) end
    end
    -- Run-scoped drafted boons stack on top of base + gear.
    for _, card in ipairs(self.run_cards or {}) do
        apply_gear_effect(hero, card.effect)
    end
    apply_equip_load(hero, self.gear_equipped)
    hero.dodge_charges = math.min(hero.dodge_charges or 1, hero.dodge_charges_max)

    local delta = hero.hp_max - old_max
    if delta > 0.0 then
        hero.hp = math.min(hero.hp_max, old_hp + delta)
    else
        hero.hp = math.min(old_hp, hero.hp_max)
    end
end

function Duel:reset_manual_gear()
    self.gold = self.gold or 0
    self.inv_grid = self.inv_grid or {}
    self.gear_equipped = self.gear_equipped or { helmet = nil, body = nil, pants = nil, gloves = nil, weapon = nil, jewelry = nil }
    self.gear_drop_cursor = 0
    self.run_cards = {}
    self.draft_offer = nil
    self._inv_drag = nil
    self._inv_last_click = nil
    self._between_wave = nil
    self:recompute_hero_stats()
end

-- The hero's TOTAL stats from base + everything equipped, computed WITHOUT
-- mutating the live hero (the inventory's live preview reads this every frame).
function Duel:gear_preview_stats()
    local hero = self.hero
    if not hero then return {} end
    local base = hero.base_stats or {}
    local t = {
        hp_max = base.hp_max or hero.hp_max or 1.0,
        dps = base.dps or hero.dps or 1.0,
        cleave = base.cleave or hero.cleave or 1,
        attack_range = base.attack_range or hero.attack_range or 1.0,
        speed = base.speed or hero.speed or 1.0,
        kite_speed = base.kite_speed or hero.kite_speed or 1.0,
        armor = base.armor or 0.0,
        lifesteal = base.lifesteal or 0.0,
        regen = base.regen or 0.0,
        whirl = base.whirl or 0,
        thorns = base.thorns or 0.0,
        dash = base.dash or 0,
        crit_chance = base.crit_chance or 0.03,
        pickup_range = base.pickup_range or PICKUP_RANGE_BASE,
        gold_find = base.gold_find or 1.0,
        fire_interval = hero.base_fire_interval or hero.fire_interval or 0.28,
        dodge_charges_max = 1, dodge_recharge = DODGE_RECHARGE,
    }
    for _, slot in ipairs({ "helmet", "body", "pants", "gloves", "weapon", "jewelry" }) do
        local item = self.gear_equipped and self.gear_equipped[slot]
        if item then apply_gear_effect(t, item.effect) end
    end
    for _, card in ipairs(self.run_cards or {}) do
        apply_gear_effect(t, card.effect)
    end
    apply_equip_load(t, self.gear_equipped)
    return t
end

-- ---------------------------------------------------------------------------
-- AI seat — the side the player did NOT pick is resolved heuristically.
-- ---------------------------------------------------------------------------

function Duel:swarm_summary()
    local n, sp, dps, tanky = 0, 0.0, 0.0, false
    for _, c in ipairs(self.creeps) do
        if c.alive and c.stats then
            n = n + 1
            sp = sp + (c.stats.speed or 0.0)
            dps = dps + (c.stats.dps or 0.0)
            if (c.stats.hp_max or c.stats.hp or 0) >= 24 then tanky = true end
        end
    end
    local hero = self.hero
    return {
        count = n, avg_speed = n > 0 and sp / n or 0.0, incoming_dps = dps, tanky = tanky,
        hp_pct = hero and (hero.hp / math.max(1.0, hero.hp_max)) or 1.0,
    }
end

-- Score a hero FRONT effect against current pressure (higher = better pick).
function Duel:score_front(e, swarm)
    if not e then return -1 end
    local score = 0.0
    local low = (swarm.hp_pct or 1.0) <= 0.5 or (swarm.incoming_dps or 0.0) >= 14.0
    local crowded = (swarm.count or 0) >= 14
    local outrun = (swarm.avg_speed or 0.0) >= (self.hero.speed or 2.0) + 0.3
    if low then
        score = score + (e.heal or 0) * 0.04 + (e.hp_max_add or 0) * 0.03 + (e.regen_add or 0) * 3.0
            + (e.armor_add or 0) * 30.0 + (e.lifesteal_add or 0) * 4.0
    end
    if crowded then
        score = score + (e.cleave_add or 0) * 6.0 + (e.whirl_add or 0) * 6.0 + (e.attack_range_add or 0) * 8.0
    end
    if outrun then
        score = score + ((e.speed_mult and (e.speed_mult - 1.0) * 30.0) or 0) + (e.dash_add or 0) * 6.0
    end
    -- Always value raw damage as the baseline.
    score = score + ((e.dps_mult and (e.dps_mult - 1.0) * 20.0) or 0) + (e.dps_add or 0) * 1.2
    return score
end

-- Score a horde BACK effect (higher = more useful pressure right now).
function Duel:score_back(e, swarm)
    if not e then return -1 end
    if e.kind == "spawn" then
        if self.reserve < (e.reserve_cost or 0) then return -1 end
        local headroom = self:live_cap() - (swarm.count or 0)
        return 8.0 + math.min(headroom, (e.count or 1)) * 1.5 - (e.reserve_cost or 0) * 0.1
    elseif e.kind == "swarm" then
        return 5.0 + (e.dps_add or 0) * 2.0 + (e.hp_add or 0) * 0.4 + (e.speed_add or 0) * 4.0
    elseif e.kind == "escalate" then
        return 4.0 + (e.batch_add or 0) * 1.5 + (e.cap_add or 0) * 0.2
    elseif e.kind == "weaken" then
        return ((swarm.hp_pct or 1.0) > 0.6) and 6.0 or 2.0
    elseif e.kind == "reserve" then
        return (self.reserve < self.reserve_start * 0.3) and 7.0 or 1.0
    end
    return 0.0
end

-- Resolve the AI seat fully: greedily play the best-scoring affordable card
-- until command runs out or nothing scores positively.
function Duel:resolve_ai_seat(seat)
    local picks = 0
    for _ = 1, 6 do
        local swarm = self:swarm_summary()
        local actions = Cards.legal_actions(seat, true)
        if #actions == 0 then break end
        local best, best_score
        for _, action in ipairs(actions) do
            local e = Cards.face(action.card, seat.side)
            local sc = (seat.side == "hero") and self:score_front(e, swarm) or self:score_back(e, swarm)
            if not best or sc > best_score then best, best_score = action, sc end
        end
        if not best or (best_score or 0) <= 0 then break end
        local card_id = best.card
        local ok, _, effect = Cards.play(seat, best.slot)
        if not ok then break end
        self:resolve_card(seat, card_id, effect)
        picks = picks + 1
        if seat.side == "hero" then
            self.hero.thought = (Cards.card(card_id) and Cards.card(card_id).name or card_id)
        end
    end
    return picks
end

-- ---------------------------------------------------------------------------
-- Human seat input (the side the player picked)
-- ---------------------------------------------------------------------------

function Duel:play_human_card(slot)
    local seat = self.player_seat
    local card_id = seat.hand[slot]
    if not card_id then return end
    -- Pre-check a horde spawn so it never burns command it cannot pay for.
    if seat.side == "horde" then
        local effect = Cards.face(card_id, "horde")
        if effect and effect.kind == "spawn" and self.reserve < (effect.reserve_cost or 0) then
            self:set_flash("Reserve too low")
            return
        end
    end
    local ok, msg, eff = Cards.play(seat, slot)
    if not ok then self:set_flash(msg); return end
    local applied, amsg = self:resolve_card(seat, card_id, eff)
    local name = Cards.card(card_id) and Cards.card(card_id).name or card_id
    self:set_flash(applied and (name .. ": " .. tostring(amsg)) or tostring(amsg))
end

-- ---------------------------------------------------------------------------
-- Round / pause loop
-- ---------------------------------------------------------------------------

function Duel:begin_pause()
    if self.manual_hero then
        self:vacuum_pickups() -- bank whatever's still on the floor before the pause
        if self.hero and not self.hero.dead then
            Art.burst("ath_wave_clear", vec3(self.hero.x, 0.8, self.hero.z),
                { preset = "hero_take", count = 26, life_max = 0.5, spawn_radius = 0.6, size_max = 0.2,
                  color_start = vec4(1.0, 0.9, 0.4, 1.0), gravity = vec3(0.0, 2.6, 0.0) })
        end
        self.state = "pause"
        self._between_wave = true -- a wave-flow pause: NEXT WAVE advances the run
        self:haptic(25)
        self:set_flash("WAVE " .. tostring(self.wave_index or 1) .. " CLEARED")
        self:save_profile()
        if self.config.hooks and self.config.hooks.on_pause then self.config.hooks.on_pause(self) end
        local bag = 0; for _, it in pairs(self.inv_grid or {}) do if it then bag = bag + 1 end end
        self:log(string.format("pause wave=%d gold=%d bag=%d", self.wave_index or 1, self.gold or 0, bag))
        return
    end

    self.state = "pause"
    self.round = self.round + 1
    Cards.start_pause(self.player_seat)
    Cards.start_pause(self.ai_seat)
    self:resolve_ai_seat(self.ai_seat) -- the AI side commits immediately
    self:set_flash("ROUND " .. tostring(self.round) .. " — your move")
    if self.config.hooks and self.config.hooks.on_pause then self.config.hooks.on_pause(self) end
    self:log(string.format("pause round=%d reserve=%.0f swarm=%d", self.round, self.reserve, self:count_alive()))
end

function Duel:resume_combat()
    if self.manual_hero then
        Inventory.hide(self)
        if self._between_wave then
            self._between_wave = false
            self:begin_manual_wave((self.wave_index or 1) + 1)
        else
            -- A mid-fight inventory peek (gear button) closes back to the SAME wave.
            self._between_wave = false
            self.state = "combat"
        end
        if self.config.hooks and self.config.hooks.on_resume then self.config.hooks.on_resume(self) end
        return
    end

    self.state = "combat"
    self.round_t = self.round_seconds
    self.spawn_t = math.min(self.spawn_t or 0.4, 0.4)
    self:set_flash("FIGHT")
    if self.config.hooks and self.config.hooks.on_resume then self.config.hooks.on_resume(self) end
end

-- Gear button (authored "HUD Gear Hit"): open/close the authored Pause Menu
-- inventory mid-run WITHOUT advancing the wave. A between-wave pause is owned by
-- the wave flow, so the gear button never closes that (use NEXT WAVE / Enter).
function Duel:toggle_inventory()
    if not self.manual_hero then return end
    if self.state == "pause" then
        if not self._between_wave then self:resume_combat() end
    elseif self.state == "combat" then
        self._between_wave = false
        self.state = "pause"
        self:haptic(15)
        Inventory.show(self)
    end
end

function Duel:reset_run(to_town)
    for _, c in ipairs(self.creeps) do
        self:park_blast_decal(c)
        Creep.destroy(c)
    end
    self.creeps = {}
    self:flush_dying()
    -- Drop parked rigs before the hero (their scene sibling under the actors
    -- group) is deleted+rebuilt: the swap-and-pop on that delete would stale
    -- their handles. New rigs are built only as the spawn queue drains.
    Creep.clear_pool()
    -- Adopted heroes (authored scene node) are re-found by create_hero, never deleted.
    if Art.valid(self.hero and self.hero.root) and not (self.hero and self.hero.adopted) then
        scene.delete_node(self.hero.root)
    end
    self:create_hero()
    self.combat_time = 0.0
    self.round = 1
    self.round_t = self.round_seconds
    self.spawn_t = 0.6
    self.spawn_counter = 0
    self.spawn_queue = {}
    self.kills = 0
    self.reserve = self.reserve_start
    self.buffs = { speed = 0.0, power = 0.0, hp = 0.0 }
    self.spawn_mods = { batch_add = 0, cap_add = 0, interval_mult = 1.0 }
    self.slowmo_t = 0.0
    self.hitstop_t = 0.0
    self._hurt_t = 0.0
    self.boss_spawned = false
    self.boss_creep = nil
    self.field = nil
    self.field_t = 0.0
    self:clear_telegraphs()
    self:reset_creep_projectiles()
    self:clear_damage_numbers()
    if self.manual_hero then
        self.player_seat = nil
        self.ai_seat = nil
        self:reset_manual_gear()
        self:ensure_hero_projectiles()
        self:reset_hero_projectiles()
        self:ensure_creep_projectiles()
        self:ensure_telegraph_pool()
        self:ensure_pickup_pools()
        self:reset_pickups()
        if to_town and self.hero_class then
            self:enter_town()
        elseif self.config.hero and self.config.hero.classes then
            self:begin_class_pick()
        else
            self:begin_manual_wave(ATH_COMMON.getenv_number("ATH_DUEL_WAVE", 1))
        end
    else
        self.state = "combat"
        self.player_seat = Cards.create({ side = self.side, deck = self.ctx.deck })
        self.ai_seat = Cards.create({ side = (self.side == "hero") and "horde" or "hero", deck = Cards.default_deck })
        self:set_flash("FIGHT")
    end
    if self.config.hooks and self.config.hooks.on_reset then self.config.hooks.on_reset(self) end
    if self.mode_started then self:warm_creep_pool() end
    self:log("run reset side=" .. self.side)
end

function Duel:update_input(dt)
    if self:key_pressed("R") then
        self:reset_run(self.manual_hero and (self.state == "slain" or self.state == "hero_win"))
        return
    end
    if self:key_pressed("Escape") or self:key_pressed("M") then
        if self.shell and self.shell.return_to_menu then self.shell.return_to_menu() end
        return
    end

    if self.state == "classpick" then
        local list = self.config.hero and self.config.hero.classes or {}
        for i = 1, #list do
            if self:key_pressed(tostring(i)) or Art.consume_click(self.hud, "classpick_" .. i) then
                self:choose_class(i)
                return
            end
        end
        return
    end

    if self.state == "worldmap" then
        local max_map = math.min((self.maps_cleared or 0) + 1, #self.maps)
        local function travel()
            self:enter_town(self._wm_from_town)
            self:set_flash("DESTINATION: " .. tostring(self:active_map().name))
        end
        local step = (self:key_pressed("Right") and 1 or 0) - (self:key_pressed("Left") and 1 or 0)
        if step ~= 0 then
            self.map_index = clampn(self.map_index + step, 1, max_map)
            self:haptic(8)
        end
        for i = 1, #self.maps do
            if Art.consume_click(self.hud, "wm_node_" .. i) then
                if i > max_map then
                    self:set_flash("LOCKED - clear " .. tostring((self.maps[i - 1] and self.maps[i - 1].name) or "the previous map"))
                elseif i == self.map_index then
                    travel() -- second click on the selected badge = go
                    return
                else
                    self.map_index = i
                    self:haptic(8)
                end
            end
        end
        if self:key_pressed("Return") or self:key_pressed("Space") or Art.consume_click(self.hud, "wm_travel") then
            travel()
            return
        end
        -- Headless smokes never sit on menus.
        if self.autoplay then
            self.autoplay_t = (self.autoplay_t or 1.2) - dt
            if self.autoplay_t <= 0.0 then
                self.autoplay_t = 1.2
                travel()
            end
        end
        return
    end

    if self.state == "town" then
        Inventory.update(self)
        for i, slot in ipairs(Inventory.SLOTS) do
            if self:key_pressed(tostring(i)) then self:buy_store_offer(slot) end
        end
        -- Destination banner (or Left/Right) reopens the world map.
        if #self.maps > 1
            and (Art.consume_click(self.hud, "town_dest") or self:key_pressed("Left") or self:key_pressed("Right")) then
            self:enter_worldmap()
            return
        end
        if self:key_pressed("Return") or self:key_pressed("Space") then self:start_map() end
        return
    end

    if self.state == "draft" then
        for i = 1, #(self.draft_offer or {}) do
            if self:key_pressed(tostring(i)) or Art.consume_click(self.hud, "draft_" .. i) then
                self:pick_draft_card(i)
                return
            end
        end
        -- Headless smokes (ATH_DUEL_AUTOPLAY) pick the first boon automatically.
        if self.autoplay then
            self.autoplay_t = (self.autoplay_t or 0.4) - dt
            if self.autoplay_t <= 0.0 then
                self.autoplay_t = 0.4
                self:pick_draft_card(1)
            end
        end
        return
    end

    if self.state == "pause" then
        if self.manual_hero then
            Inventory.update(self) -- drag-and-drop + click-to-(un)equip over authored nodes
            -- The authored "Pause Next Wave" button resumes via its own node script
            -- (on_next_wave); keep keyboard resume here.
            if self:key_pressed("Return") or self:key_pressed("Space") then
                self:resume_combat()
            end
            -- Headless smokes roll into the next wave after a short gear-up beat.
            if self.autoplay then
                self.autoplay_t = (self.autoplay_t or 1.2) - dt
                if self.autoplay_t <= 0.0 then
                    self.autoplay_t = 1.2
                    self:resume_combat()
                end
            end
            return
        end

        for slot = 1, 5 do
            if self:key_pressed(tostring(slot)) then self:play_human_card(slot) end
            if Art.consume_click(self.hud, "card_slot" .. slot) then self:play_human_card(slot) end
        end
        if self:key_pressed("Return") or self:key_pressed("Space") or Art.consume_click(self.hud, "resume_btn") then
            self:resume_combat()
        end
        if self.autoplay then
            self.autoplay_t = (self.autoplay_t or 0.0) - dt
            if self.autoplay_t <= 0.0 then
                self.autoplay_t = 0.5
                if Cards.can_play(self.player_seat) then
                    self:resolve_ai_seat(self.player_seat)
                else
                    self:resume_combat()
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- HUD
-- ---------------------------------------------------------------------------

function Duel:hand_lines()
    local seat = self.player_seat
    local lines = {}
    for _, action in ipairs(Cards.legal_actions(seat, false)) do
        local mark = action.affordable and " " or "x"
        lines[#lines + 1] = string.format("[%d]%s %s (%d) — %s", action.slot, mark, action.label, action.cost, action.desc)
    end
    if #lines == 0 then lines[1] = "(hand empty)" end
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("Command %d/%d     [Enter] resume", seat.command, seat.command_max)
    return table.concat(lines, "\n")
end

function Duel:update_hud()
    if not (runtime_ui and runtime_ui.set_quad) then return end
    local sw, sh = Art.surface_size()
    local hero = self.hero
    local accent = self.theme.accent or { 0.62, 0.34, 0.86, 0.95 }
    -- Every HUD dimension/offset multiplies by S() so panels grow with the text.
    local function S(v) return v * Art.s("hud") end

    -- Hero HP bar (top center).
    local bw, bh = S(520.0), S(36.0)
    local bx, by = sw * 0.5 - bw * 0.5, S(28.0)
    local pct = clampn((hero.hp or 0.0) / (hero.hp_max or 1.0), 0.0, 1.0)
    local hp_color = pct > 0.5 and { 0.36, 0.78, 0.42, 0.95 } or (pct > 0.25 and { 0.92, 0.74, 0.28, 0.95 } or { 0.90, 0.30, 0.26, 0.95 })
    -- config.external_hud (set by the scene-driven game_boot) means an authored
    -- scene UI draws the HP + wave-budget bars instead, so skip the built-ins.
    if not self.config.external_hud then
        Art.bar(self.hud, "hp", bx, by, bw, bh, pct, hp_color, { label = string.format("HERO  %d / %d", math.floor(hero.hp + 0.5), math.floor(hero.hp_max + 0.5)) })
    end

    -- Top-left status — ONE compact multi-line label. Drawn from the top edge, so
    -- the frame hugs the text (the title/body layout reserves a tall empty "art"
    -- band up top). Sized to the text scale; font bumped for legibility.
    local side_label = (self.side == "hero") and "YOU: HERO" or "YOU: HORDE"
    local TS = Art.s("text")
    local status_text
    if self.manual_hero then
        local map = self:active_map()
        status_text = string.format("%s\nYOU: HERO  -  Wave %d/%d\nBudget %d / %d\nSwarm %d    Kills %d\nGold %d",
            (map.name and (tostring(map.name) .. "  (Rank " .. tostring(map.rank or "?") .. ")"))
                or self.theme.hud_title or (self.config.name or "DUEL"),
            self.wave_index or 1, self.wave_cfg.count or 5,
            math.floor((self.reserve or 0.0) + 0.5), math.floor((self.reserve_start or 1.0) + 0.5),
            self:count_alive(), self.kills, self.gold or 0)
    else
        status_text = string.format("%s\n%s  -  Round %d\nReserve %d / %d\nSwarm %d    Kills %d\nHero: %s",
            (self.theme.hud_title or (self.config.name or "DUEL")), side_label, self.round,
            math.floor(self.reserve + 0.5), math.floor(self.reserve_start),
            self:count_alive(), self.kills, (hero.thought ~= "" and hero.thought or "-"))
    end
    Art.quad(self.hud, "stat", S(20.0), S(20.0), 200.0 * TS, 112.0 * TS, { 0.04, 0.04, 0.06, 0.88 }, {
        border = accent, font_scale = 1.25, text_color = { 0.95, 0.96, 1.0, 1.0 }, no_input = true,
        label = status_text,
    })

    -- Horde Reserve bar (bottom-right — modes draw their own readout bottom-left).
    local dw = S(440.0)
    local dx, dy = sw - dw - S(24.0), sh - S(58.0)
    if not self.config.external_hud then
        Art.bar(self.hud, "reserve", dx, dy, dw, S(32.0), clampn(self.reserve / self.reserve_start, 0.0, 1.0),
            { 0.86, 0.34, 0.30, 0.95 },
            { label = string.format("%s %d / %d", self.manual_hero and "WAVE BUDGET" or "HORDE RESERVE",
                math.floor(self.reserve + 0.5), math.floor(self.reserve_start)) })
    end

    -- Skip the flash banner on the manual gear screen (the inventory title says
    -- the same thing, and the flash sits right where the title bar is).
    if self.flash and self.flash ~= "" and not (self.manual_hero and (self.state == "pause" or self.state == "town")) then
        Art.quad(self.hud, "flash", sw * 0.5 - S(260.0), S(96.0), S(520.0), S(34.0), { 0.0, 0.0, 0.0, 0.0 },
            { label = self.flash, text_color = { 0.95, 0.82, 0.35, math.min(1.0, self.flash_t) } })
    else
        Art.remove(self.hud, "flash")
    end

    -- Pause overlay. The MANUAL arena's pause/inventory is now AUTHORED: the
    -- "Pause Menu" scene-node group owns the backpack grid, paper-doll, stat panel,
    -- title and NEXT WAVE button (see ath_inventory). The script only toggles the
    -- group's visibility by state and pushes current values into it. Legacy
    -- (non-manual) duel modes still draw their transient card hand here.
    if self.manual_hero then
        if self.state == "pause" or self.state == "town" then
            Inventory.show(self)
            Inventory.refresh(self)
        else
            Inventory.hide(self)
        end
    elseif self.state == "pause" then
        local card_w, card_h, gap = S(150.0), S(196.0), S(10.0)
        local row_w = 5 * (card_w + gap) - gap
        local start_x = sw * 0.5 - row_w * 0.5
        local resume_h = S(42.0)
        local resume_y = sh - S(16.0) - resume_h
        local card_y = resume_y - gap - card_h
        local panel_h = S(42.0)
        local panel_y = card_y - gap - panel_h

        Art.remove_ids(self.hud, { "gear_equipped", "gear_inv_slot1", "gear_inv_slot2", "gear_inv_slot3", "gear_inv_slot4", "gear_inv_slot5" })
        local seat = self.player_seat
        local who = (seat.side == "hero") and "UPGRADE THE HERO" or "COMMAND THE HORDE"
        local actions = Cards.legal_actions(seat, false)
        Art.quad(self.hud, "pause_panel", start_x, panel_y, row_w, panel_h, { 0.06, 0.05, 0.10, 0.92 },
            { border = accent, title = string.format("PAUSE - Round %d - %s", self.round, who), no_input = true })
        for slot = 1, 5 do
            local id = "card_slot" .. slot
            local action = actions[slot]
            if action then
                local rar = Cards.rarity(action.card)
                local fill = action.affordable and { 0.10, 0.10, 0.16, 0.95 } or { 0.06, 0.05, 0.06, 0.9 }
                Art.quad(self.hud, id, start_x + (slot - 1) * (card_w + gap), card_y, card_w, card_h, fill, {
                    border = rar.color,
                    title = action.label,
                    subtitle = string.format("Cost %d  %s%s", action.cost, string.rep("*", rar.stars), action.affordable and "" or "  (locked)"),
                    body = action.desc,
                    footer = "[" .. slot .. "] / click",
                })
            else
                Art.remove(self.hud, id)
            end
        end
        Art.quad(self.hud, "resume_btn", sw * 0.5 - S(100.0), resume_y, S(200.0), resume_h, { 0.10, 0.16, 0.10, 0.95 },
            { border = { 0.4, 0.9, 0.5, 0.95 }, label = "RESUME   [Enter]" })
    else
        Art.remove_ids(self.hud, { "pause_panel", "resume_btn", "card_slot1", "card_slot2", "card_slot3", "card_slot4", "card_slot5" })
        Art.remove_ids(self.hud, { "gear_equipped", "gear_inv_slot1", "gear_inv_slot2", "gear_inv_slot3", "gear_inv_slot4", "gear_inv_slot5" })
    end

    -- Boss HP bar: top center, tucked right under the hero bar — the bottom band
    -- belongs to the defeat/pause panels and mid-arena sat on the boss itself.
    local boss = self.boss_creep
    if boss and boss.alive then
        local bw2 = S(640.0)
        Art.bar(self.hud, "boss", sw * 0.5 - bw2 * 0.5, S(70.0), bw2, S(30.0),
            clampn((boss.hp or 0.0) / math.max(1.0, boss.hp_max or 1.0), 0.0, 1.0),
            { 0.78, 0.30, 0.86, 0.95 },
            { label = self:active_map().boss_title or self.config.boss_title or "BOSS", border = { 0.5, 0.2, 0.6, 0.95 } })
    else
        Art.remove_ids(self.hud, { "boss_bg", "boss_fg", "boss_label" })
    end

    -- Dodge readiness: a slim bar bottom-center — full/blue = ready, grey fill
    -- = recharge progress.
    if self.manual_hero and self.state == "combat" and hero and not hero.dead then
        local ready = (hero.dodge_charges or 0) >= 1
        local pct = ready and 1.0
            or clampn(1.0 - (hero.dodge_recharge_t or 0.0) / math.max(0.01, hero.dodge_recharge or 1.0), 0.0, 1.0)
        Art.bar(self.hud, "dodge", sw * 0.5 - S(110.0), sh - S(64.0), S(220.0), S(32.0), pct,
            ready and { 0.40, 0.78, 0.95, 0.95 } or { 0.42, 0.46, 0.54, 0.90 },
            { label = ready and "DODGE READY [Space]" or "DODGE . . .",
              border = ready and { 0.55, 0.88, 1.0, 0.9 } or { 0.40, 0.44, 0.50, 0.8 } })
    else
        Art.remove_ids(self.hud, { "dodge_bg", "dodge_fg", "dodge_label" })
    end

    -- Town destination banner: the picked map, top-center; click (or Left/Right)
    -- reopens the world map. The authored inventory owns the middle of the screen.
    if self.manual_hero and self.state == "town" and #self.maps > 0 then
        local m = self:active_map()
        Art.quad(self.hud, "town_dest", sw * 0.5 - S(250.0), S(26.0), S(500.0), S(72.0),
            { 0.07, 0.09, 0.12, 0.92 }, { border = { 0.75, 0.62, 0.35, 0.9 }, align_h = "center",
              label = string.format("DESTINATION: %s  (Rank %s)\nclick to change map   -   [Enter] embark",
                  tostring(m.name), tostring(m.rank or "?")) })
    else
        Art.remove(self.hud, "town_dest")
    end

    -- World map screen: the painted overworld with one badge per map. Locked
    -- badges are dimmed; the selected badge carries a gold ring. A route of
    -- dots links the ladder in rank order.
    if self.state == "worldmap" and #self.maps > 0 then
        local max_map = math.min((self.maps_cleared or 0) + 1, #self.maps)
        -- Full-bleed like the vignette: compensated coords cancel the viewport
        -- offset so the parchment covers the raw surface, not just the 20:9 band.
        local vp0 = Art._vp
        Art.quad(self.hud, "wm_bg", -vp0.x, -vp0.y, vp0.rw, vp0.rh, { 0.0, 0.0, 0.0, 0.0 },
            { style = "image", image = self.config.worldmap_image, no_input = true })
        Art.quad(self.hud, "wm_title", sw * 0.5 - S(240.0), S(16.0), S(480.0), S(50.0),
            { 0.08, 0.05, 0.02, 0.78 }, { border = { 0.85, 0.70, 0.40, 0.9 }, no_input = true,
              align_h = "center", label = "WORLD MAP - choose where to hunt" })
        local dot = 0
        for i = 2, #self.maps do
            local a = self.maps[i - 1].pos or { 0.5, 0.5 }
            local b = self.maps[i].pos or { 0.5, 0.5 }
            for k = 1, 7 do
                local t = k / 8.0
                dot = dot + 1
                local d = S(9.0)
                Art.quad(self.hud, "wm_dot_" .. dot,
                    sw * (a[1] + (b[1] - a[1]) * t) - d * 0.5, sh * (a[2] + (b[2] - a[2]) * t) - d * 0.5,
                    d, d, { 0.32, 0.22, 0.10, 0.85 }, { no_input = true })
            end
        end
        for i, m in ipairs(self.maps) do
            local locked = i > max_map
            local sel = i == self.map_index
            local px = sw * ((m.pos and m.pos[1]) or 0.5)
            local py = sh * ((m.pos and m.pos[2]) or 0.5)
            local r = sel and S(56.0) or S(46.0)
            -- Invisible click target (the badge art IS the button); only the
            -- selected node gets a frame, so boxes never stack on boxes.
            Art.quad(self.hud, "wm_node_" .. i, px - r, py - r, r * 2.0, r * 2.0,
                { 0.0, 0.0, 0.0, 0.0 },
                { border = sel and { 1.0, 0.85, 0.30, 1.0 } or { 0.0, 0.0, 0.0, 0.0 } })
            local pad = S(6.0)
            Art.quad(self.hud, "wm_ic_" .. i, px - r + pad, py - r + pad, (r - pad) * 2.0, (r - pad) * 2.0,
                { 0.0, 0.0, 0.0, 0.0 }, { style = "image", image = m.icon, no_input = true,
                  image_tint = locked and { 0.30, 0.28, 0.30, 1.0 } or { 1.0, 1.0, 1.0, 1.0 } })
            Art.quad(self.hud, "wm_nm_" .. i, px - S(95.0), py + r + S(8.0), S(190.0), S(36.0),
                { 0.08, 0.05, 0.02, locked and 0.55 or 0.80 }, { no_input = true, align_h = "center",
                  label = tostring(m.name) .. (locked and " - LOCKED" or ""),
                  text_color = locked and { 0.62, 0.60, 0.56, 1.0 } or { 0.98, 0.92, 0.76, 1.0 } })
        end
        -- The info panel IS the travel button (click it or [Enter]).
        local m = self:active_map()
        Art.quad(self.hud, "wm_travel", sw * 0.5 - S(280.0), sh - S(128.0), S(560.0), S(104.0),
            { 0.08, 0.05, 0.02, 0.90 }, { border = { 0.4, 0.9, 0.5, 0.95 },
              label = string.format("%s  [Rank %s]   %d waves   Boss: %s%s\n%s\nFoes x%.2g HP  x%.2g DMG   Gold x%.2g\n[Left]/[Right] pick   -   [Enter] / click here to TRAVEL",
                  tostring(m.name), tostring(m.rank or "?"), m.waves or 5, tostring(m.boss_title or "?"),
                  self.map_index <= (self.maps_cleared or 0) and "   (cleared)" or "",
                  tostring(m.blurb or ""), m.hp_mult or 1.0, m.dps_mult or 1.0, m.gold_mult or 1.0) })
    else
        local ids = { "wm_bg", "wm_title", "wm_travel" }
        for i = 1, 4 do
            ids[#ids + 1] = "wm_node_" .. i
            ids[#ids + 1] = "wm_ic_" .. i
            ids[#ids + 1] = "wm_nm_" .. i
        end
        for k = 1, 21 do ids[#ids + 1] = "wm_dot_" .. k end
        Art.remove_ids(self.hud, ids)
    end

    -- Gold readout: always on for the manual hero (combat, town, world map,
    -- pause, draft) — bottom-left corner, clear of every panel band. Created
    -- AFTER the world-map quads: the backend renders in creation order, so an
    -- older chip would vanish under the full-bleed parchment.
    if self.manual_hero and self.gold then
        Art.quad(self.hud, "gold_chip", S(16.0), sh - S(56.0), S(150.0), S(40.0),
            { 0.07, 0.06, 0.03, 0.85 }, { border = { 0.85, 0.72, 0.30, 0.9 }, no_input = true,
              label = string.format("GOLD  %d", math.floor(self.gold or 0)),
              text_color = { 0.98, 0.86, 0.36, 1.0 }, font_scale = 0.9,
              bring_to_front = (self.state == "worldmap") or nil })
    else
        Art.remove(self.hud, "gold_chip")
    end

    -- Hurt vignette: a brief red wash on damage + a low-HP pulse. Combat only so
    -- it never tints menus/inventory.
    local vg_a = 0.0
    if self.manual_hero and self.state == "combat" and hero and not hero.dead then
        vg_a = math.max(vg_a, 0.30 * ((self._hurt_t or 0.0) / 0.25))
        local pct2 = (hero.hp or 0.0) / math.max(1.0, hero.hp_max or 1.0)
        if pct2 < 0.35 then
            vg_a = math.max(vg_a, 0.09 + 0.07 * math.abs(math.sin(self.realtime * 4.0)))
        end
    end
    if vg_a > 0.01 then
        local vp = Art._vp
        Art.quad(self.hud, "vignette", -vp.x, -vp.y, vp.rw, vp.rh, { 0.72, 0.07, 0.05, vg_a }, { no_input = true })
    else
        Art.remove(self.hud, "vignette")
    end

    -- Wave-start draft overlay: pick 1 of 3 run-scoped boons (keys 1-3 / click).
    if self.state == "draft" then
        local offer = self.draft_offer or {}
        local n = math.max(1, #offer)
        local cw, ch, gap = S(210.0), S(240.0), S(16.0)
        local row_w = n * (cw + gap) - gap
        local sx0 = sw * 0.5 - row_w * 0.5
        local cyc = sh * 0.5 - ch * 0.5 + S(10.0)
        -- Compact quads draw `label` (title/subtitle sit below a tall reserved
        -- art band and vanish on short panels — the shell learned this too).
        Art.quad(self.hud, "draft_title", sw * 0.5 - S(280.0), cyc - S(72.0), S(560.0), S(54.0),
            { 0.05, 0.05, 0.10, 0.94 }, { border = accent, no_input = true,
              label = "WAVE " .. tostring(self.wave_index or 1) .. " - CHOOSE A BOON  ([1-" .. n .. "] or click)" })
        for i, cd in ipairs(offer) do
            Art.quad(self.hud, "draft_" .. i, sx0 + (i - 1) * (cw + gap), cyc, cw, ch,
                { 0.09, 0.10, 0.15, 0.97 }, {
                    border = RARITY_COLOR[cd.rarity or "common"] or accent,
                    title = cd.name,
                    body = "[" .. i .. "]  " .. string.upper(cd.rarity or "common") .. "\n\n" .. (cd.desc or ""),
                })
        end
    else
        Art.remove_ids(self.hud, { "draft_title", "draft_1", "draft_2", "draft_3" })
    end

    -- Class pick overlay (run start): one card per class, click or number key.
    if self.state == "classpick" then
        local list = self.config.hero and self.config.hero.classes or {}
        local n = math.max(1, #list)
        local cw, ch, gap = S(232.0), S(286.0), S(16.0)
        local row_w = n * (cw + gap) - gap
        local sx0 = sw * 0.5 - row_w * 0.5
        local cyc = sh * 0.5 - ch * 0.5 + S(20.0)
        Art.quad(self.hud, "classpick_title", sw * 0.5 - S(280.0), cyc - S(78.0), S(560.0), S(58.0),
            { 0.05, 0.05, 0.10, 0.94 }, { border = accent, title = "CHOOSE YOUR CLASS",
              subtitle = string.format("[1-%d] or click", n), no_input = true })
        for i, c in ipairs(list) do
            local x = sx0 + (i - 1) * (cw + gap)
            local stat
            if c.attack == "melee" then
                stat = string.format("HP %d    DMG %d\nReach %.1f   Cleave %d\nMove %.1f",
                    c.hp_max or 0, c.dps or 0, c.attack_range or 0, c.cleave or 0, c.speed or 0)
            else
                stat = string.format("HP %d    DMG %d/shot\nRange %.0f   Shots %d\nFire %.2fs",
                    c.hp_max or 0, c.dps or 0, c.attack_range or 0, c.cleave or 0, c.fire_interval or 0.28)
            end
            Art.quad(self.hud, "classpick_" .. i, x, cyc, cw, ch, { 0.09, 0.10, 0.15, 0.97 }, {
                border = c.accent or accent,
                title = c.name or c.id,
                subtitle = string.format("[%d]  %s", i, string.upper(c.attack or "ranged")),
                body = (c.blurb or "") .. "\n\n" .. stat,
            })
        end
    else
        Art.remove_ids(self.hud, { "classpick_title", "classpick_1", "classpick_2", "classpick_3", "classpick_4" })
    end

    -- Terminal banners.
    local player_won = (self.side == "hero" and self.state == "hero_win") or (self.side == "horde" and self.state == "slain")
    if self.state == "slain" or self.state == "hero_win" then
        local title, body
        if self.state == "slain" then
            title = (player_won and "VICTORY — the hero falls" or "DEFEAT — the hero falls")
            body = self.theme.lose_text or "The hero is slain.\nPress R to run it back  •  M for menu"
            if self.side == "horde" then body = self.theme.win_text or body end
            if self.manual_hero then
                -- Death recap: name the killer + the last three hits (newest first)
                -- straight from the apply_hero_damage ring buffer.
                title = "DEFEAT - the swarm takes you"
                local log = self.dmg_log or {}
                local lines = { "Killed by " .. ((#log > 0) and log[#log].src or "the swarm"), "" }
                for i = #log, 1, -1 do
                    local e = log[i]
                    lines[#lines + 1] = string.format("%s   -%.0f HP   %.1fs before death",
                        e.src, e.dmg, math.max(0.0, (self.death_time or e.t) - e.t))
                end
                lines[#lines + 1] = ""
                lines[#lines + 1] = "You fell before wave " .. tostring(self.wave_index or 1) .. ".  Press R to return to town"
                body = table.concat(lines, "\n")
            end
        else
            if self.manual_hero then
                title = "VICTORY - five waves cleared"
                body = "The arena is quiet for now.\nPress R to return to town"
            else
                title = (player_won and "VICTORY — the pit ran dry" or "DEFEAT — the hero prevails")
                body = "The reserve is spent and the field is clear.\nPress R to run it back   -   M for menu"
            end
        end
        local col = player_won and { 0.10, 0.18, 0.10, 0.92 } or { 0.18, 0.06, 0.06, 0.92 }
        local bord = player_won and { 0.4, 0.95, 0.5, 0.95 } or { 0.95, 0.4, 0.36, 0.95 }
        -- The manual defeat panel is taller (it carries the death recap) and is
        -- CENTERED: the legacy S(380) band runs off the bottom of the surface at
        -- HUD scale 2.775 and would clip the recap lines.
        local eh = (self.manual_hero and self.state == "slain") and S(230.0) or S(120.0)
        local ey = self.manual_hero and math.max(S(40.0), sh * 0.5 - eh * 0.5) or S(380.0)
        Art.quad(self.hud, "end", sw * 0.5 - S(300.0), ey, S(600.0), eh, col, { border = bord, title = title, body = body, no_input = true })
    else
        Art.remove(self.hud, "end")
    end

    -- Virtual movement joystick (touch / mouse-drag), combat only.
    if self.manual_hero and self.state == "combat" and self._stick then
        local vp = Art._vp
        local st = self._stick
        local R = st.R or S(120.0)
        Art.quad(self.hud, "stick_base", st.ox - vp.x - R, st.oy - vp.y - R, R * 2.0, R * 2.0,
            { 0.18, 0.42, 0.62, 0.16 }, { border = { 0.5, 0.8, 1.0, 0.35 }, no_input = true })
        local kr = R * 0.44
        Art.quad(self.hud, "stick_knob", st.kx - vp.x - kr, st.ky - vp.y - kr, kr * 2.0, kr * 2.0,
            { 0.45, 0.78, 1.0, 0.45 }, { border = { 0.7, 0.92, 1.0, 0.7 }, no_input = true })
    else
        Art.remove(self.hud, "stick_base")
        Art.remove(self.hud, "stick_knob")
    end

    if self.config.hooks and self.config.hooks.draw_hud then self.config.hooks.draw_hud(self) end
    Console.draw(self)
end

-- ---------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------

function Duel:update(dt)
    self.realtime = self.realtime + dt
    Console.update(self)
    Art.tick_iso_camera(dt)

    -- DIAG: the rendered view sometimes ends up ~19x more zoomed-in than the
    -- ortho size we set at start. Log the live camera state to catch who/when.
    if ATH_DEV and pe_log then
        self._cam_log_t = (self._cam_log_t or 0.0) - dt
        if self._cam_log_t <= 0.0 then
            self._cam_log_t = 2.0
            local cam = get_camera and get_camera()
            if cam and cam.get_orthographic_size then
                local p = cam.get_position and cam:get_position()
                local mode = cam.get_projection_mode and cam:get_projection_mode() or "?"
                local fov = cam.get_fov and cam:get_fov() or -1
                local n = 0
                if scene and scene.get_cameras then
                    for _ in pairs(scene.get_cameras()) do n = n + 1 end
                end
                -- Measure the REAL view height through the camera's actual
                -- matrix (fields can be right while the matrix is stale):
                -- project two world points 1 unit apart vertically-on-screen
                -- (z axis under the top-down rig) and read the clip-y delta.
                local vh = -1.0
                if cam.get_view_projection and vec4 then
                    local ok, h = pcall(function()
                        local vp = cam:get_view_projection()
                        local a = vp * vec4(17.5, 0.0, 18.5, 1.0)
                        local b = vp * vec4(17.5, 0.0, 19.5, 1.0)
                        local d = math.abs(b.y / b.w - a.y / a.w)
                        return d > 0.000001 and (2.0 / d) or -2.0
                    end)
                    vh = ok and h or -3.0
                end
                pe_log(string.format("[CAMDIAG] mode=%s ortho=%.2f fov=%.1f cams=%d view_h=%.2f pos=%s,%s,%s",
                    mode, cam:get_orthographic_size(), fov, n, vh,
                    p and string.format("%.1f", p.x) or "?",
                    p and string.format("%.1f", p.y) or "?",
                    p and string.format("%.1f", p.z) or "?"))
            end
        end
    end
    local sim_dt = dt
    if self.slowmo_t > 0.0 then
        self.slowmo_t = self.slowmo_t - dt
        sim_dt = dt * SLOWMO_SCALE
    end
    -- Hitstop: a few frames of near-freeze on meaty kills. Runs on REAL dt so it
    -- can't deadlock, and stacks under slowmo (the death beat).
    if (self.hitstop_t or 0.0) > 0.0 then
        self.hitstop_t = self.hitstop_t - dt
        sim_dt = sim_dt * HITSTOP_SCALE
    end
    self._hurt_t = math.max(0.0, (self._hurt_t or 0.0) - dt)

    self:update_input(dt)

    self:drain_spawn_queue(self.config.spawns_per_frame or 1)

    if self.state == "combat" then
        self.combat_time = self.combat_time + sim_dt
        self.round_t = self.round_t - sim_dt
        if self.use_flow_field then self:update_field(sim_dt) end -- else creeps beeline
        self:update_spawning(sim_dt)
        self:update_hero(sim_dt)
        self:update_creeps(sim_dt)
        self:update_telegraphs(sim_dt)
        self:update_creep_projectiles(sim_dt)
        self:update_pickups(sim_dt)
        if self.config.hooks and self.config.hooks.on_combat_tick then self.config.hooks.on_combat_tick(self, sim_dt) end
        if self.manual_hero and self.state == "combat" and self:manual_wave_done() then
            if (self.wave_index or 1) >= (self.wave_cfg.count or 5) then
                -- The last wave ends with the BOSS: spawned once via a big
                -- telegraph (which keeps manual_wave_done false until it dies).
                local map = self:active_map()
                local boss_arch = map.boss or self.config.boss_archetype
                if boss_arch and not self.boss_spawned then
                    self.boss_spawned = true
                    self:vacuum_pickups()
                    local title = map.boss_title or self.config.boss_title
                    self:set_flash(title and ("THE " .. title .. " RISES") or "A CHAMPION RISES")
                    Art.shake(0.5, 0.5)
                    self:add_telegraph(self:pick_spawn_point(), boss_arch, true)
                    self:log("boss telegraphed arch=" .. tostring(boss_arch))
                else
                    self:vacuum_pickups()
                    self.state = "hero_win"
                    -- Clearing a map unlocks the next rank (persisted below).
                    local unlocked
                    if #self.maps > 0 and self.map_index > (self.maps_cleared or 0) then
                        self.maps_cleared = self.map_index
                        unlocked = self.maps[self.map_index + 1]
                    end
                    self:save_profile()
                    self:set_flash(unlocked and (tostring(unlocked.name) .. " UNLOCKED") or "RUN CLEARED")
                    self:log(string.format("RUN CLEARED map=%d waves=%d kills=%d gold=%d",
                        self.map_index or 1, self.wave_index or 1, self.kills, self.gold or 0))
                end
            else
                self:begin_pause()
            end
        elseif (not self.manual_hero) and self.state == "combat" and self.reserve < 1.0 and self:count_alive() == 0 then
            self.state = "hero_win"
            self:set_flash("HERO PREVAILS")
            self:log(string.format("HERO PREVAILS round=%d kills=%d", self.round, self.kills))
        elseif self.state == "combat" and self.round_t <= 0.0 then
            if not self.manual_hero then self:begin_pause() end
        end
    elseif self.state == "pause" or self.state == "town" or self.state == "worldmap"
        or self.state == "classpick" or self.state == "draft" then
        -- Sim frozen; UI + camera keep running.
    else
        self:update_hero(sim_dt)
        self:update_creeps(sim_dt)
        self:update_pickups(sim_dt)
    end
    self:update_damage_numbers(dt)
    self:update_dying(dt)

    self.flash_t = math.max((self.flash_t or 0.0) - dt, 0.0)
    if self.flash and self.flash ~= self.last_flash then
        self.flash_t = 2.0
        self.last_flash = self.flash
    end
    -- Clear last_flash too, or a REPEATED message (second "Bag full!", two
    -- identical "Found X" in a row) never re-displays after the first fades.
    if self.flash_t <= 0.0 then
        self.flash = ""
        self.last_flash = nil
    end

    self:update_hud()
end

-- ---------------------------------------------------------------------------
-- Lifecycle (driven by the shell)
-- ---------------------------------------------------------------------------

function Duel:start()
    -- Wipe the transient HUD first: if the previous run's teardown threw
    -- mid-stop (it's pcall'd on the death/scene reload), its retained quads —
    -- ground item icons, damage numbers — survive as untouchable GHOSTS
    -- scattered over the new run's field.
    if runtime_ui and runtime_ui.clear then runtime_ui.clear(self.hud) end
    Creep.archetypes = self.config.archetypes or Creep.archetypes
    Creep.default_archetype = self:role_archetype("swarm")
    Creep.aliases = {}

    local seed = ATH_COMMON.getenv_number("ATH_DUEL_SEED", nil)
    if seed then math.randomseed(math.floor(seed)) end

    self.groups = {}
    self.root = Art.group((self.config.id or "duel") .. "_Root", nil)
    self.groups.world = Art.group("Duel_World", self.root)
    self.groups.actors = Art.group("Duel_Actors", self.root)

    if runtime_ui then
        if runtime_ui.set_title then runtime_ui.set_title(self.hud, (self.config.name or "Duel") .. " HUD") end
        if runtime_ui.set_screen_overlay then runtime_ui.set_screen_overlay(self.hud, true) end
        if runtime_ui.show then runtime_ui.show(self.hud) end
    end

    Art.setup_stage({ ibl_enabled = not (self.config and self.config.no_ibl) })
    self:build_arena()
    Art.setup_iso_camera({ x = self.arena.w * 0.5 - 0.5, z = self.arena.h * 0.5 - 0.5 },
        { ortho_size = self.arena.ortho_size, offset = self.arena.cam_offset })
    self:reset_run()
    if self.config.hooks and self.config.hooks.on_start then self.config.hooks.on_start(self) end
    self.mode_started = true
    self:warm_creep_pool()
    self:log(string.format("start side=%s arena=%dx%d", self.side, self.arena.w, self.arena.h))
end

function Duel:stop()
    if self.manual_hero then self:save_profile() end
    -- Clear the HUD before touching scene handles: teardown below can throw on
    -- a scene reload, and anything after the throw is silently skipped (pcall).
    if runtime_ui and runtime_ui.clear then runtime_ui.clear(self.hud) end
    for _, c in ipairs(self.creeps or {}) do Creep.destroy(c) end
    self.creeps = {}
    self:flush_dying()
    Creep.clear_pool()
    if Art.valid(self.root) then scene.delete_node(self.root) end
    -- The pooled-node tables point into the scene group just deleted; drop them so
    -- a fresh start rebuilds the pools instead of reusing stale handles.
    self.telegraphs = nil
    self.tele_pool = nil
    self.cproj = nil
    self.hproj = nil
    self.coins = nil
    self.beacons = nil
    self.dmgnums = nil
    self.boss_creep = nil
end

return Duel
