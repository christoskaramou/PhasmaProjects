-- wb_ai — Wilds decision brain: economy, build order, army, reactive combat director.
--
-- Drives state.econ.enemy on a ~0.5s tick (AI is slow, not per-frame).
-- Three sub-directors:
--   tick_economy  — keep workers harvesting, train more up to cap.
--   tick_build    — one construction site at a time; farm -> barracks -> tower.
--   tick_military — train army toward an escalating threshold, then attack or defend.
--
-- Activation: gated behind WB_AI env var (0 = passive Wilds, anything else = active).
-- Called by wb_game.update AFTER wb_build.update so Build.place mutations don't race.

local U = WB.util
local Economy = WB.economy
local Build = WB.build
local Orders = WB.orders
local World = WB.world

local AI = {}

local TICK = 0.5
local acc = 0.0
local damage_recent_t = 0.0  -- set by Combat when an enemy building/unit is hit near base
local attacking = false      -- true once a wave is committed; reset on defend so the next wave logs fresh
local base_x, base_z = nil, nil -- Wilds hall position, cached each tick (for the defense radius)
local BASE_DEF_R = 22.0      -- damage within this of the hall counts as "base under attack"

local function enemy_workers(E)
    local out = {}
    for _, u in ipairs(E.units) do if u.alive and u.arch_is_worker then out[#out+1] = u end end
    return out
end

local function tick_economy(state, E)
    -- keep idle workers harvesting (alternate gold/lumber)
    for i, w in ipairs(enemy_workers(E)) do
        if not w.job and w.order ~= "build" then
            Economy.order_harvest(E, { w }, (i % 2 == 0) and "gold" or "lumber")
        end
    end
    -- train workers up to a cap at the Wilds hall
    local hall = nil
    for _, b in ipairs(E.buildings) do if b.alive and b.state=="done" and b.arch=="enemy_town_hall" then hall=b; break end end
    if hall and #enemy_workers(E) < 5 and Economy.train_status(state, E, hall) == "ok" then
        if pe_log then pe_log(string.format("[ai] train worker (workers=%d gold=%d)", #enemy_workers(E), E.gold or 0)) end
        Economy.try_train(state, E, hall)
    end
end

-- ---- build order --------------------------------------------------------------

local function has_site(E) for _, b in ipairs(E.buildings) do if b.alive and b.state=="site" then return true end end return false end
local function count_arch(E, arch) local n=0 for _,b in ipairs(E.buildings) do if b.alive and b.arch==arch then n=n+1 end end return n end

local function free_worker(E)
    for _, u in ipairs(E.units) do if u.alive and u.arch_is_worker and u.order ~= "build" then return u end end
    return nil
end

local function tick_build(state, E)
    if has_site(E) then return end          -- one site at a time
    local hall = nil
    for _, b in ipairs(E.buildings) do if b.alive and b.state=="done" and b.arch=="enemy_town_hall" then hall=b; break end end
    if not hall then return end
    local want = nil
    if Economy.food_used(E) + 2 >= E.food_cap then want = "farm"
    elseif count_arch(E, "enemy_barracks") < 1 then want = "barracks"
    elseif damage_recent_t > 0 and count_arch(E, "enemy_tower") < 2 then want = "tower"
    elseif (E.gold or 0) > 250 then want = "barracks" end
    if not want then return end
    local def = Build.DEFS[want]; if not def then return end
    if (E.gold or 0) < def.gold or (E.lumber or 0) < def.lumber then return end
    local w = free_worker(E); if not w then return end
    -- pick a spot in a ring around the hall, scan a few angles for a valid one
    for k = 0, 7 do
        local a = k * (math.pi / 4)
        local x = hall.x + math.cos(a) * 8.0
        local z = hall.z + math.sin(a) * 8.0
        x, z = World.clamp(x, z, 3.0)
        if Build.spot_valid(state, x, z, 2.0) then
            if pe_log then pe_log(string.format("[ai] build %s (enemy) at %.1f,%.1f", want, x, z)) end
            Build.place(state, E, want, x, z, { w })
            return
        end
    end
end

-- ---- army + combat director ---------------------------------------------------

local function army(E)
    local out = {}
    for _, u in ipairs(E.units) do if u.alive and not u.arch_is_worker and not u.is_building then out[#out+1] = u end end
    return out
end

local function tick_military(state, E)
    local barracks = nil
    for _, b in ipairs(E.buildings) do if b.alive and b.state=="done" and b.arch=="enemy_barracks" then barracks=b; break end end
    local threshold = 6 + math.floor(state.time / 45.0)   -- escalates ~+1 per 45s
    local a = army(E)
    -- train army toward threshold
    if barracks and #a < threshold + 2 and Economy.train_status(state, E, barracks) == "ok" then
        if pe_log then pe_log(string.format("[ai] train army (army=%d threshold=%d gold=%d)", #a, threshold, E.gold or 0)) end
        Economy.try_train(state, E, barracks)
    end
    -- combat director
    local PB = state.econ.player.buildings
    if damage_recent_t > 0 then
        -- defend: pull army home, flee workers to hall
        attacking = false
        local hall = nil
        for _, b in ipairs(E.buildings) do if b.alive and b.arch=="enemy_town_hall" then hall=b; break end end
        if hall then Orders.move_to(a, hall.x, hall.z + 4.0) end
        for _, w in ipairs(enemy_workers(E)) do if w.order ~= "build" then w.job = nil; w.order = "move"; w.goal_x, w.goal_z = (hall and hall.x or w.x), (hall and hall.z + 6.0 or w.z) end end
    elseif #a >= threshold then
        -- attack: target the player's town hall (or nearest building)
        local tgt = nil
        for _, b in ipairs(PB) do if b.alive and b.arch=="town_hall" then tgt=b; break end end
        if not tgt then for _, b in ipairs(PB) do if b.alive then tgt=b; break end end end
        if tgt then
            if not attacking then
                attacking = true
                if pe_log then pe_log(string.format("[ai] attack wave size=%d target=%s", #a, tgt.arch or "?")) end
            end
            -- (re)command the army each tick so reinforcements join; skip units already on target
            for _, u in ipairs(a) do
                if u.target ~= tgt then u.order = "attack"; u.target = tgt; u.attack_move = true end
            end
        end
    end
end

-- ---- public API ---------------------------------------------------------------

-- Called from Combat when a Wilds thing is hit. Only damage NEAR the Wilds base counts
-- as a base attack: without the radius gate, the AI recalled its own attack wave the
-- instant it took return fire (any enemy taking damage anywhere set the flag) and never
-- committed -- the army oscillated between attack and defend.
function AI.notify_base_attacked(victim)
    if base_x and victim and victim.x then
        local dx, dz = victim.x - base_x, victim.z - base_z
        if dx * dx + dz * dz > BASE_DEF_R * BASE_DEF_R then return end
    end
    damage_recent_t = 3.0
end

function AI.update(dt, state)
    if damage_recent_t > 0 then damage_recent_t = damage_recent_t - dt end
    acc = acc + dt
    if acc < TICK then return end
    acc = 0.0
    local E = state.econ.enemy
    for _, b in ipairs(E.buildings) do
        if b.alive and b.arch == "enemy_town_hall" then base_x, base_z = b.x, b.z; break end
    end
    tick_economy(state, E)
    tick_build(state, E)
    tick_military(state, E)
end

return AI
