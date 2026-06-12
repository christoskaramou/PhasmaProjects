-- Against The Hero — entry dispatcher.
--
-- By default this boots the GAME SHELL (the menu): Play -> pick Hero/Horde ->
-- build a 20-of-50 deck -> pick a battlefield -> play. The shell drives every
-- menu-launched mode through the shared Duel engine.
--
-- ATH_MODE still jumps straight into a single standalone mode for smoke scripts:
--   pit | iron_gallows | gravewarden  -> bespoke 2D modes with their own loop
--   menu                              -> force the shell (the default)
-- To drop straight into a (menu) battlefield without clicking, set
--   ATH_DUEL_MODE=<id> [ATH_SIDE=hero|horde]  (handled inside the shell).

local DEFAULT_MODE = "menu"
local COMMON_PATH = "Scripts/shared/ath_common.lua"
local CommonModule = nil

local function load_common()
    if CommonModule then return CommonModule end
    local source = fs and fs.read and fs.read(COMMON_PATH) or nil
    if not source then error("Against The Hero: missing common module at " .. COMMON_PATH) end
    local chunk, err = load(source, "@" .. assets_path .. COMMON_PATH, "t", _ENV)
    if not chunk then error(err) end
    CommonModule = chunk()
    return CommonModule
end

local Common = load_common()

local function requested_mode()
    return Common.getenv("ATH_MODE", DEFAULT_MODE)
end

local function load_script(path, label)
    return Common.load_script(path, label, _ENV)
end

local mode = requested_mode()

if mode == "classic" then
    pe_error("Against The Hero: classic mode has been removed (reachable only via git history); run ATH_MODE=menu")
    return
end

if mode == "menu" then
    load_script("Scripts/shared/ath_shell.lua", "game shell")
    return
end

-- Standalone modes keep their own self-contained loop.
if mode == "pit" or mode == "iron_gallows" or mode == "gravewarden" then
    load_script("Scripts/modes/" .. mode .. "/mode.lua", "mode '" .. tostring(mode) .. "'")
    return
end

pe_error("Against The Hero: unknown ATH_MODE='" .. tostring(mode) .. "' (expected menu, pit, iron_gallows, or gravewarden)")
