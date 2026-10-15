extends Node3D
## Wild berry bushes drawn where the simulation's bushes grow (sim/forage.gd).
## A bush shows its berries while it has fruit. Size and turn come from seeded
## hashes, so presentation never touches the simulation RNG.
const IntNoise = preload("res://sim/world/int_noise.gd")
var models
var relief
## Cell -> bush node.
var bushes: Dictionary = {}
var signature := ""

func _init(medieval_models) -> void:
	models = medieval_models
	name = "WildBerries"

## A new site: forget every bush.
func build(terrain_relief) -> void:
	relief = terrain_relief
	for node in bushes.values():
		node.queue_free()
	bushes.clear()
	signature = ""

func sync(forage) -> void:
	if relief == null:
		return
	# A per-bush checksum, so one pick and one ripening in a frame still show.
	var sum := 0
	for cell in forage.bushes:
		sum += (int(forage.bushes[cell]) + 1) * (cell.x * 92821 + cell.y * 68917 + 1)
	var next := "%d|%d" % [forage.bushes.size(), sum]
	if next == signature:
		return
	signature = next
	for cell in bushes.keys():
		if not forage.bushes.has(cell):
			bushes[cell].queue_free()
			bushes.erase(cell)
	for cell in forage.bushes:
		var node: Node3D = bushes.get(cell)
		if node == null:
			node = models.model("wild_berry_bush")
			if node == null:
				return
			node.name = "Bush_%d_%d" % [cell.x, cell.y]
			var point := Vector2(cell) + Vector2(0.5, 0.5) + Vector2(IntNoise.unit(5501, cell.x, cell.y, 1) - 0.5, IntNoise.unit(5501, cell.x, cell.y, 2) - 0.5) * 0.4
			node.position = Vector3(point.x, relief.surface_height(point), point.y)
			node.rotation.y = IntNoise.unit(5501, cell.x, cell.y, 3) * TAU
			node.scale = Vector3.ONE * (0.85 + IntNoise.unit(5501, cell.x, cell.y, 4) * 0.4)
			add_child(node)
			bushes[cell] = node
		var berries := node.find_child("Berries", true, false) as Node3D
		if berries != null:
			berries.visible = int(forage.bushes[cell]) > 0
