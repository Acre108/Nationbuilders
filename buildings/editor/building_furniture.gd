class_name BuildingFurniture
extends RefCounted

## Full occupied visual/collision bounds, independent of ground footprints.
static func level(data: Dictionary, id: String) -> Dictionary:
	for storey in data.storeys:
		if storey.id == id: return storey
	return {}

static func instance(data: Dictionary, id: String) -> Dictionary:
	for item in data.furniture:
		if item.id == id: return item
	return {}

static func polygon(box: AABB, at: Vector3, yaw: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for corner in [Vector2(box.position.x,box.position.z),Vector2(box.end.x,box.position.z),Vector2(box.end.x,box.end.z),Vector2(box.position.x,box.end.z)]:
		var rotated := Vector3(corner.x,0,corner.y).rotated(Vector3.UP,deg_to_rad(yaw))+at
		result.append(Vector2(rotated.x,rotated.z))
	return result

static func rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])

static func area(points: PackedVector2Array) -> float:
	var sum := 0.0
	for i in points.size(): sum += points[i].cross(points[(i+1)%points.size()])
	return absf(sum)/2

static func intersection(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var sum := 0.0
	for piece in Geometry2D.intersect_polygons(a,b): sum += area(piece)
	return sum

static func occupied(item: Dictionary) -> PackedVector2Array:
	return polygon(FurnitureRuntime.bounds(item.catalogue_id),BuildingDefinition.vector(item.position),float(item.yaw_degrees))

static func vertical(item: Dictionary) -> Vector2:
	var box := FurnitureRuntime.bounds(item.catalogue_id)
	return Vector2(float(item.position[1])+box.position.y,float(item.position[1])+box.end.y)

static func candidate(data: Dictionary, storey_id: String, catalogue_id: String, point: Vector2, yaw: float, id: String = "") -> Dictionary:
	var storey := level(data,storey_id)
	var box := FurnitureRuntime.bounds(catalogue_id)
	var attach := FurnitureRuntime.attachment(catalogue_id)
	var height := float(storey.height)-box.end.y if attach == "ceiling" else -box.position.y
	var result := instance(data,id).duplicate(true)
	result.merge({"id":id if not id.is_empty() else "furniture-"+Crypto.new().generate_random_bytes(12).hex_encode(),"catalogue_id":catalogue_id,"storey_id":storey_id,"position":[point.x,height,point.y],"yaw_degrees":yaw,"attachment":attach},true)
	if attach == "wall":
		var nearest := INF
		for wall in storey.walls:
			var a := Vector2(float(wall.from[0]),float(wall.from[2]))
			var b := Vector2(float(wall.to[0]),float(wall.to[2]))
			var anchor := Geometry2D.get_closest_point_to_segment(point,a,b)
			var distance := anchor.distance_to(point)
			if distance >= nearest: continue
			var direction := (b-a).normalized()
			var normal := Vector2(-direction.y,direction.x)
			if wall.get("kind") != "partition": normal *= -float(wall.get("exterior_side",1))
			elif (point-anchor).dot(normal) < 0: normal = -normal
			var mount := anchor+normal*(float(wall.thickness)/2+box.end.z+0.005)
			result.position = [mount.x,0.0,mount.y]
			result.yaw_degrees = rad_to_deg(atan2(-normal.x,-normal.y))
			result.wall_id = wall.id
			nearest = distance
	return result

## Slabs a placement rests on. Floor items stand on the storey's floor slabs.
## Ceiling items hang from its own ceiling slab where it has one (the top
## storey, under its roof); below that the ceiling is the floor of the storey
## above, split around any stair opening.
static func _support_slabs(data: Dictionary, storey: Dictionary, attachment: String) -> Array:
	if attachment != "ceiling":
		var supports: Array = storey.slabs.filter(func(slab: Dictionary) -> bool: return slab.slot == "floor")
		if data.get("compiler_version") == 5 and data.storeys.find(storey) == 0:
			for component in data.get("exterior_components",[]):
				if component.kind == "box" and component.slot == "floor" and component.get("collision",true) and component.get("rotation_degrees",[0,0,0]) == [0,0,0] and absf(float(component.position[1])+float(component.size[1])/2) < 0.005:
					supports.append({"center":component.position,"size":component.size,"slot":"floor"})
		return supports
	var own: Array = storey.slabs.filter(func(slab: Dictionary) -> bool: return slab.slot == "ceiling")
	if not own.is_empty(): return own
	var index: int = data.storeys.find(storey)
	if index < 0 or index + 1 >= data.storeys.size(): return []
	return data.storeys[index + 1].slabs.filter(func(slab: Dictionary) -> bool: return slab.slot == "floor")

static func report(data: Dictionary, item: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var overlaps := PackedStringArray()
	var storey := level(data,str(item.storey_id))
	if storey.is_empty(): return {"errors":PackedStringArray(["Furniture has no storey."]),"overlaps":overlaps}
	if not FurnitureRuntime.catalogue().has_object(item.catalogue_id): return {"errors":errors,"overlaps":overlaps}
	var poly := occupied(item)
	var span := vertical(item)
	if span.x < -0.005 or span.y > float(storey.height)+0.005: errors.append("Furniture extends below the floor or above the ceiling.")
	var attachment := str(item.get("attachment",FurnitureRuntime.attachment(item.catalogue_id)))
	if not attachment in ["floor","ceiling","wall"]: errors.append("This furniture attachment is not supported.")
	if attachment == "wall" and not _wall_supported(storey,item,poly): errors.append("Keep the back of wall furniture attached to a solid wall face.")
	if (attachment == "floor" and absf(span.x) > 0.005) or (attachment == "ceiling" and absf(span.y-float(storey.height)) > 0.005): errors.append("Furniture must remain on its attachment surface.")
	var covered := 0.0
	for slab in _support_slabs(data,storey,attachment):
		var center := BuildingDefinition.vector(slab.center)
		var size := BuildingDefinition.vector(slab.size)
		covered += intersection(poly,rect_polygon(Rect2(Vector2(center.x-size.x/2,center.z-size.z/2),Vector2(size.x,size.z))))
	if covered < area(poly)-0.0001: errors.append("Occupied bounds leave the supporting surface or cross a stair opening.")
	for wall in storey.walls:
		var start := BuildingDefinition.vector(wall.from)
		var end := BuildingDefinition.vector(wall.to)
		var direction := (end-start).normalized()
		var length := start.distance_to(end)
		var cuts: Array = []
		for opening in storey.openings:
			if opening.wall_id == wall.id: cuts.append(opening)
		cuts.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.offset < b.offset)
		var cursor := 0.0
		for opening in cuts:
			var left := float(opening.offset)-float(opening.width)/2
			var right := float(opening.offset)+float(opening.width)/2
			if _wall_overlap(poly,span,start,direction,cursor,left,0,float(wall.height),float(wall.thickness)) or _wall_overlap(poly,span,start,direction,left,right,0,float(opening.bottom),float(wall.thickness)) or _wall_overlap(poly,span,start,direction,left,right,float(opening.bottom)+float(opening.height),float(wall.height),float(wall.thickness)):
				errors.append("Occupied bounds intersect wall " + str(wall.id))
			if opening.kind == "window" and _wall_overlap(poly,span,start,direction,left,right,float(opening.bottom),float(opening.bottom)+float(opening.height),0.04): errors.append("Occupied bounds intersect window glazing.")
			if opening.kind != "window" and span.x < 1.8:
				var route := AABB(Vector3(-float(opening.width)/2-0.3,0,-1.2),Vector3(float(opening.width)+0.6,1.8,2.4))
				if intersection(poly,polygon(route,start+direction*float(opening.offset),rad_to_deg(-atan2(direction.z,direction.x)))) > 0.00001: errors.append("Keep the doorway and its approach clear.")
			cursor = right
		if _wall_overlap(poly,span,start,direction,cursor,length,0,float(wall.height),float(wall.thickness)): errors.append("Occupied bounds intersect wall " + str(wall.id))
	for stair in data.stairs:
		if item.storey_id in [stair.from_storey,stair.to_storey] and intersection(poly,rect_polygon(BuildingStoreys.reservation(stair).grow(0.07))) > 0.00001: errors.append("Keep stairs, headroom and landings clear.")
	for other in data.furniture:
		if other.id == item.id or other.storey_id != item.storey_id: continue
		var other_span := vertical(other)
		if span.x < other_span.y-0.001 and span.y > other_span.x+0.001 and intersection(poly,occupied(other)) > 0.00001: overlaps.append(str(other.id))
	return {"errors":errors,"overlaps":overlaps}

static func _wall_supported(storey: Dictionary, item: Dictionary, poly: PackedVector2Array) -> bool:
	var backing := Vector3.BACK.rotated(Vector3.UP,deg_to_rad(float(item.yaw_degrees)))
	var back := Vector2(backing.x,backing.z)
	var span := vertical(item)
	for wall in storey.walls:
		var a := Vector2(float(wall.from[0]),float(wall.from[2]))
		var b := Vector2(float(wall.to[0]),float(wall.to[2]))
		var direction := (b-a).normalized()
		if absf(back.dot(direction)) > 0.001: continue
		var near := -INF
		var low := INF
		var high := -INF
		for point in poly:
			near = maxf(near,(point-a).dot(back))
			low = minf(low,(point-a).dot(direction))
			high = maxf(high,(point-a).dot(direction))
		if absf(near+float(wall.thickness)/2+0.005) > 0.01 or low < 0.001 or high > a.distance_to(b)-0.001: continue
		var solid := true
		for opening in storey.openings:
			if opening.wall_id == wall.id and low < float(opening.offset)+float(opening.width)/2 and high > float(opening.offset)-float(opening.width)/2 and span.x < float(opening.bottom)+float(opening.height) and span.y > float(opening.bottom): solid = false
		if solid: return true
	return false

static func _wall_overlap(poly: PackedVector2Array, span: Vector2, start: Vector3, direction: Vector3, left: float, right: float, bottom: float, top: float, thickness: float) -> bool:
	if right-left <= 0.001 or top-bottom <= 0.001 or span.x >= top-0.001 or span.y <= bottom+0.001: return false
	var box := AABB(Vector3(left,bottom,-thickness/2),Vector3(right-left,top-bottom,thickness))
	return intersection(poly,polygon(box,start,rad_to_deg(-atan2(direction.z,direction.x)))) > 0.00001

static func conflicts(data: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	for item in data.furniture:
		var check := report(data,item)
		for error in check.errors: result.append("%s: %s" % [item.id,error])
		if not check.overlaps.is_empty() and not item.get("allow_overlap",false):
			# One explicit arrangement approval is sufficient for either partner.
			for id in check.overlaps:
				if not instance(data,id).get("allow_overlap",false): result.append("%s overlaps %s; review the arrangement." % [item.id,id])
	return result

static func barriers(data: Dictionary, storey_id: String) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for item in data.furniture:
		if item.storey_id != storey_id: continue
		for collider in FurnitureRuntime.catalogue().object_data(item.catalogue_id).get("colliders",[]):
			var center := FurnitureRuntime.xyz(collider.center)
			var size := FurnitureRuntime.xyz(collider.size)
			if center.y+size.y/2+float(item.position[1]) <= 0.05 or center.y-size.y/2+float(item.position[1]) >= 1.8: continue
			var box := Transform3D(Basis(Vector3.UP,deg_to_rad(float(collider.get("yaw",0)))),Vector3.ZERO)*AABB(center-size/2,size)
			var points := polygon(box,BuildingDefinition.vector(item.position),float(item.yaw_degrees))
			var rect := Rect2(points[0],Vector2.ZERO)
			for point in points: rect = rect.expand(point)
			result.append(rect)
	return result
