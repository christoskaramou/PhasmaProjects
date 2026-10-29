------------------------------------------------------------------ menu screens: title, level select, camp (shop / gems / army board), pause, win, lose
do
local U = G.UI
local M = G.M
local US = U.US
local SCR = {}
G.SCR = SCR
local fmt = G.HUD.fmt
local WCOL = { { .35, .75, .35, 1 }, { .95, .7, .35, 1 }, { .45, .7, .95, 1 }, { .9, .45, .4, 1 } }
local WNAME = { "Meadow", "Dunes", "Glacier", "Ember" }
SCR.WCOL = WCOL

local function dim(a) U.rect("dim", 0, 0, SW, SH, { .05, .12, .3, a or 0.35 }, 0, 1) end
local function pills()
    U.pill("mc", 28 * US, 26 * US, 210, "coin", fmt(M.D.coins), 30)
    U.pill("mg", 252 * US, 26 * US, 150, "gem", fmt(M.D.gems), 30)
end
local function ribbon(id, text, cx, cy, w, col, fs)
    w = w * US
    local h = 96 * US
    U.rect(id .. "s", cx - w / 2 + 6 * US, cy - h / 2 + 10 * US, w, h, { .05, .1, .25, .3 }, 30, 19.5)
    U.rect(id .. "l", cx - w / 2, cy - h / 2 + 8 * US, w, h, { col[1] * .6, col[2] * .6, col[3] * .6, 1 }, 30, 19.6)
    U.rect(id, cx - w / 2, cy - h / 2, w, h, col, 30, 19.7)
    U.rect(id .. "h", cx - w / 2 + 12 * US, cy - h / 2 + 6 * US, w - 24 * US, h * 0.36, { 1, 1, 1, .22 }, 20, 19.8)
    U.big(id .. "t", text, cx, cy, fs or 3.6, { 1, 1, 1, 1 }, 3, 20)
end
SCR.ribbon = ribbon

-- title ------------------------------------------------------------------------------------------
function SCR.title(dt)
    local act
    pills()
    local t = G.t
    local bob = sin(t * 2) * 6 * US
    U.big("logo2", "Crowd", SW / 2, 190 * US + bob, 8.5, { .35, .7, 1, 1 }, 6, 20)
    U.big("logo1", "Master", SW / 2, 330 * US + bob, 9.5, { 1, .82, .25, 1 }, 6, 20)
    U.text("logo3", "Run  ·  Merge  ·  Conquer", SW / 2 - 400 * US, 420 * US, 800 * US, 50 * US, 2.0, { 1, 1, 1, .95 }, "center", 20)
    local nx = M.D.unlocked
    local y0 = 560 * US
    if U.button("t_play", "Play", SW / 2, y0, 420, 110, "green", { fs = 4.2 }) then act = "play" end
    U.text("t_play_s", "Level " .. min(nx, #G.LEVELS), SW / 2 - 200 * US, y0 + 66 * US, 400 * US, 40 * US, 1.5, { 1, 1, 1, .95 }, "center", 21)
    if U.button("t_lv", "Levels", SW / 2 - 140 * US, y0 + 150 * US, 260, 84, "blue") then act = "levels" end
    if U.button("t_shop", "Shop", SW / 2 + 140 * US, y0 + 150 * US, 260, 84, "orange") then act = "camp" end
    if U.button("t_opt", "Options", SW / 2 - 140 * US, y0 + 260 * US, 260, 84, "white") then act = "options" end
    if U.button("t_quit", "Quit", SW / 2 + 140 * US, y0 + 260 * US, 260, 84, "red") then act = "quit" end
    U.text("t_help", "Mouse Or Arrows + Enter", SW / 2 - 300 * US, SH - 60 * US, 600 * US, 40 * US, 1.3, { 1, 1, 1, .8 }, "center", 20)
    return act
end

-- level select -----------------------------------------------------------------------------------
function SCR.levels(dt)
    local act
    dim(0.3); pills()
    ribbon("lv_r", "Choose A Level", SW / 2, 120 * US, 640, { .3, .6, 1, 1 })
    local cw, ch, gx, gy = 330, 190, 26, 26
    local cols = 4
    local x0 = SW / 2 - (cols * cw + (cols - 1) * gx) * US / 2
    local y0 = 210 * US
    for i, L in ipairs(G.LEVELS) do
        local c, r = (i - 1) % cols, floor((i - 1) / cols)
        local x, y = x0 + c * (cw + gx) * US, y0 + r * (ch + gy) * US
        local cx, cy = x + cw * US / 2, y + ch * US / 2
        local locked = i > M.D.unlocked
        local wc = WCOL[L.world] or WCOL[1]
        local id = "lv" .. i
        if U.button(id, "", cx, cy, cw, ch, locked and "grey" or "white", { r = 24, z = 20 }) and not locked then act = i end
        U.rect(id .. "_band", cx - cw * US / 2 + 10 * US, cy - ch * US / 2 + 10 * US, cw * US - 20 * US, 54 * US, locked and { .55, .58, .65, 1 } or wc, 18, 20.25)
        U.text(id .. "_n", tostring(i), cx - cw * US / 2 + 10 * US, cy - ch * US / 2 + 10 * US, 70 * US, 54 * US, 2.5, { 1, 1, 1, 1 }, "center", 20.4)
        U.text(id .. "_w", WNAME[L.world] or "", cx - cw * US / 2 + 70 * US, cy - ch * US / 2 + 10 * US, cw * US - 90 * US, 54 * US, 1.4, { 1, 1, 1, .95 }, "right", 20.4, false)
        U.text(id .. "_nm", L.name, cx - cw * US / 2, cy - 18 * US, cw * US, 50 * US, 1.75, locked and { 1, 1, 1, .9 } or { .15, .22, .42, 1 }, "center", 20.4, false)
        if locked then
            U.img(id .. "_lk", "lock", cx, cy + 50 * US, 56, 20.5, { 1, 1, 1, .9 })
        else
            local b = M.D.best[i]
            for s = 1, 3 do U.star(id .. "_s" .. s, cx + (s - 2) * 56 * US, cy + 52 * US - (s == 2 and 8 * US or 0), s == 2 and 54 or 46, b and b.stars >= s, 20.5) end
            if L.boss then U.img(id .. "_bs", "man_r", cx + cw * US / 2 - 40 * US, cy + 50 * US, 50, 20.5) end
        end
    end
    if U.button("lv_back", "Back", 150 * US, SH - 80 * US, 220, 80, "white") or U.K.back then act = "back" end
    return act
end

-- camp: Upgrades / Gems / Army -------------------------------------------------------------------
SCR.tab = "Upgrades"
local drag = nil   -- army board drag {from, x, y}
local sel = nil    -- click-to-merge selection
local note = nil
local function say(text, col) note = { text = text, col = col or { .15, .22, .42, 1 }, t = 0 } end
SCR.say = say
local function upgrade_card(id, u, x, y, w, h, gem)
    local lv = gem and M.glvl(u.id) or M.lvl(u.id)
    U.card(id, x, y, w, h, { 1, 1, 1, .97 }, 12)
    U.text(id .. "_n", u.name, x + 24 * US, y + 14 * US, w - 48 * US, 50 * US, 2.0, { .15, .22, .42, 1 }, "left", 12.5, false)
    U.text(id .. "_d", u.desc, x + 24 * US, y + 62 * US, w - 48 * US, 40 * US, 1.25, { .35, .42, .58, 1 }, "left", 12.5, false)
    -- level pips
    local pw = (w - 48 * US - (u.max - 1) * 6 * US) / u.max
    for k = 1, u.max do
        U.rect(id .. "_p" .. k, x + 24 * US + (k - 1) * (pw + 6 * US), y + 112 * US, pw, 16 * US, k <= lv and (gem and { .9, .35, .85, 1 } or { .3, .7, 1, 1 }) or { .86, .89, .94, 1 }, 8, 12.5)
    end
    local maxed = lv >= u.max
    local cost = gem and M.gcost(u) or M.cost(u)
    local can = not maxed and ((gem and M.D.gems or M.D.coins) >= cost)
    local bx, by = x + w / 2, y + h - 52 * US
    local label = maxed and "Max" or ""
    local kind = maxed and "grey" or (can and (gem and "purple" or "green") or "grey")
    local hit = U.button(id .. "_b", label, bx, by, (w / US) - 60, 72, kind, { z = 14, disabled = false })
    if not maxed then
        U.icon_label(id .. "_bl", "", gem and "gem" or "coin", fmt(cost), bx, by - 2 * US, 3.1, 14.4, { 1, 1, 1, 1 }, true)
    end
    if hit then
        if maxed then say("Already Maxed") 
        elseif (gem and M.gbuy(u)) or (not gem and M.buy(u)) then sfx("buy"); say(u.name .. " Upgraded!", { .2, .6, .25, 1 }); G.FX.confetti(LX(C.cx), 2, C.cz + 2, 20)
        else sfx("deny"); say(gem and "Not Enough Gems" or "Not Enough Coins", { .8, .25, .2, 1 }) end
    end
end
local TIERN = { "Pawn", "Brute", "Giant" }
local TIMG = { "man_b", "man_v", "man_y" }
local function board(x0, y0)
    local sz, gap = 132, 14
    local B = M.D.board
    local rects = {}
    local hover
    for i = 1, 15 do
        local c, r = (i - 1) % 5, floor((i - 1) / 5)
        local x, y = x0 + c * (sz + gap) * US, y0 + r * (sz + gap) * US
        local cx, cy = x + sz * US / 2, y + sz * US / 2
        local t = B[i]
        rects[i] = { x, y, sz * US, sz * US }
        local id = "bd" .. i
        local kind = (sel == i) and "gold" or (t == 0 and "white" or ({ "blue", "purple", "orange" })[t])
        local hit = U.button(id, "", cx, cy, sz, sz, kind, { r = 26, z = 12 })
        if U.inside(x, y, sz * US, sz * US) then hover = i end
        if t > 0 and not (drag and drag.from == i and drag.moved) then
            U.img(id .. "_m", TIMG[t] , cx, cy - 8 * US, 70 + t * 16, 13)
            U.text(id .. "_t", TIERN[t], x, y + sz * US - 40 * US, sz * US, 32 * US, 1.2, { 1, 1, 1, 1 }, "center", 13.1)
        elseif t == 0 then U.text(id .. "_t", "+", x, y, sz * US, sz * US, 3, { .7, .75, .85, 1 }, "center", 13.1, false) end
        -- keyboard: Enter selects, Enter on another slot merges / moves. mouse click on an empty slot moves the selection
        if U.activate == id then
            if sel and sel ~= i then local r = M.merge(sel, i); SCR.merged(r, i); sel = nil
            elseif t > 0 then sel = (sel == i) and nil or i end
        elseif hit and U.MS.click and t == 0 and sel then local r = M.merge(sel, i); SCR.merged(r, i); sel = nil end
    end
    -- mouse drag-to-merge (press on a unit, release on a slot). a click without moving selects / merges into the selection
    local MS = U.MS
    if MS.click and hover and B[hover] > 0 and not drag then drag = { from = hover, moved = false } end
    if drag then
        if MS.down and (abs(MS.x - (MS.px or MS.x)) + abs(MS.y - (MS.py or MS.y)) > 12 * US) then drag.moved = true end
        if drag.moved and B[drag.from] > 0 then U.img("drag_m", TIMG[B[drag.from]], MS.x, MS.y, 100 + B[drag.from] * 16, 60) end
        if MS.release or not MS.down then
            if drag.moved then
                if hover and hover ~= drag.from then local r = M.merge(drag.from, hover); SCR.merged(r, hover) end
                sel = nil
            else
                if sel and sel ~= drag.from then local r = M.merge(sel, drag.from); SCR.merged(r, drag.from); sel = nil
                elseif sel == drag.from then sel = nil else sel = drag.from; sfx("hover") end
            end
            drag = nil
        end
    end
    return rects
end
function SCR.merged(r, at)
    if r == "merge" then sfx("merge"); say(TIERN[M.D.board[at]] .. " Forged!", { .55, .3, .9, 1 }); G.punch(2, 0.3)
    elseif r == "move" or r == "swap" then sfx("click") else sfx("deny") end
end
function SCR.camp(dt)
    local act
    dim(0.38); pills()
    ribbon("cp_r", "Camp", SW / 2, 100 * US, 420, { 1, .62, .2, 1 })
    -- tabs
    local tabs = { "Upgrades", "Gems", "Army" }
    for i, tname in ipairs(tabs) do
        local on = SCR.tab == tname
        if U.button("tab" .. i, tname, SW / 2 + (i - 2) * 260 * US, 205 * US, 240, 70, on and "blue" or "white", { z = 15 }) then SCR.tab = tname; sel = nil end
    end
    local px, py, pw = SW / 2 - 820 * US, 270 * US, 1640 * US
    if SCR.tab == "Upgrades" or SCR.tab == "Gems" then
        local list = SCR.tab == "Upgrades" and M.UP or M.GEM
        local cols = SCR.tab == "Upgrades" and 3 or 2
        local cw = (pw - (cols - 1) * 26 * US) / cols
        local ch = 250 * US
        for i, u in ipairs(list) do
            local c, r = (i - 1) % cols, floor((i - 1) / cols)
            upgrade_card("up" .. i, u, px + c * (cw + 26 * US), py + r * (ch + 26 * US), cw, ch, SCR.tab == "Gems")
        end
    else
        -- army board + info
        U.card("arm_bg", px, py, 760 * US, 500 * US, { 1, 1, 1, .5 }, 10)
        board(px + 22 * US, py + 22 * US)
        local ix = px + 790 * US
        U.card("arm_info", ix, py, pw - 790 * US, 500 * US, { 1, 1, 1, .97 }, 10)
        local a = G.army_counts()
        local lines = {
            "Drag A Unit Onto A Twin To Merge",
            "Pawn  =  2 Runners At The Start",
            "Brute  =  Power 3  ·  Takes 2 Hits",
            "Giant  =  Power 8  ·  Takes 4 Hits",
            "Big Units Shrug Off Traps And Wreck Bosses,",
            "But Plus Gates Only Add Pawns.",
        }
        for i, l in ipairs(lines) do U.text("arm_l" .. i, l, ix + 30 * US, py + (14 + (i - 1) * 46) * US, pw - 850 * US, 44 * US, i == 1 and 1.75 or 1.45, i == 1 and { .15, .22, .42, 1 } or { .35, .42, .58, 1 }, "left", 10.5, false) end
        U.text("arm_sum", "Starts With  " .. (G.start_pawns() + a[1]) .. " Pawns  ·  " .. a[2] .. " Brutes  ·  " .. a[3] .. " Giants", ix + 30 * US, py + 300 * US, pw - 850 * US, 44 * US, 1.6, { .25, .5, .95, 1 }, "left", 10.5, false)
        local rc = M.recruit_cost()
        local rx, ry = ix + 230 * US, py + 420 * US
        if U.button("arm_rec", "", rx, ry, 380, 84, M.D.coins >= rc and "green" or "grey", { z = 14 }) then
            local ok, why = M.recruit()
            if ok then sfx("buy"); say("A New Pawn Joins!", { .2, .6, .25, 1 }) else sfx("deny"); say(why, { .8, .25, .2, 1 }) end
        end
        U.icon_label("arm_rec_l", "Recruit", "coin", fmt(rc), rx, ry - 2 * US, 3.2, 14.4, { 1, 1, 1, 1 }, true)
        if U.button("arm_auto", "Auto Merge", ix + 640 * US, py + 420 * US, 340, 84, "purple", { z = 14 }) then
            local r, at = M.auto_merge(); if r then SCR.merged(r, at) else sfx("deny"); say("No Twins To Merge", { .8, .25, .2, 1 }) end
        end
    end
    -- treasury
    local bank = floor(M.D.bank or 0)
    local ty = SH - 150 * US
    U.card("tre", SW / 2 - 820 * US, ty - 56 * US, 640 * US, 112 * US, { 1, 1, 1, .97 }, 10)
    U.coin_icon("tre_i", SW / 2 - 770 * US, ty, 56, 10.5)
    U.text("tre_t", "Treasury  " .. bank .. " / " .. floor(60 + 120 * M.lvl("bank")), SW / 2 - 730 * US, ty - 50 * US, 360 * US, 100 * US, 1.7, { .15, .22, .42, 1 }, "left", 10.5, false)
    if U.button("tre_b", "Collect", SW / 2 - 300 * US, ty, 200, 76, bank > 0 and "gold" or "grey", { z = 14 }) then
        if bank > 0 then local n = M.collect(); sfx("coin"); say("+" .. n .. " Coins Collected", { .7, .5, .05, 1 }) else sfx("deny"); say("Treasury Is Empty - Upgrade It To Earn While You Play", { .8, .25, .2, 1 }) end
    end
    if U.button("cp_next", "Next Level", SW / 2 + 620 * US, ty, 340, 96, "green", { fs = 3 }) then act = "next" end
    if U.button("cp_menu", "Menu", SW / 2 + 330 * US, ty, 200, 80, "white") or U.K.back then act = "back" end
    -- feedback note
    if note then
        note.t = note.t + dt
        if note.t > 2.2 then note = nil else
            local a = clamp((2.2 - note.t) * 3, 0, 1)
            local w = (#note.text * 20 + 100) * US
            U.rect("note_b", SW / 2 - w / 2, 236 * US + 520 * US, w, 64 * US, { 1, 1, 1, .95 * a }, 32, 50)
            U.text("note_t", note.text, SW / 2 - w / 2, 236 * US + 520 * US, w, 64 * US, 1.8, { note.col[1], note.col[2], note.col[3], a }, "center", 50.1, false)
        end
    end
    return act
end

-- pause --------------------------------------------------------------------------------------------
function SCR.pause(dt)
    local act
    dim(0.45)
    local w, h = 560 * US, 600 * US
    U.card("pz", SW / 2 - w / 2, SH / 2 - h / 2, w, h, { 1, 1, 1, .97 }, 15)
    ribbon("pz_r", "Paused", SW / 2, SH / 2 - h / 2, 480, { .3, .6, 1, 1 })
    if U.button("pz_res", "Resume", SW / 2, SH / 2 - 120 * US, 380, 92, "green", { fs = 4 }) or U.K.back or U.K.pause then act = "resume" end
    if U.button("pz_ret", "Retry", SW / 2, SH / 2 - 5 * US, 380, 80, "blue") then act = "retry" end
    if U.button("pz_opt", "Options", SW / 2, SH / 2 + 100 * US, 380, 80, "purple") then act = "options" end
    if U.button("pz_menu", "Menu", SW / 2, SH / 2 + 205 * US, 380, 80, "orange") then act = "menu" end
    return act
end

-- win / lose cards -----------------------------------------------------------------------------------
SCR.res = nil   -- { won, tally, t, L }
function SCR.result(dt)
    local S = SCR.res
    S.t = S.t + dt
    local act
    dim(0.4)
    local w, h = 820 * US, 820 * US
    local x, y = SW / 2 - w / 2, SH / 2 - h / 2 + 30 * US
    local pop = clamp(S.t * 4, 0, 1)
    U.card("rs", x, y, w, h, { 1, 1, 1, .97 }, 15)
    local T = S.tally
    if S.won then
        ribbon("rs_r", "Level Complete!", SW / 2, y, 640, { .3, .78, .35, 1 })
        for s = 1, 3 do
            local on = T.stars >= s and S.t > 0.3 + s * 0.25
            if on and not S["st" .. s] then S["st" .. s] = true; sfx("trophy"); G.punch(1.5, 0.2) end
            local sp = on and (1 + 0.5 * max(0, 1 - (S.t - 0.3 - s * 0.25) * 6)) or 1
            U.star("rs_s" .. s, SW / 2 + (s - 2) * 150 * US, y + 150 * US - (s == 2 and 22 * US or 0), (s == 2 and 140 or 116) * sp, on, 16)
        end
        local R0 = S.res
        local head = R0.kind == "boss" and "The King Has Fallen!" or ("Climbed " .. R0.k .. " Steps  ·  x" .. string.format("%.1f", R0.mult))
        U.text("rs_h", head, x, y + 230 * US, w, 50 * US, 2.2, { .15, .22, .42, 1 }, "center", 16, false)
    else
        ribbon("rs_r", "Crowd Lost!", SW / 2, y, 560, { .95, .35, .3, 1 })
        local k = clamp(S.prog or 0, 0, 1)
        U.text("rs_h", "You Made It " .. floor(k * 100) .. "% Of The Way", x, y + 110 * US, w, 50 * US, 2.2, { .15, .22, .42, 1 }, "center", 16, false)
        U.rect("rs_pb", x + 120 * US, y + 180 * US, w - 240 * US, 26 * US, { .86, .89, .94, 1 }, 13, 16)
        U.rect("rs_pf", x + 124 * US, y + 184 * US, max(18 * US, (w - 248 * US) * k), 18 * US, { .95, .4, .35, 1 }, 9, 16.1)
        U.text("rs_tip", S.hint or "", x + 40 * US, y + 220 * US, w - 80 * US, 50 * US, 1.5, { .35, .42, .58, 1 }, "center", 16, false)
        local st = G.RUN.stats or {}
        local chips = { { "Biggest Crowd", st.peak or 0, { .25, .55, 1, 1 } }, { "Gates", st.gates or 0, { .3, .75, .35, 1 } }, { "Enemies Beaten", st.kills or 0, { .95, .4, .35, 1 } } }
        local cw = (w - 160 * US) / 3
        for i, c in ipairs(chips) do
            local cx = x + 60 * US + (i - 1) * (cw + 20 * US)
            U.rect("rs_cb" .. i, cx, y + 290 * US, cw, 120 * US, { .95, .96, 1, 1 }, 22, 16)
            U.text("rs_cv" .. i, fmt(c[2]), cx, y + 295 * US, cw, 64 * US, 3.0, c[3], "center", 16.1, false)
            U.text("rs_cl" .. i, c[1], cx, y + 357 * US, cw, 40 * US, 1.4, { .35, .42, .58, 1 }, "center", 16.1, false)
        end
    end
    -- tally lines roll in
    local ly = y + (S.won and 300 or 430) * US
    local shown = floor((S.t - 0.4) / 0.18)
    for i, l in ipairs(T.lines) do
        if i <= shown then
            if not S["ln" .. i] then S["ln" .. i] = true; sfx("coin") end
            local yy = ly + (i - 1) * 46 * US
            U.text("rs_l" .. i, l[1], x + 90 * US, yy, w * 0.6, 44 * US, 1.7, { .3, .38, .55, 1 }, "left", 16, false)
            U.text("rs_v" .. i, "+" .. fmt(l[2]), x + w * 0.55, yy, w * 0.45 - 140 * US, 44 * US, 1.8, { .85, .55, .05, 1 }, "right", 16, false)
            U.coin_icon("rs_c" .. i, x + w - 110 * US, yy + 22 * US, 34, 16.2)
        end
    end
    if shown >= #T.lines then
        local yy = y + h - 230 * US
        U.rect("rs_tb", x + 60 * US, yy - 8 * US, w - 120 * US, 70 * US, { .95, .96, 1, 1 }, 26, 16)
        U.text("rs_tt", "Total", x + 90 * US, yy - 8 * US, 200 * US, 70 * US, 2.2, { .15, .22, .42, 1 }, "left", 16.2, false)
        U.coin_icon("rs_ti", x + 330 * US, yy + 27 * US, 48, 16.3)
        U.text("rs_tv", "+" .. fmt(T.coins), x + 360 * US, yy - 8 * US, 200 * US, 70 * US, 2.6, { .85, .55, .05, 1 }, "left", 16.2, false)
        if T.gems > 0 then
            U.gem_icon("rs_gi", x + 580 * US, yy + 27 * US, 44, 16.3)
            U.text("rs_gv", "+" .. T.gems, x + 610 * US, yy - 8 * US, 120 * US, 70 * US, 2.6, { .8, .25, .75, 1 }, "left", 16.2, false)
        end
        if S.won then
            U.text("rs_sc", "Score " .. fmt(T.score) .. (T.new_best and "   New Best!" or ""), x, yy - 70 * US, w, 50 * US, 1.8, T.new_best and { .95, .5, .1, 1 } or { .35, .42, .58, 1 }, "center", 16, false)
            if T.perfect_run then U.text("rs_pr", "Flawless Run  +1 Gem", x, yy - 112 * US, w, 44 * US, 1.6, { .8, .25, .75, 1 }, "center", 16, false) end
        end
    end
    -- buttons
    local by = y + h - 70 * US
    if S.won then
        local last = (S.L.idx >= #G.LEVELS)
        local nx = SW / 2 - 265 * US
        if U.button("rs_next", last and "Replay" or "Next", SW / 2 - 269 * US, by, 210, 92, "green", { fs = 3.6 }) then act = "next" end
        if U.button("rs_shop", "Shop", SW / 2 - 63 * US, by, 170, 80, "orange") then act = "camp" end
        if U.button("rs_retry", "Retry", SW / 2 + 123 * US, by, 170, 80, "blue") then act = "retry" end
        if U.button("rs_menu", "Menu", SW / 2 + 299 * US, by, 150, 80, "purple") or U.K.back then act = "menu" end
    else
        if U.button("rs_retry", "Retry", SW / 2 - 200 * US, by, 240, 92, "green", { fs = 3.8 }) then act = "retry" end
        if U.button("rs_shop", "Shop", SW / 2 + 30 * US, by, 190, 80, "orange") then act = "camp" end
        if U.button("rs_menu", "Menu", SW / 2 + 220 * US, by, 160, 80, "purple") or U.K.back then act = "menu" end
    end
    return act
end
end
