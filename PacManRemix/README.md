# PAC-MAN Remix (PhasmaEngine)

A neon 3D Pac-Man remake.

## Controls
Arrows / WASD move, Enter start, P / Esc pause. Holding two directions (e.g. Up+Left) works: Pac-Man takes the newest held direction when it is open, otherwise the other held one, otherwise keeps going; a tap just before a junction is buffered.

## Sound
A soft tick loop plays while Pac-Man moves (silent when he stops against a wall); eating a dot plays the
alternating "wa-ka" chomp. All sounds are procedural: `python3 tools/gen_audio.py` regenerates
`move.wav`, `waka1.wav` and `waka2.wav` in `Assets/Audio`.

## Run on Windows

Like the other PhasmaProjects, this runs on the PhasmaEngine checkout beside this repo (`..\PhasmaEngine`).

- **Player:** double-click `run.cmd`, or run `powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1`. It copies the newest `PhasmaEngine\build*\Release\PhasmaPlayer.exe` build into `%LOCALAPPDATA%\PhasmaGames\<game>`, points its `phasma_settings.json` at this project's `Assets`, and launches with `--api vulkan --display 1`. The shared engine build is not modified.
- **Editor:** launch `PhasmaEditor.exe` (e.g. `..\PhasmaEngine\build-ninja-physics\Release`) and open this folder as the project, or set `"project_path"` in that build's `phasma_settings.json` to this folder's `Assets` (note: other tools share that file). The startup scene is `Assets/Scenes/main.pescene`.

Asset paths in scripts are Assets-relative. `shots/` holds screenshots from the Linux build.
