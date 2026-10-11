class_name ImportedLakes
extends RefCounted

## OSM lakes and reservoirs from the same sidecar as ImportedRivers (which
## owns one of these as `lakes`). Each is a polygon (islands as holes),
## clipped to the world square by tools/geo/import_rivers.py.
##
## The same treatment W4.1 gives a river, for standing water: fit() finds
## the water level from the DEM, shape_at() carves a basin below it and
## lifts a low bank around it, and HeightmapTerrainProvider.get_height()
## applies that, so the drawn ground, collision and placement all hold the
## water WaterLayer draws as one flat mesh per lake. See docs/WATER.md, W4.2.
##
## Inside/outside is exact, not sampled: every 32 m cell knows which lake
## holds its centre, and a query counts the shore edges crossed between that
## centre and itself (all such edges are within the cell's own edge list).

const CELL_SIZE := 32.0
## Within this distance of the shoreline the ground follows the shaped
## profile exactly, so the waterline sits where OSM draws it.
const SHORE_BAND := 3.0
## The lakebed falls this many metres per metre from the shore, to MAX_DEPTH.
## No bathymetry exists; 8 m already reads as "deep" in water.gdshader.
const SHORE_SLOPE := 0.2
const MAX_DEPTH := 8.0
## Ground just outside the shore is lifted (never lowered) to rise this many
## metres per metre above the water, so the mesh edge is always buried.
const BANK_SLOPE := 0.45
## Beyond SHORE_BAND, shaping fades back to the natural ground over this.
const BLEND := 10.0
## Edges are indexed out to here from each cell: the bed reaches MAX_DEPTH at
## MAX_DEPTH / SHORE_SLOPE from shore, the bank blend ends at SHORE_BAND + BLEND.
const REACH := 40.0
## The water mesh reaches this far past the shoreline into the rising bank.
const MESH_OVERLAP := 1.0

var outers: Array[PackedVector2Array] = []
## Per lake, its islands (each a PackedVector2Array).
var holes: Array[Array] = []
var names := PackedStringArray()
## Water level per lake, after fit().
var levels := PackedFloat32Array()

var _edge_a := PackedVector2Array()
var _edge_b := PackedVector2Array()
var _edge_lake := PackedInt32Array()
## 1 for a real shore, 0 for an edge the importer made by clipping the lake
## to the world square: it bounds the water but is not a bank.
var _edge_shore := PackedByteArray()
var _cells: Dictionary = {}
var _cell_lake: Dictionary = {}
var _no_edges := PackedInt32Array()


static func from_data(lakes: Array, world_size: float) -> ImportedLakes:
	var result := ImportedLakes.new()
	var half := world_size * 0.5
	for lake in lakes:
		var outer := _ring(lake.outer)
		var islands: Array = []
		for hole in lake.holes:
			islands.append(_ring(hole))
		var index := result.outers.size()
		result.outers.append(outer)
		result.holes.append(islands)
		result.names.append(lake.get("name", ""))
		result.levels.append(0.0)
		result._index_ring(outer, index, half)
		for island in islands:
			result._index_ring(island, index, half)
		result._mark_cells(index)
	return result


static func valid_data(lakes: Variant, world_size: float) -> bool:
	if not lakes is Array or lakes.size() > 2000:
		return false
	var count := 0
	for lake in lakes:
		if not lake is Dictionary or not lake.get("outer") is Array or not lake.get("holes") is Array:
			return false
		var rings: Array = [lake.outer] + lake.holes
		for ring in rings:
			if not ring is Array or ring.size() < 3:
				return false
			count += ring.size()
			if count > 200000:
				return false
			for point in ring:
				if not point is Array or point.size() != 2 or not ImportedRivers._number(point[0]) or not ImportedRivers._number(point[1]):
					return false
				if absf(point[0]) > world_size * 0.5 + 0.01 or absf(point[1]) > world_size * 0.5 + 0.01:
					return false
	return true


func size() -> int:
	return outers.size()


## Water level per lake from the uncarved DEM: the median inside the polygon
## (GLO-30 flattens real lakes to their surface, so this is usually exact),
## held no higher than the low end of its shoreline, so a pond the DEM never
## resolved does not stand above its own banks.
func fit(ground: Callable) -> void:
	for lake in outers.size():
		var outer := outers[lake]
		var bounds := Rect2(outer[0], Vector2.ZERO)
		for p in outer:
			bounds = bounds.expand(p)
		var step := maxf(10.0, sqrt(bounds.get_area() / 4000.0))
		var inside := PackedFloat32Array()
		var y := bounds.position.y + step * 0.5
		while y < bounds.end.y:
			var x := bounds.position.x + step * 0.5
			while x < bounds.end.x:
				var p := Vector2(x, y)
				if _in_water(p, lake):
					inside.append(ground.call(x, y))
				x += step
			y += step
		var shore := PackedFloat32Array()
		for i in _edge_a.size():
			if _edge_lake[i] != lake or _edge_shore[i] == 0:
				continue
			var a := _edge_a[i]
			var b := _edge_b[i]
			var n := maxi(1, ceili(a.distance_to(b) / 10.0))
			for k in n:
				var p := a.lerp(b, float(k) / n)
				shore.append(ground.call(p.x, p.y))
		var level := 0.0
		if not inside.is_empty():
			inside.sort()
			level = inside[inside.size() / 2]
		if not shore.is_empty():
			shore.sort()
			var low := shore[shore.size() / 10]
			level = low if inside.is_empty() else minf(level, low)
		levels[lake] = level


## Signed distance to the nearest real shore (negative in the water) and
## which lake, as (distance, lake). (INF, -1) far from any lake; (-INF,
## lake) deep inside one, beyond REACH of its shore.
func signed_distance(x: float, z: float) -> Vector2:
	var key := Vector2i(floori(x / CELL_SIZE), floori(z / CELL_SIZE))
	var centre_lake: int = _cell_lake.get(key, -1)
	var edges: PackedInt32Array = _cells.get(key, _no_edges)
	if edges.is_empty():
		return Vector2(-INF, centre_lake) if centre_lake >= 0 else Vector2(INF, -1)
	var point := Vector2(x, z)
	var best := INF
	var lake := centre_lake
	for index in edges:
		if _edge_shore[index] == 0:
			continue
		var nearest := Geometry2D.get_closest_point_to_segment(point, _edge_a[index], _edge_b[index])
		var d := point.distance_to(nearest)
		if d < best:
			best = d
			lake = _edge_lake[index]
	if lake < 0:
		return Vector2(INF, -1)
	# Parity from the cell centre, whose side is known, to this point.
	var centre := (Vector2(key) + Vector2(0.5, 0.5)) * CELL_SIZE
	var wet := centre_lake == lake
	for index in edges:
		if _edge_lake[index] == lake and _crosses(centre, point, _edge_a[index], _edge_b[index]):
			wet = not wet
	if best == INF:
		return Vector2(-INF, lake) if wet else Vector2(INF, -1)
	return Vector2(-best if wet else best, lake)


## Whether `area` (world XZ) might hold lake water: any of its index cells
## lies in a lake or near a shore.
func has_water_in(area: Rect2) -> bool:
	for z in range(floori(area.position.y / CELL_SIZE), floori(area.end.y / CELL_SIZE) + 1):
		for x in range(floori(area.position.x / CELL_SIZE), floori(area.end.x / CELL_SIZE) + 1):
			var key := Vector2i(x, z)
			if _cell_lake.has(key) or _cells.has(key):
				return true
	return false


## Shaped ground given the natural ground: x = height, y = lakebed (1 under
## water), z = damp shore, w = signed distance (negative in the water).
func shape_at(x: float, z: float, natural: float) -> Vector4:
	var sd := signed_distance(x, z)
	var s := sd.x
	if s >= SHORE_BAND + BLEND:
		return Vector4(natural, 0.0, 0.0, s)
	var level := levels[int(sd.y)]
	var target := level + (s * BANK_SLOPE if s >= 0.0 else maxf(s * SHORE_SLOPE, -MAX_DEPTH))
	var weight := 1.0 - smoothstep(SHORE_BAND, SHORE_BAND + BLEND, absf(s))
	var height: float
	if s < 0.0:
		# Underwater: never above the bed profile; exactly it near the shore.
		height = lerpf(minf(natural, target), target, weight)
	else:
		# Ashore: low ground lifted to a bank, higher ground left alone.
		height = lerpf(natural, maxf(natural, target), weight)
	return Vector4(height, 1.0 - smoothstep(-0.5, 0.3, s), 1.0 - smoothstep(0.0, 5.0, s), s)


func marks_at(x: float, z: float) -> Vector2:
	var s := signed_distance(x, z).x
	return Vector2(1.0 - smoothstep(-0.5, 0.3, s), 1.0 - smoothstep(0.0, 5.0, s))


func growth_mask(x: float, z: float) -> float:
	return smoothstep(0.3, 2.0, signed_distance(x, z).x)


## The lake's water surface: its outline grown MESH_OVERLAP into the bank,
## triangulated flat at its level. Islands are not cut out -- their ground
## stands above the water and hides it, as the shore does.
func build_mesh(lake: int) -> ArrayMesh:
	var level := levels[lake]
	var outer := outers[lake]
	var orientation := signf(_signed_area(outer))
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for polygon in Geometry2D.offset_polygon(outer, MESH_OVERLAP, Geometry2D.JOIN_MITER):
		if signf(_signed_area(polygon)) != orientation:
			continue  # a hole the offset produced
		var triangles := Geometry2D.triangulate_polygon(polygon)
		if triangles.is_empty():
			# Ear clipping can fail on a self-touching outline; convex pieces
			# always triangulate as fans.
			for piece in Geometry2D.decompose_polygon_in_convex(polygon):
				_append_fan(piece, level, verts, indices)
			continue
		var base := verts.size()
		for p in polygon:
			verts.append(Vector3(p.x, level, p.y))
		for t in range(0, triangles.size(), 3):
			_append_up_facing(base + triangles[t], base + triangles[t + 1], base + triangles[t + 2], verts, indices)
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for v in verts:
		normals.append(Vector3.UP)
		uvs.append(Vector2(v.x, v.z))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _in_water(p: Vector2, lake: int) -> bool:
	if not Geometry2D.is_point_in_polygon(p, outers[lake]):
		return false
	for island: PackedVector2Array in holes[lake]:
		if Geometry2D.is_point_in_polygon(p, island):
			return false
	return true


func _index_ring(ring: PackedVector2Array, lake: int, half: float) -> void:
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var on_edge := (is_equal_approx(absf(a.x), half) and is_equal_approx(a.x, b.x)) \
			or (is_equal_approx(absf(a.y), half) and is_equal_approx(a.y, b.y))
		var index := _edge_a.size()
		_edge_a.append(a)
		_edge_b.append(b)
		_edge_lake.append(lake)
		_edge_shore.append(0 if on_edge else 1)
		var bounds := Rect2(a, Vector2.ZERO).expand(b).grow(REACH)
		for z in range(floori(bounds.position.y / CELL_SIZE), floori(bounds.end.y / CELL_SIZE) + 1):
			for x in range(floori(bounds.position.x / CELL_SIZE), floori(bounds.end.x / CELL_SIZE) + 1):
				var key := Vector2i(x, z)
				if not _cells.has(key):
					_cells[key] = PackedInt32Array()
				# Shared by reference: appending here updates the stored array.
				var list: PackedInt32Array = _cells[key]
				list.append(index)


func _mark_cells(lake: int) -> void:
	var outer := outers[lake]
	var bounds := Rect2(outer[0], Vector2.ZERO)
	for p in outer:
		bounds = bounds.expand(p)
	for z in range(floori(bounds.position.y / CELL_SIZE), floori(bounds.end.y / CELL_SIZE) + 1):
		for x in range(floori(bounds.position.x / CELL_SIZE), floori(bounds.end.x / CELL_SIZE) + 1):
			var key := Vector2i(x, z)
			if _in_water((Vector2(key) + Vector2(0.5, 0.5)) * CELL_SIZE, lake):
				_cell_lake[key] = lake


func _append_fan(piece: PackedVector2Array, level: float, verts: PackedVector3Array, indices: PackedInt32Array) -> void:
	var base := verts.size()
	for p in piece:
		verts.append(Vector3(p.x, level, p.y))
	for k in range(1, piece.size() - 1):
		_append_up_facing(base, base + k, base + k + 1, verts, indices)


## Godot's front faces wind clockwise seen from the normal's side; the water
## must face +Y whatever order the triangulation returned.
static func _append_up_facing(a: int, b: int, c: int, verts: PackedVector3Array, indices: PackedInt32Array) -> void:
	if (verts[b] - verts[a]).cross(verts[c] - verts[a]).y < 0.0:
		indices.append_array([a, b, c])
	else:
		indices.append_array([a, c, b])


static func _crosses(p: Vector2, q: Vector2, a: Vector2, b: Vector2) -> bool:
	var d1 := (q - p).cross(a - p)
	var d2 := (q - p).cross(b - p)
	if (d1 > 0.0) == (d2 > 0.0):
		return false
	var d3 := (b - a).cross(p - a)
	var d4 := (b - a).cross(q - a)
	return (d3 > 0.0) != (d4 > 0.0)


static func _signed_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size():
		area += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return area * 0.5


static func _ring(points: Array) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for point in points:
		ring.append(Vector2(point[0], point[1]))
	return ring
