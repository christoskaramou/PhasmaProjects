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

local function ensure_hub_settings()
    if _G.ATH_HUB_SETTINGS then return end
    ATH_COMMON.load_script("Scripts/shared/hud/hub_settings.lua", "hub settings", _ENV)
end

local function T(key, ...)
    local I18n = _G.ATH_I18N
    if I18n and I18n.t then return I18n.t(key, ...) end
    if select("#", ...) > 0 then return string.format(key, ...) end
    return key
end

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
    common    = { 0.66, 0.70, 0.76, 1.0 },
    uncommon  = { 0.42, 0.84, 0.48, 1.0 },
    rare      = { 0.38, 0.64, 0.97, 1.0 },
    epic      = { 0.78, 0.48, 0.96, 1.0 },
    legendary = { 0.96, 0.74, 0.30, 1.0 },
}
Inv.RARITIES = { "common", "uncommon", "rare", "epic", "legendary" }

Inv.TABS = { "map", "inventory", "store", "skills", "settings", "system" }
local TAB_NODE = {
    map = "Hub Tab Map", inventory = "Hub Tab Inventory",
    store = "Hub Tab Store", skills = "Hub Tab Skills",
    settings = "Hub Tab Settings", system = "Hub Tab System",
}
local TAB_TITLE = {
    map = "MAP", inventory = "INVENTORY", store = "STORE", skills = "SKILLS",
    settings = "SETTINGS", system = "SYSTEM",
}
-- Selected = colored fill; idle = no-color (transparent fill, outline only).
local TAB_ACTIVE_FILL = { 0.62, 0.34, 0.86, 0.95 }
local TAB_IDLE_FILL = { 0.0, 0.0, 0.0, 0.0 }
local TAB_IDLE_BORDER = { 0.40, 0.62, 0.58, 0.9 }

-- Pixel-art icon per paper-doll slot (Assets/Textures/ui/items). Shared with the
-- duel's ground drops so an item looks the same on the floor and in the bag.
Inv.SLOT_ICON = {
    helmet = "ui/items/helmet.png", body = "ui/items/body.png", pants = "ui/items/pants.png",
    gloves = "ui/items/gloves.png", weapon = "ui/items/weapon.png", jewelry = "ui/items/jewelry.png",
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
local STATS_LABELS = "Health\nAttack Damage\nAttack Range\nAttacks/Hit\nAttack Rate\nMove Speed\nEquip Load\nDodge\nI-Frames/Guard\nPoise/Armor\nLife Steal\nRegen"

local function valid(n)
    return n and n.is_valid and n:is_valid()
end
Inv._valid = valid

local function cap(k)
    return k:sub(1, 1):upper() .. k:sub(2)
end

local function changed(D)
    if D.save_profile then D:save_profile() end
end

-- ---------------------------------------------------------------------------
-- Model helpers (pure data over D.inv_grid + D.gear_equipped).
-- ---------------------------------------------------------------------------
function Inv.ensure(D)
    if not D.inv_grid then D.inv_grid = {} end
    if not D.loot_filter then
        D.loot_filter = {}
        for _, rarity in ipairs(Inv.RARITIES) do D.loot_filter[rarity] = true end
    end
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
    changed(D)
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
        changed(D)
    end
end

function Inv.sort(D)
    local items, slot_order = {}, {}
    for i, slot in ipairs(Inv.SLOTS) do slot_order[slot] = i end
    for i = 1, Inv.GRID_SIZE do if D.inv_grid[i] then items[#items + 1] = D.inv_grid[i] end end
    local rarity = { common = 1, uncommon = 2, rare = 3, epic = 4 }
    table.sort(items, function(a, b)
        local sa, sb = slot_order[a.slot] or 99, slot_order[b.slot] or 99
        if sa ~= sb then return sa < sb end
        local ra, rb = rarity[a.rarity or "common"] or 0, rarity[b.rarity or "common"] or 0
        if ra ~= rb then return ra > rb end
        return tostring(a.name or a.id) < tostring(b.name or b.id)
    end)
    for i = 1, Inv.GRID_SIZE do D.inv_grid[i] = items[i] end
    changed(D)
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
    b.tabs = {}
    for _, key in ipairs(Inv.TABS) do b.tabs[key] = scene.find_model(TAB_NODE[key]) end
    b.panels = {
        inventory = scene.find_model("Inventory"),
        settings = scene.find_model("Settings"),
        store = scene.find_model("Town Store"),
        skills = scene.find_model("Skills"),
        map = scene.find_model("Map"),
        system = scene.find_model("System"),
    }
    b.inventory = b.panels.inventory
    b.store = b.panels.store
    b.stats_panel = scene.find_model("Inv Stats Panel")
    b.stats_labels = scene.find_model("Inv Stats Labels")
    b.stats_values = scene.find_model("Inv Stats Values")
    b.next_wave = scene.find_model("Sys Next Wave")
    b.sys_resume = scene.find_model("Sys Resume")
    b.store_gold = scene.find_model("Store Gold")
    b.enter_map = scene.find_model("Map Enter")
    b.map_dest = scene.find_model("Map Dest")
    b.map_exit = scene.find_model("Map Exit") or scene.find_model("Map Abandon")
    b.store_items = {}
    for _, slot in ipairs(Inv.SLOTS) do b.store_items[slot] = scene.find_model("Store " .. cap(slot)) end
    for _, k in ipairs(Inv.SLOTS) do b.eq[k] = scene.find_model("Inv Equip " .. cap(k)) end
    for i = 1, Inv.GRID_SIZE do b.bag[i] = scene.find_model("Inv Bag " .. i) end
    D._inv_nodes = b
    return b
end

function Inv.hub_hint(D, msg)
    D._hub_hint = msg
    local b = Inv.bind(D)
    if b and valid(b.title) and b.title.set_ui then
        b.title:set_ui({ body = T(msg) })
    end
end

function Inv.set_tab(D, name)
    Inv.ensure(D)
    D._abandon_armed = nil
    if name == "store" and D.state ~= "town" then
        Inv.hub_hint(D, "TOWN ONLY")
        return false
    end
    D._hub_tab = name
    local b = Inv.bind(D)
    if not b then return false end
    for key, panel in pairs(b.panels) do
        if valid(panel) and panel.set_enabled then
            panel:set_enabled(key == name)
        end
    end
    for key, tab in pairs(b.tabs) do
        if valid(tab) and tab.set_ui then
            tab:set_ui({
                fill = (key == name) and TAB_ACTIVE_FILL or TAB_IDLE_FILL,
                border = (key == name) and TAB_ACTIVE_FILL or TAB_IDLE_BORDER,
            })
        end
    end
    if valid(b.tabs.store) and b.tabs.store.set_ui and D.state ~= "town" then
        b.tabs.store:set_ui({
            fill = { 0.05, 0.05, 0.07, 0.7 },
            text_color = { 0.5, 0.52, 0.56, 0.85 },
        })
    end
    Inv.refresh(D)
    if name == "settings" then
        ensure_hub_settings()
        if D._settings_subtab == nil then D._settings_subtab = "game" end
        if _G.ATH_HUB_SETTINGS then
            if _G.ATH_HUB_SETTINGS.set_subtab then
                _G.ATH_HUB_SETTINGS.set_subtab(D._settings_subtab)
            elseif _G.ATH_HUB_SETTINGS.refresh then
                _G.ATH_HUB_SETTINGS.refresh(D)
            end
        end
    elseif name == "skills" then
        Inv.refresh_skills(D)
    end
    return true
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

function Inv.store_slots(D)
    local b = Inv.bind(D)
    if not b then return {} end
    local list = {}
    for _, k in ipairs(Inv.SLOTS) do
        list[#list + 1] = { kind = "store", key = k, id = "store_" .. k, node = b.store_items[k] }
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
    local name = (item and (item.name or item.id)) or ""
    return wrap(T(tostring(name)), 9)
end

-- The values column for the live stat panel. Keep both columns to twelve rows: the
-- engine's text widget clips longer bodies and trims leading blank lines.
function Inv.stats_values_text(st)
    local function pct(v) return string.format("%d%%", math.floor((v or 0.0) * 100.0 + 0.5)) end
    return string.format("%d\n%d\n%.1f\n%d\n%.2fs\n%.1f\n%d/%d %s\n%dx %.1fm / %.1fs\n%.2fs / %s\n%s / %s\n%.1f\n%.1f/s",
        math.floor((st.hp_max or 0) + 0.5), math.floor((st.dps or 0) + 0.5),
        st.attack_range or 0.0, math.floor((st.cleave or 0) + 0.5),
        st.fire_interval or 0.0, st.speed or 0.0, st.equip_load or 0, st.equip_load_max or 100,
        T(st.equip_load_tier or "LIGHT"), st.dodge_charges_max or 1, st.dodge_dist or 0.0,
        st.dodge_recharge or 0.0, st.dodge_iframes or 0.0, pct(st.dodge_guard), pct(st.poise),
        pct(st.armor), st.lifesteal or 0.0, st.regen or 0.0)
end

local SKILL_COLS, SKILL_MAX_RANK = 3, 5

function Inv.class_specs(D)
    local Balance = _G.ATH_BALANCE
    local class_id = D and D.hero_class
    if not (Balance and Balance.classes and class_id) then return {} end
    for _, row in ipairs(Balance.classes) do
        if row.id == class_id then return row.specializations or {} end
    end
    return {}
end

-- One icon per specialization: slot 1..3 maps directly to the branch.
function Inv.skill_slot_info(D, slot)
    local specs = Inv.class_specs(D)
    local branch = math.floor(slot or 1)
    if branch < 1 or branch > SKILL_COLS then return nil end
    local spec = specs[branch]
    if not spec then return nil end
    local pts = math.max(0, math.floor(D.skill_points or 0))
    local have = ((D.hero and D.hero.specialization_ranks) or {})[spec.id] or 0
    local card = { specialization = spec.id, max_rank = SKILL_MAX_RANK }
    local allowed = D.spec_card_allowed and D:spec_card_allowed(card)
    local can_buy = pts > 0 and have < SKILL_MAX_RANK and allowed
    local enabled = have > 0 or can_buy
    local status
    if have >= SKILL_MAX_RANK then
        status = T("OWNED")
    elseif can_buy then
        status = T("CLICK - 1 pt")
    elseif not allowed and have == 0 then
        status = T("LOCKED")
    elseif have > 0 then
        status = T("OWNED")
    else
        status = "-"
    end
    return {
        spec = spec, branch = branch, have = have,
        can_buy = can_buy, allowed = allowed, enabled = enabled, status = status,
    }
end

local function pct(v)
    return string.format("%d%%", math.floor((v or 0.0) * 100.0 + 0.5))
end

-- Combat values at a given rank (mirrors Duel:apply_on_hit_specializations).
function Inv.spec_rank_lines(spec, rank)
    rank = math.max(0, math.floor(rank or 0))
    if not spec or rank < 1 then return { T("(none)") } end
    local kind = spec.kind
    local lines = {}
    if kind == "dot" then
        lines[#lines + 1] = T("Hit %s / DoT %s of hit",
            pct((spec.initial_per_rank or 0) * rank),
            pct((spec.tick_per_rank or 0) * rank))
        if spec.spread then lines[#lines + 1] = T("Spreads on death (50%)") end
    elseif kind == "stack_dot" then
        local per = (spec.stack_base or 0.20) + (rank - 1) * (spec.stack_rank_add or 0.10)
        lines[#lines + 1] = T("Stack tick %s of hit (max %d)",
            pct(per), spec.max_stacks or 5)
    elseif kind == "frost" then
        lines[#lines + 1] = T("Frost hit %s, slow %s",
            pct((spec.damage_per_rank or 0) * rank),
            pct((spec.slow_per_rank or 0) * rank))
    elseif kind == "shadow" then
        lines[#lines + 1] = T("Pure hit %s, smoke miss %s",
            pct((spec.damage_per_rank or 0) * rank),
            pct((spec.miss_per_rank or 0) * rank))
    elseif kind == "vampirism" then
        lines[#lines + 1] = T("Hit %s / DoT %s of hit",
            pct((spec.initial_per_rank or 0) * rank),
            pct((spec.tick_per_rank or 0) * rank))
        lines[#lines + 1] = T("Heal %s of that damage", pct(spec.lifesteal_mult or 0.5))
    elseif kind == "frenzy" then
        lines[#lines + 1] = T("Per stack +%s dmg/AS/move (max %d)",
            pct((spec.stack_per_rank or 0.10) * rank), spec.max_stacks or 5)
    elseif kind == "daze" then
        lines[#lines + 1] = T("Enemy -%s dmg/AS/move",
            pct((spec.reduction_per_rank or 0) * rank))
    elseif kind == "explosion" or kind == "shockwave" then
        local dmg = (spec.damage or 0) + (rank - 1) * (spec.damage_per_rank or 0)
        lines[#lines + 1] = T("Death blast %s of hit (%.0fm)", pct(dmg), spec.radius or 3.0)
    elseif kind == "summon" then
        local cap = (spec.cap_base or 2) + (rank - 1) * (spec.cap_per_rank or 1)
        lines[#lines + 1] = T("Minion cap %d", cap)
    elseif kind == "pierce" then
        local dmg = (spec.damage or 0) + (rank - 1) * (spec.damage_per_rank or 0)
        lines[#lines + 1] = T("Pierce %s of hit", pct(dmg))
    elseif kind == "shard_cone" then
        local dmg = (spec.damage or 0) + (rank - 1) * (spec.damage_per_rank or 0)
        local n = (spec.shards_base or 4) + (rank - 1) * (spec.shards_per_rank or 1)
        lines[#lines + 1] = T("%d rock shards forward", n)
        lines[#lines + 1] = T("Each shard %s of hit (no riders)", pct(dmg))
        lines[#lines + 1] = T("Damages every enemy touched")
    elseif kind == "preservation" then
        lines[#lines + 1] = T("On damage taken: -%s dmg",
            pct((spec.damage_reduction_per_rank or 0) * rank))
        lines[#lines + 1] = T("Regen %s max HP over %.0fs",
            pct((spec.heal_fraction_per_rank or 0) * rank),
            spec.heal_seconds or 5.0)
    else
        lines[#lines + 1] = T(tostring(spec.desc or spec.id))
    end
    if spec.move_speed_per_rank then
        lines[#lines + 1] = T("Move +%s", pct((spec.move_speed_per_rank or 0) * rank))
    end
    return lines
end

function Inv.skill_tip(info)
    if not (info and info.spec) then return "" end
    local spec = info.spec
    local have = info.have or 0
    local lines = {
        T(tostring(spec.name or spec.id)),
        T("Level %d / %d", have, SKILL_MAX_RANK),
        info.status or "",
    }
    if info.have > 0 then
        lines[#lines + 1] = T("RIGHT-CLICK - refund 1")
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = T("NOW")
    for _, row in ipairs(Inv.spec_rank_lines(spec, have)) do
        lines[#lines + 1] = row
    end
    if have < SKILL_MAX_RANK then
        lines[#lines + 1] = ""
        lines[#lines + 1] = T("NEXT (rank %d)", have + 1)
        for _, row in ipairs(Inv.spec_rank_lines(spec, have + 1)) do
            lines[#lines + 1] = row
        end
    end
    local tip = table.concat(lines, "\n")
    return (Art and Art.ascii and Art.ascii(tip)) or tip
end

function Inv.refresh_skills(D)
    local header = scene.find_model("Skills Header")
    local pts = math.max(0, math.floor(D.skill_points or 0))
    if valid(header) then
        local body = T("SKILLS - %d pts", pts)
        header:set_ui({ body = (Art and Art.ascii and Art.ascii(body)) or body })
    end
    local clear = { 0.0, 0.0, 0.0, 0.0 }
    -- Hide any leftover rank-ladder nodes from older scenes.
    for i = SKILL_COLS + 1, 15 do
        local n = scene.find_model("Skill Node " .. i)
        if valid(n) and n.set_enabled then n:set_enabled(false) end
    end
    -- Invisible hit targets: no frame, no caption (space avoids engine "Button").
    for i = 1, SKILL_COLS do
        local n = scene.find_model("Skill Node " .. i)
        if valid(n) then
            if n.set_enabled then n:set_enabled(true) end
            n:set_ui({
                title = " ", body = "",
                fill = clear, border = clear, accent = clear, text_color = clear,
                font_scale = 0.01, align_h = "center", align_v = "middle",
            })
        end
    end
end

-- Spend one point into that specialization (next rank).
function Inv.try_allocate_skill(D, slot)
    local info = Inv.skill_slot_info(D, slot)
    if not info then return false end
    local spec = info.spec
    if not info.can_buy then
        if info.have >= SKILL_MAX_RANK then
            Inv.hub_hint(D, "ALREADY OWNED")
        elseif not info.allowed then
            Inv.hub_hint(D, "LOCKED")
        else
            Inv.hub_hint(D, tostring(D.skill_points or 0) < 1 and "No skill points." or "LOCKED")
        end
        return false
    end
    local ok, msg = D:allocate_skill(spec.id)
    if not ok then
        Inv.hub_hint(D, tostring(msg or "LOCKED"))
        return false
    end
    Inv.hub_hint(D, T("%s - rank %d", T(tostring(spec.name)), info.have + 1))
    Inv.refresh_skills(D)
    Inv.refresh(D)
    return true
end

-- Refund one rank from that specialization.
function Inv.try_deallocate_skill(D, slot)
    local info = Inv.skill_slot_info(D, slot)
    if not info then return false end
    if info.have < 1 then
        Inv.hub_hint(D, "NOTHING TO REMOVE")
        return false
    end
    local ok, msg = D:deallocate_skill(info.spec.id)
    if not ok then
        Inv.hub_hint(D, tostring(msg or "LOCKED"))
        return false
    end
    Inv.hub_hint(D, T("%s - rank %d", T(tostring(info.spec.name)), info.have - 1))
    Inv.refresh_skills(D)
    Inv.refresh(D)
    return true
end

function Inv.refresh(D)
    Inv.ensure(D)
    local b = Inv.bind(D)
    if not b then return end

    -- Authored text nodes render their `body` field (in text_color); see the
    -- backend's Text-widget path. (The transient cursor ghost/tooltip below still
    -- use the set_quad `label`, which the default quad style draws.)
    if valid(b.title) then
        b.title:set_ui({ body = T(D._hub_hint or "GEAR HUB") })
        D._hub_hint = nil
    end

    for key, tab in pairs(b.tabs) do
        if valid(tab) and tab.set_ui and TAB_TITLE[key] then
            tab:set_ui({ title = T(TAB_TITLE[key]) })
        end
    end
    if scene and scene.find_model then
        for _, pair in ipairs({
            { "Sys Resume", "RESUME" },
            { "Sys Quit", "QUIT TO MENU" },
            { "Sys Quit App", "QUIT" },
            { "Map Exit", "EXIT TO MAP" },
            { "Map Abandon", "EXIT TO MAP" },
            { "Menu Quit", "QUIT" },
        }) do
            local n = scene.find_model(pair[1])
            if valid(n) then n:set_ui({ title = T(pair[2]) }) end
        end
    end

    for _, s in ipairs(Inv.slots(D)) do
        local node = s.node
        if valid(node) then
            local item = Inv.item_at(D, s)
            local dragging = D._inv_drag and D._inv_drag.from.id == s.id
            if item then
                -- Name drops to the tile bottom; the icon overlay (draw_overlay)
                -- floats over the upper half.
                node:set_ui({
                    body = tile_label(item), text_color = SLOT_TEXT,
                    fill = dragging and ITEM_BG_DRAG or ITEM_BG,
                    border = Inv.RARITY[item.rarity or "common"],
                    align_h = "center", align_v = "bottom",
                })
            elseif s.kind == "equip" then
                node:set_ui({ body = T(Inv.SLOT_LABEL[s.key]), text_color = EMPTY_TEXT,
                    fill = EQUIP_BG, border = EQUIP_BORDER,
                    align_h = "default", align_v = "default" })
            else
                node:set_ui({ body = "", text_color = SLOT_TEXT, fill = SLOT_BG, border = SLOT_BORDER,
                    align_h = "default", align_v = "default" })
            end
        end
    end

    if valid(b.stats_labels) then b.stats_labels:set_ui({ body = T(STATS_LABELS) }) end
    if valid(b.stats_values) then
        local st = (D.gear_preview_stats and D:gear_preview_stats()) or {}
        b.stats_values:set_ui({ body = Inv.stats_values_text(st) })
    end

    -- Static authored headers (translated each refresh for live language switch).
    if scene and scene.find_model then
        for _, h in ipairs({
            { "Inv Equipped Header", "EQUIPPED" },
            { "Inv Backpack Header", "BACKPACK" },
            { "Store Header", "GEAR FOR SALE" },
        }) do
            local n = scene.find_model(h[1])
            if valid(n) then n:set_ui({ body = T(h[2]) }) end
        end
    end

    -- NEXT WAVE only on between-wave pause; RESUME only on mid-fight inventory peek.
    if valid(b.next_wave) and b.next_wave.set_enabled then
        local next_on = D.state == "pause" and D._between_wave == true
            and not (D.console and D.console.visible)
        b.next_wave:set_enabled(next_on)
    end
    if valid(b.sys_resume) and b.sys_resume.set_enabled then
        b.sys_resume:set_enabled(D.state == "pause" and not D._between_wave
            and not (D.console and D.console.visible))
    end
    if valid(b.sys_resume) then
        b.sys_resume:set_ui({ title = D._loot_inv and T("BACK") or T("RESUME") })
    end
    if valid(b.next_wave) then
        b.next_wave:set_ui({ title = T("NEXT WAVE   [Enter]") })
    end
    -- ENTER: start map from town, or push the next round between waves.
    local in_town = D.state == "town"
    local can_enter = in_town or (D.state == "pause" and D._between_wave == true)
    if D.console and D.console.visible then can_enter = false end
    if valid(b.enter_map) and b.enter_map.set_enabled then
        b.enter_map:set_enabled(can_enter)
    end
    if valid(b.enter_map) then
        b.enter_map:set_ui({ title = T("ENTER") })
    end
    if valid(b.map_exit) then
        b.map_exit:set_ui({ title = T("EXIT TO MAP") })
    end
    if valid(b.map_dest) then
        local m = D.active_map and D:active_map() or nil
        local name = m and (m.name or m.id) or "?"
        local round
        if in_town or D.state == "worldmap" then
            round = (D.next_wave_for_map and D:next_wave_for_map(D.map_index)) or 1
        elseif D.state == "pause" and D._between_wave then
            round = (D.wave_index or 1) + 1
        else
            round = D.wave_index or D.round or 1
        end
        b.map_dest:set_ui({
            body = T("%s\nROUND %d", T(tostring(name)), round),
        })
    end
    if D._hub_tab == "store" and D.state == "town" then
        if valid(b.store_gold) then b.store_gold:set_ui({ body = T("GOLD  %s", tostring(D.gold or 0)) }) end
        for i, slot in ipairs(Inv.SLOTS) do
            local node = b.store_items and b.store_items[slot]
            local item = D.store_offers and D.store_offers[slot]
            if valid(node) and item then
                local price = D.store_price and D:store_price(item) or 0
                node:set_ui({ title = "", body = string.format("%s\n[%d]  %d %s", tile_label(item), i, price, T("Gold")),
                    border = Inv.RARITY[item.rarity or "common"], align_h = "center", align_v = "bottom" })
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Interaction — poll authored drag state, resolve clicks + drops.
-- ---------------------------------------------------------------------------
function Inv.update(D)
    Inv.ensure(D)
    if not (runtime_ui and runtime_ui.get_state) then return end
    local tab = D._hub_tab or "map"
    if tab == "skills" then
        local hover
        for i = 1, SKILL_COLS do
            local stt = runtime_ui.get_state(SCREEN, "hub_skill_" .. i)
            if stt and stt.hovered then
                local info = Inv.skill_slot_info(D, i)
                if info then
                    hover = {
                        slot = i, info = info, mx = stt.mouse_x, my = stt.mouse_y,
                        tip = Inv.skill_tip(info),
                        border = (info.spec.accent or { 0.62, 0.34, 0.86, 1.0 }),
                    }
                end
            end
            if stt and stt.right_clicked then
                Inv.try_deallocate_skill(D, i)
            end
        end
        D._inv_drag, D._inv_selected, D._inv_hover, D._skill_hover = nil, nil, nil, hover
        Inv.draw_overlay(D)
        return
    end
    if tab == "store" and D.state == "town" then
        local hover
        for _, s in ipairs(Inv.store_slots(D)) do
            local item = D.store_offers and D.store_offers[s.key]
            local stt = item and runtime_ui.get_state(SCREEN, s.id)
            if stt and stt.hovered then hover = { item = item, slot = s, mx = stt.mouse_x, my = stt.mouse_y } end
            if stt and stt.right_clicked and D.buy_store_offer then D:buy_store_offer(s.key) end
        end
        D._inv_drag, D._inv_selected, D._inv_hover, D._skill_hover = nil, nil, hover, nil
        Inv.draw_overlay(D)
        return
    end
    if tab ~= "inventory" then
        D._inv_drag, D._inv_selected, D._inv_hover, D._skill_hover = nil, nil, nil, nil
        Inv.draw_overlay(D)
        return
    end
    D._skill_hover = nil
    local slots = Inv.slots(D)
    if #slots == 0 then return end

    -- Pickups + hover. A press on a draggable slot becomes a DRAG (the engine
    -- swallows `clicked`); a clean tap is detected on release for double-tap equip.
    local hover, tap_slot, rclick_slot = nil, nil, nil
    for _, s in ipairs(slots) do
        local item = Inv.item_at(D, s)
        if item then
            local stt = runtime_ui.get_state(SCREEN, s.id)
            if stt then
                if stt.hovered then hover = { item = item, slot = s, mx = stt.mouse_x, my = stt.mouse_y } end
                if stt.right_clicked then rclick_slot = s end
                if stt.drag_started and not D._inv_drag then
                    D._inv_drag = { from = s, mx = stt.mouse_x, my = stt.mouse_y }
                elseif stt.clicked and not stt.dragging and not D._inv_drag then
                    tap_slot = s
                end
            end
        end
    end
    D._inv_hover = (not D._inv_drag) and hover or nil

    -- RIGHT-CLICK equips a bag item / unequips a doll item, via the widget's own
    -- right_clicked state (the global input.* mouse reads return false whenever
    -- the UI has mouse capture — i.e. exactly when hovering a slot). Double-tap
    -- below stays as the touch path — Android has no right button.
    if rclick_slot and not D._inv_drag then
        if rclick_slot.kind == "grid" then Inv.try_equip(D, rclick_slot.key) else Inv.try_unequip(D, rclick_slot.key) end
        D._inv_hover = nil -- the item just moved; drop the stale tooltip this frame
        D._inv_last_click = nil
        D._inv_selected = nil
    end

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
                local tr = Inv.trash_rect(D)
                local target = nil
                for _, s in ipairs(slots) do
                    local r = valid(s.node) and s.node.get_ui_rect and s.node:get_ui_rect() or nil
                    if r and r.x and mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                        target = s; break
                    end
                end
                if tr and mx >= tr.x and mx <= tr.x + tr.w and my >= tr.y and my <= tr.y + tr.h then
                    -- Dropped on the DESTROY plate: the item is gone for good.
                    local gone = Inv.item_at(D, drag.from)
                    Inv.set_raw(D, drag.from, nil)
                    if D.recompute_hero_stats then D:recompute_hero_stats() end
                    if gone and D.set_flash then
                        D:set_flash("Destroyed %s", (_G.ATH_I18N and _G.ATH_I18N.t(tostring(gone.name or gone.id))) or tostring(gone.name or gone.id))
                    end
                    if D.haptic then D:haptic(12) end
                    changed(D)
                    D._inv_last_click = nil
                    D._inv_selected = nil
                elseif target and target.id ~= drag.from.id then
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
            D._inv_selected = nil
        else
            D._inv_last_click = { id = tap_slot.id, t = now }
            D._inv_selected = { item = Inv.item_at(D, tap_slot), slot = tap_slot }
        end
    end

    Inv.draw_overlay(D)
end

-- ---------------------------------------------------------------------------
-- Hover COMPARE — hovering a bag item shows what equipping it would change vs
-- the currently equipped piece in its slot, as +/- stat deltas. Computed by
-- swapping the item into a copy of the preview pipeline (mutate-and-restore on
-- D.gear_equipped; gear_preview_stats is pure over it).
-- ---------------------------------------------------------------------------
local COMPARE_STATS = {
    { key = "hp_max", label = "HP", fmt = "%+.0f" },
    { key = "dps", label = "Damage", fmt = "%+.0f" },
    { key = "attack_range", label = "Range", fmt = "%+.1f" },
    { key = "cleave", label = "Shots", fmt = "%+.0f" },
    { key = "fire_interval", label = "Fire time", fmt = "%+.2fs", lower = true },
    { key = "speed", label = "Move", fmt = "%+.1f" },
    { key = "equip_load", label = "Weight", fmt = "%+.0f" },
    { key = "armor", label = "Armor", fmt = "%+.0f%%", pct = true },
    { key = "crit_chance", label = "Crit", fmt = "%+.0f%%", pct = true },
    { key = "lifesteal", label = "Lifesteal", fmt = "%+.1f" },
    { key = "regen", label = "Regen", fmt = "%+.1f" },
    { key = "pickup_range", label = "Pickup", fmt = "%+.1f" },
    { key = "gold_find", label = "Gold", fmt = "%+.0f%%", pct = true },
    { key = "dodge_charges_max", label = "Dodges", fmt = "%+.0f" },
    { key = "dodge_dist", label = "Dodge dist", fmt = "%+.1fm" },
    { key = "dodge_recharge", label = "Dodge CD", fmt = "%+.1fs", lower = true },
    { key = "dodge_iframes", label = "I-frames", fmt = "%+.2fs" },
    { key = "dodge_guard", label = "Dash guard", fmt = "%+.0f%%", pct = true },
    { key = "poise", label = "Poise", fmt = "%+.0f%%", pct = true },
    { key = "thorns", label = "Retaliate", fmt = "%+.1f" },
    { key = "whirl", label = "Orbit", fmt = "%+.0f" },
    { key = "bleed_on_crit", label = "Bleed", fmt = "%+.1f/s" },
    { key = "dodge_blades", label = "Dodge blade", fmt = "%+.2f" },
    { key = "retaliation_orbit", label = "Retal orbit", fmt = "%+.2f" },
    { key = "flask_nova", label = "Flask nova", fmt = "%+.2f" },
    { key = "flask_burst", label = "Flask burst", fmt = "%+.2f" },
}

function Inv.compare_text(D, hv, polarity)
    if not (hv.slot and (hv.slot.kind == "grid" or hv.slot.kind == "store")
        and hv.item.slot and D.gear_preview_stats) then return nil end
    local slot = hv.item.slot
    local equipped = D.gear_equipped and D.gear_equipped[slot]
    local before = D:gear_preview_stats()
    D.gear_equipped[slot] = hv.item
    local after = D:gear_preview_stats()
    D.gear_equipped[slot] = equipped
    local lines = {}
    if not polarity and after.equip_load_tier ~= before.equip_load_tier then
        lines[#lines + 1] = string.format("%-10s %s -> %s", T("Load tier"), T(before.equip_load_tier), T(after.equip_load_tier))
    end
    for _, st in ipairs(COMPARE_STATS) do
        local d = (after[st.key] or 0.0) - (before[st.key] or 0.0)
        if st.pct then d = d * 100.0 end
        local good = st.lower and d < 0.0 or not st.lower and d > 0.0
        if math.abs(d) > 0.005 and (not polarity or (polarity > 0) == good) then
            lines[#lines + 1] = string.format("%-10s " .. st.fmt, T(st.label), d)
        end
    end
    if #lines == 0 then return nil end
    if polarity then return table.concat(lines, "\n") end
    local head = equipped and T("- vs %s -", T(tostring(equipped.name or equipped.id)))
        or T("- if equipped -")
    return head .. "\n" .. table.concat(lines, "\n")
end

function Inv.item_details(item)
    local tags = item.tags or {}
    local rarity = T(item.rarity or "common")
    local tag_line = {}
    for _, tag in ipairs(tags) do tag_line[#tag_line + 1] = T(tag) end
    return T("%s\n%s %s\nTags: %s\nClass: %s   Weight: %s\n%s\n%s",
        T(tostring(item.name or item.id)), rarity,
        T(Inv.SLOT_LABEL[item.slot] or "?"), #tag_line > 0 and table.concat(tag_line, " / ") or T("General"),
        T(item.class or "Any"), tostring(item.weight or 0), T(item.desc or "No mechanics."),
        T(item.lore or "Recovered field gear, built to survive another wave."))
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

-- The destroy zone exists only while a drag is in flight: a red plate spanning
-- the width of the bag grid, just under it (LIVE rects, so an editor re-layout
-- still lines up). nil until the authored nodes resolve.
function Inv.bag_bounds(D)
    local b = Inv.bind(D)
    if not b then return nil end
    local x0, y0, x1, y1
    for i = 1, Inv.GRID_SIZE do
        local n = b.bag[i]
        local r = valid(n) and n.get_ui_rect and n:get_ui_rect() or nil
        if r and r.x then
            x0 = math.min(x0 or r.x, r.x)
            y0 = math.min(y0 or r.y, r.y)
            x1 = math.max(x1 or 0.0, r.x + r.w)
            y1 = math.max(y1 or 0.0, r.y + r.h)
        end
    end
    if not x0 then return nil end
    return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

function Inv.trash_rect(D)
    local bounds = Inv.bag_bounds(D)
    if not bounds then return nil end
    local hud = Art.s("hud")
    return { x = bounds.x, y = bounds.y + bounds.h + 10.0 * hud, w = bounds.w, h = 52.0 * hud }
end

local function Inv_clear_inventory_overlays()
    for _, id in ipairs({ "inv_ghost", "inv_tip", "inv_trash", "inv_selected_panel", "inv_selected_icon",
        "inv_selected_text", "inv_selected_good", "inv_selected_bad" }) do
        runtime_ui.remove(SCREEN, id)
    end
    for _, k in ipairs(Inv.SLOTS) do runtime_ui.remove(SCREEN, "inv_ic_inv_eq_" .. k) end
    for _, k in ipairs(Inv.SLOTS) do runtime_ui.remove(SCREEN, "inv_ic_store_" .. k) end
    for i = 1, Inv.GRID_SIZE do runtime_ui.remove(SCREEN, "inv_ic_inv_bag_" .. i) end
end

local function Inv_clear_skill_overlays()
    for i = 1, 15 do
        runtime_ui.remove(SCREEN, "sk_fr_" .. i)
        runtime_ui.remove(SCREEN, "sk_ic_" .. i)
        runtime_ui.remove(SCREEN, "sk_lv_" .. i)
    end
    runtime_ui.remove(SCREEN, "sk_tip")
end

function Inv.draw_overlay(D)
    if not (runtime_ui and runtime_ui.set_quad) then return end
    local tab = D._hub_tab or "map"
    local in_store = tab == "store" and D.state == "town"
    if tab == "skills" then
        Inv_clear_inventory_overlays()
        Art.surface_size()
        local vp = Art._vp
        local rw, rh = vp.rw or 2400.0, vp.rh or 1080.0
        local function S(v) return v * Art.s("hud") end
        for i = SKILL_COLS + 1, 15 do
            runtime_ui.remove(SCREEN, "sk_fr_" .. i)
            runtime_ui.remove(SCREEN, "sk_ic_" .. i)
            runtime_ui.remove(SCREEN, "sk_lv_" .. i)
        end
        for i = 1, SKILL_COLS do
            local n = scene.find_model("Skill Node " .. i)
            local info = Inv.skill_slot_info(D, i)
            local icon = info and info.spec and info.spec.icon
            local r = icon and valid(n) and n.get_ui_rect and n:get_ui_rect() or nil
            local fr_id, ic_id, lv_id = "sk_fr_" .. i, "sk_ic_" .. i, "sk_lv_" .. i
            if r and r.x then
                local accent = info.spec.accent or { 0.62, 0.34, 0.86, 1.0 }
                local frame_fill = info.enabled
                    and { 0.06, 0.07, 0.10, 0.92 }
                    or { 0.04, 0.045, 0.055, 0.65 }
                local frame_border = info.enabled
                    and (info.have > 0 and accent or (info.can_buy and { 0.96, 0.82, 0.30, 0.95 }
                        or { 0.45, 0.48, 0.55, 0.85 }))
                    or { 0.22, 0.24, 0.28, 0.55 }
                runtime_ui.set_quad(SCREEN, fr_id, {
                    x = r.x, y = r.y, width = r.w, height = r.h, style = "panel",
                    fill = frame_fill, border = frame_border,
                    no_input = true, bring_to_front = true, z = OVERLAY_Z - 1100.0,
                })
                local pad = math.min(r.w, r.h) * 0.06
                local isz = math.min(r.w, r.h) - pad * 2.0
                local tint = info.enabled and { 1.0, 1.0, 1.0, 1.0 }
                    or { 0.35, 0.37, 0.40, 0.5 }
                runtime_ui.set_quad(SCREEN, ic_id, {
                    x = r.x + (r.w - isz) * 0.5, y = r.y + (r.h - isz) * 0.5,
                    width = isz, height = isz, style = "image", image = icon,
                    fill = { 0.0, 0.0, 0.0, 0.0 }, border = { 0.0, 0.0, 0.0, 0.0 },
                    image_tint = tint, no_input = true, bring_to_front = true, z = OVERLAY_Z - 1000.0,
                })
                if info.have > 0 then
                    local lw, lh = S(16.0), S(14.0)
                    runtime_ui.set_quad(SCREEN, lv_id, {
                        x = r.x + r.w - lw + S(2.0), y = r.y + r.h - lh + S(2.0),
                        width = lw, height = lh, style = "text",
                        fill = { 0.0, 0.0, 0.0, 0.0 }, border = { 0.0, 0.0, 0.0, 0.0 },
                        body = tostring(info.have),
                        text_color = { 0.98, 0.94, 0.78, 1.0 },
                        font_scale = 0.8, align_h = "right", align_v = "bottom",
                        no_input = true, bring_to_front = true, z = OVERLAY_Z - 400.0,
                    })
                else
                    runtime_ui.remove(SCREEN, lv_id)
                end
            else
                runtime_ui.remove(SCREEN, fr_id)
                runtime_ui.remove(SCREEN, ic_id)
                runtime_ui.remove(SCREEN, lv_id)
            end
        end
        local hv = D._skill_hover
        if hv and hv.tip and hv.tip ~= "" then
            local tw, th = S(560.0), S(420.0)
            local tx = (hv.mx or 0.0) + S(18.0)
            local ty = (hv.my or 0.0) + S(12.0)
            if tx + tw > rw then tx = rw - tw - S(8.0) end
            if ty + th > rh then ty = rh - th - S(8.0) end
            runtime_ui.set_quad(SCREEN, "sk_tip", {
                x = tx, y = ty, style = "text", fit = true,
                fill = { 0.04, 0.05, 0.08, 0.98 }, border = hv.border or { 0.62, 0.34, 0.86, 1.0 },
                body = hv.tip, text_color = { 0.92, 0.94, 0.98, 1.0 },
                font_scale = 1.35, align_h = "left", align_v = "top",
                no_input = true, bring_to_front = true, z = OVERLAY_Z,
            })
        else
            runtime_ui.remove(SCREEN, "sk_tip")
        end
        return
    end
    Inv_clear_skill_overlays()
    if tab ~= "inventory" and not in_store then
        Inv_clear_inventory_overlays()
        return
    end
    Art.surface_size()
    local vp = Art._vp
    local rw, rh = vp.rw or 2400.0, vp.rh or 1080.0
    local function S(v) return v * Art.s("hud") end

    -- Per-item slot icons: text-style widgets can't render images, so each
    -- occupied tile gets a transient image quad floated over its upper half.
    local icon_slots = in_store and Inv.store_slots(D) or Inv.slots(D)
    for _, s in ipairs(icon_slots) do
        local id = "inv_ic_" .. s.id
        local item = s.kind == "store" and (D.store_offers and D.store_offers[s.key]) or nil
        if s.kind ~= "store" then item = Inv.item_at(D, s) end
        local icon = item and Inv.SLOT_ICON[item.slot]
        local r = icon and valid(s.node) and s.node.get_ui_rect and s.node:get_ui_rect() or nil
        if r and r.x and not (D._inv_drag and D._inv_drag.from.id == s.id) then
            local isz = math.min(r.w, r.h) * 0.46
            runtime_ui.set_quad(SCREEN, id, {
                x = r.x + (r.w - isz) * 0.5, y = r.y + r.h * 0.05,
                width = isz, height = isz, style = "image", image = icon,
                fill = { 0.0, 0.0, 0.0, 0.0 }, border = { 0.0, 0.0, 0.0, 0.0 },
                no_input = true, bring_to_front = true, z = OVERLAY_Z - 1000.0,
            })
        else
            runtime_ui.remove(SCREEN, id)
        end
    end
    if in_store then
        for _, s in ipairs(Inv.slots(D)) do runtime_ui.remove(SCREEN, "inv_ic_" .. s.id) end
    else
        for _, s in ipairs(Inv.store_slots(D)) do runtime_ui.remove(SCREEN, "inv_ic_" .. s.id) end
    end

    local selected = D._inv_selected
    local b = Inv.bind(D)
    local sr = selected and selected.item and b and valid(b.stats_panel)
        and b.stats_panel.get_ui_rect and b.stats_panel:get_ui_rect() or nil
    if sr and sr.x and not D._inv_drag then
        local item = selected.item
        runtime_ui.set_quad(SCREEN, "inv_selected_panel", {
            x = sr.x, y = sr.y, width = sr.w, height = sr.h, style = "text",
            fill = { 0.035, 0.04, 0.065, 0.99 }, border = Inv.RARITY[item.rarity or "common"],
            body = "", no_input = true, bring_to_front = true, z = OVERLAY_Z - 400.0,
        })
        runtime_ui.set_quad(SCREEN, "inv_selected_icon", {
            x = sr.x + 14.0, y = sr.y + 14.0, width = 84.0, height = 84.0,
            style = "image", image = Inv.SLOT_ICON[item.slot], fill = { 0.0, 0.0, 0.0, 0.0 },
            border = { 0.0, 0.0, 0.0, 0.0 }, no_input = true, bring_to_front = true, z = OVERLAY_Z - 300.0,
        })
        runtime_ui.set_quad(SCREEN, "inv_selected_text", {
            x = sr.x + 108.0, y = sr.y + 12.0, width = sr.w - 122.0, height = 148.0, style = "text",
            fill = { 0.0, 0.0, 0.0, 0.0 }, border = { 0.0, 0.0, 0.0, 0.0 }, body = Inv.item_details(item),
            text_color = { 0.92, 0.94, 0.98, 1.0 }, font_scale = 1.15,
            align_h = "left", align_v = "top", no_input = true, bring_to_front = true, z = OVERLAY_Z - 200.0,
        })
        local good = Inv.compare_text(D, selected, 1)
        local bad = Inv.compare_text(D, selected, -1)
        runtime_ui.set_quad(SCREEN, "inv_selected_good", {
            x = sr.x + 14.0, y = sr.y + 174.0, width = sr.w * 0.5 - 20.0, height = sr.h - 186.0, style = "text",
            fill = { 0.0, 0.0, 0.0, 0.0 }, border = { 0.0, 0.0, 0.0, 0.0 },
            body = good and (T("BETTER") .. "\n" .. good) or "", text_color = { 0.42, 0.95, 0.55, 1.0 }, font_scale = 1.0,
            align_h = "left", align_v = "top", no_input = true, bring_to_front = true, z = OVERLAY_Z - 200.0,
        })
        runtime_ui.set_quad(SCREEN, "inv_selected_bad", {
            x = sr.x + sr.w * 0.5, y = sr.y + 174.0, width = sr.w * 0.5 - 14.0, height = sr.h - 186.0, style = "text",
            fill = { 0.0, 0.0, 0.0, 0.0 }, border = { 0.0, 0.0, 0.0, 0.0 },
            body = bad and (T("WORSE") .. "\n" .. bad) or "", text_color = { 1.0, 0.38, 0.34, 1.0 }, font_scale = 1.0,
            align_h = "left", align_v = "top", no_input = true, bring_to_front = true, z = OVERLAY_Z - 200.0,
        })
    else
        for _, id in ipairs({ "inv_selected_panel", "inv_selected_icon", "inv_selected_text", "inv_selected_good", "inv_selected_bad" }) do
            runtime_ui.remove(SCREEN, id)
        end
    end

    if D._inv_drag then
        local item = Inv.item_at(D, D._inv_drag.from)
        if item then
            local cell = S(64.0)
            runtime_ui.set_quad(SCREEN, "inv_ghost", {
                x = (D._inv_drag.mx or 0.0) - cell * 0.5,
                y = (D._inv_drag.my or 0.0) - cell * 0.5,
                width = cell, height = cell,
                image = Inv.SLOT_ICON[item.slot],
                fill = { 0.16, 0.18, 0.24, 0.96 }, border = Inv.RARITY[item.rarity or "common"],
                accent = { 0.0, 0.0, 0.0, 0.0 },
                body = tile_label(item), text_color = SLOT_TEXT,
                font_scale = 0.85, align_h = "center",
                no_input = true, bring_to_front = true, z = OVERLAY_Z,
            })
        end
        local tr = Inv.trash_rect(D)
        if tr then
            local mx, my = D._inv_drag.mx or 0.0, D._inv_drag.my or 0.0
            local over = mx >= tr.x and mx <= tr.x + tr.w and my >= tr.y and my <= tr.y + tr.h
            runtime_ui.set_quad(SCREEN, "inv_trash", {
                x = tr.x, y = tr.y, width = tr.w, height = tr.h, style = "text",
                fill = over and { 0.45, 0.09, 0.08, 0.97 } or { 0.16, 0.05, 0.05, 0.92 },
                border = { 0.95, 0.32, 0.26, 0.95 },
                body = T("DROP HERE TO DESTROY"), text_color = { 1.0, 0.6, 0.55, 1.0 },
                font_scale = 1.4, align_h = "center", align_v = "middle",
                no_input = true, bring_to_front = true, z = OVERLAY_Z - 500.0,
            })
        end
    else
        runtime_ui.remove(SCREEN, "inv_ghost")
        runtime_ui.remove(SCREEN, "inv_trash")
    end

    local hv = D._inv_hover
    if hv and hv.item and not D._inv_drag then
        local tip = Inv.item_details(hv.item)
        if hv.slot and hv.slot.kind == "store" then
            local equipped = D.gear_equipped and D.gear_equipped[hv.item.slot]
            tip = tip .. "\n" .. T("Equipped: %s", tostring(equipped and T(equipped.name or equipped.id) or T("Nothing")))
        end
        local cmp = Inv.compare_text(D, hv)
        if cmp then tip = tip .. "\n" .. cmp end
        -- The engine auto-fits the box to the text (fit=true); tw/th are generous
        -- upper bounds used only to keep the popup on-screen near the edges.
        local tw, th = S(420.0), S(340.0)
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
    if not (b and valid(b.group) and b.group.set_enabled) then return end
    local opening = not D._inv_open
    b.group:set_enabled(true)
    D._inv_open = true
    if opening then
        -- Wave clear / town land on MAP. Mid-fight gear peek keeps the last tab.
        local tab = D._hub_tab or "map"
        if D._between_wave or D.state == "town" then tab = "map" end
        if tab == "store" and D.state ~= "town" then tab = "map" end
        Inv.set_tab(D, tab)
    end
    if ATH_COMMON.sync_world_freeze then ATH_COMMON.sync_world_freeze(D) end
end

function Inv.hide(D)
    local b = D._inv_nodes
    if b and valid(b.group) and b.group.set_enabled then b.group:set_enabled(false) end
    D._inv_open = false
    D._abandon_armed = nil
    Inv.clear(D)
    if ATH_COMMON.sync_world_freeze then ATH_COMMON.sync_world_freeze(D) end
end

-- Tear down the transient cursor overlays + drop any in-flight drag.
function Inv.clear(D)
    if runtime_ui and runtime_ui.remove then
        runtime_ui.remove(SCREEN, "inv_ghost")
        runtime_ui.remove(SCREEN, "inv_tip")
        runtime_ui.remove(SCREEN, "inv_lang_en")
        runtime_ui.remove(SCREEN, "inv_lang_el")
        runtime_ui.remove(SCREEN, "inv_trash")
        runtime_ui.remove(SCREEN, "inv_selected_panel")
        runtime_ui.remove(SCREEN, "inv_selected_icon")
        runtime_ui.remove(SCREEN, "inv_selected_text")
        runtime_ui.remove(SCREEN, "inv_selected_good")
        runtime_ui.remove(SCREEN, "inv_selected_bad")
        runtime_ui.remove(SCREEN, "inv_loot_panel")
        runtime_ui.remove(SCREEN, "inv_loot_title")
        for _, rarity in ipairs(Inv.RARITIES) do runtime_ui.remove(SCREEN, "inv_loot_" .. rarity) end
        for _, k in ipairs(Inv.SLOTS) do runtime_ui.remove(SCREEN, "inv_ic_inv_eq_" .. k) end
        for _, k in ipairs(Inv.SLOTS) do runtime_ui.remove(SCREEN, "inv_ic_store_" .. k) end
        for i = 1, Inv.GRID_SIZE do runtime_ui.remove(SCREEN, "inv_ic_inv_bag_" .. i) end
        for i = 1, SKILL_COLS * SKILL_MAX_RANK do
            runtime_ui.remove(SCREEN, "sk_fr_" .. i)
            runtime_ui.remove(SCREEN, "sk_ic_" .. i)
            runtime_ui.remove(SCREEN, "sk_lv_" .. i)
        end
        runtime_ui.remove(SCREEN, "sk_tip")
    end
    D._inv_drag = nil
    D._inv_hover = nil
    D._skill_hover = nil
end

_G.ATH_INVENTORY = Inv
return Inv
