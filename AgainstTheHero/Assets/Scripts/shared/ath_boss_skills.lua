-- Signature mechanics for the thirteen arena bosses. World-space spell art
-- borrows the Duel's existing pooled telegraph/furrow/orb nodes.

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Anim = ATH_COMMON.load_script("Scripts/shared/ath_sprite_anim.lua", "sprite anim", _ENV)

local Skills = {}
local PARK = vec3(-1000.0, -1000.0, -1000.0)
local TAU = math.pi * 2.0

local STATUS_COLOR = {
    fire = { 1.0, 0.25, 0.04 }, ice = { 0.25, 0.85, 1.0 }, frost = { 0.25, 0.85, 1.0 },
    earth = { 0.85, 0.55, 0.15 }, air = { 0.45, 0.55, 1.0 }, poison = { 0.4, 0.9, 0.25 },
    bleed = { 0.95, 0.12, 0.18 }, curse = { 0.7, 0.25, 0.95 }, shadow = { 0.5, 0.35, 0.9 },
}
local SKILL_COLOR = {
    ground_slam = { 1.0, 0.5, 0.08 }, dive_strafe = { 1.0, 0.22, 0.1 },
    popcorn_weather = { 1.0, 0.32, 0.04 },
    thorn_leash = { 0.35, 0.95, 0.18 }, call_response = { 0.85, 0.18, 0.9 },
    grind_schedule = { 0.65, 0.82, 1.0 }, vanish_pounce = { 1.0, 0.18, 0.08 },
    dinner_bell = { 1.0, 0.65, 0.08 }, gale_shift = { 0.45, 0.85, 1.0 },
    reap_echo = { 0.88, 0.92, 0.72 }, karmic_rosary = { 0.95, 0.62, 0.18 },
    royal_writ = { 0.8, 0.35, 1.0 }, royal_tribute = { 1.0, 0.78, 0.2 },
}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function bounds(D)
    local A = D.arena
    return A.pad + 1.0, A.w - A.pad - 1.0, A.pad + 1.0, A.h - A.pad - 1.0
end

local function period(c, seconds)
    return seconds * (c.boss_phase2 and 0.75 or 1.0)
end

local function due(s, key, dt, first, every)
    if s[key] == nil then s[key] = first end
    s[key] = s[key] - dt
    if s[key] > 0.0 then return false end
    s[key] = every
    return true
end

local function play(D, s, clip, duration)
    Anim.play_oneshot(s.boss, clip, D.realtime, duration or 0.55)
    local color = SKILL_COLOR[s.id] or { 1.0, 0.2, 0.1 }
    Art.burst("ath_boss_cast_core_" .. clip, vec3(s.boss.x, 0.72, s.boss.z),
        { preset = "enemy_take", count = 12, life_min = 0.08, life_max = 0.26,
          spawn_radius = 0.14, noise_strength = 9.0, size_min = 0.05, size_max = 0.15,
          color_start = vec4(1.0, 1.0, 1.0, 1.0),
          color_end = vec4(color[1], color[2], color[3], 0.0) })
    for i = 1, 8 do
        local a = i / 8.0 * TAU + D.realtime * 0.7
        local dx, dz = math.sin(a), math.cos(a)
        Art.burst("ath_boss_cast_ray_" .. clip .. "_" .. i,
            vec3(s.boss.x + dx * 0.65, 0.55, s.boss.z + dz * 0.65),
            { preset = "enemy_give", count = 2, life_min = 0.20, life_max = 0.42,
              spawn_radius = 0.04, noise_strength = 0.6, size_min = 0.035, size_max = 0.09,
              velocity = vec3(dx * 4.2, 1.3, dz * 4.2), drag = 1.2, orientation = "velocity",
              color_start = vec4(color[1], color[2], color[3], 0.95),
              color_end = vec4(color[1], color[2], color[3], 0.0) })
    end
    s.logged = s.logged or {}
    if not s.logged[clip] then
        s.logged[clip] = true
        D:log("boss skill " .. tostring(s.id) .. " clip=" .. clip)
    end
end

local function mote_burst(name, x, z, color, radius, count)
    Art.burst(name, vec3(x, 0.2, z),
        { preset = "enemy_give", count = count or 5, life_min = 0.18, life_max = 0.45,
          spawn_radius = radius or 0.2, noise_strength = 1.2, size_min = 0.035, size_max = 0.10,
          velocity = vec3(0.0, 1.4, 0.0), drag = 1.4,
          color_start = vec4(color[1], color[2], color[3], 0.95),
          color_end = vec4(color[1], color[2], color[3], 0.0) })
end

local function ring_burst(name, x, z, radius, color, points)
    for i = 1, points or 10 do
        local a = i / (points or 10) * TAU
        local dx, dz = math.sin(a), math.cos(a)
        Art.burst(name .. "_" .. i, vec3(x + dx * radius, 0.16, z + dz * radius),
            { preset = "enemy_give", count = 2, life_min = 0.18, life_max = 0.40,
              spawn_radius = 0.035, noise_strength = 0.5, size_min = 0.035, size_max = 0.085,
              velocity = vec3(dx * 1.8, 0.9, dz * 1.8), drag = 1.0, orientation = "velocity",
              color_start = vec4(color[1], color[2], color[3], 0.9),
              color_end = vec4(color[1], color[2], color[3], 0.0) })
    end
end

local function flow_motes(name, x1, z1, x2, z2, color, clock, count)
    local dx, dz = x2 - x1, z2 - z1
    local d = math.max(0.001, math.sqrt(dx * dx + dz * dz))
    for i = 1, count or 6 do
        local t = (i / (count or 6) + clock * 0.35) % 1.0
        Art.burst(name .. "_" .. i, vec3(x1 + dx * t, 0.18, z1 + dz * t),
            { preset = "enemy_give", count = 1, life_min = 0.16, life_max = 0.30,
              spawn_radius = 0.025, noise_strength = 0.3, size_min = 0.035, size_max = 0.075,
              velocity = vec3(dx / d * 3.2, 0.45, dz / d * 3.2), drag = 0.7, orientation = "velocity",
              color_start = vec4(color[1], color[2], color[3], 0.9),
              color_end = vec4(color[1], color[2], color[3], 0.0) })
    end
end

local function break_armor(D, c, seconds)
    c.armor_broken_t = math.max(c.armor_broken_t or 0.0, seconds or 3.5)
    D:set_flash("ARMOR BROKEN")
end

local function release(D, h)
    if not h or h.released then return end
    h.released = true
    if h.pool == "disc" then
        if Art.valid(h.node) then
            h.node:set_position(PARK)
            h.node:set_scale(vec3(2.4, 0.03, 2.4))
        end
        D.tele_pool[#D.tele_pool + 1] = h.node
    elseif h.pool == "bar" then
        if Art.valid(h.node) then h.node:set_position(PARK) end
        D.furrow_pool[#D.furrow_pool + 1] = h.node
    elseif h.pool == "orb" then
        if Art.valid(h.nodes.ring) then h.nodes.ring:set_position(PARK) end
        if Art.valid(h.nodes.core) then h.nodes.core:set_position(PARK) end
        D.furrow_bomb_pool[#D.furrow_bomb_pool + 1] = h.nodes
    end
end

local function remember(s, h)
    if h then s.borrowed[#s.borrowed + 1] = h end
    return h
end

local function take_disc(D, s)
    D:ensure_telegraph_pool()
    local node = D.tele_pool and table.remove(D.tele_pool) or nil
    if not node then return nil end
    return remember(s, { pool = "disc", node = node })
end

local function take_bar(D, s)
    D:ensure_telegraph_pool()
    local node = D.furrow_pool and table.remove(D.furrow_pool) or nil
    if not node then return nil end
    return remember(s, { pool = "bar", node = node })
end

local function take_orb(D, s)
    D:ensure_telegraph_pool()
    local nodes = D.furrow_bomb_pool and table.remove(D.furrow_bomb_pool) or nil
    if not nodes then return nil end
    return remember(s, { pool = "orb", nodes = nodes })
end

local function set_disc(h, x, z, radius, color, alpha)
    if not (h and Art.valid(h.node)) then return end
    h.node:set_position(vec3(x, 0.055, z))
    h.node:set_scale(vec3(radius * 2.0, 0.025, radius * 2.0))
    material.set(h.node, "base_color", vec4(color[1], color[2], color[3], alpha or 0.18))
    material.set(h.node, "emissive", vec3(color[1] * 0.7, color[2] * 0.7, color[3] * 0.7))
end

local function set_bar(h, x1, z1, x2, z2, width, color, alpha)
    if not (h and Art.valid(h.node)) then return end
    local dx, dz = x2 - x1, z2 - z1
    local length = math.max(0.1, math.sqrt(dx * dx + dz * dz))
    h.node:set_position(vec3((x1 + x2) * 0.5, 0.045, (z1 + z2) * 0.5))
    h.node:set_scale(vec3(width or 0.35, 0.025, length))
    h.node:set_rotation(vec3(0.0, math.deg(math.atan(dx, dz)), 0.0))
    alpha = alpha or 0.16
    local glow = 0.45 + alpha * 1.5
    material.set(h.node, "base_color", vec4(color[1], color[2], color[3], alpha))
    material.set(h.node, "emissive", vec3(color[1] * glow, color[2] * glow, color[3] * glow))
end

local function set_orb(h, x, z, radius, color)
    if not h then return end
    if Art.valid(h.nodes.ring) then
        h.nodes.ring:set_position(vec3(x, 0.055, z))
        h.nodes.ring:set_scale(vec3(radius * 2.0, 0.025, radius * 2.0))
        material.set(h.nodes.ring, "base_color", vec4(color[1], color[2], color[3], 0.22))
        material.set(h.nodes.ring, "emissive", vec3(color[1] * 1.2, color[2] * 1.2, color[3] * 1.2))
    end
    if Art.valid(h.nodes.core) then
        h.nodes.core:set_position(vec3(x, 0.42, z))
        h.nodes.core:set_scale(vec3(radius * 0.48, radius * 0.40, radius * 0.48))
        material.set(h.nodes.core, "base_color", vec4(color[1], color[2], color[3], 1.0))
        material.set(h.nodes.core, "emissive", vec3(color[1] * 2.4, color[2] * 2.4, color[3] * 2.4))
    end
end

local function point_segment_d2(px, pz, x1, z1, x2, z2)
    local dx, dz = x2 - x1, z2 - z1
    local len2 = dx * dx + dz * dz
    local t = len2 > 0.001 and clamp(((px - x1) * dx + (pz - z1) * dz) / len2, 0.0, 1.0) or 0.0
    local ax, az = px - (x1 + dx * t), pz - (z1 + dz * t)
    return ax * ax + az * az
end

local function state(D, c, id)
    local s = D._boss_skill_state
    if s and s.boss ~= c then Skills.clear(D) end
    s = D._boss_skill_state
    if not s then
        s = { boss = c, id = id, borrowed = {}, logged = {} }
        D._boss_skill_state = s
    end
    return s
end

-- GOURD KING — telegraphed ground SLAM. The boss plants (boss_rest_t suppresses
-- the shared arc + Creep.update movement), a ring decal grows for ~0.9s, then an
-- AoE burst around the boss knocks the hero back. Sprout summons are untouched.
local function update_gourd(D, s, c, dt, hero)
    local spec = c.stats.boss_skill
    local radius = spec.radius or 4.6
    if not s.slam then
        if due(s, "cast_t", dt, 1.4, period(c, spec.cooldown or 4.6)) then
            s.slam = { t = spec.windup or 0.9, dur = spec.windup or 0.9, h = take_disc(D, s) }
            set_disc(s.slam.h, c.x, c.z, radius, { 1.0, 0.5, 0.08 }, 0.14)
            ring_burst("ath_gourd_slam_cast", c.x, c.z, radius * 0.9, { 1.0, 0.5, 0.08 }, 14)
            play(D, s, "ground_slam")
        end
        return
    end
    -- Plant during the wind-up: suppresses boss_arc and normal walking so the
    -- ring is honest (update_boss_v2 returns busy while boss_rest_t > 0).
    c.boss_rest_t = math.max(c.boss_rest_t or 0.0, 0.1)
    local slam = s.slam
    slam.t = slam.t - dt
    local p = 1.0 - math.max(0.0, slam.t) / slam.dur
    set_disc(slam.h, c.x, c.z, radius, { 1.0, 0.5 - 0.32 * p, 0.06 }, 0.12 + 0.18 * p)
    slam.fx_t = (slam.fx_t or 0.0) - dt
    if slam.fx_t <= 0.0 then
        slam.fx_t = 0.14
        ring_burst("ath_gourd_slam_front", c.x, c.z, radius * (0.4 + 0.6 * p), { 1.0, 0.45, 0.06 }, 12)
    end
    if slam.t <= 0.0 then
        local dx, dz = hero.x - c.x, hero.z - c.z
        if dx * dx + dz * dz <= radius * radius
            and D:apply_hero_damage(spec.damage or 30.0, { source = "Gourd King (ground slam)" }) then
            local d = math.max(0.001, math.sqrt(dx * dx + dz * dz))
            hero.knock_x = (hero.knock_x or 0.0) + dx / d * (spec.knockback or 8.0)
            hero.knock_z = (hero.knock_z or 0.0) + dz / d * (spec.knockback or 8.0)
        end
        Art.burst("ath_gourd_slam", vec3(c.x, 0.35, c.z),
            { preset = "enemy_give", count = 30, life_max = 0.42, spawn_radius = radius * 0.5,
              size_max = 0.30, color_start = vec4(1.0, 0.5, 0.1, 1.0) })
        D:log("boss skill ground_slam payoff radius=" .. string.format("%.1f", radius))
        release(D, slam.h)
        s.slam = nil
    end
end

-- WASP QUEEN — DIVE STRAFE. A line telegraph is drawn across the arena through
-- the hero (~1.0s), then the queen sweeps that line fast, dealing contact damage
-- along it. Self-driven (no charge system); drones keep spawning via summons.
local function update_dive(D, s, c, dt, hero)
    local spec = c.stats.boss_skill
    local dive = s.dive
    if not dive then
        if due(s, "cast_t", dt, 1.2, period(c, spec.cooldown or 4.8)) then
            local minx, maxx, minz, maxz = bounds(D)
            local dx, dz = hero.x - c.x, hero.z - c.z
            local d = math.max(0.001, math.sqrt(dx * dx + dz * dz))
            dx, dz = dx / d, dz / d
            local reach = 40.0
            local x1 = clamp(hero.x - dx * reach, minx, maxx)
            local z1 = clamp(hero.z - dz * reach, minz, maxz)
            local x2 = clamp(hero.x + dx * reach, minx, maxx)
            local z2 = clamp(hero.z + dz * reach, minz, maxz)
            -- Sweep starts from the end nearer the queen.
            if (x1 - c.x) ^ 2 + (z1 - c.z) ^ 2 > (x2 - c.x) ^ 2 + (z2 - c.z) ^ 2 then
                x1, z1, x2, z2 = x2, z2, x1, z1
            end
            dive = { phase = "tele", t = spec.windup or 1.0, dur = spec.windup or 1.0,
                x1 = x1, z1 = z1, x2 = x2, z2 = z2, h = take_bar(D, s), hit_t = 0.0 }
            s.dive = dive
            set_bar(dive.h, x1, z1, x2, z2, 0.55, { 1.0, 0.22, 0.1 }, 0.2)
            play(D, s, "dive_strafe")
        end
        return
    end
    c.boss_rest_t = math.max(c.boss_rest_t or 0.0, 0.12)
    if dive.phase == "tele" then
        dive.t = dive.t - dt
        local p = 1.0 - math.max(0.0, dive.t) / dive.dur
        set_bar(dive.h, dive.x1, dive.z1, dive.x2, dive.z2, 0.55,
            { 1.0, 0.22 - 0.1 * p, 0.08 }, 0.18 + 0.24 * p)
        dive.fx_t = (dive.fx_t or 0.0) - dt
        if dive.fx_t <= 0.0 then
            dive.fx_t = 0.16
            flow_motes("ath_dive_lane", dive.x1, dive.z1, dive.x2, dive.z2,
                { 1.0, 0.3, 0.1 }, D.realtime, 10)
        end
        if dive.t <= 0.0 then
            dive.phase, dive.t, dive.dur = "sweep", spec.sweep or 0.55, spec.sweep or 0.55
            c.x, c.z = dive.x1, dive.z1
            play(D, s, "dive_sweep")
        end
        return
    end
    dive.t = dive.t - dt
    dive.hit_t = math.max(0.0, dive.hit_t - dt)
    local u = clamp(1.0 - dive.t / dive.dur, 0.0, 1.0)
    c.x = dive.x1 + (dive.x2 - dive.x1) * u
    c.z = dive.z1 + (dive.z2 - dive.z1) * u
    D:clamp_creep_to_arena(c)
    Art.burst("ath_dive_wake", vec3(c.x, 0.4, c.z),
        { preset = "enemy_take", count = 4, life_max = 0.22, spawn_radius = 0.35, size_max = 0.18,
          color_start = vec4(1.0, 0.35, 0.12, 0.95) })
    local dx, dz = hero.x - c.x, hero.z - c.z
    if dive.hit_t <= 0.0 and dx * dx + dz * dz <= 1.5 ^ 2
        and D:apply_hero_damage(spec.damage or 26.0, { source = "Wasp Queen (dive strafe)" }) then
        local d = math.max(0.001, math.sqrt(dx * dx + dz * dz))
        hero.knock_x = (hero.knock_x or 0.0) + dx / d * 6.0
        hero.knock_z = (hero.knock_z or 0.0) + dz / d * 6.0
        dive.hit_t = 0.4
        D:log("boss skill dive_strafe payoff")
    end
    if dive.t <= 0.0 then release(D, dive.h); s.dive = nil end
end

local function update_corn(D, s, c, dt)
    if c.shoot_windup and not s.shooting then play(D, s, "kernel_mortar") end
    s.shooting = c.shoot_windup ~= nil
    if s.heatwave then
        s.heatwave.t = s.heatwave.t - dt
        local p = 1.0 - math.max(0.0, s.heatwave.t) / s.heatwave.dur
        local radius = 2.0 + p * 11.0
        set_disc(s.heatwave.h, c.x, c.z, radius, { 1.0, 0.25, 0.03 }, 0.16 - p * 0.10)
        s.heatwave.fx_t = (s.heatwave.fx_t or 0.0) - dt
        if s.heatwave.fx_t <= 0.0 then
            s.heatwave.fx_t = 0.12
            ring_burst("ath_heatwave_front", c.x, c.z, radius, { 1.0, 0.25, 0.03 }, 14)
        end
        if s.heatwave.t <= 0.0 then release(D, s.heatwave.h); s.heatwave = nil end
    end
    if not due(s, "heat_t", dt, 3.0, period(c, 6.5)) then return end
    play(D, s, "heatwave")
    s.heatwave = { t = 0.9, dur = 0.9, h = take_disc(D, s) }
    local kernels = {}
    for _, other in ipairs(D.creeps or {}) do
        if other.alive and other.archetype == "popcorn_kernel" then kernels[#kernels + 1] = other end
    end
    table.sort(kernels, function(a, b)
        local adx, adz = a.x - c.x, a.z - c.z
        local bdx, bdz = b.x - c.x, b.z - c.z
        return adx * adx + adz * adz < bdx * bdx + bdz * bdz
    end)
    for i, kernel in ipairs(kernels) do
        kernel.stats.explode = { radius = 2.15, damage = 24.0, fuse = 0.7, fuse_speed_mult = 1.0 }
        kernel.fuse_t = 0.55 + i * 0.16
        D:attach_blast_decal(kernel)
    end
end

local function update_briar(D, s, c, dt, hero)
    local leash = s.leash
    if not leash and due(s, "cast_t", dt, 1.4, period(c, 5.2)) then
        leash = { t = 3.4, dur = 3.4, h = take_bar(D, s) }
        s.leash = leash
        play(D, s, "thorn_leash")
    end
    if not leash then hero.boss_move_mult = 1.0; return end
    leash.t = leash.t - dt
    hero.boss_move_mult = 0.75 - 0.40 * (1.0 - leash.t / leash.dur)
    set_bar(leash.h, c.x, c.z, hero.x, hero.z, 0.13, { 0.35, 0.95, 0.18 }, 0.52)
    s.leash_fx_t = (s.leash_fx_t or 0.0) - dt
    if s.leash_fx_t <= 0.0 then
        s.leash_fx_t = 0.18
        flow_motes("ath_thorn_leash", c.x, c.z, hero.x, hero.z,
            { 0.35, 0.95, 0.18 }, D.realtime, 7)
    end
    if leash.t <= 0.0 then
        D:apply_hero_damage(30.0, { source = "Briar Matriarch (thorn leash)" })
        hero.boss_move_mult = 1.0
        release(D, leash.h)
        s.leash = nil
    end
end

local function update_bog(D, s, c, dt, hero)
    local seq = s.sequence
    if not seq and due(s, "cast_t", dt, 1.5, period(c, 6.2)) then
        seq = { phase = "call", next_t = 0.0, index = 0, points = {}, hit = false }
        s.sequence = seq
        play(D, s, "call")
    end
    if not seq then return end
    if seq.phase == "call" then
        seq.next_t = seq.next_t - dt
        if seq.next_t <= 0.0 then
            seq.index = seq.index + 1
            local h = take_disc(D, s)
            local point = { x = hero.x, z = hero.z, h = h }
            seq.points[#seq.points + 1] = point
            set_disc(h, point.x, point.z, 1.7, { 0.85, 0.18, 0.9 }, 0.14)
            ring_burst("ath_bog_call", point.x, point.z, 1.55, { 0.85, 0.18, 0.9 }, 10)
            seq.next_t = 0.28
            if seq.index >= 3 then seq.phase, seq.wait_t = "wait", 1.1 end
        end
    elseif seq.phase == "wait" then
        seq.wait_t = seq.wait_t - dt
        if seq.wait_t <= 0.0 then
            seq.phase, seq.index, seq.next_t = "response", 0, 0.0
            play(D, s, "response")
        end
    else
        seq.next_t = seq.next_t - dt
        if seq.index < #seq.points and seq.next_t <= 0.0 then
            seq.index = seq.index + 1
            seq.points[seq.index].fuse = 0.55
            set_disc(seq.points[seq.index].h, seq.points[seq.index].x, seq.points[seq.index].z,
                1.7, { 1.0, 0.08, 0.06 }, 0.24)
            seq.next_t = 0.24
        end
        local live = false
        for _, point in ipairs(seq.points) do
            if point.fuse then
                point.fuse = point.fuse - dt
                if point.fuse <= 0.0 then
                    local dx, dz = hero.x - point.x, hero.z - point.z
                    if dx * dx + dz * dz <= 1.7 ^ 2 then
                        seq.hit = D:apply_hero_damage(20.0, { source = "Bog Cantor (response)" }) or seq.hit
                    end
                    Art.burst("ath_bog_response", vec3(point.x, 0.3, point.z),
                        { preset = "enemy_give", count = 18, life_max = 0.32, spawn_radius = 0.8,
                          color_start = vec4(0.8, 0.15, 1.0, 1.0) })
                    release(D, point.h)
                    point.fuse = nil
                    point.done = true
                else
                    live = true
                end
            end
        end
        if seq.index >= #seq.points and not live then
            if not seq.hit then break_armor(D, c, 3.0) end
            s.sequence = nil
        end
    end
end

local function bounce(t, lo, hi)
    local span = hi - lo
    local u = t % (span * 2.0)
    return u <= span and (lo + u) or (hi - (u - span))
end

local function update_mill(D, s, c, dt, hero)
    if not s.stones then
        s.stones = { { h = take_orb(D, s), hit_t = 0.0 }, { h = take_orb(D, s), hit_t = 0.0 } }
        s.lanes = { take_bar(D, s), take_bar(D, s), take_bar(D, s), take_bar(D, s) }
        s.clock = 0.0
    end
    if due(s, "cast_t", dt, 0.2, period(c, 4.0)) then play(D, s, "grind_schedule") end
    s.clock = s.clock + dt * (c.boss_phase2 and 10.0 or 7.0)
    local minx, maxx, minz, maxz = bounds(D)
    local poses = {
        { x = bounce(s.clock, minx, maxx), z = (minz + maxz) * 0.5 - 3.0, vx = 1.0, vz = 0.0 },
        { x = (minx + maxx) * 0.5 + 4.0, z = bounce(s.clock + 9.0, minz, maxz), vx = 0.0, vz = 1.0 },
    }
    set_bar(s.lanes[1], minx, poses[1].z - 0.52, maxx, poses[1].z - 0.52,
        0.07, { 0.55, 0.72, 1.0 }, 0.26)
    set_bar(s.lanes[2], minx, poses[1].z + 0.52, maxx, poses[1].z + 0.52,
        0.07, { 0.55, 0.72, 1.0 }, 0.26)
    set_bar(s.lanes[3], poses[2].x - 0.52, minz, poses[2].x - 0.52, maxz,
        0.07, { 0.55, 0.72, 1.0 }, 0.26)
    set_bar(s.lanes[4], poses[2].x + 0.52, minz, poses[2].x + 0.52, maxz,
        0.07, { 0.55, 0.72, 1.0 }, 0.26)
    s.lane_fx_t = (s.lane_fx_t or 0.0) - dt
    if s.lane_fx_t <= 0.0 then
        s.lane_fx_t = 0.18
        flow_motes("ath_mill_lane_h", minx, poses[1].z, maxx, poses[1].z,
            { 0.55, 0.72, 1.0 }, D.realtime, 9)
        flow_motes("ath_mill_lane_v", poses[2].x, minz, poses[2].x, maxz,
            { 0.55, 0.72, 1.0 }, D.realtime, 7)
    end
    for i, stone in ipairs(s.stones) do
        local p = poses[i]
        set_orb(stone.h, p.x, p.z, 1.15, { 0.82, 0.86, 0.95 })
        stone.hit_t = math.max(0.0, stone.hit_t - dt)
        local dx, dz = hero.x - p.x, hero.z - p.z
        if stone.hit_t <= 0.0 and dx * dx + dz * dz <= 1.45 ^ 2 then
            if D:apply_hero_damage(26.0, { source = "Millwright Spectre (millstone)" }) then
                hero.knock_x = (hero.knock_x or 0.0) + p.vx * 7.0
                hero.knock_z = (hero.knock_z or 0.0) + p.vz * 7.0
            end
            stone.hit_t = 0.8
        end
    end
end

local function boss_alpha(c, alpha)
    local body = c.parts and c.parts.body
    if Art.valid(body) then material.set(body, "base_color", vec4(1.0, 1.0, 1.0, alpha)) end
end

local function update_fox(D, s, c, dt, hero)
    if s.pounce_lane then
        s.pounce_lane.t = s.pounce_lane.t - dt
        s.pounce_lane.fx_t = (s.pounce_lane.fx_t or 0.0) - dt
        if s.pounce_lane.fx_t <= 0.0 then
            s.pounce_lane.fx_t = 0.12
            flow_motes("ath_fox_pounce_lane", s.pounce_lane.x1, s.pounce_lane.z1,
                s.pounce_lane.x2, s.pounce_lane.z2, { 1.0, 0.18, 0.05 }, D.realtime, 8)
        end
        if s.pounce_lane.t <= 0.0 then
            for _, h in ipairs(s.pounce_lane.hs) do release(D, h) end
            s.pounce_lane = nil
        end
    end
    -- Active pounce: self-driven lunge from behind the hero along the lane.
    if s.lunge then
        c.boss_rest_t = math.max(c.boss_rest_t or 0.0, 0.1)
        local lg = s.lunge
        lg.t = lg.t - dt
        lg.hit_t = math.max(0.0, lg.hit_t - dt)
        local u = clamp(1.0 - lg.t / lg.dur, 0.0, 1.0)
        c.x = lg.x1 + (lg.x2 - lg.x1) * u
        c.z = lg.z1 + (lg.z2 - lg.z1) * u
        D:clamp_creep_to_arena(c)
        local dx, dz = hero.x - c.x, hero.z - c.z
        if lg.hit_t <= 0.0 and dx * dx + dz * dz <= 1.4 ^ 2
            and D:apply_hero_damage(lg.damage, { source = "The Fox (pounce)" }) then
            local d = math.max(0.001, math.sqrt(dx * dx + dz * dz))
            hero.knock_x = (hero.knock_x or 0.0) + dx / d * 6.0
            hero.knock_z = (hero.knock_z or 0.0) + dz / d * 6.0
            lg.hit_t = 0.5
            D:log("boss skill vanish_pounce payoff")
        end
        if lg.t <= 0.0 then s.lunge = nil end
        return
    end
    if not s.stage and due(s, "cast_t", dt, 1.0, period(c, 5.0)) then
        s.stage, s.stage_t = "vanish", 0.85
        c.boss_rest_t = 0.9
        boss_alpha(c, 0.05)
        play(D, s, "vanish")
    end
    if s.stage ~= "vanish" then return end
    c.boss_rest_t = math.max(c.boss_rest_t or 0.0, 0.1)
    s.stage_t = s.stage_t - dt
    if s.stage_t > 0.0 then return end
    -- Reappear behind the hero and lunge through where they stood.
    local facing = hero.facing or 0.0
    c.x, c.z = hero.x - math.sin(facing) * 4.5, hero.z - math.cos(facing) * 4.5
    D:clamp_creep_to_arena(c)
    boss_alpha(c, 1.0)
    local tx, tz = hero.x + math.sin(facing) * 1.5, hero.z + math.cos(facing) * 1.5
    local dx, dz = tx - c.x, tz - c.z
    local d = math.max(0.001, math.sqrt(dx * dx + dz * dz))
    local nx, nz = -dz / d * 0.34, dx / d * 0.34
    s.pounce_lane = { hs = { take_bar(D, s), take_bar(D, s) }, t = 0.9,
        x1 = c.x, z1 = c.z, x2 = tx, z2 = tz }
    set_bar(s.pounce_lane.hs[1], c.x + nx, c.z + nz, tx + nx, tz + nz,
        0.06, { 1.0, 0.18, 0.05 }, 0.34)
    set_bar(s.pounce_lane.hs[2], c.x - nx, c.z - nz, tx - nx, tz - nz,
        0.06, { 1.0, 0.18, 0.05 }, 0.34)
    ring_burst("ath_fox_pounce", tx, tz, 1.0, { 1.0, 0.18, 0.05 }, 10)
    s.lunge = { t = 0.35, dur = 0.35, x1 = c.x, z1 = c.z, x2 = tx, z2 = tz, hit_t = 0.0, damage = 28.0 }
    play(D, s, "pounce")
    s.stage = nil
end

local function update_feast(D, s, c, dt, hero)
    s.purse = s.purse or 36
    if s.bell then
        s.bell.t = s.bell.t - dt
        set_disc(s.bell.h, c.x, c.z, 5.2, { 1.0, 0.35, 0.04 }, 0.10)
        if s.bell.t <= 0.0 then release(D, s.bell.h); s.bell = nil end
    end
    if due(s, "bell_t", dt, 1.5, period(c, 5.8)) then
        local found = false
        for _, coin in ipairs(D.coins or {}) do
            if coin.active and not coin.essence then coin.feast_fuse = 1.25; found = true end
        end
        if not found then
            for i = 1, 6 do
                local a = i / 6.0 * TAU
                local coin = D:spawn_coin(c.x + math.sin(a) * 2.4, c.z + math.cos(a) * 2.4, 2)
                if coin then coin.feast, coin.feast_fuse = true, 1.25 end
            end
        end
        s.bell = { h = take_disc(D, s), t = 1.25 }
        ring_burst("ath_dinner_bell_cast", c.x, c.z, 5.0, { 1.0, 0.35, 0.04 }, 16)
        play(D, s, "dinner_bell")
    end
    for _, coin in ipairs(D.coins or {}) do
        if coin.active and coin.feast_fuse then
            coin.feast_fuse = coin.feast_fuse - dt
            local p = 0.4 + 0.6 * math.abs(math.sin(D.realtime * 18.0))
            if Art.valid(coin.node) then material.set(coin.node, "emissive", vec3(2.0 + 3.0 * p, 0.25, 0.05)) end
            if coin.feast_fuse <= 0.0 then
                local dx, dz = hero.x - coin.x, hero.z - coin.z
                if dx * dx + dz * dz <= 1.8 ^ 2 then
                    D:apply_hero_damage(24.0, { source = "Feast Warden (dinner bell)" })
                end
                Art.burst("ath_dinner_bell", vec3(coin.x, 0.3, coin.z),
                    { preset = "enemy_give", count = 16, life_max = 0.3, spawn_radius = 0.65,
                      color_start = vec4(1.0, 0.65, 0.08, 1.0) })
                coin.active, coin.feast_fuse, coin.feast = false, nil, nil
                if Art.valid(coin.node) then coin.node:set_position(PARK) end
            end
        end
    end
end

local WIND = { { 1.0, 0.0 }, { 0.0, 1.0 }, { -1.0, 0.0 }, { 0.0, -1.0 } }
local function update_weather(D, s, c, dt, hero)
    if due(s, "shift_t", dt, 0.3, period(c, 4.4)) then
        s.wind_i = (s.wind_i or 0) % #WIND + 1
        s.wind = WIND[s.wind_i]
        play(D, s, "gale_shift")
        D:set_flash("GALE SHIFT")
    end
    local wind = s.wind or WIND[1]
    hero.gale_x, hero.gale_z = wind[1], wind[2]
    local minx, maxx, minz, maxz = bounds(D)
    local cx, cz = (minx + maxx) * 0.5, (minz + maxz) * 0.5
    hero.x = clamp(hero.x + wind[1] * 0.75 * dt, minx, maxx)
    hero.z = clamp(hero.z + wind[2] * 0.75 * dt, minz, maxz)
    s.fx_t = (s.fx_t or 0.0) - dt
    if s.fx_t <= 0.0 then
        s.fx_t = 0.16
        Art.burst("ath_gale_field", vec3(cx, 0.24, cz),
            { preset = "hero_take", count = 14, life_min = 0.28, life_max = 0.52,
              spawn_radius = math.min(maxx - minx, maxz - minz) * 0.36,
              noise_strength = 0.4, size_min = 0.035, size_max = 0.09,
              velocity = vec3(wind[1] * 10.0, 0.15, wind[2] * 10.0), drag = 0.25,
              orientation = "velocity", color_start = vec4(0.82, 0.95, 1.0, 0.72),
              color_end = vec4(0.18, 0.55, 1.0, 0.0) })
    end
end

local function update_pale(D, s, c, dt, hero)
    s.samples = s.samples or {}
    s.sample_t = (s.sample_t or 0.0) - dt
    if s.sample_t <= 0.0 then
        s.sample_t = 0.15
        s.samples[#s.samples + 1] = { x = hero.x, z = hero.z }
        if #s.samples > 40 then table.remove(s.samples, 1) end
        mote_burst("ath_straw_footprint", hero.x, hero.z, { 0.88, 0.82, 0.58 }, 0.10, 2)
    end
    if not s.echo and #s.samples >= 10 and due(s, "cast_t", dt, 2.0, period(c, 6.5)) then
        local path = {}
        for i, p in ipairs(s.samples) do path[i] = { x = p.x, z = p.z } end
        s.echo = { path = path, delay = 0.65, index = 1, step_t = 0.0, hit_t = 0.0 }
        play(D, s, "record_path")
    end
    local echo = s.echo
    if not echo then return end
    if echo.delay > 0.0 then
        echo.delay = echo.delay - dt
        if echo.delay <= 0.0 then
            echo.h = take_orb(D, s)
            play(D, s, "reap_echo")
        end
        return
    end
    echo.step_t = echo.step_t - dt
    echo.hit_t = math.max(0.0, echo.hit_t - dt)
    if echo.step_t <= 0.0 then
        echo.step_t = 0.075
        local p = echo.path[echo.index]
        if not p then release(D, echo.h); s.echo = nil; return end
        set_orb(echo.h, p.x, p.z, 0.9, { 0.88, 0.92, 0.82 })
        Art.burst("ath_reap_echo", vec3(p.x, 0.25, p.z),
            { preset = "enemy_give", count = 3, life_max = 0.22, spawn_radius = 0.18,
              color_start = vec4(0.86, 0.88, 0.72, 0.9) })
        local dx, dz = hero.x - p.x, hero.z - p.z
        if echo.hit_t <= 0.0 and dx * dx + dz * dz <= 1.25 ^ 2 then
            D:apply_hero_damage(18.0, { source = "Pale Scarecrow (reap echo)" })
            echo.hit_t = 0.5
        end
        echo.index = echo.index + 1
    end
end

local function clear_beads(D, s)
    for _, bead in ipairs(s.beads or {}) do release(D, bead.h) end
    s.beads, s.bead_status = {}, {}
end

local function update_wyrmroot(D, s, c, dt, hero)
    s.beads, s.bead_status = s.beads or {}, s.bead_status or {}
    for i, bead in ipairs(s.beads) do
        local a = D.realtime * 2.2 + i / math.max(1, #s.beads) * TAU
        local radius = 2.0 + (s.volley_t and (1.2 - s.volley_t) * 2.0 or 0.0)
        set_orb(bead.h, c.x + math.sin(a) * radius, c.z + math.cos(a) * radius, 0.36,
            STATUS_COLOR[bead.status] or { 0.9, 0.75, 0.25 })
    end
    if #s.beads == 0 then return end
    if not s.volley_t then
        s.volley_wait = (s.volley_wait or 3.5) - dt
        if s.volley_wait <= 0.0 then
            s.volley_t = 1.0
            play(D, s, "rosary_volley")
        end
    else
        s.volley_t = s.volley_t - dt
        if s.volley_t <= 0.0 then
            D:apply_hero_damage(6.0 * #s.beads, { source = "Wyrmroot Ascetic (karmic rosary)" })
            clear_beads(D, s)
            s.volley_t, s.volley_wait = nil, nil
        end
    end
end

local PENALTIES = {
    { id = "damage", text = "WRIT: FRAIL HAND", color = { 1.0, 0.25, 0.16 } },
    { id = "speed", text = "WRIT: HEAVY STEP", color = { 0.25, 0.65, 1.0 } },
    { id = "dodge", text = "WRIT: SLOW GRACE", color = { 0.8, 0.35, 1.0 } },
}
local function update_herald(D, s, c, dt, hero)
    if s.penalty then
        s.penalty.t = s.penalty.t - dt
        hero.boss_damage_mult = s.penalty.id == "damage" and 0.68 or 1.0
        hero.boss_move_mult = s.penalty.id == "speed" and 0.62 or 1.0
        hero.boss_dodge_recharge_mult = s.penalty.id == "dodge" and 1.8 or 1.0
        if s.penalty.t <= 0.0 then s.penalty = nil end
    else
        hero.boss_damage_mult, hero.boss_move_mult, hero.boss_dodge_recharge_mult = 1.0, 1.0, 1.0
    end
    if not s.writ and due(s, "cast_t", dt, 1.0, period(c, 6.5)) then
        s.writ = { t = 4.5, seals = {} }
        local base = hero.facing or 0.0
        for i, penalty in ipairs(PENALTIES) do
            local a = base + (i - 2) * 1.25
            local seal = { penalty = penalty, x = hero.x + math.sin(a) * 3.0,
                z = hero.z + math.cos(a) * 3.0, h = take_disc(D, s) }
            s.writ.seals[#s.writ.seals + 1] = seal
            set_disc(seal.h, seal.x, seal.z, 1.35, penalty.color, 0.18)
            ring_burst("ath_royal_seal_" .. penalty.id, seal.x, seal.z, 1.22, penalty.color, 10)
        end
        play(D, s, "royal_writ")
    end
    local writ = s.writ
    if not writ then return end
    writ.t = writ.t - dt
    local chosen
    for _, seal in ipairs(writ.seals) do
        local dx, dz = hero.x - seal.x, hero.z - seal.z
        if dx * dx + dz * dz <= 1.35 ^ 2 then chosen = seal; break end
    end
    if chosen then
        s.penalty = { id = chosen.penalty.id, t = 4.5 }
        break_armor(D, c, 4.5)
        D:set_flash(chosen.penalty.text)
        for _, seal in ipairs(writ.seals) do release(D, seal.h) end
        s.writ = nil
    elseif writ.t <= 0.0 then
        D:apply_hero_damage(28.0, { source = "Corn Court Herald (unanswered writ)" })
        for _, seal in ipairs(writ.seals) do release(D, seal.h) end
        s.writ = nil
    end
end

local TRIBUTES = {
    { id = "medicine", clip = "tribute_medicine", color = { 0.35, 1.0, 0.45 } },
    { id = "haste", clip = "tribute_haste", color = { 1.0, 0.72, 0.12 } },
    { id = "armor", clip = "tribute_armor", color = { 0.35, 0.65, 1.0 } },
}
local function update_king(D, s, c, dt, hero)
    s.cargo = s.cargo or {}
    if due(s, "cargo_t", dt, 0.35, period(c, 2.6)) then
        s.cargo_i = (s.cargo_i or 0) % #TRIBUTES + 1
        local spec = TRIBUTES[s.cargo_i]
        local minx, maxx, minz, maxz = bounds(D)
        local edge = s.cargo_i
        local x, z = edge == 1 and minx or edge == 2 and maxx or (minx + maxx) * 0.5,
            edge == 3 and minz or (minz + maxz) * 0.5
        local cargo = { spec = spec, x = x, z = z, h = take_orb(D, s) }
        s.cargo[#s.cargo + 1] = cargo
        set_orb(cargo.h, x, z, 0.7, spec.color)
        ring_burst("ath_tribute_" .. spec.id, x, z, 0.75, spec.color, 8)
        play(D, s, spec.clip)
    end
    if (s.hero_haste_t or 0.0) > 0.0 then
        s.hero_haste_t = s.hero_haste_t - dt
        hero.boss_damage_mult, hero.boss_move_mult = 1.2, 1.2
    else
        hero.boss_damage_mult, hero.boss_move_mult = 1.0, 1.0
    end
    if (s.hero_armor_t or 0.0) > 0.0 then
        s.hero_armor_t = s.hero_armor_t - dt
        hero.boss_armor_bonus = 0.25
    else
        hero.boss_armor_bonus = 0.0
    end
    if (c._tribute_haste_t or 0.0) > 0.0 then
        c._tribute_haste_t = c._tribute_haste_t - dt
        c.damage_mult = math.max(c.damage_mult or 1.0, 1.3)
    elseif c.damage_mult == 1.3 then
        c.damage_mult = nil
    end
    c._tribute_armor_t = math.max(0.0, (c._tribute_armor_t or 0.0) - dt)
    local keep = {}
    for _, cargo in ipairs(s.cargo) do
        local dx, dz = c.x - cargo.x, c.z - cargo.z
        local d = math.max(0.001, math.sqrt(dx * dx + dz * dz))
        cargo.x, cargo.z = cargo.x + dx / d * 3.2 * dt, cargo.z + dz / d * 3.2 * dt
        set_orb(cargo.h, cargo.x, cargo.z, 0.7, cargo.spec.color)
        local hx, hz = hero.x - cargo.x, hero.z - cargo.z
        if hx * hx + hz * hz <= 1.25 ^ 2 then
            if cargo.spec.id == "medicine" then hero.hp = math.min(hero.hp_max, hero.hp + hero.hp_max * 0.20)
            elseif cargo.spec.id == "haste" then s.hero_haste_t = 5.0
            else s.hero_armor_t = 5.0 end
            D:spawn_damage_number(hero.x, hero.z, 0, false,
                { text = "TRIBUTE " .. string.upper(cargo.spec.id), color = cargo.spec.color })
            release(D, cargo.h)
        elseif d <= 1.15 then
            if cargo.spec.id == "medicine" then c.hp = math.min(c.hp_max, c.hp + c.hp_max * 0.12)
            elseif cargo.spec.id == "haste" then c._tribute_haste_t = 5.0
            else c._tribute_armor_t = 5.0 end
            release(D, cargo.h)
        else
            keep[#keep + 1] = cargo
        end
    end
    s.cargo = keep
end

local UPDATERS = {
    ground_slam = update_gourd,
    dive_strafe = update_dive,
    popcorn_weather = update_corn,
    thorn_leash = update_briar,
    call_response = update_bog,
    grind_schedule = update_mill,
    vanish_pounce = update_fox,
    dinner_bell = update_feast,
    gale_shift = update_weather,
    reap_echo = update_pale,
    karmic_rosary = update_wyrmroot,
    royal_writ = update_herald,
    royal_tribute = update_king,
}

function Skills.update(D, c, dt, hero)
    local spec = c.stats and c.stats.boss_skill
    local fn = spec and UPDATERS[spec.id]
    if not fn then return false end
    local s = state(D, c, spec.id)
    fn(D, s, c, dt, hero)
    return true
end

function Skills.on_dodge(D, hero)
    local s = D._boss_skill_state
    if not (s and s.boss and s.boss.alive) then return end
    if s.id == "thorn_leash" and s.leash then
        release(D, s.leash.h)
        s.leash = nil
        hero.boss_move_mult = 1.0
        break_armor(D, s.boss, 3.5)
        play(D, s, "leash_snap")
    elseif s.id == "karmic_rosary" and #(s.beads or {}) > 0 then
        local dx, dz = hero.x - s.boss.x, hero.z - s.boss.z
        if dx * dx + dz * dz <= 3.4 ^ 2 then
            clear_beads(D, s)
            s.volley_t, s.volley_wait = nil, nil
            break_armor(D, s.boss, 4.0)
            play(D, s, "rosary_break")
        end
    end
end

-- Autoplay hint: returns a flee direction (dx, dz) when a boss-skill payoff is
-- about to land near the hero, so the pilot dodges it. Skill logic stays fully
-- inside this file; the manual pilot just consults this one seam. Returns nil
-- when there is nothing imminent to dodge.
local function flee_perp(hero, x1, z1, x2, z2)
    local lx, lz = x2 - x1, z2 - z1
    local m = math.sqrt(lx * lx + lz * lz)
    if m < 0.001 then return hero.x - x1, hero.z - z1 end
    local px, pz = -lz / m, lx / m
    if (hero.x - x1) * px + (hero.z - z1) * pz < 0.0 then px, pz = -px, -pz end
    return px, pz
end
function Skills.dodge_hint(D, hero)
    local s = D._boss_skill_state
    if not (s and s.boss and s.boss.alive) then return nil end
    if s.id == "ground_slam" and s.slam and s.slam.t <= 0.45 then
        local r = (s.boss.stats.boss_skill.radius or 4.6) + 0.6
        local dx, dz = hero.x - s.boss.x, hero.z - s.boss.z
        if dx * dx + dz * dz <= r * r then return dx, dz end
    elseif s.id == "dive_strafe" and s.dive then
        local dv = s.dive
        if (dv.phase == "sweep" or (dv.phase == "tele" and dv.t <= 0.4))
            and point_segment_d2(hero.x, hero.z, dv.x1, dv.z1, dv.x2, dv.z2) <= 2.6 ^ 2 then
            return flee_perp(hero, dv.x1, dv.z1, dv.x2, dv.z2)
        end
    elseif s.id == "vanish_pounce" and s.lunge then
        local lg = s.lunge
        if point_segment_d2(hero.x, hero.z, lg.x1, lg.z1, lg.x2, lg.z2) <= 2.0 ^ 2 then
            return flee_perp(hero, lg.x1, lg.z1, lg.x2, lg.z2)
        end
    end
    return nil
end

function Skills.dodge_speed_mult(D, dx, dz)
    local s = D._boss_skill_state
    if not (s and s.id == "gale_shift" and s.wind) then return 1.0 end
    return clamp(1.0 + (dx * s.wind[1] + dz * s.wind[2]) * 0.55, 0.45, 1.55)
end

function Skills.on_status(D, c, status)
    local spec = c and c.stats and c.stats.boss_skill
    if not (spec and spec.id == "karmic_rosary") then return end
    local s = state(D, c, spec.id)
    s.beads, s.bead_status = s.beads or {}, s.bead_status or {}
    status = tostring(status or "status")
    if s.bead_status[status] or #s.beads >= 6 then return end
    s.bead_status[status] = true
    s.beads[#s.beads + 1] = { status = status, h = take_orb(D, s) }
    s.volley_wait = s.volley_wait or 3.5
    play(D, s, "rosary_gather")
end

function Skills.on_projectile_end(D, p)
    local s = D._boss_skill_state
    if not (s and s.id == "popcorn_weather" and p.source_archetype == "corn_colossus") then return end
    local minx, maxx, minz, maxz = bounds(D)
    D:spawn_one({ x = clamp(p.x, minx, maxx), y = clamp(p.z, minz, maxz) }, "popcorn_kernel", true)
end

function Skills.on_hero_damage(D)
    local s = D._boss_skill_state
    local hero = D.hero
    if not (s and s.id == "dinner_bell" and hero and (s.purse or 36) > 0) then return end
    s.purse = s.purse or 36
    for _ = 1, math.min(3, s.purse) do
        local coin = D:spawn_coin(hero.x, hero.z, 1)
        if coin then coin.feast = true end
        s.purse = s.purse - 1
    end
end

function Skills.clear(D)
    local s = D._boss_skill_state
    if not s then return end
    boss_alpha(s.boss, 1.0)
    for _, h in ipairs(s.borrowed or {}) do release(D, h) end
    for _, coin in ipairs(D.coins or {}) do
        coin.feast_fuse, coin.feast = nil, nil
        if coin.active and Art.valid(coin.node) then
            material.set(coin.node, "base_color", vec4(1.0, 0.84, 0.25, 1.0))
            material.set(coin.node, "emissive", vec3(1.8, 1.5, 0.35))
        end
    end
    for _, c in ipairs(D.creeps or {}) do
        if c.archetype == "popcorn_kernel" then c.alive = false end
    end
    local hero = D.hero
    if hero then
        hero.boss_move_mult, hero.boss_damage_mult = 1.0, 1.0
        hero.boss_dodge_recharge_mult, hero.boss_armor_bonus = 1.0, 0.0
        hero.gale_x, hero.gale_z = nil, nil
    end
    D._boss_skill_state = nil
end

return Skills
