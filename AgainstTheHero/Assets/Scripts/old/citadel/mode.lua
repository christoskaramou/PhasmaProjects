-- Bone Citadel — a crumbling dark-souls castle siege. A dying empire's last wall
-- stands along the far edge; the hero rolls his siege engines up to BREACH it
-- while the undead garrison pours oil, looses arrows, and floods the gate.
--
-- THE CONTRACT: return { meta = {...}, config = {...} }.
--   * meta   — what the menu shows: name, blurb, mini-map sketch, accent colour.
--   * config — handed to the shared Duel (ath_duel.lua): theme, arena, hero,
--              characters (from characters.lua), role mapping, spawn tuning, and
--              HOOKS for this level's one signature SYSTEM.
--
-- The shared Duel is a fixed iso arena, so this mode reads the engine "side-on":
-- the citadel WALL runs along the north edge (low Z) as five tall stone sections,
-- the hero's siege engines sit on the churned ground to the south, and the
-- camera is dropped to a flatter, front-on angle (arena.cam_offset) so the wall
-- rises like a castle face. The undead garrison spawns from the gate-mouths AT
-- the wall and rushes the hero — the engine's auto-fighting hero + rushing swarm,
-- reskinned as a siege.
--
-- SIGNATURE SYSTEM — THE SIEGE (everything below, driven only through hooks on
-- the live duel `D`, state namespaced on D.citadel):
--
--   1) WALL SECTIONS (x5). Each is a stone segment with its own HP, an in-world
--      HP bar, and a 3-stage damage overlay (cracks -> holes -> rubble). Breach
--      ANY section and the hero WINS (D.state = "hero_win").
--
--   2) BATTERING RAM. A timber ram on wheels sits in front of whichever section
--      the hero is nearest. While the hero stands in the siege zone by the wall,
--      the ram WINDS BACK and SLAMS that section on a cadence — a heavy impact
--      shockwave (particle burst + ram recoil) that chews the section's HP. Slow
--      but powerful; the Siege Knight boosts it.
--
--   3) CATAPULT. A timber catapult on the hero's side winds its arm up over an
--      8-beat cycle, then RELEASES a boulder that flies a true parabolic arc to a
--      target section and bursts on impact (AoE to that section + splash to its
--      neighbours). The Siege Mage boosts its cadence.
--
--   4) OIL CAULDRONS (the horde's TRAP). The garrison spends ACTION POINTS to tip
--      a cauldron over a section: it telegraphs, then POURS a 5-stage curtain of
--      boiling oil that splashes a radius of ground in front of the wall —
--      D:apply_hero_damage() if the hero is caught under it.
--
--   5) RUBBLE PHYSICS. When a section breaches, its stone COLLAPSES: chunks are
--      flung up and fall back under gravity, bouncing once before they settle.
--
-- WIN / LOSS:
--   * Hero wins  — breach any wall section (or, as the engine's own fallback,
--                  exhaust the garrison reserve with the field clear).
--   * Horde wins — slay the hero, OR hold until the SIEGE TIMER expires (the
--                  garrison overwhelms the stalled hero -> the engine's "slain").

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Cit = ATH_COMMON.load_script("Scripts/modes/citadel/characters.lua", "citadel characters", _ENV)

-- ---- Wall tuning -----------------------------------------------------------
local WALL_SECTIONS = 5
local SECTION_HP    = 120.0       -- HP per section; breach one to win
local WALL_Z        = 3.0         -- world Z of the wall face (north edge)
local WALL_HEIGHT   = 3.6         -- stone height
local WALL_DEPTH    = 1.3         -- stone thickness (toward the field)

-- ---- Battering ram tuning --------------------------------------------------
local RAM_INTERVAL  = 1.7         -- seconds between slams
local RAM_DAMAGE    = 15.0        -- HP per slam to the targeted section
local RAM_REACH     = 6.0         -- hero must be within this of the wall to drive it
local RAM_RECOIL    = 1.1         -- how far the ram recoils on the wind-back

-- ---- Catapult tuning -------------------------------------------------------
local CAT_WINDUP    = 2.4         -- arm wind-up time (the 8-beat cycle)
local CAT_FLIGHT    = 1.3         -- boulder time-of-flight along the arc
local CAT_DAMAGE    = 34.0        -- direct-hit section damage
local CAT_SPLASH    = 12.0        -- splash to neighbour sections
local CAT_ARC_PEAK  = 9.0         -- apex height of the parabola

-- ---- Oil-pour trap tuning --------------------------------------------------
local OIL_FIRST     = 5.0         -- combat seconds before the first pour
local OIL_INTERVAL  = 6.5         -- base seconds between pours
local OIL_INTERVAL_MIN = 3.0
local OIL_TELEGRAPH  = 1.3        -- warning glow before the curtain falls
local OIL_POUR       = 1.6        -- pour duration (the 5-drip animation plays over this)
local OIL_RADIUS     = 2.6        -- ground splash radius in front of the wall
local OIL_DAMAGE     = 24.0       -- applied once per pour if the hero is caught
local OIL_AP_COST    = 30.0       -- action points a pour costs the garrison

-- ---- Action-point economy (the horde's "deploy/trap" budget) ---------------
local AP_MAX         = 100.0
local AP_REGEN       = 9.0        -- per combat second

-- ---- Siege clock -----------------------------------------------------------
local SIEGE_SECONDS  = 105.0      -- combat seconds the garrison must survive

-- ---------------------------------------------------------------------------
-- Wall sections
-- ---------------------------------------------------------------------------

-- Build the five stone sections along the north edge, each with battlement,
-- in-world HP bar, and (initially hidden) damage-overlay nodes.
local function build_wall(D)
    local A = D.arena
    local cit = D.citadel
    local x0 = A.pad + 1.5
    local x1 = A.w - A.pad - 1.5
    local span = (x1 - x0) / WALL_SECTIONS
    cit.section_w = span
    for i = 1, WALL_SECTIONS do
        local cx = x0 + span * (i - 0.5)
        -- Main stone block, painted with the generated gothic-stone tile (a safe
        -- no-op if the texture bridge/asset path is unavailable — it still reads
        -- via its base colour).
        local node = Art.cube("Wall_Sec_" .. i, vec3(cx, WALL_HEIGHT * 0.5, WALL_Z),
            vec3(span * 0.94, WALL_HEIGHT, WALL_DEPTH), { 0.16, 0.16, 0.17 }, D.groups.world, 0.7,
            "Textures/modes/citadel/stone_wall.png")
        -- Crenellated battlement cap (painted with the battlement tile).
        local cap = Art.cube("Wall_Cap_" .. i, vec3(cx, WALL_HEIGHT + 0.25, WALL_Z),
            vec3(span * 0.98, 0.5, WALL_DEPTH + 0.2), { 0.22, 0.22, 0.23 }, D.groups.world, 0.8,
            "Textures/modes/citadel/battlement.png")
        -- A creeping-moss strip down the face (ancient, dying empire).
        Art.cube("Wall_Moss_" .. i, vec3(cx - span * 0.2, WALL_HEIGHT * 0.45, WALL_Z + WALL_DEPTH * 0.5),
            vec3(span * 0.18, WALL_HEIGHT * 0.7, 0.04), { 0.30, 0.42, 0.22 }, D.groups.world, 0.5)
        -- Damage overlays, hidden (scale 0) until the section takes hits.
        local crack = Art.cube("Wall_Crack_" .. i, vec3(cx, WALL_HEIGHT * 0.5, WALL_Z + WALL_DEPTH * 0.5 + 0.02),
            vec3(0.01, 0.01, 0.01), { 0.05, 0.05, 0.05 }, D.groups.world, 0.2)
        local hole = Art.cube("Wall_Hole_" .. i, vec3(cx, WALL_HEIGHT * 0.42, WALL_Z + WALL_DEPTH * 0.5 + 0.03),
            vec3(0.01, 0.01, 0.01), { 0.02, 0.02, 0.02 }, D.groups.world, 0.0)
        -- In-world HP bar floating above the section (bg + fg cubes).
        local bar_y = WALL_HEIGHT + 0.9
        local bar_bg = Art.cube("Wall_Bar_BG_" .. i, vec3(cx, bar_y, WALL_Z),
            vec3(span * 0.9, 0.16, 0.12), { 0.05, 0.05, 0.06 }, D.groups.world, 0.4)
        local bar_fg = Art.cube("Wall_Bar_FG_" .. i, vec3(cx, bar_y, WALL_Z + 0.02),
            vec3(span * 0.86, 0.20, 0.14), { 0.36, 0.78, 0.42 }, D.groups.world, 1.0)
        cit.sections[i] = {
            i = i, cx = cx, w = span, hp = SECTION_HP, hp_max = SECTION_HP,
            node = node, cap = cap, crack = crack, hole = hole,
            bar_bg = bar_bg, bar_fg = bar_fg, bar_w = span * 0.86,
            breached = false, stage = 0, rubble = {},
        }
    end
end

-- The section the hero is standing nearest (by X). Used by the ram + catapult.
local function nearest_section(D)
    local cit = D.citadel
    local hero = D.hero
    local best, bd
    for _, s in ipairs(cit.sections) do
        if not s.breached then
            local dx = math.abs(hero.x - s.cx)
            if not best or dx < bd then best, bd = s, dx end
        end
    end
    return best
end

-- Refresh a section's overlay + HP bar to match its current HP. Three stages:
-- cracks under 66%, holes under 33%, rubble at breach.
local function refresh_section(D, s)
    local pct = math.max(0.0, s.hp / s.hp_max)
    -- Cracks grow in as the first third of HP is lost.
    if pct < 0.66 then
        local g = math.min(1.0, (0.66 - pct) / 0.66)
        if Art.valid(s.crack) then
            s.crack:set_scale(vec3(s.w * 0.5 * g, WALL_HEIGHT * 0.8 * g, 0.06))
            material.set(s.crack, "emissive", vec3(0.18 * g, 0.06 * g, 0.04 * g))
        end
    end
    -- A blown-through hole opens under a third HP.
    if pct < 0.33 then
        local g = math.min(1.0, (0.33 - pct) / 0.33)
        if Art.valid(s.hole) then
            s.hole:set_scale(vec3(s.w * 0.5 * g, WALL_HEIGHT * 0.5 * g, WALL_DEPTH + 0.1))
        end
    end
    -- Tint the stone toward scorched blood-dark as it fails.
    if Art.valid(s.node) then
        local base = 0.16 * (0.4 + 0.6 * pct)
        material.set(s.node, "base_color", vec4(base + (1.0 - pct) * 0.12, base, base, 1.0))
    end
    -- HP bar: shrink the fg and recolour by remaining fraction.
    if Art.valid(s.bar_fg) then
        local col = pct > 0.5 and { 0.36, 0.78, 0.42 } or (pct > 0.25 and { 0.92, 0.74, 0.28 } or { 0.90, 0.30, 0.26 })
        s.bar_fg:set_scale(vec3(math.max(0.001, s.bar_w * pct), 0.20, 0.14))
        -- Anchor the bar to its left edge as it shrinks.
        s.bar_fg:set_position(vec3(s.cx - s.bar_w * 0.5 * (1.0 - pct), WALL_HEIGHT + 0.9, WALL_Z + 0.02))
        material.set(s.bar_fg, "emissive", vec3(col[1], col[2], col[3]))
        material.set(s.bar_fg, "base_color", vec4(col[1], col[2], col[3], 1.0))
    end
end

-- Spawn the collapse: fling stone chunks up to fall back under gravity.
local function collapse_section(D, s)
    for n = 1, 12 do
        local jx = (math.random() - 0.5) * s.w
        local chunk = Art.cube("Rubble_" .. s.i .. "_" .. n,
            vec3(s.cx + jx, WALL_HEIGHT * (0.3 + 0.6 * math.random()), WALL_Z + (math.random() - 0.3) * WALL_DEPTH),
            vec3(0.3 + math.random() * 0.3, 0.3 + math.random() * 0.3, 0.3 + math.random() * 0.3),
            { 0.16, 0.16, 0.17 }, D.groups.world, 0.5)
        s.rubble[#s.rubble + 1] = {
            node = chunk,
            x = s.cx + jx, y = WALL_HEIGHT * 0.7, z = WALL_Z + (math.random() - 0.3) * WALL_DEPTH,
            vy = 2.0 + math.random() * 3.0,
            vx = jx * 0.6, vz = (math.random() - 0.5) * 1.2,
            spin = (math.random() - 0.5) * 360.0, rot = 0.0, bounced = false,
        }
    end
    -- Drop the wall face away (sink the stone + cap below the floor).
    if Art.valid(s.node) then s.node:set_scale(vec3(s.w * 0.94, 0.2, WALL_DEPTH)) end
    if Art.valid(s.cap) then s.cap:set_scale(vec3(0.01, 0.01, 0.01)) end
    if Art.valid(s.crack) then s.crack:set_scale(vec3(0.01, 0.01, 0.01)) end
    if Art.valid(s.hole) then s.hole:set_scale(vec3(0.01, 0.01, 0.01)) end
    Art.burst("citadel_breach_" .. s.i, vec3(s.cx, WALL_HEIGHT * 0.5, WALL_Z),
        { preset = "hero_take", count = 36, life_max = 0.7, spawn_radius = s.w * 0.6, noise_strength = 6.0, size_max = 0.4 })
end

-- Advance falling rubble chunks (simple gravity + one floor bounce).
local function update_rubble(D, dt)
    for _, s in ipairs(D.citadel.sections) do
        for _, r in ipairs(s.rubble) do
            if Art.valid(r.node) then
                r.vy = r.vy - 14.0 * dt
                r.x = r.x + r.vx * dt
                r.y = r.y + r.vy * dt
                r.z = r.z + r.vz * dt
                if r.y <= 0.2 then
                    r.y = 0.2
                    if not r.bounced and r.vy < -1.0 then
                        r.vy = -r.vy * 0.35; r.vx = r.vx * 0.5; r.vz = r.vz * 0.5; r.bounced = true
                    else
                        r.vy = 0.0; r.vx = r.vx * 0.6; r.vz = r.vz * 0.6
                    end
                end
                r.rot = r.rot + r.spin * dt
                r.node:set_position(vec3(r.x, r.y, r.z))
                r.node:set_rotation(vec3(r.rot, r.rot * 0.7, 0.0))
            end
        end
    end
end

-- Deal `amount` to a section; refresh visuals; breach -> hero victory.
local function damage_section(D, s, amount, fx_y)
    if not s or s.breached then return end
    s.hp = s.hp - amount
    Art.burst("citadel_wallhit_" .. s.i, vec3(s.cx, fx_y or WALL_HEIGHT * 0.5, WALL_Z + WALL_DEPTH * 0.5),
        { preset = "enemy_take", count = 10, life_max = 0.3, spawn_radius = 0.5, size_max = 0.22 })
    if s.hp <= 0.0 then
        s.hp = 0.0
        s.breached = true
        collapse_section(D, s)
        D.citadel.breached = true
        -- The wall is down — declare the hero's victory through the engine's
        -- terminal state (the duel renders the win banner from here).
        if D.state == "combat" then
            D.state = "hero_win"
            D:set_flash("WALL BREACHED!")
            D:log("CITADEL BREACHED section=" .. s.i)
        end
    else
        refresh_section(D, s)
    end
end

-- ---------------------------------------------------------------------------
-- Battering ram
-- ---------------------------------------------------------------------------

local function build_ram(D)
    local cit = D.citadel
    local A = D.arena
    local ram = Art.group("Citadel_Ram", D.groups.world)
    local cx = A.w * 0.5
    ram:set_position(vec3(cx, 0.0, WALL_Z + WALL_DEPTH * 0.5 + 2.4))
    -- Timber cradle + the iron-capped ram log slung beneath it.
    Art.cube("Ram_Frame_L", vec3(-0.7, 0.7, 0.0), vec3(0.16, 1.4, 0.16), { 0.55, 0.27, 0.08 }, ram, 0.7)
    Art.cube("Ram_Frame_R", vec3( 0.7, 0.7, 0.0), vec3(0.16, 1.4, 0.16), { 0.55, 0.27, 0.08 }, ram, 0.7)
    Art.cube("Ram_Beam",    vec3( 0.0, 1.3, 0.0), vec3(1.7, 0.16, 0.16), { 0.55, 0.27, 0.08 }, ram, 0.7)
    Art.cylinder("Ram_Wheel_L", vec3(-0.7, 0.25, 0.4), vec3(0.5, 0.18, 0.5), { 0.45, 0.30, 0.18 }, ram, 0.5, nil)
    Art.cylinder("Ram_Wheel_R", vec3( 0.7, 0.25, 0.4), vec3(0.5, 0.18, 0.5), { 0.45, 0.30, 0.18 }, ram, 0.5, nil)
    -- The swinging log (its Z is animated toward the wall on each slam).
    local log = Art.group("Ram_Log", ram)
    Art.cylinder("Ram_Log_Body", vec3(0.0, 0.85, 0.0), vec3(0.28, 0.28, 1.8), { 0.55, 0.27, 0.08 }, log, 0.8, nil)
    Art.cylinder("Ram_Head", vec3(0.0, 0.85, -0.95), vec3(0.4, 0.4, 0.4), { 0.45, 0.30, 0.18 }, log, 1.0, nil)
    cit.ram = { root = ram, log = log, x = cx, base_z = WALL_Z + WALL_DEPTH * 0.5 + 2.4, slam_t = RAM_INTERVAL, anim = 0.0, active = false }
end

-- Drive the ram: when the hero is near the wall it tracks his section, winds the
-- log back, and slams on a cadence. The Siege Knight's bonus boosts the damage.
local function update_ram(D, dt)
    local cit = D.citadel
    local ram = cit.ram
    if not ram then return end
    local hero = D.hero
    local target = nearest_section(D)
    ram.active = (not hero.dead) and target ~= nil and (hero.z - WALL_Z) <= RAM_REACH

    -- Glide the ram across to sit in front of the hero's target section.
    if Art.valid(ram.root) and target then
        ram.x = ram.x + (target.cx - ram.x) * math.min(1.0, dt * 3.0)
        ram.root:set_position(vec3(ram.x, 0.0, ram.base_z))
    end

    if ram.active then
        ram.slam_t = ram.slam_t - dt
        ram.anim = ram.anim + dt
        -- Wind-back then snap forward: a saw-shaped log offset toward the wall.
        local cyc = 1.0 - math.min(1.0, ram.slam_t / RAM_INTERVAL)        -- 0..1 toward slam
        local back = -RAM_RECOIL * (1.0 - cyc)                            -- recoiled away early
        if Art.valid(ram.log) then ram.log:set_position(vec3(0.0, 0.0, back)) end
        if ram.slam_t <= 0.0 then
            ram.slam_t = RAM_INTERVAL
            local dmg = RAM_DAMAGE * (cit.ram_power or 1.0)
            damage_section(D, target, dmg, 1.0)
            -- Impact shockwave: punch the log forward + ring of debris.
            if Art.valid(ram.log) then ram.log:set_position(vec3(0.0, 0.0, 0.6)) end
            Art.burst("citadel_ram_" .. target.i, vec3(target.cx, 1.0, WALL_Z + WALL_DEPTH),
                { preset = "hero_take", count = 18, life_max = 0.4, spawn_radius = 1.4, noise_strength = 5.0, size_max = 0.3 })
            D:set_flash("RAM SLAM!")
        end
    elseif Art.valid(ram.log) then
        ram.log:set_position(vec3(0.0, 0.0, -RAM_RECOIL * 0.6))
    end
end

-- ---------------------------------------------------------------------------
-- Catapult (parabolic boulder)
-- ---------------------------------------------------------------------------

local function build_catapult(D)
    local cit = D.citadel
    local A = D.arena
    local cat = Art.group("Citadel_Catapult", D.groups.world)
    local base_z = A.h - A.pad - 3.0
    cat:set_position(vec3(A.w * 0.5 - 6.0, 0.0, base_z))
    Art.cube("Cat_Base", vec3(0.0, 0.4, 0.0), vec3(1.6, 0.8, 2.0), { 0.55, 0.27, 0.08 }, cat, 0.7)
    Art.cylinder("Cat_Wheel_L", vec3(-0.8, 0.3, 0.7), vec3(0.6, 0.2, 0.6), { 0.45, 0.30, 0.18 }, cat, 0.5)
    Art.cylinder("Cat_Wheel_R", vec3( 0.8, 0.3, 0.7), vec3(0.6, 0.2, 0.6), { 0.45, 0.30, 0.18 }, cat, 0.5)
    -- The throwing arm pivots at the cradle; its rotation is the wind-up cycle.
    local arm = Art.group("Cat_Arm", cat)
    arm:set_position(vec3(0.0, 0.9, 0.0))
    Art.cube("Cat_Arm_Beam", vec3(0.0, 0.0, -0.9), vec3(0.18, 0.18, 1.8), { 0.55, 0.27, 0.08 }, arm, 0.8)
    Art.sphere("Cat_Bucket", vec3(0.0, 0.0, -1.7), vec3(0.45, 0.35, 0.45), { 0.45, 0.30, 0.18 }, arm, 0.7)
    cit.catapult = {
        root = cat, arm = arm, base_x = A.w * 0.5 - 6.0, base_z = base_z,
        phase = "wind", t = 0.0, boulder = nil, target = nil,
    }
end

-- Wind the arm up over CAT_WINDUP (an 8-beat ratchet), release a boulder on a
-- parabola to a section, then burst. The Siege Mage's bonus speeds the cadence.
local function update_catapult(D, dt)
    local cit = D.citadel
    local cat = cit.catapult
    if not cat then return end
    cat.t = cat.t + dt

    if cat.phase == "wind" then
        local windup = CAT_WINDUP * (cit.cat_cadence or 1.0)
        -- 8-beat ratchet: arm rotates back in eight visible steps.
        local p = math.min(1.0, cat.t / windup)
        local beats = math.floor(p * 8.0) / 8.0
        if Art.valid(cat.arm) then cat.arm:set_rotation(vec3(-70.0 * beats, 0.0, 0.0)) end
        if cat.t >= windup then
            -- RELEASE: snap the arm forward and launch a boulder at a live section.
            cat.phase = "fly"; cat.t = 0.0
            if Art.valid(cat.arm) then cat.arm:set_rotation(vec3(40.0, 0.0, 0.0)) end
            local live = {}
            for _, s in ipairs(cit.sections) do if not s.breached then live[#live + 1] = s end end
            cat.target = live[math.random(math.max(1, #live))]
            if cat.target then
                cat.sx, cat.sz = cat.base_x, cat.base_z - 1.7
                cat.boulder = Art.sphere("Cat_Boulder", vec3(cat.sx, 1.2, cat.sz),
                    vec3(0.5, 0.5, 0.5), { 0.36, 0.36, 0.37 }, D.groups.world, 0.8,
                    "Textures/modes/citadel/catapult_projectile.png")
            else
                cat.phase = "wind"; cat.t = 0.0
            end
        end
    elseif cat.phase == "fly" then
        local flight = CAT_FLIGHT
        local p = math.min(1.0, cat.t / flight)
        if cat.target and Art.valid(cat.boulder) then
            -- True parabola: lerp ground position, add a sin-shaped arc on Y.
            local x = cat.sx + (cat.target.cx - cat.sx) * p
            local z = cat.sz + (WALL_Z - cat.sz) * p
            local y = 1.2 + math.sin(p * math.pi) * CAT_ARC_PEAK
            cat.boulder:set_position(vec3(x, y, z))
            cat.boulder:set_rotation(vec3(p * 540.0, 0.0, 0.0))
        end
        if p >= 1.0 then
            -- IMPACT: direct hit to the target, splash to its neighbours.
            if cat.target then
                damage_section(D, cat.target, CAT_DAMAGE * (cit.cat_power or 1.0), WALL_HEIGHT * 0.6)
                for _, s in ipairs(cit.sections) do
                    if s ~= cat.target and not s.breached and math.abs(s.i - cat.target.i) == 1 then
                        damage_section(D, s, CAT_SPLASH, WALL_HEIGHT * 0.5)
                    end
                end
                Art.burst("citadel_boulder_" .. cat.target.i, vec3(cat.target.cx, WALL_HEIGHT * 0.6, WALL_Z),
                    { preset = "hero_take", count = 24, life_max = 0.5, spawn_radius = 1.6, noise_strength = 5.0, size_max = 0.34 })
            end
            if Art.valid(cat.boulder) then scene.delete_node(cat.boulder); cat.boulder = nil end
            if Art.valid(cat.arm) then cat.arm:set_rotation(vec3(0.0, 0.0, 0.0)) end
            cat.phase = "wind"; cat.t = 0.0
        end
    end
end

-- ---------------------------------------------------------------------------
-- Oil-pour trap (the garrison's action-point hazard)
-- ---------------------------------------------------------------------------

local function open_oil(D)
    local cit = D.citadel
    -- Pour from a still-standing section the hero is near (defend the breach point).
    local target = nearest_section(D) or cit.sections[math.random(#cit.sections)]
    if not target then return end
    local glow = Art.cylinder("Oil_Warn_" .. cit.counter, vec3(target.cx, 0.05, WALL_Z + OIL_RADIUS),
        vec3(OIL_RADIUS * 2.0, 0.05, OIL_RADIUS * 2.0), { 1.0, 0.40, 0.0 }, D.groups.world, 1.4)
    cit.counter = cit.counter + 1
    cit.oils[#cit.oils + 1] = {
        cx = target.cx, cz = WALL_Z + OIL_RADIUS, t = 0.0, phase = "warn",
        glow = glow, curtain = {}, pool = nil, hit = false,
    }
end

local function close_oil(o)
    if Art.valid(o.glow) then scene.delete_node(o.glow) end
    if Art.valid(o.pool) then scene.delete_node(o.pool) end
    for _, c in ipairs(o.curtain) do if Art.valid(c) then scene.delete_node(c) end end
    o.curtain = {}
end

local function clear_oils(D)
    for _, o in ipairs(D.citadel and D.citadel.oils or {}) do close_oil(o) end
    if D.citadel then D.citadel.oils = {} end
end

local function update_oils(D, dt)
    local cit = D.citadel
    local hero = D.hero
    -- Schedule new pours; the garrison must be able to afford the AP cost.
    cit.next_oil = cit.next_oil - dt
    if cit.next_oil <= 0.0 and cit.ap >= OIL_AP_COST then
        local cadence = math.max(OIL_INTERVAL_MIN, OIL_INTERVAL - 0.4 * (D.round - 1))
        cit.next_oil = cadence
        cit.ap = cit.ap - OIL_AP_COST
        open_oil(D)
    end

    local survivors = {}
    for _, o in ipairs(cit.oils) do
        o.t = o.t + dt
        local keep = true
        if o.phase == "warn" then
            local pulse = 1.2 + 0.7 * math.sin(D.realtime * 13.0)
            if Art.valid(o.glow) then material.set(o.glow, "emissive", vec3(1.0 * pulse, 0.4 * pulse, 0.0)) end
            if o.t >= OIL_TELEGRAPH then
                o.phase = "pour"; o.t = 0.0
                -- Build the 5-drip curtain hanging from the battlement.
                for k = 1, 5 do
                    local dx = (k - 3) * 0.32
                    local c = Art.cube("Oil_Drip_" .. cit.counter .. "_" .. k,
                        vec3(o.cx + dx, WALL_HEIGHT, WALL_Z + WALL_DEPTH * 0.5),
                        vec3(0.14, 0.3, 0.14), { 1.0, 0.40, 0.0 }, D.groups.world, 2.0)
                    o.curtain[k] = c
                end
                -- The ground pool the oil splashes into.
                o.pool = Art.cylinder("Oil_Pool_" .. cit.counter, vec3(o.cx, 0.06, o.cz),
                    vec3(OIL_RADIUS * 1.6, 0.06, OIL_RADIUS * 1.6), { 1.0, 0.45, 0.05 }, D.groups.world, 2.0)
                -- Scorch the hero if he is caught under the curtain (once per pour).
                if not hero.dead then
                    local dxh, dzh = hero.x - o.cx, hero.z - o.cz
                    if dxh * dxh + dzh * dzh <= OIL_RADIUS * OIL_RADIUS then
                        D:apply_hero_damage(OIL_DAMAGE, { flash = "BOILED ALIVE!" })
                        o.hit = true
                    end
                end
                Art.burst("citadel_oil_" .. cit.counter, vec3(o.cx, WALL_HEIGHT, WALL_Z),
                    { preset = "hero_take", count = 20, life_max = 0.5, spawn_radius = 0.8, noise_strength = 4.0, size_max = 0.28 })
            end
        elseif o.phase == "pour" then
            -- Animate the 5 drips cascading down the wall face (staggered fall).
            local p = math.min(1.0, o.t / OIL_POUR)
            for k, c in ipairs(o.curtain) do
                if Art.valid(c) then
                    local local_p = math.max(0.0, math.min(1.0, p * 1.4 - (k - 1) * 0.08))
                    local y = WALL_HEIGHT * (1.0 - local_p)
                    c:set_position(vec3(o.cx + (k - 3) * 0.32, math.max(0.2, y), WALL_Z + WALL_DEPTH * 0.5))
                    c:set_scale(vec3(0.14, 0.3 + local_p * 0.5, 0.14))
                end
            end
            -- The pool flickers as it spreads.
            if Art.valid(o.pool) then
                local flick = 1.0 + 0.5 * math.sin(D.realtime * 18.0)
                material.set(o.pool, "emissive", vec3(1.0 * flick, 0.45 * flick, 0.05 * flick))
            end
            if o.t >= OIL_POUR then close_oil(o); keep = false end
        end
        if keep then survivors[#survivors + 1] = o end
    end
    cit.oils = survivors
end

-- ---------------------------------------------------------------------------
-- Section bookkeeping + the siege clock
-- ---------------------------------------------------------------------------

local function update_sections(D, dt)
    update_rubble(D, dt)
    -- Pulse intact battlement caps faintly so the wall reads as "alive" stone.
    for _, s in ipairs(D.citadel.sections) do
        if not s.breached and Art.valid(s.cap) then
            local g = 0.8 + 0.06 * math.sin(D.realtime * 1.5 + s.i)
            material.set(s.cap, "emissive", vec3(0.22 * g, 0.22 * g, 0.23 * g))
        end
    end
end

-- The horde regenerates action points and, when flush, hardens the weakest
-- still-standing section a little ("reinforce the wall") — the AP economy made
-- visible as defensive pressure on top of the oil pours.
local function update_ap(D, dt)
    local cit = D.citadel
    cit.ap = math.min(AP_MAX, cit.ap + AP_REGEN * dt)
    cit.reinforce_t = (cit.reinforce_t or 8.0) - dt
    if cit.reinforce_t <= 0.0 and cit.ap >= AP_MAX * 0.9 then
        cit.reinforce_t = 8.0
        cit.ap = cit.ap - 40.0
        local weakest
        for _, s in ipairs(cit.sections) do
            if not s.breached and (not weakest or s.hp < weakest.hp) then weakest = s end
        end
        if weakest then
            weakest.hp = math.min(weakest.hp_max, weakest.hp + weakest.hp_max * 0.12)
            refresh_section(D, weakest)
            Art.burst("citadel_reinforce_" .. weakest.i, vec3(weakest.cx, WALL_HEIGHT * 0.5, WALL_Z + WALL_DEPTH * 0.5),
                { preset = "enemy_take", count = 10, life_max = 0.3, spawn_radius = 0.6, size_max = 0.2 })
        end
    end
end

local function update_siege_clock(D, dt)
    local cit = D.citadel
    cit.siege_t = cit.siege_t - dt
    if cit.siege_t <= 0.0 and not cit.breached and D.state == "combat" then
        -- Time up, wall intact: the garrison overwhelms the stalled hero. Routed
        -- through the hazard API so the engine's "slain" terminal fires cleanly
        -- (a horde victory if the player took the horde seat).
        D:apply_hero_damage(1.0e6, { ignore_armor = true, flash = "THE WALLS HOLD!" })
    end
end

-- ---------------------------------------------------------------------------
-- Mode contract
-- ---------------------------------------------------------------------------

return {
    meta = {
        id      = "citadel",
        name    = "Bone Citadel",
        tagline = "the last wall of a dying empire",
        blurb   = "A crumbling dark-souls castle siege. Roll the ram and catapult up to BREACH the wall before the undead garrison's oil, arrows, and gate-flood overwhelm you.",
        side_hint = "hero",
        accent  = { 0.80, 0.40, 0.12, 0.95 },
        -- Stylised side-on sketch: the wall band along the top, siege engines and
        -- the hero massed below (normalised 0..1 rects: x,y,w,h,color).
        minimap = {
            bg = { 0.10, 0.10, 0.11, 1.0 },
            rects = {
                { 0.06, 0.06, 0.88, 0.20, { 0.20, 0.20, 0.21, 1.0 } },  -- the wall band
                -- Five wall sections.
                { 0.08, 0.08, 0.15, 0.16, { 0.30, 0.42, 0.22, 1.0 } },
                { 0.25, 0.08, 0.15, 0.16, { 0.16, 0.16, 0.17, 1.0 } },
                { 0.42, 0.08, 0.15, 0.16, { 0.16, 0.16, 0.17, 1.0 } },
                { 0.59, 0.08, 0.15, 0.16, { 0.30, 0.42, 0.22, 1.0 } },
                { 0.76, 0.08, 0.15, 0.16, { 0.16, 0.16, 0.17, 1.0 } },
                -- Oil-fire on the battlements.
                { 0.30, 0.05, 0.05, 0.04, { 1.00, 0.40, 0.0, 1.0 } },
                { 0.64, 0.05, 0.05, 0.04, { 1.00, 0.40, 0.0, 1.0 } },
                -- Hero + siege engines below.
                { 0.46, 0.62, 0.08, 0.12, { 0.86, 0.84, 0.74, 1.0 } },  -- hero
                { 0.30, 0.44, 0.14, 0.08, { 0.55, 0.27, 0.08, 1.0 } },  -- battering ram
                { 0.58, 0.78, 0.16, 0.10, { 0.55, 0.27, 0.08, 1.0 } },  -- catapult
            },
        },
    },

    config = {
        id    = "citadel",
        name  = "Bone Citadel",
        theme = Cit.theme,
        -- A wide, shallow arena: a broad wall to besiege, less depth to cross.
        -- cam_offset is dropped low + front-on (vs the default corner iso) so the
        -- wall rises like a castle face — the "side-view siege" read.
        arena = {
            width = 56, height = 32, pad = 2, ortho_size = 40.0,
            cam_offset = { x = -6.0, y = 26.0, z = 44.0 },
            hero_start = { x = 28, y = 22 },
        },
        hero  = {
            -- The Siege Knight (battering-ram specialist) is the default rig. Swap
            -- actor to Cit.hero_actor_mage for the catapult/spell Siege Mage.
            hp_max = 104.0, dps = 20.0, cleave = 3, attack_range = 1.3,
            speed = 2.25, kite_speed = 2.8,
            actor = Cit.hero_actor_knight,
        },
        archetypes = Cit.archetypes,
        roles      = Cit.roles,
        spawn = {
            interval_start = 0.75, interval_min = 0.32,
            batch_start = 3, batch_max = 7,
            cap_start = 30, cap_max = 88,
            brute_after = 24.0,
        },
        reserve_start = 360.0,
        round_seconds = 14.0,

        -- The garrison: rabble/hound chaff, periodic archers + cauldrons, the
        -- swordsmen holding the gate, and a late colossus.
        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 13 == 0) then return "marrow_colossus" end
            if D.spawn_counter % 9 == 0 then return "undead_swordsman"  end
            if D.spawn_counter % 7 == 0 then return "oil_cauldron"      end
            if D.spawn_counter % 5 == 0 then return "battlement_archer" end
            return (D.spawn_counter % 2 == 0) and "barrow_hound" or "bone_rabble"
        end,

        hooks = {
            on_start = function(D)
                D.citadel = {
                    sections = {}, oils = {}, counter = 0,
                    ap = 60.0, next_oil = OIL_FIRST,
                    siege_t = SIEGE_SECONDS, breached = false,
                    -- Siege-engine tuning (knight rams harder; swap to the mage to
                    -- speed the catapult — these multipliers are where that lives).
                    ram_power = 1.0, cat_power = 1.0, cat_cadence = 1.0,
                }
                -- All siege structures live under D.groups.world, which survives the
                -- R reset, so they are built ONCE here (never rebuilt in on_reset).
                build_wall(D)
                build_ram(D)
                build_catapult(D)
                -- Brazier ambience flanking the gate (texture-ready props).
                local A = D.arena
                Art.cube("Citadel_Brazier_L", vec3(A.pad + 2.0, 0.8, WALL_Z + 1.0), vec3(0.5, 1.6, 0.5), { 1.0, 0.62, 0.22 }, D.groups.world, 1.8)
                Art.cube("Citadel_Brazier_R", vec3(A.w - A.pad - 2.0, 0.8, WALL_Z + 1.0), vec3(0.5, 1.6, 0.5), { 1.0, 0.62, 0.22 }, D.groups.world, 1.8)
            end,

            on_reset = function(D)
                -- on_reset fires before on_start at launch (D.citadel still nil) and
                -- again on every R press. The wall/engines persist under
                -- D.groups.world, so only the transient hazards + clocks rewind, and
                -- the sections are healed back to full for a fresh siege.
                clear_oils(D)
                if D.citadel then
                    D.citadel.ap = 60.0
                    D.citadel.next_oil = OIL_FIRST
                    D.citadel.siege_t = SIEGE_SECONDS
                    D.citadel.breached = false
                    D.citadel.reinforce_t = 8.0
                    for _, s in ipairs(D.citadel.sections) do
                        -- Clear any rubble from a prior breach.
                        for _, r in ipairs(s.rubble) do if Art.valid(r.node) then scene.delete_node(r.node) end end
                        s.rubble = {}
                        s.hp = s.hp_max
                        s.breached = false
                        if Art.valid(s.node) then s.node:set_scale(vec3(s.w * 0.94, WALL_HEIGHT, WALL_DEPTH)) end
                        if Art.valid(s.cap) then s.cap:set_scale(vec3(s.w * 0.98, 0.5, WALL_DEPTH + 0.2)) end
                        if Art.valid(s.crack) then s.crack:set_scale(vec3(0.01, 0.01, 0.01)) end
                        if Art.valid(s.hole) then s.hole:set_scale(vec3(0.01, 0.01, 0.01)) end
                        refresh_section(D, s)
                    end
                end
            end,

            on_combat_tick = function(D, dt)
                update_ram(D, dt)
                update_catapult(D, dt)
                update_oils(D, dt)
                update_sections(D, dt)
                update_ap(D, dt)
                update_siege_clock(D, dt)
            end,

            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local cit = D.citadel
                if not cit then return end
                -- Strongest remaining section + the siege clock + horde AP.
                local best_hp, intact = 0.0, 0
                for _, s in ipairs(cit.sections) do
                    if not s.breached then intact = intact + 1; if s.hp > best_hp then best_hp = s.hp end end
                end
                local mins = math.max(0.0, cit.siege_t)
                Art.quad(D.hud, "citadel_status", 24.0, sh - 150.0, 560.0, 58.0,
                    { 0.10, 0.08, 0.06, 0.85 },
                    { border = { 0.80, 0.40, 0.12, 0.90 },
                      label = string.format("Wall: %d/%d sections  -  Siege clock %ds  -  Garrison AP %d",
                          intact, WALL_SECTIONS, math.floor(mins + 0.5), math.floor(cit.ap)) })
            end,
        },
    },
}
