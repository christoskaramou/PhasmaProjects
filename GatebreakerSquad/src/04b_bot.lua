------------------------------------------------------------------ 04b_bot: autopilot (title-screen attract run, harness, tools/simtest)
-- Fire goes straight, so the bot steers: it scores candidate lane positions by what the squad's fire strip would
-- cover (foes it can kill in time, the gate it wants, crates/containers, the boss) minus what would hit it
-- (foes it can't kill before contact, walls, barrels, boss strike markers), then heads for the best one.
local D, SIM = G.D, G.SIM
local BOT = {}
G.BOT = BOT
local abs, min, max = math.abs, math.min, math.max
local function cover(x, half, ox, r) -- 0..1: how much of a target of radius r sits inside the fire strip
    local d = abs(ox - x) - half - r
    if d <= -0.3 then return 1 elseif d >= 0.3 then return 0 end
    return (0.3 - d) / 0.6
end
local function gate_value(g, S, units, gain)
    if g.k == "add" then return g.v + gain / g.per
    elseif g.k == "trap" then
        if g.flip then return g.v end
        local v = g.v + gain / g.per
        return (v > g.maxv) and -2 * v or v
    elseif g.k == "mul" then local mi = min(#D.MUL, g.mi + math.floor(gain / g.per)); return units * (D.MUL[mi] - 1)
    elseif g.k == "lock" then return (g.hp < gain) and units * 2 or -1
    elseif g.k == "merge" then return units * 0.05 end   -- worth unchanged, small firepower/toughness gain
    return (g.v + gain / g.per * 5) * units / 40
end
function BOT.target(S)
    local units = SIM.units()
    local nvis = min(units, D.VIS)
    local F = SIM.formation(max(1, nvis))
    local lim = D.LANE - F.R * 0.6
    local half = max(0.1, F.R - 0.45)
    local dps = S.dps or units
    local v = S.v or D.SPEED
    -- candidates
    local nc = 33
    local best, bs = S.x, -1e18
    -- gate row: work out each gate's value once, assuming all fire goes into it from now on
    local row, rz = nil, 1e9
    for _, g in ipairs(S.gates) do if not g.passed and g.z > 0.3 and g.z < 75 and g.z < rz then rz, row = g.z, g.row end end
    local gl = {}
    if row then
        local tarr = rz / max(0.1, v)
        for _, g in ipairs(S.gates) do
            if g.row == row then
                local val = gate_value(g, S, SIM.worth(), dps * tarr * 0.75 * S.gatek)   -- gates scale worth
                local wv = 2 - min(1.5, rz / 50) -- the closer the row, the more it matters
                gl[#gl + 1] = { g = g, val = val, w = wv }
            end
        end
    end
    local share = min(1, 0.95 / (2 * half + 0.74)) -- fraction of the squad's fire one runner-size target soaks up
    for c = 0, nc - 1 do
        local x = -lim + 2 * lim * c / (nc - 1)
        local sc = -0.08 * abs(x - S.x)
        for _, f in ipairs(S.foes) do
            if not f.dead and f.z > 0 and f.z < 50 then
                local tz = f.z / max(0.5, v + (f.spd or 2))
                local cv = cover(x, half, f.x, f.r)
                local ehp = f.hp + (f.shield or 0)
                if f.boss then
                    if f.arrived then sc = sc + 12 * cv end
                else
                    local kill = min(1, dps * share * max(1, f.r * 2) * tz / max(1, ehp))
                    local urg = (f.z < 30) and 1 or 0.5
                    sc = sc + cv * (kill * (f.dmg * 1.4 + f.coin * 0.15) + 0.2) * urg
                    -- contact: will it reach the squad? steering foes close in on you, lane keepers don't
                    local reach = (f.lane or f.boss) and 0 or (f.steer or 0) * min(tz, (f.aggro or 22) / max(1, v + (f.spd or 2)))
                    local dx = abs(f.x - x) - (F.R + f.r * 0.8) - reach
                    if dx < 0.4 and f.z < 28 then sc = sc - f.dmg * (1 - cv * kill) * 1.6 * urg end
                end
            end
        end
        for _, gg in ipairs(gl) do
            local g = gg.g
            -- the gate we'd pass is the nearest one within 2.4 m
            local near, nd = nil, 1e9
            for _, h in ipairs(gl) do local d = abs(h.g.x - x); if d < nd then nd, near = d, h end end
            if near == gg and nd < 2.4 then sc = sc + gg.val * gg.w * (1 - nd / 6) end
            if gg.val > 0 then sc = sc + gg.w * 0.6 * cover(x, half, g.x, 2.2) end
        end
        for _, p in ipairs(S.props) do
            if not p.dead and p.z > 0 and p.z < 55 then
                local cv = cover(x, half, p.x, p.hw - 0.2)
                if p.t == "crate" then sc = sc + cv * 3
                elseif p.t == "container" then sc = sc + cv * 6
                elseif p.t == "barricade" then
                    sc = sc + cv * 0.8
                    if p.z < 26 and abs(p.x - x) < F.R + p.hw + 0.3 then sc = sc - math.ceil(p.hp / (6 * S.hpk)) * (p.z < 14 and 1.5 or 0.6) end
                elseif p.t == "barrel" or p.t == "cryo" then
                    if p.z < 22 and abs(p.x - x) < F.R + p.hw + 0.4 then sc = sc - (p.t == "barrel" and 6 or 1) end
                end
            end
        end
        for _, mk in ipairs(S.markers) do
            local dx = abs(x - mk.x)
            if dx < mk.r + F.R * 0.5 + 0.4 then sc = sc - mk.dmg * 4 elseif dx < mk.r + F.R + 0.4 then sc = sc - mk.dmg * 1.5 end
        end
        if sc > bs then bs, best = sc, x end
    end
    return best
end
