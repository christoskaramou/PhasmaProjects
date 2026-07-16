-- ath_console — backtick-toggled DEV cheat console (typed commands).
--
-- ENABLE: ATH_DEV=1 or Settings → Dev Mode. Starts closed; press ` / F1 to open.
-- While open, ALL other game/engine key binds are muted (Duel input + play_controls);
-- only the console line buffer reads the keyboard.

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Balance = ATH_COMMON.load_script("Scripts/shared/ath_balance.lua", "balance", _ENV)
local Inventory = ATH_COMMON.load_script("Scripts/shared/ath_inventory.lua", "inventory", _ENV)

local Console = {}

local HELP = {
    "mymap              unlock all maps",
    "swaphero <name>    change hero mid-play",
    "cantdie            toggle invulnerable",
    "gold <n>           set gold",
    "specme <n>         add skill points",
    "item <name>        spawn item in bag",
    "endless            endless creeps (in map)",
    "superhero          toggle mega hero buff",
}

local CHAR_KEYS = {
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "Space",
}

local function raw_down(name)
    return input and input.is_key_down and input.is_key_down(name) == true
end

local function state(D)
    local c = D.console
    if not c then
        c = { visible = false, line = "", msg = "", blink_t = 0.0 }
        D.console = c
    end
    if c.line == nil then c.line = "" end
    return c
end

-- Console must read keys via raw input — Duel:is_key_down is muted while open.
local function toggle_pressed(D)
    local down = raw_down("`") or raw_down("Grave") or raw_down("Backquote") or raw_down("F1")
    local prev = D._console_toggle_down
    D._console_toggle_down = down
    return down and not prev
end

local function edge(D, name)
    D._cheat_keys = D._cheat_keys or {}
    local down = raw_down(name)
    local prev = D._cheat_keys[name]
    D._cheat_keys[name] = down
    return down and not prev
end

local function norm(s)
    return string.lower(tostring(s or "")):gsub("^%s+", ""):gsub("%s+$", "")
end

local function find_hero(D, query)
    query = norm(query)
    local list = D.config.hero and D.config.hero.classes or {}
    for i, c in ipairs(list) do
        if norm(c.id) == query or norm(c.name) == query then return i, c end
    end
    return nil
end

local function find_item(D, query)
    query = norm(query)
    local items = (D.gear_cfg and D.gear_cfg.items) or Balance.items or {}
    local qsp = query:gsub("%s+", "_")
    local qns = query:gsub("[%s_%-]+", "")
    local soft
    for _, it in ipairs(items) do
        local id, name = norm(it.id), norm(it.name)
        if id == query or name == query or id == qsp then return it end
        local idns = id:gsub("[%s_%-]+", "")
        local namens = name:gsub("[%s_%-]+", "")
        if id:find(query, 1, true) or name:find(query, 1, true)
            or idns:find(qns, 1, true) or namens:find(qns, 1, true) then
            soft = soft or it
        end
    end
    return soft
end

local function clone_item(it)
    local copy = {}
    for k, v in pairs(it) do
        if k == "effect" and type(v) == "table" then
            local e = {}
            for ek, ev in pairs(v) do e[ek] = ev end
            copy[k] = e
        else
            copy[k] = v
        end
    end
    return copy
end

local function cmd_mymap(D)
    local n = D.maps and #D.maps or 0
    if n <= 0 then return "no maps" end
    -- max selectable = min(maps_cleared+1, #maps); #maps-1 unlocks the last map,
    -- #maps marks every map cleared. Either unlocks the full ladder.
    D.maps_cleared = n
    local ok, err = pcall(function()
        if D.save_profile then D:save_profile() end
    end)
    if not ok then return "unlocked, save failed: " .. tostring(err) end
    if Inventory and Inventory.refresh then Inventory.refresh(D) end
    return "unlocked " .. n .. " maps"
end

local function cmd_swaphero(D, arg)
    local idx, cls = find_hero(D, arg)
    if not idx then return "unknown hero (ranger/brawler/sower/mage/rogue/warrior/necromancer)" end
    if D.cheat_swap_hero then
        local ok, msg = D:cheat_swap_hero(idx)
        return ok and ("hero=" .. cls.id) or tostring(msg or "swap failed")
    end
    return "swap unavailable"
end

local function cmd_cantdie(D)
    D.invulnerable = not D.invulnerable
    return "cantdie " .. (D.invulnerable and "ON" or "off")
end

local function cmd_gold(D, arg)
    local n = tonumber(arg)
    if n == nil then return "usage: gold <amount>" end
    D.gold = math.max(0, math.floor(n + 0.5))
    if D.save_profile then D:save_profile() end
    return "gold=" .. D.gold
end

local function cmd_specme(D, arg)
    local n = tonumber(arg)
    if n == nil then return "usage: specme <amount>" end
    n = math.max(0, math.floor(n + 0.5))
    D.skill_points = (D.skill_points or 0) + n
    if D.save_profile then D:save_profile() end
    return "skill_points=" .. D.skill_points .. " (+" .. n .. ")"
end

local function cmd_item(D, arg)
    if norm(arg) == "" then return "usage: item <name>" end
    local it = find_item(D, arg)
    if not it then return "unknown item" end
    if not Inventory.add_item(D, clone_item(it)) then return "bag full" end
    if Inventory.refresh then Inventory.refresh(D) end
    if D.recompute_hero_stats then D:recompute_hero_stats() end
    return "got " .. tostring(it.id or it.name)
end

local function cmd_endless(D)
    if D.state ~= "combat" then return "endless only applies in a map" end
    D.endless = not D.endless
    if D.endless then
        local minc = D.minimum_spawn_cost and D:minimum_spawn_cost() or 10
        D.reserve = math.max(D.reserve or 0, math.max(minc * 8, (D.reserve_start or 200) * 0.5))
    end
    return "endless " .. (D.endless and "ON" or "off")
end

local function cmd_superhero(D)
    D.superhero = not D.superhero
    if D.recompute_hero_stats then D:recompute_hero_stats() end
    if D.superhero and D.hero then D.hero.hp = D.hero.hp_max end
    return "superhero " .. (D.superhero and "ON" or "off")
end

local COMMANDS = {
    mymap = function(D) return cmd_mymap(D) end,
    swaphero = function(D, arg) return cmd_swaphero(D, arg) end,
    cantdie = function(D) return cmd_cantdie(D) end,
    gold = function(D, arg) return cmd_gold(D, arg) end,
    specme = function(D, arg) return cmd_specme(D, arg) end,
    item = function(D, arg) return cmd_item(D, arg) end,
    endless = function(D) return cmd_endless(D) end,
    superhero = function(D) return cmd_superhero(D) end,
}

local function run_line(D, line)
    line = norm(line)
    if line == "" then return "" end
    local cmd, arg = line:match("^(%S+)%s*(.*)$")
    cmd = norm(cmd)
    local fn = COMMANDS[cmd]
    if not fn then return "unknown: " .. cmd end
    local ok, msg = pcall(fn, D, arg)
    if not ok then return "error: " .. tostring(msg) end
    return tostring(msg or "ok")
end

-- World freeze via settings.time_scale (shared with gear hub). Prefer this over
-- engine.set_paused — pause also stops this update()/typing.
local function set_capture(D, on)
    _G.PE_BLOCK_PLAY_CONTROLS = on and true or nil
    if on then
        if D._inv_open and Inventory and Inventory.hide then
            D._cheat_hub_was_open = true
            Inventory.hide(D)
        end
        if engine and engine.is_paused and engine.set_paused and engine.is_paused() then
            engine.set_paused(false)
        end
    else
        if D._cheat_hub_was_open and Inventory and Inventory.show then
            D._cheat_hub_was_open = nil
            Inventory.show(D)
        end
    end
    if ATH_COMMON.sync_world_freeze then ATH_COMMON.sync_world_freeze(D) end
end

local function poll_typing(D, c)
    for _, name in ipairs(CHAR_KEYS) do
        if edge(D, name) then
            if name == "Space" then
                c.line = c.line .. " "
            else
                c.line = c.line .. string.lower(name)
            end
        end
    end
    if edge(D, "Backspace") or edge(D, "Delete") then
        c.line = c.line:sub(1, math.max(0, #c.line - 1))
    end
    if edge(D, "Return") or edge(D, "Keypad Enter") then
        c.msg = run_line(D, c.line)
        c.line = ""
    end
end

function Console.update(D)
    if not D.manual_hero then return end
    local enabled = ATH_COMMON.dev_enabled and ATH_COMMON.dev_enabled() or false
    D._console_enabled = enabled
    local c = state(D)
    if not enabled then
        if c.visible then
            c.visible = false
            c.line = ""
            set_capture(D, false)
            Art.remove(D.hud, "console")
        end
        return
    end

    if toggle_pressed(D) then
        c.visible = not c.visible
        c.line = ""
        c.msg = c.visible and "dev console ON — type a cheat, Enter to run" or ""
        set_capture(D, c.visible)
        if not c.visible then Art.remove(D.hud, "console") end
    end

    -- Invuln from cantdie (and ATH_DUEL_INVULNERABLE) — keep HP topped while on.
    if D.invulnerable and D.hero and not D.hero.dead then
        D.hero.hp = D.hero.hp_max
    end

    if not c.visible then return end
    -- Re-assert capture every frame (other scripts may clear globals).
    _G.PE_BLOCK_PLAY_CONTROLS = true
    poll_typing(D, c)
    c.blink_t = (c.blink_t or 0.0) + 0.016
end

function Console.draw(D)
    if not (D.manual_hero and D._console_enabled) then return end
    local c = D.console
    if not (c and c.visible) then
        if c then Art.remove(D.hud, "console") end
        return
    end
    local sw = select(1, Art.surface_size())
    local function S(v) return v * Art.s("hud") end
    local cursor = ((math.floor((c.blink_t or 0) * 2) % 2) == 0) and "_" or " "
    local flags = {
        "cantdie=" .. (D.invulnerable and "ON" or "off"),
        "endless=" .. (D.endless and "ON" or "off"),
        "superhero=" .. (D.superhero and "ON" or "off"),
        "gold=" .. tostring(D.gold or 0),
        "sp=" .. tostring(D.skill_points or 0),
    }
    local lines = {
        "DEV CHEATS   ( ` or F1 to close )",
        "",
    }
    for _, h in ipairs(HELP) do lines[#lines + 1] = h end
    lines[#lines + 1] = ""
    lines[#lines + 1] = table.concat(flags, "   ")
    lines[#lines + 1] = "> " .. (c.line or "") .. cursor
    if c.msg and c.msg ~= "" then lines[#lines + 1] = "# " .. c.msg end

    local w, h = S(520.0), S(340.0)
    Art.quad(D.hud, "console", sw * 0.5 - w * 0.5, S(48.0), w, h, { 0.03, 0.05, 0.06, 0.94 }, {
        border = { 0.40, 0.95, 0.55, 0.95 }, no_input = true, font_scale = 0.95,
        text_color = { 0.90, 0.99, 0.92, 1.0 },
        label = table.concat(lines, "\n"),
    })
end

return Console
