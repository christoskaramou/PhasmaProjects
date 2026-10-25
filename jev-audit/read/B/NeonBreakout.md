# NeonBreakout

Entry: `Arcade/NeonBreakout/run.ps1` starts `Scenes/main.pescene` (run.ps1:29); the scene loads `Assets/Scripts/game.lua`, which loads `Scripts/jev_auto.lua` (game.lua:1301-1302), registers `hooks{update}` (game.lua:1358) and exposes a separate deterministic `G.sim(sec, keys)` for tooling (game.lua:1361-1366). `G.sim` is not used by Jev.

## Field and constants

14 columns × 8 rows of brick cells, cell 2.0 × 0.8, inner half-width 14, top wall y = 15, top brick row centre y = 11.6, paddle line y = -13, ball lost below y = -16.5, ball radius 0.36 (game.lua:44-52). x runs -14..14, y up. Level layouts are the 5 `LEVELS` entries, cycled (game.lua:221-237, 328).

## Stage flow

`levelintro` (bricks drop in; serve after all landed and 1.0 s, game.lua:1246-1249) → `serve` → `play` → on clear `clear` (2.6 s, +100 × level bonus, then next level, game.lua:1260-1274) or on ball loss back to `serve` / `over`.

## Player actions

- Move paddle with the mouse (after mouse motion is detected) or Left/Right/A/D keys (game.lua:1099-1113). Paddle width eases toward its target at rate 28 (game.lua:1115).
- Left click or Space launches the stuck ball once the serve has lasted > 0.25 s (game.lua:1154, 1157).
- The same click/Space fires lasers while the laser power is active (game.lua:1163-1167).
- P or Escape pauses (game.lua:1251-1253); M mutes (game.lua:1236).

## Bricks and scoring

Slot point values (game.lua:220): red 7, orange 5, green 3, yellow 1, cyan 2, magenta 4, violet 6, white 8, steel 10, gold 0. Rows of the classic wall: two red, two orange, two green, two yellow (game.lua:222-224).

- Steel (`S`): 2 hp, cracks to the damaged mesh on the first hit and is destroyed on the second (game.lua:335, 601-609).
- Gold (`G`): unbreakable, only sparks and flash (game.lua:596-600); excluded from `breakable_left` (game.lua:343).
- Destroying a brick awards its points (game.lua:613) and, on non-classic stages only, has a 15% chance to drop a power-up (game.lua:633).
- Laser kills do not count toward the classic hit-based speed-ups (game.lua:616).

## Ball speed

`BASE_SPEED = 15`, tier multipliers 1.0 / 1.14 / 1.28 / 1.44 / 1.6, plus 6% per level above 1; `slow` multiplies by 0.68 (game.lua:469-476). Tier rises on the 4th hit, the 12th hit, the first destroyed orange brick (slot 1) and the first destroyed red brick (slot 0), capped at tier 4 (game.lua:481-488, 614-621). A lost ball drops the tier by one (game.lua:1058).

## Ball physics

- Sub-stepped at `ceil(speed*dt / (BALL_R*0.5))` steps to avoid tunnelling (game.lua:727-729).
- Side and top walls reflect; the first top-wall contact sets `G.shrunk` and halves the paddle target width from 3.6 to 1.9 (game.lua:672-678, 375, 1013). `G.shrunk` is cleared on a lost ball and on a new wall (game.lua:1020, 1057).
- Paddle bounce angle: offset from paddle centre scaled by 62°, plus up to ±0.18 rad from paddle velocity; direction is normalised with a minimum |vy| of 0.28 so the ball never travels nearly horizontally (game.lua:681-688, 653-660).
- Launch angle comes from the serve offset (±0.5 rad) plus paddle velocity (game.lua:661-666).
- Brick collision is circle vs AABB with half extents 0.93 × 0.35 and picks the shallower penetration axis to reflect (game.lua:652, 694-713).
- With the `fire` power, a non-gold brick is destroyed without a bounce (pierce) (game.lua:701-709).

## Hazards, lose

- A ball below `BOTTOM` is removed; when no balls remain and state is `play`, `lose_ball` runs (game.lua:731-734, 1259).
- `lose_ball` decrements lives; at 0 the state is `over` (game.lua:1044-1055). 3 lives at the start (game.lua:447, 1028); `life` power-up adds one, capped at 9 (game.lua:549-550).
- No invulnerability, freeze or stun.

## Power-ups (non-classic walls only)

Drops fall at 6.5 u/s and are caught when within `PAD.w/2 + 0.6` of paddle x and near the paddle line (game.lua:556-565). Pickup awards 50 points (game.lua:537).

| Kind | Effect | Duration | Cite |
|---|---|---|---|
| WIDE | paddle target width ×1.6 | 15 s | game.lua:497, 1095 |
| MULTI | spawns 2 extra balls at ±0.5 rad | instant | game.lua:538-548 |
| SLOW | ball speed ×0.68 | 12 s | game.lua:499, 474 |
| LASER | click/Space fires two bolts, 0.28 s cooldown | 12 s | game.lua:500, 579-589, 1163-1167 |
| FIRE | ball pierces non-gold bricks, orange colour | 8 s | game.lua:501, 701 |
| +1 BALL | one extra life | instant | game.lua:502, 549-550 |

Drop kind weights: wide < 0.22, multi < 0.40, slow < 0.58, laser < 0.76, fire < 0.93, else life (game.lua:519-520). Lasers travel at 34 u/s and die on the first brick they meet (game.lua:635-646).

## Timers

| Timer | Value | Cite |
|---|---|---|
| Serve lock before launch | 0.25 s | game.lua:1154 |
| Level intro before serve | 1.0 s after bricks land | game.lua:1249 |
| Wall-clear hold | 2.6 s | game.lua:1274 |
| Laser cooldown | 0.28 s | game.lua:1166 |
| Power-up durations | 15 / 12 / 12 / 8 s | game.lua:497-501 |

## Win and lose

- A wall is cleared when `breakable_left <= 0` (gold bricks do not count) (game.lua:592, 343); bonus 100 × level and the next wall loads (game.lua:1260-1274). The 5 layouts cycle, so there is no final win.
- Lose when lives reach 0 (game.lua:1047-1049).

## Jev attach (game.lua:1303-1350)

`port = 9107`, `id = "neon-breakout"`. `playing()` is `levelintro`, `serve`, `play` or `clear`; `terminal()` is `over` (game.lua:1285-1288, 1308-1310). No `busy()` hook is supplied.

### observe() fields (game.lua:1317-1328)

`observe_ball` picks the ball with the lowest y (game.lua:1290-1299), then returns:
- `paddle_x`
- `ball_x`, `ball_y`, `ball_vx`, `ball_vy` (all `0` when no ball exists)
- `lives`
- `score`

### action ids (game.lua:1329-1343)

- `"launch"` when the observed ball has zero velocity on both axes.
- `"right"` when `ball_x - paddle_x > 0.2`.
- `"left"` when that difference is < -0.2.
- `"stop"` when the difference is within ±0.2.

Exactly one action is offered.

### apply(id) (game.lua:944-960)

- `"launch"` → sets `launch_pulse`; it does not touch the holds. The pulse is turned into a virtual Space press on the next update and is held back until the serve timer exceeds 0.25 s (game.lua:973-984).
- `"left"` → `hold_left = true`, `hold_right = false`.
- `"right"` → `hold_right = true`, `hold_left = false`.
- `"stop"` → both holds false.
- Any other id falls through to `stamp_holds()` with the previous holds intact.

Holds are stamped into `G.vkeys.Left/Right` each frame (game.lua:922-933), so they persist until replaced.

## Jev cannot see

- The wall: no brick positions, slots/point values, steel hp, gold bricks, or `breakable_left` (game.lua:307-343).
- All balls except the lowest one; MULTI creates two extra balls that are invisible (game.lua:538-548, 1290-1299).
- Ball speed/tier, the slow effect, and the level (game.lua:469-476).
- Power-up capsules in flight and the remaining duration of WIDE/SLOW/LASER/FIRE (game.lua:449, 556-565).
- Paddle width, whether it has been halved, and the wide multiplier (game.lua:373-375, 677).
- That the ball is stuck only through zero velocity; the serve timer and launch gate are invisible (game.lua:1154).
- Laser cooldown and whether lasers are currently available (game.lua:1163-1167).
