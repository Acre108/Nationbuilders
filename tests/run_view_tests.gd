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
	check(view.sim.grid.width == 100 and view.sim.grid.height == 100, "Playable default map is 100 by 100")
	check(view.camera.bounds.end == Vector2(95,95), "Camera bounds cover the expanded default map")
	var starting_focus: Vector3 = view.camera.focus
	view.camera.pan(Vector2(1,-1).normalized(),10.0)
	check(view.camera.focus.x > 40 or view.camera.focus.z > 40, "Camera can pan past the old map boundary")
	view.camera.focus = starting_focus
	view.camera.refresh()
	check(view.sim.buildings.size() == 5, "Playable starter has five buildings")
	check(view.hud.bottom.get_child(0).get_child_count() == 3, "Play screen has exactly three bottom actions")
	check(not view.hud.side.visible and not view.hud.build_menu.visible and not view.hud.toast.visible, "Start has no persistent text panels")
	check(not view.hud.blocks_mouse(Vector2(640,40)), "Top of play screen is unobstructed")
	var bar: Rect2 = view.hud.stock_bar.get_global_rect()
	check(view.hud.stock_bar.visible and view.hud.stock_label.text.begins_with("Storehouse ") and " / 180" in view.hud.stock_label.text and "Bread" in view.hud.stock_label.text, "Stock bar shows storehouse fill and key stocks (%s)" % view.hud.stock_label.text)
	check(bar.position.x >= view.hud.treasury_button.get_global_rect().end.x and bar.end.x < view.hud.map_button.get_global_rect().position.x, "Stock bar sits between the gold counter and the top-right buttons")
	await _click(view.hud.cog_button.get_global_rect().get_center())
	check(view.hud.options_menu.visible and view.hud.cog_button.button_pressed, "Top-right cog opens options")
	await _click_cell(_cell(21,21))
	check(view.selected_uid == -1, "Options block clicks on buildings behind menu")
	await _click(view.hud.speed_buttons[3].get_global_rect().get_center())
	check(view.speed == 3 and view.hud.speed_buttons[3].button_pressed, "Options set triple simulation speed")
	await _click(view.hud.speed_buttons[1].get_global_rect().get_center())
	check(view.speed == 1 and not view.hud.speed_buttons[3].button_pressed, "Options switch speed selection exclusively")
	await _click(view.hud.speed_buttons[0].get_global_rect().get_center())
	check(view.speed == 0, "Options pause simulation")
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
	check(view.sim.tick <= 1 and view.sim.buildings.size() == 5 and not view.hud.options_menu.visible, "Options restart resets village and closes menu")
	view._set_speed(0)
	check(view.hud.sun_button.position.x < view.hud.cog_button.position.x, "Sun button sits left of the cog")
	await _click(view.hud.sun_button.get_global_rect().get_center())
	check(view.hud.weather_menu.visible and view.hud.sun_button.button_pressed, "Sun button opens weather panel")
	check(view.hud.weather_buttons[AtmosphereProfile.Weather.CLEAR].button_pressed and not view.hud.intensity_slider.editable, "Weather panel starts on clear with intensity locked")
	await _click(view.hud.weather_buttons[AtmosphereProfile.Weather.RAIN].get_global_rect().get_center())
	check(view.atmosphere.get_target_weather() == AtmosphereProfile.Weather.RAIN and is_equal_approx(view.atmosphere.get_target_amount(),view.hud.intensity_slider.value), "Weather panel sets rain in the atmosphere")
	view.hud.intensity_slider.value = 0.3
	check(is_equal_approx(view.atmosphere.get_target_amount(),0.3), "Intensity slider drives weather intensity")
	view.hud.time_slider.value = 20.0
	check(is_equal_approx(view.atmosphere.get_time_of_day(),20.0) and view.hud.slider_values[view.hud.time_slider].text == "20:00", "Time slider sets time of day")
	await _click(view.hud.clock_button.get_global_rect().get_center())
	check(view.atmosphere.profile.day_length_minutes > 0.0, "Run clock starts the day passing")
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
	view.atmosphere.set_weather(AtmosphereProfile.Weather.CLEAR,0.0,true)
	view.atmosphere.set_time_of_day(14.0)
	view.atmosphere.profile.day_length_minutes = 0.0
	view.atmosphere.reset_wind()
	view.atmosphere.profile.weather_transition_seconds = 8.0
	view.atmosphere.wetness = 0.0
	_check_weather_audio()
	await _check_treasury()
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
	await _click_cell(_cell(15,24))
	check(view.sim.grid.occupied.has(_cell(15,24)), "Toolbar + world click places well")
	var count: int = view.sim.buildings.size()
	await _click_cell(_cell(15,24))
	check(view.sim.buildings.size() == count and not view.sim.last_error.is_empty(), "Invalid placement gives feedback without mutation")
	await _key(KEY_ESCAPE)
	await _click_cell(_cell(15,24))
	check(view.selected_uid == view.sim.grid.occupied.get(_cell(15,24)) and view.hud.side.visible, "Click opens detailed building inspector")
	var production_info: String = view.hud.inspector.get_parsed_text()
	check("Recipe" in production_info and "Input" in production_info and "Output" in production_info and "Workers" in production_info and "Cycle" in production_info, "Production inspector exposes recipe, slots, workforce and cycle")
	await _click(view.hud.close_inspector.get_global_rect().get_center())
	check(not view.hud.side.visible and view.selected_uid == -1, "Inspection close button clears selection")
	await _click(view.hud.demolish_button.get_global_rect().get_center())
	await _click_cell(_cell(15,24))
	check(not view.sim.grid.occupied.has(_cell(15,24)), "Demolish tool removes placed building")
	await _click(view.hud.demolish_button.get_global_rect().get_center())
	check(view.tool.selected == "inspect", "Demolish button toggles back to inspection")
	await _click(view.hud.deposits_button.get_global_rect().get_center())
	check(view.deposits_root.visible and view.hud.deposits_button.button_pressed, "Deposits button shows overlay")
	await _click(view.hud.deposits_button.get_global_rect().get_center())
	check(not view.deposits_root.visible, "Deposits button hides overlay")
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
	view.sim.step(300)
	view.hud.refresh(view.sim,view.selected_uid,view.tool.selected)
	await process_frame
	check(not view.hud.build_buttons.mill.disabled and not view.hud.build_buttons.bakery.disabled, "House upgrade unlocks mill and bakery in menu")
	await _click_cell(_cell(21,21))
	var house_info: String = view.hud.inspector.get_parsed_text()
	check("Tier 2" in house_info and "Needs" in house_info and "Bread" in house_info and "Workers provided" in house_info, "House inspector shows current tier, needs and workforce")
	check("Happiness" in house_info and "Pantry" in house_info and "Savings" in house_info and "Wage" in house_info and not view.hud.workers_button.visible, "House inspector shows happiness, pantry and household money, with no workers switch")
	await _key(KEY_ESCAPE)
	await _choose_build("mill")
	await _click_cell(_cell(16,18))
	await _choose_build("bakery")
	await _click_cell(_cell(23,18))
	check(view.sim.buildings.size() == 7, "Build menu places both chain buildings")
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
	var bakery_info: String = view.hud.inspector.get_parsed_text()
	check("Sells" in bakery_info and "Purse" in bakery_info, "Workshop inspector shows its price and purse")
	var bakery = view.sim.buildings[view.selected_uid]
	await _click(view.hud.workers_button.get_global_rect().get_center())
	check(not bakery.workers_enabled and view.hud.workers_button.text == "Resume workers", "Inspector button stops a building's workers")
	await _click(view.hud.workers_button.get_global_rect().get_center())
	check(bakery.workers_enabled, "Inspector button resumes a building's workers")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/inspection-bakery.png")
	await _click_cell(_cell(17,21))
	var storage_info: String = view.hud.inspector.get_parsed_text()
	check("Storage" in storage_info and "Carriers" in storage_info and "Bread" in storage_info and "treasury" in storage_info, "Storehouse inspector exposes inventory, carrier activity and the treasury")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/inspection-storehouse.png")
	await _key(KEY_ESCAPE)
	view.pixel_viewport.get_texture().get_image().save_png("res://artifacts/world-render.png")
	await _check_building_rotation()
	print("HEARTHLANDS VIEW: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

## VILLAGERS.md 5.1-5.2: the gold counter opens the Treasury panel, whose
## buttons set tax and move gold between free and reserved through real input.
func _check_treasury() -> void:
	var sim = view.sim
	var counter: Rect2 = view.hud.treasury_button.get_global_rect()
	check(view.hud.treasury_button.visible and view.hud.treasury_button.text == Economy.format(sim.treasury), "Gold counter shows the treasury")
	check(counter.position.x < 40 and counter.end.x < view.hud.map_button.get_global_rect().position.x and not view.hud.blocks_mouse(Vector2(640,40)), "Gold counter sits top left and leaves the top centre clear")
	await _click(counter.get_center())
	await process_frame
	check(view.hud.treasury_menu.visible and view.hud.treasury_button.button_pressed and view.hud.treasury_total.text == Economy.format(sim.treasury), "Gold counter opens the Treasury panel")
	check(view.hud.blocks_mouse(view.hud.treasury_menu.get_global_rect().get_center()), "Treasury panel blocks clicks on the world behind it")
	var tax: int = sim.tax_percent
	await _click(view.hud.tax_buttons[Economy.TAX_STEP].get_global_rect().get_center())
	check(sim.tax_percent == tax + Economy.TAX_STEP and view.hud.tax_value.text == "%d%%" % sim.tax_percent, "Treasury panel raises tax through real input")
	for step in (tax + Economy.TAX_STEP) / Economy.TAX_STEP:
		await _click(view.hud.tax_buttons[-Economy.TAX_STEP].get_global_rect().get_center())
	check(sim.tax_percent == 0 and view.hud.tax_buttons[-Economy.TAX_STEP].disabled, "Treasury panel lowers tax to zero, then stops")
	sim.set_tax_percent(tax)
	var free: int = Economy.free_gold(sim)
	await _click(view.hud.reserve_buttons.public[Economy.SILVER_PER_GOLD].get_global_rect().get_center())
	check(sim.public_reserve == mini(Economy.SILVER_PER_GOLD,free) and view.hud.treasury_values.public.text == Economy.format(sim.public_reserve), "Treasury panel sets gold aside for public pay")
	await _click(view.hud.reserve_buttons.capital[Economy.SILVER_PER_GOLD].get_global_rect().get_center())
	check(sim.capital_reserve > 0 and Economy.free_gold(sim) == free - sim.public_reserve - sim.capital_reserve and view.hud.treasury_values.free.text == Economy.format(Economy.free_gold(sim)), "Treasury panel sets gold aside for construction")
	var panel_text: String = view.hud.treasury_ledger.get_parsed_text()
	check("frustration" in panel_text and "Services" in panel_text, "Treasury panel reports services and public workers' frustration")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/treasury-panel.png")
	await _click(view.hud.reserve_buttons.public[-Economy.SILVER_PER_GOLD].get_global_rect().get_center())
	await _click(view.hud.reserve_buttons.capital[-Economy.SILVER_PER_GOLD].get_global_rect().get_center())
	check(sim.public_reserve == 0 and sim.capital_reserve == 0 and Economy.free_gold(sim) == free, "Treasury panel returns reserved gold to free gold")
	await _click(view.hud.cog_button.get_global_rect().get_center())
	check(view.hud.options_menu.visible and not view.hud.treasury_menu.visible and not view.hud.treasury_button.button_pressed, "Options and treasury panels are exclusive")
	await _key(KEY_ESCAPE)
	await _click(counter.get_center())
	await _key(KEY_ESCAPE)
	check(not view.hud.treasury_menu.visible and not view.hud.treasury_button.button_pressed, "Escape closes the Treasury panel")

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
	view._set_speed(0)
	await _choose_build("storehouse")
	var anchor := _cell(22,23)
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
	check("2 × 3" in view.hud.inspector.get_parsed_text() and "90°" in view.hud.inspector.get_parsed_text(), "Inspector shows the placed footprint and facing")
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