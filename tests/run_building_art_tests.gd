extends SceneTree
## Integrated inventory presentation checks and GPU review captures.
const Building = preload("res://sim/building.gd")
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

func visible_stock(node: Node3D, lane: String) -> Dictionary:
	var result: Dictionary = {}
	for prop in node.get_node("Stock/" + lane).get_children():
		if prop.visible:
			var good := str(prop.get_meta("good"))
			result[good] = int(result.get(good, 0)) + 1
	return result

func _run() -> void:
	view = load("res://view/village_view.tscn").instantiate()
	root.add_child(view)
	view._set_speed(0)
	view.atmosphere.set_process(false)
	view.foliage.set_process(false)
	view.sim.step(300)
	view._complete_chain()
	view._sync_view()
	for state in view.sim.buildings.values():
		var node: Node3D = view.building_nodes[state.uid]
		check(node.get_meta("medieval", false), "Authored model used for " + str(state.definition.id))
		if state.definition.id == "mill":
			var sails: Node3D = node.get_node("Sails")
			check(sails.basis.z.is_equal_approx(Vector3.BACK), "Mill sail rotation stays in the front XY plane")
		if state.definition.kind == "producer":
			check(visible_stock(node, "Input") == state.input.items, "Initial inputs match " + str(state.definition.id))
			check(visible_stock(node, "Output") == state.output.items, "Initial outputs match " + str(state.definition.id))
	# Delivery, recipe consumption and pickups run through the real simulation.
	var seen: Dictionary = {}
	var consumed := false
	var pickup := false
	var previous: Dictionary = {}
	for tick in 700:
		view.sim.step(1)
		var snapshot: Dictionary = view.sim.snapshot()
		view._sync_view()
		check(view.sim.snapshot() == snapshot, "Presentation leaves simulation and RNG unchanged")
		for state in view.sim.buildings.values():
			if state.definition.kind != "producer": continue
			var node: Node3D = view.building_nodes[state.uid]
			check(visible_stock(node, "Input") == state.input.items, "Live input stock follows deliveries/consumption")
			check(visible_stock(node, "Output") == state.output.items, "Live output stock follows production/pickups")
			for good in state.input.items: seen[good] = true
			for good in state.output.items: seen[good] = true
			if previous.has(state.uid):
				if state.input.total() < int(previous[state.uid][0]): consumed = true
				if state.output.total() < int(previous[state.uid][1]): pickup = true
			previous[state.uid] = [state.input.total(), state.output.total()]
	check(consumed and pickup, "Observed both recipe consumption and carrier pickup")
	for good in ["water", "logs", "wheat", "flour", "bread"]:
		check(seen.has(good), "Live chain showed " + good)
	# Isolated full/empty fixture validates mixed input goods and visual reuse.
	var fixture = Building.new(-1, view.sim.db.buildings.bakery, Vector2i.ZERO)
	var bakery: Node3D = view.factory.building(fixture.definition, 1)
	view.world.add_child(bakery)
	fixture.input.add("flour", 3)
	fixture.input.add("water", 3)
	fixture.output.add("bread", 6)
	view.factory.medieval.sync_stock(bakery, fixture)
	check(visible_stock(bakery, "Input") == {"flour": 3, "water": 3}, "Mixed inputs have distinct sacks and barrels")
	check(visible_stock(bakery, "Output") == {"bread": 6}, "Full output rack shows all six units")
	var first_prop: Node3D = bakery.get_node("Stock/Output/bread_0")
	fixture.input.take("flour", 3)
	fixture.input.take("water", 3)
	fixture.output.take("bread", 6)
	view.factory.medieval.sync_stock(bakery, fixture)
	check(visible_stock(bakery, "Input").is_empty() and visible_stock(bakery, "Output").is_empty(), "Empty building has no decorative stock")
	fixture.output.add("bread")
	view.factory.medieval.sync_stock(bakery, fixture)
	check(bakery.get_node("Stock/Output/bread_0") == first_prop and first_prop.visible, "Stock props reused after depletion")
	bakery.free()
	# Capture the playable village with honest inventory, then an explicit staged kit.
	view.hud.visible = false
	await capture("medieval-village", true)
	view.camera.zoom_size = 16
	view.camera.focus = Vector3(view.sim.site.founding_spot.x+3,0,view.sim.site.founding_spot.y-1)
	view.camera.refresh()
	await capture("medieval-village-close", true)
	view.buildings_root.visible = false
	view.roads_root.visible = false
	view.scenery_root.visible = false
	view.carrier_root.visible = false
	view.foliage.visible = false
	# A neutral backdrop keeps the staged asset sheet distinct from game captures.
	view.atmosphere.world_environment.environment.background_mode = Environment.BG_COLOR
	view.atmosphere.world_environment.environment.background_color = Color("555f60")
	view.atmosphere.world_environment.environment.fog_enabled = false
	var gallery := Node3D.new()
	view.world.add_child(gallery)
	view.factory.box(gallery,Vector3(21,-.04,20),Vector3(18,.06,12),Color("a69b76"))
	var ids := ["house", "house", "storehouse", "farm", "well", "woodcutter", "mill", "bakery"]
	var fixtures: Array = []
	for i in ids.size():
		var state = Building.new(-10-i, view.sim.db.buildings[ids[i]], Vector2i.ZERO)
		var node: Node3D = view.factory.building(state.definition, 2 if i == 1 else 1)
		node.position = Vector3(15+float(i%4)*3.9,0,17+float(i/4)*4.3)
		gallery.add_child(node)
		fixtures.append([node,state])
		var label := Label3D.new()
		label.text = "Homestead II" if i == 1 else str(state.definition.name)
		label.position = node.position + Vector3(0,.03,1.36)
		label.rotation_degrees.x = -90
		label.font_size = 40
		label.pixel_size = .007
		label.modulate = Color("302e26")
		label.outline_modulate = Color("d7caa4")
		gallery.add_child(label)
	view.pixel_viewport.size = Vector2i(1280,720)
	view.camera.zoom_size = 15
	view.camera.focus = Vector3(20.7,.2,19.4)
	view.camera.refresh()
	await capture("medieval-kit-empty", false)
	for pair in fixtures:
		var state = pair[1]
		if state.definition.kind != "producer": continue
		for good in state.definition.inputs:
			state.input.add(good, 3 if state.definition.inputs.size() == 2 else 6)
		for good in state.definition.outputs: state.output.add(good, 6)
		view.factory.medieval.sync_stock(pair[0],state)
	await capture("medieval-kit-stocked", false)
	# Side view clearly shows input sacks/barrels separately from saleable bread.
	for pair in fixtures: pair[0].visible = str(pair[1].definition.id) == "bakery"
	for child in gallery.get_children():
		if child is Label3D: child.visible = false
	view.camera.focus = fixtures[7][0].position + Vector3(0,.5,0)
	view.camera.zoom_size = 4.5
	view.camera.quarter_turn = 3
	view.camera.refresh()
	await capture("medieval-bakery-stocked", false)
	var stock_bakery = fixtures[7][1]
	stock_bakery.input.take("flour",3)
	stock_bakery.input.take("water",3)
	stock_bakery.output.take("bread",6)
	view.factory.medieval.sync_stock(fixtures[7][0],stock_bakery)
	await capture("medieval-bakery-empty", false)
	view.queue_free()
	await process_frame
	print("MEDIEVAL BUILDINGS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func capture(name: String, pixel_scale: bool) -> void:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = view.pixel_viewport.get_texture().get_image()
	if pixel_scale: image.resize(image.get_width()*2,image.get_height()*2,Image.INTERPOLATE_NEAREST)
	image.save_png("res://artifacts/"+name+".png")
