------------------------------------------------------------------ gameplay simulation (60 Hz, original pixel units)
local FR = 1 / 60
local WALK, CLIMB, JUMP_V, GRAV = 0.75, 0.62, 1.65, 0.097
G.SPEEDS = { walk = WALK, climb = CLIMB, jump_v = JUMP_V, grav = GRAV }
local M = { st = "hidden", x = 0, y = 0, ox = 0, oy = 0, face = 1, ph = 0, ham = 0, hph = 0 }
G.M = M
local B, F, PIES, SPR = {}, {}, {}, {}
G.B, G.F, G.PIES, G.SPR = B, F, PIES, SPR
local KONG = { x = 44, y = 84, ox = 44, oy = 84, st = "idle", t = 0, dir = 1, throws = 0 }
G.KONG = KONG
local PAUL = { x = 112, y = 56, t = 0, help = 0 }
G.PAUL = PAUL
local HB = { mario = { 4, 13, 1 }, barrel = 5, fire = { 5, 11 }, pie = { 6, 7 }, spring = { 6, 12 }, kong = { 13, 30 } }
G.HB = HB
local function overlap(ax0, ay0, ax1, ay1, bx0, by0, bx1, by1) return ax0 < bx1 and bx0 < ax1 and ay0 < by1 and by0 < ay1 end
local function mario_box() return M.x - HB.mario[1], M.y - HB.mario[2], M.x + HB.mario[1], M.y - HB.mario[3] end
local function ent_box(e)
    if e.kind == "barrel" then return e.x - HB.barrel, e.y - HB.barrel * 2, e.x + HB.barrel, e.y end
    if e.kind == "pie" then return e.x - HB.pie[1], e.y - HB.pie[2], e.x + HB.pie[1], e.y end
    if e.kind == "spring" then return e.x - HB.spring[1], e.y - HB.spring[2], e.x + HB.spring[1], e.y end
    return e.x - HB.fire[1], e.y - HB.fire[2], e.x + HB.fire[1], e.y - 1
end
G.mario_box, G.ent_box = mario_box, ent_box
local function diff() return min(5, G.level + floor((G.stage_f or 0) / (60 * 45))) end
local function on_conv(g) local gg = type(g) == "number" and ST.girders[g]; return gg and gg.conv and (gg.cs or 0) or 0 end

------------------------------------------------------------------ Mario
local function mario_die(cause)
    if M.st == "dead" or G.god then return end
    M.st = "dead"; M.dead_f = 0; M.cause = cause
    music(nil); sfx("death")
    flash(M.x, M.y - 8, { 1, .4, .3 }, 30, 0.5, 6)
end
G.mario_die = mario_die
local function land_on(x, y0, y1, who)
    local best, by = nil, 1e9
    for i, g in ipairs(ST.girders) do
        if covers(g, x, who) then
            local s = surf(g, x)
            if s >= y0 - 0.5 and s <= y1 + 0.5 and s < by then best, by = i, s end
        end
    end
    if ST.plats and who == "mario" then
        for _, p in ipairs(ST.plats) do
            if p.live and x >= p.x - 8.5 and x < p.x + 8.5 and p.y >= y0 - 2.5 and p.y <= y1 + 0.5 and p.y < by then best, by = p, p.y end
        end
    end
    return best, by
end
local function award_jump()
    local n = 0; for _ in pairs(M.jumped or {}) do n = n + 1 end
    if n > 0 then add_score(n == 1 and 100 or (n == 2 and 300 or 800), M.x, M.y - 18); sfx("item") end
    M.jumped = {}
end
local function mario_reset(def)
    M.st = "walk"; M.x = def.x; M.g = def.g; M.y = surf(ST.girders[def.g], def.x); M.ox, M.oy = M.x, M.y
    M.face = 1; M.ph = 0; M.ham = 0; M.vx, M.vy = 0, 0; M.jumped = {}; M.ladder = nil; M.walk_snd = 0
end
G.mario_reset = mario_reset
local function rivet_check(px)
    if ST.kind ~= "100" then return end
    for _, r in ipairs(ST.rivets) do
        local h = r.h
        if not h.open then
            local crossed = (px - h.x) * (M.x - h.x) <= 0 and abs(px - M.x) < 3
            local above = M.y <= r.y + 0.5 and r.y - M.y < 26
            if crossed and above and M.st ~= "climb" then
                h.open = true; h.grace = true; r.fly = 0
                add_score(100, h.x, r.y - 14); sfx("rivet"); sparks(h.x, r.y, { 1, .8, .25 }, 20)
                ST.rivets_left = ST.rivets_left - 1
            end
        end
        if h.grace and (abs(M.x - h.x) > 5 or M.st == "jump") then h.grace = (M.st == "jump") and abs(M.x - h.x) <= 5 or false end
    end
end
local function mario_step(inp)
    M.ox, M.oy = M.x, M.y
    local px = M.x
    if M.st == "walk" then
        local ham = M.ham > 0
        local l_up = (inp.v < 0 and not ham) and ladder_bottom(M.x, M.y, 3)
        if l_up and ladder_limit(l_up) >= M.y - 1 then l_up = nil end
        local l_dn = (inp.v > 0 and not ham) and ladder_top(M.x, M.y, 3)
        if l_dn and (l_dn.broken or (l_dn.retract and (l_dn.rk or 0) > 0.02) or ST.girders[l_dn.lo] == nil) then l_dn = nil end
        if l_up then M.st = "climb"; M.ladder = l_up; M.x = l_up.x
        elseif l_dn then M.st = "climb"; M.ladder = l_dn; M.x = l_dn.x; M.y = M.y + 0.05
        elseif inp.jump and not ham then
            M.st = "jump"; M.vy = -JUMP_V; M.vx = inp.h * WALK; M.ty = M.y; M.jumped = {}; sfx("jump")
            if inp.h ~= 0 then M.face = inp.h end
        else
            local dx = inp.h * WALK + on_conv(M.g)
            if inp.h ~= 0 then M.face = inp.h end
            M.x = clamp(M.x + dx, 5, 219)
            if ST.drum and M.x < ST.drum.x + 13 and M.y > 230 then M.x = ST.drum.x + 13 end
            if type(M.g) == "table" then M.y = M.g.y end
            local g, s = floor_near(M.x, M.y, 3, 3, "mario")
            if g then M.g = g; M.y = s
            else M.st = "fall"; M.vy = 0; M.vx = 0; M.ty = M.y end
            if inp.h ~= 0 then
                M.ph = M.ph + 0.2
                M.walk_snd = (M.walk_snd or 0) - 1
                if M.walk_snd <= 0 then sfx("walk"); M.walk_snd = 9 end
            else M.walk_snd = 0 end
        end
    elseif M.st == "climb" then
        local l = M.ladder
        local lim = ladder_limit(l)
        if inp.v < 0 then M.y = max(lim, M.y - CLIMB); M.ph = M.ph + 0.15
        elseif inp.v > 0 then M.y = M.y + CLIMB; M.ph = M.ph + 0.15 end
        if M.y < lim then M.y = lim end
        if M.y <= l.yhi + 0.001 and lim <= l.yhi + 0.001 then M.st = "walk"; M.g = l.hi; M.y = l.yhi
        elseif M.y >= l.ylo then M.st = "walk"; M.g = l.lo; M.y = l.ylo end
        if M.st == "climb" and (inp.v ~= 0) then
            M.walk_snd = (M.walk_snd or 0) - 1
            if M.walk_snd <= 0 then sfx("walk"); M.walk_snd = 14 end
        end
    elseif M.st == "jump" or M.st == "fall" then
        M.vy = min(M.vy + GRAV, 3.2)
        M.x = M.x + M.vx
        if M.x < 5 or M.x > 219 then M.vx = -M.vx; M.x = clamp(M.x, 5, 219) end
        local y0 = M.y
        M.y = M.y + M.vy
        if M.st == "jump" then
            for _, list in ipairs({ B, F, PIES, SPR }) do
                for _, e in ipairs(list) do
                    if abs(e.x - M.x) < 8 and e.y > M.y + 1 and e.y - M.y < 28 and not M.jumped[e] then M.jumped[e] = true end
                end
            end
        end
        if M.vy > 0 then
            local g, s = land_on(M.x, y0, M.y, "mario")
            if g then
                M.y = s; M.g = g
                if s - M.ty > 12 then mario_die("fall"); M.y = s
                else M.st = "walk"; if next(M.jumped or {}) then award_jump() end end
            end
        end
        if M.y > 262 then mario_die("pit") end
    end
    -- carried by elevator / crushed by the motor
    if M.st == "walk" and type(M.g) == "table" then
        M.y = M.g.y
        if M.g.dir < 0 and M.g.y < 104 then mario_die("crush") end
        if not M.g.live then M.st = "fall"; M.vy = 0; M.vx = 0; M.ty = M.y end
    end
    if M.st ~= "dead" then rivet_check(px) end
    -- hammer pickup + timer
    if M.st ~= "dead" then
        if M.ham <= 0 then
            local x0, y0, x1, y1 = mario_box()
            for _, h in ipairs(ST.hammer_props) do
                if h.live and overlap(x0, y0 - 3, x1, y1, h.x - 5, h.y - 6, h.x + 5, h.y + 6) then
                    h.live = false; M.ham = 60 * 10; M.hph = 0; music("hammer"); sfx("item")
                    if M.st == "climb" then M.st = "walk" end
                end
            end
        else
            M.ham = M.ham - 1; M.hph = M.hph + 1
            if M.ham <= 0 then music(ST.music) end
        end
    end
end
local function hammer_box()
    if M.ham <= 0 or M.st == "dead" then return nil end
    if floor(M.hph / 9) % 2 == 0 then return M.x - 7, M.y - 32, M.x + 7, M.y - 14 end
    local a = M.x + M.face * 3; local b = M.x + M.face * 17
    return min(a, b), M.y - 13, max(a, b), M.y + 1
end
G.hammer_box = hammer_box

------------------------------------------------------------------ barrels
local function free_ent(list, i) local e = list[i]; rig_free(e.rig); table.remove(list, i) end
local function spawn_fire(x, y, kind)
    local cap = ST.kind == "75" and 2 or 5
    if #F >= cap then return end
    local pool = kind == "fox" and RIGS.fox or RIGS.fire
    local r = rig_take(pool); if not r then return end
    F[#F + 1] = { kind = kind or "fire", x = x, y = y, ox = x, oy = y, st = "spawn", vx = 0.55, vy = -1.5, dir = 1, g = nil, t = 30, rig = r, ph = rand() * 6 }
end
G.spawn_fire = spawn_fire
local function ignite(x, y)
    if not ST.lit then ST.lit = true end
    sfx("ignite"); flash(x, y - 18, { 1, .55, .2 }, 70, 0.6, 9)
    sparks(x, y - 16, { 1, .5, .15 }, 30, 18)
end
local function barrel_spawn(mode, blue)
    local r = rig_take(blue and RIGS.bbarrel or RIGS.barrel); if not r then return end
    local b = { kind = "barrel", x = KONG.x + 14, y = 84, st = "roll", dir = 1, g = 6, vx = 0, vy = 0, blue = blue, rig = r, spin = 0, bnc = 0 }
    if mode == "drop" then b.st = "drop"; b.x = 28; b.y = 70; b.vy = 0; b.skip = {}
    elseif mode == "wild" then b.st = "wild"; b.x = KONG.x + 10; b.y = 74; b.vx = (M.x > b.x) and 0.7 or 0.35; b.vy = 0; b.skip = {} end
    b.ox, b.oy = b.x, b.y
    B[#B + 1] = b
    return b
end
G.barrel_spawn = barrel_spawn
local function barrel_ladder_choice(b, l)
    if l.hi == 7 then return false end
    local p = 0.18 + 0.06 * diff()
    if M.y > b.y + 8 then p = p + 0.15; if abs(M.x - l.x) < 40 then p = p + 0.25 end end
    if M.ham > 0 then p = p * 0.5 end
    return rand() < p
end
local function enter_drum(b)
    if b.blue or b.first then ignite(ST.drum.x, ST.drum.y); spawn_fire(ST.drum.x, ST.drum.y - 16, "fire") end
    sparks(ST.drum.x, ST.drum.y - 15, { 1, .6, .2 }, 10, 10)
end
local function barrel_step(b, i)
    b.ox, b.oy = b.x, b.y
    local sp = 1.0 + 0.04 * diff()
    if b.st == "roll" then
        local g = ST.girders[b.g]
        local nx = b.x + b.dir * sp
        for _, l in ipairs(ST.ladders) do
            if l.hi == b.g and (b.x - l.x) * (nx - l.x) <= 0 and b.lastl ~= l then
                b.lastl = l
                if barrel_ladder_choice(b, l) then b.st = "ladder"; b.ladder = l; b.x = l.x; return end
            end
        end
        b.x = nx; b.spin = b.spin - b.dir * sp / 5 * 57.3
        if covers(g, b.x) then b.y = surf(g, b.x)
        else b.st = "fall"; b.vx = b.dir * 0.55; b.vy = 0.3; b.bnc = 0; b.from = b.g end
        if ST.drum and b.g == 1 and b.x <= ST.drum.x + 9 then enter_drum(b); free_ent(B, i); return end
    elseif b.st == "ladder" then
        b.y = b.y + sp * 0.9
        if b.y >= b.ladder.ylo then b.st = "roll"; b.g = b.ladder.lo; b.y = b.ladder.ylo; b.dir = ST.girders[b.g].dir; b.lastl = b.ladder end
    elseif b.st == "fall" then
        b.vy = min(b.vy + 0.12, 3); b.x = b.x + b.vx
        local y0 = b.y; b.y = b.y + b.vy
        if b.vy > 0 then
            local g, s = land_on(b.x, y0, b.y, "barrel")
            if g and g ~= b.from then
                b.y = s
                if b.bnc == 0 then b.bnc = 1; b.vy = -0.9; b.vx = b.vx * 0.4; b.g2 = g; sfx("land")
                else b.st = "roll"; b.g = g; b.dir = ST.girders[g].dir end
            elseif g and b.bnc == 1 and g == b.from then b.st = "roll"; b.g = g; b.dir = ST.girders[g].dir end
        end
        if b.x < -10 or b.x > 234 or b.y > 262 then free_ent(B, i); return end
    elseif b.st == "wild" or b.st == "drop" then
        b.vy = min(b.vy + 0.1, 2.6); b.x = b.x + b.vx
        local y0 = b.y; b.y = b.y + b.vy
        b.spin = b.spin + 6
        if b.vy > 0 then
            for gi, g in ipairs(ST.girders) do
                if not b.skip[gi] and covers(g, b.x) then
                    local s = surf(g, b.x)
                    if s >= y0 and s <= b.y then
                        b.skip[gi] = true
                        if gi == 1 then
                            if b.st == "drop" then b.y = s; enter_drum(b); free_ent(B, i); return end
                            b.st = "roll"; b.g = 1; b.y = s; b.dir = (b.x < 112) and -1 or 1; return
                        end
                        b.y = s; b.vy = -1.1; sfx("land"); dust(b.x, s, 6)
                        if b.st == "wild" then b.vx = clamp((M.x - b.x) / 60, -0.9, 0.9) end
                        break
                    end
                end
            end
        end
        if b.st == "drop" and b.y >= ST.drum.y - 15 and abs(b.x - ST.drum.x) < 10 then enter_drum(b); free_ent(B, i); return end
        if b.x < -10 or b.x > 234 or b.y > 262 then free_ent(B, i); return end
    end
end

------------------------------------------------------------------ fireballs / firefoxes
local function fire_step(f, i)
    f.ox, f.oy = f.x, f.y
    f.ph = f.ph + 0.15
    local sp = (f.kind == "fox" and 0.5 or 0.42) + 0.03 * diff()
    if f.st == "spawn" then
        f.vy = f.vy + 0.08; f.x = f.x + f.vx; local y0 = f.y; f.y = f.y + f.vy
        if f.vy > 0 then
            local g, s = land_on(f.x, y0, f.y, "fire")
            if g then f.st = "walk"; f.g = g; f.y = s; f.dir = 1 end
        end
        if f.y > 262 then free_ent(F, i) end
        return
    end
    if f.st == "walk" then
        f.t = f.t - 1
        local flee = M.ham > 0
        if f.t <= 0 then
            f.t = floor(rr(40, 120))
            local tow = (M.x > f.x) and 1 or -1
            if flee then f.dir = -tow elseif rand() < 0.55 then f.dir = tow elseif rand() < 0.5 then f.dir = -f.dir end
        end
        local g = ST.girders[f.g]
        local nx = f.x + f.dir * sp * (flee and 0.7 or 1)
        -- ladders: climb toward Mario now and then
        for _, l in ipairs(ST.ladders) do
            if not l.broken and not (l.retract and (l.rk or 0) > 0.02) and l.hi ~= #ST.girders and not ST.girders[l.hi].top and (f.x - l.x) * (nx - l.x) <= 0 then
                local want_up = M.y < f.y - 10
                if l.lo == f.g and rand() < (want_up and 0.45 or 0.12) then f.st = "climb"; f.ladder = l; f.x = l.x; f.cdir = -1; return end
                if l.hi == f.g and rand() < ((not want_up and M.y > f.y + 10) and 0.45 or 0.1) then f.st = "climb"; f.ladder = l; f.x = l.x; f.cdir = 1; return end
            end
        end
        if ST.drum and f.g == 1 and nx < ST.drum.x + 12 then f.dir = 1 end
        if not covers(g, nx + f.dir * 4) or nx < 6 or nx > 218 or (ST.fire and f.g ~= 4 and abs(nx - ST.fire.x) < 14 and abs(surf(g, nx) - ST.fire.y) < 2) then f.dir = -f.dir; nx = f.x end
        f.x = nx; f.y = surf(g, f.x)
    elseif f.st == "climb" then
        local l = f.ladder
        f.y = f.y + f.cdir * sp * 0.8
        if f.cdir < 0 and f.y <= l.yhi then f.st = "walk"; f.g = l.hi; f.y = l.yhi; f.t = 20 end
        if f.cdir > 0 and f.y >= l.ylo then f.st = "walk"; f.g = l.lo; f.y = l.ylo; f.t = 20 end
    end
end

------------------------------------------------------------------ cement pies (50m), springs (75m)
local function pie_spawn(gi)
    local g = ST.girders[gi]
    local d = g.conv * (g.flip or 1)
    local x = d > 0 and g.x0 + 4 or gx1(g) - 4
    for _, p in ipairs(PIES) do if p.g == gi and abs(p.x - x) < 26 then return end end
    local r = rig_take(RIGS.pie); if not r then return end
    PIES[#PIES + 1] = { kind = "pie", x = x, y = surf(g, x), ox = x, oy = surf(g, x), g = gi, st = "ride", rig = r, vy = 0 }
end
local function pie_step(p, i)
    p.ox, p.oy = p.x, p.y
    if p.st == "ride" then
        local g = ST.girders[p.g]
        p.x = p.x + (g.cs or 0)
        if not covers(g, p.x) then
            local fg, s = floor_near(p.x, p.y, 1, 1, "pie")
            if fg and ST.girders[fg] and ST.girders[fg].conv then p.g = fg
            else p.st = "fall"; p.vy = 0 end
        end
        if ST.fire and abs(p.x - ST.fire.x) < 9 and abs(p.y - ST.fire.y) < 2 then
            sparks(p.x, p.y - 8, { 1, .5, .2 }, 16); free_ent(PIES, i); return
        end
    else
        p.vy = p.vy + 0.15; p.y = p.y + p.vy
        if p.y > 262 then free_ent(PIES, i); return end
    end
end
local function spring_step(s, i)
    s.ox, s.oy = s.x, s.y
    s.sq = max(0, (s.sq or 0) - 0.08)
    s.vy = s.vy + 0.11
    local y0 = s.y
    s.x = s.x + s.vx; s.y = s.y + s.vy
    if s.st == "hop" then
        if s.x >= 184 then s.st = "drop"; s.vx = 0; sfx("spring") end
        if s.vy > 0 and s.y >= 84 and y0 <= 84 then s.y = 84; s.vy = -1.75; s.sq = 1; sfx("spring") end
    end
    if s.y > 266 then free_ent(SPR, i) end
end

------------------------------------------------------------------ Kong + world behaviour per stage
local function kong_step()
    KONG.ox, KONG.oy = KONG.x, KONG.y
    KONG.t = KONG.t - 1
    local k = ST.kind
    if k == "25" then
        if KONG.st == "idle" and KONG.t <= 0 then
            if KONG.throws > 0 and KONG.throws % 5 == 4 and rand() < 0.6 then KONG.st = "beat"; KONG.t = 70; sfx("beat")
            else KONG.st = "grab"; KONG.t = 28 end
        elseif KONG.st == "beat" and KONG.t <= 0 then KONG.st = "idle"; KONG.t = 20; KONG.throws = KONG.throws + 1
        elseif KONG.st == "grab" and KONG.t <= 0 then KONG.st = "hold"; KONG.t = 16
        elseif KONG.st == "hold" and KONG.t <= 0 then
            KONG.st = "throw"; KONG.t = 18; KONG.throws = KONG.throws + 1
            local first = not G.first_done
            if first then
                G.first_done = true
                local b = barrel_spawn("drop", true); if b then b.first = true end
            else
                local d = diff()
                local wild = d >= 2 and rand() < 0.08 + 0.04 * d
                barrel_spawn(wild and "wild" or "roll", rand() < 0.1 + 0.03 * d)
            end
            sfx("throw")
        elseif KONG.st == "throw" and KONG.t <= 0 then
            KONG.st = "idle"; KONG.t = floor(rr(50, 150) * (1.15 - 0.12 * diff()))
        end
    elseif k == "75" then
        if KONG.st == "idle" and KONG.t <= 0 then KONG.st = "grab"; KONG.t = 24
        elseif KONG.st == "grab" and KONG.t <= 0 then
            KONG.st = "throw"; KONG.t = 16
            local r = rig_take(RIGS.spring)
            if r then SPR[#SPR + 1] = { kind = "spring", x = 52, y = 84, ox = 52, oy = 84, vx = 1.05 + rr(0, 0.25), vy = -1.5, st = "hop", rig = r } end
            sfx("throw")
        elseif KONG.st == "throw" and KONG.t <= 0 then
            KONG.st = (rand() < 0.2) and "beat" or "idle"; KONG.t = KONG.st == "beat" and 70 or floor(rr(70, 160) * (1.1 - 0.1 * diff()))
            if KONG.st == "beat" then sfx("beat") end
        elseif KONG.st == "beat" and KONG.t <= 0 then KONG.st = "idle"; KONG.t = 30 end
    else
        local p = ST.dk.patrol
        if KONG.st == "beat" then
            if KONG.t <= 0 then KONG.st = "walk"; KONG.t = floor(rr(150, 320)) end
        else
            KONG.st = "walk"
            KONG.x = KONG.x + KONG.dir * 0.35
            if KONG.x < p[1] then KONG.x = p[1]; KONG.dir = 1 end
            if KONG.x > p[2] then KONG.x = p[2]; KONG.dir = -1 end
            if rand() < 0.004 then KONG.dir = -KONG.dir end
            if KONG.t <= 0 then KONG.st = "beat"; KONG.t = 80; sfx("beat") end
        end
    end
end
local function world_step()
    local d = diff()
    -- conveyors
    for gi, g in ipairs(ST.girders) do
        if g.conv then
            if g.swap then
                g.sw_t = (g.sw_t or floor(rr(300, 540))) - 1
                if g.sw_t <= 0 then g.flip = -(g.flip or 1); g.sw_t = floor(rr(300, 540)) end
            end
            g.cs = g.conv * (g.flip or 1) * 0.5
            g.phase = (g.phase or 0) + g.cs
        end
    end
    -- retractable ladders (50m)
    for _, l in ipairs(ST.ladders) do
        if l.retract then
            l.rt = (l.rt or floor(rr(60, 240))) - 1
            if l.rt <= 0 then l.up = not l.up; l.rt = floor(l.up and rr(120, 200) or rr(150, 260)) end
            local tgt = l.up and 1 or 0
            l.rk = clamp((l.rk or 0) + (tgt > (l.rk or 0) and 0.02 or -0.02), 0, 1)
            if abs(l.rk - tgt) < 0.02 then l.rk = tgt end
        end
    end
    if ST.kind == "50" then
        G.pie_t = (G.pie_t or 60) - 1
        if G.pie_t <= 0 then
            G.pie_t = floor(rr(80, 170) * (1.15 - 0.1 * d))
            local opts = { 2, 3, 5 }
            if #PIES < 7 then pie_spawn(opts[floor(rr(1, 3.999))]) end
        end
        G.fox_t = (G.fox_t or 240) - 1
        if G.fox_t <= 0 then G.fox_t = floor(rr(360, 600) * (1.1 - 0.1 * d)); spawn_fire(ST.fire.x, ST.fire.y - 16, "fox") end
    elseif ST.kind == "100" then
        G.fox_t = (G.fox_t or 120) - 1
        if G.fox_t <= 0 then
            G.fox_t = floor(rr(420, 700) * (1.1 - 0.1 * d))
            local side = rand() < 0.5 and 20 or 204
            local gi = floor(rr(1, 3.999))
            local r = #F < 5 and rig_take(RIGS.fox)
            if r then local g = ST.girders[gi]; F[#F + 1] = { kind = "fox", x = side, y = surf(g, side), ox = side, oy = surf(g, side), st = "walk", g = gi, dir = side < 112 and 1 or -1, t = 40, rig = r, ph = 0, pop = 1 } end
        end
    elseif ST.kind == "75" then
        for _, p in ipairs(ST.plats) do
            p.oy = p.y
            p.ph = (p.ph + 0.5 / 152) % 1
            p.y = (p.dir < 0) and (248 - p.ph * 152) or (96 + p.ph * 152)
            p.live = p.y < 247 and p.y > 97
        end
        if #F < 2 and (G.stage_f or 0) % 240 == 120 then
            local spots = { { 5, 200 }, { 6, 180 } }
            local s = spots[#F + 1]
            local r = rig_take(RIGS.fire)
            if r then local g = ST.girders[s[1]]; F[#F + 1] = { kind = "fire", x = s[2], y = surf(g, s[2]), ox = s[2], oy = surf(g, s[2]), st = "walk", g = s[1], dir = -1, t = 40, rig = r, ph = 0, pop = 1 } end
        end
    end
end

------------------------------------------------------------------ collisions + scoring
local function smash(e, list, i, pts)
    add_score(pts, e.x, e.y - 14); sfx("smash")
    sparks(e.x, e.y - 6, { 1, .85, .5 }, 30, 26); flash(e.x, e.y - 6, { 1, .9, .7 }, 50, 0.3, 6)
    G.smash_fx = { x = e.x, y = e.y - 6, t = 0 }
    free_ent(list, i)
end
local function collide()
    if M.st == "dead" or M.st == "hidden" then return end
    local x0, y0, x1, y1 = mario_box()
    local hx0, hy0, hx1, hy1 = hammer_box()
    local function test(list, pts_fn)
        for i = #list, 1, -1 do
            local e = list[i]
            if e and e.st ~= "spawn" then
                local a, b, c, d = ent_box(e)
                if hx0 and pts_fn and overlap(hx0, hy0, hx1, hy1, a, b, c, d) then smash(e, list, i, pts_fn(e))
                elseif overlap(x0, y0, x1, y1, a, b, c, d) then mario_die(e.kind); return end
            end
        end
    end
    local function rnd_pts() local r = rand(); return r < 0.6 and 300 or (r < 0.9 and 500 or 800) end
    test(B, rnd_pts)
    test(F, function() return 500 end)
    test(PIES, function() return 500 end)
    test(SPR, nil)
    -- Kong
    local kh = HB.kong
    if overlap(x0, y0, x1, y1, KONG.x - kh[1], KONG.y - kh[2], KONG.x + kh[1], KONG.y) then mario_die("kong") end
    -- oil fire on the 50m stand
    if ST.fire and overlap(x0, y0, x1, y1, ST.fire.x - 8, ST.fire.y - 22, ST.fire.x + 8, ST.fire.y) then mario_die("fire") end
    -- items
    for _, it in ipairs(ST.items) do
        if it.live and overlap(x0, y0, x1, y1, it.x - 6, it.y - 10, it.x + 6, it.y) then
            it.live = false; add_score(G.level == 1 and 300 or (G.level == 2 and 500 or 800), it.x, it.y - 14); sfx("item")
            sparks(it.x, it.y - 6, { 1, .6, .8 }, 20)
        end
    end
end
local function stage_step(inp)
    G.stage_f = (G.stage_f or 0) + 1
    world_step()
    if M.st ~= "dead" then
        mario_step(inp)
        kong_step()
        for i = #B, 1, -1 do if B[i] then barrel_step(B[i], i) end end
        for i = #F, 1, -1 do if F[i] then fire_step(F[i], i) end end
        for i = #PIES, 1, -1 do if PIES[i] then pie_step(PIES[i], i) end end
        for i = #SPR, 1, -1 do if SPR[i] then spring_step(SPR[i], i) end end
        collide()
        -- bonus timer
        if G.attract then return end
        G.bonus_f = (G.bonus_f or 0) + 1
        if G.bonus_f >= 120 then
            G.bonus_f = 0; G.bonus = max(0, G.bonus - 100)
            if G.bonus <= 1000 and G.bonus > 0 then sfx("timeout") end
            if G.bonus <= 0 then mario_die("time") end
        end
    else
        M.dead_f = M.dead_f + 1
        M.ox, M.oy = M.x, M.y
    end
end
G.stage_step = stage_step
local function clear_ents()
    for _, list in ipairs({ B, F, PIES, SPR }) do for i = #list, 1, -1 do free_ent(list, i) end end
end
G.clear_ents = clear_ents
