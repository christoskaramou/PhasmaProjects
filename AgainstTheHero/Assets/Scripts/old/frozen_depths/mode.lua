-- FROZEN DEPTHS — a 2D SIDE-SCROLLING ice cave, grim and cold, in the Dark-Souls
-- key. Like THE PIT it is its own little GAME: it does NOT run on the shared 3D
-- Duel engine. It is a self-contained, real-time side-scroller drawn entirely on
-- the runtime_ui canvas (the same quad/image API the menu uses), driven by its own
-- update loop. Launch it with ATH_MODE=frozen_depths.
--
-- THE HOOK — ICE PHYSICS. The cave floor is laid in two surfaces: bare ROCK (the
-- hero stops on a dime) and glacier ICE (his momentum carries — he glides, and
-- stopping is hard). Three chambers run west->east, each more iced-over than the
-- last, so the deeper he goes the more he slides. A real Y-up gravity layer rides
-- on top: he can LEAP (to clear floor hazards and the Warden's ground-hugging
-- ice-breath).
--
-- TWO PHASES (mirroring THE PIT):
--   1. PLACEMENT — you are the cave. Pan with A/D and seed up to a budget of
--      monsters/hazards down the corridor: Ice Wights (melee, freeze trail), Frost
--      Archers (slow-on-hit bolts), Ice Walls (breakable blockers), Freeze Traps
--      (floor patches). Pick which hero gets thrown in. [Enter] releases him.
--   2. COMBAT — you then DRIVE that hero (A/D run, W/Up leap, Space swing) west->
--      east to the breach. Freeze Traps shimmer (0.8s) then FREEZE him solid (2s).
--      Ice Walls must be smashed. The GLACIAL WARDEN garrisons chamber 3 — a
--      mountain of ice that breathes a freezing cone and trails frost as it walks.
--      Slay it to drop the ice gate, then reach the breach alive.
--
-- All art is from tools/gen_textures_frozen.py and OPTIONAL — a missing PNG just
-- falls back to a flat silhouette colour, so the game still runs. Physics is hand-
-- rolled 2D side-scroll: run/slide friction by surface, gravity-arc jump, ballistic
-- bolts, breakable-wall and sealed-gate clamps.
--
-- This file ALSO returns { meta, config } at the bottom so the mode is discover-
-- able from the battlefield menu; that path can only run the shared Duel, so it
-- falls back to a valid Frozen-themed duel (same cast; Freeze Traps become the
-- floor hazard that freezes the hero where he stands).

local Art    = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Frozen = ATH_COMMON.load_script("Scripts/modes/frozen_depths/characters.lua", "frozen_depths characters", _ENV)

local DATA = Frozen.frozen2d
local C = DATA.palette

-- ===========================================================================
-- The 2D game
-- ===========================================================================

local SCREEN = "ath.frozen_depths"
local UPDATE_ID = "against_the_hero_frozen"

local GRAVITY = DATA.physics.gravity
local JUMP_APEX = DATA.physics.jump_apex
local JUMP_CLEAR = 1.0                 -- above this height the hero clears a floor hazard

local Game = {
    phase = "placement",               -- "placement" | "combat" | "won" | "lost"
    key_down = {},
    entities = {},                     -- wights / archers / walls / traps released into the cave
    projectiles = {},                  -- frost bolts in flight
    trails = {},                       -- freeze-trail patches (wight / warden wake)
    bloods = {},                       -- blood-on-ice decals (world-anchored, fading)
    placed = {},                       -- entries during placement: { id, x }
    icicles = {},                      -- ceiling stalactites (fixed dressing)
    floor = {},                        -- typed floor tiles (stone / ice)
    warden = nil,
    sel_horde = "ice_wight",
    sel_hero = "forge_walker",
    budget = 0,
    gate_sealed = true,
    time = 0.0,
    place_focus = 0.0,                 -- camera x while panning the cave in placement
    flash = "", flash_t = 0.0, last_flash = nil,
    director = { wall_t = 9.0, trap_t = 6.0 },   -- mid-combat horde deployments
    cam = { ox = 0.0, oy = 0.0, cx = 0.0, ppu = 24.0 },
    _live = {}, _prev = {},
    next_id = 0,
}

-- ---- small helpers ---------------------------------------------------------

local function log(msg) if pe_log then pe_log("[ATH:FROZEN] " .. tostring(msg)) end end

local function clampn(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function len2(x, y) return math.sqrt(x * x + y * y) end
local function sign(v) if v > 0 then return 1.0 elseif v < 0 then return -1.0 else return 0.0 end end

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

-- Cursor in surface pixels (mirrors THE PIT's nil-safe probe order).
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

-- A handy convenience: the leftmost-pressed horizontal axis (-1 / 0 / +1).
local function move_axis()
    local ix = (key_down("D") or key_down("Right")) and 1.0 or 0.0
    ix = ix - ((key_down("A") or key_down("Left")) and 1.0 or 0.0)
    return ix
end

-- ---- world <-> screen (side-on; +y is UP, camera scrolls in x) -------------

local function recompute_cam()
    local sw, sh = Art.surface_size()
    local A = DATA.arena
    -- Fit the cave's vertical span between the top banner and the bottom HUD.
    Game.cam.ppu = clampn((sh - 230.0) / A.height, 12.0, 38.0)
    Game.cam.ox = sw * 0.5
    Game.cam.oy = sh - 150.0                 -- the floor line sits here
    -- Track target: the hero in combat, the pan focus in placement.
    local target = (Game.phase == "combat" and Game.hero) and Game.hero.x or Game.place_focus
    local half = (sw * 0.5) / Game.cam.ppu
    local minx, maxx = half, A.length - half
    if maxx < minx then
        Game.cam.cx = A.length * 0.5
    else
        Game.cam.cx = clampn(target, minx, maxx)
    end
    return sw, sh
end

local function w2s(wx, wy)
    local c = Game.cam
    return c.ox + (wx - c.cx) * c.ppu, c.oy - wy * c.ppu
end

local function s2w(sx, sy)
    local c = Game.cam
    return c.cx + (sx - c.ox) / c.ppu, (c.oy - sy) / c.ppu
end

-- ---- canvas draw (records ids so stale ones get swept each frame) ----------

local function draw(id, x, y, w, h, fill, opts)
    Game._live[id] = true
    Art.quad(SCREEN, id, x, y, w, h, fill, opts)
end

-- A world-anchored sprite centred on (wx, wy): a faint solid core (so it reads
-- even with no art) plus the textured quad on top. size is in world units.
local function draw_sprite(id, wx, wy, size, image, color, opts)
    opts = opts or {}
    local ppu = Game.cam.ppu
    local px = size * ppu
    local sx, sy = w2s(wx, wy)
    local cs = px * 0.5
    draw(id .. "_core", sx - cs * 0.5, sy - cs * 0.5, cs, cs,
        { color[1], color[2], color[3], opts.core_alpha or 0.8 }, { no_input = true })
    draw(id, sx - px * 0.5, sy - px * 0.5, px, px, { 0, 0, 0, 0 },
        { image = image, no_input = true, image_tint = opts.tint })
end

-- ---- arena geometry --------------------------------------------------------

-- A cheap deterministic hash so the ice/stone pattern is byte-stable across runs
-- (no math.random — the tile layout must be identical every time, like THE PIT's
-- seeded textures).
local function tile_hash(i)
    local h = (i * 2654435761) % 100003
    return (h % 1000) / 1000.0
end

local function chamber_of(x)
    local seg = DATA.arena.length / DATA.arena.chambers
    local c = math.floor(x / seg) + 1
    return clampn(c, 1, DATA.arena.chambers)
end

local function build_floor()
    Game.floor = {}
    local A = DATA.arena
    local n = math.floor(A.length / A.tile + 0.5)
    for i = 1, n do
        local cx = (i - 0.5) * A.tile
        local ch = chamber_of(cx)
        local density = A.ice_density[ch] or 0.3
        -- The mouth (first two tiles) is always solid rock — a fair launch pad.
        local ice = (i > 2) and (tile_hash(i) < density) or false
        Game.floor[i] = { i = i, x = cx, ice = ice, chamber = ch, seed = tile_hash(i * 7) }
    end
end

-- Is the floor under world-x ICE? (drives the hero's slide and the wight trail.)
local function ice_at(x)
    local A = DATA.arena
    local idx = math.floor(x / A.tile) + 1
    local t = Game.floor[idx]
    return t and t.ice or false
end

local function build_icicles()
    Game.icicles = {}
    local A = DATA.arena
    local i = 0
    local x = 3.0
    while x < A.length - 2.0 do
        i = i + 1
        -- Deeper chambers bristle with more ice overhead.
        local ch = chamber_of(x)
        local len = 1.2 + (ch - 1) * 0.5 + tile_hash(i * 13) * 1.4
        Game.icicles[i] = { x = x, len = len, seed = tile_hash(i * 17) }
        x = x + 4.0 - (ch - 1) * 0.8 + tile_hash(i * 5) * 2.0
    end
end

-- ---- blood-on-ice decals ---------------------------------------------------

local function add_blood(wx, big)
    Game.next_id = Game.next_id + 1
    Game.bloods[#Game.bloods + 1] = {
        id = "blood_" .. Game.next_id, x = wx,
        size = (big and 2.2 or 1.3) + tile_hash(Game.next_id) * 0.4, life = 6.0,
    }
end

-- ---- freeze-trail patches (wight / warden wake) ----------------------------

local function add_trail(wx, life, slow, freeze)
    Game.next_id = Game.next_id + 1
    Game.trails[#Game.trails + 1] = {
        id = "trail_" .. Game.next_id, x = wx, life = life, life_max = life,
        slow = slow, freeze = freeze or 0.0,
    }
end

-- ---------------------------------------------------------------------------
-- Hero — gravity-arc physics + ICE-SLIDE friction by surface.
-- ---------------------------------------------------------------------------

local function spawn_hero()
    local def = DATA.heroes[Game.sel_hero]
    local sp = DATA.arena.hero_spawn
    Game.hero = {
        def = def, x = sp.x, y = 0.0, vx = 0.0, vy = 0.0,
        on_ground = true, facing = 1.0,
        hp = def.hp, hp_max = def.hp,
        phase = 0.0, moving = false,
        attack_cd = 0.0, attack_flash = 0.0,
        hit_flash = 0.0, dead = false,
        frozen_t = 0.0,                 -- seconds locked in ice (can't act)
        slow_t = 0.0, slow_mult = 1.0,  -- rime slow from frost bolts / trails
    }
end

local function hero_take_damage(amount, what)
    local h = Game.hero
    if not h or h.dead or amount <= 0.0 then return end
    h.hp = h.hp - amount
    h.hit_flash = 0.18
    add_blood(h.x, false)
    if h.hp <= 0.0 then
        h.hp = 0.0; h.dead = true
        Game.phase = "lost"
        set_flash("YOU DIED")
        add_blood(h.x, true)
        log("hero slain by " .. tostring(what or "the cold"))
    end
end

-- Freeze the hero in place. Forge Walker's ember melts it faster (melt_mult).
local function hero_freeze(seconds, what)
    local h = Game.hero
    if not h or h.dead then return end
    local t = seconds * (h.def.melt_mult or 1.0)
    if t > h.frozen_t then
        h.frozen_t = t
        h.vx = 0.0
        set_flash("FROZEN" .. (what and (" — " .. what) or "") .. "!")
        Art.burst("ath_frozen_freeze_" .. Game.next_id, vec3(0, 0, 0), { count = 0 })  -- no-op guard for nil scene
    end
end

local function hero_slow(mult, seconds)
    local h = Game.hero
    if not h or h.dead then return end
    h.slow_t = math.max(h.slow_t, seconds)
    h.slow_mult = math.min(h.slow_mult, mult)
end

-- Clamp the hero out of any solid ice wall (and the sealed exit gate) along x.
local function resolve_walls(h)
    for _, e in ipairs(Game.entities) do
        if e.alive and e.kind == "wall" then
            local half = e.def.wall_w * 0.5 + h.def.radius
            if h.y < e.def.wall_h and math.abs(h.x - e.x) < half then
                if h.x < e.x then h.x = e.x - half else h.x = e.x + half end
                h.vx = 0.0
            end
        end
    end
    -- The exit gate is a solid wall of ice until the Warden falls.
    if Game.gate_sealed then
        local gx = DATA.arena.exit.x
        local half = 1.0 + h.def.radius
        if h.x > gx - half - 1.0 then h.x = gx - half - 1.0; if h.vx > 0 then h.vx = 0.0 end end
    end
end

local function hero_attack()
    local h = Game.hero
    h.attack_cd = h.def.attack_cd
    h.attack_flash = 0.14
    local reach = h.def.attack_range + h.def.radius
    -- A swing in the facing direction (plus a little behind, forgiving).
    for _, e in ipairs(Game.entities) do
        if e.alive and e.kind ~= "trap" then
            local dx = e.x - h.x
            local fwd = (dx * h.facing >= -0.4)
            if fwd and math.abs(dx) <= reach + (e.def.radius or 0.5) then
                e.hp = e.hp - h.def.attack_damage
                e.hit_flash = 0.18
                add_blood(e.x, false)
                if e.hp <= 0.0 then
                    e.alive = false
                    add_blood(e.x, true)
                    if e.kind == "wall" then set_flash("THE WALL SHATTERS") end
                end
            end
        end
    end
    -- And a blow on the Warden if he is in reach.
    local W = Game.warden
    if W and W.alive then
        local dx = W.x - h.x
        if dx * h.facing >= -0.6 and math.abs(dx) <= reach + W.def.radius then
            W.hp = W.hp - h.def.attack_damage
            W.hit_flash = 0.18
            add_blood(h.x + h.facing * 1.0, false)
            if W.hp <= 0.0 and W.alive then
                W.alive = false
                Game.gate_sealed = false
                set_flash("THE WARDEN FALLS — THE GATE BREAKS")
                add_blood(W.x, true)
                log("glacial warden slain")
            end
        end
    end
end

local function update_hero(dt)
    local h = Game.hero
    if not h then return end
    local A = DATA.arena
    h.attack_cd = math.max(0.0, h.attack_cd - dt)
    h.hit_flash = math.max(0.0, h.hit_flash - dt)
    h.attack_flash = math.max(0.0, h.attack_flash - dt)

    -- Rime slow decays back to full speed.
    h.slow_t = math.max(0.0, h.slow_t - dt)
    if h.slow_t <= 0.0 then h.slow_mult = 1.0 end

    if h.dead then return end

    -- FROZEN SOLID: he can't act. The cold ticks down (the Forge Walker's ember
    -- already shortened it in hero_freeze). He is a sitting target.
    if h.frozen_t > 0.0 then
        h.frozen_t = math.max(0.0, h.frozen_t - dt)
        h.vx = 0.0
        h.moving = false
        return
    end

    local on_ice = h.def.slips and ice_at(h.x)     -- Ice Born never slips
    local max_speed = h.def.speed * h.slow_mult
    local ix = move_axis()
    h.moving = ix ~= 0.0
    if ix ~= 0.0 then h.facing = ix end

    -- Horizontal: accelerate toward input; bleed speed by surface friction. On ICE
    -- the bleed is gentle (momentum carries — hard to stop); on ROCK it's sharp.
    if ix ~= 0.0 then
        local accel = h.def.accel * (on_ice and 0.45 or 1.0)   -- ice gives poor grip to push off
        h.vx = h.vx + ix * accel * dt
    else
        local k = on_ice and 1.4 or 12.0
        h.vx = h.vx - h.vx * math.min(1.0, k * dt)
    end
    h.vx = clampn(h.vx, -max_speed, max_speed)

    -- Jump (W / Up): a gravity-arc leap from the floor.
    if h.on_ground and (key_pressed("W") or key_pressed("Up")) then
        h.vy = math.sqrt(2.0 * GRAVITY * JUMP_APEX)
        h.on_ground = false
    end

    -- Integrate gravity + position.
    h.vy = h.vy - GRAVITY * dt
    h.y = h.y + h.vy * dt
    if h.y <= 0.0 then h.y = 0.0; h.vy = 0.0; h.on_ground = true end
    h.x = h.x + h.vx * dt
    h.x = clampn(h.x, A.pad or 1.0, A.length - 1.0)
    resolve_walls(h)
    if h.moving and h.on_ground then h.phase = h.phase + dt * h.def.walk_freq end

    -- Attack (Space / J / K).
    if (key_pressed("Space") or key_pressed("J") or key_pressed("K")) and h.attack_cd <= 0.0 then
        hero_attack()
    end

    -- Freeze-trail patches underfoot (only while grounded — leap to skip them).
    if h.on_ground then
        for _, tr in ipairs(Game.trails) do
            if math.abs(h.x - tr.x) <= 1.0 then
                hero_slow(tr.slow, 0.6)
                if tr.freeze and tr.freeze > 0.0 then hero_freeze(tr.freeze, "frost trail") end
            end
        end
    end

    -- Reached the breach? (only once the gate is broken)
    if not Game.gate_sealed then
        local ex = DATA.arena.exit.x
        if math.abs(h.x - ex) <= DATA.arena.exit_radius then
            Game.phase = "won"
            set_flash("YOU ESCAPE THE FROZEN DEPTHS")
            log("hero escaped")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Monsters / hazards
-- ---------------------------------------------------------------------------

local function spawn_entity(kind, def, x)
    Game.next_id = Game.next_id + 1
    return {
        id = "ent_" .. Game.next_id, kind = kind, def = def,
        x = x, y = 0.0, hp = def.hp or 1.0, hp_max = def.hp or 1.0, alive = true,
        seed = tile_hash(Game.next_id) * 6.28, hit_flash = 0.0,
        cd = 0.0, trail_cd = 0.0, moving = false,
        trap_phase = "armed", trap_t = 0.0,    -- traps only
    }
end

-- ICE WIGHT — shamble at the hero on the floor; bite on contact; leave a trail.
local function update_wight(e, dt, h)
    local dx = h.x - e.x
    local d = math.abs(dx)
    if d > e.def.radius + h.def.radius + 0.1 then
        e.x = e.x + sign(dx) * e.def.speed * dt
        e.moving = true
    else
        e.moving = false
    end
    -- Drop a freezing trail patch as it walks.
    e.trail_cd = e.trail_cd - dt
    if e.moving and e.trail_cd <= 0.0 then
        e.trail_cd = e.def.trail_cd
        add_trail(e.x, e.def.trail_life, e.def.trail_slow, 0.0)
    end
    -- Contact bite.
    e.cd = math.max(0.0, e.cd - dt)
    if d <= e.def.radius + h.def.radius + 0.2 and not h.dead and e.cd <= 0.0 then
        e.cd = e.def.touch_cd
        hero_take_damage(e.def.touch_damage, "an Ice Wight")
    end
end

-- FROST ARCHER — hold a distance and loose a ballistic bolt that leads the runner.
local function shoot_bolt(e, h)
    local pj = e.def.projectile
    local ex, ey = e.x, 1.0
    -- Lead the hero's run a little so a moving target is harder to dodge.
    local tx = h.x + h.vx * 0.25
    local ty = h.y + 0.6
    local dx = tx - ex
    local T = math.max(0.4, math.abs(dx) / (pj.speed or 14.0))
    local vx = dx / T
    local vy = (ty - ey + 0.5 * pj.gravity * T * T) / T   -- ballistic launch
    Game.next_id = Game.next_id + 1
    Game.projectiles[#Game.projectiles + 1] = {
        id = "proj_" .. Game.next_id, x = ex, y = ey, vx = vx, vy = vy,
        g = pj.gravity, dmg = pj.damage, hit_r = pj.hit_radius, size = pj.size,
        slow_mult = pj.slow_mult, slow_time = pj.slow_time,
    }
end

local function update_archer(e, dt, h)
    local dx = h.x - e.x
    local d = math.abs(dx)
    local dir = 0.0
    if d < (e.def.retreat_range or 7.0) then dir = -1.0          -- too close: back off
    elseif d > (e.def.hold_range or 16.0) then dir = 1.0 end     -- too far: close in
    if dir ~= 0.0 then
        e.x = e.x + sign(dx) * dir * e.def.speed * dt
        e.moving = true
    else
        e.moving = false
    end
    e.cd = math.max(0.0, e.cd - dt)
    if e.cd <= 0.0 and d <= (e.def.hold_range or 16.0) + 1.0 and not h.dead then
        e.cd = e.def.shoot_cd
        shoot_bolt(e, h)
    end
end

-- FREEZE TRAP — arm -> shimmer telegraph (0.8s) -> freeze the hero (2s) -> rearm.
local function update_trap(e, dt, h)
    e.trap_t = e.trap_t + dt
    local over = math.abs(h.x - e.x) <= e.def.trigger_radius and h.on_ground and not h.dead
    if e.trap_phase == "armed" then
        if over then e.trap_phase = "telegraph"; e.trap_t = 0.0 end
    elseif e.trap_phase == "telegraph" then
        if e.trap_t >= e.def.telegraph then
            e.trap_phase = "active"; e.trap_t = 0.0
            if math.abs(h.x - e.x) <= e.def.radius + h.def.radius and h.on_ground then
                hero_freeze(e.def.freeze_time, "freeze trap")
            end
        end
    elseif e.trap_phase == "active" then
        if e.trap_t >= 0.5 then e.trap_phase = "cooldown"; e.trap_t = 0.0 end
    elseif e.trap_phase == "cooldown" then
        if e.trap_t >= e.def.rearm then e.trap_phase = "armed"; e.trap_t = 0.0 end
    end
end

local function update_entities(dt)
    local h = Game.hero
    local survivors = {}
    for _, e in ipairs(Game.entities) do
        e.hit_flash = math.max(0.0, e.hit_flash - dt)
        if e.alive then
            if e.kind == "wight" then update_wight(e, dt, h)
            elseif e.kind == "archer" then update_archer(e, dt, h)
            elseif e.kind == "trap" then update_trap(e, dt, h)
            -- walls just stand there (collision handled in resolve_walls)
            end
        end
        if e.alive then survivors[#survivors + 1] = e
        else Game._live[e.id] = nil; Game._live[e.id .. "_core"] = nil end
    end
    Game.entities = survivors
end

local function update_projectiles(dt)
    local h = Game.hero
    local survivors = {}
    for _, p in ipairs(Game.projectiles) do
        p.vy = p.vy - p.g * dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        local hit, gone = false, false
        if h and not h.dead then
            local dx, dy = h.x - p.x, (h.y + 0.7) - p.y
            if dx * dx + dy * dy <= (p.hit_r + h.def.radius) * (p.hit_r + h.def.radius) then
                hero_take_damage(p.dmg, "a frost bolt")
                hero_slow(p.slow_mult, p.slow_time)
                hit = true
            end
        end
        if p.y <= 0.0 then gone = true end                  -- buried in the floor
        if p.x < 0.0 or p.x > DATA.arena.length then gone = true end
        if hit or gone then
            Game._live[p.id] = nil; Game._live[p.id .. "_core"] = nil
            Game._live[p.id .. "_sh"] = nil
        else
            survivors[#survivors + 1] = p
        end
    end
    Game.projectiles = survivors
end

local function update_trails(dt)
    local survivors = {}
    for _, tr in ipairs(Game.trails) do
        tr.life = tr.life - dt
        if tr.life > 0.0 then survivors[#survivors + 1] = tr
        else Game._live[tr.id] = nil; Game._live[tr.id .. "_core"] = nil end
    end
    Game.trails = survivors
end

-- ---------------------------------------------------------------------------
-- The Glacial Warden — chamber-3 boss. Approach (freeze trail) -> ICE-BREATH
-- CONE (telegraph -> exhale, freezes anything grounded in it) -> cooldown.
-- ---------------------------------------------------------------------------

local function spawn_warden()
    local def = DATA.boss
    Game.warden = {
        def = def, x = DATA.arena.warden_x, y = 0.0, facing = -1.0,
        hp = def.hp, hp_max = def.hp, alive = true, hit_flash = 0.0,
        seed = 1.7, cd = 0.0, trail_cd = 0.0,
        phase = "idle", phase_t = 0.0, breath_cd = def.breath_cd * 0.5,
    }
end

local function update_warden(dt)
    local W = Game.warden
    local h = Game.hero
    if not W or not W.alive or not h then return end
    W.hit_flash = math.max(0.0, W.hit_flash - dt)
    local def = W.def
    local dx = h.x - W.x
    local d = math.abs(dx)
    W.facing = (dx >= 0.0) and 1.0 or -1.0
    W.breath_cd = math.max(0.0, W.breath_cd - dt)
    W.cd = math.max(0.0, W.cd - dt)
    W.phase_t = W.phase_t + dt

    -- Contact crush.
    if d <= def.radius + h.def.radius and not h.dead and W.cd <= 0.0 then
        W.cd = def.contact_cd
        hero_take_damage(def.contact_damage, "the Warden")
        h.vx = -W.facing * 8.0            -- bludgeoned back
    end

    if W.phase == "idle" or W.phase == "approach" then
        -- Lumber toward the hero, trailing freezing ground.
        if d > def.radius + h.def.radius + 0.5 then
            W.x = W.x + W.facing * def.speed * dt
            W.trail_cd = W.trail_cd - dt
            if W.trail_cd <= 0.0 then
                W.trail_cd = def.trail_cd
                add_trail(W.x - W.facing * 1.4, def.trail_life, def.trail_slow, def.trail_freeze)
            end
        end
        -- Commit to an ice-breath when the hero is in range and it's off cooldown.
        if d <= def.breath_range and W.breath_cd <= 0.0 then
            W.phase = "breath_warn"; W.phase_t = 0.0
        else
            W.phase = "approach"
        end
    elseif W.phase == "breath_warn" then
        -- Rear back: the maw glows and the cone shimmers as a warning.
        if W.phase_t >= def.breath_telegraph then
            W.phase = "breath_fire"; W.phase_t = 0.0
        end
    elseif W.phase == "breath_fire" then
        -- Exhale: a ground-hugging cone of frost. Grounded hero caught in it takes
        -- heavy damage and freezes (leap above breath_height to clear it).
        local x0 = W.x + W.facing * def.radius
        local x1 = x0 + W.facing * def.breath_length
        local lo, hi = math.min(x0, x1), math.max(x0, x1)
        if not h.dead and h.x >= lo and h.x <= hi and h.y < def.breath_height then
            hero_take_damage(def.breath_dps * dt, "ice breath")
            hero_freeze(def.breath_freeze, "ice breath")
        end
        if W.phase_t >= def.breath_active then
            W.phase = "approach"; W.phase_t = 0.0; W.breath_cd = def.breath_cd
        end
    end
    W.x = clampn(W.x, 3.0, DATA.arena.length - 3.0)
end

-- ---------------------------------------------------------------------------
-- The Horde "director" — deploys ice walls and arms freeze traps MID-COMBAT,
-- always ahead of the hero and biased to the icier deep chambers.
-- ---------------------------------------------------------------------------

local function count_kind(kind)
    local n = 0
    for _, e in ipairs(Game.entities) do if e.alive and e.kind == kind then n = n + 1 end end
    return n
end

local function update_director(dt)
    local h = Game.hero
    if not h or h.dead then return end
    local A = DATA.arena
    local d = Game.director
    -- A fresh ice wall thrown down ahead of the hero (capped, never on the gate).
    d.wall_t = d.wall_t - dt
    if d.wall_t <= 0.0 then
        d.wall_t = 9.0 + tile_hash(Game.next_id) * 4.0
        if count_kind("wall") < 4 then
            local wx = clampn(h.x + 7.0 + tile_hash(Game.time * 10) * 4.0, 6.0, A.length - 6.0)
            if math.abs(wx - A.exit.x) > 4.0 then
                local def = DATA.horde.ice_wall
                Game.entities[#Game.entities + 1] = spawn_entity("wall", def, wx)
                set_flash("AN ICE WALL RISES")
            end
        end
    end
    -- A freeze trap armed in the hero's path.
    d.trap_t = d.trap_t - dt
    if d.trap_t <= 0.0 then
        d.trap_t = 6.0 + tile_hash(Game.next_id * 3) * 4.0
        if count_kind("trap") < 5 then
            local tx = clampn(h.x + 5.0 + tile_hash(Game.time * 7) * 5.0, 5.0, A.length - 4.0)
            local def = DATA.horde.freeze_trap
            Game.entities[#Game.entities + 1] = spawn_entity("trap", def, tx)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Placement phase
-- ---------------------------------------------------------------------------

local function can_place(wx)
    local A = DATA.arena
    if wx < 6.0 or wx > A.length - 4.0 then return false end
    if math.abs(wx - A.hero_spawn.x) < 4.0 then return false end
    if math.abs(wx - A.exit.x) < 4.0 then return false end
    if math.abs(wx - A.warden_x) < 5.0 then return false end   -- keep the Warden's berth clear
    for _, pe in ipairs(Game.placed) do
        if math.abs(wx - pe.x) < 1.6 then return false end
    end
    return true
end

local function release_hero()
    Game.entities = {}
    for _, pe in ipairs(Game.placed) do
        local def = DATA.horde[pe.id]
        Game.entities[#Game.entities + 1] = spawn_entity(def.kind, def, pe.x)
    end
    spawn_warden()
    spawn_hero()
    Game.projectiles = {}
    Game.trails = {}
    Game.bloods = {}
    Game.gate_sealed = true
    Game.director = { wall_t = 9.0, trap_t = 6.0 }
    Game.time = 0.0
    Game.phase = "combat"
    set_flash("DESCEND  —  reach the breach alive")
    log("released " .. tostring(Game.sel_hero) .. " vs " .. tostring(#Game.entities) .. " placed + the Warden")
end

local function reset_game()
    Game.placed = {}
    Game.entities = {}
    Game.projectiles = {}
    Game.trails = {}
    Game.bloods = {}
    Game.warden = nil
    Game.budget = DATA.placement.budget
    Game.gate_sealed = true
    Game.phase = "placement"
    Game.hero = nil
    Game.place_focus = DATA.arena.length * 0.5
    Game.time = 0.0
    set_flash("BUILD THE DESCENT  -  place up to " .. tostring(Game.budget))
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local function draw_world(sw, sh)
    -- A deep, cold gradient backdrop (two bands).
    draw("bg", 0, 0, sw, sh, { C.deep[1], C.deep[2], C.deep[3], 1.0 }, { no_input = true })
    local horizon = select(2, w2s(0, DATA.arena.ceiling_y * 0.5))
    draw("bg_lo", 0, horizon, sw, sh - horizon, { C.cave_lo[1], C.cave_lo[2], C.cave_lo[3], 1.0 }, { no_input = true })

    local ppu = Game.cam.ppu
    local A = DATA.arena

    -- The cave back wall (a dim band behind the floor).
    local wy_top = select(2, w2s(0, A.ceiling_y))
    local wy_floor = select(2, w2s(0, 0))
    draw("wall_band", 0, wy_top, sw, wy_floor - wy_top, { C.cave[1], C.cave[2], C.cave[3], 1.0 }, { no_input = true })

    -- Floor tiles: stone or ice. Only draw those near the view for cheapness.
    local tile_px = A.tile * ppu
    local left_w = s2w(-tile_px, 0)
    local right_w = s2w(sw + tile_px, 0)
    for _, t in ipairs(Game.floor) do
        if t.x >= left_w - A.tile and t.x <= right_w + A.tile then
            local sx, sy = w2s(t.x, 0)
            local col = t.ice and C.ice_lo or C.stone
            draw("fl_" .. t.i, sx - tile_px * 0.5, sy, tile_px + 1.0, tile_px * 1.2,
                { col[1], col[2], col[3], 1.0 },
                { image = t.ice and DATA.sprites.floor_ice or DATA.sprites.floor_stone, no_input = true })
            -- A bright shine streak on ice so the slick surface reads.
            if t.ice then
                draw("fls_" .. t.i, sx - tile_px * 0.3, sy + tile_px * 0.15, tile_px * 0.5, 2.0,
                    { C.bright[1], C.bright[2], C.bright[3], 0.35 }, { no_input = true })
            end
        end
    end

    -- Chamber boundary markers (faint frost pillars) + labels via HUD elsewhere.
    for ch = 1, A.chambers - 1 do
        local bx = ch * (A.length / A.chambers)
        local sx, syt = w2s(bx, A.ceiling_y)
        local _, syb = w2s(bx, 0)
        draw("chdiv_" .. ch, sx - 2.0, syt, 4.0, syb - syt, { C.cave_lo[1], C.cave_lo[2], C.cave_lo[3], 0.6 }, { no_input = true })
    end

    -- Hanging icicles along the ceiling.
    for i, ic in ipairs(Game.icicles) do
        if ic.x >= left_w - 2.0 and ic.x <= right_w + 2.0 then
            local sx, sy = w2s(ic.x, A.ceiling_y)
            local px = ic.len * ppu
            draw("ic_" .. i, sx - px * 0.18, sy, px * 0.36, px, { 0, 0, 0, 0 },
                { image = DATA.sprites.icicle, no_input = true })
        end
    end
end

local function draw_trails()
    for _, tr in ipairs(Game.trails) do
        local a = clampn(tr.life / tr.life_max, 0.0, 1.0)
        local sx, sy = w2s(tr.x, 0)
        local ppu = Game.cam.ppu
        local pw = 1.8 * ppu
        local col = (tr.freeze and tr.freeze > 0.0) and C.frost or C.bright
        draw("trailq_" .. (tr.id), sx - pw * 0.5, sy + 1.0, pw, ppu * 0.4,
            { col[1], col[2], col[3], 0.28 * a }, { image = DATA.sprites.frost, no_input = true })
    end
end

local function draw_bloods(dt)
    local survivors = {}
    for _, b in ipairs(Game.bloods) do
        b.life = b.life - dt
        if b.life > 0.0 then
            survivors[#survivors + 1] = b
            local a = clampn(b.life / 6.0, 0.0, 0.8)
            local sx, sy = w2s(b.x, 0)
            local px = b.size * Game.cam.ppu
            draw(b.id, sx - px * 0.5, sy + 1.0, px, px * 0.5, { C.blood[1], C.blood[2], C.blood[3], a * 0.55 },
                { image = DATA.sprites.blood, no_input = true })
        else
            Game._live[b.id] = nil
        end
    end
    Game.bloods = survivors
end

-- The sealed exit gate (a wall of ice) / the open breach once the Warden falls.
local function draw_gate()
    local A = DATA.arena
    local sx, sy = w2s(A.exit.x, 0)
    local ppu = Game.cam.ppu
    if Game.gate_sealed then
        local gh = 6.0 * ppu
        draw("gate", sx - 1.2 * ppu, sy - gh, 2.4 * ppu, gh, { C.ice[1], C.ice[2], C.ice[3], 0.92 },
            { image = DATA.sprites.gate, no_input = true })
    else
        -- The breach: a cold daylight glow beyond the broken gate.
        local pulse = 0.5 + 0.4 * math.sin(Game.time * 3.0)
        local gh = 6.0 * ppu
        draw("breach", sx - 1.6 * ppu, sy - gh, 3.2 * ppu, gh, { C.bright[1], C.bright[2], C.bright[3], 0.18 + 0.12 * pulse },
            { no_input = true })
        draw("breach_lbl", sx - 60, sy - gh - 26, 120, 24, { 0, 0, 0, 0 },
            { label = "BREACH", text_color = { C.bright[1], C.bright[2], C.bright[3], pulse }, no_input = true })
    end
end

local function entity_frame(e)
    local def = e.def
    if def.frames then
        local frames = DATA.sprites[def.frames]
        if frames then
            local fps = def.anim_fps or 7.0
            local n = #frames
            local fr = (math.floor(Game.time * fps + e.seed) % n) + 1
            return frames[fr]
        end
    end
    return def.sprite
end

local function draw_entities()
    for _, e in ipairs(Game.entities) do
        local def = e.def
        if e.kind == "wall" then
            -- A breakable slab: height/colour fade with remaining HP so damage reads.
            local ppu = Game.cam.ppu
            local sx, sy = w2s(e.x, 0)
            local wh = def.wall_h * ppu
            local ww = def.wall_w * ppu
            local frac = clampn(e.hp / (e.hp_max or def.hp), 0.0, 1.0)
            local col = e.hit_flash > 0.0 and C.frost or C.ice
            draw(e.id, sx - ww * 0.6, sy - wh, ww * 1.2, wh,
                { col[1], col[2], col[3], 0.45 + 0.45 * frac },
                { image = DATA.sprites.ice_wall, no_input = true, border = { C.bright[1], C.bright[2], C.bright[3], 0.5 } })
        elseif e.kind == "trap" then
            -- Floor patch; the 3-frame shimmer plays only during the telegraph.
            local frames = DATA.sprites.trap_frames
            local img = frames and frames[1] or nil
            local tint = nil
            if e.trap_phase == "telegraph" then
                local fr = (math.floor(Game.time * 14.0) % 3) + 1
                img = frames and frames[fr] or img
                tint = { C.frost[1], C.frost[2], C.frost[3], 0.5 + 0.5 * math.sin(Game.time * 26.0) }
            elseif e.trap_phase == "active" then
                tint = { C.bright[1], C.bright[2], C.bright[3], 0.85 }
            end
            local ppu = Game.cam.ppu
            local sx, sy = w2s(e.x, 0)
            local px = def.size * ppu
            draw(e.id, sx - px * 0.5, sy - px * 0.18, px, px * 0.5, { def.color[1], def.color[2], def.color[3], 0.5 },
                { image = img, no_input = true, image_tint = tint })
        else
            -- Wights / archers: a swaying animated silhouette standing on the floor.
            local sway = (def.sway_amp or 0.0) * math.sin(Game.time * (def.sway_freq or 3.0) + e.seed)
            local col = e.hit_flash > 0.0 and { 1.0, 0.6, 0.6 } or def.color
            local img = entity_frame(e)
            draw_sprite(e.id, e.x, def.size * 0.5 + sway, def.size, img, col, {})
        end
    end
end

local function draw_warden()
    local W = Game.warden
    if not W or not W.alive then return end
    local def = W.def
    local frames = DATA.sprites[def.frames]
    local fps = def.anim_fps or 6.0
    local img = nil
    if frames then img = frames[(math.floor(Game.time * fps + W.seed) % #frames) + 1] end
    local ppu = Game.cam.ppu

    -- Ice-breath cone (telegraph shimmer, then a solid frost wedge).
    if W.phase == "breath_warn" or W.phase == "breath_fire" then
        local x0 = W.x + W.facing * def.radius
        local length = def.breath_length
        local warn = (W.phase == "breath_warn")
        local p = warn and clampn(W.phase_t / def.breath_telegraph, 0.0, 1.0) or 1.0
        local sx0, sy0 = w2s(x0, 0)
        local hpx = def.breath_height * ppu
        local lpx = length * ppu * p
        local col = warn and C.bright or C.frost
        local a = warn and (0.12 + 0.18 * math.sin(Game.time * 24.0)) or 0.55
        local x = (W.facing > 0) and sx0 or (sx0 - lpx)
        draw("warden_breath", x, sy0 - hpx, lpx, hpx, { col[1], col[2], col[3], a }, { no_input = true })
    end

    -- Body — a huge ice giant. Flash white on a hit.
    local col = W.hit_flash > 0.0 and C.frost or def.color
    local cy = def.height * 0.5
    local px = def.size * ppu
    local sx, sy = w2s(W.x, cy)
    draw("warden_core", sx - px * 0.22, sy - px * 0.22, px * 0.44, px * 0.44,
        { col[1], col[2], col[3], 0.85 }, { no_input = true })
    draw("warden", sx - px * 0.5, sy - px * 0.5, px, px, { 0, 0, 0, 0 },
        { image = img, no_input = true })
    -- A boss health pip above his crown.
    local frac = clampn(W.hp / W.hp_max, 0.0, 1.0)
    local bw = px * 0.9
    draw("warden_hp_bg", sx - bw * 0.5, sy - px * 0.62, bw, 8.0, { 0.1, 0.0, 0.0, 0.8 }, { no_input = true })
    draw("warden_hp_fg", sx - bw * 0.5, sy - px * 0.62, bw * frac, 8.0, { C.ice[1], C.ice[2], C.ice[3], 1.0 }, { no_input = true })
end

local function draw_projectiles()
    for _, p in ipairs(Game.projectiles) do
        draw_sprite(p.id, p.x, p.y, p.size, DATA.sprites.arrow, { C.bright[1], C.bright[2], C.bright[3] }, { core_alpha = 0.0 })
    end
end

local function draw_hero()
    local h = Game.hero
    if not h then return end
    local def = h.def
    local bob = (h.moving and h.on_ground and not h.dead) and (def.walk_bob * math.abs(math.sin(h.phase))) or 0.0
    local col = def.color
    if h.hit_flash > 0.0 then col = { 1.0, 0.4, 0.3 }
    elseif h.attack_flash > 0.0 then col = { 1.0, 0.9, 0.6 } end
    local img = (h.facing >= 0.0) and def.sprite_r or def.sprite_l
    local cy = def.size * 0.5 + h.y + bob
    if h.dead then
        draw_sprite("hero", h.x, def.size * 0.4, def.size * 0.9, img, { 0.3, 0.4, 0.5 }, { core_alpha = 0.4 })
        return
    end
    draw_sprite("hero", h.x, cy, def.size, img, col, {})
    -- Encased in ice while frozen: a translucent block over him.
    if h.frozen_t > 0.0 then
        local ppu = Game.cam.ppu
        local sx, sy = w2s(h.x, cy)
        local px = def.size * ppu * 1.2
        draw("hero_ice", sx - px * 0.5, sy - px * 0.55, px, px * 1.1,
            { C.bright[1], C.bright[2], C.bright[3], 0.45 }, { no_input = true, border = { C.frost[1], C.frost[2], C.frost[3], 0.8 } })
    end
    -- Attack arc: a quick frost slash in the facing direction.
    if h.attack_flash > 0.0 then
        local ppu = Game.cam.ppu
        local sx, sy = w2s(h.x + h.facing * (def.attack_range * 0.6), cy)
        local px = def.attack_range * ppu
        draw("hero_swing", sx - px * 0.5, sy - px * 0.5, px, px,
            { C.bright[1], C.bright[2], C.bright[3], 0.5 }, { no_input = true })
    end
end

-- ---- placement ghost / preview ---------------------------------------------

local function draw_placement_ghost()
    local mx, my = mouse_pos()
    if not mx then return end
    local wx = s2w(mx, my)
    local ok = can_place(wx) and Game.budget > 0
    local def = DATA.horde[Game.sel_horde]
    local img = def.frames and DATA.sprites[def.frames][1] or def.sprite
    local sx, sy = w2s(wx, 0)
    local ppu = Game.cam.ppu
    local px = def.size * ppu
    draw("ghost", sx - px * 0.5, sy - px, px, px,
        { ok and 0.3 or 0.8, ok and 0.8 or 0.2, ok and 0.9 or 0.2, 0.30 },
        { image = img, border = ok and { 0.3, 0.9, 1.0, 0.9 } or { 0.9, 0.3, 0.2, 0.9 }, no_input = true })
end

-- ---- HUD -------------------------------------------------------------------

local function button(id, x, y, w, h, label, opts)
    opts = opts or {}
    local st = Art.widget_state(SCREEN, id)
    local hov = st and st.hovered
    Game._live[id] = true
    Art.quad(SCREEN, id, x, y, w, h, opts.fill or (hov and { 0.08, 0.14, 0.22, 0.96 } or { 0.04, 0.08, 0.14, 0.94 }),
        { border = opts.border or { 0.2, 0.4, 0.6, 0.95 }, label = label, subtitle = opts.subtitle,
          text_color = opts.text_color, selected = opts.selected, font_scale = opts.font_scale })
    return Art.consume_click(SCREEN, id)
end

local function draw_hud(sw, sh)
    draw("title", 20, 16, 460, 40, { 0, 0, 0, 0 },
        { title = "FROZEN DEPTHS", text_color = { C.bright[1], C.bright[2], C.bright[3], 1.0 }, font_scale = 1.3, no_input = true })

    if Game.phase == "placement" then
        -- Horde palette (1..4 + click).
        local px, py, pw, ph = 20.0, sh - 132.0, 250.0, 56.0
        for i, id in ipairs(DATA.horde_order) do
            local def = DATA.horde[id]
            local bx = px + (i - 1) * (pw + 8.0)
            if button("pal_" .. id, bx, py, pw, ph, "[" .. i .. "] " .. def.name,
                { subtitle = def.blurb, selected = (Game.sel_horde == id),
                  border = (Game.sel_horde == id) and { 0.2, 0.7, 1.0, 1.0 } or { 0.2, 0.4, 0.6, 0.9 } })
                or key_pressed(tostring(i)) then
                Game.sel_horde = id
            end
        end
        -- Hero selector.
        local hx = px + 4 * (pw + 8.0) + 8.0
        for i, id in ipairs(DATA.hero_order) do
            local def = DATA.heroes[id]
            if button("hero_" .. id, hx, py + (i - 1) * 28.0, 250.0, 24.0, def.name,
                { selected = (Game.sel_hero == id), font_scale = 0.85, subtitle = nil,
                  border = (Game.sel_hero == id) and { 1.0, 0.5, 0.1, 1.0 } or { 0.3, 0.3, 0.4, 0.9 } }) then
                Game.sel_hero = id
            end
        end
        draw("budget", px, py - 36.0, 760.0, 28.0, { 0, 0, 0, 0 },
            { label = "Placements left: " .. tostring(Game.budget) ..
                "    [A]/[D] pan the cave  -  click to place  -  [Z] undo  -  [Enter] release the hero",
              text_color = { 0.7, 0.82, 0.92, 1.0 }, no_input = true })
        if button("release", sw - 280.0, sh - 132.0, 260.0, 56.0, "RELEASE THE HERO  [Enter]",
            { border = { 0.4, 0.9, 0.6, 1.0 }, fill = { 0.06, 0.14, 0.12, 0.96 } }) then
            release_hero()
        end
        draw_placement_ghost()

    elseif Game.phase == "combat" then
        local h = Game.hero
        local pct = h and (h.hp / h.hp_max) or 0.0
        local col = pct > 0.5 and { 0.12, 0.35, 0.55, 0.95 } or { 0.55, 0.18, 0.12, 0.95 }
        Art.bar(SCREEN, "hp", sw * 0.5 - 240.0, 24.0, 480.0, 30.0, pct, col,
            { label = (h and h.def.name or "HERO") .. string.format("   %d / %d", math.floor((h and h.hp or 0) + 0.5), math.floor((h and h.hp_max or 1) + 0.5)),
              border = { 0.2, 0.6, 1.0, 0.9 } })
        Game._live["hp_bg"] = true; Game._live["hp_fg"] = true; Game._live["hp_label"] = true

        -- Status read: frozen / slowed / on ice.
        local status = nil
        if h and h.frozen_t > 0.0 then status = string.format("FROZEN  %.1fs", h.frozen_t)
        elseif h and h.slow_t > 0.0 then status = "SLOWED"
        elseif h and ice_at(h.x) and h.def.slips then status = "ON ICE — sliding" end
        if status then
            draw("status", sw * 0.5 - 120.0, 60.0, 240.0, 24.0, { 0, 0, 0, 0 },
                { label = status, text_color = { C.bright[1], C.bright[2], C.bright[3], 1.0 }, no_input = true })
        end

        local ch = h and chamber_of(h.x) or 1
        local wardenup = Game.warden and Game.warden.alive
        draw("ctrls", 20, sh - 50.0, 760.0, 26.0, { 0, 0, 0, 0 },
            { label = "[A]/[D] run   -   [W] leap   -   [Space] swing   -   [R] rebuild      Chamber " .. ch .. " / 3" ..
                (wardenup and "   -   The Warden lives — slay it to open the gate" or "   -   GATE OPEN — run east!"),
              text_color = { 0.7, 0.8, 0.9, 1.0 }, no_input = true })
        local alive = #Game.entities
        draw("count", sw - 240.0, 24.0, 220.0, 26.0, { 0, 0, 0, 0 },
            { label = "Cave threats: " .. tostring(alive) .. (wardenup and "  + WARDEN" or ""),
              text_color = { 0.6, 0.78, 0.95, 1.0 }, no_input = true })
    end

    -- Win / lose banner.
    if Game.phase == "won" or Game.phase == "lost" then
        local won = Game.phase == "won"
        draw("end", sw * 0.5 - 320.0, sh * 0.40, 640.0, 120.0,
            won and { 0.04, 0.16, 0.18, 0.94 } or { 0.16, 0.04, 0.06, 0.94 },
            { border = won and { 0.3, 0.8, 1.0, 0.95 } or { 0.9, 0.2, 0.18, 0.95 },
              title = won and "YOU ESCAPE THE FROZEN DEPTHS" or "YOU DIED",
              body = "Press [R] to build the descent again", no_input = true })
    end

    -- Flash line.
    if Game.flash ~= "" and Game.flash_t > 0.0 then
        draw("flash", sw * 0.5 - 280.0, 92.0, 560.0, 30.0, { 0, 0, 0, 0 },
            { label = Game.flash, text_color = { C.bright[1], C.bright[2], C.bright[3], math.min(1.0, Game.flash_t) }, no_input = true })
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
        -- Pan the cave to seed hazards down its length.
        local pan = move_axis()
        if pan ~= 0.0 then
            Game.place_focus = clampn(Game.place_focus + pan * 28.0 * dt, 0.0, DATA.arena.length)
        end
        if key_pressed("Z") and #Game.placed > 0 then
            table.remove(Game.placed)
            Game.budget = Game.budget + 1
        end
        if key_pressed("Return") or key_pressed("Enter") then release_hero() end
        if Art.consume_click(SCREEN, "world_input") and Game.budget > 0 then
            local mx, my = mouse_pos()
            if mx then
                local wx = s2w(mx, my)
                if can_place(wx) then
                    Game.placed[#Game.placed + 1] = { id = Game.sel_horde, x = wx }
                    Game.budget = Game.budget - 1
                end
            end
        end
    elseif Game.phase == "combat" then
        update_hero(dt)
        update_entities(dt)
        update_warden(dt)
        update_projectiles(dt)
        update_trails(dt)
        update_director(dt)
    end

    -- Flash decay.
    Game.flash_t = math.max(0.0, Game.flash_t - dt)
    if Game.flash ~= Game.last_flash then Game.flash_t = 2.2; Game.last_flash = Game.flash end
    if Game.flash_t <= 0.0 then Game.flash = "" end

    -- ---- render ----
    local sw, sh = recompute_cam()
    -- The bottom, full-screen input quad: captures world clicks + carries the
    -- cursor. Decorative world quads above it are no_input, so clicks fall through.
    draw("world_input", 0, 0, sw, sh, { 0, 0, 0, 0 })
    draw_world(sw, sh)
    draw_bloods(dt)
    draw_trails()
    draw_gate()
    -- Placement preview of already-placed hazards.
    if Game.phase == "placement" then
        for i, pe in ipairs(Game.placed) do
            local def = DATA.horde[pe.id]
            local img = def.frames and DATA.sprites[def.frames][1] or def.sprite
            draw_sprite("placed_" .. i, pe.x, def.size * 0.5, def.size, img, def.color, {})
        end
    end
    draw_entities()
    draw_warden()
    draw_projectiles()
    draw_hero()
    draw_hud(sw, sh)

    sweep_stale()
end

-- ---------------------------------------------------------------------------
-- Lifecycle (standalone, ATH_MODE=frozen_depths)
-- ---------------------------------------------------------------------------

local function init()
    if runtime_ui then
        if runtime_ui.set_title then runtime_ui.set_title(SCREEN, "Frozen Depths") end
        if runtime_ui.set_screen_overlay then runtime_ui.set_screen_overlay(SCREEN, true) end
        if runtime_ui.show then runtime_ui.show(SCREEN) end
    end
    build_floor()
    build_icicles()
    reset_game()
    if script and script.on_update then
        script.on_update(UPDATE_ID, update, "play")
    else
        _G.update = update
    end
    log("init cave length=" .. tostring(DATA.arena.length))
end

local function destroy()
    if script and script.remove_update then script.remove_update(UPDATE_ID) end
    if runtime_ui and runtime_ui.clear then runtime_ui.clear(SCREEN) end
    log("destroyed")
end

-- Only seize the engine loop when launched as the standalone mode. When the menu
-- shell merely enumerates this file for its { meta } (ATH_MODE=menu), we must NOT
-- start a loop — we just return the contract below.
if ATH_COMMON.getenv("ATH_MODE", "menu") == "frozen_depths" then
    hooks { init = init, destroy = destroy }
end

-- ===========================================================================
-- Menu contract — { meta, config }. The shell can only drive the shared Duel, so
-- this config is a valid Frozen-themed duel fallback (same cast; Freeze Traps
-- become floor patches that FREEZE the hero where he stands).
-- ===========================================================================

-- Duel signature mechanic — FREEZE PATCHES. Frost tears open across the floor,
-- telegraphs with a shimmer, then FREEZES: the hero is locked where he stands
-- (move_mult = 0) for a beat, and chilled. The cold analogue of the magma vent.
local FREEZE_FIRST, FREEZE_INTERVAL, FREEZE_INTERVAL_MIN = 4.0, 5.0, 2.4
local FREEZE_TELEGRAPH, FREEZE_HOLD, FREEZE_RADIUS, FREEZE_DMG, FREEZE_MAX = 0.8, 2.0, 2.4, 14.0, 5

local function frozen_patch_tile(D)
    local A = D.arena
    for _ = 1, 22 do
        local x = math.random(A.pad + 2, A.w - A.pad - 2)
        local y = math.random(A.pad + 2, A.h - A.pad - 2)
        if D.map:is_walkable(x, y) then return x, y end
    end
    return math.floor(A.w * 0.5), math.floor(A.h * 0.5)
end

local function frozen_clear_patches(D)
    for _, s in ipairs(D.frozen and D.frozen.patches or {}) do
        if Art.valid(s.node) then scene.delete_node(s.node) end
    end
    if D.frozen then D.frozen.patches = {} end
end

local function frozen_update_patches(D, dt)
    local p = D.frozen
    if not p then return end
    -- Hold the hero frozen while any patch has him locked (mode-owned move_mult).
    if p.freeze_timer and p.freeze_timer > 0.0 then
        p.freeze_timer = math.max(0.0, p.freeze_timer - dt)
        D.hero.move_mult = 0.0
    end

    p.next = p.next - dt
    if p.next <= 0.0 and #p.patches < FREEZE_MAX then
        p.next = math.max(FREEZE_INTERVAL_MIN, FREEZE_INTERVAL - 0.4 * (D.round - 1))
        local x, y = frozen_patch_tile(D)
        local disc = Art.cylinder("Frozen_Patch_" .. p.counter, vec3(x, 0.05, y), vec3(FREEZE_RADIUS, 0.05, FREEZE_RADIUS),
            C.bright, D.groups.world, 1.2, DATA.sprites.trap_frames and "Objects/frozen_depths/freeze_trap_f0.png" or nil)
        p.counter = p.counter + 1
        p.patches[#p.patches + 1] = { x = x, z = y, t = 0.0, phase = "warn", node = disc }
    end

    local keep = {}
    for _, s in ipairs(p.patches) do
        s.t = s.t + dt
        local alive = true
        if s.phase == "warn" then
            local pulse = 1.1 + 0.6 * math.sin(D.realtime * 18.0)
            if Art.valid(s.node) then material.set(s.node, "emissive", vec3(C.bright[1] * pulse, C.bright[2] * pulse, C.bright[3] * pulse)) end
            if s.t >= FREEZE_TELEGRAPH then
                s.phase = "freeze"; s.t = 0.0
                if Art.valid(s.node) then
                    s.node:set_scale(vec3(FREEZE_RADIUS, 0.6, FREEZE_RADIUS))
                    Art.texture(s.node, "Objects/frozen_depths/freeze_trap_f2.png")
                end
                local dx, dz = D.hero.x - s.x, D.hero.z - s.z
                if not D.hero.dead and dx * dx + dz * dz <= FREEZE_RADIUS * FREEZE_RADIUS then
                    D:apply_hero_damage(FREEZE_DMG, { flash = "FROZEN SOLID!" })
                    p.freeze_timer = FREEZE_HOLD
                end
            end
        elseif s.phase == "freeze" then
            if s.t >= 0.6 then if Art.valid(s.node) then scene.delete_node(s.node) end alive = false end
        end
        if alive then keep[#keep + 1] = s end
    end
    p.patches = keep
end

return {
    meta = {
        id = "frozen_depths",
        name = "Frozen Depths",
        tagline = "the ice cave that swallows the bold",
        blurb = "A 2D side-scrolling ice cave. Slide on the ice, leap the freeze traps, smash the ice walls, and slay the Glacial Warden to break the gate. (Standalone: ATH_MODE=frozen_depths. From the menu it runs the duel fallback.)",
        side_hint = "horde",
        accent = { 0.0, 0.55, 1.0, 0.95 },
        -- A side-on sketch of the cave (normalized 0..1 rects: x,y,w,h,color).
        minimap = {
            bg = { 0.0, 0.051, 0.102, 1.0 },
            rects = {
                { 0.04, 0.06, 0.92, 0.86, { 0.0, 0.102, 0.200, 1.0 } },   -- cave
                { 0.04, 0.74, 0.30, 0.10, { 0.18, 0.21, 0.26, 1.0 } },    -- chamber 1 floor (rock)
                { 0.34, 0.76, 0.30, 0.08, { 0.0, 0.149, 0.42, 1.0 } },    -- chamber 2 floor (icier)
                { 0.64, 0.78, 0.32, 0.06, { 0.0, 0.200, 0.667, 1.0 } },   -- chamber 3 floor (ice)
                { 0.06, 0.62, 0.04, 0.12, { 0.533, 0.8, 1.0, 1.0 } },     -- hero (west)
                { 0.30, 0.60, 0.04, 0.14, { 0.533, 0.8, 1.0, 1.0 } },     -- an ice wight
                { 0.50, 0.66, 0.05, 0.08, { 0.45, 0.52, 0.62, 1.0 } },    -- a frost archer
                { 0.40, 0.50, 0.03, 0.26, { 0.0, 0.200, 0.667, 1.0 } },   -- an ice wall
                { 0.76, 0.46, 0.12, 0.30, { 0.533, 0.8, 1.0, 1.0 } },     -- the Glacial Warden
                { 0.93, 0.50, 0.03, 0.26, { 1.0, 1.0, 1.0, 1.0 } },       -- the ice gate (east)
            },
        },
    },

    config = {
        id = "frozen_depths",
        name = "Frozen Depths",
        theme = Frozen.theme,
        arena = { width = 50, height = 36, pad = 2, ortho_size = 36.0 },
        hero = { hp_max = 110.0, dps = 21.0, cleave = 3, attack_range = 1.30, speed = 2.3, kite_speed = 2.85, actor = Frozen.hero_actor },
        archetypes = Frozen.archetypes,
        roles = Frozen.roles,
        spawn = { interval_start = 0.75, interval_min = 0.32, batch_start = 3, batch_max = 7, cap_start = 28, cap_max = 86, brute_after = 22.0 },
        reserve_start = 320.0,
        round_seconds = 14.0,
        auto_mix = function(D)
            -- Ice Wall is static — keep it out of the roaming mix.
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 12 == 0) then return "glacial_warden" end
            if D.spawn_counter % 5 == 0 then return "frost_archer" end
            return "ice_wight"
        end,
        hooks = {
            on_start = function(D) D.frozen = { patches = {}, next = FREEZE_FIRST, counter = 0, freeze_timer = 0.0 } end,
            on_reset = function(D)
                frozen_clear_patches(D)
                if D.frozen then D.frozen.next = FREEZE_FIRST; D.frozen.freeze_timer = 0.0 end
            end,
            on_combat_tick = function(D, dt) frozen_update_patches(D, dt) end,
            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local n = D.frozen and #D.frozen.patches or 0
                local frozen = D.frozen and D.frozen.freeze_timer and D.frozen.freeze_timer > 0.0
                Art.quad(D.hud, "frozen_patches", 24.0, sh - 150.0, 420.0, 30.0, { 0.0, 0.06, 0.10, 0.85 },
                    { border = { 0.0, 0.55, 1.0, 0.9 },
                      label = "Freeze patches: " .. tostring(n) .. (frozen and "   -   FROZEN!" or "") })
            end,
        },
    },
}
