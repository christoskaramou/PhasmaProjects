# RobotronRemix

Entry: `Arcade/RobotronRemix/run.ps1` starts `Scenes/main.pescene` (run.ps1:29); the scene loads `Assets/Scripts/game.lua`, which defines `attach_jev()` using `Scripts/jev_auto.lua` (game.lua:1188-1194, 1394) and registers `hooks{init,update}` (game.lua:1403). `Scripts/gamekit/driver.lua` is present and byte-identical to the other Arcade games; `observe` is `pcall`-protected (driver.lua:111-167). Automation helper `G.sim` (game.lua:1406-1412).

## Arena and hero

- One hero in a walled arena; the wave spawns around it (game.lua:319-342, 853-871).
- Move with WASD or arrows at 10.5 units/s, damped; aim with the mouse (projected onto the play plane) and fire with left click or Space (game.lua:786-830).
- Fire cooldown 0.085 s, bolt speed 44, 14 bolts in the pool (game.lua:440, 466-480, 826-828).
- Spawn/respawn invulnerability 1.2 s at wave start, 2.2 s on respawn (game.lua:863, 880).
- 3 lives at the start; an extra life at each 25,000-point boundary, capped at 9 (game.lua:1034, 462-464).

## Waves and stage progression

Wave composition (game.lua:848-852):

| Enemy | Count | Wave rule |
|---|---|---|
| Grunt | `min(46, 10 + 4w)` | every wave |
| Electrode | `min(18, 4 + 2w)` | every wave |
| Hulk | `min(9, 1 + w)` | wave ≥ 2 |
| Spheroid | `min(4, floor(w/2))` | wave ≥ 2 |
| Brain | 6 on waves divisible by 5; 2 above wave 5; else 0 | `w % 5 == 0` |
| Mommy / Daddy | `min(4, 1 + floor(w/3))` each | every wave |
| Mikey | `min(4, 1 + floor(w/4))` | every wave |

Spawn order is electrode, mom, dad, kid, hulk, spheroid, brain, grunt, with 0.1 s warp delay plus 0.025 s per item (game.lua:865-871). The intro lasts 1.6 s (game.lua:1162). A wave clears when no enemy with `info.kill` remains — grunts, spheroids, enforcers and brains count; hulks and electrodes do not (game.lua:406-414, 430, 1098). The clear state holds 2.0 s, then the next wave starts (game.lua:1177).

## Enemies

- Grunt: homes on the hero with a sinusoidal wobble, speed `min(9, 2.0 + wave*0.22 + wave_t*0.06)`, reduced to 30% while the hero is dead (game.lua:557-564).
- Hulk: wanders on a 1.0-2.6 s timer, 75% of the time stepping toward the nearest human, otherwise 35% toward the hero; speed 2.2 + min(2, wave*0.1). Shots only push it back by 0.45 and never kill it. Contact within 1.4 kills a human (game.lua:566-589, 705-708).
- Electrode: stationary, spinning; kills on contact (game.lua:591, 678-683).
- Spheroid: drifts to random points at speed 9, spinning, and spawns up to 4 enforcers on a 2.0-3.5 s timer (game.lua:592-603).
- Enforcer: homes at 6.5 with a sine weave and fires an orb at the hero every `rr(1.4,2.8) * max(0.5, 1 - wave*0.03)` s with lead and speed `13 + min(6, wave*0.4)` (game.lua:604-616).
- Brain: hunts the nearest human at 3.2 and fires at the hero every 2.5-4.5 s; reaching a human within 1.0 kills them (game.lua:617-627).
- Humans wander at 1.6; touching one rescues it (game.lua:628-635, 678-682).

## Score, rescue and death

- Kills: grunt 100, electrode 25, spheroid 1000, enforcer 150, brain 500; hulk 0 (game.lua:406-414, 496-503).
- Shooting an enemy orb gives 25 (game.lua:717-721).
- Rescue: `rescue_n` increments up to 5 and awards `1000 * rescue_n`, so 1000, 2000, 3000, 4000, 5000 within a wave; `rescue_n` resets at wave start (game.lua:512-522, 862).
- Hero death: contact with a non-human enemy inside `(r + 0.45)`, an enemy orb inside 0.55, both only when `inv <= 0` (game.lua:678-683, 729-734). Humans are rescued, not fatal.
- `hero_die` sets `dead`; after 2.0 s a life is spent and the hero respawns at the centre with nearby enemies pushed out, or the game ends when no lives remain (game.lua:524-534, 878-888, 1093-1097).

## Timers

| Timer | Value | Cite |
|---|---|---|
| Wave intro | 1.6 s | game.lua:1162 |
| Wave-clear hold | 2.0 s | game.lua:1177 |
| Death before life spent | 2.0 s | game.lua:1095 |
| Invulnerability (wave / respawn) | 1.2 / 2.2 s | game.lua:863, 880 |
| Fire cooldown | 0.085 s | game.lua:827 |
| Enemy orb life | 4 s | game.lua:733 |
| Spawn warp | 0.55 s | game.lua:638 |

No freeze or slow effect.

## Jev attach (game.lua:1353-1391)

`port = 9128`, `id = "robotron-remix"`. `playing()` is `intro`, `play` or `clear`; `terminal()` is `over` (game.lua:1357-1363). `busy()` is always false (game.lua:1367-1369). `reset(seed)` seeds RNG, clears the hold, primes the raw-key sampler and starts a new game (game.lua:1384-1389).

### observe() fields (game.lua:1371-1381)

- `hero_x`, `hero_y`
- `nearest_x`, `nearest_y` — nearest non-human enemy; both `0` when none exists
- `lives`
- `score`

### action ids (game.lua:1321-1350)

Eight compass holds: `n`, `ne`, `e`, `se`, `s`, `sw`, `w`, `nw`. `best_dir` takes the vector to the nearest hostile, inverts it when that hostile is within 1.6, and picks the compass direction with the highest dot product; ties keep the order n, ne, e, se, s, sw, w, nw. One action is offered, score = dot + 1.

### apply(id) (game.lua:1262-1319)

- `"stop"` → `G.vkeys = {}`.
- `"fire_nearest"` → aims at the nearest hostile and sets `G.vkeys = { Space = true }`; clears the keys if no hostile or zero distance. It is legal but never offered.
- a compass id → replaces `G.vkeys` with that direction's movement keys plus `Space` (`n` = W, `ne` = W+D, `e` = D, `se` = S+D, `s` = S, `sw` = S+A, `w` = A, `nw` = W+A), and sets the aim vector at the nearest hostile, or at the compass vector when none exists; sets `G.aim_lock = true` (game.lua:1192-1201, 1290-1319).
- any other id → clears `G.vkeys`.

Every action replaces the previous hold, so movement persists until the next reply. Firing is automatic in every direction action.

## Jev cannot see

- The human family: positions, count, which is nearest, and the rescue score ladder; only the nearest hostile is exposed (game.lua:551-555, 1270-1281, 1371-1381).
- Enemy kinds and their state: a hulk (indestructible, only pushed) is indistinguishable from a grunt (game.lua:406-414, 705-708).
- Enemy projectiles and incoming orbs, the only ranged death source (game.lua:729-734).
- Every enemy except the single nearest; the rest of the swarm, including enemies flanking or behind, is invisible (game.lua:1246-1260, 1371-1381).
- Wave number, the remaining kill count, and whether a wave is about to clear (game.lua:848-852, 1098-1103).
- Invulnerability and death timers (game.lua:863, 880, 1095).
- Fire cooldown, the 14-bolt pool, and aim-lock state (game.lua:440, 826-828, 1285).
- `busy` is hard-coded false (game.lua:1367-1369).
