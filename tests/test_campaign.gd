extends RefCounted
const Campaign = preload("res://sim/campaign.gd")
const Scenario = preload("res://sim/scenario.gd")
const Sim = preload("res://sim/village_sim.gd")
const Economy = preload("res://sim/economy.gd")
const HexMath = preload("res://sim/world/hex_math.gd")
const DIRECTORY := "res://artifacts/campaign-test-saves"

func run(t) -> void:
	_road_budget(t)
	_snapshot_restore(t)
	# The quick tier stops here; the rest saves and loads whole campaigns.
	if t.get("quick") == true: return
	_snapshot_demolition(t)
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
	# One incompatible version, one changed game data, one malformed record.
	for field in ["version", "content", "villages"]:
		var altered: Dictionary = payload.duplicate(true)
		altered[field] = 999 if field in ["version", "generator"] else "invalid"
		var bytes := var_to_bytes(altered)
		file = FileAccess.open(path, FileAccess.WRITE)
		file.store_var({"payload":bytes, "checksum":Campaign._hash(bytes)})
		file.close()
		t.check(not loaded.load_save(path) and not loaded.last_error.is_empty(), "Reject incompatible or malformed saved " + field)
	var village_max_zoom := maxf(payload.village.snapshot.site.width,payload.village.snapshot.site.height) * 1.15
	# A wrong type, a non-finite number, another village's view and a zoom just
	# past the site's maximum.
	for change in [{"key":"map_view_state","state":{"focus":"invalid"}},
		{"key":"map_view_state","state":{"zoom_size":INF}},
		{"key":"village_view_state","state":{"village_id":"old-village","speed":1}},
		{"key":"village_view_state","state":{"village_id":payload.active_village,"zoom_size":village_max_zoom + 0.000001}}]:
		var altered: Dictionary = payload.duplicate(true)
		altered[change.key] = change.state
		var bytes := var_to_bytes(altered)
		file = FileAccess.open(path,FileAccess.WRITE)
		file.store_var({"payload":bytes,"checksum":Campaign._hash(bytes)})
		file.close()
		t.check(not loaded.load_save(path) and "view state" in loaded.last_error,"Malformed encoded view state is rejected clearly: " + String(change.state.keys()[-1]))
		t.check(loaded.world.fingerprint() == before,"Rejected view state preserves existing campaign")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_campaign_loop(t)

func _road_budget(t) -> void:
	var sim = Sim.new(73)
	Scenario.starter(sim)
	# Shipped roads are free. Exercise the general placement contract with a
	# priced road recipe, using real materials already held in the storehouse.
	sim.db.buildings.road.cost = {"logs":1}
	var store = sim.buildings.values()[0]
	var unit_price: int = sim.price("logs")
	store.silver += sim.treasury - unit_price
	sim.treasury = unit_price
	var stroke: Array[Vector2i] = []
	for y in sim.grid.height:
		for x in range(sim.grid.width - 2):
			var cell := Vector2i(x,y)
			var candidate: Array[Vector2i] = [cell,cell + Vector2i.RIGHT,cell + Vector2i.RIGHT * 2]
			var valid := true
			for point in candidate: valid = valid and sim.placement_error("road",point).is_empty()
			if valid and sim.grid.passable(candidate[0],candidate[1]) and sim.grid.passable(candidate[1],candidate[2]):
				stroke = candidate
				break
		if not stroke.is_empty(): break
	t.check(stroke.size() == 3 and unit_price > 0,"Budget fixture has three individually affordable road cells")
	if stroke.is_empty(): return
	var before := JSON.stringify(sim.snapshot())
	t.check(not sim.place_road(stroke) and "Treasury needs" in sim.last_error,"Road stroke rejects aggregate cost beyond treasury")
	t.check(JSON.stringify(sim.snapshot()) == before,"Rejected road stroke preserves money, stock, roads, trees and revisions atomically")
	var funding := unit_price * 2
	store.silver -= funding
	sim.treasury += funding
	var logs_before: int = sim.stock("logs")
	stroke.append(stroke[0]) # Duplicate cells must not be charged twice.
	t.check(sim.place_road(stroke),"Fully funded stroke accepts real storehouse materials")
	t.check(sim.treasury == 0 and sim.stock("logs") == logs_before - 3,"Road stroke charges each unique cell once without overdrawing")
	var restored = Sim.from_snapshot(sim.snapshot(),sim.db)
	t.check(restored != null,"Accepted exactly-funded road construction remains restorable")
	if restored != null:
		sim.step(120)
		restored.step(120)
		t.check(JSON.stringify(sim.snapshot()) == JSON.stringify(restored.snapshot()),"Exactly-funded road state continues deterministically after restore")

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
		var original_tile: String = snapshot.site.terrain[0]
		snapshot.site.terrain[0] = "rock" if original_tile != "rock" else "grass"
		t.check(restored.site.terrain[0] == original_tile,"Restored site owns its arrays independently of caller snapshot")
		snapshot.site.terrain[0] = original_tile
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
	# Stop before the first Villager house: a version-one save cannot hold the
	# working-class factions, which both copies then gain at the same tick.
	sim.step(200)
	var campaign = Campaign.new()
	campaign.generate("Legacy hearth",73)
	var site := Campaign._state(sim.site)
	var grid := Campaign._state(sim.grid)
	for key in ["footprint","seed_value","world_coord","hex_width","world_origin","owner_coords","generation_error","promised_water","playability_result","districts"]:
		site.erase(key)
		grid.erase(key)
	var buildings: Array = []
	for building in sim.buildings.values():
		# Version one predates these fields; reset the live village to their
		# defaults so both sides match.
		building.happiness_history = []
		building.crew = 0
		building.wages_paid = 0
		var building_state := Campaign._state(building)
		for key in ["frustration","happiness_history","crew","wages_paid"]:
			building_state.erase(key)
		buildings.append({"id":building.definition.id,"state":building_state,
			"input":building.input.items,"output":building.output.items,"inventory":building.inventory.items})
	var carriers: Array = []
	for carrier in sim.carriers: carriers.append(Campaign._state(carrier))
	# Version one predates treasury reserves, markup and the ledger. With the
	# live village's ledger cleared, both start from the same defaults.
	sim.ledger = []
	sim.period = Economy.blank_period()
	# Nor does it hold favour: the migrated village founds its factions afresh,
	# neutral, while the live one has drifted since its first payday.
	for id in sim.factions.favour:
		sim.factions.favour[id] = 0
	var sim_state := Campaign._state(sim)
	for key in ["public_reserve","capital_reserve","markup_percent","public_frustration","period","ledger"]:
		sim_state.erase(key)
	var payload := {"version":1,"id":"legacy-test","name":"Legacy hearth","seed":73,
		"generator":campaign.world.generator_version,"content":Campaign._content_hash(),
		"village_name":"Old clearing","village_hex":campaign.world.start,
		"village":{"sim":sim_state,"site":site,"grid":grid,"rng":sim.rng.state,
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

func _snapshot_demolition(t) -> void:
	for endpoint in ["source","target"]:
		var campaign = Campaign.new()
		campaign.generate("Cargo demolition",73)
		t.check(campaign.found(campaign.world.start,"Trading hearth"),"Cargo save fixture uses generated campaign site")
		var sim = campaign.village
		if sim == null: continue
		sim.step(240)
		Scenario.complete_chain(sim)
		var selected = null
		for tick in 1200:
			sim.step(1)
			for carrier in sim.carriers:
				if carrier.cargo.is_empty() or carrier.stage != "delivery": continue
				var building = sim.buildings.get(carrier.job.get(endpoint))
				if building != null and building.uid != carrier.owner:
					selected = carrier
					break
			if selected != null: break
		t.check(selected != null,"Demolition fixture captures loaded carrier for " + endpoint)
		if selected == null: continue
		var building = sim.buildings[selected.job[endpoint]]
		t.check(sim.demolish(building.cell),"Live delivery endpoint can be demolished: " + endpoint)
		var restored = Sim.from_snapshot(sim.snapshot())
		t.check(restored != null,"Snapshot accepts valid delivery with demolished " + endpoint)
		if restored == null: continue
		t.check(campaign.save(DIRECTORY),"Campaign saves cargo after endpoint demolition: " + endpoint)
		var loaded = Campaign.new()
		var path := DIRECTORY.path_join(campaign.id + ".campaign")
		t.check(loaded.load_save(path),"Campaign loads cargo after endpoint demolition: " + loaded.last_error)
		if loaded.village != null:
			t.check(JSON.stringify(loaded.village.snapshot()) == JSON.stringify(sim.snapshot()),"Campaign preserves stale delivery endpoint awaiting next tick")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		sim.step(1)
		restored.step(1)
		t.check(JSON.stringify(sim.snapshot()) == JSON.stringify(restored.snapshot()),"Demolished endpoint resolves identically on continuation: " + endpoint)
		if endpoint == "target":
			t.check(selected.job.get("source") == -1 and selected.cargo != "","Demolished buyer makes a real return-to-store cargo job")
			var returning = Sim.from_snapshot(sim.snapshot())
			t.check(returning != null,"Return cargo sentinel survives snapshot restore")
			if returning != null:
				sim.step(200)
				returning.step(200)
				t.check(JSON.stringify(sim.snapshot()) == JSON.stringify(returning.snapshot()),"Returned cargo and trade ledger continue deterministically")
		else:
			sim.step(200)
			restored.step(200)
			t.check(JSON.stringify(sim.snapshot()) == JSON.stringify(restored.snapshot()),"Delivery from demolished producer preserves trade and logistics")

func _campaign_loop(t) -> void:
	var campaign = Campaign.new()
	t.check(campaign.generate("Two villages",73), "Campaign for successive runs generates")
	var first := Vector2i.ZERO
	# A chartered run, then an abandoned one that is resettled below.
	for run_number in 2:
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
		var scouted := true
		for other in campaign.world.hexes:
			if HexMath.distance(coord,other) <= 2 and not campaign.world.hex(other).scouted: scouted = false
		t.check(scouted,"Run scouts radius two")
		var loaded = Campaign.new()
		t.check(loaded.load_save(DIRECTORY.path_join(campaign.id + ".campaign")), "Completed campaign reloads: " + loaded.last_error)
		t.check(loaded.villages == campaign.villages and loaded.world.fingerprint() == campaign.world.fingerprint(), "Records, spacing markers and scouting survive load")
		campaign = loaded
	t.check(campaign.villages.size() == 2, "Successive runs accumulate in one campaign")
	t.check(not campaign.found_blocked(first).is_empty(), "Chartered settlement cannot be overwritten")
	var ruin: Vector2i = campaign.villages[1].hex
	t.check(campaign.found_blocked(ruin).is_empty(), "Abandoned ruin can be resettled: " + campaign.found_blocked(ruin))
	t.check(campaign.found(ruin,"New hearth"), "Resettlement creates a new active run")
	t.check(campaign.active_record().resettlement_bonus.logs == Campaign.RESETTLEMENT_LOGS and campaign.village.reserve.count("logs") == Campaign.RESETTLEMENT_LOGS, "Modest resettlement supplies are recorded and granted")
	var before = campaign.village
	t.check(not campaign.end_and_save("abandoned","res://project.godot") and campaign.village == before and campaign.active_record().status == "active", "Failed end save preserves active run and record")
	campaign.map_view_state = {"quarter_turn":1,"focus":Vector3(1,0,2)}
	campaign.village_view_state = {"village_id":campaign.active_village,"weather":0,"charter_offer_dismissed":true}
	campaign.village_view_state["zoom_size"] = maxf(campaign.village.site.width,campaign.village.site.height) * 1.15
	t.check(campaign.save(DIRECTORY),"Active resettlement saves")
	var loaded = Campaign.new()
	t.check(loaded.load_save(DIRECTORY.path_join(campaign.id + ".campaign")),"Active resettlement reloads")
	t.check(loaded.map_view_state == campaign.map_view_state and loaded.village_view_state == campaign.village_view_state,"Both camera and view settings persist")
	t.check(loaded.village_view_state.get("zoom_size") == campaign.village_view_state.zoom_size,"Exact generated-site maximum overview zoom survives save/load")
	var save_path := DIRECTORY.path_join(campaign.id + ".campaign")
	t.check(not Campaign.delete_save("res://project.godot") and FileAccess.file_exists("res://project.godot"), "Deleting refuses non-campaign files")
	t.check(Campaign.delete_save(save_path) and not FileAccess.file_exists(save_path) and save_path not in Campaign.save_paths(DIRECTORY), "Deleted campaign leaves the save list")
	t.check(not Campaign.delete_save(save_path), "Deleting a missing campaign reports failure")
