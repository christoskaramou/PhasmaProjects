-- Arrow Out rules: pure Lua, no engine calls (tests run it under luajit).
-- A board is a grid of bent arrows. Tapping an arrow slides it head-first along its
-- head direction; it leaves the board if every cell on that ray is empty, otherwise it
-- bumps the first arrow in the way and the player loses a heart.
--
-- Levels are solvable by construction: arrows are generated one at a time and each new
-- arrow's ray must be clear of every arrow generated before it, so removing arrows in
-- reverse generation order always works. Removal only ever frees cells, so any arrow
-- that can leave now can still leave later: there are no dead ends, only mistakes.
local R = {}

R.DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } } -- up, right, down, left (y grows down)
R.DIR_NAMES = { "up", "right", "down", "left" }
R.LIVES = 3

local floor, min, max, abs = math.floor, math.min, math.max, math.abs

-- Park-Miller LCG: identical sequence under LuaJIT and Lua 5.4 (all values stay exact doubles).
function R.rng(seed)
    local s = floor(seed) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function(a, b)
        s = (s * 16807) % 2147483647
        local f = (s - 1) / 2147483646
        if a then return a + floor(f * (b - a + 1)) end
        return f
    end
end

local function shuffle(t, rand)
    for i = #t, 2, -1 do
        local j = rand(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

------------------------------------------------------------------ shapes
-- Each mask takes normalised coordinates u, v in [-1, 1] (cell centres) and returns true
-- for cells that belong to the picture. Rays still travel over non-picture cells.
local SHAPES = {
    { name = "Square", f = function() return true end },
    { name = "Diamond", f = function(u, v) return abs(u) + abs(v) <= 1.08 end },
    { name = "Heart", f = function(u, v)
        local x, y = u * 1.25, -v * 1.25 + 0.25
        local a = x * x + y * y - 1
        return a * a * a - x * x * y * y * y <= 0
    end },
    { name = "Circle", f = function(u, v) return u * u + v * v <= 1.05 end },
    { name = "House", f = function(u, v)
        if v >= -0.1 then return abs(u) <= 0.78 end
        return abs(u) <= (v + 1.05) * 0.95 + 0.05
    end },
    { name = "Cross", f = function(u, v) return abs(u) <= 0.38 or abs(v) <= 0.38 end },
    { name = "Ring", f = function(u, v) local d = u * u + v * v; return d <= 1.05 and d >= 0.18 end },
    { name = "Hourglass", f = function(u, v) return abs(u) <= abs(v) + 0.2 end },
}
R.SHAPES = SHAPES

-- Level n: the grid grows every two levels and the shape cycles. Deterministic per level.
function R.level_spec(n)
    n = max(1, floor(n))
    local w = min(18, 5 + floor((n + 1) / 2))
    local h = min(26, floor(w * 1.35 + 0.5))
    local shape = SHAPES[((n - 1) % #SHAPES) + 1]
    return { level = n, w = w, h = h, shape = shape, seed = n * 7919 + 101,
             min_len = 2, max_len = min(9, 3 + floor(n / 3)) }
end

------------------------------------------------------------------ generation
local function key(x, y, w) return (y - 1) * w + x end

function R.generate(spec)
    local w, h = spec.w, spec.h
    local rand = R.rng(spec.seed)
    local mask, occ, ray_max = {}, {}, {}
    local cells = {}
    for y = 1, h do
        for x = 1, w do
            local u = (x - 0.5) / w * 2 - 1
            local v = (y - 0.5) / h * 2 - 1
            local k = key(x, y, w)
            mask[k] = spec.shape.f(u, v) and true or false
            occ[k] = 0
            ray_max[k] = 0
            if mask[k] then cells[#cells + 1] = { x, y } end
        end
    end
    local function inside(x, y) return x >= 1 and y >= 1 and x <= w and y <= h end
    local function ray_clear(x, y, d)
        local dx, dy = R.DIRS[d][1], R.DIRS[d][2]
        x, y = x + dx, y + dy
        while inside(x, y) do
            if occ[key(x, y, w)] ~= 0 then return false end
            x, y = x + dx, y + dy
        end
        return true
    end
    local function on_ray(hx, hy, d, x, y)
        local dx, dy = R.DIRS[d][1], R.DIRS[d][2]
        if dx ~= 0 then return y == hy and (x - hx) * dx > 0 end
        return x == hx and (y - hy) * dy > 0
    end

    local arrows = {}
    local function try_place(hx, hy)
        local dirs = shuffle({ 1, 2, 3, 4 }, rand)
        for _, d in ipairs(dirs) do
            if ray_clear(hx, hy, d) then
                -- Grow the body backwards from the head: path[1] = head.
                local target = rand(spec.min_len, spec.max_len)
                local path, used = { { hx, hy } }, { [key(hx, hy, w)] = true }
                local bx, by = -R.DIRS[d][1], -R.DIRS[d][2] -- first body step points away from the head direction
                while #path < target do
                    local tx, ty = path[#path][1], path[#path][2]
                    local opts = {}
                    for nd = 1, 4 do
                        local nx, ny = tx + R.DIRS[nd][1], ty + R.DIRS[nd][2]
                        local nk = inside(nx, ny) and key(nx, ny, w)
                        if nk and mask[nk] and occ[nk] == 0 and not used[nk] and not on_ray(hx, hy, d, nx, ny) then
                            local straight = (R.DIRS[nd][1] == bx and R.DIRS[nd][2] == by)
                            opts[#opts + 1] = { nx, ny, nd, straight and 3 or 2 }
                        end
                    end
                    if #opts == 0 then break end
                    local total = 0
                    for _, o in ipairs(opts) do total = total + o[4] end
                    local pick = rand() * total
                    local choice = opts[#opts]
                    for _, o in ipairs(opts) do
                        pick = pick - o[4]
                        if pick <= 0 then choice = o; break end
                    end
                    path[#path + 1] = { choice[1], choice[2] }
                    used[key(choice[1], choice[2], w)] = true
                    bx, by = R.DIRS[choice[3]][1], R.DIRS[choice[3]][2]
                end
                if #path >= spec.min_len then
                    local body = {}
                    for i = #path, 1, -1 do body[#body + 1] = path[i] end -- tail first, head last
                    local id = #arrows + 1
                    arrows[id] = { cells = body, dir = d }
                    for _, c in ipairs(body) do occ[key(c[1], c[2], w)] = id end
                    return true
                end
            end
        end
        return false
    end

    -- Fill passes until nothing more fits.
    local placed = true
    while placed do
        placed = false
        for _, c in ipairs(shuffle(cells, rand)) do
            if occ[key(c[1], c[2], w)] == 0 and try_place(c[1], c[2]) then placed = true end
        end
    end

    -- Tail extension: an arrow may grow into an empty neighbour unless that cell lies on the
    -- ray of itself or of any arrow generated after it (those leave the board first).
    for id, a in ipairs(arrows) do
        local hx, hy = a.cells[#a.cells][1], a.cells[#a.cells][2]
        local dx, dy = R.DIRS[a.dir][1], R.DIRS[a.dir][2]
        local x, y = hx + dx, hy + dy
        while inside(x, y) do
            local k = key(x, y, w)
            ray_max[k] = max(ray_max[k], id)
            x, y = x + dx, y + dy
        end
    end
    local cap = spec.max_len + 3
    local grew = true
    while grew do
        grew = false
        for id, a in ipairs(arrows) do
            if #a.cells < cap then
                local tx, ty = a.cells[1][1], a.cells[1][2]
                for _, nd in ipairs(shuffle({ 1, 2, 3, 4 }, rand)) do
                    local nx, ny = tx + R.DIRS[nd][1], ty + R.DIRS[nd][2]
                    local nk = inside(nx, ny) and key(nx, ny, w)
                    if nk and mask[nk] and occ[nk] == 0 and ray_max[nk] < id then
                        table.insert(a.cells, 1, { nx, ny })
                        occ[nk] = id
                        grew = true
                        break
                    end
                end
            end
        end
    end

    -- Present arrows in a shuffled order so ids leak nothing about the solution.
    local order = {}
    for i = 1, #arrows do order[i] = i end
    shuffle(order, rand)
    local out = {}
    for i, src in ipairs(order) do out[i] = arrows[src] end
    return out, mask
end

------------------------------------------------------------------ game
local Game = {}
Game.__index = Game
R.Game = Game

function R.new_game(level)
    local spec = R.level_spec(level)
    local arrows, mask = R.generate(spec)
    local g = setmetatable({ spec = spec, level = spec.level, w = spec.w, h = spec.h, mask = mask,
        arrows = arrows, lives = R.LIVES, moves = 0, mistakes = 0, left = #arrows, occ = {} }, Game)
    for k = 1, g.w * g.h do g.occ[k] = 0 end
    for id, a in ipairs(arrows) do
        a.alive = true
        for _, c in ipairs(a.cells) do g.occ[key(c[1], c[2], g.w)] = id end
    end
    return g
end

function Game:inside(x, y) return x >= 1 and y >= 1 and x <= self.w and y <= self.h end
function Game:at(x, y) if self:inside(x, y) then return self.occ[key(x, y, self.w)] end return 0 end
function Game:head(id) local a = self.arrows[id]; return a.cells[#a.cells] end

-- Returns nil when the ray is clear, else (free steps before the blocker, blocker id).
function Game:blocked(id)
    local a = self.arrows[id]
    local hd = a.cells[#a.cells]
    local dx, dy = R.DIRS[a.dir][1], R.DIRS[a.dir][2]
    local x, y, steps = hd[1] + dx, hd[2] + dy, 0
    while self:inside(x, y) do
        local o = self.occ[key(x, y, self.w)]
        if o ~= 0 then return steps, o end
        steps = steps + 1
        x, y = x + dx, y + dy
    end
    return nil
end

-- Steps for the head to leave the board (used for the slide animation).
function Game:exit_steps(id)
    local a = self.arrows[id]
    local hd = a.cells[#a.cells]
    local d = a.dir
    if d == 1 then return hd[2] elseif d == 2 then return self.w - hd[1] + 1
    elseif d == 3 then return self.h - hd[2] + 1 end
    return hd[1]
end

-- Tap the arrow covering cell (x, y). Returns nil when nothing is there or the game is over,
-- else { ok, id, steps, blocker }.
function Game:tap(x, y)
    if self:over() then return nil end
    local id = self:at(x, y)
    if id == 0 then return nil end
    return self:tap_arrow(id)
end

function Game:tap_arrow(id)
    local a = self.arrows[id]
    if not a or not a.alive or self:over() then return nil end
    self.moves = self.moves + 1
    local steps, blocker = self:blocked(id)
    if steps then
        -- One heart per (arrow, blocker) pair: tapping the same arrow into the same blocker again is free.
        self.charged = self.charged or {}
        local repeat_hit = self.charged[id] == blocker
        if not repeat_hit then
            self.charged[id] = blocker
            self.lives = self.lives - 1
            self.mistakes = self.mistakes + 1
        end
        return { ok = false, id = id, steps = steps, blocker = blocker, free = repeat_hit }
    end
    a.alive = false
    self.left = self.left - 1
    for _, c in ipairs(a.cells) do self.occ[key(c[1], c[2], self.w)] = 0 end
    return { ok = true, id = id, steps = self:exit_steps(id) }
end

function Game:free_arrows()
    local out = {}
    for id, a in ipairs(self.arrows) do
        if a.alive and not self:blocked(id) then out[#out + 1] = id end
    end
    return out
end

function Game:hint() return self:free_arrows()[1] end
function Game:won() return self.left == 0 end
function Game:lost() return self.lives <= 0 and not self:won() end
function Game:over() return self:won() or self:lost() end

return R
