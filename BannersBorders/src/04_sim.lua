------------------------------------------------------------------ 04_sim: deterministic territory simulation (no engine calls; runs headless in tools/simtest.py)
local D = G.D
local SIM = {}
G.SIM = SIM
local floor, ceil, min, max, abs, sqrt = math.floor, math.ceil, math.min, math.max, math.abs, math.sqrt
local function hsh(i) local s = math.sin(i * 12.9898 + 78.233) * 43758.5453; return s - floor(s) end
local function inlist(t, v) if not t then return false end for _, x in ipairs(t) do if x == v then return true end end return false end
SIM.inlist = inlist

-- grid lookup: returns '.', ',' or region index
function SIM.cell(S, x, z)
    local M = S.M
    local col = floor((-x - M.e0) / M.cell)
    local row = floor((z - M.n0) / M.cell)
    if col < 0 or row < 0 or col >= M.gw or row >= M.gh then return 0 end
    local b = M.grid:byte(row * M.gw + col + 1)
    if b == 46 then return 0 elseif b == 44 then return -1 end
    return b - 47
end

local function fac_new(f, ai, pers)
    local F = { f = f, ai = ai, pers = pers, alive = true, prodmul = 1, speedmul = 1, defmul = 1, cdmul = 1, march_t = 0, cd = {}, think = 0,
        sent = 0, captured = 0, lost = 0, mines = 0, nreg = 0, troops = 0, rb = 1 }
    return F
end

-- level starts may be compass words ("W", "NE", ...) or "+" (a neighbour of the previous start): resolved once per level.
local DIRS = { N = { 0, 1 }, S = { 0, -1 }, E = { 1, 0 }, W = { -1, 0 }, NE = { .7, .7 }, NW = { -.7, .7 }, SE = { .7, -.7 }, SW = { -.7, -.7 }, C = { 0, 0 } }
function SIM.resolve_starts(L, M)
    local R = M.regions
    local cx, cz, n = 0, 0, #R
    for _, r in ipairs(R) do cx = cx - r.x / n; cz = cz + r.z / n end      -- east = -x
    local taken = {}
    local function far_ok(i)
        for j in pairs(taken) do
            if j == i then return false end
            for _, k in ipairs(R[j].nb) do if k == i then return false end end
        end
        return true
    end
    local function pick(d, prev)
        if type(d) == "number" then taken[d] = true; return d end
        local best, bi = -1e9, nil
        if d == "+" then
            for _, k in ipairs(R[prev].nb) do
                if not taken[k] and (R[k].area > (best or 0)) then best, bi = R[k].area, k end
            end
        else
            local v = DIRS[d]
            for i, r in ipairs(R) do
                if far_ok(i) then
                    local e, z = -r.x - cx, r.z - cz
                    local sc = (d == "C") and -(e * e + z * z) or (e * v[1] + z * v[2])
                    if sc > best then best, bi = sc, i end
                end
            end
        end
        bi = bi or 1; taken[bi] = true; return bi
    end
    local function res(list)
        local out, prev = {}, nil
        for _, d in ipairs(list) do prev = pick(d, prev); out[#out + 1] = prev end
        return out
    end
    L.p = res(L.p)
    for _, a in ipairs(L.ai) do a[3] = res(a[3]) end
    L.resolved = true
end

function SIM.new(li, sv, opt)
    opt = opt or {}
    local L = D.LEVELS[li]
    local M = BB_MAPS[L.map]
    local MI = D.MAPINFO[L.map] or M.info
    if not L.resolved then SIM.resolve_starts(L, M) end
    local S = { li = li, L = L, M = M, MI = MI, t = 0, R = {}, P = {}, ST = {}, ev = {}, F = {}, fx = { drops = {}, frost = {}, shells = {} },
        over = false, win = nil, pid = 0, sv = sv, stat = { sent = 0, cap = 0, lost = 0, clash = 0, peak = 0 }, tut = L.tut and not opt.demo, demo = opt.demo }
    -- effective difficulty = level tuning (HARD) scaled by the chosen mode and the retry boost
    local base = L.diff
    local MD = (not opt.demo) and D.MODES[opt.mode or 2] or D.MODES[3]
    local fails = opt.demo and 0 or math.min(D.RETRY.max, opt.boost or 0)
    S.mode, S.boost = MD.name, fails
    local diff = {}
    for k, v in pairs(base) do diff[k] = v end
    diff.aiprod = (base.aiprod or 1) * MD.aiprod * (1 - D.RETRY.aiprod * fails)
    diff.ivm = (base.ivm or 1) * MD.ivm
    diff.delay = (base.delay or 0) + MD.delay
    diff.ng = (base.ng or 1) * MD.ng
    diff.aicd = (base.aicd or 1) * MD.aicd
    -- per-level easing used only on Relaxed/Normal (L.soft): bosses and stalemate-prone maps get extra slack
    local soft = (not opt.demo) and (opt.mode or 2) <= 2 and L.soft or nil
    if soft then
        diff.aiprod = diff.aiprod * (soft.aiprod or 1)
        diff.ivm = diff.ivm * (soft.ivm or 1)
        diff.delay = diff.delay + (soft.delay or 0)
        diff.aicd = diff.aicd * (soft.aicd or 1)
    end
    local aistart_mul = soft and soft.aistart or 1
    local pstart = MD.pstart * (1 + D.RETRY.troops * fails)
    -- factions
    S.F[1] = fac_new(1, opt.demo and "steady" or nil)
    for _, a in ipairs(L.ai) do S.F[a[1]] = fac_new(a[1], a[2]) end
    for f = 1, 5 do if not S.F[f] then S.F[f] = fac_new(f); S.F[f].alive = false; S.F[f].absent = true end end
    local up = (sv and sv.up) or {}
    local P1 = S.F[1]
    if not opt.demo then
        P1.prodmul = 1 + 0.06 * (up.recruit or 0)
        P1.speedmul = 1 + 0.06 * (up.boots or 0)
        P1.defmul = 1 + 0.08 * (up.bastion or 0)
        P1.cdbase = 1 - 0.08 * (up.quarter or 0)
    end
    S.spd = diff.spd or 1; S.reachmul = diff.reach or 1
    for f = 2, 5 do local F = S.F[f]; if F.ai then F.prodmul = diff.aiprod; F.ivm = diff.ivm; F.cdbase = diff.aicd or 1 end end
    P1.cdbase = P1.cdbase or 1
    if opt.demo then P1.ivm = 1; P1.prodmul = diff.aiprod end
    -- regions
    local starts = {}
    for _, i in ipairs(L.p) do starts[i] = 1 end
    for _, a in ipairs(L.ai) do for _, i in ipairs(a[3]) do starts[i] = a[1] end end
    for i, src in ipairs(M.regions) do
        local size = src.area < 30 and 1 or (src.area < 70 and 2 or 3)
        local ty = "town"
        if starts[i] then ty = "capital" end
        if not starts[i] then
            if inlist(MI.mines, i) then ty = "mine" elseif inlist(MI.ports, i) then ty = "port" elseif inlist(MI.forts, i) then ty = "fort" end
        end
        -- only the first start region of each faction is a capital; extra start regions are forts
        local T = D.TYPES[ty]
        local r = { i = i, name = src.name, x = src.x, z = src.z, h = src.h, hill = src.hill, coast = src.coast, area = src.area, nb = src.nb,
            size = size, ty = ty, port = inlist(MI.ports, i), owner = 0, n = 0, frozen = 0, hit = -99, active = true, flash = 0 }
        r.cap = floor(D.CAP[size] * T.cap + 0.5)
        r.prod = D.PROD * D.SIZEMUL[size] * T.prod
        r.def = T.def
        if L.active and not inlist(L.active, i) then r.active = false end
        if starts[i] then
            r.owner = starts[i]
            r.n = (r.owner == 1) and floor(((L.start or 20) + (opt.demo and 0 or 3 * (up.veteran or 0))) * pstart + 0.5) or floor((L.aistart or 20) * aistart_mul + 0.5)
        else
            local base = D.NEUTRAL[size] * (diff.ng or 1) * (0.8 + 0.45 * hsh(i * 7 + li))
            if ty == "fort" then base = base * 1.3 elseif ty == "mine" then base = base + 4 elseif ty == "port" then base = base + 1 end
            r.n = floor(base + 0.5)
            r.n0 = r.n   -- neutral garrisons regrow back to this
        end
        S.R[i] = r
    end
    -- extra start regions beyond the first become forts (one capital per faction)
    local seen = {}
    for _, i in ipairs(L.p) do if seen[1] then S.R[i].ty = "fort" end; seen[1] = true end
    for _, a in ipairs(L.ai) do
        for k, i in ipairs(a[3]) do if k > 1 then local r = S.R[i]; r.ty = "fort"; local T = D.TYPES.fort; r.cap = floor(D.CAP[r.size] * T.cap + 0.5); r.prod = D.PROD * D.SIZEMUL[r.size] * T.prod; r.def = T.def end end
    end
    for f = 1, 5 do
        local F = S.F[f]
        for k = 1, #D.ABIL do F.cd[k] = D.ABIL[k].cd * 0.6 end
    end
    S.ai_delay = diff.delay or 0
    SIM.recount(S)
    return S
end

function SIM.recount(S)
    local tot = 0
    for f = 1, 5 do local F = S.F[f]; F.nreg, F.mines, F.troops = 0, 0, 0 end
    for _, r in ipairs(S.R) do
        if r.active then
            tot = tot + 1
            if r.owner > 0 then local F = S.F[r.owner]; F.nreg = F.nreg + 1; F.troops = F.troops + r.n; if r.ty == "mine" then F.mines = F.mines + 1 end end
        end
    end
    for _, p in ipairs(S.P) do local F = S.F[p.f]; F.troops = F.troops + p.k end
    for _, s in ipairs(S.ST) do local F = S.F[s.f]; F.troops = F.troops + s.left end
    S.nact = tot
    for f = 1, 5 do
        local F = S.F[f]
        local share = F.nreg / max(1, tot)
        F.rb = (F.nreg > 0 and share < 0.3) and (1 + 0.25 * (0.3 - share) / 0.3) or 1
        F.cdmul = (F.cdbase or 1) / (1 + 0.15 * F.mines)
    end
end

function SIM.def(S, r) return r.def * (r.owner > 0 and S.F[r.owner].defmul or 1) end
function SIM.abil_ready(S, f, k) local a = D.ABIL[k]; return S.L and (f ~= 1 or S.li >= a.unlock or S.demo) and S.F[f].cd[k] <= 0 end
function SIM.abil_frac(S, f, k) local a = D.ABIL[k]; return 1 - S.F[f].cd[k] / (a.cd * S.F[f].cdmul) end
function SIM.abil_unlocked(S, k) return S.li >= D.ABIL[k].unlock end

local function ev(S, e) S.ev[#S.ev + 1] = e; if #S.ev > 400 then table.remove(S.ev, 1) end end
SIM.ev = ev

-- send a fraction of troops from each source region to dst. returns number of troops sent
function SIM.send(S, f, srcs, dst, ratio, amounts)
    local d = S.R[dst]
    if not d or not d.active or S.over then return 0 end
    local tot = 0
    for j, i in ipairs(srcs) do
        local r = S.R[i]
        if r and i ~= dst and r.owner == f and r.active and r.frozen <= 0 then
            local amt = amounts and min(floor(amounts[j]), floor(r.n)) or floor(r.n * (ratio or 1))
            if amt >= 1 then
                r.n = r.n - amt
                local k = max(1, ceil(amt / D.PACK))
                local dx, dz = d.x - r.x, d.z - r.z
                local dl = max(0.01, sqrt(dx * dx + dz * dz))
                S.ST[#S.ST + 1] = { src = i, dst = dst, f = f, left = amt, k = k, acc = 1, n = 0, ux = dx / dl, uz = dz / dl, dl = dl, port = r.port }
                tot = tot + amt
                ev(S, { k = "send", r = i, d = dst, f = f, n = amt })
            end
        end
    end
    if tot > 0 then local F = S.F[f]; F.sent = F.sent + tot; if f == 1 then S.stat.sent = S.stat.sent + tot end end
    return tot
end

local LANE = { 0, -1, 1 }
local function emit(S, s)
    local r = S.R[s.src]
    s.n = s.n + 1
    local k = min(s.k, s.left)
    s.left = s.left - k
    local lane = LANE[(s.n - 1) % 3 + 1] * 0.2
    local px, pz = -s.uz, s.ux
    S.pid = S.pid + 1
    local sx, sz = r.x + s.ux * 0.55 + px * lane, r.z + s.uz * 0.55 + pz * lane
    local d = S.R[s.dst]
    S.P[#S.P + 1] = { id = S.pid, f = s.f, k = k, x = sx, z = sz, ox = sx, oz = sz, tx = d.x + px * lane, tz = d.z + pz * lane, dst = s.dst, src = s.src,
        port = s.port, bearer = (s.n % 8 == 1), lane = lane, age = 0, sea = false }
end

local function arrive(S, p)
    local r = S.R[p.dst]
    if r.owner == p.f then
        r.n = r.n + p.k
        return
    end
    local df = SIM.def(S, r)
    r.n = r.n - p.k / df
    r.hit = S.t
    if r.n < 0 then
        local old = r.owner
        r.n = (-r.n) * df
        r.owner = p.f
        r.frozen = 0
        r.flash = 1
        local F = S.F[p.f]
        F.captured = F.captured + 1
        if old > 0 then S.F[old].lost = S.F[old].lost + 1 end
        if p.f == 1 then S.stat.cap = S.stat.cap + 1 end
        if old == 1 then S.stat.lost = S.stat.lost + 1 end
        ev(S, { k = "capture", r = r.i, f = p.f, old = old })
        SIM.recount(S)
    else
        ev(S, { k = "hit", r = r.i, f = p.f })
    end
end

-- abilities ----------------------------------------------------------------
function SIM.use(S, f, k, ri)
    local a = D.ABIL[k]
    local F = S.F[f]
    if S.over or not SIM.abil_ready(S, f, k) then return false end
    local r = ri and S.R[ri]
    if a.target and (not r or not r.active) then return false end
    if a.key == "airdrop" then
        S.fx.drops[#S.fx.drops + 1] = { f = f, r = ri, t = 1.2, n = a.n }
    elseif a.key == "march" then
        F.march_t = a.dur
    elseif a.key == "frost" then
        S.fx.frost[#S.fx.frost + 1] = { f = f, x = r.x, z = r.z, rad = a.rad, t = a.dur, dur = a.dur }
        for _, o in ipairs(S.R) do
            local dx, dz = o.x - r.x, o.z - r.z
            if o.active and o.owner ~= f and dx * dx + dz * dz < a.rad * a.rad then o.frozen = a.dur end
        end
    elseif a.key == "barrage" then
        if r.owner == f then return false end
        S.fx.shells[#S.fx.shells + 1] = { f = f, r = ri, t = 1.0 }
    end
    F.cd[k] = a.cd * F.cdmul
    ev(S, { k = "abil", a = a.key, f = f, r = ri })
    return true
end

local function update_fx(S, dt)
    local fx = S.fx
    for i = #fx.drops, 1, -1 do
        local d = fx.drops[i]
        d.t = d.t - dt
        if d.t <= 0 then
            table.remove(fx.drops, i)
            arrive(S, { f = d.f, k = d.n, dst = d.r })
            ev(S, { k = "drop", r = d.r, f = d.f })
        end
    end
    for i = #fx.frost, 1, -1 do
        local q = fx.frost[i]
        q.t = q.t - dt
        if q.t <= 0 then table.remove(fx.frost, i) end
    end
    for i = #fx.shells, 1, -1 do
        local s = fx.shells[i]
        s.t = s.t - dt
        if s.t <= 0 then
            table.remove(fx.shells, i)
            local r = S.R[s.r]
            local a = D.ABIL[D.ABIX.barrage]
            if r.owner ~= s.f then r.n = max(0, r.n - min(a.maxk, r.n * a.frac)); r.hit = S.t end
            local rr = a.rad * a.rad
            for _, p in ipairs(S.P) do
                local dx, dz = p.x - r.x, p.z - r.z
                if p.f ~= s.f and dx * dx + dz * dz < rr then p.dead = true end
            end
            ev(S, { k = "boom", r = s.r, f = s.f })
        end
    end
end

-- clashes: packets of different factions that come close annihilate one-for-one
local HC = 0.6
local function clashes(S)
    local grid = {}
    local P = S.P
    for i, p in ipairs(P) do
        if not p.dead then
            local key = floor(p.x / HC) * 8192 + floor(p.z / HC)
            local c = grid[key]; if not c then c = {}; grid[key] = c end
            c[#c + 1] = i
        end
    end
    local R2 = D.CLASH_R * D.CLASH_R
    for i, p in ipairs(P) do
        if not p.dead and p.k > 0 then
            local cx, cz = floor(p.x / HC), floor(p.z / HC)
            for ox = -1, 1 do for oz = -1, 1 do
                local c = grid[(cx + ox) * 8192 + cz + oz]
                if c then
                    for _, j in ipairs(c) do
                        local q = P[j]
                        if j ~= i and not q.dead and q.f ~= p.f and q.k > 0 and p.k > 0 then
                            local dx, dz = q.x - p.x, q.z - p.z
                            if dx * dx + dz * dz < R2 then
                                local m = min(p.k, q.k)
                                p.k, q.k = p.k - m, q.k - m
                                if p.k <= 0 then p.dead = true end
                                if q.k <= 0 then q.dead = true end
                                S.stat.clash = S.stat.clash + m
                                ev(S, { k = "clash", x = (p.x + q.x) / 2, z = (p.z + q.z) / 2, f1 = p.f, f2 = q.f, n = m })
                            end
                        end
                    end
                end
            end end
        end
    end
end

function SIM.speed(S, p)
    local F = S.F[p.f]
    local s = D.SPEED * (S.spd or 1) * F.speedmul * (F.march_t > 0 and D.ABIL[D.ABIX.march].mul or 1)
    local c = SIM.cell(S, p.x, p.z)
    p.sea = (c == 0)
    if c == 0 then if not p.port then s = s * D.SEA_SLOW end
    elseif c > 0 and S.R[c] and S.R[c].hill then s = s * D.HILL_SLOW end
    for _, q in ipairs(S.fx.frost) do
        if q.f ~= p.f then
            local dx, dz = p.x - q.x, p.z - q.z
            if dx * dx + dz * dz < q.rad * q.rad then s = s * 0.4 end
        end
    end
    return s
end

function SIM.step(S, dt)
    if S.over then return end
    S.t = S.t + dt
    -- production & decay
    for _, r in ipairs(S.R) do
        if r.flash > 0 then r.flash = max(0, r.flash - dt) end
        if r.frozen > 0 then r.frozen = r.frozen - dt end
        if r.active and r.owner > 0 then
            local F = S.F[r.owner]
            if r.n > r.cap then
                r.n = max(r.cap, r.n - max(D.DECAY, (r.n - r.cap) * 0.08) * dt)
            elseif r.frozen <= 0 then
                r.n = min(r.cap, r.n + r.prod * F.prodmul * F.rb * (1 + 0.06 * F.mines) * dt)
            end
        elseif r.active and r.owner == 0 then
            -- neutral regrowth: slower than any owned region, paused right after an attack and while frozen
            r.regen = r.n0 and r.n < r.n0 and r.frozen <= 0 and S.t - r.hit >= D.NREGEN_WAIT or false
            if r.regen then r.n = min(r.n0, r.n + D.NREGEN * dt) end
        end
    end
    for f = 1, 5 do
        local F = S.F[f]
        if F.march_t > 0 then F.march_t = F.march_t - dt end
        for k = 1, #D.ABIL do if F.cd[k] > 0 then F.cd[k] = F.cd[k] - dt end end
    end
    -- streams emit packets
    for i = #S.ST, 1, -1 do
        local s = S.ST[i]
        s.acc = s.acc + D.EMIT * dt
        while s.acc >= 1 and s.left > 0 do s.acc = s.acc - 1; emit(S, s) end
        if s.left <= 0 then table.remove(S.ST, i) end
    end
    -- move packets
    for _, p in ipairs(S.P) do
        if not p.dead then
            p.age = p.age + dt
            local dx, dz = p.tx - p.x, p.tz - p.z
            local dl = sqrt(dx * dx + dz * dz)
            local sp = SIM.speed(S, p) * dt
            if dl <= sp + 0.35 then
                p.dead = true; p.arrived = true
                arrive(S, p)
            else
                p.x, p.z = p.x + dx / dl * sp, p.z + dz / dl * sp
            end
        end
    end
    clashes(S)
    update_fx(S, dt)
    local j = 0
    local P = S.P
    for i = 1, #P do local p = P[i]; if not p.dead then j = j + 1; P[j] = p end end
    for i = #P, j + 1, -1 do P[i] = nil end
    -- AI
    if G.AI then G.AI.update(S, dt) end
    -- end conditions
    SIM.recount(S)
    if S.F[1].troops > S.stat.peak then S.stat.peak = S.F[1].troops end
    for f = 1, 5 do local F = S.F[f]; if not F.absent then F.alive = F.nreg > 0 or F.troops > 0.5 end end
    -- the battle counts as started once the board is set up: remember how many enemy factions held land at t=0
    if not S.started then
        S.started, S.foes0 = true, 0
        for f = 2, 5 do local F = S.F[f]; if not F.absent and F.nreg > 0 then S.foes0 = S.foes0 + 1 end end
    end
    -- a win needs every enemy faction at zero regions AND zero troops in transit (packets or streams),
    -- after the battle has really started (enemies existed and at least 1 s has passed)
    local foes = false
    for f = 2, 5 do local F = S.F[f]; if not F.absent and (F.nreg > 0 or F.troops > 0) then foes = true end end
    local can_win = S.started and S.foes0 > 0 and S.t >= 1
    if not S.demo then
        if not S.F[1].alive then S.over, S.win = true, false; ev(S, { k = "lose" })
        elseif not foes and can_win then
            S.over, S.win = true, true; ev(S, { k = "win" })
        end
    else
        local alive = 0
        for f = 1, 5 do if S.F[f].alive then alive = alive + 1 end end
        if alive <= 1 or S.t > 240 then S.over = true end
    end
end

-- helpers for UI / AI
function SIM.incoming(S, ri)
    local mine, foe = 0, 0
    local r = S.R[ri]
    for _, p in ipairs(S.P) do if p.dst == ri then if p.f == r.owner then mine = mine + p.k else foe = foe + p.k end end end
    for _, s in ipairs(S.ST) do if s.dst == ri then if s.f == r.owner then mine = mine + s.left else foe = foe + s.left end end end
    return mine, foe
end
function SIM.dist(S, a, b) local ra, rb = S.R[a], S.R[b]; local dx, dz = ra.x - rb.x, ra.z - rb.z; return sqrt(dx * dx + dz * dz) end
function SIM.region_at(S, x, z)
    local c = SIM.cell(S, x, z)
    if c > 0 and S.R[c] and S.R[c].active then return c end
    return nil
end
