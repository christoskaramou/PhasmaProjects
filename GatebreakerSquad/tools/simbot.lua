-- tools/simbot.lua: the headless sim uses the very same autopilot as the game (src/04b_bot.lua); this shim is
-- kept for scripts that load it directly. tools/simtest.py loads src/04b_bot.lua itself.
local here = (debug.getinfo(1, "S").source:match("^@(.*)[/\\]")) or "tools"
assert(loadfile(here .. "/../src/04b_bot.lua"))()
return G.BOT
