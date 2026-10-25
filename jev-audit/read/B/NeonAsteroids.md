# NeonAsteroids

Entry: `Arcade/NeonAsteroids/run.ps1` starts `Scenes/main.pescene` (run.ps1:29); the scene loads `Assets/Scripts/game.lua`, which loads `Scripts/jev_auto.lua` (game.lua:976-986) and ends with `hooks{update}` (game.lua:1017). `Scripts/gamekit/driver.lua` is present and byte-identical across the Arcade games; `jev_auto.lua` requires it (jev_auto.lua:9), and its `observe` wrapper is `pcall`-protected (driver.lua:111-167).

## World

Vector playfield on an orthographic camera of size 36, so half-height `HH = 18` and half-width `HW = 18 * aspect` (game.lua:55-60). Everything wraps on both axes (game.lua:120-123); distances use wrapped deltas (game.lua:124-129).

## Ship

- State: x, y, vx, vy, angle, alive, inv, respawn, hyper (game.lua:204).
- Turn 4.6 rad/s (game.lua:630-631). Thrust adds 20 u/s² (game.lua:634). Speed is capped at 22 u/s (game.lua:639) and damped by `0.55^dt` per second, i.e. gentle friction (game.lua:640-641).
- Fire adds `cos/sin * 30` to the ship velocity, life 1.05 s, at most 4 player bullets alive (game.lua:646-649, 297).
- Hyperspace on Left Shift, Right Shift or H (game.lua:653): ship is hidden for 0.6 s, teleports to a random point, and on exit dies with probability `0.04 + min(#rocks,30) * 0.004` (game.lua:521-528, 606-613).
- Spawn/respawn invulnerability 2.5 s (game.lua:435). Respawn waits 2.5 s, then waits until no rock is within squared distance 36 of the centre (game.lua:494, 616-622).
- 3 lives at start; an extra ship at each 10,000 points, threshold rising by 10,000 (game.lua:324, 368-372, 444).

## Rocks

- Three sizes: radius factor 3.1 / 1.65 / 0.85, points 20 / 50 / 100 (game.lua:236-237). Collision radius is `SIZES[size] * 0.92` (game.lua:270).
- A destroyed rock splits into two of the next size down, inheriting 0.4 of the parent velocity plus a random speed (3-5.5 for size 2, 4.5-8.5 for size 1) and `min(wave,8) * 0.15` (game.lua:470-476). Size 1 does not split.
- Spawn speed for a fresh rock: size 3 1.5-3.2, size 2 2.8-5.5, size 1 4.5-8 (game.lua:268).

## Waves and score

- Wave 1 spawns `min(11, 3 + wave)` rocks of size 3, placed away from the ship and pushed to an edge (game.lua:420-428).
- A wave ends when no rocks and no saucer are alive; after a 2.0 s delay the next wave starts (game.lua:863-866). There is no win condition.
- Score: 20/50/100 per rock size when the player's bullet or the ship's collision destroys it (game.lua:467, 697, 708); 200 for a big saucer, 1000 for a small one (game.lua:506). A rock killed by a saucer bullet or a saucer collision awards nothing (game.lua:697, 734).
- Extra ship every 10,000 points, banner `EXTRA SHIP` (game.lua:368-372).
- High score saved to `Save/asteroids_hiscore.txt`, but only when Jev is not the assisted player (game.lua:332-334, 406, 492).

## Saucers

- First spawn timer `rr(14,22) - min(wave,6)`, then `rr(10,18) - min(wave,6)` after a kill (game.lua:430, 507) or `rr(8,16)` after it leaves (game.lua:737).
- Small saucer (`kind 2`) if score > 40,000, or score > 10,000 with 50% chance, or wave ≥ 3 with 30% chance; otherwise big (game.lua:510-511).
- Speed 5.0 (big) / 7.5 (small) across the screen; vertical direction changes every 0.8-2.2 s (game.lua:515, 717-718). It leaves after travelling 2 × HW (game.lua:737).
- Fires every 1.1 s (big) or 0.85 s (small) at speed 20. The big saucer fires in a random direction; the small one aims at the ship with error `max(0.04, 0.35 - score/100000)` (game.lua:719-729).
- A saucer can be destroyed by a player bullet inside `saucer.rad` (1.1 small, 1.9 big) (game.lua:517, 700); it is also destroyed by colliding with a rock (game.lua:732-735) or the ship (game.lua:710).

## Hazards and death

- Hostile bullet within 0.9 of the ship while `inv <= 0` (game.lua:701).
- Ship colliding with a rock inside `rock.rad + 0.7`: the rock is destroyed for points and the ship dies (game.lua:704-709).
- Ship colliding with the saucer inside `saucer.rad + 0.7`: both die; the saucer gives points (game.lua:710).
- Hyperspace exit roll (game.lua:611).
- `kill_ship` (game.lua:479-496): decrements `lives`; at 0 the state becomes `over`; otherwise `respawn = 2.5`.
- The player can kill rocks, big and small saucers, and nothing else. Hostile bullets are not shootable (they are only removed by lifetime, rock or ship collision).

## Timers

| Timer | Duration | Cite |
|---|---|---|
| Spawn invulnerability | 2.5 s | game.lua:435 |
| Hyperspace invisibility/dead time | 0.6 s | game.lua:525 |
| Respawn delay | 2.5 s | game.lua:494 |
| Bullet life (player / hostile) | 1.05 / 1.1 s | game.lua:297 |
| Wave-start banner | 2.2 s | game.lua:359 |
| Between-wave delay | 2.0 s | game.lua:865 |
| Game-over input lock | 1.5 s | game.lua:874 |
| Saucer fire (big / small) | 1.1 / 0.85 s | game.lua:721 |

No freeze or slow effects. Heartbeat sound interval decays from 1.0 s by 0.012 per beat, floor 0.25 s (game.lua:326, 858-861); audio only.

## Jev attach (game.lua:988-1014)

`port = 9105`, `id = "neon_asteroids"`. `playing()` is `state == "play"`; `terminal()` is `state == "over"` (game.lua:992-997). `busy()` is `ship.hyper > 0`, i.e. true during the 0.6 s teleport (game.lua:999-1001). `reset(seed)` seeds RNG, clears holds and calls `new_game` (game.lua:1008-1012).

### observe() fields (game.lua:926-939)

- `ship_angle` — heading normalised to (-π, π] (game.lua:928).
- `speed` — magnitude of ship velocity (game.lua:929).
- `nearest_rock_angle` — angle from the ship to the nearest rock, using wrapped deltas; `0` when no rock exists (game.lua:893-923, 906-908).
- `nearest_rock_distance` — distance to that rock; `-1` when none (game.lua:923).
- `lives` — remaining lives (game.lua:936).
- `score` — current score (game.lua:937).

### action ids (game.lua:960-974)

Exactly one action is offered per reply:
- `"left"` when the angle error to the nearest rock is > 0.28 rad;
- `"right"` when it is < -0.28 rad;
- `"thrust_fire"` when the error is within ±0.28, or when no rock exists.

### apply(id) (game.lua:941-958)

Clears all four holds and the hyperspace pulse, then sets one of them:
- `"left"` → `hold.left` and `hold.fire`
- `"right"` → `hold.right` and `hold.fire`
- `"thrust_fire"` → `hold.thrust` and `hold.fire`
- any other id → no hold; the reply only clears the previous one.

Holds persist until the next `apply`, so a single reply keeps steering, thrusting and firing at the fixed auto-fire cadence until replaced. There is no action for hyperspace, pause or a discrete shot.

## Jev cannot see

- Every rock except the single nearest one; no rock size, velocity or count, so the splitting chain and the wave-end condition are invisible (game.lua:893-923, 926-939).
- The saucer: presence, kind, position, travel, and the 200/1000-point value (game.lua:509-519, 713-747).
- Hostile bullets and their positions; the only death sources it can react to are unseen (game.lua:701).
- The ship's own position and velocity direction — only heading and scalar speed (game.lua:926-939).
- Invulnerability, respawn countdown, hyperspace cooldown/availability, and the fact that `busy` means "in hyperspace" (game.lua:435, 494, 999-1001).
- Wave number, between-wave delay, and progress to the next extra ship (game.lua:324, 368-372, 863-866).
- Whether the ship is currently alive or respawning; observe keeps returning the last death position and current lives.
