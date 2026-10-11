class_name TerrainLayer
extends Node3D

## The visible ground: chunk meshes sampled from a TerrainProvider, drawn with
## the terrain material the GrassLayer hands out.
##
## With `streaming` on, chunks follow the focus point out to `view_distance`,
## at three detail levels by distance -- fine where grass stands on it, coarse
## where only the silhouette matters. Sampling runs on WorkerThreadPool; the
## main thread only creates meshes. Chunks at different detail levels hang
## skirts (see TerrainProvider.build_chunk_arrays) so their seams never show
## sky. With streaming off, a fixed square of `extent` round the origin at full
## detail -- for the self-tests.
##
## Children are the chunk MeshInstance3Ds and nothing else; the coverage test
## repaints them by walking get_children().
##
## With a `water_material`, each chunk also meshes the provider's water field
## (TerrainProvider.build_water_arrays()) on the same lattice, in the same
## worker job, as a "Water" child of its ground mesh: rivers and lakes follow
## the ground's own streaming and detail rings. WaterLayer draws lakes past
## `water_reach`, where this hands over (see water.gdshader's water_cut).
##
## FoliageLocation runs two of these. The GROUND layer is the one above. The
## HORIZON layer (make_horizon()) uses 1 km chunks at 16-32 m spacing out to
## several kilometres, so distant hills stand on the skyline instead of
## the world ending in fog at view_distance. It skips chunks the ground layer
## fully covers, and where the two overlap its vertices are sunk a few metres
## under the ground layer in the vertex shader (instance uniform
## `terrain_sink`), so it can never poke through -- and while a ground chunk is
## still streaming in, the horizon shows just below where it will be, not sky.

var terrain: TerrainProvider
var material: ShaderMaterial

@export var streaming: bool = false
@export var defer_first_streaming_build: bool = false
@export_range(16.0, 4096.0, 1.0) var chunk_size: float = 64.0
## Streaming: how far ground exists.
@export_range(64.0, 20000.0, 1.0) var view_distance: float = 600.0
## Streaming: full detail out to this distance (grass stands on it); middle
## detail out to `middle_ring`, coarse beyond.
@export var near_ring: float = 160.0
@export var middle_ring: float = 400.0
## Fixed mode: half-width of the square built round the origin.
@export var extent: float = 144.0

## Quads per chunk side at each detail level. 48 over 64 m matches the old
## fixed test terrain's 1.33 m spacing, which grass and furniture were tuned on.
const RESOLUTIONS := [48, 16, 8]

## Detail levels in use: near, middle, far. The ground layer uses RESOLUTIONS.
var resolutions: Array = RESOLUTIONS
## Streaming: chunks lying wholly within this distance of the focus are not
## built -- another layer covers them. 0 = build everything.
var inner_radius: float = 0.0
## Streaming: chunks wholly outside this rectangle (world XZ) are not built.
## Empty = unbounded.
var limit := Rect2()
## (depth, start, end), per chunk instance: vertices within `start` of the
## camera are sunk `depth` metres, easing back to true height by `end`. See
## the class comment. Zero depth = off.
var sink := Vector3.ZERO
var cast_shadows: bool = true
## Streaming: the wanted set is recomputed each time the focus crosses a
## square this size. 0 = chunk_size. The horizon sets the ground's chunk size
## here: its inner cut-out must track the ground layer's coverage, not jump
## a kilometre at a time.
var refresh_step: float = 0.0
## Normals from the grid at every level (see build_chunk_arrays()).
var grid_normals: bool = false
## Surface water material (WaterLayer.material); null = no water meshes.
var water_material: ShaderMaterial = null
## Water is drawn out to this distance from the camera, 0 = everywhere.
var water_reach: float = 0.0

var _streamer: ChunkStreamer
var _chunks: Dictionary = {}     ## Vector2i -> MeshInstance3D
var focus_point := Vector3.ZERO
var _focus_chunk := Vector2i(1 << 30, 0)


func rebuild() -> void:
	if _streamer == null:
		_streamer = ChunkStreamer.new()
		_streamer.commit = _commit
		_streamer.release = _release
		# Ground chunks are cheap to commit but there are many; a smaller
		# budget keeps them from crowding out grass on a fast move.
		_streamer.budget_usec = 2000
	var job := _Job.new()
	job.terrain = terrain
	job.chunk_size = chunk_size
	job.resolutions = resolutions.duplicate()
	job.grid_normals = grid_normals
	job.water = water_material != null
	_streamer.job = job
	_streamer.invalidate()
	_refresh_wanted(true)
	# First build (or fixed mode): block until done. A settings change on a
	# layer that is already streaming does NOT block: every chunk is marked
	# stale, stays visible, and is replaced within the per-frame budget. A
	# blocking rebuild of a full streamed radius took 2.8 s at High and 10.7 s
	# at Ultra -- far too long to freeze a game on a settings change.
	if not streaming or (_streamer.live_count() == 0 and not defer_first_streaming_build):
		_streamer.flush()


## Sets this layer up as the horizon ring round a ground layer that reaches
## `ground_distance`, out to `distance`, within `bounds` (empty = unbounded).
##
## Coverage margin: the ground layer recomputes its disc only when the focus
## crosses one of its chunks, so round the camera it is only guaranteed out to
## ground_distance minus a chunk diagonal. Inside that the horizon is sunk and
## whole chunks are skipped; from there to ground_distance it eases back up.
func configure_as_horizon(ground: TerrainLayer, distance: float, bounds: Rect2) -> void:
	streaming = true
	chunk_size = HORIZON_CHUNK
	resolutions = HORIZON_RESOLUTIONS
	grid_normals = true
	cast_shadows = false
	view_distance = maxf(distance, ground.view_distance + HORIZON_CHUNK)
	near_ring = HORIZON_FINE_RING
	middle_ring = HORIZON_FINE_RING
	refresh_step = ground.chunk_size
	var covered := ground.view_distance - ground.chunk_size * sqrt(2.0) - HORIZON_CHUNK / float(HORIZON_RESOLUTIONS[0]) * 2.0
	inner_radius = maxf(covered, 0.0)
	sink = Vector3(HORIZON_SINK, inner_radius, ground.view_distance)
	limit = bounds


const HORIZON_CHUNK := 1024.0
## 16 m spacing out to HORIZON_FINE_RING, 32 m beyond.
const HORIZON_RESOLUTIONS := [64, 32]
const HORIZON_FINE_RING := 2500.0
## How far under the ground layer the horizon hides, metres. Must exceed the
## horizon mesh's own height error at 16 m spacing, which on the current
## landforms is under 2 m.
const HORIZON_SINK := 8.0


func update_streaming(focus: Vector3) -> void:
	if _streamer == null or not streaming:
		return
	focus_point = focus
	_refresh_wanted(false)
	_streamer.update()


## Builds everything wanted at `focus_point` now, blocking, without rebuilding
## materials or anything else. (rebuild() is for settings changes.)
func flush() -> void:
	if _streamer == null:
		return
	_refresh_wanted(true)
	_streamer.flush()


func flush_at(point: Vector3) -> void:
	if _streamer != null:
		_streamer.flush_coord(Vector2i(floori(point.x / chunk_size), floori(point.z / chunk_size)))


## Re-meshes the chunks over `area` (sculpted heights, Location Studio S5);
## the old meshes stay up until their replacements commit.
func rebuild_area(area: Rect2) -> int:
	return _streamer.invalidate_area(area, chunk_size) if _streamer != null else 0


func pending_chunks() -> int:
	return _streamer.pending_count() if _streamer != null else 0


func chunk_count() -> int:
	return _chunks.size()


## Blocks until any in-flight worker build finishes, then frees every chunk.
## See GrassLayer.stop_streaming() for why this has to be synchronous rather
## than left to queue_free().
func stop_streaming() -> void:
	if _streamer != null:
		_streamer.clear()
	for chunk in _chunks.values():
		chunk.queue_free()
	_chunks.clear()


func _refresh_wanted(force: bool) -> void:
	if not streaming:
		if force:
			var r := int(ceil(extent / chunk_size))
			var wanted := {}
			var order: Array = []
			for cz in range(-r, r):
				for cx in range(-r, r):
					wanted[Vector2i(cx, cz)] = 0
					order.append(Vector2i(cx, cz))
			_streamer.set_wanted(wanted, order)
		return
	var quantum := refresh_step if refresh_step > 0.0 else chunk_size
	var here := Vector2i(floori(focus_point.x / quantum), floori(focus_point.z / quantum))
	if here == _focus_chunk and not force:
		return
	_focus_chunk = here
	var set: Array = ChunkStreamer.disc(focus_point, chunk_size, view_distance)
	var wanted: Dictionary = set[0]
	var order: Array = set[1]
	var point := Vector2(focus_point.x, focus_point.z)
	var last := resolutions.size() - 1
	for coord in wanted.keys():
		var square := Rect2(Vector2(coord) * chunk_size, Vector2.ONE * chunk_size)
		if (inner_radius > 0.0 and _farthest_corner(point, square) < inner_radius) 				or (limit.has_area() and not limit.intersects(square)):
			wanted.erase(coord)
			continue
		var d := ChunkStreamer.distance_to_chunk(point, coord, chunk_size)
		wanted[coord] = 0 if d < near_ring else (mini(1, last) if d < middle_ring else last)
	_streamer.set_wanted(wanted, order.filter(func(c): return wanted.has(c)))


static func _farthest_corner(point: Vector2, square: Rect2) -> float:
	var dx := maxf(absf(point.x - square.position.x), absf(point.x - square.end.x))
	var dz := maxf(absf(point.y - square.position.y), absf(point.y - square.end.y))
	return Vector2(dx, dz).length()


class _Job extends RefCounted:
	var terrain: TerrainProvider
	var chunk_size: float
	var resolutions: Array
	var grid_normals: bool
	var water: bool

	## [ground arrays, water arrays (empty: none)].
	func run(coord: Vector2i, level: int) -> Array:
		var resolution: int = resolutions[level]
		var origin := Vector2(coord) * chunk_size
		# Skirt depth measured from this chunk's own edge error (-1).
		var ground := terrain.build_chunk_arrays(origin, chunk_size, resolution, -1.0, grid_normals)
		return [ground, terrain.build_water_arrays(origin, chunk_size, resolution) if water else []]


func _commit(coord: Vector2i, _level: int, built: Array) -> void:
	var arrays: Array = built[0]
	var instance: MeshInstance3D = _chunks.get(coord)
	if instance == null:
		instance = MeshInstance3D.new()
		instance.name = "Ground_%d_%d" % [coord.x, coord.y]
		instance.position = Vector3(float(coord.x) * chunk_size, 0.0, float(coord.y) * chunk_size)
		if not cast_shadows:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		_chunks[coord] = instance
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	instance.mesh = mesh
	instance.material_override = material
	if sink.x > 0.0:
		instance.set_instance_shader_parameter(&"terrain_sink", sink)
	_commit_water(instance, built[1])


func _commit_water(instance: MeshInstance3D, arrays: Array) -> void:
	var water: MeshInstance3D = instance.get_node_or_null(^"Water")
	if arrays.is_empty():
		if water != null:
			water.free()
		return
	if water == null:
		water = MeshInstance3D.new()
		water.name = "Water"
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.add_child(water)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	water.mesh = mesh
	water.material_override = water_material
	water.set_instance_shader_parameter(&"water_flow", Vector3(0.0, 0.0, 3.0))
	water.set_instance_shader_parameter(&"water_cut", Vector2(0.0, water_reach))


func _release(coord: Vector2i) -> void:
	if _chunks.has(coord):
		_chunks[coord].queue_free()
		_chunks.erase(coord)


func _exit_tree() -> void:
	if _streamer != null:
		_streamer.clear()
