-- headless campaign run: every level from a fresh save with several player autopilots
local D, SIM, BOT = G.D, G.SIM, G.BOT
local bots = {}
for b in (os.getenv("SIMBOT") or "skilled,casual,lazy,idle"):gmatch("[^,]+") do bots[#bots + 1] = b end
local seeds = tonumber(os.getenv("SIMSEEDS") or "3")
local only = tonumber(os.getenv("SIMLVL") or "0")
local verbose = os.getenv("SIMV") == "1"
local out = {}
for li = 1, #D.LEVELS do
    if only == 0 or only == li then
        local L = D.LEVELS[li]
        local line = string.format("L%-2d %-18s par %3d |", li, L.name, L.par)
        for _, b in ipairs(bots) do
            local wins, ts, stars = 0, {}, {}
            for seed = 1, seeds do
                math.randomseed(seed * 101 + li)
                local S = SIM.new(li, D.new_save(), { mode = tonumber(os.getenv("SIMMODE") or "2") })
                BOT.reset()
                local dt = D.STEP
                while not S.over and S.t < 900 do
                    BOT.update(S, dt, b)
                    SIM.step(S, dt)
                end
                if S.win then wins = wins + 1; ts[#ts + 1] = math.floor(S.t); stars[#stars + 1] = D.stars_for(S.t, L.par) end
                if verbose then
                    local own = {}
                    for f = 1, 5 do own[#own + 1] = S.F[f].nreg end
                    print(string.format("  L%d %s seed %d: %s t=%.0f regions=%s clash=%d", li, b, seed, S.win and "WIN" or (S.over and "LOSE" or "TIMEOUT"), S.t, table.concat(own, "/"), S.stat.clash))
                end
            end
            line = line .. string.format(" %s %d/%d %s%s |", b, wins, seeds, #ts > 0 and ("t=" .. table.concat(ts, ",")) or "", #stars > 0 and (" *" .. table.concat(stars, ",")) or "")
        end
        print(line)
        out[#out + 1] = line
    end
end
