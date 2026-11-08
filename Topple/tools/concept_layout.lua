-- luajit tools/concept_layout.lua <out.json>   (run from the Topple folder)
-- The Free Build room concept's dominoes, from the game's own rules: the demo build, a spiral by the bookshelf, a
-- wavy line on the coffee-table top running to the ramp, a line to the swinging ball, with the chain frozen
-- mid-run, over the staircase of books and running through the field. Writes each domino's engine pose (position, Euler degrees in
-- the engine's R = Rz * Ry * Rx convention) and paint.
local F = dofile("Assets/Scripts/topple_free.lua")
F.set_room(dofile("Assets/Scripts/free_room.lua"))
local out = arg[1] or "concept_layout.json"
local floor, min, max, sin, cos, pi = math.floor, math.min, math.max, math.sin, math.cos, math.pi

local b = F.demo(F.new_board())
local k = 0
local function rainbow() k = k + 1; return F.PAINTS[floor((k - 1) / 5) % 5 + 1] end
b:begin_action()
-- A spiral on the open floor by the bookshelf.
b:place_spots(F.spiral_spots(25, 15, 25 + 7.5, 15, false), function(i) return F.PAINTS[floor((i - 1) / 4) % 5 + 1] end, 0)
-- A wavy line along the coffee table's top, to its front edge where the ramp starts.
local tbl
for _, s in ipairs(F.ROOM.surfaces) do if s.name == "coffee table" then tbl = s end end
local pts = {}
for i = 0, 16 do pts[#pts + 1] = { -23 + i * 1.2, 2 + 2.2 * sin(i * 0.75) } end
b:place_path(pts, rainbow, tbl.h)
-- From the bottom of the ramp, a line across the rug.
local rug
for _, s in ipairs(F.ROOM.surfaces) do if s.name == "rug" then rug = s end end
b:place_path({ { -12, -16.2 }, { -16, -14.8 }, { -22, -13 }, { -28, -12.5 }, { -31, -9 } }, rainbow, rug.h)
-- A line toward the swinging ball between the sofa and the bookshelf.
b:place_path({ { 2, 10.5 }, { 6, 14 }, { 9, 17 }, { 9, 19.6 } }, rainbow, 0)
b:end_action()

local res = F.simulate(b)
-- Freeze the chain a little over halfway: over the books and running through the field.
local T = res.order[floor(#res.order * 0.58)].t

local function ease_out(u) u = max(0, min(1, u)); return 1 - (1 - u) ^ 3 end
local function angle(f, t)
    if t <= f.t then return 0 end
    if t < f.tc then return f.contact * ((t - f.t) / max(1e-3, f.tc - f.t)) ^ 1.6 end
    return f.contact + (f.final - f.contact) * ease_out((t - f.tc) / 0.15)
end
local lines = {}
local fallen = 0
for id, p in pairs(b.pieces) do
    local f = res.falls[id]
    local yaw, flip, th = p.a, false, 0
    if f and T > f.t then yaw, flip, th = f.yaw, f.flip, angle(f, T); fallen = fallen + 1 end
    local x, y, z, rx, ry, rz = F.pose(p, yaw, flip, th)
    lines[#lines + 1] = string.format('{"p":[%.4f,%.4f,%.4f],"r":[%.3f,%.3f,%.3f],"paint":"%s","pips":%d}', x, y, z, rx, ry, rz, p.paint, (id * 7) % 10)
end
local fh = assert(io.open(out, "w"))
fh:write('{"time":' .. string.format("%.3f", T) .. ',"count":' .. #lines .. ',"fallen":' .. fallen .. ',"dominoes":[\n' .. table.concat(lines, ",\n") .. "\n]}\n")
fh:close()
print(string.format("%d dominoes, %d fallen at t = %.2f s (chain %.1f s)", #lines, fallen, T, res.duration))
