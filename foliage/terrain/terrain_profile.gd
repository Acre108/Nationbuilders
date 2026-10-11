class_name TerrainProfile
extends Resource

## The shape of a location's ground: how big the world is, how it rolls, where
## the hills rise and where valleys wind between them.
##
## Its own resource rather than fields on FoliageProfile: the ground is not
## foliage, and it will keep growing (mountains next). A FoliageProfile points
## at one through `terrain`; several locations can share a file.
##
## Deterministic: every noise field is seeded from the location's world_seed,
## so every client builds the same ground and none of it is networked.
##
## Layers, each off at 0 so a profile only pays for what it uses:
##   rolling ground -- the original two-octave landform, always on;
##   hills          -- rounded hills rising out of flat low ground, gathered
##                     into hill country by a broad region field;
##   valleys        -- winding flat-floored channels cut through everything;
##   edge           -- ground rising towards the world's boundary, so the
##                     bounded area ends in a skyline, not a cliff edge.
## See LandformTerrainProvider for how they combine.

@export_group("World")
## Side of the square world, metres, centred on the origin. Nothing grows
## outside it; the ground itself carries on so the view never ends in void.
@export_range(256.0, 32000.0, 1.0) var world_size: float = 8000.0
## Height the ground rises by at the world boundary. The ring of high ground
## that closes the skyline; later, where mountains stand. 0 = no rise.
@export_range(0.0, 1000.0, 0.5) var edge_rise: float = 0.0
## How far in from the boundary the rise starts.
@export_range(10.0, 4000.0, 1.0) var edge_width: float = 600.0

@export_group("Rolling ground")
## The broad swell under everything: the whole landform of the original test
## locations. Peak-to-trough height and feature width, metres.
@export_range(0.0, 200.0, 0.1) var landform_amplitude: float = 3.5
@export_range(10.0, 2000.0, 1.0) var landform_scale: float = 90.0
## Fine bumps on top, at `detail_scale` metres per feature.
@export_range(0.0, 10.0, 0.05) var detail_amplitude: float = 0.4
@export_range(2.0, 200.0, 0.5) var detail_scale: float = 22.0

@export_group("Hills")
## Height of a full hill above the low ground around it, metres. 0 = no hills.
## Steepness follows height over hill_scale: about 1:20 stays gentle rolling
## country; 1:8 is already steep hill flanks.
@export_range(0.0, 400.0, 0.5) var hill_height: float = 0.0
## Typical distance between neighbouring hilltops, metres.
@export_range(40.0, 4000.0, 1.0) var hill_scale: float = 380.0
## Share of hill country that rises into hills; the rest stays as flat low
## ground between them. Exact: measured from the noise when the provider is
## configured, not guessed.
@export_range(0.05, 0.95, 0.01) var hill_cover: float = 0.5
## How far hill shapes are pushed around, metres. 0 gives the round blobs of
## plain noise; a fraction of hill_scale makes lobed, leaning ridgelines.
@export_range(0.0, 1000.0, 1.0) var hill_warp: float = 120.0
## 1 = noise-smooth. Higher adds knobbly detail to the hill shapes.
@export_range(1, 6) var hill_octaves: int = 4
## Share of the world that is hill country; the rest is open plain with
## only the rolling ground. 1 = hills everywhere.
@export_range(0.0, 1.0, 0.01) var hill_country: float = 0.6
## Size of the hill-country and plain regions, metres.
@export_range(200.0, 8000.0, 1.0) var region_scale: float = 2400.0

@export_group("Valleys")
## How far a valley floor sits below the rolling ground, metres. In hill
## country a valley also cuts the hills away down to that floor. 0 = none.
@export_range(0.0, 200.0, 0.5) var valley_depth: float = 0.0
## Width across the top of a valley, metres (approximate: see
## LandformTerrainProvider).
@export_range(5.0, 1000.0, 1.0) var valley_width: float = 90.0
## Share of that width that is flat floor rather than sloping wall.
@export_range(0.0, 0.9, 0.01) var valley_floor: float = 0.4
## Typical distance between neighbouring valleys, metres.
@export_range(100.0, 8000.0, 1.0) var valley_spacing: float = 1400.0
## How much valleys meander, metres.
@export_range(0.0, 1000.0, 1.0) var valley_meander: float = 220.0
## Where a valley cuts through a hill, its walls widen so they are never much
## steeper than this, degrees. Without it a narrow valley through a tall hill
## becomes a gorge.
@export_range(5.0, 60.0, 0.5) var valley_wall_slope: float = 18.0


@export_group("Altitude")
## Height above which grass gives way to bare rock and scree, metres. The
## grass mask and the terrain shader use the same formula (see
## altitude_rock()), so grass thins exactly where the ground turns to rock.
## The default is above any current procedural landform, so this is off
## until mountains exist there -- but a heightmap-backed location (real
## elevation data) can and does reach it: see HeightmapTerrainProvider.
## altitude, which reuses this same resource and these same formulas for a
## real peak.
@export_range(-500.0, 10000.0, 1.0) var rock_line: float = 5000.0
## Height above which snow lies on ground flatter than about 45 degrees.
@export_range(-500.0, 10000.0, 1.0) var snow_line: float = 6000.0
## Height above which trees and conifers stop growing, metres -- see
## altitude_treeline(). Independent of rock_line: a real treeline can sit
## hundreds of metres below where bare rock starts (real alpine meadow lives
## in between), so this is its own setting rather than a fraction of
## rock_line. Only TreePlacer's tree-canopy families read it
## (TerrainProvider.get_tree_mask()) -- grass, shrubs and cushion plants stay
## on the ordinary growth mask and are honest at any elevation near it.
## Default far above any landform, same off-by-default convention as
## rock_line/snow_line.
@export_range(-500.0, 10000.0, 1.0) var treeline: float = 10000.0
## Half-width of the blend at each line, metres. Wide, because the lines are
## smooth contours: a narrow band reads as a painted stripe.
@export_range(1.0, 500.0, 1.0) var altitude_band: float = 40.0
@export var snow_colour: Color = Color("#e8edf2")
## Triplanar rock/snow texture break-up (terrain.gdshader): world units per
## noise tile, projected on all three axes so it does not stretch on a
## near-vertical face. There is no modelled rock texture in this game --
## like everything else here, this reuses the one shared noise texture
## (`foliage_colour_noise`) the rest of the palette already samples, just
## triplanar instead of flat top-down.
@export_range(0.05, 4.0, 0.01) var rock_scale: float = 0.35
## 0 = flat colour (the old look). Higher darkens the noise's low half and
## lightens its high half, reading as broken facets rather than a smooth
## painted slope.
@export_range(0.0, 1.0, 0.01) var rock_facet_strength: float = 0.4


## 0..1 bare rock from altitude at height `h`. Shared formula: the shader
## computes the same thing (terrain.gdshader, terrain_rock_line).
func altitude_rock(h: float) -> float:
	return smoothstep(rock_line - altitude_band, rock_line + altitude_band, h)


## 0..1 snow at height `h` on ground with normal Y `normal_y`. Shared formula,
## as altitude_rock().
func altitude_snow(h: float, normal_y: float) -> float:
	return smoothstep(snow_line - altitude_band, snow_line + altitude_band, h) * smoothstep(0.62, 0.8, normal_y)


## 0..1 "above the treeline" at height `h`. Same smoothstep shape as
## altitude_rock()/altitude_snow(), reusing altitude_band for the blend --
## but this one only ever feeds TerrainProvider.get_tree_mask(), never
## growth_mask_for(), so it must stay a separate function rather than get
## folded into either of the two above.
func altitude_treeline(h: float) -> float:
	return smoothstep(treeline - altitude_band, treeline + altitude_band, h)


## Pushes the altitude settings into a terrain material. FoliageLocation calls
## it whenever the ground's material is (re)built.
func apply_to_terrain_material(material: ShaderMaterial) -> void:
	material.set_shader_parameter("terrain_rock_line", rock_line)
	material.set_shader_parameter("terrain_snow_line", snow_line)
	material.set_shader_parameter("terrain_altitude_band", altitude_band)
	material.set_shader_parameter("terrain_snow_colour", snow_colour)
	material.set_shader_parameter("terrain_rock_scale", rock_scale)
	material.set_shader_parameter("terrain_rock_facet_strength", rock_facet_strength)


## The world's square in XZ.
func bounds() -> Rect2:
	return Rect2(Vector2.ONE * (-world_size * 0.5), Vector2.ONE * world_size)


## `water`, when given, feeds the growth mask's shoreline cutoff (see
## LandformTerrainProvider.growth_mask_for -- W2 of the water system).
func make_provider(world_seed: int, water: WaterProfile = null) -> LandformTerrainProvider:
	return LandformTerrainProvider.new(self, world_seed, water)
