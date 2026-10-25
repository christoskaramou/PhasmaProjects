# PitfallRemastered

Entry: `Arcade/PitfallRemastered/run.ps1` starts `Scenes/main.pescene` (run.ps1:29); the scene loads `Assets/Scripts/game.lua`, which loads `Scripts/jev_auto.lua` (game.lua:1401-1402) and registers `hooks{init,update}` (game.lua:1436). `Assets/Scripts/gamekit/driver.lua` is present and identical to the other Arcade games; its `observe` call is `pcall`-protected (driver.lua:111-167). Fixed 120 Hz simulation (game.lua:6, 1345-1353), plus a separate `G.sim` test helper (game.lua:1379-1392).

## World

24 units wide, underground floor y = -5, ceiling y = -1.5, 120 Hz step (game.lua:6). Movement: max run 5.4, ground accel 34, ground decel 42, air accel 16 (game.lua:7-8). Jump velocity 9.4, gravity 21 going up / 30 coming down / 11 near the apex, jump-cut ×2.4 when Space is released while rising, coyote time 0.13 s, jump buffer 0.15 s, climb speed 3.4 (game.lua:9-13).

## Rooms and stage progression

- 255 rooms come from an 8-bit LFSR table seeded 0xC4 (game.lua:122-130). Each room byte yields `obj` (low 3 bits), `kind` (bits 3-5), `trees` (bits 6-7) and a wall side bit (game.lua:133).
- `kind` sets the hazard: 0/1 are ladder rooms with 1 or 3 holes, 2 tar, 3 swamp, 4 croc, 5/6 shifting tar, 7 quicksand; a vine exists for kinds 2, 3, 6 and some kind-4 rooms; kind 5 holds a treasure whose value is `band(obj,3)` (game.lua:134-141).
- Logs, fire, cobra and treasure are then derived from `obj` (game.lua:142-157). Fire and cobra always sit at x = 19.5 (game.lua:880, 611-619).
- Crossing x < 0 or x > 24 wraps to the other side and loads `screen + 255 + d * (underground and 3 or 1)`, i.e. one room per step above ground and three per step in the tunnel (game.lua:845-852).
- Treasures are worth 2000 / 3000 / 4000 / 5000 by type 0-3 (game.lua:24-25). `TOTAL_TREASURES` is the count of rooms with kind 5, computed at load (game.lua:159-160).

## Player actions

- Left/Right or A/D run; up/down or W/S climb (game.lua:1070-1072).
- Space jumps; a buffered press within 0.15 s and coyote time within 0.13 s of leaving ground are honoured (game.lua:758, 785-789).
- On a ladder (|x-12| < 1.0): down enters the ladder from above, up from below (game.lua:781-782). Climbing is clamped between the underground floor and y = 0; left/right steps off at either end (game.lua:830-839).
- On a vine: down drops with the vine's velocity, Space jumps off with vy 6.5 and a 0.6 s regrab lockout (game.lua:820-829).
- A wall in ladder rooms blocks passage within `0.5 + 0.3` of it while underground (game.lua:767, 155).

## Hazards and death

`die(cause)` sets `dying`; after 2.0 s a life is lost, then either respawn or `over` (game.lua:664-683, 1359-1361). 3 lives, respawn at x = 2.5, y = 6.5 with 1.5 s invulnerability (game.lua:643, 637-640). Death sources:

- Falling into a pit: standing on `ground` with |x - 12| inside the pit half-width (game.lua:855-863). Tar, swamp, shifting tar and quicksand kill outright.
- Croc pit: if no croc is under the feet → `water`; if a croc is under but its mouth opening is > 0.5 and x < croc_x + 0.15 → `croc` (game.lua:857-862). Closed mouth is safe ground.
- Fire or cobra: |x - 19.5| < 0.5 and y < 0.8 while above ground (game.lua:880).
- Scorpion: underground, |x - scorp_x| < 0.55 and y < -4.55 (game.lua:882-885). The scorpion chases the player at 1.5 u/s (game.lua:895-898).
- Falling from the surface into the tunnel costs 100 points, not a life (game.lua:740-744).
- Logs: standing within 0.55 of a log at y < 0.55 costs 100 points, sets a 0.45 s stumble at 40% speed, and keeps draining 30 points/s while touching (game.lua:866-878).

## Timers, pickups, win and lose

- Start: score 2000, 3 lives, 1200 s (20:00) (game.lua:643).
- Pit widths for shifting tar/quicksand oscillate with a 7 s period (game.lua:714-720).
- Croc mouth: 4 s cycle, closed for 2 s, then opening over 0.25 s, open, closing over the last 0.25 s (game.lua:729-733).
- Vine period 3.4 s, amplitude 0.95 rad, catch radius 1.7 from the tip point offset by hand height 2.15 (game.lua:15-16, 722-727, 802-811).
- Treasure pickup at |x - 20| < 1.0, y < 1.4, once per room; awards its value, marks the room collected and, when all are found, sets `win` (game.lua:686-702, 881).
- Lose when `time` reaches 0 (game.lua:1356-1357) or the last life is lost (game.lua:1359-1361).

## Jev attach (game.lua:1403-1434)

`port = 9102`, `id = "pitfall"`. `playing()` is `play` or `dying`; `terminal()` is `over` or `win` (game.lua:1407-1412). `busy()` is `hop` (game.lua:1416-1418), the short flag set by the jump action and cleared once the hop has been in the air or after 2 frames without leaving the ground (game.lua:1130-1148).

### observe() fields (game.lua:1249-1260)

- `x` — player x, rounded to 2 decimals.
- `on_ground` — `P.mode == "ground"`.
- `on_vine` — `P.mode == "vine"` or `"catch"`.
- `hazard_side` — `"left"`, `"right"` or `"none"`, from the nearest considered hazard.
- `hazard_distance` — its distance minus its pad, floored at 0; `999` when none.
- `lives`
- `score`

`nearest_hazard` considers: every hole (pad 0.85), every log's x (pad 0.55), fire/cobra at 19.5 (pad 0.5), the scorpion when underground (pad 0.55), and the pit (open croc jaws at pad 0.9, plus the pit edges) (game.lua:1220-1243, 1165-1218).

### action ids (game.lua:1421-1430)

- `"jump"` when the nearest hazard distance is < 2.2 (score 2).
- `"left"` when the nearest hazard is on the left (score 1).
- `"right"` otherwise (score 1).

Exactly one is offered; `"stop"` and `"down"` are legal per `apply_action` but never offered.

### apply(id) (game.lua:1270-1294)

- `"left"` → `G.vkeys.Left = true`, `Right = nil`.
- `"right"` → `G.vkeys.Right = true`, `Left = nil`.
- `"stop"` → both cleared.
- `"jump"` → holds Right, clears Left, sets Space and `pulse_space`; in `play` also sets `hop = true`, `hop_saw_air = false`, `hop_wait = 2`, which is what `busy` reports. Space is released by `release_pulses` on the next frame (game.lua:1119-1128, 1344).
- `"down"` → sets Down and `pulse_down`; released the next frame the same way.
- Unknown ids do nothing.

Left/right are holds and persist until replaced. Jump always resumes running right.

## Jev cannot see

- The room: its `kind`, pit type and width, which holes exist, the ladder, the vine pivot/angle, the wall, tree positions, and how many rooms remain (game.lua:131-158, 573-634).
- The vine itself and the swing state, beyond an `on_vine` boolean; the catch radius and tip position are not exposed (game.lua:802-829).
- Croc mouth phase: only the instantaneous nearest-hazard distance is given, not the 4 s open/close cycle (game.lua:729-733, 1181-1192).
- The scorpion's position, direction and the fact it chases (game.lua:895-898).
- The treasure: presence, value, distance ahead, and `found / TOTAL_TREASURES` (game.lua:686-702).
- The clock (1200 s start), lives are visible but time is not (game.lua:643, 1356-1357).
- Which side is safe: `hazard_side` is only the side of the single nearest hazard and ignores the hazard behind it (game.lua:1220-1243).
- Room transitions and the 1-vs-3-screen tunnel stride (game.lua:845-852).
- That `playing()` includes `dying`, when actions have no effect (game.lua:1407-1409, 1342-1361).
