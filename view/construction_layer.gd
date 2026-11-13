extends Node3D
## Construction sites (VillageSim.sites) on the map. A site is a dug plot with
## scaffold poles at its corners and a pale blueprint of the building to come.
## Each unit of material that arrives drops onto a pile beside it with a knock.
## Once every unit is there the blueprint gives way to the real building,
## rising out of the plot as the pile is used up. The view pops the finished
## building in its place (sync() returns the sites that finished).
const BUILDING_PREVIEW = preload("res://render/building_preview.gdshader")
const PLOT_COLOUR := Color("8b6b4a")
const POLE_COLOUR := Color("a07c52")
const BLUEPRINT_TINT := Color("efe4c4")
## Units laid on each layer of a pile, and its spacing.
const PILE_ROW := 3
const UNIT := Vector3(0.36, 0.09, 0.1)
## How quickly the rising building follows the sim's ticks, per second.
const RISE_FOLLOW := 6.0
var factory
var relief
var sounds
var nodes: Dictionary = {}
## Units on each site's pile last frame, to hear and see new arrivals.
var piles: Dictionary = {}
## Skip the arrival effects on the first sync after a village loads.
var quiet := true

func _init(mesh_factory, terrain_relief, ui_sounds) -> void:
	factory = mesh_factory
	relief = terrain_relief
	sounds = ui_sounds
	name = "construction"

func reset() -> void:
	for node in nodes.values():
		node.queue_free()
	nodes.clear()
	piles.clear()
	quiet = true

## Brings the sites up to date. Returns the uids of sites that became buildings
## since the last call, for the view to celebrate.
func sync(sim, delta: float) -> Array:
	var finished: Array = []
	for uid in nodes.keys():
		if sim.sites.has(uid):
			continue
		if sim.buildings.has(uid):
			finished.append(uid)
		nodes[uid].queue_free()
		nodes.erase(uid)
		piles.erase(uid)
	for site in sim.sites.values():
		var node: Node3D = nodes.get(site.uid)
		if node == null:
			node = _site_node(sim, site)
			add_child(node)
			nodes[site.uid] = node
			piles[site.uid] = site.materials.total()
			_fill_pile(sim, site, node, site.materials.total(), false)
			if not quiet:
				pop(node, Vector3(1.0, 0.2, 1.0))
		_update(sim, site, node, delta)
	quiet = false
	return finished

func _site_node(sim, site) -> Node3D:
	var row: Dictionary = site.definition
	var size := Vector2(float(row.footprint[0]), float(row.footprint[1]))
	var footprint: Vector2i = site.footprint()
	var node := Node3D.new()
	node.position = Vector3(site.cell.x + float(footprint.x) / 2.0, relief.cell_height(site.cell), site.cell.y + float(footprint.y) / 2.0)
	node.rotation.y = site.rotation_quarters * PI / 2.0
	factory.box(node, Vector3(0, 0.02, 0), Vector3(size.x - 0.12, 0.04, size.y - 0.12), PLOT_COLOUR)
	var poles := Node3D.new()
	poles.name = "Poles"
	node.add_child(poles)
	var half := Vector2(size.x / 2.0 - 0.12, size.y / 2.0 - 0.12)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		factory.box(poles, Vector3(corner.x * half.x, 0.6, corner.y * half.y), Vector3(0.07, 1.2, 0.07), POLE_COLOUR)
	# A rail along the two long sides ties the poles together.
	for side in [-1.0, 1.0]:
		factory.box(poles, Vector3(0, 1.05, side * half.y), Vector3(size.x - 0.2, 0.05, 0.05), POLE_COLOUR)
	var blueprint: Node3D = factory.building(row, site.tier)
	blueprint.name = "Blueprint"
	var material := ShaderMaterial.new()
	material.shader = BUILDING_PREVIEW
	material.set_shader_parameter("tint", BLUEPRINT_TINT)
	_apply_material(blueprint, material)
	node.add_child(blueprint)
	var rising: Node3D = factory.building(row, site.tier)
	rising.name = "Rising"
	rising.scale = Vector3(1.0, 0.02, 1.0)
	rising.visible = false
	node.add_child(rising)
	var pile := Node3D.new()
	pile.name = "Pile"
	# The pile sits in the plot's front corner, clear of the scaffold.
	pile.position = Vector3(-size.x / 2.0 + 0.32, 0.04, size.y / 2.0 - 0.22)
	node.add_child(pile)
	return node

func _update(sim, site, node: Node3D, delta: float) -> void:
	var build: int = sim.build_ticks(site.definition)
	var building: bool = site.status == "building"
	var blueprint: Node3D = node.get_node("Blueprint")
	var rising: Node3D = node.get_node("Rising")
	blueprint.visible = not building
	rising.visible = building
	if building:
		var target := lerpf(0.06, 1.0, float(site.progress) / float(build))
		rising.scale.y = lerpf(rising.scale.y, target, minf(1.0, delta * RISE_FOLLOW))
	# The pile fills as materials arrive, then is used up as the building rises.
	var held: int = site.materials.total()
	var shown := held if not building else int(ceil(float(held) * (1.0 - float(site.progress) / float(build))))
	var previous: int = piles.get(site.uid, 0)
	if held > previous and not building:
		sounds.play("deliver", randf_range(0.92, 1.1))
	if shown != node.get_node("Pile").get_child_count() or held != previous:
		_fill_pile(sim, site, node, shown, held > previous and not building)
	piles[site.uid] = held

## Lays `count` units on the pile in the colours of the goods delivered. With
## `drop`, the newest unit bounces into place.
func _fill_pile(sim, site, node: Node3D, count: int, drop: bool) -> void:
	var pile: Node3D = node.get_node("Pile")
	for child in pile.get_children():
		pile.remove_child(child)
		child.queue_free()
	var colours: Array = []
	for good in site.definition.cost:
		for index in site.materials.count(good):
			colours.append(Color.html(sim.db.goods[good].get("color", "9c7a50")))
	for index in mini(count, colours.size()):
		var layer := index / PILE_ROW
		var across := index % PILE_ROW
		var at := Vector3(0, UNIT.y / 2.0 + layer * UNIT.y, (across - 1) * (UNIT.z + 0.02))
		# Alternate layers cross, like a stacked woodpile.
		var unit: MeshInstance3D = factory.box(pile, at, UNIT, colours[index])
		if layer % 2 == 1:
			unit.rotation.y = PI / 2.0
			unit.position = Vector3((across - 1) * (UNIT.z + 0.02), at.y, 0)
		if drop and index == count - 1:
			unit.position.y += 0.35
			var tween := unit.create_tween()
			tween.tween_property(unit, "position:y", at.y, 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

## A squash-and-settle pop from `from` scale to rest, for new things on the map.
static func pop(node: Node3D, from: Vector3) -> void:
	node.scale = from
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3(1.06, 1.1, 1.06), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## A one-shot puff of dust over a footprint centred at `at`, `size` cells wide.
func dust(at: Vector3, size: Vector2) -> void:
	var puff := CPUParticles3D.new()
	puff.one_shot = true
	puff.explosiveness = 0.85
	puff.amount = int(clampf(size.x * size.y * 6.0, 10.0, 40.0))
	puff.lifetime = 0.9
	puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	puff.emission_box_extents = Vector3(size.x / 2.0, 0.05, size.y / 2.0)
	puff.direction = Vector3.UP
	puff.spread = 70.0
	puff.initial_velocity_min = 0.6
	puff.initial_velocity_max = 1.4
	puff.gravity = Vector3(0, -1.2, 0)
	puff.damping_min = 1.5
	puff.damping_max = 2.5
	puff.scale_amount_min = 0.6
	puff.scale_amount_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(0.86, 0.78, 0.62, 0.7))
	fade.set_color(1, Color(0.86, 0.78, 0.62, 0.0))
	puff.color_ramp = fade
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.12, 0.12)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	puff.mesh = mesh
	puff.position = at + Vector3(0, 0.1, 0)
	add_child(puff)
	puff.emitting = true
	puff.finished.connect(puff.queue_free)

static func _apply_material(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_apply_material(child, material)
