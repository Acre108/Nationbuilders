extends RefCounted
## Storage limits, long-run stability and the logistics caches.
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const SimTests = preload("res://tests/test_sim.gd")

func run(t) -> void:
	_store_limit(t)
	# An hour of simulation takes about ten seconds, so only the full tier runs it.
	if t.get("quick") != true:
		_long_run(t)

func _store_limit(t) -> void:
	var db = preload("res://sim/content_db.gd").new()
	db.load_directory()
	var limit := int(db.buildings.storehouse.good_limit)
	t.check(limit * db.goods.size() <= int(db.buildings.storehouse.storage_capacity), "Every good keeps room for its limit in a storehouse")
	var rows: Array = db.buildings.values().duplicate(true)
	for row in rows:
		if row.id == "storehouse": row.good_limit = 31
	t.check(not db.validate(db.goods.values(), rows, db.tiers.values()) and "good_limit" in "; ".join(db.errors), "Content rejects limits that could crowd out a good")
	for row in rows:
		if row.id == "storehouse": row.good_limit = 0
	t.check(not db.validate(db.goods.values(), rows, db.tiers.values()), "Content rejects a zero storehouse limit")
	var sim = _fixture()
	var road: Array[Vector2i] = []
	for x in range(12,27):
		road.append(Vector2i(x,20))
	sim.place_road(road)
	sim.place("storehouse",Vector2i(12,21))
	sim.place("well",Vector2i(18,21))
	var store = _find(sim,"storehouse")
	var well = _find(sim,"well")
	sim.step(2500)
	t.check(store.inventory.count("water") == limit, "Carriers stop hauling a good once the storehouse holds its limit: %d" % store.inventory.count("water"))
	t.check(well.output.total() == well.output.capacity and well.status == "storehouse has enough water", "The producer then fills its output and says why")
	t.check(store.inventory.count("berries") == 36, "Founding stock above the limit stays stored")
	store.inventory.take("water", 1)
	store.inventory.add("flour", store.inventory.capacity - store.inventory.total())
	sim.step(1)
	t.check(well.status == "storehouse full", "A producer blocked by a full storehouse says so")

## The starter village with the full chain, a second house and a forester
## keeps both houses at Villagers for an hour without the storehouse clogging.
## The storehouse is on low pay, the lowest markup, so households' budgets
## are less likely to decide the result: this run checks logistics, and the
## treasury balance has its own probe.
func _long_run(t) -> void:
	var sim = Sim.new(73)
	t.check(Scenario.starter(sim), "Long run: starter layout")
	sim.set_pay(_find(sim,"storehouse").uid, 0)
	sim.set_keep_service_reserve(false)
	while sim.unlocked_tier < 2 and sim.tick < 3000:
		sim.step(1)
	var shift: Vector2i = Scenario.offset(sim)
	t.check(Scenario.complete_chain(sim) and sim.place("house",Vector2i(21,23) + shift) and sim.place("forester",Vector2i(26,21) + shift), "Long run: chain, second house and forester")
	var store = _find(sim,"storehouse")
	var limit := int(store.definition.good_limit)
	var demoted_minutes := 0
	var crowded_minutes := 0
	var lowest_logs := 999
	var logs_at_20 := 0
	var started: int = sim.tick
	var clock := Time.get_ticks_msec()
	for minute in range(1,61):
		sim.step(started + minute * 600 - sim.tick)
		if minute < 3:
			continue
		for building in sim.buildings.values():
			if building.definition.kind == "house" and building.tier < 2:
				demoted_minutes += 1
				break
		# A full storehouse is fine once every good holds its limit; it must
		# never be full while some good is below it.
		if store.inventory.total() >= store.inventory.capacity:
			for good in sim.db.goods:
				if store.inventory.count(good) < limit:
					crowded_minutes += 1
					break
		if minute >= 10:
			lowest_logs = mini(lowest_logs, sim.stock("logs"))
		if minute == 20:
			logs_at_20 = sim.stock("logs")
		if minute % 15 == 0:
			_caches_agree(t, sim, "minute %d" % minute)
	print("LONG RUN: 60 min in %d ms; store %d/%d; bread %d; logs %d (lowest %d)" % [Time.get_ticks_msec() - clock, store.inventory.total(), store.inventory.capacity, sim.stock("bread"), sim.stock("logs"), lowest_logs])
	t.check(demoted_minutes == 0, "Both houses stay Villagers for an hour: %d minutes below" % demoted_minutes)
	t.check(crowded_minutes == 0, "No good is crowded out of the storehouse: %d crowded minutes" % crowded_minutes)
	# Logs sit at the storehouse's per-good limit, where one log in a carrier's
	# arms moves the count by one: allow that, not a drain.
	t.check(lowest_logs >= limit / 2 and sim.stock("logs") >= logs_at_20 - 1, "Construction logs hold steady: lowest %d, %d at minute 20, %d at the end" % [lowest_logs, logs_at_20, sim.stock("logs")])
	SimTests.new()._conservation(t, sim, "hour-long run")

## Cached routes and reservations must equal a fresh search and a full scan.
func _caches_agree(t, sim, label: String) -> void:
	var rows: Array = sim.buildings.values()
	var routes_match := true
	for a in rows:
		for b in rows:
			var route: Array[Vector2i] = sim.grid.route_between(a, b)
			if sim.grid.distance(a, b) != (-1 if route.is_empty() else route.size()):
				routes_match = false
		for carrier in sim.carriers:
			if sim.grid.reaches(carrier.cell, a) == sim.grid.route_to(carrier.cell, sim.grid.access(a)).is_empty():
				routes_match = false
	t.check(routes_match, label + ": cached road distances match A* routes")
	var reservations_match := true
	for building in rows:
		for slot in ["input","output","inventory"]:
			for good in [""] + sim.db.goods.keys():
				for outgoing in [false, true]:
					if sim._reserved(building.uid, slot, good, outgoing) != _scan(sim, building.uid, slot, good, outgoing):
						reservations_match = false
	t.check(reservations_match, label + ": indexed reservations match a scan of every carrier")

func _scan(sim, uid: int, slot: String, good: String, outgoing: bool) -> int:
	var amount := 0
	for carrier in sim.carriers:
		var job: Dictionary = carrier.job
		if job.is_empty() or (outgoing and carrier.stage != "pickup"):
			continue
		if job.get("source" if outgoing else "target") == uid and job.get("source_slot" if outgoing else "target_slot") == slot and (good.is_empty() or job.good == good):
			amount += 1
	return amount

func _find(sim, id: String):
	for building in sim.buildings.values():
		if building.definition.id == id:
			return building
	return null

func _fixture():
	var rng = preload("res://sim/rng.gd").new(73)
	return Sim.new(73, null, preload("res://sim/world/sites.gd").first_bread(rng, Vector2i(40,40)))
