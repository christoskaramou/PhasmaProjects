# PongRemix

Entry: `Arcade/PongRemix/run.ps1` starts `Scenes/main.pescene` (run.ps1:29); the scene loads `Assets/Scripts/game.lua`, which loads `Scripts/jev_auto.lua` (game.lua:823-824) and registers `hooks{update}` (game.lua:1087). `Scripts/gamekit/driver.lua` is present and byte-identical to the other Arcade games; its `observe` wrapper is `pcall`-protected (driver.lua:111-167). There is also a `G.sim(sec, keys)` automation helper (game.lua:1090-1095).

## Court and constants

Half-width 16, half-height 10, paddle line x = ±14.2, paddle height 2.6, ball radius 0.38, win at 11 with a 2-point margin, ball speed starts 14 and caps at 26 (game.lua:39-44, 43, 44, 478).

## Stage flow

`title` (attract mode, both paddles auto-track) → `serve` → `play` → on a point back to `serve`, or `over` when the win condition is met (game.lua:976-1008, 461-491). A new game starts in `serve` with a random serve direction (game.lua:719-729).

## Player actions

- Player 1: W/S, Up/Down, or the mouse in 1-player mode; key acceleration 160 units/s² up to 22 units/s, release decay `exp(-14dt)`, mouse follow rate 22 (game.lua:541-569).
- Serve: left click or Space, but only after `serve_t > 0.2` s (game.lua:996-1002).
- P/Escape pauses, M mutes (game.lua:1052, 1059-1061).
- Player 2 uses Up/Down (game.lua:542-543).

## Ball physics

- Serve: ball starts at (0,0), speed 14, direction ±1 with a launch angle uniform in ±0.35 rad (game.lua:414-423).
- Paddle hit: offset from paddle centre clamped to ±1, mapped to ±0.85 rad; ball speed +0.85 (capped at 26); paddle velocity adds `0.25 * p.vy` to vy; ball is pushed out of the paddle (game.lua:435-457).
- Top and bottom walls reflect the y velocity (game.lua:497-504).
- A ball past |x| > 17 scores for the other side (game.lua:526-529).

## Hazards, win and lose

- No hazards, pickups or timers other than the serve gate; the only "damage" is conceding a point.
- A point is scored when the ball passes a goal line; the scorer gets one point (game.lua:461-462).
- Win: `score >= 11` and `abs(score1 - score2) >= 2`, then `over` and the winner is recorded (game.lua:478-487). There is no lose condition besides the opponent reaching that state; in 1P the opponent is the AI (game.lua:994).
- The high score is the total points of the match, saved only when Jev is not the assisted player (game.lua:481-485).

## AI

`ai_target` predicts the ball's y at the paddle with wall reflections (`predict_y`, up to 80 steps of 0.05 s, game.lua:387-401), then adds random error `±(1 - skill) * PADDLE_H * 0.25`; `G.ai_skill` is 0.78 in a new game (game.lua:403-411, 724). The AI paddle moves toward that target at up to 22 * 1.1 units/s (game.lua:535-540). When the ball is stuck or moving away, the AI drifts toward y = 0 (game.lua:404-406).

## Jev attach (game.lua:825-911)

`port = 9129`, `id = "pong_remix"`. `playing()` is `play` or `serve`; `terminal()` is `over` (game.lua:829-834). `busy()` is always false (game.lua:838-840). `reset(seed)` seeds RNG, clears holds, starts a 1-player game, and primes the human-key sampler (game.lua:899-905).

### observe() fields (game.lua:842-851)

- `paddle_y` — player 1 paddle y.
- `ball_x`, `ball_y`, `ball_vx`, `ball_vy`.
- `score_left`, `score_right`.

### action ids (game.lua:853-867)

`gap = predict_y(-PADDLE_X) - PAD.L.y`, using the same wall-reflection predictor as the AI (game.lua:387-401, 854).

- `"serve"` when the ball is stuck and `|gap| <= 0.5` (game.lua:855-857).
- `"up"` when `gap > 0.15` (game.lua:858-860).
- `"down"` when `gap < -0.15` (game.lua:861-863).
- `"serve"` when the ball is stuck and neither of the above matched (game.lua:864-866). Because a stuck ball sits at y = 0, this branch is reached only when the paddle is already within 0.15 of the ball line but outside the 0.5 serve band, so in practice the first branch covers the stuck case.
- `"stop"` otherwise (game.lua:867).

Exactly one action is offered.

### apply(id) (game.lua:869-898)

- `"serve"`: only if the ball is stuck, clears W/S and any live Space pulse, then sets `pulse_arm`. `arm_pulse_frame` turns that into a one-frame virtual Space press once `serve_t > 0.2 s` (game.lua:788-803); the normal serve check then launches the ball (game.lua:1000-1001). If the ball is not stuck, this id does nothing.
- Any other id clears `pulse_arm` and any live Space pulse first.
- `"up"` → `G.vkeys.W = true`, `S = nil`.
- `"down"` → `G.vkeys.S = true`, `W = nil`.
- `"stop"` → both cleared.
- Unknown ids only clear the serve pulse; the movement holds are left as they were.

Up/down are holds and persist until replaced. `settle_input` clears W/S outside `play`/`serve` and releases the Space pulse (game.lua:805-817).

## Jev cannot see

- The AI paddle: its y, velocity and target are not exposed, so Jev cannot aim a return into space; only `score_right` is visible (game.lua:403-411, 842-851).
- Ball speed as a field; it is derivable from vx/vy, but the per-hit +0.85 ramp and the 26 cap are not exposed (game.lua:441).
- The serve gate and timer: `serve_t`, the 0.2 s lockout, and the fact that a serve request is armed rather than immediate are invisible (game.lua:788-803, 1000).
- Whether the ball is stuck: only inferable from `vx == 0 and vy == 0` (game.lua:426-431).
- Its own paddle velocity, which feeds `0.25 * p.vy` into the bounce (game.lua:445, 550).
- `G.ai_skill` and the AI's error band (game.lua:408-410, 724).
- Paddle height/width and the goal lines, so contact and scoring thresholds must be assumed (game.lua:41, 527-528).
- `busy` is hard-coded false, so a serve reply is never reported as pending (game.lua:838-840).
