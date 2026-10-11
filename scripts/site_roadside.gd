class_name SiteRoadside
extends Node3D

## Kerbs, pavements and street furniture along an imported site's roads, by
## road context (tools/geo/settlements.py `context_spans`): rural roads keep
## soft grass verges (the ROAD zone) and no furniture; village streets get a
## kerbed pavement where buildings front them, the odd bench and bin; town
## streets kerbs and pavements both sides, benches, bins and traffic lights at
## main junctions. Street lamps are SiteStreetLights. Every position is
## INFERRED from road records at load; nothing is written back to the bake.
##
## Assets: POLY TownCity (tools/geo/import_town_pack.gd), scaled at placement
## (the kit's small furniture is authored at about 0.6 of real size). The
## packs have no road signs, bus stops, post boxes or rural delineator posts.

const TOWN_ASSETS := "res://assets/town/poly_towncity/"
## asset -> placement scale.
const SCALE := {"bench_1": 1.3, "bench_2": 1.3, "bench_3": 1.3, "bin_1": 1.75, "bin_2": 1.75, "bin_3": 1.75,
	"traffic_light": 1.0, "bollard_light": 1.0}
const BENCHES := ["bench_1", "bench_2", "bench_3"]
const BINS := ["bin_1", "bin_2", "bin_3"]
## Distance between benches along a context's pavement or verge, metres.
const BENCH_SPACING := {"village": 400.0, "town": 120.0}
## Town pavements also get a bin between benches.
const TOWN_BIN_SPACING := 60.0
## Junctions of these classes inside a town get traffic lights.
const SIGNAL_CLASSES := ["primary", "secondary", "tertiary"]
## Pavement surface above the ground, and kerb width on its road side.
const PAVEMENT_RISE := 0.15
const KERB_WIDTH := 0.16
## The road ribbon's own offset above the terrain (SiteRouteMesh).
const ROUTE_RISE := 0.055
const STEP := 1.5
const VISIBLE_RANGE := 300.0
const DRIVABLE := ["primary", "secondary", "tertiary", "unclassified", "residential", "living_street", "service"]

var terrain: HeightmapTerrainProvider
## Set before entering the tree to build progressively: planning on a worker,
## then each pavement and furniture item through the queue (LocationSiteLayer).
var queue: SiteBuildQueue
var pavement_count := 0
var pavement_length := 0.0
var furniture: Array[Dictionary] = []
var _scenes := {}
var _paving: ShaderMaterial
var _kerb: StandardMaterial3D

func _ready() -> void:
	# Without a site (previews, tests) the builders are used directly.
	if terrain == null or terrain.imported_site == null:
		return
	var data: Dictionary = terrain.imported_site.data
	_paving = ShaderMaterial.new()
	_paving.shader = SiteRouteMesh.SHADER
	_paving.set_shader_parameter("surface_kind", SiteRouteMesh.SURFACES.find("paving"))
	_paving.set_shader_parameter("paving_colour", Color(.53, .52, .49))
	_paving.set_shader_parameter("route_width", 1.5)
	_kerb = StandardMaterial3D.new()
	_kerb.albedo_color = Color(.66, .65, .62)
	_kerb.roughness = .9
	if queue != null:
		queue.add(queue.origin, Callable(SiteRoadside, "_prepare").bind(data, terrain.get_height), _prepared)
		return
	var carriageways := Carriageways.new(data.get("roads", []))
	var footprints := _footprints(data)
	for index in data.get("roads", []).size():
		var road: Dictionary = data.roads[index]
		_add_pavement(pavement_mesh(road, index, terrain.get_height, carriageways, footprints, _paving, _kerb))
	furniture = plan(data, terrain.get_height, carriageways, footprints)
	for item in furniture:
		_place(item)


## WORKER THREAD: the lookups pavements are cut against, and the furniture plan.
static func _prepare(data: Dictionary, height: Callable) -> Array:
	var carriageways := Carriageways.new(data.get("roads", []))
	var footprints := _footprints(data)
	return [carriageways, footprints, plan(data, height, carriageways, footprints)]


## MAIN THREAD: queues each road's pavement (nearest first) and the furniture.
func _prepared(prepared: Array) -> void:
	var roads: Array = terrain.imported_site.data.get("roads", [])
	var build := Callable(SiteRoadside, "pavement_arrays")
	for index in roads.size():
		var road: Dictionary = roads[index]
		queue.add_along(road.points, build.bind(road, index, terrain.get_height, prepared[0], prepared[1]),
			func(data: Dictionary) -> void: _add_pavement(pavement_instance(road, data, _paving, _kerb)))
	furniture.assign(prepared[2])
	for item in furniture:
		queue.then(_place.bind(item))


func _add_pavement(instance: MeshInstance3D) -> void:
	if instance == null: return
	add_child(instance)
	pavement_count += 1


## Raised pavement and kerb strips for one road's village/town spans, with
## walkable collision. Null when the road has none.
func pavement_mesh(road: Dictionary, index: int, height: Callable, carriageways: Carriageways,
		footprints: Footprints, paving: Material, kerb: Material) -> MeshInstance3D:
	return pavement_instance(road, pavement_arrays(road, index, height, carriageways, footprints), paving, kerb)


## Thread-safe pavement geometry for one road: {surface, edge, length}, or {}
## when the road has none.
static func pavement_arrays(road: Dictionary, index: int, height: Callable, carriageways: Carriageways,
		footprints: Footprints) -> Dictionary:
	var length := 0.0
	var spans: Array = road.get("context_spans", [])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge := SurfaceTool.new()
	edge.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 0
	# A hair of height per road keeps crossing pavements from z-fighting.
	var rise := PAVEMENT_RISE + 0.002 * (index % 5)
	var half := float(road.width) * 0.5 + 0.1
	for span in spans:
		for side in [1.0, -1.0]:
			var width := float(span[3]) if side > 0.0 else float(span[4])
			if width <= 0.0: continue
			var samples := _samples(road.points, float(span[0]), float(span[1]))
			for i in samples.size() - 1:
				var a: Array = samples[i]
				var b: Array = samples[i + 1]
				var na: Vector2 = a[1] * side
				var nb: Vector2 = b[1] * side
				var inner_a: Vector2 = a[0] + na * half
				var inner_b: Vector2 = b[0] + nb * half
				var outer_a: Vector2 = a[0] + na * (half + width)
				var outer_b: Vector2 = b[0] + nb * (half + width)
				var middle := (inner_a + outer_b) * 0.5
				# Stop at other roads' carriageways and at buildings.
				if carriageways.inside(middle, road) or carriageways.inside(outer_a, road) or footprints.inside(middle): continue
				var kerb_a: Vector2 = a[0] + na * (half + KERB_WIDTH)
				var kerb_b: Vector2 = b[0] + nb * (half + KERB_WIDTH)
				_quad(surface, [kerb_a, kerb_b, outer_b, outer_a], height, rise, Vector2(0.0, float(a[2])))
				_quad(edge, [inner_a, inner_b, kerb_b, kerb_a], height, rise, Vector2.ONE)
				# Kerb face down to the road surface.
				_face(edge, inner_a, inner_b, height, ROUTE_RISE, rise)
				quads += 1
				length += a[0].distance_to(b[0])
	if quads == 0:
		return {}
	surface.generate_normals()
	edge.generate_normals()
	return {"surface": surface.commit_to_arrays(), "edge": edge.commit_to_arrays(), "length": length}


## MAIN THREAD. The pavement node for pavement_arrays(); null for {}.
func pavement_instance(road: Dictionary, data: Dictionary, paving: Material, kerb: Material) -> MeshInstance3D:
	if data.is_empty():
		return null
	pavement_length += float(data.length)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data.surface)
	mesh.surface_set_material(0, paving)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data.edge)
	mesh.surface_set_material(1, kerb)
	var instance := MeshInstance3D.new()
	instance.name = "Pavement_" + String(road.source_id).replace("/", "_")
	instance.mesh = mesh
	instance.set_meta("geographic_record", road.source_id)
	instance.set_meta("placement_basis", "inferred")
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	instance.add_child(body)
	return instance


## Furniture placements {asset, position, yaw, scale, road, basis} for a site.
static func plan(data: Dictionary, height: Callable, carriageways: Carriageways = null, footprints: Footprints = null) -> Array[Dictionary]:
	if carriageways == null: carriageways = Carriageways.new(data.get("roads", []))
	if footprints == null: footprints = _footprints(data)
	var result: Array[Dictionary] = []
	var taken: Array[Vector2] = []
	for road in data.get("roads", []):
		var highway := str(road.get("tags", {}).get("highway", ""))
		if highway not in DRIVABLE or highway == "service": continue
		var half := float(road.width) * 0.5 + 0.1
		var seed := hash(str(road.get("source_id", "")))
		for span in road.get("context_spans", []):
			var context := str(span[2])
			if not BENCH_SPACING.has(context): continue
			var length := float(span[1]) - float(span[0])
			var left := float(span[3])
			var right := float(span[4])
			var side := 1.0 if left >= right else -1.0
			var pavement := maxf(left, right)
			# Furniture stands at the back of the pavement, or on the verge.
			var offset := half + (pavement - 0.45 if pavement > 0.0 else 1.6)
			var spacing: float = BENCH_SPACING[context]
			var start := fposmod(float(seed % 997), spacing) * 0.5 + 15.0
			var at := start
			while at < length - 10.0:
				var bench := _spot(road, float(span[0]) + at, offset, side)
				if _usable(bench[0], road, carriageways, footprints, taken):
					var asset: String = BENCHES[posmod(seed + int(at), BENCHES.size())]
					result.append(_item(asset, bench, height, road, 0.0))
					taken.append(bench[0])
					var beside := _spot(road, float(span[0]) + at + 2.4, offset, side)
					if _usable(beside[0], road, carriageways, footprints, taken):
						result.append(_item(BINS[posmod(seed + int(at), BINS.size())], beside, height, road, 0.0))
						taken.append(beside[0])
				at += spacing
			if context == "town":
				at = start + TOWN_BIN_SPACING * 0.5
				while at < length - 5.0:
					for s in ([1.0, -1.0] if left > 0.0 and right > 0.0 else [side]):
						var spot := _spot(road, float(span[0]) + at, half + maxf(left if s > 0.0 else right, 0.6) - 0.45, s)
						if _usable(spot[0], road, carriageways, footprints, taken):
							result.append(_item(BINS[posmod(seed + int(at), BINS.size())], spot, height, road, 0.0))
							taken.append(spot[0])
					at += TOWN_BIN_SPACING
	result.append_array(_signals(data, height, carriageways, footprints, taken))
	return result


## Traffic lights where two or more town main roads meet: one on the near
## corner of each approach, arm reaching over its carriageway.
static func _signals(data: Dictionary, height: Callable, carriageways: Carriageways, footprints: Footprints, taken: Array[Vector2]) -> Array[Dictionary]:
	var ends := {}
	for road in data.get("roads", []):
		if str(road.get("tags", {}).get("highway", "")) not in SIGNAL_CLASSES: continue
		var spans: Array = road.get("context_spans", [])
		if spans.is_empty(): continue
		var points: Array = road.points
		for end in [0, points.size() - 1]:
			var span: Array = spans[0] if end == 0 else spans[-1]
			if str(span[2]) != "town": continue
			var key := Vector2i(roundi(points[end][0] / 4.0), roundi(points[end][1] / 4.0))
			ends[key] = ends.get(key, []) + [[road, end]]
	var result: Array[Dictionary] = []
	for key in ends:
		var approaches: Array = ends[key]
		if approaches.size() < 2: continue
		for approach in approaches:
			var road: Dictionary = approach[0]
			var points: Array = road.points
			var length := _length(points)
			var span: Array = road.context_spans[0] if approach[1] == 0 else road.context_spans[-1]
			var distance := 6.0 if approach[1] == 0 else length - 6.0
			var pavement := float(span[4]) if approach[1] == 0 else float(span[3])
			var side := -1.0 if approach[1] == 0 else 1.0
			var spot := _spot(road, distance, float(road.width) * 0.5 + maxf(pavement, 1.0) - 0.4, side)
			if not _usable(spot[0], road, carriageways, footprints, taken): continue
			# The kit's arm reaches along +Z: turn it over the carriageway.
			var to_road: Vector2 = -spot[1] * side
			result.append({"asset": "traffic_light", "position": Vector3(spot[0].x, height.call(spot[0].x, spot[0].y), spot[0].y),
				"yaw": atan2(to_road.x, to_road.y), "scale": SCALE.traffic_light, "road": str(road.get("source_id", "")), "basis": "inferred"})
			taken.append(spot[0])
	return result


static func _item(asset: String, spot: Array, height: Callable, road: Dictionary, extra_yaw: float) -> Dictionary:
	var point: Vector2 = spot[0]
	var normal: Vector2 = spot[1]
	# Seats face the road: the kit's bench front is +Z.
	var facing := -normal
	return {"asset": asset, "position": Vector3(point.x, height.call(point.x, point.y), point.y),
		"yaw": atan2(facing.x, facing.y) + extra_yaw, "scale": SCALE[asset], "road": str(road.get("source_id", "")), "basis": "inferred"}


## [point, outward unit normal] `offset` metres to one side at `distance`.
static func _spot(road: Dictionary, distance: float, offset: float, side: float) -> Array:
	var points: Array = road.points
	var travelled := 0.0
	for i in points.size() - 1:
		var a := Vector2(points[i][0], points[i][1])
		var b := Vector2(points[i + 1][0], points[i + 1][1])
		var length := a.distance_to(b)
		if length > 0.0 and travelled + length >= distance:
			var d := (b - a) / length
			var normal := Vector2(-d.y, d.x) * side
			return [a.lerp(b, (distance - travelled) / length) + normal * offset, normal]
		travelled += length
	var last := Vector2(points[-1][0], points[-1][1])
	return [last, Vector2.RIGHT]


static func _usable(point: Vector2, road: Dictionary, carriageways: Carriageways, footprints: Footprints, taken: Array[Vector2]) -> bool:
	if footprints.inside(point) or carriageways.inside(point, road, 0.8):
		return false
	for other in taken:
		if point.distance_squared_to(other) < 4.0: return false
	return true


static func _length(points: Array) -> float:
	var total := 0.0
	for i in points.size() - 1:
		total += Vector2(points[i][0], points[i][1]).distance_to(Vector2(points[i + 1][0], points[i + 1][1]))
	return total


## Centre-line samples [point, left unit normal, distance] every STEP metres
## between two distances along a polyline, mitred at corners.
static func _samples(points: Array, start: float, end: float) -> Array:
	var line: Array = []
	var travelled := 0.0
	for i in points.size() - 1:
		var a := Vector2(points[i][0], points[i][1])
		var b := Vector2(points[i + 1][0], points[i + 1][1])
		var length := a.distance_to(b)
		if length < 0.001: continue
		var d := (b - a) / length
		var t := maxf(start - travelled, 0.0)
		while t <= length and travelled + t <= end:
			line.append([a + d * t, Vector2(-d.y, d.x), travelled + t])
			t += STEP
		travelled += length
		if travelled >= end: break
	return line


static func _quad(st: SurfaceTool, corners: Array, height: Callable, rise: float, uv: Vector2) -> void:
	for k in [0, 2, 1, 0, 3, 2]:
		var p: Vector2 = corners[k]
		st.set_uv(Vector2(1.0 if k >= 2 else 0.0, uv.y))
		st.add_vertex(Vector3(p.x, float(height.call(p.x, p.y)) + rise, p.y))


static func _face(st: SurfaceTool, a: Vector2, b: Vector2, height: Callable, low: float, high: float) -> void:
	var ha := float(height.call(a.x, a.y))
	var hb := float(height.call(b.x, b.y))
	var corners := [Vector3(a.x, ha + low, a.y), Vector3(b.x, hb + low, b.y), Vector3(b.x, hb + high, b.y), Vector3(a.x, ha + high, a.y)]
	for k in [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]:
		st.add_vertex(corners[k])


func _place(item: Dictionary) -> void:
	var asset: String = item.asset
	if not _scenes.has(asset):
		_scenes[asset] = load(TOWN_ASSETS + asset + ".glb")
	var scene: PackedScene = _scenes[asset]
	if scene == null: return
	var node := scene.instantiate() as Node3D
	node.name = "%s_%d" % [asset, get_child_count()]
	node.position = item.position
	node.rotation.y = item.yaw
	node.scale = Vector3.ONE * float(item.scale)
	node.set_meta("placement_basis", "inferred")
	node.set_meta("road", item.road)
	for child in node.find_children("*", "GeometryInstance3D", true, false):
		(child as GeometryInstance3D).visibility_range_end = VISIBLE_RANGE
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.12 if asset == "traffic_light" else 0.25
	cylinder.height = 4.0 if asset == "traffic_light" else 0.9
	shape.shape = cylinder
	shape.position.y = cylinder.height * 0.5
	body.add_child(shape)
	node.add_child(body)
	add_child(node)


static func _footprints(data: Dictionary) -> Footprints:
	return Footprints.new(data.get("buildings", []))


## Bucketed point-in-footprint test (villages have hundreds of buildings).
class Footprints:
	var _cells := {}
	const CELL := 50.0
	func _init(buildings: Array) -> void:
		for building in buildings:
			var ring := PackedVector2Array()
			for p in building.outline: ring.append(Vector2(p[0], p[1]))
			if ring.size() < 3: continue
			var box := Rect2(ring[0], Vector2.ZERO)
			for q in ring: box = box.expand(q)
			for x in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
				for z in range(floori(box.position.y / CELL), floori(box.end.y / CELL) + 1):
					var key := Vector2i(x, z)
					if not _cells.has(key): _cells[key] = []
					_cells[key].append(ring)
	func inside(point: Vector2) -> bool:
		for ring in _cells.get(Vector2i(floori(point.x / CELL), floori(point.y / CELL)), []):
			if Geometry2D.is_point_in_polygon(point, ring): return true
		return false


## Bucketed "is this on another drivable road's carriageway" test.
class Carriageways:
	var _cells := {}
	const CELL := 40.0
	func _init(roads: Array) -> void:
		for road in roads:
			if str(road.get("tags", {}).get("highway", "")) not in SiteRoadside.DRIVABLE: continue
			var points: Array = road.points
			for i in points.size() - 1:
				var a := Vector2(points[i][0], points[i][1])
				var b := Vector2(points[i + 1][0], points[i + 1][1])
				var box := Rect2(a, Vector2.ZERO).expand(b).grow(float(road.width))
				for x in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
					for z in range(floori(box.position.y / CELL), floori(box.end.y / CELL) + 1):
						var key := Vector2i(x, z)
						if not _cells.has(key): _cells[key] = []
						_cells[key].append([a, b, float(road.width) * 0.5, road])
	## True when `point` lies within another road's carriageway plus `margin`.
	func inside(point: Vector2, own: Dictionary, margin: float = 0.3) -> bool:
		for segment in _cells.get(Vector2i(floori(point.x / CELL), floori(point.y / CELL)), []):
			if is_same(segment[3], own): continue
			var closest := Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1])
			if point.distance_to(closest) < float(segment[2]) + margin: return true
		return false
