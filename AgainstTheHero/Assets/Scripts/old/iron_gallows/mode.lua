-- IRON GALLOWS — a 2D top-down EXECUTION CHAMBER, grim, in the Dark-Souls key.
--
-- Like THE PIT, IRON GALLOWS is its own little GAME: it does NOT run on the
-- shared 3D Duel engine. It is a self-contained, real-time, top-down arena drawn
-- entirely on the runtime_ui canvas (the same quad/image API the menu uses),
-- driven by its own update loop — mirroring the standalone pattern of modes/pit.
--
-- TWO PHASES:
--   1. DEPLOY — you are the Horde. The chamber is already bolted full of fixed
--      execution DEVICES (guillotines, iron maidens, spike panels, a wall press).
--      You station up to a few OPERATORS (Torturer, Blood Engineer, Inquisitor)
--      who will work those devices, then pick which condemned hero to throw in.
--      Click to place; [Enter] releases the hero.
--   2. RUN — you then DRIVE that hero (WASD / arrows) and try to thread the
--      gauntlet to the far door alive. The operators ARM devices remotely: each
--      device glows ALERT-RED for 1.5s (the telegraph) before its kill-zone
--      triggers. Only a few devices can be armed at once (the EXECUTION QUEUE),
--      so there is always a seam — find it and run. [Space] swing, [Shift] dash.
--
-- SIGNATURE MECHANIC — THE EXECUTION QUEUE. The Horde can only line up
-- `queue_cap` killings at a time. Operators pick idle devices near the hero and
-- arm them (the Torturer arms TWO at once; the Blood Engineer rearms spent
-- devices 3x faster nearby; the Inquisitor also chases you for a melee kill).
-- Every device telegraphs red for 1.5s, then its zone is lethal for a beat.
--
-- All art is from tools/gen_textures_gallows.py and OPTIONAL — a missing PNG
-- just falls back to a flat silhouette colour, so the game still runs.
--
-- This file ALSO returns { meta, config } at the bottom so the mode is discover-
-- able from the battlefield menu; that path can only run the shared Duel, so it
-- falls back to a valid Gallows-themed duel (same cast; the execution devices
-- become the erupting floor hazard).

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Gallows = ATH_COMMON.load_script("Scripts/modes/iron_gallows/characters.lua", "iron_gallows characters", _ENV)

local DATA = Gallows.gallows2d
local C = DATA.palette

-- ===========================================================================
-- The 2D game
-- ===========================================================================

local SCREEN = "ath.iron_gallows"
local UPDATE_ID = "against_the_hero_iron_gallows"

-- The fixed device layout (deterministic): a gauntlet between the south spawn
-- and the north door. { device-id, x, y } in world units. Guillotines form
-- vertical lanes to thread; iron maidens flank; spike panels open the approach;
-- a single wall press sweeps the room just shy of the door.
local LAYOUT = {
    { "spike_panel", -6.0, 4.2 }, { "spike_panel", 0.0, 4.6 }, { "spike_panel", 6.0, 4.2 },
    { "guillotine", -8.4, 0.4 }, { "guillotine", -4.2, 0.4 }, { "guillotine", 0.0, 0.4 },
    { "guillotine", 4.2, 0.4 }, { "guillotine", 8.4, 0.4 },
    { "iron_maiden", -5.4, -2.8 }, { "iron_maiden", 5.4, -2.8 },
    { "wall_press", 0.0, -5.0 },
}

local Game = {
    phase = "deploy",         -- "deploy" | "run" | "won" | "lost"
    key_down = {},
    devices = {},             -- the fixed execution machines
    operators = {},           -- the Horde villains working them
    bloods = {},              -- blood-splat decals (world-anchored, fading)
    placed = {},              -- entries during deploy: { id, x, y }
    chains = {},              -- ceiling-chain decor positions: { x, y, seed }
    floor = {},
    sel_op = "inquisitor",
    sel_hero = "condemned_knight",
    budget = 0,
    queue_active = 0,         -- devices currently telegraphing or triggering
    time = 0.0,
    flash = "", flash_t = 0.0, last_flash = nil,
    cam = { ox = 0.0, oy = 0.0, ppu = 30.0 },
    _live = {}, _prev = {},
    next_id = 0,
}

-- ---- small helpers ---------------------------------------------------------

local function log(msg) if pe_log then pe_log("[ATH:GALLOWS] " .. tostring(msg)) end end

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

-- ---- world <-> screen (rectangular chamber, whole room in frame) -----------

local function recompute_cam()
    local sw, sh = Art.surface_size()
    local A = DATA.arena
    local availw = math.max(40.0, sw - 90.0)
    local availh = math.max(40.0, sh - 230.0)
    Game.cam.ppu = math.max(8.0, math.min(availw / (2.0 * A.half_w), availh / (2.0 * A.half_h)))
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
    local zoff = (opts.z or 0.0) * ppu
    local cs = px * 0.5
    if (opts.core_alpha or 0.85) > 0.0 then
        draw(id .. "_core", sx - cs * 0.5, sy - zoff - cs * 0.5, cs, cs,
            { color[1], color[2], color[3], opts.core_alpha or 0.85 }, { no_input = true })
    end
    draw(id, sx - px * 0.5, sy - zoff - px * 0.55, px, px, { 0, 0, 0, 0 },
        { image = image, no_input = true, image_tint = opts.tint })
end

-- A world-space rectangle (kill-zone overlays, device footprints).
local function draw_world_rect(id, wx, wy, ww, wh, fill, opts)
    local ppu = Game.cam.ppu
    local sx, sy = w2s(wx, wy)
    local pw, ph = ww * ppu, wh * ppu
    draw(id, sx - pw * 0.5, sy - ph * 0.5, pw, ph, fill, opts)
end

-- ---- arena geometry --------------------------------------------------------

local function inside_chamber(wx, wy, margin)
    local A = DATA.arena
    local m = margin or 0.0
    return wx >= -A.half_w + m and wx <= A.half_w - m
        and wy >= -A.half_h + m and wy <= A.half_h - m
end

local function clamp_to_chamber(wx, wy, radius)
    local A = DATA.arena
    local r = radius or 0.0
    return clampn(wx, -A.half_w + r, A.half_w - r), clampn(wy, -A.half_h + r, A.half_h - r)
end

local function point_in_zone(wx, wy, d)
    local dx, dy = wx - d.x, wy - d.y
    return math.abs(dx) <= d.zw * 0.5 and math.abs(dy) <= d.zh * 0.5
end

local function build_floor_tiles()
    Game.floor = {}
    local A = DATA.arena
    local step = A.tile
    local i = 0
    local y = -A.half_h
    while y <= A.half_h do
        local x = -A.half_w
        while x <= A.half_w do
            i = i + 1
            Game.floor[i] = { x = x, y = y, edge = (math.abs(x) > A.half_w - step) or (math.abs(y) > A.half_h - step) }
            x = x + step
        end
        y = y + step
    end
end

local function build_chains()
    Game.chains = {}
    local A = DATA.arena
    local n = A.chain_count
    for i = 1, n do
        local fx = (i - 0.5) / n
        Game.chains[i] = {
            x = -A.half_w + fx * (2.0 * A.half_w),
            y = -A.half_h + 1.4 + ((i % 3) - 1) * 2.2,
            seed = i * 1.7,
        }
    end
end

local function build_devices()
    Game.devices = {}
    local A = DATA.arena
    for _, entry in ipairs(LAYOUT) do
        local def = DATA.devices[entry[1]]
        if def then
            local zw = def.zone.w
            local zh = def.zone.h
            if def.full_width then zw = 2.0 * A.half_w end
            Game.next_id = Game.next_id + 1
            Game.devices[#Game.devices + 1] = {
                id = "dev_" .. Game.next_id, def = def, x = entry[2], y = entry[3],
                zw = zw, zh = zh,
                phase = "idle", t = 0.0, hit_done = false, seed = math.random() * 6.28,
            }
        end
    end
end

-- ---- blood decals ----------------------------------------------------------

local function add_blood(wx, wy, big)
    Game.next_id = Game.next_id + 1
    Game.bloods[#Game.bloods + 1] = {
        id = "blood_" .. Game.next_id, x = wx, y = wy,
        size = (big and 2.6 or 1.4) + math.random() * 0.4, life = 6.0,
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
        dir = 3,                          -- facing north (toward the door)
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
    h.hit_flash = 0.20
    add_blood(h.x, h.y, false)
    if h.hp <= 0.0 then
        h.hp = 0.0; h.dead = true
        Game.phase = "lost"
        set_flash("YOU DIED")
        add_blood(h.x, h.y, true)
        log("hero executed by " .. tostring(what or "the chamber"))
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

    -- Dash (Escaped Prisoner only): a brief speed burst on [Shift].
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
        h.x, h.y = clamp_to_chamber(h.x, h.y, h.def.radius)
        -- 4-way facing from heading (0=E,1=S,2=W,3=N) — matches the sprite set.
        local ang = math.atan(iy, ix)
        h.dir = math.floor(ang / (math.pi / 2.0) + 0.5) % 4
        if h.dir < 0 then h.dir = h.dir + 4 end
        h.phase = h.phase + dt * h.def.walk_freq
    end

    -- Attack: [Space] / [J] sweep — damage every operator within reach.
    if (key_pressed("Space") or key_pressed("J")) and h.attack_cd <= 0.0 then
        h.attack_cd = h.def.attack_cd
        h.attack_flash = 0.14
        local r = h.def.attack_range + h.def.radius
        local r2 = r * r
        for _, o in ipairs(Game.operators) do
            if o.alive then
                local dx, dz = o.x - h.x, o.y - h.y
                if dx * dx + dz * dz <= r2 then
                    o.hp = o.hp - h.def.attack_damage
                    o.hit_flash = 0.18
                    add_blood(o.x, o.y, false)
                    if o.hp <= 0.0 then o.alive = false; add_blood(o.x, o.y, true) end
                end
            end
        end
    end

    -- Reached the far door?
    local dr = DATA.arena.door
    if len2(h.x - dr.x, h.y - dr.y) <= DATA.arena.door_radius + h.def.radius then
        Game.phase = "won"
        set_flash("YOU REACHED THE DOOR")
        log("hero escaped the gallows")
    end
end

-- ---------------------------------------------------------------------------
-- Devices — the 4-state execution machines + the EXECUTION QUEUE
-- ---------------------------------------------------------------------------

-- Count how many devices are currently armed (telegraph) or killing (trigger).
local function recount_queue()
    local n = 0
    for _, d in ipairs(Game.devices) do
        if d.phase == "telegraph" or d.phase == "trigger" then n = n + 1 end
    end
    Game.queue_active = n
    return n
end

-- Idle devices, nearest the hero first — the menacing ones to arm.
local function idle_devices_near(hero, limit)
    local pool = {}
    for _, d in ipairs(Game.devices) do
        if d.phase == "idle" then
            local dx, dy = d.x - hero.x, d.y - hero.y
            pool[#pool + 1] = { d = d, dist = dx * dx + dy * dy }
        end
    end
    table.sort(pool, function(a, b) return a.dist < b.dist end)
    local out = {}
    for i = 1, math.min(limit, #pool) do out[#out + 1] = pool[i].d end
    return out
end

local function arm_device(d)
    if d.phase ~= "idle" then return false end
    d.phase = "telegraph"; d.t = 0.0; d.hit_done = false
    return true
end

-- An operator requests `count` killings; honoured only while the queue has room.
local function request_executions(count)
    local h = Game.hero
    if not h or h.dead then return 0 end
    local room = DATA.queue_cap - recount_queue()
    if room <= 0 then return 0 end
    local want = math.min(count, room)
    local picks = idle_devices_near(h, want)
    local armed = 0
    for _, d in ipairs(picks) do
        if arm_device(d) then armed = armed + 1 end
    end
    if armed > 0 then Game.queue_active = Game.queue_active + armed end
    return armed
end

-- Blood Engineers rearm spent devices faster — the highest bonus in range wins.
local function reset_mult_for(d)
    local mult = 1.0
    for _, o in ipairs(Game.operators) do
        if o.alive and o.def.repair_mult then
            local dx, dy = o.x - d.x, o.y - d.y
            if dx * dx + dy * dy <= o.def.repair_radius * o.def.repair_radius then
                if o.def.repair_mult > mult then mult = o.def.repair_mult end
            end
        end
    end
    return mult
end

local function update_devices(dt)
    local h = Game.hero
    for _, d in ipairs(Game.devices) do
        local def = d.def
        if d.phase == "telegraph" then
            d.t = d.t + dt
            if d.t >= def.telegraph then d.phase = "trigger"; d.t = 0.0; d.hit_done = false end
        elseif d.phase == "trigger" then
            d.t = d.t + dt
            -- Lethal for the whole trigger window; one bite per cycle.
            if not d.hit_done and h and not h.dead and point_in_zone(h.x, h.y, d) then
                hero_take_damage(def.damage, "the " .. def.name)
                d.hit_done = true
            end
            if d.t >= def.trigger then d.phase = "reset"; d.t = 0.0 end
        elseif d.phase == "reset" then
            d.t = d.t + dt * reset_mult_for(d)
            if d.t >= def.reset then d.phase = "idle"; d.t = 0.0 end
        end
    end
    recount_queue()
end

-- ---------------------------------------------------------------------------
-- Operators — the Horde villains working the chamber
-- ---------------------------------------------------------------------------

local function spawn_operator(id, x, y)
    local def = DATA.operators[id]
    Game.next_id = Game.next_id + 1
    return {
        id = "op_" .. Game.next_id, op_id = id, def = def,
        x = x, y = y, hp = def.hp, alive = true,
        seed = math.random() * 6.28, hit_flash = 0.0,
        act_cd = def.activate_cd * (0.4 + math.random() * 0.6),  -- stagger first pulls
        touch_cd = 0.0, moving = false,
    }
end

-- Boid separation so operators don't stack on one lever.
local function separation(e)
    local sx, sz = 0.0, 0.0
    local rad = e.def.sep_radius or 1.6
    local r2 = rad * rad
    for _, o in ipairs(Game.operators) do
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

local function update_operator(e, dt, h)
    local def = e.def
    local dx, dz = h.x - e.x, h.y - e.y
    local d = len2(dx, dz)
    local ux, uz = 0.0, 0.0
    if d > 0.0001 then ux, uz = dx / d, dz / d end

    -- Movement: the Inquisitor runs the hero down; the others keep their lever
    -- distance — close in if too far, back off if the hero gets in their face.
    local dir = 0.0
    if def.touch_damage then
        dir = 1.0                                       -- elite: always chase
    else
        local keep = def.keep_range or 6.0
        if d > keep + 0.6 then dir = 1.0
        elseif d < keep - 0.6 then dir = -1.0 end
    end
    if dir ~= 0.0 then
        local px, pz = separation(e)
        local vx = ux * dir + px * (def.sep_weight or 1.2)
        local vz = uz * dir + pz * (def.sep_weight or 1.2)
        local vm = len2(vx, vz)
        if vm > 0.0001 then
            e.x = e.x + (vx / vm) * def.speed * dt
            e.y = e.y + (vz / vm) * def.speed * dt
            e.x, e.y = clamp_to_chamber(e.x, e.y, def.radius)
        end
        e.moving = true
    else
        e.moving = false
    end

    -- Inquisitor contact strike.
    if def.touch_damage then
        e.touch_cd = math.max(0.0, e.touch_cd - dt)
        if d <= def.radius + h.def.radius + 0.2 and e.touch_cd <= 0.0 then
            e.touch_cd = def.touch_cd
            hero_take_damage(def.touch_damage, "the Inquisitor")
        end
    end

    -- Arm devices on the operator's own cadence (queue-gated).
    e.act_cd = math.max(0.0, e.act_cd - dt)
    if e.act_cd <= 0.0 then
        e.act_cd = def.activate_cd
        local armed = request_executions(def.activate_count or 1)
        if armed > 0 and def.activate_count and def.activate_count >= 2 then
            set_flash("THE TORTURER WORKS THE LEVERS")
        end
    end
end

local function update_operators(dt)
    local h = Game.hero
    local survivors = {}
    for _, e in ipairs(Game.operators) do
        e.hit_flash = math.max(0.0, e.hit_flash - dt)
        if e.alive then update_operator(e, dt, h) end
        if e.alive then survivors[#survivors + 1] = e
        else Game._live[e.id] = nil; Game._live[e.id .. "_core"] = nil end
    end
    Game.operators = survivors
end

-- ---------------------------------------------------------------------------
-- Deploy phase
-- ---------------------------------------------------------------------------

local function can_place(wx, wy)
    if not inside_chamber(wx, wy, 1.0) then return false end
    local sp = DATA.arena.hero_spawn
    if len2(wx - sp.x, wy - sp.y) < 2.4 then return false end
    if len2(wx - DATA.arena.door.x, wy - DATA.arena.door.y) < 2.6 then return false end
    -- Not standing inside a device footprint.
    for _, d in ipairs(Game.devices) do
        if math.abs(wx - d.x) <= d.def.size * 0.5 and math.abs(wy - d.y) <= d.def.size * 0.5 then return false end
    end
    for _, pe in ipairs(Game.placed) do
        if len2(wx - pe.x, wy - pe.y) < 1.4 then return false end
    end
    return true
end

local function release_hero()
    Game.operators = {}
    for _, pe in ipairs(Game.placed) do
        Game.operators[#Game.operators + 1] = spawn_operator(pe.id, pe.x, pe.y)
    end
    for _, d in ipairs(Game.devices) do d.phase = "idle"; d.t = 0.0; d.hit_done = false end
    spawn_hero()
    Game.bloods = {}
    Game.queue_active = 0
    Game.time = 0.0
    Game.phase = "run"
    set_flash("RUN THE GAUNTLET")
    log("released " .. tostring(Game.sel_hero) .. " vs " .. tostring(#Game.operators) .. " operators")
end

local function reset_game()
    Game.placed = {}
    Game.operators = {}
    Game.bloods = {}
    Game.budget = DATA.deploy.budget
    Game.phase = "deploy"
    Game.hero = nil
    Game.queue_active = 0
    Game.time = 0.0
    for _, d in ipairs(Game.devices) do d.phase = "idle"; d.t = 0.0; d.hit_done = false end
    set_flash("STAFF THE GALLOWS  -  deploy up to " .. tostring(Game.budget))
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local function draw_world_floor(sw, sh)
    draw("bg", 0, 0, sw, sh, { 0.02, 0.02, 0.025, 1.0 }, { no_input = true })
    local ppu = Game.cam.ppu
    local tile = DATA.arena.tile * ppu
    for i, t in ipairs(Game.floor) do
        local sx, sy = w2s(t.x, t.y)
        local shade = t.edge and 0.45 or 1.0
        draw("fl_" .. i, sx - tile * 0.5, sy - tile * 0.5, tile + 1.0, tile + 1.0,
            { C.iron[1] * shade, C.iron[2] * shade, C.iron[3] * shade, 1.0 },
            { image = t.edge and DATA.sprites.wall or DATA.sprites.floor, no_input = true })
    end
end

local function draw_door()
    local dr = DATA.arena.door
    local pulse = 0.55 + 0.45 * math.sin(Game.time * 3.0)
    draw_sprite("door", dr.x, dr.y, 3.6, DATA.sprites.door, { C.alert[1], C.alert[2], C.alert[3] },
        { core_alpha = 0.0 })
    local sx, sy = w2s(dr.x, dr.y)
    draw("door_lbl", sx - 70, sy - Game.cam.ppu * 1.8, 140, 24, { 0, 0, 0, 0 },
        { label = "DOOR", text_color = { C.alert[1], C.alert[2], C.alert[3], pulse }, no_input = true })
end

local function device_image(d)
    return d.def.sprites[d.phase] or d.def.sprites.idle
end

-- Devices and their kill-zones (drawn at floor level, under the actors).
local function draw_devices()
    for _, d in ipairs(Game.devices) do
        local def = d.def
        -- Kill-zone overlay: the whole point of the telegraph is readability.
        if d.phase == "telegraph" then
            local p = clampn(d.t / def.telegraph, 0.0, 1.0)
            local a = 0.18 + 0.30 * p * (0.6 + 0.4 * math.sin(Game.time * 18.0))
            draw_world_rect(d.id .. "_z", d.x, d.y, d.zw, d.zh,
                { C.alert[1], C.alert[2], C.alert[3], a },
                { border = { C.alert[1], C.alert[2], C.alert[3], 0.85 }, no_input = true })
        elseif d.phase == "trigger" then
            draw_world_rect(d.id .. "_z", d.x, d.y, d.zw, d.zh,
                { 1.0, 0.92, 0.82, 0.9 },
                { border = { C.alert[1], C.alert[2], C.alert[3], 1.0 }, no_input = true })
        else
            Game._live[d.id .. "_z"] = nil
        end
        -- The device prop itself.
        local tint = nil
        if d.phase == "telegraph" then
            tint = { C.alert[1], C.alert[2], C.alert[3], 0.4 + 0.4 * math.sin(Game.time * 18.0) }
        end
        draw_sprite(d.id, d.x, d.y, def.size, device_image(d), def.color, { tint = tint, core_alpha = 0.35 })
    end
end

-- Depth-sorted actors (operators + hero); lower screen-y draws first.
local function draw_actors()
    local list = {}
    for _, e in ipairs(Game.operators) do list[#list + 1] = { y = e.y, op = e } end
    if Game.hero then list[#list + 1] = { y = Game.hero.y, hero = Game.hero } end
    table.sort(list, function(a, b) return a.y < b.y end)

    for _, item in ipairs(list) do
        if item.op then
            local e = item.op
            local def = e.def
            local sway = (def.sway_amp or 0.0) * math.sin(Game.time * (def.sway_freq or 3.0) + e.seed)
            local col = def.color
            if e.hit_flash > 0.0 then col = { 1.0, 0.5, 0.4 } end
            -- The Torturer animates on a 5-frame loop; the others are a still sprite.
            local img
            if def.sprite_frames then
                local n = #def.sprite_frames
                local f = (math.floor(Game.time * (def.anim_fps or 6.0) + e.seed) % n) + 1
                img = def.sprite_frames[f]
            else
                img = def.sprite
            end
            draw_sprite(e.id, e.x, e.y + sway, def.size, img, col, {})
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

-- Ceiling chains, drawn ON TOP so they read as hanging overhead.
local function draw_chains()
    for i, ch in ipairs(Game.chains) do
        local sway = 0.12 * math.sin(Game.time * 1.4 + ch.seed)
        draw_sprite("chain_" .. i, ch.x + sway, ch.y, 2.2, DATA.sprites.chain, C.rust,
            { core_alpha = 0.0, tint = { 1.0, 1.0, 1.0, 0.55 } })
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

local function draw_deploy_ghost()
    local mx, my = mouse_pos()
    if not mx then return end
    local wx, wy = s2w(mx, my)
    local ok = can_place(wx, wy) and Game.budget > 0
    local def = DATA.operators[Game.sel_op]
    local img = def.sprite_frames and def.sprite_frames[1] or def.sprite
    local sx, sy = w2s(wx, wy)
    local px = def.size * Game.cam.ppu
    draw("ghost", sx - px * 0.5, sy - px * 0.5, px, px,
        { ok and 0.3 or 0.8, ok and 0.8 or 0.2, 0.3, 0.30 },
        { image = img, border = ok and { 0.3, 0.9, 0.4, 0.9 } or { 0.9, 0.3, 0.2, 0.9 }, no_input = true })
end

-- ---- HUD -------------------------------------------------------------------

local function button(id, x, y, w, h, label, opts)
    opts = opts or {}
    local st = Art.widget_state(SCREEN, id)
    local hov = st and st.hovered
    Game._live[id] = true
    Art.quad(SCREEN, id, x, y, w, h, opts.fill or (hov and { 0.16, 0.06, 0.05, 0.96 } or { 0.09, 0.08, 0.08, 0.94 }),
        { border = opts.border or { 0.5, 0.2, 0.1, 0.95 }, label = label, subtitle = opts.subtitle,
          text_color = opts.text_color, selected = opts.selected, font_scale = opts.font_scale })
    return Art.consume_click(SCREEN, id)
end

local function draw_hud(sw, sh)
    draw("title", 20, 16, 420, 40, { 0, 0, 0, 0 },
        { title = "IRON GALLOWS", text_color = { C.alert[1], C.alert[2], C.alert[3], 1.0 }, font_scale = 1.3, no_input = true })

    if Game.phase == "deploy" then
        -- Operator palette (1/2/3 + click).
        local px, py, pw, ph = 20.0, sh - 132.0, 250.0, 56.0
        for i, id in ipairs(DATA.operator_order) do
            local def = DATA.operators[id]
            local bx = px + (i - 1) * (pw + 10.0)
            if button("pal_" .. id, bx, py, pw, ph, "[" .. i .. "] " .. def.name,
                { subtitle = def.blurb, selected = (Game.sel_op == id),
                  border = (Game.sel_op == id) and { 1.0, 0.20, 0.0, 1.0 } or { 0.5, 0.2, 0.1, 0.9 } })
                or key_pressed(tostring(i)) then
                Game.sel_op = id
            end
        end
        -- Hero selector (click).
        local hx = px + 3 * (pw + 10.0) + 10.0
        for i, id in ipairs(DATA.hero_order) do
            local def = DATA.heroes[id]
            if button("hero_" .. id, hx, py + (i - 1) * 28.0, 250.0, 24.0, def.name,
                { selected = (Game.sel_hero == id), font_scale = 0.85,
                  border = (Game.sel_hero == id) and { 0.4, 0.7, 1.0, 1.0 } or { 0.3, 0.3, 0.4, 0.9 } }) then
                Game.sel_hero = id
            end
        end
        draw("budget", px, py - 36.0, 560.0, 28.0, { 0, 0, 0, 0 },
            { label = "Operators left: " .. tostring(Game.budget) .. "      Click to deploy  -  [Enter] release the hero  -  [Z] undo",
              text_color = { 0.85, 0.80, 0.76, 1.0 }, no_input = true })
        if button("release", sw - 280.0, sh - 132.0, 260.0, 56.0, "RELEASE THE HERO  [Enter]",
            { border = { 0.4, 0.9, 0.5, 1.0 }, fill = { 0.10, 0.16, 0.10, 0.96 } }) then
            release_hero()
        end
        draw_deploy_ghost()

    elseif Game.phase == "run" then
        local h = Game.hero
        local pct = h and (h.hp / h.hp_max) or 0.0
        local col = pct > 0.5 and { 0.55, 0.12, 0.10, 0.95 } or { 0.85, 0.18, 0.12, 0.95 }
        Art.bar(SCREEN, "hp", sw * 0.5 - 240.0, 24.0, 480.0, 30.0, pct, col,
            { label = (h and h.def.name or "HERO") .. string.format("   %d / %d", math.floor((h and h.hp or 0) + 0.5), math.floor((h and h.hp_max or 1) + 0.5)),
              border = { 1.0, 0.20, 0.0, 0.9 } })
        Game._live["hp_bg"] = true; Game._live["hp_fg"] = true; Game._live["hp_label"] = true
        draw("ctrls", 20, sh - 50.0, 760.0, 26.0, { 0, 0, 0, 0 },
            { label = "WASD / arrows move   -   [Space] swing" .. (h and h.def.dash and "   -   [Shift] dash" or "") .. "   -   [R] rebuild",
              text_color = { 0.8, 0.78, 0.74, 1.0 }, no_input = true })
        -- The execution-queue readout (the signature mechanic, surfaced).
        draw("queue", sw - 300.0, 24.0, 280.0, 26.0, { 0, 0, 0, 0 },
            { label = "Executions armed: " .. tostring(Game.queue_active) .. " / " .. tostring(DATA.queue_cap)
                .. "      Operators: " .. tostring(#Game.operators),
              text_color = { C.alert[1], C.alert[2], C.alert[3], 1.0 }, no_input = true })
    end

    if Game.phase == "won" or Game.phase == "lost" then
        local won = Game.phase == "won"
        draw("end", sw * 0.5 - 300.0, sh * 0.40, 600.0, 120.0,
            won and { 0.08, 0.14, 0.08, 0.94 } or { 0.16, 0.04, 0.04, 0.94 },
            { border = won and { 0.4, 0.9, 0.5, 0.95 } or { 0.9, 0.2, 0.18, 0.95 },
              title = won and "YOU REACHED THE DOOR" or "YOU DIED",
              body = "Press [R] to staff the gallows again", no_input = true })
    end

    if Game.flash ~= "" and Game.flash_t > 0.0 then
        draw("flash", sw * 0.5 - 280.0, 64.0, 560.0, 30.0, { 0, 0, 0, 0 },
            { label = Game.flash, text_color = { 1.0, 0.30, 0.10, math.min(1.0, Game.flash_t) }, no_input = true })
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

    if Game.phase == "deploy" then
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
                    Game.placed[#Game.placed + 1] = { id = Game.sel_op, x = wx, y = wy }
                    Game.budget = Game.budget - 1
                end
            end
        end
    elseif Game.phase == "run" then
        update_hero(dt)
        update_operators(dt)
        update_devices(dt)
    end

    Game.flash_t = math.max(0.0, Game.flash_t - dt)
    if Game.flash ~= Game.last_flash then Game.flash_t = 2.2; Game.last_flash = Game.flash end
    if Game.flash_t <= 0.0 then Game.flash = "" end

    -- ---- render ----
    local sw, sh = recompute_cam()
    draw("world_input", 0, 0, sw, sh, { 0, 0, 0, 0 })
    draw_world_floor(sw, sh)
    draw_bloods(dt)
    draw_devices()
    draw_door()
    if Game.phase == "deploy" then
        for i, pe in ipairs(Game.placed) do
            local def = DATA.operators[pe.id]
            local img = def.sprite_frames and def.sprite_frames[1] or def.sprite
            draw_sprite("placed_" .. i, pe.x, pe.y, def.size, img, def.color, {})
        end
    end
    draw_actors()
    draw_chains()
    draw_hud(sw, sh)

    sweep_stale()
end

-- ---------------------------------------------------------------------------
-- Lifecycle (standalone, ATH_MODE=iron_gallows)
-- ---------------------------------------------------------------------------

local function init()
    if runtime_ui then
        if runtime_ui.set_title then runtime_ui.set_title(SCREEN, "Iron Gallows") end
        if runtime_ui.set_screen_overlay then runtime_ui.set_screen_overlay(SCREEN, true) end
        if runtime_ui.show then runtime_ui.show(SCREEN) end
    end
    local seed = ATH_COMMON.getenv_number and ATH_COMMON.getenv_number("ATH_GALLOWS_SEED", nil) or nil
    if seed then math.randomseed(math.floor(seed)) end
    build_floor_tiles()
    build_chains()
    build_devices()
    reset_game()
    if script and script.on_update then
        script.on_update(UPDATE_ID, update, "play")
    else
        _G.update = update
    end
    log("init chamber " .. tostring(DATA.arena.half_w * 2.0) .. "x" .. tostring(DATA.arena.half_h * 2.0)
        .. " with " .. tostring(#Game.devices) .. " devices")
end

local function destroy()
    if script and script.remove_update then script.remove_update(UPDATE_ID) end
    if runtime_ui and runtime_ui.clear then runtime_ui.clear(SCREEN) end
    log("destroyed")
end

-- Only seize the engine loop when launched as the standalone mode. When the menu
-- shell merely enumerates this file for its { meta } (ATH_MODE=menu), we must NOT
-- start a loop — we just return the contract below.
if ATH_COMMON.getenv("ATH_MODE", "menu") == "iron_gallows" then
    hooks { init = init, destroy = destroy }
end

-- ===========================================================================
-- Menu contract — { meta, config }. The shell can only drive the shared Duel, so
-- this config is a valid Gallows-themed duel fallback (same cast; the execution
-- devices become an erupting floor hazard that telegraphs then gores the hero).
-- The real game is the standalone loop above.
-- ===========================================================================

-- Duel signature mechanic — EXECUTION DEVICES. Floor traps arm across the room,
-- glow alert-red for the telegraph, then trigger; the hero is gored if caught.
local DEV_FIRST, DEV_INTERVAL, DEV_INTERVAL_MIN = 3.5, 4.6, 2.0
local DEV_TELEGRAPH, DEV_ACTIVE, DEV_RADIUS, DEV_DMG, DEV_MAX = 1.5, 0.5, 2.3, 30.0, 3

local function gallows_tile(D)
    local A = D.arena
    for _ = 1, 20 do
        local x = math.random(A.pad + 2, A.w - A.pad - 2)
        local y = math.random(A.pad + 2, A.h - A.pad - 2)
        if D.map:is_walkable(x, y) then return x, y end
    end
    return math.floor(A.w * 0.5), math.floor(A.h * 0.5)
end

local function gallows_clear(D)
    for _, s in ipairs(D.gallows and D.gallows.devs or {}) do
        if Art.valid(s.node) then scene.delete_node(s.node) end
    end
    if D.gallows then D.gallows.devs = {} end
end

local function gallows_update(D, dt)
    local g = D.gallows
    if not g then return end
    g.next = g.next - dt
    if g.next <= 0.0 and #g.devs < DEV_MAX then
        g.next = math.max(DEV_INTERVAL_MIN, DEV_INTERVAL - 0.4 * (D.round - 1))
        local x, y = gallows_tile(D)
        local node = Art.cylinder("Gallows_Dev_" .. g.counter, vec3(x, 0.05, y), vec3(DEV_RADIUS, 0.05, DEV_RADIUS),
            C.alert, D.groups.world, 1.4, "Textures/modes/iron_gallows/spike_panel_telegraph.png")
        g.counter = g.counter + 1
        g.devs[#g.devs + 1] = { x = x, z = y, t = 0.0, phase = "warn", node = node }
    end
    local keep = {}
    for _, s in ipairs(g.devs) do
        s.t = s.t + dt
        local alive = true
        if s.phase == "warn" then
            local pulse = 1.2 + 0.6 * math.sin(D.realtime * 16.0)
            if Art.valid(s.node) then material.set(s.node, "emissive", vec3(C.alert[1] * pulse, C.alert[2] * pulse, C.alert[3] * pulse)) end
            if s.t >= DEV_TELEGRAPH then
                s.phase = "kill"; s.t = 0.0
                if Art.valid(s.node) then
                    s.node:set_scale(vec3(DEV_RADIUS, 1.0, DEV_RADIUS))
                    Art.texture(s.node, "Textures/modes/iron_gallows/spike_panel_trigger.png")
                end
                local dx, dz = D.hero.x - s.x, D.hero.z - s.z
                if not D.hero.dead and dx * dx + dz * dz <= DEV_RADIUS * DEV_RADIUS then
                    D:apply_hero_damage(DEV_DMG, { flash = "EXECUTED!" })
                end
            end
        elseif s.phase == "kill" then
            if s.t >= DEV_ACTIVE then if Art.valid(s.node) then scene.delete_node(s.node) end alive = false end
        end
        if alive then keep[#keep + 1] = s end
    end
    g.devs = keep
end

return {
    meta = {
        id = "iron_gallows",
        name = "Iron Gallows",
        tagline = "thread the execution chamber to the door",
        blurb = "A 2D top-down execution chamber. Guillotines, iron maidens, spike panels and a wall press fill the room; the Horde arms them remotely (they glow red 1.5s before they kill). Thread the gauntlet to the far door. (Standalone: ATH_MODE=iron_gallows. From the menu it runs the duel fallback.)",
        side_hint = "horde",
        accent = { 1.0, 0.20, 0.0, 0.95 },
        minimap = {
            bg = { 0.04, 0.04, 0.045, 1.0 },
            rects = {
                { 0.08, 0.08, 0.84, 0.84, { 0.118, 0.118, 0.118, 1.0 } },  -- the chamber
                { 0.46, 0.06, 0.08, 0.05, { 1.0, 0.20, 0.0, 1.0 } },       -- door (north)
                { 0.46, 0.86, 0.08, 0.07, { 0.60, 0.60, 0.64, 1.0 } },     -- hero (south)
                { 0.22, 0.50, 0.05, 0.10, { 0.235, 0.235, 0.235, 1.0 } },  -- guillotine lanes
                { 0.46, 0.50, 0.05, 0.10, { 0.235, 0.235, 0.235, 1.0 } },
                { 0.70, 0.50, 0.05, 0.10, { 0.235, 0.235, 0.235, 1.0 } },
                { 0.30, 0.30, 0.06, 0.06, { 1.0, 0.20, 0.0, 1.0 } },       -- armed device
                { 0.64, 0.66, 0.06, 0.06, { 0.353, 0.227, 0.0, 1.0 } },    -- iron maiden
            },
        },
    },

    config = {
        id = "iron_gallows",
        name = "Iron Gallows",
        theme = Gallows.theme,
        arena = { width = 48, height = 36, pad = 2, ortho_size = 36.0 },
        hero = { hp_max = 105.0, dps = 21.0, cleave = 3, attack_range = 1.25, speed = 2.3, kite_speed = 2.85, actor = Gallows.hero_actor },
        archetypes = Gallows.archetypes,
        roles = Gallows.roles,
        spawn = { interval_start = 0.7, interval_min = 0.3, batch_start = 3, batch_max = 7, cap_start = 30, cap_max = 88, brute_after = 18.0 },
        reserve_start = 310.0,
        round_seconds = 14.0,
        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 11 == 0) then return "torturer" end
            if D.spawn_counter % 7 == 0 then return "inquisitor" end
            if D.spawn_counter % 4 == 0 then return "blood_engineer" end
            return "gallows_thrall"
        end,
        hooks = {
            on_start = function(D) D.gallows = { devs = {}, next = DEV_FIRST, counter = 0 } end,
            on_reset = function(D) gallows_clear(D); if D.gallows then D.gallows.next = DEV_FIRST end end,
            on_combat_tick = function(D, dt) gallows_update(D, dt) end,
            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local n = D.gallows and #D.gallows.devs or 0
                Art.quad(D.hud, "gallows_devs", 24.0, sh - 150.0, 380.0, 30.0, { 0.07, 0.05, 0.05, 0.85 },
                    { border = { 1.0, 0.20, 0.0, 0.9 }, label = "Devices arming: " .. tostring(n) .. " / " .. tostring(DEV_MAX) })
            end,
        },
    },
}
