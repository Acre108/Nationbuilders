# Hearthlands: design summary

Condensed from the full prototype proposal. This is the reference for anyone building the prototype.

## Pitch

Hearthlands is a light but challenging town builder. Each 60–90 minute session founds one village on a hard site. The village can fail; every village that succeeds permanently joins a growing nation. Each village has a culture and pledges to a political faction. Each nation turn, patrols and expeditions turn wilderness into civilised land. Over many sessions the nation grows from the medieval age to the modern age.

## Pillars (use these to decide what to cut)

1. **Small, finishable, hard-won.** A village is 15–40 buildings on a compact map. Runs are challenging and can fail.
2. **Chains you can read at a glance.** No chain is longer than 4 links (wheat → flour → bread). Every building shows what it needs and what it is missing.
3. **Permanence with purpose.** Nothing is thrown away. A failed village leaves a ruin that can be resettled.
4. **Place matters.** Terrain, culture, neighbours and threats decide what a village is good at.
5. **Wild to civilised.** Every nation turn visibly turns wilderness into settled, connected land.

## Core loop

- **Village run (real time).** Found the village (pick the site and culture) → survive and grow (winters, raids, needs tiers) → build its specialty around the unique resource → charter it, or fail into a ruin.
- **Nation turn (one per run).** Goods flow along roads → factions react (power, demands) → threats resolve (raids against patrols and defences) → companies tame the wild (scout, patrol, expedition) → choose the next site.

## Village layer

- **Map.** About 40×40 tiles, cut from a nation hex. Each site has 1–2 *signature deposits* (iron, clay, timber, fish, wool, fertile soil). Harsh biomes (marsh, tundra, mountain pass) are harder but hold rare deposits.
- **Needs tiers.** Population is counted per house; individual citizens are not simulated. A house upgrades once its tier is satisfied.

| Tier | Name | Needs | Unlocks |
| --- | --- | --- | --- |
| 1 | Settlers | Shelter, water, basic food (berries, fish) | Woodcutter, farm, well |
| 2 | Villagers | Bread or meat, firewood, a chapel | Mill, bakery, smithy, market |
| 3 | Townsfolk | Varied food, tools, cloth, a tavern | Workshops, signature industry, export depot |

- **Chains.** 6–10 chains per age, each 2–4 links. Carriers move goods between buildings and storehouses, so roads and storehouse placement are the spatial puzzle.
- **Pressure.** Seasons drain food and fuel. Events strike (fire, plague, blight, beast attacks). Frontier sites get raids.
- **Charter.** Available once the village reaches Tier 3 with an export depot running. The player picks a role (Producer, Garrison or Market) and the village pledges to its culture's faction.
- **Failure.** A village fails when population reaches 0, it is overrun, or morale collapses for a full season. It becomes a ruin, which can be resettled later with a bonus.

## Nation layer

- **Map.** A seeded hex map of 150–250 hexes. Each hex has a terrain, deposit hints and a wildness level from 0 to 5 (0 = civilised).
- **Nodes.** Each chartered village is a node that produces an export bundle every nation turn.
- **Network.** Roads have a capacity per tier. Goods flow automatically to the nodes that need them; a simple flow solver handles this, with no unit pathing.
- **Promotion.** 3 or more linked villages that satisfy a needs basket can promote a hub to a town.
- **Military.** 3–6 companies. Each company gets one order per turn: Scout, Patrol, Expedition, Escort or Garrison. Odds are shown before committing, the order auto-resolves, and the result appears on an event card.
- **Threats.** Raids travel predictable routes. Each raid's strength is compared against defence coverage plus any patrol on the route; a lost raid sends the node into decline.

## Cultures and factions

| Culture | Thrives on | Faction | Faction wants |
| --- | --- | --- | --- |
| Highland clans | Hills, passes, frontier | Clan Council | Expansion, expeditions, castles |
| River folk | Rivers, coast, trade | Merchant League | Roads, ports, safe trade |
| Abbey settlers | Farmland, heartland | The Church | Abbeys, tithes, limits on war |

Each chartered village adds to its faction's power. Powerful factions make demands; meeting them raises favour, ignoring them causes unrest.

## Art direction

Low-poly 3D models with vertex colours, rendered to a low-resolution SubViewport (about 640×360). The camera is orthographic, fixed at a 30–45° pitch, and rotates in 90° steps. The image is upscaled by an integer factor with nearest-neighbour filtering and snapped to the pixel grid to prevent shimmer. Post-processing adds 1 px outlines (from depth and normals), toon lighting in 2–3 bands, a fixed 32–48 colour palette applied through a lookup table (LUT), and dithering only in shadows and fog. The UI draws on a separate crisp layer above the pixel shader.

## Tech

- Godot 4 with GDScript.
- The simulation is plain code that never touches nodes and is driven by data files. Content (buildings, goods, chains, tiers) lives in JSON under `data/`.
- Randomness is deterministic and seeded.
- Village and nation simulations meet at one contract: a *site package* goes into a run (terrain, deposits, imports, threat, culture) and a *charter result* comes out (role, export bundle, faction, or ruin).
- A headless test harness checks that every chain completes and that a scripted build reaches Tier 3.

## Milestone gates

| Week | Gate |
| --- | --- |
| 4 | One chain playable: grain → flour → bread end to end, with carriers, storage and one house upgrade |
| 7 | A hard, fun run: Tier 3 and charter in 60–90 minutes; harsh sites sometimes fail |
| 12 | Campaign loop works: 3 runs in a row, with goods flow, company orders, a raid, faction demands and a promotion |
| 14 | Playtest verdict |
