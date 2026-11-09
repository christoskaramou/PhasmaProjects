# Topple

Set up chain reactions of dominoes, then tip the first one. Three modes from the title card:

## Free Build (Enter)

Thousands of dominoes anywhere in a living room: across the oak floor and the rug, under and on top of the coffee
table, up and over a staircase of books, on the side table and the bookshelf. Tip the first one and watch the chain
run, with the camera following the falling front. A first visit opens on a ready-made chain to tip.

- **Tools** (`1`-`9`, `0`): **Draw** (drag a path; start on a line's end to carry it on), **Line** (press, drag, release),
  **Spiral** (press at the middle, drag out to size it; Shift winds it the other way), **Field** (press where it starts,
  drag the way it runs: it fans out to its width, `[` `]`), **Erase** (drag a brush over dominoes, `[` `]`),
  **Start** (click the domino the tip knocks over; click again to push it the other way), **Ball** (click near a domino:
  the wider the gap, the harder the hit), **Swing** (press where the bob swings lowest, drag the way it swings; a hit on
  its red latch lets it go), **Switch** (click to set one, then click the domino it starts; click a switch to choose
  it, again for the lamp), **Ramp** (press on one surface and drag onto a higher one).
- **Paint**: rainbow or one colour (`P` or the swatches).
- **Camera**: right-drag turns, middle-drag or Shift+right-drag moves, wheel zooms, `WASD` / arrows move, `Q` `E` turn,
  `Tab` top view, `Home` resets.
- **Run**: `Space` tips (and replays when it is done), `R` stands everything up, `Z` slow motion, `F` follow camera.
  After a run, red rings mark where a chain stopped short of dominoes still standing.
- **Editing**: right-click removes one domino, `Backspace` / `Ctrl+Z` undo, `Ctrl+Y` redo, `C` twice clears.
- **Saving**: the room autosaves; SAVE / LOAD keep three slots and the sample build. Your longest chain and the
  milestones (100, 500, 1,000, 2,500, 5,000 in one chain) are kept.
- `H` hides the controls, `Esc` settings, `M` mute, MENU back to the title. The box holds 6,000 dominoes.

## The Great Hall (G)

A floor 120 m square for up to five million dominoes, and a sample of one million waiting on your first visit.

- **Tools** (`1`-`9`, `8` is **Split**: press on the end of a line and drag, one wave becomes 2 to 6 branches, `[` `]`;
  `9` is **Bell**: click beside a line and it rings when the wave goes past): **Field** (press where it starts, drag the way it runs; `[` `]` width, as wide as the hall),
  **Line**, **Spiral**, **Draw**, **Erase** (`[` `]` brush), **Start** (click the domino the tip knocks over),
  **Picture** (choose a picture or draw one, then press and drag across the floor to lay it out in dominoes; put your own
  PNG or JPEG files in `Assets/Pictures`).
- **Samples**: 1, 2.5 or 5 million dominoes in a fan painted as a sunburst.
- **Run**: `Space` tips, the camera follows the wave and pulls back as it widens (`F` frees it), `Z` slow motion, `R` stands
  everything up. `Backspace` / `Ctrl+Y` undo and redo, `C` twice clears.
- A build is saved as the shapes that made it, so the autosave stays a few lines however many dominoes it holds.

The hall's dominoes are not scene nodes: the engine's `hinge_field` draws them all from one buffer and animates each fall
from the moment it starts, so the work per frame follows the wave, not the number of dominoes.

## Table Run (T)

A chain reaction of wooden toys on a games table, a score to beat.

- **Draw** lines of dominoes by dragging across the felt (start near the end of a line to carry it on). The first
  domino you place is the one the tip knocks over (a brass arrow marks it).
- **Bells** hang beside a line: each one the chain passes adds x2 to the multiplier. Score = every toy that falls,
  times the multiplier at that moment, so ring bells early.
- **Springs** jump a gap, **rockets** fly 5 ahead and knock over everything they land among, **marbles** roll down
  their chute and across the felt to the next toy. Houses (a cottage, a townhouse and a farmhouse, miniature model
  houses) fall far and score 5; blocks and trees stop a chain.
- Each table gives you three tips to reach its target. Clear it for coins, spend them at the **toy shop** (more toys,
  more dominoes, charms that bend the rules), then a harder table. Miss a target and the run ends.

Controls: drag to draw, `1`-`5` tools, press and drag to aim a spring / rocket / marble, right-click removes a toy,
`Backspace` undo, `C` clear, `Space` / `Enter` tip, `F` fast-forward a tip, `Esc` settings, `M` mute, MENU to the title.

Run: `run.cmd` (Windows; finds the sibling `PhasmaEngine` build, see the repo wiki index).

## How it is made

**Free Build.** The room is real 3D from `tools/gen_room.py` (textured floor, rug, wallpaper, a window, sofa, coffee
table, bookshelf, plant, the book staircase), which also writes `Assets/Scripts/free_room.lua`: the surfaces you can
build on and the solid furniture, shared by the rules and the world. Walls and ceiling are single faces looking into
the room, so the camera sees through them from outside (a dollhouse cut-away) while the shadow pass, which draws
both sides, lets the sun in only through the window (the pane is a Transmission mesh: no depth shadow). The sun
re-aims `Key`, directional light 0, which casts the shadows; Table Run gets it back. The sun's shadows are one fixed
4096 map over the whole room (the engine's `shadow_fixed_bounds`), not camera-fitted cascades, which disagreed with
each other in a room this size, so the window light came and went as the camera moved. The window frame, curtains and
pane are never hidden (a hidden node casts no shadow); only other wall decor is, when the camera is behind its wall.
The chain is worked out up front in pure Lua (`topple_free.lua`): a binary-heap event queue over a spatial grid, each
domino pivoting on its front edge onto whatever it meets first (dominoes, furniture, low ledges it slides over), so a
4,000-domino chain simulates in about 12 ms (LuaJIT) / 16 ms (in the player). Every domino is one pooled scene node
(body and pips as two mesh refs) shown with `set_visible` and posed in batches with `scene.set_positions` /
`set_rotations`; only dominoes in motion are posed each frame.

**Table Run.** The table, room, desk lamp and chalk board are a Cycles render from the game's fixed camera
(`tools/make_backdrop.py`, graded like the approved concept); the game shows it unlit on a quad that fills the view.
Every toy is real 3D on top (`tools/gen_meshes.py` cooks the meshes and writes the scene), lit by the lamp's lights
and a room HDR, with soft shadows cast on the pictured felt from the lamp's position. The houses are Tripo models
(`tools/make_houses.py`): Blender reference renders in the concept's palette, generated in Tripo Studio (via the
jev-browser skill, 20,000 polys requested, about 17,000 delivered; meshoptimizer can bring them down later), then
squared up, scaled and textured for the game, their colours pulled toward grey
like the other toys' paints. The chain is simulated in pure Lua (`Assets/Scripts/topple_rules.lua`) as a
time-ordered event queue, then animated.

| Tool | Makes |
| --- | --- |
| `tools/gen_meshes.py` | toy meshes (`Assets/Objects`), `Assets/Scenes/main.pescene` (`--scene-only`: scene only) |
| `tools/gen_room.py` | Free Build's room meshes, textures (`room_*.png`, `Skybox/day.hdr`), `Scripts/free_room.lua`, the scene (`--no-cook`) |
| `tools/make_houses.py` | `refs`: house reference pictures; `import <tripo_dir>`: `Assets/Objects/house_*.pemesh`, `Assets/Textures/house_*.png`, `icon_house.png`, the scene |
| `tools/make_backdrop.py` | `Assets/Textures/backdrop.png` (Blender 5.x) |
| `tools/furniture_refs_scene.py`, `tools/concept_layout.lua`, `tools/make_room_concept.py` | the Free Build room concept: furniture reference pictures for Tripo, a mid-run domino layout from the game's rules, and the Cycles render with the Tripo furniture (outputs stay in the work folder you pass) |
| `tools/make_icons.py` | tray, shop and Free Build tool icons from the game's own meshes (Blender 5.x) |
| `tools/make_textures.py` | shadow sprites, placement markers, `Assets/Skybox/room.hdr` |
| `tools/make_sounds.py` | `Assets/Audio/*.wav`, except the domino hits |
| `tools/make_clacks.py` | `Assets/Audio/clack*.wav`, cut from CC0 recordings (`Assets/Audio/CREDITS.txt`) |

The camera numbers in `gen_meshes.py`, `backdrop_scene.py` and `topple_world.lua` (`W.CAM`) must stay identical.

Tests (run from this folder with the engine's `luajit.exe`): `tests/rules_test.lua` (Table Run's chain rules,
scoring, tables and shop), `tests/free_test.lua` (Free Build's placement, shapes, chain, saving and scale) and
`tests/view_smoke.lua` (the game script, both modes, against stubbed engine APIs).

Font: Lilita One by Juan Montoreano, SIL Open Font License 1.1 (`Assets/Fonts/LilitaOne-OFL.txt`).
