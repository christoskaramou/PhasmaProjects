# DigDugRemix — how the game works (read from current source)

Source of truth: `Arcade/DigDugRemix/Assets/Scripts/game.lua` (1585 lines, hand-written; no `tools/src`).
Cites are `Assets/Scripts/game.lua`. Jev wrapper `Assets/Scripts/jev_auto.lua`; driver
`Assets/Scripts/gamekit/driver.lua`. `run.ps1` launches `Scenes/main.pescene` (`run.ps1:29-30`), which loads
`Scripts/game.lua`.

## Shape of a run

- Playfield: 13 columns × 13 rows of 2-unit tiles; row 0 is the surface lane, rows 1–12 are earth split
  into 26 × 26 sub-cells so digging is per half-tile (`game.lua:54-65`).
- Update is capped at 0.05 s per frame and the sim runs on that `dt` (`game.lua:1369`).
- Rounds are endless; there is no win state. New game: score 0, `G.lives = 2`, round 1 (`game.lua:1227-1231`).
- Round flow: round start places the digger on the surface at column 6 and auto-descends to row 6 during
  a 2.6 s `intro` (`game.lua:1213-1226`, `1396-1402`), then `play`; when no enemies remain, `clear` for
  2.6 s and the next round starts (`game.lua:1320-1322`, `1411-1414`).
- `G.state` values: `boot`, `title`, `intro`, `play`, `paused`, `clear`, `over`.

## Player actions

- Move/dig with WASD/arrows. When both axes are held the most recently pressed axis wins
  (`game.lua:668-677`).
- Move speed 6.2 units/s, or 4.6 while digging; movement snaps to tile lanes and is blocked by idle rocks
  and inflated enemies (`game.lua:679-710`, `652-660`).
- Digging: every 2×2 sub-cell the body overlaps is removed; `P.digging` stays true for 0.15 s after the
  last dug cell (`game.lua:417-423`, `705-707`).
- Pump/harpoon: Space or left click fires the harpoon in the facing direction; it extends at 26 units/s
  up to 5.0 units, retracts at 30/s when it hits solid earth or reaches max, and has a 0.12 s cooldown
  after retracting (`game.lua:711-747`).
- Once the harpoon hits an enemy the hose locks on: pressing/holding pump inflates it. Each pump adds 1
  inflation; 4 pops it (`game.lua:729-735`, `768-776`).
- If a locked enemy is not pumped for 0.85 s it loses one inflation, and at 0 it returns to walking
  (`game.lua:843-851`).
- Changing direction while locked releases the harpoon (`game.lua:681-683`).

## Hazards and what kills the player

- Touching a walking, charging or firing enemy: |dx| < 1.3, |dy| < 1.3, unless invulnerable
  (`game.lua:854-856`).
- Fygar flame: while firing, |dy| < 0.9 and the player is in front within the flame length
  (`min(1, fire_t*4)*5.0`, plus 0.4) (`game.lua:857-861`).
- A falling rock: |dx| < 1.5, player below it and within 1.8, sets `crushed_fall`; at rock landing the
  player dies (`game.lua:902-905`, `916`).
- Death: `P.state = dying` for 1.9 s, then if lives > 0 one life is lost and the player respawns at
  (col 6, row 6) with 2.0 s invulnerability and **all enemies reset to their spawn cells**
  (`game.lua:1291-1296`, `1272-1277`); otherwise the run ends (`game.lua:1242-1248`).
- Dirt, tunnels, rocks (until falling), gems and the vegetable are not lethal.

## What the player can kill and what it scores

- Enemies are Pookas and Fygars; 6 Pooka and 4 Fygar models exist, so at most 10 at once
  (`game.lua:496-500`).
- Pop by pumping 4 times. Pop score depends on the stratum of the enemy's row: 200 / 300 / 400 / 500
  top-to-bottom; a Fygar popped by a horizontal harpoon scores double (400–1000)
  (`game.lua:604`, `759-763`).
- Rock crush score by number of enemies crushed: 1000, 2500, 4000, 6000, 8000, 10000, 12000, 15000
  (`game.lua:605`, `913-915`).
- A popped enemy emits no fruit; the only bonus item is the vegetable (below).
- Ghosts cannot be hit by the harpoon (`game.lua:717-721`).
- The last surviving enemy flees: it runs at 1.35× speed toward the surface tile (0,0) and then exits
  left; if it escapes it is simply removed with an "ESCAPED" popup (`game.lua:782`, `791`, `812-813`,
  `1307-1309`).

## Earth, rocks, gems

- Earth starts solid for rows 1–12; digging a sub-cell hides it and may award a gem (`game.lua:342-423`).
- 14 gems are hidden in random sub-cells below row 8; each gem dug gives 250 points and the total for a
  single dig is applied at once (`game.lua:359-370`, `393-402`, `708`).
- 3–5 rocks per round (3 + min(round/3, 2)) are placed on unopened tiles (`game.lua:1036-1045`).
- A rock becomes unstable when both sub-cells directly below it are dug and the player is not underneath;
  it wobbles 0.6 s, then falls, accelerating 40/s up to 16/s (`game.lua:869-893`).
- Falling rocks crush any non-ghost enemy within |dx| < 1.6 and up to 1.9 below, then land after 0.55 s,
  score the crush, and break (`game.lua:895-921`).
- Dropping the second rock of a round spawns the bonus vegetable once (`game.lua:919`).

## Bonus vegetable

- Appears at tile (6,6) after the second rock of the round lands; lasts 10 s (`game.lua:616-620`,
  `1311-1319`).
- Values by round, capped at the sixth entry: carrot 400, mushroom 600, carrot 800, mushroom 1000,
  carrot 2000, mushroom 3000 (`game.lua:606`, `616-618`).
- Collected by overlap within 1.4 units (`game.lua:1313`).

## Enemies

- Per round: `ne = min(4 + floor((round-1)/2), 8)` enemies, of which
  `nf = min(1 + floor(round/2), 3, ne-2)` are Fygars; the rest are Pookas (`game.lua:1014-1033`).
- Each enemy starts on a dug 3-tile corridor, at speed `3.6 + min(round,10)*0.18`
  (`game.lua:522-524`, `1018-1033`).
- Movement uses BFS distance fields over open tiles, recomputed every 0.2 s: enemies chase the player, and
  the last enemy follows a flee field toward the surface (`game.lua:533-568`, `1297-1302`).
- Enemies avoid the surface row unless fleeing (`game.lua:555`).
- Ghosting: after a 7–13 s timer (which runs 3× faster while stuck), an enemy becomes a ghost at a
  junction and moves straight through dirt toward the player at `2.6 + min(round,10)*0.1`; after 1.6 s
  it re-enters the tunnels at an open tile near it (`game.lua:804-842`).
- Fygar fire: when on the player's row, facing them, and within 9 units, after a 0.75 s charge it fires
  for 1.0 s; cooldown 3–6 s minus 0.2/round (min 8) (`game.lua:818-829`). The flame goes through dirt.
- Enemies reset to spawn positions after a player death (`game.lua:1273`).

## Timers and durations

| Timer | Value | Cite |
|---|---|---|
| Round intro descent | 2.6 s (or until reaching row 6) | `game.lua:1402` |
| Digging state after last dug cell | 0.15 s | `game.lua:707` |
| Harpoon extension speed / max length | 26/s, 5.0 units | `game.lua:742-746` |
| Harpoon cooldown after retract | 0.12 s | `game.lua:739` |
| Pump interval while held | 0.32 s | `game.lua:734` |
| Pumps to pop | 4 | `game.lua:775` |
| Inflation decay | one level per 0.85 s unpumped | `game.lua:845-847` |
| Player death to respawn | 1.9 s | `game.lua:1293` |
| Respawn invulnerability | 2.0 s | `game.lua:1275` |
| Rock wobble before falling | 0.6 s | `game.lua:878` |
| Rock landing to break | 0.55 s | `game.lua:911` |
| Ghost form delay | 7–13 s at a junction | `game.lua:523` |
| Ghost re-entry | after 1.6 s | `game.lua:840` |
| Fygar charge / fire | 0.75 s / 1.0 s | `game.lua:826-829` |
| Vegetable lifetime | 10 s | `game.lua:1318` |
| Round-clear pause | 2.6 s | `game.lua:1414` |

## Score, extra lives, win/lose

- Score sources: enemy pops, rock crushes, gems (250 each), vegetable (400–3000), and the 1UP thresholds
  (`game.lua:594-606`, `759-763`, `913-915`, `708`).
- Extra life at 10000, 40000, 80000 and 120000 points, once each (`game.lua:598-600`).
- Lives start at 2 reserves (`game.lua:1228`), so a run has three diggers total; the HUD draws one icon
  per reserve (`draw_icons(G.lives)`, `game.lua:990-1000`, `1349`).
- Hi-score starts at 10000, loaded from `Save/hiscore.txt`; saved on game over/quit only when Jev was not
  assisted (`game.lua:590-592`, `1242-1248`, `1267-1268`).
- Win: **none**; rounds continue indefinitely.
- Lose: a death with no lives left → state `over` (`game.lua:1291-1296`).

## JevAuto.attach for this game

Attach block `game.lua:1424-1549`, port 9144, id `digdug`.

`observe()` returns exactly `cell` (`{c, r}`), `lives`, `score`, and `nearest_enemy_cell` (`{c, r}`,
omitted when no enemy exists) (`game.lua:1448-1477`). The wrapper adds `mode`, `terminal`, `score`,
`busy`, `actions` (`jev_auto.lua:54-61`). `nearest_enemy_cell` uses Manhattan distance in tiles over any
live enemy, including ghosts and the fleeing last enemy (`game.lua:1455-1467`). `busy` is always false
(`game.lua:1442-1444`). `playing()` is true in `play`, `intro` and `clear` (`game.lua:1433-1435`).

Action ids produced by `actions()` (`game.lua:1478-1508`): `right`, `left`, `up`, `down`, `pump`.
- No enemy → `right`.
- Enemy within 0.9 units on both axes → `pump`.
- Otherwise move along the larger absolute axis toward the nearest enemy (`right`/`left`/`up`/`down`).

`apply(id)` (`game.lua:1509-1538`):
- Looks the id up in a hold table: `left`, `right`, `up`, `down`, `stop`, `pump`
  (`game.lua:1510-1517`).
- Replaces `G.vkeys` with the matching held keys, so the direction persists until the next act
  (`game.lua:1523-1527`).
- `pump` holds Space and, on the first pump press only, sets a one-shot pump flag and clears the Space
  edge so the pump registers (`game.lua:1529-1537`, `1284-1287`).
- Any non-pump id clears the pump flag (`game.lua:1529-1531`); `stop` clears all keys.
- Unknown ids do nothing.
- `reset(seed)` seeds random, clears keys and pump, and starts a new game (`game.lua:1539-1544`);
  `on_human` clears keys and pump (`game.lua:1545-1548`).

## Jev cannot see

- Round number, the dug-tunnel map, solid/dug state, and the rock layout and states.
- Every enemy except the nearest one, and that enemy's kind, state, inflation count, ghost/flee status,
  and whether it is currently hittable.
- Gems, the vegetable and its value, and the 1UP thresholds.
- The harpoon/hose state: whether it is out, its length, direction, and the locked target.
- Fygar charge/fire timers and whether a flame is about to cover the player.
- Own invulnerability timer, digging state, exact position (only the tile), and the surface/row limits.
- That enemies reset on death and that the last enemy runs away; no win condition.
