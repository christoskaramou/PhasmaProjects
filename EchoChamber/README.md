# Echo Chamber

A 3D puzzle about sound. A horn on the edge of a tiled chamber fires one pulse. Place your pieces, send
it, and make the pulse ring every bell, in numbered order, before it fades.

Run it with `run.cmd` (needs a Release build of `../PhasmaEngine`).

## How it plays

- The pulse moves one cell per step. Each step costs 1 strength and each bounce or split costs 1 more;
  the PULSE meter shows what is left. Pillars, the board edge and the horn absorb it.
- A bell rings as the pulse passes under it. Bells must ring 1, 2, 3...: reaching an unrung bell too
  early spoils the send. Bells already rung can be passed again freely.
- Pieces (each chamber gives exactly the pieces its solution uses):
  - **Reflector**: turns the pulse 90°. Click a placed one to flip it ( `/` or `\` ).
  - **Fork**: splits the pulse into two, out to the left and right of the way it came in. Both halves
    travel at once, so timing decides the order.
  - **Resonator**: refills a fading pulse to full strength, once per send.
  - **Damper**: stops a pulse dead, to cut a fork branch short before it rings a bell too early.
- After a failed send the pulse's trail stays on the board as a faint echo, so you can see where it went.
- Stars: 3 for the first send with no hints, 2 within three sends, otherwise 1. Each hint costs a star.

Controls: click to place / flip, right-click to take back, 1-4 pick a piece, F flips the next reflector,
Space sends (and skips a send in progress), H hint, R clear the board, PgUp / PgDn change chamber
(up to the furthest reached), M mute, Esc (or the MENU button) the main menu.

The game opens on the main menu: CONTINUE / PLAY, CHAMBERS, HOW TO PLAY, SETTINGS (the shared Arcade
settings menu) and QUIT, with the chamber turning slowly behind it. CHAMBERS is a paged grid (30 per page)
of every unlocked chamber with its best stars; click one to play it. Esc in the menu returns to the
chamber. Best stars per chamber are saved in `Assets/Save/echo_stars.txt`.

## Motion

A new chamber assembles itself: the camera flies in, tiles rise out of the slab in a wave from the
horn, pillars grow, the horn spins into place and the bells drop onto their yokes and swing. Pieces drop
in and bounce, lift away when taken back, and reflectors turn on their pedestal when flipped. During a
send the horn kicks back, mirrors ring on their stands, fork tines blur, resonator rings spin up,
dampers squash, struck pillars flash and shudder, rung bells swing and hop, and a wrong bell shudders
red. A solved chamber resonates: every bell rings again in a wave while the camera leans in, then the
star card arrives. At rest the bells sway, light runs along the pillar bands and the dampers breathe.
The HUD slides in, tool cards rise one by one, badges and pips pop on each ring.

## Chambers

Chambers are generated from their number, so chamber N is always the same. Boards grow from 7x5 to
14x9 and bells from 2 to 7; resonators appear from chamber 4, forks from 5, dampers from 8. The
generator (`echo_rules.lua`) grows a solution route, simulates it, hangs bells along the real route
numbered by when the pulse reaches them, adds pillars off the route, sets the horn's strength to the
least that works plus a little slack, and drops every piece the route does not need. Damper chambers
use a deliberate set-up: one fork branch loops back across the other branch's straight line, with a
bell at the crossing and a lower-numbered bell on the loop, so without the damper the bell rings early.
The furthest chamber reached is saved in `Assets/Save/echo_chamber.txt`.

## Files

- `Assets/Scripts/echo_rules.lua`: rules, pulse simulation, chamber generator (pure Lua).
- `Assets/Scripts/echo_world.lua`: the 3D chamber, pieces, bells, pulse playback, picking, camera.
- `Assets/Scripts/echo.lua`: flow, input and the runtime-UI HUD.
- `Assets/Scripts/Lib/settings_menu.lua`: the shared settings menu (unchanged copy).
- `tools/gen_meshes.py`: builds the meshes (lathed bells, horn and pedestals; rounded pillars, tiles,
  cushions) as OBJ, cooks them to `Assets/Objects/*.pemesh` with PhasmaCook, and writes
  `Assets/Scenes/main.pescene` with one hidden template node per mesh. Bells and the ghost / hint
  previews get their own mesh entries over the same cooked file, because a material belongs to a mesh
  entry and is shared by every node using it. `--scene-only` rewrites the scene without cooking.
- `tools/make_sounds.py`: every sound, synthesized and run through a synthetic stone-chamber reverb (stereo,
  32 kHz): church-bell partials as slightly detuned pairs with a clapper strike (bells 1-7 are a
  pentatonic run), glass tinks off the mirrors, a tuning fork for the fork, a singing bowl for the
  resonator, felt and stone thuds, a breathy horn blast, a cracked bell for a wrong ring, a tam-tam,
  a carillon for a win, and a 23 s seamless room-tone loop played on the music bus (MUSIC VOLUME in
  settings). Frequent sounds have several takes the game picks between, since the engine plays files
  without per-play pitch or volume.
- `tools/make_assets.py`: the white HUD icons that are tinted in game.

## Tests

From this folder, with the engine's `luajit.exe`:

- `tests/rules_test.lua`: chambers 1-60 are solvable with exactly their pieces and not by the bare
  horn, every piece kind appears, and the send rules (order, fading, resonator, damper, fork, walls,
  inventory, hints) hold.
- `tests/view_smoke.lua`: runs the real game script against stubbed engine APIs: picking, placing and
  flipping by clicks, failing and winning sends, hints, clearing, chamber switching and node leaks.

Both are in the repo test pool (`.testpool/catalog.json`).
