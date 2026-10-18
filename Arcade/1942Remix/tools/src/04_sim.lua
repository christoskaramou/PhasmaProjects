------------------------------------------------------------------ simulation (fixed 60 Hz)
local PI2 = math.pi * 2
local SCROLL = 3.0
local P = { x = 0, y = 5, px = 0, py = 5, alive = true, inv = 0, roll = 0, rolls = 3, quad = false, esc = { false, false }, h = ALT, bank = 0 }
G.P = P
local SHOTS, BUL, EN, POWS = {}, {}, {}, {}
G.SHOTS, G.BUL, G.EN, G.POWS = SHOTS, BUL, EN, POWS
local ROLL_T = 1.6
G.ROLL_T = ROLL_T
local function inside(x, y, m) m = m or 0; return x > -FW / 2 - 6 - m and x < FW / 2 + 6 + m and y > -1 - m and y < FH + 1 + m end
local function esc_pos(i) return P.x + (i == 1 and -2.0 or 2.0), P.y - 0.4 end
G.esc_pos = esc_pos
local function circles(e)
    local hs, hc = sin(e.h), cos(e.h)
    local out = {}
    for i, c in ipairs(EK[e.kind].circles) do
        out[i] = { e.x + hc * c[1] + hs * c[2], e.y - hs * c[1] + hc * c[2], c[3] }
    end
    return out
end
G.circles = circles
------------------------------------------------------------------ spawning
local function spawn(w)
    local d = EK[w.kind]
    local e = { kind = w.kind, ai = w.ai, x = w.x, y = w.y, h = w.h, h0 = w.h, v = w.v, t = 0, hp = d.hp + (w.kind == "big" and G.k * 4 or 0),
        A = w.A, f = w.f, ly = w.ly, dir = w.dir, w = w.w, grp = w.grp, turn = 0, fired = 0, fire_t = rr(0.5, 1.8), entered = false, hit_t = 0 }
    EN[#EN + 1] = e
    if w.kind ~= "big" then G.spawned = G.spawned + 1 end
    if w.grp then G.groups[w.grp] = G.groups[w.grp] or { n = 0, k = 0 }; G.groups[w.grp].n = G.groups[w.grp].n + 1 end
    return e
end
local function fire_bullet(x, y, ang, v)
    if #BUL >= 70 or G.ceasefire > 0 then return end
    BUL[#BUL + 1] = { x = x, y = y, vx = sin(ang) * v, vy = cos(ang) * v }
end
local function aim(x, y) return math.atan2(P.x - x, P.y - y) end
------------------------------------------------------------------ enemy behaviour
local function enemy_ai(e, dt)
    local k = G.k
    e.t = e.t + dt
    local ai = e.ai
    if ai == "dive" then
        if e.y > P.y + 6 and P.alive then
            local want = clamp(aim(e.x, e.y), math.pi - 0.75, math.pi + 0.75)
            local dh = (want - e.h + math.pi) % PI2 - math.pi
            e.h = e.h + clamp(dh, -1.3 * dt, 1.3 * dt)
        end
    elseif ai == "loop" then
        if e.turn == 0 and e.y <= e.ly then e.turn = PI2 end
        if e.turn > 0 then local dh = e.v / 2.4 * dt; e.turn = max(0, e.turn - dh); e.h = e.h + e.dir * dh; if e.turn == 0 then e.turn = -1; e.h = math.pi end end
    elseif ai == "cross" then
        e.h = e.h0 + 0.35 * sin(e.t * 2.2)
    elseif ai == "swoop" then
        e.h = e.h + e.w * dt
    elseif ai == "snake" then
        e.h = e.h0 + e.A * 0.5 * sin(e.t * e.f)
    elseif ai == "rise" then
        if e.t < 11 then e.v = clamp((21 - e.y) * 0.9, 0.4, 6.5) else e.v = min(7, e.v + 3 * dt) end
        e.h = 0.15 * sin(e.t * 0.6)
    elseif ai == "sink" then
        e.h = math.pi + 0.12 * sin(e.t * 0.7)
    elseif ai == "boss" then
        if e.t < 40 then
            e.v = 0
            e.y = e.y + clamp((22 - e.y) * 0.7, -1, 3.5) * dt
            e.x = e.x + (6 * sin(e.t * 0.35) - e.x) * min(1, dt * 0.8)
            e.h = 0
        else e.v = min(9, e.v + 3 * dt) end
    end
    e.x = e.x + sin(e.h) * e.v * dt
    e.y = e.y + cos(e.h) * e.v * dt
    if ai == "boss" and e.t < 40 then e.h = 0 end
    if not e.entered and e.x > -FW / 2 - 1 and e.x < FW / 2 + 1 and e.y > 0 and e.y < FH then e.entered = true end
    -- fire
    e.fire_t = e.fire_t - dt
    if e.fire_t <= 0 and P.alive and e.y < FH - 0.5 and e.y > 1 and e.x > -FW / 2 and e.x < FW / 2 then
        local vb = 8.5 + k * 0.09
        if e.kind == "zero" or e.kind == "red" then
            local maxf = (k >= 12) and 2 or 1
            if e.fired < maxf and e.y > P.y + 3 and rand() < 0.35 + k * 0.02 then fire_bullet(e.x, e.y, aim(e.x, e.y), vb); e.fired = e.fired + 1 end
            e.fire_t = rr(0.9, 1.8)
        elseif e.kind == "mid" then
            local a = aim(e.x, e.y)
            for d = -1, 1 do fire_bullet(e.x, e.y - 0.6, a + d * 0.24, vb) end
            e.fire_t = max(0.9, 1.7 - k * 0.02)
        elseif e.kind == "big" then
            e.salvo = (e.salvo or 0) + 1
            local a = aim(e.x, e.y)
            if e.salvo % 2 == 1 then for d = -2, 2 do fire_bullet(e.x, e.y - 1.5, a + d * 0.2, vb) end
            else for _, sx in ipairs({ -3.0, 3.0 }) do local a2 = aim(e.x + sx, e.y + 0.6); for d = -1, 1 do fire_bullet(e.x + sx, e.y + 0.4, a2 + d * 0.25, vb * 0.9) end end end
            e.fire_t = max(0.7, 1.15 - k * 0.012)
        end
    end
end
------------------------------------------------------------------ hits
local function kill_enemy(e, by_player)
    e.dead = true
    local d = EK[e.kind]
    if by_player then
        add_score(d.score)
        if e.kind ~= "big" then G.killed = G.killed + 1 end
        if e.grp then
            local g = G.groups[e.grp]; g.k = g.k + 1
            if g.k >= 5 then
                G.pow_i = G.pow_i % #POWSEQ + 1
                POWS[#POWS + 1] = { x = clamp(e.x, -FW / 2 + 1, FW / 2 - 1), y = clamp(e.y, 4, FH - 2), c = POWSEQ[G.pow_i], t = 0 }
                G.banner_set("Formation Destroyed", 1.0)
            end
        end
    end
    if e.kind == "big" then
        sfx("boom_l"); G.shake = 1.4
        for i = 1, 6 do G.later(i * 0.18, function() explode(e.x + rr(-4, 4), e.y + rr(-2, 2), 2.2) end) end
        explode(e.x, e.y, 3)
        G.boss_done = true
    elseif e.kind == "mid" then sfx("boom_l"); explode(e.x, e.y, 2.0); G.shake = max(G.shake, 0.7)
    else sfx("boom_s"); explode(e.x, e.y, 1.0) end
end
G.kill_enemy = kill_enemy
local function damage(e, n)
    e.hp = e.hp - n; e.hit_t = 0.08
    if e.hp <= 0 then kill_enemy(e, true) else sfx("hit") end
end
local function player_die()
    if not P.alive then return end
    P.alive = false; P.dead_t = 2.4; P.quad = false; P.esc = { false, false }
    explode(P.x, P.y, 1.8); sfx("death"); G.shake = 1.0
    G.lives = G.lives - 1
end
G.player_die = player_die
local function lose_escort(i)
    P.esc[i] = false
    local x, y = esc_pos(i); explode(x, y, 1.0); sfx("boom_s")
end
local function seg_circle(x, y0, y1, c)
    local dx = x - c[1]
    if abs(dx) > c[3] then return false end
    local hh = sqrt(c[3] * c[3] - dx * dx)
    return max(y0, y1) >= c[2] - hh and min(y0, y1) <= c[2] + hh
end
------------------------------------------------------------------ player
local function fire_volley()
    local n = 0
    for _, s in ipairs(SHOTS) do if s.lead then n = n + 1 end end
    if n >= 3 then return end
    local xs = P.quad and { -0.62, -0.22, 0.22, 0.62 } or { -0.24, 0.24 }
    for i, dx in ipairs(xs) do SHOTS[#SHOTS + 1] = { x = P.x + dx, y = P.y + 0.7, py = P.y + 0.7, lead = (i == 1) } end
    for i = 1, 2 do if P.esc[i] then local ex, ey = esc_pos(i); SHOTS[#SHOTS + 1] = { x = ex, y = ey + 0.5, py = ey + 0.5 } end end
    sfx("shot")
end
local function player_step(inp, dt)
    P.px, P.py = P.x, P.y
    if not P.alive then
        P.dead_t = P.dead_t - dt
        if P.dead_t <= 0 then
            if G.lives < 0 then G.out_of_lives = true; return end
            P.alive = true; P.x, P.y = 0, 5; P.px, P.py = P.x, P.y; P.inv = 2.5; P.roll = 0
            for i = #BUL, 1, -1 do BUL[i] = nil end
        end
        return
    end
    P.inv = max(0, P.inv - dt)
    local mx, my = inp.mx, inp.my
    local l = sqrt(mx * mx + my * my); if l > 1 then mx, my = mx / l, my / l end
    local spd = 12.5
    P.x = clamp(P.x + mx * spd * dt, -FW / 2 + 1.1, FW / 2 - 1.1)
    P.y = clamp(P.y + my * spd * dt, 1.6, FH - 3)
    P.bank = damp(P.bank, mx * 28, 10, dt)
    if P.roll > 0 then
        P.roll = max(0, P.roll - dt)
    else
        if inp.roll and P.rolls > 0 then P.roll = ROLL_T; P.rolls = P.rolls - 1; sfx("roll")
        elseif inp.fire then fire_volley() end
    end
end
------------------------------------------------------------------ stage flow
G.later_q = {}
function G.later(d, f) G.later_q[#G.later_q + 1] = { t = d, f = f } end
local function clear_field()
    for _, t in ipairs({ SHOTS, BUL, EN, POWS }) do for i = #t, 1, -1 do t[i] = nil end end
end
local function start_stage(k)
    G.k = k; G.num = 33 - k
    clear_field()
    G.waves, G.T = G.build_waves(k); G.wi = 1; G.st = 0
    G.spawned, G.killed, G.groups = 0, 0, {}
    G.boss_done = not G.is_boss(G.num); G.boss_spawned = false
    G.ceasefire = 0
    P.rolls = 3; P.roll = 0; P.inv = 0; P.alive = true
    P.x, P.y, P.px, P.py = 0, 3.2, 0, 3.2
    G.phase = "takeoff"; G.pt = 0
    G.carrier = { y = 12.5, on = true }
    G.banner_set(string.format("Stage %d  ·  %s", G.num, G.stage_name(G.num)), 2.6)
    sfx("start")
    G.music_after = 3.0
end
G.start_stage = start_stage
local function new_game()
    G.score = 0; G.lives = 2; G.next_extra = 20000; G.out_of_lives = false; G.won = false
    P.quad = false; P.esc = { false, false }; G.pow_i = 0
    start_stage(1)
end
G.new_game_sim = new_game
local function apply_pow(c)
    sfx("pow")
    if c == "red" then P.quad = true; G.banner_set("Quad Guns", 1.4)
    elseif c == "green" then P.esc = { true, true }; G.banner_set("Side Fighters", 1.4)
    elseif c == "gray" then P.rolls = P.rolls + 1; G.banner_set("Extra Loop", 1.4)
    elseif c == "yellow" then G.ceasefire = 10; for i = #BUL, 1, -1 do BUL[i] = nil end; G.banner_set("Enemy Fire Stopped", 1.4)
    elseif c == "orange" then add_score(1000); G.banner_set("1000 Points", 1.4)
    elseif c == "white" then
        sfx("kill_all"); G.shake = 1.0; G.banner_set("Enemies Destroyed", 1.4)
        for _, e in ipairs(EN) do
            if not e.dead and e.entered then
                if e.kind == "big" then damage(e, 40) else kill_enemy(e, true) end
            end
        end
        for i = #BUL, 1, -1 do BUL[i] = nil end
    end
end
local function stage_step(inp, dt)
    G.pt = G.pt + dt
    G.scroll = (G.scroll or 0) + SCROLL * dt
    G.ceasefire = max(0, G.ceasefire - dt)
    for i = #G.later_q, 1, -1 do local q = G.later_q[i]; q.t = q.t - dt; if q.t <= 0 then table.remove(G.later_q, i); q.f() end end
    if G.carrier.on then G.carrier.y = G.carrier.y - SCROLL * dt * ((G.phase == "landing") and 0 or 1) end
    local ph = G.phase
    if ph == "takeoff" then
        local u = clamp(G.pt / 3.0, 0, 1)
        P.px, P.py = P.x, P.y
        P.y = 3.2 + u * u * 3.0
        P.h = 1.55 + (ALT - 1.55) * clamp((G.pt - 0.8) / 2.2, 0, 1) ^ 1.5
        if G.pt >= 3.0 then G.phase = "fly"; G.pt = 0; P.h = ALT; music("bgm") end
        return
    end
    if ph == "landing" then
        local c = G.carrier
        if c.y > 12 then c.y = max(12, c.y - 7 * dt) end
        P.px, P.py = P.x, P.y
        local ty = c.y - 6
        P.x = P.x + (0 - P.x) * min(1, dt * 1.6)
        P.y = P.y + (ty - P.y) * min(1, dt * 1.4)
        if c.y <= 12.01 then P.h = max(1.55, P.h - dt * 1.6) end
        P.bank = damp(P.bank, 0, 6, dt)
        if P.h <= 1.56 and G.pt > 3.5 then
            G.phase = "result"; G.pt = 0
            local rate = (G.spawned > 0) and (G.killed / G.spawned) or 0
            G.rate = rate
            G.bonus = (rate >= 0.999) and 20000 or floor(rate * 100) * 100
            add_score(G.bonus); sfx("clear"); music(nil)
        end
        for _, s in ipairs(SHOTS) do s.py = s.y; s.y = s.y + 46 * dt end
        for i = #SHOTS, 1, -1 do if SHOTS[i].y > FH + 2 then table.remove(SHOTS, i) end end
        return
    end
    if ph == "result" then
        if G.pt > 4.0 then
            if G.k >= 32 then G.won = true; G.phase = "won"; G.pt = 0; music("ending")
            else start_stage(G.k + 1) end
        end
        return
    end
    -- fly
    G.st = G.st + dt
    while G.waves[G.wi] and G.waves[G.wi].t <= G.st do spawn(G.waves[G.wi]); G.wi = G.wi + 1 end
    if not G.boss_spawned and not G.boss_done and G.st > G.T + 2 then
        G.boss_spawned = true
        spawn({ kind = "big", ai = "boss", x = 0, y = -7, h = 0, v = 0 })
        sfx("warn"); music("boss"); G.banner_set("Warning: Heavy Bomber Ayako", 2.4)
    end
    player_step(inp, dt)
    if G.out_of_lives then return end
    -- shots (swept along their path this step)
    for i = #SHOTS, 1, -1 do
        local s = SHOTS[i]
        s.py = s.y; s.y = s.y + 46 * dt
        local hit = false
        for _, e in ipairs(EN) do
            if not e.dead and e.entered then
                for _, c in ipairs(circles(e)) do
                    if seg_circle(s.x, s.py, s.y, c) then hit = true; break end
                end
                if hit then damage(e, 1); puff(s.x, s.y, { 1.6, 1.2, .6 }, 5); break end
            end
        end
        if hit or s.y > FH + 1 then table.remove(SHOTS, i) end
    end
    -- enemies
    for _, e in ipairs(EN) do
        if not e.dead then
            enemy_ai(e, dt)
            e.hit_t = max(0, e.hit_t - dt)
            if e.entered and (e.y < -6 or e.y > FH + 9 or abs(e.x) > FW / 2 + 9) then e.dead = true; e.gone = true end
            if e.kind == "big" and e.y > FH + 8 then G.boss_done = true end
            -- body contact
            if P.alive and P.roll <= 0 and P.inv <= 0 and not e.dead and e.entered then
                for _, c in ipairs(circles(e)) do
                    local dx, dy = c[1] - P.x, c[2] - P.y
                    if dx * dx + dy * dy < (c[3] + 0.36) ^ 2 then
                        player_die(); if e.kind == "zero" or e.kind == "red" then kill_enemy(e, true) end; break
                    end
                end
                for ei = 1, 2 do
                    if P.esc[ei] and not e.dead then
                        local ex, ey = esc_pos(ei)
                        for _, c in ipairs(circles(e)) do
                            local dx, dy = c[1] - ex, c[2] - ey
                            if dx * dx + dy * dy < (c[3] + 0.3) ^ 2 then lose_escort(ei); if e.kind == "zero" or e.kind == "red" then kill_enemy(e, true) end; break end
                        end
                    end
                end
            end
        end
    end
    for i = #EN, 1, -1 do if EN[i].dead then table.remove(EN, i) end end
    -- enemy bullets
    for i = #BUL, 1, -1 do
        local b = BUL[i]
        b.x = b.x + b.vx * dt; b.y = b.y + b.vy * dt
        local gone = not inside(b.x, b.y, 1)
        if not gone and P.alive and P.roll <= 0 and P.inv <= 0 then
            local dx, dy = b.x - P.x, b.y - P.y
            if dx * dx + dy * dy < 0.53 * 0.53 then player_die(); gone = true end
            for ei = 1, 2 do
                if not gone and P.esc[ei] then
                    local ex, ey = esc_pos(ei); dx, dy = b.x - ex, b.y - ey
                    if dx * dx + dy * dy < 0.47 * 0.47 then lose_escort(ei); gone = true end
                end
            end
        end
        if gone then table.remove(BUL, i) end
    end
    -- POWs drift down
    for i = #POWS, 1, -1 do
        local w = POWS[i]
        w.t = w.t + dt; w.y = w.y - 1.4 * dt; w.x = w.x + 0.8 * cos(w.t * 1.6) * dt
        local dx, dy = w.x - P.x, w.y - P.y
        if P.alive and dx * dx + dy * dy < 1.25 * 1.25 then apply_pow(w.c); table.remove(POWS, i)
        elseif w.y < -2 then table.remove(POWS, i) end
    end
    -- end of stage: all waves out, boss gone, field quiet -> carrier
    if G.wi > #G.waves and G.boss_done and P.alive then
        local busy = false
        for _, e in ipairs(EN) do if e.entered and e.kind ~= "zero" and e.kind ~= "red" then busy = true end end
        if not busy and #EN <= 2 then
            G.quiet = (G.quiet or 0) + dt
            if G.quiet > 2.5 then
                G.quiet = 0
                G.phase = "landing"; G.pt = 0
                G.carrier = { y = FH + 16, on = true }
                for j = #EN, 1, -1 do EN[j] = nil end
                for j = #BUL, 1, -1 do BUL[j] = nil end
                P.roll = 0
                G.banner_set("Landing", 1.5)
            end
        else G.quiet = 0 end
    end
end
G.stage_step = stage_step
