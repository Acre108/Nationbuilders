class_name FurniturePreview
extends RefCounted

## Draws a catalogue object from its primitive geometry nodes, for the test
## scene's carving tool. Deliberately crude -- flat albedo, no material
## families, no lights. It exists so a carved patch has something visible
## sitting on it, not to render furniture properly.


static func build(catalogue: FurnitureCatalogue, object_id: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = String(object_id)
	for node in catalogue.object_nodes(object_id):
		var size := Vector3(float(node["size"]["x"]), float(node["size"]["y"]), float(node["size"]["z"]))
		var instance := MeshInstance3D.new()
		instance.mesh = _unit_mesh(node["shape"])
		instance.position = Vector3(float(node["position"]["x"]), float(node["position"]["y"]), float(node["position"]["z"]))
		instance.rotation.y = deg_to_rad(float(node.get("yaw", 0.0)))
		# Unit meshes scaled to size, so ellipsoids and oval tables come out
		# right without per-shape radius bookkeeping.
		instance.scale = size
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(node.get("color", "#888888"))
		material.roughness = 0.8
		instance.material_override = material
		root.add_child(instance)
	return root


static func _unit_mesh(shape: String) -> Mesh:
	match shape:
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.5
			cylinder.bottom_radius = 0.5
			cylinder.height = 1.0
			return cylinder
		"cone":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.5
			cone.height = 1.0
			return cone
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			return sphere
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	return box
