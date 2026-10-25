------------------------------------------------------------------ gameplay simulation (fixed 60 Hz, world units)
local FR = 1 / 60
local GRAV, BVX, POPV = 34, 4.8, 9.5
local RAD = { 0.38, 0.72, 1.35, 2.1 }            -- balloon radius by size 1..4
local APEX = { 6.5, 10, 14.5, 18.5 }             -- fixed bounce apex (centre height above the floor) by size
local PTS = { 200, 150, 100, 50 }
local BV = {}
for s = 1, 4 do BV[s] = sqrt(2 * GRAV * (APEX[s] - RAD[s])) end
local PW, PCLIMB, PHW, PH = 9.2, 6.2, 0.5, 2.6
local WIRE_V, BULLET_V = 30, 42
G.CONST = { GRAV = GRAV, BVX = BVX, RAD = RAD, APEX = APEX, PW = PW, PCLIMB = PCLIMB, WIRE_V = WIRE_V }
local BALLS, ROPES, SHOTS, ITEMS, ANIMALS = {}, {}, {}, {}, {}
G.BALLS, G.ROPES, G.SHOTS, G.ITEMS, G.ANIMALS = BALLS, ROPES, SHOTS, ITEMS, ANIMALS
local P = { x = 0, y = 0, ox = 0, oy = 0, st = "walk", face = 1, ph = 0, shoot_t = 0, weapon = "wire", shield = false, inv = 0, stun = 0, vx = 0, vy = 0 }
G.P = P
local HB = { pw = 0.45, py0 = 0.15, py1 = 2.15, ball_k = 0.9, rope = 0.12 }
G.HB = HB
local function circ_box(cx, cy, r, x0, y0, x1, y1)
    local px, py = clamp(cx, x0, x1), clamp(cy, y0, y1)
    local dx, dy = cx - px, cy - py
    return dx * dx + dy * dy < r * r
end
G.circ_box = circ_box

------------------------------------------------------------------ balloons
local function ball_new(size, x, y, vx, vy, col)
    BALLS[#BALLS + 1] = { size = size, x = x, y = y, ox = x, oy = y, vx = vx, vy = vy, col = col or ST.def.color, r = RAD[size], spin = rand() * 360 }
    return BALLS[#BALLS]
end
G.ball_new = ball_new
local function ball_step(b, dt)
    b.ox, b.oy = b.x, b.y
    b.vy = b.vy - GRAV * dt
    b.x = b.x + b.vx * dt; b.y = b.y + b.vy * dt
    local r = b.r
    if b.x - r < X0 then b.x = X0 + r; b.vx = abs(b.vx) end
    if b.x + r > X1 then b.x = X1 - r; b.vx = -abs(b.vx) end
    if b.y + r > CEIL then b.y = CEIL - r; b.vy = -abs(b.vy) end
    if b.y - r < 0 then b.y = r; b.vy = BV[b.size]; b.bounced = true end
    for _, k in ipairs(ST.blocks) do
        if k.live then
            local px, py = clamp(b.x, k.x0, k.x1), clamp(b.y, k.y0, k.y1)
            local dx, dy = b.x - px, b.y - py
            if dx * dx + dy * dy < r * r then
                if abs(dy) >= abs(dx) then
                    if dy > 0 or (dy == 0 and b.y > (k.y0 + k.y1) / 2) then b.y = k.y1 + r; b.vy = BV[b.size]
                    else b.y = k.y0 - r; b.vy = -abs(b.vy) end
                else
                    if dx > 0 then b.x = k.x1 + r; b.vx = abs(b.vx) else b.x = k.x0 - r; b.vx = -abs(b.vx) end
                end
            end
        end
    end
end
local ITEM_KINDS = { { "double", .17 }, { "power", .14 }, { "vulcan", .12 }, { "clock", .1 }, { "hourglass", .1 }, { "dynamite", .08 },
    { "shield", .1 }, { "life", .02 }, { "fruit", .17 } }
local function item_drop(x, y, forced)
    if not forced and rand() > 0.13 then return end
    local r, acc, kind = rand(), 0, "fruit"
    for _, k in ipairs(ITEM_KINDS) do acc = acc + k[2]; if r <= acc then kind = k[1]; break end end
    if kind == "life" and G.lives >= 6 then kind = "fruit" end
    ITEMS[#ITEMS + 1] = { kind = kind, x = clamp(x, X0 + 0.6, X1 - 0.6), y = y, oy = y, vy = 0, t = 0, fruit = floor(rr(1, 3.999)) }
end
G.item_drop = item_drop
local function ball_pop(i, silent_score)
    local b = BALLS[i]; if not b then return end
    table.remove(BALLS, i)
    if not silent_score then add_score(PTS[b.size], b.x, b.y + b.r + 0.6) end
    sfx("pop" .. b.size)
    local c = BALLC[b.col]
    sparks(b.x, b.y, c, 10 + b.size * 10, 10 + b.size * 4, b.r * 0.7)
    flash(b.x, b.y, c, 25 + b.size * 12, 0.3, 4 + b.size * 2)
    G.ring_fx(b.x, b.y, b.r, b.col)
    if b.size >= 4 then G.shake = max(G.shake, 0.35) end
    if b.size > 1 then
        local s = b.size - 1
        local y = max(b.y, RAD[s] + 0.05)
        ball_new(s, b.x - RAD[s] * 0.5, y, -BVX, POPV, b.col)
        ball_new(s, b.x + RAD[s] * 0.5, y, BVX, POPV, b.col)
        item_drop(b.x, b.y)
    end
end
G.ball_pop = ball_pop
local function dynamite()
    local again = true
    while again do
        again = false
        for i = #BALLS, 1, -1 do if BALLS[i].size > 1 then ball_pop(i, true); again = true end end
    end
    for i = #ITEMS, 1, -1 do if ITEMS[i].dyn then table.remove(ITEMS, i) end end
    sfx("boom"); G.shake = 0.8
end

------------------------------------------------------------------ blocks
local function block_break(k)
    k.live = false; k.node:set_position(HIDE)
    sfx("break"); add_score(100, (k.x0 + k.x1) / 2, k.y1 + 0.5)
    local c = G.BLK_COL[k.kind]
    for x = k.x0 + 0.5, k.x1 - 0.4, 1 do sparks(x, (k.y0 + k.y1) / 2, c, 10, 10, 0.4) end
    if rand() < 0.35 then item_drop((k.x0 + k.x1) / 2, k.y0, true) end
end

------------------------------------------------------------------ player
-- death: the classic Pang knock-back. A short hit-stop with a flash, then a keyframed arc away from the balloon
-- with a spin that eases out into lying on the back, one small bounce, and a still pose. Keys are {t, value, ease}
-- where ease shapes the segment towards the next key.
local EASE = { lin = function(u) return u end, out = function(u) return 1 - (1 - u) * (1 - u) end,
    ["in"] = function(u) return u * u end, inout = function(u) return u * u * (3 - 2 * u) end }
local function kf(keys, t)
    if t <= keys[1][1] then return keys[1][2] end
    for i = 1, #keys - 1 do
        local a, b = keys[i], keys[i + 1]
        if t < b[1] then return a[2] + (b[2] - a[2]) * EASE[a[3] or "lin"]((t - a[1]) / (b[1] - a[1])) end
    end
    return keys[#keys][2]
end
G.kf = kf
local DIE = {
    hold = 0.14,
    x = { { 0, 0 }, { 0.14, 0, "out" }, { 0.95, 4.6, "out" }, { 1.25, 5.3 } },
    up = { { 0, 0 }, { 0.14, 0, "out" }, { 0.52, 3.3, "in" }, { 0.95, 0 } },        -- lift above the start height, then down
    land = { { 0, 0 }, { 0.52, 0 }, { 0.95, 1, "out" } },                            -- 0..1 blend from start height to the floor
    bounce = { { 0, 0 }, { 0.95, 0, "out" }, { 1.1, 0.55, "in" }, { 1.25, 0 } },
    spin = { { 0, 0, "out" }, { 0.14, -18, "out" }, { 0.95, 450, "inout" }, { 1.1, 468, "inout" }, { 1.25, 450 } },
}
G.DIE = DIE
local function fold(x)       -- walls reflect the arc, like the arcade
    local lo, hi = X0 + 0.9, X1 - 0.9
    for _ = 1, 3 do if x < lo then x = 2 * lo - x elseif x > hi then x = 2 * hi - x end end
    return clamp(x, lo, hi)
end
local function death_step(dt)
    local t0 = P.dead_t; P.dead_t = P.dead_t + dt
    local t, D = P.dead_t, P.die
    P.x = fold(D.x0 + D.d * kf(DIE.x, t))
    P.y = lerp(D.y0, 0, kf(DIE.land, t)) + kf(DIE.up, t) + kf(DIE.bounce, t)
    if t0 < 0.95 and t >= 0.95 then dust(P.x, 0, 8); G.shake = max(G.shake, 0.25); sfx("thud") end
    if t0 < 1.25 and t >= 1.25 then dust(P.x, 0, 4) end
end
local function player_die(cause, bx)
    if P.st == "dead" or G.god then return end
    local d = bx and ((P.x >= bx) and 1 or -1) or ((P.x < 0) and 1 or -1)
    P.st = "dead"; P.dead_t = 0; P.vx, P.vy = 0, 0; P.cause = cause
    P.die = { x0 = P.x, y0 = P.y, d = d }
    music(nil); sfx("death"); G.shake = 0.6
    flash(P.x, P.y + 1.2, { 1, .95, .85 }, 32, 0.3, 7)
    G.ring_fx(P.x, P.y + 1.3, 1, { 1, 1, 1 })
    sparks(P.x, P.y + 1.3, { 1, .9, .6 }, 26, 14, 1)
    G.hit_flash = 1
end
G.player_die = player_die
local function ladder_near(x, y, top)
    for _, l in ipairs(ST.ladders) do
        if abs(x - l.x) < 0.75 then
            if top and abs(y - l.y1) < 0.35 then return l end
            if not top and abs(y - l.y0) < 0.35 then return l end
        end
    end
end
local function fire(inp)
    local w = P.weapon
    if w == "vulcan" then
        if inp.fire_held and (P.vcool or 0) <= 0 and #SHOTS < 8 then
            P.vcool = 0.09
            SHOTS[#SHOTS + 1] = { x = P.x + (#SHOTS % 2 == 0 and -0.2 or 0.2), y = P.y + 2.4, oy = P.y + 2.4 }
            sfx("vulcan"); P.shoot_t = 0.1
        end
        return
    end
    if not inp.fire then return end
    local cap = (w == "double") and 2 or 1
    if #ROPES >= cap then return end
    ROPES[#ROPES + 1] = { x = P.x, y0 = P.y, tip = P.y + 1.8, otip = P.y + 1.8, st = "rise", t = 0, power = (w == "power") }
    P.shoot_t = 0.14; sfx("shoot")
end
local function player_step(inp, dt)
    P.ox, P.oy = P.x, P.y
    P.vcool = (P.vcool or 0) - dt
    P.inv = max(0, P.inv - dt)
    if P.st == "dead" then death_step(dt); return end
    if P.stun > 0 then P.stun = P.stun - dt; return end
    fire(inp)
    if P.shoot_t > 0 then P.shoot_t = P.shoot_t - dt end
    local moving = P.shoot_t <= 0 or P.weapon == "vulcan" or G.jev_x
    if P.st == "walk" then
        local lu = inp.v > 0 and ladder_near(P.x, P.y, false)
        local ld = inp.v < 0 and ladder_near(P.x, P.y, true)
        if lu or ld then
            P.st = "climb"; P.ladder = lu or ld; P.x = P.ladder.x
        elseif moving and inp.h ~= 0 then
            P.face = inp.h
            local nx = P.x + inp.h * PW * dt
            for _, k in ipairs(ST.blocks) do
                if k.live and k.y0 < P.y + PH - 0.2 and k.y1 > P.y + 0.15 then
                    if inp.h > 0 and P.x + PHW <= k.x0 + 0.01 and nx + PHW > k.x0 then nx = k.x0 - PHW end
                    if inp.h < 0 and P.x - PHW >= k.x1 - 0.01 and nx - PHW < k.x1 then nx = k.x1 + PHW end
                end
            end
            P.x = clamp(nx, X0 + PHW, X1 - PHW)
            P.ph = P.ph + dt * 11
            P.step_t = (P.step_t or 0) - dt
            if P.step_t <= 0 then sfx("walk"); P.step_t = 0.24 end
        else P.step_t = 0 end
        local s = G.support_at(P.x, P.y, PHW * 0.5, 0.3, 0.3)
        if s then P.y = s else P.st = "fall"; P.vy = 0 end
    elseif P.st == "climb" then
        local l = P.ladder
        if inp.v ~= 0 then
            P.y = P.y + inp.v * PCLIMB * dt; P.ph = P.ph + dt * 9
            P.step_t = (P.step_t or 0) - dt
            if P.step_t <= 0 then sfx("climb"); P.step_t = 0.2 end
        end
        if P.y >= l.y1 then P.y = l.y1; P.st = "walk"
        elseif P.y <= l.y0 then P.y = l.y0; P.st = "walk" end
    elseif P.st == "fall" then
        local y0 = P.y
        P.vy = P.vy - 40 * dt; P.y = P.y + P.vy * dt
        local s = G.support_at(P.x, (y0 + P.y) / 2, PHW * 0.5, (y0 - P.y) / 2 + 0.05, (y0 - P.y) / 2 + 0.05)
        if s and s <= y0 + 0.01 and s >= P.y - 0.01 then P.y = s; P.st = "walk"; dust(P.x, s, 5) end
        if P.y < 0 then P.y = 0; P.st = "walk" end
    end
end

------------------------------------------------------------------ wires + vulcan shots
local function rope_hits_ball(r)
    for i = #BALLS, 1, -1 do
        local b = BALLS[i]
        local cy = clamp(b.y, r.y0, r.tip)
        local dx, dy = b.x - r.x, b.y - cy
        local rad = b.r + HB.rope
        if dx * dx + dy * dy < rad * rad then ball_pop(i); return true end
    end
    for i = #ANIMALS, 1, -1 do
        local a = ANIMALS[i]
        if a.st ~= "hit" and abs(a.x - r.x) < 0.9 and a.y < r.tip and a.y + 1.0 > r.y0 then
            a.st = "hit"; a.vy = 10; add_score(500, a.x, a.y + 1.5); sfx("animal"); sparks(a.x, a.y + 0.5, { 1, .8, .4 }, 20); return true
        end
    end
    return false
end
local function rope_step(r, i, dt)
    r.otip = r.tip
    if r.st == "rise" then
        local nt = r.tip + WIRE_V * dt
        local stop = nil
        if nt >= CEIL then stop = CEIL; r.hit = "ceil" end
        for _, k in ipairs(ST.blocks) do
            if k.live and r.x > k.x0 - 0.05 and r.x < k.x1 + 0.05 and r.y0 < k.y0 and nt >= k.y0 and (not stop or k.y0 < stop) then stop = k.y0; r.hit = k end
        end
        r.tip = stop or nt
        if rope_hits_ball(r) then table.remove(ROPES, i); return end
        if stop then
            local k = r.hit
            if type(k) == "table" and k.kind ~= "s" then block_break(k); table.remove(ROPES, i); return end
            if r.power then r.st = "stick"; r.t = 3.0; sfx("climb") else table.remove(ROPES, i) end
            if type(k) ~= "table" then sparks(r.x, r.tip, { .9, .9, 1 }, 6, 6, 0.1) end
            return
        end
    else
        r.t = r.t - dt
        if rope_hits_ball(r) or r.t <= 0 then table.remove(ROPES, i) end
    end
end
local function shot_step(s, i, dt)
    s.oy = s.y; s.y = s.y + BULLET_V * dt
    if s.y >= CEIL then table.remove(SHOTS, i); return end
    for _, k in ipairs(ST.blocks) do
        if k.live and s.x > k.x0 and s.x < k.x1 and s.y >= k.y0 and s.oy <= k.y1 then
            if k.kind ~= "s" then block_break(k) end
            table.remove(SHOTS, i); return
        end
    end
    for j = #BALLS, 1, -1 do
        local b = BALLS[j]
        local cy = clamp(b.y, s.oy - 0.3, s.y)
        local dx, dy = b.x - s.x, b.y - cy
        if dx * dx + dy * dy < (b.r + 0.15) ^ 2 then ball_pop(j); table.remove(SHOTS, i); return end
    end
end

------------------------------------------------------------------ items + animals
local function apply_item(it)
    local k = it.kind
    if k == "double" or k == "power" or k == "vulcan" then P.weapon = k; sfx("weapon"); popup(it.x, it.y + 1.5, ({ double = "Double Wire", power = "Power Wire", vulcan = "Vulcan Missile" })[k], { .7, .9, 1 })
    elseif k == "clock" then G.freeze_t = 6; sfx("freeze"); popup(it.x, it.y + 1.5, "Time Stop", { .7, .9, 1 })
    elseif k == "hourglass" then G.slow_t = 8; sfx("freeze"); popup(it.x, it.y + 1.5, "Slow", { .7, .9, 1 })
    elseif k == "dynamite" then dynamite()
    elseif k == "shield" then P.shield = true; sfx("shield")
    elseif k == "life" then G.lives = G.lives + 1; sfx("life"); popup(it.x, it.y + 1.5, "1UP", { 1, .9, .5 })
    else add_score(({ 500, 1000, 2000 })[it.fruit], it.x, it.y + 1.2); sfx("item") end
end
local function item_step(it, i, dt)
    it.t = it.t + dt
    it.oy = it.y
    if not it.landed then
        local y0 = it.y
        it.vy = it.vy - 20 * dt; it.y = it.y + it.vy * dt
        local s = G.support_at(it.x, (y0 + it.y) / 2, 0.3, (y0 - it.y) / 2 + 0.05, (y0 - it.y) / 2 + 0.05)
        if s and s <= y0 + 0.01 then it.y = s; it.landed = true end
        if it.y <= 0 then it.y = 0; it.landed = true end
    else
        local s = G.support_at(it.x, it.y, 0.3, 0.05, 0.05)
        if not s then it.landed = false; it.vy = 0 end
    end
    if it.t > 7 then table.remove(ITEMS, i); return end
    if P.st ~= "dead" and abs(it.x - P.x) < 1.0 and it.y < P.y + 2.2 and it.y + 1.0 > P.y then apply_item(it); table.remove(ITEMS, i) end
end
local function animal_spawn(kind)
    local side = rand() < 0.5 and -1 or 1
    if kind == "crab" then ANIMALS[#ANIMALS + 1] = { kind = "crab", x = side * 23, y = 0, vx = -side * 3.2, st = "walk", t = 0, ox = side * 23, oy = 0 }
    else local y = rr(15, 20); ANIMALS[#ANIMALS + 1] = { kind = "bird", x = side * 23.5, y = y, y0 = y, vx = -side * 5, st = "fly", t = 0, ox = side * 23.5, oy = y } end
end
G.animal_spawn = animal_spawn
local function animal_step(a, i, dt)
    a.ox, a.oy = a.x, a.y
    a.t = a.t + dt
    if a.st == "hit" then
        a.vy = a.vy - 30 * dt; a.y = a.y + a.vy * dt; a.x = a.x + a.vx * 0.3 * dt
        if a.y < -4 then table.remove(ANIMALS, i) end
        return
    end
    a.x = a.x + a.vx * dt
    if a.kind == "crab" then
        if a.x < X0 + 1 or a.x > X1 - 1 then a.vx = -a.vx; a.x = clamp(a.x, X0 + 1, X1 - 1); a.turns = (a.turns or 0) + 1 end
        if (a.turns or 0) >= 3 and (a.x < X0 + 1.2 or a.x > X1 - 1.2) then table.remove(ANIMALS, i); return end
        if P.st ~= "dead" and P.inv <= 0 and P.stun <= 0 and abs(a.x - P.x) < 1.1 and P.y < 1.0 then P.stun = 1.4; P.inv = 2.6; sfx("animal") end
    else
        a.y = a.y0 + sin(a.t * 3) * 1.2
        if a.x < X0 - 1 or a.x > X1 + 1 then table.remove(ANIMALS, i); return end
    end
end

------------------------------------------------------------------ collisions + step
local function player_hit()
    if P.st == "dead" or P.inv > 0 then return end
    local x0, y0, x1, y1 = P.x - HB.pw, P.y + HB.py0, P.x + HB.pw, P.y + HB.py1
    for i, b in ipairs(BALLS) do
        if circ_box(b.x, b.y, b.r * HB.ball_k, x0, y0, x1, y1) then
            if P.shield then
                P.shield = false; P.inv = 1.6; sfx("shield"); sparks(P.x, P.y + 1.3, { .5, .85, 1 }, 30, 16, 1)
                b.vy = BV[b.size]; b.vx = (b.x > P.x) and abs(b.vx) or -abs(b.vx)
            else player_die("ball", b.x) end
            return
        end
    end
end
local function stage_step(inp, dt)
    if P.st ~= "dead" then
        G.time = G.time - dt
        if G.time <= 15 and floor(G.time + dt) ~= floor(G.time) and G.time > 0 then sfx("warn") end
        if G.time <= 0 then G.time = 0; player_die("time") end
    end
    player_step(inp, dt)
    if P.st == "dead" then return end
    local bdt = dt
    if (G.freeze_t or 0) > 0 then G.freeze_t = G.freeze_t - dt; bdt = 0 end
    if (G.slow_t or 0) > 0 then G.slow_t = G.slow_t - dt; bdt = bdt * 0.4 end
    if bdt > 0 then for _, b in ipairs(BALLS) do ball_step(b, bdt) end else for _, b in ipairs(BALLS) do b.ox, b.oy = b.x, b.y end end
    for i = #ROPES, 1, -1 do rope_step(ROPES[i], i, dt) end
    for i = #SHOTS, 1, -1 do shot_step(SHOTS[i], i, dt) end
    for i = #ITEMS, 1, -1 do item_step(ITEMS[i], i, dt) end
    for i = #ANIMALS, 1, -1 do animal_step(ANIMALS[i], i, dt) end
    player_hit()
    -- animals now and then
    local d = ST.def
    G.animal_t = (G.animal_t or 12) - dt
    if G.animal_t <= 0 and #ANIMALS == 0 and (d.crab or d.bird) then G.animal_t = rr(14, 22); animal_spawn(d.crab and "crab" or "bird") end
end
G.stage_step = stage_step
local function clear_all()
    for _, t in ipairs({ BALLS, ROPES, SHOTS, ITEMS, ANIMALS }) do for i = #t, 1, -1 do t[i] = nil end end
end
G.clear_all = clear_all
local function stage_reset(n)
    clear_all()
    build_stage(n)
    for i, b in ipairs(ST.def.balls) do
        local s = b[1]; local y = (s == 4) and 18 or 16
        for _, k in ipairs(ST.blocks) do if circ_box(b[2], y, RAD[s] + 0.3, k.x0, k.y0, k.x1, k.y1) then y = 22.5 end end
        ball_new(s, b[2], y, b[3] * BVX, 0, ST.def.color)
    end
    -- spawn at the centre, unless a wall stands there (centre pillar): then just right of it
    local sx = 0
    for _, k in ipairs(ST.blocks) do if k.y0 < PH - 0.2 and sx + PHW > k.x0 and sx - PHW < k.x1 then sx = k.x1 + PHW + 0.6 end end
    P.x, P.y, P.ox, P.oy = sx, 0, sx, 0; P.st = "walk"; P.face = 1; P.shoot_t = 0; P.inv = 0; P.stun = 0
    P.weapon = "wire"; P.shield = false
    G.time = ST.def.time; G.freeze_t = 0; G.slow_t = 0; G.animal_t = 12
end
G.stage_reset = stage_reset
