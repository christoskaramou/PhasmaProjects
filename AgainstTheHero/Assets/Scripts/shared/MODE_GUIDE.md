# Building an ATH mode (the shared style every mode follows)

A **mode** is one complete level: a themed arena, a cast of characters, the
dual-faced card duel, and ONE signature mechanic. The menu (`ath_shell.lua`)
launches it through the shared **Duel** engine. You write only two files inside
your own `Assets/Scripts/modes/<id>/` directory — never edit shared files.

```
modes/<id>/
  characters.lua   -- DATA: the cast (creep archetypes) + hero rig + theme
  mode.lua         -- the contract: return { meta = {...}, config = {...} }
```

Read the canonical example first: **`modes/emberforge/`**. Copy its shape.

## The contract (`mode.lua` returns this)

```lua
return {
  meta = {            -- what the MENU shows
    id, name, tagline, blurb,
    side_hint = "hero"|"horde",
    accent = {r,g,b,a},
    minimap = { bg = {r,g,b,a}, rects = { {x,y,w,h,{r,g,b,a}}, ... } }, -- 0..1 sketch
  },
  config = {          -- handed to Duel.new(config, ctx, shell)
    id, name,
    theme   = <from characters.lua>,
    arena   = { width, height, pad, ortho_size },
    hero    = { hp_max, dps, cleave, attack_range, speed, kite_speed, actor = <hero rig> },
    archetypes = <from characters.lua>,   -- the cast
    roles   = { swarm=, ranged=, elite=, brute= },  -- map card roles -> your archetype ids
    spawn   = { interval_start, interval_min, batch_start, batch_max, cap_start, cap_max, brute_after },
    reserve_start, round_seconds,
    auto_mix = function(D) return "<archetype_id>" end,  -- which creep auto-spawns over time
    hooks   = { on_start, on_reset, on_combat_tick, on_pause, on_resume, on_card, on_spawn, draw_hud },
  },
}
```

The Duel handles EVERYTHING else: the round/pause loop, the reserve economy,
card application (front=hero upgrade, back=horde play), the auto-fighting hero,
the rushing swarm, the HUD, the camera, win/loss, slow-mo death, and the AI for
whichever seat the player did NOT pick. **Do not re-implement any of that.** Your
job is content + one mechanic.

## Shared helpers you use (load them at the top of your files)

```lua
local Art   = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)
local Mine  = ATH_COMMON.load_script("Scripts/modes/<id>/characters.lua", "<id> characters", _ENV)
```

- `Art.cube/sphere/cylinder(name, vec3 pos, vec3 scale, color, parent, emissive, texture?)`
- `Art.build_actor(spec, parent)` / `Art.decorate(root, extras)` / `Art.texture(node, path)`
- `Art.burst(name, vec3 pos, opts)` — particles. `Art.quad(screen, id, x,y,w,h, fill, opts)` — HUD.
- `Art.surface_size()` -> w, h.

## Characters = DATA (horde/creep.lua archetypes + ATH extensions)

Each archetype is a `horde/creep.lua` archetype table. Fields the engine reads:
`name, threat_cost, hp, dps, range, speed, color, head, weapon, body_scale,
head_scale, head_pos, weapon_pos, weapon_scale, parts (2 or 3), scale,
flies, hold_range, anchor_hold, needs_los, projectile {…}`.

Two ATH extensions the Duel honours (this is how you add silhouettes/textures
**as data, never code**):

- `extras` = a list of decorative `Art` PART specs welded onto the creature
  after build: `{ name, kind, position={x,y,z}, scale={x,y,z}, color={r,g,b},
  emissive, rotation?, texture? }`.
- `texture = "Objects/foo.png"` — paints the body. Any part spec also takes
  `texture = "..."`.

Provide **5 distinct characters** (a cheap swarm, a fast chaser, a ranged
caster with a `projectile`, a tanky elite, and a heavy brute/boss), each with a
recognisable silhouette via `extras`. Map them in `roles` and `auto_mix`.

The **hero rig** is an `Art.build_actor` spec. Keep these part keys so the
built-in walk/attack animation clips work: `body, head, hand_r, hand_l, foot_r,
foot_l, sword`. Add extra flavour parts under any other key (they ride the root).

## The signature mechanic (your one bespoke system)

Implement it ONLY through `hooks`, operating on the live duel `D`:
- `D.hero` (`.x .z .hp .hp_max .dead .speed .attack_range .armor`), `D.creeps`,
  `D.arena` (`.w .h .pad`), `D.map:is_walkable(x,y)`, `D.groups.world`,
  `D.realtime`, `D.round`, `D.combat_time`, `D:count_alive()`, `D:set_flash(s)`.
- `D:apply_hero_damage(amount, { ignore_armor=, flash= })` — the hazard API for
  environmental damage (lava/poison/storms) with correct death handling.
- Transient debuffs WITHOUT corrupting card stats: set `D.hero.move_mult` (slow:
  ice/mud) and/or `D.hero.range_mult` (sandstorm) every tick in `on_combat_tick`
  (1.0 = off). They are mode-owned — set them each frame, the engine never resets
  them. You may also nudge `D.hero.x/.z` directly (gravity pull, conveyor shove);
  the engine clamps the hero inside the arena on its next move.
- Store your state on a namespaced field, e.g. `D.<id> = { ... }`, init it in
  `on_start`, tear it down in `on_reset`, advance it in `on_combat_tick(D, dt)`,
  and surface a readout in `draw_hud(D)`.

Build all mechanic visuals from `Art` primitives parented to `D.groups.world`
(self-lit via emissive — scene lighting barely reaches the built stage). Make
them texture-ready (accept a `texture` field where natural).

## Rules

- Write ONLY in `modes/<id>/`. Do not edit any `shared/` file, the dispatcher,
  the registry, or another mode. No `.cpp`/`.h`.
- Lua only. No build, no run, no tests (the user will test later).
- Match emberforge's comment density and style. Keep it self-lit and consistent.
