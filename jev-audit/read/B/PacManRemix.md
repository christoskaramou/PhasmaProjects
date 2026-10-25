# PacManRemix

Entry: `Arcade/PacManRemix/run.ps1` sets the project to `Assets` and starts `Scenes/main.pescene` (run.ps1:29-30); the scene's `scene_scripts.on_play` loads `Assets/Scripts/pacman.lua` (`Assets/Scenes/main.pescene:96-99`). `pacman.lua` loads `Scripts/jev_auto.lua` (pacman.lua:1004-1005) and registers `hooks{init,update}` (pacman.lua:1311). `Assets/Scripts/gamekit/driver.lua` is present and identical to the other Arcade games; `observe` is `pcall`-protected there (driver.lua:111-167).

## Maze and state

28 × 31 tile maze (pacman.lua:6-39), wrapped horizontally (pacman.lua:46-50). Characters: `#` wall, `-` ghost door (passable only by ghosts), `.` dot, `o` power pellet, space empty (pacman.lua:313-318, 217-226). Pac starts at tile (13.5, 23) heading left (pacman.lua:290). 3 lives (pacman.lua:670); an extra life at 10,000 points (pacman.lua:651).

## Stage flow

`title`/menu → `ready` (4.3 s on a fresh game, 2.0 s otherwise, pacman.lua:661-667) → `play` → `dying` (2.2 s, pacman.lua:1213-1219) or `levelclear` (2.6 s, pacman.lua:1220-1225) → `ready` again or the next level. Pellets are not reset on death, only on a new level or new game (pacman.lua:306-310, 1220-1225, 669-673).

## Player actions

- Arrows or WASD set a held direction; the newest held direction is the buffered `want`, and a tap before a junction still turns there (pacman.lua:1183-1197).
- `pacChooser` at each tile centre prefers the newest held open direction, then the buffered `want`, then straight if open, else stops (pacman.lua:346-358). Instant reversal is allowed (pacman.lua:742-744).
- P or Escape pauses during `play` or `ready` (pacman.lua:1180-1182).

## Pellets, fruit, score

- Dot: 10 points. Power pellet: 50 points (pacman.lua:686, 696).
- Power pellet starts frightened mode for `max(1.0, 7 - level)` seconds, resets the ghost combo, marks ghosts in `normal`/`house`/`leaving` frightened, and reverses normal ghosts (pacman.lua:287, 685-692).
- Eating a frightened ghost: `200 * 2^(combo-1)`, so 200, 400, 800, 1600 (pacman.lua:808-812), and a 0.5 s freeze of play (pacman.lua:816, 1210).
- Fruit appears at 70 and 170 eaten dots at tile (13.5, 17), lasts 9.5 s, and is eaten within 0.7 x and 0.6 y; its value by level is 100, 300, 500, 500, 700, 700, 1000, 1000, 2000, 2000, 3000, 3000, 5000 (pacman.lua:704-707, 761-772).
- Level completes when `S.dots >= S.totalDots` (pacman.lua:708-710).

## Ghosts

Four ghosts with scatter corners and house release dot counts (pacman.lua:242-247):

| Ghost | Scatter corner | Start | Release dots |
|---|---|---|---|
| blinky | (25, -3) | (13.5, 11) | 0 |
| pinky | (2, -3) | (13.5, 14) | 0 |
| inky | (27, 31) | (11.5, 14) | 30 |
| clyde | (0, 31) | (15.5, 14) | 60 |

- Release requires `S.dots >= max(0, dot - (level-1)*30)` or 4 s without eating a dot (pacman.lua:775-784). Blinky starts `normal`; pinky starts `leaving`; inky and clyde start in the house (pacman.lua:292-299).
- Mode cycle: scatter 7, chase 20, scatter 7, chase 20, scatter 5, chase 20, scatter 5, chase forever (pacman.lua:286). The mode timer pauses while frightened, and every mode change reverses normal ghosts (pacman.lua:723-736).
- Targets: blinky = Pac's tile; pinky = 4 tiles ahead of Pac's last direction; inky = the point twice as far from blinky as Pac's 2-tile-ahead point; clyde = Pac if squared distance > 64, else his scatter corner; eyes = (13, 11) (pacman.lua:360-377).
- Frightened ghosts pick a random legal direction that is not a reversal (pacman.lua:394-396, 386-392).
- Speeds: base 9.5; level 1 Pac 0.80 / frightened Pac 0.90 / ghost 0.75 / frightened ghost 0.50 / tunnel 0.40; levels 2-4 0.90 / 0.95 / 0.85 / 0.55 / 0.45; level 5+ 1.00 / 1.00 / 0.95 / 0.60 / 0.50 (pacman.lua:279-285).
- Eye state moves at 15 units/s (pacman.lua:792). Blinky gets 1.05× speed when fewer than 20 dots remain, unless frightened ("Cruise Elroy", pacman.lua:793).

## Death

- A collision with a non-frightened, normal ghost inside squared distance 0.5 kills Pac (pacman.lua:805-820).
- `killPac` starts `dying`; after 2.2 s a life is lost and the round restarts, or at 0 lives the state becomes `gameover` (pacman.lua:714-719, 1213-1219).
- No invulnerability window exists after respawn; the ghosts reset to their house positions (pacman.lua:289-304).

## Timers

| Timer | Value | Cite |
|---|---|---|
| Ready (fresh / respawn) | 4.3 / 2.0 s | pacman.lua:665 |
| Death animation | 2.2 s | pacman.lua:1215 |
| Level-clear hold | 2.6 s | pacman.lua:1222 |
| Frightened | max(1, 7 - level) s | pacman.lua:287 |
| Ghost-eaten freeze | 0.5 s | pacman.lua:816, 1210 |
| Fruit lifetime | 9.5 s | pacman.lua:705 |
| House idle release | 4 s without a dot | pacman.lua:780 |

## Jev attach (pacman.lua:1006-1103)

`port = 9101`, `id = "pacman"`. `playing()` is `ready`, `play`, `dying` or `levelclear`; `terminal()` is `gameover` (pacman.lua:921-926, 1010-1013). No `busy()` hook.

### observe() fields (pacman.lua:1018-1035)

- `tile` — `{c, r}` of Pac's current tile, column wrapped (pacman.lua:947-951, 1028).
- `direction` — `"up"`, `"down"`, `"left"`, `"right"` or `"stop"` from Pac's current velocity (pacman.lua:953-967, 1029).
- `ghosts` — array of 4 `{name, tile = {c, r}, mode}` in build order blinky, pinky, inky, clyde (pacman.lua:1019-1026). `mode` is `"eyes"`, `"frightened"`, `"house"`, `"leaving"`, or the current global mode name `"scatter"`/`"chase"` (pacman.lua:969-985).
- `lives`
- `score`
- `pellets_left` — `totalDots - dots`, clamped at 0 (pacman.lua:1033).

### action ids and apply(id) (pacman.lua:987-998, 1036-1093)

`"up"`, `"down"`, `"left"`, `"right"`, `"stop"`. Exactly one is offered.

`applyDir`:
- `"stop"` → `_G.PACMAN_VK = {}`; the update loop then clears `pac.held`, `pac.want` and sets velocity to zero (pacman.lua:988-991, 1200-1204).
- a direction → `_G.PACMAN_VK = { [Up|Down|Left|Right] = true }`, replacing the previous hold (pacman.lua:993-997).
- an unknown id → returns without changing the previous hold (pacman.lua:994-996).

### How the offered action is chosen (pacman.lua:1036-1093)

1. The nearest un-eaten pellet by wrapped Manhattan distance becomes the goal (pacman.lua:1041-1052).
2. If any ghost whose mode is neither `frightened` nor `eyes` is within Manhattan distance < 4, the goal is mirrored to the opposite side of Pac and the loop breaks at that ghost (pacman.lua:1054-1064).
3. Among the four directions that are not `#`/`-`, the highest dot product `step.c*dc + step.r*dr` wins; ties keep the earlier direction (up, down, left, right), and `"right"` is the default when no direction is open (pacman.lua:1066-1092). The action score is that dot product and may be negative.

## Jev cannot see

- The maze: walls, the ghost door, pellet positions, power pellets. It gets one derived direction plus `pellets_left`, never the layout (pacman.lua:1036-1093).
- The fruit: presence, tile, remaining 9.5 s and value (pacman.lua:704-707, 761-772).
- The remaining frightened time, the mode timer, and the next mode change — only the current mode word (pacman.lua:723-736, 969-985).
- Ghost release counters (`need` dots per ghost) and the 4 s idle release (pacman.lua:775-784).
- Level number, and the score thresholds that change speed, fright duration and fruit value (pacman.lua:279-287, 705).
- The 0.5 s freeze after eating a ghost, during which input still applies but play does not step (pacman.lua:816, 1210).
- That `playing()` includes `dying` and `levelclear`, when applying a direction has no gameplay effect (pacman.lua:921-926, 1213-1225).
- Ghost exact positions are tile-rounded, and ghost targeting intentions are not exposed (pacman.lua:360-377, 1023).
