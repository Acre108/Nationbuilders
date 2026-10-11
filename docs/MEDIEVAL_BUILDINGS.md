# Medieval building kit

The [project-wide art direction](ART_DIRECTION.md) sets the palette, material and motion rules for this kit and future assets. This guide records the current building implementation and authoring workflow.

The playable village uses original Blender-authored buildings with timber frames,
steep clay roofs, raised roof courses, stone foundations, shuttered windows,
plank doors, iron straps and workshop fittings. Homesteads have separate Tier 1
and Tier 2 models; the upgraded house has a taller frame, slate roof and window
boxes. The storehouse has a loading canopy, double doors and loft hoist.

![Medieval building kit, staged with full producer inventories](medieval-kit-stocked.png)

The kit contains nine building models and six stock props. The bakery has a
stone oven, bread sign and striped canopy; the woodcutter has a drying shelter
and chopping tools; the forester has a green nursery canopy, planted beds, spade and tree sign; the well has a masonry ring and winding mechanism; the field
has wheat heads, fencing and a tool shelter. The mill's four lattice-and-canvas
sails rotate while production is working.

## Stock displays

Every production building displays its actual local input and output stock.
Each visible bundle, sack, barrel or bread tray represents one stored resource
unit. Inputs and finished goods occupy separate spaces. The inspector continues
to provide exact numeric inventory and production details.

| Building | Visible inputs | Visible outputs |
| --- | --- | --- |
| Wheat field | | Harvested sheaves at the field corner |
| Well | | Banded water barrels beside the ring |
| Woodcutter | | Timber bundles inside the drying shelter |
| Windmill | Grain sheaves beside the tower | Flour sacks on the loading platform |
| Bakery | Flour sacks and water barrels along the side wall | Bread trays on the front counter |

| Empty bakery | Bakery with full input and output slots |
| --- | --- |
| ![Empty shelves and side yard](medieval-bakery-empty.png) | ![Flour, water and bread present](medieval-bakery-stocked.png) |

Goods appear on delivery or production completion and disappear when consumed
or collected. Reserved goods remain visible until the carrier picks them up.
Empty slots show the empty counter or shelter. The sign's carved loaf and the
woodcutter's stump and axe are permanent work fittings.

The gallery above stages full inventories for review. This game capture uses
the normal seed 73 village and its real inventory at tick 1000:

![Buildings in the running village at the closest gameplay zoom](medieval-village-close.png)

## Rotate during placement

Choose a building, then press **R** or click **Rotate 90° (R)** in its placement
card. The translucent model and footprint preview turn together. Rectangular
buildings swap width and depth on each odd quarter turn, and the card shows the
current size and facing. Repeated placement keeps the chosen facing; choosing
another building or cancelling resets it.

Placed buildings retain their facing through tier upgrades. Stock displays and
mill sails follow the model's rotation. Inspection and demolition work from any
occupied tile, and carriers use the rotated perimeter for road access.

![Storehouse preview rotated to a 2 by 3 footprint](rotation-preview.png)

Rotation validation: 179 simulation checks, 105 view checks and 7,728 building
checks pass. The simulation suite covers every quarter turn, overlap, map edges,
terrain, levels, ramps, reach, delivery access and deterministic snapshots.

## Source and runtime

- Editable source: [medieval_buildings.blend](../assets/buildings/medieval/source/medieval_buildings.blend).
- Generator: [build_medieval_assets.py](../tools/build_medieval_assets.py).
- Runtime models: `assets/buildings/medieval/*.glb`.
- Asset loading, material conversion and stock display: [medieval_buildings.gd](../view/medieval_buildings.gd).

The Blender source is arranged as a gallery with a collection per asset. GLB
exports use tile units and origin-centred placement; the sails retain a separate
front pivot. The source directory has `.gdignore` so Godot loads the exported
GLBs without needing Blender installed.

Rebuild the kit from the project root:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 3.2\blender.exe' --background --python tools/build_medieval_assets.py
```

Rebuilding overwrites the generated GLBs and Blender source. For manual edits,
export the chosen collection at the origin and retain the `Sails` node name and
world-aligned pivot. Palette materials are named `kind_hex`, for example
`roof_b76240` and `wall_ead7af`; change the hex suffix when repainting. The runtime
converts these colours to vertex colours and groups them into shared village
shader surfaces, preserving wet weather, cloud light and the existing art grade.

Stock meshes are shared and instances reused. Visibility changes only when the
local inventory changes. New producer definitions use the generic building
fallback and display unfamiliar goods as crates. All presentation reads the
simulation; recipes, production timing, workforce, capacity and transport remain
the existing game rules.

## Verification

```powershell
./tools/run_tests.ps1
./tools/run_tests.ps1 -View
./tools/run_tests.ps1 -Art
./tools/run_tests.ps1 -Buildings
```

The building suite checks the real bread chain for 700 successive ticks,
compares input/output props to every producer's stock, confirms presentation
leaves simulation and RNG unchanged, checks mixed/full/empty slots and prop
reuse, and verifies the mill's animation plane. It saves gameplay and staged
review captures in `artifacts/medieval-*.png`.

Validated on 11 October 2026 with Godot 4.7.2 Forward+ on Windows/NVIDIA RTX
3060 Ti: 112 simulation, 74 view, 273 art and 7,728 building checks pass.
