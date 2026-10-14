# World map art

Follow the [project-wide art direction](ART_DIRECTION.md), based on the village's palette, materials and motion. The current map pass applies that direction with village palette anchors, 16:00 light, fuller canopies, broader mountain ridges and shared environmental motion.

The map has two presentation stages. **Separate tiles** gives each hex a small landscape composition with sculpted ground, biome colours, oak/birch/conifer groves, meadow accents, wetland reeds, rocks, sandy banks and layered earth sides. **Linked scenes**, enabled by default, carries compatible relief and forest patterns across adjacent hexes. Fine dark borders and elevation steps keep the hexes visible.

Press **L** on the map to compare the stages. Camera position, zoom and the selected site survive the switch. The mouse wheel now zooms down to 8 world units for inspecting individual tiles. The standalone map also accepts `-- --unlinked`.

The map also accepts the village atmosphere controls: **[ / ]** change the hour, **0** toggles the day cycle, and **5 / 6 / 7 / 8 / 9** select storm, mist, clear, cloudy and rain. **- / =** adjust weather intensity.

![Linked world](world-map-art-linked.png)

![Tile details](world-map-art-close.png)

![Separate tile stage](world-map-art-tiles.png)

## Village direction refinement

The meadow now derives its warm and shaded colours from the village profile, with broad green/gold regions and cooler grove floors. Biomes retain a secondary tint. Coastlines use narrower sand and local water shelves rather than a pale ring of whole ocean hexes; riverbanks are also finer.

Tree crowns use the village's canopy fullness, highlight and shade controls. Grove density follows a broader shared field, and small meadow accents occupy selected patches. Source leaf textures retain their shape while crown colour is grouped into larger, stable highlights. Long warped ridges replace dense mountain noise, with fewer scattered boulders and pale snow restricted to higher crests.

Vegetation samples the village's shared wind field at each root. Smooth height-weighted bending moves trunks, crowns and their shadows together, while instance positions and roots stay fixed. Motion decreases at overview zoom and becomes easier to see when inspecting tiles. Water uses sparse short glints, driven by presentation time and suppressed at night. Terrain, foliage and water share the village cloud field; wet weather also darkens foliage and ground.

| Previous map pass | Village direction pass |
| --- | --- |
| ![Previous map](world-map-direction-before.png) | ![Refined map](world-map-art-linked.png) |

The previous pass used 14:00 light; the current pass uses the village's 16:00 baseline. The light change is part of the refinement.

![Eight-second motion preview at tile inspection zoom](world-map-art-motion.webp)

The preview is a lossless animated WebP. Open it in an animated-WebP-capable viewer or browser if the Markdown preview shows only its first frame.

## Direction and tuning

Edit [world_map_art.tres](../view/world_map/world_map_art.tres) for linked mode, relief strength, border width, foliage density, meadow detail coverage, shore width, wind scale, glints and water/shore/earth colours. The exported schema lives in `world_map_art.gd`; biome tint and species choices live in `world_map_scenery.gd`. The view's `art_profile` supplies the village palette, light and canopy settings.

The imported `assets/foliage/poly_nature` models retain their authored textures. A map-specific foliage shader adapts village crown lighting and shared wind to miniature scale. Trees, ground cover and rocks share one MultiMesh batch per asset; cached meshes survive seed and art-mode changes. Terrain and composition remain editable Godot code.

## Linking contract

- Adjacent land tiles link relief when they have the same elevation band and terrain family (rock, hill or lowland). Shared edges evaluate the same seeded world-space height field; three-way corners rise only when all three tiles are compatible. Other edges taper to their prism height, preserving the stepped map.
- Linked groves use a shared world-space distribution. Each plant root belongs to one hex, avoiding duplicates along edges. Separate mode leaves a planting margin and gives each tile its own terrain and grove pattern.
- River curves retain their shared edge endpoints and straighten near the boundary. Their widths, waterfalls and drainage come from world data. Connected lakes at the same elevation join into larger water bodies in linked mode.
- The fine border follows relief, as do hover/selection rings. Picking samples the new height field. Nature meshes are decorative; clicking a tree still chooses its terrain tile.
- These settings never alter the simulation, generation, deposits, campaign saves or settlement rules.

## Validation

Run the GPU suite with `tools/run_tests.ps1 -WorldMap`. It checks two seeds, instanced scenery, shared-edge heights, river endpoints, art-mode switching, camera/selection preservation, world-state preservation, hover picking and the village return flow. It also compares rendered images with only wind time advancing, checks fixed instance transforms and zero-wind freezing, and verifies weather and hour controls, storm response and night cloud behaviour. It writes review images and 32 motion frames to `artifacts/`.

Run `py tools/build_world_map_motion.py` after the suite to encode the motion frames as the animated WebP above (requires Pillow). Campaign rendering/input checks remain available with `-Campaign`.

Verified on Godot 4.7.2 / Forward+ / NVIDIA RTX 3060 Ti: **124 world-map checks and 17 campaign-view checks passed**. The engine reported its existing root-certificate-store diagnostic; rendering and interaction checks completed successfully.

## Campaign and village integration

The map and [generated hex villages](HEX_VILLAGES.md) now share the authoritative terrain layout for rivers, lakes, coasts, groves, meadow openings and relief. Campaign views show seven-hex reach outlines, blocked-site hatches, village history and the latest marker at each location. Press **F** to toggle settleability and **P** to print the hovered descriptor. Map camera, selection, linked mode, weather and wind survive campaign view transitions. The [world-map plan](PLAN-world-map.md) records completion of stages A through E and the follow-up art pass.
