extends SceneTree
## GPU checks for the world map scene (docs/PLAN-world-map.md phase A2).
##   godot --path . --script tests/run_world_map_tests.gd
const WorldMapMesh = preload("res://view/world_map/world_map_mesh.gd")
var failures: Array[String] = []
var checks := 0
var view

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _run() -> void:
	view = load("res://view/world_map/world_map_view.tscn").instantiate()
	view.seed_value = 73
	root.add_child(view)
	await _frames(4)
	for seed_value in [73, 1, 2]:
		if seed_value != view.seed_value:
			view.set_seed(seed_value)
			await _frames(3)
		_check_model(seed_value)
		if seed_value != 73: await _capture("world-map-direction-seed-%d.png" % seed_value)
	view.set_seed(73)
	await _frames(3)
	var world = view.world
	await _check_art()
	await _check_motion()
	await _hover(world.start)
	check(view.hovered == world.start and view.panel.visible, "Hovering the start hex selects it and opens the panel")
	check(world.data.biomes[world.hex(world.start).biome].name in view.panel_text.get_parsed_text() and "Starting region" in view.panel_text.get_parsed_text(), "Panel names the hex's biome and marks the start")
	check("can be founded" in view.panel_text.get_parsed_text(), "Panel says the start hex can be founded")
	var peak := _find(func(info): return info.elevation >= 3)
	await _hover(peak)
	check(view.hovered == peak, "Hover picks raised hexes by their prism top")
	var sea := _find(func(info): return not info.is_land() and _coastal(info.coord))
	await _hover(sea)
	check(view.hovered == sea and "Open water" in view.panel_text.get_parsed_text(), "Sea hexes are pickable and described as water")
	var hidden := _find(func(info): return info.is_land() and not info.scouted and world.has_hidden_deposits(info.coord))
	check(hidden != view.NO_HEX, "Test world has an unscouted hex with hidden deposits")
	if hidden != view.NO_HEX:
		await _hover(hidden)
		check("Unscouted" in view.panel_text.get_parsed_text(), "Unscouted hexes say more may be hidden")
		await _key(KEY_V)
		var text: String = view.panel_text.get_parsed_text()
		var all_named := true
		for deposit in world.hex(hidden).deposits:
			all_named = all_named and world.data.deposits[deposit].name in text
		check(all_named and not "Unscouted" in text, "V reveals every deposit on the hovered hex")
		await _key(KEY_V)
	var turn: int = view.camera.quarter_turn
	await _key(KEY_E)
	check(view.camera.quarter_turn == (turn + 1) % 4, "E rotates the map camera")
	await _key(KEY_N)
	check(view.seed_value == 74, "N moves to the next seed")
	await _frames(3)
	await RenderingServer.frame_post_draw
	view.get_viewport().get_texture().get_image().save_png("res://artifacts/world-map-test.png")
	view.queue_free()
	await _frames(2)
	await _village_round_trip()
	print("WORLD MAP: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

## The village's map button opens the map over a paused, hidden village, and
## "Back to village" returns to it unchanged.
func _village_round_trip() -> void:
	var village = load("res://view/village_view.tscn").instantiate()
	root.add_child(village)
	await _frames(4)
	village.sim.step(50)
	var map_button: Button = village.hud.map_button
	check(map_button.visible and map_button.tooltip_text == "World map", "Village HUD has a world map button")
	check(absf(map_button.position.x + 56.0 - village.hud.sun_button.position.x) < 1.0 and map_button.position.y == village.hud.sun_button.position.y, "World map button sits beside the weather button")
	await _click(map_button.get_global_rect().get_center())
	var map = village.world_map_view
	# Taken as the map opens; the running village may have stepped while the click landed.
	var before: String = JSON.stringify(village.sim.snapshot())
	check(map != null and map.is_inside_tree() and map.world != null, "Clicking the map button opens the world map")
	check(not village.visible and not village.hud.visible and village.process_mode == Node.PROCESS_MODE_DISABLED, "The village and its HUD are hidden and paused behind the map")
	check(village.pixel_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "The hidden village stops rendering")
	await _frames(20)
	check(JSON.stringify(village.sim.snapshot()) == before, "The village does not advance while the map is open")
	check(map.back_button.visible, "The map offers Back to village")
	# Speed 0 so frames after the village resumes cannot step it before the comparison.
	village._set_speed(0)
	await _click(map.back_button.get_global_rect().get_center())
	await _frames(2)
	check(village.world_map_view == null and not is_instance_valid(map) and village.hud.visible, "Back to village closes the map and restores the HUD")
	check(village.visible and village.process_mode == Node.PROCESS_MODE_INHERIT and village.pixel_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "The village is shown, running and rendering again")
	check(JSON.stringify(village.sim.snapshot()) == before, "The village returns exactly as it was left")
	village.open_world_map()
	await _frames(2)
	await _key(KEY_ESCAPE)
	await _frames(2)
	check(village.world_map_view == null and village.visible, "Esc on the map also returns to the village")
	village.queue_free()
	await _frames(2)

func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = at
		click.global_position = at
		click.pressed = pressed
		root.push_input(click)
		await _frames(1)

func _check_model(seed_value: int) -> void:
	var land := 0
	for coord in view.world.hexes:
		if view.world.hexes[coord].is_land():
			land += 1
	check(view.model.tops.size() == land, "Seed %d: every land hex has a prism (%d)" % [seed_value, land])
	var models := 0
	for child in view.world_root.get_children():
		if child.name.begins_with("WorldMapModel") and not child.is_queued_for_deletion():
			models += 1
	check(models == 1, "Seed %d: changing seed replaces the model" % seed_value)
	var land_mesh: MeshInstance3D = view.model_root.get_node("Land")
	check(land_mesh.mesh.get_surface_count() == 1 and land_mesh.mesh.surface_get_array_len(0) > land * 30, "Seed %d: land mesh has prism geometry" % seed_value)
	check(view.model_root.get_node("Nature").get_child_count() > 3 and view.model.scenery.instance_count > land, "Seed %d: nature assets are instanced across the map" % seed_value)

func _check_art() -> void:
	view.atmosphere.set_process(false)
	view.atmosphere.reset_art_motion()
	view.atmosphere._tick(0.0)
	check(view.atmosphere.profile.time_of_day == 16.0, "Map uses the village's 16:00 lighting baseline")
	var fingerprint: String = view.world.fingerprint()
	var focus: Vector3 = view.camera.focus
	var zoom: float = view.camera.zoom_size
	var seams := 0
	var maximum_gap := 0.0
	for coord in view.model.tops:
		var info = view.world.hex(coord)
		for edge in 3:
			var other: Vector2i = view.world.neighbour(coord, edge)
			if not view.model.scenery.compatible(coord, other): continue
			for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
				var point: Vector3 = WorldMapMesh.corner(coord, WorldMapMesh.edge_direction(edge) - 30.0).lerp(WorldMapMesh.corner(coord, WorldMapMesh.edge_direction(edge) + 30.0), fraction)
				maximum_gap = maxf(maximum_gap, absf(view.model.surface_height(coord, point) - view.model.surface_height(other, point)))
				seams += 1
	check(seams > 100 and maximum_gap < 0.0001, "Linked relief meets exactly at compatible edges (%d samples; maximum gap %.6f)" % [seams, maximum_gap])
	for coord in view.model.tops:
		for edge in view.world.hex(coord).river_edges:
			var other: Vector2i = view.world.neighbour(coord, edge)
			if not view.model.tops.has(other): continue
			var path: Array[Vector3] = view.model.scenery.river_path(coord, edge)
			var reverse: Array[Vector3] = view.model.scenery.river_path(other, (edge + 3) % 6)
			check(path[-1].distance_to(reverse[-1]) < 0.0001, "River arms share their cross-tile endpoint")
	await _capture("world-map-art-linked.png")
	view.camera.focus = WorldMapMesh.centre(view.world.start)
	view.camera.zoom_size = 12.0
	view.camera.refresh()
	await _capture("world-map-art-close.png")
	view.select_hex(view.world.start)
	var selected: Vector2i = view.selected_hex
	var linked_root = view.model_root
	await _key(KEY_L)
	check(not view.map_art.linked_tiles and view.model_root != linked_root, "L rebuilds the map as separate tile dioramas")
	check(view.selected_hex == selected and view.selection_marker.mesh != null, "Changing art mode preserves the selected site")
	check(view.camera.focus == WorldMapMesh.centre(view.world.start) and view.camera.zoom_size == 12.0, "Changing art mode preserves camera focus and zoom")
	view.camera.focus = focus
	view.camera.zoom_size = zoom
	view.camera.refresh()
	await _capture("world-map-art-tiles.png")
	await _key(KEY_L)
	check(view.map_art.linked_tiles and view.world.fingerprint() == fingerprint, "Art modes preserve the authoritative world")
	view.selection_marker.visible = false
	for step in 12: view._zoom_map(-1)
	check(view.camera.zoom_size == 8.0, "Map zoom reaches the tile scenery and clamps at 8 units")
	view.camera.zoom_size = zoom
	view.camera.refresh()

func _check_motion() -> void:
	var fingerprint: String = view.world.fingerprint()
	var focus: Vector3 = view.camera.focus
	var zoom: float = view.camera.zoom_size
	view.camera.focus = WorldMapMesh.centre(view.world.start)
	view.camera.zoom_size = 8.0
	view.camera.refresh()
	view.model.set_motion_scale(8.0)
	var roots: Dictionary = {}
	for node in view.model_root.get_node("Nature").get_children():
		roots[node.name] = node.multimesh.buffer.duplicate()
	RenderingServer.global_shader_parameter_set("village_wind_time", 0.0)
	var still := await _map_image()
	RenderingServer.global_shader_parameter_set("village_wind_time", 24.0)
	var windy := await _map_image()
	var changes := _changed_pixels(still, windy)
	print("MAP WIND: %d changed pixels with only wind time advancing" % changes)
	check(changes > 100, "Shared breeze visibly moves crowns and grass")
	for node in view.model_root.get_node("Nature").get_children():
		check(node.multimesh.buffer == roots[node.name], "Wind leaves %s roots and instance transforms fixed" % node.name)
	var strength: float = view.map_art.wind_scale
	view.map_art.wind_scale = 0.0
	view.model.set_motion_scale(8.0)
	var calm := await _map_image()
	RenderingServer.global_shader_parameter_set("village_wind_time", 80.0)
	var calm_later := await _map_image()
	check(_changed_pixels(calm, calm_later) < 10, "Zero wind strength freezes visible deformation")
	view.map_art.wind_scale = strength
	view.model.set_motion_scale(8.0)
	# A moving review sequence uses the same presentation clocks as gameplay.
	DirAccess.make_dir_recursive_absolute("res://artifacts/world-map-motion")
	for frame in 32:
		view.atmosphere._tick(0.25)
		var pose := await _map_image()
		pose.resize(960, 540, Image.INTERPOLATE_LANCZOS)
		pose.save_png("res://artifacts/world-map-motion/frame-%03d.png" % frame)
	var clear := await _map_image()
	await _key(KEY_BRACKETLEFT)
	view.atmosphere._tick(0.0)
	check(view.atmosphere.get_time_of_day() == 15.0, "Map lighting responds to the village's hour controls")
	await _key(KEY_BRACKETRIGHT)
	view.atmosphere._tick(0.0)
	await _key(KEY_5)
	check(view.atmosphere.get_target_weather() == AtmosphereProfile.Weather.STORM, "Map accepts the shared storm control")
	var clear_energy: float = view.atmosphere.sun.light_energy
	view.atmosphere.set_weather(AtmosphereProfile.Weather.STORM, 1.0, true)
	view.atmosphere._tick(20.0)
	var storm := await _map_image()
	check(view.atmosphere.sun.light_energy < clear_energy and view.atmosphere.gust_scale > 1.0 and view.atmosphere.wetness > 0.0, "Storm reduces sun, strengthens wind and wets the map")
	check(_changed_pixels(clear, storm) > 1000, "Storm changes the map's light and material response")
	await _capture("world-map-art-storm.png")
	view.atmosphere.set_weather(AtmosphereProfile.Weather.CLEAR, 0.0, true)
	view.atmosphere.wetness = 0.0
	view.atmosphere.set_time_of_day(0.0)
	view.atmosphere._tick(0.0)
	check(view.atmosphere.cloud_shadow == 0.0, "Cloud shadows fade at night on the map")
	await _capture("world-map-art-night.png")
	check(view.world.fingerprint() == fingerprint, "Motion and weather preserve authoritative world state")
	view.atmosphere.set_time_of_day(16.0)
	view.atmosphere.set_weather(AtmosphereProfile.Weather.CLEAR, 0.0, true)
	view.atmosphere.wetness = 0.0
	view.atmosphere.reset_art_motion()
	view.atmosphere._tick(0.0)
	view.atmosphere.set_process(true)
	view.camera.focus = focus
	view.camera.zoom_size = zoom
	view.camera.refresh()
	view.model.set_motion_scale(zoom)

func _map_image() -> Image:
	await _frames(3)
	await RenderingServer.frame_post_draw
	return view.pixel_viewport.get_texture().get_image()

func _changed_pixels(first: Image, second: Image) -> int:
	var changes := 0
	for y in range(80, first.get_height() - 80):
		for x in range(80, first.get_width() - 80):
			var delta := first.get_pixel(x, y) - second.get_pixel(x, y)
			if absf(delta.r) + absf(delta.g) + absf(delta.b) > 0.025: changes += 1
	return changes

func _capture(filename: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	check(view.get_viewport().get_texture().get_image().save_png("res://artifacts/" + filename) == OK, "Saved " + filename)

func _find(test: Callable) -> Vector2i:
	for coord in view.world.hexes:
		if test.call(view.world.hexes[coord]):
			return coord
	return view.NO_HEX

func _coastal(coord: Vector2i) -> bool:
	for other in view.world.neighbours(coord):
		if view.world.hex(other).is_land():
			return true
	return false

## Moves the real mouse over a hex's centre, at its prism top.
func _hover(coord: Vector2i) -> void:
	var at: Vector3 = WorldMapMesh.centre(coord) + Vector3.UP * view.model.top_of(coord)
	var pixel: Vector2 = view.camera.unproject_position(at)
	var move := InputEventMouseMotion.new()
	move.position = view.display.position + pixel * view.display.size / Vector2(view.pixel_viewport.size)
	root.push_input(move)
	await _frames(2)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	await _frames(1)

func _frames(count: int) -> void:
	for index in count:
		await process_frame
