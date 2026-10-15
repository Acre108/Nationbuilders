extends Control
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const MeshFactory = preload("res://view/mesh_factory.gd")
const CameraRig = preload("res://view/camera_rig.gd")
const BuildTool = preload("res://view/build_tool.gd")
const Building = preload("res://sim/building.gd")
const BUILDING_PREVIEW = preload("res://render/building_preview.gdshader")
const HUD = preload("res://view/overlays/village_hud.gd")
const VillageFoliage = preload("res://view/village_foliage.gd")
const VillageWildlife = preload("res://view/village_wildlife.gd")
const VillageAtmosphere = preload("res://view/village_atmosphere.gd")
const TerrainRelief = preload("res://view/terrain_relief.gd")
const GridChanges = preload("res://view/grid_changes.gd")
const Sites = preload("res://sim/world/sites.gd")
const WorldMapScene = preload("res://view/world_map/world_map_view.tscn")
signal campaign_map_requested
signal campaign_menu_requested
signal campaign_result_requested(outcome: String)
var campaign
@export var art_profile: Resource = preload("res://view/village_art.tres")
var foliage
## Deer and boar where the sim's herds live; see village_wildlife.gd.
var wildlife_layer
var atmosphere: AtmosphereSystem
## Hand-made site to play: --site=<name> on the command line, F4 to cycle.
var site_name := "first_bread"
## Opens the economy test village (Scenario.economy_test) instead of the starter.
var economy_village := false
var framed_site := ""
var relief
## The world map while it is open over this village; null otherwise.
var world_map_view
var weather_focus: Node3D
var sim
var factory: MeshFactory
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
## Class overlay markers (F5): houses by alignment, roads in a hall's reach.
var class_root: Node3D
var class_signature := ""
var carrier_root: Node3D
var scenery_root: Node3D
var building_nodes: Dictionary = {}
var carrier_nodes: Dictionary = {}
var last_revision := -1
var last_forest_revision := -1
var deposit_nodes: Dictionary = {}
## Road tiles and deposit markers are updated only where the grid changed.
var road_nodes: Dictionary = {}
var road_changes := GridChanges.new()
var deposit_changes := GridChanges.new()
var deposit_meshes: Dictionary = {}
var selected_uid := -1
var hover_cell := Vector2i(-1,-1)
var pointer_position := Vector2(-1,-1)
var accumulator := 0.0
var speed := 1
var hud_elapsed := 0.0
var ghost_signature := ""
var autosave_elapsed := 0.0
var charter_offer_dismissed := false
var card_previous_speed := 1

func _ready() -> void:
	# Weather controls change wind fields; each scene keeps its authored base.
	art_profile = art_profile.duplicate()
	factory = MeshFactory.new(art_profile)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pixel_viewport = preload("res://render/pixel_viewport.tscn").instantiate()
	add_child(pixel_viewport)
	# The world renders smooth at full display resolution with antialiasing.
	pixel_viewport.msaa_3d = Viewport.MSAA_4X
	world = pixel_viewport.get_node("World")
	display = TextureRect.new()
	display.texture = pixel_viewport.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	camera = CameraRig.new()
	world.add_child(camera)
	var light := DirectionalLight3D.new()
	LightingSettings.configure_sun(light)
	light.directional_shadow_max_distance = 80
	world.add_child(light)
	var environment := WorldEnvironment.new()
	var settings := LightingSettings.make_daylight_environment()
	environment.environment = settings
	world.add_child(environment)
	foliage = VillageFoliage.new(art_profile)
	world.add_child(foliage)
	wildlife_layer = VillageWildlife.new(factory.medieval)
	world.add_child(wildlife_layer)
	weather_focus = Node3D.new()
	weather_focus.position = camera.focus
	world.add_child(weather_focus)
	atmosphere = VillageAtmosphere.new()
	atmosphere.art = art_profile
	atmosphere.profile = AtmosphereProfile.new()
	atmosphere.profile.time_of_day = 16.0
	atmosphere.profile.rain_radius = 30.0
	atmosphere.profile.mist_haze_distance = 70.0
	atmosphere.foliage_profile = foliage.profile
	atmosphere.sun = light
	atmosphere.world_environment = environment
	atmosphere.weather_focus = weather_focus
	world.add_child(atmosphere)
	foliage.wind_source = atmosphere
	for kind in ["buildings","roads","ghost","deposits","classes","carriers","scenery"]:
		var node := Node3D.new()
		node.name = kind
		world.add_child(node)
		match kind:
			"buildings": buildings_root = node
			"roads": roads_root = node
			"ghost": ghost_root = node
			"deposits": deposits_root = node
			"classes": class_root = node
			"carriers": carrier_root = node
			"scenery": scenery_root = node
	hud = HUD.new()
	add_child(hud)
	hud.tool_selected.connect(_select_tool)
	hud.rotation_requested.connect(_rotate_building)
	hud.deposits_toggled.connect(_toggle_deposits)
	hud.speed_selected.connect(_set_speed)
	hud.restart_requested.connect(_restart)
	hud.campaign_save_requested.connect(_save_campaign)
	hud.campaign_menu_requested.connect(func(): campaign_menu_requested.emit())
	hud.campaign_abandon_requested.connect(func(): _show_run_card("abandoned"))
	hud.campaign_charter_requested.connect(func(): _show_run_card("charter"))
	hud.site_overview_requested.connect(_overview_site)
	hud.run_choice_selected.connect(_run_choice)
	hud.set_campaign_controls(campaign != null)
	hud.weather_selected.connect(func(kind,intensity): atmosphere.set_weather(kind,intensity))
	hud.time_of_day_selected.connect(atmosphere.set_time_of_day)
	hud.clock_toggled.connect(func(running): atmosphere.profile.day_length_minutes = 2.0 if running else 0.0)
	hud.fade_selected.connect(func(seconds): atmosphere.profile.weather_transition_seconds = seconds)
	hud.wind_selected.connect(atmosphere.set_wind)
	hud.weather_action.connect(_weather_action)
	hud.world_map_requested.connect(open_world_map)
	hud.workers_toggled.connect(_toggle_workers)
	hud.priority_selected.connect(func(level): _panel_command(sim.set_priority(selected_uid, level)))
	hud.tax_selected.connect(func(percent): _panel_command(sim.set_tax_percent(percent)))
	hud.markup_selected.connect(func(percent): _panel_command(sim.set_markup_percent(percent)))
	hud.reserve_target_toggled.connect(func(enabled): _panel_command(sim.set_keep_service_reserve(enabled)))
	hud.reserve_transfer_requested.connect(func(pot,amount): _panel_command(sim.transfer_reserve(pot,amount)))
	hud.offer_accepted.connect(func(id): _panel_command(sim.accept_offer(id)))
	hud.offer_declined.connect(func(id): _panel_command(sim.decline_offer(id)))
	hud.pledge_broken.connect(func(id): _panel_command(sim.break_pledge(id)))
	hud.sale_requested.connect(func(id): _panel_command(sim.sell_building(selected_uid,id)))
	hud.class_overlay_toggled.connect(_toggle_class_overlay)
	hud.inspection_closed.connect(func():
		selected_uid = -1
		hud.refresh(sim,selected_uid,tool.selected,tool.rotation_quarters)
	)
	resized.connect(_resize_display)
	_resize_display()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--site=") and argument.trim_prefix("--site=") in Sites.NAMES:
			site_name = argument.trim_prefix("--site=")
		elif argument == "--scenario=economy":
			economy_village = true
	if campaign != null:
		sim = campaign.village
		_refresh_village()
		_restore_campaign_view_state()
	else:
		_restart()
	# Render smoke uses the same running scene and public commands.
	if "--render-smoke" in OS.get_cmdline_user_args():
		_render_smoke.call_deferred()

func _resize_display() -> void:
	# Render at the window's own resolution inside a 16:9 frame, letterboxed on
	# wider/taller windows so the framing stays the same.
	var fit := minf(size.x/640.0,size.y/360.0)
	pixel_viewport.size = Vector2i((Vector2(640,360)*fit).floor()).max(Vector2i.ONE)
	display.size = Vector2(pixel_viewport.size)
	display.position = ((size-display.size)/2.0).floor()
	ghost_signature = ""
	if camera != null: camera.refresh()

## The world is shown 1:1, so only the letterbox offset separates the two.
func _display_to_viewport(point: Vector2) -> Vector2:
	return point-display.position

func _restart() -> void:
	if campaign != null: return
	# The milestone 1 map is generated by the sim itself, from its seed.
	sim = Sim.new(73) if site_name == "first_bread" else Sim.new(73, null, Sites.named(site_name, null))
	# The economy test village is laid out for the milestone 1 map.
	var built: bool = Scenario.economy_test(sim, "--halls" in OS.get_cmdline_user_args()) if economy_village and site_name == "first_bread" else Scenario.starter(sim)
	if not sim.valid or not built:
		push_error("Starter failed: " + sim.last_error)
		get_tree().quit(1)
		return
	_refresh_village()

func _refresh_village() -> void:
	for root in [buildings_root,roads_root,carrier_root,scenery_root,deposits_root,class_root,ghost_root]:
		_clear(root)
	building_nodes.clear()
	carrier_nodes.clear()
	road_nodes.clear()
	road_changes = GridChanges.new()
	selected_uid = -1
	factory.terrain(scenery_root,sim.grid)
	relief = TerrainRelief.new(sim.grid)
	relief.apply(factory)
	_frame_site()
	foliage.build(sim.grid)
	wildlife_layer.build(sim.grid,relief)
	atmosphere.reset_art_motion()
	atmosphere.set_time_of_day(16.0)
	atmosphere.set_weather(AtmosphereProfile.Weather.CLEAR,0.0,true)
	atmosphere.profile.day_length_minutes = 0.0
	atmosphere.wetness = 0.0
	atmosphere.grid = sim.grid
	atmosphere.profile.weather_transition_seconds = 8.0
	atmosphere.reset_wind()
	_build_scenery()
	last_revision = -1
	class_root.visible = false
	class_signature = ""
	last_forest_revision = sim.grid.forest_revision
	accumulator = 0
	speed = 1
	tool.choose("inspect")
	ghost_signature = ""
	_sync_view()
	hud.configure_build_menu(sim.db)
	hud.reset()
	hud.set_speed(speed)
	_sync_weather_hud()
	hud.refresh(sim,selected_uid,tool.selected)

func _sync_weather_hud() -> void:
	hud.set_weather(atmosphere.get_target_weather(),atmosphere.get_target_amount())
	hud.set_time_of_day(atmosphere.get_time_of_day(),atmosphere.profile.day_length_minutes > 0.0)
	hud.set_wind(atmosphere.wind_from_degrees(),atmosphere.wind_breeze(),atmosphere.wind_gust_speed(),atmosphere.profile.weather_transition_seconds)
	hud.set_weather_stats(atmosphere.weather_report())

func _weather_action(id: String) -> void:
	match id:
		"strike": atmosphere.lightning.strike()
		"soak": atmosphere.wetness = 1.0
		"dry": atmosphere.wetness = 0.0
	_sync_weather_hud()

func _build_scenery() -> void:
	deposit_nodes.clear()
	deposit_changes = GridChanges.new()
	_sync_deposits()
	deposits_root.visible = false

func _sync_deposits() -> void:
	var cells := deposit_changes.update(sim.grid)
	if deposit_changes.reset:
		cells.clear()
		for y in sim.grid.height:
			for x in sim.grid.width:
				cells.append(Vector2i(x,y))
	for cell in cells:
		var at := Vector3(cell.x+0.5,relief.cell_height(cell),cell.y+0.5)
		var deposit: String = sim.grid.deposits[cell.y*sim.grid.width+cell.x]
		if deposit.is_empty() and deposit_nodes.has(cell):
			var removed: Node3D = deposit_nodes[cell]
			deposits_root.remove_child(removed)
			removed.queue_free()
			deposit_nodes.erase(cell)
		elif not deposit.is_empty() and not deposit_nodes.has(cell):
			var deposit_color := Color("d6c288") if deposit == "fertile_soil" else Color("3a93a1")
			if not deposit_meshes.has(deposit_color):
				var temporary := Node3D.new()
				deposit_meshes[deposit_color] = factory.box(temporary,Vector3.ZERO,Vector3(0.85,0.035,0.85),deposit_color).mesh
				temporary.free()
			var marker := MeshInstance3D.new()
			marker.mesh = deposit_meshes[deposit_color]
			marker.material_override = factory.material
			marker.position = at+Vector3.UP*0.025
			deposits_root.add_child(marker)
			deposit_nodes[cell] = marker

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
	if pan != Vector2.ZERO and not hud.options_menu.visible and not hud.run_card.visible:
		camera.pan(pan.normalized(),delta)
	weather_focus.position = camera.focus
	foliage.set_far_trees(camera.zoom_size >= foliage.FAR_TREE_ZOOM)
	_sync_view()
	_update_ghost()
	hud_elapsed += delta
	if hud_elapsed >= 0.15:
		hud_elapsed = 0
		hud.refresh(sim,selected_uid,tool.selected,tool.rotation_quarters)
		_sync_class_overlay()
		if hud.weather_menu.visible:
			_sync_weather_hud()
		if campaign != null:
			hud.campaign_charter_button.disabled = not campaign.charter_available()
			if not hud.run_card.visible:
				if campaign.population() == 0: _show_run_card("ruin")
				elif campaign.charter_available() and not charter_offer_dismissed: _show_run_card("charter")
	if campaign != null:
		autosave_elapsed += delta
		if autosave_elapsed >= 120.0:
			autosave_elapsed = 0.0
			_save_campaign()

func _sync_view() -> void:
	var forest_changed: bool = last_forest_revision != sim.grid.forest_revision
	if last_revision != sim.grid.revision:
		_sync_roads()
		for uid in building_nodes.keys():
			if not sim.buildings.has(uid):
				building_nodes[uid].queue_free()
				building_nodes.erase(uid)
		foliage.sync_grid(sim.grid)
		factory.sync_ground_context(sim.grid)
		last_revision = sim.grid.revision
	elif forest_changed:
		foliage.sync_grid(sim.grid)
	if forest_changed:
		factory.sync_forest_ground(sim.grid)
		_sync_deposits()
		last_forest_revision = sim.grid.forest_revision
		ghost_signature = ""
	foliage.sync_growth(sim.grid,sim.tick)
	wildlife_layer.sync(sim.wildlife)
	for building in sim.buildings.values():
		var node: Node3D = building_nodes.get(building.uid)
		if node != null and int(node.get_meta("tier")) != building.tier:
			node.queue_free()
			building_nodes.erase(building.uid)
			node = null
		if node == null:
			node = factory.building(building.definition,building.tier)
			node.set_meta("tier",building.tier)
			var footprint: Vector2i = building.footprint()
			node.position = Vector3(building.cell.x+float(footprint.x)/2.0,relief.cell_height(building.cell),building.cell.y+float(footprint.y)/2.0)
			node.rotation.y = building.rotation_quarters * PI / 2.0
			buildings_root.add_child(node)
			building_nodes[building.uid] = node
		factory.medieval.sync_stock(node, building)
		if node.has_node("Sails") and building.status == "working":
			node.get_node("Sails").rotation.z = float(sim.tick) * 0.035
	for carrier in sim.carriers:
		var node: Node3D = carrier_nodes.get(carrier.uid)
		if node == null:
			node = Node3D.new()
			factory.box(node,Vector3(0,0.20,0),Vector3(0.20,0.3,0.20),Color("4b5057"))
			factory.box(node,Vector3(0,0.42,0),Vector3(0.17,0.16,0.17),Color("d8cdb4"))
			var parcel := factory.box(node,Vector3(0,0.58,0),Vector3(0.25,0.22,0.25),Color.WHITE)
			parcel.name = "Parcel"
			carrier_root.add_child(node)
			carrier_nodes[carrier.uid] = node
		# Carriers sit on their tick cell; presentation does not influence travel.
		node.position = Vector3(carrier.cell.x+0.5,0.06+relief.cell_height(carrier.cell),carrier.cell.y+0.5)
		node.visible = sim.grid.roads.has(carrier.cell)
		var parcel: MeshInstance3D = node.get_node("Parcel")
		parcel.visible = not carrier.cargo.is_empty()
		if parcel.visible and str(node.get_meta("cargo","")) != carrier.cargo:
			var arrays: Array = parcel.mesh.surface_get_arrays(0)
			var colors := PackedColorArray()
			colors.resize(arrays[Mesh.ARRAY_VERTEX].size())
			colors.fill(Color.html(sim.db.goods[carrier.cargo].color).srgb_to_linear())
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

## A road tile's verge depends on its neighbours, so a change rebuilds them too.
func _sync_roads() -> void:
	var changed := road_changes.update(sim.grid)
	var cells: Array[Vector2i] = []
	if road_changes.reset:
		_clear(roads_root)
		road_nodes.clear()
		cells.assign(sim.grid.roads.keys())
	else:
		cells = GridChanges.around(changed,1,sim.grid)
	for cell in cells:
		if road_nodes.has(cell):
			roads_root.remove_child(road_nodes[cell])
			road_nodes[cell].queue_free()
			road_nodes.erase(cell)
		if not sim.grid.roads.has(cell): continue
		# One holder per tile so a road on a ramp can tilt with it.
		var tile := Node3D.new()
		roads_root.add_child(tile)
		factory.road(tile,cell,sim.grid)
		relief.seat(tile,cell)
		road_nodes[cell] = tile
	# The approach visibly continues beyond the playable western boundary.
	var approach := roads_root.get_node_or_null("Approach")
	var show_approach: bool = not sim.site.footprint.has(0) and not sim.site.entrance_road.is_empty() and sim.grid.roads.has(sim.site.entrance_road[0])
	if approach == null and show_approach:
		approach = Node3D.new()
		approach.name = "Approach"
		roads_root.add_child(approach)
		for x in range(-4,0):
			factory.road(approach,Vector2i(x,sim.site.entrance_road[0].y),sim.grid)
	elif approach != null and not show_approach:
		roads_root.remove_child(approach)
		approach.queue_free()

func _update_ghost() -> void:
	var mouse := pointer_position
	if tool.selected == "inspect" or hud.blocks_mouse(mouse) or not display.get_global_rect().has_point(mouse):
		ghost_root.visible = false
		return
	hover_cell = _cell_at(_display_to_viewport(mouse))
	var signature := "%s:%s:%s:%s:%s" % [hover_cell,tool.selected,tool.road_start,tool.rotation_quarters,sim.grid.revision]
	ghost_root.visible = true
	if signature == ghost_signature:
		return
	ghost_signature = signature
	_clear(ghost_root)
	var cells: Array[Vector2i] = [hover_cell]
	var color := Color("3a93a1")
	if tool.selected == "road":
		cells = tool.road_cells(hover_cell)
	elif sim.db.buildings.has(tool.selected):
		cells.clear()
		var row: Dictionary = sim.db.buildings[tool.selected]
		var footprint := Building.rotated_footprint(row, tool.rotation_quarters)
		for y in footprint.y:
			for x in footprint.x:
				cells.append(hover_cell+Vector2i(x,y))
		color = Color("a8c46b") if sim.placement_error(tool.selected,hover_cell,tool.rotation_quarters).is_empty() else Color("9a5440")
		var preview := factory.building(row, 1)
		preview.name = "Preview"
		preview.position = Vector3(hover_cell.x+float(footprint.x)/2.0,relief.cell_height(hover_cell),hover_cell.y+float(footprint.y)/2.0)
		preview.rotation.y = tool.rotation_quarters * PI / 2.0
		var preview_material := ShaderMaterial.new()
		preview_material.shader = BUILDING_PREVIEW
		preview_material.set_shader_parameter("tint", color)
		_apply_preview_material(preview, preview_material)
		ghost_root.add_child(preview)
	elif tool.selected == "demolish":
		color = Color("9a5440")
	for cell in cells:
		if not sim.grid.inside(cell): continue
		for edge in [Vector3(0,0,-0.47),Vector3(0,0,0.47)]:
			factory.box(ghost_root,Vector3(cell.x+0.5,0.09+relief.cell_height(cell),cell.y+0.5)+edge,Vector3(0.98,0.055,0.045),color)
		for edge in [Vector3(-0.47,0,0),Vector3(0.47,0,0)]:
			factory.box(ghost_root,Vector3(cell.x+0.5,0.09+relief.cell_height(cell),cell.y+0.5)+edge,Vector3(0.045,0.055,0.98),color)

func _input(event: InputEvent) -> void:
	# Read the same viewport coordinates used by placement clicks, including
	# input sent through the viewport during tests.
	if event is InputEventMouse: pointer_position = event.position

func _unhandled_input(event: InputEvent) -> void:
	if hud.run_card.visible:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and hud.run_card_kind != "ruin": _run_choice("keep")
		get_viewport().set_input_as_handled()
		return
	if hud.options_menu.visible:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			hud.close_options_menu()
		elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_HOME:
			hud.close_options_menu()
			_overview_site()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if atmosphere.handle_debug_key(event.physical_keycode):
			return
		match event.physical_keycode:
			KEY_Q: camera.rotate_quarter(-1)
			KEY_E: camera.rotate_quarter(1)
			KEY_R: _rotate_building()
			KEY_SPACE: _set_speed(1 if speed == 0 else 0)
			KEY_ESCAPE:
				hud.close_build_menu()
				hud.close_weather_menu()
				hud.close_treasury_menu()
				hud.close_factions_menu()
				selected_uid = -1
				_select_tool("inspect")
			KEY_F3:
				_toggle_deposits()
			KEY_F5:
				_toggle_class_overlay()
			KEY_F4:
				_cycle_site()
			KEY_HOME: _overview_site()
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
			_act(_cell_at(_display_to_viewport(event.position)))
		ghost_signature = ""

func _select_tool(id: String) -> void:
	tool.choose(id)
	ghost_signature = ""
	if id != "inspect":
		hud.close_build_menu()
		selected_uid = -1
	hud.refresh(sim,selected_uid,tool.selected,tool.rotation_quarters)

func _rotate_building() -> void:
	if not sim.db.buildings.has(tool.selected) or tool.selected == "road": return
	if hud.options_menu.visible or hud.weather_menu.visible or hud.build_menu.visible: return
	tool.rotate()
	ghost_signature = ""
	_update_ghost()
	hud.refresh(sim,selected_uid,tool.selected,tool.rotation_quarters)

func _apply_preview_material(node: Node, preview_material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = preview_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): _apply_preview_material(child, preview_material)

## HUD panel commands (tax, markup, reserves, priority) go through the sim's public API.
func _panel_command(ok: bool) -> void:
	if not ok: hud.show_error(sim.last_error)
	hud.refresh(sim,selected_uid,tool.selected,tool.rotation_quarters)

func _toggle_deposits() -> void:
	deposits_root.visible = not deposits_root.visible
	hud.set_deposits_visible(deposits_root.visible)

func _toggle_class_overlay() -> void:
	class_root.visible = not class_root.visible
	hud.set_class_overlay_visible(class_root.visible)
	class_signature = ""
	_sync_class_overlay()

## Working-class houses wear their faction's colour (grey while unaligned) as
## a ground plate and a marker above the roof; Settlers have no class and no
## marker. Each hall tints the road tiles within its reach, the same road
## distance its pull uses. Rebuilt only when houses, halls or roads change.
func _sync_class_overlay() -> void:
	if not class_root.visible:
		return
	var parts: Array = [sim.grid.revision]
	for building in sim.buildings.values():
		if building.definition.kind in ["house","hall"]:
			parts.append([building.uid,building.tier,building.aligned])
	var signature := str(parts)
	if signature == class_signature:
		return
	class_signature = signature
	_clear(class_root)
	var faction_ids: Array = sim.db.factions.keys()
	for building in sim.buildings.values():
		var row: Dictionary = building.definition
		var footprint: Vector2i = building.footprint()
		var centre := Vector3(building.cell.x+float(footprint.x)/2.0,relief.cell_height(building.cell),building.cell.y+float(footprint.y)/2.0)
		if row.kind == "house":
			if str(sim.db.tiers[building.tier].get("class","")).is_empty():
				continue
			var colour := Color(hud.UNALIGNED_COLOUR) if building.aligned.is_empty() else Color.html(sim.db.factions[building.aligned].colour)
			factory.box(class_root,centre+Vector3(0,0.04,0),Vector3(footprint.x+0.3,0.05,footprint.y+0.3),colour)
			factory.box(class_root,centre+Vector3(0,2.9,0),Vector3(0.45,0.45,0.45),colour)
		elif row.kind == "hall":
			var colour := Color.html(sim.db.factions[row.recruits_for].colour)
			factory.box(class_root,centre+Vector3(0,0.04,0),Vector3(footprint.x+0.3,0.05,footprint.y+0.3),colour)
			# Nested squares, so two factions' reach on one tile both show.
			var order: int = faction_ids.find(row.recruits_for) % 2
			var steps: Dictionary = sim.grid.road_steps(building)
			for cell in steps:
				if int(steps[cell]) + 1 <= int(row.radius):
					factory.box(class_root,Vector3(cell.x+0.5,relief.cell_height(cell)+0.07+order*0.02,cell.y+0.5),Vector3(0.8-order*0.35,0.03,0.8-order*0.35),colour)

func _set_speed(value: int) -> void:
	speed = value
	hud.set_speed(value)

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
		var ok: bool = sim.place(tool.selected,cell,tool.rotation_quarters)
		if not ok: hud.show_error(sim.last_error)
	_sync_view()
	hud.refresh(sim,selected_uid,tool.selected,tool.rotation_quarters)

func _complete_chain() -> void:
	# Check every footprint and the total cost before any mutation.
	var reason := ""
	var logs := 0
	for entry in Scenario.CHAIN:
		if reason.is_empty(): reason = sim.placement_error(entry[0],entry[1]+Scenario.offset(sim))
		logs += int(sim.db.buildings[entry[0]].cost.get("logs",0))
	if reason.is_empty() and sim.stock("logs") < logs: reason = "Need %d logs" % logs
	if not reason.is_empty():
		hud.show_error(reason)
		return
	Scenario.complete_chain(sim)
	_sync_view()

func _cell_at(pixel: Vector2) -> Vector2i:
	return camera.cell_at(pixel,relief.surface_height,relief.top)

## Pan limits follow the site; a newly shown site is framed on its founding spot.
func _frame_site() -> void:
	camera.bounds = Rect2(4.0,4.0,sim.grid.width-9.0,sim.grid.height-9.0)
	if sim.site.footprint.has(0): camera.zoom_max = maxf(48.0, maxf(sim.grid.width, sim.grid.height) * 1.15)
	if framed_site != sim.site.name:
		framed_site = sim.site.name
		camera.focus = Vector3(sim.site.founding_spot.x+5,0,sim.site.founding_spot.y-3)
		if sim.site.footprint.has(0): camera.focus.y = relief.cell_height(sim.site.founding_spot)
		camera.refresh()

func _overview_site() -> void:
	camera.focus = Vector3(sim.grid.width * 0.5, 0, sim.grid.height * 0.5)
	if sim.site.footprint.has(0): camera.focus.y = relief.top * 0.35
	camera.zoom_size = camera.zoom_max
	camera.refresh()

func _cycle_site() -> void:
	if campaign != null: return
	site_name = Sites.NAMES[(Sites.NAMES.find(site_name)+1)%Sites.NAMES.size()]
	_restart()

## Shows the world map in place of the village. The village stays loaded but
## hidden, paused and not rendering, and comes back exactly as it was.
func _save_campaign() -> void:
	if campaign != null:
		capture_campaign_view_state()
		hud.show_error("Campaign saved." if campaign.save() else campaign.last_error)

func capture_campaign_view_state() -> void:
	if campaign == null: return
	campaign.village_view_state = {
		"village_id": campaign.active_village, "focus": camera.focus,
		"quarter_turn": camera.quarter_turn, "zoom_size": camera.zoom_size,
		"speed": card_previous_speed if hud.run_card.visible else speed,
		"deposits": deposits_root.visible,
		"charter_offer_dismissed": charter_offer_dismissed,
		"time_of_day": atmosphere.get_time_of_day(), "clock": atmosphere.profile.day_length_minutes,
		"weather": int(atmosphere.get_target_weather()), "amount": atmosphere.get_target_amount(),
		"wind_from": atmosphere.wind_from_degrees(), "breeze": atmosphere.wind_breeze(),
		"gust_speed": atmosphere.wind_gust_speed(), "fade": atmosphere.profile.weather_transition_seconds,
		"wetness": atmosphere.wetness
	}

func _restore_campaign_view_state() -> void:
	var state: Dictionary = campaign.village_view_state
	if state.is_empty() or state.get("village_id", "") != campaign.active_village: return
	camera.focus = state.get("focus", camera.focus)
	camera.quarter_turn = state.get("quarter_turn", 0)
	camera.zoom_size = state.get("zoom_size", 22.0)
	camera.refresh()
	_set_speed(state.get("speed", 1))
	deposits_root.visible = state.get("deposits", false)
	hud.set_deposits_visible(deposits_root.visible)
	charter_offer_dismissed = state.get("charter_offer_dismissed", false)
	atmosphere.set_time_of_day(state.get("time_of_day", 16.0))
	atmosphere.profile.day_length_minutes = state.get("clock", 0.0)
	atmosphere.set_weather(state.get("weather", AtmosphereProfile.Weather.CLEAR), state.get("amount", 0.0), true)
	atmosphere.profile.weather_transition_seconds = state.get("fade", 8.0)
	atmosphere.set_wind(state.get("wind_from", 0.0), state.get("breeze", 1.0), state.get("gust_speed", 1.0))
	atmosphere.wetness = state.get("wetness", 0.0)
	_sync_weather_hud()

func _show_run_card(kind: String) -> void:
	if campaign == null or hud.run_card.visible: return
	if kind == "charter" and not campaign.charter_available(): return
	card_previous_speed = speed
	_set_speed(0)
	hud.show_run_card(kind, campaign.village_name, sim.unlocked_tier, campaign.population(), sim.tick)

func _run_choice(choice: String) -> void:
	if choice == "keep":
		if hud.run_card_kind == "charter": charter_offer_dismissed = true
		hud.close_run_card()
		_set_speed(card_previous_speed)
	else:
		campaign_result_requested.emit(choice)

func open_world_map() -> void:
	if campaign != null:
		campaign_map_requested.emit()
		return
	if world_map_view != null:
		return
	world_map_view = WorldMapScene.instantiate()
	world_map_view.show_back = true
	world_map_view.back_requested.connect(close_world_map)
	get_parent().add_child(world_map_view)
	# The HUD is a CanvasLayer, so it does not inherit visibility from this control.
	visible = false
	hud.visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	pixel_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func close_world_map() -> void:
	if world_map_view == null:
		return
	world_map_view.queue_free()
	world_map_view = null
	visible = true
	hud.visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	pixel_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

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
	print("RENDER SMOKE: %dx%d; bread %d; screenshot %s" % [image.get_width(),image.get_height(),int(sim.produced.get("bread",0)),result])
	get_tree().quit(0 if result == OK else 1)

func _toggle_workers() -> void:
	var building = sim.buildings.get(selected_uid)
	if building != null and not sim.set_workers_enabled(selected_uid, not building.workers_enabled):
		hud.show_error(sim.last_error)
	hud.refresh(sim,selected_uid,tool.selected,tool.rotation_quarters)
