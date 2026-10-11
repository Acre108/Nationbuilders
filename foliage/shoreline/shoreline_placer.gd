class_name ShorelinePlacer
extends RefCounted

## Foliage-only consumer of the water branch's fitted lake outlines. The
## boundary is a signed_distance(x,z) callable and immutable levels/names;
## no dependency on ImportedLakes' implementation or water mesh construction.
##
## Where reeds and stones may stand is ShoreHabitat's call (environment zones
## Z5), shared with the SHORE zone. This class keeps the draws, the density
## patches, the asset choice and the transforms.
const REED_SALT := 0x5EED72
const ROCK_SALT := 0x50C472
const MAX_REED_DEPTH := ShoreHabitat.MAX_REED_DEPTH
const MAX_REED_BANK_HEIGHT := ShoreHabitat.MAX_REED_BANK_HEIGHT
const MAX_REED_SLOPE := ShoreHabitat.MAX_REED_SLOPE
const MAX_ROCK_DEPTH := ShoreHabitat.MAX_ROCK_DEPTH
const STREAM_ROCK_SALT := 0x57BED5
const STREAM_REED_SALT := 0x57BEED
## Streams: candidate spacing for stones and reeds, how far past the waterline
## each may stand, the foam (steepness) above which a reach is too fast for
## reeds, and the half-width below which a stream gets pebbles only.
const STREAM_ROCK_SPACING := 1.6
const STREAM_REED_SPACING := 1.4
const STREAM_ROCK_BANK := ShoreHabitat.STREAM_ROCK_BANK
const STREAM_REED_BANK := ShoreHabitat.STREAM_REED_BANK
const STREAM_REED_MAX_FOAM := ShoreHabitat.STREAM_REED_MAX_FOAM
const STREAM_BOULDER_HALF := 1.8

class Params extends RefCounted:
	var source: RefCounted
	var signed_shore: Callable
	var levels := PackedFloat32Array()
	var names := PackedStringArray()
	var lake_name: String = ""
	var world_seed: int = 0
	var chunk_size: float = 64.0
	var reed_cover: float = 0.0
	var rock_cover: float = 0.0
	var reed_spacing: float = 1.6
	var rock_spacing: float = 4.0
	var density_scale: float = 1.0
	var patches: FastNoiseLite
	var natural_height: Callable
	## Fitted rivers (ImportedRivers), or null: streams get no stones or reeds.
	var streams: RefCounted
	var stream_rock_cover: float = 0.0
	var stream_reed_cover: float = 0.0

class Placement extends RefCounted:
	var transforms: Array[Transform3D] = []
	var custom := PackedColorArray()
	var assets := PackedInt32Array()
	var reeds: int = 0
	var rocks: int = 0

## Optional adapter: absent water data simply produces no shoreline layer.
## Reading a property list avoids assuming the river branch already has lakes.
static func source_for(terrain: TerrainProvider) -> RefCounted:
	if terrain == null or not terrain.has_water_marks():
		return null
	var rivers: Variant = terrain.get("imported_rivers")
	if rivers == null:
		return null
	for property in rivers.get_property_list():
		if property.name == "lakes":
			var lakes: Variant = rivers.get("lakes")
			if lakes != null and lakes.has_method("signed_distance"):
				return lakes
	return null

## The fitted rivers, for stones and reeds along streams; null without them.
static func streams_for(terrain: TerrainProvider) -> RefCounted:
	if terrain == null or not terrain.has_water_marks():
		return null
	var rivers: Variant = terrain.get("imported_rivers")
	if rivers == null or not rivers.has_method("channel_inside") or not rivers.has_method("water_at"):
		return null
	return rivers


static func params_for(profile: FoliageProfile, terrain: TerrainProvider, quality: FoliageQuality) -> Params:
	var params := Params.new()
	params.streams = streams_for(terrain)
	params.stream_rock_cover = profile.stream_rock_cover
	params.stream_reed_cover = profile.stream_reed_cover
	params.world_seed = profile.world_seed
	params.density_scale = minf(quality.density_scale, 1.0)
	params.patches = TreePlacer.grove_noise(profile.world_seed ^ REED_SALT)
	params.patches.frequency = 0.035
	params.source = source_for(terrain)
	if params.source == null:
		return params
	params.signed_shore = Callable(params.source, "signed_distance")
	params.levels = params.source.get("levels").duplicate()
	params.names = params.source.get("names").duplicate()
	params.lake_name = profile.shoreline_lake_name
	params.world_seed = profile.world_seed
	params.reed_cover = profile.shoreline_reed_cover
	params.rock_cover = profile.shoreline_rock_cover
	params.reed_spacing = profile.shoreline_reed_spacing
	params.rock_spacing = profile.shoreline_rock_spacing
	params.density_scale = minf(quality.density_scale, 1.0)
	params.patches = TreePlacer.grove_noise(profile.world_seed ^ REED_SALT)
	params.patches.frequency = 0.035
	params.natural_height = Callable(terrain, "natural_height" if terrain.has_method("natural_height") else "get_height")
	return params

static func place_chunk(coord: Vector2i, params: Params, terrain: TerrainProvider) -> Placement:
	var out := Placement.new()
	var habitat := ShoreHabitat.from_params(params, terrain)
	if habitat.has_lakes():
		_scatter(out, coord, params, terrain, habitat, true)
		_scatter(out, coord, params, terrain, habitat, false)
	if params.streams != null:
		_scatter_stream(out, coord, params, terrain, habitat, true)
		_scatter_stream(out, coord, params, terrain, habitat, false)
	return out


## Whether a location gets this layer at all: lake shores or streams to dress.
static func wanted(profile: FoliageProfile, terrain: TerrainProvider) -> bool:
	var lakes := (profile.shoreline_reed_cover > 0.0 or profile.shoreline_rock_cover > 0.0) and source_for(terrain) != null
	var streams := (profile.stream_rock_cover > 0.0 or profile.stream_reed_cover > 0.0) and streams_for(terrain) != null
	return lakes or streams


## Stones across stream beds and along their banks (pebbles; boulders too in
## wider streams), reeds on calm reaches' banks. Same draw-before-test rule
## as _scatter(), so placements stay put when covers or habitat change.
static func _scatter_stream(out: Placement, coord: Vector2i, params: Params, terrain: TerrainProvider, habitat: ShoreHabitat, reeds: bool) -> void:
	var cover := params.stream_reed_cover if reeds else params.stream_rock_cover
	if cover <= 0.0:
		return
	var origin := Vector2(coord) * params.chunk_size
	if not params.streams.has_water_in(Rect2(origin, Vector2.ONE * params.chunk_size).grow(4.0)):
		return
	var spacing := STREAM_REED_SPACING if reeds else STREAM_ROCK_SPACING
	var cells := maxi(1, ceili(params.chunk_size / spacing))
	var cell := params.chunk_size / cells
	var rng := RandomNumberGenerator.new()
	rng.seed = GrassPlacer.hash_chunk(params.world_seed ^ (STREAM_REED_SALT if reeds else STREAM_ROCK_SALT), coord.x, coord.y)
	for z in cells:
		for x in cells:
			var point := origin + Vector2(x + rng.randf_range(0.1, 0.9), z + rng.randf_range(0.1, 0.9)) * cell
			var accept := rng.randf()
			var choice := rng.randf()
			var yaw := rng.randf() * TAU
			var scale_value := rng.randf_range(0.7, 1.2)
			var colour := rng.randf()
			var phase := rng.randf()
			var inside := habitat.stream_at(point.x, point.y, reeds)
			if inside.z < 0.0:
				continue
			var patch := smoothstep(1.0 - cover - 0.13, 1.0 - cover + 0.13, GroveScatter.grove_value(params.patches, point.x, point.y))
			if accept >= patch * (params.density_scale if reeds else 1.0):
				continue
			if not habitat.stream_suits(point.x, point.y, reeds):
				continue
			var ground := terrain.get_height(point.x, point.y)
			var normal := terrain.get_normal(point.x, point.y)
			var asset: int
			var basis: Basis
			if reeds:
				asset = mini(2, int(choice * 3.0))
				basis = Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_value * clampf(inside.y, 0.6, 1.0))
				out.reeds += 1
			else:
				var boulder := inside.y >= STREAM_BOULDER_HALF and choice >= 0.93
				asset = 6 + mini(2, int((choice - 0.93) / 0.07 * 3.0)) if boulder else 3 + mini(2, int(choice / 0.93 * 3.0))
				# Pebbles in a brook are small; they grow with the stream.
				var size := scale_value * (clampf(inside.y / 2.0, 0.45, 1.0) if not boulder else clampf(inside.y / 4.0, 0.5, 0.9))
				basis = (Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, yaw)).scaled(Vector3.ONE * size)
				ground -= NatureAssetCatalogue.SHORE_HEIGHTS[asset] * size * 0.25
				out.rocks += 1
			out.transforms.append(Transform3D(basis, Vector3(point.x, ground, point.y)))
			out.custom.append(Color(colour, phase, 0.0, 0.0))
			out.assets.append(asset)

static func _scatter(out: Placement, coord: Vector2i, params: Params, terrain: TerrainProvider, habitat: ShoreHabitat, reeds: bool) -> void:
	var cover := params.reed_cover if reeds else params.rock_cover
	if cover <= 0.0:
		return
	var spacing := params.reed_spacing if reeds else params.rock_spacing
	var cells := maxi(1, ceili(params.chunk_size / spacing))
	var cell := params.chunk_size / cells
	var origin := Vector2(coord) * params.chunk_size
	var rng := RandomNumberGenerator.new()
	rng.seed = GrassPlacer.hash_chunk(params.world_seed ^ (REED_SALT if reeds else ROCK_SALT), coord.x, coord.y)
	for z in cells:
		for x in cells:
			# Draw everything before habitat tests, keeping surviving transforms
			# stable when density, water level or exclusions change.
			var point := origin + Vector2(x + rng.randf_range(0.1, 0.9), z + rng.randf_range(0.1, 0.9)) * cell
			var accept := rng.randf()
			var choice := rng.randf()
			var yaw := rng.randf() * TAU
			var scale_value := rng.randf_range(0.8, 1.25)
			var colour := rng.randf()
			var phase := rng.randf()
			var lake := habitat.lake_at(point.x, point.y, reeds)
			if lake < 0:
				continue
			var patch := smoothstep(1.0 - cover - 0.13, 1.0 - cover + 0.13, GroveScatter.grove_value(params.patches, point.x, point.y))
			if accept >= patch * (params.density_scale if reeds else 1.0):
				continue
			if not habitat.lake_suits(lake, point.x, point.y, reeds):
				continue
			var ground := terrain.get_height(point.x, point.y)
			var normal := terrain.get_normal(point.x, point.y)
			var asset: int
			var basis: Basis
			if reeds:
				asset = mini(2, int(choice * 3.0))
				basis = Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_value)
				out.reeds += 1
			else:
				# Pebbles dominate the margin, with occasional larger boulders.
				asset = 3 + mini(2, int(choice / 0.85 * 3.0)) if choice < 0.85 else 6 + mini(2, int((choice - 0.85) / 0.15 * 3.0))
				basis = (Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, yaw)).scaled(Vector3.ONE * scale_value)
				ground -= NatureAssetCatalogue.SHORE_HEIGHTS[asset] * scale_value * 0.12
				out.rocks += 1
			out.transforms.append(Transform3D(basis, Vector3(point.x, ground, point.y)))
			out.custom.append(Color(colour, phase, 0.0, 0.0))
			out.assets.append(asset)
