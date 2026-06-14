# Against The Hero — Plan of Record

> **Direction: persistent-character ARPG. Locked 2026-06-14.**
> Supersedes the 2026-05-30 "RUSH" card-auto-battler plan (`../../ATH_plan.txt`) and the
> 2026-06-09 experiment-#1 note — both are folded in below: the *target* is the full ARPG
> loot loop; the *build order* keeps experiment #1's manual-core-first discipline.
> Read this file before acting. The project has churned hard; do not trust older plans.

## What it is

Top-down hero auto-battler **ARPG**, Brotato / Vampire-Survivors-shaped, where **you are the
hero**. Move-only control + auto-attack — positioning is the whole game (kite / dodge / tackle
/ avoid). The depth lives in the **loot loop**: gear, drops, gold, a 6-slot paper-doll, and a
town store. Lua-only on PhasmaPlayer; spine is `Assets/Scripts/shared/ath_duel.lua`.

**Combat identity (decided 2026-06-14):** auto-attack comes in **both melee and ranged**
flavors, and there will be **multiple classes** (each class an attack identity — e.g. a melee
cleaver vs a ranged shooter — that gear/cards then bend). This supersedes the original
"move-only + auto-attack *cleave*" wording: the control model is unchanged (move-only), but the
attack is class-dependent. The `arena` testbed currently ships the **ranged** auto-attack
(pooled bolts, `cleave` = bolts per volley) as the first of these; the melee cleave path
(`Duel:hero_attack`) still exists and is the second flavor to wire to a class.

## Core loop

```
Town (store + 6-slot paper-doll + stash)
   -> enter Map
        Round 1: draft 1-of-3 cards  ->  fight wave
        Round 2: draft 1-of-3 cards  ->  fight wave
        ...
        Boss
   -> map cleared, loot + gold banked
   -> back to Town -> re-enter (harder)
```

- **Round = wave.** One card draft, then that wave's combat.
- **Map = N rounds + a boss.** `N` is an open tuning knob. The map is *finite* and returns you
  to town — that finiteness is what makes the store loop work.
- **Death = keep everything.** Death just ends the map; you keep all gear, gold, and drops, and
  re-enter freely (modern-ARPG forgiving; lowest stakes while we're still finding the fun). A
  spicier opt-in "bank-on-clear" mode can come later, not in v1.

## Two upgrade systems — kept distinct (no overlap)

- **Cards = temporary, run-scoped.** Player drafts pick-1-of-3 between rounds; they bend stats
  for *this run only*. NO dual-faced cards, NO Gemma AI picking (both parked).
- **Gear = persistent.** 6-slot paper-doll — **helmet, body, pants, gloves, weapon, jewelry**.
  Drops as **fixed templates + rarity tiers** (no randomized affix rolls yet). Survives runs.

## Stat vocabulary (v1)

What *both* gear and cards manipulate — this is the mechanical depth of a move-only +
auto-attack game. Gear adds flat/%; cards bend for one run. Editable.

`max_hp`, `armor`, `damage`, `attack_speed`, `attack_range`/`area`, `projectile_count`,
`move_speed`, `crit_chance`, `pickup_range`, `gold_find`, `life_steal`

## Economy

Enemies drop gold + items; bosses drop better. Gold + gear persist across runs. The **store is
in town, pre-game** — buy before entering a map. Between-wave growth is *cards*, not shopping;
the store is town-only.

## Build order (target is full; build stays incremental — manual-core gate intact)

0. ~~Unblock the PhasmaPlayer rendering-scale bug.~~ **DONE** — fixed on engine master 2026-06-13:
   `a7b1d0d8` (render-scale resize after scene load) + companion `27f618cc` (orthographic-RT
   sprite inflation). Root cause was a serialized `render_scale` not triggering a render-target
   resize on scene load — *not* the SV_InstanceID theory in the old dossier. ATH is unblocked.
   Cleanup TODO: engine tree is clean; 4 stale ATH Lua diag logs remain (`[CAMDIAG]`/`[DMG]` in
   `ath_duel.lua`, `[ISO_CAM]` in `ath_art.lua`, `[TOPDOWN]` in `ath_topdown_view.lua`) — strip or
   gate behind `ATH_DEV` before building.
1. **Feel the manual core:** WASD + auto-attack, 5-wave `arena`, **3-slot** gear, gold counter.
   Gate (felt, not argued): does moving through the swarm feel good; does a gear swap change how
   you move; do you want one more run? If "movement itself is dull" → fix action feel (attack
   juice, enemy variety, hit feedback), NOT systems.
2. If yes → **wave-end card draft** (1-of-3 run modifiers over the stat vocab).
3. → **full 6-slot paper-doll + drops + rarity + town store + persistence/save**.
4. → maps/bosses + more battlefields (`arena` / `spud_fields` / `alien_hive` already exist).

## Parked (do not build without the user)

Gemma "Hero Brain" / dual-faced cards; PvP & horde-seat machinery (dormant, not deleted —
player always hero seat); the sprite system (parallel track, OFF the critical path — combat fun
is tested on current quads); randomized affix rolls.

## Repo reality

- Spine: `Assets/Scripts/shared/ath_duel.lua` (hero-vs-swarm duel engine); menu `ath_shell.lua`;
  `ath_cards.lua`, `duel_creep.lua`, `duel_flow.lua`, `ath_art.lua`, `ath_topdown_view.lua`;
  mode guide `shared/MODE_GUIDE.md`.
- Modes: `arena` (manual-hero 5-wave testbed), `spud_fields`, `alien_hive`. 18 grimdark modes
  archived under `Assets/Scripts/old/`.
- Dispatcher: `Assets/Scripts/Player/against_the_hero.lua` (boots the menu, `ATH_MODE=menu`).
