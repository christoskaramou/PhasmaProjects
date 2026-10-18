------------------------------------------------------------------ live stage state (cell units; world = cell * CS)
local FR = 1 / 60
local FUSE, FLAME_T, BURN_T = 2.6, 0.55, 0.5
local PSPEED, PSPEED_UP = 3.2, 1.0
local HW = 0.42             -- player half width (cells) against walls
local HIT_EN = 0.62         -- player <-> enemy contact distance (cells)
G.CONST = { FUSE = FUSE, FLAME_T = FLAME_T, PSPEED = PSPEED, HW = HW, HIT_EN = HIT_EN }
local BOMBS, FLS, ENEMIES, BRICKS = {}, {}, {}, {}
local FLAME = {}            -- FLAME[c * 100 + r] = time left
local BOMBAT = {}           -- BOMBAT[c * 100 + r] = bomb
local FLAMEG = {}           -- explosion group per flame cell (kill chain scoring)
G.BOMBS, G.FLS, G.ENEMIES, G.BRICKS, G.FLAME, G.BOMBAT = BOMBS, FLS, ENEMIES, BRICKS, FLAME, BOMBAT
local function key(c, r) return c * 100 + r end
local P = { x = 1, z = 1, ox = 1, oz = 1, st = "walk", dir = "down", ph = 0, bombs = 1, fire = 1, speed = 0, inv = 0, dead_t = 0 }
G.P = P
local EXIT, PU = { c = 0, r = 0 }, { c = 0, r = 0 }
G.EXIT, G.PU = EXIT, PU

local function flame_at(c, r) return (FLAME[key(c, r)] or 0) > 0 end
G.flame_at = flame_at
local function blocked_p(c, r)
    local s = solid_raw(c, r)
    if s == 1 then return true end
    if s == 2 and not P.wallpass then return true end
    local b = BOMBAT[key(c, r)]
    if b and not P.bombpass and not b.pass_p then return true end
    return false
end
local function blocked_e(e, c, r)
    local s = solid_raw(c, r)
    if s == 1 then return true end
    if s == 2 and not EN[e.k][4] then return true end
    if BOMBAT[key(c, r)] then return true end
    return false
end
local function box_hits(x, z)
    for c = floor(x - HW + 0.5), floor(x + HW + 0.5 - 1e-6) do
        for r = floor(z - HW + 0.5), floor(z + HW + 0.5 - 1e-6) do
            if blocked_p(c, r) then return true end
        end
    end
    return false
end
G.box_hits = box_hits

------------------------------------------------------------------ stage build (geometry nodes come from 05_render)
local function build_stage(n)
    for _, t in ipairs({ BOMBS, FLS, ENEMIES }) do for i = #t, 1, -1 do t[i] = nil end end
    for k in pairs(FLAME) do FLAME[k] = nil; FLAMEG[k] = nil end
    for k in pairs(BOMBAT) do BOMBAT[k] = nil end
    for k in pairs(BRICKS) do BRICKS[k] = nil end
    local d = stage_def(n)
    local e, p, empties, lr = build_layout(n)
    EXIT.c, EXIT.r, EXIT.exposed, EXIT.open = e[1], e[2], false, false
    PU.c, PU.r, PU.kind, PU.exposed, PU.taken = p[1], p[2], d.pu, false, false
    for c = 1, NC do for r = 1, NR do if GRID[c][r] == 2 then BRICKS[key(c, r)] = { c = c, r = r, burn = 0 } end end end
    ST = { n = n, def = d, empties = empties }
    -- enemies on free cells away from the start corner
    local slots = {}
    for i, f in ipairs(empties) do slots[i] = f end
    for tier = 1, 7 do
        for _ = 1, d.en[tier] or 0 do
            if #slots == 0 then break end
            local f = table.remove(slots, 1 + floor(lr() * #slots))
            G.enemy_new(TIER[tier], f[1], f[2], 0)
        end
    end
    G.build_bricks()
    return ST
end
G.ST = function() return ST end

------------------------------------------------------------------ enemies
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
function G.enemy_new(k, c, r, inv)
    local e = { k = k, c = c, r = r, tc = c, tr = r, t = 1, x = c, z = r, ox = c, oz = r, alive = true, inv = inv or 0, die_t = 0, ph = rand() * 6, wait = 0 }
    ENEMIES[#ENEMIES + 1] = e
    return e
end
local function enemy_choose(e)
    local def = EN[e.k]
    local opts = {}
    for _, d in ipairs(DIRS) do if not blocked_e(e, e.c + d[1], e.r + d[2]) then opts[#opts + 1] = d end end
    if #opts == 0 then e.dx, e.dz = 0, 0; e.wait = 0.4; return end
    local smart = def[3]
    local px, pz = floor(P.x + 0.5), floor(P.z + 0.5)
    local dist = abs(px - e.c) + abs(pz - e.r)
    if smart > 0 and P.st ~= "dead" and dist <= 3 + smart * 2 and rand() < 0.35 + smart * 0.2 then
        local best, bd = nil, 1e9
        for _, d in ipairs(opts) do
            local dd = abs(px - (e.c + d[1])) + abs(pz - (e.r + d[2])) + rand() * 0.3
            if dd < bd then bd, best = dd, d end
        end
        e.dx, e.dz = best[1], best[2]; return
    end
    local turn = (e.k == "dahl" or e.k == "pontan") and 0.5 or 0.12
    if e.dx then
        for _, d in ipairs(opts) do
            if d[1] == e.dx and d[2] == e.dz and rand() > turn then return end
        end
    end
    -- prefer not to reverse unless it is the only way
    local fw = {}
    for _, d in ipairs(opts) do if not (e.dx and d[1] == -e.dx and d[2] == -e.dz) then fw[#fw + 1] = d end end
    local pick = (#fw > 0 and rand() > 0.08) and fw[1 + floor(rand() * #fw)] or opts[1 + floor(rand() * #opts)]
    e.dx, e.dz = pick[1], pick[2]
end
local function enemy_step(e, dt)
    e.ox, e.oz = e.x, e.z
    e.ph = e.ph + dt
    if not e.alive then e.die_t = e.die_t + dt; return end
    e.inv = max(0, e.inv - dt)
    local sp = EN[e.k][2]
    if e.t >= 1 then
        if e.wait > 0 then e.wait = e.wait - dt; return end
        enemy_choose(e)
        if e.dx == 0 and e.dz == 0 then return end
        e.tc, e.tr = e.c + e.dx, e.r + e.dz; e.t = 0
    end
    -- a bomb dropped in front: turn back
    if BOMBAT[key(e.tc, e.tr)] and e.t < 0.6 then
        e.c, e.tc = e.tc, e.c; e.r, e.tr = e.tr, e.r; e.t = 1 - e.t; e.dx, e.dz = -e.dx, -e.dz
    end
    e.t = e.t + sp * dt
    if e.t >= 1 then e.t = 1; e.c, e.r = e.tc, e.tr end
    e.x = e.c + (e.tc - e.c) * e.t; e.z = e.r + (e.tr - e.r) * e.t
    if e.t >= 1 then e.x, e.z = e.c, e.r end
end
local function spawn_wave(c, r, tier, n)
    for _ = 1, n do
        local e = G.enemy_new(TIER[tier], c, r, 1.0)
        e.wait = rand() * 0.5
    end
    sfx("spawn")
end
G.spawn_wave = spawn_wave

------------------------------------------------------------------ bombs + flames
local function place_bomb()
    local c, r = floor(P.x + 0.5), floor(P.z + 0.5)
    if BOMBAT[key(c, r)] or solid_raw(c, r) ~= 0 then return end
    local live = 0
    for _, b in ipairs(BOMBS) do live = live + 1 end
    if live >= P.bombs then return end
    local b = { c = c, r = r, t = FUSE, range = P.fire, pass_p = true, remote = P.detonator, age = 0, born = G.t }
    BOMBS[#BOMBS + 1] = b; BOMBAT[key(c, r)] = b
    -- enemies standing in that cell keep going; enemies about to enter it turn back (enemy_step)
    sfx("place")
end
local explode
local function kill_enemy(e, grp)
    if not e.alive or e.inv > 0 then return end
    e.alive = false; e.die_t = 0
    grp.kills = grp.kills + 1
    local pts = EN[e.k][5] * 2 ^ (grp.kills - 1)
    add_score(pts, e.x, e.z)
    sfx("kill")
    sparks(e.x * CS, 1.0, e.z * CS, { 1, .8, .5 }, 26, 10, 0.6)
end
local function flame_cell(c, r, kind, ax, grp)
    FLAME[key(c, r)] = FLAME_T; FLAMEG[key(c, r)] = grp
    FLS[#FLS + 1] = { c = c, r = r, t = FLAME_T, kind = kind, ax = ax }
    if PU.exposed and not PU.taken and PU.c == c and PU.r == r and not grp.pu_hit then
        grp.pu_hit = true; PU.taken = true; sparks(c * CS, 0.5, r * CS, { .6, .8, 1 }, 20)
        spawn_wave(c, r, ST.def.spawn_tier, 8)
    end
    if EXIT.exposed and EXIT.c == c and EXIT.r == r and not grp.exit_hit and (G.exit_cool or 0) <= 0 then
        grp.exit_hit = true; G.exit_cool = 1.0
        spawn_wave(c, r, ST.def.spawn_tier, 8)
    end
end
explode = function(b, grp)
    if b.gone then return end
    b.gone = true
    BOMBAT[key(b.c, b.r)] = nil
    for i = #BOMBS, 1, -1 do if BOMBS[i] == b then table.remove(BOMBS, i) end end
    grp = grp or { kills = 0 }
    sfx("boom"); G.shake = max(G.shake, 0.32)
    flash(b.c * CS, b.r * CS, { 1, .6, .25 }, 70, 0.4, 10)
    fx_core(b.c * CS, b.r * CS)
    flame_cell(b.c, b.r, "core", 0, grp)
    for _, d in ipairs(DIRS) do
        for i = 1, b.range do
            local c, r = b.c + d[1] * i, b.r + d[2] * i
            local s = solid_raw(c, r)
            if s == 1 then break end
            if s == 2 then
                local br = BRICKS[key(c, r)]
                if br and br.burn <= 0 then br.burn = BURN_T; fx_brick_hit(c * CS, r * CS) end
                break
            end
            local ob = BOMBAT[key(c, r)]
            flame_cell(c, r, i == b.range and "end" or "arm", (d[1] ~= 0) and (d[1] > 0 and 90 or -90) or (d[2] > 0 and 0 or 180), grp)
            fx_arm(c * CS, r * CS, d[1], d[2], i, i == b.range)
            FLS[#FLS].fxd = 0.035 * i
            if ob then explode(ob, grp); break end
        end
    end
end
G.explode = explode
local function detonate()
    local oldest = nil
    for _, b in ipairs(BOMBS) do if b.remote and (not oldest or b.born < oldest.born) then oldest = b end end
    if oldest then sfx("detonate"); explode(oldest) end
end

------------------------------------------------------------------ player
local function try_move(dx, dz, dist)
    local x0, z0 = P.x, P.z
    if dx ~= 0 then
        local nx = P.x + dx * dist
        if not box_hits(nx, P.z) then P.x = nx
        else
            -- corner assist: slide toward the lane centre if the lane ahead is open
            local lane = floor(P.z + 0.5)
            local off = lane - P.z
            if abs(off) > 0.02 and not blocked_p(floor(P.x + 0.5) + dx, lane) then
                local s = min(abs(off), dist); P.z = P.z + (off > 0 and s or -s)
                if box_hits(P.x, P.z) then P.z = z0 end
            else
                -- snug up against the wall
                local c = floor(P.x + 0.5); local lim = c + dx * (0.5 - HW)
                if (dx > 0 and P.x < lim) or (dx < 0 and P.x > lim) then P.x = lim end
            end
        end
    else
        local nz = P.z + dz * dist
        if not box_hits(P.x, nz) then P.z = nz
        else
            local lane = floor(P.x + 0.5)
            local off = lane - P.x
            if abs(off) > 0.02 and not blocked_p(lane, floor(P.z + 0.5) + dz) then
                local s = min(abs(off), dist); P.x = P.x + (off > 0 and s or -s)
                if box_hits(P.x, P.z) then P.x = x0 end
            else
                local r = floor(P.z + 0.5); local lim = r + dz * (0.5 - HW)
                if (dz > 0 and P.z < lim) or (dz < 0 and P.z > lim) then P.z = lim end
            end
        end
    end
    return abs(P.x - x0) + abs(P.z - z0) > 1e-5
end
local DIRV = { left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 }, down = { 0, 1 } }
local function player_die(cause)
    if P.st == "dead" or G.god then return end
    P.st = "dead"; P.dead_t = 0; P.cause = cause
    music(nil); sfx("death"); G.shake = 0.5
    smoke(P.x * CS, 1.0, P.z * CS, 16, 0.6)
end
G.player_die = player_die
local function apply_pu(k)
    if k == "bombs" then P.bombs = min(10, P.bombs + 1)
    elseif k == "fire" then P.fire = min(10, P.fire + 1)
    elseif k == "speed" then P.speed = 1
    elseif k == "mystery" then P.inv = 10
    else P[k] = true end
    sfx("item"); popup(P.x, P.z, G.PU_NAME[k], { .7, .9, 1 })
end
local function player_step(inp, dt)
    P.ox, P.oz = P.x, P.z
    if P.st == "dead" then P.dead_t = P.dead_t + dt; return end
    if P.st ~= "walk" then return end
    P.inv = max(0, P.inv - dt)
    if inp.bomb then place_bomb() end
    if inp.det and P.detonator then detonate() end
    local dist = (PSPEED + P.speed * PSPEED_UP) * dt
    local moved = false
    -- most recently pressed direction first; if it is blocked, take whichever other held direction is open
    for _, nm in ipairs(inp.order) do
        local v = DIRV[nm]
        if try_move(v[1], v[2], dist) then moved = true; P.dir = nm; break end
    end
    if not moved and inp.order[1] then P.dir = inp.order[1] end
    P.moving = moved
    if moved then
        P.ph = P.ph + dt * 12
        P.step_t = (P.step_t or 0) - dt
        if P.step_t <= 0 then P.step_alt = not P.step_alt; sfx(P.step_alt and "walk" or "walk2"); P.step_t = 0.22 end
    else P.step_t = 0 end
    -- leave a freshly placed bomb behind
    for _, b in ipairs(BOMBS) do
        if b.pass_p and (abs(P.x - b.c) >= 0.5 + HW - 1e-3 or abs(P.z - b.r) >= 0.5 + HW - 1e-3) then b.pass_p = false end
    end
    local c, r = floor(P.x + 0.5), floor(P.z + 0.5)
    if PU.exposed and not PU.taken and PU.c == c and PU.r == r then PU.taken = true; apply_pu(PU.kind) end
end

------------------------------------------------------------------ step
local function stage_step(inp, dt)
    G.exit_cool = max(0, (G.exit_cool or 0) - dt)
    if P.st == "walk" then
        G.time = G.time - dt
        if G.time <= 10 and floor(G.time + dt) ~= floor(G.time) and G.time > 0 then sfx("warn") end
        if G.time <= 0 and not G.pontans then
            G.time = 0; G.pontans = true
            for i = 1, 8 do
                local f = ST.empties[1 + floor(rand() * #ST.empties)]
                if solid_raw(f[1], f[2]) == 0 then G.enemy_new("pontan", f[1], f[2], 1.0) end
            end
            sfx("spawn"); G.banner = { text = "Time Up", t = 2 }
        end
    end
    player_step(inp, dt)
    -- bombs
    for i = #BOMBS, 1, -1 do
        local b = BOMBS[i]
        if b then
            b.age = b.age + dt
            if not b.remote or P.st == "dead" then b.t = b.t - dt end
            if b.t <= 0 then explode(b) end
        end
    end
    -- flames
    for i = #FLS, 1, -1 do local f = FLS[i]; f.t = f.t - dt; if f.t <= 0 then table.remove(FLS, i) end end
    for k, t in pairs(FLAME) do t = t - dt; if t <= 0 then FLAME[k] = nil; FLAMEG[k] = nil else FLAME[k] = t end end
    -- burning bricks
    for k, br in pairs(BRICKS) do
        if br.burn > 0 then
            br.burn = br.burn - dt
            if br.burn <= 0 then
                GRID[br.c][br.r] = 0; BRICKS[k] = nil; sfx("brick")
                fx_brick_break(br.c * CS, br.r * CS)
                if EXIT.c == br.c and EXIT.r == br.r then EXIT.exposed = true end
                if PU.c == br.c and PU.r == br.r then PU.exposed = true end
            end
        end
    end
    for _, e in ipairs(ENEMIES) do enemy_step(e, dt) end
    for i = #ENEMIES, 1, -1 do if not ENEMIES[i].alive and ENEMIES[i].die_t > 1.0 then table.remove(ENEMIES, i) end end
    -- flame kills (cell of the centre point)
    for _, e in ipairs(ENEMIES) do
        local k = key(floor(e.x + 0.5), floor(e.z + 0.5))
        if e.alive and (FLAME[k] or 0) > 0 then kill_enemy(e, FLAMEG[k] or { kills = 0 }) end
    end
    if P.st == "walk" then
        local c, r = floor(P.x + 0.5), floor(P.z + 0.5)
        if flame_at(c, r) and not P.flamepass and P.inv <= 0 then player_die("fire") end
        if P.inv <= 0 then
            for _, e in ipairs(ENEMIES) do
                if e.alive and abs(e.x - P.x) < HIT_EN and abs(e.z - P.z) < HIT_EN then player_die("enemy"); break end
            end
        end
    end
    -- exit door
    local alive = 0
    for _, e in ipairs(ENEMIES) do if e.alive then alive = alive + 1 end end
    G.alive = alive
    if alive == 0 and not EXIT.open then EXIT.open = true; if EXIT.exposed then sfx("door") end end
    if alive > 0 then EXIT.open = false end
end
G.stage_step = stage_step
local function stage_reset(n, keep)
    build_stage(n)
    P.x, P.z, P.ox, P.oz = 1, 1, 1, 1; P.st = "walk"; P.dir = "down"; P.inv = 0; P.dead_t = 0
    if not keep then P.bombs, P.fire, P.speed = 1, 1, 0 end
    P.wallpass, P.bombpass, P.flamepass, P.detonator = false, false, false, false
    G.time = ST.def.time; G.pontans = false; G.exit_cool = 0
end
G.stage_reset = stage_reset
function G.at_exit() local c, r = floor(P.x + 0.5), floor(P.z + 0.5); return EXIT.exposed and EXIT.open and c == EXIT.c and r == EXIT.r end
