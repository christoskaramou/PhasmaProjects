# QbertRemix

Entry: `Arcade/QbertRemix/run.ps1` starts `Scenes/main.pescene` (run.ps1:29); the scene loads `Assets/Scripts/game.lua`, which loads `Scripts/jev_auto.lua` (game.lua:1355-1356) and registers its own `hooks{update}` that calls `jev:tick` then `update` (game.lua:1390-1395). `Scripts/gamekit/driver.lua` is present and byte-identical to the other Arcade games; `observe` is `pcall`-protected (driver.lua:111-167). Automation helper `G.sim` at game.lua:1398-1402.

## Pyramid and player

- 7-row pyramid, cube (r, c) with r = 0..6 and c = 0..r, 28 cubes (game.lua:55-58, 300-316).
- Four diagonal directions: UR (-1,0), UL (-1,-1), DR (1,1), DL (1,0) (game.lua:59). Q*bert starts at (0,0); a hop lasts 0.32 s (game.lua:536-551, 716-722).
- Keys: arrows/WASD map Left→UL, Up→UR, Down→DL, Right→DR; Q/E/Z/C are direct diagonals; mouse hops toward the cursor; a press is buffered for 0.3 s during a hop (game.lua:1027-1048).
- A hop off the pyramid is a fall: `q_land` marks the landing invalid, starts the fall and calls `lose_life("fall")` (game.lua:738-742).
- A disc on the side of the pyramid can be hopped onto: it carries Q*bert to the apex in 1.6 s, removes all other enemies, and lures a nearby Coily to fall for 500 points (game.lua:724-736, 748-765).

## Round rules (stage progression)

`rule()` depends only on `G.level` (game.lua:513-516):

| Level | Hops to target T | Extra hop effect | Cite |
|---|---|---|---|
| 1 | 1 | none (cube stays) | game.lua:515 |
| 2 | 2 | none | game.lua:515 |
| 3 | 1 | flips the cube back to state 0 | game.lua:515, 529-531 |
| 4+ | 2 | flips a finished cube back to state 1 | game.lua:515, 529-531 |

A round is one pyramid reset: `begin_round` clears enemies, sets every cube to 0, applies a theme, places discs, and shows the level/round banner for 2.6 s (game.lua:767-779). Four rounds make a level; after round 4 the level increments and the round returns to 1 (game.lua:789-796). The round index used by spawn/disc scaling is `(level-1)*4 + round` (game.lua:445).

## Scoring

- Each successful cube hop: 25 points (game.lua:522).
- Round clear: 1000 + 250 × (round index − 1), plus 50 per unused disc (game.lua:780-792).
- Catching Slick or Sam: 300. Catching the green ball: 100 and a 4.5 s freeze (game.lua:847-851).
- Luring Coily off the edge with a disc: 500 (game.lua:616-618).
- Extra life at 8000 points, then every 14,000 (game.lua:1054, 507-509). Start with 3 lives (game.lua:1054).

## Enemies

- Red balls hop randomly down-left/down-right and are fatal on contact (game.lua:582-601, 841-854).
- Green balls are caught for 100 and freeze every enemy for 4.5 s (game.lua:849-851, 631, 690).
- The purple egg hatches into Coily when it reaches the bottom row; contact with either is fatal (game.lua:628, 646-656).
- Coily chases Q*bert by choosing the diagonal that minimises distance, with a small random tiebreak, and is fatal on contact (game.lua:584-598).
- Slick and Sam land on cubes and decrement their state by one (game.lua:624-627); catching them before that gives 300 (game.lua:847-848).
- Every enemy that hops off the pyramid falls and is removed (game.lua:613-620, 657-661).

## Spawn director and timers

- An egg spawns whenever none exists, on a 9 s timer (game.lua:693-694).
- Otherwise spawn interval `max(1.5, 4.0 - n*0.18) * rr(0.8,1.25)` s, with `n` = round index (game.lua:697-698). Green appears from n ≥ 2 at 28%, Slick/Sam from n ≥ 3 at 16%, otherwise a red if fewer than `min(1+floor(n/3),3)` reds exist (game.lua:699-702).
- Enemy rest time `max(0.22, 0.62 - n*0.03)`; hop time `(0.36 for Coily else 0.4) * max(0.75, 1 - n*0.015)` (game.lua:580-581).
- Freeze 4.5 s (game.lua:851). Death animation 1.5 s for a fall, 1.9 s for a hit (game.lua:1101-1111). Round-clear hold 2.6 s (game.lua:1214-1217). Intro 1.6 s (game.lua:1194-1198).

## Lose

`lose_life` enters `dying`; after the timer a life is removed and either play resumes (enemies cleared, Q*bert re-dropped) or `game_over` when lives < 0 (game.lua:706-715, 1101-1111). There is no win state; rounds continue indefinitely.

## Jev attach (game.lua:1357-1371)

`port = 9125`, `id = "qbert_remix"`. `playing()` is `play`, `intro`, `dying` or `clear`; `terminal()` is `over` (game.lua:1241-1243, 1362). `busy()` is `Q.state == "hop"` (game.lua:1364). `reset(seed)` seeds RNG, primes the human-key sampler and starts a new game (game.lua:1342-1348).

### observe() fields (game.lua:1270-1293)

- `qbert` — `{row, col}`.
- `coily` — `{row, col}`; `{-1, -1}` when Coily is absent.
- `nearest_enemy` — `{kind, row, col}` of the closest live enemy by 3D distance; `kind = "none"` and rows -1 when the board is empty.
- `lives`
- `score`

### action ids (game.lua:1295-1329)

`up_left`, `up_right`, `down_left`, `down_right`.

- Returns an empty list unless `G.state == "play"` and `Q.state == "idle"` (game.lua:1296).
- The goal is the nearest cube whose `top_index(cb.s) < 2` (game.lua:1297-1309); with `G.target == 1`, `top_index` maps any `s >= 1` to 2, so only untouched cubes count, while a two-hop round treats states 0 and 1 as unfinished (game.lua:318-321).
- For each of the four moves that lands on a valid cube or a disc, score = `-|nr-goal_r| - |nc-goal_c|`; the first maximum wins (game.lua:1311-1324). That is a greedy step, not a path search, so it can accept a step that walls itself in.
- Exactly one action is offered, carrying that score (game.lua:1328).

### apply(id) (game.lua:1331-1340)

- Looks the id up in `JEV_MOVE` and sets the corresponding virtual key true: `up_left` → Left, `up_right` → Up, `down_left` → Down, `down_right` → Right (game.lua:1233-1238, 1332-1338).
- It first clears any previous pulse, then sets `pulse_key`; the next update clears that virtual key after one frame, so the hop is a one-frame press (game.lua:1205-1207, 1337-1339).
- Unknown ids return without touching the pulse.

## Jev cannot see

- The cube states: only a derived nearest-goal is computed inside `actions`; `observe` exposes no per-cube `s`, so Jev cannot tell which cubes still need hops or how many (game.lua:1270-1293, 1297-1309).
- The round rule: `G.target` (1 or 2), whether an extra hop flips back, and the level/round numbers (game.lua:513-516, 767-779).
- Disc positions and whether a hop lands on one; discs exist only as a legal destination in `actions` (game.lua:452-463, 1317).
- The freeze timer, and therefore whether enemies are currently frozen (game.lua:631, 851).
- Enemy state and timing: rest/hop/drop/hatch, the egg's hatch timer, Coily's lure target, and all enemies except Coily and the single nearest one (game.lua:630-667, 1270-1293).
- The score values for cubes, enemies and discs (game.lua:522, 616-618, 780-792, 847-851).
- The top-out/life countdown during `dying`, and that `playing()` includes `intro`, `dying` and `clear` when `actions` returns nothing (game.lua:1241-1243, 1296, 1101-1111).
