# Warbound — Slice 2 polish: base-building + Wilds build AI (design)

Date: 2026-06-18. Status: approved design, pre-plan.

Single combined spec covering player building placement, rally points, and a full
mirrored Wilds build AI. This is effectively Slice 2 polish **and** Slice 4 (enemy AI)
designed together, by user decision. The work is large but modular; the implementation
plan should land it in reviewable pieces (state refactor → archetypes/re-bake → player
build → combat/towers → rally → win/lose → AI → HUD).

## Decisions locked

- **Win/lose:** a faction's "heart" is its Town Hall(s). **Win** = all Wilds town halls
  razed. **Lose** = all player town halls razed **OR** the hero dies. Replaces the
  current "all enemy units dead / all player units dead."
- **Construction:** worker-built. Select a Laborer → choose a building → place a ghost →
  the worker walks to the site and constructs it over a build time.
- **Build roster (both factions):** existing Town Hall / Barracks **plus** a **Farm**
  (cheap, food-only) and a defensive **Tower** (static, auto-attacks nearby enemies).
- **AI aggression:** reactive + threshold. Defends its base when attacked (recalls army,
  flees workers); otherwise masses an army to an escalating threshold then attack-moves
  the player's Town Hall.
- **Resource model:** the Wilds get their **own** mine + grove near their camp.
  Independent economies; no contesting a shared node.

## Approach: faction-parameterized, not duplicated

Player and Wilds play the **same game through the same code**. Economy/training/buildings
are generalized to take a faction (today `nearest_dropoff`, food cap, and training
reserves are hardcoded to `"player"`). One shared `wb_build` module owns placement +
construction for both. A thin `wb_ai` brain issues orders to the enemy faction exactly
like mouse/HUD input issues them to the player. The AI is symmetric by construction.

Rejected: a duplicated `wb_enemy_economy` (drift, double-maintenance) and a generalized
multi-faction "commander" abstraction (YAGNI for a 2-faction game).

## Engine constraints honored

- **No runtime geometry creation.** Everything that appears at runtime is a rig
  pre-authored offstage in the bake and revived via `Units.activate` (the existing
  trained-unit pattern). Building reserves, construction sites, and placement ghosts all
  use this. The placement ghost *is* a reserve rig, activated and moved to the cursor.
- **Re-bake discipline:** `scene.clear()` first, rebuild world+units+buildings, `scene.save("baked")`,
  rename `baked` → `skirmish.pescene`, re-run `tools/build_hud.py` (truncates at the
  first authored UI_Root, so a clean bake must not contain a stale one). See project
  memory `project_warbound` for the re-bake saga.
- **Playtest on the Debug build, `--display 1`.** Release is blocked by the
  tracy-Release `0xC0000005` crash (environmental, not project code).

## 1. State model — per-faction econ

`state.econ = { player = E, enemy = E }` where each `E` holds:
`gold, lumber, food_cap, buildings, unit_reserves[arch], building_reserves[arch]`, and a
reference to that faction's unit list (`state.player_units` / `state.enemy_units` stay the
canonical lists). HUD reads `state.econ.player`.

Generalized functions (faction/econ handle instead of implicit player):
`nearest_dropoff(E, x, z)`, food cap = sum of `E.buildings` with `food_cap`,
`Economy.food_used(E)`, `Economy.train_status(E, b)`, `Economy.try_train(E, b)`,
`spawn_trained(E, b, arch)`. Reserves become `E.unit_reserves[arch]` and
`E.building_reserves[arch]`.

## 2. New archetypes + re-bake

New `wb_units.ARCH` entries:
- **farm** (player) / **enemy_farm**: `food_cap` ≈ 6, no `trains`, small footprint
  (radius ≈ 1.6), cheap (≈ 60g). No combat.
- **tower** (player) / **enemy_tower**: `is_building`, static (`speed=0`), `dps`/`range`/
  `interval` set, auto-attacks the nearest enemy in range. Moderate HP, can be razed.
- **enemy_town_hall**, **enemy_barracks**: red/brown recolors of the player rigs;
  `enemy_town_hall` trains the enemy worker, `enemy_barracks` trains grunt/wolf.
- **wilds_worker** ("Ravager"): enemy `worker`-equivalent that harvests for the Wilds.

Bake changes:
- `World.build` adds a southern Wilds **mine + grove** (`World.wilds_mine`,
  `World.wilds_forest`), plus clears scenery around them.
- `ROSTER` gains the Wilds starting workers + worker/army reserves, and **enemy building
  reserves**. `BUILDINGS` gains the Wilds starting base (1 enemy_town_hall, 1
  enemy_barracks at the camp).
- **Offstage building-reserve pools** (per faction, parked far -Y, deactivated):
  player +2 town_hall, +3 barracks, +4 farm, +4 tower; enemy similar. One reserve of each
  buildable type per faction is borrowable as the live placement ghost.

After baking: rename `baked` → `skirmish.pescene`, re-run `tools/build_hud.py`.

## 3. Building placement + worker construction (player)

New module `wb_build`:
- **Build menu:** Laborer selected → command card shows a Build sub-card (Barracks / Farm
  / Tower / Town Hall) with cost + affordability color.
- **Placement mode:** picking a type borrows the matching reserve rig, enables + tints it,
  and each frame moves it to `Camera.pick_ground(cursor)` on `y=0`. Tint **green** if
  valid, **red** if not. Validity: inside bounds (with footprint margin), no overlap with
  any building (`dist > rA+rB+pad`), not on/near a resource node.
- **Confirm (left-click, valid):** deduct cost; the rig becomes a **construction site**
  (HP starts low and ramps to full as it builds; desaturated tint; non-functional — no
  food, no training, towers don't fire). Register it into `E.buildings` with
  `state="site", build_t=def.build_time`. The selected worker(s) get `order="build",
  build_target=site`.
- **Cancel (right-click / Esc / re-click Build):** return the ghost rig to the pool;
  nothing was spent.
- **Construction tick:** a worker with `order="build"` walks to the site (`approach_point`
  at `radius+1`), then on arrival the site's `build_t` counts down (gameplay dt) while a
  worker is adjacent, pick-swing playing. At `build_t<=0`: `state="done"`, full HP,
  functionality on, worker released to idle (or back to its prior harvest job).

## 4. Towers & destroyable buildings (combat)

- Buildings are folded into combat without entering `all_units` (they don't move or take
  separation). `wb_combat` gains a **buildings pass**:
  - **Tower fire:** a completed tower acquires the nearest enemy unit within `range` and
    deals `dps*interval` on `interval`, same cadence as units.
  - **Buildings as targets:** `Combat.acquire` and AI attack-move can target enemy
    buildings; a unit attack-moving into the enemy base auto-acquires the nearest enemy
    building if no enemy unit is closer (so "raze the base" actually progresses).
- `Combat.die` handles buildings: remove from `E.buildings`, park + pool the rig, recount
  that faction's `food_cap`, then re-evaluate the win condition. Construction **sites are
  destroyable** (low HP) — killing one cancels the build (no refund).

## 5. Rally points

- Building selected + **right-click ground** → set `b.rally_x/z`, `b.rally_set=true`.
- Building selected + **right-click resource node** → **smart-rally**: trained workers
  auto-`order_harvest` that node on spawn.
- `spawn_trained` already uses `rally_*`; extend so a trained unit gets a move order to the
  rally (workers smart-harvest if the rally is a node).
- **Marker:** a minimap dot at the rally + a thin world-projected ring drawn on the HUD
  overlay at the rally's `Camera.world_to_screen` position. No new geometry.

## 6. Win / lose

`Game.update` recompute:
- `state.result = "win"` when the enemy has zero standing town halls.
- `state.result = "lose"` when the player has zero standing town halls **or**
  `state.hero_dead`.
- Track standing town halls per faction in `recount` (count `E.buildings` with
  `arch == town_hall/enemy_town_hall`, `state=="done"`, `alive`).
- Objective HUD: "Raze the Wilds' Great Hall" (+ optional standing-hall / foe counts).

## 7. Wilds AI brain (`wb_ai`)

Throttled tick (~0.5s gameplay) driving `state.econ.enemy` like a player:
- **Economy:** assign idle enemy workers to the nearest Wilds resource node; train workers
  at the enemy town hall up to a worker cap.
- **Build order (reactive-threshold):** build a Farm when `food_used` nears `food_cap`;
  keep ≥1 Barracks; drop a Tower near the base when threatened or on a slow timer; expand
  when resources are banked. The AI uses the **same worker-built path** as the player: it
  picks a valid spot near its base (no ghost/placement UI), commits the site, and assigns
  a free Wilds worker `order="build"` to walk over and construct it (pulling the worker off
  harvest, returning it after). Only one site in progress at a time.
- **Army management:** train grunts/wolves at barracks up to an **escalating army
  threshold** (grows with `state.time`).
- **Combat director (reactive):**
  - *Base under attack* (an enemy unit/building took damage recently near the base) →
    recall the army to defend; flee workers to the town hall.
  - *Else army ≥ threshold* → attack-move the army at the player's nearest building,
    biased toward the player Town Hall.
  - *Else* → hold near base.
- Reuses `wb_economy` / `wb_build` / `wb_orders` / `wb_combat`; never touches geometry.

## 8. HUD / module deltas

- **HUD:** Build sub-card (worker selected); construction-site progress bar + label;
  rally markers (minimap + world ring); enemy buildings on the minimap; placement-mode
  banner ("Left-click to place — right-click to cancel"). Resources panel reads
  `state.econ.player`.
- **New modules:** `wb_build`, `wb_ai`.
- **Changed:** `wb_economy` (faction-neutral), `wb_units` (new archetypes + building
  combat fields), `wb_combat` (tower pass + buildings as targets + building death + win
  hook), `wb_orders` (build order + rally issuing), `wb_selection` (building-select
  already exists; ensure rally + build interplay), `wb_hud`, `wb_world` (Wilds nodes +
  clear zones), `wb_game` (econ state, ROSTER/BUILDINGS, AI tick in update, win/lose
  rework, re-bake).
- **Preload order:** util → world → camera → units → selection → orders → combat →
  abilities → economy → build → ai → hud → game.

## 9. Verification

Re-bake on the Debug build (`WB_BAKE=1`), rename, run `build_hud.py`, then playtest on
`--display 1`:
- Player: select a Laborer, build a Farm / Barracks / Tower; worker walks + constructs;
  set a rally point and a smart-rally on a node.
- Wilds: observe gather → build → train → attack; base defense when attacked.
- Both win paths reachable: raze the Wilds' hall (win), lose your hall or hero (lose).
- 0 Lua errors in `PhasmaEngine.log`.

## Open defaults (flag at review if wrong)

- Hero death stays an instant loss (in addition to losing all town halls).
- Construction sites are destroyable and do not refund on cancel-by-destruction.
- Wilds economy is independent (own nodes), not contesting the player's.
- Reserve pool sizes are starting estimates; tune during the bake.
