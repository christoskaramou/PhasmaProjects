# MissileCommand

Entry: `Arcade/MissileCommand/run.ps1` starts `Scenes/main.pescene` (run.ps1:29); the scene loads `Assets/Scripts/game.lua`, which loads `Scripts/jev_auto.lua` itself (game.lua:1461-1465) and ends with `hooks{init,update}` (game.lua:1492). `Scripts/gamekit/driver.lua` is present and byte-identical across the Arcade games (hash 16CE0804…); `jev_auto.lua` loads it from `Scripts/gamekit/driver.lua` (jev_auto.lua:9). Its `observe` wrapper is `pcall`-protected and rejects malformed actions (driver.lua:111-167). Sim is 2D in a fixed camera plane: x in ±HW, y 2.6..21 for aiming (game.lua:478, 1330-1331).

## World and actors

- 3 batteries at x = -18.6, 0, 18.6, each `ammo = 10` (game.lua:80, 145). Fire from battery 2 travels at 34 units/s, batteries 1/3 at 24 (game.lua:506).
- 6 cities at x = -13.6, -9.4, -5.0, 5.0, 9.4, 13.6, all alive at start (game.lua:79, 119).
- Enemy warheads spawn at y = 22.5 across the width and fly at a target city/base x with jitter ±0.4 (game.lua:551, 1177). Target y is 1.4 for a base, 0.6 for a city (game.lua:552).
- A bomber/satellite "flyer" crosses the sky and drops warheads while `wave_plan.spawned < total` (game.lua:637-668).

## Stage flow

`boot` → `title` (init ends in title_screen, game.lua:1061) → `wavestart` (2.6 s banner, game.lua:1201-1211) → `play` → `tally` → next `wavestart` or `gameover`.

Wave N plan (game.lua:614-635):
- `total = min(10 + 2N, 34)`
- `speed = 1.5 + 0.32N`
- `salvo = min(2 + floor(N/2), 6)`
- `gap = max(1.4, 4.2 - 0.25N)`; actual timer is `gap * (0.7..1.3)` (game.lua:1174)
- first spawn timer 1.5 s
- `flyers = 0` for wave 1, else `min(1 + floor(N/3), 4)`, first at 6-10 s (game.lua:631)
- score multiplier `mult = min(6, floor((N+1)/2))` (game.lua:76, 616), applied to every point award (game.lua:672).

Wave start refills all 3 batteries to 10 and revives destroyed ones (game.lua:617-619), then converts each stored bonus city into one revived city (game.lua:621-626).

## Player actions

- Aim: mouse position mapped into world x/y, clamped (game.lua:467-478).
- Fire nearest ready battery: left click (ignored when a UI button is hovered) or Space (game.lua:1193).
- Fire battery 1: A, 1 or Q. Battery 2: S, 2, W, or right click. Battery 3: D, 3 or E (game.lua:1194-1196).
- Firing is allowed during the wave banner too (game.lua:1209).
- Pause: P during play/wavestart (game.lua:1264). ESC quits to title (game.lua:1269-1276).

## Firing and reload

- `fire(bi)` fails with `"empty"` if the battery is dead or `ammo <= 0` (game.lua:497); otherwise spends 1 ammo (game.lua:500) and creates a shot travelling to the aim point, detonating when accumulated travel reaches the distance (game.lua:507, 686-692).
- A battery counts as reloading while any of its own shots is still in flight; `battery_reloading` matches a shot by equal `sx/sy` to the battery x/y (game.lua:1360-1373). So the reload is the interceptor's flight time, not a fixed timer: 34 u/s for the centre battery, 24 u/s for the side ones (game.lua:506).
- `battery_ready = alive and ammo > 0 and not reloading` (game.lua:1375-1381).

## Explosions

Each interceptor makes a boom at its target: grow 0.55 s, hold 0.35 s, shrink 0.75 s, total 1.65 s (game.lua:772-777). Radius max 2.6 for a player shot (game.lua:691), 2.2 for a chain kill (game.lua:725), 2.0 for a ground impact (game.lua:729). Any boom with `r > 0.1` kills a warhead inside its radius (game.lua:717-726).

## Kills and score

- Warhead destroyed by an explosion: 25 points × mult (game.lua:724).
- Flyer destroyed by an explosion within `r + 0.6`: 100 points × mult (game.lua:758-759).
- Bonus city at each 10,000-point threshold; threshold then rises by 10,000 and one bonus city is stored for the next wave (game.lua:673-676).
- End-of-wave tally: each unused missile is 5 × mult (game.lua:1140) and each surviving city is 100 × mult (game.lua:1150).

## Hazards, what kills the player, what the player can kill

- Warheads kill by reaching their target y: city → `destroy_city`, base → `destroy_base` (game.lua:727-730). `destroy_base` sets `ammo = 0`, `alive = false` (game.lua:604-611). No splash damage exists despite the comment at game.lua:731 — only the assigned target dies.
- Split warheads: spawning with `can_split` is allowed from wave 2, 35% chance, with a split distance of 6-13 units below the spawn y (game.lua:557, 1177). While `y < sy - split` and `y > 7`, a warhead emits 1-3 extra warheads, capped while `spawned < total + 6` (game.lua:734-739). Children do not split.
- The player can kill warheads and the flyer. Cities and bases cannot be shot by the player.
- A warhead can be intercepted by any live boom, including a chain boom from another kill (game.lua:717-726).

## Pickups and timers

- No pickups; the only reward is the automatic bonus city every 10,000 points (game.lua:673-676).
- Wave banner 2.6 s, during which firing is live (game.lua:1201-1211).
- Tally: 0.8 s initial pause, 0.07 s per counted missile, 0.5 s before the city phase, 0.28 s per counted live city, 1.6 s before advancing (game.lua:1122, 1141-1156).
- Game over screen: 2.5 s before the restart buttons appear (game.lua:1221).

## Win and lose

- Wave ends (tally starts) when no warheads, no active flyer, no unspawned warheads remain, and no shots or booms are on screen (game.lua:1117-1119, 1198).
- Lose at the end of the tally when no city is alive and no bonus city is stored: mode becomes `gameover` (game.lua:1157-1163). There is no win; waves continue with the multiplier capped at 6 (game.lua:76).
- High score is only committed when Jev is not the assisted player (game.lua:965-974).

## Jev attach (game.lua:1466-1490)

`port = 9104`, `id = "missile_command"`. `playing()` is `mode == "play" or "wavestart"`, and not paused; `terminal()` is `mode == "gameover"` (game.lua:1470-1475). `busy()` is always false (game.lua:1479-1481). The shared wrapper (`Assets/Scripts/jev_auto.lua`, identical in all 8 games) sends `mode`, `terminal`, `score`, `busy`, `observation`, `actions`, and only fills `actions` while Jev owns a live, non-terminal match (jev_auto.lua:43-61, 36-38).

### observe() fields (game.lua:1383-1407)

- `warheads` — array of strings `"c<1-4>_r<1-3>"`, one per live warhead, from its current position mapped onto a 4-column × 3-row sky grid (game.lua:1328-1349, 1384-1389). Duplicates are kept; dead cells are absent.
- `batteries` — array of 3 booleans, `true` only when that battery is alive, has ammo, and has no interceptor still in flight (game.lua:1391-1394, 1375-1381).
- `cities` — array of 6 booleans, alive state per city (game.lua:1396-1399).
- `score` — current score (game.lua:1405).

### action ids (game.lua:1409-1429)

`"b<1-3>_c<1-4>_r<1-3>"`, only emitted for batteries where `battery_ready` is true, so 12 ids per ready battery and at most 36 in `play`.

### apply(id) (game.lua:1431-1453)

Parses `b/c/r`; returns on a malformed id, an out-of-range battery/column/row, or a battery that is not ready. Otherwise it computes the cell centre (game.lua:1351-1357), temporarily sets `aimx/aimy` to it, calls `fire(bi)` (spending 1 ammo and committing the interceptor), then restores the previous aim.

## Jev cannot see

- The flyer/bomber: position, presence, its 100-point value and its warhead drops (game.lua:637-668, 755-763). `warheads` only iterates `enemies`.
- Its own explosions: cell and radius of every live boom, including interceptors still growing (game.lua:767-825). A shot fired this action is invisible until a warhead dies.
- Ammo remaining per battery: `batteries` collapses "dead", "empty" and "reloading" into `false` (game.lua:1375-1381).
- Wave number, multiplier, bonus-city count, next bonus threshold (game.lua:614-635, 673-676). Score is visible but not its multiplier.
- Exact warhead position inside a cell, velocity, target city/base, and the split flag/pending child count (game.lua:555-558).
- Which boom will still be alive when a warhead arrives; boom timers are not exposed.
- Tally progress and the automatic per-wave base refill (game.lua:617-619, 1121-1167) except through the mode transition.
