extends RefCounted
## Faction data, presence and coffers (docs/PLAN-factions.md item 1), and
## ownership and income (item 2).
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const Economy = preload("res://sim/economy.gd")
const Factions = preload("res://sim/factions.gd")
const ContentDB = preload("res://sim/content_db.gd")
const WorldData = preload("res://sim/world/world_data.gd")
const Sites = preload("res://sim/world/sites.gd")
const SeededRNG = preload("res://sim/rng.gd")
const Campaign = preload("res://sim/campaign.gd")
const SAVE_DIRECTORY := "res://artifacts/campaign-test-saves"

func run(t) -> void:
	_data(t)
	_founding(t)
	_working_class(t)
	_harsh_sites(t)
	_no_factions(t)
	_snapshot(t)
	_long_run(t, 3000 if t.get("quick") == true else 18000)
	_buyers_data(t)
	_sales(t)
	_owner_share(t)
	_rent_and_dues(t)
	_excess(t)
	_demolition(t)
	_ownership_snapshot(t)
	_batch_sizes(t)
	# An hour of play is 36000 ticks.
	_owned_long_run(t, 3000 if t.get("quick") == true else 36000)
	# The contest for the working class (item 3).
	_contest_data(t)
	_halls(t)
	_hall_before_faction(t)
	_pull_terms(t)
	_joining(t)
	_leaving(t)
	_radius(t)
	_clustering(t)
	_settlers(t)
	_contest_snapshot(t)
	_contest_batches(t)
	# Whole-campaign saves are slow, so the quick tier skips them.
	if t.get("quick") != true:
		_legacy_save(t)

func _data(t) -> void:
	var db = ContentDB.new()
	t.check(db.load_directory() and db.factions.size() == 6, "Shipped faction data validates with six factions")
	var endowments := {}
	for id in db.factions:
		endowments[id] = int(db.factions[id].endowment)
	t.check(endowments == {"union":0,"populist":0,"middle":50,"industry":100,"gentry":200,"culture":0}, "Endowments: gentry 2 g, industry 1 g, middle 50 s")
	t.check(int(db.factions.union.dues_percent) == 5 and int(db.factions.populist.dues_percent) == 2, "Union and populist dues")
	t.check(not Factions.in_villages(db.factions.culture), "The cultural elite is a town faction")
	t.check(db.tiers[1]["class"] == "" and db.tiers[2]["class"] == "working", "Settlers have no class; Villagers are working class")
	t.check(db.biome_factions.heartland == ["gentry","middle"] and db.biome_factions.marsh.is_empty() and db.biome_factions.ocean.is_empty(), "Biomes name the factions they interest")
	var world = WorldData.new()
	t.check(world.load_directory(), "World data validates biome factions against factions.json")
	# validate() replaces the rows, so each case starts from fresh copies.
	var goods: Array = db.goods.values().duplicate(true)
	var buildings: Array = db.buildings.values().duplicate(true)
	var tiers: Array = db.tiers.values().duplicate(true)
	var factions: Array = db.factions.values().duplicate(true)
	var biomes: Array = world.biomes.values().duplicate(true)
	var cases := [
		["faction", "endowment", -5, "Reject a negative endowment"],
		["faction", "class", "clergy", "Reject an unknown class"],
		["faction", "rent", {"9":5}, "Reject rent for an unknown tier"],
		["faction", "stance", {"weather":1}, "Reject an unknown stance term"],
		["faction", "pledges", ["free_beer"], "Reject an unknown pledge type"],
		["tier", "class", "clergy", "Reject an unknown tier class"],
		["biome", "factions", ["culture"], "Reject a town faction in a biome's list"],
		["biome", "factions", ["union"], "Reject a recruiting faction in a biome's list"],
		["biome", "factions", ["dukes"], "Reject an unknown faction in a biome's list"],
	]
	for case in cases:
		var f: Array = factions.duplicate(true)
		var tr: Array = tiers.duplicate(true)
		var b: Array = biomes.duplicate(true)
		var rows: Array = f if case[0] == "faction" else (tr if case[0] == "tier" else b)
		rows[-1 if case[0] == "biome" else 0][case[1]] = case[2]
		t.check(not db.validate(goods.duplicate(true), buildings.duplicate(true), tr, f, b), case[3])
	var unsettled: Array = biomes.duplicate(true)
	unsettled[0].factions = ["gentry"]
	t.check(not world.validate(world.world, unsettled, world.deposits.values(), factions) and "cannot be settled" in "; ".join(world.errors), "World data rejects factions on a biome that cannot be settled")
	var unknown: Array = biomes.duplicate(true)
	unknown[-1].factions = ["dukes"]
	t.check(not world.validate(world.world, unknown, world.deposits.values(), factions) and "unknown faction dukes" in "; ".join(world.errors), "World data rejects an unknown biome faction")

## The default First Bread site is heartland: the gentry and the middle class
## arrive at founding, with their endowments.
func _founding(t) -> void:
	var sim = Sim.new(73)
	t.check(sim.site.biome == "heartland", "The default site is heartland")
	t.check(sim.factions.coffers == {"gentry":200,"middle":50}, "Heartland's factions arrive at founding with their endowments: %s" % str(sim.factions.coffers))
	t.check(sim.outside_money == 250 and sim.treasury == Economy.FOUNDING_TREASURY, "Endowments are outside money, not treasury gold")
	t.check(_has_event(sim, "Aristocrats") and _has_event(sim, "Middle class"), "Each arrival names its faction in the events")
	t.check(not sim.factions.present("union") and not sim.factions.present("populist"), "No working-class faction before the first Villager house")
	_money(t, sim, "founding")
	var hills = Sim.new(73, null, Sites.terraces())
	t.check(hills.factions.coffers.keys() == ["gentry","industry"] and hills.outside_money == 300, "Highland hills interest the gentry and the industrialists")

## Unions and populists arrive together when the first house becomes Villagers.
func _working_class(t) -> void:
	var db = ContentDB.new()
	db.load_directory()
	# A union endowment shows the trigger brings it like any other arrival.
	db.factions.union.endowment = 7
	var sim = Sim.new(73, db)
	Scenario.starter(sim)
	var arrived := -1
	while sim.tick < 3000 and arrived < 0:
		sim.step(1)
		if sim.factions.present("union"):
			arrived = sim.tick
	var promoted: bool = sim.unlocked_tier == 2
	t.check(arrived > 0 and promoted, "The unions arrive once a house is Villagers (tick %d)" % arrived)
	t.check(sim.factions.present("populist"), "The populists arrive with the unions")
	t.check(sim.factions.coffers.union == 7 and sim.factions.coffers.populist == 0 and sim.outside_money == 257, "The arrival brings each endowment into coffers and outside money")
	t.check(_has_event(sim, "Trade unions") and _has_event(sim, "Populists"), "Union and populist arrivals are announced")
	t.check(not sim.factions.present("culture"), "The cultural elite never arrives in a village")
	_money(t, sim, "working-class arrival")
	# Arrival is per tick, so it is the same across batch sizes.
	var a = Sim.new(73)
	var b = Sim.new(73)
	Scenario.starter(a)
	Scenario.starter(b)
	a.step(arrived + 5)
	for index in arrived + 5:
		b.step(1)
	t.check(a.factions.present("union") and JSON.stringify(a.snapshot()) == JSON.stringify(b.snapshot()), "Faction arrival is deterministic across tick batch sizes")

## A marsh site interests no middle-class or elite faction.
func _harsh_sites(t) -> void:
	var site = Sites.first_bread(SeededRNG.new(73))
	site.biome = "marsh"
	var sim = Sim.new(73, null, site)
	t.check(sim.factions.coffers.is_empty() and sim.outside_money == 0, "Marsh: nobody arrives at founding")
	Scenario.starter(sim)
	while sim.tick < 3000 and sim.unlocked_tier < 2:
		sim.step(1)
	sim.step(1)
	t.check(sim.factions.coffers.keys() == ["union","populist"], "Marsh: only the working-class factions arrive: %s" % str(sim.factions.coffers.keys()))
	for biome in sim.db.biome_factions:
		t.check("culture" not in sim.db.biome_factions[biome], "%s does not interest the cultural elite" % biome)

## Content without any factions still runs the full chain.
func _no_factions(t) -> void:
	var db = ContentDB.new()
	db.load_directory()
	t.check(db.validate(db.goods.values().duplicate(true), db.buildings.values().duplicate(true), db.tiers.values().duplicate(true)) and db.factions.is_empty(), "Content validates without faction rows")
	var sim = Sim.new(73, db)
	Scenario.starter(sim)
	while sim.tick < 3000 and sim.unlocked_tier < 2:
		sim.step(1)
	t.check(Scenario.complete_chain(sim), "No factions: the chain unlocks")
	sim.step(3000)
	t.check(sim.factions.coffers.is_empty() and sim.outside_money == 0, "No factions: nobody arrives")
	t.check(int(sim.produced.get("bread", 0)) > 0, "No factions: the village still makes bread")
	_money(t, sim, "no factions")

func _snapshot(t) -> void:
	var sim = Sim.new(73)
	Scenario.starter(sim)
	while sim.tick < 3000 and not sim.factions.present("union"):
		sim.step(1)
	sim.factions.coffers.union = 12
	sim.outside_money += 12
	var state: Dictionary = sim.snapshot()
	t.check(state.factions.keys() == ["gentry","middle","union","populist"] and state.outside_money == 262, "The snapshot holds the factions in order of arrival and the outside money")
	var restored = Sim.from_snapshot(state)
	t.check(restored != null and JSON.stringify(restored.snapshot()) == JSON.stringify(state), "Factions and outside money round-trip through a snapshot")
	if restored != null:
		sim.step(600)
		restored.step(600)
		t.check(JSON.stringify(restored.snapshot()) == JSON.stringify(sim.snapshot()), "A restored village continues identically")
	for tamper in [["dukes", {"coffers":5}, "an unknown faction"], ["culture", {"coffers":0}, "a town faction"], ["middle", {"coffers":-1}, "negative coffers"], ["middle", {"coffers":5,"favour":0}, "unknown faction fields"]]:
		var broken: Dictionary = state.duplicate(true)
		broken.factions[tamper[0]] = tamper[1]
		t.check(Sim.from_snapshot(broken) == null, "Snapshots with %s are rejected" % tamper[2])
	var broken: Dictionary = state.duplicate(true)
	broken.erase("outside_money")
	t.check(Sim.from_snapshot(broken) == null, "Snapshots without outside money are rejected")

## The money invariant holds for a growing village with every faction present.
func _long_run(t, ticks: int) -> void:
	var sim = Sim.new(73)
	Scenario.starter(sim)
	while sim.tick < 3000 and sim.unlocked_tier < 2:
		sim.step(1)
	var shift: Vector2i = Scenario.offset(sim)
	Scenario.complete_chain(sim)
	sim.place("house", Vector2i(21,23) + shift)
	var held := true
	var end: int = sim.tick + ticks
	while sim.tick < end:
		sim.step(97)
		held = held and _total(sim) == Economy.FOUNDING_TREASURY + sim.outside_money
	t.check(held and sim.factions.coffers.size() == 4, "Money is conserved with coffers and outside money over %d ticks" % ticks)
	_money(t, sim, "long run")

## A version-one save from before factions has no outside money. Loading it
## founds the village again, so heartland's factions arrive with their
## endowments, and the Villager house brings the unions and populists on the
## next tick.
func _legacy_save(t) -> void:
	var sim = Sim.new(73)
	Scenario.starter(sim)
	while sim.tick < 3000 and sim.unlocked_tier < 2:
		sim.step(1)
	var campaign = Campaign.new()
	campaign.generate("Pre-faction hearth", 73)
	var site := Campaign._state(sim.site)
	var grid := Campaign._state(sim.grid)
	for key in ["footprint","seed_value","world_coord","hex_width","world_origin","owner_coords","generation_error","promised_water","playability_result","districts"]:
		site.erase(key)
		grid.erase(key)
	var buildings: Array = []
	for building in sim.buildings.values():
		buildings.append({"id":building.definition.id,"state":Campaign._state(building),
			"input":building.input.items,"output":building.output.items,"inventory":building.inventory.items})
	var carriers: Array = []
	for carrier in sim.carriers:
		carriers.append(Campaign._state(carrier))
	var sim_state := Campaign._state(sim)
	sim_state.erase("outside_money")
	# Before factions, no arrival was announced. The loaded save's events
	# replace the founding ones, so its founding factions have no "arrived"
	# event; item 6 (saves) may add one on migration.
	var events: Array[String] = []
	for event in sim.events:
		if "arrived" not in event:
			events.append(event)
	sim_state.events = events
	var payload := {"version":1,"id":"faction-legacy-test","name":"Pre-faction hearth","seed":73,
		"generator":campaign.world.generator_version,"content":Campaign._content_hash(),
		"village_name":"Old clearing","village_hex":campaign.world.start,
		"village":{"sim":sim_state,"site":site,"grid":grid,"rng":sim.rng.state,
			"reserve":sim.reserve.items,"buildings":buildings,"carriers":carriers}}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIRECTORY))
	var path := SAVE_DIRECTORY.path_join("faction-legacy-test.campaign")
	var bytes := var_to_bytes(payload)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var({"payload":bytes,"checksum":Campaign._hash(bytes)})
	file.close()
	var loaded = Campaign.new()
	t.check(loaded.load_save(path), "A save from before factions loads: " + loaded.last_error)
	if loaded.village != null:
		var village = loaded.village
		t.check(village.factions.coffers == {"gentry":200,"middle":50} and village.outside_money == 250, "A pre-faction save gets the site's factions with their endowments: %s" % str(village.factions.coffers))
		_money(t, village, "pre-faction save")
		village.step(1)
		t.check(village.factions.present("union") and village.factions.present("populist"), "Its Villager house brings the unions and populists on the next tick")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## `buyers` in buildings.json names known factions, never on a service or well.
func _buyers_data(t) -> void:
	var db = ContentDB.new()
	db.load_directory()
	var buyers := {}
	for id in db.buildings:
		if db.buildings[id].has("buyers"):
			buyers[id] = db.buildings[id].buyers
	t.check(buyers == {"house":["gentry"],"storehouse":["middle"],"farm":["gentry"],"woodcutter":["industry"],"mill":["industry"],"bakery":["industry"]}, "Buyers: houses and fields to the gentry, workshops to industry, storehouses to the middle class: %s" % str(buyers))
	var goods: Array = db.goods.values().duplicate(true)
	var tiers: Array = db.tiers.values().duplicate(true)
	var factions: Array = db.factions.values().duplicate(true)
	for case in [["mill",["dukes"],"Reject an unknown buyer"],["forester",["gentry"],"Reject buyers on a service"],["well",["gentry"],"Reject buyers on a well"],["road",["gentry"],"Reject buyers on a road"],["mill","industry","Reject buyers that are not an array"]]:
		var rows: Array = db.buildings.values().duplicate(true)
		for row in rows:
			if row.id == case[0]:
				row.buyers = case[1]
		t.check(not db.validate(goods.duplicate(true), rows, tiers.duplicate(true), factions.duplicate(true)), case[2])

## Selling Crown buildings: price, ownership and every refusal.
func _sales(t) -> void:
	var sim = _village()
	var house = _find(sim, "house")
	var mill = _find(sim, "mill")
	var store = _find(sim, "storehouse")
	t.check(house.tier == 2 and house.owner == "" and mill.owner == "", "Buildings start as the Crown's")
	t.check(sim.factions.book_value(sim, house, "gentry") == 12 * 10, "A Tier 2 house's book value is 12 paydays of 10 s rent")
	var farm = _find(sim, "farm")
	t.check(sim.factions.book_value(sim, mill, "industry") == 8 * sim.price("logs") + mill.silver and sim.factions.book_value(sim, farm, "gentry") == 4 * sim.price("logs") + farm.silver, "A workshop's book value is its logs at chain price plus its purse")
	t.check(sim.factions.book_value(sim, store, "middle") == 10 * sim.price("logs") + store.silver, "A storehouse's book value includes its trading purse")
	var row: Dictionary = sim.db.buildings.house.duplicate(true)
	var shack = load("res://sim/building.gd").new(999, row, Vector2i.ZERO)
	t.check(sim.factions.book_value(sim, shack, "gentry") == 12 * 5 and sim.factions.sale_price(sim, house, "gentry") == 120, "A Tier 1 house is worth 60 s; with no favour yet the price is book value")
	var treasury: int = sim.treasury
	var coffers: int = sim.factions.coffers.gentry
	var deals: int = sim.period.deals
	t.check(sim.sell_building(house.uid, "gentry"), "Sell a house to the gentry: " + sim.last_error)
	t.check(house.owner == "gentry" and sim.treasury == treasury + 120 and sim.factions.coffers.gentry == coffers - 120 and sim.period.deals == deals + 120, "The gentry pay 120 s from their coffers into the treasury as a deal")
	t.check(sim.events[-1] == Factions.BUILDING_SOLD % ["Aristocrats", "Homestead", "1 g 20 s", sim.tick], "The sale is announced")
	_money(t, sim, "house sale")
	var mill_silver: int = mill.silver
	var mill_price: int = sim.factions.sale_price(sim, mill, "industry")
	treasury = sim.treasury
	t.check(sim.sell_building(mill.uid, "industry") and mill.owner == "industry" and mill.silver == mill_silver and sim.treasury == treasury + mill_price, "Sell the mill to the industrialists; its purse stays in the building")
	_money(t, sim, "mill sale")
	var state: String = JSON.stringify(sim.snapshot())
	var refusals := [
		[9999, "gentry", "Unknown building", "An unknown building cannot be sold"],
		[store.uid, "culture", "No Cultural elite in the village", "A faction that is not present cannot buy"],
		[store.uid, "dukes", "No dukes in the village", "An unknown faction cannot buy"],
		[house.uid, "gentry", "Homestead already belongs to the Aristocrats", "A building is sold only once"],
		[store.uid, "gentry", "The Aristocrats do not buy a Storehouse", "Only the building's buyers may buy it"],
		[_find(sim, "well").uid, "gentry", "Well is not for sale", "Wells are never sold"],
	]
	var chapel = _place_anywhere(sim, "chapel")
	t.check(chapel != null, "Place a chapel")
	if chapel != null:
		refusals.append([chapel.uid, "gentry", "Chapel is not for sale", "Services are never sold"])
	state = JSON.stringify(sim.snapshot())
	# The middle class's 50 s cannot buy a storehouse with its trading purse.
	refusals.append([store.uid, "middle", "The Middle class cannot pay " + Economy.format(sim.factions.sale_price(sim, store, "middle")), "The middle class cannot afford a storehouse"])
	for case in refusals:
		t.check(not sim.sell_building(case[0], case[1]) and sim.last_error == case[2], "%s: %s" % [case[3], sim.last_error])
	t.check(JSON.stringify(sim.snapshot()) == state, "A refused sale changes nothing")
	# The gentry have 80 s left; a second Tier 2 house costs 120 s.
	var second = _place_house(sim)
	if second != null:
		second.tier = 2
	t.check(second != null and not sim.sell_building(second.uid, "gentry") and sim.last_error == "The Aristocrats cannot pay 1 g 20 s", "A faction cannot pay more than its coffers: " + sim.last_error)
	_money(t, sim, "refused sales")

## The owner's share of a producer's labour and of a storehouse's markup.
func _owner_share(t) -> void:
	var sim = _village()
	var mill = _find(sim, "mill")
	var bakery = _find(sim, "bakery")
	var store = _find(sim, "storehouse")
	var house = _find(sim, "house")
	_endow(sim, "middle", sim.factions.sale_price(sim, store, "middle"))
	t.check(sim.sell_building(mill.uid, "industry") and sim.sell_building(store.uid, "middle"), "Sell the mill and the storehouse: " + sim.last_error)
	var labour := int(sim.economy.labour.flour)
	var sales := 7
	_fund(sim, bakery, sales * sim.price("flour"))
	var payroll: int = sim.payroll
	var wages: int = mill.wages_paid
	var coffers: int = sim.factions.coffers.industry
	for index in sales:
		sim.economy.settle(sim, bakery, mill.uid, "flour")
	var share: int = sales * labour * 20 / 100
	t.check(share > 0 and sim.factions.coffers.industry == coffers + share and sim.factions.period.industry.owner_share == share, "The industrialists take 20%% of the mill's labour: %d s of %d s" % [share, sales * labour])
	t.check(sim.payroll == payroll + sales * labour - share and mill.wages_paid == wages + sales * labour - share, "The rest of the labour still pays wages")
	t.check(mill.owner_work == sales * labour, "The mill keeps its running total of labour sold since the sale")
	var margin: int = sim.economy.retail_price(sim, "bread") - sim.price("bread")
	_fund(sim, house, sales * sim.economy.retail_price(sim, "bread"))
	payroll = sim.payroll
	coffers = sim.factions.coffers.middle
	var store_silver: int = store.silver
	for index in sales:
		sim.economy.settle(sim, house, store.uid, "bread")
	share = sales * margin * 20 / 100
	t.check(share > 0 and sim.factions.coffers.middle == coffers + share and sim.payroll == payroll + sales * margin - share, "The middle class takes 20%% of the storehouse markup: %d s of %d s" % [share, sales * margin])
	t.check(store.silver == store_silver + sales * sim.price("bread"), "The storehouse still keeps the chain price")
	# A sale to a workshop has no markup, so the storehouse's owner takes nothing.
	coffers = sim.factions.coffers.middle
	_fund(sim, bakery, sim.price("water"))
	sim.economy.settle(sim, bakery, store.uid, "water")
	t.check(sim.factions.coffers.middle == coffers, "A chain-price sale gives the owner nothing")
	_money(t, sim, "owner's share")

## Rent and dues at payday, and a storehouse's surplus going to its owner.
func _rent_and_dues(t) -> void:
	var sim = _village()
	var house = _find(sim, "house")
	t.check(sim.sell_building(house.uid, "gentry"), "Sell the house to the gentry")
	house.aligned = "union"
	house.last_wage = 100
	house.last_tax = 15
	_fund(sim, house, 500)
	var silver: int = house.silver
	var gentry: int = sim.factions.coffers.gentry
	var union: int = sim.factions.coffers.union
	sim.factions.payday(sim)
	t.check(sim.factions.coffers.gentry == gentry + 10 and sim.factions.last_payday.gentry.rent == 10, "A rented Tier 2 house pays the gentry 10 s rent")
	t.check(sim.factions.coffers.union == union + 4 and sim.factions.last_payday.union.dues == 4, "A union house pays 5%% dues on its 85 s wage after tax, to the nearest silver: %d" % (sim.factions.coffers.union - union))
	t.check(house.silver == silver - 14 and sim.factions.period.gentry.rent == 0, "Both come out of the household's savings, and a new period starts")
	house.aligned = "populist"
	var populist: int = sim.factions.coffers.populist
	sim.factions.payday(sim)
	t.check(sim.factions.coffers.populist == populist + 2 and sim.factions.last_payday.populist.dues == 2 and sim.factions.last_payday.union.dues == 0, "A populist house pays 2%% penny dues")
	# Rent never takes more than the household can spend.
	house.aligned = ""
	house.silver += 3 - sim.spendable(house)
	_balance(sim)
	gentry = sim.factions.coffers.gentry
	sim.factions.payday(sim)
	t.check(sim.factions.coffers.gentry == gentry + 3 and sim.spendable(house) == 0, "Rent is capped at what the household has")
	_money(t, sim, "rent and dues")
	# Through the real payday, wages and tax come first, then dues.
	house.aligned = "union"
	_fund(sim, house, 300)
	sim.step(sim.PAYDAY_TICKS - sim.tick % sim.PAYDAY_TICKS)
	var wage: int = house.last_wage - house.last_tax
	t.check(wage > 0 and sim.factions.last_payday.union.dues == (wage * 5 + 50) / 100, "Payday takes dues from the wage just paid: %d s of %d s" % [sim.factions.last_payday.union.dues, wage])
	_money(t, sim, "payday dues")
	# A middle-class storehouse's surplus goes to its owner, not the treasury.
	var store = _find(sim, "storehouse")
	_endow(sim, "middle", sim.factions.sale_price(sim, store, "middle"))
	t.check(sim.sell_building(store.uid, "middle"), "Sell the storehouse to the middle class")
	var cap: int = sim.economy.purse_cap(sim, store)
	_fund(sim, store, cap + 37 - store.silver)
	var before: int = sim.factions.period.middle.owner_share
	sim.economy.payday(sim)
	t.check(store.silver == cap and sim.ledger[-1].trade == 0 and sim.factions.last_payday.middle.owner_share == before + 37, "A middle-class storehouse's surplus goes to its owner")
	_money(t, sim, "owner's surplus")

## Coffers above the cap: relief from recruiting factions, purchases from others.
func _excess(t) -> void:
	var sim = _village()
	var first = _find(sim, "house")
	var second = _place_house(sim)
	var cap := int(sim.db.factions.union.coffer_cap)
	_endow(sim, "union", cap + 6 - sim.factions.coffers.union)
	# The older house is further short, so the newer one is helped first.
	var shorts := [5, 4]
	var houses := [first, second]
	for index in 2:
		var house = houses[index]
		house.aligned = "union"
		house.last_wage = 0
		house.last_tax = 0
		house.silver += Factions.basket(sim, house.tier) - shorts[index] - sim.spendable(house)
	_balance(sim)
	var outsider = _place_house(sim)
	outsider.silver += -sim.spendable(outsider)
	_balance(sim)
	sim.factions.payday(sim)
	t.check(sim.spendable(second) == Factions.basket(sim, second.tier), "Relief covers a member house's whole shortfall, the smallest first")
	t.check(sim.spendable(first) == Factions.basket(sim, first.tier) - 3 and sim.factions.coffers.union == cap, "Relief never pays out more than the excess over the cap")
	t.check(sim.spendable(outsider) == 0 and sim.factions.last_payday.union.relief == 6, "Unaligned houses get no union relief")
	_money(t, sim, "relief")
	# The gentry spend their excess on goods from a storehouse, at chain price.
	var store = _find(sim, "storehouse")
	var gentry_cap := int(sim.db.factions.gentry.coffer_cap)
	_endow(sim, "gentry", gentry_cap + 50 - sim.factions.coffers.gentry)
	var store_silver: int = store.silver
	var stock: int = store.inventory.total()
	var consumed := 0
	for good in sim.consumed:
		consumed += int(sim.consumed[good])
	var initial := _goods(sim)
	sim.factions.payday(sim)
	var spent: int = gentry_cap + 50 - sim.factions.coffers.gentry
	var eaten := 0
	for good in sim.consumed:
		eaten += int(sim.consumed[good])
	t.check(spent > 0 and spent <= 50 and sim.factions.last_payday.gentry.purchases == spent and store.silver == store_silver + spent, "The gentry buy %d s of goods from the storehouse with their excess" % spent)
	t.check(stock - store.inventory.total() == eaten - consumed and eaten > consumed, "The goods they buy are consumed")
	var after := _goods(sim)
	var balanced := true
	for good in sim.db.goods:
		balanced = balanced and initial[good] - after[good] == int(sim.consumed.get(good, 0)) - int(initial["_consumed_" + good])
	t.check(balanced, "Goods are conserved through faction purchases")
	_money(t, sim, "purchases")

## Demolishing a faction's workshop returns its purse to the faction.
func _demolition(t) -> void:
	var sim = _village()
	var mill = _find(sim, "mill")
	var house = _find(sim, "house")
	t.check(sim.sell_building(mill.uid, "industry") and sim.sell_building(house.uid, "gentry"), "Sell the mill and the house")
	var purse: int = mill.silver
	var treasury: int = sim.treasury
	var refunds: int = sim.period.refunds
	var coffers: int = sim.factions.coffers.industry
	t.check(purse > 0 and sim.demolish(mill.cell), "Demolish the industrialists' mill")
	t.check(sim.factions.coffers.industry == coffers + purse and sim.treasury == treasury and sim.period.refunds == refunds, "Its purse returns to the industrialists, not the treasury")
	_money(t, sim, "demolished mill")
	var savings: int = house.silver
	t.check(sim.demolish(house.cell) and sim.treasury == treasury + savings and sim.factions.coffers.gentry == 80, "A rented house's savings are the household's, so they go to the treasury")
	_money(t, sim, "demolished rented house")

## Owners, alignment and flows round-trip; bad ones are rejected.
func _ownership_snapshot(t) -> void:
	var sim = _village()
	var house = _find(sim, "house")
	var mill = _find(sim, "mill")
	sim.sell_building(house.uid, "gentry")
	sim.sell_building(mill.uid, "industry")
	house.aligned = "union"
	_fund(sim, house, 300)
	sim.step(sim.PAYDAY_TICKS + 50)
	var state: Dictionary = sim.snapshot()
	t.check(state.factions.gentry.last_payday.rent == 10 and state.factions.union.has("period"), "The snapshot holds each faction's flows")
	var restored = Sim.from_snapshot(state)
	t.check(restored != null and JSON.stringify(restored.snapshot()) == JSON.stringify(state), "Owners, alignment and faction flows round-trip through a snapshot")
	if restored != null:
		sim.step(600)
		restored.step(600)
		t.check(JSON.stringify(restored.snapshot()) == JSON.stringify(sim.snapshot()), "A restored village with owned buildings continues identically")
	var index_of := {}
	for index in state.buildings.size():
		index_of[state.buildings[index].id] = index
	for tamper in [["mill", "owner", "dukes", "an unknown owner"], ["well", "owner", "gentry", "an owned well"], ["mill", "aligned", "union", "an aligned workshop"], ["house", "aligned", "dukes", "an unknown alignment"], ["farm", "owner", "culture", "an owner not in the village"], ["mill", "owner_work", -1, "negative owner work"]]:
		var broken: Dictionary = state.duplicate(true)
		broken.buildings[index_of[tamper[0]]][tamper[1]] = tamper[2]
		t.check(Sim.from_snapshot(broken) == null, "Snapshots with %s are rejected" % tamper[3])
	var broken: Dictionary = state.duplicate(true)
	broken.factions.gentry.last_payday.rent = -1
	t.check(Sim.from_snapshot(broken) == null, "Snapshots with negative faction flows are rejected")
	broken = state.duplicate(true)
	broken.factions.gentry.period.erase("dues")
	t.check(Sim.from_snapshot(broken) == null, "Snapshots with missing faction flows are rejected")
	broken = state.duplicate(true)
	broken.period.erase("deals")
	t.check(Sim.from_snapshot(broken) == null, "Snapshots without the deals ledger key are rejected")

## Owned buildings, rent and dues give the same result across tick batch sizes.
func _batch_sizes(t) -> void:
	var a = _owned_village()
	var b = _owned_village()
	if a == null or b == null:
		t.check(false, "Set up two owned villages")
		return
	for index in 1300:
		a.step(1)
	b.step(1300)
	t.check(JSON.stringify(a.snapshot()) == JSON.stringify(b.snapshot()), "Faction income is the same across tick batch sizes")

## An hour with a sold house, mill and storehouse, a union house and a populist
## house: money and goods are conserved at every check.
func _owned_long_run(t, ticks: int) -> void:
	var sim = _owned_village()
	if sim == null:
		t.check(false, "Set up an owned village")
		return
	var initial := _goods(sim)
	var held := true
	var income := {}
	var end: int = sim.tick + ticks
	while sim.tick < end:
		sim.step(97)
		held = held and _total(sim) == Economy.FOUNDING_TREASURY + sim.outside_money
		for id in sim.factions.last_payday:
			for key in sim.factions.last_payday[id]:
				income[id + "." + key] = maxi(int(income.get(id + "." + key, 0)), int(sim.factions.last_payday[id][key]))
	t.check(held, "Money is conserved over %d ticks with owned buildings" % ticks)
	_money(t, sim, "owned long run")
	t.check(income.get("gentry.rent", 0) > 0 and income.get("industry.owner_share", 0) > 0 and income.get("middle.owner_share", 0) > 0 and income.get("union.dues", 0) > 0, "Every income stream paid during the run: %s" % str(income))
	var after := _goods(sim)
	var balanced := true
	for good in sim.db.goods:
		var expected: int = initial[good] + int(sim.produced.get(good, 0)) - int(initial.get("_produced_" + good, 0)) - (int(sim.consumed.get(good, 0)) - int(initial.get("_consumed_" + good, 0))) - (int(sim.destroyed.get(good, 0)) - int(initial.get("_destroyed_" + good, 0)))
		balanced = balanced and after[good] == expected
	t.check(balanced, "Goods are conserved over the owned run")
	if ticks >= 36000:
		print("FACTIONS HOUR: coffers %s; treasury %s; tier %d; most per payday %s" % [str(sim.factions.coffers), Economy.format(sim.treasury), sim.unlocked_tier, str(income)])

## Halls and pull weights in the shipped data, and content that gets them wrong.
func _contest_data(t) -> void:
	var db = ContentDB.new()
	db.load_directory()
	t.check(db.buildings.union_hall.kind == "hall" and db.buildings.union_hall.recruits_for == "union" and db.buildings.alehouse.recruits_for == "populist", "The union hall and the alehouse are halls recruiting for their factions")
	t.check(int(db.buildings.union_hall.radius) == 8 and int(db.buildings.alehouse.unlock_tier) == 2 and "union_hall" in db.tiers[2].unlocks and "alehouse" in db.tiers[2].unlocks, "Halls unlock with Villagers and reach 8 road tiles")
	t.check(db.factions.union.pull.employment == 10 and db.factions.populist.pull.idle_cap == 5 and not db.factions.middle.has("pull"), "Recruiting factions carry pull weights in factions.json")
	var goods: Array = db.goods.values().duplicate(true)
	var tiers: Array = db.tiers.values().duplicate(true)
	var cases := [
		["faction", "union", "pull", {"employment":-1}, "Reject a negative pull weight"],
		["faction", "union", "pull", {"employment":1.5}, "Reject a fractional pull weight"],
		["faction", "populist", "pull", {"charisma":2}, "Reject an unknown pull term"],
		["faction", "populist", "pull", {"markup_step":0}, "Reject a zero markup step"],
		["faction", "union", "pull", {}, "Reject a recruiting faction without pull weights"],
		["faction", "middle", "pull", {"hall":1}, "Reject pull weights on a faction that does not recruit"],
		["building", "union_hall", "recruits_for", "dukes", "Reject a hall recruiting for an unknown faction"],
		["building", "union_hall", "recruits_for", "middle", "Reject a hall recruiting for a faction that does not recruit"],
		["building", "union_hall", "recruits_for", "", "Reject a hall recruiting for nobody"],
		["building", "alehouse", "radius", 0, "Reject a hall without a radius"],
		["building", "alehouse", "workers", 2, "Reject a hall with workers"],
		["building", "alehouse", "outputs", {"bread":1}, "Reject a hall with outputs"],
		["building", "alehouse", "buyers", ["gentry"], "Reject a hall with buyers"],
		["building", "mill", "recruits_for", "union", "Reject recruits_for on a workshop"],
	]
	for case in cases:
		var rows: Array = (db.factions if case[0] == "faction" else db.buildings).values().duplicate(true)
		for row in rows:
			if row.id == case[1]:
				row[case[2]] = case[3]
		var buildings: Array = rows if case[0] == "building" else db.buildings.values().duplicate(true)
		var factions: Array = rows if case[0] == "faction" else db.factions.values().duplicate(true)
		t.check(not db.validate(goods.duplicate(true), buildings, tiers.duplicate(true), factions), case[4])
	db.load_directory()
	t.check(Factions.new().has_method("pull") and db.OWNABLE_KINDS.has("hall"), "Halls are a kind a faction can own")

## A hall is inert: no workers, goods, carriers or money of its own. It belongs
## to its faction from the start and is never sold.
func _halls(t) -> void:
	var sim = _village()
	var treasury: int = sim.treasury
	var price: int = sim.economy.construction_price(sim, sim.db.buildings.union_hall)
	var hall = _place_at(sim, "union_hall", [Vector2i(18,23), Vector2i(21,23), Vector2i(21,16)])
	t.check(hall != null, "Place a union hall")
	if hall == null:
		return
	t.check(hall.owner == "union" and hall.silver == 0 and sim.treasury == treasury - price, "A union hall belongs to the unions at once and costs only its logs: %s" % Economy.format(price))
	var alehouse = _place_at(sim, "alehouse", [Vector2i(21,16), Vector2i(18,16), Vector2i(26,21)])
	t.check(alehouse != null and alehouse.owner == "populist", "An alehouse belongs to the populists")
	var idle: int = sim.idle_workers
	sim.step(1)
	t.check(sim.idle_workers == idle, "Halls take no workers")
	var touched := false
	var staffed := false
	for index in 1200:
		sim.step(1)
		staffed = staffed or hall.staffed or alehouse.staffed
		for carrier in sim.carriers:
			touched = touched or int(carrier.job.get("source", -1)) in [hall.uid, alehouse.uid] or int(carrier.job.get("target", -1)) in [hall.uid, alehouse.uid]
	t.check(not staffed and not touched, "Halls are never staffed and never a carrier's source or destination")
	t.check(hall.silver == 0 and alehouse.silver == 0 and hall.input.total() + hall.output.total() + hall.inventory.total() == 0 and hall.last_wage == 0, "Halls hold no silver or goods and are never paid")
	_money(t, sim, "halls")
	t.check(not sim.set_workers_enabled(hall.uid, false) and not sim.set_priority(hall.uid, 2), "A hall has no workers to stop or prioritise")
	t.check(not sim.sell_building(hall.uid, "union") and not sim.sell_building(alehouse.uid, "gentry"), "Halls are never for sale: " + sim.last_error)
	var coffers: int = sim.factions.coffers.union
	treasury = sim.treasury
	t.check(sim.demolish(hall.cell) and sim.factions.coffers.union == coffers and sim.treasury == treasury, "Demolishing a hall moves no silver")
	_money(t, sim, "demolished hall")

## A hall built before its faction arrives stays the Crown's, then passes to
## the faction when it comes.
func _hall_before_faction(t) -> void:
	var sim = Sim.new(73)
	Scenario.starter(sim)
	# Unlocks outlive demotion, so Villager buildings can exist with no Villagers.
	sim.unlocked_tier = 2
	var hall = _place_at(sim, "union_hall", [Vector2i(18,23), Vector2i(21,23)])
	var alehouse = _place_at(sim, "alehouse", [Vector2i(21,16), Vector2i(18,16), Vector2i(26,21)])
	t.check(hall != null and alehouse != null and hall.owner == "" and alehouse.owner == "", "A hall built before its faction arrives is the Crown's")
	if hall == null or alehouse == null:
		return
	var state: Dictionary = sim.snapshot()
	t.check(Sim.from_snapshot(state) != null, "A Crown hall round-trips through a snapshot")
	while sim.tick < 3000 and not sim.factions.present("union"):
		sim.step(1)
	t.check(hall.owner == "union" and alehouse.owner == "populist", "Each hall passes to its faction when the faction arrives")
	_money(t, sim, "hall before faction")

## Each pull term from the shipped weights, one at a time.
func _pull_terms(t) -> void:
	var sim = _village()
	var house = _find(sim, "house")
	house.happiness_history = [100, 100, 100]
	house.last_wage = 0
	sim.idle_workers = 0
	sim.markup_percent = 10
	var workforce: int = sim.workforce()
	t.check(sim.factions.pull(sim, house, "union") == 10 and sim.factions.pull(sim, house, "populist") == 0, "Full employment: union 10, populist 0 (%d, %d)" % [sim.factions.pull(sim, house, "union"), sim.factions.pull(sim, house, "populist")])
	sim.idle_workers = 3
	t.check(sim.factions.pull(sim, house, "populist") == 3 and sim.factions.pull(sim, house, "union") == 10 * (workforce - 3) / workforce, "Each idle worker adds 1 to the populists and takes the union's employment share")
	sim.idle_workers = 12
	t.check(sim.factions.pull(sim, house, "populist") == 5, "Idle workers count up to 5")
	sim.idle_workers = 0
	house.happiness_history = [50, 50, 50]
	t.check(Factions.needs_unmet(sim, house) == 2 and sim.factions.pull(sim, house, "populist") == 4, "Settled at 50%% of four needs: two unmet, 4 populist pull")
	house.happiness_history = []
	t.check(Factions.needs_unmet(sim, house) == 0, "No needs count as unmet before the first full cycle")
	sim.markup_percent = 30
	t.check(sim.factions.pull(sim, house, "populist") == 4, "A 30%% markup adds (30 − 10) ÷ 5 to the populists")
	sim.markup_percent = 14
	t.check(sim.factions.pull(sim, house, "populist") == 0, "A markup within 5 points of 10%% adds nothing")
	sim.markup_percent = 10
	var workers := int(sim.db.tiers[house.tier].workers_per_house)
	house.last_wage = Economy.WAGE * workers
	t.check(Factions.wages_in_full(sim, house) and sim.factions.pull(sim, house, "union") == 13, "A full wage for each employed worker adds 3 to the unions")
	house.last_wage -= 1
	t.check(not Factions.wages_in_full(sim, house), "One silver short is not in full")
	house.last_wage = 0
	t.check(sim.factions.pull(sim, house, "union", true) == 12, "Union relief this payday adds 2")

## Joining: a lead of 3 for 5 paydays running; a broken streak starts again.
func _joining(t) -> void:
	var sim = _contest_village({"hall":3}, {"hall":0})
	var house = _find(sim, "house")
	var hall = _place_at(sim, "union_hall", [Vector2i(18,23), Vector2i(21,23)])
	t.check(hall != null and sim.grid.distance(hall, house) >= 0, "A union hall by the house's road")
	if hall == null:
		return
	_paydays(sim, 4)
	t.check(house.aligned == "" and house.pull_leader == "union" and house.pull_streak == 4 and sim.factions.last_pulls(house) == {"union":3,"populist":0}, "A lead of 3 for four paydays is a streak of 4, not yet a member")
	t.check(Factions.paydays_to_change(house) == 1, "The inspector can say it joins in 1 payday")
	_paydays(sim, 1)
	t.check(house.aligned == "union" and house.pull_streak == 0 and house.pull_leader == "", "On the fifth payday the house joins the unions")
	t.check(sim.events[-1] == Factions.HOUSE_JOINED % ["Trade unions", sim.tick], "Joining is announced")
	# A lead of 2 never wins a house.
	var second = _contest_village({"hall":2}, {"hall":0})
	var other = _find(second, "house")
	_place_at(second, "union_hall", [Vector2i(18,23), Vector2i(21,23)])
	_paydays(second, 12)
	t.check(other.aligned == "" and other.pull_streak == 0, "A lead of 2 is not enough")
	# A streak that breaks starts again.
	var third = _contest_village({"hall":3}, {"hall":0})
	var house3 = _find(third, "house")
	var hall3 = _place_at(third, "union_hall", [Vector2i(18,23), Vector2i(21,23)])
	_paydays(third, 4)
	third.db.factions.union.pull = {"hall":2}
	_paydays(third, 1)
	t.check(house3.pull_streak == 0 and house3.aligned == "", "One payday without the lead ends the streak")
	third.db.factions.union.pull = {"hall":3}
	_paydays(third, 4)
	t.check(house3.aligned == "" and house3.pull_streak == 4, "The streak counts from the start again")
	_paydays(third, 1)
	t.check(house3.aligned == "union" and hall3 != null, "And joins after five more")
	_money(t, third, "joining")

## Leaving: a member goes to a rival only after it leads by 6 for 10 paydays.
func _leaving(t) -> void:
	var sim = _contest_village({}, {"hall":6})
	var house = _find(sim, "house")
	house.aligned = "union"
	var alehouse = _place_at(sim, "alehouse", [Vector2i(18,23), Vector2i(21,23)])
	t.check(alehouse != null, "An alehouse by the union house")
	if alehouse == null:
		return
	_paydays(sim, 9)
	t.check(house.aligned == "union" and house.pull_leader == "populist" and house.pull_streak == 9, "A rival leading by 6 for nine paydays has not won the house yet")
	_paydays(sim, 1)
	t.check(house.aligned == "populist" and house.pull_streak == 0, "On the tenth payday the house goes over to the populists")
	t.check(sim.events[-1] == Factions.HOUSE_SWITCHED % ["Trade unions", "Populists", sim.tick], "Switching sides is announced")
	# A lead of 5 never moves a member, though it would win an unaligned house.
	var second = _contest_village({}, {"hall":5})
	var member = _find(second, "house")
	member.aligned = "union"
	_place_at(second, "alehouse", [Vector2i(18,23), Vector2i(21,23)])
	_paydays(second, 15)
	t.check(member.aligned == "union" and member.pull_streak == 0, "A rival lead of 5 does not move a member")
	member.aligned = ""
	_paydays(second, 5)
	t.check(member.aligned == "populist", "The same lead wins an unaligned house")
	_money(t, second, "leaving")

## A hall pulls houses within its radius by road, and none beyond it.
func _radius(t) -> void:
	for id in ["union_hall", "alehouse"]:
		var faction: String = "union" if id == "union_hall" else "populist"
		var sim = _contest_village({"hall":4}, {"hall":4})
		var house = _find(sim, "house")
		var hall = _place_at(sim, id, [Vector2i(18,23), Vector2i(21,23)])
		if hall == null:
			t.check(false, "Place a " + id)
			continue
		var cells: int = sim.grid.distance(hall, house)
		sim.db.buildings[id].radius = cells
		t.check(cells > 0 and Factions.hall_in_reach(sim, house, faction) and sim.factions.pull(sim, house, faction) == 4, "%s: a house %d road tiles away is within a radius of %d" % [id, cells, cells])
		sim.db.buildings[id].radius = cells - 1
		t.check(not Factions.hall_in_reach(sim, house, faction) and sim.factions.pull(sim, house, faction) == 0, "%s: and outside a radius of %d" % [id, cells - 1])
		var rival: String = "populist" if faction == "union" else "union"
		sim.db.buildings[id].radius = 8
		t.check(not Factions.hall_in_reach(sim, house, rival), "%s pulls only for its own faction" % id)
		# A hall with no road reaches nobody.
		var cut = _contest_village({"hall":4}, {"hall":4})
		var lonely = _place_at(cut, id, [Vector2i(30,30), Vector2i(31,10), Vector2i(8,30), Vector2i(10,10)], false)
		t.check(lonely == null or not Factions.hall_in_reach(cut, _find(cut, "house"), faction), "%s: a hall off the road network pulls nobody" % id)

## Aligned neighbours within 6 tiles pull, up to 3; further houses do not.
func _clustering(t) -> void:
	var sim = _contest_village({"neighbour":1, "neighbour_cap":3}, {"neighbour":1, "neighbour_cap":3})
	var house = _find(sim, "house")
	var near: Array = []
	for cell in [Vector2i(21,23), Vector2i(18,23), Vector2i(21,16), Vector2i(18,16), Vector2i(26,21)]:
		var placed = _place_at(sim, "house", [cell])
		if placed != null:
			placed.tier = 2
			near.append(placed)
	var far = _place_at(sim, "house", [Vector2i(12,21), Vector2i(10,22), Vector2i(9,21)])
	if far != null:
		far.tier = 2
	t.check(near.size() >= 4 and far != null, "Place four houses near the first and one further away (%d near)" % near.size())
	if near.size() < 4 or far == null:
		return
	var within := 0
	for other in near:
		within += 1 if Factions.gap(house, other) <= Factions.NEIGHBOUR_TILES else 0
	t.check(within == near.size() and Factions.gap(house, far) > Factions.NEIGHBOUR_TILES, "The near houses are within 6 tiles, the far one beyond (%d)" % Factions.gap(house, far))
	near[0].aligned = "union"
	t.check(sim.factions.pull(sim, house, "union") == 1 and sim.factions.pull(sim, house, "populist") == 0, "One union neighbour pulls 1")
	for other in near:
		other.aligned = "union"
	t.check(sim.factions.pull(sim, house, "union") == 3, "Neighbours pull at most 3")
	for other in near:
		other.aligned = ""
	far.aligned = "union"
	t.check(sim.factions.pull(sim, house, "union") == 0, "A union house 8 tiles away does not pull")
	# Three union neighbours win the house: a union street.
	far.aligned = ""
	for index in 3:
		near[index].aligned = "union"
	_paydays(sim, 5)
	t.check(house.aligned == "union", "Three union neighbours bring the house into the unions")
	t.check(far.aligned == "", "A house beyond the street stays unaligned")
	_money(t, sim, "clustering")

## Settlers are never recruited, and a house that falls back to Settlers leaves.
func _settlers(t) -> void:
	var sim = _contest_village({"hall":10}, {"hall":0})
	var house = _find(sim, "house")
	_place_at(sim, "union_hall", [Vector2i(18,23), Vector2i(21,23)])
	var settler = _place_at(sim, "house", [Vector2i(21,23), Vector2i(18,16), Vector2i(21,16)])
	t.check(settler != null and settler.tier == 1, "A Settlers house")
	if settler == null:
		return
	if Factions.hall_in_reach(sim, settler, "union") == false:
		sim.db.buildings.union_hall.radius = 40
	_paydays(sim, 10)
	t.check(house.aligned == "union", "The Villager house joins the unions")
	t.check(settler.aligned == "" and settler.pull_streak == 0 and sim.factions.last_pulls(settler).is_empty(), "A Settlers house beside a union hall is never recruited")
	# Demotion to Settlers ends the membership and any streak, at once.
	house.tier = 1
	house.pull_leader = "populist"
	house.pull_streak = 3
	sim.step(1)
	t.check(house.aligned == "" and house.pull_leader == "" and house.pull_streak == 0, "A house that falls back to Settlers loses its alignment and streak")
	t.check(_has_text(sim, Factions.HOUSE_LAPSED % ["Trade unions", "Settlers", sim.tick]), "Its leaving is announced")
	_money(t, sim, "settlers")

## The contest's state round-trips mid-streak; impossible states are rejected.
func _contest_snapshot(t) -> void:
	var sim = _contest_village({"hall":3}, {"hall":0})
	var house = _find(sim, "house")
	var hall = _place_at(sim, "union_hall", [Vector2i(18,23), Vector2i(21,23)])
	var second = _place_at(sim, "house", [Vector2i(21,16), Vector2i(18,16), Vector2i(26,21)])
	if hall == null or second == null:
		t.check(false, "Set up the contest snapshot village")
		return
	second.tier = 2
	second.aligned = "populist"
	sim.step(sim.PAYDAY_TICKS * 2 - sim.tick % sim.PAYDAY_TICKS)
	var state: Dictionary = sim.snapshot()
	var index_of := {}
	for index in state.buildings.size():
		index_of[int(state.buildings[index].uid)] = index
	var entry: Dictionary = state.buildings[index_of[house.uid]]
	t.check(entry.pull_leader == "union" and entry.pull_streak == 2, "The snapshot holds a house mid-streak (%s %d)" % [entry.pull_leader, entry.pull_streak])
	var restored = Sim.from_snapshot(state)
	t.check(restored != null and JSON.stringify(restored.snapshot()) == JSON.stringify(state), "A streak round-trips through a snapshot")
	if restored != null:
		sim.step(sim.PAYDAY_TICKS * 4)
		restored.step(sim.PAYDAY_TICKS * 4)
		t.check(JSON.stringify(restored.snapshot()) == JSON.stringify(sim.snapshot()) and restored.buildings[house.uid].aligned == "union", "A restored village finishes the streak identically")
	var tampers := [
		[house.uid, {"pull_streak":5}, "a finished joining streak"],
		[house.uid, {"pull_streak":-1}, "a negative streak"],
		[house.uid, {"pull_streak":0}, "a leader with no streak"],
		[house.uid, {"pull_leader":"", "pull_streak":2}, "a streak with no leader"],
		[house.uid, {"pull_leader":"middle"}, "a streak toward a faction that does not recruit"],
		[house.uid, {"pull_leader":"dukes"}, "a streak toward an unknown faction"],
		[second.uid, {"pull_leader":"populist", "pull_streak":1}, "a streak toward the house's own faction"],
		[second.uid, {"pull_leader":"union", "pull_streak":10}, "a finished leaving streak"],
		[second.uid, {"tier":1}, "an aligned Settlers house"],
		[hall.uid, {"owner":"populist"}, "a union hall owned by the populists"],
		[hall.uid, {"owner":"gentry"}, "a hall owned by a faction that does not recruit"],
		[hall.uid, {"pull_leader":"union", "pull_streak":1}, "a streak on a hall"],
	]
	for tamper in tampers:
		var broken: Dictionary = state.duplicate(true)
		for key in tamper[1]:
			broken.buildings[index_of[tamper[0]]][key] = tamper[1][key]
		t.check(Sim.from_snapshot(broken) == null, "Snapshots with %s are rejected" % tamper[2])
	var legal: Dictionary = state.duplicate(true)
	legal.buildings[index_of[second.uid]].pull_leader = "union"
	legal.buildings[index_of[second.uid]].pull_streak = 9
	t.check(Sim.from_snapshot(legal) != null, "A member nine paydays into a rival's lead is a valid state")
	var crown: Dictionary = state.duplicate(true)
	crown.buildings[index_of[hall.uid]].owner = ""
	t.check(Sim.from_snapshot(crown) != null, "A Crown hall is a valid state")

## The contest gives the same result across tick batch sizes, with real
## weights, halls of both kinds and several houses.
func _contest_batches(t) -> void:
	var a = _contest_setup()
	var b = _contest_setup()
	if a == null or b == null:
		t.check(false, "Set up two contest villages")
		return
	for index in 3000:
		a.step(1)
	b.step(1000)
	b.step(1)
	b.step(1999)
	var members := 0
	for house in a.buildings.values():
		members += 1 if not house.aligned.is_empty() else 0
	t.check(members > 0, "Houses join a side within 3000 ticks with a union hall and an alehouse (%d members)" % members)
	t.check(JSON.stringify(a.snapshot()) == JSON.stringify(b.snapshot()), "The contest is the same across tick batch sizes")
	var held := true
	var end: int = a.tick + (2000 if t.get("quick") == true else 12000)
	while a.tick < end:
		a.step(97)
		held = held and _total(a) == Economy.FOUNDING_TREASURY + a.outside_money
	t.check(held, "Money is conserved through the contest")
	_money(t, a, "contest")

func _contest_setup():
	var sim = _village()
	if _place_at(sim, "union_hall", [Vector2i(18,23)]) == null or _place_at(sim, "alehouse", [Vector2i(21,16)]) == null:
		return null
	for cell in [Vector2i(21,23), Vector2i(26,21), Vector2i(18,16)]:
		_place_at(sim, "house", [cell])
	_place_anywhere(sim, "chapel")
	return sim

## _village with the recruiting factions' pull weights replaced, so a test
## controls every term.
func _contest_village(union_pull: Dictionary, populist_pull: Dictionary):
	var db = ContentDB.new()
	db.load_directory()
	db.factions.union.pull = union_pull
	db.factions.populist.pull = populist_pull
	var sim = Sim.new(73, db)
	Scenario.starter(sim)
	while sim.tick < 3000 and sim.unlocked_tier < 2:
		sim.step(1)
	sim.step(1)
	Scenario.complete_chain(sim)
	return sim

## Runs the factions' payday alone, so the village itself stands still.
func _paydays(sim, count: int) -> void:
	for index in count:
		sim.factions.payday(sim)

## Places a building at the first of these layout cells (shifted to the site)
## that takes it, by default only where it has a road.
func _place_at(sim, id: String, cells: Array, need_road: bool = true):
	var shift: Vector2i = Scenario.offset(sim)
	for cell in cells:
		if sim.placement_error(id, cell + shift).is_empty() and sim.place(id, cell + shift):
			var building = sim.buildings[sim.next_uid - 1]
			if not need_road or not sim.grid.access(building).is_empty():
				return building
			sim.demolish(building.cell)
	return null

func _has_text(sim, text: String) -> bool:
	return text in sim.events

## Heartland with the industrialists added, at Villagers with the full chain.
func _village():
	var db = ContentDB.new()
	db.load_directory()
	db.biome_factions.heartland = ["gentry","middle","industry"]
	var sim = Sim.new(73, db)
	Scenario.starter(sim)
	while sim.tick < 3000 and sim.unlocked_tier < 2:
		sim.step(1)
	sim.step(1)
	Scenario.complete_chain(sim)
	return sim

## _village with a second house, the first sold to the gentry and aligned with
## the unions, the second with the populists, the mill sold to industry and the
## storehouse to the middle class (given the silver to buy it).
func _owned_village():
	var sim = _village()
	var house = _find(sim, "house")
	var second = _place_house(sim)
	var store = _find(sim, "storehouse")
	_endow(sim, "middle", sim.factions.sale_price(sim, store, "middle"))
	if second == null or not sim.sell_building(house.uid, "gentry") or not sim.sell_building(_find(sim, "mill").uid, "industry") or not sim.sell_building(store.uid, "middle"):
		return null
	house.aligned = "union"
	second.aligned = "populist"
	return sim

func _place_house(sim):
	var shift: Vector2i = Scenario.offset(sim)
	for cell in [Vector2i(21,23), Vector2i(15,15), Vector2i(24,23), Vector2i(12,22), Vector2i(15,22), Vector2i(26,18)]:
		if sim.place("house", cell + shift):
			return sim.buildings[sim.next_uid - 1]
	return _place_anywhere(sim, "house")

## Places a building on the first free spot near the village, scanning rows.
func _place_anywhere(sim, id: String):
	var shift: Vector2i = Scenario.offset(sim)
	for y in range(8, 34):
		for x in range(6, 34):
			if sim.placement_error(id, Vector2i(x, y) + shift).is_empty() and sim.place(id, Vector2i(x, y) + shift):
				return sim.buildings[sim.next_uid - 1]
	return null

func _find(sim, id: String):
	for building in sim.buildings.values():
		if building.definition.id == id:
			return building
	return null

## Gives a faction outside silver, as a test-only endowment.
func _endow(sim, id: String, amount: int) -> void:
	sim.factions.coffers[id] = int(sim.factions.coffers[id]) + amount
	sim.outside_money += amount

## Moves treasury silver to a building, keeping the total.
func _fund(sim, building, amount: int) -> void:
	building.silver += amount
	sim.treasury -= amount

## Takes any silver tests added to buildings by hand back out of the treasury
## (or returns it), so the money total holds.
func _balance(sim) -> void:
	sim.treasury += Economy.FOUNDING_TREASURY + sim.outside_money - _total(sim)

## Units of each good held anywhere, with the produced, consumed and destroyed
## counters at the time (as "_produced_<good>" and so on).
func _goods(sim) -> Dictionary:
	var result := {}
	for good in sim.db.goods:
		var count: int = sim.reserve.count(good)
		for building in sim.buildings.values():
			count += building.input.count(good) + building.output.count(good) + building.inventory.count(good)
		for carrier in sim.carriers:
			if carrier.cargo == good:
				count += 1
		result[good] = count
		for key in ["produced","consumed","destroyed"]:
			result["_%s_%s" % [key, good]] = int(sim.get(key).get(good, 0))
	return result

func _total(sim) -> int:
	var money: int = sim.treasury + sim.payroll + sim.factions.total()
	for building in sim.buildings.values():
		money += building.silver
	return money

func _money(t, sim, label: String) -> void:
	t.check(_total(sim) == Economy.FOUNDING_TREASURY + sim.outside_money, "%s conserves money: %d == %d + %d" % [label, _total(sim), Economy.FOUNDING_TREASURY, sim.outside_money])

func _has_event(sim, faction_name: String) -> bool:
	for event in sim.events:
		if faction_name in event and "arrived" in event:
			return true
	return false
