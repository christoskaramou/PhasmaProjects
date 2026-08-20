-- board.lua — board geometry and the piece registry for the ABeautifulGame chess set.
--
-- Everything downstream (picking, rules, moves) reads this module. Squares are addressed
-- as (file, rank) with file 0..7 = a..h and rank 1..8; white plays up the board from rank 1.
--
-- The model is authored at real scale: the board is 0.5 m across, centred on the origin,
-- with its playing surface at y ~= 0.017. Files run along -x (a is +x, h is -x) and ranks
-- along +z, so white's back rank sits at z = -0.21875.

local B = {}

B.PITCH = 0.0625 -- metres per square (0.5 m board / 8)
B.RIM = 0.002695 -- how far the board's outer rim stands above the playing squares (see scan)

-- Piece kind from the glTF node-name prefix. "Castle" is this model's name for the rook.
local KIND = {King = "K", Queen = "Q", Castle = "R", Knight = "N", Bishop = "B", Pawn = "P"}

-- Back rank layout, files a..h.
local BACK_RANK = {"R", "N", "B", "Q", "K", "B", "N", "R"}

function B.square_to_world(file, rank)
    return (3.5 - file) * B.PITCH, (rank - 4.5) * B.PITCH
end

function B.world_to_square(x, z)
    local file = math.floor(3.5 - x / B.PITCH + 0.5)
    local rank = math.floor(z / B.PITCH + 5.0)
    if file < 0 or file > 7 or rank < 1 or rank > 8 then return nil end
    return file, rank
end

function B.square_name(file, rank)
    return string.char(97 + file) .. tostring(rank)
end

-- Node name -> kind, color. Pawns are two nodes (Pawn_Top_* is a CHILD of Pawn_Body_*),
-- so only the body is a piece; moving it carries the top along.
local function parse_name(name)
    local prefix, color = name:gsub("_Body", ""):match("^(%a+)_([WB])%d*$")
    if not prefix then return nil end
    return KIND[prefix], color
end

-- A piece's click volume. Taken from the real mesh AABB (unioned with children, so a
-- pawn's glass top counts) rather than guessed: kings are 15 cm tall on 6.25 cm squares,
-- and a wrong height throws cursor picking off by whole ranks.
local function bounds(node)
    local bb = node:get_bounding_box()
    local min_y, max_y = bb.min.y, bb.max.y
    local w = math.max(bb.size.x, bb.size.z)
    for _, child in ipairs(node:get_children()) do
        local cb = child:get_bounding_box()
        min_y = math.min(min_y, cb.min.y)
        max_y = math.max(max_y, cb.max.y)
        w = math.max(w, cb.size.x, cb.size.z)
    end
    return w * 0.5, min_y, max_y - min_y
end

-- Build the registry from the live scene. Returns a list of pieces, each:
--   {node, name, kind, color, y, file, rank, radius, base_y, height}
-- `y` is the piece's authored height, preserved across moves (it differs per piece type).
-- B.top_y is set to the board's playing surface.
function B.scan()
    local root
    for _, e in ipairs(scene.get_entities()) do
        if e.label == "ROOT" then root = e.node end
    end
    if not root then error("[chess] ROOT node not found — is chess.pescene loaded?") end

    local pieces = {}
    for _, node in ipairs(root:get_children()) do
        local name = node:get_name()
        if name == "Chessboard" then
            -- NOT the bounding box max: the board is one mesh whose AABB top (0.018515) is the
            -- raised outer RIM, 2.7 mm proud of the squares. Highlights placed there floated
            -- visibly above the board and cut through the pieces' bases. The playing surface was
            -- measured by sweeping a test plane per file until it stopped being swallowed by the
            -- board — it is at 0.01582, and the rim offset is what B.RIM records.
            B.top_y = node:get_bounding_box().max.y - B.RIM
        end
        local kind, color = parse_name(name)
        if kind then
            local p = node:get_world_position()
            local file, rank = B.world_to_square(p.x, p.z)
            local radius, base_y, height = bounds(node)
            pieces[#pieces + 1] = {
                node = node, name = name, kind = kind, color = color,
                y = p.y, file = file, rank = rank,
                radius = radius, base_y = base_y, height = height,
            }
        end
    end
    B.top_y = B.top_y or 0.0185
    return pieces
end

-- Occupancy map keyed by square name, so callers can ask `occ["e4"]`.
function B.occupancy(pieces)
    local occ = {}
    for _, p in ipairs(pieces) do
        if p.file then occ[B.square_name(p.file, p.rank)] = p end
    end
    return occ
end

function B.place(piece, file, rank)
    local x, z = B.square_to_world(file, rank)
    piece.node:set_world_position(vec3(x, piece.y, z))
    piece.file, piece.rank = file, rank
    -- Captured men are hidden rather than shelved (see park in game.lua); landing on a
    -- square is what brings one back, which is how B.reset restores a rewound set.
    if piece.hidden then
        piece.hidden = nil
        piece.node:set_enabled(true)
    end
end

-- Move every piece to the standard opening position. The model ships a mid-game layout,
-- so this is needed before a game can start. Within a kind, pieces are assigned to target
-- files in their current file order so none visibly cross over another.
function B.reset(pieces)
    pieces = pieces or B.scan()

    local groups = {} -- groups["WP"] = {piece, ...}
    for _, p in ipairs(pieces) do
        local key = p.color .. p.kind
        groups[key] = groups[key] or {}
        table.insert(groups[key], p)
    end
    -- Captured pieces are parked off the board and have no file, so they sort last and
    -- get whatever target squares the on-board pieces of their kind did not take.
    for _, g in pairs(groups) do
        table.sort(g, function(a, b) return (a.file or 99) < (b.file or 99) end)
    end

    local function assign(color, kind, rank, files)
        local g = groups[color .. kind] or {}
        for i, file in ipairs(files) do
            if g[i] then B.place(g[i], file, rank) end
        end
    end

    for _, color in ipairs({"W", "B"}) do
        local back = (color == "W") and 1 or 8
        local pawn = (color == "W") and 2 or 7
        local by_kind = {}
        for file = 0, 7 do
            local kind = BACK_RANK[file + 1]
            by_kind[kind] = by_kind[kind] or {}
            table.insert(by_kind[kind], file)
        end
        for kind, files in pairs(by_kind) do
            assign(color, kind, back, files)
        end
        assign(color, "P", pawn, {0, 1, 2, 3, 4, 5, 6, 7})
    end

    return pieces
end

-- Self-check: square math round-trips, and the live scene holds a full 32-piece set.
function B.selftest()
    for file = 0, 7 do
        for rank = 1, 8 do
            local x, z = B.square_to_world(file, rank)
            local f2, r2 = B.world_to_square(x, z)
            assert(f2 == file and r2 == rank,
                   "round-trip failed at " .. B.square_name(file, rank))
        end
    end
    assert(B.world_to_square(0.5, 0.0) == nil, "off-board x should not map to a square")

    local pieces = B.scan()
    assert(#pieces == 32, "expected 32 pieces, got " .. #pieces)
    local counts = {}
    for _, p in ipairs(pieces) do
        counts[p.color .. p.kind] = (counts[p.color .. p.kind] or 0) + 1
        assert(p.file, p.name .. " is not on a square")
    end
    for _, color in ipairs({"W", "B"}) do
        for kind, n in pairs({K = 1, Q = 1, R = 2, N = 2, B = 2, P = 8}) do
            assert(counts[color .. kind] == n,
                   ("expected %d %s%s, got %s"):format(n, color, kind, tostring(counts[color .. kind])))
        end
    end
    return pieces
end

return B
