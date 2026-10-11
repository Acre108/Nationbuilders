class_name FoliageExclusions
extends RefCounted

## Main-thread post-scatter filtering. Cached worker results remain untouched,
## so removing/moving a building restores exactly the original vegetation.
signal changed(area: Rect2)
var _objects: Dictionary = {}

func place(id: StringName, footprints: Array[GrassCarver]) -> void:
	var area := _area(_objects.get(id,[]))
	_objects[id] = footprints.duplicate()
	var next := _area(footprints)
	changed.emit(next if area.size == Vector2.ZERO else area.merge(next))

func remove(id: StringName) -> void:
	if not _objects.has(id): return
	var area := _area(_objects[id])
	_objects.erase(id)
	changed.emit(area)

func contains(x: float,z: float) -> bool:
	for footprints in _objects.values():
		for footprint: GrassCarver in footprints:
			if footprint.contains(x,z): return true
	return false

func intersects(area: Rect2) -> bool:
	for footprints in _objects.values():
		for footprint: GrassCarver in footprints:
			if footprint.bounds().intersects(area): return true
	return false

func filter_buffer(group: Array, origin: Vector3) -> Array:
	if _objects.is_empty() or group[0] == 0: return group
	var source: PackedFloat32Array = group[1]
	var kept := PackedFloat32Array()
	for index in int(group[0]):
		var offset := index*16
		if not contains(origin.x+source[offset+3],origin.z+source[offset+11]):
			kept.append_array(source.slice(offset,offset+16))
	return [int(kept.size()/16),kept]

func filter_result(source: Dictionary,origin: Vector3,count_key: String,chunk_size: float = 64.0) -> Dictionary:
	if not intersects(Rect2(Vector2(origin.x,origin.z),Vector2.ONE*chunk_size)): return source
	var result := source.duplicate()
	result.groups = {}
	var count := 0
	for key in source.groups:
		var group := filter_buffer(source.groups[key],origin)
		if group[0] > 0: result.groups[key] = group
		count += int(group[0])
	if source.has("impostor"): result.impostor = filter_buffer(source.impostor,origin)
	if count_key == "shore":
		result.reeds = 0
		result.rocks = 0
		for key in result.groups:
			if key < 3: result.reeds += int(result.groups[key][0])
			else: result.rocks += int(result.groups[key][0])
	else: result[count_key] = count
	return result

static func _area(footprints: Array) -> Rect2:
	var area := Rect2()
	for footprint: GrassCarver in footprints:
		area = footprint.bounds() if area.size == Vector2.ZERO else area.merge(footprint.bounds())
	return area
