------------------------------------------------------------------ course
-- The road is a list of segments: { length, centre x, half width, island half width, kind }. kind: "road", "bridge"
-- (water both sides, guard rails), "river" (boat), "dock" (the boathouse ramp between road and river).
-- Centre, width and island ease between segments. The course loops; each loop is a new season.
local SEG = {
    { 60, 0, 3.0, 0, "road" }, { 40, 0, 3.0, 0, "road" }, { 50, 1.5, 2.6, 0, "road" }, { 40, -1.0, 3.4, 0, "road" },
    { 30, 0, 4.6, 1.2, "road" }, { 60, 0, 5.2, 1.8, "road" }, { 30, 0, 3.2, 0, "road" },          -- the fork
    { 50, -1.5, 2.6, 0, "road" }, { 40, 0, 2.2, 0, "bridge" }, { 30, 0, 2.6, 0, "road" },
    { 60, 2.0, 3.0, 0, "road" }, { 40, 0, 2.6, 0, "road" }, { 14, 0, 2.6, 0, "dock" },               -- into the boathouse
    { 80, 0, 3.6, 0, "river" }, { 60, 2.5, 3.2, 0, "river" }, { 60, -2.0, 4.0, 1.4, "river" }, { 60, 0, 3.4, 0, "river" },
    { 14, 0, 2.6, 0, "dock" },                                                                      -- back on land
    { 50, 0, 3.0, 0, "road" }, { 40, -2.0, 2.4, 0, "road" }, { 50, 0, 4.8, 1.4, "road" }, { 40, 0, 3.0, 0, "road" },
    { 40, 1.8, 2.4, 0, "bridge" }, { 50, 0, 3.0, 0, "road" },
}
local START, TOTAL = {}, 0
for i, s in ipairs(SEG) do START[i] = TOTAL; TOTAL = TOTAL + s[1] end
G.TOTAL = TOTAL
local function smooth(t) return t * t * (3 - 2 * t) end
-- course at distance y: centre, half width, island half width, kind
local function course(y)
    local yy = y % TOTAL
    local i = 1
    while i < #SEG and START[i + 1] <= yy do i = i + 1 end
    local s, p = SEG[i], SEG[i == 1 and #SEG or i - 1]
    local t = smooth(clamp((yy - START[i]) / min(14, s[1]), 0, 1))
    return lerp(p[2], s[2], t), lerp(p[3], s[3], t), lerp(p[4], s[4], t), s[5], i
end
G.course = course
-- is (x, y) on drivable surface for this vehicle mode? returns false when off the road / out of the river
local function on_surface(x, y, mode)
    local cx, hw, isl, kind = course(y)
    local d = abs(x - cx)
    if d > hw or d < isl then return false end
    if mode == "car" then return kind ~= "river" end
    return kind == "river" or kind == "dock"
end
G.on_surface = on_surface
