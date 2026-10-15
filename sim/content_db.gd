extends RefCounted
## Validated content only. No global class cache or scene tree is required.
## Build menu categories, in display order.
const TERRAINS := ["grass", "forest", "rock", "marsh", "sand", "water", "stream", "river", "lake", "ocean"]
const CATEGORIES := {"housing":"Housing", "logistics":"Logistics", "resources":"Resources", "food":"Food"}
## Terrains a fisher or dyer may stand beside (`adjacent_terrain`); matches Grid.WATER.
const WATER_TERRAINS := ["water", "stream", "river", "lake", "ocean"]
## Goods categories (docs/SUPPLY_CHAINS.md §3). A tier need may name a category
## instead of a good; any good listed in it meets the need.
const GOOD_CATEGORIES := {"basic":"Basic food", "staple":"Staple food", "fuel":"Fuel", "cloth":"Cloth", "masonry":"Masonry", "comfort":"Comfort"}
## Social classes of factions and house tiers; Settlers have none ("").
const CLASSES := ["", "working", "middle", "elite"]
const SETTLEMENTS := ["village", "town"]
## Stance table rows a faction's favour reads (docs/FACTIONS.md §4, village rows).
const STANCE_TERMS := ["tax", "markup", "idle_workers", "unpaid_public_workers", "rent", "houses_sold", "buildings_owned", "happiness", "woodland_lost", "strikes_riots", "union_power", "populist_power"]
## Pledge types a faction can pay for (docs/FACTIONS.md §5.2).
const PLEDGES := ["tax_cap", "public_workers_paid", "no_house_sales", "no_workplace_stopped", "markup_cap", "no_new_union_hall", "markup_floor", "no_buy_backs", "workshop_staffed", "woodland_kept", "no_workshop_near_rented", "school_built"]
## Buildings that stay common property and are never sold, like services
## (docs/FACTIONS.md §5.1).
const COMMON := ["well"]
## Building kinds. A hall (a union hall or an alehouse) has no workers, goods
## or money of its own; it recruits nearby working-class houses for its faction
## (docs/FACTIONS.md §3.1).
const KINDS := ["producer", "house", "storehouse", "road", "hall"]
## Building kinds a faction may own.
const OWNABLE_KINDS := ["house", "producer", "storehouse", "hall"]
## Pull terms a recruiting faction's `pull` weights may name (FACTIONS.md §3.1;
## factions.gd reads them). Caps and steps are whole numbers too.
## Job classes a building's jobs may name (docs/PLAN-job-classes.md).
const JOB_CLASSES := ["working", "middle", "elite"]
const PULL_TERMS := ["employment", "wages_in_full", "hall", "neighbour", "neighbour_cap", "relief", "idle_worker", "idle_cap", "need_unmet", "markup_over", "markup_step"]
var goods: Dictionary = {}
var buildings: Dictionary = {}
var tiers: Dictionary = {}
## Derived: each goods category's goods, in goods.json order.
var category_goods: Dictionary = {}
## Faction rows by id, and the factions each biome's sites interest.
var factions: Dictionary = {}
var biome_factions: Dictionary = {}
var errors: Array[String] = []

func load_directory(path: String = "res://data") -> bool:
	var rows: Array = []
	for filename in ["goods.json", "buildings.json", "tiers.json", "factions.json", "biomes.json"]:
		var file := FileAccess.open(path.path_join(filename), FileAccess.READ)
		if file == null:
			errors = ["Cannot open " + path.path_join(filename)]
			push_error(errors[0])
			return false
		var parser := JSON.new()
		if parser.parse(file.get_as_text()) != OK:
			errors = ["Invalid JSON in %s: %s" % [filename, parser.get_error_message()]]
			push_error(errors[0])
			return false
		rows.append(parser.data)
	var valid := validate(rows[0], rows[1], rows[2], rows[3], rows[4])
	if not valid:
		push_error("Content validation failed: " + "; ".join(errors))
	return valid

## Without faction rows the content has no factions, and a village runs with
## none present. Biome rows are read only for their `factions`.
func validate(good_rows: Variant, building_rows: Variant, tier_rows: Variant, faction_rows: Variant = null, biome_rows: Variant = null) -> bool:
	errors.clear()
	goods.clear()
	buildings.clear()
	tiers.clear()
	category_goods.clear()
	factions.clear()
	biome_factions.clear()
	_index(good_rows, goods, "goods", false)
	_index(building_rows, buildings, "buildings", false)
	_index(tier_rows, tiers, "tiers", true)
	for category in GOOD_CATEGORIES:
		category_goods[category] = []
	for id in goods:
		if not goods[id].get("name", "") is String or goods[id].get("name", "").is_empty():
			errors.append("Good %s needs a name" % id)
		if not goods[id].get("color", "") is String or not Color.html_is_valid(goods[id].get("color", "")):
			errors.append("Good %s needs a valid color" % id)
		if goods[id].has("price") and not _integer(goods[id].price, 0):
			errors.append("Good %s: price must be whole silver" % id)
		if GOOD_CATEGORIES.has(id):
			errors.append("Good %s: id clashes with a goods category" % id)
		var categories: Variant = goods[id].get("categories", [])
		if not categories is Array:
			errors.append("Good %s: categories must be an array" % id)
			continue
		for category in categories:
			if not GOOD_CATEGORIES.has(category):
				errors.append("Good %s: unknown category %s" % [id, str(category)])
			elif id in category_goods[category]:
				errors.append("Good %s: category %s listed twice" % [id, category])
			else:
				category_goods[category].append(id)
	for id in buildings:
		var row: Dictionary = buildings[id]
		var prefix := "Building %s: " % id
		var previous_errors := errors.size()
		if not row.get("name", "") is String or row.get("name", "").is_empty():
			errors.append(prefix + "name is required")
		var footprint: Variant = row.get("footprint")
		if not footprint is Array or footprint.size() != 2:
			errors.append(prefix + "footprint must have two positive integers")
		elif not _integer(footprint[0], 1) or not _integer(footprint[1], 1):
			errors.append(prefix + "invalid footprint")
		if row.get("kind", "") not in KINDS:
			errors.append(prefix + "unknown kind")
		if row.get("category", "") not in CATEGORIES:
			errors.append(prefix + "unknown category")
		for field in ["workers", "cycle_ticks", "unlock_tier", "input_capacity", "output_capacity"]:
			if not _integer(row.get(field), 0 if field in ["workers", "cycle_ticks"] else 1):
				errors.append(prefix + "invalid " + field)
		for field in ["cost", "inputs", "outputs"]:
			_goods_map(row.get(field), prefix + field)
		# Do not evaluate derived rules on malformed types.
		if errors.size() > previous_errors:
			continue
		if not tiers.has(int(row.get("unlock_tier", -1))):
			errors.append(prefix + "unknown unlock tier")
		if row.has("forest_action"):
			if row.kind != "producer" or row.forest_action not in ["cut","plant"] or not _integer(row.get("work_radius"),1):
				errors.append(prefix + "invalid forestry job or work radius")
			if not row.inputs.is_empty() or (row.forest_action == "plant" and not row.outputs.is_empty()):
				errors.append(prefix + "forestry must use trees rather than recipe inputs; planting has no goods output")
		# A hunter's lodge takes game, and a forager's hut wild berries, within
		# work_radius tiles (wildlife.gd, forage.gd).
		for job in ["hunts", "gathers"]:
			if row.has(job):
				if row[job] != true or row.kind != "producer" or row.has("forest_action") or (row.has("hunts") and row.has("gathers")) or not _integer(row.get("work_radius"),1):
					errors.append(prefix + "%s must be true, on a producer with a work radius and no other land job" % job)
				elif not row.inputs.is_empty() or row.outputs.is_empty():
					errors.append(prefix + "%s takes from the land rather than recipe inputs and yields goods" % ("hunting" if job == "hunts" else "gathering"))
		# A field works slower off its deposit (village_sim.deposit_speed).
		if row.has("deposit") or row.has("off_deposit_percent"):
			if not row.get("deposit") is String or row.get("deposit", "").is_empty() or not _integer(row.get("off_deposit_percent"), 1) or int(row.get("off_deposit_percent", 0)) > 100:
				errors.append(prefix + "deposit needs off_deposit_percent, a whole percentage from 1 to 100")
		if row.get("kind") == "producer" and (row.get("cycle_ticks", 0) < 1 or (row.get("outputs", {}).is_empty() and row.get("forest_action", "") != "plant" and not row.get("service", false))):
			errors.append(prefix + "producer needs a cycle and outputs")
		# A service that houses need ("provides", such as a chapel) covers houses
		# within service_radius road tiles.
		if row.has("provides"):
			if not row.provides is String or row.provides.is_empty() or row.provides == "shelter" or not row.get("service", false):
				errors.append(prefix + "provides must name a service, on a service building")
			if not _integer(row.get("service_radius"), 1):
				errors.append(prefix + "invalid service_radius")
		# Jobs by class (docs/PLAN-job-classes.md): whole counts that add up to
		# the row's workers. A storehouse's one job is its storekeeper's.
		if row.has("jobs"):
			if not row.jobs is Dictionary or row.jobs.is_empty() or row.jobs.keys().any(func(job_class): return job_class not in JOB_CLASSES) or row.jobs.values().any(func(count): return not _integer(count, 1)):
				errors.append(prefix + "jobs must map working, middle or elite to whole counts")
			else:
				var total := 0
				for count in row.jobs.values():
					total += int(count)
				if total != int(row.workers):
					errors.append(prefix + "jobs must add up to workers")
				if row.get("kind") == "storehouse" and total != 1:
					errors.append(prefix + "a storehouse has one job, its storekeeper's")
		# Public services sell nothing; the treasury pays their workers.
		if row.has("service") and not row.service is bool:
			errors.append(prefix + "service must be true or false")
		elif row.get("kind") == "producer" and row.get("outputs") is Dictionary:
			var sells_nothing: bool = row.outputs.is_empty() and int(row.get("workers", 0)) > 0
			if row.get("service", false) and not sells_nothing:
				errors.append(prefix + "a service employs workers and sells nothing")
			elif sells_nothing and not row.get("service", false):
				errors.append(prefix + "a producer that sells nothing must be a service")
		elif row.get("service", false):
			errors.append(prefix + "only producers can be services")
		# The factions that may buy this building (FACTIONS.md §5.1); the ids
		# are checked against factions.json in _validate_factions.
		if row.has("buyers"):
			if not row.buyers is Array or row.buyers.any(func(faction): return not faction is String):
				errors.append(prefix + "buyers must be an array of faction ids")
			elif not row.buyers.is_empty() and (row.get("service", false) or id in COMMON or row.get("kind") not in OWNABLE_KINDS):
				errors.append(prefix + "services, wells and roads are never for sale")
		if row.get("inputs") is Dictionary and _total(row.inputs) > row.get("input_capacity", 0):
			errors.append(prefix + "recipe exceeds input capacity")
		if row.get("outputs") is Dictionary and _total(row.outputs) > row.get("output_capacity", 0):
			errors.append(prefix + "recipe exceeds output capacity")
		if row.get("kind") == "storehouse":
			for field in ["storage_capacity", "good_limit", "carriers"]:
				if not _integer(row.get(field), 1):
					errors.append(prefix + "invalid " + field)
			# Every good keeps room for its full limit, so surplus never crowds out bread.
			if _integer(row.get("good_limit"), 1) and _integer(row.get("storage_capacity"), 1) and int(row.good_limit) * goods.size() > int(row.storage_capacity):
				errors.append(prefix + "good_limit × %d goods exceeds storage_capacity" % goods.size())
		# A hall is inert apart from recruiting: no workers, goods or buyers.
		if row.get("kind") == "hall":
			if int(row.workers) != 0 or not row.inputs.is_empty() or not row.outputs.is_empty() or int(row.cycle_ticks) != 0:
				errors.append(prefix + "a hall has no workers, inputs, outputs or cycle")
			if not _integer(row.get("radius"), 1):
				errors.append(prefix + "a hall needs a whole radius of at least 1")
			if not row.get("recruits_for") is String or row.get("recruits_for", "").is_empty():
				errors.append(prefix + "a hall needs recruits_for, a recruiting faction")
			if row.has("buyers") or row.has("service") or row.has("provides"):
				errors.append(prefix + "a hall is never sold and is not a service")
		elif row.has("recruits_for") or row.has("radius"):
			errors.append(prefix + "only halls have recruits_for and radius")
		_validate_house_type(row, prefix)
		if not row.get("terrain") is Array or row.get("terrain", []).is_empty():
			errors.append(prefix + "terrain must be a nonempty array")
		else:
			for terrain in row.terrain:
				if terrain not in TERRAINS:
					errors.append(prefix + "unknown terrain " + str(terrain))
		# A fisher must touch water: its footprint shares an edge with one of these.
		if row.has("adjacent_terrain"):
			if not row.adjacent_terrain is Array or row.adjacent_terrain.is_empty():
				errors.append(prefix + "adjacent_terrain must be a nonempty array")
			else:
				for terrain in row.adjacent_terrain:
					if terrain not in TERRAINS:
						errors.append(prefix + "unknown adjacent terrain " + str(terrain))
	for id in tiers:
		var row: Dictionary = tiers[id]
		if not row.get("name", "") is String or row.get("name", "").is_empty():
			errors.append("Tier %s: name is required" % id)
		# A house's class decides which factions can win it (FACTIONS.md §3).
		if not row.get("class") is String or row["class"] not in CLASSES:
			errors.append("Tier %s: class must be one of \"\", working, middle or elite" % id)
		_needs_map(row.get("consumption"), "Tier %s consumption" % id)
		for field in ["consume_every_ticks", "upgrade_after_ticks", "downgrade_after_ticks", "workers_per_house"]:
			if not _integer(row.get(field), 0 if field == "upgrade_after_ticks" else 1):
				errors.append("Tier %s: invalid %s" % [id, field])
		# Settled happiness below this, for the downgrade time, demotes a house.
		if not _integer(row.get("downgrade_below_happiness"), 0) or int(row.downgrade_below_happiness) > 100:
			errors.append("Tier %s: invalid downgrade_below_happiness" % id)
		if not row.get("unlocks") is Array:
			errors.append("Tier %s: unlocks must be an array" % id)
		else:
			for building_id in row.unlocks:
				if not buildings.has(building_id):
					errors.append("Tier %s: unknown building %s" % [id, building_id])
				elif int(buildings[building_id].get("unlock_tier",-1)) != id:
					errors.append("Tier %s: unlock disagrees with building %s" % [id,building_id])
		if not row.get("services") is Array:
			errors.append("Tier %s: services must be an array" % id)
		else:
			for service in row.services:
				if service != "shelter" and buildings.values().filter(func(b): return b.get("provides") == service).is_empty():
					errors.append("Tier %s: no building provides service %s" % [id, service])
	# A produced good's price comes from its chain; any other good needs a base price.
	for id in goods:
		var produced := false
		for row in buildings.values():
			if row.get("outputs") is Dictionary and row.outputs.has(id):
				produced = true
		if not produced and not goods[id].has("price"):
			errors.append("Good %s: no building makes it, so it needs a price" % id)
	if not tiers.has(1):
		errors.append("Tier 1 is required")
	for id in tiers:
		if id > 1 and not tiers.has(id - 1):
			errors.append("Tiers must be contiguous")
	_validate_factions(faction_rows, biome_rows)
	return errors.is_empty()

## Faction rows (factions.json), and the factions each biome interests
## (biomes.json `factions`; WorldData validates the rest of a biome row).
func _validate_factions(faction_rows: Variant, biome_rows: Variant) -> void:
	if faction_rows == null:
		return
	_index(faction_rows, factions, "factions", false)
	for id in factions:
		var row: Dictionary = factions[id]
		var prefix := "Faction %s: " % id
		if not row.get("name", "") is String or row.get("name", "").is_empty():
			errors.append(prefix + "name is required")
		if not row.get("class") is String or row["class"] not in CLASSES or row["class"].is_empty():
			errors.append(prefix + "class must be working, middle or elite")
		if not row.get("colour", "") is String or not Color.html_is_valid(row.get("colour", "")):
			errors.append(prefix + "colour must be a hex colour")
		if not row.get("recruits") is bool:
			errors.append(prefix + "recruits must be true or false")
		if not row.get("settlements") is Array or row.settlements.is_empty():
			errors.append(prefix + "settlements must be a nonempty array")
		else:
			for settlement in row.settlements:
				if settlement not in SETTLEMENTS:
					errors.append(prefix + "unknown settlement " + str(settlement))
		for field in ["endowment", "coffer_cap"]:
			if not _integer(row.get(field), 0):
				errors.append(prefix + field + " must be whole silver")
		for field in ["dues_percent", "owner_share_percent"]:
			if not _integer(row.get(field), 0) or row.get(field) > 100:
				errors.append(prefix + field + " must be a whole percentage")
		# Rent per house tier, keyed by the tier id as text (JSON keys are strings).
		if not row.get("rent") is Dictionary:
			errors.append(prefix + "rent must map tiers to whole silver")
		else:
			for tier in row.rent:
				if not str(tier).is_valid_int() or not tiers.has(int(str(tier))):
					errors.append(prefix + "rent for unknown tier " + str(tier))
				elif not _integer(row.rent[tier], 0):
					errors.append(prefix + "rent must be whole silver")
		# One step of each stance term; a negative weight displeases.
		if not row.get("stance") is Dictionary:
			errors.append(prefix + "stance must map terms to weights")
		else:
			for term in row.stance:
				if term not in STANCE_TERMS:
					errors.append(prefix + "unknown stance term " + str(term))
				elif not (row.stance[term] is int or row.stance[term] is float) or not is_finite(float(row.stance[term])):
					errors.append(prefix + "stance weights must be numbers")
		# Recruiting factions weigh a working-class house's pull (FACTIONS.md §3.1).
		if row.get("recruits") == true:
			if not row.get("pull") is Dictionary or row.pull.is_empty():
				errors.append(prefix + "a recruiting faction needs pull weights")
			else:
				for term in row.pull:
					if term not in PULL_TERMS:
						errors.append(prefix + "unknown pull term " + str(term))
					elif not _integer(row.pull[term], 1 if term == "markup_step" else 0):
						errors.append(prefix + "pull weights must be whole numbers")
		elif row.has("pull"):
			errors.append(prefix + "only recruiting factions have pull weights")
		if not row.get("pledges") is Array:
			errors.append(prefix + "pledges must be an array")
		else:
			for pledge in row.pledges:
				if pledge not in PLEDGES:
					errors.append(prefix + "unknown pledge " + str(pledge))
	for id in buildings:
		# A hall recruits for a recruiting faction that can come to a village.
		var recruiter = buildings[id].get("recruits_for")
		if recruiter is String and not recruiter.is_empty() and (not factions.has(recruiter) or factions[recruiter].get("recruits") != true or "village" not in factions[recruiter].get("settlements", [])):
			errors.append("Building %s: recruits_for %s is not a recruiting village faction" % [id, recruiter])
		var buyers = buildings[id].get("buyers", [])
		if buyers is Array:
			for faction in buyers:
				if not factions.has(faction):
					errors.append("Building %s: unknown buyer %s" % [id, str(faction)])
	if biome_rows == null:
		return
	if not biome_rows is Array:
		errors.append("biomes must be an array")
		return
	for row in biome_rows:
		if not row is Dictionary or not row.get("id") is String or not row.get("factions") is Array:
			errors.append("biomes need an id and a factions array")
			continue
		biome_factions[row.id] = []
		for id in row.factions:
			if not factions.has(id):
				errors.append("Biome %s: unknown faction %s" % [row.id, str(id)])
			# Recruiting factions arrive with their class, not with the site.
			elif factions[id].get("recruits") != false or "village" not in factions[id].get("settlements", []):
				errors.append("Biome %s: faction %s cannot take an interest in a village site" % [row.id, id])
			else:
				biome_factions[row.id].append(id)

func _index(rows: Variant, target: Dictionary, label: String, numeric: bool) -> void:
	if not rows is Array:
		errors.append(label + " must be an array")
		return
	for row in rows:
		if not row is Dictionary or not row.has("id"):
			errors.append(label + " contains an invalid row")
			continue
		var id: Variant = row.id
		if numeric:
			if not _integer(id, 1):
				errors.append(label + " requires positive integer ids")
				continue
			id = int(id)
		elif not id is String or id.is_empty():
			errors.append(label + " requires string ids")
			continue
		if target.has(id):
			errors.append(label + " duplicate id " + str(id))
		target[id] = row.duplicate(true)

func _goods_map(value: Variant, label: String) -> void:
	if not value is Dictionary:
		errors.append(label + " must be a goods map")
		return
	for id in value:
		if not goods.has(id):
			errors.append(label + ": unknown good " + str(id))
		if not _integer(value[id], 1):
			errors.append(label + ": amounts must be positive integers")

## House types (docs/PLAN-job-classes.md, "House types"). Every house names
## the family it holds: `family` gives [min, max] adults (at least 1) and
## children. Optional: `class` (working, middle or elite) overrides the tier's
## class; `fixed_tier` keeps the house at one tier, never promoting or
## demoting; `lodgers` makes each adult a single family (an inn); `comfort`
## lifts the happiness of houses within its road radius; `reserved` rows
## exist in data but cannot be built yet.
func _validate_house_type(row: Dictionary, prefix: String) -> void:
	var house: bool = row.get("kind") == "house"
	for field in ["family", "class", "fixed_tier", "lodgers", "comfort"]:
		if row.has(field) and not house:
			errors.append(prefix + "only houses have " + field)
	if not house:
		return
	var family: Variant = row.get("family")
	if not family is Dictionary or family.size() != 2:
		errors.append(prefix + "a house needs family: {adults: [min, max], children: [min, max]}")
	else:
		for part in ["adults", "children"]:
			var span: Variant = family.get(part)
			if not span is Array or span.size() != 2 or not _integer(span[0], 1 if part == "adults" else 0) or not _integer(span[1], 0) or span[1] < span[0]:
				errors.append(prefix + "family %s must be [min, max] whole numbers%s" % [part, ", at least 1 adult" if part == "adults" else ""])
	if row.has("class") and row["class"] not in JOB_CLASSES:
		errors.append(prefix + "class must be working, middle or elite")
	if row.has("fixed_tier") and (not _integer(row.fixed_tier, 1) or not tiers.has(int(row.fixed_tier))):
		errors.append(prefix + "fixed_tier must be a known tier")
	for flag in ["lodgers", "reserved"]:
		if row.has(flag) and not row[flag] is bool:
			errors.append(prefix + flag + " must be true or false")
	if row.has("comfort"):
		var comfort: Variant = row.comfort
		if not comfort is Dictionary or not _integer(comfort.get("radius"), 1) or not _integer(comfort.get("happiness"), 1) or int(comfort.get("happiness", 0)) > 100:
			errors.append(prefix + "comfort needs a whole radius and a happiness bonus from 1 to 100")

## A tier's consumption: a goods map whose keys may also be goods categories
## with at least one good.
func _needs_map(value: Variant, label: String) -> void:
	if not value is Dictionary:
		errors.append(label + " must be a goods map")
		return
	for id in value:
		if not goods.has(id) and category_goods.get(id, []).is_empty():
			errors.append(label + ": unknown good or empty category " + str(id))
		if not _integer(value[id], 1):
			errors.append(label + ": amounts must be positive integers")

## The goods that meet a need: the good itself, or every good of a category.
func need_goods(need: String) -> Array:
	return [need] if goods.has(need) else category_goods.get(need, [])

## A need's display name: the good's name, or the category's.
func need_name(need: String) -> String:
	return str(goods[need].name) if goods.has(need) else str(GOOD_CATEGORIES.get(need, need))

## The tier need a good meets, or "" if that tier does not eat it.
func need_for(tier: int, good: String) -> String:
	for need in tiers[tier].consumption:
		if good in need_goods(need):
			return need
	return ""

func _integer(value: Variant, minimum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum

func _total(value: Dictionary) -> int:
	var result := 0
	for amount in value.values():
		if amount is int or amount is float:
			result += int(amount)
	return result
