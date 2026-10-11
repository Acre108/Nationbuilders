# Lighting

The building editor, standalone building visits and outdoor locations share
one lighting policy. This document describes what is in place now. The
lighting plan was delivered in stages 1–6 on 5 October 2026, with warm, night
and street-light passes on 6 October. Its stage reports were folded into this
document on 7 October 2026 and remain in git history, along with the full
before/after review tables.

## Shared policy and ownership

[`LightingSettings`](../lighting/lighting_settings.gd) creates a new Environment
and Sky per viewport. `BuildingRuntime` uses it for editor and visit
construction. `LocationRuntime` uses it on each destination entry, including
when atmosphere is disabled. `FoliageLocation` delegates quality application to
the same helper. Atmosphere owns time, weather and the sun's direction, colour
and energy. It applies ambient through the helper on each tick, keeping the
selected exposure and SSAO quality. Scene entry also restores the
renderer-global directional shadow filter.

**Display.** AgX tone mapping at exposure 1.0 (white 12, contrast 1.15), with
subtle bloom on HDR highlights only. The display is identical at every quality
level. AgX replaced the original ACES 0.9 in the warm pass, because it holds
shadow detail and does not push highlights towards yellow-white.

**Fill.** Ambient is a warm colour (`#dccdb0`, about 0.52 effective by day)
mixed with 25% sky radiance. The visible sky and reflections remain. With
atmosphere running, the fill is the model's ambient intensity scaled by a
daylight blend (night 0.22, day 0.7), plus the lightning lift. The zone
ambient scale is already part of the model, so there is no extra indoor
multiplier. The sun scale is 0.9. The sun warms from 50° elevation down and
warms the fill with it. Soul warmth tints up to 30%.

**Night.** A full moon rides opposite the sun. Once the sun is 6° below the
horizon, the moon takes over the single directional light and its shadow pass.
It is a cool `#8ea6d6` at strength 0.12 (before the sun scale) and dims under
cloud like the sun. The sky draws it as a small disc of fixed brightness. Fill
and sky daylight run down to -10° while direct sun stops at the horizon. The
fill leans dusky rose in twilight, and the night fill is `#5a6f9e`. Stars
appear from about 5° below the horizon. Overcast skies darken after dark. Lit
grass still reads slightly green at night.

**Indoors.** Rendering uses the frame's unzoned `ambient_outdoor_intensity`
and keeps landscape cloud shadows active when the camera enters a room. Rain
suppression and audio muffling are decided locally, by containment (below).
Legacy fog and mist still respond globally to containment, so distant haze
seen through a window can change.

## Shadows and contact occlusion

| Tier | Sun shadow range | Cascades | Filter | SSAO (Forward+) | Tree proxy range | Building SDFGI | Active local lights |
| --- | ---: | ---: | --- | --- | ---: | --- | ---: |
| Low | 80 m | 2 | Hard | Off | 30 m | Off | 2 |
| Medium | 120 m | 2 | Hard | On | 50 m | Off | 4 |
| High (default) | 160 m | 4 | PCF, low filter | On | 80 m | On | 4 |
| Ultra | 260 m | 4 | PCSS, medium filter, 0.5° | On | 130 m | On | 6 |

The sun range can be set with `FoliageQuality.directional_shadow_distance`.
Its minimum is the tree proxy range plus 20 m. Cascade splits are
0.10/0.25/0.55, with blending, and the fade starts at 0.85. Shadow bias is
0.04 and normal bias 1.2. Lower biases striped, and the earlier 0.1/2.0
visibly detached contact shadows. Low keeps two cascades for nearby
architecture shadows. High uses PCF because PCSS cost about 3 ms more in
foliage views.

SSAO uses radius 0.6 m, intensity 1, power 1.25 and detail 0.35. It has no
influence on direct light or on the material AO channel. A 0.35 m radius lost
corner definition, and 0.9 m spread darkening across surfaces. SSIL stays off.
Low and non-Forward+ renderers use direct light plus ambient, without SSAO or
GI.

## Building indirect lighting

On High and Ultra, building worlds rendered with Forward+ use SDFGI: 0.1 m
cells, four cascades, 50% vertical scale, occlusion on, bounce feedback 0.3
and energy 1.0. It provides bounce from direct sun and local lamps in bounded
interiors. Sky injection is off. The editor's **Indirect lighting** checkbox
also controls its visit. Outdoor locations never voxelize the landscape or
foliage: they keep colour fill, direct shadows and SSAO.

When an edit is completed, or on undo/redo, load or a cutaway rebuild, the
old field is disabled immediately. `BuildingIndirectLighting` re-enables it
after two process frames, once the replacement geometry has reached the
renderer. A revision counter coalesces pending rebuilds, and the field then
converges over later frames. This refresh is needed because SDFGI does not
follow changes to dynamic occluders. Geometry takes part as static occluders.
Hidden cutaway pieces, glass and lamp fixture primitives do not. The sun and
lamps use dynamic GI. Derived lighting is never saved in a document.

The fallback (Low, Medium, headless and non-Forward+) carries light through
windows less realistically and fills rooms more evenly. Without sky injection,
sheltered rooms with no direct sun and no lamps can be very dark, overcast
interiors included. Global ambient was deliberately not raised to hide this.
Empty unlit buildings stay dark at night.

The choice was made in a bounded comparison on the starter shell, run by
`scripts/experiment_indirect_lighting.gd`:

| Candidate | Window GPU median | Sealed-shell sun leak | Outcome |
| --- | ---: | ---: | --- |
| Ambient + SSAO | 0.96 ms | 0.00017 | Fallback; even fill on broad walls |
| SSIL, 3 m / 0.6 | 1.43 ms | 0.00017 | No useful room-scale window light |
| SDFGI, sky off (selected) | 2.12 ms | 0.00002 | Sun and lamp bounce, cheap invalidation |
| VoxelGI 128 / 256 | 2.01 / 1.67 ms | 0.079 / 0.019 | Rejected: leaks and rebakes that block for 0.5–2.4 s |

SDFGI raised the reported video memory by about 430 MB in this test, which is
one reason it stays optional. Raw records are in
[gi_candidates](../reference/lighting/gi_candidates/measurements.json) and
[gi_selected](../reference/lighting/gi_selected/measurements.json).

## Containment

`AtmosphereZone.height_bounded` is opt-in and takes `[min_height, max_height)`
in world metres. Older zones are XZ-only. `BuildingLightingZones` builds
volumes from resolved floor slabs and mesh triangles, each up to the nearest
overlapping horizontal ceiling. The volumes keep concave empty cells, the gaps
between stacked floors and open porches. Cameras above a roof are outside. Roofs
with only sloped surfaces and no resolved ceiling produce no volume, and nor do
grid drafts or cutaways. These are weather and audio volumes, not room
definitions or light masks. Authored profile zones take precedence over
derived volumes, which take precedence over the whole-location indoor
fallback. Placed buildings pass their volumes to `AtmosphereSystem`.

## Local lights

`BuildingLocalLights` reads catalogue `localLights` and binds an omni ceiling
lamp or a directional task spotlight to the furniture reference. The light
moves with the reference's position and yaw. Lamps are about 2700 K and have
finite 5–7 m ranges and shadows. Ceiling fixtures are dimmed to avoid a
clipped hot spot. Fixture primitives do not block their own bulbs. Active
shadowed lights per building are capped by quality (see the table) in stable
document order. Fixtures over the cap stay visible with their lights off,
rather than leaking unshadowed light through walls. No lamp is ever inserted
automatically. Open **Lighting test room (built-in)** (`lighting-room`) for an
example.

## Street lights and lit placeholder windows

`Frame.lights_on` rises through sunset, reaching full at -3°. It is published
as the `atmosphere_night_lights` shader global and as
`AtmosphereSystem.night_lights`.

- **Street lights** (`lighting/site_street_lights.gd`). Lamp positions are
  inferred at load from site road records and are never written to the bake.
  Placement follows each road's context ([ROADS_SETTLEMENTS.md](ROADS_SETTLEMENTS.md)):
  - Street-class spans through villages get lamps on one side (the pavement
    side) every 35 m.
  - Through towns, lamps go on both sides, staggered every 28 m.
  - Rural spans get none.
  - `lit=yes` lights any way every 40 m, and `lit=no` is respected.
  - Sites baked before road contexts keep the earlier rule: street-class
    roads inside residential, commercial or retail land use, every 30 m.

  Lamps sit 0.6 m beyond the road edge with the arm over the road, outside
  building footprints and at least 14 m apart. The mesh is TownCity
  `RoadLight_01_A`, converted by `tools/geo/import_town_pack.gd` into
  `assets/town/poly_towncity/`. Every lamp has an emissive head. Only the
  nearest 6/12/24/32 lamps (Low to Ultra) within 160 m carry an unshadowed
  warm SpotLight3D.
- **Windows** (`lighting/placeholder_windows.gd` and `.gdshader`). A generic
  material on geographic placeholder walls draws one 3.2 m bay grid per 3 m
  storey, without new geometry. This was a deliberate exception, requested by
  the user, to keeping placeholders plain; the building editor still replaces
  the whole placeholder. Barns, garages, sheds, churches and other
  non-dwelling tags get no windows, nor do footprints under 40 m². About 45%
  of panes glow amber after dusk, switching on at slightly different times.
  Authored buildings are untouched.

## Measured cost

These are GPU milliseconds at 1920 × 1080 on the reference machine: Godot
4.7.2, Forward+, Vulkan 1.4.325, RTX 3060 Ti, driver 591.86. Each figure is
the stationary median of three runs (`scripts/benchmark_lighting.gd`); walking
medians differ by under 0.15 ms. They were measured before the warm pass.

| Tier | Maximum 30 × 30 m shell | Authored manor | Dense Buchenhain woodland |
| --- | ---: | ---: | ---: |
| Low | 0.63 | 0.49 | 3.87 |
| Medium | 0.87 | 0.73 | 6.90 |
| High | 2.02 | 1.41 | 12.77 |
| Ultra | 2.52 | 1.69 | 22.18 |

- **High.** Building GI adds about 0.6–1.0 ms, and every view stays under
  16.7 ms on this GPU. Shadows and SSAO cost about 2 ms outdoors.
- **Ultra.** Woodland exceeds 16.7 ms; its walking p95 is 38.7 ms.
- **Warm-up.** Building GI warm-up peaks at 15.7–16.9 ms. Outdoor quality
  switches rebuild foliage impostors, which takes 4–7 s.

Repeat the benchmark on a deployment machine to get its budget. Records:
[building tiers](../reference/lighting/lighting_benchmark/measurements.json),
[outdoor](../reference/lighting/lighting_benchmark_outdoor/measurements.json).

## Reproduce and test

Each capture stage must name a new directory, because the harness refuses to
overwrite captures. `reference/lighting/.gdignore` keeps review images out of
Godot imports and exports.

```powershell
$env:APPDATA = Join-Path (Get-Location) '.test_appdata'
$godot = 'C:\Program Files (x86)\Godot\Godot.exe'
& $godot --path . --script res://scripts/capture_lighting.gd -- --stage=review_new --motion
& $godot --path . --script res://scripts/capture_lighting.gd -- --stage=fixture_review_new --only=maximum,lamps
& $godot --path . --script res://scripts/experiment_indirect_lighting.gd -- --stage=gi_new --only=sdfgi --sdfgi-no-sky
& $godot --path . --script res://scripts/benchmark_lighting.gd -- --stage=benchmark_new
& $godot --path . --script res://scripts/capture_street_lights.gd
& $godot --path . --script res://scripts/test_lighting.gd -- --render
& $godot --headless --path . --script res://scripts/test_building_lighting.gd
& $godot --path . --script res://scripts/test_building_lighting.gd -- --render
& $godot --path . res://scenes/building_visit.tscn -- --building=lighting-room --hour=23
```

`capture_lighting.gd` also accepts `--only=contacts,manor,buchenhain --quick`
and the overrides `--no-ao`, `--radius=`, `--normal-bias=`, `--shadow-bias=` and
`--samples=`. These affect only the capture process. `--legacy` replays the
pre-stage-1 policy on current geometry.

The rendered checks confirm that:
- window bounce decreases away from the window;
- a closed shell blocks the sun;
- a lamp lights its room, and a partition blocks it;
- building shadows reach the High range;
- cutaway roofs are removed and restored.

The headless checks cover:
- independent per-viewport resources and quality switches;
- height-bounded zones, concave footprints, open porches and stacked floors;
- lamp transforms and caps;
- edits, undo/redo, load and repeated editor/visit returns;
- a collision-backed night walk through a doorway.

All of these are registered in `scripts/test_all.ps1`. Under Compatibility
rendering, Godot reports four texture leaks at shutdown; Forward+ does not.

## Open

- Firelight on the fire props (needs approval).
- Unlit roofed interiors, which are dark without lamps or sky injection.
- Shadowed street lamps.
- Daylight-responsive lamp schedules and light switches.
- A placement UI that shows fixtures with inactive lights.
- Validation of the standalone Windows executable, which needs the 4.7.2
  export templates.
