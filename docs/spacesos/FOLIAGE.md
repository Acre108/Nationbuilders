# Foliage system

Current asset pipeline: [POLY Nature Pack and regional selection](NATURE_PACK.md).

Stylised grass, flowers and trees for SpacesOS locations.

> **Status: Phase 5 of 6 complete.** Phase 6 is conditional: only if Phase 5's
> close-range terrain detail does not settle the bare-ground complaint (see
> *Why 5 and 6 both exist*).

## Phases

| # | Scope | State |
| --- | --- | --- |
| 1 | Grass mesh, deterministic placement, shared grass/terrain shader | **Done**, verified running |
| 2 | Chunking, placement carving, distance LOD | **Done**, verified running |
| 3 | Trees: painted low-poly masses, leaf shader, shadow proxies | **Done**. All five tree species and both shrubs use painted geometry; ferns/cushions retain cards |
| 4 | Per-location settings resource, quality wiring, indoor skip | **Done**, verified running |
| 5 | Wide landscapes: streaming, terrain shader, distance tint, tree impostors — **plus close-range terrain detail** | **Done**, verified running |
| 6 | Ground-plane skirt under clumps | Only if needed: judge Phase 5's ground detail in motion first |

### Why 5 and 6 both exist

They solve the same complaint — bare ground visible between clumps — from
opposite directions, and the cheap one is tried first.

**Phase 5 adds close-range terrain detail.** Phase 5 already opens
`terrain.gdshader` for the horizon handover, so this rides along: high-frequency
noise breakup and a detail normal so the ground between clumps reads as dense
turf rather than a smooth plane. No geometry, no extra draw calls. Note the
ground is *already* grass-coloured from the shared palette — it looks flat, not
wrong, and flatness is what this fixes. Visible ground that reads as turf is
fine; that is the premise of the horizon handover applied at close range.

**Phase 6 adds a ground-plane skirt** — a small horizontal textured quad per
clump — only if Phase 5 does not settle it.

Phase 6 carries real risk and should not be attempted first. A skirt is
structurally the procumbent mat that an earlier pass built and that was cut for
reading as flat papery sheets. A horizontal surface with a forced +Y normal
catches full sun and reads as a flat panel; that is the same mechanism behind
the back-face pale-panel bug documented under *Clump shape*. If Phase 6 goes
ahead, the skirt needs its own shading treatment rather than inheriting the
grass one, or it will reproduce exactly the artefact it is meant to hide.

Measure with `-- --coverage` before and after each, and judge in motion, not
from a still: the baseline to beat is 52.9% ground visible straight down and
13.6% at 20 degrees, at 10 tufts/m2. (Phase 1 read 52.4% / 13.7%; Phase 2 adds
one random draw per tuft for its LOD rank, which reshuffles the scatter, so the
figures moved within noise.)

## The one idea this system is built around

Where grass stops, the terrain has to already look like grass. A player in an
open field sees grass geometry for the first ~90 m and painted terrain after
that, and the join between them must be invisible.

The mechanism is `foliage/shaders/foliage_common.gdshaderinc`: a single include
holding the entire colour and wind model, `#include`d by `grass.gdshader`,
`terrain.gdshader` and both tree shaders. Every surface runs the same code over
the same uniform values. `FoliageProfile.apply_to_materials()` takes the grass
material and the terrain material together, so it is structurally impossible
to update one and forget the other. `apply_to_tree_materials()` does the same
for trees. Both go through `_apply_shared()`, the one place the include's
uniforms are set.

If you add a uniform to the include, set it in `_apply_shared()`. Otherwise
the surfaces drift apart and the streaming boundary becomes a visible ring on
the ground. The same goes for `foliage_distance.gdshaderinc` (see *Horizon
handover*), which every foliage shader also includes and `_apply_shared()`
also sets.

## Running the test scene

The Rolling Hills commands panel is now also on by default in every
`LocationRuntime` destination, including locations entered from the globe.
`LocationCommands` in `foliage/debug/` owns the controls and furniture for
one visit; leaving frees both. `F` hides/shows the panel. Quality, time,
weather, LOD and place/rotate/remove commands work as in the test scene.
In the main game `N` or `Esc` returns to the destination picker; in the
test harness `N` still cycles locations. There is no obsolete tree-style
toggle: painted trees are the default. Indoor controls safely skip foliage.
Special-purpose test harnesses can set `commands_enabled = false` before
entry to supply their own fixtures and avoid duplicate input handlers.

`project.godot`'s `run/main_scene` is `scenes/app.tscn` (the
real game's entry point), not this test scene, so every command below passes
it explicitly. **Leaving the scene path off does not fail loudly** -- it
silently launches the landing screen instead, which under `--headless` never
quits, so the run just hangs until something kills it. That single missing
argument was mistaken for "the self-tests got slow" for a good chunk of a
session before someone thought to check `project.godot`.

```
Godot.exe --path . scenes/test_foliage_small.tscn
```

| Input | Action |
| --- | --- |
| Right mouse | Hold to look |
| `W`/`A`/`S`/`D`, `Q`/`E` | Move, down/up |
| `Shift` | Sprint (8x) |
| `[` / `]` | Hour back / forward (with the atmosphere); rotate sun around (without) |
| `;` / `'` | Quarter hour back / forward (with the atmosphere); raise / lower sun (without) |
| `0` | Run / stop a 2-minute day (atmosphere) |
| `5` `6` `7` `8` `9` | Storm / mist / clear / cloudy / rain (atmosphere) |
| `B` | Lightning bolt now, in any weather (atmosphere) |
| `\` | Toggle the ground between bone dry and soaked (atmosphere; skips waiting for rain) |
| `-` / `=` | Weather intensity down / up (atmosphere) |
| `1` `2` `3` `4` | Low / Medium / High / Ultra |
| `F` | Toggle the HUD |
| `P` | Place the next furniture object where you are looking (carves grass) |
| `R` | Rotate the last placed object 15 degrees (a move: re-carves) |
| `Backspace` | Remove the last placed object (grass grows back) |
| `L` | Tint the far LOD band |
| `K` | Toggle distance LOD on/off (A/B comparison) |
| `N` | Next location: test meadow, dry field, wide valley, rolling hills, hedge garden, indoor room |

Interactive runs include the PlacesOS atmosphere (`AtmosphereSystem`, see
`docs/ATMOSPHERE.md`): time of day, weather, sky, rain, and weather scaling the
foliage wind. Because it owns the sun, the sun keys move the clock instead.
`-- --hour=19.5` and `-- --weather=rain` (or `cloudy`, `clear`, `mist`, `storm`, `rain:0.4`)
set the start; `-- --no-atmosphere` gives the old fixed sun. **Every mode
below runs without the atmosphere**, on the fixed sun and grey-blue sky, so
measurements and reference shots stay comparable with earlier runs. In
particular, `--coverage` tells ground from grass by the sky having equal RGB,
and `--indoor` asserts that the environment's fog is left alone.

Two headless-ish modes, both of which need a real window (see *Measuring*):

```
Godot.exe --path . scenes/test_foliage_small.tscn -- --shot     # writes user://foliage_small.png and quits
Godot.exe --path . scenes/test_foliage_small.tscn -- --bench    # runs all four quality levels, prints a table
Godot.exe --path . scenes/test_foliage_small.tscn -- --lod      # LOD band shots (plain, tinted, LOD off) + a carve close-up
Godot.exe --path . scenes/test_foliage_small.tscn -- --wide     # streaming flythrough of the wide valley: frame times + shots
```

`--location=test_meadow|dry_field|wide_valley|rolling_hills|hedge_garden|indoor_room` picks the starting
location and `--quality=low|medium|high|ultra` the quality, for any mode, e.g.
`-- --wide --quality=ultra`.

Interactive play, `--shot`, `--bench` and `--wide` stream round the camera.
`--card`, `--coverage`, `--carve` and `--lod` use the fixed square
round the origin, so their results do not depend on where the camera is.

And several that run fine under `--headless`, because they check data rather
than pixels -- together these are the whole pass/fail self-test suite, and
all five run in well under 30 seconds total:

```
Godot.exe --headless --path . scenes/test_foliage_small.tscn -- --carve          # carving self-test; exit code 0 = pass
Godot.exe --headless --path . scenes/test_foliage_small.tscn -- --indoor         # indoor-skip self-test; exit code 0 = pass
Godot.exe --headless --path . scenes/test_foliage_small.tscn -- --stream-test    # streaming self-test; exit code 0 = pass
Godot.exe --headless --path . scenes/test_foliage_small.tscn -- --water-test     # sea/lake/river self-test; exit code 0 = pass (docs/WATER.md)
Godot.exe --headless --path . scenes/test_foliage_small.tscn -- --heightmap-test # real-world terrain sampling self-test; exit code 0 = pass (docs/GEO_IMPORT.md)
Godot.exe --headless --path . --script res://scripts/test_terrain_collision.gd   # ground collision; exit code 0 = pass
```

After adding any new script with a `class_name`, run
`Godot.exe --headless --path . --import` before running the scene, or Godot
will not have the class in its cache and the scene will fail to load.

## Shader uniforms

All of these are shared by grass and terrain unless noted.

### Colour

| Uniform | What it does |
| --- | --- |
| `foliage_colour_noise` | Tiling greyscale noise, sampled in world space. |
| `foliage_palette` | The location's identity: a 1D gradient, darkest/shadowed at 0, lightest/sun-bleached at 1. Noise is mapped through this. |
| `foliage_colour_noise_scale` | World units per tile. Larger = broader colour patches. |
| `foliage_colour_octave_mix` | Blend of a second, broader octave. Stops the tiling reading as a repeating stamp at distance. |
| `foliage_palette_offset` / `_contrast` | Remap noise before the palette lookup, so one gradient can be used at full range or squeezed. |
| `foliage_variation_weight` | How much per-instance jitter overrides the world colour field. Low for grass (neighbours should agree), high for flowers (blooms should differ). |

### Wind

| Uniform | What it does |
| --- | --- |
| `foliage_wind_noise` | Seamlessly tiling noise, scrolled along the wind direction over `TIME`. |
| `foliage_wind_direction` | XZ direction gusts travel. Normalised in the shader. |
| `foliage_wind_speed` | How fast the field scrolls. |
| `foliage_wind_strength` | How far a full-weight vertex is pushed, in world units. |
| `foliage_wind_noise_scale` | World units per tile. **Terrain sets this much larger than grass** (`terrain_wind_scale_multiplier`), so distant fields show broad rolling waves instead of per-blade noise that would alias into shimmer. |
| `foliage_wind_colour_shift` | How much a gust lightens/darkens what it passes over. This is what makes wind readable on distant terrain, where there is no geometry left to bend. |

Gusts push the *palette lookup*, not the final RGB, so wind always moves colour
along the location's own gradient and can never introduce a hue the palette did
not contain.

### Grass only

`grass_root_darkening` (fake AO towards the blade base), `grass_normal_rounding`
(how much true blade normal to mix back into the forced +Y), `grass_translucency`
(backlight — the biggest contributor to grass looking soft rather than plastic),
`grass_roughness`, and `foliage_petal_palette` (bloom colour, blended in by the
mesh's vertex-colour red channel).

### Terrain only

`terrain_slope_colour`, `terrain_slope_begin`, `terrain_slope_end` — blended in
on steep faces so cliffs do not read as vertical lawn.

`terrain_growth_mask`, `terrain_mask_bounds`, `terrain_bare_colour` — the
location's painted growth mask, which is the same one the placers read. Where
nothing grows, the ground turns `bare_colour`. Otherwise a path reads as mown
lawn rather than as a path.

## The quality setting

`FoliageQuality.create(FoliageQuality.Level.HIGH)` builds a preset. One knob
moves everything together, because these cannot be tuned independently — halving
density while keeping a 260 m streaming radius just makes a sparse field that
still costs full CPU to generate.

| | Low | Medium | High | Ultra |
| --- | --- | --- | --- | --- |
| `density_scale` | 0.25 | 0.5 | 1.0 | 1.8 |
| `streaming_radius` (grass) | 52 | 76 | 106 | 166 |
| `view_distance` (ground, trees) | 300 | 450 | 600 | 900 |
| `blades_per_tuft` | 5 | 8 | 11 | 16 |
| `lod_near_end` | 14 | 22 | 32 | 55 |
| `lod_far_end` | 36 | 60 | 90 | 150 |
| `lod_far_keep` | 0.3 | 0.35 | 0.4 | 0.5 |
| `tree_shadow_distance` | 30 | 50 | 80 | 130 |
| `tree_canopy_detail` | 0.5 | 0.75 | 1.0 | 1.3 |
| `tree_impostor_distance` | 55 | 90 | 140 | 240 |

**What to lower first on weak hardware**, in order:

1. `density_scale` — dominates everything. Halving it roughly halves grass cost.
2. `streaming_radius` — cost grows with its square. It sits just past
   `lod_far_end` (grass beyond that is invisible anyway), so lower both
   together. The Phase 1 presets had 64–260 m; that was a guess, and it
   streamed grass nobody could see.
3. `lod_far_end` — pulls the geometry/terrain handover closer. `lod_near_end`
   and `lod_far_keep` are the finer knobs behind it: where the full clump mesh
   stops, and how much of the field survives past that.
4. `blades_per_tuft` — cheapest visual loss per frame saved, but it changes the
   silhouette, so prefer the three above first.
5. `view_distance` — ground and tree chunk count grows with its square. Past
   `tree_impostor_distance` trees are one card each, so this is mostly
   draw-call and streaming cost, not triangles.

Tree shadow quality is the first thing to cut: `tree_shadow_distance` is how
far trees keep casting (see *Trees*). Grass never casts shadows at any level
(`GrassChunk` forces `SHADOW_CASTING_SETTING_OFF`), because hundreds of
thousands of blade shadows are both ruinous and noisy.

**Apply it with `FoliageLocation.set_quality(level)`**, the one call a graphics
menu makes. It rebuilds grass and trees at the preset and sets the sun's
shadows:

| Preset field | Applied as |
| --- | --- |
| `directional_shadow_splits` | Sun cascade mode. Godot offers 1, 2 or 4 cascades, so 3 rounds up to 4 |
| `tree_shadow_distance` | Sun `directional_shadow_max_distance` = this + 20 m. Trees are the only big casters, so cascades spread further than that waste resolution |
| `tree_soft_shadows` | Directional soft-shadow filter, soft-low or hard. This is **renderer-global** in Godot, not per light |

## Clump shape

Picked per location with `FoliageProfile.clump_style`:

| | `SPRITE_CARDS` (default) | `BLADE_FLAT` / `BLADE_DOME` |
| --- | --- | --- |
| Built from | 3 crossed quads textured from the sprite atlas | individual tapered blade geometry |
| Triangles per clump | ~24 | ~90 |
| Transparency | alpha scissor, needs a depth prepass | fully opaque |
| Use for | ordinary grass | biomes wanting legible individual tussocks |

`BLADE_DOME` is the rounded tussock silhouette, kept for scrubby or alpine
locations. `BLADE_FLAT` is the wide flat-topped variant.

### The sprite atlas

`assets/foliage/legacy/grass_sprites.png` is a 2x2 atlas of four clump variants,
generated by `tools/blender/make_grass_sprites.py` (Blender 3.2, headless). The
script is the editable source -- edit its `VARIANTS` table and re-run:

```
"C:\Program Files\Blender Foundation\Blender 3.2\blender.exe" --background --python tools/blender/make_grass_sprites.py
```

Channels: **RGB is per-blade brightness, not colour.** Colour always comes from
the palette, so one atlas serves every location and season. **A is coverage.**

Each card quad carries a quad index in UV2.x, and the shader picks its tile as
`(instance_variant + quad_index) mod 4`. So one card shows three *different*
clump sprites crossed, and which three depends on the instance -- variety from a
single mesh and a single MultiMesh, instead of four meshes and four draw calls
per chunk.

The atlas must be imported with **mipmaps on**; the shader samples
`filter_linear_mipmap`, and without them distant grass aliases badly.

### Two traps this cost real time to find

**Back-face normals.** `cull_disabled` makes Godot negate `NORMAL` on back
faces. That is right for solid geometry and wrong here: the whole point of
forcing +Y is that a field of cards lights as one soft surface. A flipped card
gets -Y, loses all diffuse, and renders as a flat wash of `BACKLIGHT` -- pale
translucent-looking panels scattered through the field. They look exactly like
an alpha bug and are not one; the pixels pass the scissor fine. The fragment
shader flips the normal back for back faces.

**Backlight on a forced normal.** Because a card never faces away from the sun,
`grass_translucency` stops being rim transmission and becomes a flat brightness
boost. It is 0.22 for cards where blade geometry wanted ~0.45; leaving it high
washes the field out into one flat tone.

Diagnosing anything sprite-related is much easier on one card than on eighty
thousand:

```
Godot.exe --path . scenes/test_foliage_small.tscn -- --card      # four isolated cards, one per atlas variant
```

### Ground visibility and density

Cards are vertical, so they close the ground far less than the procumbent mat
that an earlier pass used (which was removed -- it read as flat papery sheets).
What buys coverage back is density, and cards are cheap enough to afford it:

| Ground visible from 1.7 m | 4 tufts/m2 | 10 tufts/m2 |
| --- | --- | --- |
| 20 deg down | 32.8% | **13.7%** |
| 35 deg down | 47.3% | **21.9%** |
| 55 deg down | 67.0% | **37.6%** |
| straight down | 77.2% | **52.4%** |

At 10/m2 the sprite field still costs fewer triangles (3.2M) than blade geometry
did at 4/m2 (7.0M). Density is the lever here; `base_density` defaults to 4.0 and
the test scene runs 10.0.

```
Godot.exe --path . scenes/test_foliage_small.tscn -- --coverage
```

Repaints the terrain flat magenta, renders from eye height at four pitches, and
reports bare-ground percentage for both clump styles. Pixels are classified by
hue (ground has red and blue clearly above green; grass is green; the grey sky
has all three equal), which stays valid under tonemapping and fog.

The test extends grass to the full terrain extent first. Without that, shallow
pitches see *past* the grass to bare terrain near the horizon, and the reading
measures where grass stops rather than how well it covers -- that inflated an
earlier version of this test from 9.5% to 38%.

## Distance LOD

Every chunk draws its tufts in two bands, each its own MultiMesh:

| Band | Tufts | Mesh (sprite cards) | Where |
| --- | --- | --- | --- |
| Near | all | full card: 2–4 quads, `blade_segments` rows | up to `lod_near_end` |
| Far | the `lod_far_keep` fraction | 2 quads, 1 row (4 triangles vs 24 at High) | `lod_near_end` to `lod_far_end` |

Past `lod_far_end` there is no grass geometry and the terrain carries the look.
That is the one idea above working as designed.

**Transitions are per tuft, not per pixel.** Each tuft carries a uniform random
LOD rank in `INSTANCE_CUSTOM.w`. In the `lod_fade` metres before `lod_near_end`,
tufts that do not survive into the far band shrink into the ground one by one,
at distances spread by rank. The field thins gradually instead of
screen-door dithering, which crawls as the camera moves. The survivors widen
across the same zone by `1/sqrt(lod_far_keep)` (capped at 1.8) so the thinner
field still covers the ground. At `lod_near_end` each one swaps to its far-band
copy. That copy has an identical transform, and its size is the exact
complement of the near copy's, so the swap is a mesh change in place. The far
band then thins out the same way over the last `lod_fade` before
`lod_far_end`. All of it is `lod_scale()` in `grass.gdshader`.

Godot's visibility ranges are used only as a **coarse cull** (fade disabled),
so a band's MultiMesh is not submitted at all where none of its tufts can show.
Godot measures that distance to the centre of the instance's AABB, so each
range is widened by the chunk box's half-diagonal. `FADE_SELF` was
deliberately not used: it would crossfade whole 16 m chunks at once.

Flowers follow the same bands but are never widened. A stretched bloom reads
as a smear.

`GrassLayer.lod_enabled = false` draws every tuft in the near band at every
distance. `--coverage` turns it off, because that test measures close-range
density and deliberate distant thinning would read as bare ground.

**Also fixed in Phase 2:** the chunk culling box used to span a fixed height
around y = 0, so on any terrain with real relief, hillside grass that was on
screen could be culled. Boxes are now sized from each chunk's actual tuft
height range.

## Carving (furniture on grass)

Whatever places an object emits on a `FoliagePlacementEvents` bus; the
`GrassLayer` listens (`grass_layer.placement_events = bus`). Neither side calls
the other. Netcode is deliberately undecided, and this is where it will attach:
a remote placement is emitted into the same bus, and each client carves its own
locally generated grass.

```gdscript
bus.place(&"blanket_7", catalogue.footprints(&"bordered-wool-rug", position, yaw))
bus.place(&"blanket_7", catalogue.footprints(&"bordered-wool-rug", position, new_yaw))  # a move
bus.remove(&"blanket_7")
```

**Footprints** come from the furniture packs carried over from PlacesOS, in
`content/furniture/*.json` (read by `FurnitureCatalogue`). The packs are
object-local with Y up; their yaw is in degrees. The footprint is:

1. the object's colliders whose underside is within 0.1 m of the ground, so a
   table carves but a wall shelf would not;
2. failing that, its geometry nodes that touch the ground. This is for rugs,
   which PlacesOS deliberately leaves non-colliding but which must still clear
   the grass.

Each becomes a `GrassCarver`: an oriented rectangle grown by `margin`
(default 0.2 m) with rounded corners. The margin exists because a tuft is not
a point. A clump is ~0.25 m across before scaling, so one rooted just outside a
rug stands its blades up through the rug.

**How a carve is applied.** Each chunk caches its *uncarved* scatter. A carve
refills only the chunks the footprint's bounds overlap, by filtering that cache.
Nothing is re-placed and the terrain is not re-sampled. Carving is a filter
*after* placement and never a test *inside* it. An earlier version skipped
carved tufts inside the placement loop, which skipped their random draws and
shifted every draw after them, so putting a blanket down reshuffled the rest of
the chunk. The split makes "same scatter minus the carved tufts" structural.
Carvers persist across a full `rebuild()`, so a quality change does not bring
grass back under the furniture.

Cost on the main thread, High, 10 tufts/m2 (~2,500 tufts per chunk): about
2 ms per chunk refilled, so 2–9 ms per carve (1–4 chunks). About 0.4 ms of that
is the filter; the rest is refilling the MultiMesh, which is written as one
packed buffer instead of per-instance calls.

`--carve` verifies all of this without a renderer. It checks that the scatter
is deterministic; that every chunk a footprint overlaps is refilled; that no
surviving tuft is inside a footprint, using independent `Transform3D` maths so
a rotation-sign error in either implementation shows; that the survivors are
exactly the uncarved scatter minus the carved tufts, in order; that a move
releases the old footprint; that carvers survive `rebuild()`; and that
removing everything restores the field bit for bit. Run windowed, it also reads
the MultiMesh buffers back to prove the packed layout.

## Trees

All woody species now use `TreeLowPolyBuilder` and the painted canopy shader
by default: oak, birch, spruce, fir, pine, rounded shrub and low hedge.
Every destination inherits this through `TreeLayer`; no profile migration or
style selection is needed. Ferns and cushion plants retain their card meshes.
The full species lineup is in
[reference/painted_foliage/](../reference/painted_foliage/lineup.png).

The approved oak/spruce prototype was extended to the other species. The
older Quaternius importer remains removed. `TreeCardBuilder` still owns the
species presets and builds the understory; its former woody construction is
available only through the review scene's `legacy_cards_for_comparison` flag.

### Clump normals

Painted masses blend each face normal 30% towards its rounded radial normal,
retaining broad facets. The card understory keeps the original clump/crown
normals. Every woody species has three seeded variants, with a fixed mesh
budget across quality levels; distance and shadow ranges provide the LOD.

### Leaf shader

`tree_painted.gdshader` draws opaque crown masses. It samples the shared
512px `tree_paint.svg` value atlas with mesh-local UVs, applies the location's
broadleaf or conifer palette, and paints warmer tops and cooler undersides.
It includes the shared world colour, weather, wind, distance tint and LOD
functions. `tree_leaf.gdshader` remains the alpha-scissored card material for
ferns/cushions and the legacy comparison. Both implement the runtime baker's
albedo and normal passes.

`tree_bark.gdshader` takes its colour per vertex from the species
(`FoliageProfile.bark_tint`), so one bark material serves oak brown and birch
white-and-black. Painted trunks use the atlas's brown-bark or birch-bark tile;
vertex alpha opts into paint so card understory stems remain unchanged.

The leaf atlas is `tools/blender/make_leaf_sprites.py`, run the same way as
the grass sprites. Its `.import` must keep mipmaps on. Each leaf is rendered
at its own depth, because coplanar overlapping leaves z-fight in Cycles and
come out as streaks.

### Wind

`tree_wind.gdshaderinc`: the whole tree bends as one body, from a gust sampled
at its root out of the *same* wind field as the grass, so a gust visibly
crosses the meadow and then the grove. Leaves add a small per-vertex flutter
on top.

**Canopy, bark and shadow proxy must sway identically**, or a crown slides off
its trunk and shadows swing out of step. So sway uses only inputs all three
carry identically: the instance origin and scale, and `UV2`, where every tree
part bakes normalised height and tree height the same way (`TreeMeshData`).
Anything new that builds a tree part must go through `TreeMeshData.add_vertex()`.

### Shadow proxies

Visible canopy and bark never cast shadows. Each tree has a proxy mesh drawn
`SHADOWS_ONLY`: one coarse ellipsoid per leaf clump plus a trunk, replacing
a full crown in every shadow cascade with a coarse interior shadow volume.
Painted broadleaf proxies use 66% of each mass's radii; conifer proxies sit
lower and narrower inside the skirts. This keeps them from protruding
through the planar canopy faces and leaving speckled self-shadow marks.

The proxy's visibility range is `tree_shadow_distance` (plus the chunk box's
reach). Beyond it, trees stop casting.

### Placement

`TreePlacer` works like `GrassPlacer`: a pure function of seed and chunk,
never networked, safe for `WorkerThreadPool`. Trees gather into groves, where
broad noise (~70 m features) crosses `tree_cover` and a jittered grid at
`tree_spacing` places the trees inside. Every cell makes the same random draws
whether or not it gets a tree, so changing cover never reshuffles the trees
that remain. Trees also need firmer ground than grass: a growth mask of at
least 0.6.

The jittered-grid loop itself — grove-thresholded accept, mask check, jitter,
species pick — is `GroveScatter.scatter_family()`. `TreePlacer` calls it five
times (trees, shrubs, conifers, ferns, then cushion plants — see *Bushes and
shrubs*, *Conifers*, *Ferns* and *Cushion plants*) into one `Placement`, and
`DebrisPlacer` calls it once more (see *Rocks, logs and fallen trees*). It
moved out to its own file
once a second placer needed the exact same thing, rather than being copied a
third time. The species pick takes a `weights: PackedFloat32Array`
(`_pick_species()`), not a single binary share, since conifers need a
three-way spruce/fir/pine split rather than the two-way split most other
families use — see *Conifers*. Ferns are a one-element `weights` array
(a single-species "family" still goes through the same call cleanly).

**Not done yet:** none of the three placers carve grass, and furniture does
not avoid any of them. Grass grows to the trunk, which reads fine.

### Cost

Grove view at eye level, High, 108 trees in the layer, RTX 3060 Ti: 2.23 mean
ms / 2.38 p95 ms, 763,060 primitives. Build cost: 19 ms per rebuild -- there is
no separate first-build cost now that there is no model-import step (that used
to add ~90 ms the first time the six Quaternius models loaded).

## Bushes and shrubs

**Current renderer:** both species use four low-poly painted masses from
`TreeLowPolyBuilder` (192 visible triangles each). The following card-shape
notes describe the retained legacy comparison; placement settings still apply.

Two more species on the same `TreeLayer`/`TreePlacer` pipeline: `rounded-shrub`
and `low-hedge`. Nothing downstream of placement changes — clump normals,
shaders, shadow proxies, impostors, streaming, quality — a shrub is simply a
`TreeCardBuilder.Species` with a short height, a crown that starts almost at
the ground (`crown_base` ~0.05–0.08) and no upward `lean`, so clumps spread
evenly into a dome instead of biasing up into a spire — `low-hedge` is simply
`rounded-shrub` rescaled shorter by its `Species.height`, not a different
source mesh. Both shrubs reuse the existing leaf atlas: `rounded-shrub` takes
the broad oak tiles, `low-hedge` the small birch ones. (An imported low-poly
alternative, reusing Quaternius `Bush_1.glb`/`Bush_2.glb` for both species,
existed alongside this through the tree-style comparison and was removed with
the rest of that path once card canopy won -- see *Trees*.)

**Density is independent of trees.** `shrub_cover`/`shrub_spacing`/
`shrub_share` are their own `FoliageProfile` fields, separate from
`tree_cover` — a location can have shrubs with no trees (`hedge_garden.tres`:
`tree_cover = 0`, `shrub_cover = 0.3`) or trees with no shrubs. They are still
placed over the *same* grove noise field as trees (see *Placement* above and
`TreePlacer`'s class comment), so where a location has both, shrubs naturally
cluster inside groves and fringe their edges rather than dotting the field
independently. Shrub spacing is deliberately much tighter than tree spacing
(2–3.5 m against 8–12 m): they are meant to read as undergrowth, not as sparse
as trees. They also tolerate rougher ground (growth mask ≥ 0.35, against
trees' 0.6) — real underbrush grows on slopes and marginal land a trunk would
not stand on.

`TreeLayer.debug_counts()` folds shrubs into the same total as trees (the HUD
prints it as "trees + shrubs"): they share every mechanism downstream of
placement, so there is nothing species-specific left to break out separately.

## Conifers

**Current renderer:** spruce and fir use eight and nine overlapping painted
tiers; pine uses five open, flattened needle masses over an exposed trunk.
The detailed card-construction history below applies only to the legacy
comparison path. Placement families, palettes and streaming are unchanged.

Three more species on the same `TreeLayer`/`TreePlacer` pipeline: `spruce`,
`fir` and `pine` (species indices 4–6). Placement, streaming, quality and
shadows are unchanged — the only two things that differ from a broadleaf
species are confined to `TreeCardBuilder` and `TreeLayer`:

- **Crown shape.** A broadleaf crown (`_build_broadleaf()`) scatters clumps
  through an ellipsoid, biased outward and (for trees) upward
  (`_clump_centre()`). A conifer crown (`_build_conic()`) instead climbs a
  single straight leader almost to the tip and hangs clumps in tapering rings
  round a cone (`_conic_clump_centre()`), narrowing by `Species.taper_power`
  towards the apex — spruce pinches to a point (`taper_power = 1.6`), pine
  stays blunter and more open (`taper_power = 0.7`, plus a much higher
  `crown_base` so the trunk shows bare below the canopy, the way a young
  pine's silhouette actually reads). Both builders still call the same
  `_add_card()` for the cards themselves — a conic species just hands it a
  synthetic bounding ellipsoid for the interior-darkening/outward-normal
  maths, not the shape clumps are actually placed in.
- **Majority-crown density, fixed 2026-09-20.** Clumps are grouped into
  evenly spaced TIERS (whorls) rather than placed independently at random
  height. An isolated render of the original tuning (16 spruce clumps up an
  11 m cone, independent random heights) showed the actual failure mode: not
  the crown_base/height fraction, which was already ~92% crown, but that
  clumps sat far enough apart vertically that bare trunk and bare branch
  spokes showed through the gaps, reading as ornaments hung on a pole rather
  than a tree. Raising `clumps`/`clump_radius` alone (still higher than the
  original values) helped but did not fix it outright — independent random
  placement can still roll an unlucky gap even at higher density, and with
  dozens of trees per grove an "unlikely" gap shows up constantly. Even tiers
  make a gap wider than one tier's band structurally impossible instead of
  merely improbable, and happen to be more botanically accurate too: real
  whorls form roughly one per year of growth, at fairly even intervals. Every
  tier gets at least one clump (`base_per_tier` is guaranteed ≥ 1); extra
  clumps go to the lowest tiers first, keeping the "more branch mass low
  down" look the old per-clump height bias was going for. A clump's radius is
  clamped to the cone's own local width at that height (`radius_here`,
  returned by `_conic_clump_centre()` alongside the position) so an enlarged
  clump cannot balloon past the silhouette near the narrow apex — but the
  floor on that clamp matters as much as the ceiling: too tight a floor
  starves exactly the tiers that most need to bridge to their neighbours,
  which showed as a visible gap in a sharply-tapering species (spruce's
  `taper_power = 1.6`) even after tiering. A guaranteed leader tuft is placed
  at a forced height fraction near the apex regardless of where the last tier
  lands, closing what was otherwise a bare multi-metre whip. Cost: roughly
  1.7–1.9× the visible triangles of the original tuning (spruce 1000, fir
  984, pine 590, against a broadleaf card tree's established ~545–900), still
  smooth at Ultra in `--bench --location=conifer_grove` (8.9 ms mean, 112
  fps, RTX 3060 Ti).
- **Stray branches, fixed 2026-09-20.** The tiering fix above closed vertical
  gaps but not a separate defect: isolated fir renders (five seeds, all
  showing it) had a low branch stretching out well past the cone's own
  silhouette with a clump dangling at the end, reading as a stray detached
  arm. Cause: `_conic_clump_centre()` placed a clump's CENTRE near the
  cone's outer skin (`reach` 0.65–1.0 of the local radius), and fir's
  gentler taper (`taper_power = 1.15` against spruce's `1.6`) keeps that
  local radius wide for longer going down the trunk, so a low clump could
  land much farther from the axis in fir than the same random draw would in
  spruce — and the branch connecting trunk to clump had to stretch to reach
  it. Fix: pull `reach` in to 0.35–0.65 (clump centres sit closer to the
  axis, so branches stay short) and widen the `r` ceiling to compensate (a
  clump's own cards still reach the true skin from a closer-in centre,
  see `_build_conic()`) — width of the silhouette is preserved, only how far
  the branch itself travels changes. The inner spray (fills the trunk/branch
  join) was also enlarged, and fir's own `clumps`/`clump_radius` raised
  further, since side-by-side with spruce it read gappier at the original
  majority-crown values — a wider, gentler-tapering cone has more surface to
  cover at the same relative density. Verified across five fir seeds in
  isolation (no stray branch on any of them) and in `conifer_grove` /
  `black_forest_test` grove views; all self-tests still pass.
- **A separate sprite atlas.** `tools/blender/make_needle_sprites.py` bakes
  `assets/foliage/legacy/needle_sprites.png` — four needle-cluster variants (upright
  dense/sparse for spruce and fir, looser dense/sparse for pine), the same
  2×2 layout and RGB-tone/alpha-coverage convention as the broadleaf
  `leaf_sprites.png`, so `TreeCardBuilder`'s UV math needs no per-atlas
  special-casing. `TreeLayer` builds a third leaf material, `_leaf_needles`
  (same `tree_leaf.gdshader`, the needle atlas bound instead), and routes to
  it by SPECIES — `leaf_material_for(species_index)`.

**A third, independent family (spruce/pine only since 2026-09-20).**
`conifer_cover`/`conifer_spacing`/`conifer_spruce_share` are their own
`FoliageProfile` fields (pine gets whatever share is left), alongside
`tree_cover` and `shrub_cover` — a location sets whichever families it wants,
typically conifers instead of broadleaf trees rather than both. Conifers are
placed over the same grove noise field as trees and shrubs (see *Placement*
above), at a growth-mask floor of 0.5 — between trees' 0.6 and shrubs' 0.35,
since real conifers hold mountain slopes a broadleaf trunk would not stand on
as well.

**Distant woodland tint.** `FoliageLocation._apply_terrain_shading()`'s far
horizon `GroveMap` tint used to key only off `tree_cover`; a conifer-only
location (no broadleaf trees at all, e.g. a real-world alpine import) would
have had no distant-woodland read on the horizon at all. It now keys off
`max(tree_cover, conifer_cover, fir_cover)` (conifer and fir share one side
of that comparison, since they share `conifer_palette`) and tints with
whichever palette belongs to the larger side.

**Not done yet:** no altitude-aware treeline gating (a `conifer_cover` that
fades out above some height) — see docs/GEO_IMPORT.md's asset wishlist for
why `swiss_alps_test` does not place any conifers yet even though the real
place is forested up to roughly 2000 m.

## Fir

Fir now uses the painted builder by default, including in fir-only locations.
Its independent placement family and profile controls below are unchanged.

A sixth, single-species family (species index 6): fir, `fir_cover`/
`fir_spacing` on `FoliageProfile`, `FIR_MIN_MASK = 0.5` in `TreePlacer` (the
same tolerance as conifer — ecologically the same evergreen, just placed
independently). Split out of the conifer family on 2026-09-20 at the user's
request: fir used to be a third share of `conifer_cover`
(`conifer_spruce_share`/`conifer_fir_share` splitting one pool three ways,
species indices 4-6), which meant a location could not have fir without also
getting spruce and pine. Now a location can run a pure fir stand, mix fir
with spruce/pine freely (they are placed independently over the same grove
field, so they cluster together the same way any two of these families do,
without being mutually exclusive on one shared grid), or skip fir entirely.

Nothing about fir's *rendering* changed: `Species.fir()` is untouched, it
still sets `is_conifer = true`, still draws the needle atlas through
`_leaf_needles`, and still takes its colour from `conifer_palette` (shared
with spruce/pine, not a separate palette field — both are needled evergreens
in the same colour family, and the atlas/material routing in
`leaf_material_for()` is by `is_conifer`, not by placement family). Only
`TreePlacer.place_chunk()` changed: fir gets its own `scatter_family()` call,
seed salt (`FIR_SEED_SALT`) and RNG stream, the same pattern every other
family already follows.

This is exactly the case `FoliageFamily` (see *Species registry*, below in
this doc — or its own class comment) was built to make cheap: `TreeLayer`
and `tools/geo/make_location_profile.gd` both picked up the new family from
one registry entry, no other code changed to learn about it. The three
existing conifer-bearing `.tres` locations (`conifer_grove`,
`black_forest_test`, `swiss_alps_test`) were hand-migrated to keep their
prior visual density: `conifer_spruce_share` was renormalised to the
spruce-vs-pine-only ratio it now means, but `conifer_cover` itself was left
UNCHANGED, at the same value fir's removal left behind, with `fir_cover` set
as a fresh, independent guess alongside it (not a slice taken out of the
other). `cover` gates a threshold on the shared grove noise field, not a
tree count (see `GroveScatter.scatter_family()`), so it still governs the
same "how much of the world is coniferous forest" extent it always did;
shrinking it to reflect fir's departure would have shrunk that boundary too,
not just fir's slice of it. That mistake was made once while building this
and caught by a visibly patchier, smaller treeline in an actual render, not
by reasoning about it in the abstract — see `FoliageFamily`'s class comment
for the fuller account, since the same trap is waiting for the next family
split too.

## Ferns

A fourth, single-species family: forest-floor fern (species index 7),
`fern_cover`/`fern_spacing` on `FoliageProfile`, `FERN_MIN_MASK = 0.25` in
`TreePlacer` (the most shade/damp-tolerant of the four families). Unlike
every other species, `TreeCardBuilder.build()` routes it to `_build_fern()`,
a THIRD clump-placement mode alongside `_build_broadleaf()`/`_build_conic()`:
clumps are sampled directly in a low band (`height * 0.05..0.4`) across a
flat disc, not biased through an ellipsoid crown the way `_clump_centre()`'s
`lean` biases a broadleaf's. That bias was tried first and was too weak to
pull a crown's centre of mass down convincingly -- the result read as a
sapling on a bare stick, not a ground-hugging plant, because an ellipsoid
crown's clump-centre inset stays small relative to how high off the ground
the ellipsoid itself sits. Sampling the clumps' own height directly, instead
of biasing an existing distribution, fixed it outright.

Its own atlas, `tools/blender/make_fern_sprites.py` ->
`assets/foliage/legacy/fern_sprites.png`: four frond-cluster variants, each a chain
of small rounded leaflets alternating off a curved stem and shrinking
towards the tip (`leaflet_polygon()`, a rounder taper than the conifer
atlas's `needle_polygon()`), fanned from a base point. Same 2x2 layout and
RGB-tone/alpha-coverage convention as the other two atlases, and a fourth
`TreeLayer` leaf material (`_leaf_ferns`) following the exact routing pattern
`is_conifer` established -- `is_fern` picks the atlas and the (fern-specific)
clump geometry.

Built as a speed check on the pipeline itself, after `--carve`/`--indoor`/
`--stream-test` turned out to be silently launching the interactive landing
screen instead of the test scene for a stretch of a session (see *Running
the test scene*) -- Blender atlas through a verified, in-game asset in
`black_forest_test`, one visual iteration included, took under 10 minutes.

## Cushion plants

A fifth, single-species family: alpine cushion plant (species index 8),
`cushion_cover`/`cushion_spacing` on `FoliageProfile`,
`CUSHION_MIN_MASK = 0.15` in `TreePlacer` (the most tolerant of every
family -- real ones hug bare rock and scree). Unlike fern, this one needed
no new clump-placement mode: a tight round dome is exactly what
`_build_broadleaf()` already produces for `rounded_shrub`, just at a far
smaller and denser scale (`height = 0.12`, `clumps = 6`, tight
`clump_radius`). First isolated render looked identical to fern's initial
"sapling on a stick" failure -- long bare trunk, foliage floating well above
it -- but this one WAS a rendering artifact, not a geometry bug: the scratch
scene had no ground plane, so `TreeMeshData.add_tube()`'s buried trunk root
(every species' bark tube starts at a hardcoded `y = -0.3`, meant to sit
under real terrain) rendered as a long stick in empty space. Adding a floor
plane to the check showed the true, correct result: a small, tight, low
dome sitting right on the ground. Good discipline to remember either way --
a "this looks like a known bug" reaction still needs the same actual check,
since here it would have led to needlessly rebuilding working geometry.

Its own atlas, `tools/blender/make_cushion_sprites.py` ->
`assets/foliage/legacy/cushion_sprites.png`: four tight-mound variants, dense
circular packing of small rounded leaflets (adapted from the fern atlas's
`leaflet_polygon()`, stubbier and packed radially instead of chained along a
stem), two of the four with a fraction of leaflets promoted to a bright
"bloom" tone. A fifth `TreeLayer` leaf material (`_leaf_cushion`) follows the
same `is_conifer`/`is_fern` routing pattern (`is_cushion`).

Placed on `swiss_alps_test` rather than `black_forest_test` -- unlike
conifers, cushion plants need no altitude gating to place honestly: they are
characteristic of exactly the open, at-or-near-treeline rocky ground that
whole crop already is, not something that reads as wrong above a line that
does not exist yet in the placement code. The cushion family's `E` entry in
`FoliageFamily.all()`'s `group_defaults` (see *Species registry*, below)
sends every future `E` (tundra/alpine) import the same way.

## Species registry

`FoliageFamily` (`foliage/trees/foliage_family.gd`) is the single list of
every species family that exists: which `TreeCardBuilder.Species` presets it
builds, which `FoliageProfile` fields drive its cover/spacing/share, and what
a real-world import should guess for it per Koppen climate group.
`TreeLayer._build_variants()` builds `_species` from
`FoliageFamily.all_species()` instead of a hand-written literal array, and
`tools/geo/make_location_profile.gd` walks `FoliageFamily.all()` to set every
family's starting cover instead of keeping its own copy of the same list
(see docs/GEO_IMPORT.md). Both reading the same registry is the point: a
species TreeLayer knows how to build but the importer does not know exists is
exactly how `fern_cover` went missing from every real-world import for a
while, only patched per-location by hand afterward -- see `FoliageFamily`'s
own class comment for the story.

Placement itself -- grove noise, growth-mask floor, seed salt, scatter mode
-- stays out of the registry and in `TreePlacer`/`GroveScatter`: that is real
per-family BEHAVIOUR, not a fact about what exists. `FoliageProfile`'s fields
also stay individually named `@export` vars rather than folding into the
registry, so a location is still hand-tuned in the Godot inspector, not
through this file. Adding a family still means giving it cover/spacing/share
fields on `FoliageProfile` and a placement block in `TreePlacer`, on top of
one `FoliageFamily.all()` entry -- this closes the two places that were
actually drifting, not every place a new species touches.

## Rocks, logs and fallen trees

A third, deliberately simpler layer: `DebrisLayer`/`DebrisPlacer`/
`DebrisBuilder`, `foliage/debris/`. Debris does not sway (no wind uniforms
needed), is not alive (no palette), and is cheap enough (14–80 triangles) to
cast its own shadow directly — so there is no canopy/bark/shadow-proxy split
and no impostors, just one MultiMesh per (species, variant) group per chunk.
`debris.gdshader` is a few lines: vertex colour as albedo, roughness/specular
constants, and the same `foliage_distance.gdshaderinc` horizon handover every
other foliage surface uses, so a distant rock fades towards the sky exactly
like the grass around it. `FoliageProfile.apply_to_debris_material()` pushes
only the four distance-tint uniforms — debris has no wind or palette to share,
so it does not go through `_apply_shared()` the way grass/trees/terrain do.

Two species, three variants each, all built by `DebrisMeshData` (the
non-swaying cousin of `TreeMeshData` — same `add_tube()`, no UV2 wind baking):

| Species | Variants | Built from |
| --- | --- | --- |
| `rock` | small / medium / large boulder | `add_lumpy_blob()`: a UV-sphere lattice with per-vertex radius jitter sampled from 3D value noise (correlated bumps, not per-vertex independent jitter, or it looks spiky instead of lumpy) |
| `deadwood` | two logs, one long fallen tree | `add_tube()`: a tapered cylinder lying on the ground. The fallen tree is longer and thicker (4–6 m against 1.1–2 m), not a different shape |

Deadwood's bark colour is `TreeCardBuilder.Species.oak()`/`.birch()`'s own
`bark_colour`, weathered duller and greyer — a fallen tree reads as a fallen
version of what is still standing nearby rather than a separately designed
grey stick.

**One family, not two.** Unlike trees-vs-shrubs, rock and deadwood do not need
as sharp a density split, so both go through one `GroveScatter.scatter_family()`
pass (`debris_spacing`/`debris_cover`, split by `debris_rock_share`) rather
than two. Placed over the same grove field trees and shrubs use — deadwood
comes from trees, so it should cluster where they are, and treating rock
outcrops the same way is a reasonable simplification. `debris_spacing`
defaults far wider than tree spacing (18 m): rocks and fallen trees are meant
to read as occasional accents, not a carpet.

### Default woodland floor

All outdoor tree-bearing profiles now also receive an automatic forest-floor
pass, using existing assets in `foliage/trees/` and `foliage/debris/`:
painted rounded bushes, rocks, logs and fallen trunks. No asset downloads
or per-destination edits are required.

`WoodlandScatter` in `foliage/util/` follows the trees' shared grove field
with cover `max(tree_cover, conifer_cover, fir_cover)`. This is area-based
woodland clustering, not a ring around each individual trunk. The tree
terrain mask excludes paths, water, steep slopes and above-treeline ground.
Debris tilts onto the sampled ground normal; bushes remain upright.

The profile's **Woodland floor** group controls the pass:

- `woodland_floor_enabled`: true by default; false restores authored-only scatter.
- `woodland_floor_density`: acceptance multiplier, default 0.55; zero disables it.
- `woodland_bush_spacing`: 5 m candidate grid, with randomized position and scale.
- `woodland_debris_spacing`: 12 m candidate grid; `debris_rock_share` controls the rock/log mix.

Independent random streams preserve existing tree and authored shrub/debris
positions. Density changes thin a stable candidate set. The extra plants
reuse existing MultiMesh groups, streaming, quality ranges, shadows and
tree impostors. Treeless and disabled/indoor profiles get no automatic pass;
explicit `shrub_cover` and `debris_cover` remain independent and additive.

`scripts/test_woodland_scatter.gd` verifies deterministic placement, unchanged
trees, masks, grove correlation, slope alignment and opt-out. Run it with
`--headless --path . --script res://scripts/test_woodland_scatter.gd`.
Omit `--headless` and append `-- --capture` for the Rolling Hills close-ups
in `reference/woodland/`. The runtime integration test covers the shared
menu, hide/show, furniture controls, return/re-entry and indoor safety.

**Not done yet:** no distance LOD or impostors (in scope, but past the point
one is worth billboarding, a rock is small enough on screen that culling it by
distance already costs nothing visible — unlike a tree's silhouette). No
placement variety beyond the six meshes above — no rock clusters, no
root-ball/branch detail on the fallen tree.

## Streaming

With `FoliageLocation.streaming` on (the default), ground, grass and trees
follow `focus`, normally the camera:

| Layer | Chunk | Out to | Built on the worker |
| --- | --- | --- | --- |
| `TerrainLayer` (ground) | 64 m | `view_distance` | height and normal sampling, vertex arrays |
| `GrassLayer` | 16 m | `streaming_radius` | placement, far-band subset, packed MultiMesh buffers |
| `TreeLayer` | 64 m | `view_distance` | placement, grouping, packed buffers |

All three run through one `ChunkStreamer` (`foliage/util/chunk_streamer.gd`).
Each frame, `update()` does three things. It frees chunks that left range.
It commits finished builds on the main thread until a time budget runs out
(3 ms each for grass and trees, 2 ms for ground). And it submits new builds
nearest-first, at most 8 in flight. The main thread only ever creates nodes,
MultiMeshes and meshes from finished data.

**The worker contract.** A build job gets a snapshot of its settings (an
object holding its own references), and each task holds a strong reference to
it. A rebuild on the main thread can swap in a new job, and in-flight builds
finish with the settings they started with; they are then discarded as
stale. Terrain providers must be safe to sample from several threads.
`NoiseTerrainProvider` is: `FastNoiseLite` reads and the painted-mask float
array are read-only. Carving stays main-thread state. A streamed grass chunk
with a carver over it is refiltered at commit rather than trusting the
worker's buffers.

**Settings changes do not block.** `rebuild()` on a layer that is already
streaming marks every chunk stale. The old chunks stay visible and are
replaced progressively within the budget. Only a first build (or fixed mode)
blocks, and that runs in parallel on the pool. A quality switch now stalls the
main thread for ~20 ms; blocking on the full rebuild took 2.8 s at High and
10.7 s at Ultra. `FoliageLocation.flush_streaming()` blocks until everything
around the focus is built, for screenshots and benchmarks.

**Fixed mode** (`streaming = false`) builds the old square round the origin:
grass `chunk_radius`, ground `extent`, trees `chunk_radius`. It still builds
through the streamer, so in parallel. The self-tests and capture modes use it,
so their results do not depend on the camera.

### Ground

`TerrainLayer` streams ground chunks at three detail levels: 48, 16 and 8
quads per 64 m side. Full detail (1.33 m, what grass and furniture were tuned
on) reaches past the grass. It ends at `max(streaming_radius, lod_far_end) +
32 m`, middle detail at 2.5× that, and coarse detail beyond. Moving between
rings rebuilds a chunk at its new level, and the old one stays up until the
new one commits.

A coarse edge cuts straight across bumps that a finer neighbour follows, so
chunks at different levels do not meet exactly. Every chunk hangs a
**skirt**, a vertical strip below each edge, deep enough to cover the error,
so the seams show ground-coloured wall instead of sky. The skirt faces
outwards whichever way the edge runs, and is wound for Godot's clockwise front
faces (the same trap as the terrain's own winding).

### Tree impostors

Past `tree_impostor_distance` each tree is a single camera-facing card.
`TreeImpostorBaker` renders every tree variant into one atlas at runtime, from
8 angles round the tree, in two passes rendered simultaneously: albedo, and
the clump normals in model space. Runtime rather than offline because the card
trees are generated per location and quality, and coloured by the location's
palette.

- **Lit live.** The impostor shader lights the baked normals under the real
  sun, so impostors match their trees as the light moves. The atlas passes
  through a viewport's sRGB encode; both samplers use `source_color` to undo it.
- **One draw per chunk.** All variants share one atlas (row = variant, column
  = view angle), and the row rides in instance custom data, so each chunk has a
  single impostor MultiMesh.
- **Handover.** Over 12 m past `tree_impostor_distance`, each pixel is drawn
  by the full tree *or* the impostor, never both, against the same
  screen-space dither (`tree_lod.gdshaderinc`). The shadow proxy uses a copy of
  the bark material with the handover off. In the shadow pass the "camera" is
  the light, and the distance test would throw the proxy away.
- **Frames.** Cards stand up round Y only, so trees seen from a hillside do not
  lean towards the camera. Each card picks the atlas column nearest its true
  view angle, in the tree's own frame, so instance yaw is honoured.
- **Bake cost.** About 1.3 s for 6 variants, asynchronous (one frame per view
  angle). Until it lands, and always under `--headless`, full trees draw at
  every distance. When it lands, every chunk currently on screen is redrawn
  in that same call, from data `_commit_chunk` already cached -- no worker
  round trip. This has to be atomic, not progressive: the impostor materials
  are shared across every chunk, so the moment they start fading full trees
  out past `tree_impostor_distance`, any chunk without its Impostors part yet
  would have neither a full tree nor a card there until the streamer got
  around to it. A quality change rebakes, because canopy detail changes the
  trees.

### Horizon handover

`foliage_distance.gdshaderinc` eases every foliage surface (terrain, grass,
full trees, impostors) towards `profile.distance_tint`. It runs from
`distance_tint_start` to `distance_tint_end`, at `distance_tint_strength`, and
is applied to albedo so it is lit like the surface. It is a stylised aerial
perspective under the environment's fog, and it helps each boundary out there
(grass ending, trees turning to cards, ground coarsening) go unnoticed, because
everything has cooled towards the sky by the same amount at the same distance.
It lives in its own include, not `foliage_common`, because that one is shared
with the atmosphere system.

The same function also applies the atmosphere's live weather, just before the
tint, because it is the one albedo step every foliage surface already shares:
**cloud shadows** and a mild **wet darkening** (see `docs/ATMOSPHERE.md`,
*Skyscape* and *Wet ground and mist*). Wet soil gloss and puddles are in
`terrain.gdshader`, gated by the bare-ground mask so grassed terrain keeps
matching the grass.

With no `AtmosphereSystem` present, the shadow global and `atmosphere_wetness`
are both 0 and every one of these terms reduces to the old value, so
self-tests are unaffected. `--coverage` was checked against the committed
baseline: both runs land within the same run-to-run noise of about 0.5%.
`TreeImpostorBaker` zeroes `foliage_live_weather_weight` on its bake copies,
so shadows and wetness are never baked into impostors.

The atmosphere system could drive the tint colour
by time of day; nothing does yet.

### Close-range terrain detail

The Phase 5 half of the bare-ground work (see *Why 5 and 6 both exist*). In
`terrain.gdshader`, fading out by 40 m:

- two octaves of the colour noise at turf scale (`terrain_detail_scale`, 3 per
  metre), shifting the palette lookup, so the speckle can only ever be the
  location's own greens;
- darker hollows, and a detail normal from the same field, so the speckle
  catches the light like blades rather than a print;
- `terrain_under_grass_shade`: close up, ground that grass grows on sits darker
  than the grass above it. Ground lighter than the blades was what made the
  gaps read as pale flat sheets. Bare ground (paths) keeps its colour.

No geometry, no draw calls. The coverage test cannot measure this: it repaints
the terrain magenta. Judge it in motion.

## Locations

A place's whole outdoor look is one `FoliageProfile` saved as a `.tres` in
`content/locations/`, plus one `FoliageLocation` node that reads it. The shape
of its ground is a separate `TerrainProfile` in `content/terrain/`, which the
`FoliageProfile` points at through `terrain`. The
location node builds the ground mesh, `GrassLayer`, `TreeLayer` (trees and
shrubs) and `DebrisLayer` (rocks and fallen trees). It wires the growth mask
into the terrain, applies fog to the scene's `WorldEnvironment` and the
quality preset to the scene's sun. `set_profile()` swaps the whole place;
press `N` in the test scene.

| Location | What it shows |
| --- | --- |
| `test_meadow.tres` | The reference meadow, with a painted growth mask: a winding footpath past the spawn point and a clearing, plus light shrub cover |
| `dry_field.tres` | The same system restyled from data alone: dry palette, taller sparser grass, few oaks, warmer fog, different seed, scrubby shrubs and mostly-rock debris |
| `wide_valley.tres` | The streaming test: ~38 m landforms over 420 m, groves, distance tint to 900 m, denser shrubs and deadwood inside the groves |
| `rolling_hills.tres` | Hills and valleys (see *Terrain profiles*): 45 m hills rising out of flat low ground in hill country, open plain elsewhere, flat-floored valleys winding through both, and the ground rising 90 m at the edge of the 8 km world. `wide_valley`'s look otherwise |
| `hedge_garden.tres` | Shrubs with **zero trees** (`tree_cover = 0`) -- proves the two covers are genuinely independent |
| `indoor_room.tres` | `enabled = false` |

**Indoor skip.** A profile with `enabled = false` makes `FoliageLocation`
build *nothing*: no nodes, no materials, no noise or palette textures, no
terrain provider, and no change to the sun or environment. An indoor room's
lighting is not this system's business. Switching an outdoor location to an
indoor one frees everything it built. `--indoor` checks all of this headless.

**Growth mask.** `profile.growth_mask` is red = grass, 0 = bare, stretched over
`mask_bounds`. The terrain provider copies it once into a float array
(`TerrainProvider.set_painted_mask`) and samples it bilinearly. The placer asks
hundreds of thousands of times per build, and the float array also stays free
of `Image` calls for the streaming worker threads. Grass and trees both read it
through `get_growth_mask()`, and the terrain shader colours bare ground from
it. Import masks **Lossless with `detect_3d` off**: VRAM compression would
leave the CPU copy unreadable. The meadow's mask is generated by
`tools/masks/make_meadow_mask.gd`; a real location's would be painted.

Close up, a path's edge still shows the straight bottom edges of the grass
cards against the dirt. That is the card look at close range; Phase 5's
ground detail softens it (see *Close-range terrain detail*), and Phase 6 would
address it further. It is not a mask artefact: from above, the mask blends
smoothly.

**Atmosphere.** `fog_colour` and `haze_amount` are applied to the
environment as depth haze reaching to the edge of the drawn ground (see
*Distance haze* in [ATMOSPHERE.md](ATMOSPHERE.md)); `distance_tint` goes to every foliage shader (see *Horizon
handover*). If the atmosphere system (in `atmosphere/`, being built in parallel)
is in a scene, it drives fog every frame and overrides this write, using the
profile's fog as its base.

## Adding foliage to a new location

1. Create a `FoliageProfile` `.tres` in `content/locations/`: copy
   `test_meadow.tres` or `dry_field.tres` and change it. Nothing about a
   location should live in code.
2. Set `world_seed`. Everything about the scatter derives from it, which is why
   grass and trees are never networked (see below).
3. Add a `FoliageLocation` node, assign the profile, and point `sun` and
   `world_environment` at the scene's own. For real elevation data, assign
   `terrain` a `TerrainProvider` before the node enters the tree. Otherwise it
   uses gentle procedural noise.
4. That is all. The ground mesh already carries the grass layer's terrain
   material, which is what keeps grass and ground in sync. Never build a
   terrain material yourself.
5. Author tree families, shrubs and debris with their own cover values.
   `tree_cover` defaults to 0.3; explicit shrub/debris cover defaults to 0.
   Tree-bearing locations also get the default woodland-floor pass above.
   Set `woodland_floor_enabled = false` for authored-only placement.

**Indoor locations** use a profile with `enabled = false`, or no
`FoliageLocation` at all. Either costs nothing, and nothing else needs to know
whether a place has grass.

### Terrain

Implement `TerrainProvider`: `get_height()`, and optionally `get_normal()` and
`growth_mask_for(x, z, normal)`. Override `growth_mask_for()`, not
`get_growth_mask()`. It should multiply in `sample_painted_mask()`, as
`NoiseTerrainProvider` does, or the location's painted mask stops applying.
`NoiseTerrainProvider` is the procedural one the test scenes use; real
locations will subclass and read elevation data.

**Chunk work goes through a `TerrainTile`.** Grass placement and ground meshes
sample `get_height()` once per grid point into a tile and answer everything
else from it, instead of paying several height samples per tuft. So a chunk's
cost follows its area, not its tuft count or how many noise layers the
landform uses. Placement tiles sit on `TerrainProvider.TILE_SPACING`, which is
the near ground mesh's lattice, and interpolate across the mesh's own
triangles. So grass roots lie exactly on the drawn surface, and the slope
grass thins by is the slope the shader paints rock by. The defaults
(`tile()`, `build_chunk_mesh()`) work for any provider; a heightmap-backed one
should override them and read its grid directly. Trees still query the
provider directly: at about 50 candidates per chunk, a tile would cost more
than it saves.

Measured on `wide_valley` (see the H1 note under *Measuring*): grass placement
went from 15.6 to 10.9 ms per 16 m chunk, and a near ground chunk from 8.3 to
5.8 ms, with identical tuft counts.

### Terrain profiles

`TerrainProfile` (`foliage/terrain/terrain_profile.gd`, files in
`content/terrain/`) holds the shape of the ground. `FoliageLocation` turns it
into a `LandformTerrainProvider`, seeded with the location's `world_seed`. A
`FoliageProfile` with no `terrain` gets `TerrainProfile`'s defaults: gentle
rolling ground. The layers are:

| Group | What it does | Off when |
| --- | --- | --- |
| World | The world is a bounded square, `world_size` (8 km), centred on the origin. Nothing grows outside it; the ground carries on as scenery. `edge_rise` lifts the ground towards the boundary to close the skyline, which is where mountains will stand later. | `edge_rise = 0` |
| Rolling ground | The original two-octave landform: `landform_*` and `detail_*`. | Never |
| Hills | Warped fractal noise, eased into rounded hills above a threshold, so hills stand out of flat low ground. A broad region field splits the world into hill country (`hill_country`, the share of the world) and open plain. | `hill_height = 0` |
| Valleys | The zero-crossings of a meandering noise field, pulled down to a flat floor `valley_depth` below the rolling ground. They cut through any hill in the way, widening their walls to stay near `valley_wall_slope`. | `valley_depth = 0` |
| Altitude | Rock above `rock_line`, snow above `snow_line`; see *Altitude and far shading*. | Lines above the landform (default) |

**Hill steepness follows `hill_height` over `hill_scale`.** About 1:20
(`rolling_hills`: 45 m over 900 m) gives a median hill slope of 9°, with 90%
of hill ground under 19°. The first tuning, 55 m over 420 m, gave a median of
24°, which is mountain flank, not rolling hills.

**Cover shares are measured, not assumed.** On configure, the provider samples
its hill and region noise on a 64×64 grid across the world and takes
thresholds from the actual distribution. So `hill_cover = 0.45` really
raises 45% of hill country, whatever octaves and warp do to the noise.

**Valley width uses the gradient at each point.** Distance to a valley's
centre is |value| / |gradient|, with the gradient sampled locally, which costs
two extra noise calls. A single world-wide mean gradient was tried first, and
valleys came out at half to a third of their asked width, because the warped
noise is much steeper in some places than in others.

The four older locations moved their `landform_*` values into
`content/terrain/<name>.tres` unchanged. Their heights are bit-identical to
before: 2,000 sample points each, maximum difference 0.

Measured on `rolling_hills` (8 km world, headless):

- **Shape:** heights run from -8 to 132 m (hills plus the edge rise). 53% of
  the world is flatter than 4°, 12% is valley floor, 0.6% is steeper than 25°,
  and the steepest point is 43°.
- **Cost:** grass placement takes 11.6 ms per chunk, against 10.9 on flat
  ground, because the tile absorbs the extra layers. A near ground mesh takes
  10.3 ms, against 5.8. Configuring the provider takes 2 ms.
- **`--wide`:** frame times are within run-to-run noise of `wide_valley` (mean
  4.9 against 4.7–5.0 ms, p99 9.3–9.6 against 9.1–10.4 ms). Streaming runs
  slightly further behind: 11.5 chunks waiting on average, against 8.

Mountains are the next layer. They will be additive, like the hills.

### Horizon ring

Ground used to end at `view_distance` (300–900 m), leaving fog and sky
beyond. `FoliageLocation` now also streams a second `TerrainLayer`, the
horizon (`TerrainLayer.configure_as_horizon()`). It uses 1 km chunks at 16 m
spacing out to 2.5 km and 32 m beyond, reaching `quality.horizon_distance`:
2.5 / 4 / 6 / 8 km from Low to Ultra. It is limited to the world plus 2 km of
scenery beyond its edge. It shares the ground's material (same palette,
distance tint, cloud shade and wetness), casts no shadows, and uses grid
normals, since exact ones would quadruple its samples for lighting nobody can
see out there. Streaming only: the fixed-square self-tests do not build it.

**Handover without gaps or doubled ground:**

- **Chunks the ground fully covers are skipped.** The ground layer recomputes
  its disc only when the focus crosses one of its 64 m chunks, so round the
  camera it is only guaranteed out to `view_distance` minus a chunk diagonal
  and one horizon cell. Horizon chunks wholly inside that radius are not
  built.
- **Where the two overlap, the horizon is sunk.** The terrain shader's
  instance uniform `terrain_sink` (depth, start, end) drops horizon vertices
  8 m within `start` of the camera, easing back to true height by
  `view_distance`. So the horizon never pokes through the ground. And while a
  ground chunk is still streaming in, you see the horizon a few metres low
  there, not sky.
- **The sink must exceed the horizon mesh's own error.** At 16 m spacing the
  mesh sits at most 1.1 m above the true ground on `rolling_hills`, 0.6 m on
  `wide_valley` and 0.1 m on `test_meadow`. The 32 m level (2.1 m) only
  exists beyond 2.5 km, which never overlaps the ground.
- **The horizon's wanted set refreshes on the ground's 64 m step**
  (`refresh_step`), not its own 1 km chunks. Otherwise its cut-out would lag
  up to a kilometre behind the camera and open holes.

**Skirt depth is now measured per chunk.** `build_chunk_arrays(..., -1)`
samples every edge segment at quarter points against the true ground and
hangs skirts twice the worst error plus 0.5 m. Measured depths are 0.5–0.8 m
on every location, against 3 / 7 / 13 m from the old spacing formula. The
old formula was far too deep on flat meadow, and nothing guaranteed it was
deep enough on a steep valley wall.

**Seeing it.** The test scene's camera far plane is now 12 km (was 3 km).
`rolling_hills` thins its fog to 0.0003 and runs its distance tint out to
4 km, so the hills fade into haze rather than a fog wall. Locations with the
old heavy fog build the ring but mostly hide it.

**Cost** (`--wide`, High, 132 horizon chunks):

| | Mean frame | p99 | Streaming backlog |
| --- | --- | --- | --- |
| `rolling_hills`, before | 4.85–5.04 ms | 9.3–10.2 ms | 11.5 chunks |
| `rolling_hills`, after | 5.70 ms | 10.9 ms | 13.6 chunks |
| `wide_valley`, after | 5.18 ms (was 4.66–5.05) | 10.5 ms | 8.2 chunks |

A horizon chunk builds in 23 ms at 16 m spacing and 6 ms at 32 m, on the
worker pool.

Seen from 180 m and 450 m up, there is no seam or gap at the 600 m handover.
Two problems that showed from altitude are fixed under *Altitude and far
shading*.

### Altitude and far shading

**Rock and snow by height.** A new `TerrainProfile` group, Altitude:
`rock_line`, `snow_line`, `altitude_band` and `snow_colour`. The defaults
(5 km and 6 km) are above any current landform, so this is off until
mountains exist.

- **One formula, two places.** `TerrainProfile.altitude_rock()` and
  `altitude_snow()` feed the grass mask (`LandformTerrainProvider.growth_mask_for`),
  and `terrain.gdshader` computes the same thing. So grass stops exactly where
  the ground turns to rock. On a test terrain with the bands inside its height
  range, none of the 881 samples above the rock band still grows.
- **Treeline.** Trees need mask ≥ 0.6, so they give out a little below the
  rock line, with no setting of their own.
- **Snow** lies only on ground flatter than about 45°.
- **Not part of `bare`.** Rock and snow stay out of the shader's `bare` term,
  because the atmosphere's puddles are gated on it. Rock soaks darker in rain;
  snow does not.
- **Free when out of reach.** When the bands start above the highest ground a
  profile can make, the grass mask skips the extra height sample, which is the
  common case today.
- `FoliageLocation._apply_terrain_shading()` pushes the values into the
  ground material whenever it is rebuilt.

**Far woodland.** Trees are drawn to `view_distance`, so wooded hills on the
horizon read as bare lawn. `ZoneMap` (formerly `GroveMap`) bakes the tree placer's grove noise into
a 1024² texture over the horizon area, about 12 m a pixel. It takes 88 ms per
location build, and matches the placer's noise to within one 8-bit step.
From 75% of `view_distance` outwards, the terrain shader darkens the ground
towards `tree_palette[1]` where GroveScatter's threshold says woods, and keeps
it off steep ground, paths, rock and snow. The map stores raw noise, so a
cover change needs no re-bake.

**Colour-noise tiling.** Two layers of repetition showed once kilometres of
ground were visible:

- **The broad octave** repeated every ~77 m in an axis-aligned grid.
  `foliage_colour_field` now cross-fades it with a rotated copy at another
  scale, under a much broader (~470 m) rotated sample. Neither lattice
  survives the blend. Warping the broad octave's coordinates was tried first:
  strong enough to hide the grid, it made the ground look like marbled liquid.
- **The fine octave's ~29 m tile** still showed as a lattice in the middle
  distance. The terrain now fades it into the broad octave between 250 and
  600 m, through `foliage_palette_t_far()`. Grass (at most ~170 m) keeps
  calling `foliage_palette_t()`, which is unchanged, so grass and ground still
  match wherever both exist. No ring is visible at eye level.

This does change the colour pattern of grass, trees and terrain slightly in
every location, because the broad octave is now a blend. The palette and
contrast are unchanged.

**Cost:** within noise. `--wide`: `rolling_hills` 5.37 ms mean (was 5.70 after
H3), `wide_valley` 5.21 ms. `--indoor`, `--stream-test` and `--carve` pass.

**Triplanar rock, and altitude on a heightmap location.** Added for
`docs/GEO_IMPORT.md`'s "Asset wishlist" (`swiss_alps_test`: real relief with
zero altitude shading, and a flat, unbuilt rock material).

- **Heightmap altitude.** `HeightmapTerrainProvider.altitude` is an optional
  `TerrainProfile`, reusing the SAME resource and formulas as above rather
  than a second mechanism. `FoliageLocation.build()` wires it from
  `FoliageProfile.terrain` whenever a heightmap location sets one --
  `profile.terrain` still builds no landform there (a heightmap location's
  ground comes from its `.r32` file, unchanged), only its Altitude group is
  read. `HeightmapTerrainProvider.growth_mask_for()` gates on it exactly like
  `LandformTerrainProvider`'s does, with its own "free when out of reach"
  guard: it measures its OWN grid's real min/max height once at load
  (`height_range()`), rather than a landform's amplitude-sum estimate.
- **Rock and snow are no longer a flat colour.** `foliage_triplanar_noise()`
  (`foliage_common.gdshaderinc`) samples the shared colour-noise texture on
  all three axes, weighted by the surface normal, and both rock (slope AND
  altitude, one shared material -- see below) and snow read a shared sample
  of it, so the two never show mismatched noise where they meet.
  `TerrainProfile.rock_scale`/`rock_facet_strength` tune it; both default off
  enough to be a no-op saving (`rock_facet_strength = 0` is the old flat
  look).
- **Slope rock and altitude rock combined into one mix.** They used to be two
  sequential flat-colour mixes toward the same target colour; a steep face
  at rock-line altitude -- exactly the common case on a real mountain --
  muddied doubly toward it. Now `rock_amount = max(rock, alt_rock)` drives
  one textured mix.
- **Verified on the real asset**, not just a synthetic profile:
  `swiss_alps_test`'s heightmap (1130-4096 m) with `rock_line = 2600`,
  `snow_line = 3300` (picked from the Bernese Oberland's real treeline plus a
  margin): ~26% of the crop still grows, ~72% reads as rock, ~20% as snow.
  A camera at the crop's steepest rock-band point (2000, 3760; ~76°) shows
  grass rooted in a near-vertical face before this fix and a textured rock
  face after it (before/after renders, and a pixel-difference check that the
  triplanar sample changes the image, not just the uniforms). Existing
  procedural locations are untouched, on both inputs to `rock_amount`: none
  sets `rock_line`/`snow_line` below the shader default (5000/6000), so
  `alt_rock` stays 0; and `terrain_slope_begin` (0.55, ~63°) is well above
  the steepest point any of them reaches (43° on `rolling_hills`, this
  system's steepest terrain -- see *Terrain profiles*), so `rock` was
  already always 0 too. Confirmed by rendering `rolling_hills`' own steepest
  point (44° at the sampled resolution) with and without the triplanar
  break-up: identical images. The triplanar branch is unreached on any
  current location but `swiss_alps_test`.
- **Not built:** a triplanar detail normal (the colour break-up alone already
  fixes the stretch this was about); altitude-aware tree/conifer placement
  (a treeline) for `swiss_alps_test`, which stays treeless -- a placement
  rule, not a shading one, and a separate, larger piece of work.
- `--heightmap-test` gained three checks: `growth_mask_for()` is an untouched
  1.0 with `altitude` unset (regression guard for every heightmap location
  before this); it gates to ~0 above `rock_line` and stays 1.0 below it once
  `altitude` is set; and a painted mask still multiplies in underneath the
  altitude gate rather than being replaced by it.

### Ground collision

`TerrainCollision` (`foliage/terrain/terrain_collision.gd`) streams one
`StaticBody3D` with a `HeightMapShape3D` for each 64 m chunk within
`FoliageLocation.collision_radius` (128 m) of the focus. It sits on physics
layer 1. Heights are sampled on the worker pool, at whole metres, from
`TerrainProvider.tile()`, which follows the drawn mesh's triangles. The grid
is 1 m because `HeightMapShape3D` spacing is fixed there, and scaling collision
shapes to change it is unreliable across Godot's physics engines.

- **The radius is fixed, not part of the quality preset,** so what can be
  walked on never depends on graphics settings. It only has to cover what can
  touch the ground soon.
- **One focus only.** Covering several far-apart players (client, server or
  both) is part of the deferred netcode decision.
- **Spawn check.** Before trusting the ground to hold something, a spawner
  should check `has_collision_at(position)`. The first build blocks, like the
  ground's, so the spawn area is always solid.
- **Built once per `build()`.** A quality change leaves it alone.
- **Off switch:** `collision_enabled = false`. Indoor locations build none.

**Self-test** (`scripts/test_terrain_collision.gd`, headless, on
`rolling_hills`):

- **Raycasts:** 500 cast inside the radius, none missed. The worst gap to
  the drawn surface is 0.008 m, against a 0.15 m tolerance.
- **Crates:** 40 of 0.6 m, dropped from 4 m. None fell through, and all 40
  came to rest sitting on the surface, the steepest on 11°. The test uses
  crates because balls roll down any slope forever and prove nothing about
  resting.
- **Streaming:** after a 745 m jump the new area is solid, the old one is
  freed, and nothing is held beyond the radius.
- **Wiring:** an outdoor `FoliageLocation` builds collision; an indoor one
  builds none.

**Cost:** a chunk takes about 11 ms to build on a worker (4,225 heights).
Streaming holds about 17–24 chunks. In the `--wide` sprint at 30 m/s, frame
time rose about 0.4–0.5 ms on average (5.80–5.92 ms, against 5.37). The
pending count now includes collision chunks.

**Deferred:** water on valley floors is H5.1, and authored heightmaps
(`HeightmapTerrainProvider`) are H5.2.

Note the winding in `build_chunk_mesh()`: terrain is **not** `cull_disabled`
(double-siding a surface that large is wasted fill), so emitting indices in the
other order makes the whole terrain face downwards and vanish. That failure
shows as a *white* ground — you are seeing the sky's ground hemisphere through
the grass — which does not read as a culling bug at first glance.

## Determinism and multiplayer

Grass placement is a pure function of `(world_seed, chunk_x, chunk_z)` via
`GrassPlacer.hash_chunk()`. Every client generates identical grass locally and
**no grass data is ever sent over the network**. When something is placed that
carves grass, the *placement event* syncs and each client rebuilds its own
chunks — so players far apart cost each other nothing.

The hash is hand-rolled rather than using Godot's `hash()`, which carries no
cross-version stability promise; a change there would silently reshuffle every
field in the game on an engine upgrade. It is 32-bit because GDScript ints are
signed 64-bit: the usual splitmix64 constants cannot be written as literals, and
`>>` on a negative int is an arithmetic shift, which silently breaks any mix
assuming a logical one. Verified to give 6,561 distinct values over an 81×81
chunk grid with no correlation between neighbours.

Worth knowing: grass is cosmetic and never affects gameplay, so clients
disagreeing by a blade would be harmless. Determinism is here because it is
nearly free and makes carving reproducible — grass does not reshuffle when
someone puts a blanket down. It is deliberately *not* worth contorting the
design to guarantee bit-identical float results across GPUs and platforms.

## Measuring

`--bench` disables vsync before sampling. Without that, every quality level
reports exactly the refresh interval (16.67 ms on a 60 Hz panel) and the
benchmark measures the monitor rather than the renderer.

Under `--headless`, MultiMesh instance buffers are not kept either:
`get_instance_transform()` returns junk. Anything that inspects what a chunk
holds reads `GrassChunk.shown`, the result it was filled from, rather than the
GPU side.

Do not use `--headless` for perf work. Its dummy renderer reports `0` for
`RENDER_TOTAL_DRAW_CALLS_IN_FRAME` and `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, so a
headless "benchmark" measures nothing.

Frame times are reported as mean **and 95th percentile**. The 95th matters more
here: streaming and chunk rebuilds produce occasional long frames, and a mean
happily hides a hitch a player feels.

### Phase 1 baseline

Small meadow (81 chunks, 16 m each), 1920×1080, **NVIDIA RTX 3060 Ti**:

| Level | mean ms | p95 ms | draws | primitives | grass tufts | rebuild |
| --- | --- | --- | --- | --- | --- | --- |
| Low | 2.31 | 2.38 | 179 | 320,135 | 52,252 | 410 ms |
| Medium | 2.76 | 2.78 | 179 | 674,984 | 100,134 | 774 ms |
| High | 3.63 | 3.70 | 179 | 1,613,996 | 201,032 | 1579 ms |
| Ultra | 8.52 | 9.09 | 179 | 6,555,852 | 357,686 | 2785 ms |

Measured with `SPRITE_CARDS` at 10 tufts/m2.

**This GPU is well above the GTX 1660 / RX 5600 target**, so these are
optimistic and are not a pass mark against the brief's 60 fps goal. They are
useful as a *shape*: cost scales with tuft count roughly as expected, and the
static render cost is not currently the problem.

**The rebuild column was the problem.** 131–834 ms of single-threaded
placement was a multi-frame stall on every quality change. Phase 2 took
carving off that path; Phase 5 moved placement onto `WorkerThreadPool` and
made settings changes progressive. See *Phase 5*.

### Phase 2

Same scene, GPU and settings as the Phase 1 baseline, with LOD on:

| Level | mean ms | p95 ms | draws | primitives | grass tufts | rebuild |
| --- | --- | --- | --- | --- | --- | --- |
| Low | 1.29 | 1.38 | 147 | 161,694 | 52,257 | 431 ms |
| Medium | 1.53 | 1.62 | 179 | 307,464 | 100,240 | 830 ms |
| High | 2.21 | 2.38 | 199 | 798,256 | 201,223 | 1665 ms |
| Ultra | 6.47 | 6.67 | 211 | 4,935,096 | 357,636 | 2978 ms |

Primitives halve at High (1.61M to 0.80M) and mean frame time drops 39%. The
gain is smallest at Ultra, where `lod_near_end` is 55 m and most of this small
meadow is inside the near band. Draw calls rise slightly: each chunk now has up
to four MultiMeshes, most of them culled by visibility range. The window
reported 1920x1061 (a title bar) for this run.

Rebuild time is unchanged. Placement still dominates it, and it is still Phase
5's job to move it off the main thread. Carves no longer go through it at all
(see *Carving*).

### Phase 4

`--bench` now applies each level through `FoliageLocation.set_quality()`, so
trees and the sun's shadow settings change with the level:

| Level | mean ms | p95 ms | draws | primitives | grass tufts |
| --- | --- | --- | --- | --- | --- |
| Low | 1.38 | 1.39 | 118 | 108,610 | 50,624 |
| Medium | 2.66 | 2.78 | 157 | 254,866 | 97,271 |
| High | 2.27 | 2.38 | 254 | 784,838 | 195,051 |
| Ultra | 5.86 | 6.06 | 353 | 4,738,085 | 346,650 |

Tuft counts are slightly lower than Phase 2's because the meadow now has a
path and a clearing. Low draws less because it uses a single shadow cascade.

**Read the sub-3 ms rows with care.** Medium coming out slower than High is
repeatable in this configuration, but it is not caused by any Medium setting.
Moving it to 4 cascades, soft shadows or an 80 m shadow distance each left it
at 2.6–2.9 ms. Rebuilding grass alone reorders the levels again (Low 1.90,
Medium 1.98, High 2.59). At 400–700 fps this machine's frame time moves
0.3–0.5 ms between runs and configurations regardless of workload, most likely
GPU clock states. Don't rank levels by these numbers; the GTX 1660-class
measurement the brief asks for is what will.

### Phase 5

**Streaming flythrough** (`--wide`): the wide valley, 900 m in a straight
line at 30 m/s, 3 m above the ground, vsync off, RTX 3060 Ti. Frames that
include the test's own screenshot readback are excluded.

| Level | mean ms | p95 | p99 | worst | pending chunks, mean / worst |
| --- | --- | --- | --- | --- | --- |
| Low | 1.60 | 1.85 | 2.38 | 13.3 | 0.7 / 48 |
| High | 4.05 | 6.67 | 7.36 | 12.9 | 8.6 / 111 |
| Ultra | 11.61 | 13.53 | 16.67 | 25.2 | 120 / 238 |

At High about 5,100 trees, 160 grass chunks and 300 ground chunks are live
round the camera. **Ultra does not keep up at sprint speed:** its far rings
lag, averaging 120 pending chunks. That is 166 m of grass at 1.8× density plus
a 900 m view. Builds go nearest-first, so what lags is the edge, not what is
under the player. Ultra's mean frame is mostly the GPU cost of its grass
(4.7M primitives in view).

**`--bench`** now measures the streamed world round the spawn point, not the
old fixed square, so it is **not comparable** with the Phase 1–4 tables. At
High it covers 403k grass tufts, against 195k before.

| Level | mean ms | p95 ms | switch | caught up | draws | primitives | grass tufts |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Low | 1.39 | 1.39 | 21 ms | 1.4 s | 120 | 136,358 | 29,614 |
| Medium | 1.64 | 1.67 | 18 ms | 1.5 s | 216 | 316,302 | 112,862 |
| High | 2.76 | 2.78 | 21 ms | 3.8 s | 440 | 1,071,024 | 402,747 |
| Ultra | 7.69 | 8.19 | 27 ms | 12.6 s | 905 | 6,006,698 | 1,666,954 |

*Switch* is how long `set_quality()` blocks: what a player feels. *Caught
up* is time until every chunk is rebuilt and the impostors rebaked, while the
game keeps running. Draw calls grew, with ground chunks and per-chunk tree
groups out to `view_distance`; they are the next thing to watch on the GTX
1660 target.

**Also fixed in Phase 5:** `NoiseTerrainProvider` only applies
`landform_scale` and `detail_scale` when its seed is set. The test scene had
set the scale afterwards, so every location so far has rendered at the default
260 m scale, never the 90 m it asked for. `FoliageLocation` now reconfigures
the provider, and `test_meadow.tres` / `dry_field.tres` pin
`landform_scale = 260` so they look exactly as they did.

### Fixed after a full-system review

Four bugs found by reading the streaming, carving and location code closely,
all in states the fixed-square self-tests never reach (they only exercise the
first build):

- **Tree impostors popped in and out for one frame per chunk.** Fixed above,
  under *Tree impostors*.
- **`set_profile()` could mutate a caller-supplied `TerrainProvider` while an
  old layer's worker was still reading it.** `queue_free()` only defers
  freeing to the end of the frame, so `build()` could reach
  `terrain.set_painted_mask()` before an old chunk still in flight had
  finished sampling the same object. Each layer now has a
  `stop_streaming()` that blocks until its in-flight builds finish, and
  `FoliageLocation._clear()` calls it before freeing a layer. This does not
  affect the default, owned `NoiseTerrainProvider` (`build()` always swaps in
  a fresh instance for it), only a location that was given its own provider --
  none of `content/locations/*.tres` are yet, so nothing changed for them.
- **`set_quality()` desynced grass and ground's terrain material.**
  `grass.rebuild()` always builds a new one; `ground.material` was never
  told. `set_quality()` now re-reads it from `grass.get_terrain_material()`
  after every rebuild, the same way `build()` already did.
- **`--bench` could hang.** It awaited `TreeLayer.impostors_ready`
  unconditionally whenever impostors were not yet ready, but `TreeLayer`
  only starts a bake when `impostors_enabled` is true and there is a real
  renderer -- the same two conditions `--bench` now checks before awaiting.

`--stream-test` (see *Running the test scene*) checks the first three
headlessly, against a location built with a caller-supplied terrain so the
mask-mutation path is the one actually under test: every held grass chunk
stays within `streaming_radius` after a jump; a footprint carved the instant
new chunks are requested -- before any of them can have committed -- still
clears exactly the tufts under it; `set_quality()` and a profile swap both
leave grass and ground sharing one terrain material. It cannot prove the
freed-terrain race itself is gone -- that needs a thread sanitizer this
project does not have, and in a fast local run the workers reliably finish
before any conflict would show. Turning `stop_streaming()` back into a plain
`queue_free()` still passes `--stream-test` here. Confirmed instead by
reading `ChunkStreamer.clear()`'s wait loop and by the fact that
`_stream_test_and_quit()`'s assertions did catch the other three regressions
when deliberately reintroduced one at a time. The impostor-pop fix is
likewise not asserted on automatically -- baking needs a real renderer, so
`--headless` never reaches that code path -- but `--shot` and `--wide` were
both run windowed afterwards and both bake and redraw cleanly, with frame
times unchanged from before the fix.

### Height H1: terrain tiles

First step of the height work (valleys, hills, mountains): placement and
ground meshes read a per-chunk `TerrainTile` instead of sampling noise per
tuft. Measured headless on `wide_valley` terrain, since this is CPU work (64
grass chunks, 16 near ground chunks):

| | Before | After |
| --- | --- | --- |
| Grass placement, per 16 m chunk | 15.6 ms | 10.9 ms |
| Near ground mesh, per 64 m chunk | 8.3 ms | 5.8 ms |
| Tufts placed | 135,424 | 135,424 |

On the test meadow, grass tuft and flower counts are identical to the
pre-tile placer. Positions moved by at most 9 mm, and up-vectors by at most
0.3°. `--indoor`, `--stream-test` and `--carve` pass. Near ground mesh
heights are unchanged, and vertex normals are within 0.6°.

**`--coverage` is sensitive to the wind.** Its SPRITE_CARDS column moved 2–3
points between two builds whose in-game scatter was identical down to a
fingerprint over all 707,154 tufts. The cause was not coverage: the capture
catches the wind at a different moment, and a gust lays the cards over. With
`foliage_wind_strength` forced to 0, the old and new placers read within
0.1–0.3 points of each other at every pitch (14.7 / 24.3 / 37.9 / 49.9%).
Freeze the wind before trusting a small `--coverage` difference.
