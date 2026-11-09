-- Topple's Great Hall: the rules for millions of dominoes on one flat floor. Pure data and maths (no engine calls), so
-- the tests run it directly. Free Build's rules give each domino a table; here a domino is a row in a few flat arrays
-- and a build is the short list of shapes that made it, so a save is a few lines however many dominoes it holds.
-- A chain only ever touches the dominoes next to its front: the cost of a run follows how many are falling, not how
-- many there are. The engine's hinge field draws them and animates each fall from the moment it is told about it.
return function(F)
local H = {}
local floor, sqrt, abs, min, max, cos, sin, asin = math.floor, math.sqrt, math.abs, math.min, math.max, math.cos, math.sin, math.asin
local rad, pi = math.rad, math.pi
local atan2 = math.atan2 or math.atan
local running, yield = coroutine.running, coroutine.yield

local W, T, DH = F.DOM.w, F.DOM.t, F.DOM.h
local SPACING, LAT = F.SPACING, F.FIELD_LAT
local MIN2 = F.MIN_GAP * F.MIN_GAP
local REACH = DH + W
local LIMIT_HIT = rad(3)
local REST = rad(F.REST)

H.BOUND = 1200                    -- half the hall's side
H.CAP = 5000000
H.FIELD_WIDTH = { min = 1.2, max = 2300, default = 60 }
H.ERASE = { min = 1, max = 60, default = 4 }
local B = H.BOUND
local EDGE = B - 2
local CELL = 1.6                  -- a neighbour within reach is always in the 3 x 3 cells around a domino
local GRID = floor(2 * B / CELL) + 3
local CHUNK = 150000              -- dominoes laid between yields and between hand-offs to the engine

local PAINTS = {
    brick = { 0.5, 0.13, 0.07 }, mustard = { 0.78, 0.52, 0.13 }, sage = { 0.32, 0.44, 0.3 },
    navy = { 0.1, 0.16, 0.32 }, cream = { 0.84, 0.77, 0.62 },
}
local function rgba(c)
    return floor(c[1] * 255 + 0.5) + floor(c[2] * 255 + 0.5) * 256 + floor(c[3] * 255 + 0.5) * 65536 + 255 * 16777216
end
local RGBA, BANDS = {}, {}
for name, c in pairs(PAINTS) do RGBA[name] = rgba(c) end
for i, name in ipairs(F.PAINTS) do BANDS[i] = RGBA[name] end
local NBANDS = #BANDS

-- The store: one row per domino, ever (an erased one stays as a gap until the build is laid again).
local X, Y, CA, SA, NEXT, STAMP = {}, {}, {}, {}, {}, {}
local HEAD
local DEAD = {}
local COUNT, LIVE = 0, 0
local CHECK = true
local sink
-- Bells: each is listed in the cells around it, so a falling domino finds one with a single lookup.
H.BELL = { block = 2.0, side = 2.2, ring = 2.9, cap = 256 }
local BELL_BLOCK2, BELL_RING2 = H.BELL.block ^ 2, H.BELL.ring ^ 2
local bell_cells = {}
H.bells = {}

local flat, nflat, since = {}, 0, 0
local function flush()
    if nflat > 0 then
        sink.append(flat, nflat)
        nflat = 0
    end
end

local function in_coroutine()
    local co, main = running()
    return co ~= nil and main ~= true
end

local function reset_store()
    X, Y, CA, SA, NEXT, STAMP = {}, {}, {}, {}, {}, {}
    DEAD = {}
    bell_cells, H.bells = {}, {}
    COUNT, LIVE, nflat, since = 0, 0, 0, 0
    if not HEAD then HEAD = {} end
    for i = 1, GRID * GRID do HEAD[i] = 0 end
    sink.clear()
end

-- Lay one domino. Returns false when it is off the floor, too close to another, or the box is empty.
local function place(x, y, a, ca, sa, color)
    if COUNT >= H.CAP or x < -EDGE or x > EDGE or y < -EDGE or y > EDGE then return false end
    local ci, cj = floor((x + B) / CELL), floor((y + B) / CELL)
    local near_bells = bell_cells[cj * GRID + ci + 1]
    if near_bells then
        for k = 1, #near_bells do
            local b = near_bells[k]
            if not b.dead and (b.x - x) ^ 2 + (b.y - y) ^ 2 < BELL_BLOCK2 then return false end
        end
    end
    if CHECK then
        for j = cj - 1, cj + 1 do
            local base = j * GRID
            for i = ci - 1, ci + 1 do
                local q = HEAD[base + i + 1]
                while q ~= 0 do
                    local dx, dy = X[q] - x, Y[q] - y
                    if dx * dx + dy * dy < MIN2 and not DEAD[q] then return false end
                    q = NEXT[q]
                end
            end
        end
    end
    COUNT, LIVE = COUNT + 1, LIVE + 1
    local n, key = COUNT, cj * GRID + ci + 1
    X[n], Y[n], CA[n], SA[n], STAMP[n] = x, y, ca, sa, 0
    NEXT[n] = HEAD[key]
    HEAD[key] = n
    local b = nflat * 5
    flat[b + 1], flat[b + 2], flat[b + 3], flat[b + 4], flat[b + 5] = x, 0, -y, a, color
    nflat = nflat + 1
    since = since + 1
    if since >= CHUNK then
        since = 0
        flush()
        if in_coroutine() then yield() end
    end
    return true
end

local function by_name(paint)
    local c = RGBA[paint]
    if c then return function() return c end end
    return nil
end

------------------------------------------------------------------ shapes
local function lay_field(op)
    local dx, dy = op.bx - op.ax, op.by - op.ay
    local L = sqrt(dx * dx + dy * dy)
    if L < 1e-6 then return end
    local ux, uy = dx / L, dy / L
    local px, py = -uy, ux
    local a = atan2(uy, ux)
    local ca, sa = cos(a), sin(a)
    local nmax = max(1, floor(op.w / LAT + 1e-6) + 1)
    local rows = floor(L / SPACING + 1e-6) + 1
    local solid = by_name(op.paint)
    local paint = op.paint_at
    local ax, ay = op.ax, op.ay
    for k = 0, rows - 1 do
        local n
        if k + 1 <= nmax then n = k + 1 else n = ((k - nmax) % 2 == 0) and (nmax - 1) or nmax end
        if n < 1 then n = 1 end
        local s = k * SPACING
        local x0, y0 = ax + ux * s, ay + uy * s
        local half = (n - 1) / 2
        for i = 0, n - 1 do
            local l = (i - half) * LAT
            local x, y = x0 + px * l, y0 + py * l
            local color = paint and paint(x, y) or (solid and solid() or BANDS[(k + i) % NBANDS + 1])
            place(x, y, a, ca, sa, color)
        end
    end
end

-- Along a polyline, one domino every spacing, each facing the way the line runs there.
local function lay_path(pts, paint_name)
    local solid = by_name(paint_name)
    local have = 0
    local n = 0
    for s = 1, #pts - 2, 2 do
        local x0, y0, x1, y1 = pts[s], pts[s + 1], pts[s + 2], pts[s + 3]
        local dx, dy = x1 - x0, y1 - y0
        local L = sqrt(dx * dx + dy * dy)
        if L > 1e-6 then
            local ux, uy = dx / L, dy / L
            local a = atan2(uy, ux)
            local ca, sa = cos(a), sin(a)
            local d = have
            while d <= L do
                n = n + 1
                place(x0 + ux * d, y0 + uy * d, a, ca, sa, solid and solid() or BANDS[floor((n - 1) / 6) % NBANDS + 1])
                d = d + SPACING
            end
            have = d - L
        end
    end
end

local function lay_spiral(op)
    local R = sqrt((op.sx - op.cx) ^ 2 + (op.sy - op.cy) ^ 2)
    if R < F.SPIRAL_MIN + 0.5 then return end
    local solid = by_name(op.paint)
    local b = F.SPIRAL_GAP / (2 * pi)
    local ang = atan2(op.sy - op.cy, op.sx - op.cx)
    local sgn = op.cw and -1 or 1
    local r, n = R, 0
    while r > F.SPIRAL_MIN do
        local ca0, sa0 = cos(ang), sin(ang)
        local tx, ty = -b * ca0 - r * sa0 * sgn, -b * sa0 + r * ca0 * sgn
        local a = atan2(ty, tx)
        n = n + 1
        place(op.cx + r * ca0, op.cy + r * sa0, a, cos(a), sin(a), solid and solid() or BANDS[floor((n - 1) / 6) % NBANDS + 1])
        local dphi = SPACING / sqrt(r * r + b * b)
        ang = ang + dphi * sgn
        r = r - b * dphi
    end
end

-- A fan that opens to a wide field, about n dominoes, painted as a sunburst around its middle.
local function sample_spec(n)
    local rows_max = floor((2 * B - 80) / SPACING)
    local nmax = floor(sqrt(n) * 0.7)
    local rows = floor(n / nmax + nmax / 2) + 2
    if rows > rows_max then
        rows = rows_max
        nmax = floor(rows - sqrt(max(0, rows * rows - 2 * n))) + 2
    end
    return nmax, rows
end
local function lay_sample(n)
    local nmax, rows = sample_spec(n)
    local L, w = (rows - 1) * SPACING, (nmax - 1) * LAT
    local ax = -L / 2
    local cx, r0 = ax + L * 0.58, max(L, w) / 9
    local cap = H.CAP
    H.CAP = COUNT + n       -- exactly n, the last row cut short if it has to be
    lay_field({ ax = ax, ay = 0, bx = ax + L, by = 0, w = w, paint_at = function(x, y)
        local dx, dy = x - cx, y
        local r = sqrt(dx * dx + dy * dy)
        return BANDS[floor(atan2(dy, dx) / (2 * pi) * 40 + r / r0) % NBANDS + 1]
    end })
    H.CAP = cap
end

------------------------------------------------------------------ pictures
-- A picture is a fan that opens to its full width, then the image: the wave reaches every row of it as one straight
-- front. It runs left to right across the image, top of the image on the left of the way it runs. The fan carries the
-- colours of the picture's first column out to the point.
H.DRAW_COLORS = { { 0.84, 0.77, 0.62 }, { 0.5, 0.13, 0.07 }, { 0.78, 0.52, 0.13 }, { 0.32, 0.44, 0.3 },
    { 0.1, 0.16, 0.32 }, { 0.04, 0.04, 0.05 }, { 0.95, 0.94, 0.9 }, { 0.3, 0.56, 0.78 } }
local DRAW_RGBA = {}
for i, c in ipairs(H.DRAW_COLORS) do DRAW_RGBA[i] = rgba(c) end
local FAN = SPACING / LAT       -- how much longer than it is wide a fan runs

local pictures = {}
local function picture(src)
    local p = pictures[src]
    if p == nil then
        local w, h, cells = src:match("^draw:(%d+):(%d+):(%d+)$")
        if w then p = { w = tonumber(w), h = tonumber(h), cells = cells }
        else p = sink.load_picture and sink.load_picture(src) or false end
        pictures[src] = p
    end
    return p or nil
end

-- For a picture laid over length L: its width across, the fan's length, its length along, and about how many dominoes.
function H.picture_layout(src, L)
    local p = picture(src)
    if not p then return nil end
    local aspect = p.w / p.h
    local w = L / (FAN + aspect)
    local nmax = floor(w / LAT) + 1
    local rows = floor(L / SPACING) + 1
    return w, w * FAN, w * aspect, floor(rows * nmax - min(rows, nmax) ^ 2 / 2)
end

local function lay_picture(op)
    local dx, dy = op.bx - op.ax, op.by - op.ay
    local L = sqrt(dx * dx + dy * dy)
    local p = L > 1e-6 and picture(op.src)
    if not p then return end
    local w, fan, len = H.picture_layout(op.src, L)
    local ux, uy, ax, ay = dx / L, dy / L, op.ax, op.ay
    local pw, ph, cells, rgb, byte = p.w, p.h, p.cells, p.rgb, string.byte
    lay_field({ ax = ax, ay = ay, bx = op.bx, by = op.by, w = w, paint_at = function(x, y)
        local rx, ry = x - ax, y - ay
        local s, l = rx * ux + ry * uy, ry * ux - rx * uy
        local ix = max(0, min(pw - 1, floor((s - fan) / len * pw)))
        local iy = max(0, min(ph - 1, floor((0.5 - l / w) * ph)))
        if cells then return DRAW_RGBA[byte(cells, iy * pw + ix + 1) - 47] or DRAW_RGBA[1] end
        local b = (iy * pw + ix) * 3
        local r, g, bl = byte(rgb, b + 1, b + 3)
        return r + g * 256 + bl * 65536 + 4278190080
    end })
end

------------------------------------------------------------------ splitters
-- One wave into several: a small fan opens it, and from its last row each branch runs on, curves out to its own
-- heading and carries on straight to the length of the drag.
H.SPLIT = { min = 2, max = 6, default = 3 }
local SPLIT_GAP, SPLIT_SPREAD, SPLIT_R = 6, rad(52), 8     -- dominoes between branches at the fan, half the spread, curve radius
local SPLIT_PAINTS = { "brick", "navy", "sage", "cream", "brick", "navy" }

-- The fan's end along the drag, its width, and each branch as a polyline {x, y, ...}.
function H.splitter_paths(op)
    local dx, dy = op.bx - op.ax, op.by - op.ay
    local L = sqrt(dx * dx + dy * dy)
    if L < 1e-6 then return nil end
    local ux, uy = dx / L, dy / L
    local base = atan2(uy, ux)
    local nmax = (op.n - 1) * SPLIT_GAP + 1
    local fan = (nmax - 1) * SPACING
    local reach = L - fan - SPACING
    if reach < 2 then return nil end
    local paths = {}
    for j = 0, op.n - 1 do
        local t = (j - (op.n - 1) / 2) / ((op.n - 1) / 2)
        local lat = (j - (op.n - 1) / 2) * SPLIT_GAP * LAT
        local x = op.ax + ux * (fan + SPACING) - uy * lat
        local y = op.ay + uy * (fan + SPACING) + ux * lat
        local pts = { x, y }
        local used, step, turn = 0, SPACING, t * SPLIT_SPREAD
        local function go(a, d)
            x, y = x + cos(a) * d, y + sin(a) * d
            pts[#pts + 1], pts[#pts + 2] = x, y
            used = used + d
        end
        go(base, min(1.2, reach))
        local steps = floor(abs(turn) * SPLIT_R / step + 0.5)
        for s = 1, steps do
            if used + step <= reach then go(base + turn * s / steps, step) end
        end
        if reach > used then go(base + turn, reach - used) end
        paths[j + 1] = pts
    end
    return fan, (nmax - 1) * LAT, paths
end

local function lay_splitter(op)
    local fan, w, paths = H.splitter_paths(op)
    if not fan then return end
    local dx, dy = op.bx - op.ax, op.by - op.ay
    local L = sqrt(dx * dx + dy * dy)
    lay_field({ ax = op.ax, ay = op.ay, bx = op.ax + dx / L * fan, by = op.ay + dy / L * fan, w = w, paint = "mustard" })
    for j, pts in ipairs(paths) do lay_path(pts, op.paint or SPLIT_PAINTS[j]) end
end

local function each_near(x, y, r, fn)
    local reach = floor(r / CELL) + 1
    local ci, cj = floor((x + B) / CELL), floor((y + B) / CELL)
    for j = max(0, cj - reach), min(GRID - 1, cj + reach) do
        local base = j * GRID
        for i = max(0, ci - reach), min(GRID - 1, ci + reach) do
            local q = HEAD[base + i + 1]
            while q ~= 0 do
                if not DEAD[q] then fn(q) end
                q = NEXT[q]
            end
        end
    end
end

-- The live domino nearest (x, y) within r, or nil: its row, x, y and facing.
function H.pick(x, y, r)
    local best, bd = nil, r * r
    each_near(x, y, r, function(q)
        local d = (X[q] - x) ^ 2 + (Y[q] - y) ^ 2
        if d <= bd then best, bd = q, d end
    end)
    if best then return best, X[best], Y[best], atan2(SA[best], CA[best]) end
    return nil
end

-- Is there room for a bell here? True, or false and why.
local function bell_clear(x, y)
    if abs(x) > EDGE - 4 or abs(y) > EDGE - 4 then return false, "That's too near the wall." end
    if #H.bells >= H.BELL.cap then return false, "That's every bell there is." end
    for _, b in ipairs(H.bells) do
        if not b.dead and (b.x - x) ^ 2 + (b.y - y) ^ 2 < 16 then return false, "There's a bell there already." end
    end
    local blocked = false
    each_near(x, y, H.BELL.block, function(q)
        if (X[q] - x) ^ 2 + (Y[q] - y) ^ 2 < BELL_BLOCK2 then blocked = true end
    end)
    if blocked then return false, "A bell stands beside a line, not on it." end
    return true
end

-- Where a click puts a bell: beside the nearest domino on the clicked side, along its line. x, y, angle; or nil, why.
function H.bell_spot(x, y)
    local i, px, py, a = H.pick(x, y, 3.5)
    local bx, by, ang = x, y, 0
    if i then
        local nx, ny = -sin(a), cos(a)
        local side = (x - px) * nx + (y - py) * ny >= 0 and 1 or -1
        bx, by, ang = px + nx * side * H.BELL.side, py + ny * side * H.BELL.side, a
    end
    local ok, why = bell_clear(bx, by)
    if not ok then return nil, why end
    return bx, by, ang
end

local function lay_bell(op)
    if not bell_clear(op.x, op.y) then return end
    local b = { x = op.x, y = op.y, a = op.a, rung = 0 }
    H.bells[#H.bells + 1] = b
    local ci, cj = floor((b.x + B) / CELL), floor((b.y + B) / CELL)
    for j = cj - 2, cj + 2 do
        for i = ci - 2, ci + 2 do
            local key = j * GRID + i + 1
            local list = bell_cells[key]
            if not list then list = {}; bell_cells[key] = list end
            list[#list + 1] = b
        end
    end
end

local hide_list, nhide = {}, 0
local function lay_erase(op)
    for s = 1, #op.pts - 2, 3 do
        local x, y, r = op.pts[s], op.pts[s + 1], op.pts[s + 2]
        for _, b in ipairs(H.bells) do
            if (b.x - x) ^ 2 + (b.y - y) ^ 2 <= r * r then b.dead = true end
        end
        each_near(x, y, r, function(q)
            if (X[q] - x) ^ 2 + (Y[q] - y) ^ 2 <= r * r then
                DEAD[q] = true
                LIVE = LIVE - 1
                nhide = nhide + 1
                hide_list[nhide] = q - 1
            end
        end)
    end
    if nhide > 0 then
        sink.hide(hide_list, nhide)
        nhide = 0
    end
end

------------------------------------------------------------------ the build
H.ops = {}
H.redo_ops = {}
local start_i, start_dir

local function apply(op)
    local k = op.k
    if k == "field" then lay_field(op)
    elseif k == "line" then lay_path({ op.ax, op.ay, op.bx, op.by }, op.paint)
    elseif k == "draw" then lay_path(op.pts, op.paint)
    elseif k == "spiral" then lay_spiral(op)
    elseif k == "picture" then lay_picture(op)
    elseif k == "splitter" then lay_splitter(op)
    elseif k == "bell" then
        flush()
        lay_bell(op)
    elseif k == "sample" then
        CHECK = COUNT > 0
        lay_sample(op.n)
        CHECK = true
    elseif k == "erase" then
        flush()
        lay_erase(op)
    elseif k == "start" then
        local i = H.pick(op.x, op.y, 1.0)
        if i then start_i, start_dir = i, op.dir end
    end
end

-- Lay the whole build again, from the last clear on. Run inside a coroutine it hands back every so often.
function H.rebuild()
    reset_store()
    start_i, start_dir = nil, nil
    local first = 1
    for i = #H.ops, 1, -1 do
        if H.ops[i].k == "clear" or H.ops[i].k == "sample" then first = i; break end
    end
    for i = first, #H.ops do apply(H.ops[i]) end
    flush()
    sink.rebuild()
end

-- A new shape, laid on top of what is there.
function H.add(op)
    H.ops[#H.ops + 1] = op
    H.redo_ops = {}
    if op.k == "clear" or op.k == "sample" then
        H.rebuild()
    else
        apply(op)
        flush()
    end
end

function H.init(s)
    sink = s
    reset_store()
end
function H.undo()
    local op = table.remove(H.ops)
    if not op then return false end
    H.redo_ops[#H.redo_ops + 1] = op
    H.rebuild()
    return true
end
function H.redo()
    local op = table.remove(H.redo_ops)
    if not op then return false end
    H.ops[#H.ops + 1] = op
    H.rebuild()
    return true
end

function H.count() return LIVE end

-- Where the tip starts: the chosen domino, or else the first still standing. Row, x, y, facing, direction.
function H.starter()
    local i, dir = start_i, start_dir or 1
    if not i or DEAD[i] then
        i, dir = nil, 1
        for q = 1, COUNT do
            if not DEAD[q] then i = q; break end
        end
    end
    if not i then return nil end
    return i, X[i], Y[i], atan2(SA[i], CA[i]), dir
end

------------------------------------------------------------------ saving
function H.serialize()
    local out = { "TOPPLE-HALL 1" }
    local function join(t)
        local s = {}
        for i = 1, #t do s[i] = string.format("%.3f", t[i]) end
        return table.concat(s, " ")
    end
    for _, op in ipairs(H.ops) do
        local k = op.k
        if k == "field" then out[#out + 1] = "field " .. join({ op.ax, op.ay, op.bx, op.by, op.w }) .. " " .. (op.paint or "-")
        elseif k == "line" then out[#out + 1] = "line " .. join({ op.ax, op.ay, op.bx, op.by }) .. " " .. (op.paint or "-")
        elseif k == "draw" then out[#out + 1] = "draw " .. (op.paint or "-") .. " " .. join(op.pts)
        elseif k == "spiral" then out[#out + 1] = "spiral " .. join({ op.cx, op.cy, op.sx, op.sy }) .. " " .. (op.cw and 1 or 0) .. " " .. (op.paint or "-")
        elseif k == "bell" then out[#out + 1] = "bell " .. join({ op.x, op.y, op.a })
        elseif k == "splitter" then out[#out + 1] = "splitter " .. join({ op.ax, op.ay, op.bx, op.by }) .. " " .. op.n .. " " .. (op.paint or "-")
        elseif k == "picture" then out[#out + 1] = "picture " .. join({ op.ax, op.ay, op.bx, op.by }) .. " " .. op.src
        elseif k == "sample" then out[#out + 1] = "sample " .. op.n
        elseif k == "clear" then out[#out + 1] = "clear"
        elseif k == "erase" then out[#out + 1] = "erase " .. join(op.pts)
        elseif k == "start" then out[#out + 1] = "start " .. join({ op.x, op.y }) .. " " .. op.dir end
    end
    return table.concat(out, "\n") .. "\n"
end

local function numbers(s)
    local t = {}
    for v in s:gmatch("%S+") do
        local n = tonumber(v)
        if not n or n - n ~= 0 then return nil end
        t[#t + 1] = n
    end
    return t
end
-- A damaged line loses only its own shape. Returns false when this is not a saved hall at all.
function H.deserialize(text)
    if not text or not text:match("^TOPPLE%-HALL 1") then return false end
    H.ops, H.redo_ops = {}, {}
    local paint = function(p) return p ~= "-" and p or nil end
    for line in text:gmatch("[^\n]+") do
        local k, rest = line:match("^(%a+)%s*(.*)$")
        local op
        if k == "field" or k == "line" then
            local nums, p = rest:match("^(.*)%s(%S+)$")
            local t = nums and numbers(nums)
            if t and k == "field" and #t == 5 then op = { k = k, ax = t[1], ay = t[2], bx = t[3], by = t[4], w = t[5], paint = paint(p) }
            elseif t and k == "line" and #t == 4 then op = { k = k, ax = t[1], ay = t[2], bx = t[3], by = t[4], paint = paint(p) } end
        elseif k == "draw" then
            local p, nums = rest:match("^(%S+)%s(.*)$")
            local t = nums and numbers(nums)
            if t and #t >= 2 and #t % 2 == 0 then op = { k = k, pts = t, paint = paint(p) } end
        elseif k == "spiral" then
            local nums, cw, p = rest:match("^(.*)%s(%d)%s(%S+)$")
            local t = nums and numbers(nums)
            if t and #t == 4 then op = { k = k, cx = t[1], cy = t[2], sx = t[3], sy = t[4], cw = cw == "1", paint = paint(p) } end
        elseif k == "bell" then
            local t = numbers(rest)
            if t and #t == 3 then op = { k = k, x = t[1], y = t[2], a = t[3] } end
        elseif k == "splitter" then
            local nums, n, p = rest:match("^(.*)%s(%d+)%s(%S+)$")
            local t = nums and numbers(nums)
            n = tonumber(n)
            if t and #t == 4 and n >= H.SPLIT.min and n <= H.SPLIT.max then
                op = { k = k, ax = t[1], ay = t[2], bx = t[3], by = t[4], n = n, paint = paint(p) }
            end
        elseif k == "picture" then
            local a, b, c, d, src = rest:match("^(%S+) (%S+) (%S+) (%S+) (.+)$")
            local t = a and numbers(a .. " " .. b .. " " .. c .. " " .. d)
            if t then op = { k = k, ax = t[1], ay = t[2], bx = t[3], by = t[4], src = src } end
        elseif k == "sample" then
            local n = tonumber(rest)
            if n and n > 0 and n <= H.CAP then op = { k = k, n = floor(n) } end
        elseif k == "clear" then op = { k = k }
        elseif k == "erase" then
            local t = numbers(rest)
            if t and #t >= 3 and #t % 3 == 0 then op = { k = k, pts = t } end
        elseif k == "start" then
            local nums, d = rest:match("^(.*)%s(%-?%d+)$")
            local t = nums and numbers(nums)
            if t and #t == 2 then op = { k = k, x = t[1], y = t[2], dir = tonumber(d) >= 0 and 1 or -1 } end
        end
        if op then H.ops[#H.ops + 1] = op end
    end
    return true
end

------------------------------------------------------------------ a run
local HT, HQ, HX, HY, hn = {}, {}, {}, {}, 0
local run = 0
local fall, nfall = {}, 0
local hit_q, hit_th = {}, {}

local function heap_push(t, q, dx, dy)
    hn = hn + 1
    local i = hn
    while i > 1 do
        local p = floor(i / 2)
        if HT[p] <= t then break end
        HT[i], HQ[i], HX[i], HY[i] = HT[p], HQ[p], HX[p], HY[p]
        i = p
    end
    HT[i], HQ[i], HX[i], HY[i] = t, q, dx, dy
end
local function heap_pop()
    local t, q, dx, dy = HT[hn], HQ[hn], HX[hn], HY[hn]
    hn = hn - 1
    local i, n = 1, hn
    while true do
        local c = 2 * i
        if c > n then break end
        if c < n and HT[c + 1] < HT[c] then c = c + 1 end
        if HT[c] >= t then break end
        HT[i], HQ[i], HX[i], HY[i] = HT[c], HQ[c], HX[c], HY[c]
        i = c
    end
    if n > 0 then HT[i], HQ[i], HX[i], HY[i] = t, q, dx, dy end
end

H.toppled, H.last_t = 0, 0
H.rung, H.rung_total = {}, 0    -- bells this run has rung and the view hasn't played yet; how many so far
function H.bell_count()
    local n = 0
    for _, b in ipairs(H.bells) do if not b.dead then n = n + 1 end end
    return n
end
H.spots, H.nspots = {}, 0      -- a few of this frame's fallers (x, y pairs), for the view's dust

-- Tip the starter. False if there is nothing to tip.
function H.tip()
    local i, _, _, _, dir = H.starter()
    if not i then return false end
    run, hn = run + 1, 0
    H.toppled, H.last_t = 0, 0
    H.rung, H.rung_total = {}, 0
    heap_push(0, i, CA[i] * dir, SA[i] * dir)
    return true
end

-- Everything due by t: tells the engine each fall, returns how many started and the average place they started.
function H.advance(t)
    local stamp, dead, head, nxt, xs, ys, cas, sas = STAMP, DEAD, HEAD, NEXT, X, Y, CA, SA
    local started, sx, sy = 0, 0, 0
    local x0, x1, y0, y1 = 1e9, -1e9, 1e9, -1e9
    local nspot = 0
    local half_t, half_w = T / 2, W / 2
    nfall = 0
    while hn > 0 and HT[1] <= t do
        local t0, p, dx, dy = HT[1], HQ[1], HX[1], HY[1]
        heap_pop()
        local px, py = xs[p], ys[p]
        if stamp[p] ~= run and not dead[p] then
            local ax, ay = cas[p], sas[p]
            local d = dx * ax + dy * ay
            if abs(d) >= 0.3 then
                local sgn = d > 0 and 1 or -1
                local fx, fy = ax * sgn, ay * sgn
                stamp[p] = run
                H.toppled = H.toppled + 1
                started, sx, sy = started + 1, sx + px, sy + py
                x0, x1, y0, y1 = min(x0, px), max(x1, px), min(y0, py), max(y1, py)
                if started % 24 == 1 then
                    local s = (nspot % 6) * 2
                    H.spots[s + 1], H.spots[s + 2] = px, py
                    nspot = nspot + 1
                end
                local ci, cj = floor((px + B) / CELL), floor((py + B) / CELL)
                local near_bells = bell_cells[cj * GRID + ci + 1]
                if near_bells then
                    for k = 1, #near_bells do
                        local b = near_bells[k]
                        if b.rung ~= run and not b.dead and (b.x - px) ^ 2 + (b.y - py) ^ 2 < BELL_RING2 then
                            b.rung = run
                            H.rung[#H.rung + 1] = b
                            H.rung_total = H.rung_total + 1
                        end
                    end
                end
                local nh, best = 0, nil
                for j = cj - 1, cj + 1 do
                    local base = j * GRID
                    for i = ci - 1, ci + 1 do
                        local q = head[base + i + 1]
                        while q ~= 0 do
                            if q ~= p and stamp[q] ~= run and not dead[q] then
                                local rx, ry = xs[q] - px, ys[q] - py
                                local along = rx * fx + ry * fy
                                if along > 0.02 and along < REACH then
                                    local qax, qay = cas[q], sas[q]
                                    local cq, sq = abs(qax * fx + qay * fy), abs(qax * fy - qay * fx)
                                    if abs(rx * fy - ry * fx) < half_w + sq * half_t + cq * half_w - 0.02 then
                                        local c = max(along - half_t - (cq * half_t + sq * half_w), 0.02)
                                        if c < DH then
                                            local th = asin(c / DH)
                                            nh = nh + 1
                                            hit_q[nh], hit_th[nh] = q, th
                                            if not best or th < best then best = th end
                                        end
                                    end
                                end
                            end
                            q = nxt[q]
                        end
                    end
                end
                local contact, final
                if best then
                    contact, final = best, F.rest_angle(best)
                    local tc = t0 + F.fall_time(contact)
                    for i = 1, nh do
                        if hit_th[i] <= best + LIMIT_HIT then heap_push(tc, hit_q[i], fx, fy) end
                    end
                else
                    contact, final = REST, REST
                end
                local tc = t0 + F.fall_time(contact)
                local b = nfall * 6
                fall[b + 1], fall[b + 2], fall[b + 3], fall[b + 4], fall[b + 5], fall[b + 6] = p - 1, t0, tc, contact, final, sgn
                nfall = nfall + 1
                if tc + 0.15 > H.last_t then H.last_t = tc + 0.15 end
            end
        end
    end
    if nfall > 0 then sink.fall(fall, nfall) end
    H.nspots = min(nspot, 6)
    if started > 0 then return started, sx / started, sy / started, sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2) end
    return 0
end

-- Nothing left to start and everything has landed.
function H.finished(t) return hn == 0 and t > H.last_t + 0.3 end

function H.stand()
    hn = 0
    sink.stand_all()
end

-- For the tests: the row of a domino laid at (x, y), and whether this run knocked it over.
function H.fell(i) return STAMP[i] == run end
function H.rows() return COUNT end

return H
end
