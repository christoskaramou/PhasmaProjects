# AgainstTheHero (ATH)

A card-fed auto-battler prototype built on **PhasmaEngine**. The pitch is simple:
heroes and hordes fight automatically, while cards, sides, battlefields, and AI
policy shape the run.

This project directory contains the game's assets, Lua gameplay systems, and project
configuration. Engine binaries are maintained separately.

## Layout

- `Assets/` - scripts, shaders, textures, fonts, particles, and other game content
- `Assets/Scripts/Player/against_the_hero.lua` - entry dispatcher for the game
- `Assets/Scripts/shared/` - shared card, duel, menu, art, console, and top-down view systems
- `Assets/Scripts/modes/` - active menu battlefields: `arena`, `spud_fields`, `alien_hive`
- `Assets/Scripts/old/` - older battlefields kept as design/code stock
- `Assets/HeroBrain/` - local AI request/response scratch space; generated files are ignored
- `phasma_project.json` - project manifest for the collection layout

## Run

Build or download PhasmaEngine, then point the engine at this project directory. In the
engine build output dir, create `phasma_settings.json` like:

```json
{ "project_path": "../../../PhasmaProjects/AgainstTheHero" }
```

Absolute paths work too.

The game entry script defaults to the menu flow: pick a side, pick a battlefield, and
run the duel. The menu-launchable battlefields are listed in
`Assets/Scripts/shared/ath_modes_index.lua`.

`Assets/Scenes/` is currently empty in this collection, so `phasma_project.json` does
not pin a startup scene yet. Create or restore a scene in the editor, attach
`Assets/Scripts/Player/against_the_hero.lua`, then save it as the project startup
scene before launching directly in `PhasmaPlayer.exe`.

Useful environment knobs once a startup scene is wired:

```bash
ATH_MODE=menu PhasmaPlayer.exe
ATH_DUEL_MODE=arena ATH_SIDE=hero PhasmaPlayer.exe
ATH_DUEL_MODE=spud_fields ATH_SIDE=horde PhasmaPlayer.exe
ATH_DUEL_MODE=alien_hive ATH_SIDE=horde PhasmaPlayer.exe
```

## Modes

- `arena` - a manual-hero five-wave feel test with movement and auto-attacks
- `spud_fields` - a chunky cartoon farm battlefield with garden-horde pressure
- `alien_hive` - a glowing bio-hive battlefield with acid hazards and brood enemies

## Hero Brain

The project has a local-AI bridge shape under `Assets/HeroBrain/`: the game can write
requests and read validated responses, while the repo ignores generated request,
response, and save-state files. Sidecar tooling can be restored or replaced without
polluting the tracked project content.

## Edit

Launch `PhasmaEditor.exe` with `project_path` set to this directory. The editor picks
up `phasma_project.json`; once a startup scene exists, save it through the project
settings or runtime `phasma_settings.json`.
