class_name SiteRouteMesh
extends RefCounted

## Continuous terrain-following ribbons: shared mitres instead of disconnected
## segment rectangles. Surface tags remain attached to the site record.
const SHADER = preload("res://foliage/shaders/site_route.gdshader")
const SURFACES := ["asphalt", "gravel", "earth", "grass", "paving"]

static func build(record: Dictionary, ground: Callable) -> MeshInstance3D:
	return instance(record, arrays(record, ground))

## Thread-safe ribbon surface arrays for a route; [] when it has none.
static func arrays(record: Dictionary, ground: Callable) -> Array:
	var points := PackedVector2Array()
	var along := PackedFloat32Array()
	var distance := 0.0
	for i in range(record.points.size()-1):
		var a := Vector2(record.points[i][0],record.points[i][1])
		var b := Vector2(record.points[i+1][0],record.points[i+1][1])
		var length := a.distance_to(b)
		if length < .001: continue
		var steps := maxi(1,ceili(length/1.5))
		for j in steps:
			points.append(a.lerp(b,float(j)/steps))
			along.append(distance+length*float(j)/steps)
		distance += length
	var last: Array = record.points[-1]
	points.append(Vector2(last[0],last[1]))
	along.append(distance)
	if points.size()<2: return []
	var half := float(record.width)*.5+.18
	var offsets := PackedVector2Array()
	for i in points.size():
		var before := (points[i]-points[maxi(0,i-1)]).normalized()
		var after := (points[mini(i+1,points.size()-1)]-points[i]).normalized()
		if i==0: before=after
		if i==points.size()-1: after=before
		var n := after.orthogonal()
		var mitre := (before.orthogonal()+n).normalized()
		if mitre.length_squared()<.1: mitre=n
		offsets.append(mitre*minf(half/maxf(.25,absf(mitre.dot(n))),half*2.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size()-1):
		var a := points[i]+offsets[i]
		var b := points[i]-offsets[i]
		var c := points[i+1]+offsets[i+1]
		var d := points[i+1]-offsets[i+1]
		_vertex(st,a,Vector2(0,along[i]),ground)
		_vertex(st,c,Vector2(0,along[i+1]),ground)
		_vertex(st,b,Vector2(1,along[i]),ground)
		_vertex(st,b,Vector2(1,along[i]),ground)
		_vertex(st,c,Vector2(0,along[i+1]),ground)
		_vertex(st,d,Vector2(1,along[i+1]),ground)
	# Rounded open ends prevent squared-off gaps at footpath junctions.
	for end in [0,points.size()-1]:
		var tangent := (points[1]-points[0]).normalized() if end==0 else (points[end-1]-points[end]).normalized()
		var across := tangent.orthogonal()
		for j in 8:
			var angle_a := PI/2+PI*float(j)/8
			var angle_b := PI/2+PI*float(j+1)/8
			_vertex(st,points[end],Vector2(.5,along[end]),ground)
			for angle in [angle_b,angle_a]:
				var p: Vector2 = points[end]+(tangent*cos(angle)+across*sin(angle))*half
				_vertex(st,p,Vector2(.5+.5*sin(angle),along[end]),ground)
	return st.commit_to_arrays()

## MAIN THREAD. The route's mesh and surface material; null for [].
static func instance(record: Dictionary, surface: Array) -> MeshInstance3D:
	if surface.is_empty(): return null
	var material := ShaderMaterial.new()
	material.shader=SHADER
	var kind := SURFACES.find(record.get("surface", "earth" if record.tags.get("highway", "") in ["path","track"] else "gravel" if record.tags.get("highway", "")=="service" else "asphalt"))
	material.set_shader_parameter("surface_kind",maxi(0,kind))
	material.set_shader_parameter("two_tracks",record.tags.get("highway", "")=="track")
	material.set_shader_parameter("route_width",float(record.width))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surface)
	var route := MeshInstance3D.new()
	route.mesh=mesh
	route.material_override=material
	return route

static func _vertex(st: SurfaceTool, point: Vector2, uv: Vector2, ground: Callable) -> void:
	st.set_uv(uv)
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(point.x,float(ground.call(point.x,point.y))+.055,point.y))
