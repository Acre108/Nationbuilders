extends SceneTree
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
	view._set_speed(0)
	view.atmosphere.set_process(false)
	view.foliage.set_process(false)
	view.hud.visible = false
	check(view.foliage.plants.size() >= view.sim.grid.trees.size(),"Every initial tree has a shared visible mesh")
	var cutter
	for building in view.sim.buildings.values():
		if building.definition.id == "woodcutter": cutter = building
	view.sim.step()
	var tree: Vector2i = cutter.work_cell
	check(view.foliage.plants.has(tree),"Woodcutter targets a rendered tree")
	view.sim.step(64)
	view._sync_view()
	check(not view.foliage.plants.has(tree) and view.foliage.stump_nodes.has(tree),"Harvest replaces the tree with a stump")
	check(not view.deposit_nodes.has(tree),"Timber overlay clears the harvested deposit")
	check(cutter.output.count("logs") == 1,"Harvested log waits in local output")
	var before: Dictionary = view.sim.snapshot()
	view._sync_view()
	check(view.sim.snapshot() == before,"Tree presentation leaves simulation and RNG untouched")
	var shift: Vector2i = preload("res://sim/scenario.gd").offset(view.sim)
	var anchor := Vector2i(26,18)+shift
	check(view.sim.place("forester",anchor,1),"Place rotated forester beside the road")
	view._sync_view()
	var forester = view.sim.buildings[view.sim.grid.occupied[anchor]]
	var model: Node3D = view.building_nodes[forester.uid]
	check(model.get_meta("medieval",false) and is_equal_approx(model.rotation.y,PI/2),"Forester uses authored model and build facing")
	view.hud.refresh(view.sim,forester.uid,"inspect")
	check("mature in 60 s" in view.hud.inspector.get_parsed_text(),"Inspector explains regrowth")
	view.sim.step(50)
	view._sync_view()
	check(not view.sim.grid.saplings.is_empty(),"Forester plants nearby")
	var cell: Vector2i = view.sim.grid.saplings.keys()[0]
	var plant: MeshInstance3D = view.foliage.plants[cell]
	var scale: float = plant.scale.x
	check(scale < 0.4,"New tree appears as a small sapling")
	view.sim.set_workers_enabled(forester.uid,false)
	view.sim.set_workers_enabled(cutter.uid,false)
	view.camera.focus = Vector3(anchor.x+1,0,anchor.y+2)
	view.camera.zoom_size = 16
	view.camera.refresh()
	await capture("forestry-saplings")
	view.sim.step(300)
	view._sync_view()
	check(view.foliage.plants[cell] == plant and plant.scale.x > scale and plant.scale.x < 1.0,"Sapling grows using the same mesh instance")
	view.sim.step(300)
	view._sync_view()
	check(view.sim.grid.trees.has(cell) and plant.scale == Vector3.ONE,"Mature tree becomes full size and harvestable")
	check(view.deposit_nodes.has(cell),"Timber overlay shows the newly mature tree")
	check_incremental_matches_full()
	await capture("forestry-grown")
	view.camera.focus = Vector3(43,0,48)
	view.camera.zoom_size = 66
	view.camera.refresh()
	await capture("forestry-map")
	view._restart()
	view._set_speed(0)
	check(view.sim.tick == 0 and view.sim.grid.saplings.is_empty() and view.foliage.stump_nodes.is_empty(),"Restart rebuilds initial woodland")
	view.queue_free()
	await process_frame
	print("FORESTRY VIEW: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

## Felling, planting and growth update the ground and grass only near the
## change; the result must equal rebuilding the whole site.
func check_incremental_matches_full() -> void:
	var GridChanges = preload("res://view/grid_changes.gd")
	var factory = view.factory
	var foliage = view.foliage
	var incremental := [factory.context_image.get_data(), factory.terrain_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR], foliage.grass.multimesh.buffer, foliage.contact.multimesh.buffer, foliage.meadow_cells, foliage.detailed_meadow_cells]
	factory.context_changes = GridChanges.new()
	factory.context_revision = -1
	factory.forest_ground_changes = GridChanges.new()
	factory.sync_forest_ground(view.sim.grid)
	foliage.changes = GridChanges.new()
	foliage.sync_grid(view.sim.grid)
	var full := [factory.context_image.get_data(), factory.terrain_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR], foliage.grass.multimesh.buffer, foliage.contact.multimesh.buffer, foliage.meadow_cells, foliage.detailed_meadow_cells]
	check(incremental == full,"Incremental ground and grass updates match a full rebuild")

func capture(label: String) -> void:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = view.pixel_viewport.get_texture().get_image()
	check(image.save_png("res://artifacts/"+label+".png") == OK,"Save "+label+" review capture")
