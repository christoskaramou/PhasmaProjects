------------------------------------------------------------------ 05_render: the living board (tiles, flags, marching figures, rings, arrows, ability props)
do
local RN = { evi = 0, sndt = {} }
G.RN = RN
local MAXFIG = 260
local KINDS = { "ring_sel", "ring_tgt", "chev", "dot", "dot_bad", "dot_rim", "ice", "shell", "crate" }
for f = 0, 5 do KINDS[#KINDS + 1] = "flag_" .. f end
for f = 1, 5 do KINDS[#KINDS + 1] = "sol_" .. f; KINDS[#KINDS + 1] = "ber_" .. f; KINDS[#KINDS + 1] = "boat_" .. f end
RN.KINDS = KINDS

function RN.reset(S)
    RN.flag = {}
    RN.col = {}
    RN.sndt = {}
    RN.fy = {}
    for i, r in ipairs(S.R) do RN.flag[i] = { owner = r.owner, t = 1 } end
end

local function snd(name, gap)
    local t = RN.sndt[name] or -9
    if G.t - t < (gap or 0.08) then return end
    RN.sndt[name] = G.t
    sfx(name)
end
RN.snd = snd

-- ground height under a world point
local function ground(S, x, z)
    local c = G.SIM.cell(S, x, z)
    if c > 0 then local r = S.R[c]; return r and r.h or 0.5, false end
    if c == 0 then return 0.02, true end
    return 0.3, false
end
RN.ground = ground

local function tiles(S, sel, hov, dt)
    for i, r in ipairs(S.R) do
        local T = G.BD.tiles[i]
        if T then
            local p
            if not r.active then p = { 0.62, 0.6, 0.56 } else p = G.D.FAC[r.owner].pastel end
            local c = RN.col[i]
            if not c then c = { p[1], p[2], p[3] }; RN.col[i] = c end
            local k = 1 - math.exp(-6 * dt)
            for j = 1, 3 do c[j] = c[j] + (p[j] - c[j]) * k end
            local em = 0
            if sel[i] then em = 0.28 + 0.08 * math.sin(G.t * 6) elseif hov == i then em = 0.16 end
            em = em + r.flash * 0.6
            local fr = r.frozen > 0 and 1 or 0
            local b = { c[1] * (1 - 0.35 * fr) + 0.35 * fr * 0.8, c[2] * (1 - 0.35 * fr) + 0.35 * fr * 0.92, c[3] * (1 - 0.35 * fr) + 0.35 * fr * 1.0 }
            local key = string.format("%.3f%.3f%.3f|%.2f", b[1], b[2], b[3], em)
            T.age = (T.age or 0) + 1
            if T.age <= 10 then T.key = nil end   -- build_board's deferred material replays (frames 2 and 6) would otherwise wipe the starting owners' tint
            if T.key ~= key then
                T.key = key
                G.tint_tile(i, b, { b[1] * em, b[2] * em, b[3] * em })
            end
        end
    end
end

local function flags(S, dt)
    for f = 0, 5 do P_begin("flag_" .. f) end
    for i, r in ipairs(S.R) do
        if r.active then
            local fl = RN.flag[i]
            if fl.owner ~= r.owner then fl.owner = r.owner; fl.t = 0 end
            fl.t = min(1, fl.t + dt * 1.6)
            local e = 1 - (1 - fl.t) ^ 3
            local n = P_get("flag_" .. r.owner)
            local s = r.ty == "capital" and 0.55 or 0.45
            place(n, r.x - 0.45, r.h + (e - 1) * 0.9 * s, r.z + 0.45, s, s * (0.4 + 0.6 * e), s, 180 + math.sin(G.t * 1.3 + i) * 8)
        end
    end
    for f = 0, 5 do P_end("flag_" .. f) end
end

local function figures(S, dt)
    for f = 1, 5 do P_begin("sol_" .. f); P_begin("ber_" .. f); P_begin("boat_" .. f) end
    local P = S.P
    local step = max(1, math.ceil(#P / MAXFIG))
    local fy = RN.fy
    local seen = {}
    for idx = 1, #P, step do
        local p = P[idx]
        local h, sea = ground(S, p.x, p.z)
        local y = fy[p.id] or h
        y = y + (h - y) * min(1, dt * 10)
        fy[p.id] = y; seen[p.id] = true
        local kind = (sea and not p.port and "boat_" or (sea and "boat_" or (p.bearer and "ber_" or "sol_"))) .. p.f
        local n = P_get(kind)
        local dx, dz = p.tx - p.x, p.tz - p.z
        local ry = math.deg(math.atan2(dx, dz))
        local s = 0.36 * (1 + 0.14 * min(p.k - 1, 5)) * (sea and 1.15 or 1)
        local bob = sea and (math.sin(G.t * 3 + p.id) * 0.03) or (abs(math.sin(G.t * 9 + p.id * 1.7)) * 0.06)
        local sway = sea and math.sin(G.t * 2 + p.id) * 4 or math.sin(G.t * 9 + p.id * 1.7) * 5
        local pop = min(1, p.age * 5)
        place(n, p.x, y + bob, p.z, s * pop, s * pop, s * pop, ry, 0, sway)
    end
    for id in pairs(fy) do if not seen[id] then fy[id] = nil end end
    for f = 1, 5 do P_end("sol_" .. f); P_end("ber_" .. f); P_end("boat_" .. f) end
end

-- rings under selected / targeted regions; a line of big round dots from each selected region to the target
-- (white core on an Azure rim; grey on a dark rim while the cursor has no valid target). Dots are opaque meshes
-- lifted 0.16 above the ground under them, with a gentle pulse travelling toward the target.
local DOT_SP, DOT_LIFT, DOT_MAX, DOT_K = 1.1, 0.16, 120, 1.9   -- spacing, lift, pool budget, dot size
local function dot_line(S, r, tx, tz, ok, budget)
    local dx, dz = tx - r.x, tz - r.z
    local dl = math.sqrt(dx * dx + dz * dz)
    if dl < 1.6 then return 0 end
    local ux, uz = dx / dl, dz / dl
    local d0, d1 = 1.05, dl - (ok and 1.2 or 0.3)
    local n = math.max(0, math.floor((d1 - d0) / DOT_SP + 0.5))
    local sp = n > 0 and (d1 - d0) / n or 0
    local kind = ok and "dot" or "dot_bad"
    local cnt = 0
    for k = 0, n do
        if cnt >= budget then break end
        local d = d0 + k * sp
        local x, z = r.x + ux * d, r.z + uz * d
        local h = ground(S, x, z)
        local w = math.cos(d * 1.2 - G.t * 7.5)
        local s = DOT_K * (1 + (ok and 0.28 or 0.1) * (w > 0 and w * w * w * w or 0))
        place(P_get("dot_rim"), x, h + DOT_LIFT, z, s, 1, s, 0)
        place(P_get(kind), x, h + DOT_LIFT + 0.02, z, s, s, s, 0)
        cnt = cnt + 1
    end
    return cnt
end
RN.dot_line = dot_line

local function rings(S, sel, tgt, drag)
    P_begin("ring_sel"); P_begin("ring_tgt"); P_begin("chev"); P_begin("dot"); P_begin("dot_bad"); P_begin("dot_rim")
    for i in pairs(sel) do
        local r = S.R[i]
        local s = 0.7 + 0.15 * r.size
        place(P_get("ring_sel"), r.x, r.h + 0.04, r.z, s, 1, s, G.t * 40)
    end
    if tgt then
        local r = S.R[tgt]
        local s = (0.8 + 0.15 * r.size) * (1 + 0.06 * math.sin(G.t * 8))
        place(P_get("ring_tgt"), r.x, r.h + 0.05, r.z, s, 1, s, -G.t * 50)
    end
    -- send preview: while dragging, or while hovering a target with regions selected
    if drag or tgt then
        local cnt = 0
        for i in pairs(sel) do
            if i ~= tgt then
                local r = S.R[i]
                local tx, tz, ok
                if tgt then tx, tz, ok = S.R[tgt].x, S.R[tgt].z, true else tx, tz, ok = drag.x, drag.z, false end
                cnt = cnt + dot_line(S, r, tx, tz, ok, DOT_MAX - cnt)
            end
        end
    end
    P_end("ring_sel"); P_end("ring_tgt"); P_end("chev"); P_end("dot"); P_end("dot_bad"); P_end("dot_rim")
end

local function props(S)
    P_begin("ice"); P_begin("shell"); P_begin("crate")
    for i, r in ipairs(S.R) do
        if r.active and r.frozen > 0 then
            local k = min(1, r.frozen * 2)
            place(P_get("ice"), r.x + 0.5, r.h, r.z - 0.35, 0.55 * k, 0.6 * k, 0.55 * k, i * 40)
        end
    end
    for _, s in ipairs(S.fx.shells) do
        local r = S.R[s.r]
        local k = 1 - s.t
        place(P_get("shell"), r.x + (1 - k) * 2.5, r.h + 9 * (1 - k) + 0.3, r.z - (1 - k) * 3, 1.3, 1.3, 1.3, 0, 30 + 40 * k)
    end
    for _, d in ipairs(S.fx.drops) do
        local r = S.R[d.r]
        local k = 1 - d.t / 1.2
        place(P_get("crate"), r.x + 0.4, r.h + 8 * (1 - k) + 0.3, r.z + 0.2, 0.7, 0.7, 0.7, G.t * 30, math.sin(G.t * 4) * 6)
    end
    P_end("ice"); P_end("shell"); P_end("crate")
end

-- one-shot effects + sounds from sim events
local function events(S)
    local FX, D = G.FX, G.D
    for _, e in ipairs(S.ev) do
        if e.k == "capture" then
            local r = S.R[e.r]
            local col = D.FAC[e.f].col
            FX.capture(r.x, r.h, r.z, col)
            if e.f == 1 then snd("capture", 0.15) elseif e.old == 1 then snd("lost", 0.15); if G.HUD and not S.demo then G.HUD.toast(r.name .. " lost!", "red", nil, "lost" .. e.r) end
            else snd("neutral", 0.2) end
            if G.on_capture then G.on_capture(S, e) end
        elseif e.k == "hit" then
            if math.random() < 0.25 then local r = S.R[e.r]; FX.hit(r.x, r.h, r.z, D.FAC[e.f].col) end
        elseif e.k == "clash" then
            local h = ground(S, e.x, e.z)
            if math.random() < 0.5 then FX.clash(e.x, h, e.z, e.n) end
            snd("clash", 0.12)
        elseif e.k == "send" then
            if e.f == 1 then snd("send", 0.15) end
        elseif e.k == "drop" then
            local r = S.R[e.r]; FX.airdrop(r.x, r.h, r.z, D.FAC[e.f].col); snd("airdrop", 0.1)
        elseif e.k == "boom" then
            local r = S.R[e.r]; FX.barrage(r.x, r.h, r.z); snd("boom", 0.1)
        elseif e.k == "abil" then
            if e.a == "frost" then local r = S.R[e.r]; FX.frost(r.x, r.h, r.z, D.ABIL[D.ABIX.frost].rad); snd("frost", 0.1)
            elseif e.a == "march" then snd("march_horn", 0.1)
            elseif e.a == "barrage" then snd("whistle", 0.1) end
            if e.f ~= 1 and G.HUD and not S.demo then G.HUD.toast(D.FAC[e.f].short .. " used " .. D.ABIL[D.ABIX[e.a]].name .. "!", "orange", nil, "ab" .. e.a) end
        end
    end
    S.ev = {}
end

function RN.update(S, dt, sel, hov, tgt, drag)
    events(S)
    tiles(S, sel, hov, dt)
    flags(S, dt)
    figures(S, dt)
    rings(S, sel, tgt, drag)
    props(S)
end
function RN.clear()
    for _, k in ipairs(KINDS) do P_begin(k); P_end(k) end
end
end
