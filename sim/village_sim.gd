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
const Labour = preload("res://sim/labour.gd")
const Economy = preload("res://sim/economy.gd")
const Factions = preload("res://sim/factions.gd")
const Wildlife = preload("res://sim/wildlife.gd")
const Forage = preload("res://sim/forage.gd")
## Game pace at 1x: every cycle, meal, payday and deadline is counted in ticks.
const TICKS_PER_SECOND := 5
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
## The factions present and their coffers; see factions.gd.
var factions = Factions.new()
## Deer and boar in the land around the village; see wildlife.gd.
var wildlife = Wildlife.new()
## Wild berry bushes in the woods; see forage.gd.
var forage = Forage.new()
var buildings: Dictionary = {}
## Construction sites by uid (docs/CONSTRUCTION.md): placed buildings waiting
## for their materials or being built. A site holds its tiles but is not yet in
## `buildings`, so nothing else in the village sees it until it is finished.
var sites: Dictionary = {}
## Whether place() lays out a construction site (play) or finishes the building
## at once (the founding layout, and fixtures testing other systems).
var construction_sites := false
## Building ticks per unit of material, once every unit has arrived.
const BUILD_TICKS_PER_MATERIAL := 15
const MIN_BUILD_TICKS := 30
var carriers: Array = []
## Founding supplies, kept outside any storehouse until the first is built.
const RESERVE_CAPACITY := 400
var reserve = Storage.new(RESERVE_CAPACITY)
var tick := 0
var unlocked_tier := 1
var idle_workers := 0
## Silver. The treasury is the player's; the payroll waits for payday. The two
## reserves are parts of the treasury the player has set aside: public pay
## draws on its reserve first and construction on the capital reserve, and
## neither touches the other's.
var treasury := Economy.FOUNDING_TREASURY
var public_reserve := 0
var capital_reserve := 0
var payroll := 0
## Silver brought from outside by arriving factions' endowments. Treasury,
## payroll, buildings' silver and faction coffers sum to FOUNDING_TREASURY
## plus this.
var outside_money := 0
var tax_percent := Economy.DEFAULT_TAX_PERCENT
## Top the public pay reserve up to a few paydays of services at each payday.
## On by default since 16 Oct 2026, so the reserves need no tending.
var keep_service_reserve := true
var taxes_collected := 0
## Worker-paydays public workers went unpaid, village-wide. Kept for the trade
## union's contentedness once factions exist.
var public_frustration := 0
## Treasury income and spending since the last payday, then per payday.
var period: Dictionary = Economy.blank_period()
var ledger: Array = []
var next_uid := 1
var next_carrier_uid := 1
var produced: Dictionary = {}
var consumed: Dictionary = {}
var destroyed: Dictionary = {}
## Goods households have eaten, for the food balance (food_report.gd). A
## derived running total: not saved, so it restarts with a loaded village.
var _eaten: Dictionary = {}
var events: Array[String] = []
var last_error := ""
var valid := false
## Derived from carriers' jobs and rebuilt when they change; see _reserved().
var _jobs_dirty := true
var _jobs_version := 0
var _incoming: Dictionary = {}
var _outgoing: Dictionary = {}
var _jobs_to: Dictionary = {}
## Job searches that found nothing since jobs last changed, by home storehouse
## and road network. Repeating one would find nothing again.
var _idle_misses: Dictionary = {}
var _idle_misses_version := -1
## Forestry buildings whose last search found no site; see forestry.gd.
var _forestry_misses: Dictionary = {}

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
	wildlife.setup(grid)
	forage.setup(grid)
	reserve.add("logs", 100)
	reserve.add("berries", 36)
	if valid:
		economy.setup(self)
		factions.found(self)

func placement_error(building_id: String, cell: Vector2i, rotation_quarters: int = 0) -> String:
	if not valid:
		return "Content is invalid"
	if not db.buildings.has(building_id):
		return "Unknown building id: " + building_id
	var row: Dictionary = db.buildings[building_id]
	if row.get("reserved", false):
		return "%s cannot be built yet" % row.name
	if int(row.unlock_tier) > unlocked_tier:
		return "Requires %s (satisfy a cottage)" % db.tiers[int(row.unlock_tier)].name
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
	if row.has("adjacent_terrain") and not touches_terrain(cell, footprint, row.adjacent_terrain):
		return "Must touch water" if row.adjacent_terrain.all(func(t): return t in ContentDB.WATER_TERRAINS) else "Must touch " + " or ".join(row.adjacent_terrain)
	for good in row.cost:
		if available(good) < int(row.cost[good]):
			return "Need %d %s" % [int(row.cost[good]), good]
	var price_due: int = economy.construction_price(self, row)
	if Economy.construction_funds(self) < price_due:
		return _treasury_shortfall(price_due)
	return ""

## A house's class (docs/PLAN-job-classes.md): its row's `class` if present,
## else its tier's. Computed here, not in labour.gd, which calls this.
func house_class(house) -> String:
	return str(house.definition.get("class", db.tiers[house.tier].get("class", "")))

## The adults and children of a house's family, drawn once per house from its
## row's "family" ranges (labour.gd). At an inn every adult is a lodger.
func family_adults(house) -> int:
	return Labour.family_adults(self, house)

func family_children(house) -> int:
	return Labour.family_children(self, house)

## Whether a footprint at this cell shares an edge with one of these terrains,
## as a fisher's hut must with water.
func touches_terrain(cell: Vector2i, footprint: Vector2i, terrains: Array) -> bool:
	for y in range(-1, footprint.y + 1):
		for x in range(-1, footprint.x + 1):
			var inside_x := x >= 0 and x < footprint.x
			var inside_y := y >= 0 and y < footprint.y
			# Edge neighbours only: exactly one coordinate lies outside the footprint.
			if inside_x != inside_y and grid.terrain_at(cell + Vector2i(x, y)) in terrains:
				return true
	return false

## Percent of full speed a building of this row would work at here. A field
## (`deposit` with `off_deposit_percent`) works at full speed with its whole
## footprint on its deposit, such as fertile soil, and at off_deposit_percent
## with none of it, in proportion between. Other buildings always work at 100.
func deposit_speed(row: Dictionary, cell: Vector2i, rotation_quarters: int = 0) -> int:
	if not row.has("off_deposit_percent"):
		return 100
	var footprint := Building.rotated_footprint(row, rotation_quarters)
	var on := 0
	for y in footprint.y:
		for x in footprint.x:
			var tile := cell + Vector2i(x, y)
			if grid.inside(tile) and grid.deposits[tile.y * grid.width + tile.x] == row.deposit:
				on += 1
	var off := int(row.off_deposit_percent)
	return off + (100 - off) * on / maxi(1, footprint.x * footprint.y)

## Ticks a building's cycle takes, longer for a field off fertile soil.
func cycle_ticks(building) -> int:
	var row: Dictionary = building.definition
	if not row.has("off_deposit_percent"):
		return int(row.cycle_ticks)
	return ceili(float(row.cycle_ticks) * 100.0 / float(deposit_speed(row, building.cell, building.rotation_quarters)))

## Statuses of a producer at work this cycle.
const WORKING_STATUSES := ["working", "gathering wild berries"]

## How a workplace is running, for the operations overlay:
## - "down": it cannot work: no workers, workers stopped, no road, or blocked
##   (missing inputs, output or storehouse full, nothing nearby to work on);
## - "limited": it works below full capacity: low morale or poor soil slows it,
##   or a storehouse is short of carriers;
## - "ready": it can work at full capacity but is not using all of it: a
##   workshop lacks its next cycle's inputs, or a storehouse has idle carriers;
## - "full": it is working at full capacity.
## Houses follow their needs met this cycle (a stand-in until migration):
## "down" below the tier's demotion threshold, "limited" with some need
## unmet, "ready" with every need met. "" for roads and halls.
func operation(building) -> String:
	var row: Dictionary = building.definition
	match row.kind:
		"house":
			var threshold := int(db.tiers[building.tier].get("downgrade_below_happiness", 50))
			if building.happiness < threshold:
				return "down"
			return "ready" if building.happiness >= 100 else "limited"
		"storehouse":
			if not building.workers_enabled or building.crew == 0 or grid.access(building).is_empty():
				return "down"
			var total := 0
			var busy := 0
			for carrier in carriers:
				if carrier.owner == building.uid:
					total += 1
					if carrier.stage != "idle":
						busy += 1
			if building.crew < total:
				return "limited"
			return "full" if busy >= total else "ready"
		"producer":
			if not building.staffed:
				return "down"
			var status: String = building.status
			if status not in WORKING_STATUSES and not status.begins_with("hunting "):
				return "down"
			if Needs.work_speed(Needs.morale(self)) * deposit_speed(row, building.cell, building.rotation_quarters) < 100 * 100:
				return "limited"
			for good in row.inputs:
				if building.input.count(good) < int(row.inputs[good]):
					return "ready"
			return "full"
	return ""

## Construction cannot use the public pay reserve, so say when that is why.
func _treasury_shortfall(price_due: int) -> String:
	return "Treasury needs " + Economy.format(price_due) + ("" if public_reserve == 0 or treasury < price_due else " outside the public pay reserve")

func place(building_id: String, cell: Vector2i, rotation_quarters: int = 0) -> bool:
	if building_id == "road":
		return place_road([cell])
	last_error = placement_error(building_id, cell, rotation_quarters)
	if not last_error.is_empty():
		return false
	var row: Dictionary = db.buildings[building_id]
	var capital: int = economy.capital(self, row)
	# A site's purse buys the materials not taken from the founding supplies.
	var materials_due: int = economy.materials_price(self, row.cost) if construction_sites else 0
	var building = Building.new(next_uid, row, cell, rotation_quarters)
	if construction_sites:
		# Founding supplies have no storehouse to be carried from: they are on site.
		for good in row.cost:
			var amount := mini(int(row.cost[good]), reserve.count(good))
			if amount > 0:
				reserve.take(good, amount)
				building.materials.add(good, amount)
	else:
		_pay(row.cost)
	# A Master's house or an inn lives at one tier and never changes it.
	if row.has("fixed_tier"):
		building.tier = int(row.fixed_tier)
	# The treasury gives the new building its working money: a house the purse
	# its family's adults earn it, now that its family is drawn.
	if row.kind == "house":
		capital = Economy.house_grant(self, building)
	building.silver = capital + materials_due
	Economy.spend_on_construction(self, capital + materials_due)
	next_uid += 1
	for tile in building.cells():
		grid.occupied[tile] = building.uid
		grid.clear_tree(tile)
	if construction_sites:
		building.status = "waiting for materials"
		sites[building.uid] = building
		grid.changed()
		return true
	buildings[building.uid] = building
	grid.changed()
	_commission(building)
	return true

## A finished building takes up its role: a hall joins its faction, and a
## storehouse takes in the founding supplies and its carriers.
func _commission(building) -> void:
	var row: Dictionary = building.definition
	var cell: Vector2i = building.cell
	# A union hall or alehouse belongs to its faction from the start, or passes
	# to it when the faction arrives.
	if row.kind == "hall":
		building.owner = factions.hall_owner(row)
		factions.hall_placed(self, building)
	if row.kind == "storehouse":
		for good in reserve.items.keys():
			var amount := mini(reserve.count(good), building.inventory.capacity - building.inventory.total())
			building.inventory.add(good, amount)
			reserve.take(good, amount)
		for index in int(row.carriers):
			carriers.append(Carrier.new(next_carrier_uid, building.uid, cell))
			next_carrier_uid += 1

## Ticks a row takes to build once its materials are all on site.
static func build_ticks(row: Dictionary) -> int:
	return maxi(MIN_BUILD_TICKS, Building.material_count(row) * BUILD_TICKS_PER_MATERIAL)

## Units of a good a site still needs: its cost, less what is on site and on
## its way in a carrier's arms. Units a carrier is only walking to collect are
## still in stock, so they are still owed.
func site_owes(site, good: String) -> int:
	var owed: int = int(site.definition.cost.get(good, 0)) - site.materials.count(good)
	for carrier in carriers:
		if carrier.stage == "delivery" and carrier.cargo == good and int(carrier.job.get("target", -1)) == site.uid:
			owed -= 1
	return maxi(0, owed)

## Stock not yet promised to a construction site.
func available(good: String) -> int:
	var total: int = stock(good)
	for site in sites.values():
		total -= site_owes(site, good)
	return total

## Units of a good carriers are walking to collect from storehouses for
## anyone but a site: still in stock, but already taken from what is unpromised.
func _reserved_from_stores(good: String) -> int:
	var count := 0
	for carrier in carriers:
		if carrier.stage == "pickup" and carrier.job.get("good") == good and carrier.job.get("source_slot") == "inventory" and not sites.has(int(carrier.job.get("target", -1))):
			count += 1
	return count

## Whether every unit of a site's cost has arrived.
func site_supplied(site) -> bool:
	return site.materials.has_all(site.definition.cost)

## A building or a construction site, by uid; null for neither.
func structure(uid: int):
	var found = buildings.get(uid)
	return found if found != null else sites.get(uid)

## Each site waits for materials, then builds at the village's work speed, then
## opens as the finished building. Its leftover purse is the building's working
## money.
func _build_sites(working: bool) -> void:
	for site in sites.values():
		if not site_supplied(site):
			# Without a road to a storehouse no carrier can come.
			site.status = "waiting for materials" if nearest_store(site) != null else "no road"
			continue
		site.status = "building"
		if working:
			site.progress += 1
		if site.progress < build_ticks(site.definition):
			continue
		for good in site.definition.cost:
			consumed[good] = int(consumed.get(good, 0)) + int(site.definition.cost[good])
		site.materials.items.clear()
		site.progress = 0
		site.status = "idle"
		sites.erase(site.uid)
		buildings[site.uid] = site
		_commission(site)
		events.append("%s finished at tick %d" % [site.definition.name, tick])
		grid.changed()

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
		if available(good) < cost[good]:
			last_error = "Not enough " + good
			return false
	# Validate the whole stroke before paying or clearing any tree. Checking
	# individual cells alone cannot reserve the same silver for every road.
	var price_due: int = economy.materials_price(self,cost)
	if Economy.construction_funds(self) < price_due:
		last_error = _treasury_shortfall(price_due)
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
	if sites.has(grid.occupied[cell]):
		_cancel_site(sites[grid.occupied[cell]])
		return true
	var building = buildings[grid.occupied[cell]]
	for storage in [building.input, building.output, building.inventory]:
		for good in storage.items:
			destroyed[good] = int(destroyed.get(good, 0)) + storage.count(good)
	# A demolished building's silver returns to the treasury, or a faction-owned
	# workshop's or storehouse's purse to its owner. A rented house's savings
	# are the household's, not the landlord's (FACTIONS.md §3).
	if building.definition.kind != "house" and factions.present(building.owner):
		factions.credit(building.owner, building.silver, "")
	else:
		Economy.refund(self, building.silver)
	factions.lost_building(building)
	for tile in building.cells():
		grid.occupied.erase(tile)
	buildings.erase(building.uid)
	for carrier in carriers.duplicate():
		if carrier.owner == building.uid:
			if not carrier.cargo.is_empty():
				destroyed[carrier.cargo] = int(destroyed.get(carrier.cargo, 0)) + 1
			carriers.erase(carrier)
	_jobs_changed()
	grid.changed()
	return true

## Clearing a construction site returns its unspent purse to the treasury and
## its delivered materials to the nearest storehouse with room; whatever finds
## no room is lost. Carriers bringing more turn back with their loads.
func _cancel_site(site) -> void:
	Economy.refund(self, site.silver)
	site.silver = 0
	var store = nearest_store(site)
	for good in site.materials.items.keys():
		var amount: int = site.materials.count(good)
		var kept: int = 0 if store == null else mini(amount, store.inventory.capacity - store.inventory.total())
		if kept > 0:
			store.inventory.add(good, kept)
		if amount > kept:
			destroyed[good] = int(destroyed.get(good, 0)) + amount - kept
	site.materials.items.clear()
	for tile in site.cells():
		grid.occupied.erase(tile)
	sites.erase(site.uid)
	_jobs_changed()
	grid.changed()

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
	if not enabled:
		last_error = factions.forbids(self, "stop_workplace")
		if not last_error.is_empty():
			return false
	building.workers_enabled = enabled
	return true

## Sells a Crown building to a faction listed in its row's `buyers`, at
## factions.sale_price(): book value × the favour multiplier (FACTIONS.md §5.1).
## The faction pays the treasury from its coffers and becomes the owner. A
## workshop's or storehouse's purse stays in the building and now counts as the
## faction's. Services and wells are never sold.
func sell_building(uid: int, faction: String) -> bool:
	last_error = ""
	var building = buildings.get(uid)
	if building == null:
		last_error = "Unknown building"
		return false
	var row: Dictionary = building.definition
	if not factions.present(faction):
		last_error = "No %s in the village" % (db.factions[faction].name if db.factions.has(faction) else faction)
		return false
	var buyer: String = db.factions[faction].name
	if not Building.ownable(row, db):
		last_error = "%s is not for sale" % row.name
		return false
	if not building.owner.is_empty():
		last_error = "%s already belongs to the %s" % [row.name, db.factions[building.owner].name]
		return false
	if faction not in row.get("buyers", []):
		last_error = "The %s do not buy a %s" % [buyer, row.name]
		return false
	if row.kind == "house":
		last_error = factions.forbids(self, "house_sale")
		if not last_error.is_empty():
			return false
	var price_due: int = factions.sale_price(self, building, faction)
	if int(factions.coffers[faction]) < price_due:
		last_error = "The %s cannot pay %s" % [buyer, Economy.format(price_due)]
		return false
	factions.coffers[faction] = int(factions.coffers[faction]) - price_due
	treasury += price_due
	period.deals += price_due
	building.owner = faction
	building.owner_work = 0
	events.append(Factions.BUILDING_SOLD % [buyer, row.name, Economy.format(price_due), tick])
	factions.sold(self, building, faction)
	return true

## Accepts, declines or breaks a faction's deal; see factions.gd. An offer's
## id is the faction's id, and a pledge's is "<faction>:<type>".
func accept_offer(faction: String) -> bool:
	last_error = ""
	return factions.accept(self, faction)

func decline_offer(faction: String) -> bool:
	last_error = ""
	return factions.decline(self, faction)

func break_pledge(pledge: String) -> bool:
	last_error = ""
	return factions.break_pledge(self, pledge)

func step(ticks: int = 1) -> void:
	if not valid:
		push_error("Cannot step invalid content")
		return
	for iteration in maxi(ticks, 0):
		tick += 1
		# Rebuild derived reservations once per tick, in case a caller edited carriers.
		_jobs_changed()
		grid.grow_trees(tick)
		wildlife.update(self)
		forage.update(self)
		# Low village morale slows every workplace: at speed s%, workplaces
		# advance on s of every 100 ticks, spread evenly.
		var speed: int = Needs.work_speed(Needs.morale(self))
		var working: bool = (tick * speed) / 100 != ((tick - 1) * speed) / 100
		idle_workers = _staff(workforce())
		_build_sites(working)
		for building in buildings.values():
			if building.definition.kind == "producer":
				if working:
					_produce(building)
			elif building.definition.kind == "storehouse":
				building.status = "connected" if not grid.access(building).is_empty() else "no road"
		for carrier in carriers:
			_update_carrier(carrier)
		for building in buildings.values():
			if building.definition.kind == "house":
				needs.update(self, building)
		factions.update(self)
		if tick % PAYDAY_TICKS == 0:
			economy.payday(self)

## Staffs workplaces and carriers from the families, by job class and
## pay (labour.gd). Returns the workers still idle.
func _staff(_workers: int) -> int:
	return Labour.staff(self)

## Sets the share of household wages taken into the treasury at payday.
func set_tax_percent(percent: int) -> bool:
	last_error = ""
	if percent < 0 or percent > Economy.MAX_TAX_PERCENT:
		last_error = "Tax must be between 0 and %d percent" % Economy.MAX_TAX_PERCENT
		return false
	last_error = factions.forbids(self, "tax", percent)
	if not last_error.is_empty():
		return false
	tax_percent = percent
	return true

## Sets a workplace's pay (Building.LOW, NORMAL or HIGH): workers fill the
## best-paid jobs first. A storehouse's pay is its markup, which a faction's
## markup pledge may hold.
func set_pay(uid: int, level: int) -> bool:
	last_error = ""
	var building = buildings.get(uid)
	if building == null:
		last_error = "Unknown building"
		return false
	if int(building.definition.workers) == 0 and building.definition.kind != "storehouse":
		last_error = "%s has no workers" % building.definition.name
		return false
	if level < Building.LOW or level > Building.HIGH:
		last_error = "Pay must be low, normal or high"
		return false
	if building.definition.kind == "storehouse":
		last_error = factions.forbids(self, "markup", int(Economy.STORE_MARKUP[level]))
		if not last_error.is_empty():
			return false
	building.pay = level
	return true

## The storehouses' average markup, which households budget by and factions
## judge; the normal markup while there is no storehouse.
func average_markup() -> int:
	var total := 0
	var count := 0
	for building in buildings.values():
		if building.definition.kind == "storehouse":
			total += Economy.markup(building)
			count += 1
	return Economy.DEFAULT_MARKUP_PERCENT if count == 0 else roundi(float(total) / count)

## Keeps SERVICE_RESERVE_PAYDAYS of services' upkeep in the public pay
## reserve, topped up from free gold at each payday.
func set_keep_service_reserve(enabled: bool) -> bool:
	last_error = ""
	keep_service_reserve = enabled
	return true

## Moves up to `amount` silver of free treasury gold into a reserve ("public"
## or "capital"); a negative amount moves it back. Fails only if nothing moves.
func transfer_reserve(pot: String, amount: int) -> bool:
	last_error = ""
	if pot not in ["public","capital"]:
		last_error = "Unknown reserve: " + pot
		return false
	var key := pot + "_reserve"
	var held: int = get(key)
	var moved := mini(amount, Economy.free_gold(self)) if amount > 0 else -mini(-amount, held)
	if moved == 0:
		last_error = "No free gold to set aside" if amount > 0 else "Nothing in that reserve"
		return false
	set(key, held + moved)
	return true

## Unit price in silver.
func price(good: String) -> int:
	return int(economy.prices.get(good, 0))

## What this buyer pays this seller per unit: the chain price, plus the
## storehouse markup when a household buys from storage.
func sale_price(buyer, seller, good: String) -> int:
	return economy.sale_price(self, buyer, seller, good)

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
	if row.get("gathers", false):
		Forage.gather(self,building)
		return
	if row.get("hunts", false):
		Wildlife.hunt(self,building)
		return
	if row.has("forest_action"):
		Forestry.work(self,building)
		return
	if not building.staffed:
		building.status = "no workers" if building.workers_enabled else "workers stopped"
		return
	if not building.output.fits(row.outputs):
		building.status = output_status(building)
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
	if building.progress >= cycle_ticks(building):
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
		# Carriers are jobs: one without a worker this tick waits at home.
		if not carrier._on_shift:
			return
		# Within a tick only carriers change the village, and every change they
		# make passes through _jobs_changed(), so an unchanged search would fail again.
		if _idle_misses_version != _jobs_version:
			_idle_misses.clear()
			_idle_misses_version = _jobs_version
		var search := Vector2i(home.uid, grid.network(carrier.cell))
		var found: Dictionary = {} if _idle_misses.has(search) else _find_job(carrier, home)
		if not found.is_empty() or not carrier.job.is_empty():
			_jobs_changed()
		carrier.job = found
		if found.is_empty():
			_idle_misses[search] = true
			return
		carrier.stage = "pickup"
		carrier.route_revision = -1
	var target = buildings.get(carrier.job.get("source")) if carrier.stage == "pickup" else structure(int(carrier.job.get("target", -1)))
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
		_jobs_changed()
	else:
		if _slot(target, carrier.job.target_slot).add(good):
			# The receiver pays the seller on delivery; spendable() reserved the silver.
			economy.settle(self, target, int(carrier.job.get("seller", -1)), good)
			carrier.cargo = ""
			carrier.stage = "idle"
			carrier.job = {}
			carrier.path.clear()
			_jobs_changed()

func _cancel_job(carrier) -> void:
	_jobs_changed()
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
		if target.definition.kind != "house" or grid.distance(home, target) < 0:
			continue
		for need in db.tiers[target.tier].consumption:
			if _pantry_wants(target, need):
				var job := _closest_supply_job(carrier, ordered, target, db.need_goods(need))
				if not job.is_empty():
					return job
	# Then construction, oldest site first, so sites finish one by one.
	var queue: Array = sites.keys()
	queue.sort()
	for uid in queue:
		var site = sites[uid]
		if grid.distance(home, site) < 0:
			continue
		for good in site.definition.cost:
			if site.materials.count(good) + _reserved(site.uid, "materials", good, false) < int(site.definition.cost[good]):
				var job := _closest_supply_job(carrier, ordered, site, [good], "materials")
				if not job.is_empty():
					return job
	for target in ordered:
		if target.definition.kind != "producer" or not target.workers_enabled or grid.distance(home, target) < 0:
			continue
		for good in target.definition.inputs:
			if _wants(target, good, input_buffer(target.definition, good)):
				var job := _closest_supply_job(carrier, ordered, target, [good])
				if not job.is_empty():
					return job
	for source in ordered:
		# Pantry goods the house's tier no longer eats go back to storage.
		if source.definition.kind == "house":
			for good in source.input.items:
				if db.need_for(source.tier, good).is_empty():
					var job := _try_job(carrier, source, "input", home, "inventory", good)
					if not job.is_empty():
						return job
		for good in source.output.items:
			# Surplus stops at the storehouse's limit; the producer then fills up and waits.
			if home.inventory.count(good) + _reserved(home.uid, "inventory", good, false) >= int(home.definition.good_limit):
				continue
			var job := _try_job(carrier, source, "output", home, "inventory", good)
			if not job.is_empty():
				return job
	return {}

## Why a producer with a full output is waiting. "storehouse full" or
## "storehouse has enough <good>" when every storehouse it reaches by road
## refuses its goods; otherwise "output full".
func output_status(building) -> String:
	var enough := ""
	var refused := false
	for store in buildings.values():
		if store.definition.kind != "storehouse" or grid.distance(building, store) < 0:
			continue
		for good in building.output.items:
			if store.inventory.total() + _reserved(store.uid, "inventory", "", false) >= store.inventory.capacity:
				refused = true
			elif store.inventory.count(good) + _reserved(store.uid, "inventory", good, false) >= int(store.definition.good_limit):
				refused = true
				enough = good
			else:
				return "output full"
	if not refused:
		return "output full"
	return "storehouse has enough " + enough if not enough.is_empty() else "storehouse full"

func _wants(target, good: String, limit: int) -> bool:
	if target.input.count(good) + _reserved(target.uid, "input", good, false) >= limit:
		return false
	return target.input.total() + _reserved(target.uid, "input", "", false) < target.input.capacity

## Units of a need the pantry keeps: two cycles, capped at an equal share of
## the pantry. A category need (staple, fuel) counts all its goods together.
func _pantry_target(house, need: String) -> int:
	var consumption: Dictionary = db.tiers[house.tier].consumption
	var amount := int(consumption[need])
	return maxi(amount, mini(amount * PANTRY_CYCLES, house.input.capacity / maxi(1, consumption.size())))

## Whether carriers should bring the house more for this need: its pantry
## stock of every good meeting it, with deliveries on their way, is below target.
func _pantry_wants(house, need: String) -> bool:
	var held := 0
	for good in db.need_goods(need):
		held += house.input.count(good) + _reserved(house.uid, "input", good, false)
	if held >= _pantry_target(house, need):
		return false
	return house.input.total() + _reserved(house.uid, "input", "", false) < house.input.capacity

## Every delivery comes from the closest supply by road, of any of the wanted
## goods: a storehouse's stock or a producer's finished output. Equal distances
## keep the rotated order, then the goods' order.
func _closest_supply_job(carrier, ordered: Array, target, wanted: Array, target_slot: String = "input") -> Dictionary:
	var candidates: Array = []
	# Nothing changes during a search, so the buyer's budget is read once.
	var budget: int = spendable(target)
	# Stored goods promised to construction sites are theirs: pantries and
	# workshops may take only what is left, as when placing took them at once.
	var unpromised: Dictionary = {}
	if target_slot != "materials" and not sites.is_empty():
		for good in wanted:
			unpromised[good] = available(good)
	for source in ordered:
		var slot := ""
		if source.definition.kind == "storehouse":
			slot = "inventory"
		elif source.definition.kind == "producer":
			slot = "output"
		if slot.is_empty() or source == target:
			continue
		var cells := -2
		for good in wanted:
			if _slot(source, slot).count(good) - _reserved(source.uid, slot, good, true) < 1:
				continue
			if slot == "inventory" and unpromised.has(good) and int(unpromised[good]) - _reserved_from_stores(good) < 1:
				continue
			if budget < sale_price(target, source, good):
				continue
			if cells == -2:
				cells = grid.distance(source, target)
			if cells > 0:
				candidates.append([cells, candidates.size(), source, slot, good])
	candidates.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for entry in candidates:
		var job := _try_job(carrier, entry[2], entry[3], target, target_slot, entry[4])
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
	if not grid.reaches(carrier.cell, source) or grid.distance(source, target) < 0:
		return {}
	if spendable(target) < sale_price(target, source, good):
		return {}
	return {"source":source.uid,"source_slot":source_slot,"target":target.uid,"target_slot":target_slot,"good":good,"seller":source.uid}

## Units promised to (or, for pickups, from) a building slot by live jobs; an
## empty good counts every good.
func _reserved(uid: int, slot: String, good: String, outgoing: bool) -> int:
	if _jobs_dirty:
		_index_jobs()
	var slots = (_outgoing if outgoing else _incoming).get(uid)
	if slots == null or not slots.has(slot):
		return 0
	return int(slots[slot].get(good, 0))

## Live jobs delivering to a building, whatever their stage.
func jobs_to(uid: int) -> Array:
	if _jobs_dirty:
		_index_jobs()
	return _jobs_to.get(uid, [])

## Call whenever a carrier's job or stage changes, or carriers come and go.
func _jobs_changed() -> void:
	_jobs_dirty = true
	_jobs_version += 1

func _index_jobs() -> void:
	_jobs_dirty = false
	_incoming.clear()
	_outgoing.clear()
	_jobs_to.clear()
	for carrier in carriers:
		var job: Dictionary = carrier.job
		if job.is_empty():
			continue
		var target := int(job.target)
		_count_job(_incoming, target, job.target_slot, job.good)
		if not _jobs_to.has(target):
			_jobs_to[target] = []
		_jobs_to[target].append(job)
		if carrier.stage == "pickup":
			_count_job(_outgoing, int(job.source), job.source_slot, job.good)

static func _count_job(index: Dictionary, uid: int, slot: String, good: String) -> void:
	if not index.has(uid):
		index[uid] = {}
	if not index[uid].has(slot):
		index[uid][slot] = {}
	var counts: Dictionary = index[uid][slot]
	counts[good] = int(counts.get(good, 0)) + 1
	counts[""] = int(counts.get("", 0)) + 1

func _slot(building, slot: String):
	match slot:
		"inventory": return building.inventory
		"input": return building.input
		"materials": return building.materials
	return building.output

func nearest_store(building):
	var nearest = null
	var distance := 999999
	for candidate in buildings.values():
		if candidate.definition.kind != "storehouse":
			continue
		var cells: int = grid.distance(building, candidate)
		if cells > 0 and cells < distance:
			nearest = candidate
			distance = cells
	return nearest

## Whether a staffed building providing this service (a chapel) is within its
## service radius of the house, by road.
func serves(house, service: String) -> bool:
	for building in buildings.values():
		var row: Dictionary = building.definition
		if row.get("provides") == service and building.staffed:
			var cells: int = grid.distance(building, house)
			if cells >= 0 and cells <= int(row.service_radius):
				return true
	return false

## Houses a service building covers, for its inspector.
func served_houses(building) -> int:
	var count := 0
	for house in buildings.values():
		if house.definition.kind == "house":
			var cells: int = grid.distance(building, house)
			if cells >= 0 and cells <= int(building.definition.get("service_radius", 0)):
				count += 1
	return count

## Every working adult: the founders, and each house's family (labour.gd).
func workforce() -> int:
	return Labour.workforce(self)

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
			Economy.spend_on_construction(self, amount * price(good))
		consumed[good] = int(consumed.get(good, 0)) + int(cost[good])

func snapshot() -> Dictionary:
	var building_states: Array = []
	var carrier_states: Array = []
	var road_cells: Array = []
	for building in buildings.values():
		building_states.append(building.snapshot())
	var site_states: Array = []
	for site in sites.values():
		site_states.append(site.snapshot())
	for carrier in carriers:
		carrier_states.append(carrier.snapshot())
	for cell in grid.roads:
		road_cells.append([cell.x, cell.y])
	return {"tick":tick,"rng":rng.state,"unlocked_tier":unlocked_tier,"idle_workers":idle_workers,"treasury":treasury,"public_reserve":public_reserve,"capital_reserve":capital_reserve,"payroll":payroll,"outside_money":outside_money,"factions":factions.snapshot(),"tax_percent":tax_percent,"keep_service_reserve":keep_service_reserve,"taxes_collected":taxes_collected,"public_frustration":public_frustration,"period":period.duplicate(),"ledger":ledger.duplicate(true),"next_uid":next_uid,"next_carrier_uid":next_carrier_uid,"width":grid.width,"height":grid.height,"terrain":grid.terrain.duplicate(),"levels":Array(grid.levels),"ramps":Array(grid.ramps),"reach":Array(grid.reach),"deposits":grid.deposits.duplicate(),"roads":road_cells,"revision":grid.revision,"forest_revision":grid.forest_revision,"trees":_forest_cells(grid.trees),"saplings":_forest_cells(grid.saplings),"stumps":_forest_cells(grid.stumps),"buildings":building_states,"sites":site_states,"construction_sites":construction_sites,"carriers":carrier_states,"reserve":reserve.items.duplicate(),"produced":produced.duplicate(),"consumed":consumed.duplicate(),"destroyed":destroyed.duplicate(),"events":events.duplicate(),"wildlife":wildlife.snapshot(),"forage":forage.snapshot(),"site":_site_snapshot()}

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
		if fields[key] is Array and not fields[key].is_same_typed(state.site[key]): return null
		var value = state.site[key]
		restored_site.set(key, value.duplicate(true) if value is Array or value is Dictionary else value)
	if not restored_site.error().is_empty(): return null
	var result = load("res://sim/village_sim.gd").new(0, content, restored_site)
	if not result.valid: return null
	var expected: Dictionary = result.snapshot()
	# The village-wide markup became each storehouse's pay on 16 Oct 2026, and
	# the ledger gained pay cuts.
	if state.has("markup_percent"):
		state = state.duplicate(true)
		state.erase("markup_percent")
		for entry in [state.get("period")] + Array(state.get("ledger", [])):
			if entry is Dictionary and entry.size() == Economy.LEDGER_KEYS.size() - 1 and not entry.has("pay_cuts"):
				entry.pay_cuts = 0
	# Construction sites arrived on 16 Oct 2026. Older saves are played villages,
	# which now build with sites.
	if not state.has("sites"):
		state = state.duplicate(true)
		state.sites = []
		state.construction_sites = true
	if state.size() != expected.size(): return null
	for key in expected:
		if not state.has(key): return null
		if expected[key] is int:
			if not Building._whole(state[key]) or (key != "rng" and state[key] < 0): return null
		elif typeof(state[key]) != typeof(expected[key]): return null
		if key in ["tick","unlocked_tier","idle_workers","treasury","public_reserve","capital_reserve","payroll","tax_percent","taxes_collected","public_frustration","outside_money","next_uid","next_carrier_uid"]:
			result.set(key, int(state[key]))
		elif key in ["keep_service_reserve","construction_sites"]:
			result.set(key, state[key])
	if not result.db.tiers.has(result.unlocked_tier) or result.tax_percent > Economy.MAX_TAX_PERCENT: return null
	if result.public_reserve + result.capital_reserve > result.treasury: return null
	if state.ledger.size() > Economy.LEDGER_PAYDAYS or not _valid_period(state.period): return null
	for entry in state.ledger:
		if not _valid_period(entry): return null
	result.period = _whole_period(state.period)
	for entry in state.ledger:
		result.ledger.append(_whole_period(entry))
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
	if not result.wildlife.restore(state.wildlife): return null
	if not result.forage.restore(state.forage, result.grid): return null
	result.reserve = Storage.from_snapshot(state.reserve, RESERVE_CAPACITY)
	if result.reserve == null: return null
	for good in result.reserve.items:
		if not result.db.goods.has(good): return null
	for key in ["produced","consumed","destroyed"]:
		for good in state[key]:
			if not result.db.goods.has(good) or not Building._whole(state[key][good]) or state[key][good] < 0: return null
		result.set(key, state[key].duplicate(true))
	for event in state.events:
		if not event is String: return null
	result.events.assign(state.events)
	if not result.factions.restore(state.factions, result.db): return null
	result.rng.state = int(state.rng)
	for entry in state.buildings:
		if not entry is Dictionary: return null
		var building = Building.from_snapshot(entry, result.db)
		if building == null or result.buildings.has(building.uid) or building.uid >= result.next_uid: return null
		# Owners and alignments name factions present in the village.
		for faction in [building.owner, building.aligned, building.pull_leader]:
			if not faction.is_empty() and not result.factions.present(faction): return null
		# Alignment and a streak are for a recruiting faction of the house's
		# class, and a streak that reached its length would already have acted.
		if not result.factions.contest_state_valid(result, building): return null
		for cell in building.cells():
			if not result.grid.in_reach(cell) or result.grid.occupied.has(cell) or result.grid.roads.has(cell): return null
			result.grid.occupied[cell] = building.uid
		result.buildings[building.uid] = building
	for entry in state.sites:
		if not entry is Dictionary: return null
		var site = Building.from_snapshot(entry, result.db)
		if site == null or result.buildings.has(site.uid) or result.sites.has(site.uid) or site.uid >= result.next_uid: return null
		# A site has no owner, family contest or wages until it is finished.
		if not site.owner.is_empty() or not site.aligned.is_empty() or not site.pull_leader.is_empty(): return null
		for cell in site.cells():
			if not result.grid.in_reach(cell) or result.grid.occupied.has(cell) or result.grid.roads.has(cell): return null
			result.grid.occupied[cell] = site.uid
		result.sites[site.uid] = site
	if not result.factions.references_valid(result): return null
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
			# A demolished endpoint can remain in a live job until its carrier's
			# next update. Return-to-store jobs deliberately use source = -1.
			# Preserve these states: _update_carrier resolves them deterministically.
			for key in ["source","target","seller"]:
				if not Building._whole(carrier.job[key]): return null
			if not result.db.goods.has(carrier.job.good): return null
			# Carriers deliver construction materials to a site's "materials" slot.
			if carrier.job.source_slot not in ["input","output","inventory"] or carrier.job.target_slot not in ["input","output","inventory","materials"]: return null
		carrier_ids[carrier.uid] = true
		result.carriers.append(carrier)
	return result

func _forest_cells(cells: Dictionary) -> Array:
	var result: Array = []
	for cell in cells:
		result.append([cell.x,cell.y,cells[cell]])
	return result

## A ledger period holds exactly the economy's ledger keys, as whole silver.
static func _valid_period(entry) -> bool:
	if not entry is Dictionary or entry.size() != Economy.LEDGER_KEYS.size(): return false
	for key in Economy.LEDGER_KEYS:
		if not Building._whole(entry.get(key)) or entry[key] < 0: return false
	return true

static func _whole_period(entry: Dictionary) -> Dictionary:
	var result := {}
	for key in Economy.LEDGER_KEYS:
		result[key] = int(entry[key])
	return result
