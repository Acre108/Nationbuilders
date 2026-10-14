extends RefCounted
## Ground relief from the grid's levels and ramps (docs/WORLD_MAP.md §5.1).
## MeshFactory.terrain() still decides the ground's colour; apply() lifts that
## flat mesh onto the relief and adds the vertical faces: cliffs, river banks,
## waterfalls and the edge of the map. Presentation only; never touches sim state.
const LEVEL_HEIGHT := 1.0
const WATER_DEPTH := 0.08
## Top of the soil block MeshFactory puts under the map.
const EDGE_BOTTOM := -0.1
const CLIFF_TOP := Color("8b8172")
const CLIFF_FOOT := Color("57514a")
const BANK := Color("6b5a45")
const FOAM := Color("d4e4de")
const EDGE := Color("6b6152")
var grid
## Highest ground in the site, for ray marching.
var top := 0.0

func _init(site_grid) -> void:
	grid = site_grid
	for level in grid.levels:
		top = maxf(top, level * LEVEL_HEIGHT)

## Corner heights clockwise from the tile's (x, y) corner: (x,y), (x+1,y),
## (x+1,y+1), (x,y+1). A ramp lowers the corners on its edges that face the
## level below, so it slopes down to meet that ground.
func corner_heights(cell: Vector2i) -> PackedFloat32Array:
	var level: int = grid.level_at(cell)
	var base := level * LEVEL_HEIGHT - (WATER_DEPTH if grid.is_water(cell) else 0.0)
	var heights := PackedFloat32Array([base, base, base, base])
	if grid.is_ramp(cell):
		var low := []
		for direction in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbour: Vector2i = cell + direction
			low.append(grid.inside(neighbour) and grid.level_at(neighbour) == level - 1)
		for corner in 4:
			# Corner k sits between edge k (left, up, right, down) and the one before it.
			if low[corner] or low[(corner + 1) % 4]:
				heights[corner] = base - LEVEL_HEIGHT
	return heights

## Ground height at a world XZ point, interpolated across its tile.
func surface_height(point: Vector2) -> float:
	var cell := Vector2i(floori(point.x), floori(point.y))
	if not grid.inside(cell):
		return 0.0
	return _bilinear(corner_heights(cell), point - Vector2(cell))

func cell_height(cell: Vector2i) -> float:
	return surface_height(Vector2(cell) + Vector2(0.5, 0.5))

## Tilts and lifts a node holding absolute-positioned tile geometry (a road)
## onto its tile, pivoting on the tile centre. Flat level-0 tiles are untouched.
func seat(node: Node3D, cell: Vector2i) -> void:
	var h := corner_heights(cell)
	var centre := Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)
	var dx := ((h[1] + h[2]) - (h[0] + h[3])) * 0.5
	var dz := ((h[3] + h[2]) - (h[0] + h[1])) * 0.5
	var basis := Basis(Quaternion(Vector3.UP, Vector3(-dx, 1.0, -dz).normalized()))
	node.transform = Transform3D(basis, centre + Vector3.UP * cell_height(cell) - basis * centre)

func apply(factory) -> void:
	var node: MeshInstance3D = factory.terrain_node
	if node == null or node.mesh == null:
		return
	var source: Array = node.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = source[Mesh.ARRAY_COLOR]
	var out := {"vertex": PackedVector3Array(), "normal": PackedVector3Array(), "color": PackedColorArray(), "uv": PackedVector2Array()}
	var water_colour: Color = factory.art.water_turquoise.srgb_to_linear()
	for index in range(0, vertices.size() - 2, 3):
		var centroid := (vertices[index] + vertices[index + 1] + vertices[index + 2]) / 3.0
		var cell := Vector2i(floori(centroid.x), floori(centroid.z))
		if not grid.inside(cell): continue
		var heights := corner_heights(cell)
		var water: bool = grid.is_water(cell)
		var lifted: Array[Vector3] = []
		for k in 3:
			var v: Vector3 = vertices[index + k]
			var local := Vector2(v.x - cell.x, v.z - cell.y).clamp(Vector2.ZERO, Vector2.ONE)
			lifted.append(Vector3(v.x, _bilinear(heights, local), v.z))
		var normal := (lifted[2] - lifted[0]).cross(lifted[1] - lifted[0]).normalized()
		for k in 3:
			out.vertex.append(lifted[k])
			out.normal.append(normal)
			out.color.append(water_colour if water else colors[index + k])
			# UV.x flags water and UV.y flags walls for village_ground.gdshader.
			out.uv.append(Vector2(1.0 if water else 0.0, 0.0))
	_add_walls(factory, out)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out.vertex
	arrays[Mesh.ARRAY_NORMAL] = out.normal
	arrays[Mesh.ARRAY_COLOR] = out.color
	arrays[Mesh.ARRAY_TEX_UV] = out.uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	node.mesh = mesh

## One vertical face wherever two neighbouring tile edges disagree in height,
## including the map's outer edge against the soil block.
func _add_walls(factory, out: Dictionary) -> void:
	for y in range(-1, grid.height):
		for x in range(-1, grid.width):
			var cell := Vector2i(x, y)
			for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
				var other: Vector2i = cell + direction
				if not grid.inside(cell) and not grid.inside(other):
					continue
				var a := _edge(cell, direction)
				var b := _edge(other, -direction)
				if absf(a.x - b.x) < 0.001 and absf(a.y - b.y) < 0.001:
					continue
				var p0 := Vector2(x + 1, y) if direction == Vector2i.RIGHT else Vector2(x, y + 1)
				var p1 := Vector2(x + 1, y + 1)
				var top_colour := EDGE
				var foot_colour := EDGE
				var high := maxf(maxf(a.x, b.x), maxf(a.y, b.y))
				if not grid.inside(cell) or not grid.inside(other):
					if high > 0.5:
						top_colour = CLIFF_TOP
						foot_colour = CLIFF_FOOT
				elif grid.is_water(cell) and grid.is_water(other):
					top_colour = FOAM
					foot_colour = FOAM.darkened(0.12)
				elif grid.is_water(cell) or grid.is_water(other):
					top_colour = BANK
					foot_colour = BANK.darkened(0.2)
				elif not grid.passable(cell, other):
					top_colour = CLIFF_TOP
					foot_colour = CLIFF_FOOT
				else:
					# The small seam where a ramp meets level ground beside it.
					top_colour = factory.ground_colour(grid, (p0 + p1) * 0.5)
					foot_colour = top_colour.darkened(0.1)
				var outward := Vector3(direction.x, 0, direction.y)
				var normal := outward if a.x + a.y > b.x + b.y else -outward
				if grid.hex_width > 0.0 and (not grid.inside(cell) or not grid.inside(other)):
					# Smooth the grid's tiny stair-step faces into the six authored
					# sides of the hex silhouette, keeping the actual physical mask.
					var local := (p0 + p1) * 0.5 - Vector2(grid.width,grid.height) * 0.5
					var best := -INF
					for side in 6:
						var candidate := Vector2.from_angle(side * TAU / 6.0)
						if local.dot(candidate) > best:
							best = local.dot(candidate)
							normal = Vector3(candidate.x,0,candidate.y)
				var corners: Array[Vector3] = [
					Vector3(p0.x, maxf(a.x, b.x), p0.y), Vector3(p1.x, maxf(a.y, b.y), p1.y),
					Vector3(p1.x, minf(a.y, b.y), p1.y), Vector3(p0.x, minf(a.x, b.x), p0.y)]
				_quad(out, corners, normal, top_colour.srgb_to_linear(), foot_colour.srgb_to_linear())

## Heights at the two ends of a tile's edge, ordered top-left to bottom-right.
func _edge(cell: Vector2i, direction: Vector2i) -> Vector2:
	if not grid.inside(cell):
		var bottom := -1.1 if "footprint" in grid and 0 in grid.footprint else EDGE_BOTTOM
		return Vector2(bottom, bottom)
	var h := corner_heights(cell)
	if direction == Vector2i.RIGHT:
		return Vector2(h[1], h[2])
	if direction == Vector2i.LEFT:
		return Vector2(h[0], h[3])
	if direction == Vector2i.DOWN:
		return Vector2(h[3], h[2])
	return Vector2(h[0], h[1])

## Corners are top-start, top-end, foot-end, foot-start. Winding is chosen so
## the face points along `normal` (Godot's front faces are clockwise).
func _quad(out: Dictionary, corners: Array[Vector3], normal: Vector3, top_colour: Color, foot_colour: Color) -> void:
	for triangle in [[0, 1, 3], [1, 2, 3]]:
		var order: Array = triangle.duplicate()
		var a: Vector3 = corners[order[0]]
		if (corners[order[2]] - a).cross(corners[order[1]] - a).dot(normal) < 0.0:
			order = [order[0], order[2], order[1]]
		for corner in order:
			out.vertex.append(corners[corner])
			out.normal.append(normal)
			out.color.append(top_colour if corner < 2 else foot_colour)
			out.uv.append(Vector2(0.0, 1.0))

static func _bilinear(h: PackedFloat32Array, f: Vector2) -> float:
	return lerpf(lerpf(h[0], h[1], f.x), lerpf(h[3], h[2], f.x), f.y)
