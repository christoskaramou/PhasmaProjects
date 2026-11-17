# Undertow

A stormy harbour at dusk. You are a glass fishing float on a chain: hold to hook the nearest hook ahead (lamp arms
of channel buoys and piers), swing, release to fly; skim the swells, don't hit them steeply. **Phase 1: look slice
only** (no rules, menus or sounds yet).

Run: `run.cmd` (finds the sibling `PhasmaEngine` build). MCP port 8912 (`Assets/Agent/agent_config.json`, gitignored).

Console (MCP `execute_lua`): `undertow.state('A')` / `undertow.state('B')` pose the two target frames exactly;
`undertow.run(12)` starts the scripted pendulum and the camera scroll; `undertow.stop()`; `undertow.info()`;
`undertow.timing_reset()` / `undertow.timing()` measure frame time inside the game.

## How it is made

See `.concepts/next/undertow/LOOKPLAN.md` and `PROGRESS.md`. The sky (a quad facing the fixed-rotation camera), the
far shore and the set pieces (buoys, boat, pier, breakwater) are Cycles bakes drawn unlit; the sea, the float, chain,
lights and particles are live. The sea is one Gerstner swell pattern, periodic every 48 units, slid along x on pooled
tiles; its vertex colours (troughs, backs, crest foam) ride with the swells, a 12-frame ripple normal map loops on top.

| Tool | Makes |
| --- | --- |
| `tools/uw_common.py` | shared numbers: camera, play plane, sea height, course, the two reference states |
| `tools/uw_sea.py` | the sea tile (shared by the Blender target and the game mesh) |
| `tools/scene.py` | Blender: textures, sky panorama, far layer, baked pieces, the target frames (`-- MODE`) |
| `tools/gen_assets.py` | cooked meshes, textures, `storm.hdr`, `main.pescene`, `Scripts/uw_data.lua`, `tests/sea_samples.lua` |
| `tools/live.py`, `tools/capture.py` | muted throwaway Player copy on 8912: Lua, screenshots, window size, captures |

Tests (engine's `luajit.exe`, from this folder): `tests/view_smoke.lua` boots the real scripts against stubbed engine
APIs: sea height parity with Python, pools over a 2,000-unit scroll, chain links on the hook-float line, states after a
long scroll, the drawn hook meeting the chain after node recycling, a held state following the bob.
