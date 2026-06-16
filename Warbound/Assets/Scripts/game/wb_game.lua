-- wb_game — orchestrator. Owns the match state, builds the battlefield, and runs
-- the per-frame pipeline: camera -> selection -> orders -> acquire -> move ->
-- attack -> abilities -> visuals -> win/lose -> HUD.

local U = WB.util
local Camera = WB.camera
local World = WB.world
local Units = WB.units

local Game = {}

local state = {
    player_units = {}, enemy_units = {}, all_units = {},
    hero = nil, gold = 150, lumber = 80, kills = 0,
    enemy_alive = 0, player_alive = 0, food_cap = 12,
    result = nil, time = 0.0,
}
Game.state = state

local actors = nil
local prev_r = false

function Game.actors_group()
    if not U.valid(actors) then actors = U.group("Actors", nil) end
    return actors
end

function Game.player_units() return state.player_units end
function Game.enemy_units() return state.enemy_units end
function Game.hero() return state.hero end

-- ---- particle FX (non-critical eye-candy; safe no-ops if unavailable) ----------

local fx_counter = 0
local function emit(preset, x, y, z, opts)
    if not (particles and particles.emit_burst) then return end
    opts = opts or {}
    fx_counter = fx_counter + 1
    pcall(particles.emit_burst, {
        preset = preset,
        name = "wbfx_" .. fx_counter,
        position = vec3(x, y or 0.4, z),
        count = opts.count or 10,
        life_min = 0.05, life_max = opts.life or 0.25,
        spawn_radius = opts.r or 0.3,
        size_max = opts.size or 0.2,
    })
end

WB.fx_ping = function(x, z, is_attack) emit(is_attack and "enemy_take" or "hero_take", x, 0.2, z, { count = 8, r = 0.4 }) end
WB.fx_hit = function(x, z) emit("enemy_take", x, 0.8, z, { count = 6, r = 0.25, life = 0.18 }) end
WB.fx_death = function(x, z) emit("enemy_take", x, 0.6, z, { count = 16, r = 0.5, life = 0.35, size = 0.28 }) end
WB.fx_levelup = function(x, z) emit("hero_take", x, 1.0, z, { count = 24, r = 0.7, life = 0.6, size = 0.3 }) end
WB.fx_stomp = function(x, z, radius) emit("enemy_take", x, 0.3, z, { count = 30, r = (radius or 5) * 0.6, life = 0.4, size = 0.35 }) end

-- ---- roster -------------------------------------------------------------------
-- Every actor is authored in the scene hierarchy under unique node names. The same
-- roster drives BAKING (build the rigs once, scene.save) and ADOPTING (find the
-- authored nodes at runtime and drive only their dynamics).

local ROSTER = {
    { name = "Hero",        arch = "hero",    x = 0.0,  z = 12.0 },
    { name = "Soldier_1",   arch = "soldier", x = -3.0, z = 14.0 },
    { name = "Soldier_2",   arch = "soldier", x = 3.0,  z = 14.0 },
    { name = "Soldier_3",   arch = "soldier", x = -1.6, z = 16.0 },
    { name = "Soldier_4",   arch = "soldier", x = 1.6,  z = 16.0 },
    { name = "Wilds_Grunt_1", arch = "grunt", x = -3.0, z = -16.0 },
    { name = "Wilds_Grunt_2", arch = "grunt", x = 0.0,  z = -17.5 },
    { name = "Wilds_Grunt_3", arch = "grunt", x = 3.0,  z = -16.0 },
    { name = "Wilds_Wolf_1",  arch = "wolf",  x = -5.5, z = -13.0 },
    { name = "Wilds_Wolf_2",  arch = "wolf",  x = 5.5,  z = -13.0 },
    { name = "Wilds_Wolf_3",  arch = "wolf",  x = 0.0,  z = -20.0 },
    { name = "Wilds_MineGrunt", arch = "grunt", x = World.mine.x - 3.0, z = World.mine.z + 2.0 },
    { name = "Wilds_MineWolf",  arch = "wolf",  x = World.mine.x + 1.0, z = World.mine.z + 3.0 },
}

local function register(u)
    if not u then return end
    state.all_units[#state.all_units + 1] = u
    if u.faction == "player" then
        state.player_units[#state.player_units + 1] = u
        if u.is_hero then state.hero = u end
    else
        state.enemy_units[#state.enemy_units + 1] = u
    end
end

-- mode = "build" (create rigs for baking) | "adopt" (wrap authored scene nodes).
local function place_units(mode)
    for _, r in ipairs(ROSTER) do
        if mode == "build" then
            register(Units.build(r.arch, r.name, r.x, r.z))
        else
            register(Units.adopt(r.name, r.arch, r.x, r.z))
        end
    end
end

local function recount()
    state.player_alive = 0
    state.enemy_alive = 0
    for _, u in ipairs(state.player_units) do if u.alive then state.player_alive = state.player_alive + 1 end end
    for _, e in ipairs(state.enemy_units) do if e.alive then state.enemy_alive = state.enemy_alive + 1 end end
end

-- ---- lifecycle ----------------------------------------------------------------

local function env(name)
    return os and os.getenv and os.getenv(name)
end

function Game.init()
    World.setup_stage() -- render settings + key light (config, not hierarchy)

    if env("WB_BAKE") then
        -- BAKE: build the full static hierarchy (world geometry + all unit rigs) and
        -- serialize it to disk. Run once; the result becomes the authored startup
        -- scene that normal runs ADOPT. (scene.save writes Assets/Scenes/<name>.)
        Game.actors_group()
        World.build()
        place_units("build")
        Camera.init(0.0, 12.0)
        if scene.save then scene.save("baked") end
        if pe_log then pe_log("[Warbound] BAKED authored scene -> Assets/Scenes/baked") end
    else
        -- ADOPT: world geometry + unit nodes are authored in skirmish.pescene; we only
        -- wrap the unit nodes and drive their dynamics. Nothing static is created here.
        place_units("adopt")
        Camera.init(0.0, 12.0)
    end

    recount()
    state.food_cap = 12
    if pe_log then pe_log("[Warbound] match started: " .. state.player_alive .. " vs " .. state.enemy_alive) end

    -- DEV self-demo (WB_DEMO=1): select the warband and attack-move into the camp so a
    -- headless smoke run exercises movement -> combat -> death -> selection HUD without
    -- a human at the mouse. Inert unless the env var is set.
    if env("WB_DEMO") then
        WB.selection.set(state.player_units)
        WB.orders.move_to(state.player_units, 0.0, -15.0)
        Camera.center_on(0.0, -13.0)
    end
end

function Game.restart()
    for _, u in ipairs(state.all_units) do if u.alive then Units.kill(u) end end
    state.player_units = {}
    state.enemy_units = {}
    state.all_units = {}
    state.hero = nil
    state.gold = 150; state.lumber = 80; state.kills = 0
    state.result = nil; state.hero_dead = false; state.time = 0.0
    WB.selection.clear()
    -- Re-wrap the authored unit nodes (Units.adopt re-enables + repositions them).
    place_units("adopt")
    recount()
    Camera.center_on(0.0, 12.0)
    if pe_log then pe_log("[Warbound] match restarted") end
end

local function window_size()
    if engine and engine.get_window_size then
        local s = engine.get_window_size()
        if s and s.w and s.w > 0 then return s.w, s.h end
    end
    return 1920.0, 1080.0
end

local function r_pressed()
    local down = input and input.is_key_down and input.is_key_down("r") == true
    local was = prev_r
    prev_r = down
    return down and not was
end

function Game.update(dt)
    state.time = state.time + dt

    -- mouse-over-HUD test (suppress world clicks / edge scroll under the bar)
    local mx, my = nil, nil
    if input and input.get_mouse_position then
        local m = input.get_mouse_position(); if m and m.x then mx, my = m.x, m.y end
    end
    local ww, wh = window_size()
    local mouse_in_ui = WB.hud.point_in_ui(mx or -1, my or -1, ww, wh)

    Camera.update(dt, mouse_in_ui)

    if state.result then
        if r_pressed() then Game.restart() end
        WB.hud.update(state)
        return
    end

    WB.selection.update(state.player_units, mouse_in_ui)
    WB.orders.handle_input(WB.selection.list, state.enemy_units, mouse_in_ui)
    WB.combat.acquire(state.player_units, state.enemy_units)
    WB.orders.locomote(dt, state.all_units)
    WB.combat.attacks(dt, state.all_units, state)
    WB.abilities.update(dt, state)

    for _, u in ipairs(state.all_units) do Units.tick_visual(u, dt, state.time) end

    recount()
    if state.enemy_alive <= 0 then state.result = "win" end
    if state.player_alive <= 0 or state.hero_dead then state.result = "lose" end

    WB.hud.update(state)
end

function Game.destroy() end

return Game
