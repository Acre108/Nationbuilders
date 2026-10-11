extends RefCounted
## Simple, deliberately legible meshes. Every visible mesh carries vertex colors.
const TOON = preload("res://render/toon.gdshader")
var material := ShaderMaterial.new()
var mesh_cache: Dictionary = {}

func _init() -> void:
	material.shader = TOON

func primitive(parent: Node3D, shape: PrimitiveMesh, color: Color, at: Vector3) -> MeshInstance3D:
	var arrays: Array = shape.get_mesh_arrays()
	var colors := PackedColorArray()
	colors.resize(arrays[Mesh.ARRAY_VERTEX].size())
	colors.fill(color)
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance

func box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return primitive(parent,shape,color,at)

func cylinder(parent: Node3D, at: Vector3, radius: float, height: float, color: Color, top: float = -1.0) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.bottom_radius = radius
	shape.top_radius = radius if top < 0.0 else top
	shape.height = height
	shape.radial_segments = 6
	shape.rings = 1
	return primitive(parent,shape,color,at)

func roof(parent: Node3D, center: Vector3, width: float, depth: float, height: float, color: Color) -> MeshInstance3D:
	var a := Vector3(-width/2,0,-depth/2)
	var b := Vector3(width/2,0,-depth/2)
	var c := Vector3(0,height,-depth/2)
	var d := Vector3(-width/2,0,depth/2)
	var e := Vector3(width/2,0,depth/2)
	var f := Vector3(0,height,depth/2)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle in [[a,c,b],[d,e,f],[a,d,f],[a,f,c],[b,c,f],[b,f,e]]:
		var normal: Vector3 = (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized()
		# Godot's front faces use clockwise winding; retain outward normals.
		for vertex in [triangle[2],triangle[1],triangle[0]]:
			surface.set_color(color)
			surface.set_normal(normal)
			surface.add_vertex(vertex)
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = material
	instance.position = center
	parent.add_child(instance)
	return instance

func building(row: Dictionary, tier: int) -> Node3D:
	var root := Node3D.new()
	var width := float(row.footprint[0])
	var depth := float(row.footprint[1])
	var color := Color.html(row.get("color","d9c396"))
	var dark := Color("625144")
	var roof_color := Color("8a5347")
	box(root,Vector3(0,0.06,0),Vector3(width-0.08,0.12,depth-0.08),Color("a0805d"))
	match row.id:
		"farm":
			box(root,Vector3(0,0.14,0),Vector3(width-0.25,0.12,depth-0.25),Color("625144"))
			for x in 7:
				for z in 4:
					box(root,Vector3(-1.1+x*0.36,0.38,-0.62+z*0.4),Vector3(0.12,0.43,0.12),color)
			for z in [-0.9,0.9]:
				box(root,Vector3(0,0.3,z),Vector3(3,0.07,0.06),dark)
		"well":
			cylinder(root,Vector3(0,0.35,0),0.4,0.55,color)
			cylinder(root,Vector3(0,0.635,0),0.28,0.02,Color("416c80"))
			for x in [-0.34,0.34]:
				box(root,Vector3(x,0.9,0),Vector3(0.08,0.95,0.08),dark)
			roof(root,Vector3(0,1.36,0),1.0,0.85,0.3,roof_color)
		"mill":
			cylinder(root,Vector3(0,1.15,0),0.64,2.2,color,0.42)
			cylinder(root,Vector3(0,2.43,0),0.67,0.65,roof_color,0.0)
			var sails := Node3D.new()
			sails.name = "Sails"
			sails.position = Vector3(0,1.95,0.66)
			root.add_child(sails)
			box(sails,Vector3.ZERO,Vector3(0.16,2.65,0.10),Color("e1cea1"))
			box(sails,Vector3.ZERO,Vector3(2.65,0.16,0.10),Color("e1cea1"))
			cylinder(root,Vector3(0.65,0.27,0.6),0.2,0.4,Color("d0b686"))
		_:
			var height := 1.25 if row.id == "storehouse" else (1.35 if tier > 1 else 0.95)
			box(root,Vector3(0,height/2+0.13,0),Vector3(width-0.38,height,depth-0.35),color)
			roof(root,Vector3(0,height+0.13,0),width-0.1,depth-0.08,0.72,roof_color if tier == 1 else Color("416c80"))
			box(root,Vector3(0,0.50,depth/2-0.15),Vector3(0.40,0.72,0.08),dark)
			for x in [-0.53,0.53]:
				box(root,Vector3(x,0.80,depth/2-0.13),Vector3(0.26,0.29,0.08),Color("dfa66b"))
			if row.id == "bakery":
				box(root,Vector3(0.55,1.85,-0.40),Vector3(0.32,1.2,0.32),Color("826750"))
				box(root,Vector3(0,0.48,1.02),Vector3(1.05,0.1,0.30),dark)
				for x in [-0.3,0,0.3]:
					box(root,Vector3(x,0.62,1.02),Vector3(0.21,0.16,0.20),Color("dfa66b"))
			if row.id == "woodcutter":
				for z in [0.0,0.25,0.5]:
					box(root,Vector3(1.0,0.22,z),Vector3(0.25,0.26,0.8),dark)
			if tier > 1 and row.kind == "house":
				box(root,Vector3(-0.78,0.3,1.03),Vector3(0.35,0.20,0.3),Color("54814d"))
	return root

func terrain(parent: Node3D, grid) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in 40:
		for x in 40:
			var tile: String = grid.terrain_at(Vector2i(x,y))
			var color := Color("829970")
			match tile:
				"forest": color = Color("577462")
				"water": color = Color("6395a3")
				"rock": color = Color("829080")
			color = color.darkened(float((x * 7 + y * 13) % 5) * 0.015)
			var height := -0.08 if tile == "water" else 0.0
			for point in [Vector3(x,height,y),Vector3(x+1,height,y),Vector3(x,height,y+1),Vector3(x+1,height,y),Vector3(x+1,height,y+1),Vector3(x,height,y+1)]:
				surface.set_normal(Vector3.UP)
				surface.set_color(color)
				surface.add_vertex(point)
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = material
	parent.add_child(mesh)
	box(parent,Vector3(20,-0.65,20),Vector3(40,1.1,40),Color("625144"))
