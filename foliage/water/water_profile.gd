class_name WaterProfile
extends Resource

## Where and how a location's water looks. W1/W2 built the sea: a flat plane
## at `sea_level`, and terrain that knows it is there. W3 adds lakes: basins
## LandformTerrainProvider finds by flooding the height field (see
## LakeBasins), filtered down to the ones worth calling a lake. On top of W3,
## the water surface itself is terrain-aware too (WaterDepthMap): the same
## sea/lake depth that drives the growth mask reaches the water shader, to
## damp the wave swell in shallow water. W4 adds rivers: unlike the sea and
## lakes, a river's surface cannot be a flat plane (it must follow its
## valley's slope), so it is real terrain-following ribbon geometry, traced
## along the valley network by RiverTracer rather than baked to a grid --
## see docs/WATER.md, W4.
##
## Saved per location as a .tres (content/water/), pointed at by
## FoliageProfile.water. Null, or every layer switched off, means no water at
## all: FoliageLocation builds no WaterLayer and touches nothing else -- the
## same "off costs nothing" rule FoliageProfile.enabled follows for indoor
## locations.

@export_group("Sea")
## A height alone cannot mean "on": 0.0 is itself an ordinary sea level (most
## sea levels ARE 0), so unlike TerrainProfile's altitude lines -- which use a
## height far above any terrain as their off switch -- this needs a real flag.
@export var sea_enabled: bool = false
@export_range(-2000.0, 2000.0, 0.1) var sea_level: float = 0.0
## Metres from sea_level (mean sea level) up to high water: the fixed design
## level everything baked uses (growth mask, water_cover(), shoreline and
## zone bakes), so grass stops at the high-water line instead of following
## the tide. 0 = no tide: high water is sea_level. The live level the sea
## plane and shore band draw at is SeaState's, not this. See
## docs/SEA_PLAN.md, SEA1.
@export_range(0.0, 20.0, 0.01) var sea_high_water_rise: float = 0.0
## Half-width of the blend between "grows normally" and "fully submerged", in
## metres of height above/below sea_level. A hard cutoff at exactly sea_level
## would show as a knife-edge ring of grass at the waterline; banding it
## softens that into a natural fringe instead -- the same reasoning
## TerrainProfile.altitude_rock()'s band uses for the treeline.
@export_range(0.05, 20.0, 0.05) var shore_band: float = 1.0
## A tidal sea's foreshore (docs/SEA_PLAN.md, SEA4): the ground the tide
## uncovers, from the seabed up to high water, where nothing grows. Mapped
## open sand or beach keeps its sand colour; elsewhere this damp buff sand
## stands in, rather than the inland bare-earth colour. Without a tide the
## foreshore is not drawn, so untidal seas look as before.
@export var foreshore_colour: Color = Color("#a39377")
## How long uncovered foreshore takes to lose its wet sheen, hours.
@export_range(0.25, 4.0, 0.05) var wet_sand_hours: float = 3.0

@export_group("Lakes")
## Procedural: LandformTerrainProvider floods the height field once when
## configured (LakeBasins.fill_depressions) and keeps whatever survives the
## two filters below. No per-basin authoring -- see docs/WATER.md, W3, for
## why that is a deliberate scope decision, not an oversight.
@export var lakes_enabled: bool = false
## Basins smaller than this are dropped as noise -- a single-cell dimple in
## the flood-fill grid, not a pond. Square metres.
@export_range(100.0, 2000000.0, 100.0) var lake_min_area: float = 4000.0
## A basin that would have to fill deeper than this to reach its own rim is
## dropped too: on a bounded, edge-raised world, a large low-lying region can
## easily flood-fill "successfully" to an implausible depth before finding an
## escape over the rim -- that is a sinkhole the algorithm found, not a lake
## worth drawing. Raising this lets deeper basins through.
@export_range(1.0, 500.0, 1.0) var lake_max_depth: float = 15.0

@export_group("Rivers")
## Procedural, riding the existing valley network (TerrainProfile's meander
## field) rather than an authored path -- see LandformTerrainProvider's
## river_strength()/RiverTracer. Requires `TerrainProfile.valley_depth > 0`:
## a river with no valley to sit in is not meaningful, and the field a river
## traces (LandformTerrainProvider._valley_distance()) is the same one
## valleys already carve.
@export var river_enabled: bool = false
## Width of the water surface, metres -- independent of the valley's own
## floor width (TerrainProfile.valley_width): a river is a ribbon down the
## middle of a valley, not the whole flat floor.
@export_range(1.0, 100.0, 0.5) var river_width: float = 8.0
## How far the streambed is carved below the valley floor, the same way
## valley_depth cuts into the rolling ground. Small on purpose: this is a
## channel in an already-flat floor, not a second valley.
@export_range(0.0, 20.0, 0.1) var river_carve_depth: float = 1.0
## Depth of water above the already-carved streambed. Kept shallower than the
## default river_carve_depth so the surface remains below the banks.
@export_range(0.0, 5.0, 0.05) var river_water_depth: float = 0.3
## Traced contours shorter than this are dropped. Measured on rolling_hills
## (valley_spacing 1500 m): 43 contours unfiltered, lengths from 120 m to
## 2,805 m with no clean gap between "fragment" and "real" -- but every
## valley in the world tracing to a river at all reads as far too dense a
## network (real landscapes leave most valleys dry). 800 m keeps the dozen or
## so longest, most substantial valleys; the true answer is a judgement call
## about density, not a threshold with an objectively correct value.
@export_range(0.0, 3000.0, 10.0) var river_min_length: float = 800.0

@export_group("Look")
## Shallow to deep, sampled by the depth-texture blend in water.gdshader.
## Same PackedColorArray-gradient pattern as FoliageProfile.grass_palette --
## a location's water is part of its identity too.
@export var water_palette: PackedColorArray = PackedColorArray([
	Color("#7fd4c9"), Color("#3a93a1"), Color("#1c5a73"), Color("#0d3550"),
])
## World depth (reconstructed from the depth buffer, not sampled terrain --
## see WaterLayer) at which the palette reaches its deepest stop. Short makes
## a hard shoreline; long makes a wide, gradual shelf.
@export_range(0.1, 40.0, 0.1) var shallow_depth: float = 4.0

@export_group("Waves")
## Large, slow vertical swell: silhouette movement, not surface detail. Kept
## small on purpose -- the sea is one coarse plane (see WaterLayer), and a
## bigger swell than this facets visibly on it.
@export_range(0.0, 1.0, 0.01) var swell_height: float = 0.12
@export_range(5.0, 400.0, 1.0) var swell_scale: float = 60.0
@export_range(0.0, 1.0, 0.01) var swell_speed: float = 0.06
## Surface ripple: fragment-only normal perturbation, so it reads as detail at
## any mesh resolution regardless of the swell mesh's coarseness. Scrolls with
## the same wind the grass bends to (foliage_gust_scale / foliage_wind_scroll),
## so a storm roughens the sea for free, from the one call AtmosphereSystem
## already makes every frame.
@export_range(0.0, 2.0, 0.01) var ripple_strength: float = 0.35
@export_range(0.01, 2.0, 0.01) var ripple_scale: float = 0.12
## Depth (WaterDepthMap, world units) over which the swell ramps from nothing
## to full strength. This is the actual fix for water visibly surging in and
## out at a shore: without it, the swell is a blind vertical offset that does
## not know the ground is right there, and on a shallow grade a few
## centimetres of bob sweeps the apparent shoreline metres back and forth.
## Fading it out in shallow water is a much smaller change than it looks --
## the map already exists (it is what the growth mask reads); this is the
## same data reaching the vertex shader too. See docs/WATER.md, *Terrain-aware
## water*.
@export_range(0.0, 20.0, 0.1) var swell_depth_fade: float = 2.0

@export_group("Surf")
## Surf on a real coastline (docs/SEA_PLAN.md, SEA5; sea_surf.gdshaderinc).
## Needs a sea sidecar with a coast field; elsewhere there is no surf. Wave
## height offshore in calm weather, metres -- a storm raises it by
## surf_storm_gain times as much again (through foliage_gust_scale).
@export_range(0.0, 3.0, 0.01) var surf_height: float = 0.35
@export_range(0.0, 8.0, 0.1) var surf_storm_gain: float = 3.0
## Seconds between waves, and the spacing of their crests, metres.
@export_range(3.0, 20.0, 0.1) var surf_period: float = 8.0
@export_range(8.0, 150.0, 1.0) var surf_wavelength: float = 36.0
## How far offshore surf is drawn, metres; it fades out over the last 40%.
@export_range(100.0, 3000.0, 10.0) var surf_range: float = 700.0
## How high the swash runs up the beach, as a fraction of the wave height.
@export_range(0.0, 3.0, 0.05) var surf_runup: float = 0.7

@export_group("Estuaries and surge")
## How far up a river from its mouth on the sea the tide is felt, metres
## (docs/SEA_PLAN.md, SEA8): the river rises towards the sea level, fully at
## the mouth and fading to nothing this far upstream. 0 keeps rivers off the
## tide.
@export_range(0.0, 20000.0, 50.0) var estuary_reach: float = 1500.0
## Storm surge (SEA8): in a full storm the sea stands this much higher from
## the low pressure alone (the inverse barometer, about 1 cm per hPa)...
@export_range(0.0, 2.0, 0.05) var surge_pressure: float = 0.3
## ...plus up to this much wind set-up with the wind blowing straight onshore
## (less across the shore, a set-down when it blows off it).
@export_range(0.0, 5.0, 0.05) var surge_wind: float = 0.5
## How fast the surge builds and falls, metres per second of game play.
@export_range(0.001, 1.0, 0.001) var surge_rate: float = 0.02

@export_group("Shading")
## Grazing angles brighten towards the sky -- the cheap stand-in for a real
## reflection this stylised water uses instead of SSR.
@export_range(0.0, 1.0, 0.01) var fresnel_strength: float = 0.6
@export_range(0.5, 8.0, 0.1) var fresnel_power: float = 3.0
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.05

## Sentinel meaning "no water here": far below any real sea_level (the export
## range above tops out at -2000/+2000), so both consumers below read as a
## no-op wherever this is used instead of a real height.
const OFF_HEIGHT := -100000.0


## Height of high water (sea_level + sea_high_water_rise): the design level
## water_mask() bands around.
func sea_high_water() -> float:
	return sea_level + sea_high_water_rise


## 0..1: how submerged a point at height `h` is, against high water rather
## than the live level -- anything baked from it must not move with the tide
## (docs/SEA_PLAN.md, SEA1). Feeds the growth mask
## (LandformTerrainProvider.growth_mask_for) -- and terrain.gdshader computes
## the exact same smoothstep band from terrain_water_level/terrain_shore_band
## (apply_to_terrain_material() below), so grass stops growing exactly where
## the ground reads as underwater. The same "one formula, two places" rule
## TerrainProfile.altitude_rock() documents for rock and snow.
func water_mask(h: float) -> float:
	if not sea_enabled:
		return 0.0
	var high := sea_high_water()
	return 1.0 - smoothstep(high - shore_band, high + shore_band, h)


## Pushes the shoreline into a terrain material -- see water_mask(). Called by
## FoliageLocation whenever the ground material is (re)built, alongside
## TerrainProfile.apply_to_terrain_material() for altitude. The level is the
## live one (SeaState); without a tide it equals sea_level.
func apply_to_terrain_material(material: ShaderMaterial, level_now: float = NAN) -> void:
	var level := sea_level if is_nan(level_now) else level_now
	material.set_shader_parameter("terrain_water_level", level if sea_enabled else OFF_HEIGHT)
	material.set_shader_parameter("terrain_shore_band", shore_band)
	material.set_shader_parameter("terrain_sea_high_water", sea_high_water() if sea_enabled else OFF_HEIGHT)
	material.set_shader_parameter("terrain_foreshore_colour", foreshore_colour)
	material.set_shader_parameter("terrain_wet_sand_hours", wet_sand_hours)


## Surf uniforms (sea_surf.gdshaderinc) for the water or terrain material:
## on only for an enabled sea whose sidecar has a coast field.
func apply_surf(material: ShaderMaterial, sea: ImportedSea) -> void:
	var on := sea_enabled and sea != null and sea.has_coast()
	material.set_shader_parameter("surf_enabled", on)
	material.set_shader_parameter("surf_coast", sea.coast_texture if on else null)
	if not on:
		return
	material.set_shader_parameter("surf_coast_bounds", sea.bounds())
	material.set_shader_parameter("surf_coast_z_sign", sea.coast_z_sign)
	material.set_shader_parameter("surf_height", surf_height)
	material.set_shader_parameter("surf_storm_gain", surf_storm_gain)
	material.set_shader_parameter("surf_period", surf_period)
	material.set_shader_parameter("surf_wavelength", surf_wavelength)
	material.set_shader_parameter("surf_range", surf_range)
	material.set_shader_parameter("surf_runup", surf_runup)


## Pushes this profile's own knobs into a water material. Wind direction/speed
## and the distance tint come from the owning FoliageProfile instead --
## FoliageLocation calls FoliageProfile.apply_to_water_material() for those,
## the same split apply_to_debris_material() uses for the one thing debris
## shares with the rest of the location.
func apply_to_material(material: ShaderMaterial, world_seed: int) -> void:
	material.set_shader_parameter("water_palette", FoliageTextures.palette_texture(water_palette, "water:%d" % world_seed))
	material.set_shader_parameter("water_shallow_depth", shallow_depth)
	# The same field that scrolls under the grass and terrain (same seed and
	# scale as FoliageProfile._apply_shared()'s foliage_wind_noise), so the
	# cache hits the existing texture rather than baking a second one, and the
	# sea's ripples are literally the same wind the grass is bending to.
	material.set_shader_parameter("water_ripple_noise", FoliageTextures.noise_texture(world_seed + 5501, 0.012, 512, 3))
	material.set_shader_parameter("water_swell_height", swell_height)
	material.set_shader_parameter("water_swell_scale", swell_scale)
	material.set_shader_parameter("water_swell_speed", swell_speed)
	material.set_shader_parameter("water_ripple_strength", ripple_strength)
	material.set_shader_parameter("water_ripple_scale", ripple_scale)
	material.set_shader_parameter("water_swell_depth_fade", swell_depth_fade)
	material.set_shader_parameter("water_fresnel_strength", fresnel_strength)
	material.set_shader_parameter("water_fresnel_power", fresnel_power)
	material.set_shader_parameter("water_roughness", roughness)
