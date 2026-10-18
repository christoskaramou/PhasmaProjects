------------------------------------------------------------------ state
local BR = 0.15                 -- ball radius
local VY = 1.0                  -- Vaus centre line
local VH = 0.2                  -- Vaus half height (collider)
local BW, BH = 1.0, 0.5         -- brick cell
local PTS = { W = 50, O = 60, C = 70, G = 80, R = 90, B = 100, P = 110, Y = 120 }
local P = { x = 0, w = 2.0, wt = 2.0, mode = nil, alive = true, guns = false }
G.P = P; G.BR, G.VY, G.VH = BR, VY, VH
G.BALLS, G.BRICKS, G.CAPS, G.SHOTS, G.EN, G.DSHOT = {}, {}, {}, {}, {}, {}
G.lives = 3
local function add_pts(n)
    local before = G.score
    add_score(n)
    local function thr(s) if s < 20000 then return 0 end; return 1 + floor((s - 20000) / 60000) end
    if thr(G.score) > thr(before) then G.lives = G.lives + 1; sfx("extra"); G.banner_set("Extra Vaus", 1.5) end
end
G.add_pts = add_pts
local function brick_xy(r, c) return -FW / 2 + (c - 0.5) * BW, FH - 0.25 - (r - 1) * BH end
G.brick_xy = brick_xy
local function load_round(n)
    G.round = n; G.BRICKS = {}; G.grid = {}
    G.CAPS, G.SHOTS, G.EN, G.DSHOT = {}, {}, {}, {}
    G.left = 0
    if n <= 32 then
        for r, row in ipairs(G.ROUNDS[n]) do
            for c = 1, #row do
                local ch = row:sub(c, c)
                if ch ~= "." and ch ~= " " then
                    local x, y = brick_xy(r, c)
                    local b = { r = r, c = c, x = x, y = y, k = ch, hp = ch == "S" and (2 + floor((n - 1) / 8)) or 1, alive = true, flash = 0 }
                    G.BRICKS[#G.BRICKS + 1] = b; G.grid[r * 100 + c] = b
                    if ch ~= "X" then G.left = G.left + 1 end
                end
            end
        end
        G.doh = nil
    else
        G.doh = { x = 0, y = 10.6, hw = 1.9, hh = 2.9, hp = 16, flash = 0, fire_t = 2.5, alive = true, t = 0 }
    end
    G.speed_lv = 0; G.hits = 0; G.top_hit = false
    G.en_t = 4; G.warp = false
    P.mode = nil; P.wt = 2.0; P.guns = false
    G.phase = "ready"; G.pt = 0
    G.banner_set(n <= 32 and ("Round " .. n) or "Round 33  ·  DOH", 2.0)
end
G.load_round = load_round
local function serve()
    P.x = 0; P.alive = true
    G.BALLS = { { x = 0, y = VY + VH + BR + 0.01, vx = 0, vy = 0, stuck = true, off = 0.35, hold = 3.0, spd = 7.0 } }
end
G.serve = serve
function G.new_game_sim()
    G.score = 0; G.lives = 3; G.won = false; G.out_of_lives = false
    load_round(1); serve()
end
local function base_speed() return 7.0 + G.speed_lv * 0.55 end
local function set_speed(b, s) local m = sqrt(b.vx * b.vx + b.vy * b.vy); if m > 1e-4 then b.vx, b.vy = b.vx / m * s, b.vy / m * s end; b.spd = s end
local function launch(b)
    b.stuck = false
    local t = clamp(b.off / (P.w / 2), -1, 1)
    local a = math.rad(t * 55 + (abs(t) < 0.05 and 25 or 0))
    b.vx, b.vy = sin(a), cos(a); set_speed(b, P.mode == "S" and 6.0 or base_speed())
    sfx("paddle")
end

------------------------------------------------------------------ capsules
local CAP_ORDER = { "S", "C", "L", "E", "D", "B", "P" }
local function drop_capsule(x, y)
    if #G.BALLS > 1 or #G.CAPS > 0 or rand() > 0.18 then return end
    local k
    repeat k = CAP_ORDER[1 + floor(rand() ^ 1.25 * 7)] until k
    if k == "P" and rand() < 0.6 then k = "E" end
    if k == "B" and rand() < 0.5 then k = "L" end
    G.CAPS[#G.CAPS + 1] = { k = k, x = x, y = y, spin = 0 }
end
local function apply_cap(k)
    sfx("capsule"); add_pts(1000)
    -- a new capsule ends the previous effect (catch releases, laser and enlarge are lost)
    for _, b in ipairs(G.BALLS) do if b.stuck and P.mode == "C" then launch(b) end end
    P.mode = nil; P.wt = 2.0; P.guns = false
    if k == "S" then P.mode = "S"; for _, b in ipairs(G.BALLS) do if not b.stuck then set_speed(b, 6.0) end end; G.speed_lv = 0
    elseif k == "C" then P.mode = "C"
    elseif k == "L" then P.mode = "L"; P.guns = true
    elseif k == "E" then P.mode = "E"; P.wt = 3.0; sfx("enlarge")
    elseif k == "D" then
        sfx("split")
        local b = G.BALLS[1]
        if b then
            if b.stuck then launch(b) end
            local a0 = math.atan2(b.vx, b.vy)
            for _, d in ipairs({ -0.45, 0.45 }) do
                local a = a0 + d
                G.BALLS[#G.BALLS + 1] = { x = b.x, y = b.y, vx = sin(a) * b.spd, vy = cos(a) * b.spd, spd = b.spd }
            end
        end
    elseif k == "B" then G.warp = true; sfx("warp"); G.banner_set("Break", 1.2)
    elseif k == "P" then G.lives = G.lives + 1; sfx("extra") end
    G.banner_set(({ S = "Slow", C = "Catch", L = "Laser", E = "Enlarge", D = "Disruption", B = "Break", P = "Extra Vaus" })[k], 1.0)
end

------------------------------------------------------------------ bricks
local function hit_brick(b)
    if b.k == "X" then b.flash = 1; sfx("hard"); return end
    b.hp = b.hp - 1; b.flash = 1
    if b.hp > 0 then sfx("hard"); return end
    b.alive = false; G.grid[b.r * 100 + b.c] = nil; G.left = G.left - 1
    add_pts(b.k == "S" and 50 * G.round or PTS[b.k])
    sfx("brick"); G.brick_burst(WP(b.x, b.y, 0.2), G.BRICK[b.k])
    if b.k ~= "S" then drop_capsule(b.x, b.y) end
end
local function bricks_near(x, y, f)
    local c0, c1 = floor((x + FW / 2 - 0.4) / BW) + 1, floor((x + FW / 2 + 0.4) / BW) + 1
    local r0, r1 = floor((FH - y - 0.4) / BH) + 1, floor((FH - y + 0.4) / BH) + 1
    for r = r0, r1 do for c = c0, c1 do local b = G.grid[r * 100 + c]; if b then f(b) end end end
end
-- circle vs box: returns push normal (nx, ny) and depth, or nil
local function circ_box(x, y, r, cx, cy, hw, hh)
    local qx, qy = clamp(x, cx - hw, cx + hw), clamp(y, cy - hh, cy + hh)
    local dx, dy = x - qx, y - qy
    local d2 = dx * dx + dy * dy
    if d2 >= r * r then return nil end
    if d2 > 1e-9 then local d = sqrt(d2); return dx / d, dy / d, r - d end
    -- centre inside: push out along the shallow axis
    local px, py = hw - abs(x - cx) + r, hh - abs(y - cy) + r
    if px < py then return (x > cx and 1 or -1), 0, px else return 0, (y > cy and 1 or -1), py end
end
G.circ_box = circ_box

------------------------------------------------------------------ ball step (swept: sub-steps of at most 0.08 units)
local function ball_step(b, dt)
    if b.stuck then b.x = P.x + b.off; b.y = VY + VH + BR + 0.01; return end
    local dist = sqrt(b.vx * b.vx + b.vy * b.vy) * dt
    local n = max(1, math.ceil(dist / 0.08))
    local h = dt / n
    for _ = 1, n do
        b.x, b.y = b.x + b.vx * h, b.y + b.vy * h
        -- walls
        local L, Rr, T = -FW / 2 + BR, FW / 2 - BR, FH - BR
        if b.x < L then b.x = L; b.vx = abs(b.vx); sfx("wall") elseif b.x > Rr then b.x = Rr; b.vx = -abs(b.vx); sfx("wall") end
        if b.y > T then b.y = T; b.vy = -abs(b.vy); sfx("wall")
            if not G.top_hit then G.top_hit = true; if P.mode ~= "S" then G.speed_lv = G.speed_lv + 2; set_speed(b, base_speed()) end end
        end
        -- bricks: resolve the deepest contact only (one brick per sub-step, like the arcade)
        local best, bn
        bricks_near(b.x, b.y, function(k)
            local nx, ny, d = circ_box(b.x, b.y, BR, k.x, k.y, BW / 2, BH / 2)
            if nx and (not best or d > bn[3]) then best, bn = k, { nx, ny, d } end
        end)
        if best then
            b.x, b.y = b.x + bn[1] * bn[3], b.y + bn[2] * bn[3]
            if abs(bn[1]) > abs(bn[2]) then b.vx = bn[1] * abs(b.vx) else b.vy = bn[2] * abs(b.vy) end
            hit_brick(best)
        end
        -- DOH
        local D = G.doh
        if D and D.alive then
            local nx, ny, d = circ_box(b.x, b.y, BR, D.x, D.y, D.hw, D.hh)
            if nx then
                b.x, b.y = b.x + nx * d, b.y + ny * d
                if abs(nx) > abs(ny) then b.vx = nx * abs(b.vx) else b.vy = ny * abs(b.vy) end
                D.hp = D.hp - 1; D.flash = 1; sfx("doh_hit"); G.sparks(WP(b.x, b.y, 0.6), 14)
                if D.hp <= 0 then D.alive = false; D.dead_t = 0; add_pts(0); sfx("doh_die"); G.boom(WP(D.x, D.y, 1), true); G.shake = 1.2 end
            end
        end
        -- enemies: the ball destroys them and bounces off
        for _, e in ipairs(G.EN) do
            if e.alive and (b.x - e.x) ^ 2 + (b.y - e.y) ^ 2 < (BR + 0.3) ^ 2 then
                e.alive = false; add_pts(100); sfx("pop"); G.boom(WP(e.x, e.y, 0.3), false)
                b.vy = -b.vy
            end
        end
        -- Vaus
        if b.vy < 0 and P.alive then
            local hw = P.w / 2
            if b.y - BR < VY + VH and b.y > VY - VH and abs(b.x - P.x) < hw + BR then
                local t = clamp((b.x - P.x) / hw, -1, 1)
                -- angle from vertical grows toward the ends of the Vaus (min 20 deg above horizontal)
                local a = math.rad(t * 62)
                local s = b.spd
                b.vx, b.vy = sin(a) * s, cos(a) * s
                b.y = VY + VH + BR
                G.hits = G.hits + 1
                if G.hits % 12 == 0 and P.mode ~= "S" then G.speed_lv = min(G.speed_lv + 1, 11); set_speed(b, base_speed()) end
                if P.mode == "C" then b.stuck = true; b.off = b.x - P.x; b.hold = 3.0; sfx("catch"); return end
                sfx("paddle")
            end
        end
    end
    -- keep the angle away from horizontal so the ball never stalls sideways
    local s = sqrt(b.vx * b.vx + b.vy * b.vy)
    if abs(b.vy) < s * 0.3 then b.vy = (b.vy >= 0 and 1 or -1) * s * 0.3; b.vx = (b.vx >= 0 and 1 or -1) * s * math.sqrt(1 - 0.09) end
end

------------------------------------------------------------------ death
local function lose_vaus()
    P.alive = false; G.phase = "dead"; G.pt = 0
    sfx("die"); G.boom(WP(P.x, VY, 0.3), false); G.shake = 0.6
    G.lives = G.lives - 1
end
G.lose_vaus = lose_vaus

------------------------------------------------------------------ main step
-- remember where everything was before a fixed step, so the renderer can blend the last two steps by AL
-- (the leftover fraction of a step). Without this the ball moved 0, 1 or 2 steps per displayed frame (judder).
function G.snap_prev()
    P.ox = P.x
    for _, t in ipairs({ G.BALLS, G.CAPS, G.SHOTS, G.DSHOT, G.EN }) do for _, o in ipairs(t) do o.ox, o.oy = o.x, o.y end end
end
function G.round_step(inp, dt)
    G.pt = G.pt + dt
    for _, b in ipairs(G.BRICKS) do if b.flash > 0 then b.flash = max(0, b.flash - dt * 5) end end
    if G.phase == "dead" then
        if G.pt > 2.2 then
            if G.lives <= 0 then G.out_of_lives = true; return end
            P.mode = nil; P.wt = 2.0; P.guns = false; G.CAPS, G.SHOTS, G.DSHOT = {}, {}, {}
            serve(); G.phase = "ready"; G.pt = 0
        end
        return
    end
    if G.phase == "clear" then
        if G.pt > 2.0 then
            if G.round >= G.LAST then G.won = true; G.out_of_lives = true
            else load_round(G.round + 1); serve(); sfx("start") end
        end
        return
    end
    -- Vaus
    P.w = P.w + (P.wt - P.w) * min(1, dt * 10)
    local lim = FW / 2 - P.w / 2
    P.x = clamp(P.x + inp.mx * 13 * dt + inp.mdx, -lim, G.warp and lim + P.w or lim)
    if G.warp and P.x > lim + 0.05 then
        -- through the break gate
        add_pts(10000); sfx("warp"); G.phase = "clear"; G.pt = 1.0; G.BALLS = {}
        return
    end
    if G.phase == "ready" then
        if G.pt > 0.8 then G.phase = "play" end
    end
    -- balls
    for _, b in ipairs(G.BALLS) do
        if b.stuck then
            b.hold = b.hold - dt
            if (inp.fire and G.phase == "play") or b.hold <= 0 then launch(b); inp.fire = false end
        end
        ball_step(b, dt)
    end
    for i = #G.BALLS, 1, -1 do if G.BALLS[i].y < -0.6 then table.remove(G.BALLS, i) end end
    if #G.BALLS == 0 and P.alive then lose_vaus(); return end
    -- laser
    if inp.fire and P.guns and #G.SHOTS < 4 then
        for _, s in ipairs({ -1, 1 }) do G.SHOTS[#G.SHOTS + 1] = { x = P.x + s * (P.w / 2 - 0.22), y = VY + 0.3, py = VY + 0.3 } end
        sfx("laser")
    end
    for i = #G.SHOTS, 1, -1 do
        local s = G.SHOTS[i]
        s.py = s.y; s.y = s.y + 18 * dt
        local hit = false
        -- swept: test every brick row the shot crossed this step
        for y = s.py, s.y, 0.2 do
            bricks_near(s.x, y, function(k) if not hit and abs(s.x - k.x) < BW / 2 and abs(y - k.y) < BH / 2 + 0.1 then hit_brick(k); hit = true end end)
            if hit then break end
        end
        for _, e in ipairs(G.EN) do if not hit and e.alive and abs(s.x - e.x) < 0.35 and e.y > s.py - 0.3 and e.y < s.y + 0.3 then e.alive = false; hit = true; add_pts(100); sfx("pop"); G.boom(WP(e.x, e.y, 0.3), false) end end
        local D = G.doh
        if not hit and D and D.alive and abs(s.x - D.x) < D.hw and s.y > D.y - D.hh then hit = true; G.sparks(WP(s.x, D.y - D.hh, 0.5), 5) end
        if hit or s.y > FH then table.remove(G.SHOTS, i) end
    end
    -- capsules
    for i = #G.CAPS, 1, -1 do
        local c = G.CAPS[i]
        c.y = c.y - 3.2 * dt; c.spin = c.spin + dt * 220
        if P.alive and c.y < VY + VH + 0.17 and c.y > VY - VH - 0.17 and abs(c.x - P.x) < P.w / 2 + 0.37 then apply_cap(c.k); table.remove(G.CAPS, i)
        elseif c.y < -0.6 then table.remove(G.CAPS, i) end
    end
    -- enemies drift in from the two top gates
    if not G.doh then
        G.en_t = G.en_t - dt
        if G.en_t <= 0 and #G.EN < 3 then
            G.en_t = rr(5, 9)
            local kinds = { "en_cone", "en_pyr", "en_orb", "en_cube" }
            G.EN[#G.EN + 1] = { k = kinds[(G.round - 1) % 4 + 1], x = rand() < 0.5 and -3.5 or 3.5, y = FH + 0.3, t = 0, alive = true, ph = rr(0, 6), gate = 0 }
        end
    end
    for i = #G.EN, 1, -1 do
        local e = G.EN[i]
        e.t = e.t + dt
        if e.alive then
            local nx = e.x + cos(e.t * 1.3 + e.ph) * 1.4 * dt
            local ny = e.y - (e.y > 3 and 0.9 or 0.25 * sin(e.t)) * dt
            -- they slide around bricks rather than through them
            local blocked = false
            bricks_near(nx, ny, function(k) if abs(nx - k.x) < 0.75 and abs(ny - k.y) < 0.55 then blocked = true end end)
            if not blocked then e.x, e.y = clamp(nx, -FW / 2 + 0.4, FW / 2 - 0.4), ny
            else e.x = clamp(e.x + (e.x > 0 and -1 or 1) * 1.2 * dt, -FW / 2 + 0.4, FW / 2 - 0.4) end
            if P.alive and abs(e.x - P.x) < P.w / 2 + 0.3 and abs(e.y - VY) < VH + 0.3 then e.alive = false; add_pts(100); sfx("pop"); G.boom(WP(e.x, e.y, 0.3), false) end
            if e.y < -0.5 then e.alive = false end
        else table.remove(G.EN, i) end
    end
    -- DOH
    local D = G.doh
    if D then
        D.t = D.t + dt; D.flash = max(0, D.flash - dt * 4)
        if D.alive then
            D.fire_t = D.fire_t - dt
            if D.fire_t <= 0 and P.alive then
                D.fire_t = rr(1.2, 2.0); sfx("doh_fire")
                local sx, sy = D.x, D.y - 1.6
                local dx, dy = P.x - sx, VY - sy
                local m = sqrt(dx * dx + dy * dy)
                G.DSHOT[#G.DSHOT + 1] = { x = sx, y = sy, vx = dx / m * 5.5, vy = dy / m * 5.5 }
            end
        else
            D.dead_t = D.dead_t + dt
            if D.dead_t > 2.5 then G.phase = "clear"; G.pt = 0; G.BALLS = {} end
        end
    end
    for i = #G.DSHOT, 1, -1 do
        local s = G.DSHOT[i]
        s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
        if P.alive and abs(s.x - P.x) < P.w / 2 + 0.12 and abs(s.y - VY) < VH + 0.12 then table.remove(G.DSHOT, i); lose_vaus(); return
        elseif s.y < -0.5 then table.remove(G.DSHOT, i) end
    end
    -- round clear
    if not G.doh and G.left <= 0 then G.phase = "clear"; G.pt = 0; G.BALLS = {}; sfx("start"); G.banner_set("Round Clear", 1.8) end
end
G.brick_burst, G.sparks, G.boom, G.flash = brick_burst, sparks, boom, flash
