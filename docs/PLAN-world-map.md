# Plan: the world map (level select and village organisation)

> **Goal:** a hex world map that is the game's home screen. You start a campaign on it, choose where each village goes, return to it between runs, and see every village you have founded, chartered or lost.

**Status:** plan, 11 Oct 2026. This replaces the zoom and seamless-terrain design in [WORLD_MAP.md](WORLD_MAP.md). The hexes, village reach, spacing, biomes and scouting rules carry over. The seamless zoom transition and identical terrain meshes between scales remain out of scope; village sites must reflect their world tile's terrain layout and river placement as recorded below.

### Next session: hex-shaped village sites (12 October 2026)

Agreed on 11 October: change the village map to a **hex-shaped visible and playable footprint**, and generate it from the selected world-map tile's terrain. Pick this up next session; this entry records the work, without starting implementation.

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

What is missing:
- **Any persistence.** Snapshots support comparison and replay, not restoring a run. A world map you return to needs a campaign save. Resuming an unfinished village needs a village save (§6).
- **Run endings.** There is no charter or failure yet (Tier 3 does not exist). The map needs a "run result" contract now, so the result can be filled in by real charter and failure rules later (§7).
- **Scene flow.** `village_view.tscn` is the main scene, and nothing sits above it.

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

`SiteGen.generate(world, hex) -> SitePackage`. Sites no longer have to match a world function exactly. They only have to **honour what the hex promised**.

### 5.1 Layout

**Next-session update:** use a hex-shaped site footprint and preserve the selected tile's major terrain layout and river placement. Resolve the dimensions and neighbour reach using the note above before implementing this section's earlier square-layout proposal.

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
- a founding spot with water within 8 tiles;
- harsh biomes: the rare deposit sits inside the reach.

The check runs during world generation (a quick pass per hex). A hex that fails is marked *too rugged* and cannot be founded. Generated terrain is never quietly changed to make it pass.

---

## 6. Persistence

| What | Where | Contents |
| --- | --- | --- |
| Campaign | `user://campaigns/<id>/campaign.json` | §4.4 |
| Active village | `user://campaigns/<id>/villages/<village>.json` | The village's full sim state, the site (or the hex to regenerate it from), the camera and the view settings |

- **Village save means real restore.** Add `VillageSim.from_snapshot(snapshot, content)`, the inverse of `snapshot()`, with `Building`, `Carrier` and `Storage` restored from their snapshot dictionaries. Snapshots already copy all authoritative state, including RNG, reservations and routes, so this is mostly deserialisation.
- **Test for it:** run a village, snapshot, restore, then step both copies the same number of ticks. Their snapshots must be identical. This extends the existing determinism test.
- **Save timing:** on returning to the map, on quitting, and every 2 minutes during a run. Write to a temporary file and rename, so a crash never leaves a half-written save.
- **Versioning:** both files carry a `version`. Older versions are migrated or refused with a clear message, never loaded wrongly.
- **Alternative considered:** a command log with deterministic replay. It is cheaper to write, but loading slows as runs get longer (a 90-minute run is 54,000 ticks), and every sim change breaks old logs. Restoring from snapshot is the better long-term base.

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
- **Ruin:** shown when the village's population reaches 0. It becomes a ruin that can later be resettled (DESIGN.md pillar 3).
- **Abandon:** from the options menu, with a confirmation. The hex becomes a ruin.

The real rules (Tier 3, export depot, morale, raids) replace these triggers later without changing `RunResult` or the map.

---

## 8. World map screen (`view/world_map/`)

- **Rendering:** the same pixel viewport, camera rig, lighting and atmosphere as the village, so the map matches its art.
  - Each hex is a low prism raised by its elevation band and coloured by biome.
  - Rivers are ribbons through hex centres and edge midpoints.
  - Ocean is a flat plane. Forests are a few instanced trees per forested hex; peaks are rock prisms.
  - The hex grid is drawn faintly in the ground shader.
- **Village hex markers:**
  - *active*: a few roofs with a banner;
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

The village view gets a **World map** button in its options menu and a run-result card. Its existing controls stay unchanged.

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
- [x] `view/world_map/world_map_view.tscn` with the village's camera rig, lighting and atmosphere, rendered **smooth at full resolution** (the pixel effect is being retired). It runs on its own: `godot --path . view/world_map/world_map_view.tscn -- --seed=N`. The village stays the main scene until phase D.
- [x] `view/world_map/world_map_mesh.gd` draws:
  - hex prisms raised by elevation band and coloured by biome, with darkened rims that read as the hex grid;
  - an ocean plane with lighter coastal shallows;
  - river ribbons with waterfalls where a river leaves higher ground or reaches the sea;
  - lakes, low-poly forests (conifers in the cold), snow-capped peaks, rocky passes and a start banner.
- [x] Hover ring and a hex panel: biome and difficulty, elevation, wildness, features, climate, known deposits, **Unscouted**, the start region, and whether the hex can be founded (with the reason if not). Hover follows mouse-motion events and re-picks as the camera moves. Picking marches the camera ray onto prism tops.
- [x] Debug keys: N / Shift+N for next / previous seed, V to reveal all deposits. `--screenshot` saves `artifacts/world-map.png` and quits.
- [x] View test: `godot --path . --script tests/run_world_map_tests.gd` (19 checks).
  - Models for 3 seeds; every land hex has a prism; changing seed replaces the model.
  - Hover picks the start, a raised hex and a sea hex.
  - Panel contents, Unscouted and the reveal key, camera rotation, next seed.

### Phase B: site generation from a hex (3–4 days)
- [ ] Next session: hex-shaped village footprint and terrain/river layout matching the selected world tile (12 October note above).
- [ ] `sim/world/site_gen.gd` (§5.1), reusing the existing site package, relief and hex maths.
- [ ] A playability check (§5.3) used by both world generation and site generation.
- [ ] Economy (sim/economy.gd): placement also needs treasury headroom ("Treasury needs …"; 10 g at the start) for logs taken from storehouses plus each new building's working money. The starter layout and any site-specific founding layout must fit that budget, and the playability check should place the starter through the real sim commands.
- [ ] Extend `dump_world.gd` to write `artifacts/site-<seed>-<q>-<r>.png` next to the hex and its neighbours.
- [ ] Tests:
  - every promised river, coast, lake and cliff appears in its part of the site;
  - deposits fall in their own hex and on valid terrain;
  - the founding hex is buildable;
  - the starter layout succeeds at the founding spot and bakes bread on 20 random settleable hexes across 3 seeds.

**Done when:** the paired PNGs read correctly by eye, and the tests pass.

### Phase C: persistence (2–3 days)
- [ ] `VillageSim.from_snapshot()` plus `from_snapshot` on `Building`, `Carrier` and `Storage`.
- [ ] `sim/world/campaign.gd` (§4.4), with save and load to JSON, atomic writes and versioning.
- [ ] Tests:
  - restoring a snapshot and stepping it matches the original run;
  - a campaign survives a save/load round trip;
  - a corrupt or old file is refused with a message.

**Done when:** a scripted run can be saved, reloaded and continued identically, headless.

### Phase D: world map screen (4–5 days)
- [ ] `view/world_map/world_map_view.tscn` becomes the new main scene, plus a small title menu (New campaign / Continue).
- [ ] Hex mesh, rivers, ocean, forests, markers and the hex grid (§8).
- [ ] Hover, hex panel, founding overlay, found card, village list.
- [ ] Scene switching between map and village: suspend, save and resume. The village gets a **World map** option.
- [ ] View tests:
  - real mouse input founds a village on a chosen hex and opens it;
  - returning to the map shows the active marker;
  - resuming restores the same tick and buildings.

**Done when:** a player can start a campaign, found a village, leave, resume, and see it on the map.

### Phase E: run results and campaign loop (2 days)
- [ ] `RunResult`, interim charter, ruin and abandon triggers (§7), the result card and map updates.
- [ ] Scouting after a run (§4.3). Ruins can be resettled.
- [ ] Test: three villages in a row on one campaign, with markers, spacing and scouting all correct after each run.

**Done when:** the week 12 gate's "3 runs in a row" can be played on the map, without the nation-turn systems.

Phases A, B and C are headless and can run in parallel with the current village work. A2 adds a standalone map scene without touching the village view. Phase D builds the interaction (founding, village list, scene switching) on A2's renderer.

---

## 10. What happens to the earlier work

| Item | Decision |
| --- | --- |
| `SitePackage`, `hex_math.gd`, reach, relief rules, `terrain_relief.gd` | **Keep.** Generated sites need them. |
| Terraces site, F4 switch | **Keep as debug fixtures** for relief, and remove F4 from the player-facing README once the world map ships |
| Continuous world function, 4-tile lattice, zoom transition, context ring, cross-scale consistency tests ([WORLD_MAP.md](WORLD_MAP.md) §1, §3, §5.7, §7, §9.2) | **Drop.** WORLD_MAP.md is marked as superseded by this plan |
| Biome table, deposit visibility, reach and spacing ([WORLD_MAP.md](WORLD_MAP.md) §2.1, §4, §5.6) | **Keep.** This plan refers to them |

---

## 11. Open questions

1. **More than one active village?** One at a time matches DESIGN.md's "one village per session", and keeps saves and the UI simple. Several in-progress villages would allow switching between them, at the cost of more saves and a busier list.
2. **Culture at founding.** Is the culture chosen on the found card from the start, or added once cultures have gameplay? The card has room for it either way.
3. **World size.** 480 hexes (24×20) was sized for the village spacing. As a level select, a smaller world (about 300) may read better on screen and still hold 12+ villages. Proposed: start at 300 and tune.
4. **Rumours.** Should unscouted hexes hint at hidden deposits, or stay silent?
5. **Spill timing.** Is the whole reach buildable from the start, or do neighbour hexes open up as the village grows?
6. **Resettling ruins.** What bonus does a ruin give (DESIGN.md "resettled later with a bonus"): starting logs, standing foundations, or scouted surroundings?
