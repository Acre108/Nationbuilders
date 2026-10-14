extends RefCounted
## Forestry is a deterministic local land job. Carriers still collect the logs.
const MATURITY_TICKS := 600

static func work(sim, building) -> void:
	var row: Dictionary = building.definition
	var cutting: bool = row.forest_action == "cut"
	if not building.staffed:
		building.status = "no workers" if building.workers_enabled else "workers stopped"
		_release(building)
		return
	if not building.output.fits(row.outputs):
		building.status = sim.output_status(building)
		_release(building)
		return
	var cell: Vector2i = building.work_cell
	var usable: bool = sim.grid.trees.has(cell) if cutting else sim.grid.can_plant(cell)
	if not usable or sim.grid.occupied.has(cell) or sim.grid.roads.has(cell):
		_release(building)
		building.work_cell = _search(sim,building,cutting)
		cell = building.work_cell
	if cell.x < 0:
		building.status = "no mature trees nearby" if cutting else "no planting space nearby"
		return
	building.status = "working"
	building.progress += 1
	if building.progress < int(row.cycle_ticks): return
	if cutting:
		sim.grid.clear_tree(cell,true)
		for good in row.outputs:
			building.output.add(good,int(row.outputs[good]))
			sim.produced[good] = int(sim.produced.get(good,0))+int(row.outputs[good])
	else:
		sim.grid.plant_tree(cell,sim.tick+MATURITY_TICKS)
	_release(building)

static func _release(building) -> void:
	building.progress = 0
	building.work_cell = Vector2i(-1,-1)

## A failed search is not repeated until the land, roads, buildings or another
## worker's claimed site changes: only those can change its answer.
static func _search(sim, building, cutting: bool) -> Vector2i:
	var claims: Array[Vector2i] = []
	for other in sim.buildings.values():
		if other != building and other.work_cell.x >= 0:
			claims.append(other.work_cell)
	var key := [sim.grid.revision, sim.grid.forest_revision, claims]
	if sim._forestry_misses.get(building.uid) == key:
		return Vector2i(-1,-1)
	var site := _find_site(sim,building,cutting,claims)
	if site.x < 0:
		sim._forestry_misses[building.uid] = key
	else:
		sim._forestry_misses.erase(building.uid)
	return site

static func _find_site(sim, building, cutting: bool, claims: Array[Vector2i]) -> Vector2i:
	var claimed: Dictionary = {}
	for cell in claims:
		claimed[cell] = true
	# Flood over walkable land, beginning at the building's perimeter. Water,
	# other buildings, cliffs and the village boundary block forestry workers.
	var frontier: Array[Vector2i] = building.cells()
	var distance: Dictionary = {}
	for cell in frontier: distance[cell] = 0
	var index := 0
	var planting_site := Vector2i(-1,-1)
	while index < frontier.size():
		var cell := frontier[index]
		index += 1
		var suitable: bool = sim.grid.trees.has(cell) if cutting else sim.grid.can_plant(cell)
		if suitable and not sim.grid.occupied.has(cell) and not sim.grid.roads.has(cell) and not claimed.has(cell):
			if cutting or sim.grid.stumps.has(cell): return cell
			if planting_site.x < 0: planting_site = cell
		if int(distance[cell]) >= int(building.definition.work_radius): continue
		for direction in sim.grid.DIRECTIONS:
			var neighbour: Vector2i = cell+direction
			if distance.has(neighbour) or not sim.grid.in_reach(neighbour) or not sim.grid.passable(cell,neighbour): continue
			if sim.grid.terrain_at(neighbour) not in ["grass","forest"] or sim.grid.occupied.has(neighbour): continue
			distance[neighbour] = int(distance[cell])+1
			frontier.append(neighbour)
	return planting_site
