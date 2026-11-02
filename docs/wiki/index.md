# PhasmaProjects knowledge

This index describes the sibling project collection, not the canonical AgainstTheHero checkout. Do not infer implementation from project names.

- `Arcade/`: the 20 arcade remakes (NeonBreakout, FroggerRemix, RiverRaidRemix, MissileCommand, NeonAsteroids,
  NeonCombat, NeonInvaders, PacManRemix, PitfallRemastered, GalagaRemix, CentipedeRemix, DefenderRemix,
  TempestRemix, QbertRemix, DigDugRemix, JoustRemix, RobotronRemix, PongRemix, BattlezoneRemix,
  BubbleBobbleRemix), moved from the repo root on 2026-10-17. Their `run.ps1` walks up to find a sibling
  `PhasmaEngine` checkout (override with `PHASMA_ENGINE`).
- `ArrowOut/`: runtime-UI arrow puzzle (tap arrows to slide them off the board), added 2026-11-02; see its README.
  Input-enabled runtime-UI quads draw above plain quads whatever their `z`, so its board click catcher is transparent.
  Its scene began as a copy of PRISM's. With PRISM's `"present_mode": 2` the Player logged 30 FPS; without that key it logged 60 (2026-11-02).
- `Chess/`: separate project; inspect its manifest, source and local instructions.
- `PhasmaSpace/`: separate project; inspect its manifest, source and local instructions.
- `Arcade/PrismTetris/`: separate project; inspect its manifest, source and README. Moved here from the engine's
  `Games/PrismTetris` on 2026-10-16 (PhasmaProjects `74226ac`, engine `0e5e648d`), then into `Arcade/` on 2026-10-17.
- `Sample/`: separate project; inspect its manifest, source and local instructions.
- `VoxelCraft/`: separate project; inspect its manifest, source and local instructions.
- `Warbound/`: separate project; inspect its manifest, source and local instructions.
- `Ylem/`: separate project; inspect its manifest, source and local instructions.

## Engine checkout beside this repo

Verified 2026-10-16: PhasmaProjects and PhasmaEngine are sibling checkouts. The engine's `CMakeLists.txt`
pins `../PhasmaProjects/Sample`, `Arcade/PrismTetris/run.ps1` searches upward for a sibling `PhasmaEngine` (Release
Player in `build-ninja-physics/Release`, race driver in `build-game-driver/Release`), and the engine's
`Arcade/PrismTetris/run-race.ps1` drives that same Player with the engine's `PhasmaGameDriver.exe` over MCP (`--url http://127.0.0.1:8876/mcp`; the driver takes no project path), replacing the engine's copying `run-tetris.ps1`. An engine checkout with another
folder name is not found (the Arcade games' `run.ps1` also honours `PHASMA_ENGINE`). Chess's `run_smoke.ps1` uses absolute engine paths instead.

Keep durable project decisions in focused pages here or in the individual project wiki. Use live source for behavior. Do not recreate retired memory or graph databases.
