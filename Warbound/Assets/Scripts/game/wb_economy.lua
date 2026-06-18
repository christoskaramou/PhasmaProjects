-- wb_economy — Slice 2: resource gathering, drop-off, building training, and food.
--
-- Laborers (the `worker` archetype) harvest two resources: GOLD from the gold mine
-- and LUMBER from the forest grove (both authored at fixed World positions). A worker
-- runs a small state machine — walk to the node, chop for a beat, carry the load back
-- to the nearest player building, deposit, repeat — driven entirely by setting the
-- unit's `order`/`goal` so the existing wb_orders locomotion does the actual moving.
--
-- Buildings (Town Hall, Barracks) are authored unit rigs kept in `E.buildings`
-- (NOT in player_units, so they neither count as food nor end the match if lost).
-- They TRAIN units by activating one of the parked reserve units authored offstage
-- (E.unit_reserves[arch]) — no geometry is created at runtime, honoring the
-- engine's "author + adopt, never script-create" rule.
--
-- Food: every live unit costs 1 food; food cap is the sum of each standing
-- building's `food_cap` (Town Hall 12 + Barracks 8). Training is blocked at cap.

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
-- per unit keeps food_used == #live units (what the HUD already shows).
local TRAIN = {
    worker       = { gold = 50,  lumber = 0,  food = 1, time = 6.0,  label = "Train Laborer",  letter = "F" },
    soldier      = { gold = 90,  lumber = 20, food = 1, time = 10.0, label = "Train Soldier",  letter = "V" },
    grunt        = { gold = 70,  lumber = 0,  food = 1, time = 8.0,  label = "Train Raider",   letter = "G" },
    wilds_worker = { gold = 50,  lumber = 0,  food = 1, time = 6.0,  label = "Train Ravager",  letter = "F" },
}
Economy.TRAIN = TRAIN

-- Accessor: return the econ handle for a faction ("player" or "enemy"), or nil.
function Economy.econ(state, faction) return state.econ and state.econ[faction] or nil end

function Economy.init(state)
    -- nothing to initialize now that state.econ is built in reset_state()
    -- kept for API compatibility
end

-- ---- finite resource nodes ----------------------------------------------------
-- Each node holds a finite amount that depletes as workers haul from it. Stored per
-- match in state.nodes so selecting a node can show what's left, and workers stop when
-- it runs dry.
local NODE_MAX = { gold = 1500, lumber = 1200 }

-- (Re)build the per-match resource registry. Called from wb_game reset_state.
function Economy.reset_nodes(state)
    state.nodes = {}
    local function add(kind, faction, np)
        if np and np.x then
            state.nodes[#state.nodes + 1] = { kind = kind, faction = faction,
                x = np.x, z = np.z, amount = NODE_MAX[kind] or 0, max = NODE_MAX[kind] or 0 }
        end
    end
    add("gold", "player", World.mine)
    add("lumber", "player", World.forest)
    add("gold", "enemy", World.wilds_mine)
    add("lumber", "enemy", World.wilds_forest)
end

-- The registry entry for a faction's resource of `kind` (or nil).
function Economy.find_node(state, kind, faction)
    if not (state and state.nodes) then return nil end
    for _, n in ipairs(state.nodes) do
        if n.kind == kind and n.faction == faction then return n end
    end
    return nil
end

-- The resource node nearest a screen click (either faction), for selection. nil if none.
function Economy.node_near_click(sx, sy)
    local state = WB.game and WB.game.state
    if not (state and state.nodes) then return nil end
    local gx, gz = Camera.pick_ground(sx, sy)
    if not gx then return nil end
    local best, bd
    for _, n in ipairs(state.nodes) do
        local d = U.dist2(gx, gz, n.x, n.z)
        if d <= 6.5 and (not bd or d < bd) then best, bd = n, d end
    end
    return best
end

-- World position of a resource node by kind and faction.
local function node_pos(kind, faction)
    if faction == "enemy" then
        if kind == "gold" and World.wilds_mine then return World.wilds_mine.x, World.wilds_mine.z end
        if kind == "lumber" and World.wilds_forest then return World.wilds_forest.x, World.wilds_forest.z end
    else
        if kind == "gold" then return World.mine.x, World.mine.z end
        if kind == "lumber" and World.forest then return World.forest.x, World.forest.z end
    end
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

-- Nearest standing building in E that accepts drop-offs.
local function nearest_dropoff(E, x, z)
    local best, bd
    for _, b in ipairs(E.buildings) do
        if b.alive and b.state ~= "site" and b.is_dropoff then
            local d = U.dist2_sq(x, z, b.x, b.z)
            if not bd or d < bd then best, bd = b, d end
        end
    end
    return best
end

-- ---- harvest order (called from wb_orders on a right-click near a node) ----------

-- Which resource (if any) a ground click at (gx,gz) targets for a given faction.
function Economy.resource_near(gx, gz, faction)
    faction = faction or "player"
    for kind, def in pairs(HARVEST) do
        local nx, nz = node_pos(kind, faction)
        if nx and U.dist2(gx, gz, nx, nz) <= def.click then return kind end
    end
    return nil
end

-- Send the given workers to harvest `kind`. Non-workers are ignored.
function Economy.order_harvest(E, workers, kind)
    local faction = E and E.faction or "player"
    if not (HARVEST[kind] and node_pos(kind, faction)) then return end
    local nx, nz = node_pos(kind, faction)
    for _, u in ipairs(workers) do
        if u.alive and u.arch_is_worker then
            u.job = { kind = kind, nx = nx, nz = nz }
            u.hstate = "to_node"
            u.carry = 0; u.carry_kind = nil
        end
    end
end

-- ---- per-worker harvest state machine -----------------------------------------

local function tick_worker(u, dt, state, E)
    local job = u.job
    if not u.hstate then u.hstate = "to_node" end

    -- Stop on a depleted node (unless still carrying a final load to deliver).
    local rnode = Economy.find_node(state, job.kind, E and E.faction)
    if rnode and rnode.amount <= 0 and (u.carry or 0) <= 0 then
        u.job = nil; u.hstate = nil; u.order = "idle"; return
    end

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
            local node = Economy.find_node(state, job.kind, E.faction)
            local amt = HARVEST[job.kind].amount
            if node then amt = math.min(amt, node.amount); node.amount = node.amount - amt end
            u.carry = amt
            u.carry_kind = job.kind
            u.hstate = "to_drop"
        end
    elseif u.hstate == "to_drop" then
        local b = nearest_dropoff(E, u.x, u.z)
        if not b then u.job = nil; u.hstate = nil; u.order = "idle"; return end
        local gx, gz = approach_point(b.x, b.z, u.x, u.z, b.radius + 1.0)
        u.order = "move"; u.target = nil; u.goal_x, u.goal_z = gx, gz
        if U.dist2(u.x, u.z, b.x, b.z) <= b.radius + 1.8 then
            if u.carry_kind == "gold" then
                E.gold = (E.gold or 0) + (u.carry or 0)
            elseif u.carry_kind == "lumber" then
                E.lumber = (E.lumber or 0) + (u.carry or 0)
            end
            u.carry = 0; u.carry_kind = nil
            u.hstate = "to_node" -- back for another load (job persists until reassigned)
        end
    end
end

-- ---- food accounting ----------------------------------------------------------

-- Live food in use: 1 per living unit in E.
function Economy.food_used(E)
    local n = 0
    for _, u in ipairs(E.units) do if u.alive then n = n + 1 end end
    return n
end

-- Food already committed to in-progress training across all buildings in E.
function Economy.food_queued(E)
    local n = 0
    for _, b in ipairs(E.buildings) do if b.alive and b.queue then n = n + #b.queue end end
    return n
end

-- ---- training -----------------------------------------------------------------

function Economy.train_def(trains) return trains and TRAIN[trains] or nil end

-- Why a building can't train right now (or "ok"): used to color the command button.
function Economy.train_status(state, E, b)
    local def = b and b.trains and TRAIN[b.trains]
    if not def then return "none" end
    if (E.gold or 0) < def.gold then return "gold" end
    if (E.lumber or 0) < def.lumber then return "lumber" end
    if Economy.food_used(E) + Economy.food_queued(E) + def.food > (E.food_cap or 0) then return "food" end
    local pool = E.unit_reserves[b.trains]
    if not pool or #pool == 0 then return "reserve" end
    return "ok"
end

-- Queue a unit at building `b` if affordable; returns true on success.
function Economy.try_train(state, E, b)
    if Economy.train_status(state, E, b) ~= "ok" then return false end
    local def = TRAIN[b.trains]
    E.gold = E.gold - def.gold; E.lumber = E.lumber - def.lumber
    b.queue = b.queue or {}
    b.queue[#b.queue + 1] = { arch = b.trains, t = def.time, total = def.time }
    return true
end

-- Activate one reserve unit of `arch` at building `b`'s rally point and make it live.
local function spawn_trained(state, E, b, arch)
    local pool = E.unit_reserves[arch]
    local u = pool and table.remove(pool) or nil
    if not u then return end
    local rx = b.x + (b.spawn_n or 0) % 3 * 1.6 - 1.6
    local rz = b.z - ((b.radius or 2.0) + 1.5) -- clear the footprint so trained units don't spawn inside the rig
    b.spawn_n = (b.spawn_n or 0) + 1
    rx, rz = World.clamp(rx, rz, 1.0)
    Units.activate(u, rx, rz)
    state.all_units[#state.all_units + 1] = u
    E.units[#E.units + 1] = u
    if b.rally_set then
        if b.rally_node and u.arch_is_worker then
            Economy.order_harvest(E, { u }, b.rally_node)
        else
            u.order = "move"; u.goal_x, u.goal_z = b.rally_x, b.rally_z
        end
    end
end

-- ---- building selection (called from wb_selection on a ground click) ------------

-- The player building under the screen point (sx,sy), or nil. Picks by the ground
-- point's distance to each building footprint — robust at any zoom.
function Economy.building_at(sx, sy)
    local state = WB.game and WB.game.state
    if not state or not state.econ then return nil end
    local E = state.econ.player -- player only; Stage 4 extends building-select to enemy
    if not E then return nil end
    local gx, gz = Camera.pick_ground(sx, sy)
    if not gx then return nil end
    local best, bd
    for _, b in ipairs(E.buildings) do
        if b.alive then
            local d = U.dist2(gx, gz, b.x, b.z)
            if d <= b.radius + 1.2 and (not bd or d < bd) then best, bd = b, d end
        end
    end
    return best
end

-- ---- per-frame update ---------------------------------------------------------

-- Periodic econ readout for dev/verification runs only (gated on the WB_DEMO dev flag,
-- like the rest of the self-demo harness); inert in normal play.
local ECON_LOG = (os and os.getenv and os.getenv("WB_DEMO") == "1") or false
local _econ_log_timer = 0.0

function Economy.update(dt, state)
    for _, fac in ipairs({ "player", "enemy" }) do
        local E = state.econ[fac]
        local cap = 0
        for _, b in ipairs(E.buildings) do
            if b.alive and b.state ~= "site" then cap = cap + (b.food_cap or 0) end
        end
        E.food_cap = cap
        for _, u in ipairs(E.units) do
            if u.alive and u.arch_is_worker and u.job then tick_worker(u, dt, state, E) end
        end
        for _, b in ipairs(E.buildings) do
            if b.alive and b.state ~= "site" and b.queue and #b.queue > 0 then
                local job = b.queue[1]; job.t = job.t - dt
                if job.t <= 0.0 then table.remove(b.queue, 1); spawn_trained(state, E, b, job.arch) end
            end
        end
    end

    -- Dev-only econ readout (~2s cadence; gated on WB_DEMO).
    if ECON_LOG then
        _econ_log_timer = _econ_log_timer + dt
        if _econ_log_timer >= 2.0 then
            _econ_log_timer = 0.0
            local PE = state.econ.player
            if pe_log then
                pe_log(string.format("[econ] player gold=%d lumber=%d food=%d/%d",
                    PE.gold, PE.lumber, Economy.food_used(PE), PE.food_cap))
            end
        end
    end
end

return Economy
