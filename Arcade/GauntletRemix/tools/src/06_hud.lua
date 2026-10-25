------------------------------------------------------------------ HUD + menus (runtime_ui, pixel coords)
local UI = "hud"
runtime_ui.show(UI); pcall(runtime_ui.set_screen_overlay, UI, true)
local NONE = { 0, 0, 0, 0 }
local hc = {}
local US = SH / 1080
local function quad(id, o)
    local key = ""
    for _, k in ipairs({ "x", "y", "w", "h", "label", "visible", "font_scale" }) do key = key .. tostring(o[k]) .. "|" end
    if o.fill then key = key .. o.fill[1] .. o.fill[2] .. o.fill[3] .. o.fill[4] end
    if o.text_color then key = key .. o.text_color[4] end
    if hc[id] == key then return end
    hc[id] = key
    pcall(runtime_ui.set_quad, UI, id, o)
end
local function text(id, label, x, y, w, h, fs, col, align, vis)
    quad(id, { x = x, y = y, w = w, h = h, z = 10, style = "text", label = label, fill = NONE, border = NONE, text_color = col,
        font_scale = fs * US, align_h = align or "center", align_v = "middle", no_input = true, visible = vis ~= false })
end
local function panel(id, x, y, w, h, vis, a, border)
    quad(id, { x = x, y = y, w = w, h = h, z = 4, style = "text", label = "", fill = { 0.04, 0.04, 0.06, a or 0.55 },
        border = border or { 1, 0.55, 0.3, 0.55 }, corner_radius = 12 * US, no_input = true, visible = vis ~= false })
end
local function button(id, label, cx, cy, vis, bw)
    local w, h = (bw or 340) * US, 60 * US
    local st = vis and select(2, pcall(runtime_ui.get_state, UI, id))
    local hov = type(st) == "table" and st.hovered
    quad(id, { x = cx - w / 2, y = cy - h / 2, w = w, h = h, z = 12, style = "text", label = label,
        fill = hov and { 0.55, 0.12, 0.08, 0.92 } or { 0.08, 0.05, 0.05, 0.85 }, border = hov and { 1, 0.75, 0.5, 1 } or { 1, 0.5, 0.3, 0.9 },
        text_color = { 0.95, 0.95, 0.92, 1 }, font_scale = 1.25 * US, align_h = "center", align_v = "middle",
        corner_radius = 12 * US, visible = vis })
    return vis and type(st) == "table" and st.clicked
end
local function pad6(n) local s = tostring(floor(n)); return string.rep("0", max(0, 6 - #s)) .. s end
local RED, WHITE, CYAN, DIM, GOLD = { 1, .35, .3, 1 }, { 1, 1, 1, 1 }, { .5, .85, 1, 1 }, { .85, .82, .78, 1 }, { 1, .85, .35, 1 }
local LW = 300 * US
G.sel = 1
local HCOL = { war = { 1, .4, .3, 1 }, val = { .45, .65, 1, 1 }, wiz = { 1, .85, .3, 1 }, elf = { .45, .9, .45, 1 } }
local function draw_hud(dt, st)
    local play = (st == "play" or st == "pause") and not G.set_open
    local h = G.H()
    panel("lp", 20 * US, 20 * US, LW, 330 * US, play, 0.5)
    text("l1", h.name, 40 * US, 30 * US, LW - 40 * US, 40 * US, 1.3, HCOL[h.id], "left", play)
    text("l2", "Health", 40 * US, 76 * US, LW - 40 * US, 30 * US, 0.9, DIM, "left", play)
    text("l3", tostring(floor(G.health or 0)), 40 * US, 102 * US, LW - 40 * US, 56 * US, 2.0, (G.health or 0) < 200 and RED or WHITE, "left", play)
    text("l4", "Score  " .. tostring(G.score), 40 * US, 166 * US, LW - 40 * US, 36 * US, 1.1, WHITE, "left", play)
    text("l5", "Keys  " .. tostring(G.keys or 0) .. "     Potions  " .. tostring(G.potions or 0), 40 * US, 210 * US, LW - 40 * US, 36 * US, 1.0, GOLD, "left", play)
    text("l6", "High Score  " .. tostring(max(G.hiscore, G.score)), 40 * US, 254 * US, LW - 40 * US, 34 * US, 0.9, CYAN, "left", play)
    text("l7", G.L and ((G.L.treasure and G.L.name or ("Level " .. (G.level or 1))) .. ((G.tough or 0) > 0 and ("  ·  Round " .. (G.tough + 1)) or "")) or "", 40 * US, 294 * US, LW - 40 * US, 34 * US, 0.9, DIM, "left", play)
    local tt = G.ttime and G.phase == "play"
    text("ttime", tt and ("Treasure Room  ·  " .. math.ceil(G.ttime) .. " s") or "", 0, 24 * US, SW, 60 * US, 1.7, (G.ttime or 9) < 6 and RED or GOLD, "center", play and tt and true or false)
    -- health flashes red when hurt
    panel("hurt", 0, 0, SW, SH, play and (G.hurt_t or 0) > 0, 0.12, { 1, 0.1, 0.05, 0.6 })
    G.banner.t = (G.banner.t or 0) - dt
    local ba = floor(clamp(G.banner.t / 0.4, 0, 1) * 20) / 20
    text("ban", G.banner.text or "", 0, SH * 0.2, SW, 80 * US, 2.4, { 1, .88, .45, ba }, "center", play and G.banner.t > 0)
    local title = st == "title" and not G.set_open
    panel("t_bg", SW / 2 - 470 * US, SH * 0.06, 940 * US, SH * 0.8, title, 0.62)
    text("t_title", "Gauntlet Remix", 0, SH * 0.08, SW, 130 * US, 4.2, { 1, .55, .3, 1 }, "center", title)
    text("t_sub", "Choose your hero and fight down through the dungeon", 0, SH * 0.08 + 120 * US, SW, 40 * US, 1.0, DIM, "center", title)
    local CL = { "WASD / Arrows: move (8 ways)  ·  Space / J / Left Click: shoot (one per press)  ·  walk into monsters to fight",
        "Shift / X / Right Click: potion (destroys everything on screen)  ·  a key opens a door",
        "Health drains over time: eat food  ·  shoot generators to stop the monsters  ·  find the exit",
        "1-4 or Left / Right: choose hero  ·  P / Esc: pause  ·  O: settings  ·  M: mute  ·  F3: colliders" }
    for i, l in ipairs(CL) do text("t_c" .. i, l, SW / 2 - 460 * US, SH * 0.6 + (i - 1) * 34 * US, 920 * US, 34 * US, 0.88, DIM, "center", title) end
    local sel = G.HEROES[G.sel or 1]
    text("t_hero", sel.hero .. " the " .. sel.name .. string.format("   ·   armour %d  shot %d  fight %d  speed %d  magic %d",
        floor((1.2 - sel.armor) * 10 + 0.5), sel.shot, sel.melee, floor(sel.speed - 2), sel.magic), 0, SH * 0.6 + 140 * US, SW, 36 * US, 1.0, HCOL[sel.id], "center", title)
    local pause = st == "pause" and not G.set_open
    panel("p_bg", SW / 2 - 300 * US, SH * 0.26, 600 * US, SH * 0.46, pause, 0.75)
    text("p_t", "Paused", 0, SH * 0.28, SW, 80 * US, 2.6, GOLD, "center", pause)
    local over = st == "over" and not G.set_open
    panel("o_bg", SW / 2 - 400 * US, SH * 0.22, 800 * US, SH * 0.56, over, 0.78)
    text("o_t", "Game Over", 0, SH * 0.24, SW, 90 * US, 3.0, RED, "center", over)
    text("o_m", h.name .. " fell on " .. (G.L and G.L.name or ""), 0, SH * 0.24 + 92 * US, SW, 40 * US, 1.2, DIM, "center", over)
    text("o_s", "Score " .. tostring(G.score), 0, SH * 0.24 + 140 * US, SW, 44 * US, 1.4, WHITE, "center", over)
    local c = {}
    local yb = SH * 0.3
    c.hero = {}
    for i, hh in ipairs(G.HEROES) do
        local lab = (i == (G.sel or 1) and "> " or "") .. hh.name .. " (" .. i .. ")"
        c.hero[i] = button("b_h" .. i, lab, SW / 2 + (i - 2.5) * 222 * US, yb, title, 210)
    end
    c.start = button("b_start", "Start (Enter)", SW / 2 - 190 * US, yb + 80 * US, title, 300)
    c.jev = button("b_jev", "Jev", SW / 2 + 190 * US, yb + 80 * US, title, 300)
    c.set_t = button("b_set_t", "Settings (O)", SW / 2, yb + 156 * US, title)
    c.quit_app = button("b_quit_app", "Quit Game", SW / 2, yb + 232 * US, title)
    c.resume = button("b_resume", "Resume (P)", SW / 2, SH * 0.42, pause)
    c.set_p = button("b_set_p", "Settings (O)", SW / 2, SH * 0.42 + 76 * US, pause)
    c.quit = button("b_quit", "Quit to Title (Q)", SW / 2, SH * 0.42 + 152 * US, pause)
    local ov = over and (G.over_t or 0) > 1.2
    c.again = button("b_again", "Play Again (Enter)", SW / 2, SH * 0.52, ov)
    c.title = button("b_title", "Title (Esc)", SW / 2, SH * 0.52 + 76 * US, ov)
    return c
end

------------------------------------------------------------------ Jev. Direction holds and shot/potion pulses sit in G.vk,
-- which held() already treats as a key. apply() only stores that and returns.
local JEV_MOVE = {
    n = { 0, 1 },
    ne = { 1, 1 },
    e = { 1, 0 },
    se = { 1, -1 },
    s = { 0, -1 },
    sw = { -1, -1 },
    w = { -1, 0 },
    nw = { -1, 1 },
    stop = { 0, 0 },
}
local JEV_ACTIONS = {
    { id = "n", description = "Hold north" },
    { id = "ne", description = "Hold northeast" },
    { id = "e", description = "Hold east" },
    { id = "se", description = "Hold southeast" },
    { id = "s", description = "Hold south" },
    { id = "sw", description = "Hold southwest" },
    { id = "w", description = "Hold west" },
    { id = "nw", description = "Hold northwest" },
    { id = "stop", description = "Stop moving" },
    { id = "shot", description = "Shoot once" },
    { id = "potion", description = "Use a potion once" },
}
local JEV_KEYS = {
    "W", "A", "S", "D", "Up", "Down", "Left", "Right",
    "Space", "J", "X", "LeftShift", "RightShift",
}
local JevHold = {
    q = { Space = 0, X = 0 },
    down = {},
    raw = {},
    seen = false,
}
local jev

local function clear_move()
    G.vk = G.vk or {}
    G.vk.W = nil
    G.vk.A = nil
    G.vk.S = nil
    G.vk.D = nil
    G.vk.Up = nil
    G.vk.Down = nil
    G.vk.Left = nil
    G.vk.Right = nil
end

local function clear_jev_input()
    clear_move()
    JevHold.q.Space = 0
    JevHold.q.X = 0
    JevHold.down.Space = nil
    JevHold.down.X = nil
    G.vk.Space = nil
    G.vk.X = nil
end

local function apply_jev(id)
    local step = JEV_MOVE[id]
    if step then
        clear_move()
        if step[2] > 0 then
            G.vk.W = true
        elseif step[2] < 0 then
            G.vk.S = true
        end
        if step[1] > 0 then
            G.vk.D = true
        elseif step[1] < 0 then
            G.vk.A = true
        end
        JevHold.q.Space = JevHold.q.Space + 1
        return
    end

    if id == "shot" then
        JevHold.q.Space = JevHold.q.Space + 1
        return
    end
    if id == "potion" then
        JevHold.q.X = JevHold.q.X + 1
    end
end

-- A pulse is one virtual key-down, then a release on the next frame so edge() can fire again.
local function arm_pulses()
    local play = G.state == "play" and not G.set_open
    G.vk = G.vk or {}
    for _, key in ipairs({ "Space", "X" }) do
        if JevHold.down[key] or not play then
            G.vk[key] = nil
            JevHold.down[key] = nil
        elseif JevHold.q[key] > 0 then
            G.vk[key] = true
            JevHold.down[key] = true
            JevHold.q[key] = JevHold.q[key] - 1
        end
    end
end

local function human_edge()
    local hit = false
    for _, key in ipairs(JEV_KEYS) do
        local ok, down = pcall(input.is_key_down_raw, key)
        down = ok and down and true or false
        if JevHold.seen and down and not JevHold.raw[key] then
            hit = true
        end
        JevHold.raw[key] = down
    end
    JevHold.seen = true
    return hit
end

local function nearest_monster()
    local px = G.P and G.P.x or 0
    local py = G.P and G.P.y or 0
    local best
    local bd
    for _, m in ipairs(G.MON or {}) do
        if m.alive ~= false then
            local d = (m.x - px) * (m.x - px) + (m.y - py) * (m.y - py)
            if not bd or d < bd then
                best = m
                bd = d
            end
        end
    end
    if not best then
        return px, py, 0, 0
    end
    return px, py, best.x, best.y
end

------------------------------------------------------------------ flow
local function to_title()
    if jev then
        jev:begin_human()
    end
    G.state = "title"
    G.new_game_sim(G.sel or 1); G.reset_world()
    music("title")
end
G.to_title = to_title
local function new_game()
    G.reset_world(); G.new_game_sim(G.sel or 1)
    G.state = "play"; G.cam_snap = true
    music("level"); sfx("start")
end
G.new_game = new_game
local function game_over()
    G.state = "over"
    G.over_t = 0
    music(nil)
    sfx("gameover")
    clear_jev_input()
    if jev and jev:assisted() then
        return
    end
    if G.score > G.hiscore then
        G.hiscore = G.score
        save_hi()
    end
end
local acc = 0
local mprev = { x = 0, y = 0 }
local q = { fire = false, potion = false }
local lmouse_prev, rmouse_prev = true, true
local function update(dt)
    jev:tick(dt)

    flush_mats()
    dt = clamp(dt, 0, 0.1)   -- a negative frame time (timer hitch) would make every damp() explode
    G.t = G.t + dt; G.dt = dt
    arm_pulses()
    local k = { ret = edge("Return"), esc = edge("Escape"), p = edge("P"), o = edge("O"), m = edge("M"), qk = edge("Q"), f3 = edge("F3"),
        space = edge("Space"), j = edge("J"), x = edge("X"), sh = edge("LeftShift"), sh2 = edge("RightShift"),
        k1 = edge("1"), k2 = edge("2"), k3 = edge("3"), k4 = edge("4"), lf = edge("Left"), rt = edge("Right"), a = edge("A"), d = edge("D") }
    local ld, rd = false, false
    pcall(function() ld = input.is_left_mouse_down and input.is_left_mouse_down() and true or false end)
    pcall(function() rd = input.is_right_mouse_down and input.is_right_mouse_down() and true or false end)
    local lclick, rclick = ld and not lmouse_prev, rd and not rmouse_prev; lmouse_prev, rmouse_prev = ld, rd
    if k.f3 then G.DBG.on = not G.DBG.on end
    G.set_open = SET:update(dt)
    local st = G.state
    local c = draw_hud(dt, st)
    if G.set_open then for kk in pairs(k) do k[kk] = false end; lclick, rclick = false, false end
    local function open_settings() sfx("click"); SET:open(); G.set_open = true end
    if k.m then SET:toggle_mute() end
    if st == "title" then
        local s0 = G.sel or 1
        for i = 1, 4 do if k["k" .. i] or c.hero[i] then G.sel = i end end
        if k.lf or k.a then G.sel = (s0 + 2) % 4 + 1 elseif k.rt or k.d then G.sel = s0 % 4 + 1 end
        if G.sel ~= s0 then sfx("click"); G.P.hero = G.sel end
        if k.ret or k.space or c.start then
            sfx("click")
            G.new_game()
        elseif c.jev then
            sfx("click")
            local ok = jev:start()
            lclick, rclick = false, false
            if not ok then
                local err = tostring(jev:error() or "Jev failed")
                G.banner_set(err, 6)
                pe_log("[GT] " .. err)
            end
        elseif k.o or c.set_t then open_settings()
        elseif c.quit_app then engine.quit() end
    elseif st == "play" then
        if k.p or k.esc then G.state = "pause"; sfx("click")
        else
            if k.space or k.j or lclick then q.fire = true end
            if k.x or k.sh or k.sh2 or rclick then q.potion = true end
        end
    elseif st == "pause" then
        if k.p or k.esc or k.ret or c.resume then G.state = "play"; sfx("click")
        elseif k.o or c.set_p then open_settings()
        elseif k.qk or c.quit then to_title() end
    elseif st == "over" then
        G.over_t = (G.over_t or 0) + dt
        if G.over_t > 1.2 then
            if k.ret or k.space or c.again then
                sfx("click")
                G.new_game()
            elseif k.esc or c.title then
                to_title()
            end
        end
    end
    st = G.state
    if st == "play" and not G.set_open then
        local mx = (any("Right", "D") and 1 or 0) - (any("Left", "A") and 1 or 0)
        local my = (any("Up", "W") and 1 or 0) - (any("Down", "S") and 1 or 0)
        if (mx ~= 0 or my ~= 0) and (mx ~= mprev.x or my ~= mprev.y) and G.P.alive then sfx("step") end
        mprev.x, mprev.y = mx, my
        if G.autoplay then mx, my, q.fire = G.autoplay_fn() end
        local inp = { mx = mx, my = my }
        acc = acc + dt
        local n = 0
        while acc >= FR and n < 4 do
            inp.fire, inp.potion = q.fire, q.potion; q.fire, q.potion = false, false
            G.level_step(inp, FR)
            acc = acc - FR; n = n + 1
        end
        if acc > FR * 4 then acc = 0 end
        AL = clamp(acc / FR, 0, 1)
        if G.out and G.state == "play" then G.out = false; game_over() end
        G.step_t = (G.step_t or 0) - dt
        if (mx ~= 0 or my ~= 0) and G.step_t <= 0 and G.P.alive then G.step_t = 0.32; sfx("step"); G.dust(WP(G.P.x, G.P.y, 0.03), 3) end
    else AL = 1 end
    render_world(dt)
    update_camera(dt)
    update_lights(dt, G.P.x, G.P.y)
    G.dbg_draw()
    local want_hide = G.state == "play" and not G.set_open
    if want_hide ~= G.cursor_hidden then G.cursor_hidden = want_hide; pcall(input.set_relative_mouse, want_hide) end
end
-- debug autopilot for tests/screenshots only: walks the shortest path to the exit (G.ap_jump: the skip-ahead exit),
-- shooting generators that block the way and monsters that get close
local function ap_path(P, tx, ty)
    local LW = G.LW
    local si, sj, ti, tj = floor(P.x), floor(P.y), floor(tx), floor(ty)
    local prev, q, h = { [sj * LW + si] = -1 }, { sj * LW + si }, 1
    while h <= #q do
        local c = q[h]; h = h + 1
        if c == tj * LW + ti then break end
        local i, j = c % LW, floor(c / LW)
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local ni, nj = i + d[1], j + d[2]; local k = nj * LW + ni
            local ch = G.cell(ni, nj)
            if prev[k] == nil and (not G.solid(ni, nj) or ch == "G") then prev[k] = c; q[#q + 1] = k end
        end
    end
    local c = tj * LW + ti; if prev[c] == nil then return nil end
    local path = {}
    while c ~= -1 do table.insert(path, 1, c); c = prev[c] end
    return path
end
function G.autoplay_fn()
    local P = G.P
    G.ap_t = (G.ap_t or 0) + 1
    local tgt = G.exit
    if G.ap_jump then for _, e in ipairs(G.EXITS) do if e.jump then tgt = e end end end
    if not tgt then return 0, 0, false end
    if G.ap_t % 10 == 1 or not G.ap_path or G.ap_lv ~= G.level then G.ap_path = ap_path(P, tgt.x, tgt.y); G.ap_lv = G.level end
    local best, bd
    for _, m in ipairs(G.MON) do local d = (m.x - P.x) ^ 2 + (m.y - P.y) ^ 2; if not bd or d < bd then best, bd = m, d end end
    if best and bd < 6 and G.ap_t % 8 == 0 then local d = sqrt(bd); P.fx, P.fy = (best.x - P.x) / d, (best.y - P.y) / d; return 0, 0, true end
    local path = G.ap_path; if not path or #path < 1 then return 0, 0, false end
    local LW = G.LW
    local nk = path[min(2, #path)]
    local ni, nj = nk % LW, floor(nk / LW)
    if G.cell(ni, nj) == "G" then
        local dx, dy = ni + 0.5 - P.x, nj + 0.5 - P.y; local d = sqrt(dx * dx + dy * dy)
        P.fx, P.fy = dx / d, dy / d; return 0, 0, G.ap_t % 6 == 0
    end
    if floor(P.x) == ni and floor(P.y) == nj and #path > 2 then table.remove(path, 1); nk = path[2]; ni, nj = nk % LW, floor(nk / LW) end
    local mx, my = ni + 0.5 - P.x, nj + 0.5 - P.y
    local ax = abs(mx) > 0.12 and (mx > 0 and 1 or -1) or 0
    local ay = abs(my) > 0.12 and (my > 0 and 1 or -1) or 0
    return ax, ay, false
end

local jev_source = assert(fs.read("Scripts/jev_auto.lua"), "Missing Scripts/jev_auto.lua")
local JevAuto = assert(load(jev_source, "@Scripts/jev_auto.lua", "t", _ENV))()
jev = JevAuto.attach({
    port = 9139,
    id = "gauntlet-remix",
    description = "Gauntlet Remix. North is +y and east is +x. The offered action walks toward the nearest monster and shoots. Prefer the higher action score.",
    playing = function()
        return G.state == "play" and not G.set_open
    end,
    terminal = function()
        return G.state == "over"
    end,
    score = function()
        return G.score or 0
    end,
    busy = function()
        return false
    end,
    human_edge = human_edge,
    observe = function()
        local hx, hy, mx, my = nearest_monster()
        return {
            hero_x = hx,
            hero_y = hy,
            monster_x = mx,
            monster_y = my,
            health = G.health or 0,
            score = G.score or 0,
        }
    end,
    actions = function()
        local hx, hy, mx, my = nearest_monster()
        local dx = mx - hx
        local dy = my - hy
        if dx == 0 and dy == 0 then
            return { { id = "n", description = "Walk north and shoot.", score = 1 } }
        end
        local best_id = "n"
        local best = -1e18
        for id, step in pairs(JEV_MOVE) do
            if id ~= "stop" then
                local dot = step[1] * dx + step[2] * dy
                if dot > best then
                    best = dot
                    best_id = id
                end
            end
        end
        return { { id = best_id, description = "Walk toward the monster and shoot.", score = best } }
    end,
    apply = apply_jev,
    reset = function(seed)
        clear_jev_input()
        math.randomseed(seed)
        new_game()
    end,
    on_human = clear_jev_input,
})
G.new_game = function()
    jev:begin_human()
    new_game()
end

------------------------------------------------------------------ boot
build_lights()
paint_templates()
build_world()
to_title()
G.update = update; G.SET = SET
hooks { update = update }
pe_log("[GT] ready")
