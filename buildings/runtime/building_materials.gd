class_name BuildingMaterials
extends RefCounted

## Shared presets; colours in legacy documents remain valid material values.
const FAMILIES := {
	"warm-wood": ["#b78a59", 0.78, 0.0], "dark-wood": ["#513a2b", 0.75, 0.0],
	"metal": ["#9ba2a6", 0.3, 0.85], "cloth": ["#a7b6ba", 0.95, 0.0],
	"painted-wall": ["#e4dfd2", 0.88, 0.0], "ceramic": ["#e7e3d8", 0.25, 0.0],
	"glass": ["#b7d9df80", 0.12, 0.0], "emissive": ["#ffe6ab", 0.4, 0.0],
	"foliage": ["#5d7946", 0.9, 0.0],
	# Exterior finishes, also used by Location Studio placeholder overrides.
	"render": ["#d8cdb4", 0.92, 0.0], "brick": ["#9a5440", 0.9, 0.0],
	"stone": ["#a39d90", 0.9, 0.0], "concrete": ["#a9a69f", 0.88, 0.0],
	"roof-tiles": ["#8c4a32", 0.92, 0.0], "slate": ["#4b5057", 0.7, 0.0],
	"thatch": ["#8d7848", 0.98, 0.0]
}
const FURNITURE_SLOTS := ["primary", "secondary", "tertiary"]
static var _cache: Dictionary = {}

static func valid(value: Variant) -> bool:
	return value is String and (FAMILIES.has(value) or Color.html_is_valid(value))

static func material(value: String, family: String = "", source_colour: String = "#888888") -> StandardMaterial3D:
	var key := JSON.stringify([value, family, source_colour])
	if _cache.has(key): return _cache[key]
	var preset: Array = FAMILIES.get(value, FAMILIES.get(family, [source_colour, 0.85, 0.0]))
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(preset[0] if FAMILIES.has(value) else (value if Color.html_is_valid(value) else source_colour))
	result.roughness = float(preset[1])
	result.metallic = float(preset[2])
	var active_family := value if FAMILIES.has(value) else family
	if active_family == "glass":
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		result.cull_mode = BaseMaterial3D.CULL_DISABLED
	if active_family == "emissive":
		result.emission_enabled = true
		result.emission = result.albedo_color
	_cache[key] = result
	return result

static func surface(data: Dictionary, id: String, slot: String, storey_id: String, fallback: String = "", source_id: String = "") -> String:
	var building: Dictionary = data.get("materials", {}).merged(data.get("material_presets", {}), true)
	var storey: Dictionary = data.get("storey_materials", {}).get(storey_id, {})
	var overrides: Dictionary = data.get("material_overrides", {})
	return str(overrides.get(id, {}).get(slot, overrides.get(source_id, {}).get(slot, storey.get(slot, data.get("material_presets", {}).get(slot, fallback if not fallback.is_empty() else building.get(slot, "#888888"))))))

static func furniture(data: Dictionary, instance: Dictionary, node: Dictionary) -> StandardMaterial3D:
	var slot := str(node.get("materialSlot", "primary"))
	var value := str(instance.get("material_overrides", {}).get(slot, data.get("furniture_materials", {}).get(slot, "")))
	return material(value, str(node.get("material", "")), str(node.get("color", "#888888")))

static func surface_slots(data: Dictionary, id: String) -> Array:
	for level in data.storeys:
		for slab in level.slabs:
			if slab.id == id: return [slab.slot]
		for wall in level.walls:
			if wall.id == id: return ["interior_wall"] if wall.get("kind") == "partition" else ["interior_wall","exterior_wall"]
		for room in level.rooms:
			if room.id == id: return ["floor"]
		for opening in level.openings:
			if opening.id == id: return ["glass","interior_wall"] if opening.kind == "window" else ["interior_wall"]
	for component in data.get("exterior_components",[]):
		if component.id == id: return [component.slot]
	for stair in data.stairs:
		if stair.id == id: return ["floor","interior_wall"]
	return []

static func furniture_slots(id: String) -> Array:
	var result: Array = []
	var source := FurnitureRuntime.catalogue().object_data(id)
	if source.is_empty(): return FURNITURE_SLOTS.duplicate()
	for node in source.nodes:
		var slot := str(node.get("materialSlot","primary"))
		if slot in FURNITURE_SLOTS and not slot in result: result.append(slot)
	result.sort()
	return result
