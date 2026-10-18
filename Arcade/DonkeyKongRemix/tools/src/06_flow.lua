------------------------------------------------------------------ stage order (US arcade) + flow
local SEQS = { { "25", "100" }, { "25", "75", "100" }, { "25", "50", "75", "100" }, { "25", "50", "25", "75", "100" }, { "25", "50", "25", "75", "25", "100" } }
local function seq() return SEQS[min(G.level, 5)] end
G.seq_i = 1
local function start_stage(kind)
    clear_ents()
    build_stage(kind)
    G.cut = nil; G.cam_ov = nil; G.kong_hidden = false; G.paul_hidden = false; G.stack_hidden = false; G.attract = false
    for _, h in ipairs(RIGS.hh) do h.root:set_position(HIDE) end
    for _, n in ipairs(G.hh_g) do n:set_position(HIDE) end
    set_point(LT.hh, HIDE, V(1, 1, 1), 0, 1)
    KONG.x, KONG.y = ST.dk.x, ST.dk.y; KONG.ox, KONG.oy = KONG.x, KONG.y; KONG.st = ST.dk.patrol and "walk" or "idle"; KONG.t = 90; KONG.dir = 1; KONG.throws = 0; KONG.yaw_ov = nil
    PAUL.x, PAUL.y = ST.pauline.x, ST.pauline.y; PAUL.carried = nil; PAUL.yaw = nil; PAUL.help = 0; PAUL.t = 0; PAUL.z = nil
    mario_reset(ST.mario)
    G.bonus = min(8000, 4000 + 1000 * G.level); G.bonus_f = 0; G.stage_f = 0; G.first_done = false
    G.pie_t, G.fox_t = 60, (kind == "100") and 60 or 240
    ST.rivets_left = #ST.rivets
    RIGS.heart:set_position(HIDE); RIGS.heart_l:set_position(HIDE); RIGS.heart_r:set_position(HIDE)
    music(ST.music)
    G.state = "play"
end
G.start_stage = start_stage

-- "How high can you get?" : Kong statues stacked for every 25 m reached
local HHX = 140
local function how_high(kind)
    G.state = "howhigh"; G.hh_t = 0; G.hh_kind = kind; G.hh_n = tonumber(kind) / 25
    music(nil); sfx("howhigh")
    set_point(LT.hh, V(HHX + 4, -9 + (G.hh_n - 1) * 2.8 + 4, 14), V(1, .92, .85), 120, 40)
    for i, r in ipairs(RIGS.hh) do
        if i <= G.hh_n then pose_dk(r, { pos = V(HHX, -9 + (i - 1) * 5.6, 0), s = 1, alz = -25, arz = 25, alx = -10, arx = -10 }) else r.root:set_position(HIDE) end
    end
    for i, n in ipairs(G.hh_g) do
        local lv = floor((i - 1) / 3) + 1
        if lv <= G.hh_n then n:set_position(V(HHX - 2 + ((i - 1) % 3) * 2, -9 + (lv - 1) * 5.6, 0)) else n:set_position(HIDE) end
    end
end
local function next_stage()
    G.seq_i = G.seq_i + 1
    if G.seq_i > #seq() then G.level = G.level + 1; G.seq_i = 1 end
    how_high(seq()[G.seq_i])
end

------------------------------------------------------------------ cutscenes
local function cut_bend(dt)
    local c = G.cut
    if not c or not c.bends then return end
    for gi, t0 in pairs(c.bends) do
        local k = clamp((c.t - t0) / 0.32, 0, 1)
        local b = k + sin(k * PI) * 0.35 * (1 - k * 0.5)
        if k >= 1 then b = 1; c.bends[gi] = nil end
        G.bend(gi, b)
    end
    G.refresh_ladders()
end
local function intro_start()
    clear_ents()
    build_stage("25")
    G.state = "intro"; G.attract = false
    G.cut = { kind = "intro", t = 0, hop = 0, bends = {} }
    M.st = "hidden"
    G.kong_hidden = false; G.paul_hidden = false; G.stack_hidden = true
    for _, l in ipairs(ST.ladders) do l.hidden = true end
    for _, d in ipairs(ST.deco_ladders) do d.hidden = true end
    G.bend_all(0)
    KONG.x, KONG.y = 112, 248; KONG.ox, KONG.oy = 112, 248; KONG.st = "climb"; KONG.yaw_ov = nil
    PAUL.x, PAUL.y = 112, 56; PAUL.help = 0
    P_begin("rung_i"); for i, n in ipairs(G.intro_lad) do G.lad_seg(n, 104 + (i - 1) * 16, 248, 56, -0.3, "rung_i") end; P_end("rung_i")
    music(nil); sfx("intro")
end
G.intro_start = intro_start
local HOPS = { 112, 100, 88, 76, 64, 54, 44 }
local function intro_update(dt)
    local c = G.cut
    c.t = c.t + dt
    local t = c.t
    if t < 5.5 then
        KONG.st = "climb"; KONG.y = lerp(248, 84, t / 5.5); KONG.x = 112
        PAUL.carried = V(WX(112) + 1.0, WY(KONG.y) + 3.9, 0.7)
    elseif t < 6.4 then
        KONG.y = 84; KONG.st = "idle"; KONG.yaw_ov = 180
        if t > 5.75 then PAUL.carried = nil; PAUL.help = 1 end
    elseif t < 7.0 then
        KONG.yaw_ov = nil
        local k = (t - 6.4) / 0.6
        P_begin("rung_i")
        for i, n in ipairs(G.intro_lad) do G.lad_seg(n, 104 + (i - 1) * 16, lerp(248, 56, k), 56, -0.3, "rung_i") end
        P_end("rung_i")
    else
        for _, n in ipairs(G.intro_lad) do n:set_position(HIDE) end; P_begin("rung_i"); P_end("rung_i")
        PAUL.help = 0
        local ht = 0.62
        local i = floor((t - 7.0) / ht) + 1
        if i <= 6 then
            local u = ((t - 7.0) % ht) / ht
            KONG.st = "hop"; KONG.x = lerp(HOPS[i], HOPS[i + 1], u); KONG.y = 84 - 16 * sin(PI * u)
            if c.hop < i - 1 or (c.hop < i and u > 0.97) then end
            if c.hop < i and u > 0.92 then
                c.hop = i
                local gi = ({ 6, 5, 4, 3, 2, 1 })[i]
                c.bends[gi] = t
                sfx("stomp"); G.shake = 0.7
                local g = ST.girders[gi]
                for x = g.x0 + 8, gx1(g) - 8, 40 do dust(x, surf(g, x), 5) end
            end
        else
            KONG.x, KONG.y = 44, 84
            KONG.st = "grin"
            if not c.lad then
                c.lad = true
                for _, l in ipairs(ST.ladders) do l.hidden = false end
                for _, d in ipairs(ST.deco_ladders) do d.hidden = false end
                G.refresh_ladders()
            end
            if t > 7.0 + 6 * ht + 1.6 then
                G.cut = nil; G.stack_hidden = false; KONG.st = "idle"
                G.seq_i = 1
                how_high(seq()[1])
                return
            end
        end
    end
    KONG.ox, KONG.oy = KONG.x, KONG.y
    cut_bend(dt)
end
local function clear_start()
    clear_ents()
    music(nil); sfx("clear")
    G.state = "clear"
    G.cut = { kind = ST.kind == "100" and "end100" or "clear", t = 0, bonus_done = false }
    M.ham = 0; M.st = "win"
    if ST.kind == "100" then
        G.cut.segs = {}
        for gi = 2, 5 do
            local g = ST.girders[gi]
            for i, n in ipairs(g.nodes) do
                local cx = g.x0 + g.sw * (i - 0.5)
                if cx > 56 and cx < 168 then G.cut.segs[#G.cut.segs + 1] = { n = n, x = WX(cx), y = WY(g.ys[i]), vy = 0, r = rr(-60, 60), d = rr(0, 0.25) } end
            end
        end
        for _, l in ipairs(ST.ladders) do l.hidden = true end
        G.refresh_ladders()
    end
end
G.clear_start = clear_start
local function heart_at(px, py, s)
    RIGS.heart:set_position(V(WX(px), WY(py), 0.4)); RIGS.heart:set_scale(V(s, s, s)); RIGS.heart:set_rotation(V(0, 15 * sin(G.t * 3), 0))
end
local function clear_update(dt)
    local c = G.cut
    c.t = c.t + dt
    local t = c.t
    local hx = (M.x + PAUL.x) / 2
    if not c.bonus_done and t > 0.8 then
        c.bonus_done = true; add_score(G.bonus); G.banner = { text = "Bonus " .. G.bonus, t = 2.4 }; sfx("bonus")
    end
    if c.kind == "clear" then
        PAUL.yaw = (M.x < PAUL.x) and -45 or 45
        if t < 1.5 then
            heart_at(hx, PAUL.y - 26, min(1, t * 3) * (1 + 0.08 * sin(t * 10)))
        elseif t < 2.0 then
            -- Kong snatches Pauline; the heart breaks
            RIGS.heart:set_position(HIDE)
            local k = (t - 1.5) / 0.5
            RIGS.heart_l:set_position(V(WX(hx) - k * 1.2, WY(PAUL.y - 26) - k * k * 3, 0.4)); RIGS.heart_l:set_rotation(V(0, 0, 25 * k))
            RIGS.heart_r:set_position(V(WX(hx) + k * 1.2, WY(PAUL.y - 26) - k * k * 3, 0.4)); RIGS.heart_r:set_rotation(V(0, 0, -25 * k))
            if not c.snatch then c.snatch = true; sfx("beat") end
        else
            RIGS.heart_l:set_position(HIDE); RIGS.heart_r:set_position(HIDE)
            local kx = ST.kind == "25" and 72 or KONG.x
            if not c.kx0 then c.kx0 = KONG.x; c.ky0 = KONG.y end
            local k = clamp((t - 2.0) / 0.6, 0, 1)
            KONG.x = lerp(c.kx0, kx, k)
            if k >= 1 then KONG.st = "climb"; KONG.y = c.ky0 - (t - 2.6) * 34 else KONG.st = "walk"; KONG.dir = kx > c.kx0 and 1 or -1 end
            PAUL.carried = V(WX(KONG.x) + 1.0, WY(KONG.y) + 3.9, 0.7)
        end
        if t > 5.2 then next_stage() end
    else
        -- 100m: Kong roars, the middle of the tower collapses, he falls head first; Mario and Pauline meet on top
        PAUL.yaw = -45
        if t < 1.0 then KONG.st = "beat"; G.shake = 0.4
        else
            if not c.fall then c.fall = true; c.ky = KONG.y; c.kvy = 0; KONG.st = "fall"; sfx("fall") end
            for _, s in ipairs(c.segs) do
                if t > 1.0 + s.d then
                    s.vy = s.vy + dt * 30; s.y = s.y - s.vy * dt
                    s.n:set_position(V(s.x, s.y, 0)); s.n:set_rotation(V(0, 0, s.r * (t - 1.0)))
                    if s.y < -30 then s.n:set_position(HIDE) end
                end
            end
            if KONG.st == "fall" then
                c.kvy = c.kvy + dt * 150; KONG.y = KONG.y + c.kvy * dt
                if KONG.y >= 248 then KONG.y = 248; KONG.st = "dazed"; sfx("stomp"); G.shake = 1; dust(KONG.x - 12, 248, 12); dust(KONG.x + 12, 248, 12) end
            end
            if t > 1.4 and not c.top then c.top = true; M.x, M.y, M.g = 100, 48, 6; M.ox, M.oy = M.x, M.y; M.face = 1; PAUL.x = 124 end
            if t > 3.0 then heart_at(112, 22, min(1, (t - 3.0) * 3) * (1 + 0.08 * sin(t * 10))) end
        end
        if t > 7.5 then next_stage() end
    end
    KONG.ox, KONG.oy = KONG.x, KONG.y
end
