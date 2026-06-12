-- COLOSSEUM — a 2D top-down gladiatorial arena, ringed by a baying crowd, in the
-- Dark-Souls key.
--
-- Unlike the index's card-duel modes, COLOSSEUM is its own little GAME: it does
-- NOT run on the shared 3D Duel engine. It is a self-contained, real-time, top-down
-- arena drawn entirely on the runtime_ui canvas (the same quad/image API the menu
-- uses), driven by its own update loop — mirroring the standalone pattern of
-- modes/pit, modes/gravewarden, modes/rush and modes/horde. Launch with
-- ATH_MODE=colosseum.
--
-- There is no placement phase: you ARE thrown to the sand. You DRIVE one of two
-- gladiators (WASD / arrows) and must survive FIVE escalating ROUNDS. Each round
-- the four PORTCULLIS gates ASCEND and the wave pours in; clear it and the gates
-- DESCEND, the sand drinks another stage of blood, and the next, harder round
-- opens. Round 5 looses the COLOSSEUM MASTER — a greatblade-swinging colossus.
--
-- SIGNATURE MECHANIC — CROWD FURY. A bar that fills whenever blood is spilled: the
-- hero KILLS a foe, or the hero TAKES a hit. The stands roar louder (brighter,
-- pulsing gold) as it climbs. At MAX the mob bays for a champion — the horde gets
-- a FREE Iron Champion through a gate, and the fury empties to begin again.
--
-- Animation is procedural-from-sprites: torches flicker on a 4-frame cycle; the
-- horde cycle their walk frames; the hero plays an 8-directional walk that bobs as
-- it strides. Physics is hand-rolled 2D: WASD locomotion, boid separation, beast
-- lunges, parabolic nets, a telegraphed boss sweep, and a rectangular wall clamp.
-- All art is from tools/gen_textures_colosseum.py and OPTIONAL — a missing PNG just
-- falls back to a flat silhouette colour, so the game still runs.
--
-- This file ALSO returns { meta, config } at the bottom so the mode is discover-
-- able from the battlefield menu; that path can only run the shared Duel, so it
-- falls back to a valid Colosseum-themed duel (same cast; CROWD FURY there looses
-- a free Iron Champion onto the field).

local Art  = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Colo = ATH_COMMON.load_script("Scripts/modes/colosseum/characters.lua", "colosseum characters", _ENV)

local DATA = Colo.colo2d
local C = DATA.palette
local FURY = DATA.fury

-- ===========================================================================
-- The 2D game
-- ===========================================================================

local SCREEN = "ath.colosseum"
local UPDATE_ID = "against_the_hero_colosseum"
local TORCH_FPS = 8.0

local Game = {
    phase = "combat",         -- "combat" | "won" | "lost"
    round_state = "opening",  -- "opening" (gates rise) | "fighting" | "closing" | "break"
    round = 1,
    blood_stage = 0,          -- 0..4 — how soaked the sand is (climbs each round)
    gate_open = 0.0,          -- 0 = portcullis fully down (shut), 1 = fully up (open)
    state_t = 0.0,            -- timer within the current round_state
    key_down = {},
    enemies = {},             -- the round's released horde
    projectiles = {},         -- thrown nets in flight
    bloods = {},              -- blood decals (world-anchored, fading)
    boss = nil,               -- the Colosseum Master, once round 5 looses him
    fury = 0.0,               -- CROWD FURY, 0..FURY.max
    fury_flare = 0.0,         -- a screen-edge roar flare when a champion is released
    sel_hero = "pit_fighter",
    time = 0.0,               -- monotonic clock (drives animation)
    flash = "", flash_t = 0.0, last_flash = nil,
    cam = { ox = 0.0, oy = 0.0, ppu = 24.0 },
    _live = {}, _prev = {},
    next_id = 0,
}

-- ---- small helpers ---------------------------------------------------------

local function log(msg) if pe_log then pe_log("[ATH:COLOSSEUM] " .. tostring(msg)) end end

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

local function set_flash(text) Game.flash = text or "" end

-- ---- arena geometry --------------------------------------------------------

local function clamp_to_arena(wx, wy, radius)
    local r = radius or 0.0
    return clampn(wx, -DATA.arena.half_w + r, DATA.arena.half_w - r),
           clampn(wy, -DATA.arena.half_h + r, DATA.arena.half_h - r)
end

-- A gate just inside the wall (where a freshly-released foe steps onto the sand).
local function gate_inner(g, inset)
    inset = inset or 1.2
    return g.x - g.nx * inset, g.y - g.ny * inset
end

-- ---- camera (fixed; the whole arena + crowd stands fit in frame) -----------

local function recompute_cam()
    local sw, sh = Art.surface_size()
    local c = Game.cam
    local sd = DATA.arena.stand_depth
    local total_w = (DATA.arena.half_w + sd + 0.5) * 2.0
    local total_h = (DATA.arena.half_h + sd + 0.5) * 2.0
    c.ppu = math.max(8.0, math.min((sw - 60.0) / total_w, (sh - 200.0) / total_h))
    c.ox = sw * 0.5
    c.oy = (sh - 110.0) * 0.5 + 80.0
    return sw, sh
end

local function w2s(wx, wy)
    local c = Game.cam
    return c.ox + wx * c.ppu, c.oy + wy * c.ppu
end

-- ---- canvas draw (records ids so stale ones get swept each frame) ----------

local function draw(id, x, y, w, h, fill, opts)
    Game._live[id] = true
    Art.quad(SCREEN, id, x, y, w, h, fill, opts)
end

-- A world-anchored sprite: a faint solid core (so it reads even with no art) plus
-- the textured quad on top. `size` is the world-unit footprint; `opts.aspect`
-- (w/h) lets wide sprites (the Iron Champion) draw un-squashed; `opts.z` lifts it.
local function draw_sprite(id, wx, wy, size, image, color, opts)
    opts = opts or {}
    local ppu = Game.cam.ppu
    local aspect = opts.aspect or 1.0
    local pw = size * ppu
    local ph = pw / aspect
    local sx, sy = w2s(wx, wy)
    local zoff = (opts.z or 0.0) * ppu
    local cs = ph * 0.5
    draw(id .. "_core", sx - cs * 0.5, sy - zoff - cs * 0.5, cs, cs,
        { color[1], color[2], color[3], opts.core_alpha or 0.8 }, { no_input = true })
    draw(id, sx - pw * 0.5, sy - zoff - ph * 0.55, pw, ph, { 0, 0, 0, 0 },
        { image = image, no_input = true, image_tint = opts.tint })
end

-- ---- blood decals ----------------------------------------------------------

local function add_blood(wx, wy, big, color)
    Game.next_id = Game.next_id + 1
    Game.bloods[#Game.bloods + 1] = {
        id = "blood_" .. Game.next_id, x = wx, y = wy,
        size = (big and 2.4 or 1.4) + math.random() * 0.4, life = 6.0,
        color = color or C.blood,
    }
end

-- ---- CROWD FURY ------------------------------------------------------------

-- Spilt blood stokes the crowd. At max the mob bays for a champion: a free Iron
-- Champion is loosed through a gate, and the fury empties.
local function add_fury(amount)
    if Game.phase ~= "combat" then return end
    Game.fury = math.min(FURY.max, Game.fury + amount)
    if Game.fury >= FURY.max then
        Game.fury = 0.0
        Game.fury_flare = 1.0
        local g = DATA.arena.gates[math.random(#DATA.arena.gates)]
        local x, y = gate_inner(g, 1.0)
        Game.enemies[#Game.enemies + 1] = spawn_enemy(DATA.horde[FURY.champion], x, y)
        Art_safe_burst(x, y)
        set_flash("CROWD FURY — CHAMPION RELEASED!")
        log("crowd fury peaked: Iron Champion released")
    end
end

-- (forward-declared above; a tiny guard so a missing Art.burst never errors here.)
function Art_safe_burst(_, _) end

-- ---------------------------------------------------------------------------
-- Hero
-- ---------------------------------------------------------------------------

local function spawn_hero()
    local def = DATA.heroes[Game.sel_hero]
    local sp = DATA.arena.hero_spawn
    Game.hero = {
        def = def, x = sp.x, y = sp.y,
        hp = def.hp, hp_max = def.hp,
        dir = 2,                      -- facing south (toward the camera)
        moving = false, phase = 0.0,
        attack_cd = 0.0, attack_flash = 0.0,
        hit_flash = 0.0, dead = false,
        slow_t = 0.0,                 -- Net Thrower snare
        counter_t = 0.0,              -- Duelist riposte window (open after a hit)
    }
end

local function hero_take_damage(amount, what)
    local h = Game.hero
    if not h or h.dead or amount <= 0.0 then return end
    h.hp = h.hp - amount
    h.hit_flash = 0.18
    if h.def.counter then h.counter_t = h.def.counter.window end   -- a riposte opens
    add_blood(h.x, h.y, false)
    add_fury(amount * FURY.per_damage)                              -- the crowd loves blood
    if h.hp <= 0.0 then
        h.hp = 0.0; h.dead = true
        Game.phase = "lost"
        set_flash("YOU DIED")
        add_blood(h.x, h.y, true)
        log("hero slain by " .. tostring(what or "the arena"))
    end
end

-- The hero's sweep: a radial cut that strikes every foe within reach at once. The
-- Duelist's RIPOSTE (a swing inside the window after being hit) lands for far more.
local function hero_attack()
    local h = Game.hero
    if not h or h.dead or h.attack_cd > 0.0 then return end
    h.attack_cd = h.def.attack_cd
    h.attack_flash = 0.14
    local dmg = h.def.attack_damage
    local riposte = false
    if h.def.counter and h.counter_t > 0.0 then
        dmg = dmg * h.def.counter.mult
        h.counter_t = 0.0
        riposte = true
        set_flash("RIPOSTE!")
    end
    local r = h.def.attack_range
    local function hit_target(e)
        if not e or not e.alive then return end
        local dx, dz = e.x - h.x, e.y - h.y
        local reach = r + (e.def.radius or 0.5)
        if dx * dx + dz * dz <= reach * reach then
            e.hp = e.hp - dmg
            e.hit_flash = 0.18
            add_blood(e.x, e.y, false)
            if e.hp <= 0.0 then
                e.alive = false
                add_blood(e.x, e.y, true)
                add_fury(FURY.per_kill)                            -- a clean kill feeds the mob
            end
        end
    end
    for _, e in ipairs(Game.enemies) do hit_target(e) end
    hit_target(Game.boss)
    if riposte then Game.fury_flare = math.max(Game.fury_flare, 0.4) end
end

local function update_hero(dt)
    local h = Game.hero
    if not h then return end
    h.attack_cd = math.max(0.0, h.attack_cd - dt)
    h.hit_flash = math.max(0.0, h.hit_flash - dt)
    h.attack_flash = math.max(0.0, h.attack_flash - dt)
    h.slow_t = math.max(0.0, h.slow_t - dt)
    h.counter_t = math.max(0.0, h.counter_t - dt)
    if h.dead then return end

    -- WASD / arrows -> a movement vector (screen +y is south).
    local ix = (key_down("D") or key_down("Right")) and 1.0 or 0.0
    ix = ix - ((key_down("A") or key_down("Left")) and 1.0 or 0.0)
    local iy = (key_down("S") or key_down("Down")) and 1.0 or 0.0
    iy = iy - ((key_down("W") or key_down("Up")) and 1.0 or 0.0)
    local mag = len2(ix, iy)
    h.moving = mag > 0.0

    if mag > 0.0 then
        ix, iy = ix / mag, iy / mag
        local speed = h.def.speed
        if h.slow_t > 0.0 then speed = speed * (h.net_slow or 0.42) end   -- snared
        h.x = h.x + ix * speed * dt
        h.y = h.y + iy * speed * dt
        h.x, h.y = clamp_to_arena(h.x, h.y, h.def.radius)
        -- 8-way facing from heading (0=E,2=S,4=W,6=N) — matches the sprite set.
        local ang = math.atan(iy, ix)
        h.dir = math.floor(ang / (math.pi / 4.0) + 0.5) % 8
        if h.dir < 0 then h.dir = h.dir + 8 end
        h.phase = h.phase + dt * h.def.walk_freq
    end

    if key_pressed("Space") or key_pressed("J") or key_pressed("Return") then hero_attack() end
end

-- ---------------------------------------------------------------------------
-- Horde (released by the rounds) + the boss
-- ---------------------------------------------------------------------------

function spawn_enemy(def, x, y)
    Game.next_id = Game.next_id + 1
    return {
        id = "foe_" .. Game.next_id, def = def, kind = def.kind,
        x = x, y = y, hp = def.hp, alive = true,
        seed = math.random() * 6.28, hit_flash = 0.0,
        cd = 0.0,                       -- generic timer (touch / throw)
        lunge_cd = 0.0, lunge_t = 0.0,  -- Sand Beast pounce
        moving = false,
    }
end

-- Boid separation: push apart from nearby kin so the pack surrounds the hero.
local function separation(e)
    local rad = e.def.sep_radius or 0.0
    if rad <= 0.0 then return 0.0, 0.0 end
    local sx, sz = 0.0, 0.0
    local r2 = rad * rad
    for _, o in ipairs(Game.enemies) do
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

-- A melee seeker (Gladiator / Iron Champion): seek the hero with separation, bite
-- on contact.
local function update_melee(e, dt, h)
    local dx, dz = h.x - e.x, h.y - e.y
    local d = len2(dx, dz)
    local sx, sz = 0.0, 0.0
    if d > 0.0001 then sx, sz = dx / d, dz / d end
    local px, pz = separation(e)
    local vx = sx + px * (e.def.sep_weight or 0.0)
    local vz = sz + pz * (e.def.sep_weight or 0.0)
    local vm = len2(vx, vz)
    if vm > 0.0001 then vx, vz = vx / vm, vz / vm end
    e.x = e.x + vx * e.def.speed * dt
    e.y = e.y + vz * e.def.speed * dt
    e.x, e.y = clamp_to_arena(e.x, e.y, e.def.radius)
    e.moving = vm > 0.01
    e.cd = math.max(0.0, e.cd - dt)
    if not h.dead and d <= e.def.radius + h.def.radius + 0.2 and e.cd <= 0.0 then
        e.cd = e.def.touch_cd
        hero_take_damage(e.def.touch_damage, "a " .. e.def.name)
    end
end

-- A Sand Beast: a fast seeker that, with a clear line, LUNGES — a brief burst
-- straight at the hero, then a recovery before it can pounce again.
local function update_beast(e, dt, h)
    local lu = e.def.lunge
    e.lunge_cd = math.max(0.0, e.lunge_cd - dt)
    local dx, dz = h.x - e.x, h.y - e.y
    local d = len2(dx, dz)
    if e.lunge_t > 0.0 then
        e.lunge_t = math.max(0.0, e.lunge_t - dt)
    elseif lu and e.lunge_cd <= 0.0 and d <= lu.range and d > e.def.radius + h.def.radius + 0.3 then
        e.lunge_t = lu.time; e.lunge_cd = lu.cd
        e.lunge_dx = (d > 0.0001) and dx / d or 0.0
        e.lunge_dz = (d > 0.0001) and dz / d or 0.0
    end
    local vx, vz, speed
    if e.lunge_t > 0.0 then
        vx, vz, speed = e.lunge_dx or 0.0, e.lunge_dz or 0.0, lu.speed
    else
        local sx, sz = 0.0, 0.0
        if d > 0.0001 then sx, sz = dx / d, dz / d end
        local px, pz = separation(e)
        vx, vz = sx + px * (e.def.sep_weight or 0.0), sz + pz * (e.def.sep_weight or 0.0)
        local vm = len2(vx, vz)
        if vm > 0.0001 then vx, vz = vx / vm, vz / vm end
        speed = e.def.speed
    end
    e.x = e.x + vx * speed * dt
    e.y = e.y + vz * speed * dt
    e.x, e.y = clamp_to_arena(e.x, e.y, e.def.radius)
    e.moving = true
    e.cd = math.max(0.0, e.cd - dt)
    if not h.dead and d <= e.def.radius + h.def.radius + 0.25 and e.cd <= 0.0 then
        e.cd = e.def.touch_cd
        hero_take_damage(e.def.touch_damage, "a Sand Beast")
        e.lunge_t = 0.0   -- pounce spent on the hit
    end
end

local function throw_net(e, h)
    local pj = e.def.net
    local lead = pj.lead or 0.0
    local tx, ty = h.x, h.y
    if h.moving then
        local ix = (key_down("D") or key_down("Right")) and 1.0 or 0.0
        ix = ix - ((key_down("A") or key_down("Left")) and 1.0 or 0.0)
        local iy = (key_down("S") or key_down("Down")) and 1.0 or 0.0
        iy = iy - ((key_down("W") or key_down("Up")) and 1.0 or 0.0)
        local m = len2(ix, iy)
        if m > 0.0 then tx = h.x + (ix / m) * lead * h.def.speed; ty = h.y + (iy / m) * lead * h.def.speed end
    end
    local dist = len2(tx - e.x, ty - e.y)
    local T = math.max(0.35, dist / (pj.speed or 11.0))
    Game.next_id = Game.next_id + 1
    Game.projectiles[#Game.projectiles + 1] = {
        id = "net_" .. Game.next_id,
        x0 = e.x, y0 = e.y, tx = tx, ty = ty,
        t = 0.0, T = T, peak = pj.arc_peak or 2.8,
        dmg = pj.damage or 8.0, blast = pj.blast or 1.9, size = pj.size or 1.6,
        slow = pj.slow or 0.42, slow_time = pj.slow_time or 1.9,
    }
end

-- A Net Thrower: hold a preferred band and lob a snaring net that leads the hero.
local function update_thrower(e, dt, h)
    local dx, dz = h.x - e.x, h.y - e.y
    local d = len2(dx, dz)
    local dir = 0.0
    if d < (e.def.retreat_range or 5.0) then dir = -1.0
    elseif d > (e.def.hold_range or 10.0) then dir = 1.0 end
    if dir ~= 0.0 and d > 0.0001 then
        local px, pz = separation(e)
        local vx = (dx / d) * dir + px * (e.def.sep_weight or 0.0)
        local vz = (dz / d) * dir + pz * (e.def.sep_weight or 0.0)
        local vm = len2(vx, vz)
        if vm > 0.0001 then
            e.x = e.x + (vx / vm) * e.def.speed * dt
            e.y = e.y + (vz / vm) * e.def.speed * dt
            e.x, e.y = clamp_to_arena(e.x, e.y, e.def.radius)
        end
        e.moving = true
    else
        e.moving = false
    end
    e.cd = math.max(0.0, e.cd - dt)
    if not h.dead and e.cd <= 0.0 and d <= (e.def.hold_range or 10.0) + 1.0 then
        e.cd = e.def.throw_cd or 2.4
        throw_net(e, h)
    end
end

-- The Colosseum Master: a slow seeker with a telegraphed greatblade SWEEP (a wide
-- AoE ring). `b.sweep_phase`: "idle" -> "warn" -> "active".
local function update_boss(dt, h)
    local b = Game.boss
    if not b or not b.alive then return end
    b.hit_flash = math.max(0.0, b.hit_flash - dt)
    local sw = b.def.sweep
    b.sweep_cd = math.max(0.0, (b.sweep_cd or 0.0) - dt)

    if b.sweep_phase == "warn" then
        b.sweep_t = b.sweep_t + dt
        if b.sweep_t >= sw.telegraph then
            b.sweep_phase = "active"; b.sweep_t = 0.0
            local dx, dz = h.x - b.x, h.y - b.y
            if not h.dead and dx * dx + dz * dz <= sw.range * sw.range then
                hero_take_damage(sw.damage, "the Master's greatblade")
            end
        end
        return   -- root while winding up
    elseif b.sweep_phase == "active" then
        b.sweep_t = b.sweep_t + dt
        if b.sweep_t >= sw.active then b.sweep_phase = "idle"; b.sweep_t = 0.0 end
        return
    end

    local dx, dz = h.x - b.x, h.y - b.y
    local d = len2(dx, dz)
    if d > 0.0001 then
        b.x = b.x + (dx / d) * b.def.speed * dt
        b.y = b.y + (dz / d) * b.def.speed * dt
        b.x, b.y = clamp_to_arena(b.x, b.y, b.def.radius)
    end
    b.moving = d > 0.05
    if d <= sw.range * 0.92 and b.sweep_cd <= 0.0 then
        b.sweep_phase = "warn"; b.sweep_t = 0.0; b.sweep_cd = sw.cd
        set_flash("THE MASTER WINDS UP")
    end
    b.cd = math.max(0.0, (b.cd or 0.0) - dt)
    if not h.dead and d <= b.def.radius + h.def.radius + 0.3 and b.cd <= 0.0 then
        b.cd = b.def.touch_cd
        hero_take_damage(b.def.touch_damage, "the Colosseum Master")
    end
end

local function update_enemies(dt)
    local h = Game.hero
    local survivors = {}
    for _, e in ipairs(Game.enemies) do
        e.hit_flash = math.max(0.0, e.hit_flash - dt)
        if e.alive then
            if e.kind == "thrower" then update_thrower(e, dt, h)
            elseif e.kind == "beast" then update_beast(e, dt, h)
            else update_melee(e, dt, h) end   -- gladiator + iron_champion
        end
        if e.alive then survivors[#survivors + 1] = e
        else Game._live[e.id] = nil; Game._live[e.id .. "_core"] = nil end
    end
    Game.enemies = survivors
end

local function update_projectiles(dt)
    local h = Game.hero
    local survivors = {}
    for _, p in ipairs(Game.projectiles) do
        p.t = p.t + dt
        local frac = p.t / p.T
        if frac >= 1.0 then
            -- The net lands: graze + snare if the hero is caught in the splash.
            local dx, dz = h.x - p.tx, h.y - p.ty
            if not h.dead and (dx * dx + dz * dz) <= (p.blast + h.def.radius) * (p.blast + h.def.radius) then
                h.slow_t = p.slow_time
                h.net_slow = p.slow
                hero_take_damage(p.dmg, "a thrown net")
                set_flash("NETTED!")
            end
            add_blood(p.tx, p.ty, false, C.bone)
            Game._live[p.id] = nil; Game._live[p.id .. "_core"] = nil; Game._live[p.id .. "_sh"] = nil
        else
            p.x = p.x0 + (p.tx - p.x0) * frac
            p.y = p.y0 + (p.ty - p.y0) * frac
            p.z = math.sin(math.pi * frac) * p.peak
            survivors[#survivors + 1] = p
        end
    end
    Game.projectiles = survivors
end

-- ---------------------------------------------------------------------------
-- The ROUNDS — escalating waves through the portcullis gates
-- ---------------------------------------------------------------------------

-- Pour a round's composition onto the sand, distributed across the four gates.
local function release_round(n)
    local comp = DATA.rounds[n] or {}
    local gates = DATA.arena.gates
    local gi = 0
    for id, count in pairs(comp) do
        local def = DATA.horde[id]
        for _ = 1, count do
            local g = gates[(gi % #gates) + 1]
            gi = gi + 1
            local x, y = gate_inner(g, 1.0 + math.random() * 0.8)
            -- fan along the gate so they don't stack on the threshold
            local tx, ty = -g.ny, g.nx     -- tangent to the wall
            local spread = (math.random() - 0.5) * 2.4
            Game.enemies[#Game.enemies + 1] = spawn_enemy(def, x + tx * spread, y + ty * spread)
        end
    end
    if n == DATA.boss_round then rise_boss() end
end

-- Rise the Colosseum Master from the north gate (once, at round 5).
function rise_boss()
    if Game.boss then return end
    local def = DATA.boss
    local g = DATA.arena.gates[1]
    local x, y = gate_inner(g, 1.6)
    Game.next_id = Game.next_id + 1
    Game.boss = {
        id = "boss_" .. Game.next_id, def = def, kind = "boss",
        x = x, y = y, hp = def.hp, hp_max = def.hp, alive = true,
        seed = 0.0, hit_flash = 0.0, moving = false,
        cd = 0.0, sweep_cd = def.sweep.cd * 0.6, sweep_phase = "idle", sweep_t = 0.0,
    }
    set_flash("THE COLOSSEUM MASTER ENTERS")
    log("the Colosseum Master enters")
end

local function round_cleared()
    if #Game.enemies > 0 then return false end
    if Game.round == DATA.boss_round then return not (Game.boss and Game.boss.alive) end
    return true
end

-- Drive the round state machine: gates ASCEND -> the wave fights -> gates DESCEND,
-- the sand drinks more blood, a beat's pause, then the next round opens.
local function update_rounds(dt)
    Game.state_t = Game.state_t + dt
    local s = Game.round_state

    if s == "opening" then
        Game.gate_open = clampn(Game.state_t / DATA.gate_open_time, 0.0, 1.0)
        if Game.state_t >= DATA.gate_open_time then
            release_round(Game.round)
            Game.round_state = "fighting"; Game.state_t = 0.0
            set_flash("ROUND " .. Game.round .. (Game.round == DATA.boss_round and " — THE MASTER" or " — FIGHT"))
        end

    elseif s == "fighting" then
        if round_cleared() then
            if Game.round >= #DATA.rounds then
                Game.phase = "won"
                set_flash("THE GAMES ARE YOURS")
                log("all rounds cleared")
            else
                Game.round_state = "closing"; Game.state_t = 0.0
                set_flash("ROUND " .. Game.round .. " CLEARED")
            end
        end

    elseif s == "closing" then
        Game.gate_open = clampn(1.0 - Game.state_t / DATA.gate_close_time, 0.0, 1.0)
        if Game.state_t >= DATA.gate_close_time then
            Game.gate_open = 0.0
            Game.blood_stage = math.min(#DATA.sprites.blood_stages - 1, Game.blood_stage + 1)
            Game.round = Game.round + 1
            Game.round_state = "break"; Game.state_t = 0.0
        end

    elseif s == "break" then
        if Game.state_t >= DATA.round_break then
            Game.round_state = "opening"; Game.state_t = 0.0
        end
    end
end

-- ---------------------------------------------------------------------------
-- Reset
-- ---------------------------------------------------------------------------

local function reset_game()
    Game.enemies = {}
    Game.projectiles = {}
    Game.bloods = {}
    Game.boss = nil
    Game.fury = 0.0
    Game.fury_flare = 0.0
    Game.round = 1
    Game.blood_stage = 0
    Game.gate_open = 0.0
    Game.round_state = "opening"
    Game.state_t = 0.0
    Game.phase = "combat"
    Game.time = 0.0
    spawn_hero()
    set_flash("THE GATES RISE...")
    log("games begin: " .. tostring(Game.sel_hero))
end

local function cycle_hero()
    -- Swap the gladiator you'll be thrown in as (only meaningful before/while a run
    -- can be restarted with [R]); applies on the next reset.
    local order = DATA.hero_order
    for i, id in ipairs(order) do
        if id == Game.sel_hero then Game.sel_hero = order[(i % #order) + 1]; break end
    end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

-- Build the floor grid once (2-unit sand tiles across the whole pit).
local function build_floor_tiles()
    Game.floor = {}
    local step = 2.0
    local i = 0
    local y = -DATA.arena.half_h
    while y <= DATA.arena.half_h + 0.01 do
        local x = -DATA.arena.half_w
        while x <= DATA.arena.half_w + 0.01 do
            i = i + 1
            Game.floor[i] = { x = x, y = y, seed = (i * 37) % 100 / 100.0 }
            x = x + step
        end
        y = y + step
    end
end

-- The crowd stands ring the pit on all four sides. They ROAR with fury: brighter,
-- pulsing gold as the bar climbs.
local function draw_stands(sw, sh)
    local ppu = Game.cam.ppu
    local sd = DATA.arena.stand_depth
    local hw, hh = DATA.arena.half_w, DATA.arena.half_h
    local fury_frac = Game.fury / FURY.max
    local roar = 0.55 + 0.45 * fury_frac + (fury_frac > 0.6 and 0.12 * math.sin(Game.time * 12.0) or 0.0)
    roar = math.min(1.25, roar)
    local tint = { C.gold[1] * roar + 0.12, C.gold[2] * roar + 0.08, C.gold[3] * roar + 0.05, 1.0 }
    -- Four bands (top / bottom / left / right), each tiled with the crowd texture.
    local function band(id, wx0, wy0, wx1, wy1)
        local sx0, sy0 = w2s(wx0, wy0)
        local sx1, sy1 = w2s(wx1, wy1)
        draw(id, sx0, sy0, sx1 - sx0, sy1 - sy0, { C.sand_lo[1] * 0.5, C.sand_lo[2] * 0.5, C.sand_lo[3] * 0.5, 1.0 },
            { image = DATA.sprites.crowd, no_input = true, image_tint = tint })
    end
    band("stand_n", -hw - sd, -hh - sd, hw + sd, -hh)
    band("stand_s", -hw - sd,  hh,      hw + sd,  hh + sd)
    band("stand_w", -hw - sd, -hh,     -hw,       hh)
    band("stand_e",  hw,      -hh,      hw + sd,   hh)
end

local function draw_world_floor(sw, sh)
    draw("bg", 0, 0, sw, sh, { C.shadow[1], C.shadow[2], C.shadow[3], 1.0 }, { no_input = true })
    local ppu = Game.cam.ppu
    local tile = 2.0 * ppu
    for i, t in ipairs(Game.floor) do
        local sx, sy = w2s(t.x, t.y)
        local shade = 0.75 + 0.25 * t.seed
        draw("fl_" .. i, sx - tile * 0.5, sy - tile * 0.5, tile + 1.0, tile + 1.0,
            { C.sand[1] * shade, C.sand[2] * shade, C.sand[3] * shade, 1.0 },
            { image = DATA.sprites.floor, no_input = true })
    end
end

-- The accumulating gore: a single overlay stretched over the whole sand, swapped
-- to a bloodier stage each round.
local function draw_blood_overlay()
    local img = DATA.sprites.blood_stages[Game.blood_stage + 1]
    if not img then Game._live["gore"] = nil; return end
    local sx0, sy0 = w2s(-DATA.arena.half_w, -DATA.arena.half_h)
    local sx1, sy1 = w2s(DATA.arena.half_w, DATA.arena.half_h)
    draw("gore", sx0, sy0, sx1 - sx0, sy1 - sy0, { 0, 0, 0, 0 },
        { image = img, no_input = true })
end

-- Each gate: the dark archway, and the iron portcullis grate that retracts OUTWARD
-- (into the wall) as the round opens, sliding back down to shut it.
local function draw_gates()
    local ppu = Game.cam.ppu
    local open = Game.gate_open
    local gw = 3.2                       -- gate width (world units)
    for i, g in ipairs(DATA.arena.gates) do
        local horiz = math.abs(g.nx) < 0.5    -- N/S gates span horizontally
        local gx, gy = w2s(g.x, g.y)
        local pw = horiz and gw * ppu or 1.4 * ppu
        local ph = horiz and 1.4 * ppu or gw * ppu
        -- The dark gateway sunk into the wall.
        draw("arch_" .. i, gx - pw * 0.5, gy - ph * 0.5, pw, ph,
            { 0.02, 0.012, 0.0, 1.0 }, { image = DATA.sprites.gateway, no_input = true })
        -- The grate, slid outward by `open` (retracting into the stands).
        local slide = open * gw * 0.95
        local cx = g.x + g.nx * slide
        local cy = g.y + g.ny * slide
        local sgx, sgy = w2s(cx, cy)
        local alpha = 1.0 - open * 0.85
        if alpha > 0.04 then
            draw("port_" .. i, sgx - pw * 0.5, sgy - ph * 0.5, pw, ph,
                { 0, 0, 0, 0 }, { image = DATA.sprites.portcullis, no_input = true,
                  image_tint = { C.iron_hi[1], C.iron_hi[2], C.iron_hi[3], alpha } })
        else
            Game._live["port_" .. i] = nil
        end
    end
end

-- The torches at the four corners flicker on a 4-frame cycle.
local function draw_torches()
    local ppu = Game.cam.ppu
    local hw, hh = DATA.arena.half_w + 0.6, DATA.arena.half_h + 0.6
    local corners = { { -hw, -hh, 1.3 }, { hw, -hh, 2.1 }, { -hw, hh, 3.4 }, { hw, hh, 0.7 } }
    for ci, c in ipairs(corners) do
        local frame = (math.floor(Game.time * TORCH_FPS + c[3]) % 4) + 1
        local sx, sy = w2s(c[1], c[2])
        local px = 2.2 * ppu
        draw("torch_" .. ci, sx - px * 0.5, sy - px * 0.78, px, px * 1.4,
            { 0, 0, 0, 0 }, { image = DATA.sprites.torch_frames[frame], no_input = true })
    end
end

-- Build the depth-sorted draw list (lower screen-y first -> south draws on top).
local function frame_image(def, seed)
    local n = def.frames or 1
    local f = (math.floor(Game.time * (def.fps or 6.0) + (seed or 0.0) * n) % n)
    return def.sprite_base .. tostring(f) .. ".png"
end

local function draw_actors()
    local list = {}
    for _, e in ipairs(Game.enemies) do list[#list + 1] = { y = e.y, e = e } end
    if Game.boss then list[#list + 1] = { y = Game.boss.y, boss = Game.boss } end
    if Game.hero then list[#list + 1] = { y = Game.hero.y, hero = Game.hero } end
    table.sort(list, function(a, b) return a.y < b.y end)

    for _, item in ipairs(list) do
        if item.e then
            local e = item.e
            local sway = (e.def.sway_amp or 0.0) * math.sin(Game.time * (e.def.sway_freq or 4.0) + e.seed)
            local col = e.def.color
            if e.hit_flash > 0.0 then col = { 1.0, 0.6, 0.5 } end
            -- A Sand Beast mid-pounce streaks gold.
            local tint = nil
            if e.kind == "beast" and e.lunge_t and e.lunge_t > 0.0 then
                tint = { C.blood_hot[1], C.blood_hot[2] + 0.3, 0.3, 1.0 }
            end
            draw_sprite(e.id, e.x, e.y + sway, e.def.size, frame_image(e.def, e.seed), col,
                { aspect = e.def.aspect, tint = tint })

        elseif item.boss then
            local b = item.boss
            local col = b.def.color
            if b.hit_flash > 0.0 then col = { 1.0, 0.7, 0.6 } end
            local tint = nil
            if b.sweep_phase == "warn" then
                local f = 0.5 + 0.5 * math.sin(Game.time * 18.0)
                tint = { 1.0, 0.7 + 0.3 * f, 0.2, 1.0 }
            end
            draw_sprite("boss", b.x, b.y, b.def.size, frame_image(b.def, b.seed), col, { core_alpha = 0.0, tint = tint })
            -- The greatblade-sweep ring (telegraph = warning pulse; active = slash).
            if b.sweep_phase == "warn" or b.sweep_phase == "active" then
                local ppu = Game.cam.ppu
                local sx, sy = w2s(b.x, b.y)
                local rr = b.def.sweep.range * 2.0 * ppu
                local alpha = b.sweep_phase == "active" and 0.55 or (0.2 + 0.2 * math.abs(math.sin(Game.time * 16.0)))
                draw("boss_sweep", sx - rr * 0.5, sy - rr * 0.5, rr, rr, { 0, 0, 0, 0 },
                    { image = DATA.sprites.glow, no_input = true, image_tint = { C.gold_hot[1], C.gold_hot[2], C.gold_hot[3], alpha } })
            else
                Game._live["boss_sweep"] = nil
            end

        elseif item.hero then
            local h = item.hero
            local bob = (h.moving and not h.dead) and (h.def.walk_bob * math.abs(math.sin(h.phase))) or 0.0
            local col = h.def.color
            if h.hit_flash > 0.0 then col = { 1.0, 0.4, 0.3 }
            elseif h.attack_flash > 0.0 then col = h.def.glow end
            local img = h.def.sprite_base .. tostring(h.dir) .. ".png"
            if h.dead then
                draw_sprite("hero", h.x, h.y, h.def.size * 0.9, img, { 0.4, 0.1, 0.1 }, { core_alpha = 0.4 })
            else
                draw_sprite("hero", h.x, h.y, h.def.size, img, col, { z = bob })
            end
            -- The Duelist's open riposte window glows a faint ring at his feet.
            if h.def.counter and h.counter_t > 0.0 and not h.dead then
                local ppu = Game.cam.ppu
                local sx, sy = w2s(h.x, h.y)
                local rr = h.def.attack_range * 2.0 * ppu
                draw("hero_riposte", sx - rr * 0.5, sy - rr * 0.5, rr, rr, { 0, 0, 0, 0 },
                    { image = DATA.sprites.glow, no_input = true,
                      image_tint = { C.blood_hot[1], C.blood_hot[2], C.blood_hot[3], 0.35 * (h.counter_t / h.def.counter.window) } })
            else
                Game._live["hero_riposte"] = nil
            end
            -- Snared: a net ring drags at his feet.
            if h.slow_t > 0.0 and not h.dead then
                local ppu = Game.cam.ppu
                local sx, sy = w2s(h.x, h.y)
                local rr = h.def.radius * 4.0 * ppu
                draw("hero_net", sx - rr * 0.5, sy - rr * 0.5, rr, rr, { 0, 0, 0, 0 },
                    { image = DATA.sprites.net, no_input = true, image_tint = { C.bone[1], C.bone[2], C.bone[3], 0.6 } })
            else
                Game._live["hero_net"] = nil
            end
        end
    end
end

local function draw_projectiles()
    for _, p in ipairs(Game.projectiles) do
        local sx, sy = w2s(p.x, p.y)
        local shw = p.size * Game.cam.ppu * 0.6
        draw(p.id .. "_sh", sx - shw * 0.5, sy - shw * 0.25, shw, shw * 0.5,
            { 0.0, 0.0, 0.0, 0.30 }, { no_input = true })
        draw_sprite(p.id, p.x, p.y, p.size, DATA.sprites.net, C.bone, { z = p.z, core_alpha = 0.0 })
    end
end

local function draw_bloods(dt)
    local survivors = {}
    for _, b in ipairs(Game.bloods) do
        b.life = b.life - dt
        if b.life > 0.0 then
            survivors[#survivors + 1] = b
            local a = clampn(b.life / 6.0, 0.0, 0.7)
            local sx, sy = w2s(b.x, b.y)
            local px = b.size * Game.cam.ppu
            draw(b.id, sx - px * 0.5, sy - px * 0.4, px, px, { b.color[1], b.color[2], b.color[3], a },
                { image = DATA.sprites.splat, no_input = true })
        else
            Game._live[b.id] = nil
        end
    end
    Game.bloods = survivors
end

-- ---- HUD -------------------------------------------------------------------

local function draw_hud(sw, sh)
    draw("title", 20, 16, 460, 40, { 0, 0, 0, 0 },
        { title = "COLOSSEUM", text_color = { C.gold_hot[1], C.gold_hot[2], C.gold_hot[3], 1.0 }, font_scale = 1.3, no_input = true })

    if Game.phase == "combat" then
        local h = Game.hero
        local pct = h and (h.hp / h.hp_max) or 0.0
        local col = pct > 0.5 and { 0.55, 0.30, 0.05, 0.95 } or { 0.75, 0.16, 0.10, 0.95 }
        Art.bar(SCREEN, "hp", sw * 0.5 - 240.0, 24.0, 480.0, 30.0, pct, col,
            { label = (h and h.def.name or "HERO") .. string.format("   %d / %d", math.floor((h and h.hp or 0) + 0.5), math.floor((h and h.hp_max or 1) + 0.5)),
              border = { C.gold[1], C.gold[2], C.gold[3], 0.9 } })
        Game._live["hp_bg"] = true; Game._live["hp_fg"] = true; Game._live["hp_label"] = true

        -- Round readout.
        local round_txt
        if Game.round == DATA.boss_round and Game.boss and Game.boss.alive then
            round_txt = "ROUND 5 / 5  -  THE MASTER"
        elseif Game.round_state == "closing" or Game.round_state == "break" then
            round_txt = "ROUND " .. Game.round .. " CLEARED"
        elseif Game.round_state == "opening" then
            round_txt = "ROUND " .. Game.round .. " / " .. #DATA.rounds .. "  -  GATES RISING"
        else
            round_txt = "ROUND " .. Game.round .. " / " .. #DATA.rounds .. "      Foes: " .. tostring(#Game.enemies + ((Game.boss and Game.boss.alive) and 1 or 0))
        end
        draw("round", sw - 380.0, 24.0, 360.0, 26.0, { 0, 0, 0, 0 },
            { label = round_txt, text_color = { C.gold[1], C.gold[2], C.gold[3], 1.0 }, no_input = true })

        -- CROWD FURY bar — the signature readout.
        local fpct = Game.fury / FURY.max
        local fcol = fpct > 0.85 and { 0.85, 0.20, 0.10, 0.95 } or { C.gold[1], C.gold[2], C.gold[3], 0.95 }
        Art.bar(SCREEN, "fury", sw * 0.5 - 240.0, sh - 56.0, 480.0, 24.0, fpct, fcol,
            { label = "CROWD FURY", border = { C.gold_hot[1], C.gold_hot[2], C.gold_hot[3], 0.9 } })
        Game._live["fury_bg"] = true; Game._live["fury_fg"] = true; Game._live["fury_label"] = true

        -- Boss health bar (only while the Master stands).
        if Game.boss and Game.boss.alive then
            local bpct = Game.boss.hp / Game.boss.hp_max
            Art.bar(SCREEN, "boss_hp", sw * 0.5 - 300.0, sh - 92.0, 600.0, 22.0, bpct,
                { 0.65, 0.50, 0.10, 0.95 }, { label = "THE COLOSSEUM MASTER", border = { C.gold_hot[1], C.gold_hot[2], C.gold_hot[3], 0.9 } })
            Game._live["boss_hp_bg"] = true; Game._live["boss_hp_fg"] = true; Game._live["boss_hp_label"] = true
        end

        draw("ctrls", 20, sh - 50.0, 820.0, 26.0, { 0, 0, 0, 0 },
            { label = "WASD / arrows move   -   [Space] " .. ((h and h.def.counter) and "strike / riposte" or "cleave") .. "   -   [Tab] swap fighter   -   [R] restart",
              text_color = { 0.85, 0.74, 0.55, 1.0 }, no_input = true })
    end

    if Game.phase == "won" or Game.phase == "lost" then
        local won = Game.phase == "won"
        draw("end", sw * 0.5 - 320.0, sh * 0.40, 640.0, 120.0,
            won and { 0.16, 0.10, 0.02, 0.94 } or { 0.16, 0.04, 0.04, 0.94 },
            { border = won and { C.gold_hot[1], C.gold_hot[2], C.gold_hot[3], 0.95 } or { 0.9, 0.2, 0.18, 0.95 },
              title = won and "THE GAMES ARE YOURS" or "YOU DIED",
              body = "Press [R] to enter the sand again  -  [Tab] swaps fighter", no_input = true })
    end

    if Game.flash ~= "" and Game.flash_t > 0.0 then
        draw("flash", sw * 0.5 - 280.0, 64.0, 560.0, 30.0, { 0, 0, 0, 0 },
            { label = Game.flash, text_color = { C.gold_hot[1], C.gold_hot[2], C.gold_hot[3], math.min(1.0, Game.flash_t) }, no_input = true })
    end

    -- A roar flare around the screen edge when a champion is released.
    if Game.fury_flare > 0.02 then
        draw("roar_flare", 0, 0, sw, sh, { 0, 0, 0, 0 },
            { image = DATA.sprites.glow, no_input = true,
              image_tint = { C.gold_hot[1], C.gold_hot[2], C.gold_hot[3], 0.22 * Game.fury_flare } })
    else
        Game._live["roar_flare"] = nil
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
    if key_pressed("Tab") then
        cycle_hero()
        if Game.phase ~= "combat" or Game.round_state == "opening" then reset_game() end
    end

    if Game.phase == "combat" then
        Game.fury = math.max(0.0, Game.fury - FURY.decay * dt)   -- the lull bleeds it down
        Game.fury_flare = math.max(0.0, Game.fury_flare - dt)
        update_hero(dt)
        update_rounds(dt)
        update_enemies(dt)
        update_projectiles(dt)
        if Game.boss then update_boss(dt, Game.hero) end
    end

    -- Flash decay.
    Game.flash_t = math.max(0.0, Game.flash_t - dt)
    if Game.flash ~= Game.last_flash then Game.flash_t = 2.4; Game.last_flash = Game.flash end
    if Game.flash_t <= 0.0 then Game.flash = "" end

    -- ---- render ----
    local sw, sh = recompute_cam()
    -- The bottom, full-screen input quad keeps the canvas consistent with the other
    -- 2D modes (no clicks are needed here — the hero is driven by keys).
    draw("world_input", 0, 0, sw, sh, { 0, 0, 0, 0 }, { no_input = true })
    draw_stands(sw, sh)
    draw_world_floor(sw, sh)
    draw_blood_overlay()
    draw_bloods(dt)
    draw_gates()
    draw_actors()
    draw_projectiles()
    draw_torches()
    draw_hud(sw, sh)

    sweep_stale()
end

-- ---------------------------------------------------------------------------
-- Lifecycle (standalone, ATH_MODE=colosseum)
-- ---------------------------------------------------------------------------

local function init()
    if runtime_ui then
        if runtime_ui.set_title then runtime_ui.set_title(SCREEN, "Colosseum") end
        if runtime_ui.set_screen_overlay then runtime_ui.set_screen_overlay(SCREEN, true) end
        if runtime_ui.show then runtime_ui.show(SCREEN) end
    end
    local seed = ATH_COMMON.getenv_number and ATH_COMMON.getenv_number("ATH_COLOSSEUM_SEED", nil) or nil
    if seed then math.randomseed(math.floor(seed)) end
    build_floor_tiles()
    reset_game()
    if script and script.on_update then
        script.on_update(UPDATE_ID, update, "play")
    else
        _G.update = update
    end
    log("init arena " .. tostring(DATA.arena.half_w * 2) .. "x" .. tostring(DATA.arena.half_h * 2))
end

local function destroy()
    if script and script.remove_update then script.remove_update(UPDATE_ID) end
    if runtime_ui and runtime_ui.clear then runtime_ui.clear(SCREEN) end
    log("destroyed")
end

-- Only seize the engine loop when launched as the standalone mode. When the menu
-- shell merely enumerates this file for its { meta } (ATH_MODE=menu), we must NOT
-- start a loop — we just return the contract below.
if ATH_COMMON.getenv("ATH_MODE", "menu") == "colosseum" then
    hooks { init = init, destroy = destroy }
end

-- ===========================================================================
-- Menu contract — { meta, config }. The shell can only drive the shared Duel, so
-- this config is a valid Colosseum-themed duel fallback (same cast). CROWD FURY
-- survives: it climbs as the hero deals/takes damage and, at max, looses a FREE
-- Iron Champion onto the field via Duel:spawn_one. The real game is the loop above.
-- ===========================================================================

local DUEL_FURY_MAX = 100.0
local DUEL_FURY_PER_KILL = 13.0
local DUEL_FURY_PER_DAMAGE = 0.45

local function duel_random_spawn(D)
    if D.spawns and #D.spawns > 0 then
        return D.spawns[math.random(#D.spawns)]
    end
    local A = D.arena
    return { x = math.floor(A.w * 0.5), y = math.floor(A.h * 0.5) }
end

local function duel_update_fury(D, dt)
    local f = D.colosseum
    if not f then return end
    -- Bleed the meter down during a lull.
    f.fury = math.max(0.0, f.fury - 1.4 * dt)
    -- Blood spilled = hero damage taken + foes felled since last tick.
    local hp = D.hero and D.hero.hp or 0.0
    if f.last_hp == nil then f.last_hp = hp end
    if hp < f.last_hp then f.fury = math.min(DUEL_FURY_MAX, f.fury + (f.last_hp - hp) * DUEL_FURY_PER_DAMAGE) end
    f.last_hp = hp
    local alive = D:count_alive()
    if f.last_alive == nil then f.last_alive = alive end
    if alive < f.last_alive then f.fury = math.min(DUEL_FURY_MAX, f.fury + (f.last_alive - alive) * DUEL_FURY_PER_KILL) end
    f.last_alive = alive
    -- At max, the crowd bays for a champion: loose a FREE Iron Champion.
    if f.fury >= DUEL_FURY_MAX then
        f.fury = 0.0
        if D.spawn_one then
            D:spawn_one(duel_random_spawn(D), (D.roles and D.roles.elite) or "iron_champion", true)
            D:set_flash("CROWD FURY — CHAMPION RELEASED!")
        end
    end
end

return {
    meta = {
        id = "colosseum",
        name = "Colosseum",
        tagline = "survive the sand; feed the crowd",
        blurb = "A gladiatorial pit ringed by a baying crowd. Survive five escalating rounds through the portcullis gates — and beware the CROWD FURY: spill blood and the mob looses a free Iron Champion. Round 5 wakes the Colosseum Master. (Standalone: ATH_MODE=colosseum. From the menu it runs the duel fallback.)",
        side_hint = "hero",
        accent = { 0.800, 0.600, 0.0, 0.95 },
        minimap = {
            bg = { 0.102, 0.059, 0.0, 1.0 },
            rects = {
                { 0.10, 0.10, 0.80, 0.80, { 0.420, 0.200, 0.0, 1.0 } },   -- sand floor
                { 0.06, 0.06, 0.88, 0.04, { 0.800, 0.600, 0.0, 1.0 } },   -- crowd stands (top)
                { 0.06, 0.90, 0.88, 0.04, { 0.800, 0.600, 0.0, 1.0 } },   -- ...bottom
                { 0.44, 0.06, 0.12, 0.05, { 0.34, 0.32, 0.30, 1.0 } },    -- north portcullis
                { 0.46, 0.46, 0.08, 0.08, { 0.620, 0.460, 0.30, 1.0 } },  -- hero (centre)
                { 0.24, 0.30, 0.05, 0.06, { 0.560, 0.300, 0.08, 1.0 } },  -- a foe
                { 0.70, 0.62, 0.05, 0.06, { 0.545, 0.0, 0.0, 1.0 } },     -- spilled blood
            },
        },
    },

    config = {
        id = "colosseum",
        name = "Colosseum",
        theme = Colo.theme,
        arena = { width = 48, height = 36, pad = 2, ortho_size = 38.0 },
        hero = { hp_max = 130.0, dps = 22.0, cleave = 3, attack_range = 1.3, speed = 2.35, kite_speed = 2.9, actor = Colo.hero_actor },
        archetypes = Colo.archetypes,
        roles = Colo.roles,
        spawn = { interval_start = 0.75, interval_min = 0.32, batch_start = 3, batch_max = 7, cap_start = 28, cap_max = 86, brute_after = 24.0 },
        reserve_start = 320.0,
        round_seconds = 14.0,
        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 13 == 0) then return "colosseum_master" end
            if D.spawn_counter % 7 == 0 then return "net_thrower" end
            if D.spawn_counter % 4 == 0 then return "sand_beast" end
            if D.spawn_counter % 9 == 0 then return "iron_champion" end
            return "gladiator"
        end,
        hooks = {
            on_start = function(D) D.colosseum = { fury = 0.0, last_hp = nil, last_alive = nil } end,
            on_reset = function(D) if D.colosseum then D.colosseum.fury = 0.0; D.colosseum.last_hp = nil; D.colosseum.last_alive = nil end end,
            on_combat_tick = function(D, dt) duel_update_fury(D, dt) end,
            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local f = D.colosseum and D.colosseum.fury or 0.0
                local pct = f / DUEL_FURY_MAX
                Art.bar(D.hud, "colo_fury", 24.0, sh - 150.0, 380.0, 30.0, pct,
                    { 0.800, 0.600, 0.0, 0.9 }, { label = "CROWD FURY", border = { 1.0, 0.78, 0.22, 0.9 } })
            end,
        },
    },
}
