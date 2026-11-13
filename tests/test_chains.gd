extends RefCounted
## The supply chains added from docs/SUPPLY_CHAINS.md: goods categories and
## category needs, the fisher, the woodshed (fuel), the sawmill (planks) and
## the meat chain (pig farm and butcher).
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const ContentDB = preload("res://sim/content_db.gd")
const SimTests = preload("res://tests/test_sim.gd")

func run(t) -> void:
	_content(t)
	_category_needs(t)
	_fisher(t)
	# The meat chain grows a village over about 10,000 ticks: full tier only.
	if t.get("quick") != true:
		_meat_chain(t)

func _content(t) -> void:
	var db = ContentDB.new()
	t.check(db.load_directory(), "Shipped content with goods categories validates")
	t.check(db.need_goods("staple") == ["bread","fish","meat"] and db.need_goods("fuel") == ["firewood"] and db.need_goods("basic") == ["berries","fish","meat"], "Categories list their goods in goods.json order")
	t.check(db.need_goods("water") == ["water"] and db.need_name("staple") == "Staple food" and db.need_name("water") == "Water", "A good is its own need")
	t.check(db.need_for(2, "meat") == "staple" and db.need_for(2, "logs") == "" and db.need_for(1, "fish") == "basic", "need_for maps a good to the tier need it meets; logs are no longer fuel")
	# Rule 2: no dead ends. Every good is an input, a construction cost or a need.
	for good in db.goods:
		var used := false
		for row in db.buildings.values():
			used = used or row.inputs.has(good) or row.cost.has(good)
		for tier in db.tiers:
			used = used or not db.need_for(tier, good).is_empty()
		t.check(used, "%s has a consumer (SUPPLY_CHAINS.md rule 2)" % good)
	# Every new building is unlocked by its tier.
	for id in ["fisher","woodshed","sawmill","pig_farm","butcher"]:
		t.check(db.buildings.has(id) and id in db.tiers[int(db.buildings[id].unlock_tier)].unlocks, "%s is unlocked by its tier" % id)
	var goods: Array = db.goods.values().duplicate(true)
	var buildings: Array = db.buildings.values().duplicate(true)
	var tiers: Array = db.tiers.values().duplicate(true)
	goods[0].categories = ["luxury"]
	t.check(not db.validate(goods, buildings, tiers) and "unknown category luxury" in "; ".join(db.errors), "Reject an unknown goods category")
	goods[0].categories = []
	tiers[1].consumption = {"water":1, "cloth":1}
	t.check(not db.validate(goods, buildings, tiers) and "empty category cloth" in "; ".join(db.errors), "Reject a need for a category no good belongs to")
	db.load_directory()
	tiers = db.tiers.values().duplicate(true)
	goods = db.goods.values().duplicate(true)
	for row in buildings:
		if row.id == "fisher": row.adjacent_terrain = ["lava"]
	t.check(not db.validate(goods, buildings, tiers) and "unknown adjacent terrain lava" in "; ".join(db.errors), "Reject an unknown adjacent terrain")

## Any good of a category meets the need, and logs no longer count as fuel.
func _category_needs(t) -> void:
	var sim = SimTests.new()._fixture()
	t.check(sim.place_road([Vector2i(20,20)]) and sim.place("house", Vector2i(20,21)), "Place a house on a road for the needs check")
	var house = _find(sim, "house")
	house.tier = 2
	for index in 250:
		for good in ["water","meat","logs"]:
			if house.input.count(good) == 0: house.input.add(good)
		sim.step(1)
	t.check(house.needs_met.has("staple") and not house.needs_met.has("fuel"), "Meat meets the staple need; logs do not meet fuel")
	t.check(house.status == "missing fuel", "The house says it is missing fuel: %s" % house.status)
	t.check(int(sim.consumed.get("meat", 0)) > 0 and house.input.count("logs") == 1, "The house ate meat and burned no logs")
	house.input.add("firewood")
	sim.step(1)
	t.check(house.needs_met.has("fuel") and int(sim.consumed.get("firewood", 0)) == 1, "Firewood meets the fuel need")
	t.check(sim.economy.need_price(sim, "staple") == mini(sim.price("bread"), mini(sim.price("fish"), sim.price("meat"))) and sim.economy.retail_price(sim, "fuel") > sim.price("firewood"), "A category need is priced at its cheapest good")

## A fisher must touch water; its fish feed Settlers without berries.
func _fisher(t) -> void:
	var sim = SimTests.new()._fixture()
	t.check(sim.placement_error("fisher", Vector2i(20,24)) == "Must touch water", "A fisher away from water is refused: %s" % sim.placement_error("fisher", Vector2i(20,24)))
	t.check(sim.placement_error("fisher", Vector2i(30,20)) == "", "A fisher on the shore is allowed: %s" % sim.placement_error("fisher", Vector2i(30,20)))
	sim.reserve.take("berries", sim.reserve.count("berries"))
	t.check(Scenario.starter(sim) and sim.place_road([Vector2i(28,20), Vector2i(29,20)]) and sim.place("fisher", Vector2i(30,20)), "Starter village with a fisher's hut on the shore")
	var house = _find(sim, "house")
	while sim.tick < 3000 and house.tier < 2:
		sim.step(1)
	t.check(house.tier == 2 and int(sim.produced.get("fish", 0)) > 0 and int(sim.consumed.get("fish", 0)) > 0 and int(sim.consumed.get("berries", 0)) == 0, "Fish alone feeds a Settler house to Villagers (tick %d)" % sim.tick)

## Sawmill planks build the pig farm and butcher; their meat feeds Villagers
## when the bakery stops.
func _meat_chain(t) -> void:
	var sim = SimTests.new()._fixture()
	t.check(Scenario.starter(sim), "Meat chain: starter layout")
	while sim.tick < 3000 and sim.unlocked_tier < 2:
		sim.step(1)
	# Families of 1–2 adults: four more cottages staff the sawmill, the meat
	# chain and its carriers, and a second well waters ten families and the
	# pigs. Their grants and the extra workshops need more silver than the
	# founding treasury holds, so the test brings some in as outside money.
	sim.treasury += 300
	sim.outside_money += 300
	t.check(Scenario.complete_chain(sim) and sim.place("house", Vector2i(21,23)) and sim.place("house", Vector2i(21,16)) and sim.place("house", Vector2i(18,16)) and sim.place("house", Vector2i(26,21)) and sim.place("well", Vector2i(22,19)) and sim.place("sawmill", Vector2i(25,18)), "Meat chain: bread chain, woodshed, four more cottages, a second well and sawmill: %s" % sim.last_error)
	t.check(sim.placement_error("pig_farm", Vector2i(12,21)) == "Need 2 planks", "A pig farm needs planks: %s" % sim.placement_error("pig_farm", Vector2i(12,21)))
	var start: int = sim.tick
	while sim.tick < start + 3000 and sim.stock("planks") < 4:
		sim.step(1)
	t.check(sim.stock("planks") >= 4, "The sawmill's planks reach the storehouse (%d ticks)" % (sim.tick - start))
	# The woodcutter has thinned its trees by now; logs cut further out arrive
	# for the butcher (counted as produced, so goods stay conserved).
	sim.reserve.add("logs", 20)
	sim.produced.logs = int(sim.produced.get("logs", 0)) + 20
	t.check(sim.place("pig_farm", Vector2i(12,21)) and sim.place("butcher", Vector2i(15,21)), "Planks pay for the pig farm and butcher: %s" % sim.last_error)
	var bakery = _find(sim, "bakery")
	sim.set_workers_enabled(bakery.uid, false)
	sim.step(4000)
	t.check(int(sim.produced.get("pigs", 0)) > 0 and int(sim.produced.get("meat", 0)) > 0, "Pigs become meat: %d pigs, %d meat" % [int(sim.produced.get("pigs", 0)), int(sim.produced.get("meat", 0))])
	t.check(int(sim.consumed.get("meat", 0)) > 0 and int(sim.produced.get("firewood", 0)) > 0, "Villagers eat meat and burn firewood")
	var fed := 0
	for building in sim.buildings.values():
		if building.definition.kind == "house" and building.tier == 2 and building.needs_met.has("staple"):
			fed += 1
	t.check(fed >= 1 and int(sim._eaten.get("meat", 0)) > 0, "With the bakery stopped, Villager houses eat meat as their staple (%d houses)" % fed)
	SimTests.new()._conservation(t, sim, "meat chain")

func _find(sim, id: String):
	for building in sim.buildings.values():
		if building.definition.id == id:
			return building
	return null
