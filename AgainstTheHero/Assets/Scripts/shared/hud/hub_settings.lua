-- Settings tab actions (game.pescene Pause Menu / Settings group).
-- Toggle rule (all on/off UI): colored fill = ON, transparent fill = OFF.
-- Labels stay short — no "ON"/"OFF" text.
--
-- Graphics knobs write live Scene Settings and scene.save("game.pescene") —
-- same blob as the editor Scene Settings node (not Save/settings.lua).

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
local TOGGLE_ON = { 0.62, 0.34, 0.86, 0.95 }

local PRESENT_MODES = { "fifo", "fifo_relaxed", "mailbox", "immediate" }
local SCENE_NAME = "game.pescene"

local SUBTABS = {
    { key = "game", node = "Set Sub Game", group = "Set Game", label = "GAME" },
    { key = "audio", node = "Set Sub Audio", group = "Set Audio", label = "AUDIO" },
    { key = "graphics", node = "Set Sub Graphics", group = "Set Graphics", label = "GRAPHICS" },
    { key = "controls", node = "Set Sub Controls", group = "Set Controls", label = "CONTROLS" },
}

local TAB_ACTIVE = { 0.62, 0.34, 0.86, 0.95 }
local TAB_IDLE = { 0.0, 0.0, 0.0, 0.0 }
local TAB_IDLE_BORDER = { 0.40, 0.62, 0.58, 0.9 }

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

local function clamp(x, lo, hi)
    x = tonumber(x) or lo
    if x < lo then return lo elseif x > hi then return hi end
    return x
end

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

local function sget(key, fallback)
    if not (settings and settings.get) then return fallback end
    local v = settings.get(key)
    if v == nil then return fallback end
    return v
end

local function preferred_time_scale()
    local D = _G.ATH_ACTIVE_DUEL
    if D and D._saved_time_scale ~= nil then return D._saved_time_scale end
    local ts = sget("time_scale", 1.0)
    if ts == 0 then return 1.0 end
    return ts
end

local function present_mode()
    if rhi and rhi.get_present_mode then
        local m = rhi.get_present_mode()
        if m and m ~= "unknown" then return m end
    end
    return "fifo"
end

local function present_label(mode)
    mode = mode or present_mode()
    if mode == "fifo" then return "VSYNC"
    elseif mode == "fifo_relaxed" then return "RELAXED"
    elseif mode == "mailbox" then return "MAILBOX"
    elseif mode == "immediate" then return "IMMEDIATE"
    end
    return string.upper(tostring(mode))
end

-- Persist live Scene Settings into game.pescene. While gear/console freeze has
-- forced time_scale=0, write the preferred restore value so the scene keeps it.
local function save_scene_settings()
    if not (settings and settings.set) then return end
    local D = _G.ATH_ACTIVE_DUEL
    local frozen = D and D._saved_time_scale ~= nil
    if frozen then settings.set("time_scale", D._saved_time_scale) end
    if scene and scene.save then
        pcall(scene.save, SCENE_NAME)
    elseif save_scene then
        pcall(save_scene, SCENE_NAME)
    end
    if frozen then settings.set("time_scale", 0.0) end
end

local function refresh_subtabs(D)
    local cur = (D and D._settings_subtab) or "game"
    for _, row in ipairs(SUBTABS) do
        local g = node(row.group)
        if g and g.set_enabled then g:set_enabled(row.key == cur) end
        local tab = node(row.node)
        if valid(tab) then
            local on = row.key == cur
            tab:set_ui({
                title = T(row.label),
                fill = on and TAB_ACTIVE or TAB_IDLE,
                border = on and TAB_ACTIVE or TAB_IDLE_BORDER,
                accent = TAB_ACTIVE,
                text_color = on and TEXT_ON or TEXT_OFF,
            })
        end
    end
end

local function refresh_gfx()
    if not (settings and settings.get) then return end
    style_toggle(node("Set Gfx Fxaa"), sget("fxaa", false) == true, ACCENT, T("FXAA"))
    style_toggle(node("Set Gfx Taa"), sget("taa", false) == true, ACCENT, T("TAA"))
    style_toggle(node("Set Gfx Grade"), sget("color_grading", false) == true, ACCENT, T("COLOR GRADE"))
    style_toggle(node("Set Gfx Disney"), sget("use_Disney_PBR", false) == true, ACCENT, T("DISNEY PBR"))

    local rs = sget("render_scale", 1.0)
    if rhi and rhi.get_render_scale then rs = rhi.get_render_scale() or rs end
    local scale_lbl = node("Set Gfx Scale Label")
    if valid(scale_lbl) then
        scale_lbl:set_ui({ body = T("SCALE") .. "  " .. tostring(math.floor(rs * 100 + 0.5)) .. "%" })
    end

    local ts = preferred_time_scale()
    local time_lbl = node("Set Gfx Time Label")
    if valid(time_lbl) then
        time_lbl:set_ui({ body = T("TIME") .. "  " .. tostring(math.floor(ts * 100 + 0.5)) .. "%" })
    end

    local present = node("Set Gfx Present")
    if valid(present) then
        present:set_ui({ title = T("PRESENT") .. "  " .. present_label() })
    end
end

local refresh

local function set_subtab(key)
    local D = _G.ATH_ACTIVE_DUEL
    if D then D._settings_subtab = key end
    if refresh then refresh(D) end
end

refresh = function(D)
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
    style_toggle(node("Set Show Fps"), I.show_fps ~= false, ACCENT, T("SHOW FPS"))
    style_toggle(node("Set Dev Mode"), I.dev_mode == true, ACCENT, T("DEV MODE"))
    style_toggle(node("Menu Dev Mode"), I.dev_mode == true, ACCENT, T("DEV MODE"))

    for _, h in ipairs({
        { "Set Game Header", "GAME" },
        { "Set Audio Header", "AUDIO" },
        { "Set Graphics Header", "GRAPHICS" },
        { "Set Controls Header", "CONTROLS & HELPERS" },
        { "Set Loot Header", "LOOT FILTER" },
    }) do
        local n = node(h[1])
        if valid(n) then n:set_ui({ body = T(h[2]) }) end
    end
    local help = node("Set Controls Help")
    if valid(help) then
        help:set_ui({ body = T(
            "Move · WASD / stick\nAttack · LMB / RT\nDodge · Space / A\nGear hub · Gear btn / Esc") })
    end

    refresh_subtabs(D)
    refresh_gfx()
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

function on_shake() toggle_setting("screen_shake") end
function on_show_fps() toggle_setting("show_fps") end

function on_sub_game() set_subtab("game") end
function on_sub_audio() set_subtab("audio") end
function on_sub_graphics() set_subtab("graphics") end
function on_sub_controls() set_subtab("controls") end

function on_dev_mode()
    local I = ensure_i18n()
    if I and I.toggle_dev_mode then I.toggle_dev_mode() end
    refresh(_G.ATH_ACTIVE_DUEL)
end

local function toggle_scene_bool(key)
    if not (settings and settings.get and settings.set) then return end
    settings.set(key, not (sget(key, false) == true))
    save_scene_settings()
    refresh(_G.ATH_ACTIVE_DUEL)
end

function on_gfx_fxaa() toggle_scene_bool("fxaa") end
function on_gfx_taa() toggle_scene_bool("taa") end
function on_gfx_grade() toggle_scene_bool("color_grading") end
function on_gfx_disney() toggle_scene_bool("use_Disney_PBR") end
function on_gfx_shadows() end -- legacy no-op
function on_gfx_cas() end -- legacy no-op

function on_gfx_scale_down()
    local cur = sget("render_scale", 1.0)
    if rhi and rhi.get_render_scale then cur = rhi.get_render_scale() or cur end
    local rs = clamp(math.floor(cur * 20.0 + 0.5) / 20.0 - 0.05, 0.5, 1.5)
    if rhi and rhi.set_render_scale then
        rhi.set_render_scale(rs)
    elseif settings and settings.set then
        settings.set("render_scale", rs)
    end
    save_scene_settings()
    refresh(_G.ATH_ACTIVE_DUEL)
end

function on_gfx_scale_up()
    local cur = sget("render_scale", 1.0)
    if rhi and rhi.get_render_scale then cur = rhi.get_render_scale() or cur end
    local rs = clamp(math.floor(cur * 20.0 + 0.5) / 20.0 + 0.05, 0.5, 1.5)
    if rhi and rhi.set_render_scale then
        rhi.set_render_scale(rs)
    elseif settings and settings.set then
        settings.set("render_scale", rs)
    end
    save_scene_settings()
    refresh(_G.ATH_ACTIVE_DUEL)
end

function on_gfx_time_down()
    local ts = clamp(preferred_time_scale() - 0.25, 0.25, 2.0)
    local D = _G.ATH_ACTIVE_DUEL
    if D and D._saved_time_scale ~= nil then
        D._saved_time_scale = ts
    elseif settings and settings.set then
        settings.set("time_scale", ts)
    end
    save_scene_settings()
    refresh(_G.ATH_ACTIVE_DUEL)
end

function on_gfx_time_up()
    local ts = clamp(preferred_time_scale() + 0.25, 0.25, 2.0)
    local D = _G.ATH_ACTIVE_DUEL
    if D and D._saved_time_scale ~= nil then
        D._saved_time_scale = ts
    elseif settings and settings.set then
        settings.set("time_scale", ts)
    end
    save_scene_settings()
    refresh(_G.ATH_ACTIVE_DUEL)
end

function on_gfx_present()
    local cur = present_mode()
    local idx = 1
    for i, m in ipairs(PRESENT_MODES) do
        if m == cur then idx = i break end
    end
    local next_mode = PRESENT_MODES[(idx % #PRESENT_MODES) + 1]
    if rhi and rhi.set_present_mode then rhi.set_present_mode(next_mode) end
    save_scene_settings()
    refresh(_G.ATH_ACTIVE_DUEL)
end

function on_quit_app()
    if engine and engine.set_play_mode and engine.is_play_mode and engine.is_play_mode() then
        engine.set_play_mode(false)
        return
    end
    if engine and engine.quit then engine.quit() end
end

_G.ATH_HUB_SETTINGS = { refresh = refresh, set_subtab = set_subtab }

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
