# Refract

A light-bending tower defense for PhasmaEngine: a lit 3D neon board (PBR, bloom, SSR, SSAO, TAA,
colour grading, coloured point lights, GPU particles) under a runtime-UI HUD, all in Lua.
You never build a gun. You build **light**: emitters fire white beams, mirrors bend them, prisms split
white light into red, green and blue, and lenses focus them. Every enemy a beam crosses burns, so the
game is about routing light *along* the lane, not just pointing it across.

## Run

`run.cmd`, or `powershell -File run.ps1 [-Api vulkan|dx12]`. It finds a sibling `PhasmaEngine`
Release `PhasmaPlayer.exe` (or uses `PHASMA_ENGINE`) and runs a private copy from `%LOCALAPPDATA%\PhasmaGames\Refract`.

| Input | Action |
| --- | --- |
| 1-5 / tool buttons | Emitter (60), Mirror (15), Prism (55), Lens (40), Upgrade |
| Left click | Build the selected piece; on a piece: turn an emitter, flip a mirror (or upgrade with tool 5) |
| Right click | Sell a piece (70% back) |
| Space / START | Start the first wave; later, call the next wave early for bonus energy |
| Q / SURGE | When charged by kills: all light x3 for 5 seconds |
| F | Speed x1 / x2 / x3 |
| P | Pause (R restarts the sector while paused or before the first wave) |
| PgUp / PgDn | Change sector before the first wave (up to the furthest reached) |
| Esc / MENU | Settings menu (graphics quality, bloom, AO, particles, volume, shake, FPS counter) |
| M | Mute |

Hovering a cell previews the new light paths and shows how the total light on the lane would change.
Hovering a tool card (or picking a tool) opens a panel that explains what the tool does, with its numbers.

Rendering: TAA at full resolution (render scale 1.0); FXAA stays off. The engine only runs post-processing
(TAA jitter, bloom, tonemapping) when the scene has a Scene Settings node, so `refract_world.lua` creates one
at startup. Shadows stay off (the shared menu's ULTRA preset would force them on; `on_graphics` overrides it). Beam glow and brightness saturate
with power, so stacking lenses strengthens the light without blowing out the picture.

## Rules

- Each sector is a generated map: a winding lane (at least 50 cells) from the rift to the core, rocks
  that block light, mirrored left/right on even sectors. 12 waves per sector; the core has 20 integrity.
- Light power: emitter 9 / 16 / 26 damage per second by tier. A prism turns white into red (left),
  green (straight) and blue (right), each at 62%. Coloured light passes prisms unchanged. Lenses x1.5.
- Enemies: Motes, fast Darts, armoured Hulks, Red/Green/Blue **Shades** (x2.2 from their colour, x0.3
  from others, x0.45 from white), **Mirrorbacks** (immune to white), **Splitters** (burst into Motes), and
  the **Eclipse** boss, whose shield cycles red, green, blue every 3 seconds.
- Kills pay energy and charge the Surge. Clearing a wave pays a bonus; calling a wave early pays more.
- The furthest sector reached is saved in `Assets/Save/refract_sector.txt`. The settings menu is the
  shared `Scripts/Lib/settings_menu.lua` (unchanged copy). TAA stays on; the menu does not manage it.

## Files

- `Assets/Scripts/refract_rules.lua`: rules (maps, light tracing, waves, economy); no engine calls.
- `Assets/Scripts/refract_world.lua`: the 3D board. Raised metal blocks with the lane cut as a neon
  channel over a mirror-polished floor; emitters, mirrors, glass prisms and lenses as models; emissive
  beams with coloured point lights; enemies, rift and core; GPU particle bursts, sparks and dust;
  shockwave rings; camera drift and shake; mouse picking by unprojecting onto the block tops.
- `Assets/Scripts/refract.lua`: flow, input and the HUD (tool cards, wave pips, next-wave icons,
  energy and core panels, cards, banners, health bars and floaters projected from 3D). The soft
  colour glow around beams is drawn here as projected Gaussian strips, because the engine's bloom
  kernel is too short to give a thin line a wide halo.
- `tools/make_art.py`: generates the HUD textures (numpy + PIL). `tools/make_assets.py`: generates the sounds.
- `tests/rules_test.lua`: rules checks plus a greedy bot that must clear sectors 1-3.
- `tests/view_smoke.lua`: boots the view and world against stubbed engine APIs, checks picking round
  trips for every cell, plays through clicks and waves, and checks scene nodes do not leak on restarts.

Run tests from this folder with the engine's LuaJIT, for example
`..\..\PhasmaEngine\build-ninja-physics\Release\luajit.exe tests\rules_test.lua`.
