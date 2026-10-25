------------------------------------------------------------------ world locations (original order: 17 locations, 50 stages)
local LOCS = {
    { "fuji", "Mt. Fuji", "Japan" }, { "guilin", "Mt. Keirin", "China" }, { "emerald", "Emerald Temple", "Thailand" },
    { "angkor", "Angkor Wat", "Cambodia" }, { "ayers", "Ayers Rock", "Australia" }, { "taj", "Taj Mahal", "India" },
    { "leningrad", "Leningrad", "U.S.S.R." }, { "paris", "Paris", "France" }, { "london", "London", "England" },
    { "barcelona", "Barcelona", "Spain" }, { "athens", "Athens", "Greece" }, { "egypt", "Egypt", "Egypt" },
    { "kenya", "Kenya", "Africa" }, { "newyork", "New York", "U.S.A." }, { "maya", "Maya", "Mexico" },
    { "antarctica", "Antarctica", "" }, { "easter", "Easter Island", "Chile" },
}
G.LOCS = LOCS
local NSTAGES = 50
local function loc_of(n) return min(17, floor((n - 1) / 3) + 1) end
G.loc_of = loc_of

------------------------------------------------------------------ layouts: blocks {x0, y0, w, h, kind}  kind: s = steel, r/b/y/g = breakable glass
-- ladders {x, y0, y1}; y1 is ALWAYS the TOP of the block the ladder leads onto (y0 + h), so the player can step off.
-- A wall that stands on the floor always gets a ladder on both sides up to a cap, so no wall can split the floor.
-- tools/audit_stages.py checks every stage (reachability, walls, trapped balloons).
local LAYOUTS = {
    { b = {}, l = {} },                                                                                                    -- 1 open field
    { b = { { -19, 9, 8, 1, "s" }, { 11, 9, 8, 1, "s" } }, l = {} },                                                       -- 2 two shelves
    { b = { { -10, 13, 4, 1, "r" }, { -6, 13, 4, 1, "y" }, { -2, 13, 4, 1, "r" }, { 2, 13, 4, 1, "y" }, { 6, 13, 4, 1, "r" } }, l = {} }, -- 3 glass row
    { b = { { -20, 8, 9, 1, "s" }, { 11, 8, 9, 1, "s" } }, l = { { -12.5, 0, 9 }, { 12.5, 0, 9 } } },                   -- 4 platforms + ladders
    { b = { { -24, 17, 22, 1, "b" }, { 2, 17, 22, 1, "b" } }, l = {} },                                                   -- 5 glass ceiling with a gap
    { b = { { -20, 4, 4, 1, "g" }, { -16, 7, 4, 1, "g" }, { -12, 10, 4, 1, "g" }, { 8, 10, 4, 1, "g" }, { 12, 7, 4, 1, "g" }, { 16, 4, 4, 1, "g" } }, l = {} }, -- 6 stairs
    { b = { { -8, 10, 16, 1, "s" } }, l = { { -6, 0, 11 }, { 6, 0, 11 } } },                                              -- 7 bridge
    { b = { { -17, 6, 2, 2, "r" }, { -7, 12, 2, 2, "y" }, { 5, 6, 2, 2, "r" }, { 15, 12, 2, 2, "y" }, { -1, 17, 2, 2, "b" } }, l = {} }, -- 8 boxes
    { b = { { -9, 0, 2, 7, "b" }, { 7, 0, 2, 7, "b" }, { -10.5, 7, 5, 1, "s" }, { 5.5, 7, 5, 1, "s" } },
      l = { { -9.9, 0, 8 }, { -6.1, 0, 8 }, { 6.1, 0, 8 }, { 9.9, 0, 8 } } },                                          -- 9 glass walls, capped, ladders both sides
    { b = { { -14, 15, 28, 1, "s" } }, l = {} },                                                                           -- 10 high bar
    { b = { { -20, 9, 3, 1, "y" }, { -11, 9, 3, 1, "y" }, { -2, 9, 3, 1, "y" }, { 7, 9, 3, 1, "y" }, { 16, 9, 3, 1, "y" },
            { -15, 15, 3, 1, "r" }, { -6, 15, 3, 1, "r" }, { 3, 15, 3, 1, "r" }, { 12, 15, 3, 1, "r" } }, l = {} },     -- 11 checker
    { b = { { -24, 12, 6, 1, "s" }, { 18, 12, 6, 1, "s" } }, l = { { -21, 0, 13 }, { 21, 0, 13 } } },                   -- 12 side ledges
    { b = { { -24, 9, 20, 1, "s" }, { 4, 9, 20, 1, "s" } }, l = { { -7, 0, 10 }, { 7, 0, 10 } } },                        -- 13 double deck
    { b = { { -1, 0, 2, 9, "s" }, { -2.5, 9, 5, 1, "s" } }, l = { { -1.9, 0, 10 }, { 1.9, 0, 10 } } },                 -- 14 centre pillar: capped, a ladder up each side
    { b = { { -6, 14, 12, 1, "g" }, { -6, 15, 1, 4, "g" }, { 5, 15, 1, 4, "g" } }, l = {} },                             -- 15 glass cup
    { b = { { -18, 6, 6, 1, "s" }, { 12, 6, 6, 1, "s" }, { -3, 12, 6, 1, "s" } }, l = { { -15, 0, 7 }, { 15, 0, 7 } } }, -- 16 three shelves
}
G.LAYOUTS = LAYOUTS
local COLORS = { "red", "blue", "green", "yellow", "purple" }
local BX = { -14, 14, -4, 6, -20, 20 }
local function stage_def(n)
    local lay = (n == 1) and LAYOUTS[1] or LAYOUTS[((n * 7) % (#LAYOUTS - 1)) + 2]
    if n == 2 then lay = LAYOUTS[2] end
    if n == 3 then lay = LAYOUTS[3] end
    local k = (n - 1) % 3 + 1
    local balls = {}
    local big = min(4, 1 + floor((n - 1) / 7))
    if n % 7 == 0 then
        for i = 1, 4 do balls[#balls + 1] = { 3, BX[i], 1 - 2 * (i % 2) } end
    else
        for i = 1, big do balls[#balls + 1] = { 4, BX[i], 1 - 2 * (i % 2) } end
        if k == 2 or n > 20 then balls[#balls + 1] = { 3, BX[#balls + 1] or 0, -1 } end
        if k == 3 then balls[#balls + 1] = { 2, BX[#balls + 1] or 0, 1 }; balls[#balls + 1] = { 2, BX[#balls + 1] or 2, -1 } end
    end
    local tm = min(150, 70 + 18 * #balls)
    return { n = n, loc = loc_of(n), lay = lay, balls = balls, color = COLORS[(n - 1) % #COLORS + 1], time = tm,
        crab = (n % 4 == 2 and n > 4), bird = (n % 4 == 0) }
end
G.stage_def = stage_def

------------------------------------------------------------------ live stage
local ST = nil
G.ST = function() return ST end
local BLK_MESH = { s = "blk_steel", r = "blk_glass_red", b = "blk_glass_blue", y = "blk_glass_yellow", g = "blk_glass_green" }
local BLK_COL = { s = { .7, .72, .78 }, r = { 1, .35, .35 }, b = { .4, .6, 1 }, y = { 1, .85, .3 }, g = { .4, 1, .5 } }
G.BLK_COL = BLK_COL
local BLKP = { "blk_steel", "blk_glass_red", "blk_glass_blue", "blk_glass_yellow", "blk_glass_green", "ladder", "rung" }
-- every ladder uses the same rung pitch, with rungs on a world-height grid so neighbouring ladders line up
local RUNG_PITCH = 0.65
local function build_stage(n)
    local d = stage_def(n)
    for _, k in ipairs(BLKP) do P_begin(k) end
    ST = { n = n, def = d, blocks = {}, ladders = {} }
    for _, b in ipairs(d.lay.b) do
        local blk = { x0 = b[1], y0 = b[2], w = b[3], h = b[4], x1 = b[1] + b[3], y1 = b[2] + b[4], kind = b[5], live = true }
        blk.node = P_get(BLK_MESH[blk.kind])
        blk.node:set_position(vec3(blk.x0 + blk.w / 2, blk.y0 + blk.h / 2, 0)); blk.node:set_scale(vec3(blk.w - 0.02, blk.h - 0.02, 2.0))
        ST.blocks[#ST.blocks + 1] = blk
    end
    for _, l in ipairs(d.lay.l) do
        local lad = { x = l[1], y0 = l[2], y1 = l[3] }
        lad.node = P_get("ladder"); lad.node:set_position(vec3(lad.x, lad.y0, 0.25)); lad.node:set_scale(vec3(1.25, lad.y1 - lad.y0, 1))
        local y = (floor(lad.y0 / RUNG_PITCH) + 1) * RUNG_PITCH - RUNG_PITCH / 2
        while y < lad.y1 - 0.15 do
            if y > lad.y0 + 0.2 then P_get("rung"):set_position(vec3(lad.x, y, 0.25)) end
            y = y + RUNG_PITCH
        end
        ST.ladders[#ST.ladders + 1] = lad
    end
    for _, k in ipairs(BLKP) do P_end(k) end
    G.set_backdrop(LOCS[d.loc][1])
    return ST
end
G.build_stage = build_stage
-- standing surfaces for the player / items: floor, block tops
local function support_at(x, y, hw, up, down)
    local best = nil
    if y <= up and y >= -down then best = 0 end
    for _, b in ipairs(ST.blocks) do
        if b.live and x + hw > b.x0 and x - hw < b.x1 and b.y1 >= y - down and b.y1 <= y + up then
            if not best or abs(b.y1 - y) < abs(best - y) then best = b.y1 end
        end
    end
    return best
end
G.support_at = support_at

------------------------------------------------------------------ frame, floor and the painted backdrop
local BG = {}
function G.set_backdrop(key)
    if BG.key == key then return end
    BG.key = key
    mtex(BG.plane, "emissive", "Textures/bg_" .. key .. ".png")
end
local function build_world()
    BG.plane = clone("bg_plane", vec3(0, 13, -2.7), vec3(48, 26, 1))
    local function fr(x, y, w, h, z, d) clone("frame", vec3(x, y, z or -0.2), vec3(w, h, d or 5.4)) end
    -- Posts sit 0.15 behind the lintel and floor and stop inside them, so the four
    -- corners are one surface. The old posts occupied the same volume and flickered.
    fr(-25, 13.05, 1.92, 26.5, -0.2, 5.1); fr(25, 13.05, 1.92, 26.5, -0.2, 5.1); fr(0, 27, 52, 2)
    clone("floor", vec3(0, -1.5, -0.2), vec3(52, 3, 5.4))
    -- surroundings so the frame doesn't float: a deep wall behind
    local back = prim("cube", vec3(0, 12, -6), vec3(140, 70, 1)); paint(back, { .08, .09, .11 }, { 0, 0, 0 }, .9, 0)
end
