# Banners & Borders — progress log
Original title "Banners & Borders" (web-checked 2026-10-29: no existing game/trademark found; only Rocket League cosmetic
terminology "banners and borders" and an unrelated tabletop "Marching Banners").
Project: /workspace/games/banners_borders  (MCP port 9157, Xvfb :57). Screens: /workspace/banners_borders_shots/

## Step 1 — scaffold
- Copied tool scripts from gatebreaker (box_run/stop, lua.sh, mcp.py, shot.sh, cook_all, build_lua, meshlib, palette,
  audiolib, gen_fx*, gen_ui, gen_scene, simtest) + bin/ (engine build) + Lib/particles.lua, settings_menu.lua.
- pip installed shapely, mapbox_earcut, pyshp, scipy (user site).
- Natural Earth (public domain) zips in /workspace/games/banners_data (10m admin0/admin1, 50m land, 10m lakes).

## Step 2 — map pipeline (tools/geo.py, mapspecs.py, gen_maps.py)
- Natural Earth admin-0/admin-1 → Albers equal-area → normalised (median region ≈ 6.4 u) → smoothed, inset bevelled
  region tiles + land base + context countries + per-map sea texture (shallows, wave bands, foam).
- Maps: greece 13, balkans 19, italy 18, iberia 16, europe 47, usa 41 regions. Lua data in src/gen_map_*.lua
  (terrain grid, neighbours, coast flags, decor slots). Previews in _preview/.

## Step 3 — core game (Lua, src/0*.lua → project/Assets/Scripts/main.lua via tools/build_lua.sh)
- Sim (04_sim.lua): regions produce up to cap, troop streams of individual 3D figures, 1:1 combat, neutral garrisons,
  region types capital/fort/port/mine + terrain (hills slow/defend), mid-path clashes between opposing streams,
  abilities airdrop / forced march / frost / barrage (unlock L2/L3/L5/L7), 5 meta upgrades bought with coins.
- AI (04b_ai.lua): personalities steady, warlord, vulture (preys on weakened fights), empire (boss), passive (tutorial).
- Render/HUD/UI: tabletop diorama (bevelled tiles, painted sea, context land), moderate bloom + TAA, badges with
  readable numbers, capture VFX, mouse menus + full keyboard (arrows/Enter/Esc, 1-4 abilities, Tab cycle).

## Step 4 — SCOPE CHANGE (Christos): global campaign
- Request: maps across every continent at several scales (country → regions, continent → areas, whole world),
  config-only Natural Earth pipeline (~8–40 regions, auto centres/adjacency), 15–25 levels + world finale,
  world-map campaign screen, smooth difficulty curve.
- Clarification: only outlines must be accurate; interior split may be gameplay-driven with invented/neutral names.
- Done:
  - tools/partition.py: area-sampled k-means/Lloyd seeds → Voronoi cells clipped to each outline part, orphan/islet
    merge, sliver merge (<0.3× mean), island_keep threshold so real islands (Sri Lanka, Tasmania, Sicily…) get a cell.
  - name_regions: largest cells pick the most prominent Natural Earth label inside them, else nearest, else flavour
    word; names ASCII-folded, ≤15 chars, "Pradesh"/"Province" stripped. Neutral loose geography only.
  - mapspecs.OUT(title, bbox, k, names|continent, clip…) — a new map is ONE line of config.
  - Equal Earth projection for the world map; Albers elsewhere. Auto ports/mines/forts from coast/hills/degree.
  - 13 new maps: India, China, Japan, Asia, Africa, West Africa, Southern Africa, Australia, New Zealand, Brazil,
    South America, Mexico, The World (+6 originals = 19 maps, all six inhabited continents).
  - 22 levels (8 Europe + 14 new), boss levels: 8 Violet Empire (Europe), 14 Middle Kingdom, 22 One World finale.
  - Level starts can be compass words ("NE", "+" = biggest neighbour) resolved per map — robust to re-partitioning.
  - World campaign screen: Equal Earth parchment world map (tools/gen_worldmap.py), pins per battle with relaxation,
    dotted march path, stars, continent progress strip, info card + March button, Left/Right/Enter.
- GPU fix: the lavapipe player crashed with "Storage buffer size is too big" (combined geometry buffer > 128 MB
  maxStorageBufferRange). Map LOD cut: min segment 0.14, bevel steps 2/1/1, simplify tolerance per map, 1024 sea
  textures, smaller sea padding, no Antarctica context → ~20–25k verts per map land/context.

## Step 5 — balance, AI, screenshots (2026-10-29)
- AI: per-level `spd` (march speed multiplier) decoupled from `reach` (AI only); new *stalled-front* rule: an AI that owns
  >=6 regions with a big army and no reachable target widens its reach to 40 so the empire/warlord crosses oceans (fixes L22 stalemates).
- L15 Silk Road: player moved off a dead-end island chain, 2 AIs, gentler diff (was skilled 0/3).
- L22 One World: Violet empire starts in China, player in Africa; spd 1.6 so the world map plays in ~6-8 min.
- L14/L16/L17/L19 eased slightly (skilled bot lost 1/3 seeds); pars re-derived = ceil10(1.25 x skilled median).
- Full headless sim (tools/simtest.py, fresh save, 5 seeds, bots skilled/casual/idle; times in sim-seconds; stars vs OLD par):

```
L1  First Muster       par  70 | skilled 5/5 t=35,35,35,35,35 *3,3,3,3,3 | casual 5/5 t=52,52,52,52,52 *3,3,3,3,3 | idle 0/5  |
L2  Hellenic Dawn      par 120 | skilled 5/5 t=114,113,119,91,99 *3,3,3,3,3 | casual 3/5 t=424,333,748 *1,1,1 | idle 0/5  |
L3  Aegean Storm       par 150 | skilled 5/5 t=121,106,111,111,101 *3,3,3,3,3 | casual 5/5 t=539,426,600,214,273 *1,1,1,2,1 | idle 0/5  |
L4  Balkan Thunder     par 170 | skilled 5/5 t=144,175,113,139,143 *3,2,3,3,3 | casual 3/5 t=237,213,204 *2,2,2 | idle 0/5  |
L5  Roman Roads        par 180 | skilled 5/5 t=81,81,72,71,83 *3,3,3,3,3 | casual 0/5  | idle 0/5  |
L6  Iberian Tides      par 200 | skilled 5/5 t=109,131,91,129,111 *3,3,3,3,3 | casual 5/5 t=165,184,649,180,219 *3,3,1,3,2 | idle 0/5  |
L7  Continental Clash  par 260 | skilled 5/5 t=310,315,296,386,301 *2,2,2,2,2 | casual 0/5  | idle 0/5  |
L8  The Violet Empire  par 300 | skilled 5/5 t=135,125,131,149,154 *3,3,3,3,3 | casual 0/5  | idle 0/5  |
L9  Gold Coast Gambit  par 200 | skilled 5/5 t=99,102,96,114,89 *3,3,3,3,3 | casual 5/5 t=375,183,253,238,450 *1,3,2,2,1 | idle 0/5  |
L10 Cape of Storms     par 200 | skilled 5/5 t=98,90,95,91,113 *3,3,3,3,3 | casual 3/5 t=176,598,577 *3,1,1 | idle 0/5  |
L11 Sahara to Savanna  par 280 | skilled 5/5 t=138,125,131,159,152 *3,3,3,3,3 | casual 2/5 t=460,405 *1,2 | idle 0/5  |
L12 Monsoon Realms     par 220 | skilled 5/5 t=111,118,114,103,115 *3,3,3,3,3 | casual 1/5 t=584 *1 | idle 0/5  |
L13 Island Shogunates  par 160 | skilled 5/5 t=142,228,132,95,734 *3,2,3,3,1 | casual 2/5 t=389,450 *1,1 | idle 0/5  |
L14 Middle Kingdom     par 260 | skilled 5/5 t=187,178,211,194,142 *3,3,3,3,3 | casual 0/5  | idle 0/5  |
L15 Silk Road          par 180 | skilled 5/5 t=135,112,115,128,129 *3,3,3,3,3 | casual 0/5  | idle 0/5  |
L16 Sunburnt Country   par 200 | skilled 5/5 t=88,146,75,71,78 *3,3,3,3,3 | casual 5/5 t=200,357,117,292,148 *2,1,3,2,3 | idle 0/5  |
L17 Long White Cloud   par 130 | skilled 5/5 t=121,211,92,172,301 *3,1,3,2,1 | casual 0/5  | idle 0/5  |
L18 Amazon Rivers      par 220 | skilled 5/5 t=78,93,80,118,96 *3,3,3,3,3 | casual 0/5  | idle 0/5  |
L19 Andes and Pampas   par 280 | skilled 5/5 t=139,278,142,164,160 *3,3,3,3,3 | casual 3/5 t=548,388,473 *1,2,1 | idle 0/5  |
L20 Sierra Madre       par 180 | skilled 5/5 t=158,103,113,95,113 *3,3,3,3,3 | casual 0/5  | idle 0/5  |
L21 New World          par 300 | skilled 5/5 t=210,199,248,195,207 *3,3,3,3,3 | casual 0/5  | idle 0/5  |
L22 One World          par 480 | skilled 5/5 t=411,351,464,422,492 *3,3,3,3,2 | casual 0/5  | idle 0/5  |
```

New pars: L1 50, L2 150, L3 140, L4 180, L5 110, L6 140, L7 390, L8 170, L9 130, L10 120, L11 180, L12 150, L13 180, L14 240, L15 160, L16 100, L17 220, L18 120, L19 200, L20 150, L21 260, L22 530
- Skilled bot: 110/110 wins (every level winnable from a fresh save). Idle: 0/110 (no level is free).
  Casual bot win rate falls from 100% (L1) to 0% by L14-L22, with breather levels at each new continent (L6, L9, L16).
- Mesh cook: 458 changed meshes OK; ctx_nz was empty (NZ has no neighbouring land) and is skipped (code tolerates a missing ctx).
  Total new geometry ~557k verts / 1.22M idx -> no more lavapipe 'storage buffer too big' crash; player boots on :57.
- UI polish: title no longer wraps, small-button labels fit, help line says Enter/Space.
- Screenshots in /workspace/banners_borders_shots/: title.png, world_campaign_map.png (sample progress set in memory),
  mid_battle_streams.png, capture_vfx.png (staged: troop counts boosted via test hook to make streams visible),
  large_match_world.png (L22), win_screen.png (forced via BB.test.finish). The test save file was deleted afterwards.

## Step 6 — easier casual play, visual fixes, Windows copy (2026-10-29)

### Difficulty
- **Modes** (`D.MODES`, Options → Difficulty): Relaxed, Normal (default) and Hard. Each mode scales AI recruit speed,
  neutral garrisons and their regrowth, your starting army, the AI wake-up delay and AI ability cooldowns. Hard is
  close to the old tuning, eased slightly so the skilled bot still wins the finale 4/5.
- **Per-level soft tables** (`L.soft`, Relaxed and Normal only): L2, L7, L8, L14, L17, L20 and L22.
- **Retry Boost** (`D.RETRY`, `SV.fails`): +12% starting troops and -4% enemy recruit speed per loss on that battle,
  up to 4 losses. It resets on a win, and a "Retry Boost xN" popup shows at battle start.
- **Pars**: blended median, `par = round10((median skilled win time + median casual win time) / 2)` over 5 seeds,
  in Normal mode. A skilled player usually gets 3★ and a casual one 2★.
- **Sims** (`tools/simtest.py`, 5 seeds per level per bot). Normal-mode wins:

| Levels | Skilled | Casual | Idle |
|---|---|---|---|
| L1–L20 | 5/5 each | 5/5 each | 0/5 each |
| L21 | 5/5 | 4/5 | 0/5 |
| L22 | 5/5 | 4/5 | 0/5 |

  - Casual targets met: at least 4/5 on L1–8 and at least 3/5 on L9–22.
  - Hard: the skilled bot wins 5/5 on L1–21 and 4/5 on L22. The casual bot struggles, winning 0–5/5.
  - Relaxed: the casual bot wins 5/5 everywhere and the idle bot wins 0/5.
- Old Normal-equivalent casual wins were 0/5 on L5, L7, L8, L14, L15, L17, L18, L20, L21 and L22.

### Visuals
- **Cloud shadows**: the clouds now float off the board, so their shadows no longer fall on the map as black blots.
- **Black coast patches**: gen_maps runs a morphological closing pass (`CLOSE = 0.32`) on the land and sea meshes,
  and `lod_enabled` is off, so LOD no longer swaps in broken low-poly coasts.
- **Dark tree and peak specks**: scenery is sparser, smaller and lighter.
- **Region tint**: starting and capital regions sometimes showed no owner tint. The cause was a race with the
  deferred material replays at frames 2 and 6. `tiles()` now re-applies the tint for the first 10 frames.
- **Europe pins**: the 8 Europe battles sit on a fixed ring around Europe, with dotted leader lines to their real
  spots. Pin relaxation treats them as anchors.
- **New Zealand**: added "Tasman Sea" and "South Pacific Ocean" captions and an "< Australia · 2,000 km" pointer,
  using the new `sea =` map field drawn by `HUD.badges`. The empty `ctx_nz` mesh is skipped.
- **Map edges**: all 19 maps were checked at the default zoom (0.7). No board edge is cut off.
- The demo battle behind the title and menus no longer shows "X used Y!" or "lost!" toasts.

### Other
- Screenshots in `/workspace/banners_borders_shots/`:
  - New shots: `after_title.png`, `after_world_campaign.png`, `after_mid_battle_europe.png`, `after_greece.png`,
    `after_new_zealand.png`, `after_world_finale.png`.
  - Comparisons: `compare_*.png` and `before_vs_after.png`.
- Tools:
  - Added `tools/fetch_natural_earth.py`, which downloads the map data into `data/`. `geo.DATA` honours `BB_DATA`.
  - Added `tools/build_lua.py`, a cross-platform twin of `build_lua.sh` with byte-identical output.

## Step 7 — dot path, neutral regrowth, menu spacing (2026-10-29)
- **Dot path**: the chevron march preview is replaced by big round dots (`dot`, `dot_bad`, `dot_rim` meshes from
  `tools/gen_meshes.py`). They are opaque glow materials lifted above the board (no alpha blending, no z-fighting),
  evenly spaced every 1.1 units, white with an Azure rim and a travelling pulse, ending in a gold target ring. With no
  valid target they turn grey.
- **Neutral regrowth** (`D.NREGEN = 0.25`/s, `D.NREGEN_WAIT = 5` s): neutrals regrow to their starting garrison
  (`r.n0`). Any arrival or barrage resets the pause (`r.hit`). The badge shows a green regrowth gauge (grey while
  paused); the tooltip shows `n / n0` and "+0.25 / s" or "paused".
- **Rebalance** (Normal, 5 seeds, skilled / casual / idle): L1–L20 5/5 · 5/5 · 0/5; L21 and L22 5/5 · 4/5 · 0/5.
  Only par change: L8 The Violet Empire 140 -> 150. Hard: skilled 5/5 on L1–21 and 4/5 on L22. Relaxed: casual 5/5
  everywhere, idle 0/5 everywhere.
- **Menus**: one font size per tier (`UI.FS` hero/main/small), labels auto-fit on one line with side padding
  (`UI.fit_fs`), 28 px gaps that scale with resolution (`UI.GAP`), the pause menu sits on a parchment card under a
  "Paused" ribbon ("Retreat To Menu" is now "Main Menu"), the victory/defeat card has wider-spaced buttons, and the
  focus outline is thinner so it does not touch neighbours. Toasts and the intro banner are hidden while a dialog is
  open. Checked at 1280x720, 1600x900, 1920x1080, 2560x1440 and 3440x1440.
- README difficulty table fixed: `ivm` is the AI reaction interval, not neutral regrowth.

## Upgrades button and win guard
- **Upgrades on every result screen**: the victory card is Menu · Upgrades · Retry · Next and the defeat card is
  Menu · Upgrades · Retry (200x88 buttons, 32 px gaps, one shared font size). A red badge with a pulsing gold glow
  shows how many upgrades you can afford right now (`D.affordable`). The same badge is on the title War Chest button
  and on a new **Upgrades** button above Back on the World Campaign screen.
- **Shop flow**: from a result screen the War Chest opens over the frozen, finished battle; Back returns to the same
  result card, so Next or Retry is one click away and new upgrades apply to that battle. From the campaign screen
  Back returns to the campaign; from the title it returns to the title (`G.shop_back`).
- **Win guard** (`SIM.step`): a win now needs the battle to have started with at least one enemy faction on the map,
  at least 1 s of battle time, and every enemy faction with zero regions and zero troops on the march. A loss still
  needs the player to lose everything.
- The "0:08 Victory, 0 regions captured" screen was produced by the screenshot test hook `BB.test.finish(true)`,
  which forces a result. The hook now marks `S.forced` and logs `[BB] test hook: forced win/loss`. Unforced play of
  Aegean Storm, Restart from pause and starting after the title demo all ran with no early end, and the stats
  (regions captured, troops sent, largest army) reset at every battle start.

## Edge scrolling replaces click-drag panning
- **Removed**: pressing on empty board / sea and dragging no longer pans the camera (the old `drag.pan` mode in
  `play_input`). A click on empty board now just clears the selection. Clicks only select, send, aim abilities and
  press UI buttons. Right-click still only cancels. There was no mouse-wheel zoom; `Z`/`X` zoom and `WASD`/arrow
  panning are unchanged.
- **Edge scrolling** (`edge_scroll` in `src/08_main.lua`): with the cursor inside the window and within
  `EDGE = clamp(round(18 * SH/1080), 12, 28)` px of an edge (12 px at 720p, 15 at 900p, 18 at 1080p, 24 at 1440p), the camera
  pans that way. Corners pan diagonally (normalised). Speed = 30%..100% of `EDGE_SPEED` (18 world units/s, x map size
  factor `max(1, ez/12)`, / zoom), smoothstep-eased by depth into the margin. The velocity is damped (rate 10/s) and
  dt-scaled, and pan stays clamped to the map bounds. It runs only in `play_input`, so pause, options, menus, results,
  War Chest and the World Campaign screen never scroll. It keeps working while you drag a send.
- Title help line now reads "... · Screen Edges / WASD Pan". README controls table has a "Pan the map" row.

## Mouse-wheel zoom and Lock Mouse to Window
- **Wheel zoom** (`read_wheel` / `zoom_step` in `src/08_main.lua`): each wheel notch multiplies the target zoom `zt`
  by 1.15 (in) or 1/1.15 (out); `zoom` eases to it with `damp(.., 12, dt)` (frame-rate independent). The range is
  0.6..2.6 (was 0.7..2.2); `Z`/`X` still work and drive the same target. The wheel comes from `runtime_ui.get_wheel()`
  (ImGui) because the full-screen UI backdrop captures the mouse and zeroes `input.get_mouse_wheel()`; that is the
  fallback. Test hook: `BB.vwheel = notches`.
- **Zoom toward the cursor**: every frame of the ease the map point under the cursor is unprojected for the old and
  new camera target (`cam_target` / `cam_pl`, `unproject_cam` in `01_core`) and pan shifts by the difference, then pan
  is clamped to the map bounds as before. With the keyboard, zoom is about the screen centre.
  Box test with real X wheel events (xdotool): the point under the cursor stayed at (-3.244, 6.894) after 4 notches
  in and at (14.035, -2.573) after 6 notches out, including mid-ease. 25 notches in stopped at 2.6 and 40 out at 0.6.
  Wheel in pause, options and the campaign screen did not change zoom. The Options menu keeps its own wheel scrolling.
- **Lock Mouse to Window**: new Options toggle (Gameplay, `lock_mouse`, default On, saved in `settings.cfg`).
  `mouse_lock(state)` runs at the end of every update: lock = setting on, state `play`, battle not over and window
  focused. Every change is logged as `[BB] mouse lock ON/OFF (...)`, and the lock is released on Quit.
  **Engine limitation**: the Phasma Lua API has no window grab or confine call and no focus query (only relative mode
  plus `warp_mouse_center`, which hide or recentre the cursor). The game feature-detects `input.set_mouse_grab`
  (or `set_window_grab` / `engine.set_mouse_grab`) and `input.is_window_focused`. Until the engine has them, it logs
  "no window grab" once and the cursor is not confined. With a stubbed grab API on the box the transitions were:
  title off, battle on, focus lost off, focus back on, pause off, resume on, setting off off, battle won off, options off.
  Proposed engine diff: in `Phasma/Runtime/Code/Script/Bindings/Input/InputBindings.cpp`, next to
  `warp_mouse_center`, add `set_mouse_grab(bool)` (`SDL_SetWindowGrab(RHII.GetWindow(), ...)`) and
  `is_window_focused()` (`SDL_GetWindowFlags(..) & SDL_WINDOW_INPUT_FOCUS`). SDL already suspends a grab while the
  window is unfocused, so Alt-Tab keeps working.
- Title help line: "... · Wheel Zoom · Edges / WASD Pan". README has a Zoom row and a Lock Mouse note.
