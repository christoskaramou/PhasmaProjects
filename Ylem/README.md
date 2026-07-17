# Ylem

A tactile physics sandbox on **PhasmaEngine** where you **coalesce** matter —
protons, neutrons, and electrons into real atoms, then atoms into molecules.
Each synthesis gets a birth announcement: real name, symbol, and a one-line
"where you find it / what it does."

*Ylem* (Gamow's word) is the primordial substance of the Big Bang — the title
is the arc's alpha point. The long-term verb is the same at every scale: pull
things together until they bind.

See [PLAN.md](./PLAN.md) for design intent and build order. **Lab** is the
playable mode today; **Cosmos** (Powers-of-Ten zoom from atoms to stars) is
planned later.

## What's playable (Lab)

Screen-space `runtime_ui` chemistry tabletop — no 3D gameplay:

- Drag **protons**, **neutrons**, and **electrons** from trays onto the atom
- Full periodic table (Z 1–118) as both target space and discovery board
- Period rings that lock gold at the noble gases
- Unstable isotopes tremble and decay (beta, alpha, electron capture, …);
  quench them before the clock runs out
- Neutron capture climb, bonding (H₂ / H₂O), fusion / fission at the high end
- Target cards: synthesize the named element or molecule, then tap for the next

## Layout

- `Assets/Scripts/ylem.lua` — scene `on_play` entry; loads Lab and ticks it
- `Assets/Scripts/lab.lua` — Lab loop, drag/snap juice, decay, bonding, UI
- `Assets/Scripts/data.lua` — element table, isotopes, configs, lore helpers
- `Assets/Scenes/main.pescene` — startup scene (Camera + HUD; Lab draws via UI)
- `Assets/Textures/` — particle / ring sprites and orbital art
- `Assets/Audio/` — snap, lock, thump, birth SFX
- `tools/` — sprite / orbital / SFX generators
- `phasma_project.json` — project manifest
- `PLAN.md` — design document

## Run

Build or download PhasmaEngine, then point the player at this project. In the
engine build output dir, create `phasma_settings.json` like:

```json
{ "project_path": "../../../PhasmaProjects/Ylem" }
```

Absolute paths work too. Startup scene: `Assets/Scenes/main.pescene`.

Release smoke on display 1:

```powershell
.\run_smoke.ps1
```

## Edit

Launch `PhasmaEditor.exe` with `project_path` set to this directory. The editor
picks up `phasma_project.json`.
