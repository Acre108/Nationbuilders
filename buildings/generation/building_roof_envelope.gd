class_name BuildingRoofEnvelope
extends RefCounted

## Resolved roof faces, shared by shell walls, ceilings and clearance checks.
## No photo settings or source annotations are interpreted at runtime.
var surfaces: Array = []
var storeys: Array = []
var skylights: Array = []
var bins: Dictionary = {}
var resolved: Array = []
var resolved_bins: Dictionary = {}

func _init(data: Dictionary) -> void:
	var record: Dictionary = data.get("roof_envelope",{})
	storeys = record.get("storey_ids",[])
	skylights = record.get("skylights",[])
	for saved in record.get("resolved_faces",[]):
		var triangle: Array = saved.map(func(point: Array) -> Vector3: return BuildingDefinition.vector(point))
		var box := Rect2(Vector2(triangle[0].x,triangle[0].z),Vector2.ZERO)
		for p: Vector3 in triangle: box = box.expand(Vector2(p.x,p.z))
		var index := resolved.size()
		resolved.append(triangle)
		for z in range(floori(box.position.y),ceili(box.end.y)+1):
			for x in range(floori(box.position.x),ceili(box.end.x)+1):
				var key := Vector2i(x,z)
				if not resolved_bins.has(key): resolved_bins[key] = []
				resolved_bins[key].append(index)
	for saved in record.get("faces",[]):
		var face: Array[Vector3] = []
		for point in saved: face.append(BuildingDefinition.vector(point))
		var normal := (face[1]-face[0]).cross(face[2]-face[0])
		if absf(normal.y) < 0.0001: continue
		var polygon := PackedVector2Array()
		for point in face: polygon.append(Vector2(point.x,point.z))
		var box := Rect2(polygon[0],Vector2.ZERO)
		for point in polygon: box = box.expand(point)
		var index := surfaces.size()
		surfaces.append({"face":face,"normal":normal,"polygon":polygon,"bounds":box})
		for z in range(floori(box.position.y),ceili(box.end.y)+1):
			for x in range(floori(box.position.x),ceili(box.end.x)+1):
				var key := Vector2i(x,z)
				if not bins.has(key): bins[key] = []
				bins[key].append(index)

func applies(id: String) -> bool:
	return id in storeys

func resolved_in(rect: Rect2) -> Array:
	var candidates := {}
	for z in range(floori(rect.position.y),ceili(rect.end.y)+1):
		for x in range(floori(rect.position.x),ceili(rect.end.x)+1):
			for index in resolved_bins.get(Vector2i(x,z),[]): candidates[index] = true
	var result: Array = []
	for index in candidates: result.append(resolved[index])
	return result

func height_at(point: Vector2) -> float:
	var result := -INF
	for index in bins.get(Vector2i(point.floor()),[]):
		var surface: Dictionary = surfaces[index]
		if not Geometry2D.is_point_in_polygon(point,surface.polygon): continue
		var a: Vector3 = surface.face[0]
		var n: Vector3 = surface.normal
		result = maxf(result,a.y-(n.x*(point.x-a.x)+n.z*(point.y-a.z))/n.y)
	return result

func standing_barriers(level: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if not applies(level.id): return result
	var unit := float(level.layout.cell_size)
	var origin := Vector2(float(level.layout.origin[0]),float(level.layout.origin[1]))
	var required := float(level.elevation)+VisitorController.HEIGHT+0.18
	for saved in level.layout.cells:
		var low := origin+Vector2(float(saved[0]),float(saved[1]))*unit
		var height := height_at(low+Vector2.ONE*unit/2)
		if is_finite(height) and height < required: result.append(Rect2(low,Vector2.ONE*unit))
	return result

static func subtract_convex(polygon: PackedVector2Array,cover: PackedVector2Array) -> Array:
	# Partition the difference into convex pieces. Geometry2D.clip_polygons
	# may return a separate hole ring, which must never be filled as a face.
	# Disjoint cuts must leave the face intact. Partitioning by their infinite
	# edge lines otherwise fragments roofs into thousands of needless pieces.
	if polygon.size() < 3: return []
	if cover.size() < 3 or Geometry2D.intersect_polygons(polygon,cover).is_empty(): return [polygon]
	var remaining := polygon
	var outside: Array = []
	var center := Vector2.ZERO
	for p in cover: center += p/cover.size()
	for i in cover.size():
		var a := cover[i]
		var edge := cover[(i+1)%cover.size()]-a
		var sign := 1.0 if edge.cross(center-a) >= 0 else -1.0
		var inner := PackedVector2Array()
		var outer := PackedVector2Array()
		for j in remaining.size():
			var p := remaining[j]
			var q := remaining[(j+1)%remaining.size()]
			var dp := edge.cross(p-a)*sign
			var dq := edge.cross(q-a)*sign
			if dp >= 0: inner.append(p)
			if dp <= 0: outer.append(p)
			if (dp > 0 and dq < 0) or (dp < 0 and dq > 0):
				var crossing := p.lerp(q,dp/(dp-dq))
				inner.append(crossing)
				outer.append(crossing)
		if outer.size() >= 3 and absf(_area(outer)) > 0.000001: outside.append(outer)
		remaining = inner
		if remaining.size() < 3: break
	return outside

static func _area(polygon: PackedVector2Array) -> float:
	var result := 0.0
	for i in polygon.size(): result += polygon[i].cross(polygon[(i+1)%polygon.size()])
	return result/2

static func validate(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var profiles: Variant = data.get("opening_profiles",{})
	if not profiles is Dictionary: return PackedStringArray(["Invalid opening profiles."])
	if data.has("preview_inspection_light") and not data.preview_inspection_light is bool: errors.append("Invalid inspection light setting.")
	var links: Variant = data.get("exterior_opening_links",[])
	if not links is Array or links.size() > 512: errors.append("Invalid exterior window links.")
	else:
		var ids := {}
		var windows := {}
		for level in data.storeys:
			for opening in level.openings:
				if opening.kind == "window": windows[opening.id] = true
		for link in links:
			if not link is Dictionary or not windows.has(link.get("opening_id")) or ids.has(link.get("opening_id")) or not BuildingDefinition.numbers(link.get("inner"),3) or not BuildingDefinition.numbers(link.get("outer"),3):
				errors.append("Exterior window link requires a unique existing window and finite endpoints.")
				continue
			ids[link.opening_id] = true
			var inside := BuildingDefinition.vector(link.inner)
			var outside := BuildingDefinition.vector(link.outer)
			if absf(inside.y-outside.y) > 0.001 or inside.distance_to(outside) < 0.01: errors.append("Exterior window links must be horizontal nonzero recesses.")
	for id in profiles:
		var found := false
		for level in data.storeys:
			for opening in level.openings:
				if opening.id == id and opening.kind == "window" and profiles[id] == "circle" and absf(float(opening.width)-float(opening.height)) < 0.0001: found = true
		if not found: errors.append("Circular profile requires an existing square window opening.")
	if not data.has("roof_envelope"): return errors
	var value: Variant = data.roof_envelope
	if not value is Dictionary or value.get("version") != 1 or not value.get("storey_ids") is Array or not value.get("faces") is Array or value.faces.size() > 4096 or not value.get("skylights",[]) is Array:
		return PackedStringArray(["Invalid resolved roof envelope."])
	for id in value.storey_ids:
		if not id is String or BuildingStoreys.level_index(data,id) < 0: errors.append("Roof envelope refers to a missing storey.")
	for face in value.faces:
		if not face is Array or face.size() < 3 or face.size() > 64: errors.append("Invalid roof envelope face."); continue
		for point in face:
			if not BuildingDefinition.numbers(point,3): errors.append("Invalid roof envelope vertex.")
		if errors.is_empty() and absf((BuildingDefinition.vector(face[1])-BuildingDefinition.vector(face[0])).cross(BuildingDefinition.vector(face[2])-BuildingDefinition.vector(face[0])).y) < 0.00001: errors.append("Roof envelope faces must project to nondegenerate floor areas.")
	var resolved_faces: Variant = value.get("resolved_faces",[])
	if not resolved_faces is Array or resolved_faces.size() > 32768: errors.append("Invalid resolved roof surfaces.")
	else:
		for face in resolved_faces:
			if not face is Array or face.size() != 3: errors.append("Invalid resolved roof triangle."); continue
			for point in face:
				if not BuildingDefinition.numbers(point,3): errors.append("Invalid resolved roof vertex.")
	for rect in value.get("skylights",[]):
		if not BuildingDefinition.numbers(rect,4) or rect[2] <= 0 or rect[3] <= 0: errors.append("Invalid roof envelope skylight.")
	if data.has("visit_ground_elevation") and (not BuildingDefinition.numbers([data.visit_ground_elevation],1) or data.visit_ground_elevation < -5 or data.visit_ground_elevation > 0): errors.append("Invalid visit ground elevation.")
	if data.has("visit_ground_start_z") and not BuildingDefinition.numbers([data.visit_ground_start_z],1): errors.append("Invalid visit forecourt boundary.")
	return errors
