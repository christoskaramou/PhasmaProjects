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
            if type(data.bag[i]) == "string" then D.inv_grid[i] = items[data.bag[i]] end
        end
    end
    if type(data.equipped) == "table" then
        for _, slot_name in ipairs(SLOTS) do
            local item = items[data.equipped[slot_name]]
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
    -- Draft picks: ids only; Duel rebuilds run_cards after create_hero.
    D._saved_run_card_ids = nil
    if type(data.run_cards) == "table" then
        local ids = {}
        for _, id in ipairs(data.run_cards) do
            if type(id) == "string" and id ~= "" then ids[#ids + 1] = id end
        end
        if #ids > 0 then D._saved_run_card_ids = ids end
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
        map_next_wave = {}, run_cards = {} }
    for i = 1, GRID_SIZE do
        local item = D.inv_grid and D.inv_grid[i]
        if item and item.id then data.bag[i] = item.id end
    end
    for _, slot_name in ipairs(SLOTS) do
        local item = D.gear_equipped and D.gear_equipped[slot_name]
        if item and item.id then data.equipped[slot_name] = item.id end
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
