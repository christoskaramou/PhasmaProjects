-- Dark Altar — a top-down dark-ritual chamber built around a summoning altar.
--
-- Two files only: this one + characters.lua.
--   * meta   — what the menu shows: name, blurb, mini-map sketch, accent colour.
--   * config — handed to the shared Duel (ath_duel.lua): theme, arena, hero,
--              characters (from characters.lua), role mapping, spawn tuning, and
--              HOOKS for this level's one signature mechanic.
--
-- Signature mechanic — THE RITUAL. A central altar casts souls into a dark SOUL
-- METER (0 -> 100). The meter climbs as the horde feeds it (each "soul cast" both
-- bumps the meter and SUMMONS a guardian that ORBITS the altar in a protective
-- ring — true centripetal motion). The altar also looses HOMING soul-bolts that
-- spiral toward the hero before their pull decays. The chamber escalates through
-- THREE phases as the meter fills (rune-blue -> soul-purple -> blood). When the
-- meter tops out the RITUAL COMPLETES: a soul nova scorches the hero and a wave
-- of horrors is summoned, then the meter resets one notch lower and climbs again.
--
-- The hero's counterplay (the auto-fighting knight will do this when combat drifts
-- to the centre): standing on the altar DRAINS its integrity; at zero the altar
-- EXPLODES — scattering nearby orbiters, knocking the meter down, and briefly
-- stunning the ritual before it recharges. So it is a tug of war over the centre,
-- expressed purely as horde-favouring environmental pressure via the hazard API.
--
-- Everything is built from ath_art primitives parented to D.groups.world, self-lit
-- via emissive (scene lighting barely reaches the built stage), and texture-ready
-- (the altar, floor rune-circle, soul-bolt and shade skins come from
-- tools/gen_textures_altar.py).

local Art   = ATH_COMMON.load_script("Scripts/shared/ath_art.lua",            "shared art",          _ENV)
local Altar = ATH_COMMON.load_script("Scripts/modes/dark_altar/characters.lua", "dark_altar characters", _ENV)

local C = Altar.palette
local TEX = Altar.tex

-- ---- Ritual tuning ---------------------------------------------------------
local METER_MAX        = 100.0
local PASSIVE_RATE     = 0.7      -- meter/s the ritual gains on its own
local RITUAL_RESET     = 45.0     -- meter drops here after a completion (then climbs)

-- Soul casts: each one bumps the meter AND summons one orbiting guardian.
local SOUL_FIRST       = 3.0
local SOUL_INTERVAL    = 3.2      -- seconds between casts
local SOUL_INTERVAL_MIN = 1.4     -- floor as phases/ritual count rise
local CAST_METER       = 6.0      -- meter gained per soul cast

-- Orbiters: guardians circling the altar in up to three rings (by phase).
local ORBIT_RING_R     = { 3.2, 4.8, 6.4 }
local ORBIT_TANGENTIAL = 1.8      -- linear speed; angular speed = this / radius
local ORBITER_MAX      = 16
local ORBITER_REPULSE_R = 1.5     -- hero is shoved out of this band
local ORBITER_PUSH     = 3.2      -- shove units/s at the orbiter centre
local ORBITER_DPS      = 6.0      -- contact drain while inside the band

-- Homing soul-bolts fired from the altar core.
local BOLT_FIRST       = 5.0
local BOLT_INTERVAL    = 4.0
local BOLT_INTERVAL_MIN = 1.8
local BOLT_SPEED       = 7.0
local BOLT_HOME_BASE   = 3.4      -- steering strength at age 0 (decays)
local BOLT_HOME_DECAY  = 0.9      -- per second exponential decay of homing
local BOLT_SPIN        = 2.6      -- tangential accel (the spiral; decays with homing)
local BOLT_LIFE        = 4.0
local BOLT_DAMAGE      = 12.0
local BOLT_HIT_R       = 0.85
local BOLT_MAX         = 14

-- Altar integrity (the hero's counterplay) + completion nova.
local ALTAR_CORE_R     = 2.3      -- hero "on the altar" zone
local ALTAR_INTEGRITY  = 100.0
local ALTAR_RECHARGE   = 9.0      -- integrity/s regained after a shatter
local SMASH_BLAST_R    = 5.0      -- orbiters within this are scattered
local SMASH_METER_KNOCK = 32.0
local SMASH_STUN       = 3.0      -- ritual paused this long after a shatter
local NOVA_DAMAGE_MAX  = 46.0     -- soul-nova damage at the altar
local NOVA_DAMAGE_MIN  = 14.0     -- minimum (arena-wide) nova damage
local NOVA_RADIUS      = 9.0

-- Per-phase look: emissive colour the core/orbiters take on as the meter climbs.
local PHASE_COLOR = { C.rune_blue, C.soul_purple, C.blood }
local PHASE_NAME  = { "GATHERING", "ASCENDANT", "CONSUMMATION" }

-- ---- Small helpers ---------------------------------------------------------

-- The altar sits on the chamber's exact centre — the same point the floor
-- rune-circle texture and the iso camera are centred on (A.w*0.5 - 0.5).
local function altar_center(D)
    local A = D.arena
    return A.w * 0.5 - 0.5, A.h * 0.5 - 0.5
end

local function phase_for(meter)
    if meter >= 66.0 then return 3 end
    if meter >= 33.0 then return 2 end
    return 1
end

-- ---- Altar construction (persists across R-resets; built once in on_start) --

local function build_altar(D)
    local cx, cz = altar_center(D)
    local al = D.altar

    -- The pedestal — a wide flat octagonal stone, painted with the altar sprite
    -- (top-down). Swap the texture for an artist drop-in any time.
    al.pedestal = Art.cylinder("Altar_Pedestal", vec3(cx, 0.16, cz),
        vec3(4.4, 0.3, 4.4), C.deep_purple, D.groups.world, 0.5, TEX.altar)

    -- The soul core — a bright sphere that pulses with the meter (set each tick).
    al.core = Art.sphere("Altar_Core", vec3(cx, 0.95, cz),
        vec3(0.9, 0.9, 0.9), C.rune_blue, D.groups.world, 2.2)

    -- A shaft of soul-light rising from the core; its height tracks the meter.
    al.beam = Art.cylinder("Altar_Beam", vec3(cx, 2.0, cz),
        vec3(0.5, 3.0, 0.5), C.soul_purple, D.groups.world, 2.0)

    -- A slowly-rotating ring of rune-nubs around the base (the rune circle spin).
    al.rune_ring = Art.group("Altar_RuneRing", D.groups.world)
    if Art.valid(al.rune_ring) then al.rune_ring:set_position(vec3(cx, 0.08, cz)) end
    for i = 1, 8 do
        local a = math.pi * 2.0 * (i - 1) / 8
        Art.cube("RuneNub_" .. i, vec3(2.6 * math.cos(a), 0.0, 2.6 * math.sin(a)),
            vec3(0.22, 0.06, 0.5), C.soul_purple, al.rune_ring, 1.4)
    end

    -- Four corner braziers framing the ritual space (texture-ready props).
    for i, off in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
        Art.cube("Altar_Brazier_" .. i, vec3(cx + off[1] * 3.4, 0.5, cz + off[2] * 3.4),
            vec3(0.4, 1.0, 0.4), C.deep_purple, D.groups.world, 0.8)
        Art.sphere("Altar_BrazierFire_" .. i, vec3(cx + off[1] * 3.4, 1.2, cz + off[2] * 3.4),
            vec3(0.34, 0.34, 0.34), C.soul_bright, D.groups.world, 1.8)
    end

    -- Ambient blood-ritual splatter decals on the floor (overlay texture).
    for i, off in ipairs({ { 0.0, 2.0 }, { 2.0, -1.4 }, { -2.2, -1.0 } }) do
        Art.cylinder("Altar_Blood_" .. i, vec3(cx + off[1], 0.06, cz + off[2]),
            vec3(1.6, 0.02, 1.6), C.blood, D.groups.world, 0.6, TEX.blood)
    end
end

-- ---- Orbiters (centripetal motion around the altar) ------------------------

local function summon_orbiter(D)
    local al = D.altar
    if #al.orbiters >= ORBITER_MAX then return end
    local cx, cz = altar_center(D)
    -- Outer rings unlock with the phase, so higher phases pack the floor.
    local ring = math.random(1, al.phase)
    local radius = ORBIT_RING_R[ring] + (math.random() - 0.5) * 0.5
    local angle = math.random() * math.pi * 2.0
    -- Alternate spin direction per ring for a layered, woven look.
    local dir = (ring % 2 == 0) and -1.0 or 1.0
    local col = PHASE_COLOR[al.phase]

    local node = Art.sphere("Orbiter_" .. al.counter,
        vec3(cx + radius * math.cos(angle), 0.7, cz + radius * math.sin(angle)),
        vec3(0.42, 0.42, 0.42), col, D.groups.world, 2.0)
    -- A trailing wisp so each guardian reads as a summoned shade, not a ball.
    local trail = Art.cube("OrbiterTrail_" .. al.counter, vec3(0.0, 0.0, 0.0),
        vec3(0.16, 0.16, 0.46), C.void_black, node, 0.8)

    al.counter = al.counter + 1
    al.orbiters[#al.orbiters + 1] = {
        angle = angle, radius = radius, dir = dir,
        omega = (ORBIT_TANGENTIAL / radius) * dir,
        bob = math.random() * math.pi * 2.0,
        node = node, trail = trail,
    }

    -- Summoning vortex: a quick inward burst at the cast point.
    Art.burst("altar_summon_" .. al.counter, vec3(cx + radius * math.cos(angle), 0.8, cz + radius * math.sin(angle)),
        { preset = "enemy_take", count = 18, life_max = 0.34, spawn_radius = 0.5, noise_strength = 4.0, size_max = 0.24 })
end

local function destroy_orbiter(o)
    if Art.valid(o.node) then scene.delete_node(o.node) end
end

local function clear_orbiters(D)
    for _, o in ipairs(D.altar and D.altar.orbiters or {}) do destroy_orbiter(o) end
    if D.altar then D.altar.orbiters = {} end
end

local function update_orbiters(D, dt)
    local al = D.altar
    local cx, cz = altar_center(D)
    local hero = D.hero
    local push_dmg = 0.0
    local touching = false

    for _, o in ipairs(al.orbiters) do
        -- Centripetal orbit: advance the angle; position is r,theta about the altar.
        o.angle = o.angle + o.omega * dt
        local ox = cx + o.radius * math.cos(o.angle)
        local oz = cz + o.radius * math.sin(o.angle)
        local oy = 0.7 + 0.15 * math.sin(D.realtime * 3.0 + o.bob)
        if Art.valid(o.node) then
            o.node:set_position(vec3(ox, oy, oz))
            -- Point the trailing wisp backward along the tangent.
            o.node:set_rotation(vec3(0.0, math.deg(o.angle) + (o.dir > 0 and 90.0 or -90.0), 0.0))
        end

        -- Hero repulsion: shove the hero out of the guardian's band + drain HP.
        if not hero.dead then
            local dx, dz = hero.x - ox, hero.z - oz
            local d2 = dx * dx + dz * dz
            if d2 < ORBITER_REPULSE_R * ORBITER_REPULSE_R and d2 > 0.0001 then
                local d = math.sqrt(d2)
                local prox = 1.0 - (d / ORBITER_REPULSE_R)
                hero.x = hero.x + (dx / d) * ORBITER_PUSH * prox * dt
                hero.z = hero.z + (dz / d) * ORBITER_PUSH * prox * dt
                push_dmg = push_dmg + ORBITER_DPS * prox * dt
                touching = true
            end
        end
    end

    if push_dmg > 0.0 then
        D:apply_hero_damage(push_dmg, { flash = "WARDED OFF" })
        al.hit_fx_t = (al.hit_fx_t or 0.0) - dt
        if touching and al.hit_fx_t <= 0.0 then
            al.hit_fx_t = 0.18
            Art.burst("altar_repulse", vec3(hero.x, 0.8, hero.z),
                { preset = "hero_take", count = 8, life_max = 0.18, spawn_radius = 0.3, noise_strength = 2.6, size_max = 0.14 })
        end
    end
end

-- ---- Homing soul-bolts (homing strength + spiral both decay with age) -------

local function fire_bolt_volley(D)
    local al = D.altar
    local cx, cz = altar_center(D)
    local hero = D.hero
    if hero.dead then return end
    local count = al.phase  -- 1 / 2 / 3 bolts as the ritual escalates
    for i = 1, count do
        if #al.bolts >= BOLT_MAX then break end
        -- Launch outward in a fanned spread; homing then curves them to the hero.
        local base = math.atan(hero.z - cz, hero.x - cx)
        local spread = (i - (count + 1) * 0.5) * 0.5
        local a = base + spread
        local node = Art.sphere("Bolt_" .. al.bolt_counter, vec3(cx, 0.9, cz),
            vec3(0.34, 0.34, 0.34), C.soul_bright, D.groups.world, 2.4, TEX.soul_bolt)
        al.bolt_counter = al.bolt_counter + 1
        al.bolts[#al.bolts + 1] = {
            x = cx, z = cz,
            vx = math.cos(a) * BOLT_SPEED, vz = math.sin(a) * BOLT_SPEED,
            age = 0.0, node = node,
        }
    end
end

local function destroy_bolt(b)
    if Art.valid(b.node) then scene.delete_node(b.node) end
end

local function clear_bolts(D)
    for _, b in ipairs(D.altar and D.altar.bolts or {}) do destroy_bolt(b) end
    if D.altar then D.altar.bolts = {} end
end

local function update_bolts(D, dt)
    local al = D.altar
    local hero = D.hero
    local A = D.arena
    local survivors = {}
    for _, b in ipairs(al.bolts) do
        b.age = b.age + dt
        local keep = true

        if not hero.dead then
            -- Homing + spiral, both fading as the bolt ages (decay).
            local decay = math.exp(-b.age * BOLT_HOME_DECAY)
            local dx, dz = hero.x - b.x, hero.z - b.z
            local d = math.sqrt(dx * dx + dz * dz)
            if d > 0.0001 then
                local nx, nz = dx / d, dz / d
                -- Steer velocity toward the hero (homing).
                b.vx = b.vx + nx * BOLT_HOME_BASE * decay * dt * BOLT_SPEED
                b.vz = b.vz + nz * BOLT_HOME_BASE * decay * dt * BOLT_SPEED
                -- Tangential nudge perpendicular to the chase dir (the spiral).
                b.vx = b.vx + (-nz) * BOLT_SPIN * decay * dt * BOLT_SPEED
                b.vz = b.vz + (nx) * BOLT_SPIN * decay * dt * BOLT_SPEED
            end
            -- Renormalise to a steady flight speed so steering curves, not accelerates.
            local sp = math.sqrt(b.vx * b.vx + b.vz * b.vz)
            if sp > 0.0001 then b.vx = b.vx / sp * BOLT_SPEED; b.vz = b.vz / sp * BOLT_SPEED end
        end

        b.x = b.x + b.vx * dt
        b.z = b.z + b.vz * dt
        if Art.valid(b.node) then
            b.node:set_position(vec3(b.x, 0.9, b.z))
            b.node:set_rotation(vec3(0.0, math.deg(math.atan(b.vx, b.vz)), 0.0))
        end

        -- Hit the hero?
        if not hero.dead then
            local hx, hz = hero.x - b.x, hero.z - b.z
            if hx * hx + hz * hz <= BOLT_HIT_R * BOLT_HIT_R then
                D:apply_hero_damage(BOLT_DAMAGE, { flash = "SOUL-STRUCK!" })
                Art.burst("altar_bolt_hit_" .. tostring(b.x), vec3(hero.x, 0.9, hero.z),
                    { preset = "hero_take", count = 12, life_max = 0.24, spawn_radius = 0.3, noise_strength = 3.0, size_max = 0.2 })
                keep = false
            end
        end
        -- Expire on lifetime or leaving the arena.
        if b.age >= BOLT_LIFE or b.x < A.pad or b.x > A.w - A.pad or b.z < A.pad or b.z > A.h - A.pad then
            keep = false
        end

        if keep then survivors[#survivors + 1] = b else destroy_bolt(b) end
    end
    al.bolts = survivors
end

-- ---- Altar core visuals + the hero's smash counterplay ---------------------

local function update_core(D, dt)
    local al = D.altar
    local cx, cz = altar_center(D)
    local frac = al.meter / METER_MAX
    local col = PHASE_COLOR[al.phase]
    -- The core swells and pulses faster as the ritual nears completion.
    local pulse = 1.0 + 0.35 * math.sin(D.realtime * (4.0 + 6.0 * frac))
    local cs = (0.8 + 1.1 * frac) * pulse
    if Art.valid(al.core) then
        al.core:set_scale(vec3(cs, cs, cs))
        local e = 1.6 + 1.6 * frac
        material.set(al.core, "emissive", vec3(col[1] * e, col[2] * e, col[3] * e))
    end
    -- The soul-shaft height tracks the meter directly (a readable progress beam).
    if Art.valid(al.beam) then
        local bh = 1.0 + 6.0 * frac
        al.beam:set_position(vec3(cx, 0.5 + bh * 0.5, cz))
        al.beam:set_scale(vec3(0.35 + 0.25 * pulse, bh, 0.35 + 0.25 * pulse))
        material.set(al.beam, "emissive", vec3(col[1] * 2.0, col[2] * 2.0, col[3] * 2.0))
    end
    -- Slowly rotate the rune ring (faster with the phase).
    if Art.valid(al.rune_ring) then
        al.ring_angle = (al.ring_angle or 0.0) + dt * (12.0 + 8.0 * al.phase)
        al.rune_ring:set_rotation(vec3(0.0, al.ring_angle, 0.0))
    end
end

local function altar_explode(D)
    local al = D.altar
    local cx, cz = altar_center(D)
    al.integrity = 0.0
    al.stun_t = SMASH_STUN
    al.meter = math.max(0.0, al.meter - SMASH_METER_KNOCK)
    D:set_flash("ALTAR SHATTERED!")
    -- A violent eruption at the centre.
    Art.burst("altar_explode_a", vec3(cx, 1.0, cz),
        { preset = "hero_take", count = 40, life_max = 0.5, spawn_radius = 2.2, noise_strength = 6.0, size_max = 0.36 })
    Art.burst("altar_explode_b", vec3(cx, 0.6, cz),
        { preset = "enemy_take", count = 30, life_max = 0.4, spawn_radius = 3.0, noise_strength = 5.0, size_max = 0.3 })
    -- Scatter (destroy) orbiters caught in the blast.
    local survivors = {}
    for _, o in ipairs(al.orbiters) do
        local ox = cx + o.radius * math.cos(o.angle)
        local oz = cz + o.radius * math.sin(o.angle)
        local dx, dz = ox - cx, oz - cz
        if dx * dx + dz * dz <= SMASH_BLAST_R * SMASH_BLAST_R then
            destroy_orbiter(o)
        else
            survivors[#survivors + 1] = o
        end
    end
    al.orbiters = survivors
    D:log(string.format("ALTAR SHATTERED meter=%.0f orbiters=%d", al.meter, #al.orbiters))
end

local function update_integrity(D, dt)
    local al = D.altar
    local cx, cz = altar_center(D)
    local hero = D.hero
    -- The auto-fighting hero drains integrity while standing on the altar.
    if not hero.dead then
        local dx, dz = hero.x - cx, hero.z - cz
        if dx * dx + dz * dz <= ALTAR_CORE_R * ALTAR_CORE_R then
            al.integrity = al.integrity - hero.dps * dt
            al.smashing = true
            if (al.smash_fx_t or 0.0) <= 0.0 then
                al.smash_fx_t = 0.12
                Art.burst("altar_smash", vec3(hero.x, 0.8, hero.z),
                    { preset = "enemy_take", count = 6, life_max = 0.16, spawn_radius = 0.4, noise_strength = 3.0, size_max = 0.16 })
            end
            al.smash_fx_t = (al.smash_fx_t or 0.0) - dt
            if al.integrity <= 0.0 then altar_explode(D) end
        else
            al.smashing = false
        end
    end
    -- Recharge integrity back toward full when not being smashed.
    if not al.smashing and al.integrity < ALTAR_INTEGRITY then
        al.integrity = math.min(ALTAR_INTEGRITY, al.integrity + ALTAR_RECHARGE * dt)
    end
end

-- ---- Ritual completion (soul nova + a summoned wave) -----------------------

local function ritual_complete(D)
    local al = D.altar
    local cx, cz = altar_center(D)
    local hero = D.hero
    al.ritual_count = (al.ritual_count or 0) + 1
    D:set_flash("THE RITUAL IS COMPLETE!")

    -- Soul nova: proximity-scaled damage, arena-wide minimum.
    if not hero.dead then
        local dx, dz = hero.x - cx, hero.z - cz
        local d = math.sqrt(dx * dx + dz * dz)
        local prox = 1.0 - math.min(1.0, d / NOVA_RADIUS)
        local dmg = NOVA_DAMAGE_MIN + (NOVA_DAMAGE_MAX - NOVA_DAMAGE_MIN) * prox
        D:apply_hero_damage(dmg, { flash = "SOUL NOVA!" })
    end
    Art.burst("altar_nova_a", vec3(cx, 1.2, cz),
        { preset = "hero_take", count = 60, life_max = 0.7, spawn_radius = 3.5, noise_strength = 7.0, size_max = 0.42 })
    Art.burst("altar_nova_b", vec3(cx, 0.8, cz),
        { preset = "enemy_take", count = 40, life_max = 0.5, spawn_radius = 5.0, noise_strength = 6.0, size_max = 0.34 })

    -- The ritual's reward for the horde: a summoned wave of horrors (free spawns).
    local function summon(arch, n)
        for i = 1, n do
            local sp = D.spawns[((D.spawn_counter + i) % #D.spawns) + 1]
            D:spawn_one(sp, arch, true)
        end
    end
    summon("dread_harbinger", 1)
    summon("revenant", 2)
    summon("soul_wisp", 4)

    -- Reset the meter one notch lower and climb again, escalating each time.
    al.meter = RITUAL_RESET
    D:log(string.format("RITUAL COMPLETE #%d round=%d", al.ritual_count, D.round))
end

-- ---- Per-frame ritual update (the one place everything advances) -----------

local function update_ritual(D, dt)
    local al = D.altar
    if not al then return end

    -- Phase tracking (recolour + announce on transition).
    local ph = phase_for(al.meter)
    if ph ~= al.phase then
        al.phase = ph
        D:set_flash("RITUAL PHASE " .. ph .. " - " .. PHASE_NAME[ph])
    end

    -- The smash-stun freezes new casts/bolts (the ritual is reeling).
    if (al.stun_t or 0.0) > 0.0 then
        al.stun_t = al.stun_t - dt
    else
        -- Passive meter drift.
        al.meter = math.min(METER_MAX, al.meter + PASSIVE_RATE * dt)

        -- Soul casts: cadence tightens with phase and each completed ritual.
        al.next_soul = al.next_soul - dt
        if al.next_soul <= 0.0 then
            local cadence = math.max(SOUL_INTERVAL_MIN,
                SOUL_INTERVAL - 0.35 * (al.phase - 1) - 0.25 * (al.ritual_count or 0))
            al.next_soul = cadence
            summon_orbiter(D)
            al.meter = math.min(METER_MAX, al.meter + CAST_METER)
        end

        -- Altar bolt volleys.
        al.next_bolt = al.next_bolt - dt
        if al.next_bolt <= 0.0 then
            local cadence = math.max(BOLT_INTERVAL_MIN,
                BOLT_INTERVAL - 0.4 * (al.phase - 1) - 0.2 * (al.ritual_count or 0))
            al.next_bolt = cadence
            fire_bolt_volley(D)
        end

        -- Completion.
        if al.meter >= METER_MAX then ritual_complete(D) end
    end

    update_orbiters(D, dt)
    update_bolts(D, dt)
    update_integrity(D, dt)
    update_core(D, dt)
end

-- ---- Mode contract ---------------------------------------------------------

return {
    meta = {
        id      = "dark_altar",
        name    = "Dark Altar",
        tagline = "the chamber where souls are unmade",
        blurb   = "A top-down ritual chamber. The horde feeds a dark altar, summoning guardians that orbit it in rings while soul-bolts hunt the hero. Shatter the altar before the ritual consummates.",
        side_hint = "horde",
        accent  = { 0.80, 0.00, 0.80, 0.95 },
        -- Stylised top-down sketch of the chamber (normalized 0..1 rects).
        minimap = {
            bg = { 0.04, 0.00, 0.06, 1.0 },
            rects = {
                { 0.06, 0.06, 0.88, 0.88, { 0.10, 0.00, 0.12, 1.0 } },  -- floor
                { 0.44, 0.44, 0.12, 0.12, { 0.80, 0.00, 0.80, 1.0 } },  -- altar core
                -- Orbiting guardians ringing the altar.
                { 0.30, 0.46, 0.05, 0.05, { 0.40, 0.10, 0.90, 1.0 } },
                { 0.65, 0.46, 0.05, 0.05, { 0.40, 0.10, 0.90, 1.0 } },
                { 0.47, 0.28, 0.05, 0.05, { 1.00, 0.00, 0.33, 1.0 } },
                { 0.47, 0.66, 0.05, 0.05, { 1.00, 0.00, 0.33, 1.0 } },
                { 0.46, 0.86, 0.08, 0.08, { 0.62, 0.78, 1.0, 1.0 } },   -- hero (south)
            },
        },
    },

    config = {
        id    = "dark_altar",
        name  = "Dark Altar",
        theme = Altar.theme,
        -- A square-ish chamber so the orbits read; the hero starts at the south
        -- edge and must work toward the central altar.
        arena = {
            width = 50, height = 44, pad = 2, ortho_size = 42.0,
            hero_start = { x = 25, y = 38 },
            -- A steep, near-overhead rig so the ritual reads as top-down 2D.
            cam_offset = { x = 0.0, y = 62.0, z = 16.0 },
        },
        hero  = {
            hp_max = 100.0, dps = 21.0, cleave = 3, attack_range = 1.25,
            speed = 2.3, kite_speed = 2.85,
            -- Pick a hero rig: ATH_ALTAR_HERO = "lightbringer" (default) | "reaver".
            actor = Altar.pick_hero(ATH_COMMON.getenv("ATH_ALTAR_HERO", "lightbringer")),
        },
        archetypes = Altar.archetypes,
        roles      = Altar.roles,
        spawn = {
            interval_start = 0.75, interval_min = 0.32,
            batch_start = 3, batch_max = 7,
            cap_start = 30, cap_max = 88,
            brute_after = 24.0,
        },
        reserve_start = 320.0,
        round_seconds = 14.0,

        -- Alternates the two cheap fliers (wisp / void shade), sprinkles cultists
        -- for ranged pressure, revenants as the wall, and a late dread harbinger.
        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 11 == 0) then
                return "dread_harbinger"
            end
            if D.spawn_counter % 8 == 0 then return "revenant" end
            if D.spawn_counter % 5 == 0 then return "soul_cultist" end
            return (D.spawn_counter % 2 == 0) and "soul_wisp" or "void_shade"
        end,

        hooks = {
            on_start = function(D)
                D.altar = {
                    meter = 0.0, phase = 1, ritual_count = 0,
                    orbiters = {}, bolts = {},
                    next_soul = SOUL_FIRST, next_bolt = BOLT_FIRST,
                    integrity = ALTAR_INTEGRITY, stun_t = 0.0,
                    smashing = false, counter = 0, bolt_counter = 0, ring_angle = 0.0,
                }
                build_altar(D)
            end,

            on_reset = function(D)
                -- The altar STRUCTURE persists under groups.world; only the
                -- transient ritual state + summoned guardians/bolts reset.
                clear_orbiters(D)
                clear_bolts(D)
                if D.altar then
                    D.altar.meter = 0.0
                    D.altar.phase = 1
                    D.altar.ritual_count = 0
                    D.altar.next_soul = SOUL_FIRST
                    D.altar.next_bolt = BOLT_FIRST
                    D.altar.integrity = ALTAR_INTEGRITY
                    D.altar.stun_t = 0.0
                    D.altar.smashing = false
                end
            end,

            on_combat_tick = function(D, dt)
                update_ritual(D, dt)
            end,

            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local al = D.altar
                if not al then return end
                local frac = al.meter / METER_MAX
                local col = PHASE_COLOR[al.phase]
                local barcol = { col[1], col[2], col[3], 0.95 }
                -- The dark soul meter (bottom-left), coloured by phase.
                Art.bar(D.hud, "altar_meter", 24.0, sh - 150.0, 520.0, 30.0, frac, barcol,
                    { label = string.format("RITUAL  %d / 100   -   PHASE %d  %s",
                        math.floor(al.meter + 0.5), al.phase, PHASE_NAME[al.phase]) })
                -- A compact status line beneath: altar integrity + guardian count.
                local stun = (al.stun_t or 0.0) > 0.0 and "  [STUNNED]" or (al.smashing and "  [SHATTERING]" or "")
                Art.quad(D.hud, "altar_status", 24.0, sh - 112.0, 520.0, 40.0, { 0.04, 0.0, 0.06, 0.85 },
                    { border = { 0.80, 0.0, 0.80, 0.9 },
                      label = string.format("Altar integrity %d / %d    Guardians %d%s",
                          math.floor(al.integrity + 0.5), math.floor(ALTAR_INTEGRITY), #al.orbiters, stun) })
            end,
        },
    },
}
