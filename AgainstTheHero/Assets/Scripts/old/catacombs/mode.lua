-- Catacombs — a 2D side-scrolling crypt corridor with a Souls-like gloom.
--
-- THE TWIST ON THE CONTRACT. Every other mode is viewed top-down; CATACOMBS
-- re-stages the same shared Duel as a SIDE-SCROLLER. The arena is a long, shallow
-- corridor (the X axis is the corridor, read left->right), the camera is dropped
-- to a low side-on angle and FOLLOWS THE HERO horizontally, and a Y-up gravity
-- layer is laid on top of the duel for the things the brief calls for: a
-- gravity-arc hero jump that leaps the traps, free-falling bone debris, patrolling
-- skeletons on raised platforms, and flickering torchlight. The hero still
-- auto-fights and the dead still rush him — we only re-skin the stage and add one
-- bespoke hazard system, exactly as the guide prescribes.
--
-- Signature mechanic — WALL SPIKE TRAPS. Iron spikes are seated along the
-- corridor floor. Each telegraphs with a red glow, then THRUSTS up: anything
-- standing in the column when the spikes lock out is impaled (D:apply_hero_damage).
-- The hero answers with a gravity-arc JUMP — leap an extending trap and the spikes
-- pass harmlessly beneath. Pure pressure on the hero; a clean demo of the hazard
-- API and of the mode-owned Y-axis physics. Everything is ath_art primitives,
-- self-lit, and texture-ready; the seamless wall/floor/background PNGs are wired
-- live (see tools/gen_textures_catacombs.py).

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Cata = ATH_COMMON.load_script("Scripts/modes/catacombs/characters.lua", "catacombs characters", _ENV)

-- ---- Physics + tuning ------------------------------------------------------
local GRAVITY = 9.8          -- units/s^2 — the mode-owned Y-axis pull (brief)
local JUMP_APEX = 1.5        -- peak height of the hero's leap, in world units
local JUMP_CLEAR = 0.45      -- above this height the hero clears the spikes
local ROLL_TIME = 0.42       -- dodge-roll duration

-- Wall spike trap cadence.
local TRAP_SPACING = 11.0    -- world units between trap stations along the corridor
local TRAP_WARN = 1.3        -- red-glow telegraph before the spikes thrust
local TRAP_EXTEND = 0.22     -- thrust time (floor -> locked out)
local TRAP_HOLD = 0.55       -- spikes held at full height
local TRAP_RETRACT = 0.5
local TRAP_CYCLE = 4.2       -- idle time between a trap's activations
local TRAP_RADIUS = 1.5      -- impale reach around a trap column
local TRAP_DAMAGE = 24.0
local TRAP_HEIGHT = 1.3      -- locked-out spike height

local PARALLAX = 0.7         -- background world-shift per hero unit (0=locked, 1=glued to cam)

-- ---------------------------------------------------------------------------
-- Stage dressing (built once, in on_start) — corridor, crypts, torches, layers.
-- ---------------------------------------------------------------------------

-- A flickering wall torch: an iron bracket + an emissive flame core we pulse every
-- tick. torch_sheet.png is the artist drop-in; the live flicker is procedural.
local function build_torch(D, x, y, z)
    local g = D.groups.world
    Art.cube("Torch_Haft_" .. x, vec3(x, y - 0.35, z), vec3(0.08, 0.7, 0.08), Cata.palette.stone, g, 0.4)
    Art.cube("Torch_Bracket_" .. x, vec3(x, y, z), vec3(0.22, 0.1, 0.22), Cata.palette.stone, g, 0.4)
    local flame = Art.sphere("Torch_Flame_" .. x, vec3(x, y + 0.32, z), vec3(0.24, 0.42, 0.24), Cata.palette.torch, g, 1.8)
    -- texture = Cata.tex.torch  -- 4-frame sheet drop-in for the flame quad
    return { node = flame, x = x, base_y = y + 0.32, seed = x * 1.7 }
end

-- A raised platform + its ladder — the corridor's vertical layers (brief).
local function build_platform(D, x, y, z, w)
    local g = D.groups.world
    Art.cube("Platform_" .. x, vec3(x, y, z), vec3(w, 0.3, 1.6), Cata.palette.stone, g, 0.7, Cata.tex.floor)
    Art.cube("Plat_Lip_" .. x, vec3(x, y + 0.18, z + 0.7), vec3(w, 0.12, 0.2), Cata.palette.hilite, g, 0.6)
    -- Ladder at the platform's near edge: two rails + rungs.
    local lx = x - w * 0.5 + 0.4
    Art.cube("Ladder_L_" .. x, vec3(lx - 0.12, y * 0.5, z - 0.6), vec3(0.06, y, 0.06), Cata.palette.rust, g, 0.5)
    Art.cube("Ladder_R_" .. x, vec3(lx + 0.12, y * 0.5, z - 0.6), vec3(0.06, y, 0.06), Cata.palette.rust, g, 0.5)
    for r = 1, math.max(1, math.floor(y / 0.45)) do
        Art.cube("Rung_" .. x .. "_" .. r, vec3(lx, r * 0.45, z - 0.6), vec3(0.30, 0.05, 0.05), Cata.palette.rust, g, 0.5)
    end
    return { x = x, y = y + 0.3, z = z, w = w }
end

-- A patrolling skeleton that walks a platform and turns at the edges (brief:
-- "skeleton patrol AI"). Decorative crypt-life — built from a tiny actor rig so
-- ath_art's walk clip animates its stride. Stays grounded on its platform (the
-- normal force balances gravity); free-fall is demonstrated by the trap debris.
local function build_patrol(D, plat)
    local spec = {
        name = "Patrol_Bones",
        parts = {
            body = { kind = "cube", position = { 0.0, 0.40, 0.0 }, scale = { 0.22, 0.42, 0.18 }, color = Cata.palette.bone, emissive = 0.6 },
            head = { kind = "sphere", position = { 0.0, 0.74, 0.0 }, scale = { 0.20, 0.20, 0.20 }, color = Cata.palette.bone, emissive = 0.6 },
            foot_r = { kind = "cube", position = { 0.08, 0.04, 0.0 }, scale = { 0.12, 0.08, 0.16 }, color = Cata.palette.bone, emissive = 0.5 },
            foot_l = { kind = "cube", position = { -0.08, 0.04, 0.0 }, scale = { 0.12, 0.08, 0.16 }, color = Cata.palette.bone, emissive = 0.5 },
            eye = { kind = "sphere", position = { 0.0, 0.74, 0.14 }, scale = { 0.07, 0.05, 0.04 }, color = Cata.palette.blood, emissive = 1.7 },
        },
    }
    local actor = Art.build_actor(spec, D.groups.world)
    local cs = Art.s("char") * 0.9
    if Art.valid(actor.root) then actor.root:set_scale(vec3(cs, cs, cs)) end
    local margin = plat.w * 0.5 - 0.6
    return {
        actor = actor, y = plat.y, z = plat.z,
        x = plat.x, min = plat.x - margin, max = plat.x + margin,
        dir = 1.0, speed = 1.4 + 0.3 * (plat.x % 2), phase = plat.x,
    }
end

local function update_patrols(D, dt)
    for _, p in ipairs(D.cata.patrols) do
        p.x = p.x + p.dir * p.speed * dt
        if p.x <= p.min then p.x = p.min; p.dir = 1.0 end      -- turn at the edge
        if p.x >= p.max then p.x = p.max; p.dir = -1.0 end
        p.phase = p.phase + dt * 8.0
        if Art.valid(p.actor.root) then
            p.actor.root:set_position(vec3(p.x, p.y, p.z))      -- gravity-grounded on the platform
            p.actor.root:set_rotation(vec3(0.0, p.dir > 0 and 90.0 or -90.0, 0.0))
        end
        Art.animate(p.actor, "walk", p.phase / 8.0)
    end
end

-- ---- Wall spike traps (the signature hazard) -------------------------------

local function build_trap(D, x, z)
    local g = D.groups.world
    -- Floor glow decal (telegraph) — starts dark, pulses red during the warning.
    local glow = Art.cylinder("Trap_Glow_" .. x, vec3(x, 0.05, z), vec3(TRAP_RADIUS * 1.6, 0.04, TRAP_RADIUS * 1.6),
        Cata.palette.blood, g, 0.2)
    -- A cluster of spikes parked BELOW the floor; the thrust raises them.
    local spikes = {}
    local offs = { { -0.5, -0.3 }, { 0.0, 0.0 }, { 0.5, 0.3 }, { -0.3, 0.5 }, { 0.3, -0.5 } }
    for i, o in ipairs(offs) do
        local s = Art.cylinder("Trap_Spike_" .. x .. "_" .. i, vec3(x + o[1], -TRAP_HEIGHT, z + o[2]),
            vec3(0.14, TRAP_HEIGHT, 0.14), Cata.palette.hilite, g, 0.6)
        spikes[i] = { node = s, ox = o[1], oz = o[2] }
    end
    return {
        x = x, z = z, glow = glow, spikes = spikes,
        phase = "idle", t = (x * 0.13) % TRAP_CYCLE, hit = false,
    }
end

local function set_spike_height(trap, h)
    for _, s in ipairs(trap.spikes) do
        if Art.valid(s.node) then
            s.node:set_position(vec3(trap.x + s.ox, h - TRAP_HEIGHT * 0.5, trap.z + s.oz))
        end
    end
end

-- Bone debris shaken loose when spikes thrust — free-falls under GRAVITY (brief).
local function spawn_debris(D, x, z)
    for i = 1, 4 do
        local n = Art.cube("Debris_" .. D.cata.debris_id, vec3(x + (i - 2) * 0.2, TRAP_HEIGHT + 0.4, z),
            vec3(0.08, 0.08, 0.08), Cata.palette.bone, D.groups.world, 0.7)
        D.cata.debris_id = D.cata.debris_id + 1
        D.cata.debris[#D.cata.debris + 1] = { node = n, x = x + (i - 2) * 0.2, y = TRAP_HEIGHT + 0.4, z = z, vy = 1.0 }
    end
end

local function update_debris(D, dt)
    local survivors = {}
    for _, d in ipairs(D.cata.debris) do
        d.vy = d.vy - GRAVITY * dt                 -- gravity acceleration
        d.y = d.y + d.vy * dt
        if d.y <= 0.04 then
            if Art.valid(d.node) then scene.delete_node(d.node) end
        else
            if Art.valid(d.node) then d.node:set_position(vec3(d.x, d.y, d.z)) end
            survivors[#survivors + 1] = d
        end
    end
    D.cata.debris = survivors
end

local function update_traps(D, dt)
    local hero = D.hero
    local hero_air = D.cata.jump.active and D.cata.jump.y > JUMP_CLEAR
    for _, tr in ipairs(D.cata.traps) do
        tr.t = tr.t + dt
        if tr.phase == "idle" then
            if tr.t >= TRAP_CYCLE then tr.phase = "warn"; tr.t = 0.0; tr.hit = false end
        elseif tr.phase == "warn" then
            local p = math.min(1.0, tr.t / TRAP_WARN)
            local pulse = 0.4 + 1.6 * (0.5 + 0.5 * math.sin(D.realtime * 16.0)) * p
            if Art.valid(tr.glow) then
                tr.glow:set_scale(vec3(TRAP_RADIUS * (1.2 + 0.5 * p), 0.04, TRAP_RADIUS * (1.2 + 0.5 * p)))
                material.set(tr.glow, "emissive", vec3(0.80 * pulse, 0.0, 0.0))
            end
            -- Cue the hero to leap a trap he is standing over as it arms.
            if tr.t >= TRAP_WARN * 0.55 and not D.cata.jump.active then
                local dx = hero.x - tr.x
                if dx * dx <= TRAP_RADIUS * TRAP_RADIUS and not hero.dead then D.cata.jump.active = true; D.cata.jump.t = 0.0 end
            end
            if tr.t >= TRAP_WARN then tr.phase = "extend"; tr.t = 0.0; spawn_debris(D, tr.x, tr.z) end
        elseif tr.phase == "extend" then
            local p = math.min(1.0, tr.t / TRAP_EXTEND)
            set_spike_height(tr, TRAP_HEIGHT * p)
            if tr.t >= TRAP_EXTEND then
                tr.phase = "hold"; tr.t = 0.0
                -- Impale: locked out. Hero is gored unless airborne above the spikes.
                if not hero.dead and not tr.hit and not hero_air then
                    local dx, dz = hero.x - tr.x, hero.z - tr.z
                    if dx * dx + dz * dz <= TRAP_RADIUS * TRAP_RADIUS then
                        D:apply_hero_damage(TRAP_DAMAGE, { flash = "IMPALED!" })
                        tr.hit = true
                        Art.burst("ath_cata_trap_" .. tr.x, vec3(tr.x, 0.8, tr.z),
                            { preset = "hero_take", count = 18, life_max = 0.3, spawn_radius = TRAP_RADIUS * 0.5, noise_strength = 4.0, size_max = 0.2 })
                    end
                end
            end
        elseif tr.phase == "hold" then
            if tr.t >= TRAP_HOLD then tr.phase = "retract"; tr.t = 0.0 end
        elseif tr.phase == "retract" then
            local p = math.min(1.0, tr.t / TRAP_RETRACT)
            set_spike_height(tr, TRAP_HEIGHT * (1.0 - p))
            if Art.valid(tr.glow) then material.set(tr.glow, "emissive", vec3(0.16 * (1.0 - p), 0.0, 0.0)) end
            if tr.t >= TRAP_RETRACT then
                tr.phase = "idle"; tr.t = 0.0
                if Art.valid(tr.glow) then tr.glow:set_scale(vec3(TRAP_RADIUS * 1.2, 0.04, TRAP_RADIUS * 1.2)) end
            end
        end
    end
end

local function clear_traps(D)
    for _, tr in ipairs(D.cata and D.cata.traps or {}) do
        if Art.valid(tr.glow) then scene.delete_node(tr.glow) end
        for _, s in ipairs(tr.spikes) do if Art.valid(s.node) then scene.delete_node(s.node) end end
    end
    for _, d in ipairs(D.cata and D.cata.debris or {}) do if Art.valid(d.node) then scene.delete_node(d.node) end end
    if D.cata then D.cata.traps = {}; D.cata.debris = {} end
end

-- ---- Hero Y-axis physics: gravity-arc jump + dodge-roll --------------------

local function update_hero_physics(D, dt)
    local hero = D.hero
    local j = D.cata.jump
    if hero.dead then j.active = false; return end

    -- Gravity-arc jump: launch velocity solved from the desired apex (v=sqrt(2gh)).
    if j.active then
        j.t = j.t + dt
        local v0 = math.sqrt(2.0 * GRAVITY * JUMP_APEX)
        j.y = v0 * j.t - 0.5 * GRAVITY * j.t * j.t
        if j.y <= 0.0 and j.t > 0.05 then j.active = false; j.y = 0.0 end
    end

    -- Dodge-roll: a quick grounded tuck when pressed by a nearby foe (cosmetic
    -- evasion). Cooldown keeps it occasional, like a stamina dodge.
    local r = D.cata.roll
    r.cd = math.max(0.0, r.cd - dt)
    if not r.active and not j.active and r.cd <= 0.0 then
        local near, nd = D:nearest_creep(hero)
        if near and nd and nd < 1.8 then r.active = true; r.t = 0.0; r.dir = (near.x >= hero.x) and -1.0 or 1.0 end
    end
    if r.active then
        r.t = r.t + dt
        if r.t >= ROLL_TIME then r.active = false; r.cd = 2.2 end
    end

    -- Apply the Y lift + roll transform on top of what update_hero already wrote
    -- this frame (on_combat_tick runs AFTER update_hero, so this is the final say).
    if Art.valid(hero.root) then
        local roll_pitch = r.active and (360.0 * (r.t / ROLL_TIME)) or 0.0
        hero.root:set_position(vec3(hero.x, j.y, hero.z))
        hero.root:set_rotation(vec3(roll_pitch, math.deg(hero.facing), 0.0))
        if j.active then
            -- A slight tuck/squash at the apex sells the leap.
            local ws = hero.world_scale or 1.0
            local sq = 1.0 - 0.12 * math.sin(math.min(1.0, j.y / JUMP_APEX) * math.pi)
            hero.root:set_scale(vec3(ws, ws * sq, ws))
        elseif not r.active then
            local ws = hero.world_scale or 1.0
            hero.root:set_scale(vec3(ws, ws, ws))
        end
    end
end

-- ---- Camera: a side-on rig that tracks the hero down the corridor ----------

local function update_camera(D)
    local A = D.arena
    -- Keep the framing inside the corridor ends so we never pan off into the void.
    local half = A.ortho_size * 0.5
    local cx = math.max(A.pad + half * 0.4, math.min(A.w - A.pad - half * 0.4, D.hero.x))
    Art.setup_iso_camera({ x = cx, z = A.h * 0.5 - 0.5 },
        { ortho_size = A.ortho_size, offset = A.cam_offset })
    -- Parallax: shove the far backdrop WITH the camera at a fraction, so distant
    -- arches drift slower than the foreground (faked depth in a flat stage).
    if Art.valid(D.cata.bg) then D.cata.bg:set_position(vec3(PARALLAX * cx, 3.2, A.h - A.pad + 1.2)) end
end

-- ---- Hero class selection (two classes; brief) -----------------------------

local function pick_hero()
    local class = "knight"
    if ATH_COMMON and ATH_COMMON.getenv then
        local v = ATH_COMMON.getenv("ATH_CATA_CLASS")
        if type(v) == "string" and Cata.heroes[v:lower()] then class = v:lower() end
    end
    local h = Cata.heroes[class]
    return class, h
end

local CLASS, HERO = pick_hero()

-- ---------------------------------------------------------------------------
-- Mode contract
-- ---------------------------------------------------------------------------

return {
    meta = {
        id = "catacombs",
        name = "Catacombs",
        tagline = "the side-scrolling crypt corridor",
        blurb = "A 2D side-scroller through a torch-lit tomb. Skeletons rise, wall spikes thrust from the floor — leap them or be impaled. Reach the far portal.",
        side_hint = "horde",
        accent = { 0.80, 0.05, 0.05, 0.95 },
        -- A side-on sketch of the corridor (normalized 0..1 rects: x,y,w,h,color).
        minimap = {
            bg = { 0.05, 0.05, 0.05, 1.0 },
            rects = {
                { 0.04, 0.62, 0.92, 0.10, { 0.165, 0.165, 0.165, 1.0 } }, -- floor
                { 0.04, 0.20, 0.92, 0.10, { 0.11, 0.11, 0.11, 1.0 } },    -- back wall band
                { 0.07, 0.46, 0.05, 0.16, { 0.78, 0.77, 0.72, 1.0 } },    -- hero (left)
                { 0.30, 0.50, 0.04, 0.12, { 0.78, 0.77, 0.72, 1.0 } },    -- skeletons
                { 0.46, 0.50, 0.04, 0.12, { 0.78, 0.77, 0.72, 1.0 } },
                { 0.62, 0.50, 0.04, 0.12, { 0.78, 0.77, 0.72, 1.0 } },
                { 0.34, 0.58, 0.015, 0.14, { 0.42, 0.42, 0.42, 1.0 } },   -- spike traps
                { 0.54, 0.58, 0.015, 0.14, { 0.42, 0.42, 0.42, 1.0 } },
                { 0.20, 0.28, 0.02, 0.10, { 1.0, 0.667, 0.0, 1.0 } },     -- torches
                { 0.66, 0.28, 0.02, 0.10, { 1.0, 0.667, 0.0, 1.0 } },
                { 0.90, 0.40, 0.05, 0.28, { 0.80, 0.05, 0.05, 1.0 } },    -- exit portal (right)
            },
        },
    },

    config = {
        id = "catacombs",
        name = "Catacombs",
        theme = Cata.theme,
        -- A long, shallow CORRIDOR. Wide X (read left->right), shallow Z depth, and
        -- a low side-on camera that tracks the hero (update_camera, each tick).
        arena = {
            width = 72, height = 16, pad = 2, ortho_size = 22.0,
            cam_offset = { x = 0.0, y = 10.0, z = -30.0 },   -- side elevation, not iso
            hero_start = { x = 5, y = 8 },
            -- The dead pour in from the FAR (right) end of the corridor, so the hero
            -- advances left->right toward the exit portal to meet them.
            spawns = {
                { x = 66, y = 8 }, { x = 68, y = 6 }, { x = 68, y = 10 },
                { x = 64, y = 5 }, { x = 64, y = 11 }, { x = 60, y = 8 },
            },
        },
        hero = {
            hp_max = HERO.stats.hp_max, dps = HERO.stats.dps, cleave = HERO.stats.cleave,
            attack_range = HERO.stats.attack_range, speed = HERO.stats.speed, kite_speed = HERO.stats.kite_speed,
            actor = HERO.actor,
        },
        archetypes = Cata.archetypes,
        roles = Cata.roles,
        spawn = { interval_start = 0.8, interval_min = 0.35, batch_start = 3, batch_max = 6, cap_start = 28, cap_max = 80, brute_after = 22.0 },
        reserve_start = 320.0,
        round_seconds = 14.0,

        -- A skeletal mix: chaff walkers + skitterers, periodic archers, the slow
        -- spike-traps as elites, and a late bone colossus.
        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 12 == 0) then return "bone_colossus" end
            if D.spawn_counter % 8 == 0 then return "wall_spike_trap" end
            if D.spawn_counter % 5 == 0 then return "tomb_archer" end
            return (D.spawn_counter % 2 == 0) and "skitter_bones" or "crypt_walker"
        end,

        hooks = {
            on_start = function(D)
                local A = D.arena
                D.cata = {
                    traps = {}, debris = {}, debris_id = 0, torches = {}, patrols = {},
                    jump = { active = false, t = 0.0, y = 0.0 },
                    roll = { active = false, t = 0.0, cd = 0.0, dir = 1.0 },
                    bg = nil, class = CLASS,
                }
                local g = D.groups.world
                local far_z = A.h - A.pad + 1.2

                -- A very dark distant backdrop (arches/coffins/bones) for parallax.
                -- Lit by the stage's directional light; only a whisper of emissive so
                -- the gloom holds (the `color` arg tints the self-glow, texture or not).
                D.cata.bg = Art.cube("Cata_Background", vec3(PARALLAX * A.w * 0.5, 3.2, far_z),
                    vec3(A.w * 1.6, 8.0, 0.2), { 0.6, 0.6, 0.6 }, g, 0.2, Cata.tex.background)

                -- A textured brick back wall, panelled so the seamless tile reads.
                local panel = 4.0
                for px = A.pad, A.w - A.pad, panel do
                    Art.cube("BackWall_" .. math.floor(px), vec3(px + panel * 0.5, 3.3, A.h - A.pad - 0.2),
                        vec3(panel, 6.6, 0.4), Cata.palette.stone, g, 0.6, Cata.tex.wall)
                end

                -- Torch line along the back wall (flicker driven in on_combat_tick).
                for tx = A.pad + 4, A.w - A.pad - 2, 9 do
                    D.cata.torches[#D.cata.torches + 1] = build_torch(D, tx, 3.4, A.h - A.pad - 0.5)
                end

                -- Coffins + tombstones propped against the back wall (crypt dressing).
                for cx = A.pad + 6, A.w - A.pad - 6, 13 do
                    Art.cube("Coffin_" .. cx, vec3(cx, 0.9, A.h - A.pad - 0.9), vec3(0.8, 1.8, 0.5), Cata.palette.stone, g, 0.4, Cata.tex.wall)
                    Art.cube("Coffin_Lid_" .. cx, vec3(cx, 1.82, A.h - A.pad - 0.9), vec3(0.9, 0.12, 0.6), Cata.palette.hilite, g, 0.5)
                    Art.cube("Tomb_" .. cx, vec3(cx + 3.5, 0.5, A.h - A.pad - 1.0), vec3(0.7, 1.0, 0.4), Cata.palette.stone, g, 0.4)
                end

                -- Bones scattered underfoot along the corridor floor.
                for i = 1, 26 do
                    local bx = A.pad + 1 + (i * 2.6) % (A.w - A.pad * 2 - 2)
                    local bz = A.h * 0.5 + ((i * 1.7) % 5.0) - 2.5
                    Art.cylinder("Bone_" .. i, vec3(bx, 0.04, bz), vec3(0.34, 0.05, 0.07), Cata.palette.bone, g, 0.45,
                        nil)
                end

                -- Vertical layers: raised platforms (with ladders) + patrolling dead.
                local plats = {
                    build_platform(D, A.w * 0.32, 2.4, A.h - A.pad - 1.6, 6.0),
                    build_platform(D, A.w * 0.60, 3.6, A.h - A.pad - 1.6, 5.0),
                }
                for _, plat in ipairs(plats) do
                    D.cata.patrols[#D.cata.patrols + 1] = build_patrol(D, plat)
                end

                -- The EXIT PORTAL at the far-right end of the corridor.
                local ex = A.w - A.pad - 1.5
                Art.cube("Portal_Frame_L", vec3(ex - 0.8, 1.6, A.h * 0.5), vec3(0.4, 3.2, 0.5), Cata.palette.stone, g, 0.6)
                Art.cube("Portal_Frame_R", vec3(ex + 0.8, 1.6, A.h * 0.5), vec3(0.4, 3.2, 0.5), Cata.palette.stone, g, 0.6)
                Art.cube("Portal_Arch", vec3(ex, 3.3, A.h * 0.5), vec3(2.2, 0.5, 0.5), Cata.palette.stone, g, 0.6)
                D.cata.portal = Art.cube("Portal_Glow", vec3(ex, 1.6, A.h * 0.5), vec3(1.2, 3.0, 0.12), Cata.palette.blood, g, 1.4)

                -- Seat the wall spike traps at regular intervals down the corridor.
                local tz = A.h * 0.5 + 1.5
                for trx = A.pad + 8, A.w - A.pad - 8, TRAP_SPACING do
                    D.cata.traps[#D.cata.traps + 1] = build_trap(D, trx, tz)
                end

                update_camera(D)
            end,

            on_reset = function(D)
                clear_traps(D)
                if D.cata then
                    D.cata.jump = { active = false, t = 0.0, y = 0.0 }
                    D.cata.roll = { active = false, t = 0.0, cd = 0.0, dir = 1.0 }
                    -- Re-seat the traps the run started with.
                    local A = D.arena
                    local tz = A.h * 0.5 + 1.5
                    for trx = A.pad + 8, A.w - A.pad - 8, TRAP_SPACING do
                        D.cata.traps[#D.cata.traps + 1] = build_trap(D, trx, tz)
                    end
                end
            end,

            on_combat_tick = function(D, dt)
                update_traps(D, dt)
                update_debris(D, dt)
                update_patrols(D, dt)
                update_hero_physics(D, dt)
                update_camera(D)
                -- Torch flicker: emissive wobble + a touch of random guttering.
                for _, t in ipairs(D.cata.torches) do
                    if Art.valid(t.node) then
                        local f = 1.3 + 0.5 * math.sin(D.realtime * 11.0 + t.seed) + 0.2 * math.sin(D.realtime * 27.0 + t.seed * 2.0)
                        material.set(t.node, "emissive", vec3(1.0 * f, 0.667 * f, 0.0))
                    end
                end
                -- Portal beckons with a slow pulse.
                if Art.valid(D.cata.portal) then
                    local pf = 1.0 + 0.6 * (0.5 + 0.5 * math.sin(D.realtime * 3.0))
                    material.set(D.cata.portal, "emissive", vec3(0.80 * pf, 0.05 * pf, 0.05 * pf))
                end
            end,

            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local A = D.arena
                -- Corridor progress toward the far portal (left->right "depth").
                local prog = math.max(0.0, math.min(1.0, (D.hero.x - 5.0) / ((A.w - A.pad - 1.5) - 5.0)))
                local armed = 0
                for _, tr in ipairs(D.cata.traps) do if tr.phase ~= "idle" then armed = armed + 1 end end
                Art.quad(D.hud, "cata_panel", 24.0, sh - 150.0, 560.0, 58.0, { 0.05, 0.05, 0.05, 0.9 },
                    { border = { 0.80, 0.05, 0.05, 0.9 },
                      label = string.format("CLASS: %s    Corridor depth: %d%%    Spikes armed: %d",
                        D.cata.class:upper(), math.floor(prog * 100.0 + 0.5), armed) })
            end,
        },
    },
}
