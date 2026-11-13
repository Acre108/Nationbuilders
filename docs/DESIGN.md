# Hearthlands: design summary

Condensed from the full prototype proposal. This is the reference for anyone building the prototype.

## Pitch

Hearthlands is a light but challenging town builder. Each 60–90 minute session founds one village on a hard site. The village can fail; every village that succeeds permanently joins a growing nation. Inside each village, class factions compete for its money and influence, and the strongest at charter carries its weight into the nation. Each nation turn, patrols and expeditions turn wilderness into civilised land. Over many sessions the nation grows from the medieval age to the modern age.

## Pillars (use these to decide what to cut)

1. **Small, finishable, hard-won.** A village is 15–40 buildings on a compact map. Runs are challenging and can fail.
2. **Chains you can read at a glance.** No chain is longer than 4 links (wheat → flour → bread). Every building shows what it needs and what it is missing.
3. **Permanence with purpose.** Nothing is thrown away. A failed village leaves a ruin that can be resettled.
4. **Place matters.** Terrain, culture, neighbours and threats decide what a village is good at.
5. **Wild to civilised.** Every nation turn visibly turns wilderness into settled, connected land.

## Core loop

- **Village run (real time).** Found the village (pick the site and culture) → survive and grow (winters, raids, needs tiers) → build its specialty around the unique resource → charter it, or fail into a ruin.
- **Nation turn (one per run).** Goods flow along roads → factions make demands, weighted by their national power → threats resolve (raids against patrols and defences) → companies tame the wild (scout, patrol, expedition) → choose the next site.

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
- **Charter.** Available once the village reaches Tier 3 with an export depot running. The player picks a role (Producer, Garrison or Market). The charter records the village's dominant faction, and its faction power shares add to the nation's totals.
- **Failure.** A village fails when population reaches 0, it is overrun, or morale collapses for a full season. It becomes a ruin, which can be resettled later with a bonus.

## Nation layer

- **Map.** A seeded hex map of 150–250 hexes. Each hex has a terrain, deposit hints and a wildness level from 0 to 5 (0 = civilised).
- **Nodes.** Each chartered village is a node that produces an export bundle every nation turn.
- **Network.** Roads have a capacity per tier. Goods flow automatically to the nodes that need them; a simple flow solver handles this, with no unit pathing.
- **Promotion.** 3 or more linked villages that satisfy a needs basket can promote a hub to a town.
- **Military.** 3–6 companies. Each company gets one order per turn: Scout, Patrol, Expedition, Escort or Garrison. Odds are shown before committing, the order auto-resolves, and the result appears on an event card.
- **Threats.** Raids travel predictable routes. Each raid's strength is compared against defence coverage plus any patrol on the route; a lost raid sends the node into decline.

## Factions

Six factions in three classes compete inside every settlement. [FACTIONS.md](FACTIONS.md) has the full design.

| Class | Factions | They want |
| --- | --- | --- |
| Working class | **Trade unions** · **Populists** | Wages and jobs · cheap bread, order and tradition |
| Middle class | **Middle class** | Shops, a healthy markup, order |
| Elite | **Industrialists** · **Aristocrats** · **Cultural elite** | Workshops and cheap labour · land, rent and woodland · schools and a free press |

- **Power** is a faction's share of the settlement's silver: its coffers, its households' savings and the property it owns.
- **Favour** toward the player follows the levers, deals and pledges. Factions pay the treasury for property and pledges.
- **Villages** get the unions and populists with the first Villager house. The site decides which of the middle class, industrialists and aristocrats also take an interest, from none to three. Towns have all six. The cultural elite is a town faction.
- **Nation.** At charter, the dominant faction is recorded and the settlement's power shares add to the nation's totals. National power drives faction demands each nation turn.

*Changed 15 Oct 2026:* the culture factions (Clan Council, Merchant League, the Church) are replaced by these class factions. Cultures (Highland clans, River folk, Abbey settlers) may stay as regional flavour, but they no longer decide factions.

## Art direction

Stylised low-poly 3D, rendered smoothly at full display resolution with antialiasing. Buildings are Blender-authored medieval models that show their stock (sacks, barrels, sheaves). The environment is the SpacesOS foliage, lighting and atmosphere stack: natural sunlight with a golden late-afternoon default, day/night, weather, wind-driven trees and grass, and cloud shadows. The camera is orthographic, fixed at a 30–45° pitch, and rotates in 90° steps. The UI draws on a separate layer above the world and follows [UI.md](UI.md): one fact per line, explanations in tooltips, and anything the player can't act on under a Details fold.

*Changed 11 Oct 2026:* the original pixel-art pipeline (a 640×360 viewport with nearest-neighbour upscaling, 1 px outlines, banded toon lighting and a 32–48 colour palette LUT) is dropped. Smooth rendering is the long-term look. *Changed 14 Oct 2026:* the remaining optional pixel view and the disconnected pixel shaders have been removed. [ART_DIRECTION.md](ART_DIRECTION.md) sets the direction for new assets; [VILLAGE_ART.md](VILLAGE_ART.md) records the current look and its tuning.

## Tech

- Godot 4 with GDScript.
- The simulation is plain code that never touches nodes and is driven by data files. Content (buildings, goods, chains, tiers) lives in JSON under `data/`.
- Randomness is deterministic and seeded.
- Village and nation simulations meet at one contract: a *site package* goes into a run (terrain, deposits, imports, threat, culture) and a *charter result* comes out (role, export bundle, dominant faction and power shares, or ruin).
- A headless test harness checks that every chain completes and that a scripted build reaches Tier 3.

## Milestone gates

| Week | Gate |
| --- | --- |
| 4 | One chain playable: grain → flour → bread end to end, with carriers, storage and one house upgrade |
| 7 | A hard, fun run: Tier 3 and charter in 60–90 minutes; harsh sites sometimes fail |
| 12 | Campaign loop works: 3 runs in a row, with goods flow, company orders, a raid, faction demands and a promotion |
| 14 | Playtest verdict |
