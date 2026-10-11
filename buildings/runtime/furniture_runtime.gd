class_name FurnitureRuntime
extends RefCounted

## Every source primitive is audited: box/cylinder/sphere/cone; colliders are boxes.
static var _catalogue: FurnitureCatalogue
static var _meshes: Dictionary = {}
static var _attachments: Dictionary = {}
static var _bounds: Dictionary = {}

static func catalogue() -> FurnitureCatalogue:
	if _catalogue == null:
		_catalogue = FurnitureCatalogue.load_default()
		var path := "res://content/furniture_overrides/attachments.json"
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary: _attachments = parsed
	return _catalogue

static func xyz(value: Dictionary) -> Vector3:
	return Vector3(float(value.x), float(value.y), float(value.z))

static func attachment(id: String) -> String:
	var entry := catalogue().object_data(id)
	var source: Dictionary = entry.get("definition", {})
	return str(source.get("placement", source.get("catalogue", {}).get("placement", _attachments.get(id, "floor"))))

static func bounds(id: String) -> AABB:
	if _bounds.has(id): return _bounds[id]
	var entry := catalogue().object_data(id)
	var result := AABB()
	var first := true
	for record in entry.get("nodes", []) + entry.get("colliders", []):
		var center := xyz(record.get("position", record.get("center", {})))
		var size := xyz(record.size)
		var box := AABB(center-size/2, size)
		var rotated := Transform3D(Basis(Vector3.UP, deg_to_rad(float(record.get("yaw", 0)))), Vector3.ZERO) * box
		result = rotated if first else result.merge(rotated)
		first = false
	_bounds[id] = AABB(Vector3(-0.3,0,-0.3),Vector3(0.6,1,0.6)) if first else result
	return _bounds[id]

static func build(data: Dictionary, instance: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = instance.id
	root.set_meta("element_id", instance.id)
	root.set_meta("furniture_id", instance.id)
	root.set_meta("furniture_definition", instance.duplicate(true))
	root.position = BuildingDefinition.vector(instance.position)
	root.rotation_degrees.y = float(instance.yaw_degrees)
	populate(root, data, instance)
	return root

static func populate(root: Node3D, data: Dictionary, instance: Dictionary) -> void:
	var entry := catalogue().object_data(instance.catalogue_id)
	root.set_meta("source_definition", entry)
	if entry.is_empty():
		var label := Label3D.new()
		label.text = "Missing furniture\n" + str(instance.catalogue_id)
		label.position.y = 0.75
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(label)
		# Retain a selectable, non-blocking placeholder for unavailable packs.
		return
	for record in entry.nodes:
		var shape := str(record.shape)
		if not shape in ["box", "cylinder", "sphere", "cone"]:
			push_error("Unsupported furniture shape: " + shape)
			continue
		var visual := MeshInstance3D.new()
		if not _meshes.has(shape): _meshes[shape] = FurniturePreview._unit_mesh(shape)
		visual.mesh = _meshes[shape]
		visual.position = xyz(record.position)
		visual.rotation_degrees.y = float(record.get("yaw", 0))
		visual.scale = xyz(record.size)
		visual.material_override = BuildingMaterials.furniture(data, instance, record)
		visual.set_meta("furniture_node", record.duplicate(true))
		visual.set_meta("furniture_id", instance.id)
		if not entry.lights.is_empty():
			visual.set_meta("light_fixture", true)
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			visual.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(visual)
	for record in entry.colliders:
		var body := StaticBody3D.new()
		body.position = xyz(record.center)
		body.rotation_degrees.y = float(record.get("yaw", 0))
		body.set_meta("furniture_id", instance.id)
		body.set_meta("element_id", instance.id)
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = xyz(record.size)
		collision.shape = box
		body.add_child(collision)
		root.add_child(body)
	BuildingLocalLights.attach(root, instance.catalogue_id, false)

static func update(root: Node3D, data: Dictionary, instance: Dictionary) -> void:
	root.position = BuildingDefinition.vector(instance.position)
	root.rotation_degrees.y = float(instance.yaw_degrees)
	root.set_meta("furniture_definition", instance.duplicate(true))
	for child in root.get_children():
		if child is MeshInstance3D and child.has_meta("furniture_node"):
			child.material_override = BuildingMaterials.furniture(data, instance, child.get_meta("furniture_node"))
