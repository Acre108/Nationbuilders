extends RefCounted
const ContentDB = preload("res://sim/content_db.gd")
const Grid = preload("res://sim/grid.gd")
const Building = preload("res://sim/building.gd")
const Carrier = preload("res://sim/carrier.gd")
const Storage = preload("res://sim/storage.gd")
const SeededRNG = preload("res://sim/rng.gd")
const Needs = preload("res://sim/needs.gd")
const TICKS_PER_SECOND := 10
const CARRIER_STEP_TICKS := 2
var db
var rng
var grid
var needs = Needs.new()
var buildings: Dictionary = {}
var carriers: Array = []
var reserve = Storage.new(300)
var tick := 0
var unlocked_tier := 1
var next_uid := 1
var next_carrier_uid := 1
var produced: Dictionary = {}
var consumed: Dictionary = {}
var destroyed: Dictionary = {}
var events: Array[String] = []
var last_error := ""
var valid := false

func _init(seed_value: int = 73, content = null) -> void:
	db = content if content != null else ContentDB.new()
	valid = db.load_directory() if content == null else db.errors.is_empty()
	rng = SeededRNG.new(seed_value)
	grid = Grid.new(rng)
	reserve.add("logs", 100)
	reserve.add("berries", 36)

func placement_error(building_id: String, cell: Vector2i) -> String:
	if not valid:
		return "Content is invalid"
	if not db.buildings.has(building_id):
		return "Unknown building id: " + building_id
	var row: Dictionary = db.buildings[building_id]
	if int(row.unlock_tier) > unlocked_tier:
		return "Requires %s (satisfy a homestead)" % db.tiers[int(row.unlock_tier)].name
	for y in int(row.footprint[1]):
		for x in int(row.footprint[0]):
			var tile := cell + Vector2i(x, y)
			if not grid.inside(tile):
				return "Outside the map"
			if grid.occupied.has(tile) or grid.roads.has(tile):
				return "Tile is occupied"
			if grid.terrain_at(tile) not in row.terrain:
				return "Cannot build on " + grid.terrain_at(tile)
	for good in row.cost:
		if stock(good) < int(row.cost[good]):
			return "Need %d %s" % [int(row.cost[good]), good]
	return ""

func place(building_id: String, cell: Vector2i) -> bool:
	if building_id == "road":
		return place_road([cell])
	last_error = placement_error(building_id, cell)
	if not last_error.is_empty():
		return false
	var row: Dictionary = db.buildings[building_id]
	_pay(row.cost)
	var building = Building.new(next_uid, row, cell)
	next_uid += 1
	buildings[building.uid] = building
	for tile in building.cells():
		grid.occupied[tile] = building.uid
	grid.changed()
	if row.kind == "storehouse":
		for good in reserve.items.keys():
			var amount := mini(reserve.count(good), building.inventory.capacity - building.inventory.total())
			building.inventory.add(good, amount)
			reserve.take(good, amount)
		for index in int(row.carriers):
			carriers.append(Carrier.new(next_carrier_uid, building.uid, cell))
			next_carrier_uid += 1
	return true

func place_road(cells: Array) -> bool:
	last_error = ""
	if not valid or not db.buildings.has("road"):
		last_error = "Missing road definition"
		return false
	var unique: Array[Vector2i] = []
	for tile in cells:
		if not tile is Vector2i:
			last_error = "Road cells must be Vector2i"
			return false
		if grid.roads.has(tile) or tile in unique:
			continue
		last_error = placement_error("road", tile)
		if not last_error.is_empty():
			return false
		unique.append(tile)
	var cost: Dictionary = db.buildings.road.cost.duplicate()
	for good in cost:
		cost[good] = int(cost[good]) * unique.size()
		if stock(good) < cost[good]:
			last_error = "Not enough " + good
			return false
	_pay(cost)
	for tile in unique:
		grid.roads[tile] = true
	if not unique.is_empty():
		grid.changed()
	return true

func demolish(cell: Vector2i) -> bool:
	last_error = ""
	# An occupied road cannot disappear beneath a walking carrier.
	if grid.roads.has(cell):
		for carrier in carriers:
			if carrier.cell == cell:
				last_error = "A carrier is on this road"
				return false
		grid.roads.erase(cell)
		grid.changed()
		return true
	if not grid.occupied.has(cell):
		last_error = "Nothing to demolish"
		return false
	var building = buildings[grid.occupied[cell]]
	for storage in [building.input, building.output, building.inventory]:
		for good in storage.items:
			destroyed[good] = int(destroyed.get(good, 0)) + storage.count(good)
	for tile in building.cells():
		grid.occupied.erase(tile)
	buildings.erase(building.uid)
	for carrier in carriers.duplicate():
		if carrier.owner == building.uid:
			if not carrier.cargo.is_empty():
				destroyed[carrier.cargo] = int(destroyed.get(carrier.cargo, 0)) + 1
			carriers.erase(carrier)
	grid.changed()
	return true

func step(ticks: int = 1) -> void:
	if not valid:
		push_error("Cannot step invalid content")
		return
	for iteration in maxi(ticks, 0):
		tick += 1
		var workers := workforce()
		for building in buildings.values():
			var required := int(building.definition.workers)
			building.staffed = required <= workers
			if building.staffed:
				workers -= required
			if building.definition.kind == "producer":
				_produce(building)
			elif building.definition.kind == "storehouse":
				building.status = "connected" if not grid.access(building).is_empty() else "no road"
		for carrier in carriers:
			_update_carrier(carrier)
		for building in buildings.values():
			if building.definition.kind == "house":
				needs.update(self, building)

func _produce(building) -> void:
	var row: Dictionary = building.definition
	if not building.staffed:
		building.status = "no workers"
		return
	if not building.output.fits(row.outputs):
		building.status = "output full"
		return
	if building.progress == 0:
		for good in row.inputs:
			if building.input.count(good) < int(row.inputs[good]):
				building.status = "missing input " + good
				return
		for good in row.inputs:
			building.input.take(good, int(row.inputs[good]))
			consumed[good] = int(consumed.get(good, 0)) + int(row.inputs[good])
	building.status = "working"
	building.progress += 1
	if building.progress >= int(row.cycle_ticks):
		for good in row.outputs:
			building.output.add(good, int(row.outputs[good]))
			produced[good] = int(produced.get(good, 0)) + int(row.outputs[good])
		building.progress = 0

func _update_carrier(carrier) -> void:
	var home = buildings.get(carrier.owner)
	if home == null:
		return
	if carrier.stage == "idle":
		# New carriers enter at their own storehouse's road frontage only.
		if not grid.roads.has(carrier.cell):
			var entries: Array[Vector2i] = grid.access(home)
			if entries.is_empty():
				return
			carrier.cell = entries[0]
		carrier.job = _find_job(carrier, home)
		if carrier.job.is_empty():
			return
		carrier.stage = "pickup"
		carrier.route_revision = -1
	var target = buildings.get(carrier.job.get("source")) if carrier.stage == "pickup" else buildings.get(carrier.job.get("target"))
	if target == null:
		_cancel_job(carrier)
		return
	if carrier.route_revision != grid.revision or carrier.path.is_empty():
		carrier.path = grid.route_to(carrier.cell, grid.access(target))
		carrier.route_revision = grid.revision
		if not carrier.path.is_empty():
			carrier.path.pop_front()
	if carrier.cell not in grid.access(target):
		if carrier.path.is_empty():
			# Cargo stays with its carrier until reconnection. Empty jobs release reservations.
			if carrier.cargo.is_empty():
				_cancel_job(carrier)
			return
		carrier.move_ticks += 1
		if carrier.move_ticks >= CARRIER_STEP_TICKS:
			carrier.move_ticks = 0
			carrier.cell = carrier.path.pop_front()
		return
	var good: String = carrier.job.good
	if carrier.stage == "pickup":
		var source_slot = _slot(target, carrier.job.source_slot)
		if not source_slot.take(good):
			_cancel_job(carrier)
			return
		carrier.cargo = good
		carrier.stage = "delivery"
		carrier.path.clear()
		carrier.route_revision = -1
	else:
		if _slot(target, carrier.job.target_slot).add(good):
			carrier.cargo = ""
			carrier.stage = "idle"
			carrier.job = {}
			carrier.path.clear()

func _cancel_job(carrier) -> void:
	carrier.path.clear()
	carrier.route_revision = -1
	if carrier.cargo.is_empty():
		carrier.job = {}
		carrier.stage = "idle"
	else:
		carrier.stage = "delivery"
		carrier.job = {"source":-1,"source_slot":"output","target":carrier.owner,"target_slot":"inventory","good":carrier.cargo}

func _find_job(carrier, home) -> Dictionary:
	var rows: Array = buildings.values()
	# Rotate tie order deterministically to prevent a well starving other pickups.
	var offset := tick % maxi(1, rows.size())
	var ordered: Array = rows.slice(offset) + rows.slice(0, offset)
	for target in ordered:
		if target.definition.kind != "producer" or grid.route_between(home, target).is_empty():
			continue
		for good in target.definition.inputs:
			var recipe_total := 0
			for amount in target.definition.inputs.values():
				recipe_total += int(amount)
			var buffer_limit := maxi(1, target.input.capacity / maxi(1, recipe_total)) * int(target.definition.inputs[good])
			if target.input.count(good) + _reserved(target.uid, "input", good, false) >= buffer_limit:
				continue
			if target.input.total() + _reserved(target.uid, "input", "", false) >= target.input.capacity:
				continue
			for source in ordered:
				var slot := "inventory" if source.definition.kind == "storehouse" else "output"
				var job := _try_job(carrier, source, slot, target, "input", good)
				if not job.is_empty():
					return job
	for source in ordered:
		for good in source.output.items:
			var job := _try_job(carrier, source, "output", home, "inventory", good)
			if not job.is_empty():
				return job
	return {}

func _try_job(carrier, source, source_slot: String, target, target_slot: String, good: String) -> Dictionary:
	if source == target:
		return {}
	var stock_slot = _slot(source, source_slot)
	var destination = _slot(target, target_slot)
	if stock_slot.count(good) - _reserved(source.uid, source_slot, good, true) < 1:
		return {}
	if destination.total() + _reserved(target.uid, target_slot, "", false) >= destination.capacity:
		return {}
	if grid.route_to(carrier.cell, grid.access(source)).is_empty() or grid.route_between(source, target).is_empty():
		return {}
	return {"source":source.uid,"source_slot":source_slot,"target":target.uid,"target_slot":target_slot,"good":good}

func _reserved(uid: int, slot: String, good: String, outgoing: bool) -> int:
	var amount := 0
	for carrier in carriers:
		if carrier.job.is_empty() or (outgoing and carrier.stage != "pickup"):
			continue
		var job: Dictionary = carrier.job
		if job.get("source" if outgoing else "target") == uid and job.get("source_slot" if outgoing else "target_slot") == slot and (good.is_empty() or job.good == good):
			amount += 1
	return amount

func _slot(building, slot: String):
	return building.inventory if slot == "inventory" else (building.input if slot == "input" else building.output)

func nearest_store(building):
	var nearest = null
	var distance := 999999
	for candidate in buildings.values():
		if candidate.definition.kind != "storehouse":
			continue
		var route: Array[Vector2i] = grid.route_between(building, candidate)
		if not route.is_empty() and route.size() < distance:
			nearest = candidate
			distance = route.size()
	return nearest

func workforce() -> int:
	var result := 4 # Founding adults; additional workers are counted per house.
	for building in buildings.values():
		if building.definition.kind == "house":
			result += int(db.tiers[building.tier].workers_per_house)
	return result

func stock(good: String) -> int:
	var total: int = reserve.count(good)
	for building in buildings.values():
		total += building.inventory.count(good)
	return total

func _pay(cost: Dictionary) -> void:
	for good in cost:
		var remaining := int(cost[good])
		var amount := mini(remaining, reserve.count(good))
		reserve.take(good, amount)
		remaining -= amount
		for building in buildings.values():
			amount = mini(remaining, building.inventory.count(good))
			building.inventory.take(good, amount)
			remaining -= amount
		consumed[good] = int(consumed.get(good, 0)) + int(cost[good])

func snapshot() -> Dictionary:
	var building_states: Array = []
	var carrier_states: Array = []
	var road_cells: Array = []
	for building in buildings.values():
		building_states.append(building.snapshot())
	for carrier in carriers:
		carrier_states.append(carrier.snapshot())
	for cell in grid.roads:
		road_cells.append([cell.x, cell.y])
	return {"tick":tick,"rng":rng.state,"unlocked_tier":unlocked_tier,"next_uid":next_uid,"next_carrier_uid":next_carrier_uid,"terrain":grid.terrain.duplicate(),"deposits":grid.deposits.duplicate(),"roads":road_cells,"revision":grid.revision,"buildings":building_states,"carriers":carrier_states,"reserve":reserve.items.duplicate(),"produced":produced.duplicate(),"consumed":consumed.duplicate(),"destroyed":destroyed.duplicate(),"events":events.duplicate()}
