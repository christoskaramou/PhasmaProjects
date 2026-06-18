-- wb_build — building placement + worker construction state machine.
--
-- Shared by the player (mouse/HUD placement) and the AI (direct Build.place calls).
-- Player placement uses Build.begin -> ghost follows cursor -> Build.confirm.
-- AI placement uses Build.place directly.
-- Worker construction progresses when the assigned builder is adjacent to the site.

local U = WB.util
local World = WB.world
local Camera = WB.camera
local Units = WB.units

local Build = {}

-- Build definitions: player arch keys -> costs + times.
-- The AI maps to enemy variants via faction_arch().
Build.DEFS = {
    barracks  = { arch = "barracks",  gold = 160, lumber = 40, build_time = 14.0, label = "Barracks",  letter = "B" },
    farm      = { arch = "farm",      gold = 60,  lumber = 20, build_time = 8.0,  label = "Farm",      letter = "F" },
    tower     = { arch = "tower",     gold = 120, lumber = 30, build_time = 12.0, label = "Tower",     letter = "T" },
    town_hall = { arch = "town_hall", gold = 300, lumber = 80, build_time = 24.0, label = "Town Hall", letter = "H" },
}

-- Player arch -> enemy arch, so the AI builds Wilds variants from the same DEFS.
local function faction_arch(E, base_arch)
    if E.faction == "enemy" then return "enemy_" .. base_arch end
    return base_arch
end

-- ---- placement validity -------------------------------------------------------

-- Is (x,z) a legal building spot for E? In bounds, clear of every live building, off nodes.
function Build.spot_valid(state, x, z, radius)
    local bx, bz = World.clamp(x, z, radius + 1.0)
    if math.abs(bx - x) > 0.01 or math.abs(bz - z) > 0.01 then return false end -- clamped => out of bounds
    for _, fac in ipairs({ "player", "enemy" }) do
        for _, b in ipairs(state.econ[fac].buildings) do
            if b.alive and U.dist2(x, z, b.x, b.z) < (radius + b.radius + 1.5) then return false end
        end
    end
    local nodes = { World.mine, World.forest, World.wilds_mine, World.wilds_forest }
    for _, n in ipairs(nodes) do
        if n and U.dist2(x, z, n.x, n.z) < radius + 6.0 then return false end
    end
    return true
end

local function borrow_reserve(E, arch)
    local pool = E.building_reserves[arch]
    return pool and table.remove(pool) or nil
end

local function return_reserve(E, arch, b)
    E.building_reserves[arch] = E.building_reserves[arch] or {}
    table.insert(E.building_reserves[arch], b)
    Units.deactivate(b)
end

-- ---- site tinting -------------------------------------------------------------

-- Desaturate/restore a site's mesh emissive as a build-progress indicator.
function Build.tint_site(b, building)
    if not b.parts then return end
    for _, n in pairs(b.parts) do
        if U.valid(n) and material and material.set then
            material.set(n, "emissive", building and vec3(0.02, 0.03, 0.05) or vec3(0.07, 0.07, 0.08))
        end
    end
end

function Build.tint_ghost(b, ok)
    if not b.parts then return end
    for _, n in pairs(b.parts) do
        if U.valid(n) and material and material.set then
            material.set(n, "emissive", ok and vec3(0.0, 0.3, 0.05) or vec3(0.4, 0.0, 0.0))
        end
    end
end

-- ---- direct placement (AI + player confirm) -----------------------------------

-- Commit a construction site for E at (x,z) of build type_key, assigning workers[1] to build.
-- Returns the site building table, or nil if unaffordable / no reserve / bad spot.
function Build.place(state, E, type_key, x, z, workers)
    local def = Build.DEFS[type_key]; if not def then return nil end
    if (E.gold or 0) < def.gold or (E.lumber or 0) < def.lumber then return nil end
    local arch_name = faction_arch(E, def.arch)
    local arch = Units.ARCH[arch_name]
    if not arch then return nil end
    if not Build.spot_valid(state, x, z, arch.radius) then return nil end
    local b = borrow_reserve(E, arch_name); if not b then return nil end
    E.gold = E.gold - def.gold; E.lumber = E.lumber - def.lumber
    Units.activate(b, x, z)                  -- show the rig at the spot
    b.arch = arch_name                       -- defensive: completion log + Stage 4/7 read b.arch
    b.state = "site"; b.build_t = def.build_time; b.build_total = def.build_time
    b.hp = math.max(1, b.hp_max * 0.1); b.queue = {}
    b.trains = arch.trains; b.rally_x, b.rally_z = x, (z - 6.0)
    b.faction = E.faction
    Build.tint_site(b, true)                 -- desaturate while building
    E.buildings[#E.buildings + 1] = b
    if workers and workers[1] then
        local w = workers[1]
        w.order = "build"; w.build_target = b; w.job = nil; w.target = nil
    end
    if pe_log then pe_log(string.format("[build] %s site placed by %s at %.0f,%.0f", def.label, E.faction, x, z)) end
    return b
end

-- (Re)assign every worker in `sel` to build `site` (resume a stopped build, or send
-- helpers to speed one up). Pulls workers off harvest. Returns the count assigned.
function Build.assign_builders(sel, site)
    if not (site and site.alive and site.state == "site") then return 0 end
    local n = 0
    for _, u in ipairs(sel) do
        if u.alive and u.arch_is_worker then
            u.order = "build"; u.build_target = site; u.job = nil; u.target = nil
            n = n + 1
        end
    end
    return n
end

-- ---- construction tick -------------------------------------------------------

function Build.update(dt, state)
    Build.update_placement(dt, state)  -- player ghost-follow; no-op when not placing
    for _, fac in ipairs({ "player", "enemy" }) do
        for _, b in ipairs(state.econ[fac].buildings) do
            if b.alive and b.state == "site" then
                -- Count every worker assigned to this site and adjacent to it. More builders
                -- build faster (capped), so extra workers meaningfully help finish.
                local builders = {}
                for _, u in ipairs(state.econ[fac].units) do
                    if u.alive and u.order == "build" and u.build_target == b
                       and U.dist2(u.x, u.z, b.x, b.z) <= b.radius + 2.2 then
                        builders[#builders + 1] = u
                    end
                end
                if #builders > 0 then
                    local rate = math.min(#builders, 3) -- diminishing help past 3 workers
                    for _, w in ipairs(builders) do
                        if (w.attack_swing or 0.0) <= 0.0 then w.attack_swing = 0.25 end
                    end
                    b.build_t = b.build_t - dt * rate
                    b.hp = math.min(b.hp_max, b.hp_max * (0.1 + 0.9 * (1.0 - b.build_t / b.build_total)))
                    if b.build_t <= 0.0 then
                        b.state = "done"; b.hp = b.hp_max
                        Build.tint_site(b, false)
                        for _, w in ipairs(builders) do w.order = "idle"; w.build_target = nil end
                        if pe_log then pe_log(string.format("[build] %s complete (%s, %d builders)", Units.ARCH[b.arch].display, fac, #builders)) end
                    end
                end
            end
        end
    end
end

-- ---- player placement mode (ghost follows cursor) ----------------------------

local placing = nil -- { E, type_key, ghost, arch_name, workers, valid, gx, gz }

function Build.is_placing() return placing ~= nil end

function Build.begin(state, E, type_key, workers)
    if placing then Build.cancel() end
    local def = Build.DEFS[type_key]; if not def then return end
    local arch_name = faction_arch(E, def.arch)
    local ghost = borrow_reserve(E, arch_name); if not ghost then return end
    Units.activate(ghost, 0.0, 0.0) -- shown; moved to cursor each frame
    placing = { E = E, type_key = type_key, ghost = ghost, arch_name = arch_name, workers = workers, valid = false }
end

function Build.cancel()
    if not placing then return end
    return_reserve(placing.E, placing.arch_name, placing.ghost)
    placing = nil
end

function Build.update_placement(dt, state)
    if not placing then return end
    local mx, my = nil, nil
    if input and input.get_mouse_position then local m = input.get_mouse_position(); if m and m.x then mx, my = m.x, m.y end end
    -- NOTE: capture BOTH returns of pick_ground directly. The `mx and pick_ground() or nil`
    -- idiom truncates multi-returns to one value, so gz was always nil -> World.clamp(gx, nil)
    -- threw in U.clamp every frame, which aborted Build.update before the ghost was ever
    -- positioned (no cursor-follow) and before placing.gx was set (left-click confirm no-op).
    local gx, gz
    if mx then gx, gz = Camera.pick_ground(mx, my) end
    if gx then
        local arch = Units.ARCH[placing.arch_name]
        placing.valid = Build.spot_valid(state, gx, gz, arch.radius)
        Units.place(placing.ghost, gx, gz)
        Build.tint_ghost(placing.ghost, placing.valid)
        placing.gx, placing.gz = gx, gz
    end
    -- left-click confirm, right-click cancel handled in wb_orders/selection input layer
end

function Build.confirm(state)
    if not (placing and placing.valid and placing.gx) then return false end
    local E, type_key, gx, gz, workers = placing.E, placing.type_key, placing.gx, placing.gz, placing.workers
    -- reuse the ghost as the site rig: return it to the pool, then place() borrows it back
    return_reserve(E, placing.arch_name, placing.ghost)
    placing = nil
    return Build.place(state, E, type_key, gx, gz, workers) ~= nil
end

WB.build = Build
return Build
