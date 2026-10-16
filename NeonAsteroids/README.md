# NEON ASTEROIDS (PhasmaEngine)

## Controls
A / D (or Left / Right) turn, Space thrust (Up / W also), left mouse click fire, Shift / H hyperspace, P / Esc pause, Q quit to title (paused), M mute, Enter start.

## Run on Windows

Like the other PhasmaProjects, this runs on the PhasmaEngine checkout beside this repo (`..\PhasmaEngine`).

- **Player:** double-click `run.cmd`, or run `powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1`. It copies the newest `PhasmaEngine\build*\Release\PhasmaPlayer.exe` build into `%LOCALAPPDATA%\PhasmaGames\<game>`, points its `phasma_settings.json` at this project's `Assets`, and launches with `--api vulkan --display 1`. The shared engine build is not modified.
- **Editor:** launch `PhasmaEditor.exe` (e.g. `..\PhasmaEngine\build-ninja-physics\Release`) and open this folder as the project, or set `"project_path"` in that build's `phasma_settings.json` to this folder's `Assets` (note: other tools share that file). The startup scene is `Assets/Scenes/main.pescene`.

Asset paths in scripts are Assets-relative. `shots/` holds screenshots from the Linux build.
