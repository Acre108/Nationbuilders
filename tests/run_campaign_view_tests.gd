extends SceneTree
const Campaign = preload("res://sim/campaign.gd")
const MapMesh = preload("res://view/world_map/world_map_mesh.gd")
var checks := 0
var failures: Array[String] = []
var app
var save_path := ""

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func frames(count: int = 3) -> void:
	for index in count: await process_frame

func click(button: Control) -> void:
	var position := button.get_global_rect().get_center()
	await click_at(position)

func click_at(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	Input.parse_input_event(motion)
	await frames(2)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)

func keypress(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)

func select_hex_by_mouse(coord: Vector2i) -> void:
	var map = app.map_view
	map.center_on(coord)
	await frames(2)
	var point: Vector3 = MapMesh.centre(coord) + Vector3.UP * map.model.top_of(coord)
	var pixel: Vector2 = map.camera.unproject_position(point)
	await click_at(map.display.position + pixel * map.display.size / Vector2(map.pixel_viewport.size))

func next_site() -> Vector2i:
	for coord in app.campaign.world.hexes:
		if app.campaign.found_blocked(coord).is_empty() and app.campaign.world.check_site(coord).is_empty(): return coord
	return Vector2i(-999, -999)

func overview_frames_site(village) -> bool:
	# Measure the generated mask's actual hull, including its staircase edge.
	# Inspect both the highest terrain and the underside of the visible board.
	var points := PackedVector2Array()
	for y in village.sim.grid.height:
		for x in village.sim.grid.width:
			var cell := Vector2i(x, y)
			if not village.sim.grid.inside(cell): continue
			for offset in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
				points.append(Vector2(cell) + offset)
	var viewport_rect := Rect2(Vector2.ONE * 2.0, Vector2(village.pixel_viewport.size) - Vector2.ONE * 4.0)
	for point in Geometry2D.convex_hull(points):
		for height in [-1.1, village.relief.top]:
			if not viewport_rect.has_point(village.camera.unproject_position(Vector3(point.x, height, point.y))): return false
	return true

func capture(filename: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/" + filename)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	app = preload("res://view/main_menu.tscn").instantiate()
	root.add_child(app)
	await frames(5)
	check(app.menu.visible and app.map_view == null and app.village_view == null, "Main menu opens before a world or village")
	await capture("campaign-main-menu.png")
	app.seed_input.text = "invalid"
	app._new_campaign()
	check(app.menu.visible and "whole-number" in app.status.text, "Invalid seed stays in menu with feedback")
	app.seed_input.text = "73"
	app.campaign_name.text = "View test campaign"
	app._new_campaign()
	await frames(6)
	check(app.map_view != null and not app.menu.visible, "Generate world opens the campaign map")
	if app.map_view == null:
		quit(1)
		return
	save_path = Campaign.SAVE_DIRECTORY.path_join(app.campaign.id + ".campaign")
	check(FileAccess.file_exists(save_path), "New campaign is saved before founding")
	check(app.map_view.world == app.campaign.world, "Map displays the campaign world")
	app._select_region(app.campaign.world.coord_at(0, 0))
	check(app.found_button.disabled, "Ocean regions disable founding")
	var map = app.map_view
	var coord: Vector2i = app.campaign.world.start
	var point: Vector3 = MapMesh.centre(coord) + Vector3.UP * map.model.top_of(coord)
	var pixel: Vector2 = map.camera.unproject_position(point)
	await click_at(map.display.position + pixel * map.display.size / Vector2(map.pixel_viewport.size))
	check(map.selected_hex == coord and app.selected_hex == coord, "Clicking a world hex selects its founding region")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_N
	key.pressed = true
	Input.parse_input_event(key)
	await frames()
	key.pressed = false
	Input.parse_input_event(key)
	check(map.seed_value == 73, "Campaign map cannot replace its world with the debug seed shortcut")
	await capture("campaign-world-selection.png")
	app.founding_name.text = "Amber Hearth"
	app.founding_name.grab_focus()
	await keypress(KEY_ENTER)
	await frames(6)
	check(app.village_view != null and app.map_view == null, "Found first village enters the village view")
	if app.village_view == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
		quit(1)
		return
	var village = app.village_view
	village._set_speed(0)
	check(village.sim == app.campaign.village and village.hud.campaign_save_button.visible and not village.hud.restart_button.visible, "Village uses campaign simulation and save controls")
	village.sim.step(40)
	village.camera.focus += Vector3(2, 0, 2)
	village.camera.rotate_quarter(1)
	village.camera.zoom_size = 36.0
	village.camera.refresh()
	village.atmosphere.set_time_of_day(15.0)
	village.atmosphere.set_wind(67.0, 0.5, 1.3)
	var expected_wind_strength: float = village.art_profile.wind_strength
	var expected_wind_speed: float = village.art_profile.wind_speed
	village._toggle_deposits()
	var expected_focus: Vector3 = village.camera.focus
	var original_id: String = app.campaign.id
	app.campaign.id = "unwritable/subfolder/save"
	app._leave_village()
	check(app.village_view == village and app.map_view == null and not village.hud.toast_label.text.is_empty(), "Failed return save keeps the running village with useful feedback")
	app.campaign.id = original_id
	village.autosave_elapsed = 119.99
	village._process(0.02)
	check(village.autosave_elapsed < 1.0 and village.hud.toast_label.text == "Campaign saved.", "Two-minute autosave captures the current village")
	var before: String = JSON.stringify(village.sim.snapshot())
	await capture("campaign-first-village.png")
	await click(village.hud.map_button)
	await frames(5)
	check(app.map_view != null and app.village_view == null, "World map button saves and suspends the village")
	check(JSON.stringify(app.campaign.village.snapshot()) == before, "Returning to the map preserves the village state")
	check(app.village_list.item_count == 1 and "Active" in app.village_list.get_item_text(0), "Village list shows the active village status")
	check(app.map_view.campaign_overlays.get_child_count() == 1 and app.map_view.campaign_overlays.get_node_or_null(NodePath(app.campaign.active_village)) != null, "Active village has one map marker")
	await click_at(app.village_list.global_position + app.village_list.get_item_rect(0).get_center())
	check(app.selected_hex == coord and "Amber Hearth" in app.village_detail.text, "Clicking a village row centres its site and shows run statistics")
	app._select_region(app.campaign.world.coord_at(0, 0))
	check(app.found_button.disabled and app.resume_button.visible and not app.resume_button.disabled, "Selecting an ocean hex never disables independent active resume")
	await click(app.resume_button)
	await frames(4)
	check(app.village_view.camera.focus == expected_focus and app.village_view.camera.quarter_turn == 1 and app.village_view.camera.zoom_size == 36.0, "Resume restores the village camera")
	check(app.village_view.speed == 0 and app.village_view.deposits_root.visible and is_equal_approx(app.village_view.atmosphere.get_time_of_day(), 15.0), "Resume restores pause, deposits and daylight settings")
	check(is_equal_approx(app.village_view.atmosphere.wind_breeze(), 0.5) and is_equal_approx(app.village_view.atmosphere.wind_gust_speed(), 1.3) and is_equal_approx(app.village_view.atmosphere.wind_from_degrees(), 67.0) and is_equal_approx(app.village_view.art_profile.wind_strength, expected_wind_strength) and is_equal_approx(app.village_view.art_profile.wind_speed, expected_wind_speed), "Resume restores nondefault wind direction, breeze and gust speed without compounding authored strength")
	app._leave_village()
	await frames(4)
	var loaded = Campaign.new()
	check(loaded.load_save(save_path) and JSON.stringify(loaded.village.snapshot()) == before, "World map transition persists the exact village progress")
	app._return_menu()
	await frames()
	check(app.menu.visible and app.saves.item_count > 0, "Save and main menu lists the campaign")
	var index: int = app.paths.find(save_path)
	app.saves.select(index)
	app._load_campaign()
	await frames(5)
	check(app.campaign.village_name == "Amber Hearth" and app.resume_button.text == "Resume Amber Hearth", "Loading offers the saved village by name")
	await click(app.resume_button)
	app.village_view._set_speed(0)
	await frames(3)
	check(app.village_view.sim.tick >= 40, "Loaded campaign resumes progress instead of restarting")
	app.village_view.sim.unlocked_tier = 2
	await frames(15)
	check(app.village_view.hud.run_card.visible and app.village_view.hud.run_card_kind == "charter", "Reaching the highest tier offers a charter")
	await capture("campaign-charter-card.png")
	await click(app.village_view.hud.run_secondary_button)
	await frames(15)
	check(not app.village_view.hud.run_card.visible and app.village_view.charter_offer_dismissed, "Keep building dismisses the charter offer without repeated interruption")
	await click(app.village_view.hud.cog_button)
	await click(app.village_view.hud.campaign_charter_button)
	var active_id: String = app.campaign.active_village
	app.campaign.id = "unwritable/subfolder/save"
	app._end_run("charter")
	check(app.village_view != null and app.village_view.hud.run_card.visible and app.campaign.active_village == active_id and app.campaign.active_record().status == "active", "Failed result save preserves the active run and confirmation card")
	app.campaign.id = original_id
	await keypress(KEY_ENTER)
	await frames(5)
	check(app.map_view != null and app.campaign.village == null and app.campaign.villages[0].status == "chartered", "Chartering ends the first run and returns to its map marker")
	check("Chartered" in app.map_view.describe(coord) and not "Resume" in app.map_view.describe(coord), "Chartered hex offers review instead of an unavailable resume")
	var second_site := next_site()
	check(second_site != Vector2i(-999, -999), "Campaign offers another appropriately spaced site")
	await select_hex_by_mouse(second_site)
	check(app.selected_hex == second_site and not app.found_button.disabled, "Mouse selects the next village site after a charter")
	app.founding_name.text = "Willow Crossing"
	await click(app.found_button)
	await frames(5)
	check(app.village_view != null and app.campaign.villages.size() == 2, "Second village begins without replacing the chartered record")
	if app.village_view == null:
		printerr("Founding feedback at %s: %s" % [second_site, app.map_status.text])
		await capture("campaign-next-site-error.png")
		app.queue_free()
		await frames()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
		quit(1)
		return
	app.village_view._set_speed(0)
	await click(app.village_view.hud.cog_button)
	await click(app.village_view.hud.campaign_abandon_button)
	check(app.village_view.hud.run_card_kind == "abandoned", "Abandon opens a confirmation card")
	await keypress(KEY_ESCAPE)
	check(not app.village_view.hud.run_card.visible and app.campaign.village != null, "Escape cancels abandonment and retains the village")
	await click(app.village_view.hud.cog_button)
	await click(app.village_view.hud.campaign_abandon_button)
	await click(app.village_view.hud.run_primary_button)
	await frames(5)
	check(app.map_view != null and app.campaign.villages[1].status == "abandoned" and app.campaign.active_village.is_empty(), "Confirmed abandon ends the active run and leaves its ruin")
	await select_hex_by_mouse(second_site)
	check(not app.found_button.disabled and "Resettle" in app.found_button.text, "A ruin can be selected for resettlement")
	check("Resettlement bonus: 12 starting logs" in app.region_text.text and "resettl" in app.map_view.describe(second_site).to_lower(), "Ruin founding card explains its bonus and hover offers resettlement")
	app.founding_name.text = "Willow Renewed"
	await click(app.found_button)
	await frames(5)
	check(app.village_view != null and app.campaign.villages.size() == 3 and app.campaign.active_record().resettlement_bonus.logs > 0, "Third run resettles the ruin and preserves all campaign records")
	app.village_view._set_speed(0)
	root.size = Vector2i(960, 640)
	await frames(4)
	await keypress(KEY_HOME)
	check(app.village_view.camera.zoom_size == app.village_view.camera.zoom_max and app.village_view.camera.focus.x == app.village_view.sim.grid.width * 0.5 and app.village_view.camera.focus.z == app.village_view.sim.grid.height * 0.5, "Home centres and frames the whole generated hex")
	check(overview_frames_site(app.village_view), "Overview keeps the actual hex hull, raised terrain and soil base inside the viewport at 960")
	await capture("campaign-site-overview-960.png")
	var overview_focus: Vector3 = app.village_view.camera.focus
	var overview_zoom: float = app.village_view.camera.zoom_size
	app._leave_village()
	await frames(4)
	check(app.map_view.campaign_overlays.get_child_count() == 2 and app.map_view.campaign_overlays.get_node_or_null(NodePath(app.campaign.villages[1].id)) == null and app.map_view.campaign_overlays.get_node_or_null(NodePath(app.campaign.active_village)) != null, "Resettlement draws the latest active marker once and keeps earlier ruins in history")
	await click(app.resume_button)
	await frames(4)
	check(app.village_view.camera.focus == overview_focus and app.village_view.camera.zoom_size == overview_zoom and overview_frames_site(app.village_view), "Map return and resume preserve the overview camera framing")
	app.village_view.camera.zoom_size = 22.0
	app.village_view.camera.refresh()
	await click(app.village_view.hud.cog_button)
	await click(app.village_view.hud.site_overview_button)
	check(app.village_view.camera.zoom_size == overview_zoom and not app.village_view.hud.options_menu.visible, "Site overview button frames the hex and closes options")
	await click(app.village_view.hud.cog_button)
	await frames(4)
	check(app.village_view.hud.options_menu.get_global_rect().end.y <= 640.0, "Campaign options fit the minimum window height")
	await capture("campaign-options-960.png")
	app._leave_to_menu()
	await frames(5)
	check(app.menu.visible, "Village save and main menu returns at minimum window size")
	await capture("campaign-menu-960.png")
	var resumed = Campaign.new()
	var reloaded: bool = resumed.load_save(save_path)
	check(reloaded and resumed.villages.size() == 3 and resumed.village_name == "Willow Renewed", "Saving three runs reloads the active resettled village and history: " + resumed.last_error)
	app.queue_free()
	await frames()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("CAMPAIGN VIEW: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
