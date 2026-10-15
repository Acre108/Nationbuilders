extends RefCounted
## Wild berry bushes in the woods (docs/WILDLIFE.md, "Wild berries"). Bushes
## grow on grass under the canopy: a tile with a tree beside it. When the site
## is founded, about one such tile in BUSH_ODDS holds a bush, chosen by a
## seeded hash. Each bush carries up to MAX_FRUIT units of fruit and ripens one
## more every REGROW_TICKS. A bush withers once no tree stands beside it, or
## when a road or building covers it, so felling the woods loses the berries
## with the timber. Foragers pick them. Everything is deterministic.
const IntNoise = preload("res://sim/world/int_noise.gd")
const MAX_FRUIT := 3
const REGROW_TICKS := 300
const BUSH_ODDS := 12
const SALT := 7717
## Fruit per bush, by cell.
var bushes: Dictionary = {}
var _revision := -1
var _forest_revision := -1

## Places the bushes the woods hold at founding, all ripe.
func setup(grid) -> void:
	bushes.clear()
	for y in grid.height:
		for x in grid.width:
			var cell := Vector2i(x, y)
			if IntNoise.mix(SALT, x, y) % BUSH_ODDS == 0 and not grid.settlement_clearance.has_point(cell) and suits(grid, cell):
				bushes[cell] = MAX_FRUIT
	_revision = grid.revision
	_forest_revision = grid.forest_revision

## Grass under the canopy, free of roads and buildings.
static func suits(grid, cell: Vector2i) -> bool:
	if not grid.in_reach(cell) or grid.terrain_at(cell) != "grass" or grid.trees.has(cell) or grid.occupied.has(cell) or grid.roads.has(cell):
		return false
	for direction in grid.DIRECTIONS:
		if grid.trees.has(cell + direction):
			return true
	return false

func ripe() -> int:
	var result := 0
	for fruit in bushes.values():
		result += int(fruit)
	return result

## Bushes wither as soon as their land changes; fruit ripens on a timer.
func update(sim) -> void:
	var grid = sim.grid
	if grid.revision != _revision or grid.forest_revision != _forest_revision:
		_revision = grid.revision
		_forest_revision = grid.forest_revision
		for cell in bushes.keys():
			if not suits(grid, cell):
				bushes.erase(cell)
	if sim.tick % REGROW_TICKS == 0:
		for cell in bushes:
			bushes[cell] = mini(MAX_FRUIT, int(bushes[cell]) + 1)

## The nearest bush with fruit within `radius` tiles of a point, by straight
## distance, then by row and column. (-1, -1) when none is in reach.
func nearest(from: Vector2, radius: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := 0.0
	for cell in bushes:
		if int(bushes[cell]) < 1:
			continue
		var distance := from.distance_to(Vector2(cell) + Vector2(0.5, 0.5))
		if distance > radius:
			continue
		if best.x < 0 or distance < best_distance or (distance == best_distance and (cell.y < best.y or (cell.y == best.y and cell.x < best.x))):
			best = cell
			best_distance = distance
	return best

## A forager's hut picks the nearest ripe bush within its work_radius; each
## cycle takes one fruit and fills its output.
static func gather(sim, building) -> void:
	var row: Dictionary = building.definition
	if not building.staffed:
		building.status = "no workers" if building.workers_enabled else "workers stopped"
		building.progress = 0
		return
	if not building.output.fits(row.outputs):
		building.status = sim.output_status(building)
		building.progress = 0
		return
	var size: Vector2i = building.footprint()
	var from := Vector2(building.cell) + Vector2(size) * 0.5
	var bush: Vector2i = sim.forage.nearest(from, int(row.work_radius))
	if bush.x < 0:
		building.status = "no ripe berries nearby"
		building.progress = 0
		return
	building.status = "gathering wild berries"
	building.progress += 1
	if building.progress < int(row.cycle_ticks):
		return
	building.progress = 0
	sim.forage.bushes[bush] = int(sim.forage.bushes[bush]) - 1
	for good in row.outputs:
		building.output.add(good, int(row.outputs[good]))
		sim.produced[good] = int(sim.produced.get(good, 0)) + int(row.outputs[good])

## Bushes as [x, y, fruit], in row order.
func snapshot() -> Array:
	var cells: Array = bushes.keys()
	cells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var result: Array = []
	for cell in cells:
		result.append([cell.x, cell.y, bushes[cell]])
	return result

## Restores saved bushes for this grid; false if malformed. Call after the
## grid itself is restored.
func restore(state, grid) -> bool:
	if not state is Array:
		return false
	var restored := {}
	for entry in state:
		if not entry is Array or entry.size() != 3:
			return false
		for value in entry:
			if not (value is int or value is float) or value != int(value):
				return false
		var cell := Vector2i(int(entry[0]), int(entry[1]))
		if not grid.in_reach(cell) or restored.has(cell) or int(entry[2]) < 0 or int(entry[2]) > MAX_FRUIT:
			return false
		restored[cell] = int(entry[2])
	bushes = restored
	_revision = grid.revision
	_forest_revision = grid.forest_revision
	return true
