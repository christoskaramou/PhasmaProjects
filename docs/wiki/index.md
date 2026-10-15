# PhasmaProjects knowledge

This index describes the sibling project collection, not the canonical AgainstTheHero checkout. Do not infer implementation from project names.

- `Chess/`: separate project; inspect its manifest, source and local instructions.
- `PhasmaSpace/`: separate project; inspect its manifest, source and local instructions.
- `PrismTetris/`: separate project; inspect its manifest, source and README. Moved here from the engine's
  `Games/PrismTetris` on 2026-10-16 (PhasmaProjects `74226ac`, engine `0e5e648d`).
- `Sample/`: separate project; inspect its manifest, source and local instructions.
- `VoxelCraft/`: separate project; inspect its manifest, source and local instructions.
- `Warbound/`: separate project; inspect its manifest, source and local instructions.
- `Ylem/`: separate project; inspect its manifest, source and local instructions.

## Engine checkout beside this repo

Verified 2026-10-16: PhasmaProjects and PhasmaEngine are sibling checkouts. The engine's `CMakeLists.txt`
pins `../PhasmaProjects/Sample`, `PrismTetris/run.ps1` finds the engine as `../../PhasmaEngine` (Release
Player in `build-ninja-physics/Release`, race driver in `build-game-driver/Release`), and the engine's
`Phasma/GameDriver/run-tetris.ps1` copies `../PhasmaProjects/PrismTetris`. An engine checkout with another
folder name is not found. Chess's `run_smoke.ps1` uses absolute engine paths instead.

Keep durable project decisions in focused pages here or in the individual project wiki. Use live source for behavior. Do not recreate retired memory or graph databases.
