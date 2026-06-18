-- wb_units — unit archetypes + factory.
--
-- A unit is a plain Lua table (position/stats/order live here) plus a primitive
-- "rig" of scene nodes parented to a root group. Gameplay drives only the root's
-- position + Y-facing each frame (both safe to write per-frame); the rig's parts
-- and scale are baked once at build time (per-frame scale writes are unreliable).
--
-- Death never deletes nodes (that staling other nodes' draw constants on this
-- engine). Instead the rig is parked far below the map and pushed to a per-archetype
-- pool for reuse on the next spawn of that archetype.

local U = WB.util
local C = U.COLOR

local Units = {}

local PARK_Y = -1000.0
local next_id = 0

-- ---- archetype definitions ----------------------------------------------------
-- stats: hp, dps (damage/second), range, interval (seconds/attack), speed,
-- armor (0..0.85 damage reduction), radius (body footprint), scale (rig size),
-- xp (bounty granted to a hero on kill). rig: list of part specs in local space.

local function torso(color, trim)
    return {
        { kind = "cube", name = "Legs", pos = { 0.0, 0.28, 0.0 }, scale = { 0.5, 0.55, 0.4 }, color = trim, emissive = 0.10 },
        { kind = "cube", name = "Body", pos = { 0.0, 0.78, 0.0 }, scale = { 0.62, 0.62, 0.46 }, color = color, emissive = 0.12 },
        { kind = "sphere", name = "Head", pos = { 0.0, 1.22, 0.0 }, scale = { 0.42, 0.44, 0.42 }, color = color, emissive = 0.12 },
    }
end

Units.ARCH = {
    hero = {
        faction = "player", display = "Commander", hp = 460, dps = 30, range = 1.7, interval = 0.7,
        speed = 6.8, armor = 0.28, radius = 0.8, scale = 1.35, mana = 120, is_hero = true,
        weapon = "Blade", bounty = 0,
        rig = {
            { kind = "cube", name = "Legs", pos = { 0.0, 0.30, 0.0 }, scale = { 0.55, 0.6, 0.44 }, color = C.hero_trim, emissive = 0.12 },
            { kind = "cube", name = "Body", pos = { 0.0, 0.85, 0.0 }, scale = { 0.72, 0.7, 0.5 }, color = C.hero, emissive = 0.16 },
            { kind = "cube", name = "Pauldrons", pos = { 0.0, 1.12, 0.0 }, scale = { 0.96, 0.22, 0.6 }, color = C.hero_trim, emissive = 0.18 },
            { kind = "sphere", name = "Head", pos = { 0.0, 1.42, 0.0 }, scale = { 0.46, 0.5, 0.46 }, color = C.hero, emissive = 0.16 },
            { kind = "cone", name = "Crest", pos = { 0.0, 1.78, 0.0 }, scale = { 0.3, 0.5, 0.3 }, color = C.hero_trim, emissive = 0.3 },
            -- a big sword on the right
            { kind = "cube", name = "Hilt", pos = { 0.62, 0.8, 0.1 }, scale = { 0.12, 0.3, 0.12 }, color = C.tree_trunk, emissive = 0.1 },
            { kind = "cube", name = "Blade", pos = { 0.62, 1.4, 0.1 }, scale = { 0.14, 1.0, 0.06 }, color = C.rock, emissive = 0.2 },
        },
    },
    soldier = {
        faction = "player", display = "Soldier", hp = 160, dps = 13, range = 1.5, interval = 0.9,
        speed = 6.0, armor = 0.16, radius = 0.55, scale = 1.0, weapon = "Spear", bounty = 0,
        rig = (function()
            local r = torso(C.player, C.player_trim)
            r[#r + 1] = { kind = "cylinder", name = "Spear", pos = { 0.5, 1.0, 0.1 }, scale = { 0.07, 1.7, 0.07 }, color = C.tree_trunk, emissive = 0.1 }
            r[#r + 1] = { kind = "cone", name = "SpearTip", pos = { 0.5, 1.92, 0.1 }, scale = { 0.13, 0.3, 0.13 }, color = C.rock, emissive = 0.2 }
            r[#r + 1] = { kind = "cube", name = "Shield", pos = { -0.42, 0.8, 0.12 }, scale = { 0.12, 0.5, 0.4 }, color = C.player_trim, emissive = 0.16 }
            return r
        end)(),
    },
    grunt = {
        faction = "enemy", display = "Raider", hp = 120, dps = 11, range = 1.5, interval = 1.0,
        speed = 5.0, armor = 0.12, radius = 0.58, scale = 1.08, xp = 40, weapon = "Club", bounty = 20,
        rig = (function()
            local r = {
                { kind = "cube", name = "Legs", pos = { 0.0, 0.3, 0.0 }, scale = { 0.6, 0.6, 0.46 }, color = C.enemy_trim, emissive = 0.1 },
                { kind = "cube", name = "Body", pos = { 0.0, 0.82, 0.0 }, scale = { 0.78, 0.68, 0.54 }, color = C.enemy, emissive = 0.14 },
                { kind = "sphere", name = "Head", pos = { 0.0, 1.26, 0.0 }, scale = { 0.46, 0.46, 0.46 }, color = C.enemy, emissive = 0.14 },
            }
            r[#r + 1] = { kind = "cylinder", name = "Club", pos = { 0.55, 0.9, 0.1 }, scale = { 0.1, 1.1, 0.1 }, color = C.tree_trunk, emissive = 0.1 }
            r[#r + 1] = { kind = "sphere", name = "ClubHead", pos = { 0.55, 1.5, 0.1 }, scale = { 0.28, 0.28, 0.28 }, color = C.rock, emissive = 0.12 }
            return r
        end)(),
    },
    -- Laborer: a fragile non-combatant that harvests gold/lumber (see wb_economy).
    worker = {
        faction = "player", display = "Laborer", hp = 90, dps = 5, range = 1.2, interval = 1.2,
        speed = 5.6, armor = 0.05, radius = 0.45, scale = 0.85, weapon = "Pick", bounty = 0,
        no_combat = true,
        rig = (function()
            local r = {
                { kind = "cube", name = "Legs", pos = { 0.0, 0.26, 0.0 }, scale = { 0.46, 0.5, 0.38 }, color = C.worker_trim, emissive = 0.10 },
                { kind = "cube", name = "Body", pos = { 0.0, 0.7, 0.0 }, scale = { 0.56, 0.56, 0.42 }, color = C.worker, emissive = 0.12 },
                { kind = "sphere", name = "Head", pos = { 0.0, 1.08, 0.0 }, scale = { 0.38, 0.4, 0.38 }, color = C.worker, emissive = 0.12 },
            }
            r[#r + 1] = { kind = "cylinder", name = "Pick", pos = { 0.42, 0.9, 0.12 }, scale = { 0.06, 1.0, 0.06 }, color = C.tree_trunk, emissive = 0.1 }
            r[#r + 1] = { kind = "cube", name = "PickHead", pos = { 0.42, 1.42, 0.12 }, scale = { 0.36, 0.1, 0.1 }, color = C.rock, emissive = 0.16 }
            return r
        end)(),
    },
    -- Town Hall: resource drop-off + trains Laborers; supplies food.
    town_hall = {
        faction = "player", display = "Town Hall", hp = 1500, dps = 0, range = 0.0, interval = 1.0,
        speed = 0.0, armor = 0.5, radius = 3.4, scale = 1.0, bounty = 0,
        is_building = true, no_combat = true, food_cap = 12, trains = "worker",
        rig = {
            { kind = "cube", name = "Base", pos = { 0.0, 1.2, 0.0 }, scale = { 5.4, 2.4, 5.0 }, color = C.stone, emissive = 0.07 },
            { kind = "cube", name = "Upper", pos = { 0.0, 3.0, 0.0 }, scale = { 4.2, 1.4, 3.8 }, color = C.stone_dark, emissive = 0.07 },
            { kind = "cube", name = "Door", pos = { 0.0, 0.9, 2.55 }, scale = { 1.4, 1.8, 0.4 }, color = C.tree_trunk, emissive = 0.05 },
            { kind = "cone", name = "Roof", pos = { 0.0, 4.7, 0.0 }, scale = { 4.6, 2.2, 4.2 }, color = C.roof, emissive = 0.12 },
            { kind = "cylinder", name = "TowerL", pos = { -2.6, 2.0, -2.2 }, scale = { 1.0, 4.0, 1.0 }, color = C.stone, emissive = 0.07 },
            { kind = "cone", name = "TowerLTop", pos = { -2.6, 4.5, -2.2 }, scale = { 1.3, 1.5, 1.3 }, color = C.roof, emissive = 0.14 },
            { kind = "cylinder", name = "TowerR", pos = { 2.6, 2.0, -2.2 }, scale = { 1.0, 4.0, 1.0 }, color = C.stone, emissive = 0.07 },
            { kind = "cone", name = "TowerRTop", pos = { 2.6, 4.5, -2.2 }, scale = { 1.3, 1.5, 1.3 }, color = C.roof, emissive = 0.14 },
            { kind = "cube", name = "Banner", pos = { 0.0, 3.3, 2.0 }, scale = { 1.0, 1.4, 0.12 }, color = C.player, emissive = 0.22 },
        },
    },
    -- Barracks: trains Soldiers.
    barracks = {
        faction = "player", display = "Barracks", hp = 1100, dps = 0, range = 0.0, interval = 1.0,
        speed = 0.0, armor = 0.4, radius = 3.0, scale = 1.0, bounty = 0,
        is_building = true, no_combat = true, food_cap = 8, trains = "soldier",
        rig = {
            { kind = "cube", name = "Hall", pos = { 0.0, 1.1, 0.0 }, scale = { 6.0, 2.2, 4.0 }, color = C.stone, emissive = 0.07 },
            { kind = "cube", name = "Roof", pos = { 0.0, 2.6, 0.0 }, scale = { 6.3, 0.8, 4.3 }, color = C.roof, emissive = 0.12 },
            { kind = "cube", name = "Door", pos = { 0.0, 0.85, 2.05 }, scale = { 1.4, 1.6, 0.4 }, color = C.tree_trunk, emissive = 0.05 },
            { kind = "cube", name = "PostL", pos = { -2.4, 1.0, 2.6 }, scale = { 0.3, 2.0, 0.3 }, color = C.tree_trunk, emissive = 0.05 },
            { kind = "cube", name = "PostR", pos = { 2.4, 1.0, 2.6 }, scale = { 0.3, 2.0, 0.3 }, color = C.tree_trunk, emissive = 0.05 },
            { kind = "cube", name = "Banner", pos = { 0.0, 1.7, 2.05 }, scale = { 0.9, 1.2, 0.12 }, color = C.player_trim, emissive = 0.22 },
            { kind = "cube", name = "Rack", pos = { 2.0, 0.6, -1.6 }, scale = { 1.8, 1.0, 0.3 }, color = C.rock, emissive = 0.1 },
        },
    },
    wolf = {
        faction = "enemy", display = "Direwolf", hp = 80, dps = 9, range = 1.4, interval = 0.8,
        speed = 8.2, armor = 0.04, radius = 0.5, scale = 1.0, xp = 30, weapon = nil, bounty = 12,
        rig = {
            { kind = "cube", name = "Body", pos = { 0.0, 0.45, 0.0 }, scale = { 0.5, 0.42, 1.05 }, color = C.enemy_trim, emissive = 0.12 },
            { kind = "sphere", name = "Head", pos = { 0.0, 0.55, 0.62 }, scale = { 0.42, 0.4, 0.42 }, color = C.enemy_trim, emissive = 0.14 },
            { kind = "cone", name = "EarL", pos = { -0.12, 0.82, 0.62 }, scale = { 0.12, 0.2, 0.12 }, color = C.enemy, emissive = 0.16 },
            { kind = "cone", name = "EarR", pos = { 0.12, 0.82, 0.62 }, scale = { 0.12, 0.2, 0.12 }, color = C.enemy, emissive = 0.16 },
            { kind = "cube", name = "Snout", pos = { 0.0, 0.46, 0.92 }, scale = { 0.2, 0.18, 0.28 }, color = C.enemy, emissive = 0.18 },
            { kind = "cube", name = "LegFL", pos = { -0.18, 0.18, 0.4 }, scale = { 0.12, 0.36, 0.12 }, color = C.enemy_trim, emissive = 0.1 },
            { kind = "cube", name = "LegFR", pos = { 0.18, 0.18, 0.4 }, scale = { 0.12, 0.36, 0.12 }, color = C.enemy_trim, emissive = 0.1 },
            { kind = "cube", name = "LegBL", pos = { -0.18, 0.18, -0.4 }, scale = { 0.12, 0.36, 0.12 }, color = C.enemy_trim, emissive = 0.1 },
            { kind = "cube", name = "LegBR", pos = { 0.18, 0.18, -0.4 }, scale = { 0.12, 0.36, 0.12 }, color = C.enemy_trim, emissive = 0.1 },
            { kind = "cube", name = "Tail", pos = { 0.0, 0.55, -0.7 }, scale = { 0.12, 0.12, 0.4 }, color = C.enemy_trim, emissive = 0.1 },
        },
    },
}

-- ---- rig construction + pooling ----------------------------------------------

local pools = {} -- archetype -> { parked rigs }

local function build_rig(arch_name, node_name, parent)
    local arch = Units.ARCH[arch_name]
    local root = U.group(node_name, parent)
    if not U.valid(root) then return nil end
    local parts = {}
    for _, spec in ipairs(arch.rig) do
        local s = {}
        for k, v in pairs(spec) do s[k] = v end
        s.parent = root
        local node = U.part(s)
        if node then parts[spec.name] = node end
    end
    -- Selection disc: a thin bright ring laid on the ground (cylinders stand along
    -- Y, so a flat one reads as a ground circle from the angled camera). Built once,
    -- shown only while selected. Scale baked here.
    local ring = primitives.cylinder(arch.radius * 1.7, 0.06)
    if U.valid(ring) then
        ring:set_name("SelectRing")
        ring:set_parent(root)
        ring:set_position(vec3(0.0, 0.05, 0.0))
        ring:set_scale(vec3(arch.radius * 1.7, 0.06, arch.radius * 1.7))
        U.tint(ring, arch.faction == "player" and C.select or C.select_foe, 0.6)
        ring:set_enabled(false)
    end
    -- bake root scale once
    root:set_scale(vec3(arch.scale, arch.scale, arch.scale))
    return root, parts, ring
end

-- Wrap a rig (root + parts + ring) in a live unit table and place it at (x,z).
local function make_unit_table(arch_name, root, parts, ring, x, z)
    local arch = Units.ARCH[arch_name]
    next_id = next_id + 1
    local unit = {
        id = next_id, arch = arch_name, faction = arch.faction, display = arch.display,
        x = x, z = z, facing = (arch.faction == "player") and math.pi or 0.0,
        hp = arch.hp, hp_max = arch.hp, dps = arch.dps, armor = arch.armor,
        range = arch.range, interval = arch.interval, attack_t = 0.0,
        speed = arch.speed, radius = arch.radius,
        order = "idle", goal_x = x, goal_z = z, target = nil, attack_move = false,
        alive = true, selected = false, hit_flash = 0.0, attack_swing = 0.0,
        root = root, parts = parts, ring = ring,
        is_hero = arch.is_hero or false,
        is_building = arch.is_building or false,
        no_combat = arch.no_combat or false,
        food_cap = arch.food_cap or 0,
        xp_value = arch.xp or 0,
    }
    if arch.is_hero then
        unit.level = 1; unit.xp = 0; unit.xp_to_level = 100
        unit.mana = arch.mana; unit.mana_max = arch.mana
    end
    Units.set_selected(unit, false)
    Units.place(unit, x, z)
    Units.face(unit, math.sin(unit.facing), math.cos(unit.facing))
    return unit
end

-- BUILD a unit's rig from scratch as scene node `node_name` (used to bake the
-- authored scene; see WB_BAKE in wb_game).
function Units.build(arch_name, node_name, x, z)
    if not Units.ARCH[arch_name] then return nil end
    local root, parts, ring = build_rig(arch_name, node_name, WB.game and WB.game.actors_group())
    if not U.valid(root) then return nil end
    return make_unit_table(arch_name, root, parts, ring, x, z)
end

-- ADOPT an already-authored unit node (by name) from the loaded scene and drive it.
-- Parts/ring are recovered from the node's children. This is the normal runtime path
-- — scripts only move/animate/kill these; they don't create geometry.
function Units.adopt(node_name, arch_name, x, z)
    if not Units.ARCH[arch_name] then return nil end
    local root = scene.find_model and scene.find_model(node_name) or nil
    if not U.valid(root) then return nil end
    root:set_enabled(true) -- revive a previously parked/disabled rig (e.g. on restart)
    local parts, ring = {}, nil
    for _, c in ipairs(root:get_children() or {}) do
        if U.valid(c) then
            local n = c:get_name()
            if n == "SelectRing" then ring = c else parts[n] = c end
        end
    end
    -- Show the rig's meshes via cheap render-visibility (a prior play may have hidden them),
    -- and enable the selection ring ONCE (it is authored set_enabled(false)) so selecting a
    -- unit later is a cheap set_visible toggle rather than a raster-instance rebuild.
    for _, c in pairs(parts) do if U.valid(c) then c:set_visible(true) end end
    if U.valid(ring) then ring:set_enabled(true); ring:set_visible(false) end
    return make_unit_table(arch_name, root, parts, ring, x, z)
end

-- Position the unit's rig on the ground at (x,z).
function Units.place(unit, x, z)
    unit.x, unit.z = x, z
    if U.valid(unit.root) then unit.root:set_position(vec3(x, 0.0, z)) end
end

-- Face the unit along ground direction (dx,dz) (rotates the root about Y).
function Units.face(unit, dx, dz)
    if dx == 0.0 and dz == 0.0 then return end
    unit.facing = math.atan(dx, dz)
    if U.valid(unit.root) then
        unit.root:set_rotation(vec3(0.0, math.deg(unit.facing), 0.0))
    end
end

-- Cheaply show/hide a unit's whole rig via per-node render visibility (the CullingCS cull
-- flag) instead of set_enabled. set_enabled forces a SYNCHRONOUS raster-instance rebuild
-- (a GPU submit+wait) on EVERY call -- that is what spikes the frame on mass deaths and on
-- selection changes. set_visible just flips a per-node flag re-uploaded on the existing
-- per-frame uniform path (no rebuild, no stall). It is per-NODE (not hierarchical) and the
-- rig root is an empty group, so we flip every mesh part explicitly.
local function set_rig_visible(unit, vis)
    if not unit.parts then return end
    for _, n in pairs(unit.parts) do
        if U.valid(n) then n:set_visible(vis) end
    end
end

function Units.set_selected(unit, on)
    unit.selected = on
    if U.valid(unit.ring) then unit.ring:set_visible(on == true) end
end

-- Per-frame cosmetics: a little walk bob, a weapon swing on attack, and a hit
-- flash. All are position/rotation/material writes (safe every frame). Call after
-- locomotion has placed the unit for the frame.
function Units.tick_visual(unit, dt, t)
    if not unit.alive or not U.valid(unit.root) then return end
    -- walk bob (raise the whole rig slightly while moving)
    local y = 0.0
    if unit.moving then y = math.abs(math.sin(t * 9.0 + unit.id * 1.3)) * 0.09 end
    unit.root:set_position(vec3(unit.x, y, unit.z))

    -- weapon swing
    local arch = Units.ARCH[unit.arch]
    if arch and arch.weapon and unit.parts and U.valid(unit.parts[arch.weapon]) then
        local w = unit.parts[arch.weapon]
        if (unit.attack_swing or 0.0) > 0.0 then
            unit.attack_swing = unit.attack_swing - dt
            local phase = 1.0 - U.clamp((unit.attack_swing or 0.0) / 0.25, 0.0, 1.0)
            local swing = math.sin(phase * math.pi) * -75.0 -- chop forward then back
            w:set_rotation(vec3(swing, 0.0, 0.0))
        else
            w:set_rotation(vec3(0.0, 0.0, 0.0))
        end
    end

    -- hit flash (briefly brighten the body's emissive)
    if (unit.hit_flash or 0.0) > 0.0 then
        unit.hit_flash = unit.hit_flash - dt
        local body = unit.parts and (unit.parts.Body or unit.parts.Head)
        if U.valid(body) and material and material.set then
            local k = U.clamp((unit.hit_flash or 0.0) / 0.14, 0.0, 1.0)
            material.set(body, "emissive", vec3(0.9 * k + 0.12, 0.18 * k + 0.12, 0.16 * k + 0.12))
        end
    elseif unit._flashed then
        unit._flashed = false
        local body = unit.parts and (unit.parts.Body or unit.parts.Head)
        local arch2 = Units.ARCH[unit.arch]
        if U.valid(body) and arch2 then
            local col = (unit.faction == "player") and (unit.is_hero and C.hero or C.player) or C.enemy
            material.set(body, "emissive", U.cv3(col, 0.14))
        end
    end
    if (unit.hit_flash or 0.0) > 0.0 then unit._flashed = true end
end

-- Deactivate a unit without pooling it: hide its ring, disable + park its rig, and
-- mark it not-alive. Used for training reserves — units authored in the scene that
-- wait offstage until a building trains them (see wb_economy). Distinct from kill():
-- no death FX, no pool push; the same table is later revived by Units.activate.
function Units.deactivate(unit)
    unit.alive = false
    unit.target = nil
    unit.order = "idle"
    unit.job = nil
    Units.set_selected(unit, false)
    set_rig_visible(unit, false)
    if U.valid(unit.root) then
        unit.root:set_position(vec3(unit.x, PARK_Y, unit.z))
    end
end

-- Revive a deactivated reserve unit at (x,z) with fresh stats. Re-enables the rig,
-- resets combat/harvest state, and places + faces it (toward the battle for players).
function Units.activate(unit, x, z)
    local arch = Units.ARCH[unit.arch]
    if not arch then return unit end
    unit.alive = true
    unit.hp = arch.hp; unit.hp_max = arch.hp
    unit.order = "idle"; unit.target = nil; unit.attack_move = false
    unit.attack_t = 0.0; unit.attack_swing = 0.0; unit.hit_flash = 0.0; unit.slow_t = 0.0
    unit.job = nil; unit.hstate = nil; unit.carry = 0; unit.carry_kind = nil
    unit.selected = false
    set_rig_visible(unit, true)
    Units.place(unit, x, z)
    Units.face(unit, 0.0, (arch.faction == "player") and -1.0 or 1.0)
    return unit
end

-- Kill a unit: hide selection, park the rig offstage, and pool it for reuse.
function Units.kill(unit)
    if not unit.alive then return end
    unit.alive = false
    unit.target = nil
    Units.set_selected(unit, false)
    set_rig_visible(unit, false)
    if U.valid(unit.root) then
        unit.root:set_position(vec3(unit.x, PARK_Y, unit.z))
    end
    pools[unit.arch] = pools[unit.arch] or {}
    table.insert(pools[unit.arch], { root = unit.root, parts = unit.parts, ring = unit.ring })
end

return Units
