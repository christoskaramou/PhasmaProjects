# PrismTetris

Entry: `Arcade/PrismTetris/run.ps1` copies `Assets` to a runtime folder and launches with `startup_scene = 'Scenes/prism_tetris.pescene'` (run.ps1:116-122). That scene loads `Assets/Scripts/prism.lua` (scene `scene_scripts.on_play`). `prism.lua` loads `tetris_rules.lua`, `prism_stage.lua`, `prism_board3d.lua`, `prism_hud.lua`, `prism_jev.lua`, `gamekit/driver.lua` and `tetris_agent.lua` (prism.lua:6-13).

**No `jev_auto.lua` is used and no `JevAuto.attach` exists here.** `prism_jev.lua` is only the wrapper that starts/stops `Bots/PhasmaGameDriver.exe` and parses its output (prism_jev.lua:1-8, 42-70, 100-139). The game exposes itself to Jev through `gamekit/driver.lua` via `Agent.attach` in `tetris_agent.lua` (prism.lua:441-452, tetris_agent.lua:269-382). `gamekit/driver.lua` is the same logic as the other Arcade games (309 lines; `observe` is `pcall`-protected at driver.lua:111-115, `act` checks session/state and legality at driver.lua:169-208).

Rules of the sim live in `tetris_rules.lua`; the driver adapter in `tetris_agent.lua`; the UI/scene in `prism.lua` and `prism_stage.lua` (stage has no gameplay, only camera/post/HUD layout: prism_stage.lua:1-28, 265-266).

## Board and pieces

10 wide × 22 tall with 2 hidden spawn rows; pieces spawn at x = 4, y = 1 (tetris_rules.lua:122-124, 111). Seven piece kinds with 4 rotations each (tetris_rules.lua:5-31); SRS wall kicks, separate I-piece table (tetris_rules.lua:34-54, 174-195). Randomiser is a shuffled 7-bag; 5 pieces are queued ahead (tetris_rules.lua:73-84, 140-142). Hold swaps the active piece and is available once until the next lock (tetris_rules.lua:221-231, 128-129, 297).

## Stage / level progression

- Level = `floor(lines / 10) + 1` (tetris_rules.lua:276).
- Gravity interval per level: `(0.8 - (level-1)*0.007)^(level-1)` s per row; at level ≥ 20 gravity is instant ("20G") (tetris_rules.lua:331-339, 348-349). Soft drop clamps the interval to 0.035 s (tetris_rules.lua:338).
- Lock delay 0.5 s with at most 15 resets from moves/rotations while grounded (tetris_rules.lua:151-156, 352-358).
- The mode machine is `ready` / `playing` / `paused` / `over` (prism.lua:46-53, 124-176).

## Player actions

- Left/Right or A/D move, with a 0.16 s initial repeat and 0.045 s thereafter (prism.lua:355-372, 358-369).
- Up/X or right click rotate clockwise; Z or left click counterclockwise; C or Shift hold; Space hard drop; Down/S soft drop (prism.lua:385-433).
- P or MENU pauses, R restarts, V starts a race, M mutes, F1 toggles motion (prism.lua:300-353).
- Soft drop awards 1 point per row; hard drop awards 2 per row (tetris_rules.lua:210-219, 319-329).

## Scoring

Line clears: 1/2/3/4 rows = 100/300/500/800 × level; a back-to-back tetris is ×1.5; combo adds `50 * combo * level` (tetris_rules.lua:261-278). Dropping adds 1 per soft-dropped row and 2 per hard-dropped row (tetris_rules.lua:216, 327, 367). The best score is saved only for unassisted solo play (prism.lua:81-89).

## Hazards, lose and win

- Top-out: the spawn does not fit (tetris_rules.lua:115) or every locked cell lies inside the two hidden rows (tetris_rules.lua:280-302) sets `game_over`.
- Solo: `game_over` on the player's board sets mode `over` (prism.lua:104-108, 231-234).
- Race: both boards start from the same seed; the first to top out loses, both in the same frame is a draw, and if the driver process stops the race ends with the driver's message (prism.lua:153-198). There is no other win condition.
- No invulnerability, freeze or slow effect.

## Timers

| Timer | Value | Cite |
|---|---|---|
| Lock delay | 0.5 s | tetris_rules.lua:352-358 |
| Lock resets | max 15 | tetris_rules.lua:151-156 |
| Soft-drop gravity floor | 0.035 s/row | tetris_rules.lua:338 |
| Horizontal repeat | 0.16 s then 0.045 s | prism.lua:358-369 |
| Agent input interval | 0.07 s | tetris_agent.lua:3, 327-340 |
| Driver stop grace after race | 3 s | prism_jev.lua:8, 182-195 |

## Jev attach (tetris_agent.lua:269-382; prism.lua:441-452)

`driver.attach` registers `id = "prism-tetris"` (tetris_agent.lua:353-354). In a race `options.game()` is the rival board and `options.apply` acts on Jev's seat (prism.lua:443-449). `reset(seed)` calls `new_game` (solo), then marks the state assisted/agent and returns `observe()` (tetris_agent.lua:365-371; prism.lua:450).

### observe() fields (tetris_agent.lua:287-325)

- `mode` — `state.mode`.
- `terminal` — `game.game_over or state.mode == "over"`.
- `score`
- `busy` — true while a chosen placement is still being executed (`placing(game)`, tetris_agent.lua:279-290).
- `observation`:
  - `board` — 20 strings, board rows y = 3..22, each 10 characters of piece letters or `.` (tetris_agent.lua:300-307).
  - `active` — the live piece table with `kind`, `rotation`, `x`, `y` (tetris_agent.lua:316).
  - `held` — piece kind or `"none"`.
  - `next` — the 5-piece queue.
  - `lines`, `level`, `can_hold`.
- `actions` — see below; the decision epoch is a string of mode/agent/busy/score/lines/level/held/can_hold/active plus the full board and queue, deliberately excluding the falling y (tetris_agent.lua:54-80).

### action ids (tetris_agent.lua:239-265)

`placement_1` … `placement_N`, one per distinct reachable landing, sorted by landing key. Each carries a numeric score and a description built from the placement (tetris_agent.lua:135-163, 255-264). Both normal placements and hold-then-place landings are included when `can_hold` (tetris_agent.lua:239-247).

### What act(id) does (tetris_agent.lua:372-378)

It does **not** move the piece directly. `act` sets `target = targets[id]` (asserting the id is known), records the current active piece, resets the input wait, and marks `state.assisted = true`, `state.agent = true`. Then `tick(dt)` (tetris_agent.lua:327-351), called from `prism.lua:415`, sends the first command of the shortest BFS route toward that landing every 0.07 s, re-planning from the piece's current position after gravity. Commands come from `{left, right, cw, ccw, down}` plus `hold` and a final `drop` (tetris_agent.lua:2, 110-122, 201-211). `options.apply` routes them to `apply_action(command, jev_seat)`, which enforces `state.mode == "playing"` and not `game_over` and returns false if the move is illegal (prism.lua:210-235, 447-449). If the piece can no longer reach the target the plan is abandoned (`target = nil`, tetris_agent.lua:340-346). A human key or a new game clears the plan (tetris_agent.lua:279-286).

## Jev cannot see

- Gravity timing, the current `gravity_timer`, `lock_timer`, `lock_resets` and whether a piece is grounded; only `busy` for its own plan (tetris_rules.lua:151-156, 341-373).
- The two hidden rows (board starts at y = 3) and therefore its own top-out risk at the spawn area; `active` coordinates include them but the board does not (tetris_agent.lua:300-307).
- The lines-to-next-level remainder and the exact gravity interval at the current level (tetris_rules.lua:276, 331-339).
- The scoring formula, combo, back-to-back state and drop points (tetris_rules.lua:261-278, 319-329).
- The rival board in a race: only its own `options.game()` is observed, so it cannot see the opponent's stack, score or top-out danger (prism.lua:443-445; judge at 178-198).
- `G.best`, mute/motion settings, and the race outcome fields (`winner`, `reason`) (prism.lua:46-53, 143-150).
- The queue beyond the visible five pieces and the shuffle state (tetris_rules.lua:73-84, 140-142).
