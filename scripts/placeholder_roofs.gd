class_name PlaceholderRoofs
extends RefCounted

## Thread-safe pitched roofs and chimneys for geographic placeholder buildings
## (import: tools/geo/building_forms.py). A pitched roof covers the record's
## `roof.corners` rectangle; corners[0] -> corners[1] runs along the ridge and
## corners[0] -> corners[3] across it. The ridge sits at the building's drawn
## height, so OSM `height` keeps meaning the top of the roof, and the walls
## stop at the eaves. Footprint and height stay the observed placeholder's;
## the future building editor replaces this unchanged.

const PITCHED := ["gabled", "hipped", "pyramidal", "skillion"]
## Eaves overhang beyond the walls, and the smaller verge overhang at gables.
const OVERHANG := 0.35
const VERGE := 0.15
## Roof rise never exceeds this share of the drawn height (walls keep the rest).
const MAX_RISE_SHARE := 0.5
const STACK_SIDES := 14


## Rise of the record's pitched roof, or 0 when it draws a flat cap.
static func rise(record: Dictionary) -> float:
	var roof: Variant = record.get("roof")
	if not roof is Dictionary or not roof.get("shape", "flat") in PITCHED or (roof.get("corners", []) as Array).size() != 4:
		return 0.0
	return minf(float(roof.get("rise", 0.0)), MAX_RISE_SHARE * float(record.height))


## {"roof": arrays, "gables": arrays} for the record's pitched roof between
## `eaves` and `top`. Gables (and a skillion's high wall) take the wall material.
static func pitched(record: Dictionary, eaves: float, top: float) -> Dictionary:
	var frame := _frame(record.roof.corners)
	var a: float = frame.a
	var b: float = frame.b
	var height := top - eaves
	var roof := _tool(false)
	var gables := _tool(true)
	var at := func(x: float, y: float, h: float) -> Vector3:
		var p: Vector2 = frame.centre + frame.u * x + frame.v * y
		return Vector3(p.x, h, p.y)
	var up := Vector3.UP
	var u3 := Vector3(frame.u.x, 0.0, frame.u.y)
	var v3 := Vector3(frame.v.x, 0.0, frame.v.y)
	match String(record.roof.shape):
		"gabled":
			var slope := height / b
			var low := eaves - slope * OVERHANG
			var k := sqrt(1.0 + slope * slope)
			for side: float in [1.0, -1.0]:
				var e := (b + OVERHANG) * side
				_roof_quad(roof, [at.call(-a - VERGE, e, low), at.call(a + VERGE, e, low), at.call(a + VERGE, 0.0, top), at.call(-a - VERGE, 0.0, top)],
					[Vector2(-a - VERGE, (b + OVERHANG) * k), Vector2(a + VERGE, (b + OVERHANG) * k), Vector2(a + VERGE, 0.0), Vector2(-a - VERGE, 0.0)], up + v3 * side)
				_wall_tri(gables, [at.call(a * side, -b, eaves), at.call(a * side, b, eaves), at.call(a * side, 0.0, top)], u3 * side, eaves)
		"hipped", "pyramidal":
			var slope := height / b
			var low := eaves - slope * OVERHANG
			var k := sqrt(1.0 + slope * slope)
			var r := 0.0 if record.roof.shape == "pyramidal" else maxf(a - b, 0.0)
			var ea := a + OVERHANG
			var eb := b + OVERHANG
			for side: float in [1.0, -1.0]:
				_roof_quad(roof, [at.call(-ea, eb * side, low), at.call(ea, eb * side, low), at.call(r, 0.0, top), at.call(-r, 0.0, top)],
					[Vector2(-ea, eb * k), Vector2(ea, eb * k), Vector2(r, 0.0), Vector2(-r, 0.0)], up + v3 * side)
				_roof_tri(roof, [at.call(ea * side, -eb, low), at.call(ea * side, eb, low), at.call(r * side, 0.0, top)],
					[Vector2(-eb, (ea - r) * k), Vector2(eb, (ea - r) * k), Vector2(0.0, 0.0)], up + u3 * side)
		"skillion":
			# Low eaves on the -v side, the high wall on +v.
			var slope := height / (2.0 * b)
			var low := eaves - slope * OVERHANG
			var k := sqrt(1.0 + slope * slope)
			_roof_quad(roof, [at.call(-a - VERGE, -b - OVERHANG, low), at.call(a + VERGE, -b - OVERHANG, low), at.call(a + VERGE, b, top), at.call(-a - VERGE, b, top)],
				[Vector2(-a - VERGE, (2.0 * b + OVERHANG) * k), Vector2(a + VERGE, (2.0 * b + OVERHANG) * k), Vector2(a + VERGE, 0.0), Vector2(-a - VERGE, 0.0)], up - v3)
			_wall_tri(gables, [at.call(-a, b, eaves), at.call(a, b, eaves), at.call(a, b, top)], v3, eaves)
			_wall_tri(gables, [at.call(-a, b, eaves), at.call(a, b, top), at.call(-a, b, top)], v3, eaves)
			for side: float in [1.0, -1.0]:
				_wall_tri(gables, [at.call(a * side, -b, eaves), at.call(a * side, b, eaves), at.call(a * side, b, top)], u3 * side, eaves)
	return {"roof": _commit(roof), "gables": _commit(gables)}


## Surface arrays with flat normals, or [] when nothing was added.
static func _commit(tool: SurfaceTool) -> Array:
	var arrays := tool.commit_to_arrays()
	if arrays[Mesh.ARRAY_VERTEX] == null or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty(): return []
	tool.generate_normals()
	return tool.commit_to_arrays()


## Chimneys for the record: [{"arrays", "material", "smoke": Vector3, "season"}].
## House chimneys stand on the ridge above `top`; stacks rise from the ground.
static func chimneys(record: Dictionary, ground: HeightmapTerrainProvider, eaves: float, top: float) -> Array:
	var result := []
	var corners: Array = record.get("roof", {}).get("corners", []) if record.get("roof") is Dictionary else []
	var along := Vector2.RIGHT
	if corners.size() == 4: along = _frame(corners).u
	for chimney in record.get("chimneys", []):
		var xz := Vector2(float(chimney.xz[0]), float(chimney.xz[1]))
		var tool := _tool(false)
		var outlet: Vector3
		if chimney.get("kind") == "stack":
			var base := ground.get_height(xz.x, xz.y) - 0.5
			var height := float(chimney.height)
			var radius := float(chimney.diameter) * 0.5
			_stack(tool, xz, base, base + height, radius, radius * 0.75)
			outlet = Vector3(xz.x, base + height + 0.3, xz.y)
		else:
			var size: Array = chimney.get("size", [0.6, 0.9])
			var top_y := top + float(chimney.get("above_ridge", 0.9))
			_box(tool, xz, along, float(size[0]) * 0.5, float(size[1]) * 0.5, lerpf(eaves, top, 0.4), top_y)
			outlet = Vector3(xz.x, top_y + 0.15, xz.y)
		tool.generate_normals()
		result.append({"arrays": tool.commit_to_arrays(), "material": String(chimney.get("material", "brick")),
			"smoke": outlet, "season": String(chimney.get("smoke", "")), "stack": chimney.get("kind") == "stack"})
	return result


static func _frame(corners: Array) -> Dictionary:
	var c0 := Vector2(float(corners[0][0]), float(corners[0][1]))
	var c1 := Vector2(float(corners[1][0]), float(corners[1][1]))
	var c2 := Vector2(float(corners[2][0]), float(corners[2][1]))
	var c3 := Vector2(float(corners[3][0]), float(corners[3][1]))
	return {"centre": (c0 + c2) * 0.5, "u": (c1 - c0).normalized(), "v": (c3 - c0).normalized(),
		"a": c0.distance_to(c1) * 0.5, "b": c0.distance_to(c3) * 0.5}


static func _tool(wall: bool) -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	if wall:
		# PlaceholderWindows layout: a negative UV2.y seed draws no windows.
		tool.set_uv2(Vector2(1.0, -1.0))
		tool.set_color(Color.BLACK)
	return tool


## Adds a triangle whose front face points along `outward` (Godot fronts
## have (b - a) x (c - a) along the outward side here).
static func _add(tool: SurfaceTool, points: Array, uvs: Array, outward: Vector3) -> void:
	var order := [0, 1, 2]
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(outward) < 0.0: order = [0, 2, 1]
	for i in order:
		tool.set_uv(uvs[i])
		tool.add_vertex(points[i])


static func _roof_tri(tool: SurfaceTool, points: Array, uvs: Array, outward: Vector3) -> void:
	if (points[1] - points[0]).cross(points[2] - points[0]).length_squared() < 1e-8: return
	_add(tool, points, uvs, outward)
	# The underside, seen below the overhang.
	_add(tool, points, uvs, -outward)


static func _roof_quad(tool: SurfaceTool, points: Array, uvs: Array, outward: Vector3) -> void:
	_roof_tri(tool, [points[0], points[1], points[2]], [uvs[0], uvs[1], uvs[2]], outward)
	_roof_tri(tool, [points[0], points[2], points[3]], [uvs[0], uvs[2], uvs[3]], outward)


static func _wall_tri(tool: SurfaceTool, points: Array, outward: Vector3, eaves: float) -> void:
	var across := Vector2(points[1].x - points[0].x, points[1].z - points[0].z).normalized()
	var uvs := []
	for p in points: uvs.append(Vector2(Vector2(p.x - points[0].x, p.z - points[0].z).dot(across), p.y - eaves))
	_add(tool, points, uvs, outward)


static func _quad(tool: SurfaceTool, points: Array, outward: Vector3) -> void:
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	_add(tool, [points[0], points[1], points[2]], [uvs[0], uvs[1], uvs[2]], outward)
	_add(tool, [points[0], points[2], points[3]], [uvs[0], uvs[2], uvs[3]], outward)


static func _box(tool: SurfaceTool, xz: Vector2, along: Vector2, half_u: float, half_v: float, low: float, high: float) -> void:
	var across := Vector2(-along.y, along.x)
	var corner := func(su: float, sv: float, y: float) -> Vector3:
		var p := xz + along * half_u * su + across * half_v * sv
		return Vector3(p.x, y, p.y)
	# Each side: its two plan corners (as along/across signs); _add orients faces.
	for side in [[Vector2(1, -1), Vector2(1, 1)], [Vector2(-1, 1), Vector2(-1, -1)], [Vector2(1, 1), Vector2(-1, 1)], [Vector2(-1, -1), Vector2(1, -1)]]:
		var first: Vector2 = side[0]
		var second: Vector2 = side[1]
		var normal := along * (first.x + second.x) * 0.5 + across * (first.y + second.y) * 0.5
		_quad(tool, [corner.call(first.x, first.y, low), corner.call(second.x, second.y, low), corner.call(second.x, second.y, high), corner.call(first.x, first.y, high)], Vector3(normal.x, 0.0, normal.y))
	_quad(tool, [corner.call(-1.0, -1.0, high), corner.call(1.0, -1.0, high), corner.call(1.0, 1.0, high), corner.call(-1.0, 1.0, high)], Vector3.UP)


static func _stack(tool: SurfaceTool, xz: Vector2, low: float, high: float, bottom: float, top: float) -> void:
	for i in STACK_SIDES:
		var a := TAU * i / STACK_SIDES
		var b := TAU * (i + 1) / STACK_SIDES
		var da := Vector2(cos(a), sin(a))
		var db := Vector2(cos(b), sin(b))
		var outward := Vector3(da.x + db.x, 0.0, da.y + db.y)
		_quad(tool, [Vector3(xz.x + da.x * bottom, low, xz.y + da.y * bottom), Vector3(xz.x + db.x * bottom, low, xz.y + db.y * bottom),
			Vector3(xz.x + db.x * top, high, xz.y + db.y * top), Vector3(xz.x + da.x * top, high, xz.y + da.y * top)], outward)
		# A dark rim cap so the open top does not show the sky from above.
		_add(tool, [Vector3(xz.x, high - 0.4, xz.y), Vector3(xz.x + da.x * top, high, xz.y + da.y * top), Vector3(xz.x + db.x * top, high, xz.y + db.y * top)],
			[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.UP)
