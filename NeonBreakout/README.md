# NEON BREAKOUT (PhasmaEngine remake)

A modern, VFX-heavy remake of Atari's Breakout (1976), written in Lua for PhasmaEngine.

## Run
- Windows: `run.cmd` (or `powershell -File run.ps1 [-Api vulkan|dx12]`). Uses the newest
  `..\..\PhasmaEngine\build*\Release\PhasmaPlayer.exe` and a private runtime copy in `%LOCALAPPDATA%\PhasmaGames\NeonBreakout`.
- Linux box: `./run.sh` (Xvfb + lavapipe), `./dev.sh` restarts only this game's player (MCP on :9107), `./stop.sh` stops it.

## Controls
| Action | Input |
|---|---|
| Move paddle | Mouse (paddle follows the cursor) or Left/Right / A/D |
| Launch ball / fire laser | Left click or Space (hold for laser) |
| Pause menu | P or Esc |
| Mute | M |
| Menus | Mouse hover/click, or Up/Down + Enter |

## Rules
- **Wall 1 – CLASSIC**: 8 rows x 14 bricks; yellow 1, green 3, orange 5, red 7 points. The ball speeds up after
  4 hits, 12 hits and on first contact with the orange and red rows; the paddle halves once the ball reaches the
  top wall. 3 balls; bounce angle depends on where the ball hits the paddle.
- **Walls 2-5 – NEON STAGES** (PRISM, DIAMOND, INVADERS, FORTRESS), then the cycle repeats faster. Steel bricks
  take 2 hits (they crack), gold bricks are unbreakable. 15% of bricks drop power-ups:
  WIDE (cyan), MULTI-ball (magenta), SLOW (green), LASER (red), FIRE piercing ball (orange), +1 BALL (white).
- Losing a ball restores the paddle and eases the speed one step. Wall clear bonus = 100 x wall.

## Tech / visuals
- Bevelled bricks, rounded paddle, rails and ball are procedural meshes (`tools/gen_meshes.py`) cooked with
  PhasmaCook into `Assets/Objects/*.pemesh`; `main.pescene` holds them as template nodes (one source per
  template so each has its own material) and the game clones them with `add_mesh_ref`.
- Glossy PBR brick bodies + emissive face plates, HDR studio skybox for reflections, bloom, colour grading,
  dynamic point lights (ball, paddle, impact flashes, swinging key lights), shard debris, spark/dust particles,
  ghost-sphere ball trails, screen shake, brick drop-in intro, pulsing neon frame.
- Shared settings menu (`Scripts/Lib/settings_menu.lua`): master volume (default 50%), SFX, mute, quality,
  bloom, AO, particles, screen shake, FPS.
- Assets regenerate with `tools/gen_assets.py` (textures, skybox, WAV sfx) and `tools/gen_scene.py`.

## 2026-10-16 update
- Neon border is now continuous: glow strips sit in front of the chrome rails (they were buried inside them, showing only as broken segments / z-fighting); side rails close the top corners.
- Removed the idle camera sway; camera now eases smoothly toward the paddle; hit shake is smaller and settles fully.
- Render: TAA on, HDR on, FXAA off, CAS sharpen on, bloom strength 0.55 / range 1.8 (smoother, weaker).
