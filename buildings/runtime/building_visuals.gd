class_name BuildingVisuals
extends RefCounted

## Optional code-native facade modules. Resolved wall/opening geometry remains
## authoritative; this adapter adds no collision or opaque replacement shell.
const PROFILES := ["plain", "painted-trim", "timber-frame"]
static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}

static func sync(root: Node3D, definition: BuildingDefinition) -> void:
	var profile: String = definition.data.get("visual_profile","plain")
	for level in root.get_children():
		if not level.has_meta("storey_id") or level.get_meta("element_id","") != level.get_meta("storey_id"): continue
		var existing := level.get_node_or_null("FacadeModules")
		var storey := BuildingFurniture.level(definition.data,str(level.get_meta("storey_id")))
		var signature := JSON.stringify([profile,storey.get("walls",[]),storey.get("openings",[])],"",true)
		if existing != null and existing.get_meta("signature","") == signature: continue
		if existing != null:
			level.remove_child(existing)
			existing.queue_free()
		if profile == "plain": continue
		var modules := Node3D.new()
		modules.name = "FacadeModules"
		modules.set_meta("visual_modules",true)
		modules.set_meta("signature",signature)
		level.add_child(modules)
		for wall in storey.walls:
			if wall.get("kind","") == "partition": continue
			_wall(modules,wall,storey.openings,profile)

static func _wall(parent: Node3D, wall: Dictionary, openings: Array, profile: String) -> void:
	var start := BuildingDefinition.vector(wall.from)
	var end := BuildingDefinition.vector(wall.to)
	var length := start.distance_to(end)
	var height := float(wall.height)
	var direction := (end-start).normalized()
	var normal := Vector3(-direction.z,0,direction.x)*float(wall.get("exterior_side",1))
	var strips: Array[Rect2] = [Rect2(0,0.14,length,0.10),Rect2(0,height-0.18,length,0.12)]
	if profile == "timber-frame":
		for index in range(ceili(length/1.8)+1):
			var x := minf(index*1.8,length-0.10)
			strips.append(Rect2(maxf(0,x),0,0.10,height))
	for opening in openings:
		if opening.wall_id != wall.id: continue
		var left := float(opening.offset)-float(opening.width)/2
		var right := left+float(opening.width)
		var bottom := float(opening.bottom)
		var top := bottom+float(opening.height)
		strips.append_array([Rect2(left-0.10,maxf(0,bottom-0.10),0.10,top-maxf(0,bottom-0.10)+0.10),Rect2(right,maxf(0,bottom-0.10),0.10,top-maxf(0,bottom-0.10)+0.10),Rect2(left,top,float(opening.width),0.10)])
		if opening.kind == "window": strips.append(Rect2(left,bottom-0.10,float(opening.width),0.10))
	var solid: Array[Rect2] = [Rect2(0,0,length,height)]
	for opening in openings:
		if opening.wall_id != wall.id: continue
		var hole := Rect2(float(opening.offset)-float(opening.width)/2,float(opening.bottom),float(opening.width),float(opening.height))
		var next: Array[Rect2] = []
		for rect in solid: next.append_array(_subtract(rect,hole))
		solid = next
	for strip in strips:
		for rect in solid:
			var piece := strip.intersection(rect)
			if piece.size.x <= 0.001 or piece.size.y <= 0.001: continue
			var module := MeshInstance3D.new()
			module.set_meta("element_id",wall.id)
			module.set_meta("slot","exterior_wall")
			module.set_meta("visual_profile",profile)
			var size := Vector3(piece.size.x,piece.size.y,0.045)
			var key := str(size)
			if not _meshes.has(key):
				var mesh := BoxMesh.new()
				mesh.size = size
				_meshes[key] = mesh
			if not _materials.has(profile):
				var material := StandardMaterial3D.new()
				material.albedo_color = Color("#594330" if profile == "timber-frame" else "#ece3cc")
				material.roughness = 0.88
				_materials[profile] = material
			module.mesh = _meshes[key]
			module.material_override = _materials[profile]
			module.position = start+direction*piece.get_center().x+Vector3.UP*piece.get_center().y+normal*(float(wall.thickness)/2+0.026)
			module.rotation.y = -atan2(direction.z,direction.x)
			parent.add_child(module)

static func _subtract(rect: Rect2, hole: Rect2) -> Array[Rect2]:
	var cut := rect.intersection(hole)
	if not cut.has_area(): return [rect]
	var result: Array[Rect2] = []
	for piece in [Rect2(rect.position,Vector2(cut.position.x-rect.position.x,rect.size.y)),Rect2(cut.end.x,rect.position.y,rect.end.x-cut.end.x,rect.size.y),Rect2(cut.position.x,rect.position.y,cut.size.x,cut.position.y-rect.position.y),Rect2(cut.position.x,cut.end.y,cut.size.x,rect.end.y-cut.end.y)]:
		if piece.has_area(): result.append(piece)
	return result
