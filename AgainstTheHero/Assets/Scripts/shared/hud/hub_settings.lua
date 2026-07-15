-- Settings tab actions (game.pescene Pause Menu / Settings group).
-- Toggle rule (all on/off UI): colored fill = ON, transparent fill = OFF.
-- Labels stay short — no "ON"/"OFF" text.

local function T(key, ...)
    local I18n = _G.ATH_I18N
    if I18n and I18n.t then return I18n.t(key, ...) end
    if select("#", ...) > 0 then return string.format(key, ...) end
    return key
end

local FILL_OFF = { 0.0, 0.0, 0.0, 0.0 }
local BORDER_OFF = { 0.40, 0.62, 0.58, 0.9 }
local TEXT_ON = { 0.96, 0.96, 1.0, 1.0 }
local TEXT_OFF = { 0.70, 0.74, 0.80, 0.95 }
local ACCENT = { 0.62, 0.34, 0.86, 0.95 }
local TOGGLE_ON = { 0.62, 0.34, 0.86, 0.95 } -- default purple for binary toggles

local LOOT_ROWS = {
    { key = "common", short = "COM", node = "Set Loot Common",
      color = { 0.55, 0.55, 0.58, 0.95 } },
    { key = "uncommon", short = "UNC", node = "Set Loot Uncommon",
      color = { 0.33, 0.67, 0.33, 0.95 } },
    { key = "rare", short = "RARE", node = "Set Loot Rare",
      color = { 0.28, 0.55, 0.93, 0.95 } },
    { key = "epic", short = "EPIC", node = "Set Loot Epic",
      color = { 0.65, 0.45, 0.93, 0.95 } },
    { key = "legendary", short = "LEG", node = "Set Loot Legendary",
      color = { 0.79, 0.64, 0.15, 0.95 } },
}

local VOL_ROWS = {
    { key = "master", label = "MASTER", node = "Set Vol MASTER Label" },
    { key = "music", label = "MUSIC", node = "Set Vol MUSIC Label" },
    { key = "sfx", label = "SFX", node = "Set Vol SFX Label" },
}

local function node(name)
    if scene and scene.find_model then return scene.find_model(name) end
    return nil
end

local function valid(n)
    return n and n.set_ui
end

-- Colored fill = on; transparent fill = off. Rarity toggles keep tinted outline when off.
local function style_toggle(n, on, color_on, title, tint_outline_off)
    if not valid(n) then return end
    local c = color_on or TOGGLE_ON
    n:set_ui({
        title = title,
        fill = on and c or FILL_OFF,
        border = (on or tint_outline_off) and c or BORDER_OFF,
        accent = c,
        text_color = on and TEXT_ON or TEXT_OFF,
    })
end

local function vol_pct(v)
    return math.floor((tonumber(v) or 0) * 100 + 0.5)
end

local function ensure_i18n()
    local I = _G.ATH_I18N
    if I and I.toggle_bool then return I end
    local path = "Scripts/shared/ath_i18n.lua"
    local src = fs and fs.read and fs.read(path) or nil
    if src then
        local chunk = load(src, "@" .. tostring(assets_path or "") .. path, "t", _ENV)
        if chunk then pcall(chunk) end
    end
    return _G.ATH_I18N
end

local function refresh(D)
    local I = ensure_i18n()
    if not I then return end

    style_toggle(node("Set Lang EN"), I.lang == "en", ACCENT, "EN")
    style_toggle(node("Set Lang EL"), I.lang == "el", ACCENT, "EL")
    style_toggle(node("Menu Lang EN"), I.lang == "en", ACCENT, "EN")
    style_toggle(node("Menu Lang EL"), I.lang == "el", ACCENT, "EL")

    style_toggle(node("Set Damage Text"), I.damage_text == true, ACCENT, T("DAMAGE"))
    style_toggle(node("Menu Damage Text"), I.damage_text == true, ACCENT, T("DAMAGE TEXT"))

    local Inv = _G.ATH_INVENTORY
    if D and Inv and Inv.ensure then Inv.ensure(D) end
    for _, row in ipairs(LOOT_ROWS) do
        local on = true
        if D and D.loot_filter then on = D.loot_filter[row.key] ~= false end
        style_toggle(node(row.node), on, row.color, row.short, true)
    end

    for _, row in ipairs(VOL_ROWS) do
        local n = node(row.node)
        if valid(n) then
            local pct = vol_pct(I["vol_" .. row.key])
            n:set_ui({ body = T(row.label) .. "  " .. pct .. "%" })
        end
    end

    style_toggle(node("Set Shake"), I.screen_shake == true, ACCENT, T("SCREEN SHAKE"))
    style_toggle(node("Menu Shake"), I.screen_shake == true, ACCENT, T("SCREEN SHAKE"))

    for _, h in ipairs({
        { "Set Game Panel Header", "GAME" },
        { "Set Audio Panel Header", "AUDIO" },
        { "Set Gfx Panel Header", "GRAPHICS" },
        { "Set Controls Panel Header", "CONTROLS & HELPERS" },
        { "Set Loot Header", "LOOT FILTER" },
    }) do
        local n = node(h[1])
        if valid(n) then n:set_ui({ body = T(h[2]) }) end
    end
    local note = node("Set Gfx Note")
    if valid(note) then
        note:set_ui({ body = T("Render settings are\nedited in the scene.") })
    end
    local help = node("Set Controls Help")
    if valid(help) then
        help:set_ui({ body = T(
            "Move · WASD / stick\nAttack · LMB / RT\nDodge · Space / A\nGear hub · Gear btn / Esc") })
    end
end

local function hub_refresh()
    local D = _G.ATH_ACTIVE_DUEL
    local Inv = _G.ATH_INVENTORY
    if D and Inv and Inv.refresh then Inv.refresh(D) end
    refresh(D)
end

local function step_vol(which, delta)
    local I = _G.ATH_I18N
    if not I then return end
    I.set_volume(which, (I["vol_" .. which] or 0) + delta)
    refresh(_G.ATH_ACTIVE_DUEL)
end

local function toggle_loot(rarity)
    local D = _G.ATH_ACTIVE_DUEL
    if not (D and D.loot_filter) then return end
    D.loot_filter[rarity] = not (D.loot_filter[rarity] ~= false)
    if D.save_profile then D:save_profile() end
    refresh(D)
end

function on_lang_en()
    local I = _G.ATH_I18N
    if I then I.set_lang("en") end
    refresh(_G.ATH_ACTIVE_DUEL)
end

function on_lang_el()
    local I = _G.ATH_I18N
    if I then I.set_lang("el") end
    refresh(_G.ATH_ACTIVE_DUEL)
end

function on_damage_text()
    local I = _G.ATH_I18N
    if I then I.toggle_damage_text() end
    refresh(_G.ATH_ACTIVE_DUEL)
end

function on_loot_common() toggle_loot("common") end
function on_loot_uncommon() toggle_loot("uncommon") end
function on_loot_rare() toggle_loot("rare") end
function on_loot_epic() toggle_loot("epic") end
function on_loot_legendary() toggle_loot("legendary") end

function on_vol_master_down() step_vol("master", -0.1) end
function on_vol_master_up() step_vol("master", 0.1) end
function on_vol_music_down() step_vol("music", -0.1) end
function on_vol_music_up() step_vol("music", 0.1) end
function on_vol_sfx_down() step_vol("sfx", -0.1) end
function on_vol_sfx_up() step_vol("sfx", 0.1) end

local function toggle_setting(key)
    local I = ensure_i18n()
    if I and I.toggle_bool then I.toggle_bool(key) end
    refresh(_G.ATH_ACTIVE_DUEL)
end

-- Stale bindings from older scenes — render settings are scene-authored now.
function on_gfx_fxaa() end
function on_gfx_taa() end
function on_gfx_shadows() end
function on_gfx_cas() end
function on_shake() toggle_setting("screen_shake") end

function on_quit_app()
    if engine and engine.quit then engine.quit() end
end

_G.ATH_HUB_SETTINGS = { refresh = refresh }

-- One refresher / init pass even though many Settings buttons share this script.
if not _G._ATH_HUB_SETTINGS_WIRED then
    _G._ATH_HUB_SETTINGS_WIRED = true
    local I18n = ensure_i18n()
    if I18n and I18n.on_refresh then I18n.on_refresh(hub_refresh) end
end

hooks {
    init = function()
        ensure_i18n()
        if _G._ATH_HUB_SETTINGS_INITED then return end
        _G._ATH_HUB_SETTINGS_INITED = true
        refresh(_G.ATH_ACTIVE_DUEL)
    end,
}
