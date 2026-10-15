# Wildlife, wild food and fertile soil

**Status:** built on 15 Oct 2026: game (`sim/wildlife.gd`, `view/village_wildlife.gd`, `tests/test_wildlife.gd`), and wild berries, fertile soil and the food overlay (`sim/forage.gd`, `view/village_forage.gd`, `view/food_overlay.gd`, `tests/test_forage.gd`). This replaces the flat `game` pool in [SUPPLY_CHAINS.md](SUPPLY_CHAINS.md) §2 ("pool of 30 per forest region").

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

## Wild berries

`sim/forage.gd` handles wild berries. They grow on grass under the canopy: a tile with a tree beside it, free of roads and buildings.
- **At founding**, about 1 such tile in 12 holds a bush, chosen by a seeded hash. None grow in the settlement clearing.
- **Fruit:** each bush holds up to 3 fruit and ripens 1 more every 300 ticks.
- **Losing bushes:** a bush withers once no tree stands beside it, or when a road or building covers it. Felling a wood loses its berries along with its game.
- **Numbers:** seed 73's default site has 386 bushes.

| Building | Workers | Cycle | Yield | Reach | Tier | Cost |
| --- | --- | --- | --- | --- | --- | --- |
| Forager's hut | 1 | 40 ticks | 1 berries from the nearest ripe bush | 8 tiles | 1 | 3 logs |

The forager's status reads "gathering wild berries" or "no ripe berries nearby". The planted **Berry bushes** building remains the farmed alternative.

## Fertile soil

Wheat fields carry `"deposit": "fertile_soil"` and `"off_deposit_percent": 50`. Their speed follows the share of their footprint on fertile soil: 100% when all of it is fertile, 50% when none is, and in proportion between. `village_sim.deposit_speed()` gives the speed, and `cycle_ticks()` stretches the cycle to match.

Where fertile soil lies:
- **Generated sites** (`site_gen._fertility`): loamy patches of grass from smooth noise, richer within 3–8 tiles of water. The bar depends on the biome: heartland and riverland have the most, coast and hills less, marsh least, and tundra and mountain passes none.
- **The default site:** its tilled clearing plus noise patches in the meadows.
- **Felled woodland** is not fertile.

## Food overlay

Press **F7**, or use the toggle in Options, to show `view/food_overlay.gd`. A key appears bottom left.

| Mark | Meaning |
| --- | --- |
| Gold tiles | Fertile soil, where fields work at full speed |
| Red marks | Wild berry bushes; larger marks hold more ripe fruit |
| Blue tiles | The fishing shore: water a fisher's hut can stand beside |
| Labels | The deer and boar living in each range, e.g. "1 deer · 2 boar" |

While you place a field, a label over the ghost gives its soil and speed, for example "Part fertile · 83% speed".

## Food balance

The **Food** button sits on the top row, left of the map button. It shows whether the village makes enough food. `sim/food_report.gd` measures the last two minutes of play (food made and eaten) against what the houses need now:
- **Settler houses** each need 6 basic food a minute: berries, fish or meat.
- **Villager houses** each need 3 staple food a minute: bread, fish or meat.

Supply is matched to needs:
- Berries feed only Settlers, and bread only Villagers.
- Fish and meat go to whichever need is still short, counted once.
- Producers idle only because the storehouse already holds enough count as spare supply, so a well-stocked village does not read as short.

| Button | Meaning |
| --- | --- |
| Green "Food +N/min" | Every need is met, with N to spare |
| Amber "Food −N/min" | A need is short by N, but stored food lasts at least 3 more minutes |
| Red "Food −N/min" | A need is short and stores are low: houses will go hungry |
| Grey "Food …" | Still measuring, for the first 30 seconds after a start or load |

Clicking the button opens a breakdown and turns on the food overlay:
- made, needed and eaten per minute, plus spare capacity;
- stored food, and how many minutes it lasts;
- each need, with its houses and supply;
- a table of made, eaten and stored for each food;
- every food producer, with how many are working and why the rest are idle.

The "Show on the map" switch in the breakdown mirrors F7.

The meter keeps its history in the HUD and is never saved. It starts measuring afresh after a restart or load.

## Presentation

`view/village_wildlife.gd` draws one Blender model per animal: `animal_deer` and `animal_boar`, from `tools/build_medieval_assets.py`. Each animal gets a home tile in its range, chosen by a seeded hash: deer on meadow, boar on grass under the trees. It idles slowly around that tile. Animals appear, vanish or move home as herds change and land is cleared. Presentation never touches the simulation RNG.

## Saves

The sim snapshot has a `wildlife` key holding each species' herd counts by range. A restored village continues identically.

## Tuning and open ideas

Constants are at the top of `sim/wildlife.gd`. With these numbers, seed 73's 100 × 100 site starts with 54 deer and 153 boar.

Ideas not built yet:
- A herd count in the hunter's inspector, besides the overlay.
- Wild bushes spreading slowly into new woodland that foresters plant.
- Gamekeepers or hunting rights as an aristocrat lever.
- Deer raiding crops.
