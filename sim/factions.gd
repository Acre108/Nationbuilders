extends RefCounted
## The factions present in a village and their coffers (docs/FACTIONS.md).
## Rows come from data/factions.json. Not every faction comes to a village:
## the site's biome names the middle-class and elite factions it interests, and
## they arrive at founding. The recruiting factions (unions and populists)
## arrive together when the first house reaches a tier of their class. A
## faction that does not list "village" in its settlements (the cultural
## elite) never arrives.
## Coffers are each faction's own purse, in whole silver. An arriving faction
## brings its endowment from outside the village: it goes into the coffers and
## into the sim's outside_money, so treasury, payroll, every building's silver
## and every faction's coffers always sum to FOUNDING_TREASURY + outside_money.
## Income (FACTIONS.md §5.1): a faction-owned workshop or storehouse pays its
## owner a share of each sale's labour or markup, and its purse surplus at
## payday; a rented house pays rent; an aligned house pays dues from its wage.
## Coffers above the cap go back into circulation (FACTIONS.md §7): recruiting
## factions pay relief to members who cannot afford their basket, and the
## others buy goods from a storehouse, which leave the village as consumption.
## The contest for the working class (FACTIONS.md §3.1): at each payday every
## working-class house gets a pull from each present recruiting faction of its
## class, weighted by the faction's `pull` row; a side that leads for long
## enough wins the house. Union halls and alehouses (kind "hall") add to their
## faction's pull within their radius, and belong to that faction.
const Economy = preload("res://sim/economy.gd")
const Needs = preload("res://sim/needs.gd")
const SETTLEMENT := "village"
## Event text when a faction arrives: its name and the tick.
const FACTION_ARRIVED := "The %s arrived in the village at tick %d"
## Event text when the Crown sells a building: faction, building, price, tick.
const BUILDING_SOLD := "The %s bought a %s for %s at tick %d"
## A house's book value is this many paydays of its rent.
const BOOK_PAYDAYS := 12
## Each faction's silver in and out, per payday, for the Factions panel.
const FLOW_KEYS := ["rent","dues","owner_share","relief","purchases"]
## An unaligned house joins a side whose pull leads the best other side by
## JOIN_LEAD or more at JOIN_PAYDAYS paydays running. A member goes over to a
## rival only once the rival leads its own side by LEAVE_LEAD for LEAVE_PAYDAYS.
const JOIN_LEAD := 3
const JOIN_PAYDAYS := 5
const LEAVE_LEAD := 6
const LEAVE_PAYDAYS := 10
## Aligned neighbours count within this many tiles, nearest footprint tile to
## nearest footprint tile (Chebyshev), roads or not.
const NEIGHBOUR_TILES := 6
## Event text: faction, tick; old faction, new faction, tick; old faction, tier, tick.
const HOUSE_JOINED := "A household joined the %s at tick %d"
const HOUSE_SWITCHED := "A household left the %s for the %s at tick %d"
const HOUSE_LAPSED := "A household left the %s on becoming %s at tick %d"

## Silver held by each present faction, by id, in order of arrival. A faction
## is present once it has an entry.
var coffers: Dictionary = {}
## Each present faction's flows (FLOW_KEYS) since the last payday, and over the
## last payday. Owner's share includes a storehouse's purse surplus.
var period: Dictionary = {}
var last_payday: Dictionary = {}
## Each working-class house's pull from each present recruiting faction of its
## class at the last payday, by house uid, then faction id. Derived for the
## inspector and not saved: it is empty after a load until the next payday.
var _pulls: Dictionary = {}

## Whether this faction can be present in a village at all.
static func in_villages(row: Dictionary) -> bool:
	return SETTLEMENT in row.get("settlements", [])

func present(id: String) -> bool:
	return coffers.has(id)

## Silver in every faction's coffers.
func total() -> int:
	var result := 0
	for silver in coffers.values():
		result += int(silver)
	return result

## The site's interested factions arrive when the village is founded.
func found(sim) -> void:
	for id in sim.db.biome_factions.get(sim.site.biome, []):
		_arrive(sim, id)

## Runs every tick. Recruiting factions arrive once a house reaches a tier of
## their class; they arrive in data order, so the result is deterministic. A
## house whose tier changed class (a Villager house back to Settlers) leaves its
## faction at once, and its streak ends.
func update(sim) -> void:
	for id in sim.db.factions:
		var row: Dictionary = sim.db.factions[id]
		if coffers.has(id) or not bool(row.recruits) or not in_villages(row):
			continue
		for building in sim.buildings.values():
			if building.definition.kind == "house" and sim.db.tiers[building.tier].get("class", "") == row["class"]:
				_arrive(sim, id)
				break
	for house in sim.buildings.values():
		if house.definition.kind != "house" or (house.aligned.is_empty() and house.pull_leader.is_empty()):
			continue
		var house_class: String = sim.db.tiers[house.tier]["class"]
		if not house.aligned.is_empty() and sim.db.factions[house.aligned]["class"] != house_class:
			sim.events.append(HOUSE_LAPSED % [sim.db.factions[house.aligned].name, sim.db.tiers[house.tier].name, sim.tick])
			house.aligned = ""
			_end_streak(house)
		if not house.pull_leader.is_empty() and sim.db.factions[house.pull_leader]["class"] != house_class:
			_end_streak(house)

## Called from the economy's payday, after households are paid and taxed. Each
## aligned house pays dues on the wage it just received, then each rented house
## pays rent from its savings; neither takes silver already promised to
## deliveries on their way. Coffers above the cap are then spent, the contest
## for the working class runs (so relief paid this payday counts), and the
## payday's flows become last_payday.
func payday(sim) -> void:
	for house in sim.buildings.values():
		if house.definition.kind != "house":
			continue
		if present(house.aligned):
			var percent := int(sim.db.factions[house.aligned].dues_percent)
			# Rounded to the nearest silver, so small penny dues are not lost.
			_collect(sim, house, house.aligned, ((house.last_wage - house.last_tax) * percent + 50) / 100, "dues")
		if present(house.owner):
			_collect(sim, house, house.owner, rent(sim, house.owner, house.tier), "rent")
	# House uid -> the faction that gave it relief this payday.
	var relieved := {}
	for id in coffers:
		var excess: int = int(coffers[id]) - int(sim.db.factions[id].coffer_cap)
		if excess <= 0:
			continue
		if bool(sim.db.factions[id].recruits):
			_relief(sim, id, excess, relieved)
		else:
			_purchase(sim, id, excess)
	_contest(sim, relieved)
	for id in coffers:
		last_payday[id] = period[id]
		period[id] = blank_flows()

static func blank_flows() -> Dictionary:
	var flows := {}
	for key in FLOW_KEYS:
		flows[key] = 0
	return flows

## Adds silver to a present faction's coffers, recorded under a flow key ("" for
## none, such as a demolished building's purse coming back).
func credit(id: String, amount: int, key: String) -> void:
	coffers[id] = int(coffers[id]) + amount
	if not key.is_empty():
		period[id][key] += amount

## A faction's rent for a house of this tier.
static func rent(sim, id: String, tier: int) -> int:
	return int(sim.db.factions[id].rent.get(str(tier), 0))

## What a house of this tier pays a storehouse for one cycle's goods.
static func basket(sim, tier: int) -> int:
	var total := 0
	var consumption: Dictionary = sim.db.tiers[tier].consumption
	for good in consumption:
		total += sim.economy.retail_price(sim, good) * int(consumption[good])
	return total

## The owner's share of a sale's work (a producer's labour or a storehouse's
## markup), moved to the owner's coffers. It is owner_share_percent of the
## building's running total of work since the sale, so rounding never loses it.
## Returns the share; the rest of the work still pays wages.
func take_owner_share(sim, building, work: int) -> int:
	if work <= 0 or not present(building.owner):
		return 0
	var percent := int(sim.db.factions[building.owner].owner_share_percent)
	var share: int = (building.owner_work + work) * percent / 100 - building.owner_work * percent / 100
	building.owner_work += work
	credit(building.owner, share, "owner_share")
	return share

## What a building is worth to a buyer (FACTIONS.md §5.1). A house is
## BOOK_PAYDAYS of the faction's rent at its tier. A workshop or storehouse is
## its materials at today's chain prices, plus the purse that goes with it.
func book_value(sim, building, id: String) -> int:
	if building.definition.kind == "house":
		return BOOK_PAYDAYS * rent(sim, id, building.tier)
	var materials := 0
	for good in building.definition.cost:
		materials += int(building.definition.cost[good]) * sim.price(good)
	return materials + building.silver

## The favour multiplier on a sale, as a percentage of book value: 75 at −100
## favour, 100 at 0 and 150 at +100. Favour arrives in PLAN-factions.md item 4;
## until then every faction pays book value.
func price_percent(_id: String) -> int:
	return 100

## What this faction would pay for the building.
func sale_price(sim, building, id: String) -> int:
	return book_value(sim, building, id) * price_percent(id) / 100

## Moves up to `amount` from a house's spendable silver into a faction's coffers.
func _collect(sim, house, id: String, amount: int, key: String) -> void:
	var paid := mini(amount, maxi(0, sim.spendable(house)))
	if paid <= 0:
		return
	house.silver -= paid
	credit(id, paid, key)

## Relief from a recruiting faction's excess: member houses that cannot afford
## their basket get the shortfall, smallest first, until the excess runs out.
func _relief(sim, id: String, excess: int, relieved: Dictionary) -> void:
	var needy: Array = []
	for house in sim.buildings.values():
		if house.definition.kind != "house" or house.aligned != id:
			continue
		var short: int = basket(sim, house.tier) - maxi(0, sim.spendable(house))
		if short > 0:
			needy.append([short, house.uid, house])
	needy.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for entry in needy:
		var paid := mini(int(entry[0]), excess)
		if paid <= 0:
			break
		entry[2].silver += paid
		coffers[id] = int(coffers[id]) - paid
		period[id].relief += paid
		relieved[entry[1]] = id
		excess -= paid

## Purchases from an elite or middle-class faction's excess: goods from the
## storehouse nearest its property, at the chain price, one unit at a time from
## the most plentiful good it can afford. The goods are consumed.
func _purchase(sim, id: String, excess: int) -> void:
	var store = _shop(sim, id)
	if store == null:
		return
	while excess > 0:
		var choice := ""
		var most := 0
		for good in sim.db.goods:
			var free: int = store.inventory.count(good) - sim._reserved(store.uid, "inventory", good, true)
			var unit: int = sim.price(good)
			if unit > 0 and unit <= excess and free > most:
				choice = good
				most = free
		if choice.is_empty():
			return
		var cost: int = sim.price(choice)
		store.inventory.take(choice, 1)
		store.silver += cost
		coffers[id] = int(coffers[id]) - cost
		period[id].purchases += cost
		sim.consumed[choice] = int(sim.consumed.get(choice, 0)) + 1
		excess -= cost

## The storehouse with goods nearest by road to any of the faction's buildings,
## or the first one with goods if it owns none that reach one.
func _shop(sim, id: String):
	var stores: Array = sim.buildings.values().filter(func(b): return b.definition.kind == "storehouse" and b.inventory.total() > 0)
	var best = null
	var best_cells := 0
	for building in sim.buildings.values():
		if building.owner != id:
			continue
		for store in stores:
			var cells: int = 0 if store == building else sim.grid.distance(building, store)
			if cells >= 0 and (best == null or cells < best_cells):
				best = store
				best_cells = cells
	if best == null and not stores.is_empty():
		best = stores[0]
	return best

func _arrive(sim, id: String) -> void:
	var row: Dictionary = sim.db.factions.get(id, {})
	if row.is_empty() or coffers.has(id) or not in_villages(row):
		return
	var endowment := int(row.endowment)
	coffers[id] = endowment
	period[id] = blank_flows()
	last_payday[id] = blank_flows()
	sim.outside_money += endowment
	var event: String = FACTION_ARRIVED % [row.name, sim.tick]
	if endowment > 0:
		event += ", bringing " + Economy.format(endowment)
	sim.events.append(event)
	# Halls built for the faction before it came pass to it now.
	for building in sim.buildings.values():
		if building.definition.kind == "hall" and building.definition.recruits_for == id:
			building.owner = id

## Who owns a newly built hall: its faction if present, otherwise the Crown
## until the faction arrives.
func hall_owner(row: Dictionary) -> String:
	return str(row.recruits_for) if present(str(row.recruits_for)) else ""

## The contest for the working class, run at each payday (FACTIONS.md §3.1).
## Every pull is computed first, from alignments as they stood, and only then
## do houses join or switch, so the order of houses never matters. Houses are
## visited in uid order and nothing is random.
func _contest(sim, relieved: Dictionary) -> void:
	_pulls.clear()
	var uids: Array = sim.buildings.keys()
	uids.sort()
	for uid in uids:
		var house = sim.buildings[uid]
		if house.definition.kind != "house":
			continue
		var house_class: String = sim.db.tiers[house.tier]["class"]
		var pulls := {}
		for id in sim.db.factions:
			if present(id) and bool(sim.db.factions[id].recruits) and not house_class.is_empty() and sim.db.factions[id]["class"] == house_class:
				pulls[id] = pull(sim, house, id, relieved.get(uid, "") == id)
		if not pulls.is_empty():
			_pulls[uid] = pulls
	for uid in _pulls:
		_decide(sim, sim.buildings[uid], _pulls[uid])

## One payday of a house's streak. An unaligned house follows the side leading
## the best other side by JOIN_LEAD; a member follows the rival leading its own
## side by LEAVE_LEAD. Ties lead nobody: the first in data order wins only when
## strictly ahead.
func _decide(sim, house, pulls: Dictionary) -> void:
	var own: String = house.aligned
	var leader := ""
	var lead := 0
	if own.is_empty():
		var top := -1
		var second := 0
		for id in pulls:
			if int(pulls[id]) > top:
				second = maxi(second, top)
				top = int(pulls[id])
				leader = id
			else:
				second = maxi(second, int(pulls[id]))
		lead = top - second
	else:
		var best := -1
		for id in pulls:
			if id != own and int(pulls[id]) > best:
				best = int(pulls[id])
				leader = id
		lead = best - int(pulls.get(own, 0))
	var needed := JOIN_LEAD if own.is_empty() else LEAVE_LEAD
	if leader.is_empty() or lead < needed:
		_end_streak(house)
		return
	house.pull_streak = house.pull_streak + 1 if house.pull_leader == leader else 1
	house.pull_leader = leader
	if house.pull_streak < (JOIN_PAYDAYS if own.is_empty() else LEAVE_PAYDAYS):
		return
	house.aligned = leader
	_end_streak(house)
	var joined: String = sim.db.factions[leader].name
	sim.events.append(HOUSE_JOINED % [joined, sim.tick] if own.is_empty() else HOUSE_SWITCHED % [sim.db.factions[own].name, joined, sim.tick])

## Whether a restored building's alignment and streak are possible: a house's
## faction and streak leader share its tier's class, and the streak is shorter
## than the one that would already have moved it.
func contest_state_valid(sim, building) -> bool:
	if building.definition.kind != "house":
		return building.aligned.is_empty() and building.pull_leader.is_empty()
	var house_class: String = sim.db.tiers[building.tier]["class"]
	for id in [building.aligned, building.pull_leader]:
		if not id.is_empty() and sim.db.factions[id]["class"] != house_class:
			return false
	return building.pull_streak < (JOIN_PAYDAYS if building.aligned.is_empty() else LEAVE_PAYDAYS)

static func _end_streak(house) -> void:
	house.pull_leader = ""
	house.pull_streak = 0

## Paydays until the house joins (or switches to) its streak's leader if the
## lead holds, or -1 with no streak. For the inspector.
static func paydays_to_change(house) -> int:
	if house.pull_leader.is_empty():
		return -1
	return (JOIN_PAYDAYS if house.aligned.is_empty() else LEAVE_PAYDAYS) - house.pull_streak

## A working-class house's pull from a recruiting faction, from the weights in
## its `pull` row (FACTIONS.md §3.1). Terms the row leaves out add nothing; a
## cap ("idle_cap", "neighbour_cap") limits its term when present.
## - employment: × the share of the village's workers in jobs (staffed
##   workplaces and carriers on shift), rounded down.
## - wages_in_full: when the house's wage last payday was at least WAGE for each
##   of its workers the village employed (its workers × the employed share).
##   Wages come from labour sold, so idle shelves or a low markup (carriers'
##   pay) leave it short.
## - idle_worker: per idle worker in the village.
## - need_unmet: per need the house goes without, from settled happiness:
##   round((100 − settled) × needs ÷ 100), none before its first full cycle.
## - markup_over / markup_step: one per markup_step points the markup is above
##   markup_over.
## - hall: a hall of this faction within its radius, by road
##   (the same measure as a chapel's service radius).
## - neighbour: per house of this faction within NEIGHBOUR_TILES.
## - relief: the faction gave the house relief this payday.
func pull(sim, house, id: String, relieved: bool = false) -> int:
	var weights: Dictionary = sim.db.factions[id].get("pull", {})
	var total := 0
	var workforce: int = sim.workforce()
	var employed: int = workforce - sim.idle_workers
	total += int(weights.get("employment", 0)) * employed / maxi(1, workforce)
	if weights.has("wages_in_full") and wages_in_full(sim, house):
		total += int(weights.wages_in_full)
	total += _capped(weights, "idle_worker", "idle_cap", sim.idle_workers)
	total += int(weights.get("need_unmet", 0)) * needs_unmet(sim, house)
	if weights.has("markup_step") and sim.markup_percent > int(weights.get("markup_over", 0)):
		total += (sim.markup_percent - int(weights.get("markup_over", 0))) / int(weights.markup_step)
	if weights.has("hall") and hall_in_reach(sim, house, id):
		total += int(weights.hall)
	if weights.has("neighbour"):
		var neighbours := 0
		for other in sim.buildings.values():
			if other != house and other.definition.kind == "house" and other.aligned == id and gap(house, other) <= NEIGHBOUR_TILES:
				neighbours += 1
		total += _capped(weights, "neighbour", "neighbour_cap", neighbours)
	if relieved:
		total += int(weights.get("relief", 0))
	return total

## Whether the house's last wage paid a full WAGE for each of its workers the
## village employed: last_wage ≥ WAGE × its workers × employed ÷ workforce.
static func wages_in_full(sim, house) -> bool:
	var workforce: int = sim.workforce()
	var employed: int = workforce - sim.idle_workers
	var workers := int(sim.db.tiers[house.tier].workers_per_house)
	return house.last_wage > 0 and house.last_wage * workforce >= Economy.WAGE * workers * employed

## Needs the house goes without, from its settled happiness (see pull()).
static func needs_unmet(sim, house) -> int:
	var settled: int = Needs.settled(house)
	if settled < 0:
		return 0
	var tier: Dictionary = sim.db.tiers[house.tier]
	var needs: int = tier.consumption.size() + Needs.counted_services(tier).size()
	return ((100 - settled) * needs + 50) / 100

## Whether a hall recruiting for this faction is within its radius of the house
## by road.
static func hall_in_reach(sim, house, id: String) -> bool:
	for hall in sim.buildings.values():
		if hall.definition.kind == "hall" and hall.definition.recruits_for == id:
			var cells: int = sim.grid.distance(hall, house)
			if cells >= 0 and cells <= int(hall.definition.radius):
				return true
	return false

## Tiles between two buildings' nearest footprint tiles (Chebyshev): 1 when
## they touch.
static func gap(a, b) -> int:
	var a_end: Vector2i = a.cell + a.footprint() - Vector2i.ONE
	var b_end: Vector2i = b.cell + b.footprint() - Vector2i.ONE
	var dx := maxi(0, maxi(b.cell.x - a_end.x, a.cell.x - b_end.x))
	var dy := maxi(0, maxi(b.cell.y - a_end.y, a.cell.y - b_end.y))
	return maxi(dx, dy)

static func _capped(weights: Dictionary, term: String, cap: String, count: int) -> int:
	var value := int(weights.get(term, 0)) * count
	return mini(value, int(weights[cap])) if weights.has(cap) else value

## The pulls computed for this house at the last payday, by faction id.
func last_pulls(house) -> Dictionary:
	return _pulls.get(house.uid, {})

func snapshot() -> Dictionary:
	var state := {}
	for id in coffers:
		state[id] = {"coffers":coffers[id],"period":period[id].duplicate(),"last_payday":last_payday[id].duplicate()}
	return state

## Replaces the roster from a snapshot. Returns false, leaving it unchanged, for
## an unknown faction, one that never comes to a village, bad coffers or flows,
## or any other field.
func restore(state, db) -> bool:
	if not state is Dictionary:
		return false
	var restored := {}
	var restored_period := {}
	var restored_last := {}
	for id in state:
		var entry = state[id]
		if not id is String or not db.factions.has(id) or not in_villages(db.factions[id]):
			return false
		if not entry is Dictionary or entry.size() != 3 or not _whole(entry.get("coffers")) or entry.coffers < 0:
			return false
		if not _valid_flows(entry.get("period")) or not _valid_flows(entry.get("last_payday")):
			return false
		restored[id] = int(entry.coffers)
		restored_period[id] = _whole_flows(entry.period)
		restored_last[id] = _whole_flows(entry.last_payday)
	coffers = restored
	period = restored_period
	last_payday = restored_last
	return true

static func _valid_flows(flows) -> bool:
	if not flows is Dictionary or flows.size() != FLOW_KEYS.size():
		return false
	for key in FLOW_KEYS:
		if not _whole(flows.get(key)) or flows[key] < 0:
			return false
	return true

static func _whole_flows(flows: Dictionary) -> Dictionary:
	var result := {}
	for key in FLOW_KEYS:
		result[key] = int(flows[key])
	return result

static func _whole(value) -> bool:
	return (value is int or value is float) and value == int(value)
