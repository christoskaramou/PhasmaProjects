# PhasmaSpace — Atmospheric Scattering Implementation Plan (Hillaire 2020)

> **STATUS 2026-06-10: DRAFT — no code written.** Awaiting user approval of *Decisions to
> confirm* below. Companion to `PLAN.md` (demo plan of record). Unlike PLAN.md, this slice
> is **engine work** (new render pass in PhasmaEngine) plus demo integration — engine repo
> rules apply: work uncommitted on `master`, `clang-format -i` every touched `.cpp/.h`,
> update `docs/wiki/architecture/rendering.md` + `log.md` and run wiki lint, no test-only
> engine code, `graphify update .` after edits.

**Goal:** Physically based atmosphere on Earth (presets for Mars/Venus later): blue limb
from space, red-orange terminator band, aerial perspective hazing the day side and
attenuating things seen through the limb (night lights, orbit ribbons, the Sun itself).
Technique: Hillaire 2020, *A Scalable and Production Ready Sky and Atmosphere Rendering
Technique* (EGSR) — the same model as UE4 SkyAtmosphere.

**Scope cut (what we implement vs. the paper):** transmittance LUT + multiple-scattering
LUT + **per-pixel ray march** for the composite. The paper's sky-view LUT and aerial-
perspective froxel volume are optimizations for cameras *inside* the atmosphere looking
around; the demo camera is in space essentially always, so they are deferred (stretch).
Per-pixel march is also the paper's own high-quality path for space views.

## Architecture

A new global fullscreen pass `AtmospherePass : IRenderPassComponent` in
`PhasmaRuntime/Code/RenderPasses/`, registered at **order 750** — after
`LightTransparent` (700), before `SSR` (1000) — reading `viewport` (lit scene) +
`depthStencil`, writing `viewport` in place (SSRPass pattern: copy RT to a sampled
image, barrier, fullscreen triangle back onto the RT). Everything on `viewport` is
pre-tonemap linear HDR and flows through Upsample→Tonemap to `display`, so the result
appears in `take_scene_screenshot` automatically.

Per-pixel shader, per atmosphere body (≤4): ray–sphere intersect the top-of-atmosphere
shell; on miss, passthrough (early-out — zero cost when no limb on screen); on hit,
march 32 steps from entry to exit-or-depth-hit, accumulating in-scatter (Rayleigh +
Mie + multi-scatter LUT term) and transmittance, then composite
`color = sceneColor * T + L_inscatter`. Opaque depth (infinite reverse-Z; sky = 0)
caps the march so surfaces get aerial perspective and the limb glows over the star map.

Two LUTs per body, baked by compute on param change (not per frame), stored as 4-layer
array images created by the pass: transmittance 256×64 RGBA16F, multi-scatter 32×32
RGBA16F — exactly the paper's resolutions.

**Sun model:** direction per body = `normalize(sunPos − bodyCenter)` (point light 0 — the
demo's sun at origin; directional approximation is exact to ~0.005° at 1 AU). In-scatter
is multiplied by `gSettings.lights_intensity` — the same global the director's photographic
auto-exposure drives — so the atmosphere is metered with the followed body and never
blows out or vanishes as exposure swings (Mercury 0.10 ↔ Neptune ~893).

**Units:** the engine pass is scale-agnostic — all params in **world units**. The demo
is now TRUE SCALE (radii ×1 since 2026-06-11), so the conversion is uniform:
`KM_PER_UNIT = 10⁴ km/u`, β[1/u] = β[1/km] × 10⁴, H[u] = H[km] / 10⁴, Earth's mesh
radius 0.6371 u = exactly 6371 km is the ground radius, top = +100 km = +0.01 u.
Camera position is rebased to the body's local frame **on the CPU** before upload
(one subtraction at float32, not per-pixel at 450k-unit magnitudes). Note the thin
shell (0.01 u) at float32: marching in body-local km (not world units) keeps step
precision comfortable.

## Decisions to confirm (user)

| # | Decision | Recommendation |
|---|----------|----------------|
| 1 | First-light scope | Earth only; Mars/Venus presets as stretch (data-only once the pass exists) |
| 2 | Config surface | Lua registry `atmosphere.set_body(index, params)` mirroring `lights.set_point_light` — **not** serialized into `.pescene`; the director re-registers at load (same pattern as orbit polylines, which also don't round-trip). Only the global `bool atmosphere` toggle serializes |
| 3 | Pass placement | Order 750 on `viewport` (atmosphere participates in SSR/TAA/bloom). Alternative — post-TAA ~1450 — avoids any TAA limb ghosting but the limb would alias; start at 750, revisit only if Task 6 shows ghosting |
| 4 | Body budget | 4 max (fixed UBO array + 4-layer LUTs) |
| 5 | Perf budget | ≤15% settled-fps cost at the Earth follow view (≈1300 → ≥1100), ~0 when no atmosphere shell on screen |

## Earth parameters (Bruneton/Hillaire standard, real km)

Ground 6371 (mesh radius), top +100. Rayleigh β_s=(5.802, 13.558, 33.1)e-3 /km, H 8.0 km.
Mie β_s=3.996e-3, β_a=4.4e-3 /km, H 1.2 km, g=0.8. Ozone absorption (0.650, 1.881,
0.085)e-3 /km, tent layer centered 25 km, width 30 km. Known wrinkle: the cloud sphere
(×1.012 ≈ +76 km) sits *inside* the shell but is alpha-blended before order 750, so cloud
pixels get aerial perspective for the *surface* distance behind them — accepted (clouds
are in the atmosphere; the error is a few km of extra haze).

## Verified engine API surface

- Pass interface: `IRenderPassComponent` — `Init / UpdatePassInfo / CreateUniforms /
  UpdateDescriptorSets / Update / DeclareInputs / DeclareOutputs / ExecutePass / Resize /
  Destroy`, protected `m_attachments` + `m_passInfo` (PhasmaCore/Code/ECS/Component.h:33-57).
- Registration: ordered table `kSceneRenderGraphPasses[]` (id, order, name, component
  member ptr) at PhasmaRuntime/Code/Render/SceneRenderGraph.cpp:37; components created in
  `CreateSceneRenderGraphPassComponents()` (:191-216); registered via `AddSceneRenderGraph
  Passes()` with per-pass enable lambdas (:174); enable gating in
  `UpdateSceneRenderGraphPassStates()` (gate like SSR: `gSettings.atmosphere`).
- Fullscreen template: **SSRPass** (PhasmaRuntime/Code/RenderPasses/SSRPass.{h,cpp}) —
  `GetRenderTarget("viewport")` / `GetDepthStencilTarget("depthStencil")` /
  `CreateFSSampledImage(true)` (:17-26); code-built PassInfo with `Shader::Create({
  sourcePath, entryPoint, stage, defines })`, Quad.hlsl VS + custom PS, no depth
  (:37-46); per-frame UBO `Buffer::Create` CPU_TO_GPU + `Copy` at `RHII.GetFrameIndex()`
  (:49-102); `CopyImage`→`ImageBarrier`→`BeginPass`→`Draw(3,1,0,0)` (:113-133).
- RT roles (grep-verified): `viewport` = lit pre-upsample (LightPass.cpp:118, SSRPass,
  FXAA, TAA); `display` = post-upsample (Tonemap, Bloom, DOF, MotionBlur, Grid, Particle).
- Compute + storage images: `Shader::Create` with `PE_SHADER_STAGE_COMPUTE` (Culling
  pattern, CullingPass.cpp:55); transient-compute precedent = skybox prefilter
  (EquirectangularToCubemap/PrefilterCubemap, docs/wiki/architecture/rendering.md) —
  **pitfall:** cached `Pipeline` treats `PassInfo` as construction-only; keep LUT
  PassInfos persistent, not transient. `Image::Create(ImageDesc)` with
  `PE_IMAGE_USAGE_STORAGE | SAMPLED`, `Image::CreateUAV`, `RGBuilder::ReadCompute/
  WriteCompute`, `CommandBuffer::ImageBarrier` all available (Image.h:70-95,
  RenderGraph.h:31-32).
- Sun + exposure: point light 0 from `scene.GetPointLights()` (ScenePointLight,
  Scene.h:61-80); `lights_intensity` already flows GlobalSettings → LightPassUBO →
  `cb_lightsIntensity` (LightPass.h:14, LightPass.cpp:259); `physical_point_falloff`
  (LightPass.h:19) is the just-landed settings-plumbing example.
- Settings pattern (copy it for `bool atmosphere = false`): field Settings.h:114 →
  bool map SettingsBindings.cpp:22 → write SceneSerializer.cpp:202 / read :333-334.
- Depth reconstruction: `GetPosFromUV(uv, depth, cb_invViewProj)` handles infinite
  reverse-Z w≈0 (Assets/Shaders/Common/Common.hlsl:66-82); camera is infinite reverse-Z
  (Camera.h:64).
- Lua registry precedent: `lights.set_point_light(index, pos, color, intensity, radius)`
  (LightBindings.cpp:106).
- **Project asset remap gotcha:** `Path::Assets` remaps fully to the project — new engine
  shaders MUST be copied into `PhasmaSpace/Assets/Shaders/` or the pass cannot compile
  when the demo project is active (root cause of past SplashScreen/IBL-LUT boot crash).

## File structure (new)

```
PhasmaEngine/
  PhasmaRuntime/Code/RenderPasses/AtmospherePass.{h,cpp}
  PhasmaEditor/Assets/Shaders/Atmosphere/
    AtmosphereCommon.hlsl        # medium sampling, phase fns, LUT param mapping
    TransmittanceLutCS.hlsl      # 256x64, per-layer
    MultiScatterLutCS.hlsl       # 32x32, per-layer (64-dir sphere integral)
    AtmospherePS.hlsl            # per-pixel march + composite (VS = Common/Quad.hlsl)
  PhasmaEditor/Code/.../AtmosphereBindings.cpp   # or extend LightBindings — Task 4
PhasmaSpace/
  Assets/Shaders/Atmosphere/*    # copy of the above (Path::Assets remap)
  Assets/Scripts/solar/atmosphere.lua  # per-body real-km params + unit conversion
```

## Task 0: Pre-flight (verify before coding)

- [ ] Re-verify pass orders + free order slot 750; confirm where Upsample hands
      `viewport`→`display` so a 750 write reaches screenshots (UpsamplePass.cpp).
- [ ] Confirm `SceneRenderGraphPassId` enum + `SceneRenderGraphPassComponents` member
      addition points (SceneRenderGraph.h:14-71) and the gating switch in
      `UpdateSceneRenderGraphPassStates()`.
- [ ] Confirm an existing **array** storage image or accept 4 separate LUT images
      (check ImageDesc arrayLayers + CreateUAV per-layer on BOTH backends — DX12 UAV
      of a texture array layer is the risk item).
- [ ] Confirm how SSRPass's descriptor reflection picks up a sampled image written by
      compute earlier in the same frame (barrier sufficiency on DX12).
- [ ] Pick UBO layout: globals (invViewProj, camPos-rebased flag, lightsIntensity,
      bodyCount) + per-body 7×vec4 — verify against `RHII.AlignUniform`.

## Task 1: Pass scaffolding (engine, no scattering yet)

- [ ] `GlobalSettings::atmosphere = false` + Lua map + .pescene serialize (3-line
      pattern above); GUI checkbox in GlobalWidget next to existing toggles.
- [ ] AtmospherePass skeleton: enum id, component member, create, register order 750,
      gate on `gSettings.atmosphere`; reads viewport+depth, debug shader = constant
      tint into a 200px corner quad (proof of insertion, screenshot-visible).
- [ ] Build `PhasmaEditorModule PhasmaEditor`; verify tint on **Vulkan AND DX12**
      (user's default is DX12); verify Init/Destroy across settings toggle and hot
      reload; verify zero fps cost when disabled.

## Task 2: LUT bakes

- [ ] `TransmittanceLutCS.hlsl` — paper §4/Bruneton mapping (r, μ) → optical depth to
      top; `MultiScatterLutCS.hlsl` — paper §5.2, 64-direction sphere integral, Ψ_ms.
- [ ] Pass-side: dirty flag per body slot; on `atmosphere.set_body` param change,
      re-dispatch both LUTs for that layer next frame (persistent compute PassInfos —
      see cached-pipeline pitfall).
- [ ] Verify: temporary debug blit of both LUTs to screen corner; transmittance must
      show the classic horizon falloff band; sample-check T(ground, zenith) ≈
      (0.92, 0.82, 0.65) ±10% vs. reference (Bruneton fig.); remove debug blit after.

## Task 3: Per-pixel march + composite

- [ ] `AtmospherePS.hlsl`: reconstruct world ray via `GetPosFromUV` (depth 0 = sky →
      march to shell exit); per body: rebase to body-local, intersect shell, 32-step
      march, in-scatter = Rayleigh+Mie phase × T(sample→sun) × shadowed(ground-intersect
      toward sun) + Ψ_ms term, composite `scene*T + L`.
- [ ] Multiply L by `lights_intensity`; calibration constant tuned so Earth day-limb
      luminance ≈ day-surface luminance at the standard follow view.
- [ ] Off-screen-center precision check at Neptune distances (no shimmer from rebase).

## Task 4: Lua binding

- [ ] `atmosphere.set_body(index, { center=vec3, ground_radius, top_radius,
      rayleigh_scatter=vec3, rayleigh_h, mie_scatter, mie_absorb, mie_h, mie_g,
      ozone_absorb=vec3, ozone_center, ozone_width, intensity })` — world units;
      `atmosphere.clear(index)`. Follow LightBindings registration pattern; params
      land in the pass's body registry, LUT dirty on change (center/intensity changes
      must NOT dirty the LUTs — per-frame updates are free).

## Task 5: Demo integration

- [ ] `Assets/Scripts/solar/atmosphere.lua`: Earth real-km table + km→unit conversion
      (×/÷1000); director `init` registers Earth, `update` refreshes `center` from the
      Earth handle's world position each frame.
- [ ] Copy `Shaders/Atmosphere/` into PhasmaSpace assets; add panel checkbox
      "Atmosphere" to solar_ui.lua (settings.set("atmosphere", v)); rebuild + save
      scene with `atmosphere=true`.
- [ ] ATH unaffected check: `atmosphere` defaults false, ATH scenes untouched.

## Task 6: Visual acceptance (screenshots, Vulkan + DX12)

- [ ] Earth gibbous follow view: blue limb, haze gradient to space, day side subtly
      lifted. — [ ] Terminator close-up: warm band, night side limb fades out.
- [ ] Sun viewed through the limb: visibly reddened/attenuated. — [ ] Night lights +
      orbit ribbon seen through limb: attenuated, not occluded.
- [ ] TAA limb ghosting at time_scale 2 (revisit Decision 3 if bad); auto-exposure
      sweep Mercury→Neptune: atmosphere never clips or vanishes.

## Task 7: Perf + handoff

- [ ] Settled-fps (10 spaced samples) at Earth follow view, atmosphere off vs on —
      within Decision-5 budget; no-shell-on-screen view = no measurable cost.
- [ ] Wiki: rendering.md Atmosphere section + log.md, `bash docs/wiki/tools/lint.sh`;
      `clang-format -i`; `git diff --check`; `graphify update .`.
- [ ] MemPalace drawer (wing phasmaengine, room phasmaspace): LUT verification data,
      DX12 caveats found, calibration constant. Draft commit messages (NO commit) —
      engine: "Add Hillaire atmospheric scattering pass (transmittance + multi-scatter
      LUTs, per-pixel march)"; demo: "Enable Earth atmosphere (real Bruneton
      parameters, UI toggle)".

## Stretch (separate go-ahead)

S1 Mars/Venus presets (data-only: Mars β_R≈(5.75,13.57,19.92)e-3 thin + dust Mie;
Venus dense CO₂ — expect tuning). S2 Sky-view LUT + aerial froxels for in-atmosphere
flight (surface tourism). S3 Sun disk limb-darkening when seen through atmosphere.

## Out of scope

Volumetric clouds, god rays, eclipse shadows on atmosphere (Moon umbra), per-planet
ozone chemistry accuracy, light shafts through rings.
