-- Against The Hero localization (EN/EL).
-- Gettext-style: English source strings are keys; Greek lives in ath_strings_el.lua.
--
-- Idempotent: re-running this file upgrades an existing _G.ATH_I18N singleton
-- (new fields + methods) so a long-lived launcher Lua state picks up settings
-- added after the first boot.

local DEFAULTS = {
    lang = "en",
    damage_text = true,
    vol_master = 1.0,
    vol_music = 0.8,
    vol_sfx = 0.9,
    screen_shake = true,
}

local I18n = _G.ATH_I18N or {}
for k, v in pairs(DEFAULTS) do
    if I18n[k] == nil then I18n[k] = v end
end
I18n._refreshers = I18n._refreshers or {}

-- Scene render settings (AA/shadows/IBL/…) live in the editor /.pescene — drop
-- any legacy player-pref keys so we never write them back.
I18n.gfx_fxaa, I18n.gfx_taa, I18n.gfx_cas, I18n.gfx_shadows = nil, nil, nil, nil

local function clamp01(x)
    x = tonumber(x) or 0
    if x < 0 then return 0 elseif x > 1 then return 1 end
    return x
end

local SETTINGS_PATH = "Save/settings.lua"
local TEXT_KEYS = { label = true, title = true, subtitle = true, body = true, footer = true }

local function serialize(t)
    local parts = {}
    for k, v in pairs(t) do
        local key = "[" .. string.format("%q", k) .. "]"
        local value = type(v) == "string" and string.format("%q", v) or tostring(v)
        parts[#parts + 1] = key .. "=" .. value
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function load_settings()
    local src = fs and fs.read and fs.read(SETTINGS_PATH) or nil
    if src then
        local ok, data = pcall(function() return load(src, "@" .. SETTINGS_PATH, "t", {})() end)
        if ok and type(data) == "table" then
            if data.lang == "en" or data.lang == "el" then I18n.lang = data.lang end
            if type(data.damage_text) == "boolean" then I18n.damage_text = data.damage_text end
            if data.vol_master ~= nil then I18n.vol_master = clamp01(data.vol_master) end
            if data.vol_music ~= nil then I18n.vol_music = clamp01(data.vol_music) end
            if data.vol_sfx ~= nil then I18n.vol_sfx = clamp01(data.vol_sfx) end
            if type(data.screen_shake) == "boolean" then I18n.screen_shake = data.screen_shake end
        end
    end
end

local function save_settings()
    if not (fs and fs.write) then return end
    pcall(fs.write, SETTINGS_PATH, "return " .. serialize({
        lang = I18n.lang,
        damage_text = I18n.damage_text,
        vol_master = I18n.vol_master,
        vol_music = I18n.vol_music,
        vol_sfx = I18n.vol_sfx,
        screen_shake = I18n.screen_shake == true,
    }))
end

local function load_el()
    if I18n._el then return I18n._el end
    local path = "Scripts/shared/ath_strings_el.lua"
    local src = fs and fs.read and fs.read(path) or nil
    if not src then
        I18n._el = {}
        return I18n._el
    end
    local ok, tbl = pcall(function()
        return load(src, "@" .. tostring(assets_path or "") .. path, "t", {})()
    end)
    I18n._el = (ok and type(tbl) == "table") and tbl or {}
    return I18n._el
end

function I18n.t(key, ...)
    if key == nil then return "" end
    key = tostring(key)
    local out = key
    if I18n.lang == "el" then
        local el = load_el()
        if el[key] then out = el[key] end
    end
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, out, ...)
        if ok then return formatted end
    end
    return out
end

function I18n.translate_fields(fields)
    if type(fields) ~= "table" then return fields end
    local out = {}
    for k, v in pairs(fields) do
        if TEXT_KEYS[k] and type(v) == "string" and v ~= "" then
            out[k] = I18n.t(v)
        else
            out[k] = v
        end
    end
    return out
end

function I18n.set_ui(node, fields)
    if not (node and node.set_ui) then return end
    node:set_ui(I18n.translate_fields(fields))
end

function I18n.on_refresh(fn)
    if type(fn) ~= "function" then return end
    for i = 1, #I18n._refreshers do
        if I18n._refreshers[i] == fn then return end
    end
    I18n._refreshers[#I18n._refreshers + 1] = fn
end

function I18n.set_duel_refresh(fn)
    I18n._duel_refresh = fn
end

function I18n.refresh()
    for i = 1, #I18n._refreshers do
        pcall(I18n._refreshers[i])
    end
    if I18n._duel_refresh then pcall(I18n._duel_refresh) end
end

function I18n.set_lang(lang)
    if lang ~= "en" and lang ~= "el" then return false end
    if I18n.lang == lang then return true end
    I18n.lang = lang
    save_settings()
    I18n.refresh()
    return true
end

function I18n.toggle()
    return I18n.set_lang(I18n.lang == "el" and "en" or "el")
end

function I18n.toggle_damage_text()
    I18n.damage_text = not (I18n.damage_text == true)
    save_settings()
end

function I18n.set_volume(which, value)
    local key = "vol_" .. tostring(which or "")
    if I18n[key] == nil then return end
    I18n[key] = clamp01(value)
    save_settings()
    I18n.apply_audio()
end

function I18n.apply_audio()
    if not (audio and audio.set_volume) then return end
    audio.set_volume("master", I18n.vol_master)
    audio.set_volume("music", I18n.vol_music)
    audio.set_volume("sfx", I18n.vol_sfx)
end

-- Kept as a no-op so older call sites don't error. Render settings are scene-authored.
function I18n.apply_graphics() end

function I18n.toggle_bool(key)
    if DEFAULTS[key] == nil and I18n[key] == nil then return end
    if tostring(key):sub(1, 4) == "gfx_" then return end -- scene-authored; ignore
    if I18n[key] == nil then I18n[key] = DEFAULTS[key] end
    I18n[key] = not (I18n[key] == true)
    save_settings()
end

function I18n.apply_named_nodes(specs)
    if not (scene and scene.find_model) then return end
    for _, spec in ipairs(specs or {}) do
        local node = scene.find_model(spec.name)
        if node and node.set_ui then
            local fields = {}
            if spec.title then fields.title = I18n.t(spec.title) end
            if spec.body then fields.body = I18n.t(spec.body) end
            if spec.subtitle then fields.subtitle = I18n.t(spec.subtitle) end
            if next(fields) then node:set_ui(fields) end
        end
    end
end

function I18n.apply_menu_scene(which)
    which = which or ""
    if which == "intro" or which == "" then
        I18n.apply_named_nodes({
            { name = "UI Title", body = "AGAINST THE HERO" },
            { name = "UI Play", title = "New Game" },
            { name = "UI Continue", title = "Continue" },
            { name = "UI Load", title = "Continue" }, -- legacy node name
            { name = "UI Load Pick", title = "Load" },
            { name = "UI Quit", title = "Quit" },
            { name = "Menu Quit", title = "Quit" },
        })
    end
    if which == "hero_select" or which == "" then
        I18n.apply_named_nodes({
            { name = "UI Title", body = "CHOOSE YOUR HERO" },
            { name = "UI Ranger", title = "RANGER",
              body = "Long-range bolts. Pick the swarm off from afar." },
            { name = "UI Brawler", title = "BRAWLER",
              body = "Cleaves all in reach. Tanky - wade into the swarm." },
            { name = "UI Sower", title = "SOWER",
              body = "Sprays seed-shot at the nearest five. Short range, fast." },
            { name = "UI Mage", title = "MAGE",
              body = "Elemental on-hit effects reshape every basic projectile." },
            { name = "UI Rogue", title = "ROGUE",
              body = "Fast short-range daggers with deadly on-hit riders." },
            { name = "UI Warrior", title = "WARRIOR",
              body = "Iron line-holder with punishing on-hit effects and guard." },
            { name = "UI Necromancer", title = "NECROMANCER",
              body = "Frail speaker for the dead. Souls of the slain feed the bolt and the pack." },
            { name = "UI Back", title = "BACK" },
        })
    end
end

load_settings()
I18n.apply_audio()
_G.ATH_I18N = I18n
return I18n
