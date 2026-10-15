extends RefCounted
## Validated content only. No global class cache or scene tree is required.
## Build menu categories, in display order.
const TERRAINS := ["grass", "forest", "rock", "marsh", "sand", "water", "stream", "river", "lake", "ocean"]
const CATEGORIES := {"housing":"Housing", "logistics":"Logistics", "resources":"Resources", "food":"Food"}
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
const PULL_TERMS := ["employment", "wages_in_full", "hall", "neighbour", "neighbour_cap", "relief", "idle_worker", "idle_cap", "need_unmet", "markup_over", "markup_step"]
var goods: Dictionary = {}
var buildings: Dictionary = {}
var tiers: Dictionary = {}
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
	factions.clear()
	biome_factions.clear()
	_index(good_rows, goods, "goods", false)
	_index(building_rows, buildings, "buildings", false)
	_index(tier_rows, tiers, "tiers", true)
	for id in goods:
		if not goods[id].get("name", "") is String or goods[id].get("name", "").is_empty():
			errors.append("Good %s needs a name" % id)
		if not goods[id].get("color", "") is String or not Color.html_is_valid(goods[id].get("color", "")):
			errors.append("Good %s needs a valid color" % id)
		if goods[id].has("price") and not _integer(goods[id].price, 0):
			errors.append("Good %s: price must be whole silver" % id)
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
		if row.get("kind") == "producer" and (row.get("cycle_ticks", 0) < 1 or (row.get("outputs", {}).is_empty() and row.get("forest_action", "") != "plant" and not row.get("service", false))):
			errors.append(prefix + "producer needs a cycle and outputs")
		# A service that houses need ("provides", such as a chapel) covers houses
		# within service_radius road tiles.
		if row.has("provides"):
			if not row.provides is String or row.provides.is_empty() or row.provides == "shelter" or not row.get("service", false):
				errors.append(prefix + "provides must name a service, on a service building")
			if not _integer(row.get("service_radius"), 1):
				errors.append(prefix + "invalid service_radius")
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
		if not row.get("terrain") is Array or row.get("terrain", []).is_empty():
			errors.append(prefix + "terrain must be a nonempty array")
		else:
			for terrain in row.terrain:
				if terrain not in TERRAINS:
					errors.append(prefix + "unknown terrain " + str(terrain))
	for id in tiers:
		var row: Dictionary = tiers[id]
		if not row.get("name", "") is String or row.get("name", "").is_empty():
			errors.append("Tier %s: name is required" % id)
		# A house's class decides which factions can win it (FACTIONS.md §3).
		if not row.get("class") is String or row["class"] not in CLASSES:
			errors.append("Tier %s: class must be one of \"\", working, middle or elite" % id)
		_goods_map(row.get("consumption"), "Tier %s consumption" % id)
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

func _integer(value: Variant, minimum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum

func _total(value: Dictionary) -> int:
	var result := 0
	for amount in value.values():
		if amount is int or amount is float:
			result += int(amount)
	return result
