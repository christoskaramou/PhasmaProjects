-- ath_sprite_anim — hero Component_Sprite clip driver for top-down ATH.
--
-- Maps duel hero state onto engine sprite clips (idle/walk/attack/hit/death).
-- Soft-fails when `sprite` bindings or sheet metadata are missing so older
-- engine builds keep the single-texture fallback path.

local Anim = {}

local function has_sprite_api()
    return type(sprite) == "table" and type(sprite.setup) == "function" and type(sprite.play) == "function"
end

function Anim.available()
    return has_sprite_api()
end

-- Attach / rebind a class sheet onto the hero body quad. Returns true on success.
function Anim.setup_hero(hero, class_or_sheet)
    if not (hero and hero.parts and has_sprite_api()) then return false end
    local body = hero.parts.body
    if not body then return false end
    local sheet = nil
    if type(class_or_sheet) == "string" then
        sheet = class_or_sheet
    elseif type(class_or_sheet) == "table" then
        sheet = class_or_sheet.sprite_sheet
    end
    if not sheet or sheet == "" then return false end
    local ok = sprite.setup(body, { metadata = sheet })
    if not ok then return false end
    hero._sprite_anim = {
        sheet = sheet,
        clip = nil,
        oneshot_until = 0.0,
        facing_left = false,
    }
    if material and material.set_double_sided then
        material.set_double_sided(body, true)
    end
    if material and material.set_render_type then
        material.set_render_type(body, "alpha_cut")
    end
    sprite.play(body, "idle", true)
    hero._sprite_anim.clip = "idle"
    return true
end

local function moving(hero)
    local vx, vz = hero.vel_x or 0.0, hero.vel_z or 0.0
    return (vx * vx + vz * vz) > 0.04
end

local function want_clip(hero, now)
    if hero.dead then return "death" end
    local st = hero._sprite_anim
    if st and (st.oneshot_until or 0.0) > now then
        return st.clip
    end
    if (hero.hit_flash or 0.0) > 0.10 and (not st or st.clip ~= "hit") then
        return "hit"
    end
    if (hero.attack_flash or 0.0) > 0.08 then
        return "attack"
    end
    if moving(hero) then return "walk" end
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
function Anim.tick(hero, now)
    local st = hero and hero._sprite_anim
    if not (st and hero.parts and has_sprite_api()) then return false end
    local body = hero.parts.body
    if not body then return false end

    local clip = want_clip(hero, now or 0.0)
    if clip ~= st.clip then
        local restart = (clip == "attack" or clip == "hit" or clip == "death" or clip ~= st.clip)
        if sprite.play(body, clip, restart) then
            st.clip = clip
            local hold = oneshot_duration(clip)
            if hold > 0.0 and clip ~= "death" then
                st.oneshot_until = (now or 0.0) + hold
            elseif clip == "death" then
                st.oneshot_until = math.huge
            else
                st.oneshot_until = 0.0
            end
        end
    end

    -- L/R facing from move / aim. Post-create scale flips are unreliable.
    -- FLAT_ROT yaw+180 is documented as upside-down; roll+180 mirrors L/R
    -- while keeping the sprite head-up under the top-down camera.
    local fx = math.sin(hero.facing or 0.0)
    st.facing_left = fx < -0.05 or (fx <= 0.05 and st.facing_left)
    return true
end

function Anim.facing_roll(hero)
    local st = hero and hero._sprite_anim
    if st and st.facing_left then return 180.0 end
    return 0.0
end

return Anim
