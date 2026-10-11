extends RefCounted
## Validated content only. No global class cache or scene tree is required.
## Build menu categories, in display order.
const CATEGORIES := {"housing":"Housing", "logistics":"Logistics", "resources":"Resources", "food":"Food"}
var goods: Dictionary = {}
var buildings: Dictionary = {}
var tiers: Dictionary = {}
var errors: Array[String] = []

func load_directory(path: String = "res://data") -> bool:
	var rows: Array = []
	for filename in ["goods.json", "buildings.json", "tiers.json"]:
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
	var valid := validate(rows[0], rows[1], rows[2])
	if not valid:
		push_error("Content validation failed: " + "; ".join(errors))
	return valid

func validate(good_rows: Variant, building_rows: Variant, tier_rows: Variant) -> bool:
	errors.clear()
	goods.clear()
	buildings.clear()
	tiers.clear()
	_index(good_rows, goods, "goods", false)
	_index(building_rows, buildings, "buildings", false)
	_index(tier_rows, tiers, "tiers", true)
	for id in goods:
		if not goods[id].get("name", "") is String or goods[id].get("name", "").is_empty():
			errors.append("Good %s needs a name" % id)
		if not goods[id].get("color", "") is String or not Color.html_is_valid(goods[id].get("color", "")):
			errors.append("Good %s needs a valid color" % id)
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
		if row.get("kind", "") not in ["producer", "house", "storehouse", "road"]:
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
		if row.get("kind") == "producer" and (row.get("cycle_ticks", 0) < 1 or row.get("outputs", {}).is_empty()):
			errors.append(prefix + "producer needs a cycle and outputs")
		if row.get("inputs") is Dictionary and _total(row.inputs) > row.get("input_capacity", 0):
			errors.append(prefix + "recipe exceeds input capacity")
		if row.get("outputs") is Dictionary and _total(row.outputs) > row.get("output_capacity", 0):
			errors.append(prefix + "recipe exceeds output capacity")
		if row.get("kind") == "storehouse":
			for field in ["storage_capacity", "carriers"]:
				if not _integer(row.get(field), 1):
					errors.append(prefix + "invalid " + field)
		if not row.get("terrain") is Array or row.get("terrain", []).is_empty():
			errors.append(prefix + "terrain must be a nonempty array")
		else:
			for terrain in row.terrain:
				if terrain not in ["grass", "forest", "water", "rock"]:
					errors.append(prefix + "unknown terrain " + str(terrain))
	for id in tiers:
		var row: Dictionary = tiers[id]
		if not row.get("name", "") is String or row.get("name", "").is_empty():
			errors.append("Tier %s: name is required" % id)
		_goods_map(row.get("consumption"), "Tier %s consumption" % id)
		for field in ["consume_every_ticks", "upgrade_after_ticks", "downgrade_after_ticks", "workers_per_house"]:
			if not _integer(row.get(field), 0 if field == "upgrade_after_ticks" else 1):
				errors.append("Tier %s: invalid %s" % [id, field])
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
				if service != "shelter":
					errors.append("Tier %s: unsupported service %s" % [id, service])
	if not tiers.has(1):
		errors.append("Tier 1 is required")
	for id in tiers:
		if id > 1 and not tiers.has(id - 1):
			errors.append("Tiers must be contiguous")
	return errors.is_empty()

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
