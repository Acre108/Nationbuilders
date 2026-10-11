class_name BuildingLightingZones
extends RefCounted

## Weather/audio volumes from resolved horizontal floors and ceilings. Slab
## rectangles and authored mesh triangles preserve concave footprints exactly.
static func create(definition: BuildingDefinition, placement: Transform3D = Transform3D.IDENTITY,
	cutaway: bool = false) -> Array[AtmosphereZone]:
	var zones: Array[AtmosphereZone] = []
	if cutaway or definition.is_grid_draft(): return zones
	var floors: Array = []
	var ceilings: Array = []
	for storey in definition.data.storeys:
		for slab in storey.slabs:
			if slab.slot == "floor": floors.append_array(_slab(slab,float(storey.elevation),true))
			if slab.slot == "floor" and definition.data.get("compiler_version") in [4,5] and float(storey.elevation) > 0: ceilings.append_array(_slab(slab,float(storey.elevation),false))
			if slab.slot == "ceiling": ceilings.append_array(_slab(slab,float(storey.elevation),false))
	for component in definition.data.get("exterior_components",[]):
		if not component.slot in ["floor","ceiling"]: continue
		var surfaces := _component(component,component.slot == "floor")
		if component.slot == "floor": floors.append_array(surfaces)
		else: ceilings.append_array(surfaces)
	ceilings.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.height < b.height)
	for floor_surface in floors:
		var remaining: Array[PackedVector2Array] = [floor_surface.polygon]
		for ceiling in ceilings:
			if ceiling.height <= floor_surface.height: continue
			var next: Array[PackedVector2Array] = []
			for uncovered in remaining:
				for polygon in Geometry2D.intersect_polygons(uncovered,ceiling.polygon):
					if polygon.size() < 3 or absf(_area(polygon)) < 0.002: continue
					var zone := AtmosphereZone.new()
					zone.label = str(definition.data.id)+" / "+str(floor_surface.id)
					zone.height_bounded = true
					zone.min_height = (placement*Vector3(0,floor_surface.height,0)).y
					zone.max_height = (placement*Vector3(0,ceiling.height,0)).y
					for corner in polygon:
						var world: Vector3 = placement*Vector3(corner.x,floor_surface.height,corner.y)
						zone.area.append(Vector2(world.x,world.z))
					zones.append(zone)
				next.append_array(Geometry2D.clip_polygons(uncovered,ceiling.polygon))
			remaining = next
			if remaining.is_empty(): break
	return zones

static func _slab(record: Dictionary,elevation: float,floor_surface: bool) -> Array:
	var center := BuildingDefinition.vector(record.center)+Vector3.UP*elevation
	var size := BuildingDefinition.vector(record.size)
	var half := Vector2(size.x,size.z)/2
	var point := Vector2(center.x,center.z)
	return [{"polygon":PackedVector2Array([point-half,point+Vector2(half.x,-half.y),point+half,point+Vector2(-half.x,half.y)]),
		"height":center.y+size.y/2*(1 if floor_surface else -1),"id":record.id}]

static func _component(record: Dictionary,floor_surface: bool) -> Array:
	var result: Array = []
	var angles := BuildingDefinition.vector(record.get("rotation_degrees",[0,0,0]))*PI/180.0
	var transform := Transform3D(Basis.from_euler(angles),BuildingDefinition.vector(record.position))
	if record.kind == "box":
		# Tilted boxes are not horizontal resolved floor/ceiling surfaces.
		if absf(angles.x)>0.0001 or absf(angles.z)>0.0001: return result
		var size := BuildingDefinition.vector(record.size)
		var height := size.y/2*(1 if floor_surface else -1)
		var polygon := PackedVector2Array()
		for corner in [Vector3(-size.x/2,height,-size.z/2),Vector3(size.x/2,height,-size.z/2),
			Vector3(size.x/2,height,size.z/2),Vector3(-size.x/2,height,size.z/2)]:
			var world: Vector3 = transform*corner
			polygon.append(Vector2(world.x,world.z))
		result.append({"polygon":polygon,"height":transform.origin.y+height,"id":record.id})
	elif record.kind == "mesh":
		for index in range(0,record.indices.size(),3):
			var a := transform*BuildingDefinition.vector(record.vertices[int(record.indices[index])])
			var b := transform*BuildingDefinition.vector(record.vertices[int(record.indices[index+1])])
			var c := transform*BuildingDefinition.vector(record.vertices[int(record.indices[index+2])])
			if maxf(a.y,maxf(b.y,c.y))-minf(a.y,minf(b.y,c.y))>0.001: continue
			var normal := (b-a).cross(c-a).y
			# Floor/ceiling metadata defines purpose; imported authoring can use
			# either winding with double-sided materials. Geometry stays unchanged.
			if absf(normal) < 0.0001: continue
			result.append({"polygon":PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)]),
				"height":a.y,"id":record.id})
	return result

static func _area(polygon: PackedVector2Array) -> float:
	var value := 0.0
	for i in polygon.size(): value += polygon[i].cross(polygon[(i+1)%polygon.size()])
	return value/2.0
