-- ath_shell — the game's front-end and mode driver.
--
-- This is the menu the player sees first and the runtime that owns the single
-- engine update loop. Flow:
--
--   HOME  ──Play──▶  SIDE  ──pick Hero/Horde──▶  DECK (keep 20 of 50)
--     ▲                                              │
--     └────────────── MODE (pick a level) ◀──────────┘
--                         │ launch
--                         ▼
--                      PLAYING  ── M / Esc ──▶ back to MODE
--
-- A "mode" is discovered from Scripts/shared/ath_modes_index.lua and is a tiny
-- contract: `return { meta = {...}, config = {...} }`. The shell builds the shared
-- Duel from config and drives it; the player's chosen { side, deck } is passed in
-- as the duel's ctx. Modes never touch lifecycle — they are pure content.
--
-- The menu is rendered with runtime_ui quads and is fully mouse-driven (click
-- tiles/buttons) with keyboard fallbacks. Avatars and mode mini-maps are composed
-- from quads and accept an optional `image = "Path/to.png"` so dropping in art
-- later is a data edit, never a code edit.

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Cards = ATH_COMMON.load_script("Scripts/shared/ath_cards.lua", "shared cards", _ENV)
local Duel = ATH_COMMON.load_script("Scripts/shared/ath_duel.lua", "shared duel", _ENV)

local SCREEN = "ath.shell"
local UPDATE_ID = "against_the_hero_shell"
local HUD = "ath.shell.hud" -- always-on overlay: FPS clock + in-play "return to menu" button

local Shell = {
    state = "home",
    side = nil,
    deck = {},            -- set of selected card ids -> true
    deck_count = 0,
    modes = {},           -- { { id, meta, config } }
    active = nil,         -- active Duel instance while playing
    key_down = {},
    detail_card = nil,    -- last hovered/clicked card in deck builder
    mode_scroll = 0.0,    -- vertical scroll offset (px) on the battlefield grid
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function log(msg)
    if pe_log then pe_log("[ATH:SHELL] " .. tostring(msg)) end
end

local function key_pressed(name)
    if not input or not input.is_key_down then return false end
    local down = input.is_key_down(name)
    local pressed = down and not Shell.key_down[name]
    Shell.key_down[name] = down
    return pressed
end

local function delta_seconds()
    local m = engine and engine.get_metrics and engine.get_metrics() or nil
    local dt = m and m.delta_ms and m.delta_ms / 1000.0 or 1.0 / 60.0
    if not dt or dt <= 0.0 then dt = 1.0 / 60.0 end
    return math.min(dt, 0.10)
end

local function clear_screen()
    if runtime_ui and runtime_ui.clear then runtime_ui.clear(SCREEN) end
end

-- A clickable button quad. Returns true if clicked this frame. A button reads
-- best as ONE centred label, so the title and any key hint (footer) are folded
-- into a single label — this avoids title/footer colliding at the larger font.
local function button(id, x, y, w, h, label, opts)
    opts = opts or {}
    local st = Art.widget_state(SCREEN, id)
    local hovered = st and st.hovered
    local fill = opts.fill or (hovered and { 0.16, 0.18, 0.26, 0.96 } or { 0.10, 0.11, 0.16, 0.94 })
    local lbl = label or opts.title or ""
    if opts.footer and opts.footer ~= "" then lbl = lbl .. "   " .. opts.footer end
    Art.quad(SCREEN, id, x, y, w, h, fill, {
        border = opts.border or { 0.5, 0.55, 0.7, 0.95 },
        subtitle = opts.subtitle, body = opts.body,
        label = lbl, text_color = opts.text_color, image = opts.image, selected = opts.selected,
        font_scale = opts.font_scale,
    })
    return Art.consume_click(SCREEN, id)
end

-- An invisible interaction region. Composed visuals (avatars, mini-maps) sit on
-- top of their panel and would otherwise intercept the click, so we read/draw a
-- transparent quad ON TOP of the whole region and use ITS state. Returns
-- clicked, hovered from the quad as it existed last frame; draw the region's
-- visuals first, then call hit_quad() last so it lands on top.
local function hit_state(id)
    local st = Art.widget_state(SCREEN, id)
    return (st and st.clicked) == true, (st and st.hovered) == true
end

local function hit_quad(id, x, y, w, h)
    Art.quad(SCREEN, id, x, y, w, h, { 0.0, 0.0, 0.0, 0.0 })
end

-- Menu readability scale. Element DIMENSIONS multiply by this so the (auto-scaled)
-- text never overflows its panel. One knob in ath_art (Art.SCALE.ui) drives it.
local function U(v) return v * Art.s("ui") end

-- Headings use LABELS, never quad titles: the backend lays a quad's title BELOW
-- a reserved accent art band (minimum 42*scale tall), and each overlay quad is
-- its own exact-size ImGui window, so on compact quads the title falls past the
-- window bottom and is clipped away entirely. A label is top-anchored at
-- ~15*scale and always fits.
--
-- Labels are LEFT-anchored at pad=10*scale, but the font is monospaced
-- (~5.8 px/char per unit of effective font scale), so a label can be visually
-- centred by deriving the quad position from the text length.
local LABEL_CHAR_W = 5.8 -- px per character per unit of effective font scale
local LABEL_HALF_H = 5.4 -- half the label text height, same unit

local function centered_label(id, cx, cy, text, fs, color)
    fs = fs or 1.0
    local s = fs * Art.s("text")
    local tw = #text * LABEL_CHAR_W * s
    local pad = 10.0 * s
    local top = pad + 5.0 * s + LABEL_HALF_H * s -- label-text centre, from quad top
    Art.quad(SCREEN, id, cx - pad - tw * 0.5, cy - top, tw + pad * 2.0 + 4.0, top * 2.0,
        { 0.0, 0.0, 0.0, 0.0 }, { label = text, text_color = color, font_scale = fs, no_input = true })
end

-- ---------------------------------------------------------------------------
-- Mode discovery
-- ---------------------------------------------------------------------------

local function load_modes()
    Shell.modes = {}
    local index = ATH_COMMON.load_script("Scripts/shared/ath_modes_index.lua", "modes index", _ENV, { optional = true })
    local ids = (type(index) == "table" and index.modes) or {}
    for _, id in ipairs(ids) do
        local mod, err = ATH_COMMON.load_script("Scripts/modes/" .. id .. "/mode.lua", "mode " .. id, _ENV, { protected = true })
        if type(mod) == "table" and mod.meta and mod.config then
            mod.meta.id = mod.meta.id or id
            Shell.modes[#Shell.modes + 1] = { id = id, kind = "duel", meta = mod.meta, config = mod.config }
        else
            log("mode '" .. id .. "' failed to load: " .. tostring(err or "no { meta, config }"))
        end
    end
    log("loaded " .. tostring(#Shell.modes) .. " modes")
end

-- ---------------------------------------------------------------------------
-- Deck selection
-- ---------------------------------------------------------------------------

local function deck_list()
    local out = {}
    for _, id in ipairs(Cards.all_ids) do
        if Shell.deck[id] then out[#out + 1] = id end
    end
    return out
end

local function set_default_deck()
    Shell.deck = {}
    Shell.deck_count = 0
    for _, id in ipairs(Cards.default_deck) do
        Shell.deck[id] = true
        Shell.deck_count = Shell.deck_count + 1
    end
end

local function toggle_card(id)
    if Shell.deck[id] then
        Shell.deck[id] = nil
        Shell.deck_count = Shell.deck_count - 1
    elseif Shell.deck_count < Cards.DECK_SIZE then
        Shell.deck[id] = true
        Shell.deck_count = Shell.deck_count + 1
    end
    Shell.detail_card = id
end

-- ---------------------------------------------------------------------------
-- Launch / return
-- ---------------------------------------------------------------------------

local function launch_mode(entry)
    if not entry then return end
    clear_screen()
    if runtime_ui and runtime_ui.hide then runtime_ui.hide(SCREEN) end
    local ctx = { side = Shell.side or "hero", deck = deck_list() }
    Shell.active = Duel.new(entry.config, ctx, Shell.api)
    Shell.active:start()
    Shell.state = "playing"
    Shell.launched_id = entry.id
    log("launch mode=" .. entry.id .. " side=" .. ctx.side .. " deck=" .. tostring(#ctx.deck))
end

local function return_to_menu()
    if Shell.active then
        Shell.active:stop()
        Shell.active = nil
    end
    if runtime_ui and runtime_ui.show then runtime_ui.show(SCREEN) end
    Shell.state = "mode"
    log("returned to menu")
end

-- ---------------------------------------------------------------------------
-- Screens
-- ---------------------------------------------------------------------------

local function draw_home(sw, sh)
    Art.quad(SCREEN, "bg", 0, 0, sw, sh, { 0.05, 0.04, 0.08, 1.0 }, { no_input = true })
    centered_label("home_title", sw * 0.5, sh * 0.30, "AGAINST THE HERO", 2.2, { 0.96, 0.86, 0.5, 1.0 })
    centered_label("home_sub", sw * 0.5, sh * 0.30 + U(60.0), "a multi-mode card auto-battler", 1.0, { 0.74, 0.70, 0.58, 1.0 })

    -- PLAY: a bordered box centred on the surface; its label is a separate
    -- no_input quad so the text sits dead-centre (quad labels are top-left-anchored).
    local bw, bh = U(340.0), U(96.0)
    local bx, by = sw * 0.5 - bw * 0.5, sh * 0.5 - bh * 0.5
    local play_click, play_hover = hit_state("play_hit")
    Art.quad(SCREEN, "play", bx, by, bw, bh,
        play_hover and { 0.16, 0.19, 0.13, 0.97 } or { 0.12, 0.14, 0.10, 0.96 },
        { border = { 0.9, 0.74, 0.3, 0.95 }, no_input = true })
    centered_label("play_label", sw * 0.5, sh * 0.5, "PLAY   [Enter]", 1.3, { 0.96, 0.90, 0.70, 1.0 })
    -- Clicks land on a transparent hit-quad ON TOP: clicking an overlay quad
    -- raises its window, which would lift the opaque box over the label.
    hit_quad("play_hit", bx, by, bw, bh)
    if play_click or key_pressed("Return") or key_pressed("Space") then
        -- Side select is parked (post-pivot the game is hero-side only): jump
        -- straight to the deck. To restore it, set Shell.state = "side" here.
        Shell.side = "hero"
        set_default_deck()
        Shell.state = "deck"
    end
    -- "Pick a champion" is aspirational: champion types + the side/champion
    -- select screen come later — kept visible on purpose as a reminder.
    centered_label("home_hint", sw * 0.5, sh - U(60.0), "Pick a champion, build a deck, choose a battlefield.", 1.0, { 0.6, 0.62, 0.7, 1.0 })
end

-- A "funny avatar" composed from quads. spec carries colours + a `kind`
-- ("hero" | "horde") that decides which gag features get drawn. Pass an
-- `image = "Path/to.png"` to swap in real art later — a data edit, never code.
local function draw_avatar(prefix, cx, cy, scale, spec, image)
    if image then
        Art.quad(SCREEN, prefix .. "_img", cx - 82 * scale, cy - 82 * scale, 164 * scale, 164 * scale,
            { 0, 0, 0, 0 }, { image = image })
        return
    end
    local s = scale
    local function q(suffix, x, y, w, h, color, opts)
        Art.quad(SCREEN, prefix .. "_" .. suffix, cx + x * s, cy + y * s, w * s, h * s, color, opts)
    end
    q("face", -70, -70, 140, 140, spec.face, { border = spec.accent })

    if spec.kind == "horde" then
        -- A goofy gribbly: crooked horns, three mismatched googly eyes, a gaping
        -- toothy maw and a lolling tongue.
        q("horn_l", -58, -94, 22, 34, spec.accent)
        q("horn_r", 40, -98, 20, 38, spec.accent)
        q("eye_l", -52, -34, 40, 44, { 0.98, 0.98, 1.0, 1.0 })
        q("eye_r", 10, -42, 50, 52, { 0.98, 0.98, 1.0, 1.0 })
        q("eye_t", -14, -66, 26, 26, { 0.98, 0.98, 1.0, 1.0 })
        q("pup_l", -38, -16, 14, 16, { 0.05, 0.05, 0.08, 1.0 })
        q("pup_r", 28, -22, 16, 18, { 0.05, 0.05, 0.08, 1.0 })
        q("pup_t", -4, -52, 10, 10, { 0.05, 0.05, 0.08, 1.0 })
        q("mouth", -44, 26, 88, 32, { 0.12, 0.05, 0.06, 1.0 })
        q("tooth_l", -40, 26, 14, 16, { 0.96, 0.96, 0.9, 1.0 })
        q("tooth_m", -10, 26, 14, 12, { 0.96, 0.96, 0.9, 1.0 })
        q("tooth_r", 18, 26, 14, 18, { 0.96, 0.96, 0.9, 1.0 })
        q("tongue", -12, 48, 24, 14, { 0.86, 0.34, 0.46, 1.0 })
    else
        -- A smug champion: tiny crown, asymmetric eyebrows, a heroic moustache and
        -- a glinting tooth.
        q("crown", -34, -98, 68, 26, { 0.95, 0.82, 0.30, 1.0 }, { border = { 0.7, 0.55, 0.15, 1.0 } })
        q("crown_jewel", -7, -104, 14, 14, { 0.5, 0.85, 1.0, 1.0 })
        q("eye_l", -44, -24, 30, 30, { 0.98, 0.98, 1.0, 1.0 })
        q("eye_r", 14, -22, 30, 26, { 0.98, 0.98, 1.0, 1.0 })
        q("pup_l", -34, -16, 12, 14, { 0.06, 0.06, 0.1, 1.0 })
        q("pup_r", 24, -14, 12, 12, { 0.06, 0.06, 0.1, 1.0 })
        q("brow_l", -50, -44, 40, 10, spec.accent)
        q("brow_r", 14, -38, 38, 9, spec.accent)
        q("cheek_l", -54, 8, 18, 14, { 0.95, 0.55, 0.5, 0.7 })
        q("cheek_r", 36, 8, 18, 14, { 0.95, 0.55, 0.5, 0.7 })
        q("stache_l", -32, 20, 30, 10, { 0.42, 0.28, 0.18, 1.0 })
        q("stache_r", 2, 20, 30, 10, { 0.42, 0.28, 0.18, 1.0 })
        q("mouth", -26, 32, 52, 11, spec.mouth)
        q("glint", 28, 24, 9, 9, { 1.0, 1.0, 0.92, 1.0 })
    end
end

local HERO_AVATAR = { kind = "hero", face = { 0.95, 0.82, 0.62, 1.0 }, mouth = { 0.7, 0.3, 0.3, 1.0 }, accent = { 0.4, 0.6, 0.95, 1.0 } }
local HORDE_AVATAR = { kind = "horde", face = { 0.46, 0.66, 0.38, 1.0 }, mouth = { 0.2, 0.5, 0.2, 1.0 }, accent = { 0.85, 0.4, 0.3, 1.0 } }

local function draw_side(sw, sh)
    Art.quad(SCREEN, "bg", 0, 0, sw, sh, { 0.05, 0.04, 0.08, 1.0 }, { no_input = true })
    centered_label("side_hdr", sw * 0.5, U(76.0), "CHOOSE YOUR SIDE", 1.4, { 0.96, 0.86, 0.5, 1.0 })

    local pw = U(470.0)
    local ph = math.min(U(580.0), sh - U(180.0))
    local gap = U(90.0)
    local hx = sw * 0.5 - pw - gap * 0.5
    local ox = sw * 0.5 + gap * 0.5
    local py = sh * 0.5 - ph * 0.5 + U(24.0)
    local av_scale = math.min(Art.s("ui"), ph / 480.0)

    -- Read interaction from the transparent hit-quads (state from last frame); the
    -- avatars sit on top of the panels, so the hit-quad (drawn last) owns clicks.
    local hero_click, hero_hover = hit_state("side_hero_hit")
    local horde_click, horde_hover = hit_state("side_horde_hit")

    local function side_panel(prefix, x, hover, fill_base, fill_hover, border, title, name, blurb, hint, avatar, image)
        Art.quad(SCREEN, prefix, x, py, pw, ph, hover and fill_hover or fill_base,
            { border = border, title = title, subtitle = name })
        draw_avatar(prefix .. "_av", x + pw * 0.5, py + ph * 0.28, av_scale, avatar, image)
        Art.quad(SCREEN, prefix .. "_blurb", x + U(28.0), py + ph * 0.54, pw - U(56.0), ph * 0.28, { 0, 0, 0, 0 },
            { body = name .. "\n\n" .. blurb, text_color = { 0.82, 0.85, 0.92, 1.0 } })
        Art.quad(SCREEN, prefix .. "_hint", x + U(24.0), py + ph - U(46.0), pw - U(48.0), U(32.0), { 0, 0, 0, 0 },
            { label = hint, text_color = { 0.70, 0.72, 0.80, 1.0 } })
    end

    side_panel("side_hero", hx, hero_hover, { 0.08, 0.10, 0.18, 0.94 }, { 0.12, 0.16, 0.26, 0.96 }, { 0.4, 0.6, 0.95, 0.95 },
        "THE HERO", "Sir Reginald Buffington III",
        "Professionally heroic.\nTragically overconfident.\nUpgrades himself each pause.",
        "[H]  -  click to choose", HERO_AVATAR, Shell.hero_avatar_image)
    side_panel("side_horde", ox, horde_hover, { 0.16, 0.10, 0.10, 0.94 }, { 0.20, 0.14, 0.12, 0.96 }, { 0.9, 0.45, 0.32, 0.95 },
        "THE HORDE", "The Gribblies",
        "Many. Hungry.\nPoorly organised.\nCommands the swarm each pause.",
        "[L]  -  click to choose", HORDE_AVATAR, Shell.horde_avatar_image)

    -- Transparent hit-quads on top (created last → capture clicks over the avatars).
    hit_quad("side_hero_hit", hx, py, pw, ph)
    hit_quad("side_horde_hit", ox, py, pw, ph)

    if hero_click or key_pressed("H") then
        Shell.side = "hero"; set_default_deck(); Shell.state = "deck"
    elseif horde_click or key_pressed("L") then
        Shell.side = "horde"; set_default_deck(); Shell.state = "deck"
    end
    if button("back", U(40.0), sh - U(84.0), U(170.0), U(52.0), "< Back", { footer = "[Esc]" }) or key_pressed("Escape") then
        Shell.state = "home"
    end
end

local function draw_deck(sw, sh)
    Art.quad(SCREEN, "bg", 0, 0, sw, sh, { 0.05, 0.04, 0.08, 1.0 }, { no_input = true })
    local face_side = Shell.side or "hero"
    Art.quad(SCREEN, "deck_hdr_t", U(40.0), U(20.0), sw - U(80.0), U(50.0), { 0.0, 0.0, 0.0, 0.0 },
        { label = string.format("BUILD YOUR DECK — %d / %d", Shell.deck_count, Cards.DECK_SIZE),
          font_scale = 1.3, text_color = { 0.96, 0.86, 0.5, 1.0 }, no_input = true })
    -- (The "showing the HERO/HORDE face" sub-header is gone with the horde
    -- faces; bring both back together if the horde seat becomes playable again.)

    -- Card grid (10 columns x 5 rows = 50) on the left; detail panel on the right.
    local cols = 7
    local margin_x = U(40.0)
    local detail_w = U(300.0)
    local grid_w = sw - margin_x * 2 - detail_w - U(20.0)
    local gap = U(8.0)
    local tile_w = (grid_w - (cols - 1) * gap) / cols
    local top = U(118.0)
    -- Fit the rows between the header and the controls row on ANY surface height.
    -- (At UI scale 1.7 a fixed tile height overflows a 1080p surface, pushing the
    -- bottom cards under the confirm row.) Shrink to fit; cap so it never balloons.
    local rows = math.max(1, math.ceil(#Cards.all_ids / cols))
    local controls_y = sh - U(74.0)
    local grid_budget = controls_y - top - U(18.0)
    local tile_h = math.max(U(36.0), math.min(U(116.0), (grid_budget - (rows - 1) * gap) / rows))
    for i, id in ipairs(Cards.all_ids) do
        local card = Cards.card(id)
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = margin_x + col * (tile_w + gap)
        local y = top + row * (tile_h + gap)
        local rar = Cards.rarity(id)
        local selected = Shell.deck[id] == true
        local clicked, hovered = hit_state("dk_hit_" .. id)
        if hovered then Shell.detail_card = id end
        local fill = selected and { 0.12, 0.20, 0.14, 0.96 } or { 0.08, 0.08, 0.12, 0.92 }
        -- Tile text is a LABEL sub-quad: a title would sit below the reserved
        -- art band, i.e. past the tile bottom, and be clipped to nothing. The
        -- click lands on a transparent hit-quad drawn ON TOP, so the opaque
        -- tile is never raised over its own labels.
        Art.quad(SCREEN, "dk_" .. id, x, y, tile_w, tile_h, fill, {
            border = selected and { 0.4, 0.95, 0.5, 0.98 } or rar.color,
            selected = selected, no_input = true,
        })
        Art.quad(SCREEN, "dk_" .. id .. "_n", x, y, tile_w, tile_h * 0.55, { 0.0, 0.0, 0.0, 0.0 },
            { label = card.name, font_scale = 0.92, text_color = { 0.95, 0.95, 1.0, 1.0 }, no_input = true })
        Art.quad(SCREEN, "dk_" .. id .. "_c", x, y + tile_h - U(26.0), tile_w, U(24.0), { 0.0, 0.0, 0.0, 0.0 },
            { label = "Cost " .. tostring(card.cost) .. "  " .. string.rep("*", rar.stars),
              font_scale = 0.72, text_color = { 0.68, 0.70, 0.78, 1.0 }, no_input = true })
        hit_quad("dk_hit_" .. id, x, y, tile_w, tile_h)
        if clicked then toggle_card(id) end
    end

    -- Detail panel (right). Shows the HERO face only: horde back-faces are
    -- hidden from all card UI while the game is hero-side only (ath_cards still
    -- carries them — the AI horde seat plays them inside the duel).
    local detail_x = sw - margin_x - detail_w
    local dcid = Shell.detail_card or Cards.all_ids[1]
    local dcard = Cards.card(dcid)
    local _, ftext = Cards.face(dcid, face_side)
    Art.quad(SCREEN, "detail", detail_x, top, detail_w, U(330.0), { 0.06, 0.06, 0.10, 0.95 }, {
        border = Cards.rarity(dcid).color, no_input = true,
        title = dcard.name,
        subtitle = "Cost " .. tostring(dcard.cost),
        body = "\n" .. ftext,
    })

    -- Controls.
    local by = controls_y
    if button("deck_default", detail_x, top + U(346.0), U(140.0), U(44.0), nil, { title = "Default 20" }) then set_default_deck() end
    if button("deck_clear", detail_x + U(156.0), top + U(346.0), U(140.0), U(44.0), nil, { title = "Clear" }) then Shell.deck = {}; Shell.deck_count = 0 end

    local ready = Shell.deck_count == Cards.DECK_SIZE
    local confirm_fill = ready and { 0.12, 0.20, 0.10, 0.96 } or { 0.10, 0.10, 0.10, 0.8 }
    if button("deck_confirm", sw * 0.5 - U(150.0), by, U(300.0), U(52.0), nil,
        { title = ready and "CONFIRM" or ("Pick " .. (Cards.DECK_SIZE - Shell.deck_count) .. " more"),
          border = ready and { 0.4, 0.95, 0.5, 0.95 } or { 0.4, 0.4, 0.45, 0.8 }, fill = confirm_fill, footer = "[Enter]" }) then
        if ready then Shell.state = "mode" end
    end
    if (key_pressed("Return") or key_pressed("Space")) and ready then Shell.state = "mode" end
    if button("back", U(40.0), by, U(170.0), U(52.0), "< Back", { footer = "[Esc]" }) or key_pressed("Escape") then
        Shell.state = "home" -- side select is parked; Back skips it (was "side")
    end
end

-- Render a mode's mini-map (normalized rects) inside a tile.
local function draw_minimap(prefix, x, y, w, h, mm)
    mm = mm or {}
    Art.quad(SCREEN, prefix .. "_mm_bg", x, y, w, h, mm.bg or { 0.10, 0.10, 0.14, 1.0 })
    for i, r in ipairs(mm.rects or {}) do
        Art.quad(SCREEN, prefix .. "_mm_" .. i,
            x + (r[1] or 0.0) * w, y + (r[2] or 0.0) * h, (r[3] or 0.1) * w, (r[4] or 0.1) * h,
            r[5] or { 0.4, 0.4, 0.5, 1.0 })
    end
end

local function draw_mode(sw, sh)
    Art.quad(SCREEN, "bg", 0, 0, sw, sh, { 0.05, 0.04, 0.08, 1.0 }, { no_input = true })

    local cols = 2
    local margin_x = U(56.0)
    local col_gap = U(24.0)
    local right_gutter = U(84.0)                 -- room for the scrollbar buttons
    local grid_w = sw - margin_x * 2 - right_gutter
    local tile_w = (grid_w - (cols - 1) * col_gap) / cols
    local tile_h = U(232.0)
    local row_stride = tile_h + U(24.0)

    -- A windowed, scrollable list: tiles draw first, then opaque header/footer
    -- bands mask anything outside the window (there is no engine scissor rect).
    local header_h = U(116.0)
    local footer_h = U(96.0)
    local view_top = header_h
    local view_bottom = sh - footer_h
    local rows = math.max(1, math.ceil(#Shell.modes / cols))
    local content_top = view_top + U(8.0)
    local content_h = (rows - 1) * row_stride + tile_h
    local max_scroll = math.max(0.0, (content_top + content_h) - view_bottom)

    -- Scroll input: mouse wheel, one-finger touch drag, arrow keys, and the
    -- on-screen Up/Dn buttons. NOTE: input.get_mouse_wheel() is zeroed by the
    -- engine while the pointer is over an interactive quad (ImGui WantCaptureMouse),
    -- so the wheel reads over the gaps/background; touch + buttons cover the rest.
    local step = row_stride * 0.6
    if key_pressed("Down") then Shell.mode_scroll = Shell.mode_scroll + step end
    if key_pressed("Up") then Shell.mode_scroll = Shell.mode_scroll - step end
    if input and input.get_mouse_wheel then
        local w = input.get_mouse_wheel()
        if w and w.y and w.y ~= 0 then
            Shell.mode_scroll = Shell.mode_scroll - w.y * step -- wheel up reveals earlier rows
        end
    end
    if input and input.get_touch then
        local tch = input.get_touch()
        if tch and (tch.fingers or 0) > 0 and tch.dy and tch.dy ~= 0.0 then
            -- dy = normalized fraction of the surface this frame (flip the sign if
            -- a finger drag scrolls the wrong way on your device).
            Shell.mode_scroll = Shell.mode_scroll - tch.dy * sh
        end
    end
    Shell.mode_scroll = math.max(0.0, math.min(max_scroll, Shell.mode_scroll))
    local scroll = Shell.mode_scroll

    for i, entry in ipairs(Shell.modes) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = margin_x + col * (tile_w + col_gap)
        local y = content_top + row * row_stride - scroll
        local meta = entry.meta
        local visible = (y + tile_h) > view_top and y < view_bottom
        local clicked, hovered = hit_state("mode_hit_" .. entry.id)
        -- Tile background + border only. The name / mini-map / hint are drawn as
        -- their OWN sub-quads so the mini-map never covers the text.
        Art.quad(SCREEN, "mode_" .. entry.id, x, y, tile_w, tile_h,
            hovered and { 0.14, 0.14, 0.22, 0.97 } or { 0.08, 0.09, 0.14, 0.94 },
            { border = (meta.accent or { 0.5, 0.55, 0.7, 0.95 }) })
        Art.quad(SCREEN, "mode_name_" .. entry.id, x, y + U(8.0), tile_w, U(40.0), { 0, 0, 0, 0 },
            { label = meta.name or entry.id, text_color = { 0.96, 0.92, 0.7, 1.0 }, font_scale = 1.15 })
        draw_minimap("mode_" .. entry.id, x + U(18.0), y + U(54.0), tile_w - U(36.0), tile_h - U(108.0), meta.minimap)
        Art.quad(SCREEN, "mode_tag_" .. entry.id, x, y + tile_h - U(40.0), tile_w, U(32.0), { 0, 0, 0, 0 },
            { label = meta.tagline or "click to deploy", text_color = { 0.62, 0.66, 0.76, 1.0 } })
        -- Transparent hit-quad on top owns the whole tile's click/hover.
        hit_quad("mode_hit_" .. entry.id, x, y, tile_w, tile_h)
        if clicked and visible then launch_mode(entry) end
    end

    -- Opaque masking bands over the scrolled tiles (drawn AFTER the tiles).
    -- NOTE: ids here must be unique to this screen. Overlay-quad z-order is the
    -- ImGui window CREATION order persisted by id, so an id reused from an
    -- earlier screen (the old shared "hdr"/"back") keeps its ancient low slot
    -- and ends up hidden UNDER these later-created bands.
    Art.quad(SCREEN, "mode_header_band", 0, 0, sw, header_h, { 0.05, 0.04, 0.08, 1.0 }, { no_input = true })
    Art.quad(SCREEN, "mode_hdr_t", U(40.0), U(18.0), sw - U(80.0), U(48.0), { 0.0, 0.0, 0.0, 0.0 },
        { label = "CHOOSE A BATTLEFIELD", font_scale = 1.3, text_color = { 0.96, 0.86, 0.5, 1.0 }, no_input = true })
    Art.quad(SCREEN, "mode_hdr_s", U(40.0), U(62.0), sw - U(80.0), U(36.0), { 0.0, 0.0, 0.0, 0.0 },
        { label = "playing as " .. ((Shell.side or "hero"):upper()) .. "   -   " .. tostring(Shell.deck_count) .. " cards"
                  .. (max_scroll > 0.0 and "   -   wheel / drag / Up-Down to scroll" or ""),
          font_scale = 0.9, text_color = { 0.78, 0.74, 0.62, 1.0 }, no_input = true })
    Art.quad(SCREEN, "mode_footer_band", 0, view_bottom, sw, footer_h + U(2.0), { 0.05, 0.04, 0.08, 1.0 }, { no_input = true })

    if #Shell.modes == 0 then
        Art.quad(SCREEN, "nomodes", sw * 0.5 - U(300.0), sh * 0.4, U(600.0), U(90.0), { 0.12, 0.06, 0.06, 0.95 },
            { border = { 0.9, 0.4, 0.4, 0.95 }, title = "No modes available",
              body = "Scripts/shared/ath_modes_index.lua lists no loadable modes." })
    end

    -- Scroll buttons (right gutter) — after the bands so they stay on top.
    if max_scroll > 0.0 then
        if button("scroll_up", sw - U(76.0), view_top + U(12.0), U(60.0), U(60.0), "Up", { font_scale = 1.2 }) then
            Shell.mode_scroll = math.max(0.0, Shell.mode_scroll - step)
        end
        if button("scroll_dn", sw - U(76.0), view_bottom - U(72.0), U(60.0), U(60.0), "Dn", { font_scale = 1.2 }) then
            Shell.mode_scroll = math.min(max_scroll, Shell.mode_scroll + step)
        end
    else
        Art.remove(SCREEN, "scroll_up"); Art.remove(SCREEN, "scroll_dn")
    end

    -- Unique id: a shared "back" was first created on an earlier screen, so its
    -- window z-slot predates the footer band's and the band painted over it.
    if button("mode_back", U(40.0), sh - U(80.0), U(170.0), U(52.0), "< Back", { footer = "[Esc]" }) or key_pressed("Escape") then
        Shell.state = "deck"
    end
end

-- ---------------------------------------------------------------------------
-- HUD overlay — a 7-segment FPS "clock" (top-right) and, while a mode is
-- running, a visible "return to menu" control. Drawn on its OWN screen (HUD) so
-- it survives the main SCREEN being hidden during play.
-- ---------------------------------------------------------------------------

-- Which of the 7 segments (a b c d e f g) light per digit 0-9:
--    aaa
--   f   b
--    ggg
--   e   c
--    ddd
local SEVEN_SEG = {
    [0] = { a = true, b = true, c = true, d = true, e = true, f = true },
    [1] = { b = true, c = true },
    [2] = { a = true, b = true, g = true, e = true, d = true },
    [3] = { a = true, b = true, g = true, c = true, d = true },
    [4] = { f = true, g = true, b = true, c = true },
    [5] = { a = true, f = true, g = true, c = true, d = true },
    [6] = { a = true, f = true, g = true, e = true, c = true, d = true },
    [7] = { a = true, b = true, c = true },
    [8] = { a = true, b = true, c = true, d = true, e = true, f = true, g = true },
    [9] = { a = true, b = true, c = true, d = true, f = true, g = true },
}
local SEG_NAMES = { "a", "b", "c", "d", "e", "f", "g" }
local SEG_LIT = { 0.66, 0.45, 1.0, 1.0 }   -- backlit violet, like the clock face
local SEG_OFF = { 0.26, 0.20, 0.42, 0.20 } -- faint ghost of an unlit segment

-- Draw one 7-seg digit cell. `on` = a SEVEN_SEG entry (nil → all-unlit).
local function draw_seg_digit(prefix, x, y, w, h, on)
    on = on or {}
    local t = math.max(2.0, w * 0.20)
    local midy = y + h * 0.5 - t * 0.5
    local vh = (h - 3.0 * t) * 0.5
    local function seg(name, sx, sy, sw, sh)
        Art.quad(HUD, prefix .. "_" .. name, sx, sy, sw, sh, on[name] and SEG_LIT or SEG_OFF, { no_input = true })
    end
    seg("a", x + t, y, w - 2.0 * t, t)
    seg("g", x + t, midy, w - 2.0 * t, t)
    seg("d", x + t, y + h - t, w - 2.0 * t, t)
    seg("f", x, y + t, t, vh)
    seg("b", x + w - t, y + t, t, vh)
    seg("e", x, midy + t, t, vh)
    seg("c", x + w - t, midy + t, t, vh)
end

local FPS_CELLS = 4 -- max digits; cells beyond the current reading are cleared
local FPS_SAMPLE_SECONDS = 0.25

local function draw_fps_clock(sw)
    local m = engine and engine.get_metrics and engine.get_metrics() or nil
    local delta_ms = m and m.delta_ms or nil
    if (not delta_ms or delta_ms <= 0.0) and m and m.fps and m.fps > 0.0 then
        delta_ms = 1000.0 / m.fps
    end
    delta_ms = (delta_ms and delta_ms > 0.0) and delta_ms or (1000.0 / 60.0)

    Shell.fps_bucket_ms = (Shell.fps_bucket_ms or 0.0) + delta_ms
    Shell.fps_bucket_frames = (Shell.fps_bucket_frames or 0) + 1
    Shell.fps_bucket_seconds = (Shell.fps_bucket_seconds or 0.0) + delta_ms / 1000.0
    if not Shell.fps_display or Shell.fps_bucket_seconds >= FPS_SAMPLE_SECONDS then
        local avg_ms = Shell.fps_bucket_ms / math.max(1, Shell.fps_bucket_frames)
        Shell.fps_display = avg_ms > 0.0 and 1000.0 / avg_ms or 0.0
        Shell.fps_bucket_ms = 0.0
        Shell.fps_bucket_frames = 0
        Shell.fps_bucket_seconds = 0.0
    end

    local shown = math.max(0, math.min(9999, math.floor((Shell.fps_display or 0.0) + 0.5)))
    local s = tostring(shown)
    local ndig = #s

    local dw, dh, gap, pad, margin, labw = U(20.0), U(34.0), U(6.0), U(10.0), U(16.0), U(50.0)
    local panel_w = labw + ndig * dw + (ndig - 1) * gap + pad * 2.0
    local panel_h = dh + pad * 2.0
    local px = sw - panel_w - margin
    local py = margin
    Art.quad(HUD, "fps_panel", px, py, panel_w, panel_h, { 0.03, 0.03, 0.06, 0.85 },
        { border = { 0.32, 0.24, 0.5, 0.9 }, no_input = true })
    Art.quad(HUD, "fps_label", px + pad, py + pad, labw - U(6.0), dh, { 0, 0, 0, 0 },
        { label = "FPS", text_color = { 0.55, 0.45, 0.82, 1.0 }, no_input = true })
    local x0 = px + pad + labw
    local y0 = py + pad
    for i = 1, FPS_CELLS do
        local prefix = "fps_d" .. i
        if i <= ndig then
            draw_seg_digit(prefix, x0 + (i - 1) * (dw + gap), y0, dw, dh, SEVEN_SEG[tonumber(s:sub(i, i))])
        else
            for _, name in ipairs(SEG_NAMES) do Art.remove(HUD, prefix .. "_" .. name) end
        end
    end
end

-- A button on the HUD screen (mirrors button(), but on the always-on overlay).
local function hud_button(id, x, y, w, h, label)
    local st = Art.widget_state(HUD, id)
    local hovered = st and st.hovered
    Art.quad(HUD, id, x, y, w, h, hovered and { 0.22, 0.11, 0.12, 0.97 } or { 0.13, 0.07, 0.08, 0.92 },
        { border = { 0.9, 0.45, 0.35, 0.95 }, label = label, text_color = { 0.96, 0.86, 0.72, 1.0 }, font_scale = 1.05 })
    return Art.consume_click(HUD, id)
end

-- In-play options live behind a small gear (top-right, under the FPS clock)
-- instead of an always-visible "< Menu" button. There is no icon font, so the
-- gear is composed from quads: 4 teeth + a body + a dark hub (the backend's
-- corner rounding makes the small quads read round). Clicks land on a
-- transparent hit-quad on top so the opaque art is never raised over itself.
local GEAR_IDS = { "hud_gear_bg", "hud_gear_t_n", "hud_gear_t_s", "hud_gear_t_w", "hud_gear_t_e",
    "hud_gear_body", "hud_gear_hub", "hud_gear_hit", "hud_gear_menu" }

local function draw_gear_button(sw)
    local size = U(40.0)
    local margin = U(16.0)
    local gx = sw - margin - size
    local gy = margin + U(54.0) + U(10.0) -- just below the FPS clock panel
    local st = Art.widget_state(HUD, "hud_gear_hit")
    local hovered = st and st.hovered
    Art.quad(HUD, "hud_gear_bg", gx, gy, size, size,
        hovered and { 0.16, 0.13, 0.22, 0.95 } or { 0.05, 0.04, 0.09, 0.88 },
        { border = { 0.32, 0.24, 0.5, 0.9 }, no_input = true })
    local cx, cy = gx + size * 0.5, gy + size * 0.5
    local body = size * 0.46
    local tooth = size * 0.16
    local tcol = hovered and { 0.78, 0.70, 0.95, 1.0 } or { 0.55, 0.45, 0.82, 1.0 }
    Art.quad(HUD, "hud_gear_t_n", cx - tooth * 0.5, cy - body * 0.5 - tooth * 0.6, tooth, tooth, tcol, { no_input = true })
    Art.quad(HUD, "hud_gear_t_s", cx - tooth * 0.5, cy + body * 0.5 - tooth * 0.4, tooth, tooth, tcol, { no_input = true })
    Art.quad(HUD, "hud_gear_t_w", cx - body * 0.5 - tooth * 0.6, cy - tooth * 0.5, tooth, tooth, tcol, { no_input = true })
    Art.quad(HUD, "hud_gear_t_e", cx + body * 0.5 - tooth * 0.4, cy - tooth * 0.5, tooth, tooth, tcol, { no_input = true })
    Art.quad(HUD, "hud_gear_body", cx - body * 0.5, cy - body * 0.5, body, body, tcol, { no_input = true })
    Art.quad(HUD, "hud_gear_hub", cx - body * 0.18, cy - body * 0.18, body * 0.36, body * 0.36,
        hovered and { 0.16, 0.13, 0.22, 1.0 } or { 0.05, 0.04, 0.09, 1.0 }, { no_input = true })
    Art.quad(HUD, "hud_gear_hit", gx, gy, size, size, { 0.0, 0.0, 0.0, 0.0 })
    if Art.consume_click(HUD, "hud_gear_hit") then
        Shell.gear_open = not Shell.gear_open
    end

    if Shell.gear_open then
        if hud_button("hud_gear_menu", gx + size - U(188.0), gy + size + U(8.0), U(188.0), U(40.0), "< Menu  [Esc]") then
            Shell.gear_open = false
            return_to_menu()
        end
    else
        Art.remove(HUD, "hud_gear_menu")
    end
end

-- Drawn every frame on the always-visible HUD screen: letterbox bars, FPS clock,
-- and (while a mode is running) a "return to menu" button.
local function draw_hud_overlay()
    local sw = Art.surface_size()
    Art.draw_letterbox(HUD)
    draw_fps_clock(sw)
    if Shell.state == "playing" then
        draw_gear_button(sw)
    else
        Shell.gear_open = false
        Art.remove_ids(HUD, GEAR_IDS)
    end
end

-- ---------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------

local function update()
    local dt = delta_seconds()

    -- Deferred env quick-launch (see maybe_env_quicklaunch).
    if Shell.pending_quicklaunch then
        Shell.pending_quicklaunch_frames = (Shell.pending_quicklaunch_frames or 0) - 1
        if Shell.pending_quicklaunch_frames <= 0 then
            local entry = Shell.pending_quicklaunch
            Shell.pending_quicklaunch = nil
            launch_mode(entry)
        end
    end

    -- The HUD overlay (letterbox bars + FPS clock + in-play menu button) lives on
    -- its own always-visible screen, so draw it every frame regardless of state.
    draw_hud_overlay()

    if Shell.state == "playing" then
        if Shell.active then Shell.active:update(dt) end
        return
    end

    -- Menu states share one screen; clear stale widgets on transition.
    if Shell.last_state ~= Shell.state then
        clear_screen()
        Shell.last_state = Shell.state
    end

    local sw, sh = Art.surface_size()

    -- Full-surface black bg behind game content — covers the 3D scene at the
    -- edges so the letterbox area is black even without the HUD bars stacking.
    local vp = Art._vp
    Art.quad(SCREEN, "bg_full", -vp.x, -vp.y, vp.rw, vp.rh, { 0.0, 0.0, 0.0, 1.0 }, { no_input = true })

    if Shell.state == "home" then
        draw_home(sw, sh)
    elseif Shell.state == "side" then
        draw_side(sw, sh)
    elseif Shell.state == "deck" then
        draw_deck(sw, sh)
    elseif Shell.state == "mode" then
        draw_mode(sw, sh)
    end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

-- The handle modes receive so they can return to the menu.
Shell.api = { return_to_menu = return_to_menu }

local function maybe_env_quicklaunch()
    -- Smoke-test shortcut: ATH_DUEL_MODE=<id> [ATH_SIDE=hero|horde] jumps past the
    -- menu straight into a mode with the default deck.
    -- DEFERRED a few frames: launching at frame ~0 configures the camera before
    -- its first engine update, and the GPU's view-projection then freezes on a
    -- degenerate first-frame matrix — the run renders massively zoomed-in.
    -- (Menu-path launches never hit this; the camera has been updating for ages.)
    local mode_id = ATH_COMMON.getenv("ATH_DUEL_MODE", nil)
    if not mode_id then return false end
    for _, entry in ipairs(Shell.modes) do
        if entry.id == mode_id then
            Shell.side = (ATH_COMMON.getenv("ATH_SIDE", "hero") == "horde") and "horde" or "hero"
            set_default_deck()
            Shell.pending_quicklaunch = entry
            Shell.pending_quicklaunch_frames = 240
            return true
        end
    end
    log("ATH_DUEL_MODE='" .. tostring(mode_id) .. "' not found; showing menu")
    return false
end

local function init()
    if runtime_ui then
        if runtime_ui.set_title then runtime_ui.set_title(SCREEN, "Against The Hero") end
        if runtime_ui.set_screen_overlay then runtime_ui.set_screen_overlay(SCREEN, true) end
        if runtime_ui.show then runtime_ui.show(SCREEN) end
        -- Always-on HUD overlay (FPS clock + in-play menu button); never hidden,
        -- so it stays up while a mode hides the main SCREEN during play.
        if runtime_ui.set_screen_overlay then runtime_ui.set_screen_overlay(HUD, true) end
        if runtime_ui.show then runtime_ui.show(HUD) end
    end
    set_default_deck()
    load_modes()
    if not maybe_env_quicklaunch() then
        -- ATH_START=home|side|deck|mode jumps straight to a screen (QA convenience).
        Shell.state = ATH_COMMON.getenv("ATH_START", "home")
    end
    if script and script.on_update then
        script.on_update(UPDATE_ID, update, "play")
    else
        _G.update = update
    end
    log("initialized")
end

local function destroy()
    if Shell.active then Shell.active:stop(); Shell.active = nil end
    if script and script.remove_update then script.remove_update(UPDATE_ID) end
    clear_screen()
    if runtime_ui and runtime_ui.clear then runtime_ui.clear(HUD) end
    log("destroyed")
end

hooks {
    init = init,
    destroy = destroy,
}
