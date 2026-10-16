# River Raid Remix

A modern 3D remake of **River Raid** (Activision, Atari 2600, 1982) for
[Phasma Engine](https://github.com/christoskaramou/PhasmaEngine).

## Highlights
- **Procedural meshes** cooked with `PhasmaCook`: player jet (fuselage, swept wings, canards,
  twin intakes, canopy, glowing nozzle), enemy jets, tankers (lofted hull, cargo tanks, bridge,
  funnel), helicopters (spinning main and tail rotors), floating fuel depots with FUEL-striped tanks,
  steel truss bridges with piers and lamps, rocky riverbank strips, trees, houses, rocks and FX meshes.
  Every part is a template node `T_<part>` in `Assets/Scenes/main.pescene`. The game clones them
  at runtime with `add_mesh_ref`, because the player can't load models.
- **Procedural river**: each section between two bridges is generated from its own seed. Sections have
  gorges, open water and split channels around islands, and the shores bend smoothly between rows.
  The river gets narrower and busier further upstream.
- **Visuals**: glossy normal-mapped water that reflects a golden-hour HDR sky, sun shadows, bloom,
  colour grading and dynamic point lights (engine glow, missile light, explosion flashes, refuel glow,
  bridge lamps).
- **Particles**: jet exhaust and heat haze, rotor downwash and ship wakes, missile trails, water
  spray, explosion fire, sparks, smoke, splash columns, refuel sparkles and floating pollen.
  Explosions also use emissive fireballs, shock rings and debris that splashes into the water.
- **Faithful rules**: speed control, fuel that drains and refills over depots, crashes on banks and
  islands, bridges as checkpoints (you respawn at the last bridge you destroyed), 4 jets, a bonus jet
  every 10,000 points, and the classic scoring: tanker 30, helicopter 60, fuel 80, jet 100, bridge 500.
- **Modern controls**: smooth lateral acceleration with banking, eased throttle, auto-fire when you
  hold the fire key, and a camera that follows you with a speed pull-back and screen shake.
- **Forgiving hitboxes**: the crash boxes for your jet, enemies, bridges and the river banks are about
  63% of their visual size, so near-misses survive (your missiles still use the full target boxes).
- An attract-mode autopilot flies behind the title screen. Your best score is saved to `Assets/Save/best.txt`.
- The shared settings menu (`Assets/Scripts/Lib/settings_menu.lua`) has master volume (default 50%),
  SFX volume, mute, quality presets, bloom, AO, particles, screen shake and an FPS counter.

## Controls
| Key | Action |
|---|---|
| Left / Right, A / D | Steer |
| Up / W | Speed up |
| Down / S | Slow down |
| Space / Z / J / X | Fire (hold for auto-fire) |
| Esc / P | Pause / resume |
| O | Settings (title, pause, game over) |
| Enter / Space | Start |
| R (paused) | Restart |
| Q (paused / game over) | Back to title |
| M | Mute |

## Run (Windows)
```powershell
.\run.ps1
# or double-click run.cmd
```
This needs a local Phasma Engine build at `../../PhasmaEngine/build*/Release/PhasmaPlayer.exe`,
relative to this folder (see `run.ps1`).

## Rebuild assets (optional)
```bash
python3 tools/gen_assets.py     # textures, HDR sky, WAV sfx
python3 tools/gen_meshes.py     # OBJ meshes -> meshsrc/
bash tools/cook_all.sh > tools/cook.log   # PhasmaCook -> Assets/Objects/*.pemesh
python3 tools/gen_scene.py      # template nodes -> Assets/Scenes/main.pescene
```
`cook_all.sh` expects `bin/` (PhasmaCook) and `meshsrc/` next to `project/`, as in the Linux dev layout.

## Shots
`shots/`: title (attract mode), gameplay, a bridge going down, and an explosion.

## 2026-10-16 update
- Steering: eased input + acceleration-limited lateral velocity, max strafe 8 (was 11.5); smoother bank (roll) and slight yaw lerp.
- Explosions ~30% smaller, fewer/dimmer sparks, weaker point-light flash and emissive fireball.
- Title / pause / game-over menus have mouse-clickable buttons.
- Render: TAA on, HDR on, FXAA off, bloom 0.55 / 1.8.
