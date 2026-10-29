------------------------------------------------------------------ 07_hud: region badges, top strength bar, ability tray, tooltips, toasts + menu screens
do
local U, D, SIM = G.UI, G.D, G.SIM
local US = U.US
local HUD = { toasts = {}, zones = {} }
G.HUD = HUD
local function fmt(n)
    n = floor((n or 0) + 0.5)
    local s = tostring(abs(n))
    local o = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if o:sub(1, 1) == "," then o = o:sub(2) end
    return (n < 0 and "-" or "") .. o
end
HUD.fmt = fmt
local function mmss(t) t = floor(t or 0); return string.format("%d:%02d", floor(t / 60), t % 60) end
HUD.mmss = mmss
local TCOL = { gold = { 1, .78, .2, 1 }, orange = { 1, .58, .18, 1 }, blue = { .35, .7, 1, 1 }, red = { 1, .35, .3, 1 }, grey = { .8, .84, .9, 1 }, green = { .4, .95, .45, 1 } }
local WHITE = { 1, 1, 1, 1 }
local INK = { .24, .16, .08, 1 }
local PARCH = { .98, .94, .84, .97 }
local WOOD = { .23, .15, .09, .92 }
HUD.INK, HUD.PARCH, HUD.WOOD = INK, PARCH, WOOD
local function fc(f, a) local c = D.FAC[f].col; return { c[1], c[2], c[3], a or 1 } end
local function sh(c, k, a) return { c[1] * k, c[2] * k, c[3] * k, a or c[4] or 1 } end
HUD.fc = fc

function HUD.reset() HUD.toasts, HUD.ban, HUD.hnt = {}, nil, nil end
function HUD.toast(txt, col, icon, key)
    for _, t in ipairs(HUD.toasts) do if t.txt == txt or (key and t.key == key) then t.txt = txt; t.t = math.min(t.t, 0.2); return end end
    table.insert(HUD.toasts, 1, { txt = txt, col = TCOL[col] or TCOL.gold, icon = icon, t = 0, key = key })
    if #HUD.toasts > 3 then HUD.toasts[4] = nil end
end
function HUD.banner(a, b, col) HUD.ban = { a = a, b = b, t = 0, col = col } end
function HUD.hint(txt) HUD.hnt = { txt = txt, t = 0 } end

-- screen zones the HUD owns this frame (map clicks inside them are ignored)
local function zone(x, y, w, h) HUD.zones[#HUD.zones + 1] = { x, y, w, h } end
function HUD.over()
    for _, z in ipairs(HUD.zones) do if U.inside(z[1], z[2], z[3], z[4]) then return true end end
    return false
end

-- floating troop badges over every region
-- ocean / neighbour captions printed on the sea (tools/gen_maps.py sea_labels), e.g. New Zealand's Tasman Sea and the way to Australia
local function sea_labels(S)
    local sea = S.M and S.M.sea
    if not sea then return end
    for k, q in ipairs(sea) do
        local sx, sy, zc = project(q.x, 0.05, q.z)
        if zc > 0.3 and sx > -300 and sx < SW + 300 and sy > -40 and sy < SH + 40 then
            local fs = clamp(70 / zc, 1.5, 2.6) * q.k
            U.text("sea" .. k, q.t, sx - 300 * US, sy - 24 * US, 600 * US, 48 * US, fs, { .86, .95, 1, .62 }, "center", 4, true)
        end
    end
end
function HUD.badges(S, sel, hov, tgt, focus)
    sea_labels(S)
    for i, r in ipairs(S.R) do
        if r.active then
            local sx, sy, zc = project(r.x, r.h + 0.55, r.z)
            if zc > 0.3 and sx > -80 and sx < SW + 80 and sy > -60 and sy < SH + 60 then
                local s = clamp(30 / zc, 0.62, 1.25)
                local hitk = clamp(1 - (S.t - r.hit) / 0.25, 0, 1)
                sx = sx + math.sin(G.t * 60) * 3 * US * hitk
                local pop = 1 + r.flash * 0.35
                s = s * pop
                local n = floor(r.n)
                local txt = tostring(n)
                local w, h = (30 + 14 * #txt) * s * US, 38 * s * US
                local col = fc(r.owner)
                if r.owner == 0 then col = { .52, .49, .44, 1 } end
                local ring = sel[i] and { 1, 1, 1, 1 } or ((tgt == i or focus == i) and { 1, .84, .3, 1 } or sh(col, 0.45, 0.95))
                local bw = (sel[i] or tgt == i or focus == i) and 4 * US or 2.5 * US
                U.rect("bo" .. i, sx - w / 2 - bw, sy - h / 2 - bw, w + 2 * bw, h + 2 * bw, ring, h / US / 2 + 3, 6)
                U.rect("bb" .. i, sx - w / 2, sy - h / 2, w, h, col, h / US / 2, 6.1)
                U.rect("bh" .. i, sx - w / 2 + 4 * US, sy - h / 2 + 3 * US, w - 8 * US, h * 0.4, { 1, 1, 1, .2 }, h / US / 3, 6.15)
                if r.frozen > 0 then U.rect("bf" .. i, sx - w / 2, sy - h / 2, w, h, { .75, .92, 1, .55 }, h / US / 2, 6.2) end
                U.text("bt" .. i, txt, sx - w / 2, sy - h / 2, w, h, 1.6 * s, WHITE, "center", 6.3)
                -- fill gauge (troops vs cap) under the pill
                if r.owner > 0 then
                    local k = clamp(r.n / r.cap, 0, 1)
                    local gw = w * 0.8
                    U.rect("bg" .. i, sx - gw / 2, sy + h / 2 + 3 * US, gw, 5 * US * s, { .1, .07, .04, .55 }, 3, 6)
                    U.rect("bk" .. i, sx - gw / 2, sy + h / 2 + 3 * US, max(2, gw * k), 5 * US * s, k >= 0.99 and { 1, .85, .3, 1 } or { 1, 1, 1, .9 }, 3, 6.05)
                end
                -- neutral regrowth gauge (garrison vs starting garrison): green while regrowing, grey while paused after a hit
                if r.owner == 0 and r.n0 and r.n < r.n0 - 0.01 then
                    local k = clamp(r.n / r.n0, 0, 1)
                    local gw = w * 0.8
                    U.rect("bg" .. i, sx - gw / 2, sy + h / 2 + 3 * US, gw, 5 * US * s, { .1, .07, .04, .55 }, 3, 6)
                    U.rect("bk" .. i, sx - gw / 2, sy + h / 2 + 3 * US, max(2, gw * k), 5 * US * s, r.regen and { .45, .95, .5, 1 } or { .8, .78, .74, .9 }, 3, 6.05)
                end
                if r.ty ~= "town" then U.img("bi" .. i, "t_" .. r.ty, sx - w / 2 - 12 * s * US, sy - 2 * US, 34 * s, 6.4) end
            end
        end
    end
end

-- tooltip for the hovered region
function HUD.tip(S, i)
    local r = S.R[i]
    if not r then return end
    local x, y, w, h = 24 * US, SH - 236 * US, 430 * US, 212 * US
    U.card("tp", x, y, w, h, PARCH, 40)
    local own = D.FAC[r.owner]
    U.rect("tpb", x, y, w, 52 * US, r.owner == 0 and { .55, .52, .46, 1 } or fc(r.owner), 30, 40.1)
    U.text("tpn", r.name, x + 18 * US, y, w - 36 * US, 52 * US, 1.8, WHITE, "left", 40.3)
    U.text("tpo", own.short or own.name, x + 18 * US, y, w - 36 * US, 52 * US, 1.3, { 1, 1, 1, .9 }, "right", 40.3, false)
    local tl = D.TYPE_DESC[r.ty] or "Town"
    if r.hill then tl = tl .. "  ·  Hills: troops march 20% slower" end
    U.text("tpd", tl, x + 18 * US, y + 58 * US, w - 36 * US, 56 * US, 1.12, { .4, .3, .2, 1 }, "left", 40.3, false)
    local rate = r.owner > 0 and r.prod * S.F[r.owner].prodmul * S.F[r.owner].rb * (1 + 0.06 * S.F[r.owner].mines) or 0
    U.text("tp1", "Troops", x + 18 * US, y + 112 * US, 200 * US, 40 * US, 1.35, { .45, .35, .25, 1 }, "left", 40.3, false)
    U.text("tp1v", floor(r.n) .. " / " .. floor(r.owner == 0 and (r.n0 or r.n) or r.cap), x + 200 * US, y + 112 * US, w - 218 * US, 40 * US, 1.5, INK, "right", 40.3, false)
    U.text("tp2", "Recruits", x + 18 * US, y + 148 * US, 200 * US, 40 * US, 1.35, { .45, .35, .25, 1 }, "left", 40.3, false)
    U.text("tp2v", r.owner > 0 and string.format("+%.1f / s", rate) or ((r.n0 and r.n < r.n0 - 0.01) and (r.regen and string.format("+%.2f / s", D.NREGEN) or "paused") or "-"), x + 200 * US, y + 148 * US, w - 218 * US, 40 * US, 1.5, INK, "right", 40.3, false)
    U.text("tp3", string.format("Defence x%.1f", SIM.def(S, r)), x + 18 * US, y + 176 * US, w - 36 * US, 34 * US, 1.15, { .45, .35, .25, 1 }, "left", 40.3, false)
end

-- top bar: level, clock, faction strength
function HUD.top(S, demo)
    local act
    local bw = 820 * US
    local x0 = SW / 2 - bw / 2
    local y0 = 18 * US
    local tot = 0
    local list = {}
    for f = 1, 5 do local F = S.F[f]; if not F.absent then local v = max(0, F.troops) + F.nreg * 4; if F.alive then tot = tot + v; list[#list + 1] = { f = f, v = v, F = F } end end end
    U.rect("sb_bg", x0 - 8 * US, y0 - 6 * US, bw + 16 * US, 50 * US, WOOD, 20, 30)
    local x = x0
    for j, e in ipairs(list) do
        local w = tot > 0 and bw * e.v / tot or bw / #list
        if j == #list then w = x0 + bw - x end
        U.rect("sb" .. e.f, x, y0, w, 38 * US, fc(e.f), 14, 30.2)
        U.rect("sbh" .. e.f, x, y0, w, 14 * US, { 1, 1, 1, .18 }, 8, 30.3)
        if w > 90 * US then U.text("sbt" .. e.f, (D.FAC[e.f].short) .. "  " .. e.F.nreg, x, y0, w, 38 * US, 1.25, WHITE, "center", 30.4) end
        x = x + w
    end
    zone(x0 - 8 * US, 0, bw + 16 * US, 70 * US)
    if not demo then
        U.rect("lv_bg", 18 * US, 14 * US, 380 * US, 58 * US, WOOD, 22, 30)
        U.text("lv_t", S.li .. ".  " .. S.L.name, 34 * US, 14 * US, 260 * US, 58 * US, 1.45, { 1, .9, .7, 1 }, "left", 30.2)
        U.text("lv_c", mmss(S.t), 250 * US, 14 * US, 132 * US, 58 * US, 1.6, WHITE, "right", 30.2)
        zone(18 * US, 14 * US, 380 * US, 58 * US)
        if U.button("pz", "II", SW - 64 * US, 44 * US, 76, 64, "white", { nokbd = true, fs = 2.4 }) then act = "pause" end
        zone(SW - 110 * US, 0, 110 * US, 90 * US)
    end
    return act
end

-- bottom tray: 4 abilities + send ratio
function HUD.tray(S, pick, ratio)
    local act
    local n = #D.ABIL
    local sz = 104 * US
    local gap = 18 * US
    local total = n * sz + (n - 1) * gap + 150 * US
    local x0 = SW / 2 - total / 2
    local y0 = SH - sz - 26 * US
    U.rect("tr_bg", x0 - 16 * US, y0 - 12 * US, total + 32 * US, sz + 30 * US, WOOD, 26, 30)
    zone(x0 - 16 * US, y0 - 12 * US, total + 32 * US, sz + 40 * US)
    for k, a in ipairs(D.ABIL) do
        local x = x0 + (k - 1) * (sz + gap)
        local id = "ab" .. k
        local unl = SIM.abil_unlocked(S, k)
        local fr = clamp(SIM.abil_frac(S, 1, k), 0, 1)
        local ready = unl and SIM.abil_ready(S, 1, k)
        local on = pick == k
        local hov = U.inside(x, y0, sz, sz)
        local bc = on and { 1, .85, .3, 1 } or (ready and { .95, .8, .45, .5 + .5 * abs(math.sin(G.t * 3)) } or { .1, .07, .04, 1 })
        U.rect(id .. "o", x - 4 * US, y0 - 4 * US, sz + 8 * US, sz + 8 * US, bc, 22, 30.4)
        U.rect(id .. "b", x, y0, sz, sz, hov and { .46, .34, .22, 1 } or { .36, .26, .16, 1 }, 18, 30.5)
        if unl then
            U.img(id .. "i", a.icon, x + sz / 2, y0 + sz / 2 - 6 * US, 74, 30.7, ready and WHITE or { .6, .6, .6, 1 })
            if not ready then
                local hh = sz * (1 - fr)
                U.rect(id .. "c", x, y0, sz, hh, { .05, .03, .02, .6 }, 18, 30.8)
                local cd = S.F[1].cd[k]
                if cd > 0 then U.text(id .. "t", tostring(math.ceil(cd)), x, y0, sz, sz - 14 * US, 2.4, WHITE, "center", 30.9) end
            end
            U.text(id .. "n", a.name, x - 10 * US, y0 + sz - 26 * US, sz + 20 * US, 26 * US, 0.95, { 1, .95, .85, 1 }, "center", 30.9)
        else
            U.img(id .. "l", "lock", x + sz / 2, y0 + sz / 2 - 8 * US, 46, 30.7, { 1, 1, 1, .7 })
            U.text(id .. "n", "Level " .. a.unlock, x, y0 + sz - 28 * US, sz, 26 * US, 1.0, { 1, .9, .7, .8 }, "center", 30.9)
        end
        U.text(id .. "k", tostring(k), x + 6 * US, y0 + 2 * US, 26 * US, 28 * US, 1.2, { 1, .85, .4, 1 }, "center", 30.95)
        if hov then
            U.card("abtp", x + sz / 2 - 220 * US, y0 - 108 * US, 440 * US, 84 * US, PARCH, 41)
            U.text("abtpn", a.name .. (unl and "" or "  (locked)"), x + sz / 2 - 210 * US, y0 - 106 * US, 420 * US, 38 * US, 1.4, INK, "center", 41.2, false)
            U.text("abtpd", a.desc, x + sz / 2 - 210 * US, y0 - 70 * US, 420 * US, 38 * US, 1.1, { .45, .35, .25, 1 }, "center", 41.2, false)
        end
        if U.MS.click and hov then act = k end
    end
    -- ratio toggle
    local rx = x0 + n * (sz + gap) + 4 * US
    local rhov = U.inside(rx, y0, 130 * US, sz)
    U.rect("ra_o", rx - 4 * US, y0 - 4 * US, 138 * US, sz + 8 * US, { .1, .07, .04, 1 }, 22, 30.4)
    U.rect("ra_b", rx, y0, 130 * US, sz, rhov and { .46, .34, .22, 1 } or { .36, .26, .16, 1 }, 18, 30.5)
    U.text("ra_l", "Send", rx, y0 + 6 * US, 130 * US, 30 * US, 1.1, { 1, .9, .7, .9 }, "center", 30.7)
    U.text("ra_v", ratio >= 1 and "100%" or "50%", rx, y0 + 30 * US, 130 * US, 50 * US, 2.3, ratio >= 1 and WHITE or { 1, .85, .4, 1 }, "center", 30.7)
    U.text("ra_k", "Space", rx, y0 + sz - 28 * US, 130 * US, 26 * US, 0.95, { 1, .9, .7, .7 }, "center", 30.7)
    if U.MS.click and rhov then act = "ratio" end
    return act
end
function HUD.begin() HUD.zones = {} end

-- tutorial card (top centre, under the strength bar)
function HUD.tut(step, i, n)
    if not step then return end
    local w, h = 900 * US, 92 * US
    local x, y = SW / 2 - w / 2, 92 * US
    local bob = math.sin(G.t * 3) * 3 * US
    U.card("tu", x, y + bob, w, h, PARCH, 35)
    U.rect("tub", x, y + bob, 110 * US, h, { .25, .56, .94, 1 }, 30, 35.1)
    U.text("tun", i .. "/" .. n, x, y + bob, 110 * US, h, 2.0, WHITE, "center", 35.3)
    U.text("tut", step.txt, x + 126 * US, y + bob, w - 146 * US, h, 1.35, INK, "left", 35.3, false)
    zone(x, y, w, h)
end

-- targeting hint for an ability
function HUD.pick_hint(k)
    local a = D.ABIL[k]
    local txt = a.name .. ": click a region  ·  Right-click / Esc cancels"
    local w = (#txt * 15 + 80) * US
    U.rect("pk_bg", SW / 2 - w / 2, SH - 200 * US, w, 52 * US, { .9, .6, .15, .9 }, 26, 34)
    U.text("pk_t", txt, SW / 2 - w / 2, SH - 200 * US, w, 52 * US, 1.45, WHITE, "center", 34.2)
end

-- overlays drawn in every state (toasts, banner, hint)
function HUD.overlays(dt)
    -- while a dialog is open (pause / options / win / lose) the battle banner, toasts and hints stay hidden
    local st = G.state
    local modal = st == "pause" or st == "options" or st == "win" or st == "lose"
    for i = #HUD.toasts, 1, -1 do
        local t = HUD.toasts[i]
        t.t = t.t + dt
        if t.t > 2.4 then table.remove(HUD.toasts, i) end
    end
    for i, t in ipairs(modal and {} or HUD.toasts) do
        local a = clamp(min(t.t * 6, (2.4 - t.t) * 3), 0, 1)
        local y = 220 * US + (i - 1) * 60 * US
        local s = 1 + max(0, 0.15 - t.t) * 2
        local w = (#t.txt * 19 + 70) * US
        U.rect("to" .. i, SW - w - 30 * US, y - 24 * US, w, 50 * US, { t.col[1] * .55, t.col[2] * .55, t.col[3] * .55, .85 * a }, 25, 44)
        U.text("tt" .. i, t.txt, SW - w - 30 * US, y - 24 * US, w, 50 * US, 1.6 * s, { 1, 1, 1, a }, "center", 45)
    end
    local b = HUD.ban
    if b then
        b.t = b.t + dt
        if b.t > 3.0 or modal then HUD.ban = nil
        else
            local a = clamp(min(b.t * 4, (3.0 - b.t) * 3), 0, 1)
            local s = 1 + max(0, 0.25 - b.t) * 2
            local c = b.col or { .2, .14, .08 }
            U.rect("ban_bg", 0, SH * 0.34, SW, 170 * US, { c[1], c[2], c[3], .7 * a }, 0, 44)
            U.big("ban_b", b.b or "", SW / 2, SH * 0.34 + 45 * US, 2.2, { 1, .9, .75, a }, 2, 45)
            U.big("ban_a", b.a, SW / 2, SH * 0.34 + 112 * US, 4.8 * s, { 1, 1, 1, a }, 4, 45)
        end
    end
    local h = HUD.hnt
    if h then
        h.t = h.t + dt
        if h.t > 4 or modal then HUD.hnt = nil
        else
            local a = clamp(min(h.t * 4, (4 - h.t) * 2), 0, 1)
            local w = (#h.txt * 16 + 70) * US
            U.rect("hn_bg", SW / 2 - w / 2, SH - 270 * US, w, 54 * US, { .1, .07, .04, .7 * a }, 27, 44)
            U.text("hn_t", h.txt, SW / 2 - w / 2, SH - 270 * US, w, 54 * US, 1.5, { 1, 1, 1, a }, "center", 45)
        end
    end
end

------------------------------------------------------------------ screens
local SCR = {}
G.SCR = SCR
local CCOL = { Europe = { .25, .5, .85, 1 }, Africa = { .88, .55, .18, 1 }, Asia = { .78, .3, .3, 1 }, Oceania = { .2, .62, .6, 1 },
    ["South America"] = { .36, .62, .28, 1 }, ["North America"] = { .45, .38, .75, 1 }, World = { .5, .2, .62, 1 } }
local MCOL = setmetatable({}, { __index = function(_, k) return CCOL[D.CONT[k] or "Europe"] end })
local MNAME = setmetatable({}, { __index = function(_, k) return (BB_MAPS[k] and BB_MAPS[k].title) or k end })
SCR.MNAME = MNAME
SCR.CCOL = CCOL
local function dim(a) U.rect("dim", 0, 0, SW, SH, { .08, .05, .02, a or 0.35 }, 0, 1) end
local function stars_total(sv) local n = 0; for _, v in pairs(sv.stars) do n = n + v end; return n end
local function pills(sv)
    U.pill("mc", SW - 470 * US, 26 * US, 220, "coin", fmt(sv.coins), 30)
    local h = 58 * US
    local x, y = SW - 236 * US, 26 * US
    U.rect("ms", x, y, 200 * US, h, { .1, .07, .04, .55 }, 29, 30)
    U.img("msi", "star", x + 30 * US, y + h / 2, 40, 31)
    U.text("msv", stars_total(sv) .. " / " .. (#D.LEVELS * 3), x + 60 * US, y, 134 * US, h, 1.7, WHITE, "left", 31)
end
local function ribbon(id, text, cx, cy, w, col, fs)
    w = w * US
    local h = 92 * US
    U.rect(id .. "s", cx - w / 2 + 6 * US, cy - h / 2 + 10 * US, w, h, { .1, .05, .02, .3 }, 22, 19.5)
    U.rect(id .. "l", cx - w / 2, cy - h / 2 + 8 * US, w, h, { col[1] * .6, col[2] * .6, col[3] * .6, 1 }, 22, 19.6)
    U.rect(id, cx - w / 2, cy - h / 2, w, h, col, 22, 19.7)
    U.rect(id .. "h", cx - w / 2 + 12 * US, cy - h / 2 + 6 * US, w - 24 * US, h * 0.36, { 1, 1, 1, .2 }, 16, 19.8)
    U.big(id .. "t", text, cx, cy, fs or 3.4, WHITE, 3, 20)
end
SCR.ribbon = ribbon

function SCR.title(dt, sv)
    local act
    pills(sv)
    local bob = math.sin(G.t * 1.6) * 4 * US
    local cx = SW / 2
    -- banner-shaped title card: wood frame, parchment face, two faction pennants
    U.rect("lg_sh", cx - 520 * US, 90 * US, 1040 * US, 300 * US, { .05, .03, .01, .35 }, 40, 17.5)
    U.rect("lg_rim", cx - 530 * US, 66 * US, 1060 * US, 316 * US, { .36, .24, .13, 1 }, 44, 17.7)
    U.rect("lg_bg", cx - 516 * US, 80 * US, 1032 * US, 288 * US, { .98, .93, .8, 1 }, 36, 17.8)
    U.rect("lg_p1", cx - 500 * US, 92 * US, 26 * US, 160 * US, { .25, .56, .94, 1 }, 6, 17.9)
    U.rect("lg_p2", cx + 474 * US, 92 * US, 26 * US, 160 * US, { .88, .28, .25, 1 }, 6, 17.9)
    U.big("lg1", "Banners & Borders", cx, 172 * US + bob, 6.0, { .98, .76, .25, 1 }, 6, 20)
    U.text("lg3", "Muster  ·  March  ·  Hold The Line", cx - 500 * US, 262 * US, 1000 * US, 50 * US, 2.0, { .35, .23, .12, 1 }, "center", 20, false)
    U.text("lg4", "A Campaign Across Six Continents", cx - 500 * US, 312 * US, 1000 * US, 40 * US, 1.4, { .5, .38, .25, 1 }, "center", 20, false)
    local y0 = 530 * US
    local nx = min(sv.unlocked, #D.LEVELS)
    if U.button("t_play", "Campaign", cx, y0, 460, 112, "green", { fs = U.FS.hero }) then act = "play" end
    U.text("t_play_s", "Next: " .. nx .. ".  " .. D.LEVELS[nx].name, cx - 300 * US, y0 + 68 * US, 600 * US, 40 * US, 1.45, { 1, 1, 1, .95 }, "center", 21)
    -- 2x2 grid: 280x84 buttons (+7 lip), 40 px column gap, 30 px row gap (reference 1080p px, scaled by US)
    local gx, r1, r2 = (280 + 40) / 2 * US, y0 + 166 * US, y0 + 166 * US + (84 + 7 + 30) * US
    if U.button("t_lv", "World Map", cx - gx, r1, 280, 84, "blue") then act = "levels" end
    if U.button("t_up", "War Chest", cx + gx, r1, 280, 84, "orange") then act = "shop" end
    SCR.upg_badge("t_up", cx + gx, r1, 280, 84, D.affordable(sv))
    if U.button("t_opt", "Options", cx - gx, r2, 280, 84, "white") then act = "options" end
    if U.button("t_quit", "Quit", cx + gx, r2, 280, 84, "red") then act = "quit" end
    U.text("t_help", "Drag From Your Regions To Attack  ·  1-4 Abilities  ·  Enter/Space 100%/50%  ·  Wheel Zoom  ·  Edges / WASD Pan", cx - 700 * US, SH - 104 * US, 1400 * US, 40 * US, 1.25, { 1, 1, 1, .9 }, "center", 20)
    return act
end

-- world campaign map: Equal Earth backdrop (tools/gen_worldmap.py), one pin per battle on its map, path in campaign order
local EE_XM, EE_Y0, EE_Y1, EE_L0 = 17243.94, -6758.84, 8325.07, 10
local function ee(lon, lat)
    local A1, A2, A3, A4, Mq = 1.340264, -0.081106, 0.000893, 0.003796, math.sqrt(3) / 2
    local lam = math.rad(((lon - EE_L0 + 540) % 360) - 180); local th = math.asin(Mq * math.sin(math.rad(lat)))
    local t2 = th * th; local t6 = t2 * t2 * t2
    local x = 2 * math.sqrt(3) * lam * math.cos(th) / (3 * (9 * A4 * t6 * t2 + 7 * A3 * t6 + 3 * A2 * t2 + A1))
    local y = th * (A4 * t6 * t2 + A3 * t6 + A2 * t2 + A1)
    return (x * 6371 + EE_XM) / (2 * EE_XM), (EE_Y1 - y * 6371) / (EE_Y1 - EE_Y0)
end
local PINS
local EU_RING = { { .041, .074 }, { .088, .058 }, { .113, .018 }, { .090, -.028 }, { .012, -.046 }, { -.049, -.034 }, { -.078, .011 }, { -.050, .061 } }
local function pin_layout(mx, my, mw, mh)
    local P = {}
    for i, L in ipairs(D.LEVELS) do
        local ll = BB_MAPS[L.map].ll
        local u, v = ee(ll[1], ll[2])
        if L.map == "world" then u, v = ee(-25, -5) end                  -- finale pin sits in mid-Atlantic
        P[i] = { ax = mx + u * mw, ay = my + v * mh }
        P[i].x, P[i].y = P[i].ax, P[i].ay
    end
    -- Europe's eight battles share a thumbnail-sized patch: fan them on a ring around the continent, leader lines show the real spot
    local eu = BB_MAPS.europe.ll
    local eu_u, eu_v = ee(eu[1], eu[2])
    local cx, cy = mx + eu_u * mw, my + eu_v * mh
    local k = 0
    for i, L in ipairs(D.LEVELS) do
        if D.CONT[L.map] == "Europe" then
            k = k + 1
            local o = EU_RING[k]
            if o then P[i].x, P[i].y, P[i].fixed = cx + o[1] * mw, cy + o[2] * mw, true end
        end
    end
    local rad = 44 * US
    for it = 1, 120 do                                                  -- relax overlapping pins
        for i = 1, #P do for j = i + 1, #P do
            local a, b = P[i], P[j]
            local dx, dy = b.x - a.x, b.y - a.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < rad then
                if d < 1e-3 then dx, dy, d = (j - i) % 2 == 0 and 1 or -1, 0.3, 1 end
                local push = (rad - d) / 2 / d
                if a.fixed and b.fixed then push = 0 elseif a.fixed or b.fixed then push = push * 2 end
                if not a.fixed then a.x, a.y = a.x - dx * push, a.y - dy * push end
                if not b.fixed then b.x, b.y = b.x + dx * push, b.y + dy * push end
            end
        end end
        for _, q in ipairs(P) do if not q.fixed then q.x = q.x + (q.ax - q.x) * 0.02; q.y = q.y + (q.ay - q.y) * 0.02 end end
    end
    return P
end
SCR.wsel = nil
-- pulsing gold glow + red count badge on a button (cx, cy = button centre; w, h = reference size) when n > 0
local function upg_badge(id, cx, cy, w, h, n)
    if not n or n <= 0 then return end
    local p = 0.5 + 0.5 * math.sin((G.t or 0) * 4.5)
    local e = (5 + 3 * p) * US
    U.rect(id .. "_gl", cx - w * US / 2 - e, cy - h * US / 2 - e, w * US + 2 * e, h * US + 7 * US + 2 * e, { 1, .82, .25, 0.35 + 0.35 * p }, min(h / 2, 26) + 6, 19)
    local s = 34
    local bx, by = cx + w * US / 2 - 8 * US, cy - h * US / 2 + 4 * US
    U.rect(id .. "_bo", bx - (s / 2 + 3) * US, by - (s / 2 + 3) * US, (s + 6) * US, (s + 6) * US, { 1, 1, 1, 1 }, s / 2 + 3, 24)
    U.rect(id .. "_bd", bx - s / 2 * US, by - s / 2 * US, s * US, s * US, { .88, .2, .15, 1 }, s / 2, 24.1)
    U.text(id .. "_bt", tostring(n), bx - s / 2 * US, by - s / 2 * US - 1 * US, s * US, s * US, 1.45, { 1, 1, 1, 1 }, "center", 24.2, false)
end
SCR.upg_badge = upg_badge
function SCR.levels(dt, sv)
    local act
    local n = #D.LEVELS
    dim(0.55); pills(sv)
    ribbon("lv_r", "World Campaign", SW / 2, 84 * US, 620, { .62, .4, .2, 1 })
    local mw = min(SW - 140 * US, (SH - 420 * US) * 2048 / 895)
    local mh = mw * 895 / 2048
    local mx, my = SW / 2 - mw / 2, 150 * US
    U.rect("wm_fr", mx - 14 * US, my - 14 * US, mw + 28 * US, mh + 28 * US, { .36, .24, .13, 1 }, 18, 18)
    U.Q("wm_img", { style = "image", image = "Textures/ui/worldmap.png", image_tint = { 1, 1, 1, 1 }, x = mx, y = my, w = mw, h = mh, z = 18.5, label = "" })
    if not PINS or PINS.mw ~= mw then PINS = pin_layout(mx, my, mw, mh); PINS.mw = mw end
    SCR.wsel = SCR.wsel or min(sv.unlocked, n)
    if U.K.left then SCR.wsel = max(1, SCR.wsel - 1); sfx("click") end
    if U.K.right then SCR.wsel = min(n, SCR.wsel + 1); sfx("click") end
    -- path dots in campaign order
    for i = 1, n - 1 do
        local a, b = PINS[i], PINS[i + 1]
        local dx, dy = b.x - a.x, b.y - a.y
        local d = math.sqrt(dx * dx + dy * dy)
        local k = floor(d / (16 * US))
        local done = (sv.stars[i] or 0) > 0
        for s = 1, k - 1 do
            local t = s / k
            U.rect("wp" .. i .. "_" .. s, a.x + dx * t - 3 * US, a.y + dy * t - 3 * US, 6 * US, 6 * US, done and { 1, .85, .3, .95 } or { 1, 1, 1, .45 }, 3, 19)
        end
    end
    -- pins
    for i, L in ipairs(D.LEVELS) do
        local p = PINS[i]
        local locked = i > sv.unlocked
        local st = sv.stars[i] or 0
        local col = locked and { .55, .55, .55, 1 } or MCOL[L.map]
        local sel = SCR.wsel == i
        local r = (L.boss and 25 or 21) * US * (sel and 1.25 or 1)
        local hov = U.inside(p.x - r, p.y - r, 2 * r, 2 * r)
        if math.abs(p.x - p.ax) + math.abs(p.y - p.ay) > 6 * US then
            U.rect("wa" .. i, p.ax - 4 * US, p.ay - 4 * US, 8 * US, 8 * US, { .1, .07, .04, .85 }, 4, 19.1)
            local lx, ly = p.x - p.ax, p.y - p.ay
            local ln = math.sqrt(lx * lx + ly * ly)
            local m = floor(ln / (7 * US))
            for s = 1, m - 1 do
                local t = s / m
                U.rect("wq" .. i .. "_" .. s, p.ax + lx * t - 1.5 * US, p.ay + ly * t - 1.5 * US, 3 * US, 3 * US, { .12, .08, .05, .75 }, 2, 19.05)
            end
        end
        if sel then
            local pulse = 1 + 0.12 * math.sin(G.t * 5)
            U.rect("wg" .. i, p.x - r * 1.45 * pulse, p.y - r * 1.45 * pulse, r * 2.9 * pulse, r * 2.9 * pulse, { 1, .95, .6, .55 }, r * 1.45 * pulse / US, 19.2)
        end
        U.rect("wo" .. i, p.x - r - 3 * US, p.y - r - 3 * US, 2 * r + 6 * US, 2 * r + 6 * US, (st > 0) and { 1, .82, .25, 1 } or { .12, .08, .05, 1 }, (r + 3 * US) / US, 19.3)
        U.rect("wc" .. i, p.x - r, p.y - r, 2 * r, 2 * r, hov and { col[1] * 1.15, col[2] * 1.15, col[3] * 1.15, 1 } or col, r / US, 19.4)
        if locked then U.img("wl" .. i, "lock", p.x, p.y, 26 * (sel and 1.25 or 1), 19.6, { 1, 1, 1, .9 })
        else U.text("wn" .. i, tostring(i), p.x - r, p.y - r, 2 * r, 2 * r, sel and 1.55 or 1.25, WHITE, "center", 19.6) end
        if L.boss and not locked then U.img("wb" .. i, "trophy", p.x + r * 0.85, p.y - r * 0.85, 24, 19.7) end
        if st > 0 then for s = 1, st do U.img("wst" .. i .. s, "star", p.x + (s - 2) * 13 * US, p.y + r + 4 * US, 18, 19.7) end end
        if hov and U.MS.click then
            if SCR.wsel == i and not locked then act = i end
            SCR.wsel = i; sfx("click")
        end
    end
    -- continent progress strip
    local conts = { "Europe", "Africa", "Asia", "Oceania", "South America", "North America", "World" }
    local cwid = mw / #conts
    for k, c in ipairs(conts) do
        local tot, got, done = 0, 0, 0
        for i, L in ipairs(D.LEVELS) do if D.CONT[L.map] == c then tot = tot + 3; got = got + (sv.stars[i] or 0); if (sv.stars[i] or 0) > 0 then done = done + 1 end end end
        local x = mx + (k - 1) * cwid
        U.rect("wcc" .. k, x + 6 * US, my + mh + 22 * US, cwid - 12 * US, 40 * US, { CCOL[c][1], CCOL[c][2], CCOL[c][3], .9 }, 14, 19)
        U.text("wct" .. k, c .. "   " .. got .. "/" .. tot, x + 6 * US, my + mh + 22 * US, cwid - 12 * US, 40 * US, 1.15, WHITE, "center", 19.5)
    end
    -- selected battle card
    local i = SCR.wsel
    local L = D.LEVELS[i]
    local locked = i > sv.unlocked
    local cy0 = my + mh + 76 * US
    local ch = SH - cy0 - 24 * US
    local cw = min(1240 * US, SW - 520 * US)
    local cx0 = SW / 2 - cw / 2
    U.card("wcd", cx0, cy0, cw, ch, PARCH, 19)
    U.rect("wcd_b", cx0 + 16 * US, cy0 + 14 * US, 12 * US, ch - 28 * US, MCOL[L.map], 6, 19.3)
    U.text("wcd_n", i .. ".  " .. L.name, cx0 + 44 * US, cy0 + 8 * US, cw * 0.6, 54 * US, 2.0, INK, "left", 19.5, false)
    U.text("wcd_m", MNAME[L.map] .. "  ·  " .. (D.CONT[L.map] or "") .. (L.boss and "  ·  Boss Battle" or ""), cx0 + 44 * US, cy0 + 58 * US, cw * 0.6, 36 * US, 1.25, { .5, .38, .25, 1 }, "left", 19.5, false)
    U.text("wcd_d", locked and "Locked: win the previous battle to march here." or (L.blurb or ""), cx0 + 44 * US, cy0 + 94 * US, cw * 0.62, 40 * US, 1.15, { .4, .3, .2, 1 }, "left", 19.5, false)
    local st = sv.stars[i] or 0
    local sx = cx0 + cw * 0.71
    for s2 = 1, 3 do U.star("wcs" .. s2, sx + (s2 - 2) * 46 * US, cy0 + 46 * US - (s2 == 2 and 6 * US or 0), s2 == 2 and 48 or 40, st >= s2, 19.6) end
    local b = sv.best[i]
    U.text("wcd_p", b and ("Best " .. mmss(b) .. " · Par " .. mmss(L.par)) or ("Par " .. mmss(L.par)), sx - 130 * US, cy0 + 82 * US, 260 * US, 36 * US, 1.1, { .5, .4, .3, 1 }, "center", 19.5, false)
    if U.button("lv_go", locked and "Locked" or "March!", cx0 + cw - 130 * US, cy0 + ch / 2, 200, 84, locked and "grey" or "green", { nokbd = true, z = 20 }) and not locked then act = i end
    if U.K.ok and not locked then act = i end
    if U.button("lv_shop", "Upgrades", 126 * US, SH - (70 + 80 + 7 + 28) * US, 200, 80, "orange", { nokbd = true, fs = U.FS.small }) then act = "shop" end
    upg_badge("lv_shop", 126 * US, SH - (70 + 80 + 7 + 28) * US, 200, 80, D.affordable(sv))
    if U.button("lv_back", "Back", 126 * US, SH - 70 * US, 200, 80, "white", { nokbd = true, fs = U.FS.small }) or U.K.back then act = "back" end
    U.text("lv_keys", "Click a pin, then March  ·  Left / Right to browse", SW - 520 * US, SH - 50 * US, 500 * US, 30 * US, 1.0, { 1, 1, 1, .7 }, "right", 19)
    return act
end

function SCR.shop(dt, sv)
    local act
    dim(0.48); pills(sv)
    ribbon("sh_r", "War Chest", SW / 2, 120 * US, 480, { .85, .55, .15, 1 })
    U.text("sh_s", "Permanent upgrades for the Azure League. Earn coins by winning battles; more stars, more coins.", SW / 2 - 700 * US, 186 * US, 1400 * US, 40 * US, 1.35, { 1, .95, .85, 1 }, "center", 20)
    local cw, ch = 1100, 120
    for i, u in ipairs(D.UPG) do
        local cx = SW / 2
        local cy = 300 * US + (i - 1) * (ch + 18) * US
        local l0, t0 = cx - cw * US / 2, cy - ch * US / 2
        U.card("uc" .. i, l0, t0, cw * US, ch * US, PARCH, 19)
        U.img("ui" .. i, u.icon, l0 + 66 * US, cy, 84, 20)
        U.text("un" .. i, u.name, l0 + 128 * US, t0 + 10 * US, 460 * US, 50 * US, 2.0, INK, "left", 20, false)
        U.text("ud" .. i, u.desc, l0 + 128 * US, t0 + 60 * US, 520 * US, 40 * US, 1.3, { .45, .35, .25, 1 }, "left", 20, false)
        local lv = sv.up[u.key] or 0
        for p = 1, D.UPG_MAX do
            U.rect("up" .. i .. "_" .. p, l0 + 600 * US + (p - 1) * 44 * US, cy - 14 * US, 34 * US, 28 * US, p <= lv and { .3, .62, 1, 1 } or { .82, .76, .64, 1 }, 8, 20)
        end
        if lv >= D.UPG_MAX then
            U.text("um" .. i, "Max", cx + 360 * US, t0, 200 * US, ch * US, 2.2, { .3, .6, .3, 1 }, "center", 20, false)
        else
            local cost = D.upg_cost(lv)
            local ok = sv.coins >= cost
            if U.button("ub" .. i, fmt(cost), cx + 420 * US, cy, 200, 80, ok and "green" or "grey", { fs = U.FS.small, z = 21 }) then
                if ok then sv.coins = sv.coins - cost; sv.up[u.key] = lv + 1; act = "buy"; sfx("upgrade") else sfx("warn") end
            end
            U.coin_icon("ubc" .. i, cx + 346 * US, cy - 2 * US, 32, 22)
        end
    end
    if U.button("sh_back", "Back", 160 * US, SH - 80 * US, 230, 84, "white", { fs = U.FS.small }) or U.K.back then act = "back" end
    return act
end

function SCR.pause(dt)
    local act
    dim(0.5)
    -- parchment card like the victory screen; four equal buttons (420x84 + 7 lip) with 28 px gaps
    local bw, bh, gap = 420, 84, U.GAP
    local pitch = (bh + 7 + gap) * US
    local cw, ch = 560, 96 + 4 * (bh + 7) + 3 * gap + 56
    local l0, t0 = SW / 2 - cw * US / 2, SH / 2 - ch * US / 2 + 20 * US
    U.card("pa_c", l0, t0, cw * US, ch * US, PARCH, 15)
    ribbon("pa_r", "Paused", SW / 2, t0, 440, { .62, .4, .2, 1 }, 3.4)
    local y = t0 + (96 + bh / 2) * US
    if U.button("pa_res", "Resume", SW / 2, y, bw, bh, "green") then act = "resume" end
    if U.button("pa_ret", "Restart", SW / 2, y + pitch, bw, bh, "orange") then act = "retry" end
    if U.button("pa_opt", "Options", SW / 2, y + 2 * pitch, bw, bh, "white") then act = "options" end
    if U.button("pa_men", "Main Menu", SW / 2, y + 3 * pitch, bw, bh, "red") then act = "menu" end
    if U.K.back then act = "resume" end
    return act
end

-- res = { won, stars, coins, lvl, t, time, cap, sent, lost, peak, clash, best, newbest, unlock }
function SCR.result(dt, res, sv)
    local act
    res.t = res.t + dt
    dim(0.4)
    local won = res.won
    local cw, ch = 980, 680
    local l0, t0 = SW / 2 - cw * US / 2, SH / 2 - ch * US / 2 + 20 * US
    U.card("rc", l0, t0, cw * US, ch * US, PARCH, 15)
    ribbon("rr", won and "Victory!" or "Defeat", SW / 2, t0, 520, won and { .3, .62, .25, 1 } or { .75, .25, .2, 1 }, 4.0)
    U.text("rl", res.lvl .. ".  " .. D.LEVELS[res.lvl].name, l0, t0 + 62 * US, cw * US, 50 * US, 1.7, { .45, .35, .25, 1 }, "center", 16, false)
    if won then
        for s = 1, 3 do
            local on = res.stars >= s and res.t > 0.3 + s * 0.25
            local pop = on and (1 + max(0, 0.5 + s * 0.25 - res.t + 0.3) * 1.2) or 1
            U.star("rs" .. s, SW / 2 + (s - 2) * 120 * US, t0 + 176 * US - (s == 2 and 18 * US or 0), (s == 2 and 116 or 96) * pop, on, 16)
            if on and not res["sf" .. s] then res["sf" .. s] = true; sfx("star") end
        end
    else
        U.text("rpr", res.hint or "Regroup and try again.", l0 + 40 * US, t0 + 130 * US, cw * US - 80 * US, 90 * US, 1.5, { .7, .28, .22, 1 }, "center", 16, false)
    end
    local rows = { { "Time", mmss(res.time) .. (won and ("  (par " .. mmss(D.LEVELS[res.lvl].par) .. ")") or "") },
        { "Regions Captured", fmt(res.cap) }, { "Troops Sent", fmt(res.sent) }, { "Largest Army", fmt(res.peak) }, { "Coins", "+" .. fmt(res.coins) } }
    for i, r in ipairs(rows) do
        local y = t0 + 256 * US + (i - 1) * 48 * US
        U.text("rk" .. i, r[1], l0 + 70 * US, y, 340 * US, 44 * US, 1.65, { .45, .35, .25, 1 }, "left", 16, false)
        U.text("rv" .. i, r[2], l0 + 330 * US, y, cw * US - 400 * US, 44 * US, 1.8, INK, "right", 16, false)
    end
    if res.unlock then U.text("run", "New ability unlocked: " .. res.unlock, l0, t0 + 500 * US, cw * US, 40 * US, 1.5, { .2, .45, .8, 1 }, "center", 16, false) end
    -- equal buttons (200x88 + 7 lip), 32 px gaps, one shared font size for the row, centred in the card:
    --   victory: Menu | Upgrades | Retry | Next      defeat: Menu | Upgrades | Retry
    local bw, bh, gap = 200, 88, 32
    local by = t0 + ch * US - (bh / 2 + 7 + 30) * US
    local last = won and res.lvl >= #D.LEVELS
    local row = { { "r_menu", "Menu", "white", "menu" }, { "r_shop", "Upgrades", "orange", "shop" },
        { "r_retry", "Retry", won and "blue" or "green", "retry" } }
    if won then row[4] = { "r_next", last and "Replay" or "Next", "green", "next" } end
    local fs = U.FS.main
    for _, b in ipairs(row) do fs = min(fs, U.fit_fs(b[2], U.FS.main, bw, bh)) end
    local n = #row
    local function bx(i) return SW / 2 + (i - (n + 1) / 2) * (bw + gap) * US end
    -- keyboard focus order: primary action first (Next on victory, Retry on defeat), then Upgrades, then Menu
    local order = won and { 4, 3, 2, 1 } or { 3, 2, 1 }
    for _, i in ipairs(order) do
        local b = row[i]
        if U.button(b[1], b[2], bx(i), by, bw, bh, b[3], { fs = fs }) then act = b[4] end
    end
    upg_badge("r_shop", bx(2), by, bw, bh, sv and D.affordable(sv) or 0)
    if res.t < 0.6 then act = nil end
    return act
end
end
