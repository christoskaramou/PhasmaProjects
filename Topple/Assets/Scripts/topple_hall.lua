-- Topple's Great Hall: Free Build's big brother, a floor for millions of dominoes. topple_hall_core.lua holds the
-- dominoes and the chain; the engine's hinge field draws them; this file is the tools, the camera and the HUD.
return function(F, FW, HC, ctx)
local H = {}
local floor, min, max, abs, sin, cos, sqrt = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt
local pi = math.pi
local C = ctx.C
local text, panel, rect, image, hide, catcher = ctx.text, ctx.panel, ctx.rect, ctx.image, ctx.hide, ctx.catcher
local clicked, hovered, col4, commas, sound = ctx.clicked, ctx.hovered, ctx.col4, ctx.commas, ctx.sound
local quad, pid = ctx.quad, ctx.pid
local pressed = ctx.edge()

local B = HC.BOUND
local WORLD = {
    limits = { x0 = -B, x1 = B, y0 = -B, y1 = B, dmin = 5, dmax = 3200 },
    far = 16000,
    sky = "hall.hdr",
    ibl = 0.8,
    pieces = {
        { name = "hall_floor", color = { 1, 1, 1 }, rough = 0.82, tex = "Textures/hall_floor.png" },
        { name = "hall_walls", color = { 0.84, 0.73, 0.56 }, rough = 0.92 },
        { name = "hall_trim", color = { 0.9, 0.85, 0.74 }, rough = 0.6 },
        { name = "hall_wood", color = { 0.42, 0.28, 0.16 }, rough = 0.6 },
    },
    -- High and behind the camera's usual places, so faces are lit and shadows fall away from you.
    sun = { dir = { -0.42, -0.62, -0.66 }, color = { 1, 0.92, 0.8 }, intensity = 4.2 },
    fill = { dir = { 0.5, -0.7, 0.5 }, color = { 0.8, 0.88, 1 }, intensity = 0.32 },
}
local NEAR_LOD = 170            -- within this the dominoes are whole boxes; beyond it, two quads each
local SHADOW_MAX_DIST = 320     -- a camera further out than this sees dominoes smaller than a shadow texel

local SAVE, BEST = "Save/hall_autosave.txt", "Save/hall_best.txt"
local MILESTONES = { 100000, 500000, 1000000, 2500000, 5000000 }
local best = tonumber(fs.read(BEST) or "0") or 0

local TOOLS = {
    { id = "field", name = "FIELD", icon = "tool_field", hint = "Press where it starts, drag the way it runs: it fans out to its width.  [ ] width" },
    { id = "line", name = "LINE", icon = "tool_line", hint = "Press and drag: a straight line, laid when you let go." },
    { id = "spiral", name = "SPIRAL", icon = "tool_spiral", hint = "Press at the middle, drag out to the size you want. Hold Shift to wind it the other way." },
    { id = "draw", name = "DRAW", icon = "tool_draw", hint = "Drag to lay a line of dominoes along your path." },
    { id = "erase", name = "ERASE", icon = "tool_erase", hint = "Drag over dominoes to lift them away.  [ ] brush size" },
    { id = "start", name = "START", icon = "tool_start", hint = "Click the domino the tip knocks over. Click it again to push it the other way." },
    { id = "picture", name = "PICTURE", icon = "tool_picture", hint = "Choose a picture, or draw one. Press where the wave starts and drag across the floor: longer makes it bigger." },
    { id = "split", name = "SPLIT", icon = "tool_split", hint = "Press on the end of a line, or on the floor, and drag the way the wave should go: it splits into branches.  [ ] branches" },
    { id = "bell", name = "BELL", icon = "bell", hint = "Click beside a line to hang a bell there: it rings when the wave goes past. Erase lifts it away." },
}
local CANVAS_W, CANVAS_H, MAX_PICTURES = 48, 30, 8
local PAINTS = { "rainbow", "brick", "mustard", "sage", "navy", "cream" }
local SWATCH = { brick = { 0.66, 0.27, 0.17, 1 }, mustard = { 0.86, 0.64, 0.24, 1 }, sage = { 0.52, 0.62, 0.47, 1 },
    navy = { 0.2, 0.26, 0.42, 1 }, cream = { 0.92, 0.87, 0.75, 1 } }
local SAMPLES = { { n = 1000000, label = "1 MILLION" }, { n = 2500000, label = "2.5 MILLION" }, { n = 5000000, label = "5 MILLION" } }
H.KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "Space", "Return", "R", "Z", "F", "H", "C", "P", "Tab", "Home", "Backspace", "Y", "[", "]", "Delete" }

local S = { tool = "field", paint = "rainbow", field_w = HC.FIELD_WIDTH.default, erase_r = HC.ERASE.default, mode = "build",
    speed = 1, t = 0, clock = 0, run_t = 0, hud = true, msg = nil, msg_t = 0, follow = true, split_n = HC.SPLIT.default }
H.S, H.core = S, HC

local function say(s, bad) S.msg, S.msg_t, S.msg_bad = s, 2.6, bad end

local function paint_name() return S.paint ~= "rainbow" and S.paint or nil end

local function autosave_later() S.save_due = S.clock + 1.5 end
local function autosave()
    S.save_due = nil
    local ok, wrote = pcall(fs.write, SAVE, HC.serialize())
    if not (ok and wrote) then say("Couldn't autosave the hall.", true) end
end

------------------------------------------------------------------ long jobs
-- Laying a build runs a slice per frame. fn may yield; after() runs when it has finished.
local function job(label, target, fn, after)
    S.job = coroutine.create(fn)
    S.job_label, S.job_target, S.job_after = label, target, after
end

local function show_starter()
    local i, x, y, a, dir = HC.starter()
    if i then FW.set_starter({ x = x, y = y, z = 0, a = a }, dir) else FW.set_starter(nil) end
end

-- One bell model per live bell, from a pool.
local bell_vis, ripples = {}, {}
local function sync_bells()
    local n = 0
    for _, b in ipairs(HC.bells) do
        if not b.dead then
            n = n + 1
            if not bell_vis[n] then bell_vis[n] = FW.make_bell() end
            local v = bell_vis[n]
            FW.place_bell(v, b.x, b.y, b.a)
            v.swing:set_rotation(vec3(0, 0, 0))
            v.ring_t, b.vis = nil, v
        end
    end
    for i = n + 1, #bell_vis do FW.hide_bell(bell_vis[i]) end
end
local function still_bells()
    for _, v in ipairs(bell_vis) do
        if v.ring_t then v.ring_t = nil; v.swing:set_rotation(vec3(0, 0, 0)) end
    end
    for i = #ripples, 1, -1 do ripples[i] = nil end
end

local function changed()
    show_starter()
    sync_bells()
    autosave_later()
end

local function add_op(op, label, target)
    if S.mode == "done" then HC.stand(); S.mode = "build" end
    S.first_visit = nil
    job(label or "Laying dominoes", target, function() HC.add(op) end, function()
        changed()
        sound("place")
    end)
end

local function load_sample(n)
    if S.mode ~= "build" then HC.stand(); S.mode = "build" end
    S.first_visit = nil
    add_op({ k = "sample", n = n }, "Laying " .. commas(n) .. " dominoes", n)
    local L = n > 2000000 and 2400 or 1500
    FW.goal.x, FW.goal.y, FW.goal.h, FW.goal.dist, FW.goal.pitch, FW.goal.yaw = 0, 0, 0, L, 42, -90
end

local function find_pictures()
    S.pictures = {}
    local ok, listed = pcall(function() return fs.list and fs.list("Pictures") end)
    for _, name in ipairs(ok and listed and listed.files or {}) do
        local low = name:lower()
        if #S.pictures < MAX_PICTURES and (low:match("%.png$") or low:match("%.jpe?g$")) then
            S.pictures[#S.pictures + 1] = name
        end
    end
    if not S.pic then S.pic = S.pictures[1] end
end

local function canvas_source(cv) return "draw:" .. CANVAS_W .. ":" .. CANVAS_H .. ":" .. table.concat(cv.cells) end

local function open_canvas()
    local cells = {}
    for i = 1, CANVAS_W * CANVAS_H do cells[i] = S.drawn and S.drawn.cells[i] or "0" end
    S.canvas = { cells = cells, brush = 2 }
end

local function stand_up()
    if S.mode == "build" then return end
    HC.stand()
    S.mode, S.front = "build", nil
    show_starter()
    still_bells()
end

local function tip()
    if S.mode == "running" or S.job then return end
    if S.mode == "done" then HC.stand() end
    still_bells()
    if not HC.tip() then say("Lay some dominoes first.", true); sound("click"); return end
    local _, x, y = HC.starter()
    hinge_field.stand_all()
    S.mode, S.run_t, S.speed, S.front = "running", 0, 1, { x = x, y = y }
    S.last_clack, S.new_best, S.milestone = nil, false, nil
    FW.set_starter(nil)
    FW.set_cursor(nil)
    if S.follow then
        -- From in front of the first domino, looking back at the wave coming: the broad faces, not their thin edges.
        local _, _, _, a, dir = HC.starter()
        local facing = dir >= 0 and a or a + pi
        FW.goal.yaw, FW.goal.pitch, FW.goal.dist = math.deg(facing) + 28, 24, 34
        S.front_width = nil
    end
    sound("tip")
end

local function finish()
    S.mode = "done"
    local n = HC.toppled
    if n > best then
        best = n
        S.new_best = true
        pcall(fs.write, BEST, tostring(best))
    end
    for _, m in ipairs(MILESTONES) do if n >= m then S.milestone = m end end
    sound("cheer")
end

------------------------------------------------------------------ input
local function key(k) return input.is_key_down_raw(k) end
local function shift() return key("Left Shift") or key("Right Shift") end
local function ctrl() return key("Left Ctrl") or key("Right Ctrl") end
local function raw_mouse()
    local ok, m = pcall(input.get_mouse_position)
    if not ok or not m then return nil end
    local sw, sh = FW.screen_size()
    local okw, ws = pcall(engine.get_window_size)
    local ww = okw and ws and (ws.w or ws.width)
    local wh = okw and ws and (ws.h or ws.height)
    if ww and ww > 0 and wh and wh > 0 then return m.x / ww * sw, m.y / wh * sh end
    return m.x, m.y
end
local hot = {}
local function over_ui()
    for id in pairs(hot) do if hovered(id) then return true end end
    return false
end

local function floor_at(mx, my)
    local x, y = FW.plane_point(mx, my, 0)
    if x and abs(x) < B - 3 and abs(y) < B - 3 then return x, y end
end

local function tool_press(mx, my)
    local x, y = floor_at(mx, my)
    if not x then return end
    local t = S.tool
    if t == "start" then
        local i, px, py = HC.pick(x, y, 2.5)
        if not i then say("Click a domino.", true); return end
        local cur = HC.starter()
        local _, _, _, _, dir = HC.starter()
        add_op({ k = "start", x = px, y = py, dir = cur == i and -dir or 1 })
    elseif t == "bell" then
        local bx, by, a = HC.bell_spot(x, y)
        if not bx then say(by, true); return end
        add_op({ k = "bell", x = bx, y = by, a = a })
    elseif t == "picture" and not S.pic then
        say("Choose a picture or draw one first.", true)
    elseif t == "draw" then S.press = { kind = t, pts = { x, y }, lx = x, ly = y }
    elseif t == "erase" then S.press = { kind = t, pts = { x, y, S.erase_r }, lx = x, ly = y }
    else S.press = { kind = t, x0 = x, y0 = y, x1 = x, y1 = y } end
end

local function tool_drag(mx, my)
    local P = S.press
    local x, y = floor_at(mx, my)
    if not x then return end
    if P.kind == "draw" then
        if sqrt((x - P.lx) ^ 2 + (y - P.ly) ^ 2) >= 0.4 then
            P.pts[#P.pts + 1], P.pts[#P.pts + 2] = x, y
            P.lx, P.ly = x, y
        end
    elseif P.kind == "erase" then
        if sqrt((x - P.lx) ^ 2 + (y - P.ly) ^ 2) >= S.erase_r * 0.5 then
            P.pts[#P.pts + 1], P.pts[#P.pts + 2], P.pts[#P.pts + 3] = x, y, S.erase_r
            P.lx, P.ly = x, y
        end
    else
        P.x1, P.y1 = x, y
    end
end

-- A splitter pressed on a domino starts one step beyond it, so the line it continues runs straight into its point.
local function split_op(P)
    local op = { k = "splitter", ax = P.x0, ay = P.y0, bx = P.x1, by = P.y1, n = S.split_n, paint = paint_name() }
    local i, px, py, a = HC.pick(P.x0, P.y0, 2)
    if i then
        local fx, fy = cos(a), sin(a)
        if (P.x1 - px) * fx + (P.y1 - py) * fy < 0 then fx, fy = -fx, -fy end
        op.ax, op.ay = px + fx * F.SPACING, py + fy * F.SPACING
    end
    return op
end

local function tool_release()
    local P = S.press
    S.press = nil
    local L = P.x1 and sqrt((P.x1 - P.x0) ^ 2 + (P.y1 - P.y0) ^ 2) or 0
    if P.kind == "draw" then
        if #P.pts >= 4 then add_op({ k = "draw", pts = P.pts, paint = paint_name() }) end
    elseif P.kind == "erase" then
        add_op({ k = "erase", pts = P.pts }, "Lifting dominoes")
    elseif L < 0.6 then
        return
    elseif P.kind == "split" then
        local op = split_op(P)
        if HC.splitter_paths(op) then add_op(op) else say("Drag further: a splitter needs room for its branches.", true) end
    elseif P.kind == "picture" then
        local _, _, _, n = HC.picture_layout(S.pic, L)
        if not n then say("That picture could not be read.", true); return end
        add_op({ k = "picture", src = S.pic, ax = P.x0, ay = P.y0, bx = P.x1, by = P.y1 }, "Painting in dominoes", n)
    elseif P.kind == "field" then
        local n = floor(S.field_w / F.FIELD_LAT) + 1
        add_op({ k = "field", ax = P.x0, ay = P.y0, bx = P.x1, by = P.y1, w = S.field_w, paint = paint_name() }, nil,
            floor(L / F.SPACING) * n)
    elseif P.kind == "line" then
        add_op({ k = "line", ax = P.x0, ay = P.y0, bx = P.x1, by = P.y1, paint = paint_name() })
    elseif P.kind == "spiral" then
        add_op({ k = "spiral", cx = P.x0, cy = P.y0, sx = P.x1, sy = P.y1, cw = shift(), paint = paint_name() })
    end
end

local function camera_input(dt, mx, my, ui)
    local rd, md = input.is_right_mouse_down and input.is_right_mouse_down(), input.is_middle_mouse_down and input.is_middle_mouse_down()
    local ok, wh = pcall(input.get_mouse_wheel)
    if ok and wh and wh.y and wh.y ~= 0 and not ui then FW.zoom(wh.y) end
    if mx and S.mx then
        local dx, dy = mx - S.mx, my - S.my
        if rd and S.rdown then
            if shift() then FW.pan(-dx, dy) else FW.orbit(dx, dy) end
        end
        if md and S.mdown then FW.pan(-dx, dy) end
    end
    S.rdown, S.mdown = rd, md
    local px, py = 0, 0
    if key("W") or key("Up") then py = py + 1 end
    if key("S") or key("Down") then py = py - 1 end
    if key("D") or key("Right") then px = px + 1 end
    if key("A") or key("Left") then px = px - 1 end
    if px ~= 0 or py ~= 0 then FW.pan(px * dt * 420, py * dt * 420) end
    if key("Q") then FW.orbit(-dt * 300, 0) end
    if key("E") then FW.orbit(dt * 300, 0) end
    if pressed("Tab") then S.top = not S.top; FW.top_view(S.top); sound("click") end
    if pressed("Home") then FW.goal.x, FW.goal.y, FW.goal.h = 0, 0, 0; FW.goal.dist = 1500; S.top = false; sound("click") end
end

function H.flush_keys() for _, k in ipairs(H.KEYS) do pressed(k) end end

local function canvas_layout()
    local u, w, h = ctx.u(), ctx.L.w, ctx.L.h
    local c = floor(min(1200 * u / CANVAS_W, 660 * u / CANVAS_H))
    local gw, gh = c * CANVAS_W, c * CANVAS_H
    return u, c, (w - gw) / 2, (h - gh) / 2 - 40 * u, gw, gh
end

H.canvas_layout = canvas_layout

local function canvas_input()
    local cv = S.canvas
    for i = 1, #HC.DRAW_COLORS do
        if clicked("gh_cv_col" .. i) then cv.brush = i; sound("click") end
    end
    if clicked("gh_cv_clear") then
        for i = 1, #cv.cells do cv.cells[i] = "0" end
        sound("remove")
    end
    if clicked("gh_cv_cancel") then S.canvas = nil; sound("click"); return end
    if clicked("gh_cv_done") then
        S.drawn, S.pic, S.canvas = cv, canvas_source(cv), nil
        sound("place")
        say("Now press on the floor and drag to lay it out.")
        return
    end
    -- The canvas covers the screen, so the UI holds the mouse: input.* reports no button and 0, 0 here.
    local st = ctx.state("gh_canvas")
    local mx, my = st and st.mouse_x, st and st.mouse_y
    if not (mx and st.down) then cv.lx, cv.ly = nil, nil; return end
    local _, c, gx, gy = canvas_layout()
    local x, y = floor((mx - gx) / c), floor((my - gy) / c)
    local x0, y0 = cv.lx or x, cv.ly or y
    local steps = max(abs(x - x0), abs(y - y0), 1)
    for k = 0, steps do
        local px, py = floor(x0 + (x - x0) * k / steps + 0.5), floor(y0 + (y - y0) * k / steps + 0.5)
        if px >= 0 and px < CANVAS_W and py >= 0 and py < CANVAS_H then cv.cells[py * CANVAS_W + px + 1] = tostring(cv.brush - 1) end
    end
    cv.lx, cv.ly = x, y
end

function H.controls(dt)
    S.clock = S.clock + dt
    if S.canvas then canvas_input(); return end
    local ui = over_ui()
    local mx, my = raw_mouse()
    if ui then mx, my = S.mx, S.my end
    camera_input(dt, (not ui) and mx or nil, my, ui)
    if pressed("H") then S.hud = not S.hud; sound("click") end
    if pressed("F") or clicked("gh_follow") then S.follow = not S.follow; sound("click") end
    if clicked("gh_menu") then sound("click"); ctx.back_to_menu(); return end
    if S.job then return end

    if S.mode == "running" then
        if pressed("Z") or clicked("gh_slow") then S.speed = S.speed < 1 and 1 or 0.25; sound("click") end
        if pressed("R") or clicked("gh_stand") then stand_up(); sound("remove") end
        if pressed("Space") or pressed("Return") then stand_up() end
    else
        local enter = pressed("Space") or pressed("Return") or clicked("gh_tip")
        if S.mode == "done" and (pressed("R") or clicked("gh_stand")) then stand_up(); sound("remove") end
        for i, t in ipairs(TOOLS) do
            if pressed(tostring(i)) or clicked("gh_tool" .. i) then
                S.tool = t.id; S.press = nil; sound("click")
                if t.id == "picture" then find_pictures() end
            end
        end
        if S.tool == "picture" then
            for i, name in ipairs(S.pictures or {}) do
                if clicked("gh_pic" .. i) then S.pic = name; sound("click") end
            end
            if clicked("gh_pic_draw") then sound("click"); open_canvas(); return end
        end
        for i, p in ipairs(PAINTS) do
            if clicked("gh_paint" .. i) then S.paint = p; sound("click") end
        end
        if pressed("P") then
            for i, p in ipairs(PAINTS) do if p == S.paint then S.paint = PAINTS[i % #PAINTS + 1]; break end end
            sound("click")
        end
        local kl, kr = pressed("["), pressed("]")
        if kl or kr then
            if S.tool == "split" then
                S.split_n = max(HC.SPLIT.min, min(HC.SPLIT.max, S.split_n + (kr and 1 or -1)))
            elseif S.tool == "erase" then
                S.erase_r = max(HC.ERASE.min, min(HC.ERASE.max, S.erase_r * (kr and 1.3 or 1 / 1.3)))
            else
                S.field_w = max(HC.FIELD_WIDTH.min, min(HC.FIELD_WIDTH.max, S.field_w * (kr and 1.3 or 1 / 1.3)))
            end
            sound("click")
        end
        for i, s in ipairs(SAMPLES) do
            if clicked("gh_sample" .. i) then sound("click"); load_sample(s.n); return end
        end
        if (ctrl() and pressed("Y")) or clicked("gh_redo") then
            if S.mode == "done" then stand_up() end
            if #HC.redo_ops > 0 then job("Laying dominoes", nil, function() HC.redo() end, changed) else sound("click") end
        elseif pressed("Backspace") or (ctrl() and pressed("Z")) or clicked("gh_undo") then
            if S.mode == "done" then stand_up() end
            if #HC.ops > 0 then job("Laying dominoes", nil, function() HC.undo() end, changed) else sound("click") end
        end
        if pressed("C") or pressed("Delete") or clicked("gh_clear") then
            if S.clear_t and S.clock - S.clear_t < 2.5 then
                if S.mode == "done" then stand_up() end
                add_op({ k = "clear" }, "Clearing")
                S.clear_t = nil
            else
                S.clear_t = S.clock; say("Press C again to clear the hall.", true); sound("click")
            end
        end
        if enter then tip(); return end
        local down = input.is_left_mouse_down and input.is_left_mouse_down() and not ui
        if down and not S.was_down and mx and not S.rdown and not S.mdown then tool_press(mx, my)
        elseif down and S.press and mx then tool_drag(mx, my)
        elseif not down and S.press then tool_release() end
        S.was_down = down
        if mx and S.mode ~= "running" and not ctx.SET:is_open() then
            local x, y = floor_at(mx, my)
            if x then
                local r = S.tool == "erase" and S.erase_r or (S.tool == "field" and max(0.42, S.field_w * 0.02) or 0.42)
                FW.set_cursor(x, y, 0, true, r)
            else
                FW.set_cursor(nil)
            end
        end
    end
    if mx then S.mx, S.my = mx, my end
end

------------------------------------------------------------------ per frame
local function run_job()
    if not S.job then return end
    local ok, err = coroutine.resume(S.job)
    if not ok then
        S.job = nil
        error("The Great Hall could not lay this build: " .. tostring(err))
    end
    if coroutine.status(S.job) == "dead" then
        S.job = nil
        local after = S.job_after
        S.job_after = nil
        if after then after() end
    end
end

-- One shadow map around where you are looking. From far out, where a domino is smaller than a texel, they cast none:
-- their contact shade in the shader keeps them grounded.
local function aim_shadows()
    local g = FW.goal
    local r = max(50, min(260, g.dist * 1.15))
    local casts = g.dist <= SHADOW_MAX_DIST
    if casts ~= S.casts then
        S.casts = casts
        hinge_field.set_casts_shadows(casts)
    end
    local moved = not S.sx or abs(g.x - S.sx) > r * 0.2 or abs(g.y - S.sy) > r * 0.2 or abs(r - S.sr) > S.sr * 0.15
    if moved then
        S.sx, S.sy, S.sr = g.x, g.y, r
        FW.set_shadow_bounds(g.x, 8, -g.y, r)
    end
end

function H.update(dt, real)
    S.t = S.t + dt
    S.msg_t = max(0, S.msg_t - dt)
    FW.set_time(1)
    run_job()
    if S.mode == "running" then
        S.run_t = S.run_t + (real or dt) * S.speed
        local started, x, y, width = HC.advance(S.run_t)
        hinge_field.set_clock(S.run_t)
        if started > 0 then
            S.front = S.front or { x = x, y = y }
            local k = min(1, dt * 4)
            S.front.x, S.front.y = S.front.x + (x - S.front.x) * k, S.front.y + (y - S.front.y) * k
            S.front_width = S.front_width and S.front_width + (width - S.front_width) * min(1, dt * 1.2) or width
            if S.clock - (S.last_clack or -1) > 0.04 then S.last_clack = S.clock; ctx.clack() end
            -- A little dust where they land, while you are close enough to see it.
            local scale = FW.particle_scale and FW.particle_scale() or 1
            if FW.goal.dist < 500 and scale > 0 and particles and particles.emit_burst then
                for i = 1, HC.nspots do
                    local sx0, sy0 = HC.spots[i * 2 - 1], HC.spots[i * 2]
                    pcall(particles.emit_burst, { position = vec3(sx0, 0.08, -sy0), velocity = vec3(0, 0.55, 0),
                        color_start = vec4(0.72, 0.62, 0.48, 0.32), color_end = vec4(0.72, 0.62, 0.48, 0), gravity = vec3(0, -0.5, 0),
                        count = max(1, floor(7 * scale)), size_min = 0.05, size_max = 0.16, life_min = 0.5, life_max = 1.1,
                        spawn_radius = 0.4, noise_strength = 0.7, drag = 3 })
                end
            end
        end
        if S.follow and S.front then
            local g, k = FW.goal, 1 - math.exp(-dt * 2.2)
            g.x, g.y = g.x + (S.front.x - g.x) * k, g.y + (S.front.y - g.y) * k
            -- Pull back as the wave widens, so the whole front stays in the picture.
            local want = max(34, min(1100, (S.front_width or 0) * 0.95))
            g.dist = g.dist + (want - g.dist) * (1 - math.exp(-dt * 0.8))
        end
        -- Bells the wave has reached ring, swing and throw out a gold ripple you can see from the far end of the hall.
        for i = #HC.rung, 1, -1 do
            local b = HC.rung[i]
            HC.rung[i] = nil
            sound("bell")
            if b.vis then b.vis.ring_t = 0 end
            ripples[#ripples + 1] = { x = b.x, y = b.y, t = 0 }
            if particles and particles.emit_burst and (FW.particle_scale and FW.particle_scale() or 1) > 0 then
                pcall(particles.emit_burst, { position = vec3(b.x, 4.4, -b.y), velocity = vec3(0, 1.4, 0),
                    color_start = vec4(1, 0.78, 0.32, 0.9), color_end = vec4(1, 0.6, 0.15, 0), gravity = vec3(0, -1.2, 0),
                    count = 40, size_min = 0.08, size_max = 0.22, life_min = 0.5, life_max = 1.3, spawn_radius = 0.7,
                    noise_strength = 1.2, drag = 2 })
            end
        end
        if HC.finished(S.run_t) then finish() end
    end
    for _, v in ipairs(bell_vis) do
        if v.ring_t then
            v.ring_t = v.ring_t + dt
            v.swing:set_rotation(vec3(0, 0, 20 * sin(v.ring_t * 8) * math.exp(-v.ring_t * 0.9)))
            if v.ring_t > 6 then v.ring_t = nil end
        end
    end
    for i = #ripples, 1, -1 do
        ripples[i].t = ripples[i].t + dt
        if ripples[i].t > 1.1 then table.remove(ripples, i) end
    end
    if S.save_due and S.clock >= S.save_due and not S.job then autosave() end
    aim_shadows()
    FW.update(dt, 0)
end

function H.enter()
    FW.enter_hall(WORLD)
    hinge_field.set_enabled(true)
    hinge_field.set_near_distance(NEAR_LOD)
    FW.follow = false
    FW.goal.x, FW.goal.y, FW.goal.h, FW.goal.yaw, FW.goal.pitch, FW.goal.dist = 0, 0, 0, -90, 42, 1500
    for k, v in pairs(FW.goal) do FW.cam[k] = v end
    S.sx, S.casts = nil, nil
    S.mode, S.press, S.front = "build", nil, nil
    H.flush_keys()
    if S.entered then show_starter(); sync_bells(); return end
    S.entered = true
    HC.init({ clear = hinge_field.clear, append = hinge_field.append, hide = hinge_field.hide, fall = hinge_field.fall,
        stand_all = hinge_field.stand_all, rebuild = hinge_field.rebuild,
        load_picture = function(name)
            local t = fs.read_image and fs.read_image("Pictures/" .. name, 2048)
            return t and { w = t.width, h = t.height, rgb = t.rgb } or nil
        end })
    hinge_field.stand_all()
    if HC.deserialize(fs.read(SAVE)) and #HC.ops > 0 then
        job("Laying your build", nil, function() HC.rebuild() end, changed)
    else
        load_sample(1000000)
        S.first_visit = true
    end
end

function H.leave()
    if S.save_due and not S.job then autosave() end
    S.save_due = nil
    if S.mode ~= "build" then HC.stand(); S.mode = "build" end
    hinge_field.set_enabled(false)
    still_bells()
    for _, v in ipairs(bell_vis) do FW.hide_bell(v) end
    FW.follow = true
    FW.leave_hall()
    S.press = nil
end

------------------------------------------------------------------ HUD
local function button(id, x, y, w, h, label, sub, on, accent)
    local u = ctx.u()
    local hov = hovered(id)
    panel(x, y, w, h, 51, on and { 0.34, 0.2, 0.09, 0.97 } or (hov and C.WALNUT_HI or { 0.17, 0.095, 0.05, 0.95 }), accent or (on and C.GOLD or col4(C.RIM, 0.6)), 10)
    text(label, x + w / 2, y + h * (sub and 0.4 or 0.5), 16 * u, on and C.GOLD or C.CREAM, "center", 53, w)
    if sub then text(sub, x + w / 2, y + h * 0.74, 12 * u, col4(C.BRASS, 0.85), "center", 53, w) end
    catcher(id, x, y, w, h, 62)
    hot[id] = true
end
local function nohot(id) hide(id); hot[id] = nil end

local function top_left()
    local u = ctx.u()
    panel(24 * u, 18 * u, 360 * u, 92 * u, 39, C.WALNUT, C.RIM, 14)
    text("TOPPLE", 44 * u, 50 * u, 40 * u, C.CREAM, "left", 41, 300 * u)
    text("the great hall", 46 * u, 88 * u, 15 * u, col4(C.BRASS, 0.95), "left", 41, 320 * u)
    button("gh_menu", 300 * u, 34 * u, 70 * u, 60 * u, "MENU", nil, false)
end

local function top_right()
    local u, w = ctx.u(), ctx.L.w
    local pw = 420 * u
    local x = w - pw - 24 * u
    panel(x, 18 * u, pw, 118 * u, 39, C.WALNUT, C.RIM, 14)
    text(commas(HC.count()) .. "  /  " .. commas(HC.CAP), x + pw / 2, 46 * u, 30 * u, C.CREAM, "center", 41, pw)
    text("dominoes in the hall", x + pw / 2, 74 * u, 13 * u, col4(C.BRASS, 0.9), "center", 41, pw)
    local bells = HC.bell_count()
    local line = S.mode == "running" and (commas(HC.toppled) .. " fallen" .. (bells > 0 and ("  ·  " .. HC.rung_total .. " / " .. bells .. " bells") or ""))
        or (HC.count() == 0 and "lay some dominoes" or "tip it and see how far it runs")
    text(line, x + pw / 2, 100 * u, 17 * u, C.GOLD, "center", 41, pw)
    text(best > 0 and ("best chain  " .. commas(best)) or "", x + pw / 2, 124 * u, 12 * u, col4(C.BRASS, 0.8), "center", 41, pw)
end

local function tray()
    local u, w, h = ctx.u(), ctx.L.w, ctx.L.h
    local tw, th = 1856 * u, 150 * u
    local tx, ty = (w - tw) / 2, h - th - 18 * u
    panel(tx, ty, tw, th, 50, C.WALNUT, C.RIM, 18)
    catcher("gh_tray", tx, ty, tw, th, 55); hot.gh_tray = true
    local bw, ch = 88 * u, 126 * u
    local isz = min(78 * u, bw - 8 * u)
    for i, t in ipairs(TOOLS) do
        local x, y = tx + 14 * u + (i - 1) * (bw + 8 * u), ty + 12 * u
        local sel = S.tool == t.id
        panel(x, y, bw, ch, 51, sel and { 0.34, 0.2, 0.09, 0.97 } or (hovered("gh_tool" .. i) and C.WALNUT_HI or { 0.17, 0.095, 0.05, 0.95 }), sel and C.GOLD or col4(C.RIM, 0.6), 12)
        image("Textures/icon_" .. t.icon .. ".png", x + (bw - isz) / 2, y + 4 * u, isz, isz, { 1, 1, 1, 1 }, 52)
        text(t.name, x + bw / 2, y + 100 * u, 15 * u, sel and C.GOLD or C.CREAM, "center", 53, bw)
        text(tostring(i), x + 13 * u, y + 15 * u, 14 * u, col4(C.BRASS, 0.8), "center", 53, 30 * u)
        catcher("gh_tool" .. i, x, y, bw, ch, 62); hot["gh_tool" .. i] = true
    end
    local px = tx + 14 * u + #TOOLS * (bw + 8 * u) + 6 * u
    local pw = 168 * u
    panel(px, ty + 12 * u, pw, ch, 51, { 0.15, 0.085, 0.045, 0.95 }, col4(C.RIM, 0.5), 12)
    text("PAINT  ·  P", px + pw / 2, ty + 28 * u, 13 * u, col4(C.BRASS, 0.9), "center", 53, pw)
    for i, p in ipairs(PAINTS) do
        local col, row = (i - 1) % 3, floor((i - 1) / 3)
        local r = 22 * u
        local cx, cy = px + pw / 2 + (col - 1) * 52 * u, ty + 70 * u + row * 50 * u
        if p == "rainbow" then
            for k = 1, 5 do
                local a = (k - 1) / 5 * 2 * pi
                quad(pid("ghs"), { style = "text", label = "", x = cx + cos(a) * r * 0.45 - r * 0.45, y = cy + sin(a) * r * 0.45 - r * 0.45,
                    width = r * 0.9, height = r * 0.9, z = 53, fill = SWATCH[F.PAINTS[k]], corner_radius = r * 0.45 })
            end
        else
            quad(pid("ghs"), { style = "text", label = "", x = cx - r * 0.8, y = cy - r * 0.8, width = r * 1.6, height = r * 1.6, z = 53,
                fill = SWATCH[p], border = { 0.1, 0.06, 0.03, 1 }, corner_radius = r * 0.8 })
        end
        quad(pid("ghs"), { style = "text", label = "", x = cx - r, y = cy - r, width = 2 * r, height = 2 * r, z = 54,
            fill = { 0, 0, 0, 0 }, border = S.paint == p and C.GOLD or { 0, 0, 0, 0 }, corner_radius = r })
        catcher("gh_paint" .. i, cx - r, cy - r, 2 * r, 2 * r, 62); hot["gh_paint" .. i] = true
    end
    local bx = px + pw + 10 * u
    local btw, bth = 112 * u, 59 * u
    local Row = { { "gh_undo", "UNDO", "Backspace" }, { "gh_clear", "CLEAR", "C  twice" }, { "gh_follow", "FOLLOW", S.follow and "on  ·  F" or "off  ·  F", S.follow },
        { "gh_redo", "REDO", "Ctrl Y" } }
    for i, b in ipairs(Row) do
        local col, row = (i - 1) % 3, floor((i - 1) / 3)
        button(b[1], bx + col * (btw + 8 * u), ty + 12 * u + row * (bth + 8 * u), btw, bth, b[2], b[3], b[4])
    end
    local sx = bx + 3 * (btw + 8 * u) + 4 * u
    local sw = 170 * u
    panel(sx, ty + 12 * u, sw, ch, 51, { 0.15, 0.085, 0.045, 0.95 }, col4(C.RIM, 0.5), 12)
    text("SAMPLES", sx + sw / 2, ty + 28 * u, 13 * u, col4(C.BRASS, 0.9), "center", 53, sw)
    for i, s in ipairs(SAMPLES) do
        button("gh_sample" .. i, sx + 8 * u, ty + 12 * u + 28 * u + (i - 1) * 32 * u, sw - 16 * u, 30 * u, s.label, nil, false)
    end
    local tipx = sx + sw + 10 * u
    local tipw = tx + tw - 14 * u - tipx
    local ready = HC.count() > 0
    local pulse = ready and (0.5 + 0.5 * sin(S.t * 4)) or 0
    panel(tipx, ty + 12 * u, tipw, ch, 51, ready and (hovered("gh_tip") and { 0.5, 0.3, 0.1, 0.98 } or { 0.42, 0.25, 0.09, 0.97 }) or { 0.17, 0.095, 0.05, 0.95 },
        ready and col4(C.GOLD, 0.7 + 0.3 * pulse) or col4(C.RIM, 0.5), 14)
    text(S.mode == "done" and "AGAIN" or "TIP", tipx + tipw / 2, ty + 62 * u, 38 * u, ready and C.GOLD or col4(C.CREAM, 0.4), "center", 53, tipw)
    text("Space", tipx + tipw / 2, ty + 104 * u, 14 * u, col4(C.BRASS, ready and 0.9 or 0.4), "center", 53, tipw)
    catcher("gh_tip", tipx, ty + 12 * u, tipw, ch, 62); hot.gh_tip = true

    local tool
    for _, t in ipairs(TOOLS) do if t.id == S.tool then tool = t end end
    local hint = tool.hint
    if S.tool == "field" then hint = hint .. "  (now " .. commas(floor(S.field_w)) .. " wide)" end
    if S.tool == "erase" then hint = hint .. "  (now " .. string.format("%.1f", S.erase_r) .. ")" end
    if S.tool == "split" then hint = hint .. "  (now " .. S.split_n .. ")" end
    text(hint, w / 2, ty - 22 * u, 15 * u, col4(C.CREAM, 0.9), "center", 45, 1500 * u)
    text("Right-drag turn  ·  Middle-drag or Shift+right-drag move  ·  Wheel zoom  ·  WASD move  ·  Q E turn  ·  Tab top view  ·  H hide",
        w / 2, ty - 46 * u, 13 * u, col4(C.BRASS, 0.8), "center", 45, 1500 * u)
    return tx, ty
end

local function run_bar()
    local u, w, h = ctx.u(), ctx.L.w, ctx.L.h
    local tw, th = 900 * u, 112 * u
    local tx, ty = (w - tw) / 2, h - th - 18 * u
    panel(tx, ty, tw, th, 50, C.WALNUT, C.RIM, 18)
    catcher("gh_tray", tx, ty, tw, th, 55); hot.gh_tray = true
    local done = S.mode == "done"
    text(commas(HC.toppled), tx + 150 * u, ty + 46 * u, 42 * u, C.GOLD, "center", 53, 280 * u)
    text(done and ("of " .. commas(HC.count()) .. " fell") or "fallen", tx + 150 * u, ty + 86 * u, 15 * u, col4(C.CREAM, 0.9), "center", 53, 280 * u)
    text(string.format("%.1f s", done and HC.last_t or S.run_t), tx + 340 * u, ty + 46 * u, 30 * u, C.CREAM, "center", 53, 160 * u)
    text(done and "the chain ran" or (S.speed < 1 and "slow motion" or "watch"), tx + 340 * u, ty + 86 * u, 14 * u, col4(C.BRASS, 0.9), "center", 53, 160 * u)
    local bw, bh = 120 * u, 82 * u
    local bx = tx + 430 * u
    button("gh_slow", bx, ty + 15 * u, bw, bh, "SLOW-MO", S.speed < 1 and "on  ·  Z" or "off  ·  Z", S.speed < 1)
    button("gh_follow", bx + (bw + 8 * u), ty + 15 * u, bw, bh, "FOLLOW", S.follow and "on  ·  F" or "off  ·  F", S.follow)
    button("gh_stand", bx + 2 * (bw + 8 * u), ty + 15 * u, bw, bh, "STAND UP", "R", false)
    if done then
        button("gh_tip", bx + 3 * (bw + 8 * u), ty + 15 * u, tx + tw - 14 * u - (bx + 3 * (bw + 8 * u)), bh, "AGAIN", "Space", true, C.GOLD)
    else
        nohot("gh_tip")
    end
    return tx, ty
end

local function result_card()
    local u, w, h = ctx.u(), ctx.L.w, ctx.L.h
    local cw = 620 * u
    local x = (w - cw) / 2
    panel(x, 150 * u, cw, 120 * u, 70, C.WALNUT, C.RIM, 16)
    local title = S.milestone and (commas(S.milestone) .. " IN ONE CHAIN!") or (commas(HC.toppled) .. " DOMINOES")
    text(title, w / 2, 192 * u, 36 * u, C.GOLD, "center", 71, cw)
    local sub = S.new_best and "A new best chain." or string.format("in %.1f seconds", HC.last_t)
    local bells = HC.bell_count()
    if bells > 0 then sub = sub .. "  ·  " .. (HC.rung_total == bells and "every bell rang" or (HC.rung_total .. " of " .. bells .. " bells rang")) end
    text(sub, w / 2, 240 * u, 18 * u, C.CREAM, "center", 71, cw)
end

local function shape_preview()
    local P = S.press
    if not P then return end
    local u = ctx.u()
    local pts = {}
    if P.kind == "draw" then
        for i = 1, #P.pts, 2 do pts[#pts + 1] = P.pts[i]; pts[#pts + 1] = P.pts[i + 1] end
    elseif P.kind == "split" then
        local _, _, paths = HC.splitter_paths(split_op(P))
        for _, path in ipairs(paths or {}) do
            local stride = max(1, floor(#path / 2 / 14)) * 2
            for i = 1, #path, stride do pts[#pts + 1], pts[#pts + 2] = path[i], path[i + 1] end
            pts[#pts + 1], pts[#pts + 2] = path[#path - 1], path[#path]
        end
    elseif P.kind == "picture" then
        local dx, dy = P.x1 - P.x0, P.y1 - P.y0
        local L = max(1e-6, sqrt(dx * dx + dy * dy))
        local pw, fan = HC.picture_layout(S.pic, L)
        if pw then
            local ux, uy, nx, ny = dx / L, dy / L, -dy / L, dx / L
            for i = 0, 60 do
                local s = i / 60 * L
                local hw = min(1, s / fan) * pw / 2
                for _, side in ipairs({ -1, 1 }) do
                    pts[#pts + 1], pts[#pts + 2] = P.x0 + ux * s + nx * hw * side, P.y0 + uy * s + ny * hw * side
                end
            end
            for i = 0, 24 do
                local l = (i / 24 - 0.5) * pw
                pts[#pts + 1], pts[#pts + 2] = P.x0 + ux * fan + nx * l, P.y0 + uy * fan + ny * l
                pts[#pts + 1], pts[#pts + 2] = P.x1 + nx * l, P.y1 + ny * l
            end
        end
    elseif P.kind == "line" or P.kind == "field" or P.kind == "spiral" then
        local n = 48
        if P.kind == "spiral" then
            local R = sqrt((P.x1 - P.x0) ^ 2 + (P.y1 - P.y0) ^ 2)
            local a0 = math.atan2(P.y1 - P.y0, P.x1 - P.x0)
            for i = 0, n do
                local a = a0 + i / n * 2 * pi
                pts[#pts + 1], pts[#pts + 2] = P.x0 + cos(a) * R, P.y0 + sin(a) * R
            end
        else
            local dx, dy = P.x1 - P.x0, P.y1 - P.y0
            local L = max(1e-6, sqrt(dx * dx + dy * dy))
            local px, py = -dy / L, dx / L
            local hw = P.kind == "field" and S.field_w / 2 or 0
            local fan = P.kind == "field" and min(L, S.field_w / F.FIELD_LAT * F.SPACING) or 0
            for i = 0, n do
                local t = i / n
                pts[#pts + 1], pts[#pts + 2] = P.x0 + dx * t, P.y0 + dy * t
                if hw > 0 then
                    local reach = L * t
                    local w = fan > 0 and min(1, reach / fan) * hw or hw
                    pts[#pts + 1], pts[#pts + 2] = P.x0 + dx * t + px * w, P.y0 + dy * t + py * w
                    pts[#pts + 1], pts[#pts + 2] = P.x0 + dx * t - px * w, P.y0 + dy * t - py * w
                end
            end
        end
    end
    local d = 7 * u
    for i = 1, #pts, 2 do
        local sx, sy = FW.project(pts[i], pts[i + 1], 0.1)
        if sx then rect(sx - d / 2, sy - d / 2, d, d, col4(C.GOLD, 0.85), 34, d / 2) end
    end
end

local function picture_panel(ty)
    local u, w = ctx.u(), ctx.L.w
    local tile, gap = 112 * u, 10 * u
    local shown = S.pictures or {}
    local pw = (#shown + 1) * (tile + gap) + gap
    local x, y = (w - pw) / 2, ty - 208 * u
    panel(x, y, pw, tile + 2 * gap, 50, C.WALNUT, C.RIM, 14)
    catcher("gh_pic_tray", x, y, pw, tile + 2 * gap, 55); hot.gh_pic_tray = true
    for i = 1, MAX_PICTURES do
        local name = shown[i]
        if name then
            local tx = x + gap + (i - 1) * (tile + gap)
            image("Pictures/" .. name, tx, y + gap, tile, tile, { 1, 1, 1, 1 }, 52)
            quad(pid("ghs"), { style = "text", label = "", x = tx, y = y + gap, width = tile, height = tile, z = 53, fill = { 0, 0, 0, 0 },
                border = S.pic == name and C.GOLD or col4(C.RIM, 0.6), corner_radius = 6 * u })
            catcher("gh_pic" .. i, tx, y + gap, tile, tile, 62); hot["gh_pic" .. i] = true
        else
            nohot("gh_pic" .. i)
        end
    end
    local dx = x + gap + #shown * (tile + gap)
    local mine = S.drawn and S.pic == canvas_source(S.drawn)
    panel(dx, y + gap, tile, tile, 51, mine and { 0.34, 0.2, 0.09, 0.97 } or { 0.17, 0.095, 0.05, 0.95 }, mine and C.GOLD or col4(C.RIM, 0.6), 8)
    text(S.drawn and "YOUR" or "DRAW", dx + tile / 2, y + gap + tile * 0.38, 18 * u, C.CREAM, "center", 53, tile)
    text(S.drawn and "DRAWING" or "ONE", dx + tile / 2, y + gap + tile * 0.62, 18 * u, C.CREAM, "center", 53, tile)
    catcher("gh_pic_draw", dx, y + gap, tile, tile, 62); hot.gh_pic_draw = true
end

local function canvas_draw()
    local cv = S.canvas
    local u, c, gx, gy, gw, gh = canvas_layout()
    local w, h = ctx.L.w, ctx.L.h
    rect(0, 0, w, h, { 0.02, 0.015, 0.01, 0.82 }, 88)
    catcher("gh_canvas", 0, 0, w, h, 89); hot.gh_canvas = true
    text("DRAW A PICTURE", w / 2, gy - 44 * u, 34 * u, C.CREAM, "center", 92, 900 * u)
    panel(gx - 10 * u, gy - 10 * u, gw + 20 * u, gh + 20 * u, 90, C.WALNUT, C.RIM, 10)
    local function col(i) local q = HC.DRAW_COLORS[i]; return { q[1], q[2], q[3], 1 } end
    for y = 0, CANVAS_H - 1 do
        local x = 0
        while x < CANVAS_W do
            local v = cv.cells[y * CANVAS_W + x + 1]
            local e = x + 1
            while e < CANVAS_W and cv.cells[y * CANVAS_W + e + 1] == v do e = e + 1 end
            rect(gx + x * c, gy + y * c, (e - x) * c, c, col(tonumber(v) + 1), 91)
            x = e
        end
    end
    local by = gy + gh + 30 * u
    local n = #HC.DRAW_COLORS
    for i = 1, n do
        local sx = gx + (i - 1) * 62 * u
        rect(sx, by, 52 * u, 52 * u, col(i), 92, 8 * u, cv.brush == i and C.GOLD or col4(C.RIM, 0.7))
        catcher("gh_cv_col" .. i, sx, by, 52 * u, 52 * u, 95); hot["gh_cv_col" .. i] = true
    end
    local bw, bh, right = 130 * u, 52 * u, gx + gw
    local function cbtn(id, label, x, on)
        panel(x, by, bw, bh, 92, on and { 0.42, 0.25, 0.09, 1 } or { 0.17, 0.095, 0.05, 1 }, on and C.GOLD or C.RIM, 10)
        text(label, x + bw / 2, by + bh / 2, 18 * u, on and C.GOLD or C.CREAM, "center", 93, bw)
        catcher(id, x, by, bw, bh, 95); hot[id] = true
    end
    cbtn("gh_cv_done", "USE IT", right - bw, true)
    cbtn("gh_cv_cancel", "CANCEL", right - 2 * bw - 10 * u, false)
    cbtn("gh_cv_clear", "CLEAR", right - 3 * bw - 20 * u, false)
end

local ALL_IDS = { "gh_menu", "gh_tray", "gh_tip", "gh_undo", "gh_redo", "gh_clear", "gh_follow", "gh_slow", "gh_stand",
    "gh_sample1", "gh_sample2", "gh_sample3", "gh_pic_tray", "gh_pic_draw", "gh_canvas", "gh_cv_done", "gh_cv_cancel", "gh_cv_clear" }
for i = 1, MAX_PICTURES do ALL_IDS[#ALL_IDS + 1] = "gh_pic" .. i end
for i = 1, #HC.DRAW_COLORS do ALL_IDS[#ALL_IDS + 1] = "gh_cv_col" .. i end
local PICTURE_IDS = { "gh_pic_tray", "gh_pic_draw" }
for i = 1, MAX_PICTURES do PICTURE_IDS[#PICTURE_IDS + 1] = "gh_pic" .. i end
local CANVAS_IDS = { "gh_canvas", "gh_cv_done", "gh_cv_cancel", "gh_cv_clear" }
for i = 1, #HC.DRAW_COLORS do CANVAS_IDS[#CANVAS_IDS + 1] = "gh_cv_col" .. i end
for i = 1, #TOOLS do ALL_IDS[#ALL_IDS + 1] = "gh_tool" .. i end
for i = 1, #PAINTS do ALL_IDS[#ALL_IDS + 1] = "gh_paint" .. i end
function H.hide_all() for _, id in ipairs(ALL_IDS) do nohot(id) end end

function H.draw()
    local u, w, h = ctx.u(), ctx.L.w, ctx.L.h
    for id in pairs(hot) do hot[id] = nil end
    if ctx.SET:is_open() then H.hide_all(); return end
    if not S.hud then
        H.hide_all()
        text("H  shows the controls", w - 24 * u, h - 24 * u, 13 * u, col4(C.CREAM, 0.55), "right", 45, 400 * u)
        return
    end
    top_left()
    top_right()
    for _, r in ipairs(ripples) do
        local sx, sy = FW.project(r.x, r.y, 3)
        if sx then
            local rad_px = (14 + 110 * r.t) * u
            rect(sx - rad_px, sy - rad_px, 2 * rad_px, 2 * rad_px, { 0, 0, 0, 0 }, 36, rad_px, col4(C.GOLD, max(0, 1 - r.t / 1.1)))
        end
    end
    if S.canvas then canvas_draw() else for _, id in ipairs(CANVAS_IDS) do nohot(id) end end
    local ty
    if S.mode == "build" then
        for _, id in ipairs({ "gh_slow", "gh_stand" }) do nohot(id) end
        ty = select(2, tray())
        shape_preview()
        if S.tool == "picture" then picture_panel(ty) else for _, id in ipairs(PICTURE_IDS) do nohot(id) end end
    else
        for _, id in ipairs(PICTURE_IDS) do nohot(id) end
        for i = 1, #TOOLS do nohot("gh_tool" .. i) end
        for i = 1, #PAINTS do nohot("gh_paint" .. i) end
        for _, id in ipairs({ "gh_undo", "gh_redo", "gh_clear", "gh_sample1", "gh_sample2", "gh_sample3" }) do nohot(id) end
        ty = select(2, run_bar())
        if S.mode == "done" then result_card() end
    end
    if S.msg and S.msg_t > 0 then
        text(S.msg, w / 2, ty - 76 * u, 19 * u, col4(S.msg_bad and C.BAD or C.GOLD, min(1, S.msg_t * 2)), "center", 46, 1200 * u)
    end
    if S.job then
        local cw = 640 * u
        local x = (w - cw) / 2
        panel(x, h * 0.42, cw, 96 * u, 70, C.WALNUT, C.RIM, 16)
        text((S.job_label or "Working") .. "…", w / 2, h * 0.42 + 34 * u, 24 * u, C.CREAM, "center", 71, cw)
        local frac = S.job_target and S.job_target > 0 and min(1, HC.rows() / S.job_target) or nil
        if frac then
            rect(x + 30 * u, h * 0.42 + 64 * u, cw - 60 * u, 12 * u, { 0.1, 0.06, 0.03, 1 }, 71, 6 * u)
            rect(x + 30 * u, h * 0.42 + 64 * u, (cw - 60 * u) * frac, 12 * u, C.GOLD, 72, 6 * u)
        end
    elseif S.first_visit and S.mode == "build" and S.t < 16 then
        local a = min(1, S.t * 2) * min(1, (16 - S.t) / 1.5)
        local cw = 760 * u
        panel((w - cw) / 2, 150 * u, cw, 76 * u, 70, col4(C.WALNUT, a), col4(C.RIM, a), 14)
        text("A million dominoes, ready to go: press Space to tip the first.", w / 2, 176 * u, 19 * u, col4(C.CREAM, a), "center", 71, cw)
        text("Or lay your own: fields fan out as wide as you like with [ and ].", w / 2, 204 * u, 15 * u, col4(C.BRASS, a), "center", 71, cw)
    end
end

return H
end
