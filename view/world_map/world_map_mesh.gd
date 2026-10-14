extends RefCounted
## Hex dioramas with sculpted relief, fine borders, layered earth, imported
## nature assets, riverbanks and coastal shelves. Compatible neighbors share
## relief and groves in linked mode. Presentation only.
const HexMath = preload("res://sim/world/hex_math.gd")
const Scenery = preload("res://view/world_map/world_map_scenery.gd")
## World units per tile unit: a 20-tile hex is 2 units across on the map.
const SCALE := 2.0 / HexMath.WIDTH
## Top of each elevation band's prism.
const BAND_TOPS: Array[float] = [0.10, 0.22, 0.36, 0.52, 0.72]
const WATER_LEVEL := 0.03
const WALL_FOOT := -0.06
const RIVER_WIDTHS: Array[float] = [0.0, 0.12, 0.18, 0.26]
var world
var material: Material
var water_colour: Color
## Axial coordinate -> prism top height, for every land hex.
var tops: Dictionary = {}
var art: Resource
var scenery
var village_art: Resource
var water_material: ShaderMaterial
var motion_settings := Vector3(-1, -1, -1)

func _init(world_map, surface_material: Material, water: Color, settings: Resource = null, village_settings: Resource = null) -> void:
	world = world_map
	material = surface_material
	water_colour = water
	art = settings if settings != null else preload("res://view/world_map/world_map_art.tres")
	village_art = village_settings if village_settings != null else preload("res://view/village_art.tres")

func surface_height(coord: Vector2i, point: Vector3) -> float:
	return scenery.height(coord, point) if scenery != null else top_of(coord)

static func centre(coord: Vector2i) -> Vector3:
	var flat := HexMath.centre(coord) * SCALE
	return Vector3(flat.x, 0.0, flat.y)

## World-space point of a hex corner at `angle` degrees (pointy-top: corners at
## 30 + 60k; edge e of HexMath.NEIGHBOURS faces -60e degrees).
static func corner(coord: Vector2i, angle: float, scale: float = 1.0) -> Vector3:
	var radius := HexMath.RADIUS * SCALE * scale
	return centre(coord) + Vector3(cos(deg_to_rad(angle)), 0.0, sin(deg_to_rad(angle))) * radius

static func edge_direction(edge: int) -> float:
	return -60.0 * edge

func top_of(coord: Vector2i) -> float:
	return tops.get(coord, WATER_LEVEL)

## Bounds of all hex centres on the map plane, as Rect2(x, z).
func bounds() -> Rect2:
	var rect := Rect2()
	var first := true
	for coord in world.hexes:
		var at := centre(coord)
		if first:
			rect = Rect2(at.x, at.z, 0, 0)
			first = false
		else:
			rect = rect.expand(Vector2(at.x, at.z))
	return rect

func build() -> Node3D:
	tops.clear()
	for coord in world.hexes:
		if world.hexes[coord].is_land():
			tops[coord] = BAND_TOPS[world.hexes[coord].elevation]
	scenery = Scenery.new(self, art)
	var root := Node3D.new()
	root.name = "WorldMapModel"
	root.add_child(_instance("Land", _land()))
	var water_node := _instance("Water", _water())
	water_material = ShaderMaterial.new()
	water_material.shader = preload("res://render/world_map_water.gdshader")
	village_art.apply_material(water_material)
	water_material.set_shader_parameter("map_water_glints", art.water_glints)
	water_node.material_override = water_material
	root.add_child(water_node)
	root.add_child(_instance("Features", _features()))
	root.add_child(scenery.build())
	return root

func _instance(node_name: String, mesh: ArrayMesh) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	return instance

func _land() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for coord in tops:
		var top: float = tops[coord]
		var middle := centre(coord)
		middle.y = surface_height(coord, middle)
		# Finer, even samples support broad ridges without concentric rock steps.
		var previous: Array[Vector3] = []
		for ring in [0.16, 0.32, 0.48, 0.64, 0.80, 1.0 - art.border_width, 1.0]:
			var points: Array[Vector3] = []
			for segment in 24:
				var edge := segment / 4
				var along := float(segment % 4) / 4.0
				var p := corner(coord, edge_direction(edge) + 30.0).lerp(corner(coord, edge_direction(edge) - 30.0), along)
				p = centre(coord).lerp(p, ring)
				p.y = surface_height(coord, p)
				points.append(p)
			for segment in 24:
				var next := (segment + 1) % 24
				if previous.is_empty():
					_ground_tri(st, coord, [middle, points[segment], points[next]], false)
				else:
					_ground_tri(st, coord, [previous[segment], points[segment], points[next]], ring == 1.0)
					_ground_tri(st, coord, [previous[segment], points[next], previous[next]], ring == 1.0)
			previous = points
		for edge in 6:
			var a0 := edge_direction(edge) - 30.0
			var a1 := edge_direction(edge) + 30.0
			var outer0 := corner(coord, a0) + Vector3.UP * top
			var outer1 := corner(coord, a1) + Vector3.UP * top
			var neighbour_top := top_of(world.neighbour(coord, edge)) if world.has(world.neighbour(coord, edge)) else WALL_FOOT
			if not world.has(world.neighbour(coord, edge)) or not world.hex(world.neighbour(coord, edge)).is_land():
				neighbour_top = WALL_FOOT
			if neighbour_top < top - 0.001:
				var normal := Vector3(cos(deg_to_rad(edge_direction(edge))), 0.0, sin(deg_to_rad(edge_direction(edge))))
				# A narrow sunlit lip over warmer, layered earth replaces the thick rim.
				var lip := minf(0.035, (top - neighbour_top) * 0.3)
				_quad(st, [outer0, outer1, outer1 - Vector3.UP * lip, outer0 - Vector3.UP * lip], normal, art.earth_colour.lightened(0.20), art.earth_colour)
				var strata := 3
				for layer in strata:
					var high := lerpf(top - lip, neighbour_top, float(layer) / strata)
					var low := lerpf(top - lip, neighbour_top, float(layer + 1) / strata)
					var wall: Color = art.earth_colour.darkened(0.15 + layer * 0.12)
					_quad(st, [Vector3(outer0.x, high, outer0.z), Vector3(outer1.x, high, outer1.z), Vector3(outer1.x, low, outer1.z), Vector3(outer0.x, low, outer0.z)], normal, wall, wall.darkened(0.08))
	return st.commit()

func _ground_tri(st: SurfaceTool, coord: Vector2i, points: Array, border: bool) -> void:
	var normal: Vector3 = (points[2] - points[0]).cross(points[1] - points[0]).normalized()
	if normal.y < 0.0: normal = -normal
	var colours: Array = []
	for point in points:
		var colour: Color = scenery.ground_colour(coord, point)
		colours.append(colour.darkened(0.21) if border else colour)
	_tri(st, points, normal, colours)

## The ocean plane, plus rivers, waterfalls and lakes on the land.
func _water() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var area := bounds().grow(40.0)
	var y := WATER_LEVEL
	_quad(st, [Vector3(area.position.x, y, area.position.y), Vector3(area.end.x, y, area.position.y), Vector3(area.end.x, y, area.end.y), Vector3(area.position.x, y, area.end.y)], Vector3.UP, water_colour.darkened(0.08), water_colour.darkened(0.08))
	# Local coastal shelves fade into deep water; avoid a full pale hex ring.
	for coord in tops:
		for edge in world.hex(coord).coast_edges:
			var a0 := edge_direction(edge) - 30.0
			var a1 := edge_direction(edge) + 30.0
			var first := corner(coord, a0)
			var second := corner(coord, a1)
			var direction := Vector3(cos(deg_to_rad(edge_direction(edge))), 0, sin(deg_to_rad(edge_direction(edge))))
			var outer0 := first + direction * 0.42
			var outer1 := second + direction * 0.42
			first.y = y + 0.002
			second.y = y + 0.002
			outer0.y = y + 0.002
			outer1.y = y + 0.002
			_quad(st, [first, second, outer1, outer0], Vector3.UP, water_colour.lightened(0.09), water_colour.darkened(0.08))
	var river: Color = art.river_colour
	for coord in tops:
		var info = world.hexes[coord]
		var top: float = tops[coord] + 0.012
		var middle := centre(coord) + Vector3.UP * top
		if info.lake:
			for edge in 6:
				var a0 := edge_direction(edge) - 30.0
				_tri(st, [middle + Vector3.UP * 0.002, corner(coord, a0, 0.52) + Vector3.UP * (top + 0.002), corner(coord, a0 + 60.0, 0.52) + Vector3.UP * (top + 0.002)], Vector3.UP, [river, river, river])
			if art.linked_tiles:
				for edge in 6:
					var other = world.hex(world.neighbour(coord, edge))
					if other == null or not other.lake or other.elevation != info.elevation: continue
					var direction := Vector3(cos(deg_to_rad(edge_direction(edge))), 0, sin(deg_to_rad(edge_direction(edge))))
					var side := Vector3(-direction.z, 0, direction.x) * 0.24
					var mouth := middle + direction
					_quad(st, [middle - side, middle + side, mouth + side, mouth - side], Vector3.UP, river, river)
		if info.river_edges.is_empty():
			continue
		var widest: float = RIVER_WIDTHS[info.river_width()]
		# A small hexagon joins the river's arms at the centre.
		for edge in 6:
			var a0 := edge_direction(edge) - 30.0
			_tri(st, [middle, middle + Vector3(cos(deg_to_rad(a0)), 0, sin(deg_to_rad(a0))) * widest * 0.6, middle + Vector3(cos(deg_to_rad(a0 + 60.0)), 0, sin(deg_to_rad(a0 + 60.0))) * widest * 0.6], Vector3.UP, [river, river, river])
		for edge in info.river_edges:
			var width: float = RIVER_WIDTHS[int(info.river_edges[edge])]
			var direction := Vector3(cos(deg_to_rad(edge_direction(edge))), 0.0, sin(deg_to_rad(edge_direction(edge))))
			var side := Vector3(-direction.z, 0.0, direction.x) * width * 0.5
			var mouth := middle + direction * HexMath.WIDTH * 0.5 * SCALE
			var path: Array[Vector3] = scenery.river_path(coord, edge)
			for index in range(1, path.size()):
				var first: Vector3 = path[index - 1] + Vector3.UP * top
				var second: Vector3 = path[index] + Vector3.UP * top
				var bank := side.normalized() * (width * 0.5 + 0.025)
				_quad(st, [first - bank - Vector3.UP * 0.004, first + bank - Vector3.UP * 0.004, second + bank - Vector3.UP * 0.004, second - bank - Vector3.UP * 0.004], Vector3.UP, art.shore_colour.darkened(0.18), art.shore_colour.darkened(0.18))
				_quad(st, [first - side, first + side, second + side, second - side], Vector3.UP, river, river.lightened(0.04))
			# Where the water leaves for lower ground or the sea, it falls.
			var other: Vector2i = world.neighbour(coord, edge)
			var below := top_of(other) + 0.012 if tops.has(other) else WATER_LEVEL
			if below < top - 0.01:
				var drop := Vector3.UP * (below - top)
				_quad(st, [mouth + side, mouth - side, mouth - side + drop, mouth + side + drop], direction, Color("d9e6e2"), river)
	return st.commit()

## Coastal shelves and the start banner; foliage is instanced separately.
func _features() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for coord in tops:
		var info = world.hex(coord)
		for edge in info.coast_edges:
			var a0 := edge_direction(edge) - 30.0
			var a1 := edge_direction(edge) + 30.0
			for segment in 4:
				var first := corner(coord, a0).lerp(corner(coord, a1), float(segment) / 4.0)
				var second := corner(coord, a0).lerp(corner(coord, a1), float(segment + 1) / 4.0)
				var inner0 := centre(coord).lerp(first, 1.0 - art.shore_width)
				var inner1 := centre(coord).lerp(second, 1.0 - art.shore_width)
				first.y = surface_height(coord, first) + 0.004
				second.y = surface_height(coord, second) + 0.004
				inner0.y = surface_height(coord, inner0) + 0.004
				inner1.y = surface_height(coord, inner1) + 0.004
				_quad(st, [inner0, inner1, second, first], Vector3.UP, art.shore_colour.darkened(0.04), art.shore_colour.lightened(0.10))
				var outer0 := centre(coord).lerp(first, 1.035)
				var outer1 := centre(coord).lerp(second, 1.035)
				first.y = WATER_LEVEL + 0.005
				second.y = WATER_LEVEL + 0.005
				outer0.y = WATER_LEVEL + 0.005
				outer1.y = WATER_LEVEL + 0.005
				_quad(st, [first, second, outer1, outer0], Vector3.UP, water_colour.lightened(0.18), water_colour.lightened(0.06))
	if world.hex(world.start).settlement.is_empty():
		var start := centre(world.start)
		start.y = surface_height(world.start, start)
		_box(st, start + Vector3(0.0, 0.45, 0.0), Vector3(0.04, 0.9, 0.04), Color("4a3a2c"))
		_box(st, start + Vector3(0.18, 0.78, 0.0), Vector3(0.34, 0.2, 0.02), Color("c8553d"))
	return st.commit()

## Per-material controls keep motion small at overview scale. Mesh placement
## and terrain picking stay static; the shader bends plants above their roots.
func set_motion_scale(zoom_size: float) -> void:
	var settings := Vector3(zoom_size, art.wind_scale, art.water_glints)
	if settings == motion_settings: return
	motion_settings = settings
	var closeness := 1.0 - smoothstep(8.0, 36.0, zoom_size)
	var strength: float = art.wind_scale * lerpf(0.32, 1.0, closeness)
	for asset in scenery.meshes:
		var mesh: ArrayMesh = scenery.meshes[asset]
		for surface in mesh.get_surface_count():
			mesh.surface_get_material(surface).set_shader_parameter("map_wind_scale", strength)
	water_material.set_shader_parameter("map_water_glints", art.water_glints * lerpf(0.3, 1.0, closeness))

func _box(st: SurfaceTool, at: Vector3, size: Vector3, colour: Color) -> void:
	var h := size * 0.5
	for axis in 3:
		for sign_value in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			normal[axis] = sign_value
			var u := Vector3.ZERO
			var v := Vector3.ZERO
			u[(axis + 1) % 3] = h[(axis + 1) % 3]
			v[(axis + 2) % 3] = h[(axis + 2) % 3]
			var face := at + normal * h[axis]
			_quad(st, [face - u - v, face + u - v, face + u + v, face - u + v], normal, colour, colour)

## Quad corners are top-start, top-end, foot-end, foot-start (any consistent
## loop works); winding is chosen so the face points along `normal`.
func _quad(st: SurfaceTool, corners: Array, normal: Vector3, first: Color, second: Color) -> void:
	_tri(st, [corners[0], corners[1], corners[3]], normal, [first, first, second])
	_tri(st, [corners[1], corners[2], corners[3]], normal, [first, second, second])

## Godot's front faces are clockwise; flip the triangle if it faces away from `normal`.
func _tri(st: SurfaceTool, points: Array, normal: Vector3, colours: Array) -> void:
	var order := [0, 1, 2]
	if (points[2] - points[0]).cross(points[1] - points[0]).dot(normal) < 0.0:
		order = [0, 2, 1]
	for index in order:
		st.set_normal(normal)
		st.set_color(colours[index].srgb_to_linear())
		st.add_vertex(points[index])
