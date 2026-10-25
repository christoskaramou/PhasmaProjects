-- Jev orders one existing command per apply, and the Wilds AI still ticks that frame.
local function fail(msg)
    io.stderr:write(msg .. "\n")
    os.exit(1)
end

local function read(path)
    local f = io.open(path, "rb")
    if not f then
        fail("missing " .. path)
    end
    local text = f:read("*a")
    f:close()
    return text
end

local function same(a, b)
    if read(a) ~= read(b) then
        fail("byte mismatch " .. a)
    end
end

same("Assets/Scripts/jev_auto.lua", "../tools/jev_autoplay/jev_auto.lua")
same("Assets/Scripts/jev_boot.lua", "../tools/jev_autoplay/jev_boot.lua")
same(
    "Assets/Scripts/gamekit/driver.lua",
    "../../PhasmaEngine/Phasma/Runtime/RuntimeAssets/Scripts/gamekit/driver.lua"
)
same(
    "Assets/Scripts/gamekit/json.lua",
    "../../PhasmaEngine/Phasma/Runtime/RuntimeAssets/Scripts/gamekit/json.lua"
)

local config = read("Assets/Agent/agent_config.json")
if not config:find('"mcp"%s*:%s*true') or not config:find('"mcp_port"%s*:%s*9146') then
    fail("agent_config mcp port")
end
if not config:find('"indexing"') then
    fail("agent_config dropped indexing")
end

local boot = read("Assets/Scripts/warbound.lua")
if not boot:find("is_key_down_raw", 1, true) or boot:find("is_key_down(", 1, true) then
    fail("human edge must read raw keys")
end
if not boot:find("jev:tick", 1, true) or not boot:find("Game.store_pulse", 1, true) then
    fail("boot does not tick or store the pulse")
end
if not boot:find('title = "Jev"', 1, true) and not read("Assets/Scripts/game/wb_hud.lua"):find('title = "Jev"', 1, true) then
    fail("missing Jev control")
end

local calls = {}
local function rec(name)
    return function(...)
        calls[#calls + 1] = { name = name, args = { ... } }
    end
end

local function count(name)
    local n = 0
    for _, c in ipairs(calls) do
        if c.name == name then
            n = n + 1
        end
    end
    return n
end

local function last(name)
    for i = #calls, 1, -1 do
        if calls[i].name == name then
            return calls[i]
        end
    end
    return nil
end

local WB = {
    util = {
        dist2_sq = function(ax, az, bx, bz)
            local dx = ax - bx
            local dz = az - bz
            return dx * dx + dz * dz
        end,
        mouse = function()
            return nil, nil
        end,
    },
    camera = {
        screen = function()
            return 1920, 1080
        end,
        update = function() end,
    },
    world = { mine = { x = 24.0, z = 2.0 } },
    units = { tick_visual = function() end },
    economy = {
        food_used = function(E)
            local n = 0
            for _, u in ipairs(E.units) do
                if u.alive then
                    n = n + 1
                end
            end
            return n
        end,
        train_status = function()
            return "ok"
        end,
        order_harvest = rec("harvest"),
        try_train = rec("train"),
        update = function() end,
    },
    orders = {
        handle_input = function() end,
        locomote = function() end,
        attack = rec("attack"),
    },
    abilities = {
        status = function()
            return "ready"
        end,
        try_cast = rec("ability"),
        update = function() end,
    },
    selection = { update = function() end },
    hud = {
        point_in_ui = function()
            return false
        end,
        update = function() end,
    },
    combat = {
        acquire = function() end,
        attacks = function() end,
        buildings_pass = function() end,
        standing_town_halls = function()
            return { player = 1, enemy = 1 }
        end,
    },
    build = {
        update = function() end,
        is_placing = function()
            return false
        end,
    },
    ai = { update = rec("ai") },
}

local env = setmetatable({ WB = WB }, { __index = _G })
local chunk, err = load(read("Assets/Scripts/game/wb_game.lua"), "@wb_game.lua", "t", env)
if not chunk then
    fail("compile " .. tostring(err))
end
local Game = chunk()

local worker = { alive = true, arch_is_worker = true, x = -12, z = 22 }
local hero = { alive = true, arch_is_worker = false, is_hero = true, hp = 321.4, x = 0, z = 12 }
local enemy = { alive = true, x = -3, z = -16 }
local hall = { alive = true, state = "done", arch = "town_hall" }
local barracks = { alive = true, state = "done", arch = "barracks" }
local units = { worker, hero }
local state = Game.state
state.player_units = units
state.enemy_units = { enemy }
state.hero = hero
state.kills = 4
state.result = nil
state.econ = {
    player = {
        gold = 150,
        lumber = 80,
        food_cap = 20,
        units = units,
        buildings = { hall, barracks },
    },
}

local function ids()
    local out = {}
    for _, a in ipairs(Game.jev_actions()) do
        out[a.id] = true
    end
    return out
end

local legal = ids()
for _, id in ipairs({
    "harvest_gold", "harvest_lumber", "train_worker", "train_soldier", "attack", "ability",
}) do
    if not legal[id] then
        fail("missing action " .. id)
    end
end

local obs = Game.jev_observe()
if obs.gold ~= 150 or obs.lumber ~= 80 or obs.food ~= 2 or obs.food_cap ~= 20 then
    fail("resource observation")
end
if obs.workers ~= 1 or obs.army ~= 1 or obs.hero_hp ~= 321 then
    fail("roster observation")
end
if obs.enemy_x ~= enemy.x or obs.enemy_z ~= enemy.z then
    fail("nearest enemy")
end
if Game.jev_score() ~= 4 or not Game.jev_playing() or Game.jev_terminal() then
    fail("match flags")
end

Game.store_pulse("harvest_gold")
if count("harvest") ~= 0 then
    fail("apply ran the order instead of storing it")
end
Game.update(0.016)
if count("harvest") ~= 1 or count("ai") ~= 1 then
    fail("harvest pulse or Wilds tick")
end
local harvest = last("harvest")
if harvest.args[3] ~= "gold" or harvest.args[2][1] ~= worker or #harvest.args[2] ~= 1 then
    fail("harvest target")
end

calls = {}
Game.update(0.016)
if count("harvest") ~= 0 or count("ai") ~= 1 then
    fail("pulse repeated or Wilds stopped")
end

worker.job = { kind = "gold" }
legal = ids()
if legal.harvest_gold or not legal.harvest_lumber then
    fail("harvest legality")
end

calls = {}
Game.store_pulse("attack")
Game.update(0.016)
local attack = last("attack")
if not attack or attack.args[2] ~= enemy or #attack.args[1] ~= 1 or attack.args[1][1] ~= hero then
    fail("attack order")
end
if count("ai") ~= 1 then
    fail("Wilds did not tick on attack")
end

calls = {}
Game.store_pulse("train_soldier")
Game.update(0.016)
local train = last("train")
if not train or train.args[3] ~= barracks or count("train") ~= 1 then
    fail("train order")
end

calls = {}
Game.store_pulse("ability")
Game.update(0.016)
local ability = last("ability")
if not ability or ability.args[2] ~= "warstomp" or count("ability") ~= 1 then
    fail("ability order")
end

WB.abilities.status = function()
    return "cooldown"
end
WB.economy.train_status = function()
    return "gold"
end
legal = ids()
if legal.ability or legal.train_worker or legal.train_soldier then
    fail("offered an order the game cannot perform")
end

calls = {}
Game.store_pulse("ability")
Game.update(0.016)
if count("ability") ~= 0 then
    fail("cast while unready")
end

print("ok")
