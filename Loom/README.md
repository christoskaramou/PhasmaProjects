# Loom

A wooden hand loom seen from the weaver's seat. The cloth you weave is a landscape in low relief, and a tiny
traveller walks through it toward the weaving edge. Weave each row cell by cell from the wool bobbins (each
colour is a kind of land), beat it in, and keep the traveller's path going: rivers need bridges, wool runs out
and is earned back by what the path passes. Nothing can be unpicked.

Run: `run.cmd` (finds the sibling `PhasmaEngine` build). MCP port 8913 (`Assets/Agent/agent_config.json`, gitignored).

Controls (also on the title card): Left/Right or A/D move along the row · 1-9 lay meadow, path, water, bridge,
woods, field, hill, rock, house (or click a cell, then a bobbin) · Backspace take back the last pick ·
Space beat the row in · Esc pause · M mute.

Rivers and rocks stand in the path's way from the first rows; the COMING UP panel (top right) shows the next 3 rows,
so turn the path sideways early. Wool is scarce: land beside the path pays it back when the traveller walks past
(hover a chip, or press its key, to see what each kind costs, does and pays). Warnings above the chips name the
next thing to fix: a river on the path, a blocked row, low path wool.

## How it is made

See `.concepts/next/loom/LOOKPLAN.md` and `PROGRESS.md`. The table, loom frame, reed, warp and wool stands are
one Cycles bake drawn unlit on a mesh projected from the bake's depth (so the engine's depth of field blurs it by
distance). The cloth is a fixed grid of 9 x 14 cell nodes; each shows one cooked variant keyed by its kind and
3x3 neighbourhood (`set_mesh_ref`), so hills, rivers, paths and fields run on across cells. Rows past the front
beam use a rolled copy of their variant.

| Tool | Makes |
| --- | --- |
| `tools/loom_grid.py` | shared numbers and fields: grid, camera, hills, bands, variant keys (one geometry source) |
| `tools/scene.py` | Blender: target frames (`-- target`), backdrop bake, `-- export` of every cooked piece |
| `tools/gen_assets.py` | runs the export, cleans and cooks the OBJs, textures, `main.pescene`, `Scripts/loom_data.lua`, test samples |
| `tools/live.py`, `tools/capture.py` | muted throwaway Player copy on 8913: Lua, screenshots, window size, captures |

Tests (engine's `luajit.exe`, from this folder): `tests/rules_test.lua` (pure rules), `tests/view_smoke.lua`
(real scripts against a stubbed engine: drawn variants and props against the rules and the cooked meshes).
