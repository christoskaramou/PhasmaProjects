# BombermanRemix — how the game works (read from current source)

Source of truth: `Arcade/BombermanRemix/Assets/Scripts/game.lua` (1461 lines). Byte-identical concatenation of
`Arcade/BombermanRemix/tools/src/0*.lua` via `tools/build_lua.sh:1-3` (verified). Cites are
`Assets/Scripts/game.lua` lines. Jev wrapper `Assets/Scripts/jev_auto.lua`; driver
`Assets/Scripts/gamekit/driver.lua`. `run.ps1` launches `Scenes/main.pescene` (`run.ps1:29-30`), which loads
`Scripts/game.lua`.

## Shape of a run

- Fixed step 1/60 s, at most 6 steps per frame (`game.lua:411`, `1413-1417`).
- Arena is a 31 × 13 cell grid plus a one-cell border; one cell is 2 world units; cell (c, r) centres at
  `(c*2, 0, r*2)` (`game.lua:15`, `378`, `381`).
- 50 stages, `ST.n` 1..50 (`game.lua:373`, `1389`).
- Cell contents: 0 empty, 1 hard (border or even/even pillar), 2 brick (`game.lua:378`, `388-394`).
- New game: score 0, 3 lives, stage 1, powers reset to 1 bomb / 1 fire / no speed (`game.lua:1129-1132`,
  `761-767`).
- State machine: `title` → `intro` (2.4 s stage card) → `play`; `clear` (3.2 s) → next stage;
  `over` ends the run (`game.lua:1374-1399`).
- Stage clear: standing on the exit cell while the exit is exposed and open
  (`game.lua:769`, `1418-1423`); after stage 50 it calls `game_over(true)` (`game.lua:1389`).

## Layout generation, stage by stage

- Hard cells: the outer border ring and every cell where c and r are both even (`game.lua:391`).
- Bricks: each free non-start cell gets a brick with 26% probability from a deterministic LCG seeded
  `n*7919 + 13`, so a stage layout is fixed (`game.lua:386-400`). Cells with `c + r <= 3` (the start
  corner) never get bricks (`game.lua:397`).
- One brick cell is then chosen as the exit, one as the hidden power-up; both stay in the brick set, and
  the item is revealed only when its covering brick burns (`game.lua:404-405`, `463-464`, `732-733`).
- Enemy slots are empty cells with `c + r >= 9`, chosen randomly without replacement
  (`game.lua:407`, `467-476`).
- Enemy mix per stage: stages 1–20 use the explicit `ST_EN` table; stages 21–50 generate
  `total = min(10, 7 + floor((n-20)/10))` enemies from tiers 3–7, forcing tier 7 for the first two
  enemies on every 5th stage (`game.lua:342-367`).
  - Stage 1: 6 Ballom. 2: 3 Ballom + 3 Onil. 3: 2 each Ballom/Onil/Dahl. 4: 1/1/2/2 through Minvo.
    5: 4 Onil + 3 Dahl. 6: 2 Onil + 3 Dahl + 2 Minvo. 7: 2 Onil + 3 Dahl + 2 Doria. 8: 1 Onil + 2 Dahl +
    4 Minvo. 9: 1/1/4/1 through Doria. 10: 1/1/1/3/1 through Ovape. 11: 1/2/3/1/1. 12: 1/1/1/1/4.
    13: 3 Dahl + 3 Minvo + 2 Ovape. 14: 7 Ovape + 1 Pass. 15: 1 Dahl + 3 Minvo + 3 Ovape + 1 Pass.
    16: 3 Minvo + 4 Ovape + 1 Pass. 17: 5 Dahl + 2 Ovape + 1 Pass. 18: 3 Dahl + 3 Minvo + 2 Pass.
    19: 1 Onil + 1 Dahl + 3 Doria + 1 Ovape + 2 Pass.
    20: 1 each Dahl/Minvo/Doria + 2 Ovape + 2 Pass (`game.lua:343-346`).
- Each stage has a fixed hidden power-up from `ST_PU`, 50 entries; repeat use of bombs/bombpass/detonator
  later (`game.lua:347-351`).
- Every stage timer is 200 s (`game.lua:373`, `766`).

## Player actions

- Walk: WASD/arrows; most recently pressed direction is tried first, and if it is blocked any other held
  direction is tried (`game.lua:677-682`, `1322-1345`).
- Speed: 3.2 cells/s, plus 1.0 if the Speed power-up was taken (`game.lua:413`, `663`, `675`).
- Player collision half-width 0.42 cells; the box test checks every overlapped cell
  (`game.lua:414`, `445-452`). Corner assist slides the player toward the lane centre when a move is
  blocked (`game.lua:623-648`).
- Drop bomb: Space/Z/J/left click (`game.lua:1404`). A bomb may not be placed on a solid cell or another
  bomb, and only while live bombs < `P.bombs` (`game.lua:548-554`).
- Detonate: X/K/right click, only once the Detonator power-up is held; it detonates the **oldest** remote
  bomb (`game.lua:610-614`, `1405`, `674`).
- Bombs are placed "passable": while the player is still inside the bomb's cell the bomb does not block
  him; the flag clears once he is out (`game.lua:554`, `690-692`).

## Bombs and flames

- Fuse `FUSE = 2.6` s (`game.lua:412`, `554`, `717-719`). Remote bombs do not tick down while the player
  is alive; they only tick if he is dead (`game.lua:718`).
- Flame lifetime `FLAME_T = 0.55` s (`game.lua:412`, `570`). Brick burn time `BURN_T = 0.5` s
  (`game.lua:412`, `598`, `726-735`).
- Blast shape: the bomb cell plus up to `P.fire` cells in each of the four directions
  (`game.lua:591-603`).
  - A hard cell stops the arm (`game.lua:595`).
  - A brick cell starts burning, stops the arm, and does not pass the flame on (`game.lua:596-600`).
  - A bomb in the arm is detonated immediately, chaining (`game.lua:601-605`).
  - Flame cell kinds are `core`, `arm`, `end`; `end` is only the last cell of a full arm
    (`game.lua:590`, `602`).
- Every flame cell is written to `FLAME` and `FLAMEG` (explosion group) on the same step; only the visual
  FX is staggered (`game.lua:569-571`, `603-604`).
- Explosion kills: any live enemy whose cell contains a flame dies (`game.lua:740-743`).
- Chain scoring: within one explosion group each successive kill doubles its base value:
  `points = base * 2^(kills-1)` (`game.lua:560-565`).

## Hazards and what kills the player

- Flame in the player's cell, unless Flame Pass is held or `P.inv > 0` (`game.lua:744-746`).
- Enemy contact within 0.62 cells in both axes, unless `P.inv > 0` (`game.lua:415`, `747-751`).
- `player_die` sets state `dead` and starts a 2.6 s death timer; then one life is lost. At 0 lives the run
  ends; otherwise the **same stage restarts with powers kept** (`game.lua:653-658`, `1428-1431`).
- The timer does not kill: at 0 s it spawns 8 Pontan on random empty cells, once, and shows "Time Up"
  (`game.lua:701-710`).
- Nothing else is lethal: bricks, pillars, bombs and the border only block movement.

## What the player can kill

`EN` table (`game.lua:329-338`), columns: mesh, speed (cells/s), smart, wallpass, points, name.

| Tier | Speed | Smart | Wall pass | Points |
|---|---|---|---|---|
| Ballom | 1.6 | 0 | no | 100 |
| Onil | 2.5 | 1 | no | 200 |
| Dahl | 2.5 | 0 | no | 400 |
| Minvo | 3.4 | 1 | no | 800 |
| Doria | 1.0 | 2 | yes | 1000 |
| Ovape | 1.6 | 1 | yes | 2000 |
| Pass | 3.4 | 2 | no | 4000 |
| Pontan | 3.4 | 3 | yes | 8000 |

- Only flame kills enemies (`game.lua:740-743`); a kill is ignored while the enemy has spawn invulnerability
  (`game.lua:561`, `540`).
- Enemies with wall pass may enter brick cells; all enemies are blocked by hard cells and by bombs
  (`game.lua:438-443`).
- Enemy AI: choose a direction from the open neighbours; smart enemies (smart > 0) may steer toward the
  player within `3 + smart*2` cells with probability `0.35 + smart*0.2`; otherwise they keep direction,
  avoid reversing, and turn with probability 0.5 (Dahl/Pontan) or 0.12 (others) (`game.lua:489-516`).
- An enemy about to enter a cell where a bomb was just dropped turns back (`game.lua:530-531`).
- Enemy spawn waves: flame hitting the exposed power-up destroys it and spawns 8 enemies of the stage's
  spawn tier at that cell; same for the exposed exit, with a 1.0 s cooldown between exit waves
  (`game.lua:572-579`, `373`).
- Enemies shot by flame are removed from the list 1.0 s after death (`game.lua:738`).

## Power-ups

The hidden power-up sits under one brick; it is revealed when that brick burns, and is collected by
standing on its cell (`game.lua:463-464`, `733`, `694`). Flame destroys it if it is already exposed
(`game.lua:572-575`). `apply_pu` (`game.lua:660-667`):

- `bombs` → +1 simultaneous bomb, capped at 10 (`game.lua:661`).
- `fire` → +1 blast range, capped at 10 (`game.lua:662`).
- `speed` → sets `P.speed = 1` (a one-time +1.0 cells/s; not cumulative) (`game.lua:663`, `675`).
- `mystery` → `P.inv = 10` s of invulnerability (`game.lua:664`).
- `wallpass` / `bombpass` / `flamepass` / `detonator` → set a permanent boolean for the run
  (`game.lua:665`).
- Every pickup shows its name as a popup and scores nothing directly (`game.lua:666`).

Powers carry between stages (`start_stage(n, true)`) but the four pass/detonator booleans are cleared at
every stage reset (`game.lua:764-765`, `1389`).

## Timers and durations

| Timer | Value | Cite |
|---|---|---|
| Stage clock | 200 s | `game.lua:373`, `766` |
| Bomb fuse | 2.6 s | `game.lua:412` |
| Flame life | 0.55 s | `game.lua:412` |
| Brick burn | 0.5 s | `game.lua:412`, `728-735` |
| Player death to life loss | 2.6 s | `game.lua:1428` |
| Mystery invulnerability | 10 s | `game.lua:664` |
| Stage intro card | 2.4 s (skippable after 0.4 s) | `game.lua:1376` |
| Stage clear card | 3.2 s (skippable after 0.8 s) | `game.lua:1387-1388` |
| Enemy spawn invulnerability | 1.0 s | `game.lua:540` |
| Exit-wave cooldown | 1.0 s | `game.lua:576-578` |
| Time-up Pontan spawn | once, at 0 s | `game.lua:703-710` |

There are no ladders, no freeze/slow effects and no score-based extra lives.

## Score, win, lose

- Score only from enemy kills, with the doubling chain inside one explosion group
  (`game.lua:560-565`).
- High score is loaded from `Save/bomberman_hiscore.txt` and saved on game over only when Jev was not the
  assisted player (`game.lua:313-315`, `1313-1316`).
- Win: clear stage 50 and then either wait 3.2 s or press Enter/Space after 0.8 s → `game_over(true)`
  (`game.lua:1387-1390`, `1310-1312`).
- Lose: lives reach 0 after a death; `game_over(false)` (`game.lua:1428-1431`).
- The exit only opens when zero enemies are alive; it closes again if an enemy wave spawns
  (`game.lua:753-758`).

## JevAuto.attach for this game

Attach block `game.lua:1282-1308`, port 9134, id `bomberman_remix`.

`observe()` returns exactly `cell` (`{ c, r }`), `nearest_enemy` (`{ c, r }` or `nil`), `bombs`, `lives`,
`score` (`game.lua:1232-1257`). The wrapper adds `mode`, `terminal`, `score`, `busy`, `actions`
(`jev_auto.lua:54-61`). `nearest_enemy` is the live enemy with the smallest Manhattan distance in cells
(`game.lua:1237-1248`). `busy` is always false (`game.lua:1295-1297`).

Action ids produced by `actions()` (`game.lua:1259-1280`): `right`, `left`, `down`, `up` only.
- No live enemy → `right`.
- Otherwise walk along the larger axis difference toward the nearest enemy; ties prefer the horizontal
  axis; if already on the enemy cell → `right`.

`apply(id)` (`game.lua:1164-1192`):
- A direction id clears the other walk keys and sets the matching direction keys, and also sets the
  virtual `Z`/`J` bomb keys — so a movement action drops a bomb as well as walking
  (`game.lua:1166-1175`).
- `stop` clears the walk keys (`game.lua:1177-1180`).
- `bomb` sets `Z`/`J` only; `detonate` sets `X`/`K` (`game.lua:1182-1191`).
- Pulse keys (`Z`, `J`, `X`, `K`) are consumed at the start of the next update, so each applied action
  yields one shot of the corresponding key (`game.lua:1194-1213`).
- Walk holds persist until replaced or `stop`.
- `reset(seed)` seeds random, clears virtual keys and starts stage 1 (`game.lua:1302-1306`);
  `on_human` clears all virtual keys (`game.lua:1307`).

## Jev cannot see

- Stage number, clock remaining, and whether the stage is in intro/play/clear.
- The brick/pillar layout, the exit cell and whether it is exposed/open, and the hidden power-up cell,
  kind and whether it is exposed/taken.
- Bombs on the field, their cells, fuses and ranges; flames and burning bricks.
- How many enemies are alive (`G.alive`), each enemy's type, HP/spawn invulnerability, and all enemies
  except the nearest one.
- Own power-up state: bombs/fire count are exposed, but speed, wallpass, bombpass, flamepass, detonator
  and the Mystery timer are not.
- Own invulnerability timer and death timer.
- Whether a bomb can actually be placed now (live-bomb cap), and that a move action also bombs.
- The life count is the internal count including the current life (`game.lua:1254`); the HUD shows one
  less while alive (`game.lua:1050`).
