------------------------------------------------------------------ stage data (original pixel space: x 0..223 right, y 0..255 down)
-- girder = { x0, sw (segment width px), ys = top surface y per segment, dir = barrel roll direction, conv = conveyor dir }
local function seq_ys(n, a, step) local t = {}; for i = 1, n do t[i] = a + (i - 1) * step end; return t end
local function flat(n, y) return seq_ys(n, y, 0) end
local function cat(a, b) local t = {}; for _, v in ipairs(a) do t[#t + 1] = v end; for _, v in ipairs(b) do t[#t + 1] = v end; return t end
local STAGE_DEF = {}
STAGE_DEF["25"] = function()
    return {
        kind = "25", mesh = "g_red", height = "25 m", music = "bgm25",
        girders = {
            { x0 = 0, sw = 16, ys = cat(flat(7, 248), seq_ys(7, 247, -1)), dir = -1 },   -- G1 bottom, oil drum on the left
            { x0 = 0, sw = 16, ys = seq_ys(13, 205, 1), dir = 1 },                        -- G2
            { x0 = 16, sw = 16, ys = seq_ys(13, 184, -1), dir = -1 },                     -- G3
            { x0 = 0, sw = 16, ys = seq_ys(13, 139, 1), dir = 1 },                        -- G4
            { x0 = 16, sw = 16, ys = seq_ys(13, 118, -1), dir = -1 },                     -- G5
            { x0 = 0, sw = 16, ys = cat(flat(9, 84), seq_ys(4, 85, 1)), dir = 1 },        -- G6 Kong's girder
            { x0 = 88, sw = 16, ys = flat(3, 56), dir = 1, top = true },                   -- Pauline
        },
        ladders = {
            { x = 80, lo = 1, hi = 2, broken = true }, { x = 184, lo = 1, hi = 2 },
            { x = 32, lo = 2, hi = 3 }, { x = 96, lo = 2, hi = 3 }, { x = 168, lo = 2, hi = 3, broken = true },
            { x = 64, lo = 3, hi = 4, broken = true }, { x = 112, lo = 3, hi = 4 }, { x = 184, lo = 3, hi = 4 },
            { x = 32, lo = 4, hi = 5 }, { x = 72, lo = 4, hi = 5, broken = true }, { x = 168, lo = 4, hi = 5 },
            { x = 72, lo = 5, hi = 6, broken = true }, { x = 184, lo = 5, hi = 6 },
            { x = 128, lo = 6, hi = 7 },
        },
        deco_ladders = { { x = 64, y0 = 84, y1 = 16 }, { x = 80, y0 = 84, y1 = 16 } },
        hammers = { { x = 168, g = 2 }, { x = 24, g = 5 } },
        items = {},
        drum = { x = 24, y = 248 },
        mario = { x = 60, g = 1 }, dk = { x = 44, y = 84 }, pauline = { x = 112, y = 56 },
        goal = function(m) return m.g == 7 end,
    }
end
STAGE_DEF["50"] = function()
    return {
        kind = "50", mesh = "g_orange", height = "50 m", music = "bgm50",
        girders = {
            { x0 = 0, sw = 16, ys = flat(14, 248), dir = 1 },                        -- 1 floor
            { x0 = 16, sw = 16, ys = flat(12, 208), conv = 1, swap = true },        -- 2 long belt (reverses)
            { x0 = 0, sw = 16, ys = flat(6, 168), conv = 1 },                       -- 3 left belt into the fire
            { x0 = 96, sw = 16, ys = flat(2, 168) },                                 -- 4 oil fire stand
            { x0 = 128, sw = 16, ys = flat(6, 168), conv = -1 },                    -- 5 right belt into the fire
            { x0 = 0, sw = 16, ys = flat(5, 128) },                                  -- 6
            { x0 = 88, sw = 16, ys = flat(3, 128), conv = -1, swap = true },        -- 7 short belt
            { x0 = 144, sw = 16, ys = flat(5, 128) },                                -- 8
            { x0 = 0, sw = 16, ys = flat(14, 88), conv = 1, swap = true, top = true }, -- 9 Kong's belt (goal)
            { x0 = 88, sw = 16, ys = flat(3, 48) },                                  -- 10 Pauline
        },
        ladders = {
            { x = 24, lo = 1, hi = 2 }, { x = 112, lo = 1, hi = 2 }, { x = 200, lo = 1, hi = 2 },
            { x = 48, lo = 2, hi = 3 }, { x = 176, lo = 2, hi = 5 },
            { x = 40, lo = 3, hi = 6, retract = true }, { x = 72, lo = 3, hi = 6 }, { x = 152, lo = 5, hi = 8 }, { x = 184, lo = 5, hi = 8, retract = true },
            { x = 16, lo = 6, hi = 9 }, { x = 64, lo = 6, hi = 9, retract = true }, { x = 160, lo = 8, hi = 9, retract = true }, { x = 208, lo = 8, hi = 9 },
        },
        hammers = { { x = 24, g = 6 }, { x = 104, g = 2 } },
        items = { { kind = "it_umbrella", x = 40, g = 2 }, { kind = "it_hat", x = 168, g = 1 }, { kind = "it_purse", x = 200, g = 8 } },
        fire = { x = 112, y = 168 },
        mario = { x = 60, g = 1 }, dk = { x = 112, y = 88, patrol = { 72, 152 } }, pauline = { x = 112, y = 48 },
        goal = function(m) return m.g == 9 end,
    }
end
STAGE_DEF["75"] = function()
    return {
        kind = "75", mesh = "g_red", height = "75 m", music = "bgm75", pit = true,
        girders = {
            { x0 = 0, sw = 8, ys = flat(4, 240) },        -- 1 start ledge
            { x0 = 72, sw = 8, ys = flat(3, 184) },       -- 2 island A
            { x0 = 72, sw = 8, ys = flat(3, 128) },       -- 3 island B
            { x0 = 128, sw = 8, ys = flat(4, 232) },      -- 4 low right
            { x0 = 136, sw = 8, ys = flat(11, 184) },     -- 5
            { x0 = 160, sw = 8, ys = flat(8, 144) },      -- 6
            { x0 = 136, sw = 8, ys = flat(7, 112) },      -- 7
            { x0 = 0, sw = 8, ys = flat(24, 84) },        -- 8 Kong's girder (springs)
            { x0 = 88, sw = 8, ys = flat(6, 56), top = true }, -- 9 Pauline
        },
        ladders = {
            { x = 88, lo = 2, hi = 3 }, { x = 76, lo = 3, hi = 8 },
            { x = 148, lo = 4, hi = 5 }, { x = 212, lo = 5, hi = 6 }, { x = 172, lo = 6, hi = 7 }, { x = 144, lo = 7, hi = 8 },
            { x = 128, lo = 8, hi = 9 },
        },
        elevators = { { x = 56, dir = -1 }, { x = 112, dir = 1 } },
        hammers = {},
        items = { { kind = "it_umbrella", x = 80, g = 3 }, { kind = "it_purse", x = 216, g = 6 }, { kind = "it_hat", x = 100, g = 8 } },
        mario = { x = 14, g = 1 }, dk = { x = 28, y = 84 }, pauline = { x = 112, y = 56 },
        goal = function(m) return m.g == 9 end,
    }
end
STAGE_DEF["100"] = function()
    local R = { 56, 168 }
    local function fl(x0, x1, y) return { x0 = x0, sw = 8, ys = flat((x1 - x0) / 8, y), rivets = (y < 248 and y > 48) and { R[1], R[2] } or nil } end
    return {
        kind = "100", mesh = "g_blue", height = "100 m", music = "bgm100",
        girders = { fl(0, 224, 248), fl(8, 216, 208), fl(16, 208, 168), fl(24, 200, 128), fl(32, 192, 88), { x0 = 88, sw = 8, ys = flat(6, 48), top = true } },
        ladders = {
            { x = 16, lo = 1, hi = 2 }, { x = 112, lo = 1, hi = 2 }, { x = 208, lo = 1, hi = 2 },
            { x = 24, lo = 2, hi = 3 }, { x = 84, lo = 2, hi = 3 }, { x = 140, lo = 2, hi = 3 }, { x = 200, lo = 2, hi = 3 },
            { x = 32, lo = 3, hi = 4 }, { x = 112, lo = 3, hi = 4 }, { x = 192, lo = 3, hi = 4 },
            { x = 40, lo = 4, hi = 5 }, { x = 88, lo = 4, hi = 5 }, { x = 136, lo = 4, hi = 5 }, { x = 184, lo = 4, hi = 5 },
        },
        hammers = { { x = 24, g = 3 }, { x = 200, g = 2 } },
        items = { { kind = "it_umbrella", x = 188, g = 2 }, { kind = "it_purse", x = 44, g = 3 }, { kind = "it_hat", x = 176, g = 4 } },
        mario = { x = 60, g = 1 }, dk = { x = 112, y = 88, patrol = { 80, 144 } }, pauline = { x = 112, y = 48 },
        goal = function() return false end,
    }
end

------------------------------------------------------------------ live stage + surface queries
local ST = nil
G.ST = function() return ST end
local function gx1(g) return g.x0 + g.sw * #g.ys end
local function in_hole(g, x, who)
    if not g.holes then return false end
    for _, h in ipairs(g.holes) do
        if h.open and x >= h.a and x < h.b and not (who == "mario" and h.grace) then return true end
    end
    return false
end
local function covers(g, x, who) return x >= g.x0 and x < gx1(g) and not in_hole(g, x, who) end
local function surf(g, x)
    local i = clamp(floor((x - g.x0) / g.sw) + 1, 1, #g.ys)
    return g.ys[i]
end
-- floors near y (inclusive band): returns girder index, surface y (elevator platforms are returned as "E"..)
local function floor_near(x, y, up, down, who)
    local best, by, bd = nil, nil, 1e9
    for i, g in ipairs(ST.girders) do
        if covers(g, x, who) then
            local s = surf(g, x)
            if s >= y - up and s <= y + down then
                local d = abs(s - y); if d < bd then best, by, bd = i, s, d end
            end
        end
    end
    if ST.plats then
        for _, p in ipairs(ST.plats) do
            if p.live and x >= p.x - 8 and x < p.x + 8 and p.y >= y - up and p.y <= y + down then
                local d = abs(p.y - y); if d < bd then best, by, bd = p, p.y, d end
            end
        end
    end
    return best, by
end
local function ladder_at(x, y, tol)
    for _, l in ipairs(ST.ladders) do
        if abs(x - l.x) <= (tol or 3) and y <= l.ylo + 0.5 and y >= l.yhi - 0.5 then return l end
    end
end
local function ladder_bottom(x, y, tol)
    for _, l in ipairs(ST.ladders) do if abs(x - l.x) <= (tol or 3) and abs(y - l.ylo) <= 2.5 then return l end end
end
local function ladder_top(x, y, tol)
    for _, l in ipairs(ST.ladders) do if abs(x - l.x) <= (tol or 3) and abs(y - l.yhi) <= 2.5 then return l end end
end
-- highest point Mario can climb to on a ladder (broken / retracted ladders stop short)
local function ladder_limit(l)
    if l.broken then return l.ylo - (l.ylo - l.yhi) * 0.42 end
    if l.retract then return lerp(l.yhi, l.ylo - (l.ylo - l.yhi) * 0.42, l.rk or 0) end
    return l.yhi
end

------------------------------------------------------------------ backdrop (built once): night city + scaffold
local function build_backdrop()
    local function block(x, y, z, w, h, d) clone("bg_block", vec3(x, y, z), vec3(w, h, d)) end
    math.randomseed(77)
    for i = -16, 16 do
        local x = i * 4.6 + rr(-1, 1)
        local h = rr(14, 34) + (abs(i) > 6 and 6 or 0)
        block(x, -26, -60 - rr(0, 20), rr(3.5, 5.5), h, rr(3, 6))
    end
    for i = -9, 9 do
        local x = i * 6 + rr(-1.5, 1.5)
        if abs(x) > 17 then block(x, -24, -28 - rr(0, 6), rr(3, 5), rr(10, 22), rr(3, 5)) end
    end
    -- steel scaffold behind the playfield (posts + cross beams)
    for i = 0, 6 do
        local x = -13.6 + i * 4.53
        clone("bg_post", vec3(x, -17, -3.2), vec3(1.3, 34, 1.3))
    end
    for j = 0, 7 do clone("bg_post", vec3(0, -15.5 + j * 4.4, -3.25), vec3(0.8, 27.6, 0.8)):set_rotation(vec3(0, 0, 90)) end
    math.randomseed(floor(G.t * 1000 + 4242))
    G.ground = prim("cube", vec3(0, -17.6, -6), vec3(120, 1.2, 40))
    paint(G.ground, { .06, .06, .07 }, { 0, 0, 0 }, .9, 0)
end

------------------------------------------------------------------ stage build (pooled clones)
local POOLED = { "g_red", "g_orange", "g_blue", "ladder", "conv_belt", "conv_tread", "conv_roller", "rivet", "el_cable", "el_motor", "od_body", "od_band", "flame",
    "hm_handle", "hm_head", "it_hat", "it_purse", "it_umbrella" }
local function place_girders(g, gi)
    local mesh = g.conv and "conv_belt" or ST.mesh
    g.nodes = g.nodes or {}
    for i, y in ipairs(g.ys) do
        local n = g.nodes[i]
        if not n then n = P_get(mesh); g.nodes[i] = n end
        local cx = g.x0 + g.sw * (i - 0.5)
        local hidden = false
        if g.holes then for _, h in ipairs(g.holes) do if h.open and cx >= h.a and cx < h.b then hidden = true end end end
        n:set_position(hidden and HIDE or vec3(WX(cx), WY(y), ((i + gi) % 2) * 0.004))
        n:set_scale(vec3(g.sw / 16, g.conv and 1.35 or 1, 1))
    end
end
local function build_stage(kind)
    for _, k in ipairs(POOLED) do P_begin(k) end
    ST = STAGE_DEF[kind]()
    for gi, g in ipairs(ST.girders) do
        g.final = {}; for i, y in ipairs(g.ys) do g.final[i] = y end
        if g.rivets then
            g.holes = {}
            for _, rx in ipairs(g.rivets) do g.holes[#g.holes + 1] = { a = rx - 4, b = rx + 4, open = false, x = rx } end
        end
        place_girders(g, gi)
        if g.conv then
            g.treads, g.rollers = {}, {}
            local len = gx1(g) - g.x0
            for i = 1, floor(len / 8) do g.treads[i] = P_get("conv_tread") end
            g.rollers[1] = P_get("conv_roller"); g.rollers[2] = P_get("conv_roller")
            g.phase = 0
        end
    end
    for _, l in ipairs(ST.ladders) do
        l.ylo = surf(ST.girders[l.lo], l.x); l.yhi = surf(ST.girders[l.hi], l.x)
        l.nodes = { P_get("ladder") }
        if l.broken or l.retract then l.nodes[2] = P_get("ladder") end
        l.rk = 0
    end
    if ST.deco_ladders then for _, d in ipairs(ST.deco_ladders) do d.node = P_get("ladder") end end
    -- rivets (100m)
    ST.rivets = {}
    for gi, g in ipairs(ST.girders) do
        if g.holes then for _, h in ipairs(g.holes) do
            local n = P_get("rivet")
            n:set_position(vec3(WX(h.x), WY(surf(g, h.x)), 0.02)); n:set_scale(vec3(1.05, 1, 1))
            ST.rivets[#ST.rivets + 1] = { g = gi, h = h, node = n, x = h.x, y = surf(g, h.x) }
        end end
    end
    -- elevators (75m): three platforms per shaft, cables and motors
    if ST.elevators then
        ST.plats = {}
        for _, e in ipairs(ST.elevators) do
            for k = 0, 2 do
                local p = { x = e.x, dir = e.dir, ph = k / 3, live = true, node = P_get(ST.mesh), y = 200 }
                ST.plats[#ST.plats + 1] = p
            end
            local c1, c2 = P_get("el_cable"), P_get("el_cable")
            c1:set_position(vec3(WX(e.x - 7), WY(250), -0.4)); c1:set_scale(vec3(1, (250 - 92) / 8, 1))
            c2:set_position(vec3(WX(e.x + 7), WY(250), -0.4)); c2:set_scale(vec3(1, (250 - 92) / 8, 1))
            local m1, m2 = P_get("el_motor"), P_get("el_motor")
            m1:set_position(vec3(WX(e.x), WY(93), -0.1)); m2:set_position(vec3(WX(e.x), WY(251), -0.1))
        end
    end
    -- oil drum
    if ST.drum or ST.fire then
        local d = ST.drum or ST.fire
        local b, band, fl = P_get("od_body"), P_get("od_band"), P_get("flame")
        b:set_position(vec3(WX(d.x), WY(d.y), 0)); band:set_position(vec3(WX(d.x), WY(d.y), 0))
        ST.flame = fl; ST.drum_xy = d
        ST.lit = ST.fire ~= nil
    end
    -- hammers + items
    ST.hammer_props = {}
    for _, h in ipairs(ST.hammers) do
        local g = ST.girders[h.g]
        local hp = { x = h.x, y = surf(g, h.x) - 22, live = true, n1 = P_get("hm_handle"), n2 = P_get("hm_head") }
        ST.hammer_props[#ST.hammer_props + 1] = hp
    end
    for _, it in ipairs(ST.items) do
        it.y = surf(ST.girders[it.g], it.x); it.live = true; it.node = P_get(it.kind)
    end
    for _, k in ipairs(POOLED) do P_end(k) end
    G.bend_all(1)
end
-- girder bend factor for the intro (0 = flat, 1 = original slants); also refreshes ladders
function G.bend_all(b) for gi = 1, #ST.girders do G.bend(gi, b) end; G.refresh_ladders() end
function G.bend(gi, b)
    local g = ST.girders[gi]
    local avg = 0; for _, y in ipairs(g.final) do avg = avg + y end; avg = avg / #g.final
    if gi == 1 then avg = g.final[1] end
    if gi == 6 and ST.kind == "25" then avg = 84 end
    for i, y in ipairs(g.final) do g.ys[i] = lerp(avg, y, b) end
    g.bent = b
    place_girders(g, gi)
end
-- one ladder piece: rails from ybot up to ytop (pixels, y grows downwards) plus rungs at a fixed 4 px pitch.
-- Fixed pieces put their rungs on the world 4 px grid, so every ladder has the same spacing at the same heights;
-- a moving piece (retractable top) carries its rungs with it, measured from its own top.
local RUNG_PITCH = 4
local function lad_seg(node, x, ybot, ytop, z, pool, moving)
    node:set_position(vec3(WX(x), WY(ybot), z)); node:set_scale(vec3(1, max(0.01, (ybot - ytop) / 8), 1))
    local y = moving and (ytop + RUNG_PITCH / 2) or (floor(ytop / RUNG_PITCH) + 1) * RUNG_PITCH
    while y < ybot - 1 do
        if y > ytop + 1 then local r = P_get(pool, "rung"); r:set_position(vec3(WX(x), WY(y), z)) end
        y = y + RUNG_PITCH
    end
end
G.lad_seg = lad_seg
function G.refresh_ladders()
    P_begin("rung")
    for _, l in ipairs(ST.ladders) do
        l.ylo = surf(ST.girders[l.lo], l.x); l.yhi = surf(ST.girders[l.hi], l.x)
        local len = l.ylo - l.yhi
        local a, b = l.nodes[1], l.nodes[2]
        if l.hidden then a:set_position(HIDE); if b then b:set_position(HIDE) end
        elseif l.broken then
            lad_seg(a, l.x, l.ylo, l.ylo - len * 0.3, -0.3, "rung")
            lad_seg(b, l.x, l.yhi + len * 0.3, l.yhi, -0.3, "rung")
        elseif l.retract then
            local k = l.rk or 0
            lad_seg(a, l.x, l.ylo, l.ylo - len * 0.36, -0.3, "rung")
            local top = lerp(l.yhi, l.ylo - len * 0.36, k)
            lad_seg(b, l.x, top + len * 0.5, top, -0.32, "rung", true)
        else
            lad_seg(a, l.x, l.ylo, l.yhi, -0.3, "rung")
        end
    end
    if ST.deco_ladders then for _, d in ipairs(ST.deco_ladders) do
        if d.hidden then d.node:set_position(HIDE) else lad_seg(d.node, d.x, d.y0, d.y1, -0.3, "rung") end
    end end
    P_end("rung")
end
