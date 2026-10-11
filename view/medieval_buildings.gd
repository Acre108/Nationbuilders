extends RefCounted
## Blender-authored kit and presentation-only local inventory displays.
const ASSET_DIR := "res://assets/buildings/medieval/"
const MODELS := ["house", "storehouse", "farm", "well", "woodcutter", "forester", "mill", "bakery"]
const GOODS := ["wheat", "flour", "water", "logs", "bread"]
var materials: Dictionary
var scenes: Dictionary = {}
var meshes: Dictionary = {}

func _init(mesh_factory) -> void:
	materials = {"plain": mesh_factory.material, "roof": mesh_factory.roof_material, "wall": mesh_factory.wall_material}

func model(id: String) -> Node3D:
	if not scenes.has(id):
		var path := ASSET_DIR + id + ".glb"
		if not ResourceLoader.exists(path): return null
		scenes[id] = load(path)
	var node: Node3D = scenes[id].instantiate()
	_apply_palette(node, id)
	return node

func _apply_palette(node: Node, id: String) -> void:
	if node is MeshInstance3D:
		var key := id + "/" + str(node.name)
		if not meshes.has(key):
			# Consolidate palette colours into shared shader surfaces. Each model
			# shares one converted mesh across all placements and stock instances.
			var groups: Dictionary = {}
			for surface in node.mesh.get_surface_count():
				var source: Material = node.mesh.surface_get_material(surface)
				var tokens: PackedStringArray = source.resource_name.split("_")
				var kind := str(tokens[0])
				var colour := Color.html(tokens[1]).srgb_to_linear() if tokens.size() > 1 else Color.WHITE
				if not groups.has(kind):
					var tool := SurfaceTool.new()
					tool.begin(Mesh.PRIMITIVE_TRIANGLES)
					groups[kind] = tool
				var arrays: Array = node.mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var tool: SurfaceTool = groups[kind]
				for index in indices:
					tool.set_color(colour)
					tool.set_normal(normals[index])
					tool.add_vertex(vertices[index])
			var mesh := ArrayMesh.new()
			for kind in groups:
				var tool: SurfaceTool = groups[kind]
				tool.index()
				tool.set_material(materials.get(kind, materials.plain))
				tool.commit(mesh)
			meshes[key] = mesh
		node.mesh = meshes[key]
	for child in node.get_children(): _apply_palette(child, id)

func building(row: Dictionary, tier: int) -> Node3D:
	if not str(row.id) in MODELS: return null
	var id := "house_tier2" if row.id == "house" and tier > 1 else str(row.id)
	var root := model(id)
	if root == null: return null
	root.set_meta("medieval", true)
	var sails := root.find_child("Sails", true, false)
	if sails != null:
		# Put the authored pivot directly under the wrapper for the existing animation.
		if sails.get_parent() != root: sails.reparent(root, true)
	add_stock_root(root, row)
	return root

func add_stock_root(root: Node3D, row: Dictionary) -> void:
	if row.kind == "producer":
		var stock := Node3D.new()
		stock.name = "Stock"
		root.add_child(stock)
		for lane in ["Input", "Output"]:
			var group := Node3D.new()
			group.name = lane
			stock.add_child(group)

func sync_stock(root: Node3D, building_state) -> void:
	if not root.has_node("Stock"): return
	_sync_lane(root.get_node("Stock/Input"), building_state.input.items, str(building_state.definition.id), true, building_state.input.capacity)
	_sync_lane(root.get_node("Stock/Output"), building_state.output.items, str(building_state.definition.id), false, building_state.output.capacity)

func _sync_lane(lane: Node3D, items: Dictionary, id: String, input: bool, capacity: int) -> void:
	if lane.get_meta("items", {}) == items: return
	lane.set_meta("items", items.duplicate())
	for child in lane.get_children(): child.visible = false
	var goods: Array = items.keys()
	goods.sort()
	var slot := 0
	for good in goods:
		for unit in mini(int(items[good]), maxi(0, capacity-slot)):
			var name := str(good) + "_" + str(unit)
			var prop := lane.get_node_or_null(NodePath(name)) as Node3D
			if prop == null:
				prop = model("stock_" + (str(good) if str(good) in GOODS else "crate"))
				if prop == null: continue
				prop.name = name
				prop.set_meta("good", str(good))
				lane.add_child(prop)
			prop.visible = true
			prop.position = _stock_position(id, input, slot)
			slot += 1

func _stock_position(id: String, input: bool, slot: int) -> Vector3:
	match id:
		"well":
			return Vector3(-0.34+float(slot%3)*0.34, 0.02+float(slot/3)*0.29, 0.38)
		"farm":
			return Vector3(0.62+float(slot%3)*0.27, 0.15+float(slot/3)*0.38, 0.65)
		"woodcutter":
			return Vector3(0.64, 0.18+float(slot/3)*0.31, -0.54+float(slot%3)*0.32)
		"bakery":
			if input: return Vector3(-0.88, 0.21, -0.76+float(slot)*0.28)
			return Vector3(-0.45+float(slot%4)*0.30, 0.35, 0.59+float(slot/4)*0.25)
		"mill":
			if input: return Vector3(-0.76, 0.17+float(slot/3)*0.35, -0.52+float(slot%3)*0.34)
			return Vector3(0.66, 0.22+float(slot/3)*0.30, -0.05+float(slot%3)*0.33)
	return Vector3(-0.40+float(slot%3)*0.32, 0.15+float(slot/3)*0.30, 0.76)
