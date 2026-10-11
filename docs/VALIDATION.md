# Milestone 1 validation

## Campaign menu and save/load

Validated on 11 October 2026 with Godot 4.7.2 Forward+ on Windows / RTX 3060 Ti.
The simulation suite passed with the campaign tests integrated. The final
focused persistence suite passes **21 checks**, the campaign input/render suite
passes **17 checks**, and the existing village and world-map suites pass
**108** and **30 checks**, respectively, all with zero failures.

Persistence checks round-trip both world-only campaigns and running villages.
They compare complete snapshots and continue both simulations for another 750
ticks, including in-flight deliveries, production, needs, money, disabled
workers, rotated construction and sapling growth. Checksum damage, unsupported
save/generator versions, changed game data and malformed metadata fail without
replacing the loaded campaign.

Real mouse input selects a founding hex, enters the first village, returns to
the map, loads the saved campaign and resumes its progress. Ocean sites disable
founding, and the campaign map ignores the debug seed-changing shortcut. The
scene transition removes the previous atmosphere before adding the next one,
preserving weather audio ownership. Menu captures at 1280 by 720 and 960 by 640
were visually inspected.

Reproduce persistence with `--headless --script tests/run_campaign_tests.gd`
or the full `tools/run_tests.ps1`; reproduce the campaign flow with
`tools/run_tests.ps1 -Campaign`. Screenshots are in
`artifacts/campaign-main-menu.png`, `campaign-world-selection.png`,
`campaign-first-village.png` and `campaign-menu-960.png`. Runs retain the host's
certificate-store diagnostic, with no script, shader or audio errors.

## Woodland and forestry

Validated on 11 October 2026 with Godot 4.7.2 Forward+ on Windows: **337
simulation, 108 view/input, 1,936 art, 1,914 environment and 7,728 building
checks pass**. The separate forestry render suite verifies stump replacement,
visible sapling growth, authored forester rotation, timber overlays and restart.

The default 100 × 100 map now has over 1,500 actual trees, a central 20 × 12
clearing and a continuous road from the western boundary. Simulation checks
cover finite timber, output capacity, workforce switches, protected clearings,
regrowth timing, shared tree claims, water/cliff/radius limits, atomic
construction, road deliveries and deterministic snapshots across tick batches.
The seed 73 chain promotes at tick 229 and first bakes bread at tick 353.

See [forestry notes and rendered map](FORESTRY.md). Render captures are saved as
`artifacts/forestry-map.png`, `forestry-saplings.png` and `forestry-grown.png`.

## Default map expansion: 100 × 100

Validated on 11 October 2026 with Godot 4.7.2 Forward+ on Windows: **187
simulation, 108 view/input and 709 art checks pass**, with zero failures. These
results include the larger default map and the earlier building rotation work.

The default site and new blank site packages hold 10,000 tiles in every map
layer. Placement succeeds beyond the former boundary and on buildable land in
the final row; footprints extending past the edge are rejected. Camera bounds
extend to (95, 95), and panning beyond the former 40 × 40 area is verified.
The coastline follows the map width, southern wilderness follows its height,
and the starter layout retains its original coordinates. An explicit 40 × 40
reference generator is still available.

The bread chain retains promotion at tick 229 and first bread at tick 357.
Rendering checks pass with 838 detailed cells out of 6,385 open meadow cells,
95,025 golden native pixels and no clipped-white pixels. The runs emit the
host's existing certificate-store diagnostic, with no script or shader errors.

## Earlier validation

Validated on 11 October 2026 with official Godot **4.7.2 stable**, Windows, NVIDIA RTX 3060 Ti / Forward+.

- Simulation: **367 checks, zero failures**. No scene or rendering is created by this runner. It covers the workers switch, house pantries stocked from the closest supply, happiness, and the economy: chain-derived prices, each stage paying the one before it, payroll shares, tax into the treasury, construction paid from the treasury, poverty, and conservation of money.
- GPU/input suite: **110 checks, zero failures**. The inspector's workers button is clicked through real input, and the inspectors and build card show prices, purses and treasury cost. Real viewport input covers the three-button HUD, build placement, rejection, inspectors, demolition, deposits, camera rotation, options, speed selection and restart. Smooth full-resolution rendering, antialiasing and smooth camera movement are verified as the startup default. Pixel-effect checks cover window resizing, input mapping and restoring exact native pixels. The display choice survives a village restart. It also confirms the palette material is absent and the old meshes use the environment-lit shader.
- Environment: **251 checks, zero failures**. Sparse grass is carved and restored deterministically; day/night, rain, wetness and weather wind remain functional.
- Village art: **273 checks, zero failures**. Original camera and vegetation positions are preserved, 144 of 679 open meadow cells have detail (21.2%), cloud shadows change broad clearing regions, and environmental time leaves paused simulation state unchanged. The tree refinement measures about 42,900 golden native pixels with zero clipped-white pixels. With lighting and clouds frozen, advancing wind four seconds changes about 23,900 crown-region pixels; zero breeze stops deformation, and storms accelerate the wind clock. See [the art guide](VILLAGE_ART.md) for tuning and before/after evidence.
- Starter house promotion: tick **229**, 22.9 simulated seconds (was 237 before house pantries; the well now supplies the house directly).
- First produced bread: tick **357**, 35.7 simulated seconds; zero initial wheat/flour/bread.
- Continued chain: the house is still Tier 2 and satisfied at the five-minute verification point. Only **2 bread** sit in storage, because storehouses now buy bread and most of it goes straight to the house.
- Conservation checks cover all six goods, including source reservations, in-flight cargo, input consumption, building demolition and recovery after road reconnection.
- Render assertions verify more than 32 world colors and exact 2-by-2 viewport scaling. The original palette lookup, outline pass and dithered toon light are inactive.

Reproduce with `tools/run_tests.ps1`, `tools/run_tests.ps1 -View`, and `tools/run_tests.ps1 -Environment`; pass `-Engine` to select a Godot 4.7.2 executable. The view suite writes `artifacts/view-tested.png`, `artifacts/native-world.png`, `artifacts/options-menu.png`, `artifacts/inspection-bakery.png` and `artifacts/inspection-storehouse.png`. Environment previews are in `artifacts/environment-day.png`, `environment-night.png`, and `environment-rain.png`. The earlier reviewed screenshot remains at `docs/first-bread.png`.

Linux execution is not claimed; this host has no WSL installation.

The first sandboxed runs emitted engine certificate-store and shader-cache access errors. The final installed-engine runs use normal engine access and complete without those errors. No game network services are used.
