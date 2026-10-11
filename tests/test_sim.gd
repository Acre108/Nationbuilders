extends RefCounted
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")

func run(t) -> void:
	_chain(t)
	_determinism(t)
	_placement(t)
	_disconnection(t)
	_capacity_and_workers(t)
	_generic_recipe(t)
	_road_repair(t)
	_nearest_store(t)

func _chain(t) -> void:
	var sim = Sim.new(73)
	t.check(Scenario.starter(sim), "Scripted layout places via public commands")
	t.check(not sim.place("mill", Vector2i(16,18)), "Mill is locked before Villagers")
	var upgrade_tick := 0
	for index in 1000:
		sim.step(1)
		if sim.unlocked_tier == 2:
			upgrade_tick = sim.tick
			break
	t.check(upgrade_tick > 0, "Water and berries upgrade a Settler house")
	t.check(Scenario.complete_chain(sim), "Upgrade unlocks mill and bakery")
	var first_bread := 0
	var carried_goods: Dictionary = {}
	for index in 3000:
		sim.step(1)
		for carrier in sim.carriers:
			if not carrier.cargo.is_empty():
				carried_goods[carrier.cargo] = true
		if first_bread == 0 and int(sim.produced.get("bread", 0)) > 0:
			first_bread = sim.tick
	t.check(first_bread > 0 and first_bread <= 1800, "Bread produced within 3 simulated minutes")
	t.check(sim.stock("bread") > 0, "Bread physically delivered to storehouse")
	for good in ["wheat","flour","bread","water","logs"]:
		t.check(carried_goods.has(good), "Carriers visibly transport " + good)
	var house = _find(sim, "house")
	t.check(house.tier == 2 and house.needs_ok, "Bread, water and logs sustain Villagers")
	_conservation(t, sim, "running chain")
	print("CHAIN: upgrade at tick %d; first bread at tick %d; stored bread %d" % [upgrade_tick, first_bread, sim.stock("bread")])
	# Delete a working destination while trips are active: cargo returns home.
	t.check(sim.demolish(_find(sim, "mill").cell), "Demolish destination during live logistics")
	sim.step(500)
	_conservation(t, sim, "demolition and cargo recovery")
	for building in sim.buildings.values():
		t.check(building.input.total() <= building.input.capacity and building.output.total() <= building.output.capacity, "Local slots remain bounded")

func _determinism(t) -> void:
	var a = Sim.new(919)
	var b = Sim.new(919)
	Scenario.starter(a)
	Scenario.starter(b)
	a.step(400)
	for index in 40:
		b.step(10)
	Scenario.complete_chain(a)
	Scenario.complete_chain(b)
	a.step(600)
	b.step(600)
	t.check(JSON.stringify(a.snapshot()) == JSON.stringify(b.snapshot()), "Seed + commands are deterministic across tick batch sizes")
	t.check(Sim.new(920).grid.terrain != a.grid.terrain, "Different seeds change wilderness")
	var state: Dictionary = a.snapshot()
	state.buildings.clear()
	state.terrain.clear()
	t.check(not a.buildings.is_empty() and a.grid.terrain.size() == 1600, "Snapshot cannot mutate live sim")

func _placement(t) -> void:
	var sim = Sim.new()
	t.check(not sim.place("unknown", Vector2i(15,15)), "Reject unknown building id")
	t.check(not sim.place("house", Vector2i(39,39)), "Reject out-of-bounds footprint")
	t.check(not sim.place("house", Vector2i(35,20)), "Reject water placement")
	t.check(sim.place("house", Vector2i(15,15)), "Place full house footprint")
	t.check(not sim.place("well", Vector2i(16,16)), "Reject footprint overlap")
	var before: Dictionary = sim.snapshot()
	t.check(not sim.place_road([Vector2i(14,15),Vector2i(15,15)]), "Reject mixed valid/invalid road batch")
	t.check(JSON.stringify(before) == JSON.stringify(sim.snapshot()), "Invalid road command is atomic")
	t.check(sim.place_road([Vector2i(14,15),Vector2i(14,16)]), "Place contiguous road")
	t.check(not sim.place("well", Vector2i(14,15)), "Cannot build on road")
	t.check(sim.grid.astar(Vector2i(14,15),Vector2i(14,16)).size() == 2, "A* follows road neighbors")
	t.check(sim.grid.astar(Vector2i(14,15),Vector2i(13,15)).is_empty(), "A* never crosses non-road tiles")
	t.check(sim.demolish(Vector2i(16,16)) and not sim.grid.occupied.has(Vector2i(15,15)), "Demolish any footprint cell clears entire building")

func _disconnection(t) -> void:
	var sim = Sim.new()
	Scenario.starter(sim)
	sim.place("house",Vector2i(26,21))
	sim.step(350)
	var house = sim.buildings[sim.grid.occupied[Vector2i(26,21)]]
	t.check(house.tier == 2, "House starts disconnection check as Villagers")
	# A disconnected isolated house must not consume remote stock.
	for attempt in 100:
		for tile in sim.grid.access(house):
			sim.demolish(tile)
		if sim.grid.access(house).is_empty():
			break
		sim.step(1)
	sim.step(950)
	t.check(house.tier == 1 and house.status.contains("road"), "Unreachable house downgrades after timeout")
	var disconnected = Sim.new()
	disconnected.place("storehouse",Vector2i(17,21))
	disconnected.place("farm",Vector2i(12,18))
	disconnected.step(600)
	t.check(disconnected.stock("wheat") == 0, "No roads means no invisible deliveries")
	t.check(_find(disconnected,"farm").status == "output full", "Disconnected producer blocks at output capacity")

func _capacity_and_workers(t) -> void:
	var sim = Sim.new()
	for cell in [Vector2i(12,15),Vector2i(16,15),Vector2i(22,15)]:
		sim.place("farm",cell)
	sim.step(300)
	var farms: Array = sim.buildings.values()
	t.check(farms[0].output.total() == 6, "Output slot capacity is six")
	t.check(farms[2].status == "no workers" and farms[2].output.total() == 0, "Insufficient workforce stops production")
	t.check(sim.grid.deposits.size() == 1600 and "timber" in sim.grid.deposits and "fertile_soil" in sim.grid.deposits, "Map has one populated deposit layer")

func _generic_recipe(t) -> void:
	var db = preload("res://sim/content_db.gd").new()
	db.load_directory()
	var rows: Array = db.buildings.values().duplicate(true)
	var custom: Dictionary = db.buildings.farm.duplicate(true)
	custom.id = "test_orchard"
	custom.outputs = {"berries":1}
	rows.append(custom)
	t.check(db.validate(db.goods.values().duplicate(true), rows, db.tiers.values().duplicate(true)), "New producer definition validates without sim changes")
	var sim = Sim.new(73,db)
	t.check(sim.place("test_orchard",Vector2i(14,15)), "Generic placement supports new content id")
	sim.step(100)
	t.check(int(sim.produced.get("berries",0)) > 0, "Generic production supports new JSON recipe")

func _road_repair(t) -> void:
	var sim = Sim.new()
	var road: Array[Vector2i] = []
	for x in range(12,27):
		road.append(Vector2i(x,20))
	sim.place_road(road)
	sim.place("storehouse",Vector2i(12,21))
	sim.place("farm",Vector2i(24,21))
	sim.step(80)
	var removed := false
	for attempt in 100:
		if sim.demolish(Vector2i(18,20)):
			removed = true
			break
		sim.step(1)
	t.check(removed,"Remove an unoccupied bridge during live trips")
	sim.step(200)
	var stock_before: int = sim.stock("wheat")
	sim.step(200)
	t.check(sim.stock("wheat") == stock_before,"Cut road halts new deliveries across the gap")
	t.check(sim.place_road([Vector2i(18,20)]),"Reconnect the broken road")
	sim.step(300)
	t.check(sim.stock("wheat") > stock_before,"Stranded carriers resume after road repair")
	_conservation(t,sim,"road repair")

func _nearest_store(t) -> void:
	var sim = Sim.new()
	var road: Array[Vector2i] = []
	for x in range(12,27):
		road.append(Vector2i(x,20))
	sim.place_road(road)
	sim.place("storehouse",Vector2i(12,21))
	sim.place("storehouse",Vector2i(24,21))
	sim.place("house",Vector2i(20,21))
	var house = _find(sim,"house")
	t.check(sim.nearest_store(house).cell == Vector2i(24,21),"House chooses shortest road distance to storehouse")
	sim.demolish(Vector2i(23,20))
	t.check(sim.nearest_store(house).cell == Vector2i(12,21),"House ignores nearer but unreachable storehouse")

func _find(sim, id: String):
	for building in sim.buildings.values():
		if building.definition.id == id:
			return building
	return null

func _conservation(t, sim, label: String) -> void:
	for good in sim.db.goods:
		var actual: int = sim.reserve.count(good)
		for building in sim.buildings.values():
			actual += building.input.count(good) + building.output.count(good) + building.inventory.count(good)
		for carrier in sim.carriers:
			if carrier.cargo == good:
				actual += 1
		var initial := 100 if good == "logs" else (36 if good == "berries" else 0)
		var expected := initial + int(sim.produced.get(good,0)) - int(sim.consumed.get(good,0)) - int(sim.destroyed.get(good,0))
		t.check(actual == expected, "%s conserves %s: %d == %d" % [label,good,actual,expected])
