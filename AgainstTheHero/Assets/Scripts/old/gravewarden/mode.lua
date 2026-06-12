-- GRAVEWARDEN — a 2D top-down graveyard hunt, drowned in fog, in the Dark-Souls key.
--
-- Unlike the index's card-duel modes, GRAVEWARDEN is its own little GAME: it does
-- NOT run on the shared 3D Duel engine. It is a self-contained, real-time, top-down
-- arena drawn entirely on the runtime_ui canvas (the same quad/image API the menu
-- uses), driven by its own update loop — mirroring the standalone pattern of
-- modes/pit, modes/rush and modes/horde. Launch it with ATH_MODE=gravewarden.
--
-- TWO PHASES:
--   1. PLACEMENT — you are the graveyard. Plant up to 6 TOMBSTONE SPAWNERS around
--      the yard (Graves, Archer Cairns, Wraith Crypts) and pick which hero gets
--      buried in. Click to plant; [Enter] opens the gate.
--   2. COMBAT — you then DRIVE that hero (WASD / arrows) under a FOG OF WAR: the
--      world is black beyond a tight ring of sight. The graves you planted RISE
--      the dead on timers, in three escalating WAVES — but every grave GLOWS
--      faintly through the fog for a beat before it erupts, your only warning. At
--      wave 3 the mausoleum tears open and the GRAVEWARDEN rises: a massive
--      skeleton with a scythe. Slay it to win.
--
-- The camera FOLLOWS the hero overhead, so the fog stays claustrophobic. Animation
-- is procedural-from-sprites: the dead cycle through their walk frames; graves
-- pulse their warning aura; the hero plays an 8-directional walk that bobs as it
-- strides. Physics is hand-rolled 2D: WASD locomotion, boid separation, parabolic
-- arrows, telegraphed AoE sweeps, and a rectangular wall clamp. All art is from
-- tools/gen_textures_gravewarden.py and OPTIONAL — a missing PNG just falls back
-- to a flat silhouette colour, so the game still runs.
--
-- This file ALSO returns { meta, config } at the bottom so the mode is discover-
-- able from the battlefield menu; that path can only run the shared Duel, so it
-- falls back to a valid Gravewarden-themed duel (same cast, "risen graves" hazard).

local Art   = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Grave = ATH_COMMON.load_script("Scripts/modes/gravewarden/characters.lua", "gravewarden characters", _ENV)

local DATA = Grave.grave2d
local C = DATA.palette
local W = DATA.waves

-- ===========================================================================
-- The 2D game
-- ===========================================================================

local SCREEN = "ath.gravewarden"
local UPDATE_ID = "against_the_hero_gravewarden"

local Game = {
    phase = "placement",      -- "placement" | "combat" | "won" | "lost"
    key_down = {},
    undead = {},              -- the risen dead + boss currently on the field
    projectiles = {},         -- bone arrows in flight
    bloods = {},              -- blood/bone-dust decals (world-anchored, fading)
    graves = {},              -- planted tombstones (active spawners in combat)
    placed = {},              -- entries during placement: { id, x, y }
    sel_grave = "risen_grave",
    sel_hero = "exorcist",
    budget = 0,
    time = 0.0,               -- monotonic clock (drives animation)
    wave = 0,                 -- 0 in placement; 1..3 in combat
    wave_time = 0.0,          -- seconds spent in the current wave
    summoned = 0,             -- total undead risen (drives wave escalation)
    boss = nil,               -- the Gravewarden, once it rises
    boss_state = "buried",    -- "buried" | "opening" | "risen"
    boss_open_t = 0.0,
    light_flare = 0.0,        -- Exorcist Consecrate fog-flare timer
    flash = "", flash_t = 0.0, last_flash = nil,
    cam = { ox = 0.0, oy = 0.0, ppu = 36.0 },
    _live = {}, _prev = {},
    next_id = 0,
}

-- ---- small helpers ---------------------------------------------------------

local function log(msg) if pe_log then pe_log("[ATH:GRAVEWARDEN] " .. tostring(msg)) end end

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

-- Cursor in surface pixels (mirrors the pit/ui_horde nil-safe probe order).
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

-- ---- arena geometry --------------------------------------------------------

local function inside_arena(wx, wy, margin)
    local m = margin or 0.0
    return wx >= -DATA.arena.half_w + m and wx <= DATA.arena.half_w - m
       and wy >= -DATA.arena.half_h + m and wy <= DATA.arena.half_h - m
end

local function clamp_to_arena(wx, wy, radius)
    local r = radius or 0.0
    return clampn(wx, -DATA.arena.half_w + r, DATA.arena.half_w - r),
           clampn(wy, -DATA.arena.half_h + r, DATA.arena.half_h - r)
end

-- ---- camera (follows the hero; clamps so the fog frames him) ---------------

local function cam_target()
    if Game.phase == "combat" and Game.hero then return Game.hero.x, Game.hero.y end
    return 0.0, -2.0   -- placement / end: frame the yard a touch toward the crypt
end

local function recompute_cam()
    local sw, sh = Art.surface_size()
    local c = Game.cam
    local tx, ty = cam_target()
    -- A little overscan past the arena edge is fine — the fog hides it anyway.
    local view_hx = (sw * 0.5) / c.ppu
    local view_hy = (sh * 0.5) / c.ppu
    local lim_x = math.max(0.0, DATA.arena.half_w - view_hx + 5.0)
    local lim_y = math.max(0.0, DATA.arena.half_h - view_hy + 5.0)
    tx = clampn(tx, -lim_x, lim_x)
    ty = clampn(ty, -lim_y, lim_y)
    c.ox = sw * 0.5 - tx * c.ppu
    c.oy = sh * 0.5 - ty * c.ppu
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

-- ---- fog of war ------------------------------------------------------------

-- Light level (0..1) on a world point: full inside the sight ring, fading to
-- black past it. The Exorcist's Consecrate flares the whole ring outward briefly.
local function light_at(wx, wy)
    if Game.phase ~= "combat" or not Game.hero then return 1.0 end
    local flare = Game.light_flare > 0.0 and (4.0 * Game.light_flare) or 0.0
    local inner = DATA.arena.sight_inner + flare
    local outer = DATA.arena.sight_outer + flare * 1.4
    local d = len2(wx - Game.hero.x, wy - Game.hero.y)
    if d <= inner then return 1.0 end
    if d >= outer then return 0.0 end
    return 1.0 - (d - inner) / (outer - inner)
end

-- ---- canvas draw (records ids so stale ones get swept each frame) ----------

local function draw(id, x, y, w, h, fill, opts)
    Game._live[id] = true
    Art.quad(SCREEN, id, x, y, w, h, fill, opts)
end

-- A world-anchored sprite: a faint solid core (so it reads even with no art) plus
-- the textured quad on top. `size` is in world units; `alpha` is the fog-scaled
-- opacity; `z` lifts the sprite (lob height / bob).
local function draw_sprite(id, wx, wy, size, image, color, opts)
    opts = opts or {}
    local a = opts.alpha == nil and 1.0 or opts.alpha
    if a <= 0.01 then
        Game._live[id .. "_core"] = nil; Game._live[id] = nil
        return
    end
    local ppu = Game.cam.ppu
    local px = size * ppu
    local sx, sy = w2s(wx, wy)
    local zoff = (opts.z or 0.0) * ppu
    local cs = px * 0.5
    draw(id .. "_core", sx - cs * 0.5, sy - zoff - cs * 0.5, cs, cs,
        { color[1], color[2], color[3], (opts.core_alpha or 0.7) * a }, { no_input = true })
    draw(id, sx - px * 0.5, sy - zoff - px * 0.55, px, px, { 0, 0, 0, 0 },
        { image = image, no_input = true, image_tint = opts.tint })
end

-- ---- blood / bone-dust decals ----------------------------------------------

local function add_blood(wx, wy, big, color)
    Game.next_id = Game.next_id + 1
    Game.bloods[#Game.bloods + 1] = {
        id = "blood_" .. Game.next_id, x = wx, y = wy,
        size = (big and 2.4 or 1.4) + math.random() * 0.4, life = 6.0,
        color = color or C.blood,
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
        dir = 6,                      -- facing north (into the yard)
        moving = false, phase = 0.0,
        attack_cd = 0.0, attack_flash = 0.0,
        hit_flash = 0.0, dead = false,
    }
end

local function hero_take_damage(amount, what)
    local h = Game.hero
    if not h or h.dead or amount <= 0.0 then return end
    h.hp = h.hp - amount
    h.hit_flash = 0.18
    add_blood(h.x, h.y, false)
    if h.hp <= 0.0 then
        h.hp = 0.0; h.dead = true
        Game.phase = "lost"
        set_flash("YOU DIED")
        add_blood(h.x, h.y, true)
        log("hero slain by " .. tostring(what or "the dead"))
    end
end

-- The hero's sweep: a radial smite that damages every nearby undead at once. The
-- Exorcist's holy version flares the fog and smites spectral foes for extra.
local function hero_attack()
    local h = Game.hero
    if not h or h.dead or h.attack_cd > 0.0 then return end
    h.attack_cd = h.def.attack_cd
    h.attack_flash = 0.16
    if h.def.holy then Game.light_flare = 0.6 end   -- flare the fog on the swing
    local r = h.def.attack_range
    local r2 = r * r
    local function hit_target(e)
        if not e or not e.alive or e.rising then return end
        local dx, dz = e.x - h.x, e.y - h.y
        if dx * dx + dz * dz <= (r + (e.def.radius or 0.5)) * (r + (e.def.radius or 0.5)) then
            local dmg = h.def.attack_damage
            if h.def.holy and e.def.spectral then dmg = dmg * 1.5 end   -- holy burns the wraith-light
            e.hp = e.hp - dmg
            e.hit_flash = 0.18
            add_blood(e.x, e.y, false, e.def.eye or C.blood)
            if e.hp <= 0.0 then e.alive = false; add_blood(e.x, e.y, true, e.def.eye or C.blood) end
        end
    end
    for _, e in ipairs(Game.undead) do hit_target(e) end
    hit_target(Game.boss)
end

local function update_hero(dt)
    local h = Game.hero
    if not h then return end
    h.attack_cd = math.max(0.0, h.attack_cd - dt)
    h.hit_flash = math.max(0.0, h.hit_flash - dt)
    h.attack_flash = math.max(0.0, h.attack_flash - dt)
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
        h.x = h.x + ix * h.def.speed * dt
        h.y = h.y + iy * h.def.speed * dt
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
-- Undead (risen from graves) + the boss
-- ---------------------------------------------------------------------------

local function spawn_undead(def, x, y)
    Game.next_id = Game.next_id + 1
    return {
        id = "ud_" .. Game.next_id, def = def,
        x = x, y = y, hp = def.hp, alive = true,
        seed = math.random() * 6.28, hit_flash = 0.0,
        cd = 0.0,                       -- generic timer (touch / throw)
        rising = true, rise_t = 0.0,    -- emerge-from-earth animation
        moving = false,
    }
end

-- Boid separation: push apart from nearby kin so the dead surround the hero.
local function separation(e)
    local rad = e.def.sep_radius or 0.0
    if rad <= 0.0 then return 0.0, 0.0 end   -- wraiths phase freely
    local sx, sz = 0.0, 0.0
    local r2 = rad * rad
    for _, o in ipairs(Game.undead) do
        if o ~= e and o.alive and not o.rising then
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

-- A melee shambler/wraith: seek the hero (with separation) and bite on contact.
local function update_seeker(e, dt, h)
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

local function throw_arrow(e, h)
    local pj = e.def.projectile
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
    local T = math.max(0.35, dist / (pj.speed or 10.0))
    Game.next_id = Game.next_id + 1
    Game.projectiles[#Game.projectiles + 1] = {
        id = "proj_" .. Game.next_id,
        x0 = e.x, y0 = e.y, tx = tx, ty = ty,
        t = 0.0, T = T, peak = pj.arc_peak or 2.6,
        dmg = pj.damage or 16.0, blast = pj.blast or 1.2, size = pj.size or 0.75,
    }
end

-- A Grave Archer: hold a preferred band and lob bone arrows that lead the hero.
local function update_archer(e, dt, h)
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
        e.cd = e.def.throw_cd or 2.0
        throw_arrow(e, h)
    end
end

-- The Gravewarden: a slow seeker with a telegraphed scythe SWEEP (a wide AoE ring
-- around itself). `b.sweep_phase`: nil/"idle" -> "warn" -> "active".
local function update_boss(dt, h)
    local b = Game.boss
    if not b or not b.alive then return end
    b.hit_flash = math.max(0.0, b.hit_flash - dt)
    if b.rising then
        b.rise_t = b.rise_t + dt
        if b.rise_t >= W.rise_time then b.rising = false end
        return
    end
    local sw = b.def.sweep
    b.sweep_cd = math.max(0.0, (b.sweep_cd or 0.0) - dt)

    if b.sweep_phase == "warn" then
        b.sweep_t = b.sweep_t + dt
        if b.sweep_t >= sw.telegraph then
            b.sweep_phase = "active"; b.sweep_t = 0.0
            local dx, dz = h.x - b.x, h.y - b.y
            if not h.dead and dx * dx + dz * dz <= sw.range * sw.range then
                hero_take_damage(sw.damage, "the Gravewarden's scythe")
            end
        end
        return   -- root while winding up
    elseif b.sweep_phase == "active" then
        b.sweep_t = b.sweep_t + dt
        if b.sweep_t >= sw.active then b.sweep_phase = "idle"; b.sweep_t = 0.0 end
        return
    end

    -- Seek the hero.
    local dx, dz = h.x - b.x, h.y - b.y
    local d = len2(dx, dz)
    if d > 0.0001 then
        b.x = b.x + (dx / d) * b.def.speed * dt
        b.y = b.y + (dz / d) * b.def.speed * dt
        b.x, b.y = clamp_to_arena(b.x, b.y, b.def.radius)
    end
    b.moving = d > 0.05
    -- Wind up a sweep when the hero is in reach and the cooldown is up.
    if d <= sw.range * 0.92 and b.sweep_cd <= 0.0 then
        b.sweep_phase = "warn"; b.sweep_t = 0.0; b.sweep_cd = sw.cd
        set_flash("THE SCYTHE RISES")
    end
    -- A slow contact crush even outside the sweep.
    b.cd = math.max(0.0, (b.cd or 0.0) - dt)
    if not h.dead and d <= b.def.radius + h.def.radius + 0.3 and b.cd <= 0.0 then
        b.cd = b.def.touch_cd
        hero_take_damage(b.def.touch_damage, "the Gravewarden")
    end
end

local function update_undead(dt)
    local h = Game.hero
    local survivors = {}
    for _, e in ipairs(Game.undead) do
        e.hit_flash = math.max(0.0, e.hit_flash - dt)
        if e.alive then
            if e.rising then
                e.rise_t = e.rise_t + dt
                if e.rise_t >= W.rise_time then e.rising = false end
            else
                local k = e.def.kind
                if k == "archer" then update_archer(e, dt, h)
                else update_seeker(e, dt, h) end   -- shambler + wraith
            end
        end
        if e.alive then survivors[#survivors + 1] = e
        else Game._live[e.id] = nil; Game._live[e.id .. "_core"] = nil end
    end
    Game.undead = survivors
end

local function update_projectiles(dt)
    local h = Game.hero
    local survivors = {}
    for _, p in ipairs(Game.projectiles) do
        p.t = p.t + dt
        local frac = p.t / p.T
        if frac >= 1.0 then
            local dx, dz = h.x - p.tx, h.y - p.ty
            if not h.dead and (dx * dx + dz * dz) <= (p.blast + h.def.radius) * (p.blast + h.def.radius) then
                hero_take_damage(p.dmg, "a bone arrow")
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
-- The RISE — graves birthing the dead, wave by wave
-- ---------------------------------------------------------------------------

-- Rise the Gravewarden from the mausoleum (once, at wave 3).
local function rise_boss()
    if Game.boss then return end
    local m = DATA.arena.mausoleum
    local def = DATA.boss
    Game.next_id = Game.next_id + 1
    Game.boss = {
        id = "boss_" .. Game.next_id, def = def,
        x = m.x, y = m.y + 0.5, hp = def.hp, hp_max = def.hp, alive = true,
        seed = 0.0, hit_flash = 0.0, rising = true, rise_t = 0.0, moving = false,
        cd = 0.0, sweep_cd = def.sweep.cd * 0.6, sweep_phase = "idle", sweep_t = 0.0,
    }
    Game.boss_state = "risen"
    set_flash("THE GRAVEWARDEN RISES")
    log("the Gravewarden rises")
end

-- Step the three-wave escalation. A wave advances when its summoned-quota is met
-- OR its time runs out; wave 3 cracks the mausoleum open (boss_telegraph), then
-- rise_boss() fires.
local function update_waves(dt)
    Game.wave_time = Game.wave_time + dt

    if Game.wave < 3 then
        local q = W.quota[Game.wave] or 999
        local tl = W.time_limit[Game.wave] or 999
        if Game.summoned >= q or Game.wave_time >= tl then
            Game.wave = Game.wave + 1
            Game.wave_time = 0.0
            if Game.wave == 3 then
                Game.boss_state = "opening"
                Game.boss_open_t = 0.0
                set_flash("THE MAUSOLEUM SHUDDERS...")
            else
                set_flash("WAVE " .. Game.wave .. " — THE DEAD STIR")
            end
        end
    end

    -- The mausoleum cracks open, then the boss rises.
    if Game.boss_state == "opening" then
        Game.boss_open_t = Game.boss_open_t + dt
        if Game.boss_open_t >= W.boss_telegraph then rise_boss() end
    end
end

-- Each planted grave, once its wave is live, telegraphs (glows) then RISES one
-- undead, on its own cadence.
local function update_graves(dt)
    for _, g in ipairs(Game.graves) do
        local active = Game.wave >= g.def.wave_active
        if not active then
            g.glow = 0.0
        else
            if g.phase == "telegraph" then
                g.glow_t = g.glow_t + dt
                g.glow = math.min(1.0, g.glow_t / W.rise_telegraph)
                if g.glow_t >= W.rise_telegraph then
                    -- RISE: birth the undead this grave is keyed to.
                    local udef = DATA.undead[g.def.spawns]
                    Game.undead[#Game.undead + 1] = spawn_undead(udef, g.x, g.y)
                    Game.summoned = Game.summoned + 1
                    g.phase = "idle"
                    g.cd = g.def.rise_cd
                    g.glow = 0.0
                end
            else
                g.cd = g.cd - dt
                -- A faint resting pulse so a primed grave still reads in the fog.
                g.glow = 0.18 + 0.08 * math.sin(Game.time * 2.0 + g.seed)
                if g.cd <= 0.0 then
                    g.phase = "telegraph"; g.glow_t = 0.0
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Placement phase
-- ---------------------------------------------------------------------------

local function can_place(wx, wy)
    if not inside_arena(wx, wy, 1.5) then return false end
    local sp = DATA.arena.hero_spawn
    if len2(wx - sp.x, wy - sp.y) < 3.0 then return false end       -- not on the gate
    local m = DATA.arena.mausoleum
    if len2(wx - m.x, wy - m.y) < 3.5 then return false end         -- not in the crypt
    for _, pe in ipairs(Game.placed) do
        if len2(wx - pe.x, wy - pe.y) < 2.0 then return false end
    end
    return true
end

local function open_gate()
    Game.graves = {}
    for _, pe in ipairs(Game.placed) do
        local def = DATA.graves[pe.id]
        Game.graves[#Game.graves + 1] = {
            def = def, x = pe.x, y = pe.y,
            phase = "idle", cd = def.rise_cd * (0.4 + math.random() * 0.4),
            glow = 0.0, glow_t = 0.0, seed = math.random() * 6.28,
        }
    end
    spawn_hero()
    Game.undead = {}
    Game.projectiles = {}
    Game.bloods = {}
    Game.boss = nil
    Game.boss_state = "buried"
    Game.boss_open_t = 0.0
    Game.wave = 1
    Game.wave_time = 0.0
    Game.summoned = 0
    Game.time = 0.0
    Game.light_flare = 0.0
    Game.phase = "combat"
    set_flash("WAVE 1 — THE DEAD STIR")
    log("gate opened: " .. tostring(Game.sel_hero) .. " vs " .. tostring(#Game.graves) .. " graves")
end

local function reset_game()
    Game.placed = {}
    Game.graves = {}
    Game.undead = {}
    Game.projectiles = {}
    Game.bloods = {}
    Game.boss = nil
    Game.boss_state = "buried"
    Game.budget = DATA.placement.budget
    Game.phase = "placement"
    Game.hero = nil
    Game.wave = 0
    Game.summoned = 0
    Game.time = 0.0
    set_flash("RAISE THE GRAVEYARD  -  plant up to " .. tostring(Game.budget))
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

-- Build the floor grid once (2-unit dark-grass tiles across the whole yard).
local function build_floor_tiles()
    Game.floor = {}
    local step = 2.0
    local i = 0
    local y = -DATA.arena.half_h
    while y <= DATA.arena.half_h do
        local x = -DATA.arena.half_w
        while x <= DATA.arena.half_w do
            i = i + 1
            Game.floor[i] = { x = x, y = y, seed = (i * 37) % 100 / 100.0 }
            x = x + step
        end
        y = y + step
    end
end

local function draw_world_floor(sw, sh)
    -- The void: everything the fog has swallowed reads as near-black grass.
    draw("bg", 0, 0, sw, sh, { C.void[1], C.void[2], C.void[3], 1.0 }, { no_input = true })
    local ppu = Game.cam.ppu
    local tile = 2.0 * ppu
    for i, t in ipairs(Game.floor) do
        local sx, sy = w2s(t.x, t.y)
        -- Cull tiles off-screen; skip ones the fog has fully eaten.
        if sx > -tile and sx < sw + tile and sy > -tile and sy < sh + tile then
            local lit = light_at(t.x, t.y)
            if lit > 0.04 then
                local shade = (0.7 + 0.3 * t.seed) * lit
                draw("fl_" .. i, sx - tile * 0.5, sy - tile * 0.5, tile + 1.0, tile + 1.0,
                    { C.grass[1] * shade, C.grass[2] * shade, C.grass[3] * shade, 1.0 },
                    { image = DATA.sprites.grass, no_input = true, image_tint = { lit, lit, lit, 1.0 } })
            else
                Game._live["fl_" .. i] = nil
            end
        else
            Game._live["fl_" .. i] = nil
        end
    end
end

-- The mausoleum at the north end — the boss crypt. Glows and shudders as it opens.
local function draw_mausoleum()
    local m = DATA.arena.mausoleum
    local lit = light_at(m.x, m.y)
    local a = lit
    if Game.boss_state == "opening" then
        local p = Game.boss_open_t / W.boss_telegraph
        a = math.max(a, 0.35 + 0.5 * math.abs(math.sin(Game.time * 12.0)) * p)
    end
    draw_sprite("mausoleum", m.x, m.y, 8.0, DATA.sprites.mausoleum, C.stone,
        { alpha = a, core_alpha = 0.0, tint = (Game.boss_state == "opening") and { 0.7, 0.7, 1.0, a } or nil })
end

-- A planted grave: the tombstone plus its warning aura. The aura is drawn even in
-- fog (max with the glow) so a priming grave is your only early read on a RISE.
local function draw_grave(id, x, y, gdef, glow, size)
    local lit = light_at(x, y)
    local aura = math.max(0.0, glow or 0.0)
    -- Warning glow halo (visible through fog when the grave is telegraphing).
    if aura > 0.05 then
        local ppu = Game.cam.ppu
        local sx, sy = w2s(x, y)
        local gr = (size * 1.4 + 0.8 * aura) * ppu
        draw(id .. "_glow", sx - gr * 0.5, sy - gr * 0.5, gr, gr, { 0, 0, 0, 0 },
            { image = DATA.sprites.grave_glow, no_input = true,
              image_tint = { gdef.glow[1], gdef.glow[2], gdef.glow[3], math.min(0.9, aura) } })
    end
    local a = math.max(lit, aura * 0.6)
    draw_sprite(id, x, y, size, DATA.sprites.tomb[gdef.tomb], gdef.color, { alpha = a, core_alpha = 0.5 })
end

-- The depth-sorted actor pass (lower screen-y first -> south draws on top).
local function frame_image(def, seed)
    local n = def.frames or 1
    local f = (math.floor(Game.time * (def.fps or 6.0) + (seed or 0.0) * n) % n)
    return def.sprite_base .. tostring(f) .. ".png"
end

local function draw_actors()
    local list = {}
    for _, e in ipairs(Game.undead) do list[#list + 1] = { y = e.y, e = e } end
    if Game.boss then list[#list + 1] = { y = Game.boss.y, boss = Game.boss } end
    if Game.hero then list[#list + 1] = { y = Game.hero.y, hero = Game.hero } end
    table.sort(list, function(a, b) return a.y < b.y end)

    for _, item in ipairs(list) do
        if item.e then
            local e = item.e
            local lit = light_at(e.x, e.y)
            local a = math.max(lit, e.def.min_alpha or 0.0)
            -- A rising corpse heaves up out of the earth: grows + clears upward.
            local sway = (e.def.sway_amp or 0.0) * math.sin(Game.time * (e.def.sway_freq or 4.0) + e.seed)
            local size = e.def.size
            local z = 0.0
            if e.rising then
                local rp = clampn(e.rise_t / W.rise_time, 0.0, 1.0)
                size = e.def.size * (0.35 + 0.65 * rp)
                z = -(1.0 - rp) * 0.6
                a = a * rp
            end
            local col = e.def.color
            if e.hit_flash > 0.0 then col = { 1.0, 0.6, 0.5 } end
            local tint = nil
            if e.def.spectral then
                -- Wraith-light: a cold blue cast, always a touch self-lit.
                tint = { e.def.color[1] + 0.2, e.def.color[2] + 0.2, 1.0, math.min(1.0, a + 0.15) }
            end
            draw_sprite(e.id, e.x, e.y + sway, size, frame_image(e.def, e.seed), col, { alpha = a, z = z, tint = tint })
            -- Eyes: a faint dot pair so the dead are sensed before they're seen.
            if not e.rising and a < 0.5 then
                local ppu = Game.cam.ppu
                local sx, sy = w2s(e.x, e.y + sway)
                local er = e.def.size * 0.12 * ppu
                draw(e.id .. "_eye", sx - er, sy - e.def.size * 0.18 * ppu, er * 2.0, er,
                    { e.def.eye[1], e.def.eye[2], e.def.eye[3], 0.35 + 0.25 * math.sin(Game.time * 6.0 + e.seed) },
                    { no_input = true })
            end

        elseif item.boss then
            local b = item.boss
            local lit = light_at(b.x, b.y)
            local a = math.max(lit, b.def.min_alpha or 0.5)   -- always a looming presence
            local size = b.def.size
            local z = 0.0
            if b.rising then
                local rp = clampn(b.rise_t / W.rise_time, 0.0, 1.0)
                size = b.def.size * (0.4 + 0.6 * rp)
                z = -(1.0 - rp) * 1.2
                a = a * (0.4 + 0.6 * rp)
            end
            local col = b.def.color
            if b.hit_flash > 0.0 then col = { 1.0, 0.7, 0.6 } end
            -- Telegraph: the whole skeleton flares spectral while the scythe winds up.
            local tint = nil
            if b.sweep_phase == "warn" then
                local f = 0.5 + 0.5 * math.sin(Game.time * 18.0)
                tint = { 0.7 + 0.3 * f, 0.7 + 0.3 * f, 1.0, 1.0 }
            end
            draw_sprite("boss", b.x, b.y, size, frame_image(b.def, b.seed), col, { alpha = a, z = z, core_alpha = 0.0, tint = tint })
            -- The scythe-sweep ring (telegraph = thin warning; active = bright slash).
            if b.sweep_phase == "warn" or b.sweep_phase == "active" then
                local ppu = Game.cam.ppu
                local sx, sy = w2s(b.x, b.y)
                local rr = b.def.sweep.range * ppu * (b.sweep_phase == "active" and 2.0 or 2.0)
                local alpha = b.sweep_phase == "active" and 0.55 or (0.2 + 0.2 * math.abs(math.sin(Game.time * 16.0)))
                draw("boss_sweep", sx - rr * 0.5, sy - rr * 0.5, rr, rr, { 0, 0, 0, 0 },
                    { image = DATA.sprites.grave_glow, no_input = true, image_tint = { 0.7, 0.7, 1.0, alpha } })
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
                draw_sprite("hero", h.x, h.y, h.def.size * 0.9, img, { 0.4, 0.1, 0.1 }, { core_alpha = 0.4, alpha = 1.0 })
            else
                draw_sprite("hero", h.x, h.y, h.def.size, img, col, { z = bob, alpha = 1.0 })
            end
            -- The Exorcist's Consecrate ring (a bright holy flare on the swing).
            if h.def.holy and Game.light_flare > 0.0 then
                local ppu = Game.cam.ppu
                local sx, sy = w2s(h.x, h.y)
                local rr = h.def.attack_range * 2.2 * ppu * (1.0 + (0.6 - Game.light_flare))
                draw("hero_consecrate", sx - rr * 0.5, sy - rr * 0.5, rr, rr, { 0, 0, 0, 0 },
                    { image = DATA.sprites.grave_glow, no_input = true,
                      image_tint = { 0.8, 0.8, 1.0, math.min(0.7, Game.light_flare) } })
            else
                Game._live["hero_consecrate"] = nil
            end
        end
    end
end

local function draw_projectiles()
    for _, p in ipairs(Game.projectiles) do
        local sx, sy = w2s(p.x, p.y)
        local lit = math.max(light_at(p.x, p.y), 0.4)   -- arrows glow a little
        local shw = p.size * Game.cam.ppu * 0.6
        draw(p.id .. "_sh", sx - shw * 0.5, sy - shw * 0.25, shw, shw * 0.5,
            { 0.0, 0.0, 0.0, 0.30 * lit }, { no_input = true })
        draw_sprite(p.id, p.x, p.y, p.size, DATA.sprites.arrow, C.bone, { z = p.z, core_alpha = 0.0, alpha = lit })
    end
end

local function draw_bloods(dt)
    local survivors = {}
    for _, b in ipairs(Game.bloods) do
        b.life = b.life - dt
        if b.life > 0.0 then
            survivors[#survivors + 1] = b
            local lit = light_at(b.x, b.y)
            local a = clampn(b.life / 6.0, 0.0, 0.6) * lit
            if a > 0.02 then
                local sx, sy = w2s(b.x, b.y)
                local px = b.size * Game.cam.ppu
                draw(b.id, sx - px * 0.5, sy - px * 0.4, px, px, { b.color[1], b.color[2], b.color[3], a },
                    { image = DATA.sprites.splat, no_input = true })
            else
                Game._live[b.id] = nil
            end
        else
            Game._live[b.id] = nil
        end
    end
    Game.bloods = survivors
end

-- A few drifting fog puffs over the lit area to sell the graveyard murk.
local function draw_fog(sw, sh)
    if Game.phase ~= "combat" then
        for i = 1, 6 do Game._live["fog_" .. i] = nil end
        return
    end
    for i = 1, 6 do
        local a = (i / 6.0) * math.pi * 2.0
        local drift = Game.time * 0.12 + i * 1.7
        local fx = Game.hero.x + math.cos(a + drift) * (4.0 + (i % 3) * 2.0)
        local fy = Game.hero.y + math.sin(a * 1.3 + drift) * (3.5 + (i % 2) * 2.0)
        local sx, sy = w2s(fx, fy)
        local px = (6.0 + (i % 3) * 2.0) * Game.cam.ppu
        draw("fog_" .. i, sx - px * 0.5, sy - px * 0.5, px, px, { 0, 0, 0, 0 },
            { image = DATA.sprites.fog, no_input = true, image_tint = { 0.5, 0.55, 0.5, 0.10 } })
    end
end

local function draw_placement_ghost()
    local mx, my = mouse_pos()
    if not mx then return end
    local wx, wy = s2w(mx, my)
    local ok = can_place(wx, wy) and Game.budget > 0
    local def = DATA.graves[Game.sel_grave]
    local sx, sy = w2s(wx, wy)
    local px = def.size * Game.cam.ppu
    draw("ghost", sx - px * 0.5, sy - px * 0.5, px, px,
        { ok and 0.3 or 0.8, ok and 0.6 or 0.2, ok and 0.8 or 0.2, 0.30 },
        { image = DATA.sprites.tomb[def.tomb], border = ok and { 0.45, 0.6, 1.0, 0.9 } or { 0.9, 0.3, 0.2, 0.9 }, no_input = true })
end

-- ---- HUD -------------------------------------------------------------------

local function button(id, x, y, w, h, label, opts)
    opts = opts or {}
    local st = Art.widget_state(SCREEN, id)
    local hov = st and st.hovered
    Game._live[id] = true
    Art.quad(SCREEN, id, x, y, w, h, opts.fill or (hov and { 0.10, 0.12, 0.16, 0.96 } or { 0.07, 0.08, 0.09, 0.94 }),
        { border = opts.border or { 0.3, 0.35, 0.5, 0.95 }, label = label, subtitle = opts.subtitle,
          text_color = opts.text_color, selected = opts.selected, font_scale = opts.font_scale })
    return Art.consume_click(SCREEN, id)
end

local function draw_hud(sw, sh)
    draw("title", 20, 16, 460, 40, { 0, 0, 0, 0 },
        { title = "GRAVEWARDEN", text_color = { C.spectral_hot[1], C.spectral_hot[2], C.spectral_hot[3], 1.0 }, font_scale = 1.3, no_input = true })

    if Game.phase == "placement" then
        local px, py, pw, ph = 20.0, sh - 132.0, 248.0, 56.0
        for i, id in ipairs(DATA.grave_order) do
            local def = DATA.graves[id]
            local bx = px + (i - 1) * (pw + 10.0)
            if button("pal_" .. id, bx, py, pw, ph, "[" .. i .. "] " .. def.name,
                { subtitle = def.blurb, selected = (Game.sel_grave == id),
                  border = (Game.sel_grave == id) and { 0.5, 0.6, 1.0, 1.0 } or { 0.3, 0.35, 0.5, 0.9 } })
                or key_pressed(tostring(i)) then
                Game.sel_grave = id
            end
        end
        local hx = px + 3 * (pw + 10.0) + 10.0
        for i, id in ipairs(DATA.hero_order) do
            local def = DATA.heroes[id]
            if button("hero_" .. id, hx, py + (i - 1) * 28.0, 250.0, 24.0, def.name,
                { selected = (Game.sel_hero == id), font_scale = 0.85,
                  border = (Game.sel_hero == id) and { 0.7, 0.9, 1.0, 1.0 } or { 0.3, 0.4, 0.5, 0.9 } }) then
                Game.sel_hero = id
            end
        end
        draw("budget", px, py - 36.0, 720.0, 28.0, { 0, 0, 0, 0 },
            { label = "Graves left: " .. tostring(Game.budget) .. "      Click in the yard to plant  -  [Enter] open the gate  -  [Z] undo",
              text_color = { 0.78, 0.82, 0.8, 1.0 }, no_input = true })
        if button("open", sw - 290.0, sh - 132.0, 270.0, 56.0, "OPEN THE GATE  [Enter]",
            { border = { 0.5, 0.8, 0.6, 1.0 }, fill = { 0.08, 0.14, 0.10, 0.96 } }) then
            open_gate()
        end
        draw_placement_ghost()

    elseif Game.phase == "combat" then
        local h = Game.hero
        local pct = h and (h.hp / h.hp_max) or 0.0
        local col = pct > 0.5 and { 0.30, 0.35, 0.55, 0.95 } or { 0.65, 0.18, 0.18, 0.95 }
        Art.bar(SCREEN, "hp", sw * 0.5 - 240.0, 24.0, 480.0, 30.0, pct, col,
            { label = (h and h.def.name or "HERO") .. string.format("   %d / %d", math.floor((h and h.hp or 0) + 0.5), math.floor((h and h.hp_max or 1) + 0.5)),
              border = { 0.5, 0.6, 1.0, 0.9 } })
        Game._live["hp_bg"] = true; Game._live["hp_fg"] = true; Game._live["hp_label"] = true

        -- Wave / boss readout.
        local wave_txt
        if Game.boss and Game.boss.alive then
            wave_txt = "WAVE 3  -  THE GRAVEWARDEN WALKS"
        elseif Game.boss_state == "opening" then
            wave_txt = "WAVE 3  -  THE MAUSOLEUM OPENS..."
        else
            wave_txt = "WAVE " .. tostring(Game.wave) .. " / 3      Risen: " .. tostring(Game.summoned)
        end
        draw("wave", sw - 360.0, 24.0, 340.0, 26.0, { 0, 0, 0, 0 },
            { label = wave_txt, text_color = { 0.6, 0.65, 1.0, 1.0 }, no_input = true })

        -- Boss health bar (only while it walks).
        if Game.boss and Game.boss.alive then
            local bpct = Game.boss.hp / Game.boss.hp_max
            Art.bar(SCREEN, "boss_hp", sw * 0.5 - 300.0, sh - 56.0, 600.0, 22.0, bpct,
                { 0.5, 0.5, 0.95, 0.95 }, { label = "THE GRAVEWARDEN", border = { 0.7, 0.7, 1.0, 0.9 } })
            Game._live["boss_hp_bg"] = true; Game._live["boss_hp_fg"] = true; Game._live["boss_hp_label"] = true
        end

        draw("ctrls", 20, sh - 50.0, 760.0, 26.0, { 0, 0, 0, 0 },
            { label = "WASD / arrows move   -   [Space] " .. (Game.hero and Game.hero.def.holy and "consecrate" or "cleave") .. "   -   [R] rebuild",
              text_color = { 0.75, 0.78, 0.74, 1.0 }, no_input = true })
    end

    if Game.phase == "won" or Game.phase == "lost" then
        local won = Game.phase == "won"
        draw("end", sw * 0.5 - 320.0, sh * 0.40, 640.0, 120.0,
            won and { 0.08, 0.12, 0.16, 0.94 } or { 0.16, 0.04, 0.04, 0.94 },
            { border = won and { 0.5, 0.7, 1.0, 0.95 } or { 0.9, 0.2, 0.18, 0.95 },
              title = won and "THE GRAVEWARDEN FALLS" or "YOU DIED",
              body = "Press [R] to raise the graveyard again", no_input = true })
    end

    if Game.flash ~= "" and Game.flash_t > 0.0 then
        draw("flash", sw * 0.5 - 280.0, 64.0, 560.0, 30.0, { 0, 0, 0, 0 },
            { label = Game.flash, text_color = { 0.6, 0.65, 1.0, math.min(1.0, Game.flash_t) }, no_input = true })
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
        if key_pressed("Return") or key_pressed("Space") then open_gate() end
        if Art.consume_click(SCREEN, "world_input") and Game.budget > 0 then
            local mx, my = mouse_pos()
            if mx then
                local wx, wy = s2w(mx, my)
                if can_place(wx, wy) then
                    Game.placed[#Game.placed + 1] = { id = Game.sel_grave, x = wx, y = wy }
                    Game.budget = Game.budget - 1
                end
            end
        end
    elseif Game.phase == "combat" then
        Game.light_flare = math.max(0.0, Game.light_flare - dt)
        update_hero(dt)
        update_waves(dt)
        update_graves(dt)
        update_undead(dt)
        update_projectiles(dt)
        if Game.boss then
            update_boss(dt, Game.hero)
            if not Game.boss.alive then
                Game.phase = "won"
                set_flash("THE GRAVEWARDEN FALLS")
                log("the Gravewarden is slain")
            end
        end
    end

    -- Flash decay.
    Game.flash_t = math.max(0.0, Game.flash_t - dt)
    if Game.flash ~= Game.last_flash then Game.flash_t = 2.4; Game.last_flash = Game.flash end
    if Game.flash_t <= 0.0 then Game.flash = "" end

    -- ---- render ----
    local sw, sh = recompute_cam()
    -- The bottom, full-screen input quad: captures world clicks + carries the
    -- cursor position. Decorative world quads above it are no_input.
    draw("world_input", 0, 0, sw, sh, { 0, 0, 0, 0 })
    draw_world_floor(sw, sh)
    draw_bloods(dt)
    draw_mausoleum()
    -- Planted graves (during placement, preview them; in combat, the live spawners).
    if Game.phase == "placement" then
        for i, pe in ipairs(Game.placed) do
            local def = DATA.graves[pe.id]
            draw_grave("placed_" .. i, pe.x, pe.y, def, 0.0, def.size)
        end
    else
        for i, g in ipairs(Game.graves) do
            draw_grave("grave_" .. i, g.x, g.y, g.def, g.glow, g.def.size)
        end
    end
    draw_actors()
    draw_projectiles()
    draw_fog(sw, sh)
    draw_hud(sw, sh)

    sweep_stale()
end

-- ---------------------------------------------------------------------------
-- Lifecycle (standalone, ATH_MODE=gravewarden)
-- ---------------------------------------------------------------------------

local function init()
    if runtime_ui then
        if runtime_ui.set_title then runtime_ui.set_title(SCREEN, "Gravewarden") end
        if runtime_ui.set_screen_overlay then runtime_ui.set_screen_overlay(SCREEN, true) end
        if runtime_ui.show then runtime_ui.show(SCREEN) end
    end
    local seed = ATH_COMMON.getenv_number and ATH_COMMON.getenv_number("ATH_GRAVEWARDEN_SEED", nil) or nil
    if seed then math.randomseed(math.floor(seed)) end
    build_floor_tiles()
    reset_game()
    if script and script.on_update then
        script.on_update(UPDATE_ID, update, "play")
    else
        _G.update = update
    end
    log("init graveyard " .. tostring(DATA.arena.half_w * 2) .. "x" .. tostring(DATA.arena.half_h * 2))
end

local function destroy()
    if script and script.remove_update then script.remove_update(UPDATE_ID) end
    if runtime_ui and runtime_ui.clear then runtime_ui.clear(SCREEN) end
    log("destroyed")
end

-- Only seize the engine loop when launched as the standalone mode. When the menu
-- shell merely enumerates this file for its { meta } (ATH_MODE=menu), we must NOT
-- start a loop — we just return the contract below.
if ATH_COMMON.getenv("ATH_MODE", "menu") == "gravewarden" then
    hooks { init = init, destroy = destroy }
end

-- ===========================================================================
-- Menu contract — { meta, config }. The shell can only drive the shared Duel, so
-- this config is a valid Gravewarden-themed duel fallback (same cast; the RISE
-- becomes "risen graves" — stone markers that erupt a bone-burst at the hero).
-- The real game is the standalone loop above.
-- ===========================================================================

-- Duel signature mechanic — RISEN GRAVES. Markers tear up across the yard,
-- telegraph with a spectral glow, then erupt a bone-burst; the hero is mauled if
-- caught standing on one.
local GRAVE_FIRST, GRAVE_INTERVAL, GRAVE_INTERVAL_MIN = 4.0, 5.0, 2.2
local GRAVE_TELEGRAPH, GRAVE_ACTIVE, GRAVE_RADIUS, GRAVE_DMG, GRAVE_MAX = 1.4, 0.4, 2.3, 24.0, 5

local function duel_grave_tile(D)
    local A = D.arena
    for _ = 1, 20 do
        local x = math.random(A.pad + 2, A.w - A.pad - 2)
        local y = math.random(A.pad + 2, A.h - A.pad - 2)
        if D.map:is_walkable(x, y) then return x, y end
    end
    return math.floor(A.w * 0.5), math.floor(A.h * 0.5)
end

local function duel_clear_graves(D)
    for _, g in ipairs(D.grave and D.grave.graves or {}) do
        if Art.valid(g.node) then scene.delete_node(g.node) end
    end
    if D.grave then D.grave.graves = {} end
end

local function duel_update_graves(D, dt)
    local p = D.grave
    if not p then return end
    p.next = p.next - dt
    if p.next <= 0.0 and #p.graves < GRAVE_MAX then
        p.next = math.max(GRAVE_INTERVAL_MIN, GRAVE_INTERVAL - 0.4 * (D.round - 1))
        local x, y = duel_grave_tile(D)
        local node = Art.cylinder("Grave_Rise_" .. p.counter, vec3(x, 0.05, y), vec3(GRAVE_RADIUS, 0.05, GRAVE_RADIUS),
            C.spectral, D.groups.world, 1.4)
        p.counter = p.counter + 1
        p.graves[#p.graves + 1] = { x = x, z = y, t = 0.0, phase = "warn", node = node }
    end
    local keep = {}
    for _, g in ipairs(p.graves) do
        g.t = g.t + dt
        local alive = true
        if g.phase == "warn" then
            local pulse = 1.0 + 0.6 * math.sin(D.realtime * 14.0)
            if Art.valid(g.node) then material.set(g.node, "emissive", vec3(C.spectral[1] * pulse, C.spectral[2] * pulse, C.spectral[3] * pulse)) end
            if g.t >= GRAVE_TELEGRAPH then
                g.phase = "erupt"; g.t = 0.0
                if Art.valid(g.node) then g.node:set_scale(vec3(GRAVE_RADIUS, 1.2, GRAVE_RADIUS)) end
                Art.burst("ath_grave_rise_" .. tostring(g.x) .. "_" .. tostring(g.z), vec3(g.x, 1.0, g.z),
                    { preset = "enemy_take", count = 24, life_max = 0.45, spawn_radius = GRAVE_RADIUS * 0.6, noise_strength = 4.0, size_max = 0.26 })
                local dx, dz = D.hero.x - g.x, D.hero.z - g.z
                if not D.hero.dead and dx * dx + dz * dz <= GRAVE_RADIUS * GRAVE_RADIUS then
                    D:apply_hero_damage(GRAVE_DMG, { flash = "THE DEAD CLUTCH!" })
                end
            end
        elseif g.phase == "erupt" then
            if g.t >= GRAVE_ACTIVE then if Art.valid(g.node) then scene.delete_node(g.node) end alive = false end
        end
        if alive then keep[#keep + 1] = g end
    end
    p.graves = keep
end

return {
    meta = {
        id = "gravewarden",
        name = "Gravewarden",
        tagline = "raise the dead, then walk among them",
        blurb = "A fog-drowned graveyard. Plant the tombstones, then take a hero in: the dead RISE in waves, and at wave 3 the Gravewarden itself claws out of the crypt. (Standalone: ATH_MODE=gravewarden. From the menu it runs the duel fallback.)",
        side_hint = "horde",
        accent = { 0.467, 0.467, 1.0, 0.95 },
        minimap = {
            bg = { 0.039, 0.059, 0.039, 1.0 },
            rects = {
                { 0.06, 0.06, 0.88, 0.88, { 0.08, 0.13, 0.08, 1.0 } },  -- the yard
                { 0.44, 0.06, 0.12, 0.10, { 0.30, 0.30, 0.38, 1.0 } },  -- mausoleum (north)
                { 0.46, 0.84, 0.08, 0.08, { 0.78, 0.78, 0.63, 1.0 } },  -- hero (south)
                { 0.24, 0.40, 0.05, 0.06, { 0.24, 0.24, 0.18, 1.0 } },  -- planted graves
                { 0.66, 0.34, 0.05, 0.06, { 0.24, 0.24, 0.18, 1.0 } },
                { 0.50, 0.58, 0.05, 0.06, { 0.47, 0.47, 1.0, 1.0 } },   -- a risen wraith
                { 0.34, 0.66, 0.04, 0.04, { 0.80, 0.0, 0.0, 1.0 } },    -- risen eyes
            },
        },
    },

    config = {
        id = "gravewarden",
        name = "Gravewarden",
        theme = Grave.theme,
        arena = { width = 48, height = 38, pad = 2, ortho_size = 38.0 },
        hero = { hp_max = 110.0, dps = 21.0, cleave = 3, attack_range = 1.3, speed = 2.3, kite_speed = 2.85, actor = Grave.hero_actor },
        archetypes = Grave.archetypes,
        roles = Grave.roles,
        spawn = { interval_start = 0.75, interval_min = 0.32, batch_start = 3, batch_max = 7, cap_start = 28, cap_max = 86, brute_after = 22.0 },
        reserve_start = 320.0,
        round_seconds = 14.0,
        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 12 == 0) then return "gravewarden" end
            if D.spawn_counter % 7 == 0 then return "grave_archer" end
            if D.spawn_counter % 4 == 0 then return "bonewraith" end
            return "risen"
        end,
        hooks = {
            on_start = function(D) D.grave = { graves = {}, next = GRAVE_FIRST, counter = 0 } end,
            on_reset = function(D) duel_clear_graves(D); if D.grave then D.grave.next = GRAVE_FIRST end end,
            on_combat_tick = function(D, dt) duel_update_graves(D, dt) end,
            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local n = D.grave and #D.grave.graves or 0
                Art.quad(D.hud, "grave_rises", 24.0, sh - 150.0, 380.0, 30.0, { 0.05, 0.06, 0.08, 0.85 },
                    { border = { 0.467, 0.467, 1.0, 0.9 }, label = "Risen graves: " .. tostring(n) })
            end,
        },
    },
}
