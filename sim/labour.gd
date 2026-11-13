extends RefCounted
## Jobs by class, the families who fill them, and whose work earned the
## payroll (docs/PLAN-job-classes.md).
## A job names a class ("jobs" in buildings.json; a row without it has
## `workers` working-class jobs). Classes rank: unclassed and working 1,
## middle 2, elite 3. A worker may take a job of their class or a lower one,
## never a higher one (until schools). Each village house holds one family,
## whose working adults are its workers; the founding adults live in the first
## house. Jobs go round the families of a class in turn, so every family gets
## one job before any gets a second. Staffing is recomputed every tick and
## never saved: a building's `_crew` lists the house uid of each worker it
## employs, and a storehouse's `_keeper` its storekeeper's house.
## Wages follow the work. A producer's labour, a storehouse's markup and a
## service's pay are credited to the families who earned them, as each
## house's `earned`, which payday pays out. Silver nobody earned (a sale made
## while a building stood unstaffed) is shared between all houses by their
## workers, as all wages were before.
const Building = preload("res://sim/building.gd")
## Adults present at founding; they belong to the first house.
const FOUNDERS := 4
const RANKS := {"":1, "working":1, "middle":2, "elite":3}
const TOP_RANK := 3
## A service job's pay per payday, by its class.
const CLASS_WAGE := {"working":10, "middle":20, "elite":30}
## The storekeeper's share of a storehouse's markup; carriers share the rest.
const KEEPER_PERCENT := 30

## A row's jobs by class. A row without `jobs` has `workers` working-class jobs.
static func jobs(row: Dictionary) -> Dictionary:
	if row.has("jobs"):
		var result := {}
		for job_class in row.jobs:
			result[job_class] = int(row.jobs[job_class])
		return result
	var workers := int(row.get("workers", 0))
	return {"working": workers} if workers > 0 else {}

static func rank(job_class: String) -> int:
	return Pools.rank(job_class)

## A house's class: its row's `class`, else its tier's.
static func house_class(sim, house) -> String:
	if sim.has_method("house_class"):
		return sim.house_class(house)
	return str(house.definition.get("class", sim.db.tiers[house.tier].get("class", "")))

## A house's working adults.
static func adults(sim, house) -> int:
	if sim.has_method("family_adults"):
		return sim.family_adults(house)
	return family_adults(sim, house)

## A house's family, drawn once from its row's "family" ranges
## ({"adults":[min,max], "children":[min,max]}) with an RNG seeded by the site
## and the house, so replays and restored saves draw the same family. A row
## without "family" keeps no drawn family.
static func ensure_family(sim, house) -> void:
	var family = house.definition.get("family")
	if house.adults > 0 or not family is Dictionary:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.site.seed_value, house.uid, "family"])
	house.adults = rng.randi_range(int(family.adults[0]), int(family.adults[1]))
	house.children = rng.randi_range(int(family.children[0]), int(family.children[1]))

## The family's working adults, or the tier's workers_per_house for a row with
## no family. The village sim's family_adults() reads this.
static func family_adults(sim, house) -> int:
	ensure_family(sim, house)
	return house.adults if house.adults > 0 else int(sim.db.tiers[house.tier].get("workers_per_house", 1))

## The family's children; none for a row with no family.
static func family_children(sim, house) -> int:
	ensure_family(sim, house)
	return house.children

## Workers free this tick, by family, and the order families are asked in.
class Pools:
	const RANKS := {"":1, "working":1, "middle":2, "elite":3}
	const TOP_RANK := 3

	static func rank(job_class: String) -> int:
		return int(RANKS.get(job_class, 1))

	## Families, by entry: the house uid each belongs to (0 for the founders
	## before any house stands, whose work earns no family), and its adults not
	## yet in a job. A house usually holds one family; an inn's lodgers are one
	## family each, all paid to the inn.
	var homes: Array[int] = []
	var free: Array[int] = []
	## Rank -> family entries of that rank, in house uid order.
	var by_rank := {}
	## Rank -> where the next search starts, so jobs go round the families.
	var next := {}

	func _init() -> void:
		for value in range(1, TOP_RANK + 1):
			by_rank[value] = []
			next[value] = 0

	## Adds a family of `count` adults, or with `singles` that many families of
	## one adult each, living at this house.
	func add(uid: int, family_rank: int, count: int, singles: bool = false) -> void:
		for family in (count if singles else 1):
			by_rank[family_rank].append(homes.size())
			homes.append(uid)
			free.append(1 if singles else count)

	## Free workers of each rank.
	func counts() -> Dictionary:
		var result := {}
		for value in by_rank:
			var total := 0
			for entry in by_rank[value]:
				total += free[entry]
			result[value] = total
		return result

	func total() -> int:
		var result := 0
		for count in free:
			result += count
		return result

	## Whether every job can be filled: the highest jobs first, each from its
	## own rank upward, lowest first.
	func can_fill(wanted: Dictionary) -> bool:
		var left: Dictionary = counts()
		for job_class in _by_rank_desc(wanted):
			var need := int(wanted[job_class])
			for value in range(rank(job_class), TOP_RANK + 1):
				var taken: int = mini(need, int(left[value]))
				left[value] -= taken
				need -= taken
			if need > 0:
				return false
		return true

	## Fills the jobs, in the order can_fill() checked them. Returns the house
	## uid of each worker.
	func fill(wanted: Dictionary) -> Array:
		var result: Array = []
		for job_class in _by_rank_desc(wanted):
			for slot in int(wanted[job_class]):
				var uid := take(rank(job_class))
				if uid >= 0:
					result.append(uid)
		return result

	## One worker of at least this rank, from the lowest rank that has one, and
	## within a rank from the next family round. Returns its house uid, or -1.
	func take(lowest: int) -> int:
		for value in range(lowest, TOP_RANK + 1):
			var list: Array = by_rank[value]
			var count := list.size()
			for step in count:
				var index: int = (int(next[value]) + step) % count
				var entry: int = list[index]
				if free[entry] > 0:
					free[entry] -= 1
					next[value] = (index + 1) % count
					return homes[entry]
		return -1

	static func _by_rank_desc(wanted: Dictionary) -> Array:
		var classes: Array = wanted.keys()
		classes.sort_custom(func(a, b): return rank(a) > rank(b) or (rank(a) == rank(b) and str(a) < str(b)))
		return classes

## Every family's free workers this tick, in house uid order.
static func pools(sim) -> Pools:
	var result := Pools.new()
	var uids: Array = []
	for building in sim.buildings.values():
		if building.definition.kind == "house":
			uids.append(building.uid)
	uids.sort()
	if uids.is_empty():
		result.add(0, 1, FOUNDERS)
		return result
	for index in uids.size():
		var house = sim.buildings[uids[index]]
		var count: int = adults(sim, house)
		var singles: bool = bool(house.definition.get("lodgers", false))
		result.add(house.uid, rank(house_class(sim, house)), count, singles)
		if index == 0:
			# The founding adults live in the first house, as one more family.
			result.add(house.uid, rank(house_class(sim, house)), FOUNDERS)
	return result

## Staffs workplaces and carriers by pay: high, then normal, then low.
## Within a level, buildings take their whole crews in placement order, then
## that level's storehouses take a storekeeper (if a family of high enough
## class is free) and put carriers on shift, up to their carrier count.
## Carriers already on a trip count first so they can finish it; the rest of
## a crew goes to idle carriers in order. Off-shift carriers wait at home.
## Returns the workers still idle.
static func staff(sim) -> int:
	var free: Pools = pools(sim)
	var shifts: Dictionary = {}
	for level in [Building.HIGH, Building.NORMAL, Building.LOW]:
		for building in sim.buildings.values():
			# Halls have no jobs, so they are never staffed.
			if building.pay != level or building.definition.kind in ["storehouse", "hall"]:
				continue
			var wanted: Dictionary = jobs(building.definition)
			building.staffed = building.workers_enabled and free.can_fill(wanted)
			building._crew = free.fill(wanted) if building.staffed else []
		for building in sim.buildings.values():
			if building.pay != level or building.definition.kind != "storehouse":
				continue
			building.staffed = building.workers_enabled
			building._keeper = -1
			building._crew = []
			building.crew = 0
			if not building.workers_enabled:
				shifts[building.uid] = 0
				continue
			# A storehouse has at most one job of its own: the storekeeper's.
			for job_class in jobs(building.definition):
				building._keeper = free.take(rank(job_class))
			for slot in int(building.definition.carriers):
				var uid := free.take(1)
				if uid < 0:
					break
				building._crew.append(uid)
			building.crew = building._crew.size()
			shifts[building.uid] = building.crew
	for busy in [true, false]:
		for carrier in sim.carriers:
			if (carrier.stage != "idle") != busy:
				continue
			var left: int = shifts.get(carrier.owner, 0)
			carrier._on_shift = left > 0
			if left > 0:
				shifts[carrier.owner] = left - 1
	return free.total()

## Credits silver earned at a building to the families who did the work: its
## crew, shared equally, the odd silver going round by tick. A storehouse's
## storekeeper takes KEEPER_PERCENT first, and its carriers the rest. With
## nobody to credit, the silver stays in the payroll unattributed.
static func credit(sim, building, amount: int) -> void:
	if amount <= 0:
		return
	var crew: Array = building._crew
	if building.definition.kind == "storehouse" and building._keeper >= 0:
		var share := amount * KEEPER_PERCENT / 100
		_earn(sim, building._keeper, share if not crew.is_empty() else amount)
		amount = amount - share if not crew.is_empty() else 0
	if crew.is_empty() or amount <= 0:
		return
	var each := amount / crew.size()
	var odd := amount % crew.size()
	var offset: int = sim.tick % crew.size()
	for index in crew.size():
		_earn(sim, crew[index], each + (1 if (index - offset + crew.size()) % crew.size() < odd else 0))

## Takes up to `each` silver per worker from what the building's crew's
## families earned (a pay cut), never more than a family earned. Returns the
## silver taken.
static func dock(sim, building, each: int) -> int:
	var taken := 0
	for uid in building._crew:
		var house = sim.buildings.get(uid)
		if house == null:
			continue
		var cut: int = mini(each, house.earned)
		house.earned -= cut
		taken += cut
	return taken

static func _earn(sim, uid: int, amount: int) -> void:
	var house = sim.buildings.get(uid)
	if house != null and amount > 0:
		house.earned += amount

## Every working adult: the founders and each house's family.
static func workforce(sim) -> int:
	var result := FOUNDERS
	for building in sim.buildings.values():
		if building.definition.kind == "house":
			result += adults(sim, building)
	return result

## A service's pay for one payday: each job at its class's wage.
static func service_pay(row: Dictionary) -> int:
	var total := 0
	var wanted: Dictionary = jobs(row)
	for job_class in wanted:
		total += int(CLASS_WAGE.get(job_class, CLASS_WAGE.working)) * int(wanted[job_class])
	return total

## The houses at payday: each house's wage is what its family earned, plus its
## share of anything nobody earned, shared by workers with the odd silver going
## round the houses by payday. Returns the wages by house, in house order.
static func wages(sim, houses: Array) -> Array[int]:
	var attributed := 0
	var workers := 0
	for house in houses:
		attributed += house.earned
		workers += adults(sim, house)
	var pool: int = maxi(0, sim.payroll - attributed)
	var result: Array[int] = []
	var spare := pool
	for house in houses:
		var share: int = pool * adults(sim, house) / maxi(1, workers)
		result.append(house.earned + share)
		spare -= share
	if not houses.is_empty():
		var offset: int = (sim.tick / sim.PAYDAY_TICKS) % houses.size()
		for index in spare:
			result[(offset + index) % houses.size()] += 1
	return result

## Each house's jobs this tick, by house uid: building uids, a storekeeper's
## store included. For the inspector.
static func jobs_by_house(sim) -> Dictionary:
	var result := {}
	for building in sim.buildings.values():
		var holders: Array = building._crew.duplicate()
		if building.definition.kind == "storehouse" and building._keeper >= 0:
			holders.append(building._keeper)
		for uid in holders:
			if not result.has(uid):
				result[uid] = []
			result[uid].append(building.uid)
	return result
