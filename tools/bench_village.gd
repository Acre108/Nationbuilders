extends SceneTree
## Village performance benchmark. Needs a real window and GPU: the headless
## dummy renderer reports zero draw calls and no GPU time.
##   Godot.exe --path . --script tools/bench_village.gd [-- --quick]
## Prints a table and writes artifacts/bench-village.json.
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const Campaign = preload("res://sim/campaign.gd")
var quick := false
var results := {}
var view

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	quick = "--quick" in OS.get_cmdline_user_args()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("== Village benchmark (%s, %s) ==" % [RenderingServer.get_video_adapter_name(), Engine.get_version_info().string])
	if "--gpu-breakdown" in OS.get_cmdline_user_args():
		await _gpu_breakdown()
		quit(0)
		return
	_bench_sim()
	if "--sim-only" in OS.get_cmdline_user_args():
		quit(0)
		return
	await _bench_render()
	var file := FileAccess.open("res://artifacts/bench-village.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(results, "  "))
	quit(0)

# --- Simulation -------------------------------------------------------------

func _starter_sim():
	var sim = Sim.new(73)
	Scenario.starter(sim)
	Scenario.complete_chain(sim)
	return sim

## Grows the starter into a dense town with every building kind: a road
## lattice around the founding spot, filled with whatever fits.
func _grown_sim(target_buildings: int = 40):
	var sim = _starter_sim()
	sim.unlocked_tier = 2
	var origin: Vector2i = sim.site.founding_spot
	var lattice: Array[Vector2i] = []
	for row in range(-3, 4):
		for x in range(-18, 19):
			lattice.append(origin + Vector2i(x, row * 5))
	for column in range(-3, 4):
		for y in range(-15, 16):
			lattice.append(origin + Vector2i(column * 6, y))
	for cell in lattice:
		_top_up(sim)
		sim.place_road([cell])
	var kinds := ["house","house","house","house","storehouse","well","farm","woodcutter","forester","mill","bakery"]
	var index := 0
	for radius in range(1, 22):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius or sim.buildings.size() >= target_buildings: continue
				_top_up(sim)
				if sim.place(kinds[index % kinds.size()], origin + Vector2i(x, y)):
					index += 1
	return sim

func _top_up(sim) -> void:
	sim.treasury = 10000000
	for good in ["logs", "berries"]:
		sim.reserve.items[good] = 120

func _tick_stats(sim, warmup: int, ticks: int) -> Dictionary:
	sim.step(warmup)
	var samples: Array[float] = []
	for i in ticks:
		var started := Time.get_ticks_usec()
		sim.step(1)
		samples.append((Time.get_ticks_usec() - started) / 1000.0)
	var stats := _stats(samples)
	stats["buildings"] = sim.buildings.size()
	stats["carriers"] = sim.carriers.size()
	stats["roads"] = sim.grid.roads.size()
	return stats

func _bench_sim() -> void:
	var ticks := 300 if quick else 1500
	results["sim_starter"] = _tick_stats(_starter_sim(), 300, ticks)
	var grown = _grown_sim(40)
	results["sim_grown"] = _tick_stats(grown, 300, ticks)
	print("\n-- Sim tick cost (ms per tick; 1x = 10 ticks/s, 3x = 30 ticks/s) --")
	for key in ["sim_starter", "sim_grown"]:
		var s: Dictionary = results[key]
		print("%-12s %2d bldg %3d carriers %4d roads | mean %.3f  p95 %.3f  p99 %.3f  max %.3f | 3x budget %.1f ms/s" % [key, s.buildings, s.carriers, s.roads, s.mean, s.p95, s.p99, s.max, s.mean * 30.0])

# --- Rendering --------------------------------------------------------------

func _bench_render() -> void:
	print("\n-- Rendering (1280x720 window, vsync off) --")
	print("%-34s %7s %7s %7s %7s | %6s %6s | %6s %9s %6s %6s" % ["scenario", "mean", "p95", "p99", "max", "cpu", "gpu", "draws", "prims", "objs", "nodes"])
	view = load("res://view/village_view.tscn").instantiate()
	var started := Time.get_ticks_usec()
	root.add_child(view)
	results["startup_first_bread_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	await _frames(5)
	RenderingServer.viewport_set_measure_render_time(view.pixel_viewport.get_viewport_rid(), true)
	var home_focus: Vector3 = view.camera.focus
	view._set_speed(0)
	await _measure("starter / default zoom / paused")
	view._overview_site()
	await _measure("starter / overview / paused")
	_focus(home_focus, 22.0)
	view._set_speed(3)
	await _measure("starter / default zoom / 3x")
	view._set_speed(0)
	await _hitches("starter")

	# Dense town on the same map.
	view.sim = _grown_sim(40)
	started = Time.get_ticks_usec()
	view._refresh_village()
	results["refresh_grown_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	view.sim.step(300)
	_focus(home_focus, 22.0)
	view._set_speed(3)
	await _frames(5)
	await _measure("grown / default zoom / 3x")
	view._overview_site()
	await _measure("grown / overview / 3x")
	view._set_speed(0)
	await _hitches("grown")
	view.queue_free()
	await _frames(3)

	# The real game path: a generated campaign site.
	var campaign = Campaign.new()
	campaign.generate("Bench", 73)
	campaign.found(campaign.world.start, "Bench")
	view = load("res://view/village_view.tscn").instantiate()
	view.campaign = campaign
	started = Time.get_ticks_usec()
	root.add_child(view)
	results["startup_campaign_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	await _frames(5)
	RenderingServer.viewport_set_measure_render_time(view.pixel_viewport.get_viewport_rid(), true)
	view._set_speed(0)
	await _measure("campaign site / default / paused")
	view._overview_site()
	await _measure("campaign site / overview / paused")
	view._set_speed(3)
	await _measure("campaign site / overview / 3x")
	view._set_speed(0)
	await _hitches("campaign")
	print("\n-- Startup (ms) --")
	for key in ["startup_first_bread_ms", "refresh_grown_ms", "startup_campaign_ms"]:
		print("%-24s %8.1f" % [key, results[key]])

## Turns one feature off at a time on the starter village to attribute GPU time.
func _gpu_breakdown() -> void:
	view = load("res://view/village_view.tscn").instantiate()
	root.add_child(view)
	await _frames(5)
	RenderingServer.viewport_set_measure_render_time(view.pixel_viewport.get_viewport_rid(), true)
	view._set_speed(0)
	var sun: DirectionalLight3D = view.atmosphere.sun
	var env: Environment = view.atmosphere.world_environment.environment
	var home: Vector3 = view.camera.focus
	print("%-34s %7s %7s %7s %7s | %6s %6s | %6s %9s %6s %6s" % ["scenario", "mean", "p95", "p99", "max", "cpu", "gpu", "draws", "prims", "objs", "nodes"])
	for zoom in ["default", "overview"]:
		if zoom == "overview": view._overview_site()
		else: _focus(home, 22.0)
		await _measure("%s / everything" % zoom)
		sun.shadow_enabled = false
		await _measure("%s / no sun shadows" % zoom)
		sun.shadow_enabled = true
		var mode := sun.directional_shadow_mode
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		await _measure("%s / 2 shadow splits" % zoom)
		sun.directional_shadow_mode = mode
		var casters: Array = []
		for plant in view.foliage.plants.values():
			if plant.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: casters.append(plant)
			plant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if plant.has_node("ShadowProxy"): plant.get_node("ShadowProxy").visible = false
		await _measure("%s / trees cast no shadow" % zoom)
		for plant in view.foliage.plants.values():
			if plant in casters: plant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if plant.has_node("ShadowProxy"): plant.get_node("ShadowProxy").visible = true
		for plant in view.foliage.plants.values(): plant.visible = false
		await _measure("%s / trees hidden" % zoom)
		view.foliage.sync_grid(view.sim.grid)
		view.foliage.grass.visible = false
		await _measure("%s / grass hidden" % zoom)
		view.foliage.grass.visible = true
		var ssao := env.ssao_enabled
		env.ssao_enabled = false
		await _measure("%s / no SSAO" % zoom)
		env.ssao_enabled = ssao
		view.pixel_viewport.msaa_3d = Viewport.MSAA_DISABLED
		await _measure("%s / no MSAA" % zoom)
		view.pixel_viewport.msaa_3d = Viewport.MSAA_4X
		view.buildings_root.visible = false
		await _measure("%s / buildings hidden" % zoom)
		view.buildings_root.visible = true
	var counts := {}
	for plant in view.foliage.plants.values():
		var key := str(plant.mesh.get_instance_id())
		if not counts.has(key):
			var triangles := 0
			for surface in plant.mesh.get_surface_count():
				var arrays: Array = plant.mesh.surface_get_arrays(surface)
				var indices = arrays[Mesh.ARRAY_INDEX]
				triangles += (indices.size() if indices != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
			counts[key] = {"triangles": triangles, "count": 0, "surfaces": plant.mesh.get_surface_count()}
		counts[key].count += 1
	var total := 0
	for key in counts: total += counts[key].triangles * counts[key].count
	print("\ntree meshes %d, plants %d, triangles in all plants %d" % [counts.size(), view.foliage.plants.size(), total])
	for key in counts: print("  mesh %s: %d tris x %d plants, %d surfaces" % [key, counts[key].triangles, counts[key].count, counts[key].surfaces])
	print("grass tufts %d (tris per tuft %d)" % [view.foliage.grass.multimesh.instance_count, view.foliage.grass_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3 if view.foliage.grass_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] != null else 0])
	print("sun: mode %d, max distance %.0f" % [sun.directional_shadow_mode, sun.directional_shadow_max_distance])

func _focus(focus: Vector3, zoom: float) -> void:
	view.camera.focus = focus
	view.camera.zoom_size = zoom
	view.camera.refresh()

func _frames(count: int) -> void:
	for i in count: await process_frame

func _measure(label: String) -> void:
	await _frames(20)
	var frames := 120 if quick else 400
	var samples: Array[float] = []
	var cpu := 0.0
	var gpu := 0.0
	var rid: RID = view.pixel_viewport.get_viewport_rid()
	var last := Time.get_ticks_usec()
	for i in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now - last) / 1000.0)
		last = now
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var stats := _stats(samples)
	stats["render_cpu"] = cpu / frames
	stats["render_gpu"] = gpu / frames
	stats["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	stats["primitives"] = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	stats["objects"] = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	stats["nodes"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	stats["video_mem_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	results[label] = stats
	print("%-34s %7.2f %7.2f %7.2f %7.2f | %6.2f %6.2f | %6d %9d %6d %6d" % [label, stats.mean, stats.p95, stats.p99, stats.max, stats.render_cpu, stats.render_gpu, stats.draw_calls, stats.primitives, stats.objects, stats.nodes])

## One-off costs a player feels as a stall: a road edit, a felled tree, a new
## building and the placement ghost following the mouse.
func _hitches(label: String) -> void:
	var sim = view.sim
	var hitch := {}
	var road_cell := Vector2i(-1, -1)
	for radius in range(2, 20):
		for cell in [sim.site.founding_spot + Vector2i(radius, 6), sim.site.founding_spot + Vector2i(-radius, -6)]:
			if road_cell.x < 0 and sim.placement_error("road", cell).is_empty(): road_cell = cell
	_top_up(sim)
	var started := Time.get_ticks_usec()
	if road_cell.x >= 0 and sim.place_road([road_cell]):
		view._sync_view()
		hitch["road_placed_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	var tree: Vector2i = sim.grid.trees.keys()[sim.grid.trees.size() / 2]
	started = Time.get_ticks_usec()
	sim.grid.clear_tree(tree, true)
	view._sync_view()
	hitch["tree_felled_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	var site := Vector2i(-1, -1)
	for radius in range(2, 25):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if site.x < 0 and sim.placement_error("house", sim.site.founding_spot + Vector2i(x, y)).is_empty():
					site = sim.site.founding_spot + Vector2i(x, y)
	if site.x >= 0:
		started = Time.get_ticks_usec()
		sim.place("house", site)
		view._sync_view()
		hitch["house_placed_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	view.tool.choose("bakery")
	view.pointer_position = view.display.get_global_rect().get_center()
	var ghost: Array[float] = []
	for i in 10:
		view.ghost_signature = ""
		started = Time.get_ticks_usec()
		view._update_ghost()
		ghost.append((Time.get_ticks_usec() - started) / 1000.0)
	hitch["ghost_rebuild_ms"] = _stats(ghost).mean
	view.tool.choose("inspect")
	started = Time.get_ticks_usec()
	view.hud.refresh(sim, -1, "inspect")
	hitch["hud_refresh_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	var house_uid := -1
	for building in sim.buildings.values():
		if building.definition.kind == "house": house_uid = building.uid
	started = Time.get_ticks_usec()
	view.hud.refresh(sim, house_uid, "inspect")
	hitch["hud_refresh_inspect_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	view._sync_view()
	hitch["sync_view_steady_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	results["hitch_" + label] = hitch
	var parts: Array[String] = []
	for key in hitch: parts.append("%s %.1f" % [key.trim_suffix("_ms"), hitch[key]])
	print("   hitches %-9s %s" % [label, ", ".join(parts)])
	await _frames(5)

func _stats(samples: Array[float]) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted: total += value
	var n := sorted.size()
	return {"mean": total / n, "p95": sorted[mini(n - 1, int(n * 0.95))], "p99": sorted[mini(n - 1, int(n * 0.99))], "max": sorted[n - 1], "samples": n}
