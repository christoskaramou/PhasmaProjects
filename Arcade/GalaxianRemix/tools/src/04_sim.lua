------------------------------------------------------------------ simulation (fixed 60 Hz steps)
local P = { x = 0, y = PY, vx = 0, alive = true, shot = nil }
G.P = P
G.A, G.BOMBS = {}, {}
G.form = { x = 0, vx = 0.8 }
G.wave, G.ships, G.phase, G.pt = 1, 2, "start", 0
local DIVE_STATES = { peel = true, dive = true, escort = true }
local function wave_k() return min(G.wave - 1, 8) end
local function dive_speed() return 6.0 + 0.35 * wave_k() end
local function add_score(n)
    local before = G.score
    G.score = G.score + n
    if before < 7000 and G.score >= 7000 then G.ships = G.ships + 1; sfx("extra"); G.banner_set("Extra Galaxip", 1.6) end
end
local function start_wave()
    G.A = {}
    for r, row in ipairs(ROWS) do
        for _, c in ipairs(row.cols) do
            G.A[#G.A + 1] = { k = row.k, row = r, col = c, x = slot_x(c) + G.form.x, y = slot_y(r), st = "form", t = 0, vx = 0, vy = 0, ang = 180,
                alive = true, grow = -(6 - r) * 0.07 - c * 0.012 }
        end
    end
    G.BOMBS = {}; P.shot = nil
    G.dive_t = 3.0; G.side = 1
end
function G.new_game_sim()
    G.score = 0; G.ships = 2; G.wave = 1; G.form.x = 0; G.form.vx = 0.8
    P.x = 0; P.vx = 0; P.alive = true; P.shot = nil
    start_wave()
    G.phase = "start"; G.pt = 0; G.out = false; G.POPS = {}
end
local function alive_count() local n = 0; for _, a in ipairs(G.A) do if a.alive then n = n + 1 end end; return n end
G.alive_count = alive_count
local function divers() local n = 0; for _, a in ipairs(G.A) do if a.alive and a.st ~= "form" then n = n + 1 end end; return n end
------------------------------------------------------------------ dives
local function launch(a, side)
    a.st = "peel"; a.t = 0; a.x0, a.y0 = a.x, a.y
    a.side = side or ((a.x < G.form.x) and -1 or 1)
    a.bombs = min(4, 2 + floor(G.wave / 3)); a.bomb_t = rr(0.25, 0.7); a.vx = 0
    a.weave = rr(0, 6)
    sfx("dive")
end
local function launch_convoy(f)
    launch(f)
    f.esc = {}
    local reds = {}
    for _, a in ipairs(G.A) do if a.alive and a.st == "form" and a.k == "red" and abs(a.col - f.col) <= 1 then reds[#reds + 1] = a end end
    table.sort(reds, function(p, q) return abs(p.col - f.col) < abs(q.col - f.col) end)
    for i = 1, min(2, #reds) do
        local r = reds[i]
        r.st = "escort"; r.leader = f; r.t = 0
        local s = (r.col < f.col) and -1 or ((r.col > f.col) and 1 or (#f.esc == 0 and -1 or 1))
        if #f.esc == 1 and f.esc[1].ox == s * 0.85 then s = -s end
        r.ox, r.oy = s * 0.85, 0.7
        r.bombs = f.bombs; r.bomb_t = rr(0.4, 0.9)
        f.esc[#f.esc + 1] = r
    end
    f.esc_n = #f.esc
end
G.launch_convoy = launch_convoy
-- the arcade launches divers from the edges of the convoy, alternating sides
local function schedule(dt)
    if not ((G.phase == "play" and P.alive) or G.phase == "attract") then return end
    G.dive_t = G.dive_t - dt
    if G.dive_t > 0 then return end
    local cap = min(7, 2 + G.wave)
    G.dive_t = max(0.7, 2.6 - 0.18 * wave_k()) * rr(0.7, 1.3)
    if divers() >= cap then return end
    -- flagship convoy now and then
    if rand() < 0.22 then
        local fl = {}
        for _, a in ipairs(G.A) do if a.alive and a.st == "form" and a.k == "flag" then fl[#fl + 1] = a end end
        if #fl > 0 then launch_convoy(fl[floor(rand() * #fl) + 1]); return end
    end
    G.side = -G.side
    local best, cand = nil, {}
    for _, a in ipairs(G.A) do
        if a.alive and a.st == "form" and a.k ~= "flag" then
            local e = (a.col - 4.5) * G.side
            if not best or e > best + 0.5 then best = e; cand = { a } elseif abs(e - best) <= 0.5 then cand[#cand + 1] = a end
        end
    end
    if #cand == 0 then
        -- only flagships remain in formation: they dive alone
        for _, a in ipairs(G.A) do if a.alive and a.st == "form" then launch(a); a.esc_n = 0; a.esc = {}; return end end
        return
    end
    local a = cand[floor(rand() * #cand) + 1]
    launch(a, G.side)
    -- from wave 3, drones sometimes peel off in pairs
    if G.wave >= 3 and a.k == "drone" and rand() < 0.3 then
        for _, b in ipairs(cand) do if b ~= a and b.st == "form" then launch(b, G.side); break end end
    end
end
local function drop_bomb(a)
    if a.bombs <= 0 or not P.alive then return end
    a.bomb_t = a.bomb_t - FR
    if a.bomb_t > 0 or a.y > 15 or a.y < PY + 4 or abs(a.x - P.x) > 5 then return end
    a.bombs = a.bombs - 1; a.bomb_t = rr(0.3, 0.75) - 0.02 * wave_k()
    G.BOMBS[#G.BOMBS + 1] = { x = a.x, y = a.y - 0.4, py = a.y - 0.4, vx = a.vx * 0.25, vy = -(10 + 0.4 * wave_k()) }
    sfx("bomb")
end
local function heading(vx, vy) return math.deg(atan2(-vx, vy)) end
local function wrap(a)
    a.y = TOPY; a.x = clamp(a.x, -XMAX, XMAX); a.vx = 0
    if alive_count() <= 4 and P.alive and G.phase == "play" then
        -- the last few aliens keep attacking without going home
        a.st = "dive"; a.vy = -dive_speed(); a.bombs = min(4, 2 + floor(G.wave / 3)); a.bomb_t = rr(0.3, 0.8)
    else a.st = "return" end
end
local function step_alien(a, dt)
    a.t = a.t + dt
    if a.grow < 1 then a.grow = min(1, a.grow + dt * 2.2) end
    local sx, sy = slot_x(a.col) + G.form.x, slot_y(a.row)
    if a.st == "form" then
        a.x, a.y, a.ang = sx, sy, 180
    elseif a.st == "peel" then
        -- loop up and outward off the end of the convoy, then turn down toward the Galaxip
        local u = min(1, a.t / 0.6); local th = PI * u; local R = 0.9
        a.x = a.x0 + a.side * R * (1 - cos(th)); a.y = a.y0 + R * sin(th)
        a.ang = heading(a.side * sin(th), cos(th))
        if u >= 1 then a.st = "dive"; a.vx = a.side * 1.5; a.vy = -dive_speed() end
    elseif a.st == "dive" then
        if a.y > PY + 3 then
            local tx = P.alive and P.x or a.x
            if a.k == "drone" or a.k == "purple" then tx = tx + sin(a.t * 2.6 + a.weave) * 1.4 end
            a.vx = clamp(a.vx + clamp((tx - a.x) * 2.4, -9, 9) * dt, -4.5, 4.5)
        end
        a.x = a.x + a.vx * dt; a.y = a.y + a.vy * dt
        if abs(a.x) > XMAX + 0.6 then a.x = clamp(a.x, -XMAX - 0.6, XMAX + 0.6); a.vx = -a.vx * 0.5 end
        a.ang = heading(a.vx, a.vy)
        drop_bomb(a)
        if a.y < -1.5 then wrap(a) end
    elseif a.st == "escort" then
        local L = a.leader
        if not L or not L.alive then a.st = "dive"; a.vx = L and L.vx or 0; a.vy = -dive_speed(); a.leader = nil
        elseif L.st == "return" or L.st == "form" then a.st = "return"; a.leader = nil
        else
            a.x = L.x + a.ox; a.y = L.y + a.oy
            a.vx, a.vy, a.ang = L.vx or 0, L.vy or 0, L.ang
            drop_bomb(a)
        end
    elseif a.st == "return" then
        local dx, dy = sx - a.x, sy - a.y
        local d = sqrt(dx * dx + dy * dy)
        local sp = 7 * dt
        if d <= sp + 0.02 then a.st = "form"; a.x, a.y, a.ang = sx, sy, 180; a.esc = nil
        else a.x = a.x + dx / d * sp; a.y = a.y + dy / d * sp; a.ang = heading(dx / d, dy / d) end
    end
end
------------------------------------------------------------------ hits
local function kill(a, by_ship)
    a.alive = false
    local pts
    if a.st == "form" then pts = PTS_FORM[a.k]
    elseif a.k == "flag" then
        local total, killed = a.esc_n or 0, 0
        for _, e in ipairs(a.esc or {}) do if not e.alive then killed = killed + 1 end end
        pts = (total == 2 and killed == 2) and 800 or (total == 2 and 300) or (total == 1 and 200) or 150
        popup(a.x, a.y, pts)
    else pts = PTS_DIVE[a.k] end
    add_score(pts)
    G.pop(WP(a.x, a.y, 0.3), COLS[a.k], a.k == "flag")
    sfx(a.k == "flag" and "hit_flag" or "hit")
    if a.k == "flag" or a.st ~= "form" then G.shake = max(G.shake, a.k == "flag" and 0.35 or 0.15) end
end
local function ship_die()
    if not P.alive then return end
    P.alive = false; P.shot = nil
    G.ship_boom(WP(P.x, P.y, 0.3)); sfx("pdie"); G.shake = 0.8
    G.phase = "dead"; G.pt = 0
end
local function overlap(ax, ay, ah, bx, by, bh) return abs(ax - bx) < ah[1] + bh[1] and abs(ay - by) < ah[2] + bh[2] end
------------------------------------------------------------------ one step
function G.step(inp, dt)
    G.pt = G.pt + dt
    -- convoy sway between the walls (bounded by the outermost living columns)
    local lo, hi = 9, 0
    for _, a in ipairs(G.A) do if a.alive then lo = min(lo, a.col); hi = max(hi, a.col) end end
    if lo <= hi then
        local f = G.form
        f.x = f.x + f.vx * dt
        if slot_x(lo) + f.x < -XMAX + 0.2 and f.vx < 0 then f.vx = -f.vx end
        if slot_x(hi) + f.x > XMAX - 0.2 and f.vx > 0 then f.vx = -f.vx end
    end
    -- the Galaxip
    if P.alive then
        local v = clamp(inp.mx or 0, -1, 1) * 7.5
        local nx = clamp(P.x + v * dt + (inp.mdx or 0), -XMAX, XMAX)
        P.vx = damp(P.vx, (nx - P.x) / dt, 12, dt); P.x = nx
        if inp.fire and not P.shot and (G.phase == "play" or G.phase == "clear" or G.phase == "start") then
            P.shot = { x = P.x, y = PY + 0.62 * SS, py = PY + 0.62 * SS }; sfx("shot")
        end
    end
    -- the missile: swept from last to new position, hits the lowest alien whose box it crosses
    local s = P.shot
    if s then
        s.py = s.y; s.y = s.y + 30 * dt
        local hit, hy = nil, 1e9
        for _, a in ipairs(G.A) do
            if a.alive and a.grow >= 1 then
                local hb = HB[a.k]
                if abs(s.x - a.x) < hb[1] + 0.04 and s.y + 0.14 >= a.y - hb[2] and s.py - 0.18 <= a.y + hb[2] and a.y < hy then hit, hy = a, a.y end
            end
        end
        if hit then kill(hit, false); P.shot = nil elseif s.y > TOPY then P.shot = nil end
    end
    schedule(dt)
    for _, a in ipairs(G.A) do if a.alive then step_alien(a, dt) end end
    -- divers colliding with the Galaxip destroy both (you still get the points)
    if P.alive then
        for _, a in ipairs(G.A) do
            if a.alive and a.st ~= "form" and overlap(P.x, P.y, SHIP_HB, a.x, a.y, HB[a.k]) then kill(a, true); ship_die(); break end
        end
    end
    -- bombs (swept against the Galaxip)
    for i = #G.BOMBS, 1, -1 do
        local b = G.BOMBS[i]
        b.py = b.y; b.x = b.x + b.vx * dt; b.y = b.y + b.vy * dt
        if P.alive and abs(b.x - P.x) < SHIP_HB[1] + 0.05 and b.y - 0.16 <= P.y + SHIP_HB[2] and b.py + 0.12 >= P.y - SHIP_HB[2] then
            table.remove(G.BOMBS, i); ship_die()
        elseif b.y < -1 then table.remove(G.BOMBS, i) end
    end
    -- phases
    if G.phase == "start" then
        if G.pt > 2.0 then G.phase = "play"; G.pt = 0 end
    elseif G.phase == "play" then
        if alive_count() == 0 then G.phase = "clear"; G.pt = 0; sfx("wave"); G.banner_set("Convoy Destroyed", 1.8) end
    elseif G.phase == "clear" then
        if G.pt > 2.2 then
            G.wave = G.wave + 1; start_wave(); G.phase = "play"; G.pt = 0
            G.banner_set("Wave " .. G.wave, 1.4)
        end
    elseif G.phase == "dead" then
        -- wait until every attacker has gone home and the bombs have cleared, as in the arcade
        if G.pt > 2.5 and divers() == 0 and #G.BOMBS == 0 then
            if alive_count() == 0 then G.wave = G.wave + 1; start_wave() end
            if G.ships > 0 then
                G.ships = G.ships - 1; P.alive = true; P.x = 0; P.vx = 0
                G.phase = "start"; G.pt = 0.8; G.dive_t = 2.0
            else G.out = true end
        end
    end
    for i = #G.POPS, 1, -1 do local p = G.POPS[i]; p.t = p.t + dt; if p.t > 1.4 then table.remove(G.POPS, i) end end
end
