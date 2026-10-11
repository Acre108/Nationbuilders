class_name BuildingLocalLights
extends RefCounted

## Shared finite, shadowed authored lights. FurnitureRuntime owns full fixtures;
## include_fixture retains the older standalone binding API.
static var _metadata: Dictionary = {}
static var _catalogue: FurnitureCatalogue

static func _load() -> void:
	if _catalogue != null: return
	_catalogue = FurnitureRuntime.catalogue()
	for id in _catalogue.object_ids():
		var source := _catalogue.object_data(id)
		if not source.lights.is_empty(): _metadata[str(id)] = source.lights

static func attach(parent: Node3D, catalogue_id: String, include_fixture: bool = true) -> bool:
	_load()
	if not _metadata.has(catalogue_id) or not _catalogue.has_object(catalogue_id): return false
	if include_fixture:
		var fixture := FurniturePreview.build(_catalogue,catalogue_id)
		parent.add_child(fixture)
		# Primitive shades/bulbs are a visible reference, not solid light blockers.
		for child in fixture.get_children():
			if child is GeometryInstance3D:
				child.set_meta("light_fixture",true)
				child.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for entry in _metadata[catalogue_id]:
		var archetype := str(entry.archetype)
		var task := archetype == "ceiling-task-light" or catalogue_id == "cantilever-floor-lamp"
		var light: Light3D = SpotLight3D.new() if task else OmniLight3D.new()
		light.name = str(entry.id)
		light.set_meta("authored_local_light",true)
		var p: Dictionary = entry.position
		light.position = Vector3(float(p.x),float(p.y),float(p.z))
		# Warm-white (~2700 K) bulbs. General ceiling lights sit close to the
		# ceiling, so they run dimmer than task lamps to avoid a clipped hot spot.
		var general := archetype.begins_with("ceiling") and not task
		light.light_color = Color("#ffcf9c") if archetype.begins_with("ceiling") else Color("#ffc285")
		light.light_energy = (1.3 if general else 2.0) * float(entry.get("intensityScale",1.0))
		light.light_bake_mode = Light3D.BAKE_DYNAMIC
		light.light_indirect_energy = 0.6
		light.shadow_enabled = true
		light.shadow_bias = 0.02
		light.shadow_normal_bias = 0.6
		if light is SpotLight3D:
			light.spot_range = 7.0
			light.spot_angle = 55.0 if archetype.begins_with("ceiling") else 40.0
			light.rotation_degrees.x = -90.0 if archetype.begins_with("ceiling") else -60.0
		else:
			light.omni_range = 7.0 if archetype.begins_with("ceiling") else 5.0
		parent.add_child(light)
	return true

static func set_quality(root: Node, level: FoliageQuality.Level) -> void:
	var lights: Array[Light3D] = []
	_collect(root,lights)
	# All active lights cast shadows so partitions remain effective. Beyond the
	# cap, fixtures stay visible but their light is inactive (never unshadowed).
	var limit := 2 if level == FoliageQuality.Level.LOW else (6 if level == FoliageQuality.Level.ULTRA else 4)
	for index in lights.size(): lights[index].visible = index < limit
	root.set_meta("active_local_lights",mini(lights.size(),limit))
	root.set_meta("inactive_local_lights",maxi(0,lights.size()-limit))

static func _collect(node: Node, lights: Array[Light3D]) -> void:
	if node is Light3D and node.get_meta("authored_local_light",false): lights.append(node)
	for child in node.get_children(): _collect(child,lights)
