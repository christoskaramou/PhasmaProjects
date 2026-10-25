# 1942Remix — Jev instruction inventory

Source: `Arcade/1942Remix/Assets/Scripts/game.lua` (generated from `Arcade/1942Remix/tools/src/0*.lua`, same line numbers as `game.lua`). Wrapper: `Assets/Scripts/jev_auto.lua`; driver: `Assets/Scripts/gamekit/driver.lua`. Notes checked: `jev-audit/read/A/1942Remix.md`.

## Attach block

`JevAuto.attach` at `game.lua:1350-1393`; port 9136 (`1351`), id `1942remix` (`1352`).

## Description string (verbatim)

`game.lua:1353-1355`:
> "1942 Remix. Fly the P-38 and shoot the formation. A direction is a hold: the plane keeps flying that way and the guns keep firing until the next direction. aim_dx positive means the target is to the right. aim_dy positive means it is up the screen. Prefer the higher action score."

## observe() fields

`game.lua:1369-1380`, all under `observation` (wrapper adds `mode`, `terminal`, `score`, `busy`, `actions`: `jev_auto.lua:54-61`):

| Field | Meaning / source |
|---|---|
| `player_x`, `player_y` | Player position, `P.x`/`P.y` (`game.lua:1369-1373`); x ∈ ±10.9, y ∈ 1.6..27 (`501-502`) |
| `aim_dx`, `aim_dy` | Derived aim vector from `aim_offset()` (`1180-1197`): nearest live enemy if at least 1 unit above the player, else (0, 5); nearby enemy bullets push dx sideways |
| `lives` | Reserve planes `G.lives` (`1376`) |
| `loops` | Remaining loops `P.rolls` (`1377`) |
| `score` | `G.score` (`1378`) |

No stage, phase, enemy, bullet, POW, escort, quad, invulnerability, ceasefire or wave data.

## Actions

`actions()` = `jev_actions` (`game.lua:1199-1224`). The wrapper only calls it when Jev owns a live match (`jev_auto.lua:45-47`, `79-84`), so actions are empty in menus and after terminal. In every phase of `state == "play"` (including takeoff/landing/result) actions are still returned (`playing` = `G.state == "play"`: `1356-1358`).

| id | Description (verbatim) | When offered | Cite |
|---|---|---|---|
| `loop` | "Loop once to dodge a close shot." (score 12) | `P.rolls > 0`, `P.roll <= 0`, and an enemy bullet satisfies `-0.5 < by < 4` and `|bx| < 1.6` relative to the player; when true this is the **only** action returned | `game.lua:1201-1209` |
| `up` | "Fly up. Guns keep firing while this is held." | Otherwise, one direction only: the 8-way step with the largest dot product against `aim_offset()`; ties go to the earlier entry in `DIR_ORDER` (up, up_right, right, down_right, down, down_left, left, up_left) | `game.lua:1050-1073`, `1211-1223` |
| `up_right` | "Fly up-right. Guns keep firing while this is held." | as above | `1067`, `1211-1223` |
| `right` | "Fly right. Guns keep firing while this is held." | as above | `1068` |
| `down_right` | "Fly down-right. Guns keep firing while this is held." | as above | `1069` |
| `down` | "Fly down. Guns keep firing while this is held." | as above | `1070` |
| `down_left` | "Fly down-left. Guns keep firing while this is held." | as above | `1071` |
| `left` | "Fly left. Guns keep firing while this is held." | as above | `1072` |
| `up_left` | "Fly up-left. Guns keep firing while this is held." | as above | `1073` |

`stop` has text (`1074`) but no `DIR_STEP` entry (`1050-1059`), so it can never be the best and is never returned (`1213-1215`).

## Apply / mode / reset

- `apply(id)` (`game.lua:1099-1116`): a direction replaces the virtual Up/Down/Left/Right hold (`1100-1106`); `loop` sets virtual `X`, arms its edge and queues a one-shot pulse released next update (`1108-1116`, `1118-1133`); any other id is a no-op.
- A held direction also forces firing because `driving` plus any direction key sets `q.fire` (`1276-1278`).
- `playing` = `G.state == "play"` (`1356-1358`); `terminal` = `G.state == "over"` (`1359-1361`).
- `busy` = player alive and roll timer running (`1365-1367`); driver rejects `game_act` while busy (`driver.lua:192-194`).
- `reset(seed)` seeds `math.random`, clears holds, sets `driving`, starts a new game (`1383-1388`); `on_human` clears holds and disables driving (`1389-1392`).
- Actions are only legal for the observed `state_id`; `game_act` rejects stale ids and never retries (`driver.lua:186-197`).
