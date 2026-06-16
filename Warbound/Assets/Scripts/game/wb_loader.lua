-- wb_loader — the tiny module system for Warbound.
--
-- PhasmaEngine's Lua does not wire `require` to the project asset tree, so we read
-- and compile module files ourselves (mirroring the project convention). Every
-- module is loaded exactly once and cached; cross-module references go through the
-- shared `WB` table, which the loader injects into each module's environment. So a
-- module just writes `WB.units.spawn(...)` and the loader guarantees `WB.units`
-- exists by the time any update tick runs (everything is preloaded up front).

local Loader = { cache = {}, WB = {} }

-- Resolve a module name ("units") to its asset-relative path.
local function module_path(name)
    return "Scripts/game/wb_" .. name .. ".lua"
end

-- Load (or return cached) module `name`. The module's chunk environment inherits
-- every engine global (scene, primitives, input, runtime_ui, vec3, math, ...) via
-- __index/__newindex on _ENV, and additionally sees `WB` (the shared namespace).
function Loader.require(name)
    local cached = Loader.cache[name]
    if cached ~= nil then return cached end

    local path = module_path(name)
    local source = fs and fs.read and fs.read(path) or nil
    if not source then
        error("Warbound: missing module '" .. tostring(name) .. "' at " .. path)
    end

    local env = setmetatable({ WB = Loader.WB }, { __index = _ENV, __newindex = _ENV })
    local chunk, err = load(source, "@" .. tostring(assets_path or "") .. path, "t", env)
    if not chunk then error("Warbound: compile error in " .. path .. ": " .. tostring(err)) end

    local mod = chunk()
    if mod == nil then mod = true end -- cache non-returning modules so we don't reload
    Loader.cache[name] = mod
    Loader.WB[name] = mod
    return mod
end

-- Preload a list of modules in order and return the shared WB namespace.
function Loader.preload(names)
    for _, name in ipairs(names) do Loader.require(name) end
    return Loader.WB
end

return Loader
