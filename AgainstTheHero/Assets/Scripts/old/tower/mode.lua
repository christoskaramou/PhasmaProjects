-- The Tower — a dark, crumbling spire the hero climbs floor by floor, fighting
-- upward toward a Stone Golem waiting at the summit.
--
-- THE TWIST ON THE CONTRACT. Like CATACOMBS this re-stages the shared Duel as a
-- SIDE-SCROLLER, but here the read is VERTICAL: a single tower floor is one wide,
-- shallow room (X is the floor, read left->right), the camera is dropped to a low
-- side-on angle that tracks the hero, and a tall gothic SHAFT backdrop scrolls
-- DOWNWARD behind the action as the hero climbs — so each cleared floor reads as a
-- storey gained. A Y-up gravity layer is laid on top for everything the brief asks:
-- a gravity-arc hero jump, gargoyles that dive-bomb out of the rafters, boulders
-- that roll down the stairwell, floor tiles that collapse away, and cursed
-- chandeliers that fall. The hero still auto-fights and the dead still rush him —
-- we only re-skin the stage and add the bespoke systems the guide allows.
--
-- Signature mechanic — FLOOR_CLEAR + THE HORDE'S DROPS. Eight floors. The Duel's
-- reserve IS each floor's garrison "AP": the horde spends it down, and a floor is
-- CLEARED the instant the garrison is exhausted and the field is empty (exactly the
-- engine's hero-win signal, which we intercept). On a clear the STAIRCASE unlocks,
-- the camera ASCENDS one storey, the horde is granted +1 floor of AP (a bigger,
-- meaner garrison) AND one new hazard is unlocked for it:
--   floor >=1  GARGOYLE DIVE-BOMB — perches in the rafters, then plunges at the hero.
--   floor >=2  ROLLING BOULDER    — tips off the stairwell and tumbles across the floor.
--   floor >=3  COLLAPSING TILES   — a flagstone cracks, then drops away beneath the hero.
--   floor >=4  CURSED CHANDELIER  — a chain snaps; the candle-wheel crashes down as AoE.
-- The eighth floor is the boss: the Stone Golem. Survive it and the climb's natural
-- reserve-drain win fires — the summit is yours. Every visual is an ath_art
-- primitive, self-lit and texture-ready; the seamless stone/window PNGs are wired
-- live (see tools/gen_textures_tower.py).

local Art   = ATH_COMMON.load_script("Scripts/shared/ath_art.lua",            "shared art",       _ENV)
local Tower = ATH_COMMON.load_script("Scripts/modes/tower/characters.lua",    "tower characters", _ENV)

-- ---- Physics + climb tuning ------------------------------------------------
local GRAVITY = 12.0          -- units/s^2 — the mode-owned Y-axis pull (brief)
local JUMP_APEX = 1.7         -- peak height of the hero's leap, in world units
local JUMP_CLEAR = 0.55       -- above this height the hero clears a ground hazard
local ROLL_TIME = 0.40        -- dodge-roll duration

local MAX_FLOOR = 8           -- eight floors, the eighth is the Stone Golem's
local FLOOR_MIN_SECONDS = 4.0 -- min combat on a floor before its stairs can open
local ASCEND_TIME = 1.25      -- camera-rises-one-storey transition on a clear
local STOREY = 7.0            -- world-Y a storey occupies in the backdrop shaft

-- Each floor's garrison "AP" = the reserve the horde gets to spend that floor;
-- it grows by one floor's worth every climb ("Horde gets +1 AP per floor cleared").
local FLOOR_AP_BASE = 90.0
local FLOOR_AP_STEP = 36.0
local function floor_ap(floor) return FLOOR_AP_BASE + (floor - 1) * FLOOR_AP_STEP end

-- ---- Hazard tuning (cadence/damage scale with the floor) -------------------
local GARG_FIRST = 3.0        -- combat-seconds before the first dive-bomb
local GARG_INTERVAL = 5.0     -- base seconds between dives (floor 1)
local GARG_INT_PER_F = 0.4    -- shaved per floor deeper into the climb
local GARG_INT_MIN = 1.8
local GARG_PERCH_Y = 6.0      -- where a gargoyle perches before it plunges
local GARG_WARN = 1.0         -- telegraph (flap + glow) before the dive
local GARG_VY = 11.0          -- initial downward dive speed (gravity adds on top)
local GARG_RADIUS = 1.5
local GARG_DAMAGE = 18.0

local BOULDER_INTERVAL = 6.5  -- base seconds between boulders (floor 2+)
local BOULDER_INT_PER_F = 0.5
local BOULDER_INT_MIN = 2.4
local BOULDER_SPEED = 6.0     -- roll speed across the floor (X units/sec)
local BOULDER_RADIUS = 1.1
local BOULDER_DAMAGE = 22.0
local BOULDER_SHOVE = 3.2     -- how far a hit punches the hero along X

local CHAND_INTERVAL = 7.0    -- base seconds between chandelier falls (floor 4+)
local CHAND_INT_PER_F = 0.5
local CHAND_INT_MIN = 3.0
local CHAND_CEIL_Y = 5.4      -- where a chandelier hangs before the chain snaps
local CHAND_WARN = 1.2        -- sway/telegraph before it drops
local CHAND_VY = 4.0          -- initial drop speed (gravity adds on top)
local CHAND_RADIUS = 1.7
local CHAND_DAMAGE = 24.0

local COLLAPSE_INTERVAL = 5.5 -- base seconds between tile collapses (floor 3+)
local COLLAPSE_INT_PER_F = 0.4
local COLLAPSE_INT_MIN = 2.2
local COLLAPSE_WARN = 1.1     -- crack-glow telegraph before the flagstone drops
local COLLAPSE_GAP = 2.0      -- how long the gap yawns before the tile is re-set
local COLLAPSE_DAMAGE = 20.0
local TILE_W = 3.0            -- floor-tile span along X

local PARALLAX = 0.6          -- backdrop world-shift per hero unit (faked depth)

-- Hazard unlock gate: which drops the horde may use on a given floor (brief).
local function gargoyles_on(f) return f >= 1 end
local function boulders_on(f)  return f >= 2 end
local function collapse_on(f)  return f >= 3 end
local function chandeliers_on(f) return f >= 4 end

-- ---------------------------------------------------------------------------
-- Stage dressing (built once in on_start) — floor, shaft backdrop, torches.
-- ---------------------------------------------------------------------------

-- A flickering wall sconce: an iron bracket + an emissive flame core we pulse each
-- tick. torch_sconce.png is the artist drop-in; the live flicker is procedural.
local function build_torch(D, x, y, z)
    local g = D.groups.world
    Art.cube("Torch_Haft_" .. x, vec3(x, y - 0.3, z), vec3(0.08, 0.6, 0.08), Tower.palette.stone, g, 0.4)
    Art.cube("Torch_Bracket_" .. x, vec3(x, y, z), vec3(0.20, 0.1, 0.20), Tower.palette.stone, g, 0.4)
    local flame = Art.sphere("Torch_Flame_" .. x, vec3(x, y + 0.30, z), vec3(0.22, 0.40, 0.22), Tower.palette.fire, g, 1.8)
    -- texture = Tower.tex.torch  -- sconce sprite drop-in for the flame quad
    return { node = flame, x = x, base_y = y + 0.30, seed = x * 1.7 }
end

-- ---- Collapsing floor tiles (the "falling sections" the brief asks for) -----
-- The whole floor is a row of flagstone tiles. A collapse telegraphs with a crack
-- glow, then the tile DETACHES and free-falls under GRAVITY, leaving a gap; the
-- hero is hurt if he is standing over it and not airborne. The tile is re-set after
-- a beat so the floor is whole again for the next round.

local function build_tiles(D)
    local A = D.arena
    local g = D.groups.world
    local z = A.h * 0.5 - 0.5
    local tiles = {}
    local i = 0
    for tx = A.pad + TILE_W * 0.5, A.w - A.pad - TILE_W * 0.5, TILE_W do
        i = i + 1
        local node = Art.cube("Tile_" .. i, vec3(tx, -0.05, z), vec3(TILE_W - 0.12, 0.18, A.h - A.pad * 2 - 0.4),
            Tower.palette.stone, g, 0.7, Tower.tex.stone)
        -- A crack overlay decal that lights up during the telegraph (texture-ready).
        local crack = Art.cube("Tile_Crack_" .. i, vec3(tx, 0.06, z), vec3(TILE_W - 0.3, 0.04, A.h - A.pad * 2 - 0.8),
            Tower.palette.fire, g, 0.0, Tower.tex.crack)
        tiles[#tiles + 1] = {
            x = tx, z = z, y = -0.05, node = node, crack = crack,
            phase = "solid", t = 0.0, hit = false,
        }
    end
    return tiles
end

local function update_collapse(D, dt)
    local T = D.tower
    local hero = D.hero
    local hero_air = T.jump.active and T.jump.y > JUMP_CLEAR

    -- Schedule a new collapse (only once the hazard is unlocked for this floor).
    if collapse_on(T.floor) then
        T.next_collapse = T.next_collapse - dt
        if T.next_collapse <= 0.0 then
            T.next_collapse = math.max(COLLAPSE_INT_MIN, COLLAPSE_INTERVAL - COLLAPSE_INT_PER_F * (T.floor - 1))
            -- Prefer a tile near the hero so the collapse actually threatens him.
            local best, bd
            for _, ti in ipairs(T.tiles) do
                if ti.phase == "solid" then
                    local dx = ti.x - hero.x
                    local d = dx * dx
                    if not best or d < bd then best, bd = ti, d end
                end
            end
            if best then best.phase = "warn"; best.t = 0.0; best.hit = false end
        end
    end

    for _, ti in ipairs(T.tiles) do
        if ti.phase == "warn" then
            ti.t = ti.t + dt
            local p = math.min(1.0, ti.t / COLLAPSE_WARN)
            local pulse = 0.4 + 1.4 * (0.5 + 0.5 * math.sin(D.realtime * 16.0)) * p
            if Art.valid(ti.crack) then material.set(ti.crack, "emissive", vec3(1.0 * pulse, 0.27 * pulse, 0.0)) end
            -- Cue the hero to leap a flagstone giving way under him.
            if ti.t >= COLLAPSE_WARN * 0.5 and not T.jump.active and not hero.dead then
                if math.abs(hero.x - ti.x) <= TILE_W * 0.5 then T.jump.active = true; T.jump.t = 0.0 end
            end
            if ti.t >= COLLAPSE_WARN then
                ti.phase = "falling"; ti.t = 0.0; ti.vy = 0.0
                -- Gore-check the moment the floor drops out.
                if not hero.dead and not hero_air and math.abs(hero.x - ti.x) <= TILE_W * 0.5 then
                    D:apply_hero_damage(COLLAPSE_DAMAGE, { flash = "THE FLOOR GIVES WAY!" })
                    ti.hit = true
                end
                Art.burst("ath_tower_collapse_" .. ti.x, vec3(ti.x, 0.2, ti.z),
                    { preset = "enemy_take", count = 16, life_max = 0.4, spawn_radius = TILE_W * 0.4, noise_strength = 4.0, size_max = 0.22 })
            end
        elseif ti.phase == "falling" then
            ti.t = ti.t + dt
            ti.vy = ti.vy - GRAVITY * dt
            ti.y = ti.y + ti.vy * dt
            if Art.valid(ti.node) then ti.node:set_position(vec3(ti.x, ti.y, ti.z)) end
            if Art.valid(ti.crack) then material.set(ti.crack, "emissive", vec3(0.0, 0.0, 0.0)) end
            if ti.t >= COLLAPSE_GAP then ti.phase = "reset"; ti.t = 0.0 end
        elseif ti.phase == "reset" then
            -- Re-seat the flagstone: rise back into place so the floor is whole again.
            ti.t = ti.t + dt
            local p = math.min(1.0, ti.t / 0.4)
            ti.y = -2.4 + (2.4 - 0.05) * p
            if Art.valid(ti.node) then ti.node:set_position(vec3(ti.x, ti.y, ti.z)) end
            if ti.t >= 0.4 then ti.phase = "solid"; ti.y = -0.05; if Art.valid(ti.node) then ti.node:set_position(vec3(ti.x, -0.05, ti.z)) end end
        end
    end
end

-- ---- Gargoyle dive-bombs ----------------------------------------------------

local function spawn_gargoyle(D)
    local A = D.arena
    local T = D.tower
    local g = D.groups.world
    -- Perch somewhere in the rafters above the playable floor.
    local x = math.random() * (A.w - A.pad * 2 - 4) + A.pad + 2
    local z = A.h * 0.5 - 0.5
    T.garg_id = T.garg_id + 1
    local body = Art.cube("Garg_" .. T.garg_id, vec3(x, GARG_PERCH_Y, z), vec3(0.5, 0.5, 0.4), Tower.palette.stone, g, 0.8, Tower.tex.gargoyle)
    local wl = Art.cube("GargW_L_" .. T.garg_id, vec3(x - 0.36, GARG_PERCH_Y + 0.1, z), vec3(0.34, 0.05, 0.24), Tower.palette.plum, g, 0.7)
    local wr = Art.cube("GargW_R_" .. T.garg_id, vec3(x + 0.36, GARG_PERCH_Y + 0.1, z), vec3(0.34, 0.05, 0.24), Tower.palette.plum, g, 0.7)
    local eye = Art.sphere("GargE_" .. T.garg_id, vec3(x, GARG_PERCH_Y, z + 0.22), vec3(0.12, 0.08, 0.06), Tower.palette.fire, g, 1.9)
    T.gargoyles[#T.gargoyles + 1] = {
        x = x, y = GARG_PERCH_Y, z = z, vy = 0.0, phase = "warn", t = 0.0, hit = false,
        body = body, wl = wl, wr = wr, eye = eye,
    }
end

local function clear_gargoyle(gv)
    for _, k in ipairs({ "body", "wl", "wr", "eye" }) do
        if Art.valid(gv[k]) then scene.delete_node(gv[k]) end
    end
end

local function set_gargoyle_pos(gv)
    if Art.valid(gv.body) then gv.body:set_position(vec3(gv.x, gv.y, gv.z)) end
    if Art.valid(gv.wl) then gv.wl:set_position(vec3(gv.x - 0.36, gv.y + 0.1, gv.z)) end
    if Art.valid(gv.wr) then gv.wr:set_position(vec3(gv.x + 0.36, gv.y + 0.1, gv.z)) end
    if Art.valid(gv.eye) then gv.eye:set_position(vec3(gv.x, gv.y, gv.z + 0.22)) end
end

local function update_gargoyles(D, dt)
    local T = D.tower
    local hero = D.hero
    local hero_air = T.jump.active and T.jump.y > JUMP_CLEAR

    if gargoyles_on(T.floor) then
        T.next_garg = T.next_garg - dt
        if T.next_garg <= 0.0 then
            T.next_garg = math.max(GARG_INT_MIN, GARG_INTERVAL - GARG_INT_PER_F * (T.floor - 1))
            spawn_gargoyle(D)
        end
    end

    local damage = GARG_DAMAGE + 2.0 * (T.floor - 1)
    local survivors = {}
    for _, gv in ipairs(T.gargoyles) do
        local keep = true
        if gv.phase == "warn" then
            gv.t = gv.t + dt
            -- Flap + glare while it locks onto the hero's lane.
            local flap = 0.10 * math.sin(D.realtime * 22.0)
            if Art.valid(gv.wl) then gv.wl:set_rotation(vec3(0.0, 0.0, 30.0 + flap * 180.0)) end
            if Art.valid(gv.wr) then gv.wr:set_rotation(vec3(0.0, 0.0, -30.0 - flap * 180.0)) end
            if Art.valid(gv.eye) then
                local pulse = 1.4 + 0.6 * math.sin(D.realtime * 16.0)
                material.set(gv.eye, "emissive", vec3(1.0 * pulse, 0.27 * pulse, 0.0))
            end
            gv.target_x = hero.x          -- aim at where the hero is as it commits
            if gv.t >= GARG_WARN then gv.phase = "dive"; gv.t = 0.0; gv.vy = -GARG_VY end
        elseif gv.phase == "dive" then
            gv.t = gv.t + dt
            gv.vy = gv.vy - GRAVITY * dt
            gv.y = gv.y + gv.vy * dt
            -- Track toward the locked X as it falls, for a real dive-bomb arc.
            gv.x = gv.x + (gv.target_x - gv.x) * math.min(1.0, dt * 3.0)
            set_gargoyle_pos(gv)
            if gv.y <= 0.45 then
                -- Impact: AoE crunch on the floor.
                Art.burst("ath_tower_garg_" .. gv.x, vec3(gv.x, 0.5, gv.z),
                    { preset = "hero_take", count = 20, life_max = 0.4, spawn_radius = GARG_RADIUS * 0.6, noise_strength = 5.0, size_max = 0.26 })
                if not hero.dead and not hero_air then
                    local dx = hero.x - gv.x
                    if dx * dx <= GARG_RADIUS * GARG_RADIUS then
                        D:apply_hero_damage(damage, { flash = "GARGOYLE STRIKE!" })
                    end
                end
                clear_gargoyle(gv); keep = false
            end
        end
        if keep then survivors[#survivors + 1] = gv end
    end
    T.gargoyles = survivors
end

-- ---- Rolling boulders (tumble down the stairwell) ---------------------------

local function update_boulders(D, dt)
    local A = D.arena
    local T = D.tower
    local hero = D.hero
    local hero_air = T.jump.active and T.jump.y > JUMP_CLEAR

    if boulders_on(T.floor) then
        T.next_boulder = T.next_boulder - dt
        if T.next_boulder <= 0.0 then
            T.next_boulder = math.max(BOULDER_INT_MIN, BOULDER_INTERVAL - BOULDER_INT_PER_F * (T.floor - 1))
            -- Tips off the stairwell at the far (right) end and rolls left.
            T.boulder_id = T.boulder_id + 1
            local z = A.h * 0.5 - 0.5
            local node = Art.sphere("Boulder_" .. T.boulder_id, vec3(A.w - A.pad - 1.0, 0.7, z),
                vec3(BOULDER_RADIUS * 1.5, BOULDER_RADIUS * 1.5, BOULDER_RADIUS * 1.5), Tower.palette.plum, D.groups.world, 0.7, Tower.tex.stone)
            T.boulders[#T.boulders + 1] = { x = A.w - A.pad - 1.0, z = z, node = node, spin = 0.0, hit = false }
        end
    end

    local damage = BOULDER_DAMAGE + 3.0 * (T.floor - 1)
    local survivors = {}
    for _, b in ipairs(T.boulders) do
        b.x = b.x - BOULDER_SPEED * dt
        b.spin = b.spin - BOULDER_SPEED * dt * 90.0   -- tumble as it rolls
        if Art.valid(b.node) then
            b.node:set_position(vec3(b.x, 0.7, b.z))
            b.node:set_rotation(vec3(0.0, 0.0, b.spin))
        end
        -- Crush + shove the hero on contact (unless he leapt the boulder).
        if not hero.dead and not b.hit and not hero_air then
            local dx = hero.x - b.x
            if dx * dx <= (BOULDER_RADIUS + 0.5) * (BOULDER_RADIUS + 0.5) then
                D:apply_hero_damage(damage, { flash = "BOULDER!" })
                hero.x = hero.x - BOULDER_SHOVE   -- punched back down the floor (engine re-clamps)
                b.hit = true
            end
        end
        if b.x <= A.pad + 0.5 then
            if Art.valid(b.node) then scene.delete_node(b.node) end
        else
            survivors[#survivors + 1] = b
        end
    end
    T.boulders = survivors
end

-- ---- Cursed chandeliers (the chain snaps; they fall) ------------------------

local function update_chandeliers(D, dt)
    local A = D.arena
    local T = D.tower
    local hero = D.hero
    local hero_air = T.jump.active and T.jump.y > JUMP_CLEAR

    if chandeliers_on(T.floor) then
        T.next_chand = T.next_chand - dt
        if T.next_chand <= 0.0 then
            T.next_chand = math.max(CHAND_INT_MIN, CHAND_INTERVAL - CHAND_INT_PER_F * (T.floor - 1))
            T.chand_id = T.chand_id + 1
            local x = math.max(A.pad + 2, math.min(A.w - A.pad - 2, hero.x + (math.random() * 4 - 2)))
            local z = A.h * 0.5 - 0.5
            local g = D.groups.world
            local ring = Art.cylinder("Chand_" .. T.chand_id, vec3(x, CHAND_CEIL_Y, z), vec3(1.0, 0.12, 1.0), Tower.palette.steel, g, 0.8, Tower.tex.chandelier)
            local glow = Art.sphere("ChandG_" .. T.chand_id, vec3(x, CHAND_CEIL_Y + 0.1, z), vec3(0.3, 0.3, 0.3), Tower.palette.gold, g, 1.6)
            local chain = Art.cube("ChandC_" .. T.chand_id, vec3(x, CHAND_CEIL_Y + 0.7, z), vec3(0.05, 1.2, 0.05), Tower.palette.stone, g, 0.4)
            T.chandeliers[#T.chandeliers + 1] = {
                x = x, y = CHAND_CEIL_Y, z = z, vy = 0.0, phase = "warn", t = 0.0,
                ring = ring, glow = glow, chain = chain,
            }
        end
    end

    local damage = CHAND_DAMAGE + 2.0 * (T.floor - 1)
    local survivors = {}
    for _, ch in ipairs(T.chandeliers) do
        local keep = true
        if ch.phase == "warn" then
            ch.t = ch.t + dt
            -- Sway on the failing chain to telegraph the drop.
            local sway = 0.18 * math.sin(D.realtime * 6.0)
            if Art.valid(ch.ring) then ch.ring:set_position(vec3(ch.x + sway, ch.y, ch.z)) end
            if Art.valid(ch.glow) then
                local pulse = 1.2 + 0.5 * math.sin(D.realtime * 14.0)
                material.set(ch.glow, "emissive", vec3(1.0 * pulse, 0.84 * pulse, 0.0))
                ch.glow:set_position(vec3(ch.x + sway, ch.y + 0.1, ch.z))
            end
            -- Cue the hero clear of where it will land.
            if ch.t >= CHAND_WARN * 0.5 and not T.jump.active and not hero.dead then
                if math.abs(hero.x - ch.x) <= CHAND_RADIUS then T.jump.active = true; T.jump.t = 0.0 end
            end
            if ch.t >= CHAND_WARN then
                ch.phase = "fall"; ch.t = 0.0; ch.vy = -CHAND_VY
                if Art.valid(ch.chain) then scene.delete_node(ch.chain); ch.chain = nil end
            end
        elseif ch.phase == "fall" then
            ch.vy = ch.vy - GRAVITY * dt
            ch.y = ch.y + ch.vy * dt
            if Art.valid(ch.ring) then ch.ring:set_position(vec3(ch.x, ch.y, ch.z)) end
            if Art.valid(ch.glow) then ch.glow:set_position(vec3(ch.x, ch.y + 0.1, ch.z)) end
            if ch.y <= 0.3 then
                Art.burst("ath_tower_chand_" .. ch.x, vec3(ch.x, 0.4, ch.z),
                    { preset = "hero_take", count = 24, life_max = 0.45, spawn_radius = CHAND_RADIUS * 0.7, noise_strength = 5.0, size_max = 0.3 })
                if not hero.dead and not hero_air then
                    local dx = hero.x - ch.x
                    if dx * dx <= CHAND_RADIUS * CHAND_RADIUS then
                        D:apply_hero_damage(damage, { flash = "CHANDELIER FALL!" })
                    end
                end
                if Art.valid(ch.ring) then scene.delete_node(ch.ring) end
                if Art.valid(ch.glow) then scene.delete_node(ch.glow) end
                keep = false
            end
        end
        if keep then survivors[#survivors + 1] = ch end
    end
    T.chandeliers = survivors
end

local function clear_hazards(D)
    local T = D.tower
    if not T then return end
    for _, gv in ipairs(T.gargoyles) do clear_gargoyle(gv) end
    for _, b in ipairs(T.boulders) do if Art.valid(b.node) then scene.delete_node(b.node) end end
    for _, ch in ipairs(T.chandeliers) do
        for _, k in ipairs({ "ring", "glow", "chain" }) do if Art.valid(ch[k]) then scene.delete_node(ch[k]) end end
    end
    T.gargoyles, T.boulders, T.chandeliers = {}, {}, {}
end

-- ---- FLOOR_CLEAR — the climb's spine -----------------------------------------
-- A floor is cleared when its garrison (the reserve) is spent and the field is
-- empty. We detect that one tick BEFORE the engine's hero-win check would fire and,
-- for floors 1..7, ADVANCE instead: refill the reserve with a bigger garrison
-- (+1 floor of AP for the horde), unlock the next hazard, and trigger the ascend.
-- On floor 8 we let the engine's natural win stand — the summit is taken.

local function open_stairs(D)
    local T = D.tower
    if Art.valid(T.stairs_glow) then material.set(T.stairs_glow, "emissive", vec3(1.0, 0.5, 0.0)) end
    T.stairs_open = true
end

local function advance_floor(D)
    local T = D.tower
    T.floor = T.floor + 1
    T.floor_time = 0.0
    T.stairs_open = false
    if Art.valid(T.stairs_glow) then material.set(T.stairs_glow, "emissive", vec3(0.16, 0.10, 0.10)) end
    -- The horde is granted the next floor's (bigger) garrison — its +1 AP per floor.
    D.reserve = floor_ap(T.floor)
    -- And its spawn cadence escalates a notch, so each storey bites harder.
    D.spawn_mods.cap_add = (D.spawn_mods.cap_add or 0) + 6
    D.spawn_mods.batch_add = (D.spawn_mods.batch_add or 0) + 1
    -- The Stone Golem garrisons the summit: drop it in the instant we arrive.
    if T.floor >= MAX_FLOOR then
        local A = D.arena
        D:spawn_one({ x = A.w - A.pad - 3, y = A.h * 0.5 - 0.5 }, "stone_golem", true)
    end
    -- Begin the camera ascent + backdrop scroll.
    T.ascending = true
    T.ascend_t = 0.0
    D:set_flash(string.format("FLOOR %d — CLIMB!", T.floor))
end

local function update_floor_clear(D, dt)
    local T = D.tower
    T.floor_time = T.floor_time + dt
    if T.ascending then
        T.ascend_t = T.ascend_t + dt
        if T.ascend_t >= ASCEND_TIME then T.ascending = false end
    end
    -- The garrison is exhausted and the floor is empty -> cleared.
    if D.state == "combat" and not T.ascending and T.floor < MAX_FLOOR
        and T.floor_time >= FLOOR_MIN_SECONDS and D.reserve < 1.0 and D:count_alive() == 0 then
        if not T.stairs_open then open_stairs(D) end
        advance_floor(D)   -- intercept the would-be win and climb on
    end
end

-- ---- Hero Y-axis physics: gravity-arc jump + dodge-roll ---------------------

local function update_hero_physics(D, dt)
    local hero = D.hero
    local T = D.tower
    local j = T.jump
    if hero.dead then j.active = false; return end

    -- Gravity-arc jump: launch velocity solved from the desired apex (v=sqrt(2gh)).
    if j.active then
        j.t = j.t + dt
        local v0 = math.sqrt(2.0 * GRAVITY * JUMP_APEX)
        j.y = v0 * j.t - 0.5 * GRAVITY * j.t * j.t
        if j.y <= 0.0 and j.t > 0.05 then j.active = false; j.y = 0.0 end
    end

    -- Dodge-roll: a quick grounded tuck when a foe crowds in (cosmetic evasion).
    local r = T.roll
    r.cd = math.max(0.0, r.cd - dt)
    if not r.active and not j.active and r.cd <= 0.0 then
        local near, nd = D:nearest_creep(hero)
        if near and nd and nd < 1.8 then r.active = true; r.t = 0.0; r.dir = (near.x >= hero.x) and -1.0 or 1.0 end
    end
    if r.active then
        r.t = r.t + dt
        if r.t >= ROLL_TIME then r.active = false; r.cd = 2.2 end
    end

    -- Apply the Y lift + roll transform AFTER update_hero wrote this frame (on_combat
    -- _tick runs after update_hero, so this is the final say on the hero transform).
    if Art.valid(hero.root) then
        local roll_pitch = r.active and (360.0 * (r.t / ROLL_TIME)) or 0.0
        hero.root:set_position(vec3(hero.x, j.y, hero.z))
        hero.root:set_rotation(vec3(roll_pitch, math.deg(hero.facing), 0.0))
        local ws = hero.world_scale or 1.0
        if j.active then
            local sq = 1.0 - 0.12 * math.sin(math.min(1.0, j.y / JUMP_APEX) * math.pi)
            hero.root:set_scale(vec3(ws, ws * sq, ws))
        elseif not r.active then
            hero.root:set_scale(vec3(ws, ws, ws))
        end
    end
end

-- ---- Camera: a side-on rig that tracks the hero, rising one storey per floor --

local function update_camera(D)
    local A = D.arena
    local T = D.tower
    -- Keep the framing inside the floor's ends so we never pan off into the void.
    local half = A.ortho_size * 0.5
    local cx = math.max(A.pad + half * 0.4, math.min(A.w - A.pad - half * 0.4, D.hero.x))
    -- A brief upward bob during the ascend transition sells the climb.
    local lift = 0.0
    if T.ascending then
        local p = T.ascend_t / ASCEND_TIME
        lift = math.sin(p * math.pi) * 2.2
    end
    Art.setup_iso_camera({ x = cx, z = A.h * 0.5 - 0.5 },
        { ortho_size = A.ortho_size, offset = { x = A.cam_offset.x, y = A.cam_offset.y + lift, z = A.cam_offset.z } })
    -- The gothic SHAFT backdrop scrolls DOWN as floors are gained (treadmill climb),
    -- plus a parallax shove so distant arches drift slower than the foreground. The
    -- climb height grows one storey per floor and animates over the ascend window;
    -- we take it modulo STOREY so the identical panels wrap seamlessly.
    local climb = (T.floor - 1) * STOREY
    if T.ascending then climb = climb - (1.0 - T.ascend_t / ASCEND_TIME) * STOREY end
    local offset = climb % STOREY
    local px = PARALLAX * cx
    for _, p in ipairs(T.shaft_panels) do
        if Art.valid(p.node) then p.node:set_position(vec3(px, p.base_y - offset, p.z)) end
    end
end

-- ---- Hero class selection (two classes; brief) -----------------------------

local function pick_hero()
    local class = "climber"
    if ATH_COMMON and ATH_COMMON.getenv then
        local v = ATH_COMMON.getenv("ATH_TOWER_CLASS")
        if type(v) == "string" and Tower.heroes[v:lower()] then class = v:lower() end
    end
    return class, Tower.heroes[class]
end

local CLASS, HERO = pick_hero()

-- ---------------------------------------------------------------------------
-- Mode contract
-- ---------------------------------------------------------------------------

return {
    meta = {
        id = "tower",
        name = "The Tower",
        tagline = "the crumbling spire you climb floor by floor",
        blurb = "A 2D vertical climb up a dark, crumbling tower. Clear each floor to unlock the stairs; the horde drops gargoyles, boulders and falling chandeliers from above. A Stone Golem waits at the summit.",
        side_hint = "horde",
        accent = { 1.0, 0.267, 0.0, 0.95 },
        -- A side-on sketch of the shaft, floors stacked bottom->top (0..1 rects).
        minimap = {
            bg = { 0.051, 0.051, 0.051, 1.0 },
            rects = {
                { 0.30, 0.04, 0.40, 0.92, { 0.165, 0.102, 0.165, 1.0 } }, -- shaft
                { 0.30, 0.78, 0.40, 0.04, { 0.29, 0.227, 0.29, 1.0 } },   -- floor 1
                { 0.30, 0.60, 0.40, 0.04, { 0.29, 0.227, 0.29, 1.0 } },   -- floor 3
                { 0.30, 0.42, 0.40, 0.04, { 0.29, 0.227, 0.29, 1.0 } },   -- floor 5
                { 0.30, 0.24, 0.40, 0.04, { 0.29, 0.227, 0.29, 1.0 } },   -- floor 7
                { 0.45, 0.82, 0.05, 0.10, { 0.541, 0.541, 0.667, 1.0 } }, -- hero (bottom)
                { 0.44, 0.10, 0.12, 0.12, { 1.0, 0.267, 0.0, 1.0 } },     -- golem (summit)
                { 0.62, 0.66, 0.05, 0.05, { 1.0, 0.843, 0.0, 1.0 } },     -- chandelier
                { 0.36, 0.48, 0.05, 0.05, { 0.29, 0.227, 0.29, 1.0 } },   -- boulder
                { 0.22, 0.30, 0.02, 0.10, { 1.0, 0.267, 0.0, 1.0 } },     -- torch
                { 0.76, 0.30, 0.02, 0.10, { 1.0, 0.267, 0.0, 1.0 } },     -- torch
            },
        },
    },

    config = {
        id = "tower",
        name = "The Tower",
        theme = Tower.theme,
        -- One floor of the tower is a wide, shallow ROOM (read left->right), with a
        -- low side-on camera that tracks the hero (update_camera, each tick). The
        -- stairwell is at the far-right end; boulders tip in from there.
        arena = {
            width = 48, height = 14, pad = 2, ortho_size = 21.0,
            cam_offset = { x = 0.0, y = 9.0, z = -28.0 },    -- side elevation, not iso
            hero_start = { x = 5, y = 7 },
            -- The dead pour in from BOTH ends of the floor and close on the hero.
            spawns = {
                { x = 6, y = 7 }, { x = 42, y = 7 }, { x = 44, y = 6 },
                { x = 44, y = 8 }, { x = 8, y = 6 }, { x = 8, y = 8 },
            },
        },
        hero = {
            hp_max = HERO.stats.hp_max, dps = HERO.stats.dps, cleave = HERO.stats.cleave,
            attack_range = HERO.stats.attack_range, speed = HERO.stats.speed, kite_speed = HERO.stats.kite_speed,
            actor = HERO.actor,
        },
        archetypes = Tower.archetypes,
        roles = Tower.roles,
        spawn = { interval_start = 0.8, interval_min = 0.35, batch_start = 3, batch_max = 7, cap_start = 26, cap_max = 78, brute_after = 18.0 },
        reserve_start = floor_ap(1),
        round_seconds = 14.0,

        -- A gargoyle-heavy mix with periodic arbalests and cursed-knight guardians;
        -- the floor-8 boss is dropped in directly by advance_floor, but bias the
        -- auto-spawner to favour the golem there too if the reserve allows.
        auto_mix = function(D)
            local floor = (D.tower and D.tower.floor) or 1
            if floor >= MAX_FLOOR and (D.spawn_counter % 9 == 0) then return "stone_golem" end
            if D.spawn_counter % 9 == 0 then return "chandelier_trap" end
            if D.spawn_counter % 6 == 0 then return "cursed_knight" end
            if D.spawn_counter % 4 == 0 then return "hollow_arbalest" end
            return "gargoyle"
        end,

        hooks = {
            on_start = function(D)
                local A = D.arena
                local g = D.groups.world
                local far_z = A.h - A.pad + 1.4

                -- A very dark gothic SHAFT backdrop: a STACK of identical pointed-arch
                -- window panels, spaced exactly one storey apart. update_camera scrolls
                -- them within a single storey (modulo) so the climb reads as continuous
                -- vertical motion while the visible band is always covered — and because
                -- every panel is identical and the wrap is exactly one storey, the loop is
                -- seamless. (One stretched cube can't tile; the engine maps UVs 0..1.)
                -- Lit by the stage light; only a whisper of emissive so the gloom holds.
                D.tower = D.tower or {}
                D.tower.shaft_panels = {}
                for s = -1, MAX_FLOOR + 2 do
                    local node = Art.cube("Shaft_Panel_" .. s, vec3(PARALLAX * A.w * 0.5, s * STOREY, far_z),
                        vec3(A.w * 1.4, STOREY + 0.1, 0.2), { 0.55, 0.5, 0.6 }, g, 0.18, Tower.tex.window)
                    D.tower.shaft_panels[#D.tower.shaft_panels + 1] = { node = node, base_y = s * STOREY, z = far_z }
                end

                -- A textured stone back wall, panelled so the seamless tile reads.
                local panel = 4.0
                for px = A.pad, A.w - A.pad, panel do
                    Art.cube("BackWall_" .. math.floor(px), vec3(px + panel * 0.5, 2.6, A.h - A.pad - 0.2),
                        vec3(panel, 5.2, 0.4), Tower.palette.stone, g, 0.5, Tower.tex.stone)
                end

                -- Torch line along the back wall (flicker driven in on_combat_tick).
                D.tower.torches = {}
                for tx = A.pad + 4, A.w - A.pad - 2, 9 do
                    D.tower.torches[#D.tower.torches + 1] = build_torch(D, tx, 3.0, A.h - A.pad - 0.5)
                end

                -- The STAIRCASE at the far-right end — the way up. It stays dim until a
                -- floor is cleared, then glows to mark the climb on.
                local ex = A.w - A.pad - 1.5
                local z = A.h * 0.5 - 0.5
                for s = 1, 5 do
                    Art.cube("Stair_" .. s, vec3(ex + 0.2, 0.1 + (s - 1) * 0.28, z - 1.4 + (s - 1) * 0.5),
                        vec3(1.6, 0.24, 0.7), Tower.palette.stone, g, 0.5, Tower.tex.stone)
                end
                Art.cube("Stair_Frame_L", vec3(ex - 0.8, 1.4, z), vec3(0.4, 2.8, 0.5), Tower.palette.stone, g, 0.6)
                Art.cube("Stair_Frame_R", vec3(ex + 0.9, 1.4, z), vec3(0.4, 2.8, 0.5), Tower.palette.stone, g, 0.6)
                Art.cube("Stair_Arch", vec3(ex, 2.9, z), vec3(2.4, 0.5, 0.5), Tower.palette.stone, g, 0.6)
                D.tower.stairs_glow = Art.cube("Stair_Glow", vec3(ex, 1.4, z), vec3(1.4, 2.6, 0.12), Tower.palette.fire, g, 0.16)

                -- The collapsing flagstone floor + the live mechanic state.
                D.tower.floor = 1
                D.tower.floor_time = 0.0
                D.tower.stairs_open = false
                D.tower.ascending = false
                D.tower.ascend_t = 0.0
                D.tower.gargoyles, D.tower.boulders, D.tower.chandeliers = {}, {}, {}
                D.tower.garg_id, D.tower.boulder_id, D.tower.chand_id = 0, 0, 0
                D.tower.next_garg = GARG_FIRST
                D.tower.next_boulder = BOULDER_INTERVAL
                D.tower.next_chand = CHAND_INTERVAL
                D.tower.next_collapse = COLLAPSE_INTERVAL
                D.tower.jump = { active = false, t = 0.0, y = 0.0 }
                D.tower.roll = { active = false, t = 0.0, cd = 0.0, dir = 1.0 }
                D.tower.class = CLASS
                D.tower.tiles = build_tiles(D)

                D.reserve = floor_ap(1)
                update_camera(D)
            end,

            on_reset = function(D)
                clear_hazards(D)
                if D.tower then
                    D.tower.floor = 1
                    D.tower.floor_time = 0.0
                    D.tower.stairs_open = false
                    D.tower.ascending = false
                    D.tower.ascend_t = 0.0
                    D.tower.next_garg = GARG_FIRST
                    D.tower.next_boulder = BOULDER_INTERVAL
                    D.tower.next_chand = CHAND_INTERVAL
                    D.tower.next_collapse = COLLAPSE_INTERVAL
                    D.tower.jump = { active = false, t = 0.0, y = 0.0 }
                    D.tower.roll = { active = false, t = 0.0, cd = 0.0, dir = 1.0 }
                    -- Re-seat any tiles caught mid-collapse.
                    for _, ti in ipairs(D.tower.tiles or {}) do
                        ti.phase = "solid"; ti.t = 0.0; ti.y = -0.05
                        if Art.valid(ti.node) then ti.node:set_position(vec3(ti.x, -0.05, ti.z)) end
                        if Art.valid(ti.crack) then material.set(ti.crack, "emissive", vec3(0.0, 0.0, 0.0)) end
                    end
                    if Art.valid(D.tower.stairs_glow) then material.set(D.tower.stairs_glow, "emissive", vec3(0.16, 0.10, 0.10)) end
                end
                D.reserve = floor_ap(1)
            end,

            on_combat_tick = function(D, dt)
                update_gargoyles(D, dt)
                update_boulders(D, dt)
                update_chandeliers(D, dt)
                update_collapse(D, dt)
                update_floor_clear(D, dt)
                update_hero_physics(D, dt)
                update_camera(D)
                -- Torch flicker: emissive wobble + a touch of random guttering.
                for _, t in ipairs(D.tower.torches) do
                    if Art.valid(t.node) then
                        local f = 1.3 + 0.5 * math.sin(D.realtime * 11.0 + t.seed) + 0.2 * math.sin(D.realtime * 27.0 + t.seed * 2.0)
                        material.set(t.node, "emissive", vec3(1.0 * f, 0.27 * f, 0.0))
                    end
                end
                -- Open stairs beckon with a slow pulse.
                if D.tower.stairs_open and Art.valid(D.tower.stairs_glow) then
                    local pf = 1.0 + 0.6 * (0.5 + 0.5 * math.sin(D.realtime * 3.0))
                    material.set(D.tower.stairs_glow, "emissive", vec3(1.0 * pf, 0.5 * pf, 0.0))
                end
            end,

            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local T = D.tower
                local hazards = {}
                if gargoyles_on(T.floor) then hazards[#hazards + 1] = "Gargoyles" end
                if boulders_on(T.floor) then hazards[#hazards + 1] = "Boulders" end
                if collapse_on(T.floor) then hazards[#hazards + 1] = "Collapse" end
                if chandeliers_on(T.floor) then hazards[#hazards + 1] = "Chandeliers" end
                local hz = (#hazards > 0) and table.concat(hazards, ", ") or "-"
                Art.quad(D.hud, "tower_panel", 24.0, sh - 150.0, 600.0, 58.0, { 0.051, 0.051, 0.06, 0.9 },
                    { border = { 1.0, 0.267, 0.0, 0.9 },
                      label = string.format("CLASS: %s    FLOOR %d / %d    Horde AP +%d    Hazards: %s",
                        T.class:upper(), T.floor, MAX_FLOOR, T.floor - 1, hz) })
            end,
        },
    },
}
