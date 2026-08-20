-- board2d.lua — the flat 2D board: a second way to DRAW and CLICK the same game.
--
-- Nothing here touches game state. The 3D set keeps moving, tweening and parking behind an
-- opaque backdrop exactly as it always did, so toggling mid-game is free and cannot desync:
-- 2D is a view, not a mode. The pieces are read straight out of `state.board` every frame.
--
-- Pixels: one `square_rect` / `square_at` pair does both directions, so what is drawn and
-- what is clicked cannot drift apart (b2.selftest round-trips all 64 in both orientations).
--
-- Layering: runtime_ui sorts quads by `z` (RuntimeUi.cpp SortQuadWidgets), so the whole 2D
-- layer lives at negative z and the HUD, move list and menus keep the default 0 above it.

local b2 = {}

local SCREEN = "chess"
local IMG = "UI/chess2d/" -- resolved under the project's Assets/
local KINDS = {"K", "Q", "R", "B", "N", "P"}

local Z_BACK, Z_SQUARE, Z_MARK, Z_PIECE, Z_DRAG = -40, -30, -20, -10, -5

local LIGHT = {0.87, 0.82, 0.72, 1}
local DARK = {0.42, 0.32, 0.24, 1}
local BACKDROP = {0.05, 0.05, 0.07, 1} -- opaque: it is what hides the 3D board
local RIM = {0.16, 0.13, 0.11, 1}
local LABEL = {0.72, 0.68, 0.58, 1}

-- Square tints, in the same spirit as grid.lua's on-board planes but flatter: there is no
-- marble showing through here, so they carry more alpha.
local MARK = {
    check   = {0.95, 0.16, 0.12, 0.55},
    capture = {0.90, 0.25, 0.18, 0.45},
    select  = {0.30, 0.88, 0.42, 0.42},
    hint    = {0.20, 0.85, 0.90, 0.45},
    last    = {0.42, 0.62, 1.00, 0.32},
}
-- Which tint wins when a square carries more than one mark.
local PRIORITY = {check = 6, capture = 5, select = 4, hint = 3, last = 2}
local HOVER = {1.00, 0.95, 0.72, 0.18}
local DOT = {0.10, 0.10, 0.09, 0.38} -- quiet-move marker, drawn as a circle

-- RuntimeUi bakes at 16px.
local FONT = 16 / 16

-- Retained-quad bookkeeping, same protocol menu.lua uses: `used` collects the ids touched
-- this frame and end_frame() hides everything else. `keep` claims an id without re-issuing
-- it, which is how the 64 board squares survive a frame without being rewritten.
local all = {}
local used = {}
local layout_key -- squares are only re-issued when the layout or orientation changes
local flip = false
local L -- last computed layout

function b2.init(screen, board)
    SCREEN = screen or SCREEN
    all, used, layout_key, L = {}, {}, nil, nil
    flip = false
    if runtime_ui and runtime_ui.preload_images then
        local paths = {}
        for _, k in ipairs(KINDS) do
            paths[#paths + 1] = IMG .. "w" .. k .. ".png"
            paths[#paths + 1] = IMG .. "b" .. k .. ".png"
        end
        runtime_ui.preload_images(paths)
    end
end

-- White at the bottom by default; flipped when the human plays Black, like every 2D board.
function b2.set_flip(on)
    if flip == (on and true or false) then return end
    flip = on and true or false
    layout_key = nil
end

function b2.flipped() return flip end

local function q(id, props)
    all[id] = "shown"
    used[id] = true
    runtime_ui.set_quad(SCREEN, id, props)
end

-- Claim an id for this frame WITHOUT re-issuing it. Returns false when the id is not
-- actually on screen any more, which is the only honest answer: the caller's "already drawn"
-- cache is stale and it has to draw again.
local function keep(id)
    if all[id] ~= "shown" then return false end
    used[id] = true
    return true
end

-- ── geometry ───────────────────────────────────────────────────────────────
-- The board is centred in what is left after the eval bar (x 14..32) on the left and the
-- move panel on the right, not in the window, or it sits under the panel on narrow windows.
local LEFT = 44
local GAP = 16
local TRAY = 42 -- height of one captured-pieces band

function b2.layout(w, h)
    local panel_w = math.max(190, w * 0.15) + 14 + GAP
    local top = h * 0.02 + math.max(44, h * 0.045) + 20
    local avail_w = w - panel_w - LEFT
    -- 34 for the file letters under the board, plus a captured-tray band top and bottom.
    local avail_h = h - top - 34 - TRAY * 2
    local sq = math.floor(math.max(24, math.min(avail_w, avail_h) / 8))
    return {
        w = w, h = h, sq = sq,
        x = LEFT + math.floor((avail_w - sq * 8) * 0.5),
        y = top + TRAY + math.floor((avail_h - sq * 8) * 0.5),
    }
end

-- (file 0..7, rank 1..8) -> the square's top-left pixel. `lay` is a b2.layout result.
function b2.square_rect(lay, file, rank)
    local col = flip and (7 - file) or file
    local row = flip and (rank - 1) or (8 - rank)
    return lay.x + col * lay.sq, lay.y + row * lay.sq, lay.sq
end

-- a1 is DARK, and file+rank is odd there (0+1) — so even is the light square. Getting this
-- backwards is invisible until you look for it, which is why selftest pins the corners.
function b2.is_light(file, rank) return (file + rank) % 2 == 0 end

-- The inverse: a pixel -> file, rank, or nil when it is off the board.
function b2.square_at(lay, px, py)
    local col = math.floor((px - lay.x) / lay.sq)
    local row = math.floor((py - lay.y) / lay.sq)
    if col < 0 or col > 7 or row < 0 or row > 7 then return nil end
    local file = flip and (7 - col) or col
    local rank = flip and (row + 1) or (8 - row)
    return file, rank
end

-- What the cursor is over. `view` is view.lua, whose cursor() already returns nil when a
-- UI widget has the mouse — the 2D layer is all no_input, so only the move panel does.
function b2.pick(view)
    local px, py, w, h = view.cursor()
    if not px then return nil end
    return b2.square_at(b2.layout(w, h), px, py)
end

-- ── drawing ────────────────────────────────────────────────────────────────
local function plain(id, x, y, w, h, fill, z, radius)
    q(id, {
        x = x, y = y, w = w, h = h,
        style = "panel", fill = fill, accent = {0, 0, 0, 0}, border = {0, 0, 0, 0},
        corner_radius = radius or 0, z = z, no_input = true, visible = true,
    })
end

local function squares(lay)
    local key = lay.x .. ":" .. lay.y .. ":" .. lay.sq .. ":" .. tostring(flip)
    if layout_key == key then
        -- The layout has not moved, so the 64 squares should still be up from last frame.
        -- "Should" is not good enough: switching to the 3D board runs b2.finish(), which
        -- HIDES them while the layout key stays valid, and opening a menu runs
        -- runtime_ui.clear, which destroys them outright. Either way the cache is a lie and
        -- the board comes back with no squares under the pieces. So the cache checks itself:
        -- `keep` reports whether the quad is really still shown, and one miss re-issues the
        -- lot. `keep(...) and ok` never short-circuits the call -- every id must be claimed.
        local ok = keep("b2_rim")
        for file = 0, 7 do
            for rank = 1, 8 do
                ok = keep("b2_s" .. file .. rank) and ok
            end
        end
        if ok then return end
    end
    layout_key = key

    local side = lay.sq * 8
    local rim = math.max(4, math.floor(lay.sq * 0.10))
    plain("b2_rim", lay.x - rim, lay.y - rim, side + rim * 2, side + rim * 2, RIM, Z_SQUARE - 1, 4)
    for file = 0, 7 do
        for rank = 1, 8 do
            local x, y, s = b2.square_rect(lay, file, rank)
            plain("b2_s" .. file .. rank, x, y, s, s,
                  b2.is_light(file, rank) and LIGHT or DARK, Z_SQUARE)
        end
    end
end

local function labels(lay)
    local s = lay.sq
    for file = 0, 7 do
        local x = b2.square_rect(lay, file, 1)
        q("b2_lf" .. file, {
            x = x, y = lay.y + s * 8 + 2, w = s, h = 20,
            body = string.char(97 + file), style = "text", fill = {0, 0, 0, 0},
            accent = {0, 0, 0, 0}, border = {0, 0, 0, 0}, text_color = LABEL,
            align_h = "center", align_v = "middle", font_scale = FONT,
            z = Z_MARK, no_input = true, visible = true,
        })
    end
    for rank = 1, 8 do
        local _, y = b2.square_rect(lay, 0, rank)
        q("b2_lr" .. rank, {
            x = lay.x - 26, y = y, w = 22, h = s,
            body = tostring(rank), style = "text", fill = {0, 0, 0, 0},
            accent = {0, 0, 0, 0}, border = {0, 0, 0, 0}, text_color = LABEL,
            align_h = "center", align_v = "middle", font_scale = FONT,
            z = Z_MARK, no_input = true, visible = true,
        })
    end
end

-- `marks` is the shared list game.lua feeds to grid.lua as well: {f, r, m}, m naming the
-- kind of mark. Quiet moves become a centred dot, everything else tints the whole square.
local function sprite(sq)
    return IMG .. (sq.color == "W" and "w" or "b") .. sq.kind .. ".png"
end

function b2.begin(w, h)
    L = b2.layout(w, h)
    used = {}
    return L
end

-- Anything shown last frame and not touched this one goes away: marks that expired, pieces
-- that moved off their square, the whole board after a switch back to 3D.
function b2.finish()
    for id, st in pairs(all) do
        if st == "shown" and not used[id] then
            runtime_ui.set_quad(SCREEN, id, {visible = false, no_input = true})
            all[id] = "hidden"
        end
    end
end

function b2.board(state, marks, hov_f, hov_r, drag)
    if not L then return end
    local w, h = L.w, L.h
    local carrying = drag and drag.active and drag.x and drag or nil

    plain("b2_back", 0, 0, w, h, BACKDROP, Z_BACK)
    squares(L)
    labels(L)

    local best, dots = {}, {}
    for _, mk in ipairs(marks or {}) do
        local k = mk.r * 8 + mk.f
        if mk.m == "move" then
            dots[k] = true
        else
            local cur = best[k]
            if not cur or (PRIORITY[mk.m] or 0) > (PRIORITY[cur] or 0) then best[k] = mk.m end
        end
    end
    if hov_f then
        local k = hov_r * 8 + hov_f
        if not best[k] then best[k] = "hover" end
    end

    for k, m in pairs(best) do
        local file, rank = k % 8, math.floor(k / 8)
        local x, y, s = b2.square_rect(L, file, rank)
        plain("b2_m" .. file .. rank, x, y, s, s, (m == "hover") and HOVER or MARK[m], Z_MARK)
    end
    for k in pairs(dots) do
        local file, rank = k % 8, math.floor(k / 8)
        local x, y, s = b2.square_rect(L, file, rank)
        -- A rounded square whose radius is half its edge IS a circle; runtime_ui has no
        -- separate circle primitive (see RuntimeUiQuadDesc::cornerRadius).
        local d = math.floor(s * 0.30)
        plain("b2_d" .. file .. rank, x + (s - d) * 0.5, y + (s - d) * 0.5, d, d,
              DOT, Z_MARK, d * 0.5)
    end

    for rank = 1, 8 do
        for file = 0, 7 do
            local sq = state.board[rank][file]
            local id = "b2_p" .. file .. rank
            if sq then
                local x, y, s = b2.square_rect(L, file, rank)
                -- The square a carried piece came FROM keeps a ghost of it: the rules never
                -- moved it, and an empty origin square would claim the move already happened.
                local ghost = carrying and carrying.file == file and carrying.rank == rank
                q(id, {
                    x = x, y = y, w = s, h = s, image = sprite(sq),
                    style = "image", fill = {0, 0, 0, 0}, accent = {0, 0, 0, 0},
                    border = {0, 0, 0, 0},
                    image_tint = ghost and {1, 1, 1, 0.28} or {1, 1, 1, 1},
                    -- 0, not the default -1: -1 inherits the global element whiten and
                    -- re-derives a lightened copy of the sprite (RuntimeUi.cpp SetQuad).
                    image_whiten = 0,
                    z = Z_PIECE, no_input = true, visible = true,
                })
            end
        end
    end

    -- The piece in hand, centred on the cursor and above everything else on the board.
    local held = carrying and state.board[carrying.rank] and state.board[carrying.rank][carrying.file]
    if held then
        local s = L.sq
        q("b2_drag", {
            x = carrying.x - s * 0.5, y = carrying.y - s * 0.5, w = s, h = s,
            image = sprite(held), style = "image",
            fill = {0, 0, 0, 0}, accent = {0, 0, 0, 0}, border = {0, 0, 0, 0},
            image_whiten = 0, z = Z_DRAG, no_input = true, visible = true,
        })
    end
end

-- ── captured tray ──────────────────────────────────────────────────────────
-- The men off the board, as a strip of small sprites per side plus the material score.
-- Screen-space, so it reads the same on the 2D board and over the 3D set — and it beats
-- counting the parked meshes, which are scattered by capture order and half off-camera.
local VALUE = {Q = 9, R = 5, B = 3, N = 3, P = 1}
local ORDER = {"Q", "R", "B", "N", "P"} -- heaviest first, the way every chess UI shows it

-- `taken[color]` = list of kinds that COLOUR has lost. Returns the strip's height so the
-- caller can stack things under it.
-- Where a side's tray sits. Over the 2D board it hugs the board edge (which is why
-- b2.layout reserves a band above and below); over the 3D set there is no known board rect
-- on screen, so it takes a fixed column down the left, clear of the eval bar and the HUD.
function b2.tray_rect(side_at_bottom, view2d)
    if not L then return 0, 0, 24 end
    if view2d then
        local size = TRAY - 8
        -- Clear of the board's rim, and below the file letters on the bottom side.
        local rim = math.max(4, math.floor(L.sq * 0.10))
        if side_at_bottom then return L.x, L.y + L.sq * 8 + 26, size end
        return L.x, L.y - rim - size - 6, size
    end
    local size = 34
    if side_at_bottom then return LEFT, L.h - size - 20, size end
    return LEFT, L.h * 0.10, size
end

-- `taken` is the list of piece kinds THIS side has captured, `prefix` the sprite colour of
-- those men ("w"/"b"), `other_taken` what the opponent has captured (for the material edge).
function b2.tray(id, x, y, taken, prefix, size, other_taken)
    local counts = {}
    for _, k in ipairs(taken or {}) do counts[k] = (counts[k] or 0) + 1 end

    local n, step = 0, size * 0.62 -- overlapped: 16 pawns must fit beside an 8-square board
    for _, kind in ipairs(ORDER) do
        for _ = 1, (counts[kind] or 0) do
            q(id .. "_" .. n, {
                x = x + n * step, y = y, w = size, h = size,
                image = IMG .. prefix .. kind .. ".png", style = "image",
                fill = {0, 0, 0, 0}, accent = {0, 0, 0, 0}, border = {0, 0, 0, 0},
                image_whiten = 0, z = Z_MARK, no_input = true, visible = true,
            })
            n = n + 1
        end
    end

    -- Material edge, shown only by the side that is ahead — "+0" on both sides is noise.
    local mine, theirs = 0, 0
    for _, k in ipairs(taken or {}) do mine = mine + (VALUE[k] or 0) end
    for _, k in ipairs(other_taken or {}) do theirs = theirs + (VALUE[k] or 0) end
    local edge = mine - theirs
    if edge > 0 then
        q(id .. "_edge", {
            x = x + n * step + 10, y = y, w = 52, h = size, body = "+" .. edge,
            style = "text", fill = {0, 0, 0, 0}, accent = {0, 0, 0, 0}, border = {0, 0, 0, 0},
            text_color = {0.85, 0.82, 0.72, 1}, align_h = "left", align_v = "middle",
            font_scale = FONT + 0.15, z = Z_MARK, no_input = true, visible = true,
        })
    end
    return n
end

-- Forget every id without touching runtime_ui: for after something else wiped the screen
-- (view.clear -> runtime_ui.clear), where "already shown" would skip re-issuing the squares.
function b2.reset()
    all, used, layout_key = {}, {}, nil
end

-- Idempotent: after the first call every id is already "hidden" and this is a bare loop.
function b2.hide()
    for id, st in pairs(all) do
        if st == "shown" then
            runtime_ui.set_quad(SCREEN, id, {visible = false, no_input = true})
            all[id] = "hidden"
        end
    end
    used, layout_key = {}, nil
end

-- Self-check: every square's centre pixel maps back to that square, in both orientations,
-- and a pixel outside the board maps to nothing.
function b2.selftest()
    -- Square colours first: a1/h8 dark, h1/a8 light, and e4 light.
    for _, c in ipairs({{0, 1, false}, {7, 8, false}, {7, 1, true}, {0, 8, true}, {4, 4, true}}) do
        assert(b2.is_light(c[1], c[2]) == c[3],
               "wrong square colour at " .. string.char(97 + c[1]) .. c[2])
    end

    local lay = {x = 100, y = 50, sq = 64}
    local was = flip
    for _, f in ipairs({false, true}) do
        flip = f
        for file = 0, 7 do
            for rank = 1, 8 do
                local x, y, s = b2.square_rect(lay, file, rank)
                local f2, r2 = b2.square_at(lay, x + s * 0.5, y + s * 0.5)
                assert(f2 == file and r2 == rank,
                       ("2D round-trip failed at %d,%d (flip=%s)"):format(file, rank, tostring(f)))
            end
        end
        -- a1 must sit at the near-left corner from the side that is at the bottom.
        local ax, ay = b2.square_rect(lay, 0, 1)
        local ex = f and (lay.x + lay.sq * 7) or lay.x
        local ey = f and lay.y or (lay.y + lay.sq * 7)
        assert(ax == ex and ay == ey, "a1 is in the wrong corner for flip=" .. tostring(f))
        assert(b2.square_at(lay, lay.x - 1, lay.y + 10) == nil, "off-board pixel picked a square")
        assert(b2.square_at(lay, lay.x + 10, lay.y + lay.sq * 8 + 1) == nil, "below-board pixel picked a square")
    end
    flip = was
    return true
end

return b2
