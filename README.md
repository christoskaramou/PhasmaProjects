# PhasmaProjects

Small, free PhasmaEngine projects and game prototypes. This repo is meant to become
a showcase shelf: fast experiments, playable slices, and demos that prove the engine
can make real things quickly.

## Projects

<table>
<tr><th width="300">Project</th><th>What it is</th></tr>
<tr><td width="300"><a href="./PhasmaSpace/README.md"><img src="docs/images/phasmaspace.png" width="280" alt="PhasmaSpace"></a><br><a href="./PhasmaSpace/README.md"><strong>PhasmaSpace</strong></a></td><td>A real-scale solar-system demo with Lua-driven ephemerides, planet/moon catalogs, orbit guides, city lights, and a Gaia sky background.</td></tr>
<tr><td width="300"><a href="./Warbound/README.md"><img src="docs/images/warbound.png" width="280" alt="Warbound"></a><br><a href="./Warbound/README.md"><strong>Warbound</strong></a></td><td>An original real-time strategy prototype in the classic 3D-RTS mold - angled command camera, hero + squad combat, base-building economy, an AI opponent, and a command-card HUD.</td></tr>
<tr><td width="300"><a href="./VoxelCraft/README.md"><img src="docs/images/voxelcraft.png" width="280" alt="VoxelCraft"></a><br><a href="./VoxelCraft/README.md"><strong>VoxelCraft</strong></a></td><td>A Minecraft-style voxel playground: first-person movement, jumping, block outline, and break/place controls over PhasmaEngine's voxel runtime.</td></tr>
<tr><td width="300"><a href="./Ylem/README.md"><img src="docs/images/ylem.png" width="280" alt="Ylem"></a><br><a href="./Ylem/README.md"><strong>Ylem</strong></a></td><td>A tactile physics sandbox about coalescing matter - Lab builds real atoms (full table) from protons, neutrons, and electrons; Cosmos is planned later.</td></tr>
<tr><td width="300"><a href="./Sample/"><strong>Sample</strong></a></td><td>The engine's default project: a content/lighting showcase (a neon "Las Vegas" scene) that the editor and launcher open out of the box.</td></tr>
</table>

## Arcade

Modern remakes of classic arcade and Atari games, in [`Arcade/`](./Arcade/). Each one has its own README, screenshots and a Windows `run.cmd`.

<table>
<tr><th width="300">Game</th><th>What it is</th></tr>
<tr><td width="300"><a href="./Arcade/PrismTetris/README.md"><img src="docs/images/prismtetris.png" width="280" alt="Prism Tetris"></a><br><a href="./Arcade/PrismTetris/README.md"><strong>Prism Tetris</strong></a></td><td>A crystal-aurora 3D Tetris with guideline speed, hold and a five-piece preview, plus a side-by-side race against the Jev model on identical pieces. It runs the PhasmaPlayer.exe from a PhasmaEngine build, which <code>run.ps1</code> finds by searching upward from the game folder for a <code>PhasmaEngine</code> folder (for example <code>C:\Users\Christos\repos\PhasmaEngine</code>), or from the <code>PHASMA_ENGINE</code> environment variable.</td></tr>
<tr><td width="300"><a href="./Arcade/PacManRemix/README.md"><img src="docs/images/pacmanremix.png" width="280" alt="Pac-Man Remix"></a><br><a href="./Arcade/PacManRemix/README.md"><strong>Pac-Man Remix</strong></a></td><td>A 3D Pac-Man remake - maze chases, frightened ghosts, and particles everywhere.</td></tr>
<tr><td width="300"><a href="./Arcade/PitfallRemastered/README.md"><img src="docs/images/pitfallremastered.png" width="280" alt="Pitfall! Remastered"></a><br><a href="./Arcade/PitfallRemastered/README.md"><strong>Pitfall! Remastered</strong></a></td><td>Pitfall! rebuilt in 3D: vine swings over the swamp, crocodiles, and treasure tunnels.</td></tr>
<tr><td width="300"><a href="./Arcade/NeonInvaders/README.md"><img src="docs/images/neoninvaders.png" width="280" alt="Neon Invaders"></a><br><a href="./Arcade/NeonInvaders/README.md"><strong>Neon Invaders</strong></a></td><td>A modern Space Invaders remake with glowing alien waves, explosions, and the UFO.</td></tr>
<tr><td width="300"><a href="./Arcade/MissileCommand/README.md"><img src="docs/images/missilecommand.png" width="280" alt="Missile Command"></a><br><a href="./Arcade/MissileCommand/README.md"><strong>Missile Command</strong></a></td><td>Mouse-aimed Missile Command: three bases, incoming warheads, and a bonus tally between waves.</td></tr>
<tr><td width="300"><a href="./Arcade/NeonAsteroids/README.md"><img src="docs/images/neonasteroids.png" width="280" alt="Neon Asteroids"></a><br><a href="./Arcade/NeonAsteroids/README.md"><strong>Neon Asteroids</strong></a></td><td>Asteroids with a vector-glow look - rotate, thrust, fire, and hyperspace out of trouble.</td></tr>
<tr><td width="300"><a href="./Arcade/NeonCombat/README.md"><img src="docs/images/neoncombat.png" width="280" alt="Neon Combat"></a><br><a href="./Arcade/NeonCombat/README.md"><strong>Neon Combat</strong></a></td><td>A modern remake of Atari 2600 <em>Combat</em>: two tanks duel across maze arenas, versus a friend or the AI.</td></tr>
<tr><td width="300"><a href="./Arcade/NeonBreakout/README.md"><img src="docs/images/neonbreakout.png" width="280" alt="Neon Breakout"></a><br><a href="./Arcade/NeonBreakout/README.md"><strong>Neon Breakout</strong></a></td><td>A VFX-heavy remake of Atari's Breakout (1976), written in Lua, with power-ups.</td></tr>
<tr><td width="300"><a href="./Arcade/FroggerRemix/README.md"><img src="docs/images/froggerremix.png" width="280" alt="Frogger Remix"></a><br><a href="./Arcade/FroggerRemix/README.md"><strong>Frogger Remix</strong></a></td><td>Konami's Frogger on a twilight city street, with moving headlights and a glossy river.</td></tr>
<tr><td width="300"><a href="./Arcade/RiverRaidRemix/README.md"><img src="docs/images/riverraidremix.png" width="280" alt="River Raid Remix"></a><br><a href="./Arcade/RiverRaidRemix/README.md"><strong>River Raid Remix</strong></a></td><td>A 3D River Raid with a procedural river, fuel depots, bridges as checkpoints, and the classic scoring.</td></tr>
<tr><td width="300"><a href="./Arcade/GalagaRemix/README.md"><img src="docs/images/galaga_remix.png" width="280" alt="Galaga Remix"></a><br><a href="./Arcade/GalagaRemix/README.md"><strong>Galaga Remix</strong></a></td><td>Galaga (1981) remake: swooping formation, diving attacks, boss tractor-beam capture and dual-fighter rescue, challenging stages, stage badges.</td></tr>
<tr><td width="300"><a href="./Arcade/CentipedeRemix/README.md"><img src="docs/images/centipederemix_thumb.png" width="280" alt="Centipede Remix"></a><br><a href="./Arcade/CentipedeRemix/README.md"><strong>Centipede Remix</strong></a></td><td>A modernized remake of Atari's Centipede (1981), set on a bioluminescent forest floor.</td></tr>
<tr><td width="300"><a href="./Arcade/TempestRemix/README.md"><img src="docs/images/tempestremix_thumb.png" width="280" alt="Tempest Remix"></a><br><a href="./Arcade/TempestRemix/README.md"><strong>Tempest Remix</strong></a></td><td>Modern tube-shooter remake of Atari Tempest (1981). Glowing rail web, cooked claw &amp; enemies, TAA + soft bloom, clickable settings.</td></tr>
<tr><td width="300"><a href="./Arcade/DefenderRemix/README.md"><img src="docs/images/defenderremix_thumb.png" width="280" alt="Defender Remix"></a><br><a href="./Arcade/DefenderRemix/README.md"><strong>Defender Remix</strong></a></td><td>Modern remake of Williams Defender (1981). Wrap-around planet, scanner, abducting Landers, cooked ships, layered explosions, TAA + soft bloom, clickable settings.</td></tr>
<tr><td width="300"><a href="./Arcade/QbertRemix/README.md"><img src="docs/images/qbertremix_thumb.png" width="280" alt="Q*bert Remix"></a><br><a href="./Arcade/QbertRemix/README.md"><strong>Q*bert Remix</strong></a></td><td>A modernized remake of Gottlieb's Q*bert (1982).</td></tr>
<tr><td width="300"><a href="./Arcade/DigDugRemix/README.md"><img src="docs/images/digdugremix_thumb.png" width="280" alt="Dig Dug Remix"></a><br><a href="./Arcade/DigDugRemix/README.md"><strong>Dig Dug Remix</strong></a></td><td>Modern remake of Namco's Dig Dug (1982). Dig through four strata of cooked voxel earth, pump Pookas and Fygars until they pop, drop rocks for crush combos, dodge ghosts and fire breath. Headlamp lighting, crumbs/dust/confetti VFX, TAA + soft bloom, clickable settings.</td></tr>
<tr><td width="300"><a href="./Arcade/JoustRemix/README.md"><img src="docs/images/joustremix_thumb.png" width="280" alt="Joust Remix"></a><br><a href="./Arcade/JoustRemix/README.md"><strong>Joust Remix</strong></a></td><td>Modern remake of Williams Joust (1982). Flap-to-fly jousting over a lava lake, eggs that hatch into tougher knights, a lava troll, cooked riders with flapping wings, ember and clash VFX, TAA and soft bloom, clickable settings.</td></tr>
<tr><td width="300"><a href="./Arcade/RobotronRemix/README.md"><img src="docs/images/robotron_remix.png" width="280" alt="Robotron Remix"></a><br><a href="./Arcade/RobotronRemix/README.md"><strong>Robotron Remix</strong></a></td><td>Robotron: 2084 (1982) remake: twin-stick arena shooter with homing Grunts, indestructible Hulks, Spheroids and Enforcers, Brains, and last-human-family rescues.</td></tr>
<tr><td width="300"><a href="./Arcade/PongRemix/README.md"><img src="docs/images/pong_remix.png" width="280" alt="Pong Remix"></a><br><a href="./Arcade/PongRemix/README.md"><strong>Pong Remix</strong></a></td><td>Modern remake of Atari Pong (1972). 1P vs AI and local 2P, first to 11 win-by-2, cooked paddles/ball, trails, sparks, HDR + TAA + soft bloom, clickable settings.</td></tr>
<tr><td width="300"><a href="./Arcade/BattlezoneRemix/README.md"><img src="docs/images/battlezoneremix_thumb.png" width="280" alt="Battlezone Remix"></a><br><a href="./Arcade/BattlezoneRemix/README.md"><strong>Battlezone Remix</strong></a></td><td>Modern first-person tank remake of Atari Battlezone (1980). Cooked tanks &amp; mountains, radar, HDR + TAA + soft bloom, clickable settings.</td></tr>
<tr><td width="300"><a href="./Arcade/BubbleBobbleRemix/README.md"><img src="docs/images/bubblebobbleremix_thumb.png" width="280" alt="Bubble Bobble Remix"></a><br><a href="./Arcade/BubbleBobbleRemix/README.md"><strong>Bubble Bobble Remix</strong></a></td><td>Modern remake of Taito Bubble Bobble (1986). Trap monsters in bubbles and pop them in chains for fruit, EXTEND letter bubbles, a wrap-through floor, Baron von Blubba on hurry-up, cooked 3D dragon, monsters and bubbles, pop VFX with dynamic lights, HDR, TAA and soft bloom, clickable settings.</td></tr>
<tr><td width="300"><a href="./Arcade/DonkeyKongRemix/README.md"><img src="docs/images/donkeykongremix_thumb.png" width="280" alt="Donkey Kong Remix"></a><br><a href="./Arcade/DonkeyKongRemix/README.md"><strong>Donkey Kong Remix</strong></a></td><td>Faithful 3D remake of Nintendo Donkey Kong (1981). The intro climb and girder stomp, all four original stages (25m barrels, 50m conveyors and cement pies, 75m elevators and springs, 100m rivets) with the original layouts, US stage order, bonus timer, hammers, fireballs and firefoxes, plus the stage-clear and ending cutscenes. Cooked 3D Mario, Kong and Pauline, a night-city backdrop, fire and smash VFX, TAA, soft bloom, and an F3 collider overlay.</td></tr>
<tr><td width="300"><a href="./Arcade/PangRemix/README.md"><img src="docs/images/pangremix_thumb.png" width="280" alt="Pang Remix"></a><br><a href="./Arcade/PangRemix/README.md"><strong>Pang Remix</strong></a></td><td>Faithful 3D remake of Mitchell's Pang (1989, a.k.a. Buster Bros.). Split bouncing balloons with the harpoon wire across 50 stages in the 17 world locations of the arcade, with steel and breakable glass blocks, ladders, power-wire, double wire, vulcan, clock and dynamite power-ups, and every stage audited to be completable. Painted backdrops, pop VFX, TAA, soft bloom, and an F3 collider overlay.</td></tr>
<tr><td width="300"><a href="./Arcade/BombermanRemix/README.md"><img src="docs/images/bombermanremix_thumb.png" width="280" alt="Bomberman Remix"></a><br><a href="./Arcade/BombermanRemix/README.md"><strong>Bomberman Remix</strong></a></td><td>Faithful 3D remake of Hudson Soft's Bomberman (1983/1985). Bomb through the 31 x 13 brick maze with chain-reaction blasts, find the exit door and power-ups under the bricks, and clear every enemy before the 200-second timer runs out. A scrolling camera like the NES version, cooked 3D Bomberman and enemies, flame and brick VFX, TAA, soft bloom, and an F3 collider overlay.</td></tr>
<tr><td width="300"><a href="./Arcade/OutRunRemix/README.md"><img src="docs/images/outrunremix_thumb.png" width="280" alt="Out Run Remix"></a><br><a href="./Arcade/OutRunRemix/README.md"><strong>Out Run Remix</strong></a></td><td>Faithful 3D remake of Sega's Out Run (1986). Drive the red convertible across the original 15-road map, choose a branch at every real 3D fork, and reach one of the five goals before the timer runs out, with a course map of the route you've taken. TAA, soft bloom, and an F3 collider overlay.</td></tr>
<tr><td width="300"><a href="./Arcade/1942Remix/README.md"><img src="docs/images/1942remix_thumb.png" width="280" alt="1942 Remix"></a><br><a href="./Arcade/1942Remix/README.md"><strong>1942 Remix</strong></a></td><td>Faithful 3D remake of Capcom's 1942 (1984). Fly the P-38 "Super Ace" from Midway (stage 32) to Tokyo (stage 1) with carrier take-offs and landings, twin guns, three evasive loops per stage, red formations that drop POW power-ups, escorts, bombers and shoot-down bonuses. Banking planes, glowing enemy fire, islands and clouds over the Pacific, TAA, soft bloom, and an F3 collider overlay.</td></tr>
<tr><td width="300"><a href="./Arcade/MarbleMadnessRemix/README.md"><img src="docs/images/marblemadnessremix_thumb.png" width="280" alt="Marble Madness Remix"></a><br><a href="./Arcade/MarbleMadnessRemix/README.md"><strong>Marble Madness Remix</strong></a></td><td>Faithful 3D remake of Atari's Marble Madness (1984). Roll your marble down the six isometric races (Practice to Ultimate, with the reversed-gravity Silly Race) against the clock, with height-field marble physics, falls that shatter it, and leftover seconds carried into the next race. TAA, soft bloom, and an F3 collider overlay.</td></tr>
<tr><td width="300"><a href="./Arcade/ArkanoidRemix/README.md"><img src="docs/images/arkanoidremix_thumb.png" width="280" alt="Arkanoid Remix"></a><br><a href="./Arcade/ArkanoidRemix/README.md"><strong>Arkanoid Remix</strong></a></td><td>Faithful 3D remake of Taito's Arkanoid (1986). Steer the Vaus through 32 rounds of bricks with silver and gold bricks, the capsule power-ups, enemies from the gates and DOH in round 33, with arcade scoring and smooth interpolated ball motion. Chrome frame, TAA, soft bloom, and an F3 collider overlay.</td></tr>
<tr><td width="300"><a href="./Arcade/GauntletRemix/README.md"><img src="docs/images/gauntletremix_thumb.png" width="280" alt="Gauntlet Remix"></a><br><a href="./Arcade/GauntletRemix/README.md"><strong>Gauntlet Remix</strong></a></td><td>Faithful 3D remake of Atari's Gauntlet (1985). Choose Thor the Warrior, Thyra the Valkyrie, Merlin the Wizard or Questor the Elf, each with their own stats, and fight down through the dungeon against monsters and their generators, with keys, food, potions and health that drains over time. TAA, soft bloom, and an F3 collider overlay.</td></tr>
<tr><td width="300"><a href="./Arcade/SpyHunterRemix/README.md"><img src="docs/images/spyhunterremix_thumb.png" width="280" alt="Spy Hunter Remix"></a><br><a href="./Arcade/SpyHunterRemix/README.md"><strong>Spy Hunter Remix</strong></a></td><td>Faithful 3D remake of Bally Midway's Spy Hunter (1983). Drive the G-6155 Interceptor down an endless road and river, destroy the enemy agents and spare the civilians, with the Free Cars timer, the weapons van, the boathouse dock where the car becomes a speedboat, the Mad Bomber helicopter and changing seasons. TAA, soft bloom, and an F3 collider overlay.</td></tr>
<tr><td width="300"><a href="./Arcade/GalaxianRemix/README.md"><img src="docs/images/galaxianremix_thumb.png" width="280" alt="Galaxian Remix"></a><br><a href="./Arcade/GalaxianRemix/README.md"><strong>Galaxian Remix</strong></a></td><td>Faithful 3D remake of Namco's Galaxian (1979). The 46-alien convoy sways and flaps while aliens peel off to loop and dive at the Galaxip, flagships take red escorts with them, and divers that miss fly back to the convoy, with the arcade scoring. Banking ships, missile and spark trails, a gas giant over a scrolling starfield, TAA, soft bloom, and an F3 collider overlay.</td></tr>
</table>

## Getting started

### 1. Get the projects

Clone the repo:

```bash
git clone https://github.com/christoskaramou/PhasmaProjects.git
```

Or download it as a zip from the GitHub page (**Code > Download ZIP**) and extract it.
Either way, put it beside your PhasmaEngine folder (see the layout below).

### 2. Get the Phasma Engine

**Prebuilt binaries.** The engine's [`latest` prerelease](https://github.com/christoskaramou/PhasmaEngine/releases/tag/latest)
("Development Build", rebuilt from `master`) ships:

- [PhasmaEngine-Full-Windows.zip](https://github.com/christoskaramou/PhasmaEngine/releases/download/latest/PhasmaEngine-Full-Windows.zip) - Vulkan and DX12
- [PhasmaEngine-Full-Linux.tar.gz](https://github.com/christoskaramou/PhasmaEngine/releases/download/latest/PhasmaEngine-Full-Linux.tar.gz) - Vulkan

**From source.** Clone with submodules (Tracy is one):

```bash
git clone --recurse-submodules https://github.com/christoskaramou/PhasmaEngine.git
```

Then configure and build with one of the CMake presets in `CMakePresets.json`:

| Configure preset | What you get | Output folder |
|---|---|---|
| `ninja` / `vs` | Editor + core only, the fastest build | `build-ninja` / `build-vs` |
| `ninja-physics` / `vs-physics` | + Jolt Physics | `build-ninja-physics` / `build-vs-physics` |
| `ninja-webgpu` / `vs-webgpu` | + the PhasmaWebGPU layer | `build-ninja-webgpu` / `build-vs-webgpu` |
| `ninja-full` / `vs-full` | WebGPU + Physics | `build-ninja-full` / `build-vs-full` |
| `ninja-full-tracy` / `vs-full-tracy` | Full + Tracy profiler | `build-ninja-full-tracy` / `build-vs-full-tracy` |

`ninja-*` presets use Ninja Multi-Config; `vs-*` use Visual Studio 2022 (x64). Each one has
`-debug`, `-release`, `-relwithdebinfo` and `-minsizerel` build presets. For example:

```bash
cmake --preset ninja-physics
cmake --build --preset ninja-physics-release
```

This gives you `build-ninja-physics/Release/` with `PhasmaLauncher`, `PhasmaEditor`, `PhasmaPlayer`
and friends. That is the exact build Prism Tetris's launcher expects.

### 3. Folder layout

Keep the two checkouts side by side. The arcade games' `run.cmd` / `run.ps1` scripts walk up from their
own folder and use the first `PhasmaEngine` checkout they find beside a parent folder (set `PHASMA_ENGINE`
to override). Prism Tetris (`Arcade\PrismTetris`) uses the same upward search, needs the `build-ninja-physics` Release build and refuses to start without it.

```mermaid
graph TD
    repos["repos/"] --> engine["PhasmaEngine/"]
    repos --> projects["PhasmaProjects/"]
    engine --> build["build-ninja-physics/Release/<br/>PhasmaLauncher, PhasmaEditor, PhasmaPlayer"]
    projects --> arcade["Arcade/"]
    arcade --> game["NeonBreakout/ (any arcade game)"]
    game --> manifest["phasma_project.json"]
    game --> assets["Assets/ (Scenes, Scripts, Textures)"]
    game --> run["run.cmd / run.ps1"]
```

```text
repos/
  PhasmaEngine/
    build-ninja-physics/Release/   PhasmaLauncher.exe, PhasmaEditor.exe, PhasmaPlayer.exe, RuntimeAssets/
  PhasmaProjects/
    Arcade/
      NeonBreakout/
        phasma_project.json
        Assets/Scenes/main.pescene
        run.cmd
        run.ps1
    Warbound/, VoxelCraft/, ...
```

### 4. Run a project

**With the launcher (easiest).** Start `PhasmaLauncher`, open the **Project** picker and select a
project folder (the one with `phasma_project.json`). Pick a startup scene from `Assets/Scenes` if the
manifest doesn't set one. The launcher writes your choice to `phasma_settings.json` next to the
executable, and `PhasmaEditor`, `PhasmaPlayer` and `PhasmaAnimator` all open that project.

**In the editor.** Once the project is selected, `PhasmaEditor` opens it. Pick the graphics API with
`PhasmaEditor --api vulkan` (default) or `PhasmaEditor.exe --api dx12` (Windows only).

**PhasmaPlayer directly.** Write `phasma_settings.json` next to the executable yourself. Use forward slashes on Windows:

```json
{
    "project_path": "C:/path/to/PhasmaProjects/Arcade/NeonBreakout/",
    "project_manifest": "C:/path/to/PhasmaProjects/Arcade/NeonBreakout/phasma_project.json",
    "startup_scene": "Assets/Scenes/main.pescene"
}
```

**The game scripts (the new games).** PacManRemix, PitfallRemastered, NeonInvaders, MissileCommand,
NeonAsteroids, NeonCombat, NeonBreakout, FroggerRemix, RiverRaidRemix and the eleven new remixes
(Galaga, Centipede, Tempest, Defender, Q*bert, Dig Dug, Joust, Robotron, Pong, Battlezone, Bubble Bobble) live in `Arcade\` and each have a
Windows `run.cmd` (a wrapper around `run.ps1`):

```powershell
.\Arcade\NeonBreakout\run.cmd
# or
powershell -File .\Arcade\NeonBreakout\run.ps1 -Api vulkan -Display 1
```

`run.ps1` takes the newest `PhasmaEngine\build*\Release\PhasmaPlayer.exe` that has `RuntimeAssets`
beside it. It copies it to a private runtime folder at `%LOCALAPPDATA%\PhasmaGames\<game>`, writes that
copy's own `phasma_settings.json`, and launches it. This way your editor's settings are never touched.
The log goes to `PhasmaEngine.log` in that folder.

**Prism Tetris.** `Arcade\PrismTetris\run.cmd` (or `run.ps1 -Port 8876`) needs `PhasmaEngine\build-ninja-physics\Release`.
It builds a runtime copy in `PhasmaEngine\build-prism-tetris\player`. To race Jev, it also needs
`build-game-driver\Release\PhasmaGameDriver.exe` (build it with `Phasma/GameDriver/build.ps1` in the engine).
In the game, Enter plays solo and V races Jev.
