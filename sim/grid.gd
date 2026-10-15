extends RefCounted
## Authoritative tiles for one site. Size, terrain, levels and reach come from
## its SitePackage; roads and buildings are added by commands.
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const WATER := ["water", "stream", "river", "lake", "ocean"]
var width := 0
var height := 0
var terrain: Array[String] = []
var deposits: Array[String] = []
var levels := PackedInt32Array()
var ramps := PackedByteArray()
var reach := PackedByteArray()
var footprint := PackedByteArray()
var owner_coords: Array[Vector2i] = []
var districts: Dictionary = {}
var hex_width := 0.0
var world_origin := Vector2.ZERO
var occupied: Dictionary = {}
var roads: Dictionary = {}
var revision := 0
## Trees and saplings are actual resources, separate from road path revisions.
var trees: Dictionary = {}
var saplings: Dictionary = {} # cell -> maturity tick
var stumps: Dictionary = {}
var forest_revision := 0
var settlement_clearance := Rect2i()
var _path_cache: Dictionary = {}
## Derived per road revision: each building's road frontage, and the road
## distance from its frontage to every reachable road cell.
var _cache_revision := -1
var _access_cache: Dictionary = {}
var _fields: Dictionary = {}
var _networks: Dictionary = {}

func _init(site) -> void:
	width = site.width
	height = site.height
	terrain = site.terrain.duplicate()
	deposits = site.deposits.duplicate()
	levels = site.levels.duplicate()
	ramps = site.ramps.duplicate()
	reach = site.reach.duplicate()
	footprint = site.footprint.duplicate()
	owner_coords = site.owner_coords.duplicate()
	districts = site.districts.duplicate(true)
	hex_width = site.hex_width
	world_origin = site.world_origin
	settlement_clearance = site.settlement_clearance
	for y in height:
		for x in width:
			if terrain_at(Vector2i(x,y)) == "forest":
				trees[Vector2i(x,y)] = true

func clear_tree(cell: Vector2i, leave_stump: bool = false) -> void:
	if not inside(cell): return
	var had_tree := trees.erase(cell)
	var had_sapling := saplings.erase(cell)
	var had_stump := stumps.erase(cell)
	if had_tree and leave_stump:
		stumps[cell] = true
	if terrain_at(cell) == "forest":
		terrain[cell.y*width+cell.x] = "grass"
		deposits[cell.y*width+cell.x] = ""
	if had_tree or had_sapling or had_stump:
		forest_revision += 1

func can_plant(cell: Vector2i) -> bool:
	# Keep the established spacing between crowns as woodland is replenished.
	return in_reach(cell) and terrain_at(cell) == "grass" and (posmod(cell.x+cell.y,3) == 0 or stumps.has(cell)) and not is_ramp(cell) and not settlement_clearance.has_point(cell) and not occupied.has(cell) and not roads.has(cell) and not trees.has(cell) and not saplings.has(cell)

func plant_tree(cell: Vector2i, maturity_tick: int) -> void:
	if not can_plant(cell): return
	saplings[cell] = maturity_tick
	stumps.erase(cell)
	forest_revision += 1

func grow_trees(tick: int) -> void:
	for cell in saplings.keys():
		if tick < int(saplings[cell]): continue
		saplings.erase(cell)
		if not inside(cell) or occupied.has(cell) or roads.has(cell): continue
		trees[cell] = true
		terrain[cell.y*width+cell.x] = "forest"
		deposits[cell.y*width+cell.x] = "timber"
		forest_revision += 1

func inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height and footprint[cell.y * width + cell.x] == 1

func world_point(cell: Vector2i) -> Vector2:
	return world_origin + (Vector2(cell) + Vector2(0.5,0.5)) * (2.0 / hex_width) if hex_width > 0.0 else Vector2(cell)

func terrain_at(cell: Vector2i) -> String:
	return terrain[cell.y * width + cell.x] if inside(cell) else "void"

func level_at(cell: Vector2i) -> int:
	return levels[cell.y * width + cell.x] if inside(cell) else 0

func is_ramp(cell: Vector2i) -> bool:
	return inside(cell) and ramps[cell.y * width + cell.x] == 1

func in_reach(cell: Vector2i) -> bool:
	return inside(cell) and reach[cell.y * width + cell.x] == 1

func is_water(cell: Vector2i) -> bool:
	return terrain_at(cell) in WATER

## Whether a carrier can step between two 4-neighbours: same level, or one
## level apart where the upper tile is a ramp. Any other level change is a cliff.
func passable(a: Vector2i, b: Vector2i) -> bool:
	if not inside(a) or not inside(b):
		return false
	var difference := level_at(a) - level_at(b)
	if difference == 0:
		return true
	if absi(difference) != 1:
		return false
	return is_ramp(a if difference > 0 else b)

## Call after any change to roads, buildings or relief: it invalidates routes.
func changed() -> void:
	revision += 1
	_path_cache.clear()

func _sync_caches() -> void:
	if _cache_revision != revision:
		_cache_revision = revision
		_access_cache.clear()
		_fields.clear()
		_networks.clear()

## The connected road network a carrier at this cell walks on, or -1 where no
## route can start. Cells on one network reach exactly the same buildings.
func network(cell: Vector2i) -> int:
	if not in_reach(cell) or not roads.has(cell):
		return -1
	_sync_caches()
	if _networks.is_empty():
		var id := 0
		for start in roads:
			if _networks.has(start):
				continue
			id += 1
			_networks[start] = id
			var frontier: Array[Vector2i] = [start]
			while not frontier.is_empty():
				var current: Vector2i = frontier.pop_back()
				for direction in DIRECTIONS:
					var neighbor: Vector2i = current + direction
					if not _networks.has(neighbor) and roads.has(neighbor) and passable(current, neighbor):
						_networks[neighbor] = id
						frontier.append(neighbor)
	return int(_networks[cell])

## Road cells beside the building that a carrier can step from. The result is
## shared with the cache, so callers must not modify it.
func access(building) -> Array[Vector2i]:
	_sync_caches()
	var cached = _access_cache.get(building.uid)
	if cached != null:
		return cached
	var result: Array[Vector2i] = []
	for tile in building.cells():
		for direction in DIRECTIONS:
			var neighbor: Vector2i = tile + direction
			if roads.has(neighbor) and passable(tile, neighbor) and neighbor not in result:
				result.append(neighbor)
	_access_cache[building.uid] = result
	return result

## The length in cells of route_between(a, b), or -1 when no road joins them.
func distance(a, b) -> int:
	var field := _field(a)
	var best := -1
	for goal in access(b):
		if in_reach(goal) and field.has(goal):
			var cells: int = int(field[goal]) + 1
			if best < 0 or cells < best:
				best = cells
	return best

## Whether route_to(cell, access(building)) would find a route.
func reaches(cell: Vector2i, building) -> bool:
	return in_reach(cell) and roads.has(cell) and _field(building).has(cell)

## Road cells by steps from the building's frontage; distance() to a building
## whose frontage is on that cell is the steps + 1. Read only: it is the cache.
func road_steps(building) -> Dictionary:
	return _field(building)

## Steps from the building's frontage to each road cell, by breadth-first
## search. Steps are symmetric, so this also measures routes towards it.
func _field(building) -> Dictionary:
	_sync_caches()
	var cached = _fields.get(building.uid)
	if cached != null:
		return cached
	var field := {}
	var frontier: Array[Vector2i] = []
	for start in access(building):
		if in_reach(start):
			field[start] = 0
			frontier.append(start)
	var index := 0
	while index < frontier.size():
		var current: Vector2i = frontier[index]
		index += 1
		for direction in DIRECTIONS:
			var neighbor: Vector2i = current + direction
			if not field.has(neighbor) and roads.has(neighbor) and passable(current, neighbor):
				field[neighbor] = int(field[current]) + 1
				frontier.append(neighbor)
	_fields[building.uid] = field
	return field

func route_between(a, b) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	for start in access(a):
		var route := route_to(start, access(b))
		if not route.is_empty() and (best.is_empty() or route.size() < best.size()):
			best = route
	return best

func route_to(start: Vector2i, goals: Array[Vector2i]) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	for goal in goals:
		var route := astar(start, goal)
		if not route.is_empty() and (best.is_empty() or route.size() < best.size()):
			best = route
	return best

func astar(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not inside(start) or not inside(goal) or not in_reach(start) or not in_reach(goal) or not roads.has(start) or not roads.has(goal):
		return empty
	var key := "%s>%s" % [start, goal]
	if _path_cache.has(key):
		return _path_cache[key].duplicate()
	var frontier: Array[Vector2i] = [start]
	var distance := {start:0}
	var previous: Dictionary = {}
	while not frontier.is_empty():
		var best_index := 0
		for index in range(1, frontier.size()):
			if int(distance[frontier[index]]) + _heuristic(frontier[index], goal) < int(distance[frontier[best_index]]) + _heuristic(frontier[best_index], goal):
				best_index = index
		var current: Vector2i = frontier[best_index]
		frontier.remove_at(best_index)
		if current == goal:
			var route: Array[Vector2i] = [current]
			while previous.has(current):
				current = previous[current]
				route.push_front(current)
			_path_cache[key] = route.duplicate()
			return route
		for direction in DIRECTIONS:
			var neighbor: Vector2i = current + direction
			var candidate := int(distance[current]) + 1
			if roads.has(neighbor) and passable(current, neighbor) and (not distance.has(neighbor) or candidate < int(distance[neighbor])):
				distance[neighbor] = candidate
				previous[neighbor] = current
				if neighbor not in frontier:
					frontier.append(neighbor)
	_path_cache[key] = empty
	return empty

func _heuristic(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
