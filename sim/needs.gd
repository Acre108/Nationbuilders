extends RefCounted
## A house eats from its own pantry, which carriers stock from the closest
## supply. Each need is eaten on its own once per cycle; a need missing at the
## start of a cycle is still met if it arrives before the cycle ends.
## Happiness is the share of the tier's needs met this cycle. Households pay
## for each delivery from their savings, so a poor house goes without.
## Settled happiness is the average over the last few completed cycles. It
## decides demotion, and the village's morale, which sets how fast workplaces work.
const Building = preload("res://sim/building.gd")
## Workplaces work at MIN_WORK_SPEED percent at zero morale, rising evenly to
## full speed at full morale.
const MIN_WORK_SPEED := 50

func update(sim, house) -> void:
	var row: Dictionary = sim.db.tiers[house.tier]
	var consumption: Dictionary = row.consumption
	if sim.tick >= house.needs_next_tick:
		# A cycle that ran (not a new house or a fresh tier) joins the history.
		if house.needs_next_tick > 0:
			house.happiness_history.append(house.happiness)
			if house.happiness_history.size() > Building.HAPPINESS_CYCLES:
				house.happiness_history.pop_front()
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
		house.status = "needs satisfied"
		if sim.db.tiers.has(house.tier + 1) and house.satisfied_ticks >= int(row.upgrade_after_ticks):
			_change_tier(sim, house, house.tier + 1)
			sim.unlocked_tier = maxi(sim.unlocked_tier, house.tier)
			sim.events.append("A homestead became %s at tick %d" % [sim.db.tiers[house.tier].name, sim.tick])
			return
	else:
		house.satisfied_ticks = 0
		# Storehouses charge households a markup, so judge against that price.
		var unaffordable: bool = sim.db.goods.has(house.missing_need) and sim.spendable(house) < sim.economy.retail_price(sim, house.missing_need)
		house.status = ("cannot afford " if unaffordable else "missing ") + house.missing_need
	# One missing good is survivable: a house demotes only when its settled
	# happiness stays below the tier's threshold for the downgrade time.
	if unhappy(sim, house):
		house.unsatisfied_ticks += 1
		if house.tier > 1 and house.unsatisfied_ticks >= int(row.downgrade_after_ticks):
			_change_tier(sim, house, house.tier - 1)
			sim.events.append("A homestead returned to %s at tick %d" % [sim.db.tiers[house.tier].name, sim.tick])
	else:
		house.unsatisfied_ticks = 0

## Average happiness over the house's completed cycles, or -1 before its first.
static func settled(house) -> int:
	if house.happiness_history.is_empty():
		return -1
	var total := 0
	for value in house.happiness_history:
		total += int(value)
	return total / house.happiness_history.size()

static func unhappy(sim, house) -> bool:
	var value := settled(house)
	return value >= 0 and value < int(sim.db.tiers[house.tier].downgrade_below_happiness)

## Village morale: settled happiness averaged over houses, weighted by the
## workers each provides. Houses without a completed cycle are left out; with
## none, morale is full.
static func morale(sim) -> int:
	var total := 0
	var weight := 0
	for building in sim.buildings.values():
		if building.definition.kind != "house":
			continue
		var value := settled(building)
		if value < 0:
			continue
		var workers := int(sim.db.tiers[building.tier].workers_per_house)
		total += value * workers
		weight += workers
	return 100 if weight == 0 else total / weight

## Percentage of full speed that workplaces work at for this morale.
static func work_speed(morale_percent: int) -> int:
	return MIN_WORK_SPEED + (100 - MIN_WORK_SPEED) * clampi(morale_percent, 0, 100) / 100

## A new tier starts a fresh cycle on the next tick, with no history: the old
## tier's happiness says nothing about the new needs. Pantry goods the new tier
## does not eat are hauled back to storage by carriers.
func _change_tier(sim, house, tier: int) -> void:
	house.tier = tier
	house.satisfied_ticks = 0
	house.unsatisfied_ticks = 0
	house.needs_met = {}
	house.needs_ok = false
	house.needs_next_tick = 0
	house.happiness_history = []
