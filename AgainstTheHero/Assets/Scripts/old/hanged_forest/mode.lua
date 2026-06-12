-- Hanged Forest — a dead wood of black gnarled trees where the executed dangle
-- from every branch, and the soil itself reaches up to pull you under.
--
-- THE TWIST ON THE CONTRACT (like catacombs/bloodtide, the same shared Duel re-
-- staged in 2D). This is a SIDE-SCROLLER: the arena's X axis is the forest read
-- left->right, the Z axis is its shallow depth, and a mode-owned Y-up layer carries
-- the things the brief lives on — the swinging dead and the grasping roots. The
-- camera drops to a low side-on angle and tracks the hero through THREE parallax
-- CANOPY LAYERS. He still auto-fights and the horde still rushes him; we re-skin the
-- stage and add one bespoke mechanic, exactly as the guide prescribes.
--
-- Signature mechanic — ANIMATE DEAD (+ the swinging dead, the grasping roots).
--   * PENDULUMS. Hanged corpses dangle from the branches and SWING on real trig
--     pendulum physics (theta = amp * sin(w t)). Walk into one at the bottom of its
--     arc and the hero is STAGGERED (0.8s, can't move) and takes chip damage. The
--     EXECUTIONER hero answers by CUTTING the ropes he passes — a cut corpse drops
--     limp and harmless.
--   * ROOTS. Barbed roots erupt from the soil, telegraph, then GRAB: caught over an
--     erupting root, the hero is rooted in place for a beat. The LOST WANDERER is
--     light enough that the roots clutch a smaller patch and hold him briefly.
--   * ANIMATE DEAD — the Horde's signature. Every character card the Horde plays
--     (a back-face creature play) REANIMATES a hanging corpse: it drops off its rope
--     and rises as a Corpse Archer that fights for the horde. The strung-up dead are
--     a standing reserve the horde can call down at will.
--   * THE HANGING JUDGE — the boss. A massive figure that swings down from the
--     canopy once the run is old enough (the deck's brute), announced as it descends.
-- Hero immobilisation is done the mode-owned way (hero.move_mult = 0 each tick while
-- staggered/grabbed — never corrupting card stats); damage goes through the hazard
-- API (D:apply_hero_damage). Everything is ath_art primitives, self-lit, and
-- texture-ready; the seamless bark/ground/fog PNGs are wired live (see
-- tools/gen_textures_forest.py).

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Hf  = ATH_COMMON.load_script("Scripts/modes/hanged_forest/characters.lua", "hanged_forest characters", _ENV)

local C = Hf.palette

-- ---- Pendulum (swinging corpse) tuning -------------------------------------
local PEND_AMP        = 0.52    -- swing amplitude, radians (peak angle from vertical)
local PEND_OMEGA      = 1.7     -- base angular frequency (rad/s); jittered per corpse
local PEND_HIT_X      = 0.8     -- half-width of a corpse's hit box, world-x
local PEND_HIT_Z      = 1.5     -- depth tolerance to the hero's lane
local PEND_HIT_Y      = 1.5     -- a corpse only bites when its feet swing below this
local STAGGER_TIME    = 0.8     -- the brief's stagger: hero rooted, can't move
local STAGGER_CHIP    = 8.0     -- chip damage on a corpse collision
local PEND_HIT_CD     = 1.1     -- per-corpse re-hit cooldown so a swing isn't a grinder
local CUT_RANGE_PAD   = 0.25    -- executioner's reach past attack_range to sever a rope

-- ---- Root-grab tuning ------------------------------------------------------
local ROOT_FIRST      = 4.0     -- seconds of combat before the first root
local ROOT_INTERVAL   = 5.0     -- seconds between root eruptions
local ROOT_INTERVAL_MIN = 2.4
local ROOT_TELEGRAPH  = 1.1     -- soil-churn warning before the roots burst up
local ROOT_ERUPT      = 1.5     -- the brief's eruption lifetime
local ROOT_RADIUS     = 1.7     -- grab reach around a root
local ROOT_RADIUS_WANDERER = 1.1 -- the Wanderer is harder to catch
local GRAB_TIME       = 1.0     -- immobilise on a normal hero
local GRAB_TIME_WANDERER = 0.5  -- the Wanderer breaks free fast
local GRAB_CHIP       = 6.0     -- chip damage when the roots first clamp
local ROOT_MAX        = 4
local ROOT_OFFSETS    = { { -0.6, -0.2 }, { 0.0, 0.0 }, { 0.6, 0.2 }, { -0.3, 0.5 }, { 0.3, -0.5 } }
local ROOT_HIDDEN_Y   = -20.0

-- ---- Stage tuning ----------------------------------------------------------
-- Three canopy layers shoved with the camera at rising fractions, so the near
-- branches sweep past fast and the far tree-line barely drifts (faked depth).
local CANOPY_PARALLAX = { 0.78, 0.55, 0.30 }
local FOG_PARALLAX    = 0.16

-- Where the hanged corpses dangle. x = trunk the branch reaches from, anchor =
-- branch height, len = rope length, seed varies each one's swing.
local CORPSES = {
    { x = 10, anchor = 5.6, len = 3.4 },
    { x = 17, anchor = 6.2, len = 4.2 },
    { x = 24, anchor = 5.2, len = 3.0 },
    { x = 31, anchor = 6.0, len = 4.0 },
    { x = 39, anchor = 5.8, len = 3.6 },
    { x = 46, anchor = 6.4, len = 4.4 },
    { x = 53, anchor = 5.4, len = 3.2 },
    { x = 60, anchor = 6.0, len = 3.8 },
}

-- ---------------------------------------------------------------------------
-- The hanged corpses — built once in on_start; swung on trig physics each tick.
-- A corpse has a body (the dangling dead) and a rope (anchor -> body). `intact`
-- corpses swing and bite; `cut` (executioner) or `reanimated` (horde) ones hang
-- slack on the ground.
-- ---------------------------------------------------------------------------

local function build_corpses(D)
    local e = D.hf
    e.corpses = {}
    local g = D.groups.world
    local cz = D.arena.h * 0.5 - 1.0   -- the corpses hang a little in front of the lane
    for i, P in ipairs(CORPSES) do
        local rope = Art.cylinder("Hf_Rope_" .. i, vec3(P.x, P.anchor - P.len * 0.5, cz),
            vec3(0.07, P.len, 0.07), C.rope, g, 0.45)
        -- The dangling dead — a gaunt body the corpse sheet paints across.
        local body = Art.cube("Hf_Corpse_" .. i, vec3(P.x, P.anchor - P.len, cz),
            vec3(0.42, 1.0, 0.30), C.bone, g, 0.55, Hf.tex.corpse)
        e.corpses[i] = {
            x = P.x, anchor = P.anchor, len = P.len, cz = cz,
            rope = rope, body = body, seed = P.x * 0.7,
            omega = PEND_OMEGA * (0.85 + 0.012 * P.x % 0.3),
            state = "intact", hit_cd = 0.0, fall = 0.0,
        }
    end
end

local function reset_corpses(D)
    local e = D.hf
    for i, p in ipairs(e.corpses or {}) do
        local spec = CORPSES[i]
        if spec then
            p.x = spec.x
            p.anchor = spec.anchor
            p.len = spec.len
            p.state = "intact"
            p.hit_cd = 0.0
            p.fall = 0.0
            p.cur_x = spec.x
            p.cur_y = spec.anchor - spec.len
            p.cur_theta = 0.0
            if Art.valid(p.body) then
                p.body:set_position(vec3(p.x, p.anchor - p.len, p.cz))
                p.body:set_scale(vec3(0.42, 1.0, 0.30))
                p.body:set_rotation(vec3(0.0, 0.0, 0.0))
            end
            if Art.valid(p.rope) then
                p.rope:set_position(vec3(p.x, p.anchor - p.len * 0.5, p.cz))
                p.rope:set_scale(vec3(0.07, p.len, 0.07))
                p.rope:set_rotation(vec3(0.0, 0.0, 0.0))
            end
        end
    end
end

-- Swing each intact corpse on a real pendulum; cut/reanimated ones slump to the
-- soil. Returns nothing — collision is handled by the hero pass.
local function update_corpses(D, dt)
    local e = D.hf
    for _, p in ipairs(e.corpses) do
        p.hit_cd = math.max(0.0, p.hit_cd - dt)
        if p.state == "intact" then
            -- theta = amp * sin(w t + phase): the classic small-angle pendulum.
            local theta = PEND_AMP * math.sin(p.omega * D.realtime + p.seed)
            local bx = p.x + p.len * math.sin(theta)
            local by = p.anchor - p.len * math.cos(theta)
            p.cur_x, p.cur_y, p.cur_theta = bx, by, theta
            if Art.valid(p.body) then
                p.body:set_position(vec3(bx, by, p.cz))
                p.body:set_rotation(vec3(0.0, 0.0, math.deg(theta)))
            end
            if Art.valid(p.rope) then
                p.rope:set_position(vec3(p.x + p.len * 0.5 * math.sin(theta), p.anchor - p.len * 0.5 * math.cos(theta), p.cz))
                p.rope:set_rotation(vec3(0.0, 0.0, math.deg(theta)))
            end
        elseif p.state == "cut" or p.state == "reanimated" then
            -- Slack: the body has dropped; let it settle on the soil and lie still.
            if p.fall < 1.0 then
                p.fall = math.min(1.0, p.fall + dt * 2.2)
                local by = (p.anchor - p.len) + (0.2 - (p.anchor - p.len)) * p.fall
                if Art.valid(p.body) then
                    p.body:set_position(vec3(p.x, by, p.cz))
                    p.body:set_rotation(vec3(78.0 * p.fall, 0.0, 0.0))   -- topple flat
                end
            end
        end
    end
end

-- Sever a corpse's rope: it drops limp and harmless (the executioner's trick, and
-- the visual half of an ANIMATE DEAD reanimation).
local function drop_corpse(D, p, reanimated)
    p.state = reanimated and "reanimated" or "cut"
    p.fall = 0.0
    if Art.valid(p.rope) then
        p.rope:set_position(vec3(p.x, ROOT_HIDDEN_Y, p.cz))
        p.rope:set_scale(vec3(0.001, 0.001, 0.001))
    end
    Art.burst("ath_hf_cut_" .. tostring(p.x), vec3(p.x, p.anchor - p.len + 0.6, p.cz),
        { preset = "hero_take", count = 12, life_max = 0.35, spawn_radius = 0.4, noise_strength = 4.0, size_max = 0.20 })
end

-- The hero vs. the swinging dead: stagger on contact, and (executioner) sever any
-- rope within reach so the corpse goes slack before it can swing back.
local function update_hero_vs_corpses(D, dt)
    local e = D.hf
    local hero = D.hero
    if hero.dead then return end
    for _, p in ipairs(e.corpses) do
        if p.state == "intact" then
            -- Executioner severs ropes he walks under (within his cleaver's reach).
            if e.class == "executioner" then
                if math.abs(p.x - hero.x) <= (hero.attack_range + CUT_RANGE_PAD) then
                    drop_corpse(D, p, false)
                    D:set_flash("ROPE CUT")
                end
            end
            -- Collision: a corpse bites only at the low part of its arc, in the lane.
            if p.state == "intact" and p.hit_cd <= 0.0 and p.cur_y and p.cur_y <= PEND_HIT_Y then
                local dx = (p.cur_x or p.x) - hero.x
                local dz = p.cz - hero.z
                if math.abs(dx) <= PEND_HIT_X and math.abs(dz) <= PEND_HIT_Z then
                    p.hit_cd = PEND_HIT_CD
                    e.stagger_t = STAGGER_TIME
                    D:apply_hero_damage(STAGGER_CHIP, { flash = "STAGGERED!" })
                    Art.burst("ath_hf_swing_" .. tostring(p.x), vec3(hero.x, 0.9, hero.z),
                        { preset = "hero_take", count = 14, life_max = 0.3, spawn_radius = 0.5, noise_strength = 4.0, size_max = 0.2 })
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Root grabs — a floor hazard that erupts, telegraphs, then clamps the hero.
-- ---------------------------------------------------------------------------

local function root_random_x(D)
    local A = D.arena
    return math.random(A.pad + 3, A.w - A.pad - 3)
end

local function hide_root_nodes(r)
    if Art.valid(r.glow) then
        r.glow:set_position(vec3(0.0, ROOT_HIDDEN_Y, r.z or 0.0))
        r.glow:set_scale(vec3(0.001, 0.001, 0.001))
        material.set(r.glow, "emissive", vec3(0.0, 0.0, 0.0))
    end
    for _, b in ipairs(r.barbs or {}) do
        if Art.valid(b.node) then
            b.node:set_position(vec3(b.ox or 0.0, ROOT_HIDDEN_Y, (r.z or 0.0) + (b.oz or 0.0)))
            b.node:set_scale(vec3(0.001, 0.001, 0.001))
        end
    end
end

local function create_root_slot(D, slot)
    local g = D.groups.world
    local cz = D.arena.h * 0.5
    local glow = Art.cylinder("Hf_RootGlow_" .. slot, vec3(0.0, ROOT_HIDDEN_Y, cz),
        vec3(0.001, 0.001, 0.001), C.green, g, 0.0)
    local barbs = {}
    for i, o in ipairs(ROOT_OFFSETS) do
        local b = Art.cube("Hf_RootBarb_" .. slot .. "_" .. i, vec3(o[1], ROOT_HIDDEN_Y, cz + o[2]),
            vec3(0.001, 0.001, 0.001), C.bark, g, 0.55, Hf.tex.root)
        barbs[i] = { node = b, ox = o[1], oz = o[2] }
    end
    local root = { x = 0.0, z = cz, glow = glow, barbs = barbs, t = 0.0, phase = "idle", clamped = false, active = false }
    hide_root_nodes(root)
    return root
end

local function build_root_pool(D)
    local e = D.hf
    e.root_pool = {}
    for i = 1, ROOT_MAX do
        e.root_pool[i] = create_root_slot(D, i)
    end
end

local function reset_root(D, r, x)
    r.x = x
    r.z = D.arena.h * 0.5
    r.t = 0.0
    r.phase = "warn"
    r.clamped = false
    r.active = true
    if Art.valid(r.glow) then
        r.glow:set_position(vec3(r.x, 0.05, r.z))
        r.glow:set_scale(vec3(ROOT_RADIUS * 1.5, 0.04, ROOT_RADIUS * 1.5))
        material.set(r.glow, "emissive", vec3(0.20, 0.40, 0.0))
    end
    for _, b in ipairs(r.barbs) do
        if Art.valid(b.node) then
            b.node:set_position(vec3(r.x + b.ox, -1.2, r.z + b.oz))
            b.node:set_scale(vec3(0.12, 1.2, 0.12))
        end
    end
end

local function build_root(D, x)
    local e = D.hf
    for _, r in ipairs(e.root_pool or {}) do
        if not r.active then
            reset_root(D, r, x)
            return r
        end
    end
    return nil
end

local function set_barb_height(r, h)
    for _, b in ipairs(r.barbs) do
        if Art.valid(b.node) then b.node:set_position(vec3(r.x + b.ox, h - 0.6, r.z + b.oz)) end
    end
end

local function close_root(D, r)
    if not r then return end
    r.active = false
    r.phase = "idle"
    r.t = 0.0
    r.clamped = false
    hide_root_nodes(r)
end

local function clear_roots(D)
    for _, r in ipairs(D.hf and D.hf.roots or {}) do close_root(D, r) end
    if D.hf then D.hf.roots = {} end
end

local function update_roots(D, dt)
    local e = D.hf
    local hero = D.hero
    local grab_radius = (e.class == "lost_wanderer") and ROOT_RADIUS_WANDERER or ROOT_RADIUS
    local grab_time = (e.class == "lost_wanderer") and GRAB_TIME_WANDERER or GRAB_TIME

    -- Schedule new roots; cadence tightens as the rounds climb.
    e.next_root = e.next_root - dt
    if e.next_root <= 0.0 and #e.roots < ROOT_MAX then
        e.next_root = math.max(ROOT_INTERVAL_MIN, ROOT_INTERVAL - 0.4 * (D.round - 1))
        -- Bias the eruption toward the hero so the grab is a real threat to read.
        local x = (math.random() < 0.6) and math.floor(hero.x + math.random(-2, 2))
            or root_random_x(D)
        x = math.max(D.arena.pad + 3, math.min(D.arena.w - D.arena.pad - 3, x))
        local root = build_root(D, x)
        if root then e.roots[#e.roots + 1] = root end
    end

    local survivors = {}
    for _, r in ipairs(e.roots) do
        r.t = r.t + dt
        local keep = true
        if r.phase == "warn" then
            local pulse = 0.4 + 1.4 * (0.5 + 0.5 * math.sin(D.realtime * 14.0)) * math.min(1.0, r.t / ROOT_TELEGRAPH)
            if Art.valid(r.glow) then material.set(r.glow, "emissive", vec3(0.20 * pulse, 0.40 * pulse, 0.0)) end
            if r.t >= ROOT_TELEGRAPH then
                r.phase = "erupt"; r.t = 0.0
                set_barb_height(r, 1.2)
                Art.burst("ath_hf_root_" .. tostring(r.x), vec3(r.x, 0.6, r.z),
                    { preset = "hero_take", count = 16, life_max = 0.4, spawn_radius = ROOT_RADIUS * 0.5, noise_strength = 4.0, size_max = 0.22 })
                -- Grab: caught over the eruption, the hero is rooted (immobilised).
                if not hero.dead and not r.clamped then
                    local dx, dz = hero.x - r.x, hero.z - r.z
                    if dx * dx + dz * dz <= grab_radius * grab_radius then
                        r.clamped = true
                        e.grab_t = grab_time
                        D:apply_hero_damage(GRAB_CHIP, { flash = "ROOTED!" })
                    end
                end
            end
        elseif r.phase == "erupt" then
            -- Sway the barbs while they're up; then they sink back into the soil.
            local s = 1.0 + 0.06 * math.sin(D.realtime * 6.0 + r.x)
            set_barb_height(r, 1.2 * s)
            if r.t >= ROOT_ERUPT then
                close_root(D, r); keep = false
            end
        end
        if keep then survivors[#survivors + 1] = r end
    end
    e.roots = survivors
end

-- ---------------------------------------------------------------------------
-- Hero immobilisation — apply the stagger/grab timers the mode-owned way:
-- pin move_mult to 0 while either is live, and tilt the rig so the hold reads.
-- (on_combat_tick runs AFTER update_hero, so this is the final say each frame.)
-- ---------------------------------------------------------------------------

local function update_hero_state(D, dt)
    local e = D.hf
    local hero = D.hero
    e.stagger_t = math.max(0.0, e.stagger_t - dt)
    e.grab_t = math.max(0.0, e.grab_t - dt)
    if hero.dead then hero.move_mult = 1.0; return end

    if e.stagger_t > 0.0 or e.grab_t > 0.0 then
        hero.move_mult = 0.0
        if Art.valid(hero.root) then
            local ws = hero.world_scale or 1.0
            if e.grab_t > 0.0 then
                -- Hauled toward the ground — a squash + a small sink.
                hero.root:set_position(vec3(hero.x, -0.12, hero.z))
                hero.root:set_scale(vec3(ws * 1.05, ws * 0.82, ws * 1.05))
                hero.root:set_rotation(vec3(0.0, math.deg(hero.facing or 0.0), 0.0))
            else
                -- Reeling — a sharp tilt that recovers as the stagger fades.
                local lean = 26.0 * (e.stagger_t / STAGGER_TIME)
                hero.root:set_rotation(vec3(0.0, math.deg(hero.facing or 0.0), lean))
                hero.root:set_scale(vec3(ws, ws, ws))
            end
        end
    else
        hero.move_mult = 1.0
    end
end

-- ---------------------------------------------------------------------------
-- ANIMATE DEAD — the Horde's signature. Reanimate a hanging corpse: drop it off
-- its rope and spawn a Corpse Archer at the spot, fighting for the horde.
-- ---------------------------------------------------------------------------

local function animate_dead(D)
    local e = D.hf
    -- Prefer a corpse near the hero (a reanimation he'll feel); else any intact one.
    local best, bestd = nil, 1e9
    for _, p in ipairs(e.corpses) do
        if p.state == "intact" then
            local d = math.abs(p.x - D.hero.x)
            if d < bestd then best, bestd = p, d end
        end
    end
    if not best then return false end
    drop_corpse(D, best, true)
    -- Loose it as a Corpse Archer at the corpse's foot (free — the card paid).
    D:spawn_one({ x = best.x, y = D.arena.h * 0.5 }, "corpse_archer", true)
    D:set_flash("ANIMATE DEAD!")
    Art.burst("ath_hf_animate_" .. tostring(best.x), vec3(best.x, 1.0, best.cz),
        { preset = "hero_take", count = 20, life_max = 0.5, spawn_radius = 0.7, noise_strength = 5.0, size_max = 0.26 })
    return true
end

-- ---- Camera: a side-on rig tracking the hero through 3 parallax canopies -----

local function update_camera(D)
    local A = D.arena
    local e = D.hf
    local half = A.ortho_size * 0.5
    local cx = math.max(A.pad + half * 0.4, math.min(A.w - A.pad - half * 0.4, D.hero.x))
    Art.setup_iso_camera({ x = cx, z = A.h * 0.5 - 0.5 },
        { ortho_size = A.ortho_size, offset = A.cam_offset })
    -- Parallax the fog wall + each canopy layer at its own fraction.
    if Art.valid(e.fog) then e.fog:set_position(vec3(FOG_PARALLAX * cx, 4.0, A.h - A.pad + 1.4)) end
    for _, layer in ipairs(e.canopy or {}) do
        if Art.valid(layer.node) then layer.node:set_position(vec3(layer.par * cx, layer.y, layer.z)) end
    end
end

-- ---- Hero class selection (two survivors; brief) ---------------------------

local function pick_hero()
    local class = "executioner"
    if ATH_COMMON and ATH_COMMON.getenv then
        local v = ATH_COMMON.getenv("ATH_HANGED_HERO")
        if type(v) == "string" and Hf.heroes[v:lower()] then class = v:lower() end
    end
    return class, Hf.heroes[class]
end

local CLASS, HERO = pick_hero()

-- ---------------------------------------------------------------------------
-- Mode contract
-- ---------------------------------------------------------------------------

return {
    meta = {
        id = "hanged_forest",
        name = "Hanged Forest",
        tagline = "the dead wood that hangs its harvest",
        blurb = "A 2D side-scroller through a dead forest of black gnarled trees. Hanged corpses swing across the path and stagger you; roots grab from below. The horde ANIMATES the dangling dead to fight — and the Hanging Judge swings down from the canopy.",
        side_hint = "horde",
        accent = { 0.40, 0.55, 0.0, 0.95 },
        -- A side-on sketch of the wood (normalized 0..1 rects: x,y,w,h,color).
        minimap = {
            bg = { 0.020, 0.020, 0.020, 1.0 },
            rects = {
                { 0.00, 0.00, 1.00, 0.30, { 0.039, 0.059, 0.0, 1.0 } },  -- the canopy band
                { 0.04, 0.78, 0.92, 0.14, { 0.039, 0.059, 0.0, 1.0 } },  -- dead-leaf soil
                { 0.12, 0.00, 0.05, 0.78, { 0.239, 0.239, 0.0, 1.0 } },  -- black trunks
                { 0.40, 0.00, 0.05, 0.78, { 0.239, 0.239, 0.0, 1.0 } },
                { 0.68, 0.00, 0.05, 0.78, { 0.239, 0.239, 0.0, 1.0 } },
                { 0.22, 0.30, 0.04, 0.30, { 0.784, 0.784, 0.627, 1.0 } }, -- hanged corpses
                { 0.50, 0.30, 0.04, 0.34, { 0.784, 0.784, 0.627, 1.0 } },
                { 0.78, 0.30, 0.04, 0.28, { 0.784, 0.784, 0.627, 1.0 } },
                { 0.08, 0.62, 0.05, 0.18, { 0.784, 0.784, 0.627, 1.0 } }, -- hero (left)
                { 0.34, 0.66, 0.04, 0.12, { 0.102, 0.165, 0.0, 1.0 } },   -- a forest wraith
                { 0.60, 0.86, 0.06, 0.05, { 0.40, 0.55, 0.0, 1.0 } },     -- a root grab
            },
        },
    },

    config = {
        id = "hanged_forest",
        name = "Hanged Forest",
        theme = Hf.theme,
        -- A long, shallow WOOD. Wide X (read left->right), shallow Z depth, low
        -- side-on camera that tracks the hero (update_camera, each tick). The Y
        -- axis carries the swinging corpses and the erupting roots.
        arena = {
            width = 66, height = 16, pad = 2, ortho_size = 22.0,
            cam_offset = { x = 0.0, y = 10.0, z = -30.0 },   -- side elevation, not iso
            hero_start = { x = 5, y = 8 },
            -- The dead drift in from the FAR (right) end of the wood.
            spawns = {
                { x = 60, y = 8 }, { x = 62, y = 6 }, { x = 62, y = 10 },
                { x = 58, y = 5 }, { x = 58, y = 11 }, { x = 54, y = 8 },
            },
        },
        hero = {
            hp_max = HERO.stats.hp_max, dps = HERO.stats.dps, cleave = HERO.stats.cleave,
            attack_range = HERO.stats.attack_range, speed = HERO.stats.speed, kite_speed = HERO.stats.kite_speed,
            actor = HERO.actor,
        },
        archetypes = Hf.archetypes,
        roles = Hf.roles,
        spawn = { interval_start = 0.8, interval_min = 0.34, batch_start = 3, batch_max = 6, cap_start = 28, cap_max = 82, brute_after = 24.0 },
        reserve_start = 320.0,
        round_seconds = 14.0,

        -- A dead-wood mix: wraiths are the chaff spine, corpse archers hold range,
        -- root tendrils block the lane, the Hanging Judge swings down once the timer
        -- is spent.
        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 12 == 0) then return "hanging_judge" end
            if D.spawn_counter % 8 == 0 then return "root_tendril" end
            if D.spawn_counter % 5 == 0 then return "corpse_archer" end
            return "forest_wraith"
        end,

        hooks = {
            on_start = function(D)
                local A = D.arena
                D.hf = {
                    corpses = {}, roots = {}, root_pool = {}, canopy = {}, fog = nil,
                    next_root = ROOT_FIRST,
                    stagger_t = 0.0, grab_t = 0.0, class = CLASS,
                    judge_seen = false,
                }
                local g = D.groups.world
                local far_z = A.h - A.pad + 1.2

                -- A dark fog wall far behind everything (dark_fog.png), for parallax.
                D.hf.fog = Art.cube("Hf_Fog", vec3(FOG_PARALLAX * A.w * 0.5, 4.0, far_z),
                    vec3(A.w * 1.8, 11.0, 0.2), { 0.5, 0.5, 0.5 }, g, 0.16, Hf.tex.fog)

                -- THREE canopy layers: bands of black branches at rising parallax, so
                -- the near branches sweep past and the far tree-line barely drifts.
                local CY = { { y = 8.6, z = A.h - A.pad - 0.3, h = 4.2, em = 0.30 },
                             { y = 9.2, z = A.h - A.pad - 0.9, h = 3.4, em = 0.22 },
                             { y = 9.6, z = A.h - A.pad - 1.6, h = 2.8, em = 0.16 } }
                for li, cl in ipairs(CY) do
                    local node = Art.cube("Hf_Canopy_" .. li, vec3(CANOPY_PARALLAX[li] * A.w * 0.5, cl.y, cl.z),
                        vec3(A.w * 1.8, cl.h, 0.2), C.forest, g, cl.em, Hf.tex.bark)
                    D.hf.canopy[li] = { node = node, par = CANOPY_PARALLAX[li], y = cl.y, z = cl.z }
                end

                -- A panelled bark back wall so the seamless tile reads across it.
                local panel = 4.0
                for px = A.pad, A.w - A.pad, panel do
                    Art.cube("Hf_BackWall_" .. math.floor(px), vec3(px + panel * 0.5, 3.4, A.h - A.pad - 0.2),
                        vec3(panel, 6.8, 0.4), C.forest, g, 0.42, Hf.tex.bark)
                end

                -- Black gnarled trunks marching down the wood (bark_tile.png).
                for tx = A.pad + 3, A.w - A.pad - 1, 7 do
                    Art.cube("Hf_Trunk_" .. tx, vec3(tx, 3.2, A.h - A.pad - 1.0), vec3(0.7, 6.4, 0.7), C.bark, g, 0.5, Hf.tex.bark)
                    -- A reaching branch the corpses hang from.
                    Art.cube("Hf_Branch_" .. tx, vec3(tx + 1.2, 5.8, A.h * 0.5 - 1.0), vec3(2.6, 0.22, 0.22), C.bark, g, 0.45)
                end

                -- The dead-leaf soil (ground_tile.png) the roots tear up through.
                Art.cube("Hf_Floor", vec3(A.w * 0.5, -0.2, A.h * 0.5), vec3(A.w, 0.4, A.h),
                    C.forest, g, 0.22, Hf.tex.ground)

                -- A few cold moonlight shafts spearing down through the canopy.
                for _, mx in ipairs({ 0.22, 0.55, 0.82 }) do
                    Art.cube("Hf_Moon_" .. math.floor(mx * 100), vec3(A.w * mx, 4.4, A.h - A.pad - 2.2),
                        vec3(1.6, 8.8, 0.1), C.moon, g, 0.5, Hf.tex.moonlight)
                end

                build_corpses(D)
                build_root_pool(D)
                update_camera(D)
            end,

            on_reset = function(D)
                -- NIL-GUARD (can fire before on_start). Re-hang the corpses, drop the
                -- roots, clear the hero's holds; the wood survives in `world`.
                clear_roots(D)
                if D.hf then
                    D.hf.next_root = ROOT_FIRST
                    D.hf.stagger_t = 0.0
                    D.hf.grab_t = 0.0
                    D.hf.judge_seen = false
                    reset_corpses(D)
                    D.hero.move_mult = 1.0
                end
            end,

            on_spawn = function(D, creep)
                -- Announce the boss the first time it swings down from the canopy.
                if D.hf and creep and creep.archetype == "hanging_judge" and not D.hf.judge_seen then
                    D.hf.judge_seen = true
                    D:set_flash("THE HANGING JUDGE DESCENDS")
                    Art.burst("ath_hf_judge_descend", vec3(creep.x, 5.0, D.arena.h * 0.5),
                        { preset = "hero_take", count = 28, life_max = 0.6, spawn_radius = 1.4, noise_strength = 5.0, size_max = 0.32 })
                end
            end,

            on_card = function(D, side, card_id, effect)
                -- ANIMATE DEAD: every Horde back-face creature play reanimates a
                -- hanging corpse into a Corpse Archer.
                if D.hf and side == "horde" then animate_dead(D) end
            end,

            on_combat_tick = function(D, dt)
                local e = D.hf
                if not e then return end
                update_corpses(D, dt)
                update_hero_vs_corpses(D, dt)
                update_roots(D, dt)
                update_hero_state(D, dt)
                update_camera(D)
                -- Moonlight breathes; the fog hangs cold and still.
            end,

            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local e = D.hf
                local A = D.arena
                -- Forest depth toward the far end (left->right "progress").
                local prog = math.max(0.0, math.min(1.0, (D.hero.x - 5.0) / ((A.w - A.pad - 2.0) - 5.0)))
                -- Count the corpses still hanging (the horde's reanimation reserve).
                local hung, roots = 0, (e and #e.roots or 0)
                for _, p in ipairs(e and e.corpses or {}) do if p.state == "intact" then hung = hung + 1 end end
                local hold = ""
                if e and e.grab_t > 0.0 then hold = "  ROOTED"
                elseif e and e.stagger_t > 0.0 then hold = "  STAGGERED" end
                Art.quad(D.hud, "hf_panel", 24.0, sh - 150.0, 580.0, 58.0, { 0.020, 0.030, 0.0, 0.9 },
                    { border = { 0.40, 0.55, 0.0, 0.9 },
                      label = string.format("SURVIVOR: %s    Depth: %d%%    Hanged: %d    Roots: %d%s",
                        (e and e.class or CLASS):upper(), math.floor(prog * 100.0 + 0.5), hung, roots, hold) })
            end,
        },
    },
}
