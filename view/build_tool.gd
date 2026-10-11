extends RefCounted
var selected := "inspect"
var road_start := Vector2i(-1,-1)

func choose(id: String) -> void:
	selected = id
	road_start = Vector2i(-1,-1)

func road_cells(to: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var start := road_start if road_start.x >= 0 else to
	var point := start
	cells.append(point)
	while point.x != to.x:
		point.x += 1 if to.x > point.x else -1
		cells.append(point)
	while point.y != to.y:
		point.y += 1 if to.y > point.y else -1
		cells.append(point)
	return cells
