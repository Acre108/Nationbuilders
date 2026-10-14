extends SceneTree
## Paired GPU review and boundary checks for campaign village landscapes.
const Campaign = preload("res://sim/campaign.gd")
const Scenario = preload("res://sim/scenario.gd")
var checks := 0
var failures: Array[String] = []
var view

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func frames(count: int = 4) -> void:
	for index in count: await process_frame

func _run() -> void:
	for seed_value in [73,1,2]:
		var campaign = Campaign.new()
		check(campaign.generate("Landscape review",seed_value), "Generate review world")
		check(campaign.found(campaign.world.start,"River Hearth"), "Found at the tested starting tile")
		if campaign.village == null: continue
		view = load("res://view/village_view.tscn").instantiate()
		view.campaign = campaign
		root.add_child(view)
		view._set_speed(0)
		view.atmosphere.set_process(false)
		view.foliage.set_process(false)
		view.atmosphere.set_time_of_day(16.0)
		view.atmosphere.reset_art_motion()
		view.atmosphere._tick(0.0)
		await frames()
		var sim = view.sim
		var before: Dictionary = sim.snapshot()
		var root_count := 0
		var roots_inside := true
		for cell in view.foliage.plants:
			var plant = view.foliage.plants[cell]
			root_count += 1
			var actual := Vector2i(floori(plant.position.x),floori(plant.position.z))
			if actual != cell or not sim.grid.inside(actual): roots_inside = false
		check(root_count > 100 and roots_inside, "Foliage roots retain their resource cell and physical hex boundary")
		var arrays: Array = view.factory.terrain_node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var visible_inside := true
		for index in range(0,vertices.size(),3):
			if normals[index].y < 0.1: continue
			var centre := (vertices[index] + vertices[index+1] + vertices[index+2]) / 3.0
			if not sim.grid.inside(Vector2i(floori(centre.x),floori(centre.z))): visible_inside = false
		check(visible_inside, "No top surfaces leak into exterior rectangular corners")
		view.deposits_root.visible = false
		await capture("generated-village-%d-close.png" % seed_value)
		view._overview_site()
		await capture("generated-village-%d-overview.png" % seed_value)
		var saved_world = view.sim.snapshot()
		view.foliage.build(sim.grid)
		check(view.sim.snapshot() == saved_world, "Rebuilding landscape art leaves simulation and RNG unchanged")
		check(sim.snapshot() == before, "Visual review leaves paused simulation unchanged")
		# Snapshot and terrain metadata survive the same campaign restore used by play.
		var path := "res://artifacts/landscape-campaigns"
		check(campaign.save(path), "Save generated landscape")
		var restored = Campaign.new()
		check(restored.load_save(path.path_join(campaign.id + ".campaign")), "Load generated landscape")
		check(restored.village.site.footprint == sim.site.footprint and restored.village.grid.districts == sim.grid.districts, "Saved hex geometry and regional art metadata are retained")
		view.queue_free()
		await frames(2)
	print("GENERATED SITE VIEW: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func capture(filename: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/" + filename) == OK,"Saved " + filename)
