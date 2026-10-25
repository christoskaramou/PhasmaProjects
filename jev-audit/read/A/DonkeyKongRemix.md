# DonkeyKongRemix — how the game works (read from current source)

Source of truth: `Arcade/DonkeyKongRemix/Assets/Scripts/game.lua` (2136 lines). Byte-identical concatenation of
`Arcade/DonkeyKongRemix/tools/src/0*.lua` via `tools/build_lua.sh` (verified). Cites are
`Assets/Scripts/game.lua` lines. Jev wrapper `Assets/Scripts/jev_auto.lua`; driver
`Assets/Scripts/gamekit/driver.lua`. `run.ps1` launches `Scenes/main.pescene` (`run.ps1:29-30`), and that scene
loads `Scripts/game.lua`.

## Shape of a run

- Simulation runs at a fixed 60 Hz in the original 224 × 256 pixel space (y grows downward); up to 6 steps per
  frame (`game.lua:5`, `693`, `1914-1924`).
- States: `title`, `intro` (Kong climb cutscene), `howhigh`, `play`, `pause`, `clear`, `over`
  (`game.lua:1491-1507`, `1542-1556`, `1886-1901`).
- New game: score 0, 3 lives, level 1, bonus 5000, then the intro (`game.lua:2070-2078`).
- The stage order is the US arcade sequence, selected by level:
  level 1 = 25, 100; level 2 = 25, 75, 100; level 3 = 25, 50, 75, 100; level 4 = 25, 50, 25, 75, 100;
  level 5+ = 25, 50, 25, 75, 25, 100 (`game.lua:1488-1489`). After the last stage of a sequence the level
  increments and the sequence repeats (`game.lua:1524-1528`).
- Between stages the `howhigh` screen shows one Kong statue per 25 m reached for 2.8 s
  (`game.lua:1510-1523`, `1898-1901`).

## Stage rules, stage by stage

### 25 m — girders and barrels (`game.lua:287-314`)

- Seven girders, sloped, plus a 3-tile top girder for Pauline; one oil drum at x 24 on the bottom girder
  (`game.lua:290-311`).
- Kong stands at (44, 84) and throws barrels from the top girder. First barrel is a blue "drop" barrel; later
  ones roll from Kong or are thrown "wild" (`game.lua:877-885`, `1043-1063`).
- Barrels roll at `1.0 + 0.04*diff` pixels/frame, may take a ladder down (probability
  `0.18 + 0.06*diff`, raised if Mario is below/near that ladder, halved while Mario has a hammer), and bounce
  once when they fall off a girder (`game.lua:887-952`).
- A barrel entering the drum at the bottom ignites it; a blue barrel or the first barrel also spawns a
  fireball (`game.lua:894-897`, `913`).
- Hammers at (168, girder 2) and (24, girder 5) (`game.lua:308`).
- Goal: reach girder 7 (`game.lua:312`).

### 50 m — conveyors, pies and fire (`game.lua:315-342`)

- Ten girders; most are conveyor belts with direction `conv = ±1`, and several reverse periodically
  (`game.lua:319-328`, `1092-1101`).
- Conveyor speed is `conv * flip * 0.5` px/frame and is added to Mario's walk when he stands on it
  (`game.lua:782`, `1098`).
- Three retractable ladders cycle between extended and retracted (`game.lua:333-334`, `1103-1110`).
- Cement pies spawn every 80–170 scaled frames on belt 2, 3 or 5 and ride the belt; they fall off the end and
  kill on contact (`game.lua:999-1023`, `1112-1118`).
- Firefoxes spawn from the central oil fire every 360–600 scaled frames; the standing oil fire itself is
  lethal (`game.lua:1119-1120`, `1175-1176`).
- Hammers at (24, girder 6) and (104, girder 2); items umbrella (40, g2), hat (168, g1), purse (200, g8)
  (`game.lua:336-337`).
- Goal: girder 9 (`game.lua:340`).

### 75 m — elevators and springs (`game.lua:343-368`)

- Nine short girders over a pit. Two elevator shafts at x 56 (down) and x 112 (up), each with three moving
  platforms on a 152-pixel loop (`game.lua:349-362`, `517-529`, `1131-1136`).
- Riding a down platform above y < 104 is crushed by the motor and kills Mario
  (`game.lua:832-836`).
- Springs are thrown from (52, 84), hop right, bounce on girder 8 at y 84, then drop at x ≥ 184
  (`game.lua:1025-1036`, `1068-1070`).
- The pit is lethal: y > 262 kills, and falling more than 12 px onto a platform also kills
  (`game.lua:821-829`).
- Fireballs are capped at 2 on this stage (`game.lua:865-866`).
- Items: umbrella (80, g3), purse (216, g6), hat (100, g8); no hammers (`game.lua:363-364`).
- Goal: girder 9 (`game.lua:366`).

### 100 m — rivets (`game.lua:369-386`)

- Five full-width girders plus the top girder; each of girders 2–5 has two rivets at x 56 and 168
  (`game.lua:370-374`, `487-515`).
- Walking over a rivet on the girder above it opens a hole, scores 100, and the hole stays open
  (`game.lua:751-766`). Mario can then fall through that hole.
- The stage clears when `ST.rivets_left` reaches 0 (8 rivets) (`game.lua:1503`, `1922`).
- Firefoxes spawn on girders 1–3 every 420–700 scaled frames, up to 5 (`game.lua:1121-1129`).
- Hammers at (24, g3) and (200, g2); items umbrella (188, g2), purse (44, g3), hat (176, g4)
  (`game.lua:381-382`).
- `goal` is always false; only the rivet count clears the stage (`game.lua:384`, `1922`).

## Player actions

- Walk left/right at 0.75 px/frame; climb at 0.62 px/frame; jump impulse 1.65, gravity 0.097
  (`game.lua:694-695`, `767-830`).
- Jump: Space/Z/J sets a one-frame jump queue (`game.lua:1911`, `1917`). Jumping gives horizontal control at
  walk speed and ends in `walk` or `fall` (`game.lua:778-780`, `808-830`).
- Climb: up/down at a ladder bottom/top within 3 px; broken ladders stop at 42% of their length and
  retractable ladders only work when extended (`game.lua:436-440`, `772-777`, `796-807`).
- Pick up a hammer by overlapping it; it lasts 600 frames (10 s) and disables climbing and jumping while
  active (`game.lua:839-851`, `772-778`).
- Hammer hitbox alternates overhead and in front every 9 frames (`game.lua:854-859`).
- Jump score: jumping over 1/2/3+ hazards in one jump awards 100/300/800 (`game.lua:741-745`).
- Mario is clamped to x 5..219 and cannot walk through the 25 m oil drum (`game.lua:784-785`).

## Hazards and what kills the player

- Contact with a barrel, fireball/firefox, cement pie or spring while not smashing it
  (`game.lua:1157-1171`).
- Kong's body box (13 wide, 30 tall) and the 50 m standing oil fire (`game.lua:1172-1176`, `704`).
- Falling more than 12 px onto a girder/platform, or dropping below y 262 (`game.lua:821-829`).
- Being carried by a descending elevator above y 104 (`game.lua:832-836`).
- Bonus timer reaching 0 (`game.lua:1196-1203`).
- Death animation lasts 160 frames (2.67 s); then a life is lost and the same stage restarts, or the run ends
  at 0 lives (`game.lua:1926-1934`).

## What the player can kill

- With a hammer: barrels (300/500/800 random), fireballs/firefoxes (500), cement pies (500); springs cannot be
  smashed (`game.lua:1147-1171`).
- Kong cannot be damaged; the 100 m clear is by removing rivets (`game.lua:369-386`).
- Items are collected, not killed (`game.lua:1177-1183`).

## Timers and durations

| Timer | Value | Cite |
|---|---|---|
| Hammer | 600 frames = 10 s | `game.lua:844` |
| Bonus timer tick | −100 every 120 frames (2 s) | `game.lua:1199-1200` |
| Stage bonus start | `min(8000, 4000 + 1000*level)` | `game.lua:1501` |
| Death to life loss | 160 frames ≈ 2.67 s | `game.lua:1926` |
| Clear to next stage | 5.2 s (`clear`) / 7.5 s (`100 m`) | `game.lua:1663`, `1684` |
| Clear bonus award | 0.8 s into the clear cutscene | `game.lua:1640-1641` |
| `howhigh` screen | 2.8 s, skippable after 0.4 s | `game.lua:1901` |
| Intro cutscene | 5.5 s climb + 6 hops of 0.62 s + 1.6 s | `game.lua:1558`, `1563-1601` |
| Kong idle between throws (25 m) | 50–150 frames scaled by difficulty | `game.lua:1062` |
| Conveyor reversal | every 300–540 frames | `game.lua:1095-1096` |
| Retractable ladder cycle | 120–200 up / 150–260 down frames | `game.lua:1105-1106` |
| Elevator loop | 152 frames per platform cycle | `game.lua:1133-1134` |

There are no freeze/slow power-ups. Hammers are the only timed power-up; items are instant points.

## Scoring, win and lose

- Points: rivet 100; item 300 at level 1, 500 at level 2, 800 at level 3+; hammer smash 300/500/800;
  jump-over 100/300/800; remaining bonus is added at stage clear (`game.lua:760`, `1180`, `1167`, `743`,
  `1641`).
- One extra life at 7000 points (`game.lua:279`).
- Hi-score loaded from `Save/dk_hiscore.txt`, saved on game over when Jev was not assisted
  (`game.lua:266-267`, `1930-1940`).
- Win: there is **no final win state**. The 100 m stage clears, the sequence repeats at the next level with
  faster/denser hazards via `diff()` (`game.lua:715`, `1524-1528`).
- Lose: lives reach 0 after a death (`game.lua:1928-1933`).

## Difficulty scaling

`diff() = min(5, level + floor(stage_f / 2700))`, i.e. the current level plus one step every 45 s in a stage
(`game.lua:715`). It raises barrel speed, ladder-taking chance, fireball speed, wild-barrel chance and shortens
Kong's idle/throw cycles (`game.lua:889-900`, `959`, `1056-1062`, `1115`).

## JevAuto.attach for this game

Attach block `game.lua:2085-2129`, port 9132, id `donkey-kong-remix`.

`observe()` returns exactly `x`, `y`, `on_ladder`, `hazard_x`, `hazard_y`, `lives`, `score`
(`game.lua:2104-2115`). The wrapper adds `mode`, `terminal`, `score`, `busy`, `actions`
(`jev_auto.lua:54-61`). `hazard_*` is the nearest of any barrel, fireball, pie or spring, or Kong, or the 50 m
oil fire, by squared pixel distance (`game.lua:2030-2068`). `busy` is true while Mario is in the `jump` state
(`game.lua:2098-2100`).

Action ids produced by `actions()` (`game.lua:2116-2125`): `jump`, `up`, `right`.
- Nearest hazard within 1.2 px horizontally → `jump`.
- Else if on a ladder → `up`.
- Else → `right`.

`apply(id)` (`game.lua:1998-2028`):
- `jump` queues a jump and holds Right (`game.lua:1999-2004`).
- `stop` clears all movement holds.
- `left`/`right`/`up`/`down` clear all movement holds and hold the single matching key.
- Unknown ids do nothing.
- `reset(seed)` seeds random, resets score/lives/level and starts the intro (`game.lua:2070-2079`);
  `on_human` clears holds and the jump queue (`game.lua:1993-1996`).

## Jev cannot see

- The stage kind/height, stage sequence and level (`G.level`), and whether the stage is cleared by goal or by
  rivets.
- Girders, conveyor direction/state, ladders and their broken/retracted state, elevator platforms.
- The bonus timer and the 7000-point extra life; the stage bonus.
- Hammers (position, whether one is active, remaining hammer time) and Pauline's items.
- Rivets and how many remain.
- Mario's facing, walk/climb/jump/fall state beyond `on_ladder`/`busy`, and the fall-death threshold.
- Every hazard except the single nearest one; hazard size/type and whether it can be jumped.
- Kong's throw timer and state, and barrels that are still in `spawn`.
