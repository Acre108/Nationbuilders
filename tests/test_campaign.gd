extends RefCounted
const Campaign = preload("res://sim/campaign.gd")
const Scenario = preload("res://sim/scenario.gd")
const Sim = preload("res://sim/village_sim.gd")
const HexMath = preload("res://sim/world/hex_math.gd")
const DIRECTORY := "res://artifacts/campaign-test-saves"

func run(t) -> void:
	_snapshot_restore(t)
	_legacy_restore(t)
	var campaign = Campaign.new()
	t.check(campaign.generate("Test campaign", 73), "Campaign generates a world")
	t.check(campaign.save(DIRECTORY), "World-only campaign saves")
	var path := DIRECTORY.path_join(campaign.id + ".campaign")
	var loaded = Campaign.new()
	t.check(loaded.load_save(path), "World-only campaign loads: " + loaded.last_error)
	t.check(loaded.name == campaign.name and loaded.world.fingerprint() == campaign.world.fingerprint() and loaded.village == null, "Loading preserves the named world before founding")
	t.check(not campaign.found(Vector2i(99999, 99999), "No"), "Cannot found outside the world")
	t.check(campaign.found(campaign.world.start, "First Hearth"), "Can found first village in starting region")
	t.check(not campaign.found(campaign.world.start, "Second"), "Campaign permits one active village")
	var sim = campaign.village
	var forester_cell := _free_cell(sim, "forester", 1)
	t.check(sim.place("forester", forester_cell, 1), "Save fixture includes rotated construction")
	sim.step(240)
	t.check(Scenario.complete_chain(sim), "Saved village has a working bread chain")
	sim.step(173)
	var in_transit := false
	for carrier in sim.carriers: in_transit = in_transit or not carrier.job.is_empty()
	t.check(in_transit, "Save fixture includes deliveries in progress")
	# Preserve a disabled building, rotated construction and regenerating forest.
	var house = sim.buildings.values()[1]
	sim.set_workers_enabled(house.uid, false)
	var tree: Vector2i = sim.grid.trees.keys()[0]
	sim.grid.clear_tree(tree, true)
	sim.grid.plant_tree(tree, sim.tick + 600)
	var snapshot: String = JSON.stringify(sim.snapshot())
	t.check(campaign.save(DIRECTORY), "Campaign overwrites its save atomically")
	loaded = Campaign.new()
	t.check(loaded.load_save(path), "Campaign with village loads: " + loaded.last_error)
	if loaded.village != null:
		t.check(JSON.stringify(loaded.village.snapshot()) == snapshot, "Load restores the complete simulation snapshot")
		t.check(loaded.village_name == "First Hearth" and loaded.world.hex(loaded.village_hex).settlement == loaded.active_village, "Loaded world retains village identity and location")
		sim.step(750)
		loaded.village.step(750)
		t.check(JSON.stringify(loaded.village.snapshot()) == JSON.stringify(sim.snapshot()), "Loaded deliveries, production, needs and trees continue deterministically")
	var file := FileAccess.open(path, FileAccess.READ)
	var envelope = file.get_var(false)
	file.close()
	envelope.payload[20] = envelope.payload[20] ^ 1
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_var(envelope)
	file.close()
	var before: String = loaded.world.fingerprint()
	t.check(not loaded.load_save(path) and "damaged" in loaded.last_error, "Damaged campaign fails with a clear message")
	t.check(loaded.world.fingerprint() == before, "Failed load preserves the existing campaign")
	# Correctly encoded files from newer versions must also fail gracefully.
	campaign.save(DIRECTORY)
	file = FileAccess.open(path, FileAccess.READ)
	envelope = file.get_var(false)
	file.close()
	var payload: Dictionary = bytes_to_var(envelope.payload)
	for field in ["version", "generator", "content", "seed"]:
		var altered: Dictionary = payload.duplicate(true)
		altered[field] = "invalid" if field in ["content", "seed"] else 999
		var bytes := var_to_bytes(altered)
		file = FileAccess.open(path, FileAccess.WRITE)
		file.store_var({"payload":bytes, "checksum":Campaign._hash(bytes)})
		file.close()
		t.check(not loaded.load_save(path) and not loaded.last_error.is_empty(), "Reject incompatible or malformed saved " + field)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_campaign_loop(t)

func _free_cell(sim, building_id: String, rotation: int = 0) -> Vector2i:
	for y in sim.grid.height:
		for x in sim.grid.width:
			var cell := Vector2i(x,y)
			if sim.placement_error(building_id,cell,rotation).is_empty(): return cell
	return Vector2i(-1,-1)

func _snapshot_restore(t) -> void:
	var sim = Sim.new(73)
	t.check(Scenario.starter(sim), "Snapshot fixture uses real founding commands")
	sim.step(240)
	t.check(Scenario.complete_chain(sim), "Snapshot fixture includes complete chain")
	sim.step(173)
	var house = sim.buildings.values()[1]
	sim.set_workers_enabled(house.uid, false)
	var tree: Vector2i = sim.grid.trees.keys()[0]
	sim.grid.clear_tree(tree, true)
	sim.grid.plant_tree(tree, sim.tick + 600)
	var snapshot: Dictionary = sim.snapshot()
	var restored = Sim.from_snapshot(snapshot)
	t.check(restored != null, "Reusable snapshot inverse accepts complete state")
	if restored != null:
		t.check(JSON.stringify(restored.snapshot()) == JSON.stringify(snapshot), "Snapshot inverse preserves site, logistics, economy and forestry")
		sim.step(750)
		restored.step(750)
		t.check(JSON.stringify(restored.snapshot()) == JSON.stringify(sim.snapshot()), "Snapshot inverse continues deterministically across growth and delivery cycles")
	var broken := snapshot.duplicate(true)
	broken.carriers[0].owner = 999999
	t.check(Sim.from_snapshot(broken) == null, "Snapshot rejects an orphan carrier without mutating original")
	broken = snapshot.duplicate(true)
	broken.buildings[0].inventory.logs = -1
	t.check(Sim.from_snapshot(broken) == null, "Snapshot rejects negative storage quantities")

func _legacy_restore(t) -> void:
	var sim = Sim.new(73)
	Scenario.starter(sim)
	sim.step(250)
	var campaign = Campaign.new()
	campaign.generate("Legacy hearth",73)
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
	for carrier in sim.carriers: carriers.append(Campaign._state(carrier))
	var payload := {"version":1,"id":"legacy-test","name":"Legacy hearth","seed":73,
		"generator":campaign.world.generator_version,"content":Campaign._content_hash(),
		"village_name":"Old clearing","village_hex":campaign.world.start,
		"village":{"sim":Campaign._state(sim),"site":site,"grid":grid,"rng":sim.rng.state,
			"reserve":sim.reserve.items,"buildings":buildings,"carriers":carriers}}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var path := DIRECTORY.path_join("legacy-test.campaign")
	var bytes := var_to_bytes(payload)
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_var({"payload":bytes,"checksum":Campaign._hash(bytes)})
	file.close()
	var loaded = Campaign.new()
	t.check(loaded.load_save(path),"Version one square village migrates with a clear active record: " + loaded.last_error)
	if loaded.village != null:
		t.check(JSON.stringify(loaded.village.snapshot()) == JSON.stringify(sim.snapshot()),"Legacy migration preserves authored square site and full state")
		sim.step(120)
		loaded.village.step(120)
		t.check(JSON.stringify(loaded.village.snapshot()) == JSON.stringify(sim.snapshot()),"Migrated legacy village continues deterministically")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _campaign_loop(t) -> void:
	var campaign = Campaign.new()
	t.check(campaign.generate("Three villages",73), "Three-run campaign generates")
	var first := Vector2i.ZERO
	for run_number in 3:
		var founded := false
		for coord in campaign.world.hexes:
			if not campaign.world.hex(coord).settlement.is_empty(): continue
			if not campaign.found_blocked(coord).is_empty(): continue
			if campaign.found(coord,"Village %d" % (run_number + 1)):
				founded = true
				break
		t.check(founded, "Run %d finds a playable spaced site" % (run_number + 1))
		if not founded: return
		var coord: Vector2i = campaign.village_hex
		for earlier in campaign.villages.slice(0,run_number):
			t.check(HexMath.distance(coord,earlier.hex) >= 4,"Village reaches retain wilderness spacing")
		if run_number == 0: first = coord
		t.check(not campaign.charter_available() and not campaign.finish("charter"), "Charter is unavailable before highest tier")
		campaign.village.step(250)
		t.check(campaign.charter_available(), "Working starter reaches interim charter tier")
		var sim = campaign.village
		t.check(campaign.charter_available() and campaign.village == sim, "Keeping building leaves active run intact")
		var outcome := "charter" if run_number != 1 else "abandoned"
		t.check(campaign.end_and_save(outcome,DIRECTORY), "Run result saves atomically: " + campaign.last_error)
		var record: Dictionary = campaign.villages[run_number]
		t.check(campaign.village == null and campaign.active_village.is_empty() and record.result.outcome == outcome, "Run ends and retains result for review")
		t.check(campaign.world.hex(coord).settlement == record.id, "Completed run keeps marker identity")
		for other in campaign.world.hexes:
			if HexMath.distance(coord,other) <= 2: t.check(campaign.world.hex(other).scouted,"Run scouts radius two")
		var loaded = Campaign.new()
		t.check(loaded.load_save(DIRECTORY.path_join(campaign.id + ".campaign")), "Completed campaign reloads: " + loaded.last_error)
		t.check(loaded.villages == campaign.villages and loaded.world.fingerprint() == campaign.world.fingerprint(), "Records, spacing markers and scouting survive load")
		campaign = loaded
	t.check(campaign.villages.size() == 3, "Three runs accumulate in one campaign")
	t.check(not campaign.found_blocked(first).is_empty(), "Chartered settlement cannot be overwritten")
	var ruin: Vector2i = campaign.villages[1].hex
	t.check(campaign.found_blocked(ruin).is_empty(), "Abandoned ruin can be resettled: " + campaign.found_blocked(ruin))
	t.check(campaign.found(ruin,"New hearth"), "Resettlement creates a new active run")
	t.check(campaign.active_record().resettlement_bonus.logs == Campaign.RESETTLEMENT_LOGS and campaign.village.reserve.count("logs") == Campaign.RESETTLEMENT_LOGS, "Modest resettlement supplies are recorded and granted")
	var before = campaign.village
	t.check(not campaign.end_and_save("abandoned","res://project.godot") and campaign.village == before and campaign.active_record().status == "active", "Failed end save preserves active run and record")
	campaign.map_view_state = {"yaw":1.25,"target":Vector3(1,0,2)}
	campaign.village_view_state = {"weather":"clear","charter_offer_dismissed":true}
	t.check(campaign.save(DIRECTORY),"Active resettlement saves")
	var loaded = Campaign.new()
	t.check(loaded.load_save(DIRECTORY.path_join(campaign.id + ".campaign")),"Active resettlement reloads")
	t.check(loaded.map_view_state == campaign.map_view_state and loaded.village_view_state == campaign.village_view_state,"Both camera and view settings persist")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIRECTORY.path_join(campaign.id + ".campaign")))
