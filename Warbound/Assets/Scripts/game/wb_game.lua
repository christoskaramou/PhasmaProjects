-- wb_game — orchestrator. Owns the match state, builds the battlefield, and runs
-- the per-frame pipeline: camera -> selection -> orders -> acquire -> move ->
-- attack -> abilities -> visuals -> win/lose -> HUD.

local U = WB.util
local Camera = WB.camera
local World = WB.world
local Units = WB.units
local Economy = WB.economy

local Game = {}

-- Global gameplay time scale. Everything that drives the SIMULATION (movement,
-- combat cadence, ability cooldowns, mana regen, unit animations) ticks on
-- dt * GAME_SPEED, so the whole battle plays out slower/faster without touching
-- the camera or HUD feel (those stay on real dt). 0.5 = half speed.
local GAME_SPEED = 0.5
Game.GAME_SPEED = GAME_SPEED

local state = {
    player_units = {}, enemy_units = {}, all_units = {},
    buildings = {}, reserves = {},
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
    -- Cycle within a bounded set of burst names instead of an ever-growing counter, so
    -- combat (a burst per hit/death) reuses a fixed pool of emitters rather than
    -- spawning unbounded named particle systems — that accumulation was a frame-spike
    -- source during mass deaths.
    fx_counter = (fx_counter % 48) + 1
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
    -- ---- Ironhold (player) warband -------------------------------------------
    { name = "Hero",        arch = "hero",    x = 0.0,  z = 12.0 },
    { name = "Soldier_1",   arch = "soldier", x = -3.0, z = 14.0 },
    { name = "Soldier_2",   arch = "soldier", x = 3.0,  z = 14.0 },
    { name = "Soldier_3",   arch = "soldier", x = -1.6, z = 16.0 },
    { name = "Soldier_4",   arch = "soldier", x = 1.6,  z = 16.0 },
    { name = "Soldier_5",   arch = "soldier", x = -5.0, z = 16.5 },
    { name = "Soldier_6",   arch = "soldier", x = 5.0,  z = 16.5 },
    { name = "Soldier_7",   arch = "soldier", x = -2.6, z = 18.5 },
    { name = "Soldier_8",   arch = "soldier", x = 2.6,  z = 18.5 },
    -- ---- the Wilds (enemy) camp + flanks -------------------------------------
    { name = "Wilds_Grunt_1", arch = "grunt", x = -3.0, z = -16.0 },
    { name = "Wilds_Grunt_2", arch = "grunt", x = 0.0,  z = -17.5 },
    { name = "Wilds_Grunt_3", arch = "grunt", x = 3.0,  z = -16.0 },
    { name = "Wilds_Grunt_4", arch = "grunt", x = -6.5, z = -19.0 },
    { name = "Wilds_Grunt_5", arch = "grunt", x = 6.5,  z = -19.0 },
    { name = "Wilds_Grunt_6", arch = "grunt", x = 0.0,  z = -22.0 },
    { name = "Wilds_Wolf_1",  arch = "wolf",  x = -5.5, z = -13.0 },
    { name = "Wilds_Wolf_2",  arch = "wolf",  x = 5.5,  z = -13.0 },
    { name = "Wilds_Wolf_3",  arch = "wolf",  x = 0.0,  z = -20.0 },
    { name = "Wilds_Wolf_4",  arch = "wolf",  x = -9.0, z = -16.0 },
    { name = "Wilds_Wolf_5",  arch = "wolf",  x = 9.0,  z = -16.0 },
    { name = "Wilds_Wolf_6",  arch = "wolf",  x = -2.5, z = -24.0 },
    { name = "Wilds_Wolf_7",  arch = "wolf",  x = 2.5,  z = -24.0 },
    { name = "Wilds_MineGrunt", arch = "grunt", x = World.mine.x - 3.0, z = World.mine.z + 3.0 },
    { name = "Wilds_MineWolf",  arch = "wolf",  x = World.mine.x + 1.0, z = World.mine.z + 4.0 },
    -- ---- Laborers (start the economy) ----------------------------------------
    { name = "Worker_1",    arch = "worker",  x = -12.0, z = 22.5 },
    { name = "Worker_2",    arch = "worker",  x = -13.5, z = 24.0 },
    { name = "Worker_3",    arch = "worker",  x = -10.5, z = 24.5 },
    -- ---- training reserves: authored offstage, parked at runtime, activated by
    -- buildings when trained (no geometry is created at runtime). --------------
    { name = "Res_Worker_1",  arch = "worker",  x = -28.0, z = 30.0, reserve = true },
    { name = "Res_Worker_2",  arch = "worker",  x = -26.0, z = 30.0, reserve = true },
    { name = "Res_Worker_3",  arch = "worker",  x = -24.0, z = 30.0, reserve = true },
    { name = "Res_Worker_4",  arch = "worker",  x = -28.0, z = 32.0, reserve = true },
    { name = "Res_Worker_5",  arch = "worker",  x = -26.0, z = 32.0, reserve = true },
    { name = "Res_Worker_6",  arch = "worker",  x = -24.0, z = 32.0, reserve = true },
    { name = "Res_Soldier_1", arch = "soldier", x = -18.0, z = 30.0, reserve = true },
    { name = "Res_Soldier_2", arch = "soldier", x = -16.0, z = 30.0, reserve = true },
    { name = "Res_Soldier_3", arch = "soldier", x = -14.0, z = 30.0, reserve = true },
    { name = "Res_Soldier_4", arch = "soldier", x = -18.0, z = 32.0, reserve = true },
    { name = "Res_Soldier_5", arch = "soldier", x = -16.0, z = 32.0, reserve = true },
    { name = "Res_Soldier_6", arch = "soldier", x = -14.0, z = 32.0, reserve = true },
    { name = "Res_Soldier_7", arch = "soldier", x = -12.0, z = 30.0, reserve = true },
    { name = "Res_Soldier_8", arch = "soldier", x = -12.0, z = 32.0, reserve = true },
}

-- Player base structures (authored in the bake; adopted + driven by wb_economy).
-- rally_* is where freshly-trained units appear (just in front of the building).
local BUILDINGS = {
    { name = "TownHall", arch = "town_hall", x = -9.0, z = 26.0, rally_x = -9.0, rally_z = 20.0 },
    { name = "Barracks", arch = "barracks",  x = 9.0,  z = 26.0, rally_x = 9.0,  rally_z = 20.0 },
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
        local u
        if mode == "build" then u = Units.build(r.arch, r.name, r.x, r.z)
        else u = Units.adopt(r.name, r.arch, r.x, r.z) end
        if u then
            if r.reserve then
                -- Park training reserves offstage; the economy activates them later.
                Units.deactivate(u)
                state.reserves[r.arch] = state.reserves[r.arch] or {}
                table.insert(state.reserves[r.arch], u)
            else
                register(u)
            end
        end
    end
end

-- Build/adopt the player base structures into state.buildings (not player_units, so
-- they don't count as food and their loss doesn't end the match).
local function place_buildings(mode)
    for _, b in ipairs(BUILDINGS) do
        local u
        if mode == "build" then u = Units.build(b.arch, b.name, b.x, b.z)
        else u = Units.adopt(b.name, b.arch, b.x, b.z) end
        if u then
            u.trains = Units.ARCH[b.arch] and Units.ARCH[b.arch].trains or nil
            u.rally_x, u.rally_z = b.rally_x, b.rally_z
            u.queue = {}
            state.buildings[#state.buildings + 1] = u
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
    -- Reset match state. The Lua chunk + modules persist across an editor Play -> Stop ->
    -- Play, so init must start from clean lists (not append to the prior session's) or the
    -- second Play double-adopts / runs on stale state.
    state.player_units = {}; state.enemy_units = {}; state.all_units = {}
    state.buildings = {}; state.reserves = {}
    state.hero = nil; state.gold = 150; state.lumber = 80; state.kills = 0
    state.enemy_alive = 0; state.player_alive = 0; state.food_cap = 12
    state.result = nil; state.hero_dead = false; state.time = 0.0
    if WB.selection and WB.selection.clear then WB.selection.clear() end
    if WB.hud and WB.hud.reset then WB.hud.reset() end -- re-show HUD overlay on a fresh play

    if env("WB_BAKE") then
        -- BAKE: build the full static hierarchy (world geometry + all unit + building
        -- rigs) and serialize it to disk. Run once; the result becomes the authored
        -- startup scene that normal runs ADOPT. (scene.save writes Assets/Scenes/<name>.)
        --
        -- CRITICAL: clear the already-loaded startup scene FIRST. The player loads the
        -- previous skirmish.pescene at boot, so without this the bake would serialize
        -- the OLD nodes (including the old HUD's UI_Root) PLUS the freshly-built ones —
        -- duplicates, and build_hud.py then truncates at the stale UI_Root and drops all
        -- the new nodes. scene.clear() (NewScene) drops everything incl. the camera, so
        -- we re-add a camera + re-run the render stage into the clean scene.
        if scene.clear then scene.clear() end
        World.setup_stage()
        if scene.add_camera and scene.set_active_camera then
            local cam = scene.add_camera()
            if cam then scene.set_active_camera(cam) end
        end
        Game.actors_group()
        World.build()
        place_units("build")
        place_buildings("build")
        Camera.init(0.0, 12.0)
        if scene.save then scene.save("baked") end
        if pe_log then pe_log("[Warbound] BAKED authored scene -> Assets/Scenes/baked") end
    else
        -- ADOPT: world geometry + unit/building nodes are authored in skirmish.pescene;
        -- we only wrap them and drive their dynamics. Nothing static is created here.
        World.setup_stage() -- render settings + key light (config, not hierarchy)
        place_units("adopt")
        place_buildings("adopt")
        Economy.init(state)
        Camera.init(0.0, 12.0)
    end

    recount()
    if pe_log then pe_log("[Warbound] match started: " .. state.player_alive .. " vs " .. state.enemy_alive) end

    -- DEV self-demo (WB_DEMO=1): send Laborers to chop lumber and march the warband
    -- into the camp, so a headless smoke run exercises economy + movement -> combat ->
    -- death -> HUD without a human at the mouse. Inert unless the env var is set.
    if env("WB_DEMO") then
        local fighters, workers = {}, {}
        for _, u in ipairs(state.player_units) do
            if u.arch == "worker" then workers[#workers + 1] = u else fighters[#fighters + 1] = u end
        end
        if #workers > 0 then Economy.order_harvest(state, workers, "lumber") end
        WB.selection.set(fighters)
        WB.orders.move_to(fighters, 0.0, -14.0)
        Camera.center_on(0.0, -2.0)
    end
end

function Game.restart()
    for _, u in ipairs(state.all_units) do if u.alive then Units.kill(u) end end
    state.player_units = {}
    state.enemy_units = {}
    state.all_units = {}
    state.buildings = {}
    state.reserves = {}
    state.hero = nil
    state.gold = 150; state.lumber = 80; state.kills = 0
    state.result = nil; state.hero_dead = false; state.time = 0.0
    WB.selection.clear()
    -- Re-wrap the authored unit + building nodes (adopt re-enables + repositions them).
    place_units("adopt")
    place_buildings("adopt")
    Economy.init(state)
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
    -- Gameplay delta: the simulation runs at GAME_SPEED of real time. Camera and
    -- HUD keep real `dt` so panning/scrolling/UI stay crisp. state.time is the
    -- gameplay/animation clock, so walk-bob/swing phases slow down in lockstep.
    local gdt = dt * GAME_SPEED
    state.time = state.time + gdt

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
    Economy.update(gdt, state)   -- sets worker harvest goals + ticks training queues
    WB.orders.locomote(gdt, state.all_units)
    WB.combat.attacks(gdt, state.all_units, state)
    -- Abilities tick on REAL dt: the cooldown is a player-facing clock (an 8s cooldown
    -- must take 8 real seconds, not 16), and mana regen rides the same dt so the cooldown
    -- stays the gate instead of mana lagging behind it.
    WB.abilities.update(dt, state)

    for _, u in ipairs(state.all_units) do Units.tick_visual(u, gdt, state.time) end

    recount()
    if state.enemy_alive <= 0 then state.result = "win" end
    if state.player_alive <= 0 or state.hero_dead then state.result = "lose" end

    WB.hud.update(state)
end

function Game.destroy() end

return Game
