extends SceneTree
## Runs the economy test village (Scenario.economy_test, docs/VILLAGERS.md
## §5.7) headless and prints its money and goods once per minute, then a
## summary and a findings list. Headless:
##   Godot.exe --headless --path . --script tools/economy_village.gd -- [--minutes=30] [--seed=73]
##       [--tax=PERCENT] [--store-pay=low|normal|high] [--no-reserve] [--halls] [--every=N] [--data=res://data]
## --store-pay sets every storehouse's pay, and so its markup; --no-reserve stops
## keeping two paydays of services reserved; --halls adds the union
## hall and alehouse; --data loads content from another directory.
const Sim = preload("res://sim/village_sim.gd")
const Scenario = preload("res://sim/scenario.gd")
const Economy = preload("res://sim/economy.gd")
const Needs = preload("res://sim/needs.gd")
const ContentDB = preload("res://sim/content_db.gd")
const TICKS_PER_MINUTE := 600

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var minutes := 30
	var seed_value := 73
	var every := 1
	var data := "res://data"
	var args := OS.get_cmdline_user_args()
	for argument in args:
		if argument.begins_with("--minutes="): minutes = int(argument.get_slice("=", 1))
		elif argument.begins_with("--seed="): seed_value = int(argument.get_slice("=", 1))
		elif argument.begins_with("--every="): every = maxi(1, int(argument.get_slice("=", 1)))
		elif argument.begins_with("--data="): data = argument.get_slice("=", 1)
	var db = ContentDB.new()
	if not db.load_directory(data):
		printerr("Content in %s is invalid" % data)
		quit(1)
		return
	var sim = Sim.new(seed_value, db)
	if not Scenario.economy_test(sim, "--halls" in args):
		printerr("Economy village failed: " + sim.last_error)
		quit(1)
		return
	for argument in args:
		if argument.begins_with("--tax=") and not sim.set_tax_percent(int(argument.get_slice("=", 1))): printerr(sim.last_error)
		elif argument.begins_with("--store-pay="):
			var level: int = ["low", "normal", "high"].find(argument.get_slice("=", 1))
			for building in sim.buildings.values():
				if building.definition.kind == "storehouse" and not sim.set_pay(building.uid, level): printerr(sim.last_error)
	if "--no-reserve" in args: sim.set_keep_service_reserve(false)
	var initial_goods := {}
	for good in sim.db.goods: initial_goods[good] = sim.stock(good)
	print("Economy village: %d buildings, %d houses, %d jobs + %d carriers for %d workers; tax %d%%, average markup %d%%; treasury after building %s" % [sim.buildings.size(), _count(sim, "house"), _jobs(sim), _carriers(sim), sim.workforce(), sim.tax_percent, sim.average_markup(), Economy.format(sim.treasury)])
	print("Money per minute is summed over its three paydays. Purses are household savings: mean / lowest.")
	print("min | T1 T2 happy morale idle | treasury  pub    | tax  trade pubpay unpaid build | wages/house | purse mean/low | stores        | " + " ".join(_goods(sim).map(func(good): return good.left(5).rpad(5))))
	var totals := _blank()
	var minute_totals := _blank()
	var findings: Array[String] = []
	var lowest_treasury: int = sim.treasury
	var stockouts := {}
	var demotions := 0
	var needs := _needs(sim)
	for minute in range(1, minutes + 1):
		while sim.tick < minute * TICKS_PER_MINUTE:
			var events_before: int = sim.events.size()
			sim.step(1)
			for index in range(events_before, sim.events.size()):
				if "returned to" in sim.events[index]: demotions += 1
			if sim.tick % sim.PAYDAY_TICKS == 0 and not sim.ledger.is_empty():
				for key in sim.ledger.back(): minute_totals[key] += int(sim.ledger.back()[key])
				lowest_treasury = mini(lowest_treasury, sim.treasury)
			if sim.tick % 50 == 0:
				for need in needs:
					if _need_stock(sim, needs[need]) == 0: stockouts[need] = int(stockouts.get(need, 0)) + 1
		if minute % every == 0 or minute == minutes:
			print(_row(sim, minute, minute_totals))
		for key in minute_totals: totals[key] += minute_totals[key]
		minute_totals = _blank()
	_summary(sim, minutes, totals, initial_goods)
	# Findings: what a balance pass should look at.
	var tiers := _tiers(sim)
	if tiers[1] > 0: findings.append("%d of %d houses are still Settlers" % [tiers[1], _count(sim, "house")])
	if demotions > 0: findings.append("%d demotions back to Settlers" % demotions)
	var net: int = totals.tax + totals.trade + totals.deals - totals.public_pay
	if totals.unpaid > 0: findings.append("Public workers went unpaid: %s in all; frustration %d" % [Economy.format(totals.unpaid), sim.public_frustration])
	if net < 0: findings.append("The treasury loses %s a minute: income %s against public pay %s" % [Economy.format(-net / minutes), Economy.format((totals.tax + totals.trade + totals.deals) / minutes), Economy.format(totals.public_pay / minutes)])
	findings.append("Lowest treasury after a payday: %s" % Economy.format(lowest_treasury))
	for need in stockouts:
		findings.append("Village stock for the %s need was empty in %d%% of samples" % [need, 100 * int(stockouts[need]) / maxi(1, minutes * TICKS_PER_MINUTE / 50)])
	for building in sim.buildings.values():
		if building.definition.kind == "storehouse":
			findings.append("Storehouse at %s holds %s (purse cap %s)" % [building.cell - Scenario.offset(sim), Economy.format(building.silver), Economy.format(sim.economy.purse_cap(sim, building))])
	for building in sim.buildings.values():
		if building.definition.kind == "house" and not building.needs_ok:
			findings.append("House at %s: %s" % [building.cell - Scenario.offset(sim), building.status])
		elif building.definition.kind == "producer" and not building.staffed:
			findings.append("%s at %s is unstaffed" % [building.definition.name, building.cell - Scenario.offset(sim)])
	var money: int = sim.treasury + sim.payroll + sim.factions.total()
	for building in sim.buildings.values(): money += building.silver
	if money != Economy.FOUNDING_TREASURY + sim.outside_money:
		findings.append("MONEY LEAK: %d silver held, %d expected" % [money, Economy.FOUNDING_TREASURY + sim.outside_money])
	print("\n== FINDINGS ==")
	for line in findings: print("- " + line)
	quit(0)

func _row(sim, minute: int, money: Dictionary) -> String:
	var tiers := _tiers(sim)
	var happiness := 0
	var houses := 0
	var wages := 0
	var purses := 0
	var lowest := 1 << 30
	for building in sim.buildings.values():
		if building.definition.kind != "house": continue
		houses += 1
		happiness += building.happiness
		wages += building.last_wage
		purses += building.silver
		lowest = mini(lowest, building.silver)
	var stock: Array = _goods(sim).map(func(good): return str(sim.stock(good)).lpad(5))
	var stores: Array = sim.buildings.values().filter(func(building): return building.definition.kind == "storehouse").map(func(store): return Economy.format(store.silver))
	return "%3d | %2d %2d %4d%% %5d%% %4d | %-9s %-6s | %4s %5s %6s %6s %5s | %11s | %6s / %-6s | %-13s | %s" % [minute, tiers[1], tiers[2], happiness / maxi(1, houses), Needs.morale(sim), sim.idle_workers, Economy.format(sim.treasury), Economy.format(sim.public_reserve), _s(money.tax), _s(money.trade), _s(money.public_pay), _s(money.unpaid), _s(money.construction), Economy.format(wages / maxi(1, houses)), Economy.format(purses / maxi(1, houses)), Economy.format(lowest), " ".join(stores), " ".join(stock)]

func _summary(sim, minutes: int, totals: Dictionary, initial_goods: Dictionary) -> void:
	print("\n== PER MINUTE, AVERAGED OVER %d MINUTES ==" % minutes)
	print("treasury income: tax %s, trade %s, deals %s; spending: public pay %s, construction %s" % [Economy.format(totals.tax / minutes), Economy.format(totals.trade / minutes), Economy.format(totals.deals / minutes), Economy.format(totals.public_pay / minutes), Economy.format(totals.construction / minutes)])
	print("good      made  eaten   price retail  stock (start)")
	for good in _goods(sim):
		print("%-8s %5.1f  %5.1f  %5s %6s  %5d (%d)" % [good, float(sim.produced.get(good, 0)) / minutes, float(sim.consumed.get(good, 0)) / minutes, Economy.format(int(sim.economy.prices[good])), Economy.format(sim.economy.retail_price(sim, good)), sim.stock(good), int(initial_goods[good])])
	var statuses := {}
	for building in sim.buildings.values():
		if building.definition.kind == "producer":
			var key: String = "%s: %s" % [building.definition.name, building.status]
			statuses[key] = int(statuses.get(key, 0)) + 1
	print("workplaces now: " + ", ".join(statuses.keys().map(func(key): return "%s ×%d" % [key, statuses[key]])))
	if not sim.factions.coffers.is_empty():
		print("factions: " + ", ".join(sim.factions.coffers.keys().map(func(id): return "%s %s" % [id, Economy.format(int(sim.factions.coffers[id]))])))

func _blank() -> Dictionary:
	var result := Economy.blank_period()
	return result

## Goods the village makes or eats, in content order.
func _goods(sim) -> Array:
	return sim.db.goods.keys().filter(func(good): return sim.produced.has(good) or sim.consumed.has(good) or _made(sim, good))

func _made(sim, good: String) -> bool:
	for building in sim.buildings.values():
		if building.definition.outputs.has(good): return true
	return false

## Each need some tier eats, with the goods that meet it: a need naming a
## category (staple, fuel) is met by any of its goods.
func _needs(sim) -> Dictionary:
	var result := {}
	for tier in sim.db.tiers.values():
		for need in tier.consumption:
			result[need] = sim.db.category_goods.get(need, [need])
	return result

## The village's stock of the goods that meet a need.
func _need_stock(sim, goods: Array) -> int:
	var total := 0
	for good in goods: total += sim.stock(good)
	return total

func _tiers(sim) -> Dictionary:
	var result := {1: 0, 2: 0}
	for building in sim.buildings.values():
		if building.definition.kind == "house": result[building.tier] = int(result.get(building.tier, 0)) + 1
	return result

func _count(sim, kind: String) -> int:
	return sim.buildings.values().filter(func(building): return building.definition.kind == kind).size()

func _jobs(sim) -> int:
	var total := 0
	for building in sim.buildings.values():
		if building.definition.kind == "producer": total += int(building.definition.workers)
	return total

func _carriers(sim) -> int:
	var total := 0
	for building in sim.buildings.values():
		if building.definition.kind == "storehouse": total += int(building.definition.carriers)
	return total

func _s(silver: int) -> String:
	return str(silver)
