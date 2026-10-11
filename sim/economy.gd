extends RefCounted
## Village money, held in whole silver; 100 silver make a gold. Every link in a
## chain pays the one before it, so a good costs its inputs plus the labour of
## the building that made it. A producer forwards that labour to the payroll,
## which households share at payday. The treasury is filled only by tax on
## those wages, and spends gold on construction and public workers.
## Money is closed: treasury, payroll and every building's silver always sum to
## the founding treasury.
const SILVER_PER_GOLD := 100
## One worker's labour for one payday, in silver.
const WAGE := 10
const FOUNDING_TREASURY := 1000
const DEFAULT_TAX_PERCENT := 10
## Starting money the treasury gives a new household or storehouse.
const HOUSEHOLD_GRANT := 50
const STOREHOUSE_CAPITAL := 100

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

## Silver not already promised to deliveries on their way to this building.
func spendable(sim, building) -> int:
	var promised := 0
	for carrier in sim.carriers:
		var job: Dictionary = carrier.job
		if job.get("target") == building.uid and job.get("seller", -1) != building.uid and sim.buildings.has(job.get("seller", -1)):
			promised += int(prices[job.good])
	return building.silver - promised

## The buyer pays the seller on delivery. A producer passes the labour part of
## its price to the payroll and keeps the rest to buy its next inputs.
func settle(sim, buyer, seller_uid: int, good: String) -> void:
	var seller = sim.buildings.get(seller_uid)
	var cost := int(prices[good])
	if seller == null or seller == buyer or buyer.silver < cost:
		return
	buyer.silver -= cost
	if seller.definition.kind == "producer":
		var work := mini(int(labour[good]), cost)
		sim.payroll += work
		seller.silver += cost - work
	else:
		seller.silver += cost

## The treasury pays public workers (buildings that sell nothing, such as the
## forester). The payroll is then shared between houses by the workers each
## provides, and tax is withheld into the treasury.
func payday(sim) -> void:
	for building in sim.buildings.values():
		if building.definition.kind == "producer" and building.staffed and building.definition.outputs.is_empty():
			var due := mini(WAGE * int(building.definition.workers), sim.treasury)
			sim.treasury -= due
			sim.payroll += due
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

static func format(silver: int) -> String:
	var gold := silver / SILVER_PER_GOLD
	var rest := silver % SILVER_PER_GOLD
	if gold == 0:
		return "%d s" % rest
	return "%d g" % gold if rest == 0 else "%d g %d s" % [gold, rest]
