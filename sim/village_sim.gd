extends RefCounted
const ContentDB = preload("res://sim/content_db.gd")
const Grid = preload("res://sim/grid.gd")
const Sites = preload("res://sim/world/sites.gd")
const SitePackage = preload("res://sim/world/site_package.gd")
const Building = preload("res://sim/building.gd")
const Carrier = preload("res://sim/carrier.gd")
const Storage = preload("res://sim/storage.gd")
const SeededRNG = preload("res://sim/rng.gd")
const Needs = preload("res://sim/needs.gd")
const Forestry = preload("res://sim/forestry.gd")
const Economy = preload("res://sim/economy.gd")
const TICKS_PER_SECOND := 10
const CARRIER_STEP_TICKS := 2
## Carriers keep each house pantry stocked for this many consumption cycles.
const PANTRY_CYCLES := 2
## Households are paid from the payroll every payday; see economy.gd.
const PAYDAY_TICKS := 200
var db
var rng
var site
var grid
var needs = Needs.new()
var economy = Economy.new()
var buildings: Dictionary = {}
var carriers: Array = []
var reserve = Storage.new(300)
var tick := 0
var unlocked_tier := 1
var idle_workers := 0
## Silver. The treasury is the player's; the payroll waits for payday.
var treasury := Economy.FOUNDING_TREASURY
var payroll := 0
var tax_percent := Economy.DEFAULT_TAX_PERCENT
var taxes_collected := 0
var next_uid := 1
var next_carrier_uid := 1
var produced: Dictionary = {}
var consumed: Dictionary = {}
var destroyed: Dictionary = {}
var events: Array[String] = []
var last_error := ""
var valid := false

## Without a site package the run uses the default 100x100 coastal village.
func _init(seed_value: int = 73, content = null, site_package = null) -> void:
	db = content if content != null else ContentDB.new()
	valid = db.load_directory() if content == null else db.errors.is_empty()
	rng = SeededRNG.new(seed_value)
	site = site_package if site_package != null else Sites.first_bread(rng)
	var site_error: String = site.error()
	if not site_error.is_empty():
		last_error = site_error
		valid = false
		site = SitePackage.new()
	grid = Grid.new(site)
	reserve.add("logs", 100)
	reserve.add("berries", 36)
	if valid:
		economy.setup(self)

func placement_error(building_id: String, cell: Vector2i, rotation_quarters: int = 0) -> String:
	if not valid:
		return "Content is invalid"
	if not db.buildings.has(building_id):
		return "Unknown building id: " + building_id
	var row: Dictionary = db.buildings[building_id]
	if int(row.unlock_tier) > unlocked_tier:
		return "Requires %s (satisfy a homestead)" % db.tiers[int(row.unlock_tier)].name
	var base_level: int = grid.level_at(cell)
	var footprint := Building.rotated_footprint(row, rotation_quarters)
	for y in footprint.y:
		for x in footprint.x:
			var tile := cell + Vector2i(x, y)
			if not grid.inside(tile):
				return "Outside the map"
			if not grid.in_reach(tile):
				return "Beyond the village lands"
			if grid.occupied.has(tile) or grid.roads.has(tile):
				return "Tile is occupied"
			if grid.terrain_at(tile) not in row.terrain:
				return "Cannot build on " + grid.terrain_at(tile)
			# Roads climb ramps; buildings need one flat level.
			if row.kind != "road":
				if grid.is_ramp(tile):
					return "Cannot build on a slope"
				if grid.level_at(tile) != base_level:
					return "Ground is not level"
	for good in row.cost:
		if stock(good) < int(row.cost[good]):
			return "Need %d %s" % [int(row.cost[good]), good]
	var price_due: int = economy.construction_price(self, row)
	if treasury < price_due:
		return "Treasury needs " + Economy.format(price_due)
	return ""

func place(building_id: String, cell: Vector2i, rotation_quarters: int = 0) -> bool:
	if building_id == "road":
		return place_road([cell])
	last_error = placement_error(building_id, cell, rotation_quarters)
	if not last_error.is_empty():
		return false
	var row: Dictionary = db.buildings[building_id]
	var capital: int = economy.capital(self, row)
	_pay(row.cost)
	var building = Building.new(next_uid, row, cell, rotation_quarters)
	# The treasury gives the new building its working money.
	building.silver = capital
	treasury -= capital
	next_uid += 1
	buildings[building.uid] = building
	for tile in building.cells():
		grid.occupied[tile] = building.uid
		grid.clear_tree(tile)
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
	# Consecutive cells of one stroke must be walkable, so an L never jumps a cliff.
	for index in range(1, cells.size()):
		var step_cells: Vector2i = cells[index] - cells[index - 1]
		if absi(step_cells.x) + absi(step_cells.y) == 1 and not grid.passable(cells[index - 1], cells[index]):
			last_error = "Cliff in the way"
			return false
	for tile in cells:
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
		grid.clear_tree(tile)
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
	# A demolished building's silver returns to the treasury.
	treasury += building.silver
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

## Stops or restarts a building's workers. Stopped workers return to the pool.
func set_workers_enabled(uid: int, enabled: bool) -> bool:
	last_error = ""
	var building = buildings.get(uid)
	if building == null:
		last_error = "Unknown building"
		return false
	if int(building.definition.workers) == 0:
		last_error = "%s has no workers" % building.definition.name
		return false
	building.workers_enabled = enabled
	return true

func step(ticks: int = 1) -> void:
	if not valid:
		push_error("Cannot step invalid content")
		return
	for iteration in maxi(ticks, 0):
		tick += 1
		grid.grow_trees(tick)
		var workers := workforce()
		for building in buildings.values():
			var required := int(building.definition.workers)
			building.staffed = building.workers_enabled and required <= workers
			if building.staffed:
				workers -= required
			if building.definition.kind == "producer":
				_produce(building)
			elif building.definition.kind == "storehouse":
				building.status = "connected" if not grid.access(building).is_empty() else "no road"
		idle_workers = workers
		for carrier in carriers:
			_update_carrier(carrier)
		for building in buildings.values():
			if building.definition.kind == "house":
				needs.update(self, building)
		if tick % PAYDAY_TICKS == 0:
			economy.payday(self)

## Sets the share of household wages taken into the treasury at payday.
func set_tax_percent(percent: int) -> bool:
	last_error = ""
	if percent < 0 or percent > 100:
		last_error = "Tax must be between 0 and 100 percent"
		return false
	tax_percent = percent
	return true

## Unit price in silver.
func price(good: String) -> int:
	return int(economy.prices.get(good, 0))

func spendable(building) -> int:
	return economy.spendable(self, building)

## How many of one input a workshop keeps on hand before carriers stop bringing more.
func input_buffer(row: Dictionary, good: String) -> int:
	var recipe_total := 0
	for amount in row.inputs.values():
		recipe_total += int(amount)
	return maxi(1, int(row.input_capacity) / maxi(1, recipe_total)) * int(row.inputs[good])

func _produce(building) -> void:
	var row: Dictionary = building.definition
	if row.has("forest_action"):
		Forestry.work(self,building)
		return
	if not building.staffed:
		building.status = "no workers" if building.workers_enabled else "workers stopped"
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
			# The receiver pays the seller on delivery; spendable() reserved the silver.
			economy.settle(self, target, int(carrier.job.get("seller", -1)), good)
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
		carrier.job = {"source":-1,"source_slot":"output","target":carrier.owner,"target_slot":"inventory","good":carrier.cargo,"seller":carrier.job.get("seller",-1)}

func _find_job(carrier, home) -> Dictionary:
	var rows: Array = buildings.values()
	# Rotate tie order deterministically to prevent a well starving other pickups.
	var offset := tick % maxi(1, rows.size())
	var ordered: Array = rows.slice(offset) + rows.slice(0, offset)
	# Villagers eat first: house pantries are stocked before workshop inputs.
	for target in ordered:
		if target.definition.kind != "house" or grid.route_between(home, target).is_empty():
			continue
		for good in db.tiers[target.tier].consumption:
			if _wants(target, good, _pantry_target(target, good)):
				var job := _closest_supply_job(carrier, ordered, target, good)
				if not job.is_empty():
					return job
	for target in ordered:
		if target.definition.kind != "producer" or not target.workers_enabled or grid.route_between(home, target).is_empty():
			continue
		for good in target.definition.inputs:
			if _wants(target, good, input_buffer(target.definition, good)):
				var job := _closest_supply_job(carrier, ordered, target, good)
				if not job.is_empty():
					return job
	for source in ordered:
		# Pantry goods the house's tier no longer eats go back to storage.
		if source.definition.kind == "house":
			for good in source.input.items:
				if not db.tiers[source.tier].consumption.has(good):
					var job := _try_job(carrier, source, "input", home, "inventory", good)
					if not job.is_empty():
						return job
		for good in source.output.items:
			var job := _try_job(carrier, source, "output", home, "inventory", good)
			if not job.is_empty():
				return job
	return {}

func _wants(target, good: String, limit: int) -> bool:
	if target.input.count(good) + _reserved(target.uid, "input", good, false) >= limit:
		return false
	return target.input.total() + _reserved(target.uid, "input", "", false) < target.input.capacity

func _pantry_target(house, good: String) -> int:
	var consumption: Dictionary = db.tiers[house.tier].consumption
	var amount := int(consumption[good])
	return maxi(amount, mini(amount * PANTRY_CYCLES, house.input.capacity / maxi(1, consumption.size())))

## Every delivery comes from the closest supply by road: a storehouse's stock or
## a producer's finished output. Equal distances keep the rotated order.
func _closest_supply_job(carrier, ordered: Array, target, good: String) -> Dictionary:
	var candidates: Array = []
	for source in ordered:
		var slot := ""
		if source.definition.kind == "storehouse":
			slot = "inventory"
		elif source.definition.kind == "producer":
			slot = "output"
		if slot.is_empty() or source == target or _slot(source, slot).count(good) - _reserved(source.uid, slot, good, true) < 1:
			continue
		var route: Array[Vector2i] = grid.route_between(source, target)
		if not route.is_empty():
			candidates.append([route.size(), candidates.size(), source, slot])
	candidates.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for entry in candidates:
		var job := _try_job(carrier, entry[2], entry[3], target, "input", good)
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
	if spendable(target) < price(good):
		return {}
	return {"source":source.uid,"source_slot":source_slot,"target":target.uid,"target_slot":target_slot,"good":good,"seller":source.uid}

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
		# Founding supplies are free; the treasury buys the rest from storehouses.
		for building in buildings.values():
			amount = mini(remaining, building.inventory.count(good))
			building.inventory.take(good, amount)
			remaining -= amount
			building.silver += amount * price(good)
			treasury -= amount * price(good)
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
	return {"tick":tick,"rng":rng.state,"unlocked_tier":unlocked_tier,"idle_workers":idle_workers,"treasury":treasury,"payroll":payroll,"tax_percent":tax_percent,"taxes_collected":taxes_collected,"next_uid":next_uid,"next_carrier_uid":next_carrier_uid,"width":grid.width,"height":grid.height,"terrain":grid.terrain.duplicate(),"levels":Array(grid.levels),"ramps":Array(grid.ramps),"reach":Array(grid.reach),"deposits":grid.deposits.duplicate(),"roads":road_cells,"revision":grid.revision,"forest_revision":grid.forest_revision,"trees":_forest_cells(grid.trees),"saplings":_forest_cells(grid.saplings),"stumps":_forest_cells(grid.stumps),"buildings":building_states,"carriers":carrier_states,"reserve":reserve.items.duplicate(),"produced":produced.duplicate(),"consumed":consumed.duplicate(),"destroyed":destroyed.duplicate(),"events":events.duplicate(),"site":_site_snapshot()}

func _site_snapshot() -> Dictionary:
	var state := {}
	for property in site.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value = site.get(property.name)
			if not value is Object: state[property.name] = value
	return state.duplicate(true)

## Restore authoritative state, then derive occupancy and caches. Returns null
## for invalid input; it never partially mutates an existing simulation.
static func from_snapshot(state: Dictionary, content = null):
	if not state.get("site") is Dictionary: return null
	var restored_site = SitePackage.new()
	var fields := {}
	for property in restored_site.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			fields[property.name] = restored_site.get(property.name)
	if state.site.size() != fields.size(): return null
	for key in fields:
		if not state.site.has(key) or typeof(fields[key]) != typeof(state.site[key]): return null
		restored_site.set(key, state.site[key])
	if not restored_site.error().is_empty(): return null
	var result = load("res://sim/village_sim.gd").new(0, content, restored_site)
	if not result.valid: return null
	var expected: Dictionary = result.snapshot()
	if state.size() != expected.size(): return null
	for key in expected:
		if not state.has(key): return null
		if expected[key] is int:
			if not Building._whole(state[key]) or (key != "rng" and state[key] < 0): return null
		elif typeof(state[key]) != typeof(expected[key]): return null
		if key in ["tick","unlocked_tier","idle_workers","treasury","payroll","tax_percent","taxes_collected","next_uid","next_carrier_uid"]:
			result.set(key, int(state[key]))
	if not result.db.tiers.has(result.unlocked_tier) or result.tax_percent > 100: return null
	if state.width != restored_site.width or state.height != restored_site.height: return null
	var count: int = state.width * state.height
	for key in ["terrain","deposits","levels","ramps","reach"]:
		if state[key].size() != count: return null
	for index in count:
		if state.terrain[index] not in result.db.TERRAINS and state.terrain[index] != "void": return null
		if not state.deposits[index] is String: return null
		for key in ["levels","ramps","reach"]:
			if not Building._whole(state[key][index]) or state[key][index] < 0: return null
		if state.ramps[index] > 1 or state.reach[index] > 1: return null
	result.grid.terrain.assign(state.terrain)
	result.grid.deposits.assign(state.deposits)
	result.grid.levels = PackedInt32Array(state.levels)
	result.grid.ramps = PackedByteArray(state.ramps)
	result.grid.reach = PackedByteArray(state.reach)
	result.grid.revision = int(state.revision)
	result.grid.forest_revision = int(state.forest_revision)
	result.grid.roads.clear()
	for point in state.roads:
		if not Building._point(point): return null
		var cell := Vector2i(int(point[0]),int(point[1]))
		if not result.grid.in_reach(cell): return null
		result.grid.roads[cell] = true
	for key in ["trees","saplings","stumps"]:
		var forest := {}
		for entry in state[key]:
			if not entry is Array or entry.size() != 3 or not Building._point(entry.slice(0,2)): return null
			var cell := Vector2i(int(entry[0]),int(entry[1]))
			if not result.grid.inside(cell): return null
			if key == "saplings" and (not Building._whole(entry[2]) or entry[2] < 0): return null
			if key != "saplings" and not entry[2] is bool: return null
			forest[cell] = int(entry[2]) if key == "saplings" else entry[2]
		result.grid.set(key, forest)
	result.reserve = Storage.from_snapshot(state.reserve, 300)
	if result.reserve == null: return null
	for key in ["produced","consumed","destroyed"]:
		for good in state[key]:
			if not result.db.goods.has(good) or not Building._whole(state[key][good]) or state[key][good] < 0: return null
		result.set(key, state[key].duplicate(true))
	for event in state.events:
		if not event is String: return null
	result.events.assign(state.events)
	result.rng.state = int(state.rng)
	for entry in state.buildings:
		if not entry is Dictionary: return null
		var building = Building.from_snapshot(entry, result.db)
		if building == null or result.buildings.has(building.uid) or building.uid >= result.next_uid: return null
		for cell in building.cells():
			if not result.grid.in_reach(cell) or result.grid.occupied.has(cell) or result.grid.roads.has(cell): return null
			result.grid.occupied[cell] = building.uid
		result.buildings[building.uid] = building
	var carrier_ids := {}
	for entry in state.carriers:
		if not entry is Dictionary: return null
		var carrier = Carrier.from_snapshot(entry)
		if carrier == null or not result.buildings.has(carrier.owner) or carrier_ids.has(carrier.uid) or carrier.uid >= result.next_carrier_uid: return null
		if not result.grid.in_reach(carrier.cell): return null
		for point in carrier.path:
			if not result.grid.in_reach(point): return null
		if not carrier.cargo.is_empty() and not result.db.goods.has(carrier.cargo): return null
		if not carrier.job.is_empty():
			for key in ["source","source_slot","target","target_slot","good","seller"]:
				if not carrier.job.has(key): return null
			if not result.buildings.has(carrier.job.source) or not result.buildings.has(carrier.job.target) or not result.db.goods.has(carrier.job.good): return null
			if carrier.job.source_slot not in ["input","output","inventory"] or carrier.job.target_slot not in ["input","output","inventory"]: return null
		carrier_ids[carrier.uid] = true
		result.carriers.append(carrier)
	return result

func _forest_cells(cells: Dictionary) -> Array:
	var result: Array = []
	for cell in cells:
		result.append([cell.x,cell.y,cells[cell]])
	return result
