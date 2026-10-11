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

static func from_snapshot(state: Dictionary):
	var validator = load("res://sim/building.gd")
	if not validator._point(state.get("cell")) or not validator._whole(state.get("uid")) or not validator._whole(state.get("owner")):
		return null
	if state.uid < 1 or state.owner < 1: return null
	var result = load("res://sim/carrier.gd").new(int(state.uid),int(state.owner),Vector2i(int(state.cell[0]),int(state.cell[1])))
	var expected: Dictionary = result.snapshot()
	if expected.size() != state.size(): return null
	for key in expected:
		if not state.has(key): return null
		if expected[key] is int:
			if not validator._whole(state[key]): return null
		elif typeof(expected[key]) != typeof(state[key]): return null
		if key not in ["cell","path"]: result.set(key, int(state[key]) if expected[key] is int else state[key].duplicate(true) if state[key] is Dictionary else state[key])
	for point in state.path:
		if not validator._point(point): return null
		result.path.append(Vector2i(int(point[0]),int(point[1])))
	if result.stage not in ["idle","pickup","delivery"] or result.move_ticks < 0: return null
	return result
