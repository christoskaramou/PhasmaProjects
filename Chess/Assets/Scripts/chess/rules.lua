-- rules.lua — full legal chess: move generation, check/mate/stalemate, castling,
-- en passant, promotion. Pure logic; it never touches the scene. `board.lua` owns
-- geometry, this module owns legality, and the two meet only through square indices.
--
-- State:
--   board[rank][file] = {kind = "K|Q|R|B|N|P", color = "W|B", piece = <registry entry>}
--   turn      "W" | "B"
--   castling  {WK, WQ, BK, BQ}  -- true while that rook+king are both unmoved
--   ep        {file, rank} | nil -- square a pawn may be captured ON by en passant
--   halfmove  plies since the last capture or pawn move (50-move rule)
--
-- Moves are made with make()/unmake() rather than copied states: legality filtering
-- has to play every pseudo-legal move to test for check, and a search-based opponent
-- would need the same primitive later.

local R = {}

local ROOK_DIRS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
local BISHOP_DIRS = {{1, 1}, {1, -1}, {-1, 1}, {-1, -1}}
local QUEEN_DIRS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}
local KNIGHT_HOPS = {{1, 2}, {2, 1}, {2, -1}, {1, -2}, {-1, -2}, {-2, -1}, {-2, 1}, {-1, 2}}

local function on_board(f, r) return f >= 0 and f <= 7 and r >= 1 and r <= 8 end
local function enemy(color) return color == "W" and "B" or "W" end

-- Pawns advance toward rank 8 for white, rank 1 for black.
local function forward(color) return color == "W" and 1 or -1 end
local function home_rank(color) return color == "W" and 2 or 7 end
local function last_rank(color) return color == "W" and 8 or 1 end

function R.new(pieces)
    local board = {}
    for r = 1, 8 do board[r] = {} end
    for _, p in ipairs(pieces) do
        if p.file then board[p.rank][p.file] = {kind = p.kind, color = p.color, piece = p} end
    end
    return {
        board = board,
        turn = "W",
        castling = {WK = true, WQ = true, BK = true, BQ = true},
        ep = nil,
        halfmove = 0,
    }
end

function R.at(state, f, r)
    if not on_board(f, r) then return nil end
    return state.board[r][f]
end

-- --- attack detection ------------------------------------------------------
-- True when `color` attacks (f, r). Used for check tests and for castling, which
-- may not pass the king through an attacked square.
function R.attacked(state, f, r, color)
    local dir = forward(color)
    for _, df in ipairs({-1, 1}) do
        local sq = R.at(state, f + df, r - dir) -- a pawn one step "behind" attacks here
        if sq and sq.color == color and sq.kind == "P" then return true end
    end

    for _, h in ipairs(KNIGHT_HOPS) do
        local sq = R.at(state, f + h[1], r + h[2])
        if sq and sq.color == color and sq.kind == "N" then return true end
    end

    for _, d in ipairs(QUEEN_DIRS) do
        local sq = R.at(state, f + d[1], r + d[2])
        if sq and sq.color == color and sq.kind == "K" then return true end
    end

    local rays = {{ROOK_DIRS, "R"}, {BISHOP_DIRS, "B"}}
    for _, ray in ipairs(rays) do
        for _, d in ipairs(ray[1]) do
            local nf, nr = f + d[1], r + d[2]
            while on_board(nf, nr) do
                local sq = state.board[nr][nf]
                if sq then
                    if sq.color == color and (sq.kind == ray[2] or sq.kind == "Q") then return true end
                    break
                end
                nf, nr = nf + d[1], nr + d[2]
            end
        end
    end
    return false
end

function R.find_king(state, color)
    for r = 1, 8 do
        for f = 0, 7 do
            local sq = state.board[r][f]
            if sq and sq.color == color and sq.kind == "K" then return f, r end
        end
    end
end

function R.in_check(state, color)
    local f, r = R.find_king(state, color)
    if not f then return false end
    return R.attacked(state, f, r, enemy(color))
end

-- --- pseudo-legal generation ----------------------------------------------
local function add(moves, state, from_f, from_r, to_f, to_r, extra)
    if not on_board(to_f, to_r) then return false end
    local target = state.board[to_r][to_f]
    local mover = state.board[from_r][from_f]
    if target and target.color == mover.color then return false end
    local move = {
        from_f = from_f, from_r = from_r, to_f = to_f, to_r = to_r,
        kind = mover.kind, color = mover.color, capture = target,
    }
    if extra then for k, v in pairs(extra) do move[k] = v end end
    moves[#moves + 1] = move
    return target == nil -- caller uses this to stop sliding
end

local function slide(moves, state, f, r, dirs)
    for _, d in ipairs(dirs) do
        local nf, nr = f + d[1], r + d[2]
        while add(moves, state, f, r, nf, nr) do
            nf, nr = nf + d[1], nr + d[2]
        end
    end
end

local function pawn_moves(moves, state, f, r, color)
    local dir = forward(color)
    local promo = (r + dir == last_rank(color))

    local function push(to_f, to_r, extra)
        if promo then
            for _, k in ipairs({"Q", "R", "B", "N"}) do
                local e = {promo = k}
                if extra then for kk, vv in pairs(extra) do e[kk] = vv end end
                add(moves, state, f, r, to_f, to_r, e)
            end
        else
            add(moves, state, f, r, to_f, to_r, extra)
        end
    end

    if not R.at(state, f, r + dir) then
        push(f, r + dir)
        -- Double step only from the home rank and only through an empty square.
        if r == home_rank(color) and not R.at(state, f, r + 2 * dir) then
            add(moves, state, f, r, f, r + 2 * dir, {double_step = true})
        end
    end

    for _, df in ipairs({-1, 1}) do
        local target = R.at(state, f + df, r + dir)
        if target and target.color ~= color then
            push(f + df, r + dir)
        elseif state.ep and state.ep.file == f + df and state.ep.rank == r + dir then
            -- En passant: the captured pawn sits beside us, not on the target square.
            local victim = R.at(state, f + df, r)
            if victim and victim.color ~= color and victim.kind == "P" then
                add(moves, state, f, r, f + df, r + dir, {ep_capture = victim})
                moves[#moves].capture = victim
            end
        end
    end
end

local function castle_moves(moves, state, f, r, color)
    if R.in_check(state, color) then return end
    local rights = {{"K", 1, {5, 6}, 7}, {"Q", -1, {3, 2}, 0}}
    for _, c in ipairs(rights) do
        local side, step, path, rook_file = c[1], c[2], c[3], c[4]
        if state.castling[color .. side] then
            local rook = R.at(state, rook_file, r)
            if rook and rook.kind == "R" and rook.color == color then
                local clear = true
                -- Every square between king and rook must be empty...
                local lo, hi = math.min(4, rook_file) + 1, math.max(4, rook_file) - 1
                for ff = lo, hi do
                    if state.board[r][ff] then clear = false break end
                end
                -- ...and the two squares the king crosses must be unattacked.
                for _, ff in ipairs(path) do
                    if R.attacked(state, ff, r, enemy(color)) then clear = false break end
                end
                if clear then
                    add(moves, state, f, r, 4 + 2 * step, r,
                        {castle = side, rook_from = rook_file, rook_to = 4 + step})
                end
            end
        end
    end
end

function R.pseudo_moves(state, color)
    local moves = {}
    for r = 1, 8 do
        for f = 0, 7 do
            local sq = state.board[r][f]
            if sq and sq.color == color then
                if sq.kind == "P" then
                    pawn_moves(moves, state, f, r, color)
                elseif sq.kind == "N" then
                    for _, h in ipairs(KNIGHT_HOPS) do add(moves, state, f, r, f + h[1], r + h[2]) end
                elseif sq.kind == "R" then
                    slide(moves, state, f, r, ROOK_DIRS)
                elseif sq.kind == "B" then
                    slide(moves, state, f, r, BISHOP_DIRS)
                elseif sq.kind == "Q" then
                    slide(moves, state, f, r, QUEEN_DIRS)
                elseif sq.kind == "K" then
                    for _, d in ipairs(QUEEN_DIRS) do add(moves, state, f, r, f + d[1], r + d[2]) end
                    castle_moves(moves, state, f, r, color)
                end
            end
        end
    end
    return moves
end

-- --- make / unmake ---------------------------------------------------------
function R.make(state, m)
    local b = state.board
    local undo = {
        castling = {WK = state.castling.WK, WQ = state.castling.WQ,
                    BK = state.castling.BK, BQ = state.castling.BQ},
        ep = state.ep, halfmove = state.halfmove,
        moved = b[m.from_r][m.from_f], captured = b[m.to_r][m.to_f],
    }

    b[m.from_r][m.from_f] = nil
    if m.ep_capture then
        undo.ep_victim = b[m.from_r][m.to_f]
        b[m.from_r][m.to_f] = nil
    end
    b[m.to_r][m.to_f] = undo.moved
    if m.promo then b[m.to_r][m.to_f] = {kind = m.promo, color = m.color, piece = undo.moved.piece} end
    if m.castle then
        b[m.from_r][m.rook_to] = b[m.from_r][m.rook_from]
        b[m.from_r][m.rook_from] = nil
    end

    -- Rights are lost when the king or a rook leaves its home square, and also when
    -- a rook is captured on its home square.
    if m.kind == "K" then
        state.castling[m.color .. "K"] = false
        state.castling[m.color .. "Q"] = false
    end
    local function drop_rook_right(f, r)
        if r == 1 then
            if f == 0 then state.castling.WQ = false elseif f == 7 then state.castling.WK = false end
        elseif r == 8 then
            if f == 0 then state.castling.BQ = false elseif f == 7 then state.castling.BK = false end
        end
    end
    if m.kind == "R" then drop_rook_right(m.from_f, m.from_r) end
    if undo.captured and undo.captured.kind == "R" then drop_rook_right(m.to_f, m.to_r) end

    state.ep = m.double_step and {file = m.from_f, rank = (m.from_r + m.to_r) / 2} or nil
    state.halfmove = (m.kind == "P" or m.capture) and 0 or state.halfmove + 1
    state.turn = enemy(state.turn)
    return undo
end

function R.unmake(state, m, undo)
    local b = state.board
    b[m.from_r][m.from_f] = undo.moved
    b[m.to_r][m.to_f] = m.ep_capture and nil or undo.captured
    if m.ep_capture then b[m.from_r][m.to_f] = undo.ep_victim end
    if m.castle then
        b[m.from_r][m.rook_from] = b[m.from_r][m.rook_to]
        b[m.from_r][m.rook_to] = nil
    end
    state.castling = undo.castling
    state.ep = undo.ep
    state.halfmove = undo.halfmove
    state.turn = enemy(state.turn)
end

-- --- legality --------------------------------------------------------------
-- A pseudo-legal move is legal iff it does not leave your own king in check.
function R.legal_moves(state, from_f, from_r)
    local color = state.turn
    local legal = {}
    for _, m in ipairs(R.pseudo_moves(state, color)) do
        if not from_f or (m.from_f == from_f and m.from_r == from_r) then
            local undo = R.make(state, m)
            if not R.in_check(state, color) then legal[#legal + 1] = m end
            R.unmake(state, m, undo)
        end
    end
    return legal
end

function R.status(state)
    if #R.legal_moves(state) == 0 then
        return R.in_check(state, state.turn) and "checkmate" or "stalemate"
    end
    if state.halfmove >= 100 then return "draw50" end
    -- Threefold is counted in game.lua against history keys: legality probing
    -- make/unmake would poison any tally kept here.
    return "playing"
end

-- --- position identity / material -----------------------------------------
R.king_square = R.find_king -- public name for callers that want "where is the king"

-- Identity string for repetition detection: 64 squares (uppercase = white,
-- lowercase = black, "-" empty) + side to move + castling rights + en-passant file.
-- Excludes halfmove/counters on purpose: repetition compares positions, not clocks.
-- ponytail: ep file is included unconditionally, slightly stricter than FIDE
-- (which only counts ep when the capture is actually legal).
function R.position_key(state)
    local parts = {}
    for r = 1, 8 do
        for f = 0, 7 do
            local sq = state.board[r][f]
            parts[#parts + 1] = sq and (sq.color == "W" and sq.kind or sq.kind:lower()) or "-"
        end
    end
    parts[#parts + 1] = state.turn
    local c = state.castling
    local rights = (c.WK and "K" or "") .. (c.WQ and "Q" or "") ..
                   (c.BK and "k" or "") .. (c.BQ and "q" or "")
    parts[#parts + 1] = rights == "" and "-" or rights
    parts[#parts + 1] = state.ep and tostring(state.ep.file) or "-"
    return table.concat(parts)
end

-- Dead-position draw: K vs K, K+B vs K, K+N vs K, and K+B vs K+B with both
-- bishops on the same square color. Anything else can still mate in theory.
function R.insufficient(state)
    local bishops, knights = {}, 0
    for r = 1, 8 do
        for f = 0, 7 do
            local sq = state.board[r][f]
            if sq then
                local k = sq.kind
                if k == "P" or k == "R" or k == "Q" then return false end
                if k == "N" then knights = knights + 1 end
                if k == "B" then bishops[#bishops + 1] = {color = sq.color, shade = (f + r) % 2} end
            end
        end
    end
    local b = #bishops
    if knights + b == 0 then return true end            -- K vs K
    if b == 0 and knights == 1 then return true end     -- K+N vs K
    if knights > 0 then return false end
    if b == 1 then return true end                      -- K+B vs K
    return b == 2 and bishops[1].color ~= bishops[2].color
        and bishops[1].shade == bishops[2].shade        -- KB vs KB, same shade
end

-- FIDE 6.9: flag is a draw if `color` cannot checkmate by any series of legal moves.
-- Q/R/P can always mate; two minors can; a single minor only mates if the opponent
-- still has material to get in the way. Lone king never can.
function R.cannot_mate(state, color)
    local mine, theirs = {P = 0, N = 0, B = 0, R = 0, Q = 0}, {P = 0, N = 0, B = 0, R = 0, Q = 0}
    for r = 1, 8 do
        for f = 0, 7 do
            local sq = state.board[r][f]
            if sq and sq.kind ~= "K" then
                local bag = (sq.color == color) and mine or theirs
                bag[sq.kind] = bag[sq.kind] + 1
            end
        end
    end
    if mine.Q + mine.R + mine.P > 0 then return false end
    local minors = mine.N + mine.B
    if minors >= 2 then return false end
    if minors == 0 then return true end
    return (theirs.P + theirs.N + theirs.B + theirs.R + theirs.Q) == 0
end

-- Match a SAN token against the current legal moves. 0-0 is accepted as O-O.
function R.parse_san(state, san)
    if not san or san == "" then return nil end
    san = san:gsub("0", "O"):gsub("[+#!?]+$", "")
    for _, m in ipairs(R.legal_moves(state)) do
        local got = R.san(state, m):gsub("[+#!?]+$", "")
        if got == san then return m end
    end
end

-- --- notation --------------------------------------------------------------
local FILES = "abcdefgh"
local function file_char(f) return FILES:sub(f + 1, f + 1) end

-- "+" or "#", which depend on the position AFTER the move. make/unmake is cheaper and
-- less error-prone than asking the caller to splice the suffix on later.
local function suffix(state, m)
    local undo = R.make(state, m)
    local s = ""
    if R.in_check(state, state.turn) then
        s = (#R.legal_moves(state) == 0) and "#" or "+"
    end
    R.unmake(state, m, undo)
    return s
end

-- Standard algebraic notation, evaluated against the position BEFORE the move is played.
function R.san(state, m)
    if m.castle then
        return ((m.castle == "K") and "O-O" or "O-O-O") .. suffix(state, m)
    end

    local text = ""
    if m.kind ~= "P" then
        text = m.kind
        -- Disambiguate against the other pieces of this kind that could LEGALLY reach the
        -- same square: by file if that is unique, else by rank, else by both.
        local rivals = {}
        for _, o in ipairs(R.legal_moves(state)) do
            if o.kind == m.kind and o.to_f == m.to_f and o.to_r == m.to_r and
               not (o.from_f == m.from_f and o.from_r == m.from_r) then
                rivals[#rivals + 1] = o
            end
        end
        if #rivals > 0 then
            local by_file, by_rank = true, true
            for _, o in ipairs(rivals) do
                if o.from_f == m.from_f then by_file = false end
                if o.from_r == m.from_r then by_rank = false end
            end
            if by_file then text = text .. file_char(m.from_f)
            elseif by_rank then text = text .. tostring(m.from_r)
            else text = text .. file_char(m.from_f) .. tostring(m.from_r) end
        end
    elseif m.capture then
        text = file_char(m.from_f) -- a pawn capture names the file it left
    end

    if m.capture then text = text .. "x" end
    text = text .. file_char(m.to_f) .. tostring(m.to_r)
    if m.promo then text = text .. "=" .. m.promo end
    return text .. suffix(state, m)
end

-- --- self-check ------------------------------------------------------------
-- Perft: count leaf nodes to a given depth. These counts are the standard published
-- values for the opening position, so they catch essentially any generation bug.
function R.perft(state, depth)
    if depth == 0 then return 1 end
    local n = 0
    for _, m in ipairs(R.legal_moves(state)) do
        local undo = R.make(state, m)
        n = n + R.perft(state, depth - 1)
        R.unmake(state, m, undo)
    end
    return n
end

function R.selftest(pieces)
    local state = R.new(pieces)
    local expect = {20, 400, 8902}
    for depth, want in ipairs(expect) do
        local got = R.perft(state, depth)
        assert(got == want, ("perft(%d) = %d, expected %d"):format(depth, got, want))
    end
    assert(state.turn == "W", "make/unmake left the side to move wrong")
    return true
end

return R
