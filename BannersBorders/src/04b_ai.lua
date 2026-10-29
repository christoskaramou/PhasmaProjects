------------------------------------------------------------------ 04b_ai: rival commanders with personalities
local D, SIM = G.D, G.SIM
local AI = {}
G.AI = AI
local floor, min, max, sqrt = math.floor, math.min, math.max, math.sqrt

-- troops needed to take r if they arrive after eta seconds (as seen by faction f)
local function tally(S)
    local inc = {}
    for _, p in ipairs(S.P) do local t = inc[p.dst]; if not t then t = {}; inc[p.dst] = t end; t[p.f] = (t[p.f] or 0) + p.k end
    for _, s in ipairs(S.ST) do local t = inc[s.dst]; if not t then t = {}; inc[s.dst] = t end; t[s.f] = (t[s.f] or 0) + s.left end
    S._inc = inc
    return inc
end
AI.tally = tally
local function need_for(S, f, r, eta)
    local n = r.n
    if r.owner > 0 and r.frozen <= 0 then
        local F = S.F[r.owner]
        n = min(r.cap, n + r.prod * F.prodmul * eta)
    end
    local t = (S._inc or tally(S))[r.i]
    local own_f, mine = 0, 0
    if t then own_f = t[f] or 0; if r.owner > 0 then mine = t[r.owner] or 0 end end
    return (n + mine) * SIM.def(S, r) - own_f
end
AI.need_for = need_for

local function value(S, F, P, r)
    local v = 10 + r.size * 3 + (D.TYPES[r.ty].val or 0)
    if r.owner == 1 then v = v * P.pbias elseif r.owner == 0 then v = v * P.nbias end
    if P.vult > 0 and S.t - r.hit < 6 then v = v * (1 + P.vult) end
    if r.owner > 0 and r.owner ~= F.f and S.F[r.owner].nreg <= 2 then v = v * 1.4 end -- finish off weak rivals
    return v
end

local function plan_attack(S, F, P, mine, used, reach)
    reach = (reach or P.reach) * (S.reachmul or 1)
    local best, bs, bsrc, bam
    local speed = D.SPEED * F.speedmul
    for _, r in ipairs(S.R) do
        if r.active and r.owner ~= F.f then
            -- nearest own region
            local dmin = 1e9
            for _, m in ipairs(mine) do local d = SIM.dist(S, m.i, r.i); if d < dmin then dmin = d end end
            if dmin < reach then
                local need = need_for(S, F.f, r, dmin / speed) + 2
                if need > 0 then
                    local sc = value(S, F, P, r) / (need + 1.5 * dmin)
                    if not bs or sc > bs then
                        -- gather sources (closest first) with their spare troops
                        local list = {}
                        for _, m in ipairs(mine) do
                            if not used[m.i] and m.frozen <= 0 then
                                local spare = m.n - P.keep * m.cap
                                if spare >= 3 then list[#list + 1] = { i = m.i, s = spare, d = SIM.dist(S, m.i, r.i) } end
                            end
                        end
                        table.sort(list, function(a, b) return a.d < b.d end)
                        local got, src, am = 0, {}, {}
                        for _, c in ipairs(list) do
                            if c.d < reach * 1.3 then
                                src[#src + 1] = c.i; am[#am + 1] = c.s; got = got + c.s
                                if got >= need * 1.15 + (r.owner > 0 and r.prod * (c.d - dmin) / speed or 0) then break end
                            end
                        end
                        local eta_need = need * 1.15
                        if got >= eta_need then
                            -- trim the excess from the last source so the garrisons are not stripped bare
                            local over = got - eta_need - 2
                            if over > 0 then am[#am] = max(1, am[#am] - over) end
                            best, bs, bsrc, bam = r, sc, src, am
                        end
                    end
                end
            end
        end
    end
    return best, bsrc, bam
end

local function defend(S, F, P, mine, used)
    for _, m in ipairs(mine) do
        local _, foe = SIM.incoming(S, m.i)
        if foe > m.n * SIM.def(S, m) * 0.9 then
            local short = foe / SIM.def(S, m) - m.n + 3
            local src, am, got = {}, {}, 0
            for _, o in ipairs(mine) do
                if o.i ~= m.i and not used[o.i] and o.frozen <= 0 and SIM.dist(S, o.i, m.i) < 9 then
                    local spare = o.n - 0.25 * o.cap
                    if spare >= 3 then src[#src + 1] = o.i; am[#am + 1] = min(spare, short - got); got = got + am[#am] end
                end
                if got >= short then break end
            end
            if got >= short * 0.6 and #src > 0 then
                SIM.send(S, F.f, src, m.i, nil, am)
                for _, i in ipairs(src) do used[i] = true end
                return true
            end
        end
    end
    return false
end

local function abilities(S, F, P, mine)
    if not P.abil then return end
    -- frost the player's strongest cluster
    local k = D.ABIX.frost
    if SIM.abil_ready(S, F.f, k) then
        local best, bv
        for _, r in ipairs(S.R) do
            if r.active and r.owner > 0 and r.owner ~= F.f then
                local v = 0
                for _, o in ipairs(S.R) do if o.owner == r.owner and SIM.dist(S, r.i, o.i) < 5 then v = v + o.n end end
                if r.owner == 1 then v = v * 1.2 end
                if not bv or v > bv then best, bv = r, v end
            end
        end
        if best and bv > 40 then SIM.use(S, F.f, k, best.i) end
    end
    k = D.ABIX.barrage
    if SIM.abil_ready(S, F.f, k) then
        local best, bv
        for _, r in ipairs(S.R) do
            if r.active and r.owner ~= F.f and r.owner > 0 and r.n > 15 then
                local v = r.n * (r.owner == 1 and 1.3 or 1)
                if not bv or v > bv then best, bv = r, v end
            end
        end
        if best then SIM.use(S, F.f, k, best.i) end
    end
    k = D.ABIX.airdrop
    if SIM.abil_ready(S, F.f, k) then
        -- reinforce a threatened region, else grab the weakest reachable target
        local tgt
        for _, m in ipairs(mine) do local _, foe = SIM.incoming(S, m.i); if foe > m.n then tgt = m.i end end
        if not tgt then
            local bv
            for _, r in ipairs(S.R) do
                if r.active and r.owner ~= F.f and r.n * SIM.def(S, r) < 10 then
                    if not bv or r.n < bv then tgt, bv = r.i, r.n end
                end
            end
        end
        if tgt then SIM.use(S, F.f, k, tgt) end
    end
    k = D.ABIX.march
    if SIM.abil_ready(S, F.f, k) then
        local fly = 0
        for _, p in ipairs(S.P) do if p.f == F.f then fly = fly + p.k end end
        if fly > 30 then SIM.use(S, F.f, k) end
    end
end

function AI.think(S, F)
    local P = D.PERS[F.ai]
    local mine = {}
    for _, r in ipairs(S.R) do if r.active and r.owner == F.f then mine[#mine + 1] = r end end
    if #mine == 0 then return end
    local used = {}
    tally(S)
    defend(S, F, P, mine, used)
    -- every garrison near its cap: the front is stalled, so mass troops from further away (ocean crossings)
    local sn, sc = 0, 0
    for _, m in ipairs(mine) do sn = sn + m.n; sc = sc + m.cap end
    local rr = (sn > 0.85 * sc and #mine >= 6) and 40 or nil
    for _ = 1, P.acts do
        local r, src, am = plan_attack(S, F, P, mine, used, rr)
        -- nothing in reach for a while (rival hiding on an island / far corner): widen the search
        if not r and S.t - (F.last_act or 0) > 10 then r, src, am = plan_attack(S, F, P, mine, used, 99) end
        if not r then break end
        F.last_act = S.t
        SIM.send(S, F.f, src, r.i, nil, am)
        for _, i in ipairs(src) do used[i] = true end
        tally(S)
    end
    abilities(S, F, P, mine)
    S._inc = nil
end

function AI.update(S, dt)
    if S.t < S.ai_delay then return end
    for f = 1, 5 do
        local F = S.F[f]
        if F.ai and F.alive and (f ~= 1 or S.demo) then
            F.think = F.think - dt
            if F.think <= 0 then
                local P = D.PERS[F.ai]
                F.think = P.iv * (F.ivm or 1) * (0.85 + 0.3 * math.random())
                AI.think(S, F)
            end
        end
    end
end
