# 1942Remix — how the game works (read from current source)

Source of truth: `Arcade/1942Remix/Assets/Scripts/game.lua` (1401 lines). That file is a byte-identical
concatenation of `Arcade/1942Remix/tools/src/0*.lua` produced by `tools/build_lua.sh:1-3` (verified by
comparing the concatenation to the live file). All cites below are `Assets/Scripts/game.lua` lines.
Jev wrapper: `Assets/Scripts/jev_auto.lua`; driver: `Assets/Scripts/gamekit/driver.lua`.
`run.ps1` does not name a script; it launches `Scenes/main.pescene` (`run.ps1:29-30`), and the scene
loads `Scripts/game.lua`.

## Shape of a run

- Fixed simulation step 1/60 s, at most 6 steps per frame (`game.lua:159`, `1305-1313`).
- Field is 24 wide and 30 tall, x ∈ [-12, 12], y up the screen 0..30; all planes fly at altitude 5
  (`game.lua:71-72`, `74`, `339`).
- 32 stages, played in order `k = 1..32`; displayed stage number is `G.num = 33 - k`, so the run starts
  at stage 32 (Midway) and ends at stage 1 (Tokyo) (`game.lua:517-518`, `269-274`).
- Stage name bands by displayed number: 29+ Midway, 25+ Marshall, 21+ Attu, 17+ Rabaul, 13+ Leyte,
  9+ Saipan, 5+ Iwo Jima, 2+ Okinawa, else Tokyo (`game.lua:269-274`).
- Every displayed stage number ≡ 1 mod 4 is a boss stage (29, 25, 21, 17, 13, 9, 5, 1) (`game.lua:275`).
- Stage phase machine: `takeoff` → `fly` → `landing` → `result` → next stage; after k=32 the phase is
  `won` then `done` and the run ends (`game.lua:526`, `563-597`, `593`, `1317`).
- New game: score 0, 2 reserve planes, quad off, no escorts, POW sequence index 0, stage k=1
  (`game.lua:533-537`).

## Stage flow, stage by stage

- `start_stage(k)` clears shots/bullets/enemies/POWs, builds that stage's wave list and total wave time
  `G.T`, resets loops to 3, puts the player at (0, 3.2) and enters `takeoff` with the carrier on
  (`game.lua:514-531`).
- Wave list per stage (`build_waves`, `game.lua:291-332`):
  - `T = 56 + min(k,16) * 1.25` seconds of waves (`game.lua:294`); enemy speed scale
    `sp = 1 + min(k,24) * 0.015` (`game.lua:296`).
  - Red formation every 9–13 s starting at 6–9 s: five `red` planes in `snake` AI, entering from one
    side, speed 9.5·sp (`game.lua:297`, `300-304`).
  - From k≥2, a `mid` bomber roughly every 15–21 s (minus 0.2·min(k,20)): 60% `rise` from below,
    else `sink` from above (`game.lua:305-308`).
  - Otherwise a pack of `zero` fighters, `nb = floor(2 + R(0, 1 + min(k,20)*0.08))` planes, in one of
    five patterns: `dive` at the player (28%), `loop` (22%), `cross` from a side (18%), `behind` from
    below only when k≥2 (16%), `swoop` from a top corner (rest) (`game.lua:310-327`).
  - Pack spacing 1.5–2.4 s minus 0.025·min(k,20) (`game.lua:328`).
  - Per-stage randomness is a fixed LCG seeded from `k`, so the same stage always has the same waves
    (`game.lua:287-289`, `291-292`).
- `takeoff` lasts 3.0 s: the player is moved automatically from y 3.2 to 6.2 and altitude 1.55 to 5;
  no input, no firing (`game.lua:563-569`).
- `fly`: waves spawn when their time arrives; when all waves are out, the boss flag is not already done,
  and `G.st > G.T + 2`, the `big` boss spawns at (0, 7 below the field) (`game.lua:599-605`).
- Boss behavior: for 40 s it holds `v = 0`, slides y toward 22 and x toward `6*sin(t*0.35)`, heading 0;
  after 40 s it accelerates to speed 9 and flies off (`game.lua:397-403`).
- `landing` starts when: all waves spawned, boss done, player alive, no live `mid`/`big` that has
  entered, at most 2 enemies on the field, and that condition has held 2.5 s; the field is then cleared
  and the carrier enters from above (`game.lua:677-692`).
- `landing`: the carrier descends to y 12 at 7/s; the player is pulled to (0, carrier.y−6) and, once the
  carrier is at 12, descends at 1.6/s; the phase ends when altitude ≤1.56 and landing time >3.5 s
  (`game.lua:571-586`).
- Landing computes the stage result: `rate = killed/spawned`, bonus 20000 if rate ≥0.999 else
  `floor(rate*100)*100` (`game.lua:582-584`).
- `result` lasts 4.0 s, then `start_stage(k+1)`; after k=32 it sets `won` instead and plays the ending
  (`game.lua:591-596`).

## Player actions

- Movement: analog 8-way from WASD/arrows, normalized, speed 12.5 units/s; x clamped to ±10.9, y to
  1.6..27 (`game.lua:498-502`, `1299-1300`).
- Fire: one volley per press/click; Space/Z/J/left click (`game.lua:1274`). A volley is 2 shots
  (`x ± 0.24`), 4 shots when quad guns is active (`x ±0.62, ±0.22`), plus one shot per live escort
  (`game.lua:477-485`). No new volley while 3 or more "lead" shots are still in flight, which is the
  effective fire-rate cap (`game.lua:478-480`).
- Loop/roll: X/K/Shift/right click; 3 per stage; lasts `ROLL_T = 1.6` s, during which the plane is
  invulnerable to bullets and body contact and cannot fire (`game.lua:339`, `343`, `504-509`, `631`,
  `656`).
- Player shots travel straight up at 46 units/s (`game.lua:611`).
- Player hitbox: circle radius 0.36 for body contact, 0.53 for enemy bullets (`game.lua:634`, `658`).
- Escorts sit at ±2.0 x, −0.4 y from the player; their hitboxes are 0.3 (contact) and 0.47 (bullets)
  (`game.lua:346`, `643`, `662`).
- Death: player explodes, loses one reserve plane, respawns at (0,5) after 2.4 s with 2.5 s
  invulnerability and all enemy bullets cleared (`game.lua:459-464`, `488-495`).
- If reserve planes are below 0 at respawn time, `out_of_lives` is set and the run ends
  (`game.lua:491`, `1316`).

## Hazards and what kills the player

- Body contact with any live, entered enemy circle while not rolling and not invulnerable; if the enemy
  is a `zero` or `red`, it dies too (`game.lua:631-636`).
- Enemy bullets: hit if within 0.53 and not rolling/invulnerable; the bullet is removed (`game.lua:652-666`).
- Enemy bullet cap is 70 on screen; `ceasefire > 0` blocks new enemy bullets (`game.lua:367-370`).
- Kinds and collider circles are defined per enemy kind (`game.lua:278-285`); circle offsets rotate with
  the enemy heading (`game.lua:348-355`).
- Islands, clouds, the carrier and the ocean are decorative: no collision code exists for them
  (`game.lua:739-806`). There are no ground targets, mines, walls, or ladders.

Enemy fire (`game.lua:410-428`):
- `zero`/`red`: at most 1 bullet (2 from stage k≥12), only when above the player by 3+ and y < 29.5,
  random chance `0.35 + 0.02k`; reload 0.9–1.8 s. Bullet speed `8.5 + 0.09k` (`game.lua:411-416`).
- `mid`: 3-shot spread ±0.24 rad, reload `max(0.9, 1.7 - 0.02k)` (`game.lua:417-420`).
- `big`: alternating salvos — odd: 5-shot spread ±0.2; even: two 3-shot spreads from x ±3; reload
  `max(0.7, 1.15 - 0.012k)` (`game.lua:421-426`).

## What the player can kill

- `zero` hp 1, 50 pts; `red` hp 1, 100 pts; `mid` hp 14, 1500 pts; `big` (boss) hp
  `150 + 4*k`, 10000 pts (`game.lua:279-284`, `360-361`). One player bullet = 1 damage
  (`game.lua:455-457`, `618`).
- Body contact also destroys a `zero`/`red` (but kills the player) (`game.lua:635`).
- White POW damages every entered enemy: `big` takes 40, everything else dies (`game.lua:546-554`).
- Killing any 5 planes of the same formation group spawns a POW at the fifth kill's position, clamped
  into the field (`game.lua:437-444`).
- The boss can survive by flying away: when it passes y > 38 it sets `boss_done` without being killed
  (`game.lua:629`). Boss kills set `boss_done` and add a 1.4 s screen shake plus staged explosions
  (`game.lua:446-452`).
- Enemies leaving the field are removed: y < −6, y > 39, or |x| > 21 (`game.lua:628`).

## Timers and durations

| Timer | Duration / rule | Cite |
|---|---|---|
| Loop invulnerability | 1.6 s per loop, does not stack; roll timer decremented each step | `game.lua:343`, `504-507` |
| Loops per stage | 3 at every `start_stage`; +1 per gray POW | `game.lua:524`, `543` |
| Respawn invulnerability | 2.5 s, all enemy bullets cleared | `game.lua:492-493` |
| Death delay before respawn | 2.4 s | `game.lua:461`, `489` |
| Yellow POW ceasefire | 10 s; blocks new enemy shots only | `game.lua:544`, `368`, `559` |
| Enemy hit flash | 0.08 s | `game.lua:456` |
| Boss hold then exit | 40 s hold, then accelerates away | `game.lua:398-403` |
| Quiet time before landing | 2.5 s | `game.lua:682` |
| Takeoff | 3.0 s | `game.lua:564` |
| Landing finish | altitude ≤1.56 and landing time >3.5 s | `game.lua:580` |
| Result card | 4.0 s | `game.lua:592` |
| Banner text | per-call 1.0–2.6 s, fades over last 0.4 s | `game.lua:266-267`, `968-970` |

## Pickups (POW)

POWs drift down 1.4/s and sway ±0.8·cos; collected within 1.25 units; despawn below y −2
(`game.lua:669-675`). Colors cycle through a fixed 12-entry sequence per formation drop
(`game.lua:334-335`, `440-441`). Effects (`apply_pow`, `game.lua:539-555`):
- red → quad guns (4-shot volley), permanent for the run until death? Quad is not cleared on death; only
  `player_die` clears escorts (`game.lua:461`), so quad persists.
- green → both side fighters (escorts), lost individually on contact or bullet hit.
- gray → +1 loop.
- yellow → 10 s enemy ceasefire and clears current enemy bullets.
- orange → +1000 points.
- white → destroys all entered enemies (40 damage to boss) and clears enemy bullets.

## Score, win, lose

- Enemy scores as above; formation drop is not itself scored; orange POW +1000 (`game.lua:435`, `545`).
- Stage bonus: 20000 for 100% killed, else `floor(rate*100)*100` (`game.lua:582-584`).
- Extra plane at 20000, then every 80000 after that (threshold becomes 100000, 180000, …); awards one
  reserve plane and a banner (`game.lua:258-265`).
- Hi-score starts at 40000, loaded from `Save/s1942_hiscore.txt`, saved only when the run ends and Jev
  was not the assisted player (`game.lua:255-257`, `1032-1035`).
- Win: clear stage k=32 (displayed stage 1) → `G.won`, state `over` (`game.lua:593`, `1317`, `1029-1031`).
- Lose: `G.lives < 0` when a respawn is due → `out_of_lives` → state `over` (`game.lua:491`, `1316`).

## JevAuto.attach for this game

Attach block `game.lua:1349-1393`, port 9136, id `1942remix`.

`observe()` returns exactly these fields inside `observation` (`game.lua:1369-1380`): `player_x`,
`player_y`, `aim_dx`, `aim_dy`, `lives`, `loops`, `score`. The wrapper adds `mode`, `terminal`,
`score`, `busy`, `actions` (`jev_auto.lua:54-61`). `aim_dx`/`aim_dy` are a derived aim vector, not a raw
enemy position: nearest live enemy if it is at least 1 unit above the player, else (0, 5), then pushed
sideways by nearby enemy bullets (`game.lua:1161-1197`).

`busy()` is true while the player is alive and the roll timer is running (`game.lua:1365-1367`).

Action ids produced by `actions()` (`game.lua:1199-1224`, direction table `1038-1064`):
`up`, `up_right`, `right`, `down_right`, `down`, `down_left`, `left`, `up_left`, and `loop`.
- If loops remain, not already rolling, and an enemy bullet is within |x|<1.6 and −0.5<y<4 of the
  player, `actions()` returns only `loop` (`game.lua:1201-1209`).
- Otherwise it returns one direction: the 8-way step whose dot product with the aim vector is largest
  (`game.lua:1211-1223`). `stop` exists in the ordering table but has no step vector, so it is never
  returned (`game.lua:1060-1064`, `1213-1215`).

`apply(id)` (`game.lua:1099-1116`):
- A direction id sets the virtual Up/Down/Left/Right keys to that direction's pattern, replacing the
  previous hold; while a direction is held the game also keeps firing (driver flag `driving` plus any
  direction key forces `q.fire`) (`game.lua:1100-1106`, `1276-1278`).
- `loop` sets virtual `X`, arms its edge, and queues a one-shot pulse that is released after the next
  update (`game.lua:1108-1116`, `1118-1133`).
- Any other id returns without changing anything (`game.lua:1109-1111`).
- `reset(seed)` seeds `math.random`, clears holds, enables `driving`, and starts a new game
  (`game.lua:1383-1388`); `on_human` clears holds and disables `driving` (`game.lua:1389-1392`).

## Jev cannot see

- Stage number and stage name (`G.num`), stage phase (`takeoff`/`fly`/`landing`/`result`), and whether
  the carrier is on screen.
- Every enemy: count, kind, position, heading, hp, and boss presence/hp. Only the derived `aim_dx/dy`
  hints at one target.
- Enemy bullets as objects: count, positions, and which one is close. They are folded into `aim_dx`.
- POWs on the field, their colors, and the next color in the POW sequence; formation kill counts.
- Escort fighters alive/dead, quad-gun state, and the player's invulnerability timer.
- The roll timer value (only `loops` count and `busy` are exposed), the ceasefire timer, and the
  remaining-wave/stage progress or clear percentage.
- Player shots in flight, so the 3-volley fire cap is invisible.
- Hi-score and whether the current run is Jev-assisted.
