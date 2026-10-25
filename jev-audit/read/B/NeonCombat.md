# NeonCombat

Entry: `Arcade/NeonCombat/run.ps1` starts `Scenes/main.pescene` (run.ps1:29); the scene loads `Assets/Scripts/game.lua`, which loads `Assets/Scripts/arenas.lua` (game.lua:8) and `Scripts/jev_auto.lua` (game.lua:904), and registers `hooks{init,update}` (game.lua:1259). `Scripts/gamekit/driver.lua` is present and byte-identical across the Arcade games; its `observe` wrapper is `pcall`-protected (driver.lua:111-167). Automation hook `_G.NC` (game.lua:1256-1257).

## Arena

Top-down tank duel on a 14-row × 24-column grid of 1.5-unit cells, world 18 wide × 10.5 deep (`arenas.lua:3, 156`), three layouts: `classic`, `maze`, `pillars` (`arenas.lua:5, 51, 105`). Walls are AABBs; a tank is pushed out of any wall inside radius 0.64 and clamped to the inner border (game.lua:460, 490-509). Shells reflect off walls (game.lua:728-744).

## Tanks

- Two tanks, each a single life-less vehicle: being hit spins it out, it never dies (game.lua:529-541).
- Movement: max forward 5.6, reverse 3.4, acceleration 16, max turn 160°/s, turn acceleration 900°/s² (game.lua:658, 671-677). Reversing is slower and turning is by angular velocity, not instant heading.
- Firing: cooldown 0.45 s, one shell per tank at a time, muzzle 1.12 × scale from centre, shell speed 17, shell life 2.6 s (game.lua:511-527). Firing is blocked unless `S.mode == "play"` (game.lua:512).
- Tank vs tank overlap pushes both apart at half the penetration (game.lua:1206-1214).

## Stage flow

Title → `countdown` 2.4 s (game.lua:893) → `play` at countdown ≤ 0 with a 0.6 s `FIGHT!` overlay (game.lua:1169-1178) → `win` when either score reaches the target (game.lua:538-540). `reset_round` respawns both tanks and clears shells (game.lua:881-884).

## Player actions

- Player 1: A/D turn, Space or W forward, S reverse, left click / F / Left Shift fire; in 1-player mode Up/Down also drive and Left/Right also turn, Return/Right Ctrl also fire (game.lua:1186-1197).
- Player 2: arrows drive/turn, Return / Right Ctrl / Keypad 0 / Right Shift / Keypad Enter fire (game.lua:1198-1201).
- P or Escape pauses (game.lua:1155). M mutes (game.lua:1156).

## Scoring, win and lose

- A shell hit gives the shooter one point; a tank can hit itself with its own bounced shell and then scores for itself with banner `SELF HIT!` (game.lua:750, 534-536).
- First score to reach `S.target` sets `mode = "win"` and records the winner (game.lua:538-540). Target defaults to 10 and is selectable as 3, 5, 10 or 15 (game.lua:88, 1042).
- There is no lose state other than the opponent reaching the target first. In 1-player mode player 2 is the AI (game.lua:885-888).
- After the win screen, Return/Space starts a rematch, Escape goes to title (game.lua:1234-1239).

## Shells and hazards

- A shell travels in 4 substeps per frame (game.lua:725) and behaves according to the menu setting `S.bounce` (default true, game.lua:88, 821): with bounce on, up to 4 wall reflections, then detonation; with bounce off, detonation on the first wall (game.lua:730-744).
- A shell hits a tank inside `TANK_R + 0.06` unless it is the shooter's own shell on its first flight segment, or the target is spinning or invulnerable (game.lua:748-754).
- On hit: spin 1.4 s (during which the tank spins at up to 720°/s and slides with knockback 7), invulnerability 2.0 s, hit flash (game.lua:529-534, 660-669). A spinning tank cannot fire (game.lua:512).
- A shell that spawns inside a wall is moved back toward the muzzle by 0.6 (game.lua:520-521).
- No pickups, no freeze/slow fields.

## Timers

| Timer | Value | Cite |
|---|---|---|
| Fire cooldown | 0.45 s | game.lua:522 |
| Shell life | 2.6 s | game.lua:517 |
| Hit spin-out | 1.4 s | game.lua:531 |
| Post-hit invulnerability | 2.0 s | game.lua:531 |
| Match countdown | 2.4 s | game.lua:893 |
| FIGHT! overlay | 0.6 s | game.lua:1171 |
| Win-screen input lock | 1.5 s | game.lua:1234 |
| AI think interval | 0.55 / 0.3 / 0.12 s by skill | game.lua:589 |

AI skill `AI_LV` rows are aim error, reaction and turn rate: Rookie {9°, 0.55 s, 0.65}, Veteran {4°, 0.3 s, 0.85}, Ace {1.5°, 0.12 s, 1.0} (game.lua:589). The AI uses line-of-sight, a BFS distance field for pathing, and bank-shot prediction when ricochet is on (game.lua:590-655).

## Jev attach (game.lua:978-1028)

`port = 9106`, `id = "neon_combat"`. `playing()` is `mode == "play"` or `"countdown"`; `terminal()` is `mode == "win"` (game.lua:982-987). `busy()` is always false (game.lua:995-997). `reset(seed)` seeds RNG, clears holds and starts a 1-player match (game.lua:1019-1026).

### observe() fields (game.lua:956-977, view built at 950-955)

- `p1` — table `{x, z, yaw}` for player 1, yaw normalised to (-180, 180].
- `p2` — same for player 2 (the AI in a 1-player match).
- `los` — boolean, whether a sampled line from p1 to p2 is clear of walls (game.lua:544-553, 959-962).
- `score` — table `{p1, p2}` (game.lua:963-975).

### action ids and apply(id) (game.lua:930-1017)

`apply` first clears every player-1 hold (game.lua:24-35, 931), then holds:

| id | Keys held | Cite |
|---|---|---|
| `left` | A | game.lua:932-933 |
| `right` | D | game.lua:934-935 |
| `thrust` | Space + W | game.lua:936-938 |
| `reverse` | S | game.lua:939-940 |
| `fire` | F | game.lua:941-943 |
| `thrust_fire` | Space + W + F | game.lua:944-948 |

Any other id clears the holds and holds nothing. Holds are virtual keys read by the normal input path, so they persist until replaced; `fire` repeats every frame and therefore every 0.45 s cooldown (game.lua:942, 1191, 511-512).

`actions()` (game.lua:1000-1017) is written to offer `left` / `right` when the heading error to p2 exceeds ±8°, else `thrust_fire`. **As written it never reaches that logic:** the guard at game.lua:1003 tests `a.alive` and `b.alive`, but tanks have no `alive` field — `new_tank` (game.lua:462-465) never sets one, and the only `alive` assignments in the scripts are on shells (game.lua:514, 883, 901). The guard therefore always returns `{id = "thrust_fire"}` (game.lua:1004), so Jev is only ever offered drive-and-fire, never a turn.

## Jev cannot see

- Both shells: position, velocity, bounce count, remaining life, and whether its own gun is reloading (game.lua:511-527, 715-786).
- Its own spin-out and invulnerability, i.e. whether it can currently move or fire (game.lua:529-532, 660-669).
- The arena layout and wall AABBs; only a single instantaneous `los` boolean is exposed, with no geometry, no distance and no useful shot prediction (game.lua:956-962).
- Both scores' target (`S.target`), the arena name and the bounce/ricochet setting (game.lua:88, 820-822).
- The AI's level and internal state (game.lua:589-655).
- Its own heading relative to the other tank in a usable form: `yaw` and positions are present, so the error is computable, but `actions()` offers no turn because of the dead guard at game.lua:1003.
- Reload state: `busy` is hard-coded false, so a reply arriving during the 0.45 s cooldown looks actionable (game.lua:995-997).
