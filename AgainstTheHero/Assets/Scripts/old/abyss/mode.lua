-- The Abyss — a bottomless chasm the hero plunges down forever, into the dark.
--
-- THE CONTRACT: return { meta = {...}, config = {...} }.
--   * meta   — what the menu shows: name, blurb, minimap sketch, accent colour.
--   * config — handed to the shared Duel (ath_duel.lua): theme, arena, hero,
--              characters (from characters.lua), role mapping, spawn tuning, and
--              HOOKS for this level's one signature mechanic.
--
-- The Duel is a TOP-DOWN arena, so the chasm is mapped onto it: the arena's Z
-- axis IS the vertical fall. z = pad (the top edge) is UP the chasm — where the
-- light was — and +Z is DOWN into the deep. Everything falls toward the hero from
-- above (low z) along +Z.
--
-- Signature mechanic — THE DESCENT. A depth counter scrolls downward forever; its
-- speed accelerates to a TERMINAL VELOCITY (the hero's fall). As depth grows the
-- run passes through 5 DEPTH ZONES, each darker and deadlier. The horde rains
-- three hazards from above, all built from ath_art primitives and texture-ready:
--   * BOULDERS    — spawn at the top, gravity-accelerate to terminal, TUMBLE as
--                   they roll down, and crush + shove the hero on contact.
--   * CHAINS      — anchored at the ceiling, swinging on simple-pendulum trig;
--                   the spiked weight sweeps the chasm and mauls anything it hits.
--   * SPIKES      — platforms that slam out of the wall: a telegraph, then an
--                   instant-kill armed window. Stand clear or be impaled.
-- Three PARALLAX layers of cave wall scroll past at different speeds to sell the
-- endless fall, and the hero GLIDES (an archetype-tuned move bonus).

local Art   = ATH_COMMON.load_script("Scripts/shared/ath_art.lua",            "shared art",        _ENV)
local Abyss = ATH_COMMON.load_script("Scripts/modes/abyss/characters.lua",    "abyss characters",  _ENV)

local TEX = "Textures/modes/abyss/"

-- ---- Descent / depth tuning -------------------------------------------------
local DESCENT_START     = 6.0     -- starting fall speed ("metres"/sec of depth)
local DESCENT_TERMINAL  = 26.0    -- terminal velocity the fall accelerates to
local DESCENT_ACCEL     = 1.4     -- how fast we approach terminal (per sec)
local ZONE_DEPTH        = 220.0   -- depth span of one zone; zone 5 is endless
local ZONE_MAX          = 5

-- The five zones, deepest danger last. Each name surfaces in the HUD.
local ZONES = {
    { name = "I · The Mouth",       tint = { 0.10, 0.10, 0.18 } },
    { name = "II · The Throat",     tint = { 0.08, 0.06, 0.16 } },
    { name = "III · The Hollow",    tint = { 0.06, 0.04, 0.14 } },
    { name = "IV · The Drowning",   tint = { 0.05, 0.02, 0.12 } },
    { name = "V · The Final Plunge",tint = { 0.03, 0.00, 0.10 } },
}

-- ---- Boulder tuning ---------------------------------------------------------
local BOULDER_FIRST     = 3.0     -- seconds of combat before the first boulder
local BOULDER_INTERVAL  = 4.2     -- base seconds between drops (zone 1)
local BOULDER_INT_PER_Z = 0.55    -- cadence shaved per zone deeper
local BOULDER_INT_MIN   = 1.1
local BOULDER_GRAVITY   = 16.0    -- downward (+Z) acceleration — momentum builds
local BOULDER_VZ_START  = 3.0     -- initial fall speed when it tips over the edge
local BOULDER_VZ_TERM   = 24.0    -- boulder terminal velocity
local BOULDER_RADIUS    = 1.7
local BOULDER_DAMAGE     = 28.0   -- crush damage on contact
local BOULDER_DMG_PER_Z = 5.0     -- extra crush per zone deeper
local BOULDER_SHOVE     = 4.5     -- how far the hero is punched along +Z on a hit
local BOULDER_MAX       = 6

-- ---- Chain (pendulum) tuning ------------------------------------------------
local CHAIN_LINKS       = 6       -- visible links rendered along each rope
local CHAIN_LENGTH      = 9.0     -- rope length (world units)
local CHAIN_AMP         = 0.95    -- swing amplitude (radians, ~54 degrees)
local CHAIN_OMEGA       = 1.7     -- angular speed of the swing
local CHAIN_WEIGHT_R    = 1.15    -- spiked-weight collision/visual radius
local CHAIN_DAMAGE      = 18.0    -- damage per sweep-hit
local CHAIN_HIT_CD      = 0.6     -- min seconds between hits from one chain

-- ---- Spike-platform tuning --------------------------------------------------
local SPIKE_FIRST       = 7.0     -- combat seconds before the first spike slam
local SPIKE_INTERVAL    = 6.5     -- base seconds between slams (zone 1)
local SPIKE_INT_PER_Z   = 0.8
local SPIKE_INT_MIN     = 2.0
local SPIKE_TELEGRAPH   = 1.1     -- warning time before the spikes arm
local SPIKE_ARMED       = 1.3     -- lethal window
local SPIKE_HALF_W      = 4.0     -- half-width of the slab along X
local SPIKE_HALF_Z      = 1.4     -- half-depth of the slab along Z
local SPIKE_DAMAGE      = 90.0    -- effectively an instant kill if caught
local SPIKE_MAX         = 3

-- ---- Parallax tuning --------------------------------------------------------
-- Three depth layers of cave wall. Distant layers are slower, dimmer, and INSET
-- (the chasm narrows with depth). Each layer is a column of wall segments on both
-- side edges that scroll upward (-Z) to sell the fall, recycling to the bottom.
local PARALLAX = {
    { speed = 3.0,  inset = 0.0, dim = 0.55, segs = 6, scale = 1.0 },  -- near wall
    { speed = 1.8,  inset = 1.6, dim = 0.35, segs = 6, scale = 0.8 },  -- mid wall
    { speed = 1.0,  inset = 3.0, dim = 0.20, segs = 6, scale = 0.6 },  -- far wall
}

-- ---- Small helpers ----------------------------------------------------------

local function zone_of(depth)
    local z = 1 + math.floor(depth / ZONE_DEPTH)
    if z < 1 then z = 1 end
    if z > ZONE_MAX then z = ZONE_MAX end
    return z
end

-- Pick an x lane somewhere across the playable width.
local function random_x(A)
    return A.pad + 2 + math.random() * (A.w - 2 * (A.pad + 2))
end

-- ---- Parallax cave walls (purely cosmetic, scroll forever) ------------------

local function build_parallax(D)
    local A = D.arena
    local e = D.abyss
    e.parallax = {}
    for li, L in ipairs(PARALLAX) do
        local layer = { speed = L.speed, dim = L.dim, segs = {} }
        local span  = (A.h - 2 * A.pad) / L.segs
        for side = -1, 1, 2 do            -- left edge (-1) and right edge (+1)
            local edge_x = (side < 0) and (A.pad + L.inset) or (A.w - A.pad - L.inset)
            for s = 1, L.segs do
                local z = A.pad + (s - 0.5) * span
                local node = Art.cube(
                    "Abyss_Wall_" .. li .. "_" .. (side < 0 and "L" or "R") .. "_" .. s,
                    vec3(edge_x, 0.6 * L.scale, z),
                    vec3(0.7 * L.scale, 2.4 * L.scale, span * 0.82),
                    ZONES[1].tint, e.parallax_root, L.dim,
                    TEX .. "parallax_walls.png")
                layer.segs[#layer.segs + 1] = { node = node, x = edge_x, z = z, top = A.pad, bottom = A.h - A.pad }
            end
        end
        e.parallax[#e.parallax + 1] = layer
    end
end

local function update_parallax(D, dt)
    local e = D.abyss
    if not e.parallax then return end
    local A = D.arena
    -- Walls drift UP (-Z) so the world appears to fall past the hero; recycle.
    for _, layer in ipairs(e.parallax) do
        for _, seg in ipairs(layer.segs) do
            seg.z = seg.z - layer.speed * dt
            if seg.z < seg.top then seg.z = seg.z + (A.h - 2 * A.pad) end
            if Art.valid(seg.node) then seg.node:set_position(vec3(seg.x, 0.6, seg.z)) end
        end
    end
end

-- Repaint every wall toward the current zone's tint (the chasm darkens as we fall).
local function tint_parallax(D, zone)
    local e = D.abyss
    if not e.parallax then return end
    local c = ZONES[zone].tint
    for _, layer in ipairs(e.parallax) do
        for _, seg in ipairs(layer.segs) do
            if Art.valid(seg.node) then
                material.set(seg.node, "emissive", vec3(c[1] * layer.dim, c[2] * layer.dim, c[3] * layer.dim))
            end
        end
    end
end

-- ---- Boulders (gravity-accelerated, tumbling) -------------------------------

local function launch_boulder(D)
    local e = D.abyss
    if #e.boulders >= BOULDER_MAX then return end
    local A = D.arena
    local x = random_x(A)
    -- ARTIST NOTE: skin via the boulder.png passed below.
    local node = Art.sphere("Abyss_Boulder_" .. e.counter,
        vec3(x, BOULDER_RADIUS * 0.9, A.pad + 0.5),
        vec3(BOULDER_RADIUS * 2.0, BOULDER_RADIUS * 2.0, BOULDER_RADIUS * 2.0),
        { 0.16, 0.14, 0.20 }, D.groups.world, 0.7, TEX .. "boulder.png")
    e.counter = e.counter + 1
    e.boulders[#e.boulders + 1] = { node = node, x = x, z = A.pad + 0.5, vz = BOULDER_VZ_START, spin = 0.0, hit = false }
end

local function clear_boulders(D)
    for _, b in ipairs(D.abyss and D.abyss.boulders or {}) do
        if Art.valid(b.node) then scene.delete_node(b.node) end
    end
    if D.abyss then D.abyss.boulders = {} end
end

local function update_boulders(D, dt, zone)
    local e = D.abyss
    local A = D.arena
    local hero = D.hero

    -- Schedule drops; cadence tightens with depth.
    e.next_boulder = e.next_boulder - dt
    if e.next_boulder <= 0.0 then
        launch_boulder(D)
        e.next_boulder = math.max(BOULDER_INT_MIN, BOULDER_INTERVAL - BOULDER_INT_PER_Z * (zone - 1))
    end

    local dmg = BOULDER_DAMAGE + BOULDER_DMG_PER_Z * (zone - 1)
    local survivors = {}
    for _, b in ipairs(e.boulders) do
        -- Momentum builds: accelerate toward boulder terminal velocity.
        b.vz = math.min(BOULDER_VZ_TERM, b.vz + BOULDER_GRAVITY * dt)
        b.z  = b.z + b.vz * dt
        -- Tumble: roll angle advances with distance travelled (arc length / radius).
        b.spin = (b.spin + b.vz * dt * (180.0 / (math.pi * BOULDER_RADIUS))) % 360.0
        if Art.valid(b.node) then
            b.node:set_position(vec3(b.x, BOULDER_RADIUS * 0.9, b.z))
            b.node:set_rotation(vec3(b.spin, 0.0, 0.0))
            local glow = 0.6 + 0.25 * math.sin(D.realtime * 6.0 + b.x)
            material.set(b.node, "emissive", vec3(0.30 * glow, 0.10 * glow, 0.04 * glow))
        end
        -- Crush + shove the hero (once per boulder).
        if not hero.dead and not b.hit then
            local dx, dz = hero.x - b.x, hero.z - b.z
            if dx * dx + dz * dz <= BOULDER_RADIUS * BOULDER_RADIUS then
                D:apply_hero_damage(dmg, { flash = "CRUSHED!" })
                hero.z = hero.z + BOULDER_SHOVE
                b.hit = true
            end
        end
        if b.z < A.h - A.pad then
            survivors[#survivors + 1] = b
        elseif Art.valid(b.node) then
            scene.delete_node(b.node)
        end
    end
    e.boulders = survivors
end

-- ---- Swinging chains (simple pendulum) --------------------------------------

local function spawn_chain(D)
    local e = D.abyss
    if #e.chains >= ZONE_MAX then return end
    local A = D.arena
    local anchor_x = random_x(A)
    local anchor_z = A.pad + 0.4
    local chain = {
        ax = anchor_x, az = anchor_z, phase = math.random() * math.pi * 2.0,
        omega = CHAIN_OMEGA * (0.85 + math.random() * 0.3), hit_cd = 0.0, links = {},
    }
    -- Ceiling anchor bracket.
    Art.cube("Abyss_ChainAnchor_" .. e.counter, vec3(anchor_x, 1.4, anchor_z),
        vec3(0.5, 0.4, 0.5), { 0.20, 0.20, 0.28 }, D.groups.world, 0.5, TEX .. "rock_tile.png")
    -- The rope links (repositioned every tick along the swing).
    -- ARTIST NOTE: chain_link.png tiles cleanly along the rope.
    for i = 1, CHAIN_LINKS do
        chain.links[i] = Art.cube("Abyss_ChainLink_" .. e.counter .. "_" .. i,
            vec3(anchor_x, 1.0, anchor_z), vec3(0.22, 0.22, 0.22),
            { 0.30, 0.30, 0.38 }, D.groups.world, 0.6, TEX .. "chain_link.png")
    end
    -- The spiked weight at the rope's end.
    chain.weight = Art.sphere("Abyss_ChainWeight_" .. e.counter,
        vec3(anchor_x, 0.9, anchor_z), vec3(CHAIN_WEIGHT_R * 2.0, CHAIN_WEIGHT_R * 2.0, CHAIN_WEIGHT_R * 2.0),
        { 0.18, 0.16, 0.22 }, D.groups.world, 0.8, TEX .. "boulder.png")
    e.counter = e.counter + 1
    e.chains[#e.chains + 1] = chain
end

local function clear_chains(D)
    for _, c in ipairs(D.abyss and D.abyss.chains or {}) do
        for _, lk in ipairs(c.links) do if Art.valid(lk) then scene.delete_node(lk) end end
        if Art.valid(c.weight) then scene.delete_node(c.weight) end
    end
    if D.abyss then D.abyss.chains = {} end
end

local function update_chains(D, dt, zone)
    local e = D.abyss
    local hero = D.hero

    -- Keep `zone` chains alive (deeper zones hang more chains).
    if #e.chains < zone then spawn_chain(D) end

    for _, c in ipairs(e.chains) do
        c.hit_cd = math.max(0.0, c.hit_cd - dt)
        -- Simple pendulum: angle swings sinusoidally about the ceiling pivot.
        local angle = CHAIN_AMP * math.sin(c.omega * D.realtime + c.phase)
        local sx, cz = math.sin(angle), math.cos(angle)
        local wx = c.ax + CHAIN_LENGTH * sx           -- weight X (lateral swing)
        local wz = c.az + CHAIN_LENGTH * cz           -- weight Z (down the chasm)
        -- Lay the visible links evenly from anchor to weight.
        for i, lk in ipairs(c.links) do
            local t = i / (CHAIN_LINKS + 1)
            if Art.valid(lk) then
                lk:set_position(vec3(c.ax + CHAIN_LENGTH * t * sx, 1.0, c.az + CHAIN_LENGTH * t * cz))
                lk:set_rotation(vec3(0.0, 0.0, math.deg(angle)))
            end
        end
        if Art.valid(c.weight) then
            c.weight:set_position(vec3(wx, 0.9, wz))
            local g = 0.8 + 0.3 * math.sin(D.realtime * 5.0 + c.phase)
            material.set(c.weight, "emissive", vec3(0.30 * g, 0.06 * g, 0.02 * g))
        end
        -- Sweep damage with a per-chain cooldown so it mauls, not deletes.
        if not hero.dead and c.hit_cd <= 0.0 then
            local dx, dz = hero.x - wx, hero.z - wz
            if dx * dx + dz * dz <= CHAIN_WEIGHT_R * CHAIN_WEIGHT_R then
                D:apply_hero_damage(CHAIN_DAMAGE, { flash = "SWEPT!" })
                c.hit_cd = CHAIN_HIT_CD
            end
        end
    end
end

-- ---- Spike platforms (telegraph → instant-kill armed window) -----------------

local function spawn_spike(D)
    local e = D.abyss
    if #e.spikes >= SPIKE_MAX then return end
    local A = D.arena
    local cx = random_x(A)
    local cz = math.random() * (A.h - 2 * (A.pad + 3)) + (A.pad + 3)
    -- Flat telegraph slab on the floor (grows/pulses during the warning).
    local tele = Art.cube("Abyss_SpikeTele_" .. e.counter,
        vec3(cx, 0.06, cz), vec3(SPIKE_HALF_W * 2.0, 0.10, SPIKE_HALF_Z * 2.0),
        { 1.0, 0.20, 0.05 }, D.groups.world, 1.8)
    e.counter = e.counter + 1
    e.spikes[#e.spikes + 1] = { cx = cx, cz = cz, t = 0.0, phase = "warn", tele = tele, spikes = nil, hit = false }
end

local function close_spike(s)
    if Art.valid(s.tele) then scene.delete_node(s.tele) end
    for _, sp in ipairs(s.spikes or {}) do if Art.valid(sp) then scene.delete_node(sp) end end
end

local function clear_spikes(D)
    for _, s in ipairs(D.abyss and D.abyss.spikes or {}) do close_spike(s) end
    if D.abyss then D.abyss.spikes = {} end
end

local function update_spikes(D, dt, zone)
    local e = D.abyss
    local hero = D.hero

    e.next_spike = e.next_spike - dt
    if e.next_spike <= 0.0 then
        spawn_spike(D)
        e.next_spike = math.max(SPIKE_INT_MIN, SPIKE_INTERVAL - SPIKE_INT_PER_Z * (zone - 1))
    end

    local survivors = {}
    for _, s in ipairs(e.spikes) do
        s.t = s.t + dt
        local keep = true
        if s.phase == "warn" then
            if Art.valid(s.tele) then
                local pulse = 1.4 + 0.7 * math.sin(D.realtime * 16.0)
                material.set(s.tele, "emissive", vec3(1.0 * pulse, 0.20 * pulse, 0.05 * pulse))
            end
            if s.t >= SPIKE_TELEGRAPH then
                s.phase, s.t = "armed", 0.0
                if Art.valid(s.tele) then scene.delete_node(s.tele) end
                s.tele = nil
                -- A row of jagged spikes erupts from the slab.
                -- ARTIST NOTE: spike.png skins each tooth.
                s.spikes = {}
                for i = -2, 2 do
                    s.spikes[#s.spikes + 1] = Art.cube("Abyss_Spike_" .. s.cx .. "_" .. i,
                        vec3(s.cx + i * (SPIKE_HALF_W / 2.5), 0.7, s.cz),
                        vec3(0.5, 1.4, 0.5), { 0.70, 0.72, 0.78 }, D.groups.world, 1.2, TEX .. "spike.png")
                end
            end
        elseif s.phase == "armed" then
            for _, sp in ipairs(s.spikes) do
                if Art.valid(sp) then
                    local g = 0.9 + 0.4 * math.sin(D.realtime * 10.0)
                    material.set(sp, "emissive", vec3(0.7 * g, 0.72 * g, 0.78 * g))
                end
            end
            -- Impale the hero if he is on the slab (once).
            if not hero.dead and not s.hit then
                if math.abs(hero.x - s.cx) <= SPIKE_HALF_W and math.abs(hero.z - s.cz) <= SPIKE_HALF_Z then
                    D:apply_hero_damage(SPIKE_DAMAGE, { flash = "IMPALED!" })
                    s.hit = true
                end
            end
            if s.t >= SPIKE_ARMED then
                close_spike(s)
                keep = false
            end
        end
        if keep then survivors[#survivors + 1] = s end
    end
    e.spikes = survivors
end

-- ---- Mode contract ----------------------------------------------------------

return {
    meta = {
        id        = "abyss",
        name      = "The Abyss",
        tagline   = "the fall that never finds a floor",
        blurb     = "A bottomless chasm of cold and dark.  Boulders, swinging chains and spike platforms rain from above as you plunge through five deepening zones.  Only dim glows break the black.",
        side_hint = "horde",
        accent    = { 1.00, 0.267, 0.00, 0.95 },
        -- Normalized 0..1 sketch: a narrow black shaft, dim ember at the lip,
        -- spectral hazards falling, the hero a pale glint mid-fall.
        minimap = {
            bg = { 0.02, 0.00, 0.06, 1.0 },
            rects = {
                { 0.30, 0.04, 0.40, 0.92, { 0.039, 0.00, 0.125, 1.0 } }, -- the shaft
                { 0.26, 0.04, 0.06, 0.92, { 0.102, 0.102, 0.180, 1.0 } },-- left wall
                { 0.68, 0.04, 0.06, 0.92, { 0.102, 0.102, 0.180, 1.0 } },-- right wall
                { 0.30, 0.04, 0.40, 0.05, { 1.00, 0.267, 0.00, 0.9 } },  -- ember at the lip
                { 0.42, 0.22, 0.10, 0.10, { 0.30, 0.30, 0.38, 1.0 } },   -- a falling boulder
                { 0.54, 0.40, 0.06, 0.06, { 0.40, 0.62, 0.95, 1.0 } },   -- a wraith
                { 0.30, 0.58, 0.40, 0.03, { 0.70, 0.72, 0.78, 1.0 } },   -- a spike row
                { 0.46, 0.74, 0.08, 0.10, { 0.878, 0.878, 0.878, 1.0 } },-- hero glint
            },
        },
    },

    config = {
        id   = "abyss",
        name = "The Abyss",
        theme      = Abyss.theme,
        -- A tall, narrow shaft: small width, large height → the chasm reads vertical.
        arena      = { width = 34, height = 56, pad = 2, ortho_size = 56.0 },
        -- Hero rig is archetype-selectable via ATH_ABYSS_HERO.
        hero       = {
            hp_max = 94.0, dps = 20.0, cleave = 3, attack_range = 1.25, speed = 2.20, kite_speed = 2.80,
            actor = (function()
                local pick = os and os.getenv and os.getenv("ATH_ABYSS_HERO")
                return (pick == "void_drifter") and Abyss.hero_drifter or Abyss.hero_knight
            end)(),
        },
        archetypes = Abyss.archetypes,
        roles      = Abyss.roles,
        spawn      = { interval_start = 0.75, interval_min = 0.30, batch_start = 3, batch_max = 7, cap_start = 30, cap_max = 90, brute_after = 22.0 },
        reserve_start  = 315.0,
        round_seconds  = 14.0,

        -- Wraiths warp in among the gloom; seers hold range; stalkers wall up; the
        -- leviathan surfaces from the deep once the timer is up.
        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 11 == 0) then
                return "drowned_leviathan"
            end
            if D.spawn_counter % 7 == 0 then return "chasm_stalker" end
            if D.spawn_counter % 5 == 0 then return "hollow_seer"   end
            if D.spawn_counter % 2 == 0 then return "abyss_wraith"  end
            return "gloom_mote"
        end,

        hooks = {
            -- on_start: persistent state + permanent props (parented to world so
            -- they survive a round reset).
            on_start = function(D)
                local A = D.arena
                -- Track whether the drifter rig was chosen, for the glide bonus.
                local pick = os and os.getenv and os.getenv("ATH_ABYSS_HERO")
                D.abyss = {
                    boulders = {}, chains = {}, spikes = {},
                    next_boulder = BOULDER_FIRST, next_spike = SPIKE_FIRST,
                    counter = 0, depth = 0.0, descent = DESCENT_START, zone = 1,
                    is_drifter = (pick == "void_drifter"),
                    parallax_root = Art.group("Abyss_Parallax", D.groups.world),
                }

                -- The void backdrop: a vast textured floor-plane (vertical gradient
                -- #000000→#0a0020 with glowing speckles) laid over the chasm floor.
                Art.cube("Abyss_Void_BG", vec3(A.w * 0.5, 0.02, A.h * 0.5),
                    vec3(A.w, 0.02, A.h), { 0.039, 0.0, 0.125 }, D.groups.world, 0.25,
                    TEX .. "void_bg.png")

                -- A dim ember ring at the lip — the last warm light, far above.
                Art.cylinder("Abyss_Lip_Glow", vec3(A.w * 0.5, 0.05, A.pad + 0.5),
                    vec3(A.w * 0.7, 0.06, 1.6), { 1.0, 0.30, 0.08 }, D.groups.world, 1.4)

                build_parallax(D)
            end,

            -- on_reset: NIL-GUARD everything (can fire BEFORE on_start). Clear only
            -- dynamic hazards; the backdrop, lip and parallax survive in `world`.
            on_reset = function(D)
                clear_boulders(D)
                clear_chains(D)
                clear_spikes(D)
                if D.abyss then
                    D.abyss.next_boulder = BOULDER_FIRST
                    D.abyss.next_spike   = SPIKE_FIRST
                    D.abyss.depth        = 0.0
                    D.abyss.descent      = DESCENT_START
                    D.abyss.zone         = 1
                end
            end,

            on_combat_tick = function(D, dt)
                local e = D.abyss
                if not e then return end

                -- THE DESCENT: accelerate toward terminal velocity, accumulate depth.
                e.descent = math.min(DESCENT_TERMINAL, e.descent + DESCENT_ACCEL * dt)
                e.depth   = e.depth + e.descent * dt
                local zone = zone_of(e.depth)
                if zone ~= e.zone then
                    e.zone = zone
                    tint_parallax(D, zone)   -- the chasm darkens at each new zone
                end

                update_parallax(D, dt)
                update_boulders(D, dt, zone)
                update_chains(D, dt, zone)
                update_spikes(D, dt, zone)

                -- HERO GLIDE: a per-frame move multiplier (mode-owned). The Void
                -- Drifter rides updraughts (lighter, more control); the Falling
                -- Knight is heavy plate. 1.0 = neutral.
                D.hero.move_mult = e.is_drifter and 1.15 or 0.95
            end,

            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local e = D.abyss
                local zone  = e and e.zone or 1
                local depth = e and math.floor(e.depth) or 0
                local haz   = e and (#e.boulders + #e.chains + #e.spikes) or 0
                Art.quad(D.hud, "abyss_depth", 24.0, sh - 150.0, 560.0, 58.0,
                    { 0.02, 0.00, 0.06, 0.85 },
                    { border = { 1.00, 0.267, 0.00, 0.9 },
                      label = "Depth " .. tostring(depth) .. "m   ·   Zone " .. ZONES[zone].name .. "   ·   hazards: " .. tostring(haz) })
            end,
        },
    },
}
