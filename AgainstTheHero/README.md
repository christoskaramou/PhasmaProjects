# AgainstTheHero (ATH)

A persistent-character top-down auto-battler ARPG built on **PhasmaEngine**. Choose a
hero, gear up in town, buy equipment with banked gold, then move through five
auto-attack waves and a boss. Drafted cards last for one map; gold and gear persist.

This project directory contains the game's assets, Lua gameplay systems, and project
configuration. Engine binaries are maintained separately.

## Layout

- `Assets/` - scripts, shaders, textures, fonts, particles, and other game content
- `Assets/Scripts/Player/against_the_hero.lua` - entry dispatcher for the game
- `Assets/Scripts/shared/` - shared card, duel, menu, art, console, and top-down view systems
- `Assets/Scripts/modes/` - the active `arena` mode and its farm-creep content
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

The authored scene flow is `intro.pescene` -> hero selection -> map selection ->
`game.pescene`. The game scene opens in town, where the store, six-slot paper doll,
backpack, and Enter Map button are available before each run. Local progress is saved
under `Assets/Save/` (gitignored).

For a Release smoke on display 1:

```powershell
.\run_smoke.ps1 -Seconds 30
```

Useful environment knobs for direct/debug launch paths:

```bash
ATH_MODE=menu PhasmaPlayer.exe
ATH_DUEL_MODE=arena ATH_SIDE=hero PhasmaPlayer.exe
ATH_DEV=1 PhasmaPlayer.exe   # or enable Dev Mode in Settings
```

Dev cheat console (`` ` `` / F1 when Dev Mode is on): `mymap`, `swaphero <name>`,
`cantdie`, `gold <n>`, `specme <n>`, `item <name>`, `endless`, `superhero`.

## Modes

- `arena` - a manual-hero five-wave feel test with movement and auto-attacks

## Hero Brain

The project has a local-AI bridge shape under `Assets/HeroBrain/`: the game can write
requests and read validated responses, while the repo ignores generated request,
response, and save-state files. Sidecar tooling can be restored or replaced without
polluting the tracked project content.

## Edit

Launch `PhasmaEditor.exe` with `project_path` set to this directory. The editor picks
up `phasma_project.json`; once a startup scene exists, save it through the project
settings or runtime `phasma_settings.json`.
