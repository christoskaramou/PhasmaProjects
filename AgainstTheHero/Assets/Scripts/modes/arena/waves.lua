-- Wave Director — DATA + tiny director (Phase 1).
--
-- A content/direction layer over the existing spawner. It never changes total
-- spawn COST (the wave budget stays authoritative and `ATH_DUEL_RESERVE` still
-- pins it) — it only shapes WHEN / WHAT / WHERE:
--   * phases (opener / pressure / lull / finale) consume budget shares,
--   * curated archetype packs replace the flat auto_mix drip,
--   * formations (lane / pincer / ring) place spawns at scripted edges/angles,
--   * one seeded mutator per wave (wave 2+) bends existing knobs only.
--
-- The Duel drives the director through two seams, both nil-gated on
-- `config.wave_scripts` so every unscripted config (and boss rounds) stays
-- byte-identical:
--   * begin_manual_wave -> Waves.begin(D, wave) returns a director or nil,
--   * update_spawning    -> director:spawn_tick(D, headroom) (pcall'd),
--   * on_combat_tick      -> director:tick(D, dt) (mode hook, pcall'd).
--
-- No engine changes, no per-frame node allocation: spawns flow through the
-- existing telegraph + creep pool; the HUD chip reuses retained set_quad ids.

local Creep = ATH_COMMON.load_script("Scripts/shared/duel_creep.lua", "duel creep", _ENV)
local Art   = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)

local Waves = {}

-- ---------------------------------------------------------------------------
-- Mutators (wave 2+, one seeded pick per wave). Effects touch ONLY existing
-- knobs: `weights` biases the director's pack pick (spawn weights + the
-- already-tinted charger/exploder/flier archetypes carry their own colour),
-- and the scalar fields map to fields the Duel already reads:
--   elite_bonus     -> self.elite_wave_bonus (spawn_one elite roll)
--   drop_every_mult -> self.drop_every_mult  (maybe_drop_manual_gear cadence)
--   drop_floor      -> self.wave_drop_floor  (roll_drop_item min rarity)
--   coin_mult       -> self.coin_gold_mult   (coin value)
--   creep_speed/hp  -> self.buffs.speed/.hp  (per-creep add mods)
--   gold_find_add   -> hero.gold_find
-- `chip` is the HUD chip colour (drawn by mode.lua draw_hud).
-- ---------------------------------------------------------------------------
-- `desc` is the one-line, player-facing tooltip shown on icon hover (mode.lua).
Waves.mutators = {
    { id = "wasp_bloom", name = "WASP BLOOM", chip = { 0.96, 0.86, 0.30 },
      desc = "Fliers swarm the field. Beacons drop more often.",
      weights = { wasp = 3, crow = 2, stinger_drone = 2 }, drop_every_mult = 1.0 / 1.5 },
    { id = "goldrush", name = "GOLDRUSH", chip = { 1.0, 0.80, 0.22 },
      desc = "Enemies rush in faster, but spill more gold.",
      gold_find_add = 0.6, creep_speed = 0.9 },
    { id = "bloated", name = "BLOATED", chip = { 0.95, 0.56, 0.26 },
      desc = "Walking bombs everywhere. Loot floors to uncommon.",
      weights = { blast_bud = 3, brood_pod = 2 }, drop_every_mult = 1.0 / 1.4, drop_floor = "uncommon" },
    { id = "veterans", name = "VETERANS", chip = { 0.96, 0.83, 0.44 },
      desc = "More elites, and their drops floor higher.",
      elite_bonus = 0.18, drop_floor = "uncommon" },
    { id = "stampede", name = "STAMPEDE", chip = { 1.0, 0.50, 0.44 },
      desc = "Chargers stampede in — but they're frail.",
      weights = { ram_beetle = 3, beetle = 2 }, creep_hp = -4.0 },
    { id = "thick_hide", name = "THICK HIDE", chip = { 0.70, 0.86, 0.60 },
      desc = "Tougher enemies, but heavier coin purses.",
      weights = { husk_knight = 2, pumpkin_brute = 1 }, creep_hp = 10.0, coin_mult = 1.6 },
}

-- ---------------------------------------------------------------------------
-- Wave scripts (1-10). Each phase has a budget `share` (spawn phases only; a
-- lull spends nothing and runs on `seconds`), a `formation`, and a weighted
-- `pack`. Every spawn pack keeps a cheap floor archetype so the reserve always
-- drains to the wave-done threshold. Packs reference only archetypes that
-- Balance.build_monsters guarantees exist on every map. The boss round
-- (wave_index > wave count) is never scripted — the director is skipped there.
-- ---------------------------------------------------------------------------
Waves.scripts = {
    [1] = { phases = {
        { kind = "opener",   share = 0.30, formation = "lane",   pack = { sprout = 5 } },
        { kind = "pressure", share = 0.45, formation = "pincer", pack = { sprout = 3, beetle = 2 } },
        { kind = "finale",   share = 0.25, formation = "ring",   pack = { sprout = 2, beetle = 2, crow = 1 } },
    } },
    [2] = { phases = {
        { kind = "opener",   share = 0.25, formation = "ring",   pack = { crow = 3, wasp = 2 } },
        { kind = "pressure", share = 0.50, formation = "lane",   pack = { sprout = 3, beetle = 2, wasp = 1 } },
        { kind = "finale",   share = 0.25, formation = "pincer", pack = { beetle = 2, husk_knight = 1, sprout = 2 } },
    } },
    [3] = { phases = {
        { kind = "opener",   share = 0.25, formation = "pincer", pack = { beetle = 3, sprout = 2 } },
        { kind = "pressure", share = 0.40, formation = "ring",   pack = { beetle = 2, crow = 2, seed_spitter = 1 } },
        { kind = "lull",     seconds = 2.2 },
        { kind = "finale",   share = 0.35, formation = "lane",   pack = { husk_knight = 1, beetle = 2, sprout = 2 } },
    } },
    [4] = { phases = {
        { kind = "opener",   share = 0.22, formation = "lane",   pack = { sprout = 4, ram_beetle = 1 } },
        { kind = "pressure", share = 0.43, formation = "pincer", pack = { beetle = 2, ram_beetle = 2, seed_spitter = 1 } },
        { kind = "lull",     seconds = 2.2 },
        { kind = "finale",   share = 0.35, formation = "ring",   pack = { husk_knight = 1, ram_beetle = 1, beetle = 2, sprout = 1 } },
    } },
    [5] = { phases = {
        { kind = "opener",   share = 0.22, formation = "ring",   pack = { wasp = 3, crow = 2 } },
        { kind = "pressure", share = 0.43, formation = "pincer", pack = { beetle = 2, ram_beetle = 2, husk_knight = 1 } },
        { kind = "lull",     seconds = 2.2 },
        { kind = "finale",   share = 0.35, formation = "lane",   pack = { husk_knight = 2, ram_beetle = 1, beetle = 2, sprout = 1 } },
    } },
    [6] = { phases = {
        { kind = "opener",   share = 0.22, formation = "ring",   pack = { wasp = 3, crow = 2 } },
        { kind = "pressure", share = 0.43, formation = "pincer", pack = { beetle = 2, ram_beetle = 2, husk_knight = 1 } },
        { kind = "lull",     seconds = 2.4 },
        { kind = "finale",   share = 0.35, formation = "lane",   pack = { blast_bud = 2, husk_knight = 1, beetle = 2, sprout = 1 } },
    } },
    [7] = { phases = {
        { kind = "opener",   share = 0.22, formation = "lane",   pack = { ram_beetle = 3, beetle = 2 } },
        { kind = "pressure", share = 0.43, formation = "ring",   pack = { beetle = 2, blast_bud = 1, seed_spitter = 2 } },
        { kind = "lull",     seconds = 2.4 },
        { kind = "finale",   share = 0.35, formation = "pincer", pack = { husk_knight = 2, ram_beetle = 2, sprout = 1 } },
    } },
    [8] = { phases = {
        { kind = "opener",   share = 0.22, formation = "pincer", pack = { husk_knight = 2, beetle = 3 } },
        { kind = "pressure", share = 0.43, formation = "ring",   pack = { blast_bud = 2, ram_beetle = 2, wasp = 1 } },
        { kind = "lull",     seconds = 2.4 },
        { kind = "finale",   share = 0.35, formation = "lane",   pack = { pumpkin_brute = 1, husk_knight = 2, beetle = 2 } },
    } },
    [9] = { phases = {
        { kind = "opener",   share = 0.22, formation = "ring",   pack = { crow = 3, wasp = 3 } },
        { kind = "pressure", share = 0.43, formation = "pincer", pack = { ram_beetle = 3, blast_bud = 2, beetle = 2 } },
        { kind = "lull",     seconds = 2.6 },
        { kind = "finale",   share = 0.35, formation = "ring",   pack = { pumpkin_brute = 1, husk_knight = 2, blast_bud = 1, beetle = 1 } },
    } },
    [10] = { phases = {
        { kind = "opener",   share = 0.22, formation = "lane",   pack = { ram_beetle = 3, husk_knight = 2 } },
        { kind = "pressure", share = 0.43, formation = "pincer", pack = { blast_bud = 3, ram_beetle = 2, beetle = 2 } },
        { kind = "lull",     seconds = 2.6 },
        { kind = "finale",   share = 0.35, formation = "ring",   pack = { pumpkin_brute = 2, husk_knight = 2, blast_bud = 2, sprout = 1 } },
    } },
}

-- Deterministic small hash -> integer. Pure arithmetic (no global RNG reseed),
-- so the pick is stable per (run_seed, wave, k). k distinguishes the successive
-- picks when a wave stacks more than one mutator.
local function wave_hash(seed, wave, k)
    local x = (math.floor(seed) % 100000) * 131 + wave * 977 + (k or 0) * 613 + 7
    x = (x * 1103515245 + 12345) % 2147483648
    return math.floor(x / 65536)
end

-- Mutator stacking ramp: waves 2-4 = 1, 5-7 = up to 2, 8+ = up to 3. A wave
-- script may override with `mutator_count`. Boss rounds/wave 1 = 0.
local function ramp_count(wave)
    if wave >= 8 then return 3 elseif wave >= 5 then return 2 elseif wave >= 2 then return 1 end
    return 0
end

local RARITY_RANK = { common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }

-- ---------------------------------------------------------------------------
-- Director instance
-- ---------------------------------------------------------------------------
local Dir = {}
Dir.__index = Dir

-- Weighted, affordability-aware pack pick (mirrors pick_affordable_auto_archetype:
-- never enqueue an unaffordable archetype or the reserve stalls above wave-done).
function Dir:pick(D, pack)
    local reserve = D.reserve or 0.0
    local pool, total = {}, 0.0
    local function add(id, w)
        local cost = Creep.threat_cost(id)
        if cost and cost <= reserve and w and w > 0 then
            pool[#pool + 1] = { id = id, w = w }
            total = total + w
        end
    end
    for id, w in pairs(pack) do add(id, w) end
    if self.weights then for id, w in pairs(self.weights) do add(id, w) end end
    if total <= 0.0 then return D:role_archetype("swarm") end
    local r = math.random() * total
    for _, e in ipairs(pool) do
        r = r - e.w
        if r <= 0.0 then return e.id end
    end
    return pool[#pool].id
end

-- Formation spawn point for the i-th scripted spawn of the wave. Edges/angles
-- only; hugs the walls like pick_spawn_point (clearance 1.25).
function Dir:point(D, i)
    local A = D.arena
    local c = 1.25
    local minx, maxx = A.pad + c, A.w - A.pad - 1.0 - c
    local minz, maxz = A.pad + c, A.h - A.pad - 1.0 - c
    local ph = self.phases[self.phase_i] or self.phases[#self.phases]
    local form = (ph and ph.formation) or "lane"
    if form == "ring" then
        -- Golden-ratio walk around the perimeter ellipse: even, non-repeating.
        local ang = ((i * 0.61803398875) % 1.0) * 6.2831853
        local cx, cz = (minx + maxx) * 0.5, (minz + maxz) * 0.5
        return { x = cx + math.cos(ang) * (maxx - minx) * 0.5,
                 y = cz + math.sin(ang) * (maxz - minz) * 0.5 }
    elseif form == "pincer" then
        local x = (i % 2 == 0) and minx or maxx -- alternate west/east edges
        local z = minz + ((i * 0.37) % 1.0) * (maxz - minz)
        return { x = x, y = z }
    else -- lane: a single edge, spread across it (edge alternates per wave)
        local x = minx + ((i * 0.29) % 1.0) * (maxx - minx)
        local z = self.lane_north and minz or maxz
        return { x = x, y = z }
    end
end

-- Advance phases: spawn phases end when their budget share is consumed; a lull
-- runs on its timer. The finale (last phase) never advances.
function Dir:advance(D, dt)
    local ph = self.phases[self.phase_i]
    if not ph then return end
    if ph.kind == "lull" then
        self.lull_t = (self.lull_t or ph.seconds or 2.2) - (dt or 0.0)
        if self.lull_t <= 0.0 and self.phase_i < #self.phases then
            self.phase_i = self.phase_i + 1
            self.phase_start_reserve = D.reserve
        end
        return
    end
    if self.phase_i >= #self.phases then return end
    local total = D.reserve_start or 1.0
    local start = self.phase_start_reserve or total
    if (start - (D.reserve or 0.0)) >= (ph.share or 1.0) * total then
        self.phase_i = self.phase_i + 1
        self.phase_start_reserve = D.reserve
        local nph = self.phases[self.phase_i]
        if nph and nph.kind == "lull" then self.lull_t = nph.seconds or 2.2 end
    end
end

-- Spawn cadence hook (called from Duel:update_spawning when spawn_t fires).
-- Enqueues the same volume the legacy drip would (batch_size, cap by headroom),
-- but with scripted archetypes + formation points. Suppressed during a lull.
function Dir:spawn_tick(D, headroom)
    local ph = self.phases[self.phase_i] or self.phases[#self.phases]
    if ph and ph.kind == "lull" then return end
    local pack = (ph and ph.pack) or self.last_pack or { sprout = 1 }
    self.last_pack = pack
    local n = math.min(D:batch_size(), headroom)
    local q = D.spawn_queue or {}
    D.spawn_queue = q
    for _ = 1, n do
        self.spawn_n = self.spawn_n + 1
        q[#q + 1] = { arch = self:pick(D, pack), free = false, spawn = self:point(D, self.spawn_n) }
    end
end

-- Per-frame hook (mode on_combat_tick): phase timing + lull coin magnet.
function Dir:tick(D, dt)
    self:advance(D, dt)
    local ph = self.phases[self.phase_i]
    if ph and ph.kind == "lull" and D.coins and D.hero and not D.hero.dead then
        local hx, hz = D.hero.x or 0.0, D.hero.z or 0.0
        local pull = 6.0 * (dt or 0.0)
        for _, e in ipairs(D.coins) do
            if e.active and not e.essence then
                local dx, dz = hx - (e.x or 0.0), hz - (e.z or 0.0)
                local d = math.sqrt(dx * dx + dz * dz) + 1.0e-4
                e.x = e.x + dx / d * pull
                e.z = e.z + dz / d * pull
                if Art.valid(e.node) then e.node:set_position(vec3(e.x, 0.22, e.z)) end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Entry point (called from Duel:begin_manual_wave for non-boss scripted waves).
-- Applies the seeded mutator's knobs on the Duel, folds it into the wave banner,
-- and returns the director instance (or nil to fall back to the legacy drip).
-- The Duel resets the per-wave mutator knobs before calling this.
-- ---------------------------------------------------------------------------
function Waves.begin(D, wave)
    -- Spud Fields (rank I) is the untouched baseline: the director arms from
    -- rank II onward. This eases new players into the plain spawner on the first
    -- map AND keeps the unscripted (legacy-drip) path directly verifiable there.
    if ((D.active_map and D:active_map()) or {}).id == "spud_fields" then return nil end

    local script = Waves.scripts[wave]
    if not script then return nil end

    local dir = setmetatable({
        wave = wave, phases = script.phases, phase_i = 1,
        spawn_n = 0, lane_north = (wave % 2 == 0), mutators = {},
    }, Dir)

    -- Seeded, distinct multi-pick of this wave's mutators (stable per run/wave).
    local seed = D.run_seed or 1
    local count = math.min(script.mutator_count or ramp_count(wave), #Waves.mutators)
    -- k is 0-based so the first pick reuses the original (k=0) hash: a wave's
    -- primary mutator is unchanged from the single-pick era (seed-stable repro).
    local used, picked = {}, {}
    for k = 0, count - 1 do
        local avail = {}
        for i = 1, #Waves.mutators do if not used[i] then avail[#avail + 1] = i end end
        if #avail == 0 then break end
        local idx = avail[(wave_hash(seed, wave, k) % #avail) + 1]
        used[idx] = true
        picked[#picked + 1] = Waves.mutators[idx]
    end
    dir.mutators = picked

    if #picked > 0 then
        -- Compose knobs across the stack: weight biases MERGE (sum), multipliers
        -- MULTIPLY, additive chances/stats SUM (capped), rarity floor = highest.
        local weights = nil
        local elite_bonus, gold_find, creep_speed, creep_hp = 0.0, 0.0, 0.0, 0.0
        local drop_mult, coin_mult = 1.0, 1.0
        local drop_floor, floor_rank = nil, 0
        local names, ids = {}, {}
        for _, m in ipairs(picked) do
            names[#names + 1] = m.name
            ids[#ids + 1] = m.id
            if m.weights then
                weights = weights or {}
                for id, w in pairs(m.weights) do weights[id] = (weights[id] or 0) + w end
            end
            if m.elite_bonus then elite_bonus = elite_bonus + m.elite_bonus end
            if m.drop_every_mult then drop_mult = drop_mult * m.drop_every_mult end
            if m.coin_mult then coin_mult = coin_mult * m.coin_mult end
            if m.creep_speed then creep_speed = creep_speed + m.creep_speed end
            if m.creep_hp then creep_hp = creep_hp + m.creep_hp end
            if m.gold_find_add then gold_find = gold_find + m.gold_find_add end
            if m.drop_floor and (RARITY_RANK[m.drop_floor] or 0) > floor_rank then
                floor_rank, drop_floor = RARITY_RANK[m.drop_floor], m.drop_floor
            end
        end
        dir.weights = weights
        if elite_bonus > 0.0 then D.elite_wave_bonus = math.min(0.5, elite_bonus) end
        if drop_mult ~= 1.0 then D.drop_every_mult = math.max(0.35, drop_mult) end
        if coin_mult ~= 1.0 then D.coin_gold_mult = coin_mult end
        if drop_floor then D.wave_drop_floor = drop_floor end
        if creep_speed ~= 0.0 and D.buffs then D.buffs.speed = creep_speed end
        if creep_hp ~= 0.0 and D.buffs then D.buffs.hp = creep_hp end
        if gold_find ~= 0.0 and D.hero then D.hero.gold_find = (D.hero.gold_find or 1.0) + gold_find end
        if #picked == 1 then
            D:set_flash("WAVE %d - %s", wave, names[1])
        else
            D:set_flash("WAVE %d - MUTATORS: %s", wave, table.concat(names, " + "))
        end
        D:log(string.format("wave director wave=%d mutators=%s phases=%d",
            wave, table.concat(ids, ","), #script.phases))
    else
        D:log(string.format("wave director wave=%d mutator=none phases=%d", wave, #script.phases))
    end
    return dir
end

return Waves
