extends SceneTree
## Real Forward+ render and input smoke. Needs a GPU, unlike run_tests.gd.
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
	view.speed = 0
	check(view.sim.buildings.size() == 5, "Playable starter has five buildings")
	check(view.hud.bottom.get_child(0).get_child_count() == 3, "Play screen has exactly three bottom actions")
	check(not view.hud.side.visible and not view.hud.build_menu.visible and not view.hud.toast.visible, "Start has no persistent text panels")
	check(not view.hud.blocks_mouse(Vector2(640,40)), "Top of play screen is unobstructed")
	await _click(view.hud.build_button.get_global_rect().get_center())
	check(view.hud.build_menu.visible, "Build button opens menu")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/build-menu.png")
	await _click(view.hud.build_buttons.road.get_global_rect().get_center())
	check(view.tool.selected == "road" and not view.hud.build_menu.visible, "Choosing a road closes build menu")
	await _click_cell(Vector2i(14,23))
	await _click_cell(Vector2i(16,23))
	check(view.sim.grid.roads.has(Vector2i(15,23)), "Two world clicks build a road segment")
	await _choose_build("well")
	await _click_cell(Vector2i(15,24))
	check(view.sim.grid.occupied.has(Vector2i(15,24)), "Toolbar + world click places well")
	var count: int = view.sim.buildings.size()
	await _click_cell(Vector2i(15,24))
	check(view.sim.buildings.size() == count and not view.sim.last_error.is_empty(), "Invalid placement gives feedback without mutation")
	await _key(KEY_ESCAPE)
	await _click_cell(Vector2i(15,24))
	check(view.selected_uid == view.sim.grid.occupied.get(Vector2i(15,24)) and view.hud.side.visible, "Click opens compact building inspector")
	await _click(view.hud.demolish_button.get_global_rect().get_center())
	await _click_cell(Vector2i(15,24))
	check(not view.sim.grid.occupied.has(Vector2i(15,24)), "Demolish tool removes placed building")
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
	await _key(KEY_F2)
	check(not view.pipeline_enabled, "F2 switches to raw toon comparison")
	await _key(KEY_F2)
	check(view.pipeline_enabled, "F2 restores pixel pipeline")
	await _key(KEY_F3)
	check(view.deposits_root.visible and view.hud.deposits_button.button_pressed, "F3 keeps deposits button state in sync")
	await _key(KEY_F3)
	view._restart()
	view.speed = 0
	view.sim.step(300)
	view.hud.refresh(view.sim,view.selected_uid,view.tool.selected)
	await process_frame
	check(not view.hud.build_buttons.mill.disabled and not view.hud.build_buttons.bakery.disabled, "House upgrade unlocks mill and bakery in menu")
	await _choose_build("mill")
	await _click_cell(Vector2i(16,18))
	await _choose_build("bakery")
	await _click_cell(Vector2i(23,18))
	check(view.sim.buildings.size() == 7, "Build menu places both chain buildings")
	await _key(KEY_ESCAPE)
	view.sim.step(500)
	view._sync_view()
	check(int(view.sim.produced.get("bread",0)) > 0, "Rendered scene produces bread")
	check(view.integer_scale == 2 and view.display.size == Vector2(1280,720), "Native pixels use integer nearest upscaling")
	view.hud.refresh(view.sim,view.selected_uid,view.tool.selected)
	await process_frame
	await RenderingServer.frame_post_draw
	var final_image := root.get_texture().get_image()
	check(final_image.save_png("res://artifacts/view-tested.png") == OK, "Capture rendered input-tested scene")
	var colors: Dictionary = {}
	var nearest_ok := true
	for y in range(112,570,2):
		for x in range(24,960,2):
			var color := final_image.get_pixel(x,y)
			colors[color.to_rgba32()] = true
			nearest_ok = nearest_ok and color == final_image.get_pixel(x+1,y) and color == final_image.get_pixel(x,y+1)
	check(colors.size() <= 32 and colors.size() > 8, "Rendered world is quantized to at most 32 colors (actual %d)" % colors.size())
	check(nearest_ok, "Each native world pixel is an exact 2x2 block")
	# Separate low-resolution output for inspecting native outlines and palette.
	var outlined: Image = view.pixel_viewport.get_texture().get_image()
	outlined.save_png("res://artifacts/native-toon-outline.png")
	view.palette_material.set_shader_parameter("enabled",false)
	view.outline_material.set_shader_parameter("enabled",false)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/raw-toon.png")
	check(root.get_texture().get_image().get_data() != final_image.get_data(), "Pipeline comparison changes rendered output")
	check(view.pixel_viewport.get_texture().get_image().get_data() != outlined.get_data(), "Depth/normal outline pass changes native 3D pixels")
	print("HEARTHLANDS VIEW: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _click_cell(cell: Vector2i) -> void:
	var local: Vector2 = view.camera.unproject_position(Vector3(cell.x+0.5,0,cell.y+0.5))
	await _click(view.display.position+local*view.integer_scale)

func _choose_build(id: String) -> void:
	await _click(view.hud.build_button.get_global_rect().get_center())
	await _click(view.hud.build_buttons[id].get_global_rect().get_center())

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
