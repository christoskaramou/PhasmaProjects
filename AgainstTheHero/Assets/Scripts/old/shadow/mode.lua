-- Shadow Hunt — a claustrophobic stone maze where the dark itself hunts you.
--
-- THE CONTRACT: return { meta = {...}, config = {...} } handed to Duel.new().
--   * meta   — what the menu shows: name, blurb, minimap sketch, accent colour.
--   * config — theme, arena (a hand-authored MAZE), hero, characters, role
--              mapping, spawn tuning, and HOOKS for this level's signature system.
--
-- Signature system — DARKNESS & THE TORCH. This is a top-down predator/prey hunt.
-- The hero carries a TORCH that lights a forward cone (+ a small pool at his feet).
-- The horde are SHADOW entities that live in the near-void: the mode keeps them
-- dim (barely visible) until torch-light or a lit wall-sconce catches them — then
-- they FLARE white and FREEZE (stun), so light is the hero's only safety. The
-- Umbral Stalker is the exception: invisible even in torchlight, never stunned.
-- The Shadow Mimic apes the hero's moves MIRRORED across the maze centre. The
-- hero collides with the stone walls (mode-owned tile AABB), can ignite sconces
-- to carve out lit ground, and races for the EXIT — reaching it floods the maze
-- with a brief light "breakthrough". Footsteps lure nearby shadows toward you.
--
-- Everything is built from ath_art primitives parented to D.groups.world and is
-- texture-ready (run tools/gen_textures_shadow.py for the matching art set).
--
-- Player knobs (env): ATH_SHADOW_MAZE = 1|2|3 (which hardcoded layout),
--                     ATH_SHADOW_HERO = torch_bearer|blind_swordsman.

local Art    = ATH_COMMON.load_script("Scripts/shared/ath_art.lua",            "shared art",        _ENV)
local Shadow = ATH_COMMON.load_script("Scripts/modes/shadow/characters.lua",   "shadow characters", _ENV)

-- ---- Tuning -----------------------------------------------------------------
local THRESHOLD          = 0.18   -- light intensity above which a shadow is "revealed"
local STUN_DURATION      = 1.10   -- seconds a revealed shadow is frozen
local STUN_RECOVER       = 0.50   -- grace after a stun before it can be re-stunned (creeps through light)
local STUN_FLASH         = 0.28   -- white-flash fade time on the instant of reveal

local SCONCE_IGNITE_R    = 1.9    -- hero proximity that ignites an unlit sconce
local SCONCE_LIGHT_R     = 5.2    -- lit sconce reveal/stun radius
local SCONCE_IGNITE_TIME = 0.45   -- 3-frame ignite animation length

local FOOTSTEP_STRIDE    = 1.6    -- world distance walked per footstep "noise" pulse
local FOOTSTEP_LURE_R    = 9.0    -- shadows within this range hear a footstep
local FOOTSTEP_LURE      = 0.55   -- world units a heard shadow is dragged toward you

local EXIT_RADIUS        = 2.2    -- how close the hero must get to "reach" the exit
local BREAKTHROUGH_TIME  = 4.0    -- seconds the whole maze stays lit after reaching the exit

local PAN_TIME           = 2.2    -- intro maze-pan duration (camera zooms in on load)
local FLAME_FPS          = 6.0    -- torch flame flicker rate

-- Colours pulled from the shared palette so the level reads as one place.
local P = Shadow.palette

-- ---------------------------------------------------------------------------
-- MAZE LAYOUTS — three hardcoded variants. A variant is a compact rect spec we
-- expand into a Flow map_def (rooms+corridors are walkable; everything else is
-- solid stone wall). The SAME chosen variant feeds config.arena.map_def AND the
-- wall/sconce/exit props built in on_start, so geometry and visuals always match.
-- ---------------------------------------------------------------------------

local ARENA_W, ARENA_H, ARENA_PAD = 48, 34, 2

-- Build a Flow map_def + the prop anchors (exit/sconces/spawns) from a spec.
local function make_maze(id, title, spec)
    local rooms = {}
    for i, r in ipairs(spec.rooms) do
        rooms[i] = { id = id .. "_room" .. i, name = title, rect = { x = r[1], y = r[2], w = r[3], h = r[4] }, anchors = {} }
    end
    local corridors = {}
    for i, c in ipairs(spec.corridors) do
        corridors[i] = { id = id .. "_cor" .. i, rect = { x = c[1], y = c[2], w = c[3], h = c[4] } }
    end
    return {
        map_def = {
            id = id, title = title, width = ARENA_W, height = ARENA_H, tile_world = 1.0,
            hero_start = { x = spec.hero_start[1], y = spec.hero_start[2] },
            rooms = rooms, corridors = corridors,
        },
        hero_start = { x = spec.hero_start[1], y = spec.hero_start[2] },
        exit    = { x = spec.exit[1], y = spec.exit[2] },
        kill    = { x = spec.kill[1], y = spec.kill[2] },
        sconces = spec.sconces,
        spawns  = spec.spawns,
    }
end

local VARIANTS = {
    -- 1) THE WARRENS — a perimeter ring crossed by a spine, kill-zone at the heart.
    make_maze("shadow_warrens", "The Warrens", {
        hero_start = { 6, 5 }, exit = { 41, 27 }, kill = { 23, 16 },
        rooms = {
            { 3, 3, 7, 6 },     -- start chamber (top-left)
            { 20, 13, 8, 7 },   -- kill zone (centre)
            { 38, 25, 7, 6 },   -- exit chamber (bottom-right)
        },
        corridors = {
            { 3, 8, 42, 3 },    -- top run
            { 3, 24, 42, 3 },   -- bottom run
            { 6, 3, 3, 24 },    -- left spine
            { 39, 6, 3, 22 },   -- right spine
            { 9, 15, 30, 3 },   -- mid run (through the kill zone)
            { 22, 8, 3, 18 },   -- centre spine (top<->bottom)
        },
        sconces = { { 12, 9 }, { 38, 9 }, { 23, 16 }, { 12, 25 }, { 38, 25 }, { 6, 20 } },
        spawns  = { { 3, 9 }, { 44, 9 }, { 3, 25 }, { 44, 25 }, { 22, 9 }, { 23, 25 } },
    }),

    -- 2) THE SERPENT — one long switchback corridor folding the hero back and forth.
    make_maze("shadow_serpent", "The Serpent", {
        hero_start = { 5, 5 }, exit = { 41, 28 }, kill = { 23, 16 },
        rooms = {
            { 3, 3, 6, 5 },     -- start chamber
            { 20, 14, 8, 6 },   -- kill zone (mid)
            { 39, 27, 6, 4 },   -- exit chamber
        },
        corridors = {
            { 3, 7, 40, 3 },    -- top run (left->right)
            { 40, 7, 3, 8 },    -- down on the right
            { 6, 13, 37, 3 },   -- mid run (right->left, past kill zone)
            { 6, 13, 3, 10 },   -- down on the left
            { 6, 20, 37, 3 },   -- low run (left->right)
            { 40, 20, 3, 10 },  -- down to the exit
        },
        sconces = { { 20, 8 }, { 41, 11 }, { 12, 14 }, { 30, 14 }, { 8, 21 }, { 41, 25 } },
        spawns  = { { 3, 8 }, { 42, 8 }, { 7, 14 }, { 42, 14 }, { 7, 21 }, { 42, 21 } },
    }),

    -- 3) THE SPIRAL — concentric rings; the hero starts trapped at the centre and
    --    must wind outward to the exit while the dark closes the rings behind him.
    make_maze("shadow_spiral", "The Spiral", {
        hero_start = { 23, 16 }, exit = { 5, 5 }, kill = { 41, 28 },
        rooms = {
            { 21, 14, 6, 6 },   -- start chamber (centre)
            { 3, 3, 6, 5 },     -- exit chamber (top-left)
            { 39, 26, 6, 5 },   -- kill zone (bottom-right)
        },
        corridors = {
            { 15, 10, 18, 3 },  -- inner ring: top
            { 30, 10, 3, 14 },  -- inner ring: right
            { 15, 21, 18, 3 },  -- inner ring: bottom
            { 15, 10, 3, 14 },  -- inner ring: left
            { 18, 15, 4, 3 },   -- spoke: start -> inner ring
            { 15, 5, 3, 6 },    -- spoke: inner ring -> outer ring
            { 6, 5, 36, 3 },    -- outer ring: top
            { 6, 5, 3, 24 },    -- outer ring: left
            { 39, 5, 3, 24 },   -- outer ring: right
            { 6, 26, 36, 3 },   -- outer ring: bottom
        },
        sconces = { { 23, 16 }, { 16, 11 }, { 31, 16 }, { 23, 22 }, { 8, 16 }, { 41, 16 } },
        spawns  = { { 6, 6 }, { 41, 6 }, { 6, 28 }, { 41, 28 }, { 16, 6 }, { 31, 22 } },
    }),
}

-- Pick the variant + hero rig at load time (config is read once, before on_start).
local VARIANT_INDEX = math.max(1, math.min(3, math.floor(ATH_COMMON.getenv_number("ATH_SHADOW_MAZE", 1) or 1)))
local MAZE = VARIANTS[VARIANT_INDEX]

local HERO_KEY = (ATH_COMMON.getenv("ATH_SHADOW_HERO", "torch_bearer") == "blind_swordsman") and "blind_swordsman" or "torch_bearer"
local HERO_RIG = (HERO_KEY == "blind_swordsman") and Shadow.hero_blind or Shadow.hero_torch
local HERO_TUNE = Shadow.hero_tuning[HERO_KEY]

-- Maze centre (used by the Shadow Mimic's mirror and the kill-zone framing).
local CENTER_X = ARENA_W * 0.5 - 0.5
local CENTER_Z = ARENA_H * 0.5 - 0.5

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

-- A cheap deterministic hash so wall stones vary in height without randomness
-- that would desync across resets. Pure arithmetic (no bitwise ops, so it runs
-- on any Lua version the engine ships).
local function stone_jitter(x, y)
    local h = (x * 374761 + y * 668265 + x * y * 97) % 1000
    return h / 1000.0
end

-- True if a world point's tile is open floor.
local function walkable_at(D, x, z)
    return D.map:is_walkable(math.floor(x + 0.5), math.floor(z + 0.5))
end

-- ---------------------------------------------------------------------------
-- Stage construction (walls / floor sigils / sconces / exit / torch visuals)
-- ---------------------------------------------------------------------------

-- Draw the maze walls. map.walls is exactly the boundary of stone touching open
-- floor, so this is the minimal visible wall set (texture-ready dark stone).
local function build_walls(D)
    local s = D.shadow
    for i, w in ipairs(D.map.walls) do
        -- Skip the outermost perimeter band — the Duel already draws four big
        -- perimeter slabs there, so we only raise the INTERIOR maze stone.
        if w.x > ARENA_PAD and w.x < ARENA_W - ARENA_PAD - 1 and w.y > ARENA_PAD and w.y < ARENA_H - ARENA_PAD - 1 then
            local hgt = 1.3 + 0.5 * stone_jitter(w.x, w.y)
            local node = Art.cube("Maze_Wall_" .. i, vec3(w.x, hgt * 0.5, w.y), vec3(1.0, hgt, 1.0),
                Shadow.theme.wall, D.groups.world, 0.10, "Textures/modes/shadow/wall.png")
            s.walls[#s.walls + 1] = node
        end
    end
end

-- Build one wall-sconce (unlit). Bracket + bowl + (dark) flame. Lighting it later
-- just brightens the flame and flips `lit`. Texture-ready (sconce.png).
local function build_sconce(D, sx, sz, i)
    local bracket = Art.cube("Sconce_Bracket_" .. i, vec3(sx, 1.0, sz), vec3(0.26, 0.5, 0.26),
        Shadow.theme.stone or P.stone, D.groups.world, 0.18, "Textures/modes/shadow/sconce.png")
    local flame = Art.sphere("Sconce_Flame_" .. i, vec3(sx, 1.42, sz), vec3(0.22, 0.30, 0.22),
        P.deep, D.groups.world, 0.05, "Textures/modes/shadow/torch_flame.png")
    -- A flat pool decal that will glow once lit (kept invisible-small while unlit).
    local pool = Art.cylinder("Sconce_Pool_" .. i, vec3(sx, 0.03, sz), vec3(0.4, 0.04, 0.4),
        P.amber, D.groups.world, 0.0, "Textures/modes/shadow/light_cone.png")
    return { x = sx, z = sz, lit = false, t = 0.0, bracket = bracket, flame = flame, pool = pool }
end

-- The exit portal — a bright rift in the far wall the hero is racing for.
local function build_exit(D)
    local e = MAZE.exit
    local node = Art.cylinder("Shadow_Exit", vec3(e.x, 0.06, e.y), vec3(2.6, 0.06, 2.6),
        P.torchlight, D.groups.world, 1.6, "Textures/modes/shadow/light_cone.png")
    local post = Art.cube("Shadow_Exit_Arch", vec3(e.x, 1.2, e.y), vec3(1.6, 2.4, 0.4),
        P.amber, D.groups.world, 0.9)
    return { x = e.x, z = e.y, node = node, post = post, reached = false }
end

-- The hero's torch: a forward light cone + a feet pool. Both ride the hero each
-- frame (see update_torch) and flicker with the flame.
local function build_torch(D)
    local t = D.shadow.torch
    t.pool = Art.cylinder("Torch_Pool", vec3(D.hero.x, 0.02, D.hero.z),
        vec3(t.inner_radius * 2.0, 0.04, t.inner_radius * 2.0), P.amber, D.groups.world, 1.2,
        "Textures/modes/shadow/light_cone.png")
    -- The cone is a flat, forward-stretched decal textured with the radial mask.
    t.cone = Art.cube("Torch_Cone", vec3(D.hero.x, 0.03, D.hero.z),
        vec3(t.torch_radius * 0.9, 0.04, t.torch_radius * 1.6), P.amber, D.groups.world, 0.9,
        "Textures/modes/shadow/light_cone.png")
end

-- ---------------------------------------------------------------------------
-- Per-frame systems
-- ---------------------------------------------------------------------------

-- Move + flicker the torch visuals and the hero's held flame.
local function update_torch(D, dt)
    local s, hero = D.shadow, D.hero
    local t = s.torch
    -- 6 fps flame frame stepper (drives a discrete flicker, not a smooth sine).
    s.flame_t = s.flame_t + dt
    if s.flame_t >= 1.0 / FLAME_FPS then
        s.flame_t = s.flame_t - 1.0 / FLAME_FPS
        s.flame_frame = (s.flame_frame + 1) % 6
    end
    local flick = 0.78 + 0.22 * ({ 1.0, 0.6, 0.9, 0.4, 1.0, 0.7 })[s.flame_frame + 1]

    local fx, fz = math.sin(hero.facing), math.cos(hero.facing)
    -- Feet pool: a soft amber ring under the hero.
    if Art.valid(t.pool) then
        t.pool:set_position(vec3(hero.x, 0.02, hero.z))
        local r = t.inner_radius * (1.9 + 0.12 * flick)
        t.pool:set_scale(vec3(r, 0.04, r))
        material.set(t.pool, "emissive", vec3(P.amber[1] * 1.2 * flick, P.amber[2] * 1.2 * flick, P.amber[3] * 1.2 * flick))
    end
    -- Forward cone: pushed ahead of the hero, rotated to face his heading.
    if Art.valid(t.cone) then
        local ahead = t.torch_radius * 0.55
        t.cone:set_position(vec3(hero.x + fx * ahead, 0.03, hero.z + fz * ahead))
        t.cone:set_rotation(vec3(0.0, math.deg(hero.facing), 0.0))
        local L = t.torch_radius * 1.6
        t.cone:set_scale(vec3(t.torch_radius * 0.95, 0.04, L))
        material.set(t.cone, "emissive", vec3(P.torchlight[1] * flick, P.torchlight[2] * 0.85 * flick, P.torchlight[3] * 0.5 * flick))
    end
    -- The flame held in the hero rig.
    local fl = hero.parts and hero.parts.torch_flame
    if Art.valid(fl) then
        local sc = 1.0 + 0.18 * (flick - 0.8)
        material.set(fl, "emissive", vec3(P.amber[1] * 2.6 * flick, P.amber[2] * 1.8 * flick, P.amber[3] * 0.6 * flick))
        fl:set_scale(vec3(0.22 * sc, 0.30 * sc, 0.22 * sc))
    end
end

-- Light intensity (0..1) on a world point from the torch cone + lit sconces +
-- any active breakthrough. This IS the dual-layer visibility, made cheap.
local function light_at(D, x, z)
    local s, hero = D.shadow, D.hero
    if s.breakthrough_t > 0.0 then return 1.0 end
    local t = s.torch
    local best = 0.0
    -- Torch: a small omni pool at the feet plus a forward cone.
    local dx, dz = x - hero.x, z - hero.z
    local dist = math.sqrt(dx * dx + dz * dz)
    if dist <= t.inner_radius then
        best = math.max(best, 1.0 - 0.4 * (dist / t.inner_radius))
    elseif dist <= t.torch_radius and dist > 0.001 then
        local fx, fz = math.sin(hero.facing), math.cos(hero.facing)
        local dot = (dx / dist) * fx + (dz / dist) * fz
        if dot >= t.cone_cos then
            local fall = 1.0 - dist / t.torch_radius
            local edge = (dot - t.cone_cos) / (1.0 - t.cone_cos)   -- soften the cone edge
            best = math.max(best, fall * math.min(1.0, 0.4 + edge))
        end
    end
    -- Lit sconces: each carves a steady pool of safe light.
    for _, sc in ipairs(s.sconces) do
        if sc.lit then
            local sdx, sdz = x - sc.x, z - sc.z
            local sd = math.sqrt(sdx * sdx + sdz * sdz)
            if sd <= SCONCE_LIGHT_R then best = math.max(best, 1.0 - sd / SCONCE_LIGHT_R) end
        end
    end
    return best
end

-- Reveal / hide / stun every shadow based on the light falling on it, and apply
-- the per-creep behaviours (mimic mirror, amorphous pulse).
local function update_shadows(D, dt)
    local s, hero = D.shadow, D.hero
    s.revealed = 0
    for _, c in ipairs(D.creeps) do
        if c.alive and c.root and Art.valid(c.root) then
            local kind = c.archetype
            local immune = (kind == "umbral_stalker")

            -- Shadow Mimic: mirror the hero across the maze centre. We step toward
            -- the mirror point and only commit if the next tile is open stone, so
            -- it threads the corridors instead of phasing through walls.
            if kind == "shadow_mimic" and not (c.sh_stun_t and c.sh_stun_t > 0.0) then
                local mx = clamp(2.0 * CENTER_X - hero.x, ARENA_PAD + 1, ARENA_W - ARENA_PAD - 2)
                local mz = clamp(2.0 * CENTER_Z - hero.z, ARENA_PAD + 1, ARENA_H - ARENA_PAD - 2)
                local ddx, ddz = mx - c.x, mz - c.z
                local dd = math.sqrt(ddx * ddx + ddz * ddz)
                if dd > 0.05 then
                    local step = math.min(dd, (c.stats.speed or 2.0) * dt)
                    local nx, nz = c.x + ddx / dd * step, c.z + ddz / dd * step
                    if walkable_at(D, nx, nz) then
                        c.x, c.z = nx, nz
                        c.root:set_position(vec3(nx, 0.0, nz))
                    end
                end
            end

            -- Light test → reveal state.
            local intensity = immune and 0.0 or light_at(D, c.x, c.z)
            local lit = intensity >= THRESHOLD
            if lit then s.revealed = s.revealed + 1 end

            -- Stun bookkeeping: a fresh reveal flashes white and freezes the shade.
            c.sh_stun_t   = math.max((c.sh_stun_t or 0.0) - dt, 0.0)
            c.sh_recover  = math.max((c.sh_recover or 0.0) - dt, 0.0)
            c.sh_flash    = math.max((c.sh_flash or 0.0) - dt, 0.0)
            if lit and not immune and c.sh_stun_t <= 0.0 and c.sh_recover <= 0.0 then
                c.sh_stun_t = STUN_DURATION
                c.sh_recover = STUN_DURATION + STUN_RECOVER
                c.sh_flash = STUN_FLASH
                c.sh_pin = { x = c.x, z = c.z }
                Art.burst("shadow_stun_" .. tostring(c.id), vec3(c.x, 0.7, c.z),
                    { preset = "enemy_take", count = 10, life_max = 0.3, spawn_radius = 0.35, size_max = 0.22 })
            end
            -- While stunned, pin the shade where it froze (cancels engine movement).
            if c.sh_stun_t > 0.0 and c.sh_pin then
                c.x, c.z = c.sh_pin.x, c.sh_pin.z
                c.root:set_position(vec3(c.x, 0.0, c.z))
            end

            -- ---- Visibility paint -------------------------------------------
            -- Revealed → flare toward torch-lit violet (white on a fresh flash);
            -- hidden → sink to a near-void emissive so it melts into the dark.
            local pulse = 0.85 + 0.15 * math.sin(D.realtime * 4.0 + c.id)  -- amorphous pulse
            local em
            if c.sh_flash > 0.0 then
                em = 2.2 * (c.sh_flash / STUN_FLASH)                        -- white reveal burst
                if Art.valid(c.parts.body) then material.set(c.parts.body, "emissive", vec3(em, em, em)) end
                if Art.valid(c.parts.head) then material.set(c.parts.head, "emissive", vec3(em, em, em)) end
            else
                local base
                if immune then
                    base = 0.04                                            -- the unseeable stalker
                elseif lit then
                    base = (0.5 + 0.9 * (intensity)) * pulse               -- revealed
                else
                    base = 0.07 * pulse                                    -- swallowed by the dark
                end
                local col = lit and P.voidlit or P.shadow
                if Art.valid(c.parts.body) then material.set(c.parts.body, "emissive", vec3(col[1] * base * 6.0, col[2] * base * 6.0, col[3] * base * 6.0)) end
                if Art.valid(c.parts.head) then material.set(c.parts.head, "emissive", vec3(col[1] * base * 6.0, col[2] * base * 6.0, col[3] * base * 6.0)) end
            end
            -- Amorphous distortion — gently breathe the body scale.
            if Art.valid(c.parts.body) then
                local bp = c.stats.body_scale or { 0.42, 0.48, 0.34 }
                local w = 1.0 + 0.08 * math.sin(D.realtime * 3.0 + c.id * 1.7)
                c.parts.body:set_scale(vec3(bp[1] * w, bp[2] * (2.0 - w), bp[3] * w))
            end
        end
    end
end

-- Ignite sconces the hero brushes past and run their 3-frame ignite animation.
local function update_sconces(D, dt)
    local s, hero = D.shadow, D.hero
    s.lit_count = 0
    for _, sc in ipairs(s.sconces) do
        if not sc.lit then
            local dx, dz = hero.x - sc.x, hero.z - sc.z
            if dx * dx + dz * dz <= SCONCE_IGNITE_R * SCONCE_IGNITE_R then
                sc.lit = true
                sc.t = 0.0
                Art.burst("sconce_ignite_" .. sc.x .. "_" .. sc.z, vec3(sc.x, 1.4, sc.z),
                    { preset = "hero_take", count = 16, life_max = 0.5, spawn_radius = 0.5, size_max = 0.3 })
                D:set_flash("A SCONCE FLARES TO LIFE")
            end
        end
        if sc.lit then
            sc.t = sc.t + dt
            s.lit_count = s.lit_count + 1
            -- 3-frame ignite ramp, then a steady warm flicker.
            local frame = math.min(3, math.floor(sc.t / (SCONCE_IGNITE_TIME / 3.0)) + 1)
            local grow = math.min(1.0, sc.t / SCONCE_IGNITE_TIME)
            local flick = 0.85 + 0.15 * math.sin(D.realtime * 9.0 + sc.x)
            if Art.valid(sc.flame) then
                local e = (0.6 + 2.0 * grow) * flick * (frame / 3.0)
                material.set(sc.flame, "emissive", vec3(P.amber[1] * e, P.amber[2] * e, P.amber[3] * e))
                material.set(sc.flame, "base_color", vec4(P.amber[1], P.amber[2], P.amber[3], 1.0))
                local fs = 0.22 + 0.10 * grow
                sc.flame:set_scale(vec3(fs, fs + 0.10 * grow, fs))
            end
            if Art.valid(sc.pool) then
                local r = SCONCE_LIGHT_R * 1.4 * grow
                sc.pool:set_scale(vec3(r, 0.04, r))
                local e = 0.8 * grow * flick
                material.set(sc.pool, "emissive", vec3(P.amber[1] * e, P.amber[2] * e, P.amber[3] * e))
            end
        end
    end
end

-- Footstep "noise": every stride the hero walks, nearby unlit shadows are lured
-- a step toward him (they hear you) and a faint ripple marks the sound.
local function update_footsteps(D, dt)
    local s, hero = D.shadow, D.hero
    local dx, dz = hero.x - s.last_step_x, hero.z - s.last_step_z
    s.step_accum = s.step_accum + math.sqrt(dx * dx + dz * dz)
    s.last_step_x, s.last_step_z = hero.x, hero.z
    if s.step_accum < FOOTSTEP_STRIDE then return end
    s.step_accum = 0.0
    Art.burst("shadow_step", vec3(hero.x, 0.05, hero.z),
        { preset = "hero_take", count = 6, life_max = 0.35, spawn_radius = 0.4, size_max = 0.14 })
    for _, c in ipairs(D.creeps) do
        if c.alive and (c.sh_stun_t or 0.0) <= 0.0 and c.archetype ~= "shadow_mimic" then
            local cx, cz = hero.x - c.x, hero.z - c.z
            local d = math.sqrt(cx * cx + cz * cz)
            if d > 0.5 and d <= FOOTSTEP_LURE_R then
                local nx, nz = c.x + cx / d * FOOTSTEP_LURE, c.z + cz / d * FOOTSTEP_LURE
                if walkable_at(D, nx, nz) then
                    c.x, c.z = nx, nz
                    if Art.valid(c.root) then c.root:set_position(vec3(nx, 0.0, nz)) end
                end
            end
        end
    end
end

-- Hero stone collision: the engine only clamps the hero to the arena rect, so we
-- own interior wall collision. If he stepped onto solid stone this frame, snap
-- him back to his last open-floor position (tile AABB).
local function update_collision(D)
    local s, hero = D.shadow, D.hero
    if hero.dead then return end
    if walkable_at(D, hero.x, hero.z) then
        s.hero_safe.x, s.hero_safe.z = hero.x, hero.z
    else
        hero.x, hero.z = s.hero_safe.x, s.hero_safe.z
        if Art.valid(hero.root) then hero.root:set_position(vec3(hero.x, 0.0, hero.z)) end
    end
end

-- Reaching the exit floods the maze with light for a few seconds (a breakthrough).
local function update_exit(D, dt)
    local s, hero = D.shadow, D.hero
    s.breakthrough_t = math.max(s.breakthrough_t - dt, 0.0)
    local ex = s.exit
    if not ex then return end
    local dx, dz = hero.x - ex.x, hero.z - ex.z
    local pulse = 1.2 + 0.6 * math.sin(D.realtime * 5.0)
    if Art.valid(ex.node) then material.set(ex.node, "emissive", vec3(P.torchlight[1] * pulse, P.torchlight[2] * pulse, P.torchlight[3] * pulse)) end
    if not ex.reached and dx * dx + dz * dz <= EXIT_RADIUS * EXIT_RADIUS then
        ex.reached = true
        s.breakthrough_t = BREAKTHROUGH_TIME
        s.reached_count = s.reached_count + 1
        D:set_flash("THE EXIT — LIGHT FLOODS THE MAZE!")
        Art.burst("shadow_breakthrough", vec3(ex.x, 1.0, ex.z),
            { preset = "hero_take", count = 40, life_max = 0.8, spawn_radius = 2.5, size_max = 0.4 })
    end
end

-- Intro maze pan: ease the camera in from a higher/wider framing on load.
local function update_pan(D, dt)
    local s = D.shadow
    if s.pan_t <= 0.0 then return end
    s.pan_t = math.max(s.pan_t - dt, 0.0)
    local cam = get_camera and get_camera()
    if not (cam and cam.set_position) then return end
    local off = D.arena.cam_offset
    local k = 1.0 - (s.pan_t / PAN_TIME)            -- 0 -> 1 over the pan
    local wide = 1.7 - 0.7 * k                       -- start 1.7x out, settle to 1.0x
    cam:set_position(vec3(CENTER_X + off.x * wide, off.y * wide, CENTER_Z + off.z * wide))
    if cam.look_at then cam:look_at(vec3(CENTER_X, 0.0, CENTER_Z)) end
end

-- ---------------------------------------------------------------------------
-- Setup / teardown
-- ---------------------------------------------------------------------------

local function init_state(D)
    D.shadow = {
        walls = {},
        sconces = {},
        exit = nil,
        torch = {
            torch_radius = HERO_TUNE.torch_radius,
            inner_radius = HERO_TUNE.inner_radius,
            cone_cos = math.cos(math.rad(HERO_TUNE.cone_deg * 0.5)),
            pool = nil, cone = nil,
        },
        hero_safe = { x = D.hero.x, z = D.hero.z },
        breakthrough_t = 0.0,
        reached_count = 0,
        revealed = 0,
        lit_count = 0,
        pan_t = PAN_TIME,
        flame_t = 0.0, flame_frame = 0,
        step_accum = 0.0, last_step_x = D.hero.x, last_step_z = D.hero.z,
    }
end

-- Relight every sconce/exit back to its unlit state on a run reset.
local function reset_state(D)
    local s = D.shadow
    if not s then return end
    for _, sc in ipairs(s.sconces) do
        sc.lit = false
        sc.t = 0.0
        if Art.valid(sc.flame) then material.set(sc.flame, "emissive", vec3(0.05, 0.0, 0.0)) end
        if Art.valid(sc.pool) then sc.pool:set_scale(vec3(0.4, 0.04, 0.4)); material.set(sc.pool, "emissive", vec3(0.0, 0.0, 0.0)) end
    end
    if s.exit then s.exit.reached = false end
    s.breakthrough_t = 0.0
    s.pan_t = PAN_TIME
    s.hero_safe.x, s.hero_safe.z = D.hero.x, D.hero.z
    s.last_step_x, s.last_step_z, s.step_accum = D.hero.x, D.hero.z, 0.0
end

-- ---------------------------------------------------------------------------
-- Mode contract
-- ---------------------------------------------------------------------------

return {
    meta = {
        id       = "shadow",
        name     = "Shadow Hunt",
        tagline  = "the dark is alive, and it is hunting you",
        blurb    = "A lightless stone maze. Your torch carves a single cone of sight; everything beyond it is teeth. Shades freeze when the light finds them — but the Umbral Stalker never does. Light the sconces, reach the exit, and pray.",
        side_hint = "horde",
        accent   = { 1.0, 0.60, 0.0, 0.95 },
        -- Normalized 0..1 top-down sketch: near-void maze, a warm torch cone, the
        -- cold exit rift, scattered shade-blots.
        minimap  = {
            bg = { 0.02, 0.02, 0.02, 1.0 },
            rects = {
                { 0.04, 0.04, 0.92, 0.92, { 0.07, 0.07, 0.08, 1.0 } },   -- stone floor
                -- maze corridors (dim grey strokes)
                { 0.10, 0.20, 0.80, 0.05, { 0.16, 0.16, 0.18, 1.0 } },
                { 0.10, 0.66, 0.80, 0.05, { 0.16, 0.16, 0.18, 1.0 } },
                { 0.16, 0.10, 0.05, 0.74, { 0.16, 0.16, 0.18, 1.0 } },
                { 0.80, 0.18, 0.05, 0.62, { 0.16, 0.16, 0.18, 1.0 } },
                { 0.46, 0.20, 0.05, 0.50, { 0.16, 0.16, 0.18, 1.0 } },
                -- torch cone + hero
                { 0.20, 0.16, 0.16, 0.16, { 1.0, 0.60, 0.0, 0.50 } },
                { 0.22, 0.18, 0.06, 0.08, { 1.0, 0.93, 0.53, 1.0 } },
                -- shade blots lurking in the dark
                { 0.62, 0.40, 0.05, 0.05, { 0.30, 0.18, 0.42, 0.9 } },
                { 0.36, 0.58, 0.05, 0.05, { 0.30, 0.18, 0.42, 0.9 } },
                { 0.70, 0.70, 0.05, 0.05, { 0.30, 0.18, 0.42, 0.9 } },
                -- the exit rift (cold)
                { 0.82, 0.80, 0.08, 0.10, { 1.0, 0.93, 0.53, 1.0 } },
            },
        },
    },

    config = {
        id   = "shadow",
        name = "Shadow Hunt",

        theme = Shadow.theme,
        -- The maze is the arena: a hand-authored map_def with flow-field pathing so
        -- the shadows BFS-thread the corridors (Creep.update honours map walls).
        arena = {
            width = ARENA_W, height = ARENA_H, pad = ARENA_PAD, ortho_size = 40.0,
            flow_field = true,
            map_def   = MAZE.map_def,
            hero_start = MAZE.hero_start,
            spawns     = MAZE.spawns,
            -- A tighter, lower iso so the maze walls box the player in.
            cam_offset = { x = -38.0, y = 40.0, z = 38.0 },
        },
        hero = {
            hp_max = HERO_TUNE.hp_max, dps = HERO_TUNE.dps, cleave = HERO_TUNE.cleave,
            attack_range = HERO_TUNE.attack_range, speed = HERO_TUNE.speed, kite_speed = HERO_TUNE.kite_speed,
            actor = HERO_RIG,
        },
        archetypes = Shadow.archetypes,
        roles      = Shadow.roles,

        -- Lean, frightening pressure: streaking shades, a holding wraith, the
        -- unseen stalker, the disorienting mimic, and a late behemoth.
        spawn = {
            interval_start = 0.85, interval_min = 0.40,
            batch_start    = 2,    batch_max    = 5,
            cap_start      = 22,   cap_max      = 64,
            brute_after    = 24.0,
        },
        reserve_start = 300.0,
        round_seconds = 14.0,

        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 12 == 0) then return "gloom_behemoth" end
            if D.spawn_counter % 9 == 0 then return "umbral_stalker" end
            if D.spawn_counter % 7 == 0 then return "shadow_mimic" end
            if D.spawn_counter % 4 == 0 then return "wraith" end
            return "shade"
        end,

        hooks = {
            -- Build the whole stage once. Props are parented to D.groups.world so
            -- they survive run resets (only dynamic shadow state is rebuilt).
            on_start = function(D)
                init_state(D)
                build_walls(D)
                for i, sp in ipairs(MAZE.sconces) do
                    D.shadow.sconces[i] = build_sconce(D, sp[1], sp[2], i)
                end
                D.shadow.exit = build_exit(D)
                build_torch(D)
            end,

            -- on_reset can fire BEFORE on_start (quick restart) — nil-guard.
            on_reset = function(D)
                reset_state(D)
            end,

            on_combat_tick = function(D, dt)
                update_pan(D, dt)
                update_torch(D, dt)
                update_sconces(D, dt)
                update_shadows(D, dt)
                update_footsteps(D, dt)
                update_exit(D, dt)
                update_collision(D)   -- last: resolve the hero against the stone
            end,

            -- Tag each freshly-spawned shadow and start it swallowed by the dark.
            on_spawn = function(D, creep)
                creep.sh_stun_t = 0.0
                creep.sh_recover = 0.0
                creep.sh_flash = 0.0
                if Art.valid(creep.parts and creep.parts.body) then
                    material.set(creep.parts.body, "emissive", vec3(0.05, 0.05, 0.06))
                end
            end,

            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local s = D.shadow or {}

                -- Darkness vignette overlay — a fullscreen frame that dims the edges
                -- (the PNG's centre is transparent, so the HUD stays readable). It is
                -- no_input so it never captures clicks.
                Art.quad(D.hud, "shadow_vignette", 0.0, 0.0, sw, sh, { 0.0, 0.0, 0.0, 0.0 },
                    { image = "Textures/modes/shadow/vignette.png", image_tint = { 1.0, 1.0, 1.0, 1.0 }, no_input = true })

                local exit_txt
                if s.exit and s.exit.reached then
                    exit_txt = "EXIT REACHED"
                elseif s.exit then
                    local dx, dz = D.hero.x - s.exit.x, D.hero.z - s.exit.z
                    exit_txt = string.format("Exit  %.0fm", math.sqrt(dx * dx + dz * dz))
                else
                    exit_txt = "-"
                end
                local hero_name = (HERO_KEY == "blind_swordsman") and "Blind Swordsman" or "Torch Bearer"
                local label = string.format("%s  -  %s\nSconces lit %d/%d    %s\nShadows revealed: %d%s",
                    hero_name, MAZE.map_def.title,
                    s.lit_count or 0, #(s.sconces or {}), exit_txt,
                    s.revealed or 0,
                    (s.breakthrough_t and s.breakthrough_t > 0.0) and "    *BREAKTHROUGH*" or "")
                Art.quad(D.hud, "shadow_status", 24.0, sh - 168.0, 560.0, 76.0,
                    { 0.03, 0.02, 0.02, 0.88 },
                    { border = { 1.0, 0.60, 0.0, 0.9 }, label = label })
            end,
        },
    },
}
