-- ath_sprite_anim — Component_Sprite clip driver for top-down ATH
-- (heroes, creeps, minions). Soft-fails when `sprite` bindings or sheet
-- metadata are missing so older engine builds keep the single-texture fallback.

local Anim = {}

local function has_sprite_api()
    return type(sprite) == "table" and type(sprite.setup) == "function" and type(sprite.play) == "function"
end

function Anim.available()
    return has_sprite_api()
end

local function resolve_sheet(sheet_or_def)
    if type(sheet_or_def) == "string" then return sheet_or_def end
    if type(sheet_or_def) == "table" then return sheet_or_def.sprite_sheet end
    return nil
end

-- Attach / rebind a sheet onto actor.parts.body. kind = "hero"|"creep"|"minion".
function Anim.setup(actor, sheet_or_def, kind)
    if not (actor and actor.parts and has_sprite_api()) then return false end
    local body = actor.parts.body
    if not body then return false end
    local sheet = resolve_sheet(sheet_or_def)
    if not sheet or sheet == "" then return false end
    local ok = sprite.setup(body, { metadata = sheet })
    if not ok then return false end
    actor._sprite_anim = {
        sheet = sheet,
        clip = nil,
        oneshot_until = 0.0,
        facing_left = false,
        kind = kind or "hero",
        last_x = actor.x,
        last_z = actor.z,
    }
    if material and material.set_double_sided then material.set_double_sided(body, true) end
    if material and material.set_render_type then material.set_render_type(body, "alpha_cut") end
    sprite.play(body, "idle", true)
    actor._sprite_anim.clip = "idle"
    return true
end

function Anim.setup_hero(hero, class_or_sheet)
    return Anim.setup(hero, class_or_sheet, "hero")
end

-- Reattach anim state to a pooled body that ALREADY has this sheet bound (the
-- engine sprite component persists on the rig; only the Lua creep table is new).
-- No sprite.setup: that engine call re-marks scene geometry dirty per spawn —
-- exactly the cost rig pooling exists to avoid.
function Anim.rebind(actor, sheet, kind)
    if not (actor and actor.parts and has_sprite_api()) then return false end
    local body = actor.parts.body
    if not body then return false end
    if not sprite.play(body, "idle", true) then return false end
    actor._sprite_anim = {
        sheet = sheet,
        clip = "idle",
        oneshot_until = 0.0,
        facing_left = false,
        kind = kind or "hero",
        last_x = actor.x,
        last_z = actor.z,
    }
    return true
end

local function moving_from_delta(actor, st, now)
    local x, z = actor.x or 0.0, actor.z or 0.0
    local lx, lz = st.last_x, st.last_z
    st.last_x, st.last_z = x, z
    local dt = now - (st.last_t or now)
    st.last_t = now
    if lx == nil then return false end
    if dt <= 0.0 then dt = 1.0 / 60.0 end
    local dx, dz = x - lx, z - lz
    -- Speed cutoff ~0.7 m/s; per-tick displacement scales with dt, a fixed
    -- threshold reads slow creeps as idle at high framerates.
    local step = 0.7 * dt
    local moving = (dx * dx + dz * dz) > step * step
    if moving then
        actor.facing = math.atan(dx, dz)
    elseif actor.facing == nil and actor._face_x then
        actor.facing = math.atan(actor._face_x, actor._face_z or 1.0)
    end
    return moving
end

local function want_clip_hero(hero, st, now, is_moving)
    if hero.dead then return "death" end
    if st and (st.oneshot_until or 0.0) > now then return st.clip end
    if (hero.hit_flash or 0.0) > 0.10 and (not st or st.clip ~= "hit") then return "hit" end
    if (hero.attack_flash or 0.0) > 0.08 then return "attack" end
    if is_moving then return "walk" end
    return "idle"
end

local function want_clip_creep(c, st, now, is_moving)
    if not c.alive then return "death" end
    if st and (st.oneshot_until or 0.0) > now then return st.clip end
    if (c.hit_flash or 0.0) > 0.10 and (not st or st.clip ~= "hit") then return "hit" end
    if c.bite_windup or c.shoot_windup or c.charge_state == "windup" then return "attack" end
    if (c._attack_flash or 0.0) > 0.08 then return "attack" end
    if is_moving then return "walk" end
    return "idle"
end

local function oneshot_duration(clip)
    if clip == "attack" then return 0.28 end
    if clip == "hit" then return 0.18 end
    if clip == "death" then return 0.55 end
    return 0.0
end

-- Per-tick: pick clip, flip facing. Returns true when sprite anim owns the body
-- (caller should skip competing procedural waddle).
function Anim.tick(actor, now)
    local st = actor and actor._sprite_anim
    if not (st and actor.parts and has_sprite_api()) then return false end
    local body = actor.parts.body
    if not body then return false end
    now = now or 0.0

    local is_moving
    if st.kind == "hero" then
        local vx, vz = actor.vel_x or 0.0, actor.vel_z or 0.0
        is_moving = (vx * vx + vz * vz) > 0.04
    else
        is_moving = moving_from_delta(actor, st, now)
    end

    local clip
    if st.kind == "hero" then
        clip = want_clip_hero(actor, st, now, is_moving)
    else
        clip = want_clip_creep(actor, st, now, is_moving)
    end

    if clip ~= st.clip then
        if sprite.play(body, clip, true) then
            st.clip = clip
            local hold = oneshot_duration(clip)
            if hold > 0.0 and clip ~= "death" then
                st.oneshot_until = now + hold
            elseif clip == "death" then
                st.oneshot_until = math.huge
            else
                st.oneshot_until = 0.0
            end
        end
    end

    local fx = math.sin(actor.facing or 0.0)
    st.facing_left = fx < -0.05 or (fx <= 0.05 and st.facing_left)
    return true
end

function Anim.facing_roll(actor)
    local st = actor and actor._sprite_anim
    if st and st.facing_left then return 180.0 end
    return 0.0
end

return Anim
