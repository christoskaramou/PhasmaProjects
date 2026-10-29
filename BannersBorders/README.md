# Banners & Borders

A real-time territory-conquest strategy game for **Phasma Engine** (C++ Vulkan/DX12, Lua gameplay). Regions grow troops;
you march them across a tabletop diorama of the world in streams of tiny 3D soldiers, meeting enemy columns mid-road,
from Greece to a final war for the whole planet.

## Run
- Windows: `run.cmd` (or `powershell -ExecutionPolicy Bypass -File run.ps1 [-Api vulkan|dx12]`).
- Expected layout: `C:\Users\Christos\repos\PhasmaProjects\BannersBorders\` with this folder's `project\`
  (`project\phasma_project.json`, `project\Assets\...`) and the engine at `..\..\PhasmaEngine` (override with
  `PHASMA_ENGINE`). The script copies the player into a private runtime folder, so editor settings are not touched.

## How to play
| Action | Mouse | Keyboard |
|---|---|---|
| Select your regions | click / drag across them | `Q` selects all |
| March | click a target (or right-click) | |
| Send half / all | ratio button in the tray | `Enter` or `Space` toggles 50% / 100% |
| Abilities | tray buttons | `1` Airdrop · `2` Forced March · `3` Frost · `4` Barrage |
| Pause | top-right button | `P` / `Esc` |
| Pan the map | move the cursor to a screen edge | `WASD` / arrows |
| Zoom | mouse wheel (zooms toward the cursor) | `Z` in · `X` out |
| Menus | click | arrows + `Enter`, `Esc` back |
| World map | click a pin, then **March!** | `Left`/`Right` browse, `Enter` march |

- **Lock Mouse to Window** (Options › Gameplay, default On): during a live battle the cursor is meant to stay inside
  the window so edge scrolling is easy; it is released in pause, menus, results and when the window loses focus
  (Alt-Tab works). The current Phasma Lua API has no window-grab call, so until the engine adds one
  (`input.set_mouse_grab`) the setting is saved but the cursor is not confined.

- Owned regions produce troops up to a cap; neutral regions hold garrisons. Combat is one soldier for one soldier.
- **Neutral regrowth**: a damaged neutral garrison regrows +1 troop every 4 s (much slower than owned production) back
  up to its starting size, after a 5 s pause since it was last attacked. A small gauge under its badge fills green
  while it regrows (grey while paused), and the hover card shows `troops / starting garrison`.
- **March preview**: while you aim, a line of big round dots runs from your selection to the target, with a gentle
  travelling pulse and a gold target ring. Dots turn grey when there is no valid target.
- Region types: **Capital** (+40% recruits, +50% cap, sturdy walls), **Fort** (defenders count 1.5x), **Port**
  (troops sail at full speed; others are slowed crossing water), **Mine** (+6% recruits everywhere, abilities recharge
  15% faster). Terrain: hills slow attackers and strengthen defenders.
- Opposing streams clash on the road. Over-extending leaves home regions empty, and the AI will notice.
- AI factions: Crimson (steady), Amber (warlord), Jade (vulture), and the boss **Violet Empire**.
- Stars come from your time against par. Coins buy 5 permanent upgrades (Recruitment, Swift Boots, Veteran Start,
  Bastions, Quartermaster) in the War Chest. Open it from the title, from the Upgrades button on the World Campaign
  screen, or from the Upgrades button on every victory/defeat card; a red badge shows how many you can afford. Back
  from a result card returns to that card. A short guided tutorial runs in battle 1.

## Difficulty
- **Options → Difficulty**: **Relaxed**, **Normal** (default) or **Hard**. It applies from the next battle you start.

| Mode | AI recruit speed | AI reaction interval | Neutral garrisons | Your starting army | AI wake-up delay | AI ability cooldowns |
|---|---|---|---|---|---|---|
| Relaxed | 72% | x1.8 (slower) | 80% | x1.5 | +12 s | x1.6 |
| Normal | 84% | x1.4 (slower) | 90% | x1.3 | +7 s | x1.3 |
| Hard | 95% | x1.1 | 100% | x1.1 | +3 s | x1.1 |

- Relaxed and Normal also apply small per-level easings on the boss and stalemate-prone battles (2, 7, 8, 14, 17,
  20, 22).
- **Retry Boost**: each loss on a battle adds one boost level, up to 4. Each level gives +12% starting troops and
  -4% enemy recruit speed. A "Retry Boost" popup shows it when the battle starts. It resets when you win that battle.
- **Stars**: 3 stars at or under par time, 2 stars within 1.6x par, otherwise 1 star.

## Campaign: 22 battles across six continents
| # | Battle | Map | Continent |
|---|---|---|---|
| 1 | First Muster (tutorial) | Greece | Europe |
| 2 | Hellenic Dawn | Greece | Europe |
| 3 | Aegean Storm | Greece | Europe |
| 4 | Balkan Thunder | The Balkans | Europe |
| 5 | Roman Roads | Italy | Europe |
| 6 | Iberian Tides | Iberia | Europe |
| 7 | Continental Clash | Europe | Europe |
| 8 | The Violet Empire (boss) | Europe | Europe |
| 9 | Gold Coast Gambit | West Africa | Africa |
| 10 | Cape of Storms | Southern Africa | Africa |
| 11 | Sahara to Savanna | Africa | Africa |
| 12 | Monsoon Realms | India | Asia |
| 13 | Island Shogunates | Japan | Asia |
| 14 | Middle Kingdom (boss) | China | Asia |
| 15 | Silk Road | Asia | Asia |
| 16 | Sunburnt Country | Australia | Oceania |
| 17 | Long White Cloud | New Zealand | Oceania |
| 18 | Amazon Rivers | Brazil | South America |
| 19 | Andes and Pampas | South America | South America |
| 20 | Sierra Madre | Mexico | North America |
| 21 | New World | United States | North America |
| 22 | One World (final boss) | The World | World |

## Map pipeline (adding a map is config)
`tools/mapspecs.py` holds one line per map, for example:
```python
def japan(): return OUT('Japan', (129, 30.8, 146, 45.6), 10, names=['Japan'], hills_ll=[(138, 36.2)])
```
`python3 tools/gen_maps.py japan` then:
1. Builds the outline: Natural Earth admin-0 countries by name or continent, clipped to a lon/lat box.
2. Projects it: Albers equal-area for countries and continents, Equal Earth for the world.
3. Splits it into regions (`tools/partition.py`): area-weighted k-means/Lloyd seeds, Voronoi cells clipped to the
   outline, islands kept as their own region when they are big enough, slivers and islets merged.
   **Only the outline is geographic; the interior split is gameplay-driven.**
4. Names each region after the most prominent Natural Earth label inside it, falling back to the nearest label or a
   neutral flavour word.
5. Writes the meshes (bevelled region tiles, land base, neighbouring countries for context, painted sea texture) and
   `src/03m_<map>.lua`. That file holds the centres, adjacency, coast flags, terrain grid, title, lon/lat for the
   campaign pin, and auto-placed ports, mines and forts.
6. Then run `tools/cook_all.sh`, `tools/gen_scene.py` and `tools/build_lua.sh`, and reference the map key in
   `src/03b_levels.lua`. Level starts can be compass words (`"NE"`, `"C"`, `"+"` = next to the previous start), so
   they survive re-partitioning.

**Natural Earth data is not shipped** (about 82 MB). The game itself does not need it: maps are already baked
into `src/03m_*.lua` and `project/Assets`. You only need it to regenerate maps. Run
`python3 tools/fetch_natural_earth.py` (Python 3, any OS). It downloads the five layers (1:10m admin-0, admin-1,
lakes; 1:50m admin-0, land) from naciscdn.org into `data/`. Or set `BB_DATA` to an existing folder. The generators
also need `pip install numpy shapely pyshp`.

The world-map backdrop is `tools/gen_worldmap.py` (Equal Earth, Natural Earth 1:50m).

## Legal and attribution
- **Title**: "Banners & Borders" is an original title. A web search on 2026-10-29 found no game or trademark with
  this name. The working title "Marching Banners" was dropped because it matched an existing tabletop product. The
  genre (territory/stream conquest, as in many games) is not protectable; this game uses no names, art, UI, logos,
  text or audio from any other game.
- **Art, audio, UI**: all procedurally generated by the scripts in `tools/` (meshes, textures, icons, sounds).
- **Geography**: [Natural Earth](https://www.naturalearthdata.com/) — admin-0 countries (1:10m, 1:50m), admin-1
  states/provinces (1:10m), land and lakes. Natural Earth is **public domain** ("No permission is needed to use
  Natural Earth. Crediting the authors is unnecessary." — naturalearthdata.com/about/terms-of-use). We credit it
  anyway: *Made with Natural Earth. Free vector and raster map data @ naturalearthdata.com.*
- Region names are loose, neutral geographic labels or invented flavour words. Factions are colours (Azure, Crimson,
  Amber, Jade, Violet) and do not stand for any real state. Borders are a gameplay abstraction, not political claims.

## Project layout
- `project/` — the Phasma project (`Assets/Scripts/game.lua`, which is built from `src/`, plus Objects, Textures,
  Audio and Scenes).
- `src/` — Lua sources: core, look, data, maps, levels, sim, AI, render, UI, HUD, main.
- `tools/` — generators, cook and run helpers, and the headless balance simulator (`tools/simtest.py`;
  `SIMMODE=1|2|3` picks Relaxed/Normal/Hard, `SIMBOT=skilled,casual,idle`, `SIMSEEDS=5`, `SIMLVL=7`).
  `python3 tools/build_lua.py` (or `build_lua.sh`) rebuilds `project/Assets/Scripts/game.lua` from `src/`.
  The Windows copy leaves out the Linux-box-only helpers (`box_run.sh`, `box_stop.sh`, `lua.sh`, `shot.sh`,
  `mcp.py`, and `cook_all.sh`, which needs the Linux `bin/PhasmaCook` and Xvfb). Cooked meshes are already in
  `project/Assets/Objects`. The copy also leaves out `meshsrc/` (38 MB of raw OBJ intermediates; `gen_maps.py`
  and `gen_meshes.py` regenerate them), the `_preview/` debug PNGs, the Linux `bin/` and the Natural Earth data.
- `FUN.md` explains the design choices. `PROGRESS.md` is the build log.
