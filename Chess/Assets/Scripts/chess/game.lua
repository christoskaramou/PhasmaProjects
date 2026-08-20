-- game.lua — hot-seat chess: selection, moves, animation, HUD, move list.
--
-- board.lua owns geometry, rules.lua owns legality, grid.lua owns the on-board square
-- highlights and view.lua owns the cursor and the screen overlay; this module is the only
-- place they meet. Both sides are played with the mouse on one screen: click a piece of
-- the side to move, then click a highlighted square.
--
-- Captured pieces are parked beside the board rather than deleted — deleting nodes mid-play
-- is a known way to crash this engine, and parked pieces double as the spare meshes a
-- promotion draws from.
--
-- The move list on the right is a real analysis board: clicking a move rewinds to the
-- position after it. Rewinding replays from the opening rather than un-doing moves, so a
-- jump is always consistent no matter what castling/en-passant/promotion happened.

local G = {}

local B, R, V, C, GR, BOT, S, MENU, PGN, K, B2, LAN

-- ── state (every one of these is reset by G.init, so editor Play→Stop→Play works) ──
local pieces, snapshots, state
local selected, targets
local parked, park_seq
local anim, prev_down, promo, result
local drag                     -- piece in hand: {file, rank, x0, y0, x, y, active}
local history, view_ply, scroll, panel_hot
local bot_on, bot_side, bot_both, bot_wait
local clones                     -- extra promo meshes, dropped on rewind / init
local hud_note, hud_note_frames
local menu_mode, cfg           -- overlay state + the config the next game starts with
local mp_note                  -- one-line reply from the not-yet-built online rows
local pgn_files, pgn_first, pgn_error -- the Open PGN browser: listing, page offset, last error
local clock_k, clock_warned    -- chess clock, and which sides already got the low-time warning
local hint, ana_kind, ana_req_ply
local eval_on, eval_view
local base_key                 -- start-position key, counted by the threefold rule
local pgn_saved, end_wait
local flag_result              -- time forfeit; refresh_result cannot recompute this from the board
local replay, ply_ms           -- timed replay of a saved game; think-time accumulator for [%emt]
local view2d                   -- flat 2D board instead of the 3D set; a VIEW, not a mode
local analysis                 -- an analysis board (Analysis > New Board / Load PGN)
local online                   -- "host" | "guest" while playing someone on the LAN
local my_color                 -- the side THIS machine plays online; the other is the peer's
local applying_remote          -- guard so a move that arrived on the wire is not echoed back
local rematch_sent, rematch_offered -- online rematch: who has asked whom
local rematch_count = 0        -- rematches on THIS link; both sides count it to swap colours
local offer_sent, offer_in     -- "draw"/"takeback" we asked for, and one we were asked
local peer_name, peer_live     -- the opponent badge: name survives a disconnect, the dot does not
local replay_speed = 1

-- Defined below, referenced across sections; declared here so every definition lands in
-- the local, not a global.
local game_over_fx, open_menu, close_menu, start_game, request_analysis, host_quit
local lan_tick, lan_break

local PARK_X = 0.30 -- centre-to-shelf; the board's own edge is at 0.25
local MOVE_TIME = 0.28
local DEFAULT_EMT = 800 -- ms, used when a PGN has no [%emt] (older saves)
local DEFAULT_CFG = {side = "W", elo = 1500, clock_min = 0, clock_inc = 0,
                     volume = 0.15, view2d = true}

local function hide_promo()
    if not V then return end
    for _, id in ipairs({"Q", "R", "B", "N"}) do V.hide("promo_" .. id) end
    V.hide("promo_lbl")
end

local KIND_NAME = {K = "King", Q = "Queen", R = "Rook", B = "Bishop", N = "Knight", P = "Pawn"}

local function load_module(path)
    local src = fs.read(path)
    if not src then error("[chess] missing module: " .. path) end
    local fn, err = load(src, "@" .. path, "bt", _ENV)
    if not fn then error("[chess] failed to load " .. path .. ": " .. tostring(err)) end
    return fn()
end

-- Loaded here and NOT in G.init, for two reasons: it owns a live socket and must survive the
-- start_game that the connection itself triggers, and G.init is at LuaJIT's 60-upvalue ceiling
-- (one more name in that function and the whole file stops parsing).
LAN = load_module("Scripts/chess/lan.lua")

-- tween.cancel does NOT fire the tween's on_done, so the in-flight counter has to be
-- unwound here or input stays blocked for the rest of the game.
local function stop_tween(piece)
    if not piece.tween then return end
    tween.cancel(piece.tween)
    piece.tween = nil
    anim = math.max(0, anim - 1)
end

-- ── parking ────────────────────────────────────────────────────────────────
-- A captured man is HIDDEN, not shelved. The 2D tray shows what has been taken — grouped,
-- sorted and with the material score — from any camera angle and in both board views, which
-- a pile of meshes beside the board cannot: it fights the orbit and half of it ends up
-- behind the move panel. The nodes still exist (deleting nodes mid-play is a known way to
-- crash this engine, and they are the spare pool a promotion draws from), they are just
-- dropped from the render and the TLAS. set_enabled, NOT set_visible: set_visible only
-- flips the raster cull flag and this scene renders hybrid, so hidden pieces would still
-- bounce light into the board.
local PARK_STEP = 0.058

-- Enable/disable costs a TLAS rebuild, so it only ever flips on a real change.
local function show_piece(piece, on)
    if (not piece.hidden) == (on and true or false) then return end
    piece.hidden = not on
    piece.node:set_enabled(on and true or false)
end

local function park(piece)
    -- A piece can be captured while its own move is still animating; that tween would
    -- otherwise finish and snap it back onto the board it was just taken from.
    stop_tween(piece)
    piece.file, piece.rank = nil, nil
    park_seq = park_seq + 1
    piece.park_seq = park_seq
    parked[#parked + 1] = piece
    -- Parked off-board anyway: invisible now, but a stray re-enable must not put a piece
    -- inside the board.
    local side = (piece.color == "W") and 1 or -1
    piece.node:set_world_position(vec3(side * PARK_X, piece.y, -0.20 + (park_seq % 8) * PARK_STEP))
    show_piece(piece, false)
end

local function drop_clones()
    for _, node in ipairs(clones or {}) do
        if node and node.is_valid and node:is_valid() then node:remove() end
    end
    clones = {}
    if pieces then
        for i = #pieces, 1, -1 do
            if pieces[i].clone then table.remove(pieces, i) end
        end
    end
    local root
    for _, e in ipairs(scene.get_entities()) do
        if e.label == "ROOT" then root = e.node end
    end
    if not root then return end
    for _, node in ipairs(root:get_children()) do
        local name = node:get_name()
        if name and name:find("_clone", 1, true) then node:remove() end
    end
end

local function copy_visual(dst, src)
    local refs = src:get_mesh_refs()
    if refs then
        for _, idx in ipairs(refs) do dst:add_mesh_ref(idx) end
    end
    dst:set_rotation(src:get_rotation())
    dst:set_scale(src:get_scale())
    for _, child in ipairs(src:get_children()) do
        local c = scene.add_empty_node((child:get_name() or "ch") .. "_x")
        c:set_parent(dst)
        copy_visual(c, child)
        c:set_position(child:get_position())
    end
end

local function clone_piece(src)
    local node = scene.add_empty_node((src.name or "Piece") .. "_clone" .. tostring(#clones + 1))
    local parent = src.node:get_parent()
    if parent then node:set_parent(parent) end
    copy_visual(node, src.node)
    node:set_world_position(src.node:get_world_position())
    clones[#clones + 1] = node
    local p = {
        node = node, name = node:get_name(), kind = src.kind, color = src.color,
        y = src.y, file = nil, rank = nil,
        radius = src.radius, base_y = src.base_y, height = src.height, clone = true,
    }
    pieces[#pieces + 1] = p
    return p
end

-- A promotion reuses an already-captured piece of the chosen kind. With none captured
-- (a second queen while the first still lives) a clone of the living piece is spawned.
local function take_spare(color, kind)
    for i, p in ipairs(parked) do
        if p.color == color and p.kind == kind then
            table.remove(parked, i)
            return p
        end
    end
    for _, p in ipairs(pieces) do
        if p.color == color and p.kind == kind then return clone_piece(p) end
    end
end

-- ── move execution ─────────────────────────────────────────────────────────
local function move_piece(piece, to_file, to_rank, instant)
    -- Two tweens on one node fight over its position; a scripted sequence can move the
    -- same piece twice inside one animation, so cancel whatever is still in flight.
    stop_tween(piece)
    -- A promotion moves the mover onto a node that was parked, so it arrives hidden.
    show_piece(piece, true)
    if instant then
        B.place(piece, to_file, to_rank)
        return
    end
    local from = piece.node:get_world_position()
    local x, z = B.square_to_world(to_file, to_rank)
    piece.file, piece.rank = to_file, to_rank
    anim = anim + 1
    piece.tween = tween.to(vec3(from.x, from.y, from.z), vec3(x, piece.y, z), MOVE_TIME,
             function(v) piece.node:set_world_position(v) end,
             {on_done = function()
                 anim = anim - 1
                 piece.tween = nil
                 piece.node:set_world_position(vec3(x, piece.y, z))
             end})
end

-- Play one move: rules first, then the meshes that have to follow it. `instant` skips the
-- tweens, which is what replaying a rewound game needs. Returns the move in notation.
local function apply(m, instant)
    -- Notation and the visual side both have to be read BEFORE R.make rearranges the board.
    local san = R.san(state, m)
    local mover = state.board[m.from_r][m.from_f].piece
    local victim = m.capture and m.capture.piece
    local rook = m.castle and state.board[m.from_r][m.rook_from].piece

    R.make(state, m)

    if victim then park(victim) end
    move_piece(mover, m.to_f, m.to_r, instant)
    if rook then move_piece(rook, m.rook_to, m.from_r, instant) end

    if m.promo then
        local spare = take_spare(m.color, m.promo)
        if spare then
            -- Swap visual identity BETWEEN the two entries rather than parking the mover:
            -- park() appends to the captured pool, so parking the live promoted piece would
            -- offer it back to the next promotion and let it steal its own mesh away.
            -- After the swap `spare` is a genuine pawn-shaped dead entry and `mover` — the
            -- entry the rules hold on the board — owns the queen mesh.
            stop_tween(mover)
            mover.node, spare.node = spare.node, mover.node
            mover.name, spare.name = spare.name, mover.name
            mover.y, spare.y = spare.y, mover.y
            mover.radius, spare.radius = spare.radius, mover.radius
            mover.base_y, spare.base_y = spare.base_y, mover.base_y
            mover.height, spare.height = spare.height, mover.height
            spare.kind = "P"
            park(spare)
            move_piece(mover, m.to_f, m.to_r, instant) -- glides in from the sideline
        else
            pe_log("[chess] promoted to " .. m.promo .. " but no captured " .. m.promo ..
                   " to swap in - keeping the pawn model")
        end
        mover.kind = m.promo
    end

    return san
end

local function refresh_result()
    -- A flag is not derivable from the position, so rewind must not erase it.
    if flag_result and not (replay and view_ply < #history) then result = flag_result return end
    local st = R.status(state)
    if st == "checkmate" then
        result = ((state.turn == "W") and "Black" or "White") .. " wins by checkmate"
    elseif st == "stalemate" then
        result = "Draw - stalemate"
    elseif st == "draw50" then
        result = "Draw - fifty-move rule"
    elseif R.insufficient(state) then
        result = "Draw - insufficient material"
    else
        -- Threefold: the current key against every position this line passed through, the
        -- start position included. Counting lives HERE, not in R.make - legality probing
        -- calls make/unmake constantly and would poison any tally kept there.
        local k = R.position_key(state)
        local n = (k == base_key) and 1 or 0
        for i = 1, view_ply do
            if history[i].key == k then n = n + 1 end
        end
        result = (n >= 3) and "Draw - threefold repetition" or nil
    end
end

-- End-of-game feedback for a game that ends NOW (never for a replayed position): the sound
-- for how it ended, then the end card after a beat so the final move is seen first.
function game_over_fx()
    if S then
        if result:find("wins") then
            local white_won = result:find("White") == 1
            local human_won = bot_both or not bot_on or ((bot_side == "W") ~= white_won)
            S.play(human_won and "end_win" or "end_lose")
        else
            S.play("end_draw")
        end
    end
    pgn_saved = false
    end_wait = 100
end

local function move_sound(m)
    if not S then return end
    if m.promo then S.play("promote")
    elseif m.capture then S.play("capture")
    else S.play("move") end
    if not result and R.in_check(state, state.turn) then S.play("check") end
end

local function finish(m)
    if result then return end -- a flag (or anything else) already closed this game
    -- Playing on from a rewound position discards the moves that used to follow, which is
    -- what every analysis board does.
    for i = #history, view_ply + 1, -1 do history[i] = nil end

    local was_over = result ~= nil
    local san = apply(m, false)
    history[#history + 1] = {
        from_f = m.from_f, from_r = m.from_r, to_f = m.to_f, to_r = m.to_r,
        promo = m.promo, san = san, emt = ply_ms,
        cap = m.capture and m.capture.kind or nil,
        key = R.position_key(state), -- position AFTER the move, for the threefold count
    }
    ply_ms = 0
    view_ply = #history
    scroll = nil -- follow the game again
    if online and not applying_remote then LAN.send_move(BOT.uci_move(history[#history])) end

    selected, targets = nil, nil
    V.outline(nil)
    hint = nil
    refresh_result()

    -- Real moves only: goto_ply replays bypass finish, so a rewind stays silent and does
    -- not touch the clock.
    move_sound(m)
    if clock_k and not result then
        K.add_increment(clock_k, (state.turn == "W") and "B" or "W") -- the side that just moved
    end
    if result and not was_over then game_over_fx() end
end

-- Re-derive a stored move against the CURRENT state. The move tables handed to R.make
-- carry references into the board they were generated from, so a replay must ask for a
-- fresh one rather than reuse the recorded object.
local function move_at(rec)
    for _, m in ipairs(R.legal_moves(state, rec.from_f, rec.from_r)) do
        if m.to_f == rec.to_f and m.to_r == rec.to_r and m.promo == rec.promo then return m end
    end
end

-- Put the board in the position after `n` half-moves. Replaying from the opening keeps
-- promotions, castling and en passant consistent for free; unwinding them would not.
local function goto_ply(n)
    n = math.max(0, math.min(n or 0, #history))
    -- A live online game has no review: rewinding would stop a clock the opponent's copy keeps
    -- running, and a move arriving off the wire would then be checked against -- and truncate --
    -- the position we rewound to. A finished one is harmless to review; the head test is what
    -- keeps a mate reviewable, since the first rewind clears `result`.
    if online and not result and view_ply == #history and n < #history then return view_ply end

    if BOT then BOT.abort() end -- whatever it is searching belongs to a position we just left
    bot_wait = nil
    for _, p in ipairs(pieces) do stop_tween(p) end
    anim = 0
    drop_clones()
    parked, park_seq = {}, 0
    selected, targets, promo, result = nil, nil, nil, nil
    hint = nil
    hide_promo()
    V.outline(nil)

    -- Restore pristine identity first: a promotion swapped meshes between two registry
    -- entries, and B.reset groups pieces by kind, so a stale swap would scatter the set.
    for i, p in ipairs(pieces) do
        local s = snapshots[i]
        p.node, p.name, p.kind, p.color = s.node, s.name, s.kind, s.color
        p.y, p.radius, p.base_y, p.height = s.y, s.radius, s.base_y, s.height
    end
    B.reset(pieces)
    state = R.new(pieces)

    for i = 1, n do
        local m = move_at(history[i])
        if not m then
            pe_log("[chess] replay stalled at ply " .. i .. " (" .. history[i].san .. ")")
            n = i - 1
            break
        end
        apply(m, true)
    end

    view_ply = n
    refresh_result()
    return view_ply
end

local function wait_for_next()
    local rec = history[view_ply + 1]
    if not rec then return 0 end
    local speed = replay_speed or 1
    if speed < 0.1 then speed = 0.1 end
    local ms = (rec.emt or DEFAULT_EMT) / speed
    local min_ms = (MOVE_TIME * 1000 + 80) / speed
    if ms < min_ms then ms = min_ms end
    return ms
end

local function replay_speed_label()
    local s = replay_speed or 1
    if s < 1 then return string.format("%.1fx", s) end
    return tostring(s) .. "x"
end

local function pause_replay()
    if replay then replay.paused = true end
end

-- Timed playback of `history`. Wait is the think-time BEFORE the next ply; the piece
-- tween then runs, then we wait again. Clicking a move-list ply pauses.
local function replay_tick(delta_ms)
    if not replay or replay.paused then return end
    if anim > 0 then return end
    if view_ply >= #history then
        replay.paused = true
        return
    end
    -- A hitch or a blocked MCP call can report tens of seconds in one frame; that is not
    -- think time. Cap so replay cannot skip a ply.
    if delta_ms > 100 then delta_ms = 100 end
    replay.wait = (replay.wait or 0) - delta_ms
    if replay.wait > 0 then return end
    local rec = history[view_ply + 1]
    local m = rec and move_at(rec)
    if not m then
        replay.paused = true
        return
    end
    apply(m, false)
    view_ply = view_ply + 1
    refresh_result()
    move_sound(m)
    replay.wait = wait_for_next()
end

-- ── bot ────────────────────────────────────────────────────────────────────
-- The whole game so far in coordinate notation, which is what `position startpos moves` wants.
local function bot_line()
    local out = {}
    for i = 1, view_ply do out[i] = BOT.uci_move(history[i]) end
    return table.concat(out, " ")
end

-- One Stockfish process; Watch-bots is the same engine answering for whichever side is to move.
local function bot_to_move()
    return bot_on and (bot_both or state.turn == bot_side)
end

-- Online, the peer's side is not clickable: the board is shared, so moving for them would
-- desync the two games instantly. Same gate the bot's side already uses.
local function remote_to_move()
    return online ~= nil and state.turn ~= my_color
end

-- One frame of the opponent. Polled unconditionally so the pipe never backs up, then it moves
-- only when it is genuinely its turn at the live head of the game.
local function bot_tick()
    if not bot_on then return end
    if not BOT.running() then
        pe_log("[chess] bot process died - restarting")
        local ok, err = BOT.start(BOT.elo())
        if not ok then
            bot_on, bot_both = false, false
            pe_log("[chess] bot unavailable: " .. tostring(err))
        end
        return
    end

    local mv = BOT.poll()
    if mv and not result and view_ply == #history and bot_to_move() then
        G.move(mv)
        return
    end

    if result or promo or anim > 0 or view_ply < #history then return end
    if not bot_to_move() or BOT.thinking() then return end
    BOT.think(bot_line())
end

-- G.bot(elo, side) turns the engine on at that Elo; G.bot(0) or G.bot(false) turns it off.
-- `side` is "W"|"B"|"both" (Watch bots). Elo is clamped to BOT.MIN_ELO..BOT.MAX_ELO.
function G.bot(target_elo, side)
    if side then
        local prev_both, prev_side = bot_both, bot_side
        local s = side:upper()
        if s == "BOTH" or s == "AUTO" then
            bot_both, bot_side = true, "B"
        else
            bot_both, bot_side = false, (s == "W") and "W" or "B"
        end
        if bot_on and (bot_both ~= prev_both or bot_side ~= prev_side) then
            BOT.abort()
            bot_wait = nil
        end
    end
    if not target_elo or target_elo == 0 then
        bot_on, bot_both, bot_wait = false, false, nil
        BOT.shutdown()
    else
        if not bot_on then
            local ok, err = BOT.start(target_elo)
            if not ok then
                pe_log("[chess] bot unavailable: " .. tostring(err))
                return {on = false, error = tostring(err)}
            end
            bot_on = true
        else
            -- Dragging the Elo field calls this every frame. Only a real change is worth
            -- abandoning a search over; aborting on every frame of a drag would restart the
            -- search forever and it would never produce a move.
            local before = BOT.elo()
            if BOT.set_elo(target_elo) ~= before then
                BOT.abort()
                bot_wait = nil
            end
        end
    end
    return G.bot_status()
end

function G.bot_status()
    return {on = bot_on, elo = BOT.elo(), engine_elo = BOT.engine_elo(),
            unlimited = BOT.unlimited(), blunder = BOT.blunder(),
            depth = BOT.search_depth(), side = bot_both and "both" or bot_side,
            both = bot_both, thinking = BOT.thinking()}
end

-- ── selection ──────────────────────────────────────────────────────────────
local function select_square(file, rank)
    local sq = state.board[rank][file]
    if sq and sq.color == state.turn then
        selected = {file = file, rank = rank}
        targets = R.legal_moves(state, file, rank)
        if S then S.play("select") end
        V.outline(sq.piece.node) -- real mesh silhouette where the engine offers one
        return
    end
    selected, targets = nil, nil
    V.outline(nil)
end

local function target_at(file, rank)
    if not targets then return nil end
    for _, m in ipairs(targets) do
        if m.to_f == file and m.to_r == rank then return m end
    end
end

local function click(file, rank)
    if not targets then
        select_square(file, rank)
        return
    end
    local m = target_at(file, rank)
    if not m then
        select_square(file, rank)
        return
    end
    if m.promo then
        -- Collect the four promotion choices for this destination and ask.
        promo = {file = file, rank = rank, moves = {}}
        for _, t in ipairs(targets) do
            if t.to_f == file and t.to_r == rank and t.promo then promo.moves[t.promo] = t end
        end
        return
    end
    finish(m)
end

-- ── drag and drop ──────────────────────────────────────────────────────────
-- Click-then-click still works exactly as before; drag is layered on top of it, because
-- both are standard and players expect whichever one they already have in their fingers.
--
-- The registry entry is NOT moved while a piece is in hand: `piece.file`/`rank` and the
-- rules state both stay on the origin square, and only the NODE is pushed around. That is
-- what makes a cancelled drag a no-op rather than something to unwind.
local DRAG_SLOP = 6      -- px of travel before a press counts as a drag rather than a click
local DRAG_LIFT = 0.012  -- m the 3D piece rides above the board while carried

local function drag_piece()
    if not drag then return nil end
    local sq = state.board[drag.rank] and state.board[drag.rank][drag.file]
    return sq and sq.piece or nil
end

-- Put the carried piece back where it started. Instant, not a tween: the rules never moved,
-- so this is a correction of the view, and a glide would imply a move happened.
local function cancel_drag()
    local p = drag and drag_piece()
    if p and not view2d then B.place(p, drag.file, drag.rank) end
    drag = nil
end

-- Follow the cursor. 2D just records the pixel for board2d to draw at; 3D pushes the node
-- along the board plane, so the piece slides under the pointer at any camera angle.
local function drag_follow()
    if not drag then return end
    local mx, my = V.cursor()
    if not mx then return end
    if not drag.active then
        if math.abs(mx - drag.x0) + math.abs(my - drag.y0) < DRAG_SLOP then return end
        drag.active = true
        local p = drag_piece()
        if p then stop_tween(p) end
    end
    drag.x, drag.y = mx, my
    if view2d then return end
    local wx, wz = V.board_point()
    local p = drag_piece()
    if wx and p then p.node:set_world_position(vec3(wx, p.y + DRAG_LIFT, wz)) end
end

-- ── board highlights ───────────────────────────────────────────────────────
-- One list of marks per frame, consumed by whichever board is on screen: grid.lua's real
-- planes in 3D, board2d.lua's quads in 2D. It is computed ONCE because the hint countdown
-- lives here — two copies of this walk would expire the hint twice as fast.
local MARK_COLOR = {last = "LAST", select = "SELECT", move = "MOVE",
                    capture = "CAPTURE", check = "CHECK", hint = "HINT"}

local function compute_marks()
    local marks = {}
    local function add(f, r, m) marks[#marks + 1] = {f = f, r = r, m = m} end

    local last = history[view_ply]
    if last then
        add(last.from_f, last.from_r, "last")
        add(last.to_f, last.to_r, "last")
    end
    if selected then add(selected.file, selected.rank, "select") end
    if targets then
        -- One square per legal move. A promotion generates four moves onto the same
        -- square, which simply collapse onto one highlight.
        for _, m in ipairs(targets) do
            add(m.to_f, m.to_r, m.capture and "capture" or "move")
        end
    end
    if not result and R.in_check(state, state.turn) then
        local kf, kr = R.king_square(state, state.turn)
        if kf then add(kf, kr, "check") end
    end
    if hint then
        hint.frames = hint.frames - 1
        if hint.frames <= 0 then hint = nil
        else
            add(hint.ff, hint.fr, "hint")
            add(hint.tf, hint.tr, "hint")
        end
    end
    return marks
end

local function draw_grid(marks)
    GR.begin()
    for _, mk in ipairs(marks) do
        -- With the outline pass available the piece itself is highlighted in 3D, so lighting
        -- its square as well is noise; the 2D board has no outline pass and always shows it.
        if mk.m ~= "select" or not V.outline_available() then
            GR.set(mk.f, mk.r, GR[MARK_COLOR[mk.m]])
        end
    end
    GR.flush()
end

-- Swap which board is drawn. Purely presentational: the 3D set keeps its position, the
-- game keeps its state, and switching back mid-game lands exactly where it left off. Each
-- side hands its widgets back so the other's are the only ones on screen.
local function set_view2d(on)
    on = on and true or false
    if view2d == on then return view2d end
    view2d = on
    cfg.view2d = on
    if on then
        GR.clear()
        V.outline(nil)
        V.coords_hide()
    end
    return view2d
end

-- ── captured pieces ────────────────────────────────────────────────────────
-- Derived from history up to the position being VIEWED, so rewinding empties the trays in
-- step with the board. Odd plies are White's, so an odd ply's capture is a Black man.
local function captured()
    local by_white, by_black = {}, {}
    for i = 1, view_ply do
        local rec = history[i]
        if rec and rec.cap then
            local into = (i % 2 == 1) and by_white or by_black
            into[#into + 1] = rec.cap
        end
    end
    return by_white, by_black
end

-- White's men sit at the bottom of the board unless it is flipped, and each side's tray
-- goes on that side's edge — the pieces you have TAKEN, beside you.
local function draw_trays()
    local by_white, by_black = captured()
    local flip = B2.flipped()
    local wx, wy, wsz = B2.tray_rect(not flip, view2d)
    local bx, by, bsz = B2.tray_rect(flip, view2d)
    B2.tray("cap_w", wx, wy, by_white, "b", wsz, by_black)
    B2.tray("cap_b", bx, by, by_black, "w", bsz, by_white)
end

-- The 2D board on its own, for the frames the game loop does not draw: the 3D set is always
-- rendered underneath (the flat board is an opaque overlay, not a mode), so a single frame
-- without these quads shows the 3D board through the gap. Anything that calls V.clear must
-- redraw them in the SAME update, not leave it to the next one.
local function draw_board_overlay()
    local s = runtime_ui.get_surface_size()
    B2.begin(s.w, s.h)
    if view2d then B2.board(state, {}) end
    draw_trays()
    B2.finish()
end

-- ── move list ──────────────────────────────────────────────────────────────
-- Ids are per visible ROW, not per move, so a 200-move game still only ever touches the
-- couple of dozen widgets that fit on screen.
local MAX_ROWS = 40
local shown_rows = 0

local function draw_moves(w, h)
    local pw = math.max(190, w * 0.15)
    local px, py = w - pw - 14, 14
    local ph = h - 28
    local row_h = math.max(24, h * 0.027)
    local head_h = row_h * 1.2
    local foot_h = row_h * 1.3
    -- runtime_ui does not clip, so the list has to stop above the footer rows or SAN
    -- rows draw under the buttons and the thumb counts hidden rows as visible.
    -- Review is refused while an online game is live (see goto_ply), so its two buttons are
    -- not drawn at all: a button that highlights and then does nothing reads as a broken one.
    local no_review = online and not result and view_ply == #history
    local by = py + ph - foot_h * ((analysis and 3) or (no_review and 1) or 2) - 20
    local list_y = py + head_h
    local list_h = math.max(row_h, by - list_y - 4)
    local rows = math.min(MAX_ROWS, math.max(1, math.floor(list_h / row_h)))
    list_h = rows * row_h

    panel_hot = V.panel("mv_bg", px, py, pw, ph)
    V.text("mv_head", px, py, pw, head_h, "Moves", {fill = {0, 0, 0, 0}, font_scale = 1.225})

    local total = math.ceil(#history / 2) -- full moves
    local max_first = math.max(1, total - rows + 1)
    local first -- first full-move number drawn
    if scroll then
        first = math.max(1, math.min(scroll, max_first))
    else
        first = max_first -- follow the game
    end

    local need_bar = total > rows
    local bar_w = 12
    local inner = pw - 16 - (need_bar and (bar_w + 4) or 0)
    local left_w = inner * 0.58
    local right_w = inner - left_w
    local list_hot = panel_hot
    local drawn = 0
    for i = 0, rows - 1 do
        local move_no = first + i
        if move_no > total then break end
        local y = list_y + i * row_h
        drawn = drawn + 1
        V.hide("mv_n" .. i)
        for side = 0, 1 do
            local ply = move_no * 2 - 1 + side
            local rec = history[ply]
            local id = "mv_" .. i .. "_" .. side
            if rec then
                local current = (ply == view_ply)
                local label = (side == 0) and string.format("%d.  %s", move_no, rec.san) or rec.san
                local x = (side == 0) and (px + 8) or (px + 8 + left_w)
                local tw = ((side == 0) and left_w or right_w) - 2
                local clicked, hovered = V.button(id, x, y, tw, row_h - 2, label, {
                        style = "button", align_h = "left",
                        fill = current and {0.22, 0.34, 0.55, 0.95} or {0, 0, 0, 0},
                        border = {0, 0, 0, 0}, corner_radius = 4,
                        text_color = current and {1, 1, 1, 1} or {0.88, 0.88, 0.84, 1},
                    })
                if hovered then list_hot = true end
                if clicked then
                    pause_replay()
                    goto_ply(ply)
                    if replay then replay.wait = wait_for_next() end
                end
            else
                V.hide(id)
            end
        end
    end
    for i = drawn, shown_rows - 1 do
        V.hide("mv_n" .. i)
        V.hide("mv_" .. i .. "_0")
        V.hide("mv_" .. i .. "_1")
    end
    shown_rows = drawn

    if need_bar then
        local bar_x = px + pw - 6 - bar_w
        local thumb_h = math.max(22, list_h * rows / total)
        if thumb_h > list_h then thumb_h = list_h end
        runtime_ui.set_quad(V.screen(), "mv_scroll", {
            x = bar_x, y = list_y, w = bar_w, h = list_h,
            style = "panel", fill = {0.07, 0.07, 0.09, 0.95}, accent = {0, 0, 0, 0},
            border = {0.32, 0.32, 0.36, 0.9}, corner_radius = 4,
            draggable = true, visible = true, body = "",
        })
        local st = runtime_ui.get_state(V.screen(), "mv_scroll") or {}
        if st.hovered or st.dragging or st.down then list_hot = true end
        if st.down or st.dragging then
            -- Click/drag is the thumb centre, not the top of the track — otherwise a click
            -- at the bottom overshoots and the thumb looks shorter than the range it maps.
            local usable = math.max(1, list_h - thumb_h)
            local t = (st.mouse_y - list_y - thumb_h * 0.5) / usable
            if t < 0 then t = 0 elseif t > 1 then t = 1 end
            scroll = math.floor(1 + t * (max_first - 1) + 0.5)
            if scroll < 1 then scroll = 1 end
            if scroll > max_first then scroll = max_first end
        end
        local t = (max_first <= 1) and 0 or ((first - 1) / (max_first - 1))
        -- no_input quads batch onto the background list (behind this track). bring_to_front
        -- keeps a windowed quad so the thumb actually paints on top of the track.
        V.text("mv_thumb", bar_x + 2, list_y + t * (list_h - thumb_h), bar_w - 4, thumb_h, "",
               {fill = {0.55, 0.58, 0.64, 0.95}, bring_to_front = true})
    else
        V.hide("mv_scroll")
        V.hide("mv_thumb")
    end

    if list_hot then
        panel_hot = true
        -- Hovering any overlay quad sets WantCaptureMouse, which zeros input.get_mouse_wheel.
        -- runtime_ui.get_wheel is ImGui's IO.MouseWheel, still live during on_update.
        local dy = (runtime_ui.get_wheel and runtime_ui.get_wheel()) or 0
        if dy == 0 then
            local wheel = input.get_mouse_wheel()
            dy = (wheel and wheel.y) or 0
        end
        if dy ~= 0 then
            local step = math.floor(dy * 3)
            if step == 0 then step = (dy > 0) and 1 or -1 end
            scroll = math.max(1, math.min(max_first, first - step))
        end
    end

    -- The eval bar is an analysis tool, so its toggle only exists on an analysis board:
    -- during a game it would be a cheat button.
    local fy = py + ph - foot_h * 2 - 12
    if analysis then
        if V.button("mv_eval", px + 8, fy - foot_h - 4, pw - 16, foot_h - 4,
                    eval_on and "Eval: on" or "Eval: off",
                    {fill = {0.14, 0.15, 0.18, 0.95}, border = {0.40, 0.40, 0.45, 1}}) then
            if S then S.play("click") end
            eval_on = not eval_on
            eval_view = nil
            if not eval_on then V.vbar_hide("eval") end
        end
    else
        V.hide("mv_eval")
    end

    -- Everything else this panel used to carry (bot, Elo, hint, board type) is chosen in the
    -- menus before the game starts, and replay is started from the end card. What is left is
    -- the review transport and the way into the pause menu.
    local half = (pw - 20) * 0.5
    if no_review then
        V.hide("mv_start")
        V.hide("mv_end")
    else
        if V.button("mv_start", px + 8, fy, half, foot_h - 4, "|< Start",
                    {fill = {0.14, 0.15, 0.18, 0.95}, border = {0.4, 0.4, 0.45, 1}}) then
            pause_replay()
            scroll = 1
            goto_ply(0)
            if replay then replay.wait = wait_for_next() end
        end
        if V.button("mv_end", px + 12 + half, fy, half, foot_h - 4, "Live >|",
                    {fill = {0.14, 0.15, 0.18, 0.95}, border = {0.4, 0.4, 0.45, 1}}) then
            pause_replay()
            scroll = nil
            goto_ply(#history)
            if replay then replay.wait = wait_for_next() end
        end
    end

    -- Quitting moved behind the pause menu, which also offers the way back to the title.
    if V.button("mv_quit", px + 8, fy + foot_h + 4, pw - 16, foot_h - 4, "Menu",
                {fill = {0.28, 0.11, 0.11, 0.95}, border = {0.65, 0.35, 0.30, 1}}) then
        if S then S.play("click") end
        open_menu("pause")
    end
end

local function draw_hud(w, h)
    local bar = math.max(44, h * 0.045)

    local text
    if replay then
        text = replay.paused and "Replay paused" or ("Replay  " .. replay_speed_label())
        if result then text = text .. "   -   " .. result end
    elseif result then
        text = result
    else
        local side = (state.turn == "W") and "White" or "Black"
        text = side .. " to move"
        if bot_to_move() then text = text .. "   -   bot thinking" end
        if R.in_check(state, state.turn) then text = text .. "   -   CHECK" end
    end
    if view_ply < #history then
        text = text .. "   (reviewing move " .. view_ply .. "/" .. #history .. ")"
    end
    if hud_note then text = hud_note end
    V.text("hud", w * 0.5 - w * 0.16, h * 0.02, w * 0.32, bar, text, {font_scale = 1.275})

    -- Clocks flank the HUD: White left, Black right; the running side is lit.
    if clock_k then
        local cw = math.max(84, w * 0.06)
        local live = not result and #history > 0
        local function clock_style(side)
            local active = live and state.turn == side and view_ply == #history
            return {fill = active and {0.20, 0.26, 0.20, 0.92} or {0.05, 0.05, 0.07, 0.72},
                    text_color = K.remaining(clock_k, side) < 30000
                                 and {1.0, 0.45, 0.35, 1} or {0.95, 0.95, 0.92, 1}}
        end
        V.text("clk_w", w * 0.5 - w * 0.16 - cw - 10, h * 0.02, cw, bar,
               "W " .. K.fmt(K.remaining(clock_k, "W")), clock_style("W"))
        V.text("clk_b", w * 0.5 + w * 0.16 + 10, h * 0.02, cw, bar,
               "B " .. K.fmt(K.remaining(clock_k, "B")), clock_style("B"))
    end

    -- Who you are playing, and whether they are still there. The name outlives the link on
    -- purpose: a grey dot answers "where did they go", a vanished badge does not.
    if peer_name then
        -- Plate first, then dot, then name: all three are no_input so they batch in creation
        -- order, and the plate is what keeps the badge readable over a bright board.
        local dot = math.max(11, bar * 0.24)
        local pad = dot * 0.7
        local bw = math.max(160, w * 0.11)
        V.text("peer_bg", 14, h * 0.02, bw, bar, "", {corner_radius = 6})
        V.text("peer_dot", 14 + pad, h * 0.02 + (bar - dot) * 0.5, dot, dot, "",
               {fill = peer_live and {0.30, 0.80, 0.40, 1} or {0.40, 0.40, 0.44, 1},
                corner_radius = dot * 0.5})
        V.text("peer_name", 14 + pad + dot + 8, h * 0.02, bw - pad - dot - 12, bar, peer_name,
               {align_h = "left", fill = {0, 0, 0, 0},
                text_color = peer_live and {0.95, 0.95, 0.92, 1} or {0.58, 0.58, 0.62, 1}})
    else
        V.hide("peer_bg")
        V.hide("peer_dot")
        V.hide("peer_name")
    end

    if promo then
        local bw, bh = w * 0.09, bar * 1.3
        local total = bw * 4 + 24 * 3
        local x0, y = w * 0.5 - total * 0.5, h * 0.5 - bh * 0.5
        V.text("promo_lbl", w * 0.5 - w * 0.12, y - bh - 12, w * 0.24, bh, "Promote to:")
        for i, kind in ipairs({"Q", "R", "B", "N"}) do
            local bx = x0 + (i - 1) * (bw + 24)
            if V.button("promo_" .. kind, bx, y, bw, bh, KIND_NAME[kind]) then
                local m = promo.moves[kind]
                promo = nil
                hide_promo()
                if m then finish(m) end
                return
            end
        end
    end
end

-- ── engine analysis: hint + eval bar ───────────────────────────────────────
-- One analyse() in flight at a time, tagged with what asked for it. A hint displaces a
-- pending eval; the eval re-requests itself on the next idle frame because its displayed
-- ply no longer matches.
function request_analysis(kind, depth)
    local ok, err = BOT.ensure()
    if not ok then
        pe_log("[chess] analysis unavailable: " .. tostring(err))
        eval_on = false
        if V then V.vbar_hide("eval") end
        return
    end
    ana_kind, ana_req_ply = kind, view_ply
    BOT.analyse(bot_line(), depth)
end

local function analysis_tick()
    if not bot_on then BOT.poll() end -- bot_tick drains the pipe when the bot plays
    local a = BOT.analysis()
    if ana_kind then
        if a and a.done then
            if ana_req_ply == view_ply then
                if ana_kind == "hint" and a.best and #a.best >= 4 then
                    hint = {ff = a.best:byte(1) - 97, fr = tonumber(a.best:sub(2, 2)),
                            tf = a.best:byte(3) - 97, tr = tonumber(a.best:sub(4, 4)),
                            frames = 240}
                elseif ana_kind == "eval" then
                    -- UCI scores are from the SIDE TO MOVE; the bar is drawn white-up.
                    if a.mate then
                        local white_mates = (a.mate > 0) == (state.turn == "W")
                        eval_view = {frac = white_mates and 1 or 0, ply = view_ply,
                                     label = (white_mates and "+#" or "-#") .. math.abs(a.mate)}
                    elseif a.cp then
                        local wcp = (state.turn == "W") and a.cp or -a.cp
                        eval_view = {frac = 1.0 / (1.0 + 10 ^ (-wcp / 400)), ply = view_ply,
                                     label = string.format("%+.1f", wcp / 100)}
                    end
                end
            end
            ana_kind = nil
        elseif not BOT.analysing() then
            -- think()/abort() preempted the search; the stale bestmove is dropped, so
            -- ana_result.done never arrives. Clear the latch so eval can re-request.
            ana_kind = nil
        end
    end
    if eval_on and not ana_kind and not BOT.thinking()
       and (not eval_view or eval_view.ply ~= view_ply) then
        request_analysis("eval", 12)
    end
end

-- ── menus ──────────────────────────────────────────────────────────────────
function host_quit()
    if V.is_editor() then engine.set_play_mode(false) else engine.quit() end
end

-- Entering an overlay clears every quad once; the game redraws its own retained widgets
-- per frame anyway, so leaving needs nothing beyond hiding the menu's quads.
function open_menu(mode)
    if drag then cancel_drag() end
    if mode == "title" and MENU then MENU.home() end
    menu_mode = mode
    V.clear()
    -- V.clear destroys the widgets themselves, so board2d's "already drawn" bookkeeping is
    -- now a lie — without this its 64 static squares would never be re-issued.
    if B2 then
        B2.reset()
        draw_board_overlay()
    end
end

function close_menu()
    MENU.hide()
    menu_mode = nil
end

function start_game(c, keep_link)
    cfg = c
    -- Any game that is not the online one drops the lobby: a listener left advertising after
    -- you walked away is a door left open. keep_link is passed by exactly one caller, the
    -- handshake that is starting the online game right now.
    if not keep_link then LAN.close() end
    online, my_color, applying_remote = nil, nil, false
    rematch_sent, rematch_offered, offer_sent, offer_in = false, false, nil, nil
    if not keep_link then peer_name, peer_live = nil, false end
    G.init() -- full board + module reset; also re-arms the title overlay, undone below
    MENU.hide()
    menu_mode = nil
    S.set_volume(cfg.volume or DEFAULT_CFG.volume)
    analysis = (cfg.side == "hotseat") -- Analysis > New Board; Load PGN sets it too
    C.face(cfg.side == "B" and "B" or "W") -- absolute; rematch must not accumulate +180
    if cfg.side == "auto" then
        G.bot(cfg.elo or 1500, "both")
    elseif cfg.side ~= "hotseat" then
        G.bot(cfg.elo or 1500, (cfg.side == "W") and "B" or "W")
    end
    if (cfg.clock_min or 0) > 0 then
        clock_k = K.new(cfg.clock_min, cfg.clock_inc or 0)
        clock_warned = {}
    end
end

-- ── PGN browser ────────────────────────────────────────────────────────────
-- There is no file-dialog binding in the engine, and `fs.read` is sandboxed to Assets/
-- (FilesystemBindings IsUnderAssets), so a native "open file" dialog could hand back a path
-- the game is not allowed to read. The browser lists what IS readable instead. fs.list also
-- enumerates game-pack assets, so this keeps working in a packed build.
local PGN_DIRS = {"Save", "Games"}

local function scan_pgn()
    local out = {}
    for _, dir in ipairs(PGN_DIRS) do
        local listing = fs.list(dir)
        for _, name in ipairs(listing and listing.files or {}) do
            if name:lower():sub(-4) == ".pgn" then
                out[#out + 1] = {label = dir .. "/" .. name, path = dir .. "/" .. name}
            end
        end
    end
    table.sort(out, function(a, b) return a.path < b.path end)
    return out
end

-- Clock presets, cycled by the Clock row. Mirrors menu.lua's list, which owns the labels.
local CLOCK_STEPS = {{0, 0}, {5, 0}, {10, 0}, {3, 2}}

local function cycle_clock()
    local i = 1
    for n, c in ipairs(CLOCK_STEPS) do
        if c[1] == (cfg.clock_min or 0) and c[2] == (cfg.clock_inc or 0) then i = n end
    end
    local c = CLOCK_STEPS[(i % #CLOCK_STEPS) + 1]
    cfg.clock_min, cfg.clock_inc = c[1], c[2]
end

-- A peer that broke the rules does not get a second try: the link goes, and the game stays
-- exactly as it was on our side.
function lan_break(why)
    LAN.close()
    online = nil
    hud_note, hud_note_frames = why, 300
end

-- The only way an online game starts. `c.side = "hotseat"` keeps the bot out of it, but that is
-- also how an ANALYSIS board is spelled, which is why `analysis` is cleared here by hand -- left
-- set, the pause card offers Reset/Back instead of Resign and Offer draw.
--
-- Colours: both sides run this off the same message and count rematches on this link, so each
-- derives its own side from the same rule and the swap needs no negotiating.
local function takeback_for(color)
    if #history == 0 then return end
    local last = (#history % 2 == 1) and "W" or "B"
    local n = (last == color) and 1 or 2
    if n > #history then n = #history end
    for _ = 1, n do history[#history] = nil end
    flag_result, result = nil, nil
    goto_ply(#history)
end

local function start_online()
    local c = {}
    for k, v in pairs(cfg) do c[k] = v end
    c.side = "hotseat"
    start_game(c, true)
    analysis = false
    online = LAN.role()
    my_color = ((LAN.role() == "host") == (rematch_count % 2 == 0)) and "W" or "B"
    peer_name, peer_live = LAN.peer_name(), true
    B2.set_flip(my_color == "B")
    C.face(my_color)
end

-- One frame of the LAN link. Every event here came off the wire, so each one is treated as a
-- claim to be checked rather than an instruction to obey.
function lan_tick(delta_ms)
    if not LAN then return end
    for _, ev in ipairs(LAN.tick(delta_ms)) do
        if ev.kind == "ready" then
            -- Host is White, guest is Black: a rule both sides compute identically, so the
            -- colours never need to be negotiated (and so cannot be argued about).
            rematch_count = 0
            start_online()
        elseif ev.kind == "move" then
            -- Two things must hold before a peer's move touches the board: it must be THEIR
            -- turn, and the move must be legal in the position WE hold. G.move does the second
            -- against R.legal_moves; the first is here because a peer moving our pieces would
            -- otherwise be perfectly legal chess.
            if state.turn == my_color then
                lan_break("Opponent moved out of turn")
            else
                applying_remote = true
                local ok = G.move(ev.uci)
                applying_remote = false
                if not ok then lan_break("Opponent sent an illegal move") end
            end
        elseif ev.kind == "draw_offer" or ev.kind == "takeback_offer" then
            offer_in = (ev.kind == "draw_offer") and "draw" or "takeback"
            hud_note = (peer_name or "Opponent") ..
                       ((offer_in == "draw") and " offers a draw" or " asks to take a move back")
            hud_note_frames = 600
            open_menu("pause") -- an offer that only lives in a corner of the HUD gets missed
        elseif ev.kind == "draw_accept" then
            offer_sent = nil
            if not result then
                flag_result, result = "Draw - agreed", "Draw - agreed"
                game_over_fx()
            end
        elseif ev.kind == "takeback_accept" then
            offer_sent = nil
            takeback_for(my_color)
        elseif ev.kind == "draw_decline" or ev.kind == "takeback_decline" then
            offer_sent = nil
            hud_note, hud_note_frames = "Declined", 180
        elseif ev.kind == "rematch_offer" then
            -- Both clicked at once: the offer we already sent IS our acceptance.
            if rematch_sent then
                LAN.send_rematch_ok()
                rematch_count = rematch_count + 1
                start_online()
            else
                rematch_offered = true
            end
        elseif ev.kind == "rematch_start" then
            rematch_count = rematch_count + 1
            start_online()
        elseif ev.kind == "resign" then
            if not result then
                flag_result = ((my_color == "W") and "White" or "Black") .. " wins by resignation"
                result = flag_result
                game_over_fx()
            end
            -- The GAME is over, not the session: the link stays up so the end card can still
            -- offer a rematch. Only a closed link clears `online`.
        elseif ev.kind == "closed" then
            online, peer_live, offer_in, offer_sent = nil, false, nil, nil
            hud_note, hud_note_frames = ev.why, 300
        end
    end
end

local function menu_frame(pressed)
    local s = runtime_ui.get_surface_size()
    -- The clock keeps running behind an online card, so it must not vanish behind one either:
    -- a clock you cannot see burning is worse than one that stops.
    if online and menu_mode ~= "title" then draw_hud(s.w, s.h) end
    if menu_mode == "title" then
        LAN.on_page(MENU.page())
        local action = MENU.draw_main(s.w, s.h, cfg,
                                      {note = LAN.note() or mp_note, pgn_files = pgn_files,
                                       pgn_first = pgn_first, pgn_error = pgn_error,
                                       lobbies = LAN.lobbies()})
        set_view2d(cfg.view2d) -- the title sits over a live board, so the choice previews
        S.set_volume(cfg.volume or DEFAULT_CFG.volume)

        if action == "volume" then
            S.play("move") -- a sample at the level you just dialled in
        elseif action == "side_w" or action == "side_b" then
            cfg.side = (action == "side_b") and "B" or "W"
            S.play("click")
        elseif action == "clock" then
            cycle_clock()
            S.play("click")
        elseif action == "board" then
            set_view2d(not view2d)
            S.play("click")
        elseif action == "start_pvb" then
            S.play("click")
            if cfg.side ~= "B" then cfg.side = "W" end
            start_game(cfg)
        elseif action == "start_bvb" then
            S.play("click")
            cfg.side = "auto"
            start_game(cfg)
        elseif action == "new_board" then
            S.play("click")
            cfg.side = "hotseat"
            start_game(cfg)
        elseif action == "browse_pgn" then
            S.play("click")
            pgn_files, pgn_first, pgn_error = scan_pgn(), 1, nil
            MENU.goto_page("pgn")
        elseif action == "pgn_prev" then
            S.play("click")
            pgn_first = math.max(1, (pgn_first or 1) - 8)
        elseif action == "pgn_next" then
            S.play("click")
            if (pgn_first or 1) + 8 <= #(pgn_files or {}) then pgn_first = (pgn_first or 1) + 8 end
        elseif type(action) == "string" and action:sub(1, 4) == "pgn:" then
            S.play("click")
            local pick = (pgn_files or {})[tonumber(action:sub(5))]
            local text = pick and fs.read(pick.path)
            local ok, err
            if text then ok, err = G.load_pgn(text) else err = "cannot read file" end
            if ok then
                pgn_error = nil
            else
                pgn_error = "Could not load: " .. tostring(err)
                pe_log("[chess] PGN load failed: " .. tostring(err))
            end
        elseif action == "lobby_create" then
            S.play("click")
            LAN.host()
        elseif action == "lobby_browse" then
            S.play("click")
            MENU.goto_page("lan")
        elseif action == "lobby_watch" then
            S.play("click")
            -- Spectating is a third connection to one game, which is a relay feature: two
            -- peers on a LAN have nowhere to put the watcher.
            mp_note = "Watching needs the relay - see MULTIPLAYER.md"
        elseif type(action) == "string" and action:sub(1, 4) == "lan:" then
            S.play("click")
            local pick = LAN.lobbies()[tonumber(action:sub(5))]
            if pick then LAN.join(pick.ip) end
        elseif action == "exit" then
            host_quit()
        end
    elseif menu_mode == "pause" then
        -- A finished game cannot be resigned, drawn or taken back, so those rows are not
        -- offered at all — a button that silently does nothing reads as a broken button.
        local live = not result
        local action = MENU.draw_pause(s.w, s.h, {
            takeback = live and #history > 0, draw = live,
            resign = live, over = not live,
            analysis = analysis, offer = online and offer_in or nil,
            sent = online and offer_sent or nil,
        })
        if action == "resume" then
            if S then S.play("click") end
            close_menu()
        elseif action == "reset" then
            if S then S.play("click") end
            cfg.side = "hotseat" -- same fresh analysis board that Analysis > New Board makes
            start_game(cfg)
        elseif action == "takeback" or action == "draw" then
            if S then S.play("click") end
            if not online then
                close_menu()
                if action == "takeback" then G.takeback() else G.offer_draw() end
            elseif offer_in == action then
                -- They asked; this is the acceptance, and both boards act on it.
                LAN.offer((action == "draw") and "DRAW_OK" or "TAKEBACK_OK")
                offer_in, hud_note = nil, nil -- the "they offer a draw" note is now stale
                close_menu()
                if action == "draw" then
                    flag_result, result = "Draw - agreed", "Draw - agreed"
                    game_over_fx()
                else
                    takeback_for((my_color == "W") and "B" or "W")
                end
            else
                LAN.offer((action == "draw") and "DRAW" or "TAKEBACK")
                offer_sent = action
                close_menu()
                hud_note, hud_note_frames = "Waiting for the opponent to answer", 300
            end
        elseif action == "decline" then
            if S then S.play("click") end
            LAN.offer((offer_in == "draw") and "DRAW_NO" or "TAKEBACK_NO")
            offer_in, hud_note = nil, nil
            close_menu()
        elseif action == "resign" then
            if S then S.play("click") end
            close_menu()
            G.resign()
        elseif action == "menu" then
            LAN.close()
            online = nil
            MENU.hide()
            MENU.home()
            menu_mode = "title"
        elseif action == "exit" then
            host_quit()
        end
    elseif menu_mode == "end" then
        local action = MENU.draw_end(s.w, s.h, result or "", pgn_saved,
                                     online and (rematch_offered and "offered"
                                                 or (rematch_sent and "sent")) or nil)
        if action == "rematch" then
            if S then S.play("click") end
            if online then
                -- Restarting alone would leave the opponent in a finished game, so this only
                -- asks; the board does not move until they answer.
                if rematch_offered then
                    LAN.send_rematch_ok()
                    rematch_count = rematch_count + 1
                    start_online()
                else
                    LAN.send_rematch()
                    rematch_sent = true
                end
            else
                MENU.hide()
                start_game(cfg)
            end
        elseif action == "review" then
            if S then S.play("click") end
            close_menu() -- back to the board; result stays in the HUD
        elseif action == "replay" then
            if S then S.play("click") end
            close_menu()
            G.replay()
        elseif action == "menu" then
            LAN.close()
            online = nil
            MENU.hide()
            MENU.home()
            menu_mode = "title"
        elseif action == "pgn" then
            if S then S.play("click") end
            G.save_pgn()
        end
    end
end

-- ── lifecycle ──────────────────────────────────────────────────────────────
function G.init()
    drop_clones()
    B = load_module("Scripts/chess/board.lua")
    R = load_module("Scripts/chess/rules.lua")
    V = load_module("Scripts/chess/view.lua")
    C = load_module("Scripts/chess/camera.lua")
    GR = load_module("Scripts/chess/grid.lua")
    BOT = load_module("Scripts/chess/bot.lua")
    S = load_module("Scripts/chess/sounds.lua")
    MENU = load_module("Scripts/chess/menu.lua")
    PGN = load_module("Scripts/chess/pgn.lua")
    K = load_module("Scripts/chess/clock.lua")
    B2 = load_module("Scripts/chess/board2d.lua")

    pieces = B.reset()
    state = R.new(pieces)

    -- Pristine identity per registry slot. A promotion swaps meshes between two entries,
    -- so rewinding needs the original mapping back before the board can be re-laid.
    snapshots = {}
    for i, p in ipairs(pieces) do
        snapshots[i] = {node = p.node, name = p.name, kind = p.kind, color = p.color,
                        y = p.y, radius = p.radius, base_y = p.base_y, height = p.height}
    end

    selected, targets = nil, nil
    parked, park_seq = {}, 0
    history, view_ply, scroll, panel_hot = {}, 0, nil, false
    shown_rows = 0
    -- A previous Play left its engine running (Stop Play does not unwind scene scripts), and
    -- proc holds one child at a time, so take the slot back before anything else.
    BOT.shutdown()
    bot_on, bot_side, bot_both, bot_wait = false, "B", false, nil
    -- LuaJIT here has no os.time and no os.clock; a fresh table's address is the only value on
    -- hand that differs between runs, so the blunder rolls are not identical every game.
    math.randomseed(tonumber((tostring({}):gsub("%D", "")):sub(-9)) or 1)
    anim, prev_down, promo, result = 0, false, nil, nil
    drag = nil

    -- The overlay state: booting lands on the title screen OVER a live hot-seat board, so
    -- every pre-menu driver (MCP feeds, smoke scripts) keeps working underneath it.
    if not cfg then
        cfg = {}
        for k, v in pairs(DEFAULT_CFG) do cfg[k] = v end
    end
    menu_mode = "title"
    mp_note = nil
    pgn_files, pgn_first, pgn_error = nil, 1, nil
    clock_k, clock_warned = nil, {}
    hint, ana_kind, ana_req_ply = nil, nil, nil
    eval_on, eval_view = false, nil
    analysis = false
    pgn_saved, end_wait, flag_result = false, nil, nil
    clones, hud_note, hud_note_frames = {}, nil, nil
    replay, ply_ms = nil, 0
    base_key = R.position_key(state)

    V.init(B)
    V.clear()
    V.outline_init()
    GR.init(B)
    B2.init(V.screen(), B)
    view2d = cfg.view2d == true
    B2.set_flip(cfg.side == "B")
    C.init(B)
    S.init(cfg.volume)
    MENU.init(V.screen())
    MENU.home()
    draw_board_overlay() -- G.init cleared every quad; a new game must not flash the 3D set
    pe_log("[chess] ready - White to move. Left-click a piece then a highlighted square; " ..
           "right-drag orbits, wheel zooms, and the move list on the right rewinds the game.")
end

-- The clock burns only at the live head of a running game; rewinding to review pauses it.
-- Lifted out of G.update because that function is at LuaJIT's 60-upvalue ceiling, and clock_k /
-- clock_warned / K / flag_result are used nowhere else in the loop.
local function clock_tick()
    -- Online, nothing local may stop it: the opponent's copy of our clock does not stop for
    -- our promotion picker, our pause card or the draw offer we are staring at, so neither may
    -- ours. Offline all three are a real pause.
    if not (clock_k and not result and #history > 0 and view_ply == #history and
            (online or (not replay and not promo))) then
        return
    end
    local side = state.turn
    local flagged = K.tick(clock_k, side, engine.get_metrics().delta_ms)
    if not clock_warned[side] and K.remaining(clock_k, side) < 30000 then
        clock_warned[side] = true
        if S then S.play("low_time") end
    end
    if not flagged then return end
    local winner = (flagged == "W") and "B" or "W"
    if R.cannot_mate(state, winner) then
        flag_result = "Draw - timeout vs insufficient material"
    else
        flag_result = ((flagged == "W") and "Black" or "White") .. " wins on time"
    end
    result = flag_result
    game_over_fx()
end

function G.update()
    if not state then return end

    -- Before anything else, and ALSO while a menu is open: the lobby screen is where a peer
    -- connects, and beacons stop being heard the moment nobody drains them.
    lan_tick(engine.get_metrics().delta_ms or 16)

    local down = input.is_left_mouse_down()
    local pressed = down and not prev_down
    local released = prev_down and not down
    prev_down = down

    -- An open overlay owns the frame: gameplay, the bot, the clock and the camera all
    -- pause behind it. (A search already in flight simply parks in the pipe until resume.)
    -- Wheel is NOT UI-gated in the engine, so skipping C.update is what stops zoom-through.
    if menu_mode then
        -- The 2D board keeps drawing under the overlay: open_menu wipes every quad, and
        -- without this the 3D set would show through the menu's translucent backdrop.
        draw_board_overlay()
        if online then clock_tick() end
        -- Flagging (or a resignation off the wire) behind the card ends the game there and
        -- then. `end_wait` is what says the game ended just now rather than before the card
        -- was opened -- without it, opening the pause card on a finished game to reach Main
        -- menu would bounce straight back to the end card.
        if end_wait and result and menu_mode == "pause" then
            end_wait = nil
            open_menu("end")
        end
        menu_frame(pressed)
        return
    end

    local delta_ms = engine.get_metrics().delta_ms or 16

    if not view2d then
        -- Zoom is suppressed over the move list, which scrolls with the same wheel.
        C.update(not panel_hot) -- orbit/zoom stays live even while a move animates
        GR.set_view(C.view())   -- highlights ride the view angle, see LIFT_K in grid.lua
    end

    replay_tick(delta_ms)

    -- Reviewing an earlier position does NOT lock the board: moving from there is how the
    -- analysis branch is made, and finish() truncates the moves that used to follow.
    if not replay then bot_tick() end
    analysis_tick()

    if not replay and not result and not promo and view_ply == #history then
        local step = delta_ms
        if step > 250 then step = 250 end
        ply_ms = (ply_ms or 0) + step
    end

    clock_tick()

    if end_wait and not replay then
        -- The card waits a beat, and only lands if the player is still at the live head —
        -- clicking into the move list to review cancels it.
        if view_ply < #history then end_wait = nil
        else
            end_wait = end_wait - 1
            if end_wait <= 0 then
                end_wait = nil
                open_menu("end")
                return
            end
        end
    end

    -- The side the engine plays is not clickable, so a stray click cannot move for it.
    local human_turn = not replay and not bot_to_move() and not remote_to_move()
    local hov_file, hov_rank
    if human_turn and not (anim > 0 or promo or result) then
        -- Same square either way: 2D reads the cursor pixel, 3D casts a ray. While a piece
        -- is in hand the ray must ignore pieces — the carried one is under the cursor and
        -- would win every pick, and dropping ONTO a piece is how you capture.
        if view2d then hov_file, hov_rank = B2.pick(V)
        elseif drag and drag.active then hov_file, hov_rank = V.pick_square()
        else hov_file, hov_rank = V.pick(pieces) end

        if pressed and hov_file then
            click(hov_file, hov_rank)
            -- Arm a drag only if that press left this very square selected, i.e. it was a
            -- piece of the side to move. Pressing a legal target already played the move.
            if selected and selected.file == hov_file and selected.rank == hov_rank then
                local mx, my = V.cursor()
                drag = {file = hov_file, rank = hov_rank, x0 = mx or 0, y0 = my or 0,
                        x = mx, y = my, active = false}
            end
        end
        drag_follow()
    elseif drag then
        cancel_drag()
    end

    if released and drag then
        local dropped = drag.active and hov_file
        -- A press-and-release without travel is a click; the piece is already selected and
        -- the second click will land the move, so leave the selection alone.
        if dropped then
            local m = target_at(hov_file, hov_rank)
            -- Only put it back when the drop is not a move: a real move glides on from
            -- where you let go, which reads as one continuous gesture.
            if not m then cancel_drag() else drag = nil end
            click(hov_file, hov_rank)
        else
            cancel_drag()
        end
    end

    -- Hover: any piece under the cursor is outlined in the brighter gold, selected or not —
    -- one rule, no exceptions. Off every piece, the single outline slot falls back to the
    -- selected piece in the normal gold. In 2D the outline pass draws behind the board's
    -- opaque backdrop, so board2d tints the square instead.
    if view2d then
        V.outline(nil)
    else
        local carried = drag and drag.active and drag_piece() or nil
        local hov = hov_file and state.board[hov_rank][hov_file] or nil
        if carried then
            V.outline(carried.node, true)
        elseif hov then
            V.outline(hov.piece.node, true)
        elseif selected then
            local sq = state.board[selected.rank][selected.file]
            V.outline(sq and sq.piece and sq.piece.node or nil)
        else
            V.outline(nil)
        end
    end

    local marks = compute_marks()
    local s = runtime_ui.get_surface_size()
    B2.begin(s.w, s.h)
    if view2d then
        GR.clear()
        B2.board(state, marks, hov_file, hov_rank, drag)
    else
        draw_grid(marks)
    end
    draw_trays() -- both views: the tray is screen-space either way
    B2.finish()
    draw_moves(s.w, s.h)
    -- The in-game Menu button calls open_menu (V.clear) mid-draw_moves; skip the HUD so
    -- those quads are not recreated under the pause overlay on the same frame.
    if menu_mode then return end
    draw_hud(s.w, s.h)
    if view2d then V.coords_hide() else V.coords(s.w, s.h) end
    if hud_note_frames then
        hud_note_frames = hud_note_frames - 1
        if hud_note_frames <= 0 then hud_note, hud_note_frames = nil, nil end
    end
    if eval_on and eval_view then
        V.vbar("eval", 14, s.h * 0.25, 18, s.h * 0.5, eval_view.frac, eval_view.label)
    end
end

function G.destroy()
    if BOT then BOT.shutdown() end
    if GR then GR.destroy() end
    if V then V.clear() end
    if B2 then B2.reset() end
    state = nil
end

-- ── scripted driver ────────────────────────────────────────────────────────
-- Plays a move in coordinate notation ("e2e4", "e7e8q"). Runs the exact same path as a
-- mouse move, so it verifies animation, capture parking, castling and promotion without
-- synthesising pointer input.
function G.move(text)
    if result then return false, "game over: " .. result end
    local ff, fr, tf, tr = text:byte(1) - 97, tonumber(text:sub(2, 2)),
                           text:byte(3) - 97, tonumber(text:sub(4, 4))
    local want = text:sub(5, 5):upper()
    for _, m in ipairs(R.legal_moves(state, ff, fr)) do
        if m.to_f == tf and m.to_r == tr and (want == "" or m.promo == want) then
            if m.promo and want == "" then
                -- default to a queen when the caller did not say
                if m.promo ~= "Q" then goto continue end
            end
            finish(m)
            return true
        end
        ::continue::
    end
    return false, "illegal: " .. text
end

-- Select a square by name ("g1") exactly as a click would, and read back the squares
-- that are currently highlighted. Every legal move of the selected piece gets a square,
-- so #G.targets() must equal the legal-move count for that piece.
function G.select(square)
    local file = square:byte(1) - 97
    local rank = tonumber(square:sub(2, 2))
    select_square(file, rank)
    return G.targets()
end

function G.targets()
    local out = {}
    for _, m in ipairs(targets or {}) do
        local name = B.square_name(m.to_f, m.to_r)
        out[#out + 1] = m.promo and (name .. "=" .. m.promo) or name
    end
    return out
end

-- The game so far in algebraic notation, and the half-move currently on the board.
function G.history()
    local out = {}
    for i, rec in ipairs(history) do out[i] = rec.san end
    return out
end

function G.goto_ply(n)
    scroll = nil
    return goto_ply(n)
end

-- Read the orbit state, or drive it: G.camera(yaw_deg, pitch_deg, distance).
function G.camera(yaw_deg, pitch_deg, distance)
    if yaw_deg or pitch_deg or distance then return C.set(yaw_deg, pitch_deg, distance) end
    return C.get()
end

-- Start a fresh game: {side="W"|"B"|"hotseat"|"auto", elo=, clock_min=, clock_inc=, sound=}.
-- Anything omitted falls back to the current config; the clock defaults OFF.
function G.new_game(c)
    c = c or {}
    local base = cfg or DEFAULT_CFG
    local next_cfg = {}
    -- Carry the live settings forward, fall back to the defaults, then let the caller
    -- override. Explicit nil tests, not `and/or`: `false` is a legal value for two of these.
    for k, v in pairs(DEFAULT_CFG) do
        if base[k] ~= nil then next_cfg[k] = base[k] else next_cfg[k] = v end
    end
    for k, v in pairs(c) do next_cfg[k] = v end
    -- A scripted new game starts clockless unless it asks for one, whatever the last game used.
    next_cfg.clock_min = c.clock_min or 0
    next_cfg.clock_inc = c.clock_inc or 0
    start_game(next_cfg)
    return G.status()
end

function G.hint()
    if result or view_ply < #history then return false end
    request_analysis("hint", 14)
    return true
end

-- Write the game so far to Assets/Save/last_game.pgn (writable under a packed export).
function G.save_pgn()
    local white, black = "Player (White)", "Player (Black)"
    if bot_on then
        local name = "Stockfish (" .. (BOT.unlimited() and "Max" or (BOT.elo() .. " Elo")) .. ")"
        if bot_both then white, black = name, name
        elseif bot_side == "W" then white = name else black = name end
    end
    local res
    if not result then res = "*"
    elseif result:find("White wins") == 1 then res = "1-0"
    elseif result:find("Black wins") == 1 then res = "0-1"
    else res = "1/2-1/2" end
    local moves, emts = {}, {}
    for i, rec in ipairs(history) do
        moves[i] = rec.san
        emts[i] = rec.emt
    end
    local body = PGN.build{moves = moves, emts = emts, result = res, white = white, black = black}
    local ok = fs.write(PGN.path(), body)
    if not ok then ok = fs.write("Games/last_game.pgn", body) end
    pgn_saved = ok and true or false
    return pgn_saved
end

function G.load_pgn(text)
    local parsed, err = PGN.parse(text)
    if not parsed then return false, err or "parse failed" end
    start_game(cfg or DEFAULT_CFG)
    for i, san in ipairs(parsed.moves) do
        local m = R.parse_san(state, san)
        if not m then
            pe_log("[chess] PGN stalled at " .. tostring(san))
            break
        end
        local rec_san = apply(m, true)
        history[#history + 1] = {
            from_f = m.from_f, from_r = m.from_r, to_f = m.to_f, to_r = m.to_r,
            promo = m.promo, san = rec_san, emt = parsed.emts and parsed.emts[i],
            key = R.position_key(state),
        }
    end
    view_ply = #history
    analysis = true
    refresh_result()
    -- Resignation / agreed draw / timeout live in the PGN result, not the pieces.
    if not result and parsed.result and parsed.result ~= "*" then
        if parsed.result == "1-0" then flag_result = "White wins"
        elseif parsed.result == "0-1" then flag_result = "Black wins"
        else flag_result = "Draw" end
        result = flag_result
    end
    return true, #history
end

-- Play back `history` with each ply's recorded think-time. `text` loads that PGN first.
-- With no args: Pause / Continue / restart from ply 0 of the current game.
function G.replay(text)
    if online then return false, "not while playing online" end
    if replay and not replay.paused then
        replay.paused = true
        return true
    end
    if replay and replay.paused and view_ply < #history then
        replay.paused = false
        return true
    end
    if text and text ~= "" then
        local ok, err = G.load_pgn(text)
        if not ok then return false, err end
    elseif #history == 0 then
        local last = PGN.read_last()
        if not last then return false, "no game" end
        local ok, err = G.load_pgn(last)
        if not ok then return false, err end
    end
    G.bot(0)
    eval_on, eval_view = analysis, nil
    end_wait = nil
    replay = {paused = false, wait = 0}
    goto_ply(0)
    replay.wait = wait_for_next()
    return true
end

function G.takeback()
    replay = nil
    if #history == 0 then return false end
    local n = 1
    if bot_on and not bot_both then
        local last_color = (#history % 2 == 1) and "W" or "B"
        if last_color == bot_side then n = 2 end
        if n > #history then n = #history end
    end
    for _ = 1, n do history[#history] = nil end
    flag_result, result = nil, nil
    goto_ply(#history)
    return true
end

local function human_color()
    if bot_both then return state.turn end
    if bot_on then return (bot_side == "W") and "B" or "W" end
    return state.turn
end

function G.resign()
    if result then return false end
    if online then
        LAN.send_resign()
        local winner = (my_color == "W") and "Black" or "White"
        flag_result = winner .. " wins by resignation"
        result = flag_result
        game_over_fx()
        return true
    end
    local loser = human_color()
    flag_result = ((loser == "W") and "Black" or "White") .. " wins by resignation"
    result = flag_result
    game_over_fx()
    return true
end

local function bot_would_accept_draw()
    if R.insufficient(state) then return true end
    if not eval_view then return BOT.elo() < 2000 end
    if eval_view.label and eval_view.label:find("#", 1, true) then
        local white_mates = eval_view.label:sub(1, 1) == "+"
        return not ((bot_side == "W") == white_mates)
    end
    if bot_side == "W" then return (eval_view.frac or 0.5) < 0.72 end
    return (eval_view.frac or 0.5) > 0.28
end

function G.offer_draw()
    if result then return false end
    if not bot_on or bot_both or bot_would_accept_draw() then
        result = "Draw - agreed"
        game_over_fx()
        return true
    end
    hud_note, hud_note_frames = "Bot declines", 180
    return false
end

-- Drive the overlays from a script: "title" | "pause" | "end" opens, false/nil closes.
function G.set_menu(mode, page)
    if mode == "title" or mode == "pause" or mode == "end" then open_menu(mode)
    else close_menu() end
    -- After open_menu, which resets the tree to its root.
    if page and MENU then MENU.goto_page(page) end
    return menu_mode, MENU and MENU.page() or nil
end

-- Which board is drawn, and which way round. Called with no argument it just reports.
function G.view2d(on, flip)
    if on ~= nil then set_view2d(on) end
    if flip ~= nil then B2.set_flip(flip) end
    return {view2d = view2d, flipped = B2.flipped()}
end

-- Centre pixel of a square on the 2D board, in the SAME pixel space b2.pick reads the
-- cursor from. Exposed so a session can drive the board without re-deriving board2d's
-- layout: a copy of that maths in a test rig silently aims at the wrong square the next
-- time the layout changes.
function G.square_px(file, rank)
    local w, h = V.viewport()
    if not w then return nil end
    local x, y, s = B2.square_rect(B2.layout(w, h), file, rank)
    return x + s * 0.5, y + s * 0.5
end

function G.status()
    return {
        view2d = view2d,
        analysis = analysis or false,
        color = my_color or false,
        rematch = rematch_offered and "offered" or (rematch_sent and "sent") or false,
        peer = peer_name and {name = peer_name, live = peer_live and true or false} or false,
        offer_in = offer_in or false,
        offer_sent = offer_sent or false,
        online = online or false,
        lan = LAN and {role = LAN.role() or false, ready = LAN.ready(),
                       note = LAN.note() or false, lobbies = #LAN.lobbies()} or false,
        eval = eval_on or false,
        -- Read-only: script.chess.menu() is a SETTER and closes the overlay when called
        -- with no mode, so it cannot be used to ask where the menu is.
        menu = menu_mode or false,
        menu_page = MENU and MENU.page() or false,
        -- Remaining ms per side: the HUD reads K directly, but a script (or a harness)
        -- cannot, and "did the clock keep running" is not answerable without it.
        clock = clock_k and {w = K.remaining(clock_k, "W"), b = K.remaining(clock_k, "B")} or false,
        turn = state.turn,
        check = R.in_check(state, state.turn),
        result = result,
        legal = #R.legal_moves(state),
        parked = #parked,
        ply = view_ply,
        moves = #history,
        bot = bot_on and G.bot_status() or false,
    }
end

return G
