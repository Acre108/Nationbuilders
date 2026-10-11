class_name BuildingDefinition
extends RefCounted

## JSON-compatible, resolved structure. Loading never calls a generator.
const SCHEMA_VERSION := 2
const LEGACY_SCHEMA_VERSION := 1
const GENERATOR_VERSION := 1
const SURFACE_SLOTS := ["exterior_wall", "interior_wall", "floor", "ceiling", "roof", "glass"]

var data: Dictionary = {}

func _init(source: Dictionary = {}) -> void:
	data = source.duplicate(true)
	# Godot's JSON reader represents every number as a float. Restore the
	# schema's integer fields so reopening does not create spurious edits.
	for key in ["schema_version", "generator_version", "seed"]:
		_restore_integer(data, key)
	if data.get("parameters") is Dictionary:
		_restore_integer(data.parameters, "storeys")
	_restore_integer(data, "compiler_version")
	if data.get("furnishing") is Dictionary:
		_restore_integer(data.furnishing,"version")
		_restore_integer(data.furnishing,"seed")
	if data.get("furniture") is Array:
		for item in data.furniture:
			if item is Dictionary and item.get("furnishing") is Dictionary:
				_restore_integer(item.furnishing,"version")
				_restore_integer(item.furnishing,"slot")
	if data.get("schema_version") == 2 and data.get("storeys") is Array:
		for storey in data.storeys:
			if not storey is Dictionary or not storey.get("layout") is Dictionary or not storey.layout.get("cells") is Array: continue
			for point in storey.layout.cells:
				if numbers(point, 2) and point[0] == floor(float(point[0])) and point[1] == floor(float(point[1])) and absf(float(point[0])) <= 2048 and absf(float(point[1])) <= 2048:
					point[0] = int(point[0])
					point[1] = int(point[1])
			if storey.layout.get("rooms") is Array:
				for room in storey.layout.rooms:
					if not room is Dictionary or not room.get("cells") is Array: continue
					for point in room.cells:
						if numbers(point,2) and float(point[0]) == floor(float(point[0])) and float(point[1]) == floor(float(point[1])) and absf(float(point[0])) <= 2048 and absf(float(point[1])) <= 2048:
							point[0] = int(point[0])
							point[1] = int(point[1])
			for collection in ["walls", "slabs", "uncut_slabs"]:
				if not storey.get(collection) is Array: continue
				for record in storey[collection]:
					if not record is Dictionary: continue
					_restore_integer(record,"exterior_side")
					for anchor in ["grid_from", "grid_to", "grid_rect"]:
						if not record.get(anchor) is Array: continue
						for index in record[anchor].size():
							var coordinate: Variant = record[anchor][index]
							if numbers([coordinate],1) and float(coordinate) == floor(float(coordinate)) and absf(float(coordinate)) < 4096: record[anchor][index] = int(coordinate)
	if data.get("stairs") is Array:
		for stair in data.stairs:
			if stair is Dictionary: _restore_integer(stair,"orientation")
	if data.get("schema_version") == 2 and data.get("conversion_source") is Dictionary and data.conversion_source.get("schema_version") == 1:
		data.conversion_source = BuildingDefinition.new(data.conversion_source).data

static func _restore_integer(record: Dictionary, key: String) -> void:
	var value: Variant = record.get(key)
	if numbers([value], 1) and float(value) == floor(float(value)) and absf(float(value)) <= 2147483647:
		record[key] = int(value)

func copy() -> BuildingDefinition:
	return BuildingDefinition.new(data)

static func vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

static func valid_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 128:
		return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.":
			return false
	return value != "." and value != ".."

static func numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)):
			return false
	return true

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if data.get("compiler_version") != 5 and data.get("storeys") is Array:
		for level in data.storeys:
			if level is Dictionary and level.get("layout") is Dictionary and level.layout.get("courtyards",false): errors.append("Courtyard layouts require compiler version 5.")
	if not data.get("visual_profile","plain") in BuildingVisuals.PROFILES: errors.append("Unsupported facade style.")
	if data.has("furnishing"):
		var settings: Variant = data.furnishing
		if not settings is Dictionary or settings.get("version") != 1 or not settings.get("seed") is int or settings.seed < 0 or settings.seed > 2147483647: errors.append("Invalid furnishing settings.")
	if not data.get("schema_version") in [LEGACY_SCHEMA_VERSION, SCHEMA_VERSION]:
		errors.append("Unsupported building schema version: %s (supported: 1–2). Source file is unchanged." % str(data.get("schema_version")))
		return errors
	if data.get("generator_version") != GENERATOR_VERSION:
		errors.append("Unsupported generator version. Explicit migration is required before editing.")
	if not valid_id(data.get("id")):
		errors.append("Building ID must contain only letters, numbers, hyphens, dots or underscores.")
	if not data.get("name") is String or str(data.get("name", "")).strip_edges().is_empty():
		errors.append("Building name is required.")
	var parameters: Variant = data.get("parameters")
	if not parameters is Dictionary:
		errors.append("Generator parameters are missing.")
	else:
		for key in ["width", "depth", "storey_height"]:
			if not numbers([parameters.get(key)], 1):
				errors.append("Invalid parameter: " + key)
		if parameters.get("storeys") != 1 and data.get("compiler_version") not in [4,5]:
			errors.append("This milestone supports one storey.")
	if not data.get("seed") is int:
		errors.append("Generator seed is missing or invalid.")
	var materials: Variant = data.get("materials")
	if not materials is Dictionary:
		errors.append("Material defaults are missing.")
	else:
		for slot in SURFACE_SLOTS:
			if not BuildingMaterials.valid(materials.get(slot)):
				errors.append("Invalid material colour for " + slot)
	var overrides: Variant = data.get("material_overrides")
	if not overrides is Dictionary:
		errors.append("Material overrides must be a dictionary.")
	else:
		for element in overrides:
			if not valid_id(element) or not overrides[element] is Dictionary:
				errors.append("Invalid material override entry.")
				continue
			for slot in overrides[element]:
				if not slot in SURFACE_SLOTS or not BuildingMaterials.valid(overrides[element][slot]):
					errors.append("Invalid material override on " + element)
	errors.append_array(_validate_contents())
	if data.get("schema_version") == 2:
		if data.get("compiler_version") in [4,5]:
			if not errors.is_empty(): return errors
			return BuildingStoreys.validate(data)
		return _validate_grid_layout(errors)
	var storeys: Variant = data.get("storeys")
	if not storeys is Array or storeys.size() != 1:
		errors.append("Resolved structure must contain one storey.")
		return errors
	var ids := {str(data.get("id", "")): true}
	var walls := {}
	var openings := {}
	for floor in storeys:
		if not floor is Dictionary:
			errors.append("Invalid storey record.")
			continue
		_register_id(floor, ids, errors)
		if not numbers([floor.get("elevation"), floor.get("height")], 2) or float(floor.get("height", 0)) < 2.7:
			errors.append("Invalid storey elevation/height or inadequate headroom.")
		if not numbers(floor.get("bounds"), 4):
			errors.append("Invalid resolved floor bounds.")
		elif floor.bounds[2] < 4 or floor.bounds[3] < 4 or floor.bounds[2] > (60 if data.get("structure_mode") == "authored" else 30) or floor.bounds[3] > (60 if data.get("structure_mode") == "authored" else 30):
			errors.append("Resolved floor dimensions must be 4–%d metres." % (60 if data.get("structure_mode") == "authored" else 30))
		for collection in ["rooms", "walls", "openings", "slabs"]:
			if not floor.get(collection) is Array or floor[collection].is_empty():
				errors.append("Missing resolved " + collection)
				continue
			for record in floor[collection]:
				if not record is Dictionary:
					errors.append("Invalid " + collection + " record.")
					continue
				_register_id(record, ids, errors)
				match collection:
					"rooms":
						if not numbers(record.get("bounds"), 4): errors.append("Invalid room bounds.")
					"walls":
						if not numbers(record.get("from"), 3) or not numbers(record.get("to"), 3) or not numbers([record.get("height"), record.get("thickness")], 2):
							errors.append("Invalid wall dimensions.")
						elif vector(record.from).distance_to(vector(record.to)) < (0.05 if data.get("structure_mode") == "authored" else 0.5) or absf(float(record.from[1]) - float(record.to[1])) > 0.001 or record.height < 2.7 or record.thickness <= 0 or record.thickness > 1:
							errors.append("Wall must be horizontal, positive and tall enough to enter.")
						if not record.get("openings") is Array: errors.append("Wall opening references are missing.")
						walls[str(record.get("id", ""))] = record
					"openings":
						if not record.get("kind") in ["entrance", "window"] or not record.get("wall_id") is String or not numbers([record.get("offset"), record.get("width"), record.get("bottom"), record.get("height")], 4):
							errors.append("Invalid opening record.")
						openings[str(record.get("id", ""))] = record
					"slabs":
						if not numbers(record.get("center"), 3) or not numbers(record.get("size"), 3) or not record.get("slot") in ["floor", "ceiling", "roof"]:
							errors.append("Invalid slab record.")
						elif vector(record.size).x <= 0 or vector(record.size).y <= 0 or vector(record.size).z <= 0:
							errors.append("Slab dimensions must be positive.")
	if not errors.is_empty(): return errors
	var referenced := {}
	for wall_id in walls:
		var wall: Dictionary = walls[wall_id]
		var length := vector(wall.from).distance_to(vector(wall.to))
		var intervals: Array[Vector2] = []
		for opening_id in wall.openings:
			if not openings.has(opening_id) or referenced.has(opening_id):
				errors.append("Missing or multiply referenced opening: " + str(opening_id))
				continue
			referenced[opening_id] = true
			var opening: Dictionary = openings[opening_id]
			if opening.wall_id != wall_id or opening.width <= 0 or opening.height <= 0 or opening.bottom < 0 or opening.bottom + opening.height > wall.height or opening.offset - opening.width / 2.0 < 0.1 or opening.offset + opening.width / 2.0 > length - 0.1:
				errors.append("Opening lies outside its wall: " + str(opening_id))
			if opening.kind == "entrance" and (opening.bottom != 0 or opening.width < 1.2 or opening.height < 2.1):
				errors.append("Entrance is too small for the visitor capsule.")
			var interval := Vector2(opening.offset - opening.width / 2.0, opening.offset + opening.width / 2.0)
			for previous in intervals:
				if interval.x < previous.y and interval.y > previous.x: errors.append("Wall openings overlap.")
			intervals.append(interval)
	if referenced.size() != openings.size(): errors.append("Orphan opening in resolved structure.")
	var entrance: Variant = data.get("entrance_id")
	if not openings.has(entrance) or openings.get(entrance, {}).get("kind") != "entrance":
		errors.append("A resolved entrance is required.")
	if not numbers(data.get("visit_spawn"), 3): errors.append("Invalid entrance spawn.")
	if not data.get("stairs") is Array or not data.stairs.is_empty(): errors.append("Stairs are not supported in the one-storey generator.")
	if not data.get("furniture") is Array:
		errors.append("Furniture must be an array.")
	else:
		for instance in data.furniture:
			if not instance is Dictionary:
				errors.append("Invalid furniture instance.")
				continue
			_register_id(instance, ids, errors)
			if not instance.get("catalogue_id") is String or instance.get("storey_id") != storeys[0].id or not numbers(instance.get("position"), 3) or not numbers([instance.get("yaw_degrees")], 1):
				errors.append("Invalid furniture reference or transform.")
	_validate_exterior(ids, errors)
	return errors

func is_grid_draft() -> bool:
	return is_grid_layout() and data.get("build_state") == "layout_draft"

func is_grid_layout() -> bool:
	return data.get("schema_version") == 2 and data.get("structure_mode") == "grid"

func has_grid_shell() -> bool:
	return is_grid_layout() and data.get("build_state") == "shell"

func _validate_grid_layout(errors: PackedStringArray) -> PackedStringArray:
	if not is_grid_layout() or not data.get("build_state") in ["layout_draft", "shell"] or not data.get("compiler_version") in GridBuildingCompiler.SUPPORTED_VERSIONS: errors.append("Unsupported grid authoring mode or compiler version.")
	if not data.get("storeys") is Array or data.storeys.size() != 1 or not data.storeys[0] is Dictionary:
		errors.append("A grid draft must contain one storey.")
		return errors
	var floor: Dictionary = data.storeys[0]
	if not valid_id(floor.get("id")) or floor.get("id") == data.get("id"): errors.append("Invalid grid storey ID.")
	if not numbers([floor.get("elevation"), floor.get("height")], 2) or floor.get("elevation") != 0 or float(floor.get("height", 0)) < 2.7 or float(floor.get("height", 0)) > 5: errors.append("Invalid grid storey elevation/height.")
	for field in ["rooms", "walls", "openings", "slabs"]:
		if not floor.get(field) is Array or floor[field].size() > 4096:
			errors.append("Invalid resolved " + field + ".")
		elif (is_grid_draft() or (field == "openings" and data.get("compiler_version",1) < 3) or (field == "rooms" and data.get("compiler_version") == 1)) and not floor[field].is_empty(): errors.append("This footprint must not contain stale resolved " + field + ".")
	for field in ["stairs", "exterior_components"]:
		if not data.get(field, []) is Array or not data.get(field, []).is_empty(): errors.append("Active " + field + " are unsupported in a footprint draft.")
	if (data.get("compiler_version",1) < 3 and data.get("entrance_id") != "") or not numbers(data.get("visit_spawn"), 3): errors.append("Invalid grid entrance or spawn.")
	var layout_errors := BuildingGridLayout.validate(floor.get("layout"))
	errors.append_array(layout_errors)
	if not errors.is_empty(): return errors
	if data.compiler_version >= 3:
		errors.append_array(GridBuildingOpenings.validate(floor.layout,float(floor.height)))
		if not errors.is_empty(): return errors
	elif floor.layout.has("openings") or floor.has("unresolved_openings"):
		errors.append("Opening authoring requires compiler version 3.")
	if data.compiler_version == 1 and not floor.layout.rooms.is_empty(): errors.append("Room painting requires compiler version 2.")
	var room_ids := {str(data.id):true,str(floor.id):true}
	for room in floor.layout.rooms: _register_id(room,room_ids,errors)
	for opening in floor.layout.get("openings",[]): _register_id(opening,room_ids,errors)
	if floor.get("layout_digest") != BuildingGridLayout.digest(floor.layout): errors.append("Grid layout digest mismatch; the source is preserved.")
	var box := BuildingGridLayout.bounds(BuildingGridLayout.cell_set(floor.layout.cells))
	var unit := float(floor.layout.cell_size)
	var expected := [float(floor.layout.origin[0]) + box.position.x * unit, float(floor.layout.origin[1]) + box.position.y * unit, box.size.x * unit, box.size.y * unit]
	if not numbers(floor.get("bounds"), 4):
		errors.append("Invalid grid bounds.")
	else:
		# JSON parsing may differ by a floating-point ULP at a converted origin.
		for index in 4:
			if absf(float(floor.bounds[index])-float(expected[index])) > 0.000000001: errors.append("Grid bounds disagree with painted cells.")
	if not data.get("parameters") is Dictionary or data.parameters.get("width") != expected[2] or data.parameters.get("depth") != expected[3] or data.parameters.get("storey_height") != floor.height: errors.append("Grid summary parameters disagree with the layout.")
	if has_grid_shell(): errors.append_array(GridBuildingCompiler.validate_shell(data))
	else:
		if floor.has("resolved_digest"): errors.append("A draft must not retain a stale shell digest.")
		if data.compiler_version >= 3: errors.append_array(GridBuildingOpenings.validate_resolved(data))
	if data.has("conversion_source"):
		if not data.conversion_source is Dictionary or data.conversion_source.get("schema_version") != 1:
			errors.append("Invalid preserved conversion source.")
		else:
			errors.append_array(BuildingDefinition.new(data.conversion_source).validate())
	return errors

func _validate_exterior(ids: Dictionary, errors: PackedStringArray) -> void:
	errors.append_array(BuildingRoofEnvelope.validate(data))
	var components: Variant = data.get("exterior_components", [])
	if not components is Array or components.size() > 4096:
		errors.append("Invalid exterior component collection.")
		return
	for component in components:
		if not component is Dictionary:
			errors.append("Invalid exterior component.")
			continue
		_register_id(component, ids, errors)
		if component.has("storey_id") and (not component.storey_id is String or data.storeys.filter(func(level: Dictionary) -> bool: return level.id == component.storey_id).is_empty()): errors.append("Exterior component refers to a missing storey.")
		if component.has("hide_in_cutaway") and not component.hide_in_cutaway is bool: errors.append("Invalid exterior cutaway visibility.")
		if component.has("collision_only") and not component.collision_only is bool: errors.append("Invalid collision-only component flag.")
		if component.has("tile_weathering") and (not numbers([component.tile_weathering],1) or component.tile_weathering < 0 or component.tile_weathering > 1): errors.append("Invalid roof weathering.")
		if not component.get("slot") in SURFACE_SLOTS or not component.get("kind") in ["box", "mesh", "cylinder"] or not numbers(component.get("position"), 3) or not numbers(component.get("rotation_degrees", [0,0,0]), 3) or not component.get("collision", true) is bool:
			errors.append("Invalid exterior component transform or surface.")
			continue
		if component.has("colour") and (not component.colour is String or not Color.html_is_valid(component.colour)):
			errors.append("Invalid component colour.")
		if component.kind in ["box", "cylinder"]:
			if not numbers(component.get("size"), 3) or vector(component.size).x <= 0 or vector(component.size).y <= 0 or vector(component.size).z <= 0:
				errors.append("Invalid exterior primitive size.")
		else:
			var vertices: Variant = component.get("vertices")
			var indices: Variant = component.get("indices")
			if not vertices is Array or vertices.size() < 3 or vertices.size() > 32768 or not indices is Array or indices.is_empty() or indices.size() % 3 != 0 or indices.size() > 196608:
				errors.append("Invalid exterior mesh.")
				continue
			for point in vertices:
				if not numbers(point, 3): errors.append("Invalid exterior mesh vertex.")
			for index in indices:
				if not numbers([index],1) or float(index) != floor(float(index)) or index < 0 or index >= vertices.size(): errors.append("Invalid exterior mesh index.")

static func _register_id(record: Dictionary, ids: Dictionary, errors: PackedStringArray) -> void:
	var id: Variant = record.get("id")
	if not valid_id(id) or ids.has(id):
		errors.append("Missing, invalid or duplicate element ID: " + str(id))
	else:
		ids[id] = true

func _validate_contents() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids := {str(data.get("id","")):true}
	var storey_ids := {}
	var levels: Variant = data.get("storeys")
	if not levels is Array: return PackedStringArray(["Invalid storey collection."])
	for level in levels:
		if not level is Dictionary: continue
		ids[str(level.get("id",""))] = true
		storey_ids[str(level.get("id",""))] = true
		for field in ["rooms","walls","openings","slabs"]:
			if not level.get(field) is Array: continue
			for record in level.get(field,[]):
				if record is Dictionary: ids[str(record.get("id",""))] = true
		var layout: Variant = level.get("layout",{})
		if layout is Dictionary:
			for field in ["rooms","openings"]:
				if not layout.get(field) is Array: continue
				for record in layout[field]:
					if record is Dictionary: ids[str(record.get("id",""))] = true
	var stairs: Variant = data.get("stairs")
	if not stairs is Array: return PackedStringArray(["Invalid stair collection."])
	for stair in stairs:
		if stair is Dictionary: ids[str(stair.get("id",""))] = true
	if not data.get("furniture") is Array or data.furniture.size() > 512: return PackedStringArray(["Invalid furniture collection (maximum 512 instances)."])
	for item in data.furniture:
		if not item is Dictionary: return PackedStringArray(["Invalid furniture record."])
		_register_id(item,ids,errors)
		if not item.get("catalogue_id") is String or str(item.catalogue_id).is_empty() or not storey_ids.has(item.get("storey_id")) or not numbers(item.get("position"),3) or not numbers([item.get("yaw_degrees")],1): errors.append("Invalid furniture reference or transform.")
		if item.has("attachment") and not item.attachment in ["floor","ceiling","wall"]: errors.append("Invalid furniture attachment.")
		if item.has("furnishing"):
			var provenance: Variant = item.furnishing
			if not provenance is Dictionary or provenance.get("generator") != "room-furnishing" or provenance.get("version") != 1 or not valid_id(provenance.get("room_id")) or not provenance.get("slot") is int or provenance.slot < 0 or provenance.slot > 16: errors.append("Invalid furnishing provenance.")
		for flag in ["allow_overlap","needs_repositioning"]:
			if item.has(flag) and not item[flag] is bool: errors.append("Invalid furniture flag.")
		_validate_material_map(item.get("material_overrides",{}),BuildingMaterials.FURNITURE_SLOTS,errors)
	_validate_material_map(data.get("material_presets",{}),SURFACE_SLOTS,errors)
	_validate_material_map(data.get("furniture_materials",{}),BuildingMaterials.FURNITURE_SLOTS,errors)
	var scoped: Variant = data.get("storey_materials",{})
	if not scoped is Dictionary: errors.append("Invalid storey material map.")
	else:
		for id in scoped:
			if not storey_ids.has(id): errors.append("Material scope refers to a missing storey.")
			_validate_material_map(scoped[id],SURFACE_SLOTS,errors)
	return errors

static func _validate_material_map(values: Variant, slots: Array, errors: PackedStringArray) -> void:
	if not values is Dictionary:
		errors.append("Invalid material map.")
		return
	for slot in values:
		if not slot in slots or not BuildingMaterials.valid(values[slot]): errors.append("Invalid material slot or preset.")
