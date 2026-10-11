extends SceneTree
const VillageSim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var sim = VillageSim.new(73)
	print("starter ok=", Scenario.starter(sim), " ", sim.last_error)
	var chained := false
	var second := false
	var t0 := Time.get_ticks_msec()
	for minute in range(1, 61):
		for s in 60:
			sim.step(10)
			if not chained and sim.unlocked_tier >= 2:
				chained = Scenario.complete_chain(sim)
				if not chained: print("chain fail: ", sim.last_error)
		if chained and not second and minute >= 4:
			var shift: Vector2i = Scenario.offset(sim)
			for c in [Vector2i(21,16),Vector2i(18,16),Vector2i(21,22+1),Vector2i(14,21),Vector2i(25,16),Vector2i(17,23)]:
				if sim.place("house", c + shift):
					second = true
					print("second house at ", c, " minute ", minute)
					break
			if not second and minute == 4: print("second house failed: ", sim.last_error)
		if minute % 6 == 0:
			var tiers := []
			var store = null
			for b in sim.buildings.values():
				if b.definition.id == "house": tiers.append("T%d/%d%%" % [b.tier, b.happiness])
				if b.definition.id == "storehouse": store = b
			print("min %d houses=%s store=%d/%d inv=%s bakery=%s wood=%s" % [minute, str(tiers), store.inventory.total(), store.inventory.capacity, str(store.inventory.items), _st(sim,"bakery"), _st(sim,"woodcutter")])
	print("ms/tick ", float(Time.get_ticks_msec() - t0) / 36000.0)
	quit(0)
func _st(sim, id):
	for b in sim.buildings.values():
		if b.definition.id == id: return b.status
	return "-"
