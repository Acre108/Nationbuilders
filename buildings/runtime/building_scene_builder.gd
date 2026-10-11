class_name BuildingSceneBuilder
extends RefCounted

## Both the editor and visit render the resolved document, never its inputs.
static func build(definition: BuildingDefinition, cutaway: bool = false, active_storey: int = -1) -> Node3D:
	if not definition.validate().is_empty() or definition.is_grid_draft(): return null
	var root := Node3D.new()
	root.name = "Building"
	var cache := {}
	cache.window_links = {}
	for link in definition.data.get("exterior_opening_links",[]): cache.window_links[link.opening_id] = link
	cache.roof_envelope = BuildingRoofEnvelope.new(definition.data)
	for storey in definition.data.storeys:
		var level := Node3D.new()
		level.name = "Storey"
		level.set_meta("element_id", storey.id)
		level.set_meta("storey_id",storey.id)
		level.visible = not (cutaway and active_storey >= 0 and definition.data.storeys.find(storey) > active_storey)
		level.position.y = float(storey.elevation)
		root.add_child(level)
		for slab in storey.slabs:
			if cache.roof_envelope.applies(storey.id) and slab.slot in ["roof","ceiling"]:
				if slab.slot == "ceiling": _envelope_ceiling(level,definition,storey,slab,cache,cutaway)
				continue
			var part := _box(level, BuildingDefinition.vector(slab.center), BuildingDefinition.vector(slab.size), _material(definition, slab.id, slab.slot, cache,str(slab.get("source_id",""))), slab.id, slab.slot)
			part.set_meta("source_id",str(slab.get("source_id","")))
			part.visible = not (cutaway and slab.slot in ["roof", "ceiling"])
		var openings := {}
		for opening in storey.openings: openings[opening.id] = opening
		for wall in storey.walls:
			_build_wall(level, definition, wall, openings, cache)
		for room in storey.rooms:
			if not room.has("regions"): continue
			var material := _material(definition,room.id,"floor",cache,"",str(room.colour))
			for region in room.regions:
				var pieces: Array[Rect2] = []
				if definition.data.get("compiler_version") in [4,5]: pieces = BuildingStoreys.floor_regions(storey,region)
				else: pieces.append(Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3])))
				for piece in pieces:
					var part := _box(level,Vector3(piece.get_center().x,0.002,piece.get_center().y),Vector3(piece.size.x,0.004,piece.size.y),material,room.id,"floor",false)
					part.set_meta("space_id",room.id)
					part.set_meta("source_colour",str(room.colour))
		for instance in definition.data.furniture:
			if instance.storey_id != storey.id: continue
			level.add_child(FurnitureRuntime.build(definition.data, instance))
	if definition.data.get("compiler_version") in [4,5]:
		var invalid := {}
		for conflict in definition.data.stair_conflicts: invalid[conflict.id] = true
		for stair in definition.data.stairs:
			if invalid.has(stair.id): continue
			var lower := BuildingStoreys.level_index(definition.data,stair.from_storey)
			var flight := _stair(root,definition,stair,cache)
			flight.position.y = float(definition.data.storeys[lower].elevation)
			flight.visible = not (cutaway and active_storey >= 0 and lower > active_storey)
	for component in definition.data.get("exterior_components", []):
		var material := _material(definition, component.id, component.slot, cache)
		if component.has("colour"):
			material = material.duplicate()
			material = BuildingMaterials.material(BuildingMaterials.surface(definition.data,component.id,component.slot,str(component.get("storey_id","")),component.colour))
		material = material.duplicate()
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		var surface: Material = material
		if component.get("pattern") == "tiles":
			var tiles := ShaderMaterial.new()
			tiles.shader = load("res://buildings/shaders/roof_tiles.gdshader")
			tiles.set_shader_parameter("tile_colour",material.albedo_color)
			tiles.set_shader_parameter("weathering",float(component.get("tile_weathering",0.0)))
			surface = tiles
		var part := _exterior(root, component, surface)
		part.set_meta("source_colour",str(component.get("colour","")))
		var component_storey := BuildingStoreys.level_index(definition.data,str(component.get("storey_id","")))
		part.visible = not (cutaway and (component.slot in ["roof", "ceiling"] or component.get("hide_in_cutaway",false) or active_storey >= 0 and component_storey > active_storey))
	BuildingVisuals.sync(root,definition)
	LightingSettings.configure_building_geometry(root)
	BuildingLocalLights.set_quality(root,FoliageQuality.Level.HIGH)
	return root

static func _stair(root: Node3D, definition: BuildingDefinition, stair: Dictionary, cache: Dictionary) -> Node3D:
	if stair.has("path"): return _path_stair(root,definition,stair,cache)
	var flight := Node3D.new()
	flight.name = stair.id
	flight.set_meta("element_id",stair.id)
	flight.set_meta("storey_id",stair.from_storey)
	var at := BuildingStoreys.start(stair)
	var direction := BuildingStoreys.direction(stair)
	flight.position = Vector3(at.x,0,at.y)
	flight.rotation.y = atan2(direction.x,direction.y)
	root.add_child(flight)
	var material := _material(definition,stair.id,"floor",cache)
	var width := float(stair.width)
	var run := float(stair.run)
	var height := float(stair.height)
	var count := ceili(height/0.17)
	for index in count:
		var rise := height/count
		var tread := run/count
		var top := (index+0.5)*rise
		_box(flight,Vector3(0,top-0.04,(index+0.5)*tread),Vector3(width,0.08,tread),material,stair.id,"floor",false)
	# A single smooth wedge keeps the same visitor capsule on a reliable slope.
	var body := StaticBody3D.new()
	body.set_meta("element_id",stair.id)
	flight.add_child(body)
	var collider := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	var vertices := PackedVector3Array()
	for x in [-width/2,width/2]:
		vertices.append_array(PackedVector3Array([Vector3(x,-0.1,0),Vector3(x,0,0),Vector3(x,height-0.1,run),Vector3(x,height,run)]))
	shape.points = vertices
	collider.shape = shape
	body.add_child(collider)
	var rail_material := _colour_material("#7f7361",cache)
	for side in [-1,1]:
		var rail := _box(flight,Vector3(side*(width/2+0.035),height/2+0.65,run/2),Vector3(0.07,1.3,sqrt(run*run+height*height)),rail_material,stair.id,"interior_wall")
		rail.rotation.x = -atan2(height,run)
		# Protect the upper floor's slab opening independently of its ramp.
		if not stair.get("path_segment",false): _box(flight,Vector3(side*(width/2+0.035),height+0.55,run/2),Vector3(0.07,1.1,run),rail_material,stair.id,"interior_wall")
	var outgoing := false
	for other in definition.data.stairs:
		if other.from_storey == stair.to_storey and other.position == stair.position and other.orientation == stair.orientation: outgoing = true
	if not outgoing and not stair.get("path_segment",false): _box(flight,Vector3(0,height+0.55,-0.035),Vector3(width+0.14,1.1,0.07),rail_material,stair.id,"interior_wall")
	return flight

static func _path_stair(root: Node3D, definition: BuildingDefinition, stair: Dictionary, cache: Dictionary) -> Node3D:
	var group := Node3D.new()
	group.name = stair.id
	group.set_meta("element_id",stair.id)
	group.set_meta("storey_id",stair.from_storey)
	root.add_child(group)
	var elevation := 0.0
	var material := _material(definition,stair.id,"floor",cache)
	var rails := _colour_material("#7f7361",cache)
	for index in stair.path.size()-1:
		var a := Vector2(float(stair.path[index][0]),float(stair.path[index][1]))
		var b := Vector2(float(stair.path[index+1][0]),float(stair.path[index+1][1]))
		var direction := (b-a).normalized()
		var lower := a+direction*(BuildingStoreys.WIDTH/2 if index > 0 else 0.0)
		var upper := b-direction*(BuildingStoreys.WIDTH/2 if index < stair.path.size()-2 else 0.0)
		var run := lower.distance_to(upper)
		var rise := run/float(stair.run)*float(stair.height)
		var segment: Dictionary = stair.duplicate(true)
		segment.erase("path")
		segment.position = [lower.x,lower.y]
		segment.run = run
		segment.height = rise
		segment.path_segment = true
		segment.orientation = [Vector2.DOWN,Vector2.RIGHT,Vector2.UP,Vector2.LEFT].find(direction)
		var flight := _stair(group,definition,segment,cache)
		flight.position.y = elevation
		elevation += rise
		if index < stair.path.size()-2:
			_box(group,Vector3(b.x,elevation-0.06,b.y),Vector3(BuildingStoreys.WIDTH,0.12,BuildingStoreys.WIDTH),material,stair.id,"floor")
			var outgoing := (Vector2(float(stair.path[index+2][0]),float(stair.path[index+2][1]))-b).normalized()
			for side in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
				if side == -direction or side == outgoing: continue
				var size := Vector3(0.07,1.1,BuildingStoreys.WIDTH) if side.x != 0 else Vector3(BuildingStoreys.WIDTH,1.1,0.07)
				_box(group,Vector3(b.x+side.x*0.735,elevation+0.55,b.y+side.y*0.735),size,rails,stair.id,"interior_wall")
	# Guard the complete upper void, leaving only the outgoing landing open.
	var box := BuildingStoreys.hole(stair)
	var exit := BuildingStoreys.end(stair)
	var before := Vector2(float(stair.path[-2][0]),float(stair.path[-2][1]))
	var outgoing := (exit-before).normalized()
	# The conservative rectangular slab cut extends half a flight width past
	# the endpoint. Bridge that remaining space at the finished floor height.
	var bridge := exit+outgoing*(BuildingStoreys.WIDTH/4)
	var bridge_size := Vector3(BuildingStoreys.WIDTH/2,0.12,BuildingStoreys.WIDTH) if outgoing.x != 0 else Vector3(BuildingStoreys.WIDTH,0.12,BuildingStoreys.WIDTH/2)
	_box(group,Vector3(bridge.x,float(stair.height)-0.06,bridge.y),bridge_size,material,stair.id,"floor")
	for side in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		var along_x: bool = side.y != 0
		var fixed := (box.position.y if side.y < 0 else box.end.y) if along_x else (box.position.x if side.x < 0 else box.end.x)
		var low := box.position.x if along_x else box.position.y
		var high := box.end.x if along_x else box.end.y
		var spans: Array = [[low,high]]
		if side == outgoing:
			var center := exit.x if along_x else exit.y
			spans = [[low,center-BuildingStoreys.WIDTH/2],[center+BuildingStoreys.WIDTH/2,high]]
		for span in spans:
			if float(span[1])-float(span[0]) < 0.001: continue
			var middle := (float(span[0])+float(span[1]))/2
			var position := Vector3(middle,float(stair.height)+0.55,fixed) if along_x else Vector3(fixed,float(stair.height)+0.55,middle)
			var size := Vector3(float(span[1])-float(span[0]),1.1,0.07) if along_x else Vector3(0.07,1.1,float(span[1])-float(span[0]))
			_box(group,position,size,rails,stair.id,"interior_wall")
	return group

static func _exterior(root: Node3D, component: Dictionary, material: Material) -> Node3D:
	var mesh: Mesh
	match component.kind:
		"box":
			var box := BoxMesh.new()
			box.size = BuildingDefinition.vector(component.size)
			mesh = box
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = float(component.size[0])/2
			cylinder.bottom_radius = float(component.size[2])/2
			cylinder.height = float(component.size[1])
			cylinder.radial_segments = 12
			mesh = cylinder
		"mesh":
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for index in component.indices:
				var point := BuildingDefinition.vector(component.vertices[int(index)])
				st.set_uv(Vector2(point.x, point.y-point.z))
				st.add_vertex(point)
			st.generate_normals()
			mesh = st.commit()
	var part := StaticBody3D.new() if component.get("collision",true) else Node3D.new()
	part.name = component.id
	part.set_meta("element_id",component.id)
	part.set_meta("slot",component.slot)
	part.set_meta("exterior_component",true)
	if component.has("storey_id"): part.set_meta("storey_id",component.storey_id)
	part.position = BuildingDefinition.vector(component.position)
	part.rotation_degrees = BuildingDefinition.vector(component.get("rotation_degrees",[0,0,0]))
	root.add_child(part)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.visible = not component.get("collision_only",false)
	part.add_child(visual)
	if component.get("collision",true):
		var collider := CollisionShape3D.new()
		collider.shape = mesh.create_trimesh_shape()
		(collider.shape as ConcavePolygonShape3D).backface_collision = true
		part.add_child(collider)
	return part

static func _build_wall(root: Node3D, definition: BuildingDefinition, wall: Dictionary, openings: Dictionary, cache: Dictionary) -> void:
	var start := BuildingDefinition.vector(wall.from)
	var end := BuildingDefinition.vector(wall.to)
	var direction := (end - start).normalized()
	var normal := Vector3(-direction.z, 0, direction.x) * (1.0 if wall.get("kind") == "partition" else float(wall.get("exterior_side",1)))
	var length := start.distance_to(end)
	var yaw := -atan2(direction.z, direction.x)
	var holes: Array[Dictionary] = []
	for id in wall.openings: holes.append(openings[id])
	holes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.offset < b.offset)
	var cursor := 0.0
	for opening in holes:
		var left := float(opening.offset) - float(opening.width) / 2
		var right := float(opening.offset) + float(opening.width) / 2
		_wall_piece(root, definition, wall, start, direction, normal, yaw, cursor, left, 0, wall.height, cache)
		_wall_piece(root, definition, wall, start, direction, normal, yaw, left, right, 0, opening.bottom, cache)
		_wall_piece(root, definition, wall, start, direction, normal, yaw, left, right, opening.bottom + opening.height, wall.height, cache)
		if opening.kind == "window":
			var center := start + direction * float(opening.offset) + Vector3.UP * (float(opening.bottom) + float(opening.height) / 2)
			if cache.window_links.has(opening.id): center = BuildingDefinition.vector(cache.window_links[opening.id].outer)-Vector3.UP*root.position.y
			if definition.data.get("opening_profiles",{}).get(opening.id) == "circle":
				var faces: Array = []
				for i in 32:
					var a := TAU*i/32
					var b := TAU*(i+1)/32
					faces.append([center,center+(direction*cos(a)+Vector3.UP*sin(a))*float(opening.width)/2,center+(direction*cos(b)+Vector3.UP*sin(b))*float(opening.width)/2])
				_resolved_faces(root,opening.id,faces,_material(definition,opening.id,"glass",cache),"glass",true)
			else:
				var pane := _box(root, center, Vector3(opening.width, opening.height, 0.04), _material(definition, opening.id, "glass", cache), opening.id, "glass")
				pane.rotation.y = yaw
		if definition.is_grid_layout() and definition.data.get("opening_profiles",{}).get(opening.id) != "circle": _opening_trim(root,definition,wall,opening,start,direction,yaw,cache)
		cursor = right
	_wall_piece(root, definition, wall, start, direction, normal, yaw, cursor, length, 0, wall.height, cache)

static func _wall_piece(root: Node3D, definition: BuildingDefinition, wall: Dictionary, start: Vector3, direction: Vector3, normal: Vector3, yaw: float, left: float, right: float, bottom: float, top: float, cache: Dictionary) -> void:
	if right - left < 0.001 or top - bottom < 0.001: return
	var envelope: BuildingRoofEnvelope = cache.get("roof_envelope")
	if envelope != null and envelope.applies(str(root.get_meta("storey_id",""))):
		_envelope_wall(root,definition,wall,start,direction,normal,left,right,bottom,top,cache)
		return
	var center := start + direction * ((left + right) / 2) + Vector3.UP * ((bottom + top) / 2)
	var size := Vector3(right - left, top - bottom, wall.thickness)
	var part := _box(root, center, size, _material(definition, wall.id, "interior_wall", cache), wall.id, "interior_wall")
	part.rotation.y = yaw
	part.set_meta("exterior_side",float(wall.get("exterior_side",1)))
	if wall.has("spaces"):
		# The two face skins replace the body's broad faces, avoiding coplanar
		# surfaces while keeping finishes within the stated wall thickness.
		var visual := part.get_child(0) as MeshInstance3D
		visual.mesh = _wall_caps(visual.mesh)
		part.set_meta("spaces",wall.spaces)
		part.set_meta("wall_kind",wall.kind)
		var left_normal := Vector3(-direction.z,0,direction.x)
		for index in 2:
			if wall.spaces[index] == "outside": continue
			var colour: String = wall.face_colours[index]
			var material := _material(definition,wall.id,"interior_wall",cache) if colour.is_empty() else _material(definition,wall.id,"interior_wall",cache,"",colour)
			# Finish at the authoring endpoints: adjacent differently coloured
			# collinear runs must not overlap each other's corner extensions.
			var face_left := maxf(left,float(wall.thickness)/2)
			var face_right := minf(right,BuildingDefinition.vector(wall.from).distance_to(BuildingDefinition.vector(wall.to))-float(wall.thickness)/2)
			if face_right-face_left < 0.001: continue
			var face_center := start+direction*((face_left+face_right)/2)+Vector3.UP*((bottom+top)/2)
			var face := _box(root,face_center+left_normal*(1 if index == 0 else -1)*(float(wall.thickness)/2-0.003),Vector3(face_right-face_left,size.y,0.006),material,wall.id,"interior_wall",false)
			face.rotation.y = yaw
			face.set_meta("space_id",wall.spaces[index])
			face.set_meta("source_colour",colour)
	if wall.get("kind") == "partition": return
	# A separate outside skin allows facade and interior colours to differ.
	var facade := _box(root, center + normal * (float(wall.thickness) / 2 + 0.003), Vector3(size.x, size.y, 0.006), _material(definition, wall.id, "exterior_wall", cache), wall.id, "exterior_wall", false)
	facade.rotation.y = yaw

static func _resolved_faces(root: Node3D,id: String,faces: Array,material: Material,slot: String,collision: bool) -> Node3D:
	var vertices: Array = []
	var indices: Array = []
	for face in faces:
		var offset := vertices.size()
		for p: Vector3 in face: vertices.append([p.x,p.y,p.z])
		for i in range(1,face.size()-1): indices.append_array([offset,offset+i,offset+i+1])
	if indices.is_empty(): return null
	var component := {"id":id,"kind":"mesh","position":[0,0,0],"slot":slot,"vertices":vertices,"indices":indices,"collision":collision}
	var part := _exterior(root,component,material)
	var visual := part.get_child(0) as MeshInstance3D
	visual.material_override = material.duplicate()
	visual.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	part.set_meta("exterior_component",false)
	return part

static func _envelope_ceiling(root: Node3D,definition: BuildingDefinition,level: Dictionary,slab: Dictionary,cache: Dictionary,cutaway: bool) -> void:
	var envelope: BuildingRoofEnvelope = cache.roof_envelope
	var center := BuildingDefinition.vector(slab.center)
	var size := BuildingDefinition.vector(slab.size)
	var rect := Rect2(center.x-size.x/2,center.z-size.z/2,size.x,size.z)
	var faces: Array = []
	if not envelope.resolved.is_empty():
		# Follow the actual trimmed roof triangles. Sampling across a valley
		# can otherwise bridge its low point and expose white ceiling flecks.
		for face in envelope.resolved_in(rect):
			var polygon := PackedVector2Array()
			for p: Vector3 in face: polygon.append(Vector2(p.x,p.z))
			var normal: Vector3 = (face[1]-face[0]).cross(face[2]-face[0])
			if absf(normal.y) < 0.00001: continue
			var pieces: Array = Geometry2D.intersect_polygons(polygon,BuildingFurniture.rect_polygon(rect))
			if level.id == definition.data.storeys[-1].id:
				for saved in envelope.skylights:
					var next: Array = []
					var hole := Rect2(float(saved[0]),float(saved[1]),float(saved[2]),float(saved[3]))
					for piece in pieces: next.append_array(BuildingRoofEnvelope.subtract_convex(piece,BuildingFurniture.rect_polygon(hole)))
					pieces = next
			for piece in pieces:
				var indices := Geometry2D.triangulate_polygon(piece)
				for i in range(0,indices.size(),3):
					var triangle: Array = []
					for j in 3:
						var p: Vector2 = piece[indices[i+j]]
						var height: float = face[0].y-(normal.x*(p.x-face[0].x)+normal.z*(p.y-face[0].z))/normal.y
						triangle.append(Vector3(p.x,minf(center.y-size.y/2,height-float(level.elevation)-0.12),p.y))
					faces.append(triangle)
		var exact := _resolved_faces(root,slab.id,faces,_material(definition,slab.id,"ceiling",cache,str(slab.get("source_id",""))),"ceiling",true)
		if exact != null: exact.visible = not cutaway
		return
	var nx := ceili(size.x/0.5)
	var nz := ceili(size.z/0.5)
	for z in nz:
		for x in nx:
			var low := rect.position+Vector2(size.x*x/nx,size.z*z/nz)
			var box := Rect2(low,Vector2(size.x/nx,size.z/nz))
			var polygons: Array = [BuildingFurniture.rect_polygon(box)]
			if level.id == definition.data.storeys[-1].id:
				for saved in envelope.skylights:
					var window := Rect2(float(saved[0]),float(saved[1]),float(saved[2]),float(saved[3]))
					var next: Array = []
					for polygon in polygons: next.append_array(BuildingRoofEnvelope.subtract_convex(polygon,BuildingFurniture.rect_polygon(window)))
					polygons = next
			for polygon in polygons:
				var triangles := Geometry2D.triangulate_polygon(polygon)
				for i in range(0,triangles.size(),3):
					var face: Array = []
					for j in 3:
						var p: Vector2 = polygon[triangles[i+j]]
						var height := envelope.height_at(p)
						var local := center.y-size.y/2
						if is_finite(height): local = minf(local,height-float(level.elevation)-0.12)
						face.append(Vector3(p.x,local,p.y))
					faces.append(face)
	var part := _resolved_faces(root,slab.id,faces,_material(definition,slab.id,"ceiling",cache,str(slab.get("source_id",""))),"ceiling",true)
	if part != null: part.visible = not cutaway

static func _envelope_wall(root: Node3D,definition: BuildingDefinition,wall: Dictionary,start: Vector3,u: Vector3,n: Vector3,left: float,right: float,bottom: float,top: float,cache: Dictionary) -> void:
	var envelope: BuildingRoofEnvelope = cache.roof_envelope
	var count := ceili((right-left)/0.4)
	var half := float(wall.thickness)/2
	var body_faces: Array = []
	var face_a: Array = []
	var face_b: Array = []
	var breaks: Array[float] = [left,right]
	for i in range(1,count): breaks.append(lerpf(left,right,float(i)/count))
	# Split at actual roof triangle edges, including valleys and dormer
	# junctions. Linear caps must not bridge a lower roof between samples.
	var line_start := start+u*left
	var line_end := start+u*right
	var roof_bounds := Rect2(Vector2(line_start.x,line_start.z),Vector2(line_end.x-line_start.x,line_end.z-line_start.z)).abs().grow(half+0.01)
	for face in envelope.resolved_in(roof_bounds):
		for sign in [-1,0,1]:
			var a: Vector3 = start+u*left+n*half*sign
			var b: Vector3 = start+u*right+n*half*sign
			for i in 3:
				var p: Vector3 = face[i]
				var q: Vector3 = face[(i+1)%3]
				var hit: Variant = Geometry2D.segment_intersects_segment(Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(p.x,p.z),Vector2(q.x,q.z))
				if hit != null:
					var offset := (Vector3(hit.x,0,hit.y)-start).dot(u)
					if offset > left+0.0001 and offset < right-0.0001: breaks.append(offset)
	breaks.sort()
	for i in breaks.size()-1:
		if breaks[i+1]-breaks[i] < 0.0001: continue
		var a := start+u*breaks[i]
		var b := start+u*breaks[i+1]
		var tops: Array[float] = []
		for p in [a,b]:
			var y := top
			for sign in [-1,0,1]:
				var sample: Vector3 = p.move_toward((a+b)/2,0.00005)+n*half*sign
				var roof := envelope.height_at(Vector2(sample.x,sample.z))
				if is_finite(roof): y = minf(y,roof-root.position.y-0.09)
			tops.append(maxf(bottom,y))
		if maxf(tops[0],tops[1]) <= bottom+0.001: continue
		var aa := Vector3(a.x,bottom,a.z)
		var bb := Vector3(b.x,bottom,b.z)
		var at := Vector3(a.x,tops[0],a.z)
		var bt := Vector3(b.x,tops[1],b.z)
		var outer: Array = [aa+n*half,bb+n*half,bt+n*half,at+n*half]
		var inner: Array = [bb-n*half,aa-n*half,at-n*half,bt-n*half]
		body_faces.append_array([outer,inner,[at+n*half,bt+n*half,bt-n*half,at-n*half],[aa+n*half,at+n*half,at-n*half,aa-n*half],[bb-n*half,bt-n*half,bt+n*half,bb+n*half]])
		face_a.append(outer.map(func(p: Vector3) -> Vector3: return p+n*0.004))
		face_b.append(inner.map(func(p: Vector3) -> Vector3: return p-n*0.004))
	var body := _resolved_faces(root,wall.id,body_faces,_material(definition,wall.id,"interior_wall",cache),"interior_wall",true)
	if body == null: return
	body.set_meta("wall_kind",wall.kind)
	body.set_meta("spaces",wall.get("spaces",[]))
	body.set_meta("exterior_side",float(wall.get("exterior_side",1)))
	if wall.kind != "partition":
		_resolved_faces(root,wall.id,face_a,_material(definition,wall.id,"exterior_wall",cache),"exterior_wall",false)
		var side := 1 if float(wall.get("exterior_side",1)) > 0 else 0
		var colour: String = wall.get("face_colours",["",""])[side]
		var skin := _resolved_faces(root,wall.id,face_b,_material(definition,wall.id,"interior_wall",cache,"",colour),"interior_wall",false)
		if skin != null: skin.set_meta("space_id",wall.get("spaces",["",""])[side]); skin.set_meta("source_colour",colour)
	else:
		for index in 2:
			var colour: String = wall.get("face_colours",["",""])[index]
			var skin := _resolved_faces(root,wall.id,face_a if index == 0 else face_b,_material(definition,wall.id,"interior_wall",cache,"",colour),"interior_wall",false)
			if skin != null: skin.set_meta("space_id",wall.get("spaces",["",""])[index]); skin.set_meta("source_colour",colour)

static func _opening_trim(root: Node3D,definition: BuildingDefinition,wall: Dictionary,opening: Dictionary,start: Vector3,direction: Vector3,yaw: float,cache: Dictionary) -> void:
	var strip := 0.055
	var depth := float(wall.thickness)+0.045
	var center := start+direction*float(opening.offset)
	var material := _colour_material("#e1d8c5",cache)
	for side in [-1,1]:
		var jamb := _box(root,center+direction*(float(opening.width)+strip)/2*side+Vector3.UP*(float(opening.bottom)+float(opening.height)/2),Vector3(strip,opening.height,depth),material,opening.id,"interior_wall",false)
		jamb.rotation.y = yaw
	var head := _box(root,center+Vector3.UP*(float(opening.bottom)+float(opening.height)+strip/2),Vector3(float(opening.width)+strip*2,strip,depth),material,opening.id,"interior_wall",false)
	head.rotation.y = yaw
	if opening.kind == "window":
		var sill := _box(root,center+Vector3.UP*(float(opening.bottom)-strip/2),Vector3(float(opening.width)+strip*2,strip,depth),material,opening.id,"interior_wall",false)
		sill.rotation.y = yaw

static func _wall_caps(mesh: Mesh) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var kept := PackedInt32Array()
	for index in range(0,indices.size(),3):
		if absf(normals[indices[index]].z) > 0.5: continue
		for vertex in 3: kept.append(indices[index+vertex])
	arrays[Mesh.ARRAY_INDEX] = kept
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result

static func _colour_material(colour: String,cache: Dictionary) -> StandardMaterial3D:
	var key := "room"+colour
	if cache.has(key): return cache[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(colour)
	result.set_meta("source_colour",colour)
	result.roughness = 0.85
	cache[key] = result
	return result

static func _material(definition: BuildingDefinition, element_id: String, slot: String, cache: Dictionary, source_id: String = "", fallback: String = "") -> StandardMaterial3D:
	if not cache.has("storey_ids"):
		cache.storey_ids = {}
		for level in definition.data.storeys:
			for field in ["walls","slabs","rooms","openings","uncut_slabs"]:
				for record in level.get(field,[]): cache.storey_ids[record.id] = level.id
		for component in definition.data.get("exterior_components",[]):
			if component.has("storey_id"): cache.storey_ids[component.id] = component.storey_id
	var storey_id: String = cache.storey_ids.get(element_id,"")
	var value := BuildingMaterials.surface(definition.data,element_id,slot,storey_id,fallback,source_id)
	return BuildingMaterials.material(value,"glass" if slot == "glass" else "")

## Appearance and furniture edits keep structural and collision nodes alive.
static func sync(root: Node3D, definition: BuildingDefinition) -> void:
	_sync_materials(root,definition)
	BuildingVisuals.sync(root,definition)
	for level in root.get_children():
		if not level.has_meta("storey_id") or level.get_meta("element_id","") != level.get_meta("storey_id"): continue
		var retained := {}
		for child in level.get_children():
			if child.has_meta("furniture_id"):
				var item := BuildingFurniture.instance(definition.data,str(child.get_meta("furniture_id")))
				if item.is_empty() or item.storey_id != level.get_meta("storey_id"):
					level.remove_child(child)
					child.queue_free()
				else:
					FurnitureRuntime.update(child,definition.data,item)
					retained[item.id] = true
		for item in definition.data.furniture:
			if item.storey_id == level.get_meta("storey_id") and not retained.has(item.id): level.add_child(FurnitureRuntime.build(definition.data,item))
	BuildingLocalLights.set_quality(root,FoliageQuality.Level.HIGH)
	LightingSettings.configure_building_geometry(root)

static func _sync_materials(node: Node, definition: BuildingDefinition, cache: Dictionary = {}) -> void:
	if node.has_meta("furniture_id") or node.has_meta("visual_modules"): return
	if node.has_meta("slot") and node.has_meta("element_id"):
		for child in node.get_children():
			if child is MeshInstance3D:
				var material := _material(definition,str(node.get_meta("element_id")),str(node.get_meta("slot")),cache,str(node.get_meta("source_id","")),str(node.get_meta("source_colour","")))
				if node.get_meta("exterior_component",false):
					material = material.duplicate()
					material.cull_mode = BaseMaterial3D.CULL_DISABLED
				if child.material_override is ShaderMaterial:
					child.material_override = child.material_override.duplicate()
					child.material_override.set_shader_parameter("tile_colour",material.albedo_color)
				else: child.material_override = material
	for child in node.get_children(): _sync_materials(child,definition,cache)

static func _box(root: Node3D, center: Vector3, size: Vector3, material: Material, element_id: String, slot: String, collision: bool = true) -> Node3D:
	var part := StaticBody3D.new() if collision else Node3D.new()
	part.set_meta("element_id", element_id)
	part.set_meta("slot", slot)
	if material.has_meta("source_colour"): part.set_meta("source_colour",material.get_meta("source_colour"))
	part.position = center
	root.add_child(part)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	part.add_child(visual)
	if slot == "glass": visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if collision:
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		part.add_child(collider)
	return part
