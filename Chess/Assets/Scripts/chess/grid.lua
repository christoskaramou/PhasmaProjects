-- grid.lua — one flat plane per board square, laid exactly on the checkerboard.
--
-- This replaces the old screen-space square markers. Those were axis-aligned UI rects
-- projected at a square's centre, so they only lined up with the board when the camera
-- happened to look straight down; the moment you orbited, a "square" highlight sat on a
-- rhombus of marble. These planes are real geometry on the board, so a highlight is the
-- square, at any camera angle, and it works in PhasmaPlayer as well as the editor.
--
-- The primitive is Primitives::CreatePlane: 10x10 units in the XZ plane with a +Y normal,
-- so one board square is a uniform scale of PITCH/10 and needs no rotation.

local grid = {}

local ROOT = "ChessGrid" -- name of the group node the 64 squares hang off

local BOARD
local root       -- the group node handle
local cells      -- cells[rank][file] = node handle
local shown      -- key -> colour currently applied
local pending    -- key -> colour requested this frame

-- How far a highlight floats above the playing surface. This CANNOT be one number.
--
-- Two parallel horizontal planes offset by dy differ in view-space depth by only dy*sin(elevation),
-- so as the camera drops toward the board that difference collapses and the board wins the depth
-- test — squares vanish from the far half inward, which is what "the grid gets cut" looks like.
-- Measured: at 80 deg a few microns is enough; at 38 deg it takes ~0.8 mm; at 10 deg even 0.8 mm
-- loses and only ~5 mm survives. A constant either floats visibly at a normal viewing angle or
-- disappears at a low one.
--
-- So the lift tracks the camera: it cancels the same sin(elevation) that causes the problem, and
-- scales with distance because the depth difference shrinks with range too. At the angles the game
-- is actually played from this lands at a few tenths of a millimetre — invisible on a 62.5 mm
-- square — and only grows when the camera lies down on the board, where a vertical offset is the
-- least of what you cannot see anyway.
-- ponytail: the real fix is a slope-scaled depth bias on the alpha-blend pipeline (the engine
-- already does exactly this for RenderType::SpriteOutline in LinesPass). That is an engine change;
-- this is a script-side equivalent.
local LIFT_K = 0.0009      -- metres of lift per metre of range, at a right angle to the board
local LIFT_MIN = 0.00005
local LIFT_MAX = 0.0040
local lift = LIFT_MIN
local lift_applied = nil

-- Hiding is set_enabled, NOT set_visible. set_visible only flips the raster cull flag; the
-- node stays in the RT TLAS, and this scene renders in hybrid mode, so 62 hidden white
-- planes still bounced light and washed the whole board out. set_enabled drops them from
-- the instance set and the TLAS. It costs a TLAS rebuild per flip, which is why flush()
-- below only touches squares whose colour actually changed.

-- {r, g, b, alpha, glow}. Held as module constants so the diff below can compare by
-- identity and skip the material write when a square keeps its colour between frames.
grid.SELECT  = {0.25, 0.90, 0.40, 0.30, 0.20}
grid.MOVE    = {1.00, 0.88, 0.25, 0.20, 0.10}
grid.CAPTURE = {0.95, 0.22, 0.16, 0.26, 0.15}
grid.LAST    = {0.35, 0.60, 1.00, 0.18, 0.10}
grid.CHECK   = {0.95, 0.12, 0.10, 0.34, 0.22} -- king's square while in check
grid.HINT    = {0.20, 0.85, 0.90, 0.24, 0.14} -- engine suggestion, from + to

local function key(file, rank) return rank * 8 + file end

local function paint(node, c)
    material.set(node, "base_color", vec4(c[1], c[2], c[3], c[4]))
    material.set(node, "emissive", vec3(c[1] * c[5], c[2] * c[5], c[3] * c[5]))
end

function grid.init(board)
    BOARD = board
    grid.destroy()
    cells, shown, pending = {}, {}, {}
    -- All 64 hang off one empty node, so the editor hierarchy gets a single collapsible
    -- "ChessGrid" entry instead of 64 siblings drowning the scene's real contents.
    root = scene.add_empty_node(ROOT)
    for rank = 1, 8 do
        cells[rank] = {}
        for file = 0, 7 do
            local node = scene.add_empty_node(board.square_name(file, rank))
            node:set_parent(root)
            scene.attach_primitive(node, "plane")
            node:set_scale(vec3(board.PITCH / 10, 1.0, board.PITCH / 10))
            local x, z = board.square_to_world(file, rank)
            -- After set_parent, because reparenting keeps the LOCAL transform and would
            -- otherwise move the square.
            node:set_world_position(vec3(x, board.top_y + lift, z))
            material.set_render_type(node, "alpha_blend")
            node:set_enabled(false)
            cells[rank][file] = node
        end
    end
end

-- Re-height every square for the current viewpoint. Cheap to call every frame: it only touches
-- the nodes when the required lift actually moved, which is while the camera is being dragged.
function grid.set_view(dist, pitch_rad)
    if not cells then return end
    local s = math.max(math.sin(pitch_rad or 1.0), 0.08)
    lift = math.min(LIFT_MAX, math.max(LIFT_MIN, LIFT_K * (dist or 0.6) / s))
    if lift_applied and math.abs(lift - lift_applied) < 0.00002 then return end
    lift_applied = lift
    local y = BOARD.top_y + lift
    for rank = 1, 8 do
        for file = 0, 7 do
            local node = cells[rank][file]
            local p = node:get_world_position()
            node:set_world_position(vec3(p.x, y, p.z))
        end
    end
end

-- Frame protocol: begin(), set() the squares that should be lit, flush(). Squares not
-- named this frame are hidden, and a square that keeps its colour is left untouched.
function grid.begin()
    pending = {}
end

function grid.set(file, rank, colour)
    if cells and cells[rank] and cells[rank][file] then pending[key(file, rank)] = colour end
end

function grid.flush()
    if not cells then return end
    for k, colour in pairs(pending) do
        if shown[k] ~= colour then
            local node = cells[math.floor(k / 8)][k % 8]
            paint(node, colour)
            node:set_enabled(true)
        end
    end
    for k in pairs(shown) do
        if not pending[k] then cells[math.floor(k / 8)][k % 8]:set_enabled(false) end
    end
    shown = pending
end

function grid.clear()
    grid.begin()
    grid.flush()
end

function grid.destroy()
    -- By name rather than the cells table: a Play->Stop->Play cycle re-runs init with a fresh
    -- table while the previous run's nodes are still in the scene. find_model searches every
    -- node, which get_entities does not do for a mesh-less group node.
    local previous = scene.find_model(ROOT)
    while previous do
        scene.delete_node(previous)
        previous = scene.find_model(ROOT)
    end
    -- Squares from a build before they were grouped.
    for _, e in ipairs(scene.get_entities()) do
        if e.label and e.label:sub(1, 10) == "ChessGrid_" then scene.delete_node(e.node) end
    end
    root, cells, shown, pending = nil, nil, {}, {}
    lift_applied = nil
end

return grid
