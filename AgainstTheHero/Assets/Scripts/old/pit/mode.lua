-- THE PIT — a 2D top-down arena, grim and oppressive, in the Dark-Souls key.
--
-- Unlike the index's card-duel modes, THE PIT is its own little GAME: it does not
-- run on the shared 3D Duel engine. It is a self-contained, real-time, top-down
-- arena drawn entirely on the runtime_ui canvas (the same quad/image API the menu
-- uses), driven by its own update loop — mirroring the standalone pattern of
-- modes/rush and modes/horde. Launch it with ATH_MODE=pit.
--
-- TWO PHASES:
--   1. PLACEMENT — you are the pit. Set up to 5 monsters/traps around the stone
--      ring (Shade Walkers, Bone Throwers, Spike Traps) and pick which hero will
--      be thrown in. Click to place; [Enter] releases the hero.
--   2. COMBAT — you then DRIVE that hero (WASD / arrows) and try to reach the exit
--      gap in the north wall alive. Shade Walkers swarm with separation steering,
--      Bone Throwers lob arcing bones that lead you, Spike Traps erupt underfoot.
--      [Space] swing, [Shift] dash (Hunter). Survive the gauntlet you built.
--
-- Animation is procedural-from-sprites: torches flicker on a 4-frame, 8fps cycle;
-- monsters sway with an idle breath; the hero plays an 8-directional walk (its
-- sprite is chosen by movement heading and bobs as it strides). Physics is hand-
-- rolled 2D: WASD locomotion, boid separation, parabolic projectile arcs, and a
-- circular-wall clamp. All art is from tools/gen_textures_pit.py and OPTIONAL — a
-- missing PNG just falls back to a flat silhouette colour, so the game still runs.
--
-- This file ALSO returns { meta, config } at the bottom so the mode is discover-
-- able from the battlefield menu; that path can only run the shared Duel, so it
-- falls back to a valid Pit-themed duel (same cast, Spike Traps as the hazard).

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Pit = ATH_COMMON.load_script("Scripts/modes/pit/characters.lua", "pit characters", _ENV)

local DATA = Pit.pit2d
local C = DATA.palette

-- ===========================================================================
-- The 2D game
-- ===========================================================================

local SCREEN = "ath.pit"
local UPDATE_ID = "against_the_hero_pit"
local TORCH_FPS = 8.0

local Game = {
    phase = "placement",      -- "placement" | "combat" | "won" | "lost"
    key_down = {},
    entities = {},            -- monsters + traps released into the pit
    projectiles = {},
    bloods = {},              -- blood-splat decals (world-anchored, fading)
    placed = {},              -- entries during placement: { id, x, y }
    torches = {},             -- fixed ring positions: { x, y, seed }
    sel_horde = "shade_walker",
    sel_hero = "ashen_knight",
    budget = 0,
    time = 0.0,
    flash = "", flash_t = 0.0,
    cam = { ox = 0.0, oy = 0.0, ppu = 30.0 },
    _live = {}, _prev = {},
    next_id = 0,
}

-- ---- small helpers ---------------------------------------------------------

local function log(msg) if pe_log then pe_log("[ATH:PIT] " .. tostring(msg)) end end

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

-- Cursor in surface pixels (mirrors ui_horde's nil-safe probe order).
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

-- ---- world <-> screen ------------------------------------------------------

local function recompute_cam()
    local sw, sh = Art.surface_size()
    local R = DATA.arena.radius
    local avail = math.min(sw - 90.0, sh - 230.0)
    Game.cam.ppu = math.max(8.0, avail / (2.0 * R))
    Game.cam.ox = sw * 0.5
    Game.cam.oy = (sh - 150.0) * 0.5 + 70.0
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

-- A world-anchored sprite: a faint solid core (so it reads even with no art) plus
-- the textured quad on top. size is in world units.
local function draw_sprite(id, wx, wy, size, image, color, opts)
    opts = opts or {}
    local ppu = Game.cam.ppu
    local px = size * ppu
    local sx, sy = w2s(wx, wy)
    local zoff = (opts.z or 0.0) * ppu              -- lob height lifts the sprite
    local cs = px * 0.5
    draw(id .. "_core", sx - cs * 0.5, sy - zoff - cs * 0.5, cs, cs,
        { color[1], color[2], color[3], opts.core_alpha or 0.85 }, { no_input = true })
    draw(id, sx - px * 0.5, sy - zoff - px * 0.55, px, px, { 0, 0, 0, 0 },
        { image = image, no_input = true, image_tint = opts.tint })
end

-- ---- arena geometry --------------------------------------------------------

local function inside_pit(wx, wy, margin)
    local R = DATA.arena.radius - (margin or 0.0)
    return (wx * wx + wy * wy) <= R * R
end

local function clamp_to_pit(wx, wy, radius)
    local R = DATA.arena.radius - (radius or 0.0)
    local d = len2(wx, wy)
    if d > R and d > 0.0001 then
        local s = R / d
        return wx * s, wy * s
    end
    return wx, wy
end

local function build_floor_tiles()
    Game.floor = {}
    local R = DATA.arena.radius
    local step = 2.0
    local i = 0
    local y = -R
    while y <= R do
        local x = -R
        while x <= R do
            if (x * x + y * y) <= (R + 0.4) * (R + 0.4) then
                i = i + 1
                Game.floor[i] = { x = x, y = y, edge = (x * x + y * y) > (R - 1.6) * (R - 1.6) }
            end
            x = x + step
        end
        y = y + step
    end
end

local function build_torches()
    Game.torches = {}
    local n = DATA.arena.torch_count
    local R = DATA.arena.radius + 0.4
    for i = 1, n do
        local a = (i / n) * math.pi * 2.0 - math.pi * 0.5
        Game.torches[i] = { x = math.cos(a) * R, y = math.sin(a) * R, seed = i * 1.7 }
    end
end

-- ---- blood decals ----------------------------------------------------------

local function add_blood(wx, wy, big)
    Game.next_id = Game.next_id + 1
    Game.bloods[#Game.bloods + 1] = {
        id = "blood_" .. Game.next_id, x = wx, y = wy,
        size = (big and 2.4 or 1.4) + math.random() * 0.4, life = 6.0,
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
        dir = 6,                      -- facing north (toward the exit)
        moving = false, phase = 0.0,
        attack_cd = 0.0, attack_flash = 0.0,
        dash_cd = 0.0, dash_t = 0.0,
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
        log("hero slain by " .. tostring(what or "the pit"))
    end
end

local function update_hero(dt)
    local h = Game.hero
    if not h then return end
    h.attack_cd = math.max(0.0, h.attack_cd - dt)
    h.dash_cd = math.max(0.0, h.dash_cd - dt)
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

    -- Dash (Hunter only): a brief speed burst on [Shift].
    if h.def.dash then
        if h.dash_t > 0.0 then h.dash_t = math.max(0.0, h.dash_t - dt) end
        if (key_pressed("LeftShift") or key_pressed("RightShift") or key_pressed("Shift"))
            and h.dash_cd <= 0.0 and mag > 0.0 then
            h.dash_t = h.def.dash.time
            h.dash_cd = h.def.dash.cd
            set_flash("DASH")
        end
    end

    if mag > 0.0 then
        ix, iy = ix / mag, iy / mag
        local speed = h.def.speed
        if h.def.dash and h.dash_t > 0.0 then speed = h.def.dash.speed end
        h.x = h.x + ix * speed * dt
        h.y = h.y + iy * speed * dt
        h.x, h.y = clamp_to_pit(h.x, h.y, h.def.radius)
        -- 8-way facing from heading (0=E,2=S,4=W,6=N) — matches the sprite set.
        local ang = math.atan(iy, ix)
        h.dir = math.floor(ang / (math.pi / 4.0) + 0.5) % 8
        if h.dir < 0 then h.dir = h.dir + 8 end
        h.phase = h.phase + dt * h.def.walk_freq
    end

    -- Attack: [Space] / [J] sweep — damage every monster within reach.
    if (key_pressed("Space") or key_pressed("J") or key_pressed("Return")) and h.attack_cd <= 0.0 then
        h.attack_cd = h.def.attack_cd
        h.attack_flash = 0.14
        local r = h.def.attack_range + h.def.radius
        local r2 = r * r
        for _, e in ipairs(Game.entities) do
            if e.alive and e.kind ~= "trap" then
                local dx, dz = e.x - h.x, e.y - h.y
                if dx * dx + dz * dz <= r2 then
                    e.hp = e.hp - h.def.attack_damage
                    e.hit_flash = 0.18
                    add_blood(e.x, e.y, false)
                    if e.hp <= 0.0 then e.alive = false; add_blood(e.x, e.y, true) end
                end
            end
        end
    end

    -- Reached the exit gap?
    local ex, ey = DATA.arena.exit.x, DATA.arena.exit.y
    if len2(h.x - ex, h.y - ey) <= DATA.arena.exit_radius + h.def.radius then
        Game.phase = "won"
        set_flash("YOU ESCAPED THE PIT")
        log("hero escaped")
    end
end

-- ---------------------------------------------------------------------------
-- Monsters / traps
-- ---------------------------------------------------------------------------

local function spawn_entity(kind, def, x, y)
    Game.next_id = Game.next_id + 1
    return {
        id = "ent_" .. Game.next_id, kind = kind, def = def,
        x = x, y = y, hp = def.hp or 1.0, alive = true,
        seed = math.random() * 6.28, hit_flash = 0.0,
        cd = 0.0,                 -- generic timer (touch / throw)
        trap_phase = "armed", trap_t = 0.0,  -- traps only
    }
end

-- Boid separation: push apart from nearby kin so packs spread and surround.
local function separation(e)
    local sx, sz = 0.0, 0.0
    local rad = e.def.sep_radius or 1.4
    local r2 = rad * rad
    for _, o in ipairs(Game.entities) do
        if o ~= e and o.alive and o.kind ~= "trap" then
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

local function update_shade(e, dt, h)
    local dx, dz = h.x - e.x, h.y - e.y
    local d = len2(dx, dz)
    local sx, sz = 0.0, 0.0
    if d > 0.0001 then sx, sz = dx / d, dz / d end               -- seek the hero
    local px, pz = separation(e)
    local vx = sx + px * (e.def.sep_weight or 1.4)
    local vz = sz + pz * (e.def.sep_weight or 1.4)
    local vm = len2(vx, vz)
    if vm > 0.0001 then vx, vz = vx / vm, vz / vm end
    e.x = e.x + vx * e.def.speed * dt
    e.y = e.y + vz * e.def.speed * dt
    e.x, e.y = clamp_to_pit(e.x, e.y, e.def.radius)
    e.moving = vm > 0.01
    -- Contact bite.
    e.cd = math.max(0.0, e.cd - dt)
    if d <= e.def.radius + h.def.radius + 0.2 and e.cd <= 0.0 then
        e.cd = e.def.touch_cd
        hero_take_damage(e.def.touch_damage, "a Shade Walker")
    end
end

local function throw_bone(e, h)
    local pj = e.def.projectile
    -- Lead the hero's current motion so the arc lands where they're going.
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
        t = 0.0, T = T, peak = pj.arc_peak or 3.0,
        dmg = pj.damage or 18.0, blast = pj.blast or 1.2, size = pj.size or 0.9,
    }
end

local function update_thrower(e, dt, h)
    local dx, dz = h.x - e.x, h.y - e.y
    local d = len2(dx, dz)
    local dir = 0.0
    if d < (e.def.retreat_range or 5.0) then dir = -1.0          -- too close: back off
    elseif d > (e.def.hold_range or 10.0) then dir = 1.0 end     -- too far: close in
    if dir ~= 0.0 and d > 0.0001 then
        local px, pz = separation(e)
        local vx = (dx / d) * dir + px
        local vz = (dz / d) * dir + pz
        local vm = len2(vx, vz)
        if vm > 0.0001 then
            e.x = e.x + (vx / vm) * e.def.speed * dt
            e.y = e.y + (vz / vm) * e.def.speed * dt
            e.x, e.y = clamp_to_pit(e.x, e.y, e.def.radius)
        end
        e.moving = true
    else
        e.moving = false
    end
    e.cd = math.max(0.0, e.cd - dt)
    if e.cd <= 0.0 and d <= (e.def.hold_range or 10.0) + 1.0 then
        e.cd = e.def.throw_cd or 1.8
        throw_bone(e, h)
    end
end

local function update_trap(e, dt, h)
    e.trap_t = e.trap_t + dt
    local dx, dz = h.x - e.x, h.y - e.y
    local on = (dx * dx + dz * dz) <= (e.def.trigger_radius * e.def.trigger_radius)
    if e.trap_phase == "armed" then
        if on then e.trap_phase = "telegraph"; e.trap_t = 0.0 end
    elseif e.trap_phase == "telegraph" then
        if e.trap_t >= e.def.telegraph then
            e.trap_phase = "active"; e.trap_t = 0.0
            if (dx * dx + dz * dz) <= (e.def.radius + h.def.radius) * (e.def.radius + h.def.radius) then
                hero_take_damage(e.def.damage, "a Spike Trap")
            end
        end
    elseif e.trap_phase == "active" then
        if e.trap_t >= e.def.active then e.trap_phase = "cooldown"; e.trap_t = 0.0 end
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
            if e.kind == "shade" then update_shade(e, dt, h)
            elseif e.kind == "thrower" then update_thrower(e, dt, h)
            elseif e.kind == "trap" then update_trap(e, dt, h) end
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
        p.t = p.t + dt
        local frac = p.t / p.T
        if frac >= 1.0 then
            -- Landed: splash damage at the impact point.
            local dx, dz = h.x - p.tx, h.y - p.ty
            if not h.dead and (dx * dx + dz * dz) <= (p.blast + h.def.radius) * (p.blast + h.def.radius) then
                hero_take_damage(p.dmg, "a thrown bone")
            end
            add_blood(p.tx, p.ty, false)
            Game._live[p.id] = nil; Game._live[p.id .. "_core"] = nil
            Game._live[p.id .. "_sh"] = nil
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
-- Placement phase
-- ---------------------------------------------------------------------------

local function can_place(wx, wy)
    if not inside_pit(wx, wy, 1.2) then return false end
    local sp = DATA.arena.hero_spawn
    if len2(wx - sp.x, wy - sp.y) < 2.4 then return false end
    if len2(wx - DATA.arena.exit.x, wy - DATA.arena.exit.y) < 2.6 then return false end
    for _, pe in ipairs(Game.placed) do
        if len2(wx - pe.x, wy - pe.y) < 1.3 then return false end
    end
    return true
end

local function release_hero()
    Game.entities = {}
    for _, pe in ipairs(Game.placed) do
        local def = DATA.horde[pe.id]
        local kind = (pe.id == "shade_walker" and "shade")
            or (pe.id == "bone_thrower" and "thrower") or "trap"
        Game.entities[#Game.entities + 1] = spawn_entity(kind, def, pe.x, pe.y)
    end
    spawn_hero()
    Game.projectiles = {}
    Game.bloods = {}
    Game.time = 0.0
    Game.phase = "combat"
    set_flash("SURVIVE")
    log("released " .. tostring(Game.sel_hero) .. " vs " .. tostring(#Game.entities) .. " placed")
end

local function reset_game()
    Game.placed = {}
    Game.entities = {}
    Game.projectiles = {}
    Game.bloods = {}
    Game.budget = DATA.placement.budget
    Game.phase = "placement"
    Game.hero = nil
    Game.time = 0.0
    set_flash("BUILD THE PIT  -  place up to " .. tostring(Game.budget))
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local function draw_world_floor(sw, sh)
    draw("bg", 0, 0, sw, sh, { 0.03, 0.03, 0.035, 1.0 }, { no_input = true })
    local ppu = Game.cam.ppu
    local tile = 2.0 * ppu
    for i, t in ipairs(Game.floor) do
        local sx, sy = w2s(t.x, t.y)
        local shade = t.edge and 0.5 or 1.0
        draw("fl_" .. i, sx - tile * 0.5, sy - tile * 0.5, tile + 1.0, tile + 1.0,
            { C.stone[1] * shade, C.stone[2] * shade, C.stone[3] * shade, 1.0 },
            { image = t.edge and DATA.sprites.rim or DATA.sprites.floor, no_input = true })
    end
end

local function draw_exit()
    local ex, ey = DATA.arena.exit.x, DATA.arena.exit.y
    local pulse = 0.6 + 0.4 * math.sin(Game.time * 3.0)
    draw_sprite("exit", ex, ey, 3.4, DATA.sprites.exit, { C.fire[1], C.fire[2], C.fire[3] },
        { core_alpha = 0.0 })
    local sx, sy = w2s(ex, ey)
    draw("exit_lbl", sx - 60, sy + Game.cam.ppu * 1.4, 120, 26, { 0, 0, 0, 0 },
        { label = "EXIT", text_color = { C.fire[1], C.fire[2], C.fire[3], pulse }, no_input = true })
end

local function entity_image(e)
    if e.kind == "trap" then
        local active = (e.trap_phase == "telegraph" or e.trap_phase == "active")
        return active and e.def.sprite_fire or e.def.sprite
    end
    return e.def.sprite
end

-- Build the depth-sorted draw list (lower screen-y first → south draws on top).
local function draw_actors()
    local list = {}
    for _, e in ipairs(Game.entities) do list[#list + 1] = { y = e.y, e = e } end
    for _, t in ipairs(Game.torches) do list[#list + 1] = { y = t.y, torch = t } end
    if Game.hero then list[#list + 1] = { y = Game.hero.y, hero = Game.hero } end
    table.sort(list, function(a, b) return a.y < b.y end)

    for _, item in ipairs(list) do
        if item.torch then
            local t = item.torch
            local frame = (math.floor(Game.time * TORCH_FPS + t.seed) % 4) + 1
            -- Torches are tall: draw with an upward bias so the flame sits above
            -- its base; a 4-frame flicker chosen by the 8fps clock.
            local sx, sy = w2s(t.x, t.y)
            local px = 2.4 * Game.cam.ppu
            draw("torch_" .. t.x .. "_" .. t.y, sx - px * 0.5, sy - px * 0.78, px, px * 1.4,
                { 0, 0, 0, 0 }, { image = DATA.sprites.torch_frames[frame], no_input = true })
        elseif item.e then
            local e = item.e
            local sway = (e.def.sway_amp or 0.0) * math.sin(Game.time * (e.def.sway_freq or 3.0) + e.seed)
            local col = e.def.color
            if e.hit_flash > 0.0 then col = { 1.0, 0.5, 0.4 } end
            local img = entity_image(e)
            -- Telegraphing traps pulse red so the player can read the danger.
            local tint = nil
            if e.kind == "trap" and e.trap_phase == "telegraph" then
                tint = { 1.0, 0.3, 0.2, 0.6 + 0.4 * math.sin(Game.time * 24.0) }
            end
            draw_sprite(e.id, e.x, e.y + sway, e.def.size, img, col, { tint = tint })
        elseif item.hero then
            local h = item.hero
            local bob = (h.moving and not h.dead) and (h.def.walk_bob * math.abs(math.sin(h.phase))) or 0.0
            local col = h.def.color
            if h.hit_flash > 0.0 then col = { 1.0, 0.4, 0.3 }
            elseif h.attack_flash > 0.0 then col = { 1.0, 0.85, 0.5 } end
            local img = h.def.sprite_base .. tostring(h.dir) .. ".png"
            if h.dead then
                draw_sprite("hero", h.x, h.y, h.def.size * 0.9, img, { 0.4, 0.1, 0.1 }, { core_alpha = 0.4 })
            else
                draw_sprite("hero", h.x, h.y, h.def.size, img, col, { z = bob })
            end
        end
    end
end

local function draw_projectiles()
    for _, p in ipairs(Game.projectiles) do
        -- Ground shadow stays put; the bone lifts off it on the arc.
        local sx, sy = w2s(p.x, p.y)
        local shw = p.size * Game.cam.ppu * 0.6
        draw(p.id .. "_sh", sx - shw * 0.5, sy - shw * 0.25, shw, shw * 0.5,
            { 0.0, 0.0, 0.0, 0.35 }, { no_input = true })
        draw_sprite(p.id, p.x, p.y, p.size, DATA.sprites.bolt, { C.bone[1], C.bone[2], C.bone[3] },
            { z = p.z, core_alpha = 0.0 })
    end
end

local function draw_bloods(dt)
    local survivors = {}
    for _, b in ipairs(Game.bloods) do
        b.life = b.life - dt
        if b.life > 0.0 then
            survivors[#survivors + 1] = b
            local a = clampn(b.life / 6.0, 0.0, 0.85)
            local sx, sy = w2s(b.x, b.y)
            local px = b.size * Game.cam.ppu
            draw(b.id, sx - px * 0.5, sy - px * 0.4, px, px, { C.blood[1], C.blood[2], C.blood[3], a * 0.5 },
                { image = DATA.sprites.blood, no_input = true })
        else
            Game._live[b.id] = nil
        end
    end
    Game.bloods = survivors
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
        { ok and 0.3 or 0.8, ok and 0.8 or 0.2, 0.3, 0.30 },
        { image = def.sprite, border = ok and { 0.3, 0.9, 0.4, 0.9 } or { 0.9, 0.3, 0.2, 0.9 }, no_input = true })
end

-- ---- HUD -------------------------------------------------------------------

local function button(id, x, y, w, h, label, opts)
    opts = opts or {}
    local st = Art.widget_state(SCREEN, id)
    local hov = st and st.hovered
    Game._live[id] = true
    Art.quad(SCREEN, id, x, y, w, h, opts.fill or (hov and { 0.16, 0.10, 0.08, 0.96 } or { 0.09, 0.08, 0.08, 0.94 }),
        { border = opts.border or { 0.5, 0.3, 0.2, 0.95 }, label = label, subtitle = opts.subtitle,
          text_color = opts.text_color, selected = opts.selected, font_scale = opts.font_scale })
    return Art.consume_click(SCREEN, id)
end

local function draw_hud(sw, sh)
    -- Title.
    draw("title", 20, 16, 360, 40, { 0, 0, 0, 0 },
        { title = "THE PIT", text_color = { C.fire[1], C.fire[2], C.fire[3], 1.0 }, font_scale = 1.3, no_input = true })

    if Game.phase == "placement" then
        -- Horde palette (1/2/3 + click).
        local px, py, pw, ph = 20.0, sh - 132.0, 230.0, 56.0
        for i, id in ipairs(DATA.horde_order) do
            local def = DATA.horde[id]
            local bx = px + (i - 1) * (pw + 10.0)
            if button("pal_" .. id, bx, py, pw, ph, "[" .. i .. "] " .. def.name,
                { subtitle = def.blurb, selected = (Game.sel_horde == id),
                  border = (Game.sel_horde == id) and { 1.0, 0.5, 0.1, 1.0 } or { 0.5, 0.3, 0.2, 0.9 } })
                or key_pressed(tostring(i)) then
                Game.sel_horde = id
            end
        end
        -- Hero selector (Tab / click).
        local hx = px + 3 * (pw + 10.0) + 10.0
        for i, id in ipairs(DATA.hero_order) do
            local def = DATA.heroes[id]
            if button("hero_" .. id, hx, py + (i - 1) * 28.0, 240.0, 24.0, def.name,
                { selected = (Game.sel_hero == id), font_scale = 0.85,
                  border = (Game.sel_hero == id) and { 0.4, 0.7, 1.0, 1.0 } or { 0.3, 0.3, 0.4, 0.9 } }) then
                Game.sel_hero = id
            end
        end
        draw("budget", px, py - 36.0, 480.0, 28.0, { 0, 0, 0, 0 },
            { label = "Placements left: " .. tostring(Game.budget) .. "      Click in the pit to place  -  [Enter] release the hero  -  [Z] undo",
              text_color = { 0.85, 0.82, 0.78, 1.0 }, no_input = true })
        if button("release", sw - 280.0, sh - 132.0, 260.0, 56.0, "RELEASE THE HERO  [Enter]",
            { border = { 0.4, 0.9, 0.5, 1.0 }, fill = { 0.10, 0.16, 0.10, 0.96 } }) then
            release_hero()
        end
        draw_placement_ghost()

    elseif Game.phase == "combat" then
        local h = Game.hero
        local pct = h and (h.hp / h.hp_max) or 0.0
        local col = pct > 0.5 and { 0.55, 0.12, 0.10, 0.95 } or { 0.85, 0.18, 0.12, 0.95 }
        Art.bar(SCREEN, "hp", sw * 0.5 - 240.0, 24.0, 480.0, 30.0, pct, col,
            { label = (h and h.def.name or "HERO") .. string.format("   %d / %d", math.floor((h and h.hp or 0) + 0.5), math.floor((h and h.hp_max or 1) + 0.5)),
              border = { 1.0, 0.40, 0.0, 0.9 } })
        Game._live["hp_bg"] = true; Game._live["hp_fg"] = true; Game._live["hp_label"] = true
        draw("ctrls", 20, sh - 50.0, 700.0, 26.0, { 0, 0, 0, 0 },
            { label = "WASD / arrows move   -   [Space] swing" .. (h and h.def.dash and "   -   [Shift] dash" or "") .. "   -   [R] rebuild",
              text_color = { 0.8, 0.78, 0.74, 1.0 }, no_input = true })
        local alive = #Game.entities
        draw("count", sw - 220.0, 24.0, 200.0, 26.0, { 0, 0, 0, 0 },
            { label = "Horde remaining: " .. tostring(alive), text_color = { 0.85, 0.6, 0.5, 1.0 }, no_input = true })
    end

    -- Win / lose banner.
    if Game.phase == "won" or Game.phase == "lost" then
        local won = Game.phase == "won"
        draw("end", sw * 0.5 - 300.0, sh * 0.40, 600.0, 120.0,
            won and { 0.08, 0.14, 0.08, 0.94 } or { 0.16, 0.04, 0.04, 0.94 },
            { border = won and { 0.4, 0.9, 0.5, 0.95 } or { 0.9, 0.2, 0.18, 0.95 },
              title = won and "YOU ESCAPED THE PIT" or "YOU DIED",
              body = "Press [R] to build the pit again", no_input = true })
    end

    -- Flash line.
    if Game.flash ~= "" and Game.flash_t > 0.0 then
        draw("flash", sw * 0.5 - 260.0, 64.0, 520.0, 30.0, { 0, 0, 0, 0 },
            { label = Game.flash, text_color = { 1.0, 0.55, 0.2, math.min(1.0, Game.flash_t) }, no_input = true })
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

    -- Global input.
    if key_pressed("R") then reset_game() end

    if Game.phase == "placement" then
        -- Undo last placement.
        if key_pressed("Z") and #Game.placed > 0 then
            table.remove(Game.placed)
            Game.budget = Game.budget + 1
        end
        if key_pressed("Return") or key_pressed("Space") then release_hero() end
        -- Place on a world click that didn't land on a HUD button.
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
        update_hero(dt)
        update_entities(dt)
        update_projectiles(dt)
    end

    -- Flash decay.
    Game.flash_t = math.max(0.0, Game.flash_t - dt)
    if Game.flash ~= Game.last_flash then Game.flash_t = 2.2; Game.last_flash = Game.flash end
    if Game.flash_t <= 0.0 then Game.flash = "" end

    -- ---- render ----
    local sw, sh = recompute_cam()
    -- The bottom, full-screen input quad: captures world clicks + carries the
    -- cursor position. Decorative world quads above it are no_input, so clicks
    -- fall through to here; HUD buttons sit on top and steal their own clicks.
    draw("world_input", 0, 0, sw, sh, { 0, 0, 0, 0 })
    draw_world_floor(sw, sh)
    draw_bloods(dt)
    draw_exit()
    -- Placement preview of already-placed entities (so you see the pit you built).
    if Game.phase == "placement" then
        for i, pe in ipairs(Game.placed) do
            local def = DATA.horde[pe.id]
            draw_sprite("placed_" .. i, pe.x, pe.y, def.size, def.sprite, def.color, {})
        end
    end
    draw_actors()
    draw_projectiles()
    draw_hud(sw, sh)

    sweep_stale()
end

-- ---------------------------------------------------------------------------
-- Lifecycle (standalone, ATH_MODE=pit)
-- ---------------------------------------------------------------------------

local function init()
    if runtime_ui then
        if runtime_ui.set_title then runtime_ui.set_title(SCREEN, "The Pit") end
        if runtime_ui.set_screen_overlay then runtime_ui.set_screen_overlay(SCREEN, true) end
        if runtime_ui.show then runtime_ui.show(SCREEN) end
    end
    local seed = ATH_COMMON.getenv_number and ATH_COMMON.getenv_number("ATH_PIT_SEED", nil) or nil
    if seed then math.randomseed(math.floor(seed)) end
    build_floor_tiles()
    build_torches()
    reset_game()
    if script and script.on_update then
        script.on_update(UPDATE_ID, update, "play")
    else
        _G.update = update
    end
    log("init arena R=" .. tostring(DATA.arena.radius))
end

local function destroy()
    if script and script.remove_update then script.remove_update(UPDATE_ID) end
    if runtime_ui and runtime_ui.clear then runtime_ui.clear(SCREEN) end
    log("destroyed")
end

-- Only seize the engine loop when launched as the standalone mode. When the menu
-- shell merely enumerates this file for its { meta } (ATH_MODE=menu), we must NOT
-- start a loop — we just return the contract below.
if ATH_COMMON.getenv("ATH_MODE", "menu") == "pit" then
    hooks { init = init, destroy = destroy }
end

-- ===========================================================================
-- Menu contract — { meta, config }. The shell can only drive the shared Duel, so
-- this config is a valid Pit-themed duel fallback (same cast; Spike Traps become
-- the erupting floor hazard). The real game is the standalone loop above.
-- ===========================================================================

-- Duel signature mechanic — ERUPTING SPIKES. Traps tear open across the floor,
-- telegraph, then erupt; the hero is gored if caught standing on one.
local SPIKE_FIRST, SPIKE_INTERVAL, SPIKE_INTERVAL_MIN = 4.0, 5.0, 2.2
local SPIKE_TELEGRAPH, SPIKE_ACTIVE, SPIKE_RADIUS, SPIKE_DMG, SPIKE_MAX = 1.3, 0.4, 2.2, 26.0, 5

local function pit_spike_tile(D)
    local A = D.arena
    for _ = 1, 20 do
        local x = math.random(A.pad + 2, A.w - A.pad - 2)
        local y = math.random(A.pad + 2, A.h - A.pad - 2)
        if D.map:is_walkable(x, y) then return x, y end
    end
    return math.floor(A.w * 0.5), math.floor(A.h * 0.5)
end

local function pit_clear_spikes(D)
    for _, s in ipairs(D.pit and D.pit.spikes or {}) do
        if Art.valid(s.node) then scene.delete_node(s.node) end
    end
    if D.pit then D.pit.spikes = {} end
end

local function pit_update_spikes(D, dt)
    local p = D.pit
    if not p then return end
    p.next = p.next - dt
    if p.next <= 0.0 and #p.spikes < SPIKE_MAX then
        p.next = math.max(SPIKE_INTERVAL_MIN, SPIKE_INTERVAL - 0.4 * (D.round - 1))
        local x, y = pit_spike_tile(D)
        local disc = Art.cylinder("Pit_Spike_" .. p.counter, vec3(x, 0.05, y), vec3(SPIKE_RADIUS, 0.05, SPIKE_RADIUS),
            C.fire, D.groups.world, 1.4, "Textures/modes/pit/spike_trap_armed.png")
        p.counter = p.counter + 1
        p.spikes[#p.spikes + 1] = { x = x, z = y, t = 0.0, phase = "warn", node = disc }
    end
    local keep = {}
    for _, s in ipairs(p.spikes) do
        s.t = s.t + dt
        local alive = true
        if s.phase == "warn" then
            local pulse = 1.2 + 0.6 * math.sin(D.realtime * 16.0)
            if Art.valid(s.node) then material.set(s.node, "emissive", vec3(C.fire[1] * pulse, C.fire[2] * pulse, C.fire[3] * pulse)) end
            if s.t >= SPIKE_TELEGRAPH then
                s.phase = "erupt"; s.t = 0.0
                if Art.valid(s.node) then
                    s.node:set_scale(vec3(SPIKE_RADIUS, 1.0, SPIKE_RADIUS))
                    Art.texture(s.node, "Textures/modes/pit/spike_trap_fire.png")
                end
                local dx, dz = D.hero.x - s.x, D.hero.z - s.z
                if not D.hero.dead and dx * dx + dz * dz <= SPIKE_RADIUS * SPIKE_RADIUS then
                    D:apply_hero_damage(SPIKE_DMG, { flash = "GORED!" })
                end
            end
        elseif s.phase == "erupt" then
            if s.t >= SPIKE_ACTIVE then if Art.valid(s.node) then scene.delete_node(s.node) end alive = false end
        end
        if alive then keep[#keep + 1] = s end
    end
    p.spikes = keep
end

return {
    meta = {
        id = "pit",
        name = "The Pit",
        tagline = "build the gauntlet, then run it",
        blurb = "A 2D top-down stone pit. Place your horde, then take the hero in and survive to the exit. (Standalone: ATH_MODE=pit. From the menu it runs the duel fallback.)",
        side_hint = "horde",
        accent = { 1.0, 0.40, 0.0, 0.95 },
        minimap = {
            bg = { 0.06, 0.06, 0.07, 1.0 },
            rects = {
                { 0.10, 0.10, 0.80, 0.80, { 0.16, 0.16, 0.17, 1.0 } },  -- the ring
                { 0.46, 0.06, 0.08, 0.06, { 1.0, 0.40, 0.0, 1.0 } },    -- exit (north)
                { 0.46, 0.84, 0.08, 0.08, { 0.62, 0.64, 0.68, 1.0 } },  -- hero (south)
                { 0.26, 0.40, 0.05, 0.05, { 0.74, 0.10, 0.10, 1.0 } },  -- placed horde
                { 0.66, 0.34, 0.05, 0.05, { 0.78, 0.76, 0.66, 1.0 } },
                { 0.50, 0.58, 0.05, 0.05, { 1.0, 0.40, 0.0, 1.0 } },    -- a trap
            },
        },
    },

    config = {
        id = "pit",
        name = "The Pit",
        theme = Pit.theme,
        arena = { width = 46, height = 36, pad = 2, ortho_size = 36.0 },
        hero = { hp_max = 100.0, dps = 21.0, cleave = 3, attack_range = 1.25, speed = 2.3, kite_speed = 2.85, actor = Pit.hero_actor },
        archetypes = Pit.archetypes,
        roles = Pit.roles,
        spawn = { interval_start = 0.7, interval_min = 0.3, batch_start = 3, batch_max = 7, cap_start = 28, cap_max = 84, brute_after = 18.0 },
        reserve_start = 300.0,
        round_seconds = 14.0,
        auto_mix = function(D)
            -- Spike Trap is static — keep it out of the roaming mix.
            if D.spawn_counter % 4 == 0 then return "bone_thrower" end
            return "shade_walker"
        end,
        hooks = {
            on_start = function(D) D.pit = { spikes = {}, next = SPIKE_FIRST, counter = 0 } end,
            on_reset = function(D) pit_clear_spikes(D); if D.pit then D.pit.next = SPIKE_FIRST end end,
            on_combat_tick = function(D, dt) pit_update_spikes(D, dt) end,
            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local n = D.pit and #D.pit.spikes or 0
                Art.quad(D.hud, "pit_spikes", 24.0, sh - 150.0, 360.0, 30.0, { 0.07, 0.06, 0.05, 0.85 },
                    { border = { 1.0, 0.40, 0.0, 0.9 }, label = "Erupting spikes: " .. tostring(n) })
            end,
        },
    },
}
