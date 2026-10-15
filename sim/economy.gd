extends RefCounted
## Village money, held in whole silver; 100 silver make a gold. Every link in a
## chain pays the one before it, so a good costs its inputs plus the labour of
## the building that made it. A producer forwards that labour to the payroll,
## which households share at payday. Storehouses sell to households at a
## markup, which pays their carriers: it goes to the payroll like a producer's
## labour. A storehouse keeps a capped trading purse. The treasury is filled by
## tax on wages and by storehouse surpluses above that cap, and spends gold on
## construction and public services. The player can set part of it aside: a
## public pay reserve and a capital reserve, each closed to the other's spending.
## Money is closed: treasury, payroll, every building's silver and every
## faction's coffers always sum to the founding treasury plus the outside money
## arriving factions brought (factions.gd). Reserves are part of the treasury,
## not extra money.
const SILVER_PER_GOLD := 100
## One worker's labour for one payday, in silver.
const WAGE := 10
const FOUNDING_TREASURY := 1000
const DEFAULT_TAX_PERCENT := 15
## The player sets tax in these steps, up to this limit.
const TAX_STEP := 5
const MAX_TAX_PERCENT := 50
## Storehouses sell to households at this markup on the chain price.
const DEFAULT_MARKUP_PERCENT := 10
const MAX_MARKUP_PERCENT := 100
## Starting money the treasury gives a new household or storehouse.
const HOUSEHOLD_GRANT := 50
const STOREHOUSE_CAPITAL := 100
## A storehouse keeps trading silver up to this cap; the rest goes to the
## treasury at payday.
const PURSE_CAP := 2 * STOREHOUSE_CAPITAL
## Treasury income and spending per payday, for the Treasury panel. Deals are
## silver factions paid the treasury, such as for a building sold to them.
const LEDGER_KEYS := ["tax","trade","refunds","public_pay","construction","unpaid","deals"]
const LEDGER_PAYDAYS := 6
## "Keep services reserved" tops the public pay reserve up to this many
## paydays of the services' upkeep.
const SERVICE_RESERVE_PAYDAYS := 2

## Derived from content: unit price, and the labour part of it, per good.
var prices: Dictionary = {}
var labour: Dictionary = {}

func setup(sim) -> void:
	prices.clear()
	labour.clear()
	for good in sim.db.goods:
		_price(sim, good, [])

## A good made by a building costs its inputs plus that building's labour per
## unit. A good no building makes uses the base price in goods.json.
func _price(sim, good: String, visiting: Array) -> int:
	if prices.has(good):
		return prices[good]
	var maker: Dictionary = {}
	for row in sim.db.buildings.values():
		if row.outputs.has(good):
			maker = row
			break
	if maker.is_empty() or good in visiting:
		labour[good] = 0
		prices[good] = int(sim.db.goods[good].get("price", 0))
		return prices[good]
	var units := 0
	for amount in maker.outputs.values():
		units += int(amount)
	var inputs_cost := 0
	for input in maker.inputs:
		inputs_cost += _price(sim, input, visiting + [good]) * int(maker.inputs[input])
	labour[good] = ceili(float(WAGE * int(maker.workers) * int(maker.cycle_ticks)) / float(sim.PAYDAY_TICKS * units))
	prices[good] = ceili(float(inputs_cost) / float(units)) + int(labour[good])
	return prices[good]

## The chain price of a good, or for a category need (staple, fuel) the
## cheapest good that meets it.
func need_price(sim, need: String) -> int:
	if prices.has(need):
		return int(prices[need])
	var best := -1
	for good in sim.db.need_goods(need):
		if best < 0 or int(prices[good]) < best:
			best = int(prices[good])
	return maxi(0, best)

## What a storehouse charges households: the chain price plus the markup,
## never less than 1 s more (so cheap goods such as water keep a margin). A
## category need is priced at its cheapest good.
func retail_price(sim, good: String) -> int:
	var price := need_price(sim, good)
	if sim.markup_percent == 0:
		return price
	return price + maxi(1, (price * sim.markup_percent + 50) / 100)

## Only households pay the markup, and only when buying from a storehouse.
## Direct deliveries from a producer, and every workshop or storehouse
## purchase, are at the chain price.
func sale_price(sim, buyer, seller, good: String) -> int:
	if seller != null and buyer != null and seller.definition.kind == "storehouse" and buyer.definition.kind == "house":
		return retail_price(sim, good)
	return int(prices[good])

## A storehouse keeps enough silver to restock every good the village makes up
## to its per-good limit, and never less than PURSE_CAP. Only silver beyond
## that is a surplus for the treasury, so construction money paid to a
## storehouse with empty shelves goes on to buy from producers.
func purse_cap(sim, store) -> int:
	var limit := int(store.definition.get("good_limit", store.inventory.capacity))
	var made: Dictionary = {}
	for building in sim.buildings.values():
		for good in building.definition.outputs:
			made[good] = true
	var restock := 0
	for good in made:
		restock += maxi(0, limit - store.inventory.count(good)) * int(prices[good])
	return maxi(PURSE_CAP, restock)

## Public services ("service" in buildings.json, such as the forester) sell
## nothing; the treasury pays their workers at payday.
static func is_public(row: Dictionary) -> bool:
	return bool(row.get("service", false))

## A service's wages for one payday.
static func upkeep(row: Dictionary) -> int:
	return WAGE * int(row.workers) if is_public(row) else 0

## Working money the treasury hands a new building: a household's first purse,
## a storehouse's trading purse, or enough for a workshop to fill its inputs once.
func capital(sim, row: Dictionary) -> int:
	match row.kind:
		"house":
			return HOUSEHOLD_GRANT
		"storehouse":
			return STOREHOUSE_CAPITAL
		"producer":
			var total := 0
			for good in row.inputs:
				total += sim.input_buffer(row, good) * int(prices[good])
			return total
	return 0

## Founding supplies are free; materials taken from storehouses are bought.
func materials_price(sim, cost: Dictionary) -> int:
	var total := 0
	for good in cost:
		total += maxi(0, int(cost[good]) - sim.reserve.count(good)) * int(prices[good])
	return total

func construction_price(sim, row: Dictionary) -> int:
	return materials_price(sim, row.cost) + capital(sim, row)

## Treasury gold not set aside in either reserve.
static func free_gold(sim) -> int:
	return maxi(0, sim.treasury - sim.public_reserve - sim.capital_reserve)

## Construction may use the capital reserve and free gold, never public pay.
static func construction_funds(sim) -> int:
	return maxi(0, sim.treasury - sim.public_reserve)

## Public pay may use its reserve and free gold, never the capital reserve.
static func public_funds(sim) -> int:
	return maxi(0, sim.treasury - sim.capital_reserve)

## Construction draws on the capital reserve first, then free gold. Callers
## check construction_funds() first.
static func spend_on_construction(sim, amount: int) -> void:
	sim.capital_reserve -= mini(amount, sim.capital_reserve)
	sim.treasury -= amount
	sim.period.construction += amount

## Silver returned to the treasury, such as a demolished building's purse.
static func refund(sim, amount: int) -> void:
	sim.treasury += amount
	sim.period.refunds += amount

static func blank_period() -> Dictionary:
	var period := {}
	for key in LEDGER_KEYS:
		period[key] = 0
	return period

## Silver not already promised to deliveries on their way to this building.
func spendable(sim, building) -> int:
	var promised := 0
	for job in sim.jobs_to(building.uid):
		if job.seller != building.uid and sim.buildings.has(job.seller):
			promised += sale_price(sim, building, sim.buildings[job.seller], job.good)
	return building.silver - promised

## The buyer pays the seller on delivery. A producer passes the labour part of
## its price to the payroll and keeps the rest to buy its next inputs. A
## storehouse keeps the chain price, which restocks it, and passes a
## household's markup to the payroll as its carriers' wages. A faction-owned
## seller first gives its owner's share of that labour or markup to the owner.
func settle(sim, buyer, seller_uid: int, good: String) -> void:
	var seller = sim.buildings.get(seller_uid)
	if seller == null or seller == buyer:
		return
	var cost := sale_price(sim, buyer, seller, good)
	if buyer.silver < cost:
		return
	buyer.silver -= cost
	var work := 0
	if seller.definition.kind == "producer":
		work = mini(int(labour[good]), cost)
	elif seller.definition.kind == "storehouse":
		work = cost - int(prices[good])
	var share: int = sim.factions.take_owner_share(sim, seller, work)
	sim.payroll += work - share
	seller.wages_paid += work - share
	seller.silver += cost - work

## At payday, storehouse surpluses above the purse cap go to the treasury, or
## to the owner of a faction-owned storehouse, and
## the treasury pays public workers from the public pay reserve, then free gold.
## Unpaid public workers keep working, but each unpaid worker adds one to
## their frustration. The payroll is then shared between houses by the workers
## each provides, and tax is withheld into the treasury. The factions' payday
## runs last, before the period joins the ledger.
func payday(sim) -> void:
	var period: Dictionary = sim.period
	for building in sim.buildings.values():
		if building.definition.kind != "storehouse":
			continue
		var cap := purse_cap(sim, building)
		if building.silver > cap:
			var surplus: int = building.silver - cap
			building.silver = cap
			if sim.factions.present(building.owner):
				sim.factions.credit(building.owner, surplus, "owner_share")
			else:
				sim.treasury += surplus
				period.trade += surplus
	for building in sim.buildings.values():
		if not building.staffed or not is_public(building.definition):
			continue
		var due := upkeep(building.definition)
		var paid := mini(due, public_funds(sim))
		sim.public_reserve -= mini(paid, sim.public_reserve)
		sim.treasury -= paid
		sim.payroll += paid
		building.last_wage = paid
		period.public_pay += paid
		if paid < due:
			var unpaid_workers := ceili(float(due - paid) / WAGE)
			building.frustration += unpaid_workers
			sim.public_frustration += unpaid_workers
			period.unpaid += due - paid
	_pay_households(sim)
	_top_up_service_reserve(sim)
	sim.factions.payday(sim)
	sim.ledger.append(period)
	while sim.ledger.size() > LEDGER_PAYDAYS:
		sim.ledger.pop_front()
	sim.period = blank_period()

func _pay_households(sim) -> void:
	var houses: Array = []
	var workers := 0
	for building in sim.buildings.values():
		if building.definition.kind == "house":
			houses.append(building)
			workers += int(sim.db.tiers[building.tier].workers_per_house)
	if houses.is_empty():
		return
	var pool: int = sim.payroll
	var shares: Array[int] = []
	var spare := pool
	for house in houses:
		var share := pool * int(sim.db.tiers[house.tier].workers_per_house) / workers
		shares.append(share)
		spare -= share
	var offset: int = (sim.tick / sim.PAYDAY_TICKS) % houses.size()
	for index in spare:
		shares[(offset + index) % houses.size()] += 1
	sim.payroll = 0
	for index in houses.size():
		var house = houses[index]
		house.last_wage = shares[index]
		house.last_tax = house.last_wage * sim.tax_percent / 100
		house.silver += house.last_wage - house.last_tax
		sim.treasury += house.last_tax
		sim.taxes_collected += house.last_tax
		sim.period.tax += house.last_tax

static func format(silver: int) -> String:
	if silver < 0:
		return "−" + format(-silver)
	var gold := silver / SILVER_PER_GOLD
	var rest := silver % SILVER_PER_GOLD
	if gold == 0:
		return "%d s" % rest
	return "%d g" % gold if rest == 0 else "%d g %d s" % [gold, rest]

## When the player keeps services reserved, the public pay reserve is topped
## up from free gold to SERVICE_RESERVE_PAYDAYS of the services' upkeep. It
## runs after taxes, so a payday's income funds it first.
static func _top_up_service_reserve(sim) -> void:
	if not sim.keep_service_reserve:
		return
	var upkeep_due := 0
	for building in sim.buildings.values():
		upkeep_due += upkeep(building.definition)
	var short: int = SERVICE_RESERVE_PAYDAYS * upkeep_due - sim.public_reserve
	sim.public_reserve += clampi(short, 0, free_gold(sim))
