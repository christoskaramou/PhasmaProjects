------------------------------------------------------------------ the run: steering, terrain, objects, interactions (fixed step)
do
local TER = {  -- speed, grip (lower = slides), bleed per second for a pawn standing in it, display name
    oil = { sp = 1.05, grip = 1.8, bleed = 0, name = "Oil" }, ice = { sp = 1.22, grip = 1.6, bleed = 0, name = "Ice" },
    mud = { sp = 0.55, grip = 10, bleed = 0, name = "Mud" }, gravel = { sp = 0.8, grip = 10, bleed = 0.035, name = "Gravel" },
    thorn = { sp = 0.85, grip = 10, bleed = 0.13, name = "Brambles" },
}
G.TER = TER
function RUN.start(L)
    G.L = L
    for _, u in ipairs(C.units) do F_put("man_" .. G.T[u.t].col .. "0", u.n) end
    for _, d in ipairs(C.dead) do F_put("man_" .. (d.col or G.T[d.t].col) .. "0", d.n) end
    C.units, C.dead = {}, {}
    G.build_level(L)
    G.boost = G.catchup(L.idx)
    R.build(L, G.boost.foe)
    local a = G.army_counts()
    C.cnt = { G.start_pawns() + a[1] + G.boost.pawns, a[2], a[3], G.breakers() }
    C.cx, C.cxt, C.cz, C.vx, C.speed, C.bdmg, C.gdmg, C.lost = 0, 0, 0, 0, 0, 0, 0, 0
    C.rmax = 1
    C.sync(false); C.formation(); C.layout(4.2)
    for _, u in ipairs(C.units) do u.ox, u.oz = u.tx, u.tz; u.born = 0 end
    RUN.stats = { coins = 0, kills = 0, perfect = 0, gates = 0, traps = 0, close = 0, lost_traps = 0, cages = 0, drops = 0, peak = C.power() }
    RUN.phase = "run"; RUN.clash = nil; RUN.t = 0; RUN.tip = nil
    G.shield_t = 0; G.shields = G.shield_charges()
    G.cam_reset = true
end

------------------------------------------------------------------ gates
local function apply(v)
    local o, n = v:sub(1, 1), tonumber(v:sub(2)) or 0
    local c = C.cnt
    local before = C.power()
    if o == "+" then c[1] = c[1] + round(n * G.gate_mult())
    elseif o == "x" then c[1] = c[1] * n
    elseif o == "-" then C.damage(n)
    elseif o == "/" then c[1] = math.ceil(c[1] / n)
    elseif o == "M" then
        if c[1] >= 2 then local k = floor(c[1] / 2); c[2] = c[2] + k; c[1] = c[1] - 2 * k
        elseif c[2] >= 2 then local k = floor(c[2] / 2); c[3] = c[3] + k; c[2] = c[2] - 2 * k end
    end
    return C.power() - before
end
local function outcome(v)  -- power after taking v (for the perfect-gate check)
    local save = { C.cnt[1], C.cnt[2], C.cnt[3], C.cnt[4] }; local bd, gd = C.bdmg, C.gdmg
    apply(v); local p = C.power()
    C.cnt = save; C.bdmg, C.gdmg = bd, gd
    return p
end
RUN.outcome = outcome
local function pass_gate(e)
    e.done = true
    local pi = 1
    if #e.panels == 2 and C.cx > 0 then pi = 2 end
    local p = e.panels[pi]
    local v = p.v
    if #e.panels == 2 then
        local other = e.panels[3 - pi].v
        if outcome(v) >= outcome(other) then RUN.stats.perfect = RUN.stats.perfect + 1 end
    end
    RUN.stats.gates = RUN.stats.gates + 1
    local d = apply(v)
    C.sync(); C.formation()
    local good = d >= 0
    local o = v:sub(1, 1)
    local col = o == "M" and { 1.4, 1.1, .3 } or (good and { .4, .8, 1.6 } or { 1.6, .35, .3 })
    G.FX.glow_trail(LX(p.x), 1.6, e.z, col)
    G.FX.flash(LX(p.x), 1.6, e.z, 3.5, col)
    G.FX.shatter(LX(p.x), 1.6, e.z, col)
    G.fx_light(vec3(LX(p.x), 2, e.z), col, 60, 0.35, 10)
    p.n:set_position(HIDE); p.gone = true
    if o == "M" then sfx("merge"); G.punch(6, 0.5); G.shake(0.25); G.popup("Merge!", { 1, .85, .3, 1 }, 1.4)
        G.FX.confetti(LX(C.cx), 2, C.cz + 2, 25)
    elseif good then sfx("gate_good"); G.punch((o == "x") and (2 + (tonumber(v:sub(2)) or 2) * 1.2) or 2.5, 0.35)
        G.popup(G.label_of(v), { .55, .85, 1, 1 }, 1.0)
        if o == "x" and (tonumber(v:sub(2)) or 0) >= 3 then G.FX.confetti(LX(C.cx), 2, C.cz + 3, 20) end
    else sfx("gate_bad"); G.shake(0.35); G.punch(-2.5, 0.3); G.popup(G.label_of(v), { 1, .45, .4, 1 }, 1.0) end
    if C.power() > RUN.stats.peak then RUN.stats.peak = C.power() end
end

------------------------------------------------------------------ unit vs trap helpers
local function near_miss(e, clear)
    if clear < (e.close or 99) then e.close = clear end
end
local function each_unit(f)
    local i = 1
    while i <= #C.units do
        local u = C.units[i]
        if not f(u, C.cx + u.ox, C.cz + u.oz) then i = i + 1 end
    end
end
-- each trap can only take a bite out of the crowd (max ~35%), never wipe it in one sweep
local function trap_hit(e, u, vx, vy, vz)
    -- the bite is measured in crowd POWER (one visible pawn can stand for several members)
    if not e.cap then e.cap = max(2, floor(C.power() * 0.16 + 0.5)) end
    if (e.lost or 0) >= e.cap then
        if u.inv <= 0 then u.inv = 0.3; G.FX.sparks(LX(C.cx + u.ox), 0.8, C.cz + u.oz, 2) end
        return false
    end
    local before, p0 = #C.units, C.power()
    C.hurt(u, "trap", vx, vy, vz)
    e.lost = (e.lost or 0) + max(1, p0 - C.power())
    e.hit = (e.hit or 0) + 1
    if #C.units < before then RUN.stats.lost_traps = RUN.stats.lost_traps + 1; return true end
    return false
end
------------------------------------------------------------------ per-step update
function RUN.step(dt)
    local L = G.L
    local st = RUN.stats
    RUN.t = RUN.t + dt
    -- steering target from keys / drag
    local dir = 0
    if anyheld("A", "Left") then dir = dir - 1 end
    if anyheld("D", "Right") then dir = dir + 1 end
    C.cxt = C.cxt + dir * 10 * dt
    if G.drag_dx then C.cxt = C.cxt + G.drag_dx; G.drag_dx = nil end
    -- floor under the crowd, terrain mix
    -- squeeze early: narrowest strip (the one under / nearest the crowd) over the next few metres
    local width = 2 * W
    -- dense samples from the rear row to ~1 s ahead (a long squeezed column must not un-squeeze while its tail is still over a pit)
    local wz = {}
    do local zz = C.cz - (C.hd or 1) - 0.4; while zz < C.cz + (C.hd or 1) * 0.5 + 9 do wz[#wz + 1] = zz; zz = zz + 1.25 end end
    for _, zq in ipairs(wz) do
        local iv = G.floor_at(L, zq)
        local bw, bd = nil, 1e9
        for _, s2 in ipairs(iv) do
            local d = (C.cx < s2[1]) and (s2[1] - C.cx) or ((C.cx > s2[2]) and (C.cx - s2[2]) or 0)
            if d < bd then bd, bw = d, s2[2] - s2[1] end
        end
        if bw and bw < width then width = bw end
    end
    local hwmax = max(0.7, min(4.2, width / 2 - 0.25))
    C.layout(hwmax)
    local hw = C.hw or 1
    C.cxt = clamp(C.cxt, -W + min(hw, W - 0.2), W - min(hw, W - 0.2))
    -- edge assist: when the floor ahead narrows (bridges, pit edges) the crowd is gently
    -- herded onto the strip it is already over, so falls come from fighting it, not from bad luck
    -- (samples the whole crowd depth: rear rows still over a pit keep the crowd on the strip)
    local sa, sb, any = -1e9, 1e9, false
    local zs = {}
    do local z0 = C.cz - (C.hd or 1) - 0.4; local zz = z0; while zz < C.cz + 6 do zs[#zs + 1] = zz; zz = zz + 1.5 end; zs[#zs + 1] = C.cz + 6 end
    for _, zz in ipairs(zs) do
        local bs, bd = nil, 1e9   -- nearest strip to the crowd centre (so a crowd beside a bridge is led onto it)
        for _, s2 in ipairs(G.floor_at(L, zz)) do
            local d = (C.cx < s2[1]) and (s2[1] - C.cx) or ((C.cx > s2[2]) and (C.cx - s2[2]) or 0)
            if d < bd then bd, bs = d, s2 end
        end
        if bs then
            if bs[2] - bs[1] < 2 * W - 0.01 then any = true end
            sa, sb = max(sa, bs[1]), min(sb, bs[2])
        end
    end
    RUN.safe = nil
    if any and sb > sa then
        local a, b = sa + hw * 0.95, sb - hw * 0.95
        RUN.safe = { a, b, (sa + sb) / 2 }
        local tgt = (a <= b) and clamp(C.cxt, a, b) or (sa + sb) / 2
        if dir == 0 then C.cxt = damp(C.cxt, tgt, 3.5, dt) else C.cxt = damp(C.cxt, tgt, 1.2, dt) end
    end
    local tcount, tsp, tgrip, nk = {}, 0, 0, 0
    for _, u in ipairs(C.units) do
        local k = G.terrain_at(L, C.cx + u.ox, C.cz + u.oz)
        local tt = k and TER[k]
        tsp = tsp + (tt and tt.sp or 1); tgrip = tgrip + (tt and tt.grip or 30); nk = nk + 1
        if k then tcount[k] = (tcount[k] or 0) + 1 end
        u.ter = k
    end
    if nk > 0 then tsp, tgrip = tsp / nk, tgrip / nk else tsp, tgrip = 1, 30 end
    RUN.ter = nil
    local best = 0
    for k, n in pairs(tcount) do if n > best then best = n; RUN.ter = k end end
    -- lateral motion: grip blends a firm follow with a slidey spring
    local want = (C.cxt - C.cx) * min(tgrip, 14)
    C.vx = damp(C.vx, want, min(tgrip, 30) * 0.9, dt)
    if RUN.ter == "oil" then C.vx = C.vx + sin(RUN.t * 1.7) * 3 * dt end
    C.cx = C.cx + C.vx * dt
    if RUN.ter == "oil" or RUN.ter == "ice" then local m = W - (C.hw or 1) * 0.55 + 0.2; C.cx = clamp(C.cx, -m, m); if abs(C.cx) >= m - 0.01 then C.vx = C.vx * 0.5 end else C.cx = clamp(C.cx, -W + 0.3, W - 0.3) end
    -- forward speed
    local base = 8.5 * G.speed_mult()
    local target = base * tsp
    if RUN.clash or RUN.block then target = RUN.block and base * 0.15 or 0 end
    C.speed = damp(C.speed, target, 5, dt)
    C.cz = C.cz + C.speed * dt
    -- units follow their slots; check the floor under each one; terrain bleed
    for i = #C.units, 1, -1 do
        local u = C.units[i]
        if u then
            local k = (u.ter == "oil" or u.ter == "ice") and 3 or 9
            u.ox = damp(u.ox, u.tx + sin(RUN.t * 3 + u.ph) * 0.04, k, dt)
            u.oz = damp(u.oz, u.tz + cos(RUN.t * 2.6 + u.ph) * 0.05, k, dt)
            local wx, wz = C.cx + u.ox, C.cz + u.oz
            if not G.solid(G.floor_at(L, wz), wx) then
                st.lost_traps = st.lost_traps + 1
                C.lose_unit(u, "fall")
            elseif u.ter and TER[u.ter].bleed > 0 and u.t ~= 3 then
                local b = TER[u.ter].bleed * (u.t == 2 and 0.3 or 1) * (1 - G.armor_chance())
                if rand() < b * dt then
                    st.lost_traps = st.lost_traps + 1
                    C.hurt(u, "trap", rr(-1, 1), 3, 0)
                    G.FX.grit(LX(wx), 0.3, wz, { .5, .3, .2 }, 4)
                end
            end
        end
    end
    C.sync()
    -- terrain feedback dust
    if RUN.ter and rand() < dt * 8 then
        local col = ({ oil = { .3, .3, .35 }, ice = { .8, .9, 1 }, mud = { .45, .3, .18 }, gravel = { .55, .52, .5 }, thorn = { .4, .45, .3 } })[RUN.ter]
        G.FX.dust(LX(C.cx + rr(-hw, hw)), 0.2, C.cz - 0.5, col, 0.5, 0.7)
    end
    -- objects
    RUN.block = nil
    local front = C.cz + (C.hd or 1)
    for _, e in ipairs(R.list) do
        if (not e.done or (e.t == "gate" and (e.sink or 0) < 1)) and e.z < C.cz + 70 and e.z > C.cz - 30 then RUN.obj(e, dt, front, hw) end
    end
    -- coins (magnet widens the pickup)
    local mag = G.magnet()
    for _, c in ipairs(R.coins) do
        if c.on and abs(c.z - C.cz) < (C.hd or 1) + 0.8 and abs(c.x - C.cx) < hw + 0.6 + mag then
            c.on = false; c.n:set_position(HIDE)
            st.coins = st.coins + 1; G.coin_sfx()
            G.FX.coin(LX(c.x), 1, c.z)
        end
    end
    if C.power() <= 0 then RUN.phase = "dead" end
end

function RUN.obj(e, dt, front, hw)
    local t = e.t
    local st = RUN.stats
    if t == "gate" then
        if e.done then   -- passed gates sink into the track so they never block the follow camera
            if (e.sink or 0) < 1 then
                e.sink = min(1, (e.sink or 0) + dt / 0.5); local dy = -4.4 * e.sink * e.sink
                for i, q in ipairs(e.posts) do q:set_position(vec3(LX(e.postx[i]), dy, e.z)) end
                for _, p in ipairs(e.panels) do if not p.gone then p.n:set_position(vec3(LX(p.x), 2.27 + dy, e.z)) end end
                if e.bar then e.bar:set_position(vec3(0, 3.35 + dy, e.z)) end
                if e.lamps then for i, l in ipairs(e.lamps) do l:set_position(vec3(LX(e.panels[i].x), 3.7 + dy, e.z)) end end
            end
            return
        end
        if e.kind == "trick" and not e.flipped and e.z - front < 13 then
            e.flipped = true; e.scramble = 0.7
            if not G.lucky_reveal() then
                local pi = (C.cx > 0) and 2 or 1
                local mine, other = e.panels[pi], e.panels[3 - pi]
                if mine and other and outcome(mine.v) > outcome(other.v) then e.swap = true end
            end
            sfx("deny")
        end
        if e.scramble then
            e.scramble = e.scramble - dt
            if e.scramble <= 0 then
                e.scramble = nil
                if e.swap then local a, b = e.panels[1].v, e.panels[2].v; R.set_panel(e.panels[1], b); R.set_panel(e.panels[2], a); G.popup("Trick Gate!", { 1, .6, .3, 1 }, 1) end
            end
        end
        if e.kind == "timed" then
            local on = floor((G.t + e.z * 0.13) / 1.5) % 2 == 0
            if on ~= e.on then
                e.on = on
                for i, p in ipairs(e.panels) do R.set_panel(p, on and ((i == 1) and e.a or e.b) or ((i == 1) and e.b or e.a)) end
                if abs(e.z - front) < 30 then sfx("click") end
            end
        end
        if front >= e.z and C.cz >= e.z - (C.hd or 1) * 0.5 then pass_gate(e) end
        for i, p in ipairs(e.panels) do
            local txt = e.scramble and ({ "+?", "×?", "-?", "÷?" })[floor(G.t * 14 + i) % 4 + 1] or G.label_of(p.v)
            local o = p.v:sub(1, 1)
            local col = o == "M" and { 1, .9, .45, 1 } or ((o == "+" or o == "x") and { 1, 1, 1, 1 } or { 1, .9, .9, 1 })
            R.label(p.x, 1.85, e.z, txt, col, 2.3)
        end
    elseif t == "enemy" then
        local dz = e.cz - front
        if e.state == "wait" and dz < 16 then e.state = "charge"; sfx("boss_roar") end
        if e.state == "charge" then e.cz = e.cz - 5 * dt; e.x = damp(e.x, C.cx, 2, dt) end
        if e.state ~= "clash" and e.cz - e.rmax <= front + 0.2 then e.state = "clash"; RUN.clash = e; G.shake(0.3); sfx("clash") end
        if e.state == "clash" then
            e.cz = max(front + e.rmax * 0.4, e.cz - 3 * dt)
            local rate = 14 + 0.35 * min(C.power(), e.n)
            e.acc = (e.acc or 0) + rate * dt
            while e.acc >= 1 and e.n > 0 and C.power() > 0 do
                e.acc = e.acc - 1; e.n = e.n - 1; st.kills = st.kills + 1
                if rand() >= G.might_chance() then C.damage(1) end
            end
            C.sync(false)
            R.enemy_sync(e)
            if rand() < dt * 14 then
                local x, z = (C.cx + e.x) / 2 + rr(-1.5, 1.5), front + rr(-0.3, 0.6)
                G.FX.puff(LX(x), 0.7, z, rand() < 0.5 and G.TEAMRGB.r or G.TEAMRGB.b, 0.8)
                G.FX.sparks(LX(x), 0.8, z, 5, nil, 5)
                G.sfx_hit()
            end
            if e.n <= 0 or C.power() <= 0 then
                e.done = true; RUN.clash = nil
                for _, u in ipairs(e.units) do F_put("man_r0", u.n) end; e.units = {}
                if C.power() > 0 then G.popup("Crushed!", { 1, .85, .3, 1 }, 1); G.punch(3, 0.3); sfx("gate_good") end
            end
        end
        for _, u in ipairs(e.units) do
            u.ph = u.ph + dt * (e.state == "wait" and 0.8 or 8)
            local fr = e.state == "wait" and "i" or tostring(floor(u.ph) % 4)
            if fr ~= u.fr then u.fr = fr; u.n:set_mesh_ref(mesh_of("man_r" .. fr)) end
            u.n:set_position(vec3(LX(e.x + u.ox), e.state == "wait" and 0 or abs(sin(u.ph * PI * 0.5)) * 0.085, e.cz + u.oz))
        end
        if not e.done then local cl = (e.state == "clash") and 1 or 0; R.label(e.x + cl * 1.3, 1.6 + e.rmax * 0.25 + 1.2 + cl * 0.6, e.cz, tostring(e.n), { 1, 1, 1, 1 }, 1.5, { .9, .2, .2, .92 }) end
    elseif t == "cage" then
        local inx = abs(C.cx - e.x) < 1.3 + hw * 0.5
        if e.hp > 0 and inx and front > e.z - 1.3 and C.cz < e.z + 1 then
            RUN.block = true
            e.hp = e.hp - (6 + 0.4 * C.power()) * dt
            if rand() < dt * 10 then G.FX.grit(LX(e.x + rr(-1, 1)), 1, e.z - 1, { .55, .38, .22 }, 3); G.sfx_hit() end
            local wob = sin(G.t * 40) * 3
            e.node:set_rotation(vec3(wob, 0, -wob))
            if e.hp <= 0 then
                e.done = true; e.node:set_position(HIDE); st.cages = st.cages + 1
                for _, n in ipairs(e.caps) do n:set_position(HIDE); F_put("man_g0", n) end
                C.cnt[1] = C.cnt[1] + e.n; C.sync(); G.shake(0.3); G.punch(4, 0.4)
                G.FX.grit(LX(e.x), 1.2, e.z, { .55, .38, .22 }, 20); G.FX.dust(LX(e.x), 0.5, e.z, { .6, .5, .4 }, 1.5, 1.5)
                G.FX.confetti(LX(e.x), 2, e.z, 20)
                sfx("slam"); sfx("gate_good"); G.popup("Freed +" .. e.n .. "!", { .6, 1, .6, 1 }, 1.2)
            end
        end
        if not e.done then
            R.label(e.x, 3.1, e.z, "+" .. e.n, { 1, 1, 1, 1 }, 1.3, { .25, .55, .3, .9 })
            if e.hp < e.hp0 then R.label(e.x, 3.9, e.z, string.rep("|", math.ceil(e.hp / e.hp0 * 10)), { 1, .9, .4, 1 }, 0.9) end
            if C.cz > e.z + 2 then e.done = true end
        end
    elseif t == "drop" then
        if e.state == "wait" and e.z - C.cz < 60 then
            e.state = "fall"; e.crate = P_get("crate"); e.chute = P_get("chute")
            e.ttl = max(1.5, (e.z - C.cz) / max(4, C.speed) - 0.8); e.y = 30; sfx("shield")
        end
        if e.state == "fall" then
            e.y = max(0, e.y - (e.y / max(e.ttl, 0.1)) * dt); e.ttl = max(0.05, e.ttl - dt)
            e.crate:set_position(vec3(LX(e.x), e.y, e.z)); e.crate:set_rotation(vec3(0, G.t * 30, sin(G.t * 2) * 5))
            e.chute:set_position(vec3(LX(e.x), e.y, e.z)); e.chute:set_rotation(vec3(sin(G.t * 1.6) * 6, G.t * 30, 0))
            if e.y <= 0.01 and not e.landed then e.landed = true; e.chute:set_position(HIDE); G.FX.dust(LX(e.x), 0.3, e.z, { .7, .65, .55 }, 1, 1.2); sfx("thud") end
            R.label(e.x, e.y + 2.2, e.z, "+" .. e.n, { 1, 1, 1, 1 }, 1.3, { .2, .5, .9, .9 })
            if C.cz > e.z - 0.5 then
                e.done = true
                if abs(C.cx - e.x) < hw + 1.0 + G.magnet() * 0.5 then
                    C.cnt[1] = C.cnt[1] + e.n; C.sync(); st.drops = st.drops + 1
                    G.FX.grit(LX(e.x), 1, e.z, { .72, .52, .3 }, 12); G.FX.confetti(LX(e.x), 1.5, e.z, 15)
                    sfx("gate_good"); G.punch(3, 0.3); G.popup("Air Drop +" .. e.n, { .55, .85, 1, 1 }, 1.1)
                    e.crate:set_position(HIDE); e.chute:set_position(HIDE)
                end
            end
        end
    elseif t == "ally" then
        e.node:set_mesh_ref(mesh_of(floor(G.t * 3) % 2 == 0 and "man_yc" or "man_yi"))
        R.label(e.x, 4.0, e.z, "Giant Ally", { 1, .95, .6, 1 }, 1.0, { .75, .5, .1, .9 })
        if C.cz > e.z - 0.5 then
            e.done = true
            if abs(C.cx - e.x) < hw + 1.4 + G.magnet() * 0.5 then
                e.node:set_position(HIDE); F_put("man_y0", e.node)
                C.cnt[3] = C.cnt[3] + 1; C.sync(); G.punch(7, 0.6); G.shake(0.3)
                G.FX.confetti(LX(e.x), 3, e.z, 30); sfx("trophy"); G.popup("A Giant Joins!", { 1, .85, .3, 1 }, 1.4)
            end
        end
    elseif t == "spin" then
        e.a = e.a + e.w * dt
        e.bar:set_rotation(vec3(0, math.deg(e.a), 0))
        local ca, sa = cos(e.a), sin(e.a)
        each_unit(function(u, x, z)
            local dx, dz = LX(x) - LX(e.x), z - e.z
            local along = dx * ca - dz * sa
            local perp = abs(dx * sa + dz * ca)
            if abs(along) < 4.4 then
                local clear = perp - (0.25 + G.T[u.t].rad)
                if clear < 0 then return trap_hit(e, u, -sa * 8 * (along > 0 and 1 or -1), 7, ca * 4) end
                near_miss(e, clear)
            end
        end)
        RUN.trap_done(e)
    elseif t == "saw" then
        local mid, amp = (e.x0 + e.x1) / 2, (e.x1 - e.x0) / 2
        e.sx = mid + amp * sin(G.t * e.w)
        e.saw:set_position(vec3(LX(e.sx), 0.85, e.z)); e.saw:set_rotation(vec3(0, 0, G.t * 900)); e.saw:set_scale(vec3(1, 1, 1))
        e.hub:set_position(vec3(LX(e.sx), 0.85, e.z)); e.hub:set_rotation(vec3(0, 0, 0))
        if rand() < dt * 6 then G.FX.sparks(LX(e.sx), 0.05, e.z, 3, { 0, 2, -3 }, 3) end
        each_unit(function(u, x, z)
            if abs(z - e.z) < 0.25 + G.T[u.t].rad then
                local clear = abs(x - e.sx) - (1.05 + G.T[u.t].rad * 0.6)
                if clear < 0 then sfx("saw"); return trap_hit(e, u, (x > e.sx and 1 or -1) * -6, 6, 2) end
                near_miss(e, clear)
            end
        end)
        RUN.trap_done(e)
    elseif t == "ham" then
        local phi = 1.15 * sin(G.t * 2 * PI / 2.6 + e.ph * 2 * PI)
        e.h1:set_position(vec3(LX(e.x), 5.5, e.z)); e.h1:set_rotation(vec3(0, 0, math.deg(phi)))
        e.h2:set_position(vec3(LX(e.x), 5.5, e.z)); e.h2:set_rotation(vec3(0, 0, math.deg(phi)))
        local hx, hy = e.x - 4.3 * sin(phi), 5.5 - 4.3 * cos(phi)
        if hy < 2.6 then
            each_unit(function(u, x, z)
                if abs(z - e.z) < 1.1 + G.T[u.t].rad then
                    local clear = abs(x - hx) - (0.75 + G.T[u.t].rad)
                    if clear < 0 and hy < 1.0 + G.T[u.t].s then return trap_hit(e, u, (x > hx and -1 or 1) * 9, 6, 1) end
                    near_miss(e, clear)
                end
            end)
        end
        RUN.trap_done(e)
    elseif t == "crush" then
        local cyc = (G.t / 2.3 + e.ph) % 1
        local y
        if cyc < 0.55 then y = 4.6 elseif cyc < 0.62 then y = lerp(4.6, 0.75, (cyc - 0.55) / 0.07) elseif cyc < 0.78 then y = 0.75 else y = lerp(0.75, 4.6, (cyc - 0.78) / 0.22) end
        if y <= 0.76 and (e.y or 5) > 0.76 then
            if abs(e.z - C.cz) < 25 then sfx("slam"); G.shake(0.2) end
            G.FX.dust(LX(e.x), 0.2, e.z, { .7, .65, .6 }, 1.2, 1.3)
        end
        e.y = y
        e.blk:set_position(vec3(LX(e.x), y, e.z)); e.blk:set_scale(vec3(e.w, 1.5, 2.1))
        if y < 1.5 then
            each_unit(function(u, x, z)
                if abs(z - e.z) < 1.05 + G.T[u.t].rad * 0.5 and abs(x - e.x) < e.w / 2 + G.T[u.t].rad * 0.5 then
                    if y - 0.75 < 1.15 * G.T[u.t].s then return trap_hit(e, u, rr(-2, 2), 2, 0) end
                end
            end)
        else
            each_unit(function(u, x, z) if abs(z - e.z) < 1.2 and abs(x - e.x) < e.w / 2 + 0.3 then near_miss(e, 0.3) end end)
        end
        RUN.trap_done(e)
    elseif t == "roll" then
        if e.state == "wait" and e.z - C.cz < 34 then e.state = "go"; sfx("thud") end
        if e.state == "go" then e.rz = e.rz - 7 * dt end
        e.node:set_position(vec3(LX(e.x), 0.62, e.rz)); e.node:set_scale(vec3(e.w, 1, 1)); e.node:set_rotation(vec3(-G.t * 400, 0, 0))
        local k = #e.sp
        for i, s in ipairs(e.sp) do
            s:set_position(vec3(LX(e.x - e.w / 2 + (i - 0.5) * e.w / k), 0.62, e.rz)); s:set_rotation(vec3(-G.t * 400 + i * 22, 0, 0))
        end
        each_unit(function(u, x, z)
            if abs(z - e.rz) < 0.9 + G.T[u.t].rad then
                local clear = abs(x - e.x) - (e.w / 2 + G.T[u.t].rad * 0.5)
                if clear < 0 then return trap_hit(e, u, 0, 6, -6) end
                near_miss(e, clear)
            end
        end)
        if e.rz < C.cz - 14 then e.done = true; e.node:set_position(HIDE); for _, s in ipairs(e.sp) do s:set_position(HIDE) end; RUN.trap_done(e, true) end
    elseif t == "pit" or t == "bridge" then
        if C.cz > e.z1 + 1 then e.done = true; RUN.trap_done(e, true) end
    elseif t == "tip" then
        if C.cz > e.z - 2 then e.done = true; G.tip(e.text) end
    elseif t == "ter" then
        if not e.told and C.cz > e.z0 - 2 then e.told = true end
        if C.cz > e.z1 then e.done = true end
    end
end
-- a trap counts as cleared once the crowd is past it; near misses pay a small bonus
function RUN.trap_done(e, force)
    local past = force or (C.cz - (C.hd or 1) > e.z + 2.5)
    if not past or e.scored then return end
    e.scored = true
    local st = RUN.stats
    if (e.hit or 0) == 0 then
        st.traps = st.traps + 1
        if (e.close or 99) < 0.45 then st.close = st.close + 1; G.popup("Close Call! +5", { .7, 1, .8, 1 }, 0.9) end
    end
    e.done = true
end
end
