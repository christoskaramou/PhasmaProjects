# BattlezoneRemix — how the game works (read from current source)

Source of truth: `Arcade/BattlezoneRemix/Assets/Scripts/game.lua` (1464 lines, hand-written; this game has no
`tools/src`). Cites are `Assets/Scripts/game.lua`. Jev wrapper `Assets/Scripts/jev_auto.lua`; driver
`Assets/Scripts/gamekit/driver.lua`. `run.ps1` launches `Scenes/main.pescene` (`run.ps1:29-30`), which loads
`Scripts/game.lua`.

## Shape of a run

- First-person tank combat on a flat plain with scattered solid props; playable half-extent `WORLD = 220`
  (`game.lua:64`).
- No rounds and **no win condition**: waves keep coming (`start_wave` only increments the wave number)
  (`game.lua:672-678`). The run ends only when the player's 3 tanks are gone (`game.lua:18`, `706-710`).
- New game: score 0, 3 tanks, wave 0, player at origin facing yaw 0, 1.5 s spawn invulnerability, then
  wave 1 starts with two enemy tanks seeded (`game.lua:1063-1075`).
- Wave spawner runs only in state `play` (`game.lua:680`).

## Player actions

- Drive: W/Up forward, S/Down reverse; target speed ±18, eased at 4.5/s (`game.lua:752-753`, `766-768`).
- Turn: mouse delta only during play (cursor is locked); sensitivity
  `0.0022 * (0.25 + 1.5 * mouse_sens)`, turn rate capped at 6 rad/s and eased at 16/s
  (`game.lua:747`, `754-765`). There are no keyboard turn keys in play (`game.lua:754`).
- Fire: Space or left click, cooldown 0.55 s; holding Space keeps firing once the cooldown is 0.05 s
  negative (`game.lua:782-798`).
- Shell: spawned 3.0 units in front at height 1.6, speed 55, lifetime 2.8 s (`game.lua:786-788`, `478`).
- Movement is blocked by the world edge and by pyramids/blocks/rocks, using a player radius of 2.2; on a
  blocked move speed is cut to 30% (`game.lua:772-776`, `292-297`).
- Obstacle radii: pyramids 2.2, blocks 1.8, rocks 1.4 (counted at 0.7×) (`game.lua:276`, `279`, `282`,
  `292-296`).

## Hazards and what kills the player

- Enemy tank shells: speed 40 (48 from a super tank), fired only when within 90 units and aimed within
  0.35 rad; cooldown 1.6–2.8 s (1.2–2.0 s for a super) (`game.lua:601-608`).
- Saucer shells: speed 35, aimed at the player, every 1.8–3.0 s (`game.lua:625-630`).
- Missiles: homing, start at speed 22 and accelerate 8/s up to 36, lifetime 12 s; a missile within 2.8
  units of the player calls `damage_player(1)` and explodes (`game.lua:541-548`, `632-660`).
- A shell hit within 2.2 units of the player damages him (`game.lua:826-833`).
- `damage_player` ignores hits while `P.invuln > 0` or outside state `play`; otherwise it sets 2.0 s
  invulnerability, removes one tank, explodes, and either ends the run (lives ≤ 0) or respawns the player
  15 units from the origin facing the origin (`game.lua:698-719`).
- Ramming an enemy tank does no damage; enemy tanks avoid obstacles but not the player, and only shells
  and missiles call `damage_player`.
- The world edge, props, mountains and ground are not lethal.

## What the player can kill

Pool sizes: 6 enemy tanks, 3 super tanks, 2 saucers, 3 missiles (`game.lua:504-510`).

| Target | HP | Score | Shell hit radius | Cite |
|---|---|---|---|---|
| Enemy tank | 1 | 1000 | 2.4 | `game.lua:551`, `820` |
| Super tank | 3 | 3000 | 2.8 | `game.lua:551`, `821`, `689` |
| Saucer | 1 | 5000 | 2.6 | `game.lua:551`, `822` |
| Missile | 1 | 2000 | 1.8 | `game.lua:551`, `823` |

- One player shell removes one HP; at 0 HP `kill_enemy` explodes it, scores it, hides it, and increments
  both `G.kills` and `G.wave_kills` (`game.lua:806-825`, `551-565`).
- Saucers fly at height 9 ± 2 and are hit in the x/z plane only, so height does not protect them
  (`game.lua:611-621`, `822`).
- Killing is the only way to progress a wave; there is no other objective.

## Waves

- `start_wave` increments the wave, resets the wave-kill counter, sets a 1.0 s spawn delay and shows a
  2.5 s banner (`game.lua:672-678`).
- Alive target is `min(2 + wave, 7)` (`game.lua:683`).
- Spawn interval is `max(1.5, 4.0 - wave*0.25)` seconds (`game.lua:685`).
- Spawn composition by one random roll (`game.lua:686-690`):
  - wave ≥ 3 and roll < 0.15 → saucer
  - wave ≥ 2 and roll < 0.35 → missile
  - wave ≥ 2 and roll < 0.55 → super tank (3 HP)
  - otherwise → enemy tank (1 HP)
  - Wave 1 therefore spawns only enemy tanks.
- A wave completes only when `wave_kills >= 5 + wave*2` **and** no enemy of any pool is alive; then the
  next wave starts (`game.lua:692-694`).
- Enemies spawn 50–100 units from the player (saucers 70+, missiles 80+), avoiding props and the world
  edge (`game.lua:514-523`, `526`, `534`, `543`).
- Enemy tanks close in when farther than 35 units, back off when closer than 18, at speed 12 (super 9),
  turn rate 2.2 (super 1.6) (`game.lua:582-598`).
- Saucers strafe in a circle at speed 14, altitude 9 ± 2 (`game.lua:611-624`).

## Timers and durations

| Timer | Value | Cite |
|---|---|---|
| Player fire cooldown | 0.55 s | `game.lua:785` |
| Player shell lifetime | 2.8 s | `game.lua:478` |
| Player invulnerability after a hit | 2.0 s | `game.lua:700` |
| Spawn invulnerability on a new game | 1.5 s | `game.lua:1067` |
| Enemy tank reload | 1.6–2.8 s (super 1.2–2.0) | `game.lua:603` |
| Saucer reload | 1.8–3.0 s | `game.lua:627` |
| Missile lifetime | 12 s | `game.lua:545` |
| Wave banner | 2.5 s | `game.lua:676` |
| First spawn delay | 1.0 s, then interval above | `game.lua:675`, `685` |
| Camera shake after a hit | 0.7 s | `game.lua:701`, `727-730` |

There is no freeze, slow, ladder, pickup, or power-up system in this game.

## Score, win, lose

- Score only from kills (`game.lua:551-561`). High score is tracked live during play when Jev is not
  assisted (`game.lua:557-560`) but is **not persisted**: there is no load/save for it, so it resets to 0
  each launch (`game.lua:18`).
- Win: none. `G.won` is never set anywhere in the file.
- Lose: `G.lives` reaches 0 in `damage_player`; state becomes `over` and the game-over menu offers Play
  Again / Title (`game.lua:706-710`).

## JevAuto.attach for this game

Attach block `game.lua:1331-1399`, port 9130, id `battlezone`.

`observe()` returns exactly `x`, `z`, `yaw`, `score`, `enemy_x`, `enemy_z`, `enemy_kind`
(`game.lua:1353-1370`). The wrapper adds `mode`, `terminal`, `score`, `busy`, `actions`
(`jev_auto.lua:54-61`). `enemy_*` describe the single nearest live enemy across all four pools
(`game.lua:1303-1325`); `enemy_kind` is `"enemy"`, `"super"`, `"saucer"`, `"missile"`, or `"none"`.
No `busy` hook is defined, so busy is always false.

Action ids produced by `actions()` (`game.lua:1371-1387`): `forward`, `left`, `right`, `forward_fire`.
- No enemy → `forward`.
- Bearing error to the nearest enemy > 0.18 rad → `left`; < −0.18 → `right`.
- Otherwise → `forward_fire`.

`apply(id)` (`game.lua:1282-1301`):
- `left` / `right` set the held virtual mouse turn `G.vmdx` to −32 / +32; `straight` sets it to 0
  (`game.lua:1283-1288`; converted to yaw rate in `update_player`, `game.lua:758-769`).
- `forward` / `back` set the held thrust; `stop` clears it (`game.lua:1271-1276`, `1289-1294`).
- `fire` queues a one-shot Space pulse; `forward_fire` sets forward thrust and also pulses Space
  (`game.lua:1278-1280`, `1295-1300`).
- Turn and thrust are independent holds: an action that changes one leaves the other in place until
  replaced.
- Unknown ids do nothing.
- `reset(seed)` seeds `math.random`, clears holds and starts a new game (`game.lua:1391-1395`);
  `on_human` clears holds (`game.lua:1396-1398`).

## Jev cannot see

- Lives, wave number, kill count and progress toward the wave-kill target.
- Every enemy except the nearest one; enemy HP, heading, speed, and which pool slot is alive.
- Saucer altitude and missile lifetime/speed.
- Incoming enemy shells and missiles as objects (only the missile counts as an "enemy" here), so there
  is no way to dodge a shell.
- Own invulnerability timer and fire cooldown, own speed, and whether the tank is currently blocked.
- Obstacles (pyramids/blocks/rocks) and their radii, even though they block movement.
- Pause/menu state and whether the player is in settings.
- High score (and it is not persisted).
