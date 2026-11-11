-- Topple's House Challenges: each room's levels, each with a locked Start domino, a locked End domino that sets off the
-- room's goal, a budget of dominoes and gadgets, and a list of challenges worth a star each. A level is completed when
-- the chain runs from Start and the End is the last domino to fall (see "Completing a level" below). Pure Lua (no
-- engine calls); the appliance behind the goal is scenery the world brings to life.
-- opts (optional): { read = function(path) -> text or nil }, path relative to Assets (default: the engine's fs.read, or
-- io from the Topple folder when run under luajit).
return function(F, opts)
local C = {}

-- The House's rooms in order. Each room's three levels (easy, normal, hard) live in
-- Scripts/challenges/<room id>.lua, which returns a list of 3 defs (format: see "A def" below). A room with no file
-- yet simply has no levels.
C.ROOM_IDS = { "hall", "living", "kitchen", "dining", "kids", "bath", "study", "attic" }
C.ROOM_NAMES = { hall = "Hallway", living = "Living Room", kitchen = "Kitchen", dining = "Dining Room", kids = "Kids' Room",
    bath = "Bathroom", study = "Study", attic = "Attic" }
-- The map each room's list is filed under in C.MAPS: the living room keeps the old map id "room"; the hallway cannot
-- be "hall" (that is the Great Hall's), so it is "hallway"; the others are their room ids.
C.MAP_OF = { hall = "hallway", living = "room" }
function C.map_of(room) return C.MAP_OF[room] or room end

local function read_text(path)
    if opts and opts.read then return opts.read(path) end
    local fs_ = rawget(_G, "fs") or fs
    if fs_ and fs_.read then
        local ok, s = pcall(fs_.read, path)
        if ok and s then return s end
    end
    local io_ = rawget(_G, "io")
    if io_ and io_.open then
        local f = io_.open("Assets/" .. path, "rb")
        if f then local s = f:read("*a"); f:close(); return s end
    end
    return nil
end

-- One room's defs from its file (nil if there is none). Each def gets room and tier from its place if it has none.
local function load_room_defs(id)
    local path = "Scripts/challenges/" .. id .. ".lua"
    local src = read_text(path)
    if not src then return nil end
    local chunk, err = (rawget(_G, "loadstring") or load)(src, "@" .. path)
    local ok, list = false, err
    if chunk then ok, list = pcall(chunk) end
    if not ok or type(list) ~= "table" then
        print("[Topple] The challenges of " .. id .. " did not load: " .. tostring(list))
        return nil
    end
    for i, def in ipairs(list) do
        def.room = def.room or id
        def.tier = def.tier or i
        def.finish = def.finish or list.finish          -- the room's End and goal, unless the level has its own
        def.goal = def.goal or list.goal
    end
    return list
end

-- The kinds of challenge a level lists (see "A def" below). Each: a default name, a brief from the entry, and
-- test(c, run) (run: see C.evaluate). A level may give its own name and brief; kind "custom" brings its own test(run).
local GADGET_WORD = { ball = "a ball", swing = "a swing", switch = "a switch of your own", ramp = "a ramp", mini = "a Mini" }
local function gadget_used(g, run)
    local b, res = run.board, run.res
    if g == "ball" then return res.balls_launched > 0
    elseif g == "swing" then return res.swings_released > 0
    elseif g == "ramp" then return b.ramp_count > 0
    elseif g == "switch" then
        for _, e in ipairs(res.switches) do if e.id ~= b.goal_id then return true end end
        return false
    elseif g == "mini" then
        for _, p in pairs(b.pieces) do if not p.fixed and not p.preset and p.s == F.SIZES[1] then return true end end
        return false
    end
    error("no gadget " .. tostring(g))
end
local function placed(g, b)
    if g == "ball" then return b.ball_count elseif g == "swing" then return b.swing_count
    elseif g == "ramp" then return b.ramp_count elseif g == "switch" then return b.switch_count - (b.goal_id and 1 or 0) end
    local n = 0
    for _, p in pairs(b.pieces) do if not p.fixed and not p.preset and p.s == F.SIZES[1] then n = n + 1 end end
    return n
end
-- Whether one of the player's own dominoes (fallen, if fell) stands in box { x0, x1, y0, y1 [, z0, z1] }.
local function in_box(B, run, fell)
    for id, p in pairs(run.board.pieces) do
        if not p.fixed and not p.preset and p.x >= B[1] and p.x <= B[2] and p.y >= B[3] and p.y <= B[4]
            and (not B[5] or (p.z >= B[5] and p.z <= B[6])) and (not fell or run.res.falls[id]) then return true end
    end
    return false
end
C.KINDS = {
    thrift = { name = "Thrifty", brief = function(c) return "Use " .. c.n .. " dominoes or fewer." end,
        test = function(c, run) return run.used <= c.n end },
    time = { name = "Against the Clock", brief = function(c) return "Reach the End within " .. c.t .. " seconds." end,
        test = function(c, run) return run.t_end <= c.t end },
    all_fall = { name = "Not One Standing", brief = function() return "Every domino falls." end,
        test = function(_, run)
            for id, p in pairs(run.board.pieces) do if not p.preset and not run.res.falls[id] then return false end end
            return true
        end },
    standing = { name = "Still Standing", brief = function(c) return "Leave the " .. c.trap .. " standing." end,
        test = function(c, run) return not run.trap_events[c.trap .. ":collapse"] end },
    trap = { name = "Set It Off", brief = function(c) return "Set off the " .. c.trap .. "." end,
        test = function(c, run) return run.trap_events[c.trap .. ":" .. (c.event or "any")] == true end },
    without = { name = "Do Without", brief = function(c) return "Do it without " .. GADGET_WORD[c.gadget] .. "." end,
        test = function(c, run) return placed(c.gadget, run.board) == 0 end },
    with = { name = "Gadgeteer", brief = function(c) return "Use " .. GADGET_WORD[c.gadget] .. " on the way." end,
        test = function(c, run) return gadget_used(c.gadget, run) end },
    via = { name = "The Scenic Route", brief = function(c) return "Take the chain by way of the " .. c.what .. "." end,
        test = function(c, run) return in_box(c.box, run, true) end },
    avoid = { name = "Keep Off", brief = function(c) return "Keep every domino off the " .. c.what .. "." end,
        test = function(c, run) return not in_box(c.box, run, false) end },
    no_dive = { name = "Mind the Edge", brief = function() return "No domino falls off an edge." end,
        test = function(_, run)
            for _, f in pairs(run.res.falls) do if f.dive then return false end end
            return true
        end },
}
-- A level's challenges, each made whole: { id, name, brief, test = function(run) -> true if earned, kind, ... }. The
-- id defaults to the kind (with the trap or gadget for those that name one). The old 1-3 star thresholds (def.stars)
-- are kept, from the thrift challenge, only for the old cards that still read them.
local function normalize(def)
    local thrift
    for _, c in ipairs(def.challenges or {}) do
        local K = c.kind and C.KINDS[c.kind]
        assert(K or (c.kind == "custom" and c.test), tostring(def.id) .. ": a challenge of no known kind, " .. tostring(c.kind))
        if K then
            c.id = c.id or (c.trap and c.kind .. "_" .. c.trap:gsub("%W+", "_")) or (c.gadget and c.kind .. "_" .. c.gadget) or c.kind
            c.name = c.name or K.name
            c.brief = c.brief or K.brief(c)
            local test = K.test
            c.test = function(run) return test(c, run) end
        end
        if c.kind == "thrift" then thrift = c.n end
    end
    if def.challenges and not def.stars then def.stars = { thrift or def.budget.domino, thrift or def.budget.domino } end
    return def
end
C.normalize = normalize
-- Listed per map, so a map's challenges live together: the Great Hall (none), then each House room with a file.
C.MAPS = { hall = { name = "The Great Hall", list = {} } }
C.HOUSE = {}            -- room id -> its list of defs (only rooms with a file)
for _, id in ipairs(C.ROOM_IDS) do
    local list = load_room_defs(id)
    for _, def in ipairs(list or {}) do normalize(def) end
    if list then
        C.HOUSE[id] = list
        C.MAPS[C.map_of(id)] = { name = "The " .. C.ROOM_NAMES[id], list = list, room = id }
    end
end
C.MAPS.room = C.MAPS.room or { name = "The Living Room", list = {}, room = "living" }

-- Global challenges count on any map. Each tests one run's stats, and only a run you built yourself counts:
-- own, fallen, total, duration (s), balls (launched), swings (released), switches (pressed, goals aside), ramp, stars.
local function fell(n) return function(s) return s.fallen >= n end end
C.GLOBAL = {
    { id = "fell_25", name = "First Steps", brief = "Topple 25 dominoes in one run.", test = fell(25) },
    { id = "fell_100", name = "A Good Hundred", brief = "Topple 100 dominoes in one run.", test = fell(100) },
    { id = "fell_500", name = "Five Hundred Down", brief = "Topple 500 dominoes in one run.", test = fell(500) },
    { id = "fell_1000", name = "The Thousand", brief = "Topple 1,000 dominoes in one run.", test = fell(1000) },
    { id = "fell_5000", name = "Boxes and Boxes", brief = "Topple 5,000 dominoes in one run.", test = fell(5000) },
    { id = "fell_100k", name = "A Small City", brief = "Topple 100,000 dominoes in one run.", test = fell(100000), needs = "hall" },
    { id = "clean_50", name = "Not One Left", brief = "A run of 50 or more where every domino falls.", test = function(s) return s.total >= 50 and s.fallen == s.total end },
    { id = "clean_500", name = "Perfectionist", brief = "A run of 500 or more where every domino falls.", test = function(s) return s.total >= 500 and s.fallen == s.total end },
    { id = "long_30", name = "Slow Burn", brief = "Keep a chain running for 30 seconds.", test = function(s) return s.duration >= 30 end },
    { id = "fast_100", name = "Blink and Miss It", brief = "Topple 100 dominoes in under 3 seconds.", test = function(s) return s.fallen >= 100 and s.duration < 3 end },
    { id = "ball", name = "On a Roll", brief = "Send a ball rolling with a falling domino.", test = function(s) return s.balls > 0 end, needs = "room" },
    { id = "swing", name = "Let It Swing", brief = "Release a swing in a run.", test = function(s) return s.swings > 0 end, needs = "room" },
    { id = "switch", name = "Remote Control", brief = "Set off a switch of your own in a run.", test = function(s) return s.switches > 0 end, needs = "room" },
    { id = "ramp", name = "Going Up", brief = "Run a chain of 20 or more with a ramp in the room.", test = function(s) return s.ramp and s.fallen >= 20 end, needs = "room" },
    { id = "contraption", name = "The Contraption", brief = "A ball, a swing and a switch, all in one run.", test = function(s) return s.balls > 0 and s.swings > 0 and s.switches > 0 end, needs = "room" },
    { id = "three_stars", name = "Gold Standard", brief = "Earn three stars on a House Challenge.", test = function(s) return s.stars == 3 end, needs = "room" },
}
C.global_done = {}

-- Which global challenges this run newly completes (and remembers them).
function C.award(stats)
    local new = {}
    if not stats.own then return new end
    for _, g in ipairs(C.GLOBAL) do
        if not C.global_done[g.id] and g.test(stats) then
            C.global_done[g.id] = true
            new[#new + 1] = g
        end
    end
    return new
end

-- What a map's list shows: its own challenges and the shared set; here = false if the goal can't be done on this map
-- (it needs tools or challenges another map has).
function C.for_map(map)
    local shared = {}
    for _, g in ipairs(C.GLOBAL) do
        shared[#shared + 1] = { g = g, done = C.global_done[g.id] == true, here = g.needs == nil or g.needs == map }
    end
    local m = C.MAPS[map] or { name = map, list = {} }
    return { name = m.name, own = m.list, shared = shared }
end

function C.global_count()
    local n = 0
    for _, g in ipairs(C.GLOBAL) do if C.global_done[g.id] then n = n + 1 end end
    return n
end

function C.load_global(text)
    C.global_done = {}
    for id in (text or ""):gmatch("%S+") do C.global_done[id] = true end
end

function C.dump_global()
    local out = {}
    for _, g in ipairs(C.GLOBAL) do if C.global_done[g.id] then out[#out + 1] = g.id end end
    return table.concat(out, "\n") .. "\n"
end

-- A def by map and id, or by id alone (C.find(id)) across every map.
function C.find(map, id)
    if id == nil then map, id = nil, map end
    for k, m in pairs(C.MAPS) do
        if map == nil or k == map then
            for _, def in ipairs(m.list) do if def.id == id then return def end end
        end
    end
end

-- A map is a room; a level (a def) is one of its boards. Scripts/challenges/<room>.lua returns the room's three levels
-- in order (level 1, 2, 3), and may carry, as fields of that list, the room's End that every level shares:
--   finish = { x, y, h, a [, s] }: the End, a locked domino (s: a scale) whose fall sets off the goal behind it, or
--     finish = { preset = "<preset id>" }: the End is that preset domino (the study's dictionary)
--   goal = { x, y, h } or { preset = "<preset id>" }: the goal object the End sets off (see goal below)
-- A level that gives its own finish or goal uses it instead.
--
-- Completing a level (the requirement, worth no star): the chain begins at Start, its first domino, and the LAST
-- domino to fall in the run is the End. Met when the Start domino is the first to fall, the End falls, and no domino
-- falls after the End (by the time each starts to fall; one that dives off an edge, by when it lands; a domino lost
-- with a collapsing support, by when it is lost), all within C.TIE seconds. Dominoes left standing do not matter.
-- A level is cleared (its room and tool unlocks) once the requirement has been met, with or without a star.
-- Stars: one per challenge; a challenge counts only in a run that met the requirement; once earned it stays.
--
-- A def (one level):
--   id: unique across the House (progress is saved by it); name, brief (one line: the idea), goal_word, win, fail
--   room = "<room id>", tier = 1|2|3 (the level; both default to the file and the place in its list)
--   unlock = "<tool id>" on level 1: what clearing the room gives ("mini" for the dining room's size); shown only
--   icon (optional): Textures/icon_<icon>.png; camera (optional): { x, y, h, yaw, pitch, dist } to open on
--   start = { x, y, h, a [, s] }: Start, the locked first domino (s: a scale for another size); the tip pushes it along a
--   finish: the End (above; normally the room's). board.end_piece is its piece id.
--   goal = { x, y, h }: a locked switch behind the End (board.goal_id is its id), or
--     goal = { preset = "<preset id>" }: tip that preset (board.goal_piece is its id, board.goal_id is nil)
--   budget = { domino = n [, ball, swing, switch, ramp] }: the player's own (Start and End are free)
--   challenges = { c1, c2, ... }: level 1 has 2, level 2 has 3, level 3 has 4; each is worth one star. An entry is
--     { kind = "<kind>", <its fields> [, id, name, brief] } and comes out as { id, name, brief, test = function(run) }:
--       thrift   n       use n dominoes or fewer (your own, as C.used)
--       time     t       the End falls within t seconds of the tip
--       all_fall         every domino that is not a preset falls (none left standing, none lost)
--       standing trap    the support named trap (its id) does not collapse
--       trap     trap [, event]  the trap named trap has an event (any, or this one: cut, drop, fall, open, collapse)
--       without  gadget  none of: "ball", "swing", "switch" (your own), "ramp", "mini" (a Mini domino) placed
--       with     gadget  that gadget used: a ball launched, a swing released, a switch of your own pressed, a ramp
--                        placed, a Mini placed
--       via      box, what  one of your dominoes in box { x0, x1, y0, y1 [, z0, z1] } falls ("by way of the <what>")
--       avoid    box, what  none of your dominoes stands in that box ("keep off the <what>")
--       no_dive          no domino falls off an edge
--       custom   test    test = function(run) -> true if earned (name and brief required)
--     The id defaults to the kind; for trap and standing "<kind>_<trap>" (other than letters, digits and _ as _), for
--     with and without "<kind>_<gadget>" ("without_switch"). Ids and kinds are unique within a level.
--   stars = { a, b } (old: 1-3 stars by domino count). A def without challenges still works that way (a level with no
--     End: won when the goal goes off). A def with challenges gets stars = { thrift n, thrift n } only for old cards.
--   props (optional): solid boxes { name, x0, x1, y0, y1, z0, z1 } only this challenge has
--   tools = { "draw", "line", ... }: the tools allowed besides erase (nil: every tool). C.allows(board, tool).
--   sizes = { 1, 2 }: indexes into F.SIZES the player may use (default { 2 }, Standard). C.allows_size(board, i).
--   preset = { ... }: fixed dominoes, each { x, y, h, a, size = i (F.SIZES index, default 2), paint, id = "<name>" }, or
--     lines, each { line = { x0, y0, x1, y1 }, h, size, paint }. They may stand on a support, cannot be removed and do
--     not count against the budget.
--   traps = { ... }: trap specs installed with board:add_trap (see the trap section of topple_free.lua).
-- The board also keeps def, room, tier and preset_ids (preset id -> piece id). The room must be set (F.set_room) to
-- the def's room before C.new_board.
C.DEFAULT_SIZES = { 2 }

-- A challenge's board: the traps and presets in place, the first domino and the goal locked, and the limits the
-- budget plus those two.
function C.new_board(def)
    local b = F.new_board()
    b.props = def.props
    b.def, b.room, b.tier = def, def.room, def.tier
    for _, tr in ipairs(def.traps or {}) do b:add_trap(tr) end
    b:check_traps()
    b.preset_ids = {}
    for i, pr in ipairs(def.preset or {}) do
        local k = pr.s or F.SIZES[pr.size or 2]
        local what = def.id .. ": preset " .. (pr.id or i)
        if pr.line then
            local l = pr.line
            local spots = F.line_spots(l.x0 or l[1], l.y0 or l[2], l.x1 or l[3], l.y1 or l[4], k)
            for _, sp in ipairs(spots) do
                assert(b:place_preset(sp.x, sp.y, sp.a, pr.h, pr.paint or "cream", k), what .. " does not fit")
            end
        else
            local p = assert(b:place_preset(pr.x, pr.y, pr.a or 0, pr.h, pr.paint or "cream", k), what .. " does not fit")
            if pr.id then b.preset_ids[pr.id] = p.id end
        end
    end
    local s, g = def.start, def.goal
    b._installing = true            -- (the locked pieces may stand on a support too)
    local first = assert(b:place(s.x, s.y, s.a, s.h, "brick", s.s), def.id .. ": the first domino does not fit")
    first.fixed = true
    b.start = { id = first.id, dir = 1 }
    b.start_piece = first.id        -- (Start for the requirement: board.start may be moved, this may not)
    if g.preset then
        b.goal_piece = assert(b.preset_ids[g.preset], def.id .. ": the goal names no preset " .. tostring(g.preset))
    else
        local goal = assert(b:place_switch(g.x, g.y, g.h), def.id .. ": the goal does not fit")
        goal.fixed, goal.goal = true, def.id
        b.goal_id = goal.id
    end
    -- The End: a locked domino (or a preset), counted like Start, outside the player's budget.
    b.locked_count = 1
    local e = def.finish
    if e and e.preset then
        b.end_piece = assert(b.preset_ids[e.preset], def.id .. ": the End names no preset " .. tostring(e.preset))
    elseif e then
        local p = assert(b:place(e.x, e.y, e.a, e.h, "brick", e.s), def.id .. ": the End domino does not fit")
        p.fixed = true
        b.end_piece = p.id
        b.locked_count = 2
    end
    b._installing = nil
    local u = def.budget
    b.limits = { domino = (u.domino or 0) + b.locked_count, ball = u.ball or 0, swing = u.swing or 0, switch = (u.switch or 0) + 1, ramp = u.ramp or 0 }
    b.rev = b.rev + 1
    return b
end

function C.used(board) return board.count - (board.locked_count or 1) - board.preset_count end

-- The requirement (see "Completing a level" above). Returns met and, when not, why: "start" (Start did not fall
-- first), "end" (the End never fell), "after" (a domino fell after the End). A board with no End: the goal went off.
C.TIE = 0.01
function C.requirement(board, res)
    if not board.end_piece then
        if board.goal_piece then return res.falls[board.goal_piece] ~= nil, "end" end
        for _, e in ipairs(res.switches) do if e.id == board.goal_id then return true end end
        return false, "end"
    end
    local s = res.falls[board.start_piece]
    if not s then return false, "start" end
    for _, f in pairs(res.falls) do if f.t < s.t - C.TIE then return false, "start" end end
    local e = res.falls[board.end_piece]
    if not e then return false, "end" end
    local te = e.t + C.TIE
    for id, f in pairs(res.falls) do
        if id ~= board.end_piece and (f.t > te or (f.dive and f.dive.t1 > te)) then return false, "after" end
    end
    for _, l in ipairs(res.lost) do if l.t > te then return false, "after" end end
    return true
end

-- One run judged: the ids of the level's challenges it earned (in the level's order; none unless the requirement was
-- met), met, and the run table the tests see:
--   { board, res, def, met, used (C.used), t_end (when the End fell; nil without), trap_events = { ["<trap id>:<event>"]
--     = true, ["<trap id>:any"] = true } }
function C.evaluate(board, res)
    local def = board.def or {}
    local met, why = C.requirement(board, res)
    local ef = board.end_piece and res.falls[board.end_piece]
    local run = { board = board, res = res, def = def, met = met, why = why, used = C.used(board), t_end = ef and ef.t, trap_events = {} }
    for _, e in ipairs(res.traps or {}) do
        run.trap_events[e.id .. ":" .. e.event] = true
        run.trap_events[e.id .. ":any"] = true
    end
    local done = {}
    if met then
        for _, c in ipairs(def.challenges or {}) do if c.test(run) then done[#done + 1] = c.id end end
    end
    return done, met, run
end

-- Won (the requirement met). For a level with challenges it also leaves this run's result where C.stars and the
-- House's record (called with only a star count) find it: def.challenges.last = { id, met, done }.
-- ponytail: a hand-off through the def, because the view passes record only a number; once the view passes
-- C.evaluate's result to House:record itself, this can go.
function C.won(board, res)
    local done, met = C.evaluate(board, res)
    local def = board.def
    if def and def.challenges then def.challenges.last = { id = def.id, met = met, done = done } end
    return met
end

-- Whether the player may use this tool here (board or def; erase always, everything outside a challenge).
function C.allows(board, tool)
    local def = board.def or (board.budget and board)
    if tool == "erase" or not def or not def.tools then return true end
    for _, t in ipairs(def.tools) do if t == tool then return true end end
    return false
end

-- Whether the player may use size i (an index into F.SIZES) here (board or def; every size outside a challenge).
function C.allows_size(board, i)
    local def = board.def or (board.budget and board)
    if not def then return F.SIZES[i] ~= nil end
    for _, s in ipairs(def.sizes or C.DEFAULT_SIZES) do if s == i then return true end end
    return false
end

-- Stars this run: for a level with challenges, how many it earned (from the last C.won on its board); for an old def,
-- 1-3 by domino count.
function C.stars(def, used, won)
    if not won then return 0 end
    if def.challenges then
        local l = def.challenges.last
        return l and l.id == def.id and l.met and #l.done or 0
    end
    return used <= def.stars[2] and 3 or used <= def.stars[1] and 2 or 1
end

-- Stars held on a level: its challenges among done (a set of challenge ids); and a room's, from done_by = { [level
-- id] = set }. A level has #def.challenges stars to earn (2, 3, 4: 9 a room).
function C.level_stars(def, done)
    local n = 0
    for _, c in ipairs(def.challenges or {}) do if done and done[c.id] then n = n + 1 end end
    return n
end
function C.room_stars(room, done_by)
    local n = 0
    for _, def in ipairs(C.HOUSE[room] or {}) do n = n + C.level_stars(def, done_by[def.id]) end
    return n
end

-- An old save's n stars (1-3) on a level: the level cleared and its first n - 1 challenges done (a set).
function C.migrate(def, n)
    local done = {}
    for i = 1, math.min(n - 1, #(def.challenges or {})) do done[def.challenges[i].id] = true end
    return done
end

-- Progress: the best stars for each challenge and the fewest dominoes that earned them.
function C.load(text)
    local out = {}
    for id, stars, used in (text or ""):gmatch("(%S+) (%d+) (%d+)") do out[id] = { stars = tonumber(stars), used = tonumber(used) } end
    return out
end

function C.dump(progress)
    local ids, out = {}, {}
    for id in pairs(progress) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do out[#out + 1] = id .. " " .. progress[id].stars .. " " .. progress[id].used end
    return table.concat(out, "\n") .. "\n"
end

-- True if this run beat the saved best.
function C.record(progress, id, stars, used)
    local p = progress[id]
    if stars > 0 and (not p or stars > p.stars or (stars == p.stars and used < p.used)) then
        progress[id] = { stars = stars, used = used }
        return true
    end
    return false
end

return C
end
