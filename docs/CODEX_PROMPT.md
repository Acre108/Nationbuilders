# Codex prompt: Hearthlands prototype, milestone 1

Copy everything below the line into Codex.

---

You are starting the prototype of **Hearthlands**, a light, challenging town builder made in Godot 4. Read `docs/DESIGN.md` before you start: it is the design reference. This task covers **milestone 1 only** (the week 4 gate): one production chain playable end to end, plus a spike that proves the pixel-art render pipeline. Do not build the nation layer, factions, military or ages yet.

## Goal

When you finish, a player can open the project, see a small pixel-shaded 3D village map, and do the following:
1. Place buildings and roads.
2. Watch carriers move goods along the chain field → wheat → mill → flour → bakery → bread.
3. See a house upgrade from Tier 1 (Settlers) to Tier 2 (Villagers) once its needs are met.

A headless test proves the same chain works without rendering anything.

## Constraints

- **Engine:** Godot 4.3 or later, GDScript only. Pin the version you use in `README.md`. If Godot isn't installed, download the official headless Linux build for tests.
- **Sim and view stay separate.** All simulation code lives in `sim/`, is made of plain `RefCounted` classes, and never touches nodes, scenes or rendering. Scenes in `view/` read sim state and send it player commands. This separation is required: it is what makes headless tests and balancing possible.
- **Content is data-driven.** Buildings, goods, recipes and needs tiers live in JSON under `data/`. Adding a building or chain must not need code changes. Validate data on load and fail loudly on unknown ids.
- **Deterministic.** The sim advances in fixed ticks (for example 10 per second) and is never tied to frame time. All randomness goes through one seeded RNG, so the same seed and the same commands give the same state.
- **Keep it small.** Only the buildings this chain needs, plus house, well, storehouse, road and woodcutter. Use placeholder art: primitive or very simple meshes coloured with vertex colours.

## What to build

### 1. Project skeleton
```
project.godot
data/        goods.json, buildings.json, tiers.json
sim/         content_db.gd, village_sim.gd, grid.gd, building.gd, carrier.gd, storage.gd, needs.gd, rng.gd
view/        village_view.tscn, camera_rig.gd, build_tool.gd, overlays/
render/      pixel_viewport.tscn, outline.gdshader, palette.gdshader, palettes/
tests/       run_tests.gd, test_*.gd
README.md
```

### 2. Content database (`sim/content_db.gd`)
- Loads and cross-validates the JSON files.
- Goods: `wheat`, `flour`, `bread`, `water`, `logs`, `berries`.
- Each building has: footprint, cost, worker count, inputs, outputs, cycle time in ticks, and the tier that unlocks it.
- Tiers: the Settlers and Villagers rows from `docs/DESIGN.md`, with per-house consumption rates.

### 3. Village sim (`sim/village_sim.gd`)
- A 40×40 tile grid with terrain (grass, forest, water, rock) and one deposit layer.
- Placement rules: building footprints, roads, and no overlap.
- **Production:** a building with all its inputs present runs its cycle and puts outputs in a local output slot (capacity 4–6).
- **Carriers:** each storehouse owns N carriers. A carrier finds a job (move good X from building A's output to building B's input, or to or from the storehouse) and walks the road graph using A* on road tiles. It takes one item per trip. Keep it simple, with no traffic simulation.
- **Needs:** each house consumes its tier's goods from the nearest storehouse it can reach. A house whose needs have been satisfied for a set time upgrades a tier; a house left unsatisfied for long enough downgrades.
- **Inspector state:** for each building, expose status (working, missing input X, output full, no workers) so the view can show it.
- **Commands:** `place(building_id, cell)`, `place_road(cells)`, `demolish(cell)`, `step(ticks)`, `snapshot()`.

### 4. Headless tests (`tests/`)
- A tiny runner started with `godot --headless --script tests/run_tests.gd`. It exits non-zero on failure.
- Tests to include:
  - The content database rejects a recipe that uses an unknown good.
  - A scripted layout (farm, mill, bakery, storehouse, house, well, roads) produces bread within N simulated minutes.
  - The house reaches Tier 2.
  - The same seed and commands give identical snapshots on two runs.
  - A building with no road connection reports "no access" and produces nothing.
- Document the test command in `README.md`.

### 5. Render spike (`render/`)
Build the pixel-art pipeline from `docs/DESIGN.md`:
- Render the 3D scene into a SubViewport at 640×360, then display it with integer upscaling and nearest-neighbour filtering. Choose the largest integer scale that fits the window.
- Use an orthographic camera at a pitch of about 35°. Q and E rotate it in 90° steps with a short tween; WASD or edge-scroll pans; there are 2–3 integer zoom levels.
- **Pixel snapping:** snap the camera to the texel grid in view space and offset the upscaled image by the sub-pixel remainder, so panning is smooth and does not shimmer.
- **Post-process:** 1 px dark outlines from depth and normal edges, toon lighting in 2–3 bands, and a palette LUT of about 32 colours loaded from a PNG in `render/palettes/`. Add a debug key that cycles summer, autumn and winter palettes to prove seasonal swaps.
- UI and overlays (status icons above buildings, the placement ghost, the selection outline) draw on a separate crisp CanvasLayer at the same pixel scale, not through the shader.

### 6. Minimal view
- A build menu listing the buildings unlocked at the current tier.
- Placement ghost showing valid or invalid placement, and road drag.
- Carriers drawn as small chunky meshes carrying a coloured cube for their good.
- Hovering a building shows its status and its input and output stock.
- A top bar with population by tier, storehouse totals, and a pause/1×/3× speed control.

## Definition of done
- `godot --headless --script tests/run_tests.gd` passes.
- Running the project shows the pixel-shaded village. A player can build the bread chain by hand and watch a house reach Tier 2.
- Panning and rotating the camera does not shimmer or crawl; check this by eye and describe the result.
- `README.md` covers how to run the project, how to run the tests, the folder layout, and how to add a new building through JSON only.
- Commit in small, logical steps with clear messages.

## Report back with
- What you built, plus any deviations from this prompt or from `docs/DESIGN.md` and why.
- Screenshots or a short description of the render result at 1080p.
- Anything that felt wrong or fiddly in the design while you were implementing it, especially the carrier logic and the shader snapping. These feed the week 7 milestone.
