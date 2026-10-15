extends RefCounted
## Game that lives in the village's land (docs/WILDLIFE.md). The map is split
## into square ranges of RANGE × RANGE tiles. Each range's habitat comes from
## the actual grid: mature trees are woodland, and open grass with no tree
## beside it, no road and no building is meadow. Wild boar live in woodland;
## red deer graze meadow but need woodland cover in or beside their range.
## Buildings and roads disturb a range. A range's capacity for each species
## follows its habitat. Herds breed towards capacity, recolonise empty habitat
## from neighbouring ranges, and leave or die when their habitat is felled or
## built over. Hunters take from them. Everything is integer and deterministic;
## no random numbers are drawn.
const RANGE := 10
## Herds change once every BREED_TICKS.
const BREED_TICKS := 600
const SPECIES := ["deer", "boar"]
const NAMES := {"deer": "red deer", "boar": "wild boar"}
## Boar: one per BOAR_TREES mature trees beyond the first BOAR_MIN_TREES.
const BOAR_MIN_TREES := 10
const BOAR_TREES := 6
## Deer: one per DEER_MEADOW meadow tiles, and one per DEER_COVER trees in the
## range and its four neighbours, whichever allows fewer.
const DEER_MEADOW := 20
const DEER_COVER := 12
const MAX_HERD := 4
## A range with this many building or road tiles is settled and holds no game;
## any fewer cost each species one animal of capacity.
const SETTLED_TILES := 12
var columns := 0
var rows := 0
## Animals per range, indexed y * columns + x, for each species.
var herds: Dictionary = {}
## Capacity per range for each species, derived from the grid. Rebuilt when
## the grid's road/building revision or its forest revision changes.
var _capacity: Dictionary = {}
var _capacity_key := []

## Sizes the ranges for this grid and fills every range to its capacity, as
## the land was before the settlers came.
func setup(grid) -> void:
	columns = ceili(float(grid.width) / RANGE)
	rows = ceili(float(grid.height) / RANGE)
	_capacity_key = []
	for species in SPECIES:
		herds[species] = capacity(grid, species).duplicate()

func range_count() -> int:
	return columns * rows

func range_of(cell: Vector2i) -> int:
	return (cell.y / RANGE) * columns + cell.x / RANGE

## The centre of a range, in tile coordinates.
func centre(index: int) -> Vector2:
	return Vector2((index % columns) * RANGE, (index / columns) * RANGE) + Vector2(RANGE, RANGE) * 0.5

func total(species: String) -> int:
	var result := 0
	for count in herds[species]:
		result += int(count)
	return result

## Each range's capacity for a species on the current grid.
func capacity(grid, species: String) -> Array:
	var key := [grid.revision, grid.forest_revision, grid.width, grid.height]
	if _capacity_key != key:
		_capacity_key = key
		_capacity = _habitat_capacity(grid)
	return _capacity[species]

## Woodland, meadow and disturbance per range, read straight from the grid.
func habitat(grid) -> Dictionary:
	var count := range_count()
	var trees: Array = []
	var meadow: Array = []
	var built: Array = []
	for list in [trees, meadow, built]:
		list.resize(count)
		list.fill(0)
	# Flat masks keep the whole-map scan cheap: 1 = tree (or sapling), 2 = built.
	var width: int = grid.width
	var mask := PackedByteArray()
	mask.resize(width * grid.height)
	for cell in grid.trees:
		if grid.in_reach(cell):
			trees[range_of(cell)] += 1
			mask[cell.y * width + cell.x] = 1
	for cell in grid.saplings:
		if grid.inside(cell):
			mask[cell.y * width + cell.x] = 1
	for source in [grid.occupied, grid.roads]:
		for cell in source:
			if grid.inside(cell) and mask[cell.y * width + cell.x] == 0:
				mask[cell.y * width + cell.x] = 2
	var last_x := width - 1
	var last_y: int = grid.height - 1
	for y in grid.height:
		var row_range: int = (y / RANGE) * columns
		for x in width:
			var at: int = y * width + x
			if grid.reach[at] != 1 or grid.footprint[at] != 1:
				continue
			var index: int = row_range + x / RANGE
			if mask[at] == 2:
				built[index] += 1
			elif mask[at] == 0 and grid.terrain[at] == "grass" \
					and (x == 0 or mask[at - 1] != 1) and (x == last_x or mask[at + 1] != 1) \
					and (y == 0 or mask[at - width] != 1) and (y == last_y or mask[at + width] != 1):
				meadow[index] += 1
	return {"trees": trees, "meadow": meadow, "built": built}

## Open grazing: grass with no tree on it or beside it.
static func _meadow(grid, cell: Vector2i) -> bool:
	if grid.terrain_at(cell) != "grass" or grid.trees.has(cell) or grid.saplings.has(cell):
		return false
	for direction in grid.DIRECTIONS:
		if grid.trees.has(cell + direction):
			return false
	return true

func _habitat_capacity(grid) -> Dictionary:
	var land := habitat(grid)
	var result := {"deer": [], "boar": []}
	for index in range_count():
		var trees: int = land.trees[index]
		var cover := trees
		for neighbour in neighbours(index):
			cover += int(land.trees[neighbour])
		var boar := maxi(0, trees - BOAR_MIN_TREES) / BOAR_TREES
		var deer := mini(int(land.meadow[index]) / DEER_MEADOW, cover / DEER_COVER)
		var built: int = land.built[index]
		var penalty := 0 if built == 0 else (MAX_HERD if built >= SETTLED_TILES else 1)
		result.boar.append(clampi(boar - penalty, 0, MAX_HERD))
		result.deer.append(clampi(deer - penalty, 0, MAX_HERD))
	return result

## The four ranges sharing an edge with this one, in a fixed order.
func neighbours(index: int) -> Array[int]:
	var result: Array[int] = []
	var x := index % columns
	var y := index / columns
	if y > 0: result.append(index - columns)
	if x > 0: result.append(index - 1)
	if x < columns - 1: result.append(index + 1)
	if y < rows - 1: result.append(index + columns)
	return result

## Once every BREED_TICKS, herds change from their previous numbers, so the
## order ranges are visited in does not matter:
## - over capacity: one animal leaves for a neighbouring range with room, or dies;
## - at least a pair and under capacity: one is born;
## - fewer than a pair with room: one arrives from a neighbour holding at
##   least a pair (each neighbour sends at most one).
func update(sim) -> void:
	if sim.tick % BREED_TICKS != 0:
		return
	for species in SPECIES:
		var room: Array = capacity(sim.grid, species)
		var before: Array = herds[species].duplicate()
		var after: Array = before.duplicate()
		var sent: Dictionary = {}
		for index in range_count():
			var count: int = before[index]
			var limit: int = room[index]
			if count > limit:
				after[index] -= 1
				for neighbour in neighbours(index):
					if int(after[neighbour]) < int(room[neighbour]) and int(before[neighbour]) <= int(room[neighbour]):
						after[neighbour] += 1
						break
			elif count >= 2 and count < limit:
				after[index] += 1
			elif count < limit:
				for neighbour in neighbours(index):
					if int(before[neighbour]) >= 2 and not sent.has(neighbour) and int(after[neighbour]) >= 2:
						sent[neighbour] = true
						after[neighbour] -= 1
						after[index] += 1
						break
		herds[species] = after

## The best quarry within `radius` tiles of a point: the range holding the most
## animals, then the nearest, then the lowest index. Its species is the one
## with more animals there, deer first on a tie. Empty when nothing is in reach.
func quarry(from: Vector2, radius: int) -> Dictionary:
	var best := {}
	var best_count := 0
	var best_distance := 0.0
	for index in range_count():
		var distance := from.distance_to(centre(index))
		if distance > radius:
			continue
		var count := int(herds.deer[index]) + int(herds.boar[index])
		if count == 0:
			continue
		if best.is_empty() or count > best_count or (count == best_count and distance < best_distance):
			best = {"range": index, "species": "deer" if int(herds.deer[index]) >= int(herds.boar[index]) else "boar"}
			best_count = count
			best_distance = distance
	return best

## Removes one animal; false if the range has none of that species.
func take(index: int, species: String) -> bool:
	if index < 0 or index >= range_count() or int(herds[species][index]) < 1:
		return false
	herds[species][index] -= 1
	return true

## A hunter's lodge works like a woodcutter: its workers hunt the best quarry
## within its work_radius, and each kill fills its output with meat. With no
## game in reach it waits, and says so.
static func hunt(sim, building) -> void:
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
	var target: Dictionary = sim.wildlife.quarry(from, int(row.work_radius))
	if target.is_empty():
		building.status = "no game nearby"
		building.progress = 0
		return
	building.status = "hunting " + NAMES[target.species]
	building.progress += 1
	if building.progress < int(row.cycle_ticks):
		return
	building.progress = 0
	sim.wildlife.take(int(target.range), target.species)
	for good in row.outputs:
		building.output.add(good, int(row.outputs[good]))
		sim.produced[good] = int(sim.produced.get(good, 0)) + int(row.outputs[good])

func snapshot() -> Dictionary:
	var state := {}
	for species in SPECIES:
		state[species] = herds[species].duplicate()
	return state

## Restores herds saved for a grid of the same size; false if malformed.
func restore(state) -> bool:
	if not state is Dictionary or state.size() != SPECIES.size():
		return false
	var restored := {}
	for species in SPECIES:
		var counts = state.get(species)
		if not counts is Array or counts.size() != range_count():
			return false
		var list: Array = []
		for value in counts:
			if not (value is int or value is float) or value != int(value) or value < 0 or value > MAX_HERD:
				return false
			list.append(int(value))
		restored[species] = list
	herds = restored
	return true
