# OutRunRemix

Entry: `Arcade/OutRunRemix/run.ps1` starts `Scenes/main.pescene` (run.ps1:29); the scene loads `Assets/Scripts/game.lua`, which loads `Scripts/jev_auto.lua` and attaches Jev inside a nested function (game.lua:1560-1605), then registers `hooks{update}` (game.lua:1735). `Assets/Scripts/gamekit/driver.lua` is present and identical to the other Arcade games; its `observe` wrapper is `pcall`-protected and rejects malformed actions (driver.lua:111-167).

## Route

5 stages, each with a left/right fork into the next row of a 15-road map; 5 goals A-E (game.lua:370-379). Segment length 5 m, road half-width 9 m, 4 lanes, fork 110 segments long with 46 m of lateral separation, choice locked at fork segment 70, 820 segments per road (game.lua:344-351, 586). Start time 75 s; each stage entry adds 64, 62, 60, 58 s respectively (game.lua:379, 649-651).

## Stage flow

Title → `count` 3 s (game.lua:1412, 1644-1648) → `play` → `goal` when the stage-5 road ends → `over`. Pause is `pause`, and a time-out becomes a `timeup` car state that ends in `over` (game.lua:1650-1665, 1694).

## Driving

- Low gear max 190 km/h (52.8 m/s), high gear max 293 km/h (81.4 m/s) (game.lua:545).
- Acceleration: low `9.5 * (1 - v/VMAX_L)^0.6`; high `8.0 * (1 - (v/VMAX_H)^2) * bog`, with `bog = clamp((v-8)/22, 0.22, 1)` (game.lua:734-738). Releasing the gas decelerates by `1.2 + 0.025v`; the brake is −16 m/s²; the high-gear soft limiter applies −6 above max (game.lua:747-752).
- Gear shifts on Space, Left/Right Shift, right click, or the `gear` action, toggling L/H (game.lua:742, 1670-1674).
- Steering is damped toward input with rate 9, lateral speed `steer * min(v,55) * 0.3`, plus curve drift `curve(rad)/SEG * v² * 0.33` (game.lua:761-767). Skid sound and flag when drift > 9, steer > 0.6 and v > 45 (game.lua:769-773).
- Off-road (beyond half-width + rumble) caps acceleration with −14 above 120 km/h and shakes the camera (game.lua:753-758, 567-579).
- Distance score: while in `drive` and moving, `floor(v * 3.6 * dt * 250 * (offroad and 0.3 or 1))` points (game.lua:775).

## Forks and checkpoints

- The fork pick is the sign of lateral offset once |x| > 2.5 m; it locks when the chosen branch is fully under the car or at fork segment 70 (game.lua:618, 657-663). A banner names the chosen road (game.lua:625).
- Entering a new stage row adds that row's extension to the clock and records the stage lap time (game.lua:646-655).
- Reaching the end of stage 5 sets the goal: `bonus = floor(max(0, time)) * 250000`, goal letter = `GOALS[col]` (game.lua:665-671).

## Traffic and collisions

- Traffic density `9 * theme.traffic` cars, spawned 330-590 m ahead, in lanes ±6.75 / ±2.25, speed 16-31 m/s (trucks 15-22) (game.lua:586-602).
- Hitting a car: if closing speed > 22 m/s the car state becomes `spin` (1.4 s); otherwise a bump. In both cases own speed is capped to `0.8 * traffic speed` and the car is pushed behind the traffic (game.lua:711-731).
- Scenery collision: a solid object inside `halfwidth + car half width` stops the car at ≤70 km/h, or at higher speed calls `crash` (game.lua:683-710). Crash state lasts 3.2 s, then resets to low gear at the same place (game.lua:780-787). Crash blocks time loss? No — the clock also runs during crash and spin (game.lua:795-799).
- `god` mode halves speed instead of crashing (game.lua:676).

## Timers, win and lose

| Timer | Value | Cite |
|---|---|---|
| Countdown | 3 s | game.lua:1648 |
| Stage start clock | 75 s | game.lua:379 |
| Checkpoint extension | +64 / +62 / +60 / +58 s | game.lua:379, 650 |
| Spin-out | 1.4 s | game.lua:779 |
| Crash recovery | 3.2 s | game.lua:783 |
| Goal bonus delay | 1.5 s | game.lua:1658 |
| Goal auto-finish | 6 s | game.lua:1659 |
| Fork lock banner | 2.2 s | game.lua:625 |
| Game-over input lock | 1.2 s | game.lua:1662 |

- Win: finish stage 5 → `goal` state → `game_over(true)` after 6 s or Return/Space after 2 s (game.lua:1656-1659).
- Lose: clock reaches 0 → `timeup`; the car brakes to a stop; once `v < 0.5` and `t > 2` → `game_over(false)` (game.lua:798, 1694). Crashing does not itself end the run.
- The clock ticks during `drive`, `spin` and `crash` (game.lua:795-799).
- High score is not saved when Jev is the assisted player (game.lua:1423).

## Jev attach (game.lua:1563-1604)

`port = 9135`, `id = "outrun_remix"`. `playing()` is `count`, `play`, `pause` or `goal`; `terminal()` is `over` (game.lua:1531-1534, 1567-1570). `busy()` is always false (game.lua:1574-1576).

### observe() fields (game.lua:1580-1587)

- `speed` — current m/s, rounded to 2 decimals.
- `lateral_offset` — `P.x` in the current road frame, rounded to 2 decimals.
- `next_curve` — `"left"`, `"right"` or `"straight"`, from the first segment within 120 ahead whose |curve| > 0.2°/segment; positive curve is a left bend (game.lua:1536-1554).
- `score` — current score.

### action ids and apply(id) (game.lua:1474-1503, 1588-1597)

`apply_drive` holds or releases virtual keys (game.lua:1453-1467):

| id | Effect |
|---|---|
| `left` | release Right/D, hold Left/A, release brake, hold gas (game.lua:1475-1479) |
| `right` | release Left/A, hold Right/D, release brake, hold gas (game.lua:1480-1484) |
| `straight` | release both steer keys, release brake, hold gas (game.lua:1485-1489) |
| `gas` | release brake, hold gas (game.lua:1490-1492) |
| `brake` | release gas, hold brake (game.lua:1493-1495) |
| `coast` | release gas and brake (game.lua:1496-1498) |
| `gear` | set `G.vk.Gear` for one frame, consumed as a shift pulse (game.lua:1499-1502, 1670-1674) |

`actions()` first calls `drive_action` (game.lua:1505-1530), which picks the steer that avoids the nearest traffic car within 22 m ahead (`left` if it is to the right, `right` if to the left), else recentres when |x| > 1.4, else `straight`. Then, if that result is `straight` and `next_curve` is left or right, it replaces it with the bend action at score 2 (game.lua:1588-1597). Exactly one action is offered.

Holds persist until replaced; only `brake`/`coast` release the gas.

## Jev cannot see

- Traffic: position, lane, speed, closing rate — the only moving hazard (game.lua:586-609, 711-731).
- Its own `s` distance, current stage/row, goal letter, and the fork pick/lock state (game.lua:641-671).
- Remaining time, and whether it has entered `timeup` (game.lua:796-798).
- The car state (`drive`/`spin`/`crash`/`goal`/`timeup`), gear, and steering input (game.lua:548, 742, 777-791).
- Off-road state and surface type, even though they change acceleration and score rate (game.lua:567-579, 753-758).
- Traffic and scenery are invisible to `next_curve`, which only reports a bend direction from the road geometry, not its magnitude or distance (game.lua:1536-1554).
- `busy` is hard-coded false, so a reply during a spin or crash looks actionable (game.lua:1574-1576).
- `playing()` includes `pause` and `goal`, so actions can be offered while the sim is not stepping (game.lua:1531-1534, 1688).
