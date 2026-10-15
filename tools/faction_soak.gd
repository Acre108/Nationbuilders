extends SceneTree
## Faction soak (PLAN-factions.md item 8) on the economy test village
## (Scenario.economy_test). Prints, per sampled minute: Villager houses by
## alignment, the mean union and populist pull on unaligned houses, each
## present faction's favour and coffers, and offers made so far. Headless:
##   Godot.exe --headless --path . --script tools/faction_soak.gd -- [--minutes=60] [--seed=73]
##       [--every=5] [--halls] [--biome=marsh] [--sell-houses] [--accept=union] [--accept=all]
## --split-halls puts the union hall at the west end of the north-east street and
## the alehouse at its east end, so each reaches about half its houses.
## --sell-houses sells every house the gentry can afford at each payday.
## --rent=T1,T2 overrides every faction's rent per tier, in silver per payday.
## --accept=<faction>|all accepts that faction's offers as they come
## (organising offers are skipped: they need a hall placed).
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const Economy = preload("res://sim/economy.gd")
const Sites = preload("res://sim/world/sites.gd")
const SeededRNG = preload("res://sim/rng.gd")
const ContentDB = preload("res://sim/content_db.gd")
const TICKS_PER_MINUTE := 600

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var minutes := 60
	var seed_value := 73
	var every := 5
	var biome := ""
	var accept := ""
	var args := OS.get_cmdline_user_args()
	for argument in args:
		if argument.begins_with("--minutes="): minutes = int(argument.get_slice("=", 1))
		elif argument.begins_with("--seed="): seed_value = int(argument.get_slice("=", 1))
		elif argument.begins_with("--every="): every = maxi(1, int(argument.get_slice("=", 1)))
		elif argument.begins_with("--biome="): biome = argument.get_slice("=", 1)
		elif argument.begins_with("--accept="): accept = argument.get_slice("=", 1)
	var site = null
	if not biome.is_empty():
		site = Sites.first_bread(SeededRNG.new(seed_value))
		site.biome = biome
	var db = ContentDB.new()
	db.load_directory()
	for argument in args:
		if argument.begins_with("--rent="):
			var rents := argument.get_slice("=", 1).split(",")
			for id in db.factions:
				db.factions[id].rent = {"1":int(rents[0]), "2":int(rents[1])}
	var sim = Sim.new(seed_value, db, site)
	if not Scenario.economy_test(sim, "--halls" in args):
		printerr("Economy village failed: " + sim.last_error)
		quit(1)
		return
	var sell := "--sell-houses" in args
	if "--split-halls" in args:
		var shift: Vector2i = Scenario.offset(sim)
		for entry in [["union_hall",[Vector2i(25,15),Vector2i(25,13),Vector2i(25,17)]],["alehouse",[Vector2i(40,15),Vector2i(40,14),Vector2i(40,19)]]]:
			var placed := false
			for cell in entry[1]:
				if sim.place(entry[0],cell + shift):
					placed = true
					print("%s at %s" % [entry[0],cell])
					break
			if not placed:
				printerr("Could not place %s: %s" % [entry[0],sim.last_error])
	print("Faction soak: seed %d, %s, halls %s, split halls %s, sell houses %s, accept %s" % [seed_value, sim.site.biome, "--halls" in args, "--split-halls" in args, sell, accept if not accept.is_empty() else "none"])
	print("min | houses: unaligned/union/populist | pull u/p | " + "  ".join(_faction_headers(sim)))
	var offers := 0
	var accepted := 0
	var deals := 0
	var seen_offers := {}
	for minute in range(1, minutes + 1):
		for tick in TICKS_PER_MINUTE:
			sim.step(1)
			if sim.tick % sim.PAYDAY_TICKS != 0:
				continue
			for id in sim.factions.offers:
				var offer: Dictionary = sim.factions.offers[id]
				if offer.is_empty():
					continue
				var key := "%s%d" % [id, int(offer.expires)]
				if not seen_offers.has(key):
					seen_offers[key] = true
					offers += 1
				if (accept == id or accept == "all") and offer.type != "organise":
					var before: int = sim.treasury
					if sim.accept_offer(id):
						accepted += 1
						deals += sim.treasury - before
			if sell:
				for building in sim.buildings.values():
					if building.definition.kind == "house" and building.owner.is_empty():
						var before: int = sim.treasury
						if sim.sell_building(building.uid, "gentry"):
							deals += sim.treasury - before
		if minute % every == 0 or minute == minutes:
			print(_row(sim, minute, offers))
	print("== SUMMARY ==")
	print("offers made %d, accepted %d, silver from deals %s (%s per 20 minutes)" % [offers, accepted, Economy.format(deals), Economy.format(deals * 20 / maxi(1, minutes))])
	for id in sim.factions.coffers:
		var terms: Dictionary = sim.factions.stance_terms(sim, id)
		var parts: Array[String] = []
		for term in terms:
			if int(terms[term]) != 0:
				parts.append("%s %d" % [term, int(terms[term])])
		print("%-9s favour %4d target %4d  %s" % [id, int(sim.factions.favour[id]), sim.factions.target(sim, id), ", ".join(parts)])
	quit(0)

func _faction_headers(sim) -> Array[String]:
	var result: Array[String] = []
	for id in sim.db.factions:
		if sim.db.factions[id].settlements.has("village"):
			result.append("%s fav/coffers" % id)
	return result

func _row(sim, minute: int, offers: int) -> String:
	var counts := {"": 0, "union": 0, "populist": 0}
	var pull_sum := {"union": 0, "populist": 0}
	var unaligned := 0
	for house in sim.buildings.values():
		if house.definition.kind != "house" or str(sim.db.tiers[house.tier].get("class", "")).is_empty():
			continue
		counts[house.aligned] = int(counts.get(house.aligned, 0)) + 1
		if house.aligned.is_empty():
			var pulls: Dictionary = sim.factions.last_pulls(house)
			unaligned += 1
			for id in pull_sum:
				pull_sum[id] += int(pulls.get(id, 0))
	var parts: Array[String] = []
	for id in sim.db.factions:
		if not sim.db.factions[id].settlements.has("village"):
			continue
		if sim.factions.present(id):
			parts.append("%4d / %-8s" % [int(sim.factions.favour[id]), Economy.format(int(sim.factions.coffers[id]))])
		else:
			parts.append("%15s" % "absent")
	var pulls := "%.1f/%.1f" % [float(pull_sum.union) / maxi(1, unaligned), float(pull_sum.populist) / maxi(1, unaligned)]
	return "%3d | %2d / %2d / %2d | %9s | %s | offers %d" % [minute, counts[""], counts.union, counts.populist, pulls, "  ".join(parts), offers]
