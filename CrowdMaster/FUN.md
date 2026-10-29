# Crowd Master: Fun Notes

## What Makes Count-Masters-Likes Fun (Research)
- **One readable decision every 2–4 seconds.** A gate pair is a tiny maths puzzle that you solve in a glance, and the result is shown at once: the crowd visibly balloons or shrinks.
- **Power fantasy, then a test.** Growth (gates, cages, air drops) always comes before a check (a red crowd, a trap or the finale). Rewards outscale the challenge, so a good run *feels* huge.
- **Non-linear intensity.** Each peak (a clash or a trap gauntlet) is followed by a relief or reward zone (a coin line or a cage). The speed varies between about 0.7x (mud) and 1.3x (ice).
- **Teach one thing at a time, then combine.** A new mechanic first appears alone with a tip banner. Later it is mixed with others (for example ice plus a saw lane).
- **Juice.** Count pops, FOV punch, screen shake, confetti on big multipliers, sparks on hits, near-miss "Close Call!" and a rising pitch when coins chain.
- **Loss is never random.** Traps take a bite, not the whole crowd. A narrow floor squeezes the blob early, and the edges gently herd you on, so a fall comes from fighting the herding.
- **Meta loop.** Coins and gems lead to upgrades and army merges, so the next attempt is stronger. Every run pays out, even a lost one.

## My Own Twists
- **Unit tiers.** Pawn (1 power) → Brute (3 power, 2 HP) → Giant (8 power, 4 HP).
  - **Merge gates** (gold) turn pairs into the next tier. It is a real choice: big units survive traps and terrain, but × gates multiply pawns only.
- **Gate traps.**
  - **Trick gates** (striped) scramble and can flip.
  - **Timed lamp gates** toggle.
  - **× gates** are followed straight away by a trap.
  - **Guarded gates** have a hazard in front.
- **Terrain.**
  - **Oil:** drift; edges are dangerous.
  - **Ice:** fast and slippery.
  - **Mud:** slow.
  - **Gravel:** slow, with a light bleed.
  - **Brambles:** bleed pawns; big units shrug them off.
- **Assists.** Breakable cages free grey captives, air drops add units, and a golden giant ally joins you.
- **Finales.**
  - A trophy staircase (the top steps give gems). The crowd runs straight onto it as one column, and each step it pays for leaves a runner standing and cheering on that step.
  - **Merged reach.** A merged unit climbs higher in proportion to the pawns merged into it. When a step takes the last bite out of a Brute it climbs 1 step further, and a Giant climbs 3 further. Formally, a unit made of N base pawns stands on step k + N − 1, where N is 2 for a Brute, 4 for a Giant and 1 for a Pawn or Breaker. Examples: 2 pawns merge into a Brute, and 2 Brutes (4 pawns) merge into a Giant. A "Brute +1 Step" or "Giant +N Steps" popup and a ring mark every step beyond the paid one, with confetti on every 5th. The payout (×multiplier, stars, gems, the trophy chest) follows the highest step **reached**, not just the steps paid for. That makes merging before the finale a real choice. The bonus is bounded at +1 step for Brutes and +3 for Giants (+0.6× at most), so the economy stays sane.
  - Every 3rd level, a king boss with an HP bar. Boss Breaker units hit him extra hard.
- **Economy.**
  - **Coin upgrades:** Starting Crowd, Gate Power, Trap Armor, Run Speed, Clash Might and Treasury (income while playing).
  - **Gem powers:** Shield Bubble (Space), Coin Magnet, Boss Breakers and Lucky Eye.
  - **Army board:** recruit pawns, then drag or click to merge them. The board army joins every run.

## Pacing Across The 12 Levels (4 Worlds)
| World | Levels | New Ideas |
|---|---|---|
| Meadow Isles | 1–3 | Gates, a red crowd, spin bars, cages, merge gates, saws, gravel, the first boss |
| Sunbaked Canyon | 4–6 | Mud, hammers, pits, oil, trick gates, crushers, the giant ally, timed gates |
| Frost Bay | 7–9 | Ice, narrow bridges, brambles, combined gauntlets |
| Ember Coast | 10–12 | Everything mixed, longer runs, the Ember Throne boss |

## Tuning Log (Autoplay Bot, tools/autoplay.sh)
- **05:00:** a greedy bot cleared L1 with 3 stars, but lost L2–L12 every time. The causes:
  - spin bars wiped the whole crowd;
  - oil drift pushed the crowd off the track;
  - the bridge squeeze came too late;
  - enemies were sized for a perfect run.
- **Fixes:**
  - each trap pass is capped at 20% of the crowd;
  - the floor squeeze looks 6.5 m ahead;
  - an edge assist was added;
  - oil and ice drift are clamped;
  - bramble bleed: 0.45/s → 0.13/s; gravel bleed: 0.1/s → 0.035/s;
  - red crowds are now 55–62% of their old size; boss HP is 70% of its old value.
- **05:20:** red crowds and boss HP are now sized automatically from a simulated "good line" through each level (start 10, best gate, cages/drops/allies taken, a bite per trap), so every level is provably winnable and difficulty climbs smoothly with the level number.
- **05:40:** traces (tools/trace.sh) showed most losses were falls, not fights:
  - a crowd steering for the next gate while its rear rows were still over a pit;
  - a crowd beside a bridge got no help onto it, and widened again before its rear rows left the bridge.
  - Fix: the squeeze and the edge assist now sample the whole crowd depth (rear to +6 m) and lead the crowd onto the nearest strip. Falls on L9 went from 56 to 0. You can still steer off on purpose, and oil/ice can still push you.
- **05:45:** gentler curve: red crowds at 0.38 + 0.022 × level of the good-line power, boss HP at 0.5 + 0.015 × level.
- **2026-10-29, human-like pass (tools/headless.lua, G.bot="human", 40 trials, 60 Hz):** the owner could not finish L6. The greedy bot reads lamp and trick gates perfectly, so red crowds were sized for a perfect read; a human misreading one of L6's two lamp gates (x2/−10, x3/−20) arrived at the final crowd far too small. Now lamp/trick gates are sized from the middle of both outcomes, misreads cost a multiplier instead of runners, a retry boost (+3 runners, −4% foes per failed try, max 4) helps a stuck player, and the loss tip points to the Camp when an upgrade is affordable.

  | Level | fresh before → after | modest before → after | owner's upgrades before → after |
  |---|---|---|---|
  | L1 | 98 → 98 | 98 → 98 | 100 → 100 |
  | L2 | 100 → 100 | 100 → 100 | 100 → 100 |
  | L3 | 75 → 100 | 93 → 95 | 98 → 95 |
  | L4 | 100 → 100 | 100 → 100 | 100 → 100 |
  | L5 | 78 → 100 | 60 → 90 | 70 → 100 |
  | L6 | 85 → 93 | 73 → 90 | 65 → 98 |
  | L7 | 100 → 100 | 100 → 100 | 100 → 100 |
  | L8 | 83 → 95 | 88 → 95 | 88 → 93 |
  | L9 | 90 → 95 | 95 → 88 | 55 → 100 |
  | L10 | 78 → 98 | 83 → 100 | 50 → 98 |
  | L11 | 90 → 88 | 100 → 100 | 80 → 100 |
  | L12 | 48 → 95 | 40 → 98 | 58 → 100 |

  The greedy bot (fresh) wins 100% everywhere (was 98% on L6 and L10). Remaining losses are mostly at the L6/L9 bosses and the L8 final crowd, which keeps some tension.
