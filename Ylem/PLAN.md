# Ylem

> *Ylem* (Gamow's word): the primordial substance of the Big Bang, from which
> nucleosynthesis forges every element. The title is the arc's alpha point.

A tactile physics sandbox where you **coalesce** the building blocks of the
universe — protons and electrons into real atoms, atoms into molecules, matter
into dust and star systems — each thing with its real name, real physics, and a
one-line "where you find it / what it does" told *after* you make it, like a
birth announcement.

**The verb the whole game speaks is *coalesce*** — the same physical event at
every scale (strong force → electromagnetism → gravity). One gesture: pull
things together until they bind.

---

## Two modes

- **Lab** — the grounded chemistry builder. Drag protons/neutrons/electrons into
  a nucleus to build real atoms (real shells, stability, isotopes), then combine
  atoms into molecules. *This is what we build first — it's the tactile core and
  the differentiator vs. the incumbent (Atomas).*
- **Cosmos** — the cosmic-ladder sandbox. The same bind-gesture, zoomed out:
  atoms → dust/gas clouds → protoplanetary disks → stars + planets, in one
  unbroken Powers-of-Ten zoom. **Later.** Present in Lab only as a teased promise.

### The loop that ties them (long-term)
Stellar nucleosynthesis forges the same heavy atoms the player hand-builds in
Lab. Cosmos reveals where your atoms came from. The carbon you forged by hand
should be *findable*, still glowing with its name, inside the star that forges it.
*Continuity rules for later: never cut the camera, never change the verb, carry
one hand-built atom through the zoom.*

---

## Build order (why Lab, why this order)

1. **Lab Slice 1** — protons + electrons, H→Ne. Fully correct atom model.
2. **Lab Slice 2** — neutrons: isotopes + unstable/trembling nucleus + decay.
   *The moat.* Atomas cannot do this; ship it one slice later, not "someday."
3. **Lab Slice 3** — bonding: combine two atoms into a molecule (start H₂, H₂O).
4. **Cosmos** — the zoom-out. Only after Lab feels great.

Each slice is a shippable, playable thing. Do not build ahead.

---

## Lab — Slice 1 (the first playable)

**Ceiling: H → Ne (Z 1–10).** Not arbitrary — that's exactly two closed shells
(2, then 8), and the naive "fill 2, then fill 8" rule is **100% correct through
Neon** (it only gets subtle at period 3+). Neon is the perfect endpoint: full
outer shell, inert, and literally the glowing sign — the lore writes itself.

### IN
- One 2D tabletop — screen-space `runtime_ui`, no 3D risk.
- A tray with draggable **protons** and **electrons**.
- Lua correctness table: `Z → element name/symbol` (H..Ne), electron count →
  shell fill (2 / 8), neutral (electrons == protons) = valid atom.
- **Birth card** fired *after* completion: name, symbol, one-line real-world lore.
- The hero juice moment (below).
- A thin "discovered" strip so building feels like collecting.

### OUT (explicit)
- Neutrons / isotopes / stability → **Slice 2**.
- Molecules / bonding → teased only (Oxygen's card ends *"pair me with two
  hydrogens and you're 60% of a human"* — a visibly locked next rung).
- Ionization (neutral atoms only), decay/half-life timers, anything past Ne,
  real orbital-lobe shapes (simple rings), 3D, Cosmos, save/meta-progression.

### Core interaction loop (~20s): grab → snap → fill → hold → name
- **Grab** a proton — it has weight, a slight wobble, wants to be placed.
- **Snap:** near the nucleus, the nucleus *reaches* and pulls it the last inch →
  bass thump + flash. Identity label morphs live the instant it lands (H→He→Li…).
- **Fill:** grab an electron → it's caught, spirals in, clicks into an
  evenly-spaced orbit slot; the shell ring brightens one notch. A 3rd electron
  won't fit shell 1 — it skids out and starts shell 2.
- **Hold:** when electrons == protons and it's a real element, everything *stills*
  for a beat and the atom glows.
- **Name:** the birth card slides up (*"NEON · Ne · the light in every bar sign.
  Full shell. Wants nothing."*). Lore always arrives as reward, never preface.
  Reach for the next particle → repeat, one element per cycle.

### First 5 minutes (felt before told — zero text walls)
- **Open** on one proton + one electron loosely orbiting: a breathing hydrogen
  atom, dead center. No text. The orbit looks touchable.
- **Only affordance:** a single proton in the tray, softly pulsing *"come here."*
  The pulse **is** the tutorial.
- Drag it in → thump. The atom now looks *incomplete* — an empty orbit slot
  glows. They feel the imbalance before it's named.
- An electron pulses in the tray → drag it → snaps into shell 1 → shell 1 now
  has 2 → **ring locks gold + chime** → HELIUM card.
- **That locked shell is the "oh, I get it."** Every rule taught by feel: pulse =
  draggable, snap = it worked, 3rd electron refusing shell 1 = capacity exists,
  glow-only-when-balanced = neutral means done.

### The ONE feedback moment to build first
**The electron-into-shell snap.** Build this before anything else; polish it
until it feels like a magnet clicking home:
- Release an electron near the atom → it's *caught*, spirals in along a curve, and
  **snaps** into an evenly-spaced slot with: a crisp tick, the shell ring flaring
  for a beat, the electron easing into the others' orbital rhythm, and a tiny
  recoil-wobble of the whole atom.
- **Escalate on completion** — when that electron closes a shell (2nd or 8th):
  ring snaps to a solid locked color + resonant chime + a soft radial shockwave.

Build the electron snap (not the proton thump): electrons are what the player
adds most, they carry the shell-completion payoff (the rule being taught), and
orbital motion is the richest thing to make satisfying. If dragging one electron
in doesn't feel great, nothing built on top will. Everything else can be
placeholder while this gets hero-level polish.

---

## Correctness anchor — Slice 1 element table

Neutral atom: `electrons == protons == Z`. Shell fill order: fill shell 1 to 2,
then shell 2 to 8. This feeds the Lua data table directly.

| Z | Sym | Shells | One-line lore (birth card) |
|---|-----|--------|----------------------------|
| 1 | H  | 1     | Fuels the stars; first atom after the Big Bang. |
| 2 | He | 2     | Floats balloons; 2nd most abundant thing in existence — perfectly content. |
| 3 | Li | 2,1   | The spark in your phone battery; lightest metal, soft enough to cut. |
| 4 | Be | 2,2   | Stiffens spacecraft and X-ray windows; light, rare, toxic. |
| 5 | B  | 2,3   | Borax and heatproof glass; strengthens rocket parts. |
| 6 | C  | 2,4   | The backbone of all life; diamond, graphite, and you. |
| 7 | N  | 2,5   | 78% of the air you breathe; locked so tight it starves fire. |
| 8 | O  | 2,6   | The other 21% of air; pair me with two hydrogens and you're 60% of a human. |
| 9 | F  | 2,7   | In your toothpaste and non-stick pans; the most reactive element there is. |
| 10| Ne | 2,8   | The glow in every bar sign; a full shell — wants nothing, reacts with nothing. |

---

## Tech notes (grounded to the real engine)

- **No engine C++ changes.** The whole chemistry sim is Lua. PhasmaEngine
  (Vulkan/DX12) already gives everything Slice 1 needs.
- **UI = `runtime_ui` (screen-space 2D).** Surface confirmed:
  `set_quad` (draw particle sprites), `get_surface_size`, `get_state`/`get_bool`
  (drag/hover state), `consume_click`, `set_text`, `set_button`.
- **Reference:** `PhasmaProjects/PhasmaSpace/Assets/Scripts/solar/solar_ui.lua`
  already drives a solar-system UI on this exact `runtime_ui` surface — a working
  model for Lab's drag UI *and* Cosmos later.
- **Scene:** strip the generated topdown-arena template (`main.pescene` ships with
  a Player sphere, 32 enemies, 64 shots) down to bare **Camera_0 + an HUD anchor**.
  Slice 1 draws everything via `set_quad`, so no meshes needed.
- **Scaffold:** created via `tools/new_game.py --name Ylem`. Self-contained
  (`gamekit` + prefabs copied in). `run_smoke.ps1` launches PhasmaPlayer and
  asserts a clean scene load — repurpose its log asserts for Lab.
- **Entry script:** `Assets/Scripts/ylem.lua` (wired as the scene's `on_play`).

### Slice-1 Lua module sketch
- `data.lua` — the Z→element table above (name, symbol, shell caps {2,8}, lore).
- `atom.lua` — state: `{protons, electrons}`; derives element, shell fill,
  `is_neutral()`, `is_valid()`.
- `particles.lua` — `runtime_ui` draw + drag: tray, in-flight particle, the
  snap/spiral animation, shell rings. **Hero juice lives here.**
- `card.lua` — birth-announcement card (fires on neutral completion).
- `ylem.lua` — bootstrap gamekit, wire the loop.

---

## First implementation step
Build the **electron-into-shell snap** as a standalone toy first: hydrogen on
screen, drag an electron from the tray, make it *catch → spiral → snap → ring
flare → wobble* feel like a magnet. Get that one interaction to hero polish
before adding the proton, the element table, or the card. Smoke-verify it loads
and drags in PhasmaPlayer (never a standalone test exe).
