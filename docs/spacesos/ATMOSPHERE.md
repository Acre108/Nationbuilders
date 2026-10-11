# Atmosphere

Time of day, weather, sky, rain and drifting motes for SpacesOS locations,
ported from PlacesOS, and wired into the foliage wind so weather moves the
grass and trees.

Lighting uses `LightingSettings` across buildings, locations and
this system: AgX at exposure 1.0 with subtle HDR bloom, a warm fill that is
mostly explicit colour plus a 25% sky-radiance mix, day/night ambient scales
0.7/0.22, and quality-controlled shadows/contact SSAO (see [LIGHTING.md](LIGHTING.md)). At night the sun node becomes
the moon (opposite the sun, cool and dim, cloud-dimmed); `Frame.moon_lit`
says which body drives it, so night scenes keep one directional shadow pass.
Rendering uses `Frame.ambient_outdoor_intensity`: entering a room no longer
changes global fill or landscape cloud shadows seen through its windows.
The model retains `ambient_intensity` with its legacy zone multiplier for
callers; the renderer ignores that multiplier. The former indoor 1.65 boost
is removed. Atmosphere retains sun direction, energy, colour, weather,
fog and lightning ownership. Environment resources remain independent per
viewport. Optional SDFGI supplies sunlight/lamp bounce in High/Ultra standalone
buildings; outdoor locations keep direct lighting, colour fill and contact AO.
See [LIGHTING.md](LIGHTING.md) for the measured choice and
the limitations of sky-free GI and the cheaper ambient fallback.

`AtmosphereZone.height_bounded` opts into world Y bounds, inclusive at the floor
and exclusive at the ceiling. Existing polygons remain XZ-only. Runtime building
volumes come from resolved floor/ceiling overlaps, including concave layouts and
the manor's authored meshes; nearest overlapping ceilings bound each floor.
Placement supports the current translation/yaw transforms. Drafts, unroofed gaps,
open porches and cutaways create no enclosed volumes. Authored profile zones take
precedence, then derived building volumes, then whole-location indoor fallback.
Containment still suppresses camera-local rain and muffles audio. Legacy fog/mist
changes remain camera-wide, so distant haze through a window can still change.

| File | Role |
| --- | --- |
| `atmosphere/atmosphere_model.gd` | Pure maths: `AtmosphereModel.calculate()` returns a `Frame` (sun, ambient, fog, sky bands, rain amount). |
| `atmosphere/atmosphere_profile.gd` | Per-location authored settings (`AtmosphereProfile` Resource). |
| `atmosphere/atmosphere_zone.gd` | Inside/outside polygons (`AtmosphereZone`). |
| `atmosphere/atmosphere_system.gd` | The node: runs the clock and weather, applies the frame, drives the foliage wind, owns rain and motes. |
| `atmosphere/shaders/sky.gdshader` | Sky: gradient bands, dawn/dusk glow, stars, sun disc, cirrus and cumulus layers. |
| `atmosphere/shaders/atmosphere_clouds.gdshaderinc` | The one cumulus field, shared by the sky and the ground's cloud shadows. |
| `atmosphere/shaders/atmosphere_ground.gdshaderinc` | Wetness: the shared wet darkening, and the puddle function the terrain uses. |
| `atmosphere/lightning.gd` | Lightning and thunder in STORM weather (`Lightning`). |
| `atmosphere/weather_audio.gd` | Rain, wind, foliage rustle, water and still-air ambience, and the indoor muffle (`WeatherAudio`). |
| `tools/audio/make_weather_audio.py` | Synthesises the WAVs in `assets/audio/`. |
| `scripts/test_atmosphere.gd` | Test scene (`scenes/test_atmosphere.tscn`). |

## What came from PlacesOS

| PlacesOS source | Ported as | Notes |
| --- | --- | --- |
| `world/atmosphere-model.ts` | `AtmosphereModel` | Presets (`golden-hour`, `quiet-evening`), 58° sun arc, weather dimming, soul-warmth tint, zones and overrides: all ported in full. The Godot spike's `atmosphere_model.gd` covered only the no-zone case. |
| `world/atmosphere.ts` `AtmosphereSystem` | `AtmosphereSystem` | Sun, ambient, fog and zone switching; ambient/display defaults now come from the shared lighting policy. |
| `world/atmosphere.ts` `RainField` | GPU particles around the camera | Opacity curve and colour carried over; the CPU line field became `GPUParticles3D`. |
| `world/skybox.ts` | `sky.gdshader` | Zenith/horizon/ground tints, place-seeded tint, stars, sun disc. |
| `simulated-clouds.ts` | Clouds in `sky.gdshader` | Coverage shaping only. In PlacesOS this drove the location globe, not the in-world sky. |
| `environmental-effects.ts` `DustField` | Motes around the camera | PlacesOS placed dust volumes by hand in rooms; outdoors they follow the camera. |
| `audio/ambience.ts` | `WeatherAudio` + generated WAVs | Its recipes (rain noise high-passed at 720 Hz; still air low-passed at 420 Hz with a 68 Hz tone) are baked into loops and cross-faded live instead of re-filtering one source. See *Lightning, thunder and ambience*. |
| `graphics-config.ts` post-processing | `LightingSettings` | Shared AgX tonemapping at exposure 1.0 with HDR-only bloom (PlacesOS used ACES 0.9); additional grading disabled. Applied at environment construction and atmosphere initialization. |

**Not ported:**

- **PlacesOS window lights and local lamps.** Their `place.json` pipeline is
  excluded. SpacesOS now binds authored catalogue `localLights` through
  `BuildingLocalLights`; it does not generate window lights or add lamps to saves.
- **Plant-motion sway and the PlacesOS grass wind.** SpacesOS's own foliage wind
  already replaces them.

### Deliberate differences from the source

These are also documented in the header of `atmosphere_model.gd`.

- **Fog darkens at night.** PlacesOS used one fog colour all day. Across a
  landscape, a pale night fog makes the horizon glow.
- **Weather fog multiplies the location's own `FoliageProfile.haze_amount`.**
  The preset densities were tuned for rooms and would white out a landscape.
- **Sky colours blend continuously instead of switching per period**, so the
  clock can run without the sky popping.
- **The place-seeded mountain silhouette is gone.** SpacesOS has real terrain.
- **Ambient scaling blends by daylight** instead of flipping at sunset.
- **Rain streaks fade out within about 4 m of the camera.** Up close they read
  as scratches on the lens.

## The wind connection

Wind direction and base speed stay on `FoliageProfile`. That is the one place
the grass, terrain and tree shaders already read them from. Weather only
**scales** that wind, through two **global** shader uniforms declared in
`project.godot` and read in `foliage_wind_field()`
(`foliage/shaders/foliage_common.gdshaderinc`):

| Global | Default | Effect |
| --- | --- | --- |
| `foliage_gust_scale` | `1.0` | Multiplies the whole gust field. Grass bends further, trees sway and flutter harder, and the gust colour shift on distant terrain strengthens. Because it is applied in the shared include, near grass and far terrain agree. |
| `foliage_wind_scroll` | `(0, 0)` | Extra scroll, integrated on the CPU, so gusts travel faster in storms. |

**Why the uniforms are global:** the atmosphere reaches every foliage material
at once without holding references to any of them, and it cannot miss one.

**Why the scroll is integrated on the CPU instead of raising
`foliage_wind_speed`:** the shader scrolls by `TIME * speed`. Changing the speed
mid-game would jump the field by (elapsed seconds × change) in one frame.

Both globals sit at their defaults whenever no `AtmosphereSystem` is in the
scene, and the node resets them when it leaves the tree. The foliage test scene
and its measurements are therefore unaffected.

Per weather kind at full intensity, from `AtmosphereProfile`:

| Weather | Gust scale | Scroll speed |
| --- | --- | --- |
| Clear | ×1.0 | ×1.0 |
| Cloudy | ×1.35 | ×1.3 |
| Rain | ×1.5 | ×1.4 |
| Mist | ×0.5 | ×0.6 |
| Storm | ×2.0 | ×1.9 |

Storm stops at ×2.0 because beyond that, short tufts bend further sideways than
they are tall.

These are lerped by intensity. Rain streaks, motes and clouds drift along the
same `FoliageProfile.wind_direction` at the same multipliers, so rain slants the
way the grass is bending.

**Limitation:** weather cannot change the wind *direction*. Rotating it at
runtime would need the same CPU-integration treatment as speed, plus a global
bend direction for grass and trees. Not needed yet.

## Skyscape

Added on top of the port, so the sky reads as a place and the ground answers
to it.

### Cloud shadows

The cumulus deck is one field, defined in `atmosphere_clouds.gdshaderinc` and
driven by five shader globals set by `AtmosphereSystem` each frame:

- `atmosphere_cloud_noise`
- `atmosphere_cloud_offset`
- `atmosphere_cloud_cover`
- `atmosphere_cloud_shadow`
- `atmosphere_sun_direction`

The deck is a flat layer 1200 m up. The sky finds the point on it along each
view ray. The ground finds the point along the ray towards the sun. Both then
evaluate the same density function, so a shadow sits under the cloud that
casts it and drifts with it.

The shadow is applied in `foliage_apply_distance_tint()`
(`foliage/shaders/foliage_distance.gdshaderinc`). That function is the last
albedo step every foliage surface already runs: terrain, grass, flowers, both
tree styles and the impostors. So one edit reaches all of them.

**Known trade-off:** the shadow multiplies albedo, so it dims a little of the
ambient light as well as the sun. The foliage shaders use Godot's built-in
lighting, with no `light()` function to hook the sun term alone. At the
strengths used, it reads as a cloud shadow.

**Impostors:** `TreeImpostorBaker` sets `foliage_live_weather_weight = 0` on
its bake copies. Without that, the shadow over the bake origin at startup
would be painted into every impostor.

**When shadows fade:**

- at night;
- as the sky closes over, since under overcast there is nothing to contrast
  with (`(1 - cover) * 3`, clamped).

Entering a building keeps the outdoor cloud-shadow field active so the landscape
seen through openings stays consistent.

With no `AtmosphereSystem` in the scene, `atmosphere_cloud_shadow` is 0 and
the ground only pays one uniform branch.

**Cost:** measured with `--shadow-cost` on 2026-09-18 (RTX 3060 Ti, High
quality, head-height view across the meadow). The GPU frame took 1.974 ms
with shadows on and 1.967 ms with them off: +0.3%, within noise.

### Sky layers

- **Dawn/dusk glow.** The horizon warms towards the sun's bearing and climbs a
  little way up the sky. A low cool-pink band sits opposite the sun (the
  "belt of Venus"). Both are driven by the new `Frame.twilight`, which peaks
  with the sun near the horizon and lingers about 10° after sunset, for the
  afterglow. Heavy cloud cover suppresses it.
- **Cumulus.** The shared deck. Each point checks the density 260 m towards
  the sun: more cloud there means this point is in its own cloud's shadow,
  which gives fake volume. Undersides warm at dawn and dusk, and thin edges
  light up when you look near the sun.
- **Cirrus.** A second, high layer (7 km), streaked along the wind, patchy,
  and warped so the streaks vary. It catches sunset colour hardest, as real
  high cloud does. It thins as the weather worsens.

`AtmosphereProfile` knobs:

| Knob | Default | Notes |
| --- | --- | --- |
| `clear_cloud_cover` | 0.3 | Raised from 0.18, so clear days get some fair-weather cumulus to cast shadows |
| `cloud_shadow_strength` | 0.4 | |
| `cirrus_amount` | 0.55 | |

## Wet ground and mist

### Wet ground

`AtmosphereSystem.wetness` (0 dry, 1 soaked) is worked out over time and
pushed to the `atmosphere_wetness` shader global each frame:

- **Rain soaks the ground**, rising towards the rain's intensity. Full rain
  soaks it completely in `wetting_seconds` (90 s by default).
- **Mist leaves dew**, topping wetness up to `dew_wetness` (0.3) at full mist.
  That never reaches the puddle threshold.
- **Otherwise the ground dries**, over `drying_minutes` (5) in full sun. It
  dries more slowly under cloud and at night, down to 30% of the rate.

Rising is fast and drying slow, so the ground still glistens after a shower
has passed.

How it shows:

- **Everything goes a little darker and more saturated.** This is applied in
  the shared `foliage_apply_distance_tint()`, at 16% darker when soaked, so
  grass and far terrain darken together and the horizon handover holds.
- **Bare soil (and rock, at half) soaks darker and turns glossy.** Terrain
  only; rock and bare come from the slope and the growth mask. Roughness
  drops from 0.95 to 0.35.
- **Puddles** form on flat bare ground once wetness passes 0.35. They start
  in the lowest hollows of a noise field and spread as the rain continues,
  then drain the same way. A puddle is dark, near-mirror (roughness 0.04),
  with the turf detail normal dropped, so it reflects the sky.
- Per-location terrain knobs: `terrain_wet_soil_darkening`,
  `terrain_puddle_amount` (0 for sandy ground that drains) and
  `terrain_puddle_scale`. These are terrain shader uniforms, not yet on
  `FoliageProfile`.

### Mist

`Frame.mist` (0..1) is the thicker of two sources:

- **`MIST` weather**, a new weather kind: soft light (sun ×0.6), calm air
  (gusts ×0.5), a hazy sky rather than crisp cloud;
- **dawn mist**, which forms by itself as a bell curve around 06:20 at
  `dawn_mist` strength (0.7), and which rain washes out.

It is applied through Godot's fog, in three parts:

- **Distance haze closes in** to an absolute `mist_haze_distance` (320 m),
  fully opaque there, with a lower curve so it gathers sooner (see *Distance
  haze* below). It is not relative to the location's own haze, so clear-air
  locations such as `rolling_hills` get the same mist as the meadow. Rain and
  storm, by contrast, scale the location's haze, so far hills stay visible
  through ordinary weather. Near grass stays crisp either way.
- **Height fog** starts `mist_depth` metres (6) above the location's average
  ground height, sampled once per location over its central 600 m. Hollows
  and valley floors fill thickest, and the layer stays put as you climb out
  of it. `mist_height_density` is kept small (0.012): Godot's height fog
  applies at any distance, so higher values wash out the grass at your feet.
- **The sky is veiled** (`fog_sky_affect` = 0.7 × mist), so the sky and the
  fogged distance meet in one soft white.

The mist colour leans white but is lit by daylight or the dawn glow,
whichever is stronger, so it never glows at night and still catches first
light.

## Distance haze

`AtmosphereHaze` (`atmosphere/atmosphere_haze.gd`) draws clear-air haze as
Godot depth fog (`FOG_MODE_DEPTH`): clear at the camera, thickening over a
smoothstep ramp (curve 0.85) to its full strength where the drawn ground
ends. It replaced exponential fog after the October 2026 location review:
at the old 0.0015 default, exponential fog was 78% opaque at 1 km and 95% at
2 km, so Brienz's mountain walls and Buchenhain's fields went flat grey while
6-8 km of horizon ground was drawn behind the fog.

- **Reach** is `FoliageLocation.drawn_ground_distance()`: the quality level's
  `horizon_distance` (2.5 km Low to 8 km Ultra), cut short by the world's
  edge plus its 2 km scenery margin, never under 1.5 km. Lower quality draws
  less ground and gets proportionally closer haze; walking towards the world
  boundary, the air closes in rather than revealing the edge. On High from
  the middle of a location, at the default strength, the haze is about 9% at
  1 km, 27% at 2 km and 66% at 4 km.
- **Strength** is `FoliageProfile.haze_amount`, the haze's opacity at that
  reach: 0.85 by default, 0.7 for Lake Brienz and the Swiss Alps (clear
  mountain air), 0.8 for Buchenhain, 0.95 for `dry_field`. 0 turns haze off
  (mist still appears).
- **Weather** (`Frame.fog_scale`: cloudy 1.35, rain 1.9, storm 2.3, indoors
  0.28) divides the reach and multiplies the strength, capped at 1.
- **Colour** is 85% aerial perspective, the sky's radiance behind each
  pixel, so ridges fade into the pale horizon by day and its peach at dusk. The
  rest is `Frame.fog_colour`, from the soft-blue `FoliageProfile.fog_colour`.
- **Glow**: `Frame.haze_glow` drives `fog_sun_scatter` (up to 0.35). It is
  strongest with a low sun in clear air, the amber bloom of a late afternoon
  looking into the light; faint at midday, gone under heavy cloud and after
  sunset.

Neither fog mode has a measurable cost; volumetric fog stays off. The cost
that haze trades against is the horizon ring and tree ranges, which the
quality level already sets. Clearer air does show where trees stop
(`view_distance`); the terrain shader's far woodland colour stands in for
them beyond it. In the October 2026 review captures that stand-in held up at
Buchenhain and Lake Brienz, but Black Forest's far ridges (2-6 km) read as
lighter, lawn-like slopes than its dense spruce cover. Darkening the far
woodland there is a terrain-shader follow-up, not a reason to thicken haze.

Keys: `6` mist, `\` toggles the ground between dry and soaked.

## Lightning, thunder and ambience

### Lightning

Lightning belongs to **STORM** weather only; RAIN never strikes, however
heavy. (Lightning first shipped as "heavy rain strikes", with no storm state.
The user then asked for rain and storm to be separate weather types.)

**STORM** rains exactly like RAIN at the same intensity: the same streaks,
soaking, puddles and rain sound. On top of that it adds:

- harder gusts (×2.0) and a louder wind sound;
- a darker sky and cloud, with sun ×0.16, ambient ×0.6 and fog ×2.3;
- lightning.

**Intensity is also how close the storm is.** Strikes come at up to
`lightning_per_minute` (4) at full storm and a quarter of that at the
lightest. The nearest a strike can land also closes in, from about 3.2 km at
low intensity to 400 m at full. A light storm is therefore a distant one:
occasional far flashes, with thunder that only rumbles, long after.
Arrivals are random (Poisson), never closer than `lightning_min_gap` (4 s).

Each strike picks a direction and a distance out to 7 km, spread evenly over
area, so far strikes are commoner. From those:

- **The flash.** The sky brightens all over, and most strongly towards the
  strike, where the cloud base lights up from inside. A shadowless
  directional light hits the land from that side, and the ambient light lifts.
  All of it weakens with distance.
- **The light is hidden from the sky shader**
  (`sky_mode = LIGHT_ONLY`). Otherwise, at night with the sun hidden, it
  becomes LIGHT0 and the sky draws a sun disc at the strike.
- **Indoors**, only the ambient lift gets through; there is no scene light.

`Lightning.strike(direction, distance)` forces a strike in any weather (debug key `B`, for bolt).

**Photosensitivity:** large bright flashes faster than 3 per second are a
seizure risk (WCAG 2.3.1). Real lightning flickers faster than that, so each
strike here is shaped to stay under the limit:

- a main flash, plus at most one re-flash at least 0.34 s later;
- strikes at least `lightning_min_gap` apart;
- `lightning_flash_scale` dims the flash, and **0 removes it entirely while
  keeping the thunder**. This is the setting to expose in an accessibility
  menu.

Strikes are random per client and not networked, like the rest of the
atmosphere.

**Terrain:** strikes pick only a direction and a distance and never query
terrain height, so the far-terrain ring planned out to 4–8 km needs nothing
here. If strikes ever need a ground point, use `TerrainProvider.get_height()`.

### Thunder

Thunder arrives after distance ÷ 343 m/s: 1.2 s at 400 m, about 20 s at 7 km.

- **Near** strikes (under 1.8 km) crack, then rumble. **Far** ones only
  rumble, lower and softer.
- Level falls by up to 20 dB with distance, and pitch drops slightly.
- It is panned towards the strike by an `AudioStreamPlayer3D` placed on that
  side, with distance attenuation off; distance is applied as volume.
- A pool of 3 players lets rolling thunder overlap.

### Ambience

Six looping beds cross-fade continuously, each following the same numbers
the visuals use:

| Bed | Follows | Level at full |
| --- | --- | --- |
| Rain | √ rain intensity, so light rain is already audible | `rain_volume_db` −8 |
| Wind | The foliage gust scale: quiet at ×1, full at ×1.8, gone in still mist (×0.5). You hear it exactly as hard as you see the grass bend. | `wind_volume_db` −12 |
| Foliage rustle | The same gust scale as Wind (lower base, since even calm foliage stays fairly quiet), scaled by `AtmosphereSystem._foliage_density()` -- a location-level 0..1 read of how much tree/conifer/shrub/fern/cushion cover the current `FoliageProfile` carries. Zero density is silent no matter how hard it blows: nothing there to rustle. | `rustle_volume_db` −16 |
| Water (calm) | Gentle lapping. Present near water at almost any wind -- never below 35% of full even in a storm, chop just dominates over it -- scaled by `AtmosphereSystem._water_proximity()`. | `water_calm_volume_db` −14 |
| Water (wind-roughened) | Chop and small breaking crests. Rises from nothing in the authored wind to full in a storm, LAYERING on top of the calm bed rather than replacing it -- water actually gets louder in a storm, not just different -- also gated by `_water_proximity()`. | `water_wind_volume_db` −10 |
| Still air | Mist, and whatever calm the wind leaves; silent in rain | `still_air_volume_db` −16 |

The rustle and water beds exist precisely so the SAME storm sounds different
over dry high ground, through a spruce forest, and beside a lake. Rustle
reads `docs/FOLIAGE.md`'s five foliage families (conifers weighted heaviest,
alpine cushion plants lightest: a dense needle canopy rustles far more than
the same numeric cover of tiny stiff cushion leaves). Water reads
`docs/WATER.md`'s sea/lake/river system -- `_water_proximity()` is a live
per-frame read of distance to the nearest one (unlike `_foliage_density()`,
which is cached per profile: water is a localized feature, not a diffuse
location-wide cover the way tree canopy is), approximated three different
ways for cheapness (sea: vertical distance to `sea_level`, since the sea
plane's reach makes it in practice everywhere at low elevation; lake:
distance to a basin's bounding rectangle, not its true shoreline; river:
distance to the nearest traced vertex, not the true nearest point on the
ribbon) -- good enough for an ambient bed's gain, nothing else reads it.

Everything, beds and thunder, goes through a **"Weather" audio bus** that
`WeatherAudio` creates with a low-pass filter. Inside (an INSIDE zone or an
indoor location), the filter closes to `indoor_cutoff_hz` (900 Hz) on an
exponential sweep, and the bus drops `indoor_volume_db` (−10 dB): the weather
heard through a roof. `audio_enabled = false` silences it all. Removing the
atmosphere removes the bus.

**Known exit-time warning:** when the whole app quits while the loops are
playing (seen under `--quit-after`, in both small and large scenes, depending
on timing), Godot may report the loops as "resources still in use". Its audio
thread releases a stopped playback on its next mix, and at quit there isn't
one. Removing the atmosphere while the game runs releases everything;
`--wind-check` asserts that.

### The sound files

`tools/audio/make_weather_audio.py` (numpy) writes 44.1 kHz mono 16-bit WAVs
to `assets/audio/`:

- `rain_loop`, `wind_loop`, `foliage_rustle_loop`, `water_calm_loop`,
  `water_wind_loop` and `still_air_loop`: 12 s loops (rustle: noise band
  1.4-4.2 kHz, above the wind body -- a "shhh" of many small things, not a
  low roar; water_calm: soft low-band noise under 700 Hz with sparse
  irregular lapping swells and a few soft low plips; water_wind: a brighter,
  wider band up to 2.2 kHz with faster, bigger chop swells and a gated
  2.5-6.5 kHz foam/spray layer on the larger swells);
- `thunder_near_1`/`_2` (7 s) and `thunder_far_1`/`_2` (8.5 s): one-shots.
- `waterfall_loop` and `surf_loop`, played positionally by the water rather
  than here. `surf_loop` (SEA7) is 24 s, holding three breakers about a surf
  period apart (0.6, 8.3 and 16.2 s). Each is a low swell, a crash, the
  wash running up the sand with its fizz, and the backwash, over a steady
  low roar. `SurfAudio` (`foliage/water/surf_audio.gd`) plays it on the
  breaking line; see [SEA_PLAN.md](SEA_PLAN.md), SEA7.

It uses fixed seeds, so re-running reproduces the files. To change a sound,
edit its recipe and re-run. To use a recording instead, drop a file with the
same name in `assets/audio/`.

**Loops are seamless by construction.** Filtering is done in the frequency
domain over exactly the loop length, which makes the result circular, and
slow modulations complete whole cycles per loop. Loop points are written into
a WAV `smpl` chunk, which Godot's importer picks up by default; `--wind-check`
asserts the loops import as looping and thunder does not.

Checked numerically, since nobody can listen from a test:

| File | Spectral centroid | 90% of energy below |
| --- | --- | --- |
| rain | 3.6 kHz | 6.5 kHz |
| wind | 235 Hz | 0.5 kHz |
| still air | 328 Hz | 0.6 kHz |
| far thunder | about 100 Hz | 180 Hz |

Every loop seam is a smaller step than the file's 99th-percentile sample step.
**Reviewed by ear (9 October 2026):** the user listened to the weather beds,
thunder and surf and judged them good as they stand.

## The clock and the tide

`time_of_day` is **local mean solar time** at the location: 12:00 is when
the mean Sun crosses the location's meridian, so UTC = hour - longitude /
15, with no time zones or daylight saving. Since SEA3 the tide reads it
that way too.

**The real sun (9 October 2026).** At a destination on the map
(`LocationDefinition.manifest_path` set), the sun follows the destination's
latitude and `day_of_year`. `AtmosphereModel.solar_position()` uses NOAA's
general solar position formulae: declination and the equation of time from
the fractional year, under 0.1 degree and a minute out, without
refraction. So Ardnamurchan in June gets a 56.7 degree noon, sunrise near
03:07 and daylight past 21:00, and Cape Town's noon sun stands in the
north. `LocationRuntime` sets `AtmosphereProfile.latitude`, `day_of_year`
and `north_z` (from the manifest's `north_axis`) at run time; they are not
saved. `AtmosphereSystem` re-reads the day from `FoliageLocation` each tick.
`sun_angles()` turns the compass azimuth into the sun node's yaw (180 - A
where north is -Z, A for legacy +Z worlds).

Before this, every location had the PlacesOS arc: sunrise 06:00, sunset
18:00, a 58 degree peak. On -Z-north worlds that arc also rose in the west.
Places without a latitude (the test meadow, lighting scenes) keep it
unchanged. Dawn mist now peaks 20 minutes after the real sunrise, and there
is none in polar day or night. The `period` label follows the sun's
elevation (night below -6 degrees). Lamps, stars, twilight and the moon
already followed elevation. The moon stays a full moon opposite the sun.
`scripts/test_solar_position.gd` checks almanac values, both hemispheres,
polar day, the yaw for both north axes and the unchanged arc. The destination's
`day_of_year` and `year` (`LocationDefinition.year`, 0 = the current year)
fix the date. Each tick the atmosphere hands its hour to
`FoliageLocation.set_clock_hour()`, so the running clock (`0`) and the
`[ ] ; '` keys move the tide as well as the sun. The hour wraps at
midnight but the tide clock does not: `SeaState` unwraps it, so running or
scrubbing past midnight carries the tide on into the next day. See
[SEA_PLAN.md](SEA_PLAN.md), SEA3; open question 2 there asks whether civil
clock time would suit better.

## Using it

```gdscript
var atmosphere := AtmosphereSystem.new()
atmosphere.profile = preload("res://content/locations/meadow_atmosphere.tres")  # or AtmosphereProfile.new()
atmosphere.sun = sun
atmosphere.world_environment = world_env
atmosphere.foliage_location = location   # wind, base fog, seed, indoor flag
add_child(atmosphere)

atmosphere.set_time_of_day(19.0)
atmosphere.set_weather(AtmosphereProfile.Weather.RAIN, 0.8)   # fades in over weather_transition_seconds
```

- **Indoor handling.** An indoor `FoliageLocation` (`enabled = false`) is
  treated as an INSIDE zone: fog drops to 28%, ambient uses the zone's reduced
  scale, and rain stops. Ambient still changes globally with camera position;
  spatial indoor/outdoor separation remains lighting stage 5.
- **Zones.** Authored zones in `AtmosphereProfile.zones` do the same for part
  of an outdoor location.
- **Fog ownership.** With an `AtmosphereSystem` present, it owns the
  environment's fog every frame. `FoliageLocation._apply_atmosphere()`'s
  one-off haze write (the same `AtmosphereHaze.apply()`, in clear weather) is
  overridden, but the base values still come from the `FoliageProfile`.

## In the main foliage scene

`scripts/test_foliage_small.gd` builds an `AtmosphereSystem` for plain
interactive runs only. It is off in every self-test, capture, `--wide` and
benchmark mode, and with `-- --no-atmosphere`. `-- --hour=` and
`-- --weather=clear|cloudy|rain|mist[:intensity]` set the start. The
`FoliageHUD` shows an atmosphere line when one is tracked. The keys are shared
via `AtmosphereSystem.handle_debug_key()`; `[ ] ; '` move the clock because
the atmosphere owns the sun. `N` (next location) needs no extra wiring: wind,
base fog and the indoor flag are read from `foliage_location` every frame.

Every location uses the same default `AtmosphereProfile` (golden hour,
16:30). There is no per-location atmosphere resource yet.

A frame is capped at 0.1 s of atmosphere time. The Phase 5 tree impostor bake
stalls one frame for over a second, and without the cap the weather fade and
the clock would leap forward across it.

**Open follow-up:** `profile.distance_tint` (Phase 5 aerial perspective) is
still a fixed colour. The atmosphere could drive it from the frame's horizon
colour by time of day, as noted in `FOLIAGE.md`.

## Test scene

```
Godot.exe --path . res://scenes/test_atmosphere.tscn                  # interactive
Godot.exe --path . res://scenes/test_atmosphere.tscn -- --wind-check  # asserts, exit code
Godot.exe --path . res://scenes/test_atmosphere.tscn -- --shots       # user://atmosphere_*.png
Godot.exe --path . res://scenes/test_atmosphere.tscn -- --shadow-cost # GPU ms, cloud shadows on vs off
Godot.exe --path . res://scenes/test_atmosphere.tscn -- --shots=mist --location=wide_valley   # a subset, another location
```

All three flags need a real window.

`--shots` includes three sun-facing views (`dawn_sun`, `sunset_sun`,
`afterglow_sun`) and an elevated `shadows_above` view for the skyscape, plus
`path_dry` / `path_after_rain` / `field_after_rain` for wet ground and
`dawn_mist` / `mist` / `mist_above` for mist. Wetness is forced per shot rather
than integrated, so shots never drift. The test scene streams terrain round the
camera, like the main scene.

Headless Godot does not store shader globals,
and the windowed run is also what compiles every foliage shader against the new
globals.

Keys (shared with the foliage scene):

| Key | Action |
| --- | --- |
| `[` / `]` | Hour back / forward |
| `;` / `'` | Quarter hour back / forward |
| `0` | Run or stop a 2-minute day |
| `5` / `6` / `7` / `8` / `9` | Storm / mist / clear / cloudy / rain |
| `B` | Lightning bolt now, in any weather |
| `\` | Ground bone dry / soaked (skips waiting for rain) |
| `-` / `=` | Weather intensity down / up |

`--wind-check` last passed on 2026-09-18, checking:

- clear weather leaves the authored wind untouched;
- full rain gives a gust scale of 1.8;
- the scroll moves with the wind direction;
- half-intensity cloud gives a gust scale of 1.175;
- a kind change fades smoothly, with the largest per-frame gust step at 0.027;
- full rain soaks the ground, and half rain only to 0.5;
- the ground dries gradually, then completely, in sun;
- mist weather gives full mist, and leaves exactly dew-level wetness;
- mist drives Godot's height fog;
- dawn mist forms by itself at 06:18 and is gone by noon;
- the generated beds import as loops, and thunder does not;
- there is no lightning in rain, even full rain;
- storms strike, and more often at full strength than at 0.2;
- a storm rains like rain, and gusts harder (×2.0 against ×1.5);
- thunder is delayed by exactly distance ÷ 343;
- a strike flashes, and a near strike's thunder cracks;
- flash scale 0 keeps the thunder but removes the flash;
- the rain and wind beds are up in a storm, and still air takes over in mist;
- an INSIDE zone closes the bus filter to 900 Hz;
- removing the atmosphere removes its audio bus.

`--wind-check` expects an outdoor location: in `indoor_room` the whole
location counts as inside, so its mist checks fail by design. Every automated
mode mutes the master bus. For silent interactive smoke runs, pass
`--audio-driver Dummy` to Godot.
