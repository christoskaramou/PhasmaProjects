# PangRemix

Entry: `Arcade/PangRemix/run.ps1` starts `Scenes/main.pescene` (run.ps1:29); the scene loads `Assets/Scripts/game.lua`.

**`game.lua` is generated:** `tools/build_lua.sh` concatenates `tools/src/0*.lua` into the runtime script (PangRemix/tools/build_lua.sh:1-3). Rule citations below use the generator source (`tools/src/03_stage.lua`, `04_sim.lua`, `06_hud.lua`), which is what the runtime is concatenated from; the Jev attach is cited from the loaded `Assets/Scripts/game.lua`. This game uses its own `Assets/Scripts/jev_auto.lua` (175 lines, with an extra `api.engage` for joining a live match, jev_auto.lua:123-142); it loads `Scripts/gamekit/driver.lua` and `jev_boot.lua` (jev_auto.lua:9-11). `gamekit/driver.lua`'s `observe` is `pcall`-protected (driver.lua:111-167).

## World, stages and locations

- World x -24..24, floor y = 0, ceiling y = 26 (game.lua:6-7; 04_sim.lua:3-16).
- 17 locations in order, 50 stages; `loc_of(n) = min(17, floor((n-1)/3) + 1)` (03_stage.lua:2-13).
- Stage layout: stage 1 uses layout 1, stage 2 layout 2, stage 3 layout 3; otherwise `LAYOUTS[((n*7) % 15) + 2]` (03_stage.lua:42-45, 19-38).
- Balloon set (03_stage.lua:46-55): `big = min(4, 1 + floor((n-1)/7))` size-4 balloons; every 7th stage instead gets four size-3 balloons. Otherwise it adds a size-3 on `k==2` or n > 20, and two size-2 balloons when `k==3` (`k = (n-1)%3 + 1`).
- Stage time `min(150, 70 + 18 * #balls)` seconds (03_stage.lua:56).
- Crabs appear on stages where `n % 4 == 2 and n > 4`; birds when `n % 4 == 0` (03_stage.lua:58).

## Player

- Walk 9.2 u/s, climb 6.2 u/s, half-width 0.5, height 2.6 (04_sim.lua:9, 176-222).
- Ladders are usable within 0.75 of the ladder x, and only when within 0.35 of its foot (down) or top (up) (04_sim.lua:152-159, 186-189). Climbing is clamped to the ladder's y0..y1, then returns to walking (04_sim.lua:206-214).
- Standing support comes from the floor or any live block top (03_stage.lua:96-107); stepping off support starts a fall with gravity 40 until a surface is found (04_sim.lua:215-221).
- Fire: one wire, rising at 30 u/s to the ceiling or the first block (04_sim.lua:10, 160-175, 241-263). After a wire launch, walking is suppressed for 0.14 s; Vulcan and Jev ignore this lock (04_sim.lua:174, 183-184).
- Power Wire: the wire sticks where it stops for 3.0 s (04_sim.lua:255).
- Double Wire: up to 2 wires at once (04_sim.lua:171-172).
- Vulcan: rapid shots while fire is held, 8 alive max, 0.09 s cooldown, speed 42 (04_sim.lua:10, 162-168, 264-279).

## Balloons

- Sizes 1..4 have radii 0.38 / 0.72 / 1.35 / 2.1 and fixed bounce apex 6.5 / 10 / 14.5 / 18.5 above the floor, so bounce speed is derived per size (04_sim.lua:4-8).
- Gravity 34; side walls and ceiling reflect; the floor bounce sets the size's fixed apex velocity (04_sim.lua:31-39).
- Balloons collide with live blocks and are pushed out along the shallower axis (04_sim.lua:40-53).
- Points by size: 4 = 200, 3 = 150, 2 = 100, 1 = 50 (04_sim.lua:6, 65-68).
- Popping a size > 1 spawns two balloons one size smaller at ±0.5 radius offset, velocities ±4.8 and +9.5 upward, and may drop an item (04_sim.lua:65-82).
- A wire hits a balloon inside `balloon.r + 0.12` of the rope segment; a Vulcan shot inside `r + 0.15` (04_sim.lua:225-240, 273-278).

## Blocks and pickups

- Glass blocks (`r/b/y/g`) break when hit by a wire or Vulcan shot, award 100 points, and have a 35% forced item drop (04_sim.lua:95-101, 247-255, 267-272).
- Steel (`s`) blocks are not broken by either: a wire stops at them (a Power Wire sticks), and a Vulcan shot is consumed (04_sim.lua:254, 269).
- Items drop on 13% of balloon splits and fall/rest on surfaces; they expire after 7 s and are picked up within 1.0 x and the player's vertical body range (04_sim.lua:55-64, 292-307).
- Item weights: double .17, power .14, vulcan .12, clock .10, hourglass .10, dynamite .08, shield .10, life .02, fruit .17; `life` becomes `fruit` at 6 lives or more (04_sim.lua:55-61).
- Effects (04_sim.lua:282-291):
  - `double` / `power` / `vulcan` set the weapon (no timer).
  - `clock` freezes balloons for 6 s (`G.freeze_t`).
  - `hourglass` slows balloons to 40% for 8 s (`G.slow_t`).
  - `dynamite` pops every balloon of size > 1 without score, repeatedly until only size 1 remains, and removes dynamite items.
  - `shield` absorbs one balloon hit, then grants 1.6 s invulnerability.
  - `life` adds a life, or becomes fruit at 6+ lives.
  - `fruit` awards 500 / 1000 / 2000 by its random fruit index (04_sim.lua:62, 290).

## Animals

- Spawn timer starts at 12 s, then 14-22 s, and only on stages flagged crab or bird; only when no animal is alive (04_sim.lua:364-367).
- Crab: walks at 3.2 u/s, turns at the walls, leaves after 3 wall turns, and on contact stuns the player for 1.4 s with 2.6 s invulnerability (no life lost) (04_sim.lua:310, 323-326).
- Bird: flies at 5 u/s at y 15-20 with a sine bob, leaving past the wall (04_sim.lua:311, 327-330).
- A wire can hit an animal within 0.9 x and the rope's vertical span for 500 points (04_sim.lua:233-238).

## Death, lives, win and lose

- Death sources: a balloon touching the player's hitbox (`pw .45`, `y+0.15..y+2.15`, balloon radius × 0.9 unless shielded) or the stage timer reaching 0 (04_sim.lua:334-352).
- `player_die` starts a keyframed knock-back death arc; there is no control during it (04_sim.lua:104-151, 180).
- After `dead_t >= 2.6` a life is spent: at 0 lives `game_over(false)`; otherwise the same stage restarts (06_hud.lua:876-878).
- Clear: when no balloons remain, `clear` starts, time bonus `floor(time) * 100` is awarded, and `cont_stage` advances (06_hud.lua:865-870).
- Stage 50 clear calls `game_over(true)`; clearing an earlier stage starts the next one (06_hud.lua:798-801). Continue from the highest stage reached is offered on the title (06_hud.lua:108-113, 776-780).
- 3 lives to start; an extra life at 20,000 points, then +30,000 until 50,000, then +50,000 (06_hud.lua:143-145, 02_look.lua:103-108).

## Timers

| Timer | Value | Cite |
|---|---|---|
| Stage intro | 2.2 s (skippable after 0.4) | 06_hud.lua:786-790 |
| Stage clear hold | 3.0 s (skippable after 0.8) | 06_hud.lua:798-801 |
| Death to life loss | 2.6 s | 06_hud.lua:876-878 |
| Item lifetime | 7 s | 04_sim.lua:305 |
| Time stop | 6 s | 04_sim.lua:285 |
| Slow | 8 s | 04_sim.lua:286 |
| Crab stun / invulnerability | 1.4 / 2.6 s | 04_sim.lua:326 |
| Shield invulnerability | 1.6 s | 04_sim.lua:340 |
| Post-shot walk lock | 0.14 s | 04_sim.lua:174, 183-184 |
| Vulcan cooldown | 0.09 s | 04_sim.lua:164 |
| Power Wire stick | 3.0 s | 04_sim.lua:255 |

## Jev attach (game.lua:1592-1684)

`port = 9133`, `id = "pang-remix"` (game.lua:1593-1594). `playing()` is `intro`, `play` or `clear`; `terminal()` is `over` (game.lua:1596-1602). `busy()` is always false (game.lua:1607-1609). `reset(seed)` seeds RNG, clears the hold and starts `new_game(1)` (game.lua:1676-1680).

The wrapper only publishes `actions` while Jev owns a live, non-terminal match, and `act` calls `hooks.apply` only in that state (jev_auto.lua:36-62, 79-84). Mode/ownership is part of the decision key, not positions (jev_auto.lua:64-78).

### observe() fields (game.lua:1613-1625)

- `player_x`, `player_y` — rounded to 2 decimals.
- `balloon_x`, `balloon_y` — nearest balloon by squared distance to the player, rounded; `0, 0` when no balloon exists (game.lua:1614-1619; 06_hud.lua:193-204).
- `shot` — `shot_free()`.
- `wire` — the 4th return of `jev_target()`, i.e. its `why` reason code, not a position (game.lua:1621; 06_hud.lua:575-608). Possible values from that function: `none`, `low`, `busy`, `miss`, `shoot`, `fruit`, `item`, `creep`, `route` (06_hud.lua:581-604, 526-538, 561, 566).
- `lives`, `score`.

`jev_target()` itself chooses an aim x and climb request: it caches per `G.t`, picks the nearest balloon, escapes a balloon that is too low, avoids while a wire is out or the shot would miss, otherwise aims at a stand where the wire hits, and finally may divert to a pickup or a ladder route (06_hud.lua:575-608, 512-573).

### action ids (game.lua:1626-1658)

`"right"` when `dx = aim - P.x > 0.3`; `"left"` when `dx < -0.3`; `"stop"` otherwise. Exactly one action is offered, score = dx / -dx / 1.

### apply(id) (game.lua:1659-1675)

- Rejects any id other than `left`, `right`, `up`, `down`, `stop` (game.lua:1660-1662).
- Calls `clear_hold()`, which empties `G.vk`, clears `G.fire_pulse`, `G.jev_x` and the target cache (06_hud.lua:179-184).
- `"left"`, `"right"` and `"stop"` all do the same thing: set `G.jev_x` to the current `jev_target()` aim x (game.lua:1667-1669). So `stop` is not a stop; it holds the aim point.
- `"up"` / `"down"` set the corresponding virtual key instead (game.lua:1670-1673); these ids are never offered.

Actual movement and firing are done by the game loop, not by `apply`: while Jev is assisted and `G.jev_x` exists, horizontal input is derived from the aim, climb input comes from `jev_target`'s 5th value, and a wire is fired automatically when `can` and `wire_outcome(P.x, 0)` is true (06_hud.lua:829-845).

## Jev cannot see

- Every balloon except the nearest one; no other positions, velocities, radii or the count remaining, so split chains and safe standing spots elsewhere are invisible (game.lua:1613-1625; 04_sim.lua:65-82).
- Wire state beyond `shot`/`wire`: rope tip x and y, remaining stick time, whether the current wire will hit, and the Vulcan cooldown (04_sim.lua:241-279).
- Blocks: positions, kind (steel vs glass) and whether a wall is between the player and an aim point (03_stage.lua:71-94; 06_hud.lua:547-562).
- Ladders: positions and top/bottom, even though the hidden plan may route to one (03_stage.lua:81-90; 06_hud.lua:500-510).
- Items and animals: no item position, kind or remaining 7 s lifetime; no crab or bird position (04_sim.lua:292-331; game.lua:1613-1625).
- Weapon, shield and power-up state, freeze/slow remaining, stage time remaining, stage number and location, and `cont_stage` (04_sim.lua:282-291, 347-352; 06_hud.lua:143-147).
- That `actions` only offers horizontal movement while `apply` accepts unused vertical ids (game.lua:1626-1673).
- `busy` is hard-coded false, and `playing()` includes `intro` and `clear` where no gameplay step occurs (game.lua:1596-1609, 06_hud.lua:786-801).
