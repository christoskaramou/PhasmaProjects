------------------------------------------------------------------ heroes (arcade stats: armour, shot power, melee, speed, magic)
local HEROES = {
    { id = "war", name = "Warrior", hero = "Thor", armor = 0.8, shot = 3, melee = 4, speed = 3.4, magic = 1, shotm = "p_axe", sv = 9 },
    { id = "val", name = "Valkyrie", hero = "Thyra", armor = 0.6, shot = 2, melee = 3, speed = 3.8, magic = 2, shotm = "p_sword", sv = 10 },
    { id = "wiz", name = "Wizard", hero = "Merlin", armor = 1.0, shot = 2, melee = 1, speed = 3.8, magic = 3, shotm = "p_fire", sv = 10 },
    { id = "elf", name = "Elf", hero = "Questor", armor = 0.9, shot = 1, melee = 2, speed = 4.6, magic = 2, shotm = "p_arrow", sv = 13 },
}
G.HEROES = HEROES
local PR = 0.29                  -- hero radius (rounded collider, slightly inside the model so corners don't snag)
local MR = 0.3                   -- monster radius
local P = { x = 2, y = 2, fx = 0, fy = 1, hero = 1, alive = true }
G.P = P; G.PR, G.MR = PR, MR
G.MON, G.SHOTS, G.ESHOT, G.GENS, G.ITEMS = {}, {}, {}, {}, {}
local MAP, LW, LH
-- solid test for a cell (walls, closed doors, generators)
local function cell(i, j) if i < 0 or j < 0 or i >= LW or j >= LH then return "#" end; return MAP[j * LW + i + 1] end
local function solid(i, j) local c = cell(i, j); return c == "#" or c == "D" or c == "G" or c == "w" end
G.cell, G.solid = cell, solid
local function setc(i, j, v) MAP[j * LW + i + 1] = v end
-- circle vs grid: does a circle at (x, y) overlap any solid cell?
local function blocked(x, y, r)
    for j = floor(y - r), floor(y + r) do for i = floor(x - r), floor(x + r) do
        if solid(i, j) then
            local qx, qy = clamp(x, i, i + 1), clamp(y, j, j + 1)
            if (x - qx) ^ 2 + (y - qy) ^ 2 < r * r then return true end
        end
    end end
    return false
end
G.blocked = blocked
-- render interpolation between fixed 60 Hz steps (prev position stored at the start of each step)
function G.lerp_pos(e)
    local ox, oy = e.ox, e.oy
    if not ox or abs(e.x - ox) > 1.5 or abs(e.y - oy) > 1.5 then return e.x, e.y end
    return ox + (e.x - ox) * AL, oy + (e.y - oy) * AL
end
-- hero movement with corner assist: when the hero is blocked on one axis and the player isn't steering on the other,
-- look sideways (up to NUDGE) for a spot where the way ahead is open and slide toward it at walking speed.
local NUDGE = 0.45
local function nudge(e, axis, d, sp, r)
    for k = 1, 15 do
        local o = k * 0.03
        for _, sg in ipairs({ 1, -1 }) do
            local tx, ty = e.x, e.y
            if axis == "x" then tx = tx + o * sg else ty = ty + o * sg end
            local fx, fy = tx, ty
            if axis == "x" then fy = fy + d else fx = fx + d end
            if not blocked(tx, ty, r) and not blocked(fx, fy, r) then
                local step = min(o, sp * 0.9) * sg
                if axis == "x" then if not blocked(e.x + step, e.y, r) then e.x = e.x + step end
                else if not blocked(e.x, e.y + step, r) then e.y = e.y + step end end
                -- keep some forward progress once we're nearly through
                if o <= sp then
                    if axis == "x" then if not blocked(e.x, e.y + d * 0.5, r) then e.y = e.y + d * 0.5 end
                    else if not blocked(e.x + d * 0.5, e.y, r) then e.x = e.x + d * 0.5 end end
                end
                return true
            end
        end
    end
    return false
end
local function hero_move(e, dx, dy, r)
    local bx = dx ~= 0 and blocked(e.x + dx, e.y, r)
    if dx ~= 0 and not bx then e.x = e.x + dx end
    local by = dy ~= 0 and blocked(e.x, e.y + dy, r)
    if dy ~= 0 and not by then e.y = e.y + dy end
    local sp = math.max(abs(dx), abs(dy))
    if by and dx == 0 then nudge(e, "x", dy, sp, r) end
    if bx and dy == 0 then nudge(e, "y", dx, sp, r) end
    -- diagonal into a wall edge: the open axis already slides; if both are blocked, try each axis alone with a nudge
    if bx and by then if not nudge(e, "x", dy, sp * 0.7, r) then nudge(e, "y", dx, sp * 0.7, r) end end
    G.nudge_dbg = (by and dx == 0) or (bx and dy == 0) or (bx and by)
end
-- move with per-axis sliding: a diagonal into a wall still slides along whichever axis is open
local function move(e, dx, dy, r)
    local hit = false
    if dx ~= 0 then if not blocked(e.x + dx, e.y, r) then e.x = e.x + dx else hit = true end end
    if dy ~= 0 then if not blocked(e.x, e.y + dy, r) then e.y = e.y + dy else hit = true end end
    return hit
end
------------------------------------------------------------------ level load
local function load_level(n)
    G.level = n; G.load_id = (G.load_id or 0) + 1      -- the renderer re-dresses the floor on every load
    local L = G.LEVELS[(n - 1) % #G.LEVELS + 1]
    G.L = L; G.li = (n - 1) % #G.LEVELS + 1
    LW, LH = L.w, L.h; MAP = {}
    G.MON, G.SHOTS, G.ESHOT, G.GENS, G.ITEMS, G.DOORS = {}, {}, {}, {}, {}, {}
    G.EXITS, G.TRAPS, G.STUNS = {}, {}, {}
    G.exit = nil; G.trapped = false; P.stun, P.stun_cd = 0, 0
    G.tough = floor((n - 1) / #G.LEVELS)            -- later loops: tougher monsters
    G.ttime = (L.treasure and G.tough == 0) and L.treasure or (L.treasure and max(18, L.treasure - 4 * G.tough)) or nil
    for r, row in ipairs(L.rows) do
        local j = LH - r
        for i = 0, LW - 1 do
            local ch = row:sub(i + 1, i + 1)
            local base = (ch == "#" or ch == "D" or ch == "w") and ch or "."
            MAP[j * LW + i + 1] = base
            local x, y = i + 0.5, j + 0.5
            if ch == "S" then P.x, P.y = x, y
            elseif ch == "D" then G.DOORS[#G.DOORS + 1] = { i = i, j = j, open = 0 }
            elseif ch == "E" then G.exit = { x = x, y = y, to = n + 1 }; G.EXITS[#G.EXITS + 1] = G.exit
            elseif ch == "X" then G.EXITS[#G.EXITS + 1] = { x = x, y = y, to = n + max(2, L.jump or 2), jump = true }
            elseif ch == "T" then G.TRAPS[#G.TRAPS + 1] = { x = x, y = y }
            elseif ch == "z" then G.STUNS[#G.STUNS + 1] = { x = x, y = y, t = 0 }
            elseif ch == "k" or ch == "f" or ch == "p" or ch == "t" then G.ITEMS[#G.ITEMS + 1] = { k = ch, x = x, y = y, alive = true }
            elseif ch:match("[gGrdls]") then
                local kind = ({ g = "ghost", r = "grunt", d = "demon", l = "lobber", s = "sorc" })[ch:lower()]
                local lv = min(3, 1 + floor((i * 7 + j * 3) % 3) + G.tough)
                G.GENS[#G.GENS + 1] = { kind = kind, lv = lv, hp = lv * 3, i = i, j = j, x = x, y = y, t = rr(0.5, 2.5), alive = true, flash = 0 }
                MAP[j * LW + i + 1] = "G"
            end
        end
    end
    G.LW, G.LH = LW, LH
    G.death_t = (not L.treasure and (n >= 6 or G.tough > 0)) and max(12, 25 - 4 * G.tough) or nil
    P.fx, P.fy = 0, 1
    P.ox, P.oy = nil, nil
    G.phase = "play"; G.pt = 0
    G.next_level = n + 1
    G.banner_set((L.treasure and (L.name .. "  ·  Grab the gold!") or ("Level " .. n)) .. (G.tough > 0 and ("  ·  Round " .. (G.tough + 1)) or ""), 2.2)
end
G.load_level = load_level
function G.new_game_sim(hero)
    P.hero = hero or P.hero or 1
    G.score = 0; G.health = 2000; G.keys = 0; G.potions = 0; G.won = false; G.out = false
    P.alive = true; G.warned = false
    load_level(1)
end
local function H() return HEROES[P.hero] end
G.H = H
------------------------------------------------------------------ damage, pickups, potions
local function hurt(n)
    if not P.alive then return end
    G.health = G.health - n * H().armor
    G.hurt_t = 0.15
    if G.health <= 0 then G.health = 0; P.alive = false; G.phase = "dead"; G.pt = 0; sfx("die"); G.puff(WP(P.x, P.y, 0.4), { 1, .3, .2 }, 30) end
end
G.hurt = hurt
local PTS = { ghost = 10, grunt = 10, demon = 20, lobber = 20, sorc = 30, death = 1000 }
local function kill_mon(m, by)
    m.alive = false
    add_score(PTS[m.kind] * m.lv)
    sfx("kill"); G.puff(WP(m.x, m.y, 0.4), m.kind == "ghost" and { .8, .85, .95 } or { .6, .5, .4 }, 12)
end
local function hit_gen(g, dmg)
    g.hp = g.hp - dmg; g.flash = 1
    if g.hp <= 0 then
        g.alive = false; setc(g.i, g.j, "."); add_score(100 * g.lv); sfx("gen"); G.boom(WP(g.x, g.y, 0.4), false)
    else
        sfx("hit")
        g.lv = max(1, min(g.lv, math.ceil(g.hp / 3)))   -- damaged generators drop a level, like the arcade
    end
end
-- potion: everything on screen (and Death) is destroyed, generators take a heavy hit
local function smart_bomb(power, radius)
    sfx("bomb"); G.boom(WP(P.x, P.y, 1.0), true); G.shake = 0.8
    for _, m in ipairs(G.MON) do
        if m.alive and abs(m.x - P.x) < radius and abs(m.y - P.y) < radius * 0.7 then
            if m.kind ~= "death" or power >= 1 then kill_mon(m) end
        end
    end
    for _, g in ipairs(G.GENS) do if g.alive and abs(g.x - P.x) < radius and abs(g.y - P.y) < radius * 0.7 then hit_gen(g, 2 + H().magic * power) end end
    G.ESHOT = {}
end
local function pickup(it)
    it.alive = false
    if it.k == "k" then G.keys = G.keys + 1; add_score(100); sfx("key")
    elseif it.k == "f" then G.health = G.health + 100; add_score(10); sfx("food"); G.warned = false
    elseif it.k == "p" then G.potions = G.potions + 1; add_score(50); sfx("potion")
    elseif it.k == "t" then add_score(100); sfx("treasure") end
end
-- doors: a key opens the whole connected door run
local function open_door(i, j)
    if G.keys <= 0 then return false end
    G.keys = G.keys - 1; sfx("door"); add_score(10)
    local q = { { i, j } }
    while #q > 0 do
        local c = table.remove(q)
        if cell(c[1], c[2]) == "D" then
            setc(c[1], c[2], ".")
            for _, d in ipairs(G.DOORS) do if d.i == c[1] and d.j == c[2] then d.open = 0.001 end end
            q[#q + 1] = { c[1] + 1, c[2] }; q[#q + 1] = { c[1] - 1, c[2] }; q[#q + 1] = { c[1], c[2] + 1 }; q[#q + 1] = { c[1], c[2] - 1 }
        end
    end
    return true
end
------------------------------------------------------------------ monsters
local SPEED = { ghost = 2.4, grunt = 1.9, demon = 1.8, lobber = 1.6, sorc = 2.0, death = 2.2 }
local function spawn(kind, lv, x, y) G.MON[#G.MON + 1] = { kind = kind, lv = lv, hp = lv, x = x, y = y, alive = true, t = rr(0, 2), atk = 0, fire = rr(1, 3), vis = true, drained = 0, fx = 0, fy = -1 } end
G.spawn = spawn
local function los(x0, y0, x1, y1)
    local d = sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2); local n = max(1, math.ceil(d * 3))
    for k = 1, n - 1 do local t = k / n; if solid(floor(lerp(x0, x1, t)), floor(lerp(y0, y1, t))) then return false end end
    return true
end
local function mon_step(m, dt)
    m.t = m.t + dt
    local dx, dy = P.x - m.x, P.y - m.y
    local d = sqrt(dx * dx + dy * dy)
    if d > 14 or not P.alive then return end
    local sp = SPEED[m.kind] * dt
    local ux, uy = dx / max(d, 1e-3), dy / max(d, 1e-3)
    if m.kind == "lobber" and d < 4 then ux, uy = -ux, -uy end
    if m.kind == "sorc" then m.vis = (m.t % 2.4) < 1.4 end
    -- 8-way like the arcade: snap the chase direction to the nearest 45 degrees
    local a = math.atan2(uy, ux); a = math.floor(a / (PI / 4) + 0.5) * (PI / 4)
    local mx, my = cos(a) * sp, sin(a) * sp
    if not (m.kind == "lobber" and d > 3.5 and d < 5.5) then
        if move(m, mx, my, MR) then
            -- blocked: try the two neighbouring directions
            local ok = false
            for _, da in ipairs({ PI / 4, -PI / 4, PI / 2, -PI / 2 }) do
                local bx, by = cos(a + da) * sp, sin(a + da) * sp
                if not blocked(m.x + bx, m.y + by, MR) then m.x, m.y = m.x + bx, m.y + by; ok = true; break end
            end
        end
    end
    m.fx, m.fy = cos(a), sin(a)
    -- contact
    local touch = d < PR + MR + 0.04
    if touch then
        if m.kind == "ghost" then hurt(10 * m.lv); m.alive = false; sfx("hurt"); G.puff(WP(m.x, m.y, 0.4), { .8, .85, .95 }, 10); return
        elseif m.kind == "death" then
            local n = min(200 - m.drained, 60 * dt * 10)
            m.drained = m.drained + n; G.health = max(0, G.health - n); G.hurt_t = 0.15
            if (G.drain_s or 0) <= 0 then sfx("drain"); G.drain_s = 0.6 end
            if G.health <= 0 then hurt(1) end
            if m.drained >= 200 then m.alive = false; G.puff(WP(m.x, m.y, 0.5), { .2, .2, .25 }, 20) end
        else
            m.atk = m.atk - dt
            if m.atk <= 0 then m.atk = 0.5; m.swing = 1; hurt(({ grunt = 5, demon = 8, lobber = 3, sorc = 8 })[m.kind] * m.lv); sfx("hurt") end
        end
    end
    -- ranged attacks
    m.fire = m.fire - dt
    if m.kind == "demon" and m.fire <= 0 and d < 8 and los(m.x, m.y, P.x, P.y) then
        m.fire = rr(2, 3); m.swing = 1; G.ESHOT[#G.ESHOT + 1] = { k = "p_dfire", x = m.x, y = m.y, vx = ux * 6, vy = uy * 6, dmg = 10, lob = false }
    elseif m.kind == "lobber" and m.fire <= 0 and d < 7 then
        -- rocks are lobbed over walls to where you are standing
        m.fire = rr(2.2, 3); m.swing = 1; local T = 0.9
        G.ESHOT[#G.ESHOT + 1] = { k = "p_rock", x = m.x, y = m.y, vx = dx / T, vy = dy / T, dmg = 10, lob = true, t = 0, T = T }
    end
end
------------------------------------------------------------------ main step
function G.level_step(inp, dt)
    G.pt = G.pt + dt
    P.ox, P.oy = P.x, P.y
    for _, m in ipairs(G.MON) do m.ox, m.oy = m.x, m.y end
    for _, s in ipairs(G.SHOTS) do s.ox, s.oy = s.x, s.y end
    for _, s in ipairs(G.ESHOT) do s.ox, s.oy = s.x, s.y end
    G.hurt_t = max(0, (G.hurt_t or 0) - dt); G.drain_s = (G.drain_s or 0) - dt
    if G.phase == "dead" then if G.pt > 2.5 then G.out = true end; return end
    if G.phase == "exit" then
        if G.pt > 1.2 then load_level(G.next_level or (G.level + 1)); sfx("start") end
        return
    end
    -- health drains one point a second, like the arcade
    G.drain = (G.drain or 0) + dt
    if G.drain >= 1 then G.drain = G.drain - 1; G.health = G.health - 1; if G.health <= 0 then hurt(1) end end
    if G.health < 200 and not G.warned then G.warned = true; sfx("warn"); G.banner_set(H().name .. " Needs Food Badly", 2.5) end
    -- hero movement
    local mx, my = inp.mx, inp.my
    P.stun = max(0, (P.stun or 0) - dt); P.stun_cd = max(0, (P.stun_cd or 0) - dt)
    if P.stun > 0 then mx, my = 0, 0 end
    if mx ~= 0 or my ~= 0 then
        local l = sqrt(mx * mx + my * my); mx, my = mx / l, my / l
        P.fx, P.fy = mx, my
        local sp = H().speed * dt
        -- doors open when you walk into them holding a key
        local nx, ny = P.x + mx * (PR + 0.08), P.y + my * (PR + 0.08)
        local ci, cj = floor(nx), floor(ny)
        if cell(ci, cj) == "D" then open_door(ci, cj) end
        hero_move(P, mx * sp, my * sp, PR)
        P.walk = (P.walk or 0) + dt
    else P.walk = 0 end
    -- melee: walking into a monster or generator fights it
    P.melee = (P.melee or 0) - dt
    -- shots: one per press
    if inp.fire and #G.SHOTS < 2 and P.stun <= 0 then
        local h = H()
        G.SHOTS[#G.SHOTS + 1] = { x = P.x + P.fx * 0.3, y = P.y + P.fy * 0.3, px = P.x, py = P.y, vx = P.fx * h.sv, vy = P.fy * h.sv, dmg = h.shot, m = h.shotm, spin = 0 }
        sfx(h.id == "wiz" and "magic" or "shot"); P.atk_t = 1
        G.muzzle(WP(P.x + P.fx * 0.45, P.y + P.fy * 0.45, 0.5), h.id)
    end
    if inp.potion and G.potions > 0 then G.potions = G.potions - 1; smart_bomb(1, 10) end
    -- shots (swept in small steps)
    for i = #G.SHOTS, 1, -1 do
        local s = G.SHOTS[i]
        local gone = false
        local n = 4
        s.spin = s.spin + dt * 900
        for _ = 1, n do
            s.px, s.py = s.x, s.y
            s.x, s.y = s.x + s.vx * dt / n, s.y + s.vy * dt / n
            local ci, cj = floor(s.x), floor(s.y)
            local c = cell(ci, cj)
            if c == "G" then for _, g in ipairs(G.GENS) do if g.alive and g.i == ci and g.j == cj then hit_gen(g, s.dmg) end end; gone = true
            elseif c == "#" or c == "D" or c == "w" then gone = true; G.sparks(WP(s.px, s.py, 0.4), 5) end
            if not gone then
                for _, m in ipairs(G.MON) do
                    if m.alive and m.vis and m.kind ~= "death" and (m.x - s.x) ^ 2 + (m.y - s.y) ^ 2 < (MR + 0.12) ^ 2 then
                        m.hp = m.hp - s.dmg; gone = true
                        if m.hp <= 0 then kill_mon(m) else sfx("hit") end
                        break
                    end
                end
            end
            if not gone then
                for _, it in ipairs(G.ITEMS) do
                    if it.alive and it.k == "p" and (it.x - s.x) ^ 2 + (it.y - s.y) ^ 2 < 0.16 then it.alive = false; gone = true; smart_bomb(0.5, 5) end
                    -- shooting food destroys it, as in the arcade
                    if it.alive and it.k == "f" and (it.x - s.x) ^ 2 + (it.y - s.y) ^ 2 < 0.16 then it.alive = false; gone = true; G.puff(WP(it.x, it.y, 0.2), { .7, .4, .3 }, 8) end
                end
            end
            if gone then break end
        end
        if gone or abs(s.x - P.x) > 14 or abs(s.y - P.y) > 10 then table.remove(G.SHOTS, i) end
    end
    -- generators spawn while you are near
    local count = 0
    for _, m in ipairs(G.MON) do if m.alive then count = count + 1 end end
    for _, g in ipairs(G.GENS) do
        g.flash = max(0, g.flash - dt * 4)
        if g.alive and abs(g.x - P.x) < 11 and abs(g.y - P.y) < 8 then
            g.t = g.t - dt
            if g.t <= 0 and count < 70 then
                g.t = (rr(1.6, 2.8) - g.lv * 0.25) / (1 + 0.25 * G.tough)
                local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }
                local d = dirs[1 + floor(rand() * 8)]
                local x, y = g.x + d[1], g.y + d[2]
                if not blocked(x, y, MR) then spawn(g.kind, g.lv, x, y); count = count + 1; G.puff(WP(x, y, 0.3), { .5, .45, .42 }, 8) end
            end
        end
    end
    -- Death drifts in on the later levels
    if G.death_t then
        G.death_t = G.death_t - dt
        if G.death_t <= 0 then
            G.death_t = 40
            for _ = 1, 12 do
                local x, y = P.x + rr(-9, 9), P.y + rr(-7, 7)
                if not blocked(x, y, MR) and (x - P.x) ^ 2 + (y - P.y) ^ 2 > 25 then spawn("death", 1, x, y); break end
            end
        end
    end
    -- monsters
    for _, m in ipairs(G.MON) do if m.alive then mon_step(m, dt) end end
    -- simple separation so crowds don't stack (and never pushed into walls)
    for a = 1, #G.MON do
        local m = G.MON[a]
        if m.alive then
            for b = a + 1, min(#G.MON, a + 12) do
                local o = G.MON[b]
                if o.alive then
                    local dx, dy = o.x - m.x, o.y - m.y
                    local d2 = dx * dx + dy * dy
                    if d2 < (2 * MR) ^ 2 and d2 > 1e-6 then
                        local d = sqrt(d2); local push = (2 * MR - d) * 0.5
                        move(m, -dx / d * push, -dy / d * push, MR); move(o, dx / d * push, dy / d * push, MR)
                    end
                end
            end
            -- monsters never overlap the hero
            local dx, dy = m.x - P.x, m.y - P.y
            local d = sqrt(dx * dx + dy * dy)
            if d < PR + MR and d > 1e-4 then
                move(m, dx / d * (PR + MR - d), dy / d * (PR + MR - d), MR)
                if m.alive and m.kind ~= "death" and (P.melee <= 0) and (inp.mx ~= 0 or inp.my ~= 0) and (dx * P.fx + dy * P.fy) > 0 then
                    P.melee = 0.3; P.atk_t = 1; m.hp = m.hp - H().melee * 0.5; sfx("hit"); G.sparks(WP((m.x + P.x) / 2, (m.y + P.y) / 2, 0.5), 6)
                    if m.hp <= 0 then kill_mon(m) end
                end
            end
        end
    end
    -- melee against generators
    if (inp.mx ~= 0 or inp.my ~= 0) and P.melee <= 0 then
        local ci, cj = floor(P.x + P.fx * (PR + 0.1)), floor(P.y + P.fy * (PR + 0.1))
        if cell(ci, cj) == "G" then for _, g in ipairs(G.GENS) do if g.alive and g.i == ci and g.j == cj then P.melee = 0.35; P.atk_t = 1; hit_gen(g, H().melee * 0.5) end end end
    end
    for i = #G.MON, 1, -1 do if not G.MON[i].alive then table.remove(G.MON, i) end end
    -- enemy shots
    for i = #G.ESHOT, 1, -1 do
        local s = G.ESHOT[i]
        local gone = false
        if s.lob then
            s.t = s.t + dt; s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
            s.h = 0.4 + 2.2 * math.sin(PI * clamp(s.t / s.T, 0, 1))
            if s.t >= s.T then
                gone = true; G.puff(WP(s.x, s.y, 0.1), { .5, .48, .45 }, 8); G.dust(WP(s.x, s.y, 0.05), 10)
                if (s.x - P.x) ^ 2 + (s.y - P.y) ^ 2 < (PR + 0.25) ^ 2 then hurt(s.dmg); sfx("hurt") end
            end
        else
            s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt; s.h = 0.45
            if solid(floor(s.x), floor(s.y)) then gone = true; G.sparks(WP(s.x, s.y, 0.4), 5, { 1.6, .7, .3 })
            elseif (s.x - P.x) ^ 2 + (s.y - P.y) ^ 2 < (PR + 0.12) ^ 2 then gone = true; hurt(s.dmg); sfx("hurt") end
        end
        if gone then table.remove(G.ESHOT, i) end
    end
    -- items
    for _, it in ipairs(G.ITEMS) do if it.alive and (it.x - P.x) ^ 2 + (it.y - P.y) ^ 2 < (PR + 0.25) ^ 2 then pickup(it) end end
    -- doors animate open
    for _, d in ipairs(G.DOORS) do if d.open > 0 and d.open < 1 then d.open = min(1, d.open + dt * 3) end end
    -- trap tiles: stepping on one makes every trap wall on the floor vanish (shortcuts and sealed treasure open up)
    if not G.trapped then
        for _, t in ipairs(G.TRAPS) do
            if (t.x - P.x) ^ 2 + (t.y - P.y) ^ 2 < 0.16 then
                G.trapped = true; sfx("door"); G.shake = 0.35; G.banner_set("Trap!  The walls give way", 1.6)
                for j = 0, LH - 1 do for i = 0, LW - 1 do
                    if cell(i, j) == "w" then setc(i, j, "."); G.puff(WP(i + 0.5, j + 0.5, 0.5), { .55, .5, .45 }, 10); G.dust(WP(i + 0.5, j + 0.5, 0.05), 8) end
                end end
                break
            end
        end
    end
    -- stun tiles: a jolt that freezes the hero for a moment (and can't re-trigger straight away)
    for _, z in ipairs(G.STUNS) do
        z.t = max(0, z.t - dt)
        if P.stun_cd <= 0 and (z.x - P.x) ^ 2 + (z.y - P.y) ^ 2 < 0.12 then
            P.stun = 0.8; P.stun_cd = 2.0; z.t = 0.8; sfx("hurt"); G.hurt_t = 0.1
            G.sparks(WP(P.x, P.y, 0.3), 14, { 1.4, 1.3, .7 })
        end
    end
    -- treasure rooms run on a clock: when it runs out you are sent on without the bonus
    if G.ttime then
        G.ttime = G.ttime - dt
        if G.ttime <= 0 then
            G.ttime = 0; G.phase = "exit"; G.pt = 0; G.next_level = G.level + 1; sfx("warn"); G.banner_set("Time's Up", 1.2); return
        end
    end
    -- exits: the plain exit leads on one floor, a marked exit skips ahead
    for _, e in ipairs(G.EXITS) do
        local d2 = (e.x - P.x) ^ 2 + (e.y - P.y) ^ 2
        if e.jump and d2 < 9 and not e.told then e.told = true; G.banner_set("Exit to Level " .. e.to, 1.8) end
        if d2 < 0.2 then
            G.phase = "exit"; G.pt = 0; sfx("exit"); add_score(100 * G.level); G.next_level = e.to
            if G.ttime then local b = floor(G.ttime) * 100; add_score(b); G.banner_set("Treasure Bonus  " .. b, 1.2)
            else G.banner_set(e.jump and ("Exit to Level " .. e.to) or "Exit", 1.2) end
            G.ttime = nil
            break
        end
    end
end
G.puff, G.sparks, G.boom, G.flash = puff, sparks, boom, flash
