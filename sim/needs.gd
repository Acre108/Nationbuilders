extends RefCounted
## A house eats from its own pantry, which carriers stock from the closest
## supply. Each need is eaten on its own once per cycle; a need missing at the
## start of a cycle is still met if it arrives before the cycle ends.
## Happiness is the share of the tier's needs met this cycle. Households pay
## for each delivery from their savings, so a poor house goes without.

func update(sim, house) -> void:
	var row: Dictionary = sim.db.tiers[house.tier]
	var consumption: Dictionary = row.consumption
	if sim.tick >= house.needs_next_tick:
		house.needs_met = {}
		house.needs_next_tick = sim.tick + int(row.consume_every_ticks)
	for good in consumption:
		if not house.needs_met.has(good) and house.input.take(good, int(consumption[good])):
			house.needs_met[good] = true
			sim.consumed[good] = int(sim.consumed.get(good, 0)) + int(consumption[good])
	house.happiness = 100 * house.needs_met.size() / maxi(1, consumption.size())
	house.needs_ok = house.needs_met.size() == consumption.size()
	house.missing_need = ""
	if not house.needs_ok:
		if sim.grid.access(house).is_empty():
			house.missing_need = "road access"
		else:
			for good in consumption:
				if not house.needs_met.has(good):
					house.missing_need = good
					break
	if house.needs_ok:
		house.satisfied_ticks += 1
		house.unsatisfied_ticks = 0
		house.status = "needs satisfied"
		if sim.db.tiers.has(house.tier + 1) and house.satisfied_ticks >= int(row.upgrade_after_ticks):
			_change_tier(sim, house, house.tier + 1)
			sim.unlocked_tier = maxi(sim.unlocked_tier, house.tier)
			sim.events.append("A homestead became %s at tick %d" % [sim.db.tiers[house.tier].name, sim.tick])
	else:
		house.satisfied_ticks = 0
		house.unsatisfied_ticks += 1
		var unaffordable: bool = sim.db.goods.has(house.missing_need) and sim.spendable(house) < sim.price(house.missing_need)
		house.status = ("cannot afford " if unaffordable else "missing ") + house.missing_need
		if house.tier > 1 and house.unsatisfied_ticks >= int(row.downgrade_after_ticks):
			_change_tier(sim, house, house.tier - 1)
			sim.events.append("A homestead returned to %s at tick %d" % [sim.db.tiers[house.tier].name, sim.tick])

## A new tier starts a fresh cycle on the next tick. Pantry goods the new tier
## does not eat are hauled back to storage by carriers.
func _change_tier(sim, house, tier: int) -> void:
	house.tier = tier
	house.satisfied_ticks = 0
	house.unsatisfied_ticks = 0
	house.needs_met = {}
	house.needs_ok = false
	house.needs_next_tick = sim.tick + 1
