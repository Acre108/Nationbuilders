extends RefCounted
## The village's food balance (docs/WILDLIFE.md, "Food balance"): how much
## food its houses need each minute against how much it made and ate over the
## last WINDOW ticks. A meter instance samples the sim's running totals; it is
## presentation state, kept by the HUD and never saved, so it starts measuring
## afresh with a loaded village.
##
## Supply is matched to needs: berries feed only Settlers' basic food and bread
## only Villagers' staple, while fish and meat count for either, so they go
## to whichever need is still short. Producers idle only because storage
## holds enough still count as spare supply.
const Needs = preload("res://sim/needs.gd")
const FOOD_NEEDS := ["basic", "staple"]
const MINUTE := 600
const WINDOW := 1200
const STEP := 100
## Below this many measured ticks the rates are too noisy to judge.
const MIN_SPAN := 300
## With food short, stores lasting at least this many minutes keep the
## balance amber rather than red.
const STORE_MINUTES := 3.0
const IDLE_FOR_STORAGE := ["storehouse full"]
## Samples: {"tick", "made": {good: total}, "eaten": {good: total}}.
var samples: Array = []

## Goods that are food: any good in a food category, in goods.json order.
static func food_goods(db) -> Array:
	var result: Array = []
	for good in db.goods:
		for need in FOOD_NEEDS:
			if good in db.category_goods.get(need, []) and good not in result:
				result.append(good)
	return result

## Whether a tier need asks for food.
static func is_food_need(db, need: String) -> bool:
	return need in FOOD_NEEDS or need in food_goods(db)

## Records the sim's running totals every STEP ticks, keeping WINDOW ticks of
## history plus one older sample to measure from. A sim that went back in time
## (a restart or a load) starts a fresh history.
func sample(sim) -> void:
	if not samples.is_empty() and sim.tick < int(samples[-1].tick):
		samples.clear()
	if not samples.is_empty() and sim.tick - int(samples[-1].tick) < STEP:
		return
	samples.append(_totals(sim))
	while samples.size() > 2 and sim.tick - int(samples[1].tick) >= WINDOW:
		samples.pop_front()

func _totals(sim) -> Dictionary:
	var made := {}
	var eaten := {}
	for good in food_goods(sim.db):
		made[good] = int(sim.produced.get(good, 0))
		eaten[good] = int(sim._eaten.get(good, 0))
	return {"tick": sim.tick, "made": made, "eaten": eaten}

## The full balance for the HUD:
## - required, made, eaten, spare, stored: food per minute (stored is units),
##   and usable (usable_spare): made plus spare of food the houses eat now,
##   with minutes_stored at the required rate;
## - needs: per food need, its houses, the rate required and the rate supplied;
## - goods: per food good, made, eaten and stored, with its producers;
## - state: "measuring", "surplus", "stores" (short but living off stored
##   food) or "deficit".
func report(sim) -> Dictionary:
	var db = sim.db
	var goods: Array = food_goods(db)
	var now := _totals(sim)
	var base: Dictionary = samples[0] if not samples.is_empty() else now
	var span: int = int(now.tick) - int(base.tick)
	var result := {"span": span, "required": 0.0, "made": 0.0, "eaten": 0.0, "spare": 0.0, "usable": 0.0, "usable_spare": 0.0, "stored": 0, "needs": [], "goods": []}
	# What the houses need, per food need.
	var needs := {}
	for building in sim.buildings.values():
		if building.definition.kind != "house":
			continue
		var tier: Dictionary = db.tiers[building.tier]
		for need in tier.consumption:
			if not is_food_need(db, need):
				continue
			if not needs.has(need):
				needs[need] = {"need": need, "name": db.need_name(need), "goods": db.need_goods(need), "houses": 0, "tiers": [], "required": 0.0, "supplied": 0.0}
			var entry: Dictionary = needs[need]
			entry.houses += 1
			if tier.name not in entry.tiers:
				entry.tiers.append(tier.name)
			entry.required += float(tier.consumption[need]) * MINUTE / float(Needs.consume_ticks(sim, building))
	# What was made and eaten per good, and what producers could add.
	var rates := {}
	for good in goods:
		var made := 0.0
		var eaten := 0.0
		if span > 0:
			made = float(int(now.made[good]) - int(base.made.get(good, 0))) * MINUTE / span
			eaten = float(int(now.eaten[good]) - int(base.eaten.get(good, 0))) * MINUTE / span
		var row := {"good": good, "name": str(db.goods[good].name), "made": made, "eaten": eaten, "spare": 0.0, "stored": sim.stock(good), "sources": _sources(sim, good)}
		for source in row.sources:
			row.spare += float(source.spare)
		rates[good] = row
		result.goods.append(row)
		result.made += made
		result.eaten += eaten
		result.spare += row.spare
	# Each good's supply (made, plus spare capacity) goes to the needs it can
	# meet: first goods that meet only one need, then shared goods to whichever
	# need is still short, in tier order.
	var order: Array = needs.keys()
	var shared: Array = []
	for good in goods:
		var serves: Array = order.filter(func(need): return good in needs[need].goods)
		if serves.size() == 1:
			needs[serves[0]].supplied += rates[good].made + rates[good].spare
		elif serves.size() > 1:
			shared.append([good, serves])
	for entry in shared:
		var left: float = rates[entry[0]].made + rates[entry[0]].spare
		for need in entry[1]:
			var short: float = maxf(0.0, needs[need].required - needs[need].supplied)
			var given := minf(short, left)
			needs[need].supplied += given
			left -= given
	var short_total := 0.0
	for need in order:
		result.needs.append(needs[need])
		result.required += needs[need].required
		short_total += maxf(0.0, needs[need].required - needs[need].supplied)
	# Stored food and the headline supply count only food that meets a need the
	# houses have now: berries feed no one in a village of Villagers.
	for row in result.goods:
		if order.any(func(need): return row.good in needs[need].goods):
			result.stored += int(row.stored)
			result.usable += float(row.made) + float(row.spare)
			result.usable_spare += float(row.spare)
	result.minutes_stored = float(result.stored) / result.required if result.required > 0.0 else 0.0
	if span < MIN_SPAN:
		result.state = "measuring"
	elif short_total <= maxf(0.05, result.required * 0.05):
		result.state = "surplus"
	elif result.minutes_stored >= STORE_MINUTES:
		result.state = "stores"
	else:
		result.state = "deficit"
	result.short = short_total
	return result

## The buildings that make a good: their name, count, how many are working,
## why the rest are idle, and the food per minute they could add if idle only
## because storage already holds enough.
static func _sources(sim, good: String) -> Array:
	var by_id := {}
	for building in sim.buildings.values():
		var row: Dictionary = building.definition
		if row.kind != "producer" or not row.outputs.has(good):
			continue
		if not by_id.has(row.id):
			by_id[row.id] = {"id": row.id, "name": str(row.name), "count": 0, "working": 0, "idle": {}, "spare": 0.0}
		var entry: Dictionary = by_id[row.id]
		entry.count += 1
		var status: String = building.status
		if status == "working" or status.begins_with("hunting") or status.begins_with("gathering"):
			entry.working += 1
			continue
		entry.idle[status] = int(entry.idle.get(status, 0)) + 1
		if status in IDLE_FOR_STORAGE or status.begins_with("storehouse has enough"):
			entry.spare += float(row.outputs[good]) * MINUTE / float(sim.cycle_ticks(building))
	return by_id.values()
