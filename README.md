# Hearthlands — First Bread

A Godot town-builder prototype for **milestone 1 / the week 4 gate**. Grow a small settlement from its first water deliveries to a working wheat → flour → bread chain. All gameplay code is GDScript.

![The milestone 1 village with compact bottom controls](docs/first-bread.png)

**Pinned engine: Godot 4.3 stable, official build `77dcf97d8`** ([download](https://godotengine.org/download/archive/4.3-stable/)). Use **Forward+** for the playable view: its outline pass needs the depth and normal buffers. Headless simulation needs no GPU.

## Play

Import [project.godot](project.godot) in Godot and press **F6** on `view/village_view.tscn`, or **F5** to run the project. The main scene is already set. A 1280×720 or larger window is recommended.

The starting village contains a field, storehouse with six carriers, well, woodcutter, homestead, and connected roads. Founding supplies are 100 logs and 36 berries, before construction costs. Wheat, flour and bread start at zero.

1. Watch the well supply the storehouse. The homestead consumes water and berries and becomes **Villagers** after 20 consecutive satisfied seconds (about 24 seconds after starting).
2. Open **Build**, choose **Windmill** or **Bakery**, and place each against a road. They unlock when the first house reaches Tier 2.
3. Carriers transport wheat to the mill, flour and water to the bakery, and bread to storage. Bread, water and logs sustain Tier 2. The house gains a taller wall and a blue-green roof on upgrade.
4. Click a building to see its name, tier and status. The play screen has three bottom buttons: **Demolish**, **Deposits** and **Build**. Resource totals remain in the simulation and are not displayed.

| Control | Action |
| --- | --- |
| Build + choice + left click | Place a building; green/red outline indicates a valid/invalid footprint |
| Road tool | Click start and end tiles; creates an orthogonal L-shaped road atomically |
| Left click a building | Show its compact inspector |
| Demolish + left click | Remove road/building; contents are discarded and construction is not refunded |
| Right click / Escape | Cancel and return to Inspect |
| WASD | Pan camera |
| Q / E | Rotate 90° |
| Mouse wheel | Change orthographic zoom in steps |
| Space | Pause / resume |
| F2 | Compare raw toon lighting with outline + palette processing |
| Deposits / F3 | Show fertile soil in gold and timber in blue |

Roads must share an edge with a building. Carriers use only road tiles, with no diagonal movement. An occupied road cannot be demolished until its carrier moves away. Disconnecting a route strands deliveries until a connection is restored. When a destination is demolished, any carried item is returned to its owner's storehouse if reachable.

## Test

From the project root, the required rendering-free runner is:

```sh
godot --headless --script tests/run_tests.gd
```

It prints individual failures and exits nonzero on failure. It works on a fresh checkout without first opening the editor; scripts use explicit preloads and no global class cache.

The recorded checks and render evidence are in [docs/VALIDATION.md](docs/VALIDATION.md). To verify the runner's failure exit code itself, append `-- --verify-failure-exit`; this deliberately exits with code 1 before running the suite.

For the installed Windows GUI executable, the wrapper waits for the actual process exit code and prints its log:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -View
```

The wrapper defaults to `C:\Program Files (x86)\Godot\Godot.exe`; use `-Engine 'path\to\Godot.exe'` for another installation. The view suite opens an off-screen/hidden native window and needs a Forward+ GPU. Its screenshots are written to `artifacts/`.

```sh
# Equivalent GPU-backed input/render tests:
godot --script tests/run_view_tests.gd
# A standalone screenshot of the completed chain:
godot -- --render-smoke
```

The simulation suite covers content rejection, the complete carrier chain, house promotion and demotion, placement/road atomicity, workforce limits, local capacity, road-only A*, nearest reachable storage, interrupted-trip recovery, conservation of every good, new content without sim changes, and deterministic replay across tick batch sizes. The rendering suite sends real viewport mouse/key events and checks the build menu, deposits toggle, building controls, a 32-colour world, exact 2×2 pixels, and an active outline pass.

The reference seed reaches Tier 2 at **tick 237 / 23.7 seconds** and produces its first bread at **tick 359 / 35.9 seconds**, with the mill and bakery placed immediately after promotion. The gate test allows up to 1,800 ticks / 3 simulated minutes. It runs for a further five minutes to verify continuing supply and Tier 2 stability.

Godot 4 uses the standard executable with `--headless`; it has no separate headless-only build. All reported execution results are from Windows; Linux has not been run.

## Architecture and rules

- `sim/`: only plain `RefCounted` classes. No nodes, scenes, rendering, frame delta, or global random calls. A single seeded Park–Miller RNG generates the 40×40 terrain and one deposit layer.
- `data/`: goods, building recipes/footprints/costs/workers/capacities, and per-house needs. `content_db.gd` validates JSON and cross-references; a load failure stops startup with diagnostics. Producers are generic: add a JSON definition to add a building or recipe. The view supplies a generic placeholder mesh for unfamiliar building ids.
- `view/`: reads state, creates vertex-coloured primitive meshes, and sends commands. The view's accumulator calls `step(1)` at 10 ticks per simulated second; backlog is retained. Speeds alter the number of fixed ticks, never production or movement math.
- `render/`: 640×360 SubViewport; camera at about 39.5° pitch with 90° rotations and translation snapped in camera space. Nearest-neighbour integer scaling and letterboxing; UI is a separate full-resolution CanvasLayer. Three lighting bands and ordered dithering confined to shadow lighting; a one-native-pixel depth/normal outline pass; a 16³ RGB lookup table selecting from the 32 colours in `render/palettes/hearth32.json`. No textures or external art packages required.
- `tests/`: direct `SceneTree` runners; they never instantiate the view in the simulation suite.

Public sim API: `place(id, Vector2i)`, `place_road(Array[Vector2i])`, `demolish(Vector2i)`, `step(ticks)`, `snapshot()`. Commands return `bool`; rejection reasons are in `last_error`. Snapshots copy all authoritative mutable state, including RNG, local slots, carrier reservations/cargo/routes, needs timers and map data. They support comparison/replay checks, not save-game loading in this milestone.

Production inputs are consumed when a cycle starts; outputs appear when it completes. Input and output slots each hold six total items. Every carrier takes one item, moves one road tile every two ticks, and reserves both source stock and destination space. Direct input deliveries get priority; remaining outputs go to the owning storehouse. Stable iteration and rotating job priority avoid random scheduling. A* uses Manhattan distance and fixed tie ordering; routes are cached only until the road/placement revision changes.

Four founding adults plus each house's data-defined workforce staff buildings in placement order. Storehouse carriers are separate transport workers. Construction spends logs from the founding reserve and storehouse inventories as a village-wide pool. Production and household consumption still require a road connection. Storehouses hold 180 items each; an empty new storehouse adds capacity and six carriers but grants no free goods.

## Milestone scope and design adaptations

[docs/DESIGN.md](docs/DESIGN.md) is the design reference and [docs/CODEX_PROMPT.md](docs/CODEX_PROMPT.md) is the original milestone 1 brief. The original Settlers/Villagers needs and unlock text is retained in `tiers.json` as `design_needs` and `design_unlocks`.

| Tier | Implemented per-house consumption | Promotion / demotion |
| --- | --- | --- |
| 1 · Settlers | 1 water + 1 berry every 100 ticks / 10 seconds; house provides shelter | 200 consecutive satisfied ticks to Tier 2; Tier 1 is the floor |
| 2 · Villagers | 1 water + 1 bread + 1 log every 200 ticks / 20 seconds | 900 consecutive unsatisfied ticks to Tier 1; no Tier 3 |

A house consumes a complete basket atomically from the **nearest reachable storehouse by road distance**. Fulfilment lasts until its next consumption deadline; a lost road immediately breaks fulfilment. Unlocks remain available after first achieving their tier, even if a house later downgrades.

The milestone excludes fish, meat and firewood production chains, chapels, smithies and markets. **Logs substitute for firewood**, the chapel service is explicitly deferred, and starting berries supply the initial Settler need. Water remains a need at Tier 2. Berry gathering is not implemented; stable Villagers no longer need berries. Wells and woodcutters are renewable prototype sources; terrain/deposits are generated and exposed but depletion/adjacency bonuses await later balancing.

There is no nation layer, factions, military, ages, seasons, raids, Tier 3, chartering, save/load, or advanced traffic simulation. The target here is the first working village chain and the pixel-rendering proof.

Shader implementation references: Godot's [reverse-Z post-processing guide](https://docs.godotengine.org/en/4.3/tutorials/shaders/advanced_postprocessing.html) and [screen/depth/normal texture documentation](https://docs.godotengine.org/en/4.3/tutorials/shaders/screen-reading_shaders.html).
