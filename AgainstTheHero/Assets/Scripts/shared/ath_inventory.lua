-- ath_inventory — the manual arena's RPG inventory, driven entirely over the
-- AUTHORED "Pause Menu" scene nodes (game.pescene). The SHAPE lives in the scene
-- hierarchy now (a backpack grid of "Inv Bag N" slots + a 6-slot paper-doll of
-- "Inv Equip <Slot>" nodes + a live stat panel), so it can be moved and restyled
-- in the editor. This module is ACTIONS ONLY: it finds those nodes, fills their
-- text/colours via node:set_ui, hit-tests drags via node:get_ui_rect, and toggles
-- the group's visibility. It builds NO geometry.
--
-- It owns no stats: it reads/writes D.inv_grid (array) + D.gear_equipped (6 named
-- slots) and calls D:recompute_hero_stats() / D:gear_preview_stats() after every
-- change.
--
-- DRAG MODEL (the engine reports drag state but never moves widgets): each slot
-- node is authored `draggable`. We poll runtime_ui.get_state(screen, id) —
-- drag_started picks the item up, a ghost quad follows the cursor, drag_released
-- hit-tests the cursor against every slot's live get_ui_rect() and moves the item
-- in the data model (redrawn next frame). A plain double-tap equips/unequips.

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)

local Inv = {}

local SCREEN = "__scene_ui" -- the authored UI screen the Pause Menu nodes live on

Inv.SLOTS = { "helmet", "body", "pants", "gloves", "weapon", "jewelry" }
Inv.SLOT_LABEL = {
    helmet = "Helmet", body = "Body", pants = "Pants",
    gloves = "Gloves", weapon = "Weapon", jewelry = "Jewelry",
}
Inv.GRID_COLS = 6
Inv.GRID_ROWS = 4
Inv.GRID_SIZE = Inv.GRID_COLS * Inv.GRID_ROWS

-- Rarity tints the slot border (matches the authored slot palette).
Inv.RARITY = {
    common   = { 0.66, 0.70, 0.76, 1.0 },
    uncommon = { 0.42, 0.84, 0.48, 1.0 },
    rare     = { 0.38, 0.64, 0.97, 1.0 },
    epic     = { 0.78, 0.48, 0.96, 1.0 },
}

-- Empty-slot palette — kept in sync with tools/build_scenes.py so a redrawn slot
-- matches its authored default exactly.
local SLOT_BG = { 0.07, 0.08, 0.11, 0.95 }
local SLOT_BORDER = { 0.26, 0.28, 0.34, 0.95 }
local EQUIP_BG = { 0.06, 0.10, 0.10, 0.95 }
local EQUIP_BORDER = { 0.40, 0.62, 0.58, 0.9 }
local ITEM_BG = { 0.13, 0.15, 0.20, 0.98 }
local ITEM_BG_DRAG = { 0.10, 0.11, 0.14, 0.45 }
local SLOT_TEXT = { 0.85, 0.88, 0.92, 1.0 }
local EMPTY_TEXT = { 0.6, 0.66, 0.7, 0.9 }

local function valid(n)
    return n and n.is_valid and n:is_valid()
end
Inv._valid = valid

local function cap(k)
    return k:sub(1, 1):upper() .. k:sub(2)
end

-- ---------------------------------------------------------------------------
-- Model helpers (pure data over D.inv_grid + D.gear_equipped).
-- ---------------------------------------------------------------------------
function Inv.ensure(D)
    if not D.inv_grid then D.inv_grid = {} end
    if not D.gear_equipped then
        D.gear_equipped = {}
        for _, k in ipairs(Inv.SLOTS) do D.gear_equipped[k] = nil end
    end
end

function Inv.item_at(D, s)
    if s.kind == "grid" then return D.inv_grid[s.key] end
    return D.gear_equipped[s.key]
end

function Inv.set_raw(D, s, item)
    if s.kind == "grid" then D.inv_grid[s.key] = item else D.gear_equipped[s.key] = item end
end

function Inv.add_item(D, item)
    if not item then return true end
    Inv.ensure(D)
    for i = 1, Inv.GRID_SIZE do
        if not D.inv_grid[i] then D.inv_grid[i] = item; return true end
    end
    return false -- bag full
end

-- Move/swap the item from one slot to another, honouring equip-type constraints
-- and never destroying an item (a displaced piece that can't fit goes to the bag).
function Inv.move(D, from, to)
    local a = Inv.item_at(D, from)
    if not a then return end
    if from.id == to.id then return end
    if to.kind == "equip" and a.slot ~= to.key then return end -- a can't go in this doll slot
    local b = Inv.item_at(D, to)
    if from.kind == "equip" and b and b.slot ~= from.key then
        -- b can't return to from's doll slot: place a, push b to the bag.
        Inv.set_raw(D, to, a)
        Inv.set_raw(D, from, nil)
        Inv.add_item(D, b)
    else
        Inv.set_raw(D, to, a)
        Inv.set_raw(D, from, b)
    end
    if D.recompute_hero_stats then D:recompute_hero_stats() end
    if D.haptic then D:haptic(8) end -- equip/move feedback (no-op without the binding)
end

function Inv.try_equip(D, grid_index)
    local item = D.inv_grid[grid_index]
    if not item or not item.slot then return end
    Inv.move(D, { kind = "grid", key = grid_index, id = "bag_" .. grid_index },
                { kind = "equip", key = item.slot, id = "eq_" .. item.slot })
end

function Inv.try_unequip(D, slot)
    local item = D.gear_equipped[slot]
    if not item then return end
    if Inv.add_item(D, item) then
        D.gear_equipped[slot] = nil
        if D.recompute_hero_stats then D:recompute_hero_stats() end
        if D.haptic then D:haptic(8) end
    end
end

-- ---------------------------------------------------------------------------
-- Authored-node binding. Resolved once by name and cached on D; re-bound if the
-- handles go stale (scene reload / play-stop).
-- ---------------------------------------------------------------------------
function Inv.bind(D)
    local b = D._inv_nodes
    if b and valid(b.group) then return b end
    if not (scene and scene.find_model) then return nil end
    b = { eq = {}, bag = {} }
    b.group = scene.find_model("Pause Menu")
    if not valid(b.group) then D._inv_nodes = nil; return nil end
    b.title = scene.find_model("Pause Title")
    b.stats_values = scene.find_model("Inv Stats Values")
    b.next_wave = scene.find_model("Pause Next Wave")
    for _, k in ipairs(Inv.SLOTS) do b.eq[k] = scene.find_model("Inv Equip " .. cap(k)) end
    for i = 1, Inv.GRID_SIZE do b.bag[i] = scene.find_model("Inv Bag " .. i) end
    D._inv_nodes = b
    return b
end

-- A flat list of slot descriptors {kind, key, id, node}. `id` is the authored
-- runtime_ui id (used for get_state); the model's own internal ids are separate.
function Inv.slots(D)
    local b = Inv.bind(D)
    if not b then return {} end
    local list = {}
    for _, k in ipairs(Inv.SLOTS) do
        list[#list + 1] = { kind = "equip", key = k, id = "inv_eq_" .. k, node = b.eq[k] }
    end
    for i = 1, Inv.GRID_SIZE do
        list[#list + 1] = { kind = "grid", key = i, id = "inv_bag_" .. i, node = b.bag[i] }
    end
    return list
end

-- ---------------------------------------------------------------------------
-- Content — push current model state into the authored node text/colours.
-- ---------------------------------------------------------------------------
-- Word-wrap to fit a tile at the slot font (labels don't auto-wrap, they clip),
-- greedily packing words up to `maxlen` chars per line.
local function wrap(text, maxlen)
    text = tostring(text or "")
    local lines, cur = {}, ""
    for word in text:gmatch("%S+") do
        if cur == "" then
            cur = word
        elseif #cur + 1 + #word <= maxlen then
            cur = cur .. " " .. word
        else
            lines[#lines + 1] = cur
            cur = word
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return table.concat(lines, "\n")
end

local function tile_label(item)
    return wrap((item and (item.name or item.id)) or "", 9)
end

-- The values column for the live stat panel (the labels column is authored
-- static; this fills "Inv Stats Values"). The leading newline aligns the first
-- value under the "Health" row (the labels start with a "TOTAL STATS" header).
function Inv.stats_values_text(st)
    local function pct(v) return string.format("%d%%", math.floor((v or 0.0) * 100.0 + 0.5)) end
    return string.format("\n%d\n%d\n%.1f\n%d\n%.2fs\n%.1f\n%s\n%.1f\n%.1f/s",
        math.floor((st.hp_max or 0) + 0.5), math.floor((st.dps or 0) + 0.5),
        st.attack_range or 0.0, math.floor((st.cleave or 0) + 0.5),
        st.fire_interval or 0.0, st.speed or 0.0,
        pct(st.armor), st.lifesteal or 0.0, st.regen or 0.0)
end

function Inv.refresh(D)
    Inv.ensure(D)
    local b = Inv.bind(D)
    if not b then return end

    -- Authored text nodes render their `body` field (in text_color); see the
    -- backend's Text-widget path. (The transient cursor ghost/tooltip below still
    -- use the set_quad `label`, which the default quad style draws.)
    if valid(b.title) then
        b.title:set_ui({ body = string.format(
            "WAVE %d CLEARED - GEAR UP   (drag or double-click to equip)", D.wave_index or 1) })
    end

    for _, s in ipairs(Inv.slots(D)) do
        local node = s.node
        if valid(node) then
            local item = Inv.item_at(D, s)
            local dragging = D._inv_drag and D._inv_drag.from.id == s.id
            if item then
                node:set_ui({
                    body = tile_label(item), text_color = SLOT_TEXT,
                    fill = dragging and ITEM_BG_DRAG or ITEM_BG,
                    border = Inv.RARITY[item.rarity or "common"],
                })
            elseif s.kind == "equip" then
                node:set_ui({ body = Inv.SLOT_LABEL[s.key], text_color = EMPTY_TEXT,
                    fill = EQUIP_BG, border = EQUIP_BORDER })
            else
                node:set_ui({ body = "", text_color = SLOT_TEXT, fill = SLOT_BG, border = SLOT_BORDER })
            end
        end
    end

    if valid(b.stats_values) then
        local st = (D.gear_preview_stats and D:gear_preview_stats()) or {}
        b.stats_values:set_ui({ body = Inv.stats_values_text(st) })
    end

    -- NEXT WAVE only resumes the run on a real between-wave pause; a mid-fight
    -- inventory peek (gear button) hides it.
    if valid(b.next_wave) and b.next_wave.set_enabled then
        b.next_wave:set_enabled(D.state == "pause" and D._between_wave == true)
    end
end

-- ---------------------------------------------------------------------------
-- Interaction — poll authored drag state, resolve clicks + drops.
-- ---------------------------------------------------------------------------
function Inv.update(D)
    Inv.ensure(D)
    if not (runtime_ui and runtime_ui.get_state) then return end
    local slots = Inv.slots(D)
    if #slots == 0 then return end

    -- Pickups + hover. A press on a draggable slot becomes a DRAG (the engine
    -- swallows `clicked`); a clean tap is detected on release for double-tap equip.
    local hover, tap_slot = nil, nil
    for _, s in ipairs(slots) do
        local item = Inv.item_at(D, s)
        if item then
            local stt = runtime_ui.get_state(SCREEN, s.id)
            if stt then
                if stt.hovered then hover = { item = item, mx = stt.mouse_x, my = stt.mouse_y } end
                if stt.drag_started and not D._inv_drag then
                    D._inv_drag = { from = s, mx = stt.mouse_x, my = stt.mouse_y }
                elseif stt.clicked and not stt.dragging and not D._inv_drag then
                    tap_slot = s
                end
            end
        end
    end
    D._inv_hover = (not D._inv_drag) and hover or nil

    -- Drag in flight: follow the cursor; on release, hit-test the LIVE rects (so a
    -- slot the user moved in the editor still resolves) and move, or register a tap.
    local drag = D._inv_drag
    if drag then
        local stt = runtime_ui.get_state(SCREEN, drag.from.id)
        if not stt then
            D._inv_drag = nil
        else
            if stt.mouse_x then drag.mx, drag.my = stt.mouse_x, stt.mouse_y end
            if stt.drag_released then
                local mx, my = drag.mx or 0.0, drag.my or 0.0
                local target = nil
                for _, s in ipairs(slots) do
                    local r = valid(s.node) and s.node.get_ui_rect and s.node:get_ui_rect() or nil
                    if r and r.x and mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                        target = s; break
                    end
                end
                if target and target.id ~= drag.from.id then
                    Inv.move(D, drag.from, target)
                    D._inv_last_click = nil
                else
                    tap_slot = drag.from -- released on its own slot: a tap
                end
                D._inv_drag = nil
            end
        end
    end

    -- Double-tap (two taps on the same slot within 0.35s) equips a bag item /
    -- unequips a doll item. Timed via the duel's realtime.
    if tap_slot then
        local now = D.realtime or 0.0
        local last = D._inv_last_click
        if last and last.id == tap_slot.id and (now - last.t) <= 0.35 then
            if tap_slot.kind == "grid" then Inv.try_equip(D, tap_slot.key) else Inv.try_unequip(D, tap_slot.key) end
            D._inv_last_click = nil
        else
            D._inv_last_click = { id = tap_slot.id, t = now }
        end
    end

    Inv.draw_overlay(D)
end

-- ---------------------------------------------------------------------------
-- Cursor overlays — the drag ghost + hover tooltip FOLLOW the mouse, so they're
-- transient set_quad widgets (not authored nodes). They are drawn on the SAME
-- screen as the authored slots ("__scene_ui") with a high `z` + bring_to_front so
-- they sort ABOVE the slots; on the duel HUD screen they rendered behind. Mouse
-- coords from get_state and the authored rects are both absolute surface pixels,
-- so these place directly (no letterbox-viewport offset).
-- ---------------------------------------------------------------------------
local OVERLAY_Z = 9000.0

function Inv.draw_overlay(D)
    if not (runtime_ui and runtime_ui.set_quad) then return end
    Art.surface_size()
    local vp = Art._vp
    local rw, rh = vp.rw or 2400.0, vp.rh or 1080.0
    local function S(v) return v * Art.s("hud") end

    if D._inv_drag then
        local item = Inv.item_at(D, D._inv_drag.from)
        if item then
            local cell = S(64.0)
            runtime_ui.set_quad(SCREEN, "inv_ghost", {
                x = (D._inv_drag.mx or 0.0) - cell * 0.5,
                y = (D._inv_drag.my or 0.0) - cell * 0.5,
                width = cell, height = cell, style = "text",
                fill = { 0.16, 0.18, 0.24, 0.96 }, border = Inv.RARITY[item.rarity or "common"],
                body = tile_label(item), text_color = SLOT_TEXT,
                font_scale = 0.85, align_h = "center", align_v = "middle",
                no_input = true, bring_to_front = true, z = OVERLAY_Z,
            })
        end
    else
        runtime_ui.remove(SCREEN, "inv_ghost")
    end

    local hv = D._inv_hover
    if hv and hv.item and not D._inv_drag then
        local tip = string.format("%s\n%s  -  %s\n%s",
            hv.item.name or hv.item.id, Inv.SLOT_LABEL[hv.item.slot] or "?",
            string.upper(hv.item.rarity or "common"), hv.item.desc or "")
        -- The engine auto-fits the box to the text (fit=true); tw/th are generous
        -- upper bounds used only to keep the popup on-screen near the edges.
        local tw, th = S(420.0), S(190.0)
        local tx = (hv.mx or 0.0) + S(18.0)
        local ty = (hv.my or 0.0) + S(12.0)
        if tx + tw > rw then tx = rw - tw - S(8.0) end
        if ty + th > rh then ty = rh - th - S(8.0) end
        runtime_ui.set_quad(SCREEN, "inv_tip", {
            x = tx, y = ty, style = "text", fit = true,
            fill = { 0.04, 0.05, 0.08, 0.98 }, border = Inv.RARITY[hv.item.rarity or "common"],
            body = tip, text_color = { 0.92, 0.94, 0.98, 1.0 },
            font_scale = 2.0, align_h = "left", align_v = "top",
            no_input = true, bring_to_front = true, z = OVERLAY_Z,
        })
    else
        runtime_ui.remove(SCREEN, "inv_tip")
    end
end

-- ---------------------------------------------------------------------------
-- Visibility — enable/disable the whole authored Pause Menu group.
-- ---------------------------------------------------------------------------
function Inv.show(D)
    local b = Inv.bind(D)
    if b and valid(b.group) and b.group.set_enabled then b.group:set_enabled(true) end
end

function Inv.hide(D)
    local b = D._inv_nodes
    if b and valid(b.group) and b.group.set_enabled then b.group:set_enabled(false) end
    Inv.clear(D)
end

-- Tear down the transient cursor overlays + drop any in-flight drag.
function Inv.clear(D)
    if runtime_ui and runtime_ui.remove then
        runtime_ui.remove(SCREEN, "inv_ghost")
        runtime_ui.remove(SCREEN, "inv_tip")
    end
    D._inv_drag = nil
    D._inv_hover = nil
end

return Inv
