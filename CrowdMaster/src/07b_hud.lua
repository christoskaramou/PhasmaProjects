------------------------------------------------------------------ HUD + G hooks (popups, punch, shake, tips) + world labels
do
local U = G.UI
local M = G.M
local US = U.US
local HUD = { pops = {}, wpops = {}, tip = nil }
G.HUD = HUD
-- hooks used by the run / finale code
G.fovp, G.fovp_t, G.fovp_d, G.shk = 0, 1, 1, 0
function G.punch(deg, dur) if abs(deg) >= abs(G.fovp * (1 - G.fovp_t / G.fovp_d)) then G.fovp, G.fovp_t, G.fovp_d = deg, 0, dur or 0.3 end end
function G.shake(a) G.shk = max(G.shk, (a or 0.2) * SET:shake_scale()) end
function G.popup(text, col, dur)
    table.insert(HUD.pops, 1, { text = text, col = col or { 1, 1, 1, 1 }, t = 0, dur = dur or 1 })
    while #HUD.pops > 3 do table.remove(HUD.pops) end
end
function G.popup_at(text, x, y, z, col, dur)
    HUD.wpops[#HUD.wpops + 1] = { text = text, x = x, y = y, z = z, col = col or { 1, 1, 1, 1 }, t = 0, dur = dur or 0.8 }
    while #HUD.wpops > 8 do table.remove(HUD.wpops, 1) end
end
function G.tip(text) HUD.tip = { text = text, t = 0 } end
local last_coin, last_hit, last_pop = 0, 0, 0
function G.coin_sfx() if G.t - last_coin > 0.07 then last_coin = G.t; sfx("coin") end end
function G.sfx_hit() if G.t - last_hit > 0.06 then last_hit = G.t; sfx("hit") end end
function G.on_loss(t, how) if G.t - last_pop > 0.09 then last_pop = G.t; sfx(how == "fall" and "pop" or "pop") end end
function G.use_shield()
    if (G.shields or 0) > 0 and (G.shield_t or 0) <= 0 and RUN.phase ~= "dead" then
        G.shields = G.shields - 1; G.shield_t = 3; sfx("shield"); G.punch(3, 0.3)
        G.popup("Shield Up!", { .6, .85, 1, 1 }, 0.9)
        return true
    end
end

local function fmt(n) n = floor(n + 0.5); local s = tostring(n); if n >= 10000 then s = string.format("%.1fk", n / 1000) end; return s end
HUD.fmt = fmt
-- one world label (projected), auto-sized by distance
local function wlabel(id, l)
    local sx, sy, zc = project(LX(l.x), l.y, l.z)
    if zc < 1 or zc > 75 or sx < -200 or sx > SW + 200 then return end
    local fs = clamp(l.size * 30 / zc, 1.15, 5.5)
    if l.bg then
        local w = (#l.text * 0.52 + 1.1) * fs * 16 * US
        local h = fs * 22 * US
        U.rect(id .. "b", sx - w / 2, sy - h / 2 + 3 * US, w, h, { l.bg[1] * 0.6, l.bg[2] * 0.6, l.bg[3] * 0.6, l.bg[4] }, h / US / 2, 6)
        U.rect(id .. "f", sx - w / 2, sy - h / 2, w, h, l.bg, h / US / 2, 6.1)
        U.text(id .. "t", l.text, sx - w / 2, sy - h / 2, w, h, fs, l.col, "center", 6.3, false)
        return { sx - w / 2, sy - h / 2, w, h }
    else
        U.big(id, l.text, sx, sy, fs, l.col, clamp(fs * 0.8, 1.2, 3.5), 6)
        local w, h = (#l.text * 0.6 + 0.6) * fs * 16 * US, fs * 26 * US
        return { sx - w / 2, sy - h / 2, w, h }
    end
end
local function progress_bar(L)
    local w, h = 560 * US, 22 * US
    local x, y = SW / 2 - w / 2, 92 * US
    U.text("lvname", "Level " .. L.idx .. "  ·  " .. L.name, x - 200 * US, 26 * US, w + 400 * US, 54 * US, 2.0, { 1, 1, 1, 1 }, "center", 31)
    U.rect("pb_bg", x, y, w, h, { .08, .14, .32, 0.5 }, 11, 30)
    local fin = L.len + (L.boss and 51 or 0)
    local k = clamp(C.cz / fin, 0, 1)
    U.rect("pb_fill", x + 4 * US, y + 4 * US, max(h - 8 * US, (w - 8 * US) * k), h - 8 * US, { .35, .75, 1, 1 }, 7, 30.1)
    U.rect("pb_shine", x + 6 * US, y + 5 * US, max(1, (w - 12 * US) * k), (h - 8 * US) * 0.4, { 1, 1, 1, 0.35 }, 4, 30.2)
    U.img("pb_end", L.boss and "man_r" or "star", x + w + 26 * US, y + h / 2, 52, 31)
end
-- the in-run HUD. returns "pause" when the pause button is hit
function HUD.play(dt, L)
    local act
    -- currency pills
    U.pill("hc", 28 * US, 26 * US, 210, "coin", fmt(M.D.coins + (RUN.stats and RUN.stats.coins or 0)), 30)
    U.pill("hg", 252 * US, 26 * US, 150, "gem", fmt(M.D.gems), 30)
    progress_bar(L)
    -- pause
    if U.button("b_pause", "", SW - 70 * US, 62 * US, 84, 84, "white", { r = 42, z = 40 }) then act = "pause" end
    U.img("b_pause_i", "pause", SW - 70 * US, 58 * US, 50, 40.6, { .2, .3, .55, 1 })
    -- shield button
    if (G.shields or 0) > 0 or (G.shield_t or 0) > 0 then
        local cx, cy = SW - 100 * US, SH - 120 * US
        if U.button("b_shield", "", cx, cy, 130, 130, (G.shield_t or 0) > 0 and "purple" or "blue", { r = 65, z = 40 }) then G.use_shield() end
        U.img("b_shield_i", "shield", cx, cy - 6 * US, 84, 40.6)
        U.text("b_shield_n", (G.shield_t or 0) > 0 and string.format("%.1f", G.shield_t) or ("x" .. G.shields), cx - 60 * US, cy + 30 * US, 120, 40 * US, 1.7, { 1, 1, 1, 1 }, "center", 40.7)
        U.text("b_shield_k", "Space", cx - 60 * US, cy + 72 * US, 120, 30 * US, 1.1, { 1, 1, 1, 0.85 }, "center", 40.7)
    end
    -- world labels from the run code
    -- staircase multipliers painted on the coming steps (x1.2 ... x5.0)
    local S = G.stairs
    if S and C.cz > S.z0 - 70 and RUN.phase ~= "dead" then
        local k0 = (G.FIN.s and G.FIN.s.k) or 0
        for i = k0 + 1, min(S.n, k0 + 9) do
            local gold = (i % 5 == 0)
            R.labels[#R.labels + 1] = { x = W - 1.5, y = (i - 0.45) * S.h, z = S.z0 + (i - 1) * S.d - 0.06, text = "x" .. string.format("%.1f", 1 + 0.2 * i),
                col = gold and { 1, .86, .3, 1 } or { 1, 1, 1, 1 }, size = gold and 1.6 or 1.25, bg = { .08, .12, .3, .78 } }
        end
    end
    local rects = {}
    for i, l in ipairs(R.labels) do local r = wlabel("wl" .. i, l); if r then rects[#rects + 1] = r end end
    R.labels = {}
    -- crowd counter badge
    if #C.units > 0 and RUN.phase ~= "dead" then
        local bz, by0 = C.cz + (C.hd or 1) * 0.3, (C.cy or 0)
        -- on the staircase the column is long and climbing: ride just behind its front, on the smooth ramp
        if RUN.phase == "stairs" and G.FIN.s then local S = G.FIN.s; bz = S.front - 1.2; by0 = G.FIN.ramp(bz) end
        local sx, sy, zc = project(LX(C.cx), 2.1 + by0 + min(2, (C.rmax or 1) * 0.15) + (C.cnt[3] > 0 and 1.6 or (C.cnt[2] > 0 and 0.7 or 0)), bz)
        if zc > 1 then
            local txt = fmt(C.power())
            local fs = clamp(52 / zc, 1.8, 3.2)
            local w, h = (#txt * 0.55 + 1.3) * fs * 16 * US, fs * 22 * US
            if RUN.clash then sx = sx - w * 0.6 end   -- keep clear of the red badge during a clash
            -- gate numbers win: the badge sits behind world labels and fades where it overlaps one
            local bx, by = sx - w / 2, sy - h / 2
            local a = 1
            for _, r in ipairs(rects) do
                if bx < r[1] + r[3] and bx + w > r[1] and by < r[2] + r[4] + 6 * US and by + h > r[2] then a = 0.28 end
            end
            HUD.badge_a = damp(HUD.badge_a or 1, a, 10, dt)
            local ba = HUD.badge_a
            U.rect("cnt_b", sx - w / 2, sy - h / 2 + 4 * US, w, h, { .1, .3, .7, ba }, h / US / 2, 5)
            U.rect("cnt_f", sx - w / 2, sy - h / 2, w, h, { .25, .55, 1, ba }, h / US / 2, 5.1)
            U.rect("cnt_h", sx - w / 2 + 6 * US, sy - h / 2 + 3 * US, w - 12 * US, h * 0.4, { 1, 1, 1, .25 * ba }, h / US / 4, 5.2)
            U.text("cnt_t", txt, sx - w / 2, sy - h / 2, w, h, fs, { 1, 1, 1, ba }, "center", 5.3, false)
        end
    end

    -- boss bar
    local B = G.FIN.b
    if B and (B.state == "fight" or (B.state == "wait" and C.cz > B.z - 40)) then
        local w, h = 640 * US, 34 * US
        local x, y = SW / 2 - w / 2, 150 * US
        U.text("boss_n", "The King  " .. fmt(B.hp), x, y - 46 * US, w, 44 * US, 2.0, { 1, .9, .6, 1 }, "center", 31)
        U.rect("boss_bg", x, y, w, h, { .2, .05, .05, 0.65 }, 17, 30)
        local k = clamp(B.hp / max(1, B.hp0), 0, 1)
        U.rect("boss_f", x + 5 * US, y + 5 * US, max(h - 10 * US, (w - 10 * US) * k), h - 10 * US, B.hit and { 1, 1, 1, 1 } or { .95, .25, .25, 1 }, 12, 30.1)
        U.rect("boss_s", x + 8 * US, y + 7 * US, max(1, (w - 16 * US) * k), (h - 10 * US) * 0.4, { 1, 1, 1, .3 }, 6, 30.2)
    end
    HUD.overlays(dt)
    return act
end
-- popups / world pops / tips (also used on the finale)
function HUD.overlays(dt)
    for i = #HUD.pops, 1, -1 do
        local p = HUD.pops[i]
        p.t = p.t + dt
        if p.t > p.dur + 0.3 then table.remove(HUD.pops, i) end
    end
    for i, p in ipairs(HUD.pops) do
        local pop = 1 + 0.45 * max(0, 1 - p.t * 7)
        local a = clamp((p.dur + 0.3 - p.t) / 0.3, 0, 1)
        local col = { p.col[1], p.col[2], p.col[3], a }
        U.big("pop" .. i, p.text, SW / 2, SH * 0.3 - (i - 1) * 80 * US - p.t * 30 * US, 4.2 * pop * (i == 1 and 1 or 0.7), col, 4, 50)
    end
    for i = #HUD.wpops, 1, -1 do
        local p = HUD.wpops[i]
        p.t = p.t + dt
        if p.t > p.dur then table.remove(HUD.wpops, i) end
    end
    for i, p in ipairs(HUD.wpops) do
        local sx, sy, zc = project(LX(p.x), p.y + p.t * 1.5, p.z)
        if zc > 1 then
            local a = clamp((p.dur - p.t) / 0.25, 0, 1)
            U.big("wp" .. i, p.text, sx, sy, clamp(36 / zc, 1, 2.6), { p.col[1], p.col[2], p.col[3], a }, 2, 45)
        end
    end
    local t = HUD.tip
    if t then
        t.t = t.t + dt
        if t.t > 4.2 then HUD.tip = nil
        else
            local a = clamp(min(t.t * 5, (4.2 - t.t) * 3), 0, 1)
            local w, h = max(520, #t.text * 22 + 120) * US, 76 * US
            local y = SH - 190 * US + (1 - a) * 40 * US
            U.rect("tip_s", SW / 2 - w / 2 + 4 * US, y + 8 * US, w, h, { .05, .1, .25, .25 * a }, 38, 44)
            U.rect("tip_b", SW / 2 - w / 2, y, w, h, { 1, 1, 1, .96 * a }, 38, 44.1)
            U.rect("tip_a", SW / 2 - w / 2 + 14 * US, y + 14 * US, h - 28 * US, h - 28 * US, { 1, .75, .2, a }, 24, 44.2)
            U.text("tip_ai", "!", SW / 2 - w / 2 + 14 * US, y + 14 * US, h - 28 * US, h - 28 * US, 2.2, { 1, 1, 1, a }, "center", 44.3, false)
            U.text("tip_t", t.text, SW / 2 - w / 2 + h, y, w - h - 20 * US, h, 2.1, { .15, .22, .42, a }, "center", 44.3, false)
        end
    end
end
end
