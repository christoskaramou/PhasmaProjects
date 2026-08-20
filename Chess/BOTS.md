# Playing against a bot

**Implemented 2026-08-19 — route A.** Stockfish 18 runs as a child process and talks UCI over
pipes. Strength is a single **Elo** you set in the move panel: `Bot: on/off`, the colour it plays,
and an Elo field you scrub by dragging (5 Elo per pixel) or step with `-` / `+` (25 at a time).
From a script: `script.chess.bot(elo, "W"|"B")`, `script.chess.bot(0)` to turn it off.

Pieces:
- `Phasma/Runtime/Code/Script/Bindings/Process/ProcessBindings.cpp` — the `proc` Lua binding.
  One child at a time, executable must live under the project's `Assets/`, non-blocking
  `read_line()`. The child runs in a kill-on-close job object (Windows) / with `PR_SET_PDEATHSIG`
  (Linux), so killing the game reaps it — verified by force-killing the editor mid-game.
- `Assets/Scripts/chess/bot.lua` — the UCI state machine, polled once per frame.
- `Assets/Scripts/chess/grid.lua` — the 64 square highlights, grouped under one `ChessGrid` node.
- `Assets/Bots/stockfish.exe` — Stockfish 18, GPLv3, with `Copying.txt` and `SOURCE.txt`.

Verified: full games in the editor and in PhasmaPlayer, castling and captures through the bot's
moves, rewinding mid-search discards the stale `bestmove`, off/on leaves exactly one process,
and no orphan survives a force-kill.

## The blocker (what shaped the design)

`ScriptSystem.cpp:422` opens Lua with `base, math, string, table, coroutine` — **no `io`, no `os`**, and
there is no process or socket binding anywhere in `Phasma/Runtime/Code/Script/Bindings/`.
`fs.*` is `find / list / read / write` only. So a script **cannot** start or talk to an external
engine. Every route below is decided by that one fact.

## Routes

### A. C++ UCI binding — BUILT

Spawn `stockfish.exe` from the Runtime, talk UCI over pipes, poll replies per frame.

- Precedent to crib: `Phasma/Editor/Code/GUI/Agent/EditorToolCatalog.cpp:87` already does
  `CreatePipe` + `CreateProcess` + `STARTF_USESTDHANDLES`. It is one-shot and Editor-side; UCI
  needs it long-lived, bidirectional and in the Runtime so PhasmaPlayer gets it too.
- Lua surface as built is generic rather than chess-specific: `proc.start(path, args?)`,
  `proc.write(text)`, `proc.read_line()` -> `nil` when nothing is buffered, `proc.is_running()`,
  `proc.stop()`. UCI itself lives in `bot.lua`, so the engine learned nothing about chess.
- No FEN needed. `history` already stores from/to/promo per ply, so the position is
  `position startpos moves e2e4 e7e5 ...` — the exact format UCI wants.
- ~280 lines of C++. Two gotchas that cost time: the parent's pipe ends must be marked
  non-inheritable and the child's ends closed after `CreateProcess`, or reads never see EOF; and
  `read_line()` has to be drained in a loop each frame, because Stockfish emits dozens of `info`
  lines per search and one-per-frame backs the pipe up.
- `script.on_update` callbacks are called with **no arguments** in this engine — only node scripts
  receive a delta. The blunder delay counts frames for that reason.

### B. External sidecar — zero engine change, dev only

A python-chess process drives `script.chess.move()` through the player's MCP port. Works today,
but the bot lives outside the game, so it is a testbed, not a shippable feature.

### C. Pure-Lua search — no dependency at all

Negamax + alpha-beta + piece-square eval on the existing `R.make` / `R.unmake` / `R.legal_moves`.
Maybe 250 lines. Realistic ceiling is club strength on a Lua interpreter inside a frame budget —
fine for the low and middle rungs, cannot reach "very high". Would need iterative deepening across
frames to avoid a hitch.

## Elo control (Stockfish)

- `UCI_LimitStrength true` + `UCI_Elo <n>`, range **1320–3190**, calibrated at 120s+1s against
  CCRL 40/4. It overrides `Skill Level`.
- 1320 is the floor because it is what `Skill Level 0` scores — random play is already ~1200, so
  the engine cannot go lower. Below that you weaken it yourself: `MultiPV` a handful of candidates
  and pick a worse one with a rating-dependent probability, or blunder-inject.
- Weakening works by randomly biasing the scores of the slightly-worse candidates, so it plays
  a normal move then drops a piece — it does not feel like a weak human.
- Search is **`go depth`**, not a time cap. Stockfish picks the weak move at
  `depth = 1 + floor(skill(Elo))` and then freezes it — extra seconds on a fast PC do not
  raise Elo, they just wait, and the same seconds on a phone can miss that depth. Same depth
  on every device; wall-clock varies. **Max is the exception**: unlimited strength has no
  calibration to hold, so it searches by time (`go movetime 3000`) and takes whatever depth
  the hardware gives.

## Licence

Stockfish is GPLv3. Shipped as a **separate executable** talked to over pipes it is mere
aggregation, so the game stays closed — that is what makes route A clean. Linking it as a library
would pull the game under GPLv3. Ship the binary plus its source offer.

## If "human-like" matters more than "correctly rated"

Maia (Leela-derived, trained on human games rather than self-play) ships 9 weights for Elo
1100–1900 and matches human moves >50% of the time. It needs an lc0 binary + weights, so it is the
same plumbing as route A with a bigger payload — worth it only if the low levels feeling human is
a goal.

## Strength as built

One number, 400-3190, and everything else is derived from it:

| asked Elo | what is sent | blunder chance | search |
|---|---|---|---|
| 400 | UCI_Elo 1320 | 80% | depth 1 |
| 900 | UCI_Elo 1320 | 46% | depth 1 |
| 1320 | UCI_Elo 1320 | — | depth 1 |
| 1500 | UCI_Elo 1500 | — | depth 2 |
| 2000 | UCI_Elo 2000 | — | depth 5 |
| 3000 | UCI_Elo 3000 | — | depth 14 |
| 3190 | **UCI_LimitStrength false** | — | movetime 3000 ms |

### How much to trust the number

**1320–3189: this is Stockfish's skill-limited Elo, hardware-independent.** The slider still
sends `UCI_Elo`, which Stockfish 18 maps to a skill level (cubic in `search.h`, clamped 0–19)
and a pick at `depth = 1 + floor(skill)`. We search exactly to that depth so a fast PC and a
phone produce the same MultiPV set before the handicap fires. It is still CCRL-shaped, not
FIDE, and it has not been verified by playing a match.

A wall-clock cap cannot do this: more seconds on a PC are wasted after the pick, and the same
seconds on Android can miss the pick depth and play a different game.

**The top of the range is not "3190".** `UCI_Elo`'s maximum of 3190 is a cap on the *handicap*,
not on Stockfish. Stockfish 18 sits around **4103 on CCRL 40/4**. The top of the slider sends
`UCI_LimitStrength false` and the field says `Max (full strength)`, searching 3 seconds by
wall-clock. Measured on this machine from a real middlegame: `go depth 20` finished in **541 ms**
(which read as "not thinking at all"); 3000 ms reaches **depth ~27**. Max is deliberately the one
rung whose strength scales with hardware. The bot never ponders — its play searches run only on
its own turn — but the hint button and the eval bar DO run idle-time analysis searches in the
same process, so the shared hash table can be a little warmer than play-searches alone would
leave it. Its hash also persists across moves within a game, so later searches start warm.

Below 1320 the field shows a `*`: Stockfish itself is pinned at its floor and the extra weakness
comes from a blunder roll — a uniformly random legal move played after a short beat. Picking the
2nd/3rd best from a MultiPV search would read as far more human and is the upgrade path.

The Elo field is a drag-scrub, not a text box, because runtime_ui has no text entry and its Number
widget cannot be read back — `set_quad{draggable = true}` plus `get_state().drag_delta_x` is the
only numeric input the UI layer offers. `drag_delta_x` is the TOTAL travel since the press, so the
value is snapshotted on `drag_started` and the delta added to it, never accumulated.

Not done: the packed `game.pepak` build cannot spawn an exe from inside the pack, so Stockfish has
to ship alongside it — which is what GPLv3 wants anyway.

## Sources

- [UCI Protocol and Stockfish Commands](https://official-stockfish.github.io/docs/stockfish-wiki/UCI-Protocol-and-Stockfish-Commands.html)
- [Stockfish FAQ](https://official-stockfish.github.io/docs/stockfish-wiki/Stockfish-FAQ.html)
- [Why is UCI_Elo's min 1350?](https://github.com/official-stockfish/Stockfish/discussions/4434)
- [python-chess UCI engine docs](https://python-chess.readthedocs.io/en/latest/engine.html)
- [Introducing Maia: a Human-Like Chess Engine](https://www.maiachess.com/blog/maia-v1)
