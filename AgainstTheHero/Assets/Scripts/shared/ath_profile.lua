-- Persistent town profile: banked gold plus item-template ids in the backpack
-- and six equipped slots. Run cards and combat state intentionally never enter
-- this file.

local Profile = {}

local SAVE_PATH = "Save/profile.lua"
local SLOTS = { "helmet", "body", "pants", "gloves", "weapon", "jewelry" }
local GRID_SIZE = 24

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

    local src = fs and fs.read and fs.read(SAVE_PATH) or nil
    if not src then return false end
    local ok, data = pcall(function() return load(src, "@" .. SAVE_PATH, "t", {})() end)
    if not ok or type(data) ~= "table" or data.v ~= 1 then return false end

    local items = item_index(D)
    if type(data.gold) == "number" and data.gold >= 0 and data.gold < math.huge then
        D.gold = math.floor(data.gold)
    end
    if type(data.maps_cleared) == "number" and data.maps_cleared >= 0 and data.maps_cleared < 1000 then
        D.maps_cleared = math.floor(data.maps_cleared)
    end
    if type(data.bag) == "table" then
        for i = 1, GRID_SIZE do
            if type(data.bag[i]) == "string" then D.inv_grid[i] = items[data.bag[i]] end
        end
    end
    if type(data.equipped) == "table" then
        for _, slot in ipairs(SLOTS) do
            local item = items[data.equipped[slot]]
            if item and item.slot == slot then D.gear_equipped[slot] = item end
        end
    end
    return true
end

function Profile.save(D)
    if not (fs and fs.write) then return false end
    local data = { v = 1, gold = math.max(0, math.floor(D.gold or 0)), bag = {}, equipped = {},
        maps_cleared = math.max(0, math.floor(D.maps_cleared or 0)) }
    for i = 1, GRID_SIZE do
        local item = D.inv_grid and D.inv_grid[i]
        if item and item.id then data.bag[i] = item.id end
    end
    for _, slot in ipairs(SLOTS) do
        local item = D.gear_equipped and D.gear_equipped[slot]
        if item and item.id then data.equipped[slot] = item.id end
    end
    local ok, wrote = pcall(fs.write, SAVE_PATH, "return " .. serialize(data))
    return ok and wrote ~= false
end

return Profile
