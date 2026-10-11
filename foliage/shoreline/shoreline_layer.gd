class_name ShorelineLayer
extends Node3D

## Optional streamed freshwater reeds and shoreline stones. Water data is
## consumed read-only through ShorelinePlacer's small fitted-shore contract.
var profile: FoliageProfile
var quality: FoliageQuality
var terrain: TerrainProvider
var streaming: bool = true
var defer_first_streaming_build: bool = false
var chunk_radius: int = 2
var chunk_size: float = 64.0
var focus_point := Vector3.ZERO

var reed_count: int = 0
var rock_count: int = 0
var _streamer: ChunkStreamer
var _meshes: Array[ArrayMesh] = []
var _chunk_result: Dictionary = {}
var _chunks: Dictionary = {}
var _counts: Dictionary = {}
var _focus_chunk := Vector2i(1 << 30, 0)
var _range: float = 100.0

var exclusions: FoliageExclusions

func _exclusions_changed(area: Rect2) -> void:
	for coord: Vector2i in _chunk_result.keys():
		if Rect2(Vector2(coord)*chunk_size,Vector2.ONE*chunk_size).intersects(area):
			_commit(coord,0,_chunk_result[coord])

func _ready() -> void:
	if exclusions != null: exclusions.changed.connect(_exclusions_changed)
	rebuild()

func rebuild() -> void:
	if profile == null or quality == null or terrain == null or not profile.enabled or not profile.use_nature_pack:
		stop_streaming()
		return
	var params := ShorelinePlacer.params_for(profile, terrain, quality)
	var lakes := params.source != null and (params.reed_cover > 0.0 or params.rock_cover > 0.0)
	var streams := params.streams != null and (params.stream_rock_cover > 0.0 or params.stream_reed_cover > 0.0)
	if not lakes and not streams:
		stop_streaming()
		return
	params.chunk_size = chunk_size
	_range = minf(quality.view_distance, maxf(quality.streaming_radius, 90.0))
	_meshes.clear()
	for asset in NatureAssetCatalogue.SHORE_ASSETS.size():
		_meshes.append(NatureMeshBuilder.build(NatureAssetCatalogue.SHORE_ASSETS[asset], NatureAssetCatalogue.SHORE_HEIGHTS[asset], profile, asset >= 3, asset >= 3))
	if _streamer == null:
		_streamer = ChunkStreamer.new()
		_streamer.commit = _commit
		_streamer.release = _release
	var job := Job.new()
	job.params = params
	job.terrain = terrain
	_streamer.job = job
	_streamer.invalidate()
	_refresh(true)
	if not streaming or (_streamer.live_count() == 0 and not defer_first_streaming_build):
		_streamer.flush()
	_recount()

## Re-places the shoreline chunks over `area` (Location Studio S4/S5).
func rebuild_zone_area(area: Rect2) -> int:
	return _streamer.invalidate_area(area, chunk_size) if _streamer != null else 0

class Job extends RefCounted:
	var params: ShorelinePlacer.Params
	var terrain: TerrainProvider
	func run(coord: Vector2i, _variant: int) -> Dictionary:
		var placed := ShorelinePlacer.place_chunk(coord, params, terrain)
		var origin := Vector3(coord.x, 0, coord.y) * params.chunk_size
		var groups := {}
		for i in placed.transforms.size():
			var asset := placed.assets[i]
			if not groups.has(asset):
				groups[asset] = [[], []]
			groups[asset][0].append(placed.transforms[i])
			groups[asset][1].append(placed.custom[i])
		var buffers := {}
		for asset in groups:
			var transforms: Array[Transform3D] = []
			transforms.assign(groups[asset][0])
			buffers[asset] = [transforms.size(), FoliageMultiMesh.pack(transforms, PackedColorArray(groups[asset][1]), origin)]
		return {"groups": buffers, "reeds": placed.reeds, "rocks": placed.rocks}

func _commit(coord: Vector2i, _variant: int, result: Dictionary) -> void:
	_release(coord)
	_chunk_result[coord] = result
	if exclusions != null: result = exclusions.filter_result(result,Vector3(coord.x,0,coord.y)*chunk_size,"shore",chunk_size)
	if result.reeds + result.rocks == 0:
		return
	var chunk := Node3D.new()
	chunk.name = "Shore_%d_%d" % [coord.x, coord.y]
	chunk.position = Vector3(coord.x, 0, coord.y) * chunk_size
	add_child(chunk)
	_chunks[coord] = chunk
	_counts[coord] = Vector2i(result.reeds, result.rocks)
	for asset in result.groups:
		var instance := MultiMeshInstance3D.new()
		instance.name = NatureAssetCatalogue.SHORE_ASSETS[asset]
		instance.multimesh = FoliageMultiMesh.from_buffer(_meshes[asset], result.groups[asset][0], result.groups[asset][1])
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if asset < 3 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		instance.custom_aabb = instance.multimesh.get_aabb().grow(0.5)
		instance.visibility_range_end = _range + instance.custom_aabb.size.length() * 0.5
		chunk.add_child(instance)
	_recount()

func _release(coord: Vector2i) -> void:
	_chunk_result.erase(coord)
	if _chunks.has(coord):
		_chunks[coord].queue_free()
		_chunks.erase(coord)
	_counts.erase(coord)
	_recount()

func _recount() -> void:
	reed_count = 0
	rock_count = 0
	for counts: Vector2i in _counts.values():
		reed_count += counts.x
		rock_count += counts.y

func _refresh(force: bool) -> void:
	var here := Vector2i(floori(focus_point.x / chunk_size), floori(focus_point.z / chunk_size))
	if not force and here == _focus_chunk:
		return
	_focus_chunk = here
	var wanted := ChunkStreamer.disc(focus_point, chunk_size, _range) if streaming else ChunkStreamer.square(chunk_radius)
	_streamer.set_wanted(wanted[0], wanted[1])

func update_streaming(focus: Vector3) -> void:
	if _streamer == null or not streaming:
		return
	focus_point = focus
	_refresh(false)
	_streamer.update()

func flush() -> void:
	if _streamer != null:
		_refresh(true)
		_streamer.flush()

func pending_chunks() -> int:
	return _streamer.pending_count() if _streamer != null else 0

func stop_streaming() -> void:
	if _streamer != null:
		_streamer.clear()
		_streamer = null
	for chunk in _chunks.values():
		chunk.queue_free()
	_chunks.clear()
	_chunk_result.clear()
	_counts.clear()
	_recount()

func _exit_tree() -> void:
	if exclusions != null and exclusions.changed.is_connected(_exclusions_changed): exclusions.changed.disconnect(_exclusions_changed)
	if _streamer != null:
		_streamer.clear()
