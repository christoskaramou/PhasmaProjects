-- wb_economy — Slice 2: resource gathering, drop-off, building training, and food.
--
-- Laborers (the `worker` archetype) harvest two resources: GOLD from the gold mine
-- and LUMBER from the forest grove (both authored at fixed World positions). A worker
-- runs a small state machine — walk to the node, chop for a beat, carry the load back
-- to the nearest player building, deposit, repeat — driven entirely by setting the
-- unit's `order`/`goal` so the existing wb_orders locomotion does the actual moving.
--
-- Buildings (Town Hall, Barracks) are authored unit rigs kept in `state.buildings`
-- (NOT in player_units, so they neither count as food nor end the match if lost).
-- They TRAIN units by activating one of the parked reserve units the bake authored
-- offstage (state.reserves[arch]) — no geometry is created at runtime, honoring the
-- engine's "author + adopt, never script-create" rule.
--
-- Food: every live player unit costs 1 food; food cap is the sum of each standing
-- player building's `food_cap` (Town Hall 12 + Barracks 8). Training is blocked at cap.

local U = WB.util
local World = WB.world
local Units = WB.units
local Camera = WB.camera

local Economy = {}

-- Harvest tuning: how much a trip yields, how long a chop takes, and how close the
-- worker must get to the node / drop-off (node radii baked into `reach`).
local HARVEST = {
    gold   = { amount = 10, time = 2.4, reach = 3.8, click = 7.0 },
    lumber = { amount = 8,  time = 2.0, reach = 3.4, click = 7.5 },
}

-- Training: cost (gold/lumber), food, and build time per trained archetype. 1 food
-- per unit keeps food_used == #live player units (what the HUD already shows).
local TRAIN = {
    worker  = { gold = 50,  lumber = 0,  food = 1, time = 6.0,  label = "Train Laborer", letter = "F" },
    soldier = { gold = 90,  lumber = 20, food = 1, time = 10.0, label = "Train Soldier", letter = "V" },
}
Economy.TRAIN = TRAIN

-- The economy reads/writes the shared match state. wb_selection / wb_orders call into
-- the economy without a state handle, so we stash the live one here on init/update.
Economy._state = nil

function Economy.init(state)
    Economy._state = state
    state.buildings = state.buildings or {}
    state.reserves = state.reserves or {}
end

-- World position of a resource node by kind.
local function node_pos(kind)
    if kind == "gold" then return World.mine.x, World.mine.z end
    if kind == "lumber" and World.forest then return World.forest.x, World.forest.z end
    return nil
end

-- A point `reach` short of (nx,nz) along the line back toward (fromx,fromz), so a
-- worker stops at the edge of a node/building instead of walking into its center.
local function approach_point(nx, nz, fromx, fromz, reach)
    local dx, dz = fromx - nx, fromz - nz
    local ux, uz, d = U.norm2(dx, dz)
    if d < 1e-3 then ux, uz = 0.0, 1.0 end
    return nx + ux * reach, nz + uz * reach
end

-- Nearest standing player building to (x,z) — the resource drop-off.
local function nearest_dropoff(state, x, z)
    local best, bd
    for _, b in ipairs(state.buildings) do
        if b.alive and b.faction == "player" then
            local d = U.dist2_sq(x, z, b.x, b.z)
            if not bd or d < bd then best, bd = b, d end
        end
    end
    return best
end

-- ---- harvest order (called from wb_orders on a right-click near a node) ----------

-- Which resource (if any) a ground click at (gx,gz) targets.
function Economy.resource_near(gx, gz)
    for kind, def in pairs(HARVEST) do
        local nx, nz = node_pos(kind)
        if nx and U.dist2(gx, gz, nx, nz) <= def.click then return kind end
    end
    return nil
end

-- Send the given workers to harvest `kind`. Non-workers are ignored.
function Economy.order_harvest(state, workers, kind)
    if not (HARVEST[kind] and node_pos(kind)) then return end
    local nx, nz = node_pos(kind)
    for _, u in ipairs(workers) do
        if u.alive and u.arch == "worker" then
            u.job = { kind = kind, nx = nx, nz = nz }
            u.hstate = "to_node"
            u.carry = 0; u.carry_kind = nil
        end
    end
end

-- ---- per-worker harvest state machine -----------------------------------------

local function tick_worker(u, dt, state)
    local job = u.job
    if not u.hstate then u.hstate = "to_node" end

    if u.hstate == "to_node" then
        local def = HARVEST[job.kind]
        local gx, gz = approach_point(job.nx, job.nz, u.x, u.z, def.reach)
        u.order = "move"; u.target = nil; u.goal_x, u.goal_z = gx, gz
        if U.dist2(u.x, u.z, job.nx, job.nz) <= def.reach + 0.6 then
            u.hstate = "harvest"; u.htimer = def.time
            u.order = "idle"; u.goal_x, u.goal_z = u.x, u.z
        end
    elseif u.hstate == "harvest" then
        u.order = "idle"; u.goal_x, u.goal_z = u.x, u.z
        -- face + swing the pick toward the node for a chopping read
        local fx, fz = U.norm2(job.nx - u.x, job.nz - u.z)
        if fx ~= 0.0 or fz ~= 0.0 then WB.units.face(u, fx, fz) end
        if (u.attack_swing or 0.0) <= 0.0 then u.attack_swing = 0.25 end
        u.htimer = (u.htimer or 0.0) - dt
        if u.htimer <= 0.0 then
            u.carry = HARVEST[job.kind].amount
            u.carry_kind = job.kind
            u.hstate = "to_drop"
        end
    elseif u.hstate == "to_drop" then
        local b = nearest_dropoff(state, u.x, u.z)
        if not b then u.job = nil; u.hstate = nil; u.order = "idle"; return end
        local gx, gz = approach_point(b.x, b.z, u.x, u.z, b.radius + 1.0)
        u.order = "move"; u.target = nil; u.goal_x, u.goal_z = gx, gz
        if U.dist2(u.x, u.z, b.x, b.z) <= b.radius + 1.8 then
            if u.carry_kind == "gold" then
                state.gold = (state.gold or 0) + (u.carry or 0)
            elseif u.carry_kind == "lumber" then
                state.lumber = (state.lumber or 0) + (u.carry or 0)
            end
            u.carry = 0; u.carry_kind = nil
            u.hstate = "to_node" -- back for another load (job persists until reassigned)
        end
    end
end

-- ---- food accounting ----------------------------------------------------------

-- Live food in use: 1 per living player unit (workers, soldiers, hero).
function Economy.food_used(state)
    local n = 0
    for _, u in ipairs(state.player_units) do if u.alive then n = n + 1 end end
    return n
end

-- Food already committed to in-progress training across all player buildings.
function Economy.food_queued(state)
    local n = 0
    for _, b in ipairs(state.buildings) do
        if b.alive and b.queue then n = n + #b.queue end
    end
    return n
end

-- ---- training -----------------------------------------------------------------

function Economy.train_def(trains) return trains and TRAIN[trains] or nil end

-- Why a building can't train right now (or "ok"): used to color the command button.
function Economy.train_status(state, b)
    local def = b and b.trains and TRAIN[b.trains]
    if not def then return "none" end
    if (state.gold or 0) < def.gold then return "gold" end
    if (state.lumber or 0) < def.lumber then return "lumber" end
    if Economy.food_used(state) + Economy.food_queued(state) + def.food > (state.food_cap or 0) then return "food" end
    local pool = state.reserves[b.trains]
    if not pool or #pool == 0 then return "reserve" end
    return "ok"
end

-- Queue a unit at building `b` if affordable; returns true on success.
function Economy.try_train(state, b)
    if Economy.train_status(state, b) ~= "ok" then return false end
    local def = TRAIN[b.trains]
    state.gold = (state.gold or 0) - def.gold
    state.lumber = (state.lumber or 0) - def.lumber
    b.queue = b.queue or {}
    b.queue[#b.queue + 1] = { arch = b.trains, t = def.time, total = def.time }
    return true
end

-- Activate one reserve unit of `arch` at building `b`'s rally point and make it live.
local function spawn_trained(state, b, arch)
    local pool = state.reserves[arch]
    local u = pool and table.remove(pool) or nil
    if not u then return end
    local rx = (b.rally_x or b.x) + (b.spawn_n or 0) % 3 * 1.6 - 1.6
    local rz = (b.rally_z or (b.z - 6.0))
    b.spawn_n = (b.spawn_n or 0) + 1
    rx, rz = World.clamp(rx, rz, 1.0)
    Units.activate(u, rx, rz)
    state.all_units[#state.all_units + 1] = u
    state.player_units[#state.player_units + 1] = u
end

-- ---- building selection (called from wb_selection on a ground click) ------------

-- The player building under the screen point (sx,sy), or nil. Picks by the ground
-- point's distance to each building footprint — robust at any zoom.
function Economy.building_at(sx, sy)
    local state = Economy._state
    if not state or not state.buildings then return nil end
    local gx, gz = Camera.pick_ground(sx, sy)
    if not gx then return nil end
    local best, bd
    for _, b in ipairs(state.buildings) do
        if b.alive then
            local d = U.dist2(gx, gz, b.x, b.z)
            if d <= b.radius + 1.2 and (not bd or d < bd) then best, bd = b, d end
        end
    end
    return best
end

-- ---- per-frame update ---------------------------------------------------------

function Economy.update(dt, state)
    Economy._state = state

    -- food cap = sum of standing player buildings' caps
    local cap = 0
    for _, b in ipairs(state.buildings) do
        if b.alive and b.faction == "player" then cap = cap + (b.food_cap or 0) end
    end
    state.food_cap = cap

    -- workers harvest
    for _, u in ipairs(state.player_units) do
        if u.alive and u.arch == "worker" and u.job then tick_worker(u, dt, state) end
    end

    -- building training queues
    for _, b in ipairs(state.buildings) do
        if b.alive and b.queue and #b.queue > 0 then
            local job = b.queue[1]
            job.t = job.t - dt
            if job.t <= 0.0 then
                table.remove(b.queue, 1)
                spawn_trained(state, b, job.arch)
            end
        end
    end
end

return Economy
