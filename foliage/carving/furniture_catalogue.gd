class_name FurnitureCatalogue
extends RefCounted

## Reads the furniture packs carried over from PlacesOS (content/furniture/*.json)
## and turns a placed object into grass footprints.
##
## Grass uses the footprint API. The building runtime consumes complete owned
## source records through object_data(), including seats, lights and components.
##
## Footprint source, in order:
##   1. Colliders whose underside is within GROUND_CONTACT of the object's
##      floor. A table's collider reaches the ground; a wall shelf's would not,
##      and grass under a shelf is correct.
##   2. If there are none, geometry nodes that touch the ground. This is for
##      rugs, which PlacesOS deliberately leaves non-colliding so they never
##      block movement -- but a rug on a lawn must still flatten the grass.
##
## Pack coordinates: object-local, Y up, metres, with each object's root at the
## origin and yaw zero (the PlacesOS exporter guarantees this). Yaw in the
## packs is in degrees.

const PACK_DIR := "res://content/furniture"
## Undersides lower than this count as resting on the ground.
const GROUND_CONTACT := 0.1

var _objects: Dictionary = {}   ## StringName -> Dictionary


static func load_default() -> FurnitureCatalogue:
	var catalogue := FurnitureCatalogue.new()
	catalogue.load_dir(PACK_DIR)
	return catalogue


func load_dir(path: String) -> int:
	var loaded := 0
	for file in DirAccess.get_files_at(path):
		if file.get_extension() == "json" and load_pack(path.path_join(file)):
			loaded += 1
	return loaded


func load_pack(path: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary) or not data.has("objects"):
		push_warning("FurnitureCatalogue: %s is not a furniture pack" % path)
		return false

	var colliders := {}
	for c in data.get("colliders", []):
		colliders[c["id"]] = c
	var nodes := {}
	for n in data.get("geometry", {}).get("nodes", []):
		nodes[n["id"]] = n

	for object in data["objects"]:
		var own_nodes: Array = []
		for id in object.get("nodeIds", []):
			if nodes.has(id):
				own_nodes.append(nodes[id])

		var local: Array = []
		for id in object.get("colliderIds", []):
			if colliders.has(id):
				var c: Dictionary = colliders[id]
				if _underside(c["center"], c["size"]) <= GROUND_CONTACT:
					local.append(_rect(c["center"], c["size"], 0.0))
		if local.is_empty():
			for n in own_nodes:
				if _underside(n["position"], n["size"]) <= GROUND_CONTACT:
					local.append(_rect(n["position"], n["size"], deg_to_rad(float(n.get("yaw", 0.0)))))

		_objects[StringName(object["id"])] = {
			"label": object.get("label", object["id"]),
			"pack": path.get_file(),
			"footprint": local,
			"nodes": own_nodes,
			"definition": object.duplicate(true),
			"colliders": _owned(data.get("colliders", []), object.get("colliderIds", [])),
			"interactables": _owned(data.get("interactables", []), object.get("interactableIds", [])),
			"lights": data.get("localLights", []).filter(func(entry: Dictionary) -> bool: return entry.get("fixtureObjectId") == object.id),
			"attribution": data.get("attribution", {}).duplicate(true),
		}
	return true


func has_object(object_id: StringName) -> bool:
	return _objects.has(object_id)


func object_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_objects.keys())
	return ids


func object_label(object_id: StringName) -> String:
	return _objects[object_id]["label"]


## Raw geometry nodes, for anything that wants to draw the object.
func object_nodes(object_id: StringName) -> Array:
	return _objects[object_id]["nodes"]

## Complete source records, independent of the grass footprint API.
func object_data(object_id: StringName) -> Dictionary:
	return _objects.get(object_id, {}).duplicate(true)

static func _owned(records: Array, ids: Array) -> Array:
	return records.filter(func(entry: Dictionary) -> bool: return entry.get("id") in ids).duplicate(true)


## World footprints for `object_id` placed at `position` with `yaw` (radians,
## Node3D.rotation.y sense). Empty if nothing it owns touches the ground.
func footprints(object_id: StringName, position: Vector3, yaw: float, margin := GrassCarver.DEFAULT_MARGIN) -> Array[GrassCarver]:
	var out: Array[GrassCarver] = []
	if not _objects.has(object_id):
		push_warning("FurnitureCatalogue: unknown object %s" % object_id)
		return out
	for rect in _objects[object_id]["footprint"]:
		# Same rotation Godot applies to a child of a node with rotation.y = yaw,
		# so the carved patch lines up with the drawn object by construction.
		var c: Vector3 = Vector3(rect["center"].x, 0.0, rect["center"].y).rotated(Vector3.UP, yaw)
		out.append(GrassCarver.new(
			Vector2(position.x + c.x, position.z + c.z),
			rect["half"],
			yaw + rect["yaw"],
			margin,
		))
	return out


static func _underside(center: Dictionary, size: Dictionary) -> float:
	return float(center["y"]) - float(size["y"]) * 0.5


static func _rect(center: Dictionary, size: Dictionary, yaw: float) -> Dictionary:
	return {
		"center": Vector2(float(center["x"]), float(center["z"])),
		"half": Vector2(float(size["x"]), float(size["z"])) * 0.5,
		"yaw": yaw,
	}
