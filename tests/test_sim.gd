extends RefCounted
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const Economy = preload("res://sim/economy.gd")
const Needs = preload("res://sim/needs.gd")
const Building = preload("res://sim/building.gd")

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
	_treasury(t)
	_carrier_jobs(t)
	_services(t)
	_happiness_effects(t)
	_chapels_and_berries(t)
	_priority_and_reserve(t)

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
	t.check(_place_first(sim,"chapel",[Vector2i(13,21),Vector2i(25,15),Vector2i(14,15)]), "Upgrade unlocks a chapel for the Villagers' chapel need")
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
	t.check(house.tier == 2 and house.needs_ok, "Bread, water, logs and a chapel sustain Villagers")
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
	# It eats its pantry, its settled happiness falls below the threshold, and
	# it stays there for the downgrade time.
	sim.step(2000)
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
	t.check(sim.price("berries") == int(sim.economy.labour.berries) and sim.price("berries") > 0, "Berries from berry bushes cost their pickers' labour")
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
	var fed := true
	for good in chain.db.tiers[2].consumption:
		fed = fed and house_two.needs_met.has(good)
	t.check(house_two.tier == 2 and fed, "Wages from the chain keep a Villager house fed")
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
	t.check(chain.set_tax_percent(0) and not chain.set_tax_percent(101), "Tax rate rejects values above the limit")
	# Only households pay the storehouse markup; a workshop buys at chain price.
	var chain_store = _find(chain,"storehouse")
	var float_silver: int = chain.price("wheat") - mill.silver
	if float_silver > 0: # The mill may be spent out after a long run; float it one purchase.
		mill.silver += float_silver
		chain.treasury -= float_silver
	var mill_silver: int = mill.silver
	var store_silver: int = chain_store.silver
	chain.economy.settle(chain,mill,chain_store.uid,"wheat")
	t.check(mill.silver == mill_silver - chain.price("wheat") and chain_store.silver == store_silver + chain.price("wheat"), "A workshop buys from a storehouse at the chain price")
	t.check(chain.sale_price(mill,chain_store,"wheat") == chain.price("wheat") and chain.sale_price(house_two,chain_store,"bread") > chain.price("bread") and chain.sale_price(house_two,bakery,"bread") == chain.price("bread"), "Only a household buying from a storehouse pays the markup")
	_money_conserved(t,chain,"workshop purchase")
	# A household with no wages spends its purse, then goes without.
	var poor = _fixture()
	poor.place_road(road)
	poor.place("storehouse",Vector2i(12,21))
	poor.place("house",Vector2i(20,21))
	var idle = _find(poor,"house")
	var shop = _find(poor,"storehouse")
	poor.step(4000)
	t.check(idle.silver < poor.economy.retail_price(poor,"berries") and idle.status.begins_with("cannot afford") and idle.happiness < 100, "A house without wages cannot afford its needs")
	t.check(shop.silver > Economy.STOREHOUSE_CAPITAL, "The storehouse is paid for the food it sold")
	_money_conserved(t,poor,"poverty")
	poor.demolish(Vector2i(20,21))
	_money_conserved(t,poor,"demolished household")
	t.check(poor.period.refunds > 0, "A demolished building's silver is recorded as a treasury refund")

## VILLAGERS.md section 5: tax control, reserves, public-worker frustration,
## storehouse markup and the purse cap.
func _treasury(t) -> void:
	var sim = _fixture()
	var road: Array[Vector2i] = []
	for x in range(12,27):
		road.append(Vector2i(x,20))
	sim.place_road(road)
	sim.place("storehouse",Vector2i(12,21))
	var store = _find(sim,"storehouse")
	t.check(sim.tax_percent == Economy.DEFAULT_TAX_PERCENT and sim.set_tax_percent(Economy.MAX_TAX_PERCENT) and sim.tax_percent == Economy.MAX_TAX_PERCENT, "Tax can be raised to the limit")
	t.check(not sim.set_tax_percent(Economy.MAX_TAX_PERCENT + Economy.TAX_STEP) and not sim.set_tax_percent(-1) and sim.tax_percent == Economy.MAX_TAX_PERCENT, "Tax outside 0 to the limit is rejected")
	sim.set_tax_percent(Economy.DEFAULT_TAX_PERCENT)
	# Reserves are parts of the treasury, moved by hand.
	var total: int = sim.treasury
	t.check(sim.transfer_reserve("public",300) and sim.public_reserve == 300 and sim.treasury == total and Economy.free_gold(sim) == total - 300, "Gold moves from free into the public pay reserve")
	t.check(sim.transfer_reserve("capital",100000) and sim.capital_reserve == total - 300 and Economy.free_gold(sim) == 0, "A transfer moves at most the free gold")
	t.check(not sim.transfer_reserve("capital",100) and not sim.transfer_reserve("savings",-100), "Nothing moves without free gold, or to an unknown reserve")
	_money_conserved(t,sim,"reserve transfers")
	# Construction draws on the capital reserve and never the public pay reserve.
	var built: int = sim.period.construction
	t.check(sim.place("house",Vector2i(20,21)), "Construction can spend the capital reserve")
	var house = _find(sim,"house")
	var house_cost: int = sim.period.construction - built
	t.check(house_cost > 0 and sim.capital_reserve == total - 300 - house_cost and sim.public_reserve == 300, "Construction leaves the public pay reserve untouched")
	t.check(sim.transfer_reserve("capital",-100000) and sim.capital_reserve == 0, "Gold moves back from a reserve")
	sim.transfer_reserve("public",100000)
	var well_error: String = sim.placement_error("well",Vector2i(18,21))
	t.check(well_error.begins_with("Treasury needs") and "public pay reserve" in well_error, "Construction cannot spend the public pay reserve: " + well_error)
	sim.transfer_reserve("public",-100000)
	t.check(sim.place("forester",Vector2i(15,21)), "Place a forester, a public workplace")
	var forester = _find(sim,"forester")
	# Public pay never touches the capital reserve. Unpaid public workers keep
	# working, but their frustration grows.
	sim.step(1)
	sim.transfer_reserve("capital",100000)
	var capital: int = sim.capital_reserve
	_to_payday(sim)
	t.check(forester.staffed and forester.last_wage == 0 and sim.capital_reserve == capital, "Public pay cannot spend the capital reserve")
	t.check(forester.frustration == 1 and sim.public_frustration == 1 and sim.ledger[-1].unpaid == Economy.WAGE, "Each unpaid public worker adds to the frustration counter")
	t.check(forester.staffed and forester.status not in ["no workers","workers stopped"], "Unpaid public workers keep working")
	# Public pay draws on its own reserve first.
	sim.transfer_reserve("capital",-100000)
	sim.transfer_reserve("public",25)
	var free_before: int = Economy.free_gold(sim)
	_to_payday(sim)
	t.check(forester.last_wage == Economy.WAGE and sim.public_reserve == 25 - Economy.WAGE and forester.frustration == 1, "Public pay comes from its reserve first")
	t.check(Economy.free_gold(sim) == free_before + sim.ledger[-1].tax + sim.ledger[-1].trade, "Free gold is untouched while the reserve pays")
	_money_conserved(t,sim,"public pay")
	# Storehouses sell to households at a markup; producers sell direct at chain price.
	var water: int = sim.price("water")
	t.check(sim.economy.retail_price(sim,"water") == water + 1, "The markup is at least 1 s on cheap goods")
	var bread: int = sim.price("bread")
	t.check(sim.economy.retail_price(sim,"bread") == bread + (bread * Economy.DEFAULT_MARKUP_PERCENT + 50) / 100, "The default markup is applied to the chain price")
	var house_silver: int = house.silver
	var store_silver: int = store.silver
	var payroll_before: int = sim.payroll
	var carried_before: int = store.wages_paid
	sim.economy.settle(sim,house,store.uid,"berries")
	var retail: int = sim.economy.retail_price(sim,"berries")
	var margin: int = retail - sim.price("berries")
	t.check(margin > 0 and house.silver == house_silver - retail, "A household pays a storehouse its markup")
	t.check(store.silver == store_silver + sim.price("berries") and sim.payroll == payroll_before + margin and store.wages_paid == carried_before + margin, "The markup pays the carriers through the payroll; the storehouse keeps the chain price")
	t.check(sim.place("well",Vector2i(18,21)), "Place a well beside the house")
	var well = _find(sim,"well")
	house_silver = house.silver
	sim.economy.settle(sim,house,well.uid,"water")
	t.check(house.silver == house_silver - water, "A producer sells to a household at the chain price")
	t.check(sim.set_markup_percent(0) and sim.economy.retail_price(sim,"bread") == bread and not sim.set_markup_percent(Economy.MAX_MARKUP_PERCENT + 1), "Markup is set from 0 to its limit")
	sim.set_markup_percent(Economy.DEFAULT_MARKUP_PERCENT)
	_money_conserved(t,sim,"markup sales")
	# A storehouse keeps enough silver to restock what the village makes up to
	# its per-good limit (and at least PURSE_CAP); the rest goes to the treasury
	# at payday. Called directly, so no carrier trades in between.
	var limit := int(store.definition.good_limit)
	var restock: int = (limit - store.inventory.count("water")) * water
	t.check(sim.economy.purse_cap(sim,store) == maxi(Economy.PURSE_CAP,restock), "The purse cap covers restocking the goods the village makes")
	var cap: int = sim.economy.purse_cap(sim,store)
	var top_up: int = cap + 37 - store.silver
	store.silver += top_up
	sim.treasury -= top_up
	sim.economy.payday(sim)
	t.check(store.silver == cap and sim.ledger[-1].trade == 37, "A storehouse's surplus above its purse cap goes to the treasury")
	_money_conserved(t,sim,"trade surplus")
	for index in Economy.LEDGER_PAYDAYS + 2:
		_to_payday(sim)
	t.check(sim.ledger.size() == Economy.LEDGER_PAYDAYS, "The ledger keeps the last few paydays")
	# Reserves, markup, frustration and the ledger survive a snapshot.
	sim.transfer_reserve("public",120)
	sim.transfer_reserve("capital",80)
	sim.set_markup_percent(40)
	var restored = Sim.from_snapshot(sim.snapshot())
	t.check(restored != null and JSON.stringify(restored.snapshot()) == JSON.stringify(sim.snapshot()), "Treasury state round-trips through a snapshot")
	var tampered: Dictionary = sim.snapshot()
	tampered.public_reserve = tampered.treasury
	t.check(Sim.from_snapshot(tampered) == null, "Snapshots with reserves larger than the treasury are rejected")
	tampered = sim.snapshot()
	tampered.ledger.append({"tax":1})
	t.check(Sim.from_snapshot(tampered) == null, "Snapshots with malformed ledger entries are rejected")

## Carriers are jobs: staffed from idle workers after buildings.
func _carrier_jobs(t) -> void:
	var sim = _fixture()
	var road: Array[Vector2i] = []
	for x in range(12,27):
		road.append(Vector2i(x,20))
	sim.place_road(road)
	sim.place("storehouse",Vector2i(12,21))
	var store = _find(sim,"storehouse")
	sim.step(1)
	t.check(store.crew == 4 and sim.idle_workers == 0, "Carriers take the village's idle workers (4 founders for 6 carriers)")
	sim.place("farm",Vector2i(16,21))
	var farm = _find(sim,"farm")
	sim.step(1)
	t.check(farm.staffed and store.crew == 2, "Buildings are staffed before carriers")
	var on_shift := 0
	for carrier in sim.carriers:
		if carrier._on_shift: on_shift += 1
	t.check(on_shift == store.crew, "Only the crew's carriers are on shift")
	var most_busy := 0
	for index in 400:
		sim.step(1)
		var busy := 0
		for carrier in sim.carriers:
			if carrier.stage != "idle": busy += 1
		most_busy = maxi(most_busy,busy)
	t.check(most_busy > 0 and most_busy <= store.crew, "No more carriers work than the crew: %d of %d" % [most_busy,store.crew])
	sim.set_workers_enabled(farm.uid,false)
	sim.step(1)
	t.check(store.crew == 4, "Stopping a building frees its workers for carrying")
	var starter = Sim.new(73)
	Scenario.starter(starter)
	starter.step(1)
	t.check(_find(starter,"storehouse").crew == starter.workforce() - 5, "The starter village runs %d of 6 carriers" % _find(starter,"storehouse").crew)

## Public services are marked in data and paid by the treasury.
func _services(t) -> void:
	var db = preload("res://sim/content_db.gd").new()
	db.load_directory()
	t.check(Economy.is_public(db.buildings.forester) and Economy.upkeep(db.buildings.forester) == Economy.WAGE * int(db.buildings.forester.workers), "The forester is a public service with upkeep")
	t.check(not Economy.is_public(db.buildings.mill) and Economy.upkeep(db.buildings.mill) == 0, "Workshops are not services")
	# validate() replaces the db's rows, so every case starts from the same copy.
	var base: Array = db.buildings.values().duplicate(true)
	var goods: Array = db.goods.values().duplicate(true)
	var tiers: Array = db.tiers.values().duplicate(true)
	for case in [["service",false,"A producer that sells nothing must be a service"],["outputs",{"logs":1},"A service cannot sell goods"]]:
		var rows: Array = base.duplicate(true)
		for row in rows:
			if row.id == "forester":
				row[case[0]] = case[1]
				if case[0] == "outputs": row.erase("forest_action")
		t.check(not db.validate(goods.duplicate(true),rows,tiers.duplicate(true)), case[2])

## Happiness settles over the last cycles; it decides demotion and workplace speed.
func _happiness_effects(t) -> void:
	t.check(Needs.work_speed(100) == 100 and Needs.work_speed(0) == Needs.MIN_WORK_SPEED and Needs.work_speed(66) == 83, "Workplace speed follows morale from half to full")
	# A house with no road or storehouse, its pantry filled by hand.
	var sim = _fixture()
	sim.place("house",Vector2i(20,21))
	var house = _find(sim,"house")
	t.check(Needs.settled(house) == -1 and Needs.morale(sim) == 100, "Before a full cycle a house has no settled happiness and morale is full")
	house.tier = 2
	for index in 1500:
		for good in ["water","bread","logs"]:
			if house.input.count(good) == 0: house.input.add(good)
		sim.step(1)
	t.check(house.tier == 2 and Needs.settled(house) == 75 and house.happiness_history.size() == 3 and not house.needs_met.has("chapel"), "One missing need (no chapel) leaves a house unhappy but not demoted: settled %d" % Needs.settled(house))
	t.check(Needs.morale(sim) == 75, "Village morale is the houses' settled happiness")
	for index in 2000:
		if house.input.count("water") == 0: house.input.add("water")
		sim.step(1)
		if house.tier == 1: break
	t.check(house.tier == 1, "A house whose settled happiness stays below the threshold is demoted")
	t.check(house.happiness_history.is_empty() or house.happiness_history.size() <= 1, "A new tier starts a fresh happiness history")
	# Low morale slows workplaces.
	var fast = _fixture()
	var slow = _fixture()
	for village in [fast,slow]:
		village.place("farm",Vector2i(12,15))
	slow.place("house",Vector2i(20,21))
	_find(slow,"house").happiness_history = [0,0,0]
	fast.step(140)
	slow.step(140)
	t.check(Needs.morale(slow) == 0 and int(slow.produced.get("wheat",0)) * 2 == int(fast.produced.get("wheat",0)), "Workplaces at zero morale work at half speed: %d vs %d wheat" % [int(slow.produced.get("wheat",0)),int(fast.produced.get("wheat",0))])

## Chapels are a service need: staffed chapels cover houses within their radius by road.
func _chapels_and_berries(t) -> void:
	var sim = _fixture()
	var road: Array[Vector2i] = []
	for x in range(12,27):
		road.append(Vector2i(x,20))
	sim.place_road(road)
	sim.place("storehouse",Vector2i(12,21))
	sim.place("house",Vector2i(20,21))
	var house = _find(sim,"house")
	t.check(not sim.place("chapel",Vector2i(24,21)) and sim.last_error.begins_with("Requires"), "Chapels unlock with Villagers")
	t.check(sim.place("berry_bushes",Vector2i(16,21)), "Settlers can plant berry bushes")
	sim.step(400)
	t.check(int(sim.produced.get("berries",0)) > 0, "Berry bushes grow berries")
	sim.unlocked_tier = 2
	house.tier = 2
	t.check(sim.place("chapel",Vector2i(24,21)), "Place a chapel near the house")
	var chapel = _find(sim,"chapel")
	sim.step(2)
	t.check(sim.serves(house,"chapel") and house.needs_met.has("chapel") and sim.served_houses(chapel) == 1, "A staffed chapel in range meets the chapel need")
	t.check(Economy.is_public(chapel.definition) and Economy.upkeep(chapel.definition) > 0, "The treasury pays the chapel's priest")
	sim.set_workers_enabled(chapel.uid,false)
	sim.step(1)
	t.check(not sim.serves(house,"chapel"), "A chapel without its priest serves nobody")
	sim.set_workers_enabled(chapel.uid,true)
	sim.step(1)
	# This sim's own content: shrink the radius below the road distance.
	chapel.definition.service_radius = sim.grid.distance(chapel,house) - 1
	t.check(not sim.serves(house,"chapel"), "A chapel beyond its radius serves nobody")
	var db = preload("res://sim/content_db.gd").new()
	db.load_directory()
	var rows: Array = db.buildings.values().duplicate(true)
	for row in rows:
		if row.id == "chapel": row.erase("service_radius")
	t.check(not db.validate(db.goods.values().duplicate(true),rows,db.tiers.values().duplicate(true)), "A providing service needs a radius")

## Labour priority orders staffing; the service reserve target tops up public pay.
func _priority_and_reserve(t) -> void:
	var sim = _fixture()
	for cell in [Vector2i(12,15),Vector2i(16,15),Vector2i(22,15)]:
		sim.place("farm",cell)
	var farms: Array = sim.buildings.values()
	sim.step(1)
	t.check(farms[0].staffed and farms[1].staffed and not farms[2].staffed, "Equal priorities staff in placement order")
	t.check(sim.set_priority(farms[2].uid,Building.HIGH), "Raise a workplace's priority")
	sim.step(1)
	t.check(farms[2].staffed and farms[0].staffed and not farms[1].staffed, "A high-priority workplace is staffed first")
	t.check(sim.set_priority(farms[0].uid,Building.LOW), "Lower a workplace's priority")
	sim.step(1)
	t.check(farms[1].staffed and not farms[0].staffed, "A low-priority workplace is staffed last")
	t.check(not sim.set_priority(farms[0].uid,3) and not sim.set_priority(9999,Building.HIGH), "Priority must be a known level on a known building")
	var road: Array[Vector2i] = []
	for x in range(12,27):
		road.append(Vector2i(x,20))
	sim.place_road(road)
	sim.place("storehouse",Vector2i(12,21))
	var store = _find(sim,"storehouse")
	sim.step(1)
	t.check(store.crew == 0, "Normal-priority carriers come after every higher job")
	t.check(sim.set_priority(store.uid,Building.HIGH), "A storehouse's priority ranks its carriers")
	sim.step(1)
	t.check(farms[2].staffed and store.crew == 2 and not farms[1].staffed, "High-priority carriers come after high workplaces but before normal ones")
	t.check(not sim.set_priority(_find(sim,"storehouse").uid - 999,Building.LOW), "Unknown buildings have no priority")
	# The service reserve target keeps two paydays of upkeep in public pay.
	var town = _fixture()
	town.place_road(road)
	town.place("storehouse",Vector2i(12,21))
	town.place("forester",Vector2i(15,21))
	t.check(town.set_keep_service_reserve(true), "Keep services reserved")
	town.step(town.PAYDAY_TICKS)
	var upkeep: int = Economy.upkeep(town.db.buildings.forester)
	t.check(town.public_reserve == Economy.SERVICE_RESERVE_PAYDAYS * upkeep, "Payday tops the public pay reserve up to two paydays of upkeep: %d" % town.public_reserve)
	_money_conserved(t,town,"service reserve")
	var restored = Sim.from_snapshot(town.snapshot())
	t.check(restored != null and restored.keep_service_reserve, "The reserve setting survives a snapshot")

func _place_first(sim, id: String, cells: Array) -> bool:
	for cell in cells:
		if sim.place(id, cell + Scenario.offset(sim)):
			return true
	return false

func _to_payday(sim) -> void:
	sim.step(sim.PAYDAY_TICKS - sim.tick % sim.PAYDAY_TICKS)

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
	# Arriving factions' endowments are outside money, held in their coffers.
	var money: int = sim.treasury + sim.payroll + sim.factions.total()
	for building in sim.buildings.values():
		money += building.silver
	var expected: int = Economy.FOUNDING_TREASURY + sim.outside_money
	t.check(money == expected, "%s conserves money: %d == %d" % [label,money,expected])
	t.check(sim.public_reserve >= 0 and sim.capital_reserve >= 0 and sim.public_reserve + sim.capital_reserve <= sim.treasury, "%s keeps reserves inside the treasury" % label)

## Small archived flat layout for isolated logistics/placement fixtures.
func _fixture(seed_value: int = 73, content = null):
	var rng = preload("res://sim/rng.gd").new(seed_value)
	var site = preload("res://sim/world/sites.gd").first_bread(rng,Vector2i(40,40))
	return Sim.new(seed_value,content,site)