extends RefCounted
## Validated world-generation data: data/world.json, biomes.json, deposits.json.
## Mirrors ContentDB: load_directory() reads files, validate() checks rows and
## collects every problem in `errors` instead of stopping at the first.
## factions.json is read only to check the factions each biome interests.
## Biome ids the generator's classification rules assign (docs/PLAN-world-map.md §4.2).
const RULE_BIOMES := ["ocean", "peaks", "mountain_pass", "tundra", "marsh", "highland_hills", "coast", "riverland", "heartland"]
const DEPOSIT_CLASSES := ["core", "uncommon", "rare"]
const VISIBILITY := ["map", "scouted"]
const REQUIREMENTS := ["ocean_edge"]
const WORLD_NUMBERS := ["sea_fraction", "continent_scale", "detail_scale", "ridge_strength", "lake_depth", "cold_temperature", "wet_moisture"]
const WORLD_INTEGERS := ["generator_version", "columns", "rows", "stream_flow", "river_flow", "great_river_flow", "min_village_distance", "scout_radius"]
var world: Dictionary = {}
var biomes: Dictionary = {}
var deposits: Dictionary = {}
var factions: Dictionary = {}
var errors: Array[String] = []

func load_directory(path: String = "res://data") -> bool:
	var rows: Array = []
	for filename in ["world.json", "biomes.json", "deposits.json", "factions.json"]:
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
	var valid := validate(rows[0], rows[1], rows[2], rows[3])
	if not valid:
		push_error("World data validation failed: " + "; ".join(errors))
	return valid

## Without faction rows, biome faction ids are checked for shape only;
## ContentDB validates the faction rows themselves.
func validate(world_row: Variant, biome_rows: Variant, deposit_rows: Variant, faction_rows: Variant = null) -> bool:
	errors.clear()
	world = {}
	biomes = {}
	deposits = {}
	factions = {}
	if faction_rows != null:
		_index(faction_rows, factions, "faction")
	_validate_world(world_row)
	_index(deposit_rows, deposits, "deposit")
	for id in deposits:
		var row: Dictionary = deposits[id]
		var prefix := "deposit %s: " % id
		if row.get("class") not in DEPOSIT_CLASSES:
			errors.append(prefix + "class must be one of " + ", ".join(DEPOSIT_CLASSES))
		if row.get("visibility") not in VISIBILITY:
			errors.append(prefix + "visibility must be map or scouted")
		if row.has("requires") and row.requires not in REQUIREMENTS:
			errors.append(prefix + "unknown requirement " + str(row.requires))
	_index(biome_rows, biomes, "biome")
	for id in RULE_BIOMES:
		if not biomes.has(id):
			errors.append("missing biome " + id)
	for id in biomes:
		_validate_biome(id, biomes[id], faction_rows != null)
	return errors.is_empty()

func _validate_world(row: Variant) -> void:
	if not row is Dictionary:
		errors.append("world.json must be an object")
		return
	world = row
	for key in WORLD_NUMBERS:
		if not _number(row.get(key)):
			errors.append("world: %s must be a number" % key)
	for key in WORLD_INTEGERS:
		if not _integer(row.get(key), 1):
			errors.append("world: %s must be a positive integer" % key)
	if errors.is_empty():
		if int(row.columns) < 8 or int(row.rows) < 8:
			errors.append("world: columns and rows must be at least 8")
		if float(row.sea_fraction) <= 0.0 or float(row.sea_fraction) >= 0.8:
			errors.append("world: sea_fraction must be between 0 and 0.8")
		if not (int(row.stream_flow) < int(row.river_flow) and int(row.river_flow) < int(row.great_river_flow)):
			errors.append("world: stream, river and great river flows must increase")
	var bands: Variant = row.get("band_fractions")
	if not bands is Array or bands.size() != 4:
		errors.append("world: band_fractions must list four cut-offs")
	else:
		var previous := 0.0
		for cut in bands:
			if not _number(cut) or float(cut) <= previous or float(cut) >= 1.0:
				errors.append("world: band_fractions must increase between 0 and 1")
				break
			previous = float(cut)

func _validate_biome(id: String, row: Dictionary, check_factions: bool) -> void:
	var prefix := "biome %s: " % id
	# The middle and elite factions a village here interests (FACTIONS.md §8).
	# The working-class factions arrive with their class, not with the site.
	if not row.get("factions") is Array:
		errors.append(prefix + "factions must be an array of faction ids")
	else:
		if row.get("settleable") == false and not row.factions.is_empty():
			errors.append(prefix + "a biome that cannot be settled interests no factions")
		var seen := {}
		for faction in row.factions:
			if not faction is String or seen.has(faction):
				errors.append(prefix + "factions must be distinct faction ids")
				continue
			seen[faction] = true
			if not check_factions:
				continue
			if not factions.has(faction):
				errors.append(prefix + "unknown faction " + str(faction))
			elif factions[faction].get("recruits") != false or "village" not in factions[faction].get("settlements", []):
				errors.append(prefix + "faction %s cannot take an interest in a village site" % faction)
	if not row.get("colour") is String or not Color.html_is_valid(row.colour):
		errors.append(prefix + "colour must be a hex colour")
	for key in ["settleable", "harsh"]:
		if not row.get(key) is bool:
			errors.append(prefix + key + " must be true or false")
	for key in ["forest", "cliffs"]:
		if not _number(row.get(key)) or float(row.get(key)) < 0.0 or float(row.get(key)) > 1.0:
			errors.append(prefix + key + " must be between 0 and 1")
	for pool in ["signature", "rare"]:
		if not row.get(pool) is Dictionary:
			errors.append(prefix + pool + " must be an object of deposit weights")
			continue
		for deposit in row[pool]:
			if not deposits.has(deposit):
				errors.append(prefix + "unknown deposit " + str(deposit))
			elif not _number(row[pool][deposit]) or float(row[pool][deposit]) <= 0.0:
				errors.append(prefix + "weight for %s must be positive" % deposit)
	if not _integer(row.get("rare_count"), 0):
		errors.append(prefix + "rare_count must be a whole number")
	elif row.get("harsh") == true and (int(row.rare_count) < 1 or row.get("rare", {}).is_empty()):
		errors.append(prefix + "harsh biomes need a rare deposit")
	if row.has("extra"):
		if not row.extra is Dictionary:
			errors.append(prefix + "extra must be an object of deposit chances")
		else:
			for deposit in row.extra:
				if not deposits.has(deposit):
					errors.append(prefix + "unknown deposit " + str(deposit))
				elif not _number(row.extra[deposit]) or float(row.extra[deposit]) < 0.0 or float(row.extra[deposit]) > 1.0:
					errors.append(prefix + "chance for %s must be between 0 and 1" % deposit)

func _index(rows: Variant, target: Dictionary, label: String) -> void:
	if not rows is Array:
		errors.append("%ss must be an array" % label)
		return
	for row in rows:
		if not row is Dictionary or not row.get("id") is String or row.id.is_empty():
			errors.append("every %s needs a string id" % label)
		elif target.has(row.id):
			errors.append("duplicate %s id %s" % [label, row.id])
		else:
			target[row.id] = row

static func _number(value: Variant) -> bool:
	return value is int or value is float

static func _integer(value: Variant, minimum: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and int(value) >= minimum
