-- Persistent town profile: banked gold, backpack/equip item ids, map unlocks,
-- and per-map next-wave (the round you re-enter on). Multiple slots live under
-- Save/slot_N.lua; Save/slots.lua tracks the last-used slot. Legacy
-- Save/profile.lua is migrated into slot 1 once.

local Profile = {}

Profile.SLOT_COUNT = 3

local META_PATH = "Save/slots.lua"
local LEGACY_PATH = "Save/profile.lua"
local SLOTS = { "helmet", "body", "pants", "gloves", "weapon", "jewelry" }
local RARITIES = { "common", "uncommon", "rare", "epic", "legendary" }
local GRID_SIZE = 24
local CLASS_NAMES = { "Ranger", "Brawler", "Sower", "Mage", "Rogue", "Warrior", "Necromancer" }

local function serialize(t)
    local parts = {}
    for k, v in pairs(t) do
        local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
        local value
        if type(v) == "table" then value = serialize(v)
        elseif type(v) == "string" then value = string.format("%q", v)
        else value = tostring(v) end
        parts[#parts + 1] = key .. "=" .. value
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function read_table(path)
    local src = fs and fs.read and fs.read(path) or nil
    if type(src) ~= "string" or #src == 0 then return nil end
    local ok, data = pcall(function() return load(src, "@" .. path, "t", {})() end)
    if ok and type(data) == "table" then return data end
    return nil
end

local function write_table(path, data)
    if not (fs and fs.write) then return false end
    local ok, wrote = pcall(fs.write, path, "return " .. serialize(data))
    return ok and wrote ~= false
end

function Profile.slot_path(slot)
    slot = math.max(1, math.min(Profile.SLOT_COUNT, math.floor(slot or 1)))
    return string.format("Save/slot_%d.lua", slot)
end

function Profile.migrate_legacy()
    if not (fs and fs.read and fs.write) then return end
    local legacy = fs.read(LEGACY_PATH)
    if type(legacy) ~= "string" or #legacy == 0 then return end
    local s1 = Profile.slot_path(1)
    local existing = fs.read(s1)
    if type(existing) == "string" and #existing > 0 then return end
    pcall(fs.write, s1, legacy)
end

local function read_meta()
    Profile.migrate_legacy()
    local data = read_table(META_PATH) or {}
    local active = tonumber(data.active) or 1
    active = math.max(1, math.min(Profile.SLOT_COUNT, math.floor(active)))
    return { active = active }
end

local function write_meta(meta)
    return write_table(META_PATH, { v = 1, active = meta.active or 1 })
end

function Profile.active_slot()
    local r = _G.ATH_RUN
    if r and type(r.save_slot) == "number" then
        return math.max(1, math.min(Profile.SLOT_COUNT, math.floor(r.save_slot)))
    end
    return read_meta().active
end

function Profile.set_active(slot)
    slot = math.max(1, math.min(Profile.SLOT_COUNT, math.floor(slot or 1)))
    _G.ATH_RUN = _G.ATH_RUN or {}
    _G.ATH_RUN.save_slot = slot
    write_meta({ active = slot })
    return slot
end

function Profile.exists(slot)
    Profile.migrate_legacy()
    local src = fs and fs.read and fs.read(Profile.slot_path(slot)) or nil
    return type(src) == "string" and #src > 0
end

function Profile.any_exists()
    for i = 1, Profile.SLOT_COUNT do
        if Profile.exists(i) then return true end
    end
    return false
end

function Profile.first_empty()
    for i = 1, Profile.SLOT_COUNT do
        if not Profile.exists(i) then return i end
    end
    return nil
end

-- Lightweight peek for menu labels (nil if empty).
function Profile.peek(slot)
    Profile.migrate_legacy()
    local data = read_table(Profile.slot_path(slot))
    if not data or data.v ~= 1 then return nil end
    local hi = tonumber(data.hero_index) or 1
    hi = math.max(1, math.floor(hi))
    return {
        hero_index = hi,
        hero_name = CLASS_NAMES[hi] or ("Hero " .. tostring(hi)),
        gold = math.max(0, math.floor(tonumber(data.gold) or 0)),
        maps_cleared = math.max(0, math.floor(tonumber(data.maps_cleared) or 0)),
    }
end

function Profile.slot_label(slot, for_new_game)
    local T = _G.ATH_I18N and _G.ATH_I18N.t or function(s, ...)
        if select("#", ...) > 0 then return string.format(s, ...) end
        return s
    end
    local info = Profile.peek(slot)
    if not info then
        return T("SLOT %d  EMPTY", slot)
    end
    local base = T("SLOT %d  %s  Map %d", slot, T(info.hero_name), (info.maps_cleared or 0) + 1)
    if for_new_game then
        return base .. "  " .. T("(overwrite)")
    end
    return base
end

local function item_index(D)
    local out = {}
    for _, item in ipairs((D.gear_cfg and D.gear_cfg.items) or {}) do
        if item.id then out[item.id] = item end
    end
    return out
end

-- Clone a catalog item with numeric effect stats scaled (boss drops = +10%).
-- `*_mult` buffs scale the bonus over 1.0; interval/recharge mults scale the
-- "faster" portion so +12% AS becomes +13.2% AS at scale 1.1.
function Profile.scale_item(item, scale)
    if not item then return nil end
    scale = scale or 1.0
    if scale == 1.0 then return item end
    local out = {}
    for k, v in pairs(item) do
        if k ~= "effect" then out[k] = v end
    end
    out.stat_scale = scale
    out.boss_drop = true
    local src = item.effect
    if type(src) == "table" then
        local effect = {}
        for k, v in pairs(src) do
            if type(v) == "number" then
                if type(k) == "string" and k:sub(-5) == "_mult" then
                    if k == "fire_interval_mult" or k == "dodge_recharge_mult" then
                        if v > 0.0 then
                            local as = (1.0 / v) - 1.0
                            effect[k] = 1.0 / math.max(0.05, 1.0 + as * scale)
                        else
                            effect[k] = v
                        end
                    else
                        effect[k] = 1.0 + (v - 1.0) * scale
                    end
                else
                    effect[k] = v * scale
                end
            else
                effect[k] = v
            end
        end
        out.effect = effect
    end
    if item.desc then
        out.desc = tostring(item.desc) .. "\n(+10% boss)"
    end
    return out
end

-- Bag/equip entries may be a bare id string or { id=, s=stat_scale }.
local function decode_item(catalog, entry)
    if type(entry) == "string" then return catalog[entry] end
    if type(entry) ~= "table" or type(entry.id) ~= "string" then return nil end
    local base = catalog[entry.id]
    if not base then return nil end
    local scale = tonumber(entry.s) or 1.0
    if scale == 1.0 then return base end
    return Profile.scale_item(base, scale)
end

local function encode_item(item)
    if not (item and item.id) then return nil end
    local scale = tonumber(item.stat_scale) or 1.0
    if scale ~= 1.0 then return { id = item.id, s = scale } end
    return item.id
end

function Profile.load(D)
    D.gold = 0
    D.inv_grid = {}
    D.gear_equipped = {}
    D.map_next_wave = {}

    -- New Game: ignore any prior file in this slot until the first save_profile.
    if _G.ATH_RUN and _G.ATH_RUN.new_game then
        _G.ATH_RUN.new_game = nil
        D.save_slot = Profile.active_slot()
        D._saved_run_card_ids = nil
        D.run_cards = {}
        D.skill_points = 0
        return false
    end

    Profile.migrate_legacy()
    local slot = Profile.active_slot()
    D.save_slot = slot
    local path = Profile.slot_path(slot)
    local data = read_table(path)
    if not data or data.v ~= 1 then return false end

    local items = item_index(D)
    if type(data.gold) == "number" and data.gold >= 0 and data.gold < math.huge then
        D.gold = math.floor(data.gold)
    end
    if type(data.maps_cleared) == "number" and data.maps_cleared >= 0 and data.maps_cleared < 1000 then
        D.maps_cleared = math.floor(data.maps_cleared)
    end
    if type(data.hero_index) == "number" and data.hero_index >= 1 and data.hero_index < 100 then
        local hi = math.floor(data.hero_index)
        D.hero_class_index = hi
        _G.ATH_RUN = _G.ATH_RUN or {}
        _G.ATH_RUN.hero_index = hi
    end
    if type(data.map_next_wave) == "table" then
        for k, v in pairs(data.map_next_wave) do
            local i = tonumber(k)
            if i and i >= 1 and i < 1000 and type(v) == "number" and v >= 1 and v < 100 then
                D.map_next_wave[math.floor(i)] = math.floor(v)
            end
        end
    end
    if type(data.bag) == "table" then
        for i = 1, GRID_SIZE do
            local item = decode_item(items, data.bag[i])
            if item then D.inv_grid[i] = item end
        end
    end
    if type(data.equipped) == "table" then
        for _, slot_name in ipairs(SLOTS) do
            local item = decode_item(items, data.equipped[slot_name])
            if item and item.slot == slot_name then D.gear_equipped[slot_name] = item end
        end
    end
    D.loot_filter = {}
    for _, rarity in ipairs(RARITIES) do D.loot_filter[rarity] = true end
    if type(data.loot_filter) == "table" then
        for _, rarity in ipairs(RARITIES) do
            local v = data.loot_filter[rarity]
            if v ~= nil then D.loot_filter[rarity] = v ~= false end
        end
    end
    -- Draft/skill picks: ids only; Duel rebuilds run_cards after create_hero.
    D._saved_run_card_ids = nil
    if type(data.run_cards) == "table" then
        local ids = {}
        for _, id in ipairs(data.run_cards) do
            if type(id) == "string" and id ~= "" then ids[#ids + 1] = id end
        end
        if #ids > 0 then D._saved_run_card_ids = ids end
    end
    if type(data.skill_points) == "number" and data.skill_points >= 0 and data.skill_points < 1000 then
        D.skill_points = math.floor(data.skill_points)
    end
    return true
end

function Profile.save(D)
    if not (fs and fs.write) then return false end
    local slot = (D and D.save_slot) or Profile.active_slot()
    slot = Profile.set_active(slot)
    if D then D.save_slot = slot end
    local hi = D.hero_class_index
        or (_G.ATH_RUN and _G.ATH_RUN.hero_index)
        or 1
    local data = { v = 1, gold = math.max(0, math.floor(D.gold or 0)), bag = {}, equipped = {},
        maps_cleared = math.max(0, math.floor(D.maps_cleared or 0)),
        hero_index = math.max(1, math.floor(hi)),
        map_next_wave = {}, run_cards = {},
        skill_points = math.max(0, math.floor(D.skill_points or 0)) }
    for i = 1, GRID_SIZE do
        local item = D.inv_grid and D.inv_grid[i]
        local enc = encode_item(item)
        if enc then data.bag[i] = enc end
    end
    for _, slot_name in ipairs(SLOTS) do
        local enc = encode_item(D.gear_equipped and D.gear_equipped[slot_name])
        if enc then data.equipped[slot_name] = enc end
    end
    for i, w in pairs(D.map_next_wave or {}) do
        if type(i) == "number" and type(w) == "number" and i >= 1 and w >= 1 then
            data.map_next_wave[math.floor(i)] = math.max(1, math.floor(w))
        end
    end
    data.loot_filter = {}
    for _, rarity in ipairs(RARITIES) do
        data.loot_filter[rarity] = not (D.loot_filter and D.loot_filter[rarity] == false)
    end
    for _, card in ipairs(D.run_cards or {}) do
        if type(card) == "table" and type(card.id) == "string" then
            data.run_cards[#data.run_cards + 1] = card.id
        end
    end
    return write_table(Profile.slot_path(slot), data)
end

_G.ATH_PROFILE = Profile
return Profile
