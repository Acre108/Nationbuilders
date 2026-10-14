extends RefCounted
## Finds the cells whose presentation inputs changed since the previous call, so
## a view can rebuild a small neighbourhood instead of the whole site. Each
## consumer keeps its own instance; presentation only, never touches sim state.
const OCCUPIED := 1
const ROAD := 2
const FOREST := 4
const TREE := 8
const SAPLING := 16
const STUMP := 32
const DEPOSIT := 64
var signatures := PackedByteArray()
var grid_id := 0
var width := 0
## True when the last update had nothing to compare against; rebuild everything.
var reset := true

func update(grid) -> Array[Vector2i]:
	var next := PackedByteArray()
	next.resize(grid.width * grid.height)
	for cell in grid.occupied: _mark(next, grid, cell, OCCUPIED)
	for cell in grid.roads: _mark(next, grid, cell, ROAD)
	for cell in grid.trees: _mark(next, grid, cell, TREE)
	for cell in grid.saplings: _mark(next, grid, cell, SAPLING)
	for cell in grid.stumps: _mark(next, grid, cell, STUMP)
	for index in next.size():
		if grid.terrain[index] == "forest": next[index] |= FOREST
		if not grid.deposits[index].is_empty(): next[index] |= DEPOSIT
	var changed: Array[Vector2i] = []
	reset = grid.get_instance_id() != grid_id or grid.width != width or signatures.size() != next.size()
	if not reset:
		for index in next.size():
			if next[index] != signatures[index]:
				changed.append(Vector2i(index % width, index / width))
	grid_id = grid.get_instance_id()
	width = grid.width
	signatures = next
	return changed

## Every in-bounds cell within `radius` (a square) of any changed cell, once each.
static func around(cells: Array[Vector2i], radius: int, grid) -> Array[Vector2i]:
	var seen := {}
	var result: Array[Vector2i] = []
	for cell in cells:
		for y in range(maxi(0, cell.y - radius), mini(grid.height, cell.y + radius + 1)):
			for x in range(maxi(0, cell.x - radius), mini(grid.width, cell.x + radius + 1)):
				var nearby := Vector2i(x, y)
				if not seen.has(nearby):
					seen[nearby] = true
					result.append(nearby)
	return result

static func _mark(into: PackedByteArray, grid, cell: Vector2i, bit: int) -> void:
	if cell.x >= 0 and cell.y >= 0 and cell.x < grid.width and cell.y < grid.height:
		into[cell.y * grid.width + cell.x] |= bit
