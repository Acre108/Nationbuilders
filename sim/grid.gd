extends RefCounted
const SIZE := 40
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
var terrain: Array[String] = []
var deposits: Array[String] = []
var occupied: Dictionary = {}
var roads: Dictionary = {}
var revision := 0
var _path_cache: Dictionary = {}

func _init(rng) -> void:
	for y in SIZE:
		for x in SIZE:
			var roll: int = rng.next_int(100)
			var tile := "grass"
			if x >= 32 + (y / 9) % 2:
				tile = "water"
			elif (x < 9 or y < 12 or y > 27) and roll < 55:
				tile = "forest"
			elif (x < 7 or y < 9 or y > 30) and roll > 90:
				tile = "rock"
			terrain.append(tile)
			deposits.append("timber" if tile == "forest" else ("fertile_soil" if tile == "grass" and x > 10 and x < 20 and y > 13 and y < 24 else ""))

func inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < SIZE and cell.y < SIZE

func terrain_at(cell: Vector2i) -> String:
	return terrain[cell.y * SIZE + cell.x] if inside(cell) else "void"

func changed() -> void:
	revision += 1
	_path_cache.clear()

func access(building) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for tile in building.cells():
		for direction in DIRECTIONS:
			var neighbor: Vector2i = tile + direction
			if roads.has(neighbor) and neighbor not in result:
				result.append(neighbor)
	return result

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
	if not roads.has(start) or not roads.has(goal):
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
			if roads.has(neighbor) and (not distance.has(neighbor) or candidate < int(distance[neighbor])):
				distance[neighbor] = candidate
				previous[neighbor] = current
				if neighbor not in frontier:
					frontier.append(neighbor)
	_path_cache[key] = empty
	return empty

func _heuristic(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
