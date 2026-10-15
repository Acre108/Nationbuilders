extends Node3D
## Deer and boar drawn where the simulation's herds live (sim/wildlife.gd).
## Each animal has a home tile chosen from its range's habitat, deer on
## meadow and boar on the forest floor, and idles around it. Placement uses
## seeded hashes only, so presentation never touches the simulation RNG.
const IntNoise = preload("res://sim/world/int_noise.gd")
const Wildlife = preload("res://sim/wildlife.gd")
## How far an animal strays from its home tile, in tiles.
const WANDER := 0.38
var models
var grid
var relief
## Key "species:range:n" -> {"node", "home" (Vector2), "phase", "pace"}.
var animals: Dictionary = {}
var signature := ""
var time := 0.0

func _init(medieval_models) -> void:
	models = medieval_models
	name = "Wildlife"

## A new site: forget every animal.
func build(site_grid, terrain_relief) -> void:
	grid = site_grid
	relief = terrain_relief
	for entry in animals.values():
		entry.node.queue_free()
	animals.clear()
	signature = ""

## Adds or removes animals to match the herds. Animals whose home tile has
## been felled, built on or paved move to another spot in their range.
func sync(wildlife) -> void:
	if grid == null:
		return
	var next := "%d|%d|%s|%s" % [grid.revision, grid.forest_revision, str(wildlife.herds.deer), str(wildlife.herds.boar)]
	if next == signature:
		return
	signature = next
	var wanted: Dictionary = {}
	for species in Wildlife.SPECIES:
		for index in wildlife.range_count():
			var count: int = wildlife.herds[species][index]
			if count == 0:
				continue
			var spots: Array = []
			for n in count:
				var key := "%s:%d:%d" % [species, index, n]
				wanted[key] = true
				if animals.has(key) and _suits(species, _home_cell(animals[key])):
					continue
				if spots.is_empty():
					spots = _spots(wildlife, species, index)
				if spots.is_empty():
					continue
				var cell: Vector2i = spots[IntNoise.mix(9113, index, n, species.hash() & 0x7FFF) % spots.size()]
				_place(key, species, cell, index, n)
	for key in animals.keys():
		if not wanted.has(key):
			animals[key].node.queue_free()
			animals.erase(key)

func _home_cell(entry: Dictionary) -> Vector2i:
	return Vector2i(floori(entry.home.x), floori(entry.home.y))

func _place(key: String, species: String, cell: Vector2i, index: int, n: int) -> void:
	var entry: Dictionary = animals.get(key, {})
	if entry.is_empty():
		var node: Node3D = models.model("animal_" + species)
		if node == null:
			return
		node.name = key.replace(":", "_")
		add_child(node)
		entry = {"node": node, "phase": IntNoise.unit(9113, index, n, 31) * TAU, "pace": 0.07 + IntNoise.unit(9113, index, n, 37) * 0.05}
		if species == "boar":
			entry.pace *= 1.4
		animals[key] = entry
	entry.home = Vector2(cell) + Vector2(0.5, 0.5)
	_pose(entry)

## Tiles in a range where an animal of this species can stand.
func _spots(wildlife, species: String, index: int) -> Array:
	var result: Array = []
	var origin := Vector2i(index % wildlife.columns, index / wildlife.columns) * Wildlife.RANGE
	for y in Wildlife.RANGE:
		for x in Wildlife.RANGE:
			var cell := origin + Vector2i(x, y)
			if _suits(species, cell):
				result.append(cell)
	return result

## Deer stand on meadow; boar on grass beside a tree, under the canopy.
func _suits(species: String, cell: Vector2i) -> bool:
	if not grid.in_reach(cell) or grid.occupied.has(cell) or grid.roads.has(cell) or grid.terrain_at(cell) != "grass":
		return false
	if species == "deer":
		return Wildlife._meadow(grid, cell)
	for direction in grid.DIRECTIONS:
		if grid.trees.has(cell + direction):
			return true
	return false

func _process(delta: float) -> void:
	time += delta
	for entry in animals.values():
		_pose(entry)

## Slow wandering around home: a Lissajous loop, facing the way it moves.
func _pose(entry: Dictionary) -> void:
	var t: float = time * float(entry.pace) + float(entry.phase)
	var offset := Vector2(sin(t), sin(t * 1.7 + 0.6)) * WANDER
	var heading := Vector2(cos(t), 1.7 * cos(t * 1.7 + 0.6))
	var point: Vector2 = entry.home + offset
	var node: Node3D = entry.node
	node.position = Vector3(point.x, relief.surface_height(point) if relief != null else 0.0, point.y)
	node.rotation.y = atan2(-heading.y, heading.x)
