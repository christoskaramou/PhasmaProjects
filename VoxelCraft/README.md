# VoxelCraft

Minecraft-style voxel playground for PhasmaEngine.

Start scene: `Assets/Scenes/voxelcraft.pescene`
Smoke scene: `Assets/Scenes/voxelcraft_smoke.pescene`
Persistence smoke: `Assets/Scenes/voxelcraft_persistence_smoke.pescene`

## Persistence

`voxelcraft_controller.lua` passes `save_dir = "VoxelWorlds/voxelcraft"` to `voxel.create`. Edited
column sections are written as sparse `.pevcol` overlays under
`Assets/VoxelWorlds/voxelcraft/columns/`.

- **Save on quit:** press Esc or close the player window (`VoxelWorld::Destroy` flushes touched columns).
- **Save on unload:** columns that stream out beyond `load_radius + unload_margin` are persisted first.
- **Manual flush:** `voxel.save_all()` from Lua (not bound to a key in the controller).

Local `Assets/VoxelWorlds/` is gitignored.

## Controls

- Mouse: look
- WASD: move
- Shift: run
- Space: jump
- Left mouse / Q: break block
- Right mouse / E: place block
- 1/2/3: select stone/dirt/grass

This project reuses the voxel playground scene and script from `Sample` as a standalone project so it can be pinned or launched without touching engine `DefaultProject`.
