# RiverRaidRemix

Entry: `Arcade/RiverRaidRemix/run.ps1` starts `Scenes/main.pescene` (run.ps1:29); the scene loads `Assets/Scripts/game.lua`, which loads `Scripts/jev_auto.lua` (game.lua:1335-1336) and registers `hooks{init,update}` (game.lua:1406). `Scripts/gamekit/driver.lua` is present and byte-identical to the other Arcade games; `observe` is `pcall`-protected (driver.lua:111-167).

## World and stage sections

- Vertical scroller: the player flies up (decreasing z) along a procedurally generated river. One section is 56 rows; each section boundary row carries a bridge (game.lua:151, 442-444). Row spacing `ROW`; the field extends 34 units of land either side (game.lua:152-155).
- River half-width and island half-width are generated per section from a deterministic LCG and interpolated between rows (game.lua:162-232). Section 0 starts as a fixed 8.5-wide channel (game.lua:190).
- Rows are streamed 26 ahead and 6 behind the player (game.lua:160, 480-495).

## Player actions and flight

- Left/Right or A/D strafe; Up/W speeds up to 25, Down/S slows to 9, otherwise 15; Space/Z/J/X fires (game.lua:747-789, 155-157).
- Steering is eased: input is damped, target lateral speed is ±8, lateral acceleration 26, and velocity is damped again (game.lua:773-781).
- Missiles: at most 2 alive, 0.2 s cooldown, speed `player speed + 48` (game.lua:659-673, 846-874).
- Altitude is fixed at 1.55; the player does not climb or descend (game.lua:154, 653).

## Fuel

- Starts at 1.0 and drains `1/38` per second × `(0.55 + 0.45 * speed/15)` (game.lua:158, 808).
- Flying over a fuel depot within the depot hitbox (`+0.7 x`, `+0.9 z`) refuels at 0.42/s (game.lua:793-804, 708-710).
- Fuel 0 kills the player with `OUT OF FUEL` (game.lua:814). Below 0.25 a low-fuel beep plays every 0.9 s (game.lua:810-813).

## Enemies and scoring

Kinds and hitboxes: ship 30 points, helicopter 60, enemy jet 100, fuel depot 80, bridge 500 (game.lua:424-430).

- Ships and helicopters patrol laterally, reversing at banks/islands, and only activate within 26 rows ahead of the player (game.lua:885-903).
- Enemy jets fly laterally at 7-10 + 3×difficulty and wrap at ±0.7 × 34 (game.lua:913-921).
- Bridges block the channel, are destroyed by a missile or by hitting them, and set the checkpoint to that section; destroying one adds 500 and increments the bridge counter (game.lua:687-706, 691-699).
- Entity spawn: bridge on every section boundary unless already down; otherwise rows 6..51 of each section (and not the first 10 rows of section 0), with 36% + 20%×difficulty chance, halved on odd rows; every 15th row (k%15==13) forces a depot. Kind by roll: depot < 0.21−0.05×diff, ship < 0.58, heli < 0.9−(0.12 if section ≥ 1), else enemy jet (game.lua:440-478).
- Ships/helis/depots are placed in the water with lane-width checks; a ship that cannot fit may become a helicopter, otherwise the row spawns nothing (game.lua:468-478).
- Extra life each time the score crosses a 10,000 boundary (game.lua:680-685).

## Death, checkpoints, win and lose

- Banks and islands kill on contact within the probe points (game.lua:816-821).
- Any non-depot entity collision destroys the entity (and awards its points) and then kills the player; a bridge collision always destroys the bridge and kills the player. The 1.5 s spawn invulnerability suppresses collisions (game.lua:822-830, 737).
- `player_die` removes a life, stops the thruster effects and clears missiles (game.lua:718-730).
- After 2.3 s dead, respawn at the last destroyed-bridge checkpoint if lives remain, else `gameover` (game.lua:1240-1257).
- 4 lives at the start (game.lua:1098). There is no win state; the run ends when lives reach 0.
- The best score is not saved when Jev is the assisted player (game.lua:1087-1089).

## Timers

| Timer | Value | Cite |
|---|---|---|
| Spawn invulnerability | 1.5 s | game.lua:737 |
| Missile cooldown | 0.2 s | game.lua:661 |
| Missile lifetime range | 46 units ahead | game.lua:871 |
| Respawn delay | 2.3 s | game.lua:1240 |
| Low-fuel beep interval | 0.9 s | game.lua:810-812 |
| Refuel tick sound | 0.11 s | game.lua:800-801 |
| Bridge banner | 1.8 s | game.lua:699 |

No freeze or slow effect; Up/Down only change speed.

## Jev attach (game.lua:1337-1403)

`port = 9110`, `id = "river-raid-remix"`. `playing()` is `play`; `terminal()` is `gameover` (game.lua:1341-1346). `score()` returns the final score while terminal, otherwise the live score (game.lua:1347-1352). No `busy()` hook.

### observe() fields (game.lua:1354-1373)

Live shape:
- `x` — player lateral position.
- `speed` — current forward speed.
- `obstacle` — `{kind, x, ahead, w}` from `nearest_obstacle` (game.lua:1263-1313): the nearest live entity ahead (kind, x, half-width), or a `"bank"`/`"island"` entry derived from the river geometry, with `ahead` as its distance and `kind = "none"`, `ahead = 0` when nothing is close.
- `fuel` — 0..1.
- `lives`
- `score`

On the game-over frame the same field names are filled from `G.final` plus `obstacle = G.final.obstacle` (game.lua:1355-1363, 1246-1254).

### action ids (game.lua:1374-1394)

- `"left"` when the nearest obstacle is < 22 ahead and `ob.x >= 0` (obstacle to the right), or when it is an island and `x >= 0`.
- `"right"` for the mirror case.
- `"left"` when no obstacle is near and `x > 1.2`; `"right"` when `x < -1.2`.
- `"faster"` otherwise.
Exactly one action is offered.

### apply(id) (game.lua:1315-1333)

`apply_hold` **replaces** `G.vkeys` with a fresh table, so the previous hold is dropped:
- `"left"` → Left + Space
- `"right"` → Right + Space
- `"faster"` → Up + Space
- any other id → returns without touching the current keys

Space is part of every action, so the gun fires continuously while any hold is active. There is no action for braking, and no id for "fire" alone.

## Jev cannot see

- The river ahead beyond the single nearest obstacle: channel half-width, island position, and the bridge row are not exposed, so there is no line to plan (game.lua:1263-1313, 220-232).
- Fuel depots as a refuel plan: a depot only appears if it is the nearest obstacle, and `actions` then offers to dodge it rather than fly over it (game.lua:1263-1313, 1377-1385).
- The forward speed limits (9/15/25) and the fact that `faster` holds Up; only the current speed is given (game.lua:155, 782).
- Spawn invulnerability and the respawn/checkpoint timers (game.lua:737, 1240-1243).
- Bridge count, checkpoint section, and `bridges_down` (game.lua:691-699, 1098-1099).
- Missile state: cooldown and both in-flight missiles (game.lua:659-673).
- Entity activation state and lateral direction/speed beyond the nearest obstacle's current x and half-width (game.lua:885-921).
- `busy` is absent, so a reply during the 2.3 s death/respawn gap still looks actionable (game.lua:1240-1257).
