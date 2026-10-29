-- Headless balance harness (box only): loads project/Assets/Scripts/game.lua with stubbed engine APIs and runs the
-- in-game test bots ("human" / "greedy") over levels with chosen upgrade profiles. Never touches any save file.
-- usage: bin/luajit tools/headless.lua <profile> <levels e.g. 1-12> <trials> [bot] [hp overrides like p_miss=0.3]
local ROOT = "project/Assets/"
local noop = function() end
local function V(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
vec3 = V; vec4 = function(a, b, c, d) return { a, b, c, d } end
local NodeMT = {}
NodeMT.__index = function(t, k)
    if k == "get_mesh_refs" then return function() return { {} } end end
    if k == "get_rotation" or k == "get_position" or k == "get_scale" then return function() return V() end end
    return noop
end
local function node() return setmetatable({}, NodeMT) end
local function mod(extra) return setmetatable(extra or {}, { __index = function() return noop end }) end
local PL = {}
scene = mod { find_model = function() return node() end, add_empty_node = function() return node() end, get_cameras = function() return { node() } end }
get_camera = function() return node() end
lights = mod { add_point = function() PL[#PL + 1] = { name = "pl" .. #PL } end, get_point_lights = function() return PL end, get_directional_lights = function() return { {} } end }
runtime_ui = mod { get_surface_size = function() return { width = 1920, height = 1080 } end, get_state = function() return nil end }
input = mod { is_key_down_raw = function() return false end, is_key_pressed = function() return false end, is_left_mouse_down = function() return false end,
    get_mouse_position = function() return { x = 0, y = 0 } end }
audio, material, settings, engine, app, particles = mod(), mod(), mod(), mod(), mod(), mod()
fs = { read = function(p) if p:match("^Save") then return nil end local f = io.open(ROOT .. p); if not f then return nil end local s = f:read("*a"); f:close(); return s end,
    write = function() end }
pe_log = noop
local UPDATE
hooks = function(t) UPDATE = t.update end
local KNOWN = { arg = true, jit = true, bit = true }
setmetatable(_G, { __index = function(t, k) if KNOWN[k] then return nil end local m = mod(); rawset(t, k, m); return m end })
local chunk = assert(loadfile(ROOT .. "Scripts/game.lua"))
chunk()
local G = CM
local M, C, RUN, HUD, U = G.M, G.C, G.RUN, G.HUD, G.UI
HUD.play = function() end; HUD.overlays = noop
G.popup = noop; G.popup_at = noop; G.tip = noop

-- upgrade profiles per level index: what a player plausibly owns when they reach level i
local PROFILES = {
    fresh = function(i) return { } end,                      -- never shopped (catch-up does the work)
    christos = function(i) return { start = 4, gate = 1, speed = 1, bank = 1 } end,   -- the owner's real save at L6
    modest = function(i)  -- about one upgrade per cleared level, spread like a casual shopper
        local n = i - 1; local up = { start = 0, gate = 0, armor = 0, speed = 0, might = 0 }
        local order = { "start", "gate", "start", "armor", "start", "gate", "might", "armor", "start", "gate", "speed", "might", "armor", "start" }
        for k = 1, n do local id = order[(k - 1) % #order + 1]; up[id] = up[id] + 1 end
        return up
    end,
}
if os.getenv('EXTRA') then dofile(os.getenv('EXTRA')) os.exit(0) end
local prof, lv, trials, botmode = arg[1] or "fresh", arg[2] or "1-12", tonumber(arg[3] or 20), arg[4] or "human"
local hp = {}
for i = 5, #arg do local k, v = arg[i]:match("([%w_]+)=([%d%.]+)"); if k then hp[k] = tonumber(v) end end
G.hp = hp; G.hdebug = os.getenv("HD")
if lv == 'all' then lv = '1-' .. #G.LEVELS end
local a, b = lv:match("(%d+)%-(%d+)"); a, b = tonumber(a or lv), tonumber(b or lv)
local verbose = os.getenv("V")
local DT, JIT = 1 / (tonumber(os.getenv('HZ')) or 60), os.getenv('JIT')
for i = a, b do
    local wins, where, peak, left = 0, {}, 0, 0
    for tr = 1, trials do
        math.randomseed(1000 * i + tr)
        M.D.up = PROFILES[prof](i); M.D.board = {}; for k = 1, 15 do M.D.board[k] = 0 end
        M.D.gem = {}; M.D.unlocked = 15
        local fails = (os.getenv("FAILS") and tonumber(os.getenv("FAILS"))) or 0
        M.D.fails = {}; M.D.fails[i] = fails
        G.bot = botmode
        G.goto_level(i)
        local L = G.L
        local log = {}
        local nextlog = 0
        local t = 0
        while G.state == "play" and t < 400 do
            local dt = DT; if JIT then dt = 1 / (40 + math.random() * 104) end
            UPDATE(dt); t = t + dt
            if os.getenv("TR") and C.cz >= (tonumber(os.getenv("Z0")) or 0) and C.cz <= (tonumber(os.getenv("Z1")) or 999) and math.floor(t * 60) % 10 == 0 then
                print(string.format("  t%.1f z%.1f cx%.2f cxt%.2f hw%.2f pow%d n%d ph=%s", t, C.cz, C.cx, C.cxt, C.hw or 0, C.power(), #C.units, RUN.phase)) end
            if verbose and C.cz >= nextlog then log[#log + 1] = string.format("%d:%d", math.floor(C.cz), C.power()); nextlog = nextlog + 20 end
        end
        if os.getenv("SHOWT") then print("t_end", t, DT) end
        local won = G.state == "win"
        if won then wins = wins + 1; left = left + (G.L.boss and C.power() or G.FIN.reach()) else
            local ph = RUN.phase
            local key = (G.L.boss and C.cz >= L.len) and "boss" or ("z" .. math.floor(C.cz / 10) * 10)
            where[key] = (where[key] or 0) + 1
        end
        peak = peak + (RUN.stats.peak or 0)
        if verbose then print(i, tr, won and "WIN" or "LOSE", math.floor(C.cz), table.concat(log, " ")) end
    end
    local w = {}
    for k, v in pairs(where) do w[#w + 1] = k .. "x" .. v end
    table.sort(w)
    print(string.format("L%-2d %-14s %s win %3d%%  peak %5.1f  left %5.1f  boost %.2f/%d  losses: %s", i, G.LEVELS[i].name or "", prof, math.floor(100 * wins / trials + 0.5),
        peak / trials, wins > 0 and left / wins or 0, G.boost.foe, G.boost.pawns, table.concat(w, " ")))
end
