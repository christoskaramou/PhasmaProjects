-- Shadow Puppeteer (PhasmaEngine, Lua). Phase 2: the rules walk the puppet live. A toy paper theatre: drag the brass
-- lantern (sideways and nearer / farther) and slide each prop on its floor track; the props' shadows on the paper are
-- the ground the cut-paper puppet walks on. sp_data.lua: the shared stage geometry and rules numbers (generated from
-- tools/sp_common.py). puppet_rules.lua: the rules (pure Lua). puppet_world.lua: the frame. No HUD or menus yet.
-- Console hooks: puppet.play() restarts the level; puppet.run("win" | "nothing") plays a scripted input;
-- puppet.status() reports; puppet.state_a() / puppet.state_b() show the reference frames (rules paused).
local function module(path)
    local source = assert(fs.read(path), "Missing Shadow Puppeteer module: " .. path)
    return assert(load(source, "@" .. path, "t", _ENV))()
end
local D = module("Scripts/sp_data.lua")
local World = module("Scripts/puppet_world.lua")(D)
local Rules = module("Scripts/puppet_rules.lua")
local Scripts = module("Scripts/puppet_scripts.lua")(D, fs.read)
local min, max = math.min, math.max

local SCREEN = "puppet"
local REF = "1-3"                                  -- the reference level (target.png's stage)
local L = Rules.level(D, REF)
local S = { drag = nil, was_down = false, mode = "play", game = nil, script = nil, clock = 0, level = REF }
_G.puppet = { D = D, W = World, S = S, R = Rules, L = L }

-- the player's input: the lantern and every prop the player moves (x on its track; the balloon: its height)
local function input_now()
    local st = World.state
    local inp = { lantern = { st.lantern[1], st.lantern[2] } }
    for name, p in pairs(L.props) do if p.move ~= "auto" then inp[name] = st[name] end end
    return inp
end
local function set_world(inp)
    local st = World.state
    st.lantern[1], st.lantern[2] = inp.lantern[1], inp.lantern[2]
    for name, p in pairs(L.props) do if p.move ~= "auto" and inp[name] ~= nil then st[name] = inp[name] end end
end
-- the world draws each present prop where the rules have it (the mouse runs by the level's clock)
local function placer(name)
    local g = S.game
    return Rules.prop_place(L, name, input_now(), g and g.t or 0)
end

-- A level from its start: lantern and props where the level puts them, the puppet on its start cliff.
local function play(script, id)
    id = id or S.level
    if id ~= S.level or L.id ~= id then
        L = Rules.level(D, id)
        S.level, _G.puppet.L = id, L
    end
    local ax = {}
    for name, p in pairs(L.props) do if p.move == "z" then ax[name] = p.ax end end
    World.set_level(L.props, placer, ax, id)
    local st = L.start
    World.state.pose = "play"
    local inp = { lantern = st.lantern }
    for name in pairs(L.props) do inp[name] = st[name] end
    set_world(inp)
    S.game = Rules.new_state(L)
    S.script = script and Scripts.for_level(L, script) or nil
    S.mode = "play"
    World.state.candle = 1
    World.apply()
    return "playing " .. id .. (script and (" " .. script) or "")
end

-- the game module starts levels through these; the console goes through the game (puppet.play / run)
_G.puppet.begin = function(id, script) return play(script, id) end
_G.puppet.look = function(which) S.mode = "look"; S.drag = nil; World.set_state(which == "b" and "b" or "a"); return "look " .. tostring(which) end
_G.puppet.levels = function() local t = {}; for i, l in ipairs(D.LEVELS) do t[i] = l.id end; return table.concat(t, " ") end
_G.puppet.status = function()
    local g = S.game
    if not g then return "no game" end
    return string.format("t %.2f x %.4f y %.4f mode %s dir %d star %s won %s dead %s", g.t, g.x, g.y, g.mode, g.dir,
        tostring(g.star), tostring(g.won), tostring(g.dead))
end
-- measurement: freeze the rules (the frame keeps drawing) and show or hide the jointed puppet
_G.puppet.pause = function(on) S.paused = on and true or nil; return "paused " .. tostring(S.paused) end
-- pause the play itself once sim time reaches t (shots of moments shorter than a poll: a 40 ms slide)
_G.puppet.pause_at = function(t) S.pause_at = t; return "pause at " .. tostring(t) end
_G.puppet.is_paused = function() return S.paused and "1" or "0" end
_G.puppet.show_puppet = function(on)
    for _, nm in ipairs(World.PP) do local n = World.N["N_" .. nm]; if n then pcall(function() n:set_enabled(on) end) end end
    return "puppet " .. tostring(on)
end
_G.puppet.state_a = function() _G.puppet.G.manual = true; S.mode = "look"; World.set_state("a"); return "state A" end
_G.puppet.state_b = function() _G.puppet.G.manual = true; S.mode = "look"; World.set_state("b"); return "state B" end
_G.puppet.set = function(t)
    for k, v in pairs(t) do World.state[k] = v end
    World.apply()
    return "set"
end

-- the whole window catches the mouse (above the front card) while a level is played; hidden under the cards
local function catcher(on)
    local sw, sh = World.screen_size()
    runtime_ui.set_quad(SCREEN, "stage", { style = "text", label = "", x = 0, y = 0, width = sw, height = sh, z = 60,
        no_input = not on, visible = on, fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 }, accent = { 0, 0, 0, 0 } })
end

local function controls()
    local st = runtime_ui.get_state(SCREEN, "stage")
    local mx, my = st and st.mouse_x, st and st.mouse_y
    local down = st and st.down
    if down and not S.was_down and mx then
        local what = World.pick(mx, my)
        S.drag = what and World.drag_begin(what, mx, my) or nil
    elseif down and S.drag and mx then
        World.drag_move(S.drag, mx, my)
    elseif not down then
        S.drag = nil
    end
    S.was_down = down
end

-- One frame of play: the rules take whole 120 Hz steps from the frame's time; the input is the stage as the player
-- holds it this frame (or the script at each step's time), so the ground the puppet meets is what is drawn.
local function step_game(dt)
    local g = S.game
    if not g then return end
    if not (g.dead or g.won) then
        if S.script then
            local f = S.script
            Rules.update(L, g, dt, f)
            set_world(f(g.t))
            World.apply()
        else
            local inp = input_now()
            Rules.update(L, g, dt, function() return inp end)
            if World.auto_props then World.apply() end        -- the self-moving mouse: drawn where the rules have it
        end
        if S.pause_at and g.t >= S.pause_at then S.paused, S.pause_at = true, nil end
        if g.dead or g.won then g.t_end = S.clock end
        World.state.candle = 1 - min(1, g.t / (L.candle_s or L.rules.candle_s))
        World.place_candle(World.state.candle)
    end
    World.pose_puppet(g, S.clock)
end

runtime_ui.clear(SCREEN)
runtime_ui.set_screen_overlay(SCREEN, true)
runtime_ui.show(SCREEN)
World.init()
_G.puppet.Scripts = Scripts
local Game = module("Scripts/puppet_game.lua")(_G.puppet, module("Scripts/Lib/settings_menu.lua"))
_G.puppet.G = Game
-- console: puppet.play(id) / puppet.run(script) start a level through the game (cards and saves as for a player)
_G.puppet.play = function(id) return Game.start_level(id) end
-- puppet.run(name[, id]): "solution" (the level's), "nothing" (it must lose), "win" (the reference level's drag)
_G.puppet.run = function(name, id)
    assert(Scripts.names[name], "no script " .. tostring(name))
    return Game.start_level(id or (name == "win" and REF) or S.level, name)
end
Game.to_title()

local last_w, last_h, catching
script.on_update("puppet", function()
    local dt = min(0.25, max(0, engine.get_metrics().delta_ms / 1000))
    S.clock = S.clock + dt
    World.update(dt)
    -- the game decides: live = a level is being played (no card, no pause, no menu); the console's look frames
    -- (Game.manual) keep the drags for measuring
    local live = Game.update(dt)
    local drags = live or Game.manual
    local sw, sh = World.screen_size()
    if sw ~= last_w or sh ~= last_h or drags ~= catching then last_w, last_h, catching = sw, sh, drags; catcher(drags) end
    if drags then controls() else S.drag, S.was_down = nil, false end
    if S.mode == "play" and not S.paused and not Game.hold and (live or Game.manual or Game.mode == "won" or Game.mode == "lost") then
        step_game(dt)
        Game.after_step()
    elseif S.mode == "play" and S.game and Game.hold then
        World.pose_puppet(S.game, S.clock)         -- the rules wait under a guide: the puppet stands where it is
    end
end, "play")

print("[ShadowPuppeteer] Title card up. Console: puppet.play('1-1'), puppet.run('win'), puppet.state_a().")
