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

local sw, sh, uiscale = 1920.0, 1080.0, 1.0
local dyn_now = {}
local dyn_prev = {}
local shown = false

local function mark(id) dyn_now[id] = true end

local function refresh_surface()
    if runtime_ui and runtime_ui.get_surface_size then
        local s = runtime_ui.get_surface_size()
        if s and s.width and s.width > 0 then sw, sh = s.width, s.height end
        if s and s.ui_scale and s.ui_scale > 0 then uiscale = s.ui_scale end
    end
end

-- Immediate quad on the overlay screen (dynamic content drawn over authored panels).
local function quad(id, x, y, w, h, fill, opts)
    if not (runtime_ui and runtime_ui.set_quad) then return end
    opts = opts or {}
    mark(id)
    runtime_ui.set_quad(SCREEN, id, {
        x = x, y = y, width = w, height = h,
        style = opts.style or "panel",
        title = U.ascii(opts.title or ""),
        body = U.ascii(opts.body or opts.label or ""),
        fill = fill or { 0, 0, 0, 0 },
        border = opts.border or { 0, 0, 0, 0 },
        accent = { 0, 0, 0, 0 },
        text_color = opts.text_color or U.COLOR.ink,
        font_scale = (opts.font_scale or 1.0) / (uiscale or 1.0),
        align_h = opts.align or "left",
        no_input = (opts.no_input ~= false),
        selected = opts.selected,
    })
end

local function button(id, x, y, w, h, fill, opts)
    opts = opts or {}
    if not (runtime_ui and runtime_ui.set_quad) then return false end
    mark(id)
    runtime_ui.set_quad(SCREEN, id, {
        x = x, y = y, width = w, height = h,
        style = "panel",
        title = U.ascii(opts.title or ""),
        body = U.ascii(opts.body or ""),
        fill = fill, border = opts.border or U.COLOR.panel_edge,
        accent = { 0, 0, 0, 0 },
        text_color = opts.text_color or U.COLOR.ink,
        font_scale = (opts.font_scale or 1.0) / (uiscale or 1.0),
        align_h = "center",
        no_input = false,
    })
    local st = runtime_ui.get_state and runtime_ui.get_state(SCREEN, id) or nil
    return st and st.clicked == true, st
end

local function bar(id, x, y, w, h, pct, color, label)
    pct = U.clamp(pct or 0.0, 0.0, 1.0)
    quad(id .. "_bg", x, y, w, h, { 0.04, 0.05, 0.06, 0.95 }, { border = { 0.2, 0.2, 0.24, 0.95 }, no_input = true })
    quad(id .. "_fg", x, y, math.max(0.0, w * pct), h, color, { no_input = true })
    if label then
        quad(id .. "_tx", x, y - h * 0.15, w, h, { 0, 0, 0, 0 }, { label = label, font_scale = 0.95, no_input = true })
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
local function add_panel(x, y, w, h) panels[#panels + 1] = { x, y, w, h } end

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
    if n and n.set_ui then n:set_ui({ body = U.ascii(body), text_color = text_color }) end
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

local function draw_minimap(state)
    local M = 20.0
    local x, y, w, h = panel_rect("Minimap", M, sh - M - 300, 300, 300)
    local pad = w * 0.05
    local mx, my, mw, mh = x + pad, y + pad, w - pad * 2, h - pad * 2
    quad("mm_bg", mx, my, mw, mh, { 0.12, 0.16, 0.10, 1.0 }, { no_input = true })

    local b = World.bounds
    local rx, rz = (b.max_x - b.min_x), (b.max_z - b.min_z)
    local function plot(id, wx, wz, col, size)
        local px = mx + ((wx - b.min_x) / rx) * mw
        local py = my + ((wz - b.min_z) / rz) * mh
        quad(id, px - size * 0.5, py - size * 0.5, size, size, col, { no_input = true })
    end
    plot("mm_mine", World.mine.x, World.mine.z, U.COLOR.gold, 7)
    if World.forest then plot("mm_forest", World.forest.x, World.forest.z, U.COLOR.tree_leaf, 7) end
    for _, b in ipairs(state.buildings or {}) do
        if b.alive then plot("mm_b" .. (b.id or 0), b.x, b.z, U.COLOR.player_trim, 9) end
    end
    for _, e in ipairs(state.enemy_units) do
        if e.alive then plot("mm_e" .. e.id, e.x, e.z, U.COLOR.enemy, 5) end
    end
    for _, u in ipairs(state.player_units) do
        if u.alive then plot("mm_p" .. u.id, u.x, u.z, u.is_hero and U.COLOR.hero_trim or U.COLOR.player, u.is_hero and 7 or 5) end
    end

    -- click-to-recenter hit area
    mark("mm_click")
    runtime_ui.set_quad(SCREEN, "mm_click", { x = mx, y = my, width = mw, height = mh,
        style = "panel", fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 }, accent = { 0, 0, 0, 0 }, no_input = false })
    local st = runtime_ui.get_state and runtime_ui.get_state(SCREEN, "mm_click")
    if st and st.clicked and st.mouse_x then
        local u = U.clamp((st.mouse_x - mx) / mw, 0.0, 1.0)
        local v = U.clamp((st.mouse_y - my) / mh, 0.0, 1.0)
        Camera.center_on(b.min_x + u * rx, b.min_z + v * rz)
    end
end

-- ---- selected-unit portrait (inside the authored HUD_Portrait panel) -----------

local function draw_portrait(state)
    local M = 20.0
    local x, y, w, h = panel_rect("Portrait", M * 2 + 300, sh - M - 300, 560, 300)
    local sel = WB.selection.list
    local pad = 14.0

    local bsel = WB.selection.building
    if bsel then
        local face = h * 0.42
        quad("port_face", x + pad, y + pad, face, face, { 0.5, 0.52, 0.6, 1.0 }, { border = U.COLOR.panel_edge, no_input = true })
        quad("port_head", x + pad + face * 0.22, y + pad + face * 0.5, face * 0.56, face * 0.3, U.COLOR.roof, { no_input = true })
        local tx = x + pad + face + 14.0
        local tw = w - pad - (tx - x)
        quad("port_name", tx, y + pad, tw, 30.0, { 0, 0, 0, 0 }, { body = bsel.display, font_scale = 1.2, no_input = true })
        local hp_pct = (bsel.hp or 1) / (bsel.hp_max or 1)
        bar("port_hp", tx, y + pad + 44.0, tw, 30.0, hp_pct, U.COLOR.hp_good,
            string.format("%d / %d", math.floor((bsel.hp or 0) + 0.5), math.floor((bsel.hp_max or 0) + 0.5)))
        local foodtxt = (bsel.food_cap or 0) > 0 and string.format("Supplies %d food", bsel.food_cap) or ""
        quad("port_stats", x + pad, y + h - 38.0, w - pad * 2, 30.0, { 0, 0, 0, 0 },
            { body = foodtxt, font_scale = 1.0, no_input = true })
        return
    end

    if #sel == 0 then
        quad("port_empty", x + pad, y + pad, w - pad * 2, h * 0.18, { 0, 0, 0, 0 },
            { body = "No unit selected", font_scale = 1.1, no_input = true })
        return
    end

    local u = sel[1]
    local face = h * 0.42
    local col = u.is_hero and U.COLOR.hero or (u.faction == "player" and U.COLOR.player or U.COLOR.enemy)
    quad("port_face", x + pad, y + pad, face, face, { col[1], col[2], col[3], 1.0 }, { border = U.COLOR.panel_edge, no_input = true })
    quad("port_head", x + pad + face * 0.3, y + pad + face * 0.22, face * 0.4, face * 0.4, { 0.95, 0.92, 0.85, 1.0 }, { no_input = true })

    local tx = x + pad + face + 14.0
    local tw = w - pad - (tx - x)
    local namestr = u.display .. (u.is_hero and ("  Lv " .. (u.level or 1)) or "")
    if #sel > 1 then namestr = namestr .. "   (+" .. (#sel - 1) .. ")" end
    quad("port_name", tx, y + pad, tw, 30.0, { 0, 0, 0, 0 }, { body = namestr, font_scale = 1.2, no_input = true })

    local by = y + pad + 44.0
    local hp_pct = u.hp / u.hp_max
    local hp_col = hp_pct > 0.5 and U.COLOR.hp_good or (hp_pct > 0.25 and U.COLOR.hp_warn or U.COLOR.hp_low)
    bar("port_hp", tx, by, tw, 30.0, hp_pct, hp_col,
        string.format("%d / %d", math.floor(u.hp + 0.5), math.floor(u.hp_max + 0.5)))
    if u.is_hero then
        bar("port_mp", tx, by + 42.0, tw, 24.0, (u.mana or 0) / (u.mana_max or 1), U.COLOR.mana,
            string.format("Mana %d / %d", math.floor(u.mana or 0), math.floor(u.mana_max or 0)))
        bar("port_xp", tx, by + 78.0, tw, 16.0, (u.xp or 0) / (u.xp_to_level or 1), { 0.7, 0.5, 0.95 }, nil)
    end
    quad("port_stats", x + pad, y + h - 38.0, w - pad * 2, 30.0, { 0, 0, 0, 0 },
        { body = string.format("Damage %d    Armor %d%%", math.floor(u.dps + 0.5), math.floor((u.armor or 0) * 100 + 0.5)),
          font_scale = 1.0, no_input = true })
end

-- ---- command card (buttons inside the authored HUD_Command panel) --------------

local function draw_command_card(state)
    local M = 20.0
    local x, y, w, h = panel_rect("Command", sw - M - 560, sh - M - 300, 560, 300)
    local sel = WB.selection.list

    local cols, rows = 4, 3
    local pad = w * 0.02
    local bw = (w - pad * (cols + 1)) / cols
    local bh = (h - pad * (rows + 1)) / rows
    local function slot(c, r) return x + pad + c * (bw + pad), y + pad + r * (bh + pad) end
    local function btn(c, r, id, label, sub, fill)
        local bx, by = slot(c, r)
        return button("cc_" .. id, bx, by, bw, bh, fill or { 0.12, 0.14, 0.18, 0.95 },
            { title = label, body = sub or "", font_scale = 1.0 })
    end

    -- Building command card: a train button + queue progress (mutually exclusive
    -- with unit selection — see wb_selection).
    local bsel = WB.selection.building
    if bsel then
        local def = WB.economy and WB.economy.train_def and WB.economy.train_def(bsel.trains)
        if def then
            local status = WB.economy.train_status(state, bsel)
            local fill = (status == "ok") and { 0.16, 0.2, 0.16, 0.95 } or { 0.12, 0.12, 0.14, 0.95 }
            local cost = string.format("%dg", def.gold) .. (def.lumber > 0 and string.format(" %dw", def.lumber) or "")
            if btn(0, 0, "train", def.label, cost, fill) then WB.economy.try_train(state, bsel) end
            local why = ({ gold = "need gold", lumber = "need lumber", food = "need food", reserve = "no reserve" })[status]
            if why then
                quad("cc_why", select(1, slot(1, 0)), select(2, slot(1, 0)), bw, bh, { 0, 0, 0, 0 },
                    { body = why, font_scale = 0.9, no_input = true, align = "center" })
            end
            if bsel.queue and #bsel.queue > 0 then
                local j = bsel.queue[1]
                local pct = 1.0 - U.clamp((j.t or 0) / (j.total or 1), 0.0, 1.0)
                local bx, by = slot(0, 2)
                bar("cc_q", bx, by + bh * 0.2, w - pad * 2, bh * 0.5, pct, U.COLOR.player,
                    string.format("Training... %d%%   (%d in queue)", math.floor(pct * 100 + 0.5), #bsel.queue))
            end
        else
            quad("cc_bhint", x + pad, y + pad, w - pad * 2, h - pad * 2, { 0, 0, 0, 0 },
                { body = bsel.display, font_scale = 1.1, no_input = true, align = "center" })
        end
        return
    end

    if #sel == 0 then
        quad("cc_hint", x + pad, y + pad, w - pad * 2, h - pad * 2, { 0, 0, 0, 0 },
            { body = "Select a unit or building\n(left-click / drag)", font_scale = 1.0, no_input = true })
        return
    end

    if btn(0, 0, "stop", "Stop", "S", { 0.15, 0.13, 0.13, 0.95 }) then WB.orders.stop(sel) end
    if btn(1, 0, "hold", "Hold", "H", { 0.13, 0.15, 0.13, 0.95 }) then WB.orders.hold(sel) end
    if sel[1] and sel[1].arch == "worker" then
        quad("cc_gather", select(1, slot(0, 1)), select(2, slot(0, 1)), bw * 2 + pad, bh, { 0.10, 0.12, 0.16, 0.9 },
            { title = "Gather", body = "right-click mine / forest", font_scale = 0.8, no_input = true, align = "center" })
    end
    quad("cc_move", select(1, slot(2, 0)), select(2, slot(2, 0)), bw, bh, { 0.10, 0.12, 0.16, 0.9 },
        { title = "Move", body = "right-click", font_scale = 0.85, no_input = true, align = "center" })
    quad("cc_atk", select(1, slot(3, 0)), select(2, slot(3, 0)), bw, bh, { 0.16, 0.11, 0.11, 0.9 },
        { title = "Attack", body = "rt-clk foe", font_scale = 0.85, no_input = true, align = "center" })

    local hero = sel[1]
    if hero and hero.is_hero then
        for i, a in ipairs(WB.abilities.LIST) do
            local status, cd = WB.abilities.status(hero, a.id)
            local fill = (status == "ready") and { 0.16, 0.14, 0.22, 0.95 } or { 0.10, 0.10, 0.12, 0.95 }
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
    local food = string.format("%d/%d", state.player_alive, state.food_cap or 12)
    drive_text("Resources",
        string.format("Gold %d   Lumber %d   Food %s", state.gold or 0, state.lumber or 0, food),
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
        msg, ccol = string.format("Clear the Wilds camp    -    %d foes remain", state.enemy_alive), U.COLOR.ink
    end
    drive_text("Objective", msg, ccol, sw * 0.5 - 500, M, 1000, 70)
end

-- ---- floating health bars + selection box (screen overlays) --------------------

local function draw_floating_hp(state)
    local function maybe(u, always)
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
        local id = "fh" .. u.id
        quad(id .. "_bg", px - w * 0.5 - 1, py - 7, w + 2, 7, { 0.02, 0.02, 0.03, 0.9 }, { no_input = true })
        quad(id .. "_fg", px - w * 0.5, py - 6, w * pct, 5, col, { no_input = true })
    end
    for _, e in ipairs(state.enemy_units) do maybe(e, true) end
    for _, u in ipairs(state.player_units) do maybe(u, u.selected) end
end

local function draw_select_box()
    local b = WB.selection.box
    if b.active then
        local x0, y0 = math.min(b.x0, b.x1), math.min(b.y0, b.y1)
        local w, h = math.abs(b.x1 - b.x0), math.abs(b.y1 - b.y0)
        local c = { 0.4, 0.95, 0.5, 0.9 }
        quad("selbox_t", x0, y0, w, 2, c, { no_input = true })
        quad("selbox_b", x0, y0 + h, w, 2, c, { no_input = true })
        quad("selbox_l", x0, y0, 2, h, c, { no_input = true })
        quad("selbox_r", x0 + w, y0, 2, h, c, { no_input = true })
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
    dyn_now = {}
    for i = #panels, 1, -1 do panels[i] = nil end

    draw_minimap(state)
    draw_portrait(state)
    draw_command_card(state)
    drive_top(state)
    draw_floating_hp(state)
    draw_select_box()

    for id in pairs(dyn_prev) do
        if not dyn_now[id] then runtime_ui.remove(SCREEN, id) end
    end
    dyn_prev = dyn_now
end

return Hud
