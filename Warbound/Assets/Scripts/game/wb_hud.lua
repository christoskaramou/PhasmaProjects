-- wb_hud — the on-screen command interface.
--
-- The HUD PANELS are authored in the scene hierarchy as runtime_ui nodes
-- (HUD_Minimap / HUD_Portrait / HUD_Command / HUD_Resources / HUD_Fps /
-- HUD_Objective; see tools/build_hud.py). This module ADOPTS them: it reads each
-- panel's laid-out screen rect via node:get_ui_rect() and draws the DYNAMIC content
-- inside it (minimap dots, portrait + bars, command buttons), and drives the text
-- panels (resources / fps / objective) via node:set_ui(). Floating health bars and
-- the drag-select rectangle are world/screen overlays. Dynamic widgets are tracked
-- so stale ones (a dead unit's dot/bar) are removed.

local U = WB.util
local Camera = WB.camera
local World = WB.world

local Hud = {}
local SCREEN = "hud"

-- Fully-transparent color, shared. The engine reads color tables by value and never
-- retains them, so one constant serves every widget instead of allocating a fresh
-- table per color field per widget per frame.
local CLEAR = { 0, 0, 0, 0 }
local EMPTY = {}
local NO_INPUT = { no_input = true }
local BAR_BG = { 0.04, 0.05, 0.06, 0.95 }
local BAR_BG_OPTS = { border = { 0.2, 0.2, 0.24, 0.95 }, no_input = true }
local LABEL_OPTS = { label = "", font_scale = 0.95, no_input = true }
local TEXT_OPTS = { body = "", font_scale = 1.0, no_input = true }
local BTN_OPTS = { title = "", body = "", font_scale = 1.0 }
local SET_UI = { body = "", text_color = nil }
local PORT_FACE_OPTS = { border = U.COLOR.panel_edge, no_input = true }
local FACE_FILL = { 0, 0, 0, 1 }
local TRAIN_WHY = { gold = "need gold", lumber = "need lumber", food = "need food", reserve = "no reserve" }
local FACTIONS = U.FACTIONS
local BUILD_KEYS = { "farm", "barracks", "tower", "town_hall" }
local MM_BG = { 0.12, 0.16, 0.10, 1.0 }
local FILL_STOP = { 0.15, 0.13, 0.13, 0.95 }
local FILL_HOLD = { 0.13, 0.15, 0.13, 0.95 }
local FILL_BTN = { 0.12, 0.14, 0.18, 0.95 }
local FILL_TRAIN_OK = { 0.16, 0.2, 0.16, 0.95 }
local FILL_TRAIN_NO = { 0.12, 0.12, 0.14, 0.95 }
local FILL_BLD_OK = { 0.14, 0.18, 0.14, 0.95 }
local FILL_MOVE = { 0.10, 0.12, 0.16, 0.9 }
local FILL_ATK = { 0.16, 0.11, 0.11, 0.9 }
local FILL_AB_OK = { 0.16, 0.14, 0.22, 0.95 }
local FILL_AB_NO = { 0.10, 0.10, 0.12, 0.95 }
local FILL_PLACE = { 0.05, 0.08, 0.05, 0.92 }
local PLACE_OPTS = { body = "Left-click to place — right-click to cancel", font_scale = 1.05,
    align = "center", no_input = true, border = { 0.3, 0.6, 0.3, 0.9 } }
local OPT_MOVE = { title = "Move", body = "right-click", font_scale = 0.85, no_input = true, align = "center" }
local OPT_ATK = { title = "Attack", body = "rt-clk foe", font_scale = 0.85, no_input = true, align = "center" }
local OPT_EMPTY = { body = "No unit selected", font_scale = 1.1, no_input = true }
local OPT_HINT = { body = "Select a unit or building\n(left-click / drag)", font_scale = 1.0, no_input = true }
local HIT_OPTS = { border = CLEAR }
local RALLY_COL = { 0.2, 0.9, 0.3, 1.0 }
local RALLY_RING = { 0.2, 0.9, 0.3, 0.85 }
local RALLY_RING_IDS = {}
for i = 0, 7 do RALLY_RING_IDS[i] = "rally_ring" .. i end
local SELBOX_COL = { 0.4, 0.95, 0.5, 0.9 }
local HP_BG = { 0.02, 0.02, 0.03, 0.9 }
local HP_BG_B = { 0.02, 0.02, 0.03, 0.92 }
local XP_COL = { 0.7, 0.5, 0.95 }
local SITE_COL = { 0.45, 0.70, 0.95 }
local HEAD_SKIN = { 0.95, 0.92, 0.85, 1.0 }
local BLD_FACE = { 0.5, 0.52, 0.6, 1.0 }
-- Engine ReadQuadOptions copies this table into C++ each call; mutating in place is safe
-- and avoids a payload alloc per widget per frame.
local PAYLOAD = {
    x = 0, y = 0, width = 0, height = 0,
    style = "panel", title = "", body = "",
    fill = CLEAR, border = CLEAR, accent = CLEAR,
    text_color = nil, font_scale = 1.0, align_h = "left",
    no_input = true, selected = nil,
}

local sw, sh, uiscale = 1920.0, 1080.0, 1.0
local dyn_now = {}
local dyn_prev = {}
local shown = false
local last_text = {}

local function mark(id) dyn_now[id] = true end

local function face_fill(col)
    FACE_FILL[1], FACE_FILL[2], FACE_FILL[3] = col[1], col[2], col[3]
    return FACE_FILL
end

local function text_opts(body, scale, align)
    TEXT_OPTS.body = body
    TEXT_OPTS.font_scale = scale or 1.0
    TEXT_OPTS.align = align
    return TEXT_OPTS
end

local function refresh_surface()
    if runtime_ui and runtime_ui.get_surface_size then
        local s = runtime_ui.get_surface_size()
        if s and s.width and s.width > 0 then sw, sh = s.width, s.height end
        if s and s.ui_scale and s.ui_scale > 0 then uiscale = s.ui_scale end
    end
end

-- Immediate quad on the overlay screen (dynamic content drawn over authored panels).
local function push_quad(id, x, y, w, h, fill, opts, clickable)
    opts = opts or EMPTY
    mark(id)
    PAYLOAD.x, PAYLOAD.y, PAYLOAD.width, PAYLOAD.height = x, y, w, h
    PAYLOAD.style = opts.style or "panel"
    PAYLOAD.title = U.ascii(opts.title or "")
    PAYLOAD.body = U.ascii(opts.body or opts.label or "")
    PAYLOAD.fill = fill or CLEAR
    PAYLOAD.border = opts.border or (clickable and U.COLOR.panel_edge or CLEAR)
    PAYLOAD.accent = CLEAR
    PAYLOAD.text_color = opts.text_color or U.COLOR.ink
    PAYLOAD.font_scale = (opts.font_scale or 1.0) / (uiscale or 1.0)
    PAYLOAD.align_h = opts.align or (clickable and "center" or "left")
    PAYLOAD.no_input = clickable and false or (opts.no_input ~= false)
    PAYLOAD.selected = opts.selected
    runtime_ui.set_quad(SCREEN, id, PAYLOAD)
end

local function quad(id, x, y, w, h, fill, opts)
    if not (runtime_ui and runtime_ui.set_quad) then return end
    push_quad(id, x, y, w, h, fill, opts, false)
end

local function button(id, x, y, w, h, fill, opts)
    if not (runtime_ui and runtime_ui.set_quad) then return false end
    push_quad(id, x, y, w, h, fill, opts, true)
    local st = runtime_ui.get_state and runtime_ui.get_state(SCREEN, id) or nil
    return st and st.clicked == true, st
end

local function bar(id, x, y, w, h, pct, color, label)
    pct = U.clamp(pct or 0.0, 0.0, 1.0)
    quad(id .. "_bg", x, y, w, h, BAR_BG, BAR_BG_OPTS)
    quad(id .. "_fg", x, y, math.max(0.0, w * pct), h, color, NO_INPUT)
    if label then
        LABEL_OPTS.label = label
        quad(id .. "_tx", x, y - h * 0.15, w, h, CLEAR, LABEL_OPTS)
    end
end

-- ---- authored panel nodes -----------------------------------------------------

-- Adopted panel nodes, keyed by suffix (HUD_<key>). Found once from the scene.
local nodes = nil
local function adopt()
    if nodes then return end
    nodes = {}
    if scene and scene.find_model then
        for _, k in ipairs({ "Minimap", "Portrait", "Command", "Resources", "Fps", "Objective" }) do
            nodes[k] = scene.find_model("HUD_" .. k)
        end
    end
end

-- HUD panel rects (surface px), so the camera can suppress edge-scroll over them.
local panels = {}
local panel_n = 0
local function add_panel(x, y, w, h)
    panel_n = panel_n + 1
    local r = panels[panel_n]
    if r then r[1], r[2], r[3], r[4] = x, y, w, h
    else panels[panel_n] = { x, y, w, h } end
end

-- The laid-out screen rect of an authored panel, or a fallback rect if it isn't
-- ready. Registers the rect as a HUD region (for edge-scroll suppression).
local function panel_rect(key, fx, fy, fw, fh)
    local n = nodes and nodes[key]
    if n and n.get_ui_rect then
        local r = n:get_ui_rect()
        if r and r.w and r.w > 0 then fx, fy, fw, fh = r.x, r.y, r.w, r.h end
    end
    add_panel(fx, fy, fw, fh)
    return fx, fy, fw, fh
end

-- Update an authored text panel's content (and register its rect).
local function drive_text(key, body, text_color, fx, fy, fw, fh)
    local n = nodes and nodes[key]
    if n and n.set_ui and last_text[key] ~= body then
        last_text[key] = body
        SET_UI.body = U.ascii(body)
        SET_UI.text_color = text_color
        n:set_ui(SET_UI)
    end
    panel_rect(key, fx, fy, fw, fh)
end

function Hud.point_in_ui(mx, my, ww, wh)
    if not (mx and ww and ww > 0 and wh and wh > 0) then return false end
    local sx = mx * (sw / ww)
    local sy = my * (sh / wh)
    for i = 1, #panels do
        local r = panels[i]
        if sx >= r[1] and sx <= r[1] + r[3] and sy >= r[2] and sy <= r[2] + r[4] then return true end
    end
    return false
end

-- ---- minimap (dots drawn inside the authored HUD_Minimap panel) ----------------

local mm_x, mm_y, mm_w, mm_h, mm_b, mm_rx, mm_rz = 0, 0, 1, 1, World.bounds, 1, 1
local function plot(id, wx, wz, col, size)
    local px = mm_x + ((wx - mm_b.min_x) / mm_rx) * mm_w
    local py = mm_y + ((wz - mm_b.min_z) / mm_rz) * mm_h
    quad(id, px - size * 0.5, py - size * 0.5, size, size, col, NO_INPUT)
end

local function draw_minimap(state)
    local M = 20.0
    local x, y, w, h = panel_rect("Minimap", M, sh - M - 300, 300, 300)
    local pad = w * 0.05
    mm_x, mm_y, mm_w, mm_h = x + pad, y + pad, w - pad * 2, h - pad * 2
    quad("mm_bg", mm_x, mm_y, mm_w, mm_h, MM_BG, NO_INPUT)

    mm_b = World.bounds
    mm_rx, mm_rz = (mm_b.max_x - mm_b.min_x), (mm_b.max_z - mm_b.min_z)
    plot("mm_mine", World.mine.x, World.mine.z, U.COLOR.gold, 7)
    if World.forest then plot("mm_forest", World.forest.x, World.forest.z, U.COLOR.tree_leaf, 7) end
    local PE_b = state.econ and state.econ.player
    for _, b in ipairs(PE_b and PE_b.buildings or {}) do
        if b.alive then plot(b.hud_mm or ("mm_b" .. (b.id or 0)), b.x, b.z, U.COLOR.player_trim, 9) end
    end
    local EE_b = state.econ and state.econ.enemy
    for _, b in ipairs(EE_b and EE_b.buildings or {}) do
        if b.alive then plot(b.hud_mm or ("mm_eb" .. (b.id or 0)), b.x, b.z, U.COLOR.enemy, 9) end
    end
    for _, e in ipairs(state.enemy_units) do
        if e.alive then plot(e.hud_mm or ("mm_e" .. e.id), e.x, e.z, U.COLOR.enemy, 5) end
    end
    for _, u in ipairs(state.player_units) do
        if u.alive then plot(u.hud_mm or ("mm_p" .. u.id), u.x, u.z, u.is_hero and U.COLOR.hero_trim or U.COLOR.player, u.is_hero and 7 or 5) end
    end

    -- click-to-recenter hit area (clear fill/border so it doesn't paint over dots)
    push_quad("mm_click", mm_x, mm_y, mm_w, mm_h, CLEAR, HIT_OPTS, true)
    local st = runtime_ui.get_state and runtime_ui.get_state(SCREEN, "mm_click")
    if st and st.clicked and st.mouse_x then
        local u = U.clamp((st.mouse_x - mm_x) / mm_w, 0.0, 1.0)
        local v = U.clamp((st.mouse_y - mm_y) / mm_h, 0.0, 1.0)
        Camera.center_on(mm_b.min_x + u * mm_rx, mm_b.min_z + v * mm_rz)
    end
end

-- ---- selected-unit portrait (inside the authored HUD_Portrait panel) -----------

local function draw_portrait(state)
    local M = 20.0
    local x, y, w, h = panel_rect("Portrait", M * 2 + 300, sh - M - 300, 560, 300)
    local sel = WB.selection.list
    local pad = 14.0

    -- Resource node selected: show what's left to gather.
    local nsel = WB.selection.node
    if nsel then
        local label = (nsel.kind == "gold") and "Gold Mine" or "Lumber Grove"
        local col = (nsel.kind == "gold") and U.COLOR.gold or U.COLOR.tree_leaf
        local face = h * 0.42
        quad("port_face", x + pad, y + pad, face, face, face_fill(col), PORT_FACE_OPTS)
        local tx = x + pad + face + 14.0
        local tw = w - pad - (tx - x)
        quad("port_name", tx, y + pad, tw, 30.0, CLEAR,
            text_opts(label .. "  (" .. (nsel.faction == "player" and "yours" or "Wilds") .. ")", 1.2))
        local pct = (nsel.max > 0) and (nsel.amount / nsel.max) or 0.0
        bar("port_node", tx, y + pad + 44.0, tw, 30.0, pct, col,
            string.format("%d / %d left", math.floor(nsel.amount + 0.5), math.floor(nsel.max + 0.5)))
        quad("port_stats", x + pad, y + h - 38.0, w - pad * 2, 30.0, CLEAR,
            text_opts((nsel.amount <= 0) and "Depleted" or "", 1.0))
        return
    end

    local bsel = WB.selection.building
    if bsel then
        local face = h * 0.42
        quad("port_face", x + pad, y + pad, face, face, BLD_FACE, PORT_FACE_OPTS)
        quad("port_head", x + pad + face * 0.22, y + pad + face * 0.5, face * 0.56, face * 0.3, U.COLOR.roof, NO_INPUT)
        local tx = x + pad + face + 14.0
        local tw = w - pad - (tx - x)
        quad("port_name", tx, y + pad, tw, 30.0, CLEAR, text_opts(bsel.display, 1.2))
        local hp_pct = (bsel.hp or 1) / (bsel.hp_max or 1)
        bar("port_hp", tx, y + pad + 44.0, tw, 30.0, hp_pct, U.COLOR.hp_good,
            string.format("%d / %d", math.floor((bsel.hp or 0) + 0.5), math.floor((bsel.hp_max or 0) + 0.5)))
        local foodtxt = (bsel.food_cap or 0) > 0 and string.format("Supplies %d food", bsel.food_cap) or ""
        quad("port_stats", x + pad, y + h - 38.0, w - pad * 2, 30.0, CLEAR, text_opts(foodtxt, 1.0))
        return
    end

    if #sel == 0 then
        quad("port_empty", x + pad, y + pad, w - pad * 2, h * 0.18, CLEAR, OPT_EMPTY)
        return
    end

    local u = sel[1]
    local face = h * 0.42
    local col = u.is_hero and U.COLOR.hero or (u.faction == "player" and U.COLOR.player or U.COLOR.enemy)
    quad("port_face", x + pad, y + pad, face, face, face_fill(col), PORT_FACE_OPTS)
    quad("port_head", x + pad + face * 0.3, y + pad + face * 0.22, face * 0.4, face * 0.4, HEAD_SKIN, NO_INPUT)

    local tx = x + pad + face + 14.0
    local tw = w - pad - (tx - x)
    local namestr = u.display .. (u.is_hero and ("  Lv " .. (u.level or 1)) or "")
    if #sel > 1 then namestr = namestr .. "   (+" .. (#sel - 1) .. ")" end
    quad("port_name", tx, y + pad, tw, 30.0, CLEAR, text_opts(namestr, 1.2))

    local by = y + pad + 44.0
    local hp_pct = u.hp / u.hp_max
    local hp_col = hp_pct > 0.5 and U.COLOR.hp_good or (hp_pct > 0.25 and U.COLOR.hp_warn or U.COLOR.hp_low)
    bar("port_hp", tx, by, tw, 30.0, hp_pct, hp_col,
        string.format("%d / %d", math.floor(u.hp + 0.5), math.floor(u.hp_max + 0.5)))
    if u.is_hero then
        bar("port_mp", tx, by + 42.0, tw, 24.0, (u.mana or 0) / (u.mana_max or 1), U.COLOR.mana,
            string.format("Mana %d / %d", math.floor(u.mana or 0), math.floor(u.mana_max or 0)))
        bar("port_xp", tx, by + 78.0, tw, 16.0, (u.xp or 0) / (u.xp_to_level or 1), XP_COL, nil)
    end
    quad("port_stats", x + pad, y + h - 38.0, w - pad * 2, 30.0, CLEAR,
        text_opts(string.format("Damage %d    Armor %d%%", math.floor(u.dps + 0.5), math.floor((u.armor or 0) * 100 + 0.5)), 1.0))
end

-- ---- command card (buttons inside the authored HUD_Command panel) --------------

local cc_x, cc_y, cc_bw, cc_bh, cc_pad = 0, 0, 1, 1, 0
local CC_ID = {}
local function slot(c, r)
    return cc_x + cc_pad + c * (cc_bw + cc_pad), cc_y + cc_pad + r * (cc_bh + cc_pad)
end
local function btn(c, r, id, label, sub, fill)
    local bx, by = slot(c, r)
    local wid = CC_ID[id]
    if not wid then wid = "cc_" .. id; CC_ID[id] = wid end
    BTN_OPTS.title, BTN_OPTS.body = label, sub or ""
    return button(wid, bx, by, cc_bw, cc_bh, fill or FILL_BTN, BTN_OPTS)
end

local function draw_command_card(state)
    local M = 20.0
    local x, y, w, h = panel_rect("Command", sw - M - 560, sh - M - 300, 560, 300)
    local sel = WB.selection.list

    local cols, rows = 4, 3
    cc_pad = w * 0.02
    cc_bw = (w - cc_pad * (cols + 1)) / cols
    cc_bh = (h - cc_pad * (rows + 1)) / rows
    cc_x, cc_y = x, y

    -- Resource node selected: no commands, just the remaining amount (portrait shows the bar).
    local nsel = WB.selection.node
    if nsel then
        quad("cc_node", x + cc_pad, y + cc_pad, w - cc_pad * 2, h - cc_pad * 2, CLEAR,
            text_opts(string.format("%s\n%d / %d left",
                (nsel.kind == "gold") and "Gold Mine" or "Lumber Grove",
                math.floor(nsel.amount + 0.5), math.floor(nsel.max + 0.5)), 1.1, "center"))
        return
    end

    -- Building command card: a train button + queue progress (mutually exclusive
    -- with unit selection — see wb_selection).
    local bsel = WB.selection.building
    if bsel then
        -- Construction-site progress bar: shown while the building is under construction.
        if bsel.state == "site" and bsel.build_total and bsel.build_total > 0 then
            local pct = U.clamp(1.0 - (bsel.build_t or 0) / bsel.build_total, 0.0, 1.0)
            local bx, by = slot(0, 0)
            bar("cc_site", bx, by + cc_bh * 0.1, w - cc_pad * 2, cc_bh * 0.6, pct, U.COLOR.player,
                string.format("Building... %d%%", math.floor(pct * 100 + 0.5)))
            return
        end

        local def = WB.economy and WB.economy.train_def and WB.economy.train_def(bsel.trains)
        if def then
            local PE = state.econ and state.econ.player
            local status = WB.economy.train_status(state, PE, bsel)
            local fill = (status == "ok") and FILL_TRAIN_OK or FILL_TRAIN_NO
            if btn(0, 0, "train", def.label, def.cost_label or "", fill) then WB.economy.try_train(state, PE, bsel) end
            local why = TRAIN_WHY[status]
            if why then
                local wx, wy = slot(1, 0)
                quad("cc_why", wx, wy, cc_bw, cc_bh, CLEAR, text_opts(why, 0.9, "center"))
            end
            if bsel.queue and #bsel.queue > 0 then
                local j = bsel.queue[1]
                local pct = 1.0 - U.clamp((j.t or 0) / (j.total or 1), 0.0, 1.0)
                local bx, by = slot(0, 2)
                bar("cc_q", bx, by + cc_bh * 0.2, w - cc_pad * 2, cc_bh * 0.5, pct, U.COLOR.player,
                    string.format("Training... %d%%   (%d in queue)", math.floor(pct * 100 + 0.5), #bsel.queue))
            end
        else
            quad("cc_bhint", x + cc_pad, y + cc_pad, w - cc_pad * 2, h - cc_pad * 2, CLEAR,
                text_opts(bsel.display, 1.1, "center"))
        end
        return
    end

    if #sel == 0 then
        quad("cc_hint", x + cc_pad, y + cc_pad, w - cc_pad * 2, h - cc_pad * 2, CLEAR, OPT_HINT)
        return
    end

    if btn(0, 0, "stop", "Stop", "S", FILL_STOP) then WB.orders.stop(sel) end
    if btn(1, 0, "hold", "Hold", "H", FILL_HOLD) then WB.orders.hold(sel) end
    if sel[1] and sel[1].arch_is_worker then
        local i = 0
        for _, key in ipairs(BUILD_KEYS) do
            local def = WB.build and WB.build.DEFS and WB.build.DEFS[key]
            if def then
                local PE = state.econ and state.econ.player
                local status = (WB.build.status and WB.build.status(PE, key)) or "ok"
                local ok = (status == "ok")
                local fill = ok and FILL_BLD_OK or FILL_TRAIN_NO
                local sub = (status == "reserve") and "none left" or def.cost_label
                local c, r = i % 4, 1 + math.floor(i / 4)
                if btn(c, r, "bld_" .. key, def.label, sub, fill) then
                    if ok then WB.build.begin(state, PE, key, sel) end
                end
                i = i + 1
            end
        end
    end
    local mx, my = slot(2, 0)
    quad("cc_move", mx, my, cc_bw, cc_bh, FILL_MOVE, OPT_MOVE)
    local ax, ay = slot(3, 0)
    quad("cc_atk", ax, ay, cc_bw, cc_bh, FILL_ATK, OPT_ATK)

    local hero = sel[1]
    if hero and hero.is_hero then
        for i, a in ipairs(WB.abilities.LIST) do
            local status, cd = WB.abilities.status(hero, a.id)
            local fill = (status == "ready") and FILL_AB_OK or FILL_AB_NO
            local sub = a.letter
            if status == "cooldown" then sub = string.format("%.0fs", cd or 0)
            elseif status == "mana" then sub = "no mana" end
            if btn(i - 1, 2, "ab_" .. a.id, a.name, sub, fill) then WB.abilities.try_cast(state, a.id) end
        end
    end
end

-- ---- resources / fps / objective (authored text panels, driven via set_ui) -----

local function drive_top(state)
    local M = 20.0
    local PE = state.econ and state.econ.player
    local food = string.format("%d/%d", state.player_alive, PE and PE.food_cap or 12)
    drive_text("Resources",
        string.format("Gold %d   Lumber %d   Food %s", PE and PE.gold or 0, PE and PE.lumber or 0, food),
        U.COLOR.gold, sw - M - 440, M, 440, 70)

    local fps = 0
    if engine and engine.get_metrics then
        local m = engine.get_metrics()
        if m then fps = m.fps or (m.delta_ms and m.delta_ms > 0 and 1000.0 / m.delta_ms) or 0 end
    end
    Hud._fps = Hud._fps and (Hud._fps * 0.9 + fps * 0.1) or fps
    drive_text("Fps", string.format("FPS %d", math.floor((Hud._fps or 0) + 0.5)),
        U.COLOR.hp_good, sw - M * 2 - 440 - 150, M, 150, 70)

    local msg, ccol
    if state.result == "win" then
        msg, ccol = "VICTORY  -  the Wilds camp is broken!   (press R)", { 0.5, 0.95, 0.55, 1.0 }
    elseif state.result == "lose" then
        msg, ccol = "DEFEAT  -  your warband has fallen.   (press R)", { 0.95, 0.45, 0.4, 1.0 }
    else
        msg, ccol = string.format("Raze the Wilds' Great Hall   -   %d enemy halls, %d foes",
            state.enemy_halls or 0, state.enemy_alive), U.COLOR.ink
    end
    drive_text("Objective", msg, ccol, sw * 0.5 - 500, M, 1000, 70)
end

-- ---- floating health bars + selection box (screen overlays) --------------------

local function floating_unit_hp(u, always)
    if not u.alive then return end
    if not always and u.hp >= u.hp_max then return end
    local top = (u.is_hero and 2.3) or (u.arch == "wolf" and 1.2 or 1.9)
    local px, py, depth = Camera.world_to_screen(u.x, top, u.z)
    if not px or not depth or depth <= 0 then return end
    if px < -60 or px > sw + 60 or py < -30 or py > sh then return end
    local w = (u.is_hero and 64 or 42)
    local pct = u.hp / u.hp_max
    local col = u.faction == "player" and U.COLOR.hp_good or U.COLOR.hp_low
    if pct <= 0.3 then col = U.COLOR.hp_low elseif pct <= 0.6 and u.faction == "player" then col = U.COLOR.hp_warn end
    local bg, fg = u.hud_fh_bg or ("fh" .. u.id .. "_bg"), u.hud_fh_fg or ("fh" .. u.id .. "_fg")
    quad(bg, px - w * 0.5 - 1, py - 7, w + 2, 7, HP_BG, NO_INPUT)
    quad(fg, px - w * 0.5, py - 6, w * pct, 5, col, NO_INPUT)
end

local function draw_floating_hp(state)
    for _, e in ipairs(state.enemy_units) do floating_unit_hp(e, true) end
    for _, u in ipairs(state.player_units) do floating_unit_hp(u, u.selected) end
end

-- Floating HP bar over a building. Buildings live in E.buildings (not *_units), so
-- draw_floating_hp never touches them; this handles them. Shown when the building is
-- selected, damaged, or under construction (a blue progress bar for sites).
local BUILDING_BAR_TOP = {
    town_hall = 6.4, enemy_town_hall = 6.4,
    barracks = 3.8,  enemy_barracks = 3.8,
    tower = 5.6,     enemy_tower = 5.6,
    farm = 2.2,      enemy_farm = 2.2,
}
local function building_hp(b, sel)
    if not (b.alive and b.hp_max and b.hp_max > 0) then return end
    local selected = (b == sel)
    local site = (b.state == "site")
    local damaged = b.hp < b.hp_max
    if not (selected or site or damaged) then return end
    local top = BUILDING_BAR_TOP[b.arch] or ((b.radius or 2.0) + 2.5)
    local px, py, depth = Camera.world_to_screen(b.x, top, b.z)
    if not px or not depth or depth <= 0 then return end
    if px < -80 or px > sw + 80 or py < -30 or py > sh then return end
    local w = 72
    local pct, col
    if site then
        pct = U.clamp(1.0 - (b.build_t or 0) / (b.build_total or 1), 0.0, 1.0)
        col = SITE_COL
    else
        pct = b.hp / b.hp_max
        col = (b.faction == "player") and U.COLOR.hp_good or U.COLOR.hp_low
        if pct <= 0.3 then col = U.COLOR.hp_low
        elseif pct <= 0.6 and b.faction == "player" then col = U.COLOR.hp_warn end
    end
    local bg, fg = b.hud_bh_bg or ("bh" .. (b.id or 0) .. "_bg"), b.hud_bh_fg or ("bh" .. (b.id or 0) .. "_fg")
    quad(bg, px - w * 0.5 - 1, py - 8, w + 2, 8, HP_BG_B, NO_INPUT)
    quad(fg, px - w * 0.5, py - 7, math.max(0.0, w * pct), 6, col, NO_INPUT)
end

local function draw_building_hp(state)
    local sel = WB.selection and WB.selection.building
    for _, fac in ipairs(FACTIONS) do
        local E = state.econ and state.econ[fac]
        if E then for _, b in ipairs(E.buildings) do building_hp(b, sel) end end
    end
end

local function draw_select_box()
    local b = WB.selection.box
    if b.active then
        local x0, y0 = math.min(b.x0, b.x1), math.min(b.y0, b.y1)
        local w, h = math.abs(b.x1 - b.x0), math.abs(b.y1 - b.y0)
        local c = SELBOX_COL
        quad("selbox_t", x0, y0, w, 2, c, NO_INPUT)
        quad("selbox_b", x0, y0 + h, w, 2, c, NO_INPUT)
        quad("selbox_l", x0, y0, 2, h, c, NO_INPUT)
        quad("selbox_r", x0 + w, y0, 2, h, c, NO_INPUT)
    end
end

-- ---- rally marker (minimap dot + world-projected ring for selected building) ---

local function draw_rally(state)
    local b = WB.selection and WB.selection.building
    if not (b and b.rally_set) then return end
    if mm_rx > 0 and mm_rz > 0 then
        plot("rally_mm", b.rally_x, b.rally_z, RALLY_COL, 8)
    end

    -- World-projected thin ring: 8-segment approximation around the rally point.
    local sx, sy = Camera.world_to_screen(b.rally_x, 0.3, b.rally_z)
    if sx then
        local R = 14.0
        local segs = 8
        local thick = 2.0
        for i = 0, segs - 1 do
            local a0 = (i / segs) * math.pi * 2
            local a1 = ((i + 0.5) / segs) * math.pi * 2
            local qx = sx + math.cos(a0) * R
            local qy = sy + math.sin(a0) * R
            local dx = math.cos(a1) * R - math.cos(a0) * R
            local dz = math.sin(a1) * R - math.sin(a0) * R
            local seg_len = math.sqrt(dx * dx + dz * dz)
            quad(RALLY_RING_IDS[i], qx, qy, math.max(seg_len, thick), thick, RALLY_RING, NO_INPUT)
        end
    end
end

-- ---- main ---------------------------------------------------------------------

-- Reset per-session HUD state. The module persists across an editor Play->Stop->Play, so
-- without this the overlay is never re-shown on the 2nd Play (`shown` stays true) and the
-- cached authored-panel handles (`nodes`) point at the pre-snapshot scene — leaving the
-- whole HUD blank. Called from Game.init.
function Hud.reset()
    shown = false
    nodes = nil
    dyn_now = {}
    dyn_prev = {}
    last_text = {}
    panel_n = 0
    for i = #panels, 1, -1 do panels[i] = nil end
end

function Hud.update(state)
    if not (runtime_ui and runtime_ui.set_quad) then return end
    if not shown then
        shown = true
        if runtime_ui.set_screen_overlay then pcall(runtime_ui.set_screen_overlay, SCREEN, true) end
        if runtime_ui.set_visible then pcall(runtime_ui.set_visible, SCREEN, true) end
        if runtime_ui.show then pcall(runtime_ui.show, SCREEN) end
    end
    adopt()
    refresh_surface()
    for k in pairs(dyn_now) do dyn_now[k] = nil end
    panel_n = 0

    draw_minimap(state)
    draw_portrait(state)
    draw_command_card(state)
    drive_top(state)

    -- Placement banner: shown while the player is in build-placement mode.
    if WB.build and WB.build.is_placing and WB.build.is_placing() then
        local bw, bh2 = 540.0, 44.0
        quad("place_banner", sw * 0.5 - bw * 0.5, sh * 0.5 - 120.0, bw, bh2, FILL_PLACE, PLACE_OPTS)
    end
    draw_floating_hp(state)
    draw_building_hp(state)
    draw_select_box()
    draw_rally(state)

    for i = #panels, panel_n + 1, -1 do panels[i] = nil end
    for id in pairs(dyn_prev) do
        if not dyn_now[id] then runtime_ui.remove(SCREEN, id) end
    end
    dyn_prev, dyn_now = dyn_now, dyn_prev
end

return Hud
