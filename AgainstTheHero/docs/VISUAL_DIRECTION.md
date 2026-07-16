# ATH Visual Direction

This is the player-facing visual contract for Against the Hero. Implementation locations and
replacement constraints live in [VISUALS_DB.md](VISUALS_DB.md).

## Priority order

When visuals compete, the lower-priority layer yields:

1. Hero position, health danger, and the next incoming hit.
2. Enemy role, attack windup, and impact area.
3. Hit confirmation, status state, and boss phase information.
4. Loot, navigation, and interactable UI.
5. Decoration, ambience, and secondary motion.

No biome palette, particle burst, damage number, or decorative animation may hide a higher layer.

## Shape language

- Use chunky forms, bold outer silhouettes, limited internal noise, and readable negative space.
- The hero must remain identifiable at the normal top-down camera through outline, stance, and
  motion—not only color.
- Light and Heavy Brawler must be distinguishable from ten seconds of silent combat footage.
- Chasers read compact and forward-leaning; archers expose a ranged weapon or narrow firing pose;
  chargers read broad and directional; walking bombs read round and unstable with a pulsing fuse.
- Fliers need altitude separation through body height and ground shadow, not color alone.
- Every boss needs a unique silhouette and signature anticipation pose. Scale or tint alone is not
  sufficient identity.

## Telegraph grammar

- A 0.4-second white flash means a melee windup.
- A ground decal appears 0.8 seconds before an area impact.
- A red tint means a must-dodge attack.
- Anticipation, impact, and recovery remain visually distinct.
- Hit flashes, status tints, and elite gold must never overwrite an active must-dodge signal.
- Never combine more than three demanding tactical roles before late waves.
- Biome colors may vary, but warning meanings do not.

## Color and effects

- Reserve gold for elite, reward, and high-value emphasis; reserve red for danger.
- Status colors stay stable across every mode and match their damage numbers and HUD treatment.
- Effects reinforce an event already expressed by pose, shape, or decal; they do not carry gameplay
  meaning alone.
- Keep the impact point visible. Particles expand away from the hero/enemy contact silhouette.
- Screen shake, bloom, and high emissive values are accents. Combat must remain understandable with
  shake disabled.

## Sprite and animation contract

- Sprites are authored facing right; runtime mirrors them for left-facing movement.
- Standard sheets provide `idle`, `walk`, `attack`, `hit`, and `death`; boss sheets also retain every
  named signature clip used by their skills.
- Shared clips preserve timing readability: anticipation before execution, then a visible recovery.
- Transparent padding must remain consistent with the current contact and body-radius assumptions.
- Replacement sprites keep a clean alpha channel, bold outline, and readable ground contact.

## UI contract

- Combat HUD uses short labels, high contrast, and stable locations. Decoration never competes with
  health, boss, reserve, dodge, flask, or gold information.
- The navy/teal/purple/gold shell is a hierarchy: navy recedes, teal frames equipment/navigation,
  purple marks selection, and gold marks title/reward emphasis.
- Text must remain legible inside the fixed 20:9 gameplay band and at 16:9 window edges.
- Hover details may be rich; persistent combat labels stay minimal.

## Review captures

For a visual change, compare the same Release-build views before and after:

1. Hero idle, move, attack, hit, and death at the normal arena camera.
2. Chaser, archer, charger, and walking-bomb windups in one representative wave.
3. Elite tint, each active status tint, and overlapping must-dodge telegraphs.
4. One boss signature attack, phase transition, and death.
5. Combat HUD, inventory, skill tree, settings, world map, and one hover tooltip.

Use identical camera, window size, wave state, and UI scale. A replacement is not accepted from an
isolated sprite-sheet preview alone.

## Acceptance gates

- In at least 7 of 10 deaths, the player names the killer unprompted and the death recap agrees.
- By wave three, telegraphed attacks are dodged through rather than only outrun.
- An observer distinguishes Light from Heavy Brawler within ten seconds of silent footage.
- Each tactical enemy role is identifiable before its first attack lands.
- Boss anticipation remains readable when status effects and damage numbers overlap it.
- Every changed screen passes a before/after capture review with no lost text or clipped controls.
