------------------------------------------------------------------ 07_hud: in-run HUD (squad count, gate values, bars, toasts) + menu screens
do
local U, D, SIM = G.UI, G.D, G.SIM
local US = U.US
local HUD = { toasts = {}, pops = {}, hurt_a = 0 }
G.HUD = HUD
local function fmt(n)
    n = floor((n or 0) + 0.5)
    local s = tostring(abs(n))
    local o = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if o:sub(1, 1) == "," then o = o:sub(2) end
    return (n < 0 and "-" or "") .. o
end
HUD.fmt = fmt
local TCOL = { gold = { 1, .78, .2, 1 }, orange = { 1, .58, .18, 1 }, blue = { .35, .7, 1, 1 }, red = { 1, .35, .3, 1 }, grey = { .8, .84, .9, 1 }, green = { .4, .95, .45, 1 } }
local WHITE = { 1, 1, 1, 1 }
local NAVY = { .06, .1, .24, 1 }

function HUD.reset() HUD.toasts, HUD.pops, HUD.hurt_a, HUD.ban, HUD.hnt = {}, {}, 0, nil, nil end
function HUD.toast(txt, col, icon, key)
    for _, t in ipairs(HUD.toasts) do if t.txt == txt or (key and t.key == key) then t.txt = txt; t.t = math.min(t.t, 0.2); return end end
    table.insert(HUD.toasts, 1, { txt = txt, col = TCOL[col] or TCOL.gold, icon = icon, t = 0, key = key })
    if #HUD.toasts > 3 then HUD.toasts[4] = nil end
end
function HUD.banner(a, b) HUD.ban = { a = a, b = b, t = 0 } end
function HUD.hint(txt) HUD.hnt = { txt = txt, t = 0 } end
function HUD.merge_flash() HUD.mfl = 1.2 end
function HUD.hurt(n) HUD.hurt_a = min(0.55, HUD.hurt_a + 0.12 + n * 0.02) end
function HUD.gate_pop(e)
    local g = e.g
    local txt
    if g.k == "rate" or g.k == "dmg" then txt = (g.v >= 0 and "+" or "") .. g.v .. "% " .. (g.k == "rate" and "Rate" or "Damage")
    elseif g.k == "merge" then txt = "Merged!"
    elseif g.k == "lock" then txt = "Locked"
    else txt = (e.delta >= 0 and "+" or "") .. e.delta end
    HUD.pops[#HUD.pops + 1] = { txt = txt, good = e.good, t = 0 }
end

local function bar(id, cx, cy, w, h, k, col, z, back)
    U.rect(id .. "b", cx - w / 2 - 2 * US, cy - h / 2 - 2 * US, w + 4 * US, h + 4 * US, back or { .05, .08, .18, .75 }, h, z or 8)
    if k > 0.003 then U.rect(id .. "f", cx - w / 2, cy - h / 2, w * clamp(k, 0, 1), h, col, h * 0.8, (z or 8) + 0.1) end
end
HUD.bar = bar

------------------------------------------------------------------ world-anchored labels
local GCOL = { blue = { .85, .95, 1, 1 }, red = { 1, .9, .88, 1 }, green = { .9, 1, .9, 1 }, gold = { 1, .97, .85, 1 }, grey = { .92, .94, 1, 1 }, orange = { 1, .95, .85, 1 } }
local function gate_labels(S)
    for i, g in ipairs(S.gates) do
        if not g.passed and g.z < 78 and g.z > -1 then
            local sx, sy, zc = project(WX(g.x), 1.78, g.z)
            if zc > 2 then
                local px = 2.18 / (zc * math.tan(VFOV / 2)) * SH / 2
                local fs = clamp(px / 24 / US, 0.6, 7) * (1 + (g.hit or 0) * 0.35)
                local big, small = SIM.gate_label(g)
                local a = clamp((80 - g.z) / 12, 0, 1)
                local col = GCOL[SIM.gate_color(g)] or WHITE
                U.big("gl" .. i, big, sx, sy - (small and px * 0.08 or 0), fs, { col[1], col[2], col[3], a }, max(1.5, fs * 0.8), 6)
                if small then U.text("gs" .. i, small, sx - px * 0.6, sy + px * 0.13, px * 1.2, px * 0.2, fs * 0.36, { 1, 1, 1, a }, "center", 6, false) end
                if g.k == "add" or g.k == "mul" or g.k == "rate" or g.k == "dmg" then
                    -- damage meter: fills smoothly with every point of squad damage, empties on each step up
                    local top = g.k == "mul" and g.mi >= #D.MUL
                    local raw = top and 1 or clamp((g.prog or 0) / SIM.gate_cost(g), 0, 1)
                    local p = g.pshow or raw
                    if raw < p - 0.3 then p = 0 end
                    p = p + (raw - p) * math.min(1, (G.HUDDT or 0.016) * 12)
                    g.pshow = p
                    bar("gp" .. i, sx, sy + px * 0.3, px * 0.8, max(5 * US, px * 0.05), p, top and { 1, .8, .3, 1 } or { .55, .95, 1, 1 }, 6)
                end
                if g.k == "lock" and g.hp then bar("gb" .. i, sx, sy + px * 0.3, px * 0.8, max(5 * US, px * 0.05), g.hp / g.maxhp, { 1, .8, .3, 1 }, 6) end
                if g.k == "trap" and not g.flip then
                    local k = g.v / max(1, g.maxv)
                    bar("gt" .. i, sx, sy + px * 0.3, px * 0.8, max(5 * US, px * 0.05), k, k > 0.8 and { 1, .3, .25, 1 } or { 1, .65, .2, 1 }, 6)
                end
            end
        end
    end
end
local function prop_labels(S)
    for i, p in ipairs(S.props) do
        if not p.dead and p.z < 70 and p.z > 0 and (p.t == "crate" or p.t == "container" or p.t == "barricade") then
            local h = (p.t == "container") and 3.4 or ((p.t == "crate") and (2.0 + (p.drop or 0) * 9) or 2.4)
            local sx, sy, zc = project(WX(p.x), h, p.z)
            if zc > 2 then
                local k = clamp(26 / zc, 0.45, 1.4)
                local a = clamp((72 - p.z) / 10, 0, 1)
                if p.t == "crate" and p.w then U.img("pw" .. i, "w_" .. p.w, sx, sy - 34 * k * US, 70 * k, 7, { 1, 1, 1, a }) end
                if p.t == "container" and p.ally then
                    U.text("pa" .. i, D.ALLY[p.ally].name, sx - 160 * US, sy - 46 * k * US, 320 * US, 40 * US, 1.25 * k, { 1, .95, .7, a }, "center", 7)
                end
                if p.hp < p.maxhp then bar("ph" .. i, sx, sy, 100 * k * US, 10 * k * US, p.hp / p.maxhp, { .4, .9, .4, 1 }, 7) end
            end
        end
    end
end
local function foe_bars(S)
    local nb = 0
    for i, f in ipairs(S.foes) do
        if not f.dead and not f.boss and (f.t == "brute" or f.t == "shield") and f.z < 70 and (f.hp < f.maxhp or (f.shield or 0) > 0) then
            nb = nb + 1
            if nb > 14 then break end
            local h = (f.t == "brute") and 2.7 or 2.0
            local sx, sy, zc = project(WX(f.x), h, f.z)
            if zc > 2 then
                local k = clamp(24 / zc, 0.4, 1.3)
                if (f.shield or 0) > 0 then bar("fs" .. i, sx, sy, 80 * k * US, 8 * k * US, f.shield / f.maxsh, { .4, .75, 1, 1 }, 7)
                else bar("fh" .. i, sx, sy, 80 * k * US, 8 * k * US, f.hp / f.maxhp, { 1, .35, .3, 1 }, 7) end
            end
        end
    end
end

------------------------------------------------------------------ the in-run HUD; returns "pause" / "air" / "merge"
function HUD.play(S, dt, demo)
    G.HUDDT = dt
    local act
    if not demo then gate_labels(S); prop_labels(S); foe_bars(S) end
    local L = S.L
    -- squad counter bubble (in-run only: on menus it would float behind the buttons)
    if demo then return end
    local F = G.R.sqF
    local n = SIM.worth()   -- total worth in soldier-equivalents: merges never lower it
    HUD.mfl = math.max(0, (HUD.mfl or 0) - (dt or 0))
    if F and n > 0 then
        local sx, sy = project(WX(S.x), 2.1 + min(n, 30) * 0.012, -F.depth * 0.5)
        local w = (70 + #tostring(n) * 22) * US
        local k = math.min(1, HUD.mfl / 0.6)   -- gold pulse right after a merge
        local pk = 1 + 0.18 * k
        sy = sy - 4 * US * k
        U.rect("sq_b", sx - w * pk / 2, sy - 32 * US * pk, w * pk, 64 * US * pk, { .2 + .8 * k, .5 + .3 * k, 1 - .8 * k, .92 }, 32 * pk, 9)
        U.rect("sq_bh", sx - w / 2 + 6 * US, sy - 28 * US, w - 12 * US, 22 * US, { 1, 1, 1, .2 }, 16, 9.1)
        U.big("sq_n", tostring(n), sx, sy + 1 * US, 2.4, WHITE, 2, 9.5)
    end
    if demo then return end
    -- top: level name, progress
    U.text("lvname", "Level " .. S.lvl .. "  " .. L.name, 30 * US, 22 * US, 700 * US, 50 * US, 1.8, WHITE, "left", 20)
    local pw = 560 * US
    local prog = clamp(S.travel / L.len, 0, 1)
    if S.boss or S.bosses_left and S.bosses_left > 0 and prog >= 1 then prog = 1 end
    bar("prog", SW / 2, 44 * US, pw, 18 * US, prog, { .35, .85, .4, 1 }, 20)
    U.img("prog_s", "u_sol", SW / 2 - pw / 2 + pw * prog, 44 * US, 44, 21)
    if L.boss then U.img("prog_b", "skull", SW / 2 + pw / 2 + 30 * US, 44 * US, 46, 21) end
    -- coins + pause
    U.pill("hc", SW - 330 * US, 22 * US, 200, "coin", fmt(S.coins), 30)
    if U.button("h_pause", "", SW - 70 * US, 52 * US, 84, 84, "white", { nokbd = true, r = 20 }) then act = "pause" end
    U.img("h_pause_i", "pause", SW - 70 * US, 50 * US, 50, 21, { .2, .3, .55, 1 })
    -- boss bar
    if S.boss and not S.boss.dead then
        local b = S.boss
        local bw = 820 * US
        U.big("bossn", D.BOSS[b.boss].name, SW / 2, 104 * US, 2.6, { 1, .85, .8, 1 }, 2.5, 20)
        bar("bossb", SW / 2, 146 * US, bw, 24 * US, b.hp / b.maxhp, { .95, .25, .25, 1 }, 20)
    end
    -- bottom-left: weapon + composition
    local W = D.WEAPONS[S.weapon]
    U.rect("wpn_bg", 24 * US, SH - 150 * US, 380 * US, 126 * US, { .06, .1, .24, .55 }, 26, 18)
    U.img("wpn_i", "w_" .. S.weapon, 100 * US, SH - 87 * US, 104, 19)
    U.text("wpn_n", W.name, 160 * US, SH - 140 * US, 240 * US, 50 * US, 2.0, { W.col[1], W.col[2], W.col[3], 1 }, "left", 19)
    local cx = 166 * US
    for _, c in ipairs({ { "u_sol", S.sol }, { "u_vet", S.vet }, { "u_hvy", S.hvy } }) do
        U.img("cmp_" .. c[1], c[1], cx + 16 * US, SH - 62 * US, 38, 19)
        U.text("cmp_t" .. c[1], tostring(c[2]), cx + 36 * US, SH - 82 * US, 60 * US, 40 * US, 1.4, WHITE, "left", 19)
        cx = cx + 78 * US
    end
    -- bottom-right: airstrike + merge
    local ax, ay = SW - 120 * US, SH - 120 * US
    local ready = S.air >= 1 and not S.jet
    local pul = ready and (1 + math.sin(G.t * 8) * 0.04) or 1
    if U.button("h_air", "", ax, ay, 150 * pul, 150 * pul, ready and "orange" or "grey", { nokbd = true, r = 75 }) and ready then act = "air" end
    U.img("h_air_i", "air", ax, ay - 8 * US, 92, 21, ready and WHITE or { 1, 1, 1, .7 })
    bar("h_airm", ax, ay + 98 * US, 140 * US, 14 * US, S.air, ready and { 1, .75, .2, 1 } or { .5, .75, 1, 1 }, 20)
    U.text("h_airk", ready and "Space" or "Airstrike", ax - 100 * US, ay + 110 * US, 200 * US, 36 * US, 1.15, WHITE, "center", 20)
    if S.sol >= 8 then
        if U.button("h_merge", "Merge", SW - 300 * US, SH - 100 * US, 170, 76, "gold", { nokbd = true, fs = 2.3 }) then act = "merge" end
        U.text("h_mk", "M", SW - 300 * US - 85 * US, SH - 62 * US, 170 * US, 30 * US, 1.0, { 1, 1, 1, .8 }, "center", 21)
    end
    -- gate result pops over the squad
    for i = #HUD.pops, 1, -1 do
        local p = HUD.pops[i]
        p.t = p.t + dt
        if p.t > 1.3 then table.remove(HUD.pops, i)
        else
            local sx, sy = project(WX(S.x), 3.0, 0)
            local col = p.good and { .45, 1, .5, 1 } or (p.good == false and { 1, .4, .35, 1 } or WHITE)
            col[4] = clamp((1.3 - p.t) * 3, 0, 1)
            U.big("pop" .. i, p.txt, sx, sy - p.t * 110 * US, 3.4 * (1 + max(0, 0.25 - p.t) * 2), col, 3, 22)
        end
    end
    -- tutorial-ish first seconds
    if S.lvl == 1 and S.t < 6 then
        local a = clamp((6 - S.t) * 0.8, 0, 1)
        U.big("tut", "Drag Or A / D To Move", SW / 2, SH * 0.885, 2.6, { 1, 1, 1, a }, 2.5, 22)
        U.text("tut2", "Shoot Gates To Raise Them, Then Walk Through", SW / 2 - 500 * US, SH * 0.885 + 34 * US, 1000 * US, 50 * US, 1.7, { 1, 1, 1, a }, "center", 22)
    end
    return act
end

-- overlays drawn in every state (toasts, banner, hint, hurt vignette)
function HUD.overlays(dt)
    for i = #HUD.toasts, 1, -1 do
        local t = HUD.toasts[i]
        t.t = t.t + dt
        if t.t > 2.2 then table.remove(HUD.toasts, i) end
    end
    for i, t in ipairs(HUD.toasts) do
        local a = clamp(min(t.t * 6, (2.2 - t.t) * 3), 0, 1)
        local y = 200 * US + (i - 1) * 64 * US
        local s = 1 + max(0, 0.15 - t.t) * 2
        local w = (#t.txt * 21 + 80) * US
        U.rect("to" .. i, SW / 2 - w / 2, y - 26 * US, w, 54 * US, { t.col[1] * .55, t.col[2] * .55, t.col[3] * .55, .82 * a }, 27, 24)
        U.big("tt" .. i, t.txt, SW / 2, y, 2.1 * s, { 1, 1, 1, a }, 2, 25)
    end
    local b = HUD.ban
    if b then
        b.t = b.t + dt
        if b.t > 2.8 then HUD.ban = nil
        else
            local a = clamp(min(b.t * 4, (2.8 - b.t) * 3), 0, 1)
            local s = 1 + max(0, 0.25 - b.t) * 2
            U.rect("ban_bg", 0, SH * 0.36, SW, 170 * US, { .45, .05, .05, .55 * a }, 0, 24)
            U.big("ban_b", b.b, SW / 2, SH * 0.36 + 45 * US, 2.4, { 1, .8, .7, a }, 2, 25)
            U.big("ban_a", b.a, SW / 2, SH * 0.36 + 112 * US, 5.0 * s, { 1, 1, 1, a }, 4, 25)
        end
    end
    local h = HUD.hnt
    if h then
        h.t = h.t + dt
        if h.t > 4 then HUD.hnt = nil
        else
            local a = clamp(min(h.t * 4, (4 - h.t) * 2), 0, 1)
            local w = (#h.txt * 17 + 70) * US
            U.rect("hn_bg", SW / 2 - w / 2, 96 * US, w, 58 * US, { .05, .1, .25, .6 * a }, 29, 24)
            U.text("hn_t", h.txt, SW / 2 - w / 2, 96 * US, w, 58 * US, 1.7, { 1, 1, 1, a }, "center", 25)
        end
    end
    HUD.hurt_a = max(0, HUD.hurt_a - dt * 1.4)
    if HUD.hurt_a > 0.01 then
        local a = HUD.hurt_a
        local e = 70 * US
        U.rect("hv_l", 0, 0, e, SH, { .9, .05, .05, a }, 0, 3)
        U.rect("hv_r", SW - e, 0, e, SH, { .9, .05, .05, a }, 0, 3)
        U.rect("hv_t", e, 0, SW - 2 * e, e * 0.7, { .9, .05, .05, a * 0.8 }, 0, 3)
        U.rect("hv_b", e, SH - e * 0.7, SW - 2 * e, e * 0.7, { .9, .05, .05, a * 0.8 }, 0, 3)
    end
end

------------------------------------------------------------------ screens
local SCR = {}
G.SCR = SCR
local WCOL = { harbor = { .25, .62, .95, 1 }, canyon = { .9, .55, .28, 1 }, forest = { .85, .45, .2, 1 }, frost = { .45, .78, .95, 1 }, volcano = { .9, .3, .2, 1 } }
local function dim(a) U.rect("dim", 0, 0, SW, SH, { .04, .08, .2, a or 0.35 }, 0, 1) end
local function pills(sv)
    U.pill("mc", SW - 470 * US, 26 * US, 220, "coin", fmt(sv.coins), 30)
    U.pill("mm", SW - 236 * US, 26 * US, 200, "medal", fmt(sv.medals), 30)
end
local function ribbon(id, text, cx, cy, w, col, fs)
    w = w * US
    local h = 96 * US
    U.rect(id .. "s", cx - w / 2 + 6 * US, cy - h / 2 + 10 * US, w, h, { .05, .1, .25, .3 }, 30, 19.5)
    U.rect(id .. "l", cx - w / 2, cy - h / 2 + 8 * US, w, h, { col[1] * .6, col[2] * .6, col[3] * .6, 1 }, 30, 19.6)
    U.rect(id, cx - w / 2, cy - h / 2, w, h, col, 30, 19.7)
    U.rect(id .. "h", cx - w / 2 + 12 * US, cy - h / 2 + 6 * US, w - 24 * US, h * 0.36, { 1, 1, 1, .22 }, 20, 19.8)
    U.big(id .. "t", text, cx, cy, fs or 3.6, WHITE, 3, 20)
end

function SCR.title(dt, sv)
    local act
    pills(sv)
    local bob = math.sin(G.t * 2) * 5 * US
    -- solid title card: drop shadow, white rim, deep-blue face, top sheen (nothing from the world shows through)
    U.rect("logo_sh", SW / 2 - 512 * US, 84 * US, 1040 * US, 330 * US, { .02, .05, .15, .35 }, 64, 17.5)
    U.rect("logo_rim", SW / 2 - 528 * US, 62 * US, 1056 * US, 346 * US, { 1, 1, 1, 1 }, 68, 17.7)
    U.rect("logo_bg", SW / 2 - 520 * US, 70 * US, 1040 * US, 330 * US, { .1, .24, .55, 1 }, 60, 17.8)
    U.rect("logo_hl", SW / 2 - 500 * US, 80 * US, 1000 * US, 120 * US, { 1, 1, 1, .1 }, 50, 17.9)
    U.big("logo1", "Gatebreaker", SW / 2, 170 * US + bob, 9.0, { 1, .8, .22, 1 }, 6, 20)
    U.big("logo2", "Squad", SW / 2, 285 * US + bob, 6.4, { 1, 1, 1, 1 }, 5, 20)
    U.text("logo3", "Shoot The Gates  ·  Grow The Squad  ·  Break The Horde", SW / 2 - 600 * US, 338 * US, 1200 * US, 50 * US, 1.8, { 1, 1, 1, .95 }, "center", 20)
    local y0 = 560 * US
    local nx = min(sv.unlocked, #D.LEVELS)
    if U.button("t_play", "Play", SW / 2, y0, 440, 116, "green", { fs = 4.4 }) then act = "play" end
    U.text("t_play_s", "Level " .. nx .. "  ·  " .. D.LEVELS[nx].name, SW / 2 - 300 * US, y0 + 70 * US, 600 * US, 40 * US, 1.5, { 1, 1, 1, .95 }, "center", 21)
    if U.button("t_lv", "Levels", SW / 2 - 145 * US, y0 + 160 * US, 270, 86, "blue") then act = "levels" end
    if U.button("t_shop", "Shop", SW / 2 + 145 * US, y0 + 160 * US, 270, 86, "orange") then act = "shop" end
    if U.button("t_opt", "Options", SW / 2 - 145 * US, y0 + 272 * US, 270, 86, "white") then act = "options" end
    if U.button("t_quit", "Quit", SW / 2 + 145 * US, y0 + 272 * US, 270, 86, "red") then act = "quit" end
    U.text("t_help", "Mouse  ·  Arrows + Enter", SW / 2 - 300 * US, SH - 56 * US, 600 * US, 40 * US, 1.3, { 1, 1, 1, .85 }, "center", 20)
    return act
end

function SCR.levels(dt, sv)
    local act
    dim(0.38); pills(sv)
    ribbon("lv_r", "Choose A Level", SW / 2, 130 * US, 640, { .3, .6, 1, 1 })
    local cw, ch, gx, gy, cols = 330, 250, 24, 28, 5
    local x0 = SW / 2 - (cols * cw + (cols - 1) * gx) * US / 2
    local y0 = 230 * US
    for i, L in ipairs(D.LEVELS) do
        local c, r = (i - 1) % cols, floor((i - 1) / cols)
        local x, y = x0 + c * (cw + gx) * US, y0 + r * (ch + gy) * US
        local cx, cy = x + cw * US / 2, y + ch * US / 2
        local locked = i > sv.unlocked
        local wc = WCOL[L.world]
        local id = "lv" .. i
        if U.button(id, "", cx, cy, cw, ch, locked and "grey" or "white", { r = 24, z = 20 }) and not locked then act = i end
        local l0 = cx - cw * US / 2
        U.rect(id .. "_band", l0 + 10 * US, cy - ch * US / 2 + 10 * US, cw * US - 20 * US, 56 * US, locked and { .55, .58, .65, 1 } or wc, 18, 20.25)
        U.text(id .. "_n", tostring(i), l0 + 12 * US, cy - ch * US / 2 + 10 * US, 64 * US, 56 * US, 2.6, WHITE, "center", 20.4)
        U.text(id .. "_w", D.WORLDS[L.world].name, l0 + 70 * US, cy - ch * US / 2 + 10 * US, cw * US - 92 * US, 56 * US, 1.35, { 1, 1, 1, .95 }, "right", 20.4, false)
        U.text(id .. "_nm", L.name, l0, cy - 40 * US, cw * US, 50 * US, 1.85, locked and { 1, 1, 1, .9 } or { .12, .2, .42, 1 }, "center", 20.4, false)
        if locked then
            U.img(id .. "_lk", "lock", cx, cy + 50 * US, 60, 20.5, { 1, 1, 1, .9 })
        else
            local st = sv.stars[i] or 0
            for s = 1, 3 do U.star(id .. "_s" .. s, cx + (s - 2) * 58 * US, cy + 30 * US - (s == 2 and 8 * US or 0), s == 2 and 56 or 48, st >= s, 20.5) end
            local b = sv.best[i] or 0
            U.text(id .. "_bs", b > 0 and ("Best " .. fmt(b)) or "New", l0, cy + 66 * US, cw * US, 40 * US, 1.3, { .3, .38, .55, 1 }, "center", 20.4, false)
            if L.boss then U.img(id .. "_sk", "skull", cx + cw * US / 2 - 36 * US, cy + 72 * US, 44, 20.5) end
        end
    end
    if U.button("lv_back", "Back", 160 * US, SH - 80 * US, 230, 84, "white") or U.K.back then act = "back" end
    return act
end

-- shop: upgrades / heroes / arsenal
SCR.tab = "upg"
local function buy_ok(sv, cost) return sv.coins >= cost end
function SCR.shop(dt, sv)
    local act
    dim(0.45); pills(sv)
    ribbon("sh_r", "Shop", SW / 2, 110 * US, 420, { 1, .6, .18, 1 })
    local tabs = { { "upg", "Upgrades" }, { "hero", "Heroes" }, { "arms", "Arsenal" } }
    for i, t in ipairs(tabs) do
        local on = SCR.tab == t[1]
        if U.button("tab_" .. t[1], t[2], SW / 2 + (i - 2) * 300 * US, 222 * US, 270, 72, on and "blue" or "white", { fs = 2.2 }) then SCR.tab = t[1] end
    end
    if SCR.tab == "upg" then
        local cw, ch = 820, 112
        for i, u in ipairs(D.UPG) do
            local c, r = (i - 1) % 2, floor((i - 1) / 2)
            local cx = SW / 2 + (c - 0.5) * (cw + 30) * US
            local cy = 340 * US + r * (ch + 18) * US
            local l0, t0 = cx - cw * US / 2, cy - ch * US / 2
            U.card("uc" .. i, l0, t0, cw * US, ch * US, { .97, .97, 1, .97 }, 19)
            U.text("un" .. i, u.name, l0 + 26 * US, t0 + 8 * US, 440 * US, 50 * US, 2.0, { .12, .2, .42, 1 }, "left", 20, false)
            U.text("ud" .. i, u.desc, l0 + 26 * US, t0 + 56 * US, 460 * US, 40 * US, 1.3, { .35, .42, .6, 1 }, "left", 20, false)
            local lv = sv.up[u.key] or 0
            U.text("ul" .. i, "Lv " .. lv .. " / " .. u.max, l0 + 440 * US, t0 + 8 * US, 150 * US, 50 * US, 1.5, { .3, .38, .58, 1 }, "right", 20, false)
            bar("upb" .. i, l0 + 515 * US, t0 + 78 * US, 150 * US, 12 * US, lv / u.max, { .35, .75, 1, 1 }, 20, { .8, .84, .92, 1 })
            if lv >= u.max then
                U.text("um" .. i, "Max", cx + 230 * US, t0, 170 * US, ch * US, 2.0, { .3, .7, .35, 1 }, "center", 20, false)
            else
                local cost = D.upg_cost(u, lv)
                local ok = buy_ok(sv, cost)
                if U.button("ub" .. i, fmt(cost), cx + 315 * US, cy, 170, 76, ok and "green" or "grey", { fs = 2.1, z = 21 }) then
                    if ok then sv.coins = sv.coins - cost; sv.up[u.key] = lv + 1; act = "buy"; sfx("levelup") else sfx("gate_bad") end
                end
                U.coin_icon("ubc" .. i, cx + 248 * US, cy - 2 * US, 30, 22)
            end
        end
    elseif SCR.tab == "hero" then
        local cw, ch = 520, 300
        for i, h in ipairs(D.HEROES) do
            local c, r = (i - 1) % 3, floor((i - 1) / 3)
            local cx = SW / 2 + (c - 1) * (cw + 30) * US
            local cy = 450 * US + r * (ch + 26) * US
            local l0, t0 = cx - cw * US / 2, cy - ch * US / 2
            local own = sv.heroes[h.key]
            local eq = sv.hero == h.key
            U.card("hc" .. i, l0, t0, cw * US, ch * US, eq and { 1, .95, .8, .98 } or { .97, .97, 1, .97 }, 19)
            U.text("hn" .. i, h.name, l0, t0 + 14 * US, cw * US, 60 * US, 2.8, { .12, .2, .42, 1 }, "center", 20, false)
            U.text("hd" .. i, h.desc, l0 + 20 * US, t0 + 80 * US, cw * US - 40 * US, 90 * US, 1.35, { .35, .42, .6, 1 }, "center", 20, false)
            if eq then U.text("he" .. i, "Leading The Squad", l0, cy + 70 * US, cw * US, 60 * US, 1.8, { .85, .55, .1, 1 }, "center", 20, false)
            elseif own then
                if U.button("hb" .. i, "Select", cx, cy + 92 * US, 240, 76, "blue", { z = 21 }) then sv.hero = h.key; act = "buy" end
            else
                local ok = sv.coins >= h.coins and sv.medals >= h.medals
                if U.button("hb" .. i, fmt(h.coins), cx, cy + 92 * US, 240, 76, ok and "green" or "grey", { z = 21, fs = 2.1 }) then
                    if ok then sv.coins = sv.coins - h.coins; sv.heroes[h.key] = true; sv.hero = h.key; act = "buy"; sfx("levelup") else sfx("gate_bad") end
                end
                U.coin_icon("hbc" .. i, cx - 80 * US, cy + 90 * US, 30, 22)
                U.img("hm" .. i, "medal", cx - 60 * US, cy + 22 * US, 36, 20)
                U.text("hmt" .. i, "Needs " .. h.medals, cx - 36 * US, cy + 2 * US, 200 * US, 40 * US, 1.4, sv.medals >= h.medals and { .3, .6, .3, 1 } or { .8, .3, .25, 1 }, "left", 20, false)
            end
        end
        U.text("h_tip", "Medals: Beat A Boss Level For The First Time", SW / 2 - 500 * US, SH - 150 * US, 1000 * US, 40 * US, 1.4, { 1, 1, 1, .9 }, "center", 20)
    else
        local cw, ch = 330, 420
        for i, k in ipairs(D.WORDER) do
            local W = D.WEAPONS[k]
            local cx = SW / 2 + (i - 3) * (cw + 22) * US
            local cy = 520 * US
            local l0, t0 = cx - cw * US / 2, cy - ch * US / 2
            local own = sv.weapons[k]
            local eq = sv.weapon == k
            U.card("wc" .. i, l0, t0, cw * US, ch * US, eq and { 1, .95, .8, .98 } or { .97, .97, 1, .97 }, 19)
            U.img("wi" .. i, "w_" .. k, cx, t0 + 110 * US, 170, 20)
            U.text("wn" .. i, W.name, l0, t0 + 190 * US, cw * US, 56 * US, 2.5, { .12, .2, .42, 1 }, "center", 20, false)
            local info = ({ rifle = "Fast, Long Range", shotgun = "Spread Of 4 Pellets", minigun = "Bullet Storm", rocket = "Splash Damage", laser = "Pierces 3 Targets" })[k]
            U.text("wd" .. i, info, l0, t0 + 244 * US, cw * US, 40 * US, 1.35, { .35, .42, .6, 1 }, "center", 20, false)
            if eq then U.text("we" .. i, "Equipped", l0, cy + 120 * US, cw * US, 60 * US, 2.0, { .85, .55, .1, 1 }, "center", 20, false)
            elseif own then
                if U.button("wb" .. i, "Equip", cx, cy + 140 * US, 220, 76, "blue", { z = 21 }) then sv.weapon = k; act = "buy" end
            else
                local cost = D.WPRICE[k]
                local ok = sv.coins >= cost
                if U.button("wb" .. i, fmt(cost), cx, cy + 140 * US, 220, 76, ok and "green" or "grey", { z = 21, fs = 2.1 }) then
                    if ok then sv.coins = sv.coins - cost; sv.weapons[k] = true; sv.weapon = k; act = "buy"; sfx("levelup") else sfx("gate_bad") end
                end
                U.coin_icon("wbc" .. i, cx - 72 * US, cy + 138 * US, 30, 22)
            end
        end
        U.text("w_tip", "Your Squad Starts Each Level With The Equipped Weapon. Crates Swap It Mid-Run.", SW / 2 - 700 * US, SH - 150 * US, 1400 * US, 40 * US, 1.4, { 1, 1, 1, .9 }, "center", 20)
    end
    if U.button("sh_back", "Back", 160 * US, SH - 80 * US, 230, 84, "white") or U.K.back then act = "back" end
    return act
end

function SCR.pause(dt)
    local act
    dim(0.5)
    ribbon("pa_r", "Paused", SW / 2, 260 * US, 520, { .3, .6, 1, 1 })
    if U.button("pa_res", "Resume", SW / 2, 420 * US, 400, 96, "green", { fs = 3.2 }) then act = "resume" end
    if U.button("pa_ret", "Retry", SW / 2, 540 * US, 400, 86, "orange") then act = "retry" end
    if U.button("pa_opt", "Options", SW / 2, 650 * US, 400, 86, "white") then act = "options" end
    if U.button("pa_men", "Menu", SW / 2, 760 * US, 400, 86, "red") then act = "menu" end
    if U.K.back then act = "resume" end
    return act
end

-- res = { won, stars, coins, score, best, kills, surv, lvl, newbest, medal, t }
function SCR.result(dt, res)
    local act
    res.t = res.t + dt
    dim(0.42)
    local won = res.won
    local cw, ch = 760, 640
    local l0, t0 = SW / 2 - cw * US / 2, SH / 2 - ch * US / 2 + 20 * US
    U.card("rc", l0, t0, cw * US, ch * US, { .97, .97, 1, .97 }, 15)
    ribbon("rr", won and "Victory!" or "Squad Down", SW / 2, t0, 560, won and { .3, .78, .35, 1 } or { .9, .32, .3, 1 }, 4.0)
    U.text("rl", "Level " .. res.lvl .. "  ·  " .. D.LEVELS[res.lvl].name, l0, t0 + 64 * US, cw * US, 50 * US, 1.7, { .3, .38, .58, 1 }, "center", 16, false)
    if won then
        for s = 1, 3 do
            local on = res.stars >= s and res.t > 0.3 + s * 0.25
            local pop = on and (1 + max(0, 0.5 + s * 0.25 - res.t + 0.3) * 1.2) or 1
            U.star("rs" .. s, SW / 2 + (s - 2) * 120 * US, t0 + 180 * US - (s == 2 and 20 * US or 0), (s == 2 and 120 or 100) * pop, on, 16)
        end
    else
        U.text("rpr", string.format("Reached %d%% Of The Way", floor(res.prog * 100 + 0.5)), l0, t0 + 140 * US, cw * US, 60 * US, 2.2, { .8, .3, .25, 1 }, "center", 16, false)
        if res.hint then U.text("rh", res.hint, l0 + 30 * US, t0 + 200 * US, cw * US - 60 * US, 50 * US, 1.4, { .35, .42, .6, 1 }, "center", 16, false) end
    end
    local rows = { { "Survivors", fmt(res.surv) }, { "Kills", fmt(res.kills) }, { "Score", fmt(res.score) .. (res.newbest and "  New Best!" or "") }, { "Coins", "+" .. fmt(res.coins) } }
    if res.medal then rows[#rows + 1] = { "Medal", "+1" } end
    for i, r in ipairs(rows) do
        local y = t0 + 262 * US + (i - 1) * 50 * US
        U.text("rk" .. i, r[1], l0 + 90 * US, y, 300 * US, 46 * US, 1.8, { .35, .42, .6, 1 }, "left", 16, false)
        U.text("rv" .. i, r[2], l0 + 330 * US, y, cw * US - 420 * US, 46 * US, 2.0, { .12, .2, .42, 1 }, "right", 16, false)
    end
    local by = t0 + ch * US - 70 * US
    if won then
        local last = res.lvl >= #D.LEVELS
        if U.button("r_next", last and "Replay" or "Next", SW / 2 + 220 * US, by, 230, 92, "green", { fs = 3.0 }) then act = "next" end
    else
        if U.button("r_shop", "Shop", SW / 2 + 220 * US, by, 230, 92, "orange", { fs = 3.0 }) then act = "shop" end
    end
    if U.button("r_retry", "Retry", SW / 2, by, 200, 92, won and "blue" or "green", { fs = 2.8 }) then act = "retry" end
    if U.button("r_menu", "Menu", SW / 2 - 220 * US, by, 200, 92, "white", { fs = 2.8 }) then act = "menu" end
    if res.t < 0.6 then act = nil end
    return act
end
end
