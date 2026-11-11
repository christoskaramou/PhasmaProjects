-- Topple Free Build: input, tools, the HUD and the flow of a run (build, tip, watch, stand them up, replay).
-- topple_free.lua: rules. topple_free_world.lua: the room, the dominoes, the camera. topple.lua owns the screen and
-- the shared helpers (passed in ctx) and hands Free Build the frame while it is open.
return function(F, FW, ctx)
local FV = {}
local floor, min, max, abs, sin, cos, sqrt = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt
local atan2 = math.atan2 or math.atan
local C = ctx.C
local text, panel, rect, image, quad, hide, catcher = ctx.text, ctx.panel, ctx.rect, ctx.image, ctx.quad, ctx.hide, ctx.catcher
local clicked, hovered, col4, commas, sound, pid = ctx.clicked, ctx.hovered, ctx.col4, ctx.commas, ctx.sound, ctx.pid
local pressed = ctx.edge()
local Ch, MAP = ctx.Challenges, "room"
local house, HM = ctx.house, ctx.House        -- the House's progress (topple_house.lua): what is open and unlocked

local S = { room = "living", tool = "draw", paint = "rainbow", painted = 0, size = 2, grow = false, field_w = F.FIELD_WIDTH.default, erase_r = 1.2, mode = "build",
    speed = 1, t = 0, clock = 0, hud = true, msg = nil, msg_t = 0 }
FV.S = S
local board
FV.board = function() return board end

-- Saves: the living room keeps the files it always had (your build and slots); every other room has its own.
-- The longest chain and the milestones are the player's, whichever room they were set in.
local BEST, MILES, HOUSE_SAVE = "Save/free_best.txt", "Save/free_milestones.txt", "Save/house.txt"
local function room_file(kind, i, id)
    id = id or S.room
    if id == "living" then return kind == "auto" and "Save/free_autosave.txt" or ("Save/free_slot" .. i .. ".txt") end
    return "Save/room_" .. id .. (kind == "auto" and "_autosave.txt" or ("_slot" .. i .. ".txt"))
end
FV.room_file = room_file
local MILESTONES = { 100, 500, 1000, 2500, 5000 }
local best = tonumber(fs.read(BEST) or "0") or 0
local reached = {}
for n in (fs.read(MILES) or ""):gmatch("%d+") do reached[tonumber(n)] = true end

local TOOLS = {
    { id = "draw", name = "DRAW", icon = "tool_draw", hint = "Drag to lay a line of dominoes along your path. Start on a line's end to carry it on." },
    { id = "line", name = "LINE", icon = "tool_line", hint = "Press and drag: a straight line, laid when you let go. It climbs the books and steps onto the rug." },
    { id = "spiral", name = "SPIRAL", icon = "tool_spiral", hint = "Press at the middle, drag out to the size you want. Hold Shift to wind it the other way." },
    { id = "field", name = "FIELD", icon = "tool_field", hint = "Press where it starts, drag the way it runs: it fans out to its width.  [ ] width" },
    { id = "erase", name = "ERASE", icon = "tool_erase", hint = "Drag over anything you've placed to lift it away.  [ ] brush size.  Right-click removes one anywhere." },
    { id = "start", name = "START", icon = "tool_start", hint = "Click the domino the tip knocks over. Click it again to push it the other way." },
    { id = "ball", name = "BALL", icon = "tool_ball", hint = "Click to set down a light ball near a domino: the wider the gap, the harder the falling domino hits it. It rolls, drops and bounces." },
    { id = "swing", name = "SWING", icon = "tool_swing", hint = "Press where the bob swings lowest, drag the way it swings: it hangs pulled back, and a hit on the red latch lets it go. By the bookshelf it hangs from the top." },
    { id = "switch", name = "SWITCH", icon = "tool_switch", hint = "Click to set a switch, then click the domino it starts (again: the other way). Click a switch to choose it; click it again for the lamp." },
    { id = "ramp", name = "RAMP", icon = "tool_ramp", hint = "Press on one surface and drag onto a higher one, in a straight line: a flight of steps up to its edge. Dominoes climb it; balls roll down it." },
}
local PAINTS = { "rainbow", "brick", "mustard", "sage", "navy", "cream" }
local SWATCH = { brick = { 0.66, 0.27, 0.17, 1 }, mustard = { 0.86, 0.64, 0.24, 1 }, sage = { 0.52, 0.62, 0.47, 1 },
    navy = { 0.2, 0.26, 0.42, 1 }, cream = { 0.92, 0.87, 0.75, 1 } }
FV.KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "Space", "Return", "R", "Z", "F", "H", "C", "P", "Tab", "Home", "Backspace", "Y",
    "[", "]", "Delete", "-", "=", "G" }

------------------------------------------------------------------ helpers
local function say(s, bad) S.msg, S.msg_t, S.msg_bad = s, 2.2, bad end
local function paint_fn()
    if S.paint == "rainbow" then
        local base = S.painted
        return function(i, s)
            if s and s.row then return F.field_paint(i, s) end       -- fields: diagonal bands of colour
            return F.PAINTS[floor((base + i - 1) / 6) % 5 + 1]
        end
    end
    local p = S.paint
    return function() return p end
end
-- The size the tools lay (a challenge keeps to Standard, so its budget means what it says), and with GROW on, the size
-- a stroke starts at before it steps toward that: the last domino's when it carries a line on, else the far end of
-- the scale.
-- What the player may use here: in a challenge what it allows (never START: its first domino is fixed); in Free Build
-- what the House has unlocked so far. ERASE always.
local function tool_ok(id)
    if id == "erase" then return true end
    if S.ch then return id ~= "start" and Ch.allows(board or S.ch, id) end
    return house:tool_open(id)
end
local function size_ok(i)
    if S.ch then return Ch.allows_size(board or S.ch, i) end
    return house:size_open(i)
end
FV.tool_ok, FV.size_ok = tool_ok, size_ok
-- A size that is allowed: the one chosen if it is, else Standard, else the nearest allowed.
local function fit_size()
    if size_ok(S.size) then return end
    if size_ok(2) then S.size = 2; return end
    for d = 1, #F.SIZES do
        for _, i in ipairs({ S.size - d, S.size + d }) do if F.SIZES[i] and size_ok(i) then S.size = i; return end end
    end
end
local function fit_tool()
    if tool_ok(S.tool) then return end
    for _, id in ipairs({ "draw", "line", "field", "spiral", "ramp", "ball", "switch", "swing" }) do
        if tool_ok(id) then S.tool = id; return end
    end
    S.tool = "erase"
end
local function cur_size() return F.SIZES[S.size] end
local function growing() return S.grow and tool_ok("grow") end
local function grow_start(from)
    if not growing() then return cur_size() end
    return from or (cur_size() > 1 and F.SIZES[1] or 1)
end
local function locked_by(r, what)
    return r and ("Clear level 1 in the " .. r.name .. " to unlock " .. what .. ".") or (what .. " isn't in this house yet.")
end
local function set_size(i)
    i = max(1, min(#F.SIZES, i))
    if not size_ok(i) then
        if S.ch then say("This challenge doesn't use " .. F.SIZE_NAMES[i] .. " dominoes.", true)
        else say(locked_by(HM.size_unlocker(i), F.SIZE_NAMES[i] .. " dominoes"), true) end
        return
    end
    S.size = i
    say(F.SIZE_NAMES[i] .. ": a domino tips one up to " .. F.KNOCK .. "x its size, so step up a size at a time.")
end
local DENY = { crowded = "Too close to another domino.", furniture = "Something's in the way.", air = "Nothing to stand it on there.",
    flat = "A ramp goes between two heights: drag onto a higher surface.", steep = "Too steep: start it further away.",
    full = "That's every domino in the box (" .. F.CAP .. ").", wait = nil,
    zone = "Nothing can go there: the red outline is out of bounds in this challenge.",
    trap = "That's part of a trap: build around it.",
    support = "Only the challenge's own dominoes stand on that stack." }
-- A refused placement: say why, and light up the no-build zone it hit.
local function deny(why, x, y)
    if why == "zone" then FW.flash_zone(x, y) end
    if DENY[why] then say(DENY[why], true) end
end
FV.deny = deny

local function deny_gadget(why, noun, cap, x, y)
    if why == "full" and S.ch then say("That's your whole budget for this challenge.", true); return end
    if why == "zone" then FW.flash_zone(x, y) end
    say(why == "full" and ("That's every " .. noun .. " in the box (" .. cap .. ").") or why == "crowded" and "Too close to something."
        or DENY[why], true)
end
-- A challenge's own pieces (its first domino, its goal, its preset dominoes) cannot be removed: say so.
local function protected_at(x, y, h, r)
    if not S.ch then return false end
    local q = board:pick(x, y, h, r)
    if not (q and q.fixed) then return false end
    say(q.preset and "Those dominoes are the challenge's: they stay where they are." or "The challenge's first domino stays put.", true)
    return true
end

-- Each room's goal has its own sound (the old living-room challenges by their goal).
local GOAL_SOUND = { hall = "goal_doorbell", living = "goal_tv", kitchen = "goal_toaster", dining = "goal_record", kids = "goal_train",
    bath = "goal_musicbox", study = "goal_dictionary", attic = "goal_lights", doorbell = "goal_doorbell", tv = "goal_tv", toaster = "goal_toaster" }
local function goal_sound(fired)
    local def = S.ch or {}
    return GOAL_SOUND[def.goal_sound or ""] or GOAL_SOUND[fired] or GOAL_SOUND[def.room or S.room] or "goal_doorbell"
end
FV.goal_sound = function(f) return goal_sound(f) end

local function changed()
    FW.sync(board)
    S.pred_due = S.clock + 0.2
    S.save_due = S.clock + 2.0
    S.gaps = nil
    FW.set_starter(board:starter())
end

local function save_to(path)
    local ok, wrote = pcall(fs.write, path, F.serialize(board))
    return ok and wrote
end
local function autosave()
    if S.ch then return end      -- a challenge's board is not your room
    if not save_to(room_file("auto")) then say("Couldn't autosave the room.", true) end
end

local function stand_up()
    if S.mode == "build" then return end
    FW.stand_all()
    S.mode = "build"
    FW.set_starter(board:starter())
end

local function load_board(b)
    board = b
    FW.clear()
    FW.sync(board, true)
    S.mode, S.res, S.gaps, S.pred = "build", nil, nil, nil
    changed()
    S.save_due = nil
end

-- Each room's own build for the session (read from its autosave the first time it is opened).
local boards = {}
FV.boards = boards
-- Make room id the one the rules and the world use (it must be loaded: ctx.load_room gives nil for a room not made yet).
local function use_room(id)
    local room = ctx.load_room(id)
    if not room then return false end
    if F.ROOM ~= room then F.set_room(room) end
    FW.set_room(room)
    S.room = id
    return true
end
FV.use_room = use_room

local function room_board()
    local b = boards[S.room]
    if not b then
        local ok
        b, ok = F.deserialize(fs.read(room_file("auto")))
        if not ok then
            b = F.new_board()
            if S.room == "living" then b = F.demo(b); S.first_visit = true end      -- (the sample is built for the living room)
        end
        boards[S.room] = b
    end
    return b
end

-- Open Free Build in a room (default: the last one), or straight into a challenge (def: its room is used). False if
-- that room isn't made yet.
function FV.enter(room_id, def)
    if not use_room(def and def.room or room_id or S.room) then return false end
    FW.enter()
    S.ch, S.ch_result = nil, nil
    board = room_board()
    if def then
        FV.start_challenge(def)
    else
        load_board(board)
        S.painted = board.count
        FW.reset_camera()
    end
    fit_tool(); fit_size()
    S.mode = "build"
    FV.flush_keys()        -- the Enter that opened Free Build is still down: it must not count as a tip
    return true
end

function FV.leave()
    if S.ch then FV.end_challenge()
    elseif board and S.save_due then autosave() end
    S.save_due = nil
    FW.leave()
    S.panel = nil
end

------------------------------------------------------------------ a run
------------------------------------------------------------------ House Challenges
-- Your room's build waits while you play; each challenge's board is kept for the session (ponytail: not saved between
-- launches, only the stars are; save it through F.serialize if losing it annoys).
S.ch_boards = {}
FV.Ch = Ch
function FV.start_challenge(def)
    if def.room and def.room ~= S.room then
        if S.ch then FV.end_challenge() elseif S.save_due then autosave(); S.save_due = nil end
        if not use_room(def.room) then return false end
        board = room_board()
    end
    if not S.ch then
        if S.save_due then autosave(); S.save_due = nil end
        S.free_board = board
    end
    if S.mode ~= "build" then FW.stand_all() end
    S.ch_boards[def.id] = S.ch_boards[def.id] or Ch.new_board(def)
    S.ch, S.ch_result, S.press, S.switch_sel, S.panel = def, nil, nil, nil, nil
    if S.tool == "start" then S.tool = "draw" end
    load_board(S.ch_boards[def.id])
    S.painted = board.count
    FW.show_challenge(def)
    local c = def.camera
    if c then for k, v in pairs({ x = c.x, y = c.y, h = c.h, yaw = c.yaw, pitch = c.pitch, dist = c.dist }) do FW.goal[k] = v end
    else FW.reset_camera() end
    if S.tool == "erase" or S.tool == "start" then S.tool = "draw" end      -- (a challenge starts with a tool that lays dominoes)
    fit_tool(); fit_size()
    return true
end

function FV.end_challenge()
    if not S.ch then return end
    if S.mode ~= "build" then FW.stand_all() end
    S.ch, S.ch_result, S.press, S.switch_sel = nil, nil, nil, nil
    FW.show_challenge(nil)
    load_board(S.free_board)
    S.free_board, S.save_due, S.painted = nil, nil, board.count
    FW.reset_camera()
    fit_tool(); fit_size()
end

local function tip()
    if S.mode == "running" then return end
    if S.mode == "done" then FW.stand_all() end
    local st = board:starter()
    if not st then say("Lay some dominoes first.", true); sound("click"); return end
    -- Balls and swings move as real bodies when the engine's physics is running; the dominoes stay calculated.
    S.run = FW.can_live() and F.begin_run(board, FW.hooks()) or nil
    if S.run then
        S.res = S.run.res
    else
        S.res = F.simulate(board)
        S.pred = S.res
    end
    S.fallen, S.clack_n = 0, 0
    FW.set_starter(nil)
    FW.set_cursor(nil)
    FW.play(S.res, S.run)
    S.mode, S.speed, S.panel = "running", 1, nil
    S.cam_before = { x = FW.goal.x, y = FW.goal.y, h = FW.goal.h, dist = FW.goal.dist }
    if FW.follow then FW.look_at(st.x, st.y, st.z, math.min(FW.goal.dist, 60)) end
    sound("tip")
end
FV.tip = tip

local function report_run(stars)
    local res, switches = S.res, 0
    for _, e in ipairs(res.switches) do if e.id ~= board.goal_id then switches = switches + 1 end end
    local line = ctx.report_run({ own = board.sample_rev ~= board.rev, fallen = res.toppled, total = res.total, duration = res.duration,
        balls = res.balls_launched, swings = res.swings_released, switches = switches, ramp = board.ramp_count > 0, stars = stars })
    if line then say(line); S.msg_t = 4.5 end
end

local function finish()
    local res = S.res
    S.mode, S.done_t = "done", 0
    S.gaps = res.gaps
    S.new_best, S.milestone = false, nil
    if S.ch then
        -- The level is done only if the chain began at Start and the End fell last (C.requirement); each of its
        -- challenges met in such a run is a star, kept once earned. held: what the House had before this run.
        local used, list = Ch.used(board), S.ch.challenges
        local done, won, run = Ch.evaluate(board, res)
        local now, held, pops = {}, {}, {}
        for _, id in ipairs(done) do now[id] = true end
        for _, c in ipairs(list or {}) do
            held[c.id] = house:done(S.ch.id, c.id)
            if now[c.id] then pops[#pops + 1] = c.id end
        end
        local stars = list and #done or Ch.stars(S.ch, used, won)
        local better, news = house:record(S.ch.id, list and { met = won, done = done } or stars, used)
        S.ch_result = { won = won, why = run.why, stars = stars, used = used, better = better, news = news, now = now, held = held, pops = pops, popped = 0 }
        if better then
            local ok, wrote = pcall(fs.write, HOUSE_SAVE, house:dump())
            if not (ok and wrote) then say("Couldn't save your stars.", true) end
        end
        if won then sound("cheer") end
        report_run(stars)
        if news then sound("unlock") end
        return
    end
    if res.toppled > best then
        best = res.toppled
        S.new_best = true
        pcall(fs.write, BEST, tostring(best))
    end
    for _, m in ipairs(MILESTONES) do
        if res.toppled >= m and not reached[m] then reached[m] = true; S.milestone = m end
    end
    if S.milestone then
        local t = {}
        for m in pairs(reached) do t[#t + 1] = tostring(m) end
        pcall(fs.write, MILES, table.concat(t, " "))
        sound("cheer")
    elseif res.toppled == res.total and res.total >= 20 then
        sound("cheer")
    end
    report_run(0)
end

------------------------------------------------------------------ input
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
local function key(k) return input.is_key_down_raw(k) end
local function shift() return key("Left Shift") or key("Right Shift") end
local function ctrl() return key("Left Ctrl") or key("Right Ctrl") end

local hot = {}       -- interactive widgets drawn last frame (the mouse over one belongs to the HUD)
local function over_ui()
    for id in pairs(hot) do if hovered(id) then return true end end
    return false
end

local function select_tool(id)
    if S.ch and id == "start" then say("A challenge's first domino is fixed.", true); sound("click"); return end
    if not tool_ok(id) then
        sound("click")
        if S.ch then say("This challenge doesn't use that tool.", true)
        else say(locked_by(HM.unlocker(id), id:upper()), true) end
        return
    end
    if S.tool ~= id then S.tool = id; S.switch_sel = nil; sound("click") end
    S.press = nil
end

local function undo()
    if board:undo() then sound("remove"); changed() else sound("click") end
end
local function redo()
    if board:redo() then sound("place"); changed() else sound("click") end
end

local function commit(placed_kind)
    if board:end_action() then
        changed()
        if placed_kind then sound(placed_kind) end
        return true
    end
    return false
end

-- The tools' press / drag / release.
local function tool_press(mx, my)
    local x, y, h, s = FW.pick(mx, my)
    if not x then
        say(s and ("The " .. s.name .. " is in the way.") or "Point at the floor, the rug, the table or the books.", true)
        return
    end
    if S.mode == "done" then stand_up() end
    local t = S.tool
    if t == "draw" then
        board:begin_action()
        local e = board:pick(x, y, h, 0.55)
        S.press = { kind = "draw", lx = x, ly = y, lz = h, started = false, n = 0, paint = paint_fn(), to = cur_size(), grow = growing() }
        if e then S.press.lx, S.press.ly, S.press.lz, S.press.started, S.press.last_s = e.x, e.y, e.z, true, e.s end
        S.press.first_s = grow_start(e and e.s)
    elseif t == "line" or t == "spiral" or t == "field" then
        S.press = { kind = t, x0 = x, y0 = y, h0 = h, x1 = x, y1 = y }
    elseif t == "erase" then
        board:begin_action()
        S.press = { kind = "erase", h0 = h }
        if board:erase_at(x, y, h, S.erase_r) == 0 then protected_at(x, y, h, S.erase_r) end
        FW.sync(board)
    elseif t == "start" then
        local p = board:pick(x, y, h, 0.6)
        if p then
            board:begin_action(); board:set_start(p.id); commit("place")
            local _, dir = board:starter()
            say(dir > 0 and "Start set: it falls the way it faces." or "Start turned round: it falls the other way.")
        else
            say("Click a domino to start the chain there.", true)
        end
    elseif t == "ball" then
        board:begin_action()
        local p, why = board:place_ball(x, y, h)
        commit(p and "place" or nil)
        if not p then deny_gadget(why, "ball", F.BALL.cap, x, y) end
    elseif t == "swing" then
        S.press = { kind = "swing", x0 = x, y0 = y, h0 = h, x1 = x, y1 = y }
    elseif t == "ramp" then
        S.press = { kind = "ramp", x0 = x, y0 = y, h0 = h, x1 = x, y1 = y, h1 = h }
    elseif t == "switch" then
        local sel = S.switch_sel and board.switches[S.switch_sel]
        local sw = board:pick_switch(x, y, h)
        if sw and sw == sel then
            board:begin_action(); board:set_switch_lamp(sw, not sw.lamp); commit("place")
            say(sw.lamp and "This switch also works the lamp." or "This switch leaves the lamp alone.")
        elseif sw then
            S.switch_sel = sw.id
            say("Switch chosen: click the domino it starts, or click it again for the lamp.")
        elseif sel then
            local p = board:pick(x, y, h, 0.6)
            S.switch_sel = nil
            if p then
                board:begin_action(); board:link_switch(sel, p.id); commit("place")
                say(sel.dir > 0 and "Linked: it starts that domino the way it faces." or "Linked: it starts that domino the other way.")
            end
        else
            board:begin_action()
            local p, why = board:place_switch(x, y, h)
            commit(p and "place" or nil)
            if p then S.switch_sel = p.id; say("Now click the domino this switch starts.")
            else deny_gadget(why, "switch", F.SWITCH.cap, x, y) end
        end
    end
end

local function tool_drag(mx, my)
    local P = S.press
    if not P then return end
    if P.kind == "draw" then
        local cx, cy = FW.plane_point(mx, my, P.lz)
        if not cx then return end
        if not P.started then
            if sqrt((cx - P.lx) ^ 2 + (cy - P.ly) ^ 2) >= F.SPACING * 0.5 then
                local a = atan2(cy - P.ly, cx - P.lx)
                local p, why = board:place(P.lx, P.ly, a, P.lz, P.paint(P.n + 1), P.first_s)
                P.started = true
                if p then P.n = P.n + 1; P.last_s = p.s; sound("place") else deny(why, P.lx, P.ly) end
            end
        end
        if P.started then
            for _ = 1, 24 do
                local from = P.last_s or P.first_s
                local nxt = P.grow and F.grow_size(from, P.to) or P.to
                local p, why, gx, gy = board:stroke_step(P.lx, P.ly, P.lz, cx, cy, P.paint(P.n + 1), nxt, from)
                if p then
                    P.lx, P.ly, P.lz, P.n, P.last_s = p.x, p.y, p.z, P.n + 1, p.s
                    if S.clock - (S.last_place or 0) > 0.05 then sound("place"); S.last_place = S.clock end
                elseif gx then
                    P.lx, P.ly = gx, gy
                    deny(why, gx, gy)
                else
                    break
                end
            end
            FW.sync(board)
        end
    elseif P.kind == "ramp" then
        local x, y, h = FW.pick(mx, my)
        if x then P.x1, P.y1, P.h1 = x, y, h end
    elseif P.kind == "erase" then
        local x, y, h = FW.pick(mx, my)
        if x and board:erase_at(x, y, h, S.erase_r) > 0 then
            FW.sync(board)
            if S.clock - (S.last_place or 0) > 0.06 then sound("remove"); S.last_place = S.clock end
        elseif x then
            protected_at(x, y, h, S.erase_r)
        end
    else
        local x, y = FW.plane_point(mx, my, P.h0)
        if x then P.x1, P.y1 = x, y end
    end
end

-- Where a preview stands: the height the rules will really set the piece at (Board:rest: a thin mat or rug under it is
-- stood on), with the clearance each placer asks for. A line dragged from the floor across the kids' play mat showed
-- its dots at the floor while the rules stood them on the mat.
local REST_CLEAR = { ball = function() return 2 * F.BALL.r end, switch = function() return 2 * F.SWITCH.r end,
    swing = function() return F.SWING.post end }
function FV.rest_h(x, y, h, kind, k)
    local c = REST_CLEAR[kind]
    return board:rest(x, y, h, c and c() or F.DOM.h * (k or 1))
end
local function shape_spots(P)
    local k = cur_size()
    if P.kind == "line" then return F.line_spots(P.x0, P.y0, P.x1, P.y1, growing() and (k + grow_start()) / 2 or k)
    elseif P.kind == "spiral" then return F.spiral_spots(P.x0, P.y0, P.x1, P.y1, shift(), k)
    elseif P.kind == "field" then return F.field_spots(P.x0, P.y0, P.x1, P.y1, S.field_w * max(1, k), k)
    elseif P.kind == "swing" then return F.swing_spots(P.x0, P.y0, P.x1, P.y1, P.h0)
    elseif P.kind == "ramp" then
        local fit = board:fit_ramp(P.x0, P.y0, P.h0, P.x1, P.y1, P.h1)
        return fit and F.ramp_spots(fit) or {}
    end
    return {}
end

local function tool_release()
    local P = S.press
    S.press = nil
    if not P then return end
    if P.kind == "draw" then
        if not P.started then
            -- A click: one domino, facing away from the camera.
            local a = math.rad(FW.goal.yaw) + math.pi
            local p, why = board:place(P.lx, P.ly, a, P.lz, P.paint(1), P.to)
            if p then P.n = 1 else deny(why, P.lx, P.ly) end
        end
        S.painted = S.painted + P.n
        commit("place")
    elseif P.kind == "erase" then
        commit("remove")
    elseif P.kind == "ramp" then
        board:begin_action()
        local p, why = board:place_ramp(P.x0, P.y0, P.h0, P.x1, P.y1, P.h1)
        commit(p and "place" or nil)
        if p then say("Ramp built: " .. p.n .. " steps.") else deny_gadget(why, "ramp", F.RAMP.cap, P.x0, P.y0) end
    elseif P.kind == "swing" then
        -- A click with no drag swings it away from the camera, like a clicked domino.
        local drag = sqrt((P.x1 - P.x0) ^ 2 + (P.y1 - P.y0) ^ 2) >= 0.5
        local a = drag and atan2(P.y1 - P.y0, P.x1 - P.x0) or math.rad(FW.goal.yaw) + math.pi
        board:begin_action()
        local p, why = board:place_swing(P.x0, P.y0, P.h0, a)
        commit(p and "place" or nil)
        if not p then deny_gadget(why, "swing", F.SWING.cap, P.x0, P.y0) end
    else
        local len = sqrt((P.x1 - P.x0) ^ 2 + (P.y1 - P.y0) ^ 2)
        if len < 0.5 and P.kind ~= "line" then say(P.kind == "spiral" and "Drag out from the middle to size the spiral." or "Drag the way the field should run.", true); return end
        board:begin_action()
        local paint = paint_fn()
        local n, why
        if P.kind == "line" then n, why = board:place_line(P.x0, P.y0, P.x1, P.y1, paint, P.h0, grow_start(), growing() and cur_size() or nil)
        else n = board:place_spots(shape_spots(P), paint, P.h0) end
        S.painted = S.painted + (n or 0)
        if commit("place") then
            say(commas(n) .. (n == 1 and " domino" or " dominoes") .. " laid.")
        else deny(why, (P.x0 + P.x1) / 2, (P.y0 + P.y1) / 2) end
    end
end

-- Mouse and keys for the camera, in any mode.
local function camera_input(dt, mx, my, ui)
    local rd, md = input.is_right_mouse_down and input.is_right_mouse_down(), input.is_middle_mouse_down and input.is_middle_mouse_down()
    local ok, wh = pcall(input.get_mouse_wheel)
    if ok and wh and wh.y and wh.y ~= 0 and not ui then FW.zoom(wh.y) end
    if mx and S.mx then
        local dx, dy = mx - S.mx, my - S.my
        if rd and S.rdown then
            S.rmove = (S.rmove or 0) + abs(dx) + abs(dy)
            if S.rmove > 4 then
                if shift() then FW.pan(-dx, dy) else FW.orbit(dx, dy) end
            end
        end
        if md and S.mdown then FW.pan(-dx, dy) end
    end
    -- A right-click that did not drag removes the domino under the cursor.
    if S.rdown and not rd and (S.rmove or 0) <= 4 and mx and S.mode ~= "running" then
        local x, y, h = FW.pick(mx, my)
        local p = x and (board:pick(x, y, h, 0.5) or board:pick_ball(x, y, h) or board:pick_swing(x, y, h) or board:pick_switch(x, y, h) or board:pick_ramp(x, y, h))
        if p and p.fixed then
            say(p.preset and "Those dominoes are the challenge's: they stay where they are." or p.goal and "The goal stays put." or "The challenge's first domino stays put.", true)
            sound("click")
        elseif p then
            if S.mode == "done" then stand_up() end
            board:begin_action(); board:remove(p.id); commit("remove")
        end
    end
    if rd and not S.rdown then S.rmove = 0 end
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
    if pressed("Home") then FW.reset_camera(); S.top = false; sound("click") end
end

function FV.flush_keys() for _, k in ipairs(FV.KEYS) do pressed(k) end end
-- Esc or a BACK / CLOSE: up one level. The save or load panel closes; a finished run's result card closes (the dominoes
-- stand up, nothing is tipped or counted). False when nothing is open here (the game then opens its pause card).
function FV.back()
    if S.panel then S.panel, S.slots = nil, nil; return true end
    if S.mode == "done" then stand_up(); return true end
    return false
end

function FV.controls(dt)
    S.clock = S.clock + dt
    local ui = over_ui()
    local mx, my = raw_mouse()
    if ui then mx, my = S.mx, S.my end
    camera_input(dt, (not ui) and mx or nil, my, ui)
    if pressed("H") then S.hud = not S.hud; sound("click") end
    if pressed("F") or clicked("fb_follow") then FW.follow = not FW.follow; sound("click"); say(FW.follow and "The camera follows the chain." or "The camera stays put.") end
    local zkey = pressed("Z")
    local undo_key = zkey and ctrl()
    if (zkey and not undo_key) or clicked("fb_slow") then S.speed = S.speed < 1 and 1 or 0.25; sound("click") end
    if clicked("fb_menu") then sound("click"); ctx.back_to_menu(); return end
    if S.mode ~= "running" and clicked("fb_ch") then
        -- The House map: from a challenge, at that room's tiers; from Free Build, at the map.
        sound("click"); ctx.open_house("challenge", S.ch and S.room or nil); return
    end

    if S.mode == "done" and clicked("fb_res_close") then sound("click"); FV.back(); return end
    if S.mode == "running" then
        if pressed("R") or clicked("fb_stand") then stand_up(); sound("remove") end
        if pressed("Space") or pressed("Return") then stand_up() end
    else
        local enter = pressed("Space") or pressed("Return") or clicked("fb_tip")
        if S.mode == "done" and (pressed("R") or clicked("fb_stand")) then stand_up(); sound("remove") end
        for i, t in ipairs(TOOLS) do
            if pressed(i == 10 and "0" or tostring(i)) or clicked("fb_tool" .. i) then select_tool(t.id) end
        end
        for i, p in ipairs(PAINTS) do
            if clicked("fb_paint" .. i) then S.paint = p; sound("click") end
        end
        if pressed("P") then
            for i, p in ipairs(PAINTS) do if p == S.paint then S.paint = PAINTS[i % #PAINTS + 1]; break end end
            sound("click")
        end
        for i = 1, #F.SIZES do if clicked("fb_size" .. i) then set_size(i); sound("click") end end
        for _, kd in ipairs({ { "-", -1 }, { "=", 1 } }) do
            if pressed(kd[1]) then
                local j = S.size + kd[2]               -- (to the next size you may use that way)
                while F.SIZES[j] and not size_ok(j) do j = j + kd[2] end
                set_size(F.SIZES[j] and j or S.size + kd[2]); sound("click")
            end
        end
        if pressed("G") or clicked("fb_grow") then
            sound("click")
            if not tool_ok("grow") then
                say(S.ch and "This challenge doesn't use GROW." or locked_by(HM.unlocker("grow"), "GROW"), true)
            else
                S.grow = not S.grow
                say(S.grow and "Grow: each domino a step bigger (or smaller) than the last, until it reaches the size you chose." or "Grow off: every domino the size you chose.")
            end
        end
        local kl, kr = pressed("["), pressed("]")
        if kl or kr then
            local d = kr and 1 or -1
            if S.tool == "erase" then S.erase_r = max(0.5, min(4, S.erase_r + d * 0.3))
            else S.field_w = max(F.FIELD_WIDTH.min, min(F.FIELD_WIDTH.max, S.field_w + d * 1.2)) end
            sound("click")
        end
        if (ctrl() and pressed("Y")) or clicked("fb_redo") then if S.mode == "done" then stand_up() end; redo()
        elseif pressed("Backspace") or undo_key or clicked("fb_undo") then if S.mode == "done" then stand_up() end; undo() end
        if pressed("C") or pressed("Delete") or clicked("fb_clear") then
            if S.clear_t and S.clock - S.clear_t < 2.5 then
                if S.mode == "done" then stand_up() end
                board:clear(); changed(); sound("remove"); S.clear_t = nil
                say("Cleared. Backspace brings it all back.")
            else
                S.clear_t = S.clock; say("Press C again to clear the room.", true); sound("click")
            end
        end
        if S.ch and (clicked("fb_save") or clicked("fb_load")) then say("Saves are for your own room, not challenges.", true); sound("click") end
        if not S.ch and clicked("fb_save") then S.panel = S.panel == "save" and nil or "save"; S.slots = nil; sound("click") end
        if not S.ch and clicked("fb_load") then S.panel = S.panel == "load" and nil or "load"; S.slots = nil; sound("click") end
        if S.panel and clicked("fb_slot_back") then sound("click"); FV.back() end
        if S.panel then
            for i = 1, 4 do
                if clicked("fb_slot" .. i) then
                    sound("click")
                    if S.panel == "save" and i <= 3 then
                        if save_to(room_file("slot", i)) then say("Saved to slot " .. i .. ".")
                        else say("Couldn't save to slot " .. i .. ".", true) end
                    elseif S.panel == "load" then
                        local b, ok
                        if i == 4 then
                            if S.room == "living" then b, ok = F.demo(F.new_board()), true end
                        else b, ok = F.deserialize(fs.read(room_file("slot", i))) end
                        if ok then
                            if S.mode ~= "build" then stand_up() end
                            board = b; boards[S.room] = b
                            load_board(b); S.save_due = S.clock + 0.5; S.painted = b.count
                            say(i == 4 and "The sample build." or ("Loaded slot " .. i .. "."))
                        else say("That slot is empty.", true) end
                    end
                    S.panel = nil
                end
            end
        end
        if enter then tip(); return end
        -- The tools, on the room (not over the HUD, not while the right or middle button turns the camera).
        local down = input.is_left_mouse_down and input.is_left_mouse_down() and not ui
        if down and not S.was_down and mx and not S.rdown and not S.mdown then S.panel = nil; tool_press(mx, my)
        elseif down and S.press and mx then tool_drag(mx, my)
        elseif not down and S.press then tool_release() end
        S.was_down = down
        -- The cursor ring: where the tool would act.
        if mx and not S.press and S.mode ~= "running" and not ctx.SET:is_open() then
            local x, y, h = FW.pick(mx, my)
            if x then
                local okp, r = true, 0.42
                if S.tool == "erase" then r = S.erase_r
                elseif S.tool == "start" then
                    local p = board:pick(x, y, h, 0.6)
                    okp = p ~= nil
                    if p then x, y, h = p.x, p.y, p.z end
                elseif S.tool == "ball" then
                    okp = board:can_place_ball(x, y, h)
                elseif S.tool == "swing" then
                    r = F.SWING.r
                    okp = board:can_place_swing(x, y, h, math.rad(FW.goal.yaw) + math.pi)
                elseif S.tool == "switch" then
                    local sel = S.switch_sel and board.switches[S.switch_sel]
                    okp = board:pick_switch(x, y, h) ~= nil or (sel and board:pick(x, y, h, 0.6) ~= nil) or (not sel and board:can_place_switch(x, y, h))
                else
                    local k = (S.tool == "draw" or S.tool == "line") and grow_start() or cur_size()
                    okp = board:can_place(x, y, h, math.rad(FW.goal.yaw) + math.pi, k)
                    r = 0.42 * k
                end
                if S.tool ~= "erase" and S.tool ~= "start" then h = FV.rest_h(x, y, h, S.tool, r / 0.42) end
                FW.set_cursor(x, y, h, okp, r)
                S.cursor = { x = x, y = y, h = h }
            else
                FW.set_cursor(nil); S.cursor = nil
            end
        elseif S.press and S.press.kind == "erase" and mx then
            local x, y, h = FW.pick(mx, my)
            if x then FW.set_cursor(x, y, h, true, S.erase_r) end
        elseif not S.press then
            FW.set_cursor(nil); S.cursor = nil
        end
    end
    if mx then S.mx, S.my = mx, my end
end

------------------------------------------------------------------ per frame
local CLACK_GAP = 0.016
-- real: the time that actually passed this frame; a run's clock follows it, so frame rate never slows the chain.
function FV.update(dt, real)
    S.t = S.t + dt
    S.msg_t = max(0, S.msg_t - dt)
    FW.set_time(S.mode == "running" and S.speed or 1)
    if S.done_t then S.done_t = S.done_t + dt end
    local R_ = S.ch_result
    if S.mode == "done" and R_ and R_.pops and R_.popped < #R_.pops and S.done_t >= FV.STAR_T0 + FV.STAR_DT * R_.popped then
        R_.popped = R_.popped + 1          -- (this run's stars come in one by one, each with a coin)
        sound("coin")
    end
    local due = FW.update(dt, S.mode == "running" and (real or dt) * S.speed or 0)
    if S.mode == "running" then
        S.fallen = (S.fallen or 0) + #due
        if FW.take_bump() then ctx.clack() end
        local thud = FW.take_thud()
        if thud and S.clock - (S.last_thud or 0) > 0.07 then
            S.last_thud = S.clock
            sound(thud >= 2 and "house" or "thunk")
        end
        for _, c in ipairs(FW.take_cues()) do sound(c) end
        local fired = FW.take_goal()
        if fired then sound(goal_sound(fired)); FW.shake(0.25) end
        if #due > 0 and S.clock - (S.last_clack or 0) > CLACK_GAP / max(0.25, S.speed) then
            S.last_clack = S.clock
            ctx.clack()
        end
        if not FW.playing() then finish() end
    end
    -- The preview and the autosave wait until the build has been still for a moment.
    if S.mode == "build" and S.pred_due and S.clock >= S.pred_due and not S.press then
        S.pred_due = nil
        S.pred = F.simulate(board)
    end
    if S.save_due and S.clock >= S.save_due and S.mode ~= "running" and not S.press then
        S.save_due = nil
        autosave()
    end
end

------------------------------------------------------------------ HUD
local function button(id, x, y, w, h, label, sub, on, accent, z)
    local u = ctx.u()
    local hov = hovered(id)
    z = z or 51                -- (a card's own button sits over the card)
    panel(x, y, w, h, z, on and { 0.34, 0.2, 0.09, 0.97 } or (hov and C.WALNUT_HI or { 0.17, 0.095, 0.05, 0.95 }), accent or (on and C.GOLD or col4(C.RIM, 0.6)), 10)
    text(label, x + w / 2, y + h * (sub and 0.4 or 0.5), 17 * u, on and C.GOLD or C.CREAM, "center", z + 2, w)
    if sub then text(sub, x + w / 2, y + h * 0.74, 12 * u, col4(C.BRASS, 0.85), "center", z + 2, w) end
    catcher(id, x, y, w, h, z + 11)
    hot[id] = true
end
-- A card's or panel's way back, at its bottom-left: BACK (or CLOSE) · Esc.
local BACK_W, BACK_H = 170, 46
local function back_button(id, x, y, label, z)
    local u = ctx.u()
    button(id, x, y, BACK_W * u, BACK_H * u, label or "BACK", "Esc", false, nil, z)
end
local function nohot(id) hide(id); hot[id] = nil end

local function top_left()
    local u = ctx.u()
    panel(24 * u, 18 * u, 360 * u, 92 * u, 39, C.WALNUT, C.RIM, 14)
    text("TOPPLE", 44 * u, 50 * u, 40 * u, C.CREAM, "left", 41, 300 * u)
    local rname = (HM.BY_ID[S.room] or { name = "the room" }).name
    local tier = S.ch and S.ch.tier and ("level " .. S.ch.tier)
    text(S.ch and (rname .. (tier and ("  ·  " .. tier) or "") .. "  ·  " .. S.ch.name) or ("free build  ·  " .. rname:lower()), 46 * u, 88 * u, 15 * u, col4(C.BRASS, 0.95), "left", 41, 250 * u)
    button("fb_menu", 300 * u, 34 * u, 70 * u, 60 * u, "MENU", nil, false)
    if S.mode ~= "running" then
        button("fb_ch", 24 * u, 118 * u, 210 * u, 50 * u, S.ch and "LEAVE CHALLENGE" or "HOUSE MAP", nil, S.ch == nil, S.ch == nil and C.GOLD or nil)
    else
        nohot("fb_ch")
    end
end

local STAR_ON, STAR_KEPT, STAR_OFF = { 1, 0.78, 0.3 }, { 0.78, 0.55, 0.24 }, { 0.2, 0.13, 0.08 }
local function star(x, y, sz, c, z, a) image("Textures/star.png", x, y, sz, sz, { c[1], c[2], c[3], a or 1 }, z) end
local function star_row(cx, y, sz, n, z, a, count)
    count = count or 3
    for i = 1, count do star(cx + (i - (count + 1) / 2) * sz * 1.12 - sz / 2, y, sz, i <= n and STAR_ON or STAR_OFF, z, a) end
end
FV.STAR_T0, FV.STAR_DT = 0.6, 0.4

local function challenge_top_right(x, pw)
    local u, def = ctx.u(), S.ch
    local B = def.budget
    panel(x, 18 * u, pw, 118 * u, 39, C.WALNUT, C.RIM, 14)
    local used = Ch.used(board)
    text(commas(used) .. "  /  " .. commas(B.domino), x + pw / 2, 46 * u, 30 * u, used >= B.domino and C.BAD or C.CREAM, "center", 41, pw)
    text("dominoes in your budget", x + pw / 2, 74 * u, 13 * u, col4(C.BRASS, 0.9), "center", 41, pw)
    local left = {}
    for _, g in ipairs({ { "ball", board.ball_count, "balls" }, { "swing", board.swing_count, "swings" }, { "switch", board.switch_count - 1, "switches" }, { "ramp", board.ramp_count, "ramps" } }) do
        if (B[g[1]] or 0) > 0 then left[#left + 1] = (B[g[1]] - g[2]) .. " " .. g[3] .. " left" end
    end
    text(#left > 0 and table.concat(left, "  ·  ") or "dominoes only", x + pw / 2, 98 * u, 16 * u, C.GOLD, "center", 41, pw)
    local best_p, line = house.best[def.id], "not cleared yet"
    if best_p then
        local n = house:stars_for(def.id)
        line = def.challenges and ("cleared  ·  " .. n .. " of " .. #def.challenges .. " stars") or ("cleared  ·  " .. n .. " stars")
    end
    text(line, x + pw / 2, 122 * u, 12 * u, col4(C.BRASS, 0.8), "center", 41, pw)
end

-- What this challenge asks, above the room while you build: its tier on the left, what clearing it unlocks on the right.
local TIER_COL = { { 0.62, 0.8, 0.55, 1 }, { 0.88, 0.68, 0.38, 1 }, { 0.93, 0.45, 0.33, 1 } }
local function tier_of(def)
    if def.tier then return def.tier end
    for k = 1, 3 do if house:tiers(def.room or S.room)[k] == def then return k end end
end
FV.tier_of = tier_of
local function unlock_word(def)
    if def.unlock then return tostring(def.unlock):upper() end
    local r = HM.BY_ID[def.room or S.room]
    if not r then return nil end
    local t = {}
    for _, id in ipairs(r.unlocks.tools or {}) do t[#t + 1] = id:upper() end
    for _, s in ipairs(r.unlocks.sizes or {}) do t[#t + 1] = F.SIZE_NAMES[s]:upper() end
    return #t > 0 and table.concat(t, ", ") or nil
end
-- The level card, above the room while you build: the level, what it asks, the rule every level keeps (Start to End),
-- and its challenges, a star slot each, gold for the ones you hold.
FV.REQUIRE = "Start the chain at START. The last domino to fall must be the END one."
local function challenge_brief()
    local u, w, def = ctx.u(), ctx.L.w, S.ch
    local list = def.challenges or {}
    local cw, rh = 820 * u, 26 * u
    local x = (w - cw) / 2
    local top = (board.end_piece and 106 or 84) * u
    local ph = top + (#list > 0 and #list * rh + 14 * u or 8 * u)
    FV.card_bottom = 18 * u + ph
    panel(x, 18 * u, cw, ph, 39, C.WALNUT, C.RIM, 14)
    local k = tier_of(def)
    if k then
        local rw = 112 * u
        panel(x + 16 * u, 30 * u, rw, 28 * u, 40, { 0.12, 0.065, 0.035, 1 }, TIER_COL[k], 9)
        text("LEVEL " .. k, x + 16 * u + rw / 2, 44 * u, 14 * u, TIER_COL[k], "center", 41, rw)
    end
    local un = unlock_word(def)
    if un and k == 1 then
        text("clear it: unlocks", x + cw - 18 * u, 34 * u, 11 * u, col4(C.BRASS, 0.9), "right", 41, 200 * u)
        text(un, x + cw - 18 * u, 52 * u, 15 * u, C.GOLD, "right", 41, 200 * u)
    end
    text(def.goal_word, w / 2, 44 * u, 26 * u, C.GOLD, "center", 41, cw - 300 * u)
    text(def.brief, w / 2, 72 * u, 15 * u, C.CREAM, "center", 41, cw)
    if board.end_piece then text(FV.REQUIRE, w / 2, 98 * u, 14 * u, col4(C.BRASS, 0.98), "center", 41, cw) end
    for i, c in ipairs(list) do
        local yy = 18 * u + top + (i - 0.5) * rh + 4 * u
        local got = house:done(def.id, c.id)
        star(x + 40 * u, yy - 10 * u, 20 * u, got and STAR_ON or STAR_OFF, 41)
        text(c.name, x + 70 * u, yy, 15 * u, got and C.GOLD or C.CREAM, "left", 41, 210 * u)
        text(c.brief, x + 290 * u, yy, 14 * u, col4(C.CREAM, 0.85), "left", 41, cw - 310 * u)
    end
end

-- START and END: a ring on each locked domino while you build, and the word on a walnut tag floating over the world's
-- marker beside it (its pennant), with a brass thread down to the plaque, while you build and while it runs. The tag's
-- size eases down with the camera's distance like the world does, but never below 17 px nor above 30, so it reads from
-- any room's camera. A
-- level made the old way (no End) rings its first domino and its goal.
function FV.mark_px(dist) return max(17, min(30, 24 * math.sqrt(40 / max(1, dist or 40)))) end
local function challenge_marks(tray_y)
    local u, def = ctx.u(), S.ch
    local p = 0.5 + 0.5 * sin(S.t * 3.5)
    if board.start_piece then
        local px = FV.mark_px(FW.goal.dist) * u
        for _, m in ipairs({ { board.start_piece, "START", C.CREAM, FW.marks.start }, { board.end_piece, "END", C.GOLD, FW.marks.finish } }) do
            local pc = m[1] and board.pieces[m[1]]
            if pc then
                local sx, sy = FW.project(pc.x, pc.y, pc.z + 0.5 * (pc.s or 1))
                if sx and S.mode == "build" then
                    local r = (18 + 5 * p) * u
                    rect(sx - r, sy - r, 2 * r, 2 * r, { 0, 0, 0, 0 }, 34, r, col4(m[3], 0.35 + 0.35 * p))
                end
                local T = m[4] and m[4].top or { x = pc.x, y = pc.y, h = pc.z + (pc.s or 1) + 1.6 }
                local lx, ly = FW.project(T.x, T.y, T.h)
                if lx then
                    local lw, lh = #m[2] * px * 0.78 + px * 1.6, px * 1.75
                    -- (kept in the clear between the level card or the top panels and the tray: never behind them)
                    local top = S.mode == "build" and (FV.card_bottom or 0) + 8 * u or 150 * u
                    local bot = (tray_y or ctx.L.h) - 70 * u
                    ly = max(top + lh / 2, min(bot - lh / 2, ly - lh / 2))
                    lx = max(lw / 2 + 10 * u, min(ctx.L.w - lw / 2 - 10 * u, lx))
                    if m[4] and not m[4].label_only then
                        local bx, by = FW.project(m[4].x, m[4].y, m[4].h)
                        if by and by > ly + lh / 2 then rect(lx - 1.5 * u, ly + lh / 2, 3 * u, by - ly - lh / 2, col4(C.BRASS, 0.85), 34) end
                    end
                    panel(lx - lw / 2, ly - lh / 2, lw, lh, 35, { 0.2, 0.1, 0.05, 0.95 }, col4(C.BRASS, 0.95), 8)
                    text(m[2], lx, ly, px, m[3], "center", 36, lw)
                end
            end
        end
        return
    end
    local gp = board.goal_piece and board.pieces[board.goal_piece]
    local goal = gp and { x = gp.x, y = gp.y, h = gp.z + (gp.s or 1) } or def.goal
    for _, m in ipairs({ { def.start, "START", C.CREAM }, { goal, "GOAL", C.GOLD } }) do
        local sx, sy
        if m[1] and m[1].x then sx, sy = FW.project(m[1].x, m[1].y, (m[1].h or 0) + 0.5) end
        if sx then
            local r = (24 + 6 * p) * u
            rect(sx - r, sy - r, 2 * r, 2 * r, { 0, 0, 0, 0 }, 34, r, col4(m[3], 0.55 + 0.4 * p))
            text(m[2], sx, sy - r - 15 * u, 16 * u, m[3], "center", 35, 120 * u)
        end
    end
end

local function top_right()
    local u = ctx.u()
    local w = ctx.L.w
    local pw = 380 * u
    local x = w - pw - 24 * u
    if S.ch then challenge_top_right(x, pw); return end
    panel(x, 18 * u, pw, 118 * u, 39, C.WALNUT, C.RIM, 14)
    text(commas(board.count) .. "  /  " .. commas(F.CAP), x + pw / 2, 46 * u, 30 * u, C.CREAM, "center", 41, pw)
    text("dominoes in the room", x + pw / 2, 74 * u, 13 * u, col4(C.BRASS, 0.9), "center", 41, pw)
    local line
    if S.mode == "running" then line = commas(S.fallen or 0) .. " fallen"
    elseif S.pred and board.count > 0 then
        -- With moving parts the real run can differ a little from this estimate.
        line = "the chain reaches " .. ((board.ball_count + board.swing_count > 0) and "about " or "") .. commas(S.pred.toppled)
    elseif board.count == 0 then line = "lay some dominoes"
    else line = "…" end
    text(line, x + pw / 2, 100 * u, 17 * u, C.GOLD, "center", 41, pw)
    text(best > 0 and ("best chain  " .. commas(best)) or "", x + pw / 2, 124 * u, 12 * u, col4(C.BRASS, 0.8), "center", 41, pw)
end

-- Down the left side: the size the tools lay, and whether a stroke grows.
local SIZE_IDS = { "fb_grow" }
for i = 1, #F.SIZES do SIZE_IDS[#SIZE_IDS + 1] = "fb_size" .. i end
local function size_panel()
    local u = ctx.u()
    local rows = {}
    for i = 1, #F.SIZES do if not S.ch or size_ok(i) then rows[#rows + 1] = i end end
    local grow = not S.ch or tool_ok("grow")
    if S.ch and #rows < 2 and not grow then for _, id in ipairs(SIZE_IDS) do nohot(id) end; return end
    local x, y, pw, rh = 24 * u, 178 * u, 210 * u, 38 * u
    local n = #rows + (grow and 1 or 0)
    panel(x, y, pw, 40 * u + n * (rh + 6 * u) + (grow and 30 or 4) * u, 39, C.WALNUT, C.RIM, 14)
    text("SIZE  ·  -  =", x + pw / 2, y + 22 * u, 14 * u, col4(C.BRASS, 0.95), "center", 41, pw)
    for i = 1, #F.SIZES do nohot("fb_size" .. i) end
    for k, i in ipairs(rows) do
        local by = y + 40 * u + (k - 1) * (rh + 6 * u)
        local on, ok = S.size == i, size_ok(i)
        button("fb_size" .. i, x + 10 * u, by, pw - 20 * u, rh, "", nil, on)
        local a = ok and 1 or 0.38
        -- (a bar as tall as the size, so the scale reads at a glance)
        local bh = min(rh - 8 * u, 7 * u * F.SIZES[i])
        quad(pid("fbz"), { style = "text", label = "", x = x + 24 * u, y = by + rh - 4 * u - bh, width = max(3 * u, bh * 0.3), height = bh, z = 53,
            fill = col4(on and C.GOLD or C.CREAM, a), corner_radius = 1.5 * u })
        text(F.SIZE_NAMES[i], x + 46 * u, by + rh / 2, 16 * u, col4(on and C.GOLD or C.CREAM, a), "left", 53, 90 * u)
        if not ok then
            local r = HM.size_unlocker(i)
            ctx.lock(x + pw - 30 * u, by + rh * 0.36, 11 * u, 0.85, 54)
            text(r and r.name or "", x + pw - 18 * u, by + rh * 0.78, 10 * u, col4(C.BRASS, 0.8), "right", 54, 100 * u)
        end
    end
    if grow then
        local gy = y + 40 * u + #rows * (rh + 6 * u)
        local ok = tool_ok("grow")
        button("fb_grow", x + 10 * u, gy, pw - 20 * u, rh, ok and (S.grow and "GROW  ·  on" or "GROW  ·  off") or "", nil, S.grow and ok)
        if ok then
            text("G  ·  steps up a size at a time", x + pw / 2, gy + rh + 16 * u, 11.5 * u, col4(C.BRASS, 0.85), "center", 41, pw)
        else
            text("GROW", x + 46 * u, gy + rh / 2, 16 * u, col4(C.CREAM, 0.38), "left", 53, 90 * u)
            ctx.lock(x + pw - 30 * u, gy + rh * 0.36, 11 * u, 0.85, 54)
            text(HM.unlocker("grow").name, x + pw - 18 * u, gy + rh * 0.78, 10 * u, col4(C.BRASS, 0.8), "right", 54, 100 * u)
            text("G  ·  steps up a size at a time", x + pw / 2, gy + rh + 16 * u, 11.5 * u, col4(C.BRASS, 0.5), "center", 41, pw)
        end
    else
        nohot("fb_grow")
    end
end

local function tray()
    local u, w, h = ctx.u(), ctx.L.w, ctx.L.h
    local tw, th = 1600 * u, 150 * u
    local tx, ty = (w - tw) / 2, h - th - 18 * u
    panel(tx, ty, tw, th, 50, C.WALNUT, C.RIM, 18)
    catcher("fb_tray", tx, ty, tw, th, 55); hot.fb_tray = true
    local cw, ch = 124 * u, 126 * u
    -- The tool buttons share a fixed strip, so adding a tool leaves the paints and buttons where they are.
    local shown = {}
    for i, t in ipairs(TOOLS) do if not S.ch or tool_ok(t.id) then shown[#shown + 1] = i else nohot("fb_tool" .. i) end end
    local strip = 6 * cw + 5 * 8 * u
    local bw = min(cw, (strip - (#shown - 1) * 8 * u) / #shown)
    local isz = min(84 * u, bw - 8 * u)
    local x0 = tx + 14 * u + (strip - (#shown * bw + (#shown - 1) * 8 * u)) / 2
    for k, i in ipairs(shown) do
        local t = TOOLS[i]
        local x, y = x0 + (k - 1) * (bw + 8 * u), ty + 12 * u
        local ok = tool_ok(t.id)
        local sel = ok and S.tool == t.id
        local hov = hovered("fb_tool" .. i)
        panel(x, y, bw, ch, 51, sel and { 0.34, 0.2, 0.09, 0.97 } or (hov and ok and C.WALNUT_HI or (ok and { 0.17, 0.095, 0.05, 0.95 } or { 0.11, 0.06, 0.035, 0.95 })),
            sel and C.GOLD or col4(C.RIM, ok and 0.6 or 0.3), 12)
        local fs_ = min(16 * u, bw * 0.19)
        if ok then
            image("Textures/icon_" .. t.icon .. ".png", x + (bw - isz) / 2, y + 4 * u, isz, isz, { 1, 1, 1, 1 }, 52)
            text(t.name, x + bw / 2, y + 100 * u, fs_, sel and C.GOLD or C.CREAM, "center", 53, bw)
        else
            image("Textures/icon_" .. t.icon .. ".png", x + (bw - isz) / 2, y + 4 * u, isz, isz, { 0.55, 0.5, 0.45, 0.3 }, 52)
            ctx.lock(x + bw / 2, y + 46 * u, 15 * u, 0.9, 54)
            text(t.name, x + bw / 2, y + 94 * u, fs_ * 0.85, col4(C.CREAM, 0.4), "center", 53, bw)
            local r = HM.unlocker(t.id)
            text(r and r.name or "", x + bw / 2, y + 113 * u, min(11 * u, bw * 0.15), col4(C.BRASS, 0.85), "center", 53, bw)
        end
        text(i == 10 and "0" or tostring(i), x + 13 * u, y + 15 * u, 14 * u, col4(C.BRASS, ok and 0.8 or 0.4), "center", 53, 30 * u)
        catcher("fb_tool" .. i, x, y, bw, ch, 62); hot["fb_tool" .. i] = true
    end
    -- Paints.
    local px = tx + 14 * u + 6 * (cw + 8 * u) + 6 * u
    local pw = 168 * u
    panel(px, ty + 12 * u, pw, ch, 51, { 0.15, 0.085, 0.045, 0.95 }, col4(C.RIM, 0.5), 12)
    text("PAINT  ·  P", px + pw / 2, ty + 28 * u, 13 * u, col4(C.BRASS, 0.9), "center", 53, pw)
    for i, p in ipairs(PAINTS) do
        local col, row = (i - 1) % 3, floor((i - 1) / 3)
        local r = 22 * u
        local cx, cy = px + pw / 2 + (col - 1) * 52 * u, ty + 70 * u + row * 50 * u
        local sel = S.paint == p
        if p == "rainbow" then
            for k = 1, 5 do
                local a = (k - 1) / 5 * 2 * math.pi
                quad(pid("fbs"), { style = "text", label = "", x = cx + cos(a) * r * 0.45 - r * 0.45, y = cy + sin(a) * r * 0.45 - r * 0.45,
                    width = r * 0.9, height = r * 0.9, z = 53, fill = SWATCH[F.PAINTS[k]], corner_radius = r * 0.45 })
            end
        else
            quad(pid("fbs"), { style = "text", label = "", x = cx - r * 0.8, y = cy - r * 0.8, width = r * 1.6, height = r * 1.6, z = 53,
                fill = SWATCH[p], border = { 0.1, 0.06, 0.03, 1 }, corner_radius = r * 0.8 })
        end
        quad(pid("fbs"), { style = "text", label = "", x = cx - r, y = cy - r, width = 2 * r, height = 2 * r, z = 54,
            fill = { 0, 0, 0, 0 }, border = sel and C.GOLD or { 0, 0, 0, 0 }, corner_radius = r })
        catcher("fb_paint" .. i, cx - r, cy - r, 2 * r, 2 * r, 62); hot["fb_paint" .. i] = true
    end
    -- Buttons: undo / redo, save / load, clear / camera.
    local bx = px + pw + 10 * u
    local bw, bh = 104 * u, 59 * u
    local B = { { "fb_undo", "UNDO", "Backspace" }, { "fb_save", "SAVE", "3 slots", S.panel == "save" }, { "fb_clear", "CLEAR", "C  twice" },
        { "fb_redo", "REDO", "Ctrl Y" }, { "fb_load", "LOAD", "slots, sample", S.panel == "load" }, { "fb_follow", "FOLLOW", FW.follow and "on  ·  F" or "off  ·  F", FW.follow } }
    for i, b in ipairs(B) do
        local col, row = (i - 1) % 3, floor((i - 1) / 3)
        button(b[1], bx + col * (bw + 8 * u), ty + 12 * u + row * (bh + 8 * u), bw, bh, b[2], b[3], b[4])
    end
    -- TIP.
    local tipx = bx + 3 * (bw + 8 * u) + 4 * u
    local tipw = tx + tw - 14 * u - tipx
    local ready = board.count > 0
    local hov = hovered("fb_tip")
    local pulse = ready and (0.5 + 0.5 * sin(S.t * 4)) or 0
    local label = S.mode == "done" and "AGAIN" or "TIP"
    panel(tipx, ty + 12 * u, tipw, ch, 51, ready and (hov and { 0.5, 0.3, 0.1, 0.98 } or { 0.42, 0.25, 0.09, 0.97 }) or { 0.17, 0.095, 0.05, 0.95 },
        ready and col4(C.GOLD, 0.7 + 0.3 * pulse) or col4(C.RIM, 0.5), 14)
    text(label, tipx + tipw / 2, ty + 62 * u, 40 * u, ready and C.GOLD or col4(C.CREAM, 0.4), "center", 53, tipw)
    text("Space", tipx + tipw / 2, ty + 104 * u, 14 * u, col4(C.BRASS, ready and 0.9 or 0.4), "center", 53, tipw)
    catcher("fb_tip", tipx, ty + 12 * u, tipw, ch, 62); hot.fb_tip = true
    -- Above the tray: the tool's hint, the size, the camera.
    local tool
    for _, t in ipairs(TOOLS) do if t.id == S.tool then tool = t end end
    local hint = tool.hint
    if S.tool == "field" then hint = hint .. "  (now " .. string.format("%.1f", S.field_w) .. " wide)" end
    if S.tool == "erase" then hint = hint .. "  (now " .. string.format("%.1f", S.erase_r) .. ")" end
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
    catcher("fb_tray", tx, ty, tw, th, 55); hot.fb_tray = true
    local res = S.res
    local done = S.mode == "done"
    local n = done and res.toppled or (S.fallen or 0)
    text(commas(n), tx + 140 * u, ty + 46 * u, 46 * u, C.GOLD, "center", 53, 260 * u)
    text(done and ("of " .. commas(res.total) .. " fell") or "fallen", tx + 140 * u, ty + 86 * u, 15 * u, col4(C.CREAM, 0.9), "center", 53, 260 * u)
    local secs = done and res.duration or FW.run_time()
    text(string.format("%.1f s", secs), tx + 330 * u, ty + 46 * u, 30 * u, C.CREAM, "center", 53, 160 * u)
    text(done and "the chain ran" or (S.speed < 1 and "slow motion" or "watch"), tx + 330 * u, ty + 86 * u, 14 * u, col4(C.BRASS, 0.9), "center", 53, 160 * u)
    local bw, bh = 120 * u, 82 * u
    local bx = tx + 430 * u
    button("fb_slow", bx, ty + 15 * u, bw, bh, "SLOW-MO", S.speed < 1 and "on  ·  Z" or "off  ·  Z", S.speed < 1)
    button("fb_follow", bx + (bw + 8 * u), ty + 15 * u, bw, bh, "FOLLOW", FW.follow and "on  ·  F" or "off  ·  F", FW.follow)
    button("fb_stand", bx + 2 * (bw + 8 * u), ty + 15 * u, bw, bh, "STAND UP", "R", false)
    if done then
        button("fb_tip", bx + 3 * (bw + 8 * u), ty + 15 * u, tx + tw - 14 * u - (bx + 3 * (bw + 8 * u)), bh, "AGAIN", "Space", true, C.GOLD)
    else
        nohot("fb_tip")
    end
    return tx, ty
end

-- After a run: the score card, and rings where the chain stopped short. A level's card says why it failed (C.requirement's
-- why), or lists its challenges: earned this run (a NEW STAR or earned again), kept from before, or not yet.
FV.WHY = { after = "Dominoes were still falling after the END.", start = "The chain did not begin at START.", ["end"] = "The END domino never fell." }
FV.ZERO_HEAD = "CLEARED  ·  0 STARS"
local function result_card()
    local u, w = ctx.u(), ctx.L.w
    local res = S.res
    local a = min(1, (S.done_t or 0) * 3)
    local R_ = S.ch_result
    if S.ch and R_ then
        local list = S.ch.challenges or {}
        local n, rh = #list, 30 * u
        local cw2 = 720 * u
        local ch2 = (n > 0 and (112 * u + n * rh) or 176 * u) + 58 * u
        local x2, y2 = (w - cw2) / 2, 30 * u
        panel(x2, y2, cw2, ch2, 70, col4(C.WALNUT, a), col4(C.RIM, a), 16)
        back_button("fb_res_close", x2 + 20 * u, y2 + ch2 - (BACK_H + 12) * u, "CLOSE", 72)
        local head, sub
        if R_.won and n > 0 and R_.stars == 0 then
            head, sub = FV.ZERO_HEAD, "Level cleared from START to END, with no challenge done. Each one below is a star."
        elseif R_.won then
            head, sub = S.ch.win, "You placed " .. R_.used .. " dominoes of your own."
        else
            head = R_.why == "end" and S.ch.fail or "NOT CLEARED"
            sub = (FV.WHY[R_.why] or FV.WHY["end"]) .. (R_.why == "end" and "  The rings show where it stopped short." or "  No star this run.")
        end
        text(head, w / 2, y2 + 40 * u, 34 * u, col4(R_.won and (R_.stars > 0 and C.GOLD or C.CREAM) or C.BAD, a), "center", 71, cw2)
        if n == 0 and R_.won then
            star_row(w / 2, y2 + 66 * u, 52 * u, R_.stars, 71, a)
            text(sub, w / 2, y2 + 146 * u, 17 * u, col4(C.CREAM, a), "center", 71, cw2)
        else
            text(sub, w / 2, y2 + (n > 0 and 80 or 92) * u, 17 * u, col4(C.CREAM, a), "center", 71, cw2)
        end
        local order = {}
        for k, id in ipairs(R_.pops or {}) do order[id] = k end
        for i, c in ipairs(list) do
            local yy = y2 + 104 * u + (i - 0.5) * rh
            local now, held = R_.now[c.id], R_.held[c.id]
            local sz, col = 24 * u, held and STAR_KEPT or STAR_OFF
            if now then
                local e = max(0, min(1, ((S.done_t or 0) - FV.STAR_T0 - FV.STAR_DT * (order[c.id] - 1)) * 4))
                if e > 0 then col, sz = STAR_ON, sz * (1 + 0.6 * (1 - e)) end
            end
            star(x2 + 52 * u - sz / 2, yy - sz / 2, sz, col, 72, a)
            text(c.name, x2 + 84 * u, yy, 17 * u, col4(now and C.GOLD or C.CREAM, (now or held) and a or 0.6 * a), "left", 71, 230 * u)
            text(c.brief, x2 + 320 * u, yy, 13 * u, col4(C.CREAM, 0.7 * a), "left", 71, 250 * u)
            local tag, tc = "not yet", col4(C.BRASS, 0.6)
            if now and not held then tag, tc = "NEW STAR", C.GOLD
            elseif now then tag, tc = "earned again", C.CREAM
            elseif held then tag, tc = "kept", C.BRASS end
            text(tag, x2 + cw2 - 26 * u, yy, 15 * u, col4(tc, a), "right", 71, 120 * u)
        end
        local nw = R_.won and R_.news
        if nw then
            local what = {}
            for _, t in ipairs(nw.cleared.unlocks.tools or {}) do what[#what + 1] = t:upper() end
            for _, s in ipairs(nw.cleared.unlocks.sizes or {}) do what[#what + 1] = F.SIZE_NAMES[s] end
            local pw2 = 760 * u
            panel((w - pw2) / 2, y2 + ch2 + 12 * u, pw2, 64 * u, 70, col4({ 0.3, 0.18, 0.07, 0.97 }, a), col4(C.GOLD, a), 14)
            text(nw.cleared.name:upper() .. " CLEARED  ·  unlocked " .. table.concat(what, ", "), w / 2, y2 + ch2 + 34 * u, 19 * u, col4(C.GOLD, a), "center", 71, pw2)
            text(nw.opened and ("The " .. nw.opened.name .. " is open, and you can build in the " .. nw.cleared.name .. ".") or ("The whole house is yours. Build anywhere."),
                w / 2, y2 + ch2 + 58 * u, 14 * u, col4(C.CREAM, a), "center", 71, pw2)
        end
        return
    end
    local cw, ch = 640 * u, 178 * u
    local x, y = (w - cw) / 2, 30 * u
    panel(x, y, cw, ch, 70, col4(C.WALNUT, a), col4(C.RIM, a), 16)
    back_button("fb_res_close", x + 20 * u, y + ch - (BACK_H + 12) * u, "CLOSE", 72)
    local all = res.toppled == res.total
    text(all and "EVERY DOMINO FELL" or (commas(res.toppled) .. " OF " .. commas(res.total) .. " FELL"), w / 2, y + 42 * u, 34 * u, col4(C.GOLD, a), "center", 71, cw)
    local sub
    if S.milestone then sub = "Milestone: " .. commas(S.milestone) .. " dominoes in one chain!"
    elseif S.new_best then sub = "Your longest chain yet."
    elseif not all and #(S.gaps or {}) > 0 then sub = "The rings show where it stopped short."
    else sub = string.format("%.1f seconds of chain", res.duration) end
    text(sub, w / 2, y + 86 * u, 18 * u, col4(C.CREAM, a), "center", 71, cw)
end

local function gap_marks()
    if not S.gaps then return end
    local u = ctx.u()
    for i, g in ipairs(S.gaps) do
        if i > 12 then break end
        local sx, sy = FW.project(g.x, g.y, g.z + 0.05)
        if sx then
            local r = (34 + 6 * sin(S.t * 5)) * u
            image("Textures/ring.png", sx - r, sy - r * 0.6, 2 * r, 1.2 * r, { 1, 0.45, 0.32, 0.9 }, 44)
        end
    end
end

-- While a line, spiral or field is being dragged: dots where its dominoes will stand, and how many.
-- With the switch tool in hand: a dotted line from each switch to the domino it starts, the chosen switch in gold.
local function switch_links()
    if S.tool ~= "switch" then return end
    local u = ctx.u()
    local function dot(x, y, r, col)
        quad(pid("fbl"), { style = "text", label = "", x = x - r, y = y - r, width = 2 * r, height = 2 * r, z = 44, fill = col, corner_radius = r })
    end
    for id, sw in pairs(board.switches) do
        local sx, sy = FW.project(sw.x, sw.y, sw.z + 1)
        local chosen = id == S.switch_sel
        local col = chosen and { 1, 0.8, 0.3, 1 } or { 1, 0.92, 0.75, 0.75 }
        if sx and chosen then dot(sx, sy, 8 * u, col) end
        local q = sw.target and board.pieces[sw.target]
        local ex, ey
        if q then ex, ey = FW.project(q.x, q.y, q.z + 0.5) end
        if sx and ex then
            for k = 1, 16 do dot(sx + (ex - sx) * k / 17, sy + (ey - sy) * k / 17, 3 * u, col) end
            dot(ex, ey, 6 * u, col)
        end
    end
end

local function shape_preview()
    local P = S.press
    if not P or P.kind == "draw" or P.kind == "erase" then return end
    local u = ctx.u()
    local spots = shape_spots(P)
    local step = max(1, floor(#spots / 500))
    for i = 1, #spots, step do
        local s = spots[i]
        local sx, sy = FW.project(s.x, s.y, (s.h or FV.rest_h(s.x, s.y, P.h0, P.kind, cur_size())) + 0.5)
        if sx then
            local r = 3.5 * u
            quad(pid("fbd"), { style = "text", label = "", x = sx - r, y = sy - r, width = 2 * r, height = 2 * r, z = 44,
                fill = i == 1 and { 1, 0.85, 0.5, 0.95 } or { 1, 0.92, 0.75, 0.8 }, corner_radius = r })
        end
    end
    local sx, sy = FW.project(P.x1, P.y1, FV.rest_h(P.x1, P.y1, P.h0, P.kind, cur_size()) + 1.2)
    if sx and #spots > 0 and P.kind ~= "swing" and P.kind ~= "ramp" then text(commas(#spots), sx, sy - 18 * u, 20 * u, C.GOLD, "center", 46, 200 * u) end
end

FV.shape_preview = shape_preview

local function slot_panel(tx, ty)
    if not S.panel then for i = 1, 4 do nohot("fb_slot" .. i) end; nohot("fb_slot_back"); return end
    local u = ctx.u()
    if not S.slots then
        S.slots = {}
        for i = 1, 3 do
            local s = fs.read(room_file("slot", i))
            local n = 0
            if s then for _ in s:gmatch("\nd ") do n = n + 1 end end
            S.slots[i] = s and n or nil
        end
    end
    local n = (S.panel == "load" and S.room == "living") and 4 or 3
    local bw, bh = 200 * u, 70 * u
    local pw = n * (bw + 10 * u) + 30 * u
    local px, py = (ctx.L.w - pw) / 2, ty - bh - 212 * u      -- (clear of the message and controls lines over the tray)
    panel(px, py, pw, bh + 116 * u, 72, { 0.1, 0.055, 0.03, 0.97 }, C.RIM, 16)
    back_button("fb_slot_back", px + 20 * u, py + 54 * u + bh, "BACK", 73)
    text(S.panel == "save" and "SAVE THE ROOM TO…" or "LOAD…", px + pw / 2, py + 24 * u, 17 * u, C.CREAM, "center", 73, pw)
    for i = 1, n do
        local x = px + 20 * u + (i - 1) * (bw + 10 * u)
        local label = i == 4 and "SAMPLE" or ("SLOT " .. i)
        local sub = i == 4 and "the starter build" or (S.slots[i] and (commas(S.slots[i]) .. " dominoes") or "empty")
        local hov = hovered("fb_slot" .. i)
        panel(x, py + 44 * u, bw, bh, 73, hov and C.WALNUT_HI or { 0.17, 0.095, 0.05, 0.97 }, col4(C.GOLD, 0.7), 10)
        text(label, x + bw / 2, py + 44 * u + bh * 0.38, 18 * u, C.GOLD, "center", 74, bw)
        text(sub, x + bw / 2, py + 44 * u + bh * 0.72, 12 * u, col4(C.CREAM, 0.85), "center", 74, bw)
        catcher("fb_slot" .. i, x, py + 44 * u, bw, bh, 76); hot["fb_slot" .. i] = true
    end
    for i = n + 1, 4 do nohot("fb_slot" .. i) end
end

local ALL_IDS = { "fb_menu", "fb_tray", "fb_tip", "fb_undo", "fb_redo", "fb_save", "fb_load", "fb_clear", "fb_follow", "fb_slow", "fb_stand",
    "fb_slot1", "fb_slot2", "fb_slot3", "fb_slot4", "fb_slot_back", "fb_res_close" }
for i = 1, #TOOLS do ALL_IDS[#ALL_IDS + 1] = "fb_tool" .. i end
for i = 1, 6 do ALL_IDS[#ALL_IDS + 1] = "fb_paint" .. i end
for _, id in ipairs(SIZE_IDS) do ALL_IDS[#ALL_IDS + 1] = id end
ALL_IDS[#ALL_IDS + 1] = "fb_ch"
function FV.hide_all()
    for _, id in ipairs(ALL_IDS) do nohot(id) end
end

function FV.draw()
    local u, w, h = ctx.u(), ctx.L.w, ctx.L.h
    for id in pairs(hot) do hot[id] = nil end
    if ctx.SET:is_open() then FV.hide_all(); return end
    if not S.hud then
        FV.hide_all()
        text("H  shows the controls", w - 24 * u, h - 24 * u, 13 * u, col4(C.CREAM, 0.55), "right", 45, 400 * u)
        if S.mode == "done" then gap_marks() end
        return
    end
    top_left()
    top_right()
    local tx, ty
    if S.mode == "build" then
        for _, id in ipairs({ "fb_slow", "fb_stand", "fb_res_close" }) do nohot(id) end
        tx, ty = tray()
        size_panel()
        shape_preview()
        switch_links()
        slot_panel(tx, ty)
        if S.ch then challenge_brief(); challenge_marks(ty) end
    else
        for i = 1, #TOOLS do nohot("fb_tool" .. i) end
        for i = 1, 6 do nohot("fb_paint" .. i) end
        for _, id in ipairs(SIZE_IDS) do nohot(id) end
        for _, id in ipairs({ "fb_undo", "fb_redo", "fb_save", "fb_load", "fb_clear" }) do nohot(id) end
        for i = 1, 4 do nohot("fb_slot" .. i) end
        nohot("fb_slot_back")
        tx, ty = run_bar()
        if S.ch and board.start_piece then challenge_marks(ty) end
        if S.mode == "done" then result_card(); gap_marks() else nohot("fb_res_close") end
    end
    if S.msg and S.msg_t > 0 then
        local a = min(1, S.msg_t * 2)
        text(S.msg, w / 2, (ty or h) - 76 * u, 19 * u, col4(S.msg_bad and C.BAD or C.GOLD, a), "center", 46, 1200 * u)
    end
    if S.first_visit and not S.ch and S.room == "living" and S.mode == "build" and S.t < 14 then
        local a = min(1, S.t * 2) * min(1, (14 - S.t) / 1.5)
        local cw = 760 * u
        panel((w - cw) / 2, 150 * u, cw, 76 * u, 70, col4(C.WALNUT, a), col4(C.RIM, a), 14)
        text("A chain is already set up for you: press Space to tip it.", w / 2, 176 * u, 19 * u, col4(C.CREAM, a), "center", 71, cw)
        text("Up the ramp, off the table's edge, then a line that grows into Titans. Then build your own.", w / 2, 204 * u, 15 * u, col4(C.BRASS, a), "center", 71, cw)
    end
end

return FV
end
