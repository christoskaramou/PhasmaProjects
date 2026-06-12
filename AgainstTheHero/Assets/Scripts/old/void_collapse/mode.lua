-- VOID COLLAPSE — a 2D top-down arena that EATS ITSELF, in the Dark-Souls key.
--
-- Like THE PIT, this is its own little GAME: it does NOT run on the shared 3D Duel
-- engine. It is a self-contained, real-time, top-down arena drawn entirely on the
-- runtime_ui canvas (the same quad/image API the menu uses), driven by its own
-- update loop — mirroring the standalone pattern of modes/pit and modes/horde.
--
-- THE SIGNATURE MECHANIC — THE COLLAPSE. A circular SAFE ZONE shrinks from 40 down
-- to 5 world units over ~four minutes. Everything outside the closing ring is the
-- VOID: a roiling band of darkness that corrodes and destroys whatever it touches
-- — the hero, and the Horde's own creatures. The Horde does not merely wait: it
-- banks AP and SURGES the collapse (a 15% instant cut), summons fresh creatures
-- INSIDE the safe zone, and — when a Void Architect lives — drags the safe zone's
-- centre sideways so the void bulges in from one direction. The squeeze tightens
-- through three danger zones as the radius falls:
--      OUTER (calm)  ->  INNER (fast)  ->  FINAL (frantic).
-- Endure the FINAL stand until the collapse bottoms out and the singularity
-- stabilises, and you live. Touch the edge too long and you unravel.
--
-- TWO PHASES (the PIT pattern):
--   1. PLACEMENT — you are the void. Seed up to 6 creatures inside the starting
--      safe disc and pick which hero gets thrown in. Click to place; [Enter] drops
--      the hero and the collapse begins.
--   2. COLLAPSE  — you then DRIVE that hero (WASD / arrows), [Space] swing, and —
--      as the Void Walker — [Shift] PHASE briefly through the void unharmed. The
--      Horde AI runs the collapse against you. Survive the squeeze.
--
-- The top-down camera ZOOMS as the safe zone shrinks, so the final cramped stand
-- fills the screen. Physics is hand-rolled 2D: WASD locomotion, boid separation,
-- blink teleports, a drifting safe-zone centre, and a circular void clamp. All art
-- is from tools/gen_textures_void_collapse.py and OPTIONAL — a missing PNG just
-- falls back to a flat silhouette colour, so the game still runs.
--
-- This file ALSO returns { meta, config } at the bottom so the mode is discover-
-- able from the battlefield menu; that path can only run the shared Duel, so it
-- falls back to a valid Void-themed duel (same cast; the collapse becomes a
-- shrinking safe-radius hazard that corrodes a hero caught outside the ring).

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local VoidC = ATH_COMMON.load_script("Scripts/modes/void_collapse/characters.lua", "void_collapse characters", _ENV)

local DATA = VoidC.void2d
local C = DATA.palette

-- ===========================================================================
-- Collapse tuning (the one bespoke system, all in one place)
-- ===========================================================================

local R_START = DATA.arena.radius_start          -- 40 safe units at t=0
local R_FLOOR = DATA.arena.radius_floor          -- 5 — the singularity floor
local COLLAPSE_S = DATA.arena.collapse_seconds   -- 240 nominal

-- Danger-zone thresholds (safe radius), and the per-phase shrink multiplier on
-- the nominal rate — calm, then fast, then frantic.
local THRESH_INNER = 24.0     -- r > THRESH_INNER  => OUTER (calm)
local THRESH_FINAL = 12.0     -- r <= THRESH_FINAL => FINAL (frantic); between => INNER
local BASE_RATE = (R_START - R_FLOOR) / COLLAPSE_S
local PHASE_MULT = { outer = 0.85, inner = 1.20, final = 1.70 }

local SURGE_PCT = 0.15        -- a Horde surge cuts the safe radius 15% instantly
local STABILIZE_HOLD = 9.0    -- seconds the hero must survive once r hits the floor

-- The void's bite: damage per second when the hero stands beyond the edge, scaling
-- with how deep into the dark they are.
local VOID_DPS = 24.0
local VOID_DEPTH_DPS = 10.0   -- extra dps per world-unit past the edge

-- Horde AP economy (it runs the collapse against you during combat).
local AP_RATE = 7.0           -- AP banked per second
local SURGE_COST = 45.0       -- AP to trigger a collapse surge
local ENTITY_CAP = 46

-- ===========================================================================
-- The 2D game
-- ===========================================================================

local SCREEN = "ath.void_collapse"
local UPDATE_ID = "against_the_hero_void_collapse"

local Game = {
    phase = "placement",      -- "placement" | "combat" | "won" | "lost"
    key_down = {},
    entities = {},            -- creatures released / summoned into the arena
    bloods = {},              -- corrosion decals (world-anchored, fading)
    placed = {},              -- entries during placement: { id, x, y }
    sel_horde = "void_fragment",
    sel_hero = "anchor",
    budget = 0,
    time = 0.0,
    flash = "", flash_t = 0.0, last_flash = nil,
    cam = { ox = 0.0, oy = 0.0, ppu = 16.0 },
    -- The live collapse state (init in begin_collapse).
    collapse = nil,
    _live = {}, _prev = {},
    next_id = 0,
}

-- ---- small helpers ---------------------------------------------------------

local function log(msg) if pe_log then pe_log("[ATH:VOID] " .. tostring(msg)) end end

local function clampn(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function len2(x, y) return math.sqrt(x * x + y * y) end

local function dt_seconds()
    local m = engine and engine.get_metrics and engine.get_metrics() or nil
    local dt = m and m.delta_ms and m.delta_ms / 1000.0 or (1.0 / 60.0)
    if not dt or dt <= 0.0 then dt = 1.0 / 60.0 end
    return math.min(dt, 0.1)
end

local function key_down(name)
    return input and input.is_key_down and input.is_key_down(name) == true
end

local function key_pressed(name)
    local down = key_down(name)
    local pressed = down and not Game.key_down[name]
    Game.key_down[name] = down
    return pressed
end

-- Cursor in surface pixels (mirrors the pit's nil-safe probe order).
local function mouse_pos()
    if input then
        local getter = input.get_mouse_position or input.mouse_position or input.get_cursor_position
        if getter then
            local a, b = getter()
            if type(a) == "table" and a.x then return a.x, a.y end
            if type(a) == "number" then return a, b end
        end
    end
    if runtime_ui and runtime_ui.get_state then
        local st = runtime_ui.get_state(SCREEN, "world_input")
        if st then
            if st.mouse and st.mouse.x then return st.mouse.x, st.mouse.y end
            if st.mouse_x then return st.mouse_x, st.mouse_y end
        end
    end
    return nil
end

local function set_flash(text) Game.flash = text or "" end

-- ---- collapse-zone queries -------------------------------------------------

-- The current danger zone from a safe radius.
local function zone_of(r)
    if r > THRESH_INNER then return "outer" end
    if r > THRESH_FINAL then return "inner" end
    return "final"
end

local function zone_label(z)
    if z == "outer" then return "OUTER", { 0.55, 0.45, 0.85, 1.0 } end
    if z == "inner" then return "INNER", { 0.78, 0.30, 0.95, 1.0 } end
    return "FINAL", { 1.0, 0.2, 1.0, 1.0 }
end

-- Distance from the (possibly drifted) safe-zone centre.
local function dist_from_centre(wx, wy)
    local cl = Game.collapse
    local cx = cl and cl.cx or 0.0
    local cy = cl and cl.cy or 0.0
    return len2(wx - cx, wy - cy)
end

-- How far a point is OUTSIDE the safe edge (<=0 means safe).
local function void_depth(wx, wy, radius)
    local cl = Game.collapse
    if not cl then return -1.0 end
    return dist_from_centre(wx, wy) - (cl.radius - (radius or 0.0))
end

-- Clamp a point to the outer arena disc (the void is traversable, the floor edge
-- of the world is not). Heroes & creatures can wander into the dark and die there.
local function clamp_to_arena(wx, wy, radius)
    local R = R_START - (radius or 0.0)
    local d = len2(wx, wy)
    if d > R and d > 0.0001 then
        local s = R / d
        return wx * s, wy * s
    end
    return wx, wy
end

-- ---- world <-> screen ------------------------------------------------------

-- The camera fits the CURRENT safe zone (plus a margin of void) in frame, so the
-- view zooms in smoothly as the collapse tightens. It also tracks the drifting
-- safe centre.
local function recompute_cam(dt)
    local sw, sh = Art.surface_size()
    local cl = Game.collapse
    local view_r = cl and clampn(cl.radius * 1.55 + 3.0, R_FLOOR + 4.0, R_START) or R_START
    local avail = math.min(sw - 90.0, sh - 210.0)
    local target_ppu = math.max(6.0, avail / (2.0 * view_r))
    -- Smooth the zoom so a surge doesn't snap the camera.
    local k = dt and clampn(dt * 4.0, 0.0, 1.0) or 1.0
    Game.cam.ppu = Game.cam.ppu + (target_ppu - Game.cam.ppu) * k
    -- Centre on the safe zone (drifts with the Architect).
    local cx = cl and cl.cx or 0.0
    local cy = cl and cl.cy or 0.0
    Game.cam.ox = sw * 0.5 - cx * Game.cam.ppu
    Game.cam.oy = ((sh - 140.0) * 0.5 + 60.0) - cy * Game.cam.ppu
    return sw, sh
end

local function w2s(wx, wy)
    local c = Game.cam
    return c.ox + wx * c.ppu, c.oy + wy * c.ppu
end

local function s2w(sx, sy)
    local c = Game.cam
    return (sx - c.ox) / c.ppu, (sy - c.oy) / c.ppu
end

-- ---- canvas draw (records ids so stale ones get swept each frame) ----------

local function draw(id, x, y, w, h, fill, opts)
    Game._live[id] = true
    Art.quad(SCREEN, id, x, y, w, h, fill, opts)
end

-- A world-anchored sprite: a faint solid core (so it reads with no art) plus the
-- textured quad on top. size is in world units; opts.z lifts it (e.g. a bob).
local function draw_sprite(id, wx, wy, size, image, color, opts)
    opts = opts or {}
    local ppu = Game.cam.ppu
    local px = size * ppu
    local sx, sy = w2s(wx, wy)
    local zoff = (opts.z or 0.0) * ppu
    local cs = px * 0.5
    draw(id .. "_core", sx - cs * 0.5, sy - zoff - cs * 0.5, cs, cs,
        { color[1], color[2], color[3], opts.core_alpha or 0.8 }, { no_input = true })
    draw(id, sx - px * 0.5, sy - zoff - px * 0.55, px, px, { 0, 0, 0, 0 },
        { image = image, no_input = true, image_tint = opts.tint })
end

-- ---- corrosion decals ------------------------------------------------------

local function add_blood(wx, wy, big)
    Game.next_id = Game.next_id + 1
    Game.bloods[#Game.bloods + 1] = {
        id = "rot_" .. Game.next_id, x = wx, y = wy,
        size = (big and 2.2 or 1.3) + math.random() * 0.4, life = 5.0,
    }
end

-- ---------------------------------------------------------------------------
-- Hero
-- ---------------------------------------------------------------------------

local function spawn_hero()
    local def = DATA.heroes[Game.sel_hero]
    local sp = DATA.arena.hero_spawn
    Game.hero = {
        def = def, x = sp.x, y = sp.y,
        hp = def.hp, hp_max = def.hp,
        dir = 6, moving = false, phase = 0.0,
        attack_cd = 0.0, attack_flash = 0.0,
        phase_cd = 0.0, phase_t = 0.0,          -- Void Walker's phase ability
        hit_flash = 0.0, void_flash = 0.0, dead = false,
        slow_mult = 1.0,                        -- recomputed each tick (Unraveler aura)
    }
end

local function hero_take_damage(amount, what)
    local h = Game.hero
    if not h or h.dead or amount <= 0.0 then return end
    h.hp = h.hp - amount
    h.hit_flash = math.max(h.hit_flash, 0.16)
    if h.hp <= 0.0 then
        h.hp = 0.0; h.dead = true
        Game.phase = "lost"
        set_flash("YOU UNRAVEL")
        add_blood(h.x, h.y, true)
        log("hero lost to " .. tostring(what or "the void"))
    end
end

local function update_hero(dt)
    local h = Game.hero
    if not h then return end
    h.attack_cd = math.max(0.0, h.attack_cd - dt)
    h.phase_cd = math.max(0.0, h.phase_cd - dt)
    h.hit_flash = math.max(0.0, h.hit_flash - dt)
    h.void_flash = math.max(0.0, h.void_flash - dt)
    h.attack_flash = math.max(0.0, h.attack_flash - dt)
    if h.dead then return end

    -- WASD / arrows -> a movement vector (screen +y is south).
    local ix = (key_down("D") or key_down("Right")) and 1.0 or 0.0
    ix = ix - ((key_down("A") or key_down("Left")) and 1.0 or 0.0)
    local iy = (key_down("S") or key_down("Down")) and 1.0 or 0.0
    iy = iy - ((key_down("W") or key_down("Up")) and 1.0 or 0.0)
    local mag = len2(ix, iy)
    h.moving = mag > 0.0

    -- Phase (Void Walker only): a brief immune dash across the void on [Shift].
    if h.def.phase then
        if h.phase_t > 0.0 then h.phase_t = math.max(0.0, h.phase_t - dt) end
        if (key_pressed("LeftShift") or key_pressed("RightShift") or key_pressed("Shift"))
            and h.phase_cd <= 0.0 then
            h.phase_t = h.def.phase.time
            h.phase_cd = h.def.phase.cd
            set_flash("PHASE")
        end
    end
    local phasing = h.def.phase and h.phase_t > 0.0

    if mag > 0.0 then
        ix, iy = ix / mag, iy / mag
        local speed = h.def.speed * (h.slow_mult or 1.0)
        if phasing then speed = h.def.phase.speed end
        h.x = h.x + ix * speed * dt
        h.y = h.y + iy * speed * dt
        h.x, h.y = clamp_to_arena(h.x, h.y, h.def.radius)
        local ang = math.atan(iy, ix)
        h.dir = math.floor(ang / (math.pi / 4.0) + 0.5) % 8
        if h.dir < 0 then h.dir = h.dir + 8 end
        h.phase = h.phase + dt * h.def.walk_freq
    end

    -- VOID BITE — beyond the safe edge the dark corrodes the hero (per second,
    -- deeper = worse). Anchor is warded; the Void Walker is immune while phasing.
    local depth = void_depth(h.x, h.y, h.def.radius)
    if depth > 0.0 and not phasing then
        local dps = (VOID_DPS + VOID_DEPTH_DPS * depth) * (h.def.void_resist or 1.0)
        h.hp = h.hp - dps * dt
        h.void_flash = 0.2
        if math.random() < dt * 6.0 then add_blood(h.x, h.y, false) end
        if h.hp <= 0.0 then
            h.hp = 0.0; h.dead = true
            Game.phase = "lost"
            set_flash("THE VOID TOOK YOU")
            add_blood(h.x, h.y, true)
            log("hero corroded by the void")
        end
    end

    -- Attack: [Space] / [J] sweep — damage every creature within reach.
    if (key_pressed("Space") or key_pressed("J")) and h.attack_cd <= 0.0 then
        h.attack_cd = h.def.attack_cd
        h.attack_flash = 0.14
        local r = h.def.attack_range + h.def.radius
        local r2 = r * r
        for _, e in ipairs(Game.entities) do
            if e.alive then
                local dx, dz = e.x - h.x, e.y - h.y
                if dx * dx + dz * dz <= r2 + (e.def.radius or 0.0) then
                    e.hp = e.hp - h.def.attack_damage
                    e.hit_flash = 0.18
                    add_blood(e.x, e.y, false)
                    if e.hp <= 0.0 then e.alive = false; add_blood(e.x, e.y, true) end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Creatures
-- ---------------------------------------------------------------------------

local function spawn_entity(id, x, y)
    local def = DATA.horde[id]
    Game.next_id = Game.next_id + 1
    return {
        id = "ent_" .. Game.next_id, kind = id, def = def,
        x = x, y = y, hp = def.hp, alive = true,
        seed = math.random() * 6.28, hit_flash = 0.0, moving = false,
        cd = 0.0, blink_cd = (def.blink_cd or 0.0), blink_t = 0.0, blink_tx = 0.0, blink_ty = 0.0,
    }
end

-- Boid separation: push apart from nearby kin so packs spread and surround.
local function separation(e)
    local sx, sz = 0.0, 0.0
    local rad = e.def.sep_radius or 1.4
    local r2 = rad * rad
    for _, o in ipairs(Game.entities) do
        if o ~= e and o.alive then
            local dx, dz = e.x - o.x, e.y - o.y
            local d2 = dx * dx + dz * dz
            if d2 < r2 and d2 > 0.0001 then
                local d = math.sqrt(d2)
                sx = sx + (dx / d) * (1.0 - d / rad)
                sz = sz + (dz / d) * (1.0 - d / rad)
            end
        end
    end
    return sx, sz
end

-- Shared melee contact bite for the seekers.
local function contact_bite(e, dt, h, d, who)
    e.cd = math.max(0.0, e.cd - dt)
    if d <= e.def.radius + h.def.radius + 0.2 and e.cd <= 0.0 then
        e.cd = e.def.touch_cd
        hero_take_damage(e.def.touch_damage, who)
    end
end

-- VOID FRAGMENT — seek the hero with separation, bite on contact.
local function update_fragment(e, dt, h)
    local dx, dz = h.x - e.x, h.y - e.y
    local d = len2(dx, dz)
    local sx, sz = 0.0, 0.0
    if d > 0.0001 then sx, sz = dx / d, dz / d end
    local px, pz = separation(e)
    local vx = sx + px * (e.def.sep_weight or 1.4)
    local vz = sz + pz * (e.def.sep_weight or 1.4)
    local vm = len2(vx, vz)
    if vm > 0.0001 then vx, vz = vx / vm, vz / vm end
    e.x = e.x + vx * e.def.speed * dt
    e.y = e.y + vz * e.def.speed * dt
    e.x, e.y = clamp_to_arena(e.x, e.y, e.def.radius)
    e.moving = vm > 0.01
    contact_bite(e, dt, h, d, "a Void Fragment")
end

-- COLLAPSE ECHO — drift slowly, then blink to the hero's flank and strike. The
-- blink telegraphs (a held marker), so a sharp player can punish the landing.
local function update_echo(e, dt, h)
    local dx, dz = h.x - e.x, h.y - e.y
    local d = len2(dx, dz)
    if e.blink_t > 0.0 then
        -- Mid-telegraph: hold position, then snap to the marked flank point.
        e.blink_t = e.blink_t - dt
        if e.blink_t <= 0.0 then
            e.x, e.y = clamp_to_arena(e.blink_tx, e.blink_ty, e.def.radius)
            e.blink_cd = e.def.blink_cd
        end
    else
        -- Drift toward the hero between blinks.
        if d > 0.0001 then
            e.x = e.x + (dx / d) * e.def.speed * dt
            e.y = e.y + (dz / d) * e.def.speed * dt
            e.x, e.y = clamp_to_arena(e.x, e.y, e.def.radius)
        end
        e.moving = true
        e.blink_cd = math.max(0.0, e.blink_cd - dt)
        if e.blink_cd <= 0.0 and d > 2.0 then
            -- Mark a point just off the hero's side and begin the telegraph.
            local a = math.random() * 6.2832
            e.blink_tx = h.x + math.cos(a) * e.def.blink_range
            e.blink_ty = h.y + math.sin(a) * e.def.blink_range
            e.blink_t = e.def.blink_telegraph
        end
    end
    contact_bite(e, dt, h, d, "a Collapse Echo")
end

-- UNRAVELER — slow elite; close on the hero, drag its pace down with an aura.
local function update_unraveler(e, dt, h)
    local dx, dz = h.x - e.x, h.y - e.y
    local d = len2(dx, dz)
    local sx, sz = 0.0, 0.0
    if d > 0.0001 then sx, sz = dx / d, dz / d end
    local px, pz = separation(e)
    local vx, vz = sx + px * (e.def.sep_weight or 0.8), sz + pz * (e.def.sep_weight or 0.8)
    local vm = len2(vx, vz)
    if vm > 0.0001 then vx, vz = vx / vm, vz / vm end
    e.x = e.x + vx * e.def.speed * dt
    e.y = e.y + vz * e.def.speed * dt
    e.x, e.y = clamp_to_arena(e.x, e.y, e.def.radius)
    e.moving = vm > 0.01
    -- The slow aura (applied to the hero in update_entities' aggregate pass).
    if d <= e.def.slow_range then h.slow_mult = math.min(h.slow_mult, e.def.slow_mult) end
    contact_bite(e, dt, h, d, "an Unraveler")
end

-- VOID ARCHITECT — boss; close in AND haul the safe-zone centre toward itself, so
-- the void bulges in from its side ("extend the collapse in a direction").
local function update_architect(e, dt, h)
    local dx, dz = h.x - e.x, h.y - e.y
    local d = len2(dx, dz)
    if d > 0.0001 then
        e.x = e.x + (dx / d) * e.def.speed * dt
        e.y = e.y + (dz / d) * e.def.speed * dt
        e.x, e.y = clamp_to_arena(e.x, e.y, e.def.radius)
    end
    e.moving = true
    -- Drag the safe centre toward the Architect (bounded so the zone stays on the
    -- floor). This is the boss's signature: a directional collapse.
    local cl = Game.collapse
    if cl then
        local ax, ay = e.x - cl.cx, e.y - cl.cy
        local am = len2(ax, ay)
        if am > 0.0001 and am < e.def.pull_range then
            local pull = e.def.pull_strength * dt
            cl.cx = cl.cx + (ax / am) * pull
            cl.cy = cl.cy + (ay / am) * pull
            -- Keep the safe disc fully inside the arena floor.
            local off = len2(cl.cx, cl.cy)
            local maxoff = math.max(0.0, R_START - cl.radius)
            if off > maxoff and off > 0.0001 then
                local s = maxoff / off
                cl.cx, cl.cy = cl.cx * s, cl.cy * s
            end
        end
    end
    contact_bite(e, dt, h, d, "the Void Architect")
end

local function update_entities(dt)
    local h = Game.hero
    if h then h.slow_mult = 1.0 end          -- recomputed by Unraveler auras below
    local survivors = {}
    for _, e in ipairs(Game.entities) do
        e.hit_flash = math.max(0.0, e.hit_flash - dt)
        if e.alive and h and not h.dead then
            if e.kind == "void_fragment" then update_fragment(e, dt, h)
            elseif e.kind == "collapse_echo" then update_echo(e, dt, h)
            elseif e.kind == "unraveler" then update_unraveler(e, dt, h)
            elseif e.kind == "void_architect" then update_architect(e, dt, h) end
        end
        -- The void corrodes the Horde too — creatures caught in the dark unravel.
        if e.alive then
            local depth = void_depth(e.x, e.y, e.def.radius)
            if depth > 0.0 then
                e.hp = e.hp - (VOID_DPS * 0.8 + VOID_DEPTH_DPS * depth) * dt
                if e.hp <= 0.0 then e.alive = false; add_blood(e.x, e.y, true) end
            end
        end
        if e.alive then survivors[#survivors + 1] = e
        else Game._live[e.id] = nil; Game._live[e.id .. "_core"] = nil end
    end
    Game.entities = survivors
end

-- ---------------------------------------------------------------------------
-- The collapse + the Horde AI that runs it
-- ---------------------------------------------------------------------------

local function begin_collapse()
    Game.collapse = {
        radius = R_START, cx = 0.0, cy = 0.0,
        ap = 0.0, next_action = 4.0, surges = 0,
        stabilize_t = STABILIZE_HOLD, zone = "outer",
        edge_seed = {},
    }
    for i = 1, DATA.arena.edge_count do
        Game.collapse.edge_seed[i] = math.random() * 6.2832
    end
end

-- Summon one creature inside the current safe zone (near the edge, the Horde's way
-- in). Returns true if it spawned.
local function summon_creature(id)
    if #Game.entities >= ENTITY_CAP then return false end
    local cl = Game.collapse
    local a = math.random() * 6.2832
    local rr = cl.radius * (0.55 + math.random() * 0.35)
    local x = cl.cx + math.cos(a) * rr
    local y = cl.cy + math.sin(a) * rr
    x, y = clamp_to_arena(x, y, DATA.horde[id].radius)
    Game.entities[#Game.entities + 1] = spawn_entity(id, x, y)
    return true
end

local function do_surge()
    local cl = Game.collapse
    cl.radius = math.max(R_FLOOR, cl.radius * (1.0 - SURGE_PCT))
    cl.surges = cl.surges + 1
    set_flash("VOID SURGE")
    log("collapse surge -> r=" .. string.format("%.1f", cl.radius))
end

-- The Horde brain. Banks AP, then spends it: surge the collapse, or summon a
-- creature inside the safe zone. It bites harder (acts more often, fields heavier
-- creatures) as the danger zone deepens.
local function update_horde_ai(dt)
    local cl = Game.collapse
    cl.ap = cl.ap + AP_RATE * dt
    cl.next_action = cl.next_action - dt
    if cl.next_action > 0.0 then return end

    local zone = cl.zone
    -- Act faster in deeper zones — OUTER calm, FINAL frantic.
    cl.next_action = (zone == "final") and (1.2 + math.random() * 1.0)
        or (zone == "inner") and (2.2 + math.random() * 1.4)
        or (3.4 + math.random() * 2.0)

    -- Decide: surge, or summon. Surges grow likelier as the squeeze tightens.
    local surge_chance = (zone == "final") and 0.55 or (zone == "inner") and 0.38 or 0.22
    if cl.ap >= SURGE_COST and math.random() < surge_chance then
        cl.ap = cl.ap - SURGE_COST
        do_surge()
        return
    end

    -- Otherwise summon something we can afford. Weighted toward fragments, with
    -- echoes appearing in INNER, an Unraveler in FINAL, and a single Architect once.
    local pick
    local roll = math.random()
    if zone == "final" and not Game.architect_summoned and cl.ap >= DATA.horde.void_architect.ap_cost then
        pick = "void_architect"; Game.architect_summoned = true
    elseif (zone == "final" or zone == "inner") and roll < 0.18 and cl.ap >= DATA.horde.unraveler.ap_cost then
        pick = "unraveler"
    elseif zone ~= "outer" and roll < 0.5 and cl.ap >= DATA.horde.collapse_echo.ap_cost then
        pick = "collapse_echo"
    elseif cl.ap >= DATA.horde.void_fragment.ap_cost then
        pick = "void_fragment"
    end
    if pick then
        if summon_creature(pick) then cl.ap = cl.ap - DATA.horde[pick].ap_cost end
    end
end

local function update_collapse(dt)
    local cl = Game.collapse
    if not cl then return end
    local zone = zone_of(cl.radius)
    cl.zone = zone

    -- Nominal shrink, scaled by danger zone (calm -> fast -> frantic).
    cl.radius = cl.radius - BASE_RATE * PHASE_MULT[zone] * dt

    -- Bottomed out: the singularity. Survive the FINAL stand to win.
    if cl.radius <= R_FLOOR then
        cl.radius = R_FLOOR
        cl.stabilize_t = cl.stabilize_t - dt
        if cl.stabilize_t <= 0.0 and Game.phase == "combat" then
            Game.phase = "won"
            set_flash("THE SINGULARITY STABILISES")
            log("hero endured the collapse")
        end
    end

    update_horde_ai(dt)
end

-- ---------------------------------------------------------------------------
-- Placement phase
-- ---------------------------------------------------------------------------

local function can_place(wx, wy)
    -- Inside the starting safe disc, off the hero's drop point, off other placings.
    if len2(wx, wy) > R_START - 2.0 then return false end
    local sp = DATA.arena.hero_spawn
    if len2(wx - sp.x, wy - sp.y) < 3.0 then return false end
    for _, pe in ipairs(Game.placed) do
        if len2(wx - pe.x, wy - pe.y) < 1.6 then return false end
    end
    return true
end

local function release_hero()
    Game.entities = {}
    for _, pe in ipairs(Game.placed) do
        Game.entities[#Game.entities + 1] = spawn_entity(pe.id, pe.x, pe.y)
    end
    spawn_hero()
    begin_collapse()
    Game.architect_summoned = false
    Game.bloods = {}
    Game.time = 0.0
    Game.phase = "combat"
    set_flash("ENDURE THE COLLAPSE")
    log("released " .. tostring(Game.sel_hero) .. " vs " .. tostring(#Game.entities) .. " placed")
end

local function reset_game()
    Game.placed = {}
    Game.entities = {}
    Game.bloods = {}
    Game.budget = DATA.placement.budget
    Game.phase = "placement"
    Game.hero = nil
    Game.collapse = nil
    Game.architect_summoned = false
    Game.time = 0.0
    set_flash("SEED THE VOID  -  place up to " .. tostring(Game.budget))
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

-- A fixed world grid built once; culled to the live safe disc each frame so the
-- lit floor shrinks with the collapse (undrawn tiles get swept away).
local function build_floor_tiles()
    Game.floor = {}
    local step = 4.0
    local i = 0
    local y = -R_START
    while y <= R_START do
        local x = -R_START
        while x <= R_START do
            i = i + 1
            Game.floor[i] = { x = x, y = y }
            x = x + step
        end
        y = y + step
    end
    Game.floor_step = step
end

local function draw_world(sw, sh)
    -- The void is the backdrop: near-black, faintly purple.
    draw("bg", 0, 0, sw, sh, { C.deep[1], C.deep[2], C.deep[3], 1.0 }, { no_input = true })

    local cl = Game.collapse
    local r = cl and cl.radius or R_START
    local cx = cl and cl.cx or 0.0
    local cy = cl and cl.cy or 0.0
    local ppu = Game.cam.ppu
    local tile = Game.floor_step * ppu

    -- Lit floor: only tiles inside the safe disc (so it visibly shrinks).
    local r2 = (r + Game.floor_step * 0.5) * (r + Game.floor_step * 0.5)
    for i, t in ipairs(Game.floor) do
        local dx, dy = t.x - cx, t.y - cy
        if dx * dx + dy * dy <= r2 then
            local sx, sy = w2s(t.x, t.y)
            -- Tiles near the closing edge glow toward the singularity.
            local edge = (dx * dx + dy * dy) > (r - Game.floor_step) * (r - Game.floor_step)
            local shade = edge and 1.0 or 0.7
            local fill = edge
                and { C.core[1], C.core[2] + 0.02, C.core[3], 1.0 }
                or { C.collapse[1] * shade + 0.02, C.collapse[2] * shade, C.collapse[3] * shade + 0.04, 1.0 }
            draw("fl_" .. i, sx - tile * 0.5, sy - tile * 0.5, tile + 1.0, tile + 1.0, fill,
                { image = DATA.sprites.floor, no_input = true })
        end
    end

    -- The danger-ring overlay sits over the whole safe disc, fiercest at the edge.
    if cl then
        local sx, sy = w2s(cx, cy)
        local dp = (2.0 * r + 4.0) * ppu
        local _, zcol = zone_label(cl.zone)
        local pulse = 0.5 + 0.5 * math.sin(Game.time * (cl.zone == "final" and 9.0 or 4.0))
        draw("danger_ring", sx - dp * 0.5, sy - dp * 0.5, dp, dp, { zcol[1], zcol[2], zcol[3], 0.10 + 0.10 * pulse },
            { image = DATA.sprites.danger_ring, no_input = true })

        -- Roiling void-edge motes orbit the closing rim (4-frame loop).
        local n = DATA.arena.edge_count
        local frame = (math.floor(Game.time * 10.0) % 4) + 1
        local img = DATA.sprites.edge_frames[frame]
        for i = 1, n do
            local a = (i / n) * 6.2832 + Game.time * 0.25
            local rr = r + 0.5 + 0.35 * math.sin(Game.time * 3.0 + (cl.edge_seed[i] or 0.0))
            local wx, wy = cx + math.cos(a) * rr, cy + math.sin(a) * rr
            draw_sprite("edge_" .. i, wx, wy, 2.0, img, C.edge, { core_alpha = 0.0 })
        end
    end
end

local function draw_corrosion(dt)
    local survivors = {}
    for _, b in ipairs(Game.bloods) do
        b.life = b.life - dt
        if b.life > 0.0 then
            survivors[#survivors + 1] = b
            local a = clampn(b.life / 5.0, 0.0, 0.8)
            local sx, sy = w2s(b.x, b.y)
            local px = b.size * Game.cam.ppu
            draw(b.id, sx - px * 0.5, sy - px * 0.4, px, px, { C.edge[1], C.edge[2], C.edge[3], a * 0.4 },
                { no_input = true })
        else
            Game._live[b.id] = nil
        end
    end
    Game.bloods = survivors
end

local function creature_frame(e)
    local frames = DATA.sprites[e.def.frames]
    if not frames then return nil end
    local n = #frames
    local idx = (math.floor(Game.time * (e.def.fps or 8.0) + e.seed * 4.0) % n) + 1
    return frames[idx]
end

-- Depth-sorted draw of every actor (lower screen-y first -> south draws on top).
local function draw_actors()
    local list = {}
    for _, e in ipairs(Game.entities) do list[#list + 1] = { y = e.y, e = e } end
    if Game.hero then list[#list + 1] = { y = Game.hero.y, hero = Game.hero } end
    table.sort(list, function(a, b) return a.y < b.y end)

    for _, item in ipairs(list) do
        if item.e then
            local e = item.e
            local sway = (e.def.sway_amp or 0.0) * math.sin(Game.time * (e.def.sway_freq or 3.0) + e.seed)
            local col = e.def.color
            if e.hit_flash > 0.0 then col = { 1.0, 0.7, 1.0 } end
            -- A blinking Echo mid-telegraph flickers translucent and marks its landing.
            local tint, alpha
            if e.kind == "collapse_echo" and e.blink_t > 0.0 then
                alpha = 0.3 + 0.3 * math.sin(Game.time * 30.0)
                local mx, my = w2s(e.blink_tx, e.blink_ty)
                local mp = e.def.size * Game.cam.ppu
                draw("blinkmark_" .. e.id, mx - mp * 0.5, my - mp * 0.5, mp, mp,
                    { C.singularity[1], C.singularity[2], C.singularity[3], 0.25 + 0.25 * math.sin(Game.time * 24.0) },
                    { no_input = true })
            end
            draw_sprite(e.id, e.x, e.y + sway, e.def.size, creature_frame(e), col, { tint = tint, core_alpha = alpha or 0.8 })
        elseif item.hero then
            local h = item.hero
            local bob = (h.moving and not h.dead) and (h.def.walk_bob * math.abs(math.sin(h.phase))) or 0.0
            local col = h.def.color
            if h.hit_flash > 0.0 then col = { 1.0, 0.4, 0.4 }
            elseif h.void_flash > 0.0 then col = { C.edge[1], C.edge[2], C.edge[3] }
            elseif h.attack_flash > 0.0 then col = { 1.0, 1.0, 0.8 } end
            local phasing = h.def.phase and h.phase_t > 0.0
            local sx, sy = w2s(h.x, h.y)
            local px = h.def.size * Game.cam.ppu
            local zoff = bob * Game.cam.ppu
            -- Body core.
            local body_a = h.dead and 0.4 or (phasing and 0.45 or 0.92)
            draw("hero_core", sx - px * 0.4, sy - zoff - px * 0.4, px * 0.8, px * 0.8,
                { col[1], col[2], col[3], body_a }, { no_input = true })
            -- A facing pip in the heading direction, so you can read where you aim.
            local ang = h.dir * (math.pi / 4.0)
            local fx = sx + math.cos(ang) * px * 0.42
            local fy = sy - zoff + math.sin(ang) * px * 0.42
            local g = h.def.glow
            draw("hero_pip", fx - px * 0.16, fy - px * 0.16, px * 0.32, px * 0.32,
                { g[1], g[2], g[3], h.dead and 0.3 or 1.0 }, { no_input = true })
            -- Ward halo: Anchor always (its void resistance), Walker only while phasing.
            if (not h.dead) and ((h.def.id == "anchor") or phasing) then
                local hp_px = px * (phasing and 1.5 or 1.2)
                local ha = (phasing and 0.5 or 0.18) + 0.12 * math.sin(Game.time * 8.0)
                draw("hero_ward", sx - hp_px * 0.5, sy - zoff - hp_px * 0.5, hp_px, hp_px,
                    { g[1], g[2], g[3], ha }, { no_input = true })
            end
        end
    end
end

local function draw_placement_ghost()
    local mx, my = mouse_pos()
    if not mx then return end
    local wx, wy = s2w(mx, my)
    local ok = can_place(wx, wy) and Game.budget > 0
    local def = DATA.horde[Game.sel_horde]
    local sx, sy = w2s(wx, wy)
    local px = def.size * Game.cam.ppu
    draw("ghost", sx - px * 0.5, sy - px * 0.5, px, px,
        { def.color[1], def.color[2], def.color[3], 0.35 },
        { border = ok and { 0.4, 0.9, 0.5, 0.9 } or { 0.9, 0.3, 0.4, 0.9 }, no_input = true })
end

-- ---- HUD -------------------------------------------------------------------

local function button(id, x, y, w, h, label, opts)
    opts = opts or {}
    local st = Art.widget_state(SCREEN, id)
    local hov = st and st.hovered
    Game._live[id] = true
    Art.quad(SCREEN, id, x, y, w, h, opts.fill or (hov and { 0.14, 0.06, 0.20, 0.96 } or { 0.07, 0.04, 0.12, 0.94 }),
        { border = opts.border or { 0.5, 0.2, 0.7, 0.95 }, label = label, subtitle = opts.subtitle,
          text_color = opts.text_color, selected = opts.selected, font_scale = opts.font_scale })
    return Art.consume_click(SCREEN, id)
end

local function draw_hud(sw, sh)
    draw("title", 20, 16, 420, 40, { 0, 0, 0, 0 },
        { title = "VOID COLLAPSE", text_color = { C.edge[1], C.edge[2], C.edge[3], 1.0 }, font_scale = 1.3, no_input = true })

    if Game.phase == "placement" then
        local px, py, pw, ph = 20.0, sh - 132.0, 250.0, 56.0
        for i, id in ipairs(DATA.horde_order) do
            local def = DATA.horde[id]
            local bx = px + (i - 1) * (pw + 8.0)
            if button("pal_" .. id, bx, py, pw, ph, "[" .. i .. "] " .. def.name,
                { subtitle = def.blurb, selected = (Game.sel_horde == id),
                  border = (Game.sel_horde == id) and { 0.8, 0.2, 1.0, 1.0 } or { 0.4, 0.2, 0.6, 0.9 } })
                or key_pressed(tostring(i)) then
                Game.sel_horde = id
            end
        end
        local hx = px + 4 * (pw + 8.0) + 6.0
        for i, id in ipairs(DATA.hero_order) do
            local def = DATA.heroes[id]
            if button("hero_" .. id, hx, py + (i - 1) * 28.0, 250.0, 24.0, def.name,
                { selected = (Game.sel_hero == id), font_scale = 0.85,
                  border = (Game.sel_hero == id) and { 0.4, 0.85, 1.0, 1.0 } or { 0.3, 0.3, 0.4, 0.9 } }) then
                Game.sel_hero = id
            end
        end
        draw("budget", px, py - 36.0, 720.0, 28.0, { 0, 0, 0, 0 },
            { label = "Placements left: " .. tostring(Game.budget) .. "      Click in the safe zone to seed  -  [Enter] drop the hero  -  [Z] undo",
              text_color = { 0.82, 0.78, 0.9, 1.0 }, no_input = true })
        if button("release", sw - 290.0, sh - 132.0, 270.0, 56.0, "DROP THE HERO  [Enter]",
            { border = { 0.8, 0.2, 1.0, 1.0 }, fill = { 0.12, 0.04, 0.18, 0.96 } }) then
            release_hero()
        end
        draw_placement_ghost()

    elseif Game.phase == "combat" then
        local h = Game.hero
        local cl = Game.collapse
        -- Hero HP.
        local pct = h and (h.hp / h.hp_max) or 0.0
        local col = pct > 0.4 and { 0.45, 0.12, 0.75, 0.95 } or { 0.85, 0.12, 0.55, 0.95 }
        Art.bar(SCREEN, "hp", sw * 0.5 - 240.0, 24.0, 480.0, 30.0, pct, col,
            { label = (h and h.def.name or "HERO") .. string.format("   %d / %d", math.floor((h and h.hp or 0) + 0.5), math.floor((h and h.hp_max or 1) + 0.5)),
              border = { 0.667, 0.0, 1.0, 0.9 } })
        Game._live["hp_bg"] = true; Game._live["hp_fg"] = true; Game._live["hp_label"] = true

        -- Collapse meter (how far the safe zone has closed) + danger-zone tag.
        if cl then
            local zname, zcol = zone_label(cl.zone)
            local closed = clampn((R_START - cl.radius) / (R_START - R_FLOOR), 0.0, 1.0)
            Art.bar(SCREEN, "collapse", sw * 0.5 - 240.0, 60.0, 480.0, 22.0, closed, { zcol[1] * 0.7, zcol[2] * 0.7, zcol[3] * 0.7, 0.95 },
                { label = string.format("COLLAPSE  %s   safe r=%.0f", zname, cl.radius), border = { zcol[1], zcol[2], zcol[3], 0.95 } })
            Game._live["collapse_bg"] = true; Game._live["collapse_fg"] = true; Game._live["collapse_label"] = true

            -- Horde AP.
            local apct = clampn(cl.ap / SURGE_COST, 0.0, 1.0)
            Art.bar(SCREEN, "ap", 24.0, sh - 132.0, 300.0, 22.0, apct, { 0.5, 0.1, 0.7, 0.9 },
                { label = string.format("HORDE AP  %d   (surges: %d)", math.floor(cl.ap), cl.surges), border = { 0.7, 0.2, 0.9, 0.9 } })
            Game._live["ap_bg"] = true; Game._live["ap_fg"] = true; Game._live["ap_label"] = true

            -- The FINAL stand countdown.
            if cl.radius <= R_FLOOR + 0.01 then
                draw("stabilize", sw * 0.5 - 240.0, 90.0, 480.0, 26.0, { 0, 0, 0, 0 },
                    { label = string.format("HOLD THE SINGULARITY  -  %.1fs", math.max(0.0, cl.stabilize_t)),
                      text_color = { 1.0, 0.3, 1.0, 1.0 }, no_input = true })
            end
        end

        draw("ctrls", 20, sh - 50.0, 760.0, 26.0, { 0, 0, 0, 0 },
            { label = "WASD / arrows move   -   [Space] swing" .. (h and h.def.phase and "   -   [Shift] phase the void" or "") .. "   -   [R] rebuild",
              text_color = { 0.78, 0.74, 0.88, 1.0 }, no_input = true })
        draw("count", sw - 240.0, 24.0, 220.0, 26.0, { 0, 0, 0, 0 },
            { label = "Void creatures: " .. tostring(#Game.entities), text_color = { 0.85, 0.5, 0.95, 1.0 }, no_input = true })
    end

    if Game.phase == "won" or Game.phase == "lost" then
        local won = Game.phase == "won"
        draw("end", sw * 0.5 - 320.0, sh * 0.40, 640.0, 120.0,
            won and { 0.10, 0.04, 0.18, 0.94 } or { 0.16, 0.02, 0.10, 0.94 },
            { border = won and { 0.8, 0.3, 1.0, 0.95 } or { 0.9, 0.1, 0.5, 0.95 },
              title = won and "THE SINGULARITY STABILISES" or "YOU UNRAVELLED",
              body = "Press [R] to seed the void again", no_input = true })
    end

    if Game.flash ~= "" and Game.flash_t > 0.0 then
        draw("flash", sw * 0.5 - 280.0, 124.0, 560.0, 30.0, { 0, 0, 0, 0 },
            { label = Game.flash, text_color = { 1.0, 0.3, 1.0, math.min(1.0, Game.flash_t) }, no_input = true })
    end
end

-- ---------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------

local function sweep_stale()
    if runtime_ui and runtime_ui.remove then
        for id in pairs(Game._prev) do
            if not Game._live[id] then runtime_ui.remove(SCREEN, id) end
        end
    end
    Game._prev = Game._live
    Game._live = {}
end

local function update()
    local dt = dt_seconds()
    Game.time = Game.time + dt
    Game._live = {}

    if key_pressed("R") then reset_game() end

    if Game.phase == "placement" then
        if key_pressed("Z") and #Game.placed > 0 then
            table.remove(Game.placed)
            Game.budget = Game.budget + 1
        end
        if key_pressed("Return") or key_pressed("Space") then release_hero() end
        if Art.consume_click(SCREEN, "world_input") and Game.budget > 0 then
            local mx, my = mouse_pos()
            if mx then
                local wx, wy = s2w(mx, my)
                if can_place(wx, wy) then
                    Game.placed[#Game.placed + 1] = { id = Game.sel_horde, x = wx, y = wy }
                    Game.budget = Game.budget - 1
                end
            end
        end
    elseif Game.phase == "combat" then
        update_collapse(dt)
        update_hero(dt)
        update_entities(dt)
    end

    -- Flash decay.
    Game.flash_t = math.max(0.0, Game.flash_t - dt)
    if Game.flash ~= Game.last_flash then Game.flash_t = 2.2; Game.last_flash = Game.flash end
    if Game.flash_t <= 0.0 then Game.flash = "" end

    -- ---- render ----
    local sw, sh = recompute_cam(dt)
    -- Bottom full-screen input quad: captures world clicks + carries the cursor.
    draw("world_input", 0, 0, sw, sh, { 0, 0, 0, 0 })
    draw_world(sw, sh)
    draw_corrosion(dt)
    if Game.phase == "placement" then
        for i, pe in ipairs(Game.placed) do
            local def = DATA.horde[pe.id]
            draw_sprite("placed_" .. i, pe.x, pe.y, def.size, (DATA.sprites[def.frames] or {})[1], def.color, {})
        end
    end
    draw_actors()
    draw_hud(sw, sh)

    sweep_stale()
end

-- ---------------------------------------------------------------------------
-- Lifecycle (standalone, ATH_MODE=void_collapse)
-- ---------------------------------------------------------------------------

local function init()
    if runtime_ui then
        if runtime_ui.set_title then runtime_ui.set_title(SCREEN, "Void Collapse") end
        if runtime_ui.set_screen_overlay then runtime_ui.set_screen_overlay(SCREEN, true) end
        if runtime_ui.show then runtime_ui.show(SCREEN) end
    end
    local seed = ATH_COMMON.getenv_number and ATH_COMMON.getenv_number("ATH_VOID_SEED", nil) or nil
    if seed then math.randomseed(math.floor(seed)) end
    build_floor_tiles()
    reset_game()
    if script and script.on_update then
        script.on_update(UPDATE_ID, update, "play")
    else
        _G.update = update
    end
    log("init arena r=" .. tostring(R_START) .. " -> " .. tostring(R_FLOOR))
end

local function destroy()
    if script and script.remove_update then script.remove_update(UPDATE_ID) end
    if runtime_ui and runtime_ui.clear then runtime_ui.clear(SCREEN) end
    log("destroyed")
end

-- Only seize the engine loop when launched as the standalone mode. When the menu
-- shell merely enumerates this file for its { meta } (ATH_MODE=menu), we must NOT
-- start a loop — we just return the contract below.
if ATH_COMMON.getenv("ATH_MODE", "menu") == "void_collapse" then
    hooks { init = init, destroy = destroy }
end

-- ===========================================================================
-- Menu contract — { meta, config }. The shell can only drive the shared Duel, so
-- this config is a valid Void-themed duel fallback (same cast). The signature
-- mechanic becomes a SHRINKING SAFE RADIUS: a ring of void closes in from the
-- arena's edge and corrodes a hero caught outside it.
-- ===========================================================================

-- Duel collapse — a safe disc centred on the arena that shrinks across the round,
-- then resets each combat phase. The hero is corroded while standing outside it.
local DUEL_R_PAD = 1.5            -- the safe disc starts this far inside the walls
local DUEL_R_FLOOR = 6.0          -- world-units it bottoms out at
local DUEL_SHRINK = 0.55          -- world-units/second the ring closes
local DUEL_VOID_DPS = 22.0        -- corrosion per second outside the ring

local function duel_void_init(D)
    local A = D.arena
    local cx, cy = A.w * 0.5, A.h * 0.5
    local r0 = math.min(A.w, A.h) * 0.5 - DUEL_R_PAD
    D.voidc = { cx = cx, cy = cy, r0 = r0, radius = r0, ring = nil }
    -- A faint floor ring marking the current safe edge (texture-ready prop).
    D.voidc.ring = Art.cylinder("Void_Ring", vec3(cx, 0.03, cy), vec3(r0, 0.04, r0),
        C.edge, D.groups.world, 1.4, "Textures/modes/void_collapse/danger_ring.png")
end

local function duel_void_reset(D)
    if D.voidc then
        D.voidc.radius = D.voidc.r0
        if Art.valid(D.voidc.ring) then D.voidc.ring:set_scale(vec3(D.voidc.r0, 0.04, D.voidc.r0)) end
    end
end

local function duel_void_tick(D, dt)
    local v = D.voidc
    if not v then return end
    v.radius = math.max(DUEL_R_FLOOR, v.radius - DUEL_SHRINK * dt)
    if Art.valid(v.ring) then
        v.ring:set_scale(vec3(v.radius, 0.04, v.radius))
        local pulse = 1.0 + 0.5 * math.sin(D.realtime * 6.0)
        material.set(v.ring, "emissive", vec3(C.edge[1] * pulse, C.edge[2] * pulse, C.edge[3] * pulse))
    end
    -- Corrode the hero while he stands beyond the closing edge.
    local h = D.hero
    if h and not h.dead then
        local dx, dz = h.x - v.cx, h.z - v.cy
        local d = math.sqrt(dx * dx + dz * dz)
        if d > v.radius then
            D:apply_hero_damage(DUEL_VOID_DPS * dt, { ignore_armor = true, flash = "THE VOID CORRODES YOU" })
        end
    end
end

return {
    meta = {
        id = "void_collapse",
        name = "Void Collapse",
        tagline = "the arena that eats itself",
        blurb = "A 2D top-down arena that shrinks. The void closes from all sides — keep to the safe zone or unravel. The Horde surges the collapse and summons within. (Standalone: ATH_MODE=void_collapse. From the menu it runs the duel fallback.)",
        side_hint = "horde",
        accent = { 0.667, 0.0, 1.0, 0.95 },
        minimap = {
            bg = { 0.02, 0.0, 0.04, 1.0 },
            rects = {
                { 0.10, 0.10, 0.80, 0.80, { 0.102, 0.0, 0.20, 1.0 } },  -- the floor
                { 0.30, 0.30, 0.40, 0.40, { 0.267, 0.0, 0.667, 1.0 } }, -- the closing safe zone
                { 0.46, 0.46, 0.08, 0.08, { 0.66, 0.70, 0.78, 1.0 } },  -- hero (centre)
                { 0.40, 0.38, 0.05, 0.05, { 0.667, 0.0, 1.0, 1.0 } },   -- void creatures
                { 0.58, 0.56, 0.05, 0.05, { 1.0, 0.0, 1.0, 1.0 } },
            },
        },
    },

    config = {
        id = "void_collapse",
        name = "Void Collapse",
        theme = VoidC.theme,
        arena = { width = 46, height = 46, pad = 2, ortho_size = 40.0 },
        hero = { hp_max = 110.0, dps = 21.0, cleave = 3, attack_range = 1.25, speed = 2.35, kite_speed = 2.9, actor = VoidC.hero_actor },
        archetypes = VoidC.archetypes,
        roles = VoidC.roles,
        spawn = { interval_start = 0.7, interval_min = 0.3, batch_start = 3, batch_max = 7, cap_start = 30, cap_max = 88, brute_after = 20.0 },
        reserve_start = 320.0,
        round_seconds = 14.0,
        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 11 == 0) then return "void_architect" end
            if D.spawn_counter % 7 == 0 then return "unraveler" end
            if D.spawn_counter % 5 == 0 then return "collapse_echo" end
            return "void_fragment"
        end,
        hooks = {
            on_start = function(D) duel_void_init(D) end,
            on_reset = function(D) duel_void_reset(D) end,
            on_combat_tick = function(D, dt) duel_void_tick(D, dt) end,
            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local r = D.voidc and D.voidc.radius or 0.0
                Art.quad(D.hud, "voidc_ring", 24.0, sh - 150.0, 380.0, 30.0, { 0.08, 0.02, 0.12, 0.85 },
                    { border = { 0.667, 0.0, 1.0, 0.9 }, label = string.format("Safe radius: %.0f", r) })
            end,
        },
    },
}
