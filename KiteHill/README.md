# Kite Hill

Fly a cloth kite through numbered ribbon gates above rolling green hills and race three rival kites.

- The kite always flies along its nose: it turns toward the **pointer** (or turn it with `A` / `D`, `←` / `→`).
  Turning hard costs speed, and the edges of the wind window are slower.
- Take the rings **in order**; through the middle is a **bullseye** (an extra coin). Dip into the grass and the kite
  crashes and relaunches a second later.
- **Gusts** are announced, then blow every kite off line for a couple of seconds: flying with one is faster.
  `Space` (or right-click) spends an **updraft**, a short burst of speed.
- Finish in the places the heat asks for (top 3, then top 2, then only a win) to go on to the next heat: more
  rings, smaller rings, faster rivals, stronger gusts. Lose a heat and the run ends.
- **Coins** (rings, bullseyes, placings) stay with you between runs. The **workshop** (`W` on the title, results and
  run-over cards) sells upgrades (Silk Sail, Tuned Bridle, Long Tail, Updraft, Keen Eye) and new kite designs.

Controls: pointer or `A` / `D` steer, `Space` updraft, `Enter` continue, `W` workshop, `Esc` settings, `M` mute.

Run: `run.cmd` (Windows; finds the sibling `PhasmaEngine` build, see the repo wiki index). The player's MCP server
listens on port 8882 (`Assets/Agent/agent_config.json`).

## How it is made

The hills, fields and hedges, footpath, whitewashed village with tiled roofs, the windmill's tower, trees, sheep,
wild flowers, sky and volumetric clouds are a Cycles render from the game's fixed camera (`tools/make_backdrop.py`);
the game shows it unlit on a quad that fills the view. The ground is one analytic function of gaussian hills shared
by the bake (`tools/kh_common.py`) and the rules (`R.HILLS`), so every house stands on the pictured hill and the
gates' poles and the kites' shadows land on the pictured grass. In 3D on top: the kites (four billowed cloth panels
on a bowed spar, a swinging tail of ribbon bows, the line), the gates, the kite flyer who turns to follow the kite,
and the windmill's sails (faster in a gust), lit by the scene's sun and a sky HDR, with soft fake shadows cast from
the sun's direction. Every kite flies in one upright plane above the valley; the race is simulated in pure Lua
(`Assets/Scripts/kitehill_rules.lua`).

| Tool | Makes |
| --- | --- |
| `tools/kh_common.py` | shared numbers: camera, sun, ground, village, trees, windmill |
| `tools/gen_meshes.py` | 3D meshes (`Assets/Objects`), `Assets/Scenes/main.pescene` (`--scene-only`: scene only) |
| `tools/make_backdrop.py` | `Assets/Textures/backdrop.png` (Blender 5.x; `[samples] [scale]`, scale < 1 writes a preview) |
| `tools/make_textures.py` | shadow sprites, `Assets/Skybox/sky.hdr` |
| `tools/make_sounds.py` | `Assets/Audio/*.wav` |

The camera and sun in `kh_common.py` and `kitehill_world.lua` (`W.CAM`, `W.SUN`), and the hills in `kh_common.py` and
`kitehill_rules.lua` (`R.HILLS`), must stay identical (`tests/rules_test.lua` checks the ground at sample points).

Tests (run from this folder with the engine's `luajit.exe`): `tests/rules_test.lua` (flight, rings, gusts, rival AI,
heats, runs, workshop and save) and `tests/view_smoke.lua` (the game script against stubbed engine APIs).

Font: Lilita One by Juan Montoreano, SIL Open Font License 1.1 (`Assets/Fonts/LilitaOne-OFL.txt`).
