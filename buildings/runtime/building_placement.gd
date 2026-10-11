class_name BuildingPlacement
extends RefCounted

const MAX_RELIEF := 1.5
const SAMPLE_SPACING := 0.5
## Entrance steps: a walkable ramp from the threshold down to the ground in
## front of the visit spawn, so a raised plinth can be walked into (Studio S3).
const RAMP_SLOPE_DEGREES := 25.0
const RAMP_WIDTH := 1.8
const RAMP_MIN_DROP := 0.08
## Flat landing at floor height across the threshold before the slope.
const RAMP_LANDING := 0.6

static func record_errors(record: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not record is Dictionary: return PackedStringArray(["Building instance must be an object."])
	for key in record:
		if not key in ["instance_id","building","source_building_id","xz","yaw_degrees","foundation","replaces","basis","history"]: errors.append("Unknown building instance field: "+str(key))
	if not BuildingDefinition.valid_id(record.get("instance_id")): errors.append("Invalid building instance_id.")
	if not BuildingSnapshotStore.valid_path(record.get("building")): errors.append("Building instance requires an immutable pinned snapshot path.")
	if not BuildingDefinition.valid_id(record.get("source_building_id")): errors.append("Invalid source_building_id.")
	if not BuildingDefinition.numbers(record.get("xz"),2) or not BuildingDefinition.numbers([record.get("yaw_degrees")],1): errors.append("Building placement coordinates/yaw must be finite.")
	if BuildingDefinition.numbers(record.get("xz"),2):
		if absf(float(record.xz[0])) > 1000000.0 or absf(float(record.xz[1])) > 1000000.0: errors.append("Building coordinates exceed the supported world range.")
	if BuildingDefinition.numbers([record.get("yaw_degrees")],1) and absf(float(record.yaw_degrees)) > 360000.0: errors.append("Building yaw exceeds the supported range.")
	var foundation: Variant = record.get("foundation")
	if not foundation is Dictionary or foundation.get("mode") != "plinth" or not BuildingDefinition.numbers([foundation.get("above_front_ground")],1):
		errors.append("Building foundation requires plinth mode and a finite above_front_ground.")
	elif float(foundation.above_front_ground) < 0.0 or float(foundation.above_front_ground) > 0.5:
		errors.append("Foundation clearance must be 0-0.5 metres above the highest ground sample.")
	if foundation is Dictionary:
		for key in foundation:
			if not key in ["mode","above_front_ground"]: errors.append("Unknown foundation field: "+str(key))
	if not record.get("replaces",[]) is Array: errors.append("replaces must be an array of source IDs.")
	else:
		var seen := {}
		for id in record.get("replaces",[]):
			if not id is String or id.is_empty() or seen.has(id): errors.append("replaces contains an invalid or duplicate source ID.")
			seen[id] = true
	if not record.get("basis","") is String: errors.append("Placement basis must be text.")
	return errors

## Ground-contact surfaces only. Upper floors, roofs and furniture never clear
## the terrain. Separate rectangles/triangles preserve an L-shaped outside corner.
static func ground_surfaces(definition: BuildingDefinition) -> Array:
	var surfaces: Array = []
	var lowest := INF
	for storey in definition.data.storeys:
		lowest = minf(lowest,float(storey.elevation))
	for storey in definition.data.storeys:
		if not is_equal_approx(float(storey.elevation),lowest): continue
		for slab in storey.slabs:
			if slab.slot == "floor": surfaces.append_array(BuildingLightingZones._slab(slab,float(storey.elevation),true))
	for component in definition.data.get("exterior_components",[]):
		if component.slot == "floor": surfaces.append_array(BuildingLightingZones._component(component,true))
	var height := INF
	for surface in surfaces: height = minf(height,float(surface.height))
	return surfaces.filter(func(surface: Dictionary) -> bool: return absf(float(surface.height)-height) < 0.05)

static func prepare(record: Dictionary, terrain: TerrainProvider) -> Dictionary:
	var errors := record_errors(record)
	if not errors.is_empty(): return {"ok":false,"error":"; ".join(errors)}
	if terrain == null: return {"ok":false,"error":"Building placement requires terrain."}
	var loaded := BuildingSnapshotStore.load_pin(record.building)
	if not loaded.ok: return loaded
	var definition: BuildingDefinition = loaded.definition
	if definition.data.id != record.source_building_id: return {"ok":false,"error":"Pinned design does not match source_building_id."}
	return prepare_definition(definition,record,terrain)

## Validates a design at a pose without a pin (Studio's placement ghost).
## `record` needs xz, yaw_degrees and foundation.
static func prepare_definition(definition: BuildingDefinition, record: Dictionary, terrain: TerrainProvider) -> Dictionary:
	if terrain == null: return {"ok":false,"error":"Building placement requires terrain."}
	var surfaces := ground_surfaces(definition)
	if surfaces.is_empty(): return {"ok":false,"error":"Building has no supported ground-floor surfaces."}
	var transform := Transform3D(Basis(Vector3.UP,deg_to_rad(float(record.yaw_degrees))),Vector3(record.xz[0],0,record.xz[1]))
	var low := INF
	var high := -INF
	var footprints: Array[GrassCarver] = []
	for surface in surfaces:
		var polygon := PackedVector2Array()
		for corner: Vector2 in surface.polygon:
			var point := transform*Vector3(corner.x,0,corner.y)
			polygon.append(Vector2(point.x,point.z))
		var footprint := PolygonGrassCarver.new(polygon,0.25)
		footprints.append(footprint)
		var bounds := footprint.bounds()
		if terrain is HeightmapTerrainProvider:
			for point in polygon:
				if not terrain._bounds.grow(0.001).has_point(point): return {"ok":false,"error":"Building footprint lies outside the terrain crop."}
		var samples := polygon.duplicate()
		for index in polygon.size():
			var a := polygon[index]
			var b := polygon[(index+1)%polygon.size()]
			var steps := maxi(1,ceili(a.distance_to(b)/SAMPLE_SPACING))
			for step in steps: samples.append(a.lerp(b,float(step)/steps))
		for x in range(ceili(bounds.size.x/SAMPLE_SPACING)+1):
			for z in range(ceili(bounds.size.y/SAMPLE_SPACING)+1):
				var point := bounds.position + Vector2(x,z)*SAMPLE_SPACING
				if footprint.contains(point.x,point.y): samples.append(point)
		for point in samples:
			if terrain.water_cover(point.x,point.y) > 0.01 or not terrain.water_sample(point.x,point.y,0.25).is_empty():
				return {"ok":false,"error":"Building footprint intersects water or its bank clearance."}
			var height := terrain.get_height(point.x,point.y)
			if not is_finite(height): return {"ok":false,"error":"Terrain does not provide finite support beneath the whole footprint."}
			low = minf(low,height)
			high = maxf(high,height)
	if high-low > MAX_RELIEF: return {"ok":false,"error":"Terrain relief %.2f m exceeds the %.1f m plinth limit." % [high-low,MAX_RELIEF]}
	transform.origin.y = high+float(record.foundation.above_front_ground)-float(surfaces[0].height)
	return {"ok":true,"definition":definition,"transform":transform,"surfaces":surfaces,"footprints":footprints,"low":low,"high":high,"entrance":entrance_ramp(definition,surfaces,transform,terrain)}

## The ramp from the footprint edge nearest the visit spawn out towards it, in
## building-local coordinates: {edge, outward, top, foot, length}. Empty when
## the spawn lies inside the footprint or the step is negligible.
static func entrance_ramp(definition: BuildingDefinition, surfaces: Array, transform: Transform3D, terrain: TerrainProvider) -> Dictionary:
	if not BuildingDefinition.numbers(definition.data.get("visit_spawn"),3): return {}
	var spawn3 := BuildingDefinition.vector(definition.data.visit_spawn)
	var spawn := Vector2(spawn3.x,spawn3.z)
	var edge := Vector2.INF
	for surface in surfaces:
		var polygon: PackedVector2Array = surface.polygon
		if Geometry2D.is_point_in_polygon(spawn,polygon): return {}
		for index in polygon.size():
			var point := Geometry2D.get_closest_point_to_segment(spawn,polygon[index],polygon[(index+1)%polygon.size()])
			if point.distance_squared_to(spawn) < edge.distance_squared_to(spawn): edge = point
	if not edge.is_finite() or edge.distance_to(spawn) < 0.01: return {}
	var outward := (spawn-edge).normalized()
	var top := float(surfaces[0].height)
	var ground := func(local: Vector2) -> float:
		var world := transform*Vector3(local.x,0,local.y)
		return terrain.get_height(world.x,world.z)-transform.origin.y
	var length := 0.0
	var foot := ground.call(edge) as float
	# Two passes: the foot's ground depends on the ramp's length.
	for pass_index in 2:
		var drop := top-foot
		if drop < RAMP_MIN_DROP: return {}
		length = clampf(drop/tan(deg_to_rad(RAMP_SLOPE_DEGREES)),0.3,8.0)
		foot = ground.call(edge+outward*(RAMP_LANDING+length))
	return {"edge":edge,"outward":outward,"top":top,"foot":minf(foot,top-RAMP_MIN_DROP),"length":length}

static func build(prepared: Dictionary) -> Node3D:
	var shell := BuildingSceneBuilder.build(prepared.definition)
	var foundation := Node3D.new()
	foundation.name = "Foundation"
	shell.add_child(foundation)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#817a70")
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for surface in prepared.surfaces:
		var polygon: PackedVector2Array = surface.polygon
		var bottom: float = prepared.low-prepared.transform.origin.y-0.15
		var top: float = surface.height-0.02
		var vertices := PackedVector3Array()
		for point in polygon:
			vertices.append(Vector3(point.x,bottom,point.y))
			vertices.append(Vector3(point.x,top,point.y))
		var body := StaticBody3D.new()
		foundation.add_child(body)
		var collision := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		shape.points = vertices
		collision.shape = shape
		body.add_child(collision)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var indices := Geometry2D.triangulate_polygon(polygon)
		for index in range(0,indices.size(),3):
			for vertex in [indices[index],indices[index+2],indices[index+1]]: st.add_vertex(vertices[vertex*2+1])
		for index in polygon.size():
			var next := (index+1)%polygon.size()
			for vertex in [index*2,next*2,next*2+1,index*2,next*2+1,index*2+1]: st.add_vertex(vertices[vertex])
		st.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.mesh = st.commit()
		mesh.material_override = material
		body.add_child(mesh)
	var ramp: Dictionary = prepared.get("entrance",{})
	if not ramp.is_empty(): foundation.add_child(_ramp(ramp,material))
	return shell

static func _ramp(ramp: Dictionary, material: Material) -> StaticBody3D:
	var outward: Vector2 = ramp.outward
	var side := outward.orthogonal()*RAMP_WIDTH*0.5
	# Start slightly inside the plinth so the threshold has no gap.
	var inner: Vector2 = ramp.edge-outward*0.1
	var landing: Vector2 = ramp.edge+outward*RAMP_LANDING
	var outer: Vector2 = landing+outward*float(ramp.length)
	# Flush with the floor surface, so the threshold has no lip.
	var top := float(ramp.top)
	var foot := float(ramp.foot)-0.05
	var bottom := foot-0.3
	# Profile inner-top, landing-top, foot, foot-bottom, inner-bottom; convex.
	var profile := [[inner,top],[landing,top],[outer,foot],[outer,bottom],[inner,bottom]]
	var points := PackedVector3Array()
	for offset in [-side,side]:
		for corner in profile: points.append(Vector3(corner[0].x+offset.x,corner[1],corner[0].y+offset.y))
	var body := StaticBody3D.new()
	body.name = "EntranceRamp"
	var collision := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	collision.shape = shape
	body.add_child(collision)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Side faces (5-gons) and the quads joining them; cull is disabled.
	for start in [0,5]:
		for index in [0,1,2,0,2,3,0,3,4]: st.add_vertex(points[start+index])
	for index in 5:
		var next := (index+1)%5
		for vertex in [index,next,next+5,index,next+5,index+5]: st.add_vertex(points[vertex])
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = material
	body.add_child(mesh)
	return body
