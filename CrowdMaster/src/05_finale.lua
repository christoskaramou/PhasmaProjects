------------------------------------------------------------------ finales: multiplier staircase and the boss king at the castle
do
local FIN = {}
G.FIN = FIN
local STEP_SFX = 0
-- stairs ----------------------------------------------------------------------------------------
-- The crowd keeps running straight from the track onto the staircase as a narrow column: there is no
-- separate "approach" and "climb" mode any more (the old code snapped C.cz back by half the column depth
-- when it reached the first riser, then fell back into the approach branch the next frame -> the crowd
-- jittered at the bottom step for a second or two). Every unit's feet follow the step under it, so the
-- column turns into a pyramid going up. When the front passes a step, that step's cost is paid by the
-- frontmost units, who peel off and stand on it.
-- Merged reach: a unit that is paid out walks up as many steps as base pawns went into it
-- (FIN.PE: Brute = 2 pawns -> 1 step further, Giant = 2 Brutes = 4 pawns -> 3 steps further).
-- The payout (multiplier, stars, gems, chest) follows the highest step anyone actually stands on.
FIN.PE = { 1, 2, 4, 1 }
local POSE = { "0", "1", "2", "3" }
local function ground(z)
    local S = FIN.s
    if z < S.z0 then return 0 end
    return min(S.n, floor((z - S.z0) / S.d) + 1) * S.h
end
-- smooth version for the camera and the badge
function FIN.ramp(z)
    local S = FIN.s
    return clamp((z - S.z0) / S.d + 0.5, 0, S.n) * S.h
end
function FIN.stairs_start(L)
    local S = G.stairs
    FIN.s = { k = 0, top = 0, stood = {}, walk = {}, slots = {}, done = false, t = 0, cost = L.stair, p0 = C.power(),
        z0 = S.z0, d = S.d, h = S.h, n = S.n, v = max(C.speed, 2.6 * S.d), front = C.cz }
    RUN.phase = "stairs"; sfx("boss")
    C.cxt = 0; C.cy = 0
end
local function step_xyz(i, x) local S = FIN.s; return x, i * S.h, S.z0 + (i - 0.5) * S.d end
local function slot(i)
    local S = FIN.s
    local n = (S.slots[i] or 0) + 1; S.slots[i] = n
    local x = ((n - 1) % 9 - 4) * 0.9 + rr(-0.15, 0.15)
    local _, y, z = step_xyz(i, x)
    return x, y, z + clamp(-0.6 + floor((n - 1) / 9) * 0.6, -0.7, 0.7) + rr(-0.15, 0.15)
end
-- a unit leaves the column and walks to its step
local function walker(n, t, x, y, z, target, kind)
    local S = FIN.s
    local tx, _, tz = slot(target)
    S.walk[#S.walk + 1] = { n = n, t = t, col = G.T[t].col, kind = kind or ("man_" .. G.T[t].col .. "0"), x = x, y = y, z = z,
        tx = tx, tz = tz, step = target, bonus = target - S.k, ph = rand() * 4 }
end
local function pay(i)
    local S = FIN.s
    S.k = i
    -- frontmost units pay first: C.sync removes the LAST unit of a tier in C.units
    local T = G.T
    table.sort(C.units, function(a, b) local pa, pb = T[a.t].area, T[b.t].area; if pa ~= pb then return pa > pb end; return a.oz < b.oz end)
    local over = C.cnt[1] > T[1].cap
    C.damage(S.cost)
    local placed = 0
    C.sync(false, function(u)
        placed = placed + 1
        walker(u.n, u.t, C.cx + u.ox, u.y, C.cz + u.oz, min(S.n, i + FIN.PE[u.t] - 1))
    end)
    if placed == 0 and over then
        -- crowd above the visible pawn cap: the real pawns paid, show two of them stepping off
        for j = 1, 2 do
            local n = F_get("man_b0"); n:set_scale(vec3(1, 1, 1))
            walker(n, 1, rr(-1.2, 1.2), ground(S.front), S.front - rr(0, 1), i, "man_b0")
        end
    end
    sfx("step" .. min(9, floor((i - 1) / 2)))
    G.punch(1.2, 0.15)
    local _, y, z = step_xyz(i, 0)
    G.FX.ring(0, y + 0.05, z, 4, { .6, .6, .6 }, true)
    if i % 5 == 0 then
        G.FX.confetti(0, y + 1, z, 30); sfx("trophy"); G.popup("x" .. string.format("%.1f", 1 + 0.2 * i) .. "!", { 1, .85, .3, 1 }, 1)
        G.shake(0.15)
    end
end
-- a merged unit reached a step above everything paid so far
local function bonus_step(w)
    local S = FIN.s
    local best = max(S.k, S.top)
    if w.step > best then
        local _, y, z = step_xyz(w.step, 0)
        sfx("step" .. min(9, floor((w.step - 1) / 2))); G.punch(1.4, 0.18)
        G.FX.ring(0, y + 0.05, z, 4.5, { 1.2, 1, .4 }, true)
        local up = w.step - best
        G.popup_at((w.t == 3 and "Giant" or "Brute") .. " +" .. up .. (up > 1 and " Steps" or " Step"), w.x, y + 3.2, z, { 1, .85, .3, 1 }, 1.2)
        if w.step % 5 == 0 or (S.k % 5 ~= 0 and floor(w.step / 5) > floor(best / 5)) then
            G.FX.confetti(0, y + 1, z, 30); sfx("trophy")
        end
    end
    S.top = max(S.top, w.step)
end
function FIN.reach() local S = FIN.s; return S and max(S.k, S.top) or 0 end
function FIN.stairs_step(dt)
    local S = FIN.s
    S.t = S.t + dt
    -- the column: steer to the middle and keep walking at climbing pace (never snapped)
    C.cx = damp(C.cx, 0, 4, dt)
    local top_z = S.z0 + S.n * S.d + 4.5
    S.v = damp(S.v, S.done and 0 or 2.6 * S.d, 2.5, dt)
    local fz = -1e9
    for _, u in ipairs(C.units) do fz = max(fz, u.oz) end
    if fz < -1e8 then fz = 0 end
    C.cz = min(C.cz + S.v * dt, top_z - fz); C.speed = S.v
    S.front = C.cz + fz
    for _, u in ipairs(C.units) do u.y = damp(u.y, ground(C.cz + u.oz + 0.3), 16, dt) end
    if not S.done then
        while S.k < S.n and C.power() > 0 and S.front >= S.z0 + (S.k + 0.5) * S.d do pay(S.k + 1) end
        if C.power() <= 0 or S.k >= S.n then S.done = true; S.t = 0 end
    end
    -- walkers: run to their step, then stand and cheer
    for i = #S.walk, 1, -1 do
        local w = S.walk[i]
        local dx, dz = w.tx - w.x, w.tz - w.z
        local dl = sqrt(dx * dx + dz * dz)
        local sp = 6.5 * dt
        if dl <= sp then
            w.x, w.z = w.tx, w.tz; w.y = w.step * S.h
            w.n:set_position(vec3(LX(w.x), w.y, w.z)); w.n:set_rotation(vec3(0, 180, 0))
            w.n:set_mesh_ref(mesh_of("man_" .. w.col .. "c"))
            S.stood[#S.stood + 1] = { n = w.n, kind = w.kind, col = w.col, ph = rand() * 6, y = w.y }
            table.remove(S.walk, i)
            if w.t == 2 or w.t == 3 then bonus_step(w) else S.top = max(S.top, w.step) end
        else
            w.x, w.z = w.x + dx / dl * sp, w.z + dz / dl * sp
            w.y = damp(w.y, ground(w.z + 0.3 * (dz >= 0 and 1 or -1)), 16, dt)
            w.ph = w.ph + dt * 8 / G.T[w.t].s
            w.n:set_mesh_ref(mesh_of("man_" .. w.col .. POSE[floor(w.ph) % 4 + 1]))
            w.n:set_position(vec3(LX(w.x), w.y + abs(sin(w.ph * PI * 0.5)) * 0.08, w.z))
            w.n:set_rotation(vec3(6, math.deg(math.atan2(dx, dz)), 0))
        end
    end
    if S.done then
        if #S.walk > 0 then S.t = 0 end   -- the payout waits for the last climber
        if S.t > 0.4 and not S.paid then
            S.paid = true
            local k = FIN.reach()
            if k >= S.n then
                G.FX.boom(0, S.n * S.h + 1, S.z0 + S.n * S.d + 3, 1.3); G.FX.confetti(0, S.n * S.h + 3, S.z0 + S.n * S.d + 3, 60, 1.6)
                sfx("win"); G.popup("Treasure Chest!", { 1, .85, .3, 1 }, 1.5)
            end
            FIN.result = { kind = "stairs", k = k, paid = S.k, bonus = k - S.k, mult = 1 + 0.2 * k, stars = (k >= 15) and 3 or ((k >= 8) and 2 or ((k >= 1) and 1 or 0)),
                gems = (k >= 20) and 2 or ((k >= 17) and 1 or 0), left = S.p0 }
        end
        if S.paid and S.t > 1.8 then RUN.phase = "finished" end
    end
    for _, s in ipairs(S.stood) do s.ph = s.ph + dt * 4; s.n:set_mesh_ref(mesh_of("man_" .. s.col .. (floor(s.ph) % 2 == 0 and "c" or "i"))) end
end
-- where the camera and the crowd badge look during the climb
function FIN.focus()
    local S = FIN.s
    local z = S.front - 3
    if #C.units == 0 then
        local best = S.z0 + (max(FIN.reach(), 1) - 0.5) * S.d
        for _, w in ipairs(S.walk) do best = max(best, w.z) end
        z = best
    end
    return z, FIN.ramp(z)
end
function FIN.cleanup()
    if FIN.s then
        for _, s in ipairs(FIN.s.stood) do F_put(s.kind, s.n) end; FIN.s.stood = {}
        for _, w in ipairs(FIN.s.walk) do F_put(w.kind, w.n) end; FIN.s.walk = {}
    end
    if FIN.b then for _, c in ipairs(FIN.b.run) do F_put(c.kind, c.n) end; FIN.b.run = {} end
    FIN.s, FIN.b, FIN.result = nil, nil, nil
end

-- boss ------------------------------------------------------------------------------------------
function FIN.boss_build(L)
    local a = L.len + 3
    local hp = max(30, floor(L.boss * ((G.boost and G.boost.foe) or 1) + 0.5))
    local B = { z = a + 48, hp = hp, hp0 = hp, run = {}, t = 0, slam = 2.0, club = 0, acc = 0, state = "wait", fall = 0 }
    B.king = P_get("king"); B.crown = P_get("crown"); B.clubn = P_get("club")
    FIN.b = B
    FIN.boss_pose(0)
end
local KS = 4.6
function FIN.boss_pose(dt)
    local B = FIN.b
    local fall = B.fall
    local tilt = fall * 88
    local by = 0
    B.king:set_position(vec3(0, by, B.z)); B.king:set_scale(vec3(KS, KS, KS)); B.king:set_rotation(vec3(-tilt, 180, 0))
    -- crown rides on the head (rotate the offset with the topple)
    local hy, hz = 1.17 * KS, 0
    local th = math.rad(tilt)
    local cy, cz = hy * cos(th), B.z + hy * sin(th)
    B.crown:set_position(vec3(0, cy, cz)); B.crown:set_scale(vec3(KS * 1.1, KS * 1.1, KS * 1.1)); B.crown:set_rotation(vec3(-tilt, 0, 0))
    -- club in the right hand: raised behind, slams forward (toward -z, the crowd)
    local hx, hy2 = -0.2 * KS, 0.47 * KS
    local cyy, czz = hy2 * cos(th), B.z + hy2 * sin(th)
    B.clubn:set_position(vec3(hx, cyy, czz)); B.clubn:set_scale(vec3(KS * 1.5, KS * 1.5, KS * 1.5))
    B.clubn:set_rotation(vec3(-B.club - tilt, 0, 0))
end
function FIN.boss_step(dt)
    local B = FIN.b
    B.t = B.t + dt
    local front = C.cz + (C.hd or 1)
    if B.state == "wait" then
        C.cz = C.cz + 8 * dt; C.speed = 8; C.cx = damp(C.cx, 0, 3, dt)
        if front > B.z - 7 then B.state = "fight"; sfx("boss_roar"); G.shake(0.4); G.punch(5, 0.5); B.slam = 1.2 end
    elseif B.state == "fight" then
        C.speed = 0
        -- units charge the king one by one
        local rate = 10 + 0.12 * C.power()
        B.acc = B.acc + rate * dt
        while B.acc >= 1 and #C.units > 0 do
            B.acc = B.acc - 1
            -- weakest first so giants stay in the blob (they smash last and hardest)
            local pick
            for i = #C.units, 1, -1 do local u = C.units[i]; if not pick or G.T[u.t].pow < G.T[pick.t].pow then pick = u end end
            if not pick then break end
            local share = (pick.t == 1) and max(1, round(C.cnt[1] / max(1, C.vis1 or 1))) or 1
            for i, v in ipairs(C.units) do if v == pick then table.remove(C.units, i); break end end
            C.cnt[pick.t] = max(0, C.cnt[pick.t] - share); C.dirty = true
            local dmg = G.T[pick.t].pow * share * ((pick.t == 4) and (4 + G.breaker_level()) or 1)
            B.run[#B.run + 1] = { n = pick.n, kind = "man_" .. G.T[pick.t].col .. "0", col = G.T[pick.t].col, t = pick.t, x = C.cx + pick.ox, z = C.cz + pick.oz, dmg = dmg, ph = 0, tx = rr(-1.4, 1.4) }
        end
        C.sync(false)
        -- slam
        B.slam = B.slam - dt
        if B.slam < 0.45 then B.club = damp(B.club, -40, 6, dt) end
        if B.slam <= 0 then
            B.slam = 2.4; B.club = 95
            sfx("slam"); G.shake(0.55); G.punch(-3, 0.3)
            local sz = B.z - 5.5
            G.FX.dust(0, 0.3, sz, { .7, .65, .6 }, 2, 2.2); G.FX.ring(0, 0.1, sz, 7, { .8, .7, .6 }, true); G.FX.grit(0, 0.5, sz, { .6, .55, .5 }, 18)
            local i, cap = 1, max(2, floor(#C.units * 0.12 + 0.5))   -- a slam bites, never wipes
            while i <= #C.units and cap > 0 do
                local u = C.units[i]
                local dz, dx = C.cz + u.oz - sz, C.cx + u.ox
                if dx * dx + dz * dz < 3.2 * 3.2 and not (G.shield_t and G.shield_t > 0) then C.lose_unit(u, "trap", dx * 3, 8, -6); cap = cap - 1 else i = i + 1 end
            end
        else B.club = damp(B.club, (B.slam < 0.45) and -40 or 0, 3, dt) end
        if C.power() <= 0 and #B.run == 0 then RUN.phase = "dead" end
    elseif B.state == "fall" then
        B.fall = min(1, B.fall + dt * 1.2)
        if B.fall >= 1 and not B.landed then
            B.landed = true; sfx("slam"); G.shake(0.8); G.FX.dust(0, 0.3, B.z + 4, { .7, .65, .6 }, 3, 3); G.FX.boom(0, 1, B.z + 4, 1.4)
            G.FX.confetti(0, 4, B.z - 2, 80, 1.8); sfx("win")
            if G.castle_gate then G.castle_gate:set_position(HIDE) end
            local h = C.power()
            FIN.result = { kind = "boss", k = 0, mult = 2 + min(3, h / max(1, B.hp0) * 4), stars = (h > B.hp0 * 0.25) and 3 or ((h > 8) and 2 or 1), gems = 3, left = h }
        end
        if B.landed then
            B.post = (B.post or 0) + dt
            C.cz = C.cz + 4 * dt * min(1, B.post); C.speed = 4 * min(1, B.post)
            if B.post > 2.2 then RUN.phase = "finished" end
        end
    end
    -- chargers sprint, hop, and smash into the king
    for i = #B.run, 1, -1 do
        local c = B.run[i]
        c.ph = c.ph + dt
        c.z = c.z + 11 * dt; c.x = damp(c.x, c.tx, 3, dt)
        local y = abs(sin(c.ph * 9)) * 0.25
        c.n:set_position(vec3(LX(c.x), y, c.z)); c.n:set_mesh_ref(mesh_of("man_" .. c.col .. floor(c.ph * 9) % 4))
        if c.z > B.z - 1.6 then
            F_put(c.kind, c.n); table.remove(B.run, i)
            if B.state == "fight" then
                B.hp = B.hp - c.dmg
                G.FX.sparks(LX(c.x), 1.5 + rand() * 2, B.z - 1.5, 6, { 0, 2, -3 }, 5)
                if c.t == 4 or rand() < 0.3 then G.FX.puff(LX(c.x), 2, B.z - 1.5, G.TEAMRGB[c.col], 0.9); G.sfx_hit() end
                if c.t >= 2 then G.shake(0.12) end
                B.hit = 0.12
                if B.hp <= 0 then B.hp = 0; B.state = "fall"; G.punch(8, 0.7); sfx("boss"); G.popup("King Down!", { 1, .85, .3, 1 }, 1.6) end
            end
        end
    end
    if B.hit then B.hit = B.hit - dt; if B.hit <= 0 then B.hit = nil end end
    FIN.boss_pose(dt)
end
end
