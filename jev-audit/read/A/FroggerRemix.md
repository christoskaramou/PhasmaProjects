# FroggerRemix — how the game works (read from current source)

Source of truth: `Arcade/FroggerRemix/Assets/Scripts/game.lua` (1390 lines, hand-written; no `tools/src`).
Cites are `Assets/Scripts/game.lua`. Jev wrapper `Assets/Scripts/jev_auto.lua`; driver
`Assets/Scripts/gamekit/driver.lua`. `run.ps1` launches `Scenes/main.pescene` (`run.ps1:29-30`), and that scene
loads `Scripts/game.lua`.

## Shape of a run

- Rows 0..12: row 0 start sidewalk, rows 1–5 road, row 6 median, rows 7–11 river, row 12 home row
  (`game.lua:94-103`).
- Columns are −6..6 half-cell steps; the frog is clamped by `start_hop` (`game.lua:95`, `636-648`).
- A hop lasts `HOP_T = 0.17` s with an arc height of 0.42 world units (`game.lua:98-99`).
- Each frog has a 40 s timer (`game.lua:100`, `569`).
- Five home bays at x = −5, −2.5, 0, 2.5, 5 (`game.lua:101`).
- New game: score 0, 3 lives, level 1, all bays empty, frog at row 0 (`game.lua:1014-1022`).
- The game is endless: clearing all five bays advances the level (`game.lua:691-701`, `1024-1033`).

## Player actions

- One hop per fresh key press: Up/W, Down/S, Left/A, Right/D (`game.lua:735-748`, `750-759`).
- Presses during a hop, a held key and key repeat are ignored; after a hop the key must be released
  before it can hop again (`game.lua:750-759`).
- A hop moves one row or one column. It is rejected (frog only turns) at row <0, row >12, or |x| > 6.01
  (`game.lua:636-642`).
- While riding a log/turtle, the frog inherits the platform's horizontal velocity, both standing and during
  a hop (`game.lua:643`, `763`, `781`).
- Jumping onto ground snaps x to the nearest half-cell unless on row 0 or 6 (`game.lua:729`).

## Hazards and what kills the player

- Water: landing on a river row with no log/turtle under the frog, or the platform drifting out from under it,
  or a turtle diving while ridden (`game.lua:712-717`, `777-785`).
- Traffic: a vehicle overlapping the frog's 0.26 half-width in the row being crossed; this is also checked
  mid-hop once hop progress > 0.25 (`game.lua:661-668`, `771-775`, `787-789`).
- Hedge: landing on row 12 outside a bay, or on a bay that is already filled (`game.lua:718-727`).
- Edge: riding a platform until |x| > 6.6 (`game.lua:786`).
- Time: the 40 s frog timer reaching 0 (`game.lua:1042-1044`).
- Death state lasts 1.4 s, then one life is lost; at 0 lives the run ends, otherwise the frog respawns at
  (x 0, row 0) with a fresh 40 s timer (`game.lua:1102-1107`, `610-620`).

## Lanes (stage layout)

Lane data `game.lua:356-367`; vehicle body extents `game.lua:354-355`. Speeds are world units/s before the
level multiplier.

| Row | Content | Dir | Base speed | Spacing |
|---|---|---|---|---|
| 1 | sedans | left | 0.8 | x = −10, 0, 10 |
| 2 | bulldozers | right | 0.6 | −12, −4.5, 3, 10.5 |
| 3 | sedans | left | 1.0 | −12, −2, 8 |
| 4 | racers | right | 2.0 | −9, 6 |
| 5 | trucks | left | 0.7 | −9, 1, 11 |
| 7 | 3-turtle groups | left | 0.75 | five groups |
| 8 | short logs | right | 0.6 | five logs |
| 9 | long logs | right | 1.3 | −10, 0, 10 |
| 10 | 2-turtle groups | left | 0.9 | six groups |
| 11 | medium logs | right | 0.9 | four logs |

- Lane objects wrap at a 30-unit loop, so objects live in x ∈ [−15, 15] (`game.lua:97`, `523-525`).
- All lane speeds scale by `G.mult` (`game.lua:508`, `521`).
- Turtle groups with `dives` follow a fixed 7 s cycle: 0–4 s up, 4–4.8 s diving, 4.8–6 s submerged, 6–7 s
  rising (`game.lua:509-517`). A submerged turtle (`depth > 0.55`) cannot support the frog
  (`game.lua:650-659`, `784`).
- Level 1: only the scripted groups dive. From level 3 every second turtle group dives; from level 5 all of
  them do (`game.lua:362`, `365`, `1028`).

## Level progression

- `G.mult = min(1.6, 1.0 + 0.1*(level-1))` — 10% faster per level, capped at 1.6× (`game.lua:1026`).
- After all five bays are filled, a 2.8 s clear state runs, then the level increments, bays reset and the frog
  respawns (`game.lua:691-701`, `1024-1033`, `1108-1115`).
- There is no win state; levels continue (`game.lua:1024-1033`).

## Timers and durations

| Timer | Value | Cite |
|---|---|---|
| Hop | 0.17 s | `game.lua:98`, `762` |
| Frog timer | 40 s, warning ticks in the last 8 s | `game.lua:100`, `1042-1044` |
| Death to life loss | 1.4 s | `game.lua:1104` |
| Turtle dive cycle | 7.0 s (4 up / 0.8 dive / 1.2 under / 1 rise) | `game.lua:509-517` |
| Level-clear celebration | 2.8 s | `game.lua:697`, `1110` |
| Fly lifetime on a bay | 5.5 s | `game.lua:859` |
| Fly respawn timer | 4–10 s after disappearing | `game.lua:855` |
| Landing squash decay | 6/s | `game.lua:791` |

There are no freezes, slows or invulnerability power-ups.

## Pickups and scoring

- 10 points the first time the frog reaches each new maximum row (`game.lua:710`).
- Reaching a home bay: `50 + floor(time_left * 2) * 10`, i.e. 10 points per half-second remaining
  (`game.lua:683`).
- Bonus fly: sits on one unfilled bay; collecting it with that bay adds 200 and clears it
  (`game.lua:684-685`, `850-869`).
- Filling all five bays adds 1000 (`game.lua:691-696`).
- Extra frog at 10000 points, once (`game.lua:587-591`).
- Hi-score loaded from `Save/hiscore.txt`; saved on game over unless Jev was assisted (`game.lua:577-586`,
  `1034-1038`).

## JevAuto.attach for this game

Attach block `game.lua:1298-1388`, port 9109, id `frogger-remix`.

`observe()` returns exactly `cell` (`{ row, x }`), `hopping`, `here`, `next`, `lives`, `score`, `time_left`
(`game.lua:1322-1332`). The wrapper adds `mode`, `terminal`, `score`, `busy`, `actions`
(`jev_auto.lua:54-61`).
- `here` / `next` are mover summaries for the frog's row and row+1 (`game.lua:1214-1248`): `kind`
  (`log`/`turtle`/vehicle/`none`), `dx`, `vx`, `left`, `right`, `on`, and `diving` for a submerged turtle.
- `busy` is true while a hop is in progress (`game.lua:1311-1313`).

Action ids produced by `actions()` (`game.lua:1333-1376`): `up`, `down`, `left`, `right` — at most one is
offered per observation, always with score 1. Only ids that pass `hop_open` (row/x bounds) are offered
(`game.lua:1250-1264`).
- Ride ahead and submerged turtle: sidestep away from it (`left` when dx ≥ 0, else `right`), else `down`.
- Ride ahead already under the frog: `up`, else sidestep.
- Ride ahead: hop toward it (`right` if dx > 0, else `left`), else `up`.
- Traffic ahead and overlapping: sidestep away, else `down`.
- Otherwise: `up`, `left`, `right`, `down` in that preference order.

`apply(id)` (`game.lua:1377-1384`): maps the id to the matching key via `HOP_KEY`, clears virtual keys and
issues one virtual key press (`G.press`), i.e. a one-shot hop with no hold (`game.lua:1187`). Unknown ids do
nothing. `reset(seed)` resets lane objects and starts a new game (`game.lua:1266-1294`, `1385-1387`).

## Jev cannot see

- The level number and the speed multiplier.
- Lane objects other than the nearest mover in the current row and row+1: no cars/logs further ahead/behind,
  no row 2–5 traffic beyond the one summary.
- Vehicle extents/speed beyond the summarised `left`/`right`/`vx`, and whether the frog's next cell will be
  occupied by traffic in two rows.
- Turtle dive timers (only the boolean `diving` when already submerged).
- Which home bays are filled, and the fly's bay/lifetime.
- The frog's riding platform identity and the current drift offset beyond `cell.x`.
- The death cause and whether the frog is in the dying/clear state (only `hopping` and the wrapper `mode`).
- That input requires a key release between hops: Jev's `apply` is a forced one-shot press, but the game's
  `hop_lock` state is not exposed.
