# Gatebreaker Squad: Fun Notes

Why the Last War style "gate shooter" ads hook people, and how this game turns that hook into something you actually want to keep playing.

## 1. What the research says makes the genre fun
- **One input, constant decisions.** Steering left/right is all you do, but every second asks a small question: *which lane? shoot the gate or the crowd first?* (Hyper-casual design: minimal input, continuous micro-choices.)
- **Visible numbers growing.** A squad going 7 → 21 → 64 is a "number-goes-up" reward you can see, not read. Crowd counts are the core feedback loop.
- **Risk and reward on screen at once.** A red ÷2 gate next to a blue +6 gate is a readable gamble. The fun is in fixing a bad gate by shooting it.
- **Flow / difficulty curve.** Csikszentmihalyi's flow channel: challenge has to grow with skill. Short levels (about 1.5–3 min), each adding ONE new idea, then a boss as a test.
- **Juice.** Hit flashes, tracers, coin bursts, screen shake, big banners. The game must feel good even with your eyes half closed.
- **Meta progression (Crowd Master / Last War).** Coins → permanent upgrades → replay earlier levels for stars. "Just one more run" comes from always being close to the next purchase.
- **Surprise helpers.** Allies freed from containers and air strikes break the routine every 20–30 s (variable rewards).
- **Fair loss.** Losses should feel like *my* fault (a gate I picked, a brute I ignored), never random.

## 2. The fun meter we tuned against
| Metric | Target | Where it stands (simtest seeds 1/4/7) |
|---|---|---|
| Level length | 1.5–3.5 min | 100–200 s |
| New idea per level | 1 | L1 gates+crates, L2 brutes+fire-rate gates+barrels, L3 traps+shields+1st boss, L4 flyers+locked gates+barricades, L5 merge gates, L7 cryo hazards, L10 double boss |
| Event spacing | something new every 6–10 s | script pattern: gates / wave / crate / container / air / big / drop |
| Boss fight | 15–35 s, survivable with skill | 15–33 s (L3 Goliath was 60 s, fixed: gates now clear the arena) |
| Helpers | every 20–30 s | ally containers x2–3 per level, air strike button, gunship and supply drops |
| First-try win rate (good bot) | high on early levels, tight late | Pass 3: 10/10 from a fresh save (catch-up boost) and with upgrades; a bot that never steers loses every fresh level |
| Coins per run | 1 upgrade per 1–2 runs | upgrades cost 50–120 at Lv 0 |

## 3. Systems and why each one is there
- **Straight fire, you aim by steering:** Rifle, Minigun and Laser shoot straight ahead, the Shotgun a fixed fan. There is no auto-target, so moving left/right *is* aiming: line up a gate, then slide over to the brute. The squad widens a little as it grows but never covers the lane. Homing is a special treat: Rockets lock on (reticle, curving trail), and air strikes and freed allies seek targets.
- **Gates you shoot** (add, multiply, damage, fire rate, merge): shooting raises the value, so aim beats luck. Shots pass through gates (each gate counts once per projectile) and keep flying into the enemies behind, so pumping a gate never means giving up on the wave.
- **Snappy steering:** about 26 m/s lateral with quick acceleration and soldiers that catch up at once, so a dodge or re-aim feels instant.
- **Trap gates** (orange): look like a bargain but subtract unless you pump them. **Locked gates** (grey): break the lock for a big reward. These are risk choices.
- **Weapon crates and barrels:** Rifle → Shotgun → Minigun → Rockets → Laser. Each changes how you play (spread, burst, splash, pierce). Barrels explode into the crowd.
- **Containers that free allies** (the Crowd Master "breakable ramp" idea): Sentry Turret, Gunship, Ally Mech, Sniper Nest, Drone Swarm. Shoot the box open and a badass helper fights with you.
- **Air assists:** a charging Air Strike button, plus scripted gunship flybys and supply drops.
- **Enemies with a purpose:** runners (swarm), brutes (tanky, punish small squads), shielded (soak front damage), flyers (dodge the ground), bosses (Goliath, Ironclad, Wasp Queen) with telegraphed attacks.
- **Merging:** soldiers merge into Veterans and then Heavies (auto, a Merge button, and gold merge gates). The squad grows in quality, not only in size.
- **Economy:** coins from kills, gates and stars → 10 upgrade tracks, 6 heroes (coins + boss medals), 5 weapons to buy and equip. Best score and stars per level are saved.
- **Worlds:** Harbor, Canyon, Autumn Woods, Frost Bay, Ember Peaks, each with its own sky, floor, props and palette, so progress also feels like travel.

## 4. Feel / juice checklist
Straight velocity-aligned tracers, a subtle flowing aim cue at the fire-strip edges, rocket lock reticles, muzzle glow per weapon, hit flashes, floating damage numbers, coin pops, a "New Weapon!" banner, a boss HP bar and arrival hold, camera shake on explosions, an orbit camera and stars on the win card, "New Best!" on the win card, title-case UI, bright mobile palette, bloom 0.45, TAA.

## 5. Worth counter and merging (Pass 4)
- The number over the squad is total worth in soldier-equivalents: Soldier 1, Veteran 5, Heavy 20, hero 1. Merging never moves it, so a merge reads as an upgrade, not a loss; the counter flashes gold and a toast says what merged.
- What a merge buys: firepower 5 soldiers (5) -> 1 veteran 5 x (1 + 0.1 x Elite), so +0% at Elite 0 up to +100% at Elite 10; 4 veterans (20) -> 1 heavy 22 x (1 + 0.1 x Elite), +10% at Elite 0. HP stays the same (vet 5 hits, heavy 20), but soldiers take hits first, so elites are a protected core. Fewer bodies means a tighter formation and more of the squad fits in the 30 drawn slots.
- Multiply gates multiply worth, so the ladder is gentler (x1.5 / x2 / x2.5) to keep growth in the old range.
- Gates fill from damage, not hit count: every point of squad damage (crits, rocket splash, upgrades) moves the meter under the gate.
