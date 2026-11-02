# Arrow Out

A tap-to-clear arrow puzzle for PhasmaEngine, built with runtime UI and Lua.
Each board is a grid of bent arrows. Tap an arrow and it slides out head-first.
It leaves only if nothing is in front of its head. Otherwise it bumps the first arrow in the way and you lose one of three hearts.

## Run

`run.cmd`, or `powershell -File run.ps1 [-Api vulkan|dx12]`. It finds a sibling `PhasmaEngine`
Release `PhasmaPlayer.exe` (or uses `PHASMA_ENGINE`) and runs a private copy from `%LOCALAPPDATA%\PhasmaGames\ArrowOut`.

| Input | Action |
| --- | --- |
| Left click | Slide the arrow under the cursor |
| H / HINT | Highlight an arrow that can leave |
| R / RESTART | Restart the level |
| Enter / Space | Next level or retry from the result card |
| PgUp / PgDn | Skip to the next or previous level |
| Esc / SETTINGS | Settings menu (volume, mute, screen shake, FPS counter) |
| M | Mute |

The game saves the furthest level reached in `Assets/Save/arrowout_level.txt` and resumes there.
The settings menu is the shared `Scripts/Lib/settings_menu.lua` used by the Arcade games (unchanged copy). Arrow Out drops its bloom, ambient occlusion and particles rows, which do nothing in a flat 2D game. It saves to `Assets/Save/settings.cfg`.

## Levels

`Assets/Scripts/arrow_rules.lua` generates every level from its number, so the same number always gives the same board.
The grid grows every two levels, up to 18x24.
The picture cycles through Square, Diamond, Heart, Circle, House, Cross, Ring and Hourglass.
Arrows grow longer as the levels advance.

Every level can be solved. The generator places arrows one at a time, and each new arrow's exit path must be clear of every arrow placed before it.
Removing arrows in the reverse order therefore always works.
After that, the generator grows arrows backwards from their tails into empty cells, as long as the new cell is not on the exit path of a later arrow.
Removing an arrow never blocks another, so the board has no dead ends. Every lost heart comes from a wrong tap.
A wrong tap costs one heart per arrow and blocker: tapping the same arrow into the same arrow again only bumps.

## Files

- `Assets/Scripts/arrow_rules.lua`: pure rules and generator, with no engine calls
- `Assets/Scripts/arrowout.lua`: runtime-UI view, animation and input. The scene's `on_play` script.
- `Assets/Scripts/Lib/settings_menu.lua`: shared settings menu, copied unchanged from the Arcade games
- `tools/make_assets.py`: arrowhead PNGs and synthesized WAV effects (needs PIL)
- `tests/rules_test.lua`: `luajit tests/rules_test.lua` from this folder. Pool test `arrowout-rules`.
