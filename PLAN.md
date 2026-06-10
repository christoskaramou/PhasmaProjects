# PhasmaSpace — Solar System Demo Implementation Plan

> **STATUS 2026-06-10: Tasks 0–7 COMPLETE.** Demo ships: cold start auto-loads the scene,
> director tracks Earth with the follow camera, orbits Horizons-verified, ~1,000 fps
> (RTX 4080 Super, Vulkan, render_scale 0.75). Deviations from the plan as written:
> - Node transforms are **methods on the handle** (`h:set_position(...)`), not a `node` table.
> - Module loading uses `fs.read` + `load` with `assets_path` (ATH pattern) — `dofile` can't see project assets.
> - `node.set_script` / `skybox.load` get absolute `assets_path ..` paths; textures stay relative ("Textures/Solar/...").
> - Engine support assets (Shaders, PassInfo, Fonts, Icons, SplashScreen, Objects, Materials, Particles) must be
>   copied into the project — `Path::Assets` fully remaps to the project (SplashScreen/IBL LUT crash otherwise).
> - Added beyond plan: **camera follow mode** in the director (exposed `follow`, `follow_distance`) — a static
>   default camera can't keep a moving planet framed; this is the Space-Engine-style fix.
> - Builder made idempotent (deletes prior SolarSystem tree, dedups lights, removes default directional light).
> - Sun = black base + emissive ×25 + bloom_strength 1.2 / range 2.5 (saved in scene settings).
> - Manifest `startup_scene` resolves against project ROOT → value is `Assets/Scenes/solar_system.pescene`.
> - **Task 8 COMPLETE (2026-06-10, second pass):** 8a Earth night lights (emissive nightmap ×5.0 — visually
>   tuned on the night side; faint day-side presence accepted), 8b cloud sphere ×1.012 (luminance→alpha bake
>   via tools/bake_earth_clouds.py, own spin at 30 h, free limb-haze bonus), 8c Galilean moons (Io/Europa/
>   Ganymede/Callisto, real radii/periods, flat tints, orbits ×2.5 cosmetic — `moons` list + `dist_scale`
>   replaced the single-`moon` shape in planets.lua/builder/director). 8d orbit lines stays a dead end.
>   38-node scene, settled fps ≥1300 (instantaneous fps reads right after load/geometry edits are hitch
>   frames — sample spaced, settled).
> - **TRUE SCALE since 2026-06-11 (user decision, supersedes Decision 1 and the scale reference below):**
>   `RADIUS_SCALE = 1`, `SUN_RADIUS_SCALE = 1`, Galilean `dist_scale` removed — sizes, distances, and
>   orbits all real. Navigation relies on the clickable body markers + follow camera.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Project rule overrides (engine CLAUDE.md):** NEVER `git commit` — leave changes for the user to review. No C++ is modified. Verification is via the running editor (Editor MCP `execute_lua` / screenshots) — there is no Lua test harness.
>
> Supersedes `PhasmaEngine/docs/superpowers/plans/2026-06-10-solar-system-demo.md` (deleted): the demo is now a **standalone project repo** (this one), loaded via the engine's project system, exactly like ATH.

**Goal:** The 8 planets + Moon + Saturn's rings orbiting per real JPL ephemerides, real NASA-derived textures, a Gaia star-map sky, with time acceleration — pure Lua + assets, zero engine changes.

**Architecture:** A one-shot Lua builder creates the scene procedurally and saves `Assets/Scenes/solar_system.pescene` (paths resolve into this project because `ApplyProjectSelectionAssetsRoot` remaps `Path::Assets` when `phasma_settings.json` points at the project). A per-node director script on the `SolarSystem` root advances a simulated Julian date and drives positions via E.M. Standish's Keplerian elements. Scale: 1 u = 10⁴ km, radii ×10, sun ×3 → Neptune at ~450k u where float32 is still clean; no floating origin.

**Tech Stack:** PhasmaEngine Lua bindings (`scene`, `node`, `material`, `lights`, `skybox`, `fs`), `uv_sphere`/`plane` primitives, existing Bloom/TAA/Tonemap, infinite reverse-Z camera. Asset prep: PowerShell + Python (OpenCV, Pillow).

**Module loading (ATH-proven pattern):** `dofile` is cwd-relative (exe dir) and does NOT see project assets. Use the engine `fs` binding + injected `assets_path` global:

```lua
local function load_module(path)  -- path is Assets-relative, e.g. "Scripts/solar/ephemeris.lua"
    local source = fs and fs.read and fs.read(path) or nil
    if not source then error("PhasmaSpace: missing module " .. path) end
    local chunk, err = load(source, "@" .. assets_path .. path, "t", _ENV)
    if not chunk then error(err) end
    return chunk()
end
```

---

## Decisions locked in (user-approved 2026-06-10)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Scale fidelity | Scaled units (1 u = 10⁴ km, radii ×10, sun ×3); real-scale floating origin deferred |
| 2 | Phase 1 scope | Content only — no engine changes, no atmospheric scattering |
| 3 | Where it lives | **Standalone repo `C:\Users\Christos\repos\PhasmaSpace`** (user decision, supersedes in-repo option) |
| 4 | Texture residency | 2k tracked; 8k + EXR git-ignored, fetched via script |
| 5 | Sky | NASA SVS Deep Star Maps 2020 → `.hdr` |

**Accepted simplifications:** tilt about orbital X (not true pole RA/Dec); circular inclined Moon orbit; no inter-planet shadows; artistic light falloff.

## Scale reference

1 AU = 14,959.79 u · Earth orbit ≈ 14,960 u, r = 6.371 u · Moon 38.44 u from Earth, r = 1.737 u · Saturn rings 74.5→140.2 u · Neptune orbit ≈ 449,850 u · Sun r = 208.7 u.
Ecliptic→engine: `engine.x = ecl.x`, `engine.z = ecl.y`, `engine.y = ecl.z` (ecliptic north = +Y).

## File structure

```
phasma_project.json            # manifest: version/name/assets/startup_scene   [done]
README.md                      # run instructions, scale model, data licenses  [done]
.gitignore                     # 8k_*, *.exr, editor_config.json               [done]
tools/
  fetch_solar_textures.ps1     # SSS 2k (tracked) + -EightK upgrade + SVS star map
  convert_starmap.py           # EXR -> Radiance .hdr (OpenCV)
  bake_saturn_rings.py         # ring strip -> 2048^2 RGBA annulus (Pillow)
Assets/
  Scripts/solar/
    ephemeris.lua              # Standish Table-1 + Kepler solver
    planets.lua                # radii/tilts/rotations/textures/rings/moon data
    build_solar_system.lua     # ONE-SHOT builder -> saves the .pescene
    solar_director.lua         # per-node script: time + orbits + spins
  Textures/Solar/              # 2k_*.jpg, saturn_rings.png, starmap_2020_4k.hdr
  Scenes/solar_system.pescene  # generated by Task 5
```

Verified engine API surface: `scene.add_empty_node/attach_primitive/add_point_light` (SceneBindings.cpp:137-204), `node.set_position/set_rotation/set_scale/set_parent/set_script/get_children/get_name` (SceneNodeBindings.cpp), `material.set / set_texture(h, slot, type, path) / set_render_type` — texture types `base_color|emissive|normal|metallic_roughness|occlusion` (MaterialBindings.cpp:394), `lights.set_point_light(index, pos, color, intensity, radius)` (LightBindings.cpp:106), `skybox.load(path)` (SkyboxBindings.cpp:17), `save_scene(name)` → `Path::Assets + "Scenes/" + name`, `fs.read` + `assets_path` (ATH `against_the_hero.lua:19-21`), `Path::Assets` remap (ProjectSelection.cpp:132-137).

## Task 0: Environment + binding pre-flight

- [ ] Locate a working engine build: `PhasmaEditor.exe` under `PhasmaEngine/build-ninja-full/Release/` or `build-ninja-full-tracy/Release/`.
- [ ] Write `phasma_settings.json` next to the exe: `{ "project_path": "C:/Users/Christos/repos/PhasmaSpace" }`.
- [ ] Launch editor, confirm log shows the active project root = PhasmaSpace (App.cpp logs project root/source at startup). Missing-icons warning is known-harmless (ATH).
- [ ] Resolve in the live editor (MCP `execute_lua`), record answers as comments atop `build_solar_system.lua`:
  - `node.set_script` path form (inspect an ATH scene node or set+`node.get_script` round-trip).
  - `exposed {}` / `get_exposed` syntax in per-node scripts (grep ATH scripts for the live pattern first).
  - `material.set(h, 0, "emissive", X)` — vec3 or vec4 factor (MaterialBindings.cpp:269-288).
  - `node.set_rotation` arg — vec3 Euler degrees vs quat (ATH uses Euler tables).
  - `skybox.load` path root — Assets-relative vs absolute (SkyboxBindings.cpp:17-28).

## Task 1: Asset fetch & conversion

- [ ] `tools/fetch_solar_textures.ps1` — downloads to `Assets/Textures/Solar/`: 2k set `2k_sun, 2k_mercury, 2k_venus_atmosphere, 2k_earth_daymap, 2k_earth_nightmap, 2k_earth_clouds, 2k_moon, 2k_mars, 2k_jupiter, 2k_saturn, 2k_uranus, 2k_neptune (.jpg)` + `8k_saturn_ring_alpha.png` from `https://www.solarsystemscope.com/textures/download/<file>`; `-EightK` switch for the 8k set; star map `https://svs.gsfc.nasa.gov/vis/a000000/a004800/a004851/starmap_2020_4k.exr`. If a pattern-derived URL 404s, get exact links from the source pages — do not skip files.
- [ ] `tools/convert_starmap.py` — OpenCV (`OPENCV_IO_ENABLE_OPENEXR=1`) EXR→`starmap_2020_4k.hdr`, `*20.0` brightness boost (tuning knob, Task 6).
- [ ] `tools/bake_saturn_rings.py` — sample the ring strip's radial profile into a 2048² RGBA annulus `saturn_rings.png`; `inner_frac = 74500/140220`; transparent hole + corners; handle vertical-strip orientation via `strip.shape` check.
- [ ] Run all three; verify 13 textures + `.hdr` + `saturn_rings.png` exist; report sizes (flag `.hdr` > 60 MB → suggest LFS).

## Task 2: `ephemeris.lua`

- [ ] Cross-check Standish Table 1 values against https://ssd.jpl.nasa.gov/planets/approx_pos.html before committing them to the file (a transposed digit silently corrupts orbits).
- [ ] Write `Assets/Scripts/solar/ephemeris.lua`: `M.J2000 = 2451545.0`, `M.AU_KM = 1.495978707e8`, `M.elements` = the 8-planet table `{a, aDot, e, eDot, I, IDot, L, LDot, varpi, varpiDot, Omega, OmegaDot}` (rates per Julian century), `solve_kepler(M_deg, e)` Newton iteration with `e* = math.deg(e)`, `M.heliocentric(name, jd)` → J2000-ecliptic x, y, z in AU (mod-360 mean anomaly folded to [-180,180], standard ω/Ω/I rotation).
- [ ] **Acceptance test vs JPL Horizons** (MCP `execute_lua`): Earth @ JD 2461202.5 (2026-06-10) → `r ≈ 1.015 AU ±0.005`, ecliptic lon `≈ 259.4° ±1.0`; repeat Mars + Neptune vs Horizons vectors (https://ssd.jpl.nasa.gov/horizons/app.html, center @sun, ecliptic J2000). >2° off = transcription error. Note: `math.atan(y, x)` on Lua 5.4, `math.atan2` on 5.1.

## Task 3: `planets.lua`

- [ ] Write the data table (NSSDC fact sheets): Mercury 2439.7 km / 1407.6 h / 0.03°; Venus 6051.8 / −5832.5 / 177.36; Earth 6371.0 / 23.9345 / 23.44 + moon {1737.4 km, a 384,400 km, 27.321661 d, incl 5.14°}; Mars 3389.5 / 24.6229 / 25.19; Jupiter 69,911 / 9.925 / 3.13; Saturn 58,232 / 10.656 / 26.73 + rings {74,500→140,220 km}; Uranus 25,362 / −17.24 / 97.77; Neptune 24,622 / 16.11 / 28.32. Sun 695,700 km. Constants: `KM_PER_UNIT=1e4`, `RADIUS_SCALE=10`, `SUN_RADIUS_SCALE=3`, `AU_UNITS`, helpers `radius_units(km)`, `dist_units(km)`, `TEX="Textures/Solar/"`.
- [ ] Sanity via MCP: `radius_units(6371) == 6.371`.

## Task 4: `solar_director.lua` (per-node script on `SolarSystem` root)

Node-name contract (builder creates, director consumes): `<Name>_orbit` → `<Name>_tilt` → `<Name>` (+ `<Name>_rings`, `Moon_orbit` → `Moon`).

- [ ] Write the director: `load_module` ephemeris+planets; exposed `time_scale=2.0` (sim days / real second), `epoch_jd=2461202.5`; `init` walks `self` children recursively into a `handles[name]` map; `update(dt)` advances `sim_days`, sets each `<Name>_orbit` position from `heliocentric()` (ecliptic→engine mapping), spins `<Name>` about local Y by `(jd−J2000)/rot_period` turns (negative `rot_h` = retrograde), Moon: circular inclined local orbit + tidally-locked spin.
- [ ] Verified as part of Task 5 (needs the scene).

## Task 5: `build_solar_system.lua` + generate the scene

- [ ] Write the one-shot builder: root `SolarSystem`; Sun = `uv_sphere`, scale 208.7 u, `base_color`+`emissive` texture `2k_sun.jpg`, emissive factor ~6; `scene.add_point_light()` + `lights.set_point_light(0, vec3(0,0,0), vec3(1,.96,.9), 50.0, 1e6)`; per planet: `_orbit` (initial heliocentric pos) → `_tilt` (Euler X = tilt) → body sphere (scale = radius_units, roughness 1, metallic 0, base_color tex); Saturn `_rings` = `plane` scaled `outer_u*2/10`, `saturn_rings.png`, `alpha_blend` (add flipped twin if backface-culled); Earth `Moon_orbit`+`Moon`; `skybox.load("Textures/Solar/starmap_2020_4k.hdr")`; `node.set_script(root, <Task-0 path form>)`; `save_scene("solar_system.pescene")`.
- [ ] Run once via MCP `execute_lua` in the project-loaded editor; expect `[solar] scene built and saved`, zero `PE_WARN/PE_ERROR`; `.pescene` lands directly in `Assets/Scenes/` (Path::Assets = project).
- [ ] **Visual verification:** reload editor (startup scene now exists) → screenshots: Saturn rings = concentric bands w/ gap, visible tilt; Moon beside Earth; sun bloom; `time_scale=50` → planets crawl + spin. Screenshot each planet.

## Task 6: Look & lighting tuning

- [ ] Bloom on, TAA on (settings via MCP); tune point-light intensity/radius (radius must stay ≥ 1e6 u to reach Neptune): Mercury not blown out, Earth day/night readable, Neptune visible. If outer planets unreadably dark → emissive floor `vec4(0.02,0.02,0.025,1)` on planet materials (documented cheat).
- [ ] Star map brightness: adjust `*20.0` in `convert_starmap.py`, re-run, re-`skybox.load`, re-save scene.
- [ ] Re-run builder after constant changes; re-screenshot.

## Task 7: Smoke + perf + handoff

- [ ] Cold-start smoke: fresh editor launch (project settings in place), 18 s liveness, log tail shows scene load + zero `PE_ERROR`.
- [ ] `engine.get_metrics().fps` at sun close-up / Saturn close-up / full-system view; Release expectation: hundreds of fps (~40 draws, 2k textures); < 100 fps = investigate before declaring done.
- [ ] Update README if controls/paths changed; store MemPalace drawer (wing `phasmaengine`, room `phasmaspace`): scale constants, Task-0 binding answers, any surprises.
- [ ] Final checkpoint: full `git status` + draft commit message (no commit): `Add real-data solar system demo (Standish ephemeris, NASA/SSS textures, Gaia sky)`.

## Task 8 (STRETCH — only on explicit go-ahead)

8a Earth night lights (emissive `2k_earth_nightmap.jpg`); 8b cloud sphere ×1.01 `alpha_blend`, slower spin; 8c Galilean moons (Io 421,800 km/1.769 d/1821.6 km, Europa 671,100/3.551/1560.8, Ganymede 1,070,400/7.155/2634.1, Callisto 1,882,700/16.689/2410.3 — orbits ×2.5 cosmetic, else inside Jupiter's ×10 radius); 8d orbit lines — **known dead end** with current primitives (torus can't take per-axis major/minor radii); needs a line-strip primitive → phase 3.

## Out of scope (phase 3+)

Atmospheric scattering pass (engine work, biggest visual upgrade — **now planned: see `ATMOSPHERE_PLAN.md`**), real-scale floating origin, terrain LOD from USGS DEMs, HYG point-star billboards, lens flare, eclipses/planet shadows, asteroid belt via particles.
