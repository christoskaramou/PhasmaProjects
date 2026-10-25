# 1942Remix — Jev gaps

Checked against gameplay note (`jev-audit/read/A/1942Remix.md`). Code wins where they differ.

## 1. Every direction action is silently ignored outside the `fly` phase

- Sim: `stage_step` returns before movement/fire in `takeoff` (3.0 s per stage, `game.lua:563-569`), `landing` (`571-589`) and `result` (4.0 s, `591-596`). The frame loop additionally zeroes `inp.fire`/`inp.roll` for any phase other than `fly` (`game.lua:1309`).
- Instruction: "A direction is a hold: the plane keeps flying that way and the guns keep firing until the next direction" (`game.lua:1353-1355`). `actions()` is not phase-gated (`1199-1224`), and `playing()` is only `G.state == "play"` (`1356-1358`), so directions and `loop` are offered throughout takeoff/landing/result.
- Effect: Jev is told to choose a direction, the action is legal, and the plane does not move or fire. It is not told that input only works after takeoff (approx. 3 s per stage) or during landing/result.

## 2. `loop` disables firing for 1.6 s and locks out actions, while the description promises the guns keep firing

- Sim: starting a loop costs one loop and sets `P.roll = ROLL_T` (1.6 s, `game.lua:343`, `507`). While `P.roll > 0` the player cannot fire (`game.lua:504-509`). `busy()` is true for that whole time (`1365-1367`) and the driver rejects every action with `busy` (`driver.lua:192-194`).
- Instruction: "A direction is a hold: the plane keeps flying that way and the guns keep firing until the next direction" (`game.lua:1353-1355`); the `loop` action says only "Loop once to dodge a close shot." (`1206`).
- Effect: a direction held before/during a loop stops firing for 1.6 s, and Jev cannot correct course during that window because the driver refuses actions while busy. Neither the invulnerability that makes the dodge work nor the no-fire/busy period is stated.

## 3. `aim_dx`/`aim_dy` is a dodge-biased vector, not the target bearing

- Sim: `aim_offset()` (`game.lua:1180-1197`) uses the nearest live enemy only if `enemy.y > P.y - 1` (`1182`); otherwise the direction is straight up (0, 5) (`1180-1181`). Every enemy bullet with `-0.5 < by < 5` and `|bx| < 2.2` shifts `dx` away from that bullet (`1188-1195`).
- Instruction: "aim_dx positive means the target is to the right. aim_dy positive means it is up the screen." (`game.lua:1354-1355`).
- Effect: when the nearest enemy is level or below the player there is no target, yet the description reads as if there is; and the returned vector can point away from the target because of bullet push. Jev is not told the value is a blended "aim + dodge" vector.

## 4. The POW pickup system is invisible

- Sim: every 5th kill of the same formation group drops a POW at the kill, clamped into the field (`game.lua:437-444`); colours cycle a fixed 12-entry sequence (`334`, `440-441`); POWs drift down at 1.4/s and are collected within 1.25 units (`669-675`). Effects: red = permanent quad guns, green = two escorts, gray = +1 loop, yellow = 10 s enemy ceasefire and clears bullets, orange = +1000, white = destroy all entered enemies / 40 boss damage (`539-555`).
- Instruction: description (`1353-1355`), `observe()` (`1369-1380`) and actions (`1199-1224`) never mention POWs, their colours or effects. Jev cannot see a POW, cannot choose to collect one, and is not told that gray POWs are the only way to gain loops or that quad/escorts exist.
- Effect: a pickup rule that changes firing (quad), survival (escorts), loop supply (gray) and enemy fire (yellow) is entirely outside Jev's model.
