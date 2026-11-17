-- Plays one level with hand-written keyframes under the real rules and prints its events (design aid):
--   luajit tools/try_level.lua <id> "<lua keyframe list>"     e.g. "{ { t = 1, dur = 1, lantern = { 0, -1 }, balloon = 0.4 } }"
-- An empty list ("{}") is the do-nothing run.
local D = assert(loadfile("Assets/Scripts/sp_data.lua"))()
local R = assert(loadfile("Assets/Scripts/puppet_rules.lua"))()
local id, keys_src = arg[1], arg[2]
local function read_asset(p) local f = io.open("Assets/" .. p, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end
local SCR = assert(loadfile("Assets/Scripts/puppet_scripts.lua"))()(D, read_asset)
local script_fn = SCR.keyframes
local L = R.level(D, id)
local keys = assert(load("return " .. keys_src))()
local f = script_fn(L, keys)
local S = R.new_state(L)
local last = -1
while not S.dead and not S.won do
    R.update(L, S, 1 / 60, f)
    if math.floor(S.t * 2) ~= last then
        last = math.floor(S.t * 2)
        io.write(string.format("t %5.2f x %6.3f y %6.3f %s | ", S.t, S.x, S.y, S.mode))
        if last % 4 == 3 then io.write("\n") end
    end
end
print()
for _, e in ipairs(S.events) do io.write(string.format("%.2f %s  ", e.t, e.e)) end
print()
print(string.format("%s: %s at %.2f s, stars %d", id, S.won and "WON" or ("dead " .. tostring(S.dead)), S.t, (R.stars(L, S))))
