extends RefCounted
const Storage = preload("res://sim/storage.gd")
var uid: int
var definition: Dictionary
var cell: Vector2i
var rotation_quarters := 0
## A house's input slot is its pantry, stocked by carriers.
var input
var output
var inventory
var progress := 0
## Reserved tree/planting site for a forestry cycle; (-1,-1) means none.
var work_cell := Vector2i(-1,-1)
var staffed := false
## Player switch: a stopped building releases its workers and receives no inputs.
var workers_enabled := true
var status := "idle"
var tier := 1
var satisfied_ticks := 0
var unsatisfied_ticks := 0
var needs_next_tick := 0
var needs_ok := false
var missing_need := "water"
## Goods eaten this consumption cycle; happiness is the percentage of needs met.
var needs_met: Dictionary = {}
var happiness := 0
## Happiness at the end of each of the last HAPPINESS_CYCLES completed cycles,
## oldest first. Their average is the house's settled happiness (see needs.gd).
const HAPPINESS_CYCLES := 3
var happiness_history: Array = []
## A storehouse's carriers on shift: carriers are jobs, staffed from idle workers.
var crew := 0
## Money in silver: a household's savings, a workshop's purse for inputs, or a
## storehouse's trading purse. Houses also keep their last payday's wage and
## tax; public buildings (the forester) keep what the treasury last paid them.
var silver := 0
var last_wage := 0
var last_tax := 0
## Public workers left unpaid keep working; each unpaid worker-payday adds one.
var frustration := 0
## Wages this building has passed to the payroll: a producer's labour, or a
## storehouse's markup paid to its carriers.
var wages_paid := 0

func _init(number: int, row: Dictionary, at: Vector2i, orientation: int = 0) -> void:
	uid = number
	definition = row
	cell = at
	rotation_quarters = posmod(orientation, 4)
	input = Storage.new(int(row.input_capacity))
	output = Storage.new(int(row.output_capacity))
	inventory = Storage.new(int(row.get("storage_capacity", 0)))

static func rotated_footprint(row: Dictionary, orientation: int = 0) -> Vector2i:
	var size := Vector2i(int(row.footprint[0]), int(row.footprint[1]))
	return Vector2i(size.y, size.x) if posmod(orientation, 2) == 1 else size

func footprint() -> Vector2i:
	return rotated_footprint(definition, rotation_quarters)

func cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var size := footprint()
	for y in size.y:
		for x in size.x:
			result.append(cell + Vector2i(x, y))
	return result

func snapshot() -> Dictionary:
	return {"uid":uid,"id":definition.id,"cell":[cell.x,cell.y],"rotation_quarters":rotation_quarters,"input":input.items.duplicate(),"output":output.items.duplicate(),"inventory":inventory.items.duplicate(),"progress":progress,"work_cell":[work_cell.x,work_cell.y],"staffed":staffed,"workers_enabled":workers_enabled,"status":status,"tier":tier,"satisfied_ticks":satisfied_ticks,"unsatisfied_ticks":unsatisfied_ticks,"needs_next_tick":needs_next_tick,"needs_ok":needs_ok,"missing_need":missing_need,"needs_met":needs_met.duplicate(),"happiness":happiness,"happiness_history":happiness_history.duplicate(),"crew":crew,"silver":silver,"last_wage":last_wage,"last_tax":last_tax,"frustration":frustration,"wages_paid":wages_paid}

static func from_snapshot(state: Dictionary, content):
	if not content.buildings.has(state.get("id")) or not _point(state.get("cell")) or not _point(state.get("work_cell")):
		return null
	if not _whole(state.get("uid")) or state.uid < 1:
		return null
	var result = load("res://sim/building.gd").new(int(state.uid), content.buildings[state.id], Vector2i(int(state.cell[0]),int(state.cell[1])))
	var expected: Dictionary = result.snapshot()
	if state.size() != expected.size(): return null
	for key in expected:
		if not state.has(key): return null
		if expected[key] is int:
			if not _whole(state[key]) or state[key] < 0: return null
		elif typeof(state[key]) != typeof(expected[key]): return null
		if key not in ["uid","id","cell","work_cell","input","output","inventory"]:
			result.set(key, int(state[key]) if expected[key] is int else state[key].duplicate(true) if state[key] is Dictionary else state[key])
	if not content.tiers.has(result.tier) or result.rotation_quarters > 3: return null
	if state.happiness_history.size() > HAPPINESS_CYCLES: return null
	result.happiness_history = []
	for value in state.happiness_history:
		if not _whole(value) or value < 0 or value > 100: return null
		result.happiness_history.append(int(value))
	result.work_cell = Vector2i(int(state.work_cell[0]),int(state.work_cell[1]))
	for slot in ["input","output","inventory"]:
		var restored = Storage.from_snapshot(state[slot], result.get(slot).capacity)
		if restored == null: return null
		for good in restored.items:
			if not content.goods.has(good): return null
		result.set(slot, restored)
	return result

static func _whole(value) -> bool:
	return (value is int or value is float) and value == int(value)

static func _point(value) -> bool:
	return value is Array and value.size() == 2 and _whole(value[0]) and _whole(value[1])
