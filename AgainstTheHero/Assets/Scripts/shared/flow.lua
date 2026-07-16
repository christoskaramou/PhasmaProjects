-- ATH scene-flow controller (intro -> hero_select -> game).
--
-- Attach this script to authored UI Button nodes (the .pescene "script" key).
-- Each button's runtime_ui.action_function names one handler below; the engine
-- resolves it on THIS node's script env and calls it as handler(event).
--
-- scene.load(name) resolves to Assets/Scenes/<name>, so pass the bare filename.
-- Cross-scene choices live on _G.ATH_RUN (see Scripts/global/ath_run.lua), which
-- survives scene.load; the game scene's launcher reads them to start the arena.
-- In-run destination picks use the painted world map inside game.pescene.

local function log(msg)
    if pe_log then
        pe_log("[flow] " .. msg)
    else
        print("[flow] " .. msg)
    end
end

local function run()
    _G.ATH_RUN = _G.ATH_RUN or { hero_index = 1, battlefield = "arena" }
    return _G.ATH_RUN
end

local function go(name)
    log("scene.load queued -> " .. name)
    if _G.ATH_REQUEST_SCENE then
        _G.ATH_REQUEST_SCENE(name)
    else
        scene.load(name)
    end
end

local function i18n()
    return _G.ATH_I18N
end

local function T(key, ...)
    local I = i18n()
    if I and I.t then return I.t(key, ...) end
    if select("#", ...) > 0 then return string.format(key, ...) end
    return key
end

local function profile()
    if _G.ATH_PROFILE then return _G.ATH_PROFILE end
    local path = "Scripts/shared/ath_profile.lua"
    local src = fs and fs.read and fs.read(path) or nil
    if not src then return nil end
    local chunk = load(src, "@" .. tostring(assets_path or "") .. path, "t", _ENV)
    if not chunk then return nil end
    local ok, mod = pcall(chunk)
    if ok then return mod end
    return nil
end

local function enter_game_from_slot(slot)
    local P = profile()
    if not P then return end
    slot = P.set_active(slot)
    local info = P.peek(slot)
    if not info then
        log("load: slot " .. tostring(slot) .. " empty")
        return false
    end
    local r = run()
    r.hero_index = info.hero_index or 1
    r.battlefield = "arena"
    r.save_slot = slot
    r.new_game = nil -- must load the existing slot, not start fresh
    log(string.format("continue slot=%d hero_index=%d", slot, r.hero_index))
    go("game.pescene")
    return true
end

-- Slot picker: "load" (Continue/Load) or "new" (New Game chooses where to save).
local picker_mode = nil -- nil | "load" | "new"

local function hide_slot_picker()
    picker_mode = nil
    if not (runtime_ui and runtime_ui.remove) then return end
    runtime_ui.remove("__scene_ui", "load_pick_bg")
    runtime_ui.remove("__scene_ui", "load_pick_title")
    for i = 1, 3 do
        runtime_ui.remove("__scene_ui", "load_slot_" .. i)
    end
    runtime_ui.remove("__scene_ui", "load_pick_back")
end

local function refresh_intro_buttons()
    if not (scene and scene.find_model) then return end
    local P = profile()
    local has = P and P.any_exists and P.any_exists() or false
    local function set_save_btn(node, title)
        if not (node and node.set_ui) then return end
        node:set_ui({
            title = title,
            fill = has and { 0.12, 0.14, 0.17, 0.96 } or { 0.08, 0.08, 0.10, 0.55 },
            border = has and { 0.96, 0.74, 0.22, 0.95 } or { 0.35, 0.36, 0.40, 0.55 },
            text_color = has and { 0.97, 0.98, 1.0, 1.0 } or { 0.45, 0.46, 0.50, 0.70 },
            no_input = not has, -- needs engine set_ui no_input (SceneNodeBindings)
        })
    end
    set_save_btn(scene.find_model("UI Continue") or scene.find_model("UI Load"), T("Continue"))
    set_save_btn(scene.find_model("UI Load Pick"), T("Load"))
end

local function draw_slot_picker()
    if not picker_mode or not (runtime_ui and runtime_ui.set_quad) then return end
    local P = profile()
    if not P then return end
    local for_new = picker_mode == "new"
    local sw, sh = 2400.0, 1080.0
    if runtime_ui.get_surface_size then
        local s = runtime_ui.get_surface_size()
        if s and s.width and s.width > 0 then sw, sh = s.width, s.height end
    end
    local panel_w, panel_h = 720.0, 520.0
    local px, py = sw * 0.5 - panel_w * 0.5, sh * 0.5 - panel_h * 0.5
    -- Capture clicks so they don't fall through to intro buttons underneath.
    runtime_ui.set_quad("__scene_ui", "load_pick_bg", {
        x = px, y = py, width = panel_w, height = panel_h,
        fill = { 0.05, 0.06, 0.09, 0.96 }, border = { 0.96, 0.74, 0.22, 0.95 },
        bring_to_front = true,
    })
    runtime_ui.set_quad("__scene_ui", "load_pick_title", {
        x = px + 40.0, y = py + 28.0, width = panel_w - 80.0, height = 56.0,
        label = for_new and T("CHOOSE SAVE SLOT") or T("LOAD SAVE"),
        style = "text", align_h = "center", align_v = "middle",
        fill = { 0, 0, 0, 0 }, text_color = { 0.98, 0.92, 0.70, 1.0 },
        font_scale = 1.4, no_input = true, bring_to_front = true,
    })
    local by = py + 110.0
    for i = 1, P.SLOT_COUNT do
        local filled = P.exists(i)
        local enabled = for_new or filled
        runtime_ui.set_quad("__scene_ui", "load_slot_" .. i, {
            x = px + 60.0, y = by, width = panel_w - 120.0, height = 72.0,
            title = P.slot_label(i, for_new and filled), style = "button",
            fill = enabled and { 0.12, 0.14, 0.17, 0.96 } or { 0.08, 0.08, 0.10, 0.75 },
            border = enabled and { 0.96, 0.74, 0.22, 0.95 } or { 0.40, 0.40, 0.44, 0.70 },
            accent = { 0.96, 0.74, 0.22, 1.0 },
            text_color = enabled and { 0.97, 0.98, 1.0, 1.0 } or { 0.55, 0.56, 0.60, 0.85 },
            font_scale = 1.05, align_h = "center", align_v = "middle",
            no_input = not enabled, bring_to_front = true,
        })
        by = by + 90.0
    end
    runtime_ui.set_quad("__scene_ui", "load_pick_back", {
        x = px + 60.0, y = py + panel_h - 92.0, width = panel_w - 120.0, height = 64.0,
        title = T("BACK"), style = "button",
        fill = { 0.10, 0.10, 0.14, 0.95 }, border = { 0.50, 0.52, 0.60, 0.9 },
        accent = { 0.70, 0.72, 0.80, 1.0 }, text_color = { 0.95, 0.96, 1.0, 1.0 },
        font_scale = 1.05, align_h = "center", align_v = "middle",
        bring_to_front = true,
    })
end

local function begin_new_game_in_slot(slot)
    local P = profile()
    if not P then return end
    slot = P.set_active(slot)
    local r = run()
    r.save_slot = slot
    r.new_game = true -- Profile.load skips stale data; first save_profile writes fresh
    r.battlefield = "arena"
    log("new game slot=" .. tostring(slot))
    go("hero_select.pescene")
end

local function poll_slot_picker()
    if not picker_mode or not runtime_ui then return end
    -- Quads store click in get_state; runtime_ui.consume_click only works for Button widgets.
    local function clicked(id)
        local st = runtime_ui.get_state and runtime_ui.get_state("__scene_ui", id)
        return st and st.clicked
    end
    if clicked("load_pick_back") then
        hide_slot_picker()
        return
    end
    local P = profile()
    if not P then return end
    for i = 1, P.SLOT_COUNT do
        if clicked("load_slot_" .. i) then
            if picker_mode == "new" then
                hide_slot_picker()
                begin_new_game_in_slot(i)
                return
            elseif P.exists(i) then
                hide_slot_picker()
                enter_game_from_slot(i)
                return
            end
        end
    end
end

local function apply_locale()
    local I = i18n()
    if not (I and scene and scene.find_model) then return end
    if scene.find_model("UI Ranger") then
        I.apply_menu_scene("hero_select")
    elseif scene.find_model("UI Play") then
        I.apply_menu_scene("intro")
        refresh_intro_buttons()
    end
    if _G.ATH_HUB_SETTINGS and _G.ATH_HUB_SETTINGS.refresh then
        pcall(_G.ATH_HUB_SETTINGS.refresh, _G.ATH_ACTIVE_DUEL)
    end
end

local function pick_hero(index, name)
    local P = profile()
    local r = run()
    r.hero_index = index
    r.battlefield = "arena"
    -- Slot was chosen on the New Game picker; fall back if skipped.
    local slot = r.save_slot
        or (P and P.first_empty and P.first_empty())
        or (P and P.active_slot and P.active_slot())
        or 1
    if P and P.set_active then P.set_active(slot) end
    r.save_slot = slot
    r.new_game = true
    log(string.format("hero = %s slot=%d", name, slot))
    go("game.pescene")
end

-- intro --------------------------------------------------------------------
function on_play()
    hide_slot_picker()
    picker_mode = "new"
    draw_slot_picker()
end

function on_continue()
    hide_slot_picker()
    local P = profile()
    if not (P and P.any_exists and P.any_exists()) then
        log("continue: no save")
        return
    end
    local slot = (P.last_played_slot and P.last_played_slot()) or P.active_slot()
    if not P.exists(slot) then
        for i = 1, P.SLOT_COUNT do
            if P.exists(i) then slot = i; break end
        end
    end
    enter_game_from_slot(slot)
end

-- Back-compat: old intro scenes still bind UI Load → on_load.
function on_load() on_continue() end

function on_load_pick()
    local P = profile()
    if not (P and P.any_exists and P.any_exists()) then
        log("load: no saves")
        return
    end
    picker_mode = "load"
    draw_slot_picker()
end

function on_quit()
    hide_slot_picker()
    if engine and engine.set_play_mode and engine.is_play_mode and engine.is_play_mode() then
        engine.set_play_mode(false)
        return
    end
    if engine and engine.quit then engine.quit() end
end

function on_lang_en()
    local I = i18n()
    if I then I.set_lang("en") end
    apply_locale()
    if picker_mode then draw_slot_picker() end
end

function on_lang_el()
    local I = i18n()
    if I then I.set_lang("el") end
    apply_locale()
    if picker_mode then draw_slot_picker() end
end

function on_damage_text()
    local I = i18n()
    if I then I.toggle_damage_text() end
    apply_locale()
end

-- hero_select: index into arena config.hero.classes → straight into game.
function on_pick_ranger() pick_hero(1, "ranger") end
function on_pick_brawler() pick_hero(2, "brawler") end
function on_pick_sower() pick_hero(3, "sower") end
function on_pick_mage() pick_hero(4, "mage") end
function on_pick_rogue() pick_hero(5, "rogue") end
function on_pick_warrior() pick_hero(6, "warrior") end
function on_pick_necromancer() pick_hero(7, "necromancer") end

-- back navigation ----------------------------------------------------------
function on_back_intro()
    hide_slot_picker()
    local r = run()
    r.new_game = nil
    go("intro.pescene")
end

hooks {
    init = function()
        profile() -- migrate legacy save + cache ATH_PROFILE
        apply_locale()
        refresh_intro_buttons()
    end,
    update = function()
        if _G.ATH_FLUSH_SCENE then _G.ATH_FLUSH_SCENE() end
        if picker_mode then
            -- Poll first: click state is from last frame's BuildFrame; redraw after.
            poll_slot_picker()
            if picker_mode then draw_slot_picker() end
        end
    end,
}
