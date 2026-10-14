extends SceneTree
## GPU-backed integration checks for the SpacesOS port.
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _run() -> void:
	var view = load("res://view/village_view.tscn").instantiate()
	root.add_child(view)
	view._set_speed(0)
	await process_frame
	check(view.foliage.plants.size() > 100,"Imported trees and rocks populate the grid")
	check(view.foliage.grass.multimesh.instance_count > 100,"Sparse grass patches use batched SpacesOS geometry")
	var renderable := true
	for plant in view.foliage.plants.values():
		renderable = renderable and plant.mesh.get_surface_count() > 0
	check(renderable,"Every imported tree and rock has renderable surfaces")
	var cell := Vector2i(-1,-1)
	for index in view.foliage.grass.multimesh.instance_count:
		var first_tuft: Vector3 = view.foliage.grass.multimesh.get_instance_transform(index).origin
		var candidate := Vector2i(floori(first_tuft.x),floori(first_tuft.z))
		if view.sim.grid.terrain_at(candidate) == "grass":
			cell = candidate
			break
	var before: int = view.foliage.grass.multimesh.instance_count
	check(view.sim.place_road([cell]),"Road placement succeeds")
	view._sync_view()
	var remaining_tufts := 0
	for index in view.foliage.grass.multimesh.instance_count:
		var at: Vector3 = view.foliage.grass.multimesh.get_instance_transform(index).origin
		if Vector2i(floori(at.x),floori(at.z)) == cell: remaining_tufts += 1
	check(remaining_tufts == 0,"Road clears grass")
	check(view.sim.demolish(cell),"Road demolition succeeds")
	view._sync_view()
	check(view.foliage.grass.multimesh.instance_count == before,"Demolition restores deterministic grass")
	var snapshot: Dictionary = view.sim.snapshot()
	view.foliage.sync_grid(view.sim.grid)
	check(view.sim.snapshot() == snapshot,"Foliage never mutates simulation state or RNG")
	var atmosphere: AtmosphereSystem = view.atmosphere
	atmosphere.set_process(false)
	atmosphere.set_time_of_day(14.0)
	atmosphere._tick(0.0)
	var day_energy: float = atmosphere.sun.light_energy
	await shot("day")
	atmosphere.set_time_of_day(0.0)
	atmosphere._tick(0.0)
	check(atmosphere.sun.light_energy < day_energy,"Night reduces directional lighting")
	check(AtmosphereSystem.night_lights > 0.5,"Night drives imported lighting globals")
	await shot("night")
	atmosphere.set_time_of_day(14.0)
	atmosphere.set_weather(AtmosphereProfile.Weather.RAIN,1.0,true)
	atmosphere._tick(1.0)
	check(atmosphere.wetness > 0.0 and atmosphere.gust_scale > 1.0,"Rain wets surfaces and increases foliage wind")
	check(atmosphere._rain.emitting,"Rain particles are active")
	check(atmosphere._rain.global_position.distance_to(view.weather_focus.global_position) < 35.0,"Rain follows the village focus")
	await shot("rain")
	view._restart()
	atmosphere._tick(0.0)
	check(atmosphere.get_weather() == AtmosphereProfile.Weather.CLEAR and atmosphere.wetness == 0.0,"Restart resets weather")
	view.queue_free()
	await process_frame
	check(AtmosphereSystem.night_lights == 0.0,"Leaving resets lighting globals")
	print("ENVIRONMENT: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func shot(label: String) -> void:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://artifacts/environment-%s.png" % label) == OK,"Save " + label + " preview")
