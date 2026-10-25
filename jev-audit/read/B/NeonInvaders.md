# NeonInvaders

Entry: `Arcade/NeonInvaders/run.ps1` starts `Scenes/main.pescene` (run.ps1:29); the scene loads `Assets/Scripts/game.lua`, which loads `Scripts/jev_auto.lua` (game.lua:835-836) and registers `hooks{init,update}` (game.lua:863). `Assets/Scripts/gamekit/driver.lua` and `json.lua` are present; `driver.lua` is byte-identical across the Arcade games (hash 16CE0804…), so the wrapper behaviour below applies to every game in this batch.

## Field and actors

Playfield half-width 13, formation top y = 7.6, player line y = -8.6, shield line y = -5.6 (game.lua:2-7). Formation is 11 columns × 5 rows, column spacing 1.85, row spacing 1.45 (game.lua:5-6), kinds by row: squid, crab, crab, octo, octo (game.lua:20), worth 30 / 20 / 10 (game.lua:10, 13, 16).

## Stage flow

`menu` (attract bobbing, game.lua:606-611) → `play` (wave intro 1.6 s, then marching starts, game.lua:225, 444-457) → wave clear banner 2.0 s → next wave with fresh shields (game.lua:527-539) → `over` when the last life is lost (game.lua:438-439).

## Player actions

- Move left/right with arrows or A/D at 9.5 u/s, clamped to ±(13 - 0.8) (game.lua:426-428).
- Fire with Space, Up or W; only one player bullet may exist at a time (game.lua:431-435, 333-334). The bullet travels up at 22 u/s (game.lua:467).
- P or Escape pauses; O or Tab opens settings from menu/pause (game.lua:561-603, 629-631).
- 3 lives (game.lua:269); no extra-life award.

## Formation movement

- Step interval `max(0.035, (0.05 + 0.75 * alive/55) * (1 - min(wave-1,5) * 0.06))` seconds (game.lua:394). It therefore accelerates as invaders die and as waves rise, and never goes below 35 ms.
- Each step moves 0.32 sideways, or on hitting the field edge reverses direction and drops 0.45 (game.lua:404-409). The step interval is per formation, not per invader.
- Invaders descending through the shield line erode a shield cell (game.lua:417). If an invader reaches `PLAYER_Y + 0.3`, `G.invaded` is set; the next update sets `G.lives = 1` and then kills the player, leaving 0 lives (game.lua:418, 463). This is an immediate loss, not a life loss.

## Hazards and death

- Enemy bullets kill the player when `|x - player.x| < 0.75` and `|y - PLAYER_Y| < 0.45` (game.lua:508).
- `kill_player` (game.lua:366-374): player hidden, respawn 2.2 s, lives −1, all enemy bullets cleared.
- On respawn, if lives ≤ 0 the state becomes `over` (game.lua:439).
- Enemy fire cadence: `max(0.25, 1.1 - wave*0.1) * (0.5 + random())` seconds, capped at `3 + min(wave,4)` bullets (game.lua:496-499). Bullet speed `6.5 + min(wave,6)*0.4` (game.lua:363); half the bullets zigzag ±0.12 horizontally (game.lua:361, 503).
- Shields: 3 shields, each built from a 12-word shape; every cell has 2 hp (game.lua:173-201). A hit removes the struck cell and, with 35% probability, each neighbour within 0.45, decrementing hp (game.lua:311-331).
- Player bullets can also destroy enemy bullets within ±0.2 x and ±0.5 y (game.lua:488-491).

## What the player can kill and score

- Invaders: 30 / 20 / 10 points by kind (game.lua:10-20, 376-387).
- UFO: 50, 100, 150 or 300 points, chosen at random on the kill (game.lua:480-486).
- Enemy bullets: destroyed for no score (game.lua:488-491).
- UFO appears when its timer expires and more than 7 invaders are alive, crosses at 5.5 u/s, then leaves and resets its timer to 20-30 s (game.lua:512-525). Initial timer 15-25 s (game.lua:281), 18 s in the constructor (game.lua:170).

## Timers

| Timer | Value | Cite |
|---|---|---|
| Wave intro (no marching, no enemy fire) | 1.6 s | game.lua:225, 444-457 |
| Player respawn | 2.2 s | game.lua:367 |
| Wave-clear banner | 2.0 s | game.lua:529 |
| UFO initial / repeat timer | 15-25 s / 20-30 s | game.lua:281, 484, 524 |
| Enemy fire interval | 0.25-1.1 s scaled by wave | game.lua:498 |

No freeze, slow or invulnerability effect exists; the player is simply not updated during the wave intro, and enemy fire is suppressed then too (game.lua:444-457).

## Jev attach (game.lua:837-856)

`port = 9103`, `id = "neon_invaders"`. `playing()` is `state == "play"` **or `"pause"`**; `terminal()` is `state == "over"` (game.lua:841-846). No `busy()` hook.

### observe() fields (game.lua:768-781)

- `player_x`
- `lives`
- `score`
- `invaders` — up to the 5 live invaders nearest the player, each `{x, y}` in world space (game.lua:746-766, 773).
- `shot` — whether a player bullet exists.
- `shot_x`, `shot_y` — present only while `shot` is true.

### action ids (game.lua:812-821)

Intended: `"right"` when `aim_dx() > 0.6`, `"left"` when `< -0.6`, else `"stop"`. **As written this call fails in normal play.** `aim_dx` (game.lua:783-800) iterates the invader list and reads `iv.x` and `iv.y`, but invader records only have `ox`, `oy`, `hw`, `hh`, `col`, `row`, `kind` (game.lua:213-215) and are positioned through `inv_pos(iv)` using `formation.x/y` (game.lua:309). On the first live invader `ax` is set to `iv.x`, i.e. `nil`, so `return ax - player.x` raises "attempt to perform arithmetic on a nil value". The only paths that avoid it are: no live invaders (`ax` stays `player.x` → `stop`) and an active UFO, where `aim_dx` returns `ufo.x - player.x` first (game.lua:784-786).

`driver.lua` wraps the observe closure in `pcall` and turns the error into `{ok = false, error = {code = "callback_failed", ...}}` (driver.lua:111-115). So while Jev owns a running match with at least one live invader and no UFO, `game_observe` returns `callback_failed` and no legal action is ever available; `game_act` also calls `observe()` first (driver.lua:181-184), so acting fails the same way.

### apply(id) (game.lua:802-810)

Clears all three holds first, then:
- `"left"` → `vkeys.Left = true`
- `"right"` → `vkeys.Right = true`
- any other id → no direction
and in every case sets `vkeys.Space = true`, so the gun fires whenever a bullet slot is free. Holds persist; `move` is read every frame in `update_play` (game.lua:426-432).

## Jev cannot see

- Enemy bullets: count, positions, zigzag, speed — the only thing that can kill it (game.lua:341-364, 500-510).
- Shield cells and their hp, so it cannot judge cover (game.lua:311-331).
- The UFO: `observe` never lists it even though `aim_dx` prefers it (game.lua:480-486, 768-781, 783-786).
- Formation offsets, direction, next step timing, and how close the formation is to the shield or player lines (game.lua:390-420).
- Invader row/kind/point value and total alive count; only 5 nearest positions are given, without ids (game.lua:746-766).
- Wave number, enemy fire cadence, and the remaining respawn timer (game.lua:394, 439, 498).
- That `playing()` is also true while paused (game.lua:841-843): actions can be applied into a paused match where they have no effect until resume.
