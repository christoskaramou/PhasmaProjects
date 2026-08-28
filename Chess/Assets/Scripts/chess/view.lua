-- view.lua — cursor picking and the screen overlay.
--
-- Everything here was pinned down against the live engine rather than assumed:
--   * The projection is REVERSE-Z: NDC z=1 is the near plane and z=0 unprojects to
--     infinity. So the ray is built from the camera position outward through a point
--     unprojected at z=0.5, never from a "near minus far" subtraction.
--   * Screen y is NOT flipped: pixel_y = (ndc_y + 1) / 2 * height.
--   * `scene.pick_view_pixel` is not used — it returned a node on only 12 of 33 pieces
--     when fed their own screen-box centres. Cursor picking is done analytically here.
--   * Pieces are tall (a king is 15 cm on a 6.25 cm square), so a ray/board-plane
--     intersection alone would select a square up to 3 ranks behind the piece you
--     clicked. Each piece gets a vertical cylinder from its real mesh AABB.

local view = {}

local BOARD = nil -- board module, injected by view.init
local SCREEN = "chess"
-- RuntimeUi bakes at 16px; +2px on the overlay. Face is Fonts/RuntimeUi.ttf (Inter).
local FONT = 18 / 16

-- set_quad copies into C++ immediately, so these scratch tables are safe to reuse.
local ZERO = {0, 0, 0, 0}
local NO_OPTS = {}
local EMPTY_STATE = {}
local FILL_PANEL = {0.05, 0.05, 0.07, 0.72}
local FILL_BTN = {0.16, 0.17, 0.20, 0.96}
local FILL_DRAG = {0.10, 0.13, 0.18, 0.96}
local FILL_PANEL_HOVER = {0.04, 0.05, 0.07, 0.78}
local FILL_VBAR_BG = {0.10, 0.10, 0.12, 0.90}
local FILL_VBAR = {0.92, 0.92, 0.88, 0.95}
local BORDER_BTN = {0.75, 0.70, 0.45, 1}
local BORDER_DRAG = {0.45, 0.55, 0.70, 1}
local BORDER_PANEL = {0.30, 0.30, 0.34, 0.9}
local BORDER_VBAR = {0.35, 0.35, 0.38, 0.9}
local TEXT_BODY = {0.95, 0.95, 0.92, 1}
local TEXT_BTN = {0.97, 0.95, 0.85, 1}
local TEXT_DRAG = {0.92, 0.95, 1.0, 1}
local COORD_OPTS = {style = "text", fill = ZERO, font_scale = FONT,
                    text_color = {0.95, 0.92, 0.82, 1}}
local VBAR_LBL = {fill = ZERO, font_scale = FONT - 0.2}
local HIDE_Q = {visible = false, no_input = true}
local TEXT_Q = {
    x = 0, y = 0, w = 0, h = 0, body = "",
    style = "panel", fill = FILL_PANEL, accent = ZERO, border = ZERO,
    text_color = TEXT_BODY, align_h = "center", align_v = "middle",
    font_scale = FONT, no_input = true, visible = true,
    corner_radius = 0, bring_to_front = false,
}
local BTN_Q = {
    x = 0, y = 0, w = 0, h = 0, body = "",
    style = "panel", fill = FILL_BTN, accent = ZERO, border = BORDER_BTN,
    text_color = TEXT_BTN, align_h = "center", align_v = "middle",
    corner_radius = 6, font_scale = FONT, no_input = false, visible = true,
}
local DRAG_Q = {
    x = 0, y = 0, w = 0, h = 0, body = "",
    style = "panel", fill = FILL_DRAG, accent = ZERO, border = BORDER_DRAG,
    text_color = TEXT_DRAG, align_h = "center", align_v = "middle",
    corner_radius = 5, font_scale = FONT, draggable = true, visible = true,
}
local VBAR_BG_Q = {
    x = 0, y = 0, w = 0, h = 0, style = "panel", fill = FILL_VBAR_BG, accent = ZERO,
    border = BORDER_VBAR, corner_radius = 3, no_input = true, visible = true,
}
local VBAR_FILL_Q = {
    x = 0, y = 0, w = 0, h = 0, style = "panel", fill = FILL_VBAR, accent = ZERO,
    border = ZERO, corner_radius = 2, no_input = true, visible = true,
}
local PANEL_Q = {
    x = 0, y = 0, w = 0, h = 0, style = "panel", fill = FILL_PANEL_HOVER,
    accent = ZERO, border = BORDER_PANEL, corner_radius = 8, visible = true,
}
local LIT = {0, 0, 0, 1}

-- The game only ever runs in play mode (its update is registered "play"), and in play mode
-- the 3D view fills the window in BOTH hosts — fullscreen in the editor, the whole window in
-- the player. So the window rect is the one pixel space for both the cursor and the overlay,
-- and no editor/player split is needed.
--
-- Do NOT use engine.get_viewport_mouse_position() here: in editor play mode it still reports
-- the *docked* scene-view image (measured 1808x967 against a 2560x1369 window), which put
-- every marker up and to the left of its square.
-- ponytail: if the game is ever run inside a docked editor viewport, this needs the image
-- rect and its absolute origin instead of the window rect.

function view.init(board)
    BOARD = board
    if runtime_ui and runtime_ui.set_screen_overlay then
        -- Overlay makes it a full-screen layer instead of a titled ImGui window; show()
        -- is separate and a new screen starts hidden, so both are required.
        runtime_ui.set_screen_overlay(SCREEN, true)
        runtime_ui.set_visible(SCREEN, true)
        runtime_ui.show(SCREEN)
    end
end

function view.screen() return SCREEN end

-- The window rect: one pixel space for the cursor, the projection and the overlay.
function view.viewport()
    local r = engine.get_viewport_rect()
    if r and r.valid and r.w > 0 then return r.w, r.h end
    local s = runtime_ui.get_surface_size()
    if s and s.w and s.w > 0 then return s.w, s.h end
end

-- Cursor in window pixels, or nil when it is off-window or swallowed by a UI widget
-- (input.get_mouse_position reports 0,0 while ImGui holds the mouse).
function view.cursor()
    local w, h = view.viewport()
    if not w then return nil end
    local m = input.get_mouse_position()
    if m.x <= 0 or m.y <= 0 or m.x >= w or m.y >= h then return nil end
    return m.x, m.y, w, h
end

-- Ray from the eye through a viewport pixel. Direction is normalised, so hit
-- parameters are true world distances from the camera.
function view.ray(vx, vy, vw, vh)
    local cam = scene.get_active_camera()
    if not cam then return nil end
    local ivp = cam:get_inv_view_projection()
    local eye = cam:get_position()
    local nx = (vx / vw) * 2.0 - 1.0
    local ny = (vy / vh) * 2.0 - 1.0
    local p = ivp * vec4(nx, ny, 0.5, 1.0)
    local w = (p.w ~= 0.0) and p.w or 1.0
    local dx, dy, dz = p.x / w - eye.x, p.y / w - eye.y, p.z / w - eye.z
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 1e-9 then return nil end
    return eye, vec3(dx / len, dy / len, dz / len)
end

-- World point to overlay pixels. Reverse-Z: NDC z=1 is near. Nil if behind the camera.
function view.project(x, y, z, vw, vh)
    local cam = scene.get_active_camera()
    if not cam or not vw then return nil end
    local p = cam:get_view_projection() * vec4(x, y, z, 1.0)
    if p.w <= 1e-6 then return nil end
    local nx, ny = p.x / p.w, p.y / p.w
    return (nx + 1) * 0.5 * vw, (ny + 1) * 0.5 * vh
end

-- a-h along White's rim, 1-8 outside the a-file. World-space, so they orbit with the board.
function view.coords(vw, vh)
    if not BOARD or not vw then return end
    local y = (BOARD.top_y or 0.016) + 0.001
    local pitch = BOARD.PITCH
    local _, z1 = BOARD.square_to_world(0, 1)
    local xa = BOARD.square_to_world(0, 1)
    for file = 0, 7 do
        local x = BOARD.square_to_world(file, 1)
        local sx, sy = view.project(x, y, z1 - pitch * 0.62, vw, vh)
        if sx then
            view.text("coord_f" .. file, sx - 12, sy - 12, 24, 24, string.char(97 + file),
                      COORD_OPTS)
        else
            view.hide("coord_f" .. file)
        end
    end
    for rank = 1, 8 do
        local _, z = BOARD.square_to_world(0, rank)
        local sx, sy = view.project(xa + pitch * 0.62, y, z, vw, vh)
        if sx then
            view.text("coord_r" .. rank, sx - 12, sy - 12, 24, 24, tostring(rank),
                      COORD_OPTS)
        else
            view.hide("coord_r" .. rank)
        end
    end
end

-- The 2D board draws its own labels, so the projected ones have to be taken down
-- explicitly: above they are only hidden when the projection fails, which never happens
-- just because a different board is on screen.
function view.coords_hide()
    for file = 0, 7 do view.hide("coord_f" .. file) end
    for rank = 1, 8 do view.hide("coord_r" .. rank) end
end

-- Ray against a vertical cylinder (a slab intersected with an infinite cylinder).
-- ponytail: cylinder proxy, not mesh-accurate — a knight's head overhangs its base
-- slightly. Swap in per-mesh picking only if players complain about edge clicks.
local function cylinder_t(ox, oy, oz, dx, dy, dz, cx, cz, r, y0, y1)
    local px, pz = ox - cx, oz - cz
    local a = dx * dx + dz * dz
    if a < 1e-12 then return nil end
    local b = 2.0 * (px * dx + pz * dz)
    local c = px * px + pz * pz - r * r
    local disc = b * b - 4.0 * a * c
    if disc < 0.0 then return nil end
    local sq = math.sqrt(disc)
    local t0, t1 = (-b - sq) / (2.0 * a), (-b + sq) / (2.0 * a)

    local ta, tb
    if math.abs(dy) < 1e-9 then
        if oy < y0 or oy > y1 then return nil end
        ta, tb = -math.huge, math.huge
    else
        ta, tb = (y0 - oy) / dy, (y1 - oy) / dy
        if ta > tb then ta, tb = tb, ta end
    end

    local tmin = math.max(t0, ta)
    local tmax = math.min(t1, tb)
    if tmax < tmin or tmax < 0.0 then return nil end
    return (tmin >= 0.0) and tmin or 0.0
end

-- What the cursor is over: file, rank, piece-or-nil. Pieces win over the bare square
-- they occlude, and the nearest piece to the eye wins over one behind it.
function view.pick(pieces)
    local vx, vy, vw, vh = view.cursor()
    if not vx then return nil end
    local o, d = view.ray(vx, vy, vw, vh)
    if not o then return nil end

    local best, best_t
    for _, p in ipairs(pieces) do
        if p.file then
            local cx, cz = BOARD.square_to_world(p.file, p.rank)
            local t = cylinder_t(o.x, o.y, o.z, d.x, d.y, d.z,
                                 cx, cz, p.radius, p.base_y, p.base_y + p.height)
            if t and (not best_t or t < best_t) then best, best_t = p, t end
        end
    end
    if best then return best.file, best.rank, best end

    if math.abs(d.y) < 1e-9 then return nil end
    local t = (BOARD.top_y - o.y) / d.y
    if t <= 0.0 then return nil end
    local file, rank = BOARD.world_to_square(o.x + d.x * t, o.z + d.z * t)
    if not file then return nil end
    return file, rank, nil
end

-- The square under the cursor, ignoring pieces entirely — the board plane and nothing else.
-- This is what a DRAG needs: the piece in your hand is under the cursor and would win every
-- pick, and you drop ONTO an occupied square to capture, so pieces must not shadow squares.
function view.pick_square()
    local vx, vy, vw, vh = view.cursor()
    if not vx then return nil end
    local o, d = view.ray(vx, vy, vw, vh)
    if not o or math.abs(d.y) < 1e-9 then return nil end
    local t = (BOARD.top_y - o.y) / d.y
    if t <= 0.0 then return nil end
    return BOARD.world_to_square(o.x + d.x * t, o.z + d.z * t)
end

-- Where the cursor meets the board plane, in world space. The 3D drag rides this point, so
-- a dragged piece tracks the cursor across the board at any camera angle.
function view.board_point()
    local vx, vy, vw, vh = view.cursor()
    if not vx then return nil end
    local o, d = view.ray(vx, vy, vw, vh)
    if not o or math.abs(d.y) < 1e-9 then return nil end
    local t = (BOARD.top_y - o.y) / d.y
    if t <= 0.0 then return nil end
    return o.x + d.x * t, o.z + d.z * t
end

-- Square highlighting lives in grid.lua now: real planes on the board, which line up at
-- any camera angle where a screen-space rect only worked from straight above.

function view.hide(id)
    runtime_ui.set_quad(SCREEN, id, HIDE_Q)
end

function view.text(id, x, y, w, h, body, opts)
    opts = opts or NO_OPTS
    TEXT_Q.x, TEXT_Q.y, TEXT_Q.w, TEXT_Q.h, TEXT_Q.body = x, y, w, h, body
    TEXT_Q.style = opts.style or "panel"
    TEXT_Q.fill = opts.fill or FILL_PANEL
    TEXT_Q.border = opts.border or ZERO
    TEXT_Q.text_color = opts.text_color or TEXT_BODY
    TEXT_Q.align_h = opts.align_h or "center"
    TEXT_Q.font_scale = opts.font_scale or FONT
    TEXT_Q.no_input = opts.no_input ~= false
    TEXT_Q.corner_radius = opts.corner_radius or 0
    TEXT_Q.bring_to_front = opts.bring_to_front or false
    runtime_ui.set_quad(SCREEN, id, TEXT_Q)
end

-- Pointer feedback for every in-game button, derived from whatever fill the caller passed
-- so each button keeps its own colour. The engine only pointer-lights the "button" visual
-- style, and it does so by DARKENING, which is nearly invisible on this dark palette —
-- hover lifts instead, press pushes down.
local HOVER_LIFT, PRESS_SINK = 1.45, 0.62

local function lit(c, k)
    LIT[1] = math.min(1.0, c[1] * k)
    LIT[2] = math.min(1.0, c[2] * k)
    LIT[3] = math.min(1.0, c[3] * k)
    LIT[4] = c[4] or 1.0
    return LIT
end

function view.button(id, x, y, w, h, label, opts)
    opts = opts or NO_OPTS
    -- Last frame's state: it colours this frame and carries this frame's click, so a button
    -- can never light up without also being the one that fired.
    local st = runtime_ui.get_state(SCREEN, id) or EMPTY_STATE
    local fill = opts.fill or FILL_BTN
    if not opts.no_input then
        if st.down then fill = lit(fill, PRESS_SINK)
        elseif st.hovered then fill = lit(fill, HOVER_LIFT) end
    end
    BTN_Q.x, BTN_Q.y, BTN_Q.w, BTN_Q.h, BTN_Q.body = x, y, w, h, label
    BTN_Q.style = opts.style or "panel"
    BTN_Q.fill = fill
    BTN_Q.border = opts.border or BORDER_BTN
    BTN_Q.text_color = opts.text_color or TEXT_BTN
    BTN_Q.align_h = opts.align_h or "center"
    BTN_Q.corner_radius = opts.corner_radius or 6
    BTN_Q.font_scale = opts.font_scale or FONT
    BTN_Q.no_input = opts.no_input or false
    runtime_ui.set_quad(SCREEN, id, BTN_Q)
    -- `clicked` is the RELEASE, not the press (the backend's InvisibleButton is
    -- PressedOnClickRelease), so sliding off before letting go cancels the action.
    return st.clicked or false, st.hovered or false
end

-- A number field you scrub by dragging, which is the only numeric INPUT runtime_ui can offer:
-- its Number widget is display-only (no getter is bound) and there is no text entry. Returns the
-- widget state; `drag_delta_x` is the TOTAL pixels since the press, not a per-frame delta, so the
-- caller snapshots the value on drag_started and adds the delta from there.
function view.drag(id, x, y, w, h, label)
    DRAG_Q.x, DRAG_Q.y, DRAG_Q.w, DRAG_Q.h, DRAG_Q.body = x, y, w, h, label
    runtime_ui.set_quad(SCREEN, id, DRAG_Q)
    return runtime_ui.get_state(SCREEN, id) or EMPTY_STATE
end

-- A vertical two-tone bar: `frac` of the height is filled white from the bottom, the rest
-- stays dark. Used for the engine eval bar; `label` is drawn under it.
function view.vbar(id, x, y, w, h, frac, label)
    frac = math.max(0.0, math.min(1.0, frac or 0.5))
    VBAR_BG_Q.x, VBAR_BG_Q.y, VBAR_BG_Q.w, VBAR_BG_Q.h = x, y, w, h
    runtime_ui.set_quad(SCREEN, id .. "_bg", VBAR_BG_Q)
    local fh = math.floor(h * frac + 0.5)
    VBAR_FILL_Q.x, VBAR_FILL_Q.y = x + 1, y + (h - fh) + 1
    VBAR_FILL_Q.w, VBAR_FILL_Q.h = w - 2, math.max(0, fh - 2)
    VBAR_FILL_Q.visible = fh > 2
    runtime_ui.set_quad(SCREEN, id .. "_fill", VBAR_FILL_Q)
    view.text(id .. "_lbl", x - 14, y + h + 4, w + 28, 18, label or "", VBAR_LBL)
end

function view.vbar_hide(id)
    view.hide(id .. "_bg")
    view.hide(id .. "_fill")
    view.hide(id .. "_lbl")
end

-- A plain backdrop that still reports hover, so the caller can tell "the cursor is over
-- the panel" from "the cursor is over the board" and route the wheel accordingly.
function view.panel(id, x, y, w, h, fill)
    PANEL_Q.x, PANEL_Q.y, PANEL_Q.w, PANEL_Q.h = x, y, w, h
    PANEL_Q.fill = fill or FILL_PANEL_HOVER
    runtime_ui.set_quad(SCREEN, id, PANEL_Q)
    local st = runtime_ui.get_state(SCREEN, id)
    return (st and st.hovered) or false
end

-- ── selection outline ──────────────────────────────────────────────────────
-- The engine's SelectionOutlinePass (Phasma/Runtime/Code/RenderPasses) draws a real silhouette
-- around selected meshes, in BOTH hosts: the editor's `selection` table drives its
-- SelectionManager, and PhasmaPlayer registers a minimal runtime `selection`
-- (select_node/clear) that feeds the same pass through SceneRuntimeHooks.
local has_outline = selection ~= nil and selection.select_node ~= nil

function view.outline_available() return has_outline end

-- `selection` exists in both hosts now, so host detection keys on an editor-only function:
-- get_gizmo has no meaning outside the editor. Quitting means different things in each.
function view.is_editor() return selection ~= nil and selection.get_gizmo ~= nil end

-- The selection gold, and the same gold pushed brighter for hover. The pass reads the colour
-- settings every frame, so retinting the single outline slot per target is free.
local TINT_SELECT = {1.0, 0.80, 0.36, 0.65}
local TINT_HOVER = {1.0, 0.90, 0.50, 0.80}
local tint_applied = nil
local outline_index = nil -- node index currently outlined, nil when clear

local function apply_tint(t)
    if tint_applied == t then return end
    tint_applied = t
    settings.set("selection_outline_color_r", t[1])
    settings.set("selection_outline_color_g", t[2])
    settings.set("selection_outline_color_b", t[3])
    settings.set("selection_outline_color_a", t[4])
end

function view.outline_init()
    if not has_outline then return false end
    settings.set("selection_outline", true)
    -- Width on screen is thickness + inner_fade + outer_fade, all in mask pixels. The engine
    -- defaults (3 / 2 / 6) are an editor gizmo — eleven pixels of line, far too loud on a chess
    -- piece. These give a hairline. Every one of the three has to be set: leaving the fades at
    -- their defaults keeps the outline fat no matter how small `thickness` gets.
    settings.set("selection_outline_thickness", 0.6)
    settings.set("selection_outline_inner_fade", 0.6)
    settings.set("selection_outline_outer_fade", 0.8)
    apply_tint(TINT_SELECT)
    outline_index = nil
    selection.clear()
    return true
end

-- Outline one piece's node (hovered = the brighter gold), or clear when passed nil. Called
-- every frame by the hover pass, so both the tint and the outlined node are diffed.
function view.outline(node, hovered)
    if not has_outline then return false end
    if node and node:is_valid() then
        apply_tint(hovered and TINT_HOVER or TINT_SELECT)
        local idx = node:get_index()
        if outline_index ~= idx then
            outline_index = idx
            selection.select_node(idx)
        end
    elseif outline_index then
        outline_index = nil
        selection.clear()
    end
    return true
end

function view.clear()
    if runtime_ui and runtime_ui.clear then runtime_ui.clear(SCREEN) end
    if has_outline then
        outline_index = nil
        selection.clear()
    end
end

return view
