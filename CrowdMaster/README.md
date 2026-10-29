# Crowd Master

Crowd Master is a crowd-runner in the style of Count Masters, written in Lua for the Phasma Engine. You steer a running stickman crowd through gates, traps and terrain. Along the way you smash red crowds, then climb a trophy staircase or topple a king.

## Run on Windows (PC)
Location: `C:\Users\Christos\repos\PhasmaProjects\CrowdMaster`. The engine checkout is `..\..\PhasmaEngine` (`C:\Users\Christos\repos\PhasmaEngine`) and needs a Release build containing `build*\Release\PhasmaPlayer.exe`. You can override it with `$env:PHASMA_ENGINE`.
- `.\run.cmd`, or `powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 [-Api vulkan] [-Display 1]`. This copies the Player into `%LOCALAPPDATA%\PhasmaGames\CrowdMaster` and points it at `project\Assets`, so the engine build's own `phasma_settings.json` is never touched.
- In the editor, open `project\phasma_project.json`.
- Rebuilding `game.lua` from `src\` uses `tools/build_lua.sh` (bash or Git Bash). The Linux-only box launch, screenshot and mesh-cook scripts are not included in the PC copy.

## Run (box)
- `./dev.sh` starts the Player headless. It runs under xvfb-run, with the MCP on port **9155**, and waits for `[CM] ready`.
- `./run.sh` starts the Player in the foreground. `./stop.sh` stops only this game's Player (by PID file).
- `./lua.sh 'code'` runs Lua in the live game. `./shot.sh name` saves `/workspace/crowdmaster_shots/name.png`.
- `tools/autoplay.sh "1 2 3" [greedy|bad]` lets a bot play levels and prints the results.
- **Build:** `tools/build_lua.sh && python3 tools/check_lua.py`. This concatenates `src/0*.lua` into `project/Assets/Scripts/game.lua`. Meshes come from `tools/gen_meshes.py` and are cooked with `tools/cook_all.sh`.

## Controls
| Action | Mouse | Keyboard |
|---|---|---|
| Steer | Drag | A / D or ← / → |
| Shield Bubble | Shield button | Space |
| Pause | Pause button | Esc / P |
| Menus | Click | Arrows / W A S D to move focus, Enter or Space to press, Esc = Back |
| Army Board | Drag a unit onto an equal one to merge; click two units | Arrows + Enter |

## Content
- **12 levels in 4 worlds:** Meadow Isles, Sunbaked Canyon, Frost Bay and Ember Coast. Every 3rd level ends in a king boss; the others end on a trophy staircase.
- **Gates:** +N, −N, ×N, ÷N and Merge. There are also gate traps: trick (scramble/flip), timed lamp gates, a × gate followed by a trap, and guarded gates.
- **Traps:** spin bars, saw lanes, hammers, crushers, spike rollers, pits and narrow bridges.
- **Terrain:** oil, ice, mud, gravel and brambles.
- **Assists:** breakable cages of captives, air drops and a golden giant ally.
- **Merge tiers:** Pawn → Brute → Giant, plus orange Boss Breakers.
- **Economy:**
  - Coins and gems.
  - Coin upgrades: Starting Crowd, Gate Power, Trap Armor, Run Speed, Clash Might and Treasury.
  - Gem powers: Shield, Magnet, Boss Breakers and Lucky Eye.
  - An army merge board.
  - The best score and stars per level, and a persistent save in `project/Assets/Save`.
- See **FUN.md** for the design research and tuning log.

## Credits
- **UI font:** Lilita One by Juan Montoreano, SIL Open Font License 1.1 (shipped as `RuntimeUi.ttf`).
