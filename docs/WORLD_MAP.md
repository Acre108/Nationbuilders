# Hearthlands: world map and site generation

> **Superseded (11 Oct 2026)** by [PLAN-world-map.md](PLAN-world-map.md). The zoom transition, continuous world function and cross-scale consistency rules below are dropped. The biome table (§4), village reach and spacing (§2.1) and deposit visibility (§5.6) still apply and are referenced from the new plan.

**Status:** design proposal. This extends [DESIGN.md](DESIGN.md) (nation map, site package) and uses the biomes and deposits from [SUPPLY_CHAINS.md](SUPPLY_CHAINS.md). It does not change milestone 1 behaviour: the current village becomes one hand-made site package, and the reference seed still reaches Tier 2 at tick 237.

The player sees a seeded hex world, picks a hex, and the camera zooms into it. The village map that appears contains the same cliffs, rivers, lakes, coast and forests that the hex showed on the world map, in the same places, with more detail.

---

## 1. The idea everything follows

**The world map and the village map are two samplings of one world.** Neither is generated from the other.

- All terrain is a pure function of `(world_seed, world_tile_position)`. A village site reads that function at 1-tile resolution. The world map reads it at 4-tile resolution and draws its vector features (rivers, cliffs, coast) from the same data.
- Site generation may only add **detail smaller than the map can show**. It can move a feature sideways by at most 2 tiles, which is half a map cell. It never adds or removes a feature the map draws.
- Nothing is site-local. No per-site RNG stream decides terrain. Two sites that overlap (for example, generated for neighbouring hexes in a test) produce identical tiles where they overlap. This is the test that proves the "one world" property (§7).

Zooming in therefore only reveals extra detail. The rest of this document applies these three rules.

---

## 2. Scale and coordinates

| Quantity | Value | Notes |
| --- | --- | --- |
| Tile | 1 world unit | Unchanged; a house is 2×2 |
| Hex | Pointy-top, 20 tiles flat-to-flat, 23.1 point-to-point | Axial `(q, r)`. Centre `x = 20q + 10r`, `y = 17.32r`. About 346 tiles of land per hex |
| Village reach | Own hex + its 6 neighbours (hex distance ≤ 1) | About 2,400 tiles, 1.5× today's 1,600-tile map. A run starts in its own hex and spills outwards |
| Village spacing | Founding hexes at least 4 apart (`min_village_distance`) | Reaches never touch: at least one full hex (20 tiles) of wilderness between them |
| World | 24 × 20 hexes = 480 | ~490 × 352 tiles, plus a 32-tile frame of ocean or peaks. Room for roughly 12–20 villages after ocean, peaks and spacing |
| Map lattice | 1 sample per 4 tiles | ~138 × 104 ≈ 14k cells; all world-scale hydrology runs on this |
| Site (simulated) | 60 × 60 tiles | Covers the whole reach. Origin is the hex centre minus (30, 30), rounded to whole tiles. Grid size comes from the site package; it is no longer a constant |
| Context ring (view only) | 96 × 96 around the site | Rendered from the same function, not simulated, fades into haze |
| Cliff level height | 1.0 unit | A cliff is about the height of a house wall |

### 2.1 Reach and dead space

A village owns its founding hex and may **spill into the six neighbouring hexes, but no further**. The 60×60 site covers that whole cluster. Tiles in the site's corners, outside the cluster, are real terrain that is drawn but cannot be built on:

```
   ┌──────────────── 60 ────────────────┐
   │ ▒▒▒▒▒▒  /\ ▒▒▒▒▒▒▒▒▒▒ /\  ▒▒▒▒▒▒▒ │   own hex     founding hex; the founding
   │ ▒▒▒▒  /    \ ▒▒▒▒▒▒ /    \  ▒▒▒▒▒ │               spot is always in here
   │ ▒▒  /  NW    \ ▒▒ /  NE    \  ▒▒▒ │
   │   |          |  |          |      │   NW … SE     spill hexes: buildable, part
   │  / \        / \/ \        / \     │               of the village once founded
   │ /    \    /        \    /    \    │
   │|  W   |  |  own hex |  |  E   |   │   ▒           outside the reach: visible,
   │ \    /    \        /    \    /    │               not buildable ("Beyond the
   │  \ /        \ /\ /        \ /     │               village lands")
   │   |          |  |          |      │
   │ ▒▒  \  SW    / ▒▒ \  SE    /  ▒▒▒ │
   │ ▒▒▒▒  \    / ▒▒▒▒▒▒ \    /  ▒▒▒▒▒ │
   │ ▒▒▒▒▒▒  \/ ▒▒▒▒▒▒▒▒▒▒ \/  ▒▒▒▒▒▒▒ │
   └────────────────────────────────────┘
```

- **Dead space is a world rule, not a village rule.** A hex can be chosen for a new village only if it is at least `min_village_distance` (4) from every existing village or ruin. With a reach of 1, two reaches are then at least 2 hexes apart, leaving one whole hex between them that no village can ever build on. Spill hexes are never shared, so the sim needs no claim or conflict rules.
- `min_village_distance` lives in `data/world.json`. 3 would let reaches touch with no gap. 5 leaves two hexes of wilderness but roughly halves the number of possible villages.
- The founding hex is "home": the founding spot and the playability check (§6.5) only consider it. Spill hexes are room to grow, and they hold most of the deposits that pull a village outwards.
- On the world map, a settled village marks its founding hex and outlines its whole reach. The dead space around it is drawn as untouched wilderness.

Every tile belongs to exactly one hex: the hex containing the tile's centre. Deposits, ownership and settlement are tracked per hex. Terrain is continuous and ignores hex borders.

---

## 3. World generation

`WorldGen.generate(seed, params) -> WorldMap`. Headless and deterministic. It runs once per campaign, and the campaign saves only the seed and generator version. Target time: under 1 second in GDScript.

### 3.1 Noise

The sim uses **integer-hash value noise** (`sim/world/int_noise.gd`) with no `FastNoiseLite`. Two reasons:
1. The project has already moved between engine versions (4.3 → 4.7.2). If an engine update changed `FastNoiseLite` output, every saved campaign's terrain would silently change.
2. The sim rule is "no nodes, no global random". Hash noise keeps world generation as plain, reproducible integer and float maths that can be tested headless.

Each noise field is `hash(world_seed, channel, x, y)` with smooth interpolation and octaves. Because it never uses a sequential RNG stream, generation order cannot affect results.

### 3.2 Pipeline (on the 4-tile lattice)

1. **Elevation.** Continent mask (radial falloff plus low-frequency noise) × fractal noise, plus ridged noise for mountain chains. The frame ring is forced to ocean or peaks, so the world ends in a skyline.
2. **Sea level.** Chosen so 25–35% of the world is ocean (measured, not assumed, the same approach `LandformTerrainProvider` uses for hill cover).
3. **Depression filling.** `LakeBasins.fill_depressions()` (already imported, a pure static function on `PackedFloat32Array`). `LakeBasins.extract_basins()` keeps real lakes and drops noise pits.
4. **Flow.** D8 flow directions on the filled surface, then flow accumulation.
5. **Rivers.** Cells with accumulation above `river_threshold` form river paths that run downstream to a lake or the ocean. Each path becomes a polyline in **world tile coordinates**, is smoothed twice with Chaikin, and gets a width per vertex from accumulation: stream 1, river 2–3, great river 4 tiles.
6. **Climate.** Temperature comes from latitude (north is cold), minus an elevation lapse, plus noise. Moisture comes from noise plus a distance-to-water term, minus a simple rain shadow (march along the prevailing west wind and reduce moisture behind high ground).
7. **Cliffiness.** A field from 0 to 1 that decides whether a height step becomes a cliff or a gentle ramp. It is high in hills, mountains and on high coasts, and low in heartland and marsh (from biome data plus noise).
8. **Forest density.** From climate and biome. The map draws it, and sites threshold it.
9. **Hexes.** Per hex: biome (§4), wildness 0–5 (distance from the start region plus noise), signature deposit rolls (seeded by `hash(seed, q, r)`), feature flags (river, lake, coast, cliffs) and `settleable`.

### 3.3 Settleability

World generation runs a cheap playability check on every hex (§6.5). A hex that fails is marked *too rugged* on the map and cannot be chosen. **Sites are never regenerated with different terrain to make them pass.** That would break the promise that the map is accurate.

---

## 4. Biomes

There are two biome concepts, and keeping them separate avoids hard edges at hex borders:

- **Terrain biome:** continuous weights per lattice cell, interpolated per tile. It drives forest, rock and marsh mix, grass palette and tree species. A forest edge falls where the map shows it, not along a hex border.
- **Rules biome:** one per hex. It decides the deposit pool, harsh-site rules, culture affinity and difficulty label.

The rules biome per hex comes from hex-wide statistics, first matching row wins:

| Order | Biome | Rule | Settleable |
| --- | --- | --- | --- |
| 1 | Ocean | > 60% of hex below sea level | No |
| 2 | Peaks | Mean elevation above the peak band | No |
| 3 | Mountain pass | Mean elevation in the mountain band | Yes (harsh) |
| 4 | Tundra | Mean temperature below `t_cold` | Yes (harsh) |
| 5 | Marsh | Moisture above `m_wet`, low relief, low elevation | Yes (harsh) |
| 6 | Highland hills | Mean elevation in the hill band, or relief above 3 levels | Yes |
| 7 | Coast | Touches ocean | Yes |
| 8 | Riverland | Contains a river ≥ 2 wide, or a lake | Yes |
| 9 | Heartland | Everything else | Yes |

Signature pools, rare pools and core shortfalls are the SUPPLY_CHAINS.md table moved into `data/biomes.json`. Tundra and Coast keep an `ocean_edge` flag for `sea_salt_flats`.

---

## 5. Features and how each one survives the zoom

### 5.1 Height, levels, cliffs and ramps

Gameplay height is an **integer level per tile**. The village stays a tile builder: buildings need flat footprints, and carriers walk a grid. Smooth height is visual only.

```
e     = world.elevation(p + warp(p))         # Catmull-Rom over the lattice
level = floor((e - sea_level) / LEVEL_HEIGHT)
```

`warp` is bounded domain-warp noise with |warp| ≤ 2 tiles. Using a domain warp, rather than adding height noise, is what keeps contours in place: added height noise moves a contour by `amplitude / slope`, which is unbounded on flat ground. A warp moves it by at most 2 tiles anywhere.

Wherever two 4-neighbour tiles have different levels:
- **Cliff** if `cliffiness` at the edge midpoint is above 0.5. The edge is impassable and is rendered as a rock wall with strata bands. A site keeps the same cliff line the map draws with hatching.
- **Ramp** otherwise. The upper tile becomes a ramp tile: roads may cross it, buildings may not, and it is rendered as a slope.

Hills on the world map become plateaus, cliffs and ramps in the village, so a hill is a real spatial puzzle. Heartland has little relief and mostly ramps, so it reads as gentle ground. Cosmetic rolling height of up to 0.3 units is added in the view only and never changes a level.

### 5.2 Rivers

Rivers are stored as world-space polylines (§3.2), so every site that touches a river reads the same curve.

- **Rasterising:** tiles whose centre is within `width / 2` of the curve become water. A per-river meander offset of up to 1.5 tiles, parameterised by arc length and seeded by river id, adds bends below the map's resolution. It is computed in world coordinates, so neighbouring sites agree.
- **Height:** a river's level comes from the filled elevation along its arc length, so it only ever descends. Where it drops a level there is a **waterfall** tile (impassable). Where its banks stand more than one level above it, the banks become cliffs: a **gorge**.
- **Crossing:** streams (width 1) can carry a road as a ford. Rivers of 2 or more tiles split the site until bridges exist (open question 3). Site generation puts the founding spot on the bank with more buildable land.

The view can render river surfaces with the imported `WaterLayer` ribbon approach. Whether it plugs in directly is checked in phase 5.

### 5.3 Lakes and coast

- **Lakes:** water wherever the lake's fill level is above the warped elevation, using the same contour rule as levels.
- **Ocean:** warped elevation below sea level. Coast tiles within 1 tile of ocean become `sand`, unless cliffiness turns that shoreline into a **sea cliff**.

### 5.4 Forest, rock and marsh

These are soft features. The map shows *where* they are but not their exact outline.
- **Forest:** `forest_density(p + warp) + 0.15 × fine_noise(p) > 0.5`. Large clearings the map shows still exist, and edges get local breakup.
- **Rock:** outcrops at cliff bases and where cliffiness is high. This matches the existing `stone_outcrop` rule (grass/hill).
- **Marsh:** the marsh weight is above a threshold, the tile is at the lowest local level, and water is within 4 tiles.

### 5.5 Deposits

- **Core deposits** come from per-tile rules: `timber` on forest, `fertile_soil` as noise patches on flat grass in a moisture band, `shallows` on water edges.
- **Signature and rare deposits** are rolled per hex at world generation. Site generation places each one on valid tiles inside its owning hex (clay on river and shore banks, `iron_vein` on raised levels next to cliffs, `peat_bog` in marsh), choosing tiles with `hash(seed, q, r, deposit)`. Placement is per hex and in world coordinates, so any site that covers the hex shows the same deposit.

### 5.6 Map-visible and scouted deposits

Each deposit has a `visibility` in data. The rule of thumb: vegetation and landforms you could see from the next hill are on the map. Anything underground, underwater, or in how animals behave has to be scouted.

| Visibility | Deposits |
| --- | --- |
| **Map** (always shown) | `fertile_soil`, `timber`, `pasture`, `sunny_slope`, `flower_heath`, `dye_meadow`, `oak_grove`, `peat_bog`, `sea_salt_flats` |
| **Scouted** (hidden until scouted) | `clay_bank`, `iron_vein`, `fish_shoals`, `salt`, `coal_seam`, `silver_lode`, `trapline`, `amber_shore` |

Consequences:
- Every mountain and tundra rare deposit is hidden. Founding a harsh site without scouting is a gamble, which gives the Scout order (DESIGN.md) real value. Marsh's lifeline, `peat_bog`, is visible.
- An unscouted hex shows its map-visible deposits and an **Unscouted** badge. It gives no hint about hidden deposits, not even a count.
- **Scouted** means any of: the hex is within 2 of a settled village or ruin (its reach plus the dead-space ring around it), the hex is in the starting region, or a Scout order covered it once the nation layer exists. A debug key reveals every hex.
- Founding a village reveals every deposit in its reach, scouted or not. The site always contains them; scouting only changes what the map showed beforehand.
- Hex info stores `scouted: bool`. The hover panel lists deposits by reach hex, so the player can see what a spill hex would add.

### 5.7 Feature tolerance

| Feature | Where the site may put it relative to the map |
| --- | --- |
| River, stream, coast line | Within 2 tiles of the map line |
| Cliff line | Within 2 tiles, along at least 90% of its length |
| Level or plateau outline | Within 2 tiles (warp bound) |
| Lake outline | Within one lattice cell (4 tiles) |
| Forest outline | Soft; large shapes match, edges may differ by up to 4 tiles |

---

## 6. Site generation

`SiteGen.generate(world, hex) -> SitePackage`. A pure function, cheap enough (~9k tiles including the context ring) to run on `WorkerThreadPool` while the camera zooms.

### 6.1 Tile terrain

| Terrain | Source | Buildable | Road |
| --- | --- | --- | --- |
| `grass` | Default land | Yes | Yes |
| `forest` | §5.4 | Woodcutter only (as now) | Yes |
| `rock` | §5.4 | No | No |
| `marsh` | §5.4 | Data-driven (peat cutter, saltern) | Yes |
| `sand` | Shoreline | Data-driven (fishing, salt pan) | Yes |
| `stream` | River width 1 | No | Yes (ford) |
| `river`, `lake`, `ocean` | §5.2–5.3 | No | No |

Ramp, cliff and waterfall are tile and edge attributes, not terrain types, so a ramp can still be forest. The legacy `water` id stays as an alias so the current content and tests still load.

### 6.2 SitePackage (the DESIGN.md contract)

```
SitePackage
  hex: Vector2i, origin: Vector2i         # world tile of local (0,0)
  terrain: Array[String]                  # row-major like Grid
  width, height: int                      # 60 × 60 for generated sites, 40 × 40 legacy
  levels: PackedInt32Array
  ramps: PackedByteArray                  # cliffs are not stored: see below
  deposits: Array[String]
  reach: PackedByteArray                  # 1 = inside the village's reach (§2.1)
  founding_spot: Vector2i                 # storehouse cell of the starter layout
  biome: String, wildness: int, culture_affinity: Dictionary
  imports: Dictionary, threat: int        # filled by the nation layer later
  sim_seed: int                           # hash(world_seed, q, r); seeds the Park–Miller RNG
  generator_version: int
```

Cliffs are derived, not stored: two 4-neighbour tiles connect if their levels are equal, or differ by one and the upper tile is a ramp. Every other level change is a cliff. That keeps the package to per-tile arrays and makes a cliff/ramp mismatch impossible.

`SitePackage.first_bread()` builds the current milestone 1 map by running the code currently in `Grid._init` unchanged, including its 1,600 RNG draws. This keeps every existing check and the tick-237 / tick-359 reference results identical.

### 6.3 Reach in the site

`reach` is 1 for every tile whose hex is the founding hex or one of its six neighbours. Buildings and roads need every tile inside the reach ("Beyond the village lands"). Spacing (§2.1) guarantees no other village's reach is in the site, so no claim rules are needed.

### 6.4 Founding spot

The current `Scenario.starter()` uses fixed coordinates. Site generation instead chooses a founding spot: the cell in the largest connected flat grass region, closest to the site centre, with water within 8 tiles, scored by distance to fertile soil and timber. The starter layout becomes relative to that spot. The fixed version stays for the legacy package and its tests.

### 6.5 Playability check

This runs at world generation for every hex (it can use a cheaper sample) and again on the real site:
- At least 250 buildable tiles in one connected, road-reachable region inside the founding hex, plus at least 800 across the whole reach.
- That region contains the founding spot and reaches water.
- Harsh biomes: the rare deposit sits inside or next to that region.

A hex that fails is marked unsettleable on the map (§3.3).

---

## 7. The consistency contract (tests)

These tests turn "feels like zooming in" into something that can be checked headless. They go in `tests/test_world.gd` and run in the existing simulation runner.

1. **Seam identity.** For every pair of adjacent settleable hexes in 3 seeds, terrain, level, ramp, cliff and deposit are identical in every overlapping tile. This is the strongest single check.
2. **Order independence.** Generating site A then B gives the same results as B then A, and the same as generating either on a freshly built world.
3. **Downsample agreement.** Box-filtering a site's land/water and level fields down to the lattice matches the world map's cells in at least 95% of cells, with mismatches only on boundary cells.
4. **Rivers.** Every world river that crosses the site rect appears as one connected water channel. It enters and leaves within 2 tiles of where the polyline crosses the site boundary, and its level never increases downstream.
5. **Cliffs.** Every map cliff segment inside the site has site cliff edges within 2 tiles along at least 90% of its length, and the site has no cliff longer than 3 tiles that the map does not show.
6. **Playability.** Every hex marked settleable passes §6.5, and `Scenario.starter()` succeeds at its founding spot.
7. **Determinism.** Same seed gives an identical world hash and site package hash across runs and across the headless and GPU runners.
8. **Legacy.** `first_bread()` matches the current terrain exactly, and all 76 existing checks pass unchanged.

A debug tool, `tools/dump_world.gd`, writes `artifacts/world-<seed>.png` (the lattice coloured by biome, with rivers and cliffs) and `artifacts/site-<seed>-<q>-<r>.png`, drawn to the same scale and overlaid. Reviewers can then check the zoom by eye before any 3D view exists.

---

## 8. Simulation changes

Small and contained. The sim rules in the README still hold.

- `Grid._init(site)` takes a `SitePackage` instead of an RNG. `VillageSim._init(seed, content, site = null)` uses `first_bread()` when `site` is null, so every existing caller and test is unaffected.
- `Grid.passable(a, b)`: same level, or one of the two is a ramp and the levels differ by 1, and no cliff edge between them. `astar` uses it instead of only checking for roads.
- `placement_error`: every footprint cell is inside the reach and on the same level, and none is a ramp. New messages: "Beyond the village lands", "Ground is not level", "Cannot build on a slope", "Cliff in the way".
- `place_road`: consecutive cells must be passable, so the L-shaped road tool rejects an L that crosses a cliff, atomically, as now.
- `Grid` takes its size from the package (`width`, `height`), replacing the `SIZE` constant. The view reads the size from the grid.
- `snapshot()` adds `width`, `height`, `levels`, `ramps` and `reach`.
- `content_db.gd` validates building `terrain` lists against the terrain ids in §6.1 and validates `data/biomes.json`.

New sim files: `sim/world/hex_math.gd`, `int_noise.gd`, `world_gen.gd`, `world_map.gd`, `site_gen.gd`, `site_package.gd`. All are `RefCounted` with explicit preloads, following the existing convention.

---

## 9. View

### 9.1 World map screen

A new main scene, `view/world_map_view.tscn`. `village_view.tscn` still runs directly (F6, `--render-smoke`) with the legacy package.

- **Relief mesh** from the lattice, one vertex per lattice point, vertex-coloured by terrain-biome weights with the same palette families as the village. It uses the same 640×360 SubViewport, the same `camera_rig.gd` pitch and 90° rotation, and the same lighting and atmosphere at a fixed hour.
- **Vertical exaggeration** of 3× on the map, as a shader uniform, so mountains read from far away. It eases to 1× during the zoom.
- **Vector features** are drawn from world data, not the mesh: river ribbons, cliff hatching (marching squares on the level field where cliffiness is above 0.5), coastline and lake shores.
- **Forests** are instanced clusters of small `NatureMeshBuilder` trees, scattered by density.
- **Hex overlay** comes from a hex-distance function in the ground shader. It is faint by default and stronger on hover.
- **Settlements:** each chartered village, ruin and current run is a generic marker on its founding hex (a small cluster of roofs sized by tier), with its reach outlined. Real building layouts are not drawn on the map.
- **Layout preview (debug, toggle):** draws each village's actual buildings and roads from its saved snapshot as flat blocks in their true positions. It exists so we can judge, in practice, whether real layouts belong on the map. If they do, it becomes the default; if not, it stays a debug view.
- **Hover panel:** biome, features (river, cliffs, coast, lake), wildness, known deposits by reach hex (§5.6), an Unscouted badge when it applies, culture affinity and difficulty (normal / harsh / too rugged / too close to <village>). Hovering a hex previews its whole reach outline. Clicking opens **Found village here?**, and confirming starts the zoom.

### 9.2 The zoom transition

The world map and the village share one 3D coordinate space. The village root is placed at the site's world origin, so the camera really moves and the scene never cuts.

1. **On hover dwell (300 ms)** start `SiteGen` and context-ring sampling on a worker thread. On a typical hex this is done before the player clicks.
2. **Zoom** over about 1.2 s. The camera centres on the hex and the orthographic size eases from the map view (~180) to the village view (~28), interpolated in **log space** so the zoom rate feels constant. Exaggeration eases from 3× to 1× at the same time.
3. **Hand-over** when one lattice cell reaches about 16 screen pixels. The site mesh, context ring and village foliage fade in with an ordered-dither threshold rather than alpha blending: there is no transparency sorting, and it suits the pixel-art pipeline. The world mesh fades out over the same area. The map is a low-pass of the site, so only detail appears and nothing moves.
4. **Backdrop.** Beyond the 96×96 context ring the world mesh stays visible at map resolution, so the village horizon is the map's real neighbouring terrain.
5. **Return.** At charter or failure, the reverse zoom plays, and the hex updates to its new village or ruin.

### 9.3 Village rendering changes

- `mesh_factory.terrain()` uses levels for heights. It builds rock wall quads with strata bands on cliff edges, slopes on ramps, and sunken water with banks for rivers. Waterfall tiles get a foam card.
- `village_foliage.gd` reads tree species weights and grass palette from the terrain biome, for example spruce-heavy and pale in tundra, reeds in marsh, oak in riverland.
- `village_atmosphere.gd` takes default weather weights from the rules biome.
- `view/site_context.gd` renders the context ring as terrain plus impostor trees from the same sampling function. It is not interactive and does not cast shadows.

---

## 10. Data files

- `data/world.json`: hex and world dimensions, lattice spacing, sea-level target, level height, warp bound, river thresholds and widths, climate thresholds, generator version.
- `data/biomes.json`: per biome display colour, settleable, harsh, cliffiness, forest, rock and marsh weights, signature, rare and core-shortfall pools (from SUPPLY_CHAINS.md), tree species weights, grass palette and weather weights.

All tuning lives in these files, following the existing data-driven rule.

---

## 11. Phases

| Phase | Scope | Done when |
| --- | --- | --- |
| 1 ✅ | `SitePackage` seam, `first_bread()`, grid size from the package, reach, levels, ramps, cliffs and rivers in sim and view, using a hand-authored 60×60 test package | All legacy checks unchanged. New sim tests cover cliffs, ramps, reach and fords. Screenshot shows a cliff, ramp, waterfall and river |
| 2 | Headless world generation and `dump_world.gd` | World PNGs for 3 seeds look like believable continents. Determinism test passes |
| 3 | Site generation from the world | Contract tests 1–7 pass on 3 seeds. Paired world and site PNGs reviewed |
| 4 | World map screen, hover panel, hex selection | Clicking a settleable hex starts a run on that site |
| 5 | Zoom transition, context ring, world backdrop | Recorded zoom shows no feature popping or jumps. View tests cover the hand-over |
| 6 | Biome presentation: foliage, palettes, weather per biome | One screenshot per settleable biome in `docs/VALIDATION.md` |

**Phase 1 is done** (11 Oct 2026): `sim/world/` (hex maths, site package, the hand-made First Bread and Terraces sites), relief rules in `Grid` and `VillageSim`, `view/terrain_relief.gd` for cliffs, ramps, banks and waterfalls, relief-aware picking, and `tests/test_site.gd`. Known polish: ramps that follow a stepped boundary show small sawtooth seams at their ends.

Phases 2–3 need no rendering work and can be fully verified headless. They are also what the week 7 gate needs ("harsh sites sometimes fail"). Phases 4–5 serve the week 12 gate ("choose the next site").

---

## 12. Decisions and open questions

**Decided here (change if you disagree):**
- Hills become integer levels with cliffs and ramps, not smooth slopes. This keeps the grid sim, flat footprints and carrier A* simple, and makes terrain a placement puzzle (pillar 4).
- Hash noise in the sim, not `FastNoiseLite`, so saved campaigns survive engine upgrades.
- Pointy-top 20-tile hexes. A village owns its hex and spills into the six neighbours, no further. Founding hexes are at least 4 apart, so there is always a full hex of wilderness between two villages.
- This changes two DESIGN.md numbers: the nation map has 480 smaller hexes instead of 150–250, and a village reach is about 2,400 tiles (60×60 site) instead of a 40×40 cut. Land per village and per world stays about the same.
- Deposits are split into map-visible and scouted (§5.6). The map shows village markers, not real layouts, with a debug layout preview to decide later.
- The map never lies: unplayable hexes are flagged, not regenerated.

**Open:**
1. **Rumours.** Should an unscouted hex hint at hidden deposits (for example "travellers speak of ore in these hills"), or stay completely silent as proposed?
2. **Spill timing.** Is the whole reach buildable from the start, or does each spill hex open with a milestone (a tier, a road reaching it, a cost)? Proposed: all buildable from the start in v1, then judged in playtests.
3. **Bridges.** A river 2 or more tiles wide splits a site. A bridge building (a road tile on river terrain, costing logs) is the obvious follow-up. Until then, site generation favours the larger bank.
4. **World size.** Fixed at 480 hexes, or chosen per campaign (small 300 / normal 480 / large 700)? The generator supports any size. Only UI and balance change.
