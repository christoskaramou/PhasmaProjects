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

local SKILL_COLS = 3

function Inv.class_specs(D)
    local Balance = _G.ATH_BALANCE
    local class_id = D and D.hero_class
    if not (Balance and Balance.classes and class_id) then return {} end
    for _, row in ipairs(Balance.classes) do
        if row.id == class_id then return row.specializations or {} end
    end
    return {}
end

-- Hero Grid: one horizontal strip per specialization (top → bottom).
-- Within a strip, tiers flow left → right; exclusive twins stack in one column.
local TREE_STEPS = {
    { "key" }, { "fa" }, { "fb" }, { "ma", "mb" }, { "ta", "tb" }, { "cap" },
}

local TIER_LABEL = {
    keystone = "KEYSTONE", foundation = "FOUNDATION", mutation = "MUTATION",
    technique = "TECHNIQUE", capstone = "CAPSTONE",
}

-- Cell state for one node in one spec column.
function Inv.tree_cell_info(D, spec, node)
    local hero = D.hero
    local mine = (D.class_tree_nodes and D:class_tree_nodes()[spec.id]) or {}
    local have = mine[node.id] or 0
    local pts = math.max(0, math.floor(D.skill_points or 0))
    local allowed, why
    if D.tree_node_allowed then allowed, why = D:tree_node_allowed(spec.id, node.id) end
    local can_buy = pts > 0 and allowed == true
    local points = 0
    for _, r in pairs(mine) do points = points + r end
    local status
    if have >= node.max_rank then
        status = T("MAXED")
    elseif can_buy then
        status = T("CLICK - 1 pt")
    elseif allowed and pts < 1 then
        status = T("No skill points.")
    else
        status = why or T("LOCKED")
    end
    return {
        spec = spec, node = node, have = have, points = points,
        allowed = allowed == true, can_buy = can_buy, status = status,
        primary = hero and hero.primary_spec == spec.id,
        class_id = D.hero_class, alloc = mine,
    }
end

local function pct(v)
    return string.format("%d%%", math.floor((v or 0.0) * 100.0 + 0.5))
end

local function on_hit()
    local B = _G.ATH_BALANCE
    return (B and B.on_hit) or { tick = 0.5, duration = 4.0, spread_radius = 4.0 }
end

-- Forward-declared; filled below so spec_fx_lines can reference it.
local FX_DESC

-- Effective rider summary from the computed spec_fx (mirrors the duel runtime).
-- Every line is a concrete number — no prose-only briefing.
function Inv.spec_fx_lines(spec, fx)
    if not spec or not fx or (fx.points or 0) < 1 then return { T("(none)") } end
    local kind = spec.kind
    local lines = {}
    local oh = on_hit()
    local dur = fx.duration or spec.duration or oh.duration
    if kind == "dot" then
        local spread = spec.spread and 0.5 or 1.0
        lines[#lines + 1] = T("On hit: %s of hit damage", pct((fx.initial or 0) * spread))
        lines[#lines + 1] = T("DoT: %s of hit every %.1fs for %.0fs",
            pct((fx.tick or 0) * spread), oh.tick, dur)
        if spec.spread then
            lines[#lines + 1] = T("Death spread: %.0fm, %d target, 50%% strength",
                (fx.spread_plus and fx.spread_plus.radius) or oh.spread_radius,
                (fx.spread_plus and fx.spread_plus.targets) or 1)
        end
    elseif kind == "stack_dot" then
        local max_s = fx.max_stacks or spec.max_stacks or 5
        local per = fx.stack_per or 0.20
        local vals = {}
        for s = 1, max_s do vals[#vals + 1] = pct(per * s) end
        lines[#lines + 1] = T("Per stack tick: %s of hit (1-%d: %s)",
            pct(per), max_s, table.concat(vals, "/"))
        lines[#lines + 1] = T("Applies on hit + every %.1fs for %.0fs", oh.tick, dur)
        if fx.fast_tick_max then
            lines[#lines + 1] = T("At max stacks: tick every %.2fs", fx.fast_tick_max.tick or 0.35)
        end
    elseif kind == "frost" then
        lines[#lines + 1] = T("Frost hit: %s of hit", pct(fx.damage))
        lines[#lines + 1] = T("Slow move/attack: -%s for %.0fs",
            pct(math.min(0.75, fx.slow or 0)), dur)
    elseif kind == "shadow" then
        lines[#lines + 1] = T("Pure hit: %s of hit", pct(fx.damage))
        lines[#lines + 1] = T("Smoke miss chance: %s for %.0fs",
            pct(math.min(0.75, fx.miss or 0)), dur)
        if fx.fleet then
            lines[#lines + 1] = T("Fleet: +%s move while smoked", pct(fx.fleet.move or 0.05))
        end
    elseif kind == "vampirism" then
        lines[#lines + 1] = T("On hit: %s of hit damage", pct(fx.initial))
        lines[#lines + 1] = T("DoT: %s of hit every %.1fs for %.0fs",
            pct(fx.tick), oh.tick, dur)
        lines[#lines + 1] = T("Heal: %s of rider damage dealt", pct(fx.lifesteal_mult or 0.5))
        if fx.overheal_shield then
            lines[#lines + 1] = T("Overheal shield cap: %s max HP", pct(fx.overheal_shield.cap or 0.10))
        end
    elseif kind == "frenzy" then
        local max_s = fx.max_stacks or 5
        lines[#lines + 1] = T("Per stack: +%s damage, +%s attack speed, +%s move",
            pct(fx.dmg_per_stack), pct(fx.as_per_stack), pct(fx.move_per_stack))
        lines[#lines + 1] = T("Max %d stacks (%.0fs): +%s dmg / +%s AS / +%s move",
            max_s, fx.duration or 3.0,
            pct((fx.dmg_per_stack or 0) * max_s),
            pct((fx.as_per_stack or 0) * max_s),
            pct((fx.move_per_stack or 0) * max_s))
    elseif kind == "daze" then
        lines[#lines + 1] = T("Enemy damage/AS/move: -%s for %.0fs",
            pct(math.min(0.75, fx.reduction or 0)), dur)
    elseif kind == "explosion" or kind == "shockwave" then
        lines[#lines + 1] = T("Death blast: %s of hit in %.1fm", pct(fx.damage), fx.radius or 3.0)
        if fx.stun_wave then
            lines[#lines + 1] = T("Survivors slowed %s for %.0fs",
                pct(fx.stun_wave.daze or 0.2), fx.stun_wave.dur or 2.0)
        end
    elseif kind == "summon" then
        local Balance = _G.ATH_BALANCE
        local sk = Balance and Balance.minions and Balance.minions.skeleton
        lines[#lines + 1] = T("Skeleton-mage cap: %d", fx.cap or 2)
        if sk then
            lines[#lines + 1] = T("Each: %s hero DPS, %s hero HP, %.0fm range",
                pct(sk.dps_mult), pct(sk.hp_mult), sk.range or 6.0)
            lines[#lines + 1] = T("Attack every %.1fs, lasts %.0fs",
                sk.attack_interval or 0.8, sk.duration or 30.0)
        end
        if fx.minion_dmg then
            lines[#lines + 1] = T("Minion damage: %s", pct(fx.minion_dmg.mult or 1.25))
        end
        if fx.legion then
            lines[#lines + 1] = T("Legion: +%d cap, minions at %s damage",
                fx.legion.cap or 1, pct(fx.legion.dmg_mult or 0.8))
        end
    elseif kind == "pierce" then
        lines[#lines + 1] = T("Pierce hit: %s of hit (carries on-hit)", pct(fx.damage))
        if (fx.range_add or 0) > 0 then
            lines[#lines + 1] = T("Attack range: +%.1fm", fx.range_add)
        end
        if fx.skewer then
            lines[#lines + 1] = T("Skewer: +%s damage taken for %.0fs",
                pct(fx.skewer.amp or 0.08), fx.skewer.dur or 3.0)
        end
        if fx.cripple then
            lines[#lines + 1] = T("Cripple: -%s move for %.0fs",
                pct(fx.cripple.slow or 0.15), fx.cripple.dur or 2.0)
        end
    elseif kind == "shard_cone" then
        lines[#lines + 1] = T("%d shards, each %s of hit (no riders)",
            fx.shards or 4, pct(fx.damage))
        lines[#lines + 1] = T("Cone %.0f deg, range %.1fm, speed %.0f",
            fx.cone_deg or 18.0, fx.range or 5.0, fx.speed or 15.0)
    elseif kind == "preservation" then
        local seconds = (fx.heal_seconds or 5.0) + (fx.long_guard and fx.long_guard.dur or 0.0)
        lines[#lines + 1] = T("On damage taken: -%s damage for %.0fs", pct(fx.dr), seconds)
        lines[#lines + 1] = T("Regen %s max HP over %.0fs", pct(fx.heal), seconds)
    else
        lines[#lines + 1] = T(tostring(spec.desc or spec.id))
    end
    if fx.rider_heal then
        lines[#lines + 1] = T("Rider heal: %s of damage (cap %s max HP/s)",
            pct(fx.rider_heal.mult or 0.05), pct(fx.rider_heal.cap or 0.005))
    end
    if fx.status_dmg_down then
        lines[#lines + 1] = T("Afflicted deal -%s to you", pct(fx.status_dmg_down.pct or 0.08))
    end
    if fx.elite_mult then
        lines[#lines + 1] = T("Elites/bosses: +%s rider damage",
            pct((fx.elite_mult.mult or 1.2) - 1.0))
    end
    if fx.capstone and FX_DESC then
        local cap = fx.capstone
        local desc = FX_DESC[cap.kind]
        if desc then lines[#lines + 1] = T("Capstone: %s", desc(cap.params or {})) end
    end
    return lines
end

-- Per-node effect description (foundation adds + the named mechanics).
local ADD_LABEL = {
    initial = "hit damage", tick = "tick damage", stack_per = "per-stack tick",
    damage = "damage", slow = "slow", miss = "miss chance",
    reduction = "enemy dmg/AS/move cut", dr = "damage reduction",
    heal = "regen share", dmg_per_stack = "damage per stack",
    as_per_stack = "attack speed per stack", move_per_stack = "move per stack",
}

FX_DESC = {
    spread_plus = function(p) return T("Death spread: %.1fm, %d targets (copies don't re-spread).", p.radius or 5.5, p.targets or 2) end,
    elite_mult = function(p) return T("+%s rider damage vs elites and bosses.", pct((p.mult or 1.2) - 1.0)) end,
    fast_tick_max = function(p) return T("At max stacks the dot ticks every %.2fs.", p.tick or 0.35) end,
    double_stack_full = function() return T("Hits on healthy (95%+) targets add two stacks.") end,
    skewer = function(p) return T("Pierced enemies take +%s from you for %.0fs.", pct(p.amp or 0.08), p.dur or 3.0) end,
    longshot = function(p) return T("+%.1fm attack range.", p.range or 1.5) end,
    relentless = function(p) return T("Stacks last %.0fs and decay one per second.", p.dur or 5.0) end,
    sixth_gear = function(p) return T("+%d maximum stack.", p.stacks or 1) end,
    deep_slow = function(p) return T("+%s stronger slow.", pct(p.slow or 0.12)) end,
    brittle = function(p) return T("Slowed enemies take +%s from you.", pct(p.amp or 0.08)) end,
    blind = function(p) return T("+%s smoke miss chance.", pct(p.miss or 0.08)) end,
    assassin = function(p) return T("+%s rider damage vs healthy (95%%+) targets.", pct((p.mult or 1.2) - 1.0)) end,
    concussion = function(p) return T("Daze cuts another %s.", pct(p.reduction or 0.05)) end,
    lasting = function(p) return T("Status lasts +%.0fs.", p.dur or 2.0) end,
    blast_radius = function(p) return T("Blast radius +%.1fm.", p.add or 1.5) end,
    stun_wave = function(p) return T("The wave slows survivors %s for %.0fs.", pct(p.daze or 0.2), p.dur or 2.0) end,
    minion_dmg = function(p) return T("Minions deal +%s damage.", pct((p.mult or 1.25) - 1.0)) end,
    legion = function(p) return T("+%d minion cap; minions deal %s damage.", p.cap or 1, pct(p.dmg_mult or 0.8)) end,
    lifesteal_plus = function(p) return T("+%s of rider damage healed.", pct(p.add or 0.1)) end,
    overheal_shield = function(p) return T("Overhealing grants a shield up to %s max HP.", pct(p.cap or 0.10)) end,
    bulwark = function(p) return T("+%s damage reduction while guarding.", pct(p.dr or 0.05)) end,
    second_skin = function(p) return T("+%s max HP regenerated per guard.", pct(p.heal or 0.05)) end,
    wide_spray = function(p) return T("Cone +%.0f deg, +%d shard.", p.cone or 12.0, p.shards or 1) end,
    dense_cores = function(p) return T("Shards hit +%s harder.", pct(p.dmg or 0.10)) end,
    status_dmg_down = function(p) return T("Afflicted enemies deal -%s to you.", pct(p.pct or 0.08)) end,
    rider_heal = function(p) return T("Heal %s of this rider's damage (cap %s max HP/s).", pct(p.mult or 0.05), pct(p.cap or 0.005)) end,
    cripple = function(p) return T("Pierced enemies are slowed %s for %.0fs.", pct(p.slow or 0.15), p.dur or 2.0) end,
    punch_through = function(p) return T("Pierce +%s damage, +%.1fm range.", pct(p.dmg or 0.05), p.range or 0.5) end,
    dr_at_max = function(p) return T("At max stacks: +%s damage reduction.", pct(p.dr or 0.08)) end,
    kill_heal_max = function(p) return T("Kills at max stacks heal %s max HP (cap %s/s).", pct(p.heal or 0.01), pct(p.cap or 0.03)) end,
    kill_heal = function(p) return T("Kills heal %s max HP (cap %s/s).", pct(p.heal or 0.005), pct(p.cap or 0.02)) end,
    long_status = function(p) return T("Status lasts +%.0fs.", p.dur or 1.0) end,
    fleet = function(p) return T("+%s move speed while smoke is out.", pct(p.move or 0.05)) end,
    blast_dmg = function(p) return T("Blast damage +%s of hit.", pct(p.add or 0.10)) end,
    bone_armor = function(p) return T("+%s damage reduction per minion (cap %s).", pct(p.dr or 0.01), pct(p.cap or 0.06)) end,
    soul_harvest = function(p) return T("Kills heal %s max HP (cap %s/s).", pct(p.heal or 0.005), pct(p.cap or 0.02)) end,
    shard_slow = function(p) return T("Shards slow %s for %.0fs.", pct(p.slow or 0.15), p.dur or 2.0) end,
    long_guard = function(p) return T("Guard window +%.0fs.", p.dur or 1.0) end,
    proc_bonus = function(p) return T("Every %dth hit: +%s bonus damage%s (%.1fs cooldown).",
        p.every or 5, pct(p.pct or 1.0),
        (p.splash_targets or 0) > 0 and T(" + %s splash to %d nearby", pct(p.splash_pct or 0.3), p.splash_targets) or "",
        p.icd or 2.0) end,
    max_stack_burst = function(p) return T("Reaching max stacks bursts for +%s of hit%s (per target %.0fs).",
        pct(p.pct or 1.0), (p.heal or 0.0) > 0.0 and T(", healing %s of it", pct(p.heal)) or "", p.per_target_icd or 4.0) end,
    full_pierce = function(p) return T("Every %dth pierce hits at 100%% damage.", p.every or 5) end,
    chain_death = function(p) return T("Blast kills re-blast once at %s.", pct(p.mult or 0.5)) end,
    death_burst = function(p) return T("Afflicted deaths burst %s of the full dot (%.1fm).", pct(p.pct or 0.5), p.radius or 2.5) end,
    status_amp = function(p) return p.elites_only
        and T("Afflicted elites and bosses take +%s from you.", pct(p.amp or 0.2))
        or T("Afflicted enemies take +%s from you.", pct(p.amp or 0.15)) end,
    detonate = function(p) return (p.targets or 1) > 1
        and T("Every %.0fs all afflicted burst for %s of their remaining dot.", p.period or 8.0, pct(p.pct or 0.3))
        or T("Every %.0fs the strongest dot bursts for %s of its remainder.", p.period or 12.0, pct(p.pct or 1.0)) end,
    aura_buff = function(p) return T("With %d+ smoked enemies: +%s damage for %.0fs (%.0fs cooldown).",
        p.min_statused or 3, pct(p.dmg or 0.15), p.dur or 4.0, p.icd or 8.0) end,
    refresh_on_kill = function(p) return T("Bleeding kills smear a stack onto everything within %.0fm.", p.radius or 5.0) end,
    debuff_amp = function(p) return T("Daze cuts enemy damage another %s.", pct(p.extra or 0.10)) end,
    guardian = function(p) return T("Once per map: a lethal hit leaves you at %s HP, immune %.0fs.", pct(p.heal or 0.2), p.immune or 2.0) end,
    summon_burst = function(p) return T("Boss entry raises %d free skeletons.", p.count or 4) end,
    low_hp_boost = function(p) return T("Below %s HP: healing riders heal x%.0f.", pct(p.threshold or 0.4), p.mult or 2.0) end,
    shard_nova = function(p) return T("Every %dth hit: three extra shard sprays (full circle).", p.every or 6) end,
}

function Inv.node_lines(spec, node, rank, class_id)
    local Balance = _G.ATH_BALANCE
    local lines = {}
    local have = math.max(0, math.floor(rank or 0))
    if node.tier == "keystone" then
        -- Full numeric keystone rider (rank-1 coefficients), not the prose blurb.
        if Balance and Balance.compute_spec_fx then
            local fx = Balance.compute_spec_fx(class_id, spec, { key = 1 })
            for _, row in ipairs(Inv.spec_fx_lines(spec, fx)) do
                lines[#lines + 1] = row
            end
        else
            lines[#lines + 1] = T(tostring(spec.desc or spec.id))
        end
        return lines
    end
    if node.adds then
        local max_r = node.max_rank or 1
        for key, add in pairs(node.adds) do
            if key == "cap" then
                lines[#lines + 1] = T("+%d minion cap per rank (max +%d)", add, add * max_r)
                if have > 0 then
                    lines[#lines + 1] = T("  Now: +%d", add * have)
                end
            elseif key == "shards" then
                lines[#lines + 1] = T("+%d shard per rank (max +%d)", add, add * max_r)
                if have > 0 then
                    lines[#lines + 1] = T("  Now: +%d", add * have)
                end
            else
                lines[#lines + 1] = T("+%s %s per rank (max +%s)",
                    pct(add), T(ADD_LABEL[key] or key), pct(add * max_r))
                if have > 0 then
                    lines[#lines + 1] = T("  Now: +%s", pct(add * have))
                end
            end
        end
    end
    if node.fx_kind and FX_DESC[node.fx_kind] then
        lines[#lines + 1] = FX_DESC[node.fx_kind](node.fx or {})
    end
    if #lines == 0 then
        lines[#lines + 1] = T(tostring(spec.desc or node.name or node.id))
    end
    return lines
end

-- fit=true sizes the tip quad to its longest hard line (the backend never
-- wraps body text), so bound every line here — this is what keeps the box
-- width predictable for the screen-edge flip in draw_overlay.
local TIP_WRAP = 44
local function tip_wrap_line(s, out)
    if #s <= TIP_WRAP then
        out[#out + 1] = s
        return
    end
    local line = ""
    for word in s:gmatch("%S+") do
        if line == "" then
            line = word
        elseif #line + 1 + #word <= TIP_WRAP then
            line = line .. " " .. word
        else
            out[#out + 1] = line
            line = "  " .. word -- continuation indent
        end
    end
    if line ~= "" then out[#out + 1] = line end
end

function Inv.skill_tip(info)
    if not (info and info.spec and info.node) then return "" end
    local Balance = _G.ATH_BALANCE
    local spec, node = info.spec, info.node
    local class_id = info.class_id
    local lines = {
        T(tostring(node.name or node.id)),
        T("%s  -  %s", T(TIER_LABEL[node.tier] or node.tier), T(tostring(spec.name or spec.id))),
        T("Rank %d / %d", info.have or 0, node.max_rank or 1),
        info.status or "",
    }
    if (node.gate or 0) > 0 then
        lines[#lines + 1] = T("Unlocks at %d points in this tree.", node.gate)
    end
    if node.primary_only then
        lines[#lines + 1] = T("Primary tree only.")
    end
    if node.choice then
        lines[#lines + 1] = T("Choose one mutation (exclusive).")
    end
    if (info.have or 0) > 0 then
        lines[#lines + 1] = T("RIGHT-CLICK - refund 1")
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = T("This node:")
    for _, row in ipairs(Inv.node_lines(spec, node, info.have or 0, class_id)) do
        lines[#lines + 1] = row
    end
    -- Live tree totals so the player always sees the full numeric sheet.
    if Balance and Balance.compute_spec_fx and info.alloc then
        local fx = Balance.compute_spec_fx(class_id, spec, info.alloc)
        if (fx.points or 0) > 0 then
            lines[#lines + 1] = ""
            lines[#lines + 1] = T("Tree total (%d pts):", fx.points)
            for _, row in ipairs(Inv.spec_fx_lines(spec, fx)) do
                lines[#lines + 1] = row
            end
        elseif (info.have or 0) < 1 and node.tier == "keystone" then
            -- Preview already covered under "This node".
        end
    end
    local tip = table.concat(lines, "\n")
    tip = (Art and Art.ascii and Art.ascii(tip)) or tip
    -- Wrap after ascii-mapping so counted chars are the rendered ones.
    local wrapped = {}
    for line in (tip .. "\n"):gmatch("(.-)\n") do tip_wrap_line(line, wrapped) end
    return table.concat(wrapped, "\n")
end

function Inv.refresh_skills(D)
    local header = scene.find_model("Skills Header")
    local pts = math.max(0, math.floor(D.skill_points or 0))
    if valid(header) then
        local Balance = _G.ATH_BALANCE
        local hero = D.hero
        local body = T("SKILLS - %d pts", pts)
        if hero and hero.primary_spec and Balance then
            local rules = Balance.tree_rules or {}
            local primary = Balance.specialization(D.hero_class, hero.primary_spec)
            local ppts = D.tree_points and D:tree_points(hero.primary_spec) or 0
            body = body .. "   " .. T("PRIMARY %s %d/%d",
                T(tostring(primary and primary.name or hero.primary_spec)),
                ppts, rules.primary_cap or 9)
            for spec_id in pairs(D.class_tree_nodes and D:class_tree_nodes() or {}) do
                if spec_id ~= hero.primary_spec then
                    local spts = D:tree_points(spec_id)
                    if spts > 0 then
                        local spec = Balance.specialization(D.hero_class, spec_id)
                        body = body .. "   " .. T("SECOND %s %d/%d",
                            T(tostring(spec and spec.name or spec_id)),
                            spts, rules.secondary_cap or 5)
                    end
                end
            end
        end
        header:set_ui({ body = (Art and Art.ascii and Art.ascii(body)) or body })
    end
    local clear = { 0.0, 0.0, 0.0, 0.0 }
    -- Hide any leftover rank-ladder nodes from older scenes.
    for i = SKILL_COLS + 1, 15 do
        local n = scene.find_model("Skill Node " .. i)
        if valid(n) and n.set_enabled then n:set_enabled(false) end
    end
    -- Invisible column anchors (their rects place the tree; clicks fall
    -- through to the keystone row drawn on top).
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

-- Cell rects: one wide strip per spec, tiers left → right under Skills Header.
function Inv.tree_layout(D)
    local Balance = _G.ATH_BALANCE
    if not Balance then return {} end
    Art.surface_size()
    local vp = Art._vp
    local rh = vp.rh or 1080.0
    local function S(v) return v * Art.s("hud") end
    local specs = Inv.class_specs(D)
    local cells = {}
    local n = math.min(SKILL_COLS, #specs)
    if n < 1 then return cells end
    -- Content band: Skills Header width when present; else span Skill Node plates.
    local left, right, top
    for i = 1, n do
        local a = scene.find_model("Skill Node " .. i)
        local r = (valid(a) and a.get_ui_rect and a:get_ui_rect()) or nil
        if r and r.x and r.w and r.w > 1.0 then
            left = left and math.min(left, r.x) or r.x
            right = right and math.max(right, r.x + r.w) or (r.x + r.w)
            top = top and math.min(top, r.y) or r.y
        end
    end
    if not left then return cells end
    local hdr = scene.find_model("Skills Header")
    if valid(hdr) and hdr.get_ui_rect then
        local hr = hdr:get_ui_rect()
        if hr and hr.w and hr.w > 1.0 then
            left, right = hr.x, hr.x + hr.w
            top = math.max(top, hr.y + hr.h + S(10.0))
        end
    end
    -- Nudge left; keep half of the header band so cells stay compact.
    left = left - S(48.0)
    local bottom = rh - S(36.0)
    local row_gap = S(10.0)
    local n_steps = #TREE_STEPS
    local col_gap = S(8.0)
    local fill_row = (bottom - top - (n - 1) * row_gap) / n
    local fill_step = (right - left - (n_steps - 1) * col_gap) / n_steps
    local row_h = math.max(S(44.0), fill_row * 0.5)
    local step_w = math.max(S(72.0), fill_step * 0.5)
    local twin_gap = S(4.0)
    for i = 1, n do
        local spec = specs[i]
        local tree = Balance.spec_tree(D.hero_class, spec.id)
        if tree then
            local y0 = top + (i - 1) * (row_h + row_gap)
            for si, step in ipairs(TREE_STEPS) do
                local x0 = left + (si - 1) * (step_w + col_gap)
                local nt = #step
                local cell_h = (row_h - (nt - 1) * twin_gap) / nt
                for k, node_id in ipairs(step) do
                    local node = tree.by_id[node_id]
                    if node then
                        cells[#cells + 1] = {
                            qid = "sk_n_" .. i .. "_" .. node_id,
                            x = x0,
                            y = y0 + (k - 1) * (cell_h + twin_gap),
                            w = step_w,
                            h = cell_h,
                            col = i, spec = spec, node = node,
                        }
                    end
                end
            end
        end
    end
    return cells
end

-- Spend one point into a tree node.
function Inv.try_allocate_skill(D, spec_id, node_id)
    local ok, msg = D:allocate_skill(spec_id, node_id)
    if not ok then
        Inv.hub_hint(D, tostring(msg or "LOCKED"))
        return false
    end
    Inv.hub_hint(D, T("%s", T(tostring(msg))))
    Inv.refresh_skills(D)
    Inv.refresh(D)
    return true
end

-- Refund one rank from a tree node.
function Inv.try_deallocate_skill(D, spec_id, node_id)
    local ok, msg = D:deallocate_skill(spec_id, node_id)
    if not ok then
        Inv.hub_hint(D, tostring(msg or "NOTHING TO REMOVE"))
        return false
    end
    Inv.hub_hint(D, T("Refunded 1 point."))
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
        local cells = Inv.tree_layout(D)
        D._tree_cells = cells
        for _, cell in ipairs(cells) do
            local stt = runtime_ui.get_state(SCREEN, cell.qid)
            if stt then
                if stt.hovered then
                    local info = Inv.tree_cell_info(D, cell.spec, cell.node)
                    hover = {
                        cell = cell, info = info, mx = stt.mouse_x, my = stt.mouse_y,
                        tip = Inv.skill_tip(info),
                        border = (cell.spec.accent or { 0.62, 0.34, 0.86, 1.0 }),
                    }
                end
                if stt.clicked then
                    Inv.try_allocate_skill(D, cell.spec.id, cell.node.id)
                elseif stt.right_clicked then
                    Inv.try_deallocate_skill(D, cell.spec.id, cell.node.id)
                end
            end
        end
        -- Clicks between cells hit the authored plates, whose on_skill_i
        -- action buys the keystone (see hud/hub_skills.lua).
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

local TREE_NODE_IDS = { "key", "fa", "fb", "ma", "mb", "ta", "tb", "cap" }

local function Inv_clear_skill_overlays()
    for i = 1, 15 do
        runtime_ui.remove(SCREEN, "sk_fr_" .. i)
        runtime_ui.remove(SCREEN, "sk_ic_" .. i)
        runtime_ui.remove(SCREEN, "sk_lv_" .. i)
    end
    for i = 1, 3 do
        for _, nid in ipairs(TREE_NODE_IDS) do
            runtime_ui.remove(SCREEN, "sk_n_" .. i .. "_" .. nid)
            runtime_ui.remove(SCREEN, "sk_ni_" .. i .. "_" .. nid)
        end
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
        for i = 1, 15 do
            runtime_ui.remove(SCREEN, "sk_fr_" .. i)
            runtime_ui.remove(SCREEN, "sk_ic_" .. i)
            runtime_ui.remove(SCREEN, "sk_lv_" .. i)
        end
        local drawn = {}
        for _, cell in ipairs(D._tree_cells or Inv.tree_layout(D)) do
            local info = Inv.tree_cell_info(D, cell.spec, cell.node)
            local node = cell.node
            local accent = cell.spec.accent or { 0.62, 0.34, 0.86, 1.0 }
            local owned = (info.have or 0) > 0
            local reachable = info.can_buy or owned
            local fill = owned and { 0.07, 0.085, 0.12, 0.95 }
                or (info.can_buy and { 0.06, 0.07, 0.10, 0.92 } or { 0.035, 0.04, 0.05, 0.72 })
            local border = owned and accent
                or (info.can_buy and { 0.96, 0.82, 0.30, 0.95 } or { 0.30, 0.32, 0.38, 0.65 })
            if node.tier == "capstone" and owned then
                border = { 0.98, 0.86, 0.30, 1.0 }
            end
            local twin = node.tier == "mutation" or node.tier == "technique"
            local name = T(tostring(node.tier == "keystone" and cell.spec.name or node.name))
            -- Leave room for the larger keystone icon; twins stay full-width.
            local pad = node.tier == "keystone" and S(88.0) or S(12.0)
            local char_w = S(twin and 10.0 or 11.0)
            local budget = math.max(8, math.floor((cell.w - pad) / char_w))
            if #name > budget then name = name:sub(1, math.max(1, budget - 1)) .. "." end
            local label = string.format("%s%s %d/%d",
                node.tier == "capstone" and "* " or "", name,
                info.have or 0, node.max_rank)
            runtime_ui.set_quad(SCREEN, cell.qid, {
                x = cell.x, y = cell.y, width = cell.w, height = cell.h,
                style = "panel", fill = fill, border = border,
                label = (Art and Art.ascii and Art.ascii(label)) or label,
                font_scale = twin and 0.90 or 1.05,
                text_color = reachable and { 0.94, 0.95, 0.98, 1.0 } or { 0.52, 0.55, 0.62, 0.85 },
                bring_to_front = true, z = OVERLAY_Z - 1100.0,
            })
            drawn[cell.qid] = true
            -- Keystone icon: doubled vs previous S(56) cap.
            local ic_id = "sk_ni_" .. cell.col .. "_" .. node.id
            if node.tier == "keystone" and cell.spec.icon then
                local isz = math.min(cell.h * 0.92, S(112.0))
                runtime_ui.set_quad(SCREEN, ic_id, {
                    x = cell.x + cell.w - isz - S(4.0), y = cell.y + (cell.h - isz) * 0.5,
                    width = isz, height = isz, style = "image", image = cell.spec.icon,
                    fill = { 0.0, 0.0, 0.0, 0.0 }, border = { 0.0, 0.0, 0.0, 0.0 },
                    image_tint = owned and { 1.0, 1.0, 1.0, 1.0 } or { 0.4, 0.42, 0.48, 0.6 },
                    no_input = true, bring_to_front = true, z = OVERLAY_Z - 1000.0,
                })
                drawn[ic_id] = true
            end
        end
        for i = 1, 3 do
            for _, nid in ipairs(TREE_NODE_IDS) do
                if not drawn["sk_n_" .. i .. "_" .. nid] then
                    runtime_ui.remove(SCREEN, "sk_n_" .. i .. "_" .. nid)
                end
                if not drawn["sk_ni_" .. i .. "_" .. nid] then
                    runtime_ui.remove(SCREEN, "sk_ni_" .. i .. "_" .. nid)
                end
            end
        end
        local hv = D._skill_hover
        if hv and hv.tip and hv.tip ~= "" then
            local margin = S(10.0)
            local gap = S(8.0)
            local nlines = 0
            for _ in string.gmatch(hv.tip, "\n") do nlines = nlines + 1 end
            nlines = nlines + 1
            -- Fixed box (no fit=true): placement math matches the drawn rect.
            -- Line height tracks font_scale 1.25 — do NOT use S(); that bloated
            -- th and the bottom-edge clamp shoved tips up away from the cell.
            local tip_w = math.min(TIP_WRAP * 9.5 + 28.0, rw - 2.0 * margin)
            local line_h = 20.0
            local th = math.min(nlines * line_h + 20.0, rh - 2.0 * margin)
            local cell = hv.cell
            local tx, ty = margin, margin
            if cell and cell.x then
                local right_x = cell.x + cell.w + gap
                local space_r = rw - margin - right_x
                local space_l = cell.x - gap - margin
                if space_r >= tip_w then
                    tx = right_x
                elseif space_l >= tip_w then
                    tx = cell.x - gap - tip_w
                elseif space_r >= space_l and space_r >= 100.0 then
                    tip_w = space_r
                    tx = right_x
                elseif space_l >= 100.0 then
                    tip_w = space_l
                    tx = cell.x - gap - tip_w
                else
                    tip_w = math.max(100.0, math.max(space_r, space_l))
                    tx = (space_r >= space_l) and right_x or (cell.x - gap - tip_w)
                end
                -- Vertical: top-align with the skill; if that would clip the
                -- bottom edge, hang upward from the cell bottom instead.
                ty = cell.y
                if ty + th > rh - margin then
                    ty = cell.y + cell.h - th
                end
            else
                tx = (hv.mx or 0.0) + 18.0
                ty = (hv.my or 0.0) + 12.0
                if tx + tip_w > rw - margin then
                    tx = math.max(margin, (hv.mx or 0.0) - tip_w - 18.0)
                end
            end
            tx = math.max(margin, math.min(tx, rw - tip_w - margin))
            ty = math.max(margin, math.min(ty, rh - th - margin))
            runtime_ui.set_quad(SCREEN, "sk_tip", {
                x = tx, y = ty, width = tip_w, height = th, style = "text",
                fill = { 0.04, 0.05, 0.08, 0.98 }, border = hv.border or { 0.62, 0.34, 0.86, 1.0 },
                body = hv.tip, text_color = { 0.92, 0.94, 0.98, 1.0 },
                font_scale = 1.25, align_h = "left", align_v = "top",
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
        -- Size estimate must stay inside the viewport; oversized S(th) used to
        -- push ty negative after the bottom clamp and clip the tip title.
        local margin = S(10.0)
        local nlines = 1
        for _ in string.gmatch(tip, "\n") do nlines = nlines + 1 end
        local tw = math.min(S(420.0), rw - 2.0 * margin)
        local th = math.min(nlines * S(22.0) + S(28.0), rh - 2.0 * margin)
        local tx = (hv.mx or 0.0) + S(18.0)
        local ty = (hv.my or 0.0) + S(12.0)
        tx = math.max(margin, math.min(tx, rw - tw - margin))
        ty = math.max(margin, math.min(ty, rh - th - margin))
        runtime_ui.set_quad(SCREEN, "inv_tip", {
            x = tx, y = ty, width = tw, style = "text", fit = true,
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
        Inv_clear_skill_overlays()
    end
    D._inv_drag = nil
    D._inv_hover = nil
    D._skill_hover = nil
end

_G.ATH_INVENTORY = Inv
return Inv
