-- menu.lua — title / end / pause overlays drawn as retained runtime_ui quads.
-- Immediate-mode over retained widgets: every draw_* sets its quads each frame and
-- anything not set this frame is explicitly hidden (retained quads persist otherwise).

local menu = {}

local SCREEN = "chess"

-- id -> "shown"|"hidden" for every quad this module has ever drawn; `used` marks the
-- ids set during the current draw_* call so the leftovers can be hidden.
local all = {}
local used = {}

local ELO_MIN, ELO_MAX = 400, 3190
local ELO_PER_PIXEL = 5

-- view.lua palette: dark panel fills, gold-ish borders.
local PANEL_FILL = {0.07, 0.08, 0.11, 0.96}
local PANEL_BORDER = {0.75, 0.70, 0.45, 1}
local BACKDROP_FILL = {0.02, 0.02, 0.03, 0.55}
local BTN_FILL = {0.16, 0.17, 0.20, 0.96}
local BTN_BORDER = {0.75, 0.70, 0.45, 1}
local BTN_TEXT = {0.97, 0.95, 0.85, 1}
local TITLE_TEXT = {1.0, 0.88, 0.55, 1}
-- RuntimeUi bakes at 16px; +2px to match the in-game overlay.
local FONT = 18 / 16
local ZERO = {0, 0, 0, 0}
local EMPTY_STATE = {}
local HIDE_Q = {visible = false, no_input = true}
local LIT = {0, 0, 0, 1}
local LABEL_Q = {
    x = 0, y = 0, w = 0, h = 0, body = "",
    style = "text", fill = ZERO, accent = ZERO, border = ZERO,
    text_color = TITLE_TEXT, align_h = "center", align_v = "middle",
    font_scale = FONT, no_input = false, visible = true,
}
local BTN_Q = {
    x = 0, y = 0, w = 0, h = 0, body = "",
    style = "panel", fill = BTN_FILL, accent = ZERO, border = BTN_BORDER,
    text_color = BTN_TEXT, align_h = "center", align_v = "middle",
    corner_radius = 6, font_scale = FONT, visible = true,
}
local PANEL_Q = {
    x = 0, y = 0, w = 0, h = 0,
    style = "panel", fill = PANEL_FILL, accent = ZERO, border = PANEL_BORDER,
    corner_radius = 10, visible = true,
}
local DRAG_Q = {
    x = 0, y = 0, w = 0, h = 0, body = "",
    style = "panel", fill = BTN_FILL, accent = ZERO, border = BTN_BORDER,
    text_color = BTN_TEXT, align_h = "center", align_v = "middle",
    corner_radius = 6, font_scale = FONT, draggable = true, visible = true,
}

function menu.init(screen_name)
    SCREEN = screen_name or SCREEN
end

local function q(id, props)
    all[id] = "shown"
    used[id] = true
    runtime_ui.set_quad(SCREEN, id, props)
end

local function begin_frame()
    for k in pairs(used) do used[k] = nil end
end

-- Hide every previously shown quad that this draw_* call did not set.
local function end_frame()
    for id, st in pairs(all) do
        if st == "shown" and not used[id] then
            runtime_ui.set_quad(SCREEN, id, HIDE_Q)
            all[id] = "hidden"
        end
    end
end

local function state(id)
    return runtime_ui.get_state(SCREEN, id) or EMPTY_STATE
end

-- Full-window backdrop. NOT no_input: it swallows clicks so the board under the
-- overlay never sees them.
local function backdrop(w, h)
    BACK_Q.w, BACK_Q.h = w, h
    q("menu_backdrop", BACK_Q)
end

local function panel(id, x, y, w, h)
    PANEL_Q.x, PANEL_Q.y, PANEL_Q.w, PANEL_Q.h = x, y, w, h
    q(id, PANEL_Q)
end

-- `no_input` DEFAULTS FALSE here, unlike view.text. Every caption this module draws sits on
-- a panel, and a no_input quad batches onto ImGui's background draw list -- behind every
-- windowed quad, including the panel it is supposed to be printed on. A batched caption is
-- not dim, it is absent. Pass true only for a caption over the bare board.
local function label(id, x, y, w, h, body, scale, color, no_input)
    -- style "text": a panel at font_scale 1.8 in a 44px box does not clip, so
    -- "PhasmaChess" painted over the buttons and read as leftover ghost text.
    LABEL_Q.x, LABEL_Q.y, LABEL_Q.w, LABEL_Q.h, LABEL_Q.body = x, y, w, h, body
    LABEL_Q.text_color = color or {0.95, 0.95, 0.92, 1}
    LABEL_Q.font_scale = scale or FONT
    LABEL_Q.no_input = no_input == true
    q(id, LABEL_Q)
end

-- Button roles. Colour carries the meaning: leaving is faint red, starting is faint green,
-- and Exit is a deeper red than Back so the two reds are never mistaken for each other.
--
-- One base colour per role and multipliers for the rest, rather than a fill per state: the
-- engine only pointer-lights the "button" visual style and it does so by DARKENING
-- (kHoverTint 0.92 / kPressTint 0.80), which barely registers on an already-dark plate.
-- Hover lifts, press pushes down, and a SELECTED button sits brighter than any idle one.
local HOVER_LIFT, PRESS_SINK, SELECTED_LIFT = 1.45, 0.62, 2.10

local ROLE = {
    normal = {fill = {0.16, 0.17, 0.20, 0.96},
              border = {0.75, 0.70, 0.45, 1}, text = {0.97, 0.95, 0.85, 1}},
    back   = {fill = {0.26, 0.14, 0.14, 0.96},
              border = {0.62, 0.38, 0.36, 1}, text = {0.95, 0.87, 0.85, 1}},
    start  = {fill = {0.13, 0.25, 0.16, 0.96},
              border = {0.42, 0.70, 0.47, 1}, text = {0.88, 0.97, 0.89, 1}},
    exit   = {fill = {0.44, 0.10, 0.09, 0.97},
              border = {0.82, 0.33, 0.28, 1}, text = {1.00, 0.90, 0.88, 1}},
}

local function lit(c, k)
    LIT[1] = math.min(1.0, c[1] * k)
    LIT[2] = math.min(1.0, c[2] * k)
    LIT[3] = math.min(1.0, c[3] * k)
    LIT[4] = c[4]
    return LIT
end

local function button(id, x, y, w, h, body, role, selected)
    -- get_state reports the state computed during the last BuildFrame, so the colour is one
    -- frame behind the pointer. Invisible at 60fps, and it is the same state the click is
    -- read from, so a button can never light up without being the one that fired.
    local st = state(id)
    local pal = ROLE[role or "normal"] or ROLE.normal
    local fill = selected and lit(pal.fill, SELECTED_LIFT) or pal.fill
    if st.down then fill = lit(fill, PRESS_SINK)
    elseif st.hovered then fill = lit(fill, HOVER_LIFT) end
    BTN_Q.x, BTN_Q.y, BTN_Q.w, BTN_Q.h, BTN_Q.body = x, y, w, h, body
    BTN_Q.fill = fill
    BTN_Q.border = pal.border
    BTN_Q.text_color = pal.text
    q(id, BTN_Q)
    -- `clicked` is the RELEASE, not the press: the backend's InvisibleButton is
    -- PressedOnClickRelease, so sliding off a button before letting go cancels it.
    return (st and st.clicked) or false
end

-- ── title fields ───────────────────────────────────────────────────────────

-- clock presets cycled in order: {minutes, increment_s, label}
local CLOCKS = {
    {0, 0, "No clock"},
    {5, 0, "5+0"},
    {10, 0, "10+0"},
    {3, 2, "3+2"},
}

local function clock_index(cfg)
    for i, c in ipairs(CLOCKS) do
        if c[1] == (cfg.clock_min or 0) and c[2] == (cfg.clock_inc or 0) then return i end
    end
    return 1
end

local elo_drag_base = nil -- cfg.elo snapshotted on drag_started
local vol_drag_base = nil

local function elo_label(elo)
    if elo >= ELO_MAX then return "Bot Elo: Max (full strength)" end
    return "Bot Elo: " .. elo .. "  (drag)"
end

-- Drag-scrub field: drag_delta_x is the TOTAL pixels since the press, so the value is
-- base-at-press + delta, never accumulated. runtime_ui has no slider and no text entry.
local function drag_field(id, x, y, w, h, body)
    local st = state(id)
    local pal = ROLE.normal
    local fill = pal.fill
    if st.dragging or st.down then fill = lit(fill, PRESS_SINK)
    elseif st.hovered then fill = lit(fill, HOVER_LIFT) end
    DRAG_Q.x, DRAG_Q.y, DRAG_Q.w, DRAG_Q.h, DRAG_Q.body = x, y, w, h, body
    DRAG_Q.fill = fill
    q(id, DRAG_Q)
    return st
end

local function elo_field(id, x, y, w, h, cfg)
    local st = drag_field(id, x, y, w, h, elo_label(cfg.elo or 1500))
    if st.drag_started then elo_drag_base = cfg.elo or 1500 end
    if st.dragging and elo_drag_base then
        local e = elo_drag_base + math.floor((st.drag_delta_x or 0) * ELO_PER_PIXEL)
        if e < ELO_MIN then e = ELO_MIN end
        if e > ELO_MAX then e = ELO_MAX end
        cfg.elo = e
    end
    if not st.dragging then elo_drag_base = nil end
end

-- Same scrub for volume, 0.5% per pixel. Returns true on release so the caller can play a
-- sample at the new level.
local function volume_field(id, x, y, w, h, cfg)
    local pct = math.floor((cfg.volume or 0.15) * 100 + 0.5)
    local st = drag_field(id, x, y, w, h, "Sound Volume: " .. pct .. "%  (drag)")
    if st.drag_started then vol_drag_base = cfg.volume or 0.15 end
    if st.dragging and vol_drag_base then
        local v = vol_drag_base + (st.drag_delta_x or 0) * 0.005
        cfg.volume = math.max(0.0, math.min(1.0, v))
    end
    if not st.dragging then vol_drag_base = nil end
    return st.drag_released or false
end

-- ── the menu tree ──────────────────────────────────────────────────────────
-- One renderer, one row list per page. Pages are a tree and every non-root page carries
-- its parent, so "Back" cannot desync the way a push/pop stack can if a page is entered
-- twice. `page` is module state: the tree stays where you left it while the game runs
-- underneath, and menu.home() resets it when the title is opened fresh.
local PARENT = {
    play = "root", pvb = "play", pvp = "play", bvb = "play", lan = "pvp", code = "pvp",
    analysis = "root", pgn = "analysis", settings = "root",
}
local PGN_ROWS = 8 -- files per page; runtime_ui does not clip, so the list is paged
local LAN_ROWS = 6 -- lobbies shown; more than this on one network is not a real case
local page = "root"

function menu.home() page = "root" end
function menu.page() return page end

-- Jump straight to a page, so a session can drive the tree without a mouse (the rows are
-- runtime_ui buttons and only ImGui's own cursor can press them). `goto` is a keyword.
function menu.goto_page(name)
    if name == "root" or PARENT[name] then page = name end
    return page
end

local TITLE = {
    root = "PhasmaChess",
    play = "Play",
    pvb = "Player vs Bot",
    pvp = "Player vs Player",
    bvb = "Bot vs Bot",
    analysis = "Analysis",
    pgn = "Open PGN",
    lan = "Games on this network",
    code = "Join with a Code",
    settings = "Settings",
}

-- Row kinds: "btn" plain button, "elo"/"vol" the two drag-scrub fields, "note" a dead
-- caption. A row's `act` is what draw_main returns when it fires.
local function rows_for(cfg, ctx)
    local r = {}
    local function btn(id, label, act, role)
        r[#r + 1] = {kind = "btn", id = id, label = label, act = act, role = role}
    end
    local function note(id, label) r[#r + 1] = {kind = "note", id = id, label = label} end
    local function go(id, label, to) r[#r + 1] = {kind = "btn", id = id, label = label, page = to} end

    if page == "root" then
        go("m_play", "Play", "play")
        go("m_analysis", "Analysis", "analysis")
        go("m_settings", "Settings", "settings")
        btn("m_exit", "Exit", "exit", "exit")

    elseif page == "play" then
        go("m_pvb", "Player vs Bot", "pvb")
        go("m_pvp", "Player vs Player", "pvp")
        go("m_bvb", "Bot vs Bot", "bvb")

    elseif page == "pvb" then
        r[#r + 1] = {kind = "pair",
                     left  = {id = "m_side_w", label = "White", act = "side_w",
                              on = cfg.side ~= "B"},
                     right = {id = "m_side_b", label = "Black", act = "side_b",
                              on = cfg.side == "B"}}
        r[#r + 1] = {kind = "elo", id = "m_elo"}
        btn("m_clock", "Clock: " .. CLOCKS[clock_index(cfg)][3], "clock")
        btn("m_start_pvb", "Start", "start_pvb", "start")

    elseif page == "pvp" then
        -- Two ways to meet. Over the internet the relay hands out a code; on this network a
        -- beacon does the finding and no code is needed.
        btn("m_create", "Create Game", "net_create")
        go("m_join_code", "Join with a Code", "code")
        go("m_join", "Games on this Network", "lan")
        if ctx and ctx.code then
            -- Spaced in threes: this gets read out loud over a phone.
            note("m_code_out", "Your code:   " .. ctx.code:sub(1, 3) .. " " .. ctx.code:sub(4))
            note("m_code_hint", "tell your friend - it works once")
        end
        if ctx and ctx.note then note("m_pvp_note", ctx.note) end

    elseif page == "code" then
        -- A keypad, because runtime_ui has no text entry: there is nowhere to type a code, so
        -- the code is tapped in. Underscores show how many digits are still missing.
        local typed = (ctx and ctx.typed) or ""
        note("m_code_in", typed .. string.rep("_", 6 - #typed))
        local function keys(a, b, c, act_c, role_c)
            r[#r + 1] = {kind = "trio", cells = {
                {id = "m_k" .. a, label = a, act = "digit:" .. a},
                {id = "m_k" .. b, label = b, act = "digit:" .. b},
                {id = "m_k" .. c, label = c, act = act_c or ("digit:" .. c), role = role_c}}}
        end
        keys("1", "2", "3")
        keys("4", "5", "6")
        keys("7", "8", "9")
        r[#r + 1] = {kind = "trio", cells = {
            {id = "m_kdel", label = "<", act = "digit_del"},
            {id = "m_k0", label = "0", act = "digit:0"},
            {id = "m_kjoin", label = "Join", act = "net_join",
             role = (#typed == 6) and "start" or nil}}}
        if ctx and ctx.note then note("m_code_note", ctx.note) end

    elseif page == "lan" then
        -- Lobbies found by UDP beacon. There is no text entry in runtime_ui, so this list IS
        -- the join flow: you cannot type an address anywhere.
        btn("m_lan_host", "Host on this Network", "lobby_create")
        local lobbies = (ctx and ctx.lobbies) or {}
        if #lobbies == 0 then
            note("m_lan_none", "Looking for games...")
            note("m_lan_hint", "the host must be on this network")
        else
            for i = 1, math.min(#lobbies, LAN_ROWS) do
                btn("m_lan_" .. i, lobbies[i].name, "lan:" .. i)
            end
        end
        if ctx and ctx.note then note("m_lan_note", ctx.note) end

    elseif page == "bvb" then
        r[#r + 1] = {kind = "elo", id = "m_elo"}
        btn("m_clock", "Clock: " .. CLOCKS[clock_index(cfg)][3], "clock")
        btn("m_start_bvb", "Start", "start_bvb", "start")

    elseif page == "analysis" then
        btn("m_newboard", "New Board", "new_board")
        btn("m_loadpgn", "Load PGN", "browse_pgn")

    elseif page == "pgn" then
        local files = (ctx and ctx.pgn_files) or {}
        local first = math.max(1, (ctx and ctx.pgn_first) or 1)
        if #files == 0 then
            note("m_pgn_none", "No .pgn files found")
            note("m_pgn_hint", "put them in Assets/Save")
        else
            -- Ids are per SLOT, not per file, so a long list still only ever touches the
            -- handful of widgets on screen (same reason the move list numbers its rows).
            for slot = 0, PGN_ROWS - 1 do
                local f = files[first + slot]
                if f then btn("m_pgn_" .. slot, f.label, "pgn:" .. (first + slot)) end
            end
            if #files > PGN_ROWS then
                local last = math.min(#files, first + PGN_ROWS - 1)
                r[#r + 1] = {kind = "pair",
                             left  = {id = "m_pgn_prev", label = "< Prev", act = "pgn_prev"},
                             right = {id = "m_pgn_next", label = "Next >", act = "pgn_next"}}
                note("m_pgn_count", first .. "-" .. last .. " of " .. #files)
            end
        end
        if ctx and ctx.pgn_error then note("m_pgn_err", ctx.pgn_error) end

    elseif page == "settings" then
        r[#r + 1] = {kind = "vol", id = "m_vol"}
        btn("m_board", "Board Type: " .. ((cfg.view2d ~= false) and "2D" or "3D"), "board")
    end

    if PARENT[page] then btn("m_back", "Back", "back", "back") end
    return r
end

-- ctx: {can_load = bool, note = string|nil}
function menu.draw_main(w, h, cfg, ctx)
    begin_frame()
    local action = nil
    local r = rows_for(cfg, ctx)

    local bh, gap = 40, 12
    local pw = 380
    local ph = 76 + #r * (bh + gap) - gap + 12
    local px, py = (w - pw) / 2, (h - ph) / 2
    local bx, bw = px + 40, pw - 80

    backdrop(w, h)
    panel("menu_panel", px, py, pw, ph)
    -- no_input: a batched label draws BEHIND the panel window, so the heading has to be an
    -- input-class quad to sit on top of its own plate (see RuntimeUi quad layering).
    label("menu_heading", px, py + 12, pw, 44, TITLE[page] or "", FONT + 0.15, TITLE_TEXT, false)

    local y = py + 68
    for _, row in ipairs(r) do
        if row.kind == "pair" then
            local half = (bw - 10) * 0.5
            if button(row.left.id, bx, y, half, bh, row.left.label, row.role, row.left.on) then
                action = row.left.act
            end
            if button(row.right.id, bx + half + 10, y, half, bh, row.right.label,
                      row.role, row.right.on) then
                action = row.right.act
            end
        elseif row.kind == "trio" then
            local third = (bw - 20) / 3
            for i, cell in ipairs(row.cells) do
                if button(cell.id, bx + (i - 1) * (third + 10), y, third, bh, cell.label, cell.role) then
                    action = cell.act
                end
            end
        elseif row.kind == "elo" then
            elo_field(row.id, bx, y, bw, bh, cfg)
        elseif row.kind == "vol" then
            if volume_field(row.id, bx, y, bw, bh, cfg) then action = "volume" end
        elseif row.kind == "note" then
            label(row.id, bx, y, bw, bh, row.label, FONT, {0.60, 0.60, 0.64, 1}, false)
        elseif button(row.id, bx, y, bw, bh, row.label, row.role) then
            if row.page then page = row.page
            elseif row.act == "back" then page = PARENT[page] or "root"
            else action = row.act end
        end
        y = y + bh + gap
    end

    end_frame()
    return action, cfg
end

-- ── end card ───────────────────────────────────────────────────────────────

-- `rematch` is the online negotiation state: nil offline, "sent" while we wait for the
-- opponent to answer, "offered" when they asked first and the button is now an acceptance.
function menu.draw_end(w, h, result_text, pgn_saved, rematch)
    begin_frame()
    local action = nil
    local pw, ph = 380, 340
    local px, py = (w - pw) / 2, (h - ph) / 2
    local bx, bw, bh, gap = px + 40, pw - 80, 40, 12

    backdrop(w, h)
    panel("menu_end_panel", px, py, pw, ph)
    label("menu_end_result", px, py + 14, pw, 44, result_text or "", FONT + 0.15, TITLE_TEXT, false)

    local y = py + 72
    local rematch_label = "Rematch"
    if rematch == "sent" then rematch_label = "Waiting for opponent..."
    elseif rematch == "offered" then rematch_label = "Accept rematch" end
    if button("menu_end_rematch", bx, y, bw, bh, rematch_label, "start") and rematch ~= "sent" then
        action = "rematch"
    end
    y = y + bh + gap
    if button("menu_end_replay", bx, y, bw, bh, "Replay") then action = "replay" end
    y = y + bh + gap
    if button("menu_end_review", bx, y, bw, bh, "Review") then action = "review" end
    y = y + bh + gap
    if button("menu_end_menu", bx, y, bw, bh, "Main menu") then action = "menu" end
    y = y + bh + gap
    if button("menu_end_pgn", bx, y, bw, bh, pgn_saved and "PGN saved" or "Save PGN")
        and not pgn_saved then
        action = "pgn"
    end

    end_frame()
    return action
end

-- ── pause card ─────────────────────────────────────────────────────────────

-- `can` says which of the mid-game actions still mean anything. Once the game is over you
-- cannot resign it, offer a draw in it, or take a move back — so those rows are not drawn
-- at all rather than drawn dead, and the panel shrinks to fit what is left.
function menu.draw_pause(w, h, can)
    begin_frame()
    can = can or {}
    local action = nil

    local rows = {}
    if can.offer then
        -- An offer from the opponent takes over the card: answering it is the only thing that
        -- matters, and burying Accept under Resume/Resign is how offers get missed. There is no
        -- Resume either -- the clock keeps running behind this card, so walking away from the
        -- offer unanswered would be a pause that only looks like one to us.
        local what = (can.offer == "draw") and "draw" or "takeback"
        rows[#rows + 1] = {"" .. can.offer, "Accept " .. what, "start"}
        rows[#rows + 1] = {"decline", "Decline " .. what, "back"}
        rows[#rows + 1] = {"exit", "Exit game", "exit"}
    elseif can.analysis then
        -- Nobody to resign to and nothing to agree with on an analysis board: it is a
        -- position you are working on, so the only verbs are start over and leave.
        rows[#rows + 1] = {"resume", "Resume"}
        rows[#rows + 1] = {"reset", "Reset"}
        rows[#rows + 1] = {"menu", "Back", "back"}
    else
        rows[#rows + 1] = {"resume", "Resume"}
        if can.takeback then
            rows[#rows + 1] = {"takeback",
                               (can.sent == "takeback") and "Takeback offered..." or "Offer takeback"}
        end
        if can.draw then
            rows[#rows + 1] = {"draw", (can.sent == "draw") and "Draw offered..." or "Offer draw"}
        end
        if can.resign then rows[#rows + 1] = {"resign", "Resign"} end
        -- Abandoning a game in progress is what Resign is for, so the way back to the title
        -- only appears once the game is actually over.
        if can.over then rows[#rows + 1] = {"menu", "Main menu"} end
        rows[#rows + 1] = {"exit", "Exit game", "exit"}
    end

    local bh, gap = 40, 12
    local pw = 300
    local ph = 44 + #rows * (bh + gap) - gap
    local px, py = (w - pw) / 2, (h - ph) / 2
    local bx, bw = px + 34, pw - 68

    backdrop(w, h)
    panel("menu_pause_panel", px, py, pw, ph)

    local y = py + 22
    for _, row in ipairs(rows) do
        if button("menu_pause_" .. row[1], bx, y, bw, bh, row[2], row[3]) then action = row[1] end
        y = y + bh + gap
    end

    end_frame()
    return action
end

function menu.hide()
    for id, st in pairs(all) do
        if st == "shown" then
            runtime_ui.set_quad(SCREEN, id, HIDE_Q)
            all[id] = "hidden"
        end
    end
    used = {}
end

return menu
