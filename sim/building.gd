extends RefCounted
const Storage = preload("res://sim/storage.gd")
var uid: int
var definition: Dictionary
var cell: Vector2i
var input
var output
var inventory
var progress := 0
var staffed := false
var status := "idle"
var tier := 1
var satisfied_ticks := 0
var unsatisfied_ticks := 0
var needs_next_tick := 0
var needs_ok := false
var missing_need := "water"

func _init(number: int, row: Dictionary, at: Vector2i) -> void:
	uid = number
	definition = row
	cell = at
	input = Storage.new(int(row.input_capacity))
	output = Storage.new(int(row.output_capacity))
	inventory = Storage.new(int(row.get("storage_capacity", 0)))

func cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in int(definition.footprint[1]):
		for x in int(definition.footprint[0]):
			result.append(cell + Vector2i(x, y))
	return result

func snapshot() -> Dictionary:
	return {"uid":uid,"id":definition.id,"cell":[cell.x,cell.y],"input":input.items.duplicate(),"output":output.items.duplicate(),"inventory":inventory.items.duplicate(),"progress":progress,"staffed":staffed,"status":status,"tier":tier,"satisfied_ticks":satisfied_ticks,"unsatisfied_ticks":unsatisfied_ticks,"needs_next_tick":needs_next_tick,"needs_ok":needs_ok,"missing_need":missing_need}
