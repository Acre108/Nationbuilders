extends SceneTree
## Long-run stability soak for the starter village. Headless:
##   Godot.exe --headless --path . --script tools/soak_village.gd -- [--minutes=60] [--houses=2] [--seed=73]
##       [--no-forester] [--every=N] [--tax=PERCENT] [--store-pay=low|normal|high]
## Places the scripted starter, then the mill, bakery, a forester and any extra
## houses at the first promotion, and prints one row per sampled minute.
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const Economy = preload("res://sim/economy.gd")
## Extra houses beside the vertical road, in milestone 1 layout coordinates.
const EXTRA_HOUSES := [Vector2i(21,23), Vector2i(18,23), Vector2i(21,15)]

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var minutes := 60
	var houses := 2
	var seed_value := 73
	var forester := true
	var every := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--minutes="): minutes = int(argument.get_slice("=", 1))
		elif argument.begins_with("--houses="): houses = int(argument.get_slice("=", 1))
		elif argument.begins_with("--seed="): seed_value = int(argument.get_slice("=", 1))
		elif argument.begins_with("--every="): every = int(argument.get_slice("=", 1))
		elif argument == "--no-forester": forester = false
	var sim = Sim.new(seed_value)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--tax="): sim.set_tax_percent(int(argument.get_slice("=", 1)))
	if not Scenario.starter(sim):
		printerr("Starter failed: " + sim.last_error)
		quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--store-pay="):
			for building in sim.buildings.values():
				if building.definition.kind == "storehouse": sim.set_pay(building.uid, ["low", "normal", "high"].find(argument.get_slice("=", 1)))
	while sim.unlocked_tier < 2 and sim.tick < 3000:
		sim.step(1)
	if not Scenario.complete_chain(sim):
		printerr("Chain failed: " + sim.last_error)
		quit(1)
		return
	for index in houses - 1:
		if not sim.place("house", EXTRA_HOUSES[index] + Scenario.offset(sim)):
			printerr("House %d failed: %s" % [index + 2, sim.last_error])
	if forester and not sim.place("forester", Vector2i(26,21) + Scenario.offset(sim)):
		printerr("Forester failed: " + sim.last_error)
	print("Promotion at tick %d; %d houses; forester %s; seed %d" % [sim.tick, houses, forester, seed_value])
	print("min | store    | bread water logs berry wheat flour | treasury | houses (tier, purse, status) | mill / bakery / woodcutter | ms/tick")
	var marks := [1, 3, 6, 10, 15, 20, 30, 40, 50, 60, 90, 120]
	var started_tick: int = sim.tick
	var elapsed := 0
	for minute in range(1, minutes + 1):
		var clock := Time.get_ticks_usec()
		while sim.tick < started_tick + minute * 600:
			sim.step(1)
		elapsed += Time.get_ticks_usec() - clock
		if minute in marks or minute == minutes or (every > 0 and minute % every == 0):
			print(_row(sim, minute, elapsed / 1000.0 / float(minute * 600)))
	quit(0)

func _row(sim, minute: int, ms_per_tick: float) -> String:
	var houses: Array[String] = []
	var workshops := {}
	var store_fill := 0
	var store_capacity := 0
	for building in sim.buildings.values():
		match building.definition.kind:
			"house": houses.append("T%d %s %s" % [building.tier, Economy.format(building.silver), building.status])
			"storehouse":
				store_fill += building.inventory.total()
				store_capacity += building.inventory.capacity
			"producer": workshops[building.definition.id] = building.status
	return "%3d | %3d/%-4d | %5d %5d %4d %5d %5d %5d | %8s | %s | %s / %s / %s | %.3f" % [minute, store_fill, store_capacity, sim.stock("bread"), sim.stock("water"), sim.stock("logs"), sim.stock("berries"), sim.stock("wheat"), sim.stock("flour"), Economy.format(sim.treasury), "; ".join(houses), workshops.get("mill", "-"), workshops.get("bakery", "-"), workshops.get("woodcutter", "-"), ms_per_tick]
