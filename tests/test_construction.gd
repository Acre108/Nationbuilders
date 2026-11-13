extends RefCounted
## Construction sites (docs/CONSTRUCTION.md): placed buildings wait for their
## materials, are built, then open.
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const Building = preload("res://sim/building.gd")
const Economy = preload("res://sim/economy.gd")
const SimTests = preload("res://tests/test_sim.gd")

func run(t) -> void:
	_site_lifecycle(t)
	_promised_stock(t)
	_cancel(t)
	_snapshots(t)
	_storehouse_site(t)

## A starter village whose player placements go up as sites.
func _village():
	var sim = Sim.new(73)
	Scenario.starter(sim)
	sim.construction_sites = true
	return sim

## The first free cell, nearest the founding spot, where this building fits
## beside a road. With any_stock, a spot that only lacks materials will do.
func _spot(sim, id: String, any_stock: bool = false) -> Vector2i:
	var centre: Vector2i = sim.site.founding_spot
	var best := Vector2i(-1,-1)
	var best_distance := 999999
	for y in range(centre.y - 12, centre.y + 13):
		for x in range(centre.x - 12, centre.x + 13):
			var cell := Vector2i(x,y)
			var error: String = sim.placement_error(id, cell)
			if not error.is_empty() and not (any_stock and error.begins_with("Need")):
				continue
			# The grid caches frontage by uid, so each probe needs its own.
			if sim.grid.access(Building.new(1000000 + y * 1000 + x, sim.db.buildings[id], cell)).is_empty():
				continue
			var distance: int = absi(x - centre.x) + absi(y - centre.y)
			if distance < best_distance:
				best = cell
				best_distance = distance
	return best

func _site_lifecycle(t) -> void:
	var sim = _village()
	var cell := _spot(sim, "well")
	var logs_before: int = sim.stock("logs")
	var treasury_before: int = sim.treasury
	var buildings_before: int = sim.buildings.size()
	t.check(sim.place("well", cell), "A well can be placed as a site: %s" % sim.last_error)
	var uid: int = sim.grid.occupied.get(cell, -1)
	t.check(sim.sites.has(uid) and not sim.buildings.has(uid), "A placed building is a construction site, not yet a building")
	t.check(sim.buildings.size() == buildings_before, "The village does not count the site as a building")
	var site = sim.sites[uid]
	t.check(sim.stock("logs") == logs_before, "Materials stay in the storehouse until carried")
	t.check(sim.available("logs") == logs_before - 3, "Its materials are promised to the site: %d available" % sim.available("logs"))
	t.check(treasury_before - sim.treasury == site.silver and site.silver >= 3 * sim.price("logs"), "The treasury funds the site's purse to buy its materials")
	t.check(not sim.place("road", cell), "The site holds its tiles")
	SimTests.new()._conservation(t, sim, "a new site")
	var statuses := {}
	var carried := false
	var finished_tick := -1
	for index in 1500:
		sim.step(1)
		statuses[sim.structure(uid).status] = true
		for carrier in sim.carriers:
			if int(carrier.job.get("target", -1)) == uid and carrier.cargo == "logs":
				carried = true
		if sim.buildings.has(uid):
			finished_tick = sim.tick
			break
	t.check(carried, "Carriers bring logs to the site")
	t.check(statuses.has("waiting for materials") and statuses.has("building"), "A site waits for materials, then builds: %s" % str(statuses.keys()))
	t.check(finished_tick > 0, "The site becomes a well")
	t.check(not sim.sites.has(uid) and sim.buildings[uid].definition.id == "well", "A finished site is a building")
	t.check(sim.buildings[uid].materials.total() == 0, "A finished building holds no materials")
	t.check(sim.events.any(func(e): return e.begins_with("Well finished")), "Finishing a building is an event")
	# A site off the road network says so.
	var lonely := Vector2i(-1,-1)
	for y in range(sim.site.founding_spot.y - 12, sim.site.founding_spot.y + 13):
		for x in range(sim.site.founding_spot.x - 12, sim.site.founding_spot.x + 13):
			if lonely.x < 0 and sim.placement_error("well", Vector2i(x,y)).is_empty() and sim.grid.access(Building.new(2000000 + y * 1000 + x, sim.db.buildings.well, Vector2i(x,y))).is_empty():
				lonely = Vector2i(x,y)
	sim.place("well", lonely)
	sim.step(1)
	t.check(sim.sites[sim.grid.occupied[lonely]].status == "no road", "A site no storehouse can reach says it has no road")
	sim.demolish(lonely)
	sim.step(300)
	t.check(sim.buildings[uid].staffed and int(sim.produced.get("water", 0)) > 0, "The finished well is staffed and draws water")
	SimTests.new()._conservation(t, sim, "a finished site")

## Placement checks stock not yet promised to sites, so two sites cannot both
## count on the same logs.
func _promised_stock(t) -> void:
	var sim = _village()
	var logs: int = sim.stock("logs")
	var placed := 0
	for index in 60:
		var cell := _spot(sim, "well")
		if cell.x < 0 or not sim.place("well", cell):
			break
		placed += 1
	t.check(placed == logs / 3, "Sites take only unpromised logs: %d wells from %d logs" % [placed, logs])
	var cell := _spot(sim, "well", true)
	t.check(cell.x >= 0 and sim.placement_error("well", cell).begins_with("Need"), "Then placement asks for more logs: %s" % sim.placement_error("well", cell))
	# Oldest first: the first site finishes before the last gets any logs.
	var first: int = sim.sites.keys().min()
	var last: int = sim.sites.keys().max()
	var lowest := 0
	for index in 2000:
		sim.step(1)
		lowest = mini(lowest, sim.available("logs"))
		if sim.buildings.has(first):
			break
	t.check(sim.buildings.has(first), "The oldest site finishes first")
	t.check(lowest == 0, "Pantries and workshops never take logs promised to sites (lowest unpromised %d)" % lowest)
	# Villagers burn logs; a long wait proves their pantries leave sites' logs alone.
	for index in 1500:
		sim.step(1)
		lowest = mini(lowest, sim.available("logs"))
	t.check(lowest == 0 and sim.unlocked_tier >= 2, "Even once houses burn logs for fuel (lowest %d)" % lowest)
	# A rich faction buys the most plentiful goods, but never promised logs.
	var buyer: String = sim.factions.coffers.keys()[0]
	_find_kind(sim, "producer").owner = buyer
	sim.factions.coffers[buyer] = int(sim.factions.coffers[buyer]) + 100000
	var money_in: int = 100000
	sim.outside_money += money_in
	if not sim.factions.period.has(buyer):
		sim.factions.period[buyer] = {"purchases": 0}
	sim.factions._purchase(sim, buyer, 100000)
	t.check(sim.available("logs") >= 0, "Factions do not buy logs promised to sites (%d unpromised)" % sim.available("logs"))
	t.check(sim.sites.has(last) and sim.sites[last].materials.total() == 0, "Newer sites wait their turn")
	SimTests.new()._conservation(t, sim, "a queue of sites")

func _find_kind(sim, kind: String):
	for building in sim.buildings.values():
		if building.definition.kind == kind:
			return building
	return null

func _cancel(t) -> void:
	var sim = _village()
	var cell := _spot(sim, "storehouse")
	var treasury_before: int = sim.treasury
	t.check(sim.place("storehouse", cell), "A storehouse site is placed")
	var uid: int = sim.grid.occupied[cell]
	for index in 400:
		sim.step(1)
		if sim.sites[uid].materials.total() >= 4:
			break
	var delivered: int = sim.sites[uid].materials.total()
	t.check(delivered >= 4, "Some logs reach the site: %d" % delivered)
	var stock_before: int = sim.stock("logs")
	t.check(sim.demolish(cell), "A site can be cleared")
	t.check(not sim.sites.has(uid) and not sim.grid.occupied.has(cell), "Clearing frees its tiles")
	t.check(sim.stock("logs") == stock_before + delivered, "Delivered logs go back to the storehouse")
	# Only the logs delivered were bought; the rest of the purse, and the
	# storehouse's working money, come back.
	t.check(sim.treasury == treasury_before - delivered * sim.price("logs"), "The unspent purse returns to the treasury: %d of %d" % [sim.treasury, treasury_before])
	sim.step(200)
	SimTests.new()._conservation(t, sim, "a cleared site")

func _snapshots(t) -> void:
	var sim = _village()
	sim.place("house", _spot(sim, "house"))
	sim.step(40)
	var saved: Dictionary = sim.snapshot()
	t.check(saved.sites.size() == 1 and saved.construction_sites == true, "A save keeps its sites")
	var restored = Sim.from_snapshot(saved)
	t.check(restored != null and restored.snapshot() == saved, "A save with a site round-trips")
	if restored != null:
		sim.step(500)
		restored.step(500)
		t.check(restored.snapshot() == sim.snapshot(), "A restored site builds exactly as the original")
	# A save taken while a carrier hauls materials to a site loads and plays on
	# exactly as the original (an autosave can land at any tick).
	var hauling = _village()
	hauling.place("storehouse", _spot(hauling, "storehouse"))
	var in_flight := false
	for index in 600:
		hauling.step(1)
		for carrier in hauling.carriers:
			if carrier.job.get("target_slot") == "materials":
				in_flight = true
		if in_flight:
			break
	t.check(in_flight, "A carrier takes a job delivering materials to a site")
	var mid_haul: Dictionary = hauling.snapshot()
	var resumed = Sim.from_snapshot(mid_haul)
	t.check(resumed != null and resumed.snapshot() == mid_haul, "A save with materials in transit round-trips")
	if resumed != null:
		hauling.step(500)
		resumed.step(500)
		t.check(resumed.snapshot() == hauling.snapshot(), "A village restored mid-haul builds exactly as the original")
	# Saves from before construction sites load as played villages.
	var old: Dictionary = Sim.new(73).snapshot()
	old.erase("sites")
	old.erase("construction_sites")
	for entry in old.buildings:
		entry.erase("materials")
	var migrated = Sim.from_snapshot(old)
	t.check(migrated != null and migrated.construction_sites and migrated.sites.is_empty(), "An older save loads, building with sites from now on")

## A storehouse site is no storehouse: no carriers, no stock, until finished.
func _storehouse_site(t) -> void:
	var sim = _village()
	var carriers_before: int = sim.carriers.size()
	var cell := _spot(sim, "storehouse")
	sim.place("storehouse", cell)
	var uid: int = sim.grid.occupied[cell]
	t.check(sim.carriers.size() == carriers_before, "A storehouse site has no carriers yet")
	for index in 3000:
		sim.step(1)
		if sim.buildings.has(uid):
			break
	t.check(sim.buildings.has(uid), "The storehouse is finished")
	t.check(sim.carriers.size() == carriers_before + int(sim.db.buildings.storehouse.carriers), "A finished storehouse brings its carriers")
	t.check(sim.buildings[uid].silver >= Economy.STOREHOUSE_CAPITAL, "Its leftover purse is its trading money")
	SimTests.new()._conservation(t, sim, "a finished storehouse")
