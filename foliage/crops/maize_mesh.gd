class_name MaizeMesh
extends RefCounted

## Stylised metre-scale maize: faceted stalk, folded pointed leaves, ear/tassel.
## Original geometry; the source nature pack offers wheat, not maize.
static var _mesh: ArrayMesh

static func get_mesh() -> ArrayMesh:
	if _mesh != null: return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stalk := Color("#6b8433")
	for i in 5:
		var a := TAU*i/5.0
		var b := TAU*(i+1)/5.0
		_face(st,[Vector3(cos(a)*.025,0,sin(a)*.025),Vector3(cos(b)*.025,0,sin(b)*.025),
			Vector3(cos(b)*.014,1.86,sin(b)*.014),Vector3(cos(a)*.014,1.86,sin(a)*.014)],stalk)
	for i in 8:
		var angle := float(i)*2.4
		var direction := Vector3(cos(angle),0,sin(angle))
		var across := Vector3(-sin(angle),0,cos(angle))
		var base := Vector3(0,.3+i*.175,0)
		var length := .65-absf(i-3)*.045
		var middle := base+direction*length*.55+Vector3(0,.18,0)
		var tip := base+direction*length+Vector3(0,.02,0)
		var colour := Color("#46752d") if i%2==0 else Color("#68923a")
		_face(st,[base,middle-across*.07,tip,middle+Vector3(0,.04,0)],colour)
		_face(st,[base,middle+Vector3(0,.04,0),tip,middle+across*.07],colour.lightened(.10))
	# One small ear partially held by a green husk; a branching pale tassel.
	_face(st,[Vector3(.015,.98,-.03),Vector3(.10,1.08,-.04),Vector3(.06,1.32,-.025),Vector3(-.015,1.17,-.025)],Color("#b1aa49"))
	_face(st,[Vector3(0,1.00,-.01),Vector3(.13,1.27,-.01),Vector3(.06,1.16,.015)],Color("#68923a"))
	for i in 5:
		var d := Vector3(cos(TAU*i/5.0),0,sin(TAU*i/5.0))
		_face(st,[Vector3(0,1.76,0),d*.14+Vector3(0,1.93,0),d*.10+Vector3(0,1.99,0),Vector3(0,1.83,0)],Color("#b9ad63"))
	st.generate_normals()
	_mesh=st.commit()
	var material := ShaderMaterial.new()
	material.shader=load("res://foliage/shaders/maize.gdshader")
	_mesh.surface_set_material(0,material)
	return _mesh

static func _face(st: SurfaceTool, points: Array, colour: Color) -> void:
	for i in range(1,points.size()-1):
		for p in [points[0],points[i],points[i+1]]:
			st.set_color(colour.srgb_to_linear())
			st.add_vertex(p)
