extends RefCounted
const DB = preload("res://sim/content_db.gd")

func run(t) -> void:
	var db = DB.new()
	t.check(db.load_directory(), "Shipped content validates")
	var goods: Array = db.goods.values().duplicate(true)
	var buildings: Array = db.buildings.values().duplicate(true)
	var tiers: Array = db.tiers.values().duplicate(true)
	buildings[2].inputs = {"unobtainium":1}
	t.check(not db.validate(goods, buildings, tiers), "Reject unknown good in recipe")
	t.check("unknown good unobtainium" in "; ".join(db.errors), "Unknown id has actionable diagnostic")
	buildings[2].inputs = {}
	buildings[2].cycle_ticks = 0
	t.check(not db.validate(goods, buildings, tiers), "Reject zero production cycle")
	buildings[2].cycle_ticks = 20
	buildings[2].outputs = {"wheat":7}
	t.check(not db.validate(goods, buildings, tiers), "Reject recipe larger than local capacity")
	buildings[2].outputs = {"wheat":1}
	goods.append(goods[0].duplicate())
	t.check(not db.validate(goods, buildings, tiers), "Reject duplicate content ids")
	t.check(not db.validate({}, [], []), "Reject malformed root and absent tiers")
	db.load_directory()
	goods = db.goods.values().duplicate(true)
	buildings = db.buildings.values().duplicate(true)
	tiers = db.tiers.values().duplicate(true)
	buildings[2].outputs = 42
	buildings[2].cycle_ticks = "broken"
	t.check(not db.validate(goods,buildings,tiers), "Malformed recipe types return diagnostics without crashing")
