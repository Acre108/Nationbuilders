# Hearthlands — First Bread

A Godot town-builder prototype for **milestone 1 / the week 4 gate**. Grow a small settlement from its first water deliveries to a working wheat → flour → bread chain. All gameplay code is GDScript.

![Late-afternoon village with a warm clearing and cool forest](docs/atmosphere-after.png)

**Pinned engine: Godot 4.7.2 stable** (Forward+). The imported SpacesOS environment systems require the newer lighting API. Headless simulation needs no GPU.

## Environment systems

The [project-wide art direction](docs/ART_DIRECTION.md) uses the village as the visual foundation: golden clearings, cool woodland, terracotta and cream materials, and quiet shared environmental motion. It defines the common palette and the next refinements for the world map.

Foliage, lighting, and atmosphere have been ported from SpacesOS and connected to the village. See [the port notes](docs/ENVIRONMENT_PORT.md) for scope and controls. Use `[` / `]` to change the hour, `0` to run the day/night cycle, and `5` through `9` for storm, mist, clear, cloudy, and rain.

The village art pass adds golden 16:00 sunlight, cool forest shade, contact shadows, broad terrain colour regions, embedded ochre paths and sparse shared wind/cloud motion. Tune the exported values in [view/village_art.tres](view/village_art.tres); see [the art guide and before/after](docs/VILLAGE_ART.md). Run `tools/run_tests.ps1 -Art` for its GPU regression checks.

The reference refinement adds fuller amber-lit crowns, brighter direct palette response, clay roof courses, stone wall feet, framed windows and richer clustered meadow details. The current default map surrounds the central settlement with woodland and natural clearings.

The [medieval building kit](docs/MEDIEVAL_BUILDINGS.md) adds Blender-authored timber frames, stonework, shutters, steep roofs and distinct workshop details. Production buildings display live input and output goods as sheaves, flour sacks, water barrels, bread trays and timber bundles. The editable Blender source and stock/empty previews are linked in the guide; run `tools/run_tests.ps1 -Buildings` to verify stock changes and generate review captures.

On a fresh checkout, open the project in Godot 4.7.2 to import its assets before playing or running view tests. The simulation runner remains independent of the environment.

## Play

Import [project.godot](project.godot) in Godot and press **F5** to open the main menu. A 1280 by 720 or larger window is recommended; the menu also fits the 960 by 640 minimum window.

1. Enter a campaign name and world seed, or choose **Random seed**, then **Generate world**. The new campaign is saved immediately.
2. On the world map, the starting region is selected. Click another hex to choose a site; oceans and peaks cannot be settled. Name your village and choose **Found village here**. The selected terrain is checked before founding; a rugged tile explains why it is blocked.
3. In the village, the map button saves progress and returns to the campaign world. Choose **Resume** to continue the village. The cog offers **Save campaign** and **Save & main menu**. Campaigns also save when closing the game normally.
4. Reaching the highest implemented tier offers **Charter village** or **Keep building**. Charter ends the run; **Abandon village** in options also ends it after confirmation. Continue with another village, or resettle a ruin for 12 extra starting logs.
5. Select a campaign under **Saved campaigns** and choose **Load campaign** to reopen its world and resume its active village. Completed runs remain in the village list.

Campaigns are independent files in Godot's `user://campaigns` folder. Saves preserve the complete village simulation, including carrier cargo/routes, household savings, production, stopped workers and regrowing trees. Writes replace the previous save only after the new file is complete; failures stay on the current screen with a message. Damaged saves and incompatible save/generator/game-data versions are rejected. One active village is supported per campaign, with persistent history for completed runs. New villages use [generated hex-shaped sites](docs/HEX_VILLAGES.md) whose rivers, lakes, coasts, groves and relief match the selected world tile and its neighbours. Press **Home**, or choose **Site overview (Home)** in options, to view the full site. Compatible v1 saves retain their original square geometry; incompatible game-data/generator saves are refused. Additional production chains remain future work.

For the standalone development village, press **F6** on `view/village_view.tscn`. Its restart and F4 site controls remain available outside a campaign.

The [world map art pass](docs/WORLD_MAP_ART.md) adds sculpted hex landscapes, imported nature scenery, riverbanks and coastal shelves. It follows the village's golden afternoon light, green/gold meadow palette, cool forest shade and shared breeze, with broader mountain ridges and sparse water glints. Press **L** on the map to compare separate tile dioramas with linked terrain and groves; hex borders remain visible in both modes. The mouse wheel zooms in for tile inspection, and the village hour/weather shortcuts work on the map. Run `tools/run_tests.ps1 -WorldMap` for its rendering, motion and interaction checks.

The village renders smoothly at full display resolution with antialiasing, letterboxed to a 16:9 frame on wider or taller windows. The earlier optional pixel view has been removed.

The default village map is **100 × 100 tiles**. The village sits in a central clearing, reached by a road from the western map edge. Woodland groves and smaller clearings fill the surrounding land. The starting village contains a field, storehouse with six carriers, well, woodcutter, homestead, and connected roads. Founding supplies are 100 logs and 36 berries, before construction costs. Wheat, flour and bread start at zero.

1. Watch carriers stock the homestead's pantry with water from the well and berries from the storehouse. The homestead eats from its pantry and becomes **Villagers** after 20 consecutive satisfied seconds (about 23 seconds after starting).
2. Open **Build**, choose **Windmill** or **Bakery**, and place each against a road. They unlock when the first house reaches Tier 2. Each goes up as a construction site: carriers bring its logs, the building rises, and then it opens ([docs/CONSTRUCTION.md](docs/CONSTRUCTION.md)). Click a site to see what it is waiting for, or cancel it.
3. Carriers transport wheat to the mill, flour and water to the bakery, and bread to storage. Bread, water and logs sustain Tier 2. The house gains a taller wall and a slate roof on upgrade.
4. Click a building to inspect it. The inspector leads with whether it works and why not: status, workers, what it makes and holds, and cycle progress; houses show their tier, happiness and time to upgrade, needs met (✓/✗), family, jobs and savings; storehouses show carriers on shift, fill and storekeeper. **Details** unfolds prices, wages, purses, owner, families and position. The build card shows what the treasury pays. **Stop workers** releases a building's workers to other jobs; **Resume workers** takes them back. **Pay** (low, normal, high) decides which workplaces, and which storehouses' carriers, get workers first: a raise comes from the treasury, a cut goes to it, and a storehouse's pay is its markup. The bottom bar holds the speed (pause, 1×, 3×), **Build**, **Overlays** (deposits, food, classes) and **Demolish**. The top-right buttons are Factions, the world map and the options cog. Top left, the gold counter shows the treasury and opens the **Treasury panel**, where you set the tax rate (15% by default), read the last payday's income and spending, see the public services the treasury runs, and, under Reserves, move gold into a public pay or capital reserve (two paydays of services are kept reserved automatically). Beside it, the resource bar shows stock by kind (food with its balance per minute, water, fuel, materials, ingredients, storehouse fill, and adults in work of all; hover it for dependents); hover a kind for each good, and click food for the food balance. A faction's offer appears as a "!" on the left edge, with a faint clock behind it counting down until it lapses; click it to accept or decline. The **Factions** button (FACTIONS.md) opens the panel with running pledges (a pledged Treasury lever shows a padlock), the power bar and one row per faction; click a row to see what drives its favour. The inspector shows who owns a building and, for a Crown building that factions buy, **Offer for sale**. A house shows its class, alignment and the pulls on it. UI changes follow [docs/UI.md](docs/UI.md).

| Control | Action |
| --- | --- |
| Build + choice + left click | Place the previewed building; green/red outline indicates a valid/invalid footprint |
| R / Rotate button while building | Rotate 90°; rectangular footprints swap width and depth |
| Road tool | Click start and end tiles; creates an orthogonal L-shaped road atomically |
| Left click a building | Show its detailed inspector |
| Demolish + left click | Remove road/building; contents are discarded and construction is not refunded |
| Right click / Escape | Cancel and return to Inspect |
| WASD | Pan camera |
| Q / E | Rotate 90° |
| Mouse wheel | Change orthographic zoom in steps |
| Home / Site overview in options | Frame the whole village site |
| Space / bottom-bar pause, 1×, 3× | Pause / resume, or set the speed |
| Overlays / F3 | Deposits: fertile soil in gold and timber in blue |
| Overlays / F7 | Food: fertile soil, wild berries, the fishing shore and game |
| Overlays / F5 | Classes: colour working-class houses by faction and tint roads within a union hall's or alehouse's reach |
| Overlays / F6 | Operations: workplaces in red (not working), yellow (below full capacity), green (could run at full capacity) or blue (at full capacity); houses red (heading down a tier), yellow (a need unmet) or green (every need met) |
| F4 | Switch site: First Bread ↔ Terraces (a 60×60 test site with cliffs, ramps, a waterfall and a river). `-- --site=terraces` starts there |
| Top-right cog | Options: site overview, restart village |
| F12 / `-- --dev` | Developer tools: the weather panel (sun button) |

Roads must share an edge with a building. Carriers use only road tiles, with no diagonal movement. An occupied road cannot be demolished until its carrier moves away. Disconnecting a route strands deliveries until a connection is restored. When a destination is demolished, any carried item is returned to its owner's storehouse if reachable.

## Test

Tests run in two tiers:

| Tier | Command | Time | When |
| --- | --- | ---: | --- |
| Quick | `tools/run_tests.ps1` | ~7 s | After every change |
| Full | `tools/run_tests.ps1 -Full` | ~4 min | Before committing, and at milestones |

The quick tier is the headless simulation suite without its slow sections: whole-campaign saves and the hour-long village run. The full tier runs every suite one at a time and prints a one-line summary for each. Logs are written to `artifacts/`. Single suites run with `-Headless` (every headless check), `-Sites`, `-View`, `-Campaign`, `-WorldMap`, `-GeneratedSites`, `-Forestry`, `-Art`, `-Buildings` or `-Environment`. Add `-View` to the quick tier when changing the village view.

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -Full
```

Without the wrapper, the headless runner is:

```sh
godot --headless --script tests/run_tests.gd               # every headless check
godot --headless --script tests/run_tests.gd -- --quick    # quick tier
```

It prints individual failures and exits nonzero on failure. It works on a fresh checkout without first opening the editor; scripts use explicit preloads and no global class cache.

The recorded checks and render evidence are in [docs/VALIDATION.md](docs/VALIDATION.md). To verify the runner's failure exit code itself, append `-- --verify-failure-exit`; this deliberately exits with code 1 before running the suite.

The wrapper waits for each Godot process's actual exit code. It defaults to `C:\Program Files (x86)\Godot\Godot.exe`; use `-Engine 'path\to\Godot.exe'` for another installation. The view suite opens an off-screen/hidden native window and needs a Forward+ GPU. Its screenshots are written to `artifacts/`.

```sh
# Equivalent GPU-backed input/render tests:
godot --script tests/run_view_tests.gd
# A standalone screenshot of the completed chain:
godot -- --render-smoke
```

The simulation suite covers content rejection, the complete carrier chain, house promotion and demotion, placement/road atomicity, workforce limits, local capacity, road-only A*, nearest reachable storage, interrupted-trip recovery, conservation of every good, new content without sim changes, and deterministic replay across tick batch sizes. The rendering suite sends real viewport input and checks the menus, building controls, direct world colors beyond the old 32-color limit, and full-resolution antialiased rendering.

The reference seed reaches Tier 2 at **tick 229 / 22.9 seconds** and produces its first bread at **tick 357 / 35.7 seconds**, with the mill and bakery placed immediately after promotion. The gate test allows up to 1,800 ticks / 3 simulated minutes. It runs for a further five minutes to verify continuing supply and Tier 2 stability.

Godot 4 uses the standard executable with `--headless`; it has no separate headless-only build. All reported execution results are from Windows; Linux has not been run.

## Architecture and rules

- `sim/`: only plain `RefCounted` classes. No nodes, scenes, rendering, frame delta, or global random calls. A village runs on a *site package* (`sim/world/`): size, terrain, levels, ramps, deposits and the buildable reach. Without one, the seeded Park–Miller RNG generates the default 100×100 coastal map. The coast follows the map dimensions; the starter layout shifts to the central clearing. Trees, saplings and stumps are authoritative simulation state. `SitePackage.DEFAULT_SIZE` defines the default; an explicit 40×40 generator size remains available for reference fixtures. Carriers and roads cross level changes only on ramps; buildings need flat, level ground inside the reach. See [the world map design](docs/WORLD_MAP.md).
- `data/`: goods, building recipes/footprints/costs/workers/capacities, and per-house needs. `content_db.gd` validates JSON and cross-references; a load failure stops startup with diagnostics. Producers are generic: add a JSON definition to add a building or recipe. The view supplies a generic placeholder mesh for unfamiliar building ids.
- `view/`: reads state, creates vertex-coloured primitive meshes, and sends commands. The view's accumulator calls `step(1)` at 10 ticks per simulated second; backlog is retained. Speeds alter the number of fixed ticks, never production or movement math.
- `render/`: the world SubViewport scene (rendered at full display resolution with 4× MSAA, under a separate full-resolution HUD) and the village, ground, contact-shadow, building-preview and world-map shaders. Village meshes use smooth weather-aware lighting alongside SpacesOS foliage. The original pixel pipeline (palette lookup, outline and dithered toon shaders) has been deleted.
- `tests/`: direct `SceneTree` runners; they never instantiate the view in the simulation suite.

Public sim API: `place(id, cell, rotation_quarters=0)`, `placement_error(id, cell, rotation_quarters=0)`, `place_road(Array[Vector2i])`, `demolish(Vector2i)`, `set_workers_enabled(uid, bool)`, `set_tax_percent(int)`, `set_pay(uid, level)`, `sell_building(uid, faction)`, `accept_offer(faction)`, `decline_offer(faction)`, `break_pledge("faction:type")`, `step(ticks)`, `snapshot()`. Building orientation uses quarter turns, normalized to 0–3; the anchor stays at the minimum grid corner of the rotated footprint. Commands return `bool`; rejection reasons are in `last_error`. Snapshots copy all authoritative mutable state, including building orientation, RNG, local slots, carrier reservations/cargo/routes, needs timers and map data. They support comparison/replay checks; `sim/campaign.gd` separately stores and restores versioned campaign saves.

Production inputs are consumed when a cycle starts; outputs appear when it completes. Input and output slots each hold six total items. Every carrier takes one item, moves one road tile every two ticks, and reserves both source stock and destination space. House pantries are stocked first, then workshop inputs; each delivery comes from the closest supply by road (a storehouse's stock or a producer's output). Remaining outputs, and pantry goods a house's tier no longer eats, go to the owning storehouse. Stable iteration and rotating job priority avoid random scheduling. A* uses Manhattan distance and fixed tie ordering; routes are cached only until the road/placement revision changes.

Four founding adults plus each house's data-defined workforce staff buildings in placement order, skipping buildings whose workers are stopped. Storehouse carriers are jobs too: they take the workers left after buildings are staffed. Each house eats from its own six-slot pantry, one need at a time, and its happiness is the share of its tier's needs met this cycle. A house demotes only when its happiness, averaged over its last three cycles, stays below 50%, and low village morale slows every workplace (down to half speed). Money is whole silver (100 silver = 1 gold): every link in a chain pays the one before it, so a good costs its inputs plus its maker's labour (bread 16 s, flour 9 s, wheat 4 s). Producers pass that labour to a payroll that households share every 20 seconds. Storehouses sell to households at a markup set by their pay (5%, 10% or 20%), which pays their carriers' wages. Villagers also need a chapel within 20 road tiles, a public service like the forester; berry bushes grow the Settlers' berries. Tax on wages (and rare storehouse surpluses) is the treasury's income, and public services such as the forester are its running cost. The treasury pays for construction materials, new buildings' working money and public workers; public workers left unpaid keep working, but their frustration grows. A house that cannot pay goes without. See [docs/VILLAGERS.md](docs/VILLAGERS.md). Construction spends logs from the founding reserve and storehouse inventories as a village-wide pool. Production and household food both arrive by road. Storehouses hold 180 items each, and carriers bring a producer's surplus only until a storehouse holds 30 of that good; the producer then fills up and waits. An empty new storehouse adds capacity and six carriers but grants no free goods.

## Milestone scope and design adaptations

[docs/DESIGN.md](docs/DESIGN.md) is the design reference, [docs/UI.md](docs/UI.md) holds the rules every HUD and screen change follows, and [docs/CODEX_PROMPT.md](docs/CODEX_PROMPT.md) is the original milestone 1 brief. The original Settlers/Villagers needs and unlock text is retained in `tiers.json` as `design_needs` and `design_unlocks`.

| Tier | Implemented per-house consumption | Promotion / demotion |
| --- | --- | --- |
| 1 · Settlers | 1 water + 1 berry every 100 ticks / 10 seconds; house provides shelter | 200 consecutive satisfied ticks to Tier 2; Tier 1 is the floor |
| 2 · Villagers | 1 water + 1 bread + 1 log every 200 ticks / 20 seconds | 900 consecutive unsatisfied ticks to Tier 1; no Tier 3 |

A house consumes a complete basket atomically from the **nearest reachable storehouse by road distance**. Fulfilment lasts until its next consumption deadline; a lost road immediately breaks fulfilment. Unlocks remain available after first achieving their tier, even if a house later downgrades.

The milestone excludes fish, meat and firewood production chains, chapels, smithies and markets. **Logs substitute for firewood**, the chapel service is explicitly deferred, and starting berries supply the initial Settler need. Water remains a need at Tier 2. Berry gathering is not implemented; stable Villagers no longer need berries. Wells remain a renewable prototype source. Woodcutters harvest actual nearby trees; foresters replenish woodland with saplings that mature in 60 simulated seconds. See [forestry and the wooded map](docs/FORESTRY.md). Adjacency bonuses await later balancing.

The prototype now supports campaign history, temporary chartering at the highest implemented tier, abandonment and resettlement. Natural population-loss ruins await a mortality system. Nation turns, factions, military, ages, seasons, raids, Tier 3 and advanced traffic remain later milestones.

Shader implementation references: Godot's [reverse-Z post-processing guide](https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html) and [screen/depth/normal texture documentation](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html).
