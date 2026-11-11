-- The House's progress: run from the Topple folder with luajit. The eight rooms in order, stars per room, what opens
-- and unlocks as level 1s are cleared, Free Build's rooms, the save (a damaged one loses only its bad lines), and the
-- challenge model: cleared once the requirement is met, stars = challenges done (kept across runs), old saves migrated.
local H = dofile("Assets/Scripts/topple_house.lua")
local checks = 0
local function check(v, msg) assert(v, msg); checks = checks + 1 end

-- The room list is the contract's, in order.
local want = { "hall", "living", "kitchen", "dining", "kids", "bath", "study", "attic" }
check(#H.ROOMS == 8, "eight rooms")
for i, id in ipairs(want) do check(H.ROOMS[i].id == id and H.BY_ID[id].n == i, "room " .. i .. " is " .. id) end
check(H.unlocker("draw").id == "hall" and H.unlocker("line").id == "living" and H.unlocker("ramp").id == "kitchen", "first tools")
check(H.size_unlocker(1).id == "dining", "the dining room unlocks Mini")
check(H.unlocker("ball").id == "kids" and H.unlocker("switch").id == "bath" and H.unlocker("grow").id == "study", "middle tools")
for _, t in ipairs({ "swing", "field", "spiral" }) do check(H.unlocker(t).id == "attic", "the attic unlocks " .. t) end
check(H.unlocker("erase") == nil and H.unlocker("start") == nil, "erase and start belong to no room")

-- Challenge defs as the challenge module lays them out: rooms and tiers on any map's list; the old living-room list
-- (no room) counts as the living room's, in order.
local function def(id, room, tier) return { id = id, room = room, tier = tier } end
local maps = {
    hall = { name = "The Great Hall", list = {} },            -- the Great Hall's map: not the Hallway
    room = { list = { { id = "old1" }, { id = "old2" } } },
    house = { list = { def("h1", "hall", 1), def("h2", "hall", 2), def("h3", "hall", 3), def("k1", "kitchen", 1), def("l3", "living", 3),
        def("x1", "nowhere", 1), def("bad", "kids", 7) } },
}
local h = H.new(maps)
check(h:tiers("hall")[1].id == "h1" and h:tiers("hall")[3].id == "h3", "room defs sorted by tier")
check(h:tiers("living")[1].id == "old1" and h:tiers("living")[2].id == "old2" and h:tiers("living")[3].id == "l3", "the old list is the living room's")
check(h:tiers("kids")[1] == nil and not h:has_challenges("kids"), "a tier out of range is ignored")
check(not h:has_challenges("attic") and h:has_challenges("kitchen"), "rooms with and without challenges")

-- Fresh: only the hallway is open; Free Build only in the living room; only erase and start, only Standard.
check(h:is_open("hall") and not h:is_open("living") and not h:is_open("attic"), "a new house opens on the hallway")
check(#h:free_rooms() == 1 and h:free_rooms()[1] == "living", "free building starts in the living room alone")
check(h:tool_open("erase") and h:tool_open("start") and not h:tool_open("draw") and not h:tool_open("swing"), "only erase and start at first")
check(h:size_open(2) and not h:size_open(1) and not h:size_open(4), "only Standard at first")
check(h:stars("hall") == 0 and h:total_stars() == 0, "no stars")

-- A normal-tier win alone clears nothing.
local better, news = h:record("h2", 3, 40)
check(better and news == nil and h:stars("hall") == 3 and not h:cleared("hall"), "stars on normal do not clear the room")
check(not h:is_open("living") and not h:tool_open("draw"), "nor open or unlock anything")
-- The easy win clears the hallway: draw unlocks, the living room opens, the hallway is buildable.
better, news = h:record("h1", 1, 60)
check(better and news and news.cleared.id == "hall" and news.opened.id == "living", "clearing says what opened")
check(h:cleared("hall") and h:is_open("living") and h:tool_open("draw") and h:free_open("hall"), "hallway cleared")
check(not h:is_open("kitchen") and not h:tool_open("line"), "the next room waits for the living room")
check(h:stars("hall") == 4, "stars add up per room: " .. h:stars("hall"))
-- Worse runs never lower a record; a better one replaces it; a fail (0 stars) never records.
check(not h:record("h1", 1, 70) and h.best.h1.used == 60, "a worse run keeps the record")
check(h:record("h1", 1, 50) and h.best.h1.used == 50, "fewer dominoes for the same stars is better")
check(h:record("h1", 3, 55) and h:stars("hall") == 6, "more stars is better")
check(not h:record("k1", 0, 10) and h.best.k1 == nil, "a fail records nothing")
local _, n2 = h:record("h1", 3, 54)
check(n2 == nil, "clearing again announces nothing")
-- Living room cleared (its easy def is the old list's first): line, then the kitchen.
_, news = h:record("old1", 2, 80)
check(news and news.cleared.id == "living" and news.opened.id == "kitchen" and h:tool_open("line") and h:is_open("kitchen"), "living room cleared")
-- The kitchen: ramp. The dining room opens but has no challenges, so the house stops there.
h:record("k1", 1, 99)
check(h:tool_open("ramp") and h:is_open("dining") and not h:is_open("kids"), "kitchen cleared; dining open; kids waits")
check(not h:size_open(1), "Mini waits for the dining room")
local rooms = table.concat(h:free_rooms(), " ")
check(rooms == "hall living kitchen", "free building in the cleared rooms and the living room: " .. rooms)

-- unlock_all opens everything, for testing.
h.all = true
check(h:is_open("attic") and h:tool_open("spiral") and h:size_open(5) and #h:free_rooms() == 8, "everything open")
h.all = false

-- Save and load.
local text = h:dump()
check(text:match("^TOPPLE%-HOUSE 2\n"), "a header")
local h2 = H.new(maps)
check(h2:load(text) == 0, "a good save reads without a bad line")
check(h2:stars("hall") == h:stars("hall") and h2:cleared("kitchen") and h2.best.h1.used == 54, "it round-trips")
check(h2:dump() == text, "and dumps the same")
-- A damaged save loses only its bad lines.
local damaged = "TOPPLE-HOUSE 1\nh1 3 54\nh2 3\nold1 2 80 extra\n\0\255garbage\nk1 9 10\nk1 1 99\r\n  h3 2 61  \n"
local h3 = H.new(maps)
local bad = h3:load(damaged)
check(bad == 4, "four bad lines found: " .. bad)
check(h3.best.h1 and h3.best.h1.stars == 3 and h3.best.k1 and h3.best.k1.used == 99 and h3.best.h3 and h3.best.h3.used == 61, "the good lines survive")
check(h3.best.h2 == nil and h3.best.old1 == nil, "the bad lines are dropped")
check(h3:cleared("hall") and h3:cleared("kitchen") and not h3:cleared("living"), "and what they unlock follows")
-- The old challenges file (no header) still reads; nothing at all is a fresh house.
local h4 = H.new(maps)
check(h4:load("h1 2 50\nold1 3 70\n") == 0 and h4:cleared("hall") and h4:cleared("living"), "the old challenges file loads")
check(h4:load(nil) == 0 and next(h4.best) == nil, "no save, a fresh house")

-- Levels with challenges (the House's model): a level is cleared once a run met its requirement (Start to End), stars
-- or not; its stars are the challenges done, each kept once earned, across runs.
local function lv(id, room, tier, n)
    local cs = {}
    for i = 1, n do cs[i] = { id = "c" .. i } end
    return { id = id, room = room, tier = tier, challenges = cs }
end
local maps2 = { house = { list = { lv("a1", "hall", 1, 2), lv("a2", "hall", 2, 3), lv("a3", "hall", 3, 4), lv("b1", "living", 1, 2) } } }
local g = H.new(maps2)
better, news = g:record("a1", { met = true, done = {} }, 50)
check(better and news and news.cleared.id == "hall" and g:cleared("hall") and g:stars("hall") == 0, "met with no challenge: cleared, 0 stars")
check(g:tool_open("draw") and g:is_open("living") and g:free_open("hall"), "a clear with no star unlocks as any clear does")
check(not g:record("b1", { met = false, done = { "c1" } }, 10) and not g:cleared("living") and g.best.b1 == nil, "a run that missed the requirement records nothing")
g:record("a2", { met = true, done = { "c1" } }, 90)
check(g:record("a2", { met = true, done = { "c3" } }, 95), "a new challenge is something to save")
check(g:stars_for("a2") == 2 and g:done("a2", "c1") and g:done("a2", "c3") and not g:done("a2", "c2"), "stars stay across runs (a set)")
check(not g:record("a2", { met = true, done = { "c1" } }, 99), "a challenge earned again is nothing new")
check(g:record("a2", { met = true, done = {} }, 80) and g.best.a2.used == 80 and g:stars_for("a2") == 2, "fewer dominoes is, and takes no star away")
g:record("a3", { met = true, done = { "c1", "c2", "c3", "c4", "zz" } }, 120)
check(g:stars_for("a3") == 4 and g:stars("hall") == 6 and g:total_stars() == 6, "only a level's own challenges count; a room is the sum: " .. g:stars("hall"))
check(g.best.a2.stars == 2 and g.best.a3.stars == 4, "best[id].stars is the count the cards read")
-- The view's number form: the run C.won left on the def (def.challenges.last) is the one recorded.
local A1 = maps2.house.list[1]
A1.challenges.last = { id = "a1", met = true, done = { "c2" } }
check(g:record("a1", 1, 48) and g:done("a1", "c2") and A1.challenges.last == nil, "a count with the hand-off records that run")
-- Save and load: the challenges done are listed; a clear without a star is "0".
local t2 = g:dump()
check(t2:match("^TOPPLE%-HOUSE 2\n") and t2:find("\na1 1 48 c2\n", 1, true) and t2:find("\na2 2 80 c1 c3\n", 1, true), "the save lists the challenges done:\n" .. t2)
local g2 = H.new(maps2)
check(g2:load(t2) == 0 and g2:dump() == t2 and g2:stars("hall") == g:stars("hall") and g2:done("a3", "c4"), "it round-trips")
local g3 = H.new(maps2)
g3:record("b1", { met = true, done = {} }, 30)
local t3 = g3:dump()
local g4 = H.new(maps2)
check(t3:find("\nb1 0 30\n", 1, true) and g4:load(t3) == 0 and g4:cleared("living") and g4:stars("living") == 0, "cleared with no star round-trips")
-- A damaged save loses only its bad lines: a count that does not match its ids, a bad id, a bad number.
local g5 = H.new(maps2)
local bad5 = g5:load("TOPPLE-HOUSE 2\na1 1 48 c2\na2 2 80 c1\na3 1 99 c$\nb1 x 1\na3 2 70 c1 c2\n")
check(bad5 == 3 and g5:done("a1", "c2") and g5.best.a2 == nil and g5:stars_for("a3") == 2, "damaged lines dropped, " .. bad5)
-- An old save migrates: n stars on a level = cleared and its first n - 1 challenges (capped at the level's).
local g6 = H.new(maps2)
check(g6:load("TOPPLE-HOUSE 1\na1 1 60\na2 3 90\na3 2 99\n") == 0, "an old save reads")
check(g6:cleared("hall") and g6:stars_for("a1") == 0 and g6:stars_for("a2") == 2 and g6:done("a2", "c1") and g6:done("a2", "c2")
    and g6:stars_for("a3") == 1 and g6:done("a3", "c1"), "old stars migrate: 1 = cleared, 3 = cleared and two challenges")
check(g6:dump():find("\na2 2 90 c1 c2\n", 1, true), "and save in the new form")
local g7 = H.new(maps2)
check(g7:load("b1 3 40\n") == 0 and g7:cleared("living") and g7:stars_for("b1") == 2, "the old challenges file migrates too, capped")
-- An old-style def (no challenges) in a new save keeps its 1-3 stars.
check(h:dump():find("\nh1 3 54\n", 1, true), "an old-style level keeps its count in the new save")

-- Nothing stands in the air: every buildable surface of every room lies on the drawn furniture's top (tools/fit_audit.lua:
-- gap or sink over 0.15, or over 5% with nothing under it, is flagged), and so do every level's Start, End, presets, props,
-- goal, traps and scripted-solution dominoes. KNOWN: pieces whose model cannot be fitted and whose spec cannot follow it
-- (none since 2026-11-11: the flagged pieces' surfaces and solids were measured from their models); anything else flagged
-- fails.
local KNOWN = {}
local FA = dofile("tools/fit_audit.lua")
local lines = FA.run()
local floating = {}
for _, l in ipairs(lines) do
    if l:sub(1, 4) == "FLAG" then
        local room, rest = l:match("^FLAG (%S+)%s+(.*)$")
        local key = rest:match("^(surface .-)%s+h%s") or rest:match("^(level %d)")
        if not KNOWN[room .. " " .. key] then floating[#floating + 1] = l end
    end
end
check(#lines >= 60, "the fit audit ran over the rooms, " .. #lines .. " lines")
check(#floating == 0, "nothing stands in the air:\n" .. table.concat(floating, "\n"))
-- And nothing drawn rises out of a narrow surface at its edges: the bath's west rim end as it was (over the taps, no tap
-- solids) is flagged.
do
    local bath = dofile("Assets/Scripts/rooms/bath.lua")
    local kept = {}
    for _, q in ipairs(bath.solids) do if q.name ~= "bathtub tap" then kept[#kept + 1] = q end end
    bath.solids = kept
    for _, s in ipairs(bath.surfaces) do if s.name == "bathtub rim end" and s.x0 < 0 then s.y0, s.y1 = 15.5, 16.75 end end
    local _, n = FA.run({ "bath" }, { rooms = { bath = bath }, surfaces_only = true })
    check(n >= 1, "the audit sees the taps rising out of the old west rim end")
end

print(checks .. " checks passed")
print("PASS house")
