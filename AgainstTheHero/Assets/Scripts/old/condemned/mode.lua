-- Condemned — a 2D side-scrolling prison break with a Souls-like gloom.
--
-- THE TWIST ON THE CONTRACT. Like catacombs, CONDEMNED re-stages the shared Duel
-- as a SIDE-SCROLLER: the arena is a long, shallow cell block (the X axis is the
-- corridor, read left->right), the camera drops to a low side-on angle and FOLLOWS
-- THE HERO, and a Y-up gravity layer rides on top for the gravity-arc escape jump
-- and free-falling debris. The hero still auto-fights and the garrison still rushes
-- him — we re-skin the stage as a dark stone gaol and add ONE bespoke system.
--
-- Signature mechanic — LOCKDOWN. The cell block is cut into 3 sections by barred
-- gates. The horde banks ACTION POINTS over time; when the hero nears an open gate
-- the horde SPENDS them to cage the section — iron bars SLAM down and block the
-- path. The hero can't pass until he has fought through the side-passage guards the
-- lockdown summons and reached the LEVER that lifts the bars (modelled as: clear the
-- knot of guards at the gate, the lever throws, the bars rise). Pure pressure that
-- forces the detour the brief asks for, built entirely on the Duel hooks.
--
-- Two more menaces ride on top: PATROL guards that walk the cell fronts, and — on
-- the FINAL block — the WARDEN, a bespoke boss that HUNTS the hero down the corridor
-- and clubs him on contact. And the gaol "breaks" mid-run: when the hero's HP
-- crosses set thresholds an alarm trips — every standing gate slams, reinforcements
-- pour in, and the Warden is enraged. Everything is ath_art primitives, self-lit,
-- and texture-ready; the seamless wall/bar PNGs are wired live (see
-- tools/gen_textures_condemned.py).

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Cond = ATH_COMMON.load_script("Scripts/modes/condemned/characters.lua", "condemned characters", _ENV)

-- ---- Physics + tuning ------------------------------------------------------
local GRAVITY = 9.8          -- units/s^2 — the mode-owned Y-axis pull (brief)
local JUMP_APEX = 1.5        -- peak height of the hero's escape leap, world units

-- LOCKDOWN — the action-point economy that cages sections.
local AP_RATE = 7.0          -- action points banked per second of combat
local AP_MAX = 100.0         -- cap on the horde's stored action points
local LOCKDOWN_COST = 34.0   -- AP the horde spends to slam one gate
local LOCKDOWN_RANGE = 7.0   -- hero must be approaching within this to trip a gate
local LOCKDOWN_DETOUR = 5.5  -- min seconds caged before the lever can throw
local DETOUR_CLEAR = 6.0     -- no live guard within this radius -> lever throws
local DETOUR_GUARDS = 3      -- side-passage guards summoned when a gate slams

-- Bar gate animation (bars hang above the corridor and drop to the floor).
local BAR_TOP = 6.2          -- parked height above the corridor
local BAR_SLAM = 0.35        -- drop time (parked -> floor)
local BAR_RISE = 0.7         -- raise time when the lever throws
local BAR_BLOCK = 0.9        -- how far in front of a gate the bars stop the hero

-- The Warden hunt (final block).
local WARDEN_SPEED = 2.05    -- a touch under the convict's sprint — outrun, don't out-stand
local WARDEN_RAGE_SPEED = 2.7
local WARDEN_HIT = 16.0      -- contact club damage
local WARDEN_REACH = 1.3
local WARDEN_HIT_CD = 1.1

local PARALLAX = 0.7         -- background world-shift per hero unit (faked depth)

-- The escape clock — reach the outer gate before it runs out, or the block puts
-- you down (brief: lose = hero dies OR timer). Counts down only during combat.
local ESCAPE_SECONDS = 95.0

-- ---------------------------------------------------------------------------
-- Stage dressing (built once, in on_start) — cells, torches, layers, exit.
-- ---------------------------------------------------------------------------

-- A flickering wall torch: an iron bracket + an emissive flame core we pulse every
-- tick. torch_sheet.png is the artist drop-in; the live flicker is procedural.
local function build_torch(D, x, y, z)
    local g = D.groups.world
    Art.cube("Torch_Haft_" .. x, vec3(x, y - 0.35, z), vec3(0.08, 0.7, 0.08), Cond.palette.metal, g, 0.4)
    Art.cube("Torch_Bracket_" .. x, vec3(x, y, z), vec3(0.22, 0.1, 0.22), Cond.palette.metal, g, 0.4)
    local flame = Art.sphere("Torch_Flame_" .. x, vec3(x, y + 0.32, z), vec3(0.24, 0.42, 0.24), Cond.palette.torch, g, 1.8)
    -- texture = Cond.tex.torch  -- 4-frame flame sheet drop-in
    return { node = flame, x = x, base_y = y + 0.32, seed = x * 1.7 }
end

-- A barred cell recessed into the back wall — pure dressing. The bar facade uses
-- the seamless semi-transparent bars tile so the dark cell shows through the gaps.
local function build_cell(D, x, z)
    local g = D.groups.world
    Art.cube("Cell_Back_" .. x, vec3(x, 1.3, z + 0.3), vec3(2.0, 2.6, 0.2), Cond.palette.black, g, 0.15)
    Art.cube("Cell_Bars_" .. x, vec3(x, 1.3, z - 0.5), vec3(2.0, 2.6, 0.08), Cond.palette.metal, g, 0.5, Cond.tex.bars)
    -- a hint of something in the cell (a slumped prisoner) for grim flavour
    Art.cube("Cell_Inmate_" .. x, vec3(x + 0.4, 0.5, z + 0.1), vec3(0.4, 0.9, 0.3), Cond.palette.stone, g, 0.25)
end

-- A patrolling Dungeon Guard that walks the cell front and turns at the edges
-- (brief: "guard patrol AI"). Decorative garrison-life — a tiny actor rig so
-- ath_art's walk clip animates its stride; stays grounded (normal force vs gravity).
local function build_patrol(D, x, z, span)
    local spec = {
        name = "Patrol_Guard",
        parts = {
            body = { kind = "cube", position = { 0.0, 0.44, 0.0 }, scale = { 0.26, 0.46, 0.20 }, color = Cond.palette.metal, emissive = 0.6 },
            head = { kind = "cube", position = { 0.0, 0.82, 0.0 }, scale = { 0.22, 0.20, 0.22 }, color = Cond.palette.stone, emissive = 0.55 },
            foot_r = { kind = "cube", position = { 0.08, 0.04, 0.0 }, scale = { 0.12, 0.08, 0.16 }, color = Cond.palette.black, emissive = 0.4 },
            foot_l = { kind = "cube", position = { -0.08, 0.04, 0.0 }, scale = { 0.12, 0.08, 0.16 }, color = Cond.palette.black, emissive = 0.4 },
            sword = { kind = "cube", position = { 0.24, 0.42, 0.06 }, scale = { 0.05, 0.40, 0.05 }, color = Cond.palette.rust, emissive = 0.6 },
            eye = { kind = "sphere", position = { 0.0, 0.82, 0.13 }, scale = { 0.07, 0.05, 0.04 }, color = Cond.palette.blood, emissive = 1.6 },
        },
    }
    local actor = Art.build_actor(spec, D.groups.world)
    local cs = Art.s("char") * 0.95
    if Art.valid(actor.root) then actor.root:set_scale(vec3(cs, cs, cs)) end
    return {
        actor = actor, y = 0.0, z = z, x = x,
        min = x - span, max = x + span, dir = 1.0,
        speed = 1.3 + 0.35 * (math.floor(x) % 3), phase = x,
    }
end

local function update_patrols(D, dt)
    for _, p in ipairs(D.cond.patrols) do
        p.x = p.x + p.dir * p.speed * dt
        if p.x <= p.min then p.x = p.min; p.dir = 1.0 end      -- turn at the edge
        if p.x >= p.max then p.x = p.max; p.dir = -1.0 end
        p.phase = p.phase + dt * 8.0
        if Art.valid(p.actor.root) then
            p.actor.root:set_position(vec3(p.x, p.y, p.z))      -- gravity-grounded
            p.actor.root:set_rotation(vec3(0.0, p.dir > 0 and 90.0 or -90.0, 0.0))
        end
        Art.animate(p.actor, "walk", p.phase / 8.0)
    end
end

-- ---- LOCKDOWN: the barred gates (the signature mechanic) --------------------

-- A gate = a rack of vertical iron bars parked above the corridor + a lever that
-- lifts them. The bars span the corridor's depth so the side-on view reads as a
-- floor-to-ceiling cage when slammed.
local function build_gate(D, x)
    local g = D.groups.world
    local A = D.arena
    local zc = A.h * 0.5
    local bars = {}
    for i = -2, 2 do
        local bz = zc + i * 0.7
        local b = Art.cube("Gate_Bar_" .. math.floor(x) .. "_" .. (i + 2),
            vec3(x, BAR_TOP, bz), vec3(0.16, 3.0, 0.16), Cond.palette.metal, g, 0.7, Cond.tex.bars)
        bars[#bars + 1] = { node = b, x = x, z = bz }   -- keep coords; never read them back
    end
    -- A header beam the bars hang from, so the parked rack reads as a portcullis.
    Art.cube("Gate_Header_" .. math.floor(x), vec3(x, 3.1, zc), vec3(0.5, 0.5, A.h - A.pad * 2.0), Cond.palette.stone, g, 0.5)
    -- The LEVER, set just before the gate in the near "side passage" (lower z).
    local lz = A.pad + 1.2
    Art.cube("Lever_Base_" .. math.floor(x), vec3(x - 1.4, 0.4, lz), vec3(0.3, 0.8, 0.3), Cond.palette.stone, g, 0.5)
    local handle = Art.cube("Lever_Arm_" .. math.floor(x), vec3(x - 1.4, 0.9, lz), vec3(0.12, 0.6, 0.12), Cond.palette.rust, g, 1.2, Cond.tex.lever)
    return {
        x = x, bars = bars, handle = handle, lz = lz,
        state = "open",        -- open | down | rising
        bar_y = BAR_TOP, t = 0.0, detour_t = 0.0, passed = false,
    }
end

local function set_bar_y(gate, y)
    gate.bar_y = y
    for _, b in ipairs(gate.bars) do
        if Art.valid(b.node) then b.node:set_position(vec3(b.x, y, b.z)) end
    end
end

-- Throw the lever visual: handle swings up and glows torch-gold when pulled.
local function set_lever(gate, pulled)
    if not Art.valid(gate.handle) then return end
    gate.handle:set_rotation(vec3(pulled and -55.0 or 35.0, 0.0, 0.0))
    local c = pulled and Cond.palette.torch or Cond.palette.blood
    material.set(gate.handle, "emissive", vec3(c[1] * 1.4, c[2] * 1.4, c[3] * 1.4))
end

-- Count live creeps milling near a gate (the side-passage guards the hero must
-- clear before the lever will throw).
local function guards_near(D, x, r)
    local n = 0
    for _, c in ipairs(D.creeps) do
        if c.alive then
            local dx = c.x - x
            if dx * dx <= r * r then n = n + 1 end
        end
    end
    return n
end

-- Slam a gate shut: bars drop, and a knot of guards is summoned to hold the
-- detour. This is the horde "spending action points to cage the section".
local function slam_gate(D, gate)
    if gate.state ~= "open" or gate.passed then return false end
    gate.state = "down"; gate.t = 0.0; gate.detour_t = 0.0
    set_lever(gate, false)
    D:set_flash("LOCKDOWN!")
    Art.burst("ath_cond_slam_" .. math.floor(gate.x), vec3(gate.x, 1.2, D.arena.h * 0.5),
        { preset = "hero_take", count = 16, life_max = 0.3, spawn_radius = 0.6, noise_strength = 5.0, size_max = 0.24 })
    -- Summon the side-passage guards that hold the lever.
    for i = 1, DETOUR_GUARDS do
        local sx = gate.x + (i - 2) * 0.6
        D:spawn_one({ x = sx, y = D.arena.h * 0.5 + 0.5 }, (i == DETOUR_GUARDS) and "jailer" or "dungeon_guard", true)
    end
    return true
end

local function update_lockdown(D, dt)
    local c = D.cond
    local hero = D.hero

    -- Bank action points over the round; the horde's pressure currency.
    c.ap = math.min(AP_MAX, c.ap + AP_RATE * dt)

    -- Decide whether to cage the section ahead: the nearest OPEN, unpassed gate the
    -- hero is walking into. Spend AP to slam it shut.
    if not hero.dead then
        for _, gate in ipairs(c.gates) do
            if gate.state == "open" and not gate.passed and hero.x < gate.x then
                local d = gate.x - hero.x
                if d <= LOCKDOWN_RANGE and c.ap >= LOCKDOWN_COST then
                    if slam_gate(D, gate) then c.ap = c.ap - LOCKDOWN_COST end
                end
                break   -- only consider the next gate ahead
            end
        end
    end

    -- Advance every gate's animation + the detour/lever logic.
    for _, gate in ipairs(c.gates) do
        if gate.state == "down" then
            -- Bars finish dropping, then hold while the hero fights to the lever.
            if gate.bar_y > 3.0 then
                gate.t = gate.t + dt
                local p = math.min(1.0, gate.t / BAR_SLAM)
                set_bar_y(gate, BAR_TOP + (3.0 - BAR_TOP) * p)
            else
                gate.detour_t = gate.detour_t + dt
                -- Cage the hero behind the bars (this is the forced detour).
                if not hero.dead and hero.x < gate.x then
                    hero.x = math.min(hero.x, gate.x - BAR_BLOCK)
                end
                -- The lever throws once he's held long enough AND cleared the guards.
                if gate.detour_t >= LOCKDOWN_DETOUR and guards_near(D, gate.x, DETOUR_CLEAR) == 0 then
                    gate.state = "rising"; gate.t = 0.0
                    set_lever(gate, true)
                    D:set_flash("LEVER THROWN")
                end
            end
        elseif gate.state == "rising" then
            gate.t = gate.t + dt
            local p = math.min(1.0, gate.t / BAR_RISE)
            set_bar_y(gate, 3.0 + (BAR_TOP - 3.0) * p)
            if p >= 1.0 then gate.state = "open"; set_bar_y(gate, BAR_TOP) end
        end
        -- Mark a gate cleared once the hero walks through it (it never re-locks).
        if not gate.passed and gate.state == "open" and hero.x > gate.x + 1.0 then
            gate.passed = true
        end
        -- Pulse a locked lever so the player reads where to break the detour.
        if gate.state == "down" and Art.valid(gate.handle) then
            local f = 1.0 + 0.7 * (0.5 + 0.5 * math.sin(D.realtime * 8.0))
            material.set(gate.handle, "emissive", vec3(0.55 * f, 0.0, 0.0))
        end
    end
end

local function clear_gates(D)
    for _, gate in ipairs(D.cond and D.cond.gates or {}) do
        for _, b in ipairs(gate.bars) do if Art.valid(b.node) then scene.delete_node(b.node) end end
        if Art.valid(gate.handle) then scene.delete_node(gate.handle) end
    end
    if D.cond then D.cond.gates = {} end
end

-- ---- The WARDEN hunt (final block) -----------------------------------------

-- A bespoke boss built from a primitive rig — NOT a card creep. He wakes when the
-- hero crosses into the final block and then relentlessly tracks the hero's X,
-- clubbing him on contact. Outrun him to the exit; he enrages on a prison break.
local function build_warden(D)
    local spec = {
        name = "Cond_Warden_Hunter",
        parts = {
            body = { kind = "cube", position = { 0.0, 0.66, 0.0 }, scale = { 0.50, 0.96, 0.40 }, color = Cond.palette.black, emissive = 0.45 },
            head = { kind = "cube", position = { 0.0, 1.32, 0.0 }, scale = { 0.34, 0.32, 0.34 }, color = Cond.palette.metal, emissive = 0.7 },
            foot_r = { kind = "cube", position = { 0.14, 0.05, 0.0 }, scale = { 0.20, 0.10, 0.26 }, color = Cond.palette.black, emissive = 0.3 },
            foot_l = { kind = "cube", position = { -0.14, 0.05, 0.0 }, scale = { 0.20, 0.10, 0.26 }, color = Cond.palette.black, emissive = 0.3 },
            sword = { kind = "cube", position = { 0.46, 0.66, 0.08 }, scale = { 0.12, 0.92, 0.30 }, color = Cond.palette.metal, emissive = 0.9 },
            cape = { kind = "cube", position = { 0.0, 0.80, -0.30 }, scale = { 0.66, 1.0, 0.10 }, color = Cond.palette.blood, emissive = 0.6 },
            crown = { kind = "cube", position = { 0.0, 1.58, 0.0 }, scale = { 0.40, 0.12, 0.40 }, color = Cond.palette.metal, emissive = 0.9 },
            eye_l = { kind = "sphere", position = { -0.12, 1.34, 0.18 }, scale = { 0.10, 0.08, 0.05 }, color = Cond.palette.torch, emissive = 2.2 },
            eye_r = { kind = "sphere", position = { 0.12, 1.34, 0.18 }, scale = { 0.10, 0.08, 0.05 }, color = Cond.palette.torch, emissive = 2.2 },
        },
        -- texture = Cond.tex.warden,  -- 8-frame sprite-sheet drop-in
    }
    local actor = Art.build_actor(spec, D.groups.world)
    local cs = Art.s("char") * 1.5
    if Art.valid(actor.root) then
        actor.root:set_scale(vec3(cs, cs, cs))
        actor.root:set_position(vec3(D.arena.w - D.arena.pad - 1.0, -8.0, D.arena.h * 0.5 + 0.6))
    end
    return { actor = actor, x = D.arena.w - D.arena.pad - 1.0, z = D.arena.h * 0.5 + 0.6,
             active = false, rage = false, hit_cd = 0.0, phase = 0.0 }
end

local function update_warden(D, dt)
    local w = D.cond.warden
    local hero = D.hero
    if not w then return end

    -- Wake on the final block: the hero has cleared the second gate.
    if not w.active and not hero.dead and hero.x >= D.cond.final_x then
        w.active = true
        -- Drop in just behind the hero, at the right edge of the block.
        w.x = math.min(D.arena.w - D.arena.pad - 1.0, hero.x + 9.0)
        D:set_flash("THE WARDEN COMES")
    end
    if not w.active then return end

    w.hit_cd = math.max(0.0, w.hit_cd - dt)
    if not hero.dead then
        local spd = w.rage and WARDEN_RAGE_SPEED or WARDEN_SPEED
        local dir = (hero.x > w.x) and 1.0 or -1.0
        w.x = w.x + dir * spd * dt
        -- Club the hero on contact (jumping doesn't clear a foe this tall).
        local dx = hero.x - w.x
        if dx * dx <= WARDEN_REACH * WARDEN_REACH and w.hit_cd <= 0.0 then
            D:apply_hero_damage(WARDEN_HIT * (w.rage and 1.4 or 1.0), { flash = "THE WARDEN STRIKES!" })
            w.hit_cd = WARDEN_HIT_CD
            Art.burst("ath_cond_warden", vec3(hero.x, 0.9, hero.z),
                { preset = "hero_take", count = 14, life_max = 0.3, spawn_radius = 0.4, noise_strength = 4.0, size_max = 0.22 })
        end
    end

    w.phase = w.phase + dt * (w.rage and 11.0 or 8.0)
    if Art.valid(w.actor.root) then
        local dir = (hero.x >= w.x) and 90.0 or -90.0
        w.actor.root:set_position(vec3(w.x, 0.0, w.z))
        w.actor.root:set_rotation(vec3(0.0, dir, 0.0))
    end
    Art.animate(w.actor, "walk", w.phase / 8.0)
end

-- ---- PRISON BREAK: HP-threshold alarms -------------------------------------

local function trigger_break(D)
    local c = D.cond
    c.breaks = c.breaks + 1
    D:set_flash("PRISON BREAK!")
    -- Every standing, unpassed gate slams in the chaos.
    for _, gate in ipairs(c.gates) do slam_gate(D, gate) end
    -- A surge of reinforcements pours from the far end (free spawns).
    local A = D.arena
    for i = 1, 4 + c.breaks * 2 do
        local sx = A.w - A.pad - 1.0 - (i % 4)
        D:spawn_one({ x = sx, y = A.h * 0.5 + ((i % 5) - 2) }, (i % 3 == 0) and "prison_hound" or "dungeon_guard", true)
    end
    -- The Warden is enraged (and woken early if he was still dormant).
    if c.warden then
        c.warden.rage = true
        if not c.warden.active then
            c.warden.active = true
            c.warden.x = math.min(A.w - A.pad - 1.0, D.hero.x + 9.0)
        end
    end
    Art.burst("ath_cond_break_" .. c.breaks, vec3(D.hero.x, 1.4, A.h * 0.5),
        { preset = "hero_take", count = 30, life_max = 0.5, spawn_radius = 2.0, noise_strength = 6.0, size_max = 0.3 })
end

local function update_breaks(D, dt)
    local c = D.cond
    local hero = D.hero
    if hero.dead then return end
    local frac = hero.hp / math.max(1.0, hero.hp_max)
    -- Fire each threshold once, in order, as the hero's HP bleeds down.
    while c.break_idx <= #c.break_at and frac <= c.break_at[c.break_idx] do
        c.break_idx = c.break_idx + 1
        trigger_break(D)
    end
end

-- ---- Hero Y-axis physics: the gravity-arc escape jump ----------------------

local function update_hero_physics(D, dt)
    local hero = D.hero
    local j = D.cond.jump
    if hero.dead then j.active = false; return end

    -- Gravity-arc jump: launch velocity solved from the desired apex (v=sqrt(2gh)).
    if j.active then
        j.t = j.t + dt
        local v0 = math.sqrt(2.0 * GRAVITY * JUMP_APEX)
        j.y = v0 * j.t - 0.5 * GRAVITY * j.t * j.t
        if j.y <= 0.0 and j.t > 0.05 then j.active = false; j.y = 0.0 end
    end

    -- Apply the Y lift on top of what update_hero already wrote this frame
    -- (on_combat_tick runs AFTER update_hero, so this is the final say on the root).
    if Art.valid(hero.root) then
        hero.root:set_position(vec3(hero.x, j.y, hero.z))
        hero.root:set_rotation(vec3(0.0, math.deg(hero.facing), 0.0))
        local ws = hero.world_scale or 1.0
        if j.active then
            local sq = 1.0 - 0.12 * math.sin(math.min(1.0, j.y / JUMP_APEX) * math.pi)
            hero.root:set_scale(vec3(ws, ws * sq, ws))
        else
            hero.root:set_scale(vec3(ws, ws, ws))
        end
    end
end

-- Cue an escape leap when the hero is pinned against freshly-slammed bars, so the
-- jump arc reads as part of the break-out (cosmetic — the bars still cage him).
local function maybe_jump(D)
    local j = D.cond.jump
    if j.active then return end
    local hero = D.hero
    if hero.dead then return end
    for _, gate in ipairs(D.cond.gates) do
        if gate.state == "down" and gate.bar_y <= 3.0 then
            local d = gate.x - hero.x
            if d > 0.0 and d <= BAR_BLOCK + 0.4 then j.active = true; j.t = 0.0; return end
        end
    end
end

-- ---- Escape: the WIN on reaching the outer gate, and the alarm-timer LOSS ---

local function update_escape(D, dt)
    local c = D.cond
    if D.hero.dead then return end
    -- WIN = ESCAPE: clear the outer gate at the far-right end of the final block.
    if D.hero.x >= c.exit_x then
        D.state = "hero_win"
        D:set_flash("ESCAPED")
        D:log(string.format("CONDEMNED ESCAPE round=%d kills=%d", D.round, D.kills))
        return
    end
    -- LOSE = TIMER: the alarm clock runs out and the block executes the hero.
    c.timer = c.timer - dt
    if c.timer <= 0.0 then
        c.timer = 0.0
        D:apply_hero_damage((D.hero.hp or 0.0) + 9999.0, { flash = "ALARM — EXECUTED", ignore_armor = true })
    end
end

-- ---- Camera: a side-on rig that tracks the hero down the block -------------

local function update_camera(D)
    local A = D.arena
    local half = A.ortho_size * 0.5
    local cx = math.max(A.pad + half * 0.4, math.min(A.w - A.pad - half * 0.4, D.hero.x))
    Art.setup_iso_camera({ x = cx, z = A.h * 0.5 - 0.5 },
        { ortho_size = A.ortho_size, offset = A.cam_offset })
    if Art.valid(D.cond.bg) then D.cond.bg:set_position(vec3(PARALLAX * cx, 3.2, A.h - A.pad + 1.2)) end
end

-- ---- Hero class selection (two classes; brief) -----------------------------

local function pick_hero()
    local class = "convict"
    if ATH_COMMON and ATH_COMMON.getenv then
        local v = ATH_COMMON.getenv("ATH_COND_CLASS")
        if type(v) == "string" and Cond.heroes[v:lower()] then class = v:lower() end
    end
    return class, Cond.heroes[class]
end

local CLASS, HERO = pick_hero()

-- ---------------------------------------------------------------------------
-- Mode contract
-- ---------------------------------------------------------------------------

return {
    meta = {
        id = "condemned",
        name = "Condemned",
        tagline = "the side-scrolling prison break",
        blurb = "A 2D side-scroller out of a dark stone gaol. Three barred blocks lie between you and the gate; the warders slam lockdowns to cage you, and the Warden hunts the final block. Reach the exit.",
        side_hint = "horde",
        accent = { 0.55, 0.0, 0.0, 0.95 },
        -- A side-on sketch of the cell block (normalized 0..1 rects: x,y,w,h,color).
        minimap = {
            bg = { 0.05, 0.05, 0.05, 1.0 },
            rects = {
                { 0.04, 0.62, 0.92, 0.10, { 0.173, 0.173, 0.173, 1.0 } }, -- floor
                { 0.04, 0.18, 0.92, 0.12, { 0.11, 0.11, 0.11, 1.0 } },    -- cell wall band
                { 0.07, 0.46, 0.05, 0.16, { 0.66, 0.63, 0.58, 1.0 } },    -- hero (left)
                { 0.30, 0.30, 0.02, 0.32, { 0.29, 0.29, 0.29, 1.0 } },    -- gate 1 bars
                { 0.56, 0.30, 0.02, 0.32, { 0.29, 0.29, 0.29, 1.0 } },    -- gate 2 bars
                { 0.80, 0.30, 0.02, 0.32, { 0.29, 0.29, 0.29, 1.0 } },    -- gate 3 bars
                { 0.40, 0.50, 0.04, 0.12, { 0.29, 0.29, 0.29, 1.0 } },    -- patrol guards
                { 0.66, 0.50, 0.04, 0.12, { 0.29, 0.29, 0.29, 1.0 } },
                { 0.84, 0.44, 0.05, 0.18, { 0.55, 0.0, 0.0, 1.0 } },      -- the Warden
                { 0.18, 0.24, 0.02, 0.10, { 1.0, 0.40, 0.0, 1.0 } },      -- torches
                { 0.62, 0.24, 0.02, 0.10, { 1.0, 0.40, 0.0, 1.0 } },
                { 0.90, 0.40, 0.05, 0.28, { 1.0, 0.40, 0.0, 1.0 } },      -- exit portal (right)
            },
        },
    },

    config = {
        id = "condemned",
        name = "Condemned",
        theme = Cond.theme,
        -- A long, shallow CELL BLOCK. Wide X (read left->right), shallow Z depth, and
        -- a low side-on camera that tracks the hero (update_camera, each tick).
        arena = {
            width = 88, height = 16, pad = 2, ortho_size = 22.0,
            cam_offset = { x = 0.0, y = 10.0, z = -30.0 },   -- side elevation, not iso
            hero_start = { x = 5, y = 8 },
            -- The garrison pours from the FAR (right) end; the hero advances
            -- left->right through the blocks toward the exit.
            spawns = {
                { x = 82, y = 8 }, { x = 84, y = 6 }, { x = 84, y = 10 },
                { x = 80, y = 5 }, { x = 80, y = 11 }, { x = 76, y = 8 },
            },
        },
        hero = {
            hp_max = HERO.stats.hp_max, dps = HERO.stats.dps, cleave = HERO.stats.cleave,
            attack_range = HERO.stats.attack_range, speed = HERO.stats.speed, kite_speed = HERO.stats.kite_speed,
            actor = HERO.actor,
        },
        archetypes = Cond.archetypes,
        roles = Cond.roles,
        spawn = { interval_start = 0.8, interval_min = 0.35, batch_start = 3, batch_max = 6, cap_start = 28, cap_max = 84, brute_after = 22.0 },
        reserve_start = 320.0,
        round_seconds = 14.0,

        -- A gaol mix: guard chaff + hounds, periodic sentries, slow jailers as
        -- elites, and a late Warden card.
        auto_mix = function(D)
            if D.combat_time >= D.spawn_cfg.brute_after and (D.spawn_counter % 13 == 0) then return "warden" end
            if D.spawn_counter % 8 == 0 then return "jailer" end
            if D.spawn_counter % 5 == 0 then return "crossbow_sentry" end
            return (D.spawn_counter % 2 == 0) and "prison_hound" or "dungeon_guard"
        end,

        hooks = {
            on_start = function(D)
                local A = D.arena
                D.cond = {
                    gates = {}, patrols = {}, torches = {},
                    jump = { active = false, t = 0.0, y = 0.0 },
                    ap = 0.0, breaks = 0, break_idx = 1, break_at = { 0.66, 0.33 },
                    warden = nil, final_x = 0.0, bg = nil, class = CLASS,
                    timer = ESCAPE_SECONDS, exit_x = A.w - A.pad - 2.0,   -- alarm clock + escape line
                }
                local g = D.groups.world
                local far_z = A.h - A.pad + 1.2

                -- A very dark distant backdrop (cell rows) for parallax depth.
                D.cond.bg = Art.cube("Cond_Background", vec3(PARALLAX * A.w * 0.5, 3.2, far_z),
                    vec3(A.w * 1.6, 8.0, 0.2), { 0.55, 0.55, 0.55 }, g, 0.2, Cond.tex.background)

                -- A textured stone back wall, panelled so the seamless tile reads.
                local panel = 4.0
                for px = A.pad, A.w - A.pad, panel do
                    Art.cube("BackWall_" .. math.floor(px), vec3(px + panel * 0.5, 3.3, A.h - A.pad - 0.2),
                        vec3(panel, 6.6, 0.4), Cond.palette.stone, g, 0.6, Cond.tex.wall)
                end

                -- Torch line along the back wall (flicker driven in on_combat_tick).
                for tx = A.pad + 4, A.w - A.pad - 2, 9 do
                    D.cond.torches[#D.cond.torches + 1] = build_torch(D, tx, 3.4, A.h - A.pad - 0.5)
                end

                -- Barred cells recessed into the back wall (dressing).
                for cx = A.pad + 6, A.w - A.pad - 6, 7 do
                    build_cell(D, cx, A.h - A.pad - 1.1)
                end

                -- The three LOCKDOWN gates that cut the block into sections.
                local fr = { 0.30, 0.58, 0.82 }
                for _, f in ipairs(fr) do
                    D.cond.gates[#D.cond.gates + 1] = build_gate(D, A.pad + (A.w - A.pad * 2.0) * f)
                end
                -- "Final block": once the hero clears the 2nd gate the Warden wakes.
                D.cond.final_x = D.cond.gates[2].x + 2.0

                -- Patrolling guards walking the cell fronts (decorative AI, brief).
                D.cond.patrols[#D.cond.patrols + 1] = build_patrol(D, A.w * 0.40, A.h * 0.5 + 1.2, 4.0)
                D.cond.patrols[#D.cond.patrols + 1] = build_patrol(D, A.w * 0.66, A.h * 0.5 + 1.2, 3.5)

                -- The dormant Warden, parked below the floor until the final block.
                D.cond.warden = build_warden(D)

                -- The EXIT PORTAL (an open gate to freedom) at the far-right end.
                local ex = A.w - A.pad - 1.5
                Art.cube("Portal_Frame_L", vec3(ex - 0.9, 1.7, A.h * 0.5), vec3(0.4, 3.4, 0.5), Cond.palette.stone, g, 0.6)
                Art.cube("Portal_Frame_R", vec3(ex + 0.9, 1.7, A.h * 0.5), vec3(0.4, 3.4, 0.5), Cond.palette.stone, g, 0.6)
                Art.cube("Portal_Arch", vec3(ex, 3.5, A.h * 0.5), vec3(2.4, 0.5, 0.5), Cond.palette.stone, g, 0.6)
                D.cond.portal = Art.cube("Portal_Glow", vec3(ex, 1.7, A.h * 0.5), vec3(1.4, 3.2, 0.12), Cond.palette.torch, g, 1.4, Cond.tex.portal)

                update_camera(D)
            end,

            on_reset = function(D)
                clear_gates(D)
                if D.cond then
                    if D.cond.warden and Art.valid(D.cond.warden.actor.root) then
                        scene.delete_node(D.cond.warden.actor.root)
                    end
                    D.cond.jump = { active = false, t = 0.0, y = 0.0 }
                    D.cond.ap = 0.0; D.cond.breaks = 0; D.cond.break_idx = 1
                    D.cond.timer = ESCAPE_SECONDS    -- restart the alarm clock
                    -- Re-seat the three gates the run started with.
                    local A = D.arena
                    local fr = { 0.30, 0.58, 0.82 }
                    for _, f in ipairs(fr) do
                        D.cond.gates[#D.cond.gates + 1] = build_gate(D, A.pad + (A.w - A.pad * 2.0) * f)
                    end
                    D.cond.final_x = D.cond.gates[2].x + 2.0
                    D.cond.warden = build_warden(D)
                end
            end,

            on_combat_tick = function(D, dt)
                update_lockdown(D, dt)   -- may cage the hero (clamp x)
                update_breaks(D, dt)
                update_warden(D, dt)
                update_patrols(D, dt)
                maybe_jump(D)
                update_hero_physics(D, dt)   -- writes the final hero root transform
                update_escape(D, dt)         -- win on the gate, lose on the alarm clock
                update_camera(D)
                -- Torch flicker: emissive wobble + a touch of random guttering.
                for _, t in ipairs(D.cond.torches) do
                    if Art.valid(t.node) then
                        local f = 1.3 + 0.5 * math.sin(D.realtime * 11.0 + t.seed) + 0.2 * math.sin(D.realtime * 27.0 + t.seed * 2.0)
                        material.set(t.node, "emissive", vec3(1.0 * f, 0.40 * f, 0.0))
                    end
                end
                -- The exit beckons with a slow torch-gold pulse.
                if Art.valid(D.cond.portal) then
                    local pf = 1.0 + 0.6 * (0.5 + 0.5 * math.sin(D.realtime * 3.0))
                    material.set(D.cond.portal, "emissive", vec3(1.0 * pf, 0.40 * pf, 0.0))
                end
            end,

            draw_hud = function(D)
                local sw, sh = Art.surface_size()
                local A = D.arena
                local c = D.cond
                -- Block progress toward the far exit (left->right "depth").
                local prog = math.max(0.0, math.min(1.0, (D.hero.x - 5.0) / ((A.w - A.pad - 1.5) - 5.0)))
                local caged = 0
                for _, gate in ipairs(c.gates) do if gate.state ~= "open" then caged = caged + 1 end end
                local warden = (c.warden and c.warden.active) and (c.warden.rage and "ENRAGED" or "HUNTING") or "dormant"
                local secs = math.max(0, math.floor((c.timer or 0.0) + 0.5))
                Art.quad(D.hud, "cond_panel", 24.0, sh - 150.0, 700.0, 58.0, { 0.05, 0.05, 0.05, 0.9 },
                    { border = { 0.55, 0.0, 0.0, 0.9 },
                      label = string.format("CLASS: %s   Depth: %d%%   ALARM %d:%02d   Lockdowns: %d   Warden: %s",
                        c.class:upper(), math.floor(prog * 100.0 + 0.5), math.floor(secs / 60), secs % 60, caged, warden) })
                -- Lockdown action-point meter (the horde's caging currency).
                local pct = c.ap / AP_MAX
                Art.quad(D.hud, "cond_ap_bg", 24.0, sh - 86.0, 360.0, 22.0, { 0.08, 0.05, 0.05, 0.9 },
                    { border = { 0.55, 0.0, 0.0, 0.8 } })
                Art.quad(D.hud, "cond_ap_fill", 26.0, sh - 84.0, math.max(0.0, 356.0 * pct), 18.0,
                    { 0.55 + 0.45 * pct, 0.10, 0.0, 0.95 }, { label = (pct >= LOCKDOWN_COST / AP_MAX) and "LOCKDOWN READY" or "Lockdown charging" })
            end,
        },
    },
}
