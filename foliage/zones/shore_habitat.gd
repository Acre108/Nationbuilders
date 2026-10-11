class_name ShoreHabitat
extends RefCounted

## Where shoreline plants and stones may stand (environment zones Z5). The
## habitat tests ShorelinePlacer used to make inline -- distance to a lake
## shore, water depth, bank slope (shaped and natural), stream current --
## live here, so the SHORE zone and the shoreline layer share one definition.
## ShorelinePlacer keeps its draws, density patches and transforms, and asks
## this whether a point qualifies.
##
## Worker-safe: only reads the fitted water (ImportedLakes / ImportedRivers)
## and the terrain. Imported water only; procedural sea, lakes and rivers have
## no shoreline layer and no SHORE zone yet.

const MAX_REED_DEPTH := 0.55
const MAX_REED_BANK_HEIGHT := 0.6
const MAX_REED_SLOPE := 24.0
const MAX_ROCK_DEPTH := 1.25
## How far from the shore line (either side) lake reeds and rocks may stand.
const LAKE_REED_BAND := 3.0
const LAKE_ROCK_BAND := 12.0
## How far past a stream's waterline stones and reeds may stand, the foam
## (steepness) above which a reach is too fast for reeds.
const STREAM_ROCK_BANK := 1.0
const STREAM_REED_BANK := 1.2
const STREAM_REED_MAX_FOAM := 0.3
## The SHORE zone: full weight within this distance of a lake shore or a
## stream's waterline, easing out over the next SHORE_FADE metres.
const SHORE_BAND := 3.0
const SHORE_FADE := 3.0

var terrain: TerrainProvider
## ImportedLakes (signed_distance, levels, names), or null.
var lakes: RefCounted
## ImportedRivers (channel_inside, water_at, has_water_in), or null.
var streams: RefCounted
var levels := PackedFloat32Array()
var names := PackedStringArray()
## Only this lake (case-insensitive) gets lake shore plants; "" = every lake.
var lake_name: String = ""
var _signed_shore: Callable
var _natural_height: Callable
var _no_segments := PackedInt32Array()


static func for_terrain(provider: TerrainProvider, profile_lake_name: String = "") -> ShoreHabitat:
	var habitat := ShoreHabitat.new()
	habitat.terrain = provider
	habitat.lakes = ShorelinePlacer.source_for(provider)
	habitat.streams = ShorelinePlacer.streams_for(provider)
	habitat.lake_name = profile_lake_name
	if habitat.lakes != null:
		habitat._signed_shore = Callable(habitat.lakes, "signed_distance")
		habitat.levels = habitat.lakes.get("levels").duplicate()
		habitat.names = habitat.lakes.get("names").duplicate()
	if provider != null:
		habitat._natural_height = Callable(provider, "natural_height" if provider.has_method("natural_height") else "get_height")
	return habitat


## Built from ShorelinePlacer.Params, so callers (and tests) that adjust its
## lake fields -- lake_name, or clearing signed_shore -- are honoured.
static func from_params(params: ShorelinePlacer.Params, provider: TerrainProvider) -> ShoreHabitat:
	var habitat := ShoreHabitat.new()
	habitat.terrain = provider
	habitat.lakes = params.source
	habitat.streams = params.streams
	habitat.lake_name = params.lake_name
	habitat._signed_shore = params.signed_shore
	habitat.levels = params.levels
	habitat.names = params.names
	habitat._natural_height = params.natural_height if params.natural_height.is_valid() \
		else Callable(provider, "natural_height" if provider.has_method("natural_height") else "get_height")
	return habitat


func has_lakes() -> bool:
	return _signed_shore.is_valid() and not levels.is_empty()


## The lake whose shore band (x, z) is in, or -1: inside the reed or rock
## band and, when lake_name is set, that lake.
func lake_at(x: float, z: float, reeds: bool) -> int:
	if not has_lakes():
		return -1
	var shore: Vector2 = _signed_shore.call(x, z)
	var lake := int(shore.y)
	if not is_finite(shore.x) or lake < 0 or lake >= levels.size():
		return -1
	if not lake_name.is_empty() and (lake >= names.size() or names[lake].nocasecmp_to(lake_name) != 0):
		return -1
	if absf(shore.x) > (LAKE_REED_BAND if reeds else LAKE_ROCK_BAND):
		return -1
	return lake


## Whether lake `lake`'s margin at (x, z) suits reeds (shallow, gentle, not a
## cliff shore) or rocks (not deep, not steep). `lake` from lake_at().
func lake_suits(lake: int, x: float, z: float, reeds: bool) -> bool:
	if terrain.sample_painted_mask(x, z) < 0.35:
		return false
	var depth := levels[lake] - terrain.get_height(x, z)
	var normal := terrain.get_normal(x, z)
	if not reeds:
		return depth <= MAX_ROCK_DEPTH and normal.y >= 0.65
	if depth > MAX_REED_DEPTH or depth < -MAX_REED_BANK_HEIGHT or normal.y < cos(deg_to_rad(MAX_REED_SLOPE)):
		return false
	# Check the natural DEM as well as the shaped bank: artificial shallow
	# shelves must not turn cliff shores into reed beds.
	var e := 8.0
	var dx: float = _natural_height.call(x + e, z) - _natural_height.call(x - e, z)
	var dz: float = _natural_height.call(x, z + e) - _natural_height.call(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized().y >= cos(deg_to_rad(MAX_REED_SLOPE))


## Where (x, z) sits relative to a stream: ImportedRivers.channel_inside()
## (x = metres inside the waterline, y = half width, z < 0 = no stream), or
## z = -1 when outside the band stones (or reeds) may use.
func stream_at(x: float, z: float, reeds: bool) -> Vector3:
	if streams == null:
		return Vector3(0.0, 0.0, -1.0)
	var inside: Vector3 = streams.channel_inside(x, z, _no_segments)
	if inside.z < 0.0 or inside.x < -(STREAM_REED_BANK if reeds else STREAM_ROCK_BANK):
		return Vector3(0.0, 0.0, -1.0)
	# Reeds stand at the margin, not mid-stream.
	if reeds and inside.x > minf(0.35, inside.y * 0.4):
		return Vector3(0.0, 0.0, -1.0)
	return inside


## Whether a stream point from stream_at() suits reeds (calm, shallow,
## gentle bank) or stones (not on steep ground).
func stream_suits(x: float, z: float, reeds: bool) -> bool:
	var water: PackedFloat32Array = streams.water_at(x, z, 0.0)
	if water.is_empty():
		return false
	var normal := terrain.get_normal(x, z)
	if not reeds:
		return normal.y >= 0.6
	var ground := terrain.get_height(x, z)
	return water[3] <= STREAM_REED_MAX_FOAM and water[0] - ground <= MAX_REED_DEPTH and normal.y >= cos(deg_to_rad(MAX_REED_SLOPE))


## 0..1 SHORE zone strength: the water margin of any imported lake (whatever
## lake_name says) or stream.
func shore_band(x: float, z: float) -> float:
	var band := 0.0
	if has_lakes():
		var shore: Vector2 = _signed_shore.call(x, z)
		if is_finite(shore.x) and int(shore.y) >= 0:
			band = 1.0 - smoothstep(SHORE_BAND, SHORE_BAND + SHORE_FADE, absf(shore.x))
	if streams != null and band < 1.0:
		var inside: Vector3 = streams.channel_inside(x, z, _no_segments)
		if inside.z >= 0.0:
			band = maxf(band, 1.0 - smoothstep(SHORE_BAND, SHORE_BAND + SHORE_FADE, absf(inside.x)))
	return band
