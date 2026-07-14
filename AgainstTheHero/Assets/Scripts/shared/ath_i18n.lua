-- Against The Hero localization (EN/EL).
-- Gettext-style: English source strings are keys; Greek lives in ath_strings_el.lua.

local I18n = {
    lang = "en",
    damage_text = true,
    _el = nil,
    _refreshers = {},
}

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
    if not src then return end
    local ok, data = pcall(function() return load(src, "@" .. SETTINGS_PATH, "t", {})() end)
    if not (ok and type(data) == "table") then return end
    if data.lang == "en" or data.lang == "el" then I18n.lang = data.lang end
    if type(data.damage_text) == "boolean" then I18n.damage_text = data.damage_text end
end

local function save_settings()
    if not (fs and fs.write) then return end
    pcall(fs.write, SETTINGS_PATH, "return " .. serialize({ lang = I18n.lang, damage_text = I18n.damage_text }))
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
    if type(fn) == "function" then I18n._refreshers[#I18n._refreshers + 1] = fn end
end

-- Replaceable single callback for the active duel (avoids stacking across restarts).
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
    I18n.damage_text = not I18n.damage_text
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

-- Menu scenes: rewrite authored English placeholders for the active language.
function I18n.apply_menu_scene(which)
    which = which or ""
    if which == "intro" or which == "" then
        I18n.apply_named_nodes({
            { name = "UI Title", body = "AGAINST THE HERO" },
            { name = "UI Play", title = "PLAY" },
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
              body = "Command fire, ice, earth, or air with mana-powered spells." },
            { name = "UI Rogue", title = "ROGUE",
              body = "Regenerate energy for poison, hemorrhage, shadow, and execution skills." },
            { name = "UI Warrior", title = "WARRIOR",
              body = "Iron line-holder. Rage from blows dealt and taken fuels the slam." },
            { name = "UI Necromancer", title = "NECROMANCER",
              body = "Frail speaker for the dead. Souls of the slain feed the bolt and the pack." },
            { name = "UI Back", title = "BACK" },
        })
    end
    if which == "map" or which == "" then
        I18n.apply_named_nodes({
            { name = "UI Title", body = "SELECT MAP" },
            { name = "UI Arena", title = "ARENA",
              body = "Spud Fields skirmish - survive 5 waves of the swarm." },
            { name = "UI Back", title = "BACK" },
        })
    end
end

load_settings()
_G.ATH_I18N = I18n
return I18n
