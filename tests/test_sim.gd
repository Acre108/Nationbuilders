extends RefCounted
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const Economy = preload("res://sim/economy.gd")

func run(t) -> void:
	_chain(t)
	_determinism(t)
	_placement(t)
	_disconnection(t)
	_capacity_and_workers(t)
	_generic_recipe(t)
	_road_repair(t)
	_nearest_store(t)
	_workforce_switch(t)
	_pantry_and_happiness(t)
	_money(t)

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
	t.check(house.happiness == 100, "A fully supplied house is fully happy")
	t.check(house.input.count("berries") == 0 and house.input.count("bread") > 0, "Carriers clear Settler food from the pantry and stock bread")
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
	t.check(not a.buildings.is_empty() and a.grid.terrain.size() == a.grid.width*a.grid.height, "Snapshot cannot mutate live sim")

func _placement(t) -> void:
	var sim = _fixture()
	t.check(not sim.place("unknown", Vector2i(15,15)), "Reject unknown building id")
	t.check(not sim.place("house", Vector2i(sim.grid.width-1,sim.grid.height-1)), "Reject out-of-bounds footprint")
	t.check(not sim.place("house", Vector2i(sim.grid.width-5,20)), "Reject water placement")
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
	var sim = _fixture()
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
	var disconnected = _fixture()
	disconnected.place("storehouse",Vector2i(17,21))
	disconnected.place("farm",Vector2i(12,18))
	disconnected.step(600)
	t.check(disconnected.stock("wheat") == 0, "No roads means no invisible deliveries")
	t.check(_find(disconnected,"farm").status == "output full", "Disconnected producer blocks at output capacity")

func _capacity_and_workers(t) -> void:
	var sim = _fixture()
	for cell in [Vector2i(12,15),Vector2i(16,15),Vector2i(22,15)]:
		sim.place("farm",cell)
	sim.step(300)
	var farms: Array = sim.buildings.values()
	t.check(farms[0].output.total() == 6, "Output slot capacity is six")
	t.check(farms[2].status == "no workers" and farms[2].output.total() == 0, "Insufficient workforce stops production")
	t.check(sim.grid.deposits.size() == sim.grid.width*sim.grid.height and "timber" in sim.grid.deposits and "fertile_soil" in sim.grid.deposits, "Map has one populated deposit layer")

func _generic_recipe(t) -> void:
	var db = preload("res://sim/content_db.gd").new()
	db.load_directory()
	var rows: Array = db.buildings.values().duplicate(true)
	var custom: Dictionary = db.buildings.farm.duplicate(true)
	custom.id = "test_orchard"
	custom.outputs = {"berries":1}
	rows.append(custom)
	t.check(db.validate(db.goods.values().duplicate(true), rows, db.tiers.values().duplicate(true)), "New producer definition validates without sim changes")
	var sim = _fixture(73,db)
	t.check(sim.place("test_orchard",Vector2i(14,15)), "Generic placement supports new content id")
	sim.step(100)
	t.check(int(sim.produced.get("berries",0)) > 0, "Generic production supports new JSON recipe")

func _road_repair(t) -> void:
	var sim = _fixture()
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
	var sim = _fixture()
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

func _workforce_switch(t) -> void:
	var sim = _fixture()
	for cell in [Vector2i(12,15),Vector2i(16,15),Vector2i(22,15)]:
		sim.place("farm",cell)
	sim.step(1)
	var farms: Array = sim.buildings.values()
	t.check(not farms[2].staffed and sim.idle_workers == 0, "Third farm starts without workers")
	t.check(sim.set_workers_enabled(farms[0].uid,false), "Stop a building's workers")
	sim.step(1)
	t.check(farms[0].status == "workers stopped" and not farms[0].staffed, "Stopped building does not work")
	t.check(farms[2].staffed, "Stopped workers move to the next building that needs them")
	sim.set_workers_enabled(farms[2].uid,false)
	sim.step(1)
	t.check(sim.idle_workers == 2, "Workers released by stopped buildings are counted as idle")
	t.check(sim.set_workers_enabled(farms[0].uid,true), "Restart a building's workers")
	sim.step(1)
	t.check(farms[0].staffed and sim.idle_workers == 0, "Restarted building takes its workers back")
	sim.place("house",Vector2i(26,15))
	t.check(not sim.set_workers_enabled(_find(sim,"house").uid,false), "Buildings without workers cannot be stopped")
	var chain = Sim.new()
	Scenario.starter(chain)
	chain.step(400)
	Scenario.complete_chain(chain)
	var mill = _find(chain,"mill")
	chain.set_workers_enabled(mill.uid,false)
	chain.step(300)
	t.check(mill.input.total() == 0, "Stopped building receives no inputs")

func _pantry_and_happiness(t) -> void:
	var sim = _fixture()
	var road: Array[Vector2i] = []
	for x in range(12,27):
		road.append(Vector2i(x,20))
	sim.place_road(road)
	sim.place("storehouse",Vector2i(12,21))
	sim.place("storehouse",Vector2i(24,21))
	var far = sim.buildings[sim.grid.occupied[Vector2i(12,21)]]
	var near = sim.buildings[sim.grid.occupied[Vector2i(24,21)]]
	near.inventory.add("berries",4)
	var far_berries: int = far.inventory.count("berries")
	sim.place("house",Vector2i(20,21))
	var house = _find(sim,"house")
	sim.step(60)
	var delivered: int = 4 - near.inventory.count("berries")
	t.check(delivered >= 2 and house.input.count("berries") + int(sim.consumed.get("berries",0)) == delivered, "Carriers stock the house pantry, which the house eats from")
	t.check(far.inventory.count("berries") == far_berries, "House is fed from the closest supply")
	t.check(house.happiness == 50 and house.status == "missing water", "Happiness counts the share of needs met")
	sim.place("well",Vector2i(18,21))
	sim.step(200)
	t.check(house.happiness == 100 and house.needs_ok, "Water from a well completes the needs")

func _money(t) -> void:
	var sim = _fixture()
	# Each stage costs its inputs plus its own labour, so longer chains cost more.
	t.check(sim.price("flour") == sim.price("wheat") + int(sim.economy.labour.flour) and sim.price("bread") == sim.price("flour") + sim.price("water") + int(sim.economy.labour.bread), "A good costs its inputs plus its maker's labour")
	t.check(sim.price("bread") > sim.price("flour") and sim.price("flour") > sim.price("wheat"), "Multistage goods cost more")
	t.check(sim.price("berries") == int(sim.db.goods.berries.price), "A good no building makes uses its base price")
	t.check(Economy.format(1234) == "12 g 34 s" and Economy.format(57) == "57 s" and Economy.format(300) == "3 g", "100 silver make a gold")
	# Construction is the treasury's spending: founding supplies are free, the
	# rest is bought from storehouses, and new buildings get working money.
	var road: Array[Vector2i] = []
	for x in range(12,27):
		road.append(Vector2i(x,20))
	sim.place_road(road)
	sim.place("storehouse",Vector2i(12,21))
	var store = _find(sim,"storehouse")
	t.check(sim.treasury == Economy.FOUNDING_TREASURY - Economy.STOREHOUSE_CAPITAL and store.silver == Economy.STOREHOUSE_CAPITAL, "Founding logs are free; a storehouse gets trading capital")
	var logs_value: int = 6 * sim.price("logs")
	sim.place("house",Vector2i(20,21))
	var house = _find(sim,"house")
	t.check(store.silver == Economy.STOREHOUSE_CAPITAL + logs_value and house.silver == Economy.HOUSEHOLD_GRANT, "The treasury buys a house's logs from the storehouse and gives it a starting purse")
	_money_conserved(t,sim,"construction")
	var saved: int = sim.treasury
	sim.treasury = 0
	t.check(sim.placement_error("well",Vector2i(18,21)).begins_with("Treasury needs"), "Construction needs gold in the treasury")
	sim.treasury = saved
	# Each link pays the one before it, and producers pass labour to the payroll.
	var chain = _fixture()
	Scenario.starter(chain)
	chain.step(400)
	Scenario.complete_chain(chain)
	var farm = _find(chain,"farm")
	var mill = _find(chain,"mill")
	var bakery = _find(chain,"bakery")
	t.check(mill.silver == chain.input_buffer(mill.definition,"wheat") * chain.price("wheat"), "A workshop gets enough silver to fill its inputs once")
	var mill_before: int = mill.silver
	var bakery_before: int = bakery.silver
	var payroll_before: int = chain.payroll
	chain.economy.settle(chain,mill,farm.uid,"wheat")
	chain.economy.settle(chain,bakery,mill.uid,"flour")
	t.check(mill.silver == mill_before - chain.price("wheat") + chain.price("flour") - int(chain.economy.labour.flour) and bakery.silver == bakery_before - chain.price("flour"), "Each stage pays the stage before it")
	t.check(chain.payroll == payroll_before + int(chain.economy.labour.wheat) + int(chain.economy.labour.flour), "Producers pass their labour to the payroll")
	chain.step(3000)
	var house_two = _find(chain,"house")
	t.check(chain.taxes_collected > 0 and house_two.last_tax == house_two.last_wage * chain.tax_percent / 100, "Tax on wages fills the treasury")
	t.check(house_two.tier == 2 and house_two.needs_ok, "Wages from the chain keep a Villager house fed")
	_conservation(t,chain,"priced chain")
	# Payroll is shared between houses by the workers each provides.
	t.check(chain.place("house",Vector2i(21,23)) or chain.place("house",Vector2i(15,15)), "Place a second household")
	var houses: Array = []
	for building in chain.buildings.values():
		if building.definition.kind == "house":
			houses.append(building)
	for house_row in houses:
		house_row.tier = 1
	chain.treasury -= 101 - chain.payroll
	chain.payroll = 101
	chain.economy.payday(chain)
	t.check(houses[0].last_wage + houses[1].last_wage == 101 and absi(houses[0].last_wage - houses[1].last_wage) <= 1, "Equal houses get equal shares of the payroll")
	_money_conserved(t,chain,"payroll shares")
	t.check(chain.set_tax_percent(0) and not chain.set_tax_percent(101), "Tax rate is set between 0 and 100 percent")
	# A household with no wages spends its purse, then goes without.
	var poor = _fixture()
	poor.place_road(road)
	poor.place("storehouse",Vector2i(12,21))
	poor.place("house",Vector2i(20,21))
	var idle = _find(poor,"house")
	var shop = _find(poor,"storehouse")
	poor.step(4000)
	t.check(idle.silver < poor.price("berries") and idle.status.begins_with("cannot afford") and idle.happiness < 100, "A house without wages cannot afford its needs")
	t.check(shop.silver > Economy.STOREHOUSE_CAPITAL, "The storehouse is paid for the food it sold")
	_money_conserved(t,poor,"poverty")
	poor.demolish(Vector2i(20,21))
	_money_conserved(t,poor,"demolished household")

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
	_money_conserved(t,sim,label)

func _money_conserved(t, sim, label: String) -> void:
	var money: int = sim.treasury + sim.payroll
	for building in sim.buildings.values():
		money += building.silver
	t.check(money == Economy.FOUNDING_TREASURY, "%s conserves money: %d == %d" % [label,money,Economy.FOUNDING_TREASURY])

## Small archived flat layout for isolated logistics/placement fixtures.
func _fixture(seed_value: int = 73, content = null):
	var rng = preload("res://sim/rng.gd").new(seed_value)
	var site = preload("res://sim/world/sites.gd").first_bread(rng,Vector2i(40,40))
	return Sim.new(seed_value,content,site)