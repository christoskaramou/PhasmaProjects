-- bot.lua — Stockfish opponent, spoken to over UCI.
--
-- The Lua state opens only base/math/string/table/coroutine, so a script has no io and no os
-- and cannot start a process. The engine's `proc` binding (Runtime/Code/Script/Bindings/Process)
-- is what makes this possible: it spawns one child under a kill-on-close job object and gives
-- Lua a non-blocking line reader.
--
-- Everything here is a state machine polled once per frame. Nothing ever blocks: a `go` is fired
-- and forgotten, and `poll()` returns the move only once Stockfish has printed `bestmove`.

local bot = {}

local EXE = "Bots/stockfish.exe"
local FILES = "abcdefgh"

-- Strength is ONE number, the Elo you ask for. Stockfish cannot play under 1320 — that IS Skill
-- Level 0, and random play is already about 1200 — so anything below the floor is delivered by
-- blundering on top of a 1320 engine:
--   engine Elo = max(asked, 1320)
--   blunder    = how far below the floor you asked, as a fraction of the span down to MIN
--
-- Below the floor, play searches run MultiPV 3 and a blunder roll picks the 2nd or 3rd
-- PV instead of a uniformly random legal move.
bot.MIN_ELO = 400
bot.FLOOR = 1320   -- Stockfish's own minimum, reported by `option name UCI_Elo ... min 1320`
bot.MAX_ELO = 3190
bot.MAX_MOVETIME = 3000 -- ms, Max only: unlimited search time per move

local elo = 1500

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

function bot.elo() return elo end
function bot.engine_elo() return math.max(elo, bot.FLOOR) end
function bot.blunder() return clamp((bot.FLOOR - elo) / (bot.FLOOR - bot.MIN_ELO), 0.0, 0.8) end
-- True at the very top of the range: play unrestricted rather than at a nominal 3190.
function bot.unlimited() return elo >= bot.MAX_ELO end

-- Stockfish 18 search.h: Skill(uci_elo) cubic, clamped to [0, 19]. Pick depth is 1+floor(level).
function bot.skill_level()
    local e = (bot.engine_elo() - bot.FLOOR) / (bot.MAX_ELO - bot.FLOOR)
    return clamp(((37.2473 * e - 40.8525) * e + 22.2943) * e - 0.311438, 0.0, 19.0)
end

function bot.search_depth()
    if bot.unlimited() then return nil end -- Max searches by time, not depth
    return 1 + math.floor(bot.skill_level())
end

local ready       -- readyok seen, options applied
local pending     -- generation tag of the play search in flight, or nil
local generation  -- bumped whenever the position changes under a running search
local ana_pending -- generation tag of the analysis search in flight, or nil
local ana_queue   -- { moves, depth } waiting for the proc slot, or nil
local ana_info    -- last info line parsed for the live analysis search
local ana_result  -- latest payload for bot.analysis(), or nil
local inflight = {} -- FIFO of { gen, kind }: UCI answers one bestmove per go, in go order
local play_pvs    -- MultiPV lines for the live play search, indexed by multipv n

local function send(line)
    return proc.write(line .. "\n")
end

function bot.available()
    return proc ~= nil and proc.start ~= nil
end

function bot.running()
    return bot.available() and proc.is_running()
end

function bot.is_ready() return ready == true end
function bot.thinking() return pending ~= nil end
function bot.analysing() return ana_pending ~= nil or ana_queue ~= nil end

-- Start (or restart) the engine at an Elo. Returns false plus a reason if the binary is missing.
function bot.start(target_elo)
    if not bot.available() then return false, "no proc binding in this build" end
    elo = clamp(math.floor(target_elo or elo), bot.MIN_ELO, bot.MAX_ELO)
    ready, pending, generation = false, nil, 0
    ana_pending, ana_queue, ana_info, ana_result = nil, nil, nil, nil
    inflight, play_pvs = {}, {}

    local ok, err = proc.start(EXE)
    if not ok then return false, err end
    send("uci")
    send("isready")
    return true
end

-- Start the engine process for analysis even when no bot plays. A live process is reused
-- untouched; only a dead slot boots fresh.
function bot.ensure()
    if bot.running() then return true end
    if not bot.available() then return false, "no proc binding in this build" end
    ready, pending, generation = false, nil, 0
    ana_pending, ana_queue, ana_info, ana_result = nil, nil, nil, nil
    inflight, play_pvs = {}, {}

    local ok, err = proc.start(EXE)
    if not ok then return false, err end
    send("uci")
    send("isready")
    return true
end

function bot.shutdown()
    if bot.available() then proc.stop() end
    ready, pending = false, nil
    ana_pending, ana_queue, ana_info, ana_result = nil, nil, nil, nil
    inflight, play_pvs = {}, {}
end

-- Push the current Elo to the engine. Called once readyok arrives, and again on every change.
local function apply_elo()
    if bot.unlimited() then
        send("setoption name UCI_LimitStrength value false")
    else
        send("setoption name UCI_LimitStrength value true")
        send("setoption name UCI_Elo value " .. bot.engine_elo())
    end
    send("isready")
end

-- Dragging the Elo field calls this every frame, so it only talks to the engine when the clamped
-- value actually moved.
function bot.set_elo(target_elo)
    local next_elo = clamp(math.floor(target_elo), bot.MIN_ELO, bot.MAX_ELO)
    if next_elo == elo then return elo end
    elo = next_elo
    if ready then apply_elo() end
    return elo
end

-- `moves` is the game so far in coordinate notation ("e2e4 e7e5 ..."). Returns the generation
-- tag of this search, which poll() checks so a rewind mid-think cannot play a stale move.
function bot.think(moves)
    if not (ready and bot.running()) then return nil end
    if ana_pending then
        send("stop") -- play never waits on analysis; the stale bestmove drops by generation
        ana_pending = nil
    end
    generation = generation + 1
    pending = generation
    inflight[#inflight + 1] = { gen = generation, kind = "play" }
    play_pvs = {}
    apply_elo() -- UCI options persist in the process and analysis turns the limiter off
    send("setoption name MultiPV value " .. ((bot.blunder() > 0) and "3" or "1"))
    send("position startpos" .. ((#moves > 0) and (" moves " .. moves) or ""))
    if bot.unlimited() then send("go movetime " .. bot.MAX_MOVETIME)
    else send("go depth " .. bot.search_depth()) end
    return pending
end

-- Fire the queued analysis. Its options are re-sent before the go for the same reason
-- think() re-applies the Elo: the two modes share one process and must not bleed.
local function start_ana()
    local q = ana_queue
    ana_queue = nil
    generation = generation + 1
    ana_pending = generation
    ana_info = {}
    ana_result = { done = false, depth = 0 }
    inflight[#inflight + 1] = { gen = generation, kind = "ana" }
    send("setoption name UCI_LimitStrength value false")
    send("setoption name MultiPV value 1")
    send("position startpos" .. ((#q.moves > 0) and (" moves " .. q.moves) or ""))
    send("go depth " .. q.depth)
end

-- Droppable analysis request for the position after `moves` (think()'s coordinate string).
-- A play search always wins the single proc slot: while one is pending this only queues,
-- latest position wins, and poll() fires it after the play bestmove arrives.
function bot.analyse(moves, depth)
    ana_queue = { moves = moves or "", depth = depth or 15 }
    if not (ready and bot.running()) or pending then return end
    if ana_pending then
        send("stop") -- superseded mid-search; the stale bestmove drops by generation
        ana_pending = nil
    end
    start_ana()
end

-- Latest analysis result, nil until one ran. cp/mate are from the side to move's view
-- (UCI convention) — the caller fixes perspective.
function bot.analysis()
    return ana_result
end

-- Abandon whatever is being searched (play or analysis). Any bestmove still in flight
-- is discarded because its generation no longer matches.
function bot.abort()
    ana_queue = nil
    if pending or ana_pending then
        send("stop")
        pending, ana_pending = nil, nil
        generation = generation + 1
    end
end

-- Drain every line waiting on the pipe — Stockfish emits many `info` lines per search and
-- reading one per frame would back the pipe up and delay `bestmove` by seconds.
-- Returns the move in coordinate notation once the search that is still current finishes.
function bot.poll()
    if not bot.available() then return nil end
    local move
    for _ = 1, 512 do
        local line = proc.read_line()
        if not line then break end
        if line == "readyok" then
            if not ready then
                ready = true
                send("ucinewgame")
                apply_elo()
            end
        elseif line:sub(1, 8) == "bestmove" then
            local mv = line:match("^bestmove%s+(%S+)")
            if mv == "(none)" then mv = nil end
            local tag = table.remove(inflight, 1)
            if tag and tag.kind == "play" and pending and tag.gen == pending then
                move = mv
                if move and bot.blunder() > 0 then
                    local alts = {}
                    for i = 2, 3 do
                        if play_pvs[i] and play_pvs[i].move and play_pvs[i].move ~= mv then
                            alts[#alts + 1] = play_pvs[i].move
                        end
                    end
                    if #alts > 0 and math.random() < bot.blunder() then
                        move = alts[math.random(#alts)]
                    end
                end
                pending = nil
            elseif tag and tag.kind == "ana" and ana_pending and tag.gen == ana_pending then
                ana_result = { done = true, cp = ana_info.cp, mate = ana_info.mate,
                               best = mv or ana_info.best, depth = ana_info.depth or 0 }
                ana_pending = nil
            end
            -- any other tag is a stopped search's reply: dropped
        elseif line:sub(1, 5) == "info " then
            -- info lines belong to the search executing now, which is the oldest go in flight
            local tag = inflight[1]
            if tag and tag.kind == "play" and pending and tag.gen == pending then
                local mpv = tonumber(line:match(" multipv (%d+)")) or 1
                local pv = line:match(" pv (%S+)")
                if pv then
                    play_pvs[mpv] = {move = pv, cp = tonumber(line:match(" score cp (%-?%d+)")),
                                     mate = tonumber(line:match(" score mate (%-?%d+)"))}
                end
            elseif tag and tag.kind == "ana" and ana_pending and tag.gen == ana_pending then
                local d = line:match(" depth (%d+)")
                local cp = line:match(" score cp (%-?%d+)")
                local mate = line:match(" score mate (%-?%d+)")
                local best = line:match(" pv (%S+)")
                if d and best and (cp or mate) then
                    ana_info = { depth = tonumber(d), cp = tonumber(cp),
                                 mate = tonumber(mate), best = best }
                    ana_result = { done = false, cp = ana_info.cp, mate = ana_info.mate,
                                   best = best, depth = ana_info.depth }
                end
            end
        end
    end
    if ana_queue and ready and bot.running() and not pending and not ana_pending then
        start_ana()
    end
    return move
end

-- Coordinate notation for one recorded ply, which is exactly what `position ... moves` wants.
function bot.uci_move(rec)
    return FILES:sub(rec.from_f + 1, rec.from_f + 1) .. rec.from_r ..
           FILES:sub(rec.to_f + 1, rec.to_f + 1) .. rec.to_r ..
           (rec.promo and rec.promo:lower() or "")
end

return bot
