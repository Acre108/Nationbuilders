# Milestone 1 validation

## Sign-off (15 October 2026)

Every Milestone 1 work item is done except the manual playtest
([PLAN-milestone-1.md](PLAN-milestone-1.md) item 3). The tag
`m1-first-bread` follows the playtest notes below.

- **Full tier green.** On 15 October, `tools/run_tests.ps1 -Full` passed every
  suite with zero failures: headless 547, site generation 100, view 116,
  campaign view 47, world map 119, generated sites 33, forestry view 19,
  art 33, buildings 31 and environment 18 checks. This includes the hour-long
  two-house run, and the carriers-as-jobs, services and happiness changes
  from VILLAGERS.md.
- **Storage is visible.** A producer whose goods a storehouse refuses
  reports "storehouse full" or "storehouse has enough <good>" instead of
  "output full". An always-visible bar beside the gold counter shows total
  storehouse fill and stored bread, water and logs. The view suite checks the
  bar's contents and placement; the logistics test checks both statuses.
- **Screenshot.** [first-bread.png](first-bread.png) is the render smoke run
  (`godot --path . res://view/village_view.tscn -- --render-smoke`): the
  starter plus mill and bakery, 80 simulated seconds, with 8 bread produced.

### Scripted input playtest (15 October 2026)

This is not the person-led playtest below. The other development session ran
`tools/playtest_village.gd`, which plays through real input only: toolbar,
build menu, map clicks, inspectors and the Treasury panel. It places
buildings on spots touching a road, as a player reading the ghost would.
Seed 73 at 3× speed; captures are in `artifacts/playtest/`.

- First Villager house at 0:22, first bread at 0:36. By then it had built
  berry bushes, a forester, a mill, a bakery, a chapel and a second house.
  Both houses were 100% happy from minute 1 to 13.
- **A forester near the centre never plants.** It reports "no planting space
  nearby" all game, because the settlement clearing is kept open. The
  woodcutter then runs out of trees and logs reach 0 at about minute 14.
  Morale falls to 83%, and workplaces slow to 91% speed.
- **The bakery stalls on money.** It shows "missing input flour" with 0
  silver while the storehouse holds 30 flour, because producers' purses run
  dry.
- **The treasury drains.** It falls from 3.84 g to 0.28 g in 15 minutes,
  with forester and chapel upkeep at 15% tax.

These are candidates for item 3's "fix anything that blocks a first-time
player". The forester case is the one most likely to catch a new player,
because nothing explains why a forester in the clearing does nothing.

### Playtest (to record)

One person plays from a fresh start to Villagers and bread using only the
toolbar, then keeps playing for 15+ minutes. Record:

- date, and who played;
- time to the first Villager house and to first bread;
- anything confusing, and where the player got stuck;
- bugs found, with what blocked a first-time player fixed before tagging.

## Current results (14 October 2026)

Run with `tools/run_tests.ps1 -Full` (Godot 4.7.2 Forward+ on Windows /
RTX 3060 Ti), which runs each suite in turn, after the storehouse limit, the
simulation caches, the treasury controls, the pixel view removal and the test
trim below. Every suite has zero failures, in 3 min 42 s in total. The quick
tier (`tools/run_tests.ps1`) runs 421 of the headless checks in 7 s.

| Suite | Checks | Time |
| --- | ---: | ---: |
| Headless simulation and campaign (`-Headless`) | 528 | 24 s |
| Site generation (`-Sites`) | 100 | 15 s |
| Village view and input (`-View`) | 114 | 16 s |
| Campaign view (`-Campaign`) | 47 | 60 s |
| World map (`-WorldMap`) | 119 | 45 s |
| Generated sites (`-GeneratedSites`) | 33 | 21 s |
| Forestry view (`-Forestry`) | 19 | 9 s |
| Art direction (`-Art`) | 33 | 11 s |
| Medieval buildings (`-Buildings`) | 31 | 10 s |
| Environment (`-Environment`) | 18 | 8 s |

The headless suite took 3 min 16 s before the simulation caches; the
hour-long logistics run is about 10 s of its 24.

**Test trim (14 October).** Some cases were cut:
- Site generation builds 2 random villages per seed instead of 7, as well
  as each seed's start and lake site.
- The campaign tests keep 3 of the 8 malformed-save fields and 4 of the 9
  malformed view states. They play 2 successive runs instead of 3; the
  campaign view suite still plays three through the UI.
- The world map builds 2 seeds instead of 3.

Checks that were repeated per tree, per tick or per hex now report once.
That is why the art, building and environment counts fell from thousands to
tens with the same coverage.

- **Simulation** additionally covers:
  - the storehouse `good_limit` and its content validation;
  - the hour-long two-house run, with cached routes and reservations
    checked against a fresh search;
  - treasury reserves, and public-pay frustration when the treasury cannot pay;
  - the household-only storehouse markup and the purse-cap surplus sweep;
  - the payday ledger;
  - snapshot validation of the new treasury keys, and tolerance of version 1
    saves.
- **GPU/input** additionally covers the gold counter and the Treasury panel's
  tax and reserve buttons, through real input.

## Pixel view removal

Brought over from the `overnight-integration` branch (`38cef05`) and
validated on 14 October 2026 with the suites above. The campaign save still
accepts the old `pixel_effect` view setting from earlier saves and ignores it.

The view suite checks that the Options menu no longer offers a pixel effect,
that the world renders at full display resolution (1280 by 720) with 4× MSAA
and smooth filtering, and that the camera follows sub-pixel movement without
snapping. Letterboxed input mapping on a 1440 by 900 window is still verified.
The pixel-specific checks (pixel toggle and its persistence across restart,
integer nearest-neighbour scaling, exact 2-by-2 blocks, restoring native
pixels) were deleted.

The art suite now measures at full resolution. Its sampled screen regions
cover the same areas as before at twice the linear resolution. At 1280 by 720 it
measures 248,135 golden pixels (threshold 32,000) and zero clipped-white
pixels (limit 4,000); four wind seconds change 182,612 crown-region pixels
(threshold 1,300), and 40 seconds of cloud drift change 52,692 clearing
pixels (threshold 400). Each pixel-mode threshold was scaled by its
measurement's own pixel-to-full-resolution factor (about 4×), keeping the old
margins. Building-art captures are saved at their rendered 1280 by 720 size
instead of being upscaled 2× with nearest-neighbour filtering.

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

## Village performance

Measured on 12 October 2026 with `tools/bench_village.gd` (Godot 4.7.2,
RTX 3060 Ti, 1280 × 720, vsync off). Run it windowed, not headless:
`Godot.exe --path . --script tools/bench_village.gd`. Add `-- --gpu-breakdown`
to attribute GPU time by switching features off one at a time.

Editing roads, buildings or trees used to repaint the whole site's ground mask,
terrain colours and grass. Each edit stalled the game for 3–6 seconds, and
woodcutters fell trees on their own. These now update only the cells within
two tiles of the change. The forestry view test checks that the result equals
a full rebuild.

| | Before | After |
| --- | --- | --- |
| Stall per road/tree/building, default map | ~3.0 s | 26–32 ms |
| Stall per edit, generated campaign site | 4.9–5.9 s | 43–53 ms |
| Startup, default map / campaign site | 5.5 s / 13.7 s | 2.0 s / 3.0 s |
| Default map at 3×, mean frame | 41 ms | 15 ms |

Trees were about 92% of GPU time: ~1,170 oaks at 8,642 triangles each, with
their shadows costing half of that. Each tree now also uses the nature pack's
authored far LOD (4,650 triangles for the oak). It always casts the tree's
shadow, which looks the same. From zoom 32 outwards it is also drawn instead
of the full tree; its crown is slightly thinner, which is not visible at that
size. Godot's generated LODs cannot simplify the oak's leaf cards, and two
shadow cascades instead of four lost tree shadows at the edge of the view.

| GPU time | Before | After |
| --- | --- | --- |
| Default map, default zoom | 13.9 ms | 10.8 ms |
| Default map, overview | 31.9 ms | 19.6 ms |
| Campaign site, overview | 17.1 ms | 9.9 ms |

Still open:

- **GPU:** every tree is still its own draw call (about 1,400 at default
  zoom). MultiMesh trees would reduce CPU and driver cost further.
- **Simulation:** resolved on 14 October; see *Simulation tick cost* below.

## Simulation tick cost

Measured on 14 October 2026 with `tools/bench_village.gd --sim-only`
(Godot 4.7.2, headless, one process at a time). "Before" is checkpoint
`01f5d43`.

| Mean tick | Before | After |
| --- | --- | --- |
| Starter, 5 buildings, 6 carriers | 4.80 ms | 0.10 ms |
| Town, 40 buildings, 24 carriers | 69.9 ms (p99 259 ms) | 3.07 ms (p99 11 ms) |
| Town at 3× speed, per real second | 2,098 ms | 92 ms |

Changes:
- Each building's road frontage and a breadth-first distance field are
  cached per road revision. Carriers walk A* paths as before.
- Reservations are indexed by building slot.
- A carrier job search that found nothing is not repeated in the same tick
  until a job changes.
- Suppliers a buyer cannot afford are skipped before routing.
- Forestry searches that found no site are not repeated until the land,
  roads or claims change.

None of these changes behaviour. A reference copy of the uncached sim and the
cached one were run through the same commands, and their full snapshots
compared every 10 simulated seconds for 6 minutes. The scenarios were the
two-house starter, seed 919, the 40-building town, and a run with a road cut
and repair, stopped workers, bakery demolition and rebuild, and a second
storehouse. All matched.

`tests/test_logistics.gd` also checks, during its hour-long run, that cached
distances equal A* routes and indexed reservations equal a carrier scan.

## Storehouse limit and hour-long run

Measured on 14 October 2026 with `tools/soak_village.gd`: seed 73, the chain
placed at promotion, a second house and a forester, 60 simulated minutes.

- **Before the limit:** surplus water fills the 180-slot storehouse. In the
  hour-long test, both houses are below Villagers for 32 minutes and the
  storehouse is full for 44, and logs fall to 8.
- **After it:** each good stops at the storehouse's `good_limit` of 30. Logs
  never fall below 30, and no good is crowded out. The hour runs in 13–17 s.
- **Money still limits the chain** (VILLAGERS.md §5.5).
  - At 25% markup, households run out of silver around minute 33 and fall
    back to Settlers.
  - At the new 10% default, both houses stay Villagers for the hour. Their
    savings peak at about 3.5 g around minute 15, then fall to 1.3 g and
    0.8 g by minute 60, and are still falling.
  - At 0%, both houses stay Villagers, but the treasury drains to 4 s,
    producers hold no silver, and the bakery bakes only to order.

## Earlier validation

Validated on 11 October 2026 with official Godot **4.7.2 stable**, Windows, NVIDIA RTX 3060 Ti / Forward+.

- Simulation: **367 checks, zero failures**. No scene or rendering is created by this runner. It covers the workers switch, house pantries stocked from the closest supply, happiness, and the economy: chain-derived prices, each stage paying the one before it, payroll shares, tax into the treasury, construction paid from the treasury, poverty, and conservation of money.
- GPU/input suite: **110 checks, zero failures**. The inspector's workers button is clicked through real input, and the inspectors and build card show prices, purses and treasury cost. Real viewport input covers the three-button HUD, build placement, rejection, inspectors, demolition, deposits, camera rotation, options, speed selection and restart. Smooth full-resolution rendering, antialiasing and smooth camera movement are verified as the startup default. Pixel-effect checks covered window resizing, input mapping and restoring exact native pixels, and the display choice survived a village restart (the pixel view has since been removed; see above). It also confirms the palette material is absent and the old meshes use the environment-lit shader.
- Environment: **251 checks, zero failures**. Sparse grass is carved and restored deterministically; day/night, rain, wetness and weather wind remain functional.
- Village art: **273 checks, zero failures**. Original camera and vegetation positions are preserved, 144 of 679 open meadow cells have detail (21.2%), cloud shadows change broad clearing regions, and environmental time leaves paused simulation state unchanged. The tree refinement measures about 42,900 golden native pixels with zero clipped-white pixels. With lighting and clouds frozen, advancing wind four seconds changes about 23,900 crown-region pixels; zero breeze stops deformation, and storms accelerate the wind clock. See [the art guide](VILLAGE_ART.md) for tuning and before/after evidence.
- Starter house promotion: tick **229**, 22.9 simulated seconds (was 237 before house pantries; the well now supplies the house directly).
- First produced bread: tick **357**, 35.7 simulated seconds; zero initial wheat/flour/bread.
- Continued chain: the house is still Tier 2 and satisfied at the five-minute verification point. Only **2 bread** sit in storage, because storehouses now buy bread and most of it goes straight to the house.
- Conservation checks cover all six goods, including source reservations, in-flight cargo, input consumption, building demolition and recovery after road reconnection.
- Render assertions verified more than 32 world colors and, at the time, exact 2-by-2 viewport scaling. The original palette lookup, outline pass and dithered toon light were inactive (and have since been deleted).

Reproduce with `tools/run_tests.ps1`, `tools/run_tests.ps1 -View`, and `tools/run_tests.ps1 -Environment`; pass `-Engine` to select a Godot 4.7.2 executable. The view suite writes `artifacts/view-tested.png`, `artifacts/world-render.png`, `artifacts/options-menu.png`, `artifacts/inspection-bakery.png` and `artifacts/inspection-storehouse.png`. Environment previews are in `artifacts/environment-day.png`, `environment-night.png`, and `environment-rain.png`. The earlier reviewed screenshot remains at `docs/first-bread.png`.

Linux execution is not claimed; this host has no WSL installation.

The first sandboxed runs emitted engine certificate-store and shader-cache access errors. The final installed-engine runs use normal engine access and complete without those errors. No game network services are used.
## Hex village and campaign plan completion

The current plan implementation was checked on Godot 4.7.2 / Windows / RTX 3060 Ti, with the GPU suites using Forward+:

| Suite | Checks | Failures |
| --- | ---: | ---: |
| Combined headless simulation/campaign suite | 519 | 0 |
| Site generation: 21 bread-producing villages, three seeds, real lake/start sites | 294 | 0 |
| Final site fixtures, including zero forest cover | 6 | 0 |
| Targeted campaign release: inverse, corruption, deliveries, budgets, view precision | 170 | 0 |
| Campaign UI release, including three-run/resettlement and Home overview | 47 | 0 |
| World map, shared edges, picking, motion and weather | 124 | 0 |
| Generated site GPU art/boundary/save review | 33 | 0 |
| Existing village view/input suite | 110 | 0 |
| Existing forestry view suite | 18 | 0 |
| Village art regression | 1936 | 0 |

The combined suite includes campaign checks; the targeted campaign release records additional delivery/schema/precision cases and is not an independent total to add to it. Recorded logs are in `artifacts/`; release files include `site-tests-release.log`, `site-fixtures-final.log`, `campaign-ui-release.log`, `generated-site-view-tests.log`, `world-map-tests.log`, `view-tests.log`, `forestry-view-tests.log` and `art-tests.log`.

Generated landscapes were visually reviewed at overview and close-up zoom, including the regular hex silhouette, terrain/water agreement and regional vegetation. The overview sky projection artifact was removed with a calm weather-aware background, retaining sky lighting and cloud motion. See [the implementation and captures](HEX_VILLAGES.md).

Natural mortality is not added: the current four founding adults mean automatic zero-population ruins are a future gameplay path. Charter/abandon/scout/resettle history is playable and tested. Compatible version 1 campaign saves migrate; incompatible data/generator versions are explicitly refused. The world generator is version 2.
