class_name LocationCommands
extends Node

## Shared location commands, including the furniture/carving tools from the
## Rolling Hills review scene. Lifetime is exactly one destination visit.
const PLACEABLE: Array[StringName] = [
	&"bordered-wool-rug", &"timber-garden-bench", &"round-stone-dining-table",
	&"oak-trestle-dining-table", &"paper-pear-floor-lantern", &"broad-leaf-house-plant",
]

var runtime: LocationRuntime
var hud: FoliageHUD
var _catalogue: FurnitureCatalogue
var _events: FoliagePlacementEvents
var _placed: Array[Dictionary] = []
var _next_id := 0
var _lod_tint := false


func _ready() -> void:
	hud = FoliageHUD.new()
	hud.name = "CommandsMenu"
	hud.destination_help = "N / Esc choose another destination"
	add_child(hud)
	hud.track_location(runtime.location)
	hud.track(runtime.location.grass)
	hud.track_trees(runtime.location.trees)
	hud.track_debris(runtime.location.debris)
	hud.track_atmosphere(runtime.atmosphere)
	_events = runtime.location.placement_events


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if handle_key(event.keycode):
			get_viewport().set_input_as_handled()


func handle_key(key: int) -> bool:
	if runtime.atmosphere != null and runtime.atmosphere.handle_debug_key(key):
		return true
	var grass := runtime.location.grass
	match key:
		KEY_F:
			hud.visible = not hud.visible
		KEY_1, KEY_2, KEY_3, KEY_4:
			var level := (key - KEY_1) as FoliageQuality.Level
			runtime.set_quality(level)
			if grass != null:
				grass.set_lod_debug(_lod_tint)
		KEY_L:
			_lod_tint = not _lod_tint
			if grass != null:
				grass.set_lod_debug(_lod_tint)
		KEY_K:
			if grass != null:
				grass.lod_enabled = not grass.lod_enabled
				grass.rebuild()
				grass.set_lod_debug(_lod_tint)
		KEY_P:
			_place_at_crosshair()
		KEY_R:
			if not _placed.is_empty():
				var entry: Dictionary = _placed.back()
				var node: Node3D = entry.node
				node.rotation.y += deg_to_rad(15.0)
				_events.place(entry.id, _catalogue.footprints(entry.object, node.position, node.rotation.y))
		KEY_BACKSPACE:
			if not _placed.is_empty():
				var entry: Dictionary = _placed.pop_back()
				_events.remove(entry.id)
				entry.node.queue_free()
		KEY_N:
			# Deferred: the receiver may free this controller during teardown.
			runtime.choose_destination_requested.emit.call_deferred()
		KEY_BRACKETLEFT:
			runtime.sun.rotation.y -= deg_to_rad(8.0)
		KEY_BRACKETRIGHT:
			runtime.sun.rotation.y += deg_to_rad(8.0)
		KEY_SEMICOLON:
			runtime.sun.rotation.x = clampf(runtime.sun.rotation.x - deg_to_rad(5.0), -PI * 0.5, -0.05)
		KEY_APOSTROPHE:
			runtime.sun.rotation.x = clampf(runtime.sun.rotation.x + deg_to_rad(5.0), -PI * 0.5, -0.05)
		_:
			return false
	return true


func _place_at_crosshair() -> void:
	if runtime.location.grass == null:
		return
	var camera := runtime.camera
	var direction := -camera.global_basis.z
	var distance := 0.3
	while distance < 80.0:
		var point := camera.global_position + direction * distance
		var height := runtime.location.terrain.get_height(point.x, point.z)
		if point.y <= height:
			place_object(Vector3(point.x, height, point.z), camera.global_rotation.y)
			return
		distance += 0.1


func place_object(at: Vector3, yaw: float) -> void:
	if runtime.location.grass == null:
		return
	if _catalogue == null:
		_catalogue = FurnitureCatalogue.load_default()
	var object := PLACEABLE[_next_id % PLACEABLE.size()]
	var id := StringName("commands_%d" % _next_id)
	_next_id += 1
	var node := FurniturePreview.build(_catalogue, object)
	node.position = at
	node.rotation.y = yaw
	add_child(node)
	_placed.append({"id": id, "object": object, "node": node})
	_events.place(id, _catalogue.footprints(object, at, yaw))
