# TempestRemix

Entry: `Arcade/TempestRemix/run.ps1` starts `Scenes/main.pescene` (run.ps1:29); the scene loads `Assets/Scripts/game.lua`, which loads `Scripts/jev_auto.lua` (game.lua:1228-1229) and registers Jev via `JevAuto.attach` (game.lua:1255-1308). `Scripts/gamekit/driver.lua` is present and byte-identical to the other Arcade games; `observe` is `pcall`-protected (driver.lua:111-167). Automation helper `G.sim` (game.lua:1519).

## Web and level progression

- The tube is a closed rim divided into 16 lanes; every shape is resampled to 16 lanes so movement and hit spacing are identical (game.lua:246-287, 249).
- 8 shapes cycle: CIRCLE, SQUARE, PLUS, TRIANGLE, HEXAGON, STAR, CLOVER, OCTAGON, with 8 tints (game.lua:288-301). `start_level(level)` calls `set_shape(level)` (game.lua:635-646).
- Wave plan by level (game.lua:602-631): flippers `4 + min(10, level)`; tankers `min(4, 1 + floor(level/2))`; spikers from level 2, `min(3, floor(level/2))`; fuseballs from level 3, `min(3, floor(level/3))`; pulsars from level 4, `min(2, floor(level/4))`.
- Spawn delays are per plan entry; enemies enter at depth 1.0 (near 0 = at the rim, far 1 = the hub) (game.lua:602-631, 585-599, 1403-1409).
- Level flow: `levelintro` 1.6 s → `play`; when the plan is empty and no enemies remain → `clear` 0.9 s → `warp` (1.5 s dive + 1.1 s arrival) → next `levelintro` at 0.6 s (game.lua:1387-1390, 1414-1419, 1435-1484).
- Clear bonus: 1000 + 250 × level (game.lua:1418).

## Player actions

- Move along the rim with Left/Right or A/D; max speed `4.6 + min(0.6, (level-1)*0.05)` lanes/s, acceleration 16 (game.lua:865-874).
- Fire with Space, Z or left mouse; cooldown 0.11 s, 10 bolts in the pool, bolt speed 1.55 depth/s (game.lua:533-546, 881-883, 704-749).
- Superzap with Left/Right Shift, X or Left Control: kills every enemy and every spike on the field and is available once per life/level (game.lua:681-701, 642, 1498, 1396).
- P/Escape pause, O settings, M mute (game.lua:1420-1434).

## Enemies and hazards

- Flipper: crawls toward the rim and flips to an adjacent lane every 0.5-1.2 s (game.lua:773-780).
- Tanker: crawls in; when killed by a shot it splits into two flippers on adjacent lanes at slightly offset depths (game.lua:781-782, 672-677).
- Spiker: crawls to depth 0.35 then plants a spike in its lane and retreats; the spike survives in the lane and is lethal near the rim (game.lua:783-793, 548-556, 885-898).
- Fuseball: moves on a half-lane rail with a sinusoidal weave (game.lua:794-796, 595).
- Pulsar: pulses open for 0.7 s and closed for 0.7 s; only the open phase is lethal, and it has a 1.2-lane kill radius instead of 0.75 (game.lua:797-806, 722).
- Any enemy reaching the rim (`depth <= 0.02`) kills if its lane distance is < 0.75 (< 1.2 for an open pulsar) and invulnerability is 0; it then shuffles one lane toward the player every 0.4-0.6 s (game.lua:802-826).
- A spike kills when its depth is < 0.08 and its lane distance is < 0.45; leftover spikes also kill during the warp dive (game.lua:885-898, 1452-1463).

## Scoring

Flipper 150, tanker 100, spiker 50 + up to 100 by proximity, fuseball 250 + up to 500 by proximity, pulsar 200 (game.lua:665-670). A shot that erodes a spike to the end gives 10 (game.lua:735-741). 3 lives; an extra claw at every 20,000 points, capped at 6 (game.lua:16, 567-575, 1166).

## Death and lose

`dying` for 1.4 s, then a life is spent; at 0 lives the state becomes `over`. Otherwise respawn grants 2.0 s invulnerability, restores the superzap, and removes enemies closer than depth 0.25 (game.lua:1485-1503). Level start grants 1.5 s invulnerability (game.lua:643). There is no win state.

## Timers

| Timer | Value | Cite |
|---|---|---|
| Level intro | 1.6 s | game.lua:1390 |
| Level-clear hold | 0.9 s | game.lua:1439 |
| Warp dive / arrival | 1.5 / 1.1 s | game.lua:1444 |
| Death animation | 1.4 s | game.lua:1488 |
| Invulnerability (level / respawn) | 1.5 / 2.0 s | game.lua:643, 1498 |
| Fire cooldown | 0.11 s | game.lua:882 |
| Superzap flash | 0.8 s | game.lua:684 |
| Pulsar open/closed phase | 0.7 s each | game.lua:800 |
| Enemy rim shuffle | max(0.4, 0.6 - level*0.01) s | game.lua:824 |

## Jev attach (game.lua:1255-1308)

`port = 9124`, `id = "tempest-remix"`. `playing()` is `levelintro`, `play`, `clear`, `warp` or `dying`; `terminal()` is `over` (game.lua:1230, 1259-1264). `busy()` is always false (game.lua:1268-1270). `reset(seed)` seeds RNG, clears the zap pulse and camera offset and starts a new game (game.lua:1298-1306).

### observe() fields (game.lua:1272-1281)

- `player_lane` — continuous lane position.
- `enemy_lane` — lane of the nearest enemy; `-1` when none.
- `enemy_depth` — that enemy's depth (0 rim .. 1 hub); `-1` when none.
- `lives`
- `score`

`nearest_enemy` ranks by depth, with lane distance as a 0.001 tiebreak (game.lua:1232-1253).

### action ids (game.lua:1282-1296)

- `"right"` when the signed lane difference to the nearest enemy is > 0.35.
- `"left"` when it is < -0.35.
- `"stop"` otherwise, and also when no enemy exists.
Exactly one action is offered.

### apply(id) (game.lua:1122-1149)

`apply_action` sets hold flags, then `write_hold` publishes them to virtual keys (game.lua:1093-1120):
- `"left"` → `hold.left`, clears right, `hold.fire = true`.
- `"right"` → `hold.right`, clears left, `hold.fire = true`.
- `"stop"` → both steers false, `hold.fire = true`.
- `"fire"` → only sets fire.
- `"left_fire"` / `"right_fire"` → the same as left/right with fire (aliases, never offered).
- `"zap"` → sets `zap_pulse`, which becomes a one-frame virtual Left Shift on the next `write_hold` (game.lua:1113-1119).
- any other id → no flag change, then `write_hold` republishes the current hold.

Steering holds persist until replaced; `stop` keeps the gun firing, so there is no way to stop shooting. `write_hold` clears virtual keys outside `play` (game.lua:1099-1102).

## Jev cannot see

- The enemy kind and state: pulsar open/closed phase, spiker planted/retreating, and which enemies will split into flippers (game.lua:767-801, 672-677).
- Spikes: lane and depth of every planted spike, the hazard that fills the rim (game.lua:548-556, 751-765).
- Every enemy except the single nearest by depth; the rest of the wave, including flankers on other lanes, is invisible (game.lua:1232-1253, 1272-1281).
- The lane count and current shape; 16 is not exposed (game.lua:249, 288-301).
- Superzap availability and cooldown, and the fire cooldown (game.lua:642, 681-684, 882).
- Invulnerability and the death/warp timers (game.lua:643, 1488-1498).
- Level number, level-clear bonus and score-to-extra-claw progress (game.lua:635-646, 567-575, 1418).
- `busy` is hard-coded false, and `playing()` includes `dying` and `warp` where actions do nothing (game.lua:1230, 1268-1270, 1485-1503).
