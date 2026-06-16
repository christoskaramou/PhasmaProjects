# Warbound

A real-time strategy prototype built on PhasmaEngine — an **original** game in the
classic 3D-RTS mold (angled command camera, hero units, base-building, tech).
Not affiliated with or derived from any existing game; all factions, names, units,
and assets are original.

## What's playable now (first vertical slice — "Hero + Squad")

- Angled RTS camera: pan with `WASD` / arrow keys / screen-edge scroll, zoom with the mouse wheel.
- Select units: left-click a unit, or left-drag a selection box. Click empty ground to deselect.
- Command units: right-click ground to move, right-click an enemy to attack.
- A hero with a leveling stat line and an active **Warstomp** ability (key `Q` or the command card).
- A squad of soldiers under your command and a feral enemy camp to clear.
- WC3-style HUD: minimap, selected-unit portrait + stats, command card, and a gold/lumber/food readout.

## Running

Warbound is a Lua-only PhasmaEngine project, run through **PhasmaPlayer**.
Point the engine build's `phasma_settings.json` at this project (set `project_path`
to this folder and `startup_scene` to `Assets/Scenes/skirmish.pescene`), then launch
`PhasmaPlayer.exe`. The whole game boots from `Assets/Scripts/Player/warbound.lua`
(PhasmaPlayer auto-runs every `.lua` in `Scripts/Player/`).

## Authored scene + script-driven dynamics

Like the AgainstTheHero project, **everything is authored in the scene hierarchy** —
the terrain, scenery (trees, rocks, the gold mine), the camera, every unit rig, AND
the HUD panels (minimap / portrait / command card / resources / FPS / objective) are
real nodes in `skirmish.pescene`. Open it in the editor and you can see/edit them. At
runtime the scripts only *adopt* those nodes (by name) and drive the **dynamic** parts:
movement, combat, HP, selection, abilities, plus the HUD's live content (minimap dots,
bars, button states, and the resource/FPS/objective text via `node:set_ui`).

### Regenerating the scene (bake)

The authored scene is generated from code, then saved once:

1. **World + units**: launch PhasmaPlayer with `WB_BAKE=1` — `Game.init` builds the
   world (`wb_world`) and every unit rig (from the `ROSTER` in `wb_game.lua`) and calls
   `scene.save`, writing `Assets/Scenes/baked`. Copy it to `skirmish.pescene`.
2. **HUD panels**: run `python tools/build_hud.py` — it appends the HUD runtime_ui
   nodes to `skirmish.pescene` (idempotent via a `UI_Root` marker).

Normal runs (no `WB_BAKE`) just adopt the authored scene. The HUD panels can't be
script-created (the engine only renders runtime_ui nodes present at scene load), which
is why they're authored as JSON by `build_hud.py`.

## Layout

```
Assets/
  Scenes/skirmish.pescene      AUTHORED scene: terrain, scenery, camera, unit rigs (real nodes)
  Scripts/
    Player/warbound.lua        boot: loads modules, drives the per-frame loop
    game/                      the game, split into focused modules (see PLAN.md)
```

See [PLAN.md](./PLAN.md) for the design, module map, and roadmap.
