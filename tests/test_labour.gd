extends RefCounted
## Jobs by class, staffing by family, and wages to the families who worked
## (docs/PLAN-job-classes.md).
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const Economy = preload("res://sim/economy.gd")
const Labour = preload("res://sim/labour.gd")
const ContentDB = preload("res://sim/content_db.gd")
const Sites = preload("res://sim/world/sites.gd")
const SeededRNG = preload("res://sim/rng.gd")

func run(t) -> void:
	_data(t)
	_pools(t)
	_staffing(t)
	_keeper(t)
	_wages(t)
	_services(t)
	_snapshot(t)
	_middle_class(t)
	_families(t)

## A row's jobs default to working-class; validation checks classes and counts.
func _data(t) -> void:
	var db = ContentDB.new()
	t.check(db.load_directory(), "Shipped content validates with jobs")
	t.check(Labour.jobs(db.buildings.storehouse) == {"middle":1} and int(db.buildings.storehouse.workers) == 1, "A storehouse has one middle-class job, its storekeeper's")
	t.check(Labour.jobs(db.buildings.mill) == {"working":2} and Labour.jobs(db.buildings.house).is_empty(), "A row without jobs has its workers' working-class jobs")
	var goods: Array = db.goods.values().duplicate(true)
	var tiers: Array = db.tiers.values().duplicate(true)
	var factions: Array = db.factions.values().duplicate(true)
	for case in [["mill", {"gentry":2}, "Reject an unknown job class"], ["mill", {"working":1}, "Reject jobs that do not add up to workers"], ["mill", {"working":0, "middle":2}, "Reject a zero count"], ["mill", [], "Reject jobs that are not a map"], ["storehouse", {"middle":2}, "Reject a storehouse with more than one job"]]:
		var rows: Array = db.buildings.values().duplicate(true)
		for row in rows:
			if row.id == case[0]:
				row.jobs = case[1]
				if case[0] == "storehouse" and case[1] is Dictionary:
					row.workers = 2
		t.check(not db.validate(goods.duplicate(true), rows, tiers.duplicate(true), factions.duplicate(true)), case[2])
	db.load_directory()

## Higher classes take lower jobs, never the reverse; jobs go round families.
func _pools(t) -> void:
	var pools = Labour.Pools.new()
	pools.add(1, 1, 2)
	pools.add(2, 1, 2)
	pools.add(3, 2, 1)
	t.check(pools.counts() == {1:4, 2:1, 3:0}, "Pools count free workers by rank")
	t.check(not pools.can_fill({"middle":2}) and pools.can_fill({"middle":1, "working":4}) and not pools.can_fill({"working":6}), "A working family never fills a middle-class job; a middle one may fill a working job")
	t.check(pools.fill({"working":2}) == [1, 2], "Working jobs go round the working families, one each before seconds")
	t.check(pools.fill({"working":2}) == [1, 2] and pools.take(1) == 3, "With the working families full, a middle-class worker takes a working job")
	t.check(pools.take(2) == -1 and pools.total() == 0, "Nobody is left for a middle-class job")
	# An inn's four lodgers are four families of one: each gets a job before
	# the couple next door gets its second.
	var inn = Labour.Pools.new()
	inn.add(1, 1, 4, true)
	inn.add(2, 1, 2)
	t.check(inn.fill({"working":5}) == [1, 1, 1, 1, 2] and inn.take(1) == 2, "Lodgers are single families, paid to their inn")

## The starter village has no middle-class family: the storekeeper's job stays
## empty, and every other job fills as before.
func _staffing(t) -> void:
	var sim = Sim.new(73)
	Scenario.starter(sim)
	sim.step(1)
	var idle: int = Labour.staff(sim)
	var store = _find(sim, "storehouse")
	var crewed := 0
	for building in sim.buildings.values():
		crewed += building._crew.size()
	t.check(store._keeper == -1 and store.crew == store._crew.size(), "No middle-class family: no storekeeper, carriers still on shift")
	t.check(idle + crewed == sim.workforce(), "Every worker is either in a job or idle: %d + %d == %d" % [idle, crewed, sim.workforce()])
	var house = _find(sim, "house")
	t.check(_find(sim, "well")._crew == [house.uid], "The well's worker is from the homestead")
	# A batch of ticks staffs as single ticks do.
	var a = Sim.new(73)
	var b = Sim.new(73)
	Scenario.starter(a)
	Scenario.starter(b)
	a.step(400)
	for index in 400:
		b.step(1)
	t.check(JSON.stringify(a.snapshot()) == JSON.stringify(b.snapshot()), "Staffing and wages are the same across tick batch sizes")

## A middle-class family fills the storekeeper's job and takes 30% of the
## markup; the carriers' families share the rest.
func _keeper(t) -> void:
	var sim = Sim.new(73)
	Scenario.starter(sim)
	var house = _find(sim, "house")
	_make_middle(house)
	Labour.staff(sim)
	var store = _find(sim, "storehouse")
	t.check(store._keeper == house.uid, "A middle-class family keeps the store")
	var carriers: Array = store._crew.duplicate()
	t.check(not carriers.is_empty() and carriers.all(func(uid): return uid == house.uid), "With one family, it also carries")
	house.earned = 0
	Labour.credit(sim, store, 100)
	t.check(house.earned == 100, "Keeper and carriers from one family earn the whole markup")
	# Two families: the keeper's share goes to the keeper's.
	var second = _place_house(sim)
	t.check(second != null, "Place a second house")
	if second == null:
		return
	Labour.staff(sim)
	house.earned = 0
	second.earned = 0
	store._crew = [second.uid]
	Labour.credit(sim, store, 100)
	t.check(house.earned == Labour.KEEPER_PERCENT and second.earned == 100 - Labour.KEEPER_PERCENT, "The storekeeper takes 30%%, the carriers the rest: %d / %d" % [house.earned, second.earned])
	store._keeper = -1
	house.earned = 0
	second.earned = 0
	Labour.credit(sim, store, 100)
	t.check(house.earned == 0 and second.earned == 100, "Without a storekeeper, the carriers take it all")

## Wages go to the families who worked; an idle family earns nothing.
func _wages(t) -> void:
	var sim = Sim.new(73)
	Scenario.starter(sim)
	var worker = _find(sim, "house")
	var idle = _place_house(sim)
	t.check(idle != null, "Place a second house")
	if idle == null:
		return
	var mill = _find(sim, "well")
	mill._crew = [worker.uid]
	sim.payroll += 40
	sim.treasury -= 40
	Labour.credit(sim, mill, 40)
	var wages: Array[int] = Labour.wages(sim, [worker, idle])
	t.check(wages == [40, 0], "The family that worked is paid; the idle one gets nothing: %s" % str(wages))
	# Silver nobody earned is shared by workers, as before.
	sim.payroll += 10
	sim.treasury -= 10
	wages = Labour.wages(sim, [worker, idle])
	t.check(wages[0] + wages[1] == 50 and wages[0] >= 40, "Unearned silver is shared between houses: %s" % str(wages))
	sim.economy._pay_households(sim)
	t.check(sim.payroll == 0 and worker.earned == 0 and idle.earned == 0 and worker.last_wage >= 40, "Payday pays and clears every family's earnings")
	_money(t, sim, "wages")
	# Through the sim, the working family ends up richer.
	var run = Sim.new(73)
	Scenario.starter(run)
	while run.tick < 3000 and run.unlocked_tier < 2:
		run.step(1)
	Scenario.complete_chain(run)
	var spare = _place_house(run)
	if spare != null:
		run.step(run.PAYDAY_TICKS * 3)
		t.check(run.buildings.values().any(func(b): return b.definition.kind == "house" and b.last_wage > 0), "Working families are paid through the sim")
	_money(t, run, "sim wages")

## A service pays each job at its class's wage.
func _services(t) -> void:
	var db = ContentDB.new()
	db.load_directory()
	t.check(Labour.service_pay(db.buildings.forester) == 10 and Economy.upkeep(db.buildings.forester) == 10, "A working-class service job pays 10 s a payday")
	var parson: Dictionary = db.buildings.chapel.duplicate(true)
	parson.jobs = {"middle":1}
	t.check(Labour.service_pay(parson) == 20 and Economy.upkeep(parson) == 20, "A parson's job pays 20 s a payday")

## Earnings round-trip; only houses earn.
func _snapshot(t) -> void:
	var sim = Sim.new(73)
	Scenario.starter(sim)
	sim.step(50)
	var house = _find(sim, "house")
	house.earned = 7
	sim.payroll += 7
	sim.treasury -= 7
	var state: Dictionary = sim.snapshot()
	var restored = Sim.from_snapshot(state)
	t.check(restored != null and restored.buildings[house.uid].earned == 7 and JSON.stringify(restored.snapshot()) == JSON.stringify(state), "A family's earnings round-trip")
	var broken: Dictionary = state.duplicate(true)
	for entry in broken.buildings:
		if entry.id == "well":
			entry.earned = 3
	t.check(Sim.from_snapshot(broken) == null, "Only a house can hold earnings")

## A middle-class house belongs to the middle class and pays it dues; on a site
## that does not interest the middle class, its first house brings it.
func _middle_class(t) -> void:
	var sim = Sim.new(73)
	Scenario.starter(sim)
	var house = _find(sim, "house")
	_make_middle(house)
	sim.step(1)
	t.check(house.aligned == "middle" and house.pull_leader.is_empty(), "A middle-class house belongs to the middle class at once")
	house.last_wage = 100
	house.last_tax = 15
	house.silver += 500
	sim.treasury -= 500
	var coffers: int = sim.factions.coffers.middle
	sim.factions.payday(sim)
	t.check(sim.factions.coffers.middle == coffers + 4 and sim.factions.last_payday.middle.dues == 4, "It pays 5%% dues on its 85 s wage after tax: %d" % (sim.factions.coffers.middle - coffers))
	_money(t, sim, "middle-class dues")
	var site = Sites.first_bread(SeededRNG.new(73))
	site.biome = "marsh"
	var marsh = Sim.new(73, null, site)
	Scenario.starter(marsh)
	t.check(not marsh.factions.present("middle"), "A marsh site does not interest the middle class")
	_make_middle(_find(marsh, "house"))
	marsh.step(1)
	t.check(marsh.factions.present("middle") and _find(marsh, "house").aligned == "middle", "Its first middle-class house brings it")
	_money(t, marsh, "middle-class arrival")
	# A working-class house is never simply given to a faction.
	var villager = Sim.new(73)
	Scenario.starter(villager)
	var homestead = _find(villager, "house")
	homestead.tier = 2
	villager.step(1)
	t.check(homestead.aligned.is_empty() and villager.factions.class_faction(villager, homestead).is_empty(), "A Villager house stays unaligned until a side wins it")

## A house's family is drawn once from its row's ranges, the same in every
## replay, and saved.
func _families(t) -> void:
	var db = ContentDB.new()
	db.load_directory()
	db.buildings.house.family = {"adults":[1,2], "children":[0,3]}
	var sim = Sim.new(73, db)
	Scenario.starter(sim)
	var extra = _place_house(sim)
	sim.step(1)
	var houses: Array = sim.buildings.values().filter(func(b): return b.definition.kind == "house")
	t.check(extra != null and houses.all(func(h): return h.adults >= 1 and h.adults <= 2 and h.children >= 0 and h.children <= 3), "Each family is drawn within its house's ranges")
	var workers := Labour.FOUNDERS
	for house in houses:
		workers += house.adults
	t.check(sim.workforce() == workers, "The workforce is the founders and every family's adults: %d" % workers)
	var again = Sim.new(73, db)
	Scenario.starter(again)
	_place_house(again)
	again.step(1)
	t.check(houses.all(func(h): return again.buildings[h.uid].adults == h.adults and again.buildings[h.uid].children == h.children), "A replay draws the same families")
	var restored = Sim.from_snapshot(sim.snapshot(), db)
	t.check(restored != null and JSON.stringify(restored.snapshot()) == JSON.stringify(sim.snapshot()), "Families round-trip through a snapshot")

## Makes a house's family middle class, as a middle house type will.
func _make_middle(house) -> void:
	var row: Dictionary = house.definition.duplicate(true)
	row["class"] = "middle"
	house.definition = row

func _place_house(sim):
	var shift: Vector2i = Scenario.offset(sim)
	for cell in [Vector2i(21,23), Vector2i(15,15), Vector2i(24,23), Vector2i(12,22), Vector2i(15,22), Vector2i(26,18)]:
		if sim.place("house", cell + shift):
			return sim.buildings[sim.next_uid - 1]
	return null

func _find(sim, id: String):
	for building in sim.buildings.values():
		if building.definition.id == id:
			return building
	return null

func _money(t, sim, label: String) -> void:
	var money: int = sim.treasury + sim.payroll + sim.factions.total()
	for building in sim.buildings.values():
		money += building.silver
	t.check(money == Economy.FOUNDING_TREASURY + sim.outside_money, "%s conserves money: %d == %d + %d" % [label, money, Economy.FOUNDING_TREASURY, sim.outside_money])
