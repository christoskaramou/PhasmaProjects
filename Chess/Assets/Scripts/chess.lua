-- chess.lua — scene on_play entry point.
--
-- Hot-seat chess on the ABeautifulGame set: both sides are played with the mouse.
-- Click a piece of the side to move, then click one of the highlighted squares.
-- Yellow marks a quiet move, red a capture, blue the move just played.
--
-- The move list on the right is clickable: any move rewinds the board to the position
-- after it, and playing on from there discards the rest, like an analysis board.
--
-- The modules live in Scripts/chess/: board (geometry + piece registry), rules
-- (legal move generation + notation), grid (the on-board square highlights),
-- view (cursor picking + overlay), game (this loop's brain).

local game = (function()
    local path = "Scripts/chess/game.lua"
    local src = fs.read(path)
    if not src then error("[chess] game module not found at " .. path) end
    return load(src, "@" .. path, "bt", _ENV)()
end)()

-- Exposed so a session can drive moves without a mouse, from the editor console or MCP:
--   script.chess.move("e2e4")   script.chess.select("g1")   script.chess.status()
--
-- A scene script runs in its own environment whose `_G` is that environment, not the host's
-- globals — so assigning a new global here is invisible to the script host. Mutating a table
-- the host already owns is not: `script` is created once in the main Lua state and inherited
-- by reference, so a field added to it is shared.
local api = {
    move = function(text) return game.move(text) end,
    select = function(square) return game.select(square) end,
    targets = function() return game.targets() end,
    status = function() return game.status() end,
    history = function() return game.history() end,
    goto_ply = function(n) return game.goto_ply(n) end,
    bot = function(elo, side) return game.bot(elo, side) end,
    camera = function(yaw_deg, pitch_deg, dist) return game.camera(yaw_deg, pitch_deg, dist) end,
    reset = function() game.init() end,
    new_game = function(c) return game.new_game(c) end,
    hint = function() return game.hint() end,
    save_pgn = function() return game.save_pgn() end,
    load_pgn = function(text) return game.load_pgn(text) end,
    takeback = function() return game.takeback() end,
    resign = function() return game.resign() end,
    offer_draw = function() return game.offer_draw() end,
    replay = function(text) return game.replay(text) end,
    menu = function(mode, page) return game.set_menu(mode, page) end,
    view2d = function(on, flip) return game.view2d(on, flip) end,
    square_px = function(file, rank) return game.square_px(file, rank) end,
    tick = function() game.update() end,
}
script.chess = api
_G.chess = api -- convenience for anything sharing this environment

game.init()
script.on_update("chess", function() game.update() end, "play")
