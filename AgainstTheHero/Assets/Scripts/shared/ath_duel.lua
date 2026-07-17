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
local Visuals = ATH_COMMON.visuals(_ENV)
local V = Visuals.data
local Cards = ATH_COMMON.load_script("Scripts/shared/ath_cards.lua", "shared cards", _ENV)
local Flow = ATH_COMMON.load_script("Scripts/shared/duel_flow.lua", "duel flow", _ENV)
local Creep = ATH_COMMON.load_script("Scripts/shared/duel_creep.lua", "duel creep", _ENV)
local Console = ATH_COMMON.load_script("Scripts/shared/ath_console.lua", "dev console", _ENV)
local Inventory = ATH_COMMON.load_script("Scripts/shared/ath_inventory.lua", "inventory", _ENV)

local function T(key, ...)
    local I18n = _G.ATH_I18N
    if I18n and I18n.t then return I18n.t(key, ...) end
    if select("#", ...) > 0 then return string.format(key, ...) end
    return key
end
local Profile = ATH_COMMON.load_script("Scripts/shared/ath_profile.lua", "persistent profile", _ENV)
local Balance = ATH_COMMON.load_script("Scripts/shared/ath_balance.lua", "balance database", _ENV)
local Anim = ATH_COMMON.load_script("Scripts/shared/ath_sprite_anim.lua", "sprite anim", _ENV)
local BossSkills = ATH_COMMON.load_script("Scripts/shared/ath_boss_skills.lua", "boss skills", _ENV)

-- Dev-only diagnostic logging ([DMG]/[CAMDIAG]); silent unless ATH_DEV=1 at launch.
local ATH_DEV = ATH_COMMON.env_enabled and ATH_COMMON.env_enabled("ATH_DEV", false) or false

local Duel = {}
Duel.__index = Duel
local RULES = Balance.rules

local SLOWMO_SCALE = 0.4
local SLOWMO_DURATION = 1.2
local WHIRL_CD = RULES.whirl.cooldown
local WHIRL_RADIUS_BASE = RULES.whirl.radius

-- Feel constants (juice pass). Hit flash is a brief emissive whiteout; knockback
-- is a small decaying shove on the struck actor; telegraphs are the pre-spawn
-- ground markers that warn where the swarm is about to pour in.
local HIT_FLASH_T = 0.16          -- seconds a struck sprite stays flashed white
local CREEP_KNOCK_MELEE = RULES.knockback.creep_melee
local CREEP_KNOCK_BOLT = RULES.knockback.creep_projectile
local HERO_KNOCK_CONTACT = RULES.knockback.hero_contact
local HERO_KNOCK_BOLT = RULES.knockback.hero_projectile
local CREEP_KNOCK_SHOCK = RULES.knockback.shockwave_death
local TELEGRAPH_T = 0.45          -- warn window before a normal creep materialises
local TELEGRAPH_T_BIG = 0.75      -- longer, scarier warn for elites/brutes
local TELEGRAPH_BIG_COST = 4      -- threat_cost at/above which a spawn reads as "big"
local CPROJ_POOL = 24             -- pooled creep projectile spheres (never deleted)

-- Kill-feel + loot constants (fun pass).
local CRIT_MULT = RULES.crit.damage_mult
local MELEE_FLUSH_T = 0.32        -- melee dt-damage aggregates into a popup this often
local DMGNUM_POOL = 128           -- five Mage layers across geared multi-shot volleys
local DMGNUM_LIFE = 0.7           -- seconds a number floats/fades
local DMGNUM_STEP = 1.0 / 30.0    -- UI text motion is smooth enough at 30 Hz
local COIN_POOL = 40              -- pooled gold coin nodes on the ground
local BEACON_POOL = 8             -- pooled item-drop beacons on the ground
local COIN_COLLECT_R = 1.1       -- world radius at which a magnetised coin banks
local BEACON_COLLECT_R = 1.8      -- walk-over pickup FLOOR; live hero.pickup_range wins when larger
local PICKUP_RANGE_BASE = 4.5     -- base coin-magnet / item-grab radius (Brotato-generous)
local HITSTOP_SCALE = 0.12        -- sim speed during a hitstop beat
local ELITE_HP_MULT = RULES.enemy.elite_hp_mult
local ELITE_DPS_MULT = RULES.enemy.elite_dps_mult

-- Normal-tier dodge (combat plan step 1). Kept as per-hero fields so the later
-- Light/Heavy load tiers only retune numbers, never reshape the state.
local DODGE_DIST = RULES.load.normal.distance
local DODGE_DUR = RULES.load.dash_duration
local DODGE_IFRAMES = RULES.load.normal.invulnerability
local DODGE_RECHARGE = RULES.load.normal.recharge
local FLASK_CHARGES = RULES.flask.charges
local FLASK_HEAL = RULES.flask.heal_fraction
local FLASK_IFRAMES = RULES.flask.invulnerability
local FLASK_DRINK_T = RULES.flask.drink_time
local FLASK_LOCK_T = RULES.flask.lock_time
local MINIONS = Balance.minions
local BOSS_ARMOR_MULT = RULES.boss.armored_damage_mult
local ARMOR_BREAK_T = RULES.boss.armor_break_seconds

-- Telegraph grammar (shared enemy language): a WHITE ramp-flash on the sprite =
-- an attack is winding up (0.4s), a RED tint/decal = the attack must be dodged,
-- a ground decal = area impact incoming. Melee contact damage is now discrete
-- BITES behind that white flash instead of silent per-frame contact dps.
local BITE_WINDUP = RULES.enemy.bite_windup
local BITE_COOLDOWN = RULES.enemy.bite_cooldown
local BITE_GRACE = RULES.enemy.bite_grace
local SHOT_WINDUP = RULES.enemy.shot_windup

-- Balance-smoke loadouts and draft cards live beside the other tuning data.
local GEARSETS = Balance.gearsets
local DRAFT_CARDS = Balance.draft_cards
local RARITY_COLOR = {
    common    = { 0.66, 0.70, 0.76, 1.0 },
    uncommon  = { 0.42, 0.84, 0.48, 1.0 },
    rare      = { 0.38, 0.64, 0.97, 1.0 },
    epic      = { 0.78, 0.48, 0.96, 1.0 },
    legendary = { 0.96, 0.74, 0.30, 1.0 },
    specialization = { 0.66, 0.48, 1.0, 1.0 },
    universal = { 0.30, 0.78, 0.92, 1.0 },
}
local STATUS_COLOR = {
    fire = { 1.00, 0.35, 0.04 },
    ice = { 0.28, 0.90, 1.00 },
    earth = { 0.88, 0.58, 0.16 },
    air = { 0.45, 0.55, 1.00 },
    poison = { 0.42, 0.92, 0.28 },
    bleed = { 0.95, 0.14, 0.20 },
    curse = { 0.72, 0.30, 0.95 },
    frost = { 0.28, 0.90, 1.00 },
    seed = { 0.54, 0.82, 0.40 },
    thorns = { 0.30, 0.72, 0.32 },
    shadow = { 0.48, 0.38, 0.88 },
    daze = { 0.92, 0.78, 0.30 },
    explosion = { 0.96, 0.58, 0.18 },
    shockwave = { 0.92, 0.42, 0.34 },
    vampirism = { 0.88, 0.18, 0.42 },
    revive = { 0.62, 0.95, 0.72 },
    frenzy = { 0.96, 0.55, 0.20 },
    pierce = { 0.96, 0.84, 0.36 },
    daggers = { 0.72, 0.30, 0.82 },
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
            texture  = V.actors.knight.cape,
            wave_speed   = 2.5,
            wave_phase   = 3.0,
            wave_amp_deg = 10.0,
        },
        parts = {
            body  = {
                kind = "quad", quad_width = 1.6, quad_height = 2.2,
                position = { 0.0, 1.1, 0.0 },
                color = { 1.0, 1.0, 1.0 }, emissive = 1.0, emissive_texture = true,
                texture = V.actors.knight.body,
            },
            sword = {
                kind = "quad", quad_width = 1.6, quad_height = 2.2,
                position = { 0.0, 1.1, 0.05 },
                color = { 1.0, 1.0, 1.0 }, emissive = 1.0, emissive_texture = true,
                texture = V.actors.knight.sword,
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
    D.balance = Balance
    D.ctx = ctx or {}
    D.shell = shell
    D.manual_hero = D.config.manual_hero == true
    D.side = D.manual_hero and "hero" or ((ctx and ctx.side == "horde") and "horde" or "hero")
    D.hud = "ath.duel.hud"
    D.theme = D.config.theme or {}
    D.key_down = {}
    D.creeps = {}
    D.seed_mines = {}
    D.spawn_queue = {}
    D.next_id = 0
    D.spawn_counter = 0
    D.realtime = 0.0
    D.fallback_dt = 1.0 / 120.0
    D.autoplay = ATH_COMMON.env_enabled("ATH_DUEL_AUTOPLAY", false)
    D.boss_tour = ATH_COMMON.env_enabled("ATH_DUEL_BOSS_TOUR", false)
    D.invulnerable = ATH_COMMON.env_enabled("ATH_DUEL_INVULNERABLE", false)
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
    D.specialization = ATH_COMMON.getenv("ATH_HERO_SPEC", nil)

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
    -- map unlocks the next, persisted in the profile as maps_cleared. Per-map
    -- next-wave (round to re-enter) lives in map_next_wave[map_index].
    D.maps = config.maps or {}
    D.maps_cleared = 0
    D.map_next_wave = {}
    D.skill_points = (Balance.tree_rules and Balance.tree_rules.starting_points) or 1
    Profile.load(D)
    if #D.maps > 0 then
        D.map_index = math.min((D.maps_cleared or 0) + 1, #D.maps)
    else
        D.map_index = 1
    end
    -- Live locale refresh: rebuild pause/HUD strings when language changes mid-run.
    if _G.ATH_I18N and _G.ATH_I18N.set_duel_refresh then
        _G.ATH_I18N.set_duel_refresh(function()
            if Inventory and Inventory.refresh then Inventory.refresh(D) end
        end)
    end
    return D
end

-- The active map definition ({} when the mode has no map ladder).
function Duel:active_map()
    return (self.maps and self.maps[self.map_index]) or {}
end

-- Rarity-weighted item roll. Weights come from the map def (deeper maps skew
-- rare/epic); min_rarity floors the pool.
local RARITY_RANK_W = { common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }
local RARITY_ORDER = { "common", "uncommon", "rare", "epic", "legendary" }

-- Boss loot rolls the map's drop odds shifted ONE rarity tier up (legendary
-- absorbs the spill), so every boss pays out a level above its map's enemies.
function Duel:boss_drop_weights()
    local base = self:active_map().drop_weights
        or { common = 60, uncommon = 30, rare = 9, epic = 1 }
    -- Explicit zeros: roll_drop_item treats a MISSING rarity key as weight 1,
    -- which would leak off-tier items back into the boss pool.
    local up = { common = 0, uncommon = 0, rare = 0, epic = 0, legendary = 0 }
    for i, rarity in ipairs(RARITY_ORDER) do
        local to = RARITY_ORDER[math.min(i + 1, #RARITY_ORDER)]
        up[to] = up[to] + (base[rarity] or 0)
    end
    return up
end

-- Clone a catalog item with numeric effect stats scaled (boss drops = +10%).
-- Delegates to Profile.scale_item so bag save/load stays in sync.
function Duel.scale_item_stats(item, scale)
    return Profile.scale_item(item, scale)
end

function Duel:roll_drop_item(items, min_rarity, weights)
    weights = weights or self:active_map().drop_weights
        or { common = 60, uncommon = 30, rare = 9, epic = 1 }
    local min_rank = RARITY_RANK_W[min_rarity or "common"] or 1
    -- Clamp the floor to the band's CEILING: early maps zero-out high tiers
    -- (whites only on I-II), so a boss's "rare" floor lowers to the best tier
    -- the band allows instead of rolling an out-of-band item.
    local best_rank = 1
    for r, w in pairs(weights) do
        local rk = RARITY_RANK_W[r] or 1
        if (w or 0) > 0 and rk > best_rank then best_rank = rk end
    end
    if min_rank > best_rank then min_rank = best_rank end
    local pool, total = {}, 0.0
    for _, it in ipairs(items) do
        local rank = RARITY_RANK_W[it.rarity or "common"] or 1
        local w = weights[it.rarity or "common"] or 1
        if rank >= min_rank and w > 0 then
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

-- Wave the player will enter next time they start this map (1-based).
function Duel:next_wave_for_map(map_i)
    map_i = math.floor(map_i or self.map_index or 1)
    local w = self.map_next_wave and self.map_next_wave[map_i]
    return math.max(1, math.floor(w or 1))
end

-- The boss fights in its OWN round after the budget waves: a map with a boss
-- runs wave_cfg.count swarm rounds, then round count+1 = the boss (zero trash
-- budget, telegraphed on round start).
function Duel:total_rounds()
    local count = (self.wave_cfg and self.wave_cfg.count) or 5
    local boss = self:active_map().boss or self.config.boss_archetype
    return count + (boss and 1 or 0)
end

-- Snapshot "round to enter" for the current map from live state, then persist.
-- Between waves → cleared wave + 1; mid-combat / death → retry this wave.
function Duel:remember_map_wave()
    if not self.manual_hero then return end
    local map_i = math.floor(self.map_index or 1)
    local next_w = self._between_wave and ((self.wave_index or 1) + 1) or (self.wave_index or 1)
    next_w = math.max(1, math.min(math.floor(next_w), self:total_rounds()))
    self.map_next_wave = self.map_next_wave or {}
    self.map_next_wave[map_i] = next_w
end

function Duel:store_price(item)
    -- Priced against measured pilot income: a full map-I clear banks ~1.2k gold,
    -- map III ~4-6k — a run should buy one or two pieces, not the whole shelf.
    local prices = RULES.economy.store_prices
    return prices[(item and item.rarity) or "common"] or prices.common
end

function Duel:buy_store_offer(slot)
    if self.state ~= "town" then return false end
    local item = self.store_offers and self.store_offers[slot]
    if not item then return false end
    local price = self:store_price(item)
    if (self.gold or 0) < price then
        self:set_flash("Need %s more gold", tostring(price - (self.gold or 0)))
        return false
    end
    if not Inventory.add_item(self, item) then
        self:set_flash("Backpack full")
        return false
    end
    self.gold = self.gold - price
    self:save_profile()
    self:haptic(12)
    self:set_flash("Bought %s", (_G.ATH_I18N and _G.ATH_I18N.t(tostring(item.name or item.id))) or tostring(item.name or item.id))
    self:log(string.format("store buy item=%s price=%d gold=%d", tostring(item.id), price, self.gold))
    return true
end

function Duel:key_pressed(name)
    if not input or not input.is_key_down then return false end
    local down = input.is_key_down(name) == true
    -- Cheat console owns the keyboard: swallow presses but keep edge state warm
    -- so closing the console doesn't dump a burst of buffered key-ups/downs.
    if self.console and self.console.visible then
        self.key_down[name] = down
        return false
    end
    local pressed = down and not self.key_down[name]
    self.key_down[name] = down
    return pressed
end

function Duel:is_key_down(name)
    if self.console and self.console.visible then return false end
    return input and input.is_key_down and input.is_key_down(name) == true
end

function Duel:set_flash(text, ...)
    local I18n = _G.ATH_I18N
    if I18n and I18n.t and text then
        text = I18n.t(text, ...)
    elseif text and select("#", ...) > 0 then
        text = string.format(text, ...)
    end
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

function Duel:deal_status_damage(c, amount, color, number_offset, pure)
    if not c or (amount or 0.0) <= 0.0 then return false, 0.0 end
    if not c.alive then
        self:spawn_damage_number(c.x, c.z, amount, false,
            { color = color, jx = number_offset, scale = 1.15 })
        return false, 0.0
    end
    local killed, _, dealt = self:hit_creep(c, amount, nil, nil,
        { no_flask_refill = true, armor_applied = pure == true })
    self:spawn_damage_number(c.x, c.z, dealt, false,
        { color = color, jx = number_offset, scale = 1.15 })
    return killed, dealt
end

-- Summon gate only: caps the skeleton pack, other riders still apply.
function Duel:can_apply_summon(c, spec, rank)
    local cap = math.min(MINIONS.skeleton.cap_max,
        (spec.cap_base or 2) + (math.max(1, rank or 1) - 1) * (spec.cap_per_rank or 1))
    if (c and c.revive_cap or 0) > 0 then return false end
    local pending = 0
    for _, other in ipairs(self.creeps or {}) do
        if other.alive and (other.revive_cap or 0) > 0 then pending = pending + 1 end
    end
    return self:count_minions("skeleton") + pending < cap
end

-- Tree-era variant: the cap comes precomputed from the spec tree.
function Duel:can_apply_summon_fx(c, fx)
    local cap = math.min(MINIONS.skeleton.cap_max, fx.cap or 2)
    if (c and c.revive_cap or 0) > 0 then return false end
    local pending = 0
    for _, other in ipairs(self.creeps or {}) do
        if other.alive and (other.revive_cap or 0) > 0 then pending = pending + 1 end
    end
    return self:count_minions("skeleton") + pending < cap
end

-- Hero-sourced damage amplifiers vs a creep: Symbols of Death window, Skewer,
-- Brittle, and the status_amp capstones (Shatter / Kingsbane / Bramble Ward).
-- Runs inside hit_creep, so it covers direct hits AND rider/status damage.
function Duel:hero_damage_amp(c)
    local hero = self.hero
    if not hero or not c or not hero.spec_fx then return 1.0 end
    local amp = 1.0
    if (hero.symbols_t or 0.0) > 0.0 then amp = amp + 0.15 end
    if (c.skewer_t or 0.0) > 0.0 then amp = amp + (c.skewer_amp or 0.08) end
    local class = self:active_class()
    for _, spec in ipairs(class and class.specializations or {}) do
        local fx = hero.spec_fx[spec.id]
        if fx and (fx.points or 0) > 0 then
            if fx.brittle and (c.spell_slow_t or 0.0) > 0.0 then
                amp = amp + (fx.brittle.amp or 0.08)
            end
            local cap = fx.capstone
            if cap and cap.kind == "status_amp" then
                local p = cap.params
                local has
                if p.at_max_stacks then
                    has = ((c.on_hit_stacks or {})[spec.status] or 0)
                        >= (fx.max_stacks or spec.max_stacks or 5)
                elseif spec.kind == "frost" then
                    has = (c.spell_slow_t or 0.0) > 0.0
                else
                    has = ((c.on_hit_statuses or {})[spec.status] or 0.0) > 0.0
                end
                if has and p.elites_only and not (c.elite or c.boss or self.boss_creep == c) then
                    has = false
                end
                if has then amp = amp + (p.amp or 0.15) end
            end
        end
    end
    return amp
end

-- Transient move-speed bonuses (frenzy stacks, Fleet Shadow).
function Duel:hero_move_bonus(hero)
    local bonus = 0.0
    if (hero.frenzy_t or 0.0) > 0.0 then bonus = bonus + (hero.frenzy_move or 0.0) end
    if (hero.fleet_t or 0.0) > 0.0 then bonus = bonus + 0.05 end
    return bonus
end

-- Periodic capstones: Combustion / Malefic Rapture detonations and the
-- Symbols of Death window. Runs once per combat tick.
function Duel:update_tree_effects(dt)
    local hero = self.hero
    if not (self.manual_hero and hero and not hero.dead) then return end
    local class = self:active_class()
    if not class then return end
    for _, spec in ipairs(class.specializations or {}) do
        local fx = (hero.spec_fx or {})[spec.id]
        local cap = fx and fx.capstone
        if cap and cap.kind == "detonate" then
            hero.det_t = hero.det_t or {}
            local t = (hero.det_t[spec.id] or cap.params.period or 10.0) - dt
            if t <= 0.0 then
                t = cap.params.period or 10.0
                local many = (cap.params.targets or 1) > 1
                local best, best_left
                for _, c in ipairs(self.creeps or {}) do
                    local dot = c.alive and c.on_hit_dots and c.on_hit_dots[spec.status]
                    if dot then
                        local left = dot.damage * math.max(0.0, dot.t)
                            / (dot.tick_interval or Balance.on_hit.tick)
                        if many then
                            self:deal_status_damage(c, left * (cap.params.pct or 0.3),
                                STATUS_COLOR[spec.status] or STATUS_COLOR.curse, 0.3)
                        elseif not best or left > best_left then
                            best, best_left = c, left
                        end
                    end
                end
                if not many and best then
                    self:deal_status_damage(best, best_left * (cap.params.pct or 1.0),
                        STATUS_COLOR[spec.status] or STATUS_COLOR.fire, 0.3)
                end
            end
            hero.det_t[spec.id] = t
        elseif cap and cap.kind == "aura_buff" then
            hero.aura_icd = math.max(0.0, (hero.aura_icd or 0.0) - dt)
            if hero.aura_icd <= 0.0 and (hero.symbols_t or 0.0) <= 0.0 then
                local n, need = 0, cap.params.min_statused or 3
                for _, c in ipairs(self.creeps or {}) do
                    if c.alive and (c.smoke_t or 0.0) > 0.0 then
                        n = n + 1
                        if n >= need then break end
                    end
                end
                if n >= need then
                    hero.symbols_t = cap.params.dur or 4.0
                    hero.aura_icd = cap.params.icd or 8.0
                end
            end
        end
    end
end

-- Rider healing with an optional per-second budget (technique caps) and
-- optional overheal-to-shield (Sanguine Ward). The budget window resets in
-- update_hero once per second.
function Duel:hero_rider_heal(amount, cap_frac, shield_cap)
    local hero = self.hero
    if not hero or (amount or 0.0) <= 0.0 then return end
    if cap_frac then
        local budget = hero.hp_max * cap_frac - (hero.capped_heal_used or 0.0)
        amount = math.min(amount, math.max(0.0, budget))
        hero.capped_heal_used = (hero.capped_heal_used or 0.0) + amount
        if amount <= 0.0 then return end
    end
    local missing = hero.hp_max - hero.hp
    hero.hp = math.min(hero.hp_max, hero.hp + amount)
    if shield_cap and amount > missing then
        hero.shield = math.min(hero.hp_max * shield_cap, (hero.shield or 0.0) + (amount - missing))
    end
end

function Duel:mark_status(c, status, duration)
    if not c then return end
    c.on_hit_statuses = c.on_hit_statuses or {}
    c.on_hit_statuses[status] = math.max(c.on_hit_statuses[status] or 0.0,
        duration or Balance.on_hit.duration)
    self:flash_creep_status(c, status)
    BossSkills.on_status(self, c, status)
end

function Duel:apply_on_hit_dot(c, status, initial, tick, spread, lifesteal_mult, opts)
    opts = opts or {}
    local color = STATUS_COLOR[status] or STATUS_COLOR.poison
    local _, dealt = self:deal_status_damage(c, initial, color, 0.0)
    if (lifesteal_mult or 0.0) > 0.0 and self.hero then
        self:hero_rider_heal(dealt * lifesteal_mult, opts.heal_cap, opts.shield_cap)
    end
    if not c.alive then return end
    c.on_hit_dots = c.on_hit_dots or {}
    local dot = c.on_hit_dots[status] or {}
    dot.damage = math.max(dot.damage or 0.0, tick)
    dot.t, dot.tick_t = Balance.on_hit.duration, Balance.on_hit.tick
    dot.tick_interval = opts.tick_interval
    dot.heal_cap, dot.shield_cap = opts.heal_cap, opts.shield_cap
    dot.spread, dot.lifesteal_mult = spread == true, lifesteal_mult or 0.0
    c.on_hit_dots[status] = dot
    self:mark_status(c, status, dot.t)
end

-- Capstone proc bookkeeping: counts qualifying applications per spec and
-- gates on the declared ICD (Hero Grid rule: procs are bounded and never
-- recurse into riders — deal_status_damage does not re-enter this function).
function Duel:capstone_count(spec_id, every, icd)
    local hero = self.hero
    hero.cap_counts = hero.cap_counts or {}
    hero.cap_icd = hero.cap_icd or {}
    local n = (hero.cap_counts[spec_id] or 0) + 1
    hero.cap_counts[spec_id] = n
    if n < (every or 5) then return false end
    if (self.combat_time or 0.0) < (hero.cap_icd[spec_id] or 0.0) then return false end
    hero.cap_counts[spec_id] = 0
    hero.cap_icd[spec_id] = (self.combat_time or 0.0) + (icd or 0.0)
    return true
end

-- Nearby-splash helper for proc capstones (target-capped by design).
function Duel:splash_creeps(x, z, radius, targets, damage, color, skip)
    local r2, hit = radius * radius, 0
    for _, c in ipairs(self.creeps or {}) do
        if c.alive and c ~= skip then
            local dx, dz = c.x - x, c.z - z
            if dx * dx + dz * dz <= r2 then
                self:deal_status_damage(c, damage, color, 0.0)
                hit = hit + 1
                if hit >= targets then break end
            end
        end
    end
end

function Duel:apply_on_hit_specializations(c, hit_damage, hit_dx, hit_dz)
    local hero, class = self.hero, self:active_class()
    if not hero or not class or not c then return false end
    local all_fx = hero.spec_fx or {}
    local piercing = false
    for _, spec in ipairs(class.specializations or {}) do
        local fx = all_fx[spec.id]
        if fx and (fx.points or 0) > 0 and spec.kind ~= "preservation" then
            if spec.kind == "summon" and not self:can_apply_summon_fx(c, fx) then
                -- skip capped summons; other riders still apply
            else
            local status = spec.status
            local spread_mult = spec.spread and Balance.on_hit.spread_damage_mult or 1.0
            local cap = fx.capstone
            -- Mutation target multipliers.
            local hd = hit_damage
            if fx.elite_mult and (c.elite or c.boss or self.boss_creep == c) then
                hd = hd * (fx.elite_mult.mult or 1.2)
            end
            if fx.assassin and c.hp >= c.hp_max * 0.95 then
                hd = hd * (fx.assassin.mult or 1.2)
            end
            hero.last_rider_hit = hit_damage
            -- Technique: enemies carrying this status hit the hero softer.
            if fx.status_dmg_down and c.alive then
                local pct = fx.status_dmg_down.pct or 0.08
                c.damage_down_t = math.max(c.damage_down_t or 0.0, fx.duration or Balance.on_hit.duration)
                c.damage_mult = math.min(c.damage_mult or 1.0, 1.0 - pct)
            end
            local heal_opts = nil
            if fx.rider_heal then
                heal_opts = { heal_mult = fx.rider_heal.mult or 0.05, heal_cap = fx.rider_heal.cap or 0.005 }
            end
            if spec.kind == "dot" then
                self:apply_on_hit_dot(c, status, hd * (fx.initial or 0.0) * spread_mult,
                    hd * (fx.tick or 0.0) * spread_mult, spec.spread,
                    heal_opts and heal_opts.heal_mult or nil,
                    heal_opts and { heal_cap = heal_opts.heal_cap } or nil)
                if cap and cap.kind == "proc_bonus"
                    and self:capstone_count(spec.id, cap.params.every, cap.params.icd) then
                    self:deal_status_damage(c, hit_damage * (cap.params.pct or 1.0),
                        STATUS_COLOR[status] or STATUS_COLOR.poison, 0.35)
                    if (cap.params.splash_targets or 0) > 0 then
                        self:splash_creeps(c.x, c.z, 3.0, cap.params.splash_targets,
                            hit_damage * (cap.params.splash_pct or 0.0),
                            STATUS_COLOR[status] or STATUS_COLOR.poison, c)
                    end
                end
            elseif spec.kind == "stack_dot" then
                c.on_hit_stacks = c.on_hit_stacks or {}
                local max_stacks = fx.max_stacks or spec.max_stacks or 5
                local add = 1
                if fx.double_stack_full and c.hp >= c.hp_max * 0.95 then add = 2 end
                local stacks = math.min(max_stacks, (c.on_hit_stacks[status] or 0) + add)
                c.on_hit_stacks[status] = stacks
                local amount = hd * stacks * (fx.stack_per or 0.20)
                local opts = nil
                if fx.fast_tick_max and stacks >= max_stacks then
                    opts = { tick_interval = fx.fast_tick_max.tick or 0.35 }
                end
                if heal_opts then
                    opts = opts or {}
                    opts.heal_cap = heal_opts.heal_cap
                end
                self:apply_on_hit_dot(c, status, amount, amount, false,
                    heal_opts and heal_opts.heal_mult or false, opts)
                -- Capstone: bursting a target that just reached full stacks.
                if cap and cap.kind == "max_stack_burst" and stacks >= max_stacks
                    and (self.combat_time or 0.0) >= (c._msb_until or 0.0) then
                    c._msb_until = (self.combat_time or 0.0) + (cap.params.per_target_icd or 4.0)
                    local _, dealt = self:deal_status_damage(c, hit_damage * (cap.params.pct or 1.0),
                        STATUS_COLOR[status] or STATUS_COLOR.bleed, 0.35)
                    if (cap.params.heal or 0.0) > 0.0 then
                        self:hero_rider_heal(dealt * cap.params.heal, 0.02)
                    end
                end
            elseif spec.kind == "frost" then
                self:deal_status_damage(c, hd * (fx.damage or 0.0), STATUS_COLOR.frost, 0.0)
                if c.alive then
                    c.spell_slow_t = fx.duration or 3.0
                    c.spell_slow_mult = math.max(0.25, 1.0 - (fx.slow or 0.0))
                    c.attack_slow_t = fx.duration or 3.0
                    c.attack_slow_mult = math.min(c.attack_slow_mult or 1.0, c.spell_slow_mult)
                    self:mark_status(c, status, fx.duration)
                end
            elseif spec.kind == "shadow" then
                self:deal_status_damage(c, hd * (fx.damage or 0.0), STATUS_COLOR.shadow, 0.0, true)
                if c.alive then
                    c.smoke_t = fx.duration or 3.0
                    c.smoke_miss = math.min(0.75, fx.miss or 0.0)
                    self:mark_status(c, status, fx.duration)
                end
                if fx.fleet then hero.fleet_t = fx.duration or 3.0 end
            elseif spec.kind == "vampirism" then
                local ls = fx.lifesteal_mult or 0.5
                if cap and cap.kind == "low_hp_boost"
                    and hero.hp < hero.hp_max * (cap.params.threshold or 0.4) then
                    ls = ls * (cap.params.mult or 2.0)
                end
                self:apply_on_hit_dot(c, status, hd * (fx.initial or 0.0),
                    hd * (fx.tick or 0.0), false, ls,
                    fx.overheal_shield and { shield_cap = fx.overheal_shield.cap or 0.10 } or nil)
            elseif spec.kind == "frenzy" then
                local max_stacks = fx.max_stacks or 5
                hero.frenzy_stacks = math.min(max_stacks, (hero.frenzy_stacks or 0) + 1)
                hero.frenzy_dmg = hero.frenzy_stacks * (fx.dmg_per_stack or 0.01)
                hero.frenzy_as = hero.frenzy_stacks * (fx.as_per_stack or 0.01)
                hero.frenzy_move = hero.frenzy_stacks * (fx.move_per_stack or 0.01)
                hero.frenzy_t = fx.duration or 3.0
                hero.frenzy_fx = fx
                self:mark_status(c, status, 0.22)
                if cap and cap.kind == "proc_bonus"
                    and self:capstone_count(spec.id, cap.params.every, cap.params.icd) then
                    self:deal_status_damage(c, hit_damage * (cap.params.pct or 0.6),
                        STATUS_COLOR[status] or STATUS_COLOR.bleed, 0.35)
                    self:splash_creeps(c.x, c.z, 3.0, cap.params.splash_targets or 3,
                        hit_damage * (cap.params.splash_pct or 0.3),
                        STATUS_COLOR[status] or STATUS_COLOR.bleed, c)
                end
            elseif spec.kind == "daze" then
                local reduction = fx.reduction or 0.0
                if cap and cap.kind == "debuff_amp" then
                    reduction = reduction + (cap.params.extra or 0.10)
                end
                reduction = math.min(0.75, reduction)
                c.daze_t, c.daze_mult = fx.duration or 3.0, 1.0 - reduction
                c.spell_slow_t, c.spell_slow_mult = c.daze_t,
                    math.min(c.spell_slow_mult or 1.0, c.daze_mult)
                c.attack_slow_t, c.attack_slow_mult = c.daze_t,
                    math.min(c.attack_slow_mult or 1.0, c.daze_mult)
                c.damage_down_t, c.damage_mult = c.daze_t,
                    math.min(c.damage_mult or 1.0, c.daze_mult)
                self:mark_status(c, status, c.daze_t)
            elseif spec.kind == "explosion" or spec.kind == "shockwave" then
                c.on_hit_death = c.on_hit_death or {}
                local entry = {
                    damage = hd * (fx.damage or 0.0),
                    radius = fx.radius or spec.radius or 3.0,
                    dx = hit_dx or 0.0, dz = hit_dz or 0.0,
                }
                if fx.stun_wave then entry.daze = fx.stun_wave end
                if cap and cap.kind == "chain_death" then
                    entry.chain_mult = cap.params.mult or 0.5
                end
                c.on_hit_death[spec.kind] = entry
                self:mark_status(c, status, Balance.on_hit.duration)
            elseif spec.kind == "summon" then
                c.revive_cap = math.min(MINIONS.skeleton.cap_max, fx.cap or 2)
                self:mark_status(c, status, Balance.on_hit.duration)
            elseif spec.kind == "pierce" then
                local coeff = fx.damage or 0.60
                if cap and cap.kind == "full_pierce"
                    and self:capstone_count(spec.id, cap.params.every, 0.0) then
                    coeff = 1.0
                end
                self:deal_status_damage(c, hd * coeff,
                    STATUS_COLOR[status] or STATUS_COLOR.earth, 0.0)
                if cap and cap.kind == "proc_bonus"
                    and self:capstone_count(spec.id, cap.params.every, cap.params.icd) then
                    self:deal_status_damage(c, hit_damage * (cap.params.pct or 0.4),
                        STATUS_COLOR[status] or STATUS_COLOR.earth, 0.35)
                    self:splash_creeps(c.x, c.z, 3.0, cap.params.splash_targets or 3,
                        hit_damage * (cap.params.splash_pct or 0.4),
                        STATUS_COLOR[status] or STATUS_COLOR.earth, c)
                end
                if fx.skewer and c.alive then
                    c.skewer_t = fx.skewer.dur or 3.0
                    c.skewer_amp = fx.skewer.amp or 0.08
                end
                if fx.cripple and c.alive then
                    c.spell_slow_t = math.max(c.spell_slow_t or 0.0, fx.cripple.dur or 2.0)
                    c.spell_slow_mult = math.min(c.spell_slow_mult or 1.0, 1.0 - (fx.cripple.slow or 0.15))
                end
                piercing = true
            elseif spec.kind == "shard_cone" then
                -- Spray continues past the target (same direction as the bolt).
                self:spawn_earth_shards(c.x, c.z, hit_dx or 0.0, hit_dz or 0.0, hd, fx, spec, c.id)
                if cap and cap.kind == "shard_nova"
                    and self:capstone_count(spec.id, cap.params.every, 0.0) then
                    -- Full-circle sundering: three extra rotated sprays.
                    local bx, bz = hit_dx or 0.0, hit_dz or 1.0
                    self:spawn_earth_shards(c.x, c.z, bz, -bx, hd, fx, spec, c.id)
                    self:spawn_earth_shards(c.x, c.z, -bx, -bz, hd, fx, spec, c.id)
                    self:spawn_earth_shards(c.x, c.z, -bz, bx, hd, fx, spec, c.id)
                end
                self:mark_status(c, status, 0.35)
            end
            end -- can_apply / not summon-capped
        end
    end
    return piercing
end

function Duel:apply_burn(c, effects)
    if not c or (effects.burn_dps or 0.0) <= 0.0 then return end
    local already_burning = (c.burn_t or 0.0) > 0.0
    c.burn_t = effects.burn_seconds
    if not already_burning then c.burn_tick_t = 0.5 end
    c.burn_fx_t = 0.12
    c.burn_dps = math.max(c.burn_dps or 0.0, effects.burn_dps)
    c.burn_data = {
        burn_dps = c.burn_dps, burn_seconds = effects.burn_seconds,
        burn_spread_radius = effects.burn_spread_radius,
        burn_spread_targets = effects.burn_spread_targets,
    }
end

function Duel:flash_creep_status(c, status)
    if not c then return end
    c.status_flash_name = type(status) == "string" and status or nil
    c.status_flash_names = type(status) == "table" and status or nil
    c.status_flash_t = 0.22
    c._status_tint_key = nil
    self:update_creep_status_tint(c)
end

function Duel:update_creep_status_tint(c)
    local active = {}
    if c.alive then
        if (c.burn_t or 0.0) > 0.0 then active[#active + 1] = "fire" end
        if (c.spell_slow_t or 0.0) > 0.0 then active[#active + 1] = "ice" end
        if (c.armor_debuff_t or 0.0) > 0.0 then active[#active + 1] = "earth" end
        if (c.storm_tint_t or 0.0) > 0.0 then active[#active + 1] = "air" end
        if (c.poison_t or 0.0) > 0.0 then active[#active + 1] = "poison" end
        if (c.bleed_t or 0.0) > 0.0 then active[#active + 1] = "bleed" end
        if (c.curse_t or 0.0) > 0.0 then active[#active + 1] = "curse" end
        for status, t in pairs(c.on_hit_statuses or {}) do
            if t > 0.0 then active[#active + 1] = status end
        end
        table.sort(active)
    end
    local flash = (c.status_flash_t or 0.0) > 0.0
    local statuses = active
    if flash then
        statuses = c.status_flash_names or (c.status_flash_name and { c.status_flash_name }) or active
    end
    local from, to, mix, blend_key = 1, 1, 0.0, ""
    if #statuses > 1 then
        local phase = ((self.realtime or 0.0) * 2.0) % #statuses
        from, mix = math.floor(phase) + 1, phase % 1.0
        to = from % #statuses + 1
        blend_key = ":" .. from .. ":" .. math.floor(mix * 12.0)
    end
    local key = #statuses > 0 and table.concat(statuses, "+") .. blend_key
        .. (flash and "_flash" or "") or nil
    if not key and not c._status_tint_key then return end
    if key == c._status_tint_key then return end
    local s = c.stats or {}
    local color = s.color or { 1.0, 1.0, 1.0 }
    if #statuses > 0 then
        local a, b = STATUS_COLOR[statuses[from]], STATUS_COLOR[statuses[to]]
        color = { a[1] + (b[1] - a[1]) * mix, a[2] + (b[2] - a[2]) * mix,
            a[3] + (b[3] - a[3]) * mix }
    end
    local defaults = { body = s.color or color, head = s.head or s.color or color,
        weapon = s.weapon or { 0.52, 0.52, 0.52 } }
    for name, base in pairs(defaults) do
        local node = c.parts and c.parts[name]
        if Art.valid(node) then
            local col = #statuses > 0 and color or base
            local glow = flash and 3.5 or (#statuses > 0 and 1.8 or 0.85)
            material.set(node, "base_color", vec4(col[1], col[2], col[3], 1.0))
            material.set(node, "emissive", vec3(col[1] * glow, col[2] * glow, col[3] * glow))
        end
    end
    c._status_tint_name, c._status_tint_key = #statuses > 0 and table.concat(statuses, "+") or nil, key
    c._status_tint_color = #statuses > 0 and color or nil
end

function Duel:fire_hit_burst(x, z, tag)
    Art.burst("ath_fire_core_" .. tag, vec3(x, 0.62, z),
        { preset = "enemy_take", count = 8, life_min = 0.06, life_max = 0.18,
          spawn_radius = 0.12, noise_strength = 8.0, size_min = 0.08, size_max = 0.20,
          color_start = vec4(1.0, 0.94, 0.32, 1.0), color_end = vec4(1.0, 0.16, 0.01, 0.0) })
    Art.burst("ath_fire_embers_" .. tag, vec3(x, 0.46, z),
        { preset = "enemy_give", count = 16, life_min = 0.18, life_max = 0.52,
          spawn_radius = 0.30, noise_strength = 5.0, size_min = 0.05, size_max = 0.16,
          velocity = vec3(0.0, 4.2, 0.0), drag = 1.6,
          color_start = vec4(1.0, 0.56, 0.04, 1.0), color_end = vec4(0.72, 0.01, 0.0, 0.0) })
end

function Duel:ice_hit_burst(x, z, tag)
    Art.burst("ath_ice_core_" .. tag, vec3(x, 0.68, z),
        { preset = "hero_take", count = 8, life_min = 0.08, life_max = 0.20,
          spawn_radius = 0.10, noise_strength = 3.0, size_min = 0.06, size_max = 0.16,
          color_start = vec4(1.0, 1.0, 1.0, 1.0), color_end = vec4(0.08, 0.62, 1.0, 0.0) })
    for i = 1, 6 do
        local a = i * 1.0472
        Art.burst("ath_ice_shard_" .. tag .. "_" .. i, vec3(x, 0.62, z),
            { preset = "hero_take", count = 2, life_min = 0.12, life_max = 0.28,
              spawn_radius = 0.04, noise_strength = 0.7, size_min = 0.04, size_max = 0.10,
              velocity = vec3(math.sin(a) * 5.2, 1.2, math.cos(a) * 5.2), orientation = "velocity",
              color_start = vec4(0.86, 1.0, 1.0, 1.0), color_end = vec4(0.04, 0.38, 1.0, 0.0) })
    end
end

function Duel:earth_hit_burst(x, z, tag)
    Art.burst("ath_earth_core_" .. tag, vec3(x, 0.18, z),
        { preset = "enemy_take", count = 8, life_min = 0.16, life_max = 0.38,
          spawn_radius = 0.26, noise_strength = 2.0, size_min = 0.12, size_max = 0.28,
          velocity = vec3(0.0, 3.0, 0.0), gravity = vec3(0.0, -8.0, 0.0),
          color_start = vec4(0.92, 0.60, 0.18, 1.0), color_end = vec4(0.20, 0.07, 0.01, 0.0) })
    for i = 1, 6 do
        local a = i * 1.0472
        Art.burst("ath_earth_chunk_" .. tag .. "_" .. i, vec3(x, 0.14, z),
            { preset = "enemy_take", count = 2, life_min = 0.14, life_max = 0.32,
              spawn_radius = 0.05, noise_strength = 0.8, size_min = 0.10, size_max = 0.20,
              velocity = vec3(math.sin(a) * 4.0, 1.5, math.cos(a) * 4.0),
              gravity = vec3(0.0, -7.0, 0.0), orientation = "velocity",
              color_start = vec4(0.72, 0.42, 0.12, 1.0), color_end = vec4(0.16, 0.05, 0.01, 0.0) })
    end
end

-- Geomancer rock fragments: tight cone continuing past the bolt hit.
local ESHARD_POOL = 48
local ESHARD_HIT_R = 0.95

function Duel:ensure_earth_shards()
    if self.eshards then return end
    if not (self.groups and self.groups.actors) then return end
    self.eshards = {}
    local rock = { 0.42, 0.36, 0.28, 1.0 }
    for i = 1, ESHARD_POOL do
        local node = Art.cube("EarthShard_" .. i, vec3(-1000.0, -1000.0, -1000.0),
            vec3(0.0001, 0.0001, 0.0001), rock, self.groups.actors, 0.15)
        self.eshards[i] = { node = node, active = false }
    end
end

function Duel:eshard_hide(p)
    p.active = false
    p.hit_ids = nil
    p.trail_t = nil
    p.vy, p.y, p.grav = nil, nil, nil
    if Art.valid(p.node) then
        p.node:set_position(vec3(-1000.0, -1000.0, -1000.0))
        p.node:set_scale(vec3(0.0001, 0.0001, 0.0001))
    end
end

function Duel:reset_earth_shards()
    if not self.eshards then return end
    for _, p in ipairs(self.eshards) do self:eshard_hide(p) end
end

function Duel:rock_shard_burst(x, z, vx, vz, tag)
    local d = math.sqrt(vx * vx + vz * vz)
    local nx, nz = (d > 0.001) and vx / d or 0.0, (d > 0.001) and vz / d or 1.0
    Art.burst("ath_rock_dust_" .. tag, vec3(x, 0.35, z),
        { preset = "enemy_take", count = 12, life_min = 0.10, life_max = 0.30,
          spawn_radius = 0.22, noise_strength = 2.2, size_min = 0.04, size_max = 0.11,
          velocity = vec3(nx * 0.8, 2.8, nz * 0.8), gravity = vec3(0.0, -8.0, 0.0),
          color_start = vec4(0.55, 0.48, 0.38, 0.95), color_end = vec4(0.22, 0.18, 0.12, 0.0) })
    for i = 1, 7 do
        local ja = (math.random() - 0.5) * 1.4
        local jx = nx * math.cos(ja) - nz * math.sin(ja)
        local jz = nx * math.sin(ja) + nz * math.cos(ja)
        local spd = 3.2 + math.random() * 4.5
        Art.burst("ath_rock_chip_" .. tag .. "_" .. i, vec3(x + (math.random() - 0.5) * 0.25, 0.4 + math.random() * 0.25, z + (math.random() - 0.5) * 0.25),
            { preset = "hero_take", count = 1, life_min = 0.14, life_max = 0.38,
              spawn_radius = 0.03, noise_strength = 0.6,
              size_min = 0.06 + math.random() * 0.06, size_max = 0.12 + math.random() * 0.10,
              velocity = vec3(jx * spd, 1.2 + math.random() * 2.8, jz * spd),
              gravity = vec3(0.0, -10.0 - math.random() * 4.0, 0.0), orientation = "velocity", drag = 0.6 + math.random() * 0.5,
              color_start = vec4(0.40 + math.random() * 0.18, 0.34 + math.random() * 0.12, 0.24 + math.random() * 0.10, 1.0),
              color_end = vec4(0.16, 0.12, 0.08, 0.0) })
    end
end

function Duel:spawn_earth_shards(x, z, bx, bz, hit_damage, fx, spec, skip_id)
    self:ensure_earth_shards()
    if not self.eshards then return end
    local d = math.sqrt((bx or 0.0) * (bx or 0.0) + (bz or 0.0) * (bz or 0.0))
    if d < 0.001 then bx, bz, d = 0.0, 1.0, 1.0 end
    bx, bz = bx / d, bz / d
    fx = fx or {}
    local count = math.max(3, math.floor(fx.shards or spec.shards_base or 4))
    -- A few extra random chips so each volley looks broken, not counted.
    count = count + math.floor(math.random() * 3.0)
    local half = math.rad((fx.cone_deg or spec.cone_deg or 18.0) * 0.5)
    local base_speed = fx.speed or spec.speed or 15.0
    local base_life = (fx.range or spec.range or 5.0) / math.max(1.0, base_speed)
    local dmg = hit_damage * (fx.damage or spec.damage or 0.40)
    local shard_slow = fx.shard_slow
    local base_yaw = math.atan(bx, bz)
    local tag = tostring(math.floor((self.realtime or 0.0) * 1000.0) + math.floor(math.random() * 97.0))
    local ox, oz = x + bx * (0.35 + math.random() * 0.25), z + bz * (0.35 + math.random() * 0.25)
    self:rock_shard_burst(ox, oz, bx * base_speed, bz * base_speed, "spawn_" .. tag)
    local tones = {
        { 0.46, 0.40, 0.32 }, { 0.38, 0.34, 0.28 }, { 0.52, 0.44, 0.34 },
        { 0.34, 0.30, 0.24 }, { 0.44, 0.36, 0.26 }, { 0.50, 0.42, 0.30 },
        { 0.30, 0.28, 0.22 },
    }
    for i = 1, count do
        local slot
        for _, p in ipairs(self.eshards) do
            if not p.active then slot = p; break end
        end
        if not slot then break end
        -- Random angle inside the cone (not evenly spaced).
        local ang = base_yaw + (math.random() * 2.0 - 1.0) * half
        -- Occasional wider outlier so the spray looks broken.
        if math.random() < 0.22 then
            ang = base_yaw + (math.random() * 2.0 - 1.0) * half * (1.35 + math.random() * 0.4)
        end
        local spd = base_speed * (0.72 + math.random() * 0.55)
        local vx, vz = math.sin(ang) * spd, math.cos(ang) * spd
        local jx = (math.random() - 0.5) * 0.55
        local jz = (math.random() - 0.5) * 0.55
        slot.active = true
        slot.x, slot.z = ox + jx, oz + jz
        slot.vx, slot.vz = vx, vz
        slot.vy = 1.5 + math.random() * 4.5
        slot.grav = 14.0 + math.random() * 8.0
        slot.y = 0.45 + math.random() * 0.35
        slot.life = base_life * (0.65 + math.random() * 0.55)
        slot.damage = dmg
        slot.slow = shard_slow
        slot.hit_ids = skip_id and { [skip_id] = true } or {}
        slot.spin = (math.random() * 2.0 - 1.0) * (280.0 + math.random() * 520.0)
        slot.spin_p = (math.random() * 2.0 - 1.0) * (200.0 + math.random() * 360.0)
        slot.spin_r = (math.random() * 2.0 - 1.0) * (180.0 + math.random() * 300.0)
        slot.pitch = math.random() * 360.0
        slot.roll = math.random() * 360.0
        slot.yaw = math.deg(ang) + (math.random() - 0.5) * 50.0
        slot.trail_t = 0.02 + math.random() * 0.05
        -- Irregular splinter sizes (chunky vs needle).
        local fat = 0.08 + math.random() * 0.16
        local sx = fat * (0.6 + math.random() * 0.9)
        local sy = fat * (0.45 + math.random() * 0.8)
        local sz = fat * (1.4 + math.random() * 1.8)
        local tone = tones[math.floor(math.random() * #tones) + 1]
        local shade = 0.85 + math.random() * 0.3
        if Art.valid(slot.node) then
            material.set(slot.node, "base_color",
                vec4(tone[1] * shade, tone[2] * shade, tone[3] * shade, 1.0))
            material.set(slot.node, "emissive",
                vec3(tone[1] * 0.08, tone[2] * 0.07, tone[3] * 0.05))
            slot.node:set_scale(vec3(sx, sy, sz))
            slot.node:set_rotation(vec3(slot.pitch, slot.yaw, slot.roll))
            slot.node:set_position(vec3(slot.x, slot.y, slot.z))
        end
    end
end

function Duel:update_earth_shards(dt)
    if not self.eshards then return end
    local A = self.arena
    local trail_budget = 6
    for _, p in ipairs(self.eshards) do
        if p.active then
            p.vy = (p.vy or 0.0) - (p.grav or 16.0) * dt
            p.y = math.max(0.18, (p.y or 0.55) + (p.vy or 0.0) * dt)
            if p.y <= 0.19 and (p.vy or 0.0) < 0.0 then
                p.vy = -(p.vy or 0.0) * 0.35
                if math.abs(p.vy) < 0.8 then p.vy = 0.0 end
            end
            p.x = p.x + p.vx * dt
            p.z = p.z + p.vz * dt
            p.life = (p.life or 0.0) - dt
            p.yaw = (p.yaw or 0.0) + (p.spin or 0.0) * dt
            p.pitch = (p.pitch or 0.0) + (p.spin_p or p.spin or 0.0) * dt
            p.roll = (p.roll or 0.0) + (p.spin_r or 0.0) * dt
            for _, c in ipairs(self.creeps) do
                if c.alive and not (p.hit_ids and p.hit_ids[c.id]) then
                    local dx, dz = c.x - p.x, c.z - p.z
                    if dx * dx + dz * dz <= ESHARD_HIT_R * ESHARD_HIT_R then
                        p.hit_ids = p.hit_ids or {}
                        p.hit_ids[c.id] = true
                        local dd = math.sqrt(p.vx * p.vx + p.vz * p.vz)
                        local nx = (dd > 0.001) and p.vx / dd or 0.0
                        local nz = (dd > 0.001) and p.vz / dd or 0.0
                        self:hit_creep(c, p.damage, nx * 1.6, nz * 1.6, { discrete = true })
                        -- Grinding Dust technique: shards chill what they chip.
                        if p.slow and c.alive then
                            c.spell_slow_t = math.max(c.spell_slow_t or 0.0, p.slow.dur or 2.0)
                            c.spell_slow_mult = math.min(c.spell_slow_mult or 1.0,
                                1.0 - (p.slow.slow or 0.15))
                        end
                        Art.burst("ath_rock_hit_" .. tostring(c.id) .. "_" .. tostring(math.floor(math.random() * 1000)),
                            vec3(p.x, p.y or 0.5, p.z),
                            { preset = "enemy_take", count = 4 + math.floor(math.random() * 3),
                              life_min = 0.08, life_max = 0.22,
                              spawn_radius = 0.08 + math.random() * 0.08,
                              size_min = 0.04, size_max = 0.10 + math.random() * 0.05,
                              noise_strength = 1.2 + math.random(),
                              gravity = vec3(0.0, -9.0, 0.0), orientation = "velocity",
                              color_start = vec4(0.48 + math.random() * 0.1, 0.40, 0.30, 1.0),
                              color_end = vec4(0.16, 0.12, 0.08, 0.0) })
                    end
                end
            end
            local off = p.x < A.pad or p.x > A.w - A.pad or p.z < A.pad or p.z > A.h - A.pad
            if p.life <= 0.0 or off then
                self:eshard_hide(p)
            elseif Art.valid(p.node) then
                p.node:set_position(vec3(p.x, p.y or 0.55, p.z))
                p.node:set_rotation(vec3(p.pitch or 0.0, p.yaw or 0.0, p.roll or 0.0))
                p.trail_t = (p.trail_t or 0.0) - dt
                if p.trail_t <= 0.0 and trail_budget > 0 and math.random() < 0.55 then
                    trail_budget = trail_budget - 1
                    p.trail_t = 0.05 + math.random() * 0.06
                    Art.burst("ath_rock_trail", vec3(p.x, (p.y or 0.5) - 0.08, p.z),
                        { preset = "hero_take", count = 1, life_max = 0.12 + math.random() * 0.08,
                          spawn_radius = 0.02, size_min = 0.03, size_max = 0.06 + math.random() * 0.03,
                          noise_strength = 0.4, gravity = vec3(0.0, -5.0, 0.0),
                          color_start = vec4(0.40, 0.34, 0.26, 0.7),
                          color_end = vec4(0.14, 0.10, 0.08, 0.0) })
                end
            end
        end
    end
end

function Duel:storm_hit_burst(x, z, tag)
    Art.burst("ath_storm_core_" .. tag, vec3(x, 0.72, z),
        { preset = "enemy_take", count = 8, life_min = 0.04, life_max = 0.14,
          spawn_radius = 0.12, noise_strength = 15.0, size_min = 0.05, size_max = 0.14,
          color_start = vec4(1.0, 1.0, 1.0, 1.0), color_end = vec4(0.08, 0.32, 1.0, 0.0) })
    for i = 1, 4 do
        local a = i * 1.5708 + (self.realtime or 0.0) * 7.0
        Art.burst("ath_storm_spark_" .. tag .. "_" .. i, vec3(x, 0.70, z),
            { preset = "hero_take", count = 2, life_min = 0.07, life_max = 0.20,
              spawn_radius = 0.06, noise_strength = 2.0, size_min = 0.04, size_max = 0.10,
              velocity = vec3(math.sin(a) * 7.0, 2.0, math.cos(a) * 7.0), orientation = "velocity",
              color_start = vec4(1.0, 1.0, 1.0, 1.0), color_end = vec4(0.04, 0.28, 1.0, 0.0) })
    end
    for branch = 1, 3 do
        local a = branch * 2.0944 + (self.realtime or 0.0) * 3.0
        for step = 1, 2 do
            local reach = step * 0.34
            local fork = (step % 2 == 0 and 0.10 or -0.10)
            Art.burst("ath_storm_fork_" .. tag .. "_" .. branch .. "_" .. step,
                vec3(x + math.sin(a) * reach + math.cos(a) * fork, 0.72,
                    z + math.cos(a) * reach - math.sin(a) * fork),
                { preset = "enemy_take", count = 2, life_min = 0.06, life_max = 0.16,
                  spawn_radius = 0.02, noise_strength = 1.0, size_min = 0.04, size_max = 0.08,
                  color_start = vec4(1.0, 1.0, 1.0, 1.0),
                  color_end = vec4(0.06, 0.32, 1.0, 0.0) })
        end
    end
end

function Duel:mage_lightning_arc(x1, z1, x2, z2, tag)
    local dx, dz = x2 - x1, z2 - z1
    local d = math.max(0.001, math.sqrt(dx * dx + dz * dz))
    for step = 1, 7 do
        local t = step / 8.0
        local fork = (step % 2 == 0 and 1.0 or -1.0) * 0.18
        Art.burst("ath_lightning_arc_" .. tag .. "_" .. tostring(step),
            vec3(x1 + dx * t - dz / d * fork, 0.72, z1 + dz * t + dx / d * fork),
            { preset = "enemy_take", count = 2, life_min = 0.03, life_max = 0.10, spawn_radius = 0.025,
              noise_strength = 2.0, size_min = 0.04, size_max = 0.09,
              velocity = vec3(dx * 2.0, 0.0, dz * 2.0), orientation = "velocity",
              color_start = vec4(1.0, 1.0, 1.0, 1.0), color_end = vec4(0.05, 0.30, 1.0, 0.0) })
    end
end

function Duel:spread_burn(source)
    local burn = source and source.burn_data
    if not burn then return end
    local candidates, r2 = {}, burn.burn_spread_radius * burn.burn_spread_radius
    for _, c in ipairs(self.creeps) do
        if c.alive and c ~= source then
            local dx, dz = c.x - source.x, c.z - source.z
            local d2 = dx * dx + dz * dz
            if d2 <= r2 then candidates[#candidates + 1] = { creep = c, distance = d2 } end
        end
    end
    table.sort(candidates, function(a, b) return a.distance < b.distance end)
    for i = 1, math.min(burn.burn_spread_targets or 0, #candidates) do
        local c = candidates[i].creep
        self:apply_burn(c, burn)
        Art.burst("ath_burn_spread_" .. tostring(c.id), vec3(c.x, 0.55, c.z),
            { preset = "enemy_give", count = 8, life_max = 0.28, spawn_radius = 0.25,
              size_max = 0.16, color_start = vec4(1.0, 0.24, 0.04, 1.0) })
    end
end

function Duel:trigger_on_hit_death(source)
    if not source then return end
    local hero = self.hero
    local sfx = (hero and hero.spec_fx) or {}
    local smap = self._status_spec or {}
    for status, dot in pairs(source.on_hit_dots or {}) do
        local fx = smap[status] and sfx[smap[status]] or nil
        if dot.spread then
            -- Epidemic mutation: wider radius, two targets, terminal copies
            -- (default keeps the classic single re-spreadable jump).
            local radius, targets, copies_spread = Balance.on_hit.spread_radius, 1, true
            if fx and fx.spread_plus then
                radius = fx.spread_plus.radius or 5.5
                targets = fx.spread_plus.targets or 2
                copies_spread = false
            end
            local cands = {}
            for _, c in ipairs(self.creeps) do
                if c.alive and c ~= source then
                    local dx, dz = c.x - source.x, c.z - source.z
                    local d2 = dx * dx + dz * dz
                    if d2 <= radius * radius then cands[#cands + 1] = { c = c, d = d2 } end
                end
            end
            table.sort(cands, function(a, b) return a.d < b.d end)
            for i = 1, math.min(targets, #cands) do
                self:apply_on_hit_dot(cands[i].c, status, dot.damage, dot.damage,
                    copies_spread, dot.lifesteal_mult)
            end
        end
        -- Blooming Death: the seeded corpse bursts for half the full dot.
        local cap = fx and fx.capstone
        if cap and cap.kind == "death_burst" then
            local full = dot.damage * (Balance.on_hit.duration / Balance.on_hit.tick)
            self:splash_creeps(source.x, source.z, cap.params.radius or 2.5, 6,
                full * (cap.params.pct or 0.5), STATUS_COLOR[status] or STATUS_COLOR.poison, source)
        end
    end
    for kind, effect in pairs(source.on_hit_death or {}) do
        local r2 = effect.radius * effect.radius
        if kind == "shockwave" then
            -- The desc promises a launch: normalize the stored hit direction
            -- (chain re-blasts store raw offsets) and kick up a dust ring
            -- biased toward the push side so the wave reads on screen.
            local el = math.sqrt(effect.dx * effect.dx + effect.dz * effect.dz)
            if el > 0.001 then effect.dx, effect.dz = effect.dx / el, effect.dz / el end
            local col = STATUS_COLOR.shockwave
            Art.burst("ath_duel_shock_" .. tostring(source.id),
                vec3(source.x + effect.dx * effect.radius * 0.35, 0.16,
                    source.z + effect.dz * effect.radius * 0.35),
                { preset = "enemy_take", count = 20, life_max = 0.35,
                  spawn_radius = effect.radius * 0.55, size_max = 0.22,
                  noise_strength = 1.2, gravity = vec3(0.0, 0.8, 0.0),
                  color_start = vec4(col[1], col[2], col[3], 0.9) })
        end
        for _, c in ipairs(self.creeps) do
            if c.alive and c ~= source then
                local dx, dz = c.x - source.x, c.z - source.z
                local d2 = dx * dx + dz * dz
                local ahead = kind ~= "shockwave" or dx * effect.dx + dz * effect.dz > 0.0
                if d2 <= r2 and ahead then
                    local killed = self:deal_status_damage(c, effect.damage, STATUS_COLOR[kind], 0.0)
                    self:mark_status(c, kind, 0.22)
                    if kind == "shockwave" and c.alive then
                        local d = math.sqrt(d2)
                        Creep.knock(c,
                            (d > 0.001 and dx / d or effect.dx) * CREEP_KNOCK_SHOCK,
                            (d > 0.001 and dz / d or effect.dz) * CREEP_KNOCK_SHOCK)
                    end
                    if effect.daze and c.alive then
                        local mult = 1.0 - math.min(0.75, effect.daze.daze or 0.2)
                        local dur = effect.daze.dur or 2.0
                        c.spell_slow_t = math.max(c.spell_slow_t or 0.0, dur)
                        c.spell_slow_mult = math.min(c.spell_slow_mult or 1.0, mult)
                        c.attack_slow_t = math.max(c.attack_slow_t or 0.0, dur)
                        c.attack_slow_mult = math.min(c.attack_slow_mult or 1.0, mult)
                    end
                    -- Seismic Chain / Soul Shatter: blast kills re-blast once.
                    if killed and effect.chain_mult then
                        c.on_hit_death = c.on_hit_death or {}
                        c.on_hit_death[kind] = {
                            damage = effect.damage * effect.chain_mult,
                            radius = effect.radius, dx = dx, dz = dz,
                        }
                    end
                end
            end
        end
    end
    if source._hero_killed and (source.revive_cap or 0) > 0 then
        self:try_summon_minion("skeleton", source.revive_cap, source.x, source.z)
    end
    source.on_hit_death, source.revive_cap = nil, nil
end

function Duel:mage_chain_lightning(source, effects)
    if not source or effects.bounces <= 0 or effects.bounce_damage <= 0.0 then return end
    local seen, x, z = { [source.id] = true }, source.x, source.z
    for _ = 1, effects.bounces do
        local best, best_d
        for _, c in ipairs(self.creeps) do
            if c.alive and not seen[c.id] then
                local dx, dz = c.x - x, c.z - z
                local d2 = dx * dx + dz * dz
                if d2 <= effects.bounce_radius * effects.bounce_radius and (not best or d2 < best_d) then
                    best, best_d = c, d2
                end
            end
        end
        if not best then break end
        seen[best.id] = true
        local from_x, from_z = x, z
        x, z = best.x, best.z
        self:mage_lightning_arc(from_x, from_z, x, z, tostring(best.id))
        self:deal_status_damage(best, effects.bounce_damage, STATUS_COLOR.air, 1.4)
        if best.alive then best.storm_tint_t = 0.55 end
        self:flash_creep_status(best, "air")
        self:storm_hit_burst(best.x, best.z, "chain_" .. tostring(best.id))
    end
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
        crit_chance = (cls and cls.crit_chance) or RULES.crit.base_chance,
        pickup_range = PICKUP_RANGE_BASE, gold_find = 1.0,
        -- Empty armor slots start Light; recompute_hero_stats retunes this from
        -- equipped armor without changing the shared dodge machinery.
        dodge_charges = RULES.load.light.charges, dodge_charges_max = RULES.load.light.charges,
        dodge_recharge = RULES.load.light.recharge, dodge_recharge_t = 0.0,
        dodge_dist = RULES.load.light.distance, dodge_iframes = RULES.load.light.invulnerability,
        dodge_guard = 0.0, poise = 0.0, stagger_resist = 0.0,
        dodge_t = 0.0, dodge_iframe_t = 0.0, dodge_dx = 0.0, dodge_dz = 1.0,
        flask_charges = FLASK_CHARGES, flask_charges_max = FLASK_CHARGES,
        flask_health = FLASK_CHARGES,
        flask_drink_t = 0.0, flask_lock_t = 0.0,
        hp_regen_pct = 0.0,
        specialization_ranks = {},
        -- Transient per-frame multipliers a mode's mechanic may set in
        -- on_combat_tick to slow/shrink the hero WITHOUT corrupting card-stacked
        -- stats (ice slow, mud, sandstorm). Mode-owned: set every tick, 1.0 = off.
        move_mult = 1.0, range_mult = 1.0,
        boss_move_mult = 1.0, boss_damage_mult = 1.0,
        boss_dodge_recharge_mult = 1.0, boss_armor_bonus = 0.0,
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
            self._topdown_hero_sheet = nil
            -- Authored Hero Body ships with Spud chicken; dress before enable.
            -- Hero root starts disabled in game.pescene so the placeholder never
            -- paints between scene.load and this create.
            local dress = cls or self.config.hero
            if not Anim.setup_hero(hero, dress or {}) then
                local tex = (cls and cls.sprite_texture)
                    or (self.config.hero and self.config.hero.sprite_texture)
                local body = hero.parts.body
                if tex and Art.valid(body) and material then
                    material.set(body, "base_color", vec4(1.0, 1.0, 1.0, 1.0))
                    if material.set_texture then
                        material.set_texture(body, tex)
                        material.set_texture(body, "emissive", tex)
                    end
                    material.set(body, "emissive", vec3(1.0, 1.0, 1.0))
                    if material.set_render_type then material.set_render_type(body, "alpha_cut") end
                    if material.set_double_sided then material.set_double_sided(body, true) end
                end
            end
            if hero.root.set_enabled then hero.root:set_enabled(true) end
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
    local hs = (self.config.topdown and self.config.topdown.hero_scale) or 1.0
    hero.topdown_base_world_scale = base * cs
    hero.world_scale = hero.topdown_base_world_scale * hs
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
    speed = speed * (hero.move_mult or 1.0) * (hero.boss_move_mult or 1.0)
        * ((hero.flask_drink_t or 0.0) > 0.0 and RULES.flask.move_mult or 1.0)
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
    if (hero.flask_drink_t or 0.0) > 0.0 then
        hero.flask_drink_t = 0.0
        hero.flask_lock_t = FLASK_LOCK_T
        self:set_flash("DRINK CANCELLED")
    end
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
        * BossSkills.dodge_speed_mult(self, dirx, dirz)
    hero.dodge_iframe_t = math.max(hero.dodge_iframe_t or 0.0, hero.dodge_iframes or DODGE_IFRAMES)
    hero.dodge_dx, hero.dodge_dz = dirx, dirz
    hero.facing = math.atan(dirx, dirz)
    self:haptic(15)
    Art.burst("ath_dodge", vec3(hero.x, 0.2, hero.z),
        { preset = "hero_take", count = 12, life_max = 0.28, spawn_radius = 0.34, size_max = 0.15,
          color_start = vec4(0.75, 0.85, 1.0, 0.9), gravity = vec3(0.0, 0.9, 0.0) })
    if (hero.dodge_blades or 0.0) > 0.0 then
        self:hero_burst(3.8, hero.dps * hero.dodge_blades, { 0.9, 0.25, 0.35 })
    end
    BossSkills.on_dodge(self, hero)
    return true
end

function Duel:flask_total()
    local hero = self.hero
    return hero and (hero.flask_health or 0) or 0
end

function Duel:restore_flask_charges(amount)
    local hero = self.hero
    if not hero then return 0 end
    local before = self:flask_total()
    hero.flask_health = math.min(FLASK_CHARGES,
        (hero.flask_health or 0) + math.max(0, math.floor(amount or 0)))
    hero.flask_charges = self:flask_total()
    return hero.flask_charges - before
end

function Duel:try_flask()
    local hero = self.hero
    if not hero then return false end
    if self.state ~= "combat" or hero.dead or (hero.flask_health or 0) < 1 or hero.hp >= hero.hp_max
        or (hero.flask_lock_t or 0.0) > 0.0 or (hero.flask_drink_t or 0.0) > 0.0 then return false end
    -- Melee heroes fight inside the swarm: their committed drink is half as long.
    hero.flask_drink_t = FLASK_DRINK_T
        * (hero.attack_type == "melee" and RULES.flask.melee_drink_mult or 1.0)
    for _, c in ipairs(self.creeps) do
        if c.alive and c.stats and c.stats.flask_hunter and not c.charge_state then
            local dx, dz = hero.x - c.x, hero.z - c.z
            local d = math.sqrt(dx * dx + dz * dz)
            if d > 0.001 then
                local cg = c.stats.charge or {}
                c.charge_state, c.charge_t = "windup", cg.windup or 0.45
                c.charge_dx, c.charge_dz = dx / d, dz / d
                c.charge_cd = cg.cooldown or 4.0
                self._hunter_lunges = (self._hunter_lunges or 0) + 1
                break
            end
        end
    end
    self:set_flash("DRINKING HEALTH")
    self:haptic(10)
    return true
end

function Duel:finish_flask()
    local hero = self.hero
    if not hero then return end
    local before = hero.hp
    hero.hp = math.min(hero.hp_max, hero.hp + hero.hp_max * FLASK_HEAL)
    local gained = hero.hp - before
    if gained > 0 then
        hero.flask_health = hero.flask_health - 1
        hero.dodge_iframe_t = math.max(hero.dodge_iframe_t or 0.0, FLASK_IFRAMES)
        if (hero.flask_nova or 0.0) > 0.0 then
            self:hero_burst(4.0, gained * hero.flask_nova, { 0.35, 1.0, 0.55 })
        end
        if (hero.flask_burst or 0.0) > 0.0 then
            self:hero_burst(4.2, hero.dps * hero.flask_burst, { 0.45, 0.58, 1.0 })
        end
    end
    self:set_flash(gained > 0 and "HEALTH FLASK +%d" or "HEALTH FULL", math.floor(gained + 0.5))
    hero.flask_charges = self:flask_total()
    hero.flask_drink_t = 0.0
    self:haptic(20)
end

function Duel:hero_burst(radius, damage, color)
    local hero = self.hero
    if not hero or damage <= 0.0 then return 0 end
    local hits, r2 = 0, radius * radius
    for _, c in ipairs(self.creeps) do
        if c.alive then
            local dx, dz = c.x - hero.x, c.z - hero.z
            if dx * dx + dz * dz <= r2 then
                self:hit_creep(c, damage, dx * 0.4, dz * 0.4, { discrete = true })
                hits = hits + 1
            end
        end
    end
    color = color or { 0.8, 0.8, 1.0 }
    Art.burst("ath_build_burst", vec3(hero.x, 0.35, hero.z),
        { preset = "hero_take", count = 22, life_max = 0.35, spawn_radius = radius * 0.5,
          size_max = 0.2, color_start = vec4(color[1], color[2], color[3], 1.0) })
    return hits
end

function Duel:park_seed_mine(mine)
    local visual = mine and mine.visual
    if not visual then return end
    if Art.valid(visual.ring) then visual.ring:set_position(vec3(-1000.0, 0.055, -1000.0)) end
    if Art.valid(visual.core) then visual.core:set_position(vec3(-1000.0, 0.42, -1000.0)) end
    self.seed_mine_pool[#self.seed_mine_pool + 1] = visual
    mine.visual = nil
end

function Duel:clear_seed_mines()
    for _, mine in ipairs(self.seed_mines or {}) do self:park_seed_mine(mine) end
    self.seed_mines = {}
end

function Duel:update_seed_mines(dt)
    local keep = {}
    for _, mine in ipairs(self.seed_mines) do
        mine.arm_t = mine.arm_t - dt
        mine.life = mine.life - dt
        mine.pulse_t = mine.pulse_t - dt
        local detonate = mine.life <= 0.0
        if not detonate and mine.trigger_t then
            mine.trigger_t = mine.trigger_t - dt
            detonate = mine.trigger_t <= 0.0
        elseif not detonate and mine.arm_t <= 0.0 then
            local r2 = mine.radius * mine.radius
            for _, c in ipairs(self.creeps) do
                local dx, dz = c.x - mine.x, c.z - mine.z
                if c.alive and dx * dx + dz * dz <= r2 then
                    mine.trigger_t = mine.trigger_delay or 0.5
                    break
                end
            end
        end
        if detonate then
            self:park_seed_mine(mine)
            local r2 = mine.radius * mine.radius
            for _, c in ipairs(self.creeps) do
                if c.alive then
                    local dx, dz = c.x - mine.x, c.z - mine.z
                    local d2 = dx * dx + dz * dz
                    if d2 <= r2 then
                        local d = math.sqrt(math.max(d2, 0.0001))
                        self:hit_creep(c, mine.damage, dx / d * 4.0, dz / d * 4.0,
                            { discrete = true, skill = true })
                    end
                end
            end
            Art.burst("ath_seed_burst", vec3(mine.x, 0.25, mine.z),
                { preset = "enemy_take", count = 24, life_max = 0.4, spawn_radius = mine.radius * 0.55,
                  size_max = 0.24, color_start = vec4(0.48, 0.95, 0.34, 1.0) })
        else
            if mine.visual then
                local pulse = 0.5 + 0.5 * math.sin(self.realtime * 12.0)
                local armed = mine.arm_t <= 0.0
                if Art.valid(mine.visual.ring) then
                    material.set(mine.visual.ring, "base_color", vec4(0.18, 1.0, 0.42, 0.20 + pulse * 0.16))
                    material.set(mine.visual.ring, "emissive", vec3(0.25, 1.2 + pulse, 0.45))
                end
                if Art.valid(mine.visual.core) then
                    mine.visual.core:set_position(vec3(mine.x, 0.42 + pulse * 0.12, mine.z))
                    material.set(mine.visual.core, "base_color", vec4(1.0, mine.trigger_t and 0.35 or (armed and 0.88 or 0.55), 0.08, 1.0))
                    material.set(mine.visual.core, "emissive", vec3(3.0 + pulse * 2.0, mine.trigger_t and 0.4 or (2.0 + pulse), 0.15))
                end
            end
            if mine.pulse_t <= 0.0 then
                mine.pulse_t = 0.18
                Art.burst("ath_seed_pulse", vec3(mine.x, 0.12, mine.z),
                    { preset = "hero_take", count = 2, life_max = 0.22, spawn_radius = 0.18,
                      size_max = 0.10, color_start = vec4(0.62, 1.0, 0.42, 0.9) })
            end
            keep[#keep + 1] = mine
        end
    end
    self.seed_mines = keep
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
        * (1.0 + ((hero.frenzy_t or 0.0) > 0.0 and (hero.frenzy_as or 0.0) or 0.0))
    local targets = math.min(hero.cleave, #in_range)
    for i = 1, targets do
        local mult = (i == 1) and 1.0 or RULES.basic_attack.melee_secondary_mult
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
    hero.whirl_t = hero.attack_type == "melee" and RULES.whirl.melee_cooldown or WHIRL_CD
    local radius = WHIRL_RADIUS_BASE + RULES.whirl.radius_per_stack * hero.whirl
    if hero.attack_type == "melee" then radius = math.max(radius, hero.attack_range or radius) end
    local r2 = radius * radius
    local damage = hero.dps * (hero.attack_type == "melee"
        and RULES.whirl.melee_damage_mult or RULES.whirl.ranged_damage_mult) * hero.whirl
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
local HPROJ_SPEED = RULES.basic_attack.projectile_speed
local HPROJ_HIT_R = RULES.basic_attack.projectile_hit_radius
local HPROJ_LIFE = RULES.basic_attack.projectile_life

function Duel:hproj_hide(p)
    p.active = false
    p.mage_effects = nil
    p.rogue_effects = nil
    p.necro_effects = nil
    p.rogue_basic, p.necro_basic = nil, nil
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

-- Orbit Blades proc boon: 2 pooled orbs circling the hero, dealing contact dps
-- through the melee-aggregation path (so hits batch and flush as damage numbers,
-- same as the brawler's contact loop). Parked at -1000 when the boon is unheld
-- or combat is frozen. No per-frame allocation: the two nodes live for the run.
local ORBIT_COUNT = 2

function Duel:ensure_orbit_pool()
    if self.orbit_pool then return end
    if not (self.groups and self.groups.actors) then return end
    self.orbit_pool = {}
    for i = 1, ORBIT_COUNT do
        local node = Art.sphere("OrbitBlade_" .. i, vec3(-1000.0, 0.9, -1000.0),
            vec3(0.42, 0.42, 0.42), { 0.70, 0.95, 1.0, 1.0 }, self.groups.actors, 2.4)
        self.orbit_pool[i] = { node = node }
    end
end

function Duel:park_orbit_blades()
    for _, b in ipairs(self.orbit_pool or {}) do
        if Art.valid(b.node) then b.node:set_position(vec3(-1000.0, 0.9, -1000.0)) end
    end
end

function Duel:update_orbit_blades(dt)
    local hero = self.hero
    local ob = hero and hero.orbit_blades
    if not (self.state == "combat" and hero and not hero.dead and ob) then
        if self.orbit_pool then self:park_orbit_blades() end
        return
    end
    self:ensure_orbit_pool()
    if not self.orbit_pool then return end
    self._orbit_t = (self._orbit_t or 0.0) + dt
    local radius = ob.radius or 2.4
    local dps = ob.dps or 14.0
    local contact2 = (radius * 0.55) * (radius * 0.55)
    for i, b in ipairs(self.orbit_pool) do
        local ang = self._orbit_t * 3.2 + (i - 1) * (2.0 * math.pi / ORBIT_COUNT)
        local bx = hero.x + math.cos(ang) * radius
        local bz = hero.z + math.sin(ang) * radius
        if Art.valid(b.node) then b.node:set_position(vec3(bx, 0.9, bz)) end
        for _, c in ipairs(self.creeps) do
            if c.alive then
                local dx, dz = c.x - bx, c.z - bz
                if dx * dx + dz * dz <= contact2 then
                    self:hit_creep(c, dps * dt, dx * 0.2, dz * 0.2, { melee = true })
                end
            end
        end
    end
end

-- Critical Burst proc boon: a crit detonates a modest AoE around the victim.
-- Visual = the death-burst particle pool; damage is flat (pre_scaled, no crit,
-- no knockback) on OTHER creeps in range, so it can't recurse or stack knockback.
function Duel:proc_crit_burst(c, base_amount)
    local hero = self.hero
    local cb = hero and hero.crit_burst
    if not (cb and c) then return end
    local radius = cb.radius or 2.2
    Art.burst("ath_crit_pop_" .. tostring(c.id), vec3(c.x, 0.6, c.z),
        { preset = "enemy_take", count = 18, life_max = 0.30, spawn_radius = radius * 0.5,
          size_max = 0.22, color_start = vec4(1.0, 0.72, 0.2, 1.0) })
    local dmg = (base_amount or 0.0) * (cb.dmg_mult or 0.6)
    if dmg < 0.5 then return end
    local r2 = radius * radius
    for _, o in ipairs(self.creeps) do
        if o.alive and o.id ~= c.id then
            local dx, dz = o.x - c.x, o.z - c.z
            if dx * dx + dz * dz <= r2 then
                self:hit_creep(o, dmg, 0.0, 0.0, { pre_scaled = true })
            end
        end
    end
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
    slot.damage = (hero.dps or 10.0) * RULES.basic_attack.ranged_damage_mult
    slot.piercing, slot.hit_ids, slot.skill, slot.mage_effects, slot.rogue_effects = nil, nil, nil, nil, nil
    slot.bounced = nil
    slot.necro_effects, slot.rogue_basic, slot.necro_basic = nil, nil, nil
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
    return slot
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
        { preset = "hero_take", count = 8, life_max = 0.20, spawn_radius = 0.22, size_max = 0.14,
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
                if c.alive and not (p.hit_ids and p.hit_ids[c.id]) then
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
                local piercing = self:apply_on_hit_specializations(hit, p.damage, nx, nz)
                local killed, was_crit = self:hit_creep(hit, p.damage,
                    nx * CREEP_KNOCK_BOLT, nz * CREEP_KNOCK_BOLT,
                    { discrete = true })
                if killed and hero and (hero.lifesteal or 0.0) > 0.0 then
                    hero.hp = math.min(hero.hp_max, hero.hp + hero.lifesteal)
                end
                local ic = was_crit and { 1.0, 0.72, 0.2 } or (p.col or { 1.0, 0.92, 0.5 })
                Art.burst("ath_hero_hit_" .. tostring(hit.id), vec3(p.x, 0.6, p.z),
                    { preset = "enemy_take", count = was_crit and 22 or 12,
                      life_max = was_crit and 0.30 or 0.20, spawn_radius = was_crit and 0.32 or 0.18,
                      size_max = was_crit and 0.24 or 0.17,
                      color_start = vec4(ic[1], ic[2], ic[3], 1.0) })
                -- Chain Bolt proc: the impact arcs ONCE to the nearest other foe
                -- in range for a fraction of the damage, via the same discrete hit
                -- path (crit + damage number roll independently).
                if hero and hero.chain_bolt and not p.bounced then
                    local cbf = hero.chain_bolt
                    local cr2 = (cbf.range or 4.0) * (cbf.range or 4.0)
                    local best, bestd
                    for _, o in ipairs(self.creeps) do
                        if o.alive and o.id ~= hit.id and not (p.hit_ids and p.hit_ids[o.id]) then
                            local ex, ez = o.x - hit.x, o.z - hit.z
                            local dd = ex * ex + ez * ez
                            if dd <= cr2 and (not bestd or dd < bestd) then best, bestd = o, dd end
                        end
                    end
                    if best then
                        p.bounced = true
                        local bx, bz = best.x - hit.x, best.z - hit.z
                        local bd = math.sqrt(bx * bx + bz * bz)
                        bx, bz = (bd > 0.001) and bx / bd or 0.0, (bd > 0.001) and bz / bd or 0.0
                        self:hit_creep(best, p.damage * (cbf.fraction or 0.5),
                            bx * CREEP_KNOCK_BOLT, bz * CREEP_KNOCK_BOLT, { discrete = true })
                        Art.burst("ath_chain_" .. tostring(best.id), vec3(best.x, 0.6, best.z),
                            { preset = "enemy_take", count = 8, life_max = 0.18, spawn_radius = 0.16,
                              size_max = 0.14, color_start = vec4(0.55, 0.9, 1.0, 1.0) })
                    end
                end
                if piercing then
                    p.hit_ids = p.hit_ids or {}
                    p.hit_ids[hit.id] = true
                else
                    self:hproj_hide(p)
                end
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
-- Necromancer minions — pooled friendly assistants raised by Soul Bolt hits.
-- Kind-locked flat-sprite pools (one quad per slot, texture + scale baked at
-- creation — no mid-combat node builds or texture swaps). Minions seek the
-- nearest creep, bite/shoot on an interval through the SAME hit_creep /
-- hero-bolt funnels as the hero (so kills count and pop numbers), get
-- chewed by creeps standing on them, and park on wave end / reset / death.
-- All tuning lives in Balance.minions + the necromancer specialization rows.
-- ---------------------------------------------------------------------------

function Duel:ensure_minion_pool()
    if self.minions then return end
    if not (self.groups and self.groups.actors) then return end
    self.minions = {}
    for kind, spec in pairs(MINIONS) do
        for i = 1, spec.cap_max do
            local size = 1.8 * (spec.scale or 1.0) * Art.s("char")
            local node = Art.part({
                name = "Minion_" .. kind .. "_" .. i, kind = "quad",
                quad_width = size, quad_height = size * 1.25,
                position = { -1000.0, 0.9, -1000.0 }, rotation = { -90.0, 0.0, 0.0 },
                color = { 1.0, 1.0, 1.0 }, emissive = 1.0, emissive_texture = true,
                texture = spec.texture,
            }, self.groups.actors)
            local slot = {
                node = node, kind = kind, active = false,
                parts = { body = node }, x = -1000.0, z = -1000.0, alive = true,
            }
            if spec.sprite_sheet then
                Anim.setup(slot, spec, "minion")
            end
            self.minions[#self.minions + 1] = slot
        end
    end
end

function Duel:park_minion(m)
    m.active = false
    if Art.valid(m.node) then
        m.node:set_position(vec3(-1000.0, 0.9, -1000.0))
        material.set(m.node, "emissive", vec3(1.0, 1.0, 1.0)) -- no tint leaks on reuse
    end
end

function Duel:park_all_minions()
    for _, m in ipairs(self.minions or {}) do
        if m.active then self:park_minion(m) end
    end
end

function Duel:count_minions(kind)
    local n = 0
    for _, m in ipairs(self.minions or {}) do
        if m.active and m.kind == kind then n = n + 1 end
    end
    return n
end

function Duel:try_summon_minion(kind, cap, x, z)
    self:ensure_minion_pool()
    if not self.minions or self:count_minions(kind) >= (cap or 0) then return end
    local slot
    for _, m in ipairs(self.minions) do
        if not m.active and m.kind == kind then slot = m break end
    end
    if not slot then return end
    local spec = MINIONS[kind]
    local hero = self.hero
    local A = self.arena
    local minx, maxx, minz, maxz = arena_actor_bounds(A, 0.8)
    slot.active = true
    slot.x = clampn(x or (hero and hero.x) or 0.0, minx, maxx)
    slot.z = clampn(z or (hero and hero.z) or 0.0, minz, maxz)
    slot.hp = spec.hp_mult * ((hero and hero.hp_max) or 100.0)
    slot.hp_max = slot.hp
    slot.dps = spec.dps_mult * ((hero and hero.dps) or 10.0)
        * ((hero and hero.minion_dmg_mult) or 1.0)
    slot.life = spec.duration
    slot.attack_t = 0.0
    slot.alive = true
    if slot._sprite_anim then
        slot._sprite_anim.oneshot_until = 0.0
        slot._sprite_anim.clip = nil
        if Anim.available() and Art.valid(slot.node) then sprite.play(slot.node, "idle", true) end
        slot._sprite_anim.clip = "idle"
    end
    if Art.valid(slot.node) then slot.node:set_position(vec3(slot.x, 0.9, slot.z)) end
    Art.burst("ath_summon_" .. kind, vec3(slot.x, 0.4, slot.z),
        { preset = "hero_take", count = 12, life_max = 0.35, spawn_radius = 0.4,
          size_max = 0.16, velocity = vec3(0.0, 2.2, 0.0),
          color_start = vec4(spec.color[1], spec.color[2], spec.color[3], 1.0) })
    return slot
end

function Duel:update_minions(dt)
    if not self.minions then return end
    local hero = self.hero
    for _, m in ipairs(self.minions) do
        if m.active then
            local spec = MINIONS[m.kind]
            m.life = m.life - dt
            -- Creeps standing on a minion chew it down (contact only — nothing
            -- retargets off the hero, so assistants BUY space, not aggro).
            for _, c in ipairs(self.creeps) do
                if c.alive then
                    local dx, dz = c.x - m.x, c.z - m.z
                    local reach = 0.5 + ((c.stats and c.stats.range) or 0.5)
                    if dx * dx + dz * dz <= reach * reach then
                        m.hp = m.hp - ((c.stats and c.stats.dps) or 1.0) * dt
                    end
                end
            end
            if m.life <= 0.0 or m.hp <= 0.0 then
                Art.burst("ath_minion_out_" .. tostring(m.kind), vec3(m.x, 0.4, m.z),
                    { preset = "enemy_take", count = 10, life_max = 0.30, spawn_radius = 0.3,
                      size_max = 0.14, color_start = vec4(spec.color[1], spec.color[2], spec.color[3], 0.9) })
                self:park_minion(m)
            else
                -- Seek the nearest living creep; hold at attack range and strike
                -- on the balance interval through the shared damage funnels.
                local target, best_d
                for _, c in ipairs(self.creeps) do
                    if c.alive then
                        local dx, dz = c.x - m.x, c.z - m.z
                        local d2 = dx * dx + dz * dz
                        if not target or d2 < best_d then target, best_d = c, d2 end
                    end
                end
                m.attack_t = math.max(0.0, (m.attack_t or 0.0) - dt)
                if m._attack_flash then
                    m._attack_flash = math.max(0.0, m._attack_flash - dt)
                end
                if target then
                    m._face_x = target.x - m.x
                    m._face_z = target.z - m.z
                    m.facing = math.atan(m._face_x, m._face_z)
                    local d = math.sqrt(best_d)
                    if d > spec.range then
                        local A = self.arena
                        local minx, maxx, minz, maxz = arena_actor_bounds(A, 0.8)
                        local step = spec.speed * dt / math.max(d, 0.001)
                        m.x = clampn(m.x + (target.x - m.x) * step, minx, maxx)
                        m.z = clampn(m.z + (target.z - m.z) * step, minz, maxz)
                    elseif m.attack_t <= 0.0 then
                        m.attack_t = spec.attack_interval
                        m._attack_flash = 0.20
                        if spec.kind == "ranged" then
                            local shot = self:spawn_hero_bolt(
                                { x = m.x, z = m.z, dps = m.dps,
                                  bolt_color = spec.bolt_color, bolt_scale = spec.bolt_scale }, target)
                            if shot then
                                shot.damage = m.dps * spec.attack_interval
                            end
                        else
                            local dx, dz = target.x - m.x, target.z - m.z
                            local n = math.max(d, 0.001)
                            self:hit_creep(target, m.dps * spec.attack_interval,
                                dx / n * CREEP_KNOCK_MELEE, dz / n * CREEP_KNOCK_MELEE,
                                { discrete = true })
                        end
                    end
                elseif hero and not hero.dead then
                    -- No foes: drift back to heel so the pack reads as the hero's.
                    local dx, dz = hero.x - m.x, hero.z - m.z
                    local d = math.sqrt(dx * dx + dz * dz)
                    m._face_x, m._face_z = dx, dz
                    if d > 0.001 then m.facing = math.atan(dx, dz) end
                    if d > 3.0 then
                        m.x = m.x + dx / d * spec.speed * 0.6 * dt
                        m.z = m.z + dz / d * spec.speed * 0.6 * dt
                    end
                end
                if m._sprite_anim then
                    Anim.tick(m, self.realtime or 0.0)
                    if Art.valid(m.node) then
                        m.node:set_rotation(vec3(-90.0, 0.0, Anim.facing_roll(m)))
                        m.node:set_position(vec3(m.x, 0.9, m.z))
                    end
                elseif Art.valid(m.node) then
                    m.node:set_position(vec3(m.x, 0.9, m.z))
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
    opts = opts or {}
    local rider_amount = amount
    if not opts.pre_scaled then
        amount = amount * ((self.hero and self.hero.boss_damage_mult) or 1.0)
        if self.manual_hero and c.stats and c.stats.boss and not opts.armor_applied then
            if opts.skill then
                if (c.armor_broken_t or 0.0) <= 0.0 then self:set_flash("ARMOR BROKEN") end
                c.armor_broken_t = opts.armor_break_t or ARMOR_BREAK_T
            elseif (c.armor_broken_t or 0.0) <= 0.0 then
                amount = amount * BOSS_ARMOR_MULT
            end
        end
        if (c.armor_debuff_t or 0.0) > 0.0 then
            amount = amount * (1.0 + (c.armor_reduction or 0.0))
        end
        if (c.curse_t or 0.0) > 0.0 then
            amount = amount * (1.0 + (c.curse_amp or 0.0))
        end
        if (c._tribute_armor_t or 0.0) > 0.0 then amount = amount * 0.65 end
        if self.hero and (self.hero.frenzy_t or 0.0) > 0.0 then
            amount = amount * (1.0 + (self.hero.frenzy_dmg or 0.0))
        end
        amount = amount * self:hero_damage_amp(c)
    end
    local crit = opts.crit == true
    if opts.discrete then
        crit = self:roll_crit()
        if crit then amount = amount * CRIT_MULT end
        self:spawn_damage_number(c.x, c.z, amount, crit)
        if crit and self.hero and self.hero.crit_burst then self:proc_crit_burst(c, amount) end
    elseif opts.melee then
        c._mdmg = (c._mdmg or 0.0) + amount
        c._mrider = (c._mrider or 0.0) + rider_amount
        c._mdmg_t = c._mdmg_t or MELEE_FLUSH_T
    end
    local hp_before = c.hp
    local killed = Creep.damage(c, amount)
    -- Melee sustain: landed blows trickle health-flask charges back (same
    -- dps-second normalisation). Banked at one pending charge while full so a
    -- spent flask refills quickly in the thick of it.
    if self.manual_hero and self.hero and self.hero.attack_type == "melee"
        and not opts.skill and not opts.no_flask_refill then
        local hero = self.hero
        hero.flask_hit_charge = (hero.flask_hit_charge or 0.0)
            + math.min(hp_before, amount) / math.max(1.0, hero.dps) * RULES.flask.melee_refill_rate
        if hero.flask_hit_charge >= 1.0 then
            if self:flask_total() < FLASK_CHARGES then
                hero.flask_hit_charge = hero.flask_hit_charge - 1.0
                self:restore_flask_charges(1)
                self:spawn_damage_number(hero.x, hero.z, 0, false,
                    { text = T("+FLASK"), color = { 0.42, 0.86, 0.52 } })
            else
                hero.flask_hit_charge = 1.0
            end
        end
    end
    if crit and not killed and self.hero and (self.hero.bleed_on_crit or 0.0) > 0.0 then
        c.bleed_t = RULES.crit.bleed_seconds
        c.bleed_dps = math.max(c.bleed_dps or 0.0, self.hero.bleed_on_crit)
    end
    if killed then c._hero_killed = true end
    if not killed then
        c.hit_flash = HIT_FLASH_T
        if (kx and kx ~= 0.0) or (kz and kz ~= 0.0) then Creep.knock(c, kx or 0.0, kz or 0.0) end
    end
    return killed, crit, amount
end

-- Flush a creep's aggregated melee packet: roll the crit for the window (a crit
-- deals the same packet AGAIN as bonus damage, so crit_chance genuinely raises
-- melee dps) and pop one number.
function Duel:flush_melee_packet(c)
    local amt = c._mdmg or 0.0
    local rider_amt = c._mrider or 0.0
    if amt < 0.5 then
        c._mdmg, c._mrider, c._mdmg_t = 0.0, 0.0, nil
        return
    end
    local hero = self.hero
    if hero then
        local dx, dz = c.x - hero.x, c.z - hero.z
        local d = math.sqrt(dx * dx + dz * dz)
        self:apply_on_hit_specializations(c, rider_amt,
            d > 0.001 and dx / d or 0.0, d > 0.001 and dz / d or 0.0)
    end
    local crit = self:roll_crit()
    if crit and c.alive then
        self:hit_creep(c, amt, nil, nil, { armor_applied = true, crit = true, pre_scaled = true })
        amt = amt * CRIT_MULT
    end
    self:spawn_damage_number(c.x, c.z, amt, crit)
    if crit and self.hero and self.hero.crit_burst then self:proc_crit_burst(c, amt) end
    c._mdmg = 0.0
    c._mrider = 0.0
    c._mdmg_t = nil
end

-- ---------------------------------------------------------------------------
-- Floating damage numbers — a fixed pool of screen-space text quads projected
-- from world positions (runtime_ui.set_quad is retained + cheap per frame).
-- Crits pop bigger, gold pickups reuse the same pool tinted gold.
-- ---------------------------------------------------------------------------
function Duel:spawn_damage_number(x, z, amount, crit, opts)
    if ATH_COMMON.world_frozen and ATH_COMMON.world_frozen(self) then return end
    if _G.ATH_I18N and _G.ATH_I18N.damage_text == false and not (opts and opts.text) then return end
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
    slot.color = (opts and opts.color) or { 0.97, 0.97, 1.0 }
    slot.jx = (opts and opts.jx) or (math.random() - 0.5) * 0.8
    slot.ox = (math.random() - 0.5) * 96.0
    slot.oy = (math.random() - 0.5) * 64.0
    slot.scale = (opts and opts.scale) or 1.0
end

function Duel:update_damage_numbers(dt)
    local list = self.dmgnums
    if not list then return end
    self._dmgnum_t = (self._dmgnum_t or 0.0) + dt
    if self._dmgnum_t < DMGNUM_STEP then return end
    dt, self._dmgnum_t = self._dmgnum_t, 0.0
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
                    local fs = (e.crit and 1.9 or 1.2) * e.scale
                        * (1.0 + 0.25 * math.min(1.0, e.t * 8.0)) * (1.0 / 3.0)
                    local a = k < 0.65 and 1.0 or (1.0 - (k - 0.65) / 0.35)
                    runtime_ui.set_quad(self.hud, e.id, {
                        x = sx - 34.0 + e.ox, y = sy - 52.0 * k - 30.0 + e.oy, style = "text", fit = true,
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
    self._dmgnum_t = 0.0
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
    -- Force the status tint back to base BEFORE the rig parks: a creep killed
    -- after this frame's tint pass (melee packet flush, thorns) would otherwise
    -- pool its body still poison-green/bleed-red (on_spawn only resets emissive).
    if c then self:update_creep_status_tint(c) end
    if not (c and Art.valid(c.root)) then
        Creep.destroy(c)
        return
    end
    self.dying = self.dying or {}
    local dur = (c.stats and c.stats.boss) and 0.30 or 0.16
    if c._sprite_anim then dur = 0.55 end -- match Anim death oneshot
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
            if c._sprite_anim then
                if Art.valid(c.root) then c.root:set_rotation(vec3(0.0, 0.0, 0.0)) end
                local body = c.parts and c.parts.body
                if Art.valid(body) then
                    local k = d.t / d.dur
                    local e = 1.0 + 3.0 * k
                    local col = c._status_tint_color or { 1.0, 1.0, 1.0 }
                    material.set(body, "emissive", vec3(col[1] * e, col[2] * e, col[3] * e))
                end
            else
                local k = d.t / d.dur
                c.root:set_rotation(vec3(0.0, (1.0 - k) * 640.0 * d.dir, 0.0))
                local body = c.parts and c.parts.body
                if Art.valid(body) then
                    local e = 7.0 * k
                    local col = c._status_tint_color or { 1.0, 1.0, 1.0 }
                    material.set(body, "emissive", vec3(col[1] * e, col[2] * e, col[3] * e))
                end
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
            texture = V.ui.items.weapon, emissive_texture = true,
        }, root)
        self.beacons[i] = { node = root, disc = disc, icon = icon, pool_index = i, active = false }
    end
end

local function park_pickup(e)
    e.active = false
    e.essence = nil
    e.boon = nil
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
            if e.active and not e.essence then e.value = e.value + (value or 1); return end
        end
        return
    end
    slot.active = true
    slot.essence = nil
    slot.x, slot.z = x, z
    slot.value = value or 1
    local ang = math.random() * 6.2831
    local sp = 2.5 + math.random() * 2.5
    slot.vx, slot.vz = math.sin(ang) * sp, math.cos(ang) * sp
    if Art.valid(slot.node) then
        slot.node:set_position(vec3(x, 0.22, z))
        material.set(slot.node, "base_color", vec4(1.0, 0.84, 0.25, 1.0))
        material.set(slot.node, "emissive", vec3(1.8, 1.5, 0.35))
    end
    return slot
end

function Duel:spawn_essence(x, z)
    local slot = self:spawn_coin(x, z, 0)
    if not slot then self:restore_flask_charges(1); return end
    slot.essence = true
    if Art.valid(slot.node) then
        material.set(slot.node, "base_color", vec4(0.42, 0.68, 1.0, 1.0))
        material.set(slot.node, "emissive", vec3(0.8, 1.3, 2.2))
    end
end

function Duel:spawn_item_beacon(x, z, item)
    if item and self.loot_filter and self.loot_filter[item.rarity or "common"] == false then return end
    self:ensure_pickup_pools()
    if not (item and self.beacons) then return end
    local slot
    for _, e in ipairs(self.beacons) do
        if not e.active then slot = e; break end
    end
    if not slot then
        -- No free beacon: fall back to the old straight-to-bag path.
        if Inventory.add_item(self, item) then self:set_flash("Found %s", (_G.ATH_I18N and _G.ATH_I18N.t(tostring(item.name or item.id))) or tostring(item.name or item.id)) end
        return
    end
    slot.active = true
    slot.x, slot.z = x, z
    slot.item = item
    slot.boon = nil -- gear beacon: clear any boon left on a reused slot
    slot.retry_t = 0.0
    local col = RARITY_COLOR[item.rarity or "common"] or RARITY_COLOR.common
    if Art.valid(slot.node) then
        slot.node:set_position(vec3(x, 0.06, z))
        material.set(slot.disc, "base_color", vec4(col[1], col[2], col[3], 1.0))
        local icon = Inventory.SLOT_ICON[item.slot]
        if Art.valid(slot.icon) then
            slot.icon:set_scale(vec3(1.0, 1.0, 1.0)) -- restore (a boon beacon hides it)
            if icon then
                Art.texture(slot.icon, icon)
                Art.texture(slot.icon, icon, "emissive")
            end
        end
    end
end

-- Boon beacons ride the gear-beacon pool but grant a proc-boon card straight into
-- run_cards (no bag; boons aren't inventory items). They read distinct: no floating
-- slot icon, and a faster/brighter pulse in the boon's rarity colour.
function Duel:eligible_boon()
    -- Exclude boons the hero owns AND boons already dropped on the field (a
    -- second elite must not roll a duplicate before the first is picked up).
    local taken = {}
    for _, card in ipairs(self.run_cards or {}) do
        if card.boon and card.id then taken[card.id] = true end
    end
    for _, e in ipairs(self.beacons or {}) do
        if e.active and e.boon and e.boon.id then taken[e.boon.id] = true end
    end
    local pool, total = {}, 0.0
    for _, card in ipairs(Balance.draft_boons or {}) do
        if not taken[card.id] then pool[#pool + 1] = card; total = total + (card.weight or 1) end
    end
    if #pool == 0 then return nil end
    local r = math.random() * total
    for _, card in ipairs(pool) do
        r = r - (card.weight or 1)
        if r <= 0.0 then return card end
    end
    return pool[#pool]
end

function Duel:grant_boon(card, x, z)
    if not card then return end
    self.run_cards = self.run_cards or {}
    -- Idempotent: never bank a duplicate boon (effects are non-stacking).
    for _, c in ipairs(self.run_cards) do
        if c.boon and c.id == card.id then return end
    end
    self.run_cards[#self.run_cards + 1] = card
    self:recompute_hero_stats()
    self:save_profile()
    local col = RARITY_COLOR[card.rarity or "rare"] or RARITY_COLOR.rare
    local nm = (_G.ATH_I18N and _G.ATH_I18N.t(tostring(card.name))) or tostring(card.name)
    self:set_flash("Gained %s", nm)
    self:spawn_damage_number(x, z, 0, false, { text = nm, color = col })
    Art.burst("ath_boon_pickup", vec3(x, 0.7, z),
        { preset = "hero_take", count = 28, life_max = 0.55, spawn_radius = 0.5, size_max = 0.20,
          color_start = vec4(col[1], col[2], col[3], 1.0), gravity = vec3(0.0, 2.4, 0.0) })
    self:haptic(14)
    self:log("boon acquired " .. tostring(card.id))
end

function Duel:spawn_boon_beacon(x, z, card)
    self:ensure_pickup_pools()
    if not (card and self.beacons) then return end
    local slot
    for _, e in ipairs(self.beacons) do if not e.active then slot = e; break end end
    if not slot then self:grant_boon(card, x, z); return end -- pool full: grant outright
    slot.active = true
    slot.x, slot.z = x, z
    slot.item = nil
    slot.boon = card
    slot.retry_t = 0.0
    local col = RARITY_COLOR[card.rarity or "rare"] or RARITY_COLOR.rare
    if Art.valid(slot.node) then
        slot.node:set_position(vec3(x, 0.06, z))
        material.set(slot.disc, "base_color", vec4(col[1], col[2], col[3], 1.0))
        if Art.valid(slot.icon) then slot.icon:set_scale(vec3(0.0001, 0.0001, 0.0001)) end
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
                if e.essence then
                    if self:restore_flask_charges(1) > 0 then
                        self:spawn_damage_number(e.x, e.z, 0, false,
                            { text = "ESSENCE +1", color = { 0.42, 0.68, 1.0 } })
                    end
                else
                    self.gold = (self.gold or 0) + math.max(1, math.floor(e.value * gf + 0.5))
                    self._gold_pop = (self._gold_pop or 0) + math.max(1, math.floor(e.value * gf + 0.5))
                end
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
            local info = item or e.boon -- gear OR boon: both carry name/desc/rarity
            local col = RARITY_COLOR[(info and info.rarity) or "common"] or RARITY_COLOR.common
            if Art.valid(e.node) then
                -- Boon beacons pulse faster + brighter so they read distinct from gear.
                local p = e.boon and (0.9 + 0.9 * math.abs(math.sin(self.realtime * 8.0)))
                    or (0.7 + 0.6 * math.abs(math.sin(self.realtime * 5.0)))
                material.set(e.disc, "emissive", vec3(col[1] * p, col[2] * p, col[3] * p))
            end
            if pickup_vp and info and mx and runtime_ui and runtime_ui.set_quad then
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
                        hovered = { item = info, col = col, sx = sx, sy = sy, d2 = d2 }
                    end
                end
            end
            local dx, dz = hero.x - e.x, hero.z - e.z
            local br = math.max(BEACON_COLLECT_R, pr)
            if not hero.dead and e.retry_t <= 0.0 and (dx * dx + dz * dz) <= br * br then
                if e.boon then
                    -- Boons aren't bag items: grant straight into run_cards (no bag-full).
                    self:grant_boon(e.boon, e.x, e.z)
                    park_pickup(e)
                elseif Inventory.add_item(self, e.item) then
                    self:log("found " .. tostring(e.item.id))
                    self:set_flash("Found %s", (_G.ATH_I18N and _G.ATH_I18N.t(tostring(e.item.name or e.item.id))) or tostring(e.item.name or e.item.id))
                    self:spawn_damage_number(e.x, e.z, 0, false,
                        { text = T(tostring(e.item.name or e.item.id)),
                          color = RARITY_COLOR[e.item.rarity or "common"] or RARITY_COLOR.common })
                    self:haptic(10)
                    park_pickup(e)
                else
                    self:set_flash("Bag full!")
                    -- Also say it AT the item — the top flash is easy to miss.
                    self:spawn_damage_number(e.x, e.z, 0, false,
                        { text = T("BAG FULL"), color = { 1.0, 0.38, 0.3 } })
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
            body = T(tostring(hovered.item.name or hovered.item.id)) .. "\n"
                .. T(tostring(hovered.item.desc or "")),
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

-- Gold / essence bank immediately (no bag). Item beacons stay for walk-pick.
function Duel:vacuum_coins()
    local hero = self.hero
    local gf = (hero and hero.gold_find) or 1.0
    for _, e in ipairs(self.coins or {}) do
        if e.active then
            if e.essence then
                self:restore_flask_charges(1)
            else
                self.gold = (self.gold or 0) + math.max(1, math.floor(e.value * gf + 0.5))
            end
            park_pickup(e)
        end
    end
end

-- Bank leftover item beacons (after the loot walk, or when abandoning a map).
-- Full bag still drops the item — the loot window is the chance to make space.
function Duel:vacuum_items()
    for _, e in ipairs(self.beacons or {}) do
        if e.active then
            if e.boon then
                self:grant_boon(e.boon, e.x, e.z) -- boons never bag; never lost
            elseif Inventory.add_item(self, e.item) then
                self:set_flash("Found %s", (_G.ATH_I18N and _G.ATH_I18N.t(tostring(e.item.name or e.item.id))) or tostring(e.item.name or e.item.id))
            else
                self:set_flash("Bag full - %s lost", (_G.ATH_I18N and _G.ATH_I18N.t(tostring(e.item.name or e.item.id))) or tostring(e.item.name or e.item.id))
            end
            park_pickup(e)
        end
    end
    if runtime_ui and runtime_ui.remove then runtime_ui.remove(self.hud, "beacon_tip") end
end

function Duel:vacuum_pickups()
    self:vacuum_coins()
    self:vacuum_items()
end

-- Hover tooltip for the top-left mutator icon row (mode.lua draw_hud passes the
-- surface-space rects). Reuses the same pointer + set_quad text-tooltip pattern
-- as the inventory (inv_tip) / beacon (beacon_tip) tips: hit-test ui_pointer
-- against each icon rect, show name + one-line desc anchored just under the icon,
-- clamped inside the viewport. Cleared when not hovering (empty rects clears it).
function Duel:mutator_tooltip(rects)
    if not (runtime_ui and runtime_ui.set_quad) then return end
    local mx, my = ui_pointer()
    local hovered
    if mx then
        for _, r in ipairs(rects or {}) do
            if mx >= r.x and mx <= r.x + r.sz and my >= r.y and my <= r.y + r.sz then
                hovered = r
                break
            end
        end
    end
    if not hovered then
        if runtime_ui.remove then runtime_ui.remove(self.hud, "mutator_tip") end
        return
    end
    local function S(v) return v * Art.s("hud") end
    local vp = Art._vp
    local rw, rh = (vp and vp.rw) or 2400.0, (vp and vp.rh) or 1080.0
    local margin = S(8.0)
    local tw = math.min(S(300.0), rw - 2.0 * margin)
    local tx = hovered.x
    local ty = hovered.y + hovered.sz + S(6.0) -- just under the icon row
    tx = math.max(margin, math.min(tx, rw - tw - margin))
    ty = math.max(margin, math.min(ty, rh - S(90.0) - margin))
    runtime_ui.set_quad(self.hud, "mutator_tip", {
        x = tx, y = ty, width = tw, style = "text", fit = true,
        fill = { 0.04, 0.05, 0.08, 0.98 }, border = hovered.col or { 0.9, 0.85, 0.4, 1.0 },
        body = Art.ascii(tostring(hovered.name) .. "\n" .. tostring(hovered.desc or "")),
        text_color = { 0.92, 0.94, 0.98, 1.0 },
        font_scale = 2.0, align_h = "left", align_v = "top",
        no_input = true, bring_to_front = true, z = 7000.0,
    })
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
    p.source_archetype = nil
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
    slot.source_archetype = desc.source_archetype
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

function Duel:creep_attack_misses(c)
    if (c.smoke_t or 0.0) <= 0.0 or math.random() >= (c.smoke_miss or 0.0) then return false end
    self:spawn_damage_number(c.x, c.z, 0, false, { text = T("MISS"), color = STATUS_COLOR.shadow })
    return true
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
            if self:creep_attack_misses(c) then return end
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
    local attack_slow = c.attack_slow_mult or 1.0
    local cd = spec.cooldown or 0.9
    local desc = Creep.attack_projectile(c, hero, (c.stats.dps or 2.0) * cd * (c.damage_mult or 1.0))
    if desc then
        c.projectile_t = (c.projectile_t or cd) / math.max(0.1, attack_slow)
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
                BossSkills.on_projectile_end(self, p)
                self:cproj_hide(p)
            elseif p.life <= 0.0 or off then
                BossSkills.on_projectile_end(self, p)
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
    self.boss_arc_nodes = {}
    for i = 1, 5 do
        local node = Art.cylinder("BossArc_" .. i, vec3(-1000.0, 0.045, -1000.0),
            vec3(2.6, 0.025, 2.6), { 1.0, 0.12, 0.08, 0.45 }, self.groups.world, 1.5)
        if Art.valid(node) and material and material.set_render_type then material.set_render_type(node, "alpha_blend") end
        self.boss_arc_nodes[i] = node
    end
    self.furrow_pool = {}
    self.furrows = {}
    for i = 1, 24 do
        local node = Art.cube("RoyalFurrow_" .. i, vec3(-1000.0, 0.025, -1000.0),
            vec3(0.46, 0.025, 1.0), { 0.20, 0.08, 0.025, 0.72 }, self.groups.world, 0.18)
        if Art.valid(node) and material and material.set_render_type then material.set_render_type(node, "alpha_blend") end
        self.furrow_pool[i] = node
    end
    self.furrow_bomb_pool = {}
    self.furrow_bombs = {}
    for i = 1, 10 do
        local ring = Art.cylinder("RoyalFurrowBombRing_" .. i, vec3(-1000.0, 0.055, -1000.0),
            vec3(4.4, 0.025, 4.4), { 1.0, 0.18, 0.06, 0.42 }, self.groups.world, 1.8)
        local core = Art.sphere("RoyalFurrowBomb_" .. i, vec3(-1000.0, 0.42, -1000.0),
            vec3(0.85, 0.70, 0.85), { 1.0, 0.38, 0.04 }, self.groups.world, 2.0)
        if Art.valid(ring) and material and material.set_render_type then material.set_render_type(ring, "alpha_blend") end
        self.furrow_bomb_pool[i] = { ring = ring, core = core }
    end
    self.seed_mine_pool = {}
    for i = 1, 8 do
        local ring = Art.cylinder("SeedMineRing_" .. i, vec3(-1000.0, 0.055, -1000.0),
            vec3(6.6, 0.02, 6.6), { 0.18, 1.0, 0.42, 0.28 }, self.groups.world, 1.8)
        local core = Art.sphere("SeedMineCore_" .. i, vec3(-1000.0, 0.42, -1000.0),
            vec3(1.0, 1.0, 1.0), { 1.0, 0.82, 0.08, 1.0 }, self.groups.world, 3.0)
        if Art.valid(ring) and material and material.set_render_type then material.set_render_type(ring, "alpha_blend") end
        self.seed_mine_pool[i] = { ring = ring, core = core }
    end
end

function Duel:park_boss_arc()
    for _, node in ipairs(self.boss_arc_nodes or {}) do
        if Art.valid(node) then node:set_position(vec3(-1000.0, 0.045, -1000.0)) end
    end
end

function Duel:clear_boss_hazards()
    BossSkills.clear(self)
    for _, furrow in ipairs(self.furrows or {}) do
        if Art.valid(furrow.node) then furrow.node:set_position(vec3(-1000.0, 0.025, -1000.0)) end
        if furrow.node and self.furrow_pool then self.furrow_pool[#self.furrow_pool + 1] = furrow.node end
    end
    self.furrows = {}
    for _, bomb in ipairs(self.furrow_bombs or {}) do
        local nodes = bomb.nodes
        if nodes then
            if Art.valid(nodes.ring) then nodes.ring:set_position(vec3(-1000.0, 0.055, -1000.0)) end
            if Art.valid(nodes.core) then nodes.core:set_position(vec3(-1000.0, 0.42, -1000.0)) end
            if self.furrow_bomb_pool then self.furrow_bomb_pool[#self.furrow_bomb_pool + 1] = nodes end
        end
    end
    self.furrow_bombs = {}
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
    self:park_boss_arc()
    self:clear_boss_hazards()
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
    if not self.manual_hero or (self.state ~= "combat" and self.state ~= "loot") then self._stick = nil; return end
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

    hero.flask_lock_t = math.max(0.0, (hero.flask_lock_t or 0.0) - dt)
    hero.retaliate_cd = math.max(0.0, (hero.retaliate_cd or 0.0) - dt)
    hero.frenzy_t = math.max(0.0, (hero.frenzy_t or 0.0) - dt)
    if hero.frenzy_t <= 0.0 and (hero.frenzy_stacks or 0) > 0 then
        local ffx = hero.frenzy_fx
        if ffx and ffx.relentless then
            -- Relentless mutation: stacks bleed off one per second, not all at once.
            hero.frenzy_stacks = hero.frenzy_stacks - 1
            if hero.frenzy_stacks > 0 then
                hero.frenzy_t = 1.0
                hero.frenzy_dmg = hero.frenzy_stacks * (ffx.dmg_per_stack or 0.01)
                hero.frenzy_as = hero.frenzy_stacks * (ffx.as_per_stack or 0.01)
                hero.frenzy_move = hero.frenzy_stacks * (ffx.move_per_stack or 0.01)
            else
                hero.frenzy_stacks, hero.frenzy_dmg, hero.frenzy_as, hero.frenzy_move = nil, nil, nil, nil
            end
        else
            hero.frenzy_stacks, hero.frenzy_dmg, hero.frenzy_as, hero.frenzy_move = nil, nil, nil, nil
        end
    end
    hero.skill_guard_t = math.max(0.0, (hero.skill_guard_t or 0.0) - dt)
    hero.preservation_t = math.max(0.0, (hero.preservation_t or 0.0) - dt)
    hero.symbols_t = math.max(0.0, (hero.symbols_t or 0.0) - dt)
    hero.fleet_t = math.max(0.0, (hero.fleet_t or 0.0) - dt)
    -- Capped rider-heal budget window (techniques): resets once per second.
    hero.capped_heal_win = (hero.capped_heal_win or 0.0) + dt
    if hero.capped_heal_win >= 1.0 then
        hero.capped_heal_win, hero.capped_heal_used = 0.0, 0.0
    end
    if hero.retaliate_pending then
        hero.retaliate_pending = nil
        self:hero_burst(3.6, hero.dps * (hero.retaliation_orbit or 0.0), { 1.0, 0.68, 0.25 })
    end
    if (hero.flask_drink_t or 0.0) > 0.0 then
        hero.flask_drink_t = hero.flask_drink_t - dt
        if hero.flask_drink_t <= 0.0 then self:finish_flask() end
    end

    if hero.regen > 0.0 then hero.hp = math.min(hero.hp_max, hero.hp + hero.regen * dt) end
    if (hero.hp_regen_pct or 0.0) > 0.0 then
        hero.hp = math.min(hero.hp_max, hero.hp + hero.hp_max * hero.hp_regen_pct * dt)
    end
    local pres_fx = self.hero_class == "warrior"
        and (hero.spec_fx or {}).preservation or nil
    if pres_fx and (pres_fx.points or 0) > 0 and hero.preservation_t > 0.0 then
        local seconds = (pres_fx.heal_seconds or 5.0) + (pres_fx.long_guard and pres_fx.long_guard.dur or 0.0)
        hero.hp = math.min(hero.hp_max, hero.hp + hero.hp_max * (pres_fx.heal or 0.0) / seconds * dt)
    end
    hero.hit_flash = math.max(0.0, (hero.hit_flash or 0.0) - dt)
    hero.dodge_iframe_t = math.max(0.0, (hero.dodge_iframe_t or 0.0) - dt)
    hero.auto_skill_t = math.max(0.0, (hero.auto_skill_t or 0.0) - dt)

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
            if (hero.flask_drink_t or 0.0) <= 0.0 and hpf < 0.35 then
                self:try_flask()
            end
            -- Dodge the grammar's red telegraphs: an imminent boss-skill payoff
            -- (ground slam / dive strafe / pounce), then an inbound dash or lit fuse.
            if (hero.dodge_charges or 0) > 0 and hero.dodge_t <= 0.0 then
                local hx, hz = BossSkills.dodge_hint(self, hero)
                if hx then self:try_dodge(hx, hz) end
            end
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
            hero.dodge_recharge_t = hero.dodge_recharge_t
                - dt / math.max(1.0, hero.boss_dodge_recharge_mult or 1.0)
            if hero.dodge_recharge_t <= 0.0 then
                hero.dodge_charges = hero.dodge_charges + 1
                hero.dodge_recharge_t = hero.dodge_recharge
            end
        end
        if not console_open then
            if self:key_pressed("Q") then self:try_flask() end
            if self:key_pressed("Space") then self:try_dodge(dirx, dirz) end
        end
        if hero.dodge_t > 0.0 then
            -- Dash overrides steering: a locked line, fixed total distance.
            local step = math.min(dt, hero.dodge_t)
            hero.dodge_t = hero.dodge_t - dt
            self:move_hero(hero, hero.dodge_dx, hero.dodge_dz, hero.dodge_speed or (DODGE_DIST / DODGE_DUR), step)
            local move_speed = hero.speed * (1.0 + self:hero_move_bonus(hero))
            hero.vel_x = hero.dodge_dx * move_speed -- exit the dash at run speed
            hero.vel_z = hero.dodge_dz * move_speed
        else
            -- Smooth the input asymmetrically: starts/turns ease in over ~50 ms,
            -- but releasing the keys bites in ~25 ms — the hero plants almost
            -- (not quite) instantly instead of sliding to a stop.
            local mag = math.sqrt(dirx * dirx + dirz * dirz)
            local tvx, tvz = 0.0, 0.0
            if mag > 0.001 then
                local move_speed = hero.speed * (1.0 + self:hero_move_bonus(hero))
                tvx = dirx / mag * move_speed
                tvz = dirz / mag * move_speed
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
        if (hero.flask_drink_t or 0.0) <= 0.0 then
            if hero.attack_type == "melee" then
                self:hero_attack(hero, dt)
            else
                self:hero_fire(hero, dt)
            end
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
    if (hero.flask_drink_t or 0.0) <= 0.0 then self:hero_whirl(hero, dt) end
    self:update_hero_projectiles(dt)
    self:update_earth_shards(dt)
    self:update_seed_mines(dt)

    -- Self-stagger: a small decaying shove from being bitten / shot, applied after
    -- input so the hit reads but the player stays in control.
    if (hero.knock_x or 0.0) ~= 0.0 or (hero.knock_z or 0.0) ~= 0.0 then
        local A = self.arena
        local minx, maxx, minz, maxz = arena_actor_bounds(A, 0.8)
        local poise = (hero.stagger_resist or 0.0)
            + ((hero.skill_guard_t or 0.0) > 0.0 and (hero.skill_poise or 0.0) or 0.0)
        local stagger_mult = 1.0 - clampn(poise, 0.0, 0.9)
        hero.x = clampn(hero.x + hero.knock_x * dt * stagger_mult, minx, maxx)
        hero.z = clampn(hero.z + hero.knock_z * dt * stagger_mult, minz, maxz)
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
    local def = Creep.archetypes[Creep.resolve_archetype(arch)] or {}
    if self.manual_hero and def.tactical_role and not def.boss then
        local active, count = {}, 0
        for _, c in ipairs(self.creeps) do
            local role = c.alive and c.stats and c.stats.tactical_role
            if role and not active[role] then active[role], count = true, count + 1 end
        end
        if not active[def.tactical_role] and count >= 3 then arch = self:role_archetype("swarm") end
    end
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
            elite = math.random() < (RULES.enemy.elite_base_chance
                + RULES.enemy.elite_wave_chance * (self.wave_index or 1) + (map.elite_bonus or 0.0)
                + (self.elite_wave_bonus or 0.0))
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
    if creep.stats and creep.stats.boss then
        self.boss_creep = creep
        self.boss_spawn_time = self.combat_time
    end
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
        -- keep their authored fixed spawn ring. The Wave Director may pin an
        -- explicit formation point (req.spawn); legacy entries have none.
        local spawn = req.spawn or (self.manual_hero and self:pick_spawn_point())
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
    if self.endless and self.manual_hero and self.state == "combat" then
        local minc = self:minimum_spawn_cost()
        if (self.reserve or 0.0) < minc * 4.0 then
            self.reserve = math.max(self.reserve or 0.0, math.max(minc * 10.0, (self.reserve_start or 200.0) * 0.5))
        end
    elseif self.manual_hero and (self.reserve or 0.0) < self:minimum_spawn_cost() then
        self.spawn_queue = {}
        return
    end
    self.spawn_t = self.spawn_t - dt
    if self.spawn_t <= 0.0 then
        self.spawn_t = self:spawn_interval()
        local queued = self.spawn_queue and #self.spawn_queue or 0
        local pending = self.telegraphs and #self.telegraphs or 0
        local headroom = self:live_cap() - self:count_alive() - pending - queued
        if headroom > 0 then
            if self.wave_dir then
                local ok, err = pcall(self.wave_dir.spawn_tick, self.wave_dir, self, headroom)
                if not ok then
                    self:log("wave director spawn error (legacy drip): " .. tostring(err))
                    self.wave_dir = nil
                    self:spawn_batch(math.min(self:batch_size(), headroom))
                end
            else
                self:spawn_batch(math.min(self:batch_size(), headroom))
            end
        end
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
    local target = math.max(0, math.floor(tonumber(count) or 0))
    local key = Creep.pool_key and Creep.pool_key(arch) or arch
    local n = math.max(0, target - #(Creep.pool[key] or {}))
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

function Duel:warm_sprite_pool(target, order)
    target = math.max(0, math.floor(tonumber(target) or 0))
    if target <= 0 or type(order) ~= "table" or #order == 0 then return end

    local total = 0
    for key, list in pairs(Creep.pool) do
        if type(key) == "string" and key:sub(1, 7) == "sprite:" then total = total + #list end
    end
    local i = 1
    while total < target do
        local arch = order[i]
        local key = Creep.pool_key(arch)
        local before = #(Creep.pool[key] or {})
        self:warm_archetype(arch, before + 1)
        local added = #(Creep.pool[key] or {}) - before
        if added <= 0 then return end
        total = total + added
        i = i % #order + 1
    end
end

function Duel:ensure_combat_pools()
    if not self.manual_hero then return end
    self:ensure_hero_projectiles()
    self:reset_hero_projectiles()
    self:ensure_earth_shards()
    self:reset_earth_shards()
    self:ensure_creep_projectiles()
    self:ensure_telegraph_pool()
    self:ensure_pickup_pools()
    self:reset_pickups()
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

function Duel:update_boss_skill(c, dt, hero, ev)
    if c.stats and c.stats.boss_skill then BossSkills.update(self, c, dt, hero) end
end

function Duel:update_boss_v2(c, dt, hero)
    local spec = c.stats and c.stats.boss_arc
    if not spec then return false end
    if not c.boss_phase2 and c.hp <= c.hp_max * RULES.boss.phase2.hp_fraction then
        c.boss_phase2 = true
        c.stats.speed = c.stats.speed * 1.25
        Anim.play_oneshot(c, "phase2", self.realtime, 0.55)
        self:set_flash("BOSS PHASE II")
        Art.shake(0.45, 0.35)
    end
    if (c.boss_rest_t or 0.0) > 0.0 then
        c.boss_rest_t = c.boss_rest_t - dt
        return true
    end
    if (c.boss_arc_t or 0.0) > 0.0 then
        c.boss_arc_t = c.boss_arc_t - dt
        local base = math.atan(c.boss_arc_dx, c.boss_arc_dz)
        for i, node in ipairs(self.boss_arc_nodes or {}) do
            local ang = base + math.rad(-50.0 + (i - 1) * 25.0)
            local r = spec.radius * 0.62
            if Art.valid(node) then
                node:set_position(vec3(c.x + math.sin(ang) * r, 0.05, c.z + math.cos(ang) * r))
                local pulse = 0.45 + 0.55 * math.abs(math.sin(self.realtime * 14.0))
                material.set(node, "base_color", vec4(1.0, 0.10, 0.06, 0.28 + 0.42 * pulse))
                material.set(node, "emissive", vec3(1.5 * pulse, 0.12, 0.06))
            end
        end
        if c.boss_arc_t <= 0.0 then
            local dx, dz = hero.x - c.x, hero.z - c.z
            local d = math.sqrt(dx * dx + dz * dz)
            local dot = d > 0.001 and (dx / d * c.boss_arc_dx + dz / d * c.boss_arc_dz) or 1.0
            if d <= spec.radius and dot >= math.cos(math.rad(55.0)) then
                self:apply_hero_damage(spec.damage, { source = creep_name(c) .. " (arc)" })
            end
            self:park_boss_arc()
            c.boss_rest_t = spec.rest or 1.2
            Art.burst("ath_boss_arc", vec3(c.x, 0.3, c.z),
                { preset = "enemy_give", count = 30, life_max = 0.4, spawn_radius = spec.radius * 0.6,
                  size_max = 0.28, color_start = vec4(1.0, 0.18, 0.08, 1.0) })
            Art.shake(0.5, 0.35)
        end
        return true
    end
    c.boss_arc_cd = (c.boss_arc_cd or 2.0) - dt
    local dx, dz = hero.x - c.x, hero.z - c.z
    local d = math.sqrt(dx * dx + dz * dz)
    if c.boss_arc_cd <= 0.0 and d <= (spec.range or 8.0) and not c.charge_state then
        c.boss_arc_dx, c.boss_arc_dz = dx / math.max(d, 0.001), dz / math.max(d, 0.001)
        c.boss_arc_t = spec.windup or 0.8
        c.boss_arc_cd = (spec.cooldown or 5.0)
            * (c.boss_phase2 and RULES.boss.phase2.cooldown_mult or 1.0)
        return true
    end
    return false
end

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
    local mage_status_fx_budget = 6
    local survivors = self._creep_survivors or {}
    local incoming = 0.0
    local contact = false
    local contacters = {}
    for _, c in ipairs(self.creeps) do
        if c.on_hit_dots then
            for status, dot in pairs(c.on_hit_dots) do
                if c.alive then
                    dot.t = dot.t - dt
                    dot.tick_t = dot.tick_t - dt
                    if dot.tick_t <= 0.0 then
                        local _, dealt = self:deal_status_damage(c, dot.damage,
                            STATUS_COLOR[status] or STATUS_COLOR.poison, 0.0)
                        if (dot.lifesteal_mult or 0.0) > 0.0 and hero then
                            self:hero_rider_heal(dealt * dot.lifesteal_mult,
                                dot.heal_cap, dot.shield_cap)
                        end
                        dot.tick_t = dot.tick_t + (dot.tick_interval or Balance.on_hit.tick)
                    end
                end
                if dot.t <= 0.0 then c.on_hit_dots[status] = nil end
            end
        end
        if c.on_hit_statuses then
            for status, t in pairs(c.on_hit_statuses) do
                t = math.max(0.0, t - dt)
                c.on_hit_statuses[status] = t > 0.0 and t or nil
            end
        end
        if (c.smoke_t or 0.0) > 0.0 then
            c.smoke_t = math.max(0.0, c.smoke_t - dt)
            if c.smoke_t <= 0.0 then c.smoke_miss = nil end
        end
        if (c.daze_t or 0.0) > 0.0 then
            c.daze_t = math.max(0.0, c.daze_t - dt)
            if c.daze_t <= 0.0 then c.daze_mult = nil end
        end
        if (c.attack_slow_t or 0.0) > 0.0 then
            c.attack_slow_t = math.max(0.0, c.attack_slow_t - dt)
            if c.attack_slow_t <= 0.0 then c.attack_slow_mult = nil end
        end
        if (c.damage_down_t or 0.0) > 0.0 then
            c.damage_down_t = math.max(0.0, c.damage_down_t - dt)
            if c.damage_down_t <= 0.0 then c.damage_mult = nil end
        end
        if c.alive and (c.bleed_t or 0.0) > 0.0 then
            c.bleed_t = c.bleed_t - dt
            c.bleed_tick_t = (c.bleed_tick_t or 0.5) - dt
            if c.bleed_tick_t <= 0.0 then
                local _, _, dealt = self:hit_creep(c, (c.bleed_dps or 0.0) * 0.5)
                self:spawn_damage_number(c.x, c.z, dealt, false,
                    { color = STATUS_COLOR.bleed, jx = -0.4, scale = 1.15 })
                c.bleed_tick_t = c.bleed_tick_t + 0.5
            end
            if c.alive and c.bleed_t <= 0.0 then c.bleed_dps, c.bleed_tick_t = nil, nil end
        end
        if c.alive and (c.burn_t or 0.0) > 0.0 then
            c.burn_t = c.burn_t - dt
            c.burn_tick_t = (c.burn_tick_t or 0.5) - dt
            if c.burn_tick_t <= 0.0 then
                local _, _, dealt = self:hit_creep(c, (c.burn_dps or 0.0) * 0.5)
                self:spawn_damage_number(c.x, c.z, dealt, false,
                    { color = STATUS_COLOR.fire, jx = -1.1, scale = 1.15 })
                c.burn_tick_t = c.burn_tick_t + 0.5
            end
            c.burn_fx_t = (c.burn_fx_t or 0.0) - dt
            if c.alive and c.burn_fx_t <= 0.0 and mage_status_fx_budget > 0 then
                mage_status_fx_budget = mage_status_fx_budget - 1
                c.burn_fx_t = 0.18
                Art.burst("ath_burn_tick_" .. tostring(c.id), vec3(c.x, 0.55, c.z),
                    { preset = "enemy_give", count = 8, life_min = 0.12, life_max = 0.42,
                      spawn_radius = 0.28, noise_strength = 4.0, size_min = 0.04, size_max = 0.15,
                      velocity = vec3(0.0, 2.4, 0.0),
                      color_start = vec4(1.0, 0.68, 0.08, 1.0),
                      color_end = vec4(0.65, 0.02, 0.0, 0.0) })
            end
            if c.alive and c.burn_t <= 0.0 then
                c.burn_dps, c.burn_data, c.burn_tick_t = nil, nil, nil
            end
        end
        if c.alive and (c.poison_t or 0.0) > 0.0 then
            c.poison_t = c.poison_t - dt
            c.poison_tick_t = (c.poison_tick_t or 0.5) - dt
            if c.poison_tick_t <= 0.0 then
                local _, _, dealt = self:hit_creep(c, (c.poison_dps or 0.0) * (c.poison_stacks or 1) * 0.5)
                self:spawn_damage_number(c.x, c.z, dealt, false,
                    { color = STATUS_COLOR.poison, jx = 1.1, scale = 1.15 })
                c.poison_tick_t = c.poison_tick_t + 0.5
            end
            if c.alive and c.poison_t <= 0.0 then
                c.poison_dps, c.poison_stacks, c.poison_tick_t = nil, nil, nil
            end
        end
        if (c.hemorrhage_t or 0.0) > 0.0 then
            c.hemorrhage_t = math.max(0.0, c.hemorrhage_t - dt)
            if c.hemorrhage_t <= 0.0 then c.hemorrhage_hits = nil end
        end
        if (c.spell_slow_t or 0.0) > 0.0 then
            c.spell_slow_t = math.max(0.0, c.spell_slow_t - dt)
            c.ice_fx_t = (c.ice_fx_t or 0.0) - dt
            if c.alive and c.ice_fx_t <= 0.0 and mage_status_fx_budget > 0 then
                mage_status_fx_budget = mage_status_fx_budget - 1
                c.ice_fx_t = 0.18
                Art.burst("ath_chill_tick_" .. tostring(c.id), vec3(c.x, 0.48, c.z),
                    { preset = "hero_take", count = 4, life_min = 0.08, life_max = 0.24,
                      spawn_radius = 0.36, noise_strength = 1.0, size_min = 0.04, size_max = 0.11,
                      velocity = vec3(0.0, 0.7, 0.0),
                      color_start = vec4(0.92, 1.0, 1.0, 1.0),
                      color_end = vec4(0.04, 0.46, 1.0, 0.0) })
            end
            if c.spell_slow_t <= 0.0 then c.spell_slow_mult = nil end
        end
        if (c.armor_debuff_t or 0.0) > 0.0 then
            c.armor_debuff_t = math.max(0.0, c.armor_debuff_t - dt)
            c.geo_fx_t = (c.geo_fx_t or 0.0) - dt
            if c.alive and c.geo_fx_t <= 0.0 and mage_status_fx_budget > 0 then
                mage_status_fx_budget = mage_status_fx_budget - 1
                c.geo_fx_t = 0.22
                Art.burst("ath_geo_tick_" .. tostring(c.id), vec3(c.x, 0.20, c.z),
                    { preset = "enemy_take", count = 4, life_min = 0.14, life_max = 0.32,
                      spawn_radius = 0.34, noise_strength = 1.2, size_min = 0.09, size_max = 0.18,
                      velocity = vec3(0.0, 1.5, 0.0), gravity = vec3(0.0, -6.0, 0.0),
                      color_start = vec4(0.82, 0.52, 0.18, 1.0),
                      color_end = vec4(0.20, 0.07, 0.01, 0.0) })
            end
            if c.armor_debuff_t <= 0.0 then c.armor_reduction = nil end
        end
        if (c.poise_break_t or 0.0) > 0.0 then
            c.poise_break_t = math.max(0.0, c.poise_break_t - dt)
            if c.poise_break_t <= 0.0 then c.poise_reduction = nil end
        end
        if (c.curse_t or 0.0) > 0.0 then
            c.curse_t = math.max(0.0, c.curse_t - dt)
            c.curse_fx_t = (c.curse_fx_t or 0.0) - dt
            if c.alive and c.curse_fx_t <= 0.0 and mage_status_fx_budget > 0 then
                mage_status_fx_budget = mage_status_fx_budget - 1
                c.curse_fx_t = 0.22
                Art.burst("ath_curse_tick_" .. tostring(c.id), vec3(c.x, 0.66, c.z),
                    { preset = "hero_take", count = 4, life_min = 0.10, life_max = 0.30,
                      spawn_radius = 0.30, noise_strength = 1.4, size_min = 0.05, size_max = 0.12,
                      velocity = vec3(0.0, 1.0, 0.0),
                      color_start = vec4(0.72, 0.30, 0.95, 1.0),
                      color_end = vec4(0.22, 0.04, 0.40, 0.0) })
            end
            if c.curse_t <= 0.0 then c.curse_amp = nil end
        end
        if (c.storm_tint_t or 0.0) > 0.0 then
            c.storm_tint_t = math.max(0.0, c.storm_tint_t - dt)
            c.storm_fx_t = (c.storm_fx_t or 0.0) - dt
            if c.alive and c.storm_fx_t <= 0.0 and mage_status_fx_budget > 0 then
                mage_status_fx_budget = mage_status_fx_budget - 1
                c.storm_fx_t = 0.10
                Art.burst("ath_storm_crackle_" .. tostring(c.id), vec3(c.x, 0.70, c.z),
                    { preset = "enemy_take", count = 4, life_min = 0.03, life_max = 0.10,
                      spawn_radius = 0.34, noise_strength = 16.0, size_min = 0.04, size_max = 0.10,
                      color_start = vec4(1.0, 1.0, 1.0, 1.0),
                      color_end = vec4(0.04, 0.30, 1.0, 0.0) })
            end
        end
        if (c.status_flash_t or 0.0) > 0.0 then
            c.status_flash_t = math.max(0.0, c.status_flash_t - dt)
            if c.status_flash_t <= 0.0 then
                c.status_flash_name, c.status_flash_names, c._status_tint_key = nil, nil, nil
            end
        end
        self:update_creep_status_tint(c)
        local frozen = c.alive and (c.freeze_t or 0.0) > 0.0
        if frozen then c.freeze_t = math.max(0.0, c.freeze_t - dt) end
        local ev = nil
        local boss_busy = not frozen and c.alive and self:update_boss_v2(c, dt, hero)
        if c.alive and not frozen and not boss_busy then ev = Creep.update(c, dt, self.field, self.map, hero) end
        if c.alive then self:update_boss_skill(c, dt, hero, ev) end
        self:clamp_creep_to_arena(c)
        if c.hit_flash then c.hit_flash = math.max(0.0, c.hit_flash - dt) end
        if c.armor_broken_t then c.armor_broken_t = math.max(0.0, c.armor_broken_t - dt) end
        if c.bite_cd then c.bite_cd = math.max(0.0, c.bite_cd - dt * (c.attack_slow_mult or 1.0)) end
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
        if c.alive and not hero.dead and not frozen then
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
                    if not self:creep_attack_misses(c)
                        and self:apply_hero_damage((c.stats.dps or 1.0) * (cg.dmg_mult or 1.6)
                            * (c.damage_mult or 1.0),
                        { source = creep_name(c) .. " (charge)" }) then
                        c.charge_state = nil
                        c.charge_cd = (cg.cooldown or 3.0)
                            * (c.boss_phase2 and RULES.boss.phase2.cooldown_mult or 1.0)
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
                        c.bite_windup = c.bite_windup - dt * (c.attack_slow_mult or 1.0)
                        if c.bite_windup <= 0.0 then
                            c.bite_windup = nil
                            c.bite_cd = BITE_COOLDOWN
                            if d <= reach + BITE_GRACE and not self:creep_attack_misses(c)
                                and self:apply_hero_damage((c.stats.dps or 1.0) * (BITE_WINDUP + BITE_COOLDOWN)
                                    * (c.damage_mult or 1.0),
                                    { source = creep_name(c) }) then
                                contact = true
                                contacters[#contacters + 1] = c
                                if (hero.thorns or 0.0) > 0.0
                                    and self:hit_creep(c, hero.thorns * (BITE_WINDUP + BITE_COOLDOWN), nil, nil,
                                        { no_flask_refill = true }) then
                                    c.alive = false
                                end
                            end
                        end
                    elseif d <= reach and (c.bite_cd or 0.0) <= 0.0 and not c.charge_state and not c.fuse_t then
                        c.bite_windup = BITE_WINDUP
                    end
                elseif d <= reach then
                    incoming = incoming + (c.stats.dps or 1.0) * (c.damage_mult or 1.0)
                    contact = true
                    contacters[#contacters + 1] = c
                end
            end
        end
        if c.alive then
            survivors[#survivors + 1] = c
        else
            if (c._mdmg or 0.0) > 0.5 then self:flush_melee_packet(c) end
            self:trigger_on_hit_death(c)
            self:spread_burn(c)
            local s = c.stats or {}
            local col = c._status_tint_color or s.color or { 0.9, 0.5, 0.3 }
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
            if self.manual_hero and c._hero_killed then
                -- Vampiric Surge proc: each kill restores health with a green
                -- heal popup from the damage-number pool.
                if hero and not hero.dead and hero.vampiric_surge then
                    local heal = hero.vampiric_surge.heal or 5.0
                    if hero.hp < hero.hp_max then
                        self:hero_rider_heal(heal)
                        self:spawn_damage_number(hero.x, hero.z, 0, false,
                            { text = "+" .. math.floor(heal + 0.5), color = { 0.42, 0.86, 0.52 } })
                    end
                end
                if c.elite and not self.essence_dropped and self:flask_total() < FLASK_CHARGES then
                    self.essence_dropped = true
                    self:spawn_essence(c.x, c.z)
                end
                -- Tree kill hooks: kill heals + Bladestorm's bleed refresh.
                local hero_fx = (hero and hero.spec_fx) or {}
                for _, spec in ipairs((self:active_class() or {}).specializations or {}) do
                    local fx = hero_fx[spec.id]
                    if fx and (fx.points or 0) > 0 then
                        if fx.kill_heal then
                            self:hero_rider_heal(hero.hp_max * (fx.kill_heal.heal or 0.005),
                                fx.kill_heal.cap or 0.02)
                        end
                        if fx.soul_harvest then
                            self:hero_rider_heal(hero.hp_max * (fx.soul_harvest.heal or 0.005),
                                fx.soul_harvest.cap or 0.02)
                        end
                        if fx.kill_heal_max
                            and (hero.frenzy_stacks or 0) >= (fx.max_stacks or 5) then
                            self:hero_rider_heal(hero.hp_max * (fx.kill_heal_max.heal or 0.01),
                                fx.kill_heal_max.cap or 0.03)
                        end
                        local cap = fx.capstone
                        if cap and cap.kind == "refresh_on_kill" and spec.kind == "stack_dot"
                            and ((c.on_hit_stacks or {})[spec.status] or 0) > 0 then
                            -- Bladestorm: a bleeding kill smears a stack onto
                            -- everything in cleave range.
                            local hd = hero.last_rider_hit or 0.0
                            if hd > 0.0 then
                                local r2 = (cap.params.radius or 5.0) ^ 2
                                for _, o in ipairs(self.creeps) do
                                    if o.alive and o ~= c then
                                        local dx, dz = o.x - c.x, o.z - c.z
                                        if dx * dx + dz * dz <= r2 then
                                            o.on_hit_stacks = o.on_hit_stacks or {}
                                            local st = math.min(fx.max_stacks or 5,
                                                (o.on_hit_stacks[spec.status] or 0) + 1)
                                            o.on_hit_stacks[spec.status] = st
                                            local amount = hd * st * (fx.stack_per or 0.20)
                                            self:apply_on_hit_dot(o, spec.status, 0.0, amount, false, false)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if self.boss_creep == c then
                self.boss_creep = nil
                self:park_boss_arc()
                self:clear_boss_hazards()
                -- Hero Grid economy: points land per wave clear and at boss
                -- entry (see award_spec_points); the kill itself pays in loot.
                local title = self:active_map().boss_title or self.config.boss_title
                local I18n = _G.ATH_I18N
                local tname = (I18n and title and I18n.t(title)) or title
                local flash = (tname and ((I18n and I18n.t("THE %s FALLS", tname)) or ("THE " .. tname .. " FALLS"))) or "CHAMPION DOWN"
                self:set_flash(flash)
                self:save_profile()
                self:log(string.format("boss down seconds=%.1f skill_points=%d",
                    self.combat_time - (self.boss_spawn_time or self.combat_time), self.skill_points))
            end
            self:begin_death_anim(c) -- defers Creep.destroy by a spin-out beat
            self.kills = self.kills + 1
            self:maybe_drop_manual_gear(c)
        end
    end
    local previous = self.creeps
    self.creeps = survivors
    for i = #previous, 1, -1 do previous[i] = nil end
    self._creep_survivors = previous

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
                if self:hit_creep(c, hero.thorns * dt, nil, nil, { no_flask_refill = true }) then c.alive = false end
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
    if self.invulnerable then return false end
    opts = opts or {}
    -- Dodge i-frames: every damage source funnels through here, so immunity
    -- lives here and never on individual enemies.
    if (hero.dodge_iframe_t or 0.0) > 0.0 then return false end
    local mitig = opts.ignore_armor and 1.0
        or (1.0 - clampn((hero.armor or 0.0) + (hero.boss_armor_bonus or 0.0), -0.5, 0.85))
    if (hero.dodge_t or 0.0) > 0.0 then
        mitig = mitig * (1.0 - clampn(hero.dodge_guard or 0.0, 0.0, 0.9))
    end
    -- Vanguard's post-slam guard window stacks multiplicatively with armor.
    if (hero.skill_guard_t or 0.0) > 0.0 then
        mitig = mitig * (1.0 - clampn(hero.skill_guard or 0.0, 0.0, 0.9))
    end
    local pres_fx = self.hero_class == "warrior"
        and (hero.spec_fx or {}).preservation or nil
    if pres_fx and (pres_fx.points or 0) > 0 then
        local seconds = (pres_fx.heal_seconds or 5.0)
            + (pres_fx.long_guard and pres_fx.long_guard.dur or 0.0)
        hero.preservation_t = seconds
        mitig = mitig * (1.0 - math.min(0.60, pres_fx.dr or 0.0))
    end
    -- Tree techniques: Iron Fury (max frenzy stacks) and Bone Armor (per minion).
    local sfx = hero.spec_fx or {}
    for _, fx in pairs(sfx) do
        if fx.dr_at_max and (hero.frenzy_stacks or 0) >= (fx.max_stacks or 5) then
            mitig = mitig * (1.0 - (fx.dr_at_max.dr or 0.08))
        end
        if fx.bone_armor then
            local dr = math.min(fx.bone_armor.cap or 0.06,
                (fx.bone_armor.dr or 0.01) * self:count_minions("skeleton"))
            if dr > 0.0 then mitig = mitig * (1.0 - dr) end
        end
    end
    if (hero.flask_drink_t or 0.0) > 0.0
        and amount * mitig >= hero.hp_max * RULES.flask.interrupt_hp_fraction then
        hero.flask_drink_t = 0.0
        hero.flask_lock_t = FLASK_LOCK_T
        self:set_flash("DRINK INTERRUPTED")
    end
    if (hero.retaliation_orbit or 0.0) > 0.0 and (hero.retaliate_cd or 0.0) <= 0.0 then
        hero.retaliate_pending = true
        hero.retaliate_cd = 0.5
    end
    local taken = amount * mitig
    -- Sanguine Ward: the overheal shield soaks before health.
    if (hero.shield or 0.0) > 0.0 then
        local soaked = math.min(hero.shield, taken)
        hero.shield = hero.shield - soaked
        taken = taken - soaked
    end
    hero.hp = hero.hp - taken
    -- Last Stand: once per map, a lethal hit leaves the warrior standing.
    if hero.hp <= 0.0 and not self._guardian_used then
        local pfx = (hero.spec_fx or {}).preservation
        local cap = pfx and pfx.capstone
        if cap and cap.kind == "guardian" then
            self._guardian_used = true
            hero.hp = hero.hp_max * (cap.params.heal or 0.20)
            hero.dodge_iframe_t = math.max(hero.dodge_iframe_t or 0.0, cap.params.immune or 2.0)
            self:set_flash("LAST STAND")
            Art.shake(0.5, 0.4)
        end
    end
    hero.hit_flash = HIT_FLASH_T
    BossSkills.on_hero_damage(self, taken)
    -- Death recap: a 3-entry ring buffer of the last hits (newest last).
    if self.manual_hero then
        local log = self.dmg_log or {}
        self.dmg_log = log
        log[#log + 1] = { src = opts.source or "the swarm", dmg = taken, t = self.realtime }
        if #log > 3 then table.remove(log, 1) end
    end
    -- Hurt vignette pulse (drawn by update_hud) + a jolt on meaty single hits.
    self._hurt_t = 0.25
    if taken >= 14.0 then Art.shake(0.10, 0.12) end
    if hero.hp <= 0.0 then
        hero.hp = 0.0
        hero.dead = true
        self:park_all_minions()
        self.death_time = self.realtime
        self:haptic(45)
        self.state = "slain"
        self:remember_map_wave() -- retry the wave that killed you
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

function Duel:finish_class_pick()
    -- Menu already picked the hero — land in town/gear hub. World map is opt-in
    -- via EXIT TO MAP (not forced after class pick).
    self:enter_town()
    if self.autoplay then self:start_map() end
end

function Duel:choose_specialization(index)
    local class = self:active_class()
    local specs = class and class.specializations or {}
    if not specs[index] then return end
    self.specialization = specs[index].id
    self:finish_class_pick()
end

-- keep_store: re-entering town from the world map must not reroll the shop
-- (restock is once per real town visit, not a free reroll).
function Duel:enter_town(keep_store)
    self.state = "town"
    self.endless = false
    self._between_wave = false
    self._hub_tab = "map"
    self.draft_offer = nil
    self:recompute_hero_stats()
    if self.hero and not keep_store then
        self.hero.flask_health = FLASK_CHARGES
        self.hero.flask_charges = FLASK_CHARGES
    end
    if not keep_store then self:restock_store() end
    self:save_profile()
    Inventory.show(self)
    self:set_flash("TOWN")
    self:apply_map_floor() -- town previews the destination's ground
end

-- World map — a painted overworld shown before the run; pick where to hunt.
function Duel:enter_worldmap()
    self._wm_from_town = self.state == "town"
    self.state = "worldmap"
    Inventory.hide(self)
    self:set_flash("WORLD MAP")
end

-- Hub "EXIT TO MAP": open the world map. From town that's just the picker;
-- mid-run soft-resets the dungeon first (no destination re-pick without leaving).
function Duel:exit_to_worldmap()
    if not self.manual_hero then return end
    if self.state == "worldmap" then return end
    if self.state == "town" then
        self:enter_worldmap()
        return
    end
    if self.state == "combat" or self.state == "pause" or self.state == "loot" or self.state == "draft" or self.state == "specpick" then
        Inventory.hide(self)
        self:remember_map_wave()
        self:save_profile()
        if self.state == "loot" or self.state == "combat" or self.state == "pause" then
            self:vacuum_pickups()
        end
        self:reset_run(true)
        self:enter_worldmap()
    end
end

-- Swap the stage floor to the active map's themed ground (config.maps[i].floor).
-- Works on both stage paths: the authored game.pescene floor and the transient
-- Duel-built one are both named "Floor". Missing floor field = keep the default.
function Duel:apply_map_floor()
    local map = self:active_map()
    local path = map.floor or (self.theme and self.theme.floor_texture)
    if not path or self._floor_tex == path then return end
    if self.realtime <= 0.0 then
        self._floor_tex_pending = true
        return
    end
    local node = scene.find_model and scene.find_model("Floor")
    if not Art.valid(node) then return end
    -- Preserve the original manifest's tint; skins own their color palette and
    -- must not inherit the authored floor's green emissive wash.
    if map.floor and material and material.set then
        local t = Visuals.name == "default" and map.id == "spud_fields" and self.theme and self.theme.floor
        if Visuals.name ~= "default" then
            material.set(node, "base_color", vec4(1.0, 1.0, 1.0, 1.0))
            material.set(node, "emissive", vec3(0.0, 0.0, 0.0))
        elseif t then
            material.set(node, "base_color", vec4(t[1], t[2], t[3], 1.0))
        else
            material.set(node, "base_color", vec4(0.80, 0.80, 0.80, 1.0))
        end
    end
    if Art.texture(node, path) then self._floor_tex = path end
end

function Duel:start_map()
    if self.state ~= "town" then return end
    self.endless = false
    self._guardian_used = nil -- Last Stand recharges per map
    -- ATH_DUEL_MAP pins the map for smokes/tuning (bypasses the unlock gate).
    local env_map = ATH_COMMON.getenv_number("ATH_DUEL_MAP", nil)
    if self.boss_tour and not self.boss_tour_started and #self.maps > 0 then
        self.map_index = clampn(math.floor(env_map or 1), 1, #self.maps)
        self.boss_tour_started = true
    elseif env_map and not self.boss_tour and #self.maps > 0 then
        self.map_index = clampn(math.floor(env_map), 1, #self.maps)
    end
    local map = self:active_map()
    if map.waves then self.wave_cfg.count = map.waves end
    self:apply_map_floor()
    self.draft_offer = nil
    self._between_wave = false
    self:recompute_hero_stats()
    Inventory.hide(self)
    if map.name then
        self:log(string.format("map start map=%d id=%s waves=%d", self.map_index, tostring(map.id), self.wave_cfg.count or 5))
    end
    local env_wave = ATH_COMMON.getenv_number("ATH_DUEL_WAVE", nil)
    local start_wave = self.boss_tour and self:total_rounds()
        or env_wave or self:next_wave_for_map(self.map_index)
    start_wave = math.max(1, math.min(math.floor(start_wave), self:total_rounds()))
    if self.boss_tour and map.boss then self:warm_archetype(map.boss, 1) end
    self:begin_manual_wave(start_wave)
end

function Duel:choose_class(index)
    local list = self.config.hero and self.config.hero.classes
    if not (list and list[index]) then return end
    self.hero_class = list[index].id
    self.hero_class_index = index
    _G.ATH_RUN = _G.ATH_RUN or {}
    _G.ATH_RUN.hero_index = index
    -- Rebuild the hero with the picked class's sprite + stats. Parked creep NodeIds
    -- survive the scene's swap-and-pop relocation, so keep the warm pool intact.
    local rebuild_hero = Art.valid(self.hero and self.hero.root) and not (self.hero and self.hero.adopted)
    self:park_all_minions()
    -- Never delete an ADOPTED hero (authored scene node): create_hero re-finds and
    -- re-drives the same node; deleting it would remove it from the scene for good.
    if rebuild_hero then
        scene.delete_node(self.hero.root)
    end
    self:create_hero()
    -- Keep profile draft picks across the menu→game choose_class rebuild.
    local keep_cards = self._saved_run_card_ids ~= nil
    self:reset_manual_gear(keep_cards)
    self._saved_run_card_ids = nil
    self:ensure_combat_pools()
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
    local specs = list[index].specializations or {}
    local requested = ATH_COMMON.getenv("ATH_HERO_SPEC", nil)
    self.specialization_preference = requested
    if list[index].progressive_specializations then
        self.specialization = nil
        self:finish_class_pick()
        return
    end
    local picked = specs[1]
    for _, spec in ipairs(specs) do
        if spec.id == requested then picked = spec; break end
    end
    self.specialization = picked and picked.id or nil
    if #specs > 1 and not self.autoplay and not requested then
        self.state = "specpick"
        self:set_flash("CHOOSE SPECIALIZATION")
        return
    end
    self:finish_class_pick()
end

function Duel:begin_manual_wave(index)
    self.wave_index = math.max(1, math.floor(index or 1))
    self.round = self.wave_index
    -- Boss round: no trash budget — the boss telegraphs as soon as combat opens
    -- (the wave-done check sees an empty field and fires the rise).
    local boss_round = self.wave_index > (self.wave_cfg.count or 5)
    self.reserve_start = boss_round and 0.0 or self:manual_wave_budget(self.wave_index)
    self.reserve = self.reserve_start
    self.round_t = 0.0
    self.spawn_t = 0.35
    self.spawn_queue = {}
    self:clear_seed_mines()
    self.essence_dropped = false
    self:clear_telegraphs()
    self:reset_creep_projectiles()
    self:reset_hero_projectiles()
    self:reset_earth_shards()
    -- Fresh wave: dodge back to full, stale death-recap entries dropped.
    self.dmg_log = nil
    local hero = self.hero
    if hero then
        hero.rage_hit_gain = 0.0
        hero.frenzy_t, hero.skill_guard_t = 0.0, 0.0
        hero.frenzy_stacks, hero.frenzy_dmg, hero.frenzy_as, hero.frenzy_move = nil, nil, nil, nil
        hero.symbols_t, hero.fleet_t, hero.shield = 0.0, 0.0, 0.0
        hero.cap_counts, hero.cap_icd, hero.det_t = nil, nil, nil
        hero.flask_drink_t, hero.flask_lock_t = 0.0, 0.0
        hero.dodge_charges = hero.dodge_charges_max or 1
        hero.dodge_recharge_t = hero.dodge_recharge or DODGE_RECHARGE
        hero.dodge_t = 0.0
        hero.dodge_iframe_t = 0.0
    end
    self:park_all_minions()
    -- Necromancer pool is built here — a menu beat, never mid-combat (the same
    -- frame-spike rule the creep prewarm follows).
    if self.hero_class == "necromancer" then self:ensure_minion_pool() end
    -- Round draft is gone: strip non-skill cards each wave (round rewards TBD).
    -- Spec ranks live in the Skills hub and persist via specialization run_cards.
    if self.manual_hero then
        local kept = {}
        for _, card in ipairs(self.run_cards or {}) do
            -- Spec ranks persist via the Skills hub; run-scoped proc boons persist
            -- for the whole run (reset only in reset_manual_gear).
            if card and (card.specialization or card.boon) then kept[#kept + 1] = card end
        end
        self.run_cards = kept
        self.draft_offer = nil
        self:recompute_hero_stats()
    end
    self.state = "combat"
    self:set_flash("WAVE %d", self.wave_index)
    self:log(string.format("wave start wave=%d budget=%.0f", self.wave_index, self.reserve_start))

    -- Wave Director (Phase 1): scripted composition/formation + one seeded
    -- mutator per wave. Nil-gated on config.wave_scripts so every unscripted
    -- config stays byte-identical; boss rounds always fall through to the legacy
    -- flat drip. The per-wave mutator knobs are reset EVERY wave (incl. boss
    -- rounds) so nothing bleeds past its wave; wave_scripts.begin re-applies the
    -- active ones. A begin/tick error drops back to the legacy drip (one log).
    self.wave_dir = nil
    if self.config.wave_scripts and self.manual_hero then
        self.elite_wave_bonus, self.drop_every_mult = nil, nil
        self.coin_gold_mult, self.wave_drop_floor = nil, nil
        self.buffs.speed, self.buffs.power, self.buffs.hp = 0.0, 0.0, 0.0
        if not boss_round then
            local ok, dir = pcall(self.config.wave_scripts.begin, self, self.wave_index)
            if ok then
                self.wave_dir = dir
            else
                self:log("wave director init error (legacy drip): " .. tostring(dir))
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Legacy wave draft helpers (unused in manual arena — Skills hub owns specs).
-- Spec breadth cap: a run invests in at most TWO of the three class
-- specializations. Riders cost nothing per attack; giving up the third spec IS
-- the cost. The third locks out once two hold ranks.
-- ---------------------------------------------------------------------------
function Duel:spec_card_allowed(card)
    if not card.specialization then return true end
    -- Tree cards route through the node gate.
    if card.tree_node then
        return (self:tree_node_allowed(card.specialization, card.tree_node))
    end
    local ranks = (self.hero and self.hero.specialization_ranks) or {}
    local rank = ranks[card.specialization] or 0
    if rank > 0 then return rank < (card.max_rank or 5) end -- keep ranking an owned spec
    local owned = 0
    for _, r in pairs(ranks) do
        if r > 0 then owned = owned + 1 end
    end
    return owned < 2
end

-- The active class's tree allocations ({spec_id = {node_id = rank}}).
function Duel:class_tree_nodes()
    return ((self.hero and self.hero.tree_nodes) or {})[self.hero_class] or {}
end

-- Points currently allocated in one spec tree.
function Duel:tree_points(spec_id)
    local t = self:class_tree_nodes()[spec_id]
    local points = 0
    for _, r in pairs(t or {}) do points = points + r end
    return points
end

-- Hero Grid gate: 9-point primary (capstone), 5-point secondary (unlocks once
-- the primary holds 5), third tree locked while two hold points.
function Duel:tree_node_allowed(spec_id, node_id)
    local hero = self.hero
    if not hero then return false, "No hero." end
    local tree = Balance.spec_tree(self.hero_class, spec_id)
    local node = tree and tree.by_id[node_id]
    if not node then return false, "Unknown node." end
    local allocs = self:class_tree_nodes()
    local mine = allocs[spec_id] or {}
    if (mine[node_id] or 0) >= node.max_rank then return false, "Maxed." end
    if node.choice then
        local twin = node_id == "ma" and "mb" or "ma"
        if (mine[twin] or 0) > 0 then return false, "Other mutation active." end
    end
    local points = self:tree_points(spec_id)
    if points < (node.gate or 0) then
        return false, string.format("Needs %d points here.", node.gate or 0)
    end
    local rules = Balance.tree_rules
    local primary = hero.primary_spec
    if primary and primary ~= spec_id then
        if points == 0 then
            local owned = 0
            for sid in pairs(allocs) do
                if self:tree_points(sid) > 0 then owned = owned + 1 end
            end
            if owned >= 2 then return false, "Two trees already chosen." end
            if self:tree_points(primary) < rules.secondary_unlock then
                return false, string.format("Primary needs %d points first.", rules.secondary_unlock)
            end
        end
        if points >= rules.secondary_cap then return false, "Secondary cap (5)." end
        if node.primary_only then return false, "Primary tree only." end
    else
        if points >= rules.primary_cap then return false, "Tree complete." end
    end
    return true
end

-- Post-refund legality: an allocation is legal iff it can be rebuilt by
-- adding points in ascending gate order (gates count total points in the
-- tree, WoW-style), the keystone anchors any invested tree, mutations stay
-- exclusive, and caps hold.
function Duel:tree_alloc_legal(allocs, primary)
    local rules = Balance.tree_rules
    local owned, primary_points, secondary_invested = 0, 0, false
    for spec_id, mine in pairs(allocs or {}) do
        local points = 0
        for _, r in pairs(mine) do points = points + r end
        if points > 0 then
            owned = owned + 1
            local tree = Balance.spec_tree(self.hero_class, spec_id)
            if not tree then return false end
            if (mine.key or 0) < 1 then return false end
            if (mine.ma or 0) > 0 and (mine.mb or 0) > 0 then return false end
            local is_primary = primary == spec_id
            if is_primary then primary_points = points else secondary_invested = true end
            if points > (is_primary and rules.primary_cap or rules.secondary_cap) then return false end
            if not is_primary and (mine.cap or 0) > 0 then return false end
            local cum = 0
            for _, node in ipairs(tree.nodes) do -- nodes are gate-ordered
                local r = mine[node.id] or 0
                if r > 0 then
                    if r > node.max_rank then return false end
                    if cum < (node.gate or 0) then return false end
                    cum = cum + r
                end
            end
        end
    end
    return owned <= 2 and (not secondary_invested or primary_points >= rules.secondary_unlock)
end

function Duel:begin_draft(catalog, guaranteed)
    self:clear_damage_numbers()
    local picks = {}
    for _, card in ipairs(guaranteed or {}) do
        if self:spec_card_allowed(card) then picks[#picks + 1] = card end
    end
    for _, card in ipairs(catalog or {}) do picks[#picks + 1] = card end
    if #picks == 0 then
        self.state = "combat"
        self:set_flash("WAVE %d", self.wave_index)
        return
    end
    self.draft_offer = picks
    self.state = "draft"
    self:set_flash("WAVE %d - CHOOSE A CARD", self.wave_index)
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
    self:set_flash("%s - WAVE %d", T(tostring(card.name)), self.wave_index)
    self:haptic(12)
    self:save_profile()
    self:log(string.format("draft pick wave=%d card=%s", self.wave_index or 1, tostring(card.id)))
end

-- Spend one skill point into a spec-tree node (Skills hub tree).
-- Gates, mutation exclusivity, and the 9/5 primary/secondary caps live in
-- tree_node_allowed.
function Duel:allocate_skill(spec_id, node_id)
    if not self.manual_hero or not spec_id then return false, "No skill." end
    node_id = node_id or "key"
    if (self.skill_points or 0) < 1 then return false, "No skill points." end
    local ok, why = self:tree_node_allowed(spec_id, node_id)
    if not ok then return false, why or "Locked." end
    local card = Balance.tree_card(self.hero_class, spec_id, node_id)
    if not card then return false, "Unknown skill." end
    self.skill_points = (self.skill_points or 0) - 1
    self.run_cards = self.run_cards or {}
    self.run_cards[#self.run_cards + 1] = card
    self:recompute_hero_stats()
    self:save_profile()
    self:haptic(12)
    self:log(string.format("skill allocate spec=%s node=%s points_left=%d",
        tostring(spec_id), tostring(node_id), self.skill_points or 0))
    return true, card.name
end

-- Refund one rank from a tree node (Skills hub right-click). Refuses refunds
-- that would leave the remaining allocation unbuildable (gate/keystone/choice
-- integrity) — refund higher tiers first. Fully unwinding a tree is always
-- reachable in reverse order, so respec stays free.
function Duel:deallocate_skill(spec_id, node_id)
    if not self.manual_hero or not spec_id then return false, "No skill." end
    node_id = node_id or "key"
    local cards = self.run_cards or {}
    for i = #cards, 1, -1 do
        local c = cards[i]
        local tn = c and c.effect and c.effect.tree_node
        if tn and tn.spec == spec_id and tn.node == node_id
            and (tn.class or self.hero_class) == self.hero_class then
            -- Simulate the refund before committing it.
            local trial = {}
            for sid, t in pairs(self:class_tree_nodes()) do
                local copy = {}
                for nid, r in pairs(t) do copy[nid] = r end
                trial[sid] = copy
            end
            local mine = trial[spec_id]
            if not mine or (mine[node_id] or 0) < 1 then return false, "Nothing to remove." end
            mine[node_id] = mine[node_id] - 1
            if mine[node_id] <= 0 then mine[node_id] = nil end
            local primary = self.hero.primary_spec
            local points_left = 0
            for _, r in pairs(mine) do points_left = points_left + r end
            if points_left == 0 then
                trial[spec_id] = nil
                if primary == spec_id then
                    -- Primary fully unwound: the other invested tree (if any)
                    -- inherits primary by card order.
                    primary = nil
                    for _, rc in ipairs(cards) do
                        local rtn = rc.effect and rc.effect.tree_node
                        if rtn and (rtn.class or self.hero_class) == self.hero_class
                            and rtn.spec ~= spec_id and trial[rtn.spec] then
                            primary = rtn.spec
                            break
                        end
                    end
                end
            end
            if not self:tree_alloc_legal(trial, primary) then
                return false, "Refund higher tiers first."
            end
            table.remove(cards, i)
            self.skill_points = (self.skill_points or 0) + 1
            self:recompute_hero_stats()
            self:save_profile()
            self:haptic(8)
            self:log(string.format("skill deallocate spec=%s node=%s points_left=%d",
                tostring(spec_id), tostring(node_id), self.skill_points or 0))
            return true
        end
    end
    return false, "Nothing to remove."
end

function Duel:manual_wave_done()
    if self.endless then return false end
    return (self.reserve or 0.0) < self:minimum_spawn_cost()
        and (not self.spawn_queue or #self.spawn_queue == 0)
        and (not self.telegraphs or #self.telegraphs == 0)
        and self:count_alive() == 0
end

-- Kills drop PHYSICAL loot at the corpse: gold coins always (heftier enemies
-- shower more), an item beacon on the drop cadence, an occasional elite piece,
-- and a two-piece shower from the boss one rarity tier above the map's drops.
function Duel:maybe_drop_manual_gear(c)
    if not self.manual_hero then return end
    local s = (c and c.stats) or {}
    local x = (c and c.x) or (self.hero and self.hero.x) or 0.0
    local z = (c and c.z) or (self.hero and self.hero.z) or 0.0
    local cost = s.threat_cost or 1
    -- Gold scales steeply with map rank (deep maps are the income; wave-one
    -- suicide farming on map I stays poor).
    local gold_mult = self:active_map().gold_mult or 1.0
    local base_gold = math.max(1, math.floor((self.gear_cfg.gold_per_kill or 1) * gold_mult
        * (self.coin_gold_mult or 1.0) + 0.5))
    local coins = 1
    if s.boss then coins = 7 elseif c and c.elite then coins = 4 elseif cost >= TELEGRAPH_BIG_COST then coins = 2 end
    for _ = 1, coins do
        self:spawn_coin(x, z, base_gold * (cost >= TELEGRAPH_BIG_COST and 2 or 1))
    end

    local items = self.gear_cfg.items or {}
    if #items == 0 then return end
    -- Drops roll rarity-weighted by the active map (deeper = shinier).
    if s.boss then
        local up = self:boss_drop_weights()
        local a = Duel.scale_item_stats(self:roll_drop_item(items, nil, up), 1.10)
        local b = Duel.scale_item_stats(self:roll_drop_item(items, nil, up), 1.10)
        self:spawn_item_beacon(x - 0.9, z, a)
        self:spawn_item_beacon(x + 0.9, z, b)
        -- Boss guarantees a boon beacon (if the hero lacks any); else just gear.
        local boon = self:eligible_boon()
        if boon then self:spawn_boon_beacon(x, z + 1.3, boon) end
        return
    end
    if c and c.elite then
        -- Elites roll a modest chance for a BOON beacon (unowned boons only),
        -- independent of the gear roll and wave_drop_floor; else the normal drop.
        if math.random() < (RULES.economy.boon_elite_chance or 0.12) then
            local boon = self:eligible_boon()
            if boon then self:spawn_boon_beacon(x, z, boon); return end
        end
        if math.random() <= 0.20 then self:spawn_item_beacon(x, z, self:roll_drop_item(items, self.wave_drop_floor)) end
        return
    end
    local every = math.max(1, math.floor((self.gear_cfg.drop_every or 6) * (self.drop_every_mult or 1.0)))
    if (self.kills % every) ~= 0 then return end
    self:spawn_item_beacon(x, z, self:roll_drop_item(items, self.wave_drop_floor))
end

-- Percentage (+X%) bonuses are additive from BASE, never compounded on current:
-- +10% then +5% then +10% => base * 1.25 (not 1.10*1.05*1.10).
-- `ref` holds the naked/class baselines (and post-load dodge_recharge).
local function apply_gear_effect(hero, effect, ref)
    if not effect then return end
    ref = ref or hero
    if effect.dps_mult then
        hero.dps = hero.dps + (ref.dps or 0.0) * (effect.dps_mult - 1.0)
    end
    if effect.dps_add then hero.dps = hero.dps + effect.dps_add end
    if effect.cleave_add then hero.cleave = hero.cleave + effect.cleave_add end
    if effect.attack_range_add then hero.attack_range = hero.attack_range + effect.attack_range_add end
    if effect.speed_mult then
        hero.speed = hero.speed + (ref.speed or 0.0) * (effect.speed_mult - 1.0)
    end
    if effect.kite_speed_mult then
        hero.kite_speed = hero.kite_speed + (ref.kite_speed or ref.speed or 0.0) * (effect.kite_speed_mult - 1.0)
    end
    if effect.hp_max_add then hero.hp_max = hero.hp_max + effect.hp_max_add end
    if effect.armor_add then hero.armor = clampn((hero.armor or 0.0) + effect.armor_add, -0.5, 0.85) end
    if effect.lifesteal_add then hero.lifesteal = (hero.lifesteal or 0.0) + effect.lifesteal_add end
    if effect.regen_add then hero.regen = (hero.regen or 0.0) + effect.regen_add end
    if effect.hp_regen_pct_add then
        hero.hp_regen_pct = (hero.hp_regen_pct or 0.0) + effect.hp_regen_pct_add
    end
    if effect.whirl_add then hero.whirl = (hero.whirl or 0) + effect.whirl_add end
    if effect.thorns_add then hero.thorns = (hero.thorns or 0.0) + effect.thorns_add end
    if effect.dash_add then hero.dash = (hero.dash or 0) + effect.dash_add end
    -- Attack speed: sum (1/mult - 1) as AS%, resolved against base interval in finalize.
    if effect.fire_interval_mult then
        hero._as_pct = (hero._as_pct or 0.0) + (1.0 / effect.fire_interval_mult - 1.0)
    end
    -- Crit is ROLLED per hit now (see hit_creep), not folded into average dps.
    if effect.crit_add then hero.crit_chance = (hero.crit_chance or 0.0) + effect.crit_add end
    if effect.pickup_range_add then hero.pickup_range = (hero.pickup_range or PICKUP_RANGE_BASE) + effect.pickup_range_add end
    if effect.gold_find_add then hero.gold_find = (hero.gold_find or 1.0) + effect.gold_find_add end
    if effect.slow_aura then hero.slow_aura = true end
    if effect.bleed_on_crit then hero.bleed_on_crit = math.max(hero.bleed_on_crit or 0.0, effect.bleed_on_crit) end
    if effect.dodge_blades then hero.dodge_blades = (hero.dodge_blades or 0.0) + effect.dodge_blades end
    if effect.retaliation_orbit then hero.retaliation_orbit = (hero.retaliation_orbit or 0.0) + effect.retaliation_orbit end
    if effect.flask_nova then hero.flask_nova = (hero.flask_nova or 0.0) + effect.flask_nova end
    if effect.flask_burst then hero.flask_burst = (hero.flask_burst or 0.0) + effect.flask_burst end
    -- Proc boons (Wave Director Phase 2): each sets a single hero field consumed
    -- by its combat hook. Non-stacking (last card wins) — one card each by design.
    if effect.chain_bolt then hero.chain_bolt = effect.chain_bolt end
    if effect.crit_burst then hero.crit_burst = effect.crit_burst end
    if effect.orbit_blades then hero.orbit_blades = effect.orbit_blades end
    if effect.vampiric_surge then hero.vampiric_surge = effect.vampiric_surge end
    if effect.specialization_rank then
        hero.specialization_ranks = hero.specialization_ranks or {}
        local id = effect.specialization_rank
        hero.specialization_ranks[id] = math.min(5, (hero.specialization_ranks[id] or 0) + 1)
    end
    if effect.tree_node then
        local tn = effect.tree_node
        hero.tree_nodes = hero.tree_nodes or {}
        local cls = hero.tree_nodes[tn.class or "?"]
        if not cls then cls = {}; hero.tree_nodes[tn.class or "?"] = cls end
        local t = cls[tn.spec]
        if not t then t = {}; cls[tn.spec] = t end
        t[tn.node] = (t[tn.node] or 0) + 1
    end
    if effect.upgrade_rank then
        hero.upgrade_ranks = hero.upgrade_ranks or {}
        local id = effect.upgrade_rank
        hero.upgrade_ranks[id] = (hero.upgrade_ranks[id] or 0) + 1
    end
    -- Dodge gear: extra charges / faster recharge (Normal-dodge machinery).
    if effect.dodge_charge_add then hero.dodge_charges_max = (hero.dodge_charges_max or 1) + effect.dodge_charge_add end
    if effect.dodge_recharge_mult then
        local b = ref.dodge_recharge or hero.dodge_recharge or DODGE_RECHARGE
        hero.dodge_recharge = hero.dodge_recharge + b * (effect.dodge_recharge_mult - 1.0)
    end
end

local function finalize_attack_speed(hero, ref)
    local as = hero._as_pct
    hero._as_pct = nil
    if not as or as == 0.0 then return end
    local bfi = (ref and ref.fire_interval) or hero.base_fire_interval or hero.fire_interval or 0.28
    hero.fire_interval = bfi / math.max(0.05, 1.0 + as)
end

local function apply_specialization_passives(hero, class_id, ref)
    local ranks = hero.specialization_ranks or {}
    local class
    for _, row in ipairs(Balance.classes) do if row.id == class_id then class = row; break end end
    ref = ref or hero
    for _, spec in ipairs(class and class.specializations or {}) do
        local rank = ranks[spec.id] or 0
        if rank > 0 and spec.move_speed_per_rank then
            -- Additive from base: rank*per_rank is already a summed %, not compounded.
            local pct = spec.move_speed_per_rank * rank
            hero.speed = hero.speed + (ref.speed or 0.0) * pct
            hero.kite_speed = hero.kite_speed + (ref.kite_speed or ref.speed or 0.0) * pct
        end
    end
end

local ARMOR_SLOTS = { "helmet", "body", "pants", "gloves" }

local function apply_equip_load(hero, equipped)
    local load = 0
    for _, slot in ipairs(ARMOR_SLOTS) do
        local item = equipped and equipped[slot]
        load = load + ((item and item.weight) or 0)
    end
    local cfg, tier = RULES.load.light, "LIGHT"
    if load > RULES.load.normal.max_weight then
        cfg, tier = RULES.load.heavy, "HEAVY"
    elseif load > RULES.load.light.max_weight then
        cfg, tier = RULES.load.normal, "NORMAL"
    end
    hero.equip_load = load
    hero.equip_load_max = RULES.load.max
    hero.equip_load_tier = tier
    hero.dodge_charges_max = cfg.charges
    hero.dodge_recharge = cfg.recharge
    hero.dodge_dist = cfg.distance
    hero.dodge_iframes = cfg.invulnerability
    hero.dodge_guard = cfg.guard
    hero.poise = cfg.poise
    hero.stagger_resist = cfg.poise
    hero.speed = hero.speed * cfg.speed_mult
    hero.kite_speed = hero.kite_speed * cfg.speed_mult
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
    hero.hp_regen_pct = 0.0
    hero.whirl = base.whirl or 0
    hero.thorns = base.thorns or 0.0
    hero.dash = base.dash or 0
    hero.crit_chance = base.crit_chance or RULES.crit.base_chance
    hero.pickup_range = base.pickup_range or PICKUP_RANGE_BASE
    hero.gold_find = base.gold_find or 1.0
    hero.slow_aura = false
    hero.bleed_on_crit, hero.dodge_blades, hero.retaliation_orbit = 0.0, 0.0, 0.0
    hero.flask_nova, hero.flask_burst = 0.0, 0.0
    -- Proc boons (run-scoped draft cards): reset to inactive every recompute.
    hero.chain_bolt, hero.crit_burst, hero.orbit_blades, hero.vampiric_surge = nil, nil, nil, nil
    hero.specialization_ranks = {}
    hero.upgrade_ranks = {}
    hero.tree_nodes = {}
    hero.primary_spec = nil
    hero.fire_interval = hero.base_fire_interval or hero.fire_interval or 0.28
    -- Load establishes the dodge identity; gear and cards then modify it.
    apply_equip_load(hero, self.gear_equipped)
    -- pct bonuses reference naked base_stats (and post-load dodge recharge).
    local ref = {
        dps = base.dps or hero.dps,
        speed = base.speed or hero.speed,
        kite_speed = base.kite_speed or hero.kite_speed,
        fire_interval = hero.base_fire_interval or hero.fire_interval or 0.28,
        dodge_recharge = hero.dodge_recharge,
    }
    hero._as_pct = 0.0

    for _, slot in ipairs({ "helmet", "body", "pants", "gloves", "weapon", "jewelry" }) do
        local item = self.gear_equipped and self.gear_equipped[slot]
        if item then apply_gear_effect(hero, item.effect, ref) end
    end
    -- Run-scoped drafted boons stack on top of base + gear.
    for _, card in ipairs(self.run_cards or {}) do
        apply_gear_effect(hero, card.effect, ref)
    end
    apply_specialization_passives(hero, self.hero_class, ref)
    -- Hero Grid: derive effective rider values (spec_fx) from tree
    -- allocations; specialization_ranks doubles as points-in-tree for the
    -- HUD, gates, and persistence sites.
    hero.spec_fx = {}
    hero.minion_dmg_mult = 1.0
    self._status_spec = {}
    -- Primary = first tree card of the ACTIVE class in run order (profiles
    -- carry every class's cards; other classes' trees stay banked but inert).
    hero.primary_spec = nil
    for _, card in ipairs(self.run_cards or {}) do
        local tn = card.effect and card.effect.tree_node
        if tn and (tn.class or self.hero_class) == self.hero_class then
            hero.primary_spec = tn.spec
            break
        end
    end
    local class_alloc = self:class_tree_nodes()
    local class = self:active_class()
    for _, spec in ipairs(class and class.specializations or {}) do
        local alloc = class_alloc[spec.id]
        if alloc then
            local tree = Balance.spec_tree(self.hero_class, spec.id)
            if tree then -- defensive clamp; allocate/migration already gate
                for nid, r in pairs(alloc) do
                    local node = tree.by_id[nid]
                    if not node then alloc[nid] = nil
                    elseif r > node.max_rank then alloc[nid] = node.max_rank end
                end
            end
        end
        local fx = Balance.compute_spec_fx(self.hero_class, spec, alloc)
        hero.spec_fx[spec.id] = fx
        -- max(): legacy modes still rank specs via effect.specialization_rank.
        hero.specialization_ranks[spec.id] =
            math.max(hero.specialization_ranks[spec.id] or 0, fx.points or 0)
        self._status_spec[spec.status] = spec.id
        if (fx.range_add or 0.0) > 0.0 then
            hero.attack_range = hero.attack_range + fx.range_add
        end
        if spec.kind == "summon" and (fx.points or 0) > 0 then
            if fx.minion_dmg then hero.minion_dmg_mult = fx.minion_dmg.mult or 1.25 end
            if fx.legion then hero.minion_dmg_mult = hero.minion_dmg_mult * (fx.legion.dmg_mult or 0.8) end
        end
    end
    finalize_attack_speed(hero, ref)
    if self.superhero then
        hero.hp_max = hero.hp_max * 5.0
        hero.dps = hero.dps * 5.0
        hero.speed = hero.speed * 2.0
        hero.kite_speed = (hero.kite_speed or hero.speed) * 2.0
        hero.cleave = (hero.cleave or 1) + 8
        hero.fire_interval = math.max(0.05, (hero.fire_interval or 0.28) * 0.35)
    end
    hero.dodge_charges = math.min(hero.dodge_charges or 1, hero.dodge_charges_max)
    hero.dodge_recharge_t = math.min(hero.dodge_recharge_t or hero.dodge_recharge, hero.dodge_recharge)

    local delta = hero.hp_max - old_max
    if delta > 0.0 then
        hero.hp = math.min(hero.hp_max, old_hp + delta)
    else
        hero.hp = math.min(old_hp, hero.hp_max)
    end
end

-- Dev cheat: rebuild the live hero as another class without dumping inventory.
function Duel:cheat_swap_hero(index)
    local list = self.config.hero and self.config.hero.classes
    if not (list and list[index]) then return false, "unknown hero" end
    local keep_state = self.state
    self.hero_class = list[index].id
    self.hero_class_index = index
    _G.ATH_RUN = _G.ATH_RUN or {}
    _G.ATH_RUN.hero_index = index
    local rebuild_hero = Art.valid(self.hero and self.hero.root) and not (self.hero and self.hero.adopted)
    self:park_all_minions()
    if rebuild_hero then scene.delete_node(self.hero.root) end
    self:create_hero()
    local specs = list[index].specializations or {}
    if list[index].progressive_specializations then
        self.specialization = nil
    else
        local keep = false
        for _, spec in ipairs(specs) do
            if spec.id == self.specialization then keep = true; break end
        end
        self.specialization = keep and self.specialization or (specs[1] and specs[1].id) or nil
    end
    self:ensure_combat_pools()
    self:recompute_hero_stats()
    if self.hero then self.hero.hp = self.hero.hp_max end
    if keep_state == "combat" or keep_state == "pause" or keep_state == "town" then
        self.state = keep_state
    end
    return true, self.hero_class
end

function Duel:draft_card_catalog()
    local catalog = {}
    for _, card in ipairs(Balance.draft_cards or {}) do
        if card.id then catalog[card.id] = card end
    end
    for _, card in ipairs(Balance.draft_boons or {}) do
        if card.id then catalog[card.id] = card end
    end
    for _, cards in pairs(Balance.specialization_cards or {}) do
        for _, card in ipairs(cards) do
            if card.id then catalog[card.id] = card end
        end
    end
    for _, cards in pairs(Balance.tree_cards or {}) do
        for _, card in ipairs(cards) do
            if card.id then catalog[card.id] = card end
        end
    end
    return catalog
end

function Duel:apply_saved_run_cards()
    local ids = self._saved_run_card_ids
    if type(ids) ~= "table" or #ids == 0 then return end
    local catalog = self:draft_card_catalog()
    self.run_cards = {}
    -- Legacy spine migration: the Nth occurrence of an old flat spec card
    -- ({class}_spec_{spec}) becomes the Nth node of the canonical spine, so an
    -- old rank-5 lands exactly on keystone + both Foundation nodes maxed.
    local spine_seen = {}
    local boon_seen = {}
    for _, id in ipairs(ids) do
        if id == "universal_projectiles" then id = "universal_sustain" end
        local card = catalog[id]
        -- Proc boons persist across save/load once obtained (elite/boss drops);
        -- dedupe on restore so a legacy profile never re-adds the same boon.
        if card and card.boon then
            if not boon_seen[card.id] then
                boon_seen[card.id] = true
                self.run_cards[#self.run_cards + 1] = card
            end
        -- Only specialization ranks persist; universal draft cards are retired.
        elseif card and card.specialization then
            if card.tree_node then
                self.run_cards[#self.run_cards + 1] = card
            elseif card.class_id and Balance.spec_tree(card.class_id, card.specialization) then
                local n = (spine_seen[id] or 0) + 1
                spine_seen[id] = n
                local node_id = Balance.tree_legacy_spine[n]
                local node_card = node_id
                    and Balance.tree_card(card.class_id, card.specialization, node_id)
                if node_card then
                    self.run_cards[#self.run_cards + 1] = node_card
                end -- ranks past the old cap of 5 never existed; drop silently
            else
                self.run_cards[#self.run_cards + 1] = card
            end
        end
    end
    local restored = {}
    for _, card in ipairs(self.run_cards) do
        if card.boon and card.id then restored[#restored + 1] = card.id end
    end
    if #restored > 0 then self:log("boons restored: " .. table.concat(restored, ",")) end
end

function Duel:reset_manual_gear(keep_progression)
    self.gold = self.gold or 0
    self.inv_grid = self.inv_grid or {}
    self.gear_equipped = self.gear_equipped or { helmet = nil, body = nil, pants = nil, gloves = nil, weapon = nil, jewelry = nil }
    self.gear_drop_cursor = 0
    if not keep_progression then
        self.run_cards = {}
        self.skill_points = (Balance.tree_rules and Balance.tree_rules.starting_points) or 1
    end
    -- Re-apply pending profile picks (ids cleared after choose_class).
    if self._saved_run_card_ids then self:apply_saved_run_cards() end
    self:recompute_hero_stats()
    -- Legacy economy banked unbounded points; anything the 14-point cap can
    -- never spend converts to gold once here. Full respec stays whole:
    -- refunds return spent points, and spent + kept <= point_cap.
    local rules = Balance.tree_rules
    if rules and self.hero then
        local spent = 0
        for _, t in pairs(self:class_tree_nodes()) do
            for _, r in pairs(t) do spent = spent + r end
        end
        local keep = math.max(0, (rules.point_cap or 14) - spent)
        local excess = math.floor((self.skill_points or 0) - keep)
        if excess > 0 then
            local payout = excess * (rules.excess_point_gold or 100)
            self.skill_points = keep
            self.gold = (self.gold or 0) + payout
            self:log(string.format("legacy skill points: %d excess -> %d gold", excess, payout))
        end
    end
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
        crit_chance = base.crit_chance or RULES.crit.base_chance,
        pickup_range = base.pickup_range or PICKUP_RANGE_BASE,
        gold_find = base.gold_find or 1.0,
        fire_interval = hero.base_fire_interval or hero.fire_interval or 0.28,
        dodge_charges_max = RULES.load.light.charges, dodge_recharge = RULES.load.light.recharge,
        dodge_dist = RULES.load.light.distance, dodge_iframes = RULES.load.light.invulnerability,
        dodge_guard = 0.0, poise = 0.0, stagger_resist = 0.0,
        bleed_on_crit = 0.0, dodge_blades = 0.0, retaliation_orbit = 0.0,
        flask_nova = 0.0, flask_burst = 0.0,
        hp_regen_pct = 0.0,
        specialization_ranks = {},
        upgrade_ranks = {},
    }
    apply_equip_load(t, self.gear_equipped)
    local ref = {
        dps = base.dps or t.dps,
        speed = base.speed or t.speed,
        kite_speed = base.kite_speed or t.kite_speed,
        fire_interval = hero.base_fire_interval or t.fire_interval or 0.28,
        dodge_recharge = t.dodge_recharge,
    }
    t._as_pct = 0.0
    for _, slot in ipairs({ "helmet", "body", "pants", "gloves", "weapon", "jewelry" }) do
        local item = self.gear_equipped and self.gear_equipped[slot]
        if item then apply_gear_effect(t, item.effect, ref) end
    end
    for _, card in ipairs(self.run_cards or {}) do
        apply_gear_effect(t, card.effect, ref)
    end
    apply_specialization_passives(t, self.hero_class, ref)
    finalize_attack_speed(t, ref)
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
-- Round / pause / loot loop
-- ---------------------------------------------------------------------------

-- Walk-and-pick window before leaving a wave / boss / map. Gold is already
-- banked; item beacons stay until the hero walks onto them (or confirm loses
-- leftovers). Gear / Esc opens the bag to free slots without auto-vacuum.
-- Hero Grid income: +1 per swarm-wave clear, +2 at boss entry, capped at 14
-- points earned per character (spent ranks + banked points count as earned).
function Duel:award_spec_points(n, why)
    if not self.manual_hero or (n or 0) <= 0 then return end
    local spent = 0
    for _, t in pairs(self:class_tree_nodes()) do
        for _, r in pairs(t) do spent = spent + r end
    end
    local cap = (Balance.tree_rules and Balance.tree_rules.point_cap) or 14
    local give = math.max(0, math.min(n, cap - spent - (self.skill_points or 0)))
    if give <= 0 then return end
    self.skill_points = (self.skill_points or 0) + give
    local I18n = _G.ATH_I18N
    local msg = (I18n and I18n.t("+%d SKILL", give)) or string.format("+%d SKILL", give)
    self:set_flash("%s", (self.flash and self.flash ~= "" and (self.flash .. "  ") or "") .. msg)
    self:log(string.format("spec points +%d (%s) banked=%d", give, tostring(why), self.skill_points))
end

function Duel:begin_loot(after)
    self:vacuum_coins()
    self:park_all_minions()
    self:reset_hero_projectiles()
    self:reset_earth_shards()
    self:reset_creep_projectiles()
    self:restore_flask_charges(2)
    -- A cleared swarm wave pays +1. Boss-entry points land here too, so the
    -- loot/gear window can spend them before one-shot boss-arrival capstones.
    if after == "next_wave" or after == "boss"
        or (after == "map_clear" and not (self:active_map().boss or self.config.boss_archetype)) then
        self:award_spec_points(Balance.tree_rules and Balance.tree_rules.wave_points or 1, "wave clear")
    end
    if after == "boss" then
        self:award_spec_points(Balance.tree_rules and Balance.tree_rules.boss_points or 2, "boss entry")
    end
    if self.hero and not self.hero.dead then
        Art.burst("ath_wave_clear", vec3(self.hero.x, 0.8, self.hero.z),
            { preset = "hero_take", count = 26, life_max = 0.5, spawn_radius = 0.6, size_max = 0.2,
              color_start = vec4(1.0, 0.9, 0.4, 1.0), gravity = vec3(0.0, 2.6, 0.0) })
    end
    self.state = "loot"
    self._loot_after = after
    self._loot_inv = nil
    self._between_wave = false
    self:haptic(25)
    self:set_flash("PICK UP ITEMS")
    if after == "next_wave" then
        self:remember_map_wave()
        self:save_profile()
    end
    self:log("loot after=" .. tostring(after))
end

function Duel:rise_boss()
    local map = self:active_map()
    local boss_arch = map.boss or self.config.boss_archetype
    if not boss_arch then return end
    self.boss_spawned = true
    -- Apocalypse capstone: the boss's arrival raises a free bone escort.
    local hero = self.hero
    local sum_fx = hero and (hero.spec_fx or {}).summoner
    local sum_cap = sum_fx and sum_fx.capstone
    if sum_cap and sum_cap.kind == "summon_burst" and hero and not hero.dead then
        for _ = 1, sum_cap.params.count or 4 do
            local angle, radius = math.random() * math.pi * 2.0, 0.8 + math.random() * 1.2
            self:try_summon_minion("skeleton", MINIONS.skeleton.cap_max + (sum_cap.params.count or 4),
                hero.x + math.cos(angle) * radius, hero.z + math.sin(angle) * radius)
        end
    end
    local title = map.boss_title or self.config.boss_title
    local I18n = _G.ATH_I18N
    if title then
        local tname = (I18n and I18n.t(title)) or title
        self:set_flash("THE %s RISES", tname)
    else
        self:set_flash("A CHAMPION RISES")
    end
    Art.shake(0.5, 0.5)
    self.state = "combat"
    self:add_telegraph(self:pick_spawn_point(), boss_arch, true)
    self:log("boss telegraphed arch=" .. tostring(boss_arch))
end

function Duel:finish_map_clear()
    local map = self:active_map()
    local boss_arch = map.boss or self.config.boss_archetype
    if self.boss_tour then
        self:log(string.format("boss tour clear map=%d boss=%s",
            self.map_index or 1, tostring(boss_arch)))
        if self.map_index < #self.maps then
            self.map_index = self.map_index + 1
            self.boss_spawned = false
            self.boss_creep = nil
            self.boss_spawn_time = nil
            if self.hero then self.hero.hp = self.hero.hp_max end
            self.state = "town"
            self:start_map()
        else
            self.state = "hero_win"
            self:set_flash("BOSS TOUR COMPLETE")
        end
        return
    end
    local unlocked
    if #self.maps > 0 and self.map_index > (self.maps_cleared or 0) then
        self.maps_cleared = self.map_index
        unlocked = self.maps[self.map_index + 1]
    end
    self.map_next_wave = self.map_next_wave or {}
    self.map_next_wave[math.floor(self.map_index or 1)] = 1
    self:save_profile()
    local clear = unlocked and T("%s UNLOCKED", T(tostring(unlocked.name))) or T("RUN CLEARED")
    self:log(string.format("RUN CLEARED map=%d waves=%d kills=%d gold=%d",
        self.map_index or 1, self.wave_index or 1, self.kills, self.gold or 0))
    self:reset_run(true) -- town; loot button already was ENTER TOWN
    self:set_flash(clear)
end

function Duel:confirm_loot()
    if self.state ~= "loot" then return end
    self:vacuum_pickups() -- leftover items: bag or lost
    local after = self._loot_after
    self._loot_after = nil
    if after == "next_wave" then
        self:begin_pause({ from_loot = true })
    elseif after == "boss" then
        self:rise_boss()
    elseif after == "map_clear" then
        self:finish_map_clear()
    else
        self.state = "combat"
    end
end

function Duel:loot_leave_label()
    local after = self._loot_after
    if after == "next_wave" then return T("NEXT WAVE") end
    if after == "boss" then return T("CONTINUE") end
    if after == "map_clear" and self.boss_tour and (self.map_index or 1) < #self.maps then
        return T("CONTINUE")
    end
    return T("ENTER TOWN")
end

function Duel:begin_pause(opts)
    opts = opts or {}
    if self.manual_hero then
        if not opts.from_loot then
            self:vacuum_coins() -- gold only; items need the loot walk (or were none)
            self:park_all_minions()
            self:reset_hero_projectiles()
            self:reset_earth_shards()
            self:reset_creep_projectiles()
            self:restore_flask_charges(2)
            if self.hero and not self.hero.dead then
                Art.burst("ath_wave_clear", vec3(self.hero.x, 0.8, self.hero.z),
                    { preset = "hero_take", count = 26, life_max = 0.5, spawn_radius = 0.6, size_max = 0.2,
                      color_start = vec4(1.0, 0.9, 0.4, 1.0), gravity = vec3(0.0, 2.6, 0.0) })
            end
            self:remember_map_wave()
            self:save_profile()
        end
        self.state = "pause"
        self._between_wave = true -- a wave-flow pause: NEXT WAVE advances the run
        self._hub_tab = "map" -- don't keep a mid-fight Settings/Inventory peek
        self:haptic(25)
        self:set_flash("WAVE %d CLEARED", self.wave_index or 1)
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
    self:set_flash("ROUND %d — your move", self.round)
    if self.config.hooks and self.config.hooks.on_pause then self.config.hooks.on_pause(self) end
    self:log(string.format("pause round=%d reserve=%.0f swarm=%d", self.round, self.reserve, self:count_alive()))
end

function Duel:resume_combat()
    if self.manual_hero then
        Inventory.hide(self)
        if self._worldmap_inv then
            self._worldmap_inv = nil
            self.state = "worldmap"
            if self.config.hooks and self.config.hooks.on_resume then self.config.hooks.on_resume(self) end
            return
        end
        if self._loot_inv then
            -- Gear peek during loot walk — close bag, keep picking up.
            self._loot_inv = false
            self.state = "loot"
            if self.config.hooks and self.config.hooks.on_resume then self.config.hooks.on_resume(self) end
            return
        end
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
    elseif self.state == "loot" then
        self._loot_inv = true
        self._between_wave = false
        self.state = "pause"
        self._hub_tab = "inventory"
        self:haptic(15)
        Inventory.show(self)
    elseif self.state == "worldmap" then
        self._worldmap_inv = true
        self._between_wave = false
        self.state = "pause"
        self:haptic(15)
        Inventory.show(self)
    end
end

function Duel:reset_run(to_town)
    -- A run spans maps: every drafted specialization and universal upgrade
    -- belongs to this hero until death, regardless of town/map transitions.
    local keep_progression = self.manual_hero and self.state ~= "slain"
    for _, c in ipairs(self.creeps) do
        self:park_blast_decal(c)
        Creep.destroy(c)
    end
    self.creeps = {}
    self:flush_dying()
    self:park_all_minions()
    -- Parked creep NodeIds survive sibling relocation, so a run reset keeps the
    -- warm pool instead of deleting and rebuilding every rig.
    local rebuild_hero = Art.valid(self.hero and self.hero.root) and not (self.hero and self.hero.adopted)
    -- Adopted heroes (authored scene node) are re-found by create_hero, never deleted.
    if rebuild_hero then
        scene.delete_node(self.hero.root)
    end
    self:create_hero()
    self.combat_time = 0.0
    self.round = 1
    self.round_t = self.round_seconds
    self.spawn_t = 0.6
    self.spawn_counter = 0
    self.spawn_queue = {}
    self:clear_seed_mines()
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
    self:reset_hero_projectiles()
    self:reset_earth_shards()
    self:clear_damage_numbers()
    if self.manual_hero then
        self.player_seat = nil
        self.ai_seat = nil
        self:reset_manual_gear(keep_progression)
        self:ensure_combat_pools()
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
    if self.console and self.console.visible then return end
    -- R (reset) / M (menu) are gear/UI only — no keyboard shortcuts in the shipped game.
    if self.manual_hero and (self.state == "hero_win" or self.state == "slain") then
        if Art.consume_click(self.hud, "end_town_btn") then
            self:reset_run(true)
        end
        return
    end
    if self:key_pressed("Escape") then
        if self.manual_hero and (self.state == "combat" or self.state == "pause" or self.state == "loot"
            or self.state == "town" or self.state == "worldmap") then
            self:toggle_inventory()
            return
        end
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

    if self.state == "specpick" then
        local class = self:active_class()
        for i = 1, #(class and class.specializations or {}) do
            if self:key_pressed(tostring(i)) or Art.consume_click(self.hud, "specpick_" .. i) then
                self:choose_specialization(i)
                return
            end
        end
        return
    end

    if self.state == "worldmap" then
        if Art.consume_click(self.hud, "wm_gear") then
            self:toggle_inventory()
            return
        end
        local max_map = math.min((self.maps_cleared or 0) + 1, #self.maps)
        local function travel()
            self:enter_town(self._wm_from_town)
            self:set_flash("DESTINATION: %s", (_G.ATH_I18N and _G.ATH_I18N.t(tostring(self:active_map().name))) or tostring(self:active_map().name))
        end
        local step = (self:key_pressed("Right") and 1 or 0) - (self:key_pressed("Left") and 1 or 0)
        if step ~= 0 then
            self.map_index = clampn(self.map_index + step, 1, max_map)
            self:haptic(8)
        end
        -- Nodes only select; travel is the ENTER button (or Return/Space).
        for i = 1, #self.maps do
            if Art.consume_click(self.hud, "wm_node_" .. i) then
                if i > max_map then
                    local prev = (self.maps[i - 1] and self.maps[i - 1].name) or "the previous map"
                    self:set_flash("LOCKED - clear %s", (_G.ATH_I18N and _G.ATH_I18N.t(tostring(prev))) or tostring(prev))
                elseif i ~= self.map_index then
                    self.map_index = i
                    self:haptic(8)
                end
            end
        end
        if Art.consume_click(self.hud, "wm_travel")
            or self:key_pressed("Return") or self:key_pressed("Space") then
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
        if self:key_pressed("T") then Inventory.sort(self) end
        for i, slot in ipairs(Inventory.SLOTS) do
            if self:key_pressed(tostring(i)) then self:buy_store_offer(slot) end
        end
        -- Left/Right reopen the world map (click is the hub Map Dest button).
        if #self.maps > 1 and (self:key_pressed("Left") or self:key_pressed("Right")) then
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
                local pick = 1
                for i, card in ipairs(self.draft_offer or {}) do
                    local rank = card.specialization
                        and ((self.hero.specialization_ranks or {})[card.specialization] or 0) or 0
                    if not card.max_rank or rank < card.max_rank then pick = i; break end
                end
                self:pick_draft_card(pick)
            end
        end
        return
    end

    if self.state == "pause" then
        if self.manual_hero then
            Inventory.update(self) -- drag-and-drop + click-to-(un)equip over authored nodes
            if self:key_pressed("T") then Inventory.sort(self) end
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
        return
    end

    if self.state == "loot" then
        -- Enter confirms leave; Space stays dodge (movement still live).
        if self:key_pressed("Return") or Art.consume_click(self.hud, "loot_leave_btn") then
            self:confirm_loot()
            return
        end
        if self.autoplay then
            self.autoplay_t = (self.autoplay_t or 0.8) - dt
            if self.autoplay_t <= 0.0 then
                self.autoplay_t = 0.8
                self:confirm_loot()
            end
        end
        return
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
    -- Bottom strip: icon + text (no chip boxes).
    local bottom_hud_y = sh - S(26.0)
    local bottom_hud_h = S(36.0)
    local bottom_icon = S(26.0)
    local bottom_gap = S(10.0) -- between groups (gold | dodge | flask)
    -- Draw icon at x; return x after icon (label starts immediately).
    local function hud_icon(id, x, path)
        local iz = bottom_icon
        local iy = bottom_hud_y + (bottom_hud_h - iz) * 0.5
        Art.quad(self.hud, id, x, iy, iz, iz, { 0.0, 0.0, 0.0, 0.0 },
            { style = "image", image = path, no_input = true })
        return x + iz
    end
    -- Backend pads Text-style labels by 10*fontScale on both sides. Shift left by
    -- pad and grow width by 2*pad so wrap width == `w` and glyphs start at `x`.
    local label_fs = Art.s("text") / (Art._ui_scale or 1.0)
    local label_pad = 10.0 * label_fs
    local function hud_text(id, x, w, label, text_color, gap_after)
        local vp = Art._vp
        runtime_ui.set_quad(self.hud, id, {
            x = x - label_pad + vp.x, y = bottom_hud_y + vp.y,
            width = w + label_pad * 2.0, height = bottom_hud_h,
            label = Art.ascii(label or ""), style = "text", align_h = "left", align_v = "middle",
            fill = { 0.0, 0.0, 0.0, 0.0 }, border = { 0.0, 0.0, 0.0, 0.0 },
            text_color = text_color or { 0.98, 0.98, 1.0, 1.0 },
            font_scale = label_fs, no_input = true,
        })
        return x + w + (gap_after or bottom_gap)
    end

    -- Hero HP bar (top center).
    local bw, bh = S(520.0), S(36.0)
    local bx, by = sw * 0.5 - bw * 0.5, S(28.0)
    local pct = clampn((hero.hp or 0.0) / (hero.hp_max or 1.0), 0.0, 1.0)
    local hp_color = pct > 0.5 and { 0.36, 0.78, 0.42, 0.95 } or (pct > 0.25 and { 0.92, 0.74, 0.28, 0.95 } or { 0.90, 0.30, 0.26, 0.95 })
    -- config.external_hud (set by the scene-driven game_boot) means an authored
    -- scene UI draws the HP + wave-budget bars instead, so skip the built-ins.
    if not self.config.external_hud then
        Art.bar(self.hud, "hp", bx, by, bw, bh, pct, hp_color, {
            label = T("HERO  %d / %d", math.floor(hero.hp + 0.5), math.floor(hero.hp_max + 0.5)) })
    end

    -- Top-left status — ONE compact multi-line label. Drawn from the top edge, so
    -- the frame hugs the text (the title/body layout reserves a tall empty "art"
    -- band up top). Sized to the text scale; font bumped for legibility.
    local side_label = (self.side == "hero") and "YOU: HERO" or "YOU: HORDE"
    local TS = Art.s("text")
    local status_text
    if self.manual_hero then
        local map = self:active_map()
        local map_line = (map.name and T("%s  (Rank %s)", T(tostring(map.name)), tostring(map.rank or "?")))
            or T(self.theme.hud_title or (self.config.name or "DUEL"))
        status_text = T("%s\nYOU: HERO  -  Wave %d/%d\nBudget %d / %d\nSwarm %d    Kills %d\nGold %d",
            map_line,
            self.wave_index or 1, self:total_rounds(),
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
    local flash_blocked = self.manual_hero and (self.state == "pause" or self.state == "town"
        or self.state == "draft" or self.state == "classpick" or self.state == "specpick"
        or self.state == "worldmap")
    if self.flash and self.flash ~= "" and not flash_blocked then
        Art.quad(self.hud, "flash", sw * 0.5 - S(260.0), S(96.0), S(520.0), S(34.0), { 0.0, 0.0, 0.0, 0.0 },
            { label = self.flash, text_color = { 0.95, 0.82, 0.35, math.min(1.0, self.flash_t) } })
    else
        Art.remove(self.hud, "flash")
    end

    -- Loot walk leave button: centered, just above the bottom gold/flask strip so
    -- it clears gear (top), flash (top), and the right-side spec icons.
    if self.manual_hero and self.state == "loot" then
        local bw, bh = S(360.0), S(56.0)
        local by = bottom_hud_y - bh - S(18.0)
        Art.quad(self.hud, "loot_leave_btn", sw * 0.5 - bw * 0.5, by, bw, bh,
            { 0.20, 0.10, 0.28, 0.96 }, {
                style = "button",
                border = accent, accent = accent,
                title = self:loot_leave_label(),
                text_color = { 0.96, 0.92, 1.0, 1.0 },
                font_scale = 1.15, align_h = "center", align_v = "middle",
                bring_to_front = true,
            })
    else
        Art.remove(self.hud, "loot_leave_btn")
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
    -- With the authored scene HUD, y=0 (the 20:9 letterbox top inset) already
    -- sits just below the surface-anchored hero bar and ABOVE the arena's top
    -- border, keeping the bar out of the play field.
    -- ponytail: assumes a letterboxed (non-ultrawide) window; at 21:9 the inset
    -- collapses and the bar rides up onto the authored hero bar.
    local boss = self.boss_creep
    if boss and boss.alive and self.state == "combat" then
        -- Cap at 60% of the surface: the authored FPS clock (top-right) starts
        -- at ~84% of the width, and a fixed S(640) ran underneath it.
        local bw2 = math.min(S(640.0), sw * 0.60)
        local boss_title = T(self:active_map().boss_title or self.config.boss_title or "BOSS")
        local armor_state = (boss.armor_broken_t or 0.0) > 0.0 and T(" - ARMOR BROKEN") or T(" - ARMORED")
        if boss.boss_phase2 then armor_state = armor_state .. T(" - PHASE II") end
        Art.bar(self.hud, "boss", sw * 0.5 - bw2 * 0.5, self.config.external_hud and 0.0 or S(70.0), bw2, S(30.0),
            clampn((boss.hp or 0.0) / math.max(1.0, boss.hp_max or 1.0), 0.0, 1.0),
            { 0.78, 0.30, 0.86, 0.95 },
            { label = boss_title .. armor_state, border = { 0.5, 0.2, 0.6, 0.95 } })
    else
        Art.remove_ids(self.hud, { "boss_bg", "boss_fg", "boss_label" })
    end

    -- Bottom strip left→right: gold, dodge, health flask. Compact so the
    -- flask clears the right-side specs.
    local strip_x = S(8.0)
    if self.manual_hero and self.gold and self.state ~= "worldmap" then
        strip_x = hud_icon("gold_icon", strip_x, V.ui.hud.gold)
        strip_x = hud_text("gold_label", strip_x, S(72.0),
            tostring(math.floor(self.gold or 0)),
            { 0.98, 0.86, 0.36, 1.0 })
        Art.remove_ids(self.hud, { "gold_chip", "gold_chip_label", "gold_chip_icon" })
    else
        Art.remove_ids(self.hud, { "gold_icon", "gold_label", "gold_chip", "gold_chip_label", "gold_chip_icon" })
    end

    if self.manual_hero and (self.state == "combat" or self.state == "loot") and hero and not hero.dead then
        local cursor = strip_x
        local ready = (hero.dodge_charges or 0) >= 1
        cursor = hud_icon("dodge_icon", cursor, V.ui.hud.dodge)
        cursor = hud_text("dodge_label", cursor, S(96.0),
            ready and T("READY [Space]") or T(". . ."),
            ready and { 0.70, 0.92, 1.0, 1.0 } or { 0.65, 0.68, 0.72, 1.0 })

        local drink_h = (hero.flask_drink_t or 0.0) > 0.0
            and string.format(" %.1fs", hero.flask_drink_t) or ""
        -- Flask: label glued to icon. Width fits "xN [K]".
        cursor = hud_icon("flask_h_icon", cursor, V.ui.hud.flask_health)
        cursor = hud_text("flask_h_label", cursor, drink_h ~= "" and S(64.0) or S(52.0),
            T("x%d [Q]%s", hero.flask_health or 0, drink_h),
            { 1.0, 0.72, 0.72, 1.0 }, S(0.0))
        -- Drop legacy chip/bar widgets from older builds (incl. the mana era).
        Art.remove_ids(self.hud, { "mana_bg", "mana_fg", "mana_label",
            "res_icon", "res_bg", "res_fg", "res_label",
            "flask_m_icon", "flask_m_label",
            "dodge_bg", "dodge_fg", "flask", "flask_label", "flask_icon" })
    else
        Art.remove_ids(self.hud, {
            "res_icon", "res_bg", "res_fg", "res_label",
            "mana_bg", "mana_fg", "mana_label",
            "dodge_bg", "dodge_fg", "dodge_label", "dodge_icon",
            "flask", "flask_label", "flask_icon",
            "flask_h_icon", "flask_h_label", "flask_m_icon", "flask_m_label",
        })
    end

    -- The current class's three specializations stay visible for the whole run.
    local show_specs = self.manual_hero and hero and not hero.dead
    if show_specs then
        Art.remove_ids(self.hud, { "specializations", "buffs_title", "buff_1", "buff_2", "buff_3",
            "buff_4", "buff_5", "buff_6", "buff_tip" })
        local class = self:active_class()
        local specs = class and class.specializations or {}
        local icon_size, gap = S(30.0), S(5.0)
        local row_w = #specs * icon_size + math.max(0, #specs - 1) * gap
        local bx, by = sw - row_w - S(16.0), bottom_hud_y
        local tip
        for i, spec in ipairs(specs) do
            local id = "spec_hud_" .. i
            local x = bx + (i - 1) * (icon_size + gap)
            Art.remove_ids(self.hud, { id .. "_icon", id .. "_text" })
            local rank = (hero.specialization_ranks or {})[spec.id] or 0
            local fx = (hero.spec_fx or {})[spec.id]
            local text
            if rank > 0 and fx and Inventory.spec_fx_lines then
                text = T("Current:") .. "\n" .. table.concat(Inventory.spec_fx_lines(spec, fx), "\n")
            else
                text = T("Not learned.\n") .. T(tostring(spec.desc or spec.id))
            end
            if spec.kind == "frenzy" and (hero.frenzy_t or 0.0) > 0.0 then
                text = text .. "\n" .. T("Active: %d stacks, %.1fs left.",
                    hero.frenzy_stacks or 0, hero.frenzy_t)
            elseif spec.kind == "preservation" and (hero.preservation_t or 0.0) > 0.0 then
                text = text .. "\n" .. T("Active: %.1fs left.", hero.preservation_t)
            end
            local color = rank > 0 and (spec.accent or class.accent) or { 0.30, 0.32, 0.38, 0.80 }
            Art.quad(self.hud, id, x, by, icon_size, icon_size, { 0, 0, 0, 0 },
                { image = spec.icon,
                  image_tint = rank > 0 and { 1, 1, 1, 1 } or { 0.38, 0.40, 0.46, 0.72 } })
            local badge_size = S(14.0)
            local badge_x, badge_y = x + icon_size - badge_size, by + icon_size - badge_size
            Art.quad(self.hud, id .. "_level", badge_x, badge_y, badge_size, badge_size,
                { 0.025, 0.03, 0.045, 0.96 }, { no_input = true, border = color })
            local badge_font_scale = 0.28
            local badge_text_y = badge_y + badge_size * 0.5 - Art.s("text") * 21.0 * badge_font_scale
            Art.quad(self.hud, id .. "_level_text", badge_x, badge_text_y, badge_size, badge_size,
                { 0, 0, 0, 0 }, { no_input = true, align_h = "center", font_scale = badge_font_scale,
                  text_color = { 1, 1, 1, 1 }, label = tostring(rank) })
            local st = Art.widget_state(self.hud, id)
            if st and st.hovered then tip = { spec = spec, rank = rank, text = text, x = x, color = color } end
        end
        for i = #specs + 1, 3 do
            local id = "spec_hud_" .. i
            Art.remove_ids(self.hud, { id, id .. "_icon", id .. "_text", id .. "_level", id .. "_level_text" })
        end
        if tip then
            local tw, th = S(420.0), S(112.0)
            local tx = clampn(tip.x + icon_size * 0.5 - tw * 0.5, S(8.0), sw - tw - S(8.0))
            local ty = math.max(S(8.0), by - th - S(8.0))
            Art.quad(self.hud, "spec_hud_tip", tx, ty, tw, th,
                { 0.035, 0.04, 0.065, 0.98 }, { no_input = true, bring_to_front = true,
                  border = tip.color, font_scale = 0.72,
                  label = T("%s  LV %d\n%s", T(tip.spec.name), tip.rank, tip.text) })
        else
            Art.remove(self.hud, "spec_hud_tip")
        end
    else
        Art.remove_ids(self.hud, { "buffs_title", "buff_1", "buff_2", "buff_3", "buff_4", "buff_5",
            "buff_6", "buff_tip", "specializations", "spec_hud_tip" })
        for i = 1, 3 do
            local id = "spec_hud_" .. i
            Art.remove_ids(self.hud, { id, id .. "_icon", id .. "_text", id .. "_level", id .. "_level_text" })
        end
    end

    -- Destination lives on the hub Map tab (Map Dest above ENTER MAP).
    Art.remove(self.hud, "town_dest")

    -- World map screen: the painted overworld. Each map IS a building painted
    -- on the artwork, marked by a ring frame + bobbing gold pin; locked ones
    -- grey out. Hovering a marker shows the full description. A route of dots
    -- links the ladder in rank order.
    if self.state == "worldmap" and #self.maps > 0 then
        self._wm_drawn = true
        local max_map = math.min((self.maps_cleared or 0) + 1, #self.maps)
        -- Full-bleed like the vignette: compensated coords cancel the viewport
        -- offset so the parchment covers the raw surface, not just the 20:9 band.
        local vp0 = Art._vp
        Art.quad(self.hud, "wm_bg", -vp0.x, -vp0.y, vp0.rw, vp0.rh, { 0.0, 0.0, 0.0, 0.0 },
            { style = "image", image = self.config.worldmap_image, no_input = true })
        Art.remove_ids(self.hud, { "wm_title", "wm_dest" })
        -- Locations are buildings PAINTED on the map, so pos is a fraction of
        -- the ARTWORK (raw surface), not the letterboxed viewport — compensated
        -- coords cancel the vp offset exactly like the full-bleed bg above.
        -- ponytail: 3 authored nodes today; the plan is every painted house
        -- becomes a map eventually — this loop already scales to that.
        local function map_xy(md)
            return ((md.pos and md.pos[1]) or 0.5) * vp0.rw - vp0.x,
                ((md.pos and md.pos[2]) or 0.5) * vp0.rh - vp0.y
        end
        -- Route dots walk the authored journey polyline (config.worldmap_route,
        -- art fractions) at even spacing; without one, node-to-node lines.
        local pts = {}
        for _, p in ipairs(self.config.worldmap_route or {}) do
            pts[#pts + 1] = { p[1] * vp0.rw - vp0.x, p[2] * vp0.rh - vp0.y }
        end
        if #pts < 2 then
            for _, md in ipairs(self.maps) do
                local x, y = map_xy(md)
                pts[#pts + 1] = { x, y }
            end
        end
        local dot, spacing, carry = 0, S(34.0), 0.0
        for wi = 1, #pts - 1 do
            local ax, ay = pts[wi][1], pts[wi][2]
            local dx, dy = pts[wi + 1][1] - ax, pts[wi + 1][2] - ay
            local len = math.max(1.0e-3, math.sqrt(dx * dx + dy * dy))
            local t = carry
            while t < len and dot < 80 do
                dot = dot + 1
                local d = S(8.0)
                Art.quad(self.hud, "wm_dot_" .. dot, ax + dx * (t / len) - d * 0.5,
                    ay + dy * (t / len) - d * 0.5, d, d, { 0.32, 0.22, 0.10, 0.85 }, { no_input = true })
                t = t + spacing
            end
            carry = t - len
        end
        local tip -- at most one hover tooltip, drawn after the loop so it tops the markers
        for i, m in ipairs(self.maps) do
            local locked = i > max_map
            local sel = i == self.map_index
            local px, py = map_xy(m)
            -- Small frame sized to the little painted houses, not a region box.
            local hw, hh = sel and S(30.0) or S(26.0), sel and S(25.0) or S(22.0)
            Art.quad(self.hud, "wm_node_" .. i, px - hw, py - hh, hw * 2.0, hh * 2.0,
                { 0.0, 0.0, 0.0, 0.0 },
                { border = locked and { 0.35, 0.32, 0.28, 0.85 }
                    or (sel and { 1.0, 0.85, 0.30, 1.0 } or { 0.80, 0.62, 0.28, 0.95 }) })
            -- Bobbing gold pin above the frame = "this house is a map"; locked
            -- pins sit still and grey.
            local ps = sel and S(16.0) or S(12.0)
            local bob = locked and 0.0 or math.sin((self.realtime or 0.0) * 3.0 + i * 1.7) * S(5.0)
            Art.quad(self.hud, "wm_pin_" .. i, px - ps * 0.5, py - hh - S(14.0) + bob, ps, ps,
                locked and { 0.40, 0.38, 0.34, 0.95 }
                    or (sel and { 1.0, 0.85, 0.30, 1.0 } or { 0.95, 0.72, 0.25, 0.95 }),
                { border = { 0.25, 0.15, 0.05, 0.9 }, no_input = true })
            -- Bare small text (no plate box — a dozen stations would clutter
            -- the painting); width tracks the label so centring stays true.
            local nm = locked and T("%s - LOCKED", T(tostring(m.name))) or T(tostring(m.name))
            local nw = S(12.0) + #nm * S(6.5)
            Art.quad(self.hud, "wm_nm_" .. i, px - nw * 0.5, py + hh + S(2.0), nw, S(22.0),
                { 0.0, 0.0, 0.0, 0.0 }, { no_input = true, align_h = "center",
                  font_scale = 0.7, label = nm,
                  text_color = locked and { 0.78, 0.74, 0.66, 1.0 } or { 1.0, 0.90, 0.45, 1.0 } })
            local st = Art.widget_state(self.hud, "wm_node_" .. i)
            if st and st.hovered then tip = { m = m, i = i, px = px, py = py, hh = hh, locked = locked } end
        end
        -- Hover tooltip: full details for the pointed-at location, clamped on-screen.
        if tip then
            local md = tip.m
            local prev = (self.maps[tip.i - 1] and self.maps[tip.i - 1].name) or "the previous map"
            local lines = {
                T("%s  [Rank %s]%s", T(tostring(md.name)), tostring(md.rank or "?"),
                    tip.i <= (self.maps_cleared or 0) and T("   (cleared)") or ""),
                T(tostring(md.blurb or "")),
                T("%d waves   Boss: %s", md.waves or 5, T(tostring(md.boss_title or "?"))),
                T("Foes x%.2g HP  x%.2g DMG   Gold x%.2g",
                    md.hp_mult or 1.0, md.dps_mult or 1.0, md.gold_mult or 1.0),
                tip.locked
                    and T("LOCKED - clear %s", T(tostring(prev)))
                    or T("click to select, then ENTER to travel"),
            }
            local tw, th = S(430.0), S(128.0)
            local tx = clampn(tip.px - tw * 0.5, S(8.0), sw - tw - S(8.0))
            local ty = tip.py - tip.hh - S(44.0) - th
            if ty < S(8.0) then ty = tip.py + tip.hh + S(46.0) end
            Art.quad(self.hud, "wm_tip", tx, ty, tw, th, { 0.05, 0.04, 0.02, 0.95 },
                { border = tip.locked and { 0.45, 0.42, 0.38, 0.95 } or { 0.95, 0.80, 0.35, 0.95 },
                  no_input = true, font_scale = 0.85, label = table.concat(lines, "\n") })
        else
            Art.remove(self.hud, "wm_tip")
        end
        -- ENTER only — title / destination / gold stay off the painted map.
        Art.quad(self.hud, "wm_travel", sw * 0.5 - S(100.0), sh - S(64.0), S(200.0), S(48.0),
            { 0.12, 0.28, 0.14, 0.95 }, { border = { 0.4, 0.9, 0.5, 0.95 }, align_h = "center",
              font_scale = 1.05, label = T("ENTER") })
        local gear_size, gear_margin = S(28.0), S(10.0)
        Art.quad(self.hud, "wm_gear", vp0.rw - vp0.x - gear_size - gear_margin,
            gear_margin - vp0.y, gear_size, gear_size, { 0.0, 0.0, 0.0, 0.0 },
            { style = "image", image = V.ui.hud.gear, bring_to_front = true })
    elseif self._wm_drawn then
        -- One-shot teardown on leaving the map (not a per-frame remove storm).
        self._wm_drawn = nil
        local ids = { "wm_bg", "wm_title", "wm_dest", "wm_travel", "wm_tip", "wm_gear" }
        for i = 1, 16 do
            ids[#ids + 1] = "wm_node_" .. i
            ids[#ids + 1] = "wm_pin_" .. i
            ids[#ids + 1] = "wm_nm_" .. i
        end
        for k = 1, 80 do ids[#ids + 1] = "wm_dot_" .. k end
        Art.remove_ids(self.hud, ids)
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

    -- Wave-start draft overlay: progressive classes add their specialization cards
    -- beside two ordinary boons; every pick still consumes the one wave choice.
    if self.state == "draft" then
        local offer = self.draft_offer or {}
        local n = math.max(1, #offer)
        local gap = S(12.0)
        local cw = math.min(S(210.0), (sw - S(32.0) - (n - 1) * gap) / n)
        local ch = S(320.0)
        local row_w = n * (cw + gap) - gap
        local sx0 = sw * 0.5 - row_w * 0.5
        local cyc = sh * 0.5 - ch * 0.5 + S(10.0)
        -- Compact quads draw `label` (title/subtitle sit below a tall reserved
        -- art band and vanish on short panels — the shell learned this too).
        Art.quad(self.hud, "draft_title", sw * 0.5 - S(280.0), cyc - S(72.0), S(560.0), S(54.0),
            { 0.05, 0.05, 0.10, 0.94 }, { border = accent, no_input = true, bring_to_front = true,
              label = T("WAVE %d - CHOOSE A CARD  ([1-%d] or click)", self.wave_index or 1, n) })
        for i, cd in ipairs(offer) do
            local rank = cd.specialization
                and ((hero.specialization_ranks or {})[cd.specialization] or 0)
                or cd.rank_id and ((hero.upgrade_ranks or {})[cd.rank_id] or 0)
            local capped = cd.max_rank and rank >= cd.max_rank
            local rank_line = rank and (capped and T("RANK %d  MAX\n", rank)
                or T("RANK %d -> %d\n", rank, rank + 1)) or ""
            local desc = capped and T("Maximum specialization level reached.")
                or cd.specialization
                    and Balance.specialization_upgrade_text(cd.class_id or self.hero_class, cd.specialization, rank)
                or cd.rank_id and Balance.universal_upgrade_text(cd, rank)
                or cd.desc or ""
            local tags = {}
            for _, tag in ipairs(cd.tags or {}) do tags[#tags + 1] = T(tag) end
            Art.quad(self.hud, "draft_" .. i, sx0 + (i - 1) * (cw + gap), cyc, cw, ch,
                capped and { 0.07, 0.07, 0.09, 0.90 } or { 0.09, 0.10, 0.15, 0.97 }, {
                    style = "panel",
                    border = cd.accent or RARITY_COLOR[cd.rarity or "common"] or accent,
                    title = T(cd.name or cd.id), font_scale = 0.70, bring_to_front = true,
                    body = "[" .. i .. "]  " .. T(string.upper(cd.rarity or "common")) .. "\n" .. rank_line
                        .. (#tags > 0 and ("\n" .. table.concat(tags, " / ")) or "")
                        .. "\n\n" .. desc,
                })
        end
    else
        Art.remove_ids(self.hud, { "draft_title", "draft_1", "draft_2", "draft_3", "draft_4", "draft_5", "draft_6" })
    end

    -- Class pick overlay (run start): one card per class, click or number key.
    if self.state == "classpick" then
        local list = self.config.hero and self.config.hero.classes or {}
        local n = math.max(1, #list)
        local gap = S(12.0)
        local cw = math.min(S(232.0), (sw - S(32.0) - (n - 1) * gap) / n)
        local ch = S(286.0)
        local row_w = n * (cw + gap) - gap
        local sx0 = sw * 0.5 - row_w * 0.5
        local cyc = sh * 0.5 - ch * 0.5 + S(20.0)
        Art.quad(self.hud, "classpick_title", sw * 0.5 - S(280.0), cyc - S(78.0), S(560.0), S(58.0),
            { 0.05, 0.05, 0.10, 0.94 }, { border = accent, align_h = "center",
              label = (_G.ATH_I18N and _G.ATH_I18N.t("CHOOSE YOUR CLASS   [1-%d] or click", n))
                  or string.format("CHOOSE YOUR CLASS   [1-%d] or click", n), no_input = true })
        for i, c in ipairs(list) do
            local x = sx0 + (i - 1) * (cw + gap)
            local stat
            if c.attack == "melee" then
                stat = T("HP %d    DMG %d\nReach %.1f   Cleave %d\nMove %.1f",
                    c.hp_max or 0, c.dps or 0, c.attack_range or 0, c.cleave or 0, c.speed or 0)
            else
                stat = T("HP %d    DMG %d/shot\nRange %.0f   Shots %d\nFire %.2fs",
                    c.hp_max or 0, c.dps or 0, c.attack_range or 0, c.cleave or 0, c.fire_interval or 0.28)
            end
            local cname = T(c.name or c.id)
            local blurb = T(c.blurb or "")
            Art.quad(self.hud, "classpick_" .. i, x, cyc, cw, ch, { 0.09, 0.10, 0.15, 0.97 }, {
                border = c.accent or accent,
                title = cname,
                subtitle = T("[%d]  %s", i, T(string.upper(c.attack or "ranged"))),
                body = blurb .. "\n\n" .. stat,
            })
        end
    else
        Art.remove_ids(self.hud, { "classpick_title", "classpick_1", "classpick_2", "classpick_3",
            "classpick_4", "classpick_5", "classpick_6", "classpick_7" })
    end

    -- Legacy start-of-run specialization picker. Progressive classes such as
    -- Mage choose stackable specialization cards in the wave draft instead.
    if self.state == "specpick" then
        local class = self:active_class()
        local specs = class and class.specializations or {}
        local n = math.max(1, #specs)
        local gap = S(12.0)
        local cw = math.min(S(220.0), (sw - S(32.0) - (n - 1) * gap) / n)
        local ch = S(250.0)
        local row_w = n * (cw + gap) - gap
        local sx0 = sw * 0.5 - row_w * 0.5
        local cyc = sh * 0.5 - ch * 0.5 + S(20.0)
        Art.quad(self.hud, "specpick_title", sw * 0.5 - S(280.0), cyc - S(78.0), S(560.0), S(58.0),
            { 0.05, 0.05, 0.10, 0.94 }, { border = accent, align_h = "center",
              label = (_G.ATH_I18N and _G.ATH_I18N.t("CHOOSE SPECIALIZATION   [1-%d] or click", n))
                  or string.format("CHOOSE SPECIALIZATION   [1-%d] or click", n), no_input = true })
        for i, spec in ipairs(specs) do
            Art.quad(self.hud, "specpick_" .. i, sx0 + (i - 1) * (cw + gap), cyc, cw, ch,
                { 0.09, 0.10, 0.15, 0.97 }, {
                    border = spec.accent or accent,
                    title = T(spec.name),
                    subtitle = T("[%d]  ON HIT", i),
                    body = T(spec.desc or "") .. T("\n\nResource cost per hit: %d", spec.cost or 0),
                })
        end
    else
        Art.remove_ids(self.hud, { "specpick_title", "specpick_1", "specpick_2", "specpick_3", "specpick_4" })
    end

    -- Terminal banners (manual arena: click RETURN TO TOWN — R keybind is gone).
    local player_won = (self.side == "hero" and self.state == "hero_win") or (self.side == "horde" and self.state == "slain")
    if self.state == "slain" or self.state == "hero_win" then
        local title, body
        if self.state == "slain" then
            title = T(player_won and "VICTORY — the hero falls" or "DEFEAT — the hero falls")
            body = T(self.theme.lose_text or "The hero is slain.")
            if self.side == "horde" then body = T(self.theme.win_text or body) end
            if self.manual_hero then
                title = T("DEFEAT - the swarm takes you")
                local log = self.dmg_log or {}
                local killer = (#log > 0) and log[#log].src or "the swarm"
                local lines = { T("Killed by %s", T(killer)), "" }
                for i = #log, 1, -1 do
                    local e = log[i]
                    lines[#lines + 1] = T("%s   -%.0f HP   %.1fs before death",
                        T(e.src), e.dmg, math.max(0.0, (self.death_time or e.t) - e.t))
                end
                lines[#lines + 1] = ""
                lines[#lines + 1] = T("You fell before wave %d.", self.wave_index or 1)
                body = table.concat(lines, "\n")
            end
        else
            if self.manual_hero then
                title = T("VICTORY - five waves cleared")
                body = T("The arena is quiet for now.")
            else
                title = (player_won and "VICTORY — the pit ran dry" or "DEFEAT — the hero prevails")
                body = "The reserve is spent and the field is clear.\nPress R to run it back   -   M for menu"
            end
        end
        local col = player_won and { 0.10, 0.18, 0.10, 0.92 } or { 0.18, 0.06, 0.06, 0.92 }
        local bord = player_won and { 0.4, 0.95, 0.5, 0.95 } or { 0.95, 0.4, 0.36, 0.95 }
        local eh = (self.manual_hero and self.state == "slain") and S(230.0) or S(150.0)
        local ey = self.manual_hero and math.max(S(40.0), sh * 0.5 - eh * 0.5 - S(40.0)) or S(380.0)
        Art.quad(self.hud, "end", sw * 0.5 - S(300.0), ey, S(600.0), eh, col, {
            border = bord, title = T(title), body = T(body), no_input = true })
        if self.manual_hero then
            local bw, bh = S(360.0), S(56.0)
            Art.quad(self.hud, "end_town_btn", sw * 0.5 - bw * 0.5, ey + eh + S(18.0), bw, bh,
                { 0.20, 0.10, 0.28, 0.96 }, {
                    style = "button",
                    border = accent, accent = accent,
                    title = T("RETURN TO TOWN"),
                    text_color = { 0.96, 0.92, 1.0, 1.0 },
                    font_scale = 1.15, align_h = "center", align_v = "middle",
                    bring_to_front = true,
                })
        else
            Art.remove(self.hud, "end_town_btn")
        end
    else
        Art.remove(self.hud, "end")
        Art.remove(self.hud, "end_town_btn")
    end

    -- Virtual movement joystick (touch / mouse-drag), combat + loot walk.
    if self.manual_hero and (self.state == "combat" or self.state == "loot") and self._stick then
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
    Console.update(self)
    -- Gear hub / cheat console hold the world via settings.time_scale=0. Early-out
    -- so frame-based work (spawn drain) also stops; HUD/UI keep drawing. Still
    -- poll Escape so the gear menu can close (toggle_inventory → resume).
    if ATH_COMMON.world_frozen and ATH_COMMON.world_frozen(self) then
        Art.tick_iso_camera(0.0)
        self:update_input(0.0)
        -- Leftover combat floaters use bring_to_front + high z; clear so they
        -- don't paint over the gear hub / console.
        self:clear_damage_numbers()
        self:update_hud()
        return
    end

    self.realtime = self.realtime + dt
    if self._floor_tex_pending then
        self._floor_tex_pending = nil
        self:apply_map_floor()
    end
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
    self:update_orbit_blades(sim_dt) -- gated internally to combat; parks otherwise

    if self.state == "combat" then
        self.combat_time = self.combat_time + sim_dt
        self.round_t = self.round_t - sim_dt
        if self.use_flow_field then self:update_field(sim_dt) end -- else creeps beeline
        self:update_spawning(sim_dt)
        self:update_hero(sim_dt)
        self:update_creeps(sim_dt)
        self:update_tree_effects(sim_dt)
        self:update_minions(sim_dt)
        self:update_telegraphs(sim_dt)
        self:update_creep_projectiles(sim_dt)
        self:update_pickups(sim_dt)
        if self.config.hooks and self.config.hooks.on_combat_tick then self.config.hooks.on_combat_tick(self, sim_dt) end
        if self.manual_hero and self.state == "combat" and self:manual_wave_done() then
            if (self.wave_index or 1) >= self:total_rounds() then
                -- Final round: the BOSS'S OWN round (zero budget, so the rise
                -- telegraph fires immediately; it keeps manual_wave_done false
                -- until the boss dies). Bossless maps end on the last wave.
                local map = self:active_map()
                local boss_arch = map.boss or self.config.boss_archetype
                if boss_arch and not self.boss_spawned then
                    self:begin_loot("boss")
                else
                    self:begin_loot("map_clear")
                end
            else
                self:begin_loot("next_wave")
            end
        elseif (not self.manual_hero) and self.state == "combat" and self.reserve < 1.0 and self:count_alive() == 0 then
            self.state = "hero_win"
            self:set_flash("HERO PREVAILS")
            self:log(string.format("HERO PREVAILS round=%d kills=%d", self.round, self.kills))
        elseif self.state == "combat" and self.round_t <= 0.0 then
            if not self.manual_hero then self:begin_pause() end
        end
    elseif self.state == "loot" then
        -- Cleared arena: walk for item beacons. Gold already banked.
        self:update_hero(sim_dt)
        self:update_pickups(sim_dt)
        self:update_minions(sim_dt)
    elseif self.state == "pause" or self.state == "town" or self.state == "worldmap"
        or self.state == "classpick" or self.state == "specpick" or self.state == "draft" then
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
    -- Stable run seed for the Wave Director's deterministic per-wave mutator pick
    -- (independent of global math.random). ATH_DUEL_SEED pins it for smokes;
    -- otherwise a wall-clock seed so real runs get mutator variety.
    self.run_seed = seed or self.run_seed or (os and os.time and os.time()) or 1

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
    self.orbit_pool = nil
    self.coins = nil
    self.beacons = nil
    self.minions = nil
    self.dmgnums = nil
    self.boss_creep = nil
end

return Duel
