extends RefCounted
## Campaign persistence uses object-free Variants to retain typed tile arrays,
## integer dictionary keys and carrier jobs without lossy JSON conversion.
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const WorldGen = preload("res://sim/world/world_gen.gd")
const SitePackage = preload("res://sim/world/site_package.gd")
const Sites = preload("res://sim/world/sites.gd")
const RNG = preload("res://sim/rng.gd")
const IntNoise = preload("res://sim/world/int_noise.gd")
const Building = preload("res://sim/building.gd")
const Carrier = preload("res://sim/carrier.gd")
const HexMath = preload("res://sim/world/hex_math.gd")
const RunResult = preload("res://sim/world/run_result.gd")
const VERSION := 2
const SAVE_DIRECTORY := "user://campaigns"
var id := ""
var name := ""
var seed_value := 73
var world
var village
var village_name := ""
var village_hex := Vector2i.ZERO
var last_error := ""
var villages: Array = []
var active_village := ""
var turn := 0
var created := 0
var last_played := 0
var map_view_state: Dictionary = {}
var village_view_state: Dictionary = {}
const RESETTLEMENT_LOGS := 12

func generate(campaign_name: String, seed_number: int) -> bool:
	last_error = ""
	village = null
	village_name = ""
	village_hex = Vector2i.ZERO
	villages.clear()
	active_village = ""
	turn = 0
	created = int(Time.get_unix_time_from_system())
	last_played = created
	map_view_state.clear()
	village_view_state.clear()
	name = campaign_name.strip_edges()
	if name.is_empty(): name = "New campaign"
	seed_value = seed_number
	world = WorldGen.generate(seed_value)
	if world == null:
		last_error = "Could not generate the world."
		return false
	id = "%d-%d" % [int(Time.get_unix_time_from_system() * 1000), Time.get_ticks_usec()]
	return true

func found(coord: Vector2i, settlement_name: String) -> bool:
	if world == null: return _fail("Generate a world before founding a village.")
	if village != null:
		last_error = "Resume your existing village."
		return false
	last_error = found_blocked(coord)
	if not last_error.is_empty(): return false
	var info = world.hex(coord)
	var local_seed := IntNoise.mix(seed_value, coord.x, coord.y, 200)
	var site = load("res://sim/world/site_gen.gd").generate(world, coord)
	world.site_errors[coord] = site.error() if site != null else "No playable site"
	if site == null or not site.error().is_empty():
		return _fail("Cannot found this village: " + (site.error() if site != null else "No playable site"))
	local_seed = site.seed_value
	var candidate = Sim.new(local_seed, null, site)
	if not candidate.valid or not Scenario.starter(candidate):
		last_error = "Cannot found this village: " + candidate.last_error
		return false
	var previous := village_at(coord)
	var bonus := RESETTLEMENT_LOGS if not previous.is_empty() else 0
	if bonus > 0: candidate.reserve.add("logs", bonus)
	village = candidate
	village_hex = coord
	village_name = settlement_name.strip_edges()
	if village_name.is_empty(): village_name = "Hearth %d" % (villages.size() + 1)
	active_village = "%s-v%d" % [id, villages.size() + 1]
	villages.append({"id":active_village,"name":village_name,"hex":coord,"status":"active",
		"founded_turn":turn,"ended_turn":-1,"best_tier":1,"population":population(),
		"buildings":village.buildings.size(),"result":{},"save":id + ".campaign",
		"resettlement_bonus":{"logs":bonus},"resettled_from":previous.get("id", "")})
	info.settlement = active_village
	village_view_state.clear()
	_scout(coord)
	return true

func active_record() -> Dictionary:
	for record in villages:
		if record.id == active_village: return record
	return {}

## Latest run occupies the marker; earlier runs remain in the village list.
func village_at(coord: Vector2i) -> Dictionary:
	for index in range(villages.size() - 1, -1, -1):
		if villages[index].hex == coord: return villages[index]
	return {}

func found_blocked(coord: Vector2i) -> String:
	if world == null: return "Generate a world before founding a village."
	if village != null: return "Resume, charter or abandon your active village first."
	var previous := village_at(coord)
	var ignored: String = previous.get("id", "") if previous.get("status", "") in ["ruin","abandoned"] else ""
	var settlements: Array[Vector2i] = []
	return world.found_blocked(coord, settlements, ignored)

func population() -> int:
	return village.workforce() if village != null else 0

func _update_record() -> void:
	var record := active_record()
	if record.is_empty() or village == null: return
	record.best_tier = maxi(int(record.best_tier), village.unlocked_tier)
	record.population = population()
	record.buildings = village.buildings.size()

func charter_available() -> bool:
	if village == null: return false
	var highest := 1
	for tier in village.db.tiers: highest = maxi(highest, int(tier))
	return village.unlocked_tier >= highest

func finish(outcome: String = "charter") -> bool:
	if village == null: return _fail("There is no active village.")
	if outcome not in ["charter","ruin","abandoned"]: return _fail("Unknown run result.")
	if outcome == "charter" and not charter_available(): return _fail("Reach the current highest tier before chartering.")
	if outcome == "ruin" and population() > 0: return _fail("The village still has inhabitants.")
	_update_record()
	var record := active_record()
	record.status = "chartered" if outcome == "charter" else outcome
	record.ended_turn = turn
	record.result = RunResult.create(outcome, record.best_tier, population(), village.tick)
	record.save = ""
	_scout(village_hex)
	active_village = ""
	village = null
	last_error = ""
	return true

func abandon() -> bool:
	return finish("abandoned")

## The present sim retains four founding adults; future mortality can make
## this trigger reachable naturally without changing the result contract.
func check_run_end() -> bool:
	return finish("ruin") if village != null and population() == 0 else false

func end_and_save(outcome: String, directory: String = SAVE_DIRECTORY) -> bool:
	var previous = village
	var records := villages.duplicate(true)
	var active := active_village
	if not finish(outcome): return false
	if save(directory): return true
	village = previous
	villages = records
	active_village = active
	return false

func _scout(coord: Vector2i) -> void:
	for other in world.hexes:
		if HexMath.distance(coord, other) <= 2: world.hex(other).scouted = true

func save(directory: String = SAVE_DIRECTORY) -> bool:
	last_error = ""
	if FileAccess.file_exists(directory): return _fail("The campaign save folder is a file.")
	if world == null:
		last_error = "Generate a world before saving."
		return false
	_update_record()
	last_played = int(Time.get_unix_time_from_system())
	var scouted: Array = []
	for coord in world.hexes:
		if world.hex(coord).scouted: scouted.append(coord)
	var payload := {"version":VERSION, "id":id, "name":name, "seed":seed_value,
		"generator":world.generator_version, "content":_content_hash(),
		"village_name":village_name, "village_hex":village_hex, "village":{},
		"villages":villages.duplicate(true),"active_village":active_village,"scouted":scouted,
		"turn":turn,"created":created,"last_played":last_played,
		"map_view_state":map_view_state,"village_view_state":village_view_state}
	if village != null:
		payload.village = {"snapshot":village.snapshot()}
	var bytes := var_to_bytes(payload)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		last_error = "Could not create the campaign save folder."
		return false
	var path := directory.path_join(id + ".campaign")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "Could not write the campaign save."
		return false
	file.store_var({"checksum":_hash(bytes), "payload":bytes})
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path)) != OK:
		last_error = "Could not finish the campaign save. Previous save was kept."
		return false
	return true

func load_save(path: String) -> bool:
	last_error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _fail("Could not open this campaign.")
	var envelope = file.get_var(false)
	if not envelope is Dictionary or not envelope.get("payload") is PackedByteArray:
		return _fail("This campaign save is damaged.")
	if envelope.get("checksum") != _hash(envelope.payload):
		return _fail("This campaign save is damaged (checksum mismatch).")
	var payload = bytes_to_var(envelope.payload)
	if not payload is Dictionary or payload.get("version") not in [1, VERSION]:
		return _fail("This campaign uses an unsupported save version.")
	for key in ["id", "name", "content", "village_name"]:
		if not payload.get(key) is String: return _fail("This campaign save is damaged.")
	if not payload.get("seed") is int or not payload.get("generator") is int or not payload.get("village_hex") is Vector2i or not payload.get("village") is Dictionary:
		return _fail("This campaign save is damaged.")
	if not payload.id.is_valid_filename(): return _fail("Invalid campaign identifier.")
	if payload.get("content") != _content_hash():
		return _fail("This campaign was saved with different game data.")
	var generated = WorldGen.generate(payload.seed)
	if generated == null or generated.generator_version != payload.generator:
		return _fail("This campaign uses a different world generator.")
	var restored = null
	if not payload.village.is_empty():
		var saved: Dictionary = payload.village
		if payload.version == VERSION:
			if not saved.get("snapshot") is Dictionary: return _fail("Invalid saved village snapshot.")
			restored = Sim.from_snapshot(saved.snapshot)
			if restored == null: return _fail("Invalid saved village snapshot.")
		else:
			for key in ["sim", "site", "grid", "reserve"]:
				if not saved.get(key) is Dictionary: return _fail("Invalid saved village state.")
			if not saved.get("rng") is int or not saved.get("buildings") is Array or not saved.get("carriers") is Array:
				return _fail("Invalid saved village state.")
			if not saved.site.get("width") is int or not saved.site.get("height") is int or saved.site.width < 1 or saved.site.height < 1 or saved.site.width * saved.site.height > 1000000:
				return _fail("Invalid saved village dimensions.")
			var site = SitePackage.new(saved.site.width,saved.site.height)
			if not _restore_legacy(site, saved.site) or not site.error().is_empty(): return _fail("Invalid saved village site.")
			restored = Sim.new(payload.seed, null, site)
			if not restored.valid or not _restore(restored, saved.sim) or not _restore_legacy(restored.grid, saved.grid):
				return _fail("Invalid saved village state.")
			restored.rng.state = saved.rng
			restored.reserve.items = saved.reserve
			for entry in saved.buildings:
				if not entry is Dictionary or not entry.get("id") is String or not entry.get("state") is Dictionary:
					return _fail("Invalid saved building.")
				if not entry.state.get("uid") is int or not entry.state.get("cell") is Vector2i:
					return _fail("Invalid saved building.")
				for key in ["input", "output", "inventory"]:
					if not entry.get(key) is Dictionary: return _fail("Invalid saved building storage.")
				if not restored.db.buildings.has(entry.id): return _fail("Unknown saved building.")
				var building = Building.new(entry.state.uid, restored.db.buildings[entry.id], entry.state.cell)
				if not _restore(building, entry.state): return _fail("Invalid saved building.")
				building.input.items = entry.input
				building.output.items = entry.output
				building.inventory.items = entry.inventory
				restored.buildings[building.uid] = building
			for entry in saved.carriers:
				if not entry is Dictionary or not entry.get("uid") is int or not entry.get("owner") is int or not entry.get("cell") is Vector2i:
					return _fail("Invalid saved carrier.")
				var carrier = Carrier.new(entry.uid, entry.owner, entry.cell)
				if not _restore(carrier, entry): return _fail("Invalid saved carrier.")
				restored.carriers.append(carrier)
			# Legacy reflection saves are normalized through the same validated
			# inverse as current saves before they enter the campaign.
			restored = Sim.from_snapshot(restored.snapshot())
			if restored == null: return _fail("Invalid legacy village state.")
			if not generated.has(payload.village_hex): return _fail("Invalid village region.")
	var loaded_records: Array = []
	var loaded_active := ""
	var loaded_map := {}
	var loaded_view := {}
	var loaded_turn := 0
	var loaded_created := 0
	var loaded_played := 0
	if payload.version == VERSION:
		if not payload.get("villages") is Array or not payload.get("active_village") is String or not payload.get("scouted") is Array:
			return _fail("Invalid saved campaign records.")
		for key in ["turn","created","last_played"]:
			if not payload.get(key) is int or payload[key] < 0: return _fail("Invalid saved campaign dates.")
		for key in ["map_view_state","village_view_state"]:
			if not payload.get(key) is Dictionary: return _fail("Invalid saved camera state.")
		var known_ids := {}
		var active_count := 0
		for record in payload.villages:
			if not _valid_record(record, generated) or known_ids.has(record.id): return _fail("Invalid saved village record.")
			known_ids[record.id] = true
			if record.status == "active":
				active_count += 1
				if record.id != payload.active_village or record.hex != payload.village_hex: return _fail("Invalid active village record.")
			generated.hex(record.hex).settlement = record.id
		if active_count != (1 if restored != null else 0) or (active_count == 0 and not payload.active_village.is_empty()):
			return _fail("Invalid active village state.")
		for coord in payload.scouted:
			if not coord is Vector2i or not generated.has(coord): return _fail("Invalid saved scouting.")
			generated.hex(coord).scouted = true
		loaded_records = payload.villages.duplicate(true)
		loaded_active = payload.active_village
		loaded_map = payload.map_view_state.duplicate(true)
		loaded_view = payload.village_view_state.duplicate(true)
		loaded_turn = payload.turn
		loaded_created = payload.created
		loaded_played = payload.last_played
	elif restored != null:
		loaded_active = payload.id + "-v1"
		loaded_records.append({"id":loaded_active,"name":payload.village_name,"hex":payload.village_hex,"status":"active",
			"founded_turn":0,"ended_turn":-1,"best_tier":restored.unlocked_tier,"population":restored.workforce(),
			"buildings":restored.buildings.size(),"result":{},"save":payload.id + ".campaign",
			"resettlement_bonus":{"logs":0},"resettled_from":""})
		generated.hex(payload.village_hex).settlement = loaded_active
	id = payload.id
	name = payload.name
	seed_value = payload.seed
	world = generated
	village = restored
	village_name = payload.village_name
	village_hex = payload.village_hex
	villages = loaded_records
	active_village = loaded_active
	map_view_state = loaded_map
	village_view_state = loaded_view
	turn = loaded_turn
	created = loaded_created
	last_played = loaded_played
	return true

static func _valid_record(record, generated) -> bool:
	if not record is Dictionary: return false
	for key in ["id","name","status","save","resettled_from"]:
		if not record.get(key) is String: return false
	if record.id.is_empty() or record.status not in ["active","chartered","ruin","abandoned"]: return false
	if not record.get("hex") is Vector2i or not generated.has(record.hex): return false
	for key in ["founded_turn","ended_turn","best_tier","population","buildings"]:
		if not record.get(key) is int or record[key] < (-1 if key == "ended_turn" else 0): return false
	if not record.get("resettlement_bonus") is Dictionary or not record.resettlement_bonus.get("logs") is int or record.resettlement_bonus.logs not in [0,RESETTLEMENT_LOGS]: return false
	if record.status == "active": return record.get("result") is Dictionary and record.result.is_empty()
	if not RunResult.valid(record.get("result")): return false
	return record.result.outcome == ("charter" if record.status == "chartered" else record.status)

static func save_paths(directory: String = SAVE_DIRECTORY) -> Array[String]:
	var paths: Array[String] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)): return paths
	for filename in DirAccess.get_files_at(directory):
		if filename.ends_with(".campaign"): paths.append(directory.path_join(filename))
	paths.sort()
	paths.reverse()
	return paths

func _fail(message: String) -> bool:
	last_error = message
	return false

static func _state(object) -> Dictionary:
	var result := {}
	for property in object.get_property_list():
		var key: String = property.name
		if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE or key in ["buildings", "carriers", "_path_cache"]: continue
		var value = object.get(key)
		if value is Object: continue
		result[key] = value
	return result

static func _restore(object, state: Dictionary) -> bool:
	var expected := _state(object)
	if expected.size() != state.size(): return false
	for key in expected:
		if not state.has(key) or typeof(state[key]) != typeof(expected[key]): return false
	for key in expected: object.set(key, state[key])
	return true

static func _restore_legacy(object, state: Dictionary) -> bool:
	var expected := _state(object)
	var added := ["footprint","seed_value","world_coord","hex_width","world_origin","owner_coords","generation_error","promised_water","playability_result","districts"]
	for key in state:
		if not expected.has(key) or typeof(state[key]) != typeof(expected[key]): return false
	for key in expected:
		if not state.has(key) and key not in added: return false
	for key in state: object.set(key,state[key])
	return true

static func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

static func _content_hash() -> String:
	var bytes := PackedByteArray()
	for filename in ["world", "biomes", "deposits", "buildings", "goods", "tiers"]:
		bytes.append_array(FileAccess.get_file_as_bytes("res://data/" + filename + ".json"))
	return _hash(bytes)
