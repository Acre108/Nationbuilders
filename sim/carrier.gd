extends RefCounted
var uid: int
var owner: int
var cell: Vector2i
var path: Array[Vector2i] = []
var job: Dictionary = {}
var cargo := ""
var stage := "idle"
var move_ticks := 0
var route_revision := -1

func _init(number: int, store: int, at: Vector2i) -> void:
	uid = number
	owner = store
	cell = at

func snapshot() -> Dictionary:
	var route: Array = []
	for point in path:
		route.append([point.x, point.y])
	return {"uid":uid,"owner":owner,"cell":[cell.x,cell.y],"path":route,"job":job.duplicate(true),"cargo":cargo,"stage":stage,"move_ticks":move_ticks,"route_revision":route_revision}
