local D, SIM, BOT = G.D, G.SIM, G.BOT
local save = D.new_save()
local verbose = os.getenv and os.getenv("SIMV")
-- SIMFRESH=1: every level from a brand-new save (no upgrades, rifle, catch-up assist active), no shop between tries
-- SIMBOT=center: never steers (stays in the middle) | SIMBOT=sloppy: steers late (0.4 s reaction) and imprecisely
local fresh = os.getenv("SIMFRESH")
local mode = os.getenv("SIMBOT") or "bot"
local function pilot(S)
    if mode == "center" then return 0 end
    if mode == "sloppy" then
        S._rt = (S._rt or 0) - 1 / 60
        if S._rt <= 0 then S._rt = 0.4; S._tx = BOT.target(S) + (math.random() - 0.5) * 1.6 end
        return S._tx
    end
    return BOT.target(S)
end
local function buy()
    -- greedy: cheapest upgrade among a priority list, then weapons
    local spent = true
    while spent do
        spent = false
        local best, bc = nil, 1e9
        for _, u in ipairs(D.UPG) do
            local l = save.up[u.key]
            local c = D.upg_cost(u, l)
            local w = ({ fire = 1, rate = 1, squad = 1.1, crit = 1.3, gate = 1.2, armor = 1.6, elite = 1.4, air = 1.8, ally = 1.8, bounty = 1.5 })[u.key]
            if l < u.max and c * w < bc and c <= save.coins then best, bc = u, c * w end
        end
        if best then save.coins = save.coins - D.upg_cost(best, save.up[best.key]); save.up[best.key] = save.up[best.key] + 1; spent = true end
    end
end
local tot = 0
for n = tonumber(os.getenv("SIMA") or 1), tonumber(os.getenv("SIMB") or #D.LEVELS) do
    local tries = 0
    while true do
        tries = tries + 1
        if fresh then save = D.new_save() end
        local S = SIM.start(n, save)
        local dt = 1 / 60
        local stats = { minu = 1e9, gates = 0 }
        while not S.over and S.t < 400 do
            local tx = pilot(S)
            if os.getenv("SIMW") then S.weapon = os.getenv("SIMW") end   -- SIMW=rocket etc: lock the loadout
            SIM.step(dt, { tx = tx, strike = true })
            for _, e in ipairs(S.events) do
                if e.k == "hurt" then stats.lost = (stats.lost or 0) + e.n end
                if e.k == "boss" then stats.bt = S.t end
                if e.k == "kill" and e.boss then stats.bd = (stats.bd or "") .. string.format("%.0fs ", S.t - (stats.bt or 0)) end
                if e.k == "gatetick" then stats.ticks = (stats.ticks or 0) + 1 end
                if e.k == "gate" then stats.gates = stats.gates + 1; if verbose then print(string.format("  t=%.0f gate %s v=%s mi=%s delta=%d worth=%d bodies=%d", S.t, e.g.k, tostring(e.g.v), tostring(e.g.mi), e.delta, SIM.worth(), SIM.units())) end end
                if verbose and (e.k == "weapon" or e.k == "ally" or e.k == "boss") then print("  t=" .. math.floor(S.t) .. " " .. e.k .. " " .. tostring(e.w or e.t or e.b)) end
                if verbose and e.k == "hurt" and e.n >= 3 then print(string.format("  t=%.0f hurt %d worth by %s worth=%d", S.t, e.n, tostring(e.why), SIM.worth())) end
            end
            S.events = {}
            if S.t % 10 < dt and verbose then print(string.format("  t=%3.0f worth=%d bodies=%d sol=%d vet=%d hvy=%d fp=%.0f dps=%.0f foes=%d w=%s", S.t, SIM.worth(), SIM.units(), S.sol, S.vet, S.hvy, SIM.firepower(), S.dps or 0, #S.foes, S.weapon)) end
        end
        local coins = math.floor(S.coins)
        if S.over ~= "win" then coins = math.floor(coins * 0.5) end
        save.coins = save.coins + coins
        tot = tot + coins
        print(string.format("L%-2d %-15s try %d: %-4s t=%3.0fs peak=%4d surv=%4d bodies=%3d/%3d rb=%.2f rw=%.2f fp=%5.0f coins=%4d stars=%s boss=%s kills=%d airs=%d w=%s lost=%d gdmg=%d ticks=%d bossfight=%s",
            n, D.LEVELS[n].name, tries, tostring(S.over), S.t, S.peak, SIM.worth(), SIM.units(), S.peakb or 0, SIM.units() / math.max(1, S.peakb or 1), SIM.worth() / math.max(1, S.peak), SIM.firepower(), coins, tostring(S.stars), S.boss and math.floor(S.boss.hp) .. "/" .. math.floor(S.boss.maxhp) or "-", S.kills, S.airs, S.weapon, stats.lost or 0, S.gdmg or 0, stats.ticks or 0, stats.bd or "-"))
        if not fresh then buy() end
        if S.over == "win" or tries >= 6 then break end
    end
end
local ups = {}
for k, v in pairs(save.up) do ups[#ups + 1] = k .. "=" .. v end
print("upgrades: " .. table.concat(ups, " ") .. "  coins left " .. save.coins)
