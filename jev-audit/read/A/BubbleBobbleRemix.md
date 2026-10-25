# BubbleBobbleRemix — how the game works (read from current source)

Source of truth: `Arcade/BubbleBobbleRemix/Assets/Scripts/game.lua` (1251 lines, hand-written; no `tools/src`)
plus its level data `Arcade/BubbleBobbleRemix/Assets/Scripts/levels.lua` (loaded at `game.lua:61`). Cites are
`Assets/Scripts/game.lua` lines unless prefixed `levels.lua`. Jev wrapper `Assets/Scripts/jev_auto.lua`;
driver `Assets/Scripts/gamekit/driver.lua`. `run.ps1` launches `Scenes/main.pescene`
(`run.ps1:29-30`), which loads `Scripts/game.lua`.

## Shape of a run

- Fixed frame update capped at 0.05 s; the whole sim runs on the rendered `dt` (`game.lua:1039-1042`).
- Single arena: inner walls at x = −14 and 14, ceiling row bottom at y = 25, floor platforms at y = 0/1
  with a wrap hole between x = −3 and 3 (`game.lua:62-63`, `334`, `365-368`).
- There are 6 level layouts; level `n` uses `LEVELS[(n-1) % 6 + 1]`, so the game loops layouts forever
  (`game.lua:61`, `830`, `846`). Each later loop adds `min(3, floor((n-1)/6))` extra Zen enemies
  (`game.lua:851`).
- Level data supplies the solid platforms (x0, z0, x1, y), spawn points and enemy list
  (`levels.lua:2-6`). Enemy counts: L1 3 Zen; L2 4 Zen; L3 3 Zen + 2 Monsta; L4 3 Zen + 2 Monsta;
  L5 5 Zen + 3 Monsta; L6 3 Zen + 3 Monsta (`levels.lua:2-6`).
- New game: score 0, 3 lives, letters cleared, 2.0 s invulnerability, level 1 (`game.lua:1017-1024`).
- Round flow: `play` → when all enemies are gone → 4.5 s delay → 2.4 s bubble transition → next level
  (`game.lua:900-904`, `860-887`).

## Player actions

- Move: A/D or arrows, target speed ±7.2; easing 18/s on the ground, 9/s in the air
  (`game.lua:805-807`).
- Jump: W/Up/Space/K (`game.lua:1095-1096`). Jump impulse `JUMP_V = 19.5`; gravity 44; falling speed
  capped at −15 (`game.lua:349`, `809`, `358`). Releasing jump while rising faster than 6 adds extra
  gravity, giving a short hop (`game.lua:810`).
- Jump buffer: a jump press stays valid for 0.12 s before landing (`game.lua:1099-1100`).
- Blow bubble: J/X/Ctrl/F or click; cooldown 0.24 s (`game.lua:811`, `1097-1098`).
- One-way platforms: the body lands only when moving down across a platform top; side walls are solid
  (`game.lua:339-343`, `351-371`).
- Wrap hole: falling below y = −1.8 teleports the player to y = 26.3 (drop in from the top); going above
  26.6 teleports to −1.6 (`game.lua:365-368`).
- Player body: half-width 0.42, height 1.6, speed 7.2 (`game.lua:419`, `805`).
- Bubbles can be bounced on: while falling, above a bubble, and holding jump, the player gets
  `vy = JUMP_V*0.92` instead of popping it (`game.lua:689-690`).

## Bubbles

- Blown bubble: 0.35 radius, shot at 17 units/s in the facing direction, grows to 0.95, life 11 s
  (`game.lua:533-543`). A shot bubble stops being a projectile when |vx| < 2.5 and then floats upward
  toward y 22.4 (`game.lua:658-676`).
- A shot bubble traps a walking enemy on contact (|dx| < 0.95, |dy| < 1.0); the enemy state becomes
  `trapped`, the bubble's life becomes 8.5 s (`game.lua:663-670`).
- If a trapping bubble expires, the enemy is released angry (`game.lua:696-698`).
- Touching a floating bubble pops it (unless bounced on) (`game.lua:686-695`).
- Pop chain: popping one bubble also pops every non-shot bubble within 2.3 units, in BFS order, each
  with a 0.06 s delay (`game.lua:618-632`).
- Letter bubbles are a separate pool of 6 and never chain (`game.lua:692`).

## Hazards and what kills the player

- Contact with a walking enemy: |dx| < 0.8 and vertical centres within 1.1 → `player_die`
  (`game.lua:765`).
- Baron von Blubba: contact within 1.6 while not invulnerable → `player_die` (`game.lua:739`).
- Nothing else kills: bubbles, fruit, platforms, the wrap hole and the floor do not damage.
- Death: player is dead for 1.8 s, then one life is lost; at 0 lives the run ends, otherwise respawn at
  the start point with 2.5 s invulnerability, the Baron removed, and the hurry timer rolled back to at
  most 18 s (`game.lua:1108-1116`, `1033-1038`).
- Death is ignored outside state `play` (`game.lua:1031-1032`).

## What the player can kill

- Any trapped enemy, by popping its bubble (`game.lua:646-651`, `633-654`).
- Kill score: `1000 * 2^min(chain-1, 5)` — 1000, 2000, 4000, 8000, 16000, 32000 within one pop chain
  (`game.lua:601-608`). `chain` counts trapped enemies popped in the same chain.
- A killed enemy tumbles, then spawns one fruit where it lands on a platform, with fruit tier
  `min(3, chain-1)` (`game.lua:766-779`, `569-570`).
- Enemies not killable by contact: touching a walking enemy kills the player instead
  (`game.lua:765`).

Enemy movement (`game.lua:459-516`):
- Zen: ground walker at 3.3 units/s; reverses at walls and sometimes at ledges; jumps every 1.2–3.0 s
  (more often when angry), and jumps when the player is above within 7 units
  (`game.lua:491-516`).
- Monsta: flies at 3.0 units/s at 45°, bouncing off x walls and the y 1.0/23.6 bounds; it ignores
  platforms (`game.lua:492-498`).
- Angry enemies move at 1.7× speed (`game.lua:491`, `894`).
- Level speed scale is `1 + 0.05*min(level, 10)` (`game.lua:491`).

## Timers and durations

| Timer | Value | Cite |
|---|---|---|
| Blown bubble life | 11 s | `game.lua:537` |
| Trapping bubble life | 8.5 s | `game.lua:665` |
| Bubble blow cooldown | 0.24 s | `game.lua:811` |
| Bubble pop chain delay | 0.06 s per queued bubble | `game.lua:627` |
| Player death to life loss | 1.8 s | `game.lua:1108` |
| Respawn invulnerability | 2.5 s | `game.lua:1034` |
| New-game invulnerability | 2.0 s | `game.lua:1021` |
| Jump buffer | 0.12 s | `game.lua:1100` |
| Fruit lifetime | 11 s | `game.lua:573` |
| Letter bubble lifetime | 15 s | `game.lua:551` |
| Letter spawn interval | 8–12 s initially, then 11–16 s | `game.lua:857`, `898` |
| Hurry-up | at 32 s into a level, all enemies angry | `game.lua:892-895` |
| Baron spawn | at 42 s into a level, if enemies remain | `game.lua:896` |
| Level-clear delay | 4.5 s in play (2.5 s otherwise) | `game.lua:903` |
| Level transition | 2.4 s | `game.lua:880` |

## Baron von Blubba

- Spawns at (0, 28) when a level passes 42 s with enemies left; speed 2.6, accelerating 0.12/s up to 7.5
  (`game.lua:720`, `725-728`, `735`).
- Homes directly at the player each frame and kills on contact within 1.6 (`game.lua:736-739`).
- Leaves upward when the level is cleared (`game.lua:900-901`, `733`).

## Fruit, letters and extra lives

- Fruit tiers and points: cherry 500, banana 700, peach 1000, gem 2000 (`game.lua:555-558`).
- Fruit tier for a kill is `clamp(1 + floor(level/2)%2 + min(3, chain-1), 1, 4)` (`game.lua:570`).
- Fruit is collected by overlap: |dx| < 0.9 and y within −0.8..+1.6 of the player (`game.lua:589-595`).
- Letter bubbles: the six letters E, X, T, E, N, D; one missing letter spawns at a random spot in the
  floor gap every 8–12 s (then 11–16 s), drifting up at 2.2 (`game.lua:392`, `546-552`, `857`, `897-898`).
- Popping a letter bubble marks that letter collected; collecting all six grants +1 life, clears the
  letters, and shows "EXTEND" (`game.lua:635-645`).
- Letters persist across levels until the set completes or a new game starts (`game.lua:1017-1020`).
- Score extra life: at 30000, then every 50000 more (`game.lua:314`, `329`).

## Score, win, lose

- Score: enemy pops (doubling chain) and fruit (500–2000) (`game.lua:601-604`, `591`).
- Lives: 3; EXTEND set and score thresholds add lives (`game.lua:313`, `329`, `642`).
- High score loaded from `Save/bb_hiscore.txt`, saved on game over only when Jev was not assisted
  (`game.lua:315-316`, `1112-1115`).
- Win: **none**. Levels loop forever through the six layouts with extra enemies; there is no `G.won`
  and no final state.
- Lose: lives reach 0 after a death → state `over` (`game.lua:1109-1116`).

## JevAuto.attach for this game

Attach block `game.lua:1193-1248`, port 9142, id `bubble-bobble-remix`.

`observe()` returns exactly `player_x`, `player_y`, `enemy_x`, `enemy_y`, `lives`, `score`
(`game.lua:1213-1223`). The wrapper adds `mode`, `terminal`, `score`, `busy`, `actions`
(`jev_auto.lua:54-61`). `enemy_*` is the nearest non-dead enemy, or the Baron if he is active and closer
(`game.lua:1142-1171`). When there is no enemy the coordinates are (0, 0). `busy` is always false
(`game.lua:1207-1209`). `playing()` is true in state `play` **or** `next` (the level transition)
(`game.lua:1198-1200`).

Action ids produced by `actions()` (`game.lua:1224-1240`): `right`, `left`, `jump`, `bubble`.
- No enemy → `right`.
- Enemy above (`enemy_y > player_y + 0.8`) and |dx| < 0.9 → `jump`.
- dx > 0.3 → `right`; dx < −0.3 → `left`; otherwise → `bubble`.

`apply(id)` (`game.lua:1173-1191`):
- Clears all virtual keys first, so every action replaces the previous hold.
- `left` / `left_jump` hold Left; `right` / `right_jump` hold Right (`game.lua:1175-1184`).
- `jump`, `left_jump`, `right_jump` hold Space (`game.lua:1185-1187`).
- Any direction or `bubble` also holds J (blow bubble) (`game.lua:1188-1190`).
- Unknown ids only clear the keys.
- `reset(seed)` clears keys, seeds random and starts a new game (`game.lua:1242-1246`); `on_human` clears
  the virtual keys (`game.lua:1247`).

## Jev cannot see

- Level number, level name/layout, remaining enemies count, and each enemy's type and state
  (entering/walking/trapped/dead).
- Every enemy except the nearest one, and whether the nearest is the Baron (no type flag).
- Bubbles: positions, age, whether one is trapping an enemy, and the pop chain.
- Fruit on the field and its tier/points.
- Which EXTEND letters are already collected, and the next letter spawn timer.
- Hurry/Baron timers; the fact that enemies are angry.
- Own invulnerability timer, jump/fall state, ground state, and the short-hop input state.
- That the game has no win condition; scoring and lives only.
