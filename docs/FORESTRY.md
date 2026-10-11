# Woodland and forestry

The default 100 × 100 village starts in a central 20 × 12 clearing. A continuous
road reaches it from the western map edge and visibly extends beyond the map.
Oak and spruce groves, smaller clearings and occasional rocks fill the inland
area; the eastern coast remains open water. Seed 73 has over 1,500 actual trees.

![Woodland, clearings and the incoming road](forestry-map.png)

Both forestry buildings are available under **Build → Resources** from Tier 1.
They cost four logs each and work up to ten land steps from their footprint.
Workers can cross ramps and roads, but cannot cross water, cliffs, other
buildings or the village boundary. The inspector shows the current job,
workers, target tile and cycle progress.

| Building | Workers | Work |
| --- | --- | --- |
| Woodcutter | 2 | Cuts one mature tree every 6.5 simulated seconds, producing one log in its local output shelter. Carriers collect the log through the normal road network. |
| Forester | 1 | Plants one sapling every 5 simulated seconds. It becomes a mature, harvestable tree after 60 simulated seconds. |

Cutting removes the actual tree mesh, leaves a stump, clears its timber deposit
and changes the tile to buildable grass. A woodcutter with full local output,
stopped workers or no reachable mature trees stops harvesting. Two workers
cannot claim the same tree.

Foresters prefer harvested stumps, then vacant ground. They maintain the grove's
spacing, avoid roads and occupied tiles, and preserve the central settlement
clearing. Saplings visibly grow from small trees to full crowns. Growth
continues without workers; clearing a sapling for a road or building removes
it permanently. Trees do not spontaneously regenerate without planting.

![Forester nursery and surrounding woodland](forestry-saplings.png)

The forester uses a Blender-authored cottage with a green nursery canopy,
seedling beds, spade and tree sign. Its model supports the existing placement
rotation controls. Woodcutter stock displays continue to show actual logs.

Tree state, planting timers and work targets belong to the deterministic
simulation and its snapshots. Presentation reads them without consuming the
simulation RNG. Forestry has a separate revision counter, so cutting does not
invalidate the carriers' cached road routes. Ground colour, grass, shadows and
nearby leaf audio update when woodland changes.

Run `tools/run_tests.ps1` for simulation coverage and
`tools/run_tests.ps1 -Forestry` for rendered harvesting, sapling growth,
authored models and restart checks. Captures are written to `artifacts/`.
The explicit 40 × 40 archived map and the Terraces relief fixture remain
available; the new approach and clearing are part of the default site.
