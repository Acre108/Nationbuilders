# Hearthlands art direction

**The village art is the visual foundation for the whole project.** Aim for a warm pastoral world: golden clearings, cool woodland, terracotta roofs, cream plaster, weathered natural materials and gentle environmental motion. The village and world map should feel like views of the same place at different scales.

This document sets the direction for new assets and future art passes. [Village art](VILLAGE_ART.md), [medieval buildings](MEDIEVAL_BUILDINGS.md) and [world map art](WORLD_MAP_ART.md) describe their implementations and controls. Where an implementation differs from this guide, treat the difference as work remaining toward the target.

## Visual foundation

![Village lighting, palette and landscape reference](atmosphere-after.png)

Use this village image for the relationship between light, shade, ground, foliage and water. Use the later building capture below for architectural materials and detail. Both are historical captures; their pixel treatment is incidental. The project targets smooth rendering at full display resolution, with antialiasing and stable detail during camera movement.

![Architectural materials and settlement scale](medieval-village-close.png)

At a glance, the scene should read as broad meadow and woodland shapes, then a settlement or landscape landmark, then small material details. Let quiet ground surround concentrated detail. Light should reveal forms, and movement should make the landscape feel alive while leaving gameplay easy to read.

## Palette and light

The palette is built around warm sunlight and cool shade. Meadows lean yellow-green in light and softer green in shade. Forest interiors are deep teal-green with enough fill to retain canopy and trunk detail. Terracotta, cream and ochre distinguish human activity from the landscape; turquoise provides a cool water accent.

These are the authored **sRGB base colours** from [the village art profile](../view/village_art_profile.gd). Lighting and grading determine their rendered appearance; they are not colours sampled from the reference image.

| Role | Base colour | Direction |
| --- | --- | --- |
| Sunlit grass | `#bbc16a` | Golden yellow-green; use in broad lit regions |
| Shaded grass | `#698954` | Muted green; keep the clearing readable |
| Forest floor | `#24463e` | Deep cool green; reserve for woodland interiors |
| Roof clay | `#ad5937` | Earthy terracotta with warm course highlights |
| Plaster | `#e4cfa1` | Warm cream with soft variation and darker foundations |
| Paths and dry soil | `#c7aa7b` | Dusty ochre, embedded into surrounding ground |
| Crops | `#dfb543` | Golden wheat; concentrate around cultivation |
| Water | `#398fa4` | Turquoise, with darker depth and restrained pale glints |
| Daylight shadow fill | `#637f91` | Cool blue-grey illumination; this is a lighting colour |

Supporting timber, stone, earth and slate colours should stay muted and sit comfortably beside these anchors. Put flower colours, flags and goods in small, purposeful accents. Biomes may change the balance of green, earth, moisture and snow while keeping the same warm-light/cool-shade relationship.

Judge colour under the baseline clear **16:00** light before checking other weather. The initial village view receives sunlight from the upper-left; the light is fixed in world space, so it changes screen direction when the camera rotates. Preserve shaded detail, strong material identity and highlight headroom. Bloom is disabled in the baseline.

The current [village profile](../view/village_art.tres) is the starting point for tuning: sun warmth **0.72**, sun intensity **1.75**, ambient fill **0.58**, exposure **1.0**, palette grade **0.32** and contact strength **0.75**. These are existing authoring values. At other scales, match their visible relationships before copying individual effect amplitudes.

## Materials and form

Materials should have broad colour structure, restrained surface texture and clear contact with the ground. Model the parts that affect silhouette and recognition; use grouped surface detail for the rest. Detail must remain stable as the camera pans and zooms.

| Material | Treatment | What should read at gameplay distance |
| --- | --- | --- |
| Meadow and soil | Broad warm/cool patches, sparse clustered grass and flowers, worn path margins | Clearings and routes before individual blades |
| Leaves | Full canopy masses, connected yellow-green/amber highlights, cool interiors, subtle differences between trees | Crown shape and grove structure; suppress tiny leaf holes and sparkle |
| Bark and timber | Dark warm browns, visible framing, a few broad grain or plank breaks | Tree trunks and structural beams anchored into the scene |
| Clay roofs | Terracotta planes, readable courses, shaded eaves, modest tile variation | Roof pitch and warm highlights before individual tiles |
| Plaster | Cream walls, quiet mottling, darker stone feet, recessed openings | Lit wall planes and dark windows |
| Stone and rock | Muted earth/grey planes, broad facets and crevices, grounded bases | Ridge, outcrop or foundation shape before cracks |
| Slate and metal | Cool dark slate; small iron fittings with restrained reflection | A distinct roof or fitting without bright glitter |
| Water | Broad turquoise colour, subdued surface variation, occasional short pale glints | Shoreline, flow and depth; keep the surface calm between glints |
| Goods and props | Simple recognisable bundles, sacks, barrels, trays and crates | Resource identity and actual stock changes |

Keep most surfaces matte. For new materials, roughness around **0.85–1.0** is a useful starting range for earth, foliage and buildings; tune water separately for a softer reflective response. Imported textures are a starting point: adjust their palette, contrast, leaf coverage and detail scale to match the village.

Architecture should feel handmade and practical: timber frames, steep clay or slate roofs, stone foundations, shutters, framed windows, plank doors and workshop fittings. Distinguish building functions through silhouette and a few meaningful features. Ground contact, dark eaves and recessed openings give depth without covering every edge in a heavy outline.

Rocky terrain needs a readable large form with supporting outcrops. Keep snow on high crests and shelves. Use broader, quieter stone masses where dense small facets compete with the surrounding meadow and forest.

## Landscape composition and scale

In villages, woodland frames warm usable clearings. Paths, roof shapes and crop rows organise the settlement. Meadow detail sits in irregular patches, leaving most ground quiet; the village's `meadow_detail_cover = 0.16` is the authoring baseline. Flowers cluster in selected patches. Small roots, grass and stones should support the composition without hiding routes, footprints or stock.

On the world map, each tile is a miniature landscape. Keep the same meadow, forest, water and earth palette relationships, with broader detail suited to the camera distance. Thin hex borders and elevation steps remain visible beneath the scenery. Hover and selection outlines must clearly identify the full tile.

Linked tiles form larger compositions: a grove continues into its neighbour, ridges establish a chain, rivers retain continuous flow and compatible lakes form a larger water body. Shared patterns should cross tile borders without making every tile's centre a separate focal point. Preserve enough quiet space and edge visibility to count and select hexes.

| Element | Village treatment | World map treatment |
| --- | --- | --- |
| Ground | Broad colour regions with local path wear and clustered accents | Larger patches carried across linked tiles; sparse readable accents |
| Woodland | Full crowns, varied roots and clearings, shaded forest floor | Recognisable grove masses with fewer visible detail layers |
| Rock | Outcrops and relief that support the site | Broad ridge silhouettes; simplify small facets at overview zoom |
| Water | Shore detail, flowing falls and occasional glints | Clear river paths and lake shapes; restrained overview motion |
| Human activity | Buildings and goods read directly from simulation | A clear settlement marker, consistent with the map's scale |

Menus, map panels and overlays should use the same restrained earth/forest family: dark muted backgrounds, warm cream text and limited accent colour for selection and status. Maintain legible contrast. Scenery must leave room for the information needed to choose a site or understand a building.

## Motion

Environmental motion is continuous, sparse and coherent. A gentle breeze persists between broad travelling gusts. Plants respond according to size and stiffness; trees and grasses in one area should share the direction and timing of the passing wind.

| Element | Motion direction | Scale and readability rule |
| --- | --- | --- |
| Trees | Slow crown rocking, stronger gust response, restrained leaf flutter | Roots stay planted; trunk, crown and shadow move together |
| Grass and crops | Light continuous sway with gusts moving through patches | Small details move within a larger coherent wave |
| Cloud light | Broad, slow brightness and temperature changes | Shadows cross terrain and tile boundaries continuously |
| Seeds and motes | Occasional individual drifting accents | Long quiet intervals; daylight visibility; reduce at overview scale |
| Water | Gentle surface motion and intermittent short glints; falls follow gravity | Avoid repeated bright patterns or shimmer during camera movement |
| Machinery | Clear purposeful movement, such as the mill's rotating sails | Operational animation follows production state |

The village baseline uses wind strength **0.16**, speed **0.028**, direction **(1.0, 0.35)**, cloud shadow opacity **0.22**, cloud speed **0.0015**, particle density **0.18** and water glints **0.65**. Use the shared presentation clocks and weather response. Environmental motion continues while gameplay is paused, and never advances simulation state or its RNG. Machinery keeps its own operational rules.

At world-map scale, reduce displacement and fine flutter until tile silhouettes and selection stay stable. Judge motion in screen space: a slight visible crown drift at inspection zoom, with subdued movement at overview zoom. Share wind phase across linked tiles. Reserve stronger motion for gusts and storms; keep weather readable through changes in light, wetness and wind together.

Zero vegetation wind strength must freeze deformation. Rocks and building foundations remain fixed. Anchor animated patterns to their objects or the world so camera movement does not make textures swim.

## Applying the direction to the world map

The [world-map refinement](WORLD_MAP_ART.md) now applies this direction: village palette anchors and 16:00 light, broader green/gold ground regions, fuller warm/cool crowns, narrower shorelines, linked mountain ridges, coherent root-anchored breeze and sparse water glints. Motion reduces at overview zoom. The map accepts the village hour and weather controls, and its GPU checks cover visible motion, zero-wind freezing and weather response.

The map uses fewer surface detail layers than the village to suit its miniature scale. Continue reviewing biome identity, canopy grouping, ridge silhouettes and hex legibility against the village references as new assets and scenes are added. Implementation notes and still/moving review captures live in the map guide.

## Reviewing an art pass

Compare the new scene with the village references at overview and inspection zoom, under the same time and weather. Review a short moving capture as well as still images. Confirm that:

- Warm light and cool shade separate forms, with readable forests and unclipped highlights.
- Materials retain their identity; broad canopy and terrain shapes read before small texture detail.
- Quiet ground balances the detail clusters, and paths, footprints, goods and hex boundaries remain legible.
- Panning, zooming and rotation preserve stable leaf coverage, textures, shadows and selection markers.
- Breezes and gusts feel connected across vegetation and linked tiles; roots and foundations stay planted.
- Clear weather, night and storm preserve the same material language while changing atmosphere.
- Presentation changes preserve simulation state, RNG, saves and input behaviour.

Use the relevant existing suites after a runtime art change: `tools/run_tests.ps1 -Art`, `-Buildings`, `-WorldMap` and `-Campaign`. Run the simulation suite when a change could affect simulation behaviour. Keep the implementation guides and comparison captures current as the look develops.
