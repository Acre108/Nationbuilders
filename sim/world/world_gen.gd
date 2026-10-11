extends RefCounted
## Seeded world generation at hex resolution (docs/PLAN-world-map.md §4.2).
## Pure and deterministic: every random choice comes from IntNoise or a
## per-hex SeededRNG keyed by the hex, so nothing depends on iteration order
## beyond the fixed row-major order used throughout.
const WorldMap = preload("res://sim/world/world_map.gd")
const HexInfo = preload("res://sim/world/hex_info.gd")
const HexMath = preload("res://sim/world/hex_math.gd")
const IntNoise = preload("res://sim/world/int_noise.gd")
const WorldData = preload("res://sim/world/world_data.gd")
const SeededRNG = preload("res://sim/rng.gd")
## Smallest rise of the drainage surface per hex, so flats still drain one way.
const DRAIN_EPSILON := 0.0001
## Noise channels; one per field so fields never correlate.
enum Channel { WARP = 10, CONTINENT = 20, DETAIL = 30, RIDGE = 40, TEMPERATURE = 50, MOISTURE = 60, FOREST = 70, CLIFFS = 80, WILDNESS = 90, DEPOSITS = 100 }

## `data` is a loaded WorldData; when null the shipped data is loaded.
static func generate(seed_value: int, data = null):
	if data == null:
		data = WorldData.new()
		if not data.load_directory():
			return null
	var settings: Dictionary = data.world
	var world = WorldMap.new()
	world.seed_value = seed_value
	world.generator_version = int(settings.generator_version)
	world.columns = int(settings.columns)
	world.rows = int(settings.rows)
	world.data = data
	for row in world.rows:
		for column in world.columns:
			var info = HexInfo.new()
			info.coord = WorldMap.coord_at(column, row)
			world.hexes[info.coord] = info
	_heights(world, seed_value, settings)
	var sea_level := _sea(world, float(settings.sea_fraction))
	_bands(world, settings.band_fractions)
	_drainage(world, sea_level)
	_rivers(world, settings)
	_coasts(world)
	_climate(world, seed_value)
	_biomes(world, seed_value, settings)
	_start(world, seed_value, int(settings.scout_radius))
	_deposits(world, seed_value)
	return world

## Position of a hex in hex-width units, for sampling noise.
static func _point(coord: Vector2i) -> Vector2:
	return HexMath.centre(coord) / HexMath.WIDTH

## A continent mask (fading to sea at the edges, its outline pushed around by
## noise) times broad and fine fractal noise, plus ridges for mountain chains.
static func _heights(world, seed_value: int, settings: Dictionary) -> void:
	var continent := float(settings.continent_scale)
	var detail := float(settings.detail_scale)
	var ridges := float(settings.ridge_strength)
	for coord in world.hexes:
		var info = world.hexes[coord]
		var column: int = WorldMap.column_of(coord)
		var row: int = coord.y
		if column == 0 or row == 0 or column == world.columns - 1 or row == world.rows - 1:
			info.height = -1.0
			continue
		var p := _point(coord)
		var u: float = (float(column) + 0.5 * (row & 1)) / (world.columns - 0.5) * 2.0 - 1.0
		var v: float = float(row) / (world.rows - 1) * 2.0 - 1.0
		var edge := sqrt(u * u * 0.8 + v * v) + (IntNoise.fbm(seed_value, Channel.WARP, p * 0.28, 3) - 0.5) * 1.1
		var mask := 1.0 - smoothstep(0.3, 1.0, edge)
		var land := 0.65 * IntNoise.fbm(seed_value, Channel.CONTINENT, p * continent, 4) + 0.35 * IntNoise.fbm(seed_value, Channel.DETAIL, p * detail, 3)
		# Low ground noise can cut below the sea near coasts, carving bays and inlets.
		info.height = 0.55 * mask + 0.6 * (land - 0.5) + ridges * IntNoise.ridge(seed_value, Channel.RIDGE, p * 0.2, 3) * mask

## Sea level is the height below which `fraction` of the map lies, measured, not
## assumed. Only low hexes connected to the map's edge become ocean, so there
## are no one-hex inland seas; low inland hexes stay land and may hold lakes.
static func _sea(world, fraction: float) -> float:
	var heights: Array[float] = []
	for coord in world.hexes:
		heights.append(world.hexes[coord].height)
	heights.sort()
	var sea_level: float = heights[clampi(int(fraction * heights.size()), 0, heights.size() - 1)]
	var frontier: Array[Vector2i] = []
	for coord in world.hexes:
		if world.hexes[coord].height < 0.0:
			world.hexes[coord].biome = "ocean"
			frontier.append(coord)
	while not frontier.is_empty():
		var coord: Vector2i = frontier.pop_back()
		for other in world.neighbours(coord):
			var info = world.hexes[other]
			if info.biome != "ocean" and info.height < sea_level:
				info.biome = "ocean"
				frontier.append(other)
	return sea_level

## Elevation bands from land-height quantiles, so each band's share is exact.
static func _bands(world, cuts: Array) -> void:
	var land: Array[float] = []
	for coord in world.hexes:
		if world.hexes[coord].is_land():
			land.append(world.hexes[coord].height)
	land.sort()
	var thresholds: Array[float] = []
	for cut in cuts:
		thresholds.append(land[clampi(int(float(cut) * land.size()), 0, land.size() - 1)])
	for coord in world.hexes:
		var info = world.hexes[coord]
		if not info.is_land():
			continue
		info.elevation = 0
		for threshold in thresholds:
			if info.height >= threshold:
				info.elevation += 1

## Priority flood from the sea (Barnes et al. 2014, on the hex graph): every
## land hex learns the lowest level water must reach to escape, and the hex it
## escapes through. That gives each hex one downhill direction to the sea,
## including through basins, which become lakes once a river fills them.
static func _drainage(world, sea_level: float) -> void:
	var order: Array = world.hexes.keys()
	var index_of := {}
	for index in order.size():
		index_of[order[index]] = index
	var queue: Array = []
	var done := {}
	for coord in order:
		var info = world.hexes[coord]
		if not info.is_land():
			info.filled = sea_level
			done[coord] = true
			queue.append([info.filled, index_of[coord]])
	queue.sort_custom(_before)
	while not queue.is_empty():
		var current: Vector2i = order[queue.pop_front()[1]]
		var level: float = world.hexes[current].filled
		for edge in 6:
			var other: Vector2i = world.neighbour(current, edge)
			if not world.has(other) or done.has(other):
				continue
			done[other] = true
			var info = world.hexes[other]
			info.filled = maxf(info.height, level + DRAIN_EPSILON)
			info.flows_to = WorldMap.opposite(edge)
			_insert(queue, [info.filled, index_of[other]])

static func _before(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])

static func _insert(queue: Array, entry: Array) -> void:
	var low := 0
	var high := queue.size()
	while low < high:
		var middle := (low + high) / 2
		if _before(queue[middle], entry):
			low = middle + 1
		else:
			high = middle
	queue.insert(low, entry)

## Flow accumulates downhill; enough of it makes a stream, river or great river
## on the edge it leaves by, marked on both hexes. A river crossing a basin
## (filled well above the ground) makes a lake there.
static func _rivers(world, settings: Dictionary) -> void:
	var land: Array = []
	for coord in world.hexes:
		var info = world.hexes[coord]
		if info.is_land():
			info.flow = 1
			land.append(coord)
	land.sort_custom(func(a, b): return world.hexes[a].filled > world.hexes[b].filled)
	for coord in land:
		var info = world.hexes[coord]
		var down = world.hex(world.neighbour(coord, info.flows_to))
		if down.is_land():
			down.flow += info.flow
	for coord in land:
		var info = world.hexes[coord]
		if info.flow < int(settings.stream_flow):
			continue
		var width := 1
		if info.flow >= int(settings.great_river_flow):
			width = 3
		elif info.flow >= int(settings.river_flow):
			width = 2
		info.river_edges[info.flows_to] = width
		world.hex(world.neighbour(coord, info.flows_to)).river_edges[WorldMap.opposite(info.flows_to)] = width
		if info.filled - info.height > float(settings.lake_depth):
			info.lake = true

static func _coasts(world) -> void:
	for coord in world.hexes:
		var info = world.hexes[coord]
		if not info.is_land():
			continue
		for edge in 6:
			var other = world.hex(world.neighbour(coord, edge))
			if other != null and not other.is_land():
				info.coast_edges.append(edge)

## Colder to the north and with height; wetter near water and in noise, drier
## east of high ground (the prevailing wind comes from the west).
static func _climate(world, seed_value: int) -> void:
	var distance := {}
	var frontier: Array[Vector2i] = []
	for coord in world.hexes:
		var info = world.hexes[coord]
		if not info.is_land() or not info.river_edges.is_empty() or info.lake:
			distance[coord] = 0
			frontier.append(coord)
	var cursor := 0
	while cursor < frontier.size():
		var coord: Vector2i = frontier[cursor]
		cursor += 1
		for other in world.neighbours(coord):
			if not distance.has(other):
				distance[other] = int(distance[coord]) + 1
				frontier.append(other)
	for coord in world.hexes:
		var info = world.hexes[coord]
		var p := _point(coord)
		info.temperature = clampf(0.12 + 0.84 * float(coord.y) / (world.rows - 1) - 0.06 * info.elevation + (IntNoise.unit(seed_value, coord.x, coord.y, Channel.TEMPERATURE) - 0.5) * 0.12, 0.0, 1.0)
		var shadow := 0.0
		for step in range(1, 4):
			var upwind = world.hex(coord - Vector2i(step, 0))
			if upwind != null and upwind.elevation >= 3:
				shadow = 0.18
		var near_water := 1.0 - minf(float(distance.get(coord, 4)), 4.0) / 4.0
		info.moisture = clampf(0.6 * IntNoise.fbm(seed_value, Channel.MOISTURE, p * 0.3, 3) + 0.45 * near_water - shadow, 0.0, 1.0)

## First matching rule wins (docs/WORLD_MAP.md §4), then forest and ruggedness
## from the biome's data plus noise.
static func _biomes(world, seed_value: int, settings: Dictionary) -> void:
	for coord in world.hexes:
		var info = world.hexes[coord]
		if info.is_land():
			if info.elevation >= 4:
				info.biome = "peaks"
			elif info.elevation == 3:
				info.biome = "mountain_pass"
			elif info.temperature < float(settings.cold_temperature):
				info.biome = "tundra"
			elif info.moisture > float(settings.wet_moisture) and info.elevation == 0:
				info.biome = "marsh"
			elif info.elevation == 2:
				info.biome = "highland_hills"
			elif not info.coast_edges.is_empty():
				info.biome = "coast"
			elif info.river_width() >= 2 or info.lake:
				info.biome = "riverland"
			else:
				info.biome = "heartland"
		var biome: Dictionary = world.data.biomes[info.biome]
		info.forest = clampf(float(biome.forest) * (0.6 + 0.8 * info.moisture) + (IntNoise.unit(seed_value, coord.x, coord.y, Channel.FOREST) - 0.5) * 0.3, 0.0, 1.0)
		var sea_cliffs := 0.2 if not info.coast_edges.is_empty() and info.elevation >= 1 else 0.0
		info.cliffs = clampf(float(biome.cliffs) + sea_cliffs + (IntNoise.unit(seed_value, coord.x, coord.y, Channel.CLIFFS) - 0.5) * 0.3, 0.0, 1.0)

## The start region: a gentle, settleable hex toward the middle-south, preferring
## rivers. Its surroundings are scouted; wildness grows with distance from it.
static func _start(world, seed_value: int, scout_radius: int) -> void:
	var best_score := -INF
	for coord in world.hexes:
		var info = world.hexes[coord]
		if not world.data.biomes[info.biome].settleable or world.data.biomes[info.biome].harsh:
			continue
		var column: int = WorldMap.column_of(coord)
		var score := -absf(column - world.columns * 0.5) - absf(coord.y - world.rows * 0.68) * 1.5
		if info.biome in ["heartland", "riverland"]:
			score += 4.0
		if info.biome == "riverland":
			score += 1.0
		# A seeded nudge so campaigns do not all start on the same hex.
		score += IntNoise.unit(seed_value, coord.x, coord.y, Channel.WILDNESS + 1) * 4.0
		if score > best_score:
			best_score = score
			world.start = coord
	for coord in world.hexes:
		var info = world.hexes[coord]
		var distance := HexMath.distance(coord, world.start)
		info.scouted = distance <= scout_radius
		var wild := float(distance) / 3.0 + (IntNoise.unit(seed_value, coord.x, coord.y, Channel.WILDNESS) - 0.5) * 1.5
		info.wildness = 0 if distance <= scout_radius else clampi(roundi(wild), 1, 5)

## Signature deposits (one, sometimes two), rare deposits for harsh biomes (plus
## a 25% chance of a second), and any extras, from the biome's pools in data.
static func _deposits(world, seed_value: int) -> void:
	for coord in world.hexes:
		var info = world.hexes[coord]
		var biome: Dictionary = world.data.biomes[info.biome]
		if not biome.settleable:
			continue
		var rng = SeededRNG.new(IntNoise.mix(seed_value, coord.x, coord.y, Channel.DEPOSITS))
		var signature := _available(world, info, biome.signature)
		var picks := 2 if rng.next_int(100) < 45 else 1
		for pick in picks:
			_take(rng, signature, info.deposits)
		var rare := _available(world, info, biome.rare)
		var rare_picks := int(biome.rare_count)
		if rare_picks > 0 and rng.next_int(100) < 25:
			rare_picks += 1
		for pick in rare_picks:
			_take(rng, rare, info.deposits)
		for deposit in biome.get("extra", {}):
			if not deposit in info.deposits and _allowed(world, info, deposit) and rng.next_int(1000) < int(float(biome.extra[deposit]) * 1000.0):
				info.deposits.append(deposit)

## The pool without deposits whose requirement this hex fails.
static func _available(world, info, pool: Dictionary) -> Dictionary:
	var result := {}
	for deposit in pool:
		if _allowed(world, info, deposit):
			result[deposit] = pool[deposit]
	return result

static func _allowed(world, info, deposit: String) -> bool:
	if deposit == "fish_shoals":
		return info.lake or not info.river_edges.is_empty() or not info.coast_edges.is_empty()
	if deposit == "amber_shore": return not info.coast_edges.is_empty()
	var requirement: String = world.data.deposits[deposit].get("requires", "")
	return requirement != "ocean_edge" or not info.coast_edges.is_empty()

## Weighted pick without replacement; does nothing once the pool is empty.
static func _take(rng, pool: Dictionary, into: Array[String]) -> void:
	var total := 0
	for deposit in pool:
		total += int(pool[deposit])
	if total <= 0:
		return
	var roll: int = rng.next_int(total)
	for deposit in pool:
		roll -= int(pool[deposit])
		if roll < 0:
			into.append(deposit)
			pool.erase(deposit)
			return
