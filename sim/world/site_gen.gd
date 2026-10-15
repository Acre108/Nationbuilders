extends RefCounted
## Deterministic village-scale interpretation of a selected world tile and its
## six neighbours. Square command cells remain; the physical boundary is hex.
const SitePackage = preload("res://sim/world/site_package.gd")
const HexMath = preload("res://sim/world/hex_math.gd")
const Layout = preload("res://sim/world/terrain_layout.gd")
const IntNoise = preload("res://sim/world/int_noise.gd")
const Grid = preload("res://sim/grid.gd")
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const HEX_WIDTH := 48.0
const SIZE := Vector2i(144, 168)
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

static func generate(world, coord: Vector2i):
	var site = SitePackage.new(SIZE.x, SIZE.y, "void")
	site.name = "world_%d_%d_%d" % [world.seed_value, coord.x, coord.y]
	site.seed_value = IntNoise.mix(world.seed_value, coord.x, coord.y, 901) & 0x7FFFFFFF
	site.world_coord = coord
	site.hex_width = HEX_WIDTH
	site.world_origin = Layout.centre(coord) - Vector2(SIZE) / HEX_WIDTH
	site.footprint.fill(0)
	site.reach.fill(0)
	var info = world.hex(coord)
	if info == null or not bool(world.data.biomes[info.biome].settleable):
		site.generation_error = "Cannot settle this world tile"
		return site
	site.biome = info.biome
	site.promised_water = not info.river_edges.is_empty() or info.lake or not info.coast_edges.is_empty()
	var owners: Array[Vector2i] = world.reach(coord)
	var paths := {}
	for owner in owners:
		site.districts["%d,%d" % [owner.x,owner.y]] = world.hex(owner).to_dict()
		for edge in world.hex(owner).river_edges:
			paths[Vector3i(owner.x, owner.y, int(edge))] = Layout.river_path(world, owner, int(edge))
	for y in site.height:
		for x in site.width:
			var cell := Vector2i(x, y)
			var point: Vector2 = site.world_point(cell)
			var local := point - Layout.centre(coord)
			var index: int = site.index(cell)
			var owner := HexMath.from_point(point / Layout.SCALE)
			# Fill the small outer corner wedges with the nearest reach descriptor.
			# This makes one regular hex, with seven district centres, rather than a
			# scalloped union. No eighth district can become buildable.
			if owner not in owners:
				owner = _nearest_owner(owners, point)
			site.owner_coords.append(owner)
			if not _outer_hex(local): continue
			site.footprint[index] = 1
			site.reach[index] = 1
			var descriptor = world.hex(owner)
			var water: String = Layout.water_at(world, owner, point, paths)
			var tile := water if not water.is_empty() else "grass"
			var relief: float = Layout.relief_at(world, owner, point, paths)
			var level: int = descriptor.elevation * 2 + int(floor(relief * 8.0))
			if not descriptor.is_land(): level = 0
			site.levels[index] = level
			if water.is_empty():
				var grove: float = Layout.grove_at(world, owner, point)
				if descriptor.forest > 0.0 and grove > 0.68 - descriptor.forest * 0.42 and (x + y) % 3 == 0:
					tile = "forest"
				elif descriptor.biome == "peaks" or (descriptor.biome == "mountain_pass" and relief > 0.95):
					tile = "rock"
			site.terrain[index] = tile
			site.deposits[index] = "timber" if tile == "forest" else ("fertile_soil" if tile == "grass" and descriptor.biome not in ["tundra", "mountain_pass"] else "")
	_add_ramps(site, world)
	var water_distances := _water_distances(site)
	_fertility(site, world, water_distances)
	_place_deposits(site, world, owners, water_distances)
	var spot := _find_starter(site, water_distances)
	if spot.x < 0:
		site.generation_error = "Too rugged: no natural starter clearing near the promised water" if site.promised_water else "Too rugged: no natural starter clearing"
		return site
	site.founding_spot = spot
	site.settlement_clearance = Rect2i(spot + Vector2i(-6, -6), Vector2i(18, 11))
	site.playability_result = playability(site)
	if not site.playability_result.ok: site.generation_error = site.playability_result.reason
	return site

static func _outer_hex(point: Vector2) -> bool:
	# A pointy-top hex has edge normals every sixty degrees.
	for edge in 6:
		if point.dot(Layout.direction(edge)) > 3.0: return false
	return true

static func _nearest_owner(owners: Array[Vector2i], point: Vector2) -> Vector2i:
	var best := owners[0]
	var distance := INF
	for owner in owners:
		var candidate := point.distance_squared_to(Layout.centre(owner))
		if candidate < distance:
			best = owner
			distance = candidate
	return best

static func _add_ramps(site, world) -> void:
	for y in site.height:
		for x in site.width:
			var cell := Vector2i(x, y)
			if not site.inside(cell): continue
			var index: int = site.index(cell)
			if site.terrain[index] not in ["grass", "forest", "stream"]: continue
			var owner: Vector2i = site.owner_coords[index]
			var info = world.hex(owner)
			for direction in DIRECTIONS:
				var other: Vector2i = cell + direction
				if not site.inside(other) or site.levels[site.index(other)] != site.levels[index] - 1: continue
				# Founding relief is road-accessible. Wilder neighbour cliffs keep
				# narrow natural passes, rather than flattening entire districts.
				if owner == site.world_coord or info.cliffs < 0.4 or posmod(x + y, 11) <= 2:
					site.ramps[index] = 1

static func _starter_cells() -> Dictionary:
	var cells := {}
	for x in range(-5, 11): cells[Vector2i(x, -1)] = true
	for y in range(-5, 4): cells[Vector2i(3, y)] = true
	for entry in [[Vector2i(0,0),Vector2i(3,2)], [Vector2i(4,0),Vector2i(2,2)], [Vector2i(4,-2),Vector2i.ONE], [Vector2i(-5,-3),Vector2i(3,2)], [Vector2i(7,0),Vector2i(2,2)], [Vector2i(-1,-3),Vector2i(2,2)], [Vector2i(6,-3),Vector2i(2,2)]]:
		for y in entry[1].y:
			for x in entry[1].x: cells[entry[0] + Vector2i(x,y)] = true
	return cells

static func _find_starter(site, water_distances: PackedInt32Array) -> Vector2i:
	var required := _starter_cells()
	var best := Vector2i(-1,-1)
	var score := INF
	for y in site.height:
		for x in site.width:
			var spot := Vector2i(x,y)
			if not site.inside(spot) or site.owner_coords[site.index(spot)] != site.world_coord: continue
			var level: int = site.levels[site.index(spot)]
			var valid := true
			for offset in required:
				var cell: Vector2i = spot + offset
				if not site.inside(cell):
					valid = false
					break
				var index: int = site.index(cell)
				if site.owner_coords[index] != site.world_coord or site.terrain[index] != "grass" or site.levels[index] != level or site.ramps[index] != 0:
					valid = false
					break
			if not valid: continue
			var water_distance := mini(9,water_distances[site.index(spot)])
			if site.promised_water and water_distance > 8: continue
			var candidate: float = Vector2(spot).distance_squared_to(Vector2(site.width,site.height) * 0.5) + float(water_distance) * 0.1
			if candidate < score:
				best = spot
				score = candidate
	return best

static func _water_distance(site, spot: Vector2i, radius: int = 8) -> int:
	var result := radius + 1
	for y in range(spot.y - radius, spot.y + radius + 1):
		for x in range(spot.x - radius, spot.x + radius + 1):
			var cell := Vector2i(x,y)
			var distance := absi(x - spot.x) + absi(y - spot.y)
			if distance < result and site.inside(cell) and site.terrain[site.index(cell)] in Grid.WATER: result = distance
	return result

static func _water_distances(site) -> PackedInt32Array:
	var distance := PackedInt32Array()
	distance.resize(site.width * site.height)
	distance.fill(999)
	var queue: Array[Vector2i] = []
	for y in site.height:
		for x in site.width:
			var cell := Vector2i(x,y)
			if site.inside(cell) and site.terrain[site.index(cell)] in Grid.WATER:
				distance[site.index(cell)] = 0
				queue.append(cell)
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for direction in DIRECTIONS:
			var other: Vector2i = cell + direction
			if not site.inside(other): continue
			var index: int = site.index(other)
			var candidate := distance[site.index(cell)] + 1
			if candidate < distance[index]:
				distance[index] = candidate
				queue.append(other)
	return distance

static func _place_deposits(site, world, owners: Array[Vector2i], water_distances: PackedInt32Array) -> void:
	var district_cells := {}
	for owner in owners: district_cells[owner] = []
	for y in site.height:
		for x in site.width:
			var cell := Vector2i(x,y)
			if site.inside(cell): district_cells[site.owner_coords[site.index(cell)]].append(cell)
	for owner in owners:
		var descriptor = world.hex(owner)
		for deposit in descriptor.deposits:
			var candidates: Array[Vector2i] = []
			for cell in district_cells[owner]:
				var index: int = site.index(cell)
				if site.deposits[index] not in ["","timber","fertile_soil",deposit]: continue
				var terrain: String = site.terrain[index]
				if deposit in ["fish_shoals", "fresh_water", "shallows"] and terrain not in Grid.WATER: continue
				if deposit not in ["fish_shoals", "fresh_water", "shallows"] and terrain in Grid.WATER: continue
				if deposit in ["sea_salt_flats", "amber_shore"] and water_distances[index] > 3: continue
				if deposit == "clay_bank" and descriptor.biome != "marsh" and descriptor.moisture < 0.55 and water_distances[index] > 4: continue
				if deposit in ["oak_grove", "timber", "wild_berries", "game", "trapline"] and terrain != "forest": continue
				candidates.append(cell)
			if candidates.is_empty() and deposit not in ["fish_shoals", "fresh_water", "shallows", "sea_salt_flats", "amber_shore"]:
				# Prospecting exposes buried or dormant resources on dry ground;
				# open-water resources must remain on actual promised water.
				for cell in district_cells[owner]:
					if site.terrain[site.index(cell)] in ["grass","forest","rock"] and site.deposits[site.index(cell)] in ["","timber","fertile_soil",deposit]: candidates.append(cell)
			if not candidates.is_empty():
				var selected: Vector2i = candidates[IntNoise.mix(world.seed_value, owner.x, owner.y, deposit.hash() & 0x7FFF) % candidates.size()]
				site.deposits[site.index(selected)] = deposit
			elif owner == site.world_coord:
				site.generation_error = "Too rugged: promised " + deposit.replace("_", " ") + " has no suitable terrain"

static func playability(site, validate_starter: bool = true) -> Dictionary:
	var result := {"ok":false, "reason":"", "founding_cells":0, "reach_cells":0, "water_distance":9}
	if not site.generation_error.is_empty():
		result.reason = site.generation_error
		return result
	var grid = Grid.new(site)
	result.founding_cells = _connected(site, grid, true)
	result.reach_cells = _connected(site, grid, false)
	result.water_distance = _water_distance(site, site.founding_spot)
	if result.founding_cells < 250 or result.reach_cells < 800:
		result.reason = "Too rugged: insufficient connected founding land"
	elif site.promised_water and result.water_distance > 8:
		result.reason = "Too rugged: water is too far from the founding clearing"
	elif validate_starter:
		var sim = Sim.new(site.seed_value, null, site)
		if not sim.valid or not Scenario.starter(sim): result.reason = "Starter layout: " + sim.last_error
	result.ok = result.reason.is_empty()
	return result

static func _connected(site, grid, founding_only: bool) -> int:
	var queue: Array[Vector2i] = [site.founding_spot]
	var visited := {site.founding_spot:true}
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for direction in DIRECTIONS:
			var other: Vector2i = cell + direction
			if visited.has(other) or not grid.in_reach(other): continue
			var index: int = site.index(other)
			if founding_only and site.owner_coords[index] != site.world_coord: continue
			if site.terrain[index] not in ["grass","forest","stream"] or not grid.passable(cell,other): continue
			visited[other] = true
			queue.append(other)
	return visited.size()


## Fertile soil (docs/SUPPLY_CHAINS.md §2) lies in loamy patches of grass,
## richer within a few tiles of water. The biome sets how much land clears the
## bar: heartland and riverland most, coast and hills less, marsh least.
## Tundra and mountain passes have none. Fields work at half speed elsewhere.
const FERTILE_BAR := {"heartland": 0.46, "riverland": 0.48, "coast": 0.56, "highland_hills": 0.56, "marsh": 0.62}

static func _fertility(site, world, water_distances: PackedInt32Array) -> void:
	for index in site.terrain.size():
		if site.deposits[index] != "fertile_soil":
			continue
		var bar: float = FERTILE_BAR.get(world.hex(site.owner_coords[index]).biome, 2.0)
		var cell := Vector2i(index % site.width, index / site.width)
		var loam := IntNoise.fbm(world.seed_value, 613, Vector2(cell) / 9.0, 3)
		var water: int = water_distances[index]
		loam += 0.2 if water <= 3 else (0.1 if water <= 8 else 0.0)
		if loam < bar:
			site.deposits[index] = ""
