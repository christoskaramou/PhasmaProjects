-- ath_inventory — a normal-RPG inventory for the manual arena: a backpack GRID of
-- square slots + a 6-slot character paper-doll, drag-and-drop between them, click
-- to (un)equip, and a LIVE total-stat preview that updates as you gear up.
--
-- PURE PRESENTATION + interaction over the Duel's gear model. It owns no stats: it
-- reads/writes D.inv_grid (array) + D.gear_equipped (6 named slots) and calls
-- D:recompute_hero_stats() / D:gear_preview_stats() after every change.
--
-- DRAG MODEL (engine reports drag state but never moves quads): each occupied slot
-- draws a `draggable` item quad. We poll its get_state — drag_started picks it up,
-- a ghost quad follows the cursor, drag_released hit-tests the cursor against the
-- slot rects and moves the item in the data model (redrawn next frame). A plain
-- click (no drag) equips a bag item / unequips a doll item.

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)

local Inv = {}

Inv.SLOTS = { "helmet", "body", "pants", "gloves", "weapon", "jewelry" }
Inv.SLOT_LABEL = {
    helmet = "Helmet", body = "Body", pants = "Pants",
    gloves = "Gloves", weapon = "Weapon", jewelry = "Jewelry",
}
Inv.GRID_COLS = 6
Inv.GRID_ROWS = 4
Inv.GRID_SIZE = Inv.GRID_COLS * Inv.GRID_ROWS

Inv.RARITY = {
    common   = { 0.66, 0.70, 0.76, 1.0 },
    uncommon = { 0.42, 0.84, 0.48, 1.0 },
    rare     = { 0.38, 0.64, 0.97, 1.0 },
    epic     = { 0.78, 0.48, 0.96, 1.0 },
}

local SLOT_BG = { 0.07, 0.08, 0.11, 0.95 }
local SLOT_BORDER = { 0.26, 0.28, 0.34, 0.95 }
local EQUIP_BG = { 0.06, 0.10, 0.10, 0.95 }

-- ---------------------------------------------------------------------------
-- Model helpers
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
-- Layout — pure function of the surface size (vp-relative coords, like Art.quad).
-- ---------------------------------------------------------------------------
-- Fixed layout geometry (band-relative px). Sized so the title bar, both slot
-- blocks, the stat panel, and the NEXT WAVE button all fit the letterboxed band
-- without overlapping.
function Inv.geom()
    local vw, vh = Art.surface_size()
    local function S(v) return v * Art.s("hud") end
    -- Slot sizes scale with the band so the column fits above the NEXT WAVE
    -- button. The title/left-column ANCHORS clear the ABSOLUTE top HUD (HP bar
    -- ~S(64) tall, top-left status panel ~S(220) wide) via max(...), because
    -- those are S-sized, not band-fraction sized — otherwise they re-collide on
    -- smaller windows. Headers chain off the title so they never tuck under it.
    local cell = vh * 0.118
    local gap = vh * 0.016
    -- runtime_ui card layout: one text line is ~S(22) tall and sits ~S(15) below
    -- a box's top. Title/header text uses the `label` field (the ONLY field
    -- anchored at the box top; title/subtitle/body sit below a reserved ~S(42)
    -- art band and fall outside a short box). Boxes are sized to one line so the
    -- text fits exactly, and each block clears the one above it.
    local titleh = math.max(vh * 0.048, S(44.0))
    local hdr_h = math.max(vh * 0.05, S(44.0))
    local hdr_gap = S(12.0)
    local titley = math.max(vh * 0.072, S(66.0)) -- just clears the absolute HP bar
    return {
        vw = vw, vh = vh, S = S,
        cell = cell, gap = gap, pitch = cell + gap,
        titley = titley, titleh = titleh, hdr_h = hdr_h, hdr_gap = hdr_gap,
        top = titley + titleh + S(12.0) + hdr_h + hdr_gap, -- first slot row
        dollx = math.max(vw * 0.08, S(225.0)),             -- right of the top-left status panel
        gx = vw * 0.46,                                    -- backpack grid column
    }
end

function Inv.layout(D)
    local g = Inv.geom()
    local slots = {}
    -- Paper-doll: 3 columns x 2 rows (short, to leave room for the stat panel).
    for i, key in ipairs(Inv.SLOTS) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        slots[#slots + 1] = { id = "eq_" .. key, kind = "equip", key = key,
            x = g.dollx + col * g.pitch, y = g.top + row * g.pitch, w = g.cell, h = g.cell }
    end
    -- Backpack grid: 6 columns x 4 rows.
    for idx = 1, Inv.GRID_SIZE do
        local col = (idx - 1) % Inv.GRID_COLS
        local row = math.floor((idx - 1) / Inv.GRID_COLS)
        slots[#slots + 1] = { id = "bag_" .. idx, kind = "grid", key = idx,
            x = g.gx + col * g.pitch, y = g.top + row * g.pitch, w = g.cell, h = g.cell }
    end
    return slots, g.cell, g.gap, g
end

-- ---------------------------------------------------------------------------
-- Interaction — poll drag state, resolve clicks + drops.
-- ---------------------------------------------------------------------------
function Inv.update(D)
    Inv.ensure(D)
    local slots = Inv.layout(D)
    Art.surface_size()
    local vp = Art._vp

    -- Pickups + hover. A press on a draggable quad becomes a DRAG (the engine
    -- swallows `clicked`), so equip-by-double-click is detected from taps: a drag
    -- that releases on the SAME slot with no real move counts as a tap.
    local hover, tap_slot = nil, nil
    for _, s in ipairs(slots) do
        local item = Inv.item_at(D, s)
        if item then
            local st = Art.widget_state(D.hud, s.id)
            if st then
                if st.hovered then hover = { item = item, mx = st.mouse_x, my = st.mouse_y } end
                if st.drag_started and not D._inv_drag then
                    D._inv_drag = { from = s, mx = st.mouse_x, my = st.mouse_y }
                elseif st.clicked and not st.dragging and not D._inv_drag then
                    tap_slot = s -- some setups DO report a plain click; treat as a tap
                end
            end
        end
    end
    -- No tooltip while a drag is in flight (the ghost is what reads).
    D._inv_hover = (not D._inv_drag) and hover or nil

    -- Drag in flight: follow the cursor; on release, move to the target slot or
    -- (if released on its own slot) register a tap for double-click detection.
    local drag = D._inv_drag
    if drag then
        local st = Art.widget_state(D.hud, drag.from.id)
        if not st then
            D._inv_drag = nil
        else
            if st.mouse_x then drag.mx, drag.my = st.mouse_x, st.mouse_y end
            if st.drag_released then
                local mx = (drag.mx or 0.0) - vp.x
                local my = (drag.my or 0.0) - vp.y
                local target = nil
                for _, s in ipairs(slots) do
                    if mx >= s.x and mx <= s.x + s.w and my >= s.y and my <= s.y + s.h then
                        target = s; break
                    end
                end
                if target and target.id ~= drag.from.id then
                    Inv.move(D, drag.from, target) -- a real drag to another slot
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
end

-- ---------------------------------------------------------------------------
-- Draw — slot backgrounds, item tiles, paper-doll, live stat preview, drag ghost.
-- ---------------------------------------------------------------------------
-- Word-wrap to fit a tile at the normal label font (labels don't auto-wrap, they
-- clip), greedily packing words up to `maxlen` chars per line.
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

function Inv.draw(D, accent)
    Inv.ensure(D)
    local vw, vh = Art.surface_size()
    local function S(v) return v * Art.s("hud") end
    local slots, cell, gap, g = Inv.layout(D)
    accent = accent or { 0.62, 0.34, 0.86, 0.95 }
    -- Item-name font is PINNED to the size the fixed-size cells were tuned for
    -- (baseline 1.85 text scale). The global UI text was scaled up for legibility,
    -- but a 9-char wrap at the big font overflows a cell and CLIPS ("Sprint
    -- Greave"); dividing by the live text scale keeps tile names fitting at any
    -- global size. min(1.0, ..) so it never grows past the original on small scales.
    local tile_font = math.min(1.0, 1.85 / Art.s("text"))

    -- Title bar — uses `label` (anchors at the box top, stays inside it; `title`
    -- would render below the reserved art band, outside this short box).
    Art.quad(D.hud, "inv_title", vw * 0.5 - vw * 0.25, g.titley, vw * 0.50, g.titleh,
        { 0.06, 0.05, 0.10, 0.92 }, { border = accent, no_input = true, font_scale = 0.8,
          label = string.format("WAVE %d CLEARED - GEAR UP   (drag or double-click to equip)",
            D.wave_index or 1) })

    -- Section headers: small boxes sized to one line, sitting clear above the slots.
    local hy = g.top - g.hdr_gap - g.hdr_h
    Art.quad(D.hud, "inv_doll_hdr", g.dollx, hy, S(126.0), g.hdr_h, { 0.06, 0.06, 0.10, 0.80 },
        { border = { 0.40, 0.62, 0.58, 0.9 }, label = "EQUIPPED",
          text_color = { 0.9, 0.92, 1.0, 1.0 }, no_input = true })
    Art.quad(D.hud, "inv_bag_hdr", g.gx, hy, S(126.0), g.hdr_h, { 0.06, 0.06, 0.10, 0.80 },
        { border = { 0.40, 0.62, 0.58, 0.9 }, label = "BACKPACK",
          text_color = { 0.9, 0.92, 1.0, 1.0 }, no_input = true })

    local pad = S(4.0)
    for _, s in ipairs(slots) do
        local item = Inv.item_at(D, s)
        local is_dragging = D._inv_drag and D._inv_drag.from.id == s.id
        -- Slot background (empty doll slots show their slot name as a hint).
        Art.quad(D.hud, s.id .. "_bg", s.x, s.y, s.w, s.h,
            (s.kind == "equip") and EQUIP_BG or SLOT_BG,
            { border = (s.kind == "equip") and { 0.40, 0.62, 0.58, 0.9 } or SLOT_BORDER, no_input = true,
              label = (not item and s.kind == "equip") and Inv.SLOT_LABEL[s.key] or "",
              font_scale = tile_font, text_color = { 0.6, 0.66, 0.7, 0.9 } })
        -- Item tile (draggable). Dim while it is the one being dragged.
        if item then
            local rc = Inv.RARITY[item.rarity or "common"]
            local fill = is_dragging and { 0.10, 0.11, 0.14, 0.45 } or { 0.13, 0.15, 0.20, 0.98 }
            -- Name at the normal font, word-wrapped to fit the cell.
            Art.quad(D.hud, s.id, s.x + pad, s.y + pad, s.w - pad * 2, s.h - pad * 2, fill,
                { border = rc, draggable = true, bring_to_front = true, label = tile_label(item), font_scale = tile_font })
        else
            Art.remove(D.hud, s.id)
        end
    end

    -- Live total-stat preview (recomputed every frame), compact 2-column so it
    -- fits below the paper-doll without running off the band.
    local st = (D.gear_preview_stats and D:gear_preview_stats()) or {}
    local function pct(v) return string.format("%d%%", math.floor((v or 0.0) * 100.0 + 0.5)) end
    -- Single column. Labels + values are TWO separate stacked-label quads so the
    -- values line up in a clean column (a single string can't column-align in a
    -- proportional font; space-padding drifts).
    local labels_col = "TOTAL STATS\nHealth\nAttack Damage\nAttack Range\nAttacks/Hit\nAttack Rate\nMove Speed\nArmor\nLife Steal\nRegen"
    local values_col = string.format("\n%d\n%d\n%.1f\n%d\n%.2fs\n%.1f\n%s\n%.1f\n%.1f/s",
        math.floor((st.hp_max or 0) + 0.5), math.floor((st.dps or 0) + 0.5),
        st.attack_range or 0.0, math.floor((st.cleave or 0) + 0.5),
        st.fire_interval or 0.0, st.speed or 0.0,
        pct(st.armor), st.lifesteal or 0.0, st.regen or 0.0)
    local sy = g.top + 2 * g.pitch + S(6.0)
    local sw_stat = math.max(g.vw * 0.22, g.gx - g.dollx - S(28.0)) -- fill left column up to the grid
    local sh_stat = S(208.0)
    Art.quad(D.hud, "inv_stats", g.dollx, sy, sw_stat, sh_stat, { 0.05, 0.06, 0.09, 0.95 },
        { border = accent, no_input = true })
    Art.quad(D.hud, "inv_stats_l", g.dollx + S(8.0), sy + S(4.0), sw_stat, sh_stat, { 0, 0, 0, 0 },
        { label = labels_col, no_input = true, font_scale = 0.85, text_color = { 0.92, 0.94, 0.98, 1.0 } })
    Art.quad(D.hud, "inv_stats_v", g.dollx + S(150.0), sy + S(4.0), sw_stat, sh_stat, { 0, 0, 0, 0 },
        { label = values_col, no_input = true, font_scale = 0.85, text_color = { 0.96, 0.92, 0.70, 1.0 } })

    -- Hover tooltip: name + slot + rarity + description of the item under the
    -- cursor (the tiles are too small to carry the full description themselves).
    local hv = D._inv_hover
    if hv and hv.item then
        local vp = Art._vp
        local tw, th = S(300.0), S(86.0)
        local tx = (hv.mx or 0.0) - vp.x + S(18.0)
        local ty = (hv.my or 0.0) - vp.y + S(12.0)
        if tx + tw > vw then tx = vw - tw - S(8.0) end
        if ty + th > vh then ty = vh - th - S(8.0) end
        local rc = Inv.RARITY[hv.item.rarity or "common"]
        -- Single multi-line label (top-anchored): name / TYPE - rarity / description.
        local tip = string.format("%s\n%s  -  %s\n%s",
            hv.item.name or hv.item.id,
            Inv.SLOT_LABEL[hv.item.slot] or "?",
            string.upper(hv.item.rarity or "common"),
            hv.item.desc or "")
        Art.quad(D.hud, "inv_tip", tx, ty, tw, th, { 0.04, 0.05, 0.08, 0.98 },
            { border = rc, bring_to_front = true, no_input = true, label = tip, font_scale = 0.9 })
    else
        Art.remove(D.hud, "inv_tip")
    end

    -- Drag ghost: the held item rendered at the cursor (vp-relative).
    if D._inv_drag then
        local item = Inv.item_at(D, D._inv_drag.from)
        if item then
            local vp = Art._vp
            local gx = (D._inv_drag.mx or 0.0) - vp.x - cell * 0.5
            local gy = (D._inv_drag.my or 0.0) - vp.y - cell * 0.5
            local rc = Inv.RARITY[item.rarity or "common"]
            Art.quad(D.hud, "inv_ghost", gx, gy, cell, cell, { 0.16, 0.18, 0.24, 0.96 },
                { border = rc, bring_to_front = true, no_input = true, label = tile_label(item), font_scale = tile_font })
        end
    else
        Art.remove(D.hud, "inv_ghost")
    end
end

-- Remove every widget this screen owns (call when leaving the inventory/pause).
function Inv.clear(D)
    if not (runtime_ui and runtime_ui.remove) then return end
    Art.remove(D.hud, "inv_title")
    Art.remove(D.hud, "inv_doll_hdr")
    Art.remove(D.hud, "inv_bag_hdr")
    Art.remove(D.hud, "inv_stats")
    Art.remove(D.hud, "inv_stats_l")
    Art.remove(D.hud, "inv_stats_v")
    Art.remove(D.hud, "inv_ghost")
    Art.remove(D.hud, "inv_tip")
    for _, k in ipairs(Inv.SLOTS) do
        Art.remove(D.hud, "eq_" .. k); Art.remove(D.hud, "eq_" .. k .. "_bg")
    end
    for i = 1, Inv.GRID_SIZE do
        Art.remove(D.hud, "bag_" .. i); Art.remove(D.hud, "bag_" .. i .. "_bg")
    end
end

return Inv
