extends RefCounted
## Same public commands used by the playable start and headless fixture.
## Coordinates are the milestone 1 layout, shifted so its storehouse sits on the
## site's founding spot; on the milestone 1 map the shift is zero.
const LAYOUT_STOREHOUSE := Vector2i(17, 21)
## Four family cottages (docs/PLAN-job-classes.md: a house holds one family of
## 1–2 adults), about the ten workers the old homestead gave at founding.
const STARTER := [["storehouse",Vector2i(17,21)],["house",Vector2i(21,21)],["house",Vector2i(21,22)],["house",Vector2i(21,18)],["house",Vector2i(21,24)],["well",Vector2i(21,19)],["farm",Vector2i(12,18)],["woodcutter",Vector2i(24,21)]]
## The Villager chain the starter grows into at its first promotion, with two
## more cottages for its workers.
const CHAIN := [["mill",Vector2i(16,18)],["bakery",Vector2i(23,18)],["woodshed",Vector2i(18,19)],["house",Vector2i(18,23)],["house",Vector2i(18,24)]]

## Economy test village (docs/VILLAGERS.md §5.7): the starter and its chain,
## grown to eight homesteads with every public service and enough producers
## for eight Villager houses, so money is what is tested. Industry lines the
## main road west of the founding spot; a residential street runs north-east
## with the chapel in its middle and a second storehouse behind it. Per 200
## ticks at full morale, eight Villager houses eat 8 water, 8 staple and 8
## fuel; three bakeries also use 12 water.
##   3 farms 17 wheat > 3 mills 13 flour > 3 bakeries 12 bread (staple, need 8)
##   1 woodshed 13 firewood (fuel, need 8) from 7 logs; 3 woodcutters 9 logs
##   4 wells 32 water (need 20); 2 foresters replant
##   2 berry bushes feed Settlers until promotion
const ECONOMY_ROADS := [[Vector2i(28,20),Vector2i(39,20)],[Vector2i(27,10),Vector2i(27,19)],[Vector2i(28,15),Vector2i(41,15)],[Vector2i(28,10),Vector2i(41,10)]]
const ECONOMY_LAYOUT := [
	# West industry, along the entrance road.
	["farm",Vector2i(4,18)],["well",Vector2i(8,19)],["mill",Vector2i(10,18)],
	["woodcutter",Vector2i(0,21)],["forester",Vector2i(3,21)],["bakery",Vector2i(6,21)],
	["mill",Vector2i(9,21)],["well",Vector2i(11,21)],["farm",Vector2i(12,21)],["bakery",Vector2i(15,21)],
	["berry_bushes",Vector2i(25,18)],["berry_bushes",Vector2i(0,18)],["berry_bushes",Vector2i(2,18)],["well",Vector2i(27,21)],
	# Middle street: the chapel at its west end, then family cottages both sides.
	["chapel",Vector2i(28,12)],
	["house",Vector2i(30,14)],["house",Vector2i(32,14)],["house",Vector2i(34,14)],["house",Vector2i(36,14)],["house",Vector2i(38,14)],
	["house",Vector2i(28,16)],["house",Vector2i(30,16)],["house",Vector2i(32,16)],["house",Vector2i(34,16)],["house",Vector2i(36,16)],["house",Vector2i(38,16)],
	["house",Vector2i(40,14)],["house",Vector2i(40,16)],
	# North street: cottages, the inn's lodgers and two masters' families.
	["house",Vector2i(28,9)],["house",Vector2i(30,9)],["house",Vector2i(34,9)],["house",Vector2i(36,9)],["house",Vector2i(38,9)],
	["house",Vector2i(28,11)],["inn",Vector2i(32,11)],["master_house",Vector2i(35,11)],["master_house",Vector2i(37,11)],
	["house",Vector2i(40,9)],["house",Vector2i(40,11)],
	# Infill beside the founding cross and along the main road.
	["house",Vector2i(21,23)],["house",Vector2i(28,21)],["house",Vector2i(37,21)],
	# Behind the middle street: a second storehouse, a well and berries.
	["storehouse",Vector2i(29,18)],["well",Vector2i(33,19)],["well",Vector2i(34,19)],["berry_bushes",Vector2i(36,18)],["berry_bushes",Vector2i(38,18)],
	# Eastern forest.
	["woodcutter",Vector2i(30,21)],["forester",Vector2i(33,21)],
	# Hunters at the street ends: game is the cheap staple a village of
	# families leans on (docs/WILDLIFE.md).
	["hunter",Vector2i(42,10)],["hunter",Vector2i(42,15)],
]
## Faction halls change who owns what (docs/FACTIONS.md), so they are optional.
const ECONOMY_HALLS := [["union_hall",Vector2i(18,16)],["alehouse",Vector2i(21,16)]]
## Logs left in the storehouse once everything is built, as the starter leaves.
const ECONOMY_SPARE_LOGS := 60

static func offset(sim) -> Vector2i:
	return sim.site.founding_spot - LAYOUT_STOREHOUSE

static func starter(sim) -> bool:
	if not _starter_roads(sim):
		return false
	return _place_all(sim, STARTER)

static func complete_chain(sim) -> bool:
	return _place_all(sim, CHAIN)

static func _starter_roads(sim) -> bool:
	var shift := offset(sim)
	var roads: Array[Vector2i] = []
	roads.append_array(sim.site.entrance_road)
	for x in range(12, 28):
		roads.append(Vector2i(x, 20) + shift)
	for y in range(16, 25):
		roads.append(Vector2i(20, y) + shift)
	return sim.place_road(roads)

static func _place_all(sim, entries: Array) -> bool:
	for entry in entries:
		if not sim.place(entry[0], entry[1] + offset(sim)):
			sim.last_error = "%s at %s: %s" % [entry[0], entry[1], sim.last_error]
			return false
	return true

## Every building of the economy test village, in placement order. Placement
## order is staffing order, so the starter's buildings keep their crews first.
static func economy_entries(halls: bool = false) -> Array:
	var entries: Array = STARTER + CHAIN + ECONOMY_LAYOUT
	if halls:
		entries += ECONOMY_HALLS
	return entries

## Logs added to the founding supplies so the whole village is built from
## them, with ECONOMY_SPARE_LOGS left over.
static func economy_supplies(sim, halls: bool = false) -> int:
	var logs := ECONOMY_SPARE_LOGS
	for entry in economy_entries(halls):
		logs += int(sim.db.buildings[entry[0]].cost.get("logs", 0))
	return maxi(0, logs - sim.reserve.count("logs"))

## Builds the economy test village on a fresh sim. Villager buildings are
## unlocked at once; houses still start as Settlers and promote on their own.
## Founding logs are topped up so construction costs no treasury silver beyond
## each building's working money. Storehouses go last, since a storehouse
## takes the founding supplies into stock, where the treasury must buy them.
static func economy_test(sim, halls: bool = false) -> bool:
	if not sim.valid:
		return false
	sim.reserve.add("logs", economy_supplies(sim, halls))
	sim.reserve.add("planks", economy_planks(sim, halls))
	# Family houses are many and small (docs/PLAN-job-classes.md). The founding
	# treasury pays the grants of the eight houses the village had before
	# families; the rest arrive as outside money, so money stays conserved.
	var grants: int = maxi(0, economy_houses(halls) - 8) * sim.economy.capital(sim, sim.db.buildings.house)
	sim.treasury += grants
	sim.outside_money += grants
	sim.unlocked_tier = maxi(sim.unlocked_tier, 2)
	if not _starter_roads(sim):
		return false
	for stroke in ECONOMY_ROADS:
		var cells: Array[Vector2i] = []
		var from: Vector2i = stroke[0]
		var to: Vector2i = stroke[1]
		var step := (to - from).sign()
		var cell := from
		while true:
			cells.append(cell + offset(sim))
			if cell == to:
				break
			cell += step
		if not sim.place_road(cells):
			return false
	var entries := economy_entries(halls)
	var stores := entries.filter(func(entry): return entry[0] == "storehouse")
	return _place_all(sim, entries.filter(func(entry): return entry[0] != "storehouse")) and _place_all(sim, stores)

## Houses of every type in the economy test village.
static func economy_houses(halls: bool = false) -> int:
	return economy_entries(halls).filter(func(entry): return entry[0] in ["house", "master_house", "inn"]).size()

## Planks the economy test village's buildings cost, given as founding supplies
## (the Master's houses and the inn are built from them).
static func economy_planks(sim, halls: bool = false) -> int:
	var planks := 0
	for entry in economy_entries(halls):
		planks += int(sim.db.buildings[entry[0]].cost.get("planks", 0))
	return planks
