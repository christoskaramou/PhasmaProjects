# Why Banners & Borders is fun: design notes

## The core loop
1. Look at the map.
2. Spot a weak border.
3. Drag across a few of your regions.
4. Release on the target.
5. Watch a stream of tiny soldiers march.

Each decision takes about a second. The game then spends 5–15 s showing you the result as a moving column you can
read at a glance. That gap between a fast decision and a slow, readable result is the hook.

## Snowball tension
- Every region you own recruits troops up to its cap, so territory grows your army, which wins more territory.
- The snowball has brakes:
  - **Caps**: a full region stops recruiting, so hoarding troops wastes time. You must spend them.
  - **Garrisons cost time**: neutral garrisons scale with region size, so the first minute is a race over which
    neutrals to take, not whether to take them.
  - **Neutrals heal**: a neutral you chip at but don't take regrows (+1 every 4 s after a 5 s pause) back to its
    starting garrison, so half-hearted pokes are wasted. Commit, or leave it alone.
  - **AI target choice**: AIs pick the most valuable reachable target for their personality, so the leader draws
    fire. The Emperor (boss) has `pbias 1.5` and goes after you first.

## 1–3 minute rounds
- Early battles (Greece, small countries) finish in about 35–120 s for a strong player. Mid-campaign continent maps
  take 1.5–3 min.
- Only the finale (the whole world, 40 regions, two oceans) is a 6–8 min war, and it marches 1.6× faster so the
  oceans do not drag.
- Par times sit just above a strong player's time: beat par for 3 stars, 1.6× par for 2 stars.

## Swarm streams
- Troops are not a number sliding along a line. Each one is a small 3D soldier in a column, so a big attack looks
  big and a desperate trickle looks desperate.
- **Mid-path clashes**: enemy columns meeting on the road fight soldier for soldier. Intercepting an attack is a real
  tactic, and the clash VFX make the board feel alive.

## Readable numbers
- Every region has a large pill badge in its owner's colour with the troop count, and a gauge under it fills toward
  the cap.
- Region-type icons (capital, fort, port, mine) appear on the badge, so you can see what each region does without
  reading tooltips.
- Hovering any region opens a parchment card with troops/cap, recruits per second, defence multiplier and the
  region-type rule, so you can do the maths before you commit.
- While aiming, a line of big dots shows exactly where the march will go and pulses toward the target ring.
- A top bar shows each faction's share of total strength. You always know who is snowballing.

## Overextension risk
- Sending 100% empties the source regions. The **50% / 100% toggle** (`Enter`/`Space` or the tray button) is the
  core risk dial.
- The vulture AI watches for regions you have just stripped and for fights that leave both sides weak, then strikes.
- On continent maps the empty interior (Sahara, Outback, Siberian steppe) is cheap to take but slow to cross, which
  invites you to overreach.
- Water crossings slow every army except troops sent from **ports**, so islands are tempting but cut off.

## Aggressive but beatable AI
Personalities differ in behaviour, not just numbers:

| AI | Behaviour |
|---|---|
| Steady | Expands sensibly and defends threatened regions |
| Warlord | Big infrequent hammer blows; uses barrage and forced march |
| Vulture | Opportunist that strikes whoever was just weakened |
| Emperor (boss) | Uses every ability, starts with a big army, focuses you |
| Passive | Tutorial only |

- AIs start after a short delay (6 s down to 3 s across the campaign), so your opening plan matters.
- AI production ramps up from 85% to 95% of yours, which keeps the curve smooth.
- When an AI's whole front is near its caps, it masses troops from far away. Stalemates break, and the AI can cross
  oceans, so you can't simply turtle.

## Comebacks
- Abilities on cooldowns let a losing player swing a fight:
  - **Airdrop** drops troops anywhere.
  - **Frost** freezes a threatening stack.
  - **Barrage** shreds a big garrison or column.
  - **Forced March** speeds up an all-in.
- A losing AI is still dangerous because the vulture also preys on the leader's overextended edges.
- Coins carry over even from lost battles. Five permanent upgrades (Recruitment, Swift Boots, Veteran Start,
  Bastions, Quartermaster) make a retry slightly easier without being needed: every level is beaten from a fresh
  save in the headless sim.

## Pick your challenge
- **Relaxed / Normal / Hard** (Options). Normal is tuned with a headless casual autopilot. That bot clears early
  Europe almost every time and most later battles more often than not. A skilled autopilot still wins every battle,
  and an idle one never does.
- **Retry Boost**: losing a battle makes the next attempt slightly kinder (more starting troops, slower enemy
  recruiting, up to 4 steps). A popup tells you, and it resets once you win, so being stuck never lasts long.
- **Pars**: par sits halfway between a skilled and a casual win time. 3★ asks for skill, and 2★ comes from
  simply winning at a steady pace.

## Pacing across the campaign
22 battles over six acts and every inhabited continent:

| Act | Region | Battles |
|---|---|---|
| I | Europe | 1–8; tutorial, then a boss |
| II | Africa | 9–11 |
| III | Asia | 12–15; boss at 14 |
| IV | Oceania | 16–17 |
| V | South America | 18–19 |
| VI | North America | 20–21 |
| Finale | The world | 22 |

- Maps alternate between small countries (fast, tactical) and continents (sprawling, strategic), so the rhythm keeps
  changing.
- Abilities unlock at battles 2, 3, 5 and 7, so you learn one tool at a time.
- The world campaign screen shows your march around the globe: pins, a gold path, stars per battle, and progress per
  continent. That is a meta goal that is visible every time you return to the menu.
