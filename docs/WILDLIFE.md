# Wildlife and hunting

**Status:** built on 15 Oct 2026 (`sim/wildlife.gd`, `view/village_wildlife.gd`, `tests/test_wildlife.gd`). This replaces the flat `game` pool in [SUPPLY_CHAINS.md](SUPPLY_CHAINS.md) §2 ("pool of 30 per forest region").

## The choice

The land around a village is a food source as well as a timber yard. Woodland holds wild boar. Open meadow beside woodland holds red deer. A hunter's lodge turns both into meat with one worker and no fields.

Every tree a woodcutter fells, and every road, field or building laid down, shrinks that habitat. A village can live off its woods by keeping them, or clear them for logs and farmland and feed itself some other way. Hunting too hard empties the land as well.

## Ranges and habitat

The village map is split into **ranges** of 10 × 10 tiles. Each range's habitat is read straight from the grid:

| Measure | What counts |
| --- | --- |
| Woodland | Mature trees in the range |
| Meadow | Grass with no tree, sapling, road or building on it and no tree beside it. The gaps inside a wood are not meadow. |
| Disturbance | Building and road tiles in the range |
| Cover | Woodland in the range plus its four neighbouring ranges |

Each range has a capacity for each species:

| Species | Capacity |
| --- | --- |
| Wild boar | 1 per 6 trees beyond the first 10 |
| Red deer | The lower of 1 per 20 meadow tiles and 1 per 12 trees of cover |

Both are capped at 4 per range. Any building or road in a range costs each species 1 animal of capacity. From 12 such tiles, the range is **settled** and holds no game.

The result:
- Boar live deep in woodland.
- Deer graze clearings and meadows near the woods.
- Open land far from cover holds nothing.
- The village's own clearing empties as it is built up.

## Herds

Herds start at capacity when the site is founded. Every 600 ticks (one minute), each range changes once, based on the previous numbers, so the order ranges are visited in doesn't matter:

| Situation | What happens |
| --- | --- |
| More animals than capacity | One leaves for a neighbouring range with room, or dies |
| At least a pair, below capacity | One is born |
| Fewer than a pair, with room | One arrives from a neighbouring range holding at least a pair. Each neighbour sends at most one. |

So hunted ranges recover while a breeding pair remains nearby. An area hunted down to lone animals stays empty, and felling a wood drives its boar out one per minute. No random numbers are drawn.

## Hunter's lodge

| Workers | Cycle | Yield | Reach | Tier | Cost | Buyers |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 120 ticks | 2 meat per animal | Ranges whose centre is within 14 tiles of the lodge | 1 | 4 logs | Aristocrats |

The hunter always goes after the range in reach holding the most animals, nearest first on a tie. In that range it takes whichever species is more numerous there, deer on a tie. Its status reads "hunting red deer", "hunting wild boar" or "no game nearby". Meat joins the staple food need, and the lodge sells it at the chain price set by the butcher.

One lodge in an unbroken wood takes about 5 animals per 10 minutes. The six or so ranges in its reach can breed up to about 6 in the same time, so one lodge can live off a wood indefinitely, while two lodges or a felled wood run it down.

## Presentation

`view/village_wildlife.gd` draws one Blender model per animal: `animal_deer` and `animal_boar`, from `tools/build_medieval_assets.py`. Each animal gets a home tile in its range, chosen by a seeded hash: deer on meadow, boar on grass under the trees. It idles slowly around that tile. Animals appear, vanish or move home as herds change and land is cleared. Presentation never touches the simulation RNG.

## Saves

The sim snapshot has a `wildlife` key holding each species' herd counts by range. A restored village continues identically.

## Tuning and open ideas

Constants are at the top of `sim/wildlife.gd`. With these numbers, seed 73's 100 × 100 site starts with 54 deer and 153 boar.

Ideas not built yet:
- A habitat overlay, or a herd count in the hunter's inspector. Boar are hard to see under the canopy.
- Foragers drawing wild berries from forest edges, in the same way.
- Gamekeepers or hunting rights as an aristocrat lever.
- Deer raiding crops.
