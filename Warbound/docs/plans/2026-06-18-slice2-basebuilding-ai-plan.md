# Warbound Slice 2 — Base-building + Wilds Build AI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add player building placement + rally points and a full mirrored Wilds build AI to Warbound, with a raze-the-base win condition — all in Lua, on top of a single scene re-bake.

**Architecture:** Faction-parameterized — player and Wilds run the *same* economy/build/combat code; only the order-issuer differs (mouse/HUD for the player, a `wb_ai` brain for the Wilds). Everything that appears at runtime is a rig pre-authored offstage in the bake and revived with `set_visible`/`Units.activate` (no runtime geometry, per the engine rule). Two new modules: `wb_build` (placement + worker construction, shared) and `wb_ai` (Wilds decision brain).

**Tech Stack:** Lua 5.4 (sol2 bindings) on PhasmaEngine; scene authored via `WB_BAKE` + `scene.save`; HUD via `runtime_ui`; verification by launching PhasmaPlayer and asserting on `PhasmaEngine.log`.

## Global Constraints

- **No runtime geometry creation.** Never `primitives.*`/`U.part`/`U.group` at runtime in play mode. New buildings/units come from offstage reserves authored in the bake and shown via `set_visible(true)` / `Units.activate`. (Verified spike-safe: `set_visible` is the cheap cull-flag path; `set_enabled` forces a synchronous raster-instance rebuild — see commit `c5e3867`.)
- **Re-bake discipline:** bake runs in the player with `WB_BAKE=1`; `Game.init` must `scene.clear()` FIRST, rebuild world+units+buildings, `scene.save("baked")`. Then rename `Assets/Scenes/baked` → `Assets/Scenes/skirmish.pescene` and re-run `python tools/build_hud.py`. `build_hud.py` truncates at the first authored `UI_Root`, so a clean bake must contain none.
- **Module load order** (in `Assets/Scripts/Player/warbound.lua` `preload{}`): `util, world, camera, units, selection, orders, combat, abilities, economy, build, ai, hud, game`. A module's load-time `local X = WB.x` captures require its deps preloaded first.
- **Lua vec3 is float32** — keep big-coordinate math in plain numbers; only build `vec3` at the final `set_position`.
- **No `delete_node` mid-combat** — dead/parked rigs are hidden via `set_visible(false)` + moved to `PARK_Y`, never deleted.
- **Bake scale once** at creation; per-frame writes are position/rotation/material/visibility only.
- **Playtest build:** `build-ninja-full-tracy\Debug` on `--display 1` (per project rule). The tracy-Release build (`build-ninja-full-tracy\Release`) was observed stable on 2026-06-18 and is faster to iterate; either works for headless log runs, Debug is the safe default.
- **Commits:** never commit unless the user says "commit". Leave each task's work as an unstaged diff; the per-task "Commit" step means *stage + draft message*, executed only on the user's go-ahead. **Never add `Co-Authored-By` lines.**

## Verification model (read once)

There is no Lua unit-test harness. Each task's "test" is a **scripted launch + log assertion**, the same method that validated the perf fix:

```powershell
# VERIFY-LAUNCH (PowerShell). $SCN = env flags for the scenario under test.
$dir = "C:\Users\Christos\repos\PhasmaEngine\build-ninja-full-tracy\Debug"
Get-Process PhasmaPlayer,PhasmaEditor -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 1
Remove-Item "$dir\PhasmaEngine.log" -Force -ErrorAction SilentlyContinue
$env:WB_DEMO='1'        # plus any scenario flags the task names
$p = Start-Process "$dir\PhasmaPlayer.exe" -ArgumentList '--api','vulkan','--display','1' -WorkingDirectory $dir -PassThru
Start-Sleep 30
if ($p.HasExited) { "EXITED 0x{0:X8}" -f $p.ExitCode } else { "ALIVE"; Stop-Process -Id $p.Id -Force }
```

Then assert with Grep on `$dir\PhasmaEngine.log`:
- **PASS gate (every task):** the log contains `Scene loaded from:` and `[Warbound] match started:` and contains **no** `update error` / `init failed` / `[ERROR]` / `[Lua] ... error` lines.
- Plus the **task-specific assertion** lines listed in that task (new `pe_log` lines the task adds — these are permanent, operationally-useful INFO logs, not test-only scaffolding).

`pe_log(msg)` writes `[INFO] [Lua] <msg>`. Use it for assertions. Scenario env flags introduced by this plan (all read in `wb_game`): `WB_DEMO` (existing self-demo), `WB_BAKE` (existing bake), `WB_TEST_BUILD` (player auto-builds one of each building, Stage 3), `WB_AI=0` (disable the AI brain to isolate, Stage 7). These are dev harness flags like the existing `WB_DEMO` and stay in the code.

---

## File Structure

**New files:**
- `Assets/Scripts/game/wb_build.lua` — placement-mode state + worker-construction state machine; faction-agnostic. Consumed by `wb_hud` (player) and `wb_ai` (Wilds).
- `Assets/Scripts/game/wb_ai.lua` — Wilds decision brain (economy / build order / army / combat director). Issues orders to `state.econ.enemy` via `wb_economy`/`wb_build`/`wb_orders`.

**Modified files:**
- `wb_game.lua` — `state.econ`, expanded `ROSTER`/`BUILDINGS`, faction-aware `place_units`/`place_buildings`, `update` pipeline gains `Build.update` + `AI.update`, win/lose rework, `recount` tracks town halls, new env flags, bake branch.
- `wb_economy.lua` — every function takes an econ handle `E` instead of implicit player; per-faction reserves; `Economy.econ(state, faction)` accessor.
- `wb_units.lua` — new archetypes (`farm`, `tower`, `enemy_town_hall`, `enemy_barracks`, `enemy_farm`, `enemy_tower`, `wilds_worker`); building combat fields (`dps`/`range`/`interval` on towers); `Units.building_at` stays.
- `wb_combat.lua` — tower-fire pass, buildings as acquirable targets, `Combat.die` building branch, `Combat.standing_town_halls(E)`.
- `wb_orders.lua` — `order="build"` locomotion + rally-issue on building selection; attack-move targets enemy buildings.
- `wb_selection.lua` — keep single-building select; expose nothing new (build menu lives in HUD).
- `wb_world.lua` — `World.wilds_mine` / `World.wilds_forest` + scenery clear zones; `node_pos` extended.
- `wb_hud.lua` — Build sub-card, placement banner, site progress bar, rally markers, enemy buildings on minimap; reads `state.econ.player`.
- `wb_util.lua` — enemy-building colors (`enemy_stone`, `enemy_roof`).
- `Assets/Scripts/Player/warbound.lua` — `preload{}` gains `build`, `ai`.

**Re-baked artifact:** `Assets/Scenes/skirmish.pescene` (regenerated in Stage 2; HUD re-appended via `tools/build_hud.py`).

---

## Stage 0 — Faction-neutral economy (behavior-preserving refactor)

### Task 0: Introduce `state.econ` and parameterize the economy

**Files:**
- Modify: `Assets/Scripts/game/wb_game.lua` (state table, `register`, `place_units`, `place_buildings`, `recount`, `init`, `restart`)
- Modify: `Assets/Scripts/game/wb_economy.lua` (all functions)
- Modify: `Assets/Scripts/game/wb_hud.lua` (`drive_top` reads `state.econ.player`)
- Modify: `Assets/Scripts/game/wb_orders.lua` (harvest deposit reads econ)
- Modify: `Assets/Scripts/game/wb_combat.lua` (`Combat.die` bounty credits `state.econ.enemy`→player gold)

**Interfaces:**
- Produces: `state.econ = { player = E, enemy = E }`, each `E = { faction, gold, lumber, food_cap, buildings = {}, units = <list ref>, unit_reserves = {}, building_reserves = {} }`.
- Produces: `Economy.econ(state, faction) -> E`; `Economy.food_used(E)`, `Economy.food_queued(E)`, `Economy.train_status(state, E, b)`, `Economy.try_train(state, E, b)`, `Economy.order_harvest(E, workers, kind)`, `Economy.update(dt, state)` (iterates both econs).
- Consumes (later stages): `state.econ`, the `E` shape, `Economy.*`.

- [ ] **Step 1: Define the econ state shape in `wb_game.lua`.** Replace the flat `gold/lumber/food_cap` fields. New `state`:

```lua
local state = {
    player_units = {}, enemy_units = {}, all_units = {},
    hero = nil, kills = 0,
    enemy_alive = 0, player_alive = 0,
    result = nil, time = 0.0, hero_dead = false,
    econ = nil, -- built in reset_state()
}

local function reset_state()
    state.player_units = {}; state.enemy_units = {}; state.all_units = {}
    state.hero = nil; state.kills = 0
    state.enemy_alive = 0; state.player_alive = 0
    state.result = nil; state.hero_dead = false; state.time = 0.0
    state.econ = {
        player = { faction = "player", gold = 150, lumber = 80, food_cap = 0,
                   buildings = {}, units = state.player_units, unit_reserves = {}, building_reserves = {} },
        enemy  = { faction = "enemy",  gold = 150, lumber = 80, food_cap = 0,
                   buildings = {}, units = state.enemy_units, unit_reserves = {}, building_reserves = {} },
    }
end
```

Call `reset_state()` at the top of both `Game.init` and `Game.restart` (replacing the inline field resets). Keep `Game.state = state`.

- [ ] **Step 2: Parameterize `wb_economy.lua`.** Change the signatures to take `E` (or `state`+`E`). Key rewrites (full bodies):

```lua
function Economy.econ(state, faction) return state.econ and state.econ[faction] or nil end

local function nearest_dropoff(E, x, z)
    local best, bd
    for _, b in ipairs(E.buildings) do
        if b.alive and b.state ~= "site" and (b.food_cap or 0) >= 0 and b.is_dropoff then
            local d = U.dist2_sq(x, z, b.x, b.z)
            if not bd or d < bd then best, bd = b, d end
        end
    end
    return best
end

function Economy.food_used(E)
    local n = 0
    for _, u in ipairs(E.units) do if u.alive then n = n + 1 end end
    return n
end

function Economy.food_queued(E)
    local n = 0
    for _, b in ipairs(E.buildings) do if b.alive and b.queue then n = n + #b.queue end end
    return n
end
```

`is_dropoff` is a new archetype flag (town halls = true); set it in Stage 1. Until then, treat any non-site building with `trains == "worker"` as a drop-off — but cleaner to add `is_dropoff` now to the existing `town_hall` arch (one-line, Stage 1 formalizes per faction).

- [ ] **Step 3: Make `train_status`/`try_train`/`spawn_trained` econ-keyed.** Full bodies:

```lua
function Economy.train_status(state, E, b)
    local def = b and b.trains and TRAIN[b.trains]
    if not def then return "none" end
    if (E.gold or 0) < def.gold then return "gold" end
    if (E.lumber or 0) < def.lumber then return "lumber" end
    if Economy.food_used(E) + Economy.food_queued(E) + def.food > (E.food_cap or 0) then return "food" end
    local pool = E.unit_reserves[b.trains]
    if not pool or #pool == 0 then return "reserve" end
    return "ok"
end

function Economy.try_train(state, E, b)
    if Economy.train_status(state, E, b) ~= "ok" then return false end
    local def = TRAIN[b.trains]
    E.gold = E.gold - def.gold; E.lumber = E.lumber - def.lumber
    b.queue = b.queue or {}
    b.queue[#b.queue + 1] = { arch = b.trains, t = def.time, total = def.time }
    return true
end

local function spawn_trained(state, E, b, arch)
    local pool = E.unit_reserves[arch]
    local u = pool and table.remove(pool) or nil
    if not u then return end
    local rx = (b.rally_x or b.x) + (b.spawn_n or 0) % 3 * 1.6 - 1.6
    local rz = (b.rally_z or (b.z - 6.0))
    b.spawn_n = (b.spawn_n or 0) + 1
    rx, rz = World.clamp(rx, rz, 1.0)
    Units.activate(u, rx, rz)
    state.all_units[#state.all_units + 1] = u
    E.units[#E.units + 1] = u
    -- rally walk wired in Stage 6
end
```

- [ ] **Step 4: Make `Economy.update` iterate both econs.** Full body:

```lua
function Economy.update(dt, state)
    for _, fac in ipairs({ "player", "enemy" }) do
        local E = state.econ[fac]
        local cap = 0
        for _, b in ipairs(E.buildings) do
            if b.alive and b.state ~= "site" then cap = cap + (b.food_cap or 0) end
        end
        E.food_cap = cap
        for _, u in ipairs(E.units) do
            if u.alive and u.arch_is_worker and u.job then tick_worker(u, dt, state, E) end
        end
        for _, b in ipairs(E.buildings) do
            if b.alive and b.state ~= "site" and b.queue and #b.queue > 0 then
                local job = b.queue[1]; job.t = job.t - dt
                if job.t <= 0.0 then table.remove(b.queue, 1); spawn_trained(state, E, b, job.arch) end
            end
        end
    end
end
```

`tick_worker(u, dt, state, E)` deposits into `E` (gold/lumber). Add `arch_is_worker` to the unit table in `wb_units.make_unit_table` (`unit.arch_is_worker = arch.is_worker == true`) and set `is_worker = true` on the `worker` and (Stage 1) `wilds_worker` archetypes. Update `tick_worker`'s deposit lines to `E.gold = (E.gold or 0) + u.carry` / `E.lumber = ...`.

- [ ] **Step 5: Update callers to econ.** In `wb_game.update`, change `Economy.update(gdt, state)` (already takes state — keep). In `wb_combat.Combat.die`, the enemy-kill bounty currently does `state.gold = state.gold + bounty`; change to `state.econ.player.gold = state.econ.player.gold + bounty`. In `wb_hud.drive_top`, change `state.gold`/`state.lumber`/`state.food_cap`/`state.player_alive` to read `local PE = state.econ.player` → `PE.gold`, `PE.lumber`, `PE.food_cap`. In `wb_orders.handle_input` harvest path, change `WB.economy.order_harvest(WB.economy._state, ...)` to `WB.economy.order_harvest(state.econ.player, workers, kind)` and update `Economy.order_harvest(E, workers, kind)` to store `u.job` (unchanged logic, no `_state` global). In `wb_game.init`'s `WB_DEMO` block, `Economy.order_harvest(state.econ.player, workers, "lumber")`.

- [ ] **Step 6: Verify parity.** Run VERIFY-LAUNCH with `WB_DEMO=1`. Assert log has `[Warbound] match started:` and (existing) harvest behavior: add a temporary one-shot `pe_log(string.format("[econ] player gold=%d lumber=%d food=%d/%d", PE.gold, PE.lumber, Economy.food_used(PE), PE.food_cap))` at the end of `Economy.update` gated to fire once per ~2s (reuse a timer). Expect lumber to climb from 80 as workers deposit (same as pre-refactor), food `12/20` (TownHall 12 + Barracks 8), 0 errors.

Expected log lines:
```
[Warbound] match started: 12 vs 15
[econ] player gold=150 lumber=88 food=12/20   (lumber climbing across windows)
```

- [ ] **Step 7: Commit.** Stage `wb_game.lua wb_economy.lua wb_hud.lua wb_orders.lua wb_combat.lua wb_units.lua`. Draft message: `Warbound: faction-neutral economy state (state.econ), no behavior change`.

---

## Stage 1 — New archetypes + colors

### Task 1: Add building/worker archetypes for both factions

**Files:**
- Modify: `Assets/Scripts/game/wb_util.lua` (add `COLOR.enemy_stone`, `COLOR.enemy_roof`)
- Modify: `Assets/Scripts/game/wb_units.lua` (`Units.ARCH` additions; `make_unit_table` flags)

**Interfaces:**
- Produces archetypes: `farm`, `tower`, `enemy_town_hall`, `enemy_barracks`, `enemy_farm`, `enemy_tower`, `wilds_worker`.
- Produces unit-table flags: `arch_is_worker`, `is_building`, `is_dropoff`, and on towers `dps`/`range`/`interval`.

- [ ] **Step 1: Add enemy building colors** to `wb_util.lua` `COLOR` (red/brown). Match the existing color-table style:

```lua
enemy_stone = { 0.34, 0.20, 0.18 }, enemy_roof = { 0.55, 0.16, 0.12 },
```

- [ ] **Step 2: Add the `farm` and `tower` archetypes** to `Units.ARCH` (player). Full entries (rigs follow the existing primitive-rig style; keep footprints small):

```lua
farm = {
    faction = "player", display = "Farm", hp = 500, dps = 0, range = 0.0, interval = 1.0,
    speed = 0.0, armor = 0.3, radius = 1.8, scale = 1.0, bounty = 0,
    is_building = true, no_combat = true, food_cap = 6,
    rig = {
        { kind = "cube", name = "Base", pos = { 0.0, 0.5, 0.0 }, scale = { 3.0, 1.0, 3.0 }, color = C.stone, emissive = 0.07 },
        { kind = "cube", name = "Crop", pos = { 0.0, 1.1, 0.0 }, scale = { 2.6, 0.3, 2.6 }, color = C.tree_leaf, emissive = 0.10 },
        { kind = "cube", name = "Post", pos = { 1.2, 0.9, 1.2 }, scale = { 0.2, 1.0, 0.2 }, color = C.tree_trunk, emissive = 0.05 },
    },
},
tower = {
    faction = "player", display = "Guard Tower", hp = 700, dps = 22, range = 9.0, interval = 1.1,
    speed = 0.0, armor = 0.35, radius = 1.6, scale = 1.0, bounty = 0,
    is_building = true, weapon = nil,
    rig = {
        { kind = "cylinder", name = "Shaft", pos = { 0.0, 2.0, 0.0 }, scale = { 1.6, 4.0, 1.6 }, color = C.stone, emissive = 0.07 },
        { kind = "cube", name = "Crown", pos = { 0.0, 4.2, 0.0 }, scale = { 2.0, 0.6, 2.0 }, color = C.stone_dark, emissive = 0.08 },
        { kind = "cube", name = "Banner", pos = { 0.0, 3.4, 1.0 }, scale = { 0.8, 1.0, 0.12 }, color = C.player_trim, emissive = 0.2 },
    },
},
```

`tower` has `dps/range/interval` and `is_building` but NOT `no_combat` (it fights). Note: towers never move (`speed=0`); locomote already early-outs on no order.

- [ ] **Step 3: Add `is_dropoff = true` to the player `town_hall` arch** (so `nearest_dropoff` finds it), and `is_worker = true` to `worker`.

- [ ] **Step 4: Add the enemy archetypes** — `enemy_town_hall`, `enemy_barracks`, `enemy_farm`, `enemy_tower`, `wilds_worker`. These mirror the player rigs with enemy colors. To stay DRY, add a helper at the top of the ARCH section that recolors a copy:

```lua
-- Build an enemy variant of a player building arch: same rig shape, enemy colors/faction.
local function enemy_variant(base, display, trains)
    local a = {}
    for k, v in pairs(base) do a[k] = v end
    a.faction = "enemy"; a.display = display; a.trains = trains
    a.rig = {}
    for i, part in ipairs(base.rig) do
        local p = {}; for k, v in pairs(part) do p[k] = v end
        if p.color == C.stone or p.color == C.stone_dark then p.color = C.enemy_stone end
        if p.color == C.roof then p.color = C.enemy_roof end
        if p.color == C.player or p.color == C.player_trim then p.color = C.enemy end
        a.rig[i] = p
    end
    return a
end
```

Then (placed AFTER the player `town_hall`/`barracks`/`farm`/`tower` are defined in the table — so define enemy variants in a second `Units.ARCH.x = enemy_variant(...)` block after the table literal):

```lua
Units.ARCH.enemy_town_hall = enemy_variant(Units.ARCH.town_hall, "Wilds Den", "wilds_worker")
Units.ARCH.enemy_town_hall.is_dropoff = true
Units.ARCH.enemy_barracks  = enemy_variant(Units.ARCH.barracks,  "Wilds Pit", "grunt")
Units.ARCH.enemy_farm      = enemy_variant(Units.ARCH.farm,      "Wilds Pen", nil)
Units.ARCH.enemy_tower     = enemy_variant(Units.ARCH.tower,     "Wilds Spire", nil)
Units.ARCH.enemy_tower.dps = 20

Units.ARCH.wilds_worker = (function()
    local w = {}; for k, v in pairs(Units.ARCH.worker) do w[k] = v end
    w.faction = "enemy"; w.display = "Ravager"
    -- reuse the worker rig but tint via enemy colors at bake by cloning rig parts
    w.rig = {}
    for i, part in ipairs(Units.ARCH.worker.rig) do
        local p = {}; for k, v in pairs(part) do p[k] = v end
        if p.color == C.worker or p.color == C.worker_trim then p.color = C.enemy end
        w.rig[i] = p
    end
    return w
end)()
```

Add a `TRAIN.grunt` entry in `wb_economy.lua` (the Wilds barracks trains grunts): `grunt = { gold = 70, lumber = 0, food = 1, time = 8.0, label = "Train Raider", letter = "G" }`, and `wilds_worker = { gold = 50, lumber = 0, food = 1, time = 6.0, label = "Train Ravager", letter = "F" }`.

- [ ] **Step 5: Set unit-table flags** in `make_unit_table` (`wb_units.lua`): after building `unit`, add `unit.arch_is_worker = arch.is_worker == true`, `unit.is_dropoff = arch.is_dropoff == true`. Buildings already get `is_building`. For towers, the existing `dps/range/interval/radius` copy already covers combat fields (they read from `arch`).

- [ ] **Step 6: Verify the archetypes load.** Add `pe_log(string.format("[arch] count=%d farm=%s tower_dps=%s enemy_hall=%s", (function() local n=0 for _ in pairs(Units.ARCH) do n=n+1 end return n end)(), tostring(Units.ARCH.farm~=nil), tostring(Units.ARCH.tower.dps), tostring(Units.ARCH.enemy_town_hall~=nil)))` once in `Game.init`. Run VERIFY-LAUNCH (`WB_DEMO=1`). Expect:

```
[arch] count=13 farm=true tower_dps=22 enemy_hall=true
```
0 errors, `match started` still 12 vs 15 (roster unchanged until Stage 2). Remove the temporary `[arch]` log after confirming (it's a one-shot sanity check, not operational).

- [ ] **Step 7: Commit.** Stage `wb_util.lua wb_units.lua wb_economy.lua`. Message: `Warbound: add farm/tower + enemy building & worker archetypes`.

---

## Stage 2 — Wilds world nodes + roster expansion + re-bake

### Task 2a: Wilds resource nodes in the world

**Files:** Modify `Assets/Scripts/game/wb_world.lua`, `Assets/Scripts/game/wb_economy.lua` (`node_pos`).

**Interfaces:** Produces `World.wilds_mine = {x,z}`, `World.wilds_forest = {x,z}`; `Economy.resource_near`/`node_pos` resolve per-faction nodes.

- [ ] **Step 1: Add Wilds node coords** near the camp (south) in `wb_world.lua`:

```lua
World.wilds_mine = { x = -22.0, z = -24.0 }
World.wilds_forest = { x = 20.0, z = -22.0 }
```

- [ ] **Step 2: Build the Wilds nodes in `World.build`** — call `make_gold_mine(root, World.wilds_mine.x, World.wilds_mine.z)` and `make_forest(root, World.wilds_forest.x, World.wilds_forest.z)` alongside the player ones, and add both to `clear_of_structures` exclusion zones (same `dist2 <= 8/9` guards). These run only in the bake.

- [ ] **Step 3: Make `node_pos` faction-aware** in `wb_economy.lua`. A worker harvests from its faction's nodes:

```lua
local function node_pos(kind, faction)
    if faction == "enemy" then
        if kind == "gold" then return World.wilds_mine.x, World.wilds_mine.z end
        if kind == "lumber" and World.wilds_forest then return World.wilds_forest.x, World.wilds_forest.z end
    else
        if kind == "gold" then return World.mine.x, World.mine.z end
        if kind == "lumber" and World.forest then return World.forest.x, World.forest.z end
    end
    return nil
end
```

Thread `faction` through `Economy.order_harvest(E, workers, kind)` (use `E.faction`) and `tick_worker` (use the unit's faction). `Economy.resource_near(gx, gz, faction)` checks that faction's nodes (player path passes `"player"`).

### Task 2b: Expand ROSTER + BUILDINGS, faction-aware placement

**Files:** Modify `Assets/Scripts/game/wb_game.lua`.

- [ ] **Step 1: Expand `BUILDINGS`** with the Wilds starting base + per-faction reserve pools. Add a `faction` and `reserve` field; reserves are parked offstage and deactivated like unit reserves:

```lua
local BUILDINGS = {
    -- player starting base
    { name = "TownHall", arch = "town_hall", faction = "player", x = -9.0, z = 26.0, rally_x = -9.0, rally_z = 20.0 },
    { name = "Barracks", arch = "barracks",  faction = "player", x = 9.0,  z = 26.0, rally_x = 9.0,  rally_z = 20.0 },
    -- Wilds starting base (south)
    { name = "WildsHall",     arch = "enemy_town_hall", faction = "enemy", x = -3.0, z = -28.0, rally_x = -3.0, rally_z = -22.0 },
    { name = "WildsBarracks", arch = "enemy_barracks",  faction = "enemy", x = 6.0,  z = -28.0, rally_x = 6.0,  rally_z = -22.0 },
    -- player building reserves (offstage, activated on placement)
    { name = "PRes_townhall_1", arch = "town_hall", faction = "player", x = -40, z = 36, reserve = true },
    { name = "PRes_townhall_2", arch = "town_hall", faction = "player", x = -37, z = 36, reserve = true },
    { name = "PRes_barracks_1", arch = "barracks",  faction = "player", x = -34, z = 36, reserve = true },
    { name = "PRes_barracks_2", arch = "barracks",  faction = "player", x = -31, z = 36, reserve = true },
    { name = "PRes_barracks_3", arch = "barracks",  faction = "player", x = -28, z = 36, reserve = true },
    { name = "PRes_farm_1", arch = "farm", faction = "player", x = -40, z = 40, reserve = true },
    { name = "PRes_farm_2", arch = "farm", faction = "player", x = -37, z = 40, reserve = true },
    { name = "PRes_farm_3", arch = "farm", faction = "player", x = -34, z = 40, reserve = true },
    { name = "PRes_farm_4", arch = "farm", faction = "player", x = -31, z = 40, reserve = true },
    { name = "PRes_tower_1", arch = "tower", faction = "player", x = -40, z = 44, reserve = true },
    { name = "PRes_tower_2", arch = "tower", faction = "player", x = -37, z = 44, reserve = true },
    { name = "PRes_tower_3", arch = "tower", faction = "player", x = -34, z = 44, reserve = true },
    { name = "PRes_tower_4", arch = "tower", faction = "player", x = -31, z = 44, reserve = true },
    -- Wilds building reserves
    { name = "ERes_townhall_1", arch = "enemy_town_hall", faction = "enemy", x = 28, z = -36, reserve = true },
    { name = "ERes_barracks_1", arch = "enemy_barracks", faction = "enemy", x = 31, z = -36, reserve = true },
    { name = "ERes_barracks_2", arch = "enemy_barracks", faction = "enemy", x = 34, z = -36, reserve = true },
    { name = "ERes_farm_1", arch = "enemy_farm", faction = "enemy", x = 28, z = -40, reserve = true },
    { name = "ERes_farm_2", arch = "enemy_farm", faction = "enemy", x = 31, z = -40, reserve = true },
    { name = "ERes_farm_3", arch = "enemy_farm", faction = "enemy", x = 34, z = -40, reserve = true },
    { name = "ERes_tower_1", arch = "enemy_tower", faction = "enemy", x = 28, z = -44, reserve = true },
    { name = "ERes_tower_2", arch = "enemy_tower", faction = "enemy", x = 31, z = -44, reserve = true },
}
```

(Reserve offstage coords are outside `World.bounds` ±34 so they never appear; `Units.deactivate` parks them at `PARK_Y` anyway. Bake authors them; runtime adopts+deactivates.)

- [ ] **Step 2: Add Wilds starting workers + per-faction unit reserves** to `ROSTER` (existing player reserves stay; add enemy worker(s) + enemy unit reserves and rename pools by faction):

```lua
-- Wilds starting laborers
{ name = "WildsWorker_1", arch = "wilds_worker", x = -6.0, z = -30.0 },
{ name = "WildsWorker_2", arch = "wilds_worker", x = -8.0, z = -31.0 },
{ name = "WildsWorker_3", arch = "wilds_worker", x = -4.0, z = -31.5 },
-- Wilds unit reserves (trained by the AI)
{ name = "ERes_wworker_1", arch = "wilds_worker", x = 38, z = 30, reserve = true },
{ name = "ERes_wworker_2", arch = "wilds_worker", x = 40, z = 30, reserve = true },
{ name = "ERes_wworker_3", arch = "wilds_worker", x = 42, z = 30, reserve = true },
{ name = "ERes_grunt_1", arch = "grunt", x = 38, z = 32, reserve = true },
{ name = "ERes_grunt_2", arch = "grunt", x = 40, z = 32, reserve = true },
{ name = "ERes_grunt_3", arch = "grunt", x = 42, z = 32, reserve = true },
{ name = "ERes_grunt_4", arch = "grunt", x = 38, z = 34, reserve = true },
{ name = "ERes_grunt_5", arch = "grunt", x = 40, z = 34, reserve = true },
{ name = "ERes_grunt_6", arch = "grunt", x = 42, z = 34, reserve = true },
{ name = "ERes_grunt_7", arch = "grunt", x = 38, z = 36, reserve = true },
{ name = "ERes_grunt_8", arch = "grunt", x = 40, z = 36, reserve = true },
```

- [ ] **Step 3: Make `register`, `place_units`, `place_buildings` faction-aware.** `register(u)` already routes by `u.faction` to `state.player_units`/`state.enemy_units`; also push reserves into the faction's econ pool. Full `place_units`:

```lua
local function place_units(mode)
    for _, r in ipairs(ROSTER) do
        local u = (mode == "build") and Units.build(r.arch, r.name, r.x, r.z)
                                     or  Units.adopt(r.name, r.arch, r.x, r.z)
        if u then
            if r.reserve then
                Units.deactivate(u)
                local E = state.econ[u.faction]
                E.unit_reserves[r.arch] = E.unit_reserves[r.arch] or {}
                table.insert(E.unit_reserves[r.arch], u)
            else
                register(u)
            end
        end
    end
end
```

Full `place_buildings`:

```lua
local function place_buildings(mode)
    for _, b in ipairs(BUILDINGS) do
        local u = (mode == "build") and Units.build(b.arch, b.name, b.x, b.z)
                                     or  Units.adopt(b.name, b.arch, b.x, b.z)
        if u then
            local arch = Units.ARCH[b.arch]
            u.trains = arch and arch.trains or nil
            u.rally_x, u.rally_z = b.rally_x, b.rally_z
            u.queue = {}
            u.state = "done"
            local E = state.econ[b.faction]
            if b.reserve then
                Units.deactivate(u)
                E.building_reserves[b.arch] = E.building_reserves[b.arch] or {}
                table.insert(E.building_reserves[b.arch], u)
            else
                E.buildings[#E.buildings + 1] = u
            end
        end
    end
end
```

- [ ] **Step 4: Update `recount`** to count both factions' alive units (already does) — no change needed beyond using `state.player_units`/`state.enemy_units`. Town-hall counting is added in Stage 5.

### Task 2c: Re-bake the scene

**Files:** regenerates `Assets/Scenes/skirmish.pescene`.

- [ ] **Step 1: Run the bake.** With the build at `build-ninja-full-tracy\Debug`:

```powershell
$dir = "C:\Users\Christos\repos\PhasmaEngine\build-ninja-full-tracy\Debug"
Get-Process PhasmaPlayer,PhasmaEditor -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Remove-Item "$dir\PhasmaEngine.log" -Force -ErrorAction SilentlyContinue
$env:WB_BAKE='1'; $env:WB_DEMO=''
$p = Start-Process "$dir\PhasmaPlayer.exe" -ArgumentList '--api','vulkan','--display','1' -WorkingDirectory $dir -PassThru
Start-Sleep 15
Stop-Process -Id $p.Id -Force; $env:WB_BAKE=''
```

Assert the log shows `[Warbound] BAKED authored scene -> Assets/Scenes/baked`.

- [ ] **Step 2: Rename + re-append HUD.**

```powershell
$assets = "C:\Users\Christos\repos\PhasmaProjects\Warbound\Assets"
Move-Item "$assets\Scenes\baked" "$assets\Scenes\skirmish.pescene" -Force
python "C:\Users\Christos\repos\PhasmaProjects\Warbound\tools\build_hud.py"
```

(If the bake writes into the build-tree `Assets` copy rather than the project, locate `baked` via `Get-ChildItem -Recurse -Filter baked` under the build dir and the project, and rename the project one. Confirm `build_hud.py`'s output path matches the scene you renamed.)

- [ ] **Step 3: Verify the baked scene loads with both bases.** Run VERIFY-LAUNCH (`WB_DEMO=1`). Assert:
```
Scene loaded from: ...skirmish.pescene
[Warbound] match started: 12 vs 15
```
(player count unchanged: 12 player units; enemy now 15 grunts/wolves + 3 wilds workers — adjust the expected `match started` number to the new enemy total; print it from `recount`). Add a one-shot `pe_log(string.format("[bake] p_buildings=%d e_buildings=%d p_breserve=%d e_breserve=%d", #state.econ.player.buildings, #state.econ.enemy.buildings, ...))` to confirm 2 player + 2 enemy live buildings and the reserve pools populated. 0 errors. Visually confirm (one screenshot/playtest) both bases render and reserves are offstage.

- [ ] **Step 4: Commit.** Stage `wb_world.lua wb_economy.lua wb_game.lua Assets/Scenes/skirmish.pescene`. Message: `Warbound: bake Wilds base + resource nodes + building/unit reserve pools`.

---

## Stage 3 — `wb_build`: player placement + worker construction

### Task 3: Placement mode and the construction state machine

**Files:**
- Create: `Assets/Scripts/game/wb_build.lua`
- Modify: `Assets/Scripts/game/wb_orders.lua` (`order == "build"` locomotion)
- Modify: `Assets/Scripts/game/wb_game.lua` (call `Build.update` in the pipeline; `WB_TEST_BUILD` harness)
- Modify: `Assets/Scripts/Player/warbound.lua` (preload `build`)

**Interfaces:**
- Produces `Build.DEFS = { barracks=..., farm=..., tower=..., town_hall=... }` each `{ arch, gold, lumber, build_time, label, letter }` (player arch names; the AI maps to enemy_* via a faction prefix).
- Produces `Build.begin(state, E, type_key, workers)` → enters placement mode (player) or, for the AI, `Build.place(state, E, type_key, x, z, workers)` → commits a site directly.
- Produces `Build.cancel()`, `Build.is_placing() -> bool`, `Build.update(dt, state)` (drives placement-follow + per-site construction).
- Produces site fields on a building table: `state = "site"|"done"`, `build_t`, `build_total`, `builder` (worker), `faction`.
- Consumes: `state.econ[*].building_reserves`, `Camera.pick_ground/world_to_screen`, `Units.activate`/`set_visible`, `Economy`, `World.clamp`.

- [ ] **Step 1: Create `wb_build.lua` skeleton with DEFS + arch mapping.**

```lua
local U = WB.util
local World = WB.world
local Camera = WB.camera
local Units = WB.units
local Build = {}

Build.DEFS = {
    barracks  = { arch = "barracks",  gold = 160, lumber = 40, build_time = 14.0, label = "Barracks",  letter = "B" },
    farm      = { arch = "farm",      gold = 60,  lumber = 20, build_time = 8.0,  label = "Farm",      letter = "F" },
    tower     = { arch = "tower",     gold = 120, lumber = 30, build_time = 12.0, label = "Tower",     letter = "T" },
    town_hall = { arch = "town_hall", gold = 300, lumber = 80, build_time = 24.0, label = "Town Hall", letter = "H" },
}

-- Player arch -> enemy arch, so the AI builds Wilds variants from the same DEFS.
local function faction_arch(E, base_arch)
    if E.faction == "enemy" then return "enemy_" .. base_arch end
    return base_arch
end
```

- [ ] **Step 2: Placement validity + reserve borrow.** Full bodies:

```lua
-- Is (x,z) a legal building spot for E? In bounds, clear of every live building, off nodes.
function Build.spot_valid(state, x, z, radius)
    local bx, bz = World.clamp(x, z, radius + 1.0)
    if math.abs(bx - x) > 0.01 or math.abs(bz - z) > 0.01 then return false end -- clamped => out of bounds
    for _, fac in ipairs({ "player", "enemy" }) do
        for _, b in ipairs(state.econ[fac].buildings) do
            if b.alive and U.dist2(x, z, b.x, b.z) < (radius + b.radius + 1.5) then return false end
        end
    end
    local nodes = { World.mine, World.forest, World.wilds_mine, World.wilds_forest }
    for _, n in ipairs(nodes) do
        if n and U.dist2(x, z, n.x, n.z) < radius + 6.0 then return false end
    end
    return true
end

local function borrow_reserve(E, arch)
    local pool = E.building_reserves[arch]
    return pool and table.remove(pool) or nil
end

local function return_reserve(E, arch, b)
    E.building_reserves[arch] = E.building_reserves[arch] or {}
    table.insert(E.building_reserves[arch], b)
    Units.deactivate(b)
end
```

- [ ] **Step 3: Direct placement (used by AI now, and by the player's confirm in Step 5).** Full body:

```lua
-- Commit a construction site for E at (x,z) of build type_key, assigning `workers` to build.
-- Returns the site building table, or nil if unaffordable / no reserve / bad spot.
function Build.place(state, E, type_key, x, z, workers)
    local def = Build.DEFS[type_key]; if not def then return nil end
    if (E.gold or 0) < def.gold or (E.lumber or 0) < def.lumber then return nil end
    local arch_name = faction_arch(E, def.arch)
    local arch = Units.ARCH[arch_name]
    if not Build.spot_valid(state, x, z, arch.radius) then return nil end
    local b = borrow_reserve(E, arch_name); if not b then return nil end
    E.gold = E.gold - def.gold; E.lumber = E.lumber - def.lumber
    Units.activate(b, x, z)                  -- show the rig at the spot
    b.state = "site"; b.build_t = def.build_time; b.build_total = def.build_time
    b.hp = math.max(1, b.hp_max * 0.1); b.queue = {}
    b.trains = arch.trains; b.rally_x, b.rally_z = x, (z - 6.0)
    b.faction = E.faction
    Build.tint_site(b, true)                 -- desaturate while building
    E.buildings[#E.buildings + 1] = b
    if workers and workers[1] then
        local w = workers[1]
        w.order = "build"; w.build_target = b; w.job = nil; w.target = nil
    end
    if pe_log then pe_log(string.format("[build] %s site placed by %s at %.0f,%.0f", def.label, E.faction, x, z)) end
    return b
end

-- Desaturate/restore a site's mesh emissive as a build-progress read (material writes are frame-safe).
function Build.tint_site(b, building)
    if not b.parts then return end
    for _, n in pairs(b.parts) do
        if U.valid(n) and material and material.set then
            material.set(n, "emissive", building and vec3(0.02, 0.03, 0.05) or vec3(0.07, 0.07, 0.08))
        end
    end
end
```

- [ ] **Step 4: Construction tick + completion** in `Build.update`. Full body:

```lua
function Build.update(dt, state)
    Build.update_placement(dt, state)  -- player ghost-follow (Step 5); no-op when not placing
    for _, fac in ipairs({ "player", "enemy" }) do
        for _, b in ipairs(state.econ[fac].buildings) do
            if b.alive and b.state == "site" then
                local w = b.builder or b.build_worker
                -- progress only while the assigned worker is adjacent and building
                local builder = nil
                for _, u in ipairs(state.econ[fac].units) do
                    if u.alive and u.order == "build" and u.build_target == b
                       and U.dist2(u.x, u.z, b.x, b.z) <= b.radius + 2.2 then builder = u; break end
                end
                if builder then
                    if (builder.attack_swing or 0.0) <= 0.0 then builder.attack_swing = 0.25 end
                    b.build_t = b.build_t - dt
                    b.hp = math.min(b.hp_max, b.hp_max * (0.1 + 0.9 * (1.0 - b.build_t / b.build_total)))
                    if b.build_t <= 0.0 then
                        b.state = "done"; b.hp = b.hp_max
                        Build.tint_site(b, false)
                        builder.order = "idle"; builder.build_target = nil
                        if pe_log then pe_log(string.format("[build] %s complete (%s)", Units.ARCH[b.arch].display, fac)) end
                    end
                end
            end
        end
    end
end
```

- [ ] **Step 5: Player placement mode (ghost follows cursor).** Full bodies:

```lua
local placing = nil -- { E, type_key, ghost, workers }

function Build.is_placing() return placing ~= nil end

function Build.begin(state, E, type_key, workers)
    if placing then Build.cancel() end
    local def = Build.DEFS[type_key]; if not def then return end
    local arch_name = faction_arch(E, def.arch)
    local ghost = borrow_reserve(E, arch_name); if not ghost then return end
    Units.activate(ghost, 0.0, 0.0) -- shown; moved to cursor each frame
    placing = { E = E, type_key = type_key, ghost = ghost, arch_name = arch_name, workers = workers, valid = false }
end

function Build.cancel()
    if not placing then return end
    return_reserve(placing.E, placing.arch_name, placing.ghost)
    placing = nil
end

function Build.update_placement(dt, state)
    if not placing then return end
    local mx, my = nil, nil
    if input and input.get_mouse_position then local m = input.get_mouse_position(); if m and m.x then mx, my = m.x, m.y end end
    local gx, gz = mx and Camera.pick_ground(mx, my) or nil
    if gx then
        local arch = Units.ARCH[placing.arch_name]
        placing.valid = Build.spot_valid(state, gx, gz, arch.radius)
        Units.place(placing.ghost, gx, gz)
        Build.tint_ghost(placing.ghost, placing.valid)
        placing.gx, placing.gz = gx, gz
    end
    -- left-click confirm, right-click cancel handled in wb_orders/selection input layer (Step 6)
end

function Build.tint_ghost(b, ok)
    if not b.parts then return end
    for _, n in pairs(b.parts) do
        if U.valid(n) and material and material.set then
            material.set(n, "emissive", ok and vec3(0.0, 0.3, 0.05) or vec3(0.4, 0.0, 0.0))
        end
    end
end

function Build.confirm(state)
    if not (placing and placing.valid and placing.gx) then return false end
    local E, type_key, gx, gz, workers = placing.E, placing.type_key, placing.gx, placing.gz, placing.workers
    -- reuse the ghost as the site rig: return it to the pool, then place() borrows it back
    return_reserve(E, placing.arch_name, placing.ghost)
    placing = nil
    return Build.place(state, E, type_key, gx, gz, workers) ~= nil
end
```

- [ ] **Step 6: `order == "build"` locomotion** in `wb_orders.locomote`. Add a branch alongside `move`/`attack`: when `u.order == "build"` and `u.build_target` alive+site, steer toward an `approach_point` at `build_target.radius + 1.2`; on arrival, stop (the build tick detects adjacency). When `build_target` is nil/done, revert to `idle`. Code (insert in the `if u.order == ...` ladder):

```lua
elseif u.order == "build" and u.build_target and u.build_target.alive and u.build_target.state == "site" then
    local b = u.build_target
    local dx, dz = b.x - u.x, b.z - u.z
    local nx, nz, d = U.norm2(dx, dz)
    pt_x, pt_z, stop = b.x, b.z, (b.radius + 1.2)
elseif u.order == "build" then
    u.order = "idle"; u.build_target = nil
```

- [ ] **Step 7: Wire `Build.update` into the pipeline** and preload. In `wb_game.update`, after `Economy.update(gdt, state)` add `WB.build.update(gdt, state)`. In `warbound.lua` preload list, insert `"build"` after `"economy"`. Add `WB.build = Build` return at the end of `wb_build.lua` (`return Build`).

- [ ] **Step 8: `WB_TEST_BUILD` harness.** In `Game.init`, after the `WB_DEMO` block, add:

```lua
if env("WB_TEST_BUILD") then
    local PE = state.econ.player
    local w = nil
    for _, u in ipairs(state.player_units) do if u.arch == "worker" then w = u; break end end
    if w then WB.build.place(state, PE, "farm", -16.0, 22.0, { w }) end
end
```

This drives a headless build without the HUD (which lands in Stage 8).

- [ ] **Step 9: Verify construction.** Run VERIFY-LAUNCH with `WB_DEMO=1` AND set `$env:WB_TEST_BUILD='1'`. Assert log:
```
[build] Farm site placed by player at -16,22
[build] Farm complete (player)
```
and that `state.econ.player.food_cap` rose by 6 after completion (add a one-shot log after the complete line, or assert via the `[econ]` line from Task 0 showing `food=12/26`). 0 errors. Clear `WB_TEST_BUILD` after.

- [ ] **Step 10: Commit.** Stage `wb_build.lua wb_orders.lua wb_game.lua warbound.lua`. Message: `Warbound: wb_build placement + worker construction (player + AI shared)`.

---

## Stage 4 — Combat: towers, buildings as targets, building death

### Task 4: Fold buildings into combat

**Files:** Modify `Assets/Scripts/game/wb_combat.lua`, `wb_game.lua` (pipeline order).

**Interfaces:**
- Produces `Combat.buildings_pass(dt, state)` (tower fire), `Combat.standing_town_halls(E) -> int`.
- Extends `Combat.acquire` so units target enemy buildings; `Combat.die` handles `target.is_building`.

- [ ] **Step 1: Enemy-building targeting in `Combat.acquire`.** A unit on `attack`/`attack_move` with no live unit target, within aggro of an enemy building, targets the nearest enemy building. Add a helper that searches both enemy units and enemy buildings:

```lua
local function nearest_foe(u, foe_units, foe_buildings, radius)
    local best, bd = nearest(u, foe_units, radius)
    if best then bd = U.dist2_sq(u.x, u.z, best.x, best.z) end
    for _, b in ipairs(foe_buildings) do
        if b.alive then
            local d = U.dist2_sq(u.x, u.z, b.x, b.z)
            if d <= radius * radius and (not bd or d < bd) then best, bd = b, d end
        end
    end
    return best
end
```

In `acquire`, where player/enemy idle units look for foes, pass the opposing faction's `buildings` list too (player units → `state.econ.enemy.buildings`, enemy units → `state.econ.player.buildings`). Units explicitly attack-moving into a base will thus auto-acquire the base buildings (so razing progresses). Keep the existing `no_combat` guard (workers never auto-engage).

- [ ] **Step 2: Tower fire pass.** `Combat.buildings_pass(dt, state)` — each completed tower acquires the nearest enemy unit in range and attacks on its interval, reusing `Combat.apply_damage`:

```lua
function Combat.buildings_pass(dt, state)
    for _, fac in ipairs({ "player", "enemy" }) do
        local foes = state.econ[fac == "player" and "enemy" or "player"].units
        for _, b in ipairs(state.econ[fac].buildings) do
            if b.alive and b.state == "done" and (b.dps or 0) > 0 then
                if not (b.target and b.target.alive) or U.dist2(b.x, b.z, b.target.x, b.target.z) > b.range then
                    b.target = nearest(b, foes, b.range)
                end
                if b.target and b.target.alive then
                    b.attack_t = (b.attack_t or 0.0) - dt
                    if b.attack_t <= 0.0 then
                        b.attack_t = b.interval
                        Combat.apply_damage(b.target, b.dps * b.interval, b, state)
                        WB.fx_hit(b.target.x, b.target.z)
                    end
                end
            end
        end
    end
end
```

- [ ] **Step 3: Building death in `Combat.die`.** When `target.is_building`: remove from its econ's `buildings`, hide+park the rig (reuse `Units.kill`), and DO NOT credit unit-kill bounty/xp (or a small flat gold). Sites being killed cancels the build. Add at the top of `Combat.die`:

```lua
if target.is_building then
    WB.units.kill(target)
    local E = state.econ[target.faction or (target.faction == "enemy" and "enemy" or "player")]
    if E then U.compact(E.buildings, function(x) return x.alive end) end
    if pe_log then pe_log(string.format("[combat] %s razed (%s)", WB.units.ARCH[target.arch].display, target.faction or "?")) end
    return
end
```

Ensure every building table has `b.faction` set (Task 2b sets it via `b.state="done"` block — add `u.faction = b.faction` there; `Build.place` sets it too). `Units.kill` already hides via `set_visible` (commit c5e3867) — good, no rebuild stall on building death.

- [ ] **Step 4: `Combat.standing_town_halls`.**

```lua
function Combat.standing_town_halls(E)
    local n = 0
    for _, b in ipairs(E.buildings) do
        if b.alive and b.state == "done"
           and (b.arch == "town_hall" or b.arch == "enemy_town_hall") then n = n + 1 end
    end
    return n
end
```

- [ ] **Step 5: Pipeline.** In `wb_game.update`, add `WB.combat.buildings_pass(gdt, state)` right after `WB.combat.attacks(...)`.

- [ ] **Step 6: Verify.** Run VERIFY-LAUNCH with `WB_DEMO=1` (fighters march south into the Wilds base; the Wilds towers don't exist yet at start, but the Wilds base buildings do). Assert:
```
[combat] Wilds Den razed (enemy)   (or Wilds Pit, whichever the blob reaches)
```
Also `WB_TEST_BUILD=1` to build a player tower near the path and assert it fires (`WB.fx_hit` is cosmetic; add a one-shot `[combat] tower acquired target` log in the pass for the assertion). 0 errors.

- [ ] **Step 7: Commit.** Stage `wb_combat.lua wb_game.lua`. Message: `Warbound: towers fire, buildings are targets, building death + razed-hall count`.

---

## Stage 5 — Win / lose by base

### Task 5: Raze-the-base win condition

**Files:** Modify `wb_game.lua` (`recount`, `update` result logic), `wb_hud.lua` (objective text).

- [ ] **Step 1: Track standing town halls in `recount`.** Add:

```lua
state.player_halls = WB.combat.standing_town_halls(state.econ.player)
state.enemy_halls  = WB.combat.standing_town_halls(state.econ.enemy)
```

- [ ] **Step 2: Rewrite the result check in `Game.update`** (replace the `enemy_alive<=0`/`player_alive<=0` block):

```lua
recount()
if not state.result then
    if state.enemy_halls <= 0 then state.result = "win"
    elseif state.player_halls <= 0 or state.hero_dead then state.result = "lose" end
    if state.result and pe_log then
        pe_log("[Warbound] " .. (state.result == "win" and "VICTORY: razed the Wilds" or "DEFEAT"))
    end
end
```

- [ ] **Step 3: Objective HUD text** in `wb_hud.drive_top` — replace the foe-count line:

```lua
else
    msg, ccol = string.format("Raze the Wilds' Great Hall   -   %d enemy halls, %d foes",
        state.enemy_halls or 0, state.enemy_alive), U.COLOR.ink
end
```

Win/lose strings stay (`VICTORY ... (press R)` / `DEFEAT ... (press R)`).

- [ ] **Step 4: Verify.** Run VERIFY-LAUNCH `WB_DEMO=1` long enough (40s) for the demo blob to reach a Wilds hall, OR `WB_TEST_BUILD`-style add a hero-suicide path. Assert one of:
```
[Warbound] VICTORY: razed the Wilds
[Warbound] DEFEAT
```
0 errors.

- [ ] **Step 5: Commit.** Stage `wb_game.lua wb_hud.lua`. Message: `Warbound: raze-the-base win/lose (town halls + hero death)`.

---

## Stage 6 — Rally points

### Task 6: Set rally, smart-rally, marker, trained-unit walk

**Files:** Modify `wb_orders.lua` (rally issue), `wb_economy.lua` (`spawn_trained` rally walk), `wb_hud.lua` (marker).

- [ ] **Step 1: Rally issue on right-click while a building is selected** in `wb_orders.handle_input`. Before the unit-order branch, handle building selection:

```lua
if WB.selection.building then
    local b = WB.selection.building
    if down and not prev_right and not mouse_in_ui then
        local mx, my = mouse()
        if mx then
            local gx, gz = Camera.pick_ground(mx, my)
            if gx then
                local kind = WB.economy.resource_near(gx, gz, "player")
                if kind then b.rally_node = kind; b.rally_x, b.rally_z = Camera and gx or gx, gz
                else b.rally_node = nil; b.rally_x, b.rally_z = gx, gz end
                b.rally_set = true
                WB.fx_ping(gx, gz, false)
            end
        end
    end
    prev_right = down
    return
end
```

- [ ] **Step 2: Trained-unit walk in `spawn_trained`** (extend the Stage 0 body). After `Units.activate(u, rx, rz)` and registration:

```lua
if b.rally_set then
    if b.rally_node and u.arch_is_worker then
        Economy.order_harvest(E, { u }, b.rally_node)   -- smart-rally: auto-harvest
    else
        u.order = "move"; u.goal_x, u.goal_z = b.rally_x, b.rally_z
    end
end
```

- [ ] **Step 3: Rally marker on the HUD** (`wb_hud`): for the selected building with `rally_set`, draw a minimap dot at the rally and a thin world-projected ring at `Camera.world_to_screen(rally_x, 0.3, rally_z)` (a few `quad()` segments, `no_input`). Add to `draw_minimap` (dot) and a new `draw_rally()` called from `Hud.update`. Code mirrors `draw_select_box` (screen-space quads).

- [ ] **Step 4: Verify.** `WB_TEST_BUILD=1` plus a harness line that selects the Barracks and sets a rally + trains a unit, then assert the trained unit walks to the rally (log its goal). Simpler headless assertion: add a one-shot `[rally] set at x,z node=...` log in Step 1 and drive it from a `WB_TEST_RALLY` flag that sets `WB.selection.set_building(barracks)` then simulates the right-click via `b.rally_x/z` directly + trains. Assert:
```
[rally] barracks rally set node=lumber
```
0 errors. Full UX verified interactively in Stage 8.

- [ ] **Step 5: Commit.** Stage `wb_orders.lua wb_economy.lua wb_hud.lua`. Message: `Warbound: rally points + smart-rally + marker`.

---

## Stage 7 — `wb_ai`: the Wilds brain

### Task 7: Wilds economy, build order, army, combat director

**Files:**
- Create: `Assets/Scripts/game/wb_ai.lua`
- Modify: `wb_game.lua` (call `AI.update`; `WB_AI` flag), `warbound.lua` (preload `ai`)

**Interfaces:**
- Produces `AI.update(dt, state)` (throttled ~0.5s), driving `state.econ.enemy`.
- Consumes: `Economy`, `Build`, `Orders`, `Combat`, `state.econ.enemy`.

- [ ] **Step 1: Skeleton + throttle + economy.**

```lua
local U = WB.util
local Economy = WB.economy
local Build = WB.build
local Orders = WB.orders
local World = WB.world
local AI = {}

local TICK = 0.5
local acc = 0.0
local damage_recent_t = 0.0  -- set by Combat when an enemy building/unit is hit near base

local function enemy_workers(E)
    local out = {}
    for _, u in ipairs(E.units) do if u.alive and u.arch_is_worker then out[#out+1] = u end end
    return out
end

local function tick_economy(state, E)
    -- keep idle workers harvesting (alternate gold/lumber)
    for i, w in ipairs(enemy_workers(E)) do
        if not w.job and w.order ~= "build" then
            Economy.order_harvest(E, { w }, (i % 2 == 0) and "gold" or "lumber")
        end
    end
    -- train workers up to a cap at the Wilds hall
    local hall = nil
    for _, b in ipairs(E.buildings) do if b.alive and b.state=="done" and b.arch=="enemy_town_hall" then hall=b; break end end
    if hall and #enemy_workers(E) < 5 and Economy.train_status(state, E, hall) == "ok" then
        Economy.try_train(state, E, hall)
    end
end
```

- [ ] **Step 2: Build order (worker-built, one site at a time).**

```lua
local function has_site(E) for _, b in ipairs(E.buildings) do if b.alive and b.state=="site" then return true end end return false end
local function count_arch(E, arch) local n=0 for _,b in ipairs(E.buildings) do if b.alive and b.arch==arch then n=n+1 end end return n end

local function free_worker(E)
    for _, u in ipairs(E.units) do if u.alive and u.arch_is_worker and u.order ~= "build" then return u end end
    return nil
end

local function tick_build(state, E)
    if has_site(E) then return end          -- one site at a time
    local hall = nil
    for _, b in ipairs(E.buildings) do if b.alive and b.state=="done" and b.arch=="enemy_town_hall" then hall=b; break end end
    if not hall then return end
    local want = nil
    if Economy.food_used(E) + 2 >= E.food_cap then want = "farm"
    elseif count_arch(E, "enemy_barracks") < 1 then want = "barracks"
    elseif damage_recent_t > 0 and count_arch(E, "enemy_tower") < 2 then want = "tower"
    elseif (E.gold or 0) > 250 then want = "barracks" end
    if not want then return end
    local def = Build.DEFS[want]
    if (E.gold or 0) < def.gold or (E.lumber or 0) < def.lumber then return end
    local w = free_worker(E); if not w then return end
    -- pick a spot in a ring around the hall, scan a few angles for a valid one
    for k = 0, 7 do
        local a = k * (math.pi / 4)
        local x = hall.x + math.cos(a) * 8.0
        local z = hall.z + math.sin(a) * 8.0
        x, z = World.clamp(x, z, 3.0)
        if Build.spot_valid(state, x, z, Units and 2.0 or 2.0) then
            Build.place(state, E, want, x, z, { w })
            return
        end
    end
end
```

- [ ] **Step 3: Army + combat director (reactive + threshold).**

```lua
local function army(E)
    local out = {}
    for _, u in ipairs(E.units) do if u.alive and not u.arch_is_worker and not u.is_building then out[#out+1] = u end end
    return out
end

local function tick_military(state, E)
    local barracks = nil
    for _, b in ipairs(E.buildings) do if b.alive and b.state=="done" and b.arch=="enemy_barracks" then barracks=b; break end end
    local threshold = 6 + math.floor(state.time / 45.0)   -- escalates ~+1 per 45s
    local a = army(E)
    -- train army toward threshold
    if barracks and #a < threshold + 2 and Economy.train_status(state, E, barracks) == "ok" then
        Economy.try_train(state, E, barracks)
    end
    -- combat director
    local PB = state.econ.player.buildings
    if damage_recent_t > 0 then
        -- defend: pull army home, flee workers to hall
        local hall = nil
        for _, b in ipairs(E.buildings) do if b.alive and b.arch=="enemy_town_hall" then hall=b; break end end
        if hall then Orders.move_to(a, hall.x, hall.z + 4.0) end
        for _, w in ipairs(enemy_workers(E)) do if w.order ~= "build" then w.job = nil; w.order = "move"; w.goal_x, w.goal_z = (hall and hall.x or w.x), (hall and hall.z + 6.0 or w.z) end end
    elseif #a >= threshold then
        -- attack: target the player's town hall (or nearest building)
        local tgt = nil
        for _, b in ipairs(PB) do if b.alive and b.arch=="town_hall" then tgt=b; break end end
        if not tgt then for _, b in ipairs(PB) do if b.alive then tgt=b; break end end end
        if tgt then for _, u in ipairs(a) do u.order = "attack"; u.target = tgt; u.attack_move = true end end
    end
end

function AI.notify_base_attacked() damage_recent_t = 3.0 end  -- called from Combat when a Wilds thing is hit

function AI.update(dt, state)
    if damage_recent_t > 0 then damage_recent_t = damage_recent_t - dt end
    acc = acc + dt
    if acc < TICK then return end
    acc = 0.0
    local E = state.econ.enemy
    tick_economy(state, E)
    tick_build(state, E)
    tick_military(state, E)
end

return AI
```

- [ ] **Step 4: Hook base-attacked notify** in `wb_combat.apply_damage`: when `target.faction == "enemy"` (a Wilds unit or building took damage), call `WB.ai and WB.ai.notify_base_attacked()`. Throttle is internal (the 3s timer).

- [ ] **Step 5: Pipeline + preload + flag.** In `wb_game.update`, after `WB.build.update(...)` add `if WB.ai and not env_ai_off then WB.ai.update(gdt, state) end` where `env_ai_off = env("WB_AI") == "0"`. Preload `"ai"` after `"build"` in `warbound.lua`.

- [ ] **Step 6: Verify the AI plays.** Run VERIFY-LAUNCH **without** `WB_DEMO` (let the AI run unattended; the player just sits) for 60s. Assert the log shows the Wilds gathering → building → training → attacking:
```
[build] Farm site placed by enemy at ...
[build] Barracks complete (enemy)
```
and eventually army movement toward the player base (add a one-shot `[ai] attack wave size=N` log in the attack branch). Confirm 0 errors and that workers harvest (lumber/gold for `state.econ.enemy` climbs — add it to the `[econ]` debug line for both factions). Then run with `WB_AI=0` and confirm the Wilds stay passive (regression isolation).

- [ ] **Step 7: Commit.** Stage `wb_ai.lua wb_game.lua wb_combat.lua warbound.lua`. Message: `Warbound: Wilds build AI (economy, build order, army, reactive director)`.

---

## Stage 8 — HUD: build sub-card, site progress, markers, enemy buildings

### Task 8: Player-facing build UI

**Files:** Modify `Assets/Scripts/game/wb_hud.lua`, `wb_selection.lua` (track a build-submenu mode if needed).

- [ ] **Step 1: Build sub-card when a Laborer is selected.** In `draw_command_card`, when `sel[1].arch == "worker"`, replace the "Gather" hint with Build buttons (one per `Build.DEFS` entry) showing cost + affordability color. On click, `WB.build.begin(state, state.econ.player, type_key, sel)`:

```lua
if sel[1] and sel[1].arch == "worker" then
    local i = 0
    for _, key in ipairs({ "farm", "barracks", "tower", "town_hall" }) do
        local def = WB.build.DEFS[key]
        local affordable = state.econ.player.gold >= def.gold and state.econ.player.lumber >= def.lumber
        local fill = affordable and { 0.14, 0.18, 0.14, 0.95 } or { 0.12, 0.12, 0.14, 0.95 }
        local c, r = i % 4, 1 + math.floor(i / 4)
        if btn(c, r, "bld_" .. key, def.label, string.format("%dg %dw", def.gold, def.lumber), fill) then
            if affordable then WB.build.begin(state, state.econ.player, key, sel) end
        end
        i = i + 1
    end
end
```

- [ ] **Step 2: Placement banner + confirm/cancel input.** When `WB.build.is_placing()`, draw a centered banner ("Left-click to place — right-click to cancel"). Handle the clicks in `wb_selection.update`: if `Build.is_placing()`, a left-press (not over UI) calls `WB.build.confirm(state)` and a right-press calls `WB.build.cancel()` — and both consume the click (return before normal selection/orders). Add at the very top of `Selection.update`:

```lua
if WB.build.is_placing() then
    local l = input.is_left_mouse_down and input.is_left_mouse_down() == true
    local r = input.is_right_mouse_down and input.is_right_mouse_down() == true
    if l and not prev_down then WB.build.confirm(state) end
    if r then WB.build.cancel() end
    prev_down = l
    return
end
```

(Thread `state` into `Selection.update` — it currently takes `player_units, mouse_in_ui`; add `state` or read `WB.game.state`.)

- [ ] **Step 3: Construction-site progress bar.** In `draw_command_card`, when the selected building has `state == "site"`, draw a progress `bar()` = `1 - build_t/build_total` with label "Building… N%". When a tower/barracks is `done`, the existing train button (barracks) or a "Guard Tower" label (tower) shows.

- [ ] **Step 4: Enemy buildings on the minimap.** In `draw_minimap`, after plotting `state.buildings`, also plot `state.econ.enemy.buildings` (enemy color) and `state.econ.player.buildings` (player color). Replace the old `state.buildings` reference (removed in Stage 0) with both econ lists.

- [ ] **Step 5: Verify interactively.** This is the UI task — use the playtesting-a-feature skill. Launch the editor or PhasmaPlayer on `--display 1` (no `WB_DEMO`), then: select a Laborer → Build sub-card appears → click Farm → ghost follows cursor green/red → left-click on a valid spot → worker walks and builds → Farm completes and food cap rises. Set a rally on the Barracks (select it, right-click ground) → train → unit walks to rally. Confirm the Wilds AI is also building/attacking on the minimap. Capture the log and confirm 0 errors plus the `[build] ... complete (player)` line.

- [ ] **Step 6: Full-loop headless smoke.** Run VERIFY-LAUNCH with `WB_DEMO=1` + `WB_TEST_BUILD=1` for 60s; assert the log shows player build complete, AI build complete, and a `VICTORY`/`DEFEAT` result, with 0 errors.

- [ ] **Step 7: Commit.** Stage `wb_hud.lua wb_selection.lua`. Message: `Warbound: build sub-card, placement banner, site progress, rally + enemy buildings on minimap`.

---

## Self-Review

**Spec coverage (each spec section → task):**
- §1 per-faction econ → Task 0. §2 archetypes+re-bake → Tasks 1, 2a-2c. §3 placement+construction → Task 3. §4 towers/targets/death → Task 4. §5 win/lose → Task 5. §6 rally → Task 6. §7 AI → Task 7. §8 HUD/module deltas → Task 8 (+ preload edits in Tasks 3/7). §9 verification → per-task launch+log gates + Task 8 interactive playtest. Open-defaults: hero-death loss (Task 5 Step 2), sites destroyable no-refund (Task 4 Step 3 + Task 3 — cost spent on confirm, killing a site cancels with no refund), independent Wilds economy (Task 2a), reserve sizes (Task 2b, tunable). **No gaps.**

**Placeholder scan:** every code step carries full bodies; no TBD/TODO. Two intentional "tune during bake" knobs (reserve pool sizes, AI thresholds) are flagged in the spec's open-defaults, not placeholders.

**Type/name consistency:** `state.econ[faction]` with fields `gold/lumber/food_cap/buildings/units/unit_reserves/building_reserves` used identically across Tasks 0,2,3,4,7. Building site fields `state/build_t/build_total/builder/faction` consistent in Tasks 3,4,8. `Build.DEFS` keys (`farm/barracks/tower/town_hall`) and `faction_arch` mapping consistent in Tasks 3,7,8. `arch_is_worker`/`is_dropoff`/`is_building` set in Task 1, read in 0/3/4/7. `Combat.standing_town_halls` defined Task 4, used Task 5.

**Known risk to watch during execution:** the re-bake (Task 2c) is the fragile step (per project memory) — verify the renamed scene loads *both* bases and that `build_hud.py` targeted the right scene before proceeding to Stage 3. If `Selection.update` signature change (Task 8 Step 2) ripples, update its single caller in `wb_game.update`.

---

## Execution Handoff

Plan complete and saved to `Warbound/docs/plans/2026-06-18-slice2-basebuilding-ai-plan.md`.
