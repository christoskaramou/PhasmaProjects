-- Dumps a level's rules ground for given inputs (design aid): luajit tools/level_dump.lua <id> [lx ly name=v ... t=sec]
-- one line per polygon: kind x1 y1 x2 y2 ...  (kind: solid, thorn, shadow:<prop>, ladder, door, star, start)
local D = assert(loadfile("Assets/Scripts/sp_data.lua"))()
local R = assert(loadfile("Assets/Scripts/puppet_rules.lua"))()
local id = arg[1]
local L = R.level(D, id)
local inp = { lantern = { L.start.lantern[1], L.start.lantern[2] } }
for name, p in pairs(L.props) do inp[name] = L.start[name] end
local t = 0
local i = 2
while arg[i] do
    local k, v = arg[i]:match("^(%w+)=(.+)$")
    if k == "lx" then inp.lantern[1] = tonumber(v) elseif k == "ly" then inp.lantern[2] = tonumber(v)
    elseif k == "t" then t = tonumber(v) elseif k then inp[k] = tonumber(v) end
    i = i + 1
end
local function out(kind, pts)
    local s = { kind }
    for _, q in ipairs(pts) do s[#s + 1] = string.format("%.4f %.4f", q[1], q[2]) end
    print(table.concat(s, " "))
end
local function pts(p) local t = {}; for i = 1, p.n do t[i] = { p[2 * i - 1], p[2 * i] } end; return t end
for _, s in ipairs(L.solids) do out("solid", pts(s)) end
for _, s in ipairs(L.thorns) do out("thorn", pts(s)) end
local lx, ly = inp.lantern[1], inp.lantern[2]
for name in pairs(L.props) do
    local ax, az, left = R.prop_place(L, name, inp, t)
    for _, poly in ipairs(R.shadow_polys(L, name, ax, lx, ly, az, left)) do out("shadow:" .. name, poly) end
end
out("door", { { L.door[1], L.door[2] } })
if L.star then out("star", { { L.star[1], L.star[2] } }) end
out("start", { { L.start.puppet[1], L.start.puppet[2] } })
