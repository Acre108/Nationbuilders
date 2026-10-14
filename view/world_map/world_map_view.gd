extends Control
## The world map (docs/PLAN-world-map.md phase A2): a generated world drawn with
## the village's camera, lighting and sky, rendered smooth at full resolution. Hover a hex to see
## what it offers. The campaign menu supplies founding and resume controls.
##   godot --path . view/world_map/world_map_view.tscn -- --seed=73 [--screenshot]
const WorldGen = preload("res://sim/world/world_gen.gd")
const WorldData = preload("res://sim/world/world_data.gd")
const HexMath = preload("res://sim/world/hex_math.gd")
const WorldMapMesh = preload("res://view/world_map/world_map_mesh.gd")
const MeshFactory = preload("res://view/mesh_factory.gd")
const CameraRig = preload("res://view/camera_rig.gd")
const VillageAtmosphere = preload("res://view/village_atmosphere.gd")
const NO_HEX := Vector2i(999999, 999999)
const ELEVATIONS: Array[String] = ["Lowland", "Rolling", "Hills", "Highland", "Peaks"]
const RIVERS: Array[String] = ["", "a stream", "a river", "a great river"]
## Emitted by "Back to village" (or Esc) when opened from a village.
signal back_requested
signal hex_selected(coord: Vector2i)
var provided_world
var provided_campaign
var campaign_overlays: Node3D
var reach_overlay: Node3D
var show_settleability := false
var campaign_mode := false
var selected_hex := NO_HEX
var selection_marker: MeshInstance3D
@export var art_profile: Resource = preload("res://view/village_art.tres")
@export var map_art: Resource = preload("res://view/world_map/world_map_art.tres")
## Set before the node enters the tree when a village opened the map.
var show_back := false
## Set before the node enters the tree to choose the first world.
var seed_value := 73
var reveal_all := false
var data
var world
var model: WorldMapMesh
var factory: MeshFactory
var pixel_viewport: SubViewport
var display: TextureRect
var world_root: Node3D
var model_root: Node3D
var camera
var atmosphere
var weather_focus: Node3D
var hover_marker: MeshInstance3D
var hovered := NO_HEX
## Last mouse position from motion events, in window coordinates.
var mouse_position := Vector2(-1, -1)
var panel: PanelContainer
var panel_text: RichTextLabel
var hint: Label
var back_button: Button

func _ready() -> void:
	art_profile = art_profile.duplicate()
	map_art = map_art.duplicate()
	if "--unlinked" in OS.get_cmdline_user_args(): map_art.linked_tiles = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	factory = MeshFactory.new(art_profile)
	data = WorldData.new()
	if not data.load_directory():
		push_error("World data failed: " + "; ".join(data.errors))
		get_tree().quit(1)
		return
	pixel_viewport = preload("res://render/pixel_viewport.tscn").instantiate()
	add_child(pixel_viewport)
	world_root = pixel_viewport.get_node("World")
	display = TextureRect.new()
	display.texture = pixel_viewport.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pixel_viewport.msaa_3d = Viewport.MSAA_4X
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	camera = CameraRig.new()
	world_root.add_child(camera)
	var light := DirectionalLight3D.new()
	LightingSettings.configure_sun(light)
	light.directional_shadow_max_distance = 120
	world_root.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = LightingSettings.make_daylight_environment()
	world_root.add_child(environment)
	weather_focus = Node3D.new()
	world_root.add_child(weather_focus)
	atmosphere = VillageAtmosphere.new()
	atmosphere.art = art_profile
	atmosphere.profile = AtmosphereProfile.new()
	atmosphere.profile.time_of_day = 16.0
	atmosphere.foliage_profile = FoliageProfile.new()
	atmosphere.sun = light
	atmosphere.world_environment = environment
	atmosphere.weather_focus = weather_focus
	world_root.add_child(atmosphere)
	hover_marker = MeshInstance3D.new()
	hover_marker.name = "Hover"
	hover_marker.mesh = _ring_mesh()
	hover_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hover_marker.visible = false
	world_root.add_child(hover_marker)
	_build_overlay()
	resized.connect(_resize_display)
	_resize_display()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			seed_value = int(argument.trim_prefix("--seed="))
	if provided_world != null:
		set_world(provided_world)
	else:
		set_seed(seed_value)
	atmosphere.set_weather(AtmosphereProfile.Weather.CLEAR, 0.0, true)
	if "--screenshot" in OS.get_cmdline_user_args():
		_screenshot.call_deferred()

## Generates and draws the world for a seed, framing the whole map.
func set_seed(value: int) -> void:
	set_world(WorldGen.generate(value, data))

func set_world(value) -> void:
	world = value
	data = world.data
	seed_value = world.seed_value
	if model_root != null:
		world_root.remove_child(model_root)
		model_root.queue_free()
	model = WorldMapMesh.new(world, factory.material, art_profile.water_turquoise, map_art, art_profile)
	model_root = model.build()
	world_root.add_child(model_root)
	_refresh_campaign_overlays()
	_refresh_blocked_overlay()
	var area: Rect2 = model.bounds()
	camera.bounds = area
	camera.focus = Vector3(area.get_center().x, 0.0, area.get_center().y)
	camera.zoom_size = 28.0
	camera.refresh()
	model.set_motion_scale(camera.zoom_size)
	weather_focus.position = camera.focus
	_set_hover(NO_HEX)
	hint.text = "Seed %d   ·   N / Shift+N: next / previous seed   ·   V: reveal deposits   ·   WASD, Q/E, wheel: camera" % seed_value
	if show_back: hint.text += "   ·   Esc: back to village"
	if campaign_mode:
		hint.text = "Seed %d   ·   Click a hex to choose your village site   ·   WASD, Q/E, wheel: camera" % seed_value
	hint.text += "   ·   L: linked scenes %s" % ("on" if map_art.linked_tiles else "off")
	if selected_hex != NO_HEX and world.has(selected_hex): select_hex(selected_hex)

func center_on(coord: Vector2i) -> void:
	if not world.has(coord): return
	camera.focus = WorldMapMesh.centre(coord)
	camera.refresh()
	weather_focus.position = camera.focus
	select_hex(coord)

func capture_view_state() -> Dictionary:
	return {"focus":camera.focus, "zoom_size":camera.zoom_size, "quarter_turn":camera.quarter_turn,
		"selected_hex":selected_hex, "reveal_all":reveal_all, "linked_tiles":map_art.linked_tiles,
		"show_settleability":show_settleability, "time_of_day":atmosphere.get_time_of_day(),
		"clock":atmosphere.profile.day_length_minutes, "weather":int(atmosphere.get_target_weather()),
		"amount":atmosphere.get_target_amount(), "wind_from":atmosphere.wind_from_degrees(),
		"breeze":atmosphere.wind_breeze(), "gust_speed":atmosphere.wind_gust_speed(),
		"fade":atmosphere.profile.weather_transition_seconds, "wetness":atmosphere.wetness}

func restore_view_state(state: Dictionary) -> void:
	if typeof(state.get("linked_tiles")) == TYPE_BOOL and state.linked_tiles != map_art.linked_tiles:
		map_art.linked_tiles = state.linked_tiles
		set_world(world)
	if state.get("focus") is Vector3 and state.focus.is_finite():
		camera.focus = state.focus
		camera.focus.x = clampf(camera.focus.x, camera.bounds.position.x, camera.bounds.end.x)
		camera.focus.z = clampf(camera.focus.z, camera.bounds.position.y, camera.bounds.end.y)
	if state.get("zoom_size") is float or state.get("zoom_size") is int:
		camera.zoom_size = clampf(float(state.zoom_size), 8.0, 48.0)
	if state.get("quarter_turn") is int: camera.quarter_turn = posmod(state.quarter_turn, 4)
	if typeof(state.get("reveal_all")) == TYPE_BOOL: reveal_all = state.reveal_all
	if typeof(state.get("show_settleability")) == TYPE_BOOL: show_settleability = state.show_settleability
	if state.get("time_of_day") is float: atmosphere.set_time_of_day(state.time_of_day)
	if state.get("clock") is float: atmosphere.profile.day_length_minutes = state.clock
	if state.get("weather") is int and state.get("amount") is float:
		atmosphere.set_weather(clampi(state.weather, 0, 4), clampf(state.amount, 0, 1), true)
	if state.get("wind_from") is float and state.get("breeze") is float and state.get("gust_speed") is float:
		atmosphere.set_wind(state.wind_from, state.breeze, state.gust_speed)
	if state.get("fade") is float: atmosphere.profile.weather_transition_seconds = state.fade
	if state.get("wetness") is float: atmosphere.wetness = clampf(state.wetness, 0, 1)
	atmosphere._tick(0.0)
	_refresh_blocked_overlay()
	camera.refresh()
	weather_focus.position = camera.focus
	model.set_motion_scale(camera.zoom_size)
	if state.get("selected_hex") is Vector2i and world.has(state.selected_hex): select_hex(state.selected_hex)

func _refresh_campaign_overlays() -> void:
	if campaign_overlays != null:
		world_root.remove_child(campaign_overlays)
		campaign_overlays.queue_free()
	campaign_overlays = Node3D.new()
	campaign_overlays.name = "CampaignMarkers"
	world_root.add_child(campaign_overlays)
	if provided_campaign == null or not "villages" in provided_campaign: return
	for record in provided_campaign.villages:
		var coord: Vector2i = record.hex
		if not world.has(coord): continue
		if world.hex(coord).settlement != record.id: continue
		var marker := Node3D.new()
		marker.name = record.id
		marker.position = WorldMapMesh.centre(coord)
		marker.position.y = model.surface_height(coord, marker.position) + 0.035
		campaign_overlays.add_child(marker)
		var status_name: String = record.status
		if status_name in ["ruin", "abandoned"]:
			for offset in [Vector3(-0.16,0.09,0), Vector3(0.1,0.04,0.1), Vector3(0.08,0.13,-0.10)]:
				factory.box(marker, offset, Vector3(0.14,offset.y * 2,0.12), Color("858c7b"))
		else:
			var offsets := [Vector3(-0.18,0,-0.10), Vector3(0.16,0,0.12)]
			if status_name == "chartered": offsets.append(Vector3(0.15,0,-0.23))
			for at in offsets:
				factory.box(marker, at + Vector3.UP * 0.10, Vector3(0.22,0.20,0.20), art_profile.plaster_cream)
				factory.roof(marker, at + Vector3.UP * 0.20, 0.26, 0.24, 0.14, art_profile.roof_terracotta)
		var colour := Color("e1ba62") if status_name == "chartered" else (Color("c8553d") if status_name == "active" else Color("87948b"))
		factory.box(marker, Vector3(0,0.36,0), Vector3(0.028,0.72,0.028), Color("59422e"))
		factory.box(marker, Vector3(0.11,0.62,0), Vector3(0.22,0.13,0.015), colour)

func _refresh_reach_overlay() -> void:
	if reach_overlay != null:
		world_root.remove_child(reach_overlay)
		reach_overlay.queue_free()
	reach_overlay = Node3D.new()
	reach_overlay.name = "VillageReach"
	world_root.add_child(reach_overlay)
	if not campaign_mode or selected_hex == NO_HEX: return
	for coord in world.reach(selected_hex):
		if not world.has(coord): continue
		var ring := MeshInstance3D.new()
		ring.mesh = _ring_mesh(coord)
		var mat: StandardMaterial3D = ring.mesh.surface_get_material(0)
		mat.albedo_color = Color("b9c783")
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position = WorldMapMesh.centre(coord) + Vector3.UP * 0.007
		reach_overlay.add_child(ring)

## Full resolution, keeping the village's 16:9 framing (letterboxed if needed).
func _resize_display() -> void:
	var fit := minf(size.x / 640.0, size.y / 360.0)
	pixel_viewport.size = Vector2i((Vector2(640, 360) * fit).floor()).max(Vector2i.ONE)
	display.size = Vector2(pixel_viewport.size)
	display.position = ((size - display.size) / 2.0).floor()
	if camera != null:
		camera.refresh()

func _process(delta: float) -> void:
	if world == null:
		return
	var pan := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A): pan.x -= 1
	if Input.is_physical_key_pressed(KEY_D): pan.x += 1
	if Input.is_physical_key_pressed(KEY_W): pan.y += 1
	if Input.is_physical_key_pressed(KEY_S): pan.y -= 1
	if pan != Vector2.ZERO and not get_viewport().gui_get_focus_owner() is LineEdit:
		camera.pan(pan.normalized(), delta)
		weather_focus.position = camera.focus
	_update_hover()
	model.set_motion_scale(camera.zoom_size)

## Re-picks the hex under the mouse; runs every frame so camera moves update it.
func _update_hover() -> void:
	if mouse_position.x < 0.0 or not display.get_global_rect().has_point(mouse_position):
		_set_hover(NO_HEX)
		return
	if panel.visible and panel.get_global_rect().has_point(mouse_position):
		return
	_set_hover(hex_at(to_viewport(mouse_position)))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_position = event.position
		_update_hover()
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				if show_back: back_requested.emit()
			KEY_Q: camera.rotate_quarter(-1)
			KEY_E: camera.rotate_quarter(1)
			KEY_N:
				if not campaign_mode: set_seed(seed_value + (-1 if event.shift_pressed else 1))
			KEY_V:
				reveal_all = not reveal_all
				_refresh_panel()
			KEY_F:
				show_settleability = not show_settleability
				_refresh_blocked_overlay()
			KEY_P:
				if hovered != NO_HEX: print(JSON.stringify(world.hex(hovered).to_dict(), "  "))
			KEY_L:
				var focus: Vector3 = camera.focus
				var zoom: float = camera.zoom_size
				map_art.linked_tiles = not map_art.linked_tiles
				set_world(world)
				camera.focus = focus
				camera.zoom_size = zoom
				camera.refresh()
			_:
				atmosphere.handle_debug_key(event.physical_keycode)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and campaign_mode:
			var coord := hex_at(to_viewport(event.position))
			if coord != NO_HEX:
				select_hex(coord)
				hex_selected.emit(coord)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_map(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_map(1)

func _zoom_map(direction: int) -> void:
	camera.zoom_size = clampf(camera.zoom_size + direction * 4.0, 8.0, 48.0)
	camera.refresh()

func select_hex(coord: Vector2i) -> void:
	selected_hex = coord
	if selection_marker == null:
		selection_marker = MeshInstance3D.new()
		selection_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(selection_marker)
	selection_marker.mesh = _ring_mesh(coord)
	selection_marker.position = WorldMapMesh.centre(coord) + Vector3.UP * 0.008
	_refresh_reach_overlay()

func _refresh_blocked_overlay() -> void:
	var prior := world_root.get_node_or_null("Settleability")
	if prior != null:
		world_root.remove_child(prior)
		prior.queue_free()
	var founding_mode: bool = campaign_mode and provided_campaign != null and provided_campaign.village == null
	if not show_settleability and not founding_mode: return
	var overlay := Node3D.new()
	overlay.name = "Settleability"
	world_root.add_child(overlay)
	for coord in world.hexes:
		var blocked: String = world.found_blocked(coord)
		if provided_campaign != null: blocked = provided_campaign.found_blocked(coord)
		if blocked.is_empty(): continue
		var hatch := MeshInstance3D.new()
		hatch.mesh = _hatch_mesh(coord)
		hatch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hatch.position = WorldMapMesh.centre(coord) + Vector3.UP * 0.012
		overlay.add_child(hatch)

func _hatch_mesh(coord: Vector2i) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(-5, 6):
		for segment in range(-9, 10):
			var x := segment * 0.12
			var z := row * 0.22 + x * 0.45
			var points := [Vector3(x,0,z), Vector3(x+0.12,0,z+0.054), Vector3(x+0.12,0,z+0.079), Vector3(x,0,z+0.025)]
			var inside := true
			for point in points:
				if HexMath.from_point(Vector2(point.x,point.z) / WorldMapMesh.SCALE) != Vector2i.ZERO: inside = false
			if not inside: continue
			for point in [points[0],points[2],points[1],points[0],points[3],points[2]]:
				point.y = model.surface_height(coord, WorldMapMesh.centre(coord) + point)
				st.set_normal(Vector3.UP)
				st.add_vertex(point)
	var mesh := st.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.61,0.31,0.22,0.20)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0,material)
	return mesh

func to_viewport(point: Vector2) -> Vector2:
	return (point - display.position) * Vector2(pixel_viewport.size) / display.size

## The hex under a viewport point: march down the camera
## ray until it meets a prism top (or the sea), so raised hexes pick correctly.
func hex_at(pixel: Vector2) -> Vector2i:
	var origin: Vector3 = camera.project_ray_origin(pixel)
	var ray: Vector3 = camera.project_ray_normal(pixel)
	var start := (origin.y - 3.0) / -ray.y
	var finish := (origin.y - WorldMapMesh.WATER_LEVEL + 0.05) / -ray.y
	var distance := start
	while distance <= finish:
		var at := origin + ray * distance
		var coord := HexMath.from_point(Vector2(at.x, at.z) / WorldMapMesh.SCALE)
		if at.y <= model.surface_height(coord, at):
			return coord if world.has(coord) else NO_HEX
		distance += 0.01
	var flat := origin + ray * finish
	var last := HexMath.from_point(Vector2(flat.x, flat.z) / WorldMapMesh.SCALE)
	return last if world.has(last) else NO_HEX

func _set_hover(coord: Vector2i) -> void:
	if coord == hovered and coord != NO_HEX:
		return
	hovered = coord
	hover_marker.visible = coord != NO_HEX
	if hover_marker.visible:
		hover_marker.mesh = _ring_mesh(coord)
		hover_marker.position = WorldMapMesh.centre(coord) + Vector3.UP * 0.006
	_refresh_panel()

func _refresh_panel() -> void:
	panel.visible = hovered != NO_HEX
	if not panel.visible:
		return
	panel_text.text = describe(hovered)

## The hex panel's text: what a player needs to judge the hex as a site.
func describe(coord: Vector2i) -> String:
	var info = world.hex(coord)
	var biome: Dictionary = data.biomes[info.biome]
	var lines: Array[String] = []
	var kind := "Harsh" if biome.harsh else ("Cannot be settled" if not biome.settleable else "Normal")
	lines.append("[font_size=18][b]%s[/b][/font_size]   [color=#a9b39a]%s[/color]" % [biome.name, kind])
	if not info.is_land():
		lines.append("Open water.")
		return "\n".join(lines)
	lines.append("%s  ·  wildness %d/5" % [ELEVATIONS[info.elevation], info.wildness])
	var features: Array[String] = []
	if info.river_width() > 0: features.append(RIVERS[info.river_width()])
	if info.lake: features.append("a lake")
	if not info.coast_edges.is_empty(): features.append("sea coast")
	if info.cliffs > 0.55: features.append("cliffs")
	if info.forest > 0.6: features.append("dense forest")
	elif info.forest > 0.3: features.append("woodland")
	lines.append("Features: " + (", ".join(features) if not features.is_empty() else "open ground"))
	var climate := "cold" if info.temperature < 0.3 else ("warm" if info.temperature > 0.7 else "temperate")
	var wetness := "wet" if info.moisture > 0.66 else ("dry" if info.moisture < 0.33 else "moist")
	lines.append("Climate: %s, %s" % [climate, wetness])
	if biome.settleable:
		var known: Array[String] = info.deposits.duplicate() if reveal_all else world.visible_deposits(coord)
		var names: Array[String] = []
		for deposit in known:
			names.append(data.deposits[deposit].name)
		lines.append("Deposits: " + (", ".join(names) if not names.is_empty() else "none known"))
		if not info.scouted and not reveal_all:
			lines.append("[color=#d9b45f]Unscouted[/color]: more may be hidden")
	var blocked: String = provided_campaign.found_blocked(coord) if provided_campaign != null else world.found_blocked(coord)
	if coord == world.start:
		lines.append("[color=#e0a17d]Starting region[/color]")
	if not info.settlement.is_empty():
		var record: Dictionary = provided_campaign.village_at(coord) if provided_campaign != null else {}
		lines.append("[color=#e0a17d]%s · %s[/color]" % [record.get("name", "Your village"), String(record.get("status", "active")).capitalize()])
	if info.settlement.is_empty():
		var message := "A village can be founded here" if provided_campaign == null or world.site_errors.has(coord) else "Select to check the founding terrain"
		lines.append("[color=#9fc27a]%s[/color]" % message if blocked.is_empty() else "[color=#c98a7a]%s[/color]" % blocked)
	else:
		var record: Dictionary = provided_campaign.village_at(coord) if provided_campaign != null else {}
		var status_name: String = record.get("status", "active")
		if status_name == "active": lines.append("[color=#9fc27a]Resume your village from the campaign panel[/color]")
		elif status_name == "chartered": lines.append("[color=#e0bf78]Chartered village · review its record[/color]")
		elif blocked.is_empty(): lines.append("[color=#9fc27a]This ruin can be resettled[/color]")
		else: lines.append("[color=#c98a7a]%s[/color]" % blocked)
	return "\n".join(lines)

func _build_overlay() -> void:
	var theme := Theme.new()
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", Color("e4dfd2"))
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.theme = theme
	add_child(overlay)
	panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.105, 0.14, 0.11, 0.96)
	style.border_color = Color("5d7946")
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(16, 16)
	if campaign_mode: panel.position = Vector2(258, 18)
	panel.custom_minimum_size = Vector2(320, 0)
	panel.visible = false
	overlay.add_child(panel)
	panel_text = RichTextLabel.new()
	panel_text.bbcode_enabled = true
	panel_text.fit_content = true
	panel_text.scroll_active = false
	panel_text.custom_minimum_size = Vector2(300, 0)
	panel_text.add_theme_color_override("default_color", Color("e4dfd2"))
	panel_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(panel_text)
	hint = Label.new()
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -34
	hint.offset_bottom = -12
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.9, 0.88, 0.82, 0.85))
	hint.add_theme_color_override("font_outline_color", Color(0.06, 0.08, 0.07))
	hint.add_theme_constant_override("outline_size", 4)
	overlay.add_child(hint)
	back_button = Button.new()
	back_button.text = "Back to village"
	back_button.visible = show_back
	back_button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "focus"]:
		var button_style := StyleBoxFlat.new()
		button_style.bg_color = Color("2d3328") if state == "normal" else Color("485439")
		button_style.set_corner_radius_all(5)
		button_style.content_margin_left = 14
		button_style.content_margin_right = 14
		button_style.content_margin_top = 10
		button_style.content_margin_bottom = 10
		back_button.add_theme_stylebox_override(state, button_style)
	back_button.add_theme_color_override("font_color", Color("e4dfd2"))
	back_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back_button.offset_left = -190
	back_button.offset_right = -18
	back_button.offset_top = 18
	back_button.offset_bottom = 66
	back_button.pressed.connect(func(): back_requested.emit())
	overlay.add_child(back_button)

## A thin light ring on a hex's rim, for the hovered hex.
func _ring_mesh(coord: Vector2i = NO_HEX) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := HexMath.RADIUS * WorldMapMesh.SCALE
	for segment in 24:
		var side := segment / 4
		var a0 := deg_to_rad(side * 60.0 - 30.0)
		var a1 := deg_to_rad(side * 60.0 + 30.0)
		var first := Vector3(cos(a0), 0, sin(a0)) * radius
		var second := Vector3(cos(a1), 0, sin(a1)) * radius
		var outer0 := first.lerp(second, float(segment % 4) / 4.0)
		var outer1 := first.lerp(second, float(segment % 4 + 1) / 4.0)
		var inner0 := outer0 * 0.94
		var inner1 := outer1 * 0.94
		if coord != NO_HEX and model != null:
			outer0.y = model.surface_height(coord, WorldMapMesh.centre(coord) + outer0)
			outer1.y = model.surface_height(coord, WorldMapMesh.centre(coord) + outer1)
			inner0.y = model.surface_height(coord, WorldMapMesh.centre(coord) + inner0)
			inner1.y = model.surface_height(coord, WorldMapMesh.centre(coord) + inner1)
		for point in [inner0, outer1, outer0, inner0, inner1, outer1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(point)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("f3e7b8")
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := st.commit()
	mesh.surface_set_material(0, material)
	return mesh

func _screenshot() -> void:
	for frame in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var result := get_viewport().get_texture().get_image().save_png("res://artifacts/world-map.png")
	print("WORLD MAP SCREENSHOT: seed %d -> %s" % [seed_value, "res://artifacts/world-map.png" if result == OK else "failed"])
	get_tree().quit(0 if result == OK else 1)
