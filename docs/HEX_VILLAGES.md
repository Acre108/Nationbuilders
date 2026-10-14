# Hex villages and campaign runs

The world-map plan now has generated hex-shaped village sites and a complete prototype campaign loop. Choose a tile, found a village on its terrain, keep building or charter it, and continue with another village. The world retains the history of completed and abandoned runs.

![Generated hex village, seed 73](generated-village-73-overview.png)

![Founding beside the world tile's river](generated-village-73-close.png)

## Terrain and the playable boundary

New campaign sites have a regular hex physical boundary inside 144×168 backing arrays. Individual building and road cells remain square. The founding tile and its six neighbours supply seven terrain districts, at 48 local cells per world hex. Small corner wedges are assigned to the nearest district to retain a regular outline.

[terrain_layout.gd](../sim/world/terrain_layout.gd) is the authoritative shared layout for map and village: river curves, matching edge mouths and widths, linked lakes, coast orientation, groves, meadow openings and ridge fields. [site_gen.gd](../sim/world/site_gen.gd) samples it into terrain cells, quantized elevation levels, natural ramps and owned deposits. Water channels suppress local relief before either scale samples it.

The hex mask applies to terrain rendering, buildings, roads, routing, planting and growth. Exterior corners are void, including after save/load. The generator searches for a natural clearing that fits the actual starter, including planned mill/bakery space and the existing material/treasury budget. It does not move rivers or flatten failed terrain. Selected sites that lack enough connected land or a valid clearing are marked too rugged. Detailed checks run on selection/founding and are cached, preserving fast coarse-world generation.

When a founding tile promises river, lake or coastal water, its clearing must lie within eight cells of water. Dry inland sites retain the prototype well. Additional production chains and detailed biome gameplay remain separate work.

![World districts (left) and generated village terrain (right)](site-73-6-9.png)

The paired layout image is a headless terrain diagnostic; the GPU captures above show the playable art.

## Campaign controls

1. Create or load a campaign. The map's village list records each run's status. Selecting a hex checks its terrain and shows known resources across its reach.
2. Name and found a village. Oceans, peaks, rugged sites and sites too close to existing villages/ruins are blocked. One active village is supported.
3. Use the map button to save and return. **Resume active village** works even when another region is selected. Camera, zoom, rotation, pause/speed, deposit display and weather/wind settings are retained.
4. Press **Home**, or choose **Site overview (Home)** in options, to see the full hex. Scroll back in to inspect and build.
5. Reaching the highest implemented tier offers **Charter village** or **Keep building**. Charter ends the run and records its result. The options menu also offers **Abandon village**, with a confirmation.
6. Continue with another village. Completed villages and ruins enforce spacing and reveal nearby tiles. A ruin may be resettled with **12 extra starting logs**, shown on its founding card and recorded in campaign history.

Only the latest run at a location gets a world marker; earlier runs remain in the list. Active villages show roofs and a red banner, chartered villages show a larger roof cluster and a gold banner, and abandoned/ruined villages show broken walls.

The zero-population ruin contract exists, but natural population loss is not yet part of the simulation: four founding adults remain. Abandonment supplies the current playable ruin/resettlement path. Tier 3, faction/export charter rules and nation turns remain outside this prototype plan.

## Saving

Campaign save version 2 uses an atomic, checksum-protected binary Variant file in `user://campaigns`. It stores typed tile arrays, complete active simulation/site state, delivery jobs and cargo, RNG, finances, forestry, history, results, scouting and both views' settings. Saves occur on founding, transitions, normal quit and every two minutes. A failed transition save keeps the scene/run intact.

Compatible version 1 saves migrate and retain their original square village geometry. Saves with incompatible game data or world generator versions are refused with a clear message; they are not overwritten by loading. The generator is now version 2, including resource checks that prevent fish shoals on dry tiles and amber shores inland.

## Art refinement

The follow-up pass uses the [project art direction](ART_DIRECTION.md): golden light, broad meadow colour, cool woodland interiors, warm crowns, muted stone and turquoise water. Regional metadata selects cold conifers, marsh birches and temperate oak/birch groves. Seeded visual offsets reduce tree rows while keeping every root in its resource cell; contacts, regrowth and stumps use the same position.

The soil edge follows the physical hex, with consistent lighting across its six sides. Generated sites use a quiet weather-aware background at overview scale to avoid sky-projection streaks. Sky-based fill, cloud shadows, wind and weather continue to operate. Legacy authored square fixtures retain their existing appearance and controls.

![A different site's relief and vegetation, seed 1](generated-village-1-overview.png)

## Validation and review

```powershell
./tools/run_tests.ps1
./tools/run_tests.ps1 -Sites
./tools/run_tests.ps1 -GeneratedSites
./tools/run_tests.ps1 -Campaign
./tools/run_tests.ps1 -WorldMap
```

Recorded checks included 21 generated villages baking bread across three seeds (the suite now builds 2 random villages per seed besides each start and lake site; see [VALIDATION.md](VALIDATION.md)); real lake/coast/confluence fixtures; footprint and terrain alignment; deterministic snapshot continuation; interrupted delivery restoration; atomic save failures; malformed view-state rejection; three-run campaign history/resettlement; keyboard/mouse flow; and 960×640 full-site framing. The generated-site GPU suite verifies that art does not alter simulation/RNG and that no terrain tops or foliage roots leak into exterior corners.

The headless paired-image tool also supports:

```powershell
# World, selected village terrain and neighbouring district captures:
godot --headless --script tools/dump_world.gd -- --seeds=73,1,2
# A lake site, or a specific world coordinate:
godot --headless --script tools/dump_world.gd -- --seeds=73 --lake
godot --headless --script tools/dump_world.gd -- --seeds=73 --site=6,9
```
