-- Alien Hive — a glowing chunky-cartoon alien arena (DUEL mode).
--
-- Two files only: this one + characters.lua.
--   * meta   — what the menu shows: name, blurb, mini-map sketch, accent colour.
--   * config — handed to the shared Duel (ath_duel.lua): theme, arena, hero (a flat
--              2D sprite vanguard), the flat-sprite cast, role mapping, spawn
--              tuning, and HOOKS for this level's one signature mechanic.
--
-- Uses the DEFAULT iso camera (no cam_offset override) so the shared Duel's sprite
-- billboard (pitch 35.26 / yaw -45) faces the cast correctly.
--
-- Signature mechanic — ACID SUMPS. Pools of hive-acid bubble on the floor; while
-- the hero stands in one the acid eats through his armour (ignore_armor DoT) and
-- his footing slows (move_mult). Horde-favouring pressure via the hazard API
-- (D:apply_hero_damage) and the engine's mode-owned transient hero.move_mult.

local Art  = ATH_COMMON.load_script("Scripts/shared/ath_art.lua",              "shared art",       _ENV)
local View = ATH_COMMON.load_script("Scripts/shared/ath_topdown_view.lua",     "top-down view",    _ENV)
local Hive = ATH_COMMON.load_script("Scripts/modes/alien_hive/characters.lua", "alien_hive cast",  _ENV)

local C   = Hive.palette
local TEX = Hive.tex

-- ---- Acid tuning ------------------------------------------------------------
local ACID_DPS    = 10.0   -- armour-ignoring damage/s while standing in a sump
local ACID_SLOW   = 0.7    -- hero move multiplier while in the acid
local ACID_RADIUS = 3.0    -- world radius of each sump

-- Sump layout as fractions of the arena (kept off the central hero start).
local ACID_SPOTS = {
    { 0.22, 0.28 }, { 0.78, 0.30 }, { 0.50, 0.18 }, { 0.28, 0.76 }, { 0.74, 0.74 },
}

local function build_acid(D)
    local A = D.arena
    D.hive = D.hive or {}
    D.hive.sumps = {}
    for i, f in ipairs(ACID_SPOTS) do
        local x = A.pad + (A.w - A.pad * 2) * f[1]
        local z = A.pad + (A.h - A.pad * 2) * f[2]
        local node = Art.cylinder("Acid_" .. i, vec3(x, 0.06, z), vec3(ACID_RADIUS * 2.0, 0.04, ACID_RADIUS * 2.0),
            C.acid, D.groups.world, 1.1, TEX.acid)
        D.hive.sumps[#D.hive.sumps + 1] = { x = x, z = z, r = ACID_RADIUS, node = node }
    end
end

local function update_acid(D, dt)
    local hero = D.hero
    -- Mode owns the transient slow: clear to 1.0 each tick, re-apply if in a sump.
    hero.move_mult = 1.0
    if not D.hive or hero.dead then D.hive_burning = false; return end
    local burning = false
    for _, s in ipairs(D.hive.sumps) do
        local dx, dz = hero.x - s.x, hero.z - s.z
        if dx * dx + dz * dz <= s.r * s.r then burning = true; break end
    end
    if burning then
        hero.move_mult = ACID_SLOW
        D:apply_hero_damage(ACID_DPS * dt, { ignore_armor = true, flash = "ACID BURN!" })
        if not D.hive_burning then
            Art.burst("hive_acid_hero", vec3(hero.x, 0.4, hero.z),
                { preset = "enemy_take", count = 6, life_max = 0.18, spawn_radius = 0.35, noise_strength = 3.0, size_max = 0.16 })
        end
    end
    D.hive_burning = burning
end

-- ---- Mode contract ----------------------------------------------------------

return {
    meta = {
        id      = "alien_hive",
        name    = "Alien Hive",
        tagline = "a glowing brood arena",
        blurb   = "A bio-luminescent alien hive. An armoured vanguard auto-fights a cute-grotesque brood — grubs, spore-floaters, armoured carapaces and a towering behemoth — while stingers swoop in. Bubbling acid sumps eat the hero's armour and slow him.",
        side_hint = "horde",
        accent  = { 0.62, 0.95, 0.24, 0.95 },
        minimap = {
            bg = { 0.16, 0.07, 0.22, 1.0 },
            rects = {
                { 0.05, 0.05, 0.90, 0.90, { 0.26, 0.12, 0.34, 1.0 } },  -- hive floor
                { 0.17, 0.23, 0.11, 0.11, { 0.62, 0.95, 0.24, 1.0 } },  -- acid sumps
                { 0.72, 0.25, 0.11, 0.11, { 0.62, 0.95, 0.24, 1.0 } },
                { 0.45, 0.13, 0.11, 0.11, { 0.62, 0.95, 0.24, 1.0 } },
                { 0.23, 0.71, 0.11, 0.11, { 0.62, 0.95, 0.24, 1.0 } },
                { 0.69, 0.69, 0.11, 0.11, { 0.62, 0.95, 0.24, 1.0 } },
                { 0.46, 0.44, 0.10, 0.10, { 0.62, 0.70, 0.82, 1.0 } },  -- the vanguard hero
            },
        },
    },

    config = {
        id    = "alien_hive",
        name  = "Alien Hive",
        theme = Hive.theme,
        arena = {
            width = 48, height = 36, pad = 2,
            -- Straight-down top-down rig (ath_topdown_view). ortho_size is divided by the
            -- art zoom channel, so ~66 frames the whole arena from directly above.
            ortho_size = 66.0,
            cam_offset = View.CAM_OFFSET,
        },
        hero = {
            hp_max = 100.0, dps = 22.0, cleave = 3, attack_range = 1.3,
            speed = 2.35, kite_speed = 2.9,
            -- The forced knight body quad is reskinned into this flat 2D vanguard by
            -- ath_topdown_view (engine left untouched); this is the texture it paints on.
            sprite_texture = Hive.tex.hero,
        },
        archetypes = Hive.archetypes,
        roles      = Hive.roles,
        spawn = {
            interval_start = 0.70, interval_min = 0.30,
            batch_start = 3, batch_max = 7,
            cap_start = 32, cap_max = 92,
            brute_after = 22.0,
        },
        reserve_start = 320.0,
        round_seconds = 14.0,
        kill_fx_budget_per_frame = 4,

        -- Pre-build every creep rig at start/reset (incl. the flier the stock role
        -- warm misses) so primitives.* never runs mid-combat -> no spawn spikes.
        warm_pool_count = 0,
        prewarm_order = { "grub", "carapace", "spore_floater", "stinger", "behemoth" },
        prewarm = { grub = 56, spore_floater = 18, carapace = 24, behemoth = 8, stinger = 18 },

        -- Swarms of grubs, spore-floaters for ranged pressure, carapaces as the
        -- wall, swooping stingers, and a late behemoth.
        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 11 == 0) then
                return "behemoth"
            end
            if D.spawn_counter % 7 == 0 then return "stinger" end
            if D.spawn_counter % 5 == 0 then return "spore_floater" end
            if D.spawn_counter % 3 == 0 then return "carapace" end
            return "grub"
        end,

        hooks = {
            on_start = function(D)
                build_acid(D)
            end,

            -- on_reset can fire BEFORE on_start; guard D.hive. The sumps persist
            -- under groups.world, so only transient state is cleared here.
            on_reset = function(D)
                if D.hero then D.hero.move_mult = 1.0 end
                D.hive_burning = false
                D._bv_dressed = nil   -- pool was cleared; forget dressed-body handles
                View.prewarm(D)       -- rebuild the creep pool up front
            end,

            on_prewarm_spawn = function(D, creep)
                View.on_spawn(D, creep)
            end,

            on_spawn = function(D, creep)
                View.on_spawn(D, creep)
            end,

            on_combat_tick = function(D, dt)
                View.tick(D)        -- lay hero + creep sprites flat & head-up (top-down)
                update_acid(D, dt)
            end,

            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local burning = D.hive_burning == true
                local fill = burning and { 0.22, 0.30, 0.06, 0.92 } or { 0.10, 0.06, 0.14, 0.85 }
                Art.quad(D.hud, "hive_acid", 24.0, sh - 150.0, 380.0, 40.0, fill,
                    { border = { 0.62, 0.95, 0.24, 0.9 },
                      label = burning and "ACID SUMP - the hero is melting!" or "ACID SUMPS - 5 pools bubbling" })
            end,
        },
    },
}
