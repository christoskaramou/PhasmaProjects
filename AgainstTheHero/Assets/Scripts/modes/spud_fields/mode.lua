-- Spud Fields — a bright chunky-cartoon farm arena (DUEL mode).
--
-- Two files only: this one + characters.lua.
--   * meta   — what the menu shows: name, blurb, mini-map sketch, accent colour.
--   * config — handed to the shared Duel (ath_duel.lua): theme, arena, hero (a flat
--              2D sprite spud), the flat-sprite cast, role mapping, spawn tuning,
--              and HOOKS for this level's one signature mechanic.
--
-- Uses the DEFAULT iso camera (no cam_offset override) because the shared Duel's
-- sprite billboard is tuned to that rig (pitch 35.26 / yaw -45) — the same rig the
-- knight hero already faces.
--
-- Signature mechanic — FERTILE MUD. A handful of churned mud wallows sit in the
-- field; while the hero stands in one his footing bogs down (move_mult drops), so
-- the swarm can pile on. Pure horde-favouring environmental pressure via the
-- engine's transient hero.move_mult (mode-owned: re-set every tick, 1.0 = clear).

local Art  = ATH_COMMON.load_script("Scripts/shared/ath_art.lua",              "shared art",       _ENV)
local View = ATH_COMMON.load_script("Scripts/shared/ath_topdown_view.lua",     "top-down view",    _ENV)
local Spud = ATH_COMMON.load_script("Scripts/modes/spud_fields/characters.lua", "spud_fields cast", _ENV)

local C   = Spud.palette
local TEX = Spud.tex

-- ---- Mud tuning -------------------------------------------------------------
local MUD_SLOW   = 0.5    -- hero move multiplier while mired (0.5 = half speed)
local MUD_RADIUS = 3.0    -- world radius of each wallow

-- The wallow layout, as fractions of the arena (kept off the central hero start).
local MUD_SPOTS = {
    { 0.24, 0.30 }, { 0.76, 0.28 }, { 0.30, 0.74 }, { 0.72, 0.72 },
}

-- Build the static mud wallows once (they persist under groups.world across the
-- R-reset, so this runs in on_start, never on_reset). Stores world centres.
local function build_mud(D)
    local A = D.arena
    D.spud = D.spud or {}
    D.spud.mud = {}
    for i, f in ipairs(MUD_SPOTS) do
        local x = A.pad + (A.w - A.pad * 2) * f[1]
        local z = A.pad + (A.h - A.pad * 2) * f[2]
        Art.cylinder("Mud_" .. i, vec3(x, 0.06, z), vec3(MUD_RADIUS * 2.0, 0.04, MUD_RADIUS * 2.0),
            C.soil, D.groups.world, 0.5, TEX.mud)
        D.spud.mud[#D.spud.mud + 1] = { x = x, z = z, r = MUD_RADIUS }
    end
end

local function update_mud(D, dt)
    local hero = D.hero
    -- The engine never resets these transient multipliers, so the mode owns them:
    -- clear to 1.0 each tick, then re-apply the slow if the hero is in a wallow.
    hero.move_mult = 1.0
    if not D.spud or hero.dead then D.spud_mired = false; return end
    local mired = false
    for _, m in ipairs(D.spud.mud) do
        local dx, dz = hero.x - m.x, hero.z - m.z
        if dx * dx + dz * dz <= m.r * m.r then mired = true; break end
    end
    hero.move_mult = mired and MUD_SLOW or 1.0
    D.spud_mired = mired
end

-- ---- Mode contract ----------------------------------------------------------

return {
    meta = {
        id      = "spud_fields",
        name    = "Spud Fields",
        tagline = "a sunny farm overrun",
        blurb   = "A bright top-down farm arena. A heroic spud auto-fights a goofy garden horde — sprouts, seed-spitters, husk knights and a pumpkin brute — while crows dive from above. Churned mud wallows bog the hero down for the swarm.",
        side_hint = "horde",
        accent  = { 0.46, 0.78, 0.24, 0.95 },
        -- A sunny top-down sketch (normalized 0..1 rects).
        minimap = {
            bg = { 0.30, 0.54, 0.20, 1.0 },
            rects = {
                { 0.05, 0.05, 0.90, 0.90, { 0.42, 0.70, 0.27, 1.0 } },  -- grass field
                { 0.19, 0.25, 0.12, 0.12, { 0.34, 0.22, 0.13, 1.0 } },  -- mud wallows
                { 0.69, 0.23, 0.12, 0.12, { 0.34, 0.22, 0.13, 1.0 } },
                { 0.25, 0.69, 0.12, 0.12, { 0.34, 0.22, 0.13, 1.0 } },
                { 0.67, 0.67, 0.12, 0.12, { 0.34, 0.22, 0.13, 1.0 } },
                { 0.46, 0.44, 0.10, 0.10, { 0.84, 0.66, 0.40, 1.0 } },  -- the spud hero
                { 0.10, 0.10, 0.05, 0.05, { 0.96, 0.84, 0.28, 1.0 } },  -- spawn suns
                { 0.85, 0.85, 0.05, 0.05, { 0.96, 0.84, 0.28, 1.0 } },
            },
        },
    },

    config = {
        id    = "spud_fields",
        name  = "Spud Fields",
        theme = Spud.theme,
        arena = {
            width = 48, height = 36, pad = 2,
            -- Straight-down top-down rig (ath_topdown_view). ortho_size is divided by the
            -- art zoom channel, so ~66 frames the whole arena from directly above.
            ortho_size = 66.0,
            cam_offset = View.CAM_OFFSET,
        },
        hero = {
            hp_max = 96.0, dps = 21.0, cleave = 3, attack_range = 1.3,
            speed = 2.3, kite_speed = 2.85,
            -- The forced knight body quad is reskinned into this flat 2D spud by
            -- ath_topdown_view (engine left untouched); this is the texture it paints on.
            sprite_texture = Spud.tex.hero,
        },
        archetypes = Spud.archetypes,
        roles      = Spud.roles,
        spawn = {
            interval_start = 0.72, interval_min = 0.30,
            batch_start = 3, batch_max = 7,
            cap_start = 30, cap_max = 88,
            brute_after = 22.0,
        },
        reserve_start = 300.0,
        round_seconds = 14.0,

        -- Pre-build every creep rig at start/reset (incl. the flier the stock role
        -- warm misses) so primitives.* never runs mid-combat -> no spawn spikes.
        warm_pool_count = 0,
        prewarm_order = { "sprout", "husk_knight", "seed_spitter", "crow", "pumpkin_brute" },
        prewarm = { sprout = 50, seed_spitter = 14, husk_knight = 16, pumpkin_brute = 6, crow = 12 },

        -- Swarm of sprouts, with seed-spitters for ranged pressure, husk knights as
        -- the wall, the occasional diving crow, and a late pumpkin brute.
        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 11 == 0) then
                return "pumpkin_brute"
            end
            if D.spawn_counter % 7 == 0 then return "crow" end
            if D.spawn_counter % 5 == 0 then return "seed_spitter" end
            if D.spawn_counter % 3 == 0 then return "husk_knight" end
            return "sprout"
        end,

        hooks = {
            on_start = function(D)
                build_mud(D)
            end,

            -- on_reset can fire BEFORE on_start (Duel:start resets first), so guard
            -- D.spud; the wallows themselves persist under groups.world.
            on_reset = function(D)
                if D.hero then D.hero.move_mult = 1.0 end
                D.spud_mired = false
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
                update_mud(D, dt)
            end,

            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local mired = D.spud_mired == true
                local fill = mired and { 0.30, 0.18, 0.10, 0.9 } or { 0.10, 0.14, 0.06, 0.85 }
                Art.quad(D.hud, "spud_mire", 24.0, sh - 150.0, 360.0, 40.0, fill,
                    { border = { 0.46, 0.78, 0.24, 0.9 },
                      label = mired and "FERTILE MUD - the hero is bogged down!" or "FERTILE MUD - 4 wallows in the field" })
            end,
        },
    },
}
