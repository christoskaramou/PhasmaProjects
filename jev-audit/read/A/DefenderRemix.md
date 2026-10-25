# DefenderRemix — how the game works (read from current source)

Source of truth: `Arcade/DefenderRemix/Assets/Scripts/game.lua` (1321 lines, hand-written; no `tools/src`).
Cites are `Assets/Scripts/game.lua`. Jev wrapper `Assets/Scripts/jev_auto.lua`; driver
`Assets/Scripts/gamekit/driver.lua`. `run.ps1` launches `Scenes/main.pescene` (`run.ps1:29-30`), which loads
`Scripts/game.lua`.

## Shape of a run

- Wrapping world 480 units around (`WW = 480`), floor at y = −13, ceiling at y = 10.5 (`game.lua:61-62`).
- Update splits `dt` into 1/60 s steps (`game.lua:1127-1137`).
- Endless attack waves; there is no win state. New game: score 0, 3 ships, 3 smart bombs, wave 0, 10
  humanoids, planet alive (`game.lua:445`, `1030-1041`, `524-529`).
- Wave flow: `start_wave` builds a queue; when the queue is empty and no non-baiter enemy remains, a 3.2 s
  intermission runs, then the next wave starts (`game.lua:620-656`).

## Player actions

- Horizontal flight: acceleration 40 units/s² in the facing direction, drag `exp(-0.35*dt)` while
  thrusting, `exp(-1.6*dt)` when not; max speed 30 (`game.lua:675-678`).
- Vertical flight: target ±15 units/s, eased at 12/s; y clamped to floor+1.4 .. ceiling
  (`game.lua:679-681`).
- Facing flips with the horizontal input direction and yaw eases 10/s (`game.lua:674`, `683`).
- Fire: Space/J/Z/Left Ctrl, cooldown 0.11 s; up to 8 lasers; each laser extends at 190 units/s, starts
  retracting after 0.12 s and lives at most 0.6 s (`game.lua:474-484`, `704-712`, `1119`).
- Smart bomb: B/X, requires a bomb, kills every enemy within the view (+4) and clears mines in that range
  (`game.lua:589-596`).
- Hyperspace: H/C, 2.5 s cooldown, teleports to a random x and y and grants 1.0 s invulnerability
  (`game.lua:597-606`).
- Carry a falling humanoid by flying within 2.2 x / 2.0 y; it is set down when the ship drops below
  floor+3, scoring 500 for the catch and 500 for the return (`game.lua:698-702`, `858-859`).
- Player invulnerability blinks the ship (`game.lua:685-686`).

## Hazards and what kills the player

- Collision with any enemy body: |dx| < `KIND.r + 1.4`, |dy| < `KIND.r*0.8 + 0.4`; both the enemy and the
  player die (`game.lua:829-832`).
- Enemy bullets: lifetime 3 s, speed `10 + wave*0.6`, aimed with lead; hit within 1.6 x / 0.6 y kills the
  player (`game.lua:539-552`, `875-884`).
- Mines dropped by bombers: lifetime 7 s; hit within 1.4 x / 0.7 y kills the player
  (`game.lua:553-555`, `887-897`).
- A player laser can also kill a falling/carried humanoid (`game.lua:725-730`).
- Death: 2.4 s later one ship is lost; at 0 the run ends, otherwise respawn at the start with 2.0 s
  invulnerability (`game.lua:1138-1146`, `1027-1029`).
- Losing all 10 humanoids destroys the planet: the ground/cities disappear and every lander becomes a
  mutant; the run continues (`game.lua:607-616`, `351-367`).

## What the player can shoot

| Enemy | Pool | HP/hits | Points | Radius |
|---|---|---|---|---|
| Lander | 20 | 1 | 150 | 1.7 |
| Mutant | 20 | 1 | 150 | 1.6 |
| Bomber | 6 | 1 | 250 | 1.5 |
| Baiter | 5 | 1 | 200 | 1.8 |
| Pod | 5 | 1 | 1000 | 1.6 |
| Swarmer | 24 | 1 | 150 | 1.05 |

All from `kind` table `game.lua:487-494`; a laser kills on the first hit inside its swept segment
(`game.lua:718-724`). A killed pod bursts into 4 swarmers (`game.lua:571`). Killing a lander holding a
humanoid drops it into a fall (`game.lua:570`).

## Humans, landers and the planet

- 10 humanoids walk on the ground at 0.9 units/s, reversing randomly (`game.lua:517-529`, `844-847`).
- Landers hunt: they pick an un-targeted walking humanoid within 90 units, fly above it, descend, and grab
  it when within 3 units of its y (`game.lua:758-791`).
- A carried humanoid rises with the lander at `3.2 + 0.15*wave`; at the ceiling it becomes a Mutant and the
  human is lost (`game.lua:749-757`).
- A falling humanoid is caught by the ship for 500, set down for another 500; if it hits the ground after
  falling more than 9 units it dies, otherwise it lands safely for 250 (`game.lua:855-863`, `698-702`).
- If all humanoids die, `planet_boom` runs once; every wave number ≡ 1 mod 5 (above 1) restores the
  planet and all humanoids (`game.lua:607-616`, `627`, `578`).

## Waves

- `start_wave` queues `min(20, 8 + 2*wave)` landers, `min(1 + floor(wave/2), 4)` bombers, and from wave 2
  `min(wave-1, 3)` pods (`game.lua:620-627`).
- Spawns 4 queue entries at a time every 3.0 s, at a random x around the player and y near the ceiling,
  with a 0.6 s scale-in (`game.lua:633-642`).
- After 45 s in a wave, baiters spawn every `max(5, 12-wave)` s; baiters do not block wave completion
  (`game.lua:643-648`).
- Wave complete when the queue is empty and no non-baiter enemy is alive; bonus is
  `humans_alive * 100 * min(wave,5)` (`game.lua:647-654`).
- Enemy fire cadence: lander 2.8, mutant 1.6, baiter 1.2, swarmer 3.0 (bomber/pod never shoot), scaled by
  `max(0.45, 1 - wave*0.06)` and randomised 0.6–1.4 (`game.lua:822-826`).
- Behaviour: mutants and swarmers home on the ship; bombers fly sideways and drop mines every 0.9–1.6 s;
  pods drift; baiters chase a point behind the ship at speed 31 (`game.lua:794-811`).

## Timers and durations

| Timer | Value | Cite |
|---|---|---|
| Player fire cooldown | 0.11 s | `game.lua:694` |
| Laser life | 0.6 s | `game.lua:712` |
| Laser retract start | 0.12 s | `game.lua:710` |
| Hyperspace cooldown | 2.5 s | `game.lua:599` |
| Hyperspace invulnerability | 1.0 s | `game.lua:603` |
| Respawn invulnerability | 2.0 s | `game.lua:1028` |
| Player death to life loss | 2.4 s | `game.lua:1138` |
| Enemy bullet life | 3 s | `game.lua:879` |
| Mine life | 7 s | `game.lua:890` |
| Wave intermission | 3.2 s | `game.lua:650` |
| Spawn batch interval | 3.0 s | `game.lua:635` |
| Baiter spawn interval | `max(5, 12-wave)` s after 45 s | `game.lua:643-645` |

No ladders, freezes, slow effects or pickups.

## Score, extra ships, win/lose

- Kills give the table above; humanoid catch/set-down/landing give 500/500/250; wave bonus as above
  (`game.lua:569`, `701`, `859`, `862`, `651`).
- Extra ship at every 10000 points, and each also grants +1 smart bomb (`game.lua:451-454`, `1032`).
- Hi-score loaded from `Save/defender_hiscore.txt`, saved on game over only when Jev was not assisted
  (`game.lua:447-448`, `1144`).
- Win: **none**; waves continue indefinitely.
- Lose: `lives <= 0` after a death → state `over` (`game.lua:1141-1145`).

## JevAuto.attach for this game

Attach block `game.lua:1299-1318`, port 9123, id `defender-remix`.

`observe()` returns exactly `ship` (`{x, y, facing}`), `enemy` (a table `{kind, x, y, dx, dy}` or nil),
`humanoid` (a table `{x, y, state, dx, dy}` or nil), `lives`, `score` (`game.lua:1267-1286`).
The wrapper adds `mode`, `terminal`, `score`, `busy`, `actions` (`jev_auto.lua:54-61`).
- `enemy` is the nearest enemy by `|dx| + 2*|dy|` across all kinds (`game.lua:661-665`).
- `humanoid` is the alive humanoid that is falling, carried, or targeted by a lander, nearest to the ship;
  its `state` is `fall`, `carried`, or `hunted` for a targeted walker (`game.lua:1209-1237`).
- No `busy` hook is defined, so busy is always false.

Action ids produced by `actions()` (`game.lua:1239-1265`): `thrust_fire`, `climb`, `dive`, `reverse`.
- Uses the humanoid in trouble if any, otherwise the nearest enemy; if neither, `thrust_fire`.
- |dy| > |dx| and |dy| > 1.2 → `climb` (dy > 0) or `dive` (dy < 0).
- Target behind the current facing and |dx| > 0.8 → `reverse`.
- Otherwise → `thrust_fire`.

`apply(id)` (`game.lua:1187-1207`): clears all virtual holds first, then
- `thrust` / `thrust_fire` hold the current facing direction; `reverse` holds the opposite direction
  (`game.lua:1175-1185`, `1190-1198`).
- `climb` holds Up; `dive` holds Down (`game.lua:1195-1196`).
- `bomb` and `hyperspace` queue a one-shot pulse (`game.lua:1198-1202`).
- `fire`, `thrust_fire` and every direction id also hold Space, so the gun keeps firing
  (`game.lua:1204-1206`).
- Unknown ids only clear the holds.
- `reset(seed)` seeds random, clears holds and starts a new game (`game.lua:1288-1295`);
  `on_human` clears holds (`game.lua:1317`).

## Jev cannot see

- Wave number, the wave queue, and how many enemies remain.
- All enemies except the nearest one; enemy HP is 1 everywhere, but their fire timers and velocities are
  hidden.
- The other nine humanoids, the count of living humanoids, and whether the planet is already lost.
- Bombs (smart-bomb count), and whether a bomb or hyperspace is available.
- Incoming enemy bullets and mines as objects — the two things that actually kill the ship.
- Own velocity, invulnerability timer, hyperspace cooldown, and camera/wrap offset.
- Lasers in flight and the 8-laser pool.
- That there is no win condition; only `lives` and `score` are exposed.
