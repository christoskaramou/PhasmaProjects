------------------------------------------------------------------ crowd: tiers, formation, run, gates, enemies, traps, terrain
local C = { units = {}, dead = {}, cnt = { 0, 0, 0, 0 }, cx = 0, cxt = 0, cz = 0, vx = 0, speed = 0 }
local R = { list = {}, coins = {}, labels = {} }
local RUN = { stats = {} }
G.C, G.R, G.RUN = C, R, RUN
do
-- tier 1 Pawn, 2 Brute (2 pawns), 3 Giant (2 brutes), 4 Breaker (boss-breaker gem unit)
local T = {
    { name = "Pawn", pow = 1, hp = 1, s = 1.0, rad = 0.3, col = "b", cap = 110, area = 1.0 },
    { name = "Brute", pow = 3, hp = 2, s = 1.5, rad = 0.46, col = "v", cap = 32, area = 2.4 },
    { name = "Giant", pow = 8, hp = 4, s = 2.25, rad = 0.7, col = "y", cap = 12, area = 5.2 },
    { name = "Breaker", pow = 2, hp = 1, s = 1.2, rad = 0.36, col = "w", cap = 12, area = 1.4, boss = 4 },
}
G.T = T
local MESH = {}
local function mesh(col, p) local k = col .. p; local m = MESH[k]; if m == nil then m = mesh_of("man_" .. k) or false; MESH[k] = m end; return m end
local TEAMRGB = { b = { .3, .6, 1.4 }, v = { .7, .45, 1.4 }, y = { 1.4, 1.1, .4 }, w = { 1.4, .8, .3 }, r = { 1.4, .35, .3 }, g = { .9, .9, .95 } }
G.TEAMRGB = TEAMRGB

function C.power() local c = C.cnt; return c[1] + c[2] * 3 + c[3] * 8 + c[4] * 2 end
function C.total() local c = C.cnt; return c[1] + c[2] + c[3] + c[4] end
-- visible units -> one real unit each, except pawns past the cap (ratio)
function C.ratio(t) local v = 0; for _, u in ipairs(C.units) do if u.t == t then v = v + 1 end end; return v > 0 and C.cnt[t] / v or 1 end

local function new_unit(t, x, z)
    local n = F_get("man_" .. T[t].col .. "0")
    local u = { t = t, n = n, ox = x or 0, oz = z or 0, tx = 0, tz = 0, ph = rand() * 4, fr = -1, hp = T[t].hp, inv = 0, y = 0, born = 0 }
    n:set_scale(vec3(T[t].s, T[t].s, T[t].s)); n:set_rotation(vec3(0, 0, 0))
    return u
end
-- formation: biggest in the middle, phyllotaxis by area, squeezed into the floor strip
local GOLDEN = 2.39996
function C.formation()
    local list = C.units
    table.sort(list, function(a, b) local pa, pb = T[a.t].area, T[b.t].area; if pa ~= pb then return pa > pb end; return (a.id or 0) < (b.id or 0) end)
    local acc = 0
    local rmax = 0.1
    for i, u in ipairs(list) do
        local a = T[u.t].area
        acc = acc + a
        local r = sqrt(acc - a * 0.5) * 0.36
        local ang = i * GOLDEN
        u.fx, u.fz = cos(ang) * r, sin(ang) * r * 0.9
        rmax = max(rmax, r + T[u.t].rad)
    end
    C.rmax = rmax
end
function C.layout(hwmax)
    local k = 1
    if C.rmax > hwmax then k = hwmax / C.rmax end
    local kz = min(1 / k, 3.2)
    for _, u in ipairs(C.units) do u.tx, u.tz = u.fx * k, u.fz * kz end
    C.hw = min(C.rmax, hwmax); C.hd = C.rmax * kz
end

local function team_col(t) return TEAMRGB[T[t].col] end
-- bring the visible units in line with the real counts (spawn / vanish with a puff)
local seq_id = 0
function C.sync(fx, on_remove)
    local vis = { 0, 0, 0, 0 }
    for _, u in ipairs(C.units) do vis[u.t] = vis[u.t] + 1 end
    local changed = false
    for t = 1, 4 do
        local want = min(C.cnt[t], T[t].cap)
        while vis[t] < want do
            local a, r = rand() * 6.28, rand() * (C.rmax or 1) * 0.8
            local u = new_unit(t, cos(a) * r, sin(a) * r); seq_id = seq_id + 1; u.id = seq_id; u.born = 0.25
            C.units[#C.units + 1] = u; vis[t] = vis[t] + 1; changed = true
            if fx ~= false and rand() < 0.5 then local c = team_col(t); G.FX.puff(LX(C.cx + u.ox), 0.6, C.cz + u.oz, c, 0.6) end
        end
        while vis[t] > want do
            local bi
            for i = #C.units, 1, -1 do if C.units[i].t == t then bi = i; break end end
            if not bi then break end
            local u = table.remove(C.units, bi); vis[t] = vis[t] - 1; changed = true
            if on_remove then on_remove(u) else
                if fx ~= false and rand() < 0.6 then G.FX.puff(LX(C.cx + u.ox), 0.6, C.cz + u.oz, team_col(t), 0.6) end
                F_put("man_" .. T[t].col .. "0", u.n)
            end
        end
    end
    if changed or C.dirty then C.formation(); C.dirty = false end
end
-- damage in power units, pawns first (used by clashes, - gates, bosses)
function C.damage(p)
    local c = C.cnt
    while p > 0 and C.power() > 0 do
        if c[1] > 0 then local k = min(c[1], p); c[1] = c[1] - k; p = p - k
        elseif c[4] > 0 then c[4] = c[4] - 1; p = p - 2
        elseif c[2] > 0 then C.bdmg = (C.bdmg or 0) + p; local k = min(c[2], floor(C.bdmg / 3)); c[2] = c[2] - k; C.bdmg = C.bdmg - k * 3; p = 0
            if k == 0 then break end
        elseif c[3] > 0 then C.gdmg = (C.gdmg or 0) + p; local k = min(c[3], floor(C.gdmg / 8)); c[3] = c[3] - k; C.gdmg = C.gdmg - k * 8; p = 0
            if k == 0 then break end
        else break end
    end
    if c[2] == 0 then C.bdmg = 0 end
    if c[3] == 0 then C.gdmg = 0 end
end
-- remove one visible unit (trap / fall / bleed); real count drops by its share
function C.lose_unit(u, how, vx, vy, vz)
    for i, v in ipairs(C.units) do if v == u then table.remove(C.units, i); break end end
    local share = (u.t == 1) and max(1, round(C.cnt[1] / max(1, (C.vis1 or 1)))) or 1
    C.cnt[u.t] = max(0, C.cnt[u.t] - share)
    C.lost = (C.lost or 0) + share
    local wx, wz = C.cx + u.ox, C.cz + u.oz
    local d = { n = u.n, t = u.t, x = wx, y = u.y, z = wz, vx = vx or rr(-3, 3), vy = vy or rr(4, 7), vz = vz or rr(-1, 3), rx = 0, rz = 0, sp = rr(-500, 500), life = 0, how = how }
    C.dead[#C.dead + 1] = d
    if how == "fall" then d.vy = 0; d.vx = (u.ox > 0) and 1.5 or -1.5; d.vz = C.speed * 0.8 end
    C.dirty = true
    G.on_loss(u.t, how)
end
function C.hurt(u, how, vx, vy, vz)
    if u.inv > 0 then return false end
    if G.shield_t and G.shield_t > 0 then u.inv = 0.4; G.FX.sparks(LX(C.cx + u.ox), 0.8, C.cz + u.oz, 4, nil, 4, { .6, 1.2, 2 }); return false end
    if rand() < G.armor_chance() then u.inv = 0.5; G.FX.sparks(LX(C.cx + u.ox), 0.8, C.cz + u.oz, 4, nil, 4, { 1.4, 1.4, 1.4 }); G.popup_at("Blocked!", C.cx + u.ox, 2, C.cz + u.oz, { .8, .9, 1, 1 }, 0.8); return false end
    u.hp = u.hp - 1
    if u.hp <= 0 then C.lose_unit(u, how, vx, vy, vz); return true end
    u.inv = 0.8; G.sfx_hit()
    G.FX.sparks(LX(C.cx + u.ox), T[u.t].s, C.cz + u.oz, 8)
    return false
end

-- animation: swap run poses; units bob and lean; fallers tumble
local POSE = { "0", "1", "2", "3" }
function C.animate(dt, mode, ox, oz)
    local sp = C.speed
    C.vis1 = 0
    for _, u in ipairs(C.units) do
        if u.t == 1 then C.vis1 = C.vis1 + 1 end
        local s = T[u.t].s
        local fr
        if mode == "idle" then fr = "i" elseif mode == "cheer" then fr = (floor(G.t * 3 + u.ph) % 2 == 0) and "c" or "i"
        else u.ph = u.ph + dt * (2.2 + sp * 0.75) / s; fr = POSE[floor(u.ph) % 4 + 1] end
        if fr ~= u.fr then u.fr = fr; local m = mesh(T[u.t].col, fr); if m then u.n:set_mesh_ref(m) end end
        local bs = s
        if u.born > 0 then u.born = max(0, u.born - dt); bs = s * (1 - u.born / 0.25 * 0.8) end
        if u.inv > 0 then u.inv = u.inv - dt; if floor(u.inv * 12) % 2 == 0 then bs = bs * 1.12 end end
        -- run bob: lift at the flight phase of each stride (poses 1 and 3), a tiny hop when cheering
        local bob = 0
        if mode == "run" and sp > 0.5 then bob = abs(sin(u.ph * PI * 0.5)) * 0.085 * s
        elseif mode == "cheer" then bob = max(0, sin(G.t * 9.4 + u.ph * 2)) * 0.16 * s end
        u.n:set_position(vec3(LX(C.cx + u.ox), u.y + bob + (C.cy or 0), C.cz + u.oz))
        u.n:set_scale(vec3(bs, bs, bs))
        u.n:set_rotation(vec3(mode == "run" and 6 or 0, (u.yaw or 0) + clamp(-C.vx * 4, -25, 25), 0))
    end
    for i = #C.dead, 1, -1 do
        local d = C.dead[i]
        d.life = d.life + dt
        d.vy = d.vy - 22 * dt
        d.x, d.y, d.z = d.x + d.vx * dt, d.y + d.vy * dt, d.z + d.vz * dt
        d.rx = d.rx + d.sp * dt
        d.n:set_position(vec3(LX(d.x), d.y, d.z)); d.n:set_rotation(vec3(d.rx, d.rx * 0.5, d.rz))
        if d.how ~= "fall" and d.y < 0 and d.life < 1.0 and G.solid(G.floor_at(G.L, d.z), d.x) then
            d.y = 0; d.vy = -d.vy * 0.3; d.vx = d.vx * 0.6; d.vz = d.vz * 0.6
            if abs(d.vy) < 1 then d.life = 9 end
        end
        if d.y < -8.8 and not d.splash then d.splash = true; G.FX.spray(LX(d.x), -8.9, d.z, 0.5, 0.6); d.life = 9 end
        if d.life > 1.4 then
            if not d.splash then G.FX.puff(LX(d.x), d.y + 0.5, d.z, TEAMRGB[d.col or T[d.t].col], 0.7) end
            F_put("man_" .. (d.col or T[d.t].col) .. "0", d.n); table.remove(C.dead, i)
        end
    end
end
end
