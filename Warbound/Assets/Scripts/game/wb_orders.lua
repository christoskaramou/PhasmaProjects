-- wb_orders — issuing commands (right-click + command card) and locomotion.
-- Locomotion moves units toward their goal or attack target, keeps them spread
-- (separation), faces them along travel, and resolves arrival.

local U = WB.util
local Camera = WB.camera
local World = WB.world

local Orders = {}

local prev_right = false

local function mouse()
    if input and input.get_mouse_position then
        local m = input.get_mouse_position()
        if m and m.x then return m.x, m.y end
    end
    return nil
end

-- ---- command primitives (also called by the HUD command card) -----------------

function Orders.stop(sel)
    for _, u in ipairs(sel) do
        u.order = "idle"; u.target = nil; u.job = nil; u.goal_x, u.goal_z = u.x, u.z
    end
end

function Orders.hold(sel)
    for _, u in ipairs(sel) do
        u.order = "hold"; u.target = nil; u.job = nil; u.goal_x, u.goal_z = u.x, u.z
    end
end

local function formation(n, cx, cz)
    local cols = math.max(1, math.ceil(math.sqrt(n)))
    local rows = math.ceil(n / cols)
    local s = 1.8
    local out = {}
    for i = 0, n - 1 do
        local c = i % cols
        local r = math.floor(i / cols)
        out[i + 1] = {
            x = cx + (c - (cols - 1) * 0.5) * s,
            z = cz + (r - (rows - 1) * 0.5) * s,
        }
    end
    return out
end

function Orders.move_to(sel, cx, cz)
    local pts = formation(#sel, cx, cz)
    for i, u in ipairs(sel) do
        local p = pts[i]
        local gx, gz = World.clamp(p.x, p.z, 0.8)
        u.order = "move"; u.target = nil; u.job = nil; u.goal_x, u.goal_z = gx, gz
    end
end

function Orders.attack(sel, target)
    for _, u in ipairs(sel) do
        u.order = "attack"; u.target = target; u.job = nil; u.attack_move = false
    end
end

-- ---- right-click order issuing ------------------------------------------------

function Orders.handle_input(sel, enemy_units, mouse_in_ui)
    local down = input and input.is_right_mouse_down and input.is_right_mouse_down() == true

    -- Building selection: right-click sets the rally point.
    if WB.selection.building then
        local b = WB.selection.building
        if down and not prev_right and not mouse_in_ui then
            local mx, my = mouse()
            if mx then
                local gx, gz = Camera.pick_ground(mx, my)
                if gx then
                    local kind = WB.economy and WB.economy.resource_near(gx, gz, "player")
                    if kind then b.rally_node = kind; b.rally_x, b.rally_z = gx, gz
                    else b.rally_node = nil; b.rally_x, b.rally_z = gx, gz end
                    b.rally_set = true
                    WB.fx_ping(gx, gz, false)
                    if pe_log then
                        pe_log(string.format("[rally] %s rally set node=%s", b.display or b.arch or "building", tostring(kind or "none")))
                    end
                end
            end
        end
        prev_right = down
        return
    end

    if down and not prev_right and not mouse_in_ui and #sel > 0 then
        local mx, my = mouse()
        if mx then
            local foe = WB.selection.unit_at(mx, my, enemy_units)
            if foe then
                Orders.attack(sel, foe)
                WB.fx_ping(foe.x, foe.z, true)
            else
                local gx, gz = Camera.pick_ground(mx, my)
                if gx then
                    -- Laborers + a click near a resource node = harvest; everything
                    -- else (and any non-worker in the selection) just moves there.
                    local kind = WB.economy and WB.economy.resource_near(gx, gz) or nil
                    local workers = {}
                    if kind then
                        for _, u in ipairs(sel) do
                            if u.alive and u.arch_is_worker then workers[#workers + 1] = u end
                        end
                    end
                    if #workers > 0 then
                        local _state = WB.game and WB.game.state
                        local _E = _state and _state.econ and _state.econ.player
                        if _E then WB.economy.order_harvest(_E, workers, kind) end
                        local movers = {}
                        for _, u in ipairs(sel) do if u.arch ~= "worker" then movers[#movers + 1] = u end end
                        if #movers > 0 then Orders.move_to(movers, gx, gz) end
                    else
                        Orders.move_to(sel, gx, gz)
                    end
                    WB.fx_ping(gx, gz, false)
                end
            end
        end
    end
    prev_right = down
end

-- ---- locomotion ---------------------------------------------------------------

-- Separation push for `unit` from nearby live units. Returns (dx,dz) unit-ish.
local function separation(unit, units)
    local sx, sz = 0.0, 0.0
    for _, o in ipairs(units) do
        if o ~= unit and o.alive then
            local dx, dz = unit.x - o.x, unit.z - o.z
            local min_d = unit.radius + o.radius + 0.1
            local d2 = dx * dx + dz * dz
            if d2 < min_d * min_d and d2 > 1e-5 then
                local d = math.sqrt(d2)
                local push = (min_d - d) / min_d
                sx = sx + (dx / d) * push
                sz = sz + (dz / d) * push
            end
        end
    end
    return sx, sz
end

function Orders.locomote(dt, units)
    for _, u in ipairs(units) do
        if u.alive then
            -- slow debuff (Warstomp): decay timer + cut effective speed
            if (u.slow_t or 0.0) > 0.0 then u.slow_t = u.slow_t - dt end
            local sp = u.speed * (((u.slow_t or 0.0) > 0.0) and 0.55 or 1.0)
            local moving = false
            local pt_x, pt_z, stop = nil, nil, 0.25

            if u.order == "move" then
                pt_x, pt_z, stop = u.goal_x, u.goal_z, 0.25
            elseif u.order == "attack" and u.target and u.target.alive then
                pt_x, pt_z = u.target.x, u.target.z
                stop = u.range * 0.85 + u.target.radius
            elseif u.order == "build" and u.build_target and u.build_target.alive and u.build_target.state == "site" then
                local b = u.build_target
                pt_x, pt_z, stop = b.x, b.z, (b.radius + 1.2)
            elseif u.order == "build" then
                u.order = "idle"; u.build_target = nil
            end

            local face_dx, face_dz = 0.0, 0.0
            if pt_x then
                local dx, dz = pt_x - u.x, pt_z - u.z
                local nx, nz, dist = U.norm2(dx, dz)
                if dist > stop then
                    moving = true
                    local vx, vz = nx * u.speed, nz * u.speed
                    -- blend in separation so units don't pile up
                    local spx, spz = separation(u, units)
                    vx = vx + spx * u.speed * 0.9
                    vz = vz + spz * u.speed * 0.9
                    local nvx, nvz, vlen = U.norm2(vx, vz)
                    if vlen > 0.0 then
                        local step = sp * dt
                        local mx, mz = World.clamp(u.x + nvx * step, u.z + nvz * step, 0.8)
                        WB.units.place(u, mx, mz)
                        face_dx, face_dz = nvx, nvz
                    end
                else
                    face_dx, face_dz = nx, nz -- in range / arrived: face the point
                    if u.order == "move" then
                        u.order = "idle"
                    end
                end
            else
                -- standing units still ease apart if overlapping
                local spx, spz = separation(u, units)
                if spx ~= 0.0 or spz ~= 0.0 then
                    local nvx, nvz = U.norm2(spx, spz)
                    local step = u.speed * 0.5 * dt
                    local mx, mz = World.clamp(u.x + nvx * step, u.z + nvz * step, 0.8)
                    WB.units.place(u, mx, mz)
                end
                if u.order == "attack" and (not u.target or not u.target.alive) then
                    u.order = "idle"; u.target = nil
                end
            end

            if face_dx ~= 0.0 or face_dz ~= 0.0 then
                WB.units.face(u, face_dx, face_dz)
            elseif u.order == "attack" and u.target and u.target.alive then
                local fx, fz = U.norm2(u.target.x - u.x, u.target.z - u.z)
                WB.units.face(u, fx, fz)
            end

            u.moving = moving
        end
    end
end

return Orders
