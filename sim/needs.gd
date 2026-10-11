extends RefCounted

func update(sim, house) -> void:
	var row: Dictionary = sim.db.tiers[house.tier]
	var store = sim.nearest_store(house)
	if store == null:
		house.needs_ok = false
		house.missing_need = "road to storehouse"
	elif sim.tick >= house.needs_next_tick:
		house.needs_ok = store.inventory.has_all(row.consumption)
		house.missing_need = ""
		if house.needs_ok:
			for good in row.consumption:
				store.inventory.take(good, int(row.consumption[good]))
				sim.consumed[good] = int(sim.consumed.get(good, 0)) + int(row.consumption[good])
			house.needs_next_tick = sim.tick + int(row.consume_every_ticks)
		else:
			for good in row.consumption:
				if store.inventory.count(good) < int(row.consumption[good]):
					house.missing_need = good
					break
	if house.needs_ok:
		house.satisfied_ticks += 1
		house.unsatisfied_ticks = 0
		house.status = "needs satisfied"
		if sim.db.tiers.has(house.tier + 1) and house.satisfied_ticks >= int(row.upgrade_after_ticks):
			house.tier += 1
			sim.unlocked_tier = maxi(sim.unlocked_tier, house.tier)
			house.satisfied_ticks = 0
			house.needs_next_tick = sim.tick
			house.needs_ok = false
			sim.events.append("A homestead became %s at tick %d" % [sim.db.tiers[house.tier].name, sim.tick])
	else:
		house.satisfied_ticks = 0
		house.unsatisfied_ticks += 1
		house.status = "missing " + house.missing_need
		if house.tier > 1 and house.unsatisfied_ticks >= int(row.downgrade_after_ticks):
			house.tier -= 1
			house.unsatisfied_ticks = 0
			house.needs_next_tick = sim.tick
			sim.events.append("A homestead returned to Settlers at tick %d" % sim.tick)
