-- Bloodtide — a drowned chasm where a tide of dark blood climbs from below.
--
-- THE TWIST ON THE CONTRACT (like catacombs/abyss, the same shared Duel re-staged
-- in 2D). This is a SIDE-SCROLLER: the arena's X axis is the cavern read left->
-- right, the Z axis is its shallow depth, and a mode-owned Y-up layer carries the
-- one thing the brief lives on — a RISING TIDE. The camera drops to a low side-on
-- angle and tracks the hero. He still auto-fights and the drowned still rush him;
-- we re-skin the stage and add one bespoke hazard, exactly as the guide prescribes.
--
-- Signature mechanic — THE TIDE. A level of dark blood/ichor climbs the cavern at
-- a base rate that ACCELERATES every minute of the 5-minute run. The hero must
-- stay ABOVE it: he rides FLOATING DEBRIS PLATFORMS at varying heights (some are
-- anchored ledges, some ride the surface itself). Where the blood rises over his
-- footing he is TOUCHED — heavy damage per second; sink in past his head and he
-- DROWNS — an instant kill. The horde can pour the tide higher: every character
-- card the Horde SACRIFICES (a back-face creature play) surges the level +15%
-- instantly, and every Tide Caller that dies spills a smaller surge. Pure pressure
-- on the hero; a clean demo of the hazard API (D:apply_hero_damage) and of mode-
-- owned Y physics. Everything is ath_art primitives, self-lit, and texture-ready;
-- the seamless cliff/platform/tide-surface PNGs are wired live (see
-- tools/gen_textures_bloodtide.py).

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Bt  = ATH_COMMON.load_script("Scripts/modes/bloodtide/characters.lua", "bloodtide characters", _ENV)

-- ---- Tide tuning -----------------------------------------------------------
local TIDE_FLOOR    = -1.6     -- world Y the blood starts at (below the deck)
local TIDE_TOP      = 6.6      -- world Y the blood caps at (the cavern brim)
local TIDE_RANGE    = TIDE_TOP - TIDE_FLOOR
local TIDE_BASE     = 0.105    -- base climb, world-units/sec (minute 0)
local TIDE_ACCEL_PM = 0.55     -- each elapsed minute adds this fraction of base
local RUN_SECONDS   = 300.0    -- the 5-minute run the HUD counts down
local SURGE_CARD    = 0.15     -- Horde sacrifice: +15% of the full range, instant
local SURGE_CALLER  = 0.07     -- a slain Tide Caller spills +7% of the range

-- ---- Drowning tuning -------------------------------------------------------
local TIDE_DPS      = 34.0     -- heavy damage/sec while the blood touches the hero
local DROWN_DEPTH   = 0.95     -- submerged this far past his footing = he drowns
local TIDE_FLASH_CD = 0.9      -- min seconds between "THE TIDE!" warnings

-- ---- Stage tuning ----------------------------------------------------------
local FLOAT_RIDE    = 0.45     -- a floating platform's deck sits this far above the surface
local PARALLAX      = 0.7      -- backdrop world-shift per hero unit (0=locked, 1=glued)

-- Floating debris platforms across the cavern. `fixed` ledges hang at a set
-- height (safe until the blood climbs to them); `floating` rafts ride the surface
-- (always just above the blood, but always within its reach). x = centre, w =
-- span, y = anchored deck height (fixed only).
local PLATFORMS = {
    { x = 6,  w = 7.0, y = 0.0,  kind = "fixed" },     -- the starting jetty
    { x = 15, w = 4.0, y = 1.4,  kind = "fixed" },
    { x = 22, w = 3.6, y = 0.0,  kind = "floating" },
    { x = 29, w = 4.4, y = 2.6,  kind = "fixed" },
    { x = 37, w = 3.4, y = 0.0,  kind = "floating" },
    { x = 44, w = 4.2, y = 1.8,  kind = "fixed" },
    { x = 51, w = 3.4, y = 3.4,  kind = "fixed" },     -- the high ledge — last refuge
    { x = 58, w = 5.0, y = 0.0,  kind = "floating" },
}

-- ---------------------------------------------------------------------------
-- Platforms — built once in on_start; floating rafts re-seated on the surface
-- every tick. Logical `top` is what the hero stands on; the node tracks it.
-- ---------------------------------------------------------------------------

local function build_platforms(D)
    local e = D.bloodtide
    e.platforms = {}
    local g = D.groups.world
    local cz = D.arena.h * 0.5
    for i, P in ipairs(PLATFORMS) do
        local top = (P.kind == "fixed") and P.y or (e.level + FLOAT_RIDE)
        -- Sodden driftwood deck (platform.png tiles across it).
        local node = Art.cube("Bt_Platform_" .. i, vec3(P.x, top, cz),
            vec3(P.w, 0.34, 2.0), Bt.palette.wood, g, 0.55, Bt.tex.platform)
        -- A pale lip so the deck edge reads against the dark.
        local lip = Art.cube("Bt_PlatLip_" .. i, vec3(P.x, top + 0.20, cz + 1.0),
            vec3(P.w, 0.10, 0.18), Bt.palette.bone, g, 0.5)
        e.platforms[i] = {
            x = P.x, w = P.w, kind = P.kind, base_y = P.y, top = top,
            node = node, lip = lip, seed = P.x * 1.3,
        }
    end
end

-- Re-seat floating rafts on the surface (+a gentle bob) and update their `top`.
local function update_platforms(D, dt)
    local e = D.bloodtide
    local cz = D.arena.h * 0.5
    for _, p in ipairs(e.platforms) do
        if p.kind == "floating" then
            local bob = 0.06 * math.sin(D.realtime * 1.8 + p.seed)
            p.top = e.level + FLOAT_RIDE + bob
        end
        if Art.valid(p.node) then p.node:set_position(vec3(p.x, p.top, cz)) end
        if Art.valid(p.lip) then p.lip:set_position(vec3(p.x, p.top + 0.20, cz + 1.0)) end
    end
end

-- The footing under a world-x: the highest platform deck spanning it, else the
-- submerged stone floor at y = 0 (which the tide drowns the moment it climbs).
local function footing_at(D, x)
    local best = 0.0
    for _, p in ipairs(D.bloodtide.platforms) do
        if math.abs(x - p.x) <= p.w * 0.5 and p.top > best then best = p.top end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- The tide plane — one broad blood quad we lift to `level` each tick, roiling.
-- ---------------------------------------------------------------------------

local function build_tide(D)
    local e = D.bloodtide
    local A = D.arena
    local g = D.groups.world
    -- The surface slab (tide_surface_sheet.png paints the roiling crimson).
    e.surface = Art.cube("Bt_Tide_Surface", vec3(A.w * 0.5, e.level, A.h * 0.5),
        vec3(A.w + 4.0, 0.30, A.h + 4.0), Bt.palette.blood, g, 1.1, Bt.tex.tide)
    -- A dark body of blood hanging below the surface so the deep reads as volume.
    e.body = Art.cube("Bt_Tide_Body", vec3(A.w * 0.5, e.level - 4.0, A.h * 0.5),
        vec3(A.w + 4.0, 8.0, A.h + 4.0), Bt.palette.dark, g, 0.45)
end

local function update_tide_visual(D)
    local e = D.bloodtide
    local A = D.arena
    if Art.valid(e.surface) then
        e.surface:set_position(vec3(A.w * 0.5, e.level, A.h * 0.5))
        -- Roil: a slow emissive swell so the surface looks alive and hungry.
        local roil = 1.0 + 0.35 * math.sin(D.realtime * 2.2) + 0.15 * math.sin(D.realtime * 5.7)
        material.set(e.surface, "emissive", vec3(0.55 * roil, 0.0, 0.0))
    end
    if Art.valid(e.body) then e.body:set_position(vec3(A.w * 0.5, e.level - 4.0, A.h * 0.5)) end
end

-- Add a surge of tide (a fraction of the full range), clamped to the brim, with
-- a splatter burst at the surface to sell the impact.
local function surge_tide(D, frac, flash)
    local e = D.bloodtide
    if not e then return end
    e.level = math.min(TIDE_TOP, e.level + frac * TIDE_RANGE)
    local A = D.arena
    Art.burst("ath_bloodtide_surge_" .. tostring(e.counter), vec3(D.hero.x, e.level + 0.4, A.h * 0.5),
        { preset = "hero_take", count = 24, life_max = 0.45, spawn_radius = 3.0, noise_strength = 5.0, size_max = 0.30 })
    e.counter = e.counter + 1
    if flash then D:set_flash(flash) end
end

-- ---------------------------------------------------------------------------
-- Hero vs. the tide — footing, drowning, and the Y-lift that rides the decks.
-- ---------------------------------------------------------------------------

local function update_hero_vs_tide(D, dt)
    local e = D.bloodtide
    local hero = D.hero
    if hero.dead then return end

    local foot = footing_at(D, hero.x)
    local submersion = e.level - foot

    if submersion >= DROWN_DEPTH then
        -- Under for good — the red closes over his head.
        D:apply_hero_damage(9999.0, { ignore_armor = true, flash = "DROWNED!" })
    elseif submersion > 0.0 then
        -- Touched by the tide: heavy, continuous scald. Warn on a cooldown so the
        -- flash reads as menace, not spam.
        D:apply_hero_damage(TIDE_DPS * dt)
        e.flash_cd = e.flash_cd - dt
        if e.flash_cd <= 0.0 then
            D:set_flash("THE TIDE!")
            e.flash_cd = TIDE_FLASH_CD
        end
        if not e.was_wet then
            Art.burst("ath_bloodtide_splash", vec3(hero.x, e.level + 0.2, hero.z),
                { preset = "hero_take", count = 16, life_max = 0.35, spawn_radius = 0.6, noise_strength = 4.0, size_max = 0.22 })
        end
        e.was_wet = true
    else
        e.was_wet = false
    end

    -- Ride the deck: lift the hero to his footing (on_combat_tick runs AFTER
    -- update_hero, so this is the final say on his Y). Past the lip he sinks into
    -- the blood — a visible plunge as he goes under.
    if Art.valid(hero.root) then
        local sink = math.max(0.0, math.min(submersion, DROWN_DEPTH)) * 0.6
        local hy = foot - sink
        hero.root:set_position(vec3(hero.x, hy, hero.z))
        hero.root:set_rotation(vec3(0.0, math.deg(hero.facing or 0.0), 0.0))
        local ws = hero.world_scale or 1.0
        hero.root:set_scale(vec3(ws, ws, ws))
    end
end

-- ---------------------------------------------------------------------------
-- Tide Callers — track each that spawns; when a tracked one dies, surge.
-- (Dead creeps are pruned the same tick, but our stored ref keeps `alive=false`.)
-- ---------------------------------------------------------------------------

local function check_callers(D)
    local e = D.bloodtide
    for id, c in pairs(e.callers) do
        if not c.alive then
            e.callers[id] = nil
            surge_tide(D, SURGE_CALLER, "TIDE CALLER SPILLS!")
        end
    end
end

-- ---- Camera: a side-on rig that tracks the hero along the cavern -----------

local function update_camera(D)
    local A = D.arena
    local half = A.ortho_size * 0.5
    local cx = math.max(A.pad + half * 0.4, math.min(A.w - A.pad - half * 0.4, D.hero.x))
    Art.setup_iso_camera({ x = cx, z = A.h * 0.5 - 0.5 },
        { ortho_size = A.ortho_size, offset = A.cam_offset })
    -- Parallax the far cliff so depth reads in the flat stage.
    if Art.valid(D.bloodtide.bg) then D.bloodtide.bg:set_position(vec3(PARALLAX * cx, 3.2, A.h - A.pad + 1.2)) end
end

-- ---- Hero class selection (two survivors; brief) ---------------------------

local function pick_hero()
    local class = "tide_runner"
    if ATH_COMMON and ATH_COMMON.getenv then
        local v = ATH_COMMON.getenv("ATH_BLOODTIDE_HERO")
        if type(v) == "string" and Bt.heroes[v:lower()] then class = v:lower() end
    end
    return class, Bt.heroes[class]
end

local CLASS, HERO = pick_hero()

-- ---------------------------------------------------------------------------
-- Mode contract
-- ---------------------------------------------------------------------------

return {
    meta = {
        id = "bloodtide",
        name = "Bloodtide",
        tagline = "the drowning chasm of blood",
        blurb = "A 2D side-scroller in a drowned chasm. A tide of dark blood climbs from below and accelerates every minute — ride the floating debris, stay above the red. Touch it and burn; sink and drown.",
        side_hint = "horde",
        accent = { 0.80, 0.0, 0.0, 0.95 },
        -- A side-on sketch of the chasm (normalized 0..1 rects: x,y,w,h,color).
        minimap = {
            bg = { 0.040, 0.0, 0.0, 1.0 },
            rects = {
                { 0.04, 0.04, 0.92, 0.92, { 0.102, 0.0, 0.0, 1.0 } },   -- cliff walls
                { 0.00, 0.62, 1.00, 0.38, { 0.239, 0.0, 0.0, 1.0 } },   -- the rising tide
                { 0.00, 0.60, 1.00, 0.04, { 0.800, 0.0, 0.0, 1.0 } },   -- the roiling surface
                { 0.06, 0.50, 0.14, 0.05, { 0.30, 0.18, 0.10, 1.0 } },  -- debris platforms
                { 0.30, 0.40, 0.10, 0.05, { 0.30, 0.18, 0.10, 1.0 } },
                { 0.54, 0.30, 0.08, 0.05, { 0.30, 0.18, 0.10, 1.0 } },
                { 0.78, 0.50, 0.10, 0.05, { 0.30, 0.18, 0.10, 1.0 } },
                { 0.09, 0.42, 0.04, 0.10, { 0.74, 0.71, 0.66, 1.0 } },  -- hero (left)
                { 0.62, 0.32, 0.05, 0.14, { 0.545, 0.0, 0.0, 1.0 } },   -- a leech worm
                { 0.40, 0.55, 0.04, 0.08, { 0.545, 0.0, 0.0, 1.0 } },   -- a blood thrall
            },
        },
    },

    config = {
        id = "bloodtide",
        name = "Bloodtide",
        theme = Bt.theme,
        -- A long, shallow CHASM. Wide X (read left->right), shallow Z depth, low
        -- side-on camera that tracks the hero (update_camera, each tick). The Y
        -- axis carries the tide.
        arena = {
            width = 64, height = 14, pad = 2, ortho_size = 20.0,
            cam_offset = { x = 0.0, y = 9.0, z = -28.0 },   -- side elevation, not iso
            hero_start = { x = 6, y = 7 },
            -- The drowned wade in from the FAR (right) end of the chasm.
            spawns = {
                { x = 58, y = 7 }, { x = 60, y = 5 }, { x = 60, y = 9 },
                { x = 55, y = 4 }, { x = 55, y = 10 }, { x = 51, y = 7 },
            },
        },
        hero = {
            hp_max = HERO.stats.hp_max, dps = HERO.stats.dps, cleave = HERO.stats.cleave,
            attack_range = HERO.stats.attack_range, speed = HERO.stats.speed, kite_speed = HERO.stats.kite_speed,
            actor = HERO.actor,
        },
        archetypes = Bt.archetypes,
        roles = Bt.roles,
        spawn = { interval_start = 0.8, interval_min = 0.32, batch_start = 3, batch_max = 6, cap_start = 28, cap_max = 84, brute_after = 24.0 },
        reserve_start = 320.0,
        round_seconds = 14.0,

        -- A drowned mix: thralls are the chaff spine, leech worms hold range, tide
        -- callers chant the blood higher (and surge it on death), the colossus
        -- heaves up once the timer is spent.
        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 12 == 0) then return "drowned_colossus" end
            if D.spawn_counter % 8 == 0 then return "tide_caller" end
            if D.spawn_counter % 5 == 0 then return "leech_worm" end
            return "blood_thrall"
        end,

        hooks = {
            on_start = function(D)
                local A = D.arena
                D.bloodtide = {
                    level = TIDE_FLOOR, counter = 0, callers = {},
                    flash_cd = 0.0, was_wet = false,
                    platforms = {}, surface = nil, body = nil, bg = nil,
                    class = CLASS,
                }
                local g = D.groups.world
                local far_z = A.h - A.pad + 1.2

                -- A very dark distant cliff face (cliff_wall.png) for parallax.
                D.bloodtide.bg = Art.cube("Bt_Background", vec3(PARALLAX * A.w * 0.5, 3.2, far_z),
                    vec3(A.w * 1.6, 9.0, 0.2), { 0.5, 0.5, 0.5 }, g, 0.18, Bt.tex.cliff)

                -- A panelled cliff back wall so the seamless tile reads across it.
                local panel = 4.0
                for px = A.pad, A.w - A.pad, panel do
                    Art.cube("Bt_Cliff_" .. math.floor(px), vec3(px + panel * 0.5, 3.6, A.h - A.pad - 0.2),
                        vec3(panel, 7.2, 0.4), Bt.palette.dark, g, 0.45, Bt.tex.cliff)
                end

                -- The submerged stone floor (drowns the moment the tide tops it).
                Art.cube("Bt_Floor", vec3(A.w * 0.5, -0.2, A.h * 0.5), vec3(A.w, 0.4, A.h),
                    Bt.palette.void, g, 0.2)

                build_tide(D)
                build_platforms(D)
                update_camera(D)
            end,

            on_reset = function(D)
                -- NIL-GUARD (can fire before on_start). Drop the tide and clear the
                -- caller watch; the cliff/floor/platforms survive in `world`.
                if D.bloodtide then
                    D.bloodtide.level = TIDE_FLOOR
                    D.bloodtide.callers = {}
                    D.bloodtide.flash_cd = 0.0
                    D.bloodtide.was_wet = false
                    update_tide_visual(D)
                    update_platforms(D, 0.0)
                end
            end,

            on_spawn = function(D, creep)
                -- Watch every Tide Caller so we can surge the tide when it dies.
                if D.bloodtide and creep and creep.archetype == "tide_caller" then
                    D.bloodtide.callers[creep.id] = creep
                end
            end,

            on_card = function(D, side, card_id, effect)
                -- The Horde's signature: sacrificing a creature card (a back-face
                -- play) pours the tide +15% instantly.
                if D.bloodtide and side == "horde" then
                    surge_tide(D, SURGE_CARD, "THE TIDE SURGES!")
                end
            end,

            on_combat_tick = function(D, dt)
                local e = D.bloodtide
                if not e then return end
                -- THE TIDE: a base climb that accelerates every elapsed minute.
                local minute = math.floor(D.combat_time / 60.0)
                local rate = TIDE_BASE * (1.0 + TIDE_ACCEL_PM * minute)
                e.level = math.min(TIDE_TOP, e.level + rate * dt)

                check_callers(D)
                update_tide_visual(D)
                update_platforms(D, dt)
                update_hero_vs_tide(D, dt)
                update_camera(D)
            end,

            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local e = D.bloodtide
                local level = e and e.level or TIDE_FLOOR
                -- How high the blood stands, 0..100% of the chasm.
                local pct = math.floor(math.max(0.0, math.min(1.0, (level - TIDE_FLOOR) / TIDE_RANGE)) * 100.0 + 0.5)
                -- Countdown of the 5-minute run.
                local left = math.max(0.0, RUN_SECONDS - (D and D.combat_time or 0.0))
                local mm = math.floor(left / 60.0)
                local ss = math.floor(left % 60.0)
                Art.quad(D.hud, "bt_panel", 24.0, sh - 150.0, 560.0, 58.0, { 0.06, 0.0, 0.0, 0.9 },
                    { border = { 0.80, 0.0, 0.0, 0.9 },
                      label = string.format("SURVIVOR: %s    Tide: %d%%    Time: %d:%02d",
                        (e and e.class or CLASS):upper(), pct, mm, ss) })
            end,
        },
    },
}
