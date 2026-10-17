# PITFALL! Remastered (PhasmaEngine)

## Controls
Arrows / WASD run & climb, Space jump / grab vine, Down release vine, P / Esc pause, Enter start / resume.

## Run on Windows

Like the other PhasmaProjects, this runs on the PhasmaEngine checkout beside this repo (`..\PhasmaEngine`).

- **Player:** double-click `run.cmd`, or run `powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1`. It copies the newest `PhasmaEngine\build*\Release\PhasmaPlayer.exe` build into `%LOCALAPPDATA%\PhasmaGames\<game>`, points its `phasma_settings.json` at this project's `Assets`, and launches with `--api vulkan --display 1`. The shared engine build is not modified.
- **Editor:** launch `PhasmaEditor.exe` (e.g. `..\PhasmaEngine\build-ninja-physics\Release`) and open this folder as the project, or set `"project_path"` in that build's `phasma_settings.json` to this folder's `Assets` (note: other tools share that file). The startup scene is `Assets/Scenes/main.pescene`.

Asset paths in scripts are Assets-relative. `shots/` holds screenshots from the Linux build.

## Playtest fixes (Oct 2026)
- Crocodiles: a closed mouth is always safe to stand on; only an open mouth (jaw zone at the croc's front) kills. Standable span matches the cooked mesh. Crocs made larger, brighter and pulled slightly forward so they read clearly in the pond.
- Meshes: zero-area triangles stripped from all sources (croc, Harry, log, rock, scorpion), recooked as single meshes; scene templates fixed (no more invisible sub-mesh 0).
- Terrain z-fighting: each grass/dirt block gets a tiny incremental depth offset (0.002 per block) so coplanar faces never fight.
- Hazard audit: pits, tar, shifting tar, quicksand, logs, fire, cobra, scorpion, ladders/holes and vine verified.
- Simulation step cap raised for low-FPS robustness (dt-based, frame-rate independent).
