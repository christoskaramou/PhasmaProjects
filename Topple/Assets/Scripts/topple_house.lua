-- Topple's House: eight rooms, each a chapter of three levels (easy, normal, hard) that unlocks a tool. Pure Lua
-- (no engine calls): the room list, the stars earned, what is open and unlocked, and the save as text.
-- A level is cleared once a run met its requirement (Start to End), with or without a star; its stars are the
-- challenges done (each once earned, kept). Room N opens when room N-1's level 1 is cleared (the first is always open);
-- a room's tool unlocks, and the room opens for free building, when its own level 1 is cleared. The living room is
-- always open to build in. A def without challenges (old style) keeps 1-3 stars by count instead.
local H = {}

-- plan: the room's cell on the house map's floor plan (x, y, w, h on a 16 x 9 grid; the attic is the strip upstairs).
-- unlocks: tools (ids of the Free Build tray, "grow" the GROW switch) and sizes (indexes into F.SIZES).
H.ROOMS = {
    { id = "hall", name = "Hallway", unlocks = { tools = { "draw" } }, plan = { 0, 6, 4, 3 } },
    { id = "living", name = "Living Room", unlocks = { tools = { "line" } }, plan = { 4, 6, 7, 3 } },
    { id = "kitchen", name = "Kitchen", unlocks = { tools = { "ramp" } }, plan = { 0, 2.6, 5, 3.4 } },
    { id = "dining", name = "Dining Room", unlocks = { sizes = { 1 } }, plan = { 5, 2.6, 6, 3.4 } },
    { id = "kids", name = "Kids' Room", unlocks = { tools = { "ball" } }, plan = { 11, 2.6, 5, 3.4 } },
    { id = "bath", name = "Bathroom", unlocks = { tools = { "switch" } }, plan = { 11, 6, 5, 1.5 } },
    { id = "study", name = "Study", unlocks = { tools = { "grow" }, sizes = { 3, 4, 5 } }, plan = { 11, 7.5, 5, 1.5 } },
    { id = "attic", name = "Attic", unlocks = { tools = { "swing", "field", "spiral" } }, plan = { 0, 0, 16, 2.2 } },
}
H.BY_ID = {}
for i, r in ipairs(H.ROOMS) do r.n = i; H.BY_ID[r.id] = r end
H.FREE_ALWAYS = "living"                 -- the user's own build lives here, so it never locks
H.BASE_TOOLS = { erase = true, start = true }
H.BASE_SIZES = { [2] = true }            -- Standard
H.TIERS = { "EASY", "NORMAL", "HARD" }
H.SAVE_HEADER = "TOPPLE-HOUSE 2"
H.OLD_HEADER = "TOPPLE-HOUSE 1"         -- (best stars per level: migrated on load)

-- What unlocks a tool or a size: the room, or nil (always there, or nothing does).
function H.unlocker(tool)
    for _, r in ipairs(H.ROOMS) do
        for _, t in ipairs(r.unlocks.tools or {}) do if t == tool then return r end end
    end
end
function H.size_unlocker(i)
    for _, r in ipairs(H.ROOMS) do
        for _, s in ipairs(r.unlocks.sizes or {}) do if s == i then return r end end
    end
end

-- The challenge defs, sorted into rooms by def.room and def.tier. maps: the challenge module's MAPS (any map's list
-- may hold room challenges). A def in the old living-room list with no room is the living room's, in list order.
function H.sort_defs(maps)
    local by = {}
    for _, r in ipairs(H.ROOMS) do by[r.id] = {} end
    local keys = {}
    for k in pairs(maps or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        for i, def in ipairs(maps[k].list or {}) do
            local room = def.room or (k == "room" and "living") or nil
            local tier = def.tier or (not def.room and k == "room" and i) or nil
            if room and by[room] and tier and tier >= 1 and tier <= 3 and not by[room][tier] then by[room][tier] = def end
        end
    end
    return by
end

local House = {}
House.__index = House

function H.new(maps)
    local self = setmetatable({ best = {}, all = false }, House)
    self:set_defs(maps)
    return self
end

function House:set_defs(maps)
    self.defs = H.sort_defs(maps)
    self.by_id = {}
    for _, tiers in pairs(self.defs) do for k = 1, 3 do if tiers[k] then self.by_id[tiers[k].id] = tiers[k] end end end
    for id, e in pairs(self.best) do e.stars = self:stars_for(id) end
end

-- { [1] = def or nil, [2] = ..., [3] = ... } for a room.
function House:tiers(id) return self.defs[id] or {} end
function House:has_challenges(id) local t = self:tiers(id); return t[1] ~= nil or t[2] ~= nil or t[3] ~= nil end

-- best[level id] = { stars, used (fewest dominoes in a run that met the requirement), done = { [challenge id] = true }
-- (nil for an old-style def: stars is its 1-3) }. A level's stars: its challenges among done.
function House:stars_for(ch_id)
    local b = self.best[ch_id]
    if not b then return 0 end
    if not b.done then return b.stars end
    local def, n = self.by_id[ch_id], 0
    if def and def.challenges then
        for _, c in ipairs(def.challenges) do if b.done[c.id] then n = n + 1 end end
    else
        for _ in pairs(b.done) do n = n + 1 end
    end
    return n
end
-- Whether a level's challenge is done (earned in some run).
function House:done(ch_id, cid) local b = self.best[ch_id]; return b ~= nil and b.done ~= nil and b.done[cid] == true end
-- An old save's n stars on a level with challenges: cleared, and its first n - 1 challenges done.
local function migrate(def, n)
    local done = {}
    for i = 1, math.min(n - 1, #def.challenges) do done[def.challenges[i].id] = true end
    return done
end
-- Stars earned in a room, out of 9.
function House:stars(id)
    local n = 0
    for k = 1, 3 do local d = self:tiers(id)[k]; if d then n = n + self:stars_for(d.id) end end
    return n
end
function House:total_stars()
    local n = 0
    for _, r in ipairs(H.ROOMS) do n = n + self:stars(r.id) end
    return n
end

-- Cleared: its level 1 has been completed (a record exists, stars or not).
function House:cleared(id)
    local easy = self:tiers(id)[1]
    return easy ~= nil and self.best[easy.id] ~= nil
end
function House:is_open(id)
    local r = H.BY_ID[id]
    if not r then return false end
    if self.all or r.n == 1 then return true end
    return self:cleared(H.ROOMS[r.n - 1].id)
end
-- Rooms you may free-build in: the living room, and every room cleared.
function House:free_open(id)
    return id == H.FREE_ALWAYS or self.all or self:cleared(id)
end
function House:free_rooms()
    local out = {}
    for _, r in ipairs(H.ROOMS) do if self:free_open(r.id) then out[#out + 1] = r.id end end
    return out
end

function House:tool_open(tool)
    if H.BASE_TOOLS[tool] or self.all then return true end
    local r = H.unlocker(tool)
    return r ~= nil and self:cleared(r.id)
end
function House:size_open(i)
    if H.BASE_SIZES[i] or self.all then return true end
    local r = H.size_unlocker(i)
    return r ~= nil and self:cleared(r.id)
end
function House:unlocked_tools()
    local out = {}
    for t in pairs(H.BASE_TOOLS) do out[#out + 1] = t end
    for _, r in ipairs(H.ROOMS) do
        for _, t in ipairs(r.unlocks.tools or {}) do if self:tool_open(t) then out[#out + 1] = t end end
    end
    table.sort(out)
    return out
end

-- Record a finished run of a level. run = { met = bool, done = { challenge ids earned } } (C.evaluate's), or a number:
-- for a level with challenges, the run its last C.won left on def.challenges.last (else read as an old save's stars);
-- for an old-style def, its 1-3 stars (0: failed). Returns better (something new to save: a first clear, a challenge,
-- fewer dominoes) and, when this clear newly opened anything, { cleared = room, opened = next room or nil }.
-- ponytail: the number form exists because the view still passes Ch.stars' count; it can pass C.evaluate's run later.
function House:record(ch_id, run, used)
    local was = {}
    for _, r in ipairs(H.ROOMS) do was[r.id] = self:cleared(r.id) end
    local def = self.by_id[ch_id]
    local p = self.best[ch_id]
    local better = false
    if type(run) == "number" and def and def.challenges then
        local l = def.challenges.last
        if l and l.id == ch_id then
            run = l
            def.challenges.last = nil
        else
            local n, done = run, {}
            if n > 0 then for cid in pairs(migrate(def, n)) do done[#done + 1] = cid end end
            run = { met = n > 0, done = done }
        end
    end
    if type(run) == "number" then
        if run > 0 and (not p or run > p.stars or (run == p.stars and used < p.used)) then
            self.best[ch_id] = { stars = run, used = used }
            better = true
        end
    elseif run.met then
        if not p or not p.done then p = { stars = 0, used = used, done = {} }; self.best[ch_id] = p; better = true end
        for _, cid in ipairs(run.done or {}) do
            if not p.done[cid] then p.done[cid] = true; better = true end
        end
        if used < p.used then p.used = used; better = true end
        p.stars = self:stars_for(ch_id)
    end
    local news
    for _, r in ipairs(H.ROOMS) do
        if self:cleared(r.id) and not was[r.id] then
            news = { cleared = r, opened = H.ROOMS[r.n + 1] }
        end
    end
    return better, news
end

-- The save: the header "TOPPLE-HOUSE 2", then one line per level cleared: "<id> <stars> <used> [<challenge id> ...]",
-- the challenges done listed (stars = how many; 0 and none: cleared without a star). An old-style def's line has no
-- ids, its stars are its 1-3. Any line that does not read as that is skipped on its own (a damaged save loses only its
-- bad lines). An old save ("TOPPLE-HOUSE 1", or the old challenges file with no header: "<id> <stars 1-3> <used>")
-- migrates: a level with challenges is cleared with its first stars - 1 challenges done.
function House:dump()
    local ids, out = {}, { H.SAVE_HEADER }
    for id in pairs(self.best) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local b = self.best[id]
        local line = id .. " " .. b.stars .. " " .. b.used
        if b.done then
            local cs = {}
            for cid in pairs(b.done) do cs[#cs + 1] = cid end
            table.sort(cs)
            line = id .. " " .. #cs .. " " .. b.used .. (#cs > 0 and " " .. table.concat(cs, " ") or "")
        end
        out[#out + 1] = line
    end
    return table.concat(out, "\n") .. "\n"
end

function House:load(text)
    self.best = {}
    local bad, v2 = 0, false
    for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        local id, stars, used, rest = line:match("^%s*([%w_%-]+)%s+(%d+)%s+(%d+)(.-)%s*$")
        stars, used = tonumber(stars), tonumber(used)
        local cids, ok = {}, id ~= nil
        for tok in (rest or ""):gmatch("%S+") do
            if tok:match("^[%w_%-]+$") then cids[#cids + 1] = tok else ok = false end
        end
        local def = id and self.by_id[id]
        local done                                   -- the challenges this line says are done (nil: old-style stars)
        if ok and v2 and #cids > 0 then
            ok = stars == #cids
            done = {}
            for _, c in ipairs(cids) do done[c] = true end
        elseif ok and #cids == 0 and stars <= 3 and (stars >= 1 or v2) then
            if def and def.challenges then done = stars > 0 and migrate(def, stars) or {}
            elseif stars == 0 then done = {} end
        else
            ok = false
        end
        if ok then
            local p = self.best[id]
            if not p then
                self.best[id] = { stars = stars, used = used, done = done }
            else
                if done then
                    p.done = p.done or {}
                    for c in pairs(done) do p.done[c] = true end
                elseif not p.done then
                    p.stars = math.max(p.stars, stars)
                end
                p.used = math.min(p.used, used)
            end
            self.best[id].stars = self:stars_for(id)
        elseif line == H.SAVE_HEADER then
            v2 = true
        elseif line:match("%S") and line ~= H.OLD_HEADER then
            bad = bad + 1
        end
    end
    return bad
end

return H
