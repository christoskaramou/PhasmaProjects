-- player autopilots for the headless balance test (never loaded by the game)
local D, SIM, AI = G.D, G.SIM, G.AI
local BOT = {}
G.BOT = BOT
D.PERS.skilled = { name = "Skilled", iv = 1.0, keep = 0.15, pbias = 1.0, nbias = 1.0, acts = 2, reach = 16, vult = 0.8, abil = true }
D.PERS.casual = { name = "Casual", iv = 2.5, keep = 0.3, pbias = 1.0, nbias = 1.2, acts = 1, reach = 12, vult = 0 }
BOT.t = 0
function BOT.reset() BOT.t = 0.5 end
function BOT.update(S, dt, kind)
    if kind == "idle" then return end
    BOT.t = BOT.t - dt
    if BOT.t > 0 then return end
    local F = S.F[1]
    if kind == "skilled" or kind == "casual" then
        F.ai = kind
        BOT.t = D.PERS[kind].iv
        AI.think(S, F)
        F.ai = nil
    elseif kind == "lazy" then
        -- every 6 s: dump one region's troops into the nearest region it does not own
        BOT.t = 6
        local mine = {}
        for _, r in ipairs(S.R) do if r.active and r.owner == 1 then mine[#mine + 1] = r end end
        if #mine == 0 then return end
        local m = mine[math.random(#mine)]
        local best, bd
        for _, r in ipairs(S.R) do if r.active and r.owner ~= 1 then local d = SIM.dist(S, m.i, r.i); if not bd or d < bd then best, bd = r, d end end end
        if best then SIM.send(S, 1, { m.i }, best.i, 1) end
    end
end
return BOT
