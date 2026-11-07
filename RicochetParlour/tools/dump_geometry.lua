local f = assert(io.open("Assets/Scripts/rp_rules.lua", "rb"))
local R = assert(loadstring(f:read("*a")))(); f:close()
local out = { '{"W":' .. R.W .. ',"H":' .. R.H .. ',"BALL_R":' .. R.BALL_R .. ',"SLOT":' .. R.SLOT .. ',"ARCH_CY":' .. R.ARCH.cy .. ',"pins":[' }
for i, p in ipairs(R.PINS) do out[#out + 1] = string.format('%s{"x":%.6f,"y":%.6f,"r":%.4f,"rubber":%s}', i > 1 and "," or "", p.x, p.y, p.r, tostring(p.rubber)) end
out[#out + 1] = '],"walls":['
for i, s in ipairs(R.WALLS) do out[#out + 1] = string.format('%s[%.6f,%.6f,%.6f,%.6f]', i > 1 and "," or "", s[1], s[2], s[3], s[4]) end
out[#out + 1] = '],"cups":['
for i, c in ipairs(R.CUPS) do out[#out + 1] = string.format('%s{"x":%.4f,"y":%.4f,"r":%.3f,"points":%d}', i > 1 and "," or "", c.x, c.y, c.r, c.points) end
out[#out + 1] = ']}'
io.write(table.concat(out))
