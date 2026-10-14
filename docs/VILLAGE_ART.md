# Village atmosphere and palette

This village pass is the foundation of the [project-wide art direction](ART_DIRECTION.md). This guide records its implementation, tuning and validation.

The village defaults to clear late-afternoon light at 16:00. Its original
camera, map and tree/rock scatter
remain intact. The art pass creates a cool forest frame around a warm clearing
and terracotta settlement. Weather and ambient motion continue while gameplay
is paused.

The village renders at full display resolution with 4× MSAA and smooth camera
movement. The earlier optional 640 by 360 pixel view was removed on 14 October
2026, and the art regression suite now measures at full resolution
(1280 by 720 in the test window). The before/after captures below predate the
removal; their pixel treatment is incidental.

| Before | After |
| --- | --- |
| ![Original afternoon](atmosphere-before.png) | ![Warm clearing and cool forest](atmosphere-after.png) |

Both captures use seed 73, the original camera, and the completed bread chain
at tick 800. The before capture uses the original 14:00 lighting; the after
uses the new default 16:00. The later sun is part of the art direction.

The subsequent [medieval building kit](MEDIEVAL_BUILDINGS.md) replaces the
primitive buildings with Blender-authored timber frames, stonework, roof
details and workshop fittings. Production buildings display their actual local
stock as sheaves, sacks, barrels, bread trays and timber bundles.

## Reference refinement

The supplied golden pastoral reference led to a second pass with brighter
direct palette response, fuller leaf coverage, connected amber crown highlights,
clay roof courses, stone wall feet, dark framed windows and richer grass/flower
groups. The camera, tree/rock roots, building silhouettes and paths are retained.

| First atmosphere pass | Reference refinement |
| --- | --- |
| ![First atmosphere pass](atmosphere-pass-1.png) | ![Reference refinement](atmosphere-after.png) |

Both of these captures use the same 16:00 clock, camera, seed and completed
bread chain. Village mesh vertex colours are explicitly converted from sRGB
to linear, with direct linear tonemapping replacing the muted AgX response.
Leaf cards keep one outward crown normal on both sides; this removes dark
peppering on sunlit crowns. Coarse texture mip coverage and stepped world-space
colour groups improve canopy mass without adding leaf geometry. Two grass
clusters share each original seeded tuft root, staying inside its tile, and
selected patches hold small flower groups. The ground mask shares the same
patch selection, so added pigment strokes leave quiet cells alone. Shoreline
accents and intermittent golden glints make the water less uniform.

The tree readability refinement lifts the cool side of each crown, introduces
subtle root-seeded differences between neighbouring trees and groups leaf
detail into broader patches. Those patches follow the crown as it moves,
avoiding texture shimmer. A continuous breeze and gentle crown rocking now
continue between stronger travelling gusts; trunks and shadows use the same
deformation, with the roots planted and rocks static.

## Implemented passes

1. **Light and contact.** A warm sun projects from the upper-left of the
   starting view. Reduced cool ambient fill separates lit and shaded walls.
   Ground contact masks, small root/rock shadows and dark eave strips anchor
   objects; larger directional shadows are lighter. Bloom is disabled.
2. **Palette and terrain.** Roofs become terracotta, plaster warm cream,
   paths dusty ochre and water turquoise. Canopy normals form broad light
   layers with yellow-green sunward edges and deep teal interiors. Seeded
   low-frequency colour regions and forest density shade the existing terrain
   mesh. About 79% of available meadow cells have no scattered detail; the
   remaining patches hold grass, occasional flowers, earth flecks and pebbles.
   Road margins darken adjacent ground and have sparse wear and grass intrusion.
   Golden crop rows retain their original stalk count and positions.
3. **Environmental time.** A single clock and travelling gust field drive
   grass, crops, tree crowns, dapples and drifting seeds. A weather-scaled wind
   clock drives broad gusts over a continuous breeze. Crown displacement scales
   with tree height and caps at 0.45 world units, about ten pixels at 1280 by
   720 and the initial zoom. Large cloud shadows share
   the existing sky field, but use a village-sized deck and five density bands.
   Seeds arrive singly, disappear at night, and use small opaque quads.
   Sparse water glints use short horizontal lines and stepped lifetimes.

Tree/rock contact, grass and ground accents are batched. Grass is substantially
less dense than before. The ground context is cached and refreshed on layout
changes. No simulation state or simulation RNG is used for environmental time.

## Tuning

Select `view/village_art.tres` in Godot's FileSystem dock and edit its exported
fields in the Inspector, then restart the running scene. Values are applied
when materials and terrain are built; this is an authoring profile, not a live
player settings panel. To author a second look, duplicate the resource and
assign it to the village view's `art_profile` property.

| Parameter | Default | Effect |
| --- | ---: | --- |
| `sun_warmth` | 0.72 | Blends the daylight sun toward golden cream |
| `sun_intensity` | 1.75 | Scales weather-aware directional energy |
| `shadow_tint` | `#637f91` | Cool daylight ambient fill |
| `ambient_fill` | 0.58 | Retains detail in forest and shaded walls |
| `exposure` | 1.0 | Direct palette exposure; preserve highlight headroom |
| `surface_detail` | 0.65 | Roof courses, wall foot stones and meadow strokes |
| `canopy_highlights` | 0.75 | Amber sunward crown layers |
| `canopy_fullness` | 0.65 | Coarse leaf coverage with fewer subpixel holes |
| `canopy_readability` | 0.65 | Broader leaf groups, clearer cool shade and differences between trees |
| `grass_patch_density` | 2 | Clusters around each original seeded grass root |
| `flower_patch_density` | 0.28 | Flower groups inside selected meadow patches |
| `ao_strength` | 0.75 | Ground masks, root contact and SSAO |
| `terrain_variation` | 0.65 | Broad warm/cool meadow colour regions |
| `forest_darkness` | 0.80 | Forest-floor and canopy palette separation |
| `cloud_shadow_opacity` | 0.22 | Moving brightness and temperature changes |
| `wind_strength` | 0.16 | Vegetation displacement and seed drift |
| `wind_speed` | 0.028 | Breeze and gust travel; weather also speeds the wind clock |
| `particle_density` | 0.18 | Frequency of occasional seed events |

Additional controls include sun azimuth, palette grade, cloud scale/speed,
wind direction/speed, meadow detail coverage, water glints and individual
grass/forest/roof/wall/path/crop/water colours. A zero motion strength or density
disables its effect. Keep the ambient fill high enough for forest detail before
increasing sun intensity. Tune the first pass, then terrain/forest, then motion.

Day/night, rain, mist, storm and the existing weather controls remain available.
The sun's azimuth is authored during daylight; its elevation follows the clock
and the imported moon takes over at night. Rotating the camera changes the
screen-relative direction of this fixed world light.

## Verification

```powershell
./tools/run_tests.ps1
./tools/run_tests.ps1 -View
./tools/run_tests.ps1 -Environment
./tools/run_tests.ps1 -Art
```

The art runner checks original camera and tree/rock positions, quiet meadow
coverage, grass carving and exact regrowth, broad changing cloud light, night
behaviour, unchanged paused simulation/RNG, and restart. It also compares
rendered crowns with only wind time advancing, verifies that zero breeze
freezes deformation and checks storm acceleration. It writes full-resolution
cloud/time and night captures plus `artifacts/atmosphere-after.png`.

Re-baselined at full resolution on 14 October 2026 with Godot 4.7.2 Forward+
on Windows/NVIDIA RTX 3060 Ti: 114 view and 1,936 art checks pass. At 1280 by
720 the palette check measures 248,135 golden pixels and zero clipped-white
pixels; four wind seconds change 182,612 crown-region pixels, and 40
environmental seconds of cloud drift change 52,692 clearing pixels. Each
threshold was scaled from its pixel-mode value by the same factor as its
measurement (about four times, matching the pixel area), so the margins are
unchanged.

## Generated hex-site refinement

New campaign sites now use the [hex village layout](HEX_VILLAGES.md), with region-specific conifers/birches/oaks, planted-root variation within resource cells, biome ground tints and masked soil sides. The full-site overview uses a quiet weather-aware backdrop while retaining sky lighting, cloud shadows and shared wind. Legacy authored sites keep their existing appearance. Use `tools/run_tests.ps1 -GeneratedSites` for paired overview/close-up GPU captures and boundary/state checks.
