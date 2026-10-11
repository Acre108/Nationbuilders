extends RefCounted
## Seeded relief and batched imported nature assets for miniature landscapes.
const HexMath = preload("res://sim/world/hex_math.gd")
const IntNoise = preload("res://sim/world/int_noise.gd")
const NatureBuilder = preload("res://foliage/util/nature_mesh_builder.gd")
const Profile = preload("res://foliage/resources/foliage_profile.gd")
const TerrainLayout = preload("res://sim/world/terrain_layout.gd")
var model_ref: WeakRef
var model:
	get: return model_ref.get_ref()
var art: Resource
var profile: Resource
static var meshes: Dictionary = {}
var batches: Dictionary = {}
var links: Dictionary = {}
var corner_support: Dictionary = {}
var instance_count := 0
var river_paths: Dictionary = {}
const GROUND_PALETTE := {"peaks": "7e8984", "mountain_pass": "8b9478", "tundra": "9baa9d", "marsh": "537968", "highland_hills": "7b9157", "coast": "99a36c", "riverland": "709452", "heartland": "94aa60"}

func _init(map_model, settings: Resource) -> void:
	model_ref = weakref(map_model)
	art = settings
	profile = Profile.new()
	profile.haze_amount = 0.0
	profile.distance_tint_strength = 0.0
	profile.tree_translucency = 0.025
	profile.tree_flutter = 0.0
	for coord in model.world.hexes:
		var mask := 0
		for edge in 6:
			if compatible(coord, model.world.neighbour(coord, edge)):
				mask |= 1 << edge
		links[coord] = mask

func kind(coord: Vector2i) -> String:
	var info = model.world.hex(coord)
	if info == null or not info.is_land(): return "water"
	if info.biome in ["peaks", "mountain_pass"]: return "rock"
	if info.biome == "highland_hills": return "hill"
	return "low"

func compatible(a: Vector2i, b: Vector2i) -> bool:
	if not model.world.has(a) or not model.world.has(b): return false
	var first = model.world.hex(a)
	var second = model.world.hex(b)
	return first.is_land() and second.is_land() and first.elevation == second.elevation and kind(a) == kind(b)

func _corner_shared(coord: Vector2i, side: int) -> bool:
	var key := Vector3i(coord.x, coord.y, side)
	if corner_support.has(key): return corner_support[key]
	# Corner between side and side+1. All three tiles must share the relief.
	var result: bool = compatible(coord, model.world.neighbour(coord, side)) and compatible(coord, model.world.neighbour(coord, (side + 1) % 6))
	corner_support[key] = result
	return result

## Both sides of a linked edge evaluate the same world-space field and the
## same corner support. Unlinked edges fade to the original prism surface.
func height(coord: Vector2i, point: Vector3) -> float:
	if not model.tops.has(coord): return model.WATER_LEVEL
	point.y = 0.0
	var offset: Vector3 = point - model.centre(coord)
	var angle := fposmod(rad_to_deg(atan2(-offset.z, offset.x)) + 30.0, 360.0)
	var edge := int(angle / 60.0) % 6
	var normal := Vector3(cos(deg_to_rad(-edge * 60.0)), 0, sin(deg_to_rad(-edge * 60.0)))
	var radial := clampf(offset.dot(normal), 0.0, 1.0)
	var side := Vector3(-normal.z, 0, normal.x)
	var along := clampf(offset.dot(side) / maxf(radial, 0.001) / (2.0 / sqrt(3.0)) + 0.5, 0.0, 1.0)
	var support := 0.0
	if art.linked_tiles and (int(links[coord]) & (1 << edge)) != 0:
		var left := 1.0 if _corner_shared(coord, edge) else 0.0
		var right := 1.0 if _corner_shared(coord, (edge + 5) % 6) else 0.0
		support = lerpf(left, right, along) + (1.0 - lerpf(left, right, along)) * sin(along * PI)
	var taper := lerpf(1.0, support, smoothstep(0.55, 1.0, radial))
	var sample_point := Vector2(point.x, point.z)
	if not art.linked_tiles:
		sample_point += Vector2(coord.x * 13.7, coord.y * 19.3)
	var rise := TerrainLayout.relief_at(model.world, coord, sample_point)
	# Keep lakes and river arms level, including their banks.
	var clearance := water_distance(coord, point)
	var dry := smoothstep(0.20, 0.38, clearance)
	return model.top_of(coord) + rise * taper * dry * art.relief_strength

func water_distance(coord: Vector2i, point: Vector3) -> float:
	point.y = 0.0
	var info = model.world.hex(coord)
	var offset: Vector3 = point - model.centre(coord)
	var result := 10.0
	if info.lake: result = maxf(0.0, offset.length() - 0.60)
	for edge in info.river_edges:
		var path := river_path(coord, edge)
		for index in range(1, path.size()):
			var delta: Vector3 = path[index] - path[index - 1]
			var projected := clampf((point - path[index - 1]).dot(delta) / delta.length_squared(), 0.0, 1.0)
			result = minf(result, (point - path[index - 1] - delta * projected).length())
	if art.linked_tiles and info.lake:
		for edge in 6:
			var other = model.world.hex(model.world.neighbour(coord, edge))
			if other == null or not other.lake or other.elevation != info.elevation: continue
			var direction := Vector3(cos(deg_to_rad(model.edge_direction(edge))), 0, sin(deg_to_rad(model.edge_direction(edge))))
			result = minf(result, (offset - direction * clampf(offset.dot(direction), 0.0, 1.0)).length())
	return result

func river_path(coord: Vector2i, edge: int) -> Array[Vector3]:
	var key := Vector3i(coord.x, coord.y, edge)
	if river_paths.has(key): return river_paths[key]
	var result: Array[Vector3] = []
	for point in TerrainLayout.river_path(model.world, coord, edge):
		result.append(Vector3(point.x, 0, point.y))
	river_paths[key] = result
	return result

func ground_colour(coord: Vector2i, point: Vector3) -> Color:
	var info = model.world.hex(coord)
	var p := Vector2(point.x, point.z)
	if not art.linked_tiles: p += Vector2(coord.x * 11.0, coord.y * 17.0)
	var broad := IntNoise.value(model.world.seed_value, 231, p * 0.38)
	var colour: Color = model.village_art.grass_shade.lerp(model.village_art.grass_sun, smoothstep(0.18, 0.82, broad) * 0.78)
	colour = colour.lerp(Color(GROUND_PALETTE.get(info.biome, "94aa60")), 0.24)
	if kind(coord) != "rock":
		var grove: float = smoothstep(0.38, 0.65, grove_at(coord, point)) * info.forest
		colour = colour.lerp(model.village_art.forest_floor.lightened(0.10), grove * 0.62)
	else:
		var rise: float = height(coord, point) - model.top_of(coord)
		colour = colour.lerp(Color("7e8984"), smoothstep(0.10, 0.45, rise) * 0.85)
		colour = colour.lerp(Color("dddcd0"), smoothstep(0.84, 1.07, rise))
	if info.biome == "marsh": colour = colour.lerp(Color("38675e"), (1.0 - broad) * 0.4)
	return colour

func grove_at(coord: Vector2i, point: Vector3) -> float:
	var p := Vector2(point.x, point.z)
	if not art.linked_tiles: p += Vector2(coord.x * 11.0, coord.y * 17.0)
	return TerrainLayout.grove_at(model.world, coord, p)

func detail_at(coord: Vector2i, point: Vector3) -> bool:
	var p := Vector2(point.x, point.z)
	if not art.linked_tiles: p += Vector2(coord.x * 11.0, coord.y * 17.0)
	return IntNoise.value(model.world.seed_value, 243, p * 1.6) > 1.0 - art.meadow_detail_cover

func build() -> Node3D:
	batches.clear()
	instance_count = 0
	for coord in model.tops:
		var info = model.world.hex(coord)
		var centre: Vector3 = model.centre(coord)
		# The same staggered lattice continues across linked hexes. Each root
		# belongs to exactly one hex, so links never duplicate plants.
		for row in range(floori((centre.z - 1.2) / 0.28), ceili((centre.z + 1.2) / 0.28)):
			for column in range(floori((centre.x - 1.2) / 0.28), ceili((centre.x + 1.2) / 0.28)):
				var jitter := Vector2(IntNoise.unit(model.world.seed_value, column, row, 251), IntNoise.unit(model.world.seed_value, column, row, 253))
				var point := Vector3((column + jitter.x * 0.7) * 0.28, 0, (row + jitter.y * 0.7) * 0.28)
				if HexMath.from_point(Vector2(point.x, point.z) / model.SCALE) != coord: continue
				var local: Vector3 = point - centre
				var edge_distance := 1.0
				for edge in 6:
					var normal := Vector3(cos(deg_to_rad(model.edge_direction(edge))), 0, sin(deg_to_rad(model.edge_direction(edge))))
					if not art.linked_tiles or (int(links[coord]) & (1 << edge)) == 0:
						edge_distance = minf(edge_distance, 1.0 - local.dot(normal))
				if edge_distance < 0.12: continue
				var water := water_distance(coord, point)
				if water < 0.22: continue
				var random := IntNoise.unit(model.world.seed_value, column, row, 257)
				var grove := grove_at(coord, point)
				var detailed := detail_at(coord, point)
				var asset := ""
				var size := 1.0
				if info.biome == "peaks":
					if random < 0.025: asset = "rock_2"; size = 0.10
				elif random < info.forest * art.foliage_density * lerpf(0.025, 1.15, smoothstep(0.34, 0.65, grove)):
					if info.biome in ["tundra", "mountain_pass", "highland_hills"] or info.temperature < 0.35:
						asset = "spruce" if random < 0.18 else "pine"
					elif info.biome == "marsh": asset = "birch_2"
					else: asset = "oak" if random < 0.30 else "birch_2"
					size = 0.46 + IntNoise.unit(model.world.seed_value, column, row, 263) * 0.24
				elif info.biome == "marsh" and detailed and random < 0.48:
					asset = "lake_reeds"; size = 0.16
				elif water < 0.40 and random < 0.38:
					asset = "lake_rushes"; size = 0.12
				elif kind(coord) == "rock" and random < 0.06:
					asset = "rock_1"; size = 0.10
				elif detailed and random > 0.55 and info.biome not in ["mountain_pass", "tundra"]:
					asset = "grass_short" if random < 0.95 else "wildflower_purple"; size = 0.07
				elif detailed and random > 0.96:
					asset = "lake_pebble_1"; size = 0.07
				if asset.is_empty(): continue
				point.y = height(coord, point) + 0.008
				_place(asset, point, size, IntNoise.unit(model.world.seed_value, column, row, 269) * TAU)
	var root := Node3D.new()
	root.name = "Nature"
	for asset in batches:
		if not meshes.has(asset):
			meshes[asset] = NatureBuilder.build(asset, 1.0, profile, false, true, false, NatureBuilder.root_sink(asset) if asset in ["oak", "spruce", "pine", "birch_2"] else 0.0)
			for surface in meshes[asset].get_surface_count():
				var mat: ShaderMaterial = meshes[asset].surface_get_material(surface)
					# Keep source textures; apply the village palette at miniature scale.
				mat.shader = preload("res://render/world_map_nature.gdshader")
		for surface in meshes[asset].get_surface_count():
			var mat: ShaderMaterial = meshes[asset].surface_get_material(surface)
			model.village_art.apply_material(mat)
			var tree: bool = asset in ["oak", "spruce", "pine", "birch_2"]
			mat.set_shader_parameter("map_plant_kind", 1 if tree else (0 if "rock" in asset or "pebble" in asset else 2))
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_custom_data = true
		multi.mesh = meshes[asset]
		multi.instance_count = batches[asset].size()
		for index in multi.instance_count:
			multi.set_instance_transform(index, batches[asset][index])
			multi.set_instance_custom_data(index, Color(0.5, 0.5, 0.5, 1.0))
		var node := MultiMeshInstance3D.new()
		node.name = asset
		node.multimesh = multi
		node.extra_cull_margin = 0.05
		root.add_child(node)
	return root

func _place(asset: String, point: Vector3, size: float, angle: float) -> void:
	if not batches.has(asset): batches[asset] = []
	batches[asset].append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * size), point))
	instance_count += 1
