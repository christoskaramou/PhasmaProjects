if rawget(_G, "ATH_VISUALS") then return _G.ATH_VISUALS end

local function log(message)
    if pe_log then pe_log("[visuals] " .. message) end
end

local function load_manifest(name)
    local path = "Data/visuals/" .. name .. ".json"
    local source = fs and fs.read and fs.read(path) or nil
    if not source then return nil, "missing " .. path end
    local data, err = ATH_COMMON.json_decode(source)
    if type(data) ~= "table" then return nil, err or ("invalid " .. path) end
    return data
end

local requested = ATH_COMMON.getenv("ATH_SKIN", "default")
if not requested:match("^[%w_-]+$") then
    log("invalid ATH_SKIN=" .. tostring(requested) .. "; using default")
    requested = "default"
end

local data, err = load_manifest(requested)
local active = requested
if not data and requested ~= "default" then
    log(tostring(err) .. "; using default")
    data, err = load_manifest("default")
    active = "default"
end
assert(data, "Against The Hero: " .. tostring(err))

local Visuals = { name = active, data = data }
_G.ATH_VISUALS = Visuals
log("manifest=" .. active)
return Visuals
