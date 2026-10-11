# POLY Nature Pack foliage

Outdoor profiles use `POLY_NaturePack` by default (`use_nature_pack = true`).
The 42 curated, textured runtime assets live in `assets/foliage/poly_nature/`
(40 distinct source models, about 11% of the pack's 370 model names).
The previous sprite/paint assets are retained under `assets/foliage/legacy/`
for the procedural comparison fixture and profiles that explicitly disable
the pack. Downloads are excluded from Godot's main project scan and exports.

One additional original Blender asset, `willow_weeping`, lives under
`assets/foliage/custom/`. It uses the same Near/Far mesh and material/wind
pipeline, with an original narrow-leaf texture and the existing pack bark
palette. It is available for explicit landmark placement, without changing
regional forest scatter. It does not increase the percentage of the source
pack imported.

No willow exists in either downloaded pack, and the marketplace and
untextured web models found were not used. The willow is original
procedural work, built by `tools/blender/make_weeping_willow.py` (seed 32032;
source `tools/blender/sources/willow_weeping.blend`, provenance in
`assets/foliage/custom/willow_weeping.json`):

```powershell
& 'C:/Program Files/Blender Foundation/Blender 3.2/blender.exe' --background --factory-startup --python tools/blender/make_weeping_willow.py
```

Its leaves are an original atlas in the oak palette, but the bark uses the
pack's `Polygon_Texture2`, so it is not independently licensed. Near has
13,658 triangles and Far 3,965. It is registered and exported but in no
scatter or destination, and it has no collider: placing it needs a trunk
collider, a ground exclusion footprint and a far LOD or impostor choice.
`scripts/test_nature_pack.gd` checks it, and `scripts/capture_weeping_willow.gd`
renders it beside oak and birch ([lineup](../reference/nature_pack/willow_lineup.png)).

The conversion reads the pack's Godot prefabs, rather than its raw glTF
models: the prefabs contain the correct material overrides, including leaf
textures and alpha cutouts. It exports the source LOD1 and LOD2 groups into
self-contained GLBs. At runtime, source surfaces and texture UVs survive;
meshes are centred, rooted at ground level and scaled to the existing species
heights in metres. Placement, growth masks, slope rules, treeline/snow rules,
streaming, grass carving and instance seeds remain owned by the existing layers.

## Regional selection

`NatureAssetCatalogue` is the shared selection registry. An imported profile
persists `nature_region`; authored profiles can leave it at `auto` to use their
climate code, or choose a region in the inspector.

| Region | Starting selection |
| --- | --- |
| Temperate | Oak/maple/poplar, birch/aspen, mixed bushes, ferns |
| Mediterranean (`Cs`) | Temperate broadleaf, pine instead of spruce, little fern cover |
| Boreal (`D`) | Aspen/birch, spruce/pine, juniper, ferns |
| Alpine (`E` with authored treeline) | Conifers below the existing treeline, short grass, low moss cover |
| Polar (`E` without alpine context) | Short grass and low moss cover; no imported tree cover |
| Warm dry (`Bh`, latitude within 40 degrees) | Agave/aloe shrubs and short grass; no imported broadleaf cover |
| Cold dry (other `B`) | Juniper shrubs and short grass, without succulents |
| Tropical (`A`) | Grass, bushes and ferns; canopy omitted because the pack lacks rainforest trees |

These are editable visual starting points, not species occurrence data.
Black Forest explicitly uses temperate assets despite its `Dfb` climate code;
Swiss Alps uses alpine assets. Their existing tuned densities are preserved.

The pack has no true fir or alpine cushion species: the existing `fir_cover`
slot uses spruce models, and `cushion_cover` uses low moss models. The slot
names remain compatible with existing profiles and terrain masks. There is no
new moss scatter family. Regional selection changes models; it does not infer
vegetation from satellite land cover.

## Lake Brienz

`lake_brienz.tres` and the location importer's `lake_brienz` override select
`nature_asset_set = "lake_brienz"`: maple/aspen, three birch variants,
spruce/pine and the existing spruce stand-in for fir. Trees retain the Alpine
terrain profile's 2,100 m treeline. This is a curated visual approximation;
the pack lacks true beech and silver fir models, and placement does not use
surveyed vegetation or individual-tree data.

Eleven additional prefab models were converted: two birches, three reed/rush
clumps, three small stones and three grey round/square/layered boulders. The
boulders also replace the generic dry-land rocks for this location.

`ShorelineLayer` streams instanced source meshes around fitted lake outlines.
The Brienz profile restricts this scatter to the named `Brienzersee`, avoiding
the mountain tarns. Reeds occupy patchy margins within 3 m of the shore, at
depths up to 0.55 m or banks up to 0.6 m above water; both shaped-ground and
natural DEM slopes must be at most 24 degrees. Stones occupy a wider 12 m
margin and avoid water deeper than 1.25 m. Painted exclusions apply to both.
These are editable habitat and appearance rules, not an ecological survey.

The [Bern shoreline plan](https://www.raumplanung.dij.be.ch/content/dam/raumplanung_dij/dokumente/de/Raumplanungsthemen/Landschaft-und-Umwelt/Planungen-zum-See--und-Flussufergesetz-%28SFG%29/see-und-flussuferrichtpl%C3%A4ne/oberland%20ost%20objektblatt%205-de.pdf)
documents reed beds and their protection/restoration around Brienzersee.
The visual tree choices draw on the pack's available models; [WSL's forest
research](https://www.wsl.ch/en/forest/forest-management-and-forest-functions/experimental-forest-management/continuous-cover-forest-research/)
describes spruce, silver fir and beech in Swiss managed forests.

The foliage adapter reads the water work's fitted `signed_distance(x,z)`,
`levels` and `names` through the terrain's `imported_rivers.lakes`. It changes
no water geometry, shaders or carving. Without fitted/enabled lake data the
optional shoreline layer is omitted; the trees and dry-land rocks still work.
For other lake profiles, opt in with `shoreline_reed_cover` and
`shoreline_rock_cover`, plus an optional `shoreline_lake_name` filter.

`scripts/test_lake_brienz_foliage.gd` checks habitat exclusions, determinism,
quality thinning, lake-name filtering, worker teardown and the real shoreline.
`godot --path . --script res://scripts/capture_lake_brienz_foliage.gd` renders
the actual imported location to `reference/nature_pack/lake_brienz.png`.

## Import a location profile

Existing no-argument regeneration of the curated locations still works.
To author a profile from any imported DEM manifest:

```powershell
godot --headless --path . --script res://tools/geo/make_location_profile.gd -- --manifest=res://content/terrain/heightmaps/my_location.json --output=res://content/locations/my_location.tres --display-name="My location" --seed=1234
```

Use `--region=temperate` (or another registry region) to override the selected
asset set. Climate-derived density and per-location overrides still apply.
Regeneration remains an authoring operation that replaces the output profile;
retain hand tuning in the importer overrides before regenerating an existing
profile. A destination definition must still reference the resulting profile
and heightmap manifest as described in `GEO_IMPORT.md`.

## Forest-floor cover

Environment zones (phase Z3, see [ENVIRONMENT_ZONES.md](ENVIRONMENT_ZONES.md))
place moss, litter, stumps and mushrooms by zone recipe
(`GroundCoverScatter`, drawn by `DebrisLayer`). The assets are listed in
`NatureAssetCatalogue.FLOOR_ASSETS`, with target heights in `FLOOR_HEIGHTS`.

Stand-ins and gaps:

- **No needle or leaf litter mesh in the pack.** `needle_litter` is
  `Ones/SM_Muss_011`, a flat mat of dry twigs, recoloured from orange/red to
  rust-brown through `ASSET_RECOLOURS`. The woodland floor colour itself comes
  from the terrain tint (Z2).
- **No conifer stumps.** Oak, maple and poplar stumps stand in, scaled from
  their source 1.4–1.6 m down to about 0.55 m.
- **Mosses tinted.** `moss_1` and `moss_tuft` (`Ones/SM_Muss_010`) turn
  yellow in full sun; `ASSET_TINTS` pulls them back to green.
- **Not imported:**
  - The red mosses (`SM_Moss_03`, `Ones/SM_Muss_012`) are now imported as
    heather (see below).
  - `Trunks/SM_Branch_02` (4.6 m) and the aspen stump (3.7 m wide) are too
    large for scattered litter.
  - Morel and honey fungus are left out; one cluster type (toadstool) covers
    them.
  - Berry shrubs (wolfberry, currant, raspberry, blackberry) belong to a
    later undergrowth pass.

## Coastal dune and heath

The DUNE and HEATH zones (Z8, see
[ENVIRONMENT_ZONES.md](ENVIRONMENT_ZONES.md)) were added for
Waterleidingduinen. The pack has no coastal or heathland species, so the
`marram`, `heather` and `buckthorn` floor categories
(`NatureAssetCatalogue.DUNE_HEATH_ASSETS`) use stand-ins, imported through
`import_nature_pack.gd`:

| Runtime asset | Source prefab | Stands in for | Height |
| --- | --- | --- | --- |
| `marram_1` | `SM_Sea_Reeds` | Marram grass (*Ammophila arenaria*) | 0.8 m |
| `marram_2` | `Ones/SM_Sea_Reeds_005` | Marram grass | 0.7 m |
| `sea_buckthorn` | `SM_Wolfberry` | Sea buckthorn (*Hippophae rhamnoides*) | 2.2 m |
| `heather_1` | `Ones/SM_Lavender` | Heather in flower (*Calluna vulgaris*) | 0.4 m |
| `heather_2` | `SM_Moss_03` | Heather/crowberry mats (*Empetrum nigrum*) | 0.25 m |
| `heather_3` | `Ones/SM_Muss_012` | Heather/crowberry mats | 0.2 m |

- The sea reeds' seed heads are pink; `ASSET_TINTS` turns marram pale straw.
- Lavender's bright purple spikes read as heather in flower (August to
  September). Floor cover has no seasonal swap, so it stays in flower all year,
  including at Waterleidingduinen's `day_of_year` 120 (late April).
- `SM_Lavender`'s source material is flagged opaque although its texture is
  a cut-out, so `heather_1` drew as black squares. The converter forces
  alpha scissor for it (`CUTOUT_ASSETS` in `import_nature_pack.gd`).
- The red moss mats read as paint-red; `ASSET_RECOLOURS` pulls `heather_2`
  and `heather_3` to russet, like ling and crowberry mats.
- Lüneburger Heide needed no new imports: heather, juniper, birch and pine
  cover its heath, and the pack has no better dwarf-shrub or heath grass
  (wavy hair-grass, purple moor-grass) candidates.
- Not available in the pack: sand couch, sand sedge, creeping willow, grey
  hair-grass and lichen carpets. DUNE's moss stands in for lichen.
- Inner-dune woods use the existing oak, birch and pine (pine standing in for
  planted black/Corsican pine). See the profile note in
  `content/locations/waterleidingduinen.import.json`.

Captures: [dune](../reference/waterleidingduinen/dune.png),
[sand](../reference/waterleidingduinen/sand.png),
[arrival](../reference/waterleidingduinen/arrival.png).

## Wetland reeds and scrub bushes

Observed zones (phase Z6) reuse existing assets as `GroundCoverScatter`
categories: wetland reeds are the shoreline's `lake_reeds`, `lake_rushes` and
`reed_seedheads` (`FLOOR_ASSETS["reed"]`), and scrub bushes are `bush_1`–`3`
and `juniper` (`FLOOR_ASSETS["bush"]`), drawn static by `DebrisLayer`. No new
imports were needed.

## Meadow variety

Environment zones (phase Z4) add tall grass in lush meadow patches and
wild flowers in drifts (`MeadowPatches`, drawn by `GrassChunk` as extra mesh
sets). `grass_tall` (`Ones/SM_Grass_Simple_002`), `daisies`
(`Ones/SM_Grass_With_Wlowers_003`) and the `wildflower_*` colours
(`Ones/SM_Wild_Flower_*_01`) were chosen for their low triangle counts (20–26):
grass and flowers are instanced at grass density. Per-region flower sets are
in `NatureAssetCatalogue.meadow_flowers()`; with meadow variety on they
replace the dense `flowers` clump (832 triangles).

Audited but not used: `SM_Grass_02`/`03`, `SM_Grass_Shorts` and
`SM_Grass_Simple` (600–1,300 triangles); `SM_Grass_01` and
`Ones/SM_Grass_Simple_002B` (heavier and no better than `grass_tall`);
goldenrod and lavender (tall garden/field plants, maybe for a later farmland
or garden zone); the `_02` wild-flower variants (68 triangles, same look).

## Managed crops and trunk material fix

`wheat` (`Ones/SM_Wheat`, 18 triangles, ripe) is a managed field plant for
`SiteCropLayer` crop records of kind `wheat`, listed in
`NatureAssetCatalogue.CROP_ASSETS`. It is never used for wild scatter.

The source aspen prefab (both LODs) and the birch far LOD bind their two trunk
materials in the wrong order, so tiling bark UVs sampled the shared colour
atlas and rendered as rainbow faces. The converter now gives the
`Polygon_Texture*` atlas to the surface with compact UVs and the bark to the
surface whose UVs tile (`_fix_swapped_atlas`). A scan of every runtime asset
finds no remaining swaps. [Broadleaf trunks after the fix](../reference/nature_pack/broadleaf_trunks.png).

## Woodland structure (6 October 2026)

Woods used to be one storey of equal adults on an even jittered grid, with
lawn under the canopy. Profiles can now give them structure; every setting
defaults to the old output (placement fingerprints unchanged):

- **Regrowth** (`regrowth_cover`, `regrowth_spacing`, `regrowth_assets`):
  saplings and young trees, species slot 9, family `regrowth`, placed by
  TreePlacer over the same woodland field as the canopy families (it changes
  no acceptance, so zones and the terrain tint still agree). Default assets:
  `young_tree_1/4/5` (the pack's `SM_Small_Tree_0N_Green`, whose prefabs bind
  the autumn `Aspen_yellow` leaves; the converter swaps in `Aspen_green`), or
  small spruce in conifer-led woods. Drawn within 80 m only (shadows 40 m),
  never as impostors: from afar they are under the canopy.
- **Uneven stands**: `tree_scale_min/max`, `conifer_scale_min/max` and
  `tree_jitter` (offset within a grid cell: 0.7 = the old even spacing, 1.0 =
  pairs and gaps).
- **Species**: `broadleaf_assets` / `light_tree_assets` override the region's
  slot 0/1 assets (Buchenhain: maple-led as the beech stand-in).
- **Deadwood** (`woodland_deadwood`): debris deadwood becomes a cut log, a
  fallen tree with dead branches and a broken standing stump
  (`DEADWOOD_HEIGHTS`), instead of three cut logs.
- **Mantle** (`mantle_cover`, `mantle_width`, `mantle_spacing`,
  `low_shrub_assets`): the Waldmantel, a belt of bushes, low brambles and
  young trees on the open side of wood edges, `mantle_width` metres deep and
  stepping down from the wood (`EnvironmentZones.mantle()`: open ground with
  woodland within reach). Fields, roads and paths grow nothing; lawns,
  gardens, settlements, verges, farmland and wetland keep no mantle. It uses
  the growth mask, not an imported site's tree channel, which ends exactly
  where the mapped wood does. Placement only, not a zone. Buchenhain 0.8 /
  8 m, Black Forest 0.7 / 6 m, Lake Brienz 0.5 / 6 m, brambles `raspberry`
  and `bush_3` (`blackberry` renders pale). [Mantle](../reference/woodland/mantle.png):
  Buchenhain above, Black Forest below. Cost: about +0.4 ms.
- Imported but not yet placed: `broken_tree`, `dried_wood` (standing snag),
  `trunk_1/2`, `blackberry`.

| Location | Settings | Frame time (RTX 3060 Ti, High) |
| --- | --- | --- |
| Buchenhain | spacing 6.5 m, scale 0.65-1.4, jitter 1, maple/maple/oak, regrowth 0.35, deadwood, broadleaf floor grass_keep 0.12 | 10.3 -> 14.2 ms |
| Black Forest | conifer 0.6 / fir 0.25 at 6 m, scale 0.6-1.3, jitter 1, regrowth 0.3, deadwood | 5.3 -> 8.0 ms |
| Lake Brienz | scale 0.65-1.3, jitter 0.9, regrowth 0.3, deadwood | - |

[Before and after](../reference/woodland/structure_before_after.png) (pairs of
rows: Buchenhain, Black Forest, Lake Brienz; inside, inside, edge, above).
Denser spacing closed the canopies further but cost about twice the frame
time, so spacing was eased back. Narrow spruce crowns still show some floor
from above in the Black Forest.

The default bare-ground colour is now a neutral compacted earth (`#6b6152`,
was `#7a664a`, which rendered orange under warm sun), with slight patchiness
in the terrain shader.

## Tree grounding and bark wind

Trees are normalised with their lowest root tip at the ground, then sunk so
the root flare is buried. The default sink is 3% of height; models whose roots
join the trunk higher use `NatureMeshBuilder.TREE_ROOT_SINKS` (oak 13%, spruce
8%, birch_2 4.5%, aspen and tall spruce 3.5%), measured from gauge renders.
Before this the oak stood on about 1.5 m of arching roots and the spruce on its
buttress. [Tree bases](../reference/nature_pack/tree_bases.png).

A surface gets foliage wind and the alpha cut only when its material is
transparent **and** its texture has cut-out texels (`has_cutout`). The pack
flags the opaque birch and aspen bark (`Tree_01`/`Tree_02`, 0% transparent
texels) as alpha-scissor, which made those trunks sway and flutter like leaves.

## Rebuild pack assets

Run the converter with the download as the Godot project root, so its original
resource paths resolve. Supply an absolute output directory:

```powershell
godot --headless --path Downloads/POLY_NaturePack --script ../../tools/geo/import_nature_pack.gd -- --output="C:/Users/vlexa/Documents/Codex Projects/SpacesOS/assets/foliage/poly_nature"
godot --headless --path . --import
```

Optional `--assets=grass,grass_short,grass_simple` rebuilds only named assets.
The selected dense-scatter grass uses an 86-triangle source mesh, with a
20-triangle short/far mesh, rather than the pack's 1,200-triangle grass clumps.
Visible trees preserve source texture materials and use the existing runtime
impostor handover, wind, weather and distance tint. Existing coarse procedural
proxies provide shadows without alpha-testing every leaf in shadow cascades.
Tree meshes are more detailed than the former painted trees; this integration
does not establish a new hardware performance target.

## Verification

`scripts/test_nature_pack.gd` checks all assets, materials, bounds, wind data,
climate/latitude selection, serialization and layer integration. It runs in
`scripts/test_all.ps1`. The export smoke test verifies that all 42 assets are
present in the packaged project, together with the custom willow (43 total).

`godot --path . --script res://scripts/capture_nature_pack.gd` checks the actual
renderer and the 27-row impostor bake, then writes `reference/nature_pack/lineup.png`
and `impostors.png`. The labels show the legacy species slot and selected
source model, including the documented stand-ins.
