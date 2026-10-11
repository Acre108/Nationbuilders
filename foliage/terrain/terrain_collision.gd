class_name TerrainCollision
extends Node3D

## Physics ground: one StaticBody3D with a HeightMapShape3D per 64 m chunk,
## streamed round the focus like the visible ground.
##
## Heights come from TerrainProvider.tile(), which interpolates across the
## drawn mesh's own triangles, sampled at whole metres: HeightMapShape3D's
## grid spacing is fixed at 1 m, and scaling collision shapes to change it is
## unreliable across Godot's physics engines. So a body rests on the surface
## you see to within the difference between two triangulations of the same
## heights -- measured by the collision self-test, not assumed.
##
## The radius is fixed, NOT tied to the graphics quality preset: what you can
## walk on must not depend on your settings. It only needs to cover what can
## touch the ground soon -- a player, dropped objects -- so it is small next
## to view_distance. Far-away players would each need their own coverage; how
## that is split between clients and a server is part of the deferred netcode
## decision, so this node simply follows one focus.
##
## Deterministic for the same reason the terrain is: every client builds the
## same shape from the same seed.

var terrain: TerrainProvider

@export var streaming: bool = true
@export var defer_first_streaming_build: bool = false
## Streaming: chunks within this distance of the focus have collision.
@export_range(16.0, 1024.0, 1.0) var radius: float = 128.0
## Fixed mode: half-width of the square round the origin.
@export var extent: float = 144.0
## Physics layer bits the ground occupies.
@export_flags_3d_physics var collision_layer: int = 1

const CHUNK := 64.0
## Samples per side: 1 m spacing, both edges included, so neighbouring
## chunks share their edge heights exactly.
const SAMPLES := int(CHUNK) + 1

var focus_point := Vector3.ZERO
var _streamer: ChunkStreamer
var _bodies: Dictionary = {}     ## Vector2i -> StaticBody3D
var _focus_chunk := Vector2i(1 << 30, 0)


func rebuild() -> void:
	if _streamer == null:
		_streamer = ChunkStreamer.new()
		_streamer.commit = _commit
		_streamer.release = _release
		# Shape creation is cheap, but bodies entering the physics space are
		# not free; keep it from crowding out the visual layers.
		_streamer.budget_usec = 1500
	var job := _Job.new()
	job.terrain = terrain
	_streamer.job = job
	_streamer.invalidate()
	_refresh_wanted(true)
	# The first build blocks, like the ground's: nothing may stand on
	# ground that has not had collision built yet.
	if not streaming or (_streamer.live_count() == 0 and not defer_first_streaming_build):
		_streamer.flush()


func update_streaming(focus: Vector3) -> void:
	if _streamer == null or not streaming:
		return
	focus_point = focus
	_refresh_wanted(false)
	_streamer.update()


func flush() -> void:
	if _streamer == null:
		return
	_refresh_wanted(true)
	_streamer.flush()


func flush_at(point: Vector3) -> void:
	if _streamer != null:
		_streamer.flush_coord(Vector2i(floori(point.x / CHUNK), floori(point.z / CHUNK)))


## Rebuilds the collision chunks over `area` (sculpted heights, S5).
func rebuild_area(area: Rect2) -> int:
	return _streamer.invalidate_area(area, CHUNK) if _streamer != null else 0


func pending_chunks() -> int:
	return _streamer.pending_count() if _streamer != null else 0


func chunk_count() -> int:
	return _bodies.size()


## True when the chunk under a world XZ position has its collision built:
## the test a spawner or a physics object should make before trusting the
## ground to hold it.
func has_collision_at(position: Vector3) -> bool:
	return _bodies.has(Vector2i(floori(position.x / CHUNK), floori(position.z / CHUNK)))


func stop_streaming() -> void:
	if _streamer != null:
		_streamer.clear()
	for body in _bodies.values():
		body.queue_free()
	_bodies.clear()


func _refresh_wanted(force: bool) -> void:
	if not streaming:
		if force:
			var r := int(ceil(extent / CHUNK))
			var wanted := {}
			var order: Array = []
			for cz in range(-r, r):
				for cx in range(-r, r):
					wanted[Vector2i(cx, cz)] = 0
					order.append(Vector2i(cx, cz))
			_streamer.set_wanted(wanted, order)
		return
	var here := Vector2i(floori(focus_point.x / CHUNK), floori(focus_point.z / CHUNK))
	if here == _focus_chunk and not force:
		return
	_focus_chunk = here
	var set: Array = ChunkStreamer.disc(focus_point, CHUNK, radius)
	_streamer.set_wanted(set[0], set[1])


class _Job extends RefCounted:
	var terrain: TerrainProvider

	## WORKER THREAD: heights only, row-major (x fastest), as HeightMapShape3D
	## wants them.
	func run(coord: Vector2i, _variant: int) -> PackedFloat32Array:
		var origin := Vector2(coord) * TerrainCollision.CHUNK
		var ground := terrain.tile(Rect2(origin, Vector2.ONE * TerrainCollision.CHUNK))
		var heights := PackedFloat32Array()
		heights.resize(TerrainCollision.SAMPLES * TerrainCollision.SAMPLES)
		for iz in TerrainCollision.SAMPLES:
			for ix in TerrainCollision.SAMPLES:
				heights[iz * TerrainCollision.SAMPLES + ix] = ground.get_height(origin.x + float(ix), origin.y + float(iz))
		return heights


func _commit(coord: Vector2i, _variant: int, heights: PackedFloat32Array) -> void:
	var body: StaticBody3D = _bodies.get(coord)
	if body == null:
		body = StaticBody3D.new()
		body.name = "Collision_%d_%d" % [coord.x, coord.y]
		body.collision_layer = collision_layer
		body.collision_mask = 0
		# HeightMapShape3D is centred on its node: put the node at the
		# chunk's centre.
		body.position = Vector3((float(coord.x) + 0.5) * CHUNK, 0.0, (float(coord.y) + 0.5) * CHUNK)
		var shape_node := CollisionShape3D.new()
		shape_node.shape = HeightMapShape3D.new()
		body.add_child(shape_node)
		add_child(body)
		_bodies[coord] = body
	var shape: HeightMapShape3D = (body.get_child(0) as CollisionShape3D).shape
	shape.map_width = SAMPLES
	shape.map_depth = SAMPLES
	shape.map_data = heights


func _release(coord: Vector2i) -> void:
	if _bodies.has(coord):
		_bodies[coord].queue_free()
		_bodies.erase(coord)


func _exit_tree() -> void:
	if _streamer != null:
		_streamer.clear()
