# Plan: the world map (level select and village organisation)

> **Goal:** a hex world map that is the game's home screen. You start a campaign on it, choose where each village goes, return to it between runs, and see every village you have founded, chartered or lost.

**Status:** phases A through E implemented for the current prototype, 11 October 2026, with a follow-up art pass. The latest implementation and review captures are in [Hex villages and campaign runs](HEX_VILLAGES.md). This supersedes the seamless-zoom design in [WORLD_MAP.md](WORLD_MAP.md). Sites preserve their world tile's major terrain layout and river placement; identical meshes and seamless zoom remain out of scope.

### Hex-shaped village sites: implemented

Agreed on 11 October: change the village map to a **hex-shaped visible and playable footprint**, and generate it from the selected world-map tile's terrain. This work is now implemented: a regular hex boundary clips the rectangular backing grid, with terrain generated from the founding tile and its six neighbours. The notes below record the agreed requirements.

- Carry the selected tile's biome, major relief, woodland/clearings, coastline and lakes into the village site, preserving their overall arrangement and orientation. Replace the generic starter terrain with a site that visibly belongs to the chosen tile.
- Match **river placement**, including entry/exit edges, positions along those edges, width, connections, confluences and lake/coast destinations. Fine-scale meanders may add detail while retaining the map's watercourse layout.
- Define a shared terrain/layout contract so the world-map presentation and village generator agree on the large features; presentation-only art settings must not become authoritative simulation state.
- Apply the hex boundary to terrain rendering, building placement, roads and pathfinding. Outside-footprint cells must not remain playable merely because internal storage is rectangular. Changing individual building/path cells to hexes is a separate decision.
- Reconcile the footprint and scale with the existing founding-hex-plus-six-neighbours reach. The square dimensions in §5.1 are an earlier proposal; they do not override the new hex-shaped boundary requirement.
- Keep generation deterministic and preserve a workable founding clearing. Review paired world-tile/village captures and check river alignment, boundary enforcement, playability, and save/load consistency.

---

## 1. What the world map is

- **Level select.** Every settleable hex is a possible village site. Hovering shows what the site offers. Clicking founds a village there, which starts a run on a site generated from that hex.
- **Organisation layer.** Every village is a *village hex* with a status marker: active, chartered or ruin. A village list lets you find, resume and review villages. The map is where the campaign's state lives between runs.
- **Home for the nation layer later.** Nation turns, companies, factions and goods flow (DESIGN.md) will act on the same hexes. This plan builds the data and screen they will need, but not those systems.

Not in scope:
- zooming seamlessly from the map into the village, or using identical terrain meshes between scales (the site's major terrain features and river placement must still match its world tile);
- drawing village buildings on the map; a village is one marker on its hex;
- nation turn mechanics (company orders, raids, faction demands, goods flow), except the scouting rule in §4.3.

---

## 2. Where we are

What already exists and is reused:
- **Site package seam.** `VillageSim.new(seed, content, site)` runs a village on any `SitePackage` (`sim/world/site_package.gd`): size, terrain, levels, ramps, deposits and a buildable reach. The default coastal village is now 100 × 100 tiles, with a central starter clearing, woodland groves and a road entering from the western boundary. The explicit 40 × 40 reference generator remains available.
- **Relief.** Cliffs, ramps, rivers, lakes and streams already work in the sim (placement, roads, carrier routing) and in the view (`view/terrain_relief.gd`). Generated sites can use them immediately.
- **Hex maths.** `sim/world/hex_math.gd`: pointy-top axial hexes, point-to-hex, distance, neighbours.
- **Terraces test site** (F4 / `--site=terraces`). It stays as a debug fixture for relief.

What is now implemented:
- **Hex site generation:** deterministic regular hex footprints, shared river/lake/coast/grove/relief layout, real-command starter validation and cached playability checks.
- **Persistence:** complete simulation/site restoration, versioned atomic campaign saves, corruption rejection and compatible v1 migration.
- **Campaign flow:** main menu, map selection and village history, founding, suspend/resume, two-minute autosave, saved camera/weather settings, charter/keep-building and confirmed abandonment.
- **Run results:** persistent charter/ruin/abandon records, scouting, spacing, three-run continuation and ruin resettlement with 12 extra logs. The zero-population ruin hook exists; natural population loss is not introduced by this plan because the prototype retains four founding adults.

---

## 3. Player flow

```
New campaign ─▶ World map ─▶ hover hex (info panel) ─▶ Found village here? ─▶ Village run
                   ▲                                                            │
                   │                ◀──── Return to world map (run suspended) ──┤
                   │                                                            │
                   └──── Run result (charter / ruin / abandon) updates the hex ◀┘
```

- **New campaign:** choose a seed (or a random one). The world is generated and the start region revealed.
- **Continue:** load the last campaign and open the world map.
- **World map:** pan, rotate and zoom with the village controls. Hover a hex to see its details. The village list docks on the left.
- **Found:** a confirmation card shows the site summary, the village name (auto-generated, editable) and, once cultures exist, a culture choice. Confirming generates the site and opens the village.
- **In the village:** a **World map** entry in the options (cog) menu suspends the run and returns to the map. The village hex shows *active*.
- **Resume:** click an active village hex, or its row in the village list.
- **Run end:** a result card (§7). The hex becomes chartered or a ruin, and nearby hexes are scouted.

**One active village at a time** (DESIGN.md: one village per session). You can view the map at any time, but founding a second village asks you to abandon or finish the active one first. Open question 1 covers relaxing this.

---

## 4. World model (`sim/world/`)

All world data is plain `RefCounted` sim code: deterministic, seeded and tested headless, following the existing sim rules.

### 4.1 Hexes

| Field | Meaning |
| --- | --- |
| `coord` | Axial `Vector2i(q, r)` |
| `biome` | One of the rules biomes (§4.2), or `ocean` / `peaks` |
| `elevation` | Integer band 0–4: lowland, rolling, hills, highland, peaks |
| `moisture`, `temperature` | 0–1, used for biome and site generation |
| `river_edges` | Set of edge indices (0–5) a river crosses, with a width per edge (1 stream, 2–3 river) |
| `coast_edges` | Edges that face an ocean hex |
| `lake` | Whether the hex holds a lake |
| `cliffs` | 0–1 ruggedness. Hills and coasts with high values get cliff lines in their sites |
| `forest` | 0–1 cover |
| `deposits` | Signature and rare deposits rolled for this hex, each with `visibility` (`map` / `scouted`) |
| `wildness` | 0–5 (DESIGN.md) |
| `scouted` | Whether hidden deposits are known |
| `settlement` | Village id or empty |

### 4.2 Generation (hex resolution only)

`WorldGen.generate(seed, params) -> WorldMap`, targeting under 200 ms. There is no fine lattice; everything is computed per hex.

1. **Elevation:** a continent mask times fractal value noise sampled at hex centres, plus a ridge term for mountain chains, quantised to bands. The map border is ocean or peaks.
2. **Sea:** hexes below the sea threshold, chosen so about 30% of the map is ocean, become `ocean`. `coast_edges` comes from neighbours.
3. **Rivers:** from a few highland sources, walk downhill hex to hex, choosing the lowest neighbour with fixed tie order, until reaching ocean or a lake. Each step marks the shared edge in both hexes. Rivers merge and widen downstream. A river that hits a pit forms a lake there.
4. **Climate:** temperature falls northward and with elevation. Moisture comes from noise plus distance to water, minus a rain shadow east of highland.
5. **Biome:** the first matching rule in the [WORLD_MAP.md §4](WORLD_MAP.md) table (ocean, peaks, mountain pass, tundra, marsh, highland hills, coast, riverland, heartland).
6. **Deposits:** roll each settleable hex's signature and rare deposits from its biome pool ([SUPPLY_CHAINS.md](SUPPLY_CHAINS.md)), seeded by `hash(seed, q, r)`.
7. **Wildness:** from distance to the start region, plus noise.
8. **Start region:** a heartland or riverland hex near the middle-south, with its radius-2 area scouted.

All noise is integer-hash based, so worlds survive engine upgrades. A campaign stores only the seed and generator version; the world is regenerated on load and campaign state is applied on top.

### 4.3 Rules carried over

- **Reach:** a village owns its hex and may build into the six neighbours, no further.
- **Dead space:** a hex can be founded only if it is at least `min_village_distance` (4) from every village and ruin. Reaches never touch, and at least one full hex of wilderness lies between two villages.
- **Settleable:** not ocean or peaks, not too close to another village, and the site passes its playability check (§5.3).
- **Deposit visibility:** map-visible deposits always show. Scouted ones show only when `scouted` is true ([WORLD_MAP.md §5.6](WORLD_MAP.md) table).
- **Scouting:** hexes within 2 of a village or ruin, the start region, and later Scout orders.

### 4.4 Campaign state

```
Campaign
  seed, generator_version, created, last_played
  hexes:    { coord → { scouted, settlement } }       # only fields that change
  villages: [ VillageRecord ]
  active_village: id or ""
  turn: int                                           # nation turns, 0 for now

VillageRecord
  id, name, hex, status: active | chartered | ruin | abandoned
  founded_turn, ended_turn
  best_tier, population, buildings (count)            # shown in list and panel
  result: RunResult or null                           # §7
  save: path to the village save while active
```

---

## 5. Site generation from a hex

`SiteGen.generate(world, hex) -> SitePackage`. Sites **honour what the hex promised** through the authoritative `terrain_layout.gd`, shared with the world-map renderer. River paths, edge mouths, water widths, linked lakes, groves and ridge fields are sampled at both scales; village relief is quantized into traversable levels and ramps.

### 5.1 Layout

**Implemented layout:** square command cells inside a regular hex-shaped physical footprint. Buildings, roads, routing, planting and terrain rendering all respect the mask.

The site is 60×60 tiles, covering the founding hex plus its six neighbours, each 20 tiles wide (as in phase 1). Each tile knows which of the seven hexes it is in. That hex's descriptor drives the tile, so the site is assembled from seven pieces of the map.

| Hex property | What appears in its part of the site |
| --- | --- |
| Biome, forest | Mix of grass, forest, rock and marsh from biome data, with forest density from `forest` |
| Elevation band | That piece's base level. A band difference between neighbours makes a level change at their shared border: cliffs if `cliffs` is high, ramps otherwise |
| River edges | A river enters at the midpoint of each marked edge, is traced through the hex centre, and leaves by its other marked edge, with smooth meanders. Width comes from the edge |
| Coast edges | The far side of a coastal piece becomes ocean, with a sand shore or sea cliffs |
| Lake | A lake basin around the hex centre |
| Deposits | Placed on valid tiles in their own hex (clay on banks, iron near cliffs, peat in marsh) |

The founding hex is always a buildable core: its level changes are always ramped, and it gets the founding spot. Generation is seeded by `hash(world_seed, q, r)`, so the same hex always gives the same site.

### 5.2 Consistency without a shared world function

Neighbouring villages are at least 4 hexes apart, so no two sites ever overlap. Two sites only need to agree with the map, not with each other. The tests check that promise directly (§8).

### 5.3 Playability

Every settleable hex must pass:
- at least 250 buildable tiles connected by possible roads inside the founding hex, plus at least 800 across the reach;
- a founding spot with water within 8 tiles when its founding tile promises river, lake or coastal water; dry sites retain the prototype well;
- harsh biomes: the rare deposit sits inside the reach.

Detailed playability is checked when a site is selected and before founding, then cached on the world. This keeps world generation fast instead of generating all 300 fine sites upfront. A failed site is labelled *too rugged* and cannot be founded. Meadow openings belong to the shared world layout before sampling; failed terrain is never flattened and rivers are never moved to fit the starter. The real starter commands also verify material and treasury budgets.

---

## 6. Persistence

Campaigns use `user://campaigns/<id>.campaign`, one atomic file containing campaign records, scouting, results, the active village's complete simulation and site, and map/village view settings. Object-free binary Variants preserve typed arrays and integer/vector keys; this replaces the proposed split JSON files.

- `VillageSim.from_snapshot(snapshot, content)` and building/carrier/storage inverse methods restore the complete run, including jobs, cargo, reservations, finances, forestry, RNG and masked site metadata.
- Save on founding, map/menu transitions, normal quit and every two minutes. A temporary write plus checksum envelope and rename protects the previous save; failed completion rolls back the run transition and keeps the scene open.
- **Save version 2:** compatible v1 saves migrate, retaining their original square sites. Wrong game data or generator versions are refused with a clear message. The world generator is now version 2 to reject old resource promises incompatible with actual water/coasts.
- Camera, selection, linked-art mode, time/weather/wind, rendering mode, pause/speed and deposit display are restored. Malformed saved view data is rejected before entering the scene.
- Tests cover deterministic continued simulation after restore, real cargo-return jobs and demolished delivery endpoints, full hex-site round trips, atomic failures, corruption and migration.

---

## 7. Run results (the DESIGN.md contract)

A run ends with a `RunResult`, which the map applies to the village hex:

```
RunResult
  outcome: charter | ruin | abandoned
  best_tier, final_population, duration_ticks
  role, faction, export_bundle        # charter only; filled in once those exist
```

Until charter and failure rules exist:
- **Charter:** shown once the village reaches its current highest tier. The result card offers "Charter village" (the hex becomes chartered and the run ends) or "Keep building".
- **Ruin:** the zero-population hook produces a resettleable ruin. Natural mortality is not yet simulated: the current four founding adults prevent normal runs from reaching zero. Explicit abandonment already provides the playable ruin/resettlement route.
- **Abandon:** from the options menu, with a confirmation. The record becomes abandoned and the map shows a ruin marker. Resettling grants 12 recorded extra starting logs; other settlements' spacing still applies.

The real rules (Tier 3, export depot, morale, raids) replace these triggers later without changing `RunResult` or the map.

---

## 8. World map screen (`view/world_map/`)

- **Rendering:** the same smooth full-resolution viewport, camera rig, lighting and atmosphere as the village, so the map matches its art.
  - Each hex is a low prism raised by its elevation band and coloured by biome.
  - Rivers are ribbons through hex centres and edge midpoints.
  - Ocean is a flat plane with local shores. Imported nature models form groves; broad ridge relief and restrained snow define peaks.
  - Fine dark surface borders keep hexes readable beneath the linked scenery.
- **Village hex markers:**
  - *active*: a few roofs with a red banner;
  - *chartered*: a larger cluster with a coloured banner, later the faction colour;
  - *ruin*: grey broken walls;
  - *abandoned*: the ruin marker, dimmer.
  - A village's reach is outlined.
- **Founding overlay** (while hovering in found mode):
  - the hovered hex's reach is outlined;
  - hexes that are too close, too rugged or unsettleable are hatched;
  - each blocked hex's reason shows in the panel.
- **Hex panel:** biome, features (river, coast, lake, cliffs), elevation, wildness, known deposits by reach hex, the **Unscouted** badge, difficulty (normal / harsh) and why founding is blocked, if it is.
- **Village list:** name, status, best tier, population and founded turn. Clicking centres the map on the village. Active villages have **Resume**.
- **Debug keys:** reveal all deposits; show settleability; regenerate with the next seed; print the hovered hex's descriptor.

The village view has a **World map** button, run-result cards, confirmed abandonment and **Site overview (Home)**. Its existing building, road, camera and weather controls remain available.

---

## 9. Work items (in order)

### Phase A: world data, headless ✅ (11 Oct 2026)
- [x] `sim/world/hex_info.gd`, `world_map.gd` and `world_gen.gd` (§4.1–4.2). `int_noise.gd` holds the portable hash noise. Generation takes about 22 ms for 300 hexes.
- [x] `data/deposits.json`: every deposit with its class and `visibility` (map / scouted). `sea_salt_flats` has `"requires": "ocean_edge"`.
- [x] `data/world.json` (20×15 = 300 hexes, sea fraction, elevation bands, river flows, climate thresholds, spacing, scouting radius) and `data/biomes.json` (colours, settleable, harsh, forest, cliffs, signature, rare and extra pools from SUPPLY_CHAINS.md).
  - These are validated by `sim/world/world_data.gd`, which works the same way as `content_db.gd` but is kept separate so village content loading is untouched.
- [x] `tools/dump_world.gd` writes `artifacts/world-<seed>.png`: `godot --headless --path . --script tools/dump_world.gd -- --seeds=1,2,3`.
- [x] Tests: `tests/test_world.gd`, 93 checks in the headless runner.
  - Data rejection; the same seed gives the same world and different seeds differ; the map is ringed by ocean with the configured sea share.
  - Rivers: mirrored edges, downhill on the drainage surface, every river reaches the sea.
  - Biome rules; a start region that is settleable, scouted and tame, with wildness growing away from it.
  - Deposits come from their pools, harsh hexes get a rare deposit, sea salt only on coasts.
  - Founding spacing (3 apart blocked, 4 allowed), reach and deposit visibility.

**Implementation notes:**
- Rivers use a priority flood on the hex graph, so every hex has one downhill route to the sea through basins, and lakes form where a river crosses a basin.
- Only low hexes connected to the map edge become ocean, so there are no one-hex inland seas.
- Elevation bands come from measured quantiles.

### Phase A2: render the world map ✅ (11 Oct 2026)
- [x] `view/world_map/world_map_view.tscn` with the village's camera rig, lighting and atmosphere, rendered **smooth at full resolution** (the optional pixel effect has since been removed). It runs on its own: `godot --path . view/world_map/world_map_view.tscn -- --seed=N`. The main menu now hosts this scene as the campaign map.
- [x] `view/world_map/world_map_mesh.gd` draws:
  - hex prisms raised by elevation band and coloured by biome, with darkened rims that read as the hex grid;
  - an ocean plane with lighter coastal shallows;
  - river ribbons with waterfalls where a river leaves higher ground or reaches the sea;
  - lakes, low-poly forests (conifers in the cold), snow-capped peaks, rocky passes and a start banner.
- [x] Hover ring and a hex panel: biome and difficulty, elevation, wildness, features, climate, known deposits, **Unscouted**, the start region, and whether the hex can be founded (with the reason if not). Hover follows mouse-motion events and re-picks as the camera moves. Picking marches the camera ray onto prism tops.
- [x] Debug keys: N / Shift+N for next / previous seed, V to reveal all deposits. `--screenshot` saves `artifacts/world-map.png` and quits.
- [x] View test: `godot --path . --script tests/run_world_map_tests.gd` (124 checks, with follow-up motion, linked-edge and interaction coverage).
  - Models for 3 seeds; every land hex has a prism; changing seed replaces the model.
  - Hover picks the start, a raised hex and a sea hex.
  - Panel contents, Unscouted and the reveal key, camera rotation, next seed.

### Phase B: site generation from a hex — complete
- [x] Shared `terrain_layout.gd` and `site_gen.gd`: regular hex footprint, seven owner districts, rivers/coasts/lakes, groves, terrain bands, ramps and deposits.
- [x] Physical mask enforced by rendering, placement, roads, routing and forestry; square command cells retained.
- [x] Cached site-selection/founding playability and real-command starter checks, including the existing treasury/material budget.
- [x] Paired `dump_world.gd` PNGs, including `--site=q,r` and `--lake` fixtures.
- [x] **294 generation checks:** 21 villages bake bread across three seeds; all three starts and actual lake sites are playable; boundary, relief, river mouths, water and deposit ownership match. The final zero-forest-cover change passed **6 targeted fixture checks**.

**Done:** paired layouts and GPU landscapes reviewed; detailed checks run lazily at site selection to preserve fast world generation.

### Phase C: persistence — complete
- [x] Complete `VillageSim`, `Building`, `Carrier` and `Storage` snapshot inverse methods.
- [x] `sim/campaign.gd`: atomic checksum-protected Variant saves, version 2, compatible v1 migration and schema validation (§6).
- [x] Full state, cargo/delivery interruption, finances, forestry, site geometry, view state and RNG restored.
- [x] **170 targeted campaign checks:** deterministic continuation, corrupted/malformed saves, migration, complete generated sites, maximum overview zoom, failed completion rollback and aggregate road-budget atomicity.

**Done:** a saved run restores and continues identically, including deliveries interrupted by demolition.

### Phase D: world map screen — complete
- [x] `view/main_menu.tscn` is the main scene, hosting New/Load campaign, the world map and the village.
- [x] Art-directed hex landscapes, water, latest village status markers, grid outlines and seven-hex reach.
- [x] Hover details, site validation, blocked founding hatches, village list, known reach deposits and named founding controls.
- [x] Suspend/save/resume, independent active-village resume, and per-view camera/weather/wind/pause/render settings.
- [x] **47 rendered campaign checks:** real mouse/keyboard flow, save failures, 960×640 layout, Site overview/Home framing and restoration, history and status actions. Existing village view checks also pass.

**Done:** players can create/load a campaign, choose a valid site, found, leave and resume their village.

### Phase E: run results and campaign loop — prototype complete
- [x] `RunResult`, temporary charter at the highest implemented tier, Keep building, confirmed abandonment, zero-population ruin hook, result cards and map updates.
- [x] Scouting, minimum spacing, latest status markers, persistent history and ruin resettlement with 12 extra logs.
- [x] Three distinct completed runs followed by resettlement tested headlessly; rendered flow also tests successive charter/abandon/resettle runs, save/load and rollback.

**Done for the prototype:** repeated village runs work without nation-turn mechanics. Natural population-loss ruins await a mortality system; Tier 3, faction/export charter rules and nation turns remain their separate later milestones.

### Follow-up art pass — complete
- [x] Shared world/village terrain fields, village palette and golden light, regional woodland species and quiet meadow patches.
- [x] Generated foliage root offsets break regular rows while retaining resource cells; regrowth/stumps share the same placement.
- [x] Clipped soil sides, full-site camera framing and a calm weather-aware overview backdrop with live cloud lighting and wind.
- [x] **33 generated-site GPU checks:** no exterior terrain/foliage leaks, art leaves simulation/RNG unchanged, and saved regional metadata survives restoration. Overview/close-up captures for three seeds are in [HEX_VILLAGES.md](HEX_VILLAGES.md).

---

## 10. What happens to the earlier work

| Item | Decision |
| --- | --- |
| `SitePackage`, `hex_math.gd`, reach, relief rules, `terrain_relief.gd` | **Keep.** Generated sites need them. |
| Terraces site, F4 switch | **Keep as debug fixtures** for relief, and remove F4 from the player-facing README once the world map ships |
| Continuous world function, 4-tile lattice, zoom transition, context ring, cross-scale consistency tests ([WORLD_MAP.md](WORLD_MAP.md) §1, §3, §5.7, §7, §9.2) | **Drop.** WORLD_MAP.md is marked as superseded by this plan |
| Biome table, deposit visibility, reach and spacing ([WORLD_MAP.md](WORLD_MAP.md) §2.1, §4, §5.6) | **Keep.** This plan refers to them |

---

## 11. Prototype decisions and remaining questions

1. **Active villages:** one at a time, matching DESIGN.md's "one village per session". Completed and abandoned runs remain in history.
2. **Culture at founding.** Is the culture chosen on the found card from the start, or added once cultures have gameplay? The card has room for it either way.
3. **World size:** 300 hexes (20×15), with later tuning based on campaign play.
4. **Rumours.** Should unscouted hexes hint at hidden deposits, or stay silent?
5. **Spill timing:** the whole physical site is available from the start, subject to terrain and building rules.
6. **Resettling ruins:** 12 extra starting logs, with the predecessor recorded in campaign history.
