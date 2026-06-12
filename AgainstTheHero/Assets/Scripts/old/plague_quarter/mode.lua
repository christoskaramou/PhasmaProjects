-- Plague Quarter — a 2D side-scroll through a diseased district, Souls-grim.
--
-- THE TWIST ON THE CONTRACT. Like catacombs/condemned, PLAGUE QUARTER re-stages
-- the shared Duel as a SIDE-SCROLLER: the arena is a long, shallow street (the X
-- axis is the quarter, read left->right through three districts), the camera drops
-- to a low side-on angle and FOLLOWS THE HERO, and a Y-up gravity layer rides on
-- top for the rot-gobs' arcing fall and the hero's infection knockdown. He still
-- auto-fights and the diseased still rush him — we re-skin the stage as a rotting
-- city ward and add ONE bespoke system.
--
-- Signature mechanic — INFECTION. A bar (0->100%) the hero fills whenever a plague
-- carrier touches him or he stands in an infection puddle. It DECAYS slowly when
-- he is clean. At 100% he is STUNNED for 3s and sheds a big chunk of HP, then the
-- bar resets to a residue. Two hero classes shape it: the PLAGUE DOCTOR auto-
-- medicates (a recurring immunity window on a 3s cooldown), the IRON IMMUNE simply
-- soaks far less per touch. ROT THROWERS lob arcing gobs that bloom into puddles on
-- the cobbles; PLAGUE BEARERS infect on contact. Pure pressure that forces clean
-- footing — a clean demo of the hazard API (D:apply_hero_damage) and the mode-owned
-- debuff (D.hero.move_mult during the stun).
--
-- QUARANTINE (the horde's bespoke play): the street is cut into 3 districts (SLUMS
-- / MARKET / CATHEDRAL) by quarantine points. The horde banks ACTION POINTS; when
-- the hero nears an open seal it SPENDS them to slam a diseased barrier across the
-- street and summon the guards that hold it. The hero is caged until he clears the
-- knot of guards (the seal "rots through") and the barrier dissolves. And in the
-- CATHEDRAL the PLAGUELORD wakes — a bespoke boss that HUNTS the hero and looses an
-- AoE PESTILENCE BURST (heavy damage + a flood of infection). Everything is
-- ath_art primitives, self-lit, and texture-ready; the seamless floor/wall PNGs and
-- the puddle/barrier sprites are wired live (see tools/gen_textures_plague.py).

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Pq  = ATH_COMMON.load_script("Scripts/modes/plague_quarter/characters.lua", "plague_quarter characters", _ENV)

-- ---- Physics + tuning ------------------------------------------------------
local GRAVITY = 9.8          -- units/s^2 — the mode-owned Y-axis pull (brief)
local KNOCK_APEX = 0.7       -- how high the stun-knockdown stagger pops, world units

-- INFECTION — the signature bar.
local INFECT_MAX     = 100.0
local INFECT_DECAY   = 6.0   -- %/sec the bar bleeds off while the hero is clean
local INFECT_TOUCH   = 22.0  -- %/sec a plague carrier in contact pumps in
local INFECT_PUDDLE  = 30.0  -- %/sec standing in a puddle pumps in
local INFECT_BURST   = 45.0  -- % a Plaguelord pestilence burst dumps at once
local CONTACT_RANGE  = 1.05  -- how near a carrier must be to infect
local STUN_TIME      = 3.0   -- seconds frozen at 100%
local STUN_HP_LOSS   = 26.0  -- HP shed when the bar caps out
local STUN_RESIDUE   = 18.0  -- the bar resets here (not zero) after a stun
local PUDDLE_DPS      = 5.0  -- light chip damage while in a puddle (the rot bites)

-- INFECTION PUDDLES — the floor hazard the Rot Throwers seed.
local PUDDLE_INTERVAL = 2.4  -- seconds between thrown puddles (while a thrower lives)
local PUDDLE_MIN      = 1.4  -- starting radius
local PUDDLE_MAX      = 2.6  -- radius once fully spread
local PUDDLE_SPREAD   = 1.5  -- seconds to spread to full
local PUDDLE_LIFE     = 8.0  -- seconds before it dries and fades
local PUDDLE_CAP      = 7    -- max live puddles
local PUDDLE_HIDDEN_Y  = -20.0

-- QUARANTINE — the action-point economy that seals districts.
local AP_RATE = 7.0          -- action points banked per second of combat
local AP_MAX = 100.0         -- cap on the horde's stored action points
local SEAL_COST = 34.0       -- AP the horde spends to slam one barrier
local SEAL_RANGE = 7.0       -- hero must be approaching within this to trip a seal
local SEAL_HOLD = 5.5        -- min seconds caged before the seal can rot through
local SEAL_CLEAR = 6.0       -- no live guard within this radius -> seal dissolves
local SEAL_GUARDS = 3        -- guards summoned when a barrier slams

-- Barrier animation (a diseased membrane drops from above the street).
local BAR_TOP = 6.2          -- parked height above the street
local BAR_SLAM = 0.35        -- drop time (parked -> floor)
local BAR_RISE = 0.7         -- dissolve/raise time when the seal rots through
local BAR_BLOCK = 0.9        -- how far in front of a barrier it stops the hero

-- The Plaguelord hunt (cathedral district).
local LORD_SPEED = 2.05      -- a touch under the hero's sprint — outrun, don't out-stand
local LORD_RAGE_SPEED = 2.7
local LORD_HIT = 15.0        -- contact strike damage
local LORD_REACH = 1.4
local LORD_HIT_CD = 1.1
local LORD_BURST_CD = 5.0    -- seconds between pestilence bursts
local LORD_BURST_R = 4.0     -- pestilence burst radius
local LORD_BURST_DMG = 18.0  -- pestilence burst damage if caught

local PARALLAX = 0.7         -- background world-shift per hero unit (faked depth)

-- ---------------------------------------------------------------------------
-- Stage dressing (built once, in on_start) — district floors, torches, exit.
-- ---------------------------------------------------------------------------

-- A guttering wall torch: an iron bracket + an emissive flame core we pulse every
-- tick. torch_sheet.png is the artist drop-in; the live flicker is procedural.
local function build_torch(D, x, y, z)
    local g = D.groups.world
    Art.cube("Pq_Torch_Haft_" .. x, vec3(x, y - 0.35, z), vec3(0.08, 0.7, 0.08), Pq.palette.iron, g, 0.4)
    Art.cube("Pq_Torch_Bracket_" .. x, vec3(x, y, z), vec3(0.22, 0.1, 0.22), Pq.palette.iron, g, 0.4)
    local flame = Art.sphere("Pq_Torch_Flame_" .. x, vec3(x, y + 0.32, z), vec3(0.24, 0.42, 0.24), Pq.palette.torch, g, 1.8)
    -- texture = Pq.tex.torch  -- 4-frame flame sheet drop-in
    return { node = flame, x = x, base_y = y + 0.32, seed = x * 1.7 }
end

-- A leaning, plague-marked house front recessed into the back wall — pure dressing.
local function build_house(D, x, z)
    local g = D.groups.world
    Art.cube("Pq_House_" .. x, vec3(x, 1.6, z + 0.3), vec3(2.4, 3.2, 0.3), Pq.palette.dark, g, 0.2)
    -- A boarded, infection-daubed door (a quarantine cross painted on it).
    Art.cube("Pq_Door_" .. x, vec3(x, 0.8, z - 0.2), vec3(0.9, 1.6, 0.12), Pq.palette.stone, g, 0.3)
    Art.cube("Pq_Cross_V_" .. x, vec3(x, 0.9, z - 0.28), vec3(0.10, 0.9, 0.04), Pq.palette.infect, g, 1.1)
    Art.cube("Pq_Cross_H_" .. x, vec3(x, 0.9, z - 0.28), vec3(0.5, 0.10, 0.04), Pq.palette.infect, g, 1.1)
end

-- ---- INFECTION PUDDLES: the floor hazard ----------------------------------

-- Bloom a puddle on the cobbles at world-x (z at street centre). Starts small and
-- spreads (the 4-frame sprite reads as it grows), then dries and fades.
local function hide_puddle_node(node)
    if not Art.valid(node) then return end
    node:set_position(vec3(0.0, PUDDLE_HIDDEN_Y, 0.0))
    node:set_scale(vec3(0.001, 0.001, 0.001))
    material.set(node, "emissive", vec3(0.0, 0.0, 0.0))
end

local function init_puddle_pool(D)
    local e = D.plague
    if not e then return end
    e.puddle_pool = e.puddle_pool or {}
    for i = #e.puddle_pool + 1, PUDDLE_CAP do
        local node = Art.cylinder("Pq_PuddlePool_" .. i, vec3(0.0, PUDDLE_HIDDEN_Y, 0.0),
            vec3(0.001, 0.001, 0.001), Pq.palette.infect, D.groups.world, 0.0, Pq.tex.puddle)
        e.puddle_pool[i] = { node = node, active = false }
    end
    for _, slot in ipairs(e.puddle_pool) do
        slot.active = false
        hide_puddle_node(slot.node)
    end
    e.puddles = {}
end

local function acquire_puddle(D)
    for _, slot in ipairs(D.plague and D.plague.puddle_pool or {}) do
        if not slot.active and Art.valid(slot.node) then
            slot.active = true
            return slot
        end
    end
    return nil
end

local function bloom_puddle(D, x)
    local e = D.plague
    if #e.puddles >= PUDDLE_CAP then return end
    local A = D.arena
    x = math.max(A.pad + 1.0, math.min(A.w - A.pad - 1.0, x))
    local zc = A.h * 0.5
    local slot = acquire_puddle(D)
    if not slot then return end
    local disc = slot.node
    disc:set_position(vec3(x, 0.04, zc))
    disc:set_scale(vec3(PUDDLE_MIN, 0.05, PUDDLE_MIN))
    material.set(disc, "emissive", vec3(0.0, 1.0, 0.0))
    e.counter = e.counter + 1
    e.puddles[#e.puddles + 1] = { x = x, z = zc, r = PUDDLE_MIN, t = 0.0, node = disc, slot = slot }
    Art.burst("ath_plague_splat_" .. e.counter, vec3(x, 0.3, zc),
        { preset = "hero_take", count = 12, life_max = 0.35, spawn_radius = PUDDLE_MIN * 0.5, noise_strength = 4.0, size_max = 0.20 })
end

local function clear_puddles(D)
    for _, p in ipairs(D.plague and D.plague.puddles or {}) do
        if p.slot then p.slot.active = false end
        hide_puddle_node(p.node)
    end
    if D.plague then D.plague.puddles = {} end
end

-- Returns true if (x) is over a live puddle (used for the per-tick infection gain).
local function in_puddle(D, x, z)
    for _, p in ipairs(D.plague.puddles) do
        local dx, dz = x - p.x, z - p.z
        if dx * dx + dz * dz <= p.r * p.r then return true end
    end
    return false
end

local function update_puddles(D, dt)
    local e = D.plague
    -- Seed new puddles where the Rot Throwers aim: a gob arcs to land near the hero.
    e.puddle_next = e.puddle_next - dt
    if e.puddle_next <= 0.0 then
        e.puddle_next = PUDDLE_INTERVAL
        local thrower = nil
        for _, c in ipairs(D.creeps) do
            if c.alive and c.archetype == "rot_thrower" then thrower = c; break end
        end
        if thrower and not D.hero.dead then
            -- Land it near the hero with a little lead/scatter (the lob's gravity arc
            -- is the rot_thrower's own projectile; this is where it pools).
            local lead = (math.random() * 2.0 - 1.0) * 2.0
            bloom_puddle(D, D.hero.x + lead)
        end
    end

    -- Advance each puddle: spread, hold, then dry up.
    local keep = {}
    for _, p in ipairs(e.puddles) do
        p.t = p.t + dt
        local alive = true
        local spread = math.min(1.0, p.t / PUDDLE_SPREAD)
        p.r = PUDDLE_MIN + (PUDDLE_MAX - PUDDLE_MIN) * spread
        if p.t >= PUDDLE_LIFE then
            if p.slot then p.slot.active = false end
            hide_puddle_node(p.node)
            alive = false
        elseif Art.valid(p.node) then
            -- Pulse the pool and shrink it back as it dries (last second).
            local fade = (p.t > PUDDLE_LIFE - 1.0) and (PUDDLE_LIFE - p.t) or 1.0
            local r = p.r * math.max(0.2, fade)
            p.node:set_scale(vec3(r, 0.05, r))
            local pulse = 0.9 + 0.4 * math.sin(D.realtime * 5.0 + p.x)
            material.set(p.node, "emissive", vec3(0.0, 0.8 * pulse * math.max(0.3, fade), 0.0))
        end
        if alive then keep[#keep + 1] = p end
    end
    e.puddles = keep
end

-- ---- INFECTION: the bar, the stun, and the class modifiers -----------------

-- How much the bar resists this frame: the class infect_mult, zeroed during a
-- Plague Doctor's auto-medication immunity window.
local function infect_scale(D)
    local e = D.plague
    if e.immune_t > 0.0 then return 0.0 end
    return e.infect_mult
end

local function add_infection(D, amount)
    local e = D.plague
    if e.stun_t > 0.0 then return end                 -- already maxed/stunned
    e.infection = math.min(INFECT_MAX, e.infection + amount * infect_scale(D))
end

local function trigger_stun(D)
    local e = D.plague
    e.stun_t = STUN_TIME
    e.infection = STUN_RESIDUE
    D:apply_hero_damage(STUN_HP_LOSS, { flash = "INFECTED — STUNNED!" })
    -- Knockdown stagger (gravity arc, sells the collapse).
    e.knock.active = true; e.knock.t = 0.0
    Art.burst("ath_plague_stun", vec3(D.hero.x, 0.9, D.hero.z),
        { preset = "hero_take", count = 22, life_max = 0.5, spawn_radius = 1.2, noise_strength = 5.0, size_max = 0.28 })
end

local function update_infection(D, dt)
    local e = D.plague
    local hero = D.hero

    -- Plague Doctor auto-medicates: when the bar is rising and his salve is ready,
    -- he opens an immunity window, then it goes on cooldown.
    if e.immunity then
        e.immune_t = math.max(0.0, e.immune_t - dt)
        e.immune_cd = math.max(0.0, e.immune_cd - dt)
        if e.immune_t <= 0.0 and e.immune_cd <= 0.0 and e.infection >= 35.0 and not hero.dead then
            e.immune_t = e.immunity.window
            e.immune_cd = e.immunity.cd + e.immunity.window
            D:set_flash("ANTITOXIN")
        end
    end

    if hero.dead then e.stun_t = 0.0; e.knock.active = false; return end

    -- Stun countdown: while stunned the hero is frozen (move_mult 0; engine never
    -- resets it, so we re-assert every frame — 1.0 when free).
    if e.stun_t > 0.0 then
        e.stun_t = math.max(0.0, e.stun_t - dt)
        hero.move_mult = 0.0
    else
        hero.move_mult = 1.0

        -- Contact infection from plague carriers (the melee infect-on-hit).
        local cr2 = CONTACT_RANGE * CONTACT_RANGE
        local touched = false
        for _, c in ipairs(D.creeps) do
            if c.alive and c.archetype == "plague_bearer" then
                local dx, dz = c.x - hero.x, c.z - hero.z
                if dx * dx + dz * dz <= cr2 then touched = true; break end
            end
        end
        if touched then add_infection(D, INFECT_TOUCH * dt) end

        -- Puddle infection + a light chip of rot damage.
        if in_puddle(D, hero.x, hero.z) then
            add_infection(D, INFECT_PUDDLE * dt)
            D:apply_hero_damage(PUDDLE_DPS * dt)
        end

        -- Clean decay when nothing is feeding the bar.
        if not touched and not in_puddle(D, hero.x, hero.z) then
            e.infection = math.max(0.0, e.infection - INFECT_DECAY * dt)
        end

        -- Cap-out -> stun.
        if e.infection >= INFECT_MAX then trigger_stun(D) end
    end
end

-- ---- QUARANTINE: the diseased barriers (the signature horde play) ----------

-- A barrier = a rack of struts + a membrane pane parked above the street that
-- drops to cage the district. It spans the street depth so the side-on view reads
-- as a wall when slammed.
local function build_barrier(D, x)
    local g = D.groups.world
    local A = D.arena
    local zc = A.h * 0.5
    local struts = {}
    for i = -1, 1 do
        local bz = zc + i * 1.1
        local b = Art.cube("Pq_Bar_Strut_" .. math.floor(x) .. "_" .. (i + 1),
            vec3(x, BAR_TOP, bz), vec3(0.18, 3.0, 0.18), Pq.palette.iron, g, 0.6)
        struts[#struts + 1] = { node = b, x = x, z = bz }
    end
    -- The membrane: a translucent diseased pane (infection-daubed) the struts hold.
    local pane = Art.cube("Pq_Bar_Pane_" .. math.floor(x), vec3(x, BAR_TOP, zc),
        vec3(0.10, 3.0, A.h - A.pad * 2.0), Pq.palette.sick, g, 1.0, Pq.tex.barrier)
    struts[#struts + 1] = { node = pane, x = x, z = zc, pane = true }
    -- A header beam the membrane hangs from.
    Art.cube("Pq_Bar_Header_" .. math.floor(x), vec3(x, 3.1, zc), vec3(0.5, 0.5, A.h - A.pad * 2.0), Pq.palette.stone, g, 0.5)
    return {
        x = x, bars = struts,
        state = "open",        -- open | down | rising
        bar_y = BAR_TOP, t = 0.0, hold_t = 0.0, passed = false,
    }
end

local function set_bar_y(bar, y)
    bar.bar_y = y
    for _, b in ipairs(bar.bars) do
        if Art.valid(b.node) then b.node:set_position(vec3(b.x, y, b.z)) end
    end
end

-- Count live creeps milling near a barrier (the guards holding the seal).
local function guards_near(D, x, r)
    local n = 0
    for _, c in ipairs(D.creeps) do
        if c.alive then
            local dx = c.x - x
            if dx * dx <= r * r then n = n + 1 end
        end
    end
    return n
end

-- Slam a barrier shut: membrane drops, and a knot of guards is summoned to hold the
-- seal. This is the horde "spending action points to quarantine the district".
local function slam_barrier(D, bar)
    if bar.state ~= "open" or bar.passed then return false end
    bar.state = "down"; bar.t = 0.0; bar.hold_t = 0.0
    D:set_flash("QUARANTINE!")
    Art.burst("ath_plague_seal_" .. math.floor(bar.x), vec3(bar.x, 1.2, D.arena.h * 0.5),
        { preset = "hero_take", count = 18, life_max = 0.35, spawn_radius = 0.8, noise_strength = 5.0, size_max = 0.26 })
    for i = 1, SEAL_GUARDS do
        local sx = bar.x + (i - 2) * 0.6
        D:spawn_one({ x = sx, y = D.arena.h * 0.5 + 0.5 }, (i == SEAL_GUARDS) and "quarantine_guard" or "plague_bearer", true)
    end
    return true
end

local function update_quarantine(D, dt)
    local e = D.plague
    local hero = D.hero

    e.ap = math.min(AP_MAX, e.ap + AP_RATE * dt)

    -- Cage the district ahead: the nearest OPEN, unpassed barrier the hero walks
    -- into. Spend AP to slam it.
    if not hero.dead then
        for _, bar in ipairs(e.barriers) do
            if bar.state == "open" and not bar.passed and hero.x < bar.x then
                local d = bar.x - hero.x
                if d <= SEAL_RANGE and e.ap >= SEAL_COST then
                    if slam_barrier(D, bar) then e.ap = e.ap - SEAL_COST end
                end
                break
            end
        end
    end

    for _, bar in ipairs(e.barriers) do
        if bar.state == "down" then
            if bar.bar_y > 3.0 then
                bar.t = bar.t + dt
                local p = math.min(1.0, bar.t / BAR_SLAM)
                set_bar_y(bar, BAR_TOP + (3.0 - BAR_TOP) * p)
            else
                bar.hold_t = bar.hold_t + dt
                -- Cage the hero behind the membrane (the forced fight-through).
                if not hero.dead and hero.x < bar.x then
                    hero.x = math.min(hero.x, bar.x - BAR_BLOCK)
                end
                -- The seal rots through once he's held long enough AND cleared the guards.
                if bar.hold_t >= SEAL_HOLD and guards_near(D, bar.x, SEAL_CLEAR) == 0 then
                    bar.state = "rising"; bar.t = 0.0
                    D:set_flash("SEAL BREACHED")
                end
            end
            -- Pulse the membrane while it holds, so the player reads the danger.
            for _, b in ipairs(bar.bars) do
                if b.pane and Art.valid(b.node) then
                    local f = 0.7 + 0.6 * (0.5 + 0.5 * math.sin(D.realtime * 7.0))
                    material.set(b.node, "emissive", vec3(0.0, 0.8 * f, 0.0))
                end
            end
        elseif bar.state == "rising" then
            bar.t = bar.t + dt
            local p = math.min(1.0, bar.t / BAR_RISE)
            set_bar_y(bar, 3.0 + (BAR_TOP - 3.0) * p)
            if p >= 1.0 then bar.state = "open"; set_bar_y(bar, BAR_TOP) end
        end
        if not bar.passed and bar.state == "open" and hero.x > bar.x + 1.0 then
            bar.passed = true
        end
    end
end

local function clear_barriers(D)
    for _, bar in ipairs(D.plague and D.plague.barriers or {}) do
        for _, b in ipairs(bar.bars) do if Art.valid(b.node) then scene.delete_node(b.node) end end
    end
    if D.plague then D.plague.barriers = {} end
end

-- ---- The PLAGUELORD hunt (cathedral district) ------------------------------

-- A bespoke boss built from a primitive rig — NOT a card creep. He wakes when the
-- hero crosses into the cathedral and then relentlessly tracks the hero's X,
-- striking on contact and venting a PESTILENCE BURST on a cooldown.
local function build_plaguelord(D)
    local spec = {
        name = "Pq_Plaguelord_Hunter",
        parts = {
            body = { kind = "cube", position = { 0.0, 0.70, 0.0 }, scale = { 0.56, 1.02, 0.44 }, color = Pq.palette.sick, emissive = 0.5 },
            head = { kind = "cube", position = { 0.0, 1.40, 0.0 }, scale = { 0.36, 0.34, 0.36 }, color = Pq.palette.dark, emissive = 0.6 },
            foot_r = { kind = "cube", position = { 0.16, 0.05, 0.0 }, scale = { 0.22, 0.10, 0.28 }, color = Pq.palette.void, emissive = 0.3 },
            foot_l = { kind = "cube", position = { -0.16, 0.05, 0.0 }, scale = { 0.22, 0.10, 0.28 }, color = Pq.palette.void, emissive = 0.3 },
            sword = { kind = "cube", position = { 0.50, 0.70, 0.08 }, scale = { 0.14, 0.96, 0.16 }, color = Pq.palette.stone, emissive = 0.8 },
            crown = { kind = "cube", position = { 0.0, 1.64, 0.0 }, scale = { 0.46, 0.14, 0.46 }, color = Pq.palette.pale, emissive = 0.9 },
            boil = { kind = "sphere", position = { 0.0, 0.86, 0.30 }, scale = { 0.30, 0.30, 0.24 }, color = Pq.palette.infect, emissive = 1.6 },
            eye_l = { kind = "sphere", position = { -0.12, 1.42, 0.18 }, scale = { 0.11, 0.08, 0.05 }, color = Pq.palette.infect, emissive = 2.2 },
            eye_r = { kind = "sphere", position = { 0.12, 1.42, 0.18 }, scale = { 0.11, 0.08, 0.05 }, color = Pq.palette.infect, emissive = 2.2 },
        },
        -- texture = Pq.tex.plaguelord,  -- 8-frame sprite-sheet drop-in
    }
    local actor = Art.build_actor(spec, D.groups.world)
    local cs = Art.s("char") * 1.6
    if Art.valid(actor.root) then
        actor.root:set_scale(vec3(cs, cs, cs))
        actor.root:set_position(vec3(D.arena.w - D.arena.pad - 1.0, -8.0, D.arena.h * 0.5 + 0.6))
    end
    -- The pestilence-burst ring (a flat disc we flash and grow on a burst).
    local ring = Art.cylinder("Pq_Lord_Burst", vec3(0.0, 0.06, D.arena.h * 0.5),
        vec3(0.1, 0.05, 0.1), Pq.palette.infect, D.groups.world, 0.0)
    return {
        actor = actor, ring = ring, x = D.arena.w - D.arena.pad - 1.0, z = D.arena.h * 0.5 + 0.6,
        active = false, rage = false, hit_cd = 0.0, burst_cd = LORD_BURST_CD, burst_t = -1.0, phase = 0.0,
    }
end

local function lord_burst(D)
    local w = D.plague.boss
    w.burst_t = 0.0
    D:set_flash("PESTILENCE!")
    if not D.hero.dead then
        local dx = D.hero.x - w.x
        if dx * dx <= LORD_BURST_R * LORD_BURST_R then
            D:apply_hero_damage(LORD_BURST_DMG * (w.rage and 1.3 or 1.0), { flash = "PESTILENCE BURST!" })
            add_infection(D, INFECT_BURST)
        end
    end
    Art.burst("ath_plague_burst", vec3(w.x, 0.6, w.z),
        { preset = "hero_take", count = 30, life_max = 0.6, spawn_radius = LORD_BURST_R * 0.5, noise_strength = 6.0, size_max = 0.34 })
end

local function update_plaguelord(D, dt)
    local w = D.plague.boss
    local hero = D.hero
    if not w then return end

    -- Wake in the cathedral: the hero has cleared into the final district.
    if not w.active and not hero.dead and hero.x >= D.plague.cathedral_x then
        w.active = true
        w.x = math.min(D.arena.w - D.arena.pad - 1.0, hero.x + 9.0)
        D:set_flash("THE PLAGUELORD RISES")
    end
    if not w.active then return end

    w.hit_cd = math.max(0.0, w.hit_cd - dt)
    w.burst_cd = math.max(0.0, w.burst_cd - dt)
    if not hero.dead then
        local spd = w.rage and LORD_RAGE_SPEED or LORD_SPEED
        local dir = (hero.x > w.x) and 1.0 or -1.0
        w.x = w.x + dir * spd * dt
        local dx = hero.x - w.x
        if dx * dx <= LORD_REACH * LORD_REACH and w.hit_cd <= 0.0 then
            D:apply_hero_damage(LORD_HIT * (w.rage and 1.4 or 1.0), { flash = "THE PLAGUELORD STRIKES!" })
            add_infection(D, INFECT_TOUCH)
            w.hit_cd = LORD_HIT_CD
        end
        -- Vent a pestilence burst on cadence (tighter when enraged).
        if w.burst_cd <= 0.0 then
            w.burst_cd = LORD_BURST_CD * (w.rage and 0.65 or 1.0)
            lord_burst(D)
        end
    end

    -- Burst ring visual: a flat green disc that flares out then fades.
    if w.burst_t >= 0.0 then
        w.burst_t = w.burst_t + dt
        local f = math.min(1.0, w.burst_t / 0.5)
        if Art.valid(w.ring) then
            local r = 0.1 + LORD_BURST_R * f
            w.ring:set_position(vec3(w.x, 0.06, w.z))
            w.ring:set_scale(vec3(r, 0.05, r))
            material.set(w.ring, "emissive", vec3(0.0, 0.9 * (1.0 - f), 0.0))
        end
        if w.burst_t >= 0.5 then w.burst_t = -1.0 end
    end

    w.phase = w.phase + dt * (w.rage and 11.0 or 8.0)
    if Art.valid(w.actor.root) then
        local face = (hero.x >= w.x) and 90.0 or -90.0
        w.actor.root:set_position(vec3(w.x, 0.0, w.z))
        w.actor.root:set_rotation(vec3(0.0, face, 0.0))
    end
    Art.animate(w.actor, "walk", w.phase / 8.0)
end

-- ---- Hero Y-axis physics: the gravity knockdown stagger ---------------------

local function update_hero_physics(D, dt)
    local hero = D.hero
    local k = D.plague.knock
    if hero.dead then k.active = false; return end

    -- Gravity-arc stagger when the infection caps out (cosmetic; the stun freezes X).
    if k.active then
        k.t = k.t + dt
        local v0 = math.sqrt(2.0 * GRAVITY * KNOCK_APEX)
        k.y = v0 * k.t - 0.5 * GRAVITY * k.t * k.t
        if k.y <= 0.0 and k.t > 0.05 then k.active = false; k.y = 0.0 end
    end

    -- Apply the Y lift on top of what update_hero already wrote (on_combat_tick runs
    -- AFTER update_hero, so this is the final say on the root).
    if Art.valid(hero.root) then
        hero.root:set_position(vec3(hero.x, k.y, hero.z))
        hero.root:set_rotation(vec3(0.0, math.deg(hero.facing or 0.0), 0.0))
        local ws = hero.world_scale or 1.0
        -- A green sickly tint pulses on the hero as the infection climbs.
        if D.plague.infection > 1.0 then
            local g = math.min(1.0, D.plague.infection / INFECT_MAX)
            local body = hero.actor_parts and hero.actor_parts.body
            if Art.valid(body) then material.set(body, "emissive", vec3(0.0, 0.6 * g, 0.0)) end
        end
        hero.root:set_scale(vec3(ws, ws, ws))
    end
end

-- ---- WIN: reach the cathedral doors at the far end -------------------------

local function update_escape(D)
    local e = D.plague
    if D.hero.dead then return end
    if D.hero.x >= e.exit_x then
        D.state = "hero_win"
        D:set_flash("THE DOORS SEAL")
        D:log(string.format("PLAGUE QUARTER ESCAPE round=%d kills=%d", D.round, D.kills))
    end
end

-- ---- Camera: a side-on rig that tracks the hero down the quarter ------------

local function update_camera(D)
    local A = D.arena
    local half = A.ortho_size * 0.5
    local cx = math.max(A.pad + half * 0.4, math.min(A.w - A.pad - half * 0.4, D.hero.x))
    Art.setup_iso_camera({ x = cx, z = A.h * 0.5 - 0.5 },
        { ortho_size = A.ortho_size, offset = A.cam_offset })
    if Art.valid(D.plague.bg) then D.plague.bg:set_position(vec3(PARALLAX * cx, 3.2, A.h - A.pad + 1.2)) end
end

-- Which district the hero stands in (for the HUD).
local function district_name(D)
    local e = D.plague
    if D.hero.x >= e.cathedral_x then return "CATHEDRAL" end
    if D.hero.x >= e.market_x then return "MARKET" end
    return "SLUMS"
end

-- ---- Hero class selection (two classes; brief) -----------------------------

local function pick_hero()
    local class = "plague_doctor"
    if ATH_COMMON and ATH_COMMON.getenv then
        local v = ATH_COMMON.getenv("ATH_PLAGUE_CLASS")
        if type(v) == "string" and Pq.heroes[v:lower()] then class = v:lower() end
    end
    return class, Pq.heroes[class]
end

local CLASS, HERO = pick_hero()

-- ---------------------------------------------------------------------------
-- Mode contract
-- ---------------------------------------------------------------------------

return {
    meta = {
        id = "plague_quarter",
        name = "Plague Quarter",
        tagline = "the side-scrolling rot of a dying district",
        blurb = "A 2D side-scroller through a diseased ward — slums, market, cathedral. Plague carriers infect on touch and pool the cobbles with rot; let the bar hit 100% and you collapse. The horde quarantines each district behind diseased barriers, and the Plaguelord hunts the cathedral.",
        side_hint = "horde",
        accent = { 0.0, 0.80, 0.0, 0.95 },
        -- A side-on sketch of the quarter (normalized 0..1 rects: x,y,w,h,color).
        minimap = {
            bg = { 0.051, 0.051, 0.0, 1.0 },
            rects = {
                { 0.04, 0.62, 0.92, 0.10, { 0.165, 0.165, 0.0, 1.0 } }, -- cobble street
                { 0.04, 0.18, 0.92, 0.12, { 0.102, 0.102, 0.0, 1.0 } }, -- house-front band
                { 0.07, 0.46, 0.05, 0.16, { 0.62, 0.60, 0.50, 1.0 } },  -- hero (left)
                { 0.36, 0.30, 0.02, 0.32, { 0.0, 0.80, 0.0, 1.0 } },    -- barrier 1
                { 0.64, 0.30, 0.02, 0.32, { 0.0, 0.80, 0.0, 1.0 } },    -- barrier 2
                { 0.26, 0.58, 0.06, 0.04, { 0.0, 0.80, 0.0, 1.0 } },    -- puddles
                { 0.52, 0.58, 0.07, 0.04, { 0.0, 0.80, 0.0, 1.0 } },
                { 0.46, 0.50, 0.04, 0.12, { 0.290, 0.400, 0.0, 1.0 } }, -- plague bearers
                { 0.88, 0.42, 0.06, 0.20, { 0.0, 0.80, 0.0, 1.0 } },    -- the Plaguelord
                { 0.18, 0.24, 0.02, 0.10, { 0.80, 0.40, 0.0, 1.0 } },   -- torches
                { 0.62, 0.24, 0.02, 0.10, { 0.80, 0.40, 0.0, 1.0 } },
                { 0.92, 0.40, 0.04, 0.28, { 0.80, 0.40, 0.0, 1.0 } },   -- cathedral doors (right)
            },
        },
    },

    config = {
        id = "plague_quarter",
        name = "Plague Quarter",
        theme = Pq.theme,
        -- A long, shallow STREET. Wide X (read left->right through 3 districts),
        -- shallow Z depth, and a low side-on camera that tracks the hero.
        arena = {
            width = 92, height = 16, pad = 2, ortho_size = 22.0,
            cam_offset = { x = 0.0, y = 10.0, z = -30.0 },   -- side elevation, not iso
            hero_start = { x = 5, y = 8 },
            -- The diseased pour from the FAR (right) end; the hero advances left->
            -- right through slums -> market -> cathedral toward the doors.
            spawns = {
                { x = 86, y = 8 }, { x = 88, y = 6 }, { x = 88, y = 10 },
                { x = 84, y = 5 }, { x = 84, y = 11 }, { x = 80, y = 8 },
            },
        },
        hero = {
            hp_max = HERO.stats.hp_max, dps = HERO.stats.dps, cleave = HERO.stats.cleave,
            attack_range = HERO.stats.attack_range, speed = HERO.stats.speed, kite_speed = HERO.stats.kite_speed,
            actor = HERO.actor,
        },
        archetypes = Pq.archetypes,
        roles = Pq.roles,
        spawn = { interval_start = 0.8, interval_min = 0.35, batch_start = 3, batch_max = 6, cap_start = 28, cap_max = 84, brute_after = 22.0 },
        reserve_start = 320.0,
        round_seconds = 14.0,

        -- A plague mix: bearer chaff + rats, periodic rot throwers, slow quarantine
        -- guards as elites, and a late Plaguelord card.
        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 13 == 0) then return "plaguelord" end
            if D.spawn_counter % 8 == 0 then return "quarantine_guard" end
            if D.spawn_counter % 5 == 0 then return "rot_thrower" end
            return (D.spawn_counter % 2 == 0) and "carrion_rat" or "plague_bearer"
        end,

        hooks = {
            on_start = function(D)
                local A = D.arena
                D.plague = {
                    -- infection bar + class modifiers
                    infection = 0.0, stun_t = 0.0, infect_mult = HERO.infect_mult or 1.0,
                    immunity = HERO.immunity, immune_t = 0.0, immune_cd = 0.0,
                    knock = { active = false, t = 0.0, y = 0.0 },
                    -- puddles
                    puddles = {}, puddle_next = PUDDLE_INTERVAL, counter = 0,
                    -- quarantine
                    barriers = {}, ap = 0.0,
                    -- boss + stage
                    boss = nil, torches = {}, bg = nil, class = CLASS,
                    market_x = 0.0, cathedral_x = 0.0, exit_x = A.w - A.pad - 2.0,
                }
                local g = D.groups.world
                local far_z = A.h - A.pad + 1.2
                init_puddle_pool(D)

                -- A very dark distant skyline (rotting roofs) for parallax depth.
                D.plague.bg = Art.cube("Pq_Background", vec3(PARALLAX * A.w * 0.5, 3.2, far_z),
                    vec3(A.w * 1.6, 8.0, 0.2), { 0.4, 0.4, 0.25 }, g, 0.2, Pq.tex.wall)

                -- A textured infected back wall, panelled so the seamless tile reads.
                local panel = 4.0
                for px = A.pad, A.w - A.pad, panel do
                    Art.cube("Pq_BackWall_" .. math.floor(px), vec3(px + panel * 0.5, 3.3, A.h - A.pad - 0.2),
                        vec3(panel, 6.6, 0.4), Pq.palette.stone, g, 0.5, Pq.tex.wall)
                end

                -- Torch line along the back wall (flicker driven in on_combat_tick).
                for tx = A.pad + 4, A.w - A.pad - 2, 9 do
                    D.plague.torches[#D.plague.torches + 1] = build_torch(D, tx, 3.4, A.h - A.pad - 0.5)
                end

                -- Plague-marked house fronts recessed into the back wall (dressing).
                for cx = A.pad + 6, A.w - A.pad - 6, 8 do
                    build_house(D, cx, A.h - A.pad - 1.1)
                end

                -- The two QUARANTINE barriers that cut the street into 3 districts.
                local span = A.w - A.pad * 2.0
                D.plague.market_x = A.pad + span * 0.34
                D.plague.cathedral_x = A.pad + span * 0.66
                D.plague.barriers[#D.plague.barriers + 1] = build_barrier(D, D.plague.market_x)
                D.plague.barriers[#D.plague.barriers + 1] = build_barrier(D, D.plague.cathedral_x)

                -- The dormant Plaguelord, parked below the floor until the cathedral.
                D.plague.boss = build_plaguelord(D)

                -- The CATHEDRAL DOORS (the exit to safety) at the far-right end.
                local ex = A.w - A.pad - 1.5
                Art.cube("Pq_Door_Frame_L", vec3(ex - 1.0, 1.9, A.h * 0.5), vec3(0.4, 3.8, 0.5), Pq.palette.stone, g, 0.5)
                Art.cube("Pq_Door_Frame_R", vec3(ex + 1.0, 1.9, A.h * 0.5), vec3(0.4, 3.8, 0.5), Pq.palette.stone, g, 0.5)
                Art.cube("Pq_Door_Arch", vec3(ex, 3.9, A.h * 0.5), vec3(2.6, 0.5, 0.5), Pq.palette.stone, g, 0.5)
                D.plague.portal = Art.cube("Pq_Door_Glow", vec3(ex, 1.8, A.h * 0.5), vec3(1.6, 3.4, 0.12), Pq.palette.torch, g, 1.3)

                update_camera(D)
            end,

            on_reset = function(D)
                -- NIL-GUARD (can fire before on_start). Drop the barriers/boss and
                -- reset the infection state; the street/walls survive in `world`.
                clear_barriers(D)
                clear_puddles(D)
                if D.plague then
                    if D.plague.boss and Art.valid(D.plague.boss.actor.root) then
                        scene.delete_node(D.plague.boss.actor.root)
                    end
                    if D.plague.boss and Art.valid(D.plague.boss.ring) then
                        scene.delete_node(D.plague.boss.ring)
                    end
                    D.plague.infection = 0.0; D.plague.stun_t = 0.0
                    D.plague.immune_t = 0.0; D.plague.immune_cd = 0.0
                    D.plague.knock = { active = false, t = 0.0, y = 0.0 }
                    D.plague.ap = 0.0
                    D.plague.puddle_next = PUDDLE_INTERVAL
                    if D.hero then D.hero.move_mult = 1.0 end
                    init_puddle_pool(D)
                    -- Re-seat the two barriers + the boss the run started with.
                    local A = D.arena
                    D.plague.barriers[#D.plague.barriers + 1] = build_barrier(D, D.plague.market_x)
                    D.plague.barriers[#D.plague.barriers + 1] = build_barrier(D, D.plague.cathedral_x)
                    D.plague.boss = build_plaguelord(D)
                end
            end,

            on_card = function(D, side, card_id, effect)
                -- The Horde's signature flourish: a back-face creature play banks a
                -- surge of quarantine action points (so a played card can trigger a
                -- seal sooner — the brief's "horde spends AP to seal a section").
                if D.plague and side == "horde" then
                    D.plague.ap = math.min(AP_MAX, D.plague.ap + SEAL_COST * 0.5)
                end
            end,

            on_combat_tick = function(D, dt)
                update_infection(D, dt)      -- the bar; sets move_mult; may stun
                update_puddles(D, dt)        -- seed + age the floor hazards
                update_quarantine(D, dt)     -- may cage the hero (clamp x)
                update_plaguelord(D, dt)     -- the cathedral boss hunt + burst
                update_hero_physics(D, dt)   -- writes the final hero root transform
                update_escape(D)             -- win on the cathedral doors
                update_camera(D)
                -- Torch flicker: emissive wobble + a touch of random guttering.
                for _, t in ipairs(D.plague.torches) do
                    if Art.valid(t.node) then
                        local f = 1.3 + 0.5 * math.sin(D.realtime * 11.0 + t.seed) + 0.2 * math.sin(D.realtime * 27.0 + t.seed * 2.0)
                        material.set(t.node, "emissive", vec3(0.80 * f, 0.40 * f, 0.0))
                    end
                end
                -- The cathedral doors beckon with a slow torch-gold pulse.
                if Art.valid(D.plague.portal) then
                    local pf = 1.0 + 0.6 * (0.5 + 0.5 * math.sin(D.realtime * 3.0))
                    material.set(D.plague.portal, "emissive", vec3(0.80 * pf, 0.40 * pf, 0.0))
                end
            end,

            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local A = D.arena
                local e = D.plague
                -- District progress toward the far doors (left->right "depth").
                local prog = math.max(0.0, math.min(1.0, (D.hero.x - 5.0) / (e.exit_x - 5.0)))
                local sealed = 0
                for _, bar in ipairs(e.barriers) do if bar.state ~= "open" then sealed = sealed + 1 end end
                local boss = (e.boss and e.boss.active) and (e.boss.rage and "ENRAGED" or "HUNTING") or "dormant"
                Art.quad(D.hud, "pq_panel", 24.0, sh - 150.0, 720.0, 58.0, { 0.051, 0.051, 0.0, 0.9 },
                    { border = { 0.0, 0.80, 0.0, 0.9 },
                      label = string.format("CLASS: %s   District: %s   Depth: %d%%   Quarantines: %d   Plaguelord: %s",
                        e.class:upper(), district_name(D), math.floor(prog * 100.0 + 0.5), sealed, boss) })
                -- The INFECTION bar (0->100%); turns lurid as it nears the stun.
                local pct = (e.infection or 0.0) / INFECT_MAX
                local lurid = e.immune_t > 0.0
                Art.quad(D.hud, "pq_inf_bg", 24.0, sh - 86.0, 360.0, 22.0, { 0.05, 0.08, 0.0, 0.9 },
                    { border = { 0.0, 0.80, 0.0, 0.8 } })
                local fill_col = lurid and { 0.2, 0.6, 1.0, 0.95 } or { 0.2 + 0.6 * pct, 0.8, 0.0, 0.95 }
                Art.quad(D.hud, "pq_inf_fill", 26.0, sh - 84.0, math.max(0.0, 356.0 * pct), 18.0, fill_col,
                    { label = lurid and "IMMUNE" or (e.stun_t > 0.0 and "STUNNED!" or string.format("INFECTION %d%%", math.floor(pct * 100.0 + 0.5))) })
            end,
        },
    },
}
