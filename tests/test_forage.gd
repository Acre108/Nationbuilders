extends RefCounted
## Natural food besides game: wild berries in the woods (sim/forage.gd), and
## fields that work best on fertile soil (village_sim.deposit_speed).
const Sim = preload("res://sim/village_sim.gd")
const Forage = preload("res://sim/forage.gd")
const WildlifeTests = preload("res://tests/test_wildlife.gd")

func run(t) -> void:
	_bushes(t)
	_forager(t)
	_snapshot(t)
	_fertility(t)

## The wildlife fixture: a wood (x 0–9) beside open meadow.
func _sim():
	return Sim.new(73, null, WildlifeTests.new()._site())

func _bushes(t) -> void:
	var sim = _sim()
	var bushes: Dictionary = sim.forage.bushes
	t.check(bushes.size() > 5, "The wood holds wild berry bushes: %d" % bushes.size())
	var under_canopy := true
	for cell in bushes:
		under_canopy = under_canopy and Forage.suits(sim.grid, cell) and cell.x <= 10 and int(bushes[cell]) == Forage.MAX_FRUIT
	t.check(under_canopy, "Bushes grow only under the canopy, and start ripe")
	# Fruit ripens one per REGROW_TICKS, up to MAX_FRUIT.
	var cell: Vector2i = bushes.keys()[0]
	bushes[cell] = 0
	sim.step(Forage.REGROW_TICKS)
	t.check(int(bushes[cell]) == 1, "Picked fruit ripens again over time")
	sim.step(Forage.REGROW_TICKS * 4)
	t.check(int(bushes[cell]) == Forage.MAX_FRUIT, "A bush holds at most %d fruit" % Forage.MAX_FRUIT)
	# Felling the trees around a bush withers it; so does building over it.
	for direction in sim.grid.DIRECTIONS:
		sim.grid.clear_tree(cell + direction, true)
	sim.step(1)
	t.check(not bushes.has(cell), "A bush withers once the trees around it are felled")
	var other: Vector2i = bushes.keys()[0]
	sim.place_road([other])
	sim.step(1)
	t.check(not bushes.has(other), "A road over a bush destroys it")

func _forager(t) -> void:
	var sim = _sim()
	t.check(sim.place_road([Vector2i(12, 9), Vector2i(13, 9)]) and sim.place("forager", Vector2i(12, 10)), "Place a forager's hut at the wood's edge: %s" % sim.last_error)
	var hut = null
	for building in sim.buildings.values():
		hut = building
	var ripe: int = sim.forage.ripe()
	sim.step(int(hut.definition.cycle_ticks) * 3 + 2)
	t.check(hut.status == "gathering wild berries" and int(sim.produced.get("berries", 0)) == 3 and sim.forage.ripe() == ripe - 3, "Each cycle picks one fruit: %s, %d berries" % [hut.status, int(sim.produced.get("berries", 0))])
	# Nothing ripe in reach: the hut waits and says why.
	for cell in sim.forage.bushes:
		sim.forage.bushes[cell] = 0
	hut.output.take("berries", hut.output.count("berries"))
	sim.step(1)
	t.check(hut.status == "no ripe berries nearby" and hut.progress == 0, "With no ripe berries in reach the forager waits: %s" % hut.status)
	var far := Vector2i(-1, -1)
	for cell in sim.forage.bushes:
		if Vector2(cell).distance_to(Vector2(13, 11)) > float(hut.definition.work_radius) + 1.0:
			far = cell
	if far.x >= 0:
		sim.forage.bushes[far] = 2
		sim.step(1)
		t.check(hut.status == "no ripe berries nearby", "Berries beyond the work radius are out of reach")

func _snapshot(t) -> void:
	var sim = _sim()
	sim.place_road([Vector2i(12, 9), Vector2i(13, 9)])
	sim.place("forager", Vector2i(12, 10))
	sim.step(Forage.REGROW_TICKS + 130)
	var state: Dictionary = sim.snapshot()
	var restored = Sim.from_snapshot(state, sim.db)
	t.check(restored != null and JSON.stringify(restored.snapshot()) == JSON.stringify(state), "Wild berries round-trip through a snapshot")
	if restored != null:
		sim.step(Forage.REGROW_TICKS * 2)
		restored.step(Forage.REGROW_TICKS * 2)
		t.check(JSON.stringify(restored.snapshot()) == JSON.stringify(sim.snapshot()), "A restored village's berries continue identically")
	var bad: Dictionary = state.duplicate(true)
	bad.forage[0][2] = Forage.MAX_FRUIT + 1
	t.check(Sim.from_snapshot(bad, sim.db) == null, "Reject an overripe bush")
	bad = state.duplicate(true)
	bad.forage.append(bad.forage[0].duplicate())
	t.check(Sim.from_snapshot(bad, sim.db) == null, "Reject two bushes on one tile")

## A wheat field works at full speed on fertile soil, half speed off it, and
## in proportion when partly on it.
func _fertility(t) -> void:
	var sim = _sim()
	var row: Dictionary = sim.db.buildings.farm
	var width: int = sim.grid.width
	for y in range(20, 22):
		for x in range(20, 26):
			sim.grid.deposits[y * width + x] = "fertile_soil"
	t.check(sim.deposit_speed(row, Vector2i(20, 20)) == 100, "A field wholly on fertile soil works at full speed")
	t.check(sim.deposit_speed(row, Vector2i(30, 20)) == int(row.off_deposit_percent), "A field off fertile soil works at %d%%" % int(row.off_deposit_percent))
	t.check(sim.deposit_speed(row, Vector2i(24, 20)) == 83, "A field two-thirds on fertile soil works at 83%%: %d" % sim.deposit_speed(row, Vector2i(24, 20)))
	t.check(sim.deposit_speed(sim.db.buildings.well, Vector2i(30, 20)) == 100, "Buildings without a deposit rule always work at full speed")
	t.check(sim.place("farm", Vector2i(20, 20)) and sim.place("farm", Vector2i(30, 20)), "Place a field on and off fertile soil")
	var fields: Array = []
	for building in sim.buildings.values():
		fields.append(building)
	t.check(sim.cycle_ticks(fields[0]) == int(row.cycle_ticks) and sim.cycle_ticks(fields[1]) == int(row.cycle_ticks) * 100 / int(row.off_deposit_percent), "Cycle lengths follow the soil: %d and %d ticks" % [sim.cycle_ticks(fields[0]), sim.cycle_ticks(fields[1])])
	sim.step(int(row.cycle_ticks) * 4)
	t.check(fields[0].output.count("wheat") == 4 and fields[1].output.count("wheat") == 2, "Fertile soil yields twice the wheat: %d and %d" % [fields[0].output.count("wheat"), fields[1].output.count("wheat")])
	var db = sim.db
	var rows: Array = db.buildings.values().duplicate(true)
	for entry in rows:
		if entry.id == "farm": entry.off_deposit_percent = 0
	t.check(not db.validate(db.goods.values().duplicate(true), rows, db.tiers.values().duplicate(true)) and "off_deposit_percent" in "; ".join(db.errors), "Reject a field that never works off its deposit")
	db.load_directory()
	# The default site has fertile patches beyond its tilled clearing.
	var village = Sim.new(73)
	var outside := 0
	for index in village.grid.deposits.size():
		var cell := Vector2i(index % village.grid.width, index / village.grid.width)
		if village.grid.deposits[index] == "fertile_soil" and not village.site.settlement_clearance.has_point(cell):
			outside += 1
	t.check(outside > 200, "The default site has fertile meadow patches outside the clearing: %d tiles" % outside)
