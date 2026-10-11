extends SceneTree
## GPU regression checks for art direction, placement and environmental time.
var failures: Array[String] = []
var checks := 0
var view

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: "+message)

func _run() -> void:
	view = load("res://view/village_view.tscn").instantiate()
	root.add_child(view)
	# Keep art comparisons at their historical native resolution; the playable
	# scene now starts in smooth mode, covered by the view/input suite.
	view._set_pixel_effect(true)
	view._set_speed(0)
	view.atmosphere.set_process(false)
	view.foliage.set_process(false)
	var original: Dictionary = view.sim.snapshot()
	check(view.camera.focus == Vector3(view.sim.site.founding_spot.x+5,0,view.sim.site.founding_spot.y-3) and view.camera.zoom_size == 22.0 and view.camera.quarter_turn == 0,"Camera frames the central clearing")
	check(view.pixel_viewport.size == Vector2i(640,360) and view.display.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,"Native pixel resolution preserved")
	check(not view.atmosphere.world_environment.environment.glow_enabled,"Village bloom disabled")
	var sun_direction: Vector3 = view.atmosphere.sun.basis.z
	check(sun_direction.dot(view.camera.basis.x) < -0.3 and sun_direction.dot(view.camera.basis.y) > 0.3,"Sun projects from the upper-left of the original screen")
	check(view.foliage.detailed_meadow_cells < view.foliage.meadow_cells*0.22,"About 80% of meadow cells remain quiet")
	print("MEADOW: %d detailed / %d open cells" % [view.foliage.detailed_meadow_cells,view.foliage.meadow_cells])
	var expected_plants := 0
	for y in view.sim.grid.height:
		for x in view.sim.grid.width:
			var terrain: String = view.sim.grid.terrain_at(Vector2i(x,y))
			if terrain in ["forest","rock"]: expected_plants += 1
	check(view.foliage.plants.size() == expected_plants,"Tree and rock count matches original scatter")
	for cell in view.foliage.plants:
		check(view.foliage.plants[cell].position == Vector3(cell.x+0.5,0.02,cell.y+0.5),"Original vegetation position retained")
	var tuft_buffer: PackedFloat32Array = view.foliage.grass.multimesh.buffer.duplicate()
	var targets: Array[Vector2i] = []
	for i in view.foliage.grass.multimesh.instance_count:
		var at: Vector3 = view.foliage.grass.multimesh.get_instance_transform(i).origin
		var cell := Vector2i(floori(at.x),floori(at.z))
		if not view.sim.grid.roads.has(cell) and view.sim.grid.terrain_at(cell) == "grass":
			targets.append(cell)
			break
	check(not targets.is_empty(),"Sparse grass still has a road-carving target")
	var before: int = view.foliage.grass.multimesh.instance_count
	check(view.sim.place_road(targets),"Place a road through a visible grass patch")
	view._sync_view()
	var remaining_tufts := 0
	for index in view.foliage.grass.multimesh.instance_count:
		var at: Vector3 = view.foliage.grass.multimesh.get_instance_transform(index).origin
		if Vector2i(floori(at.x),floori(at.z)) == targets[0]: remaining_tufts += 1
	check(remaining_tufts == 0,"Construction removes every tuft in its cell")
	check(view.sim.demolish(targets[0]),"Demolish art-test road")
	view._sync_view()
	check(view.foliage.grass.multimesh.buffer == tuft_buffer,"Demolition restores exact seeded grass placement")
	var paused_snapshot: Dictionary = view.sim.snapshot()
	view.atmosphere._tick(0.0)
	await _check_tree_motion()
	var before_cloud: Vector2 = view.atmosphere._cloud_offset
	var image_before := await capture("art-cloud-0")
	view.atmosphere._tick(40.0)
	# Hold vegetation at the first capture's pose to isolate cloud lighting.
	RenderingServer.global_shader_parameter_set("village_wind_time",0.0)
	var image_after := await capture("art-cloud-40")
	RenderingServer.global_shader_parameter_set("village_wind_time",view.atmosphere.wind_time)
	check(before_cloud != view.atmosphere._cloud_offset,"Cloud field drifts over environmental time")
	var changed := 0
	for y in range(80,280):
		for x in range(140,500):
			var difference := image_before.get_pixel(x,y)-image_after.get_pixel(x,y)
			if absf(difference.r)+absf(difference.g)+absf(difference.b) > 0.03: changed += 1
	check(changed > 100,"Large cloud shadows change rendered clearing light")
	print("CLOUD: %d native clearing pixels changed after 40 environmental seconds" % changed)
	check(view.sim.snapshot() == paused_snapshot,"Atmospheric time leaves paused simulation and RNG untouched")
	view.foliage._process(4.0)
	view.foliage.ambience_time = 4.0
	view.foliage._process(0.125)
	var active := 0
	for mote in view.foliage.motes:
		if mote.visible: active += 1
	check(active <= 1,"Motes appear as sparse occasional events")
	view.atmosphere.set_time_of_day(0.0)
	view.atmosphere._tick(0.0)
	view.foliage._process(0.125)
	check(view.atmosphere.cloud_shadow == 0.0,"Cloud shadows fade at night")
	for mote in view.foliage.motes: check(not mote.visible,"Golden seed motes hidden at night")
	await capture("art-night")
	view._restart()
	view._set_speed(0)
	check(view.sim.snapshot() == original,"Restart restores original simulation exactly")
	check(is_equal_approx(view.atmosphere.get_time_of_day(),16.0),"Restart restores late-afternoon art direction")
	view.atmosphere._tick(0.0)
	view.sim.step(300)
	view._complete_chain()
	view.sim.step(500)
	view._sync_view()
	view.hud.refresh(view.sim,view.selected_uid,view.tool.selected)
	var final_image := await capture("atmosphere-after-native")
	var golden_pixels := 0
	var clipped_white := 0
	for y in range(20,340):
		for x in range(20,620):
			var colour := final_image.get_pixel(x,y)
			if colour.r > 0.52 and colour.g > 0.43 and colour.b < colour.g*0.70 and colour.r >= colour.g*0.90: golden_pixels += 1
			if colour.r > 0.99 and colour.g > 0.99 and colour.b > 0.99: clipped_white += 1
	check(golden_pixels > 8000,"Reference pass produces broad golden light, beyond a few roof highlights")
	check(clipped_white < 1000,"Brighter palette retains highlight detail without broad white clipping")
	print("PALETTE: %d golden pixels; %d clipped white pixels" % [golden_pixels,clipped_white])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/atmosphere-after.png")
	view.queue_free()
	await process_frame
	print("ART DIRECTION: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func capture(label: String) -> Image:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = view.pixel_viewport.get_texture().get_image()
	check(image.save_png("res://artifacts/%s.png" % label) == OK,"Save "+label+" render")
	return image

func _check_tree_motion() -> void:
	# Freeze cloud, lighting and water time; advance only wind. Compare actual
	# crown pixels, then prove the live zero-breeze control stops deformation.
	var tree_regions: Array[Rect2i] = []
	for cell in view.foliage.plants:
		if view.sim.grid.terrain_at(cell) != "forest": continue
		var plant: MeshInstance3D = view.foliage.plants[cell]
		var root_pixel: Vector2 = view.camera.unproject_position(plant.position)
		var top_pixel: Vector2 = view.camera.unproject_position(plant.position+Vector3.UP*plant.mesh.get_aabb().size.y)
		var span := int(absf(root_pixel.y-top_pixel.y)*0.65)
		var region := Rect2i(Vector2i(int(top_pixel.x)-span,int(top_pixel.y)),Vector2i(span*2,int(root_pixel.y-top_pixel.y)))
		region = region.intersection(Rect2i(0,0,640,360))
		if region.has_area(): tree_regions.append(region)
	var still := await capture("trees-wind-0")
	view.atmosphere.wind_time = 4.0
	RenderingServer.global_shader_parameter_set("village_wind_time",4.0)
	var breezy := await capture("trees-wind-4")
	var moving := _changed_tree_pixels(still,breezy,tree_regions)
	check(moving > 300,"Default breeze visibly moves rendered crowns with clouds and lighting frozen")
	print("TREE WIND: %d changed crown pixels after four wind seconds" % moving)
	view.atmosphere.set_wind(view.atmosphere.wind_from_degrees(),0.0,1.0)
	var calm := await capture("trees-calm-4")
	view.atmosphere.wind_time = 8.0
	RenderingServer.global_shader_parameter_set("village_wind_time",8.0)
	var later := await capture("trees-calm-8")
	check(_changed_tree_pixels(calm,later,tree_regions) == 0,"Zero breeze freezes crown deformation")
	view.atmosphere.reset_wind()
	view.atmosphere.set_weather(AtmosphereProfile.Weather.STORM,1.0,true)
	view.atmosphere._tick(1.0)
	check(is_equal_approx(view.atmosphere.wind_time,9.9),"Storm accelerates the shared wind clock")
	view.atmosphere.set_weather(AtmosphereProfile.Weather.CLEAR,0.0,true)
	view.atmosphere.reset_art_motion()
	view.atmosphere._tick(0.0)

func _changed_tree_pixels(first: Image, second: Image, regions: Array[Rect2i]) -> int:
	var pixels := {}
	for region in regions:
		for y in range(region.position.y,region.end.y):
			for x in range(region.position.x,region.end.x):
				var delta := first.get_pixel(x,y)-second.get_pixel(x,y)
				if absf(delta.r)+absf(delta.g)+absf(delta.b) > 0.08: pixels[Vector2i(x,y)] = true
	return pixels.size()
