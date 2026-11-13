extends SceneTree
## Real Forward+ render and input smoke. Needs a GPU, unlike run_tests.gd.
const Economy = preload("res://sim/economy.gd")
var failures: Array[String] = []
var checks := 0
var view

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _run() -> void:
	view = load("res://view/village_view.tscn").instantiate()
	root.add_child(view)
	await process_frame
	view._set_speed(0)
	check(view.sim.construction_sites, "Play places construction sites")
	# Most checks test finished buildings; _check_construction() turns sites on.
	view.sim.construction_sites = false
	check(view.sim.grid.width == 100 and view.sim.grid.height == 100, "Playable default map is 100 by 100")
	check(view.camera.bounds.end == Vector2(95,95), "Camera bounds cover the expanded default map")
	var starting_focus: Vector3 = view.camera.focus
	view.camera.pan(Vector2(1,-1).normalized(),10.0)
	check(view.camera.focus.x > 40 or view.camera.focus.z > 40, "Camera can pan past the old map boundary")
	view.camera.focus = starting_focus
	view.camera.refresh()
	var starter_size: int = preload("res://sim/scenario.gd").STARTER.size()
	check(view.sim.buildings.size() == starter_size, "Playable starter has its %d buildings (%d)" % [starter_size, view.sim.buildings.size()])
	var bottom_buttons: Array = view.hud.bottom.get_child(0).get_children().filter(func(node): return node is Button)
	check(bottom_buttons.size() == 6 and view.hud.overlays_button in bottom_buttons and view.hud.speed_buttons[3] in bottom_buttons, "Bottom bar holds speed, Build, Overlays and Demolish")
	check(not view.hud.sun_button.visible, "The weather panel's sun button is a developer tool, hidden by default")
	check(not view.hud.side.visible and not view.hud.build_menu.visible and not view.hud.toast.visible, "Start has no persistent text panels")
	check(not view.hud.blocks_mouse(Vector2(640,40)), "Top of play screen is unobstructed")
	var bar: Rect2 = view.hud.stock_bar.get_global_rect()
	var chips: Dictionary = view.hud.resource_chips
	check(view.hud.stock_bar.visible and chips.keys() == ["water","fuel","materials","ingredients","storage","workers"] and view.hud.stock_bar.is_ancestor_of(view.hud.food_button), "The top bar shows food, water, fuel, materials, ingredients, storage and workers")
	check(chips.workers[1].text == "%d/%d" % [view.sim.workforce() - view.sim.idle_workers, view.sim.workforce()] and "Dependents" in chips.workers[0].tooltip_text, "The worker chip shows adults in work of all, with dependents on hover (%s)" % chips.workers[0].tooltip_text.replace("
"," | "))
	check(chips.materials[1].text == str(view.sim.stock("logs") + view.sim.stock("planks")) and "Logs" in chips.materials[0].tooltip_text and "Planks" in chips.materials[0].tooltip_text, "A category shows its total and breaks it down on hover (%s)" % chips.materials[0].tooltip_text.replace("\n"," | "))
	check("Berries" in view.hud.food_button.tooltip_text and "/" in chips.storage[1].text, "The food chip lists each food; storage shows its fill")
	var top_right: float = view.hud.factions_button.get_global_rect().position.x if view.hud.factions_button.visible else view.hud.map_button.get_global_rect().position.x
	check(bar.position.x >= view.hud.treasury_button.get_global_rect().end.x and bar.end.x < top_right, "The top bar sits between the gold counter and the top-right buttons")
	# The first input of the run needs the GUI settled first.
	await process_frame
	await process_frame
	await _click(view.hud.speed_buttons[3].get_global_rect().get_center())
	check(view.speed == 3 and view.hud.speed_buttons[3].button_pressed, "Bottom bar sets triple simulation speed (speed %d, pressed %s, blocked %s)" % [view.speed, str(view.hud.speed_buttons[3].button_pressed), str(view.hud.speed_buttons[3].get_global_rect())])
	await _click(view.hud.speed_buttons[1].get_global_rect().get_center())
	check(view.speed == 1 and not view.hud.speed_buttons[3].button_pressed, "Bottom bar switches speed selection exclusively")
	await _click(view.hud.speed_buttons[0].get_global_rect().get_center())
	check(view.speed == 0 and view.hud.speed_buttons[0].button_pressed, "Bottom bar pauses simulation")
	await _click(view.hud.cog_button.get_global_rect().get_center())
	check(view.hud.options_menu.visible and view.hud.cog_button.button_pressed, "Top-right cog opens options")
	await _click_cell(_cell(21,21))
	check(view.selected_uid == -1, "Options block clicks on buildings behind menu")
	check(view.display.material == null, "Village display has no palette post-processing material")
	check(view.factory.material.shader.resource_path == "res://render/world.gdshader", "Old meshes use the environment-lit world material")
	var option_labels: Array[String] = []
	_collect_button_text(view.hud.options_menu, option_labels)
	check(not option_labels.is_empty() and not " ".join(option_labels).to_lower().contains("pixel") and not "pixel_effect_button" in view.hud, "Options menu offers no pixel effect (%s)" % ", ".join(option_labels))
	check(view.pixel_viewport.size == Vector2i(1280,720) and view.display.size == Vector2(1280,720) and view.display.position == Vector2.ZERO, "World renders at full display resolution")
	check(view.pixel_viewport.msaa_3d == Viewport.MSAA_4X and view.display.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR, "World render is antialiased and smoothly filtered")
	var camera_before: Vector3 = view.camera.position
	view.camera.focus += Vector3(0.01,0,0)
	view.camera.refresh()
	check((view.camera.position-camera_before-Vector3(0.01,0,0)).length() < 0.001, "Camera follows sub-pixel movement without snapping")
	view.camera.focus -= Vector3(0.01,0,0)
	view.camera.refresh()
	var original_size: Vector2 = view.size
	view.size = Vector2(1440,900)
	check(view.pixel_viewport.size == Vector2i(1440,810) and view.display.position == Vector2(0,45),"Smooth rendering follows window size with the same framing")
	var world_pixel: Vector2 = view.camera.unproject_position(Vector3(_cell(21,21).x+0.5,0,_cell(21,21).y+0.5))
	check(view.camera.cell_at(view._display_to_viewport(view.display.position+world_pixel)) == _cell(21,21),"Letterboxed full-resolution input maps to the correct world cell")
	view.size = original_size
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/options-menu.png")
	await _click(view.hud.close_options_button.get_global_rect().get_center())
	check(not view.hud.options_menu.visible and not view.hud.cog_button.button_pressed, "Options close button resets cog")
	await _click_cell(_cell(21,21))
	check(view.selected_uid == view.sim.grid.occupied.get(_cell(21,21)),"Building inspection works at full resolution")
	await _key(KEY_ESCAPE)
	await _click(view.hud.cog_button.get_global_rect().get_center())
	await _key(KEY_ESCAPE)
	check(not view.hud.options_menu.visible, "Escape closes options")
	await _click(view.hud.cog_button.get_global_rect().get_center())
	await _click(view.hud.restart_button.get_global_rect().get_center())
	check(view.sim.tick <= 1 and view.sim.buildings.size() == starter_size and not view.hud.options_menu.visible, "Options restart resets village and closes menu")
	view.sim.construction_sites = false
	view._set_speed(0)
	await _key(KEY_F12)
	check(view.hud.sun_button.visible and view.hud.sun_button.position.x < view.hud.cog_button.position.x and view.hud.map_button.position.x < view.hud.sun_button.position.x, "F12 shows the sun button left of the cog")
	await _click(view.hud.sun_button.get_global_rect().get_center())
	check(view.hud.weather_menu.visible and view.hud.sun_button.button_pressed, "Sun button opens weather panel")
	check(view.hud.weather_buttons[AtmosphereProfile.Weather.CLEAR].button_pressed and not view.hud.intensity_slider.editable, "Weather panel starts on clear with intensity locked")
	await _click(view.hud.weather_buttons[AtmosphereProfile.Weather.RAIN].get_global_rect().get_center())
	check(view.atmosphere.get_target_weather() == AtmosphereProfile.Weather.RAIN and is_equal_approx(view.atmosphere.get_target_amount(),view.hud.intensity_slider.value), "Weather panel sets rain in the atmosphere")
	view.hud.intensity_slider.value = 0.3
	check(is_equal_approx(view.atmosphere.get_target_amount(),0.3), "Intensity slider drives weather intensity")
	view.hud.time_slider.value = 20.0
	check(is_equal_approx(view.atmosphere.get_time_of_day(),20.0) and view.hud.slider_values[view.hud.time_slider].text == "20:00", "Time slider sets time of day")
	check(view.hud.clock_button.button_pressed and view.atmosphere.profile.day_length_minutes > 0.0, "The clock runs by default")
	await _click(view.hud.clock_button.get_global_rect().get_center())
	check(view.atmosphere.profile.day_length_minutes == 0.0, "Run clock toggle stops the day")
	view.hud.wind_from_slider.value = 90.0
	var wind_to: Vector2 = view.atmosphere.art.wind_direction
	check(wind_to.x < -0.99 and view.foliage.profile.wind_direction.is_equal_approx(wind_to), "Wind from east blows west in art and foliage")
	check((view.factory.material.get_shader_parameter("village_wind_direction") as Vector2).is_equal_approx(wind_to), "Wind direction reaches world materials live")
	view.hud.breeze_slider.value = 2.0
	check(is_equal_approx(view.atmosphere.wind_breeze(),2.0), "Breeze slider scales wind strength")
	view.hud.fade_slider.value = 2.0
	check(is_equal_approx(view.atmosphere.profile.weather_transition_seconds,2.0), "Fade slider sets weather transition time")
	var strikes: int = view.atmosphere.lightning.strike_count
	await _click(view.hud.weather_action_buttons.strike.get_global_rect().get_center())
	check(view.atmosphere.lightning.strike_count == strikes + 1, "Lightning button strikes")
	await _click(view.hud.weather_action_buttons.soak.get_global_rect().get_center())
	check(view.atmosphere.wetness > 0.99, "Soak button wets the ground")
	await process_frame
	view._sync_weather_hud()
	var stats: String = view.hud.weather_stats_text()
	check("E 90°" in stats and "Gust bend" in stats and "Near trees" in stats and "Wet ground" in stats, "Weather panel shows live stats")
	await RenderingServer.frame_post_draw
	var menu_rect: Rect2 = view.hud.weather_menu.get_global_rect()
	check(menu_rect.end.y < view.hud.bottom.get_global_rect().position.y or menu_rect.position.x > view.hud.bottom.get_global_rect().end.x, "Weather panel clears the bottom action bar")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/weather-menu.png")
	await _click(view.hud.cog_button.get_global_rect().get_center())
	check(view.hud.options_menu.visible and not view.hud.weather_menu.visible, "Options and weather panels are exclusive")
	await _key(KEY_ESCAPE)
	await _click(view.hud.sun_button.get_global_rect().get_center())
	await _key(KEY_ESCAPE)
	check(not view.hud.weather_menu.visible and not view.hud.sun_button.button_pressed, "Escape closes weather panel")
	await _key(KEY_F12)
	check(not view.hud.sun_button.visible and view.hud.map_button.position.x == view.hud.cog_button.position.x - 56, "F12 hides the developer tools again")
	view.atmosphere.set_weather(AtmosphereProfile.Weather.CLEAR,0.0,true)
	view.atmosphere.set_time_of_day(14.0)
	view.atmosphere.profile.day_length_minutes = 0.0
	view.atmosphere.reset_wind()
	view.atmosphere.profile.weather_transition_seconds = 8.0
	view.atmosphere.wetness = 0.0
	_check_weather_audio()
	await _check_treasury()
	await _check_factions()
	await _check_food_overlay()
	await _click(view.hud.build_button.get_global_rect().get_center())
	check(view.hud.build_menu.visible and view.hud.category_list.visible and not view.hud.building_list.visible, "Build button opens category list")
	check(view.hud.build_category_buttons.keys() == ["housing","logistics","resources","food"], "Build categories follow content order")
	check(view.hud.supply_bar.visible and view.hud.supply_items.logs.visible and view.hud.supply_labels.logs.text == str(view.sim.stock("logs")), "Build menu shows log supply")
	check(view.hud.supply_items.logs.get_child(0).texture != null, "Supply entry has a goods icon")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/build-menu.png")
	await _click(view.hud.build_category_buttons.food.get_global_rect().get_center())
	check(view.hud.building_list.visible and view.hud.build_title.text == "Food", "Category opens its building list")
	check(view.hud.build_buttons.farm.visible and view.hud.build_buttons.bakery.visible and not view.hud.build_buttons.road.visible, "Category lists only its own buildings")
	check(view.hud.build_details.farm.text == "4 Logs" and view.hud.build_details.bakery.text == "Needs Villagers", "Building rows show cost or unlock requirement")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/build-menu-food.png")
	await _click(view.hud.build_back_button.get_global_rect().get_center())
	check(view.hud.category_list.visible and not view.hud.build_back_button.visible, "Back returns to categories")
	await _click(view.hud.build_category_buttons.logistics.get_global_rect().get_center())
	await _click(view.hud.build_buttons.road.get_global_rect().get_center())
	check(view.tool.selected == "road" and not view.hud.build_menu.visible, "Choosing a road closes build menu")
	check(view.hud.placement_card.visible and "Free" in view.hud.placement_info.get_parsed_text(), "Placement card shows road requirements")
	await _click_cell(_cell(14,23))
	await _click_cell(_cell(16,23))
	check(view.sim.grid.roads.has(_cell(15,23)), "Two world clicks build a road segment")
	await _choose_build("well")
	var well_card: String = view.hud.placement_info.get_parsed_text()
	check(view.hud.placement_title.text == "Well" and "3 Logs" in well_card and "have" in well_card and "Workers" in well_card and "Water" in well_card, "Selected building lists cost, stock, workers and output")
	check("Treasury pays" in well_card, "Selected building shows what the treasury pays to build it")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/placement-card.png")
	await _check_construction()
	check(view.sim.grid.occupied.has(_cell(15,24)), "Toolbar + world click places well (%s)" % view.sim.last_error)
	var count: int = view.sim.buildings.size()
	await _click_cell(_cell(15,24))
	check(view.sim.buildings.size() == count and not view.sim.last_error.is_empty(), "Invalid placement gives feedback without mutation")
	await _key(KEY_ESCAPE)
	await _click_cell(_cell(15,24))
	check(view.selected_uid == view.sim.grid.occupied.get(_cell(15,24)) and view.hud.side.visible, "Click opens detailed building inspector")
	var production_info: String = view.hud.inspector.get_parsed_text()
	check("Makes" in production_info and "Has" in production_info and "Workers" in production_info and view.hud.inspection_progress.visible and view.hud.pay_row.visible, "Production inspector leads with output, stock, workers, cycle and pay")
	check(not "Footprint" in production_info and not "Facing" in production_info and not "Owner" in production_info, "Position and owner wait under Details")
	view.sim.step(1)
	view.hud.refresh(view.sim,view.selected_uid,view.tool.selected)
	var staffed_info: String = view.hud.details_text.get_parsed_text()
	check(not view.sim.buildings[view.selected_uid].staffed or ("Families" in staffed_info and "Cottage at" in staffed_info), "Details name the families its workers come from")
	check(not view.hud.details_text.visible, "Details start folded")
	await _click(view.hud.details_button.get_global_rect().get_center())
	check(view.hud.details_text.visible and view.hud.details_button.button_pressed, "The Details button unfolds them")
	await _click(view.hud.details_button.get_global_rect().get_center())
	check(not view.hud.details_text.visible, "and folds them again")
	await _click(view.hud.close_inspector.get_global_rect().get_center())
	check(not view.hud.side.visible and view.selected_uid == -1, "Inspection close button clears selection")
	await _click(view.hud.demolish_button.get_global_rect().get_center())
	await _click_cell(_cell(15,24))
	check(not view.sim.grid.occupied.has(_cell(15,24)), "Demolish tool removes placed building")
	await _click(view.hud.demolish_button.get_global_rect().get_center())
	check(view.tool.selected == "inspect", "Demolish button toggles back to inspection")
	await _click(view.hud.overlays_button.get_global_rect().get_center())
	check(view.hud.overlays_menu.visible and view.hud.overlays_menu.get_global_rect().end.y < view.hud.bottom.get_global_rect().position.y, "Overlays button opens its menu above the bottom bar")
	await _click(view.hud.deposits_button.get_global_rect().get_center())
	check(view.deposits_root.visible and view.hud.deposits_button.button_pressed, "Deposits toggle shows overlay")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/overlays-menu.png")
	await _click(view.hud.deposits_button.get_global_rect().get_center())
	check(not view.deposits_root.visible, "Deposits toggle hides overlay")
	await _key(KEY_ESCAPE)
	check(not view.hud.overlays_menu.visible, "Escape closes the overlays menu")
	await _click(view.hud.build_button.get_global_rect().get_center())
	await _key(KEY_ESCAPE)
	check(not view.hud.build_menu.visible, "Escape closes build menu")
	var before: int = view.camera.quarter_turn
	await _key(KEY_E)
	check(view.camera.quarter_turn == (before+1)%4, "E rotates camera exactly ninety degrees")
	await _key(KEY_Q)
	await _key(KEY_SPACE)
	check(view.speed == 1, "Space resumes simulation")
	await _key(KEY_SPACE)
	check(view.speed == 0, "Space pauses simulation")
	await _key(KEY_F3)
	check(view.deposits_root.visible and view.hud.deposits_button.button_pressed, "F3 keeps deposits button state in sync")
	await _key(KEY_F3)
	view._restart()
	view._set_speed(0)
	view.sim.construction_sites = false
	view.sim.step(300)
	view.hud.refresh(view.sim,view.selected_uid,view.tool.selected)
	await process_frame
	check(not view.hud.build_buttons.mill.disabled and not view.hud.build_buttons.bakery.disabled, "House upgrade unlocks mill and bakery in menu")
	await _click_cell(_cell(21,21))
	var house_info: String = view.hud.inspector.get_parsed_text()
	var house_details: String = view.hud.details_text.get_parsed_text()
	check("tier 2" in house_info and "Needs" in house_info and "Family" in house_info and "adult" in house_info and ("Jobs" in house_info or "no wages" in house_info), "House inspector shows current tier, needs, its family and their jobs")
	check("Happiness" in house_info and "Savings" in house_info and not view.hud.workers_button.visible and not view.hud.pay_row.visible, "House inspector shows happiness and savings, with no workers switch or pay")
	check("Pantry" in house_details and "wage" in house_details and "Bread" in house_details and "Settled happiness" in house_details, "House details hold the pantry, wages, prices and settled happiness")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/inspection-house.png")
	await _key(KEY_ESCAPE)
	var before_chain: int = view.sim.buildings.size()
	await _choose_build("mill")
	await _click_cell(_cell(16,18))
	await _choose_build("bakery")
	await _click_cell(_cell(23,18))
	check(view.sim.buildings.size() == before_chain + 2, "Build menu places both chain buildings")
	await _key(KEY_ESCAPE)
	view.sim.step(500)
	view._sync_view()
	check(int(view.sim.produced.get("bread",0)) > 0, "Rendered scene produces bread")
	view.hud.refresh(view.sim,view.selected_uid,view.tool.selected)
	await process_frame
	await RenderingServer.frame_post_draw
	var final_image := root.get_texture().get_image()
	check(final_image.save_png("res://artifacts/view-tested.png") == OK, "Capture rendered input-tested scene")
	var colors: Dictionary = {}
	for y in range(112,570,2):
		for x in range(24,960,2):
			colors[final_image.get_pixel(x,y).to_rgba32()] = true
	check(colors.size() > 32, "Rendered world retains more than the old 32-colour palette (actual %d)" % colors.size())
	await _click_cell(_cell(23,18))
	check(view.hud.inspector_title.text == "Bakery" and view.hud.inspection_progress.visible, "Bakery inspection includes cycle progress bar")
	var bakery_info: String = view.hud.details_text.get_parsed_text()
	check("Sells" in bakery_info and "Purse" in bakery_info, "Workshop details show its price and purse")
	var bakery = view.sim.buildings[view.selected_uid]
	await _click(view.hud.pay_buttons[2].get_global_rect().get_center())
	check(bakery.pay == 2 and view.hud.pay_buttons[2].button_pressed and "from the treasury" in view.hud.pay_hint.text, "Pay buttons raise a workplace's pay and say who pays (%s)" % view.hud.pay_hint.text)
	await _click(view.hud.pay_buttons[1].get_global_rect().get_center())
	check(bakery.pay == 1, "and set it back to normal")
	await _click(view.hud.workers_button.get_global_rect().get_center())
	check(not bakery.workers_enabled and view.hud.workers_button.text == "Resume workers", "Inspector button stops a building's workers")
	await _click(view.hud.workers_button.get_global_rect().get_center())
	check(bakery.workers_enabled, "Inspector button resumes a building's workers")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/inspection-bakery.png")
	await _click_cell(_cell(17,21))
	var storage_info: String = view.hud.inspector.get_parsed_text()
	check("Stored" in storage_info and "carriers" in storage_info and "Holds" in view.hud.details_text.get_parsed_text(), "Storehouse inspector shows carriers and fill, with the goods in Details")
	check("storekeeper" in storage_info.to_lower() and "needs a middle-class family" in storage_info, "Storehouse inspector says its storekeeper's job needs a middle-class family")
	var store = view.sim.buildings[view.selected_uid]
	await _click(view.hud.pay_buttons[2].get_global_rect().get_center())
	check(store.pay == 2 and Economy.markup(store) == 20 and "Markup 20%" in view.hud.pay_hint.text, "A storehouse's pay is its markup")
	await _click(view.hud.pay_buttons[1].get_global_rect().get_center())
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/inspection-storehouse.png")
	await _key(KEY_ESCAPE)
	view.pixel_viewport.get_texture().get_image().save_png("res://artifacts/world-render.png")
	await _check_building_rotation()
	print("HEARTHLANDS VIEW: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

## docs/CONSTRUCTION.md: a click lays out a site with a thunk and dust; its
## inspector shows the materials and Cancel; carriers fill its pile, the
## building rises and opens with a pop and a chime.
func _check_construction() -> void:
	view.sim.construction_sites = true
	# Join the new road to the village so carriers can reach the site.
	check(view.sim.place_road([_cell(16,22),_cell(16,21)]), "A road joins the new strip to the main road (%s)" % view.sim.last_error)
	var logs: int = view.sim.stock("logs")
	await _click_cell(_cell(15,24))
	var uid: int = view.sim.grid.occupied.get(_cell(15,24),-1)
	check(view.sim.sites.has(uid) and not view.sim.buildings.has(uid), "A click lays out a construction site (%s)" % view.sim.last_error)
	check(view.sim.available("logs") == logs - 3 and logs >= 3, "The site's logs are promised to it (%d logs in stock, %d free, reserve %d, error %s)" % [logs, view.sim.available("logs"), view.sim.reserve.count("logs"), view.sim.last_error])
	check(view.construction.nodes.has(uid) and view.construction.nodes[uid].get_node("Blueprint").visible, "The site shows its plot and a blueprint of the building")
	check(view.construction.get_children().any(func(node): return node is CPUParticles3D), "Placing raises a puff of dust")
	check(view.sounds.last_played.has("place"), "Placing plays a thunk")
	await _key(KEY_ESCAPE)
	await _click_cell(_cell(15,24))
	var site_info: String = view.hud.inspector.get_parsed_text()
	check(view.hud.side.visible and view.hud.inspector_title.text == "Well" and "Waiting for materials" in site_info and "Logs" in site_info and view.hud.cancel_site_button.visible and not view.hud.pay_row.visible, "The site inspector shows what it waits for, its materials and Cancel (%s)" % site_info.replace("\n"," | "))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/construction-site.png")
	var rising := false
	for index in 600:
		view.sim.step(1)
		view._sync_view()
		var site = view.sim.sites.get(uid)
		if site == null:
			break
		if site.status == "building" and site.progress > view.sim.build_ticks(site.definition) / 2 and not rising:
			rising = true
			view.hud.refresh(view.sim,view.selected_uid,view.tool.selected)
			await process_frame
			check("Building" in view.hud.inspector.get_parsed_text() and view.construction.nodes[uid].get_node("Rising").visible, "Once supplied the site builds, and the building rises")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/construction-rising.png")
	var stuck = view.sim.sites.get(uid)
	check(rising and view.sim.buildings.has(uid), "The well is finished%s" % ("" if stuck == null else " (stuck %s with %s, %d logs available, tick %d)" % [stuck.status, str(stuck.materials.items), view.sim.available("logs"), view.sim.tick]))
	check(not view.construction.nodes.has(uid) and view.building_nodes.has(uid), "The finished building replaces its site")
	check(view.sounds.last_played.has("complete") and view.sounds.last_played.has("deliver"), "Deliveries knock and the finish chimes")
	view.hud.refresh(view.sim,view.selected_uid,view.tool.selected)
	await process_frame
	check(view.hud.inspector_title.text == "Well" and not view.hud.cancel_site_button.visible and view.hud.pay_row.visible, "The inspector turns into the well's")
	await _key(KEY_ESCAPE)
	await _choose_build("well")
	view.sim.construction_sites = false

## VILLAGERS.md 5.1-5.2: the gold counter opens the Treasury panel, whose
## buttons set tax and move gold between free and reserved through real input.
func _check_treasury() -> void:
	var sim = view.sim
	var counter: Rect2 = view.hud.treasury_button.get_global_rect()
	check(view.hud.treasury_button.visible and view.hud.treasury_button.text == Economy.format(sim.treasury), "Gold counter shows the treasury")
	check(counter.position.x < 40 and counter.end.x < view.hud.map_button.get_global_rect().position.x and not view.hud.blocks_mouse(Vector2(640,40)), "Gold counter sits top left and leaves the top centre clear")
	await _click(counter.get_center())
	await process_frame
	check(view.hud.treasury_menu.visible and view.hud.treasury_button.button_pressed, "Gold counter opens the Treasury panel")
	check(not view.hud.reserves_box.visible, "Reserves start folded away")
	check(view.hud.blocks_mouse(view.hud.treasury_menu.get_global_rect().get_center()), "Treasury panel blocks clicks on the world behind it")
	var tax: int = sim.tax_percent
	await _click(view.hud.tax_buttons[Economy.TAX_STEP].get_global_rect().get_center())
	check(sim.tax_percent == tax + Economy.TAX_STEP and view.hud.tax_value.text == "%d%%" % sim.tax_percent, "Treasury panel raises tax through real input")
	for step in (tax + Economy.TAX_STEP) / Economy.TAX_STEP:
		await _click(view.hud.tax_buttons[-Economy.TAX_STEP].get_global_rect().get_center())
	check(sim.tax_percent == 0 and view.hud.tax_buttons[-Economy.TAX_STEP].disabled, "Treasury panel lowers tax to zero, then stops")
	sim.set_tax_percent(tax)
	await _click(view.hud.reserves_button.get_global_rect().get_center())
	await process_frame
	check(view.hud.reserves_box.visible and view.hud.keep_reserve_button.button_pressed, "Reserves unfold, with services kept reserved by default")
	sim.set_keep_service_reserve(false)
	var free: int = Economy.free_gold(sim)
	await _click(view.hud.reserve_buttons.public[Economy.SILVER_PER_GOLD].get_global_rect().get_center())
	check(sim.public_reserve == mini(Economy.SILVER_PER_GOLD,free) and view.hud.treasury_values.public.text == Economy.format(sim.public_reserve), "Treasury panel sets gold aside for public pay")
	await _click(view.hud.reserve_buttons.capital[Economy.SILVER_PER_GOLD].get_global_rect().get_center())
	check(sim.capital_reserve > 0 and Economy.free_gold(sim) == free - sim.public_reserve - sim.capital_reserve and view.hud.treasury_values.free.text == Economy.format(Economy.free_gold(sim)), "Treasury panel sets gold aside for construction")
	var panel_text: String = view.hud.treasury_ledger.get_parsed_text()
	check("Services" in panel_text and (sim.public_frustration > 0) == ("frustration" in panel_text), "Treasury panel reports services, and frustration only when there is some")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/treasury-panel.png")
	await _click(view.hud.reserve_buttons.public[-Economy.SILVER_PER_GOLD].get_global_rect().get_center())
	await _click(view.hud.reserve_buttons.capital[-Economy.SILVER_PER_GOLD].get_global_rect().get_center())
	check(sim.public_reserve == 0 and sim.capital_reserve == 0 and Economy.free_gold(sim) == free, "Treasury panel returns reserved gold to free gold")
	sim.set_keep_service_reserve(true)
	await _click(view.hud.reserves_button.get_global_rect().get_center())
	await _click(view.hud.cog_button.get_global_rect().get_center())
	check(view.hud.options_menu.visible and not view.hud.treasury_menu.visible and not view.hud.treasury_button.button_pressed, "Options and treasury panels are exclusive")
	await _key(KEY_ESCAPE)
	await _click(counter.get_center())
	await _key(KEY_ESCAPE)
	check(not view.hud.treasury_menu.visible and not view.hud.treasury_button.button_pressed, "Escape closes the Treasury panel")

## PLAN-factions item 7: faction chips, the Factions panel's offers and
## pledges, a padlocked lever, the inspector's sale button and the class
## overlay, all through real input.
func _check_factions() -> void:
	var sim = view.sim
	var hud = view.hud
	hud.refresh(sim,view.selected_uid,view.tool.selected)
	await process_frame
	await process_frame
	check(hud.factions_button.visible and "Aristocrats" in hud.factions_button.tooltip_text and not "Trade unions" in hud.factions_button.tooltip_text, "The Factions button lists the factions present at founding (%s)" % hud.factions_button.tooltip_text.replace("\n"," | "))
	check(hud.factions_button.position.x < hud.map_button.position.x and hud.factions_button.position.y == hud.map_button.position.y and not hud.blocks_mouse(Vector2(640,40)), "The Factions button sits with the top-right buttons")
	var house = null
	var farm = null
	for building in sim.buildings.values():
		if building.definition.id == "house" and house == null: house = building
		if building.definition.id == "farm" and farm == null: farm = building
	house.tier = 2
	sim.step(1)
	hud.refresh(sim,view.selected_uid,view.tool.selected)
	await process_frame
	await process_frame
	check("Trade unions" in hud.factions_button.tooltip_text and "Populists" in hud.factions_button.tooltip_text, "Unions and populists join the Factions button when they arrive")
	for id in ["gentry","union","middle"]:
		sim.factions.coffers[id] = int(sim.factions.coffers[id]) + 1000
		sim.outside_money += 1000
	await _click(hud.factions_button.get_global_rect().get_center())
	check(hud.factions_menu.visible and hud.blocks_mouse(hud.factions_menu.get_global_rect().get_center()), "The Factions button opens the panel, which blocks the world behind it")
	check(hud.power_segments.has("crown") and hud.power_segments.has("unaligned") and "Crown" in hud.power_segments.crown.tooltip_text, "The panel shows the power bar, named in its tooltips")
	var rows: String = hud.faction_text.get_parsed_text()
	check("Aristocrats" in rows and "favour" in rows and not "coffers" in rows and rows.count("\n") == sim.factions.coffers.size() - 1, "The panel lists each faction on one row")
	hud.faction_text.meta_clicked.emit("gentry")
	check("coffers" in hud.faction_text.get_parsed_text(), "A faction's row opens to show what moves its favour")
	hud.faction_text.meta_clicked.emit("gentry")
	var bid := _offer(sim,"gentry","bid")
	hud.refresh(sim,view.selected_uid,view.tool.selected)
	await process_frame
	await process_frame
	var alert = hud.offer_alerts_by_id.get("gentry")
	check(not bid.is_empty() and alert != null and alert.visible and alert.get_global_rect().position.x < 40 and not hud.offer_card.visible, "An open offer shows as an alert on the left edge")
	# Two thirds of its life left, without moving the village on.
	sim.factions.offers.gentry.expires = sim.tick + 2 * sim.PAYDAY_TICKS
	hud.refresh(sim,view.selected_uid,view.tool.selected)
	check(alert != null and is_equal_approx(alert.left, 2.0 / 3.0), "The alert's clock counts down to the offer lapsing (%.2f left)" % (alert.left if alert != null else -1.0))
	if alert != null:
		await _click(alert.get_global_rect().get_center())
		await process_frame
	check(hud.offer_card.visible and hud.offer_buttons.has("gentry") and "Aristocrats" in hud.offer_title.text and "Lapses in" in hud.offer_text.get_parsed_text(), "Clicking the alert opens its card")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/offer-alert.png")
	if hud.offer_buttons.has("gentry"):
		await _click(hud.offer_buttons.gentry.accept.get_global_rect().get_center())
		check(sim.buildings[int(bid.uid)].owner == "gentry" and sim.factions.offers.gentry.is_empty(), "Accept sells the building through real input")
	hud.refresh(sim,view.selected_uid,view.tool.selected)
	check(not hud.offer_alerts_by_id.has("gentry") and not hud.offer_card.visible, "An answered offer's alert and card go")
	var pledge := _offer(sim,"middle","pledge")
	var favour: int = sim.factions.favour.middle
	hud.refresh(sim,view.selected_uid,view.tool.selected)
	await process_frame
	await process_frame
	if hud.offer_alerts_by_id.has("middle"):
		await _click(hud.offer_alerts_by_id.middle.get_global_rect().get_center())
	if not pledge.is_empty() and hud.offer_buttons.has("middle"):
		await _click(hud.offer_buttons.middle.decline.get_global_rect().get_center())
	check(not pledge.is_empty() and sim.factions.offers.middle.is_empty() and sim.factions.favour.middle == favour - 5, "Decline closes an offer through real input")
	sim.set_tax_percent(15)
	var cap := _offer(sim,"union","pledge","tax_cap")
	hud.refresh(sim,view.selected_uid,view.tool.selected)
	await process_frame
	await process_frame
	if hud.offer_alerts_by_id.has("union"):
		await _click(hud.offer_alerts_by_id.union.get_global_rect().get_center())
	if not cap.is_empty() and hud.offer_buttons.has("union"):
		await _click(hud.offer_buttons.union.accept.get_global_rect().get_center())
	hud.refresh(sim,view.selected_uid,view.tool.selected)
	await process_frame
	await process_frame
	check(sim.tax_percent == 10 and sim.factions.pledges.union.size() == 1 and hud.pledge_buttons.has("union:tax_cap"), "Accepting a tax cap pledges it and lists it with a Break button")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/factions-panel.png")
	await _click(hud.treasury_button.get_global_rect().get_center())
	await process_frame
	check(hud.treasury_menu.visible and not hud.factions_menu.visible, "Treasury and Factions panels are exclusive")
	check(hud.tax_lock.get_parent().visible and "Trade unions" in hud.tax_lock.text and hud.tax_buttons[Economy.TAX_STEP].disabled, "A pledged lever shows a padlock and the faction's name")
	await _click(hud.tax_buttons[Economy.TAX_STEP].get_global_rect().get_center())
	check(sim.tax_percent == 10, "A padlocked lever refuses changes")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/treasury-pledged.png")
	await _key(KEY_ESCAPE)
	await _click(hud.factions_button.get_global_rect().get_center())
	hud.refresh(sim,view.selected_uid,view.tool.selected)
	await process_frame
	await process_frame
	if hud.pledge_buttons.has("union:tax_cap"):
		await _click(hud.pledge_buttons["union:tax_cap"].get_global_rect().get_center())
	check(sim.factions.pledges.union.is_empty() and sim.factions.blocked_until.union > sim.tick and sim.set_tax_percent(20), "Break pledge frees the lever through real input")
	sim.set_tax_percent(15)
	await _key(KEY_ESCAPE)
	check(not hud.factions_menu.visible, "Escape closes the Factions panel")
	await _click_cell(farm.cell)
	hud.refresh(sim,view.selected_uid,view.tool.selected)
	check(view.selected_uid == farm.uid and hud.sale_button.visible and "The Crown" in hud.details_text.get_parsed_text(), "A Crown field shows its owner and Offer for sale")
	await _click(hud.sale_button.get_global_rect().get_center())
	await process_frame
	check(hud.sale_list.visible and hud.sale_buttons.has("gentry"), "Offer for sale lists the buyers' bids")
	if hud.sale_buttons.has("gentry"):
		await _click(hud.sale_buttons.gentry.get_global_rect().get_center())
	hud.refresh(sim,view.selected_uid,view.tool.selected)
	check(farm.owner == "gentry" and not hud.sale_button.visible and "Aristocrats" in hud.details_text.get_parsed_text(), "The sale button sells through real input")
	await _click_cell(house.cell)
	hud.refresh(sim,view.selected_uid,view.tool.selected)
	check(view.selected_uid == house.uid and "Working class" in hud.details_text.get_parsed_text() and "rent" in hud.details_text.get_parsed_text(), "A Villager house shows its class, alignment and landlord")
	await _key(KEY_ESCAPE)
	# A union hall and a union house, so the overlay has reach and colour to show.
	var unlocked: int = sim.unlocked_tier
	sim.unlocked_tier = maxi(unlocked,2)
	var hall = null
	for cell in [_cell(18,23),_cell(21,23),_cell(21,16),_cell(18,16)]:
		if sim.placement_error("union_hall",cell).is_empty() and sim.place("union_hall",cell):
			hall = sim.buildings[sim.next_uid - 1]
			break
	# The build menu checks after this expect Villager buildings still locked.
	sim.unlocked_tier = unlocked
	house.aligned = "union"
	await _click(hud.overlays_button.get_global_rect().get_center())
	await _click(hud.class_overlay_button.get_global_rect().get_center())
	check(hall != null and view.class_root.get_child_count() > 4, "The overlay draws houses and the hall's reach (%d markers, hall %s)" % [view.class_root.get_child_count(), str(hall != null)])
	check("Unaligned" in hud.class_legend_text.get_parsed_text() and "Trade unions" in hud.class_legend_text.get_parsed_text(), "The class overlay key names its colours")
	check(view.class_root.visible and view.class_root.get_child_count() > 0 and hud.class_legend.visible and hud.class_overlay_button.button_pressed, "The overlays toggle shows the class overlay and its key")
	await _key(KEY_ESCAPE)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/class-overlay.png")
	await _key(KEY_F5)
	check(not view.class_root.visible and not hud.class_legend.visible and not hud.class_overlay_button.button_pressed, "F5 hides the class overlay")
	# The operations overlay tints each workplace by how it is running.
	await _click(hud.overlays_button.get_global_rect().get_center())
	await _click(hud.operations_overlay_button.get_global_rect().get_center())
	var workplaces := 0
	for building in sim.buildings.values():
		if not sim.operation(building).is_empty(): workplaces += 1
	check(view.operations_root.visible and hud.operations_legend.visible and hud.operations_overlay_button.button_pressed, "The overlays menu shows the operations overlay and its key")
	check(workplaces > 0 and view.operations_root.get_child_count() == workplaces * 2, "Every workplace gets a plate and a marker (%d for %d workplaces)" % [view.operations_root.get_child_count(), workplaces])
	await _key(KEY_ESCAPE)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/operations-overlay.png")
	await _key(KEY_F6)
	check(not view.operations_root.visible and not hud.operations_legend.visible, "F6 hides the operations overlay")

## Opens one of the faction's candidate offers by type (and pledge), or {}.
func _offer(sim, id: String, type: String, pledge: String = "") -> Dictionary:
	for offer in sim.factions.candidates(sim,id):
		if offer.type == type and (pledge.is_empty() or offer.get("pledge","") == pledge):
			offer["expires"] = sim.tick + 600
			sim.factions.offers[id] = offer
			return offer
	return {}

func _click_cell(cell: Vector2i) -> void:
	var local: Vector2 = view.camera.unproject_position(Vector3(cell.x+0.5,0,cell.y+0.5))
	await _click(view.display.position+local)

func _choose_build(id: String) -> void:
	await _click(view.hud.build_button.get_global_rect().get_center())
	await _click(view.hud.build_category_buttons[view.sim.db.buildings[id].category].get_global_rect().get_center())
	await _click(view.hud.build_buttons[id].get_global_rect().get_center())

func _move_cell(cell: Vector2i) -> void:
	var local: Vector2 = view.camera.unproject_position(Vector3(cell.x+0.5,view.relief.cell_height(cell),cell.y+0.5))
	var move := InputEventMouseMotion.new()
	move.position = view.display.position + local
	root.push_input(move)
	await process_frame
	await process_frame

func _check_building_rotation() -> void:
	view._restart()
	view.sim.construction_sites = false
	view._set_speed(0)
	await _choose_build("storehouse")
	# East of the woodcutter, on the main road: free in both orientations.
	var anchor := _cell(26,21)
	check(view.sim.placement_error("storehouse",anchor,0).is_empty() and view.sim.placement_error("storehouse",anchor,1).is_empty(), "Rotation input fixture fits in both orientations")
	await _move_cell(anchor)
	check(view.ghost_root.has_node("Preview") and view.hud.rotate_button.visible, "Building placement shows model preview and Rotate button")
	var original_camera: int = view.camera.quarter_turn
	await _key(KEY_R)
	check(view.tool.rotation_quarters == 1 and view.camera.quarter_turn == original_camera, "R rotates the building without rotating the camera")
	var card: String = view.hud.placement_info.get_parsed_text()
	check("2 × 3" in card and "90°" in card, "Placement card reflects rotated footprint and facing")
	await _move_cell(anchor)
	var preview: Node3D = view.ghost_root.get_node("Preview")
	check(is_equal_approx(preview.rotation.y,PI/2.0) and preview.position == Vector3(anchor.x+1,0,anchor.y+1.5), "Preview rotates around the swapped footprint centre")
	var preview_position := preview.position
	var preview_rotation := preview.rotation.y
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/rotation-preview.png")
	await _click_cell(anchor)
	if not view.sim.grid.occupied.has(anchor):
		check(false, "World click places the rotated storehouse: %s" % view.sim.last_error)
		return
	var placed = view.sim.buildings[view.sim.grid.occupied[anchor]]
	var model: Node3D = view.building_nodes[placed.uid]
	check(placed.rotation_quarters == 1 and model.position == preview_position and is_equal_approx(model.rotation.y,preview_rotation), "World click preserves preview orientation and centre")
	check(view.sim.grid.occupied.get(anchor+Vector2i(1,2)) == placed.uid and not view.sim.grid.occupied.has(anchor+Vector2i(2,0)), "Placed rectangular building occupies swapped footprint")
	# Tier upgrades rebuild a model without losing its chosen facing.
	await _choose_build("house")
	check(view.tool.rotation_quarters == 0, "Changing building resets placement facing")
	await _click(view.hud.rotate_button.get_global_rect().get_center())
	check(view.tool.rotation_quarters == 1, "Placement card Rotate button turns the building")
	for turn in 3: await _key(KEY_R)
	check(view.tool.rotation_quarters == 0, "Four rotations return to the original facing")
	await _key(KEY_R)
	await _click_cell(_cell(15,24))
	var house = view.sim.buildings[view.sim.grid.occupied[_cell(15,24)]]
	house.tier = 2
	view._sync_view()
	check(is_equal_approx(view.building_nodes[house.uid].rotation.y,PI/2.0), "Tier upgrade retains the placed orientation")
	await _key(KEY_ESCAPE)
	await _key(KEY_R)
	check(view.tool.selected == "inspect" and view.tool.rotation_quarters == 0, "Cancel clears orientation and R does nothing in inspection")
	await _choose_build("road")
	await _key(KEY_R)
	check(not view.hud.rotate_button.visible and view.tool.rotation_quarters == 0, "Road strokes have no building rotation")
	await _key(KEY_ESCAPE)
	await _click_cell(anchor+Vector2i(1,2))
	check("2 × 3" in view.hud.details_text.get_parsed_text() and "90°" in view.hud.details_text.get_parsed_text(), "Inspector details show the placed footprint and facing")
	await _key(KEY_ESCAPE)
	await _click(view.hud.demolish_button.get_global_rect().get_center())
	await _click_cell(anchor+Vector2i(1,2))
	check(not view.sim.buildings.has(placed.uid) and not view.sim.grid.occupied.has(anchor), "Demolition from rotated corner removes the entire building")
	await _key(KEY_ESCAPE)

func _check_weather_audio() -> void:
	var atmosphere = view.atmosphere
	atmosphere._tick(0.0)
	var audio: WeatherAudio = atmosphere.audio
	var frame: AtmosphereModel.Frame = atmosphere.frame
	# A long step snaps every bed to its target.
	audio.advance(30.0,frame,1.0,0.0,0.0)
	check(is_zero_approx(audio.wind_gain) and is_zero_approx(audio.still_gain), "Clear calm weather has no wind or still-air bed")
	audio.advance(30.0,frame,1.0,1.0,0.0)
	check(audio.rustle_gain > 0.3 and audio.wind_gain == 0.0, "Trees rustle in the authored breeze without open-air wind")
	audio.advance(30.0,frame,2.0,0.0,0.0)
	check(is_equal_approx(audio.wind_gain,1.0), "Storm gusts play the full wind bed")
	var zoom: float = view.camera.zoom_size
	var forest := Vector3(3.5,0,3.5)
	var meadow := Vector3(_cell(18,18).x+0.5,0,_cell(18,18).y+0.5)
	var shore := Vector3(int(view.sim.grid.width*0.8)-1.5,0,18.5)
	view.camera.zoom_size = 16.0
	var forest_near: float = atmosphere._foliage_density(null,forest)
	check(forest_near > 0.6, "Zoomed into forest, foliage density is high")
	check(atmosphere._foliage_density(null,meadow) < 0.15, "Open meadow has almost no foliage rustle")
	check(atmosphere._water_proximity(shore) > 0.5 and atmosphere._water_proximity(meadow) == 0.0, "Water beds play by the shore, not inland")
	view.camera.zoom_size = 48.0
	check(atmosphere._foliage_density(null,forest) < forest_near, "Zooming out quietens nearby foliage")
	view.camera.zoom_size = zoom

func _collect_button_text(node: Node, labels: Array[String]) -> void:
	if node is Button: labels.append((node as Button).text)
	for child in node.get_children(): _collect_button_text(child, labels)

func _click(point: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = point
	root.push_input(move)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await process_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await process_frame

func _cell(x: int,y: int) -> Vector2i:
	return Vector2i(x,y)+preload("res://sim/scenario.gd").offset(view.sim)
## Natural food on the land (docs/WILDLIFE.md): wild berry bushes and game are
## drawn where the sim has them, and the food overlay (F7) marks fertile soil,
## berries, the fishing shore and each range's game.
func _check_food_overlay() -> void:
	var hud = view.hud
	var sim = view.sim
	view._sync_view()
	check(sim.forage.bushes.size() > 100 and view.forage_layer.bushes.size() == sim.forage.bushes.size(), "Every wild berry bush is drawn (%d)" % sim.forage.bushes.size())
	check(view.wildlife_layer.animals.size() == sim.wildlife.total("deer") + sim.wildlife.total("boar"), "Every deer and boar is drawn (%d)" % view.wildlife_layer.animals.size())
	var cell: Vector2i = sim.forage.bushes.keys()[0]
	var fruit: int = sim.forage.bushes[cell]
	sim.forage.bushes[cell] = 0
	view._sync_view()
	var berries := view.forage_layer.bushes[cell].find_child("Berries", true, false) as Node3D
	check(berries != null and not berries.visible, "A picked bush shows no berries")
	sim.forage.bushes[cell] = fruit
	view._sync_view()
	check(berries != null and berries.visible, "Ripe berries show again")
	await _key(KEY_F7)
	check(view.food_overlay.visible and hud.food_legend.visible and hud.food_overlay_button.button_pressed, "F7 shows the food overlay and its key")
	check(view.food_overlay.land.mesh != null and view.food_overlay.berries.mesh != null and view.food_overlay.game.get_child_count() > 10, "The overlay marks fertile soil, berries and game (%d ranges)" % view.food_overlay.game.get_child_count())
	var legend: String = hud.food_legend.get_child(0).get_parsed_text()
	check("Fertile soil" in legend and "Wild berries" in legend and "Fishing shore" in legend, "The food overlay key names its marks")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/food-overlay-hud.png")
	await _key(KEY_F7)
	check(not view.food_overlay.visible and not hud.food_legend.visible and not hud.food_overlay_button.button_pressed, "F7 hides the food overlay")
	# The food button sits on the top row and opens its breakdown and the overlay.
	var food_rect: Rect2 = hud.food_button.get_global_rect()
	check(hud.food_button.visible and hud.stock_bar.get_global_rect().encloses(food_rect) and hud.food_button.text.begins_with(str(hud.food_total)), "The food chip leads the top bar with food stored and its balance (%s)" % hud.food_button.text)
	await _click(food_rect.get_center())
	hud.refresh(sim,-1,"inspect")
	var breakdown: String = hud.food_text.get_parsed_text()
	check(hud.food_menu.visible and view.food_overlay.visible and hud.food_overlay_button.button_pressed, "The food button opens its breakdown and the food overlay")
	check("Stored" in breakdown and ("Made by" in breakdown or "Measuring" in hud.food_verdict.get_parsed_text()) and ("needed" in hud.food_verdict.get_parsed_text() or "Measuring" in hud.food_verdict.get_parsed_text()), "The breakdown shows the verdict, stores and each food with its makers")
	check(hud.blocks_mouse(hud.food_menu.get_global_rect().get_center()), "The food breakdown blocks clicks behind it")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/food-balance-view.png")
	await _key(KEY_ESCAPE)
	check(not hud.food_menu.visible and not hud.food_button.button_pressed, "Escape closes the food breakdown")
	await _key(KEY_F7)
	check(not view.food_overlay.visible and not hud.food_overlay_button.button_pressed, "F7 still hides the overlay afterwards")
	# Placing a field shows how fertile its ground is.
	await _choose_build("farm")
	await _move_cell(_cell(12,15))
	var soil := view.ghost_root.find_child("Soil", true, false) as Label3D
	check(soil != null and "% speed" in soil.text, "A field's ghost shows its soil and speed (%s)" % (soil.text if soil != null else "none"))
	await _key(KEY_ESCAPE)
