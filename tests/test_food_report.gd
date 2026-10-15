extends RefCounted
## The food balance behind the HUD's food button (sim/food_report.gd).
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const FoodReport = preload("res://sim/food_report.gd")
const SimTests = preload("res://tests/test_sim.gd")
const Needs = preload("res://sim/needs.gd")

func run(t) -> void:
	_needs(t)
	_balance(t)
	_sources(t)
	_measured(t)

func _house(sim, tier: int):
	sim.place("house", Vector2i(20, 21))
	for building in sim.buildings.values():
		if building.definition.kind == "house":
			building.tier = tier
			return building

func _needs(t) -> void:
	var sim = SimTests.new()._fixture()
	t.check(FoodReport.food_goods(sim.db) == ["bread", "berries", "fish", "meat"], "Food is every good in a food category: %s" % str(FoodReport.food_goods(sim.db)))
	var house = _house(sim, 1)
	var report: Dictionary = FoodReport.new().report(sim)
	var settler: float = float(FoodReport.MINUTE) / Needs.consume_ticks(sim, house)
	t.check(report.needs.size() == 1 and report.needs[0].need == "basic" and is_equal_approx(report.required, settler), "A Settler family needs one basket per its own interval: %.2f a minute" % report.required)
	t.check(report.state == "measuring", "With nothing measured yet the balance says so")
	house.tier = 2
	report = FoodReport.new().report(sim)
	t.check(report.needs[0].need == "staple" and is_equal_approx(report.required, float(FoodReport.MINUTE) / Needs.consume_ticks(sim, house)) and report.needs[0].houses == 1, "A Villager family needs staple food at its own rate")
	# A family of six mouths (Needs.REFERENCE_MOUTHS) eats at the tier's rate: 6 basic or 3 staple a minute.
	house.adults = 2
	house.children = 8
	house.tier = 1
	t.check(is_equal_approx(FoodReport.new().report(sim).required, 6.0), "Six mouths eat the Settler basket every 100 ticks")
	house.tier = 2
	t.check(is_equal_approx(FoodReport.new().report(sim).required, 3.0), "Six mouths eat the Villager basket every 200 ticks")

## Supply is matched to needs: berries feed no Villager, fish and meat fill
## whichever need is short, and stored food buys time.
func _balance(t) -> void:
	var sim = SimTests.new()._fixture()
	var house = _house(sim, 2)
	house.adults = 2
	house.children = 8
	sim.reserve.take("berries", sim.reserve.count("berries"))
	var meter = FoodReport.new()
	meter.sample(sim)
	sim.step(FoodReport.MINUTE)
	sim.produced.berries = int(sim.produced.get("berries", 0)) + 60
	sim.produced.bread = int(sim.produced.get("bread", 0)) + 1
	var report: Dictionary = meter.report(sim)
	t.check(report.span == FoodReport.MINUTE and is_equal_approx(report.made, 61.0), "Made food is measured per minute: %s" % str(report.made))
	t.check(is_equal_approx(report.needs[0].supplied, 1.0) and is_equal_approx(report.usable, 1.0), "Berries do not feed Villagers")
	t.check(report.state == "deficit" and is_equal_approx(report.short, 2.0), "Villagers short of staple food are in deficit: %s %s" % [report.state, str(report.short)])
	sim.reserve.add("bread", 20)
	report = meter.report(sim)
	t.check(report.state == "stores" and report.stored == 20 and int(report.minutes_stored) == 6, "Short but stocked lives off stores: %s, %s min" % [report.state, str(report.minutes_stored)])
	sim.produced.meat = int(sim.produced.get("meat", 0)) + 5
	report = meter.report(sim)
	# With Settlers and Villagers both present, fish fills either need but is
	# counted only once.
	var mixed = SimTests.new()._fixture()
	var villager = _house(mixed, 2)
	mixed.place("house", Vector2i(24, 21))
	for building in mixed.buildings.values():
		building.adults = 2
		building.children = 8
	mixed.reserve.take("berries", mixed.reserve.count("berries"))
	var mixed_meter = FoodReport.new()
	mixed_meter.sample(mixed)
	mixed.step(FoodReport.MINUTE)
	mixed.produced.fish = int(mixed.produced.get("fish", 0)) + 6
	var both: Dictionary = mixed_meter.report(mixed)
	t.check(villager != null and both.needs.size() == 2 and is_equal_approx(both.required, 9.0) and is_equal_approx(both.short, 3.0) and is_equal_approx(both.usable, 6.0), "Shared fish is split between needs, not counted twice: short %s" % str(both.short))
	t.check(report.state == "surplus" and is_equal_approx(report.needs[0].supplied, 6.0) and is_equal_approx(report.usable, 6.0), "Meat fills the staple shortfall: %s" % report.state)

## Producers and why they idle; storage-idle ones count as spare supply.
func _sources(t) -> void:
	var sim = Sim.new(73)
	Scenario.starter(sim)
	var shift: Vector2i = Scenario.offset(sim)
	sim.place_road([Vector2i(28, 20) + shift, Vector2i(29, 20) + shift])
	t.check(sim.place("hunter", Vector2i(28, 21) + shift), "Place a hunter for the producer list")
	sim.step(1)
	var hunter = null
	for building in sim.buildings.values():
		if building.definition.id == "hunter":
			hunter = building
	var meat: Dictionary = {}
	for row in FoodReport.new().report(sim).goods:
		if row.good == "meat":
			meat = row
	t.check(meat.sources.size() == 1 and meat.sources[0].name == "Hunter's lodge" and meat.sources[0].working == 1, "Meat lists its working hunter")
	hunter.status = "storehouse has enough meat"
	for row in FoodReport.new().report(sim).goods:
		if row.good == "meat":
			meat = row
	t.check(meat.sources[0].idle.has("storehouse has enough meat") and is_equal_approx(meat.spare, 2.0 * FoodReport.MINUTE / int(hunter.definition.cycle_ticks)), "A hunter idle for storage room counts as spare supply: %s" % str(meat.spare))

## Over a real run the meter's eaten food matches the houses' needs, and a
## restarted village starts a fresh history.
func _measured(t) -> void:
	var sim = Sim.new(73)
	Scenario.starter(sim)
	while sim.unlocked_tier < 2 and sim.tick < 3000:
		sim.step(1)
	Scenario.complete_chain(sim)
	var meter = FoodReport.new()
	for index in 30:
		sim.step(FoodReport.STEP)
		meter.sample(sim)
	var report: Dictionary = meter.report(sim)
	t.check(report.span >= FoodReport.WINDOW and report.span <= FoodReport.WINDOW + FoodReport.STEP, "The meter measures the last two minutes: %d ticks" % report.span)
	t.check(report.eaten > 0.0 and report.eaten <= report.required + 0.5 and report.made > 0.0, "Food made and eaten are measured: made %.1f, eaten %.1f, needed %.1f" % [report.made, report.eaten, report.required])
	var fresh = Sim.new(73)
	meter.sample(fresh)
	t.check(meter.samples.size() == 1, "A village that went back in time starts a fresh history")
