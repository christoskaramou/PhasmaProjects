# SpyHunterRemix

Entry: `Arcade/SpyHunterRemix/run.ps1` starts `Scenes/main.pescene` (run.ps1:29); the scene loads `Assets/Scripts/game.lua`.

**`game.lua` is generated.** `tools/build_lua.sh` concatenates `tools/src/0*.lua` into `project/Assets/Scripts/game.lua` (SpyHunterRemix/tools/build_lua.sh:1-3). The rules below are cited from the generator (`tools/src/03_course.lua`, `tools/src/04_sim.lua`), which is the source of the runtime copy; the Jev attach is cited from `Assets/Scripts/game.lua` because it sits in a later source part. `Scripts/jev_auto.lua` is loaded at game.lua:1159-1160. `Scripts/gamekit/driver.lua` is present and its `observe` wrapper is `pcall`-protected (driver.lua:111-167).

## Course and vehicle modes

The road is a looping list of segments (road, bridge, dock, river) with eased centre, half-width and island width; a lap is `G.TOTAL` metres and each lap changes season (04_sim.lua:5-17, 236-237). Being on the surface requires `|x - centre| <= half width` and `>= island width`; the car cannot use river segments and the boat only river/dock (03_course.lua:29-36). Car↔boat swaps at the boathouse using the vehicle's leading edge (04_sim.lua:224-235).

## Driving and scoring

- Speed starts at 10, max 26; accelerate 13/s, brake 22/s, no reverse (04_sim.lua:10, 47-55, 216-221).
- Steering strength `(3 + v*0.18) * input`, eased at rate 10 (04_sim.lua:218-219).
- Distance score: 5 points per metre travelled (04_sim.lua:222-223).
- Off the drivable surface crashes the car, unless invulnerable, in which case it is eased back to a safe lane (04_sim.lua:238-241).

## Crashes, cars and game over

- `crash` sets the crash phase; after 2.0 s a car is spent unless the opening 60 s of free cars is still running; at 0 cars the game ends (04_sim.lua:70-76, 183-198).
- Respawn places the player on a safe lane for the roll-out ahead and grants 2.5 s invulnerability (04_sim.lua:192-195). Initial invulnerability is 2 s (04_sim.lua:49).
- An extra car at every 10,000 points (04_sim.lua:56-60).

## Weapons

- Machine guns fire a pair of bullets, max 8 player shots alive, speed `44 + v` (04_sim.lua:109-113, 280).
- Drive into the back of the weapons van (behind it, within 0.35 x) to dock for 1.3 s; it then grants the next weapon in the cycle smoke → oil → missile, with 8 / 8 / 4 ammo (04_sim.lua:106-108, 200-212, 258-262).
- Special weapon: missile is a forward shot (4 ammo) that homes on the helicopter; oil and smoke are dropped behind and spin enemies that drive into them (04_sim.lua:114-121, 322-332).
- The Road Lord (`rl`) is bulletproof — bullets only spark; a missile wrecks it (04_sim.lua:297).
- The helicopter can only be destroyed by a missile, for 1500 (04_sim.lua:292).

## Enemies, hazards and what kills the player

- Spawns: one traffic item every `rr(1.0,2.2) - min(0.6, y/4000)` s while fewer than 7 are alive (04_sim.lua:246-248). Cars: civilian when r < 0.38, truck < 0.50, Switch Blade < 0.68, Road Lord when r < 0.84 (or whenever y < 300), Enforcer otherwise (04_sim.lua:98-103). On the river: enemy boat or dumper (04_sim.lua:93-96).
- Switch Blade: pulls alongside and its tyre slashers crash the player after 0.5 s within 0.9 lateral and 0.6 longitudinal (04_sim.lua:135-146).
- Enforcer: pulls alongside and fires when within 0.8 longitudinally, every 1.6-2.4 s (04_sim.lua:147-153).
- Helicopter ("Mad Bomber"): hovers 9 m ahead, drops bombs every 1.3-2.0 s; a bomb landing within 0.7 x and 0.9 y crashes the player; it leaves after 26 s (04_sim.lua:154-160, 313-321).
- Enemy boat: closes from behind and fires torpedoes straight ahead when aligned (04_sim.lua:161-166).
- Dumper: drops barrels ahead every 1.2-2.0 s when within 22 m; a barrel contact crashes the player (04_sim.lua:167-169, 333-335).
- Crater contact crashes a car (not a boat) (04_sim.lua:335).
- Enemy shots and torpedoes crash the player inside the player box (04_sim.lua:305-311).
- Contact with any enemy does not itself crash; it shoves both vehicles, and an enemy pushed off the surface is wrecked (04_sim.lua:256-274).
- Destroying a civilian or truck **by the player** freezes scoring for 6 s and shows a penalty banner; other kills award points: Switch Blade / Road Lord / Enforcer 500, helicopter 1500, enemy boat / dumper 700, other 300 (04_sim.lua:6, 63-69).
- Gun hits: enemy hp values are sw 2, enf 3, eboat 2, dumper 2, civ 1, truck 2; a hit reduces hp and wrecks at 0 (04_sim.lua:79-84, 288-299).

## Stage timers

| Timer | Value | Cite |
|---|---|---|
| Free cars at start | 60 s | 04_sim.lua:48, 181 |
| Crash before respawn | 2.0 s | 04_sim.lua:185 |
| Respawn invulnerability | 2.5 s | 04_sim.lua:194 |
| Van docking | 1.3 s | 04_sim.lua:205 |
| Civilian-kill score freeze | 6 s | 04_sim.lua:67 |
| Helicopter lifetime | 26 s | 04_sim.lua:159 |
| Oil/smoke drop lifetime | 20 s or 14 m behind | 04_sim.lua:337 |

No win state: the run ends when cars reach 0 after a crash.

## Jev attach (game.lua:1303-1354)

`port = 9140`, `id = "spyhunter-remix"`. `playing()` is `play`; `terminal()` is `over` (game.lua:1307-1312). `busy()` is always false (game.lua:1316-1318). `reset(seed)` seeds RNG, starts a match and primes the human-key sampler (game.lua:1349-1353).

### observe() fields (game.lua:1321-1328)

- `lane_offset` — signed offset from the current lane centre; on a split road the centre is taken on the player's side of the island (game.lua:1218-1230).
- `speed` — `G.P.v`.
- `nearest_enemy_ahead` — `{distance, side, kind}` of the nearest hostile with `y > player y`; `distance = -1`, `side = 0`, `kind = ""` when none (game.lua:1232-1250).
- `score`

### action ids (game.lua:1329-1347)

- `"left"` when `lane_offset > 1.1`.
- `"right"` when `lane_offset < -1.1`.
- otherwise, if a hostile is within 28 ahead: `"right"` when `side > 0.35`, `"left"` when `side < -0.35`.
- otherwise `"straight"`.
Exactly one action is offered, so `gas`, `brake`, `guns` and `special` are never proposed even though `apply` handles them (game.lua:1170-1178).

### apply(id) (game.lua:1252-1290)

- `"left"` / `"right"` / `"straight"` first clear Left/Right/A/D and Down/S (so brake is released), then set the steer key (except straight), set Up (gas), and set `pulse_guns`.
- `"gas"` clears Up/Down/W/S, then sets Up.
- `"brake"` clears Up/Down/W/S, then sets Down.
- `"guns"` sets `pulse_guns` only.
- `"special"` sets `pulse_special` only.
- Unknown ids do nothing beyond the initial table creation.

`pulse_guns` and `pulse_special` are consumed on the next update into one-frame `fire`/`special` inputs (game.lua:1440-1453), so guns fire one burst per action and the special weapon only if one is stocked.

## Jev cannot see

- Its vehicle mode (car/boat), the current course segment kind, road half-width, island width and the boathouse position; only a lane offset is exposed (game.lua:1321-1328, 03_course.lua:19-27).
- Weapon and ammo, the weapons van, and the dock state (04_sim.lua:200-212, game.lua:1321-1328).
- The free-car timer, remaining cars, the 2.0 s crash/respawn state and invulnerability (04_sim.lua:48, 183-198).
- Enemy health, spin/knockback state, and whether an enemy is a civilian, truck, Road Lord (bulletproof) or other kind — `kind` is exposed but no hp or bulletproof flag (04_sim.lua:79-84, 288-299).
- Enemy shots, torpedoes, helicopter bombs, barrels and craters — all incoming hazards are absent from `observe` (04_sim.lua:305-338).
- The nearest enemy only when it is ahead; enemies alongside or behind (Switch Blade, Enforcer, enemy boat) are invisible even though they are what kills the player (game.lua:1232-1245).
- Season/lap and the score-freeze timer (04_sim.lua:67, 236-237).
- `busy` is hard-coded false (game.lua:1316-1318).
