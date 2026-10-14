extends RefCounted
## Authoritative large-feature layout shared by the world miniature and village
## generation. Points use normalized XZ coordinates: a hex is two units wide.
## No rendering resources, camera settings or presentation toggles affect it.
const HexMath = preload("res://sim/world/hex_math.gd")
const IntNoise = preload("res://sim/world/int_noise.gd")
const SCALE := 0.1
const RIVER_WIDTHS := [0.0, 0.06, 0.09, 0.13]
const LAKE_RADIUS := 0.60
const COAST_INSET := 0.90

static func centre(coord: Vector2i) -> Vector2:
	return HexMath.centre(coord) * SCALE

static func direction(edge: int) -> Vector2:
	return Vector2(cos(deg_to_rad(-60.0 * edge)), sin(deg_to_rad(-60.0 * edge)))

static func river_path(world, coord: Vector2i, edge: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var normal := direction(edge)
	var side := Vector2(-normal.y, normal.x)
	var bend := (IntNoise.unit(world.seed_value, coord.x, coord.y, 281 + edge) - 0.5) * 0.26
	for index in 9:
		var t := float(index) / 8.0
		result.append(centre(coord) + normal * t + side * sin(t * PI) * bend * (1.0 - smoothstep(0.4, 0.65, t)))
	return result

static func path_distance(point: Vector2, path: Array[Vector2]) -> float:
	var result := INF
	for index in range(1, path.size()):
		result = minf(result, point.distance_to(Geometry2D.get_closest_point_to_segment(point, path[index - 1], path[index])))
	return result

static func grove_at(world, coord: Vector2i, point: Vector2) -> float:
	var field := IntNoise.value(world.seed_value, 237, point * 0.48)
	# Broad meadow openings are part of the promised layout at both scales.
	# They remove no relief or water; a wet/rugged opening can still fail the
	# founding check. The site never clears a failed generated candidate.
	var anchor := Vector2(-0.10,0.16) + Vector2(IntNoise.unit(world.seed_value,coord.x,coord.y,283)-0.5,IntNoise.unit(world.seed_value,coord.x,coord.y,285)-0.5) * 0.16
	var offset := (point - centre(coord) - anchor) / Vector2(0.78,0.64)
	var meadow := 1.0 - smoothstep(0.78,1.12,offset.length())
	return field * (1.0 - meadow * 0.85)

static func relief_at(world, coord: Vector2i, point: Vector2, paths: Dictionary = {}) -> float:
	var info = world.hex(coord)
	if info == null or not info.is_land(): return 0.0
	var dry := smoothstep(0.20,0.38,water_distance(world,coord,point,paths))
	if info.biome in ["peaks", "mountain_pass"]:
		var warp := IntNoise.value(world.seed_value, 217, point * 0.18)
		var phase := point.dot(Vector2(0.72, 0.40)) + (warp - 0.5) * 2.0
		return 1.12 * (0.10 + pow(1.0 - absf(sin(phase)), 1.35) * 0.90) * dry
	if info.biome == "highland_hills":
		return 0.24 * IntNoise.value(world.seed_value, 219, point * 0.6) * dry
	return 0.055 * IntNoise.value(world.seed_value, 211, point * 0.8) * dry

static func water_distance(world, coord: Vector2i, point: Vector2, paths: Dictionary = {}) -> float:
	var info = world.hex(coord)
	if info == null or not info.is_land(): return 0.0
	var local := point - centre(coord)
	var result := 10.0
	if info.lake: result = maxf(0.0,local.length() - LAKE_RADIUS)
	for edge in info.river_edges:
		var key := Vector3i(coord.x,coord.y,int(edge))
		var path: Array[Vector2] = paths[key] if paths.has(key) else river_path(world,coord,int(edge))
		result = minf(result,path_distance(point,path))
	if info.lake:
		for edge in 6:
			var other = world.hex(world.neighbour(coord,edge))
			if other == null or not other.lake or other.elevation != info.elevation: continue
			var normal := direction(edge)
			result = minf(result,(local - normal * clampf(local.dot(normal),0.0,1.0)).length())
	return result

static func water_at(world, coord: Vector2i, point: Vector2, paths: Dictionary = {}) -> String:
	var info = world.hex(coord)
	if info == null or not info.is_land(): return "ocean"
	var local := point - centre(coord)
	for edge in info.coast_edges:
		if local.dot(direction(edge)) >= COAST_INSET: return "ocean"
	if info.lake and local.length() <= LAKE_RADIUS: return "lake"
	# Same-level adjacent lakes are one water body in both views.
	if info.lake:
		for edge in 6:
			var other = world.hex(world.neighbour(coord, edge))
			if other == null or not other.lake or other.elevation != info.elevation: continue
			var normal := direction(edge)
			if (local - normal * clampf(local.dot(normal), 0.0, 1.0)).length() <= LAKE_RADIUS * 0.66:
				return "lake"
	var widest := 0
	for edge in info.river_edges:
		var key := Vector3i(coord.x, coord.y, int(edge))
		var path: Array[Vector2] = paths[key] if paths.has(key) else river_path(world, coord, int(edge))
		var width := int(info.river_edges[edge])
		if path_distance(point, path) <= RIVER_WIDTHS[width]: widest = maxi(widest, width)
	return "stream" if widest == 1 else ("river" if widest > 1 else "")

