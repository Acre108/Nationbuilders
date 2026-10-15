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

## Favour (FACTIONS.md §4), from −FAVOUR_LIMIT to +FAVOUR_LIMIT. Each payday it
## moves FAVOUR_STEP toward the target set by the stance table.
const FAVOUR_STEP := 5
const FAVOUR_LIMIT := 100
## One-off favour jumps: to the faction whose offer was accepted or declined,
## or whose pledge was kept or broken; to the buyer of any sale; to the unions
## when a house goes to a landlord; to the owner of a demolished building.
const OFFER_ACCEPTED := 10
const OFFER_DECLINED := -5
const PLEDGE_KEPT := 10
const PLEDGE_BROKEN := -40
const BUYER_PLEASED := 5
const HOUSE_SOLD := -5
const DEMOLISHED := -15
## Stance rows that count only above a level (FACTIONS.md §4): tax and markup
## above 10%, a rival's power share above 15%. Happiness counts from 50%.
const TAX_OVER := 10
const MARKUP_OVER := 10
const POWER_OVER := 15
const HAPPINESS_MID := 50
## Houses sold to landlords count against the unions for this many paydays.
const SALES_PAYDAYS := 30
## Power bands by share (FACTIONS.md §3): below WEAK, below ORGANISED, below
## STRONG, and dominant from STRONG up.
const WEAK := 5
const ORGANISED := 15
const STRONG := 30

## Offers (FACTIONS.md §5.3). A faction considers one every OFFER_PAYDAYS,
## staggered by its place in arrival order, while it has none open and is not
## blocked; an offer lapses OFFER_EXPIRY paydays after it is made. Breaking a
## pledge blocks the faction's offers for BLOCK_PAYDAYS.
const OFFER_PAYDAYS := 5
const OFFER_EXPIRY := 3
const BLOCK_PAYDAYS := 30
## A pledge runs PLEDGE_PAYDAYS and is worth PLEDGE_SILVER per payday, scaled
## by the faction's power band (BAND_PERCENT, weak first), and capped by its
## coffers. A faction with less than MIN_OFFER to spend makes no offer.
const PLEDGE_PAYDAYS := 10
const PLEDGE_SILVER := 10
const BAND_PERCENT := [50, 100, 150, 200]
const MIN_OFFER := 10
## An organising offer pays toward a hall placed within this many tiles of the
## house it names, nearest footprint tile to nearest footprint tile.
const ORGANISE_TILES := 8
const OFFER_TYPES := ["bid", "pledge", "organise"]
## The pledges a village can hold, with the text for the panel and errors.
## A pledge locks its lever while it runs: tax_cap and markup_cap hold the
## lever at TAX_OVER and MARKUP_OVER or below, markup_floor at its level or
## above; no_house_sales stops house sales; no_workplace_stopped stops the
## player stopping workers. woodland_kept cannot be locked, so it breaks at a
## payday that finds fewer trees than its level.
const VILLAGE_PLEDGES := {
	"tax_cap": "tax at or below 10%",
	"markup_cap": "markup at or below 10%",
	"markup_floor": "markup at %d%% or higher",
	"no_house_sales": "no house sold to a landlord",
	"no_workplace_stopped": "no workplace stopped",
	"woodland_kept": "woodland kept at %d trees or more",
}
## Event text: faction, the offer's description, tick.
const OFFER_MADE := "The %s offer %s at tick %d"
## Event text: faction, the pledge's description, tick.
const PLEDGE_MADE := "The Crown pledged to the %s: %s, at tick %d"
const PLEDGE_KEPT_TEXT := "The Crown kept its pledge to the %s: %s, at tick %d"
const PLEDGE_BROKEN_TEXT := "The Crown broke its pledge to the %s: %s, at tick %d"
const HALL_FUNDED := "The %s paid %s toward the %s at tick %d"

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
## Each present faction's favour toward the Crown, by id.
var favour: Dictionary = {}
## Each present faction's open offer, by id, or {} for none. An offer has a
## `type` (OFFER_TYPES), the `silver` it pays, the tick it `expires`, and a
## building `uid` (the bid's building, or the house an organising offer names)
## or a `pledge` type. A faction has at most one, so its id is the offer's id.
var offers: Dictionary = {}
## Each present faction's running pledges, by id: `type`, the tick it runs
## `until`, its `level` (a markup floor or a tree count, else 0) and the
## `silver` paid for it. Its id is "<faction>:<type>".
var pledges: Dictionary = {}
## The tick until which each faction makes no offers (a broken pledge).
var blocked_until: Dictionary = {}
## The ticks at which each faction bought a house, for the houses_sold term.
var sales: Dictionary = {}
## Trees on the site when each faction arrived, for woodland_lost.
var trees: Dictionary = {}

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
	_drift(sim)
	_run_pledges(sim)
	_run_offers(sim)
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
## favour, 100 at 0 and 150 at +100, in a straight line either side of 0.
func price_percent(id: String) -> int:
	var value := int(favour.get(id, 0))
	return 100 + (value / 4 if value < 0 else value / 2)

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
	favour[id] = 0
	offers[id] = {}
	pledges[id] = []
	blocked_until[id] = 0
	sales[id] = []
	trees[id] = sim.grid.trees.size()
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

## Silver behind the Crown, each present faction and nobody (FACTIONS.md §3),
## by "crown", faction id and "unaligned". A faction holds its coffers, the
## savings of houses aligned with it and the purses of workshops and
## storehouses it owns; a rented house's savings follow its alignment, not its
## landlord. The Crown holds the treasury and its own buildings' purses.
## Unaligned is every other house's savings. Payroll waiting for payday is
## left out. Derived, so never saved.
func power(sim) -> Dictionary:
	var result := {"crown":sim.treasury, "unaligned":0}
	for id in coffers:
		result[id] = int(coffers[id])
	for building in sim.buildings.values():
		var holder := "crown"
		if building.definition.kind == "house":
			holder = building.aligned if present(building.aligned) else "unaligned"
		elif present(building.owner):
			holder = building.owner
		result[holder] += building.silver
	return result

## Power as whole percentages of the total, rounded down, by the keys of power().
func shares(sim) -> Dictionary:
	var silver: Dictionary = power(sim)
	var total := 0
	for value in silver.values():
		total += maxi(0, int(value))
	var result := {}
	for key in silver:
		result[key] = maxi(0, int(silver[key])) * 100 / total if total > 0 else 0
	return result

## A faction's power band: 0 weak, 1 organised, 2 strong, 3 dominant.
static func band(share: int) -> int:
	if share < WEAK:
		return 0
	if share < ORGANISED:
		return 1
	return 2 if share < STRONG else 3

## Each stance term of a present faction's row, by term, as its whole share of
## the favour target (FACTIONS.md §4): the row's weight × the measure below,
## rounded. Strikes and riots do not happen in villages, so that term is 0.
## - tax, markup: points above TAX_OVER and MARKUP_OVER.
## - idle_workers: idle workers now.
## - unpaid_public_workers: public workers unpaid per payday over the ledger.
## - rent: average rent per house per payday, Crown houses paying none.
## - houses_sold: houses sold to landlords in the last SALES_PAYDAYS.
## - buildings_owned: buildings the faction owns.
## - happiness: average settled happiness of its houses − HAPPINESS_MID, or 0
##   while none has settled.
## - woodland_lost: percent of the trees present at its arrival since lost.
## - union_power, populist_power: points of that faction's share above POWER_OVER.
func stance_terms(sim, id: String) -> Dictionary:
	var weights: Dictionary = sim.db.factions[id].stance
	var result := {}
	var cached_shares := {}
	for term in weights:
		var measure := 0.0
		match term:
			"tax":
				measure = maxi(0, sim.tax_percent - TAX_OVER)
			"markup":
				measure = maxi(0, sim.markup_percent - MARKUP_OVER)
			"idle_workers":
				measure = sim.idle_workers
			"unpaid_public_workers":
				var unpaid := 0
				for entry in sim.ledger:
					unpaid += ceili(float(entry.unpaid) / Economy.WAGE)
				measure = float(unpaid) / maxi(1, sim.ledger.size())
			"rent":
				var houses := 0
				var rents := 0
				for house in sim.buildings.values():
					if house.definition.kind == "house":
						houses += 1
						if present(house.owner):
							rents += rent(sim, house.owner, house.tier)
				measure = float(rents) / maxi(1, houses)
			"houses_sold":
				measure = houses_sold(sim)
			"buildings_owned":
				for building in sim.buildings.values():
					if building.owner == id:
						measure += 1
			"happiness":
				var count := 0
				var total := 0
				for house in sim.buildings.values():
					if house.definition.kind == "house" and house.aligned == id and Needs.settled(house) >= 0:
						count += 1
						total += Needs.settled(house)
				measure = float(total) / count - HAPPINESS_MID if count > 0 else 0.0
			"woodland_lost":
				var before := int(trees.get(id, 0))
				if before > 0:
					measure = maxi(0, 100 - sim.grid.trees.size() * 100 / before)
			"union_power", "populist_power":
				if cached_shares.is_empty():
					cached_shares = shares(sim)
				measure = maxi(0, int(cached_shares.get(term.trim_suffix("_power"), 0)) - POWER_OVER)
		result[term] = roundi(float(weights[term]) * measure)
	return result

## The favour a faction drifts toward: its stance terms, summed and clamped.
func target(sim, id: String) -> int:
	var total := 0
	for value in stance_terms(sim, id).values():
		total += int(value)
	return clampi(total, -FAVOUR_LIMIT, FAVOUR_LIMIT)

## Houses bought by any faction in the last SALES_PAYDAYS.
func houses_sold(sim) -> int:
	var count := 0
	for id in sales:
		for tick in sales[id]:
			if sim.tick - int(tick) < SALES_PAYDAYS * sim.PAYDAY_TICKS:
				count += 1
	return count

## Moves a present faction's favour by a one-off amount, within the limits.
func jump(id: String, amount: int) -> void:
	if present(id):
		favour[id] = clampi(int(favour[id]) + amount, -FAVOUR_LIMIT, FAVOUR_LIMIT)

## Each present faction's favour takes one step toward its target; house sales
## too old to count are forgotten.
func _drift(sim) -> void:
	for id in coffers:
		favour[id] = int(move_toward(int(favour[id]), target(sim, id), FAVOUR_STEP))
		sales[id] = sales[id].filter(func(tick): return sim.tick - int(tick) < SALES_PAYDAYS * sim.PAYDAY_TICKS)

## A pledge's id, and the text for the panel and errors.
static func pledge_id(id: String, pledge: Dictionary) -> String:
	return "%s:%s" % [id, pledge.type]

static func pledge_text(pledge: Dictionary) -> String:
	var text: String = VILLAGE_PLEDGES[pledge.type]
	return text % int(pledge.level) if "%d" in text else text

## Ends pledges that ran their course (+PLEDGE_KEPT) and breaks woodland
## pledges whose trees fell below the level.
func _run_pledges(sim) -> void:
	for id in coffers:
		for pledge in pledges[id].duplicate():
			if pledge.type == "woodland_kept" and sim.grid.trees.size() < int(pledge.level):
				_break(sim, id, pledge)
			elif sim.tick >= int(pledge.until):
				pledges[id].erase(pledge)
				jump(id, PLEDGE_KEPT)
				sim.events.append(PLEDGE_KEPT_TEXT % [sim.db.factions[id].name, pledge_text(pledge), sim.tick])

func _break(sim, id: String, pledge: Dictionary) -> void:
	pledges[id].erase(pledge)
	jump(id, PLEDGE_BROKEN)
	blocked_until[id] = sim.tick + BLOCK_PAYDAYS * sim.PAYDAY_TICKS
	offers[id] = {}
	sim.events.append(PLEDGE_BROKEN_TEXT % [sim.db.factions[id].name, pledge_text(pledge), sim.tick])

## The running pledge that forbids a change, as an error naming it, or "".
## Levers: "tax" and "markup" with the new percent, "house_sale" and
## "stop_workplace".
func forbids(sim, lever: String, value: int = 0) -> String:
	for id in coffers:
		for pledge in pledges[id]:
			var locked := false
			match pledge.type:
				"tax_cap":
					locked = lever == "tax" and value > TAX_OVER
				"markup_cap":
					locked = lever == "markup" and value > MARKUP_OVER
				"markup_floor":
					locked = lever == "markup" and value < int(pledge.level)
				"no_house_sales":
					locked = lever == "house_sale"
				"no_workplace_stopped":
					locked = lever == "stop_workplace"
			if locked:
				return "Pledged to the %s: %s" % [sim.db.factions[id].name, pledge_text(pledge)]
	return ""

## Lapses offers that expired or no longer make sense, then lets each faction
## whose turn it is make one. Turns are staggered by arrival order, and the
## choice comes from an RNG seeded by the site, the tick and the faction, so
## replays and restored saves choose the same.
func _run_offers(sim) -> void:
	var payday_index: int = sim.tick / sim.PAYDAY_TICKS
	var order: int = 0
	for id in coffers:
		var offer: Dictionary = offers[id]
		if not offer.is_empty() and (sim.tick >= int(offer.expires) or not offer_possible(sim, id, offer)):
			offers[id] = {}
		if offers[id].is_empty() and sim.tick >= int(blocked_until[id]) and (payday_index + order) % OFFER_PAYDAYS == 0:
			var choices: Array = candidates(sim, id)
			if not choices.is_empty():
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([sim.site.seed_value, sim.tick, id])
				var chosen: Dictionary = choices[rng.randi_range(0, choices.size() - 1)]
				chosen["expires"] = sim.tick + OFFER_EXPIRY * sim.PAYDAY_TICKS
				offers[id] = chosen
				sim.events.append(OFFER_MADE % [sim.db.factions[id].name, describe(sim, id, chosen), sim.tick])
		order += 1

## Every offer a faction could make now, in a stable order: bids for Crown
## buildings it buys (unless a pledge forbids the sale), pledges it seeks that
## are not running, and, for a recruiting faction, organising offers for each
## unaligned house of its class with none of its halls within ORGANISE_TILES.
func candidates(sim, id: String) -> Array:
	var row: Dictionary = sim.db.factions[id]
	var spend := int(coffers[id])
	var result: Array = []
	if spend < MIN_OFFER:
		return result
	var uids: Array = sim.buildings.keys()
	uids.sort()
	for uid in uids:
		var building = sim.buildings[uid]
		var bid := {"type":"bid", "uid":uid, "silver":0}
		if building.owner.is_empty() and id in building.definition.get("buyers", []) and offer_possible(sim, id, bid):
			bid.silver = sale_price(sim, building, id)
			if bid.silver <= spend:
				result.append(bid)
	var share: int = int(shares(sim).get(id, 0))
	var value: int = mini(spend, PLEDGE_SILVER * PLEDGE_PAYDAYS * BAND_PERCENT[band(share)] / 100)
	for type in row.pledges:
		var pledge := {"type":"pledge", "pledge":type, "silver":value}
		if VILLAGE_PLEDGES.has(type) and offer_possible(sim, id, pledge):
			result.append(pledge)
	var hall_id := hall_for(sim, id)
	if bool(row.recruits) and not hall_id.is_empty():
		var price: int = mini(spend, sim.economy.construction_price(sim, sim.db.buildings[hall_id]))
		for uid in uids:
			var organise := {"type":"organise", "uid":uid, "silver":price}
			if offer_possible(sim, id, organise):
				result.append(organise)
	return result

## Whether an offer still makes sense: its building stands and is the Crown's,
## its pledge is not already running and would not mean nothing, or its house
## is still an unaligned house of the faction's class with no hall near.
func offer_possible(sim, id: String, offer: Dictionary) -> bool:
	match offer.type:
		"bid":
			var building = sim.buildings.get(int(offer.uid))
			if building == null or not building.owner.is_empty() or id not in building.definition.get("buyers", []):
				return false
			return building.definition.kind != "house" or forbids(sim, "house_sale").is_empty()
		"pledge":
			for pledge in pledges[id]:
				if pledge.type == offer.pledge:
					return false
			# No house sales means something only while a landlord could buy.
			if offer.pledge == "no_house_sales":
				for other in coffers:
					if "house" in _buys(sim, other):
						return true
				return false
			return true
		"organise":
			var house = sim.buildings.get(int(offer.uid))
			if house == null or house.definition.kind != "house" or not house.aligned.is_empty():
				return false
			if sim.db.tiers[house.tier]["class"] != sim.db.factions[id]["class"]:
				return false
			for hall in sim.buildings.values():
				if hall.definition.kind == "hall" and hall.definition.recruits_for == id and gap(hall, house) <= ORGANISE_TILES:
					return false
			return true
	return false

## Building ids a faction buys.
static func _buys(sim, id: String) -> Array:
	var result: Array = []
	for building_id in sim.db.buildings:
		if id in sim.db.buildings[building_id].get("buyers", []):
			result.append(building_id)
	return result

## The hall building that recruits for this faction, or "".
static func hall_for(sim, id: String) -> String:
	for building_id in sim.db.buildings:
		if sim.db.buildings[building_id].kind == "hall" and sim.db.buildings[building_id].recruits_for == id:
			return building_id
	return ""

## An offer in words, for events and the panel.
func describe(sim, id: String, offer: Dictionary) -> String:
	var silver: String = Economy.format(int(offer.silver))
	match offer.type:
		"bid":
			return "%s for the %s" % [silver, sim.buildings[int(offer.uid)].definition.name.to_lower()]
		"pledge":
			var level := _pledge_level(sim, offer.pledge)
			return "%s for %d paydays of %s" % [silver, PLEDGE_PAYDAYS, pledge_text({"type":offer.pledge, "level":level})]
		"organise":
			var house = sim.buildings[int(offer.uid)]
			return "%s toward a %s within %d tiles of the house at %d,%d" % [silver, sim.db.buildings[hall_for(sim, id)].name.to_lower(), ORGANISE_TILES, house.cell.x, house.cell.y]
	return silver

## The level a pledge would hold if made now: the markup for a floor, the
## tree count for woodland, else 0.
static func _pledge_level(sim, type: String) -> int:
	match type:
		"markup_floor":
			return sim.markup_percent
		"woodland_kept":
			return sim.grid.trees.size()
	return 0

## Accepts a faction's open offer (its id is the faction's). A bid sells the
## building as sell_building() does. A pledge first applies its lever (tax and
## markup caps lower the lever, no_workplace_stopped restarts stopped
## workplaces), and fails if another pledge forbids that, then pays its silver.
## An organising offer is accepted by placing the hall, so this refuses it.
## On success the faction gains OFFER_ACCEPTED favour.
func accept(sim, id: String) -> bool:
	var offer: Dictionary = offers.get(id, {})
	if offer.is_empty():
		sim.last_error = "No open offer from the %s" % (sim.db.factions[id].name if sim.db.factions.has(id) else id)
		return false
	match offer.type:
		"bid":
			if not sim.sell_building(int(offer.uid), id):
				return false
		"organise":
			var hall: Dictionary = sim.db.buildings[hall_for(sim, id)]
			sim.last_error = "Place a %s within %d tiles of the house to accept" % [hall.name.to_lower(), ORGANISE_TILES]
			return false
		"pledge":
			var silver := mini(int(offer.silver), int(coffers[id]))
			if offer.pledge == "tax_cap" and sim.tax_percent > TAX_OVER and not sim.set_tax_percent(TAX_OVER):
				return false
			if offer.pledge == "markup_cap" and sim.markup_percent > MARKUP_OVER and not sim.set_markup_percent(MARKUP_OVER):
				return false
			if offer.pledge == "no_workplace_stopped":
				for building in sim.buildings.values():
					if int(building.definition.workers) > 0:
						building.workers_enabled = true
			var pledge := {"type":offer.pledge, "until":sim.tick + PLEDGE_PAYDAYS * sim.PAYDAY_TICKS, "level":_pledge_level(sim, offer.pledge), "silver":silver}
			pledges[id].append(pledge)
			coffers[id] = int(coffers[id]) - silver
			sim.treasury += silver
			sim.period.deals += silver
			sim.events.append(PLEDGE_MADE % [sim.db.factions[id].name, pledge_text(pledge), sim.tick])
	offers[id] = {}
	jump(id, OFFER_ACCEPTED)
	sim.last_error = ""
	return true

## Declines a faction's open offer: it closes, and the faction loses
## OFFER_DECLINED favour.
func decline(sim, id: String) -> bool:
	if offers.get(id, {}).is_empty():
		sim.last_error = "No open offer from the %s" % (sim.db.factions[id].name if sim.db.factions.has(id) else id)
		return false
	offers[id] = {}
	jump(id, OFFER_DECLINED)
	sim.last_error = ""
	return true

## Breaks a running pledge by id ("<faction>:<type>"): PLEDGE_BROKEN favour,
## and the faction's offers stop for BLOCK_PAYDAYS. Its silver is not repaid.
func break_pledge(sim, pledge: String) -> bool:
	var parts := pledge.split(":")
	if parts.size() == 2 and pledges.has(parts[0]):
		for running in pledges[parts[0]]:
			if running.type == parts[1]:
				_break(sim, parts[0], running)
				sim.last_error = ""
				return true
	sim.last_error = "No such pledge: " + pledge
	return false

## A sale was made: the buyer is pleased, and a house going to a landlord
## costs the unions and counts against them for SALES_PAYDAYS.
func sold(sim, building, id: String) -> void:
	jump(id, BUYER_PLEASED)
	if building.definition.kind == "house":
		sales[id].append(sim.tick)
		jump("union", HOUSE_SOLD)
	# A sale settles that faction's bid for the building, if it had one.
	if offers[id].get("type", "") == "bid" and int(offers[id].uid) == building.uid:
		offers[id] = {}

## A faction's building was demolished.
func lost_building(building) -> void:
	jump(building.owner, DEMOLISHED)

## A hall was placed: a matching organising offer pays its silver to the
## treasury (as a deal) and counts as accepted.
func hall_placed(sim, hall) -> void:
	var id: String = hall.definition.recruits_for
	var offer: Dictionary = offers.get(id, {})
	if offer.get("type", "") != "organise" or not sim.buildings.has(int(offer.uid)):
		return
	if gap(hall, sim.buildings[int(offer.uid)]) > ORGANISE_TILES:
		return
	var silver := mini(int(offer.silver), int(coffers[id]))
	coffers[id] = int(coffers[id]) - silver
	sim.treasury += silver
	sim.period.deals += silver
	offers[id] = {}
	jump(id, OFFER_ACCEPTED)
	sim.events.append(HALL_FUNDED % [sim.db.factions[id].name, Economy.format(silver), hall.definition.name.to_lower(), sim.tick])

func snapshot() -> Dictionary:
	var state := {}
	for id in coffers:
		state[id] = {"coffers":coffers[id],"period":period[id].duplicate(),"last_payday":last_payday[id].duplicate(),"favour":favour[id],"offer":offers[id].duplicate(),"pledges":pledges[id].duplicate(true),"blocked_until":blocked_until[id],"sales":sales[id].duplicate(),"trees":trees[id]}
	return state

## Keys of a faction's snapshot entry; an entry with only the first three is
## from before favour and offers, and loads with neutral favour, no offer or
## pledges, and no woodland baseline.
const ENTRY_KEYS := ["coffers","period","last_payday","favour","offer","pledges","blocked_until","sales","trees"]

## Replaces the roster from a snapshot. Returns false, leaving it unchanged, for
## an unknown faction, one that never comes to a village, bad coffers or flows,
## favour out of range, a malformed offer or pledge, or any other field.
## Offers name buildings, which load later: references_valid() checks them.
func restore(state, db) -> bool:
	if not state is Dictionary:
		return false
	var restored := {}
	for key in ENTRY_KEYS:
		restored[key] = {}
	for id in state:
		var entry = state[id]
		if not id is String or not db.factions.has(id) or not in_villages(db.factions[id]):
			return false
		if not entry is Dictionary or not _whole(entry.get("coffers")) or entry.coffers < 0:
			return false
		var legacy: bool = entry.size() == 3
		if not legacy and entry.size() != ENTRY_KEYS.size():
			return false
		for key in ENTRY_KEYS:
			if not entry.has(key) and not (legacy and ENTRY_KEYS.find(key) >= 3):
				return false
		if not _valid_flows(entry.get("period")) or not _valid_flows(entry.get("last_payday")):
			return false
		restored.coffers[id] = int(entry.coffers)
		restored.period[id] = _whole_flows(entry.period)
		restored.last_payday[id] = _whole_flows(entry.last_payday)
		if legacy:
			entry = {"favour":0, "offer":{}, "pledges":[], "blocked_until":0, "sales":[], "trees":0}
		if not _whole(entry.favour) or absi(int(entry.favour)) > FAVOUR_LIMIT:
			return false
		for key in ["blocked_until", "trees"]:
			if not _whole(entry[key]) or entry[key] < 0:
				return false
		if not entry.sales is Array or not entry.sales.all(func(tick): return _whole(tick) and tick >= 0):
			return false
		var offer = _restore_offer(entry.offer, db, id)
		var running = _restore_pledges(entry.pledges, db, id)
		if offer == null or running == null:
			return false
		restored.favour[id] = int(entry.favour)
		restored.offer[id] = offer
		restored.pledges[id] = running
		restored.blocked_until[id] = int(entry.blocked_until)
		restored.sales[id] = entry.sales.map(func(tick): return int(tick))
		restored.trees[id] = int(entry.trees)
	coffers = restored.coffers
	period = restored.period
	last_payday = restored.last_payday
	favour = restored.favour
	offers = restored.offer
	pledges = restored.pledges
	blocked_until = restored.blocked_until
	sales = restored.sales
	trees = restored.trees
	return true

## A restored offer with whole numbers, or null if malformed.
static func _restore_offer(offer, db, id: String):
	if not offer is Dictionary:
		return null
	if offer.is_empty():
		return {}
	if offer.get("type") not in OFFER_TYPES or offer.size() != 4 or not _whole(offer.get("silver")) or offer.silver < 0 or not _whole(offer.get("expires")) or offer.expires < 0:
		return null
	if offer.type == "pledge":
		if not offer.get("pledge") is String or not VILLAGE_PLEDGES.has(offer.pledge) or offer.pledge not in db.factions[id].pledges:
			return null
		return {"type":"pledge", "pledge":offer.pledge, "silver":int(offer.silver), "expires":int(offer.expires)}
	if not _whole(offer.get("uid")) or offer.uid < 0:
		return null
	if offer.type == "organise" and not bool(db.factions[id].recruits):
		return null
	return {"type":offer.type, "uid":int(offer.uid), "silver":int(offer.silver), "expires":int(offer.expires)}

## Restored pledges with whole numbers, or null if malformed or repeated.
static func _restore_pledges(running, db, id: String):
	if not running is Array:
		return null
	var result: Array = []
	var seen := {}
	for pledge in running:
		if not pledge is Dictionary or pledge.size() != 4 or not pledge.get("type") is String or not VILLAGE_PLEDGES.has(pledge.type) or pledge.type not in db.factions[id].pledges or seen.has(pledge.type):
			return null
		for key in ["until", "level", "silver"]:
			if not _whole(pledge.get(key)) or pledge[key] < 0:
				return null
		seen[pledge.type] = true
		result.append({"type":pledge.type, "until":int(pledge.until), "level":int(pledge.level), "silver":int(pledge.silver)})
	return result

## After buildings load: every bid names a building the faction buys, and
## every organising offer names a house.
func references_valid(sim) -> bool:
	for id in offers:
		var offer: Dictionary = offers[id]
		if offer.is_empty() or offer.type == "pledge":
			continue
		var building = sim.buildings.get(int(offer.uid))
		if building == null:
			return false
		if offer.type == "bid" and id not in building.definition.get("buyers", []):
			return false
		if offer.type == "organise" and building.definition.kind != "house":
			return false
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
