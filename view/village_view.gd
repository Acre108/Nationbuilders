extends Control
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const MeshFactory = preload("res://view/mesh_factory.gd")
const CameraRig = preload("res://view/camera_rig.gd")
const BuildTool = preload("res://view/build_tool.gd")
const HUD = preload("res://view/overlays/village_hud.gd")
const PaletteLUT = preload("res://render/palette_lut.gd")
var sim
var factory := MeshFactory.new()
var tool := BuildTool.new()
var pixel_viewport: SubViewport
var display: TextureRect
var world: Node3D
var camera
var hud
var buildings_root: Node3D
var roads_root: Node3D
var ghost_root: Node3D
var deposits_root: Node3D
var carrier_root: Node3D
var scenery_root: Node3D
var building_nodes: Dictionary = {}
var carrier_nodes: Dictionary = {}
var last_revision := -1
var selected_uid := -1
var hover_cell := Vector2i(-1,-1)
var accumulator := 0.0
var speed := 1
var integer_scale := 2
var pipeline_enabled := true
var outline_material: ShaderMaterial
var palette_material: ShaderMaterial
var hud_elapsed := 0.0
var ghost_signature := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pixel_viewport = preload("res://render/pixel_viewport.tscn").instantiate()
	add_child(pixel_viewport)
	world = pixel_viewport.get_node("World")
	display = TextureRect.new()
	display.texture = pixel_viewport.get_texture()
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	palette_material = ShaderMaterial.new()
	palette_material.shader = preload("res://render/palette.gdshader")
	palette_material.set_shader_parameter("color_lut",PaletteLUT.create())
	display.material = palette_material
	add_child(display)
	camera = CameraRig.new()
	world.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-35,0)
	light.light_color = Color("f0e2bc")
	light.light_energy = 1.05
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 80
	world.add_child(light)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("244043")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b9bca3")
	settings.ambient_light_energy = 0.7
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	world.add_child(environment)
	var quad := MeshInstance3D.new()
	var shape := QuadMesh.new()
	shape.size = Vector2(2,2)
	quad.mesh = shape
	quad.extra_cull_margin = 16384.0
	outline_material = ShaderMaterial.new()
	outline_material.shader = preload("res://render/outline.gdshader")
	outline_material.render_priority = 100
	quad.material_override = outline_material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(quad)
	for kind in ["buildings","roads","ghost","deposits","carriers","scenery"]:
		var node := Node3D.new()
		node.name = kind
		world.add_child(node)
		match kind:
			"buildings": buildings_root = node
			"roads": roads_root = node
			"ghost": ghost_root = node
			"deposits": deposits_root = node
			"carriers": carrier_root = node
			"scenery": scenery_root = node
	hud = HUD.new()
	add_child(hud)
	hud.tool_selected.connect(_select_tool)
	hud.deposits_toggled.connect(_toggle_deposits)
	hud.inspection_closed.connect(func():
		selected_uid = -1
		hud.refresh(sim,selected_uid,tool.selected)
	)
	resized.connect(_resize_display)
	_resize_display()
	_restart()
	# Render smoke uses the same running scene and public commands.
	if "--render-smoke" in OS.get_cmdline_user_args():
		_render_smoke.call_deferred()

func _resize_display() -> void:
	integer_scale = maxi(1,mini(floori(size.x/640.0),floori(size.y/360.0)))
	display.size = Vector2(640,360) * integer_scale
	display.position = ((size-display.size)/2.0).floor()

func _restart() -> void:
	sim = Sim.new(73)
	if not sim.valid or not Scenario.starter(sim):
		push_error("Starter failed: " + sim.last_error)
		get_tree().quit(1)
		return
	for root in [buildings_root,roads_root,carrier_root,scenery_root,deposits_root,ghost_root]:
		_clear(root)
	building_nodes.clear()
	carrier_nodes.clear()
	selected_uid = -1
	factory.terrain(scenery_root,sim.grid)
	_build_scenery()
	last_revision = -1
	accumulator = 0
	speed = 1
	tool.choose("inspect")
	ghost_signature = ""
	_sync_view()
	hud.configure_build_menu(sim.db)
	hud.reset()
	hud.refresh(sim,selected_uid,tool.selected)

func _build_scenery() -> void:
	for y in 40:
		for x in 40:
			var cell := Vector2i(x,y)
			var tile: String = sim.grid.terrain_at(cell)
			var at := Vector3(x+0.5,0,y+0.5)
			if tile == "forest" and (x+y)%3 == 0:
				var tree := Node3D.new()
				tree.name = "tree_%d_%d" % [x,y]
				tree.position = at
				scenery_root.add_child(tree)
				var height := 1.5 + float((x*13+y*7)%5)*0.18
				factory.cylinder(tree,Vector3(0,0.4,0),0.12,0.8,Color("625144"))
				factory.cylinder(tree,Vector3(0,height*0.62,0),0.64,height,Color("426b46"),0)
				factory.cylinder(tree,Vector3(0,height*0.98,0),0.45,height*0.65,Color("54814d"),0)
			elif tile == "rock":
				factory.cylinder(scenery_root,at+Vector3.UP*0.3,0.45,0.7,Color("829080"),0.24)
			var deposit: String = sim.grid.deposits[y*40+x]
			if not deposit.is_empty():
				var deposit_color := Color("d0b686") if deposit == "fertile_soil" else Color("8db9bf")
				factory.box(deposits_root,at+Vector3.UP*0.025,Vector3(0.85,0.035,0.85),deposit_color)
	deposits_root.visible = false

func _process(delta: float) -> void:
	if sim == null:
		return
	accumulator += delta * speed
	# Rendering can lag; accumulated fixed ticks are never discarded.
	var iterations := 0
	while accumulator >= 0.1 and iterations < 100:
		sim.step(1)
		accumulator -= 0.1
		iterations += 1
	var pan := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A): pan.x -= 1
	if Input.is_physical_key_pressed(KEY_D): pan.x += 1
	if Input.is_physical_key_pressed(KEY_W): pan.y += 1
	if Input.is_physical_key_pressed(KEY_S): pan.y -= 1
	if pan != Vector2.ZERO:
		camera.pan(pan.normalized(),delta)
	_sync_view()
	_update_ghost()
	hud_elapsed += delta
	if hud_elapsed >= 0.15:
		hud_elapsed = 0
		hud.refresh(sim,selected_uid,tool.selected)

func _sync_view() -> void:
	if last_revision != sim.grid.revision:
		_clear(roads_root)
		for cell in sim.grid.roads:
			factory.box(roads_root,Vector3(cell.x+0.5,0.035,cell.y+0.5),Vector3(0.98,0.06,0.98),Color("b9a983"))
		for uid in building_nodes.keys():
			if not sim.buildings.has(uid):
				building_nodes[uid].queue_free()
				building_nodes.erase(uid)
		for child in scenery_root.get_children():
			if child.name.begins_with("tree_"):
				var parts := str(child.name).split("_")
				var cell := Vector2i(int(parts[1]),int(parts[2]))
				child.visible = not sim.grid.occupied.has(cell) and not sim.grid.roads.has(cell)
		last_revision = sim.grid.revision
	for building in sim.buildings.values():
		var node: Node3D = building_nodes.get(building.uid)
		if node != null and int(node.get_meta("tier")) != building.tier:
			node.queue_free()
			building_nodes.erase(building.uid)
			node = null
		if node == null:
			node = factory.building(building.definition,building.tier)
			node.set_meta("tier",building.tier)
			node.position = Vector3(building.cell.x+float(building.definition.footprint[0])/2.0,0,building.cell.y+float(building.definition.footprint[1])/2.0)
			buildings_root.add_child(node)
			building_nodes[building.uid] = node
		if node.has_node("Sails") and building.status == "working":
			node.get_node("Sails").rotation.z = float(sim.tick) * 0.035
	for carrier in sim.carriers:
		var node: Node3D = carrier_nodes.get(carrier.uid)
		if node == null:
			node = Node3D.new()
			factory.box(node,Vector3(0,0.20,0),Vector3(0.20,0.3,0.20),Color("416c80"))
			factory.box(node,Vector3(0,0.42,0),Vector3(0.17,0.16,0.17),Color("e1cea1"))
			var parcel := factory.box(node,Vector3(0,0.58,0),Vector3(0.25,0.22,0.25),Color.WHITE)
			parcel.name = "Parcel"
			carrier_root.add_child(node)
			carrier_nodes[carrier.uid] = node
		# Tick positions keep pixels stable; presentation does not influence travel.
		node.position = Vector3(carrier.cell.x+0.5,0.06,carrier.cell.y+0.5)
		node.visible = sim.grid.roads.has(carrier.cell)
		var parcel: MeshInstance3D = node.get_node("Parcel")
		parcel.visible = not carrier.cargo.is_empty()
		if parcel.visible and str(node.get_meta("cargo","")) != carrier.cargo:
			var arrays: Array = parcel.mesh.surface_get_arrays(0)
			var colors := PackedColorArray()
			colors.resize(arrays[Mesh.ARRAY_VERTEX].size())
			colors.fill(Color.html(sim.db.goods[carrier.cargo].color))
			arrays[Mesh.ARRAY_COLOR] = colors
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			parcel.mesh = mesh
			node.set_meta("cargo",carrier.cargo)
	for uid in carrier_nodes.keys():
		var found := false
		for carrier in sim.carriers:
			if carrier.uid == uid: found = true
		if not found:
			carrier_nodes[uid].queue_free()
			carrier_nodes.erase(uid)

func _update_ghost() -> void:
	var mouse := get_global_mouse_position()
	if tool.selected == "inspect" or hud.blocks_mouse(mouse) or not display.get_global_rect().has_point(mouse):
		ghost_root.visible = false
		return
	hover_cell = camera.cell_at((mouse-display.position)/integer_scale)
	var signature := "%s:%s:%s:%s" % [hover_cell,tool.selected,tool.road_start,sim.grid.revision]
	ghost_root.visible = true
	if signature == ghost_signature:
		return
	ghost_signature = signature
	_clear(ghost_root)
	var cells: Array[Vector2i] = [hover_cell]
	var color := Color("8db9bf")
	if tool.selected == "road":
		cells = tool.road_cells(hover_cell)
	elif sim.db.buildings.has(tool.selected):
		cells.clear()
		var row: Dictionary = sim.db.buildings[tool.selected]
		for y in int(row.footprint[1]):
			for x in int(row.footprint[0]):
				cells.append(hover_cell+Vector2i(x,y))
		color = Color("94a85e") if sim.placement_error(tool.selected,hover_cell).is_empty() else Color("ad6b50")
	elif tool.selected == "demolish":
		color = Color("ad6b50")
	for cell in cells:
		if not sim.grid.inside(cell): continue
		for edge in [Vector3(0,0,-0.47),Vector3(0,0,0.47)]:
			factory.box(ghost_root,Vector3(cell.x+0.5,0.09,cell.y+0.5)+edge,Vector3(0.98,0.055,0.045),color)
		for edge in [Vector3(-0.47,0,0),Vector3(0.47,0,0)]:
			factory.box(ghost_root,Vector3(cell.x+0.5,0.09,cell.y+0.5)+edge,Vector3(0.045,0.055,0.98),color)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_Q: camera.rotate_quarter(-1)
			KEY_E: camera.rotate_quarter(1)
			KEY_SPACE: speed = 1 if speed == 0 else 0
			KEY_ESCAPE:
				hud.close_build_menu()
				selected_uid = -1
				_select_tool("inspect")
			KEY_F2:
				pipeline_enabled = not pipeline_enabled
				palette_material.set_shader_parameter("enabled",pipeline_enabled)
				outline_material.set_shader_parameter("enabled",pipeline_enabled)
			KEY_F3:
				_toggle_deposits()
		ghost_signature = ""
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			hud.close_build_menu()
			selected_uid = -1
			_select_tool("inspect")
			return
		if hud.blocks_mouse(event.position) or not display.get_global_rect().has_point(event.position):
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom(1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_act(camera.cell_at((event.position-display.position)/integer_scale))
		ghost_signature = ""

func _select_tool(id: String) -> void:
	tool.choose(id)
	ghost_signature = ""
	if id != "inspect":
		hud.close_build_menu()
		selected_uid = -1
	hud.refresh(sim,selected_uid,tool.selected)

func _toggle_deposits() -> void:
	deposits_root.visible = not deposits_root.visible
	hud.set_deposits_visible(deposits_root.visible)

func _act(cell: Vector2i) -> void:
	if tool.selected == "inspect":
		selected_uid = int(sim.grid.occupied.get(cell,-1))
	elif tool.selected == "road":
		if tool.road_start.x < 0:
			tool.road_start = cell
		else:
			var ok: bool = sim.place_road(tool.road_cells(cell))
			if not ok: hud.show_error(sim.last_error)
			tool.road_start = Vector2i(-1,-1)
	elif tool.selected == "demolish":
		var ok: bool = sim.demolish(cell)
		if not ok: hud.show_error(sim.last_error)
	else:
		var ok: bool = sim.place(tool.selected,cell)
		if not ok: hud.show_error(sim.last_error)
	_sync_view()
	hud.refresh(sim,selected_uid,tool.selected)

func _complete_chain() -> void:
	# Check both footprints and total cost before either mutation.
	var reason: String = sim.placement_error("mill",Vector2i(16,18))
	if reason.is_empty(): reason = sim.placement_error("bakery",Vector2i(23,18))
	if reason.is_empty() and sim.stock("logs") < 16: reason = "Need 16 logs"
	if not reason.is_empty():
		hud.show_error(reason)
		return
	Scenario.complete_chain(sim)
	_sync_view()

func _clear(root: Node) -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()

func _render_smoke() -> void:
	speed = 0
	sim.step(300)
	_complete_chain()
	sim.step(500)
	_sync_view()
	hud.refresh(sim,selected_uid,tool.selected)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png("res://artifacts/render-smoke.png")
	print("RENDER SMOKE: %dx%d; integer scale %d; bread %d; screenshot %s" % [image.get_width(),image.get_height(),integer_scale,int(sim.produced.get("bread",0)),result])
	get_tree().quit(0 if result == OK else 1)
