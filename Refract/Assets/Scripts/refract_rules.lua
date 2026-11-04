-- Refract rules: map generation, beam tracing, enemies, waves and economy. No engine calls, so the
-- whole game can run headless (tests/rules_test.lua drives it with a bot).
local R = {}

R.W, R.H = 22, 13
R.WAVES = 12            -- waves per sector
R.CORE = 20             -- core integrity
R.START_ENERGY = 170
R.SURGE_TIME, R.SURGE_MULT = 5, 3
R.CALL_TIME = 14        -- seconds between waves before the next one starts on its own
R.MAX_BEAM = 120        -- cells one emitter's light may travel in total (stops mirror loops)

-- Directions: 1 up, 2 right, 3 down, 4 left (screen coordinates, y grows down).
R.DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
local DIRS = R.DIRS
local function dir_index(dx, dy)
    for i, d in ipairs(DIRS) do if d[1] == dx and d[2] == dy then return i end end
end

-- Pieces. Emitters fire white light; mirrors turn it; prisms split white into red / green / blue;
-- lenses focus whatever passes through.
R.PIECES = {
    emitter = { cost = 60, name = "Emitter" },
    mirror  = { cost = 15, name = "Mirror" },
    prism   = { cost = 55, name = "Prism" },
    lens    = { cost = 40, name = "Lens" },
}
R.TOOLS = { "emitter", "mirror", "prism", "lens", "upgrade" }
R.EMITTER_POWER = { 9, 16, 26 }   -- damage per second per cell of contact, by tier
R.UPGRADE_COST = { 70, 115 }      -- to tier 2, to tier 3
R.PRISM_SPLIT = 0.62              -- each coloured ray keeps this share of the white input
R.LENS_GAIN = 1.5
R.SELL_BACK = 0.7

R.COLORS = { "w", "r", "g", "b" }

-- Enemies. mult: damage taken from each light colour.
R.ENEMIES = {
    mote   = { hp = 1.0, speed = 1.55, reward = 4,  leak = 1, size = 0.3, mult = { w = 1, r = 1, g = 1, b = 1 } },
    dart   = { hp = 0.55, speed = 2.9, reward = 4,  leak = 1, size = 0.24, mult = { w = 1, r = 1, g = 1, b = 1 } },
    hulk   = { hp = 3.4, speed = 0.85, reward = 12, leak = 3, size = 0.46, mult = { w = 1, r = 1, g = 1, b = 1 } },
    shade_r = { hp = 1.5, speed = 1.3, reward = 8, leak = 1, size = 0.36, shield = "r", mult = { w = 0.45, r = 2.2, g = 0.3, b = 0.3 } },
    shade_g = { hp = 1.5, speed = 1.3, reward = 8, leak = 1, size = 0.36, shield = "g", mult = { w = 0.45, r = 0.3, g = 2.2, b = 0.3 } },
    shade_b = { hp = 1.5, speed = 1.3, reward = 8, leak = 1, size = 0.36, shield = "b", mult = { w = 0.45, r = 0.3, g = 0.3, b = 2.2 } },
    mirrorback = { hp = 1.3, speed = 1.4, reward = 9, leak = 1, size = 0.38, mult = { w = 0, r = 1.25, g = 1.25, b = 1.25 } },
    splitter = { hp = 1.7, speed = 1.2, reward = 6, leak = 2, size = 0.42, split = 3, mult = { w = 1, r = 1, g = 1, b = 1 } },
    -- The Eclipse's shield cycles red -> green -> blue, so only a board with every colour keeps burning it.
    eclipse = { hp = 22, speed = 0.6, reward = 90, leak = 6, size = 0.62, cycle = 3.0, mult = { w = 0.35, r = 0.3, g = 0.3, b = 0.3 } },
}
R.ENEMY_NAMES = {
    mote = "Mote", dart = "Dart", hulk = "Hulk", shade_r = "Red Shade", shade_g = "Green Shade", shade_b = "Blue Shade",
    mirrorback = "Mirrorback", splitter = "Splitter", eclipse = "ECLIPSE",
}

local floor, min, max, abs = math.floor, math.min, math.max, math.abs

------------------------------------------------------------------ rng
local function rng(seed)
    local s = (seed * 2654435761) % 4294967296
    if s == 0 then s = 1 end
    return function(a, b)
        s = (s * 1103515245 + 12345) % 2147483648
        local f = s / 2147483648
        if a then return a + floor(f * (b - a + 1)) end
        return f
    end
end

------------------------------------------------------------------ map
-- Cell kinds: "ground" (buildable), "path", "rock" (blocks light and building), "core", "gate".
local function idx(x, y) return (y - 1) * R.W + x end
R.idx = idx

local function gen_map(sector)
    local W, H = R.W, R.H
    for attempt = 0, 200 do
        local rnd = rng(sector * 7919 + attempt * 104729 + 17)
        local cells = {}
        for k = 1, W * H do cells[k] = "ground" end
        local path = {}
        local x, y = 1, rnd(3, H - 2)
        local function add(px, py) path[#path + 1] = { px, py } end
        add(x, y)
        -- Monotone in x: horizontal runs joined by vertical runs, so the path never touches itself.
        local turns = 0
        while x < W - 1 do
            local run = min(W - 1 - x, rnd(2, 4))
            for _ = 1, run do x = x + 1; add(x, y) end
            if x >= W - 1 then break end
            local ny
            repeat ny = rnd(2, H - 1) until abs(ny - y) >= 3
            local s = ny > y and 1 or -1
            while y ~= ny do y = y + s; add(x, y) end
            turns = turns + 1
        end
        if #path >= 50 and turns >= 4 then
            for _, p in ipairs(path) do cells[idx(p[1], p[2])] = "path" end
            cells[idx(path[1][1], path[1][2])] = "gate"
            cells[idx(path[#path][1], path[#path][2])] = "core"
            -- Rocks: a few light blockers on ground, never next to the gate.
            local rocks = 5 + min(8, sector)
            local placed, tries = 0, 0
            while placed < rocks and tries < 400 do
                tries = tries + 1
                local rx, ry = rnd(1, W), rnd(1, H)
                local k = idx(rx, ry)
                if cells[k] == "ground" and rx > 2 then cells[k] = "rock"; placed = placed + 1 end
            end
            -- Mirror the map left-right on even sectors so the core is not always on the right.
            if sector % 2 == 0 then
                local flipped = {}
                for yy = 1, H do for xx = 1, W do flipped[idx(W + 1 - xx, yy)] = cells[idx(xx, yy)] end end
                cells = flipped
                for _, p in ipairs(path) do p[1] = W + 1 - p[1] end
            end
            return cells, path
        end
    end
    error("map generation failed for sector " .. sector)
end

------------------------------------------------------------------ waves
-- Wave n of a sector: a template by position in the sector, scaled by the global wave number.
local TEMPLATES = {
    { { "mote", 9 } },
    { { "mote", 9 }, { "dart", 5 } },
    { { "mote", 6 }, { "shade_r", 6 } },
    { { "hulk", 3 }, { "mote", 8 } },
    { { "shade_g", 6 }, { "shade_b", 6 } },
    { { "mote", 8 }, { "eclipse", 1 } },
    { { "mirrorback", 8 }, { "dart", 6 } },
    { { "splitter", 6 }, { "mote", 6 } },
    { { "dart", 18 }, { "shade_r", 4 } },
    { { "hulk", 5 }, { "shade_g", 5 }, { "shade_b", 5 } },
    { { "mirrorback", 8 }, { "splitter", 5 }, { "hulk", 3 } },
    { { "shade_r", 5 }, { "shade_g", 5 }, { "shade_b", 5 }, { "eclipse", 2 } },
}

function R.hp_scale(sector, wave)
    -- Each sector restarts the economy, so health restarts too, from a higher base.
    return 36 * (1 + 0.45 * (sector - 1)) * (1 + 0.4 * (wave - 1)) * (1.08 ^ (wave - 1))
end

function R.wave_list(sector, wave)
    local t = TEMPLATES[(wave - 1) % #TEMPLATES + 1]
    local grow = 1 + 0.25 * (sector - 1)
    local list = {}
    for _, e in ipairs(t) do
        local n = e[2]
        if e[1] ~= "eclipse" then n = floor(n * grow + 0.5) end
        list[#list + 1] = { e[1], n }
    end
    return list
end

-- Spawn order: interleave groups so a wave is a mixed stream, bosses last.
local function spawn_queue(sector, wave)
    local list = R.wave_list(sector, wave)
    local q, left, t, more = {}, {}, 0, true
    for i, e in ipairs(list) do left[i] = e[1] == "eclipse" and 0 or e[2] end
    while more do -- round-robin over the regular groups
        more = false
        for i, e in ipairs(list) do
            if left[i] > 0 then
                left[i], more = left[i] - 1, true
                q[#q + 1] = { kind = e[1], t = t }
                t = t + 0.62 / (R.ENEMIES[e[1]].speed / 1.5) ^ 0.5
            end
        end
    end
    for _, e in ipairs(list) do
        if e[1] == "eclipse" then
            for _ = 1, e[2] do t = t + 2.5; q[#q + 1] = { kind = e[1], t = t } end
        end
    end
    return q
end

------------------------------------------------------------------ game
local Game = {}
Game.__index = Game

function R.new_game(sector)
    local g = setmetatable({}, Game)
    g.sector = sector
    g.w, g.h = R.W, R.H
    g.cells, g.path = gen_map(sector)
    g.path_index = {}
    for i, p in ipairs(g.path) do g.path_index[idx(p[1], p[2])] = i end
    g.pieces = {}           -- cell index -> { kind, dir (emitter), flip (mirror: "/" or "\\"), tier, spent }
    g.energy = R.START_ENERGY + 30 * (sector - 1)
    g.core = R.CORE
    g.wave = 0              -- last wave started
    g.state = "build"       -- build (before first wave), fight, between, won, lost
    g.call_t = 0
    g.enemies, g.queue, g.qt = {}, {}, 0
    g.surge, g.surge_t = 0, 0
    g.time = 0
    g.kills, g.leaks = 0, 0
    g:retrace()
    return g
end

function Game:kind(x, y)
    if x < 1 or y < 1 or x > self.w or y > self.h then return nil end
    return self.cells[idx(x, y)]
end
function Game:piece(x, y) return self.pieces[idx(x, y)] end

function Game:can_place(kind, x, y)
    local def = R.PIECES[kind]
    if not def then return false, "no such piece" end
    if self:kind(x, y) ~= "ground" then return false, "build on open ground" end
    if self:piece(x, y) then return false, "cell taken" end
    if self.energy < def.cost then return false, "not enough energy" end
    return true
end

-- Pick the emitter facing that lights the most path cells, so a fresh emitter starts useful.
function Game:best_dir(x, y)
    local best, bd = -1, 2
    for d = 1, 4 do
        local seg, cov = self:trace({ [idx(x, y)] = { kind = "emitter", dir = d, tier = 1 } })
        local s = 0
        for k, c in pairs(cov) do if self.path_index[k] then s = s + c.w + c.r + c.g + c.b end end
        if s > best then best, bd = s, d end
    end
    return bd
end

function Game:place(kind, x, y, dir, flip)
    local ok, why = self:can_place(kind, x, y)
    if not ok then return false, why end
    local def = R.PIECES[kind]
    local p = { kind = kind, tier = 1, spent = def.cost }
    if kind == "emitter" then p.dir = dir or self:best_dir(x, y) end
    if kind == "mirror" then p.flip = flip or "/" end
    self.energy = self.energy - def.cost
    self.pieces[idx(x, y)] = p
    self:retrace()
    return true
end

function Game:rotate(x, y)
    local p = self:piece(x, y)
    if not p then return false end
    if p.kind == "emitter" then p.dir = p.dir % 4 + 1
    elseif p.kind == "mirror" then p.flip = p.flip == "/" and "\\" or "/"
    else return false end
    self:retrace()
    return true
end

function Game:upgrade_cost(x, y)
    local p = self:piece(x, y)
    if not p or p.kind ~= "emitter" or p.tier >= 3 then return nil end
    return R.UPGRADE_COST[p.tier]
end

function Game:upgrade(x, y)
    local c = self:upgrade_cost(x, y)
    if not c then return false, "nothing to upgrade" end
    if self.energy < c then return false, "not enough energy" end
    local p = self:piece(x, y)
    self.energy = self.energy - c
    p.tier, p.spent = p.tier + 1, p.spent + c
    self:retrace()
    return true
end

function Game:sell_value(x, y)
    local p = self:piece(x, y)
    return p and floor(p.spent * R.SELL_BACK) or 0
end

function Game:sell(x, y)
    local p = self:piece(x, y)
    if not p then return false end
    local v = self:sell_value(x, y)
    self.energy = self.energy + v
    self.pieces[idx(x, y)] = nil
    self:retrace()
    return v
end

------------------------------------------------------------------ light
-- Trace every emitter's light. Returns segments (cell-space centres, for drawing) and coverage:
-- cell index -> { w, r, g, b } light power crossing that cell. extra overrides pieces (previews).
function Game:trace(extra)
    local pieces = self.pieces
    local function piece_at(k)
        if extra and extra[k] ~= nil then return extra[k] or nil end
        return pieces[k]
    end
    local segs, cov = {}, {}
    local W, H, cells = self.w, self.h, self.cells
    local function add_cov(k, col, pw)
        local c = cov[k]
        if not c then c = { w = 0, r = 0, g = 0, b = 0 }; cov[k] = c end
        c[col] = c[col] + pw
    end
    local emit = {}
    for k = 1, W * H do
        local p = piece_at(k)
        if p and p.kind == "emitter" then emit[#emit + 1] = k end
    end
    for _, ek in ipairs(emit) do
        local p = piece_at(ek)
        local ex, ey = (ek - 1) % W + 1, floor((ek - 1) / W) + 1
        local budget = R.MAX_BEAM
        local seen = {}
        local stack = { { x = ex, y = ey, d = p.dir, col = "w", pw = R.EMITTER_POWER[p.tier], depth = 0 } }
        while #stack > 0 do
            local b = table.remove(stack)
            local dx, dy = DIRS[b.d][1], DIRS[b.d][2]
            local sx, sy = b.x, b.y
            local x, y = b.x, b.y
            local ended = false
            while not ended do
                local nx, ny = x + dx, y + dy
                local k = (nx >= 1 and ny >= 1 and nx <= W and ny <= H) and idx(nx, ny) or nil
                local kind = k and cells[k]
                local q = k and piece_at(k)
                if budget <= 0 or not k or kind == "rock" or kind == "core" or kind == "gate" or (q and q.kind == "emitter") then
                    segs[#segs + 1] = { sx, sy, x + dx * 0.5, y + dy * 0.5, b.col, b.pw }
                    ended = true
                else
                    budget = budget - 1
                    x, y = nx, ny
                    add_cov(k, b.col, b.pw)
                    local key = k * 64 + b.d * 8 + (b.col == "w" and 0 or b.col == "r" and 1 or b.col == "g" and 2 or 3)
                    if seen[key] then
                        segs[#segs + 1] = { sx, sy, x, y, b.col, b.pw }
                        ended = true
                    elseif q then
                        seen[key] = true
                        if q.kind == "mirror" then
                            segs[#segs + 1] = { sx, sy, x, y, b.col, b.pw }
                            local ndx, ndy
                            if q.flip == "/" then ndx, ndy = -dy, -dx else ndx, ndy = dy, dx end
                            stack[#stack + 1] = { x = x, y = y, d = dir_index(ndx, ndy), col = b.col, pw = b.pw, depth = b.depth + 1 }
                            ended = true
                        elseif q.kind == "prism" and b.col == "w" then
                            segs[#segs + 1] = { sx, sy, x, y, b.col, b.pw }
                            local pw = b.pw * R.PRISM_SPLIT
                            local left, right = (b.d + 2) % 4 + 1, b.d % 4 + 1
                            stack[#stack + 1] = { x = x, y = y, d = left, col = "r", pw = pw, depth = b.depth + 1 }
                            stack[#stack + 1] = { x = x, y = y, d = b.d, col = "g", pw = pw, depth = b.depth + 1 }
                            stack[#stack + 1] = { x = x, y = y, d = right, col = "b", pw = pw, depth = b.depth + 1 }
                            ended = true
                        elseif q.kind == "lens" then
                            segs[#segs + 1] = { sx, sy, x, y, b.col, b.pw }
                            stack[#stack + 1] = { x = x, y = y, d = b.d, col = b.col, pw = b.pw * R.LENS_GAIN, depth = b.depth + 1 }
                            ended = true
                        end
                    end
                end
            end
        end
    end
    return segs, cov
end

function Game:retrace()
    self.segs, self.cov = self:trace()
end

-- Damage per second an enemy of this kind would take standing in cell k (surge excluded).
function Game:dps_at(k, kind, shield)
    local c = self.cov[k]
    if not c then return 0 end
    local m = R.ENEMIES[kind].mult
    if shield then -- eclipse: the current shield colour takes full damage
        local s = 0
        for _, col in ipairs(R.COLORS) do s = s + c[col] * (col == shield and 1.6 or m[col]) end
        return s
    end
    return c.w * m.w + c.r * m.r + c.g * m.g + c.b * m.b
end

------------------------------------------------------------------ waves and enemies
function Game:can_call() return self.state == "build" or self.state == "between" end

function Game:call_bonus()
    if self.state ~= "between" then return 0 end
    return floor(self.call_t * 1.5)
end

function Game:start_wave()
    if not self:can_call() then return false end
    local bonus = self:call_bonus()
    self.energy = self.energy + bonus
    self.wave = self.wave + 1
    self.queue, self.qt = spawn_queue(self.sector, self.wave), 0
    self.state = "fight"
    return true, bonus
end

function Game:next_wave_list()
    if self.wave >= R.WAVES then return nil end
    return R.wave_list(self.sector, self.wave + 1)
end

function Game:pos(e)
    -- Path position (cells, 1-based, fractional) -> cell-space point.
    local path = self.path
    local i = floor(e.d)
    local f = e.d - i
    local a = path[max(1, min(#path, i))]
    local b = path[max(1, min(#path, i + 1))]
    return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
end

local function spawn(self, kind, d, hp_frac)
    local def = R.ENEMIES[kind]
    local hp = R.hp_scale(self.sector, self.wave) * def.hp * (hp_frac or 1)
    local e = { kind = kind, d = d or 1, hp = hp, max = hp, hit = 0, id = (self.next_id or 0) + 1, age = 0 }
    self.next_id = e.id
    return e
end

function Game:surge_ready() return self.surge >= 100 and self.surge_t <= 0 and self.state == "fight" end
function Game:fire_surge()
    if not self:surge_ready() then return false end
    self.surge, self.surge_t = 0, R.SURGE_TIME
    return true
end

function R.shield_of(e)
    local def = R.ENEMIES[e.kind]
    if def.cycle then return R.COLORS[2 + floor(e.age / def.cycle) % 3] end
    return def.shield
end

-- Advance the simulation. Returns events: { kind = "kill"|"leak"|"spawn"|"wave_done"|"won"|"lost", ... }.
function Game:update(dt)
    local ev = {}
    if self.state == "won" or self.state == "lost" then return ev end
    self.time = self.time + dt
    if self.surge_t > 0 then self.surge_t = max(0, self.surge_t - dt) end
    local mult = self.surge_t > 0 and R.SURGE_MULT or 1
    if self.state == "between" then
        self.call_t = self.call_t - dt
        if self.call_t <= 0 then
            self.call_t = 0
            self:start_wave()
            ev[#ev + 1] = { kind = "auto_wave", wave = self.wave }
        end
    end
    if self.state == "fight" then
        self.qt = self.qt + dt
        while self.queue[1] and self.queue[1].t <= self.qt do
            local s = table.remove(self.queue, 1)
            local e = spawn(self, s.kind, 1)
            self.enemies[#self.enemies + 1] = e
            ev[#ev + 1] = { kind = "spawn", enemy = e }
        end
    end
    local n = #self.path
    local alive = {}
    for _, e in ipairs(self.enemies) do
        local def = R.ENEMIES[e.kind]
        e.age = e.age + dt
        e.d = e.d + def.speed * dt
        local k = self.path[min(n, floor(e.d + 0.5))]
        local dmg = 0
        if k then
            dmg = self:dps_at(idx(k[1], k[2]), e.kind, def.cycle and R.shield_of(e)) * mult * dt
        end
        e.hit = dmg > 0 and 0.12 or max(0, e.hit - dt)
        e.hp = e.hp - dmg
        if e.hp <= 0 then
            local reward = def.reward + floor(self.sector / 2)
            self.energy = self.energy + reward
            self.kills = self.kills + 1
            if self.surge_t <= 0 then self.surge = min(100, self.surge + (def.cycle and 30 or 3)) end
            local x, y = self:pos(e)
            ev[#ev + 1] = { kind = "kill", enemy = e, x = x, y = y, reward = reward }
            if def.split then
                for j = 1, def.split do
                    local c = spawn(self, "mote", max(1, e.d - 0.35 * j), 0.45)
                    alive[#alive + 1] = c
                end
            end
        elseif e.d >= n then
            self.core = max(0, self.core - def.leak)
            self.leaks = self.leaks + 1
            ev[#ev + 1] = { kind = "leak", enemy = e, amount = def.leak }
        else
            alive[#alive + 1] = e
        end
    end
    self.enemies = alive
    if self.core <= 0 then
        self.state = "lost"
        ev[#ev + 1] = { kind = "lost" }
    elseif self.state == "fight" and #self.queue == 0 and #self.enemies == 0 then
        local bonus = 20 + 4 * self.wave
        self.energy = self.energy + bonus
        ev[#ev + 1] = { kind = "wave_done", wave = self.wave, bonus = bonus }
        if self.wave >= R.WAVES then
            self.state = "won"
            ev[#ev + 1] = { kind = "won" }
        else
            self.state, self.call_t = "between", R.CALL_TIME
        end
    end
    return ev
end

return R
