-- Shadow Puppeteer rules (pure Lua: no engine calls; tests/rules_test.lua runs it under plain LuaJIT).
-- The puppet lives on the paper (screen coordinates u right, v up). Ground each step = the union of the fixed paper
-- pieces and every solid prop's shadow, projected from the SAME silhouettes and formula the view draws
-- (sp_data.lua, generated from tools/sp_common.py). Ladder shadows are climbable, not solid. Thorns kill.
-- Fixed 120 Hz step: R.update() runs whole steps from a time accumulator, so results do not depend on frame rate.
local R = {}
local abs, max, min, floor = math.abs, math.max, math.min, math.floor
local EPS = 1e-6

------------------------------------------------------------------ level
-- level = { D = sp_data, solids = {poly}, thorns = {poly}, props = {name = {y, kind, sil = {poly}}}, door, star,
--           u0, u1, rules } ; poly = flat array { x1, y1, x2, y2, ... } with a bounding box.
local function mkpoly(pts)
    local p = { n = #pts }
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for i, q in ipairs(pts) do
        p[2 * i - 1], p[2 * i] = q[1], q[2]
        x0, x1, y0, y1 = min(x0, q[1]), max(x1, q[1]), min(y0, q[2]), max(y1, q[2])
    end
    p.x0, p.y0, p.x1, p.y1 = x0, y0, x1, y1
    return p
end
R.mkpoly = mkpoly

-- A level from sp_data.LEVELS by id (the props present, each with its level settings), as R.level's overrides.
function R.level_def(D, id)
    local lv
    for _, l in ipairs(D.LEVELS) do if l.id == id then lv = l end end
    assert(lv, "no level " .. tostring(id))
    local props, kinds, start = {}, {}, { puppet = lv.start.puppet, dir = lv.start.dir, lantern = lv.start.lantern }
    for name, cfg in pairs(lv.props) do
        props[name] = D.PROPS[name]
        kinds[name] = D.PROP_KIND[name]
        local mv = D.PROP_MOVE[name]
        if mv == "x" then start[name] = cfg.x
        elseif mv == "z" then start[name] = cfg.z end
    end
    return { solids = lv.solids, thorns = lv.thorns, props = props, kinds = kinds, cfg = lv.props, door = lv.door,
        star = lv.bonus, start = start, candle_s = lv.candle, quick_s = lv.quick, id = lv.id, map = lv.map }
end

function R.level(D, over)
    if over == nil then over = R.level_def(D, "1-3") end      -- the reference level (target.png's)
    if type(over) == "string" then over = R.level_def(D, over) end
    local L = { D = D, rules = over.rules or D.RULES, props = {}, solids = {}, thorns = {}, id = over.id, map = over.map }
    for _, k in ipairs({ "left_cliff", "right_cliff", "ledge" }) do
        if not (over.solids) then L.solids[#L.solids + 1] = mkpoly(D.LEVEL.solids[k]) end
    end
    for _, pts in ipairs(over.solids or {}) do L.solids[#L.solids + 1] = mkpoly(pts) end
    if over.thorns then
        for _, pts in ipairs(over.thorns) do L.thorns[#L.thorns + 1] = mkpoly(pts) end
    else
        L.thorns[1] = mkpoly(D.LEVEL.thorns)
    end
    for name, p in pairs(over.props or D.PROPS) do
        local cfg = over.cfg and over.cfg[name] or {}
        L.props[name] = { y = p.y, kind = (over.kinds or D.PROP_KIND)[name] or "solid", sil = p.silhouette, track = p.x,
            sil_l = p.silhouette_l, ztrack = p.z, move = (over.moves or D.PROP_MOVE or {})[name] or "x",
            auto = cfg.speed and cfg or nil, ax = cfg.x }
    end
    L.candle_s = over.candle_s                                 -- nil: the rules' default
    L.quick_s = over.quick_s
    L.door = over.door or { D.LEVEL.door[1], D.LEVEL.door[2] }
    L.star = over.star == false and nil or (over.star or { D.LEVEL.bonus[1], D.LEVEL.bonus[2] })
    L.u0, L.u1 = D.SCREEN_U[1], D.SCREEN_U[2]
    L.SY, L.LZ = D.SY, D.LZ
    L.start = over.start or D.LEVEL.start
    return L
end

------------------------------------------------------------------ the shadows (the rule both the view and the tests use)
-- Screen polygons of a prop's shadow: every silhouette vertex (x, z) of the prop at anchor ax, lantern (lx, ly):
-- u = lx + k (ax + x - lx), v = LZ + k (z - LZ), k = (SY - ly) / (prop_y - ly).
function R.shadow_polys(L, name, ax, lx, ly, az, left)
    local p = L.props[name]
    local k = (L.SY - ly) / (p.y - ly)
    az = az or 0
    local out = {}
    for i, poly in ipairs(left and p.sil_l or p.sil) do
        local pts = {}
        for j, q in ipairs(poly) do pts[j] = { lx + k * (ax + q[1] - lx), L.LZ + k * (az + q[2] - L.LZ) } end
        out[i] = pts
    end
    return out
end

-- A self-moving prop's place at sim time t: it runs x0 -> x1 -> x0 at `speed`, starting `phase` (0..1) along the
-- loop; dir -1 while running back (its mirrored silhouette).
function R.auto_x(a, t)
    local len = a.x1 - a.x0
    local s = (t * a.speed + (a.phase or 0) * 2 * len) % (2 * len)
    if s < len then return a.x0 + s, 1 end
    return a.x1 - (s - len), -1
end

-- Where each present prop is (anchor x, height z, facing) for an input and a sim time (the view draws the same).
function R.prop_place(L, name, inp, t)
    local p = L.props[name]
    if p.move == "auto" and p.auto then
        local x, d = R.auto_x(p.auto, t or 0)
        return x, 0, d < 0
    elseif p.move == "z" then
        return p.ax or 0, inp[name] or 0, false
    end
    return inp[name], 0, false
end

-- inp = { lantern = { lx, ly }, cup = x, comb = x, ladder = x, balloon = z }, sim time t (self-moving props)
--   ->  ground = { solids = {poly}, ladders = {box} }
function R.ground(L, inp, t)
    local G = { solids = {}, ladders = {} }
    for i, s in ipairs(L.solids) do G.solids[i] = s end
    local lx, ly = inp.lantern[1], inp.lantern[2]
    local names = {}
    for name in pairs(L.props) do names[#names + 1] = name end
    table.sort(names)                                         -- deterministic order
    for _, name in ipairs(names) do
        local ax, az, left = R.prop_place(L, name, inp, t)
        if ax then
            local polys = R.shadow_polys(L, name, ax, lx, ly, az, left)
            if L.props[name].kind == "ladder" then
                local b = { x0 = math.huge, x1 = -math.huge, y0 = math.huge, y1 = -math.huge }
                for _, pts in ipairs(polys) do
                    for _, q in ipairs(pts) do
                        b.x0, b.x1, b.y0, b.y1 = min(b.x0, q[1]), max(b.x1, q[1]), min(b.y0, q[2]), max(b.y1, q[2])
                    end
                end
                G.ladders[#G.ladders + 1] = b
            else
                for _, pts in ipairs(polys) do G.solids[#G.solids + 1] = mkpoly(pts) end
            end
        end
    end
    return G
end

------------------------------------------------------------------ geometry queries
-- Inside-intervals of the polygons at column x, merged: { a1, b1, a2, b2, ... } ascending.
local function column(polys, x)
    local iv = {}
    for _, p in ipairs(polys) do
        if x >= p.x0 and x <= p.x1 then
            local ys = {}
            local n = p.n
            for i = 1, n do
                local j = i % n + 1
                local ax, ay, bx, by = p[2 * i - 1], p[2 * i], p[2 * j - 1], p[2 * j]
                if (ax <= x) ~= (bx <= x) then ys[#ys + 1] = ay + (x - ax) * (by - ay) / (bx - ax) end
            end
            table.sort(ys)
            for i = 1, #ys - 1, 2 do iv[#iv + 1] = { ys[i], ys[i + 1] } end
        end
    end
    table.sort(iv, function(a, b) return a[1] < b[1] end)
    local out = {}
    for _, s in ipairs(iv) do
        local m = #out
        if m > 0 and s[1] <= out[m] + EPS then
            if s[2] > out[m] then out[m] = s[2] end
        else
            out[m + 1], out[m + 2] = s[1], s[2]
        end
    end
    return out
end
R.column = column

local function cols(L, x)
    local hw = L.rules.puppet_w / 2
    return { x - hw, x, x + hw }
end
-- the columns that can hold the puppet up: under its feet, not its outer edge
local function feet(L, x)
    local hf = L.rules.feet_w / 2
    return { x - hf, x, x + hf }
end

-- Does solid ground overlap the vertical span (y0, y1) at the puppet's core columns at x (or at the given columns)?
local function blocked(L, G, x, y0, y1, columns)
    for _, c in ipairs(columns or feet(L, x)) do
        local iv = column(G.solids, c)
        for i = 1, #iv, 2 do
            if iv[i] < y1 - EPS and iv[i + 1] > y0 + EPS then return true end
        end
    end
    return false
end

-- The highest ground top under the puppet's feet within [y - down, y + up] (the feet can stand on it), or nil.
-- A ladder's top rung is a step too: a puppet at the top of a ladder walks off along it.
local function support(L, G, x, y, up, down, columns)
    local best
    for _, c in ipairs(columns or feet(L, x)) do
        local iv = column(G.solids, c)
        for i = 2, #iv, 2 do
            local b = iv[i]
            if b <= y + up + EPS and b >= y - down - EPS and (not best or b > best) then best = b end
        end
        for _, l in ipairs(G.ladders) do
            local b = l.y1
            if c >= l.x0 and c <= l.x1 and b <= y + up + EPS and b >= y - down - EPS and (not best or b > best) then best = b end
        end
    end
    return best
end

local function free(L, G, x, y, columns)
    return not blocked(L, G, x, y, y + L.rules.puppet_h, columns)
end

-- Top of the SOLID ground (not a ladder's rung) at the single column c within [y - down, y + up], or nil.
local function top(L, G, c, y, up, down)
    local best
    local iv = column(G.solids, c)
    for i = 2, #iv, 2 do
        local t = iv[i]
        if t <= y + up + EPS and t >= y - down - EPS and (not best or t > best) then best = t end
    end
    return best
end
-- How far a steep face runs down ahead of the front heel (followed in 4 mm columns while steeper than max_slope).
local function face_height(L, G, x, y, dir)
    local tn, dx = math.tan(math.rad(L.rules.max_slope)), 0.004
    local py = top(L, G, x + dir * L.rules.feet_w / 2, y, EPS, L.rules.step) or y
    for k = 1, 80 do
        local t = top(L, G, x + dir * (L.rules.feet_w / 2 + k * dx), py, EPS, dx * 60)
        if not t or (py - t) < tn * dx then break end
        py = t
    end
    return y - py
end
-- Slope under the feet at x (positive = going down in direction dir): drop from the back heel to the front heel over
-- the feet's width; nil where either heel has no ground within a step.
local function slope(L, G, x, y, dir)
    local hf, st = L.rules.feet_w / 2, L.rules.step
    local yb, yf = top(L, G, x - dir * hf, y, st, st), top(L, G, x + dir * hf, y, st, st)
    if not (yb and yf) then return nil end
    return (yb - yf) / (2 * hf)
end
R.slope = function(L, S, inp) return slope(L, R.ground(L, inp, S.t), S.x, S.y, S.dir) end
-- While sliding the body lies back along the face: what can block it is ahead (centre and front heel), not behind.
local function slide_cols(L, S) return { S.x, S.x + S.dir * L.rules.feet_w / 2 } end

------------------------------------------------------------------ state
function R.new_state(L, start)
    start = start or L.start
    return { x = start.puppet[1], y = start.puppet[2], dir = start.dir or 1, mode = "walk", vy = 0, n = 0, t = 0,
        acc = 0, star = false, won = false, dead = nil, phase = 0, events = {} }
end

local function event(S, e) S.events[#S.events + 1] = { t = S.t, e = e } end
local function kill(S, why) S.dead = why; S.mode = "dead"; event(S, "dead:" .. why) end

-- Ground that moved into the puppet: lift it out from underneath, push it out from the side, or crush it.
local function resolve(L, G, S)
    local r = L.rules
    if S.mode == "slide" then
        if free(L, G, S.x, S.y, slide_cols(L, S)) then return end
        -- ground rising under a sliding puppet (a balloon lifted) carries it up, still sliding (switching to walk here
        -- flipped walk/slide every step while the balloon rose, 2026-11-13)
        local up = support(L, G, S.x, S.y, r.lift_max, 0, slide_cols(L, S))
        if up and up > S.y and free(L, G, S.x, up, slide_cols(L, S)) then S.y = up; return end
        S.mode = "walk"; S.slide_end_t = S.t                  -- ground moved into a sliding puppet: as if standing
    end
    if free(L, G, S.x, S.y) then return end
    -- lifted: ground rising under the feet, with room above its new top
    local lift = support(L, G, S.x, S.y, r.lift_max, 0)
    if lift and lift > S.y and free(L, G, S.x, lift) then
        S.y = lift
        if S.mode == "fall" then S.mode, S.vy = "walk", 0 end
        return
    end
    -- pushed: the nearest free spot sideways (toward the free side first), within push_max
    local hw = r.puppet_w / 2
    local lb = blocked(L, G, S.x - hw, S.y + r.step, S.y + r.puppet_h)
    local first = lb and 1 or -1
    for d = 0.004, r.push_max + EPS, 0.004 do
        for _, sgn in ipairs({ first, -first }) do
            local nx = S.x + sgn * d
            if nx - hw >= L.u0 and nx + hw <= L.u1 then
                if free(L, G, nx, S.y) then S.x = nx; return end
                local up = support(L, G, nx, S.y, r.step, 0)  -- pushed onto a low edge: step up onto it
                if up and up > S.y + EPS and free(L, G, nx, up) then S.x, S.y = nx, up; return end
            end
        end
    end
    kill(S, "crushed")
end

local function ladder_at(L, G, S)
    local hw = L.rules.puppet_w / 2
    for _, b in ipairs(G.ladders) do
        if S.x >= b.x0 + hw * 0.5 and S.x <= b.x1 - hw * 0.5 and b.y1 > S.y + EPS then return b end
    end
    return nil
end

-- One fixed step with the given input.
function R.step(L, S, inp)
    if S.dead or S.won then return end
    local r = L.rules
    local dt = r.dt
    S.n = S.n + 1
    S.t = S.n * dt
    if S.t >= (L.candle_s or r.candle_s) then kill(S, "candle"); return end
    local G = R.ground(L, inp, S.t)
    resolve(L, G, S)
    if S.dead then return end
    local h, hw = r.puppet_h, r.puppet_w / 2
    if S.mode == "climb" then
        local b = ladder_at(L, G, S)
        if not b then
            S.mode, S.vy = "fall", 0
        else
            local cx = (b.x0 + b.x1) / 2                          -- stay on the ladder's middle (it moves with the lantern)
            if abs(cx - S.x) > EPS then
                local nx = S.x + max(-r.walk * dt, min(r.walk * dt, cx - S.x))
                if free(L, G, nx, S.y) then S.x = nx end
            end
            local ny = min(S.y + r.climb * dt, b.y1)
            if not free(L, G, S.x, ny) then
                S.mode, S.vy = "fall", 0                          -- head against ground: let go
            else
                S.y = ny
                S.phase = S.phase + r.climb * dt / 0.06
                if S.y >= b.y1 - EPS then S.mode = "walk"; S.offladder = b.y1; event(S, "top") end
            end
        end
    elseif S.mode == "walk" then
        local b = (not S.offladder or S.y < S.offladder - r.step) and ladder_at(L, G, S) or nil
        local cx = b and (b.x0 + b.x1) / 2
        -- a ladder is climbed from its middle: walk on to it (or, already past it, start and drift there while climbing)
        if b and b.y1 > S.y + r.step and (abs(cx - S.x) <= r.walk * dt + EPS or (cx - S.x) * S.dir < 0) then
            if abs(cx - S.x) <= r.walk * dt + EPS and free(L, G, cx, S.y) then S.x = cx end
            S.mode = "climb"; event(S, "climb")
        else
            local nx = S.x + S.dir * r.walk * dt
            -- a rise ahead (centre to leading edge) is stepped onto; standing and walking down need ground under the feet
            -- (the feet's own columns too: over a rounded summit the peak can sit under a heel between the samples
            -- ahead, and the body test then met it as a wall: the puppet turned on the balloon's top, 2026-11-13)
            local hf = r.feet_w / 2
            local t = support(L, G, nx, S.y, r.step, 0, { nx - S.dir * hf, nx, nx + S.dir * hf, nx + S.dir * hw * 0.5, nx + S.dir * hw })
            -- a rise is a lip: within a step of the ground under the feet there (on a steep face the leading edge always
            -- found ground a few cm higher, and the puppet ratcheted up the face floating off it: solver, 2026-11-13)
            if t and t > S.y + EPS then
                local base = support(L, G, nx, t, 0, 2 * r.step)
                if not base or t - base > r.step + EPS then t = nil end
            end
            if not (t and t > S.y + EPS) then t = support(L, G, nx, S.y, 0, r.step) end
            local edge = nx - hw < L.u0 or nx + hw > L.u1
            local lead = { nx + S.dir * hw }                -- the body's leading edge meets walls first
            local ty = t or S.y
            if edge or not free(L, G, nx, ty) or blocked(L, G, nx, ty + r.step, ty + h, lead) then
                S.dir = -S.dir; event(S, "turn")                  -- wall taller than a step, or the paper's edge
            elseif t then
                S.x, S.y = nx, t
                S.phase = S.phase + r.walk * dt / 0.09
                -- too steep to stand on going down: slide, attached at the centre column
                local s = slope(L, G, S.x, S.y, S.dir)
                -- (a lip shorter than a step is stepped down, not slid: a chamfer, a rung's edge, 2026-11-13)
                local rearmed = S.t - (S.slide_end_t or -1e9) >= (r.slide_rearm or 0)
                local yc = rearmed and s and s > math.tan(math.rad(r.max_slope)) and face_height(L, G, S.x, S.y, S.dir) >= r.step
                    and top(L, G, S.x, S.y, EPS, r.step)
                if yc then S.y, S.mode, S.slope, S.slide_x0 = yc, "slide", math.deg(math.atan(s)), S.x; event(S, "slide") end
            else
                S.x = nx; S.mode, S.vy = "fall", 0; event(S, "fall")
            end
            if S.offladder and S.y < S.offladder - r.step then S.offladder = nil end
        end
    end
    if S.mode == "slide" then
        local tn = math.tan(math.rad(S.slope or r.max_slope))
        local nx = S.x + S.dir * r.slide * dt / math.sqrt(1 + tn * tn)
        local ny = nx - hw >= L.u0 and nx + hw <= L.u1 and top(L, G, nx, S.y, EPS, r.step) or nil
        if not ny then
            S.mode, S.vy = "fall", -r.slide * tn / math.sqrt(1 + tn * tn); S.slide_end_t = S.t; event(S, "fall")   -- the face ends: drop off it
        elseif not free(L, G, nx, ny, { nx, nx + S.dir * r.feet_w / 2 }) then
            S.mode = "walk"; S.slide_end_t = S.t              -- ground ahead: stand (the walk turns at a wall)
        else
            S.x, S.y = nx, ny
            S.phase = S.phase + r.slide * dt / 0.09
            local s = slope(L, G, S.x, S.y, S.dir)
            if s then S.slope = math.deg(math.atan(s)) end
            -- stand again once the ground behind the centre is gentle (no pop up the face behind the heels)
            -- (not before the back heel has left the lip it started from: it stood up again in the slide's first
            -- step there and slid again the next, a double start, 2026-11-13)
            local yb = top(L, G, S.x - S.dir * r.feet_w / 2, S.y, r.step, EPS)
            local off_lip = math.abs(S.x - (S.slide_x0 or S.x)) >= r.feet_w / 2
            if off_lip and (not yb or (yb - S.y) < (r.feet_w / 2) * math.tan(math.rad(r.slide_exit))) then
                S.mode = "walk"; S.slope = nil; S.slide_end_t = S.t; event(S, "stand")
            end
        end
    end
    if S.mode == "fall" then
        S.vy = max(S.vy - r.gravity * dt, -r.fall_max)
        local nx = S.x + S.dir * r.walk * dt
        if nx - hw < L.u0 or nx + hw > L.u1 or not free(L, G, nx, S.y) then nx = S.x end
        local ny = S.y + S.vy * dt
        local land = support(L, G, nx, S.y, 0, S.y - ny)       -- any top crossed on the way down (no tunnelling)
        S.x = nx
        if land then
            S.y, S.vy, S.mode = land, 0, "walk"; event(S, "land")
        else
            S.y = ny
        end
    end
    -- hazards and goals
    for _, c in ipairs(cols(L, S.x)) do
        local iv = column(L.thorns, c)
        for i = 1, #iv, 2 do
            if iv[i] < S.y + h and iv[i + 1] > S.y + EPS then kill(S, "thorns"); return end
        end
    end
    if S.y < r.fell_v then kill(S, "fell"); return end
    if L.star and not S.star then
        local dx, dy = S.x - L.star[1], S.y + h / 2 - L.star[2]
        if dx * dx + dy * dy < (r.star_r + hw) ^ 2 then S.star = true; event(S, "star") end
    end
    if S.mode == "walk" and abs(S.x - L.door[1]) < r.door_w and abs(S.y - L.door[2]) < r.door_dv then
        S.won = true; S.mode = "won"; event(S, "won")
    end
end

-- Real time in, whole fixed steps out. input(t) gives the lantern and props at sim time t (held for a live frame).
function R.update(L, S, frame_dt, input)
    S.acc = S.acc + max(0, frame_dt)
    local dt = L.rules.dt
    local steps = 0
    while S.acc >= dt - 1e-12 and steps < 240 do               -- at most 2 s of catch-up per frame
        S.acc = S.acc - dt
        R.step(L, S, input(S.n * dt))
        steps = steps + 1
    end
    return steps
end

-- Is the puppet's body clear of solid ground (alive, not mid-crush)? For tests and the view's sanity checks.
function R.body_free(L, S, inp)
    return free(L, R.ground(L, inp, S.t), S.x, S.y, S.mode == "slide" and slide_cols(L, S) or nil)
end
function R.support_top(L, S, inp)
    return support(L, R.ground(L, inp, S.t), S.x, S.y, 0.02, 0.02)
end
-- The level's challenges met (0..3 stars): reached the door, took the bonus star, arrived before the quick mark.
function R.stars(L, S)
    if not S.won then return 0, { false, false, false } end
    local c = { true, S.star and true or false, (L.quick_s == nil) or S.t <= L.quick_s }
    local n = 0
    for _, v in ipairs(c) do if v then n = n + 1 end end
    return n, c
end

return R
