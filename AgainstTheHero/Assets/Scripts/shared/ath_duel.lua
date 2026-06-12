-- ath_duel — the shared HERO-vs-HORDE duel engine every mode runs on.
--
-- This is the generalised, reusable heart of the rush prototype: one arena, one
-- auto-fighting hero, a continuous rushing swarm, and a ROUND/PAUSE loop where
-- both sides grow via the dual-faced cards. A "mode" is now mostly CONTENT — a
-- theme, an arena, a cast of characters (creep archetypes), and one signature
-- mechanic — handed to Duel.new(config). The loop, the reserve economy, the card
-- application, the HUD, the camera, win/loss, and the AI for whichever seat the
-- player did NOT pick all live here, so every mode plays consistently.
--
-- The player picked a SIDE in the menu (ctx.side). Either way the hero
-- auto-fights and the swarm auto-rushes; the only difference is which SEAT's
-- cards the human plays at each pause, and which side's victory counts as a win:
--   * side = "hero"  -> human plays the hero's FRONT upgrade cards; AI commands
--                       the horde. Win when the reserve is spent and field clear.
--   * side = "horde" -> human commands the horde's BACK cards; AI upgrades the
--                       hero. Win when the hero's HP hits 0.
--
-- Reuses shared/duel_flow.lua (map + flow field) and shared/duel_creep.lua
-- (characters with movement, projectiles, procedural animation). Visuals/HUD go
-- through ath_art.
--
-- See modes/pit/mode.lua for a worked example of a mode config.

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Cards = ATH_COMMON.load_script("Scripts/shared/ath_cards.lua", "shared cards", _ENV)
local Flow = ATH_COMMON.load_script("Scripts/shared/duel_flow.lua", "duel flow", _ENV)
local Creep = ATH_COMMON.load_script("Scripts/shared/duel_creep.lua", "duel creep", _ENV)
local Console = ATH_COMMON.load_script("Scripts/shared/ath_console.lua", "dev console", _ENV)

local Duel = {}
Duel.__index = Duel

local SLOWMO_SCALE = 0.4
local SLOWMO_DURATION = 1.2
local WHIRL_CD = 1.2
local WHIRL_RADIUS_BASE = 2.0

local function clampn(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- A minimal flat sprite hero (single textured quad, no sword/cape) for top-down
-- manual-hero modes. Avoids loading the large knight textures (which would only
-- be hidden anyway); ath_topdown_view lays the body flat and re-applies the
-- mode's sprite each frame.
--
local function flat_hero_actor(sprite_texture)
    return {
        name = "Flat_Hero",
        parts = {
            body = {
                kind = "quad", quad_width = 1.6, quad_height = 2.2,
                position = { 0.0, 1.1, 0.0 },
                color = { 1.0, 1.0, 1.0 }, emissive = 1.0, emissive_texture = true,
                texture = sprite_texture or "Objects/white.png",
            },
        },
    }
end

-- A sensible default hero rig (the classic knight) used when a mode does not
-- supply config.hero.actor. Part keys match ath_art's built-in walk/attack clips.
local function default_hero_actor(theme)
    return {
        name = "Souls_Knight",
        soft_cape = {
            width    = 2.0,
            height   = 1.6,
            segments = 48,
            bones    = 20,
            position = { 0.0, 0.75, 0.12 },
            rotation = { 0.0, 0.0, -90.0 },
            scale    = { 1.0, 1.0, 1.0 },
            texture  = "Textures/hero/knight/knight_cape_strip.png",
            wave_speed   = 2.5,
            wave_phase   = 3.0,
            wave_amp_deg = 10.0,
        },
        parts = {
            body  = {
                kind = "quad", quad_width = 1.6, quad_height = 2.2,
                position = { 0.0, 1.1, 0.0 },
                color = { 1.0, 1.0, 1.0 }, emissive = 1.0, emissive_texture = true,
                texture = "Textures/hero/knight/knight_body.png",
            },
            sword = {
                kind = "quad", quad_width = 1.6, quad_height = 2.2,
                position = { 0.0, 1.1, 0.05 },
                color = { 1.0, 1.0, 1.0 }, emissive = 1.0, emissive_texture = true,
                texture = "Textures/hero/knight/knight_sword.png",
            },
        },
    }
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

function Duel.new(config, ctx, shell)
    local D = setmetatable({}, Duel)
    D.config = config or {}
    D.ctx = ctx or {}
    D.shell = shell
    D.manual_hero = D.config.manual_hero == true
    D.side = D.manual_hero and "hero" or ((ctx and ctx.side == "horde") and "horde" or "hero")
    D.hud = "ath.duel.hud"
    D.theme = D.config.theme or {}
    D.key_down = {}
    D.creeps = {}
    D.spawn_queue = {}
    D.next_id = 0
    D.spawn_counter = 0
    D.realtime = 0.0
    D.fallback_dt = 1.0 / 120.0
    D.autoplay = ATH_COMMON.env_enabled("ATH_DUEL_AUTOPLAY", false)
    D.flash = ""
    D.flash_t = 0.0

    -- Arena geometry.
    local a = D.config.arena or {}
    D.arena = {
        w = a.width or 48,
        h = a.height or 34,
        pad = a.pad or 2,
        ortho_size = a.ortho_size or 34.0,
        cam_offset = a.cam_offset or { x = -44.0, y = 44.0, z = 44.0 },
    }
    D.arena.hero_start = a.hero_start or { x = math.floor(D.arena.w * 0.5), y = math.floor(D.arena.h * 0.5) }
    -- Open arenas (the default) have no interior obstacles, so creeps BEELINE
    -- straight at the hero (Creep.update falls back to direct pursuit when no flow
    -- field is supplied). A mode with a maze sets arena.flow_field = true to get
    -- the 4-connected flow-field pathing instead.
    D.use_flow_field = a.flow_field == true

    -- Hero baseline.
    local h = D.config.hero or {}
    D.hero_spec = {
        hp_max = h.hp_max or 90.0,
        dps = h.dps or 20.0,
        cleave = h.cleave or 3,
        attack_range = h.attack_range or 1.25,
        speed = h.speed or 2.2,
        kite_speed = h.kite_speed or 2.7,
        body_radius = h.body_radius or 0.6,
        kite_threshold = h.kite_threshold or 0.30,
        kite_distance = h.kite_distance or 4.5,
        actor = h.actor or default_hero_actor(D.theme),
    }

    -- Spawn tuning.
    local s = D.config.spawn or {}
    D.spawn_cfg = {
        interval_start = s.interval_start or 0.7,
        interval_min = s.interval_min or 0.3,
        interval_ramp = s.interval_ramp or 0.05,
        batch_start = s.batch_start or 3,
        batch_max = s.batch_max or 7,
        cap_start = s.cap_start or 32,
        cap_max = s.cap_max or 90,
        brute_after = s.brute_after or 18.0,
    }

    D.roles = D.config.roles or {}
    D.reserve_start = ATH_COMMON.getenv_number("ATH_DUEL_RESERVE", D.config.reserve_start or 300.0)
    D.round_seconds = ATH_COMMON.getenv_number("ATH_DUEL_ROUND", D.config.round_seconds or 14.0)

    local waves = D.config.waves or {}
    D.wave_cfg = {
        count = waves.count or 5,
        budgets = waves.budgets,
        reserve_start = waves.reserve_start,
        reserve_add = waves.reserve_add or 40.0,
    }
    local gear = D.config.gear or {}
    D.gear_cfg = {
        items = gear.items or {},
        drop_every = gear.drop_every or 6,
        gold_per_kill = gear.gold_per_kill or 1,
    }
    return D
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

function Duel:log(msg)
    if pe_log then pe_log("[ATH:" .. tostring(self.config.id or "duel"):upper() .. "] " .. tostring(msg)) end
end

function Duel:key_pressed(name)
    if not input or not input.is_key_down then return false end
    local down = input.is_key_down(name)
    local pressed = down and not self.key_down[name]
    self.key_down[name] = down
    return pressed
end

function Duel:is_key_down(name)
    return input and input.is_key_down and input.is_key_down(name) == true
end

function Duel:set_flash(text)
    self.flash = text or ""
end

-- ---------------------------------------------------------------------------
-- Arena
-- ---------------------------------------------------------------------------

function Duel:build_arena()
    local A = self.arena
    local theme = self.theme
    local def = self.config.arena and self.config.arena.map_def
    if not def then
        def = {
            id = (self.config.id or "duel") .. "_arena",
            title = self.config.name or "Arena",
            width = A.w, height = A.h, tile_world = 1.0,
            hero_start = A.hero_start,
            rooms = { {
                id = "pit", name = self.config.name or "The Pit",
                rect = { x = A.pad, y = A.pad, w = A.w - A.pad * 2, h = A.h - A.pad * 2 },
                anchors = {},
            } },
            corridors = {},
        }
    end
    self.map = Flow.build_map(def)

    -- Perimeter spawn points (the swarm pours in from all sides).
    self.spawns = (self.config.arena and self.config.arena.spawns) or nil
    if not self.spawns then
        local inset = A.pad + 1
        self.spawns = {
            { x = inset, y = inset },
            { x = A.w - inset - 1, y = inset },
            { x = inset, y = A.h - inset - 1 },
            { x = A.w - inset - 1, y = A.h - inset - 1 },
            { x = math.floor(A.w * 0.5), y = inset },
            { x = math.floor(A.w * 0.5), y = A.h - inset - 1 },
        }
    end

    -- Cheap, self-lit stage (emissive only — scene lighting barely reaches here).
    local cx = A.w * 0.5 - 0.5
    local cz = A.h * 0.5 - 0.5
    -- The floor VISUAL may extend past the playable bounds (config.arena.
    -- floor_extent) so an ultra-wide camera never shows the raw scene around
    -- the pit; the walls still mark the real gameplay edge.
    local fx = (self.config.arena and self.config.arena.floor_extent) or {}
    local fw = fx.width or A.w
    local fh = fx.height or A.h
    Art.cube("Floor", vec3(cx, -0.05, cz), vec3(fw, 0.1, fh), theme.floor or { 0.26, 0.24, 0.32 }, self.groups.world, 0.9, theme.floor_texture)
    local wall = theme.wall or { 0.42, 0.36, 0.50 }
    Art.cube("Wall_N", vec3(cx, 0.5, A.pad - 0.5), vec3(A.w, 1.2, 0.4), wall, self.groups.world, 0.8)
    Art.cube("Wall_S", vec3(cx, 0.5, A.h - A.pad - 0.5), vec3(A.w, 1.2, 0.4), wall, self.groups.world, 0.8)
    Art.cube("Wall_W", vec3(A.pad - 0.5, 0.5, cz), vec3(0.4, 1.2, A.h), wall, self.groups.world, 0.8)
    Art.cube("Wall_E", vec3(A.w - A.pad - 0.5, 0.5, cz), vec3(0.4, 1.2, A.h), wall, self.groups.world, 0.8)
    local sigil = theme.spawn_sigil or { 0.92, 0.26, 0.22 }
    for i, sp in ipairs(self.spawns) do
        Art.cylinder("Spawn_" .. i, vec3(sp.x, 0.03, sp.y), vec3(1.1, 0.04, 1.1), sigil, self.groups.world, 1.2)
    end
end

-- ---------------------------------------------------------------------------
-- Hero (auto-fighting actor; the "hero seat" cards upgrade it)
-- ---------------------------------------------------------------------------

function Duel:create_hero()
    local spec = self.hero_spec
    local hero = {
        x = self.arena.hero_start.x, z = self.arena.hero_start.y,
        hp = spec.hp_max, hp_max = spec.hp_max,
        dps = spec.dps, base_dps = spec.dps,
        cleave = spec.cleave, attack_range = spec.attack_range,
        speed = spec.speed, base_speed = spec.speed,
        kite_speed = spec.kite_speed, base_kite_speed = spec.kite_speed,
        body_radius = spec.body_radius,
        phase = 0.0, facing = 0.0, attack_flash = 0.0,
        dead = false, death_t = 0.0,
        lifesteal = 0.0, regen = 0.0, whirl = 0, whirl_t = 0.0,
        armor = 0.0, thorns = 0.0, dash = 0,
        -- Transient per-frame multipliers a mode's mechanic may set in
        -- on_combat_tick to slow/shrink the hero WITHOUT corrupting card-stacked
        -- stats (ice slow, mud, sandstorm). Mode-owned: set every tick, 1.0 = off.
        move_mult = 1.0, range_mult = 1.0,
        thought = "",
    }
    hero.base_stats = {
        hp_max = hero.hp_max,
        dps = hero.dps,
        cleave = hero.cleave,
        attack_range = hero.attack_range,
        speed = hero.speed,
        kite_speed = hero.kite_speed,
        armor = hero.armor,
        lifesteal = hero.lifesteal,
        regen = hero.regen,
        whirl = hero.whirl,
        thorns = hero.thorns,
        dash = hero.dash,
    }
    -- "Replace the hero with the 2D souls-knight everywhere": every duel mode
    -- supplies its own themed actor, so force the knight rig here (set
    -- Duel.FORCE_KNIGHT = false to fall back to the mode's own rig).
    local actor_spec = spec.actor
    if self.manual_hero then
        -- Top-down manual hero: a single flat sprite quad, NOT the knight rig
        -- (skips loading ~1.2 MB of knight textures that would only be hidden).
        actor_spec = flat_hero_actor(self.config.hero and self.config.hero.sprite_texture)
    elseif Duel.FORCE_KNIGHT ~= false then
        actor_spec = default_hero_actor(self.theme)
    end
    hero.actor = (actor_spec and actor_spec.soft_cape)
        and Art.build_soft_actor(actor_spec, self.groups.actors)
        or  Art.build_actor(actor_spec, self.groups.actors)
    hero.root = hero.actor.root
    hero.parts = hero.actor.parts
    if pe_log then
        local np = 0; for _ in pairs(hero.parts or {}) do np = np + 1 end
        pe_log(string.format("[KNIGHT] forced=%s soft=%s root=%s parts=%d cape=%s",
            tostring(Duel.FORCE_KNIGHT ~= false),
            tostring(actor_spec and actor_spec.soft_cape ~= nil),
            tostring(Art.valid(hero.root)), np,
            tostring(hero.parts and Art.valid(hero.parts.soft_cape))))
    end
    -- An attack-range aura ring, if the rig didn't already provide one.
    if not hero.parts.aura then
        hero.parts.aura = Art.cylinder("Hero_Aura", vec3(0.0, 0.04, 0.0),
            vec3(spec.attack_range * 2.0, 0.03, spec.attack_range * 2.0),
            (self.theme.aura or { 0.42, 0.70, 0.95, 0.5 }), hero.root, 0.7)
    end
    -- World character scale — make the hero read clearly at the iso distance.
    local cs = Art.s("char")
    local base = (spec.actor and spec.actor.scale) or 1.0
    hero.world_scale = base * cs
    if Art.valid(hero.root) then
        hero.root:set_scale(vec3(hero.world_scale, hero.world_scale, hero.world_scale))
        hero.root:set_position(vec3(hero.x, 0.0, hero.z))
    end
    self.hero = hero
end

function Duel:swarm_centroid()
    local n, sx, sz = 0, 0.0, 0.0
    for _, c in ipairs(self.creeps) do
        if c.alive then n = n + 1; sx = sx + c.x; sz = sz + c.z end
    end
    if n == 0 then return nil end
    return sx / n, sz / n
end

function Duel:nearest_creep(hero)
    local best, best_d
    for _, c in ipairs(self.creeps) do
        if c.alive then
            local dx, dz = c.x - hero.x, c.z - hero.z
            local d = dx * dx + dz * dz
            if not best or d < best_d then best, best_d = c, d end
        end
    end
    if not best then return nil, nil end
    return best, math.sqrt(best_d)
end

function Duel:move_hero(hero, dirx, dirz, speed, dt)
    local A = self.arena
    speed = speed * (hero.move_mult or 1.0)
    hero.x = clampn(hero.x + dirx * speed * dt, A.pad + 0.8, A.w - A.pad - 1.8)
    hero.z = clampn(hero.z + dirz * speed * dt, A.pad + 0.8, A.h - A.pad - 1.8)
    if dirx * dirx + dirz * dirz > 0.0001 then hero.facing = math.atan(dirx, dirz) end
end

function Duel:hero_attack(hero, dt)
    local in_range = {}
    local eff_range = hero.attack_range * (hero.range_mult or 1.0)
    local r2 = eff_range * eff_range
    for _, c in ipairs(self.creeps) do
        if c.alive then
            local dx, dz = c.x - hero.x, c.z - hero.z
            local d = dx * dx + dz * dz
            if d <= r2 then in_range[#in_range + 1] = { c = c, d = d } end
        end
    end
    if #in_range == 0 then return end
    table.sort(in_range, function(a, b) return a.d < b.d end)
    hero.attack_flash = 0.12
    local targets = math.min(hero.cleave, #in_range)
    for i = 1, targets do
        local mult = (i == 1) and 1.0 or 0.45
        local c = in_range[i].c
        if Creep.damage(c, hero.dps * mult * dt) then
            c.alive = false
            if hero.lifesteal > 0.0 then hero.hp = math.min(hero.hp_max, hero.hp + hero.lifesteal) end
        end
    end
end

function Duel:hero_whirl(hero, dt)
    if (hero.whirl or 0) <= 0 then return end
    hero.whirl_t = (hero.whirl_t or 0.0) - dt
    if hero.whirl_t > 0.0 then return end
    hero.whirl_t = WHIRL_CD
    local radius = WHIRL_RADIUS_BASE + 0.4 * hero.whirl
    local r2 = radius * radius
    local damage = hero.dps * 0.6 * hero.whirl
    for _, c in ipairs(self.creeps) do
        if c.alive then
            local dx, dz = c.x - hero.x, c.z - hero.z
            if dx * dx + dz * dz <= r2 then
                if Creep.damage(c, damage) then
                    c.alive = false
                    if hero.lifesteal > 0.0 then hero.hp = math.min(hero.hp_max, hero.hp + hero.lifesteal) end
                end
            end
        end
    end
    Art.burst("ath_duel_whirl", vec3(hero.x, 0.5, hero.z),
        { preset = "hero_take", count = 18, life_max = 0.28, spawn_radius = radius * 0.5, noise_strength = 4.0, size_max = 0.18 })
end

function Duel:update_hero(dt)
    local hero = self.hero
    if not hero then return end
    if hero.dead then
        hero.death_t = hero.death_t + dt
        if Art.valid(hero.root) then
            hero.root:set_position(vec3(hero.x, 0.0, hero.z))
            hero.root:set_rotation(vec3(90.0, math.deg(hero.facing), 0.0))
            local ws = hero.world_scale or 1.0
            hero.root:set_scale(vec3(ws, 0.35 * ws, ws))
        end
        if Art.valid(hero.parts.aura) then hero.parts.aura:set_scale(vec3(0.01, 0.01, 0.01)) end
        return
    end

    if hero.regen > 0.0 then hero.hp = math.min(hero.hp_max, hero.hp + hero.regen * dt) end

    local target, tdist = self:nearest_creep(hero)
    if self.manual_hero then
        -- Suppress movement while the dev console is open so tuning keys don't drive.
        local console_open = self.console and self.console.visible
        local dirx, dirz = 0.0, 0.0
        if not console_open then
            dirx = (self:is_key_down("D") or self:is_key_down("Right")) and 1.0 or 0.0
            dirx = dirx - ((self:is_key_down("A") or self:is_key_down("Left")) and 1.0 or 0.0)
            dirz = (self:is_key_down("S") or self:is_key_down("Down")) and 1.0 or 0.0
            dirz = dirz - ((self:is_key_down("W") or self:is_key_down("Up")) and 1.0 or 0.0)
        end
        -- Smooth the input asymmetrically: starts/turns ease in over ~50 ms,
        -- but releasing the keys bites in ~25 ms — the hero plants almost
        -- (not quite) instantly instead of sliding to a stop.
        local mag = math.sqrt(dirx * dirx + dirz * dirz)
        local tvx, tvz = 0.0, 0.0
        if mag > 0.001 then
            tvx = dirx / mag * hero.speed
            tvz = dirz / mag * hero.speed
        end
        local rate = (mag > 0.001) and 20.0 or 40.0
        local blend = math.min(1.0, rate * dt)
        hero.vel_x = (hero.vel_x or 0.0) + (tvx - (hero.vel_x or 0.0)) * blend
        hero.vel_z = (hero.vel_z or 0.0) + (tvz - (hero.vel_z or 0.0)) * blend
        local sp = math.sqrt(hero.vel_x * hero.vel_x + hero.vel_z * hero.vel_z)
        if sp > 0.05 then
            self:move_hero(hero, hero.vel_x / sp, hero.vel_z / sp, sp, dt)
        elseif target then
            local dx, dz = target.x - hero.x, target.z - hero.z
            hero.facing = math.atan(dx, dz)
        end
        self:hero_attack(hero, dt)
    else
        local kite_speed = hero.kite_speed * (1.0 + 0.25 * (hero.dash or 0))
        local kite_distance = self.hero_spec.kite_distance + 1.2 * (hero.dash or 0)
        local low = hero.hp <= hero.hp_max * self.hero_spec.kite_threshold
        if target then
            local dx, dz = target.x - hero.x, target.z - hero.z
            local d = tdist > 0.001 and tdist or 1.0
            if low and tdist < kite_distance then
                local cx, cz = self:swarm_centroid()
                if cx then
                    local ax, az = hero.x - cx, hero.z - cz
                    local an = math.sqrt(ax * ax + az * az)
                    if an > 0.001 then self:move_hero(hero, ax / an, az / an, kite_speed, dt) end
                end
            elseif tdist > hero.attack_range * 0.8 then
                self:move_hero(hero, dx / d, dz / d, hero.speed, dt)
            else
                hero.facing = math.atan(dx, dz)
            end
            self:hero_attack(hero, dt)
        end
    end
    self:hero_whirl(hero, dt)

    -- Locomotion + procedural animation (walk gait + an attack flash blend).
    hero.phase = hero.phase + dt * 9.0
    if Art.valid(hero.root) then
        hero.root:set_position(vec3(hero.x, 0.0, hero.z))
        hero.root:set_rotation(vec3(0.0, math.deg(hero.facing), 0.0))
    end
    -- Billboard textured quads toward the iso camera so they aren't edge-on.
    -- The iso camera offset is (-44,44,44) → face toward it: pitch ~35°, yaw −45°.
    -- Parts are children of root (which rotates by hero.facing), so counter-rotate.
    if hero.actor and hero.actor.spec and hero.actor.spec.soft_cape then
        local cam_pitch, cam_yaw = 35.26, -45.0
        local facing_deg = math.deg(hero.facing)
        local local_yaw = cam_yaw - facing_deg
        for _, key in ipairs({ "body", "sword" }) do
            local p = hero.parts[key]
            if Art.valid(p) then p:set_rotation(vec3(cam_pitch, local_yaw, 0.0)) end
        end
    else
        Art.animate(hero.actor, "walk", hero.phase / 9.0)
    end
    Art.animate_soft_cape(hero.actor, self.realtime)
    hero.attack_flash = math.max(hero.attack_flash - dt, 0.0)
    if hero.attack_flash > 0.0 then
        Art.animate(hero.actor, "attack", self.realtime, { weight = math.min(1.0, hero.attack_flash / 0.12) })
    end
    if Art.valid(hero.parts.aura) then
        local rng = hero.attack_range * 2.0
        hero.parts.aura:set_scale(vec3(rng, 0.03, rng))
    end
end

-- ---------------------------------------------------------------------------
-- Spawning
-- ---------------------------------------------------------------------------

function Duel:spawn_interval()
    local s = self.spawn_cfg
    local base = math.max(s.interval_min, s.interval_start - s.interval_ramp * (self.combat_time / 10.0))
    return base * (self.spawn_mods.interval_mult or 1.0)
end

function Duel:batch_size()
    local s = self.spawn_cfg
    return math.min(s.batch_max, s.batch_start + math.floor(self.combat_time / 16.0)) + (self.spawn_mods.batch_add or 0)
end

function Duel:live_cap()
    local s = self.spawn_cfg
    return math.min(s.cap_max, s.cap_start + math.floor(self.combat_time / 8.0) * 4) + (self.spawn_mods.cap_add or 0)
end

function Duel:count_alive()
    local n = 0
    for _, c in ipairs(self.creeps) do if c.alive then n = n + 1 end end
    return n
end

function Duel:minimum_spawn_cost()
    local min_cost = nil
    for _, role in ipairs({ "swarm", "ranged", "elite", "brute" }) do
        local arch = self:role_archetype(role)
        if arch then
            local cost = Creep.threat_cost(arch)
            if cost and (not min_cost or cost < min_cost) then min_cost = cost end
        end
    end
    return min_cost or 1
end

-- Map a role to one of the mode's archetype ids.
function Duel:role_archetype(role)
    return self.roles[role] or self.roles.swarm or Creep.default_archetype
end

-- Which archetype the auto-spawner picks over time. Modes can override with
-- config.auto_mix(duel) -> archetype_id.
function Duel:pick_auto_archetype()
    if self.config.auto_mix then return self.config.auto_mix(self) end
    if self.combat_time >= self.spawn_cfg.brute_after and (self.spawn_counter % 9 == 0) then
        return self:role_archetype("brute")
    end
    if self.spawn_counter % 5 == 0 and self.roles.ranged then return self:role_archetype("ranged") end
    if self.spawn_counter % 3 == 0 and self.roles.elite then return self:role_archetype("elite") end
    return self:role_archetype("swarm")
end

function Duel:pick_affordable_auto_archetype()
    local reserve = self.reserve or 0.0
    local picked = self:pick_auto_archetype()
    if picked and Creep.threat_cost(picked) <= reserve then return picked end
    for _, role in ipairs({ "swarm", "ranged", "elite", "brute" }) do
        local arch = self:role_archetype(role)
        if arch and Creep.threat_cost(arch) <= reserve then return arch end
    end
    return picked
end

-- Spawn one creep. `free` skips the reserve cost (a card already paid it).
function Duel:spawn_one(spawn, arch, free)
    arch = arch or (self.manual_hero and self:pick_affordable_auto_archetype() or self:pick_auto_archetype())
    local cost = Creep.threat_cost(arch)
    if not free then
        if self.reserve < cost then return nil end
        self.reserve = self.reserve - cost
    end
    self.spawn_counter = self.spawn_counter + 1
    self.next_id = self.next_id + 1
    local jx = (self.spawn_counter % 5 - 2) * 0.3
    local jz = (self.spawn_counter % 7 - 3) * 0.3
    local creep = Creep.create({
        id = self.next_id, archetype = arch,
        x = spawn.x + jx, z = spawn.y + jz,
        parent = self.groups.actors,
        -- POOLING IS LOAD-BEARING: deleting rig nodes mid-combat (a no_pool
        -- experiment) shuffles node storage via swap-and-pop and leaves mesh
        -- draw-constants pointing at OTHER nodes' world matrices — sprites
        -- then render with arbitrary (often giant) transforms. Park & reuse.
        mods = { speed_add = self.buffs.speed, dps_add = self.buffs.power, hp_add = self.buffs.hp },
    })
    self:dress_creep(creep)
    self.creeps[#self.creeps + 1] = creep
    if self.config.hooks and self.config.hooks.on_spawn then self.config.hooks.on_spawn(self, creep) end
    return creep
end

function Duel:enqueue_spawn(count, arch, free)
    local n = math.max(0, math.floor(tonumber(count) or 0))
    if n <= 0 then return end
    self.spawn_queue = self.spawn_queue or {}
    for _ = 1, n do
        self.spawn_queue[#self.spawn_queue + 1] = { arch = arch, free = free == true }
    end
end

function Duel:drain_spawn_queue(per_frame)
    local q = self.spawn_queue
    if not q or #q == 0 then return end

    local n = math.min(math.max(1, math.floor(tonumber(per_frame) or 1)), #q)
    for _ = 1, n do
        if self:count_alive() >= self:live_cap() then return end

        local req = table.remove(q, 1)
        local spawn = self.spawns[(self.spawn_counter % #self.spawns) + 1]
        self:spawn_one(spawn, req.arch, req.free)
    end
end

function Duel:spawn_batch(count)
    self:enqueue_spawn(count, nil, false)
end

function Duel:update_spawning(dt)
    if self.manual_hero and (self.reserve or 0.0) < self:minimum_spawn_cost() then
        self.spawn_queue = {}
        return
    end
    self.spawn_t = self.spawn_t - dt
    if self.spawn_t <= 0.0 then
        self.spawn_t = self:spawn_interval()
        self:spawn_batch(self:batch_size())
    end
end

-- Apply the per-archetype VISUAL dressing on top of a freshly built or reused
-- rig: self-light glow (so it reads on the dark stage), the mode's signature
-- extras/texture, and the iso-read world scale. Glow and scale are cheap and
-- constant per archetype, so they run every spawn; the extras ADD nodes, so
-- they only run for a fresh rig — a reused rig already carries them from when it
-- was first built (see Creep pooling + creep.fresh_rig in duel_creep).
function Duel:dress_creep(creep)
    local s = creep.stats or {}
    local function glow(node, color)
        if Art.valid(node) and color then
            material.set(node, "emissive", vec3(color[1] * 0.85, color[2] * 0.85, color[3] * 0.85))
        end
    end
    glow(creep.parts and creep.parts.body, s.color)
    glow(creep.parts and creep.parts.head, s.head or s.color)
    glow(creep.parts and creep.parts.weapon, s.weapon)
    local arch_def = (self.config.archetypes or {})[creep.archetype]
    if creep.fresh_rig then
        if arch_def and arch_def.extras then Art.decorate(creep.root, arch_def.extras) end
        if arch_def and arch_def.texture then Art.texture(creep.parts and creep.parts.body, arch_def.texture) end
    end
    -- World character scale: re-derive the archetype's intended scale and grow it
    -- so the swarm reads at the iso distance (gameplay radii are unaffected).
    if Art.valid(creep.root) then
        local cbase = (arch_def and arch_def.scale) or 1.0
        local cw = cbase * Art.s("char")
        creep.root:set_scale(vec3(cw, cw, cw))
    end
end

function Duel:warm_archetype(arch, count)
    if not arch then return end
    local n = math.max(0, math.floor(tonumber(count) or 0))
    for _ = 1, n do
        self.next_id = self.next_id + 1
        local creep = Creep.create({
            id = self.next_id, archetype = arch,
            x = self.arena.hero_start.x, z = self.arena.hero_start.y,
            parent = self.groups.actors, no_pool = true,
        })
        self:dress_creep(creep)
        if self.config.hooks and self.config.hooks.on_prewarm_spawn then
            self.config.hooks.on_prewarm_spawn(self, creep)
        end
        Creep.destroy(creep)
    end
end

function Duel:warm_creep_pool()
    local target = self.config.warm_pool_count
    if target == nil then target = math.min(self.spawn_cfg.cap_start or 28, 28) end
    target = ATH_COMMON.getenv_number("ATH_DUEL_WARM_POOL", target)
    target = math.max(0, math.floor(tonumber(target) or 0))
    if target <= 0 then return end

    local counts = {}
    local function add(role, count)
        local arch = self:role_archetype(role)
        if not arch then return end
        counts[arch] = (counts[arch] or 0) + math.max(0, math.floor(count or 0))
    end

    local swarm = math.max(1, math.floor(target * 0.64))
    local ranged = math.max(1, math.floor(target * 0.18))
    local elite = math.max(1, math.floor(target * 0.14))
    local brute = math.max(1, target - (swarm + ranged + elite))
    add("swarm", swarm)
    add("ranged", ranged)
    add("elite", elite)
    add("brute", brute)

    local built = 0
    for arch, count in pairs(counts) do
        if built >= target then break end
        local n = math.min(count, target - built)
        self:warm_archetype(arch, n)
        built = built + n
    end
    self:log(string.format("warm_pool rigs=%d target=%d", built, target))
end

-- ---------------------------------------------------------------------------
-- Creeps + combat
-- ---------------------------------------------------------------------------

function Duel:update_field(dt)
    local hero = self.hero
    local tx = math.floor((hero.x or 0.0) + 0.5)
    local ty = math.floor((hero.z or 0.0) + 0.5)
    -- The flow field only depends on the hero's tile over a static map, so it is
    -- valid until the hero crosses into a new tile. Standing still costs nothing;
    -- the old code rebuilt the whole grid on a fixed 0.35s timer regardless.
    if self.field and tx == self.field_tx and ty == self.field_ty then
        return
    end
    self.field_tx = tx
    self.field_ty = ty
    self.field = Flow.compute(self.map, { x = tx, y = ty }, self.field)
    self.field.sample = Flow.sample
end

function Duel:update_creeps(dt)
    local hero = self.hero
    local kill_fx_budget = self.config.kill_fx_budget_per_frame
    local kill_fx_used = 0
    local survivors = {}
    local incoming = 0.0
    local contact = false
    local contacters = {}
    for _, c in ipairs(self.creeps) do
        if c.alive then Creep.update(c, dt, self.field, self.map, hero) end
        if c.alive and not hero.dead then
            local dx, dz = hero.x - c.x, hero.z - c.z
            local d = math.sqrt(dx * dx + dz * dz)
            if d <= hero.body_radius + (c.stats.range or 0.5) then
                incoming = incoming + (c.stats.dps or 1.0)
                contact = true
                contacters[#contacters + 1] = c
            end
        end
        if c.alive then
            survivors[#survivors + 1] = c
        else
            if kill_fx_budget == nil or kill_fx_used < kill_fx_budget then
                Art.burst("ath_duel_kill_" .. tostring(c.id), vec3(c.x, 0.6, c.z),
                    { preset = "enemy_take", count = 12, life_max = 0.22, spawn_radius = 0.18 })
                kill_fx_used = kill_fx_used + 1
            end
            Creep.destroy(c)
            self.kills = self.kills + 1
            self:maybe_drop_manual_gear(c)
        end
    end
    self.creeps = survivors

    if incoming > 0.0 and not hero.dead then
        -- DIAG: name every damage source once a second so "damage out of
        -- nowhere" is attributable (creep, distance, its contact reach).
        self._dmg_log_t = (self._dmg_log_t or 0.0) - dt
        if pe_log and self._dmg_log_t <= 0.0 then
            self._dmg_log_t = 1.0
            local parts = {}
            for _, c in ipairs(contacters) do
                local dx, dz = hero.x - c.x, hero.z - c.z
                parts[#parts + 1] = string.format("%s d=%.2f reach=%.2f+%.2f",
                    tostring(c.archetype), math.sqrt(dx * dx + dz * dz),
                    hero.body_radius or 0, (c.stats and c.stats.range) or 0)
            end
            pe_log("[DMG] hero takes " .. string.format("%.1f", incoming) .. " dps from: " .. table.concat(parts, " | "))
        end
        self:apply_hero_damage(incoming * dt) -- armor is applied inside
        -- Thorns: reflect to the creeps actually in contact.
        if (hero.thorns or 0.0) > 0.0 then
            for _, c in ipairs(contacters) do
                if Creep.damage(c, hero.thorns * dt) then c.alive = false end
            end
        end
        self.hit_fx_t = (self.hit_fx_t or 0.0) - dt
        if contact and self.hit_fx_t <= 0.0 then
            self.hit_fx_t = 0.12
            Art.burst("ath_duel_herohit", vec3(hero.x, 0.9, hero.z),
                { preset = "hero_take", count = 8, life_max = 0.16, spawn_radius = 0.12, noise_strength = 2.4, size_max = 0.12 })
        end
    end
end

-- Deal damage to the hero from ANY source (swarm contact OR a mode's signature
-- hazard) with one centralised death path. opts.ignore_armor bypasses mitigation.
-- This is the API modes use for environmental damage (lava, poison, storms).
function Duel:apply_hero_damage(amount, opts)
    local hero = self.hero
    if not hero or hero.dead or (amount or 0.0) <= 0.0 then return end
    opts = opts or {}
    local mitig = opts.ignore_armor and 1.0 or (1.0 - clampn(hero.armor or 0.0, -0.5, 0.85))
    hero.hp = hero.hp - amount * mitig
    if hero.hp <= 0.0 then
        hero.hp = 0.0
        hero.dead = true
        self.state = "slain"
        self.slowmo_t = SLOWMO_DURATION
        self:set_flash(opts.flash or "HERO SLAIN")
        self:log(string.format("HERO SLAIN round=%d kills=%d reserve=%.0f", self.round, self.kills, self.reserve))
    end
end

-- ---------------------------------------------------------------------------
-- Card effect application
-- ---------------------------------------------------------------------------

function Duel:apply_front(e)
    local hero = self.hero
    if not e then return end
    if e.dps_mult then hero.dps = hero.dps * e.dps_mult end
    if e.dps_add then hero.dps = hero.dps + e.dps_add end
    if e.cleave_add then hero.cleave = hero.cleave + e.cleave_add end
    if e.attack_range_add then hero.attack_range = hero.attack_range + e.attack_range_add end
    if e.speed_mult then hero.speed = hero.speed * e.speed_mult end
    if e.kite_speed_mult then hero.kite_speed = hero.kite_speed * e.kite_speed_mult end
    if e.hp_max_add then hero.hp_max = hero.hp_max + e.hp_max_add end
    if e.heal then hero.hp = math.min(hero.hp_max, hero.hp + e.heal) end
    if e.lifesteal_add then hero.lifesteal = (hero.lifesteal or 0.0) + e.lifesteal_add end
    if e.regen_add then hero.regen = (hero.regen or 0.0) + e.regen_add end
    if e.whirl_add then hero.whirl = (hero.whirl or 0) + e.whirl_add end
    if e.armor_add then hero.armor = clampn((hero.armor or 0.0) + e.armor_add, -0.5, 0.85) end
    if e.thorns_add then hero.thorns = (hero.thorns or 0.0) + e.thorns_add end
    if e.dash_add then hero.dash = (hero.dash or 0) + e.dash_add end
    if e.crit_add then hero.dps = hero.dps * (1.0 + 0.5 * e.crit_add) end -- crit modelled as expected dps
end

function Duel:apply_back(e)
    if not e then return false, "No effect." end
    if e.kind == "swarm" then
        self.buffs.speed = self.buffs.speed + (e.speed_add or 0.0)
        self.buffs.power = self.buffs.power + (e.dps_add or 0.0)
        self.buffs.hp = self.buffs.hp + (e.hp_add or 0.0)
        for _, c in ipairs(self.creeps) do
            if c.alive and c.stats then
                c.stats.speed = math.max(0.2, (c.stats.speed or 1.0) + (e.speed_add or 0.0))
                c.stats.dps = math.max(0.0, (c.stats.dps or 1.0) + (e.dps_add or 0.0))
                -- hp_add is advertised as "future + current spawns": raise the live
                -- creep's current and max HP so "+X HP" actually hardens the wave.
                if (e.hp_add or 0.0) ~= 0.0 then
                    c.hp_max = (c.hp_max or c.hp or 1.0) + e.hp_add
                    c.hp = math.max(1.0, (c.hp or 0.0) + e.hp_add)
                    if c.stats.hp then c.stats.hp = c.stats.hp + e.hp_add end
                end
            end
        end
        return true, "Swarm strengthened."
    elseif e.kind == "weaken" then
        local hero = self.hero
        if e.dps_mult then hero.dps = math.max(6.0, hero.dps * e.dps_mult) end
        if e.speed_mult then hero.speed = math.max(0.9, hero.speed * e.speed_mult) end
        if e.kite_speed_mult then hero.kite_speed = math.max(1.1, hero.kite_speed * e.kite_speed_mult) end
        if e.attack_range_add then hero.attack_range = math.max(0.6, hero.attack_range + e.attack_range_add) end
        return true, "Hero weakened."
    elseif e.kind == "spawn" then
        local cost = e.reserve_cost or 0
        if self.reserve < cost then return false, "Not enough reserve." end
        self.reserve = self.reserve - cost
        local arch = self:role_archetype(e.role or "swarm")
        self:enqueue_spawn(e.count or 1, arch, true)
        return true, "Summoned " .. tostring(e.count or 1) .. " " .. tostring(e.role or "swarm") .. "."
    elseif e.kind == "escalate" then
        self.spawn_mods.batch_add = (self.spawn_mods.batch_add or 0) + (e.batch_add or 0)
        self.spawn_mods.cap_add = (self.spawn_mods.cap_add or 0) + (e.cap_add or 0)
        if e.interval_mult then self.spawn_mods.interval_mult = (self.spawn_mods.interval_mult or 1.0) * e.interval_mult end
        return true, "Spawn cadence escalated."
    elseif e.kind == "reserve" then
        self.reserve = self.reserve + (e.reserve_add or 0.0)
        return true, "Reserve replenished."
    end
    return false, "Unknown effect."
end

-- Apply whichever face the seat plays, fire the mode hook, return ok, message.
function Duel:resolve_card(seat, card_id, effect)
    local ok, msg
    if seat.side == "hero" then
        self:apply_front(effect)
        ok, msg = true, (select(2, Cards.face(card_id, "hero")))
    else
        ok, msg = self:apply_back(effect)
    end
    if ok and self.config.hooks and self.config.hooks.on_card then
        self.config.hooks.on_card(self, seat.side, card_id, effect)
    end
    return ok, msg
end

-- ---------------------------------------------------------------------------
-- Manual-hero wave and gear path
-- ---------------------------------------------------------------------------

function Duel:manual_wave_budget(index)
    local budgets = self.wave_cfg and self.wave_cfg.budgets
    if budgets and budgets[index] then return budgets[index] end
    local base = (self.wave_cfg and self.wave_cfg.reserve_start) or self.reserve_start or 300.0
    local add = (self.wave_cfg and self.wave_cfg.reserve_add) or 40.0
    return base + (math.max(1, index or 1) - 1) * add
end

function Duel:begin_manual_wave(index)
    self.wave_index = math.max(1, math.floor(index or 1))
    self.round = self.wave_index
    self.reserve_start = self:manual_wave_budget(self.wave_index)
    self.reserve = self.reserve_start
    self.round_t = 0.0
    self.spawn_t = 0.35
    self.spawn_queue = {}
    self.state = "combat"
    self:set_flash("WAVE " .. tostring(self.wave_index))
    self:log(string.format("wave start wave=%d budget=%.0f", self.wave_index, self.reserve_start))
end

function Duel:manual_wave_done()
    return (self.reserve or 0.0) < self:minimum_spawn_cost()
        and (not self.spawn_queue or #self.spawn_queue == 0)
        and self:count_alive() == 0
end

function Duel:manual_item_owned(item_id)
    if not item_id then return false end
    for _, item in pairs(self.gear_equipped or {}) do
        if item and item.id == item_id then return true end
    end
    for _, item in ipairs(self.gear_inventory or {}) do
        if item and item.id == item_id then return true end
    end
    return false
end

function Duel:maybe_drop_manual_gear(_creep)
    if not self.manual_hero then return end
    self.gold = (self.gold or 0) + (self.gear_cfg.gold_per_kill or 1)

    local items = self.gear_cfg.items or {}
    local every = math.max(1, math.floor(self.gear_cfg.drop_every or 6))
    if #items == 0 or (self.kills % every) ~= 0 then return end

    local start = (self.gear_drop_cursor or 0)
    for offset = 1, #items do
        local index = ((start + offset - 1) % #items) + 1
        local item = items[index]
        if item and not self:manual_item_owned(item.id) then
            self.gear_drop_cursor = index
            self.gear_inventory[#self.gear_inventory + 1] = item
            self:set_flash("Found " .. tostring(item.name or item.id))
            return
        end
    end
end

local function apply_gear_effect(hero, effect)
    if not effect then return end
    if effect.dps_mult then hero.dps = hero.dps * effect.dps_mult end
    if effect.dps_add then hero.dps = hero.dps + effect.dps_add end
    if effect.cleave_add then hero.cleave = hero.cleave + effect.cleave_add end
    if effect.attack_range_add then hero.attack_range = hero.attack_range + effect.attack_range_add end
    if effect.speed_mult then hero.speed = hero.speed * effect.speed_mult end
    if effect.kite_speed_mult then hero.kite_speed = hero.kite_speed * effect.kite_speed_mult end
    if effect.hp_max_add then hero.hp_max = hero.hp_max + effect.hp_max_add end
    if effect.armor_add then hero.armor = clampn((hero.armor or 0.0) + effect.armor_add, -0.5, 0.85) end
    if effect.lifesteal_add then hero.lifesteal = (hero.lifesteal or 0.0) + effect.lifesteal_add end
    if effect.regen_add then hero.regen = (hero.regen or 0.0) + effect.regen_add end
    if effect.whirl_add then hero.whirl = (hero.whirl or 0) + effect.whirl_add end
    if effect.thorns_add then hero.thorns = (hero.thorns or 0.0) + effect.thorns_add end
    if effect.dash_add then hero.dash = (hero.dash or 0) + effect.dash_add end
end

function Duel:recompute_hero_stats()
    local hero = self.hero
    if not hero then return end
    local base = hero.base_stats or {}
    local old_hp = hero.hp or base.hp_max or 1.0
    local old_max = hero.hp_max or base.hp_max or 1.0

    hero.hp_max = base.hp_max or hero.hp_max or 1.0
    hero.dps = base.dps or hero.dps or 1.0
    hero.cleave = base.cleave or hero.cleave or 1
    hero.attack_range = base.attack_range or hero.attack_range or 1.0
    hero.speed = base.speed or hero.speed or 1.0
    hero.kite_speed = base.kite_speed or hero.kite_speed or hero.speed
    hero.armor = base.armor or 0.0
    hero.lifesteal = base.lifesteal or 0.0
    hero.regen = base.regen or 0.0
    hero.whirl = base.whirl or 0
    hero.thorns = base.thorns or 0.0
    hero.dash = base.dash or 0

    for _, slot in ipairs({ "weapon", "armor", "trinket" }) do
        local item = self.gear_equipped and self.gear_equipped[slot]
        if item then apply_gear_effect(hero, item.effect) end
    end

    local delta = hero.hp_max - old_max
    if delta > 0.0 then
        hero.hp = math.min(hero.hp_max, old_hp + delta)
    else
        hero.hp = math.min(old_hp, hero.hp_max)
    end
end

function Duel:reset_manual_gear()
    self.gold = 0
    self.gear_inventory = {}
    self.gear_equipped = { weapon = nil, armor = nil, trinket = nil }
    self.gear_drop_cursor = 0
    self:recompute_hero_stats()
end

function Duel:equip_manual_item(index)
    if not self.manual_hero then return end
    local item = self.gear_inventory and self.gear_inventory[index]
    if not item then return end
    table.remove(self.gear_inventory, index)
    local slot = item.slot or "trinket"
    local old = self.gear_equipped[slot]
    if old then self.gear_inventory[#self.gear_inventory + 1] = old end
    self.gear_equipped[slot] = item
    self:recompute_hero_stats()
    self:set_flash("Equipped " .. tostring(item.name or item.id))
end

-- ---------------------------------------------------------------------------
-- AI seat — the side the player did NOT pick is resolved heuristically.
-- ---------------------------------------------------------------------------

function Duel:swarm_summary()
    local n, sp, dps, tanky = 0, 0.0, 0.0, false
    for _, c in ipairs(self.creeps) do
        if c.alive and c.stats then
            n = n + 1
            sp = sp + (c.stats.speed or 0.0)
            dps = dps + (c.stats.dps or 0.0)
            if (c.stats.hp_max or c.stats.hp or 0) >= 24 then tanky = true end
        end
    end
    local hero = self.hero
    return {
        count = n, avg_speed = n > 0 and sp / n or 0.0, incoming_dps = dps, tanky = tanky,
        hp_pct = hero and (hero.hp / math.max(1.0, hero.hp_max)) or 1.0,
    }
end

-- Score a hero FRONT effect against current pressure (higher = better pick).
function Duel:score_front(e, swarm)
    if not e then return -1 end
    local score = 0.0
    local low = (swarm.hp_pct or 1.0) <= 0.5 or (swarm.incoming_dps or 0.0) >= 14.0
    local crowded = (swarm.count or 0) >= 14
    local outrun = (swarm.avg_speed or 0.0) >= (self.hero.speed or 2.0) + 0.3
    if low then
        score = score + (e.heal or 0) * 0.04 + (e.hp_max_add or 0) * 0.03 + (e.regen_add or 0) * 3.0
            + (e.armor_add or 0) * 30.0 + (e.lifesteal_add or 0) * 4.0
    end
    if crowded then
        score = score + (e.cleave_add or 0) * 6.0 + (e.whirl_add or 0) * 6.0 + (e.attack_range_add or 0) * 8.0
    end
    if outrun then
        score = score + ((e.speed_mult and (e.speed_mult - 1.0) * 30.0) or 0) + (e.dash_add or 0) * 6.0
    end
    -- Always value raw damage as the baseline.
    score = score + ((e.dps_mult and (e.dps_mult - 1.0) * 20.0) or 0) + (e.dps_add or 0) * 1.2
    return score
end

-- Score a horde BACK effect (higher = more useful pressure right now).
function Duel:score_back(e, swarm)
    if not e then return -1 end
    if e.kind == "spawn" then
        if self.reserve < (e.reserve_cost or 0) then return -1 end
        local headroom = self:live_cap() - (swarm.count or 0)
        return 8.0 + math.min(headroom, (e.count or 1)) * 1.5 - (e.reserve_cost or 0) * 0.1
    elseif e.kind == "swarm" then
        return 5.0 + (e.dps_add or 0) * 2.0 + (e.hp_add or 0) * 0.4 + (e.speed_add or 0) * 4.0
    elseif e.kind == "escalate" then
        return 4.0 + (e.batch_add or 0) * 1.5 + (e.cap_add or 0) * 0.2
    elseif e.kind == "weaken" then
        return ((swarm.hp_pct or 1.0) > 0.6) and 6.0 or 2.0
    elseif e.kind == "reserve" then
        return (self.reserve < self.reserve_start * 0.3) and 7.0 or 1.0
    end
    return 0.0
end

-- Resolve the AI seat fully: greedily play the best-scoring affordable card
-- until command runs out or nothing scores positively.
function Duel:resolve_ai_seat(seat)
    local picks = 0
    for _ = 1, 6 do
        local swarm = self:swarm_summary()
        local actions = Cards.legal_actions(seat, true)
        if #actions == 0 then break end
        local best, best_score
        for _, action in ipairs(actions) do
            local e = Cards.face(action.card, seat.side)
            local sc = (seat.side == "hero") and self:score_front(e, swarm) or self:score_back(e, swarm)
            if not best or sc > best_score then best, best_score = action, sc end
        end
        if not best or (best_score or 0) <= 0 then break end
        local card_id = best.card
        local ok, _, effect = Cards.play(seat, best.slot)
        if not ok then break end
        self:resolve_card(seat, card_id, effect)
        picks = picks + 1
        if seat.side == "hero" then
            self.hero.thought = (Cards.card(card_id) and Cards.card(card_id).name or card_id)
        end
    end
    return picks
end

-- ---------------------------------------------------------------------------
-- Human seat input (the side the player picked)
-- ---------------------------------------------------------------------------

function Duel:play_human_card(slot)
    local seat = self.player_seat
    local card_id = seat.hand[slot]
    if not card_id then return end
    -- Pre-check a horde spawn so it never burns command it cannot pay for.
    if seat.side == "horde" then
        local effect = Cards.face(card_id, "horde")
        if effect and effect.kind == "spawn" and self.reserve < (effect.reserve_cost or 0) then
            self:set_flash("Reserve too low")
            return
        end
    end
    local ok, msg, eff = Cards.play(seat, slot)
    if not ok then self:set_flash(msg); return end
    local applied, amsg = self:resolve_card(seat, card_id, eff)
    local name = Cards.card(card_id) and Cards.card(card_id).name or card_id
    self:set_flash(applied and (name .. ": " .. tostring(amsg)) or tostring(amsg))
end

-- ---------------------------------------------------------------------------
-- Round / pause loop
-- ---------------------------------------------------------------------------

function Duel:begin_pause()
    if self.manual_hero then
        self.state = "pause"
        self:set_flash("WAVE " .. tostring(self.wave_index or 1) .. " CLEARED")
        if self.config.hooks and self.config.hooks.on_pause then self.config.hooks.on_pause(self) end
        self:log(string.format("pause wave=%d gold=%d inventory=%d", self.wave_index or 1, self.gold or 0, #(self.gear_inventory or {})))
        return
    end

    self.state = "pause"
    self.round = self.round + 1
    Cards.start_pause(self.player_seat)
    Cards.start_pause(self.ai_seat)
    self:resolve_ai_seat(self.ai_seat) -- the AI side commits immediately
    self:set_flash("ROUND " .. tostring(self.round) .. " — your move")
    if self.config.hooks and self.config.hooks.on_pause then self.config.hooks.on_pause(self) end
    self:log(string.format("pause round=%d reserve=%.0f swarm=%d", self.round, self.reserve, self:count_alive()))
end

function Duel:resume_combat()
    if self.manual_hero then
        self:begin_manual_wave((self.wave_index or 1) + 1)
        if self.config.hooks and self.config.hooks.on_resume then self.config.hooks.on_resume(self) end
        return
    end

    self.state = "combat"
    self.round_t = self.round_seconds
    self.spawn_t = math.min(self.spawn_t or 0.4, 0.4)
    self:set_flash("FIGHT")
    if self.config.hooks and self.config.hooks.on_resume then self.config.hooks.on_resume(self) end
end

function Duel:reset_run()
    for _, c in ipairs(self.creeps) do Creep.destroy(c) end
    self.creeps = {}
    -- Drop parked rigs before the hero (their scene sibling under the actors
    -- group) is deleted+rebuilt: the swap-and-pop on that delete would stale
    -- their handles. New rigs are built only as the spawn queue drains.
    Creep.clear_pool()
    if Art.valid(self.hero and self.hero.root) then scene.delete_node(self.hero.root) end
    self:create_hero()
    self.combat_time = 0.0
    self.round = 1
    self.round_t = self.round_seconds
    self.spawn_t = 0.6
    self.spawn_counter = 0
    self.spawn_queue = {}
    self.kills = 0
    self.reserve = self.reserve_start
    self.buffs = { speed = 0.0, power = 0.0, hp = 0.0 }
    self.spawn_mods = { batch_add = 0, cap_add = 0, interval_mult = 1.0 }
    self.slowmo_t = 0.0
    self.field = nil
    self.field_t = 0.0
    if self.manual_hero then
        self.player_seat = nil
        self.ai_seat = nil
        self:reset_manual_gear()
        self:begin_manual_wave(1)
    else
        self.state = "combat"
        self.player_seat = Cards.create({ side = self.side, deck = self.ctx.deck })
        self.ai_seat = Cards.create({ side = (self.side == "hero") and "horde" or "hero", deck = Cards.default_deck })
        self:set_flash("FIGHT")
    end
    if self.config.hooks and self.config.hooks.on_reset then self.config.hooks.on_reset(self) end
    if self.mode_started then self:warm_creep_pool() end
    self:log("run reset side=" .. self.side)
end

function Duel:update_input(dt)
    if self:key_pressed("R") then self:reset_run(); return end
    if self:key_pressed("Escape") or self:key_pressed("M") then
        if self.shell and self.shell.return_to_menu then self.shell.return_to_menu() end
        return
    end

    if self.state == "pause" then
        if self.manual_hero then
            for slot = 1, 5 do
                if self:key_pressed(tostring(slot)) or Art.consume_click(self.hud, "gear_inv_slot" .. slot) then
                    self:equip_manual_item(slot)
                end
            end
            if self:key_pressed("Return") or self:key_pressed("Space") or Art.consume_click(self.hud, "resume_btn") then
                self:resume_combat()
            end
            return
        end

        for slot = 1, 5 do
            if self:key_pressed(tostring(slot)) then self:play_human_card(slot) end
            if Art.consume_click(self.hud, "card_slot" .. slot) then self:play_human_card(slot) end
        end
        if self:key_pressed("Return") or self:key_pressed("Space") or Art.consume_click(self.hud, "resume_btn") then
            self:resume_combat()
        end
        if self.autoplay then
            self.autoplay_t = (self.autoplay_t or 0.0) - dt
            if self.autoplay_t <= 0.0 then
                self.autoplay_t = 0.5
                if Cards.can_play(self.player_seat) then
                    self:resolve_ai_seat(self.player_seat)
                else
                    self:resume_combat()
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- HUD
-- ---------------------------------------------------------------------------

function Duel:hand_lines()
    local seat = self.player_seat
    local lines = {}
    for _, action in ipairs(Cards.legal_actions(seat, false)) do
        local mark = action.affordable and " " or "x"
        lines[#lines + 1] = string.format("[%d]%s %s (%d) — %s", action.slot, mark, action.label, action.cost, action.desc)
    end
    if #lines == 0 then lines[1] = "(hand empty)" end
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("Command %d/%d     [Enter] resume", seat.command, seat.command_max)
    return table.concat(lines, "\n")
end

function Duel:update_hud()
    if not (runtime_ui and runtime_ui.set_quad) then return end
    local sw, sh = Art.surface_size()
    local hero = self.hero
    local accent = self.theme.accent or { 0.62, 0.34, 0.86, 0.95 }
    -- Every HUD dimension/offset multiplies by S() so panels grow with the text.
    local function S(v) return v * Art.s("hud") end

    -- Hero HP bar (top center).
    local bw, bh = S(520.0), S(36.0)
    local bx, by = sw * 0.5 - bw * 0.5, S(28.0)
    local pct = clampn((hero.hp or 0.0) / (hero.hp_max or 1.0), 0.0, 1.0)
    local hp_color = pct > 0.5 and { 0.36, 0.78, 0.42, 0.95 } or (pct > 0.25 and { 0.92, 0.74, 0.28, 0.95 } or { 0.90, 0.30, 0.26, 0.95 })
    Art.bar(self.hud, "hp", bx, by, bw, bh, pct, hp_color, { label = string.format("HERO  %d / %d", math.floor(hero.hp + 0.5), math.floor(hero.hp_max + 0.5)) })

    -- Top-left status — ONE compact multi-line label. Drawn from the top edge, so
    -- the frame hugs the text (the title/body layout reserves a tall empty "art"
    -- band up top). Sized to the text scale; font bumped for legibility.
    local side_label = (self.side == "hero") and "YOU: HERO" or "YOU: HORDE"
    local TS = Art.s("text")
    local status_text
    if self.manual_hero then
        status_text = string.format("%s\nYOU: HERO  -  Wave %d/%d\nBudget %d / %d\nSwarm %d    Kills %d\nGold %d",
            (self.theme.hud_title or (self.config.name or "DUEL")), self.wave_index or 1, self.wave_cfg.count or 5,
            math.floor((self.reserve or 0.0) + 0.5), math.floor((self.reserve_start or 1.0) + 0.5),
            self:count_alive(), self.kills, self.gold or 0)
    else
        status_text = string.format("%s\n%s  -  Round %d\nReserve %d / %d\nSwarm %d    Kills %d\nHero: %s",
            (self.theme.hud_title or (self.config.name or "DUEL")), side_label, self.round,
            math.floor(self.reserve + 0.5), math.floor(self.reserve_start),
            self:count_alive(), self.kills, (hero.thought ~= "" and hero.thought or "-"))
    end
    Art.quad(self.hud, "stat", S(20.0), S(20.0), 200.0 * TS, 112.0 * TS, { 0.04, 0.04, 0.06, 0.88 }, {
        border = accent, font_scale = 1.25, text_color = { 0.95, 0.96, 1.0, 1.0 }, no_input = true,
        label = status_text,
    })

    -- Horde Reserve bar (bottom-right — modes draw their own readout bottom-left).
    local dw = S(440.0)
    local dx, dy = sw - dw - S(24.0), sh - S(58.0)
    Art.bar(self.hud, "reserve", dx, dy, dw, S(32.0), clampn(self.reserve / self.reserve_start, 0.0, 1.0),
        { 0.86, 0.34, 0.30, 0.95 },
        { label = string.format("%s %d / %d", self.manual_hero and "WAVE BUDGET" or "HORDE RESERVE",
            math.floor(self.reserve + 0.5), math.floor(self.reserve_start)) })

    if self.flash and self.flash ~= "" then
        Art.quad(self.hud, "flash", sw * 0.5 - S(260.0), S(96.0), S(520.0), S(34.0), { 0.0, 0.0, 0.0, 0.0 },
            { label = self.flash, text_color = { 0.95, 0.82, 0.35, math.min(1.0, self.flash_t) } })
    else
        Art.remove(self.hud, "flash")
    end

    -- Pause overlay: card hand for legacy modes, loot/equip for manual hero.
    -- Laid out bottom-up so the panel, row, and resume button never overlap.
    if self.state == "pause" then
        local card_w, card_h, gap = S(150.0), S(196.0), S(10.0)
        local row_w = 5 * (card_w + gap) - gap
        local start_x = sw * 0.5 - row_w * 0.5
        local resume_h = S(42.0)
        local resume_y = sh - S(16.0) - resume_h
        local card_y = resume_y - gap - card_h
        local panel_h = S(42.0)
        local panel_y = card_y - gap - panel_h

        if self.manual_hero then
            Art.remove_ids(self.hud, { "card_slot1", "card_slot2", "card_slot3", "card_slot4", "card_slot5" })
            local equipped = self.gear_equipped or {}
            local function eq(slot)
                local item = equipped[slot]
                return item and (item.name or item.id) or "-"
            end
            Art.quad(self.hud, "pause_panel", start_x, panel_y, row_w, panel_h, { 0.06, 0.05, 0.10, 0.92 },
                { border = accent, title = string.format("WAVE %d CLEARED - EQUIP LOOT", self.wave_index or 1), no_input = true })
            Art.quad(self.hud, "gear_equipped", start_x, panel_y - S(98.0), row_w, S(86.0), { 0.05, 0.07, 0.08, 0.90 }, {
                border = { 0.45, 0.70, 0.62, 0.9 }, no_input = true,
                label = string.format("Weapon: %s     Armor: %s     Trinket: %s     Gold: %d",
                    eq("weapon"), eq("armor"), eq("trinket"), self.gold or 0),
            })

            for slot = 1, 5 do
                local id = "gear_inv_slot" .. slot
                local item = self.gear_inventory and self.gear_inventory[slot]
                if item then
                    Art.quad(self.hud, id, start_x + (slot - 1) * (card_w + gap), card_y, card_w, card_h,
                        { 0.08, 0.12, 0.13, 0.95 }, {
                        border = { 0.42, 0.86, 0.68, 0.95 },
                        title = item.name or item.id,
                        subtitle = string.upper(item.slot or "trinket"),
                        body = item.desc or "",
                        footer = "[" .. slot .. "] / click",
                    })
                else
                    Art.remove(self.hud, id)
                end
            end
            Art.quad(self.hud, "resume_btn", sw * 0.5 - S(100.0), resume_y, S(200.0), resume_h, { 0.10, 0.16, 0.10, 0.95 },
                { border = { 0.4, 0.9, 0.5, 0.95 }, label = "NEXT WAVE   [Enter]" })
        else
            Art.remove_ids(self.hud, { "gear_equipped", "gear_inv_slot1", "gear_inv_slot2", "gear_inv_slot3", "gear_inv_slot4", "gear_inv_slot5" })
            local seat = self.player_seat
            local who = (seat.side == "hero") and "UPGRADE THE HERO" or "COMMAND THE HORDE"
            local actions = Cards.legal_actions(seat, false)
            Art.quad(self.hud, "pause_panel", start_x, panel_y, row_w, panel_h, { 0.06, 0.05, 0.10, 0.92 },
                { border = accent, title = string.format("PAUSE - Round %d - %s", self.round, who), no_input = true })
            for slot = 1, 5 do
                local id = "card_slot" .. slot
                local action = actions[slot]
                if action then
                    local rar = Cards.rarity(action.card)
                    local fill = action.affordable and { 0.10, 0.10, 0.16, 0.95 } or { 0.06, 0.05, 0.06, 0.9 }
                    Art.quad(self.hud, id, start_x + (slot - 1) * (card_w + gap), card_y, card_w, card_h, fill, {
                        border = rar.color,
                        title = action.label,
                        subtitle = string.format("Cost %d  %s%s", action.cost, string.rep("*", rar.stars), action.affordable and "" or "  (locked)"),
                        body = action.desc,
                        footer = "[" .. slot .. "] / click",
                    })
                else
                    Art.remove(self.hud, id)
                end
            end
            Art.quad(self.hud, "resume_btn", sw * 0.5 - S(100.0), resume_y, S(200.0), resume_h, { 0.10, 0.16, 0.10, 0.95 },
                { border = { 0.4, 0.9, 0.5, 0.95 }, label = "RESUME   [Enter]" })
        end
    else
        Art.remove_ids(self.hud, { "pause_panel", "resume_btn", "card_slot1", "card_slot2", "card_slot3", "card_slot4", "card_slot5" })
        Art.remove_ids(self.hud, { "gear_equipped", "gear_inv_slot1", "gear_inv_slot2", "gear_inv_slot3", "gear_inv_slot4", "gear_inv_slot5" })
    end

    -- Terminal banners.
    local player_won = (self.side == "hero" and self.state == "hero_win") or (self.side == "horde" and self.state == "slain")
    if self.state == "slain" or self.state == "hero_win" then
        local title, body
        if self.state == "slain" then
            title = (player_won and "VICTORY — the hero falls" or "DEFEAT — the hero falls")
            body = self.theme.lose_text or "The hero is slain.\nPress R to run it back  •  M for menu"
            if self.side == "horde" then body = self.theme.win_text or body end
            if self.manual_hero then
                title = "DEFEAT - the swarm takes you"
                body = self.theme.lose_text or "You fell before wave " .. tostring(self.wave_index or 1) .. ".\nPress R to run it back"
            end
        else
            if self.manual_hero then
                title = "VICTORY - five waves cleared"
                body = self.theme.win_text or "The arena is quiet for now.\nPress R to run it back"
            else
                title = (player_won and "VICTORY — the pit ran dry" or "DEFEAT — the hero prevails")
                body = "The reserve is spent and the field is clear.\nPress R to run it back   -   M for menu"
            end
        end
        local col = player_won and { 0.10, 0.18, 0.10, 0.92 } or { 0.18, 0.06, 0.06, 0.92 }
        local bord = player_won and { 0.4, 0.95, 0.5, 0.95 } or { 0.95, 0.4, 0.36, 0.95 }
        Art.quad(self.hud, "end", sw * 0.5 - S(300.0), S(380.0), S(600.0), S(120.0), col, { border = bord, title = title, body = body, no_input = true })
    else
        Art.remove(self.hud, "end")
    end

    if self.config.hooks and self.config.hooks.draw_hud then self.config.hooks.draw_hud(self) end
    Console.draw(self)
end

-- ---------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------

function Duel:update(dt)
    self.realtime = self.realtime + dt
    Console.update(self)
    Art.tick_iso_camera()

    -- DIAG: the rendered view sometimes ends up ~19x more zoomed-in than the
    -- ortho size we set at start. Log the live camera state to catch who/when.
    if pe_log then
        self._cam_log_t = (self._cam_log_t or 0.0) - dt
        if self._cam_log_t <= 0.0 then
            self._cam_log_t = 2.0
            local cam = get_camera and get_camera()
            if cam and cam.get_orthographic_size then
                local p = cam.get_position and cam:get_position()
                local mode = cam.get_projection_mode and cam:get_projection_mode() or "?"
                local fov = cam.get_fov and cam:get_fov() or -1
                local n = 0
                if scene and scene.get_cameras then
                    for _ in pairs(scene.get_cameras()) do n = n + 1 end
                end
                -- Measure the REAL view height through the camera's actual
                -- matrix (fields can be right while the matrix is stale):
                -- project two world points 1 unit apart vertically-on-screen
                -- (z axis under the top-down rig) and read the clip-y delta.
                local vh = -1.0
                if cam.get_view_projection and vec4 then
                    local ok, h = pcall(function()
                        local vp = cam:get_view_projection()
                        local a = vp * vec4(17.5, 0.0, 18.5, 1.0)
                        local b = vp * vec4(17.5, 0.0, 19.5, 1.0)
                        local d = math.abs(b.y / b.w - a.y / a.w)
                        return d > 0.000001 and (2.0 / d) or -2.0
                    end)
                    vh = ok and h or -3.0
                end
                pe_log(string.format("[CAMDIAG] mode=%s ortho=%.2f fov=%.1f cams=%d view_h=%.2f pos=%s,%s,%s",
                    mode, cam:get_orthographic_size(), fov, n, vh,
                    p and string.format("%.1f", p.x) or "?",
                    p and string.format("%.1f", p.y) or "?",
                    p and string.format("%.1f", p.z) or "?"))
            end
        end
    end
    local sim_dt = dt
    if self.slowmo_t > 0.0 then
        self.slowmo_t = self.slowmo_t - dt
        sim_dt = dt * SLOWMO_SCALE
    end

    self:update_input(dt)

    self:drain_spawn_queue(self.config.spawns_per_frame or 1)

    if self.state == "combat" then
        self.combat_time = self.combat_time + sim_dt
        self.round_t = self.round_t - sim_dt
        if self.use_flow_field then self:update_field(sim_dt) end -- else creeps beeline
        self:update_spawning(sim_dt)
        self:update_hero(sim_dt)
        self:update_creeps(sim_dt)
        if self.config.hooks and self.config.hooks.on_combat_tick then self.config.hooks.on_combat_tick(self, sim_dt) end
        if self.manual_hero and self.state == "combat" and self:manual_wave_done() then
            if (self.wave_index or 1) >= (self.wave_cfg.count or 5) then
                self.state = "hero_win"
                self:set_flash("RUN CLEARED")
                self:log(string.format("RUN CLEARED waves=%d kills=%d gold=%d", self.wave_index or 1, self.kills, self.gold or 0))
            else
                self:begin_pause()
            end
        elseif (not self.manual_hero) and self.state == "combat" and self.reserve < 1.0 and self:count_alive() == 0 then
            self.state = "hero_win"
            self:set_flash("HERO PREVAILS")
            self:log(string.format("HERO PREVAILS round=%d kills=%d", self.round, self.kills))
        elseif self.state == "combat" and self.round_t <= 0.0 then
            if not self.manual_hero then self:begin_pause() end
        end
    elseif self.state == "pause" then
        -- Sim frozen; UI + camera keep running.
    else
        self:update_hero(sim_dt)
        self:update_creeps(sim_dt)
    end

    self.flash_t = math.max((self.flash_t or 0.0) - dt, 0.0)
    if self.flash and self.flash ~= self.last_flash then
        self.flash_t = 2.0
        self.last_flash = self.flash
    end
    if self.flash_t <= 0.0 then self.flash = "" end

    self:update_hud()
end

-- ---------------------------------------------------------------------------
-- Lifecycle (driven by the shell)
-- ---------------------------------------------------------------------------

function Duel:start()
    Creep.archetypes = self.config.archetypes or Creep.archetypes
    Creep.default_archetype = self:role_archetype("swarm")
    Creep.aliases = {}

    local seed = ATH_COMMON.getenv_number("ATH_DUEL_SEED", nil)
    if seed then math.randomseed(math.floor(seed)) end

    self.groups = {}
    self.root = Art.group((self.config.id or "duel") .. "_Root", nil)
    self.groups.world = Art.group("Duel_World", self.root)
    self.groups.actors = Art.group("Duel_Actors", self.root)

    if runtime_ui then
        if runtime_ui.set_title then runtime_ui.set_title(self.hud, (self.config.name or "Duel") .. " HUD") end
        if runtime_ui.set_screen_overlay then runtime_ui.set_screen_overlay(self.hud, true) end
        if runtime_ui.show then runtime_ui.show(self.hud) end
    end

    Art.setup_stage()
    self:build_arena()
    Art.setup_iso_camera({ x = self.arena.w * 0.5 - 0.5, z = self.arena.h * 0.5 - 0.5 },
        { ortho_size = self.arena.ortho_size, offset = self.arena.cam_offset })
    self:reset_run()
    if self.config.hooks and self.config.hooks.on_start then self.config.hooks.on_start(self) end
    self.mode_started = true
    self:warm_creep_pool()
    self:log(string.format("start side=%s arena=%dx%d", self.side, self.arena.w, self.arena.h))
end

function Duel:stop()
    for _, c in ipairs(self.creeps or {}) do Creep.destroy(c) end
    self.creeps = {}
    Creep.clear_pool()
    if runtime_ui and runtime_ui.clear then runtime_ui.clear(self.hud) end
    if Art.valid(self.root) then scene.delete_node(self.root) end
end

return Duel
