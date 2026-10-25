# CentipedeRemix — how the game works (read from current source)

Source of truth: `Arcade/CentipedeRemix/Assets/Scripts/game.lua` (1667 lines, hand-written; no `tools/src`).
Cites are `Assets/Scripts/game.lua`. Jev wrapper `Assets/Scripts/jev_auto.lua`; driver
`Assets/Scripts/gamekit/driver.lua`. `run.ps1` launches `Scenes/main.pescene` (`run.ps1:29-30`), which loads
`Scripts/game.lua`.

## Shape of a run

- Fixed play tick: `dt` is split into 1/60 s sub-steps (`game.lua:1482-1488`).
- Field: 24 × 28 cells of 1.05 units; 24 wide, 28 tall; the bottom 6 rows are the player's free area
  (`game.lua:39-44`).
- Waves are endless: clearing all centipede segments advances to the next level; there is no win state
  (`game.lua:1571-1586`, `1380-1400`).
- New game: score 0, 3 lives, level 1, mushrooms seeded, one centipede (`game.lua:1318-1323`,
  `1303-1316`).
- States: `boot` → `title`; `levelintro` (1.4 s) → `play`; `dying` (1.6 s); `clear` (2.2 s) → next wave;
  `over` (`game.lua:1561-1604`).

## Player actions

- Move with WASD/arrows at 16 units/s, or mouse (trackball-style chase) — the last input method wins
  (`game.lua:1411-1437`).
- The blaster is confined to the bottom 6 rows and inside the side walls (`game.lua:625-629`).
- Fire: left click or Space. At most **one bullet alive at a time**, with an additional 0.06 s cooldown
  (`game.lua:647-649`).
- Bullet speed 46 units/s, moves straight up, own hitbox against enemies is 0.7–0.95 in x and
  0.6–0.7 in y depending on target (`game.lua:646`, `887-893`).
- Starting position: x 0, y = bottom + 1.5 cells (`game.lua:631-632`, `1313`).

## Hazards and what kills the player

Contact with any of these while `PL.invuln <= 0` triggers `kill_player` (`game.lua:929-941`):
- Any centipede segment: |dx| < 0.8, |dy| < 0.8.
- Flea: |dx| < 0.55, |dy| < 0.55.
- Spider: |dx| < 0.65, |dy| < 0.55.
- Scorpion: |dx| < 0.8, |dy| < 0.5.

`kill_player` sets state `dying`, clears bullets and all three critters, then after 1.6 s `after_death`
removes one life, repairs all damaged mushrooms to 4 hp (each repair scores 5) and either ends the run or
respawns the centipede and puts the blaster back at centre with 2.0 s invulnerability
(`game.lua:1344-1378`, `1592-1595`). Nothing else damages the player.

## What the player can kill and what it scores

| Target | HP / hits | Score | Cite |
|---|---|---|---|
| Mushroom | 4 bullet hits | +1 on destruction | `game.lua:272-291`, `312-321` |
| Centipede head | 1 | 100 | `game.lua:476-486` |
| Centipede body | 1 | 10 | `game.lua:483` |
| Flea | 2 hits | 200 | `game.lua:700`, `733-750`, `887-890` |
| Spider | 1 | 900 / 600 / 300 by proximity to the blaster | `game.lua:751-757` |
| Scorpion | 1 | 1000 | `game.lua:772-775` |

- A bullet dies on the first thing it hits; mushrooms are tested before centipede segments
  (`game.lua:670-686`, `894`).
- Shooting a centipede segment splits the worm: segments before it keep the current direction, segments
  after it become a new worm travelling the opposite way; the killed segment leaves a full-hp mushroom in
  its cell (`game.lua:476-510`).
- Enemies that leave the playfield are removed without score (`game.lua:818`, `844`, `874`).
- Wave-clear bonus: the sum of all remaining mushroom HP is added to the score (`game.lua:1383-1388`).
- Extra life once per game when score reaches 10000 (`game.lua:1396-1399`, `1319`).

## Centipede behaviour

- Segment speed is `5.5 * (1 + 0.12*(level-1))` cells/s (`game.lua:423-426`).
- Movement along a row; on the field edge or a live mushroom ahead, it drops one row and reverses
  (`game.lua:525-572`). It reverses its drop direction at the bottom, bouncing inside the player area
  (`game.lua:545-551`).
- Entering a poisoned mushroom arms a straight-down "poison dive" for that worm (`game.lua:559-561`,
  `533-542`).
- Body segments follow the head's cell path (`game.lua:563-595`).
- A new wave spawns `min(12 + level - 1, 18)` segments starting at the top centre, direction alternating
  by level, plus `min(level - 1, 4)` single-segment worms on later waves (`game.lua:1303-1311`).
- After a death, only the main centipede respawns, with length `min(12+level-1, 18)`, direction +1 and no
  extra heads (`game.lua:1370-1374`).

## Mushrooms

- 4 HP each; a bullet removes one HP and the mushroom shrinks visually; at 0 it is destroyed and scores 1
  (`game.lua:312-321`).
- Initial seeding: `35 + level*3` mushrooms, only in rows above the player area (`game.lua:357-369`,
  `1305`).
- A destroyed mushroom cell can be replanted by a flea drop (`game.lua:793-801`).
- The spider randomly eats mushrooms it passes (`game.lua:833-836`).
- The scorpion poisons every live mushroom within one cell of it on its row; a poisoned mushroom shows a
  different colour and makes any centipede entering it dive (`game.lua:847-857`, `332-347`, `559-561`).
- Between lives all damaged mushrooms are repaired to full HP and each repaired mushroom scores 5
  (`game.lua:380-402`).
- At the start of a new wave, 8 more mushrooms are sprinkled above the player area
  (`game.lua:1390-1394`).

## Flea, spider, scorpion

- Flea: spawns only when fewer than 3 mushrooms are in the player area; moves straight down at
  `7.5 + 0.4*level`; leaves a mushroom roughly every 0.85 cells of travel with 55% probability; 2 HP
  (`game.lua:693-702`, `791-819`, `916-919`).
- Spider: spawns from a side in the player area, moves horizontally at `5.5 + 0.3*level` and reverses its
  vertical zigzag every 0.25–0.55 s; bounces between the player-area top and 2 cells below its bottom;
  eats mushrooms (`game.lua:704-716`, `821-845`).
- Scorpion: crosses one random row above the player area at `4.0 + 0.25*level`, poisoning mushrooms
  (`game.lua:717-731`, `847-875`).
- Spawn cooldowns are reset on wave start to 2.0 / 4–7 / 9–14 s, and after a player death to
  1.5 / 5 / 10 s (`game.lua:1312`, `907-910`).

## Timers and durations

| Timer | Value | Cite |
|---|---|---|
| Bullet fire cooldown | 0.06 s, and only one bullet alive | `game.lua:648-649` |
| Wave intro | 1.4 s | `game.lua:1564` |
| Death to life loss | 1.6 s | `game.lua:1595` |
| Wave clear to next wave | 2.2 s | `game.lua:1599` |
| Invulnerability on wave start | 1.5 s | `game.lua:1314` |
| Invulnerability after death | 2.0 s | `game.lua:1374` |
| Flea respawn cooldown | 4–8 s | `game.lua:918` |
| Spider respawn cooldown | `6–12 - min(level,5)*0.4` s | `game.lua:921` |
| Scorpion respawn cooldown | `12–20 - min(level,6)*0.5` s | `game.lua:924` |
| Spider zigzag interval | 0.25–0.55 s | `game.lua:824` |

There are no ladders, freezes or slow effects.

## Win and lose

- Win: **none**. Waves continue indefinitely; `G.level` only grows (`game.lua:1380-1400`).
- Lose: lives reach 0 in `after_death`; state `over` (`game.lua:1358-1368`).
- Hi-score is loaded from `Save/hiscore.txt` and saved on game over / quit / title, but never when Jev
  was assisted (`game.lua:1285-1300`, `1315`).

## JevAuto.attach for this game

Attach block `game.lua:1612-1637`, port 9122, id `centipede_remix`.

`observe()` returns exactly `blaster` (`{ c, r }`), `segment` (`{ c, r }`), `lives`, `score`
(`game.lua:1200-1209`). The wrapper adds `mode`, `terminal`, `score`, `busy`, `actions`
(`jev_auto.lua:54-61`). `segment` is the nearest centipede segment in cell distance, or `{-1,-1}` when
there are no segments (`game.lua:1180-1197`). `busy` is always false (`game.lua:1621-1623`).
`playing()` is true in `levelintro`, `play`, `dying` and `clear` (`game.lua:1257-1260`).

Action ids produced by `actions()` (`game.lua:1226-1255`): a direction with `_fire` appended —
`n_fire`, `s_fire`, `e_fire`, `w_fire`, `ne_fire`, `nw_fire`, `se_fire`, `sw_fire`, `stop_fire`.
- No segment → `stop_fire`.
- Otherwise the direction is built from the sign of the row/column difference to the nearest segment
  (row smaller = north, larger = south; column larger = east, smaller = west), with both axes combined,
  and `_fire` is always appended.

`apply(id)` (`game.lua:1152-1178`):
- A trailing `_fire` sets the fire flag and strips the suffix; the base id indexes `DIR_KEYS`
  (`n/s/e/w/ne/nw/se/sw/stop`) (`game.lua:1099-1109`).
- The complete `G.vkeys` table is replaced by the new direction's keys plus Space when firing, so the
  action is a hold that persists until the next act (`game.lua:1169-1177`).
- `stop_fire` sets only Space (hold still and fire).
- Unknown ids do nothing.
- `reset(seed)` seeds random, disables mouse control and starts a new game (`game.lua:1628-1635`);
  `on_human` clears the hold (`game.lua:1636`).

## Jev cannot see

- Every mushroom: grid position, HP, and poisoned state; the field layout generally.
- All centipede segments except the single nearest one; how many worms/segments remain and which
  direction they travel.
- Flea, spider and scorpion, their positions and HP.
- Bullets in flight (only one exists at a time) and the fact that firing is blocked while one is alive.
- Wave number, score needed for the single extra life, and the wave-clear bonus.
- Own invulnerability timer, and the exact movement limits of the bottom 6 rows.
- The player always fires upward; `observe()` gives no facing because there is none.
